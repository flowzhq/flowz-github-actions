# flowzhq/github-actions

Public home for Flowz's GitHub Actions. Each action lives in its own subfolder
and is referenced as:

```yaml
uses: flowzhq/github-actions/<action-name>@<tag>
```

Tags (`vX.Y.Z`) cover the **whole repo** — a tag pins every action at that
state. Pin a tag in production; don't track `main`.

## Actions

| Action | What it does |
| --- | --- |
| [`flowz-ci-integration`](flowz-ci-integration/) | Regenerates Flowz FSG/eFSG/system-view artifacts on every PR in your repo and pushes them to your `.flowz-artifacts` repo. |

Each action's subfolder README is its usage documentation — inputs, outputs,
onboarding, and a copy-paste workflow example.

## What this repo is (and isn't)

These actions are **thin wrappers**: composite actions must live in a public
repo to be referenced from other repos, so the recipes live here — but they
only pull the private, pre-built Flowz binaries from GHCR (access controlled
by the `read:packages` token Flowz issues each customer) and invoke them. No product logic
lives in this repo; the engines stay in Flowz's private repositories.
