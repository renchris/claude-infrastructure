#!/bin/bash
# iterm-clear-sticky-command.sh — clear the STICKY per-session custom-command override that
# iTerm2 attaches to any pane created via AppleScript's `… with default profile command "X"`.
#
# THE BUG IT REPAIRS (incident 2026-07-25)
# `tell app "iTerm2" to (create window|split vertically) with default profile command "X"` does
# NOT run X once — iTerm2 stores X as a SESSION-SCOPED PROFILE OVERRIDE (use_custom_command=Yes,
# command=X) on the created session. ⌘D ("Split … with Current Profile") copies the CURRENT
# session's profile, override included, so every split off that pane re-runs X. The clones carry
# the override too, so it self-propagates for the life of the window. Live proof 2026-07-25: a
# single `/limit-recover handoff` fire at 01:28 left 4 panes pinned to
# `/bin/bash /tmp/lr-launch-076a1186.sh`, and three ⌘D presses at 17:55/17:56/17:57 each spawned a
# fresh `claude --resume 076a1186…` — concurrent duplicate resumes of ONE transcript — instead of
# the plain shell the operator asked for.
#
# The producers are fixed at source (lr-handoff.sh / lr-reset-poller.sh now create a bare pane and
# TYPE the launcher, the pattern handoff-fire.sh already used). This script repairs panes that were
# ALREADY created with the override — the fix cannot reach them, they outlive it, and each one is a
# live ⌘D trap. Clearing an override never touches the running process: it only decides what a
# FUTURE split inherits.
#
# Usage: iterm-clear-sticky-command.sh [--dry-run] [--all]
#   (default)  clear only overrides pointing at a generated launcher (/tmp/lr-launch-*.sh,
#              /tmp/lr-poller-launch-*.sh, /tmp/handoff-*.sh) — never a hand-configured profile
#   --all      clear EVERY session-local custom-command override
#   --dry-run  list what would be cleared, change nothing
set -uo pipefail

DRY=0 ALL=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --all)     ALL=1 ;;
    -h|--help) sed -n '1,30p' "$0"; exit 0 ;;
    *) echo "iterm-clear-sticky-command: unknown arg $a" >&2; exit 2 ;;
  esac
done

# Fail OPEN and quiet on a machine with no iTerm2 python API (headless/CI) — this is a repair
# convenience, never a gate. Exit 0 so a caller chaining it is not broken by its absence.
python3 -c 'import iterm2' 2>/dev/null || {
  echo "iterm-clear-sticky-command: iterm2 python module unavailable — nothing to do" >&2; exit 0; }

DRY="$DRY" ALL="$ALL" python3 <<'PY'
import os, re, sys
import iterm2

DRY = os.environ.get("DRY") == "1"
ALL = os.environ.get("ALL") == "1"
# Generated-launcher shapes written by our own fire paths. Anything else is presumed operator-owned.
LAUNCHER = re.compile(r"/tmp/(lr-launch-|lr-poller-launch-|handoff-)[^\s]*\.sh")

async def main(connection):
    app = await iterm2.async_get_app(connection)
    found = cleared = 0
    for w in app.terminal_windows:
        for t in w.tabs:
            for s in t.sessions:
                p = await s.async_get_profile()
                if p.use_custom_command != "Yes":
                    continue
                cmd = p.command or ""
                found += 1
                ours = bool(LAUNCHER.search(cmd))
                if not (ALL or ours):
                    print("SKIP  %s — custom command not one of ours: %r" % (s.session_id[:8], cmd))
                    continue
                if DRY:
                    print("WOULD-CLEAR %s — %r" % (s.session_id[:8], cmd))
                    cleared += 1
                    continue
                change = iterm2.LocalWriteOnlyProfile()
                change.set_use_custom_command("No")
                change.set_command("")
                await s.async_set_profile_properties(change)
                print("CLEARED %s — was %r" % (s.session_id[:8], cmd))
                cleared += 1
    verb = "would clear" if DRY else "cleared"
    print("iterm-clear-sticky-command: %d session(s) with a custom command, %s %d"
          % (found, verb, cleared))
    # A cleared pane's OWN running process is untouched; only its ⌘D inheritance is repaired.

iterm2.run_until_complete(main)
PY
