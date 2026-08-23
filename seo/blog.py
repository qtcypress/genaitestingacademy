"""The blog: index page plus one static HTML file per post.

Posts are committed to the repository as data and rendered here into real pages,
for the same reason the syllabus is baked rather than fetched. Googlebot renders
JavaScript eventually; the assistant crawlers that matter for AEO mostly do not.
A post that only exists after a fetch is a post ChatGPT and Perplexity will never
quote, and being quoted is most of why a training company writes one.

Each post carries what a search engine and an answer engine each need:

  search  — a unique title under 60 chars, a description under 155, a canonical,
            Open Graph and Twitter tags, and a sitemap entry
  answers — Article schema with a real datePublished and author, headings that
            are questions, and self-contained paragraphs that survive being
            lifted out of the page

`meta keywords` is deliberately absent. Google has ignored it since 2009 and Bing
treats it as a spam signal; the "keywords" that matter are the ones in the title,
the h1, the first paragraph and the headings, which is where the composer puts them.

A post lives in blog/posts/<slug>.json:

  {"slug", "title", "description", "published", "updated", "author",
   "keywords": [...], "body_html", "source_url"?, "source_title"?}
"""
import html
import json
import pathlib
import re

from build_pages import SITE, BRAND, head, tail, crumbs, ORG, WEBSITE, footer

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
POSTS_DIR = ROOT / "blog" / "posts"
OUT_DIR = ROOT / "blog"


def load_posts():
    """Newest first. A post with no published date is a draft and is skipped —
    that is how the composer can commit work in progress without it going live."""
    posts = []
    if not POSTS_DIR.exists():
        return posts
    for f in sorted(POSTS_DIR.glob("*.json")):
        try:
            p = json.loads(f.read_text(encoding="utf-8"))
        except Exception as e:
            raise SystemExit(f"{f.name} is not valid JSON: {e}")
        if not p.get("published"):
            continue
        for req in ("slug", "title", "description", "body_html"):
            if not p.get(req):
                raise SystemExit(f"{f.name} is missing required field {req!r}")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{2,80}", p["slug"]):
            raise SystemExit(f"{f.name}: slug {p['slug']!r} must be lowercase words and hyphens")
        posts.append(p)
    posts.sort(key=lambda p: p["published"], reverse=True)
    return posts


def post_url(slug):
    return f"{SITE}/blog/{slug}.html"


def article_ld(p):
    node = {
        "@type": "Article",
        "@id": post_url(p["slug"]) + "#article",
        "headline": p["title"],
        "description": p["description"],
        "url": post_url(p["slug"]),
        "datePublished": p["published"],
        "dateModified": p.get("updated") or p["published"],
        "author": {"@type": "Organization", "name": p.get("author") or BRAND,
                   "url": SITE + "/"},
        "publisher": {"@id": SITE + "/#org"},
        "image": SITE + "/social-card.png",
        "inLanguage": "en",
        "isAccessibleForFree": True,
        "mainEntityOfPage": {"@type": "WebPage", "@id": post_url(p["slug"])},
    }
    if p.get("keywords"):
        # schema keywords are read by some answer engines; the <meta name="keywords">
        # tag is not, which is why only this one exists
        node["keywords"] = ", ".join(p["keywords"])
    return node


def build_post(p, others):
    ld = {"@context": "https://schema.org", "@graph": [
        ORG, WEBSITE, article_ld(p),
        crumbs([("Home", ""), ("Blog", "blog/"), (p["title"], f"blog/{p['slug']}.html")]),
    ]}

    # Two or three other posts, so no post is a dead end and link equity moves
    # around the blog instead of stopping.
    more = [q for q in others if q["slug"] != p["slug"]][:3]
    more_html = ""
    if more:
        items = "\n".join(
            f'      <a class="mod mod-free" href="{q["slug"]}.html">'
            f'<span class="mod-t">{html.escape(q["title"])}</span>'
            f'<span class="mod-s">{html.escape(q["description"])}</span></a>'
            for q in more)
        more_html = f"""
  <section class="section">
    <h2>More on testing AI systems</h2>
    <div class="modlist">
{items}
    </div>
  </section>"""

    src = ""
    if p.get("source_url"):
        # Say where something came from. A post built on someone else's article
        # that does not say so is passing off, and a visible citation is also the
        # thing that makes the claim checkable.
        src = (f'<p class="muted" style="font-size:13px;margin-top:22px">'
               f'Written with reference to '
               f'<a href="{html.escape(p["source_url"])}" rel="nofollow noopener" target="_blank">'
               f'{html.escape(p.get("source_title") or p["source_url"])}</a>.</p>')

    body = f"""
<header class="hero">
  <div class="wrap">
    <p class="hero-eyebrow"><a href="./" style="color:var(--amber)">Blog</a></p>
    <h1>{html.escape(p["title"])}</h1>
    <p>{html.escape(p["description"])}</p>
    <p class="muted" style="color:#CFD5E4;font-size:13px;margin-top:14px">
      {html.escape(p.get("author") or BRAND)} · <time datetime="{p['published']}">{p['published']}</time>
      {f" · updated <time datetime='{p['updated']}'>{p['updated']}</time>" if p.get("updated") and p["updated"] != p["published"] else ""}
    </p>
  </div>
</header>

<main class="wrap section">
  <article class="post">
{p["body_html"]}
  </article>
  {src}
{more_html}

  <section class="section card" style="margin-top:30px">
    <h2 style="margin-top:0">Learn this properly</h2>
    <p class="muted">These techniques are taught hands-on in the
      <a href="../genai-testing-course.html">GenAI Testing course</a>, against two real
      applications you attack rather than watch. Module 1 is free.</p>
    <p style="margin-bottom:0">
      <a class="btn btn-primary" href="../index.html?next=app.html&amp;start=free">Start free</a>
      <a class="btn btn-ghost" href="../faq.html">Read the FAQ</a>
    </p>
  </section>
</main>
"""
    h = head(path=f"blog/{p['slug']}.html", title=p["title"] + " | " + BRAND,
             desc=p["description"], og_title=p["title"], ld=ld, rel="../")
    return h + body + footer(rel="../") + tail("blog", rel="../")


def build_index(posts):
    if posts:
        rows = "\n".join(
            f'''      <a class="mod mod-free" href="{q["slug"]}.html">
        <span class="mod-n">{q["published"]}</span>
        <span class="mod-t">{html.escape(q["title"])}</span>
        <span class="mod-s">{html.escape(q["description"])}</span>
      </a>''' for q in posts)
        listing = f'<div class="modlist">\n{rows}\n    </div>'
    else:
        listing = ('<p class="lead">Nothing published yet. The first posts are being '
                   'written — the questions they answer are the ones people actually '
                   'search for before choosing a course.</p>')

    ld = {"@context": "https://schema.org", "@graph": [
        ORG, WEBSITE,
        {"@type": "Blog", "@id": SITE + "/blog/#blog", "url": SITE + "/blog/",
         "name": BRAND + " — testing AI systems",
         "description": "Practical notes on testing GenAI, LLM, RAG and AI agent applications.",
         "publisher": {"@id": SITE + "/#org"},
         "blogPost": [{"@type": "Article", "headline": q["title"],
                       "url": post_url(q["slug"]), "datePublished": q["published"]}
                      for q in posts]},
        crumbs([("Home", ""), ("Blog", "blog/")]),
    ]}

    body = f"""
<header class="hero">
  <div class="wrap">
    <p class="hero-eyebrow">Blog</p>
    <h1>Testing AI systems<br><span class="accent">notes from the course</span></h1>
    <p>
      Short, practical pieces on the things testers actually get stuck on: how to tell
      a hallucination from a retrieval failure, what to assert when there is no single
      right answer, and which controls are worth having.
    </p>
  </div>
</header>

<main class="wrap section">
  <section class="section">
    {listing}
  </section>
</main>
"""
    h = head(path="blog/", title="Blog — Testing AI Systems | " + BRAND,
             desc=("Practical notes on testing GenAI, LLM, RAG and AI agent applications — "
                   "hallucination detection, prompt injection, RAG evaluation and agent controls."),
             ld=ld, rel="../")
    return h + body + footer(rel="../") + tail("blog", rel="../")


def write_all():
    posts = load_posts()
    OUT_DIR.mkdir(exist_ok=True)
    (OUT_DIR / "index.html").write_text(build_index(posts), encoding="utf-8")
    for p in posts:
        (OUT_DIR / f"{p['slug']}.html").write_text(build_post(p, posts), encoding="utf-8")
    return posts


def sitemap_entries(posts):
    """Blog index plus each post, for build.py to fold into sitemap.xml."""
    out = [("blog/", "0.6")] if posts else []
    out += [(f"blog/{p['slug']}.html", "0.6") for p in posts]
    return out
