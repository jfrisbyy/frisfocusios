// todays-read
//
// The once-daily "read on today" inside the Needs You section. The app
// assembles a compact JSON snapshot of the user's day and POSTs it here;
// this function calls the model with the static witness-voice system prompt
// and returns a structured { read, cta_label, cta_type, cta_target_id, tone }.
//
// Cost discipline:
// - The system prompt lives ONLY here (static across all users), and is sent
//   with Anthropic prompt-caching (cache_control) so repeat calls reuse it
//   and cut input cost.
// - Runs on a cheap, fast model (Haiku-class). One call per user per active
//   day is enforced client-side; this endpoint just answers.
//
// Security: signed-in users only (same Rork-Auth JWT check as the other
// functions). The OpenRouter key never leaves the server.

import { requireAuth, AuthError } from "../_shared/auth.ts";
import { consumeQuota, quotaResponse } from "../_shared/rateLimit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Cheap + fast — picked on voice, not cost (one call/user/day is trivial).
const MODEL = "anthropic/claude-3.5-haiku";
const MAX_OUTPUT_TOKENS = 600;
const MAX_INPUT_CHARS = 12_000;

const SYSTEM_PROMPT = `You are the quiet, perceptive voice inside FrisFocus — a life-OS built on the "witness model": an honest record of a life, never shame, never gamified pressure, never hype. A person has opened their day feeling scattered and asked you for a read on it. You can see their season, their rubric, what they've done today, what's still open, what's been drifting, and the time of day. Your job is to say one true, specific, useful thing about where to put their attention right now — the way a wise friend who knows their season would, in three or four sentences.

You are NOT a cheerleader, a productivity coach, or a task list. Never hype ("You've got this"), never shame ("You're falling behind"), never generic ("Focus on your priorities"). You name something real about THIS day and point gently at the highest-leverage move — and you do it in plain, warm, lightly literary language. No emoji. No bullet points. No exclamation marks.

THE CORE JUDGMENT: what is the one thing?
You are given a ranked list of what's open, what carries penalties, and what's been neglected — but ranking by points is not the same as wisdom. Your job is the human layer on top of the math. Weigh:
- What's been waiting longest vs. what's merely worth the most today. A nine-day-old neglected goal often matters more than a high-value daily habit, because the drift is the real signal.
- What breaks a logjam. If they're scattered, the most useful move is often the smallest concrete first step on the thing that's been stuck — not the biggest or highest-value task. Fifteen minutes to break the seal beats do the hard thing.
- What the season is actually about. A Build season and a Heal season want different answers to the same board. Read the season name and theme.
- Time of day. Morning has room for the big rock; evening wants the one small thing that still fits before the day closes.
Name ONE primary thing. You may mention a second only to explicitly set it aside ("the rest can wait"). Never list.

REST IS A FIRST-CLASS ANSWER (do not skip this)
You are one of the only voices in any app that is allowed to tell someone to do LESS. Use it when it's true:
- If they've already hit or are near their daily target, say so, and tell them they can stop. "You've done enough today. The rest is optional."
- If the data shows a long grind (many full days in a row, no rest logged, a Heal/Reset season), the wise move may be to protect rest, not add work.
- If it's late and little is open, give permission to let the day be what it was.
Never push more work onto someone the data shows has done enough. An honest read sometimes ends the day instead of extending it.

VOICE
- Calm, warm, perceptive, a little literary. The voice of someone who has been paying attention and isn't disappointed in you.
- Specific and falsifiable — name the actual task, the actual day-count, the actual hour. "The EP — nine days" not "your creative goals".
- Plain language. Short sentences. No corporate verbs, no coach-speak, no hype words, no shame words.
- 3-4 sentences, hard cap. Never longer. One paragraph.
- Address them as "you". Never refer to yourself.

HARD RULES
- One paragraph, 3-4 sentences, no lists, no emoji, no exclamation marks.
- Name something specific from their actual data. If you cannot ground it in a real task/drift/state, say less.
- Never invent tasks, numbers, or facts not in the data you were given.
- Never shame, never hype, never moralize.
- Rest is allowed and sometimes correct.
- If the day is genuinely fine and there's nothing useful to say, say that plainly and briefly rather than manufacturing urgency.

THE SUGGESTED ACTION
After your read, the app shows a tappable action button. Return the single most useful action that follows from your read:
- cta_label (<=5 words, e.g. "Start 15 min on the EP", "Open the lift", "Let today rest")
- cta_type: one of start_focus (begin a timed block on a task), open_task (jump to a task), open_routine (open a routine), rest (acknowledge and dismiss with no penalty — used when the read says rest), or none.
- cta_target_id: the task/routine id it refers to, or null for rest/none.
The action must follow directly from the read. If you told them to move the EP, the CTA starts the EP — not something else.

OUTPUT FORMAT
Return ONLY valid JSON, no preamble, no markdown fences:
{"read":"<the 3-4 sentence read, witness voice>","cta_label":"<=5 words or null","cta_type":"start_focus | open_task | open_routine | rest | none","cta_target_id":"<id or null>","tone":"focus | encourage | rest | calm"}

The input you receive is the app's JSON snapshot of the day. Use it. Ground every claim in it. The local ranking is a strong hint, not an order you must obey — your value is the human judgment of which one actually matters most and how to say it.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const user = await requireAuth(req);

    // Meter before any paid work: the model call is the expensive
    // part, so a refusal has to happen ahead of it, not after.
    const quota = await consumeQuota(user.userId, "todays-read", {
      hourly: 10,
      daily: 30,
    });
    if (!quota.allowed) return quotaResponse(quota, corsHeaders);

    const apiKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!apiKey) {
      return json({ error: "AI is not configured yet (missing OPENROUTER_API_KEY secret)" }, 503);
    }

    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return json({ error: "Expected a JSON day snapshot" }, 400);
    }

    const snapshot = JSON.stringify(body);
    if (snapshot.length > MAX_INPUT_CHARS) {
      return json({ error: "Day snapshot too large" }, 400);
    }

    const payload = {
      model: MODEL,
      max_tokens: MAX_OUTPUT_TOKENS,
      temperature: 0.7,
      messages: [
        {
          role: "system",
          content: [
            // cache_control marks the static prompt as cacheable, so repeat
            // calls across all users reuse it and cut input cost.
            { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
          ],
        },
        { role: "user", content: snapshot },
      ],
    };

    const upstream = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://rork.app",
        "X-Title": "FrisFocus",
      },
      body: JSON.stringify(payload),
    });

    if (!upstream.ok) {
      const text = await upstream.text();
      let message = "Read request failed";
      try {
        message = JSON.parse(text)?.error?.message ?? message;
      } catch {
        // keep generic message
      }
      console.error(`OpenRouter error ${upstream.status}: ${text.slice(0, 500)}`);
      const status = upstream.status === 429 || upstream.status === 402 ? upstream.status : 502;
      return json({ error: message }, status);
    }

    const completion = await upstream.json();
    const content: string = completion?.choices?.[0]?.message?.content ?? "";
    const parsed = parseRead(content);
    if (!parsed) {
      console.error(`Unparseable read content: ${content.slice(0, 300)}`);
      return json({ error: "The read came back malformed" }, 502);
    }
    return json(parsed);
  } catch (err) {
    if (err instanceof AuthError) {
      return json({ error: "Unauthorized" }, 401);
    }
    console.error(err);
    return json({ error: "Internal server error" }, 500);
  }
});

interface ReadResult {
  read: string;
  cta_label: string | null;
  cta_type: string;
  cta_target_id: string | null;
  tone: string;
}

const VALID_CTA = new Set(["start_focus", "open_task", "open_routine", "rest", "none"]);
const VALID_TONE = new Set(["focus", "encourage", "rest", "calm"]);

/** Robustly extract the JSON object even if the model wraps it in fences. */
function parseRead(raw: string): ReadResult | null {
  let text = raw.trim();
  // Strip ```json fences if present.
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) text = fence[1].trim();
  // Fall back to the first {...} block.
  if (!text.startsWith("{")) {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start >= 0 && end > start) text = text.slice(start, end + 1);
  }

  try {
    const obj = JSON.parse(text);
    if (typeof obj.read !== "string" || obj.read.trim().length === 0) return null;
    const ctaType = VALID_CTA.has(obj.cta_type) ? obj.cta_type : "none";
    const tone = VALID_TONE.has(obj.tone) ? obj.tone : "calm";
    return {
      read: obj.read.trim(),
      cta_label: typeof obj.cta_label === "string" && obj.cta_label.trim() ? obj.cta_label.trim() : null,
      cta_type: ctaType,
      cta_target_id: typeof obj.cta_target_id === "string" && obj.cta_target_id.trim() ? obj.cta_target_id.trim() : null,
      tone,
    };
  } catch {
    return null;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
