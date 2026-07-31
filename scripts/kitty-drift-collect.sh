#!/bin/bash
# kitty-drift-collect.sh — wait for a kitty-drift-run to finish, then COMMIT its result.
#
# WHY THIS EXISTS. The 6 h drift run outlives the session that starts it. Without this, the series
# finishes onto disk and then waits for a human to notice — and the two things this box has actually
# done to measurements are lose them to a panic and leave them uncollected. The run already writes to
# a durable path rather than /tmp; this closes the other half, so the result lands whether or not
# anyone is watching.
#
# DELIBERATELY DOES NOT LAND. It commits on the current branch and stops. An unattended `/ship` six
# hours later would push a gate nobody read, and landing stays a decision with a person behind it.
#
# It also never fabricates a verdict: it copies whatever token the run emitted — including
# ABORTED-SUBJECT-DIED — because "the run died" is a result, and overwriting it with silence is how
# the first run came to report OK on a dead subject.
set -uo pipefail

REPO="${1:?usage: kitty-drift-collect.sh <repo> <tsv> <log>}"
TSV="${2:?}"; LOG="${3:?}"

cd "$REPO" || exit 1

# Wait for the producer to exit. Bounded: 8 h covers a 6 h run plus slack, and a bound that cannot
# expire is a wedged process rather than a patient one.
DEADLINE=$(( $(date +%s) + 8*3600 ))
while pgrep -f 'kitty-drift-run' >/dev/null 2>&1; do
  [ "$(date +%s)" -lt "$DEADLINE" ] || { echo "collect: deadline hit while run still alive" >&2; break; }
  sleep 60
done

VERDICT="$(grep -o 'verdict=[A-Z-]*' "$LOG" 2>/dev/null | tail -1)"
VERDICT="${VERDICT:-verdict=UNKNOWN-no-token}"
ROWS="$(($(wc -l < "$TSV" 2>/dev/null || echo 1) - 1))"

# Summarise first-vs-last so the commit body carries the number, not just the file. Guarded: a run
# that aborted early may have fewer than two usable rows, and an awk over that must not invent one.
SUMMARY="$(python3 - "$TSV" <<'PY' 2>/dev/null || echo "  (no fittable series)"
import csv,sys
try:
    rows=[r for r in csv.DictReader(open(sys.argv[1]),delimiter='\t') if r.get('elapsed_s','').isdigit()]
except Exception: sys.exit(1)
if len(rows)<2: sys.exit(1)
a,b=rows[0],rows[-1]; h=(int(b['elapsed_s'])-int(a['elapsed_s']))/3600
if h<=0: sys.exit(1)
for k in ('mem_mb','threads','ports'):
    try: d=float(b[k])-float(a[k]); print(f"  {k:8} {a[k]:>5} -> {b[k]:>5}  {d:+.0f} over {h:.2f}h = {d/h:+.1f}/hr")
    except Exception: pass
print(f"  samples={len(rows)} baseline={h:.2f}h")
PY
)"

git add "$TSV" "$LOG" 2>/dev/null
git diff --cached --quiet && { echo "collect: nothing to commit"; exit 0; }
git commit -q -F - <<EOF
data(kitty-drift): run 2 result — $VERDICT

Collected automatically when the run exited, so the series lands whether or not a
session was still watching. This box has lost one measurement to a panic and had
another die unattended at t+90m; a result that waits to be noticed is the same
failure with extra steps.

$SUMMARY

rows=$ROWS. The verdict token is copied from the run, never re-derived here — an
ABORTED-* is a RESULT (the run is void, kitty is not thereby convicted), and
silently replacing it would repeat the defect where a dead subject reported OK.

Committed, deliberately NOT landed: an unattended push six hours later is a gate
nobody read. Land it with the project-local /ship after reading the verdict.
EOF
echo "collect: committed — $VERDICT rows=$ROWS"
