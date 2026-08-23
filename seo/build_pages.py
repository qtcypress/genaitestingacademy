"""Build the public, indexable pages for genaitesting.online.

Why a generator and not three hand-written files: the <head> of a page carries
about twenty tags that all have to agree with each other — canonical, og:url and
the sitemap entry are the same URL written three times, og:title and <title> are
the same sentence written twice. Hand-typing that three times is how a canonical
ends up pointing at the wrong page, which is the one SEO mistake that can quietly
de-index a page rather than merely rank it badly. So the URL is written once here
and every tag is derived from it.

Every factual claim below was read out of the live database, not estimated:
  - GenAI Testing: 16 modules, three certification levels (Basic/Advanced/Expert)
  - Python Zero to Hero: 24 modules, six phases, five lessons each
  - plans: 49900 / 119900 / 399900 paise INR for 30 / 90 / 365 days
There is deliberately no aggregateRating anywhere. We have no ratings, and
inventing them is both dishonest and a manual-action risk with Google.
"""
import json
import pathlib

SITE = "https://genaitesting.online"
BRAND = "GenAITesting"
OUT = pathlib.Path(__file__).resolve().parent.parent

PLANS = [
    ("monthly",   "1 Month",   499.0,  30),
    ("quarterly", "3 Months",  1199.0, 90),
    ("yearly",    "12 Months", 3999.0, 365),
]

ORG = {
    "@type": "EducationalOrganization",
    "@id": SITE + "/#org",
    "name": BRAND,
    "alternateName": "GenAI Testing Academy",
    "url": SITE + "/",
    "logo": {"@type": "ImageObject", "url": SITE + "/icon-512.png",
             "width": 512, "height": 512},
    "image": SITE + "/social-card.png",
    # Hyderabad is where the training is run from and it is a real search term
    # ("AI testing course in Hyderabad" is a People-Also-Ask question), but the
    # courses are online, so areaServed is worldwide rather than a city. No
    # street address or phone number is asserted here because I do not have
    # verified ones, and a wrong address in schema is worse than none.
    "address": {"@type": "PostalAddress", "addressLocality": "Hyderabad",
                "addressRegion": "Telangana", "addressCountry": "IN"},
    "areaServed": {"@type": "Place", "name": "Worldwide"},
    "sameAs": ["https://github.com/qtcypress/genaitestingacademy"],
}

WEBSITE = {
    "@type": "WebSite",
    "@id": SITE + "/#website",
    "url": SITE + "/",
    "name": BRAND,
    "publisher": {"@id": SITE + "/#org"},
    "inLanguage": "en",
}


def offers(course_url):
    """One Offer per plan. A subscription unlocks both courses, so both course
    pages legitimately carry the same offers — the thing being sold is access."""
    return [{
        "@type": "Offer",
        "name": name,
        "price": "%.2f" % amount,
        "priceCurrency": "INR",
        "category": "subscription",
        "url": SITE + "/pricing.html",
        "availability": "https://schema.org/InStock",
        "eligibleDuration": {"@type": "QuantitativeValue",
                             "value": days, "unitCode": "DAY"},
    } for _, name, amount, days in PLANS]


import html as _html


def _rendered_len(s):
    """Length as a search engine sees it: entities are one character, not five."""
    return len(_html.unescape(s))


def head(*, path, title, desc, og_title=None, og_desc=None, ld=None,
         extra_css="", robots=None, rel=""):
    # `rel` prefixes every same-site asset path. Blog posts live one directory down,
    # so they need "../". Getting this wrong does not error — it silently serves a
    # page with no stylesheet, which is why it is a parameter rather than a habit.
    # Google truncates a title around 60 characters and a description around 155,
    # and a truncated description is worse than a short one because the sentence
    # that was meant to earn the click gets cut mid-word. Asserting here rather
    # than eyeballing it means a future edit that overshoots fails the build
    # instead of quietly shipping an ellipsis.
    tl, dl = _rendered_len(title), _rendered_len(desc)
    assert tl <= 60, f"{path}: title is {tl} rendered chars, max 60 — {title!r}"
    assert dl <= 155, f"{path}: description is {dl} rendered chars, max 155 — {desc!r}"
    assert dl >= 110, f"{path}: description is only {dl} chars; use the space"
    url = SITE + "/" + path if path else SITE + "/"
    ld_block = ""
    if ld:
        ld_block = ('<script type="application/ld+json">\n'
                    + json.dumps(ld, indent=1, ensure_ascii=False)
                    + "\n</script>\n")
    robots_tag = f'<meta name="robots" content="{robots}">\n' if robots else ""
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
{robots_tag}<link rel="canonical" href="{url}">
<link rel="manifest" href="{rel}manifest.webmanifest">
<meta name="theme-color" content="#1F3864">
<link rel="icon" href="{rel}favicon.ico" sizes="32x32">
<link rel="icon" href="{rel}favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="{rel}apple-touch-icon.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="{BRAND}">
<meta property="og:title" content="{og_title or title}">
<meta property="og:description" content="{og_desc or desc}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}/social-card.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="{BRAND} — GenAI application testing training and certification">
<meta property="og:locale" content="en_IN">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{og_title or title}">
<meta name="twitter:description" content="{og_desc or desc}">
<meta name="twitter:image" content="{SITE}/social-card.png">
<link rel="stylesheet" href="{rel}app.css">
{ld_block}{extra_css}</head>
<body>
<nav class="topbar" id="topbar"></nav>
"""


def tail(active, rel=""):
    return f"""
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
<script src="{rel}config.js"></script>
<script src="{rel}app.js"></script>
<script>renderTopbar("{active}", "{rel}");</script>
</body>
</html>
"""


# Kept so the existing three pages need no edit; new callers should use tail().
TAIL = """
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
<script src="config.js"></script>
<script src="app.js"></script>
<script>renderTopbar("%s");</script>
</body>
</html>
"""


def crumbs(items):
    return {"@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": i + 1, "name": n,
         "item": SITE + "/" + u if u else SITE + "/"}
        for i, (n, u) in enumerate(items)]}


def footer(active_note="", rel=""):
    return f"""
<footer class="site-foot">
  <div class="wrap">
    <p class="muted" style="margin:0 0 10px">
      <a href="{rel}genai-testing-course.html">GenAI Testing course</a> ·
      <a href="{rel}python-dsa-course.html">Python &amp; DSA course</a> ·
      <a href="{rel}faq.html">FAQ</a> ·
      <a href="{rel}projects.html">Hands-on projects</a> ·
      <a href="{rel}pricing.html">Pricing</a> ·
      <a href="{rel}verify.html">Verify a certificate</a>
    </p>
    <p class="muted" style="margin:0;font-size:12.5px">
      {BRAND} — online training in GenAI, LLM and AI agent application testing,
      run from Hyderabad, India, open to learners anywhere.{active_note}
    </p>
  </div>
</footer>
"""
