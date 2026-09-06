// openrouter-chat
//
// Server-side proxy to OpenRouter for the season rubric-generation
// conversation (and future AI features). The app sends a message list;
// this function forwards it to OpenRouter with the server-held API key
// and streams the assistant reply back as SSE, so the app can render a
// chat-style typing response.
//
// Security:
// - Signed-in users only (same Rork-Auth JWT check as send-push).
// - The OpenRouter key lives ONLY as a Supabase secret (OPENROUTER_API_KEY);
//   it never ships in the app.
// - Guardrails: request-size limits and a max-token cap so a client bug
//   can't run up costs.
//
// Graceful failure: until OPENROUTER_API_KEY is configured, returns a clear
// 503 "not configured" JSON error instead of crashing.

import { requireAuth, AuthError } from "../_shared/auth.ts";
import { consumeQuota, quotaResponse } from "../_shared/rateLimit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Always resolves to the newest Claude Opus on OpenRouter (currently 4.8).
const DEFAULT_MODEL = "~anthropic/claude-opus-latest";

// Guardrails.
const MAX_MESSAGES = 60;
const MAX_TOTAL_CHARS = 200_000; // ~50k tokens of input, plenty for a rubric chat
const MAX_OUTPUT_TOKENS = 8_192;
const DEFAULT_OUTPUT_TOKENS = 4_096;

interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

interface ChatRequest {
  messages: ChatMessage[];
  /** Optional model override; defaults to latest Claude Opus. */
  model?: string;
  /** Optional system prompt, prepended to messages. */
  system?: string;
  /** When true, the reply is streamed as SSE. Defaults to true. */
  stream?: boolean;
  /** Structured-output mode: pass a JSON schema and the model must return
   *  JSON matching it (used by the rubric validator step). Forces
   *  non-streaming so the caller gets one parseable body. */
  jsonSchema?: { name: string; schema: Record<string, unknown> };
  maxTokens?: number;
  temperature?: number;
}

function validate(body: ChatRequest): string | null {
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return "messages must be a non-empty array";
  }
  if (body.messages.length > MAX_MESSAGES) {
    return `too many messages (max ${MAX_MESSAGES})`;
  }
  let totalChars = body.system?.length ?? 0;
  for (const m of body.messages) {
    if (!m || typeof m.content !== "string" || !["system", "user", "assistant"].includes(m.role)) {
      return "each message needs a valid role and string content";
    }
    totalChars += m.content.length;
  }
  if (totalChars > MAX_TOTAL_CHARS) {
    return `conversation too large (max ${MAX_TOTAL_CHARS} characters)`;
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const user = await requireAuth(req);

    // Meter before any paid work: the model call is the expensive
    // part, so a refusal has to happen ahead of it, not after.
    const quota = await consumeQuota(user.userId, "openrouter-chat", {
      hourly: 60,
      daily: 300,
    });
    if (!quota.allowed) return quotaResponse(quota, corsHeaders);

    const apiKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!apiKey) {
      return json({ error: "AI is not configured yet (missing OPENROUTER_API_KEY secret)" }, 503);
    }

    const body = (await req.json()) as ChatRequest;
    const validationError = validate(body);
    if (validationError) {
      return json({ error: validationError }, 400);
    }

    const messages: ChatMessage[] = body.system
      ? [{ role: "system", content: body.system }, ...body.messages]
      : body.messages;

    // Structured output must come back as one parseable body.
    const wantsStream = body.jsonSchema ? false : (body.stream ?? true);
    const maxTokens = Math.min(Math.max(1, body.maxTokens ?? DEFAULT_OUTPUT_TOKENS), MAX_OUTPUT_TOKENS);

    const payload: Record<string, unknown> = {
      model: body.model?.trim() || DEFAULT_MODEL,
      messages,
      stream: wantsStream,
      max_tokens: maxTokens,
    };
    if (typeof body.temperature === "number") {
      payload.temperature = Math.min(Math.max(0, body.temperature), 2);
    }
    if (body.jsonSchema) {
      payload.response_format = {
        type: "json_schema",
        json_schema: { name: body.jsonSchema.name, strict: true, schema: body.jsonSchema.schema },
      };
    }

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
      let message = "AI request failed";
      try {
        message = JSON.parse(text)?.error?.message ?? message;
      } catch {
        // Non-JSON upstream error — keep the generic message.
      }
      console.error(`OpenRouter error ${upstream.status}: ${text.slice(0, 500)}`);
      // 429/402 are user-meaningful (rate limit / out of credits); pass through.
      const status = upstream.status === 429 || upstream.status === 402 ? upstream.status : 502;
      return json({ error: message }, status);
    }

    if (wantsStream) {
      // Forward OpenRouter's SSE body untouched (data: {...} chunks ending
      // with data: [DONE]). The client reads choices[0].delta.content.
      return new Response(upstream.body, {
        headers: {
          ...corsHeaders,
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
        },
      });
    }

    const completion = await upstream.json();
    const content: string = completion?.choices?.[0]?.message?.content ?? "";
    return json({ content, model: completion?.model ?? null, usage: completion?.usage ?? null });
  } catch (err) {
    if (err instanceof AuthError) {
      return json({ error: "Unauthorized" }, 401);
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
