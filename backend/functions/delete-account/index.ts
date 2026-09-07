// delete-account
//
// Complete, irreversible account deletion. Removes every row and every
// stored file that belongs to (or personally identifies) the caller:
//
//   • circles they own, and everything inside those circles
//   • their activity in other people's circles (check-offs, events,
//     RSVPs, golden-hour posts, join requests)
//   • the social graph: messages + proof media, friendships, requests,
//     blocks, cheers, pacts, focus sessions, stories with likes /
//     comments / views
//   • personal data: journal notes + folders, season history, cadence
//     routines, contact-matching keys, device push tokens
//   • the proof library: their permanent capture archive, rows + media
//   • storage: avatars, story media, journal media, proof media,
//     golden-hour media, proof-library media
//
// Reports the user filed are removed; reports OTHERS filed about them
// are kept (anonymised — reported_user_id cleared) so moderation
// history survives without pointing at a deleted person.
//
// Every step is wrapped so one failed table never strands the rest;
// the profile row is deleted last, after all references to it are gone.

import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// deno-lint-ignore no-explicit-any
type Admin = any;

/** Run a deletion step, logging failures without aborting the rest. */
async function step(label: string, fn: () => Promise<unknown>): Promise<void> {
  try {
    await fn();
  } catch (err) {
    console.error(`delete-account step failed [${label}]:`, err);
  }
}

/** Remove storage objects in chunks (the API caps batch size). */
async function removePaths(admin: Admin, bucket: string, paths: string[]): Promise<void> {
  for (let i = 0; i < paths.length; i += 100) {
    const chunk = paths.slice(i, i + 100);
    try {
      await admin.storage.from(bucket).remove(chunk);
    } catch (err) {
      console.error(`storage remove failed [${bucket}]:`, err);
    }
  }
}

/** Delete every file directly inside `bucket/{folder}/`.
 *
 *  Loops rather than taking a single page. A one-shot `list` capped at
 *  1000 quietly left everything past the first thousand objects behind —
 *  and "we deleted most of your photos" is not what account deletion
 *  promises. Every path this app writes is flat (`<userId>/<file>`), so
 *  listing the folder does reach every file; there are no subfolders
 *  hiding below.
 *
 *  Each pass re-lists from the start because the previous pass deleted
 *  what it saw, so offsets would shift underneath us. The pass counter
 *  is a guard against a delete that silently fails: without it, a bucket
 *  that refuses removal would spin here forever.
 */
async function clearFolder(admin: Admin, bucket: string, folder: string): Promise<void> {
  const pageSize = 1000;
  const maxPasses = 50; // 50k objects — far past any real account.
  try {
    for (let pass = 0; pass < maxPasses; pass++) {
      const { data: files } = await admin.storage
        .from(bucket)
        .list(folder, { limit: pageSize });
      if (!files || files.length === 0) return;
      const paths = files.map((f: { name: string }) => `${folder}/${f.name}`);
      await removePaths(admin, bucket, paths);
      if (files.length < pageSize) return;
    }
    console.error(`storage folder clear hit the pass limit [${bucket}/${folder}]`);
  } catch (err) {
    console.error(`storage folder clear failed [${bucket}/${folder}]:`, err);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const user = await requireAuth(req);
    const uid = user.userId;
    const admin: Admin = createAdminClient();

    // ── 0. Collect storage paths BEFORE their rows disappear ─────────
    let proofPaths: string[] = [];
    await step("collect proof media", async () => {
      const { data } = await admin
        .from("direct_messages")
        .select("media_path")
        .or(`sender_id.eq.${uid},recipient_id.eq.${uid}`)
        .not("media_path", "is", null);
      proofPaths = (data ?? []).map((r: { media_path: string }) => r.media_path);
    });

    let goldenPaths: string[] = [];
    await step("collect golden media", async () => {
      const { data } = await admin
        .from("golden_hour_posts")
        .select("media_path")
        .eq("user_id", uid)
        .not("media_path", "is", null);
      goldenPaths = (data ?? []).map((r: { media_path: string }) => r.media_path);
    });

    let myPostIds: string[] = [];
    await step("collect story posts", async () => {
      const { data } = await admin.from("story_posts").select("id").eq("author_id", uid);
      myPostIds = (data ?? []).map((r: { id: string }) => r.id);
    });

    // ── 1. Tear down circles this user owns (and everything inside) ──
    const { data: owned } = await admin.from("circles").select("id").eq("owner_id", uid);
    const ownedIds = (owned ?? []).map((c: { id: string }) => c.id);
    if (ownedIds.length > 0) {
      // Events in owned circles, with their RSVP / check-in children.
      await step("owned circle events", async () => {
        const { data: events } = await admin.from("circle_events").select("id").in("circle_id", ownedIds);
        const eventIds = (events ?? []).map((e: { id: string }) => e.id);
        if (eventIds.length > 0) {
          await admin.from("circle_event_checkins").delete().in("event_id", eventIds);
          await admin.from("circle_event_rsvps").delete().in("event_id", eventIds);
        }
        await admin.from("circle_events").delete().in("circle_id", ownedIds);
      });
      // Golden hour lives per-circle.
      await step("owned golden hour", async () => {
        await admin.from("golden_hour_posts").delete().in("circle_id", ownedIds);
        await admin.from("golden_hour_picks").delete().in("circle_id", ownedIds);
        await admin.from("golden_hour_settings").delete().in("circle_id", ownedIds);
      });
      await step("owned circle rows", async () => {
        await admin.from("circle_join_requests").delete().in("circle_id", ownedIds);
        await admin.from("circle_task_completions").delete().in("circle_id", ownedIds);
        await admin.from("circle_contributions").delete().in("circle_id", ownedIds);
        await admin.from("circle_tasks").delete().in("circle_id", ownedIds);
        await admin.from("circle_invitations").delete().in("circle_id", ownedIds);
        await admin.from("circle_members").delete().in("circle_id", ownedIds);
        await admin.from("circles").delete().in("id", ownedIds);
      });
    }

    // ── 2. Their own activity inside circles owned by others ─────────
    await step("my circle activity", async () => {
      await admin.from("circle_task_completions").delete().eq("user_id", uid);
      await admin.from("circle_contributions").delete().eq("user_id", uid);
      await admin.from("circle_event_checkins").delete().eq("user_id", uid);
      await admin.from("circle_event_rsvps").delete().eq("user_id", uid);
    });
    // Events they created in other people's circles (children first).
    await step("my created events", async () => {
      const { data: mine } = await admin.from("circle_events").select("id").eq("creator_id", uid);
      const ids = (mine ?? []).map((e: { id: string }) => e.id);
      if (ids.length > 0) {
        await admin.from("circle_event_checkins").delete().in("event_id", ids);
        await admin.from("circle_event_rsvps").delete().in("event_id", ids);
        await admin.from("circle_events").delete().in("id", ids);
      }
    });
    await step("my golden hour", async () => {
      await admin.from("golden_hour_posts").delete().eq("user_id", uid);
      await admin.from("golden_hour_picks").delete().eq("picker_id", uid);
      // Settings rows someone else's circle keeps: just unlink the name.
      await admin.from("golden_hour_settings").update({ updated_by: null }).eq("updated_by", uid);
    });
    await step("my membership rows", async () => {
      await admin.from("circle_join_requests").delete().eq("requester_id", uid);
      await admin.from("circle_members").delete().eq("user_id", uid);
      await admin.from("circle_invitations").delete().or(`inviter_id.eq.${uid},invitee_id.eq.${uid}`);
    });

    // ── 3. Messages, friend graph, cheers, moderation rows ───────────
    await step("messages + graph", async () => {
      await admin.from("direct_messages").delete().or(`sender_id.eq.${uid},recipient_id.eq.${uid}`);
      await admin.from("friend_requests").delete().or(`requester_id.eq.${uid},addressee_id.eq.${uid}`);
      await admin.from("friendships").delete().or(`user_a.eq.${uid},user_b.eq.${uid}`);
      await admin.from("blocks").delete().or(`blocker_id.eq.${uid},blocked_id.eq.${uid}`);
      await admin.from("cheers").delete().or(`sender_id.eq.${uid},recipient_id.eq.${uid}`);
    });
    await step("reports", async () => {
      // Their filed reports go; reports about them stay, anonymised.
      await admin.from("reports").delete().eq("reporter_id", uid);
      await admin.from("reports").update({ reported_user_id: null }).eq("reported_user_id", uid);
    });
    await step("device tokens", async () => {
      await admin.from("device_tokens").delete().eq("user_id", uid);
    });

    // ── 4. Pacts (theirs entirely; their marks on any other) ─────────
    await step("pacts", async () => {
      const { data: pacts } = await admin
        .from("pacts")
        .select("id")
        .or(`proposer_id.eq.${uid},partner_id.eq.${uid}`);
      const pactIds = (pacts ?? []).map((p: { id: string }) => p.id);
      if (pactIds.length > 0) {
        await admin.from("pact_completions").delete().in("pact_id", pactIds);
        await admin.from("pact_tasks").delete().in("pact_id", pactIds);
        await admin.from("pacts").delete().in("id", pactIds);
      }
      await admin.from("pact_completions").delete().eq("user_id", uid);
    });

    // ── 5. Focus groves ───────────────────────────────────────────────
    await step("focus", async () => {
      const { data: hosted } = await admin.from("focus_blocks").select("id").eq("host_id", uid);
      const blockIds = (hosted ?? []).map((b: { id: string }) => b.id);
      if (blockIds.length > 0) {
        await admin.from("focus_participants").delete().in("block_id", blockIds);
      }
      await admin.from("focus_participants").delete().eq("user_id", uid);
      await admin.from("focus_blocks").delete().eq("host_id", uid);
    });

    // ── 6. Stories: their posts (with all engagement) + their marks ──
    await step("stories", async () => {
      if (myPostIds.length > 0) {
        await admin.from("story_views").delete().in("post_id", myPostIds);
        await admin.from("story_comments").delete().in("post_id", myPostIds);
        await admin.from("story_likes").delete().in("post_id", myPostIds);
      }
      await admin.from("story_views").delete().eq("viewer_id", uid);
      await admin.from("story_comments").delete().eq("user_id", uid);
      await admin.from("story_likes").delete().eq("user_id", uid);
      await admin.from("story_posts").delete().eq("author_id", uid);
    });

    // ── 7. Personal data: journal, seasons, cadence, contacts ────────
    await step("journal", async () => {
      await admin.from("notes").delete().eq("user_id", uid);
      await admin.from("note_folders").delete().eq("user_id", uid);
    });
    await step("season history", async () => {
      await admin.from("season_sync").delete().eq("user_id", uid);
    });
    await step("cadence", async () => {
      await admin.from("cadence_outcome_events").delete().eq("account_id", uid);
      await admin.from("cadence_routines").delete().eq("account_id", uid);
    });
    await step("contact keys", async () => {
      await admin.from("contact_keys").delete().eq("user_id", uid);
    });
    await step("engine state", async () => {
      await admin.from("test_engine_state").delete().like("id", `%${uid}%`);
    });
    // The proof library cascades when the profile row goes at step 9,
    // but every other table is deleted explicitly for the same reason:
    // a wrapped step reports its own failure instead of stranding the
    // rest behind one silent constraint error.
    await step("proof library", async () => {
      await admin.from("proof_library").delete().eq("user_id", uid);
    });

    // ── 8. Storage: every bucket that can hold their bytes ───────────
    await clearFolder(admin, "avatars", uid);
    await clearFolder(admin, "stories", uid);
    await clearFolder(admin, "note-media", uid);
    await clearFolder(admin, "proof-library", uid);
    if (proofPaths.length > 0) await removePaths(admin, "proofs", proofPaths);
    if (goldenPaths.length > 0) await removePaths(admin, "golden-hour", goldenPaths);

    // ── 9. Finally, the profile row itself ───────────────────────────
    await admin.from("profiles").delete().eq("id", uid);

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    if (err instanceof AuthError) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    console.error(err);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
