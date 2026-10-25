#!/bin/bash
# migration-class: c10
# migration-step: migration 0079 — load the usage levers' two launchd jobs: com.claude.lever-guard (every 600 s: demotes a lever to pct 0 and latches a trip on a guard breach, a REVERT verdict or two blind ticks, and writes the guard heartbeat without which every raise is refused) and com.claude.lever-score (hourly: lever verdicts, the session ledger and the guard rows). Neither raises a lever; every lever stays where it is (S0, pct 0 today). Loading a plist is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0079-lever-jobs-activate.sh --confirm launchd
# migration-subject: ~/Library/LaunchAgents/com.claude.lever-guard.plist ~/Library/LaunchAgents/com.claude.lever-score.plist
# migration-verify: launchctl print "gui/$(id -u)/com.claude.lever-guard" >/dev/null 2>&1 && launchctl print "gui/$(id -u)/com.claude.lever-score" >/dev/null 2>&1
#
# ══ 0079 — the usage levers' guard and scorer jobs (docs/plans/USAGE_LEVERS.md § W7+ §3 "Auto-rollback", §5.1) ══
# Both plists are SSOT in launchd/staged/, outside install.sh's launchd/*.plist glob, so nothing loads
# them but this. What each does is in its own plist header. Loading them changes no lever: the guard
# only ever lowers, and at S0 (pct 0) there is nothing to lower. What it ENABLES is the operator's
# own raises, which cc-lever refuses without a guard heartbeat younger than 1800 s.
#
# SAFETY. Refuses until the live layer carries bin/cc-lever-guard, bin/cc-lever-score and bin/cc-lever
# (converge first). Backs up ~/.claude/settings.json (it is not edited here; the copy keeps the c10
# rollback uniform) to ~/.claude/backups/lever-jobs-0079-<ts>/ in the layout
# `bash scripts/c10-batch.sh --rollback <dir>` reads. A label already loaded from identical bytes is
# left alone, so a re-run is a no-op; a stale copy is booted out and replaced, never doubled. Each
# load is read back with `launchctl print`.
# Undo: launchctl bootout gui/$(id -u)/com.claude.lever-guard ; launchctl bootout gui/$(id -u)/com.claude.lever-score
#   (then every live lever falls to pct 0 within 1800 s by the dead-man; nothing else needs undoing).
#
# Usage: bash migrations/0079-lever-jobs-activate.sh --dry-run    # what a real run would do; touches nothing
#        bash migrations/0079-lever-jobs-activate.sh --verify     # rc 0 iff both labels are loaded
#        bash migrations/0079-lever-jobs-activate.sh --confirm launchd
# Exit: 0 loaded / already loaded / dry run · 1 failure · 2 usage (no --confirm: nothing touched) ·
#       4 REFUSED, the live layer lacks the jobs' code (converge first)
# Seams (tests): CC_MIGRATION_REPO, CC_MIGRATION_LA_DIR; launchctl resolves on PATH. bash 3.2-safe.
set -uo pipefail

N=0079
REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
LABELS="com.claude.lever-guard com.claude.lever-score"
NEEDS="$HOME/.claude/bin/cc-lever-guard $HOME/.claude/bin/cc-lever-score $HOME/.claude/bin/cc-lever"

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --verify) mode=verify ;;
  --confirm)
    case "${2:-launchd}" in
      launchd) mode=apply ;;
      *) printf '%s: --confirm names its target: --confirm launchd (got %s)\n' "$N" "$2" >&2; exit 2 ;;
    esac ;;
  '') printf '%s: refused — pass --dry-run, --verify or --confirm launchd; nothing touched\n' "$N" >&2; exit 2 ;;
  *) printf '%s: unknown argument %s (use --dry-run, --verify or --confirm launchd)\n' "$N" "$1" >&2; exit 2 ;;
esac

uid="$(id -u)"
loaded() { launchctl print "gui/$uid/$1" >/dev/null 2>&1; }

if [ "$mode" = verify ]; then
  for l in $LABELS; do loaded "$l" || exit 1; done
  exit 0
fi

for l in $LABELS; do
  [ -f "$REPO/launchd/staged/$l.plist" ] || {
    printf '%s: MISSING %s — the wave S6 commit did not land intact; nothing touched\n' "$N" "$REPO/launchd/staged/$l.plist" >&2
    exit 1
  }
done
miss=""
for f in $NEEDS; do [ -f "$f" ] || miss="$miss $f"; done
[ -x /usr/bin/python3 ] || miss="$miss /usr/bin/python3"

if [ "$mode" = dry ]; then
  [ -z "$miss" ] && printf '%s: the live layer carries the jobs'"'"' code\n' "$N" \
                 || printf '%s: the live layer LACKS%s — a real run would refuse (exit 4)\n' "$N" "$miss"
  for l in $LABELS; do
    if loaded "$l" && cmp -s "$REPO/launchd/staged/$l.plist" "$LA/$l.plist"; then
      printf '%s: %s already loaded from the repo plist — a real run leaves it\n' "$N" "$l"
    else
      printf '%s: would install %s -> %s and bootstrap gui/%s/%s\n' "$N" "$REPO/launchd/staged/$l.plist" "$LA/$l.plist" "$uid" "$l"
    fi
  done
  printf '%s: DRY RUN — nothing touched\n' "$N"
  exit 0
fi

[ -z "$miss" ] || {
  printf '%s: REFUSED — the live layer lacks%s. Converge first: bash %s/scripts/deploy-live.sh\n' "$N" "$miss" "$REPO" >&2
  exit 4
}

bdir="$HOME/.claude/backups/lever-jobs-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" || { printf '%s: backup dir FAILED — nothing touched\n' "$N" >&2; exit 1; }
: > "$bdir/MANIFEST"
if [ -f "$HOME/.claude/settings.json" ]; then
  cp -pL "$HOME/.claude/settings.json" "$bdir/shared.settings.json" || { printf '%s: backup FAILED — nothing touched\n' "$N" >&2; exit 1; }
fi
printf '%s: backup %s\n' "$N" "$bdir"

mkdir -p "$LA" "$HOME/.claude/logs"
rc=0
for l in $LABELS; do
  src="$REPO/launchd/staged/$l.plist" dst="$LA/$l.plist"
  if loaded "$l" && cmp -s "$src" "$dst"; then
    printf '%s: %s already loaded from the repo plist\n' "$N" "$l"
    continue
  fi
  launchctl bootout "gui/$uid/$l" >/dev/null 2>&1 || true     # a stale copy is replaced, not doubled
  if ! cp "$src" "$dst"; then printf '%s: copy of %s FAILED\n' "$N" "$l" >&2; rc=1; continue; fi
  if ! launchctl bootstrap "gui/$uid" "$dst"; then printf '%s: bootstrap of %s FAILED\n' "$N" "$l" >&2; rc=1; continue; fi
  if loaded "$l"; then
    printf '%s: %s loaded\n' "$N" "$l"
  else
    printf '%s: %s bootstrapped but launchctl print cannot see it\n' "$N" "$l" >&2; rc=1
  fi
done
[ "$rc" -eq 0 ] && printf '%s: verified — both jobs loaded. The guard writes its heartbeat on load; read it with: cc-lever-guard status\n' "$N"
printf '%s: undo: launchctl bootout gui/%s/com.claude.lever-guard ; launchctl bootout gui/%s/com.claude.lever-score\n' "$N" "$uid" "$uid"
exit "$rc"
