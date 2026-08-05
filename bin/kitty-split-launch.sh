#!/usr/bin/env bash
# kitty-split-launch.sh — open a new kitty split ANCHORED to a specific pane (default: the
# calling pane), never wherever kitty's globally-active tab happens to be.
#
# WHY THIS EXISTS. `kitty @ launch --location=vsplit` places the new window relative to kitty's
# INSTANCE-WIDE active tab — not the tab containing the pane that issued the command. All of a
# kitty instance's OS windows share one control socket and one "active tab" pointer (whichever
# tab was focused most recently), so `kitty @ launch --location=vsplit` fired from pane A, while
# the user's focus sits on pane B in a different OS window, splits B's tab — not A's.
#
# Measured 2026-08-05 (crash-recovery resume): three resumed sessions, launched this way from a
# Bash tool call whose own pane WAS the intended anchor, landed in an unrelated OS window instead
# — twice (once because the caller's own window id had been misidentified, once because kitty's
# active-tab default was trusted at all) — and had to be relocated by hand with
# `kitty @ detach-window --target-tab`.
#
# THE FIX. `kitty @ launch --match "window_id:<anchor>" --next-to "id:<anchor>"` anchors the
# split to an EXPLICITLY NAMED pane regardless of kitty's active-tab state. This is not a new
# discovery — bin/it2-kitty (Agent Teams' teammate-pane creation) has used exactly this pattern
# since it was written, and has never hit the bug above, because it always names its anchor
# rather than trusting kitty's default. This script is that pattern, standalone, for any other
# caller (resume flows, handoff, ad hoc automation) that wants "split next to a specific pane"
# instead of "split wherever kitty's UI focus happens to be".
#
# USAGE
#   kitty-split-launch.sh [--anchor <kitty-window-id>] [--location vsplit|hsplit] [--cwd DIR]
#                          [--title T] [--keep-focus] -- CMD [ARGS...]
#
#   --anchor    kitty window id to split relative to. Default: $KITTY_WINDOW_ID — i.e. splits
#               land next to whoever RAN this script, not wherever kitty's UI focus happens to
#               be. Pass an explicit id (from `kitty @ ls`) to direct the split elsewhere — this
#               is the "direct them to other windows as needed" escape hatch; the default is not
#               a restriction, it is just what happens when nothing else is asked for.
#   --location  vsplit (right of anchor, default) | hsplit (below anchor)
#
# Prints kitty @ launch's own stdout (the new window id) — chain further splits by passing that
# id as the next call's --anchor, which is how you stack more than one pane in the same column.
set -euo pipefail

anchor="${KITTY_WINDOW_ID:-}"
location="vsplit"
cwd=""
title=""
keep_focus=()

while [ $# -gt 0 ]; do
  case "$1" in
    --anchor) anchor="$2"; shift 2 ;;
    --location) location="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --keep-focus) keep_focus=(--keep-focus); shift ;;
    --) shift; break ;;
    *) echo "kitty-split-launch: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [ -z "$anchor" ]; then
  echo "kitty-split-launch: no anchor — pass --anchor <window-id> or run from inside kitty (KITTY_WINDOW_ID unset)" >&2
  exit 2
fi
if [ $# -eq 0 ]; then
  echo "kitty-split-launch: no command given (after --)" >&2
  exit 2
fi

args=(launch --type=window --location="$location" --match "window_id:$anchor" --next-to "id:$anchor")
[ -n "$cwd" ] && args+=(--cwd "$cwd")
[ -n "$title" ] && args+=(--title "$title")
args+=("${keep_focus[@]}")
args+=(-- "$@")

exec kitty @ "${args[@]}"
