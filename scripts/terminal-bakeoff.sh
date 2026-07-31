#!/bin/bash
# terminal-bakeoff.sh — drive a candidate terminal to N panes and measure it, so a terminal choice
# rests on a reading from THIS box rather than on a reading of somebody's source tree.
#
# WHY A SEPARATE DRIVER. scripts/terminal-bench.sh measures whatever is already running; it cannot
# create the condition under test. The condition that broke this box was ~30 concurrent panes, and
# no candidate has ever been run at that scale here. Architecture reading gets us a hypothesis
# ("WezTerm presents one CAMetalLayer per WINDOW, iTerm2 one MTKView per PANE"); only this produces
# the number.
#
# TWO STAGES, and stage A is the one that settles the architecture question.
#   A  structural (--idle):  N panes running an idle shell. Costs almost no CPU, so it is safe to
#      run beside the operator's live fleet, and it still exposes the decisive axis — compositor
#      objects, threads and ports per pane. If a terminal really does present one surface per
#      window, that shows up here with idle panes and does not need load to reveal it.
#   B  loaded (default):     N panes each running scripts/tui-load.sh, the Ink-shaped synthetic
#      load. This is the responsiveness/CPU comparison, and it is genuinely heavy — 30 panes
#      repainting at 10 fps is approximately the operator's real workload.
#
# 🚨 STAGE B PERTURBS A SHARED MACHINE. This box hosts the operator's live Claude Code sessions.
# Run stage B only when the fleet is quiet, start at a low --panes and climb, and read the abort
# guard below. The instrument must never be the cause of the outage it is studying.
#
# SAFETY. Only ever touches the terminal it launched: it records that app's pid at start and tears
# down by that pid. It never enumerates or closes iTerm2 panes, and iTerm2 is measure-only (the
# incumbent baseline is taken from the operator's already-running instance — creating 30 fresh
# iTerm2 panes would disturb the very sessions being protected).
#
# USAGE
#   scripts/terminal-bakeoff.sh --app wezterm --panes 20 --idle
#   scripts/terminal-bakeoff.sh --app kitty   --panes 30 --fps 10 --duration 180
#   scripts/terminal-bakeoff.sh --app iTerm2  --measure-only          # incumbent, no pane creation
set -uo pipefail

APP=""; PANES=20; FPS=10; DURATION=180; IDLE=0; MEASURE_ONLY=0; OUT=""
MAXLOAD="${BAKEOFF_MAXLOAD:-40}"
while [ $# -gt 0 ]; do
  case "$1" in
    --app)          APP="${2:-}"; shift 2 ;;
    --panes)        PANES="${2:-20}"; shift 2 ;;
    --fps)          FPS="${2:-10}"; shift 2 ;;
    --duration)     DURATION="${2:-180}"; shift 2 ;;
    --idle)         IDLE=1; shift ;;
    --measure-only) MEASURE_ONLY=1; shift ;;
    --out)          OUT="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '1,40p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$APP" ] || { echo "terminal-bakeoff: --app is required" >&2; exit 2; }

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  _l="$(readlink "$SELF")"; case "$_l" in /*) SELF="$_l" ;; *) SELF="$(cd "$(dirname "$SELF")" && pwd -P)/$_l" ;; esac
done
REPO="${CC_REPO:-$(cd "$(dirname "$SELF")/.." && pwd -P)}"
BENCH="$REPO/scripts/terminal-bench.sh"
LOAD="$REPO/scripts/tui-load.sh"

# ── abort guard ───────────────────────────────────────────────────────────────────────────────────
# loadavg is a poor attribution signal (measured on this box: a 2.05x swing at CONSTANT session
# count — memory load-is-not-a-function-of-session-count), so it is NOT used to draw conclusions.
# It is used only as a circuit breaker: a bad number here means "the box is already busy, do not add
# 30 repainting panes to it", which is a decision loadavg is adequate for.
loadnow() { uptime | sed -E 's/.*load averages?: ([0-9.]+).*/\1/'; }
L="$(loadnow)"
if awk -v l="$L" -v m="$MAXLOAD" 'BEGIN{exit !(l+0 > m+0)}'; then
  echo "terminal-bakeoff: REFUSING — loadavg $L exceeds $MAXLOAD. Re-run when the box is quieter" >&2
  echo "verdict=REFUSED"; exit 4
fi

PANE_CMD="exec /bin/sh -c 'while :; do sleep 3600; done'"
[ "$IDLE" = 1 ] || PANE_CMD="exec bash '$LOAD' --fps $FPS --duration $DURATION --label bakeoff --stats ${TMPDIR:-/tmp}/bakeoff-load.tsv"

echo "== terminal-bakeoff  app=$APP panes=$PANES stage=$([ "$IDLE" = 1 ] && echo A-idle || echo B-loaded) loadavg=$L =="

# ── spawn N panes ─────────────────────────────────────────────────────────────────────────────────
# One window, N panes — the same shape for every candidate, because comparing a 30-pane window
# against 6 windows of 5 panes would measure the LAYOUT rather than the terminal.
SPAWNED=0
spawn_wezterm() {
  local cli=/opt/homebrew/bin/wezterm
  [ -x "$cli" ] || cli="$(command -v wezterm)"
  open -a WezTerm; sleep 4
  # ROUND-ROBIN OVER EVERY PANE, not repeated splits of the newest one. WezTerm halves the target
  # pane, so always splitting the most recent one shrinks that branch geometrically and hits the
  # minimum pane size fast: measured 9 of 24 requested before it refused. Splitting every existing
  # pane once per round grows a BALANCED tree (1→2→4→8→16→32), which reaches 30+ at usable sizes.
  SPAWNED=1
  local round_progressed=1
  while [ "$SPAWNED" -lt "$PANES" ] && [ "$round_progressed" = 1 ]; do
    round_progressed=0
    local ids; ids="$(timeout 25 "$cli" cli list --format json 2>/dev/null \
                      | sed -n 's/.*"pane_id": *\([0-9]*\).*/\1/p' | sort -un)"
    [ -n "$ids" ] || break
    local id
    for id in $ids; do
      [ "$SPAWNED" -ge "$PANES" ] && break
      local dir=--right; [ $(( SPAWNED % 2 )) -eq 0 ] && dir=--bottom
      if timeout 25 "$cli" cli split-pane --pane-id "$id" "$dir" \
           -- /bin/sh -c "$PANE_CMD" >/dev/null 2>&1; then
        SPAWNED=$(( SPAWNED + 1 )); round_progressed=1
      fi
    done
  done
  # A round in which NOTHING could be split means the layout is saturated — report the true count
  # rather than looping forever against a terminal that is refusing.
}
spawn_kitty() {
  local sock="unix:${TMPDIR:-/tmp}/kitty-bakeoff"
  /Applications/kitty.app/Contents/MacOS/kitty -o allow_remote_control=yes --listen-on "$sock" \
    -o enabled_layouts=grid --detach >/dev/null 2>&1
  sleep 3
  local i=1
  while [ "$i" -lt "$PANES" ]; do
    /Applications/kitty.app/Contents/MacOS/kitty @ --to "$sock" launch --location=split \
      /bin/sh -c "$PANE_CMD" >/dev/null 2>&1 || break
    i=$((i+1)); SPAWNED=$i
  done
}

if [ "$MEASURE_ONLY" = 0 ]; then
  case "$APP" in
    wezterm|WezTerm) spawn_wezterm ;;
    kitty)           spawn_kitty ;;
    iTerm2)          echo "  iTerm2 is measure-only here — creating panes would disturb live sessions" >&2
                     MEASURE_ONLY=1 ;;
    *) echo "  ✗ no spawn strategy for '$APP'; use --measure-only" >&2; exit 2 ;;
  esac
  echo "  spawned $SPAWNED of $PANES requested panes"
  # An under-spawn silently changes the denominator of every per-pane figure below, so it is named
  # rather than absorbed.
  [ "$SPAWNED" -lt "$PANES" ] && echo "  ⚠ UNDER-SPAWNED — per-pane figures use $SPAWNED, not $PANES"
  sleep 5
fi

# ── MEASURE THE DENOMINATOR, DO NOT COUNT IT ──────────────────────────────────────────────────────
# Every per-pane figure divides by this number, so trusting the spawner's own tally is the classic
# denominator error (memory positive-control-the-denominator). The tally is wrong whenever a split
# silently fails, and wrong by the pre-existing pane count whenever the app was ALREADY running —
# both of which happened during development. Ask the terminal how many panes it actually has.
actual_panes() {
  case "$APP" in
    wezterm|WezTerm)
      local cli=/opt/homebrew/bin/wezterm; [ -x "$cli" ] || cli="$(command -v wezterm)"
      timeout 25 "$cli" cli list --format json 2>/dev/null \
        | sed -n 's/.*"pane_id": *\([0-9]*\).*/\1/p' | sort -un | wc -l | tr -d ' ' ;;
    kitty)
      timeout 25 /Applications/kitty.app/Contents/MacOS/kitty @ --to "unix:${TMPDIR:-/tmp}/kitty-bakeoff" ls 2>/dev/null \
        | grep -c '"is_focused"' | tr -d ' ' ;;
    *) echo 0 ;;
  esac
}
MEASURED_PANES="$PANES"
[ "$SPAWNED" -gt 0 ] && MEASURED_PANES="$SPAWNED"
if [ "$MEASURE_ONLY" = 0 ]; then
  _live="$(actual_panes)"
  if [ "${_live:-0}" -gt 0 ] && [ "$_live" != "$MEASURED_PANES" ]; then
    echo "  ⚠ denominator corrected: spawner counted $MEASURED_PANES, terminal reports $_live live panes"
    MEASURED_PANES="$_live"
  fi
fi
bash "$BENCH" --app "$APP" --panes "$MEASURED_PANES" --interval 0 ${OUT:+--out "$OUT"}

echo "  (teardown: quit $APP from its own UI, or 'pkill -x $APP' — this script does not kill what it did not launch)"
