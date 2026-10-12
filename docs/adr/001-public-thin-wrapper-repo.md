# ADR-001 — Public thin-wrapper repo for Flowz's GitHub Actions

**Status:** Accepted (2026-07-04) — the recipe now pulls one package,
`ghcr.io/flowzhq/flowz-cli` (both binaries), instead of the three named below

## Context

Flowz's CI integration is a **composite GitHub Action** whose recipe
(`action.yml` + a bash bootstrap script) lived at the root of the private
`flowzhq/flowz-ci-integration` repo. A real customer PR proved live what
GitHub documents: a `uses:` reference to an action in a **private repo cannot
be resolved from another repo**, even within the same org — the run fails with
"Unable to resolve action, repository not found". Composite actions referenced
externally must live in a public repo (or every caller needs a PAT-checkout
workaround).

The recipe files themselves contain **zero proprietary logic**: they install
`oras`, pull three already-gated private GHCR binary packages (`flowz-ci`,
`flowz-cli`, `fsg-enricher` — access controlled per customer via
`read:packages` tokens), and shell out to the pulled orchestrator binary. All
real IP is compiled into those private GHCR artifacts and lives in the private
engine repos.

We also expect more public actions over time, so the fix should be a durable
home, not a one-off.

## Options considered

**A. Make `flowzhq/flowz-ci-integration` public.** Pros: zero moves, the
existing `uses:` string starts working. Cons: exposes the Go orchestrator
source, internal ADRs, task tracking, and admin runbooks — exactly the split
(private engines, public glue) the distribution model is built on.

**B. GHCR-distributed docker-container action.** Publish the action as a
container image so nothing public hosts the recipe. Pros: recipe stays out of
any public repo. Cons: converts the action type composite → docker (linux-only
containers, container startup cost on every customer run), requires a brand-new
image build/publish pipeline to own, and buys nothing — the two files being
distributed contain no proprietary logic to hide.

**C. Customer-side PAT-checkout workaround.** Each customer checks out the
private action repo with a flowzhq-issued PAT, then `uses:` it by local path.
Pros: no new repo. Cons: extra credential + extra workflow steps for **every**
customer, a non-standard integration that reads as a hack, and the checkout PAT
would expose the whole private repo (source, internals) — worse than B.

**D. Public thin-wrapper repo, one subfolder per action (chosen).** A new
public `flowzhq/github-actions` repo holds only each action's `action.yml`,
its bash glue, and customer-facing docs; GitHub supports subdirectory action
references (`uses: flowzhq/github-actions/<action>@<tag>`). Pros: standard
`uses:` UX for customers, minimum-necessary exposure, a durable home for
future actions, no new build pipeline. Cons: the recipe now lives apart from
the engine repo that owns it — two repos to keep in sync when a recipe
changes.

## Decision

Option D. `flowzhq/github-actions` is the public home for all Flowz GitHub
Actions:

- One subfolder per action; the first is `flowz-ci-integration/` (named after
  its owning private repo for discoverability), holding `action.yml` +
  `scripts/bootstrap.sh` copied verbatim plus a customer-facing README.
- Customers reference `uses: flowzhq/github-actions/<action-name>@vX.Y.Z`.
- **Tags cover the whole repo** — one `vX.Y.Z` pins every action at that
  state.
- Only customer-facing content lives here; engines, internal docs, and
  credential-minting runbooks stay in the private repos. The GHCR
  `read:packages` token remains the access boundary for the binaries.

## Consequences

- The live customer-facing failure is fixed with the standard `uses:` UX and
  no new distribution pipeline.
- Recipe changes now touch two repos: the owning private repo (where the
  change is planned, reviewed, and shellchecked) and the mirrored copy here —
  keep them in the same change set. The private repo's CI self-tests its
  binary against this repo's `main` to catch drift.
- Anything committed here is public immediately — review for internal
  references before merging.
- The private repo's name no longer doubles as the action reference; its docs
  point here (its ADR-007 records the split on that side).
