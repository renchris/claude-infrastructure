#!/bin/bash
# post-land.sh — the phase-2 post-land repro: the LANDED kitty-fullscreen-guard and kitty-pane-menu
# (~/.claude/bin) driven against a throwaway kitty, with the review's missing arms, then one table.
#
#   bash post-land.sh            # refuses (exit 3) while the screen is locked
#
# Native fullscreen cannot be entered on a locked screen and every window reads offscreen, so a run
# there only shows the guard failing closed (refused-unknown) — measured 2026-10-15 03:30. The
# refusal is the precondition check, not a failure of the fix.
# Each trial takes over the screen with a native-fullscreen Space for ~10 s; run.sh's exit trap
# leaves fullscreen and quits its throwaway kitty. It never addresses the live kitty (run.sh header).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="${KCR_RUN:-$HOME/Development/.worktrees/kitty-repro}"
locked="$(/usr/bin/python3 -c '
import ctypes
cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
cg.CGSessionCopyCurrentDictionary.restype = ctypes.c_void_p
cf.CFStringCreateWithCString.restype = ctypes.c_void_p
cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
cf.CFDictionaryGetValue.restype = ctypes.c_void_p
cf.CFDictionaryGetValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
cf.CFBooleanGetValue.argtypes = [ctypes.c_void_p]
d = cg.CGSessionCopyCurrentDictionary()
v = cf.CFDictionaryGetValue(d, cf.CFStringCreateWithCString(None, b"CGSSessionScreenIsLocked", 0x08000100)) if d else None
print(1 if v and cf.CFBooleanGetValue(v) else 0)')"
if [ "$locked" != 0 ]; then
  echo "post-land: the screen is LOCKED — native fullscreen cannot be entered; nothing run. Unlock, then re-run." >&2
  exit 3
fi
cd "$HERE" || exit 1
RES="$RUN/results-p2-postland.tsv"
before="$(find "$RUN/logs" -name 'run-*.log' 2>/dev/null | sort)"
# 1. the landed guard and menu on the last pane of a fullscreen window; A unfocused (B takes focus,
#    so A's Space goes to the background on its display)
KCR_RES="$RES" ./run.sh 2 guard-move:idle guard-close:idle guard-exit:idle menu-move:idle menu-new:idle menu-close:idle guard-move:unfocus
# 2. A on a second display: idle, and unfocused while still visible there
KCR_RES="$RES" KCR_DISPLAY=2 ./run.sh 1 guard-move:idle guard-move:unfocus menu-move:idle
# 3. destroy during AppKit's automatic fullscreen of a new window (B fullscreen and key when A opens)
KCR_RES="$RES" KCR_BFS=1 ./run.sh 2 guard-move:autofs:200 guard-move:autofs:700
new="$(comm -13 <(printf '%s\n' "$before") <(find "$RUN/logs" -name 'run-*.log' | sort))"
# shellcheck disable=SC2086  # one log path per word
/usr/bin/python3 "$HERE/postland-table.py" $new
