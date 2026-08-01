#!/bin/bash
# renderer-film.sh — film ONE candidate terminal rendering the bake-off load, at 1080p60.
#
# WHAT THIS IS EVIDENCE OF. README §6 compares terminals on loaded app CPU and threads per pane.
# Those are numbers in a table, and a reader has no way to tell whether they came from a real run or
# from reading somebody's source tree. This films the run itself: N panes of the SAME synthetic
# Ink-shaped load (scripts/tui-load.sh — alternate screen, 24-bit colour, full-frame repaint at a
# fixed rate) repainting in the candidate, and takes the measurement in the same breath, so the film
# and the row underneath it come from one event.
#
# 🚨 THE CAPTURE IS WINDOW-SCOPED, AND THAT IS A SAFETY PROPERTY, NOT A CONVENIENCE.
# `screencapture -v` cannot film a window: `-l<window-id>` silently films the whole display, and
# `-R x,y,w,h` films whatever is ON SCREEN at that rect. Both were tried here. The `-R` route, with
# a rect correct to the pixel, produced a still of the operator's BROWSER — their open tabs, their
# mail client, their home address — because the browser was on top and a rect does not know what it
# is looking at. tools/terminal-bench/window-film.swift uses ScreenCaptureKit's
# desktop-independent-window filter, which composites that window's OWN content: occlusion, the
# Dock, notification banners and every other window become impossible to film rather than something
# a reviewer has to catch. The machine stays usable while a take runs.
#
# THE WINDOW IS FOUND BY TITLE, AND ONLY BY TITLE. This box runs the operator's live Claude Code
# fleet in the very apps under test — a census while building this found THREE live kitty windows
# titled "Claude Code". Every pane sets the window title to $FILM_TITLE via OSC 0, and
# window-rect.swift refuses (verdict=NO-MATCH, exit 4) rather than falling back to "first window of
# that app". A fallback would film a live agent session.
#
# USAGE
#   assets/demo/renderer-film.sh --app kitty                     # 18 panes, 20 s, 1080p60
#   assets/demo/renderer-film.sh --app ghostty --panes 18 --seconds 20
#   assets/demo/renderer-film.sh --app wezterm --out /tmp/films
# OUTPUT (in --out, default assets/demo/):
#   renderer-<app>.mp4    1920x1080, 60 fps, the linked master
#   renderer-<app>.txt    the terminal-bench row taken during the take
# VERDICT: verdict=OK | SPAWN-FAILED | NO-WINDOW | CAPTURE-FAILED | STATIC | REFUSED
set -uo pipefail

APP=""; PANES=18; FPS=10; SECONDS_TAKE=15; OUTDIR=""; KEEP_RAW=0
MAXLOAD="${FILM_MAXLOAD:-40}"
FILM_TITLE="CCFILM60"

while [ $# -gt 0 ]; do
  case "$1" in
    --app)      APP="${2:-}"; shift 2 ;;
    --panes)    PANES="${2:-18}"; shift 2 ;;
    --fps)      FPS="${2:-10}"; shift 2 ;;
    --seconds)  SECONDS_TAKE="${2:-20}"; shift 2 ;;
    --out)      OUTDIR="${2:-}"; shift 2 ;;
    --keep-raw) KEEP_RAW=1; shift ;;
    -h|--help)  sed -n '1,34p' "$0"; exit 0 ;;
    *) echo "renderer-film: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$APP" ] || { echo "renderer-film: --app is required" >&2; exit 2; }

# Resolve the repo root through this script's own symlink chain — `pwd -P` alone resolves the
# DIRECTORY, not the final symlink component, and this file lives TWO levels down (assets/demo/).
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  _l="$(readlink "$SELF")"
  case "$_l" in /*) SELF="$_l" ;; *) SELF="$(cd "$(dirname "$SELF")" && pwd -P)/$_l" ;; esac
done
REPO="${CC_REPO:-$(cd "$(dirname "$SELF")/../.." && pwd -P)}"
cd "$REPO" || { echo "renderer-film: cannot cd to REPO=$REPO" >&2; exit 1; }
[ -x scripts/tui-load.sh ] || { echo "renderer-film: scripts/tui-load.sh missing under $REPO" >&2; exit 1; }
OUTDIR="${OUTDIR:-$REPO/assets/demo}"
mkdir -p "$OUTDIR"

RECT_SWIFT="$REPO/tools/terminal-bench/window-rect.swift"
FILM_SWIFT="$REPO/tools/terminal-bench/window-film.swift"
BIN="${TMPDIR:-/tmp}/window-film-$(date -u +%Y%m%d)"

# ── circuit breaker ───────────────────────────────────────────────────────────────────────────────
# 18 panes repainting at 10 fps is genuinely heavy, and this box hosts the operator's live fleet.
# loadavg is a poor attribution signal but an adequate "do not add this right now" signal.
LOADNOW="$(uptime | sed -E 's/.*load averages?: ([0-9.]+).*/\1/')"
if awk -v l="$LOADNOW" -v m="$MAXLOAD" 'BEGIN{exit !(l+0 > m+0)}'; then
  echo "renderer-film: REFUSING — loadavg $LOADNOW exceeds $MAXLOAD; re-run when the box is quieter" >&2
  echo "verdict=REFUSED"; exit 4
fi

# ── the screen must be UNLOCKED, and this is not a retryable condition ────────────────────────────
# 🚨 A LOCKED MAC RENDERS NOTHING. When the login window is up, no application draws, nothing can be
# activated, and a window-scoped capture returns zero frames — indistinguishable, without this check,
# from a terminal that failed to repaint. Measured exactly that way here: the screen locked at
# 18:43:30, between a kitty take that produced 887 frames and a WezTerm take that produced 0, and
# three retries plus two rounds of activation fixes were spent on what was a locked screen.
#
# `caffeinate -u` is tried first because a merely SLEEPING display is recoverable without the
# operator. A LOCK is not: unlocking needs the operator's password, so this refuses with a named
# operator step instead of burning the retry budget.
screen_locked() {
  # Absent key = unlocked; the value is only published while locked.
  #
  # 🚨 NOT `ioreg | grep -q`. Under this script's `set -o pipefail`, grep -q exits the instant it
  # matches, ioreg is SIGPIPEd, and the pipeline reports the PRODUCER's 141 — so the probe reads
  # FALSE exactly when the pattern IS present. This check was written that way, silently inverted,
  # and let three takes run against a screen it had correctly detected as locked. Capture the output
  # first, then test it: no early exit, nothing to SIGPIPE.
  local state
  state="$(ioreg -n Root -d1 2>/dev/null | grep -o 'CGSSessionScreenIsLocked"=[A-Za-z]*')"
  case "$state" in *'=Yes'*) return 0 ;; *) return 1 ;; esac
}
if screen_locked; then
  caffeinate -u -t 2 2>/dev/null; sleep 2
fi
if screen_locked; then
  echo "renderer-film: REFUSING — the screen is locked, so no window is being drawn." >&2
  echo "  Filming needs the Mac awake and unlocked. Unlock it, then re-run this command." >&2
  echo "verdict=LOCKED"; exit 9
fi

# window-film.swift MUST be compiled. Interpreted, the same SCContentFilter call aborts inside
# swift-frontend — and its sibling window-rect.swift interprets fine, which is exactly what makes
# the trap easy to walk into.
if [ ! -x "$BIN" ] || [ "$FILM_SWIFT" -nt "$BIN" ]; then
  echo "  building window-film (swiftc)…"
  swiftc -O "$FILM_SWIFT" -o "$BIN" || { echo "renderer-film: swiftc failed" >&2; exit 1; }
fi

# The panes must outlive the take. Their own --duration is the teardown: when the last pane exits the
# window closes itself, so a crashed run cannot strand 18 repainting panes on a shared machine.
SETTLE=6
# A take on this box competes with the operator's live fleet for the foreground, and a take spoiled
# by a focus-steal is retried rather than published. The panes must outlive EVERY attempt, so their
# duration is sized for the whole retry budget — otherwise attempt 2 films a window whose panes have
# already exited, which looks like a renderer that stopped drawing.
ATTEMPTS=3
PANE_SECONDS=$(( SETTLE + ATTEMPTS * (SECONDS_TAKE + 8) + 10 ))
# Every pane sets the OS window title, so the title is right whichever pane has focus — that is what
# makes one title-matching rule work across four terminals with four different title behaviours.
PANE_CMD="printf '\033]0;${FILM_TITLE}\007'; exec bash '$REPO/scripts/tui-load.sh' --fps $FPS --duration $PANE_SECONDS --label film --stats ${TMPDIR:-/tmp}/renderer-film-load.tsv"

KITTY_BIN=/Applications/kitty.app/Contents/MacOS/kitty
KITTY_SOCK="unix:${TMPDIR:-/tmp}/kitty-ccfilm"
SPAWNED=0
GHOSTTY_WIN=""

spawn_kitty() {
  # --instance-group keeps this in its OWN process, so teardown can never reach the operator's kitty.
  "$KITTY_BIN" --instance-group=ccfilm -o allow_remote_control=yes --listen-on "$KITTY_SOCK" \
    -o enabled_layouts=grid -o remember_window_size=no \
    -o initial_window_width=1280 -o initial_window_height=692 -o font_size=11 \
    -o macos_quit_when_last_window_closed=yes --title "$FILM_TITLE" \
    --detach bash -c "$PANE_CMD" || return 1
  sleep 4
  SPAWNED=1
  local i=2
  while [ "$i" -le "$PANES" ]; do
    "$KITTY_BIN" @ --to "$KITTY_SOCK" launch --location=split --cwd="$REPO" \
      bash -c "$PANE_CMD" >/dev/null 2>&1 || break
    SPAWNED=$i; i=$(( i + 1 ))
  done
}

spawn_wezterm() {
  local cli=/opt/homebrew/bin/wezterm
  [ -x "$cli" ] || cli="$(command -v wezterm)"
  [ -n "$cli" ] || { echo "  ✗ wezterm not installed" >&2; return 1; }
  # --always-new-process gives this run its OWN gui process — the WezTerm equivalent of kitty's
  # --instance-group — so teardown can never reach a WezTerm the operator is using.
  #
  # 🚨 AND THAT PRIVATE PROCESS NEEDS ITS OWN SOCKET. `wezterm cli` talks to
  # ~/.local/share/wezterm/default-org.wezfurlong.wezterm, a SYMLINK to whichever instance claimed it
  # first — measured here, a symlink to gui-sock-46797, a pid dead since 17:12. The CLI failed to
  # connect, no split ever ran, and this harness reported "spawned only 1 pane" while a perfectly
  # healthy WezTerm sat on screen. The per-instance socket is gui-sock-<pid>; WEZTERM_UNIX_SOCKET
  # pointed at it addresses OUR process and no other.
  # `--config` is a GLOBAL flag and must precede the subcommand: after `start` it is rejected with
  # "unexpected argument '--config' found" — on stderr, from a backgrounded process, i.e. invisible.
  # 🚨 LAUNCH THROUGH LaunchServices (`open -n -a`), NOT THE CLI BINARY. A wezterm-gui started
  # directly from the shell has NO BUNDLE IDENTIFIER, and macOS will not activate a bundle-less
  # process: measured, `NSRunningApplication.activate` returned with `isActive` still false on all 16
  # attempts, the window was never drawn, and the take got ZERO frames. Launched via `open -n -a` the
  # same binary reports `bundleID=com.github.wez.wezterm` and can be raised.
  #
  # The launch route also RENAMES THE WINDOW OWNER: CGWindowList calls it "wezterm-gui" when started
  # from the CLI and "WezTerm" when started through LaunchServices. Same binary, same window, two
  # names — so the owner used to find the window has to follow the launch route (see OWNER below).
  open -n -a WezTerm --args --config font_size=11 \
     --config initial_cols=190 --config initial_rows=44 \
     start --always-new-process \
     -- bash -c "$PANE_CMD" >/dev/null 2>&1
  local gui_pid="" waited=0
  while [ "$waited" -lt 20 ]; do
    gui_pid="$(pgrep -f 'wezterm-gui.*--always-new-process' | tail -1)"
    [ -n "$gui_pid" ] && [ -S "$HOME/.local/share/wezterm/gui-sock-$gui_pid" ] && break
    sleep 1; waited=$(( waited + 1 ))
  done
  [ -n "$gui_pid" ] && [ -S "$HOME/.local/share/wezterm/gui-sock-$gui_pid" ] || {
    echo "  ✗ wezterm gui socket never appeared (pid=${gui_pid:-none})" >&2; return 1; }
  export WEZTERM_UNIX_SOCKET="$HOME/.local/share/wezterm/gui-sock-$gui_pid"
  sleep 2
  # ROUND-ROBIN over every pane, not repeated splits of the newest. A WezTerm split halves the
  # TARGET pane, so always splitting the newest shrinks that branch geometrically and hits the
  # minimum pane size early (measured in terminal-bakeoff.sh: 9 of 24 requested). Splitting every
  # existing pane once per round grows a balanced tree and reaches 18 at usable sizes.
  SPAWNED=1
  local progressed=1
  while [ "$SPAWNED" -lt "$PANES" ] && [ "$progressed" = 1 ]; do
    progressed=0
    local ids; ids="$(timeout 25 "$cli" cli list --format json 2>/dev/null \
                      | sed -n 's/.*"pane_id": *\([0-9]*\).*/\1/p' | sort -un)"
    [ -n "$ids" ] || break
    local id
    for id in $ids; do
      [ "$SPAWNED" -ge "$PANES" ] && break
      local dir=--right; [ $(( SPAWNED % 2 )) -eq 0 ] && dir=--bottom
      if timeout 25 "$cli" cli split-pane --pane-id "$id" "$dir" -- bash -c "$PANE_CMD" >/dev/null 2>&1; then
        SPAWNED=$(( SPAWNED + 1 )); progressed=1
      fi
    done
  done
}

spawn_ghostty() {
  # NO CLI IPC ON MACOS — `ghostty +new-window` answers "not supported on this platform" and there
  # is no control socket. What Ghostty ships is a full AppleScript dictionary where `split` returns
  # the new terminal, so every split is acknowledged individually and an under-spawn is OBSERVED.
  # The pane command goes through a FILE: Ghostty word-splits `command` itself and PANE_CMD contains
  # quotes, so interpolating it would put a quoting round-trip through AppleScript → Ghostty → sh.
  [ -d /Applications/Ghostty.app ] || { echo "  ✗ Ghostty.app not installed" >&2; return 1; }
  local sh="${TMPDIR:-/tmp}/renderer-film-ghostty-pane.sh"
  printf '%s\n' "$PANE_CMD" > "$sh"
  open -a Ghostty; sleep 3
  local out
  out="$(osascript - "$PANES" "/bin/sh $sh" <<'APPLESCRIPT' 2>&1
on run argv
	set target to (item 1 of argv) as integer
	set paneCmd to (item 2 of argv)
	tell application "Ghostty"
		set cfg to new surface configuration
		set command of cfg to paneCmd
		set win to new window with configuration cfg
		delay 1.5
		set made to 1
		set progressed to true
		repeat while (made < target) and progressed
			set progressed to false
			repeat with t in (terminals of win)
				if made >= target then exit repeat
				try
					split t direction right with configuration cfg
					set made to made + 1
					set progressed to true
				end try
				if made >= target then exit repeat
				try
					split t direction down with configuration cfg
					set made to made + 1
					set progressed to true
				end try
			end repeat
		end repeat
		-- 🚨 CREATED IS NOT ON SCREEN. Every Ghostty window on this box — including a freshly
		-- created one — read onscreen=nil in CGWindowList, because Ghostty was hidden or on
		-- another Space after the reboot restored it. The resolver then reported NO-MATCH with
		-- owner_windows=0, which reads like "the app is not running" when it plainly was.
		-- The Ghostty dictionary ships an "activate window" command, which is what maps it back.
		-- (No apostrophes or backticks in this heredoc: it sits inside a $( ) command substitution,
		-- where bash tracks quotes while scanning for the closing paren, so one stray quote character
		-- here produced a syntax error reported 100 lines further down the file.)
		activate
		activate window win
		delay 1
		return "winid=" & (id of win) & " achieved=" & (count of terminals of win)
	end tell
end run
APPLESCRIPT
)"
  case "$out" in
    winid=*) GHOSTTY_WIN="${out#winid=}"; GHOSTTY_WIN="${GHOSTTY_WIN%% *}"
             SPAWNED="${out##*achieved=}" ;;
    *) echo "  ✗ ghostty AppleScript driver failed: $out" >&2; SPAWNED=0; return 1 ;;
  esac
}

spawn_iterm2() {
  # 🚨 THE INCUMBENT IS NOT FILMED, AND THE REASON IS NOT SQUEAMISHNESS — IT WAS TRIED.
  #
  # The plan was sound on paper: scripts/terminal-bakeoff.sh makes iTerm2 measure-only because this
  # box normally runs the operator live Claude Code fleet inside it, so the guard was "film it only
  # when iTerm2 is NOT running" — no sessions present, no sessions disturbed. That guard passed.
  # iTerm2 was not running. It was launched anyway and the run still had to be aborted:
  #
  #   LAUNCHING iTerm2 RESTORES THE OPERATOR WINDOWS. Window restoration reopened three windows —
  #   one of them titled "Advance hook-chain cost durable record", another mid-command on a real
  #   project — none of which existed a second earlier. The AppleScript driver addresses "current
  #   window" (it must; the window object returned by `create window` goes stale across splits), and
  #   current window then resolved to a RESTORED window. Eighteen splits went into the operator
  #   windows instead of ours, and the resolver refused the take because no window carried the film
  #   title. iTerm2 was quit and the machine returned to not-running, as found.
  #
  # A not-running guard cannot fix this: the resurrection happens AT LAUNCH, before any check can
  # run. The sanctioned isolated route already exists — scripts/iterm-metal-bench-app.sh clones
  # iTerm2 under its own bundle id and its own defaults domain, which is the only way to get an
  # iTerm2 that restores nothing. Filming the incumbent is left to that path, deliberately unbuilt
  # here rather than shipped as a trap for whoever runs this next.
  echo "  ✗ iTerm2 is deliberately not filmed — launching it restores the operator windows and the" >&2
  echo "    splits land in THEIR sessions. See the comment above this refusal, and" >&2
  echo "    scripts/iterm-metal-bench-app.sh for the isolated-clone route that could do it safely." >&2
  return 1
}

# WHICH PIDS EXISTED BEFORE WE TOUCHED ANYTHING. The caveat further down needs to know whether the
# process finally measured is one we created or one that was already there hosting somebody else's
# surfaces — and that is a question about the PID, not about the app name.
#
# Keyed on the app name it is worse than useless: kitty deliberately films in its own
# --instance-group process, so the operator's live kitty being up says nothing about our instance,
# and the caveat fired on every kitty run while being true only of Ghostty. An alarm that always
# fires carries the same information as one that never does.
case "$APP" in
  wezterm|WezTerm) _procname=wezterm-gui ;;
  ghostty|Ghostty) _procname=ghostty ;;
  *)               _procname="$APP" ;;
esac
PIDS_BEFORE=" $(ps -eo pid=,comm= | awk -v want="$_procname" '{n=split($2,a,"/"); if (tolower(a[n])==tolower(want)) print $1}' | tr '\n' ' ')"

spawn_itermbench() {
  # THE INCUMBENT, FILMED SAFELY — via an isolated CLONE, which is the only way it can be done.
  # Filming the real iTerm2 was tried and had to be aborted: launching it RESTORES the operator's
  # windows, `current window` then resolves to one of theirs, and 18 splits landed in restored
  # sessions. scripts/iterm-metal-bench-app.sh clones iTerm2 under its own CFBundleIdentifier, which
  # gives it its own defaults domain and therefore NO window arrangement to restore — so the window
  # this driver creates is the only window that exists, and `current window` cannot mean anyone
  # else's. (The clone also carries a raised Metal pane cap, which is why it exists at all.)
  local app="${ITERMBENCH_APP:-/tmp/itermbench/iTermMetalBench.app}"
  [ -d "$app" ] || {
    echo "  ✗ no bench clone at $app — build it: scripts/iterm-metal-bench-app.sh --out /tmp/itermbench" >&2
    return 1; }
  local sh="${TMPDIR:-/tmp}/renderer-film-itermbench-pane.sh"
  printf '%s\n' "$PANE_CMD" > "$sh"
  open -n -a "$app" >/dev/null 2>&1
  sleep 10
  local out
  # `application id`, never the name: an unlaunched name lookup loads no terminology and puts up a
  # blocking "Choose Application" modal. `write text` rather than the `command` parameter, which
  # collides with a class name in this dictionary. `current window` rather than a held reference,
  # which goes stale across splits ("Can-t get window id 4547").
  out="$(osascript - "$PANES" "exec /bin/sh $sh" <<'ITERMBENCHSCRIPT' 2>&1
on run argv
	set target to (item 1 of argv) as integer
	set paneCmd to (item 2 of argv)
	-- The bundle id must be a LITERAL. A `tell application id <variable>` form cannot load the
	-- terminology at compile time, so every verb below parses as a class name and the script dies
	-- with "Expected end of line, etc. but found class name" — the same failure mode as targeting
	-- an unlaunched app by NAME.
	-- (No apostrophes or backticks in this heredoc: it sits inside a $( ), where bash tracks quotes
	-- while scanning for the closing paren. This file has now been broken that way TWICE.)
	tell application id "com.googlecode.iterm2.metalbench"
		activate
		create window with default profile
		delay 3
		-- Addressed as `window 1` — the clone has exactly one window, because its own bundle id
		-- gives it its own defaults domain and therefore nothing to restore. All three other
		-- specifiers were tried and all three fail here: a held reference goes stale across splits,
		-- `current window` is nil until a window becomes key (which under load does not happen
		-- inside the delay), and even `window id <n>` died mid-loop non-deterministically as iTerm2
		-- renumbered under contention. An index into a single-window app cannot go stale.
		tell (current session of current tab of window 1) to write text paneCmd
		set made to 1
		set progressed to true
		repeat while (made < target) and progressed
			set progressed to false
			repeat with s in (sessions of current tab of window 1)
				if made >= target then exit repeat
				try
					set ns to (split vertically with default profile) of s
					tell ns to write text paneCmd
					set made to made + 1
					set progressed to true
				end try
				if made >= target then exit repeat
				try
					set ns to (split horizontally with default profile) of s
					tell ns to write text paneCmd
					set made to made + 1
					set progressed to true
				end try
			end repeat
		end repeat
		-- CREATED IS NOT ON SCREEN — the same trap Ghostty sprang. After the splits the resolver
		-- reported owner_windows=0 for a window that plainly existed, because it was not mapped on
		-- the active Space. `select` is the iTerm2 dictionary verb that maps it back.
		activate
		-- Defensive: the window id can go stale by the time the splits finish, and a raise failing
		-- must not discard a window that already has 18 panes in it. The resolver still refuses if
		-- the window never comes on screen, so this cannot hide a bad take.
		try
			tell window 1 to select
		end try
		delay 2
		return "achieved=" & made
	end tell
end run
ITERMBENCHSCRIPT
)"
  case "$out" in
    achieved=*) SPAWNED="${out#achieved=}"; SPAWNED="${SPAWNED%% *}" ;;
    *) echo "  ✗ iTermMetalBench AppleScript driver failed: $out" >&2; SPAWNED=0; return 1 ;;
  esac
}

echo "== renderer-film  app=$APP panes=$PANES fps=$FPS take=${SECONDS_TAKE}s loadavg=$LOADNOW =="
case "$APP" in
  kitty)            spawn_kitty ;;
  wezterm|WezTerm)  spawn_wezterm ;;
  ghostty|Ghostty)  spawn_ghostty ;;
  iterm2|iTerm2)    spawn_iterm2 ;;
  itermbench)       spawn_itermbench ;;
  *) echo "renderer-film: no spawn strategy for '$APP'" >&2; exit 2 ;;
esac
if [ "${SPAWNED:-0}" -lt 2 ]; then
  echo "renderer-film: spawned only ${SPAWNED:-0} panes" >&2
  echo "verdict=SPAWN-FAILED"; exit 5
fi
# An under-spawn changes what the film shows, so it is NAMED rather than absorbed into "18 panes".
[ "$SPAWNED" -lt "$PANES" ] && echo "  ⚠ UNDER-SPAWNED — filming $SPAWNED panes, not $PANES"
echo "  spawned $SPAWNED panes; settling ${SETTLE}s"
sleep "$SETTLE"

# ── resolve OUR window, by title only ─────────────────────────────────────────────────────────────
# The CGWindow owner name is the running BINARY's name, which is not the app name and not the name
# `ps` reports: WezTerm's windows are owned by "wezterm-gui", so --owner WezTerm matched nothing and
# the harness refused with owner_windows=0. That refusal is the design working — it distinguishes
# "wrong app name" from "wrong title" — but the mapping has to be right or every WezTerm take fails.
OWNER="$APP"
case "$APP" in
  # "WezTerm" because spawn_wezterm launches through LaunchServices; a CLI-launched one would be
  # "wezterm-gui". The name is a property of the launch, not of the app.
  wezterm|WezTerm) OWNER="WezTerm" ;;
  ghostty|Ghostty) OWNER="Ghostty" ;;
  iterm2|iTerm2)   OWNER="iTerm2" ;;
  itermbench)      OWNER="iTermMetalBench" ;;
  kitty)           OWNER="kitty" ;;
esac
RECT_OUT="$(swift "$RECT_SWIFT" --owner "$OWNER" --title "$FILM_TITLE" --largest 2>&1)"
WID="$(printf '%s' "$RECT_OUT" | sed -n 's/.*wid=\([0-9]*\).*/\1/p')"
WPID="$(printf '%s' "$RECT_OUT" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')"
# Exact membership, spaces included, so pid 649 never matches pid 6491.
PID_PREEXISTED=no
case "$PIDS_BEFORE" in *" $WPID "*) PID_PREEXISTED=yes ;; esac
if [ -z "$WID" ]; then
  echo "renderer-film: could not resolve a window titled $FILM_TITLE for $OWNER" >&2
  printf '%s\n' "$RECT_OUT" >&2
  echo "verdict=NO-WINDOW"; exit 6
fi
echo "  window: $(printf '%s' "$RECT_OUT" | head -1)"

RAW="${TMPDIR:-/tmp}/renderer-film-$APP.mov"
MP4="$OUTDIR/renderer-$APP.mp4"
ROW="$OUTDIR/renderer-$APP.txt"

# ── the take, with a bounded retry ────────────────────────────────────────────────────────────────
# Every attempt runs the full gate: delivered-rate floor, resolution, frame rate, duration, freeze.
# A take is only kept if it passes all of them, so a retry can never launder a spoiled take into the
# README — it just buys another roll of the dice against whatever stole the foreground last time.
attempt_take() {
  FAILREASON=""

  # Take the MEASUREMENT during the take, not before or after it — the row and the film then
  # describe the same event, which is the whole claim the README makes about this pair of artifacts.
  # --pid, not just --app: the bench resolves a name to the LOWEST matching pid, which silently
  # measured a stale WezTerm instead of the one on camera (cpu=0.0 while it rendered at 40 fps).
  # WPID comes off the CGWindow we are filming, so the row and the film cannot describe different
  # processes.
  ( sleep 2; bash scripts/terminal-bench.sh --app "$APP" --pid "$WPID" --panes "$SPAWNED" --interval 0 > "$ROW" 2>&1 ) &
  local bench_pid=$!
  # An INDEPENDENT occlusion oracle, sampled mid-take. The delivered-rate floor already catches a
  # covered window, but it cannot say WHAT covered it; this names the app, so a spoiled take points
  # at a window to move instead of at a mystery.
  ( sleep 4; swift "$RECT_SWIFT" --owner "$OWNER" --title "$FILM_TITLE" --largest --assert-unoccluded > "$OCC_LOG" 2>&1 ) &
  local occ_pid=$!

  # NO EXTERNAL RAISE LOOP. An earlier version ran `open -a <App>` every 1.2 s during the take to
  # hold the foreground. It was written when activation appeared impossible — which turned out to be
  # the bundle-less-process problem, fixed at the launch site. Left in, it was a CONFOUND on the one
  # thing this film exists to show: it spawns a process 16 times per take and re-activates an app
  # that is already active, and the WezTerm takes made under it showed 1-5 freeze intervals that
  # must not be attributed to WezTerm while the instrument is still interfering. The film binary's
  # own activation is enough, and it acts only when the app is genuinely not active.
  FILM_OUT="$("$BIN" --window-id "$WID" --seconds "$SECONDS_TAKE" --activate --out "$RAW" 2>&1)"
  printf '%s\n' "$FILM_OUT" | sed 's/^/      /'
  wait "$bench_pid" 2>/dev/null
  wait "$occ_pid" 2>/dev/null

  case "$FILM_OUT" in
    *verdict=OK*) : ;;
    *) FAILREASON="CAPTURE-FAILED"; return 1 ;;
  esac

  # 🚨 verdict=OK FROM THE CAPTURE MEANS "FRAMES WERE WRITTEN", NOT "A TAKE HAPPENED".
  # The first run of this script produced THREE frames over 21 s — 0.14 fps, a 0.12-second master —
  # and every check that existed at the time passed it: genuinely 1920x1080, genuinely 60/1, and
  # freezedetect found nothing because there was no footage to freeze. A delivered-rate floor is the
  # check that could not have been fooled. The floor is half the load's own rate: the terminal is
  # being asked to repaint at $FPS, so near that is a real take and near zero is a window that was
  # not being drawn at all.
  local delivered floor
  delivered="$(printf '%s' "$FILM_OUT" | sed -n 's/.*[^_]fps=\([0-9.]*\).*/\1/p' | head -1)"
  floor="$(awk -v f="$FPS" 'BEGIN{printf "%.2f", f/2}')"
  if awk -v d="${delivered:-0}" -v f="$floor" 'BEGIN{exit !(d+0 < f+0)}'; then
    echo "      ⚠ only ${delivered:-0} fps delivered against a ${FPS} fps load (floor ${floor})" >&2
    sed 's/^/        /' "$OCC_LOG" >&2
    FAILREASON="STATIC"; return 1
  fi
  if grep -q 'verdict=OCCLUDED' "$OCC_LOG" 2>/dev/null; then
    echo "      note: something was over the window mid-take —" >&2
    sed -n 's/^occluder=/        occluder=/p' "$OCC_LOG" >&2
  fi

  # ── 1080p60 master ──────────────────────────────────────────────────────────────────────────────
  # scale-to-fit + pad, never crop: the window's aspect ratio is whatever the app made it, and
  # cropping to 16:9 would silently cut a row of panes out of the evidence.
  # force_original_aspect_ratio=decrease guarantees the scale is a DOWNscale from the 2x capture.
  #
  # crf 23, not 18. This content is close to incompressible — 18 panes of shifting 24-bit colour is
  # per-pixel noise, and at crf 18 a single 20 s take weighed 30 MB, which is not a README asset,
  # it is a permanent clone tax paid by everyone who ever fetches this repo. Measured on the same
  # take: crf 20 = 19.1 MB, crf 23 = 13.9 MB, crf 26 = 10.0 MB. 23 is the last step that leaves the
  # per-pane text and the colour ramp legible at full size, which is the whole point of the file.
  ffmpeg -y -v error -i "$RAW" \
    -vf "scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,fps=60" \
    -c:v libx264 -crf 23 -preset slow -pix_fmt yuv420p -an "$MP4" || {
    FAILREASON="CAPTURE-FAILED"; return 1; }

  # ── verify the artifact, do not assume it ───────────────────────────────────────────────────────
  local probe
  probe="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -of default=nw=1 "$MP4")"
  W="$(printf '%s' "$probe" | sed -n 's/^width=//p')"
  H="$(printf '%s' "$probe" | sed -n 's/^height=//p')"
  R="$(printf '%s' "$probe" | sed -n 's/^avg_frame_rate=//p')"
  if [ "$W" != 1920 ] || [ "$H" != 1080 ] || [ "$R" != "60/1" ]; then
    echo "      ⚠ master is ${W}x${H} @ $R, not 1920x1080 @ 60/1" >&2
    FAILREASON="CAPTURE-FAILED"; return 1
  fi

  # Duration is a SEPARATE assertion from resolution and rate, because the 3-frame take satisfied
  # both of those and lasted 0.12 s. 80% leaves room for the stream's start-up latency, nothing more.
  local dur mindur
  dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$MP4")"
  mindur="$(awk -v s="$SECONDS_TAKE" 'BEGIN{printf "%.2f", s*0.8}')"
  if awk -v d="${dur:-0}" -v m="$mindur" 'BEGIN{exit !(d+0 < m+0)}'; then
    echo "      ⚠ master is ${dur}s, short of the ${SECONDS_TAKE}s requested (floor ${mindur}s)" >&2
    FAILREASON="CAPTURE-FAILED"; return 1
  fi

  # STALLS ARE MEASURED AND PUBLISHED, NOT REFUSED — and they are measured AT THE SOURCE.
  #
  # This began as ffmpeg `freezedetect` over the finished master, and that instrument is wrong for
  # this content in a way that took a retraction to notice. It averages the difference over the
  # WHOLE frame, so on sparse coloured text it reported "freeze_start: 0" with no end — the entire
  # 20 s film called frozen — while 808 distinct frames sat in it. And its answer moved with how
  # much black padding each candidate's window shape required, so it was not comparable across the
  # very candidates being compared. A first reading off it ("WezTerm stalls, kitty does not") was
  # withdrawn.
  #
  # window-film.swift now reports the gaps between DELIVERED frames instead. ScreenCaptureKit emits
  # a frame only when the window content changes, so an interval between two frames IS the time the
  # window sat unchanged — no pixel heuristic, no dependence on aspect ratio or padding.
  STALLS="$(printf '%s' "$FILM_OUT" | sed -n 's/.*stalls=\([0-9]*\).*/\1/p' | head -1)"
  STALLED_S="$(printf '%s' "$FILM_OUT" | sed -n 's/.*stalled_s=\([0-9.]*\).*/\1/p' | head -1)"
  MAX_GAP="$(printf '%s' "$FILM_OUT" | sed -n 's/.*max_gap_s=\([0-9.]*\).*/\1/p' | head -1)"

  # The refusal is reserved for a film that is MOSTLY a still image; anything less is a reported
  # property of the subject. The delivered-rate floor above already caught the window that was not
  # being drawn at all, which is the failure this check used to be conflated with.
  local stalled_frac
  stalled_frac="$(awk -v f="${STALLED_S:-0}" -v d="${dur:-1}" 'BEGIN{printf "%.3f", (d>0)? f/d : 0}')"
  if awk -v x="$stalled_frac" 'BEGIN{exit !(x+0 > 0.4)}'; then
    echo "      ⚠ ${STALLED_S}s of ${dur}s with no content change — mostly a still image" >&2
    FAILREASON="STATIC"; return 1
  fi
  [ "${STALLS:-0}" -gt 0 ] && \
    echo "      note: ${STALLS} gap(s) >1.5s, ${STALLED_S}s total, longest ${MAX_GAP}s — recorded, not hidden"
  return 0
}

OCC_LOG="${TMPDIR:-/tmp}/renderer-film-occ-$APP.txt"
TAKE_OK=0
STALLS=0
STALLED_S=0.00
MAX_GAP=0.00
for attempt in $(seq 1 "$ATTEMPTS"); do
  # Re-checked per attempt, not just at start: the screen can lock DURING a run, and when it does
  # every remaining attempt is guaranteed to fail for a reason that has nothing to do with the
  # terminal. Spending the retry budget on it would bury the real cause.
  if screen_locked; then
    echo "renderer-film: the screen locked mid-run — no window is being drawn." >&2
    echo "  Unlock the Mac and re-run; retrying here cannot help." >&2
    echo "verdict=LOCKED"; exit 9
  fi
  echo "    take $attempt/$ATTEMPTS — ${SECONDS_TAKE}s, window-scoped, subject raised"
  if attempt_take; then TAKE_OK=1; break; fi
  echo "    take $attempt spoiled ($FAILREASON)"
done

# ── teardown ──────────────────────────────────────────────────────────────────────────────────────
# Close ONLY what we launched. Ghostty in particular is one shared process that may already host the
# operator's surfaces, so it is closed by window id and never with pkill.
case "$APP" in
  kitty)   "$KITTY_BIN" @ --to "$KITTY_SOCK" close-os-window >/dev/null 2>&1 ;;
  ghostty|Ghostty)
    [ -n "$GHOSTTY_WIN" ] && osascript -e "tell application \"Ghostty\" to close window (first window whose id is \"$GHOSTTY_WIN\")" >/dev/null 2>&1 ;;
  itermbench)
    osascript -e 'tell application id "com.googlecode.iterm2.metalbench" to quit' >/dev/null 2>&1 ;;
  iterm2|iTerm2)
    # Safe to quit outright: spawn_iterm2 refuses unless iTerm2 was NOT running, so this instance is
    # entirely ours and no operator session can be inside it.
    osascript -e 'tell application "iTerm2" to quit' >/dev/null 2>&1 ;;
  wezterm|WezTerm)
    cli=/opt/homebrew/bin/wezterm; [ -x "$cli" ] || cli="$(command -v wezterm)"
    for p in $(timeout 15 "$cli" cli list --format json 2>/dev/null | sed -n 's/.*"pane_id": *\([0-9]*\).*/\1/p' | sort -un); do
      timeout 10 "$cli" cli kill-pane --pane-id "$p" >/dev/null 2>&1
    done ;;
esac

[ "$KEEP_RAW" = 1 ] || rm -f "$RAW"

# Report the failure the LAST attempt actually hit — never a generic one. Three spoiled takes with
# the reason discarded would send a reader looking at the renderer when the cause was a browser.
if [ "$TAKE_OK" != 1 ]; then
  echo "renderer-film: $ATTEMPTS take(s) all spoiled; last reason: $FAILREASON" >&2
  rm -f "$MP4"
  echo "verdict=$FAILREASON"; exit 8
fi

BYTES="$(wc -c < "$MP4" | tr -d ' ')"
# Written INTO the row file: the stall count is a reading from this take, and a reading that lives
# only in a terminal scrollback is a reading that will be misremembered.
{
  printf 'film: %sx%s @ %s  %s bytes\n' "$W" "$H" "$R" "$BYTES"
  printf 'stalls: %s gap(s) >1.5s between delivered frames, %ss total, longest %ss, over a %ss take\n' \
    "${STALLS:-0}" "${STALLED_S:-0.00}" "${MAX_GAP:-0.00}" "$SECONDS_TAKE"
  printf 'load delivered: see %srenderer-film-load.tsv (achieved fps + SUSPECT flag per pane)\n' "${TMPDIR:-/tmp}"
  printf 'measured pid: %s (that pid pre-existed this run: %s)\n' "${WPID:-?}" "$PID_PREEXISTED"
  if [ "$PID_PREEXISTED" = yes ]; then
    printf 'CAVEAT: that process pre-existed this run, so its totals may include surfaces this film\n'
    printf '        did not create. Read the app-wide columns; the per-pane division is an upper bound.\n'
  fi
} >> "$ROW"
echo "  master: $MP4  ${W}x${H} @ $R  ${BYTES} bytes"
echo "  stalls: ${STALLS:-0} gap(s) >1.5s totalling ${STALLED_S:-0.00}s, longest ${MAX_GAP:-0.00}s"
echo "  row:    $ROW  ($(sed -n 's/.*\(verdict=[A-Z-]*\).*/\1/p' "$ROW" | tail -1))"
echo "verdict=OK app=$APP panes=$SPAWNED"
