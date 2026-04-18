#!/bin/bash
# TaskCompleted hook — quality gate that runs typecheck in the teammate's worktree.
# Exit code 2 rejects the task and sends build errors back to the teammate.
# Exit code 0 allows the task to complete normally.
#
# Receives JSON on stdin with task details (task_id, task_subject, teammate_name, team_name).

set -uo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty')
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // empty')
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // empty')

LOG_FILE="$HOME/.claude/logs/task-quality-gate.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [quality-gate] $1" >> "$LOG_FILE"
}

# Only run quality gate for team tasks (not standalone tasks)
[ -z "$TEAM_NAME" ] && exit 0

log "Quality gate for task: $TASK_SUBJECT (teammate: $TEAMMATE_NAME, team: $TEAM_NAME)"

# Phase 0 verification gate — forcing function for the 2026-04-17 routines-v1
# incident where Phase 0 was marked complete with zero worktrees. If the
# task subject contains "Phase 0", run verify-team.sh against the team and
# block completion if it fails.
if [[ "$TASK_SUBJECT" == *"Phase 0"* ]]; then
  PROJECT_DIR="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "")"
  VERIFY_SCRIPT="$PROJECT_DIR/scripts/team/verify-team.sh"
  # Fallback to canonical location if we're not in the project root
  [[ -x "$VERIFY_SCRIPT" ]] || VERIFY_SCRIPT="$HOME/Development/reso-management-app/scripts/team/verify-team.sh"
  if [[ -x "$VERIFY_SCRIPT" ]]; then
    log "Phase 0 task detected — running verify-team.sh for $TEAM_NAME"
    VERIFY_OUTPUT=$("$VERIFY_SCRIPT" "$TEAM_NAME" 2>&1 || true)
    VERIFY_EXIT=$?
    if [ "$VERIFY_EXIT" -ne 0 ]; then
      log "PHASE 0 VERIFY FAILED for $TEAM_NAME (exit $VERIFY_EXIT) — blocking task"
      echo "QUALITY GATE FAILED: Phase 0 verification failed for team $TEAM_NAME. Fix worktrees / settings / branches before marking Phase 0 task complete:" >&2
      echo "" >&2
      echo "$VERIFY_OUTPUT" | tail -40 >&2
      exit 2
    fi
    log "Phase 0 verify passed for $TEAM_NAME"
  else
    log "verify-team.sh not found — skipping Phase 0 gate for $TEAM_NAME"
  fi
fi

# Find the teammate's working directory by checking recent worktrees
# Look for worktrees that match the teammate name
WORKTREE_PATH=""
while IFS= read -r line; do
  WT_PATH=$(echo "$line" | awk '{print $1}')
  if echo "$WT_PATH" | grep -qi "$TEAMMATE_NAME" 2>/dev/null; then
    WORKTREE_PATH="$WT_PATH"
    break
  fi
done < <(git worktree list 2>/dev/null)

# Also check /tmp/worktree-* paths
if [ -z "$WORKTREE_PATH" ]; then
  for wt in /tmp/worktree-*; do
    if [ -d "$wt" ] && echo "$wt" | grep -qi "$TEAMMATE_NAME" 2>/dev/null; then
      WORKTREE_PATH="$wt"
      break
    fi
  done
fi

# If we can't find the worktree, allow task completion (don't block on lookup failure)
if [ -z "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
  log "Could not find worktree for teammate $TEAMMATE_NAME — allowing task completion"
  exit 0
fi

log "Found worktree: $WORKTREE_PATH"

# Run typecheck in the worktree
TYPECHECK_OUTPUT=""
TYPECHECK_EXIT=0
cd "$WORKTREE_PATH" || exit 0

# Check if pnpm/node_modules exist (worktree may not have dependencies)
if [ ! -d "node_modules" ] && [ ! -L "node_modules" ]; then
  log "No node_modules in worktree — skipping typecheck"
  exit 0
fi

# Run typecheck with a timeout (60 seconds)
TYPECHECK_OUTPUT=$(timeout 60 npx tsc --noEmit 2>&1) || TYPECHECK_EXIT=$?

if [ "$TYPECHECK_EXIT" -ne 0 ] && [ "$TYPECHECK_EXIT" -ne 124 ]; then
  # Typecheck failed — extract first 20 error lines
  ERROR_SUMMARY=$(echo "$TYPECHECK_OUTPUT" | grep "error TS" | head -20)
  ERROR_COUNT=$(echo "$TYPECHECK_OUTPUT" | grep -c "error TS" || echo "0")

  log "TYPECHECK FAILED ($ERROR_COUNT errors) in $WORKTREE_PATH"

  # Exit code 2 rejects the task completion
  echo "QUALITY GATE FAILED: TypeScript typecheck found $ERROR_COUNT error(s) in $WORKTREE_PATH. Fix these before marking the task complete:" >&2
  echo "" >&2
  echo "$ERROR_SUMMARY" >&2
  exit 2
fi

if [ "$TYPECHECK_EXIT" -eq 124 ]; then
  log "Typecheck timed out (60s) — allowing task completion"
  exit 0
fi

log "TYPECHECK PASSED in $WORKTREE_PATH"
exit 0
