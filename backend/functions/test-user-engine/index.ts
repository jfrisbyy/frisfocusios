// test-user-engine (retired)
//
// The simulated-friends engine has been removed for production: real
// accounts only. This tombstone keeps the endpoint alive so older app
// builds that still fire a best-effort poke receive a clean 200 —
// but no simulated activity is ever generated again.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return new Response(JSON.stringify({ ok: true, disabled: true }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
