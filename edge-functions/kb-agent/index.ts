// ============================================================
// kb-agent — answers from the knowledge base, and writes from it
//
// Deploy: Supabase → Edge Functions → Deploy a new function → Via Editor,
//         name it exactly  kb-agent  and paste this file.
//         Leave "Verify JWT with legacy secret" ON — we need to know who is
//         asking, both to log it and because answers draw on paid material.
//
// Secrets (Edge Functions → Secrets):
//   GROQ_API_KEY     from console.groq.com — the free tier is enough
//   GROQ_MODEL       optional; defaults to llama-3.3-70b-versatile
//   EMBED_PROVIDER   jina | gemini | hf          (default jina)
//   EMBED_API_KEY    the key for whichever that is
//   EMBED_MODEL      optional; a sane default per provider
//
// Three modes:
//   ask       a student's question -> a grounded answer with citations
//   summary   a module -> a polished summary of what it covers
//   interview a module -> interview questions with model answers
//   probe     no model call: reports what is configured, for diagnosis
//
// ---------- what this file is careful about ----------
//
// Groq sits behind Cloudflare, and Cloudflare rejects clients with no
// User-Agent using *its own* error — "error code: 1010" carried on HTTP 403.
// That cost a whole debugging session in August because the code collapsed
// 401 and 403 into "the provider rejected the key" and threw the body away.
// The key was fine. So: every provider call sends a real User-Agent, and no
// error path ever discards the provider's own words.
// (claude/qt-groq-403-diagnosis.md)
//
// A model name typed into Render's environment field appends rather than
// replaces, which produced `llama-3.3-70b-versllama-3.1-8b-instantatile`. The
// probe below flags a model name that contains a known model but is longer
// than it, because that shape is almost always this mistake.
//
// And the thing that matters most: this refuses to answer when the corpus
// cannot support an answer. A help desk that confidently invents an answer
// about a paid course is worse than one that says it does not know.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const env = (k: string, d = "") => Deno.env.get(k) ?? d;

const GROQ_KEY = env("GROQ_API_KEY");
const GROQ_MODEL = env("GROQ_MODEL", "llama-3.3-70b-versatile");
const EMBED_PROVIDER = env("EMBED_PROVIDER", "jina").toLowerCase();
const EMBED_KEY = env("EMBED_API_KEY");

const KNOWN_GROQ_MODELS = [
  "llama-3.3-70b-versatile", "llama-3.1-8b-instant",
  "llama3-70b-8192", "mixtral-8x7b-32768", "gemma2-9b-it",
];

// Cloudflare only blocks clients that look like scripts. This is not a
// disguise — it names us honestly — it is simply a User-Agent, which the
// default urllib/fetch client does not always send.
const UA = "GenAITesting-kb-agent/1.0 (+https://genaitesting.online)";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), {
    status, headers: { ...CORS, "Content-Type": "application/json" },
  });

/* ---------- provider errors, reported rather than guessed at ---------- */
function explainProviderError(name: string, status: number, body: string) {
  const lower = (body || "").toLowerCase();

  // Cloudflare's own refusal, not the provider's.
  if (lower.includes("error code: 1010") || lower.includes("cloudflare")) {
    return `${name} never saw this request — Cloudflare blocked it before it arrived ` +
      `(the response is a Cloudflare error page, not ${name}'s). This is a client ` +
      `fingerprint problem, not a key problem. Verbatim: ${body.slice(0, 200)}`;
  }
  if (status === 401) {
    return `${name} rejected the key (401). Its own words: ${body.slice(0, 300)}`;
  }
  if (status === 403) {
    return `${name} refused this request (403) — note that is refusing the *request*, ` +
      `which is not the same as rejecting the key. Its own words: ${body.slice(0, 300)}`;
  }
  if (status === 404 && lower.includes("model")) {
    return `${name} has no such model for this key. Its own words: ${body.slice(0, 300)}`;
  }
  if (status === 429) {
    return `${name} rate-limited us (429) — on a free tier this is normal under load, ` +
      `not a broken product. Try again shortly. Its own words: ${body.slice(0, 200)}`;
  }
  return `${name} returned ${status}: ${body.slice(0, 300)}`;
}

/* ---------- embeddings ---------- */
async function embed(text: string): Promise<{ vector: number[] | null; note: string | null }> {
  if (!EMBED_KEY) {
    return { vector: null, note: "No EMBED_API_KEY is set, so this answer used word matching only." };
  }
  try {
    let url: string, body: unknown, headers: Record<string, string>;

    if (EMBED_PROVIDER === "gemini") {
      const model = env("EMBED_MODEL", "text-embedding-004");
      url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:embedContent?key=${EMBED_KEY}`;
      headers = { "Content-Type": "application/json", "User-Agent": UA };
      body = { content: { parts: [{ text }] }, outputDimensionality: 768 };
    } else if (EMBED_PROVIDER === "hf") {
      const model = env("EMBED_MODEL", "sentence-transformers/all-mpnet-base-v2");
      url = `https://api-inference.huggingface.co/pipeline/feature-extraction/${model}`;
      headers = { Authorization: `Bearer ${EMBED_KEY}`, "Content-Type": "application/json", "User-Agent": UA };
      body = { inputs: text, options: { wait_for_model: true } };
    } else {
      const model = env("EMBED_MODEL", "jina-embeddings-v3");
      url = "https://api.jina.ai/v1/embeddings";
      headers = { Authorization: `Bearer ${EMBED_KEY}`, "Content-Type": "application/json", "User-Agent": UA };
      // Matryoshka truncation to 768 so one vector column serves every provider.
      body = { model, task: "retrieval.query", dimensions: 768, input: [text] };
    }

    const res = await fetch(url, { method: "POST", headers, body: JSON.stringify(body) });
    const raw = await res.text();
    if (!res.ok) {
      return { vector: null, note: explainProviderError(`The embedding provider (${EMBED_PROVIDER})`, res.status, raw) };
    }

    const j = JSON.parse(raw);
    let v: number[] | null = null;
    if (EMBED_PROVIDER === "gemini") v = j?.embedding?.values ?? null;
    else if (EMBED_PROVIDER === "hf") v = Array.isArray(j?.[0]) ? j[0] : (Array.isArray(j) ? j : null);
    else v = j?.data?.[0]?.embedding ?? null;

    if (!Array.isArray(v)) {
      return { vector: null, note: `The embedding provider answered 200 but with no vector in it: ${raw.slice(0, 160)}` };
    }
    if (v.length !== 768) {
      // Mixing dimensions is caught by the database too, but saying it here
      // names the cause instead of surfacing a Postgres type error.
      return { vector: null, note:
        `The embedding provider returned ${v.length} dimensions; this index is built for 768. ` +
        `Either set EMBED_MODEL to a 768-dimension model or re-embed the whole corpus.` };
    }
    return { vector: v, note: null };
  } catch (e) {
    return { vector: null, note: `Could not reach the embedding provider: ${String(e).slice(0, 200)}` };
  }
}

/* ---------- generation ---------- */
async function groqChat(messages: unknown[], model: string, maxTokens = 1200) {
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${GROQ_KEY}`,
      "Content-Type": "application/json",
      Accept: "application/json",
      "User-Agent": UA,
    },
    body: JSON.stringify({ model, messages, temperature: 0.2, max_tokens: maxTokens }),
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(explainProviderError("Groq", res.status, raw));
  const j = JSON.parse(raw);
  const text = j?.choices?.[0]?.message?.content;
  if (!text) throw new Error(`Groq answered 200 but with no content: ${raw.slice(0, 200)}`);
  return text as string;
}

/* ---------- prompts ---------- */
const GROUNDING =
  "You answer only from the numbered sources given to you. " +
  "Cite the sources you used inline as [1], [2] and so on, matching the numbers given. " +
  "If the sources do not contain enough to answer, say exactly what is missing rather " +
  "than filling the gap from general knowledge — the reader is paying for this course " +
  "and a confident wrong answer costs them more than an honest gap. " +
  "Never cite a number you were not given. Write in plain English, in prose.";

function buildSources(rows: any[]) {
  return rows.map((r, i) =>
    `[${i + 1}] ${r.title}${r.heading ? " — " + r.heading : ""}` +
    `${r.module ? ` (${r.module})` : ""}\n${r.content}`).join("\n\n");
}

function instructionFor(mode: string, question: string, count: number) {
  if (mode === "interview") {
    return `Write ${count} interview questions with model answers, drawn from the sources.\n\n` +
      `Each question must be one a real interviewer would ask about this topic, and each answer ` +
      `must be answerable from the sources — do not invent questions the material cannot support. ` +
      `Give each as:\n\n**Q: <question>**\nA: <answer, two to five sentences, with citations>\n\n` +
      `Range from straightforward to searching, and put the searching ones last.` +
      (question ? `\n\nFocus on: ${question}` : "");
  }
  if (mode === "summary") {
    return `Write a polished summary of what these sources cover.\n\n` +
      `Open with one sentence saying what the material is about. Then explain the substance in ` +
      `prose — what it teaches, what it expects the reader to do, and anything it is explicit ` +
      `about getting wrong. Cite as you go. Do not pad it to a length; stop when it is said.` +
      (question ? `\n\nAngle it towards: ${question}` : "");
  }
  return question;
}

/* ---------- the function ---------- */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "not signed in" }, 401);

  const sb = createClient(
    env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"),
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } },
  );

  let body: any = {};
  try { body = await req.json(); } catch { /* an empty body is a probe */ }

  const mode: string = body.mode ?? "ask";
  const question: string = (body.question ?? "").toString().slice(0, 2000).trim();
  const module: string | null = body.module || null;
  const count = Math.min(Math.max(parseInt(body.count ?? "8", 10) || 8, 1), 15);

  /* ---------- probe: what is configured, without revealing anything ---------- */
  if (mode === "probe") {
    const shape = (k: string, v: string, expect: string) => ({
      name: k, set: !!v, length: v.length,
      starts: v ? v.slice(0, 4) : null,
      prefix_looks_right: v ? v.startsWith(expect) : null,
      has_stray_whitespace: v !== v.trim(),
    });
    // A model name that contains a known model but is longer than it is almost
    // always a value typed into a field that appends instead of replacing.
    const spliced = KNOWN_GROQ_MODELS.find(
      (m) => GROQ_MODEL.includes(m) && GROQ_MODEL.length > m.length);
    return json({
      ok: true,
      groq: shape("GROQ_API_KEY", GROQ_KEY, "gsk_"),
      embed: { provider: EMBED_PROVIDER, ...shape("EMBED_API_KEY", EMBED_KEY, "") },
      chat_model: GROQ_MODEL,
      chat_model_warning: spliced
        ? `"${GROQ_MODEL}" contains "${spliced}" but is longer — this is the shape produced by ` +
          `typing over a field that appends rather than replaces. Clear it and retype one name.`
        : null,
    });
  }

  if (!GROQ_KEY) {
    return json({
      error: "No GROQ_API_KEY is configured, so no answer can be written.",
      hint: "Supabase → Edge Functions → Secrets. A Groq key starts gsk_ and the free tier is enough.",
    }, 503);
  }
  if (mode === "ask" && !question) return json({ error: "Ask a question." }, 400);
  if (!["ask", "summary", "interview"].includes(mode)) {
    return json({ error: `Unknown mode "${mode}".` }, 400);
  }

  const started = Date.now();
  const retrievalQuery = question || module || "overview";

  /* ---------- retrieve ---------- */
  const { vector, note: embedNote } = await embed(retrievalQuery);

  const { data: rows, error: sErr } = vector
    ? await sb.rpc("kb_search", {
        p_embedding: JSON.stringify(vector), p_query: retrievalQuery,
        p_module: module, p_limit: mode === "ask" ? 8 : 14 })
    : await sb.rpc("kb_lexical_search", {
        p_query: retrievalQuery, p_module: module,
        p_limit: mode === "ask" ? 8 : 14 });

  if (sErr) return json({ error: `Could not search the knowledge base: ${sErr.message}` }, 500);

  const { data: cfg } = await sb.from("kb_config")
    .select("min_similarity, chat_model").eq("id", 1).maybeSingle();
  const floor = cfg?.min_similarity ?? 0.3;
  /* The model comes from kb_config so an admin can change it from the settings
     page without a redeploy. GROQ_MODEL stays as the fallback for a project
     that has not run schema-12 yet — but when both exist the database wins,
     because two sources of truth for a model name is how you end up debugging
     a 404 against the value you are not looking at. */
  const model = cfg?.chat_model || GROQ_MODEL;

  // A chunk earns its place either by being semantically close or by actually
  // containing the words asked about. Requiring both would lose the loosely
  // worded question; requiring neither is how a corpus answers everything.
  const kept = (rows ?? []).filter((r: any) =>
    (r.similarity !== null && r.similarity >= floor) || r.lex_hit === true);

  if (!kept.length) {
    const { data: cov } = await sb.rpc("kb_coverage");
    const answer =
      "I could not find anything in the course material that answers this. " +
      (cov?.length
        ? "What I do hold is: " + cov.map((c: any) => `${c.module} (${c.documents} documents)`).join(", ") + "."
        : "The knowledge base is empty — nothing has been ingested yet.");
    await sb.rpc("kb_log_answer", {
      p_mode: mode, p_question: question || `(${mode}: ${module ?? "all"})`, p_module: module,
      p_answer: answer, p_cited: [], p_grounded: false, p_model: model,
      p_ms: Date.now() - started, p_error: null,
    });
    return json({
      grounded: false, answer, citations: [], coverage: cov ?? [],
      note: embedNote, retrieval: vector ? "hybrid" : "lexical only",
    });
  }

  /* ---------- generate ---------- */
  try {
    const text = await groqChat([
      { role: "system", content: GROUNDING },
      { role: "user", content:
        `Sources:\n\n${buildSources(kept)}\n\n---\n\n${instructionFor(mode, question, count)}` },
    ], model, mode === "ask" ? 900 : 1800);

    // Only report citations the model actually used. Listing all eight sources
    // under an answer that leant on two is a quiet form of overclaiming.
    const used = new Set<number>();
    for (const m of text.matchAll(/\[(\d{1,2})\]/g)) {
      const n = parseInt(m[1], 10);
      if (n >= 1 && n <= kept.length) used.add(n);
    }
    const citations = [...used].sort((a, b) => a - b).map((n) => {
      const r = kept[n - 1];
      return { n, chunk_id: r.chunk_id, title: r.title, heading: r.heading,
               module: r.module, kind: r.kind, uri: r.uri, start_sec: r.start_sec };
    });

    await sb.rpc("kb_log_answer", {
      p_mode: mode, p_question: question || `(${mode}: ${module ?? "all"})`, p_module: module,
      p_answer: text, p_cited: citations.map((c) => c.chunk_id),
      p_grounded: citations.length > 0, p_model: model,
      p_ms: Date.now() - started, p_error: null,
    });

    return json({
      grounded: citations.length > 0,
      answer: text, citations,
      considered: kept.length,
      retrieval: vector ? "hybrid" : "lexical only",
      note: embedNote,
      ms: Date.now() - started,
    });
  } catch (e) {
    const msg = String(e instanceof Error ? e.message : e);
    await sb.rpc("kb_log_answer", {
      p_mode: mode, p_question: question || `(${mode}: ${module ?? "all"})`, p_module: module,
      p_answer: null, p_cited: [], p_grounded: false, p_model: model,
      p_ms: Date.now() - started, p_error: msg.slice(0, 500),
    });
    // 502, not 500: the failure is upstream, and the message is the provider's
    // own rather than our guess at what it meant.
    return json({ error: msg }, 502);
  }
});
