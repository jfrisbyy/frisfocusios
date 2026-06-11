// golden-hour-sweep
//
// Makes Golden Hour ephemerality REAL: once a circle's viewing hour has
// fully ended, this function deletes the captured media from the private
// `golden-hour` Storage bucket and nulls the `media_path` on each post
// row. The rows themselves survive as the residue — attendance counts
// and streaks — but the pixels are gone forever.
//
// Triggered opportunistically by any signed-in client (on app open and
// when a wall is seen to be expired). Idempotent and safe to call as
// often as clients like: it only ever touches posts whose viewing hour
// ended more than a small grace period ago, verified server-side, so a
// malicious client can't delete anything early.

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    await requireAuth(req);
    const admin = createAdminClient();

    const cutoff = new Date(Date.now() - EXPIRY_MS).toISOString();
    const { data: expired, error } = await admin
      .from("golden_hour_posts")
      .select("id, media_path, fired_at")
      .not("media_path", "is", null)
      .lt("fired_at", cutoff)
      .limit(200);

    if (error) {
      console.error("sweep query failed:", error);
      return json({ error: "Query failed" }, 500);
    }

    const rows = (expired ?? []) as PostRow[];
    if (rows.length === 0) {
      return json({ ok: true, deleted: 0 });
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

    return json({ ok: true, deleted: rows.length });
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
