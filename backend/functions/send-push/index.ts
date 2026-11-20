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
// Who may push to whom. A valid session is not enough: the caller names
// the recipient, so without a check any signed-in account could put a
// notification on any other account's lock screen. Every request has to
// clear, in order:
//
//   1. a known `type` — anything else is refused, never guessed at;
//   2. the rate limits (per sender, and per sender→recipient pair);
//   3. the relationship that `type` implies — see `authorize` below for
//      the table. A direct-message push must point at a real message
//      from the sender to the recipient, a friend-request push at a real
//      pending request, a circle push at a circle both people are in;
//   4. the recipient's own block / mute / per-kind preferences.
//
// Steps 1–3 answer with an error (400 / 429 / 403) because they are about
// the SENDER and a legitimate client never trips them. Step 4 is about the
// RECIPIENT's private choices, so it answers 200 with one opaque
// `skipped: "not_delivered"` that is the same for a block, a mute, a
// switched-off kind and a phone with no token — the sender cannot tell
// which, which is the promise a mute makes.
//
// Graceful no-op: until the Apple push credentials are configured as
// Supabase secrets (APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY), the
// function returns `{ ok: true, skipped: "apns_not_configured" }` and
// nothing breaks — every caller treats push as fire-and-forget. It says so
// once per instance in the function log, loudly, because "every push
// succeeded and none arrived" is otherwise indistinguishable from working.

import { requireAuth, createAdminClient, AuthError } from "../_shared/auth.ts";
import { consumeQuota, quotaResponse } from "../_shared/rateLimit.ts";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v5.2.0/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// The app's bundle id doubles as the APNs topic. Overridable via env so a
// renamed/white-labelled build can point pushes at the right topic.
const DEFAULT_BUNDLE_ID = "com.frisfocus.app";
const APNS_PROD_HOST = "api.push.apple.com";
const APNS_SANDBOX_HOST = "api.sandbox.push.apple.com";

// Every kind the app sends — `PushKind` in PushService.swift. A value, not
// only a type, so an incoming `type` can be checked against it at runtime:
// a kind that is not on this list is refused.
const PUSH_TYPES = [
  "proof",
  "note",
  "friend_request",
  "friend_accept",
  "circle_invite",
  "circle_task",
  "circle_progress",
  "circle_mode",
  "circle_event",
  "golden_post",
  "cheer",
  "cheer_reaction",
  "story_like",
  "story_comment",
  "pact_invite",
  "pact_accept",
  "focus_invite",
] as const;

type PushType = (typeof PUSH_TYPES)[number];

function isPushType(value: unknown): value is PushType {
  return typeof value === "string" && (PUSH_TYPES as readonly string[]).includes(value);
}

// Rate limits. One social action is one push per recipient, so a check-off
// in a ten-person circle is nine calls — the per-sender ceiling has to
// clear an active person in several circles, and still stop a loop.
// Refused calls get a 429; the action they were about already landed, only
// its notification is dropped.
//
// Both daily figures stay under 1000 on purpose: the ledger read in
// `consumeQuota` is one PostgREST query, which the API caps at 1000 rows,
// so a higher daily limit could never be counted up to.
const SENDER_LIMITS = { hourly: 400, daily: 900 };
// One person on the receiving end of one sender. Roomy enough for a long
// back-and-forth of notes; far short of a buzzing phone used as a weapon.
const PAIR_LIMITS = { hourly: 90, daily: 300 };

// How many of a recipient's devices one push fans out to (newest first).
const MAX_DEVICES = 10;

// Ids arrive from the client and go into filters. Rork user ids are short
// opaque strings; this allows the punctuation an id plausibly carries and
// refuses whitespace, quotes, commas and brackets outright.
const USER_ID_RE = /^[A-Za-z0-9_.:@|-]{1,128}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// The only thing a golden_post preview may say: the time left, as the
// poster's device formats it ("3:12 left").
const TIME_LEFT_RE = /^\d{1,3}:\d{2} left$/;

interface PushRequest {
  recipientId: string;
  type: PushType;
  circleId?: string;
  // Optional task / event / pact title or comment text. Sanitised and
  // capped before use, and ignored for the kinds whose text the server
  // can read for itself (direct messages, cheers).
  preview?: string;
  // The direct-message row a proof/note push refers to, so the tapped
  // notification can land directly inside the full-screen player. Also
  // the proof that the push is about a message that really exists.
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

/** Make user-authored text safe for a lock screen and cap its length.
 *
 *  Names, circle names, titles and previews are all written by people, and
 *  all end up in an alert on someone else's phone. Control characters and
 *  line breaks become spaces (one alert, one line — no fake second
 *  notification stacked under the first), the invisible direction and
 *  zero-width marks used to disguise or reorder text are dropped, and runs
 *  of whitespace collapse. The zero-width JOINER is deliberately kept: it
 *  is what holds a multi-part emoji together.
 *
 *  Length is counted in code points, not UTF-16 units, so the cut can
 *  never land in the middle of an emoji and leave half a character. */
function clean(text: unknown, max: number): string {
  if (typeof text !== "string") return "";
  const flat = text
    .replace(/\p{Cc}+/gu, " ")
    .replace(/[​‎‏‪-‮⁦-⁩﻿]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  const chars = Array.from(flat);
  return chars.length > max ? `${chars.slice(0, max - 1).join("")}…` : flat;
}

/** The preview a kind is allowed to carry, or undefined for none.
 *
 *  Direct messages and cheers never reach here — their text is read from
 *  the row the push is about. For the rest the client's text is the only
 *  source (a task title, an event title, a comment), so it is sanitised
 *  and held to a length that fits what it is. Kinds whose copy has no
 *  preview, or whose call site never sends one, get none at all rather
 *  than a free-text slot nobody uses legitimately. */
function allowedPreview(type: PushType, raw: unknown): string | undefined {
  let text = "";
  switch (type) {
    case "circle_task":
    case "circle_event":
    case "pact_invite":
    case "pact_accept":
      text = clean(raw, 80);
      break;
    case "focus_invite":
      text = clean(raw, 60);
      break;
    case "story_comment":
      text = clean(raw, 120);
      break;
    case "golden_post": {
      const left = clean(raw, 16);
      text = TIME_LEFT_RE.test(left) ? left : "";
      break;
    }
    default:
      text = "";
  }
  return text.length > 0 ? text : undefined;
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
  const p = clean(preview, 120);
  const threadData =(): Record<string, string> =>
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
    case "circle_event":
      return {
        title: circleName,
        body: p ? `${senderName} planned "${p}"` : `${senderName} planned something in ${circleName}`,
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
    if (!senderId) {
      return json({ error: "Unauthorized" }, 401);
    }

    let payload: Partial<PushRequest> | null = null;
    try {
      payload = (await req.json()) as Partial<PushRequest>;
    } catch {
      return json({ error: "Body must be JSON" }, 400);
    }

    const recipientId = payload?.recipientId;
    if (typeof recipientId !== "string" || !USER_ID_RE.test(recipientId)) {
      return json({ error: "Missing or malformed recipientId" }, 400);
    }
    // Default-deny: a kind this function does not know has no rule to be
    // checked against, so it is refused rather than waved through.
    const type = payload?.type;
    if (!isPushType(type)) {
      return json({ error: "Unknown push type" }, 400);
    }
    // Ids that are not ids are dropped here, so everything below can treat
    // a present value as a well-formed one.
    const rawCircleId = payload?.circleId;
    const circleId = typeof rawCircleId === "string" && UUID_RE.test(rawCircleId) ? rawCircleId : undefined;
    const rawMessageId = payload?.messageId;
    const messageId = typeof rawMessageId === "string" && UUID_RE.test(rawMessageId) ? rawMessageId : undefined;

    // A user never needs to notify themselves.
    if (recipientId === senderId) {
      return json({ ok: true, sent: 0, skipped: "self" });
    }

    // Rate limits, before any other work: per sender across everyone, and
    // per sender→recipient so one person cannot be singled out. Metered
    // the same way the AI functions are — a rolling hour and a rolling
    // day, fail-open if the ledger itself is unavailable.
    const [senderQuota, pairQuota] = await Promise.all([
      consumeQuota(senderId, "send-push", SENDER_LIMITS),
      consumeQuota(senderId, `send-push:to:${recipientId}`, PAIR_LIMITS),
    ]);
    if (!senderQuota.allowed) return quotaResponse(senderQuota, corsHeaders);
    if (!pairQuota.allowed) return quotaResponse(pairQuota, corsHeaders);

    const admin = createAdminClient();

    // This function is now the busiest writer to the quota ledger, and
    // nothing schedules its cleanup. Sweep it once in a few hundred calls
    // so the table stays the size of its widest window.
    if (Math.random() < 0.005) {
      const { error: pruneError } = await admin.rpc("prune_ai_usage");
      if (pruneError) console.error("[send-push] ledger prune failed:", pruneError.message);
    }

    // The relationship this kind implies. Refused loudly: a legitimate
    // client never gets here without one, so a 403 in the app's console
    // means a call site and its rule have drifted apart.
    const grant = await authorize(admin, type, senderId, recipientId, circleId, messageId);
    if (!grant.allowed) {
      console.warn(`[send-push] refused ${type}: sender has no qualifying relationship with the recipient`);
      return json({ error: "Not allowed to notify this person" }, 403);
    }

    // The recipient's side, checked together:
    //
    //  - blocks, in either direction — never notify someone who blocked
    //    the sender, or whom the sender blocked;
    //  - a mute, one direction only. Unlike a block, a mute is the
    //    recipient's private preference about the sender — the sender is
    //    never told, and muting someone does not stop THEM hearing from
    //    you;
    //  - the per-kind preferences. Stored as the DISABLED set, so no row
    //    means everything is on and a newly added kind is on for existing
    //    accounts without a backfill.
    //
    // All of them answer with the same opaque skip (and so does "no
    // device registered", below). The response used to name the reason,
    // which told any curious client exactly who had muted or blocked it.
    const [blockedByRecipient, blockedBySender, muted, prefRow] = await Promise.all([
      hasRow(admin.from("blocks").select("id").eq("blocker_id", recipientId).eq("blocked_id", senderId).limit(1)),
      hasRow(admin.from("blocks").select("id").eq("blocker_id", senderId).eq("blocked_id", recipientId).limit(1)),
      hasRow(admin.from("mutes").select("muted_id").eq("muter_id", recipientId).eq("muted_id", senderId).limit(1)),
      firstRow(admin.from("notification_preferences").select("disabled_kinds").eq("user_id", recipientId).limit(1)),
    ]);
    const disabled: string[] = Array.isArray(prefRow?.disabled_kinds) ? prefRow.disabled_kinds : [];
    if (blockedByRecipient || blockedBySender || muted || disabled.includes(type)) {
      return json({ ok: true, sent: 0, skipped: "not_delivered" });
    }

    // Credentials gate — graceful no-op until the publisher adds the key.
    const keyId = Deno.env.get("APNS_KEY_ID");
    const teamId = Deno.env.get("APNS_TEAM_ID");
    const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
    if (!keyId || !teamId || !privateKey) {
      warnApnsNotConfigured(keyId, teamId, privateKey);
      return json({ ok: true, sent: 0, skipped: "apns_not_configured" });
    }

    // Recipient's devices (admin read — RLS would hide another user's
    // rows). Newest first and capped: a real person has a phone and maybe
    // a tablet, so anything past that is rows nobody is holding.
    const { data: tokenRows, error: tokenError } = await admin
      .from("device_tokens")
      .select("token")
      .eq("user_id", recipientId)
      .order("updated_at", { ascending: false })
      .limit(MAX_DEVICES);
    if (tokenError) throw new Error(`device token lookup failed: ${tokenError.message}`);
    const tokens = (tokenRows ?? []).map((r: { token: string }) => r.token);
    if (tokens.length === 0) {
      return json({ ok: true, sent: 0, skipped: "not_delivered" });
    }

    // Resolve display context for the copy. Both names are written by
    // people and land on someone else's lock screen, so both go through
    // the same sanitising as a preview. No fallback to the sender's email:
    // it is not a field other accounts can read, and a notification is not
    // the place to start handing it out.
    const { data: senderProfile } = await admin
      .from("profiles")
      .select("name, username")
      .eq("id", senderId)
      .maybeSingle();
    const senderUsername = clean(senderProfile?.username, 30);
    const senderName =
      clean(senderProfile?.name, 40) ||
      (senderUsername ? `@${senderUsername}` : "") ||
      "Someone";

    let circleName = "your circle";
    if (circleId) {
      const { data: circle } = await admin
        .from("circles")
        .select("name")
        .eq("id", circleId)
        .maybeSingle();
      circleName = clean(circle?.name, 40) || circleName;
    }

    // Text the server read for itself wins; otherwise whatever this kind
    // is allowed to carry from the client, sanitised.
    const preview = grant.text !== undefined ? grant.text : allowedPreview(type, payload?.preview);

    const copy = buildCopy(type, senderName, circleName, preview, senderId, circleId, messageId);

    // Truthful badge: the real number of things waiting for the recipient
    // (unread direct messages + pending friend requests), never a
    // hardcoded constant. Counted with head-only queries so no rows move.
    const badge = await countBadge(admin, recipientId);

    const apsPayload = {
      aps: {
        // One last cap on the assembled lines, whatever went into them.
        alert: { title: clean(copy.title, 80), body: clean(copy.body, 200) },
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
      // Scoped to the recipient: a token re-bound to another account
      // between the read above and this delete is no longer ours to drop.
      await admin.from("device_tokens").delete().eq("user_id", recipientId).in("token", staleTokens);
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

// ---------------------------------------------------------------------------
// APNs configuration warning

// Module scope, so it is said once per function instance rather than once
// per push.
let warnedApnsNotConfigured = false;

/** Say — once, and by name — which Apple push secrets are missing. */
function warnApnsNotConfigured(
  keyId: string | undefined,
  teamId: string | undefined,
  privateKey: string | undefined,
): void {
  if (warnedApnsNotConfigured) return;
  warnedApnsNotConfigured = true;
  const missing = [
    keyId ? "" : "APNS_KEY_ID",
    teamId ? "" : "APNS_TEAM_ID",
    privateKey ? "" : "APNS_PRIVATE_KEY",
  ].filter((name) => name.length > 0);
  console.error(
    `[send-push] APNs IS NOT CONFIGURED — NO PUSH NOTIFICATIONS ARE BEING DELIVERED. ` +
      `Missing Supabase secret(s): ${missing.join(", ")}. ` +
      `Every request answers 200 with skipped "apns_not_configured" until they are set ` +
      `(supabase secrets set APNS_KEY_ID=… APNS_TEAM_ID=… APNS_PRIVATE_KEY=…). ` +
      `This is logged once per function instance.`,
  );
}

// ---------------------------------------------------------------------------
// Relationship rules

// The service-role client. Untyped here, as in `countBadge` below: the
// project's generated types are not wired into the functions.
// deno-lint-ignore no-explicit-any
type Admin = any;

interface Grant {
  allowed: boolean;
  /** Text read from the row the push is about (a message body, a cheer,
   *  a reaction). When present it replaces anything the client sent. */
  text?: string;
}

const DENIED: Grant = { allowed: false };
const ALLOWED: Grant = { allowed: true };

function grantIf(condition: boolean): Grant {
  return condition ? ALLOWED : DENIED;
}

/** The first row a query returns, or null.
 *
 *  A query that ERRORS throws rather than reading as "no row". Every
 *  caller is a permission or a privacy check, and neither may quietly
 *  pass because a lookup broke: a failed block lookup must not deliver,
 *  and a failed relationship lookup must not look like a stranger. The
 *  request ends as a 500, which the app logs and otherwise ignores. */
// deno-lint-ignore no-explicit-any
async function firstRow(query: any): Promise<any | null> {
  const { data, error } = await query;
  if (error) {
    throw new Error(`lookup failed: ${error.message ?? String(error)}`);
  }
  return Array.isArray(data) && data.length > 0 ? data[0] : null;
}

// deno-lint-ignore no-explicit-any
async function hasRow(query: any): Promise<boolean> {
  return (await firstRow(query)) !== null;
}

/** A friendship row exists for the pair. `friendships` stores each pair
 *  once with user_a < user_b; asking for both columns to be one of the two
 *  ids finds it without having to reproduce the database's ordering. */
function areFriends(admin: Admin, a: string, b: string): Promise<boolean> {
  return hasRow(
    admin.from("friendships").select("id").in("user_a", [a, b]).in("user_b", [a, b]).limit(1),
  );
}

/** Both people are members of at least one circle in common. */
async function shareCircle(admin: Admin, a: string, b: string): Promise<boolean> {
  const { data, error } = await admin
    .from("circle_members")
    .select("circle_id")
    .eq("user_id", a)
    .order("joined_at", { ascending: false })
    .limit(100);
  if (error) throw new Error(`lookup failed: ${error.message}`);
  const circleIds = (data ?? []).map((r: { circle_id: string }) => r.circle_id);
  if (circleIds.length === 0) return false;
  return await hasRow(
    admin.from("circle_members").select("id").eq("user_id", b).in("circle_id", circleIds).limit(1),
  );
}

/** Friends, or in a circle together — the two ways people in this app can
 *  already see each other's stories and names. */
async function areConnected(admin: Admin, a: string, b: string): Promise<boolean> {
  if (await areFriends(admin, a, b)) return true;
  return await shareCircle(admin, a, b);
}

/** Has a membership row in the circle. */
function isCircleMember(admin: Admin, circleId: string, userId: string): Promise<boolean> {
  return hasRow(
    admin.from("circle_members").select("id").eq("circle_id", circleId).eq("user_id", userId).limit(1),
  );
}

/** Is a member of the circle, or owns it. The owner clause matters for a
 *  circle created a moment ago: the app writes the `circles` row first and
 *  the membership rows after, and may notify in between. */
async function belongsToCircle(admin: Admin, circleId: string, userId: string): Promise<boolean> {
  const [member, owner] = await Promise.all([
    isCircleMember(admin, circleId, userId),
    hasRow(admin.from("circles").select("id").eq("id", circleId).eq("owner_id", userId).limit(1)),
  ]);
  return member || owner;
}

/** The recipient is a participant in a focus block the sender hosts or is
 *  also taking part in. Looks at the recipient's most recent blocks only —
 *  an invitation is always to a block that was just touched. */
async function shareFocusBlock(admin: Admin, senderId: string, recipientId: string): Promise<boolean> {
  const { data, error } = await admin
    .from("focus_participants")
    .select("block_id")
    .eq("user_id", recipientId)
    .order("updated_at", { ascending: false })
    .limit(25);
  if (error) throw new Error(`lookup failed: ${error.message}`);
  const blockIds = (data ?? []).map((r: { block_id: string }) => r.block_id);
  if (blockIds.length === 0) return false;
  const [hosted, joined] = await Promise.all([
    hasRow(admin.from("focus_blocks").select("id").in("id", blockIds).eq("host_id", senderId).limit(1)),
    hasRow(
      admin.from("focus_participants").select("id").in("block_id", blockIds).eq("user_id", senderId).limit(1),
    ),
  ]);
  return hosted || joined;
}

/** Decide whether `senderId` may send a push of this kind to `recipientId`.
 *
 *  Each rule is the relationship the kind is ABOUT, checked against the
 *  rows the app wrote (under row-level security) just before it called:
 *
 *    proof, note        a direct_messages row with this id, of this kind,
 *                       from the sender to the recipient
 *    friend_request     a pending friend_requests row sender → recipient
 *    friend_accept      the two are friends, or the recipient's request
 *                       to the sender is marked accepted
 *    circle_invite      the sender belongs to the circle (member or
 *                       owner) AND the recipient has a pending invitation
 *                       to it, is already a member of it, or is otherwise
 *                       connected to the sender (friend / shared circle)
 *    circle_task, circle_progress, circle_mode, circle_event, golden_post
 *                       the sender belongs to the circle and the
 *                       recipient is a member of it
 *    cheer              a cheers row sender → recipient
 *    cheer_reaction     a cheers row recipient → sender that carries a
 *                       reaction
 *    story_like, story_comment
 *                       the two are connected (friend / shared circle) —
 *                       the audiences a story is visible to
 *    pact_invite        a pacts row proposed by the sender to the
 *                       recipient
 *    pact_accept        a pacts row between the two, either way round
 *    focus_invite       the two are connected, or the recipient is a
 *                       participant in a focus block the sender hosts or
 *                       has joined
 *
 *  Two of these carry a "connected" fallback (circle_invite,
 *  focus_invite) because their call sites fire the push BEFORE the row
 *  that names the recipient is written; the people involved are always
 *  picked from the sender's own friends and circles.
 *
 *  No `default`: the switch is exhaustive over PushType, so adding a kind
 *  without a rule is a type error rather than an open door. */
async function authorize(
  admin: Admin,
  type: PushType,
  senderId: string,
  recipientId: string,
  circleId: string | undefined,
  messageId: string | undefined,
): Promise<Grant> {
  switch (type) {
    case "proof":
    case "note": {
      if (!messageId) return DENIED;
      const message = await firstRow(
        admin
          .from("direct_messages")
          .select("body")
          .eq("id", messageId)
          .eq("sender_id", senderId)
          .eq("recipient_id", recipientId)
          .eq("kind", type)
          .limit(1),
      );
      // The body as stored — a note's text, a proof's caption (or none).
      return message ? { allowed: true, text: clean(message.body, 120) } : DENIED;
    }

    case "friend_request":
      return grantIf(
        await hasRow(
          admin
            .from("friend_requests")
            .select("id")
            .eq("requester_id", senderId)
            .eq("addressee_id", recipientId)
            .eq("status", "pending")
            .limit(1),
        ),
      );

    case "friend_accept": {
      if (await areFriends(admin, senderId, recipientId)) return ALLOWED;
      return grantIf(
        await hasRow(
          admin
            .from("friend_requests")
            .select("id")
            .eq("requester_id", recipientId)
            .eq("addressee_id", senderId)
            .eq("status", "accepted")
            .limit(1),
        ),
      );
    }

    case "circle_invite": {
      if (!circleId) return DENIED;
      if (!(await belongsToCircle(admin, circleId, senderId))) return DENIED;
      const invited = await hasRow(
        admin
          .from("circle_invitations")
          .select("id")
          .eq("circle_id", circleId)
          .eq("invitee_id", recipientId)
          .eq("status", "pending")
          .limit(1),
      );
      if (invited) return ALLOWED;
      if (await isCircleMember(admin, circleId, recipientId)) return ALLOWED;
      return grantIf(await areConnected(admin, senderId, recipientId));
    }

    case "circle_task":
    case "circle_progress":
    case "circle_mode":
    case "circle_event":
    case "golden_post": {
      if (!circleId) return DENIED;
      const [senderIn, recipientIn] = await Promise.all([
        belongsToCircle(admin, circleId, senderId),
        isCircleMember(admin, circleId, recipientId),
      ]);
      return grantIf(senderIn && recipientIn);
    }

    case "cheer": {
      const cheer = await firstRow(
        admin
          .from("cheers")
          .select("message")
          .eq("sender_id", senderId)
          .eq("recipient_id", recipientId)
          .order("created_at", { ascending: false })
          .limit(1),
      );
      return cheer ? { allowed: true, text: clean(cheer.message, 120) } : DENIED;
    }

    case "cheer_reaction": {
      const cheer = await firstRow(
        admin
          .from("cheers")
          .select("reaction")
          .eq("sender_id", recipientId)
          .eq("recipient_id", senderId)
          .not("reaction", "is", null)
          .order("reaction_at", { ascending: false, nullsFirst: false })
          .limit(1),
      );
      // A single emoji; the cap leaves room for a joined sequence.
      return cheer ? { allowed: true, text: clean(cheer.reaction, 16) } : DENIED;
    }

    case "story_like":
    case "story_comment":
      return grantIf(await areConnected(admin, senderId, recipientId));

    case "pact_invite":
      return grantIf(
        await hasRow(
          admin.from("pacts").select("id").eq("proposer_id", senderId).eq("partner_id", recipientId).limit(1),
        ),
      );

    case "pact_accept": {
      const [proposedByMe, proposedToMe] = await Promise.all([
        hasRow(
          admin.from("pacts").select("id").eq("proposer_id", senderId).eq("partner_id", recipientId).limit(1),
        ),
        hasRow(
          admin.from("pacts").select("id").eq("proposer_id", recipientId).eq("partner_id", senderId).limit(1),
        ),
      ]);
      return grantIf(proposedByMe || proposedToMe);
    }

    case "focus_invite": {
      if (await areConnected(admin, senderId, recipientId)) return ALLOWED;
      return grantIf(await shareFocusBlock(admin, senderId, recipientId));
    }
  }
}

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
