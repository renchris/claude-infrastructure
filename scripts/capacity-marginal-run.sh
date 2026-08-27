#!/bin/bash
# capacity-marginal-run.sh — drive §6 of docs/research/marginal-load-per-active-session-2026-08-19.md
# to a verdict in ONE command, on the box, with no operator judgment in the loop.
#
# WHY THIS EXISTS (backlog 193ae8ddce72). `capacity-marginal.sh` is the instrument and it is done:
# 15/15 green, three controls each watched failing. What was NOT done is the RUN, and §6 specified
# it as a worksheet — two commands plus a judgment loop the operator was expected to execute:
#
#     "analyze is re-runnable over a growing file, so the honest protocol is: sample, analyze, and
#      extend the window until the verdict stops being NO-ATTRIBUTION *or* the refusal repeats with
#      the same term across several windows — which would itself be the finding."
#
# That is a program, and the repo's own Manual-Command Delivery rule says a hand-off must BE one:
# making the human the runtime is the defect. Every branch of that paragraph is mechanical — the
# stop criterion is "PASS, or the same failing term N times running" — so there is nothing here for
# a person to decide. This file is that paragraph, executable.
#
# ══ WHAT IT DOES ════════════════════════════════════════════════════════════════════════════════
# Round 1 samples CC_MARGRUN_FIRST_S (default 3600 — §6's hour, which is what buys n_eff = 60
# against C2's floor of 20). Each later round extends the SAME file by CC_MARGRUN_EXTEND_S and
# re-analyzes the accumulated window, because `analyze` is a function of the series, not of the
# round. It stops on exactly three conditions, all mechanical:
#
#   PASS             — all three controls passed. The coefficient is quotable. Exit 0.
#   SETTLED-REFUSAL  — the identical control signature refused CC_MARGRUN_SETTLE rounds running.
#                      §6 calls this out as itself the finding (the process-unit census is not the
#                      right instrument, and §7's thread-unit refinement becomes the next
#                      increment). Exit 1, naming the term that kept failing.
#   UNSETTLED        — CC_MARGRUN_MAX_S of wall clock elapsed with the signature still moving.
#                      Exit 1. Re-runnable: point --out at the same file and it extends it.
#
# ══ WHAT IT DELIBERATELY DOES NOT DO ════════════════════════════════════════════════════════════
# It computes NOTHING. Every verdict, every control and the coefficient itself come from
# `capacity-marginal.sh analyze` unmodified — this driver only decides WHEN to stop asking. A
# second implementation of the arithmetic is a second thing to keep true, and the whole point of
# the item is that the repo already had four numbers from instruments nobody controlled.
#
# It also never synthesises conditions. §6 is explicit — "do NOT synthesise levels by pausing the
# box" — so this sleeps and watches; it starts no sessions and kills none.
#
# ══ THE ARTIFACT ════════════════════════════════════════════════════════════════════════════════
# --artifact-dir writes three files, so the close can cite a path rather than a scrollback:
#   marginal.tsv       the raw series (also --out; re-runnable input)
#   marginal.txt       the final `analyze` text, verbatim
#   marginal.json      the final `analyze --json` line, plus a `run` object recording the box
#                      (uname/ncpu/host), the rounds, and the stop condition
# Provenance is in the artifact because a coefficient is a property of a BOX. This number measured
# on a 4-core Linux container is not the 10-core Darwin fleet's number, and nothing downstream can
# tell them apart once the value is separated from where it was taken.
#
# Usage:
#   capacity-marginal-run.sh [--out FILE] [--artifact-dir DIR] [--first-s N] [--extend-s N]
#                            [--interval-s N] [--max-s N] [--settle N] [--quiet]
#
# Exit: 0 MARGINAL (quotable) · 1 refusal (SETTLED-REFUSAL or UNSETTLED) · 2 usage · 3 NO-DATA.
#
# Seams (all read with an explicit default; none may be empty):
#   CC_MARGRUN_FIRST_S(3600)    first window, seconds — §6's hour
#   CC_MARGRUN_EXTEND_S(1800)   each later round's extension
#   CC_MARGRUN_INTERVAL_S(60)   sample spacing; must stay >= CC_MARG_TAU or n_eff caps out
#   CC_MARGRUN_MAX_S(14400)     total wall-clock cap across all rounds
#   CC_MARGRUN_SETTLE(3)        identical consecutive refusals that count as SETTLED
#   CC_MARGRUN_BIN              the capacity-marginal.sh to drive (default: sibling)
set -uo pipefail

CC_MARGRUN_FIRST_S="${CC_MARGRUN_FIRST_S:-3600}"
CC_MARGRUN_EXTEND_S="${CC_MARGRUN_EXTEND_S:-1800}"
CC_MARGRUN_INTERVAL_S="${CC_MARGRUN_INTERVAL_S:-60}"
CC_MARGRUN_MAX_S="${CC_MARGRUN_MAX_S:-14400}"
CC_MARGRUN_SETTLE="${CC_MARGRUN_SETTLE:-3}"
CC_MARGRUN_BIN="${CC_MARGRUN_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/capacity-marginal.sh}"

die() { printf 'capacity-marginal-run: %s\n' "$*" >&2; exit 2; }

OUT=""; ART=""; QUIET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)          OUT="${2:-}"; shift 2 ;;
    --artifact-dir) ART="${2:-}"; shift 2 ;;
    --first-s)      CC_MARGRUN_FIRST_S="${2:-}"; shift 2 ;;
    --extend-s)     CC_MARGRUN_EXTEND_S="${2:-}"; shift 2 ;;
    --interval-s)   CC_MARGRUN_INTERVAL_S="${2:-}"; shift 2 ;;
    --max-s)        CC_MARGRUN_MAX_S="${2:-}"; shift 2 ;;
    --settle)       CC_MARGRUN_SETTLE="${2:-}"; shift 2 ;;
    --quiet)        QUIET=1; shift ;;
    -h|--help)      sed -n '/^# Usage:/,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

for v in CC_MARGRUN_FIRST_S CC_MARGRUN_EXTEND_S CC_MARGRUN_INTERVAL_S CC_MARGRUN_MAX_S CC_MARGRUN_SETTLE; do
  case "${!v}" in ''|*[!0-9]*) die "$v must be a non-negative integer (got '${!v}')" ;; esac
done
[ "$CC_MARGRUN_INTERVAL_S" -ge 1 ] || die "--interval-s must be >= 1"
[ "$CC_MARGRUN_SETTLE" -ge 1 ]     || die "--settle must be >= 1"
[ "$CC_MARGRUN_EXTEND_S" -ge 1 ]   || die "--extend-s must be >= 1"
[ -x "$CC_MARGRUN_BIN" ] || [ -r "$CC_MARGRUN_BIN" ] || die "cannot read sampler '$CC_MARGRUN_BIN'"

if [ -n "$ART" ]; then
  mkdir -p "$ART" || die "cannot create artifact dir '$ART'"
  [ -n "$OUT" ] || OUT="$ART/marginal.tsv"
fi
[ -n "$OUT" ] || OUT="${TMPDIR:-/tmp}/capacity-marginal.tsv"

say() { [ -n "$QUIET" ] || printf 'capacity-marginal-run: %s\n' "$*" >&2; }

# The interval must not undercut C2. `analyze` counts n_eff = span/tau + 1, so sampling faster than
# tau buys rows that are not observations — exactly B3's defect, and the reason C2 was undecided
# there rather than refuting. Sampling faster is not an error (the rows are still valid data), but
# it is never what the caller meant, so it is said out loud rather than silently absorbed.
if [ "$CC_MARGRUN_INTERVAL_S" -lt "${CC_MARG_TAU:-60}" ]; then
  say "WARNING interval ${CC_MARGRUN_INTERVAL_S}s < tau ${CC_MARG_TAU:-60}s — extra rows are not extra INDEPENDENT observations; n_eff is span-bound, so this only costs ps(1) calls"
fi

# ── the box, recorded ───────────────────────────────────────────────────────────────────────────
# A marginal is a property of a machine. Captured up front so the artifact says which one, and so a
# run taken somewhere other than the 10-core Darwin fleet cannot be quoted as if it were.
BOX_UNAME="$(uname -srm 2>/dev/null || printf unknown)"
BOX_HOST="$(hostname 2>/dev/null || printf unknown)"
BOX_NCPU="$( { sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null; } | head -1)"
case "$BOX_NCPU" in ''|*[!0-9]*) BOX_NCPU=0 ;; esac

START="$(date +%s)"
ROUND=0; PREV_SIG=""; STREAK=0; STOP=""; RC=1
ANALYZE_TXT=""; ANALYZE_JSON=""

say "box: $BOX_HOST ($BOX_UNAME, ${BOX_NCPU} cores) -> $OUT"
say "protocol: first ${CC_MARGRUN_FIRST_S}s then +${CC_MARGRUN_EXTEND_S}s per round at ${CC_MARGRUN_INTERVAL_S}s, cap ${CC_MARGRUN_MAX_S}s, settle after ${CC_MARGRUN_SETTLE} identical refusals"

while :; do
  ROUND=$(( ROUND + 1 ))
  elapsed=$(( $(date +%s) - START ))
  remaining=$(( CC_MARGRUN_MAX_S - elapsed ))
  if [ "$remaining" -le 0 ]; then STOP="UNSETTLED"; break; fi

  window="$CC_MARGRUN_EXTEND_S"
  [ "$ROUND" -eq 1 ] && window="$CC_MARGRUN_FIRST_S"
  # Never overrun the cap: a round that cannot finish inside the budget is truncated to what is
  # left, so --max-s is a deadline rather than a suggestion the last round is free to ignore.
  [ "$window" -le "$remaining" ] || window="$remaining"

  say "round $ROUND: sampling ${window}s (elapsed ${elapsed}s of ${CC_MARGRUN_MAX_S}s)"
  # A round that samples nothing (exit 3) is not fatal on its own — the accumulated file may still
  # analyze — so the sample rc is deliberately not propagated here; `analyze` owns the NO-DATA call.
  "$CC_MARGRUN_BIN" sample --window-s "$window" --interval-s "$CC_MARGRUN_INTERVAL_S" --out "$OUT" ${QUIET:+--quiet}

  ANALYZE_TXT="$("$CC_MARGRUN_BIN" analyze --in "$OUT" 2>&1)"; arc=$?
  ANALYZE_JSON="$("$CC_MARGRUN_BIN" analyze --in "$OUT" --json 2>/dev/null)"

  if [ "$arc" -eq 3 ]; then STOP="NO-DATA"; RC=3; break; fi
  if [ "$arc" -eq 0 ]; then STOP="PASS"; RC=0; break; fi

  # The refusal SIGNATURE is which controls failed, never the withheld fit — a coefficient that
  # wobbles between refused windows is still not a measurement, and treating its digits as state
  # would make the stop criterion depend on a number the script is forbidden to report.
  sig="$(printf '%s' "$ANALYZE_JSON" | grep -oE '"c[123]_[a-z]+":(true|false)' | tr '\n' ' ')"
  [ -n "$sig" ] || sig="$(printf '%s\n' "$ANALYZE_TXT" | grep -oE 'C[123] [A-Z]+ +(PASS|FAIL)' | tr -s ' ' | tr '\n' ',')"
  say "round $ROUND: NO-ATTRIBUTION [$sig]"

  if [ "$sig" = "$PREV_SIG" ]; then STREAK=$(( STREAK + 1 )); else STREAK=1; PREV_SIG="$sig"; fi
  if [ "$STREAK" -ge "$CC_MARGRUN_SETTLE" ]; then STOP="SETTLED-REFUSAL"; RC=1; break; fi
done

[ -n "$STOP" ] || STOP="UNSETTLED"
ELAPSED=$(( $(date +%s) - START ))

printf '%s\n' "$ANALYZE_TXT"
printf 'RUN: %s after %d round(s), %ds wall, on %s (%s, %s cores)\n' \
  "$STOP" "$ROUND" "$ELAPSED" "$BOX_HOST" "$BOX_UNAME" "$BOX_NCPU"
case "$STOP" in
  PASS)            printf 'RUN: the coefficient above is quotable WITH its s.e. and this window. Update the citation sites per §6 and close backlog 193ae8ddce72.\n' ;;
  SETTLED-REFUSAL) printf 'RUN: the same control refused %d rounds running — §6 says that is itself the finding: the process-unit census is not the instrument, and §7 thread-unit is the next increment. Still NOTHING quotable.\n' "$CC_MARGRUN_SETTLE" ;;
  UNSETTLED)       printf 'RUN: cap reached with the signature still moving. Re-run with the same --out to extend this window; nothing is quotable yet.\n' ;;
  NO-DATA)         printf 'RUN: no analyzable rows. Check that %s can read the load average and run ps(1) on this box.\n' "$CC_MARGRUN_BIN" ;;
esac

if [ -n "$ART" ]; then
  printf '%s\n' "$ANALYZE_TXT" > "$ART/marginal.txt"
  { printf '%s\n' "${ANALYZE_JSON:-{\}}"
    printf '{"run":{"stop":"%s","rounds":%d,"elapsed_s":%d,"first_s":%d,"extend_s":%d,"interval_s":%d,"settle":%d,"host":"%s","uname":"%s","ncpu":%d,"tsv":"%s"}}\n' \
      "$STOP" "$ROUND" "$ELAPSED" "$CC_MARGRUN_FIRST_S" "$CC_MARGRUN_EXTEND_S" "$CC_MARGRUN_INTERVAL_S" \
      "$CC_MARGRUN_SETTLE" "$BOX_HOST" "$BOX_UNAME" "$BOX_NCPU" "$OUT"
  } > "$ART/marginal.json"
  say "artifact: $ART/{marginal.tsv,marginal.txt,marginal.json}"
fi

exit "$RC"
