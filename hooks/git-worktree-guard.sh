#!/usr/bin/env bash
# git-worktree-guard.sh — PreToolUse(Bash): never reap a worktree/branch out from under a
# LIVE Claude session. Born from the 2026-06-12 incident: a manual `git worktree remove` +
# `git branch -D` on a "clean" tree deleted an ACTIVE session's worktree mid-work, because
# clean-tree was used as the only gate — but **clean tree != idle session** (a session that
# just committed has a clean tree). The worktree-gc janitor (scripts/worktree-gc.sh) gates on
# live-claude-cwd / lsof / idle>30m / .teammate-busy and NEVER deletes branches; raw git
# bypasses all of it. This hook reasserts the two load-bearing gates for manual git calls.
#
# Blocks (exit 2) when:
#   (1) `git branch -d|-D <b>` and <b> has a checked-out worktree — branches-with-worktrees
#       are NEVER deleted (the janitor preserves branches so a vanished worktree is recoverable).
#   (2) `git worktree remove [<flags>] <path>` and a live `claude` is cwd'd in <path>, OR any
#       process has files open under it (lsof). Idle worktrees pass → teammate lifecycle +
#       janitor are unaffected (a finished teammate's worktree is idle).
# Fail-OPEN on parse failure / non-matching command. Kill switch: WT_GUARD_DISABLED=1.
set -uo pipefail
[ "${WT_GUARD_DISABLED:-0}" = "1" ] && exit 0

input="$(cat)"
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
else
  cmd="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\(.*\)"$/\1/')"
fi
[ -n "${cmd:-}" ] || exit 0

# Fast pass-through: only inspect branch-delete / worktree-remove.
case "$cmd" in
  *"git worktree remove"*|*"git branch -d"*|*"git branch -D"*|*"git branch --delete"*) ;;
  *) exit 0 ;;
esac

# (1) branch -d/-D guard — refuse to delete a branch that has a worktree.
if printf '%s' "$cmd" | grep -qE 'git branch([[:space:]]|.)*-(d|D|-delete)'; then
  wtlist="$(git worktree list 2>/dev/null)"
  for tok in $(printf '%s' "$cmd" | sed -E 's/.*git branch//' | tr ' ' '\n' | grep -vE '^-'); do
    [ -n "$tok" ] || continue
    if printf '%s\n' "$wtlist" | grep -qF "[$tok]"; then
      echo "git-worktree-guard: BLOCKED 'git branch -D $tok' — branch '$tok' has a checked-out worktree. Branches with worktrees are NEVER force-deleted (a live Claude session may depend on it; the worktree-gc janitor preserves branches by design — a vanished worktree must stay recoverable via its branch). If the worktree is genuinely idle, reap it with 'bash scripts/worktree-gc.sh --prune' (it gates on live-claude-cwd/lsof/idle>30m and KEEPS the branch)." >&2
      exit 2
    fi
  done
fi

# (2) worktree remove guard — refuse if a live claude is cwd'd in the path (or it's open).
if printf '%s' "$cmd" | grep -qE 'git worktree remove'; then
  wt="$(printf '%s' "$cmd" | sed -E 's/.*git worktree remove//' | tr ' ' '\n' | grep -vE '^-' | tail -1)"
  [ -n "${wt:-}" ] || exit 0
  wtabs="$(cd "$wt" 2>/dev/null && pwd -P || echo "$wt")"
  live=0
  for cpid in $(pgrep -f claude 2>/dev/null | sort -u); do
    if lsof -a -p "$cpid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | grep -qxF "$wtabs"; then live=1; break; fi
  done
  if [ "$live" = "0" ] && command -v lsof >/dev/null 2>&1 && lsof -- "$wtabs" 2>/dev/null | grep -q .; then live=1; fi
  if [ "$live" = "1" ]; then
    echo "git-worktree-guard: BLOCKED 'git worktree remove $wt' — a live process (likely a Claude session) is cwd'd in / has files open under it. Removing it now yanks the worktree out from under active work (clean tree != idle session). Let 'bash scripts/worktree-gc.sh --prune' handle reaping — it KEEPS anything live and only removes clean+merged+idle>30m worktrees, preserving the branch. Or wait for that session to finish." >&2
    exit 2
  fi
fi
exit 0
