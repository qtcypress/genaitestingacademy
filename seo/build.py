"""Write the public pages, robots.txt and sitemap.xml into the site root."""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from build_pages import SITE, OUT          # noqa: E402
import pages_genai, pages_python, pages_faq  # noqa: E402

# (filename, builder, sitemap priority). Only pages that should be indexed appear
# here — the sitemap is a statement about what we want crawled, so putting a
# noindex page in it is a contradiction a crawler will report as an error.
PAGES = [
    ("genai-testing-course.html", pages_genai.build, "0.9"),
    ("python-dsa-course.html", pages_python.build, "0.9"),
    ("faq.html", pages_faq.build, "0.7"),
]

# Public pages that already exist and are not generated here, but do belong in
# the sitemap.
EXISTING_PUBLIC = [("", "1.0"), ("pricing.html", "0.8"),
                   ("projects.html", "0.7"), ("verify.html", "0.5")]

ROBOTS = """# genaitesting.online
#
# Student-only pages are excluded here *and* carry a noindex meta tag. The tag is
# what actually keeps them out of the index — a Disallow only stops crawling, and
# a page that is linked from elsewhere can still be indexed without being read,
# which is how login pages end up in search results with no description. Both,
# then, deliberately.
User-agent: *
Allow: /
Disallow: /admin.html
Disallow: /app.html
Disallow: /viewer.html
Disallow: /quiz.html
Disallow: /certificate.html
Disallow: /reset-password.html
Disallow: /unsubscribe.html
Disallow: /*?next=

# The assistant crawlers are allowed on purpose. Being quoted by an assistant is
# now a real route to this site, and the FAQ page exists to be quoted — blocking
# these would forfeit that while doing nothing for privacy, since everything they
# can reach is already public.
User-agent: GPTBot
Allow: /

User-agent: OAI-SearchBot
Allow: /

User-agent: ChatGPT-User
Allow: /

User-agent: ClaudeBot
Allow: /

User-agent: Claude-SearchBot
Allow: /

User-agent: PerplexityBot
Allow: /

User-agent: Google-Extended
Allow: /

Sitemap: %s/sitemap.xml
""" % SITE


def sitemap(entries, lastmod):
    urls = "\n".join(
        f"""  <url>
    <loc>{SITE}/{path}</loc>
    <lastmod>{lastmod}</lastmod>
    <priority>{prio}</priority>
  </url>""" for path, prio in entries)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
{urls}
</urlset>
"""


def main(lastmod):
    written = []
    for name, build, _ in PAGES:
        html = build()
        (OUT / name).write_text(html, encoding="utf-8")
        written.append((name, len(html)))

    entries = EXISTING_PUBLIC + [(n, p) for n, _, p in PAGES]
    # homepage first, then by descending priority, so the file reads sensibly
    entries.sort(key=lambda e: (-float(e[1]), e[0]))
    (OUT / "sitemap.xml").write_text(sitemap(entries, lastmod), encoding="utf-8")
    (OUT / "robots.txt").write_text(ROBOTS, encoding="utf-8")

    for n, size in written:
        print(f"  wrote {n:34s} {size:>7,} bytes")
    print(f"  wrote {'sitemap.xml':34s} {len(entries)} urls")
    print(f"  wrote {'robots.txt':34s}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "2026-08-19")
