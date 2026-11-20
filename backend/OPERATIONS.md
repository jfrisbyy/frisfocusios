# Backend operations

What has to be set, applied and checked for the backend to do what the app
promises. Moderation has its own runbook: [MODERATION.md](MODERATION.md).

## Edge function secrets

Supabase dashboard → Edge Functions → Secrets. `SUPABASE_URL`,
`SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided by the
platform.

| Secret | Used by | Needed for |
| --- | --- | --- |
| `MODERATOR_USER_IDS` | `moderation` | Comma-separated account ids allowed to moderate. Unset = every moderator request refused (503). |
| `MODERATION_WEBHOOK_URL` | `moderation` | Optional. Slack/Discord incoming webhook; one line per newly filed report. |
| `SWEEP_SECRET` | `stories-sweep`, `golden-hour-sweep` | Lets the scheduler call the sweeps without a member's token. At least 16 characters; shorter values are ignored. Generate with `openssl rand -hex 32`. |
| `INVITE_INSTALL_URL` | `invite` | **Set to the App Store URL at launch.** Until it is, the invite page has no "Get FrisFocus" button and tells people to search by @username instead. |

All four of these functions must run with gateway **JWT verification off**
(they verify the Rork token themselves, and `invite` and the scheduled
sweep calls carry no Supabase token at all). `scripts/deploy-functions.sh`
does not pass `--no-verify-jwt`, so after any deploy confirm in the
dashboard (Edge Functions → the function → Details) that "Verify JWT" is
still off. If it has flipped on, the scheduled sweeps and the invite page
fail with 401 before the function runs.

## Migrations added 2026-11-20

Apply in order. Each is written to be re-run safely.

| File | What it does | Deploy order |
| --- | --- | --- |
| `20261120000110_report_targets.sql` | `reports.golden_hour_post_id`, `reports.circle_id`; `moderation_actions.target_kind/target_id`. | Before deploying `moderation` (its remove/suspend actions write the new audit columns). |
| `20261120000111_focus_shared_tasks.sql` | The `focus_shared_tasks` table the app has always written to. | Any time. No client change needed. |
| `20261120000112_account_suspension.sql` | `suspensions` table, `is_suspended()`, and the policies that enforce it. Replaces `can_see_story`, `search_people`, `discover_public_circles`, `filter_not_blocked`, `match_contacts`, `match_contact_keys` with versions that skip suspended accounts. | Before using `suspend`. Nobody is suspended until you suspend them, so applying it changes nothing visible. |
| `20261120000113_schedule_media_sweeps.sql` | Enables `pg_cron` and `pg_net`; schedules the two sweeps. | Any time — it does nothing until the two Vault secrets below exist. |
| `20261120000114_golden_hour_post_to_see.sql` | Storage policy: Golden Hour media readable only by members who have posted to that wall. | With or after the app build that contains the matching wall change (tiles re-request their media once you post). Applying it earlier is safe but an older build shows a spinner on other people's tiles until the wall is reopened. |
| `20261120000115_unbreak_people_discovery.sql` | Grants `authenticated` SELECT on `profiles.is_test`. People suggestions and "Near you" filter on that column and have been refused (42501) since `20260906000001`, so both lists have been empty. | Any time. One `GRANT`; fixes it for builds already installed. |

`backend/types.ts` is generated and now stale; regenerate it after applying.

## Scheduled media sweeps

Stories are meant to vanish after a day and Golden Hour captures after an
hour. The sweeps are what delete the stored media; until they were
scheduled, they ran only when someone opened the app.

After applying `20261120000113`:

1. Set the function secret `SWEEP_SECRET` (above) and redeploy both sweeps:
   `./scripts/deploy-functions.sh stories-sweep golden-hour-sweep`
2. Store the same value, and the project URL, in Vault (SQL editor):

   ```sql
   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
   select vault.create_secret('<the SWEEP_SECRET value>', 'sweep_secret');
   ```

   To change one later: `select vault.update_secret(id, '<new value>')`
   with the `id` from `select id, name from vault.secrets`.

Schedule: `stories-sweep` hourly at :07; `golden-hour-sweep` every 15
minutes (:03, :18, :33, :48) — a wall lasts an hour, so an hourly sweep
would leave a capture stored for up to an hour after its wall closed. A
third job trims pg_cron's own run history to 7 days.

Check it is working:

```sql
-- the jobs
select jobname, schedule, active from cron.job;

-- recent runs (status 'succeeded' means the SQL ran, not that the HTTP call worked)
select jobname, status, return_message, start_time
from cron.job_run_details d join cron.job j using (jobid)
order by start_time desc limit 10;

-- the HTTP responses themselves: expect status_code 200 and {"ok":true,...}
select id, status_code, content::text, created
from net._http_response order by created desc limit 10;

-- run one now
select public.run_media_sweep('golden-hour-sweep');
```

A run that logs `vault secrets project_url / sweep_secret are not set;
skipping` is the unconfigured no-op. A 401 in `net._http_response` means
the Vault value and the function secret differ, or JWT verification is on
for that function.

The app still triggers both sweeps opportunistically; that is harmless.
Any signed-in member can call them because the request has no parameters:
the cutoff is the server's clock, and a second call finds nothing to do.

**Reported media is held.** A story or capture with an open report is
skipped by the sweep until the report is reviewed, or for 14 days at most.
This is the one exception to "deleted when the timer ends", and the
privacy policy should say so (content that has been reported may be kept
while the report is reviewed).

## Invite links

`InviteLink.webURL` points at the `invite` edge function on the project's
default domain. **Supabase serves edge-function HTML from `*.supabase.co`
as `text/plain`**, so a recipient who opens the link in a browser may see
the page's source instead of the page. This has not been verified from
the build environment — open
`https://<project-ref>.supabase.co/functions/v1/invite?u=<your id>` in
Safari to see which you get.

The invite works either way:

- The app's share text leads with `Add me on FrisFocus: @username`, so
  the message itself tells the recipient who to search for.
- The document begins with a plain-language note (who invited you, their
  @username, where to search, the install link) which is what a person
  reads first if the source is shown.

For a page that renders, do one of:

- **Custom domain** on the Supabase project (a paid add-on). HTML from
  edge functions is served as HTML on custom domains. Set
  `EXPO_PUBLIC_SUPABASE_URL` for the build to that domain — invite links
  are built from it.
- **Static host.** Put the page on any static host (the HTML is
  self-contained), and point `InviteLink.functionsBase` at it. A static
  page cannot look up the inviter's name, so it would be the generic
  card; `InviteLink.userId(from:)` also needs to accept the new path.

At launch set `INVITE_INSTALL_URL` to the App Store URL. No redeploy is
needed for a secret change to take effect on new invocations.

## Upload size

The app refuses media over 45 MB after compression
(`VideoTranscoder.maxUploadBytes`). Supabase's project-wide upload limit
is 50 MB on the free plan and overrides the 200 MB bucket limits set in
`20260906000007`. If the project moves to a paid plan and the global limit
is raised (Storage → Settings), the client cap can be raised with it.
