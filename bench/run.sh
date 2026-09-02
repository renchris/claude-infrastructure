#!/usr/bin/env bash
# The whole perception pipeline, in order, over the ground-truth corpus.
#
#   build -> capture -> SCREEN (deterministic + cross-check) -> ROUTE -> GATE
#
# The last two steps are the ones that decide anything. ROUTE says what a model
# is allowed to be asked; the GATE says whether the rules may ship at all, and it
# is the only step here that can exit non-zero.
#
# Usage:  ./run.sh [corpus-dir] [--app <name>]
set -euo pipefail
cd "$(dirname "$0")"

OUT="${1:-corpus/out}"; [[ "${1:-}" == --* ]] && OUT=corpus/out
APP=bench
for i in "$@"; do [[ "${PREV:-}" == --app ]] && APP="$i"; PREV="$i"; done

PY=python3
[[ -x .venv/bin/python ]] && PY=.venv/bin/python

echo "== 1. corpus"   ; $PY corpus/build_corpus.py "$OUT"
echo "== 2. capture"  ; $PY capture.py "$OUT" --dpr 1,1.5
# Output is captured rather than piped to head: a SIGPIPE from a truncating pager
# aborts the step under `set -o pipefail` and reads as a pipeline failure.
head3() { printf '%s\n' "$1" | awk 'NR<=3'; }

echo "== 3. screen"   ; head3 "$($PY detect_dom.py "$OUT")"
                         head3 "$($PY detect_xcheck.py "$OUT")"
echo "== 4. route"    ; $PY route.py "$OUT" --app "$APP"
echo "== 5. gate"     ; head3 "$($PY test_bench.py "$OUT" | tail -3)"
                         $PY fp_budget.py "$OUT"
