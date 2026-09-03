#!/usr/bin/env bash
# Build the corpus, capture it, run every detector, route the residue, grade the
# lot. One command, because a gate that takes five is a gate nobody runs.
#
#   ./run.sh                        # default profile
#   ./run.sh reso-management-app    # per-app rule weighting
#
# Exits non-zero when score.py refuses the run -- a false positive on the clean
# control, a rule that was never graded against it, or a defect the queue cannot
# reach. That exit code is the point: it is what makes "every rule added must be
# re-run against the clean control before it ships" a fact rather than a habit.
set -euo pipefail

cd "$(dirname "$0")"
APP="${1:-default}"
OUT="${DR_CORPUS:-corpus/out}"
PY="${DR_PYTHON:-.venv/bin/python}"
[ -x "$PY" ] || PY=python3

# On a box whose pinned Chromium revision does not match the installed
# Playwright package, name the binary rather than letting `channel=` guess.
if [ -z "${DR_CHROMIUM_PATH:-}" ] && [ -x /opt/pw-browsers/chromium ]; then
  export DR_CHROMIUM_PATH=/opt/pw-browsers/chromium
fi

echo "== build";   "$PY" corpus/build_corpus.py "$OUT"
echo "== capture"; "$PY" capture.py "$OUT"
echo "== detect (dom)";    "$PY" detect_dom.py "$OUT"
echo "== detect (xcheck)"; "$PY" detect_xcheck.py "$OUT"
echo "== route [$APP]";    "$PY" route.py "$OUT" --app "$APP"
echo "== score";           "$PY" score.py "$OUT"
