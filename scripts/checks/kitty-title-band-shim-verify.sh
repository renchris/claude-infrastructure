#!/usr/bin/env bash
# Verify the no-restart SHIM (scripts/kitty-title-band-watcher.py) against a STOCK, unpatched kitty
# -- by default the very binary the operator is running. This is the half of the title band that can
# be installed into a terminal that is already open, so it is verified on the binary that is already
# open, not on the patched one.
#
# The sequence is built around one control: the SAME config swap, on the SAME instance, in the SAME
# session, is measured BEFORE the shim is injected and again after. Before, it must cost a row and
# fire SIGWINCH; after, it must cost neither and still draw the bar. A test that only measured the
# second half could not tell a working shim from a config swap that did nothing.
#
# 🚨 Never aimed at the operator's live kitty: own instance, own socket outside the /tmp/kitty-*
# glob, KITTY_LISTEN_ON / KITTY_PID / KITTY_WINDOW_ID stripped, and no synthetic event is posted
# unless this script's OWN window is verified unoccluded and its window id resolved.
set -uo pipefail

# Resolve $0 through its symlinks BEFORE deriving anything from it. ~/.claude/{scripts,hooks,bin}
# are per-file symlink farms into this checkout, so `dirname "$0"/..` through the live layer is
# ~/.claude — which has no tests/, no docs/ and no .git. Canonical loop from scripts/ship-land.sh;
# no `readlink -f`, which is GNU-only and this box is BSD.
_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s' "$p"
}
SELF_DIR="$(cd "$(dirname "$(_resolve_self "$0")")" && pwd)"

KITTY_BIN="${KITTY_BIN:-/Applications/kitty.app/Contents/MacOS/kitty}"
SB="${SB:-/private/tmp/ktb-shim}"
REPO="${REPO:-$HOME/Development/claude-infrastructure}"
WATCHER="${WATCHER:-$(cd "$SELF_DIR/.." && pwd)/kitty-title-band-watcher.py}"
BANDS_PY="$SELF_DIR/kitty-title-band-bands.py"
DRAGHOLD="$SB/draghold"; WRECT="$SB/window-rect"
CELL_H="${CELL_H:-45}"
PASS=0; FAIL=0

# Every in-tree site that creates a terminal surface leaves ONE row, so the pane census's
# "a pane with no row was spawned by something outside this tree" inference stays true. A sandbox
# pane is still a pane: it would otherwise be the single uninstrumented site that turns that
# inference into "outside the tree, or that one site".
# shellcheck source=/dev/null
[ -r "${REPO}/scripts/lib/pane-spawn-log.sh" ] && . "${REPO}/scripts/lib/pane-spawn-log.sh" || true
_ktb_log_spawn() {  # _ktb_log_spawn <kind> <note>
  command -v cc_log_pane_spawn >/dev/null 2>&1 && \
    cc_log_pane_spawn "$1" kitty "" "$SB" "$2" || true
}
ok()  { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
k()   { env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID "$KITTY_BIN" @ --to "unix:$SB/sock" "$@"; }

mkdir -p "$SB"
[ -x "$DRAGHOLD" ] || bash "$REPO/tools/draghold/build.sh" "$DRAGHOLD" >/dev/null 2>&1
[ -x "$WRECT" ]    || swiftc -O -o "$WRECT" "$REPO/tools/terminal-bench/window-rect.swift" 2>/dev/null

cat > "$SB/child.sh" <<'EOF'
#!/bin/bash
n="$1"; c=0; echo 0 > "/private/tmp/ktb-shim/winch.$n"
trap 'c=$((c+1)); echo $c > "/private/tmp/ktb-shim/winch.'"$n"'"' WINCH
for i in $(seq 1 60); do printf 'row %02d ................................................\n' "$i"; done
while true; do read -r -t 3600 x || true; done
EOF
chmod +x "$SB/child.sh"
cat > "$SB/base.conf" <<'EOF'
font_family           Monaco
font_size             18.0
modify_font           cell_height 94%
window_padding_width  0 5 0 5
window_border_width   1pt
draw_minimal_borders  no
placement_strategy    top
window_drag_tolerance 6
window_title_bar_align            left
window_title_bar_active_background   #2f62d8
window_title_bar_active_foreground   #ffffff
window_title_bar_inactive_background #3f5590
window_title_bar_inactive_foreground #f4f6fd
allow_remote_control  yes
confirm_os_window_close 0
macos_quit_when_last_window_closed yes
enable_audio_bell no
update_check_interval 0
cursor_blink_interval 0
EOF
printf 'include base.conf\nwindow_title_bar_min_windows 0\n' > "$SB/off.conf"
printf 'include base.conf\nwindow_title_bar_min_windows 1\n' > "$SB/on.conf"
cat > "$SB/session" <<'EOF'
new_tab sandbox
layout splits
launch --title "PANE-ONE alpha" bash /private/tmp/ktb-shim/child.sh 1
launch --location=hsplit --title "PANE-TWO beta" bash /private/tmp/ktb-shim/child.sh 2
EOF

echo "== launching a STOCK kitty sandbox =="
echo "   binary : $KITTY_BIN"
echo "   watcher: $WATCHER"
k action quit >/dev/null 2>&1; sleep 3
# NEVER rm the shared /tmp/kitty-title-band-watcher.log: it is the only evidence of whether the
# OPERATOR's kitty is still shimmed, and deleting it made `--status` report a false all-clear
# over a still-patched process. This sandbox logs to its own file instead.
export KITTY_TITLE_BAND_LOG="$SB/watcher.log"
rm -f "$SB"/winch.* "$SB"/*.png "$SB"/bands.txt "$SB/watcher.log"
( cd "$SB" && env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID nohup "$KITTY_BIN" \
    --config "$SB/off.conf" --session "$SB/session" --listen-on "unix:$SB/sock" \
    --instance-group ktbshim --directory "$SB" > "$SB/kitty.log" 2>&1 & )
_ktb_log_spawn os-window "kitty-title-band-shim-verify sandbox, 2 panes, sock:$SB/sock bin:$KITTY_BIN"
for _ in $(seq 1 25); do [ -S "$SB/sock" ] && break; sleep 1; done
sleep 3

rows()  { k ls 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); print(','.join(str(w['lines']) for o in d for t in o['tabs'] for w in t['windows']),end='')"; }
winch() { printf '%s,%s' "$(cat "$SB/winch.1" 2>/dev/null)" "$(cat "$SB/winch.2" 2>/dev/null)"; }
nbrs()  { k ls 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(' '.join('%s:top=%s'%(w['id'],(w.get('neighbors') or {}).get('top')) for o in d for t in o['tabs'] for w in t['windows']),end='')"; }
load()  { k load-config --ignore-overrides "$1" >/dev/null 2>&1; sleep 2; }
shoot() { /usr/sbin/screencapture -x -o -l "$PWID" "$SB/$1.png"; }
bands() { python3 "$BANDS_PY" "$SB/$1.png" "$SB/$2.png" "$CELL_H" "$SB/bands.txt" 2>/dev/null; }
guard() {
  for _ in 1 2 3 4 5; do
    k focus-window --match id:1 >/dev/null 2>&1; sleep 1
    [ "$("$WRECT" --owner kitty --window-id "$PWID" --assert-unoccluded 2>&1 | tail -1)" = "verdict=OK" ] && return 0
  done
  return 1
}
PWID="$(k ls 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["platform_window_id"])' 2>/dev/null)"
case "${PWID:-}" in ''|*[!0-9]*) echo "  sandbox failed to start"; exit 1 ;; esac
echo "  sandbox up, platform_window_id=$PWID"

echo
echo "== CONTROL, shim NOT yet injected: the stock bar costs a row and signals =="
load "$SB/off.conf"; R0="$(rows)"; W0="$(winch)"; printf '  min_windows 0  rows=%-8s winch=%s\n' "$R0" "$W0"
load "$SB/on.conf";  R1="$(rows)"; W1="$(winch)"; printf '  min_windows 1  rows=%-8s winch=%s\n' "$R1" "$W1"
load "$SB/off.conf"; R2="$(rows)"; W2="$(winch)"; printf '  min_windows 0  rows=%-8s winch=%s\n' "$R2" "$W2"
[ "$R1" != "$R0" ] && ok "control: stock kitty DOES lose a row when the bar goes up ($R0 -> $R1)" || bad "control dead: no row lost"
[ "$W1" != "$W0" ] && ok "control: stock kitty DOES signal both children ($W0 -> $W1)"            || bad "control dead: no SIGWINCH"

echo
echo "== inject the shim into the RUNNING instance =="
# A fresh path per injection: kitty memoises watcher modules by path (kitty/launch.py:523), so
# re-injecting the same path is a silent no-op. --type=overlay, not background: a background launch
# creates no Window, so load_watch_modules is never reached.
INJ="$SB/watcher-$$.py"; cp "$WATCHER" "$INJ"
k launch --type=overlay --watcher "$INJ" sh -c 'sleep 0.2' >/dev/null 2>&1
_ktb_log_spawn overlay "kitty-title-band-shim-verify: transient watcher-injection overlay, exits in 0.2s"
sleep 3
if grep -q 'installed' "$SB/watcher.log" 2>/dev/null; then
  ok "the shim installed itself into the running kitty"
else
  bad "the shim did not install (see $SB/watcher.log)"
fi

echo
echo "== SUBJECT: the same swap, now with the shim live =="
load "$SB/off.conf"; R3="$(rows)"; W3="$(winch)"; printf '  min_windows 0  rows=%-8s winch=%s\n' "$R3" "$W3"
shoot off
load "$SB/on.conf";  R4="$(rows)"; W4="$(winch)"; printf '  min_windows 1  rows=%-8s winch=%s\n' "$R4" "$W4"
shoot on
[ "$R4" = "$R3" ] && ok "(a) the bar now costs NO rows ($R3 -> $R4)"   || bad "(a) rows still changed: $R3 -> $R4"
[ "$W4" = "$W3" ] && ok "(a) no child signalled ($W3 -> $W4)"          || bad "(a) children still signalled: $W3 -> $W4"
if FOUND="$(bands off on)"; then
  N="$(python3 -c "print(len(eval(open('$SB/bands.txt').read())))")"
  printf '  cell-tall bands: %s\n' "$FOUND"
  [ "$N" = 2 ] && ok "the bar still DRAWS, as one one-cell strip per pane" || bad "expected 2 bands, got $N: $FOUND"
else
  bad "the bar did not draw once the shim was installed"
fi

echo
echo "== (b) it does not scroll with the content =="
k scroll-window --match id:1 end >/dev/null 2>&1; sleep 1; shoot s0
k scroll-window --match id:1 3-  >/dev/null 2>&1; sleep 1; shoot s1
SCROLL_PY="$SELF_DIR/kitty-title-band-scroll.py"
read -r SBODY SBAND SEDGE < <(python3 "$SCROLL_PY" "$SB/s0.png" "$SB/s1.png" "$SB/bands.txt" 2>/dev/null || echo "0 0 0")
printf '  positive control: body ROWS changed by the scroll = %s%%\n' "${SBODY:-?}"
printf '  claim           : band edges byte-identical = %s   (band pixels changed %s%%)\n' "${SEDGE:-?}" "${SBAND:-?}"
awk "BEGIN{exit !(${SBODY:-0} > 50)}" && ok "control: the scroll really happened (${SBODY}% of body rows moved)" || bad "control dead: only ${SBODY:-0}% of body rows changed"
[ "${SEDGE:-0}" = 1 ] && ok "(b) the band did not move: all four edge rows byte-identical" || bad "(b) the band MOVED: an edge row changed"
k scroll-window --match id:1 end >/dev/null 2>&1

echo
echo "== (c) the hit test: hand cursor and drag, which the research left unmeasured =="
RECT="$("$WRECT" --owner kitty --window-id "$PWID" 2>/dev/null | head -1)"
OX="$(echo "$RECT" | sed -E 's/rect=([0-9]+),.*/\1/')"; OY="$(echo "$RECT" | sed -E 's/rect=[0-9]+,([0-9]+),.*/\1/')"
read -r B1 B2 < <(python3 -c "
b = eval(open('$SB/bands.txt').read())
print(int($OY + (b[0][0]+b[0][1])/4), int($OY + (b[1][0]+b[1][1])/4))")
CX=$((OX + 200))
echo "  window $OX,$OY -> band1 y=$B1 band2 y=$B2 x=$CX"
if guard; then
  BEFORE="$(nbrs)"; R5="$(rows)"; W5="$(winch)"
  "$DRAGHOLD" "$CX" "$B2" "$CX" "$B1" 400 120 >/dev/null 2>&1; sleep 2
  AFTER="$(nbrs)"
  printf '  drag band2 -> band1: before[%s] after[%s] rows %s->%s winch %s->%s\n' "$BEFORE" "$AFTER" "$R5" "$(rows)" "$W5" "$(winch)"
  [ "$BEFORE" != "$AFTER" ] && ok "(c) the bar is grabbable and re-positions the pane" || bad "(c) the drag did not swap the panes"
  # the no-op drag: press in band1, move, drop back inside band1
  BEFORE2="$(nbrs)"; shoot noop0
  "$DRAGHOLD" "$((CX-70))" "$B1" "$((CX+70))" "$B1" 300 60 >/dev/null 2>&1; sleep 1
  "$DRAGHOLD" "$((CX+70))" "$B1" "$((CX-70))" "$B1" 300 60 >/dev/null 2>&1; sleep 2
  AFTER2="$(nbrs)"; shoot noop1
  [ "$BEFORE2" = "$AFTER2" ] && ok "(c) a no-op drag leaves the layout unchanged" || bad "(c) the no-op drag moved a pane"
  python3 - "$SB" <<'PY'
import sys
from PIL import Image
SB = sys.argv[1]
bands = eval(open(f'{SB}/bands.txt').read())
y = (bands[0][0] + bands[0][1]) // 2
def blue(f):
    im = Image.open(f'{SB}/{f}.png').convert('RGB'); p = im.load()
    return sum(1 for x in range(0, im.size[0], 4) if p[x, y][2] > 100)
print(f'  band pixels before={blue("noop0")} after={blue("noop1")} (bar-off reference={blue("off")})')
open(f'{SB}/noop.txt', 'w').write(f'{blue("noop0")} {blue("noop1")} {blue("off")}')
PY
  read -r N0 N1 NOFF < "$SB/noop.txt"
  if [ "${N1:-0}" -gt $(( ${NOFF:-0} * 4 )) ]; then ok "(c) the title is still up after the no-op drag"
  else bad "(c) the title vanished after the no-op drag ($N0 -> $N1, off=$NOFF)"; fi
else
  bad "(c) window occluded, refused to post events"
fi

echo
echo "== the shim is REVERSIBLE =="
REV="$SB/revert-$$.py"; cp "$(dirname "$WATCHER")/kitty-title-band-unwatcher.py" "$REV"
k launch --type=overlay --watcher "$REV" sh -c 'sleep 0.2' >/dev/null 2>&1
_ktb_log_spawn overlay "kitty-title-band-shim-verify: transient revert overlay, exits in 0.2s"
sleep 3
load "$SB/on.conf"; R6="$(rows)"
printf '  after revert, min_windows 1 rows=%s (stock behaviour is %s)\n' "$R6" "$R1"
[ "$R6" = "$R1" ] && ok "uninstall restores stock behaviour exactly" || bad "uninstall did not restore stock rows: $R6 vs $R1"

printf '\n== RESULT: %d passed, %d failed ==\n' "$PASS" "$FAIL"
k action quit >/dev/null 2>&1
[ "$FAIL" -eq 0 ]
