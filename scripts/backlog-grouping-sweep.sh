#!/usr/bin/env bash
# backlog-grouping-sweep.sh — THE CALLER for scripts/backlog-consolidation/.
#
# WHY THIS FILE EXISTS AT ALL. The consolidation tools worked and were invoked by nobody: `link.py`
# and `prune.py` moved this pile more than anything else ever has (113 links, 161 closes, 0 failures)
# from an UNTRACKED directory with no caller, one `git clean -f -d` from gone. Tracking them was half
# the fix; a tracked script with no caller is inert, which is the defect this repo keeps
# rediscovering. This is the other half.
#
# WHAT IT MEASURES, and why the number matters more than the row count. The pile is ~93-95% genuinely
# distinct work, so shrinking the ROW COUNT is not available. What is available is shrinking the
# SESSION COUNT: rows sharing a condition cost ONE dispatch, because cc-backlog's condition lease
# refuses live siblings and cc-dispatch admits one item per declared cluster (bin/cc-dispatch, the
# `_clusterSrc == "declared"` arm). So the health metric is UNGROUPED LIVE ROWS — rows that are
# one-session-each by default. 419 of 548 on 2026-08-12, before this ran.
#
# ALARM POLARITY: silent when healthy. It speaks only when the ungrouped count crosses the floor.
# A sweep line that printed every pass would be one the reader learns to skip, and the ungrouped
# count is normally boring by design (memory: alarm-polarity-and-attention-budget).
#
# IT FILES RATHER THAN PRINTS, for the reason this whole repo keeps relearning: a printed warning
# dies with the terminal that showed it, and the failure class here is a conclusion that never
# reaches an enforcing store. `--file` writes ONE condition-keyed row, so repeated runs UPDATE rather
# than mint — and that update only became real in the same commit as this file (cc-backlog's
# cmd_add UPDATE ARM; before it, a re-file of a known id was a silent rc-0 no-op and the escalation
# row stayed frozen at its first wording forever).
#
# WHY --apply IS NOT THE DEFAULT, and what would earn it. The classifier is a hand-written taxonomy
# over row headlines; it is right about ~97% of the store and its residue is meant to be read by a
# person. Writing is append-only and asserts its own conservation, but it is still a WRITE to the
# fleet's live ledger while every other arm here is a pure read. The flip criterion is the same one
# the mechanical fold used: when `grouping_residue` has been stable across a run of sweeps and no run
# has reported `conservation=FAILED`, set CC_GROUPING_APPLY=1 here. Never flip past a FAILED.
#
# Usage:
#   backlog-grouping-sweep.sh                report the census; silent unless the floor is crossed
#   backlog-grouping-sweep.sh --assert       exit 1 if the floor is crossed (for a gate)
#   backlog-grouping-sweep.sh --file         file/update ONE condition-keyed row when crossed
#   backlog-grouping-sweep.sh --apply        write the links (group.py --apply → link.py --run)
#   --floor N                                default 50 (the W2 DoD), or CC_GROUPING_FLOOR
#
# EXIT CODES — three, and the third is why this file was edited (backlog 70cc9f44040f):
#   0  measured: under the floor, or over it and reported/filed
#   1  --assert only: the floor is crossed
#   2  COULD NOT MEASURE — bad usage, or THE ENGINE IS ABSENT (no python3 / no group.py)
#
# 🚨 THE ENGINE CHECK IS FAIL-CLOSED, AND IT WAS FAIL-OPEN FOR THIS MECHANISM'S ENTIRE DEPLOYED LIFE.
# The two guards below used to `exit 0` with one line to stderr — and autonomy-sweep calls this with
# `>/dev/null 2>&1`, so the line went nowhere and the rc read as a clean store. install.sh's
# deploy-class gap meant `scripts/backlog-consolidation/*.py` never reached the live layer at all
# (fixed in 6d96bf560), so the LIVE copy of this sweep answered "no grouper at … (fail-open)" with
# rc 0 on every 5-minute tick, forever: wired in, running on schedule, reporting success, folding
# nothing. The fail-open is the reason nobody found out — a fail-CLOSED check would have paged on
# the first tick. (Same shape as deploy-parity-assert.sh's want=0 arm, which measured exactly this.)
#
# WHY 2 AND NOT A NEW CODE OF ITS OWN. `--assert` is this script's stored falsifier
# (`--falsifier "bash … --assert --floor N"` below), and cc-premise's `run_falsifier` reads exit 0 as
# THE CONDITION IS GONE — so an absent engine did not merely fail to measure, it RETRACTED the
# escalation row and told the reader to close it. cc-premise already has a could-not-ask band for
# exactly this, `_FALSIFIER_UNASKABLE_RCS = {2, 124, 126, 127}`, which renders "UNVERIFIED, not
# confirmed". Minting a fourth code would land OUTSIDE that set and be rendered "NOT REFUTED — the
# probe declined to retract", i.e. a new non-verdict state that strands its own consumer. Picking the
# code the consumer already handles is what fixes the consumer in the same diff (memory:
# new-nonverdict-state-strands-its-consumers).
#
# THE PAGE IS DAMPED AND IT IS A FILING, NOT A PRINT — same two reasons as the floor row above: a
# printed warning dies with the terminal, and a producer that re-derives one conclusion every sweep
# re-sends it every sweep (page-damp.sh's own 570-pages-in-three-days forensics). It fires only in
# `--file` mode, so `--assert` stays a pure read: it is run as a probe under cc-premise's 20 s bound,
# and a probe that writes to the ledger it is being asked about is not a probe.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
GROUP="$HERE/backlog-consolidation/group.py"
CITE="$HERE/backlog-consolidation/citegraph.py"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$REPO/bin/cc-backlog}"
FLOOR="${CC_GROUPING_FLOOR:-50}"
MODE="report"

while [ $# -gt 0 ]; do
  case "$1" in
    --assert) MODE="assert"; shift ;;
    --file)   MODE="file"; shift ;;
    --apply)  MODE="apply"; shift ;;
    --floor)  FLOOR="${2:-50}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) printf 'backlog-grouping-sweep: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

# Send-damping, best-effort: an absent lib means UNDAMPED, never a lost page (page-damp.sh's own
# fail-open posture). Resolved through the tolerant ladder self-path-lint green-cases as (g).
for _c in "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib/page-damp.sh" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/page-damp.sh" \
          "$HOME/.claude/hooks/lib/page-damp.sh"; do
  # shellcheck disable=SC1090,SC1091
  [ -f "$_c" ] && { . "$_c" 2>/dev/null || true; break; }
done

# engine_absent <reason> — the fail-CLOSED exit. Says it on stderr for a human at a terminal, FILES
# it for the scheduled caller whose stderr goes to /dev/null, and exits 2 in every mode.
engine_absent() {
  printf 'backlog-grouping-sweep: %s — CANNOT MEASURE (fail-closed, rc 2)\n' "$1" >&2
  if [ "$MODE" = "file" ] && [ -x "$BACKLOG_BIN" ]; then
    # The fingerprint is the STATE, never a clock or a count — a fingerprint that moved every sweep
    # would look wired and damp nothing. Two engine states, so two fingerprints: a python3 that
    # disappears while the grouper is present is a different fact from a grouper the deploy classes
    # never carried, and a change between them is news that must not wait out the other's TTL.
    if ! command -v damp_should_send >/dev/null 2>&1 || damp_should_send "store:backlog" "GROUPING-ENGINE-ABSENT:$2"; then
      "$BACKLOG_BIN" add --project claude-infrastructure \
        --condition backlog-grouping-engine-absent \
        --title "the backlog grouping sweep cannot run: $1 — it is wired into autonomy-sweep on a 300 s tick and has been reporting success while folding nothing; every ungrouped row stays one dispatch slot until the engine is back" \
        --source backlog-grouping-sweep \
        --falsifier "command -v python3 >/dev/null 2>&1 && [ -f '$GROUP' ]" \
        --dod-ref "origin/main:docs/plans/BACKLOG_SELF_DRAINING_2026-08-12.md" >/dev/null 2>&1 \
        || {
          # The marker records an INTENT to send. The filing failed — most likely because the very
          # engine that is missing is the one cc-backlog needs — so drop it, or the whole TTL would
          # suppress the retry of a page nobody ever received.
          command -v damp_forget >/dev/null 2>&1 && damp_forget "store:backlog" "GROUPING-ENGINE-ABSENT:$2"
          printf 'backlog-grouping-sweep: could not file the engine-absent row\n' >&2
        }
    fi
  fi
  exit 2
}
command -v python3 >/dev/null 2>&1 || engine_absent "python3 missing" "no-python3"
[ -f "$GROUP" ] || engine_absent "no grouper at $GROUP" "no-grouper"
export CC_BACKLOG_BIN="$BACKLOG_BIN"

if [ "$MODE" = "apply" ]; then
  python3 "$GROUP" --apply; exit $?
fi

# ONE read of the census, reused by every arm — so the number a gate refuses on, the number a row is
# filed with, and the number a human reads are the same number. Two reads would be two populations.
CENSUS="$(python3 "$GROUP" --json 2>/dev/null)" || CENSUS=""
printf '%s' "$CENSUS" | jq -e 'type=="object"' >/dev/null 2>&1 || {
  # "I could not ask" must never read as "the answer was no": a grouper that failed to run leaves the
  # floor unjudged, and a sweep arm that reported healthy here would be the worse error.
  printf 'backlog-grouping-sweep: grouper produced no census — NOT judging the floor (fail-open)\n' >&2
  exit 0
}

# `ungrouped_before` — THE STORE AS IT IS, and this line was wrong first. `ungrouped_after` is the
# grouper's PROJECTION of what would remain once its links were written, so a floor keyed on it
# measures the fix rather than the defect: the first run of this sweep reported "6 ungrouped, nothing
# to consolidate" over a store holding 419 genuinely ungrouped rows. A gate whose input already
# assumes the remedy has been applied can never fire (memory: gate-must-not-key-on-its-own-signal).
UNGROUPED="$(printf '%s' "$CENSUS" | jq -r '.ungrouped_before // 0')"
REMAINING="$(printf '%s' "$CENSUS" | jq -r '.ungrouped_after // 0')"
LIVE="$(printf '%s' "$CENSUS"      | jq -r '.live // 0')"
WOULD="$(printf '%s' "$CENSUS"     | jq -r '.would_link // 0')"
EFFORTS="$(printf '%s' "$CENSUS"   | jq -r '.master_efforts_after // 0')"
case "$UNGROUPED" in ''|*[!0-9]*) UNGROUPED=0 ;; esac

if [ "$UNGROUPED" -le "$FLOOR" ]; then
  [ "$MODE" = "report" ] && printf 'backlog-grouping-sweep: %s ungrouped live row(s) of %s, floor %s · %s master effort(s) — nothing to consolidate.\n' \
    "$UNGROUPED" "$LIVE" "$FLOOR" "$EFFORTS"
  exit 0
fi

TITLE="$(printf '%s of %s live backlog rows carry no master effort (floor %s) — each is one dispatch slot by default; %s would fold into %s master effort(s), leaving %s for a human, via scripts/backlog-consolidation/group.py --apply' \
  "$UNGROUPED" "$LIVE" "$FLOOR" "$WOULD" "$EFFORTS" "$REMAINING")"

case "$MODE" in
  report)
    printf 'backlog-grouping-sweep: %s\n' "$TITLE"
    # The in-degree ranking says which rows to work FIRST inside a group — a row three siblings cite
    # is a root the others hang off. Printed here so the derived signal reaches a reader rather than
    # a JSON file nobody opens; failure is non-fatal, this arm is advisory.
    [ -f "$CITE" ] && python3 "$CITE" --top 5 2>/dev/null | sed 's/^/  /' || true
    printf '  Write them:  %s --apply\n' "$0"
    ;;
  assert)
    printf 'backlog-grouping-sweep: %s\n' "$TITLE" >&2
    exit 1
    ;;
  file)
    # Condition-keyed, so this is ONE row forever rather than one row per measurement — the exact
    # defect a detector must not commit while detecting it. The measurement lives in the TITLE, which
    # cmd_add's update arm now keeps current.
    [ -x "$BACKLOG_BIN" ] || { printf 'no cc-backlog at %s (fail-open)\n' "$BACKLOG_BIN" >&2; exit 0; }
    # THE ROW CARRIES ITS OWN RETRACTION, because a filed row with no way back out is an alarm that
    # can only ever accumulate. This arm fires when the floor is crossed and is SILENT when it is
    # not — so on its own it would leave a stale row open forever the moment the count went healthy,
    # and nobody would be looking at that row to notice.
    #
    # `--assert` is the probe because its polarity is already exactly right: rc 1 while the condition
    # HOLDS, rc 0 once the store is back under the floor — and cc-premise's contract is that exit 0
    # RETRACTS. Note that `cc-backlog add --falsifier` reaches a row only while CREATING it (on a
    # known id it is deliberately a no-op — see cmd_add's UPDATE ARM), so this attaches once, at first
    # filing, and `cc-backlog falsify` is the verb for correcting it later.
    "$BACKLOG_BIN" add --project claude-infrastructure \
      --condition backlog-ungrouped-over-floor \
      --title "$TITLE" \
      --source backlog-grouping-sweep \
      --falsifier "bash $HERE/backlog-grouping-sweep.sh --assert --floor $FLOOR" \
      --dod-ref "origin/main:docs/plans/BACKLOG_SELF_DRAINING_2026-08-12.md" >/dev/null 2>&1 \
      || { printf 'backlog-grouping-sweep: could not file the escalation row\n' >&2; exit 0; }
    ;;
esac
exit 0
