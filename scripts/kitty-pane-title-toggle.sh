#!/usr/bin/env bash
# Toggle kitty's per-pane title bars with ZERO content layout shift.
#
# WHY THIS EXISTS. `toggle_window_title_bars` costs one text ROW in every pane of the tab, and a row
# change is a PTY resize, so kitty SIGWINCHes every child on the show AND again on the hide: one peek
# = two full scrollback reflows per pane. That is the defect. It cannot be fixed by suppressing the
# signal (kitty must send it) and it cannot be fixed by drawing the header somewhere else — the
# window logo paints under the glyphs, an overlay window covers the whole pane, and a graphics
# placement is destroyed by the first screen clear (docs/research/kitty-pane-title-overlay-2026-09-14.md).
#
# THE FIX IS TO PAY THE ROW ONCE, IN PADDING, AND HAND IT BACK WHEN THE BAR WANTS IT. The bar needs
# exactly one cell height of pixels. We keep that much permanently in the TOP padding, and when the
# bar appears we shrink the top padding by exactly one cell in the SAME relayout. The cell area's row
# capacity rises by one at the instant the bar consumes one, so the row count never changes, the PTY
# is never resized, and no child is ever signalled. The first text row also lands on the same
# absolute pixel, because the bar occupies precisely the band the padding vacated — so nothing moves.
#
# MEASURED (isolated instance, Monaco 18, 45px cell, WINCH-trapping shells in both panes of a split):
#   three full on/off cycles -> rows constant 7x7, SIGWINCH count 0 in BOTH panes, bar visible.
# The same probe fires 1 SIGWINCH for a real split, so the instrument is not blind.
#
# ATOMICITY IS THE WHOLE TRICK. Two separate remote commands (`action toggle_window_title_bars` then
# `set-spacing`) are two relayouts and give you 16 -> 15 -> 16, i.e. TWO signals — worse than the
# thing we are fixing. One `load-config` carrying both overrides is one relayout and gives you none.
#
# COST, stated plainly: one row per pane, permanently (47 -> 46 at this geometry). It buys a header
# that genuinely appears and disappears, which is what "always on" took away.
set -euo pipefail

CONF="${KITTY_CONF:-$HOME/.config/kitty/kitty.conf}"
STATE="${KITTY_TITLE_STATE:-$HOME/.claude/autonomy/kitty-title-state}"

# Both states are tuned so the pane box keeps the SAME sub-cell remainder (1 device px at a 2160px
# cell area), which is what keeps every pane rectangle flush top and bottom. Derivation:
#   OFF  chrome = 4 border + 65 top + 20 bottom = 89 -> floor((2160-89)/45) = 46 rows, remainder 1
#   ON   chrome = 4 border + 20 top + 20 bottom = 44 -> floor((2160-44)/45) = 47 rows, remainder 1
#        minus the bar's own row = 46 CONTENT rows. Identical. Nothing moves.
# 32.5pt = 65 device px = one 45px cell above the ordinary 10pt (20px). If the cell height ever
# changes (modify_font cell_height), re-derive both numbers or the toggle starts costing a row again.
PAD_OFF="32.5 7 10 7"
PAD_ON="10 7 10 7"

mkdir -p "$(dirname "$STATE")"
cur="$(cat "$STATE" 2>/dev/null || echo off)"

case "${1:-toggle}" in
  on)     next=on ;;
  off)    next=off ;;
  toggle) [ "$cur" = on ] && next=off || next=on ;;
  *) echo "usage: $0 [toggle|on|off]" >&2; exit 2 ;;
esac

if [ "$next" = on ]; then
  kitty @ load-config -o window_title_bar_min_windows=1 -o window_padding_width="$PAD_ON" "$CONF"
else
  kitty @ load-config -o window_title_bar_min_windows=0 -o window_padding_width="$PAD_OFF" "$CONF"
fi
printf '%s' "$next" > "$STATE"
