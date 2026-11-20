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
//   GET  ?reportId=<id>          one report with the content it is about
//                                (text, plus hour-long signed media links)
//   POST { reportId, decision: "actioned" | "dismissed", note? }
//   POST { action: "remove", reportId, note? }
//   POST { action: "remove", target: { kind, id }, reportId?, note? }
//          kind: story_post | story_comment | message |
//                golden_hour_post | circle
//   POST { action: "suspend", userId | reportId, reason?, note? }
//   POST { action: "unsuspend", userId, note? }
//
// Recording a decision was never enough on its own: a queue that can
// say "actioned" but cannot take anything down still leaves the content
// up. Removal deletes the row and the stored media behind it.
// Suspension writes `public.suspensions`, which row-level security
// reads (20261120000112) — accounts are third-party identities, so the
// database is the only place a suspension can be enforced. Every action
// lands in `moderation_actions`. Operating notes: backend/MODERATION.md.
//
// One route is NOT a moderator's:
//
//   POST { action: "notify", reportId }
//
// The app calls it right after filing a report, and it posts a short
// line to MODERATION_WEBHOOK_URL (Slack- or Discord-style) so a report
// does not wait for someone to remember to look. It accepts only the
// caller's own, just-filed, still-open report, says nothing about the
// queue in its response, and does nothing at all when the webhook is
// not configured. A database webhook would have been the tidier
// trigger, but that needs pg_net; this needs nothing.

import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";
import { consumeQuota } from "../_shared/rateLimit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const MAX_LIMIT = 200;
const DEFAULT_LIMIT = 50;
const DECISIONS = ["actioned", "dismissed"] as const;
type Decision = (typeof DECISIONS)[number];

/** What a moderator can take down, by the name used in requests and in
 *  the audit trail. */
const TARGET_KINDS = [
  "story_comment",
  "story_post",
  "message",
  "golden_hour_post",
  "circle",
] as const;
type TargetKind = (typeof TARGET_KINDS)[number];

/** The `reports` column that points at each kind. The order of
 *  TARGET_KINDS is also the order a report is resolved in — most
 *  specific first, because a comment report carries its post's id too,
 *  and a circle last, because removing one is the widest action here
 *  and should never be what an ambiguous report falls through to. */
const REPORT_COLUMN: Record<TargetKind, string> = {
  story_comment: "story_comment_id",
  story_post: "story_post_id",
  message: "message_id",
  golden_hour_post: "golden_hour_post_id",
  circle: "circle_id",
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** How long a signed evidence link works. Long enough to look, short
 *  enough that a pasted link is dead by the end of the day. */
const EVIDENCE_URL_TTL_S = 60 * 60;

/** A report can only announce itself while it is fresh — this is a
 *  "one was just filed" ping, not a way to re-raise old ones. */
const NOTIFY_WINDOW_MS = 10 * 60 * 1000;
/** Generous for a person, tight for a loop. Over the line the report is
 *  still filed and still in the queue; it just does not ping. */
const NOTIFY_LIMITS = { hourly: 12, daily: 40 };

type Admin = ReturnType<typeof createAdminClient>;

interface ActionRequest {
  action?: string;
  reportId?: string;
  decision?: string;
  note?: string;
  target?: { kind?: string; id?: string };
  userId?: string;
  reason?: string;
}

interface ReportRow {
  id: string;
  reporter_id: string;
  reported_user_id: string | null;
  reason: string;
  status: string;
  created_at: string;
  message_id?: string | null;
  story_post_id?: string | null;
  story_comment_id?: string | null;
  golden_hour_post_id?: string | null;
  circle_id?: string | null;
}

interface Target {
  kind: TargetKind;
  id: string;
}

interface Removal {
  /** False when the content was already gone — still a success. */
  found: boolean;
  /** Whose content it was, for the audit trail. */
  subjectUserId: string | null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isTargetKind(value: unknown): value is TargetKind {
  return typeof value === "string" && (TARGET_KINDS as readonly string[]).includes(value);
}

/** The content a report points at, most specific first. Null for a
 *  report that is only about a person. */
function targetFromReport(report: ReportRow): Target | null {
  const columns = report as unknown as Record<string, string | null | undefined>;
  for (const kind of TARGET_KINDS) {
    const id = columns[REPORT_COLUMN[kind]];
    if (id) return { kind, id };
  }
  return null;
}

async function loadReport(admin: Admin, reportId: string): Promise<ReportRow | null> {
  // `*` rather than a column list, so this function does not depend on
  // which report-target columns the database has grown so far.
  const { data, error } = await admin
    .from("reports")
    .select("*")
    .eq("id", reportId)
    .maybeSingle();
  if (error) throw error;
  return (data as ReportRow | null) ?? null;
}

/** Delete stored media. Logged and survived: the row delete that
 *  follows is what takes the content out of the app, and a path that is
 *  already gone must not stop it. */
async function removeMedia(admin: Admin, bucket: string, paths: (string | null)[]): Promise<void> {
  const clean = paths.filter((p): p is string => !!p);
  for (let i = 0; i < clean.length; i += 100) {
    const { error } = await admin.storage.from(bucket).remove(clean.slice(i, i + 100));
    if (error) console.error(`[moderation] storage remove failed (${bucket})`, error);
  }
}

/** Take one piece of content down: its media first, then its row.
 *  Idempotent — removing something already removed reports
 *  `found: false` and changes nothing. */
async function removeTarget(admin: Admin, target: Target): Promise<Removal> {
  const gone: Removal = { found: false, subjectUserId: null };
  const { kind, id } = target;

  if (kind === "story_post") {
    const { data, error } = await admin
      .from("story_posts")
      .select("id, author_id, media_path")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (!data) return gone;
    await removeMedia(admin, "stories", [data.media_path]);
    // Likes, comments and views go with it (ON DELETE CASCADE).
    const { error: deleteError } = await admin.from("story_posts").delete().eq("id", id);
    if (deleteError) throw deleteError;
    return { found: true, subjectUserId: data.author_id };
  }

  if (kind === "story_comment") {
    const { data, error } = await admin
      .from("story_comments")
      .select("id, user_id")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (!data) return gone;
    const { error: deleteError } = await admin.from("story_comments").delete().eq("id", id);
    if (deleteError) throw deleteError;
    return { found: true, subjectUserId: data.user_id };
  }

  if (kind === "message") {
    const { data, error } = await admin
      .from("direct_messages")
      .select("id, sender_id, media_path")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (!data) return gone;
    await removeMedia(admin, "proofs", [data.media_path]);
    const { error: deleteError } = await admin.from("direct_messages").delete().eq("id", id);
    if (deleteError) throw deleteError;
    return { found: true, subjectUserId: data.sender_id };
  }

  if (kind === "golden_hour_post") {
    const { data, error } = await admin
      .from("golden_hour_posts")
      .select("id, user_id, media_path")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (!data) return gone;
    await removeMedia(admin, "golden-hour", [data.media_path]);
    const { error: deleteError } = await admin.from("golden_hour_posts").delete().eq("id", id);
    if (deleteError) throw deleteError;
    return { found: true, subjectUserId: data.user_id };
  }

  // A whole circle. Its rows cascade from `circles`; its media does
  // not, so collect the paths before the rows that name them are gone.
  const { data: circle, error: circleError } = await admin
    .from("circles")
    .select("id, owner_id")
    .eq("id", id)
    .maybeSingle();
  if (circleError) throw circleError;
  if (!circle) return gone;

  const { data: clips, error: clipsError } = await admin
    .from("story_posts")
    .select("media_path")
    .eq("circle_id", id)
    .not("media_path", "is", null);
  if (clipsError) throw clipsError;
  const { data: captures, error: capturesError } = await admin
    .from("golden_hour_posts")
    .select("media_path")
    .eq("circle_id", id)
    .not("media_path", "is", null);
  if (capturesError) throw capturesError;

  await removeMedia(admin, "stories", (clips ?? []).map((r) => r.media_path as string | null));
  await removeMedia(admin, "golden-hour", (captures ?? []).map((r) => r.media_path as string | null));

  const { error: deleteError } = await admin.from("circles").delete().eq("id", id);
  if (deleteError) throw deleteError;
  return { found: true, subjectUserId: circle.owner_id };
}

/** Other open reports about the same content — closed along with it,
 *  so removing one story does not leave five reports about it open. */
async function openReportsAbout(admin: Admin, target: Target): Promise<string[]> {
  const { data, error } = await admin
    .from("reports")
    .select("id")
    .eq("status", "open")
    .eq(REPORT_COLUMN[target.kind], target.id);
  if (error) {
    // The column may not exist yet on a database that predates it.
    console.error("[moderation] sibling report lookup failed", error);
    return [];
  }
  return (data ?? []).map((r) => r.id as string);
}

async function closeReports(
  admin: Admin,
  reportIds: string[],
  decision: Decision,
  moderatorId: string,
  note: string | null,
): Promise<string> {
  const reviewedAt = new Date().toISOString();
  if (reportIds.length === 0) return reviewedAt;
  const { error } = await admin
    .from("reports")
    .update({
      status: decision,
      reviewed_at: reviewedAt,
      reviewer_id: moderatorId,
      reviewer_note: note,
    })
    .in("id", reportIds);
  if (error) throw error;
  return reviewedAt;
}

async function signedUrl(admin: Admin, bucket: string, path: string | null): Promise<string | null> {
  if (!path) return null;
  const { data, error } = await admin.storage.from(bucket).createSignedUrl(path, EVIDENCE_URL_TTL_S);
  if (error) {
    console.error(`[moderation] signed url failed (${bucket})`, error);
    return null;
  }
  return data?.signedUrl ?? null;
}

/** Everything a moderator needs to decide, in one response: the text,
 *  a link to the media, and who it is about. A key that is present and
 *  null means "the report pointed here and it is already gone". */
async function evidenceFor(admin: Admin, report: ReportRow): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};

  if (report.story_comment_id) {
    const { data } = await admin
      .from("story_comments")
      .select("id, post_id, user_id, body, created_at")
      .eq("id", report.story_comment_id)
      .maybeSingle();
    out.story_comment = data ?? null;
  }
  if (report.story_post_id) {
    const { data } = await admin
      .from("story_posts")
      .select("id, author_id, caption, media_path, media_kind, circle_id, created_at")
      .eq("id", report.story_post_id)
      .maybeSingle();
    out.story_post = data
      ? { ...data, signed_media_url: await signedUrl(admin, "stories", data.media_path) }
      : null;
  }
  if (report.message_id) {
    const { data } = await admin
      .from("direct_messages")
      .select("id, sender_id, recipient_id, kind, body, media_path, media_kind, created_at")
      .eq("id", report.message_id)
      .maybeSingle();
    out.message = data
      ? { ...data, signed_media_url: await signedUrl(admin, "proofs", data.media_path) }
      : null;
  }
  if (report.golden_hour_post_id) {
    const { data } = await admin
      .from("golden_hour_posts")
      .select("id, circle_id, day, user_id, media_path, media_kind, fired_at, posted_at")
      .eq("id", report.golden_hour_post_id)
      .maybeSingle();
    out.golden_hour_post = data
      ? { ...data, signed_media_url: await signedUrl(admin, "golden-hour", data.media_path) }
      : null;
  }
  if (report.circle_id) {
    const { data } = await admin
      .from("circles")
      .select("id, owner_id, name, description, visibility, join_rule, created_at")
      .eq("id", report.circle_id)
      .maybeSingle();
    out.circle = data ?? null;
  }
  if (report.reported_user_id) {
    const { data: profile } = await admin
      .from("profiles")
      .select("id, name, username, created_at")
      .eq("id", report.reported_user_id)
      .maybeSingle();
    const { data: suspension } = await admin
      .from("suspensions")
      .select("user_id, reason, created_at")
      .eq("user_id", report.reported_user_id)
      .maybeSingle();
    const { count } = await admin
      .from("moderation_actions")
      .select("id", { count: "exact", head: true })
      .eq("subject_user_id", report.reported_user_id);
    out.reported_user = {
      profile: profile ?? null,
      suspension: suspension ?? null,
      prior_actions: count ?? 0,
    };
  }
  return out;
}

/** Post one line to the moderation webhook, if there is one. The body
 *  carries both `text` (Slack) and `content` (Discord); each ignores
 *  the other's key. Never throws: a webhook outage must not turn a
 *  filed report into an error on someone's screen. */
async function postWebhook(text: string): Promise<boolean> {
  const url = Deno.env.get("MODERATION_WEBHOOK_URL") ?? "";
  if (url.length === 0) return false;
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text, content: text }),
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) {
      console.error("[moderation] webhook returned", res.status);
      return false;
    }
    return true;
  } catch (err) {
    console.error("[moderation] webhook failed", err);
    return false;
  }
}

/** The member-facing route: "I just filed this one". */
async function handleNotify(admin: Admin, userId: string, body: ActionRequest): Promise<Response> {
  const reportId = body.reportId;
  if (typeof reportId !== "string" || !UUID_RE.test(reportId)) {
    return json({ error: "reportId is required" }, 400);
  }

  const report = await loadReport(admin, reportId);
  // Only ever the caller's own report: nobody can use this to learn
  // that a report exists, or to raise someone else's.
  if (!report || report.reporter_id !== userId) {
    return json({ error: "No such report." }, 404);
  }

  const age = Date.now() - new Date(report.created_at).getTime();
  if (report.status !== "open" || age > NOTIFY_WINDOW_MS) {
    return json({ ok: true, notified: false });
  }

  const quota = await consumeQuota(userId, "report-notify", NOTIFY_LIMITS);
  if (!quota.allowed) {
    return json({ ok: true, notified: false });
  }

  const { count } = await admin
    .from("reports")
    .select("id", { count: "exact", head: true })
    .eq("status", "open");

  const target = targetFromReport(report);
  const about = target ? target.kind.replaceAll("_", " ") : "a person";
  // Ids and the picked reason only — never the reporter's free text,
  // which can name people and would be leaving for a third party.
  const text = [
    `New FrisFocus report: ${report.reason.slice(0, 80)}`,
    `About: ${about}${report.reported_user_id ? ` (user ${report.reported_user_id})` : ""}`,
    `Report id: ${report.id}`,
    `Open reports: ${count ?? "?"}`,
  ].join("\n");

  const notified = await postWebhook(text);
  return json({ ok: true, notified });
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
    const admin = createAdminClient();

    let body: ActionRequest = {};
    if (req.method === "POST") {
      let parsed: unknown = null;
      try {
        parsed = await req.json();
      } catch (_err) {
        parsed = null;
      }
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
        return json({ error: "The request body must be a JSON object." }, 400);
      }
      body = parsed as ActionRequest;

      // The one route that belongs to every member, so it is answered
      // before the moderator check — and independently of whether
      // moderation is configured at all.
      if (body.action === "notify") {
        return await handleNotify(admin, user.userId, body);
      }
    }

    const allowed = moderatorIds();
    if (allowed.length === 0) {
      // Say why, without saying who: a caller learns the surface is
      // unconfigured, never who would be allowed if it were.
      return json({ error: "Moderation is not configured." }, 503);
    }
    if (!allowed.includes(user.userId)) {
      return json({ error: "Not found." }, 404);
    }

    if (req.method === "GET") {
      const url = new URL(req.url);

      const oneId = url.searchParams.get("reportId");
      if (oneId !== null) {
        if (!UUID_RE.test(oneId)) return json({ error: "reportId is not a valid id" }, 400);
        const report = await loadReport(admin, oneId);
        if (!report) return json({ error: "No such report." }, 404);
        const evidence = await evidenceFor(admin, report);
        return json({ ok: true, report, target: targetFromReport(report), evidence });
      }

      const status = url.searchParams.get("status") ?? "open";
      const requested = Number(url.searchParams.get("limit") ?? DEFAULT_LIMIT);
      const limit = Number.isFinite(requested)
        ? Math.min(Math.max(1, Math.trunc(requested)), MAX_LIMIT)
        : DEFAULT_LIMIT;

      const { data, error } = await admin
        .from("reports")
        .select("*")
        .eq("status", status)
        // Oldest first: the thing waiting longest is the thing most at
        // risk of breaching a response-time expectation.
        .order("created_at", { ascending: true })
        .limit(limit);

      if (error) throw error;
      return json({ ok: true, count: data?.length ?? 0, reports: data ?? [] });
    }

    if (req.method === "POST") {
      const note = typeof body.note === "string" ? body.note.slice(0, 2000) : null;
      const reportId = typeof body.reportId === "string" ? body.reportId : null;
      if (reportId !== null && !UUID_RE.test(reportId)) {
        return json({ error: "reportId is not a valid id" }, 400);
      }

      // ── Take content down ────────────────────────────────────────
      if (body.action === "remove") {
        const report = reportId ? await loadReport(admin, reportId) : null;
        if (reportId && !report) return json({ error: "No such report." }, 404);

        let target: Target | null = null;
        if (body.target !== undefined) {
          const kind = body.target?.kind;
          const id = body.target?.id;
          if (!isTargetKind(kind) || typeof id !== "string" || !UUID_RE.test(id)) {
            return json(
              { error: `target must be { kind: ${TARGET_KINDS.join(" | ")}, id: <uuid> }` },
              400,
            );
          }
          target = { kind, id };
        } else if (report) {
          target = targetFromReport(report);
        }
        if (!target) {
          return json(
            {
              error:
                "Nothing to remove: this report is about a person, not a piece of content. Pass target { kind, id }, or use suspend.",
            },
            400,
          );
        }

        // Read the sibling reports BEFORE the delete: for most kinds the
        // delete nulls the very column that ties them to this content.
        const related = await openReportsAbout(admin, target);
        const removal = await removeTarget(admin, target);

        const toClose = reportId && !related.includes(reportId) ? [...related, reportId] : related;
        const reviewedAt = await closeReports(admin, toClose, "actioned", user.userId, note);

        const { error: auditError } = await admin
          .from("moderation_actions")
          .insert({
            report_id: reportId,
            moderator_id: user.userId,
            action: "remove",
            subject_user_id: removal.subjectUserId ?? report?.reported_user_id ?? null,
            note,
            target_kind: target.kind,
            target_id: target.id,
          });
        if (auditError) throw auditError;

        return json({
          ok: true,
          action: "remove",
          target,
          removed: removal.found,
          subjectUserId: removal.subjectUserId,
          reportsClosed: toClose,
          reviewedAt,
        });
      }

      // ── Suspend / lift a suspension ──────────────────────────────
      if (body.action === "suspend" || body.action === "unsuspend") {
        const report = reportId ? await loadReport(admin, reportId) : null;
        if (reportId && !report) return json({ error: "No such report." }, 404);

        const userId = typeof body.userId === "string" && body.userId.trim().length > 0
          ? body.userId.trim()
          : report?.reported_user_id ?? null;
        if (!userId) {
          return json({ error: "userId is required (or a reportId that names a person)." }, 400);
        }
        // A moderator locking out a moderator — themselves included — is
        // far more likely a pasted wrong id than an intention.
        if (allowed.includes(userId)) {
          return json({ error: "That account is a moderator." }, 400);
        }

        if (body.action === "suspend") {
          const { data: profile, error: profileError } = await admin
            .from("profiles")
            .select("id")
            .eq("id", userId)
            .maybeSingle();
          if (profileError) throw profileError;
          if (!profile) return json({ error: "No such account." }, 404);

          // Shown to the suspended person in the app; the moderator's
          // own note stays in the audit trail.
          const reason = typeof body.reason === "string" ? body.reason.slice(0, 500) : null;
          const { error: suspendError } = await admin
            .from("suspensions")
            .upsert({ user_id: userId, reason }, { onConflict: "user_id" });
          if (suspendError) throw suspendError;
        } else {
          const { error: liftError } = await admin
            .from("suspensions")
            .delete()
            .eq("user_id", userId);
          if (liftError) throw liftError;
        }

        const toClose = reportId && body.action === "suspend" ? [reportId] : [];
        const reviewedAt = await closeReports(admin, toClose, "actioned", user.userId, note);

        const { error: auditError } = await admin
          .from("moderation_actions")
          .insert({
            report_id: reportId,
            moderator_id: user.userId,
            action: body.action,
            subject_user_id: userId,
            note,
            target_kind: "user",
            target_id: userId,
          });
        if (auditError) throw auditError;

        return json({
          ok: true,
          action: body.action,
          userId,
          suspended: body.action === "suspend",
          reportsClosed: toClose,
          reviewedAt,
        });
      }

      if (body.action !== undefined) {
        return json(
          { error: "Unknown action. Use remove, suspend, unsuspend, or a decision." },
          400,
        );
      }

      // ── Record a decision without acting ─────────────────────────
      const decision = body.decision as Decision | undefined;

      if (!reportId || !decision || !DECISIONS.includes(decision)) {
        return json(
          { error: `reportId and decision (${DECISIONS.join(" | ")}) are required` },
          400,
        );
      }

      const report = await loadReport(admin, reportId);
      if (!report) return json({ error: "No such report." }, 404);

      const reviewedAt = await closeReports(admin, [reportId], decision, user.userId, note);

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
