// golden-hour-sweep
//
// Makes Golden Hour ephemerality REAL: once a circle's viewing hour has
// fully ended, this function deletes the captured media from the private
// `golden-hour` Storage bucket and nulls the `media_path` on each post
// row. The rows themselves survive as the residue — attendance counts
// and streaks — but the pixels are gone forever.
//
// Triggered two ways: on a schedule (pg_cron, presenting SWEEP_SECRET —
// see 20261120000113), and opportunistically by any signed-in client
// (on app open and when a wall is seen to be expired). Letting any
// member trigger it is safe because the request carries no parameters:
// it is idempotent and only ever touches posts whose viewing hour ended
// more than a small grace period ago, by the server's clock, so a
// malicious client can't delete anything early or choose what goes.
//
// One exception to "gone when the hour ends": a capture with an OPEN
// report against it is held until the report is reviewed (or two weeks
// pass). Otherwise the evidence for every Golden Hour report would
// delete itself before anyone could look at it. The wall still closes
// on time in the app; only the stored object waits.

import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Viewing window length (1 hour) plus a small grace period so clocks
 *  slightly out of sync never see media vanish before the timer hits 0. */
const EXPIRY_MS = 65 * 60 * 1000;

interface PostRow {
  id: string;
  media_path: string | null;
  fired_at: string;
}

/** A held post is released after this long even if nobody reviewed the
 *  report. The hold exists so a moderator has something to look at; it
 *  must not become a way to make "vanishes" untrue forever just because
 *  a queue went unattended. */
const REVIEW_HOLD_MAX_MS = 14 * 24 * 60 * 60 * 1000;

/** Byte-wise comparison that takes the same time whether the first
 *  character differs or the last. */
function sameSecret(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

/** True when the caller is the scheduler: it presents the shared
 *  SWEEP_SECRET in `x-sweep-secret` instead of a member's JWT (see
 *  20261120000113). Unset, or too short to be a real secret, and this
 *  path simply does not exist. */
function isScheduler(req: Request): boolean {
  const expected = Deno.env.get("SWEEP_SECRET") ?? "";
  const given = req.headers.get("x-sweep-secret") ?? "";
  return expected.length >= 16 && sameSecret(given, expected);
}

/** Ids of posts that have an open report against them. Their media is
 *  the evidence, so it is held until the report is reviewed. A failed
 *  lookup holds nothing: the sweep's promise comes first, and on a
 *  database that predates the column there is nothing to hold. */
async function heldForReview(
  admin: ReturnType<typeof createAdminClient>,
  column: string,
): Promise<Set<string>> {
  const since = new Date(Date.now() - REVIEW_HOLD_MAX_MS).toISOString();
  const { data, error } = await admin
    .from("reports")
    .select(column)
    .eq("status", "open")
    .not(column, "is", null)
    .gte("created_at", since)
    .limit(500);
  if (error) {
    console.error("sweep: report hold lookup failed, holding nothing:", error);
    return new Set();
  }
  const rows = (data ?? []) as unknown as Record<string, string | null>[];
  return new Set(rows.map((r) => r[column]).filter((id): id is string => !!id));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!isScheduler(req)) {
      await requireAuth(req);
    }
    const admin = createAdminClient();
    const held = await heldForReview(admin, "golden_hour_post_id");

    const cutoff = new Date(Date.now() - EXPIRY_MS).toISOString();
    const { data: expired, error } = await admin
      .from("golden_hour_posts")
      .select("id, media_path, fired_at")
      .not("media_path", "is", null)
      .lt("fired_at", cutoff)
      // Held rows are filtered out below, so leave room for them here
      // or a queue of reports could crowd out everything else.
      .limit(200 + held.size);

    if (error) {
      console.error("sweep query failed:", error);
      return json({ error: "Query failed" }, 500);
    }

    const rows = ((expired ?? []) as PostRow[]).filter((r) => !held.has(r.id));
    if (rows.length === 0) {
      return json({ ok: true, deleted: 0, held: held.size });
    }

    const paths = rows.map((r) => r.media_path).filter((p): p is string => !!p);
    if (paths.length > 0) {
      const { error: removeError } = await admin.storage.from("golden-hour").remove(paths);
      if (removeError) {
        // Log but continue — nulling the rows still hides the media, and
        // the next sweep retries any stragglers.
        console.error("storage remove failed:", removeError);
      }
    }

    const { error: updateError } = await admin
      .from("golden_hour_posts")
      .update({ media_path: null })
      .in("id", rows.map((r) => r.id));

    if (updateError) {
      console.error("row null-out failed:", updateError);
      return json({ error: "Update failed" }, 500);
    }

    return json({ ok: true, deleted: rows.length, held: held.size });
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
