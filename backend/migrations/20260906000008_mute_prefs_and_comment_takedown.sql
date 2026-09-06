-- Social Tier 2 foundations: mute, per-kind notification control, and
-- comment takedown by the person whose story it is.

-- 1. Mute ------------------------------------------------------------
--
-- The only tools for an unwanted person were unfriend and block: both
-- loud, both severing, both visible in their consequences. There was no
-- way to simply turn the volume down, which is the thing people actually
-- reach for, so the app pushed every mild annoyance toward a nuclear
-- option.
--
-- Mute is deliberately NOT a permission. It never appears in
-- can_see_story: blocking is the wall, and folding mute into the same
-- check would make a quiet personal preference behave like one, hiding
-- content even when the person deliberately opens a profile. It filters
-- the feed and suppresses pushes; nothing more, and the muted person is
-- never told.

create table if not exists public.mutes (
  muter_id text not null,
  muted_id text not null,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  constraint mutes_no_self check (muter_id <> muted_id)
);

alter table public.mutes enable row level security;

-- Only ever your own list, in both directions: a person must not be able
-- to discover that someone muted them.
create policy "Own mutes" on public.mutes
  for all
  using (muter_id = public.user_id())
  with check (muter_id = public.user_id());

create index if not exists mutes_muter_idx on public.mutes (muter_id);

create or replace function public.is_muted(other_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from public.mutes m
    where m.muter_id = public.user_id() and m.muted_id = other_id
  );
$function$;

revoke execute on function public.is_muted(text) from anon;

-- 2. Per-kind notification preferences --------------------------------
--
-- Reminder settings covered only the four locally-built reminders, so
-- none of the seventeen social push kinds could be turned off
-- individually. Someone who wanted friend requests but not story-likes
-- had exactly one lever: switch notifications off at the OS level, which
-- loses the channel permanently.
--
-- Stored as the DISABLED set so the default — no row, empty array — is
-- "everything on", and a kind added later is on for existing accounts
-- without a backfill.

create table if not exists public.notification_preferences (
  user_id text primary key,
  disabled_kinds text[] not null default '{}',
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

create policy "Own notification preferences" on public.notification_preferences
  for all
  using (user_id = public.user_id())
  with check (user_id = public.user_id());

-- 3. Comment takedown --------------------------------------------------
--
-- "Delete my comments" already let an author remove their own. What was
-- missing is the other half: the person whose story it is could not take
-- an unwanted comment off their own post. Report and block existed, but
-- neither removes the content, so the only remedy left it in place.

drop policy if exists "Delete my comments" on public.story_comments;

create policy "Delete my comment, or any on my story" on public.story_comments
  for delete
  using (
    user_id = public.user_id()
    or exists (
      select 1 from public.story_posts p
      where p.id = story_comments.post_id
        and p.author_id = public.user_id()
    )
  );
