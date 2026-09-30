#!/usr/bin/env bash
# Build dl-ek: a Swift EventKit CLI with an EMBEDDED Info.plist (so TCC has usage strings to show)
# and an ad-hoc signature with a stable identifier (so a TCC grant survives rebuilds of the same id).
# Output: ${DL_EK_OUT:-$HOME/.local/bin/dl-ek}. Re-runnable; prints the codesign verdict.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${DL_EK_OUT:-$HOME/.local/bin/dl-ek}"
mkdir -p "$(dirname "$out")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
swiftc -O -o "$tmp/dl-ek" "$here/main.swift" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$here/Info.plist"
codesign --force --sign - --identifier com.chrisren.dl-ek "$tmp/dl-ek"
mv -f "$tmp/dl-ek" "$out"
codesign --verify --verbose=1 "$out"
echo "built $out"
