#!/usr/bin/env bash
# Assemble the publish directory for Netlify.
#
# This exists because the repository root is not the website. Alongside the 32
# files that should be public it holds schema-*.sql, the Supabase edge functions,
# the whole rag-console service, seo/*.py and the setup guides. Pointing Netlify at
# the repo root would publish every one of them — the database schema most of all.
# Until now that was prevented only by hand-picking files into a zip, which is also
# why the repo drifted three weeks behind production.
#
# So the curated list lives here instead: explicit, reviewable, and the same list
# every time. Adding a page to the site means adding it here, and the SEO watchdog
# will fail the next morning if a page in the sitemap is not being served.
set -euo pipefail

OUT="${1:-_site}"
rm -rf "$OUT"
mkdir -p "$OUT"

# Regenerate the built pages so a syllabus or FAQ edit cannot ship stale HTML.
python3 seo/build.py "$(date -u +%Y-%m-%d)"

PAGES=(
  index.html app.html admin.html projects.html viewer.html quiz.html
  certificate.html verify.html pricing.html reset-password.html unsubscribe.html
  genai-testing-course.html python-dsa-course.html faq.html
)
ASSETS=(
  app.css app.js config.js sw.js manifest.webmanifest
  logo.svg logo-mono.svg logo-on-light.svg favicon.svg favicon.ico
  icon-192.png icon-512.png icon-maskable-512.png apple-touch-icon.png
  social-card.png robots.txt sitemap.xml
)

for f in "${PAGES[@]}" "${ASSETS[@]}"; do
  if [ ! -f "$f" ]; then echo "missing required file: $f" >&2; exit 1; fi
  cp "$f" "$OUT/"
done

# Blog posts, once there are any. Copied wholesale because each one is a finished
# static page; the generator writes them and the sitemap already lists them.
if [ -d blog ]; then
  mkdir -p "$OUT/blog"
  cp -r blog/. "$OUT/blog/"
fi

# The IndexNow key proves domain ownership to Bing and must keep being served.
shopt -s nullglob
for k in [0-9a-f]*.txt; do cp "$k" "$OUT/"; done
shopt -u nullglob

# Nothing that is not meant to be public should have crept in.
if find "$OUT" -name "*.sql" -o -name "*.py" -o -name "*.md" -o -name "*.ts" | grep -q .; then
  echo "refusing to publish: source files found in $OUT" >&2
  find "$OUT" -name "*.sql" -o -name "*.py" -o -name "*.md" -o -name "*.ts" >&2
  exit 1
fi

echo "published $(find "$OUT" -type f | wc -l) files to $OUT"
