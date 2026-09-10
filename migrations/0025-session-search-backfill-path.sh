#!/bin/bash
# migration-class: c10
# migration-step: reinstall + reload com.claude.session-search-backfill — the weekly backfill has never once run, and the loaded job is a COPY of the plist, so landing the fix alone changes nothing
# migration-run: bash ~/Development/claude-infrastructure/migrations/0025-session-search-backfill-path.sh
# migration-subject: ~/Library/LaunchAgents/com.claude.session-search-backfill.plist
# migration-verify: bash ~/Development/claude-infrastructure/migrations/0025-session-search-backfill-path.sh --verify
#
# 0025 — THE WEEKLY SESSION-SEARCH BACKFILL HAS NEVER SUCCEEDED, AND REPORTED OK EVERY TIME.
#
# Measured 2026-09-09 (docs/plans/ACCOUNT_AGNOSTIC_AGENT_STATE.md § W4 found it; this migration is
# the converge path for the fix):
#
#   1. `~/.claude/bin/session-index-backfill.sh` is a SYMLINK into the claude-session-search
#      checkout. That script's line 10 is `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`, which does
#      not resolve a symlink — so invoked by its link name SCRIPT_DIR became `~/.claude/bin`, and
#      line 13's `source "$SCRIPT_DIR/lib/progress-ui.sh"` pointed at a file that does not exist.
#      `~/.claude/logs/backfill-scheduled.log` holds that one error repeated and nothing else.
#   2. It survived because the plist's command ended `... 2>&1 | head -50 >> log`, so the exit
#      status launchd saw was head's. A job that had NEVER run reported exit 0 forever — a dead rung
#      reporting OK, which is worse than no rung (MEMORY.md alarm-polarity-and-attention-budget).
#
# A/B, one variable, on the live box: invoked by the link name it dies at line 13 in under a second;
# invoked through `readlink -f` it ran to `✓ Phase 1: Session index scan  154 indexed  54.2s`.
#
# WHAT THIS DOES. The repo plist now resolves the symlink before invoking, and captures the real
# rc into a parseable `verdict=` line instead of discarding it. But the LOADED job is a plain COPY
# at ~/Library/LaunchAgents — not a symlink into the repo — so the landed fix is inert until the
# copy is refreshed and the job reloaded. That copy+reload is the C10 step this migration owns.
#
# SAFE TO RE-RUN: the copy is content-checked and the job is reloaded only when it changed.

set -uo pipefail

LABEL="com.claude.session-search-backfill"
REPO_PLIST="$(cd "$(dirname "$0")/.." && pwd)/launchd/$LABEL.plist"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

verify_one() {
  local rc=0
  if [ ! -f "$DEST" ]; then
    printf '0025 --verify: %s absent\n' "$DEST" >&2; return 1
  fi
  if ! cmp -s "$REPO_PLIST" "$DEST"; then
    printf '0025 --verify: installed plist DIFFERS from the repo copy (fix not live)\n' >&2; rc=1
  fi
  # The two properties the fix exists for, asserted on the INSTALLED file, not the repo one.
  if ! grep -q 'readlink -f' "$DEST"; then
    printf '0025 --verify: installed plist does not resolve the symlink\n' >&2; rc=1
  fi
  # shellcheck disable=SC2016  # a literal search string, not an expansion: the plist contains
  # the four characters $rc and must keep containing them.
  if ! grep -q 'exit "$rc"' "$DEST"; then
    printf '0025 --verify: installed plist does not propagate the job exit code\n' >&2; rc=1
  fi
  if ! launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    printf '0025 --verify: %s is not loaded in %s\n' "$LABEL" "$DOMAIN" >&2; rc=1
  fi
  [ "$rc" -eq 0 ] && printf '0025 --verify: live\n'
  return "$rc"
}

if [ "${1:-}" = "--verify" ]; then verify_one; exit $?; fi

[ -f "$REPO_PLIST" ] || { printf '0025: repo plist missing: %s\n' "$REPO_PLIST" >&2; exit 1; }
plutil -lint "$REPO_PLIST" >/dev/null || { printf '0025: repo plist is not valid\n' >&2; exit 1; }

if [ -f "$DEST" ] && cmp -s "$REPO_PLIST" "$DEST"; then
  printf '0025: %s already current\n' "$DEST"
else
  if [ -f "$DEST" ]; then
    bak="$DEST.bak-0025-$(date -u +%Y%m%dT%H%M%SZ)"
    cp -p "$DEST" "$bak" || { printf '0025: backup FAILED; nothing changed\n' >&2; exit 1; }
    printf '0025: backup: %s\n' "$bak"
  fi
  mkdir -p "$(dirname "$DEST")"
  cp "$REPO_PLIST" "$DEST" || { printf '0025: copy FAILED\n' >&2; exit 1; }
  cmp -s "$REPO_PLIST" "$DEST" || { printf '0025: copy did not verify\n' >&2; exit 1; }
  printf '0025: installed %s\n' "$DEST"
fi

# Reload so the running job picks up the new command. bootout may legitimately report "not loaded".
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if launchctl bootstrap "$DOMAIN" "$DEST" 2>/dev/null; then
  printf '0025: %s reloaded\n' "$LABEL"
else
  printf '0025: bootstrap reported an error; checking whether it is loaded anyway\n' >&2
fi

verify_one
