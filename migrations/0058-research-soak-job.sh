#!/bin/bash
# migration-class: c10
# migration-step: the research program's Stage 9 soak job (com.claude.research-soak, hourly at :17) is built and staged but not loaded; installing and loading it is yours
# migration-run: bash ~/Development/claude-infrastructure/migrations/0058-research-soak-job.sh
# migration-subject: ~/Library/LaunchAgents/com.claude.research-soak.plist
# migration-verify: launchctl print gui/$(id -u)/com.claude.research-soak >/dev/null 2>&1
#
# WHAT THIS LOADS (method v1.2, REPORT.md §11 instrument 4, built gate row 24 —
# docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md)
# ───────────────────────────────────────────────────────────────
# One launchd job, `/bin/bash ~/.claude/scripts/research-kit/jobs/research-job.sh soak`: the same
# runner as 0051's five jobs, which execs `cc-research job soak`. Each run takes one soak sample
# (every acceptance check, from an empty HOME with PATH=/usr/bin:/bin under /bin/bash) for every
# research program in build-certifying; nothing else is visited. Hourly, so a 24-hour soak crosses
# the hour, UTC midnight and local midnight that row 24 requires.
#
# Why its own migration and not a sixth job in 0051: 0051 has already been run and ledgered, and the
# converger files a c10 step once, so a job added to 0051's list would never reach the operator.
# The SSOT plist lives in launchd/staged/, outside install.sh's launchd/*.plist glob
# (tests/install-staged-plist.bats). c10 because loading a plist is an operator step.
#
#   0058-research-soak-job.sh [--dry-run]
#
# --dry-run prints what a real run would do and touches nothing. A real run refuses until the live
# layer carries the runner and cc-research, then copies the plist into ~/Library/LaunchAgents and
# bootstraps it; a label already loaded from identical bytes is left alone, so a re-run is a no-op.
# The load is read back with `launchctl print`; exit 1 if the label is not loaded at the end.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
RUNNER="$HOME/.claude/scripts/research-kit/jobs/research-job.sh"
CLI="$HOME/.claude/bin/cc-research"
LABEL="com.claude.research-soak"

dry=0
case "${1:-}" in
  --dry-run) dry=1 ;;
  '') ;;
  *) echo "usage: 0058-research-soak-job.sh [--dry-run]" >&2; exit 2 ;;
esac

uid="$(id -u)"
src="$REPO/launchd/staged/$LABEL.plist"
dst="$LA/$LABEL.plist"
if [ ! -f "$src" ]; then
  echo "0058: MISSING $src — the wiring commit did not land intact; refusing" >&2
  exit 1
fi

if [ "$dry" -eq 1 ]; then
  for f in "$RUNNER" "$CLI"; do
    if [ -f "$f" ]; then echo "0058: live layer has $f"; else echo "0058: live layer LACKS $f — a real run would refuse"; fi
  done
  echo "0058: would install $src -> $dst and bootstrap gui/$uid/$LABEL"
  exit 0
fi

for f in "$RUNNER" "$CLI"; do
  if [ ! -f "$f" ]; then
    echo "0058: $f is not in the live layer yet — converge first (bash $REPO/scripts/deploy-live.sh), then re-run" >&2
    exit 1
  fi
done

mkdir -p "$LA" "$HOME/.claude/logs"
if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1 && cmp -s "$src" "$dst"; then
  echo "0058: $LABEL already loaded from the repo plist"
  exit 0
fi
launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1 || true   # a stale copy is replaced, not doubled
cp "$src" "$dst"
if ! launchctl bootstrap "gui/$uid" "$dst"; then
  echo "0058: bootstrap of $LABEL FAILED" >&2
  exit 1
fi
if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
  echo "0058: $LABEL loaded"
else
  echo "0058: $LABEL bootstrapped but launchctl print cannot see it" >&2
  exit 1
fi
