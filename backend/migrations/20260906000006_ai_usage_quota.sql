-- Per-user quota accounting for the AI edge functions.
--
-- openrouter-chat, season-setup and todays-read all verify the caller's
-- JWT but had no per-user limit of any kind — only per-request size caps.
-- Each one calls a paid model (season-setup runs Claude Opus, the most
-- expensive tier, on every onboarding), so a retry loop in a client bug,
-- or one motivated account, could run up an unbounded bill.
--
-- Deliberately a plain append-only ledger rather than a counter column:
-- rolling windows stay honest across restarts, and a row is far cheaper
-- to write than a model call is to make. RLS is enabled with NO policies,
-- so nothing but the service role can read or write it — the edge
-- functions already hold that key and no client has any business seeing
-- another person's usage.

create table if not exists public.ai_usage (
  id bigint generated always as identity primary key,
  user_id text not null,
  fn text not null,
  created_at timestamptz not null default now()
);

-- Serves both window queries (hourly and daily) for one user and function.
create index if not exists ai_usage_lookup
  on public.ai_usage (user_id, fn, created_at desc);

-- Serves the retention sweep.
create index if not exists ai_usage_created_at
  on public.ai_usage (created_at);

alter table public.ai_usage enable row level security;

-- Old rows carry no value once they leave the widest window. Kept as a
-- function so a scheduled job (or any function) can call it cheaply.
create or replace function public.prune_ai_usage()
returns void
language sql
security definer
set search_path to 'public'
as $function$
  delete from public.ai_usage where created_at < now() - interval '3 days';
$function$;

revoke execute on function public.prune_ai_usage() from public;
revoke execute on function public.prune_ai_usage() from anon;
revoke execute on function public.prune_ai_usage() from authenticated;
