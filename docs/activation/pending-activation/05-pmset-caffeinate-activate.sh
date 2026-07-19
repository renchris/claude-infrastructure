#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 05-pmset-caffeinate  —  T-P16-3 (AC-policy verifier) + T-P16-4 (caffeinate idle-sleep floor)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: (2) one-time `sudo pmset -c …` AC-awake apply, then (3) load two LaunchAgents — the
#   caffeinate FLOOR (RunAtLoad+KeepAlive, holds an idle-sleep assertion forever) FIRST, then the
#   power-policy VERIFIER (RunAtLoad+hourly, pages on AC-policy drift). Loading them makes "stay awake
#   24/7" durable + battery-safe and re-asserted-on-reboot instead of a manual out-of-band pmset.
# PRECONDITION: feat/desk-pmset-caffeinate landed (the plists reference the main-checkout script path).
# BATTERY POLICY: the floor default `-i -s` keeps the machine awake on battery too (docked & away).
#   To let it sleep on battery (preserve UPS runtime through an outage), set CC_CAFFEINATE_FLAGS=-s in
#   the floor plist env BEFORE loading. Loading ratifies the default (operator decision G-P16-2).
# C10: agent staged; operator runs. Dry by default — re-run with CONFIRM=1 to apply+load.
# Authoritative: docs/activation/pmset-caffeinate-activate-snippet.md
# Mark done: touch ~/.claude/autonomy/pending-activation/05-pmset-caffeinate-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
UID_N="$(id -u)"
PMSET_APPLY=(sudo pmset -c sleep 0 displaysleep 0 disablesleep 0)
FLOOR="com.claude.caffeinate-floor.plist"           # load FIRST (assertion up before the verifier reads)
VERIFY="com.claude.power-policy-verify.plist"

echo "== 05-pmset-caffeinate (T-P16-3 + T-P16-4) =="
echo "Step 2 — one-time AC power policy (interactive root):"
echo "    ${PMSET_APPLY[*]}"
echo "Step 3 — load the two LaunchAgents (floor first, then the verifier):"
for L in "$FLOOR" "$VERIFY"; do
  echo "    cp $REPO/launchd/$L ~/Library/LaunchAgents/$L"
  echo "    plutil -lint ~/Library/LaunchAgents/$L && launchctl bootstrap gui/$UID_N ~/Library/LaunchAgents/$L"
done
echo

if [ "${CONFIRM:-0}" = 1 ]; then
  echo "-- applying AC pmset policy (sudo will prompt) --"
  if ! "${PMSET_APPLY[@]}"; then
    echo "✗ pmset apply failed (if it rejected 'disablesleep', drop it and re-run; see the snippet)" >&2; exit 1
  fi
  for L in "$FLOOR" "$VERIFY"; do
    label="${L%.plist}"
    if cp "$REPO/launchd/$L" "$HOME/Library/LaunchAgents/$L" \
         && plutil -lint "$HOME/Library/LaunchAgents/$L" \
         && { launchctl bootout "gui/$UID_N/$label" 2>/dev/null || true; \
              launchctl bootstrap "gui/$UID_N" "$HOME/Library/LaunchAgents/$L"; }; then
      echo "✓ loaded $label"
    else
      echo "✗ load failed for $label — inspect above" >&2; exit 1
    fi
  done
  echo "-- verify --"
  "$REPO/scripts/caffeinate-floor.sh" --verify        || echo "  (floor not yet asserting — KeepAlive relaunches within ~10s; re-check)"
  "$REPO/scripts/power-policy-verify.sh" --verify      || true
  echo "  pmset assertions (floor = a caffeinate WITHOUT -t):"
  pmset -g assertions | grep -E 'caffeinate' | grep -v -- '-t' || echo "    (none yet — re-check in a few seconds)"
  touch "$HOME/.claude/autonomy/pending-activation/05-pmset-caffeinate-activate.sh.done" 2>/dev/null || true
else
  echo "(dry: re-run with CONFIRM=1 to apply the pmset policy + load both plists.)"
fi

echo
echo "ROLLBACK:"
echo "    for L in $FLOOR $VERIFY; do launchctl bootout gui/$UID_N/\${L%.plist} 2>/dev/null; rm -f ~/Library/LaunchAgents/\$L; done"
echo "    # pmset AC policy is durable; to revert: sudo pmset -c sleep 1"
