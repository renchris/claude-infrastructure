#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 23-qos-census  —  put the QoS coverage census on a 10-min cadence (row 13 completion, M12)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two idempotent steps. (1) symlink scripts/qos-census.sh into the live ~/.claude/scripts/
#   layer if absent — a BRAND-NEW file is never auto-linked by a per-file symlink dir
#   (memory deploy-lag-checkout-behind-origin). (2) load com.claude.qos-census
#   (StartInterval 600, RunAtLoad false, Background/Nice 10).
#
# WHY: AC1 (≥95% batch-band coverage) is a CONTINUOUS claim; before 2026-07-30 every row in
#   ~/.claude/logs/qos-census.jsonl was a manual run — the census existed, the cadence did not
#   (feature-durability-mechanism-not-memory). NO-BURST ticks are cheap honest non-verdicts
#   (exit 3 is a DESIGNED outcome — daemon-fleet-v2: do not "fix" it to exit 0).
#
# WHY C10 (agent stages; operator loads): loading a launchd job IS an activation.
# Kill after load: launchctl bootout gui/$UID/com.claude.qos-census.
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.qos-census.plist"
SRC="$REPO/scripts/qos-census.sh"
DEST="$HOME/.claude/scripts/qos-census.sh"
LA="$HOME/Library/LaunchAgents"

echo "== 23-qos-census =="
[ -f "$SRC" ] || { echo "✗ missing in checkout: $SRC (is the checkout on a trunk with this commit?)" >&2; exit 1; }
[ -f "$REPO/launchd/$PLIST" ] || { echo "✗ missing plist: $REPO/launchd/$PLIST" >&2; exit 1; }

echo "Will do: [0] run $SRC --quiet once (any of exits 0/1/3 is a valid verdict; only a crash blocks)"
echo "         [1] symlink $SRC → $DEST (if not already linked)"
echo "         [2] cp launchd/$PLIST → $LA/ ; plutil -lint ; launchctl enable ; launchctl bootstrap"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/23-qos-census-activate.sh"
  exit 0
fi

echo "[0] smoke run (verdict-tolerant)"
bash "$SRC" --quiet --no-append; rc=$?
case "$rc" in
  0|1|3) echo "  · verdict exit $rc — a valid census outcome, proceeding" ;;
  *)     echo "✗ census crashed (exit $rc) — NOT activating" >&2; exit 1 ;;
esac

echo "[1] symlink"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "✗ $DEST exists and is NOT a symlink — refusing to clobber a real file" >&2; exit 1
fi
ln -sfn "$SRC" "$DEST"
echo "  · $DEST → $(readlink "$DEST")"

echo "[2] launchd"
mkdir -p "$LA"
cp -f "$REPO/launchd/$PLIST" "$LA/$PLIST"
plutil -lint "$LA/$PLIST" || { echo "✗ plist lint failed" >&2; exit 1; }
launchctl enable "gui/$(id -u)/com.claude.qos-census" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.claude.qos-census" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LA/$PLIST" || { echo "✗ bootstrap failed" >&2; exit 1; }
launchctl print "gui/$(id -u)/com.claude.qos-census" | grep -E 'state|last exit' | head -3 || true

echo "DONE. Verify later:  tail -3 ~/.claude/logs/qos-census.jsonl   (rows every ~600 s)"
echo "Then:  touch $HOME/.claude/autonomy/pending-activation/23-qos-census-activate.sh.done"
