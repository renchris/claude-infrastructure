#!/usr/bin/env bash
# frontier-spawn-gate.sh — PreToolUse (Agent + Bash matchers): deterministic backstop for
# frontier-model routing. Knowledge layers (CLAUDE.md § Frontier Tier Routing,
# rules, skill descriptions) steer the agent; this gate catches the one failure
# knowledge can't: stale routing after the frontier_access window closes.
#
# Behavior: inspects tool calls that request the frontier tier (model "fable" / the SSOT
# frontier model id) on EITHER of the two paths that can spend the frontier meter:
#   AGENT path   — an Agent spawn carrying `tool_input.model`.
#   SESSION path — a Bash call that FIRES A SESSION on the frontier tier, i.e.
#                  `handoff-fire.sh … --model <frontier>` or a `claude*` launcher with the same.
# Window open → count against the per-session cap, then allow. Window closed/inactive → exit 2
# with a reason the agent reads and adapts to (re-spawn on the fallback). Everything else →
# untouched.
#
# WHY THE SESSION PATH IS HERE (R2 of docs/plans/NONLIMIT_RESUME_LADDER.md § W3, conviction 93%).
# Until this arm existed the gate counted Agent spawns only, while the fleet's actual frontier
# spend was overwhelmingly SESSIONS: measured 2026-09-09 over 4,117 transcripts, Fable ran **52
# lead sessions** against 140 subagent runs, and the three frontier COMMANDS had been invoked once
# between them. So `frontier_discovery_budget.max_fable_spawns_per_session` was a bound on the
# minority path and no bound at all on the majority one — and CLAUDE.md § Frontier Tier Routing
# described the agent as "bounded" on the strength of it. A cap that cannot see the dominant
# carrier is the "gate's surface is not its traffic" failure, stated in this repo's own rules.
#
# ONE PREDICATE, SHARED WITH THE THING IT GATES. The session arm keys on `--model` and on NOTHING
# ELSE — deliberately the same sole-source-of-truth handoff-fire.sh itself uses
# (scripts/handoff-fire.sh:9303-9311). That file used to ALSO sniff the launcher NAME
# (`claude-fable*`) and deleted the arm on 2026-08-01 because it was a SECOND, DISAGREEING oracle:
# `--launcher claude-fable3` with no `--model` set FABLE_EFFECTIVE=1 while the probe still ran
# haiku. Re-introducing a name arm here would re-create exactly that disagreement one layer up, so
# a launcher name is NOT a frontier signal in this gate either. If that ever changes, it changes in
# both files in one diff (model-config.yaml § 3b already lists the keying census).
set -uo pipefail

input="$(cat)"
CFG="${FRONTIER_GATE_CFG:-$HOME/.claude/model-config.yaml}"
[ -f "$CFG" ] || exit 0

block="$(sed -n '/^frontier_access:/,/^[a-z_]/p' "$CFG" 2>/dev/null)"
fmodel="$(printf '%s\n' "$block" | grep -m1 '  model:' | awk '{print $2}')"

is_frontier_model() { # <model> → 0 when it is the frontier tier
  # PREFIX on the family, not just equality against the SSOT's current id. `$fmodel` is whatever
  # frontier_access.model says TODAY (claude-fable-5-1); a spawn pinned to the still-Active PRIOR
  # id (claude-fable-5 — deliberately kept in auto_mode_allowlist so pinned sessions survive the
  # bump) matched neither arm and fell through `*) exit 0`, i.e. spent the frontier tier with NO
  # per-session spawn cap. This is the gate's whole job, so an unmatched frontier id is not a
  # no-op, it is a silent disarm. Same prefix shape as handoff-fire.sh's four detectors and
  # ~/.zshrc's cost warning; see the ⚠️ bump-models note there before adding hooks/ to
  # model-classification.json's `update` list.
  case "${1:-}" in
    fable|claude-fable-5*) return 0 ;;
    "$fmodel") [ -n "${fmodel:-}" ] && return 0 ;;
  esac
  return 1
}

frontier_fire_model() { # <bash command> → the frontier model this command FIRES A SESSION on, else rc 1
  local c="${1:-}" m
  # A command that spawns nothing spends nothing. `--dry-run` is handoff-fire's own probe mode and
  # must not consume a slot, or the cheapest way to CHECK the gate is to trip it.
  case "$c" in *--dry-run*) return 1 ;; esac
  # Entry point must be a session launcher. Requiring it is what keeps this from becoming a
  # substring gate: `grep claude-fable-5-1 model-config.yaml` and `cc-backlog add "… fable …"`
  # name the tier without spending it, and a hook that exit-2'd on those would refuse ordinary
  # reads. Word-anchored so `my-handoff-fire.sh.bak` and `unclaude` do not match.
  printf '%s' "$c" | grep -qE '(^|[[:space:]]|[;&|(])([A-Za-z0-9_./~$"{}-]*/)?(handoff-fire\.sh|claude|claude-latest|claude-next[0-9]*|claude[0-9]+)([[:space:]]|$)' || return 1
  # `--model X` / `--model=X`, every occurrence: last-wins is handoff-fire's own semantics, but a
  # frontier id ANYWHERE in the flag list is what would reach the meter if the last-wins order
  # differs from ours, so the safe reading counts it.
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    if is_frontier_model "$m"; then printf '%s\n' "$m"; return 0; fi
  done <<EOF
$(printf '%s' "$c" | grep -oE -- '--model[= ]+[A-Za-z0-9._-]+' | sed -E 's/^--model[= ]+//')
EOF
  return 1
}

# ---- which path is this, and what model does it ask for? -------------------------------------
# `path` is carried into the refusal texts so a blocked SESSION fire is never told to "re-spawn
# this agent", which names a tool the operator did not use and reads as a different defect.
tool_name=""
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
fi

path=agent
req_model=""
if [ "${tool_name:-}" = "Bash" ]; then
  path=session
  cmd=""
  if command -v jq >/dev/null 2>&1; then
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  fi
  [ -n "$cmd" ] || exit 0
  req_model="$(frontier_fire_model "$cmd")" || exit 0
  [ -n "${req_model:-}" ] || exit 0
else
  # Extract the requested model (jq if available; conservative grep fallback).
  if command -v jq >/dev/null 2>&1; then
    req_model="$(printf '%s' "$input" | jq -r '.tool_input.model // empty' 2>/dev/null)"
  else
    req_model="$(printf '%s' "$input" | grep -oE '"model"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  fi
  [ -n "${req_model:-}" ] || exit 0
fi

# Only gate frontier-tier requests (family alias or full id) — see is_frontier_model above.
is_frontier_model "$req_model" || exit 0

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
    if [ "$path" = session ]; then
      echo "frontier-spawn-gate: per-session frontier cap reached ($cnt/$cap — SSOT frontier_discovery_budget.max_fable_spawns_per_session; Agent spawns and frontier session FIRES share one budget). Do NOT retry: fire this session on the default tier instead (--model claude-opus-5), or park the remaining hole(s) in docs/research/FRONTIER_HOLES.md for a later session's wrap-up batch." >&2
    else
      echo "frontier-spawn-gate: per-session frontier-spawn cap reached ($cnt/$cap — SSOT frontier_discovery_budget.max_fable_spawns_per_session). Do NOT retry: park the remaining hole(s) in docs/research/FRONTIER_HOLES.md; a later session's wrap-up batch runs them." >&2
    fi
    exit 2
  fi
  echo $((cnt + 1)) > "$cnt_file"
  exit 0 # window open, under cap — allow
fi

if [ "$path" = session ]; then
  echo "frontier-spawn-gate: frontier window is CLOSED (frontier_access active=${active:-unset}, end=${end:-unset}) — '$req_model' is not routable, so this fire would launch a session that cannot answer. Re-fire on the fallback tier (--model ${fallback:-claude-opus-5}) and note the degradation in your close. SSOT: ~/.claude/model-config.yaml." >&2
else
  echo "frontier-spawn-gate: frontier window is CLOSED (frontier_access active=${active:-unset}, end=${end:-unset}) — '$req_model' is not routable. Re-spawn this agent on the fallback tier (omit model, or model: \"opus\" → ${fallback:-claude-opus-4-8}) and note the degradation in your report. SSOT: ~/.claude/model-config.yaml." >&2
fi
exit 2
