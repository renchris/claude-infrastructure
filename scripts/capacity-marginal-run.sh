#!/bin/bash
# capacity-marginal-run.sh — drive the §6 measurement to a DECISION, on the box, in one command.
#
# WHY THIS EXISTS (backlog 193ae8ddce72; run protocol
# docs/research/marginal-load-per-active-session-2026-08-19.md §6). That item's instrument
# (scripts/capacity-marginal.sh) landed 2026-08-19 and its ban on the four refuted values landed
# 2026-08-26 (§6a). What was left is the measurement itself, and it was left as a PROTOCOL:
#
#     sample 3600 s -> analyze -> read the verdict -> if NO-ATTRIBUTION, extend the window and
#     analyze again -> repeat until it passes, OR until the same term refuses across several
#     windows, which is itself the finding -> on PASS, re-grep the citation sites and update them.
#
# That is a worksheet with a loop and a judgment in it, and it makes the operator the runtime. It
# also cannot be started off-box — and the box it needs is not the box most sessions run on. This
# script is that protocol as a PROGRAM: it refuses the wrong box in one second instead of the
# wrong hour, drives the sample/analyze loop to one of four named verdicts, and on a PASS prints
# the citation sites it just re-derived rather than a list someone has to trust.
#
# ══ PREFLIGHT IS THE POINT, AND IT USES THE SAMPLER AS ITS OWN ARBITER ══════════════════════════
# The measurement needs three things this box may not have: a readable load average, a live
# `cc_sp_active` sensor, and an actual fleet of resident sessions. A run that discovers any of
# those is missing does so AFTER an hour of sampling, and returns NO-DATA that reads exactly like
# a quiet box. So preflight takes ONE real sample row through the sampler itself and inspects it.
# Not a reimplementation of the sampler's probes — the sampler's own row, so preflight can never
# disagree with the run it is gating (memory: make-the-actuator-the-arbiter, the shape
# githooks/pre-commit uses for the same reason).
#
# ══ WHY A REFUSAL IS NOT AUTOMATICALLY A FINDING ════════════════════════════════════════════════
# §6: "extend the window until the verdict stops being NO-ATTRIBUTION *or* the refusal repeats
# with the same term across several windows — which would itself be the finding (the process-unit
# census is not the right instrument)." Two guards keep that from firing on a window that was
# merely too short, because C2 needs `n_eff` >= 20 and an early window cannot have it:
#
#   1. A refusal is not eligible to be persistent until CC_MARGRUN_SETTLE_S of wall clock has been
#      sampled (default 3600 — §6's own "one hour at 60 s gives n_eff = 60 against a floor of 20",
#      which is the point at which C2 becomes decidable at all).
#   2. A window whose C2 failure is worded "uninformative, not refuting" NEVER counts toward the
#      streak. That distinction is the whole lesson of B3 (2.5-4 min windows, ~2.5 independent
#      observations, negative correlations carrying no information) and treating an uninformative
#      window as evidence is precisely the defect the sampler was built to refuse.
#
# ══ ON A PASS, THE SITES ARE RE-GREPPED, NEVER RECITED ══════════════════════════════════════════
# §6a is explicit: the doc named two citation sites and a grep over live code found three — the
# third being scripts/lib/spawn-presence.sh, the library that DEFINES the population the
# coefficient is denominated in. "A ban enumerated as a list of paths is a denylist of spellings."
# So this script greps at the moment of the PASS and prints what it finds. It does not edit them:
# the substitution is a judgment about what each site should say, and it wants the coefficient's
# standard error and window beside it.
#
# Usage:
#   capacity-marginal-run.sh [--out FILE] [--window-s N] [--interval-s N] [--max-total-s N]
#                            [--repeat-refusals N] [--fresh] [--preflight-only] [--no-preflight]
#
# Exit: 0 MARGINAL (coefficient emitted) · 1 UNDECIDED (budget spent, term still moving; extend)
#       2 usage error · 3 PERSISTENT-REFUSAL (same term across N windows — itself the finding)
#       4 PREFLIGHT-REFUSED (this box cannot answer; nothing was sampled)
#
# Seams (all read with an explicit default):
#   CC_MARGRUN_SAMPLER          path to capacity-marginal.sh (default: beside this script)
#   CC_MARGRUN_OUT              default TSV path
#   CC_MARGRUN_WINDOW_S(900)    seconds sampled per increment before re-analyzing
#   CC_MARGRUN_INTERVAL_S(60)   sample spacing; 60 is load1's time constant and the independence unit
#   CC_MARGRUN_MAX_TOTAL_S(7200) total sampling budget across all increments
#   CC_MARGRUN_REPEAT(3)        consecutive same-term refusals that constitute the finding
#   CC_MARGRUN_SETTLE_S(3600)   wall clock that must be sampled before a refusal may be persistent
#   CC_MARGRUN_MIN_RESIDENT(2)  resident sessions preflight requires before it will spend the budget
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

CC_MARGRUN_SAMPLER="${CC_MARGRUN_SAMPLER:-$HERE/capacity-marginal.sh}"
CC_MARGRUN_OUT="${CC_MARGRUN_OUT:-${TMPDIR:-/tmp}/capacity-marginal.tsv}"
CC_MARGRUN_WINDOW_S="${CC_MARGRUN_WINDOW_S:-900}"
CC_MARGRUN_INTERVAL_S="${CC_MARGRUN_INTERVAL_S:-60}"
CC_MARGRUN_MAX_TOTAL_S="${CC_MARGRUN_MAX_TOTAL_S:-7200}"
CC_MARGRUN_REPEAT="${CC_MARGRUN_REPEAT:-3}"
CC_MARGRUN_SETTLE_S="${CC_MARGRUN_SETTLE_S:-3600}"
CC_MARGRUN_MIN_RESIDENT="${CC_MARGRUN_MIN_RESIDENT:-2}"

die() { printf 'capacity-marginal-run: %s\n' "$*" >&2; exit 2; }

log() { printf '%s\n' "$*"; [ -z "${LOGFILE:-}" ] || printf '%s\n' "$*" >> "$LOGFILE"; }

# ── preflight ───────────────────────────────────────────────────────────────────────────────────
# Returns 0 when this box can answer. Otherwise prints the term that refused and returns 4.
# Takes ONE row through the sampler itself; see the header for why it is not its own probe.
preflight() {
  local probe rc line active resident
  probe="$(mktemp "${TMPDIR:-/tmp}/capmarg-preflight.XXXXXX")" || {
    log "PREFLIGHT-REFUSED — tmpdir: cannot create a probe file"; return 4; }

  bash "$CC_MARGRUN_SAMPLER" sample --window-s 1 --interval-s 1 --out "$probe" --quiet
  rc=$?
  line="$(grep -v '^#' "$probe" 2>/dev/null | tail -1)"
  rm -f "$probe"

  if [ "$rc" -eq 3 ] || [ -z "$line" ]; then
    log "PREFLIGHT-REFUSED — load1: the sampler recorded no row, so the load average is unreadable here."
    log "  A row is dropped rather than written as 0 when load1 cannot be read (Darwin sysctl vm.loadavg /"
    log "  Linux /proc/loadavg). Nothing downstream can be measured without it."
    return 4
  fi
  [ "$rc" -eq 0 ] || { log "PREFLIGHT-REFUSED — sampler: exited $rc on a 1 s probe"; return 4; }

  active="$(printf '%s' "$line" | cut -f6)"
  resident="$(printf '%s' "$line" | cut -f7)"

  case "$active" in
    ''|*[!0-9]*)
      log "PREFLIGHT-REFUSED — active: cc_sp_active is unmeasurable on this box (row reads '${active:--}')."
      log "  The coefficient is denominated in the ACTIVE (mid-turn) population and C3 needs it to move."
      log "  A dead sensor must not read as a quiet box, so this refuses rather than sampling zeros."
      return 4 ;;
  esac
  case "$resident" in ''|*[!0-9]*) resident=0 ;; esac
  if [ "$resident" -lt "$CC_MARGRUN_MIN_RESIDENT" ]; then
    log "PREFLIGHT-REFUSED — fleet: $resident resident session(s), below CC_MARGRUN_MIN_RESIDENT=$CC_MARGRUN_MIN_RESIDENT."
    log "  This is the measurement's subject, not a precondition to wave through: a marginal per ACTIVE"
    log "  session fitted on a box with no fleet is a slope through one point. Run it on the operator's"
    log "  box during a dispatch wave, which is also what gives C3 its >= 3 active levels."
    return 4
  fi

  log "PREFLIGHT PASS — load1 readable · cc_sp_active = $active · resident = $resident"
  return 0
}

# ── failing-term extraction ─────────────────────────────────────────────────────────────────────
# From `analyze --json`. Prints a stable space-separated term list, e.g. "C1 C2". Empty on a PASS.
failing_terms() {
  printf '%s' "$1" | awk '
    { s = $0
      if (s ~ /"c1_level":false/)     t = t (t ? " " : "") "C1"
      if (s ~ /"c2_dynamics":false/)  t = t (t ? " " : "") "C2"
      if (s ~ /"c3_identify":false/)  t = t (t ? " " : "") "C3"
      print t }'
}

# True when the only reason C2 failed is that the window holds too few INDEPENDENT observations.
# Such a window is uninformative, not refuting (B3's defect, by name), so it may not be counted as
# evidence that the instrument is wrong.
c2_uninformative() { case "$1" in *"uninformative, not refuting"*) return 0 ;; *) return 1 ;; esac; }

# ── the citation sites, re-derived at the moment of the PASS ────────────────────────────────────
regrep_sites() {
  log ""
  log "CITATION SITES — re-grepped just now over live code (docs/ excluded). Update these, quoting"
  log "the coefficient WITH its standard error and its window; do not work from any stored list:"
  local hits
  hits="$(cd "$REPO" && grep -rnE '0\.172|0\.566|1\.89|2\.5[-–]5' \
            --include='*.sh' --include='*.py' --include='*.bash' \
            scripts hooks bin lib 2>/dev/null | grep -v 'capacity-marginal')"
  if [ -z "$hits" ]; then
    log "  (none — either they are already updated, or the spelling moved again; widen the grep)"
  else
    while IFS= read -r h; do log "  $h"; done <<< "$hits"
  fi
  log ""
  log "Then land, and close the item with the landed sha:"
  log "  cc-backlog done 193ae8ddce72 --evidence \"<landed sha>\""
}

main() {
  local out="$CC_MARGRUN_OUT" window="$CC_MARGRUN_WINDOW_S" interval="$CC_MARGRUN_INTERVAL_S"
  local budget="$CC_MARGRUN_MAX_TOTAL_S" repeat="$CC_MARGRUN_REPEAT" settle="$CC_MARGRUN_SETTLE_S"
  local fresh="" only="" skip=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out)              out="${2:-}"; shift 2 ;;
      --window-s)         window="${2:-}"; shift 2 ;;
      --interval-s)       interval="${2:-}"; shift 2 ;;
      --max-total-s)      budget="${2:-}"; shift 2 ;;
      --repeat-refusals)  repeat="${2:-}"; shift 2 ;;
      --fresh)            fresh=1; shift ;;
      --preflight-only)   only=1; shift ;;
      --no-preflight)     skip=1; shift ;;
      -h|--help)
        sed -n '/^# Usage:/,/^#       4 PREFLIGHT/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 2 ;;
      *) die "unknown argument '$1'" ;;
    esac
  done
  case "$window$interval$budget$repeat$settle" in
    *[!0-9]*) die "--window-s/--interval-s/--max-total-s/--repeat-refusals must be integers" ;;
  esac
  [ "$interval" -ge 1 ] || die "--interval-s must be >= 1"
  [ "$window"   -ge 1 ] || die "--window-s must be >= 1"
  [ "$budget"   -ge 1 ] || die "--max-total-s must be >= 1"
  [ "$repeat"   -ge 1 ] || die "--repeat-refusals must be >= 1"
  [ -r "$CC_MARGRUN_SAMPLER" ] || die "sampler not readable: $CC_MARGRUN_SAMPLER"

  [ -z "$fresh" ] || rm -f "$out"
  LOGFILE="$out.log"; : > "$LOGFILE" 2>/dev/null || LOGFILE=""

  log "capacity-marginal-run — backlog 193ae8ddce72 §6"
  log "  out=$out  window=${window}s  interval=${interval}s  budget=${budget}s  repeat=$repeat  settle=${settle}s"

  if [ -z "$skip" ]; then
    preflight || exit 4
  else
    log "PREFLIGHT SKIPPED (--no-preflight)"
  fi
  [ -z "$only" ] || exit 0

  local elapsed=0 streak=0 last="" terms json rc why increment
  while [ "$elapsed" -lt "$budget" ]; do
    increment="$window"
    [ $(( elapsed + increment )) -le "$budget" ] || increment=$(( budget - elapsed ))
    log ""
    log "── sampling ${increment}s (elapsed ${elapsed}s / ${budget}s) ─────────────────────────────"
    bash "$CC_MARGRUN_SAMPLER" sample \
      --window-s "$increment" --interval-s "$interval" --out "$out" --quiet
    elapsed=$(( elapsed + increment ))

    json="$(bash "$CC_MARGRUN_SAMPLER" analyze --in "$out" --json 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then
      log ""
      bash "$CC_MARGRUN_SAMPLER" analyze --in "$out" | tee -a "${LOGFILE:-/dev/null}"
      log ""
      log "VERDICT: MARGINAL — all three controls passed over ${elapsed}s of sampling."
      log "  series: $out    machine-readable: $json"
      regrep_sites
      exit 0
    fi
    if [ "$rc" -eq 3 ]; then
      log "  NO-DATA so far — $json"
      streak=0; last=""
      continue
    fi

    terms="$(failing_terms "$json")"
    why="$(bash "$CC_MARGRUN_SAMPLER" analyze --in "$out" 2>&1 | grep -E '^  C[123] ')"
    log "  NO-ATTRIBUTION — failing: ${terms:-none}"
    printf '%s\n' "$why"
    [ -z "${LOGFILE:-}" ] || printf '%s\n' "$why" >> "$LOGFILE"

    # An uninformative C2 is a window that was too short, not an instrument that is wrong. It can
    # never be the finding, so it resets the streak rather than building one.
    if [ "$terms" = "C2" ] && c2_uninformative "$why"; then
      log "  (C2 is uninformative, not refuting — this window does not count toward a persistent refusal)"
      streak=0; last=""
      continue
    fi

    if [ "$terms" = "$last" ]; then streak=$(( streak + 1 )); else streak=1; last="$terms"; fi

    if [ "$streak" -ge "$repeat" ] && [ "$elapsed" -ge "$settle" ]; then
      log ""
      log "VERDICT: PERSISTENT-REFUSAL — '$terms' refused $streak consecutive windows over ${elapsed}s."
      log "  This IS the finding, not a failed run: the process-unit census is not the right"
      log "  instrument for this box, and the thread-unit refinement (§7.3 of"
      log "  docs/research/marginal-load-per-active-session-2026-08-19.md — a captured \`ps -axM\`"
      log "  fixture, then a tested parser) becomes the next increment rather than a nicety."
      log "  Report it with this series attached: $out"
      exit 3
    fi
  done

  log ""
  log "VERDICT: UNDECIDED — budget of ${budget}s spent; last failing term '${last:-none}' had not"
  log "  yet repeated $repeat times (streak $streak). This is not a finding either way."
  log "  Extend over the SAME series — analyze is re-runnable over a growing file:"
  log "    bash $HERE/$(basename "${BASH_SOURCE[0]}") --out $out --max-total-s $(( budget * 2 )) --no-preflight"
  exit 1
}

main "$@"
