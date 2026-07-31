#!/bin/bash
# bench-demo.sh — the on-camera sequence for the 1080p60 screen capture.
# Same five beats as assets/demo/terminal-bench.tape, typed by a script instead of by VHS,
# because VHS 0.11 hard-codes 25 fps for its mp4 muxer (probed) and the operator asked for 60.
# Everything here is REAL: terminal-bench.sh is read-only by construction.
set -u
cd /Users/chrisren/Development/.worktrees/l3l4-docs

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
