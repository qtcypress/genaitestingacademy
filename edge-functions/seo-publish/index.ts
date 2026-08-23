// seo-publish — commit a saved draft to the repository as a blog post.
//
// The post is written to blog/posts/<slug>.json. Netlify is connected to the repo,
// so the push triggers a build: seo/build.py renders the JSON into a real static
// page, adds it to sitemap.xml, and the SEO watchdog checks it the next morning.
// Nothing here writes HTML — generating the page in one place is what stops a
// hand-built post from drifting away from the others.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   GITHUB_TOKEN   a fine-grained PAT with Contents: Read and write on this one repo
//   GITHUB_REPO    optional, defaults to qtcypress/genaitestingacademy
//   GITHUB_BRANCH  optional, defaults to main
//
// The token is deliberately not in the browser. A GitHub token with write access is
// worth more than the site: with it someone can rewrite any file in the repository,
// including the one Netlify deploys.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });

const REPO = Deno.env.get("GITHUB_REPO") ?? "qtcypress/genaitestingacademy";
const BRANCH = Deno.env.get("GITHUB_BRANCH") ?? "main";

async function gh(path: string, token: string, init: RequestInit = {}) {
  const r = await fetch("https://api.github.com" + path, {
    ...init,
    headers: {
      ...(init.headers ?? {}),
      Authorization: "Bearer " + token,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "GenAITesting-Publisher/1.0",
    },
  });
  const text = await r.text();
  let body: unknown = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  return { ok: r.ok, status: r.status, body };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const token = Deno.env.get("GITHUB_TOKEN");
  if (!token) {
    return json({ error: "GITHUB_TOKEN is not set on this function. " +
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

  const { slug } = await req.json().catch(() => ({ slug: null }));
  if (!slug || !/^[a-z0-9][a-z0-9-]{2,80}$/.test(slug)) {
    return json({ error: "a valid slug is required" }, 400);
  }

  // Read the draft from the database rather than from the request. The browser
  // already sent this content when it saved; taking it from the request again would
  // let a tampered call publish something the admin never reviewed.
  const { data: d, error: dErr } = await sb.from("seo_drafts").select("*").eq("slug", slug).single();
  if (dErr || !d) return json({ error: "no draft with that slug" }, 404);
  if (!d.title || !d.description || !d.body_html) {
    return json({ error: "the draft is missing a title, description or body" }, 400);
  }
  if (d.title.length > 60) return json({ error: `title is ${d.title.length} chars, max 60` }, 400);
  if (d.description.length > 155) {
    return json({ error: `description is ${d.description.length} chars, max 155` }, 400);
  }

  const today = new Date().toISOString().slice(0, 10);
  const post = {
    slug: d.slug,
    title: d.title,
    description: d.description,
    published: d.published_at ?? today,
    updated: d.published_at && d.published_at !== today ? today : undefined,
    author: "GenAITesting",
    keywords: d.keywords ?? [],
    body_html: d.body_html,
    source_url: d.source_url ?? undefined,
    source_title: d.source_title ?? undefined,
  };
  const path = `blog/posts/${d.slug}.json`;
  const content = btoa(unescape(encodeURIComponent(JSON.stringify(post, null, 2) + "\n")));

  // An update needs the blob sha of what is there; a new file must not send one.
  const existing = await gh(`/repos/${REPO}/contents/${path}?ref=${BRANCH}`, token);
  const sha = existing.ok && existing.body && typeof existing.body === "object"
    ? (existing.body as { sha?: string }).sha : undefined;

  const put = await gh(`/repos/${REPO}/contents/${path}`, token, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      message: (sha ? "Update post: " : "Publish post: ") + d.title,
      content,
      branch: BRANCH,
      ...(sha ? { sha } : {}),
    }),
  });

  if (!put.ok) {
    const detail = typeof put.body === "object" && put.body
      ? (put.body as { message?: string }).message ?? "" : String(put.body).slice(0, 200);
    // 403 here almost always means the token lacks Contents: write on this repo,
    // which is worth saying rather than passing through GitHub's terser wording.
    const hint = put.status === 403 || put.status === 404
      ? " — check the token has Contents: Read and write on " + REPO
      : "";
    return json({ error: `GitHub returned ${put.status}: ${detail}${hint}` }, 502);
  }

  const commit = (put.body as { commit?: { sha?: string; html_url?: string } }).commit ?? {};
  await sb.from("seo_drafts").update({
    status: "published",
    published_at: post.published,
    commit_sha: commit.sha ?? null,
  }).eq("slug", slug);

  // Publishing satisfies the weekly checklist item, so record it here rather than
  // relying on the admin to also remember to tick the box.
  await sb.rpc("seo_task_done", { p_id: "publish-post", p_note: "published " + slug });

  return json({
    ok: true,
    path,
    commit_sha: commit.sha ?? null,
    commit_url: commit.html_url ?? null,
    live_url: `https://genaitesting.online/blog/${slug}.html`,
    note: "Netlify builds from the push; the page is usually live within two minutes.",
  });
});
