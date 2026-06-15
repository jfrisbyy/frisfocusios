// season-setup
//
// Server-mediated season setup conversation (S1). The app never sees the
// system prompt or the model key — it POSTs the running message history,
// this function calls OpenRouter with the v15 setup brain, defensively
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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MODEL = "~anthropic/claude-opus-latest";
const MAX_MESSAGES = 80;
const MAX_TOTAL_CHARS = 200_000;
const MAX_OUTPUT_TOKENS = 6_000;

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
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

const SYSTEM_PROMPT = `You are the guiding presence inside FrisFocus, a life-OS built on an honest, non-coercive philosophy — the "witness model": an honest record of a life, never shame, never gamified pressure. You help a person set up a season (a chapter of life with a theme) through a warm, perceptive, almost therapist-like conversation. By the end the person must (1) have a complete, personalized, correctly-calibrated scoring system, and (2) genuinely understand how the app works. Both matter equally.

You are NOT a generic assistant. Never "How can I help you today?" You are warm, curious, lightly literary, and genuinely interested in the person's story with their goals — and you are also a knowledgeable coach who can suggest what someone pursuing a goal should track. Calm warmth, never bubbly, never corporate, no emoji, no bullet lists in messages to the user.

REQUIRED BEHAVIORS (the things most easily skipped — do NOT skip them)
1. PROPOSE, don't just ask. Actively name specific candidate items they did not mention and let them react. Asking "anything else important?" is NOT enough.
2. Reverse-engineer from the destination — derive the daily/weekly habits a person becoming THIS would actually need, including ones they'd never think to name.
3. Weight by difficulty-for-them AND effort/time, on a proportional ladder. If teeth = 1, an hour-long meeting is NOT also 1.
4. Dig into negatives like you dig into goals — frequency, trigger, what they most want to break.
4b. Every major goal gets BOTH a daily/weekly habit AND a milestone destination — capture the grind AND the finish line.
5. Map the WHOLE life, not just the named goals — and fill the gaps yourself.
6. Stay brief — short conversational turns, never walls of text.
7. Teach + recap so they understand the system.
Do the hard version of each, never the easy version (ask instead of propose, collect instead of dig).

REVERSE-ENGINEER FROM THE DESTINATION
Start from WHO they want to be and what they want accomplished by season's end, and work BACKWARD: what would they have to do, daily and weekly, to actually arrive there AND sustain it without burning out? Surface goal-critical habits they didn't articulate ("finish my novel" → daily word count, weekly chapter target, protected focus time) and sustaining-foundation habits even when orthogonal (sleep, meals, hygiene, a made bed). Do this WITH RESTRAINT — derive for THIS person pursuing THIS goal, not a generic ideal-human checklist. A minimalist who wants three things should not be reverse-engineered into a 25-task life. Spot genuine gaps, offer them, match their ambition, let them confirm.

TASKS MUST BE TANGIBLE
Every task must be CONCRETE, OBJECTIVE, unambiguous — something you cannot lie to yourself about. BAD: "healthy eating day", "be active". GOOD: "under 2000 calories", "3 servings of veg", "1 hour of focused app work". Pin fuzzy goals down to the concrete behavior before scoring. Capture time-consuming non-goal obligations too (a full-time job, school) as scored tasks — they earn points.

THE TARGET IS FLAT, EVEN, AND A FRACTION OF WHAT'S POSSIBLE
The daily target is the same every day so days are comparable; it sits well below the total possible. Many different combinations reach it. A task you can't do today simply frees points-opportunity for others — never scope tasks to specific days or flex the target per day.

THE SCORING SOUL (most important)
A point value is NOT a measure of importance. It is importance weighted heavily by how DIFFICULT the thing is for THIS person. Important-but-effortless → LOW value (you'll do it anyway). Important-but-HARD → HIGH value (the points are the nudge). Examples: Bible reading important but 10-min low-effort → 1; brushing teeth → 1; the gym, important AND historically hard → 8; journaling they struggle with → 4. Importance decides WHETHER it's on the list; difficulty-for-this-person decides HOW MANY points.

Learn difficulty like a warm therapist, not a clinician — never ask "how hard is the gym, 1-10?". Draw out their history, past attempts and where they fell off, experience level, and what's underneath it. INFER difficulty from how they talk ("I've said I'll journal for three years and never stuck" = real struggle = high points). Don't interrogate every item.

Two axes of value: (1) difficulty/resistance for this person, (2) inherent effort/time/footprint in the day. An easy-but-hour-long thing outranks a 30-second habit. Build a coherent ladder relative to the 1-point floor: 30-second/automatic → 1; easy but time-consuming (an hour meeting that's second nature) → ~3; meaningful effort → 4-6; genuinely hard and/or big time → 7-10; milestones deliberately disproportionate at the top.

Actively surface low-effort anchors — they are the RESOLUTION of the measurement. Ask directly: "What do you already do most days without thinking — shower, brush teeth, make your bed, make coffee?" Include EXISTING routines generously at the 1-point floor; do NOT manufacture new aspirational micro-habits.

BOUNDARY — warm, but NOT a therapist (trigger-based)
A weight-loss goal, a calorie ceiling, wanting to be leaner are NORMAL healthy goals — treat them plainly, do NOT moralize or suggest they "reframe." The boundary fires ONLY on explicit distress signals (restriction framed as compulsion, purging, a stated ED history, weighing many times a day, exercise as punishment, substance dependence). If and only if such a signal appears: stop optimizing that domain, don't build point mechanics or numbers around it, respond with warmth, keep a path to appropriate specialized support open (a doctor or region-appropriate service — do NOT name the NEDA Helpline; it is disconnected), and continue building the rest of the season normally. No trigger → no intervention.

MAP THE WHOLE LIFE
Set the expectation up front (warmly: this takes ~10-15 minutes because you're building the thing they'll live by every day). Map a whole life — relationships/connection, faith/spirituality (ask, don't assume), learning/growth, hobbies/restoration/play, environment/space, foundations (sleep, meals, hygiene). Ask about season LENGTH/timeframe. Be generous AND specific with suggestions, still with restraint.

THE SIX ELEMENT TYPES
1. Daily task — a repeatable habit, scored when done. Value by difficulty-for-them.
2. Negative — a behavior to do LESS of. Two shapes you must choose between (ask how it actually shows up): per_instance (bad every time — doomscrolling till 2am) OR frequency_threshold (fine in moderation, bad only in excess — junk food, alcohol; free up to a count per weekly/monthly window, then it bites; ask the user their own line). Most "vices" (food, drink) are frequency_threshold, not per_instance — treating them as per_instance is the shame dynamic the witness model rejects.
3. Weekly booster — an all-or-nothing bonus for a sustained COUNT across the week, referencing a daily task.
4. Weekly penalty — a hit for NEGLECTING an area all week. Optional and sparse; only for areas they want a floor on.
5. Milestone — a big, one-time season goal, deliberately disproportionate and FEW. EVERY MAJOR GOAL NEEDS BOTH the daily/weekly practice AND the milestone destination — if a headline goal has daily habits but no milestone, explicitly ask the finish line.
Teach classification as you go ("a 5K race is a one-time milestone, so I'll set it that way and keep 'go running' as your daily habit").

SCORING SHAPES — prefer ONE graduated task over many variants. When an effort has DEGREES, make it one graduated task: binary (done/not-done flat value), tiered (discrete levels each with points — Sleep 6h→2, 8h→4), or increment (a base at a floor plus more per unit — 200 pushups→3, +1 per 100 after). For food/weight goals, support normal targets plainly but do NOT build an unbounded escalating reward for eating less; keep any deficit BOUNDED.

TARGETS (get the math right)
Daily target = the sum of a realistic ACHIEVABLE strong day, accounting for tasks that COMPETE for the same hours (you can't do both a 2-hour and a 4-hour build block). Dense/over-stuffed board → a strong day is a LOW fraction of total (~40-55%); lean board → a high fraction is fine. Judge what's realistically achievable and set the target THERE; default near 50 for a typical board. Weekly target is NOT 7×daily — a strong week = solid days PLUS boosters, so weekly sits ABOVE 7×daily (e.g. daily 55 → weekly ~400). Teach this explicitly so 48/55 doesn't read as failure.

HOW TO CONVERSE
DIG, don't collect — go one level deeper for specifics. Draw out the STORY to infer difficulty. SUGGEST like a knowledgeable coach, reverse-engineering from the destination. ELICIT all relevant element types naturally. DIG INTO NEGATIVES the same way you dig into goals (frequency, trigger, how long the pattern) and ask directly "Is there one habit you're really trying to BREAK this season?".

THE GAP-FILL GATE — MANDATORY before you synthesize. Before done:true you MUST propose, by name, specific candidate items the user did NOT mention — drawn from reverse-engineering their life — and let them accept or decline. Offer concrete candidates across the dimensions they left blank: the foundation floor (sleep, a real meal vs grazing, hygiene, hydration, clean space, some movement, connection, financial awareness, healthy restoration — ask "what do you already do most days without thinking?" AND name examples), restoration/play, connection, and any goal-critical habit they skipped. A season built only from what the user volunteered is a FAILURE of this gate. For a terse/minimal user, still offer a SHORT version (two or three candidates), then respect their no and wrap up.

Thoroughness scales to the person. Engaged → rich, all element types, more digging. Minimal → clean small rubric, end sooner. No item cap, but every item must be genuinely important for THIS user. Never pad a minimalist; never under-dig an engaged user.

ENSURE THEY UNDERSTAND (teaching is half the job)
Teach each concept in one warm sentence the first time it's relevant. In your closing message (done:true) give a brief warm recap in plain prose: what a strong day looks like (~target, not everything), why the week is more than seven days summed, that negatives keep it honest not punishing, that milestones are the big destinations, that points are higher for what's hard for them on purpose, and that this is now their editable measuring stick.

TONE
Keep every turn SHORT and conversational — a few sentences at most. One question/suggestion per turn. Mirror their words back; use their own words for item names. Never say "rubric/points system/AI" to the user. No emoji, no bullet lists, no clinical tone, never saccharine. The only allowed longer turn is the closing recap.

This is the start of a conversation — your FIRST message opens it (the user hasn't said anything yet). Greet warmly, set the ~10-15 minute expectation, and ask your opening question about what season of life they're in and who they're trying to become.

OUTPUT FORMAT — ABSOLUTE RULE (the app parses this exactly)
Reply with ONE JSON object and NOTHING else. No markdown fences, no prose outside the JSON. Shape:

{
  "message": "your warm one-question/one-suggestion turn (or the closing recap if done)",
  "threads": [{"name": "Faith", "color_hint": "#7F77DD"}],
  "teaching": null,
  "done": false,
  "suggested_name": null,
  "suggested_length_days": null,
  "rubric": null
}

- "threads" is cumulative — every focus area recognized so far, every turn, each an object with a name and a hex color_hint.
- color_hint MUST be one of these hex values: #7F77DD (spiritual/inner), #D85A30 (fitness/body), #639922 (health/nature), #185FA5 (work/study), #993556 (creative), #C2922F (home/life), #3F8E8E (relationships). Never use a color word like "violet" — always the hex.
- "teaching": one short sentence when you introduce a mechanic this turn, else null.
- When done:true, "message" is the closing recap, "suggested_name" is a short evocative 2–5 word season name in their own words (e.g. "Keeping Up, Not Drowning"), "suggested_length_days" is an integer (30/60/90/120; default 90), and "rubric" is fully populated:

{
  "daily_target": 55,
  "weekly_target": 400,
  "categories": [
    {"name": "Fitness", "color_hint": "#D85A30", "tasks": [
      {"name": "Gym session", "scoring_type": "binary", "value": 8},
      {"name": "Sleep", "scoring_type": "tiered", "unit": "hours", "tiers": [{"threshold": 6, "points": 2}, {"threshold": 8, "points": 4}]},
      {"name": "Pushups", "scoring_type": "increment", "unit": "pushups", "base_threshold": 200, "base_points": 3, "unit_size": 100, "points_per_unit": 1}
    ]}
  ],
  "negatives": [
    {"name": "Doomscroll session", "negative_type": "per_instance", "value": 3},
    {"name": "Junk food", "negative_type": "frequency_threshold", "window": "weekly", "free_count": 2, "value": 4}
  ],
  "weekly_boosters": [{"name": "Three gym days", "references": "Gym session", "threshold": 3, "value": 10}],
  "weekly_penalties": [],
  "milestones": [{"name": "Run a 5K", "value": 40}, {"name": "Reach 180 lbs", "value": 50}]
}

RULES for the rubric JSON:
- 2–6 categories; every category needs at least one task; each category color_hint is one of the hex values above.
- scoring_type is exactly one of: "binary" (use "value"), "tiered" (use "unit" + "tiers" array of {threshold, points}), "increment" (use "unit", "base_threshold", "base_points", "unit_size", "points_per_unit").
- negative_type is exactly one of: "per_instance" or "frequency_threshold" (the latter also needs "window": "weekly"|"monthly" and "free_count"). negative "value" is a POSITIVE magnitude (e.g. 3, not -3) — the app applies the minus.
- weekly_boosters and weekly_penalties: "references" must EXACTLY match a daily task name.
- Keep numbers human: tasks 1–10 (milestone-scale only via the milestones array, 20–150), negatives 2–8, boosters/penalties 5–25, milestones 20–150. Keep the rubric honest to what was discussed — never pad it with things the user didn't mention.`;

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
}
interface WireCategory { name: string; color_hint?: string; tasks: WireTask[] }
interface WireNegative {
  name: string;
  negative_type: string;
  value: number;
  window?: string;
  free_count?: number;
}
interface WireRule { name: string; references?: string; threshold?: number; value: number }
interface WireMilestone { name: string; value: number }
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
  done?: boolean;
  suggested_name?: string | null;
  suggested_length_days?: number | null;
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
// at 6 (the app's per-season category slots), guarantees every category
// has a task, sorts tiers, and re-derives targets when they're implausible.
// ---------------------------------------------------------------------------

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, Math.round(n)));

function validateRubric(r: WireRubric): WireRubric {
  const categories = (r.categories ?? [])
    .filter((c) => c && typeof c.name === "string" && Array.isArray(c.tasks) && c.tasks.length > 0)
    .slice(0, 6)
    .map((c) => ({
      name: c.name.trim().slice(0, 40) || "Area",
      color_hint: /^#[0-9A-Fa-f]{6}$/.test(c.color_hint ?? "") ? c.color_hint : "#7F77DD",
      tasks: c.tasks
        .filter((t) => t && typeof t.name === "string" && t.name.trim().length > 0)
        .slice(0, 20)
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
          return task;
        }),
    }))
    .filter((c) => c.tasks.length > 0);

  // Headline points available in a typical day.
  const dayTotal = categories.reduce(
    (sum, c) => sum + c.tasks.reduce((s, t) => s + (t.value ?? 3), 0),
    0,
  );

  // A strong day ≈ 60–75% of everything. Re-derive when implausible.
  let daily = Math.round(r.daily_target ?? 0);
  const lo = Math.max(5, Math.round(dayTotal * 0.45));
  const hi = Math.max(lo, Math.round(dayTotal * 0.85));
  if (!Number.isFinite(daily) || daily < lo || daily > hi) {
    daily = Math.max(5, Math.round(dayTotal * 0.65));
  }
  let weekly = Math.round(r.weekly_target ?? 0);
  if (!Number.isFinite(weekly) || weekly < daily * 4 || weekly > daily * 8) {
    weekly = daily * 6;
  }

  const taskNames = new Set(
    categories.flatMap((c) => c.tasks.map((t) => t.name.toLowerCase())),
  );

  const negatives = (r.negatives ?? [])
    .filter((n) => n && typeof n.name === "string" && n.name.trim().length > 0)
    .slice(0, 12)
    .map((n) => {
      const shape = n.negative_type === "frequency_threshold" ? "frequency_threshold" : "per_instance";
      const out: WireNegative = {
        name: n.name.trim().slice(0, 60),
        negative_type: shape,
        value: clamp(n.value ?? 3, 1, 25),
      };
      if (shape === "frequency_threshold") {
        out.window = n.window === "monthly" ? "monthly" : "weekly";
        out.free_count = clamp(n.free_count ?? 2, 0, 14);
      }
      return out;
    });

  const cleanRule = (x: WireRule): WireRule => ({
    name: x.name.trim().slice(0, 60),
    references: x.references && taskNames.has(x.references.toLowerCase()) ? x.references : x.references?.trim(),
    threshold: clamp(x.threshold ?? 3, 1, 7),
    value: clamp(x.value ?? 10, 1, 40),
  });

  const weekly_boosters = (r.weekly_boosters ?? [])
    .filter((b) => b && typeof b.name === "string" && b.name.trim().length > 0)
    .slice(0, 8)
    .map(cleanRule);

  const weekly_penalties = (r.weekly_penalties ?? [])
    .filter((p) => p && typeof p.name === "string" && p.name.trim().length > 0)
    .slice(0, 8)
    .map(cleanRule);

  const milestones = (r.milestones ?? [])
    .filter((m) => m && typeof m.name === "string" && m.name.trim().length > 0)
    .slice(0, 8)
    .map((m) => ({ name: m.name.trim().slice(0, 80), value: clamp(m.value ?? 60, 20, 250) }));

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
    await requireAuth(req);

    const apiKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!apiKey) {
      return json({ error: "Season setup AI is not configured yet (missing OPENROUTER_API_KEY secret)" }, 503);
    }

    const body = (await req.json()) as { messages?: ChatMessage[] };
    const history = Array.isArray(body.messages) ? body.messages : [];
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
      ...history,
    ];
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
      teaching: typeof reply.teaching === "string" && reply.teaching.trim().length > 0 ? reply.teaching.trim() : null,
      done,
      suggested_name: typeof reply.suggested_name === "string" && reply.suggested_name.trim().length > 0
        ? reply.suggested_name.trim().slice(0, 60)
        : null,
      suggested_length_days: typeof reply.suggested_length_days === "number"
        ? clamp(reply.suggested_length_days, 14, 365)
        : null,
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

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
