#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 02-load-dispatcher  —  run AFTER 01 (reap-guard) is engaged
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: loads com.claude.dispatcher (RunAtLoad=false, StartInterval 900) — the cron dispatcher spine
#   that pulls cc-backlog → cc-wave-plan quota-places → claims + spawns sessions. Loading this plist IS
#   the "autonomous-operator-goes-live" ratification (operator decisions #5/#6).
# PRECONDITION: 01-reap-guard-insert must be .done (Sequencing Law). cc-dispatch is symlinked live.
# C10: agent staged; operator loads. Sanity-run `cc-dispatch --once --dry-run` by hand first.
# Authoritative: docs/activation/dispatcher-activate-snippet.md
# Mark done: touch ~/.claude/autonomy/pending-activation/02-load-dispatcher-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.dispatcher.plist"

echo "== 02-load-dispatcher =="
if [ ! -f "$HOME/.claude/autonomy/pending-activation/01-reap-guard-insert-activate.sh.done" ]; then
  echo "⚠ PRECONDITION: 01-reap-guard-insert is NOT marked .done. Engage reap-guard FIRST (Sequencing Law)." >&2
fi
echo "Pre-flight (do by hand first): cc-dispatch --once --dry-run"
echo "Load:"
echo "    cp $REPO/launchd/$PLIST ~/Library/LaunchAgents/$PLIST"
echo "    plutil -lint ~/Library/LaunchAgents/$PLIST"
echo "    launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/$PLIST"
echo "    launchctl print gui/\$(id -u)/com.claude.dispatcher | grep -E 'state|program'"
echo

if [ "${CONFIRM:-0}" = 1 ]; then
  if cp "$REPO/launchd/$PLIST" "$HOME/Library/LaunchAgents/$PLIST" \
       && plutil -lint "$HOME/Library/LaunchAgents/$PLIST" \
       && launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$PLIST"; then
    echo "✓ dispatcher loaded (RunAtLoad=false → first pass in one StartInterval)."
  else
    echo "✗ load failed — inspect above" >&2; exit 1
  fi
else
  echo "(dry: re-run with CONFIRM=1 to cp+lint+bootstrap.)"
fi

echo
echo "ROLLBACK: launchctl bootout gui/\$(id -u)/com.claude.dispatcher ; rm ~/Library/LaunchAgents/$PLIST"
