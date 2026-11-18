#!/usr/bin/env bash
# Package the chart in helm/ and push it to GHCR as an OCI chart, then prune old versions.
set -euo pipefail

CHART_DIR="${CHART_DIR:-helm}"

if [ ! -d "$CHART_DIR" ]; then
  echo "No '${CHART_DIR}' directory found — skipping helm publish."
  exit 0
fi

CHART_NAME=$(awk '/^name:/{print $2; exit}' "$CHART_DIR/Chart.yaml")
echo "Packaging helm chart '${CHART_NAME}' from '${CHART_DIR}'"

# OCI refs must be lowercase
REPO="${GITHUB_REPOSITORY,,}"
CHART_NAME="${CHART_NAME,,}"

OUT=$(mktemp -d)
helm package "$CHART_DIR" --destination "$OUT"

echo "$TOKEN" | helm registry login "$REGISTRY" -u "$GITHUB_ACTOR" --password-stdin

for pkg in "$OUT"/*.tgz; do
  echo "Pushing $(basename "$pkg") -> oci://${REGISTRY}/${REPO}/charts"
  helm push "$pkg" "oci://${REGISTRY}/${REPO}/charts"
done

# keep only the newest $KEEP chart versions
KEEP="$KEEP" TOKEN="$TOKEN" CLEANUP_TOKEN="$CLEANUP_TOKEN" \
  bash "${GITHUB_ACTION_PATH}/prune.sh" "${REPO}/charts/${CHART_NAME}"
