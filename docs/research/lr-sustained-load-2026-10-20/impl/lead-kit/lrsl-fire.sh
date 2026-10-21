#!/bin/bash
# usage: lrsl-fire.sh <WAVE> <SLOT> "<plan heading>" "<extra read-first text or ->"
# Builds /tmp/fire-lrsl-<wave>.txt from the template and fires it as a dispatched session.
set -u
WAVE=$1 SLOT=$2 HEADING=$3 EXTRA=${4:--}
[ "$EXTRA" = "-" ] && EXTRA=""
lw=$(printf '%s' "$WAVE" | tr '[:upper:]' '[:lower:]')
BR="lrsl-$lw"
OUT="/tmp/fire-lrsl-$lw.txt"
/usr/bin/python3 -I - "$WAVE" "$SLOT" "$BR" "$HEADING" "$EXTRA" "$OUT" "$(cd "$(dirname "$0")" && pwd)/brief-template.txt" <<'PY'
import sys
w, s, br, h, ex, out = sys.argv[1:7]
t = open(sys.argv[7]).read()
for k, v in (('@WAVE@', w), ('@SLOT@', s), ('@BRANCH@', br), ('@HEADING@', h), ('@EXTRA@', ex)):
    t = t.replace(k, v)
open(out, 'w').write(t)
PY
grep -q '@[A-Z]*@' "$OUT" && { echo "unfilled placeholder in $OUT"; exit 2; }
GOAL="Wave $WAVE of docs/plans/LR_SUSTAINED_LOAD_IMPL.md (section: $HEADING) is landed on origin/main and converged — proven by printing each Done check that section lists with its output (bats runs with their 1..N plan line and 0 not ok; unittest OK lines under a /tmp HOME), git ls-tree origin/main for the wave's paths, and git rev-list --count origin/main..HEAD = 0; owed Tier-L runs may be reported as owed instead of run; do not write files outside the wave's Phase 0 ownership row and do not type into, recover, move or signal any Claude session; full brief in the prompt above"
~/.claude/scripts/handoff-fire.sh --prompt-file "$OUT" --repo ~/Development/claude-infrastructure \
  --worktree "$BR" --notify-back 187 --account auto --split-right --goal "$GOAL" 2>&1 \
  | grep -v 'Updating files' | tail -14 | cut -c1-400
