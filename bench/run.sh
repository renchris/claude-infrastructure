#!/usr/bin/env bash
# The whole perception pipeline, in the order the stages actually depend on each
# other. A plain CLI rather than an MCP server: an MCP tool CAN return image
# content, but image data is charged against MAX_MCP_OUTPUT_TOKENS and the
# maxResultSizeChars escape hatch explicitly has no effect on tools returning
# images -- so an MCP image tool has exactly one lever, a session-global env var.
# A CLI that writes a JSON findings file and a PNG, and lets the agent Read the
# PNG, chooses its own output resolution and stays inside the Read ladder by
# construction.
#
# Usage:  ./run.sh [corpus-dir] [profile]
# Env:    BENCH_CHROMIUM_EXECUTABLE  explicit browser path, for hosts where the
#                                    playwright `chromium` channel does not resolve
set -euo pipefail
cd "$(dirname "$0")"

OUT="${1:-corpus/out}"
PROFILE="${2:-bench-corpus}"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "1/5 build the ground-truth corpus"
python3 corpus/build_corpus.py "$OUT"

step "2/5 capture (one browser pass: screenshot + layout snapshot, same frame)"
python3 capture.py "$OUT"

step "3/5 detect_dom -- the deterministic rules, with their explicit INDETERMINATE"
python3 detect_dom.py "$OUT"

step "4/5 detect_xcheck -- measure the DISAGREEMENT, not either side"
python3 detect_xcheck.py "$OUT"

step "5/5 route -- the abstention router; what a model is asked, and what it is not"
python3 route.py "$OUT" --profile "$PROFILE"

# The gate runs LAST and its exit code is the script's. Every rule added must be
# re-run against the clean control before it ships, and the only version of that
# rule which survives contact with a deadline is one that fails a build.
step "GATE: false-positive budget against the clean control"
exec python3 fp_budget.py "$OUT"
