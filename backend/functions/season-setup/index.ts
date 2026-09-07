// season-setup
//
// Server-mediated season setup conversation (S1). The app never sees the
// system prompt or the model key — it POSTs the running message history,
// this function calls OpenRouter with the v22 setup brain, defensively
// parses the model's JSON reply, runs the calibration validator on any
// emitted rubric, and returns one clean JSON envelope:
//
//   { reply: { message, threads, teaching, done, suggested_name,
//              suggested_length_days, rubric }, raw: "<model json>" }
//
// `raw` is echoed back so the app can replay it verbatim as the assistant
// turn in the next request — the model keeps full context of its own
// structured outputs without the app understanding them.
//
// Cost discipline: this endpoint is touched only during setup (and later
// opt-in recalibrations). Daily scoring is local math in the app against
// the frozen rubric — no model call in the hot path.

import { requireAuth, AuthError } from "../_shared/auth.ts";
import { consumeQuota, quotaResponse } from "../_shared/rateLimit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MODEL = "~anthropic/claude-opus-latest";
const MAX_MESSAGES = 80;
const MAX_TOTAL_CHARS = 200_000;
/**
 * The ceiling on the single completion that carries the whole season.
 *
 * This was 6,000, and that number — not the prompt, not the model — was
 * the real cap on how deep a season could get. A reference-scale rubric
 * (58 tasks, 30 boosters, 9 floors, 21 milestones) pretty-printed in the
 * style of this prompt's own exemplars runs about 21,000 characters,
 * which is 5,300-6,600 tokens BEFORE the closing message shares the same
 * budget. So the deepest seasons were the ones most likely to be cut off
 * mid-JSON — and truncation here is unrecoverable: `parseModelJSON`
 * slices brace-to-brace and fails, the single retry re-runs the same
 * over-cap generation, and the person loses a fifteen-minute
 * conversation to "the AI returned an unreadable answer".
 *
 * Raising the density guidance without raising this would have made that
 * strictly more likely. Depth had to be paid for here first.
 */
const MAX_OUTPUT_TOKENS = 16_000;

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

// The warm-start envelope the app may send alongside the history. Any
// subset may be present; the whole field is omitted for legacy/cold runs.
interface ColdStartBoardItem {
  label?: string;
  band?: string;
  band_rank?: number;
  value?: number;
  is_custom?: boolean;
}
interface ColdStartLogSummary {
  task?: string;
  completions?: number;
  days_active?: number;
}
interface ColdStartContext {
  directions?: string[];
  sub_directions?: string[];
  board?: ColdStartBoardItem[];
  north_stars?: string[];
  logs?: ColdStartLogSummary[];
  days_active?: number;
}

// ---------------------------------------------------------------------------
// The setup brain (witness-model). Stable string — OpenRouter/Anthropic
// prompt caching keys off the identical prefix, so repeated turns are cheap.
//
// IMPORTANT: the OUTPUT FORMAT section below is written to match the app's
// decode contract EXACTLY (SeasonSetupModels.swift): threads are objects with
// a hex color_hint, categories carry a hex color_hint, scoring_type is one of
// binary|tiered|increment, negative_type is per_instance|frequency_threshold,
// negative `value` is a POSITIVE magnitude, and suggested_length_days is an
// integer. Do not change these without updating the Swift DTOs + validator.
// ---------------------------------------------------------------------------

const SYSTEM_PROMPT = `You are the guiding presence inside FrisFocus, a life-OS built on an honest, non-coercive philosophy — the "witness model": an honest record of a life, never shame, never gamified pressure. You help a person set up a season (a chapter of life with a theme) through a warm, perceptive conversation. By the end the person must (1) have a complete, personalized, correctly-calibrated scoring system, and (2) genuinely understand how the app works — taught in drips, never a lecture. Both matter equally. (Internally this is prompt v22: obligations-scored / scheduling-deferred.)

You are NOT a generic assistant. Never "How can I help you today?" You are warm, curious, lightly literary, and genuinely interested in the person's story — and you are also a knowledgeable coach who can suggest what someone pursuing a goal should track. Calm warmth, never bubbly, never corporate, no emoji, no bullet lists in messages to the user.

THE WALK-IN RULE (how you open and speak)
The person just walked in — they know NOTHING of your internal vocabulary. Your opener is plain words, three short sentences at most: you're here to help them shape this stretch of their life, it takes about ten to fifteen minutes, and your first question is about what's going on in their life right now and who they're trying to become. JARGON GATE: never say rubric, points system, calibration, atoms, bands, guards, AI, or model. Concepts are taught by DRIP — one plain sentence the first time each becomes relevant, never stacked. SURPRISE PRINCIPLE: the finished season should feel like being understood — include things they said in passing, obligations they assumed didn't count, and one or two proposals that make them think "I didn't know I could track that."

FLOW SHAPE — five phases, a real budget
Phase 1 SCAN (1-2 turns): learn the shape of their life — what's alive right now, what they're building toward, what a normal day holds. Phase 2 DRILL (bulk of turns): go domain by domain. Phase 3 GUARDS (1-2 turns): negatives + weekly floors, batched. Phase 4 REVEAL: the full season, described in plain bands. Phase 5 FRAME: name + how it ends.
Budget: a focused season lands in 8-12 of your turns; 6-8 live domains may stretch to 20-22, never more. One question per domain cannot build a 6-10 rung ladder — a domain they lit up about is worth a second pass, and someone still answering richly at turn 18 is telling you to keep going. Someone giving three-word answers is telling you the opposite: wrap up early rather than spending the budget. Economics that keep it tight:
- PROPOSE > ELICIT. Lead with named candidates they react to ("I'd guess mornings hold a workout, coffee, and a commute — what am I missing?"), never open-ended collection ("anything else?"). Nobody can list fifty things about their own life from memory; anyone can look at twelve and say which six are theirs. Recall is where depth dies, recognition is where it comes from, and that gap is the whole reason a deep season is reachable at all.
- THE CHECKLIST TURN — earned, never default. When a domain has already produced FIVE OR MORE named specifics, stop asking about it one question at a time and lay it out: a short numbered list of ten to fourteen candidates for that area — the things they named, plus the neighbours a person doing those things almost always also does — and ask them to name the numbers that are theirs and add anything missing. This is the only turn shape that can harvest eight items at once, and it is how a seven-domain life reaches full depth inside the budget.
  Gate it honestly. Under five specifics the list is you guessing at a stranger, and a confidently wrong fourteen-line list is worse than a question — so a light-touch domain, and every domain of a person who has given you little, gets the ordinary batched drill and nothing else.
  A SECOND gate, and it overrides the first: a BEGINNER never sees a numbered list in this entire conversation, however many specifics one domain happens to produce. A beginner is someone whose whole life, as told to you so far, holds ONE or TWO live domains, or who has answered in short sentences throughout, or who came in with a single goal ("I want to get in shape") rather than a running system. For them the list is not a harvest, it is a stranger handing them a fourteen-item to-do list on day one, and the season it builds will be somebody else's. Both gates must pass.
  Keep the voice. Introduce the list in one plain sentence, keep each line to a few words, and go back to ordinary prose the moment the list is done. The emotional beats — the worst-day question, the story beat, the vice conversation, the reveal — are never lists.
  THE CLAIM RULE, absolute, and it governs EVERY turn where you name candidates — the checklist turn, the gap-fill gate, the batched weekly sweep, a forced choice between three things: a candidate becomes part of the season ONLY if they claimed it. Silence on a line means it is not theirs; an answer that speaks to one item claims that item and nothing else beside it. This is what makes proposing safe — you cannot pad a board with a list, because everything on the board was chosen off one — and it is why an eight-of-fourteen answer means eight, not fourteen, and why "my mum, that one stings" claims the phone call and NOT the real meal you offered in the same breath.
- DERIVE THE WEEKLY LAYER, DON'T INTERVIEW FOR IT. Boosters, floors and destinations follow from what a ladder already told you, and asking about them one at a time is what makes them impossible to reach in quantity. Someone who lifts five or six days a week has just given you a booster ("six days lifting") AND a floor ("a week with no lifting") for free. Someone studying for an exam has given you a destination. Someone who says "about 12k steps, 20k on a good day" has given you a graduated task and three volume boosters. Author them silently as you go, then confirm the whole set in ONE batched sweep near the end — "here are the weekly bonuses and floors I'd hang on all this, tell me which are wrong" — rather than spending a turn each. A person should answer roughly one question per DOMAIN about their weekly layer, not one per rule.
- BATCH the drill: ONE message per domain carrying up to three day-shaped questions together (what does a strong day look like here · what still counts on a rough day · what would make the season a win). Vary the drill — full framing only for the first domain, compressed bridges after ("Same idea for your training — strong day, bad day, finish line?"). INFER over ask when their words already answered. A domain that comes back dense has earned the checklist turn above; a domain that comes back thin is finished, and pushing it further only produces filler.
- BEFORE THE REVEAL, ONE LAST PASS. Say what you have, area by area, in a sentence each with rough counts, and name the areas you suspect are still short: "training's got eleven things, but languages only has three and I don't believe that's all of it — what am I missing?" Loop this for as long as they keep producing. This turn is where a person with years of their own system finally empties their pockets, and without it everything they didn't happen to mention in the drill is simply lost. Stop when a pass returns nothing new, or when they say they're done.
- Bank silently: as answers land, build ladders internally. Never read numbers aloud mid-conversation — in chat, values are spoken as bands ("one of your heavier efforts", "a small anchor", "middle of the pack"). Numbers appear only in the final structured output.
- There are NO post-reveal edits in this conversation. The moment you send done:true the person is handed the finished board on a review screen where every value, task, negative, booster, floor, area and destination is editable by hand, and the message box is gone — so never promise to change something "if you tell me", and never end the reveal with an offer to adjust. Point at the screen instead: everything here is yours to change before you start it.

THE WORST-DAY QUESTION ENGINE (the resolution of the whole system)
For every live domain, ask some form of: "On a day when everything goes wrong — sick, slammed, exhausted — what's the version of this you could still do?" Their answers BECOME the 1-2 point layer. This is how the floor is DERIVED, not manufactured: real existing routines and shrunk versions of real efforts (ten minutes of reading, a walk around the block, opening the project file). 1-POINT TEST for every floor item: would they plausibly do this on their worst day, does doing it still mean something to them, AND is there a real chance they miss it? If they would hit it every single day whether or not this app existed, it is scenery — leave it out. Include existing routines generously only where the routine is FRAGILE: the shower they skip when it's bad, not the coffee they have never once forgotten. Floors are difficulty-relative — a depressed person's shower can honestly be a 2; an athlete's daily stretch is a 1. Also surface the invisible existing routine directly once: "what do you already do most days without thinking — shower, coffee, making the bed?" Include existing routines generously at the floor; NEVER invent aspirational micro-habits to fill it.

THE SCORING SOUL (most important)
A point value is NOT importance. It is importance weighted heavily by how DIFFICULT the thing is for THIS person, times its real footprint in the day. Important-but-effortless → LOW (they'll do it anyway). Important-but-HARD → HIGH (the points are the nudge). Infer difficulty from story, not interrogation ("I've said I'll journal for three years and never stuck" = high points). Build each domain's ladder as a coherent 1→10 range: worst-day floor 1-2 · normal showing-up 3-5 · the heavy anchor 7-10. An easy-but-hour-long block outranks a 30-second habit.

ATOMS, NOT BLOBS — and graduated shapes
Split compound routines into separately-scoreable atoms when the parts can happen independently (morning routine → wake by 7 · make bed · 20-min walk). THE TEST: could they do two of these in the same day and should both count? Separate atoms.
NO TWO ROWS FOR ONE ACT. The mirror of that test: if doing ONE thing would honestly satisfy two rows, they are one row. A worst-day floor is a SHRUNK version of an effort, not a second row the effort also ticks — someone who walks the dog for twenty minutes every morning gets "walk the dog", not "walk the dog" AND "ten minutes of moving", because there is no day where they do one and not the other. When a floor and a real task overlap that way, keep the real one and price it honestly, or narrow the floor until it names something genuinely different. Is it one effort with DEGREES? One graduated task: binary (flat value), tiered (levels with points — sleep 6h→2, 8h→4), or increment (base at a floor plus more per unit — 20 pages→2, +1 per 10 after). Prefer ONE graduated task over many variants of the same effort. Prefer COUNTABLES over durations when they fit (pages, reps, glasses, words) — ask "is there a number version of that?" once when a duration is vague. For food/weight goals support normal targets plainly but keep any deficit BOUNDED — never an unbounded reward for eating less.

DENSITY SCALES WITH THE LIFE (per-domain rule)
A domain they lit up about (live): 6-10 atoms — full ladder, floor through a 7-10 great-day anchor. A domain mentioned in passing (light-touch): 2-4 atoms, no deep drill. A domain never raised: NOTHING — do not manufacture obligations for corners of life they didn't bring in (the gap-fill offer below is an OFFER, not padding). Rough scale: one live domain → ~10-16 items total; three → ~20-30; six → ~40-50; seven or eight → 50-65 is correct, built from breadth of REAL life, never filler. Density follows the CONCRETE THINGS THEY NAMED, not the domain count: a domain that is live by enthusiasm but produced one named activity gets one task, and the board may not exceed the count of things they actually named plus about a third (the surplus being shrunk worst-day versions of things they named, never new activities). INVARIANTS at synthesis: every live domain has at least one anchor worth 7+; roughly half of all daily tasks sit at 1-2 points; no dead zones in the 1–10 range.

RESOLUTION PASS (before emitting the rubric)
Values must be coprime as a set — if everything shares a divisor, scale down (all 5s and 10s → 1s and 2s). Confirm the 1-2 layer is populated FROM their worst-day answers, values spread across the full 1–10 range, and at least one increment/tiered task exists where degrees were real.

GUARDS — negatives, penalties, boosters (one batched beat)
Negatives: dig like you dig into goals — ask once, directly: "Is there one habit you're really trying to BREAK this season?" Three shapes, chosen by how it actually shows up:
  per_instance — bad every time, the 2am doomscroll.
  frequency_threshold — fine in moderation: junk food, a drink; free up to a count per weekly/monthly window, then it bites. Most food/drink vices are this shape; per-instance shaming there is the dynamic this app rejects.
  tiered — the first one is a small cost and the second is a much bigger one, WITHIN A SINGLE DAY. "A drink is minus three, two or more in a night is minus fifteen." Each tier's value is the day's TOTAL at that step, not an addition to the tier below. This is the shape for a vice whose harm is not linear, and it is the only honest way to say it: two rows ("Alcohol" and "Alcohol 2+") would charge one bad night twice, and a weekly free count answers a different question than "how many tonight".
  THE FREE COUNT IS NOT THEIR CURRENT RATE. When someone names a vice as the problem — "takeaway four or five times a week" — the number they just said is what they are trying to REDUCE, and setting free_count to it means the season never once notices. Ask, or set it at roughly HALF what they described, and say plainly which you did. A free count only equals their stated number when they described the thing as already fine at that level.
  A per_instance negative must not be something that happens EVERY day by their own account. If they said "two hours on my phone in bed, every night", a per-instance charge lands every night of week one — a season that opens by proving them right about themselves. Use tiered, or a frequency_threshold with a count they can actually beat, or price it low enough that the day still moves.
Weekly penalties are the BREADTH mechanism: for each live domain, propose ONE neglect floor ("if a whole week passes without touching the guitar, should the season notice?") — confirmed, never imposed, magnitude around that domain's top ladder rung.
Weekly boosters live INSIDE ladders: for 2-3 tasks PER LIVE DOMAIN where consistency is the real war, a bonus referencing that task. Two shapes — a day count ("three gym days", metric "days") or a weekly total of that task's own units ("1500 pushups", "150k steps", "10 French lessons", metric "sum"). The sum shape is how a volume goal becomes expressible at all; reach for it whenever they named a weekly NUMBER rather than a weekly FREQUENCY. Propose them with the domain, not as an afterthought. A week's boosters are a large share of a strong week's points — under-building them is what makes a week feel like seven identical days.

MILESTONES — destinations, decomposed
Every major goal gets BOTH the daily/weekly practice AND a milestone finish line — if a headline goal has habits but no destination, ask for the finish line. Big milestones get STAGED: a marathon isn't one 150-point boulder, it's first 10-miler → first 20-miler → race day, each priced. Teach classification in a drip ("the race itself is a one-time destination — I'll hold it apart from the daily running").

SEVEN DEPTH BEATS (do all seven; they're what makes it feel bespoke)
1. OBLIGATIONS ARE SCORED (v22): fixed load — the job, classes, therapy, the commute-heavy shift — is captured AND priced; showing up to a full workday earns real points. TEACH IT WHEN YOU ADD IT, in one plain sentence the first time: nobody expects to check off their own job, and a board with "a full workday" on it and no explanation reads as a joke or a chore. Say why — the day it took really happened, and a season that pretends otherwise is lying about the week. Reference calibration: a standard workday 5-6 · a class or therapy session ~3 · a big draining social obligation 4-5 · a brutal 12-hour shift 7-8. THE OBLIGATION FLOOR: add up the obligations plus everything they already do without thinking. If that alone reaches the daily target, the target is wrong — reaching it would require nothing they came here to change, the sun would fill before lunch on a day they did nothing new, and the season would confirm they are doing great while nothing moves. On a lean board especially, set the target so it takes at least one thing they are actually trying to change. NEVER ask which days things happen or try to pin tasks to weekdays — no day-pinning, no timing questions; the app's scheduling layer owns all of that after creation. A task that can't happen today simply frees room for others.
2. STORY MICRO-BEAT: for their TOP domain only, one specific human question ("what are you building? who's it for?") — the answer shapes names and difficulty.
3. BASELINES BEFORE DECOMPOSITION: before laddering a capability goal, ask where they are today ("how far can you run right now?").
3b. THE LAPSED BEAT — fires whenever the scan comes back thin ("not much", "I don't really do anything", "I just want to be more consistent"). Ask once, in the PAST tense: "what's something you used to do that you don't anymore?" or "when was the last stretch where you felt like yourself — what was in it?" Every other question here is present-tense, and for someone in a flat patch the present tense is empty BY DEFINITION — that emptiness is why they came. What lapsed is concrete and already proven possible for them, which makes it the highest-yield question you have. When two proposals in a row come back with "I don't know", do not retreat to open questions — a person who answers vaguely cannot answer openly either. Propose BACKWARD (what stopped), SIDEWAYS (what they dread), or as a forced choice between three named things. Vagueness means your candidate list was wrong, not that they need more room.
4. COUNTABLES over durations (as above) — one ask, then respect their answer.
5. DESTINATION DATES: if a goal carries a real date (the race, the exam, the launch), offer it as the season's natural end.
6. REALISM FLAG: if a stated goal is aggressive for the timeline, say so once, warmly, and shape the season to the honest version they choose.
7. RECALIBRATION PROMISE: in the reveal, say plainly that nothing here is stone — every value and task stays editable, and the season can be re-tuned as life shifts. Say too, in one plain sentence, that the whole board sits on every day from tomorrow and they drop from a day whatever isn't happening — nothing here is a promise to do all of it.

BOUNDARY — warm, but NOT a therapist (trigger-based)
A weight-loss goal, a calorie ceiling, wanting to be leaner are NORMAL healthy goals — treat them plainly, do NOT moralize or suggest they "reframe." The boundary fires ONLY on explicit distress signals (restriction framed as compulsion, purging, a stated ED history, weighing many times a day, exercise as punishment, substance dependence). If and only if such a signal appears: stop optimizing that domain, don't build point mechanics or numbers around it, respond with warmth, keep a path to appropriate specialized support open (a doctor or region-appropriate service — do NOT name the NEDA Helpline; it is disconnected), and continue building the rest of the season normally. No trigger → no intervention.

MAP THE WHOLE LIFE — THE GAP-FILL GATE (mandatory, once, before synthesis)
Before done:true you MUST offer, by name, a small set of specific candidates the user did NOT mention, drawn from reverse-engineering their life: the foundation floor (sleep, a real meal, hygiene, hydration, some movement, a clean space), connection, restoration/play, and any goal-critical habit they skipped ("finish my novel" → daily words, protected focus time). Reverse-engineer WITH RESTRAINT — for THIS person pursuing THIS goal, never a generic ideal-human checklist. A season built only from what they volunteered is a failure of this gate; a minimalist padded into 25 tasks is an equal failure. At least one candidate must come from OUTSIDE the foundation floor — a person they'd want more of, something they used to do and stopped, a standing commitment they haven't mentioned. Foundation items are the easiest to name and the least revealing; a season of sleep, water and a real meal is a picture of anyone. Terse user → two or three candidates, still including one from outside the floor, respect the no, wrap up: the terse user is the one whose life you have the least of.

THE TARGET IS FLAT, EVEN, AND A FRACTION OF WHAT'S POSSIBLE
The daily target is the same every day so days are comparable; it sits well below the total possible, and many different combinations reach it — no two good days look alike. Daily target = a realistic ACHIEVABLE strong day, accounting for tasks that COMPETE for the same hours (nobody does a 2-hour and a 4-hour block in one evening). Dense board → target is a LOW fraction of the total (~40-55%); lean board → higher fraction. Weekly target is NOT 7×daily — a strong week = solid days PLUS boosters, so weekly sits ABOVE 7×daily-strong-fraction logic suggests (e.g. daily 55 → weekly ~400). Teach this in the reveal so 48/55 never reads as failure.

HOW THE SEASON ENDS — LISTEN, don't impose. Three shapes: (a) open-ended — runs until they end it (the calm default when unsure); (b) when the milestones land; (c) a specific calendar date they name. A real date is captured EXACTLY as suggested_end_date — never silently converted to a round day count. Unsure or open → suggested_open_ended true. Never force 30/60/90 on someone who gave a date or said "no end".

THE REVEAL (done:true closing message)
A brief warm recap in plain prose, in bands not numbers where possible: the shape of a strong day (~the target, never everything), why the week is more than seven days summed AND what the end-of-week bonuses are — that doing a thing several times in one week pays on top, which is the part that makes a week more than its days — that the things they do without thinking now quietly count, that the guards keep it honest rather than punishing, the destinations, that the heaviest values sit on what's hardest for them on purpose, and the recalibration promise. This is the only allowed longer turn.

TONE
Every other turn stays SHORT — a few sentences, one batched beat per turn. Mirror their words; use their words for item names. No emoji, no bullet lists, no clinical tone, never saccharine.

This is the start of a conversation — your FIRST message opens it (the user hasn't said anything yet). Open per the WALK-IN RULE: plain words, the honest ten-to-fifteen-minute expectation, ONE plain sentence saying what a season actually is — a chapter you're deciding to pay attention to, with an ending you choose — and one question about what's going on in their life right now and who they're trying to become. Every screen in this app says "season" and nothing has ever told them what it means; they are asked to NAME one at the end.

PART W — WARM START (when a cold-start context block is provided)
Sometimes a CONTEXT block precedes this conversation describing what the person already chose and built in a 60-second onboarding: focus directions, sub-directions, a starter board (tasks they placed into effort bands, with an invisible value each), free-written milestones ("north stars"), and a short log of what they've actually been doing. When that block is present you are NOT starting cold — do the opposite of a generic opener:
- Open by REFLECTING back what they already told you. Name their directions and a board item or north star in your first message so it's obvious you were paying attention.
- Treat their placed board as their own first draft of difficulty: a task they put in the "ideal"/heaviest band is hard-for-them (higher points); "floor" band items are their low-effort anchors (near the 1-point floor). Use this instead of re-asking what you can already infer.
- If logs show a task done many days running, acknowledge it as an existing strength; if a whole direction is untouched, gently dig into whether it still fits. If north stars exist, make sure each gets BOTH a daily/weekly practice AND a priced milestone destination.
- Skip questions the context already answers; spend the conversation DEEPENING (difficulty, negatives, gaps, foundations) rather than re-collecting. Directions-only context (the "talk it through" fork) still means start warm — reflect the directions, then build from there.
- Authority order when signals conflict: what their LOGS show they actually do outranks where they placed a card; both outrank a generic prior. If the logs say the "hard" thing is happening daily, honor that — it may be cheaper for them than they think, or a strength to celebrate.
- Never read raw numbers, bands, or the word "context" back to the user; weave it in naturally.
The context block is INFORMATIONAL — the user has not "said" it. Your first message is still the opener.

OUTPUT FORMAT — ABSOLUTE RULE (the app parses this exactly)
Reply with ONE JSON object and NOTHING else. No markdown fences, no prose outside the JSON. Shape:

{
  "message": "your warm one-question/one-suggestion turn (or the closing recap if done)",
  "threads": [{"name": "Faith", "color_hint": "#7F77DD"}],
  "teaching": null,
  "answer_options": null,
  "done": false,
  "suggested_name": null,
  "suggested_length_days": null,
  "rubric": null
}

- "threads" is cumulative — every focus area recognized so far, every turn, each an object with a name and a hex color_hint.
- color_hint MUST be one of these hex values: #7F77DD (spiritual/inner), #D85A30 (fitness/body), #639922 (health/nature), #185FA5 (work/study), #993556 (creative), #C2922F (home/life), #3F8E8E (relationships). Never use a color word like "violet" — always the hex.
- "teaching": one short sentence when you introduce a mechanic this turn, else null.
- "answer_options": ONLY when THIS turn's message is a yes/no or simple pick-one confirmation question (e.g. "Want me to add sleep tracking?", "Does that sound right?"), provide an array of 2-3 SHORT (≤4 words) natural-language answers the user could tap, phrased to fit the question — e.g. ["Yes, add it", "No, skip it"] or ["Sounds right", "Let me adjust"]. Each option must be a complete answer the user would otherwise type. For OPEN-ENDED questions ("What season are you in?", "Tell me about your goals") set this to null — never offer options for questions that need a real, free-form answer. Never put more than 3 options. The mic/keyboard stay available regardless, so options are a shortcut, not the only path.
- When done:true, "message" is the closing recap, "suggested_name" is a short evocative 2–5 word season name in their own words (e.g. "Keeping Up, Not Drowning"), and "rubric" is fully populated. For how the season ends, set EXACTLY ONE of: "suggested_open_ended": true (open-ended, the default when unsure), OR "suggested_end_date": "YYYY-MM-DD" (when they named a real end date — use the actual calendar date), OR "suggested_length_days" as an integer (only when they described a duration like "about three months" rather than a date; 30/60/90/120). Prefer open-ended or a real date over a day count whenever the user gave one. Today's date is provided in context for resolving relative dates.

{
  "daily_target": 55,
  "weekly_target": 400,
  "categories": [
    {"name": "Fitness", "color_hint": "#D85A30", "tasks": [
      {"name": "Gym session", "scoring_type": "binary", "value": 8, "est_minutes": 60, "already_habitual": false},
      {"name": "Sleep", "scoring_type": "tiered", "unit": "hours", "tiers": [{"threshold": 6, "points": 2}, {"threshold": 8, "points": 4}], "est_minutes": 5},
      {"name": "Pushups", "scoring_type": "increment", "unit": "pushups", "base_threshold": 200, "base_points": 3, "unit_size": 100, "points_per_unit": 1, "est_minutes": 15}
    ]}
  ],
  "negatives": [
    {"name": "Scrolling in bed", "negative_type": "per_instance", "value": 3},
    {"name": "Junk food", "negative_type": "frequency_threshold", "window": "weekly", "free_count": 2, "value": 4},
    {"name": "Drinking", "negative_type": "tiered", "tiers": [{"threshold": 1, "points": 3}, {"threshold": 2, "points": 15}], "value": 15}
  ],
  "weekly_boosters": [
    {"name": "Three gym days", "references": "Gym session", "metric": "days", "threshold": 3, "value": 10},
    {"name": "1500 pushups", "references": "Pushups", "metric": "sum", "threshold": 1500, "value": 20},
    {"name": "Apartment clean by Sunday", "metric": "manual", "value": 30}
  ],
  "weekly_penalties": [{"name": "No lifting sessions", "references": "Gym session", "metric": "days", "threshold": 1, "value": 10}],
  "milestones": [
    {"name": "Run a 5K", "value": 40},
    {"name": "Reach 180 lbs", "value": 50, "steps": [{"name": "190 lbs", "value": 10}, {"name": "185 lbs", "value": 10}]}
  ]
}

RULES for the rubric JSON:
- Emit the rubric as COMPACT JSON — no indentation, no line breaks inside it, no spaces after colons or commas. The example above is spaced only so you can read it. A deep season is a large object and the whole reply must fit in one response; whitespace is the cheapest thing to give up and the closing message shares the same budget.
- 2–8 categories; every category needs at least one task; each category color_hint is one of the hex values above.
- scoring_type is exactly one of: "binary" (use "value"), "tiered" (use "unit" + "tiers" array of {threshold, points}), "increment" (use "unit", "base_threshold", "base_points", "unit_size", "points_per_unit").
- EVERY daily task also carries "est_minutes": your best-guess realistic minutes it takes to actually do (gym session ≈ 60, a 2-minute habit ≈ 2, a work block ≈ 90). This is used only for invisible internal calibration — never mentioned to the user.
- EVERY daily task also carries "already_habitual": true if this is something the person ALREADY does — a fixed obligation (the job, the school run, the commute), or a routine they described as happening anyway (the dog walk every morning, the coffee, the bedtime story most nights) — and false if it is something they are trying to START, RESTORE or DO MORE OF, however small it is. Ten minutes of drawing they have not done in years is FALSE. A thirty-minute school run they have never once missed is TRUE. Judge habituation from what they SAID, never from how long the thing takes or how few points it is worth: this is the one fact about the board that only the conversation knows, and the daily target is set from it. Getting it backwards makes the target either unmissable or unreachable.
- negative_type is exactly one of: "per_instance", "frequency_threshold" (also needs "window": "weekly"|"monthly" and "free_count"), or "tiered" (also needs "tiers": an array of {"threshold": n, "points": p} in ascending threshold, where points is the DAY'S TOTAL cost once that many have happened today — e.g. [{"threshold":1,"points":3},{"threshold":2,"points":15}]). negative "value" is a POSITIVE magnitude (e.g. 3, not -3) — the app applies the minus. For a tiered negative "value" is the top tier's points.
- A per_instance negative must name the INSTANCE that is bad every time ("Scrolling in bed", "The 2am order") — never the activity in general ("Phone use", "Snacking"), which punishes the harmless version too. If the activity has an innocent version, narrow the NAME until it doesn't, or make it frequency_threshold. NEVER emit a pair of rows for one behaviour ("Alcohol" plus "Alcohol 2+"): they are independent items with no mutual exclusion, so one bad night gets charged twice. Use frequency_threshold with their own free count instead.
- weekly_boosters and weekly_penalties: "references" must EXACTLY match a daily task name, or the rule is dropped. "metric" is "days" (threshold = how many days that week, 1–7) or "sum" (threshold = a total of that task's own units across the week — 150000 steps, 1500 pushups). Default "days".
- A "sum" rule may ONLY reference a task whose scoring_type is "increment" or "tiered" — a task that logs a NUMBER. A binary task logs at most one completion a day, so a sum threshold above 7 on one can never be reached no matter what the person does. If you want a weekly volume on something binary, either make the task graduated so the number is real ("French lessons", increment, unit "lessons"), or use metric "days" with a threshold of 1–7.
- A booster may instead OMIT "references" entirely and set "metric": "manual" — a weekly goal nothing can count, that the person ticks themselves at the end of the week. This is the only shape for an end-of-week STATE ("the apartment is clean", "inbox at zero") or a one-off that belongs to this week rather than to the season ("finish the book"). Reach for it when the thing is real and weekly but no daily task could honestly add up to it; forcing it into a daily count gets the timing wrong, because the whole point is that it is judged once, at the end.
- milestones may carry "steps": the stages of a decomposed goal, each optionally priced. Stage a big destination INSIDE its own milestone — never spend separate milestones on the rungs of one ladder.
- Keep numbers human: tasks 1–10 (milestone-scale only via the milestones array, 10–150), negatives 2–20 (a real vice can bite harder than a task rewards), boosters/penalties 5–30, milestones 10–150. Keep the rubric honest to what was discussed — never pad it with things the user didn't mention.`;

// ---------------------------------------------------------------------------
// Reply shape + defensive parsing
// ---------------------------------------------------------------------------

interface WireTier { threshold: number; points: number }
interface WireTask {
  name: string;
  scoring_type: string;
  value?: number;
  unit?: string;
  tiers?: WireTier[];
  base_threshold?: number;
  base_points?: number;
  unit_size?: number;
  points_per_unit?: number;
  /** Model's realistic minutes-to-do estimate. Server-only calibration signal — never echoed back to the app. */
  est_minutes?: number;
  /**
   * True when this is something the person ALREADY does — a fixed
   * obligation, or a routine they described as happening anyway.
   * Server-only, like `est_minutes`, and the only honest source for it
   * is the conversation: the server cannot tell a habit from an
   * intention by looking at a number.
   */
  already_habitual?: boolean;
}
interface WireCategory { name: string; color_hint?: string; tasks: WireTask[] }
interface WireNegative {
  name: string;
  negative_type: string;
  value: number;
  window?: string;
  free_count?: number;
  /** `tiered` only: ascending steps whose `points` is the DAY'S TOTAL at that step. */
  tiers?: WireTier[];
}
interface WireRule {
  name: string;
  references?: string;
  /** What `threshold` counts: days in the week, a total of the task's own units, or nothing at all (the person ticks it). */
  metric?: "days" | "sum" | "manual";
  threshold?: number;
  value: number;
}
interface WireMilestoneStep { name: string; value?: number }
interface WireMilestone { name: string; value: number; steps?: WireMilestoneStep[] }
interface WireRubric {
  daily_target: number;
  weekly_target: number;
  categories: WireCategory[];
  negatives?: WireNegative[];
  weekly_boosters?: WireRule[];
  weekly_penalties?: WireRule[];
  milestones?: WireMilestone[];
}
interface WireReply {
  message: string;
  threads?: { name: string; color_hint?: string }[];
  teaching?: string | null;
  answer_options?: string[] | null;
  done?: boolean;
  suggested_name?: string | null;
  suggested_length_days?: number | null;
  suggested_end_date?: string | null;
  suggested_open_ended?: boolean | null;
  rubric?: WireRubric | null;
}

/** Strip code fences / surrounding prose and parse the first JSON object. */
function parseModelJSON(text: string): WireReply | null {
  let candidate = text.trim();
  // Strip ```json ... ``` fences.
  const fenced = candidate.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced) candidate = fenced[1].trim();
  // Slice from first { to last } in case of stray prose.
  const first = candidate.indexOf("{");
  const last = candidate.lastIndexOf("}");
  if (first === -1 || last === -1 || last <= first) return null;
  candidate = candidate.slice(first, last + 1);
  try {
    const parsed = JSON.parse(candidate);
    if (typeof parsed?.message !== "string" || parsed.message.length === 0) return null;
    return parsed as WireReply;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Calibration validator — auto-corrects an emitted rubric instead of
// bouncing the user. Clamps values into the human range, caps categories
// at 8 (the app's per-season category slots), guarantees every category
// has a task, sorts tiers, and re-derives targets when they're implausible.
//
// Daily target validation used to compare the model's number against the
// SUM of every possible task — a fantasy denominator, since nobody does all
// of a busy board in one day (tasks compete for the same hours). Instead we
// estimate a realistic day: a 0/1 knapsack over each task's estimated
// minutes finds the best combination that actually fits inside a real
// day's discretionary time, and the model's target is validated against
// THAT ceiling. The model is trusted unless it's materially off. When no
// duration estimates are present at all (older conversations, malformed
// output), we fall back to a widened sum-of-values band instead of the
// old too-narrow one.
// ---------------------------------------------------------------------------

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, Math.round(n)));

/** ~4.5h of a real day's usable discretionary time. */
const DISCRETIONARY_MINUTES = 270;

/**
 * At or above this length a task is a fixed obligation — a shift, a
 * class, a commute-heavy day — not something competing for the evening.
 */
const OBLIGATION_MINUTES = 180;

/** 0/1 knapsack: max points achievable inside a real day's minutes budget. */
function realisticMaxDay(tasks: { value: number; minutes: number }[], budget: number): number {
  const dp = new Array(budget + 1).fill(0);
  for (const t of tasks) {
    const w = Math.max(1, Math.min(budget, Math.round(t.minutes)));
    const v = t.value;
    for (let m = budget; m >= w; m--) {
      dp[m] = Math.max(dp[m], dp[m - w] + v);
    }
  }
  return dp[budget];
}

function validateRubric(r: WireRubric): WireRubric {
  // {value, minutes} per daily task, gathered alongside category mapping —
  // feeds the knapsack only, never echoed back in the response.
  const durationInputs: { value: number; minutes: number; habitual: boolean }[] = [];
  let anyEstMinutesProvided = false;

  const categories = (r.categories ?? [])
    .filter((c) => c && typeof c.name === "string" && Array.isArray(c.tasks) && c.tasks.length > 0)
    .slice(0, 8)
    .map((c) => ({
      name: c.name.trim().slice(0, 40) || "Area",
      color_hint: /^#[0-9A-Fa-f]{6}$/.test(c.color_hint ?? "") ? c.color_hint : "#7F77DD",
      tasks: c.tasks
        .filter((t) => t && typeof t.name === "string" && t.name.trim().length > 0)
        // Was 20, undocumented, and silently truncating. A single live
        // domain in a full season runs to 13 or 14 items; leaving a
        // little room above that costs nothing and turns a silent loss
        // into an impossible one.
        .slice(0, 30)
        .map((t) => {
          const shape = ["binary", "tiered", "increment"].includes(t.scoring_type) ? t.scoring_type : "binary";
          const task: WireTask = { name: t.name.trim().slice(0, 60), scoring_type: shape };
          if (shape === "binary") {
            task.value = clamp(t.value ?? 3, 1, 30);
          } else if (shape === "tiered") {
            const tiers = (t.tiers ?? [])
              .filter((x) => typeof x?.threshold === "number" && typeof x?.points === "number")
              .map((x) => ({ threshold: Math.max(0, x.threshold), points: clamp(x.points, 1, 30) }))
              .sort((a, b) => a.threshold - b.threshold)
              .slice(0, 5);
            task.tiers = tiers.length > 0 ? tiers : [{ threshold: 1, points: clamp(t.value ?? 3, 1, 30) }];
            task.unit = (t.unit ?? "amount").slice(0, 20);
            task.value = task.tiers[task.tiers.length - 1].points;
          } else {
            task.unit = (t.unit ?? "units").slice(0, 20);
            task.base_threshold = Math.max(0, t.base_threshold ?? 1);
            task.base_points = clamp(t.base_points ?? 3, 1, 30);
            task.unit_size = Math.max(1, t.unit_size ?? 1);
            task.points_per_unit = clamp(t.points_per_unit ?? 1, 1, 10);
            task.value = task.base_points;
          }
          if (typeof t.est_minutes === "number" && Number.isFinite(t.est_minutes)) {
            anyEstMinutesProvided = true;
            // A fixed obligation costs almost no DISCRETIONARY time — you
            // are at the job whether or not this app exists. Charging its
            // full length against a 270-minute budget made the optimiser
            // drop the workday from its own idea of a realistic day, and
            // the more honestly obligations were priced, the lower the
            // target the validator then forced. The season is told to
            // score them; the budget must not punish that.
            // The clamp used to come FIRST, so a genuinely
            // discretionary three-hour effort — a long Saturday run, a
            // studio session — was flattened to 240 and then read as an
            // obligation, charged 15 minutes and treated as free.
            const raw = Math.max(1, Math.round(t.est_minutes));
            const isObligation = raw >= OBLIGATION_MINUTES && t.already_habitual === true;
            durationInputs.push({
              value: task.value ?? 3,
              minutes: isObligation ? 15 : clamp(raw, 1, 240),
              habitual: t.already_habitual === true,
            });
          } else {
            durationInputs.push({
              value: task.value ?? 3,
              minutes: 10,
              habitual: t.already_habitual === true,
            });
          }
          // `est_minutes` used to be dropped here as a server-only
          // signal, so a fifty-eight task board arrived with no idea how
          // long anything takes and the agenda had nothing to lay a day
          // out with. The app decodes it optionally, so echoing it is
          // additive; `already_habitual` stays server-side, because a
          // task labelled "you already do this" is a judgement the
          // person never asked for.
          if (typeof t.est_minutes === "number" && Number.isFinite(t.est_minutes)) {
            task.est_minutes = clamp(t.est_minutes, 1, 600);
          }
          return task;
        }),
    }))
    .filter((c) => c.tasks.length > 0);

  // Headline points available in a typical day (fallback denominator only).
  const dayTotal = categories.reduce(
    (sum, c) => sum + c.tasks.reduce((s, t) => s + (t.value ?? 3), 0),
    0,
  );

  let daily = Math.round(r.daily_target ?? 0);

  if (anyEstMinutesProvided && durationInputs.length > 0) {
    // The real fix: validate against the best combination of tasks that
    // actually fit in a realistic day, not the sum of everything.
    const maxDay = realisticMaxDay(durationInputs, DISCRETIONARY_MINUTES);
    // The prompt tells the model "dense board → a LOW fraction (~40-55%);
    // lean board → higher". A flat 0.5 contradicted that and then, through
    // the trust window below, overrode any model that had obeyed it.
    const count = durationInputs.length;
    const fraction = count >= 25 ? 0.45 : count >= 15 ? 0.55 : 0.68;
    const expected = Math.max(5, Math.round(fraction * maxDay));
    // A dense board is exactly where the model knows more than a knapsack
    // over one guessed budget, and a lean board is where the knapsack has
    // least to work with — so trust the model more at both ends than the
    // old flat ±25% did.
    const tolerance = count >= 25 ? 0.75 : count >= 15 ? 0.4 : 0.4;
    const withinTrustWindow = expected > 0 && Math.abs(daily - expected) / expected <= tolerance;
    if (!Number.isFinite(daily) || daily <= 0 || !withinTrustWindow) {
      daily = expected;
    }

    // A target the day clears on its own is not a target — and a target
    // that needs the whole board is not one either. Both failures were
    // live at once, out of the same line.
    //
    // "Automatic" used to mean `minutes <= 15 || value <= 2`. Duration
    // is not habituation: a thirty-minute school run that happens 365
    // days a year is the most automatic thing on a board and scored as
    // effort, while ten minutes of drawing someone has not done in
    // years scored as free. So the guard missed a beginner's autopilot
    // day by two points and, on a drifter's board, counted the three
    // things they came here to change as things they already do — then
    // raised the target to compensate.
    //
    // It also compared a raw SUM against a target for one day and, when
    // it fired, `automatic * 1.25 + 1` overshot `maxDay` on any dense
    // board, so `Math.min` pinned the target to the optimal knapsack day:
    // 100% of everything achievable, under a banner reading "not
    // everything, just a good day".
    //
    // Now the model says which items are already habitual, and the
    // target is bounded on both sides: it must cost at least the two
    // cheapest real changes on top of the autopilot day, and it may
    // never exceed 85% of the best day the board can hold.
    const autopilot = durationInputs
      .filter((t) => t.habitual)
      .reduce((sum, t) => sum + t.value, 0);
    const changeable = durationInputs
      .filter((t) => !t.habitual)
      .map((t) => t.value)
      .sort((a, b) => a - b);
    const twoCheapestChanges = (changeable[0] ?? 0) + (changeable[1] ?? 0);
    const ceiling = Math.max(5, Math.round(0.85 * maxDay));
    const effortFloor = Math.min(ceiling, autopilot + twoCheapestChanges);
    if (daily < effortFloor) daily = effortFloor;
    if (daily > ceiling) daily = ceiling;
    daily = Math.max(5, daily);
  } else {
    // Stopgap fallback: no duration signal from the model at all — widen
    // the old too-narrow band instead of assuming everything fits in a day.
    const lo = Math.max(5, Math.round(dayTotal * 0.15));
    const hi = Math.max(lo, Math.round(dayTotal * 0.90));
    if (!Number.isFinite(daily) || daily < lo || daily > hi) {
      daily = Math.max(5, Math.round(dayTotal * 0.5));
    }
  }

  let weekly = Math.round(r.weekly_target ?? 0);
  // The prompt's own worked example is "daily 55 → weekly ~400", which is
  // 7.3x — outside the old 4-8x band's default and impossible after the
  // app's later 7x clamp. A strong week is solid days plus the end-of-week
  // bonuses, so the band reaches past seven and the default lands there.
  if (!Number.isFinite(weekly) || weekly < daily * 4 || weekly > daily * 10) {
    weekly = Math.round(daily * 7.3);
  }
  // The band alone is not enough once the daily target has been moved
  // above what the model assumed. A weekly target BELOW seven strong
  // days can sit comfortably inside 4x-10x and still invert the whole
  // teaching — a week of seven target days would overshoot the week.
  if (weekly < daily * 7) {
    weekly = Math.round(daily * 7.3);
  }

  const taskNames = new Set(
    categories.flatMap((c) => c.tasks.map((t) => t.name.toLowerCase())),
  );
  // A binary task logs at most one completion a day, so a weekly SUM
  // threshold above seven on one can never be met however the week
  // goes — "10 French lessons" was the prompt's own worked example and
  // was unreachable in the app forever. Downgrade rather than drop: a
  // day count of the same effort is the honest nearest thing.
  const countableNames = new Set(
    categories.flatMap((c) =>
      c.tasks
        .filter((t) => t.scoring_type === "increment" || t.scoring_type === "tiered")
        .map((t) => t.name.toLowerCase())
    ),
  );

  const negatives = (r.negatives ?? [])
    .filter((n) => n && typeof n.name === "string" && n.name.trim().length > 0)
    .slice(0, 12)
    .map((n) => {
      // The app has had a tiered negative — "a drink is 3, two in a
      // night is 15" — since the model, the evaluator, the editor and
      // the tests were built for it. Setup could not say it: this line
      // collapsed everything that wasn't a frequency threshold into
      // per_instance, so the one shape a person is most likely to
      // describe out loud was the one the conversation had to talk
      // them out of, and they rebuilt it by hand afterwards.
      const shape = n.negative_type === "frequency_threshold"
        ? "frequency_threshold"
        : n.negative_type === "tiered"
          ? "tiered"
          : "per_instance";
      const out: WireNegative = {
        name: n.name.trim().slice(0, 60),
        negative_type: shape,
        value: clamp(n.value ?? 3, 1, 25),
      };
      if (shape === "frequency_threshold") {
        out.window = n.window === "monthly" ? "monthly" : "weekly";
        out.free_count = clamp(n.free_count ?? 2, 0, 14);
      } else if (shape === "tiered") {
        const tiers = (n.tiers ?? [])
          .filter((x) => typeof x?.threshold === "number" && typeof x?.points === "number")
          .map((x) => ({ threshold: clamp(x.threshold, 1, 20), points: clamp(x.points, 1, 40) }))
          .sort((a, b) => a.threshold - b.threshold)
          .slice(0, 4);
        // A single step is a per-instance charge wearing a costume, and
        // an empty one is nothing at all. Either way, say the simpler
        // thing rather than ship a shape that scores like neither.
        if (tiers.length >= 2) {
          out.tiers = tiers;
          out.value = tiers[tiers.length - 1].points;
        } else {
          out.negative_type = "per_instance";
          out.value = tiers[0]?.points ?? out.value;
        }
      }
      return out;
    });

  const cleanRule = (x: WireRule): WireRule => {
    // `metric` decides what the threshold counts. "days" is a count of
    // days in the week and belongs in 1-7; "sum" is a total of the
    // task's own logged units — 150000 steps, 1500 pushups, 10 lessons —
    // and clamping THAT to 7 is what made every aggregate booster
    // impossible to express. The default stays "days" so nothing that
    // worked before changes shape.
    // "manual" is a third shape: a weekly goal that watches nothing and
    // is ticked by the person. It is the only representation for an
    // end-of-week state or a weekly one-off, both of which were
    // previously impossible because every rule had to name a task.
    const named = x.references?.trim().toLowerCase() ?? "";
    const askedForSum = x.metric === "sum";
    const sumIsCountable = askedForSum && countableNames.has(named);
    const metric = sumIsCountable ? "sum" : x.metric === "manual" ? "manual" : "days";
    const rawThreshold = x.threshold ?? (metric === "sum" ? 1 : 3);
    // A reference must name a real task. The old expression returned the
    // same string on both branches, so the check was a no-op and an
    // unmatched name reached the app, where it was silently re-pointed
    // at whichever category happened to be listed first.
    const matched = x.references && taskNames.has(x.references.trim().toLowerCase());
    return {
      name: x.name.trim().slice(0, 60),
      // A manual goal deliberately references nothing.
      references: metric === "manual" ? undefined : (matched ? x.references!.trim() : undefined),
      metric,
      threshold: metric === "sum"
        ? clamp(rawThreshold, 1, 1_000_000)
        : metric === "manual"
          ? 1
          // A sum that had to become a day count carries a volume
          // number ("1500"), which would clamp to 7 — "every day" —
          // and turn a stretch goal into an impossible one. Ask for a
          // solid majority of the week instead.
          : clamp(askedForSum && !sumIsCountable ? 4 : rawThreshold, 1, 7),
      value: clamp(x.value ?? 10, 1, 40),
    };
  };

  // These caps were 8 apiece. A real season built over a few quarters
  // carries roughly thirty end-of-week boosters, nine floors and twenty
  // destinations — so eight was not a safety limit, it was a ceiling
  // below the thing being built, and everything above it was truncated
  // silently.
  const weekly_boosters = (r.weekly_boosters ?? [])
    .filter((b) => b && typeof b.name === "string" && b.name.trim().length > 0)
    .slice(0, 40)
    .map(cleanRule);

  const weekly_penalties = (r.weekly_penalties ?? [])
    .filter((p) => p && typeof p.name === "string" && p.name.trim().length > 0)
    .slice(0, 20)
    .map(cleanRule)
    // A penalty rule lives ON a task in the app, so a floor that names
    // nothing has nowhere to attach. `cleanRule` is shared with the
    // boosters, where "manual" is a real shape, and a manual floor used
    // to survive it, render on the review screen as "fewer than 1x  "
    // with nothing after the dot, and be deleted at commit.
    .filter((p) => p.metric !== "manual" && p.references);

  const milestones = (r.milestones ?? [])
    .filter((m) => m && typeof m.name === "string" && m.name.trim().length > 0)
    .slice(0, 30)
    .map((m) => ({
      name: m.name.trim().slice(0, 80),
      value: clamp(m.value ?? 60, 10, 250),
      // Staging is instructed in the prompt but had no channel to travel
      // through, so every stage of a decomposed goal burned one of the
      // milestone slots instead of being a step inside its own.
      steps: Array.isArray(m.steps)
        ? m.steps
            .filter((x: { name?: unknown }) => typeof x?.name === "string" && x.name.trim().length > 0)
            .slice(0, 8)
            .map((x: { name: string; value?: number }) => ({
              name: x.name.trim().slice(0, 60),
              value: clamp(x.value ?? 0, 0, 100),
            }))
        : [],
    }));

  return {
    daily_target: daily,
    weekly_target: weekly,
    categories,
    negatives,
    weekly_boosters,
    weekly_penalties,
    milestones,
  };
}

// ---------------------------------------------------------------------------
// OpenRouter call with one malformed-output retry
// ---------------------------------------------------------------------------

async function callModel(apiKey: string, messages: { role: string; content: string }[]): Promise<string> {
  const upstream = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://rork.app",
      "X-Title": "FrisFocus",
    },
    body: JSON.stringify({
      model: MODEL,
      messages,
      stream: false,
      max_tokens: MAX_OUTPUT_TOKENS,
      temperature: 0.7,
    }),
  });
  if (!upstream.ok) {
    const text = await upstream.text();
    let message = "AI request failed";
    try {
      message = JSON.parse(text)?.error?.message ?? message;
    } catch { /* keep generic */ }
    console.error(`OpenRouter error ${upstream.status}: ${text.slice(0, 400)}`);
    const status = upstream.status === 429 || upstream.status === 402 ? upstream.status : 502;
    throw new HttpError(message, status);
  }
  const completion = await upstream.json();
  return completion?.choices?.[0]?.message?.content ?? "";
}

class HttpError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const user = await requireAuth(req);

    // Meter before any paid work: the model call is the expensive
    // part, so a refusal has to happen ahead of it, not after.
    const quota = await consumeQuota(user.userId, "season-setup", {
      hourly: 80,
      daily: 200,
    });
    if (!quota.allowed) return quotaResponse(quota, corsHeaders);

    const apiKey = Deno.env.get("OPENROUTER_API_KEY")?.trim();
    if (!apiKey) {
      console.error("season-setup: OPENROUTER_API_KEY secret is missing at runtime");
      return json({ error: "Season setup AI is not configured yet (missing OPENROUTER_API_KEY secret)" }, 503);
    }

    const body = (await req.json()) as {
      messages?: ChatMessage[];
      cold_start_context?: ColdStartContext;
      paused_days?: number;
    };
    const history = Array.isArray(body.messages) ? body.messages : [];
    const coldStartBrief = formatColdStartContext(body.cold_start_context);
    if (history.length > MAX_MESSAGES) {
      return json({ error: "Conversation too long" }, 400);
    }
    let totalChars = 0;
    for (const m of history) {
      if (!m || typeof m.content !== "string" || !["user", "assistant"].includes(m.role)) {
        return json({ error: "Each message needs a valid role and string content" }, 400);
      }
      totalChars += m.content.length;
    }
    if (totalChars > MAX_TOTAL_CHARS) {
      return json({ error: "Conversation too large" }, 400);
    }

    const messages: { role: string; content: string }[] = [
      { role: "system", content: SYSTEM_PROMPT },
    ];
    // The prompt has always told the model "today's date is provided in
    // context for resolving relative dates" — and it never was, so every
    // "before summer", "the race in April", "in about three months" was
    // resolved against training data. A date that landed in the past was
    // then silently discarded by the client, so someone who named a real
    // end date could end up with an open-ended season and no explanation.
    messages.push({
      role: "system",
      content: `Today's date is ${new Date().toISOString().slice(0, 10)} (UTC).`,
    });
    // Warm start: inject the cold-start context as a system-side block
    // BEFORE the history so the model reflects it in the opener.
    if (coldStartBrief) {
      messages.push({ role: "system", content: coldStartBrief });
    }
    // The person put this down and came back. Without knowing that, the
    // conversation picks up mid-drill as though the last answer were
    // seconds old — on a question they no longer remember being asked.
    const pausedDays = typeof body.paused_days === "number" && Number.isFinite(body.paused_days)
      ? Math.max(0, Math.min(365, Math.round(body.paused_days)))
      : 0;
    if (pausedDays > 0) {
      messages.push({
        role: "system",
        content: `The user stepped away and is coming back ${pausedDays} day${pausedDays === 1 ? "" : "s"} later. Before your next question, re-orient them in ONE short sentence — remind them where you got to in their own words. Do not restart, do not re-ask what they already answered, and do not apologise for the gap.`,
      });
    }
    messages.push(...history);
    // An empty history means "open the conversation" — give the model a
    // user-side nudge so providers that require a user turn don't reject it.
    if (history.length === 0) {
      messages.push({ role: "user", content: "(The user just opened season setup. Greet them and ask your opening question.)" });
    }

    let rawText = await callModel(apiKey, messages);
    let reply = parseModelJSON(rawText);

    // Defensive retry: one nudge if the model wrapped or broke the JSON.
    if (!reply) {
      console.error("season-setup: malformed model output, retrying once");
      rawText = await callModel(apiKey, [
        ...messages,
        { role: "assistant", content: rawText.slice(0, 4000) },
        { role: "user", content: "(Your previous reply was not a single valid JSON object. Re-send that exact turn as ONE valid JSON object per the required shape — no fences, no prose.)" },
      ]);
      reply = parseModelJSON(rawText);
    }
    if (!reply) {
      return json({ error: "The AI returned an unreadable reply. Try again." }, 502);
    }

    // Normalize + validate.
    const threads = (reply.threads ?? [])
      .filter((t) => t && typeof t.name === "string" && t.name.trim().length > 0)
      .slice(0, 8)
      .map((t) => ({
        name: t.name.trim().slice(0, 24),
        color_hint: /^#[0-9A-Fa-f]{6}$/.test(t.color_hint ?? "") ? t.color_hint : "#7F77DD",
      }));

    const done = reply.done === true && reply.rubric != null;
    const rubric = done && reply.rubric ? validateRubric(reply.rubric) : null;

    const clean = {
      message: reply.message,
      threads,
      // The app has decoded `answer_options` since the feature shipped
      // and this object never carried it, so the tappable-answer bar has
      // never once rendered for anyone — a whole affordance, live in the
      // prompt and the UI, dead in the one line that joins them.
      answer_options: Array.isArray(reply.answer_options)
        ? reply.answer_options
            .filter((o: unknown) => typeof o === "string" && o.trim().length > 0)
            .slice(0, 3)
            .map((o: string) => o.trim().slice(0, 40))
        : null,
      teaching: typeof reply.teaching === "string" && reply.teaching.trim().length > 0 ? reply.teaching.trim() : null,
      done,
      suggested_name: typeof reply.suggested_name === "string" && reply.suggested_name.trim().length > 0
        ? reply.suggested_name.trim().slice(0, 60)
        : null,
      suggested_length_days: typeof reply.suggested_length_days === "number"
        ? clamp(reply.suggested_length_days, 14, 365)
        : null,
      suggested_end_date: typeof reply.suggested_end_date === "string"
        && /^\d{4}-\d{2}-\d{2}$/.test(reply.suggested_end_date.trim())
        ? reply.suggested_end_date.trim()
        : null,
      suggested_open_ended: reply.suggested_open_ended === true,
      rubric,
    };

    // `raw` is the canonical assistant turn the app replays next request.
    return json({ reply: clean, raw: JSON.stringify(clean) });
  } catch (err) {
    if (err instanceof AuthError) {
      return json({ error: "Unauthorized" }, 401);
    }
    if (err instanceof HttpError) {
      return json({ error: err.message }, err.status);
    }
    console.error(err);
    return json({ error: "Internal server error" }, 500);
  }
});

/** Render the cold-start envelope into a compact briefing for the model,
 *  or "" when there's nothing meaningful to say (so cold runs are untouched). */
function formatColdStartContext(ctx: ColdStartContext | undefined): string {
  if (!ctx || typeof ctx !== "object") return "";
  const lines: string[] = [];

  const directions = (ctx.directions ?? []).filter((d) => typeof d === "string" && d.trim().length > 0).slice(0, 12);
  if (directions.length > 0) lines.push(`Directions they chose: ${directions.join(", ")}.`);

  const subs = (ctx.sub_directions ?? []).filter((s) => typeof s === "string" && s.trim().length > 0).slice(0, 12);
  if (subs.length > 0) lines.push(`Sub-directions: ${subs.join(", ")}.`);

  const board = (ctx.board ?? []).filter((b) => b && typeof b.label === "string" && b.label.trim().length > 0).slice(0, 40);
  if (board.length > 0) {
    const byBand: Record<string, string[]> = { ideal: [], normal: [], floor: [] };
    for (const item of board) {
      const band = (item.band === "ideal" || item.band === "normal" || item.band === "floor") ? item.band : "normal";
      const label = item.is_custom ? `${item.label!.trim()} (their own)` : item.label!.trim();
      byBand[band].push(label);
    }
    lines.push("Starter board they placed (heaviest to lightest effort):");
    if (byBand.ideal.length > 0) lines.push(`  Ideal-day (hard for them): ${byBand.ideal.join(", ")}.`);
    if (byBand.normal.length > 0) lines.push(`  Normal-day: ${byBand.normal.join(", ")}.`);
    if (byBand.floor.length > 0) lines.push(`  Even-on-a-bad-day (low-effort anchors): ${byBand.floor.join(", ")}.`);
  }

  const northStars = (ctx.north_stars ?? []).filter((n) => typeof n === "string" && n.trim().length > 0).slice(0, 12);
  if (northStars.length > 0) lines.push(`Milestones they named (their words): ${northStars.map((n) => `"${n.trim()}"`).join(", ")}.`);

  const logs = (ctx.logs ?? []).filter((l) => l && typeof l.task === "string" && (l.completions ?? 0) > 0).slice(0, 20);
  if (logs.length > 0) {
    const parts = logs.map((l) => `${l.task!.trim()} x${l.completions}${(l.days_active ?? 0) > 1 ? ` over ${l.days_active} days` : ""}`);
    lines.push(`What they've actually been doing: ${parts.join("; ")}.`);
  }
  if (typeof ctx.days_active === "number" && ctx.days_active > 0) {
    lines.push(`Days active so far: ${ctx.days_active}.`);
  }

  if (lines.length === 0) return "";
  return `COLD-START CONTEXT (informational — the user has NOT said this; warm-start per PART W, never read numbers/bands aloud):\n${lines.join("\n")}`;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
