# ADR index & decision log

Process: [ADR-000](000-adr-process.md).

| ADR | Decision | Why (one line) | Status |
|---|---|---|---|
| [000](000-adr-process.md) | ADR process | durable record of *why* | Accepted (2026-07-04) |
| [001](001-public-thin-wrapper-repo.md) | Public thin-wrapper repo, one subfolder per action, repo-wide tags | cross-repo `uses:` only resolves public repos; the recipes carry no IP | Accepted (2026-07-04) |
| [002](002-license-input.md) | `flowz-ci-integration` `license` input: base64 or raw JSON from a secret, written to a 0600 file in `$RUNNER_TEMP` for the run step only | `flowz` reads a license file path; base64 masks exactly, raw JSON still works | Accepted (2026-10-13) |
