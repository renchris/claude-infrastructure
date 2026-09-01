#!/usr/bin/env bash
# The whole pipeline, in the order the stages actually depend on each other.
#
# Nothing here is a CI gate except the false-positive budget, and that is
# deliberate: the deterministic layer scored 9/9 with zero control false
# positives and needs no API key, so it is the only thing worth failing a build
# on. The router's output is advisory triage. Taste stays human.
#
# Usage: ./run.sh [corpus-dir] [--app NAME]
# Env:   BENCH_CHROMIUM  path to a Chromium binary, when the pre-provisioned one
#                        is a different build than pip's playwright pins.
set -euo pipefail
cd "$(dirname "$0")"

CORPUS="${1:-corpus/out}"
shift || true
APP="default"
[[ "${1:-}" == "--app" ]] && APP="$2"

PY="python3"
[[ -x .venv/bin/python ]] && PY=.venv/bin/python

echo "=== 1. corpus ==============================================="
$PY corpus/build_corpus.py "$CORPUS"

echo; echo "=== 2. capture (screenshot + snapshot, one browser pass) ===="
$PY capture.py "$CORPUS" --dpr 1,1.5

echo; echo "=== 3. deterministic rules =================================="
$PY detect_dom.py "$CORPUS"

echo; echo "=== 4. DOM-vs-pixels cross-check ============================"
$PY detect_xcheck.py "$CORPUS" --x2

echo; echo "=== 5. abstention router (profile: $APP) ===================="
$PY route.py "$CORPUS" --app "$APP"

echo; echo "=== 6. false-positive budget — THE SHIP GATE ================"
$PY fp_budget.py "$CORPUS" --x2 --app "$APP"

echo; echo "=== 7. acceptance tests ====================================="
$PY test_pipeline.py "$CORPUS"
