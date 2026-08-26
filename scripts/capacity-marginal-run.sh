#!/bin/bash
# capacity-marginal-run.sh — drive the ONE measurement that is left on backlog 193ae8ddce72 to a
# TERMINAL verdict, in one command, on the box.
#
# WHY THIS EXISTS. `capacity-marginal.sh` is the instrument; this is the RUN. The distinction is
# not ceremony — read what the protocol actually asks for
# (docs/research/marginal-load-per-active-session-2026-08-19.md §6, verbatim):
#
#     "analyze is re-runnable over a growing file, so the honest protocol is: sample, analyze, and
#      extend the window until the verdict stops being NO-ATTRIBUTION **or** the refusal repeats
#      with the same term across several windows — which would itself be the finding."
#
# That is a loop with a decision inside it, and §6 is written for a human to execute. A human
# executing it IS the interpreter: they run `sample`, read three control verdicts, judge whether
# this refusal means "keep going" or "stop, that is the answer", re-run, and repeat — for hours,
# on a box they are also trying to work on. Handing that over as two commands and a paragraph is a
# worksheet, and the interpreter it delegates is a person (global CLAUDE.md § Manual-Command
# Delivery). This file is that interpreter, so the residue is one command that drives itself,
# verifies its own work, and is safe to re-run.
#
# It measures NOTHING itself. Every number comes from `capacity-marginal.sh analyze`, whose three
# controls are the product; this file only decides when to stop asking it.
#
# ══ THE PREFLIGHT IS KEYED ON THE DANGEROUS EFFECT, NOT ON `uname` ══════════════════════════════
# The obvious guard is "refuse unless Darwin". It is the wrong key, in both directions, and this
# repo has the lesson written down already (memory: guard-refusal-fires-on-its-own-harness):
#
#   · A Darwin box whose ACTIVE sensor is dead passes a `uname` guard and then burns the whole
#     window to print "0 row(s) carry an ACTIVE count" — C3 cannot pass without a regressor, so
#     the run was undecidable before its first sample. That is the expensive failure.
#   · A Linux VM with a stubbed `cc_sp_active` FAILS a `uname` guard for the right reason by
#     accident, which teaches nothing, and would pass one keyed on the kernel string alone.
#
# The dangerous effect is a window that either cannot decide or decides about a machine that is
# not the fleet. Both are identified by the same two facts, and this file measures them before
# spending an hour: is `cc_sp_active` MEASURABLE (not `-`), and is there a resident fleet to
# apportion at all. Off-box that is exactly why it refuses — a cloud VM reads `active=` empty and
# `resident=0` — but it refuses on the measurement, so the guard still fires on a broken sensor at
# home and still stands down on a box that genuinely has a fleet.
#
# ══ NOT EVERY REFUSAL IS A FINDING — the one judgment this loop exists to get right ═════════════
# §6's terminal condition is "the refusal repeats with the same term". Taken literally it stops the
# run at the exact moment §6 says to continue, because the FIRST refusal of a short window is
# always C2 failing on `n_eff`, and that refusal is the loop's normal early state:
#
#     "corr 0.812 but n_eff 1.8 < 20 independent observations (span 60s / tau 60s)
#      — uninformative, not refuting"
#
# The sampler words it that way deliberately, and the word is load-bearing here. An `n_eff`
# shortfall is the ONE refusal that extending the window CURES; counting it toward the finding
# would convert "not enough data yet" into "the instrument cannot answer", which is precisely the
# error B3 made and the sampler's C2 was built to refuse. So an `n_eff` shortfall RESETS the
# streak, and only a SUBSTANTIVE refusal — a census that does not track the load, a ratio that
# drifts across tertiles, an ACTIVE count that never moves — counts toward it.
#
# ══ IT DOES NOT WRITE THE CITATION SITES, AND THAT IS DELIBERATE ════════════════════════════════
# On a PASS, §6 says to update the sites that carry the refuted 2.5-5. §6a of the same doc records
# that the list of those sites was WRONG when written — it named two, and a grep over live code
# returned three, the third being `spawn-presence.sh`, the library that defines the very
# population the coefficient is denominated in. Its instruction is therefore "re-grep at the PASS,
# do not work from this table". This file re-greps, and REPORTS: the hits are candidates a reader
# must judge, because some of them quote the figure as refuted history (which stays) and some
# state a derivation (which gets the measured value). A driver that edited them would be
# re-creating the denylist-of-spellings the doc just finished refuting.
#
# Usage:
#   capacity-marginal-run.sh [--round-s N] [--interval-s N] [--max-rounds N] [--repeat N]
#                            [--out FILE] [--force]
#
#   --round-s     (3600) seconds of sampling per round. One hour at 60 s gives n_eff = 60 against
#                 a floor of 20, which is the single thing B3's windows could not buy.
#   --interval-s  (60)   sample spacing. Below CC_MARG_TAU the extra rows are not extra evidence.
#   --max-rounds  (4)    deadline in rounds. The run exits EARLY on a verdict; this only bounds
#                 the undecided case so it cannot sample forever.
#   --repeat      (3)    substantive refusals with the identical failing term(s) before the
#                 refusal is reported as the finding. "Several windows", made countable.
#   --out         sampling TSV. Appended across rounds and across invocations — the growing file
#                 IS the protocol, so re-running this command extends the window rather than
#                 restarting it.
#   --force       run the rounds even though the preflight refused. For a box where the operator
#                 knows the sensor better than this file does; it never suppresses the reason.
#
# Exit: 0 MARGINAL (a coefficient, all three controls passed) · 4 preflight refused (nothing
#       sampled) · 5 TERMINAL REFUSAL — the same substantive term across --repeat windows, which
#       §6 names as itself the finding · 6 deadline reached still undecided · 2 usage · 3 the
#       sampler produced no usable rows at all.
#
# Seams: CC_MARGRUN_SAMPLER (path to capacity-marginal.sh, for tests) · every CC_MARG_* seam of
# the sampler passes straight through, since this file only invokes it.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLER="${CC_MARGRUN_SAMPLER:-$SELF_DIR/capacity-marginal.sh}"

die() { printf 'capacity-marginal-run: %s\n' "$*" >&2; exit 2; }

round_s=3600
interval_s=60
max_rounds=4
repeat_n=3
out=""
force=""

while [ $# -gt 0 ]; do
  case "$1" in
    --round-s)    round_s="${2:-}"; shift 2 ;;
    --interval-s) interval_s="${2:-}"; shift 2 ;;
    --max-rounds) max_rounds="${2:-}"; shift 2 ;;
    --repeat)     repeat_n="${2:-}"; shift 2 ;;
    --out)        out="${2:-}"; shift 2 ;;
    --force)      force=1; shift ;;
    -h|--help)    sed -n '/^# Usage:/,/^# Seams:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

case "$round_s$interval_s$max_rounds$repeat_n" in *[!0-9]*) die "--round-s/--interval-s/--max-rounds/--repeat must be integers" ;; esac
[ "$round_s"    -ge 1 ] || die "--round-s must be >= 1"
[ "$interval_s" -ge 1 ] || die "--interval-s must be >= 1"
[ "$max_rounds" -ge 1 ] || die "--max-rounds must be >= 1"
[ "$repeat_n"   -ge 1 ] || die "--repeat must be >= 1"
[ -x "$SAMPLER" ] || [ -r "$SAMPLER" ] || die "sampler not found at '$SAMPLER' (set CC_MARGRUN_SAMPLER)"
[ -n "$out" ] || out="${TMPDIR:-/tmp}/capacity-marginal.tsv"

# ── PREFLIGHT ───────────────────────────────────────────────────────────────────────────────────
# Two facts, both MEASURED here rather than inferred from the kernel string. Each names the control
# it would have starved, because "cannot run here" must not read as "the box is quiet".
preflight() { # -> 0 ok / 1 refused; prints the reasons
  local lib active resident bad=0
  lib="$SELF_DIR/lib/spawn-presence.sh"
  active=""
  if [ -r "$lib" ]; then
    # shellcheck source=/dev/null
    . "$lib" 2>/dev/null || true
    if command -v cc_sp_active >/dev/null 2>&1; then
      active="$(cc_sp_active 2>/dev/null)" || active=""
    fi
  fi
  case "$active" in ''|*[!0-9]*) active="" ;; esac
  resident="$(ps -axo comm= 2>/dev/null || ps -eo comm= 2>/dev/null)"
  resident="$(printf '%s\n' "$resident" | grep -cE "${CC_MARG_EXEC_RE:-\.claude-[0-9]+/node_modules/|claude\.exe$}")"

  if [ -z "$active" ]; then
    printf '  ACTIVE census   UNMEASURABLE — cc_sp_active returned nothing. C3 IDENTIFY can never\n' >&2
    printf '                  pass without a regressor, so this window is undecidable before its\n' >&2
    printf '                  first sample. This is the sensor, not a quiet box.\n' >&2
    bad=1
  else
    printf '  ACTIVE census   ok — cc_sp_active reads %s\n' "$active" >&2
  fi
  if [ "$resident" -lt 1 ]; then
    printf '  RESIDENT fleet  NONE — 0 processes match the launcher executable path. There is no\n' >&2
    printf '                  Claude load to apportion here; any coefficient would describe another\n' >&2
    printf '                  machine. (Off-box, this is the line that fires.)\n' >&2
    bad=1
  else
    printf '  RESIDENT fleet  ok — %s session process(es)\n' "$resident" >&2
  fi
  return "$bad"
}

printf 'capacity-marginal-run: preflight\n' >&2
if ! preflight; then
  if [ -z "$force" ]; then
    printf 'VERDICT: PREFLIGHT-REFUSED — nothing sampled. This measurement needs the live fleet\n'
    printf '  (docs/research/marginal-load-per-active-session-2026-08-19.md §6). Run it on the box\n'
    printf '  during a dispatch wave, not off-box. Override with --force if the sensor is wrong.\n'
    exit 4
  fi
  printf 'capacity-marginal-run: preflight refused; --force given, continuing anyway\n' >&2
fi

# ── THE ROUNDS ──────────────────────────────────────────────────────────────────────────────────
prev_sig=""
streak=0
round=0
last_txt=""
last_rc=3

while [ "$round" -lt "$max_rounds" ]; do
  round=$(( round + 1 ))
  printf 'capacity-marginal-run: round %d/%d — sampling %ss at %ss (cumulative window in %s)\n' \
    "$round" "$max_rounds" "$round_s" "$interval_s" "$out" >&2
  bash "$SAMPLER" sample --window-s "$round_s" --interval-s "$interval_s" --out "$out" --quiet

  last_txt="$(bash "$SAMPLER" analyze --in "$out" 2>&1)"; last_rc=$?
  printf '%s\n' "$last_txt" >&2

  # PASS — the loop's whole purpose. Report and stop.
  if [ "$last_rc" -eq 0 ]; then
    printf '%s\n' "$last_txt"
    printf '\n'
    printf 'VERDICT: MARGINAL — the coefficient above is quotable: its census demonstrably tracks\n'
    printf '  the load it apportions, over enough independent observations to tell. Quote it WITH\n'
    printf '  the standard error and the window shown on the first line, never bare.\n'
    printf '\n'
    printf 'Candidate citation sites, re-grepped live just now (§6a: do not work from a stored list):\n'
    grep -rnE '2\.5-5|2\.5–5|0\.172|0\.566|\b1\.89\b' \
      --include='*.sh' --include='*.py' --include='*.bats' "$SELF_DIR/.." 2>/dev/null \
      | grep -v '/docs/' | grep -v '/\.git/' | sed 's/^/  /' || true
    printf '\n'
    printf '  Read each. A site that STATES a derivation for a gate constant takes the measured\n'
    printf '  value; a site that quotes the figure as REFUTED history keeps saying so. They are not\n'
    printf '  distinguishable by path, which is why this is a report and not an edit.\n'
    printf '\n'
    printf 'Then close the item:\n'
    printf '  cc-backlog done 193ae8ddce72 --evidence "<landed sha>"\n'
    exit 0
  fi

  # NO-DATA — the sampler recorded nothing usable. Not a refusal; nothing to count.
  if [ "$last_rc" -eq 3 ]; then
    printf 'capacity-marginal-run: round %d produced no usable rows — not a refusal, extending\n' "$round" >&2
    streak=0; prev_sig=""
    continue
  fi

  # A refusal. Which controls failed, and is it the curable one?
  #
  # NOT `grep -q`, and this is not style. This file runs under `pipefail`, where an early-exiting
  # consumer SIGPIPEs its producer and the pipeline's status becomes the producer's 141 — so
  # `printf … | grep -q P` reads FALSE ON A MATCH once the payload outgrows the pipe buffer. The
  # analyze output is small today and every one of these conditions would have passed its test
  # while being wrong on a long window, which is the worst shape a latent bug can have: the
  # n_eff carve-out below is the one branch that must never silently invert. Draining with
  # `grep P >/dev/null` removes the early exit and with it the signal.
  sig=""
  for c in C1 C2 C3; do
    if printf '%s\n' "$last_txt" | grep -E "^  $c [A-Z]+ +FAIL" >/dev/null; then
      sig="$sig${sig:+,}$c"
    fi
  done
  if printf '%s\n' "$last_txt" | grep 'uninformative, not refuting' >/dev/null; then
    printf 'capacity-marginal-run: round %d refused on n_eff (%s) — the curable refusal; extending\n' \
      "$round" "$sig" >&2
    streak=0; prev_sig=""
    continue
  fi

  if [ -n "$sig" ] && [ "$sig" = "$prev_sig" ]; then
    streak=$(( streak + 1 ))
  else
    streak=1; prev_sig="$sig"
  fi
  printf 'capacity-marginal-run: round %d substantive refusal [%s] — %d/%d toward the finding\n' \
    "$round" "$sig" "$streak" "$repeat_n" >&2

  if [ "$streak" -ge "$repeat_n" ]; then
    printf '%s\n' "$last_txt"
    printf '\n'
    printf 'VERDICT: TERMINAL-REFUSAL — [%s] failed identically across %d growing windows, with\n' "$sig" "$streak"
    printf '  n_eff already sufficient, so this is not "not enough data yet". §6 names this outcome\n'
    printf '  as itself the finding: the PROCESS-unit census is not the right instrument on this\n'
    printf '  box, and the THREAD-unit refinement (§7 item 3) becomes the next increment rather\n'
    printf '  than a nicety — it needs a captured ps -axM fixture before its parser can be tested.\n'
    printf '  No coefficient is quotable from this run, and none of the four published values\n'
    printf '  becomes quotable by its failure.\n'
    printf '\n'
    printf 'File the increment, do not close the item:\n'
    printf '  cc-backlog add --project claude-infrastructure --title "thread-unit census for capacity-marginal: capture a ps -axM fixture and ship a tested parser (process unit refused [%s] across %d windows)"\n' "$sig" "$streak"
    exit 5
  fi
done

# ── DEADLINE ────────────────────────────────────────────────────────────────────────────────────
# Undecided is its own outcome and must never round to either of the other two.
printf '%s\n' "$last_txt"
printf '\n'
printf 'VERDICT: UNDECIDED — %d round(s) of %ss did not reach a coefficient or a repeated\n' "$max_rounds" "$round_s"
printf '  substantive refusal. The window in %s is CUMULATIVE: re-run this command to extend it\n' "$out"
printf '  rather than starting over. If the refusals keep landing on n_eff, the box is quieter\n'
printf '  than the protocol needs — run the window across a dispatch wave, not during a lull, and\n'
printf '  do NOT synthesise levels by pausing the box (§6).\n'
exit 6
