#!/usr/bin/env bash
# run_bench.sh -- the whole perception pipeline over the corpus, in order, as one
# command.
#
# The order is not cosmetic. Each stage consumes the previous one's artifact, and
# two of the dependencies are the kind that fail silently if you get them wrong:
#
#   build   -> pages/            regenerate before capturing; a snapshot taken
#                                against an older page grades a different corpus
#   capture -> shots/ snapshots/ ONE browser pass, so the screenshot and the
#                                layout describe the same frame
#   dom     -> findings_dom.json
#   xcheck  -> findings_xcheck.json   MUST run before route: its absence is not
#                                neutral, it makes the router's queue grow
#   route   -> route-plan.json   the abstention router
#   score   -> recall, the arm that catches a rule going quiet
#   fp      -> the SHIP GATE, the arm that catches a rule going loud
#
# score and fp_budget are the two that carry exit codes, and they fail in
# opposite directions on purpose. A change that improves one at the other's
# expense is the failure mode neither alone can see.
#
# Env: PYTHON (default python3) · CORPUS (default corpus/out)
# Exit: 0 = 11/11 recall and zero control false positives · non-zero otherwise.
set -uo pipefail

cd "$(dirname "$0")" || exit 2
PY="${PYTHON:-python3}"
CORPUS="${CORPUS:-corpus/out}"
rc=0

step() { printf '\n\033[1m── %s ─────────────────────────────────────\033[0m\n' "$1"; }

step "build corpus"
"$PY" corpus/build_corpus.py "$CORPUS" || exit 2

step "capture (screenshot + layout snapshot, one pass)"
"$PY" capture.py "$CORPUS" || {
  echo "capture failed. It needs playwright and a chromium; everything below" >&2
  echo "reads its artifacts, so stopping here rather than grading a stale run." >&2
  exit 2
}

step "detect_dom"
"$PY" detect_dom.py "$CORPUS" || exit 2

step "detect_xcheck"
"$PY" detect_xcheck.py "$CORPUS" || exit 2

step "route (abstention router)"
"$PY" route.py "$CORPUS" || exit 2

step "score (recall against ground truth)"
"$PY" score.py "$CORPUS" || rc=1

step "fp_budget (SHIP GATE: zero on the control)"
"$PY" fp_budget.py "$CORPUS" || rc=1

step "verdict"
if [ "$rc" -eq 0 ]; then
  echo "✓ green — full recall on the reachable defects, zero control false positives"
else
  echo "✗ red — see the score and/or ship-gate sections above"
fi
exit "$rc"
