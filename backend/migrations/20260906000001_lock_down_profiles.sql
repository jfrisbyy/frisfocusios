-- Lock down public.profiles.
--
-- Before this migration the table carried a single SELECT policy —
-- `USING (true)` for role `public`, which includes `anon`. The anon key
-- ships inside the app binary and is trivially extracted, so anyone could
-- GET /rest/v1/profiles?select=* and dump every user's id, name, username,
-- avatar, header, coarse area, season card AND email address, with no
-- authentication at all.
--
-- That directly contradicts the in-app Privacy Policy ("Your email is
-- stored privately — it is never shown to other members") and it bypassed
-- the friend-gating in get_season_cards, since season_card is a plain
-- column on the same open table.
--
-- Two changes, because RLS alone is not enough:
--
--  1. Require authentication to read any profile row at all.
--  2. Restrict WHICH COLUMNS a signed-in member can read. Postgres will
--     not honour a column-level REVOKE while a table-level SELECT grant
--     exists, so the table grant is dropped first and the readable
--     columns are granted back explicitly.
--
-- `email`, `season_card` and `is_test` are deliberately absent from the
-- allow-list. The iOS client never selects any of them: it reads explicit
-- column lists, and season cards come from the friend-gated
-- get_season_cards RPC (SECURITY DEFINER, so column grants do not apply).
-- The `invite` edge function uses the service-role key and is unaffected.

begin;

drop policy if exists "Anyone can read profiles" on public.profiles;

create policy "Signed-in members read profiles"
  on public.profiles
  for select
  using (public.user_id() is not null);

revoke select on public.profiles from anon;
revoke select on public.profiles from authenticated;

grant select (
  id,
  name,
  username,
  avatar_url,
  header_url,
  bio,
  area_key,
  area_name,
  created_at,
  updated_at
) on public.profiles to authenticated;

commit;
