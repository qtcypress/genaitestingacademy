// seo-draft — read a reference page, return a drafted post.
//
// Runs server-side for two reasons that both matter. The Anthropic key stays out of
// the browser, where anyone with dev tools could take it. And fetching the reference
// from here sidesteps CORS, which would block the admin page from reading almost any
// third-party article directly.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   ANTHROPIC_API_KEY   required
//   DRAFT_MODEL         optional, defaults to a current Sonnet
//
// Admin only. The check is a database round-trip rather than a claim in the JWT,
// because role in a token is whatever the token says and this endpoint spends money.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });

// A reference page can be enormous, and we only need enough to write about. Cap it
// rather than paying to send a whole documentation site to the model.
const MAX_REF_CHARS = 24_000;

function textFromHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<nav[\s\S]*?<\/nav>/gi, " ")
    .replace(/<footer[\s\S]*?<\/footer>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/\s+/g, " ")
    .trim();
}

function titleFromHtml(html: string): string {
  const m = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return m ? m[1].replace(/\s+/g, " ").trim().slice(0, 200) : "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) {
    return json({ error: "ANTHROPIC_API_KEY is not set on this function. " +
                         "Supabase → Edge Functions → Secrets." }, 500);
  }

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth) return json({ error: "not signed in" }, 401);
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const { data: who } = await sb.auth.getUser();
  if (!who?.user) return json({ error: "not signed in" }, 401);
  const { data: prof } = await sb.from("profiles").select("role").eq("id", who.user.id).single();
  if (!prof || prof.role !== "admin") return json({ error: "admins only" }, 403);

  let body: { source_url?: string | null; hint?: string } = {};
  try { body = await req.json(); } catch { /* an empty body is a valid "write from scratch" */ }

  let reference = "", refTitle = "";
  if (body.source_url) {
    let u: URL;
    try { u = new URL(body.source_url); } catch { return json({ error: "that is not a URL" }, 400); }
    if (u.protocol !== "https:" && u.protocol !== "http:") {
      return json({ error: "only http and https links can be read" }, 400);
    }
    try {
      const r = await fetch(u.toString(), {
        headers: { "User-Agent": "GenAITesting-Composer/1.0 (+https://genaitesting.online)" },
        signal: AbortSignal.timeout(20_000),
      });
      if (!r.ok) return json({ error: `the reference returned HTTP ${r.status}` }, 400);
      const html = await r.text();
      refTitle = titleFromHtml(html);
      reference = textFromHtml(html).slice(0, MAX_REF_CHARS);
      if (reference.length < 200) {
        return json({ error: "that page had almost no readable text — it may be a " +
                             "JavaScript app. Paste the text into the body instead." }, 400);
      }
    } catch (e) {
      return json({ error: "could not read that link: " + (e as Error).message }, 400);
    }
  }

  // The instruction is deliberately strict about honesty and about not copying. A
  // post that restates someone else's article adds nothing, ranks for nothing, and
  // is a copyright problem; a post that answers the same question from our own
  // teaching is the thing worth publishing.
  const prompt = `You write for genaitesting.online, which teaches software testers how to
test GenAI, LLM, RAG and AI-agent applications. Write one blog post.

${reference ? `A reader sent this reference article. Use it only as a starting point for what
to write about — form your own explanation from what the course teaches, do not
summarise or paraphrase it, and never reproduce its sentences.

REFERENCE TITLE: ${refTitle}
REFERENCE TEXT:
${reference}` : `Pick a topic a tester moving into AI testing genuinely gets stuck on.`}

${body.hint ? `The author also said: ${body.hint}` : ""}

Rules:
- title: under 60 characters including spaces. Specific, not clever.
- description: between 80 and 155 characters. One sentence someone would click.
- slug: lowercase words and hyphens, under 60 characters.
- keywords: 3 to 6 real search phrases a person would type.
- body_html: 400 to 700 words. Use <h2> for each question the post answers and
  <p class="lead"> for paragraphs. No <h1> — the page adds it. Include one link to
  ../genai-testing-course.html or ../faq.html where it genuinely helps.
- Each paragraph must stand on its own: an AI assistant will quote one in isolation.
- Be specific — name real tools, metrics and failure modes.
- Be honest. If a competing tool or certification is the better answer for some
  readers, say so.
- No invented statistics, no claims about outcomes we have not measured, no
  testimonials, no "studies show".

Return only JSON: {"title","description","slug","keywords":[],"body_html"}`;

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": key,
               "anthropic-version": "2023-06-01" },
    body: JSON.stringify({
      model: Deno.env.get("DRAFT_MODEL") ?? "claude-sonnet-4-5",
      max_tokens: 3000,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!r.ok) {
    const t = await r.text();
    return json({ error: `the model API returned ${r.status}: ${t.slice(0, 300)}` }, 502);
  }
  const out = await r.json();
  const text = (out.content ?? []).map((c: { text?: string }) => c.text ?? "").join("").trim();

  // Models sometimes wrap JSON in a fence however firmly you ask them not to.
  const m = text.match(/\{[\s\S]*\}/);
  if (!m) return json({ error: "the model did not return JSON", raw: text.slice(0, 400) }, 502);
  let draft;
  try { draft = JSON.parse(m[0]); }
  catch (e) { return json({ error: "the model's JSON did not parse: " + (e as Error).message }, 502); }

  return json({ ...draft, source_url: body.source_url ?? null, source_title: refTitle || null });
});
