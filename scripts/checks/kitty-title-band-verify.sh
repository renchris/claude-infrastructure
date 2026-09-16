#!/usr/bin/env bash
# Verify the overlay window title band end to end, in a SANDBOX kitty, against the four things it
# exists to do. Every test carries a control, because almost every measurement here returns a clean
# null when the instrument is dead, and a null from a dead instrument is indistinguishable from a
# pass:
#
#   (a) toggling costs no rows and no top margin  -> rows + SIGWINCH, with the stock CELL title bar
#                                                    as the positive control that DOES lose a row
#                                                    and DOES signal both children
#   (b) the band does not scroll with the content -> scroll the pane: the body must move (positive
#                                                    control) and the band must not
#   (c) draggable, and a no-op drag keeps it up   -> a real CGEvent drag, with a stock-cell-bar arm
#                                                    that must swap and a no-band arm that must not
#   (d) system sans face                          -> not asserted here; judged by eye from on.png
#
# 🚨 NEVER aimed at the operator's live kitty. It builds its own instance, on a socket outside the
# /tmp/kitty-* glob this repo's tooling scans, with KITTY_LISTEN_ON / KITTY_PID / KITTY_WINDOW_ID
# stripped from every invocation; it refuses to post a synthetic event unless its OWN window is
# verified unoccluded; and it fails closed if it cannot resolve its own window id, because an empty
# --window-id makes window-rect fall back to "some kitty window", which on this machine is one of
# the operator's live agent sessions.
#
# Usage:  bash scripts/checks/kitty-title-band-verify.sh
#         KITTY_BIN=/path/to/patched/kitty bash scripts/checks/kitty-title-band-verify.sh
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

KITTY_BIN="${KITTY_BIN:-$HOME/ktb/kitty/launcher/kitty}"
SB="${SB:-/private/tmp/ktb-verify}"
REPO="${REPO:-$HOME/Development/claude-infrastructure}"
DRAGHOLD="$SB/draghold"; HOVER="$SB/hover"; WRECT="$SB/window-rect"
BANDS_PY="$SELF_DIR/kitty-title-band-bands.py"
CELL_H="${CELL_H:-45}"          # font_size 18 x modify_font cell_height 94% at dpi 144
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
if [ ! -x "$HOVER" ]; then
  cat > "$SB/hover.c" <<'EOF'
#include <ApplicationServices/ApplicationServices.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc < 4) return 2;
    CGPoint p = CGPointMake(atof(argv[1]), atof(argv[2]));
    CGWarpMouseCursorPosition(p);
    CGEventRef mv = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft);
    if (mv) { CGEventPost(kCGHIDEventTap, mv); CFRelease(mv); }
    usleep(atoi(argv[3]) * 1000);
    return 0;
}
EOF
  clang -O2 -o "$HOVER" "$SB/hover.c" -framework ApplicationServices 2>/dev/null
fi

cat > "$SB/child.sh" <<'EOF'
#!/bin/bash
n="$1"; c=0; echo 0 > "/private/tmp/ktb-verify/winch.$n"
trap 'c=$((c+1)); echo $c > "/private/tmp/ktb-verify/winch.'"$n"'"' WINCH
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
window_title_bar_min_windows 0
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
printf 'include base.conf\nwindow_title_bar_overlay no\n'    > "$SB/off.conf"
printf 'include base.conf\nwindow_title_bar_overlay yes\n'   > "$SB/on.conf"
printf 'include base.conf\nwindow_title_bar_min_windows 1\n' > "$SB/cells.conf"
cat > "$SB/session" <<'EOF'
new_tab sandbox
layout splits
launch --title "PANE-ONE alpha" bash /private/tmp/ktb-verify/child.sh 1
launch --location=hsplit --title "PANE-TWO beta" bash /private/tmp/ktb-verify/child.sh 2
EOF

echo "== launching sandbox =="
# A previous run may still own the socket. A second instance that cannot bind it comes up with NO
# control socket at all (kitty prints "Invalid listen_on" and carries on), and every measurement
# after that reads an instance nothing can drive.
k action quit >/dev/null 2>&1; sleep 3
rm -f "$SB"/winch.* "$SB"/*.png "$SB"/bands.txt "$SB"/arm.txt
( cd "$SB" && env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID nohup "$KITTY_BIN" \
    --config "$SB/off.conf" --session "$SB/session" --listen-on "unix:$SB/sock" \
    --instance-group ktbverify --directory "$SB" > "$SB/kitty.log" 2>&1 & )
_ktb_log_spawn os-window "kitty-title-band-verify sandbox, 2 panes, sock:$SB/sock bin:$KITTY_BIN"
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
  # Refuse to post a synthetic event unless OUR window is verifiably on top: a drag aimed at an
  # occluded rect lands in whatever is actually there. Retried, because the check is transiently
  # false right after a window is raised.
  for _ in 1 2 3 4 5; do
    k focus-window --match id:1 >/dev/null 2>&1; sleep 1
    [ "$("$WRECT" --owner kitty --window-id "$PWID" --assert-unoccluded 2>&1 | tail -1)" = "verdict=OK" ] && return 0
  done
  return 1
}
resolve_pwid() {
  PWID="$(k ls 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["platform_window_id"])' 2>/dev/null)"
  case "${PWID:-}" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}

resolve_pwid || { echo "  sandbox failed to start"; exit 1; }
echo "  sandbox up, platform_window_id=$PWID"

echo
echo "== (a) rows and SIGWINCH across the toggle =="
load "$SB/off.conf";   R0="$(rows)"; W0="$(winch)"; printf '  off           rows=%-8s winch=%s\n' "$R0" "$W0"
load "$SB/cells.conf"; R1="$(rows)"; W1="$(winch)"; printf '  CONTROL cell  rows=%-8s winch=%s\n' "$R1" "$W1"
load "$SB/off.conf";   R2="$(rows)"; W2="$(winch)"; printf '  off           rows=%-8s winch=%s\n' "$R2" "$W2"
load "$SB/on.conf";    R3="$(rows)"; W3="$(winch)"; printf '  BAND on       rows=%-8s winch=%s\n' "$R3" "$W3"
load "$SB/off.conf";   R4="$(rows)"; W4="$(winch)"; printf '  off           rows=%-8s winch=%s\n' "$R4" "$W4"
[ "$R1" != "$R0" ] && ok "control: the stock cell bar DOES cost a row ($R0 -> $R1)"        || bad "control dead: the cell bar cost no row"
[ "$W1" != "$W0" ] && ok "control: the stock cell bar DOES signal children ($W0 -> $W1)"   || bad "control dead: no SIGWINCH from the cell bar"
[ "$R3" = "$R2" ]  && ok "(a) band on costs NO rows ($R2 -> $R3)"                          || bad "(a) band changed rows: $R2 -> $R3"
[ "$W3" = "$W2" ]  && ok "(a) band on signals NO child ($W2 -> $W3)"                       || bad "(a) band signalled a child: $W2 -> $W3"
[ "$R4" = "$R3" ]  && ok "(a) band off costs no rows either"                               || bad "(a) band off changed rows"

echo
echo "== the band is DRAWN, and is exactly one cell tall =="
load "$SB/off.conf"; shoot off
load "$SB/on.conf";  shoot on
load "$SB/off.conf"; shoot off2
if bands off off2 >/dev/null; then
  bad "negative control: two OFF captures differ by a cell-tall band, so the diff proves nothing"
else
  ok "negative control: two OFF captures show no band"
fi
if FOUND="$(bands off on)"; then
  N="$(python3 -c "print(len(eval(open('$SB/bands.txt').read())))")"
  printf '  cell-tall bands found: %s\n' "$FOUND"
  [ "$N" = 2 ] && ok "the band draws as one one-cell strip per pane" || bad "expected 2 bands, found $N: $FOUND"
else
  bad "the band did not draw at all"
fi

echo
echo "== (b) the band does not move when the content scrolls =="
load "$SB/on.conf"
k scroll-window --match id:1 end >/dev/null 2>&1; sleep 1; shoot s0
k scroll-window --match id:1 3-  >/dev/null 2>&1; sleep 1; shoot s1
SCROLL_PY="$SELF_DIR/kitty-title-band-scroll.py"
read -r SBODY SBAND SEDGE < <(python3 "$SCROLL_PY" "$SB/s0.png" "$SB/s1.png" "$SB/bands.txt" 2>/dev/null || echo "0 0 0")
printf '  positive control: body ROWS changed by the scroll = %s%%\n' "${SBODY:-?}"
printf '  claim           : band edges byte-identical = %s   (band pixels changed %s%%)\n' "${SEDGE:-?}" "${SBAND:-?}"
awk "BEGIN{exit !(${SBODY:-0} > 50)}" && ok "control: the scroll really happened (${SBODY}% of body rows moved)" || bad "control dead: only ${SBODY:-0}% of body rows changed"
[ "${SEDGE:-0}" = 1 ] && ok "(b) the band did not move: all four edge rows byte-identical" || bad "(b) the band MOVED: an edge row changed"
k scroll-window --match id:1 end >/dev/null 2>&1

# A drag can move an OS window or detach a pane into a new one, so every coordinate derived before
# a drag is stale after it. Re-derive, and refuse to keep aiming if the topology is no longer two
# panes in one OS window.
calibrate() {
  local topo rect
  topo="$(k ls 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); print(len(d), sum(len(t["windows"]) for o in d for t in o["tabs"]))' 2>/dev/null)"
  [ "$topo" = "1 2" ] || { bad "topology drifted to [$topo], expected [1 2]"; return 1; }
  resolve_pwid || { bad "could not resolve the sandbox window id, refusing to aim anything"; return 1; }
  load "$SB/off.conf"; shoot cal-off
  load "$SB/on.conf";  shoot cal-on
  bands cal-off cal-on >/dev/null || { bad "calibration found no band"; return 1; }
  [ "$(python3 -c "print(len(eval(open('$SB/bands.txt').read())))")" = 2 ] || { bad "calibration found $(cat "$SB/bands.txt")"; return 1; }
  rect="$("$WRECT" --owner kitty --window-id "$PWID" 2>/dev/null | head -1)"
  OX="$(echo "$rect" | sed -E 's/rect=([0-9]+),.*/\1/')"
  OY="$(echo "$rect" | sed -E 's/rect=[0-9]+,([0-9]+),.*/\1/')"
  case "${OX:-}${OY:-}" in ''|*[!0-9]*) bad "could not read the sandbox window rect"; return 1 ;; esac
  read -r B1 B2 TOP1 < <(python3 -c "
b = eval(open('$SB/bands.txt').read())
print(int($OY + (b[0][0]+b[0][1])/4), int($OY + (b[1][0]+b[1][1])/4), int($OY + b[0][0]/2) + 2)")
  CX=$((OX + 200))
  printf '  calibrated: window %s,%s  band1 y=%s  band2 y=%s  band1 top y=%s  x=%s\n' "$OX" "$OY" "$B1" "$B2" "$TOP1" "$CX"
  return 0
}

arm() { # arm <conf> <label> <y_from> <y_to>
  # Blank the result file FIRST: an aborted arm must not leave the previous arm's result on disk
  # for the assertions to read as their own.
  : > "$SB/arm.txt"
  load "$SB/$1"; guard || { bad "$2: window occluded, refused to post events"; return; }
  local before after r0 w0
  before="$(nbrs)"; r0="$(rows)"; w0="$(winch)"
  "$DRAGHOLD" "$CX" "$3" "$CX" "$4" 400 120 >/dev/null 2>&1; sleep 2
  after="$(nbrs)"
  printf '  %-26s before[%s] after[%s] rows %s->%s winch %s->%s\n' "$2" "$before" "$after" "$r0" "$(rows)" "$w0" "$(winch)"
  printf '%s|%s|%s|%s|%s|%s' "$before" "$after" "$r0" "$(rows)" "$w0" "$(winch)" > "$SB/arm.txt"
}

echo
echo "== (c) drag: three arms, one variable =="
if calibrate; then
  arm cells.conf "CONTROL stock cell bar" "$B2" "$B1"
  IFS='|' read -r CB CA _ _ _ _ < "$SB/arm.txt"
  { [ -n "${CB:-}" ] && [ "$CB" != "${CA:-}" ]; } && ok "control: the drag instrument really swaps panes" || bad "control dead: the stock cell bar did not swap"
fi
if calibrate; then
  arm on.conf "SUBJECT overlay band" "$B2" "$B1"
  IFS='|' read -r XB XA XR0 XR1 XW0 XW1 < "$SB/arm.txt"
  { [ -n "${XB:-}" ] && [ "$XB" != "${XA:-}" ]; }   && ok "(c) dragging the band re-positions the pane"    || bad "(c) the band drag did not swap"
  { [ -n "${XR0:-}" ] && [ "$XR0" = "${XR1:-}" ]; } && ok "(c)+(a) rows UNCHANGED across the drag ($XR0)"  || bad "(c)+(a) the drag shifted content: ${XR0:-?} -> ${XR1:-?}"
  { [ -n "${XW0:-}" ] && [ "$XW0" = "${XW1:-}" ]; } && ok "(c)+(a) no child signalled across the drag"     || bad "(c)+(a) the drag signalled children: ${XW0:-?} -> ${XW1:-?}"
fi
if calibrate; then
  arm off.conf "NEGATIVE no bar at all" "$B2" "$B1"
  IFS='|' read -r NB NA _ _ _ _ < "$SB/arm.txt"
  { [ -n "${NB:-}" ] && [ "$NB" = "${NA:-}" ]; } && ok "negative control: with no band the same drag swaps nothing" || bad "negative control swapped anyway, or was skipped"
fi

echo
echo "== (c) the TOP edge of the band grabs, it does not resize the split =="
if calibrate && load "$SB/on.conf" && guard; then
  BEFORE="$(nbrs)"
  "$DRAGHOLD" "$CX" "$TOP1" "$CX" "$B2" 400 120 >/dev/null 2>&1; sleep 2
  AFTER="$(nbrs)"
  printf '  press at band top y=%s: before[%s] after[%s]\n' "$TOP1" "$BEFORE" "$AFTER"
  [ "$BEFORE" != "$AFTER" ] && ok "(c) the band's top edge grabs the pane, the border resizer does not win" \
                            || bad "(c) the band's top edge did NOT grab, the border resizer claimed it"
fi

echo
echo "== (c) a no-op drag leaves the title up and the layout alone =="
if calibrate && load "$SB/on.conf" && guard; then
  # Take the OFF reference here, with a settle-and-verify loop. A capture taken too soon after a
  # load-config can catch a half-redrawn frame, and using that as the "band absent" reference makes
  # the present/absent threshold meaningless. Verify it really is near-zero before trusting it.
  NOFF=999
  for _ in 1 2 3 4; do
    load "$SB/off.conf"; sleep 1; shoot noop-off
    NOFF="$(python3 - "$SB" <<'PYREF'
import sys
from PIL import Image
SB = sys.argv[1]
bands = eval(open(f'{SB}/bands.txt').read())
y = (bands[0][0] + bands[0][1]) // 2
im = Image.open(f'{SB}/noop-off.png').convert('RGB'); p = im.load()
print(sum(1 for x in range(0, im.size[0], 4) if p[x, y][2] > 100))
PYREF
)"
    [ "${NOFF:-999}" -lt 50 ] && break
  done
  [ "${NOFF:-999}" -lt 50 ] || bad "could not get a clean band-absent reference (got $NOFF)"
  load "$SB/on.conf"
  BEFORE="$(nbrs)"; shoot noop0
  "$DRAGHOLD" "$((CX-70))" "$B1" "$((CX+70))" "$B1" 300 60 >/dev/null 2>&1; sleep 1
  "$DRAGHOLD" "$((CX+70))" "$B1" "$((CX-70))" "$B1" 300 60 >/dev/null 2>&1; sleep 2
  AFTER="$(nbrs)"; shoot noop1
  printf '  before[%s] after[%s]\n' "$BEFORE" "$AFTER"
  [ "$BEFORE" = "$AFTER" ] && ok "(c) a no-op drag leaves the layout unchanged" || bad "(c) the no-op drag moved a pane"
  python3 - "$SB" <<'PY'
import sys
from PIL import Image
SB = sys.argv[1]
bands = eval(open(f'{SB}/bands.txt').read())
y = (bands[0][0] + bands[0][1]) // 2
def blue(f):
    im = Image.open(f'{SB}/{f}.png').convert('RGB'); p = im.load()
    return sum(1 for x in range(0, im.size[0], 4) if p[x, y][2] > 100)
print(f'  band pixels before={blue("noop0")} after={blue("noop1")} (overlay-off reference={blue("noop-off")})')
open(f'{SB}/noop.txt', 'w').write(f'{blue("noop0")} {blue("noop1")} {blue("noop-off")}')
PY
  read -r N0 N1 NOFF < "$SB/noop.txt"
  # "Still up" is the property, not pixel equality: which pane is ACTIVE can change across a drag
  # and the active/inactive band colours differ, so a strict == fails on a real success. The
  # measurement separates by an order of magnitude (present ~390, absent ~11), so the threshold is
  # set well above the absent case and well below the present one.
  if [ "${N0:-0}" -le $(( ${NOFF:-0} * 4 )) ]; then
    bad "(c) precondition failed: the title was not up BEFORE the no-op drag ($N0 vs off=$NOFF)"
  elif [ "${N1:-0}" -gt $(( ${NOFF:-0} * 4 )) ]; then
    ok "(c) the title is still up after the no-op drag ($N0 -> $N1, off reference $NOFF)"
  else
    bad "(c) the title vanished after the no-op drag ($N0 -> $N1, off=$NOFF)"
  fi
fi

printf '\n== RESULT: %d passed, %d failed ==\n' "$PASS" "$FAIL"
k action quit >/dev/null 2>&1
[ "$FAIL" -eq 0 ]
