# ADR-002 — `flowz-ci-integration` license input: a secret, written to a 0600 file

**Status:** Accepted (2026-10-13)

## Context

`flowz` is license-gated: every product command exits 77 unless `FLOWZ_LICENSE`
names a valid license file. A CI pipeline gets its own license file, so the
recipe must turn a repository secret into a file path for the run step without
leaking it.

GitHub masks secret values in logs, but documents that structured values such as
JSON are masked unreliably: a multi-line secret is registered line by line, so a
fragment printed alone (`{`, a key) may slip through or match unrelated output.

## Options considered

**A. Accept base64 or raw JSON; recommend base64 (chosen).** A license is a JSON
object, so raw content starts with `{`; base64 output never contains `{`. The
first non-space character decides, with no flag or guess. Pros: base64 is one
opaque line, masked exactly; a customer who stores the file as-is
(`gh secret set FLOWZ_LICENSE < license.json`) still works. Cons: two accepted
forms to document.

**B. Base64 only.** Pros: one form, best masking. Cons: storing the file as-is is
the obvious first move and would fail; the error can only say "re-encode it".

**C. Raw JSON only.** Pros: no encoding step. Cons: the masking weakness above,
with no way out.

**D. A path input pointing at a file the workflow writes itself.** Pros: no
handling in the recipe. Cons: every customer workflow grows a step that writes a
secret to disk, each with its own permissions and cleanup mistakes.

## Decision

Option A.

- Input `license`, from a secret. Skipped entirely on `dry-run`.
- The run step creates `mktemp "$RUNNER_TEMP/flowz-license.XXXXXX"` under
  `umask 077` (mode 0600). `scripts/write-license.sh` writes the content into
  it, decoded when base64, ignoring whitespace and a leading UTF-8 BOM, and
  checks it starts with `{`. The step exports `FLOWZ_LICENSE=<path>` within
  that step only, unsets the content variable before `flowz-ci` runs, and
  deletes the file on exit.
- Content that is neither JSON nor base64 JSON fails the step with the command
  that stores it correctly. A missing license on a real run warns and continues:
  `flowz` exits 77 and `flowz-ci` names the `license` input.

## Consequences

- One secret per pipeline (`FLOWZ_LICENSE`); the README's Secrets section shows
  the base64 command.
- The decoded license is never a masked value; nothing prints it (`flowz` reports
  only refusals), and it exists only as a 0600 file for one step.
- The exit trap removes the file when the step fails or is cancelled by a
  signal it can trap. The runner also empties `RUNNER_TEMP` at the start and end
  of every job, self-hosted included, so only a SIGKILL on cancel leaves the
  file, and only until that cleanup.
