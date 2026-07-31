# terminal-bench.tape — the terminal bake-off instrument, run against the LIVE fleet.
#
#   vhs assets/demo/terminal-bench.tape     → assets/demo/terminal-bench.gif  (intermediate, gitignored)
#   gif2webp -m 6 -min_size -mt assets/demo/terminal-bench.gif \
#            -o assets/demo/terminal-bench.webp                               (the INLINE artifact)
#
# TWO ARTIFACTS, TWO ROUTES — and the split is forced, not stylistic.
#   • INLINE  `terminal-bench.webp`  ← THIS TAPE (VHS → gif → gif2webp, lossless, deterministic)
#   • LINKED  `terminal-bench.mp4`   ← `assets/demo/terminal-bench-capture.sh` under
#                                      `screencapture -v -V88 -R<rect>`, then trim + scale to 1080p60
# Why not one: VHS 0.11.0 **ignores `Set Framerate` for its mp4 muxer** and emits 25 fps whatever the
# tape asks (probed directly: a minimal tape at `Set Framerate 60` still produced 25/1). The operator
# asked for 1080p60, so the mp4 is a real `screencapture` at display refresh (60.00 Hz on all three
# displays here) and this tape no longer emits an mp4 at all.
#
# 🚨 THE CAPTURE ROUTE CAN LEAK THE OPERATOR'S SCREEN. Three failures hit while producing it, each
# caught by the mandatory contact sheet and none by any encoder error:
#   1. `screencapture -l<window-id>` does NOT scope VIDEO to that window — it recorded the whole
#      display, Dock, wallpaper and the operator's other windows. Use `-R x,y,w,h` and make your own
#      window cover the rect exactly.
#   2. A macOS notification banner (carrying live session ids) landed in the top-right of the frame.
#      Banners are right-aligned; keep the rect's right edge left of ~x=1368 on this display.
#      1280×720 at x=0 clears it by 88 pt and captures at 2× ⇒ 2560×1440 ⇒ a clean 1080p downscale.
#   3. The window closed before the capture's `-V` budget expired, so the tail filmed the desktop.
#      Trim to the last dark frame; a mean-luma scan separates them unambiguously here
#      (terminal ≈ 6.4k, wallpaper ≈ 22.8k out of 65535). Scan EVERY second, not a sample.
# Re-shooting is cheap; shipping a leak is not. Contact-sheet before you encode, every time.
#
# WHY THIS RECORDING EXISTS. The README makes quantitative claims about which terminal survives
# 30+ concurrent Claude Code panes. Those claims are only worth anything if the instrument behind
# them was actually run on this box — a reader cannot tell a measured table from a table copied out
# of somebody's source tree at a reading glance. So this is the instrument, running, against the
# terminals that are genuinely up at record time, printing the numbers the README quotes.
#
# EVERYTHING HERE IS REAL. No mock-ups, no re-enactment, no --dry-run. terminal-bench.sh is
# READ-ONLY by construction (it creates no panes, closes no panes, writes no preference, kills
# nothing — scene 1 shows that contract in its own source), which is the only reason it is safe to
# point at the operator's live fleet mid-session.
#
# THE THREE VERDICTS ARE THE POINT. A measurement instrument that cannot say "I did not measure
# this" is worthless, because a consumer then cannot tell a measured zero from a run that never
# happened (this repo's memory claimed-outcome-vs-checked-outcome). So the recording deliberately
# shows all three terminal states of the verdict= token:
#   verdict=OK        both readings + GPU profile resolved  — kitty, a full drift row
#   verdict=PARTIAL   --interval 0, a single reading        — iTerm2; every number in it is real,
#                     but one reading CANNOT support a leak verdict, so it is refused the OK token
#                     rather than filed as if it could
#   verdict=NO-DATA   the app is not running (exit 3)       — WezTerm, genuinely not installed here
#
# SCENE 4 IS THE INCUMBENT'S OWN NUMBER, and it is the reason this clip is worth recording at all:
# iTerm2 measures ~107% CPU with a GPU:CPU frame ratio of ~0.53:1 — i.e. it is rendering MOSTLY ON
# THE CPU, live, while the box is under the operator's real load. That is the finding the README's
# whole terminal section rests on, captured from the instrument rather than asserted.
#
# ONE CENSUS TRAP, WORTH KNOWING BEFORE YOU EDIT THIS TAPE. `pgrep -x iTerm2` finds NOTHING on this
# box: macOS stored iTerm2's accounting name as the first 16 chars of its FULL PATH
# (`/Applications/iT`), so -x can never match. An ad-hoc census written while preparing this very
# recording concluded "iTerm2 is not running" and scripted a scene around it — while iTerm2 was pid
# 591 burning 107% CPU. terminal-bench.sh is immune because it falls back to matching the BASENAME
# of ps's comm; the shell one-liner in scene 2 uses that same method deliberately.
#
# HONEST QUALIFICATION, and it is the reason the drift scene is short: the recorded kitty run uses
# --interval 20 to keep the clip watchable. A 20 s window resolves drift no finer than ~180
# ports/hr, so the +0 it prints is a real reading but a WEAK bound — it cannot by itself exclude
# iTerm2's measured +76 ports/hr. The bound that CAN is the 30-minute run reported in the README
# table beside this clip (~2 ports/hr resolution). Short interval on camera, long interval for the
# claim; do not read the clip as the evidence for the drift number.

Output assets/demo/terminal-bench.gif
# NO mp4 Output here — it would overwrite the real 1080p60 screencapture with a 25 fps VHS render.

Set Shell bash
Set FontSize 22
Set Width 1920
Set Height 1080
Set Padding 30
# MEASURED, do not "fix" this to 60 and assume it took: VHS 0.11.0 IGNORES Set Framerate for the
# mp4 muxer and emits 25 fps regardless. Probed directly — a minimal tape at `Set Framerate 60`
# still produced avg_frame_rate=25/1. The setting is kept because it governs the GIF; the mp4's
# real rate is 25, and the README caption says 25 rather than claiming a 60 the file does not have.
# A genuine 60 fps master would need the screencapture path (see the demo-recording skill), which
# films a real window and therefore carries a content-leak risk this scripted tape does not.
Set Framerate 60
Set TypingSpeed 12ms
Set Theme { "name": "gh-dark", "background": "#0d1117", "foreground": "#c9d1d9", "cursor": "#d4af37", "selection": "#264f78", "black": "#484f58", "red": "#ff7b72", "green": "#3fb950", "yellow": "#d29922", "blue": "#58a6ff", "magenta": "#bc8cff", "cyan": "#39c5cf", "white": "#b1bac4", "brightBlack": "#6e7681", "brightRed": "#ffa198", "brightGreen": "#56d364", "brightYellow": "#e3b341", "brightBlue": "#79c0ff", "brightMagenta": "#d2a8ff", "brightCyan": "#56d4dd", "brightWhite": "#f0f6fc" }

Hide
Type "cd /Users/chrisren/Development/.worktrees/l3l4-docs" Enter
Type "export PS1='\[\033[38;5;179m\]❯\[\033[0m\] '" Enter
Type "clear" Enter
Show

Type "# 1 — THE CONTRACT.  This instrument is read-only, so it is safe to aim at a live fleet." Enter
Sleep 1200ms
Type "grep -n 'READ-ONLY' scripts/terminal-bench.sh" Enter
Sleep 3500ms

Type "# 2 — WHAT IS ACTUALLY UP RIGHT NOW.  Matched on the comm BASENAME: macOS stores iTerm2's" Enter
Type "#     accounting name as the first 16 chars of its full path, so pgrep -x can never see it." Enter
Sleep 1500ms
Type "ps -eo comm= | sed 's|.*/||' | grep -Eix 'kitty|ghostty|cmux|iTerm2' | sort | uniq -c" Enter
Sleep 3500ms

Type "# 3 — kitty, THE INCUMBENT'S CHALLENGER.  A full row: two readings, GPU path by PROFILE" Enter
Type "#     (not by flag), and the drift instrument at constant layout.  ~30s." Enter
Sleep 1500ms
Type "scripts/terminal-bench.sh --app kitty --interval 20" Enter
Sleep 42s

Type "# 4 — THE INCUMBENT, LIVE, UNDER THE OPERATOR'S REAL LOAD.  Watch the GPU:CPU frame ratio:" Enter
Type "#     iTerm2 is drawing MOSTLY ON THE CPU.  That is the whole terminal argument, measured." Enter
Sleep 1500ms
Type "scripts/terminal-bench.sh --app iTerm2 --interval 0" Enter
Sleep 12s
Type "# PARTIAL, not OK — every number above is real, but ONE reading cannot support a leak" Enter
Type "# verdict, so the instrument refuses the OK token rather than overclaim." Enter
Sleep 4s

Type "# 5 — AND IT SAYS WHEN IT DID NOT MEASURE.  WezTerm is not installed here: NO-DATA, exit 3," Enter
Type "#     never a silent zero a consumer could mistake for a measured one." Enter
Sleep 1500ms
Type "scripts/terminal-bench.sh --app wezterm --interval 0; echo exit=$?" Enter
Sleep 5s
