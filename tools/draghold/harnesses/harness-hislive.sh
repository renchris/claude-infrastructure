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
# The body is unreachable behind the refusal guard below — that is the point. Codes below are
# the ones shellcheck 0.11.0 itself emitted; SC2329 is the newer spelling of SC2317.
# shellcheck disable=SC2034,SC2086,SC2329,SC2317
#
# 🚨🚨 THIS FILE IS ARMED TO DRIVE THE OPERATOR'S LIVE TERMINAL AND IS DISABLED HERE. 🚨🚨
# Its `SOCK=unix:/tmp/kitty-97084` is his real kitty's control socket, and it launches an OS
# window in HIS process and then fires draghold at it. It is committed as a READABLE RECORD of
# the technique only — the guard below makes it refuse to run. Nothing is deleted; every
# original line is intact underneath. To use the technique, copy it and point it at a sandbox
# instance with its own KITTY_CONFIG_DIRECTORY and a socket outside the /tmp/kitty-* glob.
echo "harness-hislive.sh: REFUSING TO RUN — this artifact targets the operator's LIVE kitty." >&2
echo "  See the banner above. Copy it and retarget a sandbox before use." >&2
exit 9
# Test the drag INSIDE THE OPERATOR'S RUNNING KITTY PROCESS, in a throwaway OS window with
# throwaway panes, so none of his sessions move. This separates "his kitty process/config
# cannot do it" from "a fresh probe instance can" — the only axis left after the action was
# shown to work remotely on that same process.
set -u
K=/Applications/kitty.app/Contents/MacOS/kitty
SOCK=unix:/tmp/kitty-97084
HOLD="$(dirname "$0")/draghold"
OUT="${1:-/tmp/hl}"; mkdir -p "$OUT"
k(){ "$K" @ --to "$SOCK" "$@"; }
mk(){ printf 'import sys,time\nwhile True:\n    sys.stdout.write("\\033[H"+("%s"*300+"\\n")*60); sys.stdout.flush(); time.sleep(0.4)\n' "$1"; }
NEW=$(k launch --type=os-window --cwd=/tmp -- /usr/bin/python3 -c "$(mk A)")
sleep 2.0
# find the OS window that holds the new pane
read -r OSW TABID <<EOF
$(k ls | python3 -c "
import json,sys
d=json.load(sys.stdin)
for o in d:
    for t in o['tabs']:
        for w in t['windows']:
            if str(w['id'])=='$NEW': print(o['platform_window_id'], t['id'])
")
EOF
echo "new os-window $OSW tab $TABID (pane $NEW)"
k launch --location=vsplit --match id:$NEW --cwd=/tmp -- /usr/bin/python3 -c "$(mk B)" >/dev/null; sleep 0.6
k launch --location=vsplit --cwd=/tmp -- /usr/bin/python3 -c "$(mk C)" >/dev/null; sleep 0.6
k action --self layout_action equalize >/dev/null 2>&1; sleep 1.0
B=$(osascript -e "tell application \"System Events\" to tell process \"kitty\" to get {position, size} of window 1" 2>/dev/null)
WX=$(echo "$B"|cut -d, -f1|tr -d ' '); WY=$(echo "$B"|cut -d, -f2|tr -d ' ')
WW=$(echo "$B"|cut -d, -f3|tr -d ' '); WH=$(echo "$B"|cut -d, -f4|tr -d ' ')
echo "bounds $B"
COLW=$(( WW / 3 ))
k action --self toggle_window_title_bars >/dev/null 2>&1; sleep 1.2
screencapture -x -o -l"$OSW" "$OUT/aim.png" 2>/dev/null
read -r AIMY PNGW <<EOF
$(python3 - "$OUT/aim.png" <<'PYEOF'
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert("RGB"); W,H=im.size; px=im.load()
BARS=((0x2f,0x62,0xd8),(0x3f,0x55,0x90))
def isbar(x,y): return any(all(abs(px[x,y][i]-b[i])<=14 for i in range(3)) for b in BARS)
best=-1
for y in range(60,H//3):
    if sum(1 for x in range(0,W,4) if isbar(x,y)) > (W//4)*0.5: best=y; break
print(best, W)
PYEOF
)
EOF
[ "${AIMY:--1}" -ge 0 ] || { echo "ABORT: no title bar found — refusing to aim blind"; exit 1; }
SCALE=$(( PNGW / WW )); [ "$SCALE" -lt 1 ] && SCALE=1
BARY=$(( WY + AIMY / SCALE ))
echo "bar y $BARY"
ord(){ for t in 1 2 3; do rm -f "$OUT/$1.png"; screencapture -x -o -l"$OSW" "$OUT/$1.png" 2>/dev/null; [ -s "$OUT/$1.png" ] && break; sleep 0.4; done
python3 - "$OUT/$1.png" "$OUT/refs.json" <<'PYEOF'
import sys, json, os
from PIL import Image
im=Image.open(sys.argv[1]).convert("L"); W,H=im.size; px=im.load()
R=sys.argv[2]
def sig(x0,x1):
    y0=int(H*0.5)
    return [1 if px[x,y]>140 else 0 for y in range(y0,y0+30,3) for x in range(x0,x1,3)]
third=W//3
s=[sig(int(third*i)+60, int(third*i)+220) for i in range(3)]
if not os.path.exists(R):
    json.dump({"A":s[0],"B":s[1],"C":s[2]}, open(R,"w")); print("ABC"); raise SystemExit
refs=json.load(open(R))
print("".join(min(refs,key=lambda k: sum(1 for a,b in zip(refs[k],x) if a!=b)) for x in s))
PYEOF
}
echo "order before: $(ord o1)"
"$HOLD" $(( WX + COLW/2 )) "$BARY" $(( WX + COLW*2 + COLW/2 )) "$BARY" 400 120 2>/dev/null
sleep 2.0
echo "order after : $(ord o2)"
echo "-- cleaning up the throwaway window --"
k close-tab --match id:$NEW >/dev/null 2>&1 || true
