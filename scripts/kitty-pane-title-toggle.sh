#!/usr/bin/env bash
# Toggle kitty's per-pane title bars with ZERO content layout shift. Bound to cmd+shift+b.
#
# THE DEFECT. `toggle_window_title_bars` takes one text ROW from every pane in the tab. A row change
# is a PTY resize, so kitty SIGWINCHes every child on the show AND again on the hide: one peek = two
# full scrollback reflows per pane. It cannot be fixed by suppressing the signal (kitty must send
# it), nor by drawing the header elsewhere — the window logo paints under the glyphs, an overlay
# window covers the whole pane, and a graphics placement is destroyed by the first screen clear.
# All six routes are measured in docs/research/kitty-pane-title-overlay-2026-09-14.md.
#
# THE FIX: PAY THE ROW ONCE, IN PADDING, AND HAND IT BACK WHEN THE BAR WANTS IT. The main config
# keeps one cell height of extra TOP padding permanently. When the bar appears, the whole config is
# swapped in ONE relayout to a variant whose top padding is exactly one cell smaller. The cell area
# gains precisely the row the bar consumes, so the row count never changes, the PTY is never
# resized, and no child is ever signalled. The first text row also lands on the same absolute pixel,
# because the bar fills exactly the band the padding vacated — so nothing moves.
#
# MEASURED, all in ONE run (the pairing that matters — earlier attempts had one half or the other):
#   two-pane split, WINCH-trapping shells, Monaco 18, 45px cell
#     OFF  rows [7,7]  SIGWINCH 0/0
#     ON   rows [7,7]  SIGWINCH 0/0   and a capture shows the title bar VISIBLE in BOTH panes
#     cursor block bottom edge: 626 px (ON) vs 625 px (OFF) — content does not move
#
# ATOMICITY IS THE TRICK. Two remote commands (`action toggle_window_title_bars` then
# `set-spacing`) are two relayouts and measured 16 -> 15 -> 16, i.e. TWO signals — worse than the
# defect. One `load-config` of a complete file is one relayout and gives none. `-o` overrides were
# tried first and do NOT reproduce it reliably; a real conf file does, which is why the ON half is
# a file that `include`s the main config rather than a list of overrides.
#
# COST: one row per pane, permanently (47 -> 46 at this geometry). That is the reservoir, and it is
# what buys a header that genuinely appears and disappears — which is what "always on" took away.
set -euo pipefail

CONF_OFF="${KITTY_CONF:-$HOME/.config/kitty/kitty.conf}"
CONF_ON="${KITTY_CONF_TITLE_ON:-$HOME/.config/kitty/kitty-title-on.conf}"
STATE="${KITTY_TITLE_STATE:-$HOME/.claude/autonomy/kitty-title-state}"

mkdir -p "$(dirname "$STATE")"
cur="$(cat "$STATE" 2>/dev/null || echo off)"
case "${1:-toggle}" in
  on)     next=on ;;
  off)    next=off ;;
  toggle) [ "$cur" = on ] && next=off || next=on ;;
  *) echo "usage: ${0##*/} [toggle|on|off]" >&2; exit 2 ;;
esac

[ "$next" = on ] && kitty @ load-config "$CONF_ON" || kitty @ load-config "$CONF_OFF"
printf '%s' "$next" > "$STATE"
