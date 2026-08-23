// Public invite landing page.
//
// Invite links used to be a bare custom scheme (frisfocus://add-friend?u=<id>),
// which dies anywhere outside the app — Messages previews, browsers, or on a
// phone without FrisFocus installed. Shares now point at this HTTPS page
// instead. It renders a small branded page with an "Open FrisFocus" button
// that hops into the app via the custom scheme (landing on the inviter's
// Add-friend screen), plus install guidance when the app isn't there yet.
//
// GET /functions/v1/invite?u=<accountId>
// Deployed public (no JWT) — it serves plain HTML to logged-out browsers.

const SCHEME = "frisfocus";
const HOST = "add-friend";

/** Account ids come from Rork Auth — constrain hard before embedding. */
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

function page(userId: string | null): string {
  const valid = userId !== null && ID_PATTERN.test(userId);
  const appLink = valid ? `${SCHEME}://${HOST}?u=${userId}` : `${SCHEME}://`;
  const title = "Add me on FrisFocus";
  const description = valid
    ? "Tap to open FrisFocus and add your friend — keep each other going."
    : "FrisFocus — an honest record of your days.";

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>${title}</title>
<meta property="og:title" content="${title}" />
<meta property="og:description" content="${description}" />
<meta property="og:type" content="website" />
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
  p.note {
    margin-top: 18px; font-size: 12.5px; line-height: 1.55;
    color: rgba(44, 44, 42, 0.5);
  }
</style>
</head>
<body>
  <main class="card">
    <div class="sun" aria-hidden="true"></div>
    <div class="eyebrow">FrisFocus invite</div>
    <h1>${valid ? "A friend wants you in their corner" : "FrisFocus"}</h1>
    <p class="sub">${
      valid
        ? "Open FrisFocus to land on their profile with an Add control — and keep each other going, day by day."
        : "This invite link is missing its code. Ask your friend to share it again from inside FrisFocus."
    }</p>
    ${valid ? `<a class="open" href="${appLink}">Open FrisFocus</a>` : ""}
    <p class="note">${
      valid
        ? "Nothing happened? FrisFocus isn't installed on this phone yet — install it first, then tap this link again."
        : ""
    }</p>
  </main>
</body>
</html>`;
}

Deno.serve((req) => {
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

  return new Response(page(userId), {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300",
    },
  });
});
