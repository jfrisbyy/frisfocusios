-- Three user-keyed tables survived account deletion.
--
-- `delete-account` deletes ~35 tables by hand, and `season_cards` and
-- `share_tiers` are safe only because they carry ON DELETE CASCADE from
-- profiles. These three carried neither: no delete in the function, and
-- no foreign key to cascade through. After "delete my account" they kept
-- the person's notification preferences, their teaching progress, and
-- their AI usage ledger — all keyed by a user id that no longer had an
-- account. Two of the three are tables this branch added.
--
-- Fixed with a foreign key rather than three more lines in the edge
-- function, because a cascade cannot be forgotten by the next person to
-- add a table's worth of deletes. Verified as zero orphan rows before
-- adding the constraint, and rehearsed afterwards in a rolled-back
-- transaction: inserting a profile plus a row in each of the three, then
-- deleting the profile, leaves all three at zero.
--
-- The index on each user_id is required anyway: without it, deleting one
-- profile sequentially scans each of these to find referencing rows.

create index if not exists walkthrough_progress_user_id_idx
  on public.walkthrough_progress (user_id);
create index if not exists ai_usage_user_id_idx
  on public.ai_usage (user_id);
create index if not exists notification_preferences_user_id_idx
  on public.notification_preferences (user_id);

alter table public.walkthrough_progress
  drop constraint if exists walkthrough_progress_user_id_fkey,
  add constraint walkthrough_progress_user_id_fkey
    foreign key (user_id) references public.profiles(id) on delete cascade;

alter table public.ai_usage
  drop constraint if exists ai_usage_user_id_fkey,
  add constraint ai_usage_user_id_fkey
    foreign key (user_id) references public.profiles(id) on delete cascade;

alter table public.notification_preferences
  drop constraint if exists notification_preferences_user_id_fkey,
  add constraint notification_preferences_user_id_fkey
    foreign key (user_id) references public.profiles(id) on delete cascade;
