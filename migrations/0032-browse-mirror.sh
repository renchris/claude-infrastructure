#!/bin/bash
# migration-class: c10
# migration-step: convert ~/Development/reso-management-app into a detached browse mirror (its files were 1,948 commits stale) and load com.claude.browse-mirror so it stays current — it installs a launchd plist, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0032-browse-mirror.sh
# migration-subject: ~/.claude/scripts/browse-mirror-sync.sh
# migration-verify: launchctl print "gui/$(id -u)/com.claude.browse-mirror" 2>/dev/null | awk '/last exit code/{c=$NF} END{exit (c=="0")?0:1}' && git -C "$HOME/Development/reso-management-app" merge-base --is-ancestor HEAD origin/main 2>/dev/null
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
# WHY THE VERIFIER DOES NOT CHECK THAT THE JOB IS MERELY LOADED. README.md § "Verify the EFFECT, not
# the paperwork": a loaded job is not the effect, and this one proved it the hard way. On the day it
# shipped, the job was loaded and heartbeating while CRASHING on every trigger — /bin/bash is 3.2 and
# the script had a construct only bash 5 parses, so `runs = 5, last exit code = 2` and the mirror
# never advanced. A loaded-only oracle answers YES to that, forever. So the first arm reads the
# job's own LAST EXIT CODE: it is the one field that distinguishes "runs" from "runs successfully",
# and it is exactly the field that was non-zero.
#
# AND WHY IT NO LONGER ASSERTS HEAD == origin/main, which was the first thing it did. That oracle is
# RACY on this repo and would have reported FAIL on a perfectly healthy system: origin/main moves
# every 2-15 minutes (measured: six advances in sixteen minutes), while a full advance across reso's
# 24 GB working tree takes ~3 minutes — so trunk routinely moves DURING a run and the mirror is a
# commit behind the instant it finishes. A verifier that fails on a healthy system is the same
# defect as one that passes on a broken one; it just fails in the direction that gets ignored.
# `merge-base --is-ancestor HEAD origin/main` is the non-racy half of the same question: it proves
# the mirror is TRACKING trunk rather than diverged or wedged, and stays true through a landing.
# The lag bound itself is the cadence's guarantee, not something a point-in-time check can assert.
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
