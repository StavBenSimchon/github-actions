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

API="https://api.github.com"
AUTH=(-H "Authorization: Bearer ${TOKEN_USE}" -H "Accept: application/vnd.github+json")

# GitHub names container packages inconsistently across endpoints;
# try every known form and use the first that answers.
NAME_FULL="$PACKAGE"          # owner/image
NAME_BARE="${PACKAGE#*/}"     # image
BASE=""
NAME=""
ENC=""

probe() {
  local cand_base cand_name cand_enc resp
  for cand_base in "users/${OWNER}" "user"; do
    for cand_name in "$NAME_BARE" "$NAME_FULL"; do
      cand_enc=$(printf '%s' "$cand_name" | jq -sRr @uri)
      resp=$(curl -sS "${AUTH[@]}" "${API}/${cand_base}/packages/container/${cand_enc}/versions?per_page=100&page=1")
      if echo "$resp" | jq -e 'type == "array"' >/dev/null 2>&1; then
        BASE="$cand_base"
        NAME="$cand_name"
        ENC="$cand_enc"
        echo "  found package at ${BASE}/packages/container/${NAME}"
        return 0
      fi
    done
  done
  LAST_ERR=$(echo "$resp" | jq -r '.message' 2>/dev/null || true)
  LAST_ERR="${LAST_ERR:-${resp}}"
  return 1
}

echo "Pruning ${PACKAGE}: keeping newest ${KEEP} versions"

for attempt in 1 2 3; do
  if probe; then
    break
  fi
  echo "  attempt ${attempt}: package not reachable (${LAST_ERR:-no response}) - retrying in 5s"
  sleep 5
done

if [ -z "$BASE" ]; then
  echo "WARN: cannot find package via REST API - skipping prune"
  exit 0
fi

# collect all versions
VERSIONS=$(curl -sS "${AUTH[@]}" "${API}/${BASE}/packages/container/${ENC}/versions?per_page=100&page=1")
PAGE=2
while [ "$(echo "$VERSIONS" | jq 'length')" -ge 100 ]; do
  RESP=$(curl -sS "${AUTH[@]}" "${API}/${BASE}/packages/container/${ENC}/versions?per_page=100&page=${PAGE}")
  echo "$RESP" | jq -e 'type == "array"' >/dev/null 2>&1 || break
  VERSIONS=$(jq -n --argjson a "$VERSIONS" --argjson b "$RESP" '$a + $b')
  PAGE=$((PAGE + 1))
done

SORTED=$(echo "$VERSIONS" | jq 'sort_by(.created_at) | reverse')
COUNT=$(echo "$SORTED" | jq 'length')
echo "Found ${COUNT} version(s)"

if [ "$COUNT" -le "$KEEP" ]; then
  echo "Nothing to prune"
  exit 0
fi

echo "$SORTED" | jq -r --argjson keep "$KEEP" ".[\$keep:] | .[].id" | while read -r id; do
  CODE=$(curl -sS -o /tmp/prune-resp.json -w "%{http_code}" -X DELETE "${AUTH[@]}" \
    "${API}/${BASE}/packages/container/${ENC}/versions/${id}")
  if [ "$CODE" = "204" ] || [ "$CODE" = "200" ]; then
    echo "  deleted version ${id}"
  else
    echo "  WARN: cannot delete version ${id} (HTTP ${CODE}: $(jq -r '.message // ""' /tmp/prune-resp.json 2>/dev/null))"
  fi
done

exit 0
