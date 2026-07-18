#!/bin/bash
# PostToolUse hook — plan-structure lint for plan files. Two concerns:
#
#   1. STATUS SCHEMA (blocking, G-P14-6). Every hand-authored plan MUST carry a
#      YAML frontmatter `status:` key, one of:
#         status: open | in-progress | complete | superseded
#      A NEW authored plan (untracked in git, else mtime-fresh) LACKING a valid
#      status FAILS the hook (exit 2). Pre-existing plans only WARN (never
#      retro-break the corpus). The ExitPlanMode global sink (~/.claude/plans) is
#      machine-authored and never gated. A truthful status is what lets
#      find-plan.sh --list-open classify open vs. done work.
#
#   2. PHASE 0 / AGENT TEAMS (non-blocking warn). Agent Teams are the DEFAULT for
#      implementation work; warn if an impl plan omits Phase 0 orchestration.
#
# Env overrides (tests): CC_PLANS_DIR, CC_PLAN_NEW_AGE_S.

set -uo pipefail

command -v jq &>/dev/null || exit 0

PLANS_DIR="${CC_PLANS_DIR:-$HOME/.claude/plans}"

# has_valid_status <file> → 0 if frontmatter carries status: <one of the 4 values>.
has_valid_status() {
  local f="$1"
  head -1 "$f" 2>/dev/null | grep -qx -- '---' || return 1
  sed -n '2,/^---$/p' "$f" 2>/dev/null \
    | grep -qiE '^status:[[:space:]]*(open|in-progress|in_progress|complete|completed|superseded)([[:space:]]|$)'
}

# is_new_plan <file> → 0 if the file is NEW (git-untracked, else mtime-fresh).
# Pre-existing (git-tracked, or old on disk) ⇒ returns 1 (warn-only, never block).
is_new_plan() {
  local f="$1" dir; dir=$(dirname "$f")
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$dir" ls-files --error-unmatch "$f" >/dev/null 2>&1 && return 1  # tracked
    return 0                                                                  # untracked
  fi
  local now mt age
  now=$(date +%s); mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
  age=$(( now - mt ))
  [ "$age" -lt "${CC_PLAN_NEW_AGE_S:-300}" ]
}

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_result.filePath // empty')

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# === PLAN FILE DETECTION (must match backup-before-write.sh exactly) ===
# IS_AUTHORED = hand-authored namespace (status-gated). The global sink is a plan
# but machine-authored (ExitPlanMode) → IS_PLAN only, never status-gated.
IS_PLAN=false; IS_AUTHORED=false
case "$FILE" in
  "$PLANS_DIR"/*.md)                             IS_PLAN=true ;;
  *"/.claude-plans/"*.md)                        IS_PLAN=true; IS_AUTHORED=true ;;
  *"/docs/plans/"*.md)                           IS_PLAN=true; IS_AUTHORED=true ;;
  docs/plans/*.md)                               IS_PLAN=true; IS_AUTHORED=true ;;
  *"/AGENT_TEAM_IMPLEMENTATION_PLAN"*.md)        IS_PLAN=true; IS_AUTHORED=true ;;
esac

[ "$IS_PLAN" = false ] && exit 0

# === STATUS SCHEMA GATE (blocking for NEW authored plans; else warn) ===
if [ "$IS_AUTHORED" = true ] && ! has_valid_status "$FILE"; then
  BN=$(basename "$FILE")
  if is_new_plan "$FILE"; then
    echo "❌ PLAN STATUS REQUIRED [${BN}]: new plan is missing a valid 'status:' frontmatter key. Add YAML frontmatter at the top: status: open|in-progress|complete|superseded (use 'open' for active work). This keeps the mission-ledger enumerator (find-plan.sh --list-open) truthful — G-P14-6." >&2
    exit 2
  fi
  # Pre-existing plan: warn only (never retro-break the corpus).
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "⚠️ PLAN STATUS [${BN}]: no valid 'status:' frontmatter (open|in-progress|complete|superseded). Pre-existing plan — not blocked; add a status: line so find-plan.sh --list-open can classify it (open vs. done)."
  }
}
EOF
  exit 0
fi

# === PHASE 0 CHECK ===
# Warn if file has 2+ sections (any structured plan with multiple tasks)
SECTION_COUNT=$(grep -c "^## \|^### " "$FILE" 2>/dev/null || echo "0")
[ "$SECTION_COUNT" -lt 2 ] && exit 0

# Check if this looks like an implementation plan (has phases, tasks, or implementation keywords)
IS_IMPL=false
if grep -qEi "Phase [1-9]|Implementation|Wave [1-9]|Task [1-9]|Sprint|Milestone" "$FILE" 2>/dev/null; then
  IS_IMPL=true
fi

if [ "$IS_IMPL" = true ] && ! grep -qEi "Phase 0|Agent Team Orchestration|Team Orchestration|Pre-Flight Checklist|Team Roster" "$FILE" 2>/dev/null; then
  BASENAME=$(basename "$FILE")
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "⚠️ AGENT TEAMS REQUIRED [${BASENAME}]: This implementation plan has NO Phase 0 / Agent Team Orchestration. Per CLAUDE.md: Agent Teams are the DEFAULT for all implementation work (9/10 sessions). Add Phase 0 as the FIRST section with: team roster, task dependency graph, worktree assignments, spawn wave order. Only omit for purely research/exploration plans with no code changes. Use the plan-update skill 'Phase 0' template."
  }
}
EOF
fi

exit 0
