#!/usr/bin/env bash
# phase.sh <model> <subdir> <sample> <effort>... — one sample of the 7 DEFECTIVE briefs per effort.
# Bash on purpose: zsh reads "$b:h" as a head modifier (the 09-22 invocation fault #2).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
model="$1" sub="$2" s="$3"; shift 3
cells=()
for e in "$@"; do for b in cp-01 cp-02 cp-04 cp-05 cp-06 cp-08 cp-09; do cells+=("${b}:${e}"); done; done
SWEEP_MODEL="$model" SWEEP_BIN="$HOME/.claude-280/node_modules/.bin/claude" \
  SWEEP_CONFIG_DIR="${ARM_CFG:-$HOME/.claude-quaternary}" SWEEP_PAR="${PAR:-3}" \
  "$here/run-arms.sh" "$here/runs/$sub/s$s" "${cells[@]}"   # ABSOLUTE out-dir (09-22 fault #1)
