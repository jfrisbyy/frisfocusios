-- Give reports somewhere to go.
--
-- Block, report and hide were all properly built and RLS-enforced, but a
-- report was a dead end: the row landed in public.reports and nothing
-- read it. No status, no queue, no record of a decision, and no way to
-- act on one. App Review expects a mechanism with a timely response
-- behind it, and the Terms promise content removal and account
-- suspension that there was no tooling to deliver.
--
-- This adds the workflow columns and an audit trail. The queue itself is
-- the `moderation` edge function, which is the only thing that writes
-- here — reporters keep their existing insert-and-read-my-own access and
-- gain nothing new.

alter table public.reports
  add column if not exists status text not null default 'open',
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewer_id text,
  add column if not exists reviewer_note text;

-- Deliberately a check constraint rather than an enum: statuses change
-- shape as a moderation process matures, and altering a check is cheap
-- where altering an enum in Postgres is not.
alter table public.reports
  drop constraint if exists reports_status_valid;
alter table public.reports
  add constraint reports_status_valid
  check (status in ('open', 'actioned', 'dismissed'));

-- The queue reads open reports oldest-first; this is that query.
create index if not exists reports_open_idx
  on public.reports (status, created_at)
  where status = 'open';

-- Every decision, kept separately from the report it was about, so the
-- record survives even if the report row is later cleaned up. There is no
-- RLS policy: only the service role reaches this, and a moderation trail
-- is not something any member should be able to read.
create table if not exists public.moderation_actions (
  id bigint generated always as identity primary key,
  report_id uuid references public.reports(id) on delete set null,
  moderator_id text not null,
  action text not null,
  subject_user_id text,
  note text,
  created_at timestamptz not null default now()
);

alter table public.moderation_actions enable row level security;

create index if not exists moderation_actions_subject_idx
  on public.moderation_actions (subject_user_id, created_at desc);
