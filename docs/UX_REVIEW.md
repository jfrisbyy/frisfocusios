# FrisFocus UX review — 20 November 2026

A walk through the app as a brand-new user, reconstructed from the SwiftUI
source (there was no simulator, so nothing here was seen running). File and
line references were read in code; timings, bounce points and contrast ratios
are estimates.

Each problem is marked **Fixed** (changed on branch
`claude/elegant-ride-x4cifd` the same day), **Partly fixed**, or **Open**
(needs a product decision).

## Verdict

The core loop is learnable: tap a row, the sun rises. The teaching layer is
better than most — a skippable hands-on tour, a "How FrisFocus moves" help
sheet, one-per-session concept lessons, and good social empty states.

The problem is everything before and around that loop. A new user passes about
13 screens and a sign-in wall, was promised "about a minute" twice, and on the
quick path landed on an empty plan. After that, adding a real task, changing
the daily goal and reaching season settings were hidden behind a 9pt "TAP FOR
SEASON DETAILS" label. Vocabulary is the biggest tax: roughly 25 coined terms,
several with three or four synonyms.

## First-run funnel (quick path)

| # | Screen | Required? |
|---|---|---|
| 1 | Welcome: "Get started" / "Explore a demo first" / "Sign in" | — |
| 2–5 | Manifesto, four cards ("Skip" available) | Skippable |
| 6 | Age check (date wheel) | Yes |
| 7 | Account: Apple or Google, no guest option | Yes |
| 8 | Claim name: unique @handle (network check), photo optional | Yes |
| 9 | Fork: build it quickly vs "Talk it through" (10–15 min) | Yes |
| 10 | "What are you focused on right now?" — at least one tile | Yes |
| 11 | One board page per direction: sort cards into "Even on a bad day / A normal day / An ideal day" | Yes |
| 12 | "What would make this season a win?" | Skippable |
| 13 | "What does a good day look like?" — point target | Yes |
| 14 | "Name this season." plus how it ends | Yes |
| 15 | People card ("Not now" exits) | Skippable |
| 16 | Invites (only if they chose "Bring your people") | Skippable |
| 17 | Home, with an empty Today's plan; the tour starts | — |

- **Required decisions:** about 9.
- **Time to first value:** about 3–5 minutes on the quick path, 15–20 on the
  AI path. The demo is the only route to value in under 30 seconds.
- **Likeliest bounce points:** the account wall (7), the handle check (8), and
  the empty Home (17).

## Top problems, by expected impact

| # | Problem | Status |
|---|---|---|
| 1 | **Empty Home after a long setup.** The quick path commits every task unpinned by design (`Store.swift`), after the fork promised "The sun starts moving today". | **Partly fixed** — the promise is corrected ("You'll pick today's few at the end"). Auto-placing a starter day is open. |
| 2 | **The two paths teach opposite models.** The AI path ends "It's all on today. Clear what isn't happening"; the quick path ends "today starts empty". | **Open** — pick one landing state. |
| 3 | **Location alert at first launch, unprimed.** Home requested location while the onboarding cover was still up. | **Fixed** — waits until onboarding is over, with an explanation card (Allow / Not now). |
| 4 | **Creating a real task is buried.** "Add to today" only made to-dos or pinned existing items; "New task" needed a sun tap, a scroll and a collapsed section, and the new task did not land on today. | **Fixed** — "New task" is in the Add-to-today sheet and lands on today. |
| 5 | **The daily goal could not be edited after setup.** No view wrote it. | **Fixed** — stepper in season settings; a manual value sticks. |
| 6 | **Synonym sprawl.** area / category / direction / focus area; pin / add to today / rhythm / schedule; negative / avoid / reduce / behavior / weekly limit / penalty; band / block / bucket. "Floor" meant both the bad-day band and a weekly penalty. | **Partly fixed** — "floor" → "Weekly minimum", "negative" → "thing to avoid". App-wide consolidation is open. |
| 7 | **Wayfinding.** Icon-only nav pill resting at 50% opacity; stats, season settings, boosters and "New task" behind a 9pt label; editing a task is long-press only; undo is shake only. | **Partly fixed** — nav rests at 85%. Labels and a real Season destination are open. |
| 8 | **AI path rough edges.** Voice was the default input (two unprimed system alerts); the wait state said "FrisFocus is listening…" while the model was thinking; raw server errors reached the screen; progress has no "about N questions left". | **Mostly fixed** — keyboard first, honest wait copy, humane errors. Progress indicator is open. |
| 9 | **Copy contradicted the promise.** "Nothing is ever public" vs "Your public story"; "never nag" vs "Fires every day — no skipping … Only streaks survive"; "You don't chase a number here" vs an 86pt score and "GOAL · N". | **Partly fixed** — the first two are reworded. The score-vs-"no number" tension is open. |
| 10 | **Pacts have no visible door.** They sat behind "Start a circle or join one". | **Fixed** — "Start a circle or a pact". |
| 11 | **Accessibility.** 669 uses of primary text at ≤65% opacity (0.45 is about 2.5:1 on the wheat background); 278 font calls at 10pt or smaller; pills about 25pt tall; Reduce Motion read in 47 of 274 view files; light mode forced. Good: fonts scale via UIFontMetrics (capped at AX2) and there are 443 accessibility labels. | **Partly fixed** — tap areas enlarged on the work-screen pills. Contrast floor is open. |
| 12 | **Internal language on screen.** "Zone 3 of 4", "Apple's error: …", "New negative", "rubric". | **Fixed.** |

## What was changed

### Copy

| Where | Old | New |
|---|---|---|
| Welcome | "Set up takes about a minute." | "Setup takes a few minutes." |
| Fork, AI failure banner | "Build it in about a minute" | "Build it in a few minutes" |
| Fork | "The sun starts moving today." | "You'll pick today's few at the end." |
| Board, last page | "Start tracking" | "Continue" |
| Calibrate | "…lands near N —" | "…lands near N points —" |
| People card | "Nothing is ever public." | "Nothing is public unless you choose it." |
| Season options tiles | "Add a task to today" / "Linked habit streaks" / "Bonus point multipliers" | "Add a task to your season" / "Habits done in a chain" / "Weekly & monthly bonuses" |
| Capture review | "Your public story" / "Public story + more" | "All your friends, for a day" / "Friends' story + more" |
| Circles | "Start a circle or join one" | "Start a circle or a pact" |
| Golden Hour settings | "Fires every day — no skipping", "Only streaks survive." | "Fires once a day"; second line removed |
| Task edit sheet | "New negative" / "Edit negative" | "New thing to avoid" / "Edit thing to avoid" |
| Season review | "End-of-week floor(s)" | "Weekly minimum(s)" |
| AI setup wait state | "FrisFocus is listening…" | "Thinking — this can take a few seconds…" |
| AI setup errors | "Setup request failed (503)." and raw server text | "The conversation couldn't connect. Try again in a moment." |
| Notes, Milestones, Signal | "Zone N of 4" | removed |
| Scoring settings | "rubric … negatives" | "season … things to avoid" |

### Behaviour

- **Location prompt** — never fires during onboarding; a card explains it
  first. "Not now" is remembered and not re-asked. No Settings toggle to
  re-offer it yet.
- **AI season setup** — opens on the keyboard; the mic is one tap away.
- **Daily goal** — editable in season settings (1–500 points); a manual value
  is no longer overwritten by auto-recalibration.
- **New task** — available from the Add-to-today sheet and placed on today.
- **Tap targets** — AGENDA, FOCUS, ⋯ and the swipe-hint dismiss have larger
  hit areas at the same drawn size. The ⋯ menu's area may be unchanged.
- **Navigation bar** — rests at 85% opacity instead of 50%.

## Open decisions

| Decision | Trade-off |
|---|---|
| Auto-place a starter day on the quick path | Instantly checkable Home; loses "choose the day's few" as the first act |
| Shorten the funnel: manifesto to one card, merge the last three setup screens with defaults, move people and invites after the first check-off | Faster value; less philosophy up front |
| Sign in after first value (local-first) | Removes the biggest wall; handle, sync and restore all assume an account exists |
| One word per concept (area, pin, avoid, bonus, block) | Touches hundreds of strings and the AI prompt |
| Labelled navigation plus a real Season destination | More findable; less minimal |
| Contrast floor (no body text under 70% opacity) | More readable; changes the visual quietness across the app |
| One landing state for both setup paths | Consistency; one path's closing ritual changes |
| "About N questions left" in the AI conversation | Sets expectations; the conversation length is not fixed |

## Glossary: terms met in the first 10 minutes

| Term | First appears | Explained? | Plain gloss |
|---|---|---|---|
| sun | Welcome | Yes (manifesto 2, tour) | Today's progress |
| season | Manifesto 3; Account "every season kept" | Only at the last quick-path screen; never on the AI path | A named stretch of weeks with its own tasks and goal |
| direction / focus area / area / category | Direction pick, board, review, task form | No; four names for one thing | Area of life |
| bands (bad / normal / ideal day) | Board page | Partly | How big the task is for you |
| floor | Board dialog; review | Had two meanings; the weekly one is now "weekly minimum" | Bad-day task |
| points / priced / GOAL | Manifesto 2; Calibrate; Home | Partly | What a task is worth to you |
| strong day | Calibrate | Yes | Daily point target |
| win / milestone / big win | Capstone, then Home "Milestones" | The link between them is never stated | One-time season goal |
| board / library / "your lists" | Board page, tour, add sheet | No | All your season's tasks |
| task vs to-do | Tour step 1 | Only in the capture sheet | Repeating and scored / one-off |
| pin / add to today / rhythm / Pin to days | Tour | Yes, but four phrasings | Put on a day / repeat on days |
| Today's plan vs Agenda | Home | Agenda has its own explainer | List view / time-of-day view |
| block / bucket | Tour, Agenda | Partly | Flexible slot with options |
| proof | People card | Tour step 3, lesson | Photo sent to chosen friends |
| story | Friends | Lesson | Photo your friends see for 24h |
| cheer | Notification card | Lesson | One-tap encouragement |
| circle | Sign-in sheet, Friends | Yes | Small group with a shared goal |
| pact | Profile subtitle | Yes; the door is now labelled | Two-person commitment |
| Golden Hour | Circle settings | Yes | Daily 5-minute group photo moment |
| booster | Review, Season options | Yes in its manager | Weekly bonus |
| avoid / reduce / weekly limit / skip penalty | Review, options, task form | Each locally, never unified | Things that subtract points |
| trains | Season options | Now hinted as "Habits done in a chain" | Habits done in sequence |
| grove | Focus sheet | One line | Group focus session |
| Needs You / Today's read | Home | Read: lesson. Needs You: no | Suggested next things |
| Cadence / Esengo | Settings | No | Companion routines app |
