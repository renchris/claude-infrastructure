#!/usr/bin/env bash
# kitty-sitting.sh — the operator's whole kitty sitting (plan sitting S9) as one command each way.
#
#   bash ~/.claude/scripts/kitty-sitting.sh            arm (or re-raise) the sandbox and say what to do
#   bash ~/.claude/scripts/kitty-sitting.sh --verdict  read the answer back and record it
#
# WHAT THE SITTING ANSWERS, in one separate kitty window with two stacked panes:
#   1. does a hand drag reorder panes — by the blue title band (plain click and drag) and by the
#      ⌘⇧ + left-button chord anywhere in a pane (KITTY_DRAG_ACTION DoD #4 and #5, W4's Q9/Q12);
#   2. which chord to keep;
#   3. yes or no on adopting the patched build (the band, plus the two upstream NULL guards);
#   4. whether the default text-width band is right, or full width is wanted.
# Answers 2-4 are cc-decide packets; --verdict prints their ids.
#
# The sandbox runs the STAGED patched build (/Applications/kitty.app.staged, scripts/kitty-build-swap.sh)
# with the band on, through scripts/kitty-drag-w4.sh, which never addresses the operator's own kitty
# (its socket is outside the /tmp/kitty-* glob, it sends no signals, it writes nothing under
# ~/.config/kitty). If nothing patched is staged it falls back to the stock app and says that the
# build and width questions cannot be answered in this sitting. Nothing here sends synthetic input:
# the drag is the operator's hand.
#
# Exit: 0 armed / verdict read · 1 the sandbox could not be armed or read · 2 usage
set -uo pipefail

_self="$0"
while [ -L "$_self" ]; do _d="$(cd "$(dirname "$_self")" && pwd)"; _self="$(readlink "$_self")"; case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac; done
DIR="$(cd "$(dirname "$_self")" && pwd)"
W4="$DIR/kitty-drag-w4.sh"
STAGED_BIN="${KITTY_SITTING_BIN:-/Applications/kitty.app.staged/Contents/MacOS/kitty}"
STATE="${KITTY_SITTING_STATE:-$HOME/.claude/autonomy}"
RECORD="$STATE/kitty-sitting-S9.txt"
SOCK="/tmp/kdw4.sock"
BAND_CONF="/tmp/kdw4-sitting-band.conf"

case "${1:-}" in
  --verdict)
    mkdir -p "$STATE"
    out="$(bash "$W4" --verdict 2>&1)"; rc=$?
    printf '%s\n' "$out"
    { printf '# kitty sitting S9 — verdict read %s\n' "$(date '+%Y-%m-%d %H:%M %z')"; printf '%s\n' "$out"; } >> "$RECORD"
    echo
    echo "recorded in $RECORD"
    echo "Open kitty decisions (answer each with: cc-decide action <id>  or  cc-decide veto <id>):"
    cc-decide list --open 2>/dev/null | grep -i kitty || echo "  (none open)"
    exit "$rc" ;;
  '') ;;
  *) echo "usage: ${0##*/} [--verdict]" >&2; exit 2 ;;
esac

kit() { env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID /Applications/kitty.app/Contents/MacOS/kitten @ --to "unix:$SOCK" "$@"; }

# Already armed and alive: just bring it forward, so a second run never discards a baseline.
if [ -s /tmp/kdw4/before.json ] && kit ls >/dev/null 2>&1; then
  kit focus-window --match "cwd:/tmp/kdw4" >/dev/null 2>&1 || true
  echo "The sandbox is already armed; its window is now in front."
else
  if [ -x "$STAGED_BIN" ]; then
    printf 'window_title_bar_overlay yes\n' > "$BAND_CONF"
    export KDW4_KITTY="$STAGED_BIN" KDW4_EXTRA_CONF="$BAND_CONF"
    echo "Build in the sandbox: the PATCHED kitty staged at ${STAGED_BIN%/Contents/MacOS/kitty}"
  else
    echo "Nothing patched is staged, so the sandbox runs STOCK kitty: the build and band-width"
    echo "questions cannot be answered in this sitting, only the drag and the chord."
  fi
  bash "$W4" --teardown >/dev/null 2>&1 || true
  bash "$W4" --arm || { echo "could not arm the sandbox"; exit 1; }
fi

cat <<'TXT'

In the separate kitty window (two stacked panes, not one of yours), for about a minute:
  1. Drag the BOTTOM pane onto the TOP one by its blue title, with a plain click and drag.
  2. Drag a pane again holding ⌘⇧ and the left button anywhere inside it (try ⌘ alone too).
  3. Look at the blue title: is "only as wide as its text" right, or do you want it full width?
Then run:  bash ~/.claude/scripts/kitty-sitting.sh --verdict
TXT
