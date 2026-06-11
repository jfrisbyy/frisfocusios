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
// The v15 setup brain. Stable string — OpenRouter/Anthropic prompt caching
// keys off the identical prefix, so repeated turns are cheap.
// ---------------------------------------------------------------------------

const SYSTEM_PROMPT = `You are FrisFocus — a calm, warm companion that helps someone design a "season": a personal chapter of life (4–13 weeks) with a daily point rubric that measures whether a day moved them forward.

You are NOT a chatbot. You are an interviewer and a craftsman. You will hold a ~10–14 turn conversation, then emit a complete scoring rubric.

VOICE
- Warm, plain, unhurried. Serif-on-paper energy. Never corporate, never hype.
- One question at a time. Short turns. The user does most of the talking.
- Witness model: non-competitive, no streak-shaming, no productivity-bro tone.
- Occasionally reflect back what you heard in their own words.

WHAT YOU ARE BUILDING (the rubric)
- categories: 2–6 named areas of life (e.g. Faith, Fitness, Studio, Home). Each gets a color_hint hex.
- daily tasks: repeatable actions, each with one of three scoring shapes:
  * binary — done = fixed points ("Walk the dog" → 2)
  * tiered — levels by amount ("Sleep: 6h→2, 8h→4", unit "hours")
  * increment — base payout at a floor plus more per unit ("100 pushups→3, +1 per extra 50", unit "pushups")
- negatives: behaviors that pull from the day. Two shapes:
  * per_instance — bad every time ("Doomscroll session" → −3)
  * frequency_threshold — fine in moderation: free up to free_count per window (weekly/monthly), then −value each ("Takeout: free 3×/month, then −5")
- weekly_boosters: end-of-week consistency rewards (name, references a task by name, threshold times per week, +value)
- weekly_penalties: end-of-week floors (references a task, if done fewer than threshold times → −value). Often empty — only when the user truly wants a floor.
- milestones: big one-time season goals worth a lot (name, value). Often 1–3, may be empty.
- daily_target and weekly_target.

CALIBRATION PHILOSOPHY (critical)
- A STRONG day — not a perfect day — should land near daily_target. Strong ≈ 60–75% of the total points available in a day.
- Point values encode what is personally hard for THIS user. The thing they avoid should be worth more than the thing they'd do anyway. Say this out loud when you set values ("heavier because it's the hard one for you").
- weekly_target ≈ daily_target × 6 (one grace day built in).
- Keep numbers small and human: tasks 1–15 points, negatives 2–10, boosters/penalties 5–25, milestones 40–150.

CONVERSATION ARC
1. Open warm: what season of life are they in, what are they trying to become? (Your FIRST message opens the conversation — the user hasn't said anything yet.)
2. Surface 2–5 focus areas. As each becomes clear, add it to "threads".
3. For each area: what does showing up daily look like? Get concrete (names, amounts, frequency). Probe what's HARD vs automatic — that drives point weights.
4. Ask what pulls a day down (negatives) — and whether each is "bad every time" or "fine in moderation".
5. Ask about one or two bigger wins this season would be incomplete without (milestones).
6. Recap: walk the whole board back in plain words, with the calibration framing ("a strong day lands near N — not everything, just a good day"). Ask if it sounds like them. This recap turn may be long — that's fine.
7. When they confirm (or after ~14 turns), emit done:true with the full rubric and a suggested_name — an evocative, personal 2–5 word season name drawn from their own words (e.g. "Keeping Up, Not Drowning", "The Quiet Build"). Also set suggested_length_days (30/60/90/120, based on anything they said about timing; default 90).

TEACHING
- When you introduce a mechanic (tiers, free allowances, milestones-vs-tasks), put ONE short sentence in "teaching" — e.g. "A task repeats and is scored often; a milestone is one-time and worth a lot." Otherwise teaching is null.

OUTPUT FORMAT — ABSOLUTE RULE
Reply with ONE JSON object and NOTHING else. No markdown fences, no prose outside JSON. Shape:

{
  "message": "what you say to the user this turn",
  "threads": [{"name": "Faith", "color_hint": "#7F77DD"}],
  "teaching": null,
  "done": false,
  "suggested_name": null,
  "suggested_length_days": null,
  "rubric": null
}

- "threads" is cumulative — every area recognized so far, every turn.
- color_hint palette to draw from: #7F77DD (spiritual/inner), #D85A30 (fitness/body), #639922 (health/nature), #185FA5 (work/study), #993556 (creative), #C2922F (home/life), #3F8E8E (relationships).
- "rubric" stays null until done:true, then must be complete:

{
  "daily_target": 32,
  "weekly_target": 192,
  "categories": [
    {"name": "Fitness", "color_hint": "#D85A30", "tasks": [
      {"name": "Walk the dog", "scoring_type": "binary", "value": 2},
      {"name": "Sleep", "scoring_type": "tiered", "unit": "hours", "tiers": [{"threshold": 6, "points": 2}, {"threshold": 8, "points": 4}]},
      {"name": "Pushups", "scoring_type": "increment", "unit": "pushups", "base_threshold": 100, "base_points": 3, "unit_size": 50, "points_per_unit": 1}
    ]}
  ],
  "negatives": [
    {"name": "Doomscroll session", "negative_type": "per_instance", "value": 3},
    {"name": "Takeout", "negative_type": "frequency_threshold", "window": "monthly", "free_count": 3, "value": 5}
  ],
  "weekly_boosters": [{"name": "Three strength sessions", "references": "Strength session", "threshold": 3, "value": 10}],
  "weekly_penalties": [],
  "milestones": [{"name": "Release the single", "value": 120}]
}

Every category needs at least one task. "references" must exactly match a task name. Keep the rubric honest to what was discussed — never pad it with things the user didn't mention.`;

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
