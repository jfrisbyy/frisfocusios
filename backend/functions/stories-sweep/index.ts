// stories-sweep
//
// Makes the app's promise about stories true in storage, not just in the
// UI.
//
// A general story post expires 24 hours after it is made. Every surface
// already honours that — `isExpired()` filters them out of every view,
// and `refreshStories` will not even fetch them — and a First Light
// lesson tells people in as many words that stories vanish after a day.
// But nothing ever deleted the bytes: the row stayed, the object stayed
// in the private `stories` bucket, and the bucket's read policy grants
// access on friendship and circle membership, never on age. So an
// "expired" photo remained fetchable indefinitely by anyone still
// friends with its author. The app was keeping the promise on screen and
// breaking it on disk.
//
// Mirrors `golden-hour-sweep` deliberately, including its residue model:
// the media is destroyed and `media_path` / `media_url` are nulled, while
// the row itself survives. Deleting rows would cascade into likes,
// comments and views — history about a real moment that people may still
// reference — and the pixels are the part the promise is about.
//
// CIRCLE CLIPS ARE NEVER SWEPT. They deliberately do not expire (the
// lesson says so, and "Our story" reads them back years later), which is
// why every query here is scoped to `circle_id is null`.
//
// Triggered two ways, like the Golden Hour sweep: on a schedule
// (pg_cron, presenting SWEEP_SECRET — see 20261120000113), and
// opportunistically by any signed-in client. Idempotent, parameterless,
// and the cutoff is computed server-side, so a client cannot make
// anything vanish early.
//
// A story with an OPEN report against it is held until the report is
// reviewed (or two weeks pass): a report filed in a story's last hour
// would otherwise have nothing left to review.

import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** 24 hours, plus an hour of grace so a clock slightly out of sync never
 *  destroys a story the person can still see counting down. Matches the
 *  25-hour window `refreshStories` fetches. */
const EXPIRY_MS = 25 * 60 * 60 * 1000;

interface PostRow {
  id: string;
  media_path: string | null;
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
    const held = await heldForReview(admin, "story_post_id");

    const cutoff = new Date(Date.now() - EXPIRY_MS).toISOString();
    const { data: expired, error } = await admin
      .from("story_posts")
      .select("id, media_path")
      .is("circle_id", null)
      .not("media_path", "is", null)
      .lt("created_at", cutoff)
      // Held rows are filtered out below, so leave room for them here
      // or a queue of reports could crowd out everything else.
      .limit(200 + held.size);

    if (error) {
      console.error("stories sweep query failed:", error);
      return json({ error: "Query failed" }, 500);
    }

    const rows = ((expired ?? []) as PostRow[]).filter((r) => !held.has(r.id));
    if (rows.length === 0) {
      return json({ ok: true, swept: 0, held: held.size });
    }

    const paths = rows.map((r) => r.media_path).filter((p): p is string => !!p);
    if (paths.length > 0) {
      const { error: removeError } = await admin.storage.from("stories").remove(paths);
      if (removeError) {
        // Log and continue: nulling the columns still severs every path
        // the app has to the object, and the next sweep retries the
        // stragglers.
        console.error("stories storage remove failed:", removeError);
      }
    }

    const { error: updateError } = await admin
      .from("story_posts")
      .update({ media_path: null, media_url: null })
      .in("id", rows.map((r) => r.id));

    if (updateError) {
      console.error("stories row null-out failed:", updateError);
      return json({ error: "Update failed" }, 500);
    }

    return json({ ok: true, swept: rows.length, held: held.size });
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
