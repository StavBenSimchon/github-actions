#!/usr/bin/env bash
# Prune old versions of a GHCR package. Keeps newest $KEEP, deletes the rest.
# Usage: prune.sh <package-name-with-owner>   e.g. "octocat/my-image"
# Best-effort: pruning never fails the caller.
set -uo pipefail

PACKAGE="${1:?package name required}"
KEEP="${KEEP:-3}"
OWNER="${GITHUB_REPOSITORY%%/*}"
export GH_TOKEN="${CLEANUP_TOKEN:-${TOKEN}}"

PACKAGE_ENC=$(printf '%s' "$PACKAGE" | jq -sRr @uri)

if [ "$(gh api "users/${OWNER}" --jq .type)" = "Organization" ]; then
  BASE="orgs/${OWNER}"
else
  BASE="users/${OWNER}"
fi

echo "Pruning ${PACKAGE}: keeping newest ${KEEP} versions"

ALL=$(gh api --paginate "${BASE}/packages/container/${PACKAGE_ENC}/versions?per_page=100" \
  | jq -s 'add | sort_by(.created_at) | reverse') \
  || { echo "WARN: cannot list versions, skipping prune"; exit 0; }

COUNT=$(echo "$ALL" | jq 'length')
if [ "$COUNT" -le "$KEEP" ]; then
  echo "Only ${COUNT} version(s) exist, nothing to prune"
  exit 0
fi

echo "$ALL" | jq -r --argjson keep "$KEEP" ".[\$keep:] | .[].id" | while read -r id; do
  if gh api -X DELETE "${BASE}/packages/container/${PACKAGE_ENC}/versions/${id}" --silent; then
    echo "  deleted version ${id}"
  else
    echo "  WARN: cannot delete version ${id} (token needs delete:packages)"
  fi
done

exit 0
