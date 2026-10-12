#!/usr/bin/env bash
# write-license.sh <out> — write the CI license held in $FLOWZ_LICENSE_INPUT to
# <out> (ADR-002). The input is the license JSON or base64 of it: base64 never
# contains "{", so the first character decides. Surrounding whitespace and a
# leading UTF-8 byte-order mark (Windows editors add one) are ignored, before
# and after decoding. Prints a GitHub ::error:: and exits 1 on anything else.
set -euo pipefail

out=${1:?usage: write-license.sh <out>}
bom=$'\xef\xbb\xbf'

# strip <text> — drop leading whitespace, a BOM, then whitespace again.
strip() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s#"$bom"}"
  printf '%s' "${s#"${s%%[![:space:]]*}"}"
}

license="$(strip "${FLOWZ_LICENSE_INPUT:-}")"
if [ "${license:0:1}" != "{" ]; then
  license="$(printf '%s' "$license" | tr -d ' \t\r\n' | base64 -d 2>/dev/null)" || license=""
  license="$(strip "$license")"
fi
if [ "${license:0:1}" != "{" ]; then
  echo "::error::the license input is neither JSON nor base64-encoded JSON — set the secret with: base64 -w0 license.json | gh secret set FLOWZ_LICENSE"
  exit 1
fi
printf '%s\n' "$license" > "$out"
