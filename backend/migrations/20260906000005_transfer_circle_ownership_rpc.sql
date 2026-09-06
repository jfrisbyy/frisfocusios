-- Make ownership transfer atomic.
--
-- Transferring a circle touches three rows: the new owner's membership
-- role, the outgoing owner's role, and circles.owner_id. Done as three
-- separate statements from the client, the third one is denied:
--
--   my_circle_role(id) reads the CALLER'S OWN circle_members.role, and
--   the "Owner or admin update circle" policy requires it to be 'owner'
--   or 'admin'. By the time the client reaches the circles UPDATE it has
--   already demoted itself to 'member', so the policy refuses.
--
-- The circle would be left with circle_members naming the new owner
-- while circles.owner_id still named the old one — and unrecoverable by
-- retry, because the outgoing owner can no longer satisfy the policy.
-- owns_circle() would say one thing and my_circle_role() another, which
-- different policies each rely on.
--
-- Reordering the writes would hide the hazard rather than remove it, so
-- the whole transfer moves server-side: one call, one permission check
-- against circles.owner_id, all three writes in a single transaction.

create or replace function public.transfer_circle_ownership(
  p_circle_id uuid,
  p_to_user text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me text := public.user_id();
begin
  if v_me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  -- Authority comes from circles.owner_id, not from the caller's own
  -- membership role, precisely so the demotion below cannot revoke the
  -- permission mid-transfer.
  if not exists (
    select 1 from public.circles c
    where c.id = p_circle_id and c.owner_id = v_me
  ) then
    raise exception 'Only the circle owner can transfer ownership'
      using errcode = '42501';
  end if;

  if p_to_user = v_me then
    raise exception 'That circle is already yours' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.circle_members m
    where m.circle_id = p_circle_id and m.user_id = p_to_user
  ) then
    raise exception 'Ownership can only pass to another member'
      using errcode = '22023';
  end if;

  update public.circle_members
     set role = 'owner'
   where circle_id = p_circle_id and user_id = p_to_user;

  update public.circle_members
     set role = 'member'
   where circle_id = p_circle_id and user_id = v_me;

  update public.circles
     set owner_id = p_to_user
   where id = p_circle_id;
end;
$function$;

-- Signed-in members only. The database linter flags SECURITY DEFINER
-- functions that anon can reach, and a governance action has no business
-- being callable without a session.
revoke execute on function public.transfer_circle_ownership(uuid, text) from anon;
revoke execute on function public.transfer_circle_ownership(uuid, text) from public;
grant execute on function public.transfer_circle_ownership(uuid, text) to authenticated;
