#!/bin/bash
# migration-class: c10
# migration-step: the research program's five scheduled jobs (com.claude.research-sweep hourly; freshness, triage and drift daily; market weekly) are built and staged but not loaded; installing and loading them is yours
# migration-run: bash ~/Development/claude-infrastructure/migrations/0051-research-jobs.sh
# migration-subject: ~/Library/LaunchAgents/com.claude.research-sweep.plist
# migration-verify: launchctl print gui/$(id -u)/com.claude.research-sweep >/dev/null 2>&1 && launchctl print gui/$(id -u)/com.claude.research-freshness >/dev/null 2>&1 && launchctl print gui/$(id -u)/com.claude.research-triage >/dev/null 2>&1 && launchctl print gui/$(id -u)/com.claude.research-drift >/dev/null 2>&1 && launchctl print gui/$(id -u)/com.claude.research-market >/dev/null 2>&1
#
# WHAT THIS LOADS (REPORT.md §5.5, §8 item 12, §10 item 4 —
# docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md)
# ───────────────────────────────────────────────────────────────
# Five launchd jobs, each `/bin/bash ~/.claude/scripts/research-kit/jobs/research-job.sh <job>`, which
# execs `cc-research job <job>` over every research program in certifying|certified:
#   sweep      hourly at :07     fired class-B defaults, overdue class-C conversions (§5.6)
#   freshness  daily 06:00       expired premises re-checked once per program (§5.5)
#   triage     daily 07:00       pending concerns bucketed (§5.2)
#   drift      daily 05:30       rule and lesson text diffed against acceptance rows (§5.5)
#   market     Monday 08:00      outside populations refreshed on their cadence (§5.5)
# The SSOT plists live in launchd/staged/, outside install.sh's launchd/*.plist glob, because a copy
# into ~/Library/LaunchAgents is itself an activation at the next login (tests/install-staged-plist.bats).
# c10 because loading a plist is an operator step (migrations/README.md).
#
#   0051-research-jobs.sh [--dry-run]
#
# --dry-run prints what a real run would do and touches nothing. A real run refuses until the live
# layer carries the runner and cc-research, then copies each plist into ~/Library/LaunchAgents and
# bootstraps it; a label already loaded from identical bytes is left alone, so a re-run is a no-op.
# Each load is read back with `launchctl print`; exit 1 if any label is not loaded at the end.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
RUNNER="$HOME/.claude/scripts/research-kit/jobs/research-job.sh"
CLI="$HOME/.claude/bin/cc-research"
JOBS="sweep freshness triage drift market"

dry=0
case "${1:-}" in
  --dry-run) dry=1 ;;
  '') ;;
  *) echo "usage: 0051-research-jobs.sh [--dry-run]" >&2; exit 2 ;;
esac

uid="$(id -u)"
for j in $JOBS; do
  src="$REPO/launchd/staged/com.claude.research-$j.plist"
  if [ ! -f "$src" ]; then
    echo "0051: MISSING $src — the wiring commit did not land intact; refusing" >&2
    exit 1
  fi
done

if [ "$dry" -eq 1 ]; then
  for f in "$RUNNER" "$CLI"; do
    if [ -f "$f" ]; then echo "0051: live layer has $f"; else echo "0051: live layer LACKS $f — a real run would refuse"; fi
  done
  for j in $JOBS; do
    label="com.claude.research-$j"
    echo "0051: would install $REPO/launchd/staged/$label.plist -> $LA/$label.plist and bootstrap gui/$uid/$label"
  done
  exit 0
fi

for f in "$RUNNER" "$CLI"; do
  if [ ! -f "$f" ]; then
    echo "0051: $f is not in the live layer yet — converge first (bash $REPO/scripts/deploy-live.sh), then re-run" >&2
    exit 1
  fi
done

mkdir -p "$LA" "$HOME/.claude/logs"
rc=0
for j in $JOBS; do
  label="com.claude.research-$j"
  src="$REPO/launchd/staged/$label.plist"
  dst="$LA/$label.plist"
  if launchctl print "gui/$uid/$label" >/dev/null 2>&1 && cmp -s "$src" "$dst"; then
    echo "0051: $label already loaded from the repo plist"
    continue
  fi
  launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true   # a stale copy is replaced, not doubled
  cp "$src" "$dst"
  if ! launchctl bootstrap "gui/$uid" "$dst"; then
    echo "0051: bootstrap of $label FAILED" >&2
    rc=1
    continue
  fi
  if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
    echo "0051: $label loaded"
  else
    echo "0051: $label bootstrapped but launchctl print cannot see it" >&2
    rc=1
  fi
done
exit "$rc"
