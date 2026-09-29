#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 48-coreaudiod-watchdog  —  install the root watchdog that restarts a leaking coreaudiod
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY (docs/research/coreaudiod-spin-2026-09-29.md): under CPU starvation coreaudiod stops releasing
#   client IO contexts. It held 5,117 when restarted on 2026-09-24 and 4,641 on 2026-09-29, sat at
#   ~200% CPU for days, and only a restart frees them. The user-level detector
#   (com.claude.coreaudiod-watch) sees it but cannot act: restarting coreaudiod needs root.
#
# WHAT THIS DOES — re-runnable, every step idempotent:
#   1. (no root) links ~/.claude/scripts/coreaudiod-watch.sh if the converge has not yet
#   2. (no root) loads the user detector com.claude.coreaudiod-watch if it is not loaded
#   3. (ROOT, needs --confirm com.claude.coreaudiod-watchdog) copies the watcher to a ROOT-OWNED
#      /usr/local/libexec/claude-coreaudiod-watch.sh, installs
#      /Library/LaunchDaemons/com.claude.coreaudiod-watchdog.plist and loads it. macOS shows its
#      own administrator dialog (Touch ID or password) for this step.
#   4. verifies by reading back: the daemon is loaded, the copy is root-owned, and its first run
#      wrote a verdict line.
# Without --confirm it performs 1-2 and prints what 3 would do.
#
# WHAT IT CANNOT UNDO BY ITSELF: once loaded, the daemon will `killall coreaudiod` when >= 1000
#   contexts are held (or >= 300 with >= 100% CPU), at most every 30 min and never while an audio
#   input younger than 3 h is live. Audio drops for about a second at each restart. Uninstall:
#     sudo launchctl bootout system/com.claude.coreaudiod-watchdog
#     sudo rm /Library/LaunchDaemons/com.claude.coreaudiod-watchdog.plist /usr/local/libexec/claude-coreaudiod-watch.sh
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
LABEL=com.claude.coreaudiod-watchdog
USER_LABEL=com.claude.coreaudiod-watch
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SRC="$REPO/scripts/coreaudiod-watch.sh"
SRC_PLIST="$REPO/launchd/system/$LABEL.plist"
USER_PLIST="$REPO/launchd/$USER_LABEL.plist"
DST=/usr/local/libexec/claude-coreaudiod-watch.sh
DST_PLIST=/Library/LaunchDaemons/$LABEL.plist
CONFIRM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    *) echo "usage: $0 [--confirm $LABEL]" >&2; exit 2 ;;
  esac
done

fail() { echo "FAIL: $*" >&2; exit 1; }
for f in "$SRC" "$SRC_PLIST" "$USER_PLIST"; do [ -f "$f" ] || fail "missing $f (has the fix landed and converged into $REPO?)"; done
/usr/bin/plutil -lint "$SRC_PLIST" >/dev/null || fail "$SRC_PLIST does not parse"

echo "== 1. user detector script link"
if [ ! -e "$HOME/.claude/scripts/coreaudiod-watch.sh" ]; then
  ln -sfn "$SRC" "$HOME/.claude/scripts/coreaudiod-watch.sh" && echo "   linked"
else echo "   present"; fi

echo "== 2. user detector job"
if launchctl list "$USER_LABEL" >/dev/null 2>&1; then echo "   loaded"
else
  ln -sfn "$USER_PLIST" "$HOME/Library/LaunchAgents/$USER_LABEL.plist"
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$USER_LABEL.plist" 2>/dev/null || true
  launchctl list "$USER_LABEL" >/dev/null 2>&1 && echo "   loaded now" || fail "could not load $USER_LABEL"
fi
"$HOME/.claude/scripts/coreaudiod-watch.sh" | sed 's/^/   /'

echo "== 3. root watchdog $LABEL"
if [ "$CONFIRM" != "$LABEL" ]; then
  echo "   NOT installed. Re-run with: --confirm $LABEL"
  echo "   It would copy $SRC -> $DST (root:wheel 755), $SRC_PLIST -> $DST_PLIST, and load it."
  exit 0
fi
tmpd="$(mktemp -d /tmp/cadw.XXXXXX)"; chmod 700 "$tmpd"
cat > "$tmpd/root.sh" <<EOF
set -e
/bin/mkdir -p /usr/local/libexec
/usr/bin/install -o root -g wheel -m 755 "$SRC" "$DST"
/usr/bin/install -o root -g wheel -m 644 "$SRC_PLIST" "$DST_PLIST"
/bin/launchctl bootout system/$LABEL 2>/dev/null || true
/bin/launchctl bootstrap system "$DST_PLIST"
EOF
/usr/bin/osascript -e "do shell script \"/bin/bash $tmpd/root.sh\" with administrator privileges" >/dev/null \
  || { rm -rf "$tmpd"; fail "administrator step refused or failed (nothing past this point ran)"; }
rm -rf "$tmpd"

echo "== 4. verify (read back, fail closed)"
launchctl print "system/$LABEL" >/dev/null 2>&1 || fail "$LABEL is not loaded"
[ "$(/usr/bin/stat -f %Su "$DST")" = root ] || fail "$DST is not root-owned"
cmp -s "$SRC" "$DST" || fail "$DST differs from $SRC"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s /var/log/claude-coreaudiod-watchdog.stdout.log ] && break; sleep 1
done
v="$(grep -o 'verdict=[a-z]*' /var/log/claude-coreaudiod-watchdog.stdout.log 2>/dev/null | tail -1)"
[ -n "$v" ] || fail "the daemon loaded but has not written a verdict yet — check /var/log/claude-coreaudiod-watchdog.stderr.log"
echo "   loaded, root-owned, first run: $v"
tail -1 /var/log/claude-coreaudiod-watchdog.stdout.log 2>/dev/null | sed 's/^/   /'
touch "$HOME/.claude/autonomy/pending-activation/48-coreaudiod-watchdog-install.sh.done" 2>/dev/null || true
echo "OK: $LABEL installed"
