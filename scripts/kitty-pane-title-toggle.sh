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
# THE FIX: RESERVE THE ROW IN TOP PADDING, AND HAND IT BACK WHEN THE BAR WANTS IT. The main config
# keeps exactly ONE CELL of top padding permanently. When the bar appears, the whole config is
# swapped in ONE relayout to a variant whose top padding is zero. The cell area gains precisely the
# row the bar consumes, so the row count never changes, the PTY is never resized, and no child is
# ever signalled. The first text row also lands on the same absolute pixel, because the bar fills
# exactly the band the padding vacated — so nothing moves.
#
# 🚨 THE RESERVOIR IS NOT A LOST ROW, AND THAT IS THE WHOLE POINT (2026-09-16). The earlier pairing
# kept the OFF bottom padding at 10pt and paid the reservoir ON TOP of it (`26 5 10 5`), which put
# total vertical padding at 36pt and did cost a row — 30 -> 29 — the cost the operator rejected
# twice. Spending the BOTTOM padding into the top instead keeps the total at one cell, so the OFF
# row count is the SAME as today's. See config/kitty.conf § 3 for the full measurement.
#
# MEASURED 2026-09-16, isolated kitty 0.48.2 instance, this kitty.conf, Monaco 18, 45px cell,
# 2-pane split, SIGWINCH-trapping children — ALL IN ONE RUN:
#   TODAY  `10 5`                            rows 30,30
#   OFF    `22.5 5 0 5` + min_windows 0      rows 30,30   <- no permanent row: same as today
#   ON     `0 5 0 5`    + min_windows 1      rows 30,30   across 6 swaps, SIGWINCH 0
#   positive control (forced row change)     rows 27,27   SIGWINCH 1 -> 2   (the counter is live)
#   content row 1, screenshot, static pane:  y 465..644 in BOTH states — pixel-identical
#   only changed pixels OFF->ON:             ONE band, y 420..464 = exactly 45px = one cell
#
# THE RESERVOIR MUST EQUAL THE CELL HEIGHT IN PIXELS, NOT MERELY EXCEED IT. 23pt rounds to 46px
# against a 45px cell and leaves a visible 1px creep (measured: content row 1 at 466 vs 465);
# 22.5pt is 45px exactly and measures 0. `window_padding_width` takes floats — use them.
# 22.5pt is `font_size 18` x `modify_font cell_height 94%`. CHANGE EITHER AND THIS BREAKS SILENTLY
# (the shift returns, nothing errors) — tests/kitty-title-zero-shift.bats pins the coupling.
#
# ATOMICITY IS THE TRICK. Two remote commands (`action toggle_window_title_bars` then
# `set-spacing`) are two relayouts and measured 16 -> 15 -> 16, i.e. TWO signals — worse than the
# defect. One `load-config` of a complete file is one relayout and gives none. `-o` overrides were
# tried first and do NOT reproduce it reliably; a real conf file does, which is why the ON half is
# a file that `include`s the main config rather than a list of overrides. `kitty @ load-config`
# also RESPECTS `-o` overrides from the original invocation unless `--ignore-overrides` is passed,
# which is the likeliest instrument error behind the 2026-09-14 "measured DEAD on this machine".
#
# WHY A CONFIG SWAP RATHER THAN THE BUILT-IN ACTION — the second half of the operator's ask.
# kitty hides the bars again after ANY drag completes, including a drag that puts the pane back
# where it started. That is `TabManager._clear_force_show_title_bars`, and all it does is set the
# per-tab `force_show_title_bars` bool to False. The bars here are held up by a CONFIG value
# instead: `Layout.__call__` computes `show_title_bar = force_show or (min_windows > 0 and
# visible >= min_windows)`, so with min_windows 1 the drag's clear has no authority and the title
# stays up. Measured, same synthetic no-op drag in both arms (order unchanged, one tab throughout):
#   today's config, bars up via the action:  29,29 -> 30,30   the title VANISHES
#   this pair, bars up via min_windows:      30,30 -> 30,30   x3, bar still at y=221pt
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

# The state file is the only record of which half is loaded — kitty exposes no way to read the
# live `window_title_bar_min_windows` back, and KITTY_PID is INHERITED rather than set by kitty
# for `launch --type=background` children (measured 2026-09-16: a child reported the pid of an
# unrelated kitty it had inherited the var from), so it cannot key per-instance state either.
# Consequence, and it is the whole of it: after a kitty restart the file may still read `on`
# while the fresh instance is showing the OFF config, and the next press is a no-op that
# re-loads OFF. One dead press, self-correcting on the second. `… off` / `… on` force a state.
# 🚨 --ignore-overrides IS LOAD-BEARING, and without it this script is a silent no-op on a
# long-lived kitty. `kitty @ load-config` RESPECTS overrides from the kitty invocation AND from a
# PREVIOUS load-config, by documented design, unless this flag is passed. Any `-o` that ever
# reached this instance therefore pins the very setting the pairing flips, and the toggle reports
# success while nothing on screen moves. MEASURED on the operator's live kitty (pid 97084, 12
# panes), one variable, rows via `kitty @ ls`:
#     load-config mw=1 WITHOUT the flag ... [8,8,8,8,8,45,45,45,45,47,47,47]  (identical — inert)
#     load-config mw=1 WITH    the flag ... [7,7,7,7,7,44,44,44,44,45,45,46]  (the bar drew)
# That instance was launched with NO `-o` in its argv, so the sticky override came from an earlier
# load-config, not from startup — which is why nothing about the process looked wrong. This is the
# mechanism kitty.conf §3 originally recorded as "measured DEAD ON THIS MACHINE": the reading was
# RIGHT about his windows, and the isolated-instance re-measurement that appeared to refute it was
# testing a kitty too young to have accumulated an override. A fresh instance cannot express this
# bug; only a long-lived one can.
if [ "$next" = on ]; then kitty @ load-config --ignore-overrides "$CONF_ON"; else kitty @ load-config --ignore-overrides "$CONF_OFF"; fi
printf '%s' "$next" > "$STATE"
