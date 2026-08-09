#!/bin/bash
# idle-slope-sweep.sh — the DECISIVE TEST for Phase A: launch N idle sessions, sweep N, regress
# load on N. The answer is a SLOPE, in runnable threads per resident session.
#
# WHY A SLOPE AND NOT A LEVEL. docs/plans/CONCURRENCY_PROGRAM.md §S6.3 states the acceptance
# condition in exactly these terms — "Slope, not absolute load — absolute drifts with ambient" — and
# the reason is visible in this repo's own history: §12's caveat records arm baselines drifting
# 4.93 → 5.60 → 5.92 → 12.81 across four arms of a single run, which is larger than several of the
# effects being claimed. A single-point measurement on a quiet box proves nothing at all; a
# regression across a swept N survives a baseline that moves under it, because a drifting intercept
# does not rotate the line.
#
# WHY IT MEASURES BOTH TERMS. Two quantities are regressed on N and BOTH are reported:
#   · load1 — the 1-minute EWMA. This is the term the capacity model and the admission gate are
#     written in, so it is the only one directly comparable to the published 1.6/session.
#   · mean runnable — occupancy-probe.sh's instantaneous count. Immune to the EWMA lag, and it
#     carries the per-component attribution that says WHICH thing holds the slot.
# Reporting only the first would inherit the EWMA's burst-blindness; reporting only the second would
# produce a number nothing else in the program can be compared against.
#
# THE SETTLE IS NOT A CONVENIENCE. load1 is a 1-minute exponentially-weighted average: it reaches
# only ~63% of a step change after 60 s. Sampling before it settles reports a fraction of the true
# effect and, worse, reports a fraction that VARIES with how fast the sweep ran — an instrument
# whose reading depends on the operator's patience. Default settle is 120 s (≈86% of the step) and
# the floor is enforced, not documented: a settle below 90 s is refused rather than warned about.
#
# WHAT AN "IDLE SESSION" IS HERE, stated so the figure cannot be over-read. It is a real `claude`
# process launched on a real pty with NO prompt: it runs the full SessionStart hook chain (so it
# arms whatever per-session pollers the fleet arms), renders its TUI, and then sits at the composer.
# It makes NO API call, so the sweep costs no quota. It is the honest model of a RESIDENT session —
# §S6.2's design point is 150 resident, ~10 active, and this measures the residency term only. It
# is NOT a model of an active session and must never be quoted as one.
#
# SAFETY. This launches real processes on a box with a documented panic history, so it refuses to
# start above a load floor, caps N, and tears down every session it launched on ANY exit path
# including a signal — a sweep that dies holding 12 sessions would leave the box worse than it found
# it. Only pids THIS RUN launched are ever killed; the fleet is never touched.
#
# Exits: 0 completed · 64 usage · 3 could not measure · 4 refused (box too loaded / launcher absent).
#
# Seams: CC_SLOPE_POINTS ("0 3 6 9") · CC_SLOPE_SETTLE_S (120) · CC_SLOPE_MEASURE_S (60)
#        CC_SLOPE_MAX_N (16) · CC_SLOPE_MAX_START_LOAD (14) · CC_SLOPE_CLAUDE_BIN · CC_SLOPE_OUT
set -uo pipefail

POINTS="${CC_SLOPE_POINTS:-0 3 6 9}"
SETTLE_S="${CC_SLOPE_SETTLE_S:-120}"
MEASURE_S="${CC_SLOPE_MEASURE_S:-60}"
MAX_N="${CC_SLOPE_MAX_N:-16}"
MAX_START_LOAD="${CC_SLOPE_MAX_START_LOAD:-14}"
OUT="${CC_SLOPE_OUT:-$HOME/.claude/logs/idle-slope-sweep.jsonl}"
LABEL=""
DRY=0
REGRESS=0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/occupancy-probe.sh"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0; }

# ── ordinary least squares, and the honesty terms that come with it ───────────────────────────────
# stdin: "<N> <load1> <mean_runnable>" rows.
#
# R² is printed BESIDE the slope and is not optional. A slope fitted through points that do not lie
# on a line is a number whose confidence interval is wide enough to contain anything, and quoting it
# bare is how a fleet ends up with a published figure nobody can reproduce
# (memory: published-figure-decays-with-its-source).
#
# FEWER THAN 3 POINTS ⇒ NO SLOPE AT ALL. Two points always fit a line exactly, so the R² would read
# 1.000 over no evidence whatsoever — the most misleading output this function could produce. It
# refuses and says how many points it had, because "not computed" is a verdict a reader can act on
# and a perfect-looking fit is not.
regress() {
  awk '
    NF == 3 && $1 ~ /^[0-9]+$/ { n++; x[n]=$1; yl[n]=$2; yr[n]=$3 }
    END {
      if (n < 3) {
        printf "SLOPE: not computed — %d usable point(s). Two points fit a line exactly and would\n", n
        printf "       report R2=1.000 over no evidence at all. Re-run with >= 3 points.\n"
        exit 0
      }
      printf "─── REGRESSION over %d points ───\n", n
      split("load1 mean_runnable", nm, " ")
      for (k = 1; k <= 2; k++) {
        sx=0; sy=0; sxx=0; sxy=0; syy=0
        for (i = 1; i <= n; i++) {
          yy = (k==1 ? yl[i] : yr[i])
          sx+=x[i]; sy+=yy; sxx+=x[i]*x[i]; sxy+=x[i]*yy; syy+=yy*yy
        }
        den = n*sxx - sx*sx
        if (den == 0) { printf "  %-14s slope: undefined (every point at the same N)\n", nm[k]; continue }
        b = (n*sxy - sx*sy) / den
        a = (sy - b*sx) / n
        rden = (n*sxx - sx*sx) * (n*syy - sy*sy)
        r2 = (rden > 0) ? ((n*sxy - sx*sy)^2) / rden : 0
        printf "  %-14s SLOPE = %+.5f per resident session   (intercept %.3f, R2 %.3f)\n", nm[k], b, a, r2
      }
    }'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --points)   POINTS="${2:-}";    shift ;;
    --settle)   SETTLE_S="${2:-}";  shift ;;
    --measure)  MEASURE_S="${2:-}"; shift ;;
    --label)    LABEL="${2:-}";     shift ;;
    --out)      OUT="${2:-}";       shift ;;
    --dry-run)  DRY=1 ;;
    # Re-run the fit over "<N> <load1> <mean_runnable>" rows on stdin, launching nothing. Two jobs:
    # it re-analyses a past sweep from its own JSONL without paying for the sessions again, and it
    # makes the regression drivable by the suite. A fit that can only be reached by launching twelve
    # real sessions is a fit nobody ever tests.
    --regress)  REGRESS=1 ;;
    -h|--help)  usage ;;
    *) echo "idle-slope-sweep.sh: unknown arg '$1'" >&2; exit 64 ;;
  esac
  shift
done

# The settle floor is ENFORCED. A sweep run with a 10 s settle produces a clean-looking slope that is
# a fraction of the true one, and nothing downstream can tell — the number carries no marking that
# says it was taken early. Refusing is the only way that stays true.
case "$SETTLE_S" in ''|*[!0-9]*) echo "idle-slope-sweep.sh: --settle needs an integer" >&2; exit 64 ;; esac
if [ "$SETTLE_S" -lt 90 ] && [ "$DRY" = 0 ]; then
  printf 'idle-slope-sweep.sh: --settle %s is below the 90 s EWMA floor. load1 reaches only ~63%%\n' "$SETTLE_S" >&2
  printf '  of a step change after 60 s, so a shorter settle understates every point by an amount\n' >&2
  printf '  that varies with how fast the sweep ran. Refusing rather than reporting an early number.\n' >&2
  exit 64
fi
case "$MEASURE_S" in ''|*[!0-9]*) echo "idle-slope-sweep.sh: --measure needs an integer" >&2; exit 64 ;; esac

# --regress launches nothing and reads nothing from the machine, so it returns BEFORE the load floor
# and the launcher resolution. Re-analysing a sweep taken last week must not be refusable because the
# box happens to be busy today.
if [ "$REGRESS" = 1 ]; then regress; exit 0; fi

for p in $POINTS; do
  case "$p" in ''|*[!0-9]*) echo "idle-slope-sweep.sh: point '$p' is not a non-negative integer" >&2; exit 64 ;; esac
  [ "$p" -le "$MAX_N" ] || { echo "idle-slope-sweep.sh: point $p exceeds CC_SLOPE_MAX_N=$MAX_N" >&2; exit 64; }
done

[ -x "$PROBE" ] || { echo "idle-slope-sweep.sh: occupancy-probe.sh not executable at $PROBE" >&2; exit 4; }

# ── the launcher ──────────────────────────────────────────────────────────────────────────────────
# Resolved rather than assumed: this box carries more than one Claude Code track, and a launcher's
# own --version reports ITS track, not the running one (memory:
# version-identity-is-the-running-process-not-the-launcher). We take the binary the live fleet is
# actually running when we can see one, so the sweep measures the same thing the fleet costs.
resolve_claude_bin() {
  # An OVERRIDE IS STILL VALIDATED. The first version returned $CC_SLOPE_CLAUDE_BIN unchecked, and a
  # typo'd path then reached the launch arm: `script -q /dev/null /no/such/thing` fails in
  # milliseconds and leaves no process, so the sweep sailed on and slept its full settle at every
  # point before regressing over sessions that never existed. It would have reported a slope of
  # approximately zero — the exact answer the wave was hoping for — from a run that launched nothing.
  # A seam that can silently produce the desired result is worse than no seam.
  if [ -n "${CC_SLOPE_CLAUDE_BIN:-}" ]; then
    [ -x "$CC_SLOPE_CLAUDE_BIN" ] || return 1
    printf '%s' "$CC_SLOPE_CLAUDE_BIN"; return 0
  fi
  local live
  live="$(ps -axo command= 2>/dev/null | awk '{
      n = split($1, a, "/"); b = a[n]
      if (b == "claude" || b == "claude.exe") { print $1; exit }
    }')"
  if [ -n "$live" ] && [ -x "$live" ]; then printf '%s' "$live"; return 0; fi
  local c
  for c in "$HOME"/.claude-*/node_modules/.bin/claude; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

CLAUDE_BIN="$(resolve_claude_bin)" || {
  echo "idle-slope-sweep.sh: no claude binary found — set CC_SLOPE_CLAUDE_BIN" >&2; exit 4; }

read_load1() {
  local v
  v="$(sysctl -n vm.loadavg 2>/dev/null)" || return 1
  v="${v#*\{ }"; v="${v%% *}"
  case "$v" in ''|*[!0-9.]*) return 1 ;; esac
  printf '%s' "$v"
}

START_LOAD="$(read_load1)" || { echo "idle-slope-sweep.sh: cannot read vm.loadavg" >&2; exit 3; }
if awk -v a="$START_LOAD" -v b="$MAX_START_LOAD" 'BEGIN{exit !(a>b)}'; then
  printf 'idle-slope-sweep.sh: REFUSED — load1 %s exceeds the %s start floor.\n' "$START_LOAD" "$MAX_START_LOAD" >&2
  printf '  A sweep begun on a loaded box measures the box, not the sessions, and it adds N more\n' >&2
  printf '  processes to a machine already near the gate ceiling. Wait for the box to quiet.\n' >&2
  exit 4
fi

# ── session pool, and the teardown that must survive every exit path ───────────────────────────────
# Only pids launched BY THIS RUN are recorded and killed. A sweep that killed by pattern would reap
# the operator's own fleet the first time a name collided, and there is no undo for that.
POOL=()
teardown() {
  local p
  [ "${#POOL[@]}" -gt 0 ] || return 0
  for p in "${POOL[@]}"; do kill "$p" 2>/dev/null; done
  sleep 1
  # SIGKILL only after SIGTERM has had a second: a `claude` killed outright skips SessionEnd, and
  # SessionEnd is what removes the watchdog pidfile. Skipping it leaves an orphan watchdog daemon
  # per session — this sweep would then MANUFACTURE the very population it exists to measure.
  for p in "${POOL[@]}"; do kill -9 "$p" 2>/dev/null; done
  POOL=()
}
trap 'teardown' EXIT TERM INT HUP

launch_one() {
  # `script -q /dev/null` is what allocates the pty. A claude process without a tty takes a
  # different code path entirely and would not be the thing under measurement.
  script -q /dev/null "$CLAUDE_BIN" --permission-mode plan </dev/null >/dev/null 2>&1 &
  POOL+=("$!")
}

pool_size() { echo "${#POOL[@]}"; }

mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

printf '── idle-slope-sweep %s ──\n' "${LABEL:-(unlabelled)}"
printf 'binary   : %s\n' "$CLAUDE_BIN"
printf 'points   : %s   settle %ss   measure %ss\n' "$POINTS" "$SETTLE_S" "$MEASURE_S"
printf 'start    : load1 %s\n\n' "$START_LOAD"

if [ "$DRY" = 1 ]; then
  printf 'DRY RUN — nothing launched, nothing measured.\n'
  exit 0
fi

ROWS=""
printf '%6s  %10s  %14s  %s\n' "N" "load1" "mean_runnable" "top holder"

for N in $POINTS; do
  # Ramp UP only. Tearing back down between points would make every point pay a fresh
  # SessionStart storm, and the decay of that storm is exactly the drift §12's caveat records.
  while [ "$(pool_size)" -lt "$N" ]; do launch_one; sleep 2; done

  sleep "$SETTLE_S"

  J="$("$PROBE" --seconds "$MEASURE_S" --json --label "N=$N" 2>/dev/null)" || J=""
  if [ -z "$J" ]; then
    printf '%6s  %10s  %14s  %s\n' "$N" "BLIND" "BLIND" "(probe failed — no row)"
    continue
  fi

  LD="$(printf '%s' "$J"  | sed -n 's/.*"mean_load1":\([0-9.]*\).*/\1/p')"
  MR="$(printf '%s' "$J"  | sed -n 's/.*"mean_runnable":\([0-9.]*\).*/\1/p')"
  TOP="$(printf '%s' "$J" | sed -n 's/.*"buckets":{"\([^"]*\)":\([0-9.]*\).*/\1 \2/p')"
  [ -n "$LD" ] && [ -n "$MR" ] || {
    printf '%6s  %10s  %14s  %s\n' "$N" "PARSE?" "PARSE?" "(unparseable probe row — no point)"
    continue
  }

  printf '%6s  %10s  %14s  %s\n' "$N" "$LD" "$MR" "${TOP:-—}"
  ROWS="$ROWS$N $LD $MR
"
  printf '{"ts":"%s","run":"%s","label":"%s","n":%s,"load1":%s,"mean_runnable":%s,"settle_s":%s,"measure_s":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RUN_TS" "$LABEL" "$N" "$LD" "$MR" "$SETTLE_S" "$MEASURE_S" >> "$OUT" 2>/dev/null || true
done

teardown

printf '\n'
printf '%s' "$ROWS" | regress

exit 0
