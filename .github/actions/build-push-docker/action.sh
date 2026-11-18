#!/usr/bin/env bash
# Build Docker image, push to registry, prune old versions.
set -euo pipefail

OWNER="${GITHUB_REPOSITORY%%/*}"
IMAGE_NAME="${IMAGE_NAME:-$(basename "$GITHUB_REPOSITORY")}"
IMAGE="${REGISTRY}/${OWNER}/${IMAGE_NAME}"
DEFAULT_BRANCH=$(jq -r '.repository.default_branch // "main"' "$GITHUB_EVENT_PATH")
SHORT_SHA="${GITHUB_SHA:0:7}"

echo "$TOKEN" | docker login "$REGISTRY" -u "$GITHUB_ACTOR" --password-stdin

TAGS=(-t "${IMAGE}:sha-${SHORT_SHA}")

if [ "${GITHUB_REF_TYPE}" = "tag" ]; then
  TAGS+=(-t "${IMAGE}:${GITHUB_REF_NAME}")
  TAGS+=(-t "${IMAGE}:${GITHUB_REF_NAME#v}")
fi

if [ "${GITHUB_REF_TYPE}" = "branch" ] && [ "${GITHUB_REF_NAME}" = "${DEFAULT_BRANCH}" ]; then
  TAGS+=(-t "${IMAGE}:latest")
fi

IFS=',' read -ra EXTRA <<< "${EXTRA_TAGS}"
for raw in "${EXTRA[@]}"; do
  tag="$(echo "$raw" | xargs)"
  if [ -n "$tag" ]; then
    TAGS+=(-t "${IMAGE}:${tag}")
  fi
done

BUILD=(-f "$DOCKERFILE")
if [ -n "$TARGET" ]; then
  BUILD+=(--target "$TARGET")
fi

echo "Building ${IMAGE} -> ${TAGS[*]}"
docker buildx build --push "${BUILD[@]}" "${TAGS[@]}" "$CONTEXT"
echo "Pushed ${IMAGE} (sha-${SHORT_SHA})"

# keep only the newest $KEEP versions
KEEP="$KEEP" TOKEN="$TOKEN" CLEANUP_TOKEN="$CLEANUP_TOKEN" \
  bash "${GITHUB_ACTION_PATH}/prune.sh" "${IMAGE}"
