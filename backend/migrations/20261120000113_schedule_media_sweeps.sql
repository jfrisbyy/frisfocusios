-- Run the media sweeps on a clock instead of on a visit.
--
-- `stories-sweep` and `golden-hour-sweep` are what make "this vanishes"
-- true in storage, and until now the only thing that ever called them
-- was an app launch. On a quiet day — or for a circle nobody reopened —
-- "deleted when the timer ends" meant "deleted whenever somebody next
-- opens the app".
--
-- pg_cron fires on schedule; pg_net makes the HTTP call to the edge
-- function. Both functions accept the shared secret in an
-- `x-sweep-secret` header as an alternative to a member's JWT.
--
-- SAFE TO APPLY BEFORE ANYTHING IS CONFIGURED. The URL and the secret
-- are read from Vault at run time, not baked into the job, and a run
-- that finds either missing does nothing and says so. To switch it on
-- (see backend/OPERATIONS.md):
--
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<same value as the SWEEP_SECRET function secret>', 'sweep_secret');
--
-- Nothing secret is stored in this file, in `cron.job`, or in the
-- function body.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;

create or replace function public.run_media_sweep(p_function text)
returns void
language plpgsql
set search_path to 'public'
as $function$
declare
  v_url text;
  v_secret text;
begin
  -- An allow-list, so this can never be pointed at an arbitrary path
  -- with the sweep secret attached.
  if p_function not in ('stories-sweep', 'golden-hour-sweep') then
    raise exception 'run_media_sweep: unknown function %', p_function;
  end if;

  select s.decrypted_secret into v_url
    from vault.decrypted_secrets s
   where s.name = 'project_url'
   limit 1;
  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s
   where s.name = 'sweep_secret'
   limit 1;

  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then
    raise notice 'run_media_sweep(%): vault secrets project_url / sweep_secret are not set; skipping', p_function;
    return;
  end if;

  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/' || p_function,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sweep-secret', v_secret
    ),
    timeout_milliseconds := 30000
  );
end;
$function$;

-- Not an RPC. Only the scheduler (which runs as the role that created
-- the job) and the service role have any business calling this.
revoke execute on function public.run_media_sweep(text) from public;
revoke execute on function public.run_media_sweep(text) from anon;
revoke execute on function public.run_media_sweep(text) from authenticated;

-- cron.schedule with a job name replaces a job of the same name, so
-- re-applying this file reschedules rather than duplicating.
--
-- Stories expire on a 24-hour clock, so hourly is ample. A Golden Hour
-- wall lasts one hour, so an hourly sweep could leave a capture in
-- storage for nearly an hour after its wall closed; every fifteen
-- minutes keeps the promise close to literal. Minutes are offset so the
-- two never fire together, and off the top of the hour.
select cron.schedule(
  'stories-sweep-hourly',
  '7 * * * *',
  $cron$select public.run_media_sweep('stories-sweep')$cron$
);

select cron.schedule(
  'golden-hour-sweep-quarter-hourly',
  '3,18,33,48 * * * *',
  $cron$select public.run_media_sweep('golden-hour-sweep')$cron$
);

-- pg_cron keeps a row per run forever. At ~120 runs a day that is small,
-- but it is still a table that only grows; keep a week.
select cron.schedule(
  'cron-run-history-trim',
  '41 4 * * *',
  $cron$delete from cron.job_run_details where end_time < now() - interval '7 days'$cron$
);
