-- Carry teaching progress with the account, not the device.
--
-- WalkthroughManager kept everything it knows in UserDefaults:
-- `walkthrough.seenLessons.v1` and `walkthrough.mechanicsTour.done.v1`.
-- So a new phone replays the whole seven-step tour and every concept
-- lesson to someone who has used the app for months — the app forgetting
-- who you are, in the one layer whose entire job is to remember.
--
-- Deliberately its own table rather than columns on `profiles`: that
-- table is readable by every signed-in member (name, avatar, username),
-- and which lessons someone still has to be taught is nobody else's
-- business.

create table if not exists public.walkthrough_progress (
  user_id text primary key,
  seen_lessons text[] not null default '{}',
  tour_completed boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.walkthrough_progress enable row level security;

create policy "Own walkthrough progress" on public.walkthrough_progress
  for all
  using (user_id = public.user_id())
  with check (user_id = public.user_id());
