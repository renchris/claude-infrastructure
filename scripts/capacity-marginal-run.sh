#!/usr/bin/env bash
# capacity-marginal-run.sh — §6 of docs/research/marginal-load-per-active-session-2026-08-19.md,
# run to a VERDICT by one command instead of by a human looping two.
#
# WHY THIS EXISTS. The instrument (`capacity-marginal.sh`) landed 2026-08-19 with its three
# controls proven able to fail; §6a discharged the citation ban off-box; and what was left of
# backlog `193ae8ddce72` was a PROTOCOL, written as prose, that nobody could hand to a machine:
#
#     "sample, analyze, and extend the window until the verdict stops being NO-ATTRIBUTION OR the
#      refusal repeats with the same term across several windows — which would itself be the
#      finding (the process-unit census is not the right instrument, and the thread-unit
#      refinement in §7 becomes the next increment rather than a nicety)."
#
# That paragraph contains a LOOP, a STOP RULE and an ADJUDICATION, and it was left for a person to
# execute at 1 h per iteration while remembering which term failed last time. A recipe a human has
# to interpret is a worksheet, and the interpreter is the defect (global CLAUDE.md § Manual-Command
# Delivery). This file is the interpreter.
#
# THE ADJUDICATION IS THE POINT, AND IT IS NOT "DID IT FAIL AGAIN". §6's stop rule says "the same
# TERM", and the terms are not interchangeable — two of the three controls can fail for a reason
# that is about the BOX and self-resolves, and for a reason that is about the INSTRUMENT and never
# will. Collapsing them to "C2 failed twice" would stop a run that was one window from deciding,
# or would report an instrument finding over a box that was merely asleep. So every refusal is
# reduced to a per-control REASON token, taken from the analyzer's own why-string:
#
#   INSTRUMENT — the census cannot do the job, and more hours cannot fix it:
#     C1:swing     tertile load/census ratios drift  → the x1.553 single-point-fit defect, live
#     C2:corr      the census does not track the load it apportions  → the "64% is our own
#                  automation" headline's cause of death, reproduced on real data
#     C2:constant  the census is flat across a moving load  → "the instrument, not the box"
#   CONDITION — the window has not seen enough box yet, and another window plausibly fixes it:
#     C1:span      load1 never moved 1.5x            → a quiet hour
#     C2:neff      n_eff below the floor             → "uninformative, not refuting"; n_eff grows
#                  with span, so this ALWAYS clears given enough wall clock (60 rows at 60 s ⇒ 60)
#     C3:flat      ACTIVE spans too few levels       → a lull; §6's remedy is to run ACROSS A
#                  DISPATCH WAVE, and explicitly NOT to synthesise levels by pausing the box
#     C3:blind     no row carries an ACTIVE count    → cc_sp_active is unmeasurable here
#
# A repeated signature containing ANY instrument term is §6's finding and exits 1. A repeated
# signature of condition terms only is NOT a finding about the census — it is a report about the
# hour you chose — so it keeps extending to the budget and then exits 3 naming the condition and
# the doc's own remedy. Reporting a quiet box as an instrument failure would be this wave's own
# original sin (an instrument that always answers) wearing the opposite sign.
#
# THE INVARIANT THIS FILE INHERITS AND MUST NOT BREAK. `analyze` withholds the fit on a refusal and
# never prints the string `VERDICT: MARGINAL`, so that a grep for a quotable number over a failed
# window returns nothing. A driver that summarised its own run could re-introduce exactly the
# leak — four values spanning 30x are in the archive because a number outlived the control that
# should have killed it. Every non-PASS path here therefore prints NO coefficient of its own, and
# `tests/capacity-marginal-run.bats` asserts it over each stop.
#
# RESUME IS FREE, AND IT IS THE PROTOCOL. `sample` APPENDS and `analyze` is a pure read, so the TSV
# is the run's whole state: interrupt this at any point and re-run the identical command, and the
# window continues rather than restarting. Point --out at a fresh file to start over.
#
# Usage:
#   capacity-marginal-run.sh [--out FILE] [--window-s N] [--interval-s N]
#                            [--max-windows K] [--repeat-stop M] [--quiet]
#
# Exit: 0 PASS — a coefficient cleared all three controls (the next steps are printed)
#       1 THE FINDING — an instrument term repeated across M windows; §7's thread unit is next
#       2 usage error
#       3 budget spent with the refusal still a CONDITION (or the sampler produced nothing)
#
# Seams (all read with an explicit default; every CC_MARG_* seam of the analyzer applies too):
#   CC_MARG_BIN          path to capacity-marginal.sh (default: this script's sibling)
#   CC_MARG_OUT          default --out, shared with the sampler so a resume needs no argument
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_MARG_BIN="${CC_MARG_BIN:-$HERE/capacity-marginal.sh}"
CC_MARG_OUT="${CC_MARG_OUT:-${TMPDIR:-/tmp}/capacity-marginal.tsv}"

ITEM=193ae8ddce72
DOC=docs/research/marginal-load-per-active-session-2026-08-19.md

die() { printf 'capacity-marginal-run: %s\n' "$*" >&2; exit 2; }
say() { [ -n "$QUIET" ] || printf '%s\n' "$*" >&2; }

# ── the reason token, taken from the analyzer's own why-string ───────────────────────────────────
# Matched on the analyzer's wording, not on a code it does not emit. That couples this file to
# `analyze`'s text — which is why the suite pins every branch against the REAL analyzer over a
# fixture, so a reworded why-string fails a test here instead of silently degrading every signature
# to `other` and turning the stop rule into "it failed again".
c1_token() {
  case "$1" in
    *"load span"*)      printf 'C1:span' ;;
    *"tertile ratios"*) printf 'C1:swing' ;;
    *)                  printf 'C1:other' ;;
  esac
}
c2_token() {
  case "$1" in
    *"uninformative, not refuting"*) printf 'C2:neff' ;;
    *"the instrument, not the box"*) printf 'C2:constant' ;;
    *"does not track the load"*)     printf 'C2:corr' ;;
    *)                               printf 'C2:other' ;;
  esac
}
c3_token() {
  case "$1" in
    *"carry an ACTIVE count"*) printf 'C3:blind' ;;
    *"active spans"*)          printf 'C3:flat' ;;
    *)                         printf 'C3:other' ;;
  esac
}

# A term is an INSTRUMENT term when no amount of further wall clock can clear it. `:other` counts as
# an instrument term ON PURPOSE: an unrecognised why-string is a wording drift this file cannot
# adjudicate, and the safe side of "I cannot tell" is to STOP and make a human read it, never to
# keep burning hours on a refusal whose meaning has been lost.
is_instrument_term() {
  case "$1" in
    C1:span|C2:neff|C3:flat|C3:blind) return 1 ;;
    *) return 0 ;;
  esac
}
sig_is_instrument() {
  local t
  for t in $1; do is_instrument_term "$t" && return 0; done
  return 1
}

# The failing controls of ONE analyze run, as a space-separated signature. Empty means PASS.
signature_of() {
  local text="$1" sig="" line
  while IFS= read -r line; do
    case "$line" in
      *"C1 LEVEL"*FAIL*)    sig="$sig $(c1_token "$line")" ;;
      *"C2 DYNAMICS"*FAIL*) sig="$sig $(c2_token "$line")" ;;
      *"C3 IDENTIFY"*FAIL*) sig="$sig $(c3_token "$line")" ;;
      *NO-DATA*)            sig="$sig NO-DATA" ;;
    esac
  done <<<"$text"
  printf '%s' "${sig# }"
}

OUT="$CC_MARG_OUT"; WINDOW=3600; INTERVAL=60; MAXW=6; REPEAT=3; QUIET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)          OUT="${2:-}"; shift 2 ;;
    --window-s)     WINDOW="${2:-}"; shift 2 ;;
    --interval-s)   INTERVAL="${2:-}"; shift 2 ;;
    --max-windows)  MAXW="${2:-}"; shift 2 ;;
    --repeat-stop)  REPEAT="${2:-}"; shift 2 ;;
    --quiet)        QUIET=1; shift ;;
    -h|--help)      sed -n '/^# Usage:/,/^#   CC_MARG_OUT/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
case "$WINDOW$INTERVAL$MAXW$REPEAT" in *[!0-9]*) die "--window-s/--interval-s/--max-windows/--repeat-stop must be integers" ;; esac
[ "$MAXW" -ge 1 ] || die "--max-windows must be >= 1"
[ "$REPEAT" -ge 2 ] || die "--repeat-stop must be >= 2 (one refusal is not a repeat)"
[ -x "$CC_MARG_BIN" ] || [ -r "$CC_MARG_BIN" ] || die "cannot read analyzer at '$CC_MARG_BIN' (set CC_MARG_BIN)"

prior="$(grep -cv '^#' "$OUT" 2>/dev/null)"
case "$prior" in ''|*[!0-9]*) prior=0 ;; esac
say "capacity-marginal-run: item $ITEM · $DOC §6"
if [ "$prior" -gt 0 ]; then
  say "capacity-marginal-run: RESUMING — $OUT already carries $prior row(s); this window EXTENDS it"
else
  say "capacity-marginal-run: fresh window -> $OUT"
fi
say "capacity-marginal-run: up to $MAXW x ${WINDOW}s at ${INTERVAL}s; stop on PASS, or on the same instrument term x$REPEAT"

hist=""; w=0; last_text=""; last_sig=""
while [ "$w" -lt "$MAXW" ]; do
  w=$(( w + 1 ))
  say ""
  say "── window $w/$MAXW ──────────────────────────────────────────────────────────────"
  bash "$CC_MARG_BIN" sample --window-s "$WINDOW" --interval-s "$INTERVAL" --out "$OUT" ${QUIET:+--quiet}
  srv=$?
  if [ "$srv" -ne 0 ] && [ "$prior" -eq 0 ] && [ "$w" -eq 1 ]; then
    printf 'CAPACITY-MARGINAL-RUN: NO-DATA — the sampler recorded nothing (rc %d). Nothing to analyze.\n' "$srv"
    exit 3
  fi

  last_text="$(bash "$CC_MARG_BIN" analyze --in "$OUT" 2>&1)"; arv=$?
  printf '%s\n' "$last_text"
  if [ "$arv" -eq 0 ]; then
    cat <<EOF

CAPACITY-MARGINAL-RUN: PASS after $w window(s) — the coefficient above cleared all three controls.

The number is quotable ONLY with its standard error and its window, both printed above. Next, per
$DOC §6 and §6a:

  1. Re-grep the live sites — §6a's own rule, because the ban was enumerated as two paths and a
     grep found three; a list of paths is a denylist of spellings:

       grep -rnE '0\\.172|0\\.566|\\b1\\.89\\b|2\\.5-5' --include='*.sh' --include='*.py' . | grep -v '^\\./docs/'

  2. Replace the REFUTED labels at those sites with the measured value, its s.e. and its window.
     Read the runtime deny string in hooks/agent-teams-enforce.sh before editing it — it is user
     visible text, not a comment.
  3. cc-backlog done $ITEM --evidence "<landed sha>"
EOF
    exit 0
  fi

  last_sig="$(signature_of "$last_text")"
  [ -n "$last_sig" ] || last_sig="unparsed"
  hist="$hist|$last_sig"
  say "capacity-marginal-run: window $w refused on [$last_sig]"

  # THE STOP RULE — the same signature, REPEAT times running. Expressed as an exact SUFFIX match on
  # the `|`-delimited history rather than as index arithmetic: a signature carries spaces, so a
  # field walk is one quoting slip away from comparing halves of two different terms.
  want=""; i=0
  while [ "$i" -lt "$REPEAT" ]; do want="$want|$last_sig"; i=$(( i + 1 )); done
  same=0; case "$hist" in *"$want") same=1 ;; esac

  if [ "$same" -eq 1 ]; then
    if sig_is_instrument "$last_sig"; then
      cat <<EOF

CAPACITY-MARGINAL-RUN: THE FINDING — [$last_sig] refused $REPEAT windows running.

This is $DOC §6's own second exit, and it is a
result, not a failure to get one: an instrument term does not clear with wall clock, so the
process-unit census is NOT the right instrument on this box. No coefficient is quotable, and none
is printed above or below this line.

Next increment is §7.3, not another window: capture a Darwin \`ps -axM\` fixture so the THREAD-unit
census can be parsed under test (B3 measured its load/census ratio at 0.913 against the process
census's 1.30-1.55), then re-run this command against the thread unit.

  cc-backlog add --project claude-infrastructure --dod-ref $DOC \\
    --title "capture a Darwin ps -axM fixture and ship the thread-unit census — the process unit refused $ITEM on [$last_sig]"
EOF
      exit 1
    fi
    cat <<EOF

CAPACITY-MARGINAL-RUN: still CONDITION-limited — [$last_sig] repeated $REPEAT windows running.

These terms are about the HOUR, not the census, so this is not §6's finding and nothing here says
the instrument is wrong. Keep extending; $OUT holds the accumulated window and re-running the
identical command continues it.

  C3:flat / C3:blind  the ACTIVE count never moved — §6: run the window ACROSS A DISPATCH WAVE.
                      Do NOT synthesise levels by pausing the box.
  C1:span             load1 never moved 1.5x. An ordinary day spans 8.35..46.39; a dead-quiet hour
                      correctly refuses.
  C2:neff             not enough INDEPENDENT observations yet — n_eff = span/tau + 1, so this one
                      clears itself given wall clock.
EOF
    exit 3
  fi
done

cat <<EOF

CAPACITY-MARGINAL-RUN: budget spent — $MAXW window(s), refusal still moving. Terms seen: ${hist#|}

The refusal has NOT stabilised, so neither §6 exit is earned: this is not a coefficient and it is
not the finding. $OUT holds the accumulated window; re-run the identical command to extend it.
EOF
exit 3
