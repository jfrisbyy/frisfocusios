-- Take EXECUTE away from anon on the client-facing RPCs.
--
-- `is_muted` was written with `revoke execute ... from anon`, and the
-- linter still reported it as anon-executable. The reason is the same
-- trap as the column-level SELECT revoke on `profiles`: Postgres grants
-- EXECUTE on every new function to PUBLIC, and `anon` inherits that.
-- Revoking the role alone removes nothing. `transfer_circle_ownership`,
-- which revoked PUBLIC as well, is correctly absent from the report —
-- which is what made the difference legible.
--
-- Scope is deliberately the ENTRY-POINT RPCs only: the ones the client
-- calls directly, all of which already return nothing when `user_id()`
-- is null. This is defence in depth, not a hole being closed.
--
-- The helpers used INSIDE row-level-security policies — are_friends,
-- can_see_story, is_blocked, is_circle_member, my_circle_role,
-- owns_circle, is_pact_member, in_focus_block, shares_circle_with — are
-- deliberately left alone. Those are evaluated as whatever role is
-- running the query, so revoking PUBLIC risks breaking policy evaluation
-- in ways that cannot be verified from here. That belongs in a pass with
-- a way to test it, not bundled into this one.

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.search_people(text)',
    'public.match_contacts(text[], text[])',
    'public.match_contact_keys(text[], text[])',
    'public.discover_public_circles(text)',
    'public.get_season_cards(text[])',
    'public.is_muted(text)'
  ]
  loop
    execute format('revoke execute on function %s from public', fn);
    execute format('revoke execute on function %s from anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
