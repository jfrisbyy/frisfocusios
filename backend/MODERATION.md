# Moderation runbook

How to act on a report. App Store guideline 1.2 expects objectionable
content to be dealt with — removed, and the person responsible ejected —
within 24 hours of a report. Everything here goes through one edge
function, `moderation`; there is no dashboard.

## One-time setup

1. Apply migrations `20261120000110_report_targets.sql` and
   `20261120000112_account_suspension.sql`.
2. Deploy the function: `./scripts/deploy-functions.sh moderation`
3. Set its secrets (Supabase dashboard → Edge Functions → Secrets):

   | Secret | Value |
   | --- | --- |
   | `MODERATOR_USER_IDS` | Comma-separated account ids (`usr_…`) allowed to moderate. **Until this is set every moderator request is refused with 503.** |
   | `MODERATION_WEBHOOK_URL` | Optional. A Slack or Discord incoming-webhook URL. When set, each newly filed report posts one line there. |

   Your own account id is the `sub` of your token, and the `id` of your row
   in `profiles`.

The webhook line carries the report id, the reason picked and the reported
account id — never the reporter's free-text note. If the webhook is unset,
nothing is sent and you have to poll the queue (below) at least daily.

## Getting a token

Requests are authenticated as **you**, with the same Rork access token the
app uses. Exchange a refresh token for one (this is the call the app itself
makes in `AuthManager.refreshToken`):

```bash
# Simulator, signed in as a moderator account:
REFRESH=$(xcrun simctl spawn booted defaults read com.frisfocus.app RORK_AUTH_REFRESH_TOKEN)

TOKEN=$(curl -s "$RORK_AUTH_URL/oauth/refresh" \
  -H 'Content-Type: application/json' \
  -d "{\"app_key\":\"$RORK_APP_KEY\",\"refresh_token\":\"$REFRESH\"}" | jq -r .access_token)

FN="https://<project-ref>.supabase.co/functions/v1/moderation"
```

`RORK_AUTH_URL` and `RORK_APP_KEY` are the values the app is built with
(see the README). Access tokens are short-lived; re-run the exchange when a
call starts returning 401.

That `defaults read` only finds a token on a simulator launched through
Rork, which is where the app reads it from too. On a device or a plain
Xcode simulator the refresh token lives in the Keychain; the practical
route there is a debug build that prints
`KeychainHelper.get("access_token")` once. This section was written from
the app's own refresh code and has not been run end to end — check it
works for you before you need it in a hurry.

A `404 Not found` means the token is valid but its account is not in
`MODERATOR_USER_IDS`. That is deliberate: a non-moderator cannot tell this
function from one that does not exist.

## Working the queue

**List open reports**, oldest first:

```bash
curl -s "$FN?status=open&limit=50" -H "Authorization: Bearer $TOKEN" | jq
```

`status` can also be `actioned` or `dismissed`.

**Look at one report** — the content it points at, with links to the media
that work for one hour:

```bash
curl -s "$FN?reportId=<report-id>" -H "Authorization: Bearer $TOKEN" | jq
```

`target` says what `remove` would take down. `evidence` holds the text
(caption, comment, message body, circle name and description) and a
`signed_media_url` for photos and video. A key that is present but `null`
means the content is already gone. `evidence.reported_user.prior_actions`
is how many times this account has been actioned before.

**Dismiss** — nothing wrong:

```bash
curl -s "$FN" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"reportId":"<report-id>","decision":"dismissed","note":"Not a violation"}'
```

**Mark actioned** without removing anything (you dealt with it some other way):

```bash
curl -s "$FN" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"reportId":"<report-id>","decision":"actioned","note":"Warned by email"}'
```

**Remove the reported content.** Deletes the row and its stored media, marks
this report — and every other open report about the same content —
actioned:

```bash
curl -s "$FN" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"action":"remove","reportId":"<report-id>","note":"Explicit content"}'
```

A report resolves to the most specific thing it names: comment, then story,
then message/proof, then Golden Hour capture, then circle. To remove
something else, or something nobody reported, name it:

```bash
curl -s "$FN" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"action":"remove","target":{"kind":"story_post","id":"<uuid>"},"note":"…"}'
```

`kind` is one of `story_post`, `story_comment`, `message`,
`golden_hour_post`, `circle`. Removing a `circle` deletes the whole circle
for every member, with its stories and captures — the widest action here.
Removal cannot be undone. Running it twice is harmless (`"removed": false`).

**Suspend an account:**

```bash
curl -s "$FN" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"action":"suspend","reportId":"<report-id>","reason":"Repeated harassment","note":"3rd report this week"}'
```

Pass `"userId":"usr_…"` instead of `reportId` to suspend someone directly.
`reason` is **shown to the suspended person** in the app; `note` is internal.

**Lift a suspension:**

```bash
curl -s "$FN" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"action":"unsuspend","userId":"usr_…","note":"Appeal accepted"}'
```

A typical bad report takes two calls: `remove` the content, then `suspend`
the account if it is not their first.

## What a suspension does

Enforced in the database (row-level security), so it holds whatever the
client does:

- **Cannot create:** stories, comments, likes, messages and proofs, cheers,
  Golden Hour captures, circles, circle events and shared tasks, circle
  invitations and join requests, friend requests and friendships, pacts,
  group focus sessions; cannot join a circle; cannot edit a circle they run;
  cannot upload to the shared media buckets (stories, proofs, Golden Hour,
  avatars).
- **Hidden from others:** their stories, comments and Golden Hour captures;
  their account in people search, people suggestions, "Near you" and
  contact matching; circles they own in Discover.
- **The app** shows them "Your account is suspended", the reason, and a
  contact-support button in place of the social room.

Not covered — do these by hand if they matter for a case:

- Messages, cheers and circle content they sent **before** the suspension
  stay visible to the people who received them. Remove specific items with
  `remove`.
- They can still edit their own profile (name, bio, username).
- They remain a member of circles they were already in, and existing
  friendships stay.
- Their own private data (tasks, notes, season) is untouched, on purpose.
- Push notifications they trigger are not blocked separately; with nothing
  left that they can send, there is nothing to trigger them.
- **Deleting the account lifts the suspension.** The suspension row is
  removed with the profile (like the rest of their data), and the same
  person signing in again gets a fresh, unsuspended account — with no
  friends, circles or content. If that is being abused, re-suspend the id
  (it does not change), or drop the foreign key on `suspensions.user_id`
  so the record outlives the account; that keeps an account id after
  deletion and would need a line in the privacy policy.

Lifting a suspension restores everything that was hidden. Nothing is
deleted by suspending.

## Evidence that would otherwise vanish

Stories delete their media after a day and Golden Hour captures after an
hour. A story or capture with an **open** report against it is held back
from that sweep until the report is reviewed (or 14 days pass), so there is
something to look at. Once you dismiss or action the report, the next sweep
deletes it as usual. An unreviewed queue is therefore also a privacy cost:
close reports promptly.

## The record

Every decision, removal and suspension is a row in `moderation_actions`
(who, what, on whom, when, your note). No member can read it. From the SQL
editor:

```sql
select created_at, moderator_id, action, target_kind, target_id, subject_user_id, note
from moderation_actions
order by created_at desc
limit 50;

-- Who is suspended right now
select * from suspensions order by created_at desc;

-- How long has the oldest open report been waiting?
select now() - min(created_at) as oldest_open from reports where status = 'open';
```

## If the function is unavailable

The same actions by hand, in the SQL editor (service role):

```sql
-- suspend / lift
insert into suspensions (user_id, reason) values ('usr_…', 'Reason shown to them')
  on conflict (user_id) do update set reason = excluded.reason;
delete from suspensions where user_id = 'usr_…';

-- remove a story (then delete its object in Storage → stories)
delete from story_posts where id = '<uuid>';
```

Record what you did in `moderation_actions` so the trail stays whole.
