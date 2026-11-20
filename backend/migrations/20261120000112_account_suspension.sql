-- Make "we may suspend your account" something the database enforces.
--
-- The Terms promise suspension and the moderation function could record
-- a decision, but nothing could act on one: a reported account kept
-- posting, messaging and turning up in search exactly as before.
--
-- Accounts are third-party identities (Rork JWTs; `auth.users` is
-- empty), so there is no auth-side switch to flip and a suspended person
-- keeps a perfectly valid token. The only place a suspension can mean
-- anything is where every request already lands: row-level security.
--
-- A separate table rather than a `profiles.suspended_at` column, for two
-- reasons that both come from how `profiles` is already set up:
--
--   * Members may UPDATE their own profile row, and that policy is not
--     column-scoped. A flag on that row is a flag its subject can clear.
--   * Column-level SELECT on `profiles` is an explicit allow-list
--     (20260906000001), so the client could not read a new column
--     without widening that grant for everyone.
--
-- Here the only writer is the service role (the `moderation` edge
-- function), and the only thing a member can read is their own row —
-- which is what lets the app say "your account is suspended" instead of
-- failing every write with no explanation.

create table if not exists public.suspensions (
  user_id text primary key references public.profiles(id) on delete cascade,
  -- Shown to the suspended person, so it is written for them. The
  -- moderator's own note and identity live in `moderation_actions`,
  -- which no member can read.
  reason text,
  created_at timestamptz not null default now()
);

alter table public.suspensions enable row level security;

revoke all on public.suspensions from anon;
revoke all on public.suspensions from authenticated;
grant select on public.suspensions to authenticated;
grant all on public.suspensions to service_role;

drop policy if exists "Read my own suspension" on public.suspensions;
create policy "Read my own suspension" on public.suspensions
  for select
  using (user_id = public.user_id());

-- The helper every policy below calls. SECURITY DEFINER because the
-- caller can only see their own suspension row and these checks are
-- frequently about someone else (is the AUTHOR of this story
-- suspended?). STABLE, like the other policy helpers: it only reads, and
-- the table it reads is a primary-key lookup on a handful of rows.
--
-- EXECUTE is left at the default, like the other helpers used inside
-- policies (is_blocked, are_friends, is_circle_member — see the note in
-- 20260906000012): a policy is evaluated as whichever role runs the
-- query, and revoking PUBLIC would turn "no rows" into "permission
-- denied" for that role.
create or replace function public.is_suspended(p_user_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from public.suspensions s where s.user_id = p_user_id
  );
$function$;

-- 1. A suspended account cannot create anything other people see ------
--
-- RESTRICTIVE policies are ANDed with whatever permissive policies a
-- table already has, so this adds one condition to every insert path
-- without restating — and risking drift from — the rules already there.
-- The service role bypasses RLS and is unaffected.

do $$
declare
  t text;
begin
  foreach t in array array[
    'story_posts',
    'story_comments',
    'story_likes',
    'direct_messages',
    'cheers',
    'golden_hour_posts',
    'circles',
    'circle_members',
    'circle_invitations',
    'circle_join_requests',
    'circle_events',
    'circle_tasks',
    'friend_requests',
    'friendships',
    'pacts',
    'focus_blocks'
  ]
  loop
    execute format('drop policy if exists "Suspended accounts cannot create" on public.%I', t);
    execute format(
      'create policy "Suspended accounts cannot create" on public.%I as restrictive for insert with check (not public.is_suspended(public.user_id()))',
      t
    );
  end loop;
end $$;

-- Circles carry text strangers can read in Discover (name, description),
-- and so do their events and shared tasks. Creating is blocked above;
-- this stops a suspended owner or admin rewriting what already exists.
do $$
declare
  t text;
begin
  foreach t in array array['circles', 'circle_events', 'circle_tasks']
  loop
    execute format('drop policy if exists "Suspended accounts cannot edit" on public.%I', t);
    execute format(
      'create policy "Suspended accounts cannot edit" on public.%I as restrictive for update using (not public.is_suspended(public.user_id()))',
      t
    );
  end loop;
end $$;

-- Uploads to the buckets other people read from. Private buckets (notes,
-- the proof library) are deliberately left alone: a suspension takes
-- away the social surface, not someone's own journal.
drop policy if exists "Suspended accounts cannot upload shared media" on storage.objects;
create policy "Suspended accounts cannot upload shared media" on storage.objects
  as restrictive
  for insert
  with check (
    bucket_id not in ('stories', 'golden-hour', 'proofs', 'avatars')
    or not public.is_suspended(public.user_id())
  );

-- 2. What a suspended account already posted stops being served --------
--
-- The author still sees their own rows (so the app does not look
-- corrupted to them, and so an appeal can refer to something); everyone
-- else stops. Lifting the suspension brings it all back — nothing is
-- deleted here. Removing a specific item is a separate moderation
-- action.

drop policy if exists "Hide stories from suspended accounts" on public.story_posts;
create policy "Hide stories from suspended accounts" on public.story_posts
  as restrictive
  for select
  using (author_id = public.user_id() or not public.is_suspended(author_id));

drop policy if exists "Hide comments from suspended accounts" on public.story_comments;
create policy "Hide comments from suspended accounts" on public.story_comments
  as restrictive
  for select
  using (user_id = public.user_id() or not public.is_suspended(user_id));

drop policy if exists "Hide captures from suspended accounts" on public.golden_hour_posts;
create policy "Hide captures from suspended accounts" on public.golden_hour_posts
  as restrictive
  for select
  using (user_id = public.user_id() or not public.is_suspended(user_id));

-- can_see_story gates likes, comments and views on a post, and as a
-- SECURITY DEFINER function it does not pass through the policy above.
-- Same body as 20260906000002 with the one added condition.
create or replace function public.can_see_story(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  SELECT EXISTS (
    SELECT 1 FROM story_posts p
    WHERE p.id = p_post_id
      AND (
        p.author_id = user_id()
        OR (
          NOT is_blocked(p.author_id)
          AND NOT is_suspended(p.author_id)
          AND (
            (p.circle_id IS NOT NULL AND is_circle_member(p.circle_id))
            OR (p.circle_id IS NULL AND are_friends(p.author_id))
          )
        )
      )
  );
$function$;

-- 3. A suspended account is not discoverable ---------------------------
--
-- The discovery RPCs, each re-stated from its current definition
-- (20260906000011, and the live `search_people` / `filter_not_blocked`)
-- with one added filter.
-- CREATE OR REPLACE keeps the existing EXECUTE grants from
-- 20260906000012.

create or replace function public.search_people(q text)
returns table(id text, name text, username text, avatar_url text, header_url text)
language sql
stable
security definer
set search_path to 'public'
as $function$
  SELECT p.id, p.name, p.username, p.avatar_url, p.header_url
  FROM profiles p
  WHERE user_id() IS NOT NULL
    AND length(btrim(q)) >= 2
    AND p.id <> user_id()
    AND COALESCE(p.is_test, false) = false
    AND NOT is_blocked(p.id)
    AND NOT is_suspended(p.id)
    AND (
      p.name ILIKE '%' || btrim(q) || '%'
      OR p.username ILIKE '%' || ltrim(btrim(q), '@') || '%'
      OR (position('@' in btrim(q)) > 1 AND lower(p.email) = lower(btrim(q)))
    )
  ORDER BY (lower(COALESCE(p.username, '')) = lower(ltrim(btrim(q), '@'))) DESC,
           p.name NULLS LAST
  LIMIT 20;
$function$;

create or replace function public.discover_public_circles(search text default null::text)
returns table(
  id uuid, name text, type text, timeframe_kind text,
  end_date timestamp with time zone, collective_unit text,
  collective_target double precision, description text, join_rule text,
  member_count bigint, created_at timestamp with time zone
)
language sql
security definer
set search_path to 'public'
as $function$
  SELECT c.id, c.name, c.type, c.timeframe_kind, c.end_date,
         c.collective_unit, c.collective_target, c.description, c.join_rule,
         (SELECT count(*) FROM circle_members m WHERE m.circle_id = c.id) AS member_count,
         c.created_at
  FROM circles c
  WHERE c.visibility = 'public'
    AND NOT EXISTS (
      SELECT 1 FROM circle_members m2
      WHERE m2.circle_id = c.id AND m2.user_id = user_id()
    )
    -- A circle is only as real as the person running it.
    AND NOT EXISTS (
      SELECT 1 FROM profiles owner
      WHERE owner.id = c.owner_id AND coalesce(owner.is_test, false)
    )
    -- ...and only as welcome as they are.
    AND NOT is_suspended(c.owner_id)
    AND (c.end_date IS NULL OR c.end_date > now())
    AND (
      search IS NULL OR btrim(search) = ''
      OR c.name ILIKE '%' || btrim(search) || '%'
      OR coalesce(c.description, '') ILIKE '%' || btrim(search) || '%'
    )
  ORDER BY c.created_at DESC
  LIMIT 50;
$function$;

-- The suggestion lists ("people you may know", "near you") read
-- `profiles` directly and then pass their candidates through this RPC to
-- drop anyone with a block in either direction. It is the one server-side
-- gate those lists already go through, so it is where a suspended
-- account is dropped from them too — with no client change. Same body as
-- the live function plus the last condition.
create or replace function public.filter_not_blocked(candidate_ids text[])
returns text[]
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(array_agg(cid), '{}'::text[])
  from unnest(candidate_ids) as cid
  where not exists (
    select 1 from blocks b
    where (b.blocker_id = cid and b.blocked_id = user_id())
       or (b.blocker_id = user_id() and b.blocked_id = cid)
  )
  and not is_suspended(cid);
$function$;

create or replace function public.match_contacts(p_emails text[], p_phone_hashes text[])
returns setof text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select p.id from profiles p
  where user_id() is not null
    and coalesce(p.is_test, false) = false
    and not is_suspended(p.id)
    and p.email is not null
    and lower(p.email) in (select lower(e) from unnest(coalesce(p_emails, '{}'::text[])) e)
  union
  select ck.user_id from contact_keys ck
  join profiles cp on cp.id = ck.user_id
  where user_id() is not null
    and coalesce(cp.is_test, false) = false
    and not is_suspended(cp.id)
    and ck.phone_hash is not null
    and ck.phone_hash in (select h from unnest(coalesce(p_phone_hashes, '{}'::text[])) h)
$function$;

create or replace function public.match_contact_keys(p_emails text[], p_phone_hashes text[])
returns table(profile_id text, matched_email text, matched_phone_hash text)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select p.id, lower(p.email), null::text
  from profiles p
  where user_id() is not null
    and coalesce(p.is_test, false) = false
    and not is_suspended(p.id)
    and p.email is not null
    and lower(p.email) in (select lower(e) from unnest(coalesce(p_emails, '{}'::text[])) e)
  union
  select ck.user_id, null::text, ck.phone_hash
  from contact_keys ck
  join profiles cp on cp.id = ck.user_id
  where user_id() is not null
    and coalesce(cp.is_test, false) = false
    and not is_suspended(cp.id)
    and ck.phone_hash is not null
    and ck.phone_hash in (select h from unnest(coalesce(p_phone_hashes, '{}'::text[])) h)
$function$;
