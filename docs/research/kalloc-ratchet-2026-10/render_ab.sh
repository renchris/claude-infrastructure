#!/usr/bin/env bash
# render_ab.sh — no-root A/B: does TERMINAL RENDERING drive data.kalloc.1024?
#
# Prior evidence (docs/research/panic-2026-08-24-evidence/kernel-zone.md §2) inherited upstream
# claude-code#44824's chain: TUI redraw flood → terminal → WindowServer → AGX GPU driver → 1 KiB
# data buffers never freed. This tests the terminal half of that chain directly, in a THROWAWAY
# kitty instance (--single-instance=no: its own process, never a live pane):
#   control : sleep D seconds
#   idle    : a kitty window that exists for D seconds and draws nothing new
#   flood   : a kitty window that scrolls text continuously for D seconds
# Each arm's zone delta is printed; the verdict is flood - idle and idle - control, over ROUNDS.
# Usage: render_ab.sh [ROUNDS=3] [D=40]
set -uo pipefail
ROUNDS="${1:-3}"; D="${2:-40}"
KITTY="${KITTY_BIN:-/opt/homebrew/bin/kitty}"
zone() { /usr/bin/zprint data.kalloc.1024 | awk '$1=="data.kalloc.1024"{print $7}'; }
arm() { # name → prints "name dz dt"
  local z0 t0 z1 t1
  z0="$(zone)"; t0="$(date +%s)"
  case "$1" in
    control) sleep "$D" ;;
    idle)  "$KITTY" --single-instance=no --config NONE -o macos_quit_when_last_window_closed=yes -o confirm_os_window_close=0 -o allow_remote_control=no \
             --title kalloc-probe-idle sh -c "sleep $D" >/dev/null 2>&1 ;;
    flood) "$KITTY" --single-instance=no --config NONE -o macos_quit_when_last_window_closed=yes -o confirm_os_window_close=0 -o allow_remote_control=no \
             --title kalloc-probe-flood sh -c "end=\$((\$(date +%s)+$D)); while [ \$(date +%s) -lt \$end ]; do cat /usr/share/dict/words; done" >/dev/null 2>&1 ;;
  esac
  z1="$(zone)"; t1="$(date +%s)"
  printf '{"arm":"%s","dz":%d,"dt":%d,"rate":%.1f}\n' "$1" $((z1 - z0)) $((t1 - t0)) \
    "$(awk -v a=$((z1 - z0)) -v b=$((t1 - t0)) 'BEGIN{print (b ? a/b : 0)}')"
}
for _ in $(seq 1 "$ROUNDS"); do
  for a in control idle flood; do arm "$a"; done
done
