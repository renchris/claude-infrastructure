#!/usr/bin/env bash
# frontier-status.sh — SessionStart one-liner: frontier-window + holes-ledger nudge.
#
# Routing guidance (discipline dates from 2026-06-09): the default model is
# roles.lead_default in model-config.yaml; the frontier tier (versions.frontier_latest)
# is not opt-in — it is Follow-On Gate F2's third branch (CLAUDE.global.md § Frontier Tier Routing).
# Prints AT MOST one line:
#   - window open AND OPEN holes in this project → hole count + window status + /frontier-run
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

# SILENT UNLESS A HOLE IS OPEN (docs/research/startup-hooks-2026-10-18/README.md §2 #12, A4-R4).
# The open-window line was identical on 404 of 404 starts with 0 holes, it restated the routing rules
# CLAUDE.md already carries, and its "agent auto-escalates" contradicted them ("a session chooses the
# ladder; it is not automatic"). `end` is a sentinel while frontier_access is permanent, so the
# 14-day window-closing branch A4-R4 offered would never fire; an open hole is the only news.
case "$holes" in ''|*[!0-9]*) holes=0 ;; esac
if [ "$holes" -gt 0 ] && [ "$window_open" = 1 ]; then
  echo "Frontier: ${holes} OPEN hole(s) in ${LEDGER} · ${fmodel:-frontier} window open→${end} · default=${lead:-opus} · escalating is this session's call, not automatic, bounded by frontier_discovery_budget · /frontier-run=inline-on-blocking-wall / batch-at-wrap-up"
elif [ "$holes" -gt 0 ]; then
  echo "Frontier: window closed · ${holes} OPEN hole(s) parked in ${LEDGER} await the next frontier window (/frontier-hole still captures)"
fi
exit 0
