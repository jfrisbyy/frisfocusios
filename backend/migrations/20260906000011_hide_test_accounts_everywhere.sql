-- Keep seeded test accounts out of every discovery surface, not just one.
--
-- The project carries seven seeded accounts (`is_test = true`) used to
-- develop the social features against something. `search_people` filters
-- them; nothing else did.
--
-- The concrete consequence: two of their circles — "Sunrise Club" and
-- "1000 Miles Together" — are `visibility = 'public'`, so a real beta
-- user opening Discover would have found rooms full of fictional people
-- and been able to join them. Contact matching had the same hole, latent
-- only because these particular rows happen to carry no email.
--
-- Filtering by the flag rather than deleting the rows keeps the fixtures
-- useful for development, and — more importantly — means the guard holds
-- for the NEXT seeded account too, instead of depending on someone
-- remembering to clean up.

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
    AND (c.end_date IS NULL OR c.end_date > now())
    AND (
      search IS NULL OR btrim(search) = ''
      OR c.name ILIKE '%' || btrim(search) || '%'
      OR coalesce(c.description, '') ILIKE '%' || btrim(search) || '%'
    )
  ORDER BY c.created_at DESC
  LIMIT 50;
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
    and p.email is not null
    and lower(p.email) in (select lower(e) from unnest(coalesce(p_emails, '{}'::text[])) e)
  union
  select ck.user_id from contact_keys ck
  join profiles cp on cp.id = ck.user_id
  where user_id() is not null
    and coalesce(cp.is_test, false) = false
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
    and p.email is not null
    and lower(p.email) in (select lower(e) from unnest(coalesce(p_emails, '{}'::text[])) e)
  union
  select ck.user_id, null::text, ck.phone_hash
  from contact_keys ck
  join profiles cp on cp.id = ck.user_id
  where user_id() is not null
    and coalesce(cp.is_test, false) = false
    and ck.phone_hash is not null
    and ck.phone_hash in (select h from unnest(coalesce(p_phone_hashes, '{}'::text[])) h)
$function$;
