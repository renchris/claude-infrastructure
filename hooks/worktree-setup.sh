#!/bin/bash
# WorktreeCreate hook — automates pre-flight setup for new worktrees.
# Copies .env.local, symlinks node_modules, and ensures the worktree is ready.
# Eliminates the manual "Pre-Flight Checklist" friction.
#
# The hook receives JSON on stdin with worktree details.
# Must print the worktree path to stdout on success.

set -uo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path // empty')
MAIN_WORKTREE=$(echo "$INPUT" | jq -r '.main_worktree // empty')

[ -z "$WORKTREE_PATH" ] && exit 0
[ -z "$MAIN_WORKTREE" ] && exit 0

LOG_FILE="$HOME/.claude/logs/worktree-lifecycle.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [worktree-setup] $1" >> "$LOG_FILE"
}

log "Setting up worktree: $WORKTREE_PATH (main: $MAIN_WORKTREE)"

# 1. Copy .env.local from main worktree if it exists and doesn't exist in new worktree
if [ -f "$MAIN_WORKTREE/.env.local" ] && [ ! -f "$WORKTREE_PATH/.env.local" ]; then
  cp "$MAIN_WORKTREE/.env.local" "$WORKTREE_PATH/.env.local"
  log "Copied .env.local from main worktree"
fi

# 2. Symlink node_modules if not already present (worktree.symlinkDirectories handles
#    this in settings.json, but belt-and-suspenders for manual worktrees)
if [ -d "$MAIN_WORKTREE/node_modules" ] && [ ! -d "$WORKTREE_PATH/node_modules" ] && [ ! -L "$WORKTREE_PATH/node_modules" ]; then
  ln -s "$MAIN_WORKTREE/node_modules" "$WORKTREE_PATH/node_modules"
  log "Symlinked node_modules from main worktree"
fi

# 3. Symlink .cache if not already present
if [ -d "$MAIN_WORKTREE/.cache" ] && [ ! -d "$WORKTREE_PATH/.cache" ] && [ ! -L "$WORKTREE_PATH/.cache" ]; then
  ln -s "$MAIN_WORKTREE/.cache" "$WORKTREE_PATH/.cache"
  log "Symlinked .cache from main worktree"
fi

# 4. Copy .claude directory contents if needed (skills, rules, agents)
if [ -d "$MAIN_WORKTREE/.claude" ] && [ ! -d "$WORKTREE_PATH/.claude" ]; then
  # .claude is typically tracked by git, but symlink settings that may differ
  :
fi

log "Worktree setup complete: $WORKTREE_PATH"

# Output success context for Claude
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "WorktreeCreate",
    "additionalContext": "Worktree setup complete at $WORKTREE_PATH. .env.local copied, node_modules symlinked. Ready for teammate."
  }
}
EOF
