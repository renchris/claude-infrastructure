#!/usr/bin/env bash
# unfired-brief-sweep.sh — THE BRIEF THAT WAS WRITTEN AND NEVER FIRED (backlog 4a11a0ac850a)
#
# THE FAILURE CLASS. A lead ANNOUNCED a recycle, WROTE the successor brief, and died before firing
# it. Succession was lost in SILENCE: no pane, no ledger row, no alarm, and the only artifact left
# behind was a file in /tmp that looks exactly like one that was fired successfully. Measured
# 2026-08-10 on session e5d3628d; the chain simply stopped.
#
# WHY THIS COULD NOT BE BUILT BEFORE. The question is "was a fire ever made FROM this brief", and
# until 2026-08-17 no row in ~/.claude/logs/handoffs.jsonl named a prompt-file path — 1005 rows,
# zero such field. Every sweep buildable over that ledger was a heuristic (guess from timing, from
# pane counts, from filename shape), i.e. an alarm over an attention budget with no exact answer
# underneath it. `prompt_file` (same commit as this file) is the linking primitive; this is the
# consumer it was added for. A brief whose path appears in no row was never fired. Exactly.
#
# ── THE TRAP THIS FILE IS MOSTLY ABOUT: AN ABSENCE TEST OVER A STORE WITH NO HISTORY ─────────────
# `prompt_file` did not exist yesterday. So on the day it lands, EVERY brief on disk appears in no
# row, and a naive sweep reports every one of them as a lost succession. Measured at authoring time:
# 98 briefs in /tmp spanning 2026-08-13..17 — 98 false positives on the first run, which is not a
# detector, it is an alarm that has trained its reader to ignore it before it has ever been right
# once (memory alarm-polarity-and-attention-budget).
#
# The floor is therefore derived FROM THE STORE, never from a hardcoded date — a date in a script is
# a perishable fact with no path to learn it changed (memory
# resident-policy-must-not-restate-perishable-facts):
#
#   EPOCH   the `ts` of the EARLIEST ledger row carrying a non-null prompt_file. Before that instant
#           the field did not exist, so its absence is blindness and proves nothing. No such row ⇒
#           the sweep is NOT ARMED and says so, reporting zero findings rather than 98 (memory
#           probe-that-acts-on-absence-must-confirm-presence: a negative that fires an ACTION must
#           first confirm the safe state is even observable).
#   TRIM    the ledger SELF-TRIMS at 1200 rows and writes a `class:"trim"` row naming
#           `window_starts_at`. A fire older than the surviving window has had its row DELETED, so
#           its brief reads unfired for a reason that is retention, not succession — the same
#           evidence-expiry that closed backlog 620f2fa354a6. The floor is raised to the oldest
#           surviving row's ts whenever that is later than EPOCH.
#   GRACE   a brief written 30 seconds ago has not been fired YET, which is not a fault. Briefs
#           younger than --grace (default 1800s) are held, not reported.
#
# So the floor is max(EPOCH, oldest-surviving-ts) and the window is [floor, now-grace]. A brief
# outside it is UNKNOWABLE and is counted separately from CLEAN — an unknown reported as clean is
# the same lie as an unknown reported as a fault.
#
# Usage:
#   unfired-brief-sweep.sh [--briefs GLOBDIR] [--ledger FILE] [--grace SECONDS] [--json]
# Exit: 0 = swept (findings or not; a finding is DATA, not an error — memory
#       null-result-must-not-use-the-error-channel), 2 = usage/precondition failure.
set -uo pipefail

BRIEF_DIR="${CC_BRIEF_DIR:-/tmp}"
LEDGER="${CC_HANDOFF_LEDGER:-$HOME/.claude/logs/handoffs.jsonl}"
GRACE="${CC_BRIEF_GRACE_S:-1800}"
JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --briefs) BRIEF_DIR="${2:?--briefs needs a directory}"; shift 2 ;;
    --ledger) LEDGER="${2:?--ledger needs a path}";          shift 2 ;;
    --grace)  GRACE="${2:?--grace needs seconds}";           shift 2 ;;
    --json)   JSON=1; shift ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    *) printf 'unfired-brief-sweep: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "unfired-brief-sweep: jq is required" >&2; exit 2; }

# 🚨 THE TRAILING SLASH ON EVERY `find "$BRIEF_DIR/"` BELOW IS LOAD-BEARING, NOT STYLE.
# The default brief directory is /tmp, and on Darwin /tmp is a SYMLINK to /private/tmp. `find` does
# not traverse a symlinked start point unless it is forced to, so `find /tmp -maxdepth 1 -name
# 'fire-*.txt'` returns the symlink itself and NOTHING ELSE — measured here at authoring time: 0
# files, against 98 from the shell glob over the identical pattern. That is the worst failure this
# script has available to it: a detector whose finding set is silently, permanently empty reports
# "all clear" forever and is indistinguishable from a machine with nothing wrong. It was found by
# RUNNING the sweep against the real ledger, not by reading it. The suite pins the count against a
# glob control for exactly that reason — an instrument that can only return zero must be able to
# fail its own test.

# A MISSING LEDGER IS NOT AN EMPTY ONE. With no ledger there is no evidence either way, and
# reporting every brief as unfired off a store that does not exist is the loudest possible version
# of the blindness this file is built to refuse.
if [ ! -f "$LEDGER" ]; then
  if [ "$JSON" = 1 ]; then
    printf '{"verdict":"not-armed","reason":"no ledger at %s","findings":[]}\n' "$LEDGER"
  else
    printf 'unfired-brief-sweep: NOT ARMED — no ledger at %s; nothing is knowable, 0 reported\n' "$LEDGER"
  fi
  exit 0
fi

# EPOCH — the earliest row that carries the field at all. `select(.prompt_file != null)` also
# excludes rows where the key is ABSENT, which is the pre-primitive population by construction.
EPOCH="$(jq -rs '[.[] | select(.prompt_file != null) | .ts] | sort | first // empty' "$LEDGER" 2>/dev/null || true)"
OLDEST="$(head -1 "$LEDGER" 2>/dev/null | jq -r '.ts // empty' 2>/dev/null || true)"

if [ -z "$EPOCH" ]; then
  if [ "$JSON" = 1 ]; then
    printf '{"verdict":"not-armed","reason":"no ledger row carries prompt_file yet","findings":[]}\n'
  else
    printf 'unfired-brief-sweep: NOT ARMED — no ledger row carries prompt_file yet.\n'
    printf '  The linking primitive is landed but no fire has exercised it, so absence is blindness.\n'
    printf '  0 reported (there are briefs on disk; reporting them would be %s false positives).\n' \
      "$(find "$BRIEF_DIR/" -maxdepth 1 -name 'fire-*.txt' -type f 2>/dev/null | wc -l | tr -d ' ')"
  fi
  exit 0
fi

# The floor is the LATER of the two — whichever blindness bites harder.
FLOOR="$EPOCH"
if [ -n "$OLDEST" ] && [ "$OLDEST" \> "$FLOOR" ]; then FLOOR="$OLDEST"; fi

_epoch_s() { # ISO-8601 Z → unix seconds, or nothing
  [ -n "${1:-}" ] || return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null || true
}
FLOOR_S="$(_epoch_s "$FLOOR")"
[ -n "$FLOOR_S" ] || { echo "unfired-brief-sweep: could not parse floor timestamp '$FLOOR'" >&2; exit 2; }
NOW_S="$(date -u +%s)"
CUTOFF_S=$(( NOW_S - GRACE ))

# Every prompt_file the ledger has ever recorded, one per line. Read ONCE — a per-brief jq over a
# 1200-row file would fork the sweep's cost into the alarm's own overhead.
FIRED="$(jq -rs '[.[] | .prompt_file // empty] | unique | .[]' "$LEDGER" 2>/dev/null || true)"

n_clean=0 n_unfired=0 n_unknowable=0 n_held=0
findings=""

while IFS= read -r b; do
  [ -n "$b" ] || continue
  m_s="$(stat -f %m "$b" 2>/dev/null || stat -c %Y "$b" 2>/dev/null || true)"
  [ -n "$m_s" ] || continue
  if   [ "$m_s" -lt "$FLOOR_S" ];  then n_unknowable=$(( n_unknowable + 1 )); continue
  elif [ "$m_s" -gt "$CUTOFF_S" ]; then n_held=$(( n_held + 1 ));             continue
  fi
  # Exact match on the whole line — a substring test would let /tmp/fire-a.txt be "found" by a row
  # naming /tmp/fire-ab.txt, and the sweep's whole claim is that the answer is exact.
  #
  # A HERE-STRING, NOT A PIPE, AND THIS WAS A REAL BUG THE LAND GATE CAUGHT. `printf … | grep -q`
  # under `set -o pipefail` is the early-exit-consumer trap: grep -q exits the instant it matches,
  # SIGPIPEs printf, and pipefail then reports the PIPELINE as failed — so the condition reads
  # FALSE exactly when the brief WAS found. In this sweep that inverts the only output it has: a
  # clean, successfully-fired brief would be reported as a lost succession, on the match path,
  # every time. A here-string is not a pipeline, so there is no producer to signal and nothing to
  # invert.
  if grep -qxF -- "$b" <<<"$FIRED"; then
    n_clean=$(( n_clean + 1 ))
  else
    n_unfired=$(( n_unfired + 1 ))
    findings="${findings}${b}"$'\n'
  fi
done <<EOF
$(find "$BRIEF_DIR/" -maxdepth 1 -name 'fire-*.txt' -type f 2>/dev/null | sort)
EOF

if [ "$JSON" = 1 ]; then
  printf '%s' "$findings" | jq -Rs --arg fl "$FLOOR" --arg ep "$EPOCH" \
    --argjson c "$n_clean" --argjson u "$n_unfired" --argjson k "$n_unknowable" --argjson h "$n_held" \
    '{verdict:"swept", epoch:$ep, floor:$fl,
      counts:{clean:$c, unfired:$u, unknowable_pre_floor:$k, held_in_grace:$h},
      findings:(split("\n")|map(select(length>0)))}'
else
  printf 'unfired-brief-sweep: floor=%s (epoch=%s)\n' "$FLOOR" "$EPOCH"
  # EVERY STRATUM IS NAMED. A bare "0 unfired" over a population where most rows were excluded reads
  # as all-clear (memory zero-claim-must-name-its-excluded-strata).
  printf '  %d clean · %d UNFIRED · %d unknowable (pre-floor) · %d held (younger than %ss grace)\n' \
    "$n_clean" "$n_unfired" "$n_unknowable" "$n_held" "$GRACE"
  if [ "$n_unfired" -gt 0 ]; then
    printf '  briefs written inside the observable window that no fire row names:\n'
    printf '%s' "$findings" | sed 's/^/    /'
  fi
fi
exit 0
