# github-actions — Claude conventions guide

## 1. Project Overview

The **public** home for Flowz's GitHub Actions, one action per subfolder,
referenced as `uses: flowzhq/github-actions/<action-name>@<tag>`. It exists
because GitHub cannot resolve a `uses:` reference to a private repo from
another repo (even same-org), so the action *recipes* must be public — but the
recipes are deliberately thin: they pull private, pre-built binaries from the
one GHCR package `ghcr.io/flowzhq/flowz-cli` (gated by one classic
`read:packages` token per customer, minted on the shared `flowz-dp` machine
account, which has Read on that package only; no per-customer accounts) and
shell out to them. All real product logic
stays in the private engine repos: `flowzhq/flowz-app` (`flowz`, analyzer
embedded) and `flowzhq/flowz-ci-integration` (the `flowz-ci` orchestrator). See
ADR-001.

There is nothing to build here — it's YAML + bash + docs. No Makefile. The one
test, run after touching `write-license.sh`:
`bash flowz-ci-integration/scripts/write-license.test.sh`.

## 2. Layout

```txt
CLAUDE.md                 conventions (this file)
README.md                 repo overview + index of actions
docs/adr/                 decisions — 000-adr-process.md, README.md (index), NNN-*.md
<action-name>/            one subfolder per public action
  action.yml              the composite action recipe
  scripts/                bash glue the recipe runs (e.g. GHCR bootstrap)
  README.md               customer-facing usage docs for that action
```

Current actions: `flowz-ci-integration/` (recipe owned by the private
`flowzhq/flowz-ci-integration` repo — its ADR-007 documents the split).

## 3. Per-area conventions

### Adding a new public action

- New subfolder `<action-name>/` with `action.yml` + minimal customer-facing
  docs only (`README.md`: what it does, inputs/outputs table, a copy-paste
  usage example, version-pinning guidance). Bash glue under
  `<action-name>/scripts/`.
- The action must stay a **thin wrapper**: pull pre-built private binaries
  from GHCR and invoke them. If it needs a new *distribution mechanism* (not
  another oras pull), write an ADR here first.
- Keep every subfolder self-contained — `${{ github.action_path }}` resolves
  to the subfolder, so recipes must not reach into sibling folders.
- **Tagging:** tags are `vX.Y.Z` and cover the whole repo — cutting a tag for
  one action's change pins *all* actions at that state. Bump the patch/minor
  for recipe changes; customers reference `@vX.Y.Z`.
- If the recipe is owned by a private engine repo (as with
  `flowz-ci-integration`), changes land there first (with its ADR/task
  discipline) and are mirrored here in the same change set.

## 4. ADR process

Every significant decision (a new distribution mechanism, a new external
service, a load-bearing design choice) is one ADR at
`docs/adr/NNN-short-slug.md`, per `docs/adr/000-adr-process.md`:

- **Status:** Proposed | Accepted (YYYY-MM-DD) | Superseded by ADR-MMM
- **Context** / **Options considered** (≥2, honest pros/cons) / **Decision** /
  **Consequences**

Numbers are monotonic across the repo (never reused); `docs/adr/README.md`
indexes them. **Discipline-enforced, not CI-enforced** — the reviewer is the
gate.

## 5. Task workflow

This repo carries no `.claude/tasks/` bookkeeping or release plan — it is a
distribution shell, and its changes are usually one-file mirrors of work
planned and tracked in the owning private repo (see Known limitations). If it
ever grows work of its own beyond mirroring, adopt the workspace task
conventions then, not preemptively.

Changes to an **established** state of this repo still follow the workspace
rule: branch + PR into `main`, never commit straight to `main` (the initial
bootstrap commit is the one exception).

## 6. What NOT to do

- **Don't put internal/admin docs here.** No credential-minting runbooks, no
  customer onboarding internals, no links into private repos' `docs/adr/` or
  `.claude/` task tracking. This repo exposes the minimum necessary.
- **Don't put product logic in a recipe.** If an action's subfolder starts
  accumulating build steps or real logic, that's the signal it should be a
  private engine repo distributing a binary, with only a thin wrapper here.
- **Don't commit secrets or tokens** — recipes carry no credentials by design;
  customers pass theirs as action inputs from their own secrets.
- **Don't retag or delete published tags.** Customers pin them; a moved tag
  silently changes what runs in their CI.
- **Don't let a recipe drift from its owning private repo.** For
  `flowz-ci-integration`, the private repo's CI self-tests against this repo's
  `main` — keep the two in sync in the same change set.

## 7. Known limitations

- **Single action today.** The multi-action, subfolder-per-action structure
  exists but is unexercised beyond `flowz-ci-integration/`.
- **No task workflow / release plan** (see §5) — deliberate while the repo is
  a mirror target; revisit if it grows independent work.
- **No CI.** Nothing to build; shellcheck/lint of the mirrored bash runs in
  the owning private repo. A recipe typo would only surface in a consumer run.
- **Repo-wide tags** mean an unchanged action still gets "new" versions when a
  sibling action tags — acceptable at this scale.
