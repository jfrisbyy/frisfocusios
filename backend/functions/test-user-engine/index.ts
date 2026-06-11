// test-user-engine
//
// Drives the simulated test accounts (profiles with is_test = true) so
// they behave like living friends: they auto-accept friend requests,
// reply to messages, post stories with real media, like/comment/view
// the caller's posts, send the occasional cheer, keep their side of
// pacts and circles moving, and join live focus groves.
//
// Trigger model: the app pokes this function (fire-and-forget) on
// launch, on foreground, and right after social actions. Each run is
// idempotent, rate-limited per caller, and scoped to the caller's own
// relationships — so reactions land with natural-feeling delays
// without any cron infrastructure.

import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Persona {
  captions: string[];
  media: string[];
  replies: string[];
  comments: string[];
  cheers: string[];
  welcome: string;
}

const PERSONAS: Record<string, Persona> = {
  "test-maya": {
    captions: [
      "5 miles before the heat. Worth every step 🌄",
      "Trail legs are back",
      "Sunrise paid me back for the alarm",
      "Easy recovery run, hard to complain with this view",
    ],
    media: ["https://r2-pub.rork.com/generated-images/c8b51f5f-a37a-49c3-8b06-48bc2223dffb.png"],
    replies: [
      "Yes!! Love that for you",
      "Okay that's motivating, lacing up tomorrow",
      "Haha same energy over here",
      "Proud of you — keep stacking days",
    ],
    comments: ["Let's gooo 🔥", "This is the consistency I aspire to", "Strong."],
    cheers: ["You've been showing up — I see it 🌞", "One more good day. You've got this."],
    welcome: "Hey! Glad we're connected — let's keep each other honest 🌄",
  },
  "test-eli": {
    captions: [
      "Three pages before coffee got cold. Small win.",
      "The draft is fighting back but I showed up",
      "Morning pages done. Head's quieter already.",
    ],
    media: ["https://r2-pub.rork.com/generated-images/3d355cb2-89cc-419f-a709-7cf9184b0451.png"],
    replies: [
      "That's the good stuff. Keep going",
      "Honestly? Respect.",
      "Adding that to my own list tomorrow",
    ],
    comments: ["Quietly excellent", "The discipline is showing 📝"],
    cheers: ["Word by word, day by day. Keep at it."],
    welcome: "Hey hey — good to be in each other's corner ✍️",
  },
  "test-sana": {
    captions: [
      "20 minutes on the mat before the world woke up",
      "Breathwork + stretch. Body says thank you.",
      "Slow morning, on purpose 🧘",
    ],
    media: ["https://r2-pub.rork.com/generated-images/57def23d-f2d3-4ea6-b80f-1f0a36f792e4.png"],
    replies: ["Love this — steady wins", "You're glowing through the app, I swear", "Breathe in, day's yours"],
    comments: ["So calm, so good 🌿", "This is the way"],
    cheers: ["Gentle reminder: you're doing better than you think 🌿"],
    welcome: "Hi! Excited to share the journey — one calm day at a time 🌿",
  },
  "test-cole": {
    captions: [
      "Lake was 52°F. I am awake. VERY awake.",
      "Plunge #14 — it does not get easier, I get braver",
      "Cold water, clear head",
    ],
    media: ["https://r2-pub.rork.com/generated-images/6f2b7e12-61c0-4434-8f4b-500d87396301.png"],
    replies: ["LET'S GO 🥶", "That's a real one right there", "Built different today huh"],
    comments: ["Absolute machine 🥶", "Couldn't be me. Respect."],
    cheers: ["Do the hard thing first. You always do 💪"],
    welcome: "Yooo welcome! Cold water thinking says you've got big days ahead 🥶",
  },
  "test-ivy": {
    captions: [
      "Inked the rooftops page today 🖋️",
      "Daily sketch done — rough but mine",
      "30 minutes of drawing > 30 minutes of scrolling",
    ],
    media: ["https://r2-pub.rork.com/generated-images/326eae6e-7e09-470b-8a2e-d092596bd549.png"],
    replies: ["Make the thing! Always make the thing", "This made my day honestly", "Yes — art and discipline, same muscle"],
    comments: ["Beautiful little moment 🎨", "Keep the streak alive!"],
    cheers: ["Your consistency is a work of art 🎨"],
    welcome: "Hi! Can't wait to see your moments — I post my daily sketches here 🎨",
  },
  "test-ruben": {
    captions: [
      "32 miles of golden hour. Legs are spent, soul is full 🚴",
      "Climbed the hill I've been avoiding all month",
      "Short spin, but a spin is a spin",
    ],
    media: ["https://r2-pub.rork.com/generated-images/620304f4-1f18-4a8e-8483-3e33555fd106.png"],
    replies: ["Keep pedaling my friend", "That's how it's done 🚴", "We ride at dawn (or whenever, honestly)"],
    comments: ["Miles in the bank 🚴", "The grind is real and so are you"],
    cheers: ["Every mile counts — today included 🚴"],
    welcome: "Hey! Always good to find more people who show up daily 🚴",
  },
  "test-amara": {
    captions: [
      "Chapter 12 down with my tea ☕📚",
      "50 pages tonight. The book won.",
      "Library haul day — future me says thanks",
    ],
    media: [],
    replies: ["Noted and admired 📚", "You love to see it", "Quiet wins are still wins"],
    comments: ["Cozy excellence 📚", "Adding this to my evening routine"],
    cheers: ["A little progress every day — you're living it 📚"],
    welcome: "Hello! So glad we connected — here's to steady, gentle progress 📚",
  },
};

const todayKey = () => new Date().toISOString().slice(0, 10);
const chance = (p: number) => Math.random() < p;
const pick = <T>(arr: T[]): T => arr[Math.floor(Math.random() * arr.length)];

// deno-lint-ignore no-explicit-any
type Admin = any;

async function getStateTime(admin: Admin, id: string): Promise<Date | null> {
  const { data } = await admin.from("test_engine_state").select("last_run_at").eq("id", id).maybeSingle();
  return data?.last_run_at ? new Date(data.last_run_at) : null;
}

async function setStateTime(admin: Admin, id: string) {
  await admin.from("test_engine_state").upsert({ id, last_run_at: new Date().toISOString() });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const caller = await requireAuth(req);
    const callerId = caller.userId;
    const admin = createAdminClient();

    // Per-caller rate limit so a burst of pokes costs one pass.
    const last = await getStateTime(admin, `run:${callerId}`);
    if (last && Date.now() - last.getTime() < 40_000) {
      return json({ ok: true, skipped: "cooldown" });
    }
    await setStateTime(admin, `run:${callerId}`);

    const { data: simRows } = await admin.from("profiles").select("id").eq("is_test", true);
    const simIds: string[] = (simRows ?? []).map((r: { id: string }) => r.id).filter((id: string) => PERSONAS[id]);
    if (simIds.length === 0) return json({ ok: true, skipped: "no_sims" });

    const summary: Record<string, number> = {};
    const bump = (k: string, n = 1) => (summary[k] = (summary[k] ?? 0) + n);

    // ── 1. Accept pending friend requests addressed to sims ───────────
    try {
      const { data: requests } = await admin
        .from("friend_requests")
        .select("id, requester_id, addressee_id")
        .eq("status", "pending")
        .in("addressee_id", simIds);
      for (const r of requests ?? []) {
        const a = r.requester_id < r.addressee_id ? r.requester_id : r.addressee_id;
        const b = r.requester_id < r.addressee_id ? r.addressee_id : r.requester_id;
        await admin.from("friendships").upsert({ user_a: a, user_b: b }, { onConflict: "user_a,user_b", ignoreDuplicates: true });
        await admin.from("friend_requests").update({ status: "accepted", responded_at: new Date().toISOString() }).eq("id", r.id);
        // Warm welcome note so the new friendship feels alive instantly.
        const persona = PERSONAS[r.addressee_id];
        if (persona) {
          await admin.from("direct_messages").insert({
            sender_id: r.addressee_id,
            recipient_id: r.requester_id,
            kind: "note",
            body: persona.welcome,
          });
        }
        bump("friendRequestsAccepted");
      }
    } catch (e) {
      console.error("acceptFriendRequests", e);
    }

    // The caller's sim friends — everything below scopes to them.
    const { data: friendships } = await admin
      .from("friendships")
      .select("user_a, user_b")
      .or(`user_a.eq.${callerId},user_b.eq.${callerId}`);
    const simFriends = (friendships ?? [])
      .map((f: { user_a: string; user_b: string }) => (f.user_a === callerId ? f.user_b : f.user_a))
      .filter((id: string) => simIds.includes(id));

    // ── 2. Accept circle invitations sent to sims ──────────────────────
    try {
      const { data: invites } = await admin
        .from("circle_invitations")
        .select("id, circle_id, invitee_id")
        .eq("status", "pending")
        .in("invitee_id", simIds);
      for (const inv of invites ?? []) {
        const { data: existing } = await admin
          .from("circle_members")
          .select("id")
          .eq("circle_id", inv.circle_id)
          .eq("user_id", inv.invitee_id)
          .maybeSingle();
        if (!existing) {
          await admin.from("circle_members").insert({ circle_id: inv.circle_id, user_id: inv.invitee_id, role: "member" });
        }
        await admin.from("circle_invitations").update({ status: "accepted", responded_at: new Date().toISOString() }).eq("id", inv.id);
        bump("circleInvitesAccepted");
      }
    } catch (e) {
      console.error("acceptCircleInvites", e);
    }

    // ── 3. Accept pending pacts where a sim is the partner ────────────
    try {
      const { data: pacts } = await admin
        .from("pacts")
        .select("id, duration_days, title, proposer_id")
        .eq("status", "pending")
        .in("partner_id", simIds);
      for (const p of pacts ?? []) {
        const start = todayKey();
        const end = new Date(Date.now() + p.duration_days * 86_400_000).toISOString().slice(0, 10);
        await admin
          .from("pacts")
          .update({ status: "active", start_date: start, end_date: end, responded_at: new Date().toISOString() })
          .eq("id", p.id);
        bump("pactsAccepted");
      }
    } catch (e) {
      console.error("acceptPacts", e);
    }

    // ── 4. Reply to unanswered direct messages ─────────────────────────
    try {
      for (const simId of simFriends) {
        const { data: lastMsgs } = await admin
          .from("direct_messages")
          .select("id, sender_id, created_at, body")
          .or(
            `and(sender_id.eq.${callerId},recipient_id.eq.${simId}),and(sender_id.eq.${simId},recipient_id.eq.${callerId})`,
          )
          .order("created_at", { ascending: false })
          .limit(1);
        const lastMsg = lastMsgs?.[0];
        if (!lastMsg || lastMsg.sender_id !== callerId) continue;
        const ageMs = Date.now() - new Date(lastMsg.created_at).getTime();
        if (ageMs < 45_000) continue; // natural typing delay
        const persona = PERSONAS[simId];
        await admin.from("direct_messages").insert({
          sender_id: simId,
          recipient_id: callerId,
          kind: "note",
          body: pick(persona.replies),
        });
        await admin
          .from("direct_messages")
          .update({ read_at: new Date().toISOString() })
          .eq("recipient_id", simId)
          .eq("sender_id", callerId)
          .is("read_at", null);
        bump("replies");
      }
    } catch (e) {
      console.error("replyToMessages", e);
    }

    // ── 5. Sims post fresh stories on a gentle cadence ─────────────────
    try {
      for (const simId of simFriends) {
        const lastStory = await getStateTime(admin, `story:${simId}`);
        const gapHours = 3.5 + Math.random() * 3;
        if (lastStory && Date.now() - lastStory.getTime() < gapHours * 3_600_000) continue;
        const persona = PERSONAS[simId];
        const useMedia = persona.media.length > 0 && chance(0.8);
        await admin.from("story_posts").insert({
          author_id: simId,
          caption: pick(persona.captions),
          media_url: useMedia ? pick(persona.media) : null,
          media_kind: useMedia ? "photo" : null,
        });
        await setStateTime(admin, `story:${simId}`);
        bump("storiesPosted");
      }
    } catch (e) {
      console.error("postStories", e);
    }

    // ── 6. View / like / comment the caller's recent posts ────────────
    try {
      const cutoff = new Date(Date.now() - 24 * 3_600_000).toISOString();
      const { data: posts } = await admin
        .from("story_posts")
        .select("id, caption, created_at")
        .eq("author_id", callerId)
        .gte("created_at", cutoff);
      for (const post of posts ?? []) {
        const ageMs = Date.now() - new Date(post.created_at).getTime();
        if (ageMs < 30_000) continue; // they "haven't seen it yet"
        for (const simId of simFriends) {
          await admin
            .from("story_views")
            .upsert({ post_id: post.id, viewer_id: simId }, { onConflict: "post_id,viewer_id", ignoreDuplicates: true });
          const { data: liked } = await admin
            .from("story_likes")
            .select("id")
            .eq("post_id", post.id)
            .eq("user_id", simId)
            .maybeSingle();
          if (!liked && chance(0.45)) {
            await admin.from("story_likes").insert({ post_id: post.id, user_id: simId });
            bump("likes");
          }
          const { data: commented } = await admin
            .from("story_comments")
            .select("id")
            .eq("post_id", post.id)
            .eq("user_id", simId)
            .limit(1);
          if ((commented ?? []).length === 0 && chance(0.22)) {
            await admin.from("story_comments").insert({
              post_id: post.id,
              user_id: simId,
              body: pick(PERSONAS[simId].comments),
            });
            bump("comments");
          }
        }
      }
    } catch (e) {
      console.error("reactToStories", e);
    }

    // ── 7. Occasional cheer (max one per sim per day) ──────────────────
    try {
      const dayStart = `${todayKey()}T00:00:00Z`;
      for (const simId of simFriends) {
        const { data: sentToday } = await admin
          .from("cheers")
          .select("id")
          .eq("sender_id", simId)
          .eq("recipient_id", callerId)
          .gte("created_at", dayStart)
          .limit(1);
        if ((sentToday ?? []).length === 0 && chance(0.18)) {
          await admin.from("cheers").insert({
            sender_id: simId,
            recipient_id: callerId,
            message: pick(PERSONAS[simId].cheers),
          });
          bump("cheers");
        }
      }
    } catch (e) {
      console.error("sendCheers", e);
    }

    // ── 8. Sims keep their side of active pacts moving ─────────────────
    try {
      const { data: activePacts } = await admin
        .from("pacts")
        .select("id, proposer_id, partner_id")
        .eq("status", "active")
        .or(`proposer_id.eq.${callerId},partner_id.eq.${callerId}`);
      for (const p of activePacts ?? []) {
        const simId = simIds.includes(p.proposer_id) ? p.proposer_id : simIds.includes(p.partner_id) ? p.partner_id : null;
        if (!simId) continue;
        const { data: tasks } = await admin.from("pact_tasks").select("id").eq("pact_id", p.id);
        for (const t of tasks ?? []) {
          const { data: done } = await admin
            .from("pact_completions")
            .select("id")
            .eq("pact_id", p.id)
            .eq("task_id", t.id)
            .eq("user_id", simId)
            .eq("completed_on", todayKey())
            .maybeSingle();
          if (!done && chance(0.55)) {
            await admin.from("pact_completions").insert({
              pact_id: p.id,
              task_id: t.id,
              user_id: simId,
              completed_on: todayKey(),
            });
            bump("pactCompletions");
          }
        }
      }
    } catch (e) {
      console.error("pactCompletions", e);
    }

    // ── 9. Sims stay active inside shared circles ──────────────────────
    try {
      const { data: myMemberships } = await admin
        .from("circle_members")
        .select("circle_id")
        .eq("user_id", callerId);
      const circleIds = (myMemberships ?? []).map((m: { circle_id: string }) => m.circle_id);
      if (circleIds.length > 0) {
        const { data: simMemberships } = await admin
          .from("circle_members")
          .select("circle_id, user_id")
          .in("circle_id", circleIds)
          .in("user_id", simIds);
        for (const m of simMemberships ?? []) {
          const { data: tasks } = await admin
            .from("circle_tasks")
            .select("id")
            .eq("circle_id", m.circle_id);
          for (const t of tasks ?? []) {
            const { data: done } = await admin
              .from("circle_task_completions")
              .select("id")
              .eq("circle_id", m.circle_id)
              .eq("task_id", t.id)
              .eq("user_id", m.user_id)
              .eq("completed_on", todayKey())
              .maybeSingle();
            if (!done && chance(0.4)) {
              await admin.from("circle_task_completions").insert({
                circle_id: m.circle_id,
                task_id: t.id,
                user_id: m.user_id,
                completed_on: todayKey(),
              });
              bump("circleCompletions");
            }
          }
          // Collective circles: log a contribution at most once a day.
          const { data: circle } = await admin
            .from("circles")
            .select("type, collective_unit")
            .eq("id", m.circle_id)
            .maybeSingle();
          if (circle && (circle.type === "collective" || circle.type === "hybrid")) {
            const stateId = `contrib:${m.circle_id}:${m.user_id}:${todayKey()}`;
            const already = await getStateTime(admin, stateId);
            if (!already && chance(0.35)) {
              await admin.from("circle_contributions").insert({
                circle_id: m.circle_id,
                user_id: m.user_id,
                amount: Math.round((1 + Math.random() * 6) * 10) / 10,
              });
              await setStateTime(admin, stateId);
              bump("contributions");
            }
          }
        }
      }
    } catch (e) {
      console.error("circleActivity", e);
    }

    // ── 10. Sims join + live inside the caller's focus grove ───────────
    try {
      const { data: blocks } = await admin
        .from("focus_blocks")
        .select("id, started_at, planned_minutes")
        .eq("host_id", callerId)
        .is("ended_at", null)
        .gte("started_at", new Date(Date.now() - 3 * 3_600_000).toISOString());
      for (const block of blocks ?? []) {
        const { data: participants } = await admin
          .from("focus_participants")
          .select("id, user_id, state, leaf_tier")
          .eq("block_id", block.id)
          .in("user_id", simIds);
        for (const part of participants ?? []) {
          if (part.state === "invited") {
            await admin
              .from("focus_participants")
              .update({ state: "inBlock", leaf_tier: "full", updated_at: new Date().toISOString() })
              .eq("id", part.id);
            bump("groveJoins");
          } else if (part.state === "inBlock" && chance(0.15)) {
            await admin
              .from("focus_participants")
              .update({ state: "steppedAway", updated_at: new Date().toISOString() })
              .eq("id", part.id);
            bump("groveDrift");
          } else if (part.state === "steppedAway") {
            const nextTier = part.leaf_tier === "full" ? "thinning" : part.leaf_tier === "thinning" && chance(0.5) ? "sparse" : part.leaf_tier;
            await admin
              .from("focus_participants")
              .update({ state: "inBlock", leaf_tier: nextTier, updated_at: new Date().toISOString() })
              .eq("id", part.id);
            bump("groveDrift");
          }
        }
      }
    } catch (e) {
      console.error("grovePresence", e);
    }

    return json({ ok: true, summary });
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
