#!/bin/bash
#
# ───────────────────────────────────────────────────────────────────────────────────────────
# RECOVERED AS-IS (W8, 2026-09-16). The body below is the artifact that produced the § I9
# four-row table; it is kept verbatim EXCEPT for two `# shellcheck disable=SC2034` directives
# (codes taken from shellcheck 0.11.0's own output, not from memory) so it passes the land
# gate. 🚨 DO NOT RUN IT UNMODIFIED — it violates two of this repo's sandbox rules:
#   1. its socket is `/tmp/kitty-vd-$$`, which MATCHES the `/tmp/kitty-*` glob that
#      `bin/cc-kitty-socket` scans and that `scripts/kitty-pane-title-overlay.py` refuses on
#      when it finds more than one. Move it outside that glob (e.g. /tmp/kdw8-vd.sock).
#   2. it does not strip the inherited KITTY_LISTEN_ON / KITTY_PID / KITTY_WINDOW_ID, so a
#      command losing its explicit `--to` would drive the operator's live terminal. Prefix
#      every invocation with `env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID`.
# It also calls `screencapture -C`, which captures the WHOLE SCREEN, and it calls draghold,
# which takes the real cursor. See README.md § Safety.
# ───────────────────────────────────────────────────────────────────────────────────────────
# LAYOUT ORDER READ FROM THE SCREEN, not from `kitty @ ls`.
#
# `move_window right` — a known-good reorder — leaves the ls windows array untouched, so that
# array is creation order and is structurally blind to the thing under test. Every pane here
# floods itself with ONE distinct letter, so the left-to-right sequence of letters in a
# capture IS the layout order. The control below drives move_window and requires the reading
# to change; if it does not, this instrument is blind too and nothing under it may be trusted.
set -u
KITTY=/Applications/kitty.app/Contents/MacOS/kitty
HOLD="$(dirname "$0")/draghold"
SOCK=/tmp/kitty-vd-$$; CONF=$(mktemp /tmp/vdconf.XXXX.conf)
OUT="${1:-/tmp/vd}"; mkdir -p "$OUT"
printf 'allow_remote_control yes\nenabled_layouts splits,stack\nremember_window_size no\ninitial_window_width 1400\ninitial_window_height 800\nconfirm_os_window_close 0\nwindow_title_bar_min_windows %s\nwindow_title_bar_active_background #2f62d8\nwindow_title_bar_inactive_background #3f5590\n' "${MINW:-1}" > "$CONF"
mk(){ printf 'import sys,time\nwhile True:\n    sys.stdout.write("\\033[H"+("%s"*300+"\\n")*60); sys.stdout.flush(); time.sleep(0.4)\n' "$1"; }
"$KITTY" --config "$CONF" --listen-on "unix:$SOCK" -- /usr/bin/python3 -c "$(mk A)" & KPID=$!
trap 'kill $KPID 2>/dev/null; rm -f "$CONF"' EXIT
# shellcheck disable=SC2034   # loop counter is a repeat count, not a value
for i in $(seq 1 80); do [ -S "$SOCK" ] && break; sleep 0.25; done; sleep 1.5
k(){ "$KITTY" @ --to "unix:$SOCK" "$@"; }
k launch --location=vsplit --cwd=/tmp -- /usr/bin/python3 -c "$(mk B)" >/dev/null; sleep 0.5
k launch --location=vsplit --cwd=/tmp -- /usr/bin/python3 -c "$(mk C)" >/dev/null; sleep 0.5
k action --self layout_action equalize >/dev/null 2>&1; sleep 1.0; k focus-window >/dev/null 2>&1; sleep 1.0
WID=$(k ls | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["platform_window_id"])')
B=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $KPID) to get {position, size} of window 1" 2>/dev/null)
WX=$(echo "$B"|cut -d, -f1|tr -d ' '); WY=$(echo "$B"|cut -d, -f2|tr -d ' ')
WW=$(echo "$B"|cut -d, -f3|tr -d ' '); WH=$(echo "$B"|cut -d, -f4|tr -d ' ')
COLW=$(( WW / 3 ))
read_order(){  # OCR-free: sample the glyph bitmap of each column's mid-height band
  # shellcheck disable=SC2034   # loop counter is a repeat count, not a value
  for t in 1 2 3; do rm -f "$OUT/$1.png"; k focus-window >/dev/null 2>&1; sleep 0.5
    screencapture -x -o -l"$WID" "$OUT/$1.png" 2>/dev/null; [ -s "$OUT/$1.png" ] && break; done
  python3 - "$OUT/$1.png" "$OUT/refs.json" <<'PYEOF'
import sys, json, os
from PIL import Image
im=Image.open(sys.argv[1]).convert("L"); W,H=im.size; px=im.load()
REFS=sys.argv[2]
def sig(x0,x1):
    y0=int(H*0.45)
    return [1 if px[x,y]>140 else 0 for y in range(y0,y0+30,3) for x in range(x0,x1,3)]
third=W//3
sigs=[sig(int(third*i)+40, int(third*i)+200) for i in range(3)]
# LABELS ARE ANCHORED TO REFERENCES, NOT TO FIRST-SEEN ORDER. Labelling by first sight makes
# column 1 always "A", so the reading is constant whatever the layout does — blind by
# construction, which is how it passed a control that should have failed it.
if not os.path.exists(REFS):
    json.dump({"A":sigs[0],"B":sigs[1],"C":sigs[2]}, open(REFS,"w"))
    print("ABC"); raise SystemExit
refs=json.load(open(REFS))
def best(s):
    return min(refs, key=lambda k: sum(1 for a,b in zip(refs[k],s) if a!=b))
print("".join(best(s) for s in sigs))
PYEOF
}
echo "start layout order      : $(read_order start)"
echo "-- CONTROL: move_window must change the reading --"
k action move_window left >/dev/null 2>&1; sleep 1.3
echo "after move_window left  : $(read_order c1)"
k action move_window right >/dev/null 2>&1; sleep 1.3
echo "restored                : $(read_order c2)"

[ "${MODE:-natural}" = toggled ] && { k action --self toggle_window_title_bars >/dev/null 2>&1; sleep 1.0; }
screencapture -x -o -l"$WID" "$OUT/aim.png" 2>/dev/null
AIM=$(python3 - "$OUT/aim.png" <<'PYEOF'
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert("RGB"); W,H=im.size; px=im.load()
BARS=((0x2f,0x62,0xd8),(0x3f,0x55,0x90))
def isbar(x,y): return any(all(abs(px[x,y][i]-b[i])<=14 for i in range(3)) for b in BARS)
# SKIP macOS CHROME. hide_window_decorations is not set, so the top ~28 logical pt of the
# capture is the OS title bar; a match there aims the press at window chrome and drags the
# whole OS WINDOW. At 2x that is ~56 device px, so start below it — and REPORT the row so a
# regression in the aim is visible instead of silently voiding the run.
CHROME = 60
best=-1
for y in range(CHROME,H//3):
    if sum(1 for x in range(0,W,4) if isbar(x,y)) > (W//4)*0.5: best=y; break
print(best, W)
PYEOF
)
AIMY=$(echo "$AIM"|awk '{print $1}'); PNGW=$(echo "$AIM"|awk '{print $2}')
SCALE=$(( PNGW / WW )); [ "$SCALE" -lt 1 ] && SCALE=1
if [ "${AIMY:--1}" -lt 0 ]; then echo "ABORT: no pane title bar found in the capture — refusing to aim blind"; exit 1; fi
BARY=$(( WY + AIMY / SCALE ))
P1=$(( WX + COLW/2 )); P2=$(( WX + COLW + COLW/2 )); P3=$(( WX + COLW*2 + COLW/2 ))
echo "-- THE DRAG (bar y $BARY) --"
drag(){ [ "${MODE:-natural}" = toggled ] && { k action --self toggle_window_title_bars >/dev/null 2>&1; sleep 0.9; }
  b=$(read_order "b$5"); "$HOLD" "$1" "$2" "$3" "$4" 400 120 2>/dev/null; sleep 1.8
  a=$(read_order "a$5")
  printf '  %-34s [%s] -> [%s]  %s\n' "$5" "$b" "$a" "$([ "$b" = "$a" ] && echo 'no reorder' || echo 'REORDERED')"; }
drag "$P1" "$BARY" "$P3" "$BARY" "pane1-title -> pane3-title"
drag "$P1" "$BARY" "$P2" "$BARY" "pane1-title -> pane2-title"
drag "$P1" "$BARY" "$P3" $(( WY + WH/2 )) "pane1-title -> pane3-body"
