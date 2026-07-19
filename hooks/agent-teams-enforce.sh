#!/bin/bash
# PreToolUse hook on Agent tool — enforces Agent Teams for implementation tasks.
#
# DENY: Background subagents with implementation keywords (code-writing) are blocked.
#       Model receives clear instructions to retry with team_name set.
# ALLOW+NUDGE: Foreground agents without team_name get a reminder.
# ALLOW SILENT: Agents with team_name, known read-only types, research prompts.

set -uo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)

# Extract Agent tool parameters
TEAM_NAME=$(echo "$INPUT" | jq -r '.tool_input.team_name // empty')
RUN_BG=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')
MODEL=$(echo "$INPUT" | jq -r '.tool_input.model // empty')

# Teammate spawns (team_name set) MUST use a Max-plan auto-mode-allowlisted model.
# Allowlist is read from the SSOT (~/.claude/model-config.yaml
# .auto_mode_allowlist.non_firstParty_max — claude-opus-4-8 as of 2026-06-09) so
# this hook can never drift from a model bump again (pre-2026-06-09 it hardcoded
# opus-4-7 and would have rejected the swept 4-8 manifests). Off-allowlist models
# silent-demote to acceptEdits and break team parallelism. Teams run BOTH launcher
# tracks (stable 2.1.114 + claude-next eval); frontier models (claude-fable-5)
# become teammate-eligible the moment they're verified into the SSOT allowlist —
# until then they risk silent auto-mode demotion, so they're denied here. Blocks
# the 2026-04-17 failure mode (stale plan hardcoding Sonnet for "mechanical"
# teammates).
# Rule: memory/feedback-agent-team-models.md + model-upgrade skill.
if [ -n "$TEAM_NAME" ] && [ -n "$MODEL" ]; then
  ALLOWED=$(yq -r '.auto_mode_allowlist.non_firstParty_max[]' "$HOME/.claude/model-config.yaml" 2>/dev/null)
  [ -n "$ALLOWED" ] || ALLOWED="claude-opus-4-8"   # fallback if yq/config unavailable
  ALLOWED_FLAT=$(echo "$ALLOWED" | tr '\n' ' ')
  MODEL_BASE="${MODEL%%\[*}"                        # strip [1m]-style suffixes
  ALLOW_OK=0
  case "$MODEL_BASE" in
    *-*)  # full model ID — must match an allowlisted ID exactly
      for m in $ALLOWED; do
        [ "$MODEL_BASE" = "$m" ] && ALLOW_OK=1
      done
      ;;
    *)    # bare family alias (opus, fable, …) — allowed iff the allowlist
          # contains a model of that family (alias resolves to it)
      for m in $ALLOWED; do
        case "$m" in claude-"$MODEL_BASE"-*) ALLOW_OK=1 ;; esac
      done
      ;;
  esac
  if [ "$ALLOW_OK" -ne 1 ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Teammate spawn rejected: model='$MODEL' is not on the Max-plan auto-mode allowlist (${ALLOWED_FLAT}). Use model='opus' (alias) or an allowlisted ID for all teammates. Off-allowlist models silent-demote to acceptEdits and break team parallelism. Frontier models (claude-fable-5) become teammate-eligible only after verification into the SSOT allowlist (~/.claude/model-config.yaml auto_mode_allowlist.non_firstParty_max) — verify with one test spawn on the eval track, then append it there; this hook follows the SSOT automatically. Rule: memory/feedback-agent-team-models.md."
  }
}
EOF
    exit 0
  fi
fi

# Emit an allow + advisory skill-pointer (same pattern as the impl-nudge below). The resident
# CLAUDE.md invariants carry the CORE discipline; these pointers ensure the full-detail skill
# loads at the actual spawn point. Additive/advisory only — never denies.
emit_allow_ctx() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$1"
}

# If team_name is set (with valid or absent model), this is an Agent Team — allow + point to skill.
#
# G-P13-4 — brief-count guard. The teammate brief IS the `prompt`. An oversized brief burns the
# teammate's context before any work and drives the GH #49593 /compact crash → wave stall (FM2).
# The Agent-Teams discipline caps a brief at 150 lines (tightened from 200 after the tp-assignee
# crash 2026-05-03); ~250 lines is the empirically-observed crash size (a 21-agent synthesis dumped
# inline). Graduated response, both thresholds env-overridable:
#   >  WARN (150) → allow, but INJECT a hard warning naming the split rule. Near-misses over 150 are
#                   common and can be legitimate, so warn — don't block.
#   >= DENY (250) → deny. No legitimate brief is this large; blocking forces the split and prevents a
#                   near-certain crash (the exact FM2 wave-stall the guard exists to stop).
# Line count via `grep -c ''` — exact even when the prompt has no trailing newline (wc -l undercounts
# that case by one). Dynamic reasons are jq-built, never raw %s-interpolated (malformed-JSON class).
if [ -n "$TEAM_NAME" ]; then
  BRIEF_WARN="${AGENT_TEAMS_BRIEF_WARN_LINES:-150}"
  BRIEF_DENY="${AGENT_TEAMS_BRIEF_DENY_LINES:-250}"
  BRIEF_LINES=$(printf '%s' "$PROMPT" | grep -c '' || true)
  SKILL_PTR="AGENT-TEAMS SKILL: spawning a teammate. If not already loaded, invoke the agent-teams skill for the full brief discipline (150-line brief cap, pre-grep line ranges, verbatim stop-on-issue clause, phase checkpoints), runtime detection, per-teammate effort + model-pinning, lifecycle + graceful-shutdown, and crash recovery. The resident CLAUDE.md invariant carries the core; the skill carries the detail."

  if [ "$BRIEF_LINES" -ge "$BRIEF_DENY" ]; then
    jq -n --arg n "$BRIEF_LINES" --arg warn "$BRIEF_WARN" --arg deny "$BRIEF_DENY" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Teammate brief is \($n) lines — at/over the \($deny)-line hard cap. An oversized brief burns the teammate context before any work and drives the GH #49593 /compact crash → wave stall (the tp-assignee 2026-05-03 failure mode). SPLIT into 2-3 teammates along domain boundaries (target ≤\($warn) lines each; pre-grep line ranges instead of pasting file bodies; defer visual verification to a separate Explore subagent), then re-spawn. Env override: AGENT_TEAMS_BRIEF_DENY_LINES. Rule: agent-teams skill § Brief Discipline.")
      }
    }'
    exit 0
  fi

  if [ "$BRIEF_LINES" -gt "$BRIEF_WARN" ]; then
    jq -n --arg n "$BRIEF_LINES" --arg warn "$BRIEF_WARN" --arg ptr "$SKILL_PTR" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: ("BRIEF OVER CAP: this teammate brief is \($n) lines, over the \($warn)-line Agent-Teams cap. Oversized briefs risk the GH #49593 /compact crash → wave stall. Prefer splitting into 2-3 teammates by domain (≤\($warn) lines each), pre-greping line ranges instead of pasting file bodies, and deferring visual verification to a separate Explore subagent. " + $ptr)
      }
    }'
    exit 0
  fi

  emit_allow_ctx "$SKILL_PTR"
  exit 0
fi

# If this is a known read-only subagent type, allow silently
case "$SUBAGENT_TYPE" in
  Explore|Plan|claude-code-guide|fresh-eyes-evaluator|north-star-design-agent|visual-design-iterator) exit 0 ;;
esac

# === RESEARCH ESCAPE HATCH ===
# Strong research-only markers override the keyword heuristic. Lead prepends
# any of these phrases to a research-only prompt to bypass false-positives
# (e.g. research about "schema", "migration mechanics", "Phase 0 patterns"
# was previously blocked because those words triggered the impl regex).
# Discriminator is the EXPLICIT marker, not the topic.
RESEARCH_MARKERS='READ[- ]ONLY RESEARCH|RESEARCH[- ]ONLY|NO (FILES|CODE)( WILL BE)? (WRITTEN|MODIFIED|CREATED)|WRITES? NOTHING (TO|ON) DISK|Tool budget:[[:space:]]*(Read|Glob|Grep|WebFetch|WebSearch|,|[[:space:]])+|Tool use limited to:[[:space:]]*(Read|Glob|Grep|WebFetch|WebSearch|,|[[:space:]])'
if echo "$PROMPT" | grep -qEi "$RESEARCH_MARKERS"; then
  emit_allow_ctx "RESEARCH-SUBAGENTS SKILL: fanning out research subagents. If composing a WAVE, invoke the research-subagents skill for the decomposition discipline (decompose before counting, default N=10, question-type + named-entity gates, 6-field briefs, adversarial-sampling floor, OASIS stop). The resident CLAUDE.md invariant carries the core."
  exit 0
fi

# Check if the prompt contains implementation keywords (case-insensitive)
IMPL_KEYWORDS="implement|create.*file|write.*code|modify|refactor|add.*column|schema|migration|build.*component|fix.*bug|update.*file|delete.*file|edit.*file|new.*route|new.*component|add.*feature|deploy|seed|generate|write.*test|create.*component|add.*hook"
RESEARCH_KEYWORDS="research|explore|investigate|find|search|analyze|audit|verify|check|review|read|look|scan|inspect|evaluate|fetch|report|list|summarize|compare"

# Count implementation vs research keyword matches
IMPL_COUNT=$(echo "$PROMPT" | grep -oEi "$IMPL_KEYWORDS" 2>/dev/null | wc -l | tr -d ' ')
RESEARCH_COUNT=$(echo "$PROMPT" | grep -oEi "$RESEARCH_KEYWORDS" 2>/dev/null | wc -l | tr -d ' ')

# If clearly research-oriented (more research keywords than implementation), allow silently
if [ "$RESEARCH_COUNT" -gt "$IMPL_COUNT" ] && [ "$IMPL_COUNT" -le 1 ]; then
  emit_allow_ctx "RESEARCH-SUBAGENTS SKILL: research-oriented subagent spawn. If composing a research WAVE, invoke the research-subagents skill for the decomposition discipline (decompose before counting, default N=10, adversarial-sampling floor, OASIS stop, synthesis-bottleneck rules). The resident CLAUDE.md invariant carries the core."
  exit 0
fi

# DENY: Background subagent with implementation keywords — block and redirect to Agent Teams
if [ "$RUN_BG" = "true" ] && [ "$IMPL_COUNT" -ge 2 ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Background subagents cannot write code. Implementation tasks require Agent Teams for visibility and coordination. To proceed: use TeamCreate first, then spawn agents with team_name parameter set (e.g., team_name='implementation-wave-1'). You ARE authorized to use Agent Teams — this constraint exists to ensure parallel work is coordinated safely. If this task is purely research/exploration with no code changes, rephrase the prompt to clarify."
  }
}
EOF
  exit 0
fi

# ALLOW+NUDGE: Foreground agent without team_name that looks like implementation
if [ "$IMPL_COUNT" -ge 2 ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "AGENT TEAMS DEFAULT: This agent spawn involves code changes but has no team_name. Per global rules, ALL implementation tasks with 2+ code-writing tasks MUST use Agent Teams (TeamCreate + team_name + worktree isolation). Only research/exploration subagents should run without team_name. You ARE authorized to use Agent Teams."
  }
}
EOF
  exit 0
fi

# Default: allow silently (ambiguous or single-keyword cases)
exit 0
