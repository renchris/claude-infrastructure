#!/bin/bash
# migration-class: c10
# migration-step: convert ~/Development/reso-management-app into a detached browse mirror (its files were 1,948 commits stale) and load com.claude.browse-mirror so it stays current — it installs a launchd plist, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0032-browse-mirror.sh
# migration-subject: ~/.claude/scripts/browse-mirror-sync.sh
# migration-verify: launchctl print "gui/$(id -u)/com.claude.browse-mirror" >/dev/null 2>&1 && [ "$(git -C "$HOME/Development/reso-management-app" rev-parse HEAD 2>/dev/null)" = "$(git -C "$HOME/Development/reso-management-app" rev-parse origin/main 2>/dev/null)" ]
# migration-conflict: [ -f "$HOME/Library/LaunchAgents/com.claude.browse-mirror.plist" ] && ! cmp -s "$HOME/Library/LaunchAgents/com.claude.browse-mirror.plist" "$HOME/Development/claude-infrastructure/launchd/com.claude.browse-mirror.plist"
#
# 0032 — the browse mirror.
# Subject: scripts/browse-mirror-sync.sh · launchd/com.claude.browse-mirror.plist
#          tests/browse-mirror-sync.bats
#
# WHAT IT FIXES. Every session in a high-volume repo runs in a worktree, so the ORIGINAL checkout is
# never worked in — and so nothing ever advanced it. Measured 2026-09-19,
# ~/Development/reso-management-app was showing files 1,948 commits old to anyone who opened it in
# Cursor or Finder. The repository itself was never stale: refs/remotes lives in the git COMMON dir,
# so every fetch by any of that repo's 35 worktrees had been updating the root's own origin/main all
# along (root and wt-pool-1 both read 06ce6fee5 at the moment of measurement). Only HEAD — and
# therefore the FILES — had never moved.
#
# WHY A ONE-TIME FIX WOULD NOT HOLD, which is the whole reason this is a cadence and not a command.
# The folder had already rotted and been hand-reconciled once: tag archive/local-main-20260702
# records "169 ahead / 702 behind origin/main at retirement", 32 patch-unique commits triaged. Ten
# weeks later it was 10 ahead / 1,948 behind again. Two wedges do it, both silent and both permanent
# once entered: ONE accidental commit in the root diverges its local main and `pull --ff-only`
# refuses forever, and `next dev` REGENERATES a block in AGENTS.md so a dirty tree is not something
# discipline can prevent. scripts/browse-mirror-sync.sh removes both by holding the checkout at a
# DETACHED HEAD — no local branch to diverge, and tracked modifications archived to a ref rather
# than blocking.
#
# WHY c10. It installs a launchd plist. migrations/README.md: "A migration that touches
# settings.json, a launchd plist, or credentials declares c10 and waits for a human." So this
# STAGES and never self-runs.
#
# WHY THE VERIFIER ASSERTS BOTH LOADED *AND* AT-TARGET. README.md § "Verify the EFFECT, not the
# paperwork": a loaded job is not the effect. This exact job loaded over a mirror that is blocked on
# an untracked collision heartbeats healthily forever while the folder shows stale files — the
# failure it exists to prevent, wearing a pass. The oracle therefore requires the checkout to
# actually equal origin/main.
#
# WHAT THE OPERATOR SEES. The conversion runs in the FOREGROUND first, before the cadence is
# installed, because it is the one interesting run: it advances the folder ~1,948 commits, which
# takes a moment on a 24 GB working tree, and it is the run most likely to report `blocked` (an
# untracked file sitting where the target ref wants to write one). Better to see that on the
# terminal than to discover it later in a log. Then the plist goes in and the cadence takes over.
#
# NOTHING HERE IS DESTRUCTIVE. Tracked modifications are archived to refs/mirror-rescue/<ts> (a real
# commit object, recoverable with `git stash apply` years later) before they are cleared, untracked
# files are never touched and never forced over, and the pre-existing divergent history is preserved
# at tag archive/root-main-2026-09-19. The only irreversible thing in this file is nothing.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.claude.browse-mirror"
PLIST_SRC="$REPO/launchd/$LABEL.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
SYNC_SRC="$REPO/scripts/browse-mirror-sync.sh"
SYNC_LIVE="$HOME/.claude/scripts/browse-mirror-sync.sh"

say() { printf '0032: %s\n' "$*"; }

[ -r "$PLIST_SRC" ] || { say "FATAL: missing $PLIST_SRC"; exit 1; }
[ -r "$SYNC_SRC" ]  || { say "FATAL: missing $SYNC_SRC"; exit 1; }

# 1. The conversion, in the foreground, from whichever copy is live (falling back to the checkout
#    when install.sh has not yet created the symlink — a converge that has not run must not make
#    this step unreachable).
RUNNER="$SYNC_LIVE"
[ -x "$RUNNER" ] || RUNNER="$SYNC_SRC"
say "running the mirror sync in the foreground from $RUNNER"
say "the first run advances ~1,948 commits over a 24 GB tree — give it a minute"
bash "$RUNNER"
sync_rc=$?
if [ "$sync_rc" -ne 0 ]; then
  say "the sync reported a problem (rc=$sync_rc). Read the verdict above before continuing."
  say "a 'blocked' verdict means an untracked file sits where the target ref wants to write one;"
  say "move or delete that file and re-run. Installing the cadence anyway is safe — it retries."
fi

# 2. The cadence.
say "installing $PLIST_DST"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude/logs" || exit 1
cp "$PLIST_SRC" "$PLIST_DST" || { say "FATAL: could not install the plist"; exit 1; }

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  say "already loaded — replacing it so the new plist takes effect"
  launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
fi
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" || { say "FATAL: bootstrap failed"; exit 1; }

# 3. Report the effect, not the paperwork.
say "loaded. current state:"
bash "$RUNNER" --status | sed 's/^/     /'
say "kill switch: touch ~/.claude/autonomy/browse-mirror.disabled"
exit 0
