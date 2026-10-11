#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 51-chime-player  —  load the resident chime player, so a chime stops being a new coreaudiod client
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY (2026-10-10): every chime hooks/notify.sh plays was a fresh `/usr/bin/afplay`, i.e. a NEW
#   coreaudiod client, ~300 a day. Measured from coreaudiod's own log: each new client process costs
#   3 TCCAccessRequest calls in coreaudiod, while one long-lived process paid 3 at its first play and 0
#   for the next two. On 2026-10-09 one chime's permission check parked coreaudiod ~7 minutes behind a
#   stalled trustd/secd and froze Hammerspoon. com.claude.chime-player is that long-lived process:
#   notify.sh drops a request file into its spool and returns; the player plays it with a cached NSSound.
#
# WHAT THIS DOES — no root, re-runnable, every step idempotent:
#   1. links ~/.claude/scripts/chime-player.sh if the converge has not yet (its .js stays beside the
#      checkout copy; the wrapper finds it through the link)
#   2. installs ~/Library/LaunchAgents/com.claude.chime-player.plist from launchd/staged/ if absent or
#      different (staged/ is outside install.sh's glob, so a converge never installs it: this is the one way)
#   3. loads (bootstraps) the agent if it is not loaded, clearing a domain-level disabled bit first
#   4. verifies by reading back: `launchctl print` says running with a pid, and the player's heartbeat
#      (the file notify.sh reads to decide whether to enqueue) is fresh. Fails closed on either.
#
# WHAT CHANGES ONCE IT IS LOADED: notify.sh sees a fresh heartbeat and enqueues instead of forking
#   afplay. If the player wedges (heartbeat older than 15 s, most likely a stalled coreaudiod), chimes
#   are DROPPED rather than handed to a new afplay client — that is the failure being avoided. The
#   desktop banners are untouched. Kill switch without unloading: CC_NOTIFY_CHIME_PLAYER=off.
#   After running this, the fleet.manifest row for com.claude.chime-player should move staged -> run.
#   Uninstall (notify.sh falls back to afplay once the heartbeat file is gone):
#     launchctl bootout gui/$(id -u)/com.claude.chime-player; rm ~/Library/LaunchAgents/com.claude.chime-player.plist; rm -r "$(getconf DARWIN_USER_TEMP_DIR)cc-chime"
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
LABEL=com.claude.chime-player
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SRC="$REPO/scripts/chime-player.sh"
SRC_JS="$REPO/scripts/chime-player.js"
SRC_PLIST="$REPO/launchd/staged/$LABEL.plist"   # staged/: outside install.sh's glob, so only THIS loads it
DST_LINK="$HOME/.claude/scripts/chime-player.sh"
DST_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
if [ $# -gt 0 ]; then echo "usage: $0   (no arguments; re-runnable)" >&2; exit 2; fi

fail() { echo "FAIL: $*" >&2; exit 1; }
for f in "$SRC" "$SRC_JS" "$SRC_PLIST"; do [ -f "$f" ] || fail "missing $f (has the fix landed and converged into $REPO?)"; done
/usr/bin/plutil -lint "$SRC_PLIST" >/dev/null || fail "$SRC_PLIST does not parse"

echo "== 1. player script link"
if [ -e "$DST_LINK" ]; then echo "   present"
else
  mkdir -p "$HOME/.claude/scripts"
  ln -sfn "$SRC" "$DST_LINK" && echo "   linked (a converge would have done the same)"
fi
[ -x "$DST_LINK" ] || fail "$DST_LINK is not executable"

echo "== 2. LaunchAgent plist"
mkdir -p "$HOME/Library/LaunchAgents"
if [ -f "$DST_PLIST" ] && cmp -s "$SRC_PLIST" "$DST_PLIST"; then echo "   present, matches the repo"
else
  /bin/cp "$SRC_PLIST" "$DST_PLIST" || fail "could not write $DST_PLIST"
  echo "   installed"
fi

echo "== 3. load $LABEL"
if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then echo "   loaded"
else
  if launchctl print-disabled "$DOMAIN" 2>/dev/null | grep -qF "\"$LABEL\" => disabled"; then
    launchctl enable "$DOMAIN/$LABEL" || fail "launchctl enable $LABEL failed"
    echo "   cleared the domain-level disabled bit"
  fi
  launchctl bootstrap "$DOMAIN" "$DST_PLIST" 2>/dev/null || true
  launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 && echo "   loaded now" || fail "could not load $LABEL"
fi

echo "== 4. verify (read back, fail closed)"
base="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
[ -n "$base" ] || fail "getconf DARWIN_USER_TEMP_DIR failed"
hb="${base%/}/cc-chime/heartbeat"
age=999; pid=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  pid="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null | awk '$1 == "pid" && $2 == "=" { print $3; exit }')"
  if [ -n "$pid" ] && [ -f "$hb" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$hb" 2>/dev/null || echo 0) ))
    [ "$age" -le 15 ] && break
  fi
  sleep 1
done
launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -q 'state = running' \
  || fail "$LABEL is loaded but not running — check ~/.claude/logs/chime-player.err.log"
[ -n "$pid" ] || fail "$LABEL reports no pid"
[ -f "$hb" ] || fail "no heartbeat at $hb after 20 s — check ~/.claude/logs/chime-player.err.log"
[ "$age" -le 15 ] || fail "heartbeat is ${age}s old (notify.sh would DROP chimes) — check ~/.claude/logs/chime-player.err.log"
echo "   running, pid $pid, heartbeat ${age}s old"
tail -1 "$HOME/.claude/logs/chime-player.err.log" 2>/dev/null | sed 's/^/   /'
touch "$HOME/.claude/autonomy/pending-activation/51-chime-player-activate.sh.done" 2>/dev/null || true
echo "OK: $LABEL loaded; the next admitted chime goes through it (notify log: 'via player')"
echo "Uninstall: launchctl bootout $DOMAIN/$LABEL; rm $DST_PLIST; rm -r \"${base%/}/cc-chime\""
