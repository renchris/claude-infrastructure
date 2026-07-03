#!/bin/bash
# WorktreeCreate hook — provisions the worktree for `claude -w <name>` and returns it.
#
# CONTRACT (CC 2.1.183, code.claude.com/docs/en/hooks): stdout must contain ONLY the
# absolute worktree path; exit 0 = success. Any other stdout (JSON, progress text)
# makes CC abort with "WorktreeCreate hook failed: no successful output" — which is
# exactly how the previous version of this hook broke `claude -w` (it printed a
# hookSpecificOutput JSON blob). ALL diagnostics go to the log file / stderr.
#
# Behavior:
#   • reso (repo has scripts/worktree-pool.sh): CLAIM a warm pool slot — pre-built
#     node_modules + codegen + seeded DB — instead of cold-building (~30s → <3s).
#   • repo has scripts/new-worktree.sh only: cold-build via that script.
#   • older CC shape (stdin carries worktree_path = CC already created it): copy
#     .env.local and echo the path back. NEVER symlink node_modules — that breaks
#     pnpm's isolated layout + native bins (better-sqlite3/sharp); the old hook's
#     symlink step violated the repo rule and is deliberately gone.
#   • anything else: create a plain worktree under ~/Development/.worktrees.
#
# Rewritten 2026-07-02 (worktree-latency end-state). Previous version backed up at
# ~/.claude/hooks/worktree-setup.sh.bak-2026-07-02.

set -uo pipefail

LOG_FILE="$HOME/.claude/logs/worktree-lifecycle.log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [worktree-setup] $1" >> "$LOG_FILE"; }

command -v jq >/dev/null 2>&1 || { log "jq missing — cannot parse hook input"; exit 1; }

INPUT=$(cat)
NAME=$(echo "$INPUT" | jq -r '.name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path // empty')
MAIN_WORKTREE=$(echo "$INPUT" | jq -r '.main_worktree // empty')

# ── Older shape: CC created the worktree already; we just finish setup ──────
if [ -n "$WORKTREE_PATH" ]; then
  if [ -n "$MAIN_WORKTREE" ] && [ -f "$MAIN_WORKTREE/.env.local" ] && [ ! -f "$WORKTREE_PATH/.env.local" ]; then
    cp "$MAIN_WORKTREE/.env.local" "$WORKTREE_PATH/.env.local" && chmod 0600 "$WORKTREE_PATH/.env.local"
    log "copied .env.local into $WORKTREE_PATH"
  fi
  log "setup complete (pre-created): $WORKTREE_PATH"
  printf '%s\n' "$WORKTREE_PATH"
  exit 0
fi

# ── Current shape: the hook owns creation ───────────────────────────────────
[ -n "$CWD" ] || { log "no cwd in hook input"; exit 1; }
REPO="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO" ] || { log "cwd is not a git repo: $CWD"; exit 1; }

BRANCH="${NAME:-cc-$(date +%H%M%S)-$$}"
BRANCH="$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._/-' '-')"

POOL_SH="$REPO/scripts/worktree-pool.sh"
[ -f "$POOL_SH" ] || POOL_SH="$HOME/.reso/bin/worktree-pool.sh"   # installed trunk copy (local main lags)
if [ -f "$POOL_SH" ] && [ -f "$REPO/scripts/new-worktree.sh" ]; then
  WT="$(cd "$REPO" && bash "$POOL_SH" claim "$BRANCH" 2>>"$LOG_FILE")"
  [ -n "$WT" ] && [ -d "$WT" ] || { log "pool claim failed for $BRANCH"; exit 1; }
  log "claimed pool worktree: $WT (branch $BRANCH)"
  printf '%s\n' "$WT"
  exit 0
fi

if [ -f "$REPO/scripts/new-worktree.sh" ]; then
  SAFE="${BRANCH//\//-}"
  WT="$HOME/Development/.worktrees/wt-$SAFE"
  ( cd "$REPO" && bash scripts/new-worktree.sh "$BRANCH" "$WT" ) >>"$LOG_FILE" 2>&1 || { log "new-worktree.sh failed for $BRANCH"; exit 1; }
  log "cold-built worktree: $WT (branch $BRANCH)"
  printf '%s\n' "$WT"
  exit 0
fi

# Generic repo: plain worktree, .env.local copied if present.
SAFE="${BRANCH//\//-}"
WT="$HOME/Development/.worktrees/$(basename "$REPO")-$SAFE"
mkdir -p "$(dirname "$WT")"
git -C "$REPO" worktree add "$WT" -b "$BRANCH" >>"$LOG_FILE" 2>&1 || { log "git worktree add failed for $BRANCH"; exit 1; }
[ -f "$REPO/.env.local" ] && { cp "$REPO/.env.local" "$WT/.env.local"; chmod 0600 "$WT/.env.local"; }
log "generic worktree: $WT (branch $BRANCH)"
printf '%s\n' "$WT"
exit 0
