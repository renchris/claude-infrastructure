#!/usr/bin/env bash
# frontier-status.sh — SessionStart one-liner: frontier-window + holes-ledger nudge.
#
# Routing guidance for the Fable-opt-in discipline (2026-06-09): default model is
# Opus 4.8 (lead_default in model-config.yaml); the frontier tier is opt-in only.
# Prints AT MOST one line:
#   - window open  → status + open-hole count + the two skills + launcher
#   - window closed but OPEN holes exist in this project → parked-holes reminder
#   - otherwise → silent (zero context cost outside frontier-relevant sessions)
set -uo pipefail

CFG="$HOME/.claude/model-config.yaml"
LEDGER="docs/research/FRONTIER_HOLES.md" # cwd-relative: per-project ledger
[ -f "$CFG" ] || exit 0

# Cheap SSOT reads (grep/awk, no yq dependency; first match inside the block wins).
block="$(sed -n '/^frontier_access:/,/^[a-z_]/p' "$CFG" 2>/dev/null)"
active="$(printf '%s\n' "$block" | grep -m1 '  active:' | awk '{print $2}')"
end="$(printf '%s\n' "$block" | grep -m1 '  end:' | awk '{print $2}' | tr -d '"')"
fmodel="$(printf '%s\n' "$block" | grep -m1 '  model:' | awk '{print $2}')"
lead="$(grep -m1 '^  lead_default:' "$CFG" | awk '{print $2}')"

holes=0
if [ -f "$LEDGER" ]; then
  holes="$(grep -c '^### H-[0-9].*OPEN' "$LEDGER" 2>/dev/null)" || holes=0
fi

today="$(date +%F)"
window_open=0
if [ "${active:-}" = "true" ] && [ -n "${end:-}" ] && [ ! "$today" \> "$end" ]; then
  window_open=1
fi

if [ "$window_open" = 1 ]; then
  echo "Frontier: ${fmodel:-frontier} window OPEN→${end} · default=${lead:-opus} · agent auto-escalates, bounded (frontier_discovery_budget) · holes: ${holes} OPEN in ${LEDGER} · /frontier-hole=capture · /frontier-run=inline-on-blocking-wall / batch-at-wrap-up"
elif [ "${holes:-0}" -gt 0 ] 2>/dev/null; then
  echo "Frontier: window closed · ${holes} OPEN hole(s) parked in ${LEDGER} await the next frontier window (/frontier-hole still captures)"
fi
exit 0
