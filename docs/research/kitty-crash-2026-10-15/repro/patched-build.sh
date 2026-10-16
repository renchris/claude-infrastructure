#!/bin/bash
# patched-build.sh — the kitty-side fix (README § "Kitty patch"): every destroy path, UNGUARDED (no
# kitty-fullscreen-guard in front), against a throwaway kitty running a given build, then one table.
#
#   bash patched-build.sh <kitty.app> [reps]     # e.g. ~/ktb-noband/kitty.app 2
#
# Pass = every closed A reads LEFT-FULLSCREEN-FIRST: the patched _glfwPlatformDestroyWindow leaves
# native fullscreen and closes the window only after windowDidExitFullScreen. Run it once against an
# unpatched bundle as the control (every A reads CLOSED-IN-FULLSCREEN). Each trial takes over the
# screen with a native-fullscreen Space for ~10 s; refuses (exit 3) while the screen is locked.
# run.sh never addresses the live kitty (its header); this script only picks the binary.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="${1:?usage: patched-build.sh <kitty.app> [reps]}"; REPS="${2:-2}"
RUN="${KCR_RUN:-$HOME/Development/.worktrees/kitty-repro}"
[ -x "$APP/Contents/MacOS/kitty" ] || { echo "patched-build: no kitty binary in $APP" >&2; exit 2; }
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
  echo "patched-build: the screen is LOCKED — native fullscreen cannot be entered; nothing run." >&2
  exit 3
fi
cd "$HERE" || exit 1
export KCR_KITTY="$APP/Contents/MacOS/kitty"
RES="$RUN/results-kitty-patch-$(date +%Y%m%d%H%M%S).tsv"
before="$(find "$RUN/logs" -name 'run-*.log' 2>/dev/null | sort)"
# 1. each destroy path while kitty is idle and A is at rest in fullscreen; then the incident's shape
#    (the move after a helper app activated and quit, followed by the pane menu's tail)
KCR_RES="$RES" ./run.sh "$REPS" move:idle close:idle exit:idle closeos:idle move:helper:0:menu
# 2. mid-transition: destroy A while AppKit is still auto-entering fullscreen (B fullscreen and key)
KCR_RES="$RES" KCR_BFS=1 ./run.sh "$REPS" close:autofs:200 exit:autofs:700
new="$(comm -13 <(printf '%s\n' "$before") <(find "$RUN/logs" -name 'run-*.log' | sort))"
echo "build: $APP ($(LC_ALL=C grep -ac GLFWDeferredClose "$APP/Contents/Resources/kitty/kitty/glfw-cocoa.so" | sed 's/^0$/unpatched/;s/^[1-9].*/patched/'))"
# shellcheck disable=SC2086  # one log path per word
/usr/bin/python3 "$HERE/postland-table.py" $new
