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
// Triggered opportunistically by any signed-in client, like the Golden
// Hour sweep. Idempotent, and the cutoff is computed server-side, so a
// client cannot make anything vanish early.

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    await requireAuth(req);
    const admin = createAdminClient();

    const cutoff = new Date(Date.now() - EXPIRY_MS).toISOString();
    const { data: expired, error } = await admin
      .from("story_posts")
      .select("id, media_path")
      .is("circle_id", null)
      .not("media_path", "is", null)
      .lt("created_at", cutoff)
      .limit(200);

    if (error) {
      console.error("stories sweep query failed:", error);
      return json({ error: "Query failed" }, 500);
    }

    const rows = (expired ?? []) as PostRow[];
    if (rows.length === 0) {
      return json({ ok: true, swept: 0 });
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

    return json({ ok: true, swept: rows.length });
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
