#!/usr/bin/env bash
# frontier-spawn-gate.sh — PreToolUse (Agent matcher): deterministic backstop for
# frontier-model routing. Knowledge layers (CLAUDE.md § Frontier Tier Routing,
# rules, skill descriptions) steer the agent; this gate catches the one failure
# knowledge can't: stale routing after the frontier_access window closes.
#
# Behavior: inspects Agent tool calls that request the frontier tier
# (model "fable" / the SSOT frontier model id). Window open → silent allow.
# Window closed/inactive → exit 2 with a reason the agent reads and adapts to
# (re-spawn on the fallback). Non-frontier spawns → untouched.
set -uo pipefail

input="$(cat)"
CFG="${FRONTIER_GATE_CFG:-$HOME/.claude/model-config.yaml}"
[ -f "$CFG" ] || exit 0

# Extract the requested model (jq if available; conservative grep fallback).
if command -v jq >/dev/null 2>&1; then
  req_model="$(printf '%s' "$input" | jq -r '.tool_input.model // empty' 2>/dev/null)"
else
  req_model="$(printf '%s' "$input" | grep -oE '"model"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
[ -n "${req_model:-}" ] || exit 0

block="$(sed -n '/^frontier_access:/,/^[a-z_]/p' "$CFG" 2>/dev/null)"
fmodel="$(printf '%s\n' "$block" | grep -m1 '  model:' | awk '{print $2}')"

# Only gate frontier-tier requests (family alias or full id).
case "$req_model" in
  fable|"$fmodel") ;;
  *) exit 0 ;;
esac

active="$(printf '%s\n' "$block" | grep -m1 '  active:' | awk '{print $2}')"
end="$(printf '%s\n' "$block" | grep -m1 '  end:' | awk '{print $2}' | tr -d '"')"
fallback="$(printf '%s\n' "$block" | grep -m1 '  fallback:' | awk '{print $2}')"
today="$(date +%F)"

if [ "${active:-}" = "true" ] && [ -n "${end:-}" ] && [ ! "$today" \> "$end" ]; then
  # Window open — enforce the per-session spawn cap (bounded autonomy: the agent
  # escalates to the frontier tier WITHOUT a human, but never unboundedly).
  cap="$(grep -m1 'max_fable_spawns_per_session:' "$CFG" | awk '{print $2}')"
  case "${cap:-}" in ''|*[!0-9]*) cap=6 ;; esac
  # Production-support reserve (SSOT frontier_discovery_budget.reserve_dates):
  # on a reserve date the cap is HALVED — a mid-incident plan-window exhaustion
  # during live-ops outweighs any per-task economics (2026-06-11 routing verdict).
  reserve="$(grep -m1 'reserve_dates:' "$CFG" | sed 's/.*reserve_dates:[[:space:]]*"\{0,1\}//; s/".*//')"
  case " ${reserve:-} " in
    *" $today "*) cap=$(( cap / 2 )); [ "$cap" -lt 1 ] && cap=1 ;;
  esac
  if command -v jq >/dev/null 2>&1; then
    sid="$(printf '%s' "$input" | jq -r '.session_id // "nosid"' 2>/dev/null)"
  fi
  sid="${sid:-nosid}"
  cnt_file="${TMPDIR:-/tmp}/frontier-gate-${sid}.count"
  cnt=0; [ -f "$cnt_file" ] && cnt="$(cat "$cnt_file" 2>/dev/null)"
  case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
  if [ "$cnt" -ge "$cap" ]; then
    echo "frontier-spawn-gate: per-session frontier-spawn cap reached ($cnt/$cap — SSOT frontier_discovery_budget.max_fable_spawns_per_session). Do NOT retry: park the remaining hole(s) in docs/research/FRONTIER_HOLES.md; a later session's wrap-up batch runs them." >&2
    exit 2
  fi
  echo $((cnt + 1)) > "$cnt_file"
  exit 0 # window open, under cap — allow
fi

echo "frontier-spawn-gate: frontier window is CLOSED (frontier_access active=${active:-unset}, end=${end:-unset}) — '$req_model' is not routable. Re-spawn this agent on the fallback tier (omit model, or model: \"opus\" → ${fallback:-claude-opus-4-8}) and note the degradation in your report. SSOT: ~/.claude/model-config.yaml." >&2
exit 2
