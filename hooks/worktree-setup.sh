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

# Point the new worktree's PROJECT MEMORY at the primary repo's. Claude Code keys project state on
# cwd, so a worktree otherwise starts memory-blind — measured 2026-07-31: 164 worktree-keyed project
# dirs on this box, 0 with a memory/ dir, against 213 topic files in the primary's. Full rationale
# (and why it is a symlink, not a copy) in scripts/worktree-memory-link.sh.
#
# STDOUT DISCIPLINE IS LOAD-BEARING: this hook's contract is that stdout carries ONLY the worktree
# path — anything else makes CC abort with "WorktreeCreate hook failed: no successful output", which
# is exactly how a previous version of this hook broke `claude -w`. So the call is fully redirected
# into the log and can never fail the hook.
#
# $0 MUST BE RESOLVED THROUGH ITS SYMLINKS BEFORE DERIVING '..'. Live, this file is
# ~/.claude/hooks/worktree-setup.sh — a per-file symlink into the checkout. An unresolved
# `dirname "$0"/../scripts/…` therefore points at ~/.claude/scripts/…, and a BRAND-NEW tracked file
# lands there UNLINKED until install.sh runs, so the hook would silently no-op on the live path
# while looking correct from a worktree. self-path-lint caught exactly this. No `readlink -f` —
# that is GNU-only and this box is BSD.
_resolve_self() {  # <path> → absolute path, every symlink hop resolved (bash 3.2 / POSIX-safe)
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}

link_memory() {
  local wt="$1" wml self
  self="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
  wml="$(cd "$(dirname "$self")/.." && pwd)/scripts/worktree-memory-link.sh"
  [ -f "$wml" ] || { log "worktree-memory-link.sh not found at $wml"; return 0; }
  CC_WML_QUIET=1 bash "$wml" "$wt" >>"$LOG_FILE" 2>&1 || log "memory-link failed (non-fatal): $wt"
  return 0
}

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
  link_memory "$WORKTREE_PATH"
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

# WARM-POOL FAST PATH — the repo's OWN allocator only, and never load-bearing.
#
# NO CROSS-REPO FALLBACK. This used to fall back to $HOME/.reso/bin/worktree-pool.sh whenever
# $REPO shipped no allocator of its own ("installed trunk copy, local main lags"). That path is a
# machine-GLOBAL one with no repo test in it, so for any repo but reso it claimed a slot out of
# RESO's pool: the slots live at a shared $WTROOT under generic wt-pool-N names, and `claim` ran
# `git switch -C <our-branch>` inside one of them and printed it back as though it were ours. The
# caller then worked in the wrong repo entirely — observed 2026-08-05, this hook took wt-pool-9.
# reso closed it at the allocator chokepoint (99753cf31: a foreign caller is refused, exit 3), so
# the claim now fails loudly instead of silently succeeding — but a refusal we treat as fatal is
# still a broken `claude -w`. Both halves are fixed here: the fallback is gone (nothing foreign is
# ever asked), and a failed claim FALLS THROUGH rather than exiting.
#
# FALL THROUGH, NEVER exit 1. A pool is an OPTIMISATION — a warm slot instead of a ~30s cold
# build. The cold rungs below need nothing from it, so any claim failure (refusal, empty pool,
# allocator bug) must degrade to them; exiting turned a slow launch into no launch at all. This
# mirrors scripts/handoff-fire.sh's pool gate, which already refuses a foreign slot and cold-builds.
POOL_SH="$REPO/scripts/worktree-pool.sh"
if [ -f "$POOL_SH" ] && [ -f "$REPO/scripts/new-worktree.sh" ]; then
  WT="$(cd "$REPO" && bash "$POOL_SH" claim "$BRANCH" 2>>"$LOG_FILE")"
  if [ -n "$WT" ] && [ -d "$WT" ]; then
    link_memory "$WT"
    log "claimed pool worktree: $WT (branch $BRANCH)"
    printf '%s\n' "$WT"
    exit 0
  fi
  log "pool claim failed for $BRANCH — falling through to the cold path"
fi

if [ -f "$REPO/scripts/new-worktree.sh" ]; then
  SAFE="${BRANCH//\//-}"
  WT="$HOME/Development/.worktrees/wt-$SAFE"
  ( cd "$REPO" && bash scripts/new-worktree.sh "$BRANCH" "$WT" ) >>"$LOG_FILE" 2>&1 || { log "new-worktree.sh failed for $BRANCH"; exit 1; }
  link_memory "$WT"
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
link_memory "$WT"
log "generic worktree: $WT (branch $BRANCH)"
printf '%s\n' "$WT"
exit 0
