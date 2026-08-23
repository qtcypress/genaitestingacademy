#!/usr/bin/env bash
# Netlify's build-ignore hook. Exit 0 = skip the build, exit 1 = build.
#
# Why this exists: the free plan grants 300 credits a month and a production
# deploy costs 15 of them. That is twenty deploys, and this repository holds far
# more than the website — the Supabase migrations, the edge functions, the
# rag-console service and the setup guides all live here too. Committing a
# migration used to spend a deploy republishing a byte-identical site.
#
# So: work out what actually changed since the last successful build, and skip
# when none of it can reach the published output. The list below is a *denylist*
# on purpose. Anything unrecognised builds, because the cost of one wasted deploy
# is 15 credits and the cost of wrongly skipping one is a stale live site.

set -uo pipefail

# On the very first build, or if the previous commit is unknown, always build.
if [ -z "${CACHED_COMMIT_REF:-}" ] || [ -z "${COMMIT_REF:-}" ]; then
  echo "no cached commit — building"
  exit 1
fi

if ! CHANGED=$(git diff --name-only "$CACHED_COMMIT_REF" "$COMMIT_REF" 2>/dev/null); then
  echo "cannot diff $CACHED_COMMIT_REF..$COMMIT_REF — building to be safe"
  exit 1
fi

if [ -z "$CHANGED" ]; then
  echo "nothing changed — skipping"
  exit 0
fi

# Paths that cannot affect anything scripts/build-site.sh copies into _site.
IRRELEVANT='^(schema.*\.sql|edge-functions/|rag-console/|RAG project/|\.github/|[A-Z-]+\.md|README\.md|seo/content-backlog\.md|blog/posts/.*\.json)'

RELEVANT=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if ! printf '%s' "$f" | grep -Eq "$IRRELEVANT"; then
    RELEVANT="$RELEVANT $f"
  fi
done <<< "$CHANGED"

# blog/posts/*.json is in the denylist above but is genuinely published *through*
# the generator, so treat a change there as relevant after all — unless the post
# is still a draft, which is the case worth skipping and the reason drafts can be
# committed freely.
while IFS= read -r f; do
  case "$f" in
    blog/posts/*.json)
      if git show "$COMMIT_REF:$f" 2>/dev/null | grep -q '"published"[[:space:]]*:[[:space:]]*"'; then
        RELEVANT="$RELEVANT $f"
      else
        echo "  $f is still a draft — not a reason to deploy"
      fi
      ;;
  esac
done <<< "$CHANGED"

if [ -z "${RELEVANT// /}" ]; then
  echo "only non-published files changed — skipping this deploy:"
  printf '  %s\n' $CHANGED
  exit 0
fi

echo "published files changed — building:"
printf '  %s\n' $RELEVANT
exit 1
