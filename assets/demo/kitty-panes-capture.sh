#!/bin/bash
# kitty-panes-capture.sh — the on-camera sequence for the pane-management demo (1080p60 master).
#
# WHAT IS ON CAMERA
#   Every beat is a REAL kitty action, performed by the same code path the keybinding fires:
#   `kitten @ action <name>` runs a mappable action against the focused window, and `launch` /
#   `detach-window` are the remote-control forms of what ⌘D and ⌘⇧O invoke. The chord names the
#   narration prints are therefore claims about config/kitty.conf, which tests/kitty-conf-
#   bindings.bats pins against kitty's own config loader — not decoration typed over a mock-up.
#
#   Keystrokes are NOT synthesised. macOS `System Events` keystrokes go to the FRONTMOST process,
#   and on this box that is frequently one of ~30 live Claude Code panes in the operator's own
#   kitty — a stray ⌘⇧O there would detach a working session's pane. Driving this instance's own
#   socket cannot reach another instance, which is the whole reason the demo is safe to run on a
#   loaded machine.
#
# HOW THE MASTER WAS MADE (reproduce, don't guess)
#   1. launch ONE window you own, in its OWN instance group so it shares nothing with the fleet,
#      titled so the capture can find it by title and by nothing else:
#        open -n -a /Applications/kitty.app --args \
#          --instance-group=ccpanes --title=CCPANES60 --config <repo>/config/kitty.conf \
#          -o remember_window_size=no -o initial_window_width=1280 \
#          -o initial_window_height=720 -o font_size=15 \
#          bash -c "sleep 16; <repo>/assets/demo/kitty-panes-capture.sh"
#      (plain ints — kitty rejects a `px` suffix here with an int-parse error. `open -n -a`, not a
#      bare exec: a shell-launched GUI app is not activated by LaunchServices and its window can
#      end up composited on no display at all.)
#   2. resolve the window BY TITLE, then film the window itself:
#        swift tools/terminal-bench/window-rect.swift --owner kitty --title CCPANES60 --largest
#        swiftc -O tools/terminal-bench/window-film.swift -o /tmp/window-film   # MUST be compiled
#        /tmp/window-film --window-id <wid> --seconds 38 --activate --out raw.mov
#   3. ffmpeg -i raw.mov -vf "scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos,
#              pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,fps=60" -c:v libx264 -crf 20 ...
#   4. CONTACT-SHEET IT, and read the film binary's own frames=/fps= line before believing the
#      container's frame rate.
#
#   🚨 NOT `screencapture`. Both of its window routes were tried here and both are wrong:
#   `-l<window-id>` does not scope a VIDEO capture (it silently films the whole display), and
#   `-R x,y,w,h` films whatever is ON TOP at that rect. The `-R` attempt at this very demo recorded
#   the operator's browser — their tabs, their mail, their address — because the demo window was
#   behind it, and that take was deleted unused. Worse, positioning the window to fix the rect needs
#   Accessibility (`osascript` → "not allowed assistive access", -1719), which this box does not
#   grant. window-film.swift's ScreenCaptureKit filter composites the window's OWN content, so
#   occlusion, the Dock, notification banners and every other window are impossible to film. It also
#   works when the window is on no visible Space at all, which is where a freshly launched window on
#   this 4-display box actually lands.
#
#   The beat log written to $BEATLOG timestamps each action for post; the on-screen narration in
#   pane 1 is what the viewer reads (this ffmpeg has no drawtext, so burnt-in captions are not an
#   option and an overlay would cover the panes the film exists to show).
set -u

BEATLOG="${CC_BEATLOG:-/tmp/ccpanes-beats.log}"
: > "$BEATLOG"

# Resolve the repo root through this script's own symlink chain — `pwd -P` alone resolves the
# DIRECTORY, not the final symlink component, and this file lives TWO levels down (assets/demo/).
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  _l="$(readlink "$SELF")"
  case "$_l" in /*) SELF="$_l" ;; *) SELF="$(cd "$(dirname "$SELF")" && pwd -P)/$_l" ;; esac
done
REPO="${CC_REPO:-$(cd "$(dirname "$SELF")/../.." && pwd -P)}"
[ -x "$REPO/scripts/tui-load.sh" ] || {
  echo "kitty-panes-capture: scripts/tui-load.sh not found under $REPO — wrong root" >&2; exit 1; }
cd "$REPO" || exit 1

# Mark a beat: the wall-clock instant the action fires, so post can align a caption to it without
# anyone counting frames by eye — AND narrate it in pane 1, which is what the viewer reads. The
# chord is printed before the action so the frame that shows the change already carries its name.
beat() {
  printf '%s\t%s\n' "$(date +%s.%N)" "$1" >> "$BEATLOG"
  printf '  \033[38;5;179m%s\033[0m  \033[38;5;245m%s\033[0m\n' "${1%%  *}" "${1#*  }"
}

# Remote control against THIS instance only. kitty exports KITTY_LISTEN_ON into every child, so
# no --to is needed and none should be added: an explicit socket path is how a demo script grows
# the ability to reach the operator's fleet.
K() { kitten @ "$@" >/dev/null 2>&1; }

[ -n "${KITTY_LISTEN_ON:-}" ] || {
  echo "kitty-panes-capture: no KITTY_LISTEN_ON — run me INSIDE the demo kitty window" >&2
  exit 1
}

# The panes run the repo's own synthetic TUI load, for two reasons. It makes each pane
# identifiable while it moves — but more importantly the capture is CHANGE-DRIVEN: ScreenCaptureKit
# delivers a frame when the window redraws, so a window of static text yields almost nothing. A
# first take of this sequence with idle panes produced 26 frames in 38 s (0.68 fps) and 27 s of
# stall; the container could still be muxed at 60 fps, which would have made "1080p60" a true
# statement about the file and a false one about the content. Panes that actually repaint are what
# make the frame rate real. 60 Hz, not the bake-off's representative 10 Hz: this file is a
# DEMO, and its caption claims 60 fps, so the content has to change 60 times a second for that
# claim to describe the pixels and not just the container.
#
# CC_PANES_STATIC=1 runs the same sequence with STILL panes instead, and that take is what the
# inline README image is built from. Two artifacts, two routes, for a measured reason: at 60 Hz the
# panes are per-pixel colour churn, which is close to incompressible — the animated WebP of the
# moving take came out 38 MB, a permanent clone tax on everyone who fetches this repo. With still
# panes the encoder merges runs of identical frames and the same sequence lands two orders of
# magnitude smaller, while losing nothing the inline image is there to show: the pane MOVES are the
# content, and they are discrete state changes, not motion.
LOAD="$REPO/scripts/tui-load.sh"
STILL=$(mktemp -t ccpane-still)
cat > "$STILL" <<'EOF'
#!/bin/sh
printf '\033[2J\033[H\n\n\n      \033[1m%s\033[0m\n' "$1"
while :; do sleep 30; done
EOF
chmod +x "$STILL"
if [ "${CC_PANES_STATIC:-0}" = "1" ]; then
  pane() { K launch --location="$1" --cwd=current "$STILL" "$2"; }
else
  pane() { K launch --location="$1" --cwd=current bash "$LOAD" --fps 60 --duration 240 --label "$2"; }
fi
name() { K set-window-title --match "id:$1" "$2"; }
tint() { K set-colors --match "id:$1" "background=$2"; }

# Pane 1 is this script's own pane: it narrates each beat as it fires, so the chord that caused a
# change is on screen in the same frames as the change.
clear
printf '\n  \033[1mkitty pane management\033[0m — every line below is the real action behind the chord\n\n'
sleep 3

beat "cmd+d  split right"
pane vsplit "PANE 2"
sleep 4

beat "cmd+shift+d  split below"
pane hsplit "PANE 3"
sleep 4

# Colour + name the three panes at once so the moves below are unambiguous on camera. ls order is
# layout order (kitty documents `num` as position, clockwise, in ls order), so index 0/1/2 here
# are stable references to the panes as laid out, not to creation order.
IDS=$(kitten @ ls | python3 -c '
import json,sys
for o in json.load(sys.stdin):
    for t in o["tabs"]:
        if t.get("is_focused"):
            print(" ".join(str(w["id"]) for w in t["windows"]))
' 2>/dev/null)
# Word splitting is the POINT here — $IDS is a space-separated id list being turned into
# positional parameters. Quoting it would make one argument of the whole list.
# shellcheck disable=SC2086
set -- $IDS
i=1
for id in "$@"; do
  case $i in
    1) tint "$id" "#123044" ;;
    2) tint "$id" "#3a2450" ;;
    3) tint "$id" "#14402c" ;;
  esac
  name "$id" "pane $i"
  i=$((i+1))
done
sleep 3

beat "cmd+shift+left  move_window — a SWAP, silent no-op with no neighbour"
K action move_window left
sleep 4

beat "cmd+ctrl+up  move_to_screen_edge top"
K action layout_action move_to_screen_edge top
sleep 4

beat "cmd+shift+b  toggle_window_title_bars — the drag handle for re-order"
K action toggle_window_title_bars
sleep 5

beat "cmd+shift+o  detach_window — the pane LEAVES this tab"
K detach-window --target-tab new --stay-in-tab
sleep 5

beat "done"

# Hold the frame. The starting pane is the one running THIS script, so returning here would exit
# its command and close the window — on camera, in the last seconds of the take, which reads as a
# crash rather than an ending. The capture's own -V bound ends the take; the instance is closed
# afterwards from outside (`kitten @ --to unix:/tmp/kitty-<pid> close-tab --match all`).
while :; do sleep 30; done
