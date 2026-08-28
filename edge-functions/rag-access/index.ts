// ============================================================
// rag-access — mints a short-lived token for the TripSage RAG console
//
// The console runs on Render, a completely separate origin with no access to
// your Supabase session. Linking students straight to its URL would mean the
// paywall is decorative: anyone who saw the link could use it forever.
//
// So: the browser calls this function WITH the student's session. We check they
// actually have paid access, then hand back a token signed with a secret shared
// only between this function and the Render service. The console verifies the
// signature and the expiry and never needs a database of its own.
//
// Deploy: Supabase → Edge Functions → Deploy a new function → Via Editor,
//         name it exactly  rag-access  and paste this file.
//         Leave "Verify JWT with legacy secret" ON — we need to know who is asking.
//
// Secrets required (Edge Functions → Secrets):
//   RAG_GATE_SECRET          the same long random string you set on Render
//   RAG_GATE_WINDOW_SECONDS  optional, defaults to 43200 (12 hours)
//
// The token now carries *scope*: which projects this student may open, signed
// alongside the expiry. Requires schema-08-projects.sql (my_projects()).
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SECRET = Deno.env.get("RAG_GATE_SECRET") ?? "";
const WINDOW = parseInt(Deno.env.get("RAG_GATE_WINDOW_SECONDS") ?? "43200", 10);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

async function sign(message: string) {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(SECRET),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!SECRET) return json({ error: "RAG_GATE_SECRET is not configured" }, 500);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "not signed in" }, 401);

  // Act as the caller, so RLS and my_access() see their identity, not ours.
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } },
  );

  const { data: user, error: uErr } = await sb.auth.getUser();
  if (uErr || !user?.user) return json({ error: "not signed in" }, 401);

  const { data, error } = await sb.rpc("my_access");
  if (error) return json({ error: "could not check access: " + error.message }, 500);
  const access = Array.isArray(data) ? data[0] : data;

  // Which projects this student holds. Admins get everything, because
  // my_projects() says so — the decision stays in the database.
  //
  // If schema-08-projects.sql has not been run yet, my_projects() does not
  // exist. That is a deployment gap, not a reason to lock out a paying
  // student: we fall back to the legacy two-part token, which the console
  // honours as full access. This is what makes the deploy order irrelevant —
  // this function can ship before or after the migration, and scoping starts
  // the moment the migration lands, with no second deploy.
  const { data: projRows, error: pErr } = await sb.rpc("my_projects");
  if (pErr) {
    const missing = pErr.code === "42883" ||
      /could not find the function|does not exist|schema cache/i.test(pErr.message ?? "");
    if (!missing) return json({ error: "could not check projects: " + pErr.message }, 500);
    if (!access?.has_access) return json({ allowed: false, reason: "no active access" });
    const legacyExpiry = String(Math.floor(Date.now() / 1000) + WINDOW);
    return json({
      allowed: true,
      token: legacyExpiry + "." + await sign(legacyExpiry),
      projects: [],
      scope: "all",
      note: "project scoping is not enabled on this database yet",
      expires_at: new Date(parseInt(legacyExpiry, 10) * 1000).toISOString(),
      is_admin: !!access?.is_admin,
    });
  }
  const projects: string[] = (projRows ?? []).map((r: { project_id: string }) => r.project_id);

  if (!projects.length) {
    // A paid subscription is course access; it is not project access. Saying so
    // plainly beats handing over a token that opens nothing.
    //
    // Answered with 200, deliberately. "Has this student been given a project?"
    // is a question this function answered successfully; the answer is no. A 403
    // would say "you may not ask", which is false, and the Supabase SDK turns any
    // non-2xx into a thrown error — so a 403 here never reached the branch in
    // projects.html that explains how to get a project, and every student without
    // one was shown "Couldn't check your access just now. The server returned
    // HTTP 403" above a Try again button that could not possibly help.
    return json({
      allowed: false,
      reason: access?.has_access
        ? "your subscription is active, but no project has been assigned to your account"
        : "no active access",
      projects: [],
    });
  }

  // The scope is inside the signature, so a student cannot widen their own token
  // by editing the URL — the console recomputes the MAC over expiry + scope.
  const expiry = String(Math.floor(Date.now() / 1000) + WINDOW);
  const scope = projects.slice().sort().join(",");
  const token = expiry + "." + scope + "." + await sign(expiry + "." + scope);

  return json({
    allowed: true,
    token,
    projects,
    scope,
    expires_at: new Date(parseInt(expiry, 10) * 1000).toISOString(),
    is_admin: !!access?.is_admin,
  });
});
