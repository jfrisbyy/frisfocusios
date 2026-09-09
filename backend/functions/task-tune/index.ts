// task-tune
//
// The scoped "talk it through" for ONE neglected task or milestone.
//
// The home used to answer neglect with an invitation into the full
// season conversation — a fifteen-minute rebuild pitched at someone who
// just needs to renegotiate one commitment. This is the right-sized
// version: the app sends the item, its real numbers (days idle, value,
// schedule, the season's shape) and the running chat; the model answers
// like a coach who can see the ledger, and every concrete move it
// proposes comes back as a TYPED change the app applies on tap. The
// model never mutates anything — it only proposes; the person applies.
//
// Same security envelope as season-setup: Rork-Auth JWT, server-held
// OpenRouter key, per-user quota before any paid work.

import { requireAuth, AuthError } from "../_shared/auth.ts";
import { consumeQuota, quotaResponse } from "../_shared/rateLimit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// The proven route in this project — the same alias season-setup runs on.
const MODEL = "~anthropic/claude-opus-latest";
const MAX_OUTPUT_TOKENS = 700;
const MAX_TURNS = 24;
const MAX_MESSAGE_CHARS = 2_000;

const SYSTEM_PROMPT = `You are the tune-up voice inside FrisFocus — a life-OS built on the "witness model": an honest record, never shame, never hype. One item in a person's season has been slipping, and they've opened a small conversation about JUST that item. You can see its real numbers in the CONTEXT message: what it's worth, how long it takes, when it's scheduled, how many days it's been untouched, how deep into the season they are.

YOUR JOB
Renegotiate this one commitment so it fits the life actually being lived. A slipped task is information, not failure: usually the task is too big, scheduled on the wrong days, priced wrong for its effort, or simply not this season's work. Say the true thing about which of those it looks like, then propose concrete moves.

HARD RULES
- Never suggest creating a new season, redoing setup, or touching any other item. This conversation is about one thing.
- Speak like a perceptive friend: plain, warm, brief. Max ~70 words per reply. No emoji, no bullet lists, no exclamation marks, no cheerleading, no shame.
- Every proposal must use the item's REAL numbers (its minutes, its days, its value) — never invent state you weren't given.
- On the OPENING turn (no user words yet): name what you see in one or two sentences and offer 2-3 proposals immediately. Do not open with a question barrage.
- When the person picks a direction or says they're done, set "done": true and stop proposing.
- 0-3 proposals per turn. Repeat a proposal only if the person asked to see it again.

PROPOSAL CHANGES — the only allowed shapes
For a task:
  {"action":"reschedule","days":[2,4,6]}        // 1=Sun … 7=Sat; [] means available every day
  {"action":"shrink","est_minutes":15,"name":"Walk 10 minutes"}  // smaller honest version; name optional
  {"action":"reprice","value":2}                 // 1-10, what a day of it is worth
  {"action":"pause","days":7}                    // 1-14 days of guilt-free silence
  {"action":"drop"}                              // off the board, said kindly
For a milestone:
  {"action":"push_date","target_date":"2026-10-01"}
  {"action":"add_step","title":"Email the venue"} // the next smallest real step
  {"action":"reprice","value":50}                // 5-500
  {"action":"drop"}

OUTPUT — exactly this JSON, nothing else, no markdown fences:
{"say":"<your reply>","proposals":[{"label":"<=28 chars button text","detail":"<=90 chars why this works","change":{...}}],"done":false}`;

// ---------------------------------------------------------------------------

interface WireProposal {
  label: string;
  detail: string;
  change: Record<string, unknown>;
}

function clampInt(v: unknown, lo: number, hi: number): number | null {
  const n = typeof v === "number" ? Math.round(v) : NaN;
  if (!Number.isFinite(n)) return null;
  return Math.min(hi, Math.max(lo, n));
}

/** Whitelist + clamp one proposed change. Returns null to drop it. */
function sanitizeChange(kind: string, raw: unknown): Record<string, unknown> | null {
  if (typeof raw !== "object" || raw === null) return null;
  const c = raw as Record<string, unknown>;
  const action = typeof c.action === "string" ? c.action : "";

  if (kind === "task") {
    switch (action) {
      case "reschedule": {
        const days = Array.isArray(c.days)
          ? [...new Set(c.days.map((d) => clampInt(d, 1, 7)).filter((d): d is number => d !== null))]
          : [];
        if (days.length > 7) return null;
        return { action, days: days.sort((a, b) => a - b) };
      }
      case "shrink": {
        const minutes = clampInt(c.est_minutes, 1, 600);
        if (minutes === null) return null;
        const name = typeof c.name === "string" && c.name.trim().length > 0
          ? c.name.trim().slice(0, 60)
          : null;
        return name ? { action, est_minutes: minutes, name } : { action, est_minutes: minutes };
      }
      case "reprice": {
        const value = clampInt(c.value, 1, 10);
        return value === null ? null : { action, value };
      }
      case "pause": {
        const days = clampInt(c.days, 1, 14);
        return days === null ? null : { action, days };
      }
      case "drop":
        return { action };
      default:
        return null;
    }
  }

  switch (action) {
    case "push_date": {
      const rawDate = typeof c.target_date === "string" ? c.target_date : "";
      const parsed = Date.parse(rawDate);
      if (!Number.isFinite(parsed)) return null;
      const now = Date.now();
      if (parsed < now - 24 * 3600 * 1000) return null;
      if (parsed > now + 365 * 24 * 3600 * 1000) return null;
      return { action, target_date: rawDate.slice(0, 10) };
    }
    case "add_step": {
      const title = typeof c.title === "string" ? c.title.trim().slice(0, 80) : "";
      return title.length > 0 ? { action, title } : null;
    }
    case "reprice": {
      const value = clampInt(c.value, 5, 500);
      return value === null ? null : { action, value };
    }
    case "drop":
      return { action };
    default:
      return null;
  }
}

function extractJSON(text: string): Record<string, unknown> | null {
  const trimmed = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  try {
    const parsed = JSON.parse(trimmed);
    return typeof parsed === "object" && parsed !== null ? parsed : null;
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start === -1 || end <= start) return null;
    try {
      const parsed = JSON.parse(trimmed.slice(start, end + 1));
      return typeof parsed === "object" && parsed !== null ? parsed : null;
    } catch {
      return null;
    }
  }
}

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
      temperature: 0.6,
    }),
  });
  if (!upstream.ok) {
    const text = await upstream.text();
    let message = "AI request failed";
    try {
      message = JSON.parse(text)?.error?.message ?? message;
    } catch { /* keep generic */ }
    console.error(`task-tune OpenRouter error ${upstream.status}: ${text.slice(0, 400)}`);
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

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const user = await requireAuth(req);

    const quota = await consumeQuota(user.userId, "task-tune", {
      hourly: 60,
      daily: 150,
    });
    if (!quota.allowed) return quotaResponse(quota, corsHeaders);

    const apiKey = Deno.env.get("OPENROUTER_API_KEY")?.trim();
    if (!apiKey) {
      console.error("task-tune: OPENROUTER_API_KEY secret is missing at runtime");
      return json({ error: "Talk it through isn't configured yet (missing OPENROUTER_API_KEY secret)" }, 503);
    }

    const body = await req.json().catch(() => null) as
      | { messages?: unknown; item?: unknown }
      | null;
    if (!body || typeof body !== "object") return json({ error: "Bad request" }, 400);

    const item = (typeof body.item === "object" && body.item !== null)
      ? body.item as Record<string, unknown>
      : null;
    const kind = item && item.kind === "milestone" ? "milestone" : "task";
    if (!item || typeof item.name !== "string" || item.name.trim().length === 0) {
      return json({ error: "Missing item" }, 400);
    }

    const rawMessages = Array.isArray(body.messages) ? body.messages : [];
    if (rawMessages.length > MAX_TURNS) return json({ error: "Conversation too long" }, 400);
    const history = rawMessages
      .filter((m): m is { role: string; content: string } =>
        typeof m === "object" && m !== null &&
        ((m as Record<string, unknown>).role === "user" || (m as Record<string, unknown>).role === "assistant") &&
        typeof (m as Record<string, unknown>).content === "string")
      .map((m) => ({ role: m.role, content: m.content.slice(0, MAX_MESSAGE_CHARS) }));

    // The item snapshot rides as a context turn ahead of the chat, so
    // the system prompt stays byte-identical (cacheable) across users.
    const context = `CONTEXT (the one item under discussion) — kind: ${kind}\n${
      JSON.stringify(item).slice(0, 4_000)
    }`;

    const messages = [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: context },
      ...history,
    ];
    if (history.length === 0) {
      messages.push({ role: "user", content: "(They just opened the conversation. Open it.)" });
    }

    let raw = await callModel(apiKey, messages);
    let parsed = extractJSON(raw);
    if (!parsed || typeof parsed.say !== "string") {
      // One malformed-output retry, mirroring season-setup.
      raw = await callModel(apiKey, [
        ...messages,
        { role: "assistant", content: raw },
        { role: "user", content: "That was not the required JSON. Reply again with ONLY the JSON object." },
      ]);
      parsed = extractJSON(raw);
    }
    if (!parsed || typeof parsed.say !== "string") {
      return json({ error: "The coach lost its train of thought. Try again." }, 502);
    }

    const proposals: WireProposal[] = [];
    if (Array.isArray(parsed.proposals)) {
      for (const p of parsed.proposals.slice(0, 3)) {
        if (typeof p !== "object" || p === null) continue;
        const rec = p as Record<string, unknown>;
        const change = sanitizeChange(kind, rec.change);
        if (!change) continue;
        proposals.push({
          label: (typeof rec.label === "string" ? rec.label : "Apply").trim().slice(0, 28),
          detail: (typeof rec.detail === "string" ? rec.detail : "").trim().slice(0, 90),
          change,
        });
      }
    }

    return json({
      message: parsed.say.trim().slice(0, 900),
      proposals,
      done: parsed.done === true,
      raw,
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return json({ error: error.message }, 401);
    }
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status);
    }
    console.error("task-tune error:", error);
    return json({ error: "Something went wrong" }, 500);
  }
});
