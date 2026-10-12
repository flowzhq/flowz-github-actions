# Flowz CI Integration

A composite GitHub Action that keeps your Flowz architecture artifacts fresh.
On every PR in your repo it:

1. checks whether source code changed (doc-only PRs are skipped),
2. scans the repo into FSG files (`flowz system build`),
3. pushes them to your artifacts repo under `repos/<repo>/fsg/` *(parallel, non-blocking)*,
4. enriches each FSG into an eFSG (the same build, with the analyzer embedded in `flowz`),
5. pushes those under `repos/<repo>/efsg/` *(parallel, non-blocking)*,
6. resolves the systems the repo belongs to (`.flowz.yml` ∪ `systems.yaml` on the
   artifacts repo's `config` branch),
7. recomputes each system's view (`flowz system build --from-efsg`), fed all member
   repos' eFSGs,
8. pushes `systems/<system>/system-view.json` *(blocking — this is the product output)*, and
9. posts (or updates in place) a PR comment linking each recomputed system to its
   [flowz-viewer](https://flowzhq.github.io/viewer/) architecture view *(non-blocking)*, and
10. notifies the artifacts repo (`repository_dispatch: efsg-updated`) that this
    branch's eFSG set changed, so its aggregator can recompute the system-views
    from the full set once every member has landed *(non-blocking)*.

Artifacts land on the branch `branch-<your-PR-branch>` of the artifacts repo; git
history is the artifact version history.

> **Why step 10:** a system-view spans repos, but each PR run only sees its own
> repo's fresh eFSG plus whatever peers had already landed — so when sibling repos
> push on the same branch afterwards, this run can't refresh the view. The artifacts
> repo is the only place that sees every member land, so it owns the recompute; this
> dispatch is how a run tells it to. Requires an `efsg-updated`-triggered workflow on
> the artifacts repo (see the `.flowz-artifacts` README).

The action is a thin wrapper: it pulls the private, pre-built Flowz binaries
(`flowz-ci` and `flowz`) from the one package `ghcr.io/flowzhq/flowz-cli` with
`oras`, using the `read:packages` token Flowz issues you, then runs them on your
runner. Your code
never leaves your CI; no Flowz server is in the loop.

## Usage

```yaml
# .github/workflows/flowz-ci.yml
name: flowz-ci

on:
  pull_request:
  workflow_dispatch: # manual rerun; combine with skip-change-check below if needed

# Rapid pushes to the same PR queue behind each other instead of racing on the
# same artifacts branch.
concurrency:
  group: flowz-ci-${{ github.head_ref }}
  cancel-in-progress: true

permissions:
  contents: read # artifacts-repo writes use the PAT, not GITHUB_TOKEN
  pull-requests: write # the PR architecture comment (posted with github.token)

jobs:
  flowz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # change detection needs the merge-base with the target branch

      - uses: flowzhq/github-actions/flowz-ci-integration@v0.4.0
        with:
          registry-token: ${{ secrets.FLOWZ_TOKEN }}
          artifacts-token: ${{ secrets.FLOWZ_ARTIFACTS_TOKEN }}
          license: ${{ secrets.FLOWZ_LICENSE }}
          # Pin the versions Flowz support gave you:
          flowz-ci-version: v0.6.0
          scanner-version: v0.5.0-rc.2
          # artifacts-repo: my-org/.flowz-artifacts   # default: <owner>/.flowz-artifacts
          # skip-change-check: "true"                 # e.g. for workflow_dispatch reruns
```

**Git identity.** As of `v0.1.1` the action sets a fallback committer identity
(`flowz-ci[bot]`) before running, so the artifacts push/rebase works on runners
that have no default identity — no per-repo `git config` step needed. A caller
that configures its own `user.name`/`user.email` first still wins.

**Version pinning.** Pin everything in production:

- the action itself — `flowzhq/github-actions/flowz-ci-integration@vX.Y.Z`
  (tags cover this whole repo); don't track `main`,
- `flowz-ci-version` / `scanner-version` — the versions Flowz support gives you.
  `flowz-ci-version` defaults to the one the action tag was tested with;
  `scanner-version` (the `flowz` CLI, at least `v0.5.0`) is required for real
  runs. `enricher-version` is ignored since `v0.4.0`: `flowz` embeds the
  analyzer.

## Onboarding

**1. Get your Flowz credentials.** Flowz issues you a classic `read:packages`
token, minted for you on its shared `flowz-dp` machine account, that reads
`ghcr.io/flowzhq/flowz-cli` only (the one package; it carries both binaries). You
need no GitHub account with Flowz. You also get a CI license file and the
versions to pin.

**2. Create the artifacts repo** (default name `.flowz-artifacts` in your org):

```bash
gh repo create my-org/.flowz-artifacts --private
cd .flowz-artifacts && git commit --allow-empty -m init && git push -u origin main
git checkout -b config
cat > systems.yaml <<'EOF'
version: 1
systems:
  my-system:
    repos: [my-repo]
EOF
git add systems.yaml && git commit -m "systems map" && git push -u origin config
```

`systems.yaml` maps systems to member repos — it is how one repo's PR pulls the
other members' eFSGs into the system view.

**3. Mint an artifacts PAT.** A your-org token with `contents: read/write` on the
artifacts repo only. This is separate from the flowzhq token by design: neither side
holds both credentials.

**4. Configure the source repo.** Set the token and license from step 1 and the
artifacts PAT from step 3 on the repo that will run the action (`gh secret set`
prompts for the value, so it stays out of shell history):

```bash
gh secret set FLOWZ_TOKEN            # the read:packages token Flowz gave you
gh secret set FLOWZ_ARTIFACTS_TOKEN  # your-org PAT, contents:write on .flowz-artifacts
base64 -w0 license.json | gh secret set FLOWZ_LICENSE
```

Then add the workflow above as `.github/workflows/flowz-ci.yml` and pin the
versions. Optionally add a `.flowz.yml` at your repo root to declare systems, a
scan path, or extra change-detection excludes.

## Secrets

| Secret | Input | What it is |
| --- | --- | --- |
| `FLOWZ_TOKEN` | `registry-token` | read:packages token Flowz issued you; reads `ghcr.io/flowzhq/flowz-cli` only |
| `FLOWZ_ARTIFACTS_TOKEN` | `artifacts-token` | your-org PAT, contents:write on the artifacts repo |
| `FLOWZ_LICENSE` | `license` | the CI license file Flowz issued you |

**The license.** `flowz` refuses to run without a valid license (exit 77), and
`flowz-ci` then fails with an error naming the `license` input. Store the file
base64-encoded:

```bash
base64 -w0 license.json | gh secret set FLOWZ_LICENSE   # macOS: base64 -i license.json
```

GitHub masks a secret's value in logs line by line and warns against structured
values such as JSON; base64 makes the secret one opaque line, masked exactly. Raw
JSON (`gh secret set FLOWZ_LICENSE < license.json`) is also accepted. The action
writes the decoded file to `$RUNNER_TEMP` with mode 0600, exports its path as
`FLOWZ_LICENSE` to the run step only, and deletes it when the step ends. A
`dry-run` needs no license.

## Requirements

- `actions/checkout` with `fetch-depth: 0` **before** the action (change
  detection needs the merge-base with the target branch).
- GitHub-hosted **linux/amd64** runners.
- The action installs `oras` itself (via `oras-project/setup-oras`) and uses it
  to pull the Flowz binaries from `ghcr.io` — your runner needs network access
  to `ghcr.io`, and your `registry-token` must read `ghcr.io/flowzhq/flowz-cli`.
- The artifacts repo and its `config` branch must exist before the first run
  (step 2 above) — the action errors with an onboarding message rather than
  auto-creating repos.
- `permissions: pull-requests: write` on the job (workflow above) lets the
  action post its PR architecture comment with the workflow's own
  `github.token` — no extra secret. Without it the comment fails with a
  warning; artifacts still land and the run stays green.

## Inputs & outputs

| Input | Required | Notes |
| --- | --- | --- |
| `registry-token` | yes | the read:packages token Flowz issued you (secret `FLOWZ_TOKEN`) |
| `registry-user` | no (`flowz-dp`) | GHCR ignores it for a token |
| `artifacts-token` | yes (real runs) | customer-org PAT, contents:write on the artifacts repo |
| `license` | yes (real runs) | the CI license file, base64 or raw JSON, from a secret (see Secrets) |
| `artifacts-repo` | no | default `<owner>/.flowz-artifacts` |
| `flowz-ci-version` | no (the version this action tag was tested with) | `vX.Y.Z` |
| `scanner-version` | yes (real runs) | the `flowz` version, `vX.Y.Z` ≥ `v0.5.0` |
| `enricher-version` | no | deprecated, ignored |
| `scan-path` | no (`.`) | scan root |
| `scan-mode` | no | override scan mode: `single` \| `monorepo` \| `components`; blank uses `.flowz.yml` (default `monorepo`). Requires `flowz-ci >= v0.5.0` |
| `skip-change-check` | no (`false`) | run even for doc-only changes |
| `dry-run` | no (`false`) | print the plan, execute nothing |
| `viewer-base-url` | no (`https://flowzhq.github.io/viewer`) | PR-comment link target; override for self-hosted viewers |
| `external-config-repo` | no | pull another repo's config files into the scan (owner/name or URL); they surface as ExternalFile nodes |
| `external-config-files` | no | repo-relative files from `external-config-repo` (comma/space separated) |
| `external-config-token` | no | read token (secret) for a private `external-config-repo`; blank for public |

Outputs: `skipped`, `systems` (comma-separated), `artifacts-branch`. A human summary
lands in the job's step summary.

## The artifacts-repo layout

```yml
# on branch-<pr-source-branch>
repos/<repo>/fsg/scan-<idx>-<name>.json.gz        # .flowz-empty for a repo with no Go code
repos/<repo>/efsg/scan-<idx>-<name>.efsg.json.gz
systems/<system>/system-view.json
# on the config branch
systems.yaml
```

Commits are additive (never force-pushed); concurrent PRs from different repos
rebase cleanly.
