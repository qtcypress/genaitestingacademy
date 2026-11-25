// ============================================================
// config-probe — tells an admin what is configured, and tests it
//
// Deploy: Supabase → Edge Functions → Deploy a new function → Via Editor,
//         name it exactly  config-probe  and paste this file.
//         Leave "Verify JWT with legacy secret" ON — this is admin-only and
//         the check below needs to know who is asking.
//
// Needs no secrets of its own. It reads the same environment every other
// function reads, because Supabase Edge Function secrets are project-wide:
// one function can therefore report on all of them.
//
// ---------- what this deliberately does not do ----------
//
// It never returns a secret, and there is no way to set one through it. Keys
// stay in Edge Function Secrets, where a compromised admin login cannot read
// them and a database backup cannot contain them. What it returns is the
// *shape* of each key — set or not, length, first four characters, whether the
// prefix matches what that provider issues, whether there is stray whitespace —
// which is enough to diagnose every configuration fault seen on this project so
// far without ever putting a credential on a wire to a browser.
//
// That is not a theoretical preference. In August a Groq key that was entirely
// valid was blamed for a 403 that Cloudflare had produced, and separately a Hugging
// Face token pasted into GROQ_API_KEY was invisible until something reported the
// prefix. A key's first four characters distinguish gsk_ from hf_ instantly and
// reveal nothing. (claude/qt-groq-403-diagnosis.md)
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const env = (k: string, d = "") => Deno.env.get(k) ?? d;
const UA = "GenAITesting-config-probe/1.0 (+https://genaitesting.online)";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), {
    status, headers: { ...CORS, "Content-Type": "application/json" },
  });

const KNOWN_GROQ_MODELS = [
  "llama-3.3-70b-versatile", "llama-3.1-8b-instant",
  "llama3-70b-8192", "mixtral-8x7b-32768", "gemma2-9b-it",
];

/* Every secret the application expects, what breaks without it, and what its
   value should look like. Kept here rather than in the page so there is one
   list, and the page cannot drift from what the functions actually read. */
const EXPECTED = [
  { name: "GROQ_API_KEY", prefix: "gsk_", feature: "The help agent",
    breaks: "Asking the course a question returns a configuration error.",
    where: "console.groq.com → API Keys. The free tier is enough." },
  { name: "EMBED_API_KEY", prefix: "", feature: "Semantic search",
    breaks: "Search still works on words alone, and every answer says so. Loosely-worded questions get worse.",
    where: "jina.ai → API key (free, no card), or a Gemini / Hugging Face key." },
  { name: "ZEPTOMAIL_TOKEN", prefix: "Zoho-enczapikey", feature: "All email",
    breaks: "Booking invitations and the welcome email queue in email_outbox. Nothing is lost; nothing is sent either.",
    where: "ZeptoMail → Mail Agent → Send Mail token. Keep the Zoho-enczapikey prefix." },
  { name: "BOOKING_HOOK_SECRET", prefix: "", feature: "The booking email sender",
    breaks: "send-booking-email refuses every call with 403, so the queue never drains.",
    where: "Any long random string. Paste the same one into the schedule's x-booking-secret header." },
  { name: "RAG_GATE_SECRET", prefix: "", feature: "Capstone console access",
    breaks: "Students cannot open the RAG console — the gate fails closed.",
    where: "Must be byte-identical to the value set on the Render service." },
  { name: "MAIL_FROM", prefix: "", feature: "The sender address", optional: true,
    breaks: "Defaults to no-reply@genaitesting.online, which is correct, so this is informational.",
    where: "Must be an address on a domain verified with ZeptoMail." },
  { name: "SITE_URL", prefix: "https://", feature: "Links inside emails", optional: true,
    breaks: "Defaults to https://genaitesting.online, so this is informational.",
    where: "Only set it if the site moves." },
];

function shapeOf(name: string, expectedPrefix: string) {
  const raw = Deno.env.get(name) ?? "";
  const set = raw.length > 0;
  return {
    name, set,
    length: raw.length,
    // Four characters is enough to tell gsk_ from hf_ from sk- and reveals
    // nothing that could be used.
    starts: set ? raw.slice(0, 4) : null,
    prefix_expected: expectedPrefix || null,
    prefix_looks_right: set && expectedPrefix ? raw.startsWith(expectedPrefix) : null,
    // A trailing newline from a copy-paste produces "Invalid API Key" with a
    // perfectly correct-looking prefix, and is otherwise invisible.
    has_stray_whitespace: set && raw !== raw.trim(),
  };
}

/* ---------- live tests ---------- */
async function testGroq(model: string) {
  const t = Date.now();
  if (!env("GROQ_API_KEY")) return { ok: false, detail: "GROQ_API_KEY is not set." };
  try {
    const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env("GROQ_API_KEY")}`,
        "Content-Type": "application/json", Accept: "application/json",
        // Without this Cloudflare answers 403 with its own error page and the
        // key gets the blame. This single header is the August bug.
        "User-Agent": UA,
      },
      body: JSON.stringify({
        model, max_tokens: 1,
        messages: [{ role: "user", content: "ping" }],
      }),
    });
    const raw = await res.text();
    const ms = Date.now() - t;
    if (res.ok) return { ok: true, ms, model, detail: `${res.status} in ${ms} ms` };

    const lower = raw.toLowerCase();
    let cause = `Groq returned ${res.status}.`;
    if (lower.includes("error code: 1010") || lower.includes("cloudflare")) {
      cause = "Cloudflare blocked this before Groq saw it. Not a key problem.";
    } else if (res.status === 401) {
      cause = "Groq rejected the key. If the prefix and length above look right, " +
        "the key was probably revoked or regenerated after it was set here.";
    } else if (res.status === 404) {
      cause = `Groq has no model called "${model}" for this key.`;
    } else if (res.status === 429) {
      cause = "Rate limited. Normal on a free tier under load, not a fault.";
    }
    // The body is the diagnosis. Never swallow it.
    return { ok: false, ms, status: res.status, cause, detail: raw.slice(0, 300) };
  } catch (e) {
    return { ok: false, cause: "Could not reach Groq at all.", detail: String(e).slice(0, 200) };
  }
}

async function testEmbedding() {
  const t = Date.now();
  const provider = env("EMBED_PROVIDER", "jina").toLowerCase();
  const key = env("EMBED_API_KEY");
  if (!key) {
    return { ok: false, provider,
      detail: "EMBED_API_KEY is not set — search falls back to word matching." };
  }
  try {
    let url: string, body: unknown, headers: Record<string, string>;
    if (provider === "gemini") {
      const m = env("EMBED_MODEL", "text-embedding-004");
      url = `https://generativelanguage.googleapis.com/v1beta/models/${m}:embedContent?key=${key}`;
      headers = { "Content-Type": "application/json", "User-Agent": UA };
      body = { content: { parts: [{ text: "ping" }] }, outputDimensionality: 768 };
    } else if (provider === "hf") {
      const m = env("EMBED_MODEL", "sentence-transformers/all-mpnet-base-v2");
      url = `https://api-inference.huggingface.co/pipeline/feature-extraction/${m}`;
      headers = { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "User-Agent": UA };
      body = { inputs: "ping", options: { wait_for_model: true } };
    } else {
      const m = env("EMBED_MODEL", "jina-embeddings-v3");
      url = "https://api.jina.ai/v1/embeddings";
      headers = { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "User-Agent": UA };
      body = { model: m, task: "retrieval.query", dimensions: 768, input: ["ping"] };
    }

    const res = await fetch(url, { method: "POST", headers, body: JSON.stringify(body) });
    const raw = await res.text();
    const ms = Date.now() - t;
    if (!res.ok) {
      return { ok: false, provider, ms, status: res.status, detail: raw.slice(0, 300) };
    }
    const j = JSON.parse(raw);
    const v = provider === "gemini" ? j?.embedding?.values
      : provider === "hf" ? (Array.isArray(j?.[0]) ? j[0] : j)
      : j?.data?.[0]?.embedding;
    const dims = Array.isArray(v) ? v.length : null;
    return {
      ok: dims === 768, provider, ms, dimensions: dims,
      detail: dims === 768
        ? `${res.status} in ${ms} ms, 768 dimensions`
        : `Returned ${dims} dimensions; the index is built for 768. Change EMBED_MODEL, ` +
          `or re-embed the whole corpus to the new size — the two cannot be mixed.`,
    };
  } catch (e) {
    return { ok: false, provider, detail: String(e).slice(0, 200) };
  }
}

/* ZeptoMail has no cheap no-op endpoint, and sending a test message to prove
   configuration is a real email to a real person. So this reports shape and
   whether the queue is draining, which is the question that actually matters. */
async function mailStatus(sb: any) {
  const token = env("ZEPTOMAIL_TOKEN");
  const { data, error } = await sb
    .from("email_outbox")
    .select("status")
    .limit(500);
  const counts: Record<string, number> = { queued: 0, sent: 0, failed: 0, skipped: 0 };
  for (const r of data ?? []) counts[r.status] = (counts[r.status] ?? 0) + 1;
  return {
    token_set: !!token,
    host: env("ZEPTOMAIL_HOST", "api.zeptomail.com"),
    from: env("MAIL_FROM", "no-reply@genaitesting.online"),
    outbox: error ? null : counts,
    verdict: !token
      ? "No token, so nothing sends. Invitations are accumulating in the queue and will " +
        "all go out when a token is added — none are lost."
      : counts.queued > 0 && counts.sent === 0
        ? "A token is set but nothing has sent yet. Check that send-booking-email is deployed " +
          "and that a schedule is calling it with the x-booking-secret header."
        : counts.failed > 0
          ? `${counts.failed} message(s) failed. Each row's last_error holds ZeptoMail's own reply.`
          : "Sending normally.",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "not signed in" }, 401);

  const sb = createClient(
    env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"),
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } },
  );

  // Admin only, decided by the database rather than by this function: is_admin()
  // is the same check every RLS policy uses, so there is one definition of admin.
  const { data: isAdmin, error: aErr } = await sb.rpc("is_admin");
  if (aErr) return json({ error: `Could not check your role: ${aErr.message}` }, 500);
  if (!isAdmin) return json({ error: "Admins only." }, 403);

  let body: any = {};
  try { body = await req.json(); } catch { /* no body means report only */ }

  // The model comes from the database so it can be changed without a redeploy;
  // the environment is only a fallback for a project that has not run
  // schema-12 yet.
  const { data: cfg } = await sb.from("kb_config").select("*").eq("id", 1).maybeSingle();
  const chatModel = cfg?.chat_model || env("GROQ_MODEL", "llama-3.3-70b-versatile");

  const secrets = EXPECTED.map((e) => ({
    ...shapeOf(e.name, e.prefix),
    feature: e.feature, breaks: e.breaks, where: e.where, optional: !!e.optional,
  }));

  const spliced = KNOWN_GROQ_MODELS.find(
    (m) => chatModel.includes(m) && chatModel.length > m.length);

  const report: any = {
    ok: true,
    secrets,
    models: {
      chat: chatModel,
      chat_source: cfg?.chat_model ? "kb_config (editable here)" : "environment (GROQ_MODEL)",
      chat_known: KNOWN_GROQ_MODELS.includes(chatModel),
      chat_warning: spliced
        ? `"${chatModel}" contains "${spliced}" but is longer. That is the shape produced by ` +
          `typing into a field that appends instead of replacing — clear it and retype one name.`
        : null,
      known_chat_models: KNOWN_GROQ_MODELS,
      embed_provider: env("EMBED_PROVIDER", "jina"),
      embed: cfg?.embed_model || env("EMBED_MODEL", "jina-embeddings-v3"),
      embed_dim: cfg?.embed_dim ?? 768,
      min_similarity: cfg?.min_similarity ?? null,
      schema_12_applied: !!cfg,
    },
    mail: await mailStatus(sb),
  };

  // Live tests cost a provider call each, so they are opt-in rather than part
  // of every page load.
  if (body.test) {
    report.tests = {
      groq: await testGroq(chatModel),
      embedding: await testEmbedding(),
    };
  }

  return json(report);
});
