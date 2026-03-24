#!/bin/bash
# PreToolUse hook for Write|Edit|MultiEdit — auto-backup, overwrite guard, plan conventions
# Matches: Write/MultiEdit (backup + warn) and Edit on plan files (inject plan conventions)
# Creates timestamped backups in ~/.claude/backups/ with sidecar path files
#
# Hardened Mar 19 2026 — fixes from 15-agent deep research:
#   - Nanosecond timestamps (prevent agent team race conditions)
#   - Explicit symlink following (-L flag)
#   - Relative path detection for docs/plans/
#   - Graceful backup failure (warn, don't block Write)
#   - jq dependency check

# Don't use set -e — backup failures must not block tool execution
set -uo pipefail

# === JQ CHECK ===
if ! command -v jq &>/dev/null; then
  exit 0  # Silent pass-through if jq unavailable — never block writes
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Fast exit: no file path or file doesn't exist
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

BASENAME=$(basename "$FILE")
LINES=$(wc -l < "$FILE" | tr -d ' ')

# === PLAN FILE DETECTION ===
# 5-pattern hybrid: personal plans, project symlinks, project docs (absolute + relative), master plan
IS_PLAN=false
case "$FILE" in
  "$HOME/.claude/plans/"*.md)                    IS_PLAN=true ;;  # Personal plans (absolute)
  *"/.claude-plans/"*.md)                        IS_PLAN=true ;;  # Project symlinks (absolute)
  *"/docs/plans/"*.md)                           IS_PLAN=true ;;  # Project plan docs (absolute)
  docs/plans/*.md)                               IS_PLAN=true ;;  # Project plan docs (relative)
  *"/AGENT_TEAM_IMPLEMENTATION_PLAN"*.md)        IS_PLAN=true ;;  # Master plan (any location)
esac

# === PLAN CONVENTIONS (injected for both Write AND Edit on plan files) ===
PLAN_RULES=""
if [ "$IS_PLAN" = true ]; then
  PLAN_RULES=" PLAN UPDATE RULES: (1) COMPLETED sections: mark DONE, compact to key learnings + commit hashes only — remove step-by-step details. (2) UPCOMING sections: keep comprehensive and expansive — file paths, line ranges, decision context, trade-offs. (3) Phase 0 MANDATORY: first upcoming section must be Agent Team Orchestration (team size, roles, task dependencies, worktree assignments, spawn wave order). (4) NEVER delete: historical decisions, 'Why:' explanations, learnings, or known issues — these compound across sessions."
fi

# === EDIT TOOL: plan context only, no backup needed ===
if [ "$TOOL" = "Edit" ]; then
  if [ "$IS_PLAN" = true ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "PLAN GUARD: Editing plan file '${BASENAME}' (${LINES} lines).${PLAN_RULES}"
  }
}
EOF
  fi
  # Non-plan Edit: silent pass-through (no output = no context injection)
  exit 0
fi

# === WRITE / MULTIEDIT TOOL: backup + warn ===

BACKUP_DIR="$HOME/.claude/backups"
mkdir -p "$BACKUP_DIR" 2>/dev/null || true

# Nanosecond timestamp prevents race conditions with parallel agent teams
TIMESTAMP=$(date +%Y%m%d-%H%M%S)-$$
# macOS date doesn't support %N — use PID as unique suffix (guaranteed unique per process)
BACKUP_FILE="${BACKUP_DIR}/${BASENAME}__${TIMESTAMP}.bak"
PATH_FILE="${BACKUP_DIR}/${BASENAME}__${TIMESTAMP}.path"

# Copy existing file before Write overwrites it
# -L: explicitly follow symlinks (back up real content, not symlink)
# Graceful failure: warn but don't block the Write
if cp -L "$FILE" "$BACKUP_FILE" 2>/dev/null; then
  echo "$FILE" > "$PATH_FILE" 2>/dev/null || true

  # === AUTO-PRUNE: keep only last 10 backups per basename ===
  BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "${BASENAME}__*.bak" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$BACKUP_COUNT" -gt 10 ]; then
    find "$BACKUP_DIR" -maxdepth 1 -name "${BASENAME}__*.bak" -print0 2>/dev/null \
      | xargs -0 ls -t 2>/dev/null \
      | tail -n +11 \
      | while IFS= read -r old_bak; do
          old_path="${old_bak%.bak}.path"
          rm -f "$old_bak" "$old_path"
        done
  fi

  # === WARN AI ===
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "OVERWRITE GUARD: You are about to OVERWRITE '${BASENAME}' (${LINES} lines). Backup saved to ${BACKUP_FILE}. CRITICAL RULE: INTEGRATE new content — do NOT delete or restructure existing sections. Use Edit for targeted changes instead of Write.${PLAN_RULES} Restore if overwritten: ~/.claude/scripts/restore-file.sh ${FILE}"
  }
}
EOF
else
  # Backup failed (disk full, permissions) — warn but allow Write to proceed
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WARNING: Backup of '${BASENAME}' FAILED (disk/permissions). Write will proceed WITHOUT backup. CRITICAL: Use Edit instead of Write to avoid losing existing content.${PLAN_RULES}"
  }
}
EOF
fi

exit 0
