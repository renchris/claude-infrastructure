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

# 🚨 PARSE PER LINE, NEVER SLURP — ONE BAD ROW USED TO DISARM THIS ENTIRE SWEEP (2026-09-09).
# Both reads below were `jq -rs`, which is SLURP: jq consumes the ledger as ONE document, so a
# single malformed line aborts the whole parse. With `2>/dev/null || true` underneath, EPOCH came
# back EMPTY and this script answered `not-armed — no ledger row carries prompt_file yet` over a
# fully armed ledger — measured end-to-end, a `swept` verdict became `not-armed` on appending one
# row. That is the state this file's own header refuses at the top ("a detector whose finding set
# is silently, permanently empty reports all-clear forever and is indistinguishable from a machine
# with nothing wrong"), and the producer that emitted such rows is fixed in the same series
# (handoff-fire.sh's jq-less fallback interpolated a filesystem path into JSON unescaped).
#
# THE PRODUCER FIX IS NOT ENOUGH, WHICH IS WHY THIS ARM EXISTS. `not-armed` is ALSO the correct
# answer for a young, pre-primitive ledger, so the two are indistinguishable to every consumer —
# fail-safe-default-mimics-the-healthy-state. This ledger has several writers and a truncated
# concurrent append or a full disk can malform a row with no bug anywhere; an alarm must not go
# quiet on input it cannot read. `fromjson? // empty` skips exactly the unreadable rows and keeps
# every readable one, and the count of what was skipped is SURFACED rather than swallowed: a
# malformed row may be a real fire, whose brief then appears in no row and is reported as a lost
# succession, so the number bounds this sweep's own false-positive rate for the reader.
#
# Read ONCE into a variable, preserving the original's cost note — a per-brief jq over a 1200-row
# file would fork the sweep's cost into the alarm's own overhead. ~250 B/row at the 1200-row
# retention bound is ~300 KB, which is a variable, not a problem.
ROWS="$(jq -R -c 'fromjson? // empty' "$LEDGER" 2>/dev/null || true)"
N_TOTAL="$(wc -l < "$LEDGER" 2>/dev/null | tr -d ' ')"; N_TOTAL="${N_TOTAL:-0}"
N_PARSED="$(printf '%s' "$ROWS" | grep -c '' 2>/dev/null || true)"; N_PARSED="${N_PARSED:-0}"
N_BAD=$(( N_TOTAL - N_PARSED )); [ "$N_BAD" -ge 0 ] || N_BAD=0

# EPOCH — the earliest row that carries the field at all. `select(.prompt_file != null)` also
# excludes rows where the key is ABSENT, which is the pre-primitive population by construction.
EPOCH="$(printf '%s\n' "$ROWS" | jq -rs '[.[] | select(.prompt_file != null) | .ts] | sort | first // empty' 2>/dev/null || true)"
# The oldest READABLE row, not literally line 1: with `head -1 | jq` a malformed first line made
# OLDEST empty and silently dropped the later of the two blindness floors.
OLDEST="$(printf '%s\n' "$ROWS" | jq -rs '[.[] | .ts // empty] | first // empty' 2>/dev/null || true)"

if [ -z "$EPOCH" ]; then
  # THE TWO REASONS ARE DIFFERENT FACTS AND GET DIFFERENT VERDICTS. `not-armed` says the primitive
  # is young — true, benign, self-clearing on the next fire. `ledger-unparseable` says the evidence
  # exists and could not be read — an event with a culprit, which nothing downstream could ever see
  # while both rendered the same string.
  if [ "$N_BAD" -gt 0 ]; then
    if [ "$JSON" = 1 ]; then
      printf '{"verdict":"ledger-unparseable","reason":"%s of %s ledger rows are not valid JSON and no readable row carries prompt_file","counts":{"malformed_rows":%s,"ledger_rows":%s},"findings":[]}\n' \
        "$N_BAD" "$N_TOTAL" "$N_BAD" "$N_TOTAL"
    else
      printf 'unfired-brief-sweep: LEDGER UNPARSEABLE — %s of %s rows are not valid JSON.\n' "$N_BAD" "$N_TOTAL"
      printf '  No READABLE row carries prompt_file, so this is not the young-ledger case: the\n'
      printf '  evidence may exist and cannot be read. 0 reported; fix %s, then re-run.\n' "$LEDGER"
    fi
    exit 0
  fi
  if [ "$JSON" = 1 ]; then
    printf '{"verdict":"not-armed","reason":"no ledger row carries prompt_file yet","counts":{"malformed_rows":0,"ledger_rows":%s},"findings":[]}\n' "$N_TOTAL"
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
FIRED="$(printf '%s\n' "$ROWS" | jq -rs '[.[] | .prompt_file // empty] | unique | .[]' 2>/dev/null || true)"

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
    --argjson mb "$N_BAD" --argjson lr "$N_TOTAL" \
    '{verdict:"swept", epoch:$ep, floor:$fl,
      counts:{clean:$c, unfired:$u, unknowable_pre_floor:$k, held_in_grace:$h,
              malformed_rows:$mb, ledger_rows:$lr},
      findings:(split("\n")|map(select(length>0)))}'
else
  printf 'unfired-brief-sweep: floor=%s (epoch=%s)\n' "$FLOOR" "$EPOCH"
  # A PARTIALLY unreadable ledger still sweeps — every readable row counts — but the skipped rows
  # bound this run's own false-positive rate, because a malformed row may be a real fire whose
  # brief then appears in no row and is reported below as a lost succession. Printed only when
  # non-zero: a line that renders "0 malformed" on every healthy run is one more row to scan for
  # no bits (alarm-polarity-and-attention-budget).
  if [ "$N_BAD" -gt 0 ]; then
    printf '  ⚠ %s of %s ledger rows are not valid JSON and were SKIPPED — any fire recorded in\n' "$N_BAD" "$N_TOTAL"
    printf '    one of them cannot be seen, so up to %s finding(s) below may be false.\n' "$N_BAD"
  fi
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
