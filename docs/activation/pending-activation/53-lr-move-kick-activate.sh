#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 53-lr-move-kick  —  start `cc-lr move` batches the moment they are asked for, in the Interactive band
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY (2026-10-18, docs/research/lr-inplace-immediacy-2026-10-18/REPORT.md §6 item 1): every process
#   the move lane runs — batch runner, worker, lr-handoff, handoff-fire, the recycle watcher — sat at
#   priority 20, because their only starter, com.reso.lr-reset-poller, has no ProcessType and launchd
#   gives such a job its default light limits; a child cannot climb back to 31. The load they compete
#   with ran at 31 (755 processes at 31 against 137 at 20). A nominal 5 s wait took 41-50 s and the
#   recycle precheck 163 s. The same default starved com.claude.research-classifier-warm on 2026-10-08,
#   and `ProcessType Interactive` read back PRI 31/37 there (memory darwin-qos-band-mechanics).
#
# WHAT THIS DOES — no root, re-runnable, every step idempotent:
#   1. installs ~/Library/LaunchAgents/com.reso.lr-move-kick.plist from launchd/staged/ if absent or
#      different (staged/ is outside install.sh's glob: this script is the only way it is installed)
#   2. loads (bootstraps) it if it is not loaded, clearing a domain-level disabled bit first
#   3. verifies by READING BACK from a real run: it starts one run of the job (`launchctl kickstart`,
#      never -k: a run in flight is left alone) and reads the `MOVE-KICK pri N` line that run wrote to
#      poller.log. Fails closed unless N >= 31. With no request queued that run claims nothing.
#
# WHAT CHANGES ONCE IT IS LOADED: a request `cc-lr move` writes to move/requests/ starts its batch
#   within ~1-2 s (launchd's WatchPaths, ThrottleInterval 2) at the Interactive band, whether or not a
#   poller tick is running. The poller's own kick and mid-tick drainer stay as the fallback; the
#   hard-link claim keeps a batch from ever starting twice. Kill switch without unloading:
#   LR_MOVE_LANE=off in the job's environment stops every kick, as it does for the poller.
#   Uninstall: launchctl bootout gui/$(id -u)/com.reso.lr-move-kick; rm ~/Library/LaunchAgents/com.reso.lr-move-kick.plist
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
LABEL=com.reso.lr-move-kick
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SRC_PLIST="$REPO/launchd/staged/$LABEL.plist"
POLLER="$HOME/.claude/scripts/limit-recover/lr-reset-poller.sh"
DST_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/.reso/limit-recover/poller.log"
DOMAIN="gui/$(id -u)"
if [ $# -gt 0 ]; then echo "usage: $0   (no arguments; re-runnable)" >&2; exit 2; fi

fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$SRC_PLIST" ] || fail "missing $SRC_PLIST (has the fix landed and converged into $REPO?)"
/usr/bin/plutil -lint "$SRC_PLIST" >/dev/null || fail "$SRC_PLIST does not parse"
grep -q -- '--move-kick' "$POLLER" 2>/dev/null || fail "$POLLER has no --move-kick mode yet (converge first: CC_DEPLOY_MAX_LAG_COMMITS=0 bash $REPO/scripts/deploy-live.sh)"
mkdir -p "$HOME/.reso/limit-recover/move/requests" || fail "cannot create the watched move/requests/ dir"

echo "== 1. LaunchAgent plist"
mkdir -p "$HOME/Library/LaunchAgents"
if [ -f "$DST_PLIST" ] && cmp -s "$SRC_PLIST" "$DST_PLIST"; then echo "   present, matches the repo"
else
  /bin/cp "$SRC_PLIST" "$DST_PLIST" || fail "could not write $DST_PLIST"
  echo "   installed"
fi

echo "== 2. load $LABEL"
if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then echo "   loaded"
else
  if launchctl print-disabled "$DOMAIN" 2>/dev/null | grep -F "\"$LABEL\" => disabled" >/dev/null; then
    launchctl enable "$DOMAIN/$LABEL" || fail "launchctl enable $LABEL failed"
    echo "   cleared the domain-level disabled bit"
  fi
  launchctl bootstrap "$DOMAIN" "$DST_PLIST" 2>/dev/null || true
  launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 && echo "   loaded now" || fail "could not load $LABEL"
fi

echo "== 3. verify the band from a real run (read back, fail closed)"
before="$(grep -c 'MOVE-KICK pri' "$LOG" 2>/dev/null || true)"; before="${before:-0}"
launchctl kickstart "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
pri=""
for _ in $(seq 1 30); do
  now="$(grep -c 'MOVE-KICK pri' "$LOG" 2>/dev/null || true)"
  if [ "${now:-0}" -gt "$before" ]; then pri="$(grep 'MOVE-KICK pri' "$LOG" | tail -1 | awk '{ print $NF }')"; break; fi
  sleep 1
done
[ -n "$pri" ] || fail "no run of $LABEL wrote a MOVE-KICK line to $LOG within 30 s — check ~/.reso/limit-recover/move-kick.launchd.err"
[[ "$pri" =~ ^[0-9]+$ ]] || fail "unreadable priority '$pri' in $LOG"
[ "$pri" -ge 31 ] || fail "$LABEL ran at priority $pri, not the Interactive band (>= 31): the fix does not hold on this macOS"
echo "   a real run read priority $pri"
mkdir -p "$HOME/.claude/autonomy/pending-activation" 2>/dev/null || true
touch "$HOME/.claude/autonomy/pending-activation/53-lr-move-kick-activate.sh.done" 2>/dev/null || true
echo "OK: $LABEL loaded; the next cc-lr move batch starts within ~2 s at priority $pri"
echo "Uninstall: launchctl bootout $DOMAIN/$LABEL; rm $DST_PLIST"
