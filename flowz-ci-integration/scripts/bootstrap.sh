#!/usr/bin/env bash
# Pull the pinned flowz toolchain from GHCR (oras) and install it on PATH.
# Everything comes from the one package ghcr.io/flowzhq/flowz-cli:
#   flowz-ci-<FLOWZ_CI_VERSION>-linux-amd64   layer flowz-ci.gz (the orchestrator)
#   <SCANNER_VERSION>-linux-amd64             layer flowz.gz    (flowz, analyzer embedded)
#
# Inputs via env (set by action.yml):
#   REGISTRY_USER / REGISTRY_TOKEN  — the read:packages token Flowz issued
#                                     (GHCR ignores the username for a PAT)
#   FLOWZ_CI_VERSION                — flowz-ci version, vX.Y.Z
#   SCANNER_VERSION                 — flowz version, vX.Y.Z (>= v0.5.0)
#   DRY_RUN                         — "true" skips the flowz pull (a dry-run
#                                     never invokes it)
#
# GitHub-hosted linux/amd64 runners only for now — binary selection is hardcoded.
set -euo pipefail

err()  { echo -e "\033[0;31m[bootstrap]\033[0m $*" >&2; }
info() { echo -e "\033[0;34m[bootstrap]\033[0m $*" >&2; }

PACKAGE=${PACKAGE:-ghcr.io/flowzhq/flowz-cli}
REGISTRY=${PACKAGE%%/*}
BIN_DIR=${BIN_DIR:-"$HOME/.local/bin"}
PLATFORM=linux-amd64
mkdir -p "$BIN_DIR"

command -v oras >/dev/null 2>&1 || { err "oras not found (action.yml installs it via oras-project/setup-oras)"; exit 1; }
: "${REGISTRY_TOKEN:?REGISTRY_TOKEN is required (the read:packages token Flowz issued you)}"

# version <name> <value> — vX.Y.Z[-pre]; a bare X.Y.Z gets its v. No `latest`:
# in this package that tag is the flowz CLI's release metadata, not a binary.
version() {
  local v="$2"
  case "$v" in [0-9]*) v="v$v" ;; esac
  [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] \
    || { err "$1 must be a version like v1.2.3, got '$2'"; exit 1; }
  printf '%s' "$v"
}

# The login lives in a throwaway registry config, never ~/.docker/config.json
# (self-hosted runners keep it between jobs).
REGCFG="$(mktemp -d "${RUNNER_TEMP:-/tmp}/flowz-oras.XXXXXX")"
trap 'rm -rf "$REGCFG"' EXIT
printf '%s' "$REGISTRY_TOKEN" | oras login "$REGISTRY" -u "${REGISTRY_USER:-flowz-dp}" \
  --password-stdin --registry-config "$REGCFG/config.json" >/dev/null
info "logged in to $REGISTRY"

# pull_binary <tag> <layer> <install-name> — each tag holds one gzipped binary.
pull_binary() {
  local ref="$PACKAGE:$1" layer="$2" name="$3" tmp
  tmp="$(mktemp -d "${RUNNER_TEMP:-/tmp}/flowz-pull.XXXXXX")"
  info "oras pull $ref"
  oras pull --registry-config "$REGCFG/config.json" -o "$tmp" "$ref" >/dev/null \
    || { err "oras pull $ref failed — check the version exists and your token reads $PACKAGE"; exit 1; }
  [ -f "$tmp/$layer" ] || { err "no $layer in $ref"; ls -la "$tmp" >&2; exit 1; }
  gzip -dc "$tmp/$layer" > "$tmp/bin"
  install -m 0755 "$tmp/bin" "$BIN_DIR/$name"
  rm -rf "$tmp"
  info "installed $name ← $1"
}

FLOWZ_CI_VERSION="$(version flowz-ci-version "${FLOWZ_CI_VERSION:-}")"
pull_binary "flowz-ci-$FLOWZ_CI_VERSION-$PLATFORM" flowz-ci.gz flowz-ci

if [ "${DRY_RUN:-false}" = "true" ]; then
  info "dry-run: skipping the flowz pull"
else
  [ -n "${SCANNER_VERSION:-}" ] || { err "scanner-version is required for real runs — pin the flowz version (>= v0.5.0)"; exit 1; }
  SCANNER_VERSION="$(version scanner-version "$SCANNER_VERSION")"
  pull_binary "$SCANNER_VERSION-$PLATFORM" flowz.gz flowz
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$BIN_DIR" >> "$GITHUB_PATH"
  info "$BIN_DIR added to GITHUB_PATH"
fi
