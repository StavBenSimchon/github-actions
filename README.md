# github-actions

My own reusable GitHub Actions. Use them in any repo:

```yaml
uses: StavBenSimchon/github-actions/.github/actions/build-push-docker@main
```

## Actions

### `build-push-docker`

Builds a Docker image and pushes it to GHCR, then prunes old versions.

| input | default | what |
|---|---|---|
| `token` | — | `${{ github.token }}` (needs `packages: write`) |
| `cleanup-token` | `""` | optional PAT (`read:packages` + `delete:packages`) for pruning |
| `image-name` | repo name | image name under `ghcr.io/<owner>/` |
| `dockerfile` | `Dockerfile` | path to Dockerfile |
| `context` | `.` | build context |
| `target` | `""` | multi-stage target (e.g. `web`) |
| `extra-tags` | `""` | comma separated extra tags |
| `keep` | `3` | how many newest versions to keep |
| `registry` | `ghcr.io` | registry |

Tags pushed automatically: `sha-<short>`, `latest` (on default branch), `vX.Y.Z` + `X.Y.Z` (on git tags).

### `publish-helm`

If a `helm/` directory exists (containing `Chart.yaml`), packages the chart and
pushes it to `oci://ghcr.io/<owner>/<repo>/charts`. If there is no `helm/`
directory the action does nothing (safe to use in every repo).
Prunes old chart versions, same `keep` behavior.

| input | default | what |
|---|---|---|
| `token` | — | `${{ github.token }}` (needs `packages: write`) |
| `cleanup-token` | `""` | optional PAT for pruning |
| `chart-dir` | `helm` | directory with `Chart.yaml` |
| `keep` | `3` | how many newest chart versions to keep |
| `registry` | `ghcr.io` | registry |

## Usage example

```yaml
name: Publish to GHCR
on:
  push:
    branches: [main]
    tags: ["v*"]

permissions:
  contents: read
  packages: write

jobs:
  image:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: StavBenSimchon/github-actions/.github/actions/build-push-docker@main
        with:
          token: ${{ github.token }}
          cleanup-token: ${{ secrets.GHCR_CLEANUP_TOKEN }}   # optional
          keep: "3"

  helm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: StavBenSimchon/github-actions/.github/actions/publish-helm@main
        with:
          token: ${{ github.token }}
```

### `sync-upstream`

Merges an upstream repo's branch into this repo and pushes. No-op when already
up to date. Fails loudly on merge conflicts (and aborts, so your branch stays
clean).

| input | default | what |
|---|---|---|
| `token` | — | `${{ github.token }}` (needs `contents: write`) |
| `upstream-repo` | — | e.g. `themrsami/scribd-downloader` |
| `branch` | `main` | branch to sync |

Notes:
- Pushes made with `github.token` do **not** trigger other workflows (GitHub
  blocks that to prevent loops). Pass a PAT as `token` if the sync push should
  also run your publish CI.
- Use `actions/checkout` with `fetch-depth: 0` (the action also unshallows by
  itself, belt and suspenders).

```yaml
on:
  schedule:
    - cron: "0 6 * * 1"   # Mondays 06:00 UTC
  workflow_dispatch:

permissions:
  contents: write

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main
          fetch-depth: 0
      - uses: StavBenSimchon/github-actions/.github/actions/sync-upstream@main
        with:
          token: ${{ github.token }}
          upstream-repo: themrsami/scribd-downloader
          branch: main
```

## Notes

- **Pruning and user-owned packages**: `GITHUB_TOKEN` can delete versions of
  packages the workflow published, but for user-owned (not org) packages it may
  get 403. If you see `WARN: cannot delete`, create a classic PAT with
  `read:packages` + `delete:packages` and pass it as `cleanup-token`. Pruning
  is best-effort and never fails the build.
- **Helm** is preinstalled on `ubuntu-latest` runners.
