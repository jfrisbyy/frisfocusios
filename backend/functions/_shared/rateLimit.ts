// Per-user quota for the paid-model functions.
//
// Every AI function verifies the caller's JWT but, before this, none of
// them limited how OFTEN one account could call. The only guardrails were
// per-request size caps, which bound the cost of a single call and say
// nothing about ten thousand of them. season-setup runs Claude Opus on
// every onboarding, so an unattended retry loop is a real bill.
//
// Two rolling windows, because they catch different failures: the hourly
// one catches a client stuck in a loop, the daily one catches sustained
// abuse that stays under the hourly bar.
//
// Fail-open by design. If the ledger itself is unavailable the request is
// allowed through and the reason logged: a metering outage should not take
// down season setup for everyone. The cost ceiling of that failure mode is
// bounded by how long an outage lasts, which is the right trade against
// breaking onboarding.

import { createAdminClient } from "./auth.ts";

export interface QuotaLimits {
  /** Calls allowed in any rolling 60 minutes. */
  hourly: number;
  /** Calls allowed in any rolling 24 hours. */
  daily: number;
}

export interface QuotaResult {
  allowed: boolean;
  /** Which window was exceeded, for the error message. */
  window?: "hour" | "day";
  /** Seconds the caller should wait before retrying. */
  retryAfter?: number;
}

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/**
 * Record one call and report whether it was within quota.
 *
 * Counts first, then records, so a caller already over the line is not
 * charged for the request it was refused. Under heavy concurrency this can
 * admit a couple of extra calls past the limit, which is the right trade:
 * the alternative is a lock on the hot path of every AI request, to save a
 * rounding error on a bill this exists to bound rather than to meter
 * exactly.
 */
export async function consumeQuota(
  userId: string,
  fn: string,
  limits: QuotaLimits,
): Promise<QuotaResult> {
  try {
    const admin = createAdminClient();
    const since = new Date(Date.now() - DAY_MS).toISOString();

    const { data, error } = await admin
      .from("ai_usage")
      .select("created_at")
      .eq("user_id", userId)
      .eq("fn", fn)
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(Math.max(limits.daily, limits.hourly) + 1);

    if (error) throw error;

    const now = Date.now();
    const stamps = (data ?? []).map((r) => new Date(r.created_at).getTime());
    const inHour = stamps.filter((t) => now - t < HOUR_MS);

    if (stamps.length >= limits.daily) {
      const oldest = stamps[stamps.length - 1];
      return {
        allowed: false,
        window: "day",
        retryAfter: Math.max(1, Math.ceil((oldest + DAY_MS - now) / 1000)),
      };
    }
    if (inHour.length >= limits.hourly) {
      const oldest = inHour[inHour.length - 1];
      return {
        allowed: false,
        window: "hour",
        retryAfter: Math.max(1, Math.ceil((oldest + HOUR_MS - now) / 1000)),
      };
    }

    const { error: insertError } = await admin
      .from("ai_usage")
      .insert({ user_id: userId, fn });
    if (insertError) throw insertError;

    return { allowed: true };
  } catch (err) {
    console.error(`[rateLimit] ${fn}: metering unavailable, allowing`, err);
    return { allowed: true };
  }
}

/** The 429 body and headers to return when {@link consumeQuota} refuses. */
export function quotaResponse(
  result: QuotaResult,
  corsHeaders: Record<string, string>,
): Response {
  const wait = result.retryAfter ?? 60;
  const message = result.window === "day"
    ? "You've reached today's limit for this. It resets over the next day."
    : "That's a lot at once — give it a few minutes and try again.";
  return new Response(
    JSON.stringify({ error: message, retryAfter: wait }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(wait),
      },
    },
  );
}
