#!/bin/bash
# dod-probe.sh <arm default|lineage> <scenario unrelated|legit> <task-id> <rep> <config-dir>
# One run of the CC_DOD_LINEAGE_ONLY probe (wave 2, item 3). Same fixture, arm files and claude
# invocation as the F1 gate (run.sh, arm `full`); the two arms differ ONLY in CC_DOD_LINEAGE_ONLY,
# which decides what dod-persist.sh injects at SessionStart.
#
# Before the run, a private DoD store (WRAP_DOD_DIR) is seeded for the fixture's origin with ONE
# capture stamped with THIS fixture's toplevel and ANOTHER session's id — the shape a pooled or
# re-used worktree leaves behind:
#   unrelated  the capture is a different project's contract (the misdirection the flag removes;
#              measure/hooks.md §4: 7 of 8 sampled sessions got an unrelated contract)
#   legit      the capture is this fixture's own PLAN.md scope, written by an earlier session that
#              is not in this one's lineage (the continuation the flag can hide)
# default injects the capture as "THE CURRENT CONTRACT"; lineage injects a one-line pointer.
set -u
[ $# -eq 5 ] || { echo "usage: dod-probe.sh <default|lineage> <unrelated|legit> <task> <rep> <config-dir>" >&2; exit 2; }
ARM=$1; SCEN=$2; TASK=$3; REP=$4; CCD=$5
H=$(cd "$(dirname "$0")" && pwd)
G=${GATE_ROOT:-/private/tmp/tokeff-dodprobe}
case "$ARM" in default) LO=0 ;; lineage) LO=1 ;; *) echo "bad arm: $ARM" >&2; exit 2 ;; esac
case "$SCEN" in unrelated|legit) ;; *) echo "bad scenario: $SCEN" >&2; exit 2 ;; esac

RUN="$G/runs/$TASK/r$REP"
D="$G/dod/$TASK-r$REP"
rm -rf "$D"; mkdir -p "$D" "$RUN"
# dod-path.sh keys the store on remote.origin.url, which fixture.sh sets to the bare origin path, and
# stamps captures with `git rev-parse --show-toplevel`, which resolves /tmp to /private/tmp.
ORIGIN="$RUN/origin.git"
KEY=$(printf '%s' "$ORIGIN" | shasum | cut -c1-16)
TOP=$(cd "$RUN" && pwd -P)/fx
if [ "$SCEN" = unrelated ]; then
  SCOPE='Scope (frozen): a launch-video-grade hero for github.com/renchris/agent-context-sync replacing the SVG infographic as the first README element; frame 0 states the governing thought; rendered, verified frame by frame in both schemes, committed and published; diagrams below unchanged. Bridge: /tmp/hero-launch/HANDOFF-resume.md'
else
  SCOPE=$(grep -m1 '^Scope (frozen):' "$H/tasks/$TASK/fixture.sh")
  [ -n "$SCOPE" ] || { echo "no Scope line in $TASK fixture" >&2; exit 2; }
fi
{
  printf '# Durable frozen DoD — %s\n' "$TOP"
  printf '# producer: dod-persist.sh · consumers: wrap-ledger.sh, completion-assert.sh\n'
  printf '# INTEGRATE-only: each capture APPENDS below; history is never rewritten (a19 HOP A).\n\n'
  printf '## 2026-09-20T10:00:00Z (manual-set) · toplevel=%s · session=5f0c1d2e-0000-4000-8000-00000000d0d0\n' "$TOP"
  printf '%s\n\n' "$SCOPE"
} > "$D/repo-$KEY.md"
printf '%s\n' "$SCEN" > "$D/scenario"

WRAP_DOD_DIR="$D" CC_DOD_LINEAGE_ONLY="$LO" GATE_ROOT="$G" "$H/run.sh" full "$TASK" "$REP" "$CCD"
RC=$?
# run.sh records arm=full; overwrite with the probe arm so the aggregation can un-blind it, and keep
# the injected store beside the run for the record.
printf '%s\n' "$ARM" > "$RUN/out/arm"
printf '%s\n' "$SCEN" > "$RUN/out/scenario"
cp "$D/repo-$KEY.md" "$RUN/out/dod-store.md" 2>/dev/null || true
exit "$RC"
