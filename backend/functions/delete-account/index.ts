import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const user = await requireAuth(req);
    const uid = user.userId;
    const admin = createAdminClient();

    // 1. Tear down circles this user owns (and everything inside them).
    const { data: owned } = await admin.from("circles").select("id").eq("owner_id", uid);
    const ownedIds = (owned ?? []).map((c: { id: string }) => c.id);
    if (ownedIds.length > 0) {
      await admin.from("circle_task_completions").delete().in("circle_id", ownedIds);
      await admin.from("circle_contributions").delete().in("circle_id", ownedIds);
      await admin.from("circle_tasks").delete().in("circle_id", ownedIds);
      await admin.from("circle_invitations").delete().in("circle_id", ownedIds);
      await admin.from("circle_members").delete().in("circle_id", ownedIds);
      await admin.from("circles").delete().in("id", ownedIds);
    }

    // 2. Remove the user's own activity in circles owned by others.
    await admin.from("circle_task_completions").delete().eq("user_id", uid);
    await admin.from("circle_contributions").delete().eq("user_id", uid);
    await admin.from("circle_members").delete().eq("user_id", uid);
    await admin.from("circle_invitations").delete().or(`inviter_id.eq.${uid},invitee_id.eq.${uid}`);

    // 3. Messages, friend graph, and moderation rows touching this user.
    await admin.from("direct_messages").delete().or(`sender_id.eq.${uid},recipient_id.eq.${uid}`);
    await admin.from("friend_requests").delete().or(`requester_id.eq.${uid},addressee_id.eq.${uid}`);
    await admin.from("friendships").delete().or(`user_a.eq.${uid},user_b.eq.${uid}`);
    await admin.from("blocks").delete().or(`blocker_id.eq.${uid},blocked_id.eq.${uid}`);
    await admin.from("reports").delete().eq("reporter_id", uid);
    await admin.from("device_tokens").delete().eq("user_id", uid);

    // 4. Best-effort: clear the user's avatar files.
    try {
      const { data: files } = await admin.storage.from("avatars").list(uid);
      if (files && files.length > 0) {
        const paths = files.map((f: { name: string }) => `${uid}/${f.name}`);
        await admin.storage.from("avatars").remove(paths);
      }
    } catch (_err) {
      // Storage cleanup is non-critical; ignore failures.
    }

    // 5. Finally the profile row itself.
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
