-- Cover every foreign key with an index.
--
-- The argument that settles this is account deletion. `delete-account`
-- has to remove a user, and Postgres checks each referencing table for
-- rows pointing at the row being deleted. Without an index on the
-- referencing column that check is a sequential scan — so deleting one
-- account scans all twenty of these tables end to end. That is a
-- requirement (App Store review and GDPR both want deletion to work),
-- and it is the operation least able to afford a timeout.
--
-- The same indexes serve the ordinary reads: "reports filed by me",
-- "who viewed this post", "this pact's tasks" all filter on exactly
-- these columns.

create index if not exists blocks_blocked_id_idx on public.blocks (blocked_id);
create index if not exists cadence_outcome_events_routine_id_idx on public.cadence_outcome_events (routine_id);
create index if not exists cheers_sender_id_idx on public.cheers (sender_id);
create index if not exists circle_contributions_user_id_idx on public.circle_contributions (user_id);
create index if not exists circle_invitations_invitee_id_idx on public.circle_invitations (invitee_id);
create index if not exists circle_invitations_inviter_id_idx on public.circle_invitations (inviter_id);
create index if not exists circle_join_requests_requester_id_idx on public.circle_join_requests (requester_id);
create index if not exists circle_task_completions_user_id_idx on public.circle_task_completions (user_id);
create index if not exists circles_owner_id_idx on public.circles (owner_id);
create index if not exists direct_messages_story_post_id_idx on public.direct_messages (story_post_id);
create index if not exists focus_blocks_host_id_idx on public.focus_blocks (host_id);
create index if not exists moderation_actions_report_id_idx on public.moderation_actions (report_id);
create index if not exists pact_completions_user_id_idx on public.pact_completions (user_id);
create index if not exists pact_tasks_pact_id_idx on public.pact_tasks (pact_id);
create index if not exists reports_message_id_idx on public.reports (message_id);
create index if not exists reports_reported_user_id_idx on public.reports (reported_user_id);
create index if not exists reports_reporter_id_idx on public.reports (reporter_id);
create index if not exists share_tiers_friend_id_idx on public.share_tiers (friend_id);
create index if not exists story_comments_user_id_idx on public.story_comments (user_id);
create index if not exists story_likes_user_id_idx on public.story_likes (user_id);
create index if not exists story_views_viewer_id_idx on public.story_views (viewer_id);
