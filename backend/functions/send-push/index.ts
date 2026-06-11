// send-push
//
// Delivers an Apple Push Notification to one recipient's registered devices.
//
// Fired by the *acting* user's app (the sender / inviter / partner) right
// after a social action lands — at that moment their app is foreground and
// reliably online, so this is a dependable place to trigger a push without
// any database webhooks or background workers.
//
// The notification copy is built entirely server-side from the action
// `type` plus a little context, so the client never decides wording and a
// malicious client can't forge arbitrary alert text. The recipient's device
// tokens are looked up with the admin client (a user can't read another
// user's tokens under RLS).
//
// Graceful no-op: until the Apple push credentials are configured as
// Supabase secrets (APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY), the
// function returns `{ ok: true, skipped: "apns_not_configured" }` and
// nothing breaks — every caller treats push as fire-and-forget.

import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v5.2.0/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// The app's bundle id doubles as the APNs topic. Overridable via env so a
// renamed/white-labelled build can point pushes at the right topic.
const DEFAULT_BUNDLE_ID = "app.rork.c2il3hsv6vzgwqe989xoj";
const APNS_PROD_HOST = "api.push.apple.com";
const APNS_SANDBOX_HOST = "api.sandbox.push.apple.com";

type PushType =
  | "proof"
  | "note"
  | "friend_request"
  | "friend_accept"
  | "circle_invite"
  | "circle_task"
  | "circle_progress"
  | "circle_mode"
  | "golden_post"
  | "cheer"
  | "cheer_reaction"
  | "story_like"
  | "story_comment"
  | "pact_invite"
  | "pact_accept"
  | "focus_invite";

interface PushRequest {
  recipientId: string;
  type: PushType;
  circleId?: string;
  // Optional caption / note preview / task title — clipped before use.
  preview?: string;
  // The direct-message row a proof/note push refers to, so the tapped
  // notification can land directly inside the full-screen player.
  messageId?: string;
}

interface PushCopy {
  title: string;
  body: string;
  // Custom payload keys the app reads to deep-link the tap.
  data: Record<string, string>;
}

/** Normalise the Apple .p8 private key from an env var into PEM text that
 *  `importPKCS8` accepts. Tolerates escaped "\n" newlines and a bare
 *  base64 body with no PEM header. */
function normalizePrivateKey(raw: string): string {
  let key = raw.trim().replace(/\\n/g, "\n");
  if (!key.includes("BEGIN")) {
    key = `-----BEGIN PRIVATE KEY-----\n${key}\n-----END PRIVATE KEY-----`;
  }
  return key;
}

/** Mint a short-lived APNs provider token (ES256 JWT) for token-based auth. */
async function makeProviderToken(keyId: string, teamId: string, privateKeyPem: string): Promise<string> {
  const key = await importPKCS8(normalizePrivateKey(privateKeyPem), "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt()
    .sign(key);
}

function clip(text: string | undefined, max = 120): string {
  const t = (text ?? "").trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

/** Build the alert wording + deep-link payload from the action type. */
function buildCopy(
  type: PushType,
  senderName: string,
  circleName: string,
  preview: string | undefined,
  senderId: string,
  circleId: string | undefined,
  messageId: string | undefined,
): PushCopy {
  const p = clip(preview);
  const threadData = (): Record<string, string> =>
    messageId ? { route: "thread", peerId: senderId, messageId } : { route: "thread", peerId: senderId };
  switch (type) {
    case "proof":
      return {
        title: senderName,
        body: p ? `📷 ${p}` : "Sent you a proof",
        data: threadData(),
      };
    case "note":
      return {
        title: senderName,
        body: p || "Sent you a message",
        data: threadData(),
      };
    case "friend_request":
      return {
        title: "FrisFocus",
        body: `${senderName} sent you a friend request`,
        data: { route: "friends" },
      };
    case "friend_accept":
      return {
        title: "FrisFocus",
        body: `${senderName} accepted your friend request`,
        data: { route: "friends" },
      };
    case "circle_invite":
      return {
        title: circleName,
        body: `${senderName} invited you to ${circleName}`,
        data: { route: "circles" },
      };
    case "circle_task":
      return {
        title: circleName,
        body: p ? `${senderName} checked off "${p}"` : `${senderName} checked off a task`,
        data: { route: "circle", circleId: circleId ?? "" },
      };
    case "circle_progress":
      return {
        title: circleName,
        body: `${senderName} logged progress in ${circleName}`,
        data: { route: "circle", circleId: circleId ?? "" },
      };
    case "circle_mode":
      return {
        title: circleName,
        body: p
          ? `${senderName} switched ${circleName} to ${p}`
          : `${senderName} changed what ${circleName} is doing together`,
        data: { route: "circle", circleId: circleId ?? "" },
      };
    case "golden_post":
      // Golden Hour is its own ephemeral module — the push routes to the
      // golden surface (camera while live, wall during the hour), never
      // to stories or threads. `preview` carries the time remaining
      // (e.g. "3:12 left"), built by the poster's device.
      return {
        title: `Golden Hour · ${circleName}`,
        body: p ? `${senderName} made Golden Hour — ${p}` : `${senderName} made Golden Hour`,
        data: { route: "golden", circleId: circleId ?? "" },
      };
    case "cheer":
      return {
        title: senderName,
        body: p ? `🌞 ${p}` : "sent you a cheer",
        data: { route: "home" },
      };
    case "cheer_reaction":
      // `preview` carries the single emoji the recipient picked.
      return {
        title: senderName,
        body: p ? `reacted ${p} to your cheer` : "reacted to your cheer",
        data: { route: "home" },
      };
    case "story_like":
      return {
        title: "FrisFocus",
        body: `${senderName} liked your story`,
        data: { route: "stories" },
      };
    case "story_comment":
      return {
        title: "FrisFocus",
        body: p ? `${senderName} commented: ${p}` : `${senderName} commented on your story`,
        data: { route: "stories" },
      };
    case "pact_invite":
      return {
        title: "FrisFocus",
        body: p ? `${senderName} proposed a pact: ${p}` : `${senderName} proposed a pact`,
        data: { route: "pacts" },
      };
    case "pact_accept":
      return {
        title: "FrisFocus",
        body: p ? `${senderName} accepted your pact: ${p}` : `${senderName} accepted your pact`,
        data: { route: "pacts" },
      };
    case "focus_invite":
      return {
        title: "FrisFocus",
        body: p ? `${senderName} invited you to focus — ${p}` : `${senderName} invited you to focus together`,
        data: { route: "grove" },
      };
  }
}

interface ApnsResult {
  status: number;
  reason?: string;
}

async function postToApns(
  host: string,
  token: string,
  providerToken: string,
  bundleId: string,
  payload: unknown,
): Promise<ApnsResult> {
  const res = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${providerToken}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });
  if (res.status === 200) {
    await res.body?.cancel();
    return { status: 200 };
  }
  let reason: string | undefined;
  try {
    const parsed = JSON.parse(await res.text());
    reason = parsed?.reason;
  } catch {
    // Non-JSON error body — leave reason undefined.
  }
  return { status: res.status, reason };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const sender = await requireAuth(req);
    const senderId = sender.userId;
    const payload = (await req.json()) as PushRequest;

    if (!payload?.recipientId || !payload?.type) {
      return json({ error: "Missing recipientId or type" }, 400);
    }
    // A user never needs to notify themselves.
    if (payload.recipientId === senderId) {
      return json({ ok: true, sent: 0, skipped: "self" });
    }

    const admin = createAdminClient();

    // Respect blocks in either direction — never notify someone who blocked
    // the sender (or whom the sender blocked).
    const { data: blockRows } = await admin
      .from("blocks")
      .select("id")
      .or(
        `and(blocker_id.eq.${payload.recipientId},blocked_id.eq.${senderId}),and(blocker_id.eq.${senderId},blocked_id.eq.${payload.recipientId})`,
      )
      .limit(1);
    if (blockRows && blockRows.length > 0) {
      return json({ ok: true, sent: 0, skipped: "blocked" });
    }

    // Credentials gate — graceful no-op until the publisher adds the key.
    const keyId = Deno.env.get("APNS_KEY_ID");
    const teamId = Deno.env.get("APNS_TEAM_ID");
    const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
    if (!keyId || !teamId || !privateKey) {
      return json({ ok: true, sent: 0, skipped: "apns_not_configured" });
    }

    // Recipient's devices (admin read — RLS would hide another user's rows).
    const { data: tokenRows } = await admin
      .from("device_tokens")
      .select("token")
      .eq("user_id", payload.recipientId);
    const tokens = (tokenRows ?? []).map((r: { token: string }) => r.token);
    if (tokens.length === 0) {
      return json({ ok: true, sent: 0, skipped: "no_devices" });
    }

    // Resolve display context for the copy.
    const { data: senderProfile } = await admin
      .from("profiles")
      .select("name, username, email")
      .eq("id", senderId)
      .maybeSingle();
    const senderName =
      senderProfile?.name?.trim() ||
      (senderProfile?.username ? `@${senderProfile.username}` : "") ||
      senderProfile?.email ||
      "Someone";

    let circleName = "your circle";
    if (payload.circleId) {
      const { data: circle } = await admin
        .from("circles")
        .select("name")
        .eq("id", payload.circleId)
        .maybeSingle();
      if (circle?.name) circleName = circle.name;
    }

    const copy = buildCopy(payload.type, senderName, circleName, payload.preview, senderId, payload.circleId, payload.messageId);

    // Truthful badge: the real number of things waiting for the recipient
    // (unread direct messages + pending friend requests), never a
    // hardcoded constant. Counted with head-only queries so no rows move.
    const badge = await countBadge(admin, payload.recipientId);

    const apsPayload = {
      aps: {
        alert: { title: copy.title, body: copy.body },
        sound: "default",
        badge,
      },
      ...copy.data,
    };

    const providerToken = await makeProviderToken(keyId, teamId, privateKey);
    const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? DEFAULT_BUNDLE_ID;
    const primaryHost =
      (Deno.env.get("APNS_ENVIRONMENT") ?? "production") === "sandbox" ? APNS_SANDBOX_HOST : APNS_PROD_HOST;
    const fallbackHost = primaryHost === APNS_PROD_HOST ? APNS_SANDBOX_HOST : APNS_PROD_HOST;

    let sent = 0;
    const staleTokens: string[] = [];
    for (const token of tokens) {
      let result = await postToApns(primaryHost, token, providerToken, bundleId, apsPayload);
      // A token minted for the other environment fails with BadDeviceToken —
      // retry the opposite host so dev and production builds both deliver.
      if (result.status === 400 && result.reason === "BadDeviceToken") {
        result = await postToApns(fallbackHost, token, providerToken, bundleId, apsPayload);
      }
      if (result.status === 200) {
        sent += 1;
      } else if (result.status === 410 || result.reason === "Unregistered" || result.reason === "BadDeviceToken") {
        // Device unregistered or invalid — drop it so we stop trying.
        staleTokens.push(token);
      } else {
        console.error(`APNs send failed (${result.status} ${result.reason ?? ""}) for token ${token.slice(0, 8)}…`);
      }
    }

    if (staleTokens.length > 0) {
      await admin.from("device_tokens").delete().in("token", staleTokens);
    }

    return json({ ok: true, sent });
  } catch (err) {
    if (err instanceof AuthError) {
      return json({ error: "Unauthorized" }, 401);
    }
    console.error(err);
    return json({ error: "Internal server error" }, 500);
  }
});

/** The recipient's real badge number: unread direct messages plus
 *  pending friend requests. Falls back to 1 (something *did* just
 *  happen) if either count query fails. */
// deno-lint-ignore no-explicit-any
async function countBadge(admin: any, recipientId: string): Promise<number> {
  try {
    const [{ count: unread }, { count: requests }] = await Promise.all([
      admin
        .from("direct_messages")
        .select("id", { count: "exact", head: true })
        .eq("recipient_id", recipientId)
        .is("read_at", null),
      admin
        .from("friend_requests")
        .select("id", { count: "exact", head: true })
        .eq("addressee_id", recipientId)
        .eq("status", "pending"),
    ]);
    return Math.max(1, (unread ?? 0) + (requests ?? 0));
  } catch {
    return 1;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
