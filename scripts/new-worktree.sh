#!/usr/bin/env bash
# new-worktree.sh — create a runnable claude-infrastructure worktree for ONE session.
#
# WHY THIS FILE EXISTS: `~/.zshrc:_cc_route_check()` is the always-isolate gate shared by every
# launcher (`claude`, `claude-default`, `claude-previous`). Its creation ladder already has a
# branch for `$_top/scripts/new-worktree.sh` with a FIXED contract (below) — reso ships one, this
# repo did not, so claude-infrastructure fell through to `return 0` and every session launched in
# the SHARED checkout root. That is the condition `.claude/CLAUDE.md` forbids writing from, and
# the one that structurally blocks the deploy lane: `deploy-live.sh`'s `git merge --ff-only`
# refuses whenever a sibling session has left root dirty (observed 2026-07-31, root 16 commits
# behind, `com.claude.deploy-live` at exit 1 for hours, live `~/.claude` stale fleet-wide).
#
# THE CONTRACT the gate depends on — do not change these three without changing ~/.zshrc:
#   1. argv[1] is a NAME (not a path); the worktree MUST land at
#      $HOME/Development/.worktrees/wt-<name>, because the gate DERIVES that path rather than
#      reading our stdout.
#   2. Every human-facing byte goes to STDERR. The gate runs us as `( … ) >&2` and a stray stdout
#      write would be harmless there but breaks any caller that captures the path — keep the
#      stream discipline so both shapes stay safe.
#   3. Exit non-zero on ANY failure. The launcher treats non-zero as "isolation failed" and
#      REFUSES to launch un-isolated (that refusal is the whole safety property — a silent
#      fallback to root would reintroduce exactly the bug this closes).
#
# WHY NOT `worktree-harness new`: the installed harness is generic and good, but its defaults are
# wrong for this repo in two ways that are silent, not loud — it puts worktrees in `~/.worktrees`
# (this repo's whole convention, its gc exclude lists and every operator habit say
# `~/Development/.worktrees`), and it detects `npm ci` from a package.json that exists ONLY to
# render diagrams (`beautiful-mermaid`; `node_modules` is absent even in root). That would run a
# pointless install per session. A `.harnessrc` could correct both, but then the harness is
# configured to do exactly what these 40 lines do, with a version-skew surface we do not need.
#
# BASE FRESHNESS (backlog #68): we branch off `origin/main` after an explicit fetch, NEVER the
# local `main` ref. The shared checkout frequently sits behind — cutting from it silently starts
# every new session on a stale base, and the divergence only surfaces at land time as a conflict.
set -euo pipefail

name="${1:-}"
[ -n "$name" ] || { echo "usage: new-worktree.sh <name>" >&2; exit 2; }
case "$name" in
  */*|.|..) echo "new-worktree.sh: <name> must be a bare name, not a path: '$name'" >&2; exit 2 ;;
esac

repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || { echo "new-worktree.sh: not inside a git repo" >&2; exit 2; }

home="$HOME/Development/.worktrees"
dest="$home/wt-$name"
branch="$name"

[ -e "$dest" ] && { echo "new-worktree.sh: $dest already exists" >&2; exit 3; }
mkdir -p "$home"

# Freshest trunk. A fetch failure is NOT fatal — offline still deserves a worktree — but it is
# announced, because a silently stale base is the failure mode this comment block exists for.
if ! git -C "$repo" fetch --quiet origin main 2>/dev/null; then
  echo "new-worktree.sh: ⚠ fetch origin main failed — branching off the LOCAL main (possibly stale)" >&2
fi
base="origin/main"
git -C "$repo" rev-parse --verify --quiet "$base" >/dev/null || base="main"

echo "new-worktree.sh: creating $dest off $base" >&2
git -C "$repo" worktree add -b "$branch" "$dest" "$base" >&2

# Gitignored runtime files a fresh worktree lacks. Copy, NEVER symlink: a symlinked
# settings.local.json would make every worktree mutate the shared file, which is the same
# shared-state defect one level down. Absent sources are skipped silently — they are optional.
for rel in .claude/settings.local.json .env .env.local; do
  if [ -f "$repo/$rel" ]; then
    mkdir -p "$dest/$(dirname "$rel")"
    cp "$repo/$rel" "$dest/$rel" && echo "new-worktree.sh: copied $rel" >&2
  fi
done

# No dependency install: this repo's package.json exists only for `npm run diagrams`
# (beautiful-mermaid) and node_modules is absent even in the primary checkout. Adding an install
# here would tax every session launch to build something no session uses.

echo "new-worktree.sh: ready → $dest (branch $branch, base $base)" >&2
