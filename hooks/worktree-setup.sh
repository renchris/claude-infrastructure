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

# ── EXIT-POINT OWNERSHIP ASSERTION — the CLASS, not one spelling of it ─────────────────────────
#
# Every rung below ends by printing a path that CC turns into an agent's cwd, and nothing between
# "an allocator handed us a path" and "we print it" ever asked whether that path is a worktree of
# THIS repo. Twice it was not, both recorded in worktree-lifecycle.log: 2026-08-04 01:18 an
# `Agent isolation:"worktree"` spawn from a claude-infrastructure session was handed RESO's
# `wt-pool-2` (branch agent-a9cac33d5c961c805, its .git file pointing at
# reso-management-app/.git/worktrees/…), and 2026-08-05 01:16 the same rung took `wt-pool-9`. The
# first probe happened to be read-only; a code-writing agent would have committed into the wrong
# repository, which is why this is filed as data-integrity and not as a launcher bug.
#
# efecf749 deleted the machine-global fallback that produced both, and reso now refuses a foreign
# caller at its allocator (99753cf31). Each of those removes one SPELLING of "we returned someone
# else's tree" — neither asks the question. This does, at the one point every rung must pass
# through, so a future allocator (a repo's own pool, a cold builder, a path CC pre-created) is
# checked by construction instead of trusted.
#
# THE TEST IS EXACT, NOT A PROXY: a worktree of repo X resolves to X's common git dir from any of
# its linked worktrees, so comparing common dirs cannot misjudge a legitimate path. It has THREE
# outcomes and the third is load-bearing — a path in no git repo at all (a not-yet-built target, a
# stub) is not evidence of a FOREIGN repo, and refusing there would fire on cases carrying none of
# this defect's harm. The harm requires the path to sit inside ANOTHER repo; that is exactly and
# only what is refused.
_repo_key() {  # <dir> → canonical common git dir, or empty when the dir belongs to no repo
  local d k
  d="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
  [ -n "$d" ] || return 0
  k="$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)" || return 0
  [ -n "$k" ] || return 0
  case "$k" in /*) ;; *) k="$d/$k" ;; esac
  (cd "$k" 2>/dev/null && pwd -P)
}

# rc 0 = ours, or unattributable; rc 1 = it demonstrably belongs to another repository.
_owned_by_us() {  # <candidate worktree> <any dir inside the expected repo>
  local want have
  want="$(_repo_key "$2")"
  have="$(_repo_key "$1")"
  [ -n "$want" ] && [ -n "$have" ] && [ "$want" != "$have" ] || return 0
  log "FOREIGN WORKTREE REFUSED: $1 belongs to $have, not $want — see hooks/worktree-setup.sh"
  return 1
}

INPUT=$(cat)
NAME=$(echo "$INPUT" | jq -r '.name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path // empty')
MAIN_WORKTREE=$(echo "$INPUT" | jq -r '.main_worktree // empty')

# ── Older shape: CC created the worktree already; we just finish setup ──────
if [ -n "$WORKTREE_PATH" ]; then
  # Checked BEFORE any setup runs — .env.local must never be copied into another repo's tree.
  _owned_by_us "$WORKTREE_PATH" "${MAIN_WORKTREE:-$CWD}" || exit 1
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
  # A foreign slot degrades to the cold path rather than exiting: this rung is an OPTIMISATION, and
  # the rungs below need nothing from it (same reasoning as the fall-through above).
  if [ -n "$WT" ] && [ -d "$WT" ] && ! _owned_by_us "$WT" "$REPO"; then
    log "pool claim for $BRANCH returned a FOREIGN worktree ($WT) — falling through to the cold path"
    WT=""
  fi
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
  # No rung remains below this one, so a foreign tree here fails the launch. A failed `claude -w` is
  # recoverable; an agent writing into the wrong repository is not.
  _owned_by_us "$WT" "$REPO" || exit 1
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
_owned_by_us "$WT" "$REPO" || exit 1
[ -f "$REPO/.env.local" ] && { cp "$REPO/.env.local" "$WT/.env.local"; chmod 0600 "$WT/.env.local"; }
link_memory "$WT"
log "generic worktree: $WT (branch $BRANCH)"
printf '%s\n' "$WT"
exit 0
