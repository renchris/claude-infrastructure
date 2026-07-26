#!/bin/bash
# deploy-now.sh — deploy origin/main to the live ~/.claude layer (fast-forward the shared checkout).
#
# The live layer is symlinked from ~/Development/claude-infrastructure and lags origin/main between
# syncs. This safely discards the stale-superseded live-hook edit (verified lossless), then ff-merges
# and verifies. Reusable — run it any time the live layer is behind.
#
#   Run:  bash ~/.claude/DEPLOY-NOW.sh          (the operator entrypoint — a symlink to this file)
#
# SSOT NOTE: this lived ONLY as a real file at ~/.claude/DEPLOY-NOW.sh, unversioned and
# unrecoverable. It is now a tracked script deployed like every other (install.sh symlinks
# scripts/*.sh into ~/.claude/scripts/, plus a ~/.claude/DEPLOY-NOW.sh compat link so the
# operator's existing command is unchanged).
#
# WHAT THE FF DOES NOT DO — the reason for step 5: ~/.claude/{hooks,commands,scripts,bin,skills}
# are real directories of PER-FILE symlinks. A fast-forward updates every file that already has a
# link and deploys NOTHING for a file the checkout gained, so brand-new landed code is inert with
# no signal (`git rev-list HEAD..origin/main` reads 0 — landed ≠ deployed). Step 5 REPORTS those
# files. It never creates a link: a settings-wired hook is deliberately left unlinked until its
# staged activation script runs, and auto-linking would erase that signal.
#
# Step 5 REPLACES the pre-SSOT script's verify leg, which was `grep -c 'REOPEN GUARDS'
# ~/.claude/bin/cc-backlog` — a hardcoded content probe for one file from one 2026-07-20 deploy,
# already stale for every deploy after it. Its intent ("did the live layer actually pick this up?")
# is subsumed and generalised: link parity asserts the topology of all ~212 deployed files,
# cc-backlog among them. Recorded here because that script was never tracked in git, so this
# comment is the only surviving record of what it did.
set -uo pipefail
REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"
HOOK="hooks/teammate-auto-shutdown.sh"
say(){ printf '\n\033[1m%s\033[0m\n' "$*"; }
cd "$REPO" || { echo "✗ repo not found: $REPO" >&2; exit 1; }

# Step 5 runs on EVERY path, including "already current". A sibling session's ff leaves this
# checkout current while the new file still has no live link — exiting early there is exactly how
# landed code stays inert forever.
link_parity() {
  say "5/5  link parity (checkout files with no live symlink)"
  local lp="$REPO/scripts/deploy-link-parity.sh"
  if [ ! -x "$lp" ]; then
    echo "  ⚠ $lp missing — cannot verify that new files went live" >&2
    return 0
  fi
  "$lp" || return 1
  return 0
}

say "1/5  fetch origin/main"
git fetch origin main --quiet || { echo "✗ fetch failed" >&2; exit 1; }
behind=$(git rev-list --count HEAD..origin/main)
echo "  behind origin/main by $behind commit(s)"

if [ "$behind" -eq 0 ]; then
  echo "  ✓ already current — nothing to fast-forward"
  link_parity; rc=$?
  say "✓ checkout current."
  exit "$rc"
fi

say "2/5  safety check (only the stale hook is dirty, and discarding it is lossless)"
dirty=$(git status --porcelain --untracked-files=no | awk '{print $2}')
if [ -n "$dirty" ] && [ "$dirty" != "$HOOK" ]; then
  echo "✗ ABORT — unexpected dirty tracked file(s):" >&2; printf '%s\n' "$dirty" | sed 's/^/    /' >&2
  echo "  Only the stale $HOOK is known-safe to discard. Resolve the others, then re-run." >&2
  exit 1
fi
if [ -n "$dirty" ]; then
  git show origin/main:"$HOOK" | grep -q 'reap-safety birth-grace' \
    || { echo "✗ ABORT — origin/main's hook lacks the reap-guard wiring; discard would NOT be lossless" >&2; exit 1; }
  git checkout -- "$HOOK" && echo "  ✓ trunk supersedes the local edit — discarded the stale copy"
else
  echo "  (working tree clean)"
fi

say "3/5  fast-forward to origin/main"
prev=$(git rev-parse --short HEAD)
git merge --ff-only origin/main || { echo "✗ ABORT — not a clean fast-forward" >&2; exit 1; }
echo "  ✓ $prev → $(git rev-parse --short HEAD)"

say "4/5  fast-forwarded"
git log --oneline "$prev"..HEAD 2>/dev/null | head -12 | sed 's/^/  /'

link_parity; rc=$?

if [ "$rc" -eq 0 ]; then
  say "✓✓ DEPLOYED — every landed file is live."
else
  say "⚠ FF DONE, DEPLOY INCOMPLETE — files above landed but are NOT live. Link them, then re-run."
fi
exit "$rc"
