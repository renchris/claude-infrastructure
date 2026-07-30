#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 19-capacity-alarm  —  fire the memory-ceiling alarm every 10 min (row 13 M6)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two idempotent steps. (1) symlink scripts/capacity-alarm.sh into the live ~/.claude/scripts/
#   layer — required because it is a BRAND-NEW file and per-file symlink dirs never auto-link one
#   (memory deploy-lag-checkout-behind-origin). (2) load com.claude.capacity-alarm
#   (StartInterval 600, RunAtLoad false, Background/Nice 10).
#
# WHY: row 13 measured a real ceiling (~50 concurrent sessions on this 10-core/64 GiB box) and shipped
#   the reader, but a built alarm that nothing invokes is INERT — the exact
#   feature-durability-mechanism-not-memory failure. Without this the ceiling is documented and
#   unwatched, and pressure gets discovered by swapping (the lagging indicator).
#
# WHY IT IS CHEAP ENOUGH TO EXIST (this row is about NOT adding load): one vm_stat + one sysctl + one
#   ps + one python3, ~100-200 ms/tick ⇒ ~0.03% of one core at 600 s, in the BACKGROUND band.
#
# IT NEVER REFUSES ANYTHING — it reports and exits. Do NOT "upgrade" it into a spawn gate: the landed
#   capacity_gate() scores REFUSE 10/10 against real sampled load, i.e. a permanent dispatch outage
#   (docs/plans/MACHINE_CAPACITY_V2.md §8.5.7).
#
# WHY C10 (agent stages; operator loads): loading a launchd job IS an activation.
# Kill switches after load: CC_CAPACITY_ALARM=off · CC_CAP_PAGE=off (page only) · launchctl bootout.
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.capacity-alarm.plist"
SRC="$REPO/scripts/capacity-alarm.sh"
DEST="$HOME/.claude/scripts/capacity-alarm.sh"
LA="$HOME/Library/LaunchAgents"

echo "== 19-capacity-alarm =="
[ -f "$SRC" ] || { echo "✗ missing in checkout: $SRC (is the checkout on a trunk with this commit?)" >&2; exit 1; }
[ -f "$REPO/launchd/$PLIST" ] || { echo "✗ missing plist: $REPO/launchd/$PLIST" >&2; exit 1; }

echo "Will do: [0] $SRC --selftest  (proves all 4 verdict rungs are reachable, side-effect-free)"
echo "         [1] symlink $SRC → $DEST"
echo "         [2] cp launchd/$PLIST → $LA/ ; plutil -lint ; launchctl enable ; launchctl bootstrap"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/19-capacity-alarm-activate.sh"
  exit 0
fi

echo "[0] selftest"
bash "$SRC" --selftest || { echo "✗ selftest RED — NOT activating" >&2; exit 1; }

echo "[1] live symlink"
mkdir -p "$(dirname "$DEST")"
if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then echo "  = $DEST (already linked)"
elif [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "  ✗ $DEST exists and is NOT a symlink — refusing to clobber a real file." >&2; exit 1
elif ln -sfn "$SRC" "$DEST"; then echo "  → $DEST"
else echo "  ✗ failed: $DEST" >&2; exit 1; fi

echo "[2] launchd"
mkdir -p "$LA"
cp "$REPO/launchd/$PLIST" "$LA/$PLIST" || { echo "  ✗ cp failed" >&2; exit 1; }
# plutil -lint ONLY (never -extract without -o: that REWRITES the plist in place and has destroyed
# 5 LaunchAgents before — memory plutil-extract-clobbers-input).
plutil -lint "$LA/$PLIST" || { echo "  ✗ plist malformed — NOT loading" >&2; exit 1; }
launchctl enable "gui/$(id -u)/com.claude.capacity-alarm" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LA/$PLIST" 2>/dev/null \
  || launchctl load -w "$LA/$PLIST" 2>/dev/null \
  || echo "  (already bootstrapped, or bootstrap declined — check the print below)"

echo
echo "verify (existence evidence from the DECLARATION, not from the subject's success —"
echo "         a 'list | grep' hides the disabled/unloaded/failed states; memory daemon-fleet-v2):"
launchctl print "gui/$(id -u)/com.claude.capacity-alarm" 2>/dev/null \
  | grep -E "state|program|last exit|run interval" | sed 's/^/    /' \
  || echo "    ✗ launchctl print found no such job — it did NOT load."

echo
echo "✓ 19-capacity-alarm ACTIVE (first tick within 600s; RunAtLoad is false by design)."
echo "  Read it now:     $DEST"
echo "  Durable record:  ~/.claude/logs/capacity-alarm.jsonl"
echo "  Page (only when WARN/ALARM, self-clears on OK):  ~/.claude/autonomy/pages/capacity-alarm.page"
echo "  Kill:            CC_CAPACITY_ALARM=off · CC_CAP_PAGE=off · launchctl bootout gui/$(id -u)/com.claude.capacity-alarm"
echo
echo "  Mark done:  touch $HOME/.claude/autonomy/pending-activation/19-capacity-alarm-activate.sh.done"
