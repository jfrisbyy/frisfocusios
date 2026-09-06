-- Crash, hang and onboarding-funnel telemetry.
--
-- Deliberately NOT keyed by account. Every row carries a random
-- per-install id instead of a user id, so the table answers "how many
-- people crash in the cold start" without becoming a per-person
-- behavioural record. That choice is what lets the privacy manifest
-- declare this data unlinked, and it is why there is no read policy
-- for the people writing it: nobody, including the author of a row,
-- can read this table back through the API.
--
-- Writes require a session so the endpoint is not an open firehose.
-- The cost is that pre-sign-in funnel steps have to be buffered on the
-- device and flushed once an account exists; someone who abandons
-- before ever signing in is not counted. That is a known and accepted
-- gap — the alternative is an anonymous, unauthenticated insert
-- endpoint, which is worse.

create table if not exists public.diagnostics_events (
  id uuid primary key default gen_random_uuid(),
  install_id uuid not null,
  kind text not null check (kind in ('crash', 'hang', 'disk_write', 'funnel')),
  name text not null,
  app_version text,
  os_version text,
  detail jsonb,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists diagnostics_events_kind_created_idx
  on public.diagnostics_events (kind, created_at desc);
create index if not exists diagnostics_events_install_idx
  on public.diagnostics_events (install_id);

alter table public.diagnostics_events enable row level security;

-- Insert only, and only with a session. No select, update or delete
-- policy exists, so only service_role can ever read this back.
drop policy if exists "Signed-in devices record diagnostics" on public.diagnostics_events;
create policy "Signed-in devices record diagnostics"
  on public.diagnostics_events
  for insert
  to authenticated
  with check (user_id() is not null);

-- Supabase's default privileges hand ALL on a new public table to anon
-- and authenticated, so an insert-only *policy* would otherwise sit on
-- top of a table-level SELECT grant. RLS would still return nothing
-- (there is no select policy), but "no policy" is a weaker guarantee
-- than "no grant" — the same trap this schema has hit three times now,
-- with column privileges on profiles and with PUBLIC EXECUTE on the
-- RPCs. Take everything back, hand out only the one verb.
revoke all on public.diagnostics_events from anon, authenticated, public;
grant insert on public.diagnostics_events to authenticated;
