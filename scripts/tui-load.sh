#!/bin/bash
# tui-load.sh — a synthetic stand-in for one Claude Code pane, for terminal bake-offs.
#
# WHY A SYNTHETIC LOAD. Comparing terminals at 30 panes needs 30 panes under REPRESENTATIVE load.
# Using 30 real Claude Code sessions is wrong twice: it burns quota on a rendering experiment, and
# it is not reproducible — real sessions differ in output volume minute to minute, so a difference
# between two terminals could not be attributed to the terminal. This produces an IDENTICAL,
# parameterised load in every pane and in every candidate, which is what makes the comparison fair.
#
# WHAT IT IMITATES, and why those specific properties. Claude Code's TUI is Ink (React for the
# terminal). Against a terminal emulator, that means:
#   · ALTERNATE SCREEN (\e[?1049h). This is the property that matters most on this box: iTerm2's
#     `disableAdaptiveFrameRateInInteractiveApps` defaults to YES, which EXEMPTS alternate-screen
#     panes from the adaptive frame-rate throttle — so a TUI pane is throttled differently from a
#     scrolling log pane. A load generator that just printed lines would measure the wrong regime.
#   · FULL-FRAME REPAINT on state change, addressed by cursor positioning rather than scrolling.
#   · 24-BIT COLOUR, which costs the parser and the glyph cache far more than plain ASCII.
#   · A ~10 Hz heartbeat (the spinner) even when nothing is happening — this is why 30 idle agent
#     panes are not free, and why "idle" is the case the operator actually leaves running for hours.
#
# WHAT IT DELIBERATELY DOES NOT IMITATE: token streaming bursts, images, and scrollback growth.
# Those vary per session and would reintroduce the reproducibility problem. This is a floor on the
# real cost, not an estimate of it — state that plainly wherever its numbers are used.
#
# USAGE
#   scripts/tui-load.sh                          # 10 fps, 300 s, auto-size
#   scripts/tui-load.sh --fps 10 --duration 600
#   scripts/tui-load.sh --fps 30 --duration 300  # stress regime, NOT the representative one
# Stats (frames drawn, bytes written, achieved fps) are appended to --stats on exit, because the
# alternate screen is torn down and anything printed to stdout would be lost with it — a diagnostic
# that is blank exactly when you need it is the failure in memory
# negative-array-slice-empties-the-diagnostic.
set -uo pipefail

FPS=10; DURATION=300; STATS="${TMPDIR:-/tmp}/tui-load-stats.tsv"; LABEL="${TUI_LOAD_LABEL:-pane}"
while [ $# -gt 0 ]; do
  case "$1" in
    --fps)      FPS="${2:-10}"; shift 2 ;;
    --duration) DURATION="${2:-300}"; shift 2 ;;
    --stats)    STATS="${2:-}"; shift 2 ;;
    --label)    LABEL="${2:-pane}"; shift 2 ;;
    -h|--help)  sed -n '1,32p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

COLS="$(tput cols 2>/dev/null || echo 80)"
ROWS="$(tput lines 2>/dev/null || echo 24)"
[ "$COLS" -gt 4 ] 2>/dev/null || COLS=80
[ "$ROWS" -gt 4 ] 2>/dev/null || ROWS=24
BODY_ROWS=$(( ROWS - 3 ))
[ "$BODY_ROWS" -ge 1 ] || BODY_ROWS=1

FRAMES=0; BYTES=0; PERL_ELAPSED=""
# $SECONDS is a bash builtin. `$(date +%s)` in the loop condition would be one fork PER FRAME.

# Restore the terminal on ANY exit path. Without this an interrupted run leaves the pane on the
# alternate screen with a hidden cursor, which silently corrupts every subsequent measurement in
# that pane.
cleanup() {
  printf '\e[?25h\e[?1049l'
  local elapsed afps
  # Prefer the emitter's own float elapsed. Integer $SECONDS quantises a short run badly: at
  # --duration 2 it can only report 1, 2 or 3, which is enough to swing achieved-fps across the
  # SUSPECT threshold on a generator that is working correctly.
  elapsed="${PERL_ELAPSED:-$SECONDS}"
  awk -v e="$elapsed" 'BEGIN{ exit !(e+0 > 0) }' || elapsed=1
  afps="$(awk -v f="$FRAMES" -v e="$elapsed" 'BEGIN{printf "%.2f", f/e}')"
  # A run that did not achieve its requested rate did not deliver the load the experiment assumed —
  # either the generator was starved (producer confound) or the terminal could not keep up (a real
  # finding, but a different one). Either way the row is not comparable, and saying so HERE is what
  # stops it being read later as a clean measurement.
  local flag
  flag="$(awk -v a="$afps" -v r="$FPS" 'BEGIN{ d=a-r; if(d<0)d=-d; print (r>0 && d/r>0.2) ? "SUSPECT" : "OK" }')"
  [ -n "$STATS" ] && printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%FT%TZ)" "$LABEL" "$$" "$FRAMES" "$BYTES" "${elapsed}s" "$afps" "$NAP_STRATEGY" "$flag" >> "$STATS"
  [ "$flag" = SUSPECT ] && printf 'tui-load: SUSPECT — requested %s fps, achieved %s\n' "$FPS" "$afps" >&2
  exit 0
}
trap cleanup EXIT INT TERM

SPIN='|/-\'
SLEEP="$(awk -v f="$FPS" 'BEGIN{ if(f<=0) f=1; printf "%.4f", 1/f }')"

# ── PRECOMPUTE THE FRAMES ─────────────────────────────────────────────────────────────────────────
# 🚨 THE PRODUCER MUST NOT BE THE BOTTLENECK, and the first version of this loop was.
# It built each frame inline with one command substitution PER ROW: ~21 forks per frame, which at
# 10 fps x 30 panes is ~6,300 forks/second of pure PRODUCER cost. Measured effect: 6.67 fps achieved
# against 10 requested — the generator was CPU-bound in bash before the terminal drew anything. A
# load generator whose own cost scales with pane count measures ITSELF, not the terminal, and would
# have contaminated every cross-terminal comparison in the same direction. (This box is already
# known to be fork-dominated: memory load-is-not-a-function-of-session-count found 49% of the hook
# chain's cost was pure scheduler queueing caused by its own forks.)
# So: frames are built ONCE into a cycle, and the hot loop performs ZERO forks — no subshell, no
# `sleep`, no `date`. Verify with the achieved-fps column in --stats; if it is not within a few
# percent of --fps, the numbers from that run are not comparable and must not be used.
CYCLE=8
declare -a FRAME
n=$(( COLS - 12 )); [ "$n" -gt 0 ] || n=8
pad=""
while [ "${#pad}" -lt "$n" ]; do pad+="········································"; done
pad="${pad:0:$n}"

k=0
while [ "$k" -lt "$CYCLE" ]; do
  s="${SPIN:$(( k % 4 )):1}"
  f=$'\e[H\e[2K\e[38;2;120;200;255m'"● ${LABEL}"$'\e[0m'"  ${s}  ${COLS}x${ROWS}"
  # Every row repainted with a shifting colour ramp, so no terminal can win the comparison with a
  # damage-region optimisation that an unchanging frame would hand it for free.
  r=2
  while [ "$r" -le "$BODY_ROWS" ]; do
    g=$(( (k * 23 + r * 7) % 200 + 55 ))
    b=$(( (k * 31 + r * 11) % 200 + 55 ))
    f+=$'\e['"${r}"$';1H\e[2K\e[38;2;90;'"${g}"$';'"${b}"$'m'"${pad}"$'\e[0m'
    r=$(( r + 1 ))
  done
  f+=$'\e['"${ROWS}"$';1H\e[2K\e[38;2;150;150;150m'"synthetic TUI load · ${LABEL}"$'\e[0m'
  FRAME[$k]="$f"
  k=$(( k + 1 ))
done
FRAME_BYTES="${#FRAME[0]}"

# ── EMISSION STRATEGY ─────────────────────────────────────────────────────────────────────────────
# THE RATE MUST NOT DEPEND ON HOW BUSY THE BOX IS, because how busy the box is IS the variable under
# test. Two bash strategies were tried and both fail that requirement on this machine:
#   · `read -t` builtin (forkless) needs bash >= 4 for a fractional timeout; macOS ships 3.2.57,
#     where it errors instantly — a busy loop measured at 7,651 fps against a requested 10.
#   · `sleep` per frame costs a fork, and fork latency rises with load: at loadavg 13.6 a requested
#     5 fps delivered 3.33 and a requested 10 delivered 9.0. That is a BIAS, not an offset — the
#     busier a candidate makes the box, the lighter the load this generator hands it, which
#     systematically flatters the worse terminal.
# tools/terminal-bench/tui-emit.pl is deadline-corrected and forkless: 10.00 fps exactly at the same
# loadavg. perl is present at /usr/bin/perl on every macOS. The bash `sleep` loop is kept ONLY as a
# fallback, and the strategy actually used is recorded in the stats row so no reader has to guess
# which one produced a number.
EMITTER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/tools/terminal-bench/tui-emit.pl"
NAP_STRATEGY="sleep"
[ -f "$EMITTER" ] && [ -x /usr/bin/perl ] && NAP_STRATEGY="perl"
nap() { sleep "$SLEEP"; }

printf '\e[?1049h\e[?25l'          # alternate screen + hide cursor: the Ink regime

# Reset the clock at the LOOP boundary. $SECONDS otherwise counts from script start, so start-up
# (tput, the awk fork, precomputing the frame cycle) is charged against the delivery rate: it both
# truncates the run and deflates achieved-fps. Measured effect at --duration 2: ~4.5 fps reported
# for a 5 fps run, which tripped the SUSPECT flag on a generator that was working correctly. The
# achieved rate must describe the LOAD-DELIVERY phase, which is the only part a terminal sees.
SECONDS=0

if [ "$NAP_STRATEGY" = perl ]; then
  # Hand the precomputed cycle to the deadline-corrected emitter. It reports what it ACTUALLY
  # delivered, which is what the stats row must carry — never the requested rate.
  FRAMEFILE="${TMPDIR:-/tmp}/tui-load.$$.frames"
  RESULTFILE="${TMPDIR:-/tmp}/tui-load.$$.result"
  : > "$FRAMEFILE"
  k=0
  while [ "$k" -lt "$CYCLE" ]; do printf '%s\0' "${FRAME[$k]}" >> "$FRAMEFILE"; k=$(( k + 1 )); done
  /usr/bin/perl "$EMITTER" "$FRAMEFILE" "$FPS" "$DURATION" "$RESULTFILE"
  if [ -s "$RESULTFILE" ]; then
    FRAMES="$(sed -n 's/.*frames=\([0-9]*\).*/\1/p' "$RESULTFILE")"
    BYTES="$(sed -n 's/.*bytes=\([0-9]*\).*/\1/p' "$RESULTFILE")"
    PERL_ELAPSED="$(sed -n 's/.*elapsed=\([0-9.]*\).*/\1/p' "$RESULTFILE")"
  fi
  rm -f "$FRAMEFILE" "$RESULTFILE"
else
  while [ "$SECONDS" -lt "$DURATION" ]; do
    printf '%s' "${FRAME[$(( FRAMES % CYCLE ))]}"
    BYTES=$(( BYTES + FRAME_BYTES ))
    FRAMES=$(( FRAMES + 1 ))
    nap
  done
fi
