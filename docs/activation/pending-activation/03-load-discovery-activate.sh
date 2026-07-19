#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 03-load-discovery  —  run AFTER 02 (dispatcher)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: loads com.claude.discovery (RunAtLoad=false, hourly) — the 4 standing critics (C1 frontier-hole /
#   C2 plan-open / C3 wiring-inert-D9 / C4 gate-red) that refill cc-backlog idempotently. Absent-source →
#   ABSTAIN, never fabricate. Feeds the dispatcher's future waves.
# C10: agent staged; operator loads. cc-discover is symlinked live; run `cc-discover --once --dry-run` first.
# Authoritative: docs/activation/discovery-activate-snippet.md
# Mark done: touch ~/.claude/autonomy/pending-activation/03-load-discovery-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.discovery.plist"

echo "== 03-load-discovery =="
echo "Pre-flight (by hand): cc-discover --once --dry-run"
echo "Load:"
echo "    cp $REPO/launchd/$PLIST ~/Library/LaunchAgents/$PLIST"
echo "    plutil -lint ~/Library/LaunchAgents/$PLIST"
echo "    launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/$PLIST"
echo

if [ "${CONFIRM:-0}" = 1 ]; then
  if cp "$REPO/launchd/$PLIST" "$HOME/Library/LaunchAgents/$PLIST" \
       && plutil -lint "$HOME/Library/LaunchAgents/$PLIST" \
       && launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$PLIST"; then
    echo "✓ discovery loaded (RunAtLoad=false → first pass hourly)."
  else
    echo "✗ load failed — inspect above" >&2; exit 1
  fi
else
  echo "(dry: re-run with CONFIRM=1 to cp+lint+bootstrap.)"
fi

echo
echo "ROLLBACK: launchctl bootout gui/\$(id -u)/com.claude.discovery ; rm ~/Library/LaunchAgents/$PLIST"
