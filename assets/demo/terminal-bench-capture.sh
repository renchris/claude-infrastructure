#!/bin/bash
# terminal-bench-capture.sh — the on-camera sequence for the 1080p60 screen capture.
#
# Same five beats as assets/demo/terminal-bench.tape, driven by a script instead of by VHS,
# because VHS 0.11 ignores `Set Framerate` for its mp4 muxer (probed: a minimal tape at 60
# still emitted 25/1) and the linked master is specified at 1080p60.
# Everything here is REAL: terminal-bench.sh is read-only by construction.
#
# HOW THE MASTER WAS MADE (reproduce, don't guess — full rationale in terminal-bench.tape):
#   1. launch ONE terminal window you own, 1280x720 logical, in its own instance group:
#        kitty --instance-group=ccbench --title=CCBENCH60 -o remember_window_size=no \
#              -o initial_window_width=1280 -o initial_window_height=720 -o font_size=15 \
#              bash -c "sleep 10; assets/demo/terminal-bench-capture.sh"
#      (plain ints — kitty rejects a `px` suffix here with an int-parse error)
#   2. position it clear of the notification zone, then capture that RECT — never -l<window-id>,
#      which does NOT scope VIDEO and will record the whole desktop:
#        screencapture -v -V88 -R0,38,1280,720 take.mov
#   3. trim to the last dark frame (the window closes before -V expires and the tail films the
#      desktop), then scale 2560x1440 -> 1920x1080:
#        ffmpeg -i take.mov -t <cut> -vf "scale=1920:1080:flags=lanczos" -r 60 \
#               -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -an terminal-bench.mp4
#   4. CONTACT-SHEET IT, and scan EVERY second for desktop frames, not a sample.
set -u

# Resolve the repo root from this script's own location, walking the symlink chain — the same
# discipline as scripts/terminal-bench.sh. A hardcoded path made this reproducible on exactly
# one machine, and `pwd -P` alone resolves the DIRECTORY, not the final symlink component.
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(cd "$(dirname "$SELF")" && pwd -P)/$_link" ;;
  esac
done
# NB `/../..` — this script lives TWO levels down (assets/demo/), unlike scripts/terminal-bench.sh
# which is one. Copying that file's `/..` verbatim resolved to assets/ and the guard below fired.
REPO="${CC_REPO:-$(cd "$(dirname "$SELF")/../.." && pwd -P)}"
cd "$REPO" || { echo "terminal-bench-capture: cannot cd to REPO=$REPO" >&2; exit 1; }
[ -x scripts/terminal-bench.sh ] || {
  echo "terminal-bench-capture: scripts/terminal-bench.sh not found under $REPO — wrong root" >&2; exit 1; }

# Render a line as if it had been typed, then run it. Keeps the clip legible without a
# typing simulator — the point of the recording is the OUTPUT, not the keystrokes.
say()  { printf '\033[38;5;179m❯\033[0m %s\n' "$1"; }
note() { printf '\033[38;5;245m%s\033[0m\n' "$1"; }
run()  { say "$1"; eval "$1"; echo; }

clear
sleep 1

note "# 1 — THE CONTRACT.  This instrument is read-only, so it is safe to aim at a live fleet."
sleep 1
run "grep -n 'READ-ONLY' scripts/terminal-bench.sh"
sleep 2

note "# 2 — WHAT IS ACTUALLY UP RIGHT NOW.  Matched on the comm BASENAME: macOS stores iTerm2's"
note "#     accounting name as the first 16 chars of its full path, so pgrep -x can never see it."
sleep 1
run "ps -eo comm= | sed 's|.*/||' | grep -Eix 'kitty|ghostty|cmux|iTerm2' | sort | uniq -c"
sleep 2

note "# 3 — kitty, THE CHALLENGER.  A full row: two readings, GPU path by PROFILE (not by flag),"
note "#     and the drift instrument at constant layout."
sleep 1
run "scripts/terminal-bench.sh --app kitty --interval 20"
sleep 2

note "# 4 — THE INCUMBENT, LIVE, UNDER THE OPERATOR'S REAL LOAD.  Watch the GPU:CPU frame ratio:"
note "#     iTerm2 is drawing MOSTLY ON THE CPU.  That is the whole terminal argument, measured."
sleep 1
run "scripts/terminal-bench.sh --app iTerm2 --interval 0"
note "# PARTIAL, not OK — every number above is real, but ONE reading cannot support a leak"
note "# verdict, so the instrument refuses the OK token rather than overclaim."
sleep 3

note "# 5 — AND IT SAYS WHEN IT DID NOT MEASURE.  WezTerm is not installed here: NO-DATA, exit 3,"
note "#     never a silent zero a consumer could mistake for a measured one."
sleep 1
run "scripts/terminal-bench.sh --app wezterm --interval 0; echo exit=\$?"
sleep 4
