// moderation
//
// The queue behind the report button.
//
// Reports were landing in public.reports and nothing read them: no status,
// no triage, no record of a decision. App Review expects a reporting
// mechanism with a timely response behind it, and the Terms promise
// content removal and suspension that nothing could actually deliver.
//
// Access is an explicit allowlist of user ids in the MODERATOR_USER_IDS
// secret, checked against a verified JWT. Deliberately not a role column
// on profiles: that table is readable by every signed-in member, so who
// moderates would have been public, and a compromised account could not
// grant itself the role from a secret it cannot read.
//
// Until MODERATOR_USER_IDS is set, every request is refused. Failing
// closed is the only safe default for a surface that can read reports
// about people.
//
//   GET  ?status=open&limit=50   list reports, oldest first
//   POST { reportId, decision: "actioned" | "dismissed", note? }
//
// Suspension is intentionally not here yet. Recording the decision is the
// part that unblocks a beta; enforcing a ban needs an account-state model
// that every RLS policy has to respect, and half of that is worse than
// none.

import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const MAX_LIMIT = 200;
const DEFAULT_LIMIT = 50;
const DECISIONS = ["actioned", "dismissed"] as const;
type Decision = (typeof DECISIONS)[number];

interface DecisionRequest {
  reportId?: string;
  decision?: string;
  note?: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Allowlisted moderators, from the secret. Empty means nobody. */
function moderatorIds(): string[] {
  return (Deno.env.get("MODERATOR_USER_IDS") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const user = await requireAuth(req);

    const allowed = moderatorIds();
    if (allowed.length === 0) {
      // Say why, without saying who: a caller learns the surface is
      // unconfigured, never who would be allowed if it were.
      return json({ error: "Moderation is not configured." }, 503);
    }
    if (!allowed.includes(user.userId)) {
      return json({ error: "Not found." }, 404);
    }

    const admin = createAdminClient();

    if (req.method === "GET") {
      const url = new URL(req.url);
      const status = url.searchParams.get("status") ?? "open";
      const requested = Number(url.searchParams.get("limit") ?? DEFAULT_LIMIT);
      const limit = Number.isFinite(requested)
        ? Math.min(Math.max(1, Math.trunc(requested)), MAX_LIMIT)
        : DEFAULT_LIMIT;

      const { data, error } = await admin
        .from("reports")
        .select(
          "id, reporter_id, reported_user_id, message_id, story_post_id, story_comment_id, reason, details, status, created_at, reviewed_at, reviewer_id, reviewer_note",
        )
        .eq("status", status)
        // Oldest first: the thing waiting longest is the thing most at
        // risk of breaching a response-time expectation.
        .order("created_at", { ascending: true })
        .limit(limit);

      if (error) throw error;
      return json({ ok: true, count: data?.length ?? 0, reports: data ?? [] });
    }

    if (req.method === "POST") {
      const body = (await req.json()) as DecisionRequest;
      const reportId = body?.reportId;
      const decision = body?.decision as Decision | undefined;

      if (!reportId || !decision || !DECISIONS.includes(decision)) {
        return json(
          { error: `reportId and decision (${DECISIONS.join(" | ")}) are required` },
          400,
        );
      }
      const note = typeof body.note === "string" ? body.note.slice(0, 2000) : null;

      const { data: report, error: readError } = await admin
        .from("reports")
        .select("id, reported_user_id")
        .eq("id", reportId)
        .maybeSingle();
      if (readError) throw readError;
      if (!report) return json({ error: "No such report." }, 404);

      const reviewedAt = new Date().toISOString();
      const { error: updateError } = await admin
        .from("reports")
        .update({
          status: decision,
          reviewed_at: reviewedAt,
          reviewer_id: user.userId,
          reviewer_note: note,
        })
        .eq("id", reportId);
      if (updateError) throw updateError;

      // The trail is written second and separately, so a decision is
      // recorded even once the report row itself is cleaned up.
      const { error: auditError } = await admin
        .from("moderation_actions")
        .insert({
          report_id: reportId,
          moderator_id: user.userId,
          action: decision,
          subject_user_id: report.reported_user_id,
          note,
        });
      if (auditError) throw auditError;

      return json({ ok: true, reportId, status: decision, reviewedAt });
    }

    return json({ error: "Method not allowed" }, 405);
  } catch (err) {
    if (err instanceof AuthError) {
      return json({ error: "Unauthorized" }, 401);
    }
    console.error("[moderation]", err);
    return json({ error: "Moderation request failed" }, 500);
  }
});
