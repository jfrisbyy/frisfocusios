// Public invite landing page.
//
// Invite links used to be a bare custom scheme (frisfocus://add-friend?u=<id>),
// which dies anywhere outside the app — Messages previews, browsers, or on a
// phone without FrisFocus installed. Shares now point at this HTTPS page
// instead. It renders a small branded page with an "Open FrisFocus" button
// that hops into the app via the custom scheme (landing on the inviter's
// Add-friend screen), plus install guidance when the app isn't there yet.
//
// The page carries real Open Graph metadata — the inviter's name and
// avatar — so an invite dropped into iMessage / WhatsApp unfurls as a
// designed card ("Jordan is walking a season — walk with them"), not a
// bare link. Profile lookup is service-role and read-only.
//
// GET /functions/v1/invite?u=<accountId>
// Deployed public (no JWT) — it serves plain HTML to logged-out browsers.

const SCHEME = "frisfocus";
const HOST = "add-friend";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/** Account ids come from Rork Auth — constrain hard before embedding. */
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/** Escape text for safe embedding in HTML/attributes. */
function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

interface Inviter {
  name: string | null;
  avatar: string | null;
  username: string | null;
}

/** Optional install link (TestFlight / App Store). While the app has no
 *  public install path, this stays unset and the page leans on the
 *  manual @username route instead — the one thing a recipient can act
 *  on TODAY. The custom-scheme button is useless on a phone without the
 *  app, which during a private beta is every recipient. */
const INSTALL_URL = Deno.env.get("INVITE_INSTALL_URL") ?? "";

/** Read the inviter's display name + avatar. Best-effort — a miss just
 *  renders the generic card. */
async function fetchInviter(userId: string): Promise<Inviter> {
  if (!SUPABASE_URL || !SERVICE_KEY) return { name: null, avatar: null, username: null };
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=name,username,avatar_url&limit=1`,
      {
        headers: {
          apikey: SERVICE_KEY,
          Authorization: `Bearer ${SERVICE_KEY}`,
        },
      },
    );
    if (!res.ok) return { name: null, avatar: null, username: null };
    const rows = (await res.json()) as Array<{
      name?: string | null;
      username?: string | null;
      avatar_url?: string | null;
    }>;
    const row = rows?.[0];
    if (!row) return { name: null, avatar: null, username: null };
    const rawName = (row.name ?? row.username ?? "").toString().trim();
    const name = rawName.length > 0 ? rawName.slice(0, 60) : null;
    const avatar =
      typeof row.avatar_url === "string" && /^https:\/\//.test(row.avatar_url)
        ? row.avatar_url
        : null;
    const rawUsername = (row.username ?? "").toString().trim().replace(/^@+/, "");
    const username = /^[A-Za-z0-9_.]{2,30}$/.test(rawUsername) ? rawUsername : null;
    return { name, avatar, username };
  } catch {
    return { name: null, avatar: null, username: null };
  }
}

function page(userId: string | null, inviter: Inviter, pageURL: string): string {
  const valid = userId !== null && ID_PATTERN.test(userId);
  const appLink = valid ? `${SCHEME}://${HOST}?u=${userId}` : `${SCHEME}://`;
  const name = valid ? inviter.name : null;
  const avatar = valid ? inviter.avatar : null;
  const username = valid ? inviter.username : null;

  const title = name
    ? `${name} is walking a season — walk with them`
    : "Add me on FrisFocus";
  const description = valid
    ? name
      ? `${name} keeps an honest record of their days on FrisFocus. Open the invite to walk alongside them.`
      : "Tap to open FrisFocus and add your friend — keep each other going."
    : "FrisFocus — an honest record of your days.";

  const ogImage = avatar
    ? `<meta property="og:image" content="${esc(avatar)}" />
<meta property="og:image:width" content="400" />
<meta property="og:image:height" content="400" />
<meta name="twitter:card" content="summary" />
<meta name="twitter:image" content="${esc(avatar)}" />`
    : `<meta name="twitter:card" content="summary" />`;

  const heroDisc = avatar
    ? `<img class="avatar" src="${esc(avatar)}" alt="" />`
    : `<div class="sun" aria-hidden="true"></div>`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>${esc(title)}</title>
<meta property="og:title" content="${esc(title)}" />
<meta property="og:description" content="${esc(description)}" />
<meta property="og:type" content="website" />
<meta property="og:site_name" content="FrisFocus" />
<meta property="og:url" content="${esc(pageURL)}" />
${ogImage}
<meta name="theme-color" content="#FAF2E0" />
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    min-height: 100dvh;
    display: flex; align-items: center; justify-content: center;
    background: linear-gradient(180deg, #FAF2E0 0%, #F3E8CC 100%);
    color: #2C2C2A;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    padding: 28px;
    text-align: center;
  }
  .card { max-width: 340px; width: 100%; }
  .sun {
    width: 72px; height: 72px; border-radius: 50%;
    margin: 0 auto 22px;
    background: radial-gradient(circle at 38% 34%, #E8B84B, #D08627);
    box-shadow: 0 0 44px rgba(224, 163, 52, 0.45);
  }
  .avatar {
    width: 76px; height: 76px; border-radius: 50%;
    margin: 0 auto 22px; display: block;
    object-fit: cover;
    border: 3px solid rgba(224, 163, 52, 0.75);
    box-shadow: 0 0 44px rgba(224, 163, 52, 0.35);
  }
  .eyebrow {
    font-size: 11px; font-weight: 600; letter-spacing: 2.4px;
    color: rgba(44, 44, 42, 0.5); text-transform: uppercase;
    margin-bottom: 10px;
  }
  h1 {
    font-family: Georgia, "Times New Roman", serif;
    font-size: 27px; font-weight: 500; line-height: 1.2;
    margin-bottom: 10px;
  }
  p.sub {
    font-size: 14px; line-height: 1.5;
    color: rgba(44, 44, 42, 0.65);
    margin-bottom: 28px;
  }
  a.open {
    display: block; width: 100%;
    padding: 16px 20px; border-radius: 15px;
    background: #2C2C2A; color: #FAF2E0;
    font-size: 16px; font-weight: 600; text-decoration: none;
    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.14);
  }
  a.open:active { transform: scale(0.98); }
  a.open.install {
    margin-top: 10px;
    background: transparent; color: #2C2C2A;
    border: 1.5px solid rgba(44, 44, 42, 0.35);
    box-shadow: none;
  }
  .manual {
    margin-top: 22px; padding: 16px 14px;
    border-radius: 15px;
    background: rgba(255, 255, 255, 0.55);
    border: 1px solid rgba(44, 44, 42, 0.10);
  }
  .manual-label {
    font-size: 11px; font-weight: 600; letter-spacing: 1.6px;
    text-transform: uppercase; color: rgba(44, 44, 42, 0.5);
    margin-bottom: 8px;
  }
  button.handle {
    font-family: inherit;
    font-size: 17px; font-weight: 650; color: #2C2C2A;
    background: none; border: none; cursor: pointer;
    padding: 4px 8px;
  }
  button.handle span {
    font-size: 12px; font-weight: 500; color: rgba(44, 44, 42, 0.45);
  }
  .manual-line {
    margin-top: 6px; font-size: 12.5px; line-height: 1.5;
    color: rgba(44, 44, 42, 0.6);
  }
  p.note {
    margin-top: 18px; font-size: 12.5px; line-height: 1.55;
    color: rgba(44, 44, 42, 0.5);
  }
</style>
</head>
<body>
  <main class="card">
    ${heroDisc}
    <div class="eyebrow">FrisFocus invite</div>
    <h1>${
      valid
        ? name
          ? `${esc(name)} wants you in their corner`
          : "A friend wants you in their corner"
        : "FrisFocus"
    }</h1>
    <p class="sub">${
      valid
        ? `Open FrisFocus to land on ${name ? esc(name) + "'s" : "their"} profile with an Add control — and keep each other going, day by day.`
        : "This invite link is missing its code. Ask your friend to share it again from inside FrisFocus."
    }</p>
    ${valid ? `<a class="open" href="${appLink}">Open FrisFocus</a>` : ""}
    ${
      valid && INSTALL_URL
        ? `<a class="open install" href="${esc(INSTALL_URL)}">Get FrisFocus</a>`
        : ""
    }
    ${
      valid && username
        ? `<div class="manual">
      <div class="manual-label">No app on this phone yet?</div>
      <button class="handle" type="button" onclick="navigator.clipboard&&navigator.clipboard.writeText('@${esc(username)}');this.querySelector('span').textContent='copied';">@${esc(username)}<span> · tap to copy</span></button>
      <div class="manual-line">Once you're in FrisFocus: Circles → Friends → search this name.</div>
    </div>`
        : ""
    }
    <p class="note">${
      valid
        ? "Already have FrisFocus? The button above lands on your friend's profile — even if you sign in later."
        : ""
    }</p>
  </main>
</body>
</html>`;
}

Deno.serve(async (req) => {
  const method = req.method.toUpperCase();
  if (method === "HEAD") {
    return new Response(null, {
      status: 200,
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  }
  if (method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }

  const url = new URL(req.url);
  const raw = url.searchParams.get("u");
  const userId = raw !== null && ID_PATTERN.test(raw) ? raw : null;
  const inviter = userId
    ? await fetchInviter(userId)
    : { name: null, avatar: null, username: null };

  return new Response(page(userId, inviter, url.toString()), {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300",
    },
  });
});
