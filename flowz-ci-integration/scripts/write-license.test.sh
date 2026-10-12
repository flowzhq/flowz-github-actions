#!/usr/bin/env bash
# Tests for write-license.sh: bash flowz-ci-integration/scripts/write-license.test.sh
# Uses a fake license; never point it at a real one.
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/write-license.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
json='{"customer":"test","sig":"fake"}'
bom=$'\xef\xbb\xbf'
fails=0

# case <name> <input> <want: ok|error>
case_() {
  local out="$tmp/license" got
  rm -f "$out"
  if got="$(FLOWZ_LICENSE_INPUT="$2" bash "$script" "$out" 2>&1)"; then
    if [ "$3" = ok ] && [ "$(cat "$out")" = "$json" ]; then echo "ok   $1"; return; fi
  elif [ "$3" = error ] && [[ "$got" == ::error::* ]] && [ ! -s "$out" ]; then
    echo "ok   $1"; return
  fi
  echo "FAIL $1 (want $3; output: $got)"
  fails=$((fails + 1))
}

b64="$(printf '%s' "$json" | base64 -w0)"
case_ "raw JSON" "$json" ok
case_ "raw JSON, surrounding whitespace" $'\n  '"$json"$'\n' ok
case_ "raw JSON with a BOM" "$bom$json" ok
case_ "raw JSON, whitespace then a BOM" "  $bom$json" ok
case_ "base64" "$b64" ok
case_ "base64, wrapped at 76" "$(printf '%s' "$json" | base64 -w76)" ok
case_ "base64 with a trailing newline" "$b64"$'\n' ok
case_ "base64 of JSON with a BOM" "$(printf '%s' "$bom$json" | base64 -w0)" ok
case_ "garbage" "not a license" error
case_ "base64 of non-JSON" "$(printf 'hello' | base64 -w0)" error
case_ "a BOM alone" "$bom" error

[ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
