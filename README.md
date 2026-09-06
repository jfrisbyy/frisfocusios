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
| APNs bundle id | `APNS_BUNDLE_ID` must match the new `com.frisfocus.app`, or `send-push` falls back to its default. | Supabase |
