-- Stop an admin from removing the circle's owner.
--
-- The DELETE policy on circle_members read:
--
--     user_id = user_id()
--     OR my_circle_role(circle_id) = ANY (ARRAY['owner','admin'])
--
-- which lets ANY admin delete ANY row — including the owner's, and
-- including other admins'. The Swift Store already encoded the intended
-- rules ("owners can't be kicked; admins can't remove other admins"), but
-- those checks lived only on the device, so the database itself would
-- have accepted an admin deleting the owner.
--
-- Now the rules live where they are actually enforced:
--   • anyone may remove themselves (leaving a circle),
--   • an owner may remove anyone except themselves — ownership has to be
--     transferred first, so a circle is never left without an owner,
--   • an admin may remove plain members only.

begin;

drop policy if exists "Leave or be removed by owner/admin" on public.circle_members;

create policy "Leave, or be removed by owner or admin"
  on public.circle_members
  for delete
  using (
    user_id = public.user_id()
    or (
      public.my_circle_role(circle_id) = 'owner'
      and role <> 'owner'
    )
    or (
      public.my_circle_role(circle_id) = 'admin'
      and role = 'member'
    )
  );

commit;
