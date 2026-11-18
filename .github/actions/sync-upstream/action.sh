#!/usr/bin/env bash
# Merge upstream branch into the current branch and push.
set -euo pipefail

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# shallow checkout breaks merge-base; get full history
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  git fetch --unshallow origin || true
fi

git remote remove upstream 2>/dev/null || true
git remote add upstream "https://github.com/${UPSTREAM_REPO}.git"
git fetch --no-tags upstream "${BRANCH}"

if git merge-base --is-ancestor "upstream/${BRANCH}" HEAD; then
  echo "Already up to date with ${UPSTREAM_REPO}@${BRANCH}. Nothing to do."
  exit 0
fi

BEHIND=$(git rev-list --count "HEAD..upstream/${BRANCH}")
AHEAD=$(git rev-list --count "upstream/${BRANCH}..HEAD")
echo "Local is ${AHEAD} commit(s) ahead, ${BEHIND} commit(s) behind ${UPSTREAM_REPO}@${BRANCH}"

if ! git merge "upstream/${BRANCH}" --no-edit -m "Sync with upstream ${UPSTREAM_REPO}@${BRANCH}"; then
  echo "::error::Merge conflict while syncing with ${UPSTREAM_REPO}@${BRANCH}. Resolve manually: git fetch upstream && git merge upstream/${BRANCH}"
  git merge --abort || true
  exit 1
fi

git push "https://x-access-token:${TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:${BRANCH}"
echo "Synced ${GITHUB_REPOSITORY}@${BRANCH} with ${UPSTREAM_REPO}@${BRANCH}"
