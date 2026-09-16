#!/bin/bash
#
# ─────────────────────────────────────────────────────────────────────────────────────────
# RECOVERED AS-IS (W8, 2026-09-16) from a reapable per-session scratchpad. The body below is
# the original artifact, UNCHANGED. Added here: this banner, and a FILE-LEVEL shellcheck
# directive so the land gate passes. That directive is deliberate and is scoped to a FROZEN
# reference artifact — it is not a licence for new code, and any edit to this file should
# drop it and fix the findings properly.
# 🚨 These harnesses drive `draghold`, which posts to the SYSTEM-WIDE HID event tap and takes
# the real cursor, and several call `screencapture -C`, which captures the WHOLE SCREEN.
# Several also use a socket inside the `/tmp/kitty-*` glob that this repo's tooling scans, and
# none strip the inherited KITTY_LISTEN_ON / KITTY_PID / KITTY_WINDOW_ID. Read ../README.md
# § Safety, and fix both before running any of them.
# ─────────────────────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC2034,SC2086   # frozen recovered artifact; see banner
set -u
KITTY=/Applications/kitty.app/Contents/MacOS/kitty
HOLD="$(dirname "$0")/draghold"
OUT="${1:-/tmp/mid}"; mkdir -p "$OUT"
SOCK=/tmp/kitty-mid-$$; CONF=$(mktemp /tmp/midconf.XXXX.conf)
printf 'allow_remote_control yes\nenabled_layouts splits,stack\nremember_window_size no\ninitial_window_width 1400\ninitial_window_height 800\nconfirm_os_window_close 0\nwindow_title_bar_min_windows 1\nwindow_title_bar_active_background #2f62d8\nwindow_title_bar_inactive_background #3f5590\nwindow_title_bar_active_foreground #ffffff\nwindow_title_bar_inactive_foreground #f4f6fd\n' > "$CONF"
"$KITTY" --config "$CONF" --listen-on "unix:$SOCK" -- /bin/sh -c 'while :; do sleep 60; done' & KPID=$!
trap 'kill $KPID 2>/dev/null; rm -f "$CONF"' EXIT
for i in $(seq 1 80); do [ -S "$SOCK" ] && break; sleep 0.25; done; sleep 1.5
k(){ "$KITTY" @ --to "unix:$SOCK" "$@"; }
for i in 1 2; do k launch --location=vsplit --cwd=/tmp -- /bin/sh -c 'while :; do sleep 60; done' >/dev/null; sleep 0.4; done
k action --self layout_action equalize >/dev/null 2>&1; sleep 0.8
k focus-window >/dev/null 2>&1; sleep 1.0
order(){ k ls | python3 -c 'import json,sys
d=json.load(sys.stdin);print(" ".join(str(w["id"]) for o in d for t in o["tabs"] for w in t["windows"]))'; }
B=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $KPID) to get {position, size} of window 1" 2>/dev/null)
WX=$(echo "$B"|cut -d, -f1|tr -d ' '); WY=$(echo "$B"|cut -d, -f2|tr -d ' ')
WW=$(echo "$B"|cut -d, -f3|tr -d ' '); WH=$(echo "$B"|cut -d, -f4|tr -d ' ')
COLW=$(( WW / 3 ))
WID=$(k ls | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["platform_window_id"])')
screencapture -x -o -l"$WID" "$OUT/aimshot.png" 2>/dev/null
AIM=$(python3 - "$OUT/aimshot.png" <<'PYEOF'
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert("RGB"); W,H=im.size; px=im.load()
BARS=((0x2f,0x62,0xd8),(0x3f,0x55,0x90))
def isbar(x,y): return any(all(abs(px[x,y][i]-b[i])<=14 for i in range(3)) for b in BARS)
best=-1
for y in range(0,H//3):
    if sum(1 for x in range(0,W,4) if isbar(x,y)) > (W//4)*0.5: best=y; break
print(best, W)
PYEOF
)
AIMY=$(echo "$AIM"|awk '{print $1}'); PNGW=$(echo "$AIM"|awk '{print $2}')
SCALE=$(( PNGW / WW )); [ "$SCALE" -lt 1 ] && SCALE=1
BARY=$(( WY + AIMY / SCALE )); SX=$(( WX + COLW/2 ))
screencapture -x -C "$OUT/before.png" 2>/dev/null
echo "bar y $BARY  order before: $(order)"
( sleep 1.2; screencapture -x -C "$OUT/mid1.png" 2>/dev/null
  sleep 0.9; screencapture -x -C "$OUT/mid2.png" 2>/dev/null; echo "captured mid-drag x2" ) &
CAPPID=$!
"$HOLD" "$SX" "$BARY" $(( WX + COLW + COLW/2 )) "$BARY" 3000 120
wait "$CAPPID"
sleep 1.5
echo "order after : $(order)"
k close-window --match id:1 >/dev/null 2>&1
