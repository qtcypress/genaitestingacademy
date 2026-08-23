"""Check the live site for the SEO mistakes that are silent until they cost you.

Run by .github/workflows/seo-watchdog.yml every morning, and on every push that
touches the site. It runs in GitHub Actions rather than anywhere else for one
measured reason: the Cowork sandbox cannot reach genaitesting.online, google.com,
bing.com or api.indexnow.org — of seven hosts tested, only api.github.com answered.
Actions has real network access, is free on a public repo, and runs whether or not
anyone's laptop is on.

Every check here corresponds to a real bug that was actually shipped to this site
and found by hand:

  * app.html and certificate.html were indexable with no content behind a login
  * the homepage claimed canonical "/" while telling social platforms "/index.html"
  * robots.txt and sitemap.xml were both 404 for weeks
  * manifest.webmanifest still carried the old brand long after the rebrand
  * a title grew past 60 characters and would have been truncated mid-sentence

Each was invisible from the outside and none would have failed a build. That is
what this file is for: turning "someone eventually noticed" into "the build went
red the next morning".

Exit code 1 on any failure, so the workflow goes red and GitHub emails the owner.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

# Overridable so the checker can be run against a local copy before it is deployed,
# which is how it gets tested rather than trusted.
SITE = os.environ.get("SEO_SITE", "https://genaitesting.online").rstrip("/")
UA = "GenAITesting-SEO-Watchdog/1.0 (+https://genaitesting.online)"

# Pages the world should be able to find.
PUBLIC = ["", "genai-testing-course.html", "python-dsa-course.html", "faq.html",
          "pricing.html", "projects.html", "verify.html"]

# Pages that exist for signed-in students. An indexed login shell is worse than no
# page at all: it puts a student-only URL in results under a blank snippet.
PRIVATE = ["app.html", "certificate.html", "quiz.html", "viewer.html", "admin.html",
           "reset-password.html", "unsubscribe.html"]

# Google truncates around these. A cut-off description is worse than a short one,
# because the sentence meant to earn the click is the half that disappears.
TITLE_MAX = 60
DESC_MAX = 155
DESC_MIN = 80

DEAD_BRAND = re.compile(r"quality\s*thought|QT GenAI|QT Academy", re.I)

problems = []
notes = []


def fetch(path):
    url = SITE + "/" + path
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception as e:                                   # DNS, TLS, timeout
        return 0, str(e)


def tag(html, pattern):
    m = re.search(pattern, html, re.I | re.S)
    return m.group(1).strip() if m else None


def unescape(s):
    import html as h
    return h.unescape(s or "")


def check_public(path):
    label = path or "/"
    status, html = fetch(path)
    if status != 200:
        problems.append(f"{label}: HTTP {status} — a public page is not being served")
        return

    title = unescape(tag(html, r"<title>(.*?)</title>"))
    desc = unescape(tag(html, r'<meta name="description" content="([^"]*)"'))
    canon = tag(html, r'<link rel="canonical" href="([^"]+)"')
    ogurl = tag(html, r'<meta property="og:url" content="([^"]+)"')
    robots = tag(html, r'<meta name="robots" content="([^"]+)"')

    if not title:
        problems.append(f"{label}: no <title>")
    elif len(title) > TITLE_MAX:
        problems.append(f"{label}: title is {len(title)} chars, Google truncates near {TITLE_MAX} — {title!r}")

    if not desc:
        problems.append(f"{label}: no meta description — Google will invent a snippet")
    elif len(desc) > DESC_MAX:
        problems.append(f"{label}: description is {len(desc)} chars, truncates near {DESC_MAX}")
    elif len(desc) < DESC_MIN:
        problems.append(f"{label}: description is only {len(desc)} chars — wasted space")

    if not canon:
        problems.append(f"{label}: no canonical")
    if canon and ogurl and canon != ogurl:
        problems.append(f"{label}: canonical {canon} but og:url {ogurl} — two URLs for one page")

    if robots and "noindex" in robots.lower():
        problems.append(f"{label}: PUBLIC page carries noindex — it cannot rank at all")

    if not re.search(r"<h1[ >]", html, re.I):
        problems.append(f"{label}: no <h1>")

    for block in re.findall(r'<script type="application/ld\+json">(.*?)</script>', html, re.S):
        try:
            json.loads(block)
        except Exception as e:
            problems.append(f"{label}: JSON-LD does not parse — {e}")

    if DEAD_BRAND.search(html):
        found = set(DEAD_BRAND.findall(html))
        problems.append(f"{label}: retired brand name is back — {sorted(found)}")

    notes.append(f"  {label:<28} title {len(title or ''):>2}  desc {len(desc or ''):>3}  ok")


def check_private(path):
    status, html = fetch(path)
    if status != 200:
        notes.append(f"  {path:<28} HTTP {status} (not serving — not an SEO problem)")
        return
    robots = tag(html, r'<meta name="robots" content="([^"]+)"') or ""
    if "noindex" not in robots.lower():
        problems.append(f"{path}: student-only page is indexable — it will be indexed as an empty shell")
    else:
        notes.append(f"  {path:<28} noindex ok")


def check_infra():
    for f in ("robots.txt", "sitemap.xml"):
        status, body = fetch(f)
        if status != 200:
            problems.append(f"{f}: HTTP {status} — search engines cannot read it")
            continue
        notes.append(f"  {f:<28} 200")
        if f == "sitemap.xml":
            urls = re.findall(r"<loc>([^<]+)</loc>", body)
            if not urls:
                problems.append("sitemap.xml: contains no <loc> entries")
            for u in urls:
                # The sitemap always carries absolute production URLs, but SITE may
                # be a local copy under test. Take the path off the URL rather than
                # string-stripping a prefix that will not match.
                from urllib.parse import urlparse
                p = urlparse(u).path.lstrip("/")
                st, page = fetch(p)
                if st != 200:
                    problems.append(f"sitemap lists {u} which returns HTTP {st}")
                elif re.search(r'name="robots"[^>]*noindex', page, re.I):
                    # asking to crawl a page while telling it not to index is a
                    # contradiction search consoles report as an error
                    problems.append(f"sitemap lists {u} but that page is noindex")

    # The IndexNow key must stay reachable or Bing silently stops accepting pings.
    key = None
    status, robots_txt = fetch("robots.txt")
    m = re.search(r"([0-9a-f]{32})", robots_txt or "")
    try:
        import pathlib
        bp = pathlib.Path(__file__).with_name("build.py").read_text(encoding="utf-8")
        km = re.search(r'INDEXNOW_KEY = "([0-9a-f]{32})"', bp)
        key = km.group(1) if km else None
    except Exception:
        pass
    if key:
        st, body = fetch(key + ".txt")
        if st != 200 or body.strip() != key:
            problems.append(f"IndexNow key file {key}.txt: HTTP {st} — Bing submissions will be rejected")
        else:
            notes.append(f"  {'indexnow key':<28} 200 and matches")


def main():
    print(f"Checking {SITE}\n")
    for p in PUBLIC:
        check_public(p)
    for p in PRIVATE:
        check_private(p)
    check_infra()

    print("\n".join(notes))
    print()
    if problems:
        print(f"::error::{len(problems)} SEO problem(s) on the live site")
        for p in problems:
            print(f"  ✗ {p}")
            # surface each one in the Actions annotations too
            print(f"::error::{p}")
        return 1
    print(f"✓ {len(PUBLIC)} public and {len(PRIVATE)} student-only pages all correct")
    return 0


if __name__ == "__main__":
    sys.exit(main())
