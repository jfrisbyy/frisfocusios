# FrisFocus

An honest record of your life. Your day is a sun that rises as you do what
matters — priced by what each thing costs *you*, shared only with the people
you choose, and never gamified into pressure.

- `ios-frisfocus/` — the SwiftUI app (iOS 18+), its widget, and test targets.
- `backend/` — Supabase edge functions (Deno) and the generated DB types.
- `scripts/` — build configuration templates and bootstrap tooling.

## Getting the project to build

The project needs a `Config.swift` that is **not** in version control, because
it carries environment values. Generate it before opening Xcode:

```bash
# Placeholders — compiles and opens, but cannot reach the network.
./scripts/bootstrap-config.sh

# Real values — a working local build.
FRISFOCUS_SUPABASE_URL="https://<ref>.supabase.co" \
FRISFOCUS_SUPABASE_ANON_KEY="<anon key>" \
FRISFOCUS_RORK_AUTH_URL="https://api.rork.com" \
FRISFOCUS_RORK_APP_KEY="<app key>" \
FRISFOCUS_PROJECT_ID="<project id>" \
./scripts/bootstrap-config.sh
```

Then:

```bash
open ios-frisfocus/FrisFocus.xcodeproj
```

**Xcode 26 or newer is required.** The app deploys to iOS 18, but
`SundialNavView` uses the iOS 26 `glassEffect` API behind an
`if #available(iOS 26.0, *)` check. An availability check still needs an SDK
that knows the symbol, so building on Xcode 16 fails with
"value of type '_ShapeView<Capsule, Color>' has no member 'glassEffect'".

Adding a new configuration key means editing **both**
`scripts/config/Config.example.swift` and `scripts/bootstrap-config.sh`, so a
fresh clone and CI keep building.

> The template lives outside `ios-frisfocus/FrisFocus/` on purpose. That folder
> is a `PBXFileSystemSynchronizedRootGroup`, so every `.swift` file inside it is
> compiled automatically — a second file declaring `Config` there would be a
> duplicate-symbol failure.

## CI

`.github/workflows/ios.yml` runs on every push:

- **Build & test** (macOS): generates `Config.swift` from repository secrets,
  compiles the `FrisFocus` scheme against the iOS Simulator SDK, and runs the
  unit tests.
- **Edge functions typecheck** (Ubuntu): `deno check` over every
  `backend/functions/*/index.ts`.

Set these repository secrets so CI builds against the real environment. Without
them the build still runs with placeholders, which is enough to catch compile
errors:

`FRISFOCUS_SUPABASE_URL`, `FRISFOCUS_SUPABASE_ANON_KEY`,
`FRISFOCUS_RORK_AUTH_URL`, `FRISFOCUS_RORK_APP_KEY`, `FRISFOCUS_PROJECT_ID`.

After your first local package resolve, commit the resulting
`ios-frisfocus/FrisFocus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
so dependency versions are pinned for everyone.

## Database

Schema changes live in `backend/migrations/` and are applied to the Supabase
project. Never change the schema only through the dashboard — an unversioned
policy change is how a table ends up world-readable without anyone noticing.

### Advisor findings we deliberately leave open

Two categories of Supabase linter warning stay in the report on purpose.
Both were tested, not assumed.

**`rls_enabled_no_policy` on `ai_usage`, `moderation_actions`,
`test_engine_state`** — RLS on with zero policies means deny-all to
`anon` and `authenticated`; only `service_role` reaches them. For a quota
ledger, a moderation audit trail, and test-harness state, that *is* the
intended posture. A policy here would be a widening, not a fix.

**`anon`/`authenticated` can execute the SECURITY DEFINER helpers**
(`is_blocked`, `is_circle_member`, `are_friends`, `can_see_story`, …) —
these are the functions RLS policies are built out of, and a policy
expression is evaluated with the *calling* role's rights. Revoking
`EXECUTE` from `PUBLIC` was rehearsed inside a rolled-back transaction:
with the grant in place an anonymous `select from story_posts` returns
0 rows; with it revoked the same query fails with
`42501: permission denied for function is_blocked`. So revoking turns a
clean empty result into a hard error on every policy that references the
helper. The helpers resolve everything through `user_id()`, which is null
for `anon`, so they disclose nothing — the warning describes reachability,
not exposure. Closing it properly means restructuring the policies, not
changing a grant.

The client-facing entry-point RPCs are a different matter and *are*
revoked — see `20260906000012_revoke_anon_rpc_execute.sql`.

The **iOS 18.0 deployment floor stays**. iOS 26 is current, so 18 is two
major versions back and adoption is high; dropping to 17 would mean
auditing every API in the app for a sliver of devices. The one iOS 26
call (`glassEffect` in `SundialNavView`) is already behind an
`#available` check with a working `.ultraThinMaterial` fallback.

Two performance findings are also left open on purpose. **17 unused
indexes**: this database has almost no traffic yet, so "unused" means
"nothing has run that query", not "nothing ever will". Dropping indexes
on that evidence before launch is how a query goes quadratic in week
two. Re-read this after real beta traffic, not before. **24 overlapping
permissive policies**: consolidating two permissive policies into one
changes what the table allows, and there is no test here that would
catch getting it wrong. It is a real cost at scale and the wrong thing
to do blind — it wants a pass with a way to verify each merge.

### Localization: what is actually left

`FrisFocus/Localizable.xcstrings` now exists (empty, source language
`en`), so Xcode extracts `Text` literals into it on build and there is
somewhere for translations to land. That is the pipeline, not the work. The infrastructure is
smaller than it looks and the work is bigger, so it is worth separating
the two.

SwiftUI's `Text("…")` takes a `LocalizedStringKey`, so **1160 literals in
`Views/` are already localization keys** and the catalog picks them up
with no code change. That is the cheap half.

The expensive half, measured rather than estimated:

| Count | What | Why it is not automatic |
|---|---|---|
| 392 | `Text(someVariable)` | Uses the `String` overload, which is never localized. Each one has to be triaged: genuinely user-entered content should become `Text(verbatim:)` to say so; anything else is a missed string. |
| 265 | `Text("… \(value) …")` | Interpolation needs a plural rule per language, not a translated sentence. "1 moment" / "3 moments" is the easy case; languages with more than two plural forms are not. |
| — | Accessibility labels, alert titles, confirmation dialogs, notification bodies | Written as plain `String`, outside `Text` entirely. |

None of it blocks a single-language beta, which is why it is sequenced
last. Do not read "1160 strings are already keys" as "the app is nearly
localized" — the 392 and the 265 are where the real work is, and both
need a translator, not a refactor.

### CI is currently blocked on GitHub billing

Runs stop before any step with:

> The job was not started because recent account payments have failed or
> your spending limit needs to be increased.

Nothing in the repository can fix that — it needs Settings → Billing &
plans on the account. Until it is lifted, pushes produce no signal at
all, so treat any commit after `c9107be` as unverified rather than
passing.

macOS runners bill at **10x** the Linux rate, which is what makes this
easy to hit. Two changes reduce the burn:

- The workflow no longer runs a separate `xcodebuild build` before
  `xcodebuild test`. `test` builds the whole scheme anyway, so that was
  paying for the entire compile twice on the expensive runner.
- A `paths` filter keeps README- and docs-only commits from starting a
  macOS runner at all.

`concurrency.cancel-in-progress` is deliberately **false**. Superseding
runs looks frugal but repeatedly destroyed the only evidence of why a
build failed, turning each diagnosis into two runs instead of one.

## Before a beta release — items that need a human

These cannot be done from the repository and several have long lead times.

| Item | Why it matters | Owner |
|---|---|---|
| **Family Controls (Distribution) entitlement** | `FocusBlockingService` uses `FamilyControls` + `ManagedSettings`. Development is auto-granted; **distribution requires Apple's approval**, which can take weeks. Start this first. | Apple Developer account |
| `DEVELOPMENT_TEAM` | Currently empty — the project cannot be archived or uploaded. | Xcode signing |
| Bundle identifier | Moving from the generated `app.rork.…` placeholder to `com.frisfocus.app`. Permanent after first App Store release. | App Store Connect |
| Hosted Privacy Policy + Terms URLs | App Store Connect requires public URLs. `LegalContact.privacyURL` / `.termsURL` name where the app expects them; the in-app `LegalView` text is the source copy to publish there. | Web host |
| Support email | `LegalContact.supportEmail` (`support@frisfocus.app`) is linked from both legal documents. The mailbox has to exist before review. | Domain + mailbox |
| Legal entity + governing law | Neither document names the company behind FrisFocus or a jurisdiction. Deliberately not invented — fill in before publishing. | You |
| Crash reporting account | Planned: Sentry. Needs a project DSN before the SDK can report. | Sentry |
| APNs keys | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID` as Supabase secrets, or `send-push` skips silently. | Apple + Supabase |
| OpenRouter key | `OPENROUTER_API_KEY` as a Supabase secret, or the season conversation returns 503. | OpenRouter |
| Moderator allowlist | `MODERATOR_USER_IDS` (comma-separated user ids) as a Supabase secret. Until it is set, the `moderation` function refuses every request — reports pile up unread, which is the situation this replaced. | Supabase |
| Separate staging project | The app already points wherever `FRISFOCUS_*` env vars say (see `scripts/bootstrap-config.sh`), so a second Supabase project needs no code change — only provisioning, which costs money and is your call. Until then beta traffic and development share one database. | Supabase |
| APNs bundle id | `APNS_BUNDLE_ID` must match the new `com.frisfocus.app`, or `send-push` falls back to its default. | Supabase |
