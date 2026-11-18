#!/usr/bin/env bash
# Prune old versions of a GHCR package. Keeps newest $KEEP, deletes the rest.
# Usage: prune.sh <package-name-with-owner>   e.g. "octocat/my-image"
# Best-effort: pruning never fails the caller.
set -uo pipefail

PACKAGE="${1:?package name required}"
PACKAGE="${PACKAGE,,}"   # GHCR package names are lowercase
KEEP="${KEEP:-3}"
OWNER="${GITHUB_REPOSITORY%%/*}"
TOKEN_USE="${CLEANUP_TOKEN:-${TOKEN}}"

PACKAGE_ENC=$(printf '%s' "$PACKAGE" | jq -sRr @uri)
API="https://api.github.com"
AUTH=(-H "Authorization: Bearer ${TOKEN_USE}" -H "Accept: application/vnd.github+json")

if [ "$(curl -fsS "${AUTH[@]}" "${API}/users/${OWNER}" | jq -r .type)" = "Organization" ]; then
  BASE="orgs/${OWNER}"
else
  BASE="users/${OWNER}"
fi

echo "Pruning ${PACKAGE}: keeping newest ${KEEP} versions"

# collect all versions — with retry, registry needs a moment after push
VERSIONS="[]"
OK=0
ERR=""
for attempt in 1 2 3; do
  PAGE=1
  VERSIONS="[]"
  OK=1
  while :; do
    RESP=$(curl -sS "${AUTH[@]}" "${API}/${BASE}/packages/container/${PACKAGE_ENC}/versions?per_page=100&page=${PAGE}")
    if ! echo "$RESP" | jq -e 'type == "array"' >/dev/null 2>&1; then
      OK=0
      ERR=$(echo "$RESP" | jq -r '.message' 2>/dev/null || true)
      ERR="${ERR:-${RESP}}"
      break
    fi
    VERSIONS=$(jq -n --argjson a "$VERSIONS" --argjson b "$RESP" '$a + $b')
    if [ "$(echo "$RESP" | jq 'length')" -lt 100 ]; then
      break
    fi
    PAGE=$((PAGE + 1))
  done
  if [ "$OK" = "1" ]; then
    break
  fi
  echo "  attempt ${attempt}: list failed (${ERR}) - retrying in 5s"
  sleep 5
done

if [ "$OK" != "1" ]; then
  echo "WARN: cannot list versions (${ERR}) - skipping prune"
  exit 0
fi

SORTED=$(echo "$VERSIONS" | jq 'sort_by(.created_at) | reverse')
COUNT=$(echo "$SORTED" | jq 'length')
echo "Found ${COUNT} version(s)"

if [ "$COUNT" -le "$KEEP" ]; then
  echo "Nothing to prune"
  exit 0
fi

echo "$SORTED" | jq -r --argjson keep "$KEEP" ".[\$keep:] | .[].id" | while read -r id; do
  CODE=$(curl -sS -o /tmp/prune-resp.json -w "%{http_code}" -X DELETE "${AUTH[@]}" \
    "${API}/${BASE}/packages/container/${PACKAGE_ENC}/versions/${id}")
  if [ "$CODE" = "204" ] || [ "$CODE" = "200" ]; then
    echo "  deleted version ${id}"
  else
    echo "  WARN: cannot delete version ${id} (HTTP ${CODE}: $(jq -r '.message // ""' /tmp/prune-resp.json 2>/dev/null))"
  fi
done

exit 0
