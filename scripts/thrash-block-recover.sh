#!/usr/bin/env bash
# thrash-block-recover.sh — release backlog items that reap's rule B blocked on a DISPATCHER
# SELF-RELEASE, i.e. on evidence about the machine that was recorded as evidence about the item.
#
# ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────────
# cc-backlog's reap rule B blocks an item after MAX_THRASH fast claim→reopen pairs. cc-dispatch
# takes the claim BEFORE it fires and rolls that claim back whenever it cannot start — a refused
# fire (capacity gate rc 9, whose own text is "Shed load first … then re-fire"), a brief that failed
# to compose, a worktree that could not be provisioned. Those write the identical ledger shape while
# no worker has been anywhere near the item.
#
# `blocked` is the OPERATOR-ONLY state and cc-dispatch excludes it from the wave by construction, so
# each such block removed real work from the autonomous queue permanently. Measured on the live store
# 2026-08-07: 228 items, 64% of everything blocked; 182 of them had never held a claim for even the
# 90 s window. bin/cc-backlog now carries `reopen --self-release` so this cannot recur (see
# SELF-RELEASE in its header), but the flag is a PROPERTY OF NEW RECORDS — the ledger is append-only
# and the historical rows cannot acquire it. This script is the one-time repair of those rows.
#
# ── HOW IT DECIDES, AND WHERE IT IS DELIBERATELY WIDER THAN THE LIVE RULE ────────────────────────
# reap's live predicate is EVIDENCE-ONLY: it skips a pair only if the reopen positively asserts
# `selfRelease`. It must be, because guessing would suppress the one shape rule B exists to see.
#
# This script cannot use that predicate — by construction no historical row carries the flag — so it
# adds an authorship test, and that widening is the whole reason it is a separate, dry-run-by-default,
# one-shot script rather than a change to reap. A pair is treated as a self-release when the reopen
#   (a) asserts selfRelease, or
#   (b) names the SAME identity as the claim it closes (cc-dispatch reopens --by "$SID"), or
#   (c) names NO identity at all (the pre---by dispatcher, before 2026-07-19).
# Anything else — a reopen naming a DIFFERENT, non-empty identity — is worker-attributable, and any
# single one of those HOLDS the item.
#
# The widening is grounded, not assumed. Over the whole live ledger the same day: 691 fast pairs
# same-author vs 14 different-author, and all 14 of those were anonymous (b) shapes whose trails were
# read by hand and are the pre---by dispatcher. Two of them (fdc101e8b0c7, 53a1cb0441c9) were blocked
# as "the worker cannot land" and then COMPLETED — 53a1cb0441c9 within seven minutes of its next
# claim, which is the cleanest available refutation of the verdict this script reverses.
#
# ── SAFETY ───────────────────────────────────────────────────────────────────────────────────────
#   · DRY-RUN BY DEFAULT. --apply is required to write anything.
#   · It only ever touches an item whose LATEST event is a rule-B block authored by cc-backlog-reap.
#     A human block, a wedged-worker block, an operator `needs` step and a done item are all
#     structurally out of reach — the filter is the last record, not a text search.
#   · It unblocks and nothing else. The item returns to `open`, where cc-dispatch decides it under
#     the same ceiling, capacity gate and premise check as any other open item. Releasing 200 items
#     does not mean running 200 workers.
#   · --max bounds a single run (default 400); exceeding it is a refusal, not a truncation.
#   · Every action prints the id and the derived counts, so the run is its own audit record.
set -uo pipefail

BACKLOG="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
CC_BACKLOG_BIN="${CC_BACKLOG_BIN:-$(command -v cc-backlog || echo "$HOME/.claude/bin/cc-backlog")}"
WINDOW="${CC_BACKLOG_THRASH_WINDOW_S:-90}"
APPLY=0
MAX="${CC_RECOVER_MAX:-400}"

usage() {
  cat <<'EOF'
usage: thrash-block-recover.sh [--apply] [--max N]

  (default)   dry run — classify every rule-B thrash block and print the verdicts
  --apply     unblock the RECOVER set (writes via cc-backlog unblock)
  --max N     refuse to act on more than N items in one run (default 400)

env: CC_BACKLOG_FILE, CC_BACKLOG_BIN, CC_BACKLOG_THRASH_WINDOW_S
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --max)   MAX="${2:-}"; shift 2 || shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'thrash-block-recover: unknown arg %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MAX" in ''|*[!0-9]*) printf 'thrash-block-recover: --max must be a non-negative integer\n' >&2; exit 2 ;; esac

if [ ! -s "$BACKLOG" ]; then
  printf 'thrash-block-recover: ledger %s is absent or empty — nothing to do\n' "$BACKLOG" >&2
  exit 0
fi
command -v jq >/dev/null || { printf 'thrash-block-recover: jq is required\n' >&2; exit 2; }

# ── the derivation ───────────────────────────────────────────────────────────────────────────────
# Emits one TSV row per rule-B-blocked item: <id> <verdict> <selfRelPairs> <workerPairs> <longClaims>
# `longClaims` = claims that survived longer than the thrash window, i.e. positive evidence that a
# worker actually engaged the item at some point. It does NOT decide the verdict (a worker engaging
# once says nothing about a later refused fire) but it is the number a reader wants, so it is shown.
#
# Malformed lines are DROPPED here rather than failing the run: the ledger's own contract is that a
# bad line is reported and never silently reinterpreted, and this tool is a reader — but an
# unparseable record cannot be classified either, so anything it belongs to falls through to the
# default verdict, which is HOLD.
rows="$(jq -R 'fromjson? // empty' "$BACKLOG" | jq -s -r --argjson window "$WINDOW" '
  def isself($r): (($r.selfRelease // false) == true);
  group_by(.id)
  | map(
      (sort_by(.ts)) as $g
      | $g[-1] as $last
      | select($last.event == "block"
               and ($last.by // "") == "cc-backlog-reap"
               and (($last.needs // "") | startswith("persistent thrash")))
      | ($g[0:-1]) as $h
      | ([ range(0; ($h|length)) as $j
           | select($h[$j].event=="unblock" or $h[$j].event=="block") | $j ] | last // -1) as $cut
      | [ range(0; ($h|length)-1) as $i
          | select($i > $cut
                   and $h[$i].event=="claim" and $h[$i+1].event=="reopen"
                   and (($h[$i+1].ts|fromdateiso8601) - ($h[$i].ts|fromdateiso8601)) <= $window)
          | { self: ( isself($h[$i+1])
                      or (($h[$i+1].by // "") == "")
                      or (($h[$i+1].by // "") == ($h[$i].by // "")) ) } ] as $pairs
      | [ range(0; ($h|length)-1) as $i
          | select($h[$i].event=="claim"
                   and (($h[$i+1].ts|fromdateiso8601) - ($h[$i].ts|fromdateiso8601)) > $window) ] as $long
      | { id: $last.id,
          selfrel: ([$pairs[]|select(.self)]|length),
          worker:  ([$pairs[]|select(.self|not)]|length),
          long:    ($long|length) }
      | . + { verdict: (if .worker == 0 and .selfrel > 0 then "RECOVER" else "HOLD" end) }
    )
  | .[]
  | [.id, .verdict, (.selfrel|tostring), (.worker|tostring), (.long|tostring)]
  | @tsv
' 2>/dev/null)"

if [ -z "$rows" ]; then
  printf 'thrash-block-recover: no rule-B thrash blocks in %s — nothing to recover\n' "$BACKLOG"
  exit 0
fi

recover=0; hold=0
printf '%-14s %-8s %8s %8s %8s\n' ID VERDICT SELF-REL WORKER LONG-CLAIM
while IFS=$'\t' read -r id verdict selfrel worker long; do
  [ -n "$id" ] || continue
  printf '%-14s %-8s %8s %8s %8s\n' "$id" "$verdict" "$selfrel" "$worker" "$long"
  if [ "$verdict" = RECOVER ]; then recover=$((recover + 1)); else hold=$((hold + 1)); fi
done <<< "$rows"

printf '\nthrash-block-recover: %s RECOVER · %s HOLD (window %ss, ledger %s)\n' \
  "$recover" "$hold" "$WINDOW" "$BACKLOG"

if [ "$recover" -gt "$MAX" ]; then
  printf 'thrash-block-recover: REFUSED — %s items exceeds --max %s. This bound is a refusal and not\n' "$recover" "$MAX" >&2
  printf '  a truncation on purpose: a partial release would leave the store in a state no later run\n' >&2
  printf '  can tell apart from a completed one. Raise it deliberately:  --max %s\n' "$recover" >&2
  exit 3
fi

if [ "$APPLY" -ne 1 ]; then
  printf 'thrash-block-recover: DRY RUN — nothing written. Apply with:  %s --apply\n' "$0"
  exit 0
fi
[ "$recover" -gt 0 ] || { printf 'thrash-block-recover: nothing to apply\n'; exit 0; }
[ -x "$CC_BACKLOG_BIN" ] || { printf 'thrash-block-recover: cc-backlog not executable at %s\n' "$CC_BACKLOG_BIN" >&2; exit 2; }

ok=0; failed=0
while IFS=$'\t' read -r id verdict _ _ _; do
  [ "$verdict" = RECOVER ] || continue
  if "$CC_BACKLOG_BIN" unblock "$id" >/dev/null 2>&1; then
    ok=$((ok + 1)); printf 'thrash-block-recover: UNBLOCK %s\n' "$id"
  else
    # Never `|| true`-silent: an unblock that failed leaves the item exactly where the false verdict
    # put it, and a run that reported success would be the same defect one layer up (memory:
    # claimed-outcome-vs-checked-outcome).
    failed=$((failed + 1)); printf 'thrash-block-recover: FAILED to unblock %s\n' "$id" >&2
  fi
done <<< "$rows"

printf 'thrash-block-recover: %s unblocked, %s failed\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
