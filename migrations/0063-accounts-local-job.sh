#!/bin/bash
# migration-class: c10
# migration-step: load com.claude.accounts-local (the 20 s local auth + live-session refresh for the account board and router), installing it from launchd/staged; launchctl is machine-wide, so this is yours
# migration-run: bash ~/Development/claude-infrastructure/migrations/0063-accounts-local-job.sh --confirm launchd
# migration-subject: ~/Development/claude-infrastructure/launchd/staged/com.claude.accounts-local.plist
# migration-verify: launchctl print gui/$(id -u)/com.claude.accounts-local 2>/dev/null | grep -q 'run interval = 20' && [ $(( $(date +%s) - $(stat -f %m "$HOME/.claude/logs/accounts-local.stamp" 2>/dev/null || echo 0) )) -lt 600 ]
# migration-batch-hold: manual — boots a LIVE launchd job; launchctl is machine-wide and the batch's scratch-HOME rehearsal cannot sandbox it
#
# WHAT THIS LOADS (docs/plans/ACCOUNTS_BOARD_FRESHNESS.md D9)
# ───────────────────────────────────────────────────────────────
# One launchd job, `claude-accounts --local-refresh` every 20 s plus a login.keychain-db WatchPaths
# accelerator: it refreshes auth state and live sessions for the account board and the router from
# this machine only, and never writes the cache `ts`, so keepwarm's usage sweeps are never silenced.
# The SSOT plist lives in launchd/staged/, outside install.sh's launchd/*.plist glob, because a copy
# into ~/Library/LaunchAgents is itself an activation at the next login (tests/install-staged-plist.bats).
# The subject is the repo arm, so registration-state reads `staged-pending` while this waits.
#
#   0063-accounts-local-job.sh [--dry-run | --confirm launchd]
#
# A bare run is a dry run: it prints the plan and changes nothing. `--confirm launchd` acts:
#   1. refuses unless `CC_ACCOUNTS_LOCAL=off claude-accounts --local-refresh` prints exactly
#      `local: disabled` — the live layer must carry the verb, and the probe never runs a real pass;
#   2. a job already loaded from identical bytes is left alone, so a re-run is a no-op;
#   3. never boots out a running tick: it waits up to CC_0063_WAIT_S (130 s) for the tick to end and
#      otherwise exits 75 `busy: re-run` with nothing changed;
#   4. backs up a differing live plist beside it, installs via a tmp file + mv, boots out the old
#      job (bounded wait), bootstraps the new one, reads `launchctl print` back (state, run
#      interval 20) and waits up to CC_0063_STAMP_WAIT_S (60 s) for the job to touch its stamp.
# Undo: launchctl bootout gui/$(id -u)/com.claude.accounts-local; rm ~/Library/LaunchAgents/com.claude.accounts-local.plist
#
# Seams (tests/migration-0063-accounts-local-job.bats): CC_0063_LAUNCHCTL (default launchctl) ·
# CC_MIGRATION_LA_DIR · CC_MIGRATION_REPO · CC_0063_CA_BIN · CC_0063_WAIT_S · CC_0063_STAMP_WAIT_S ·
# CC_0063_POLL_S (default 2) · HOME.
set -uo pipefail

N=0063
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CC_MIGRATION_REPO:-$(cd "$here/.." && pwd)}"
LC="${CC_0063_LAUNCHCTL:-launchctl}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
CA_BIN="${CC_0063_CA_BIN:-$HOME/.claude/bin/claude-accounts}"
WAIT_S="${CC_0063_WAIT_S:-130}"
STAMP_WAIT_S="${CC_0063_STAMP_WAIT_S:-60}"
POLL_S="${CC_0063_POLL_S:-2}"
LABEL="com.claude.accounts-local"
DOMAIN="gui/$(id -u)"
STAMP="$HOME/.claude/logs/accounts-local.stamp"
LOCAL_DIR="$HOME/.claude/state/accounts-local"
src="$REPO/launchd/staged/$LABEL.plist"
dst="$LA/$LABEL.plist"

say() { printf '%s: %s\n' "$N" "$*"; }
err() { printf '%s: %s\n' "$N" "$*" >&2; }

mode=""
case "${1:-}" in
  ''|--dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = launchd ] || { err "--confirm must name its target: --confirm launchd"; exit 2; }
             mode=apply ;;
  *) err "unknown argument $1 (use --dry-run or --confirm launchd)"; exit 2 ;;
esac

job_print()   { "$LC" print "$DOMAIN/$LABEL" 2>/dev/null; }
job_loaded()  { job_print >/dev/null; }
job_running() { job_print | grep -E '^[[:space:]]*state = running' >/dev/null; }
stamp_mtime() { stat -f %Fm "$STAMP" 2>/dev/null || echo absent; }
# Waits (bounded) for a running tick to end. rc 0 = not running now, rc 1 = still running at the bound.
wait_idle() {
  local waited=0
  while job_running; do
    [ "$waited" -ge "$WAIT_S" ] && return 1
    sleep "$POLL_S"; waited=$((waited + POLL_S))
  done
  return 0
}

if [ ! -f "$src" ]; then
  err "MISSING $src — the wiring commit did not land intact; refusing"
  exit 1
fi

if [ "$mode" = dry ]; then
  if [ -x "$CA_BIN" ]; then say "live layer has $CA_BIN (a real run first checks it prints 'local: disabled' under CC_ACCOUNTS_LOCAL=off)"
  else say "live layer LACKS $CA_BIN — a real run would refuse"; fi
  if job_loaded && cmp -s "$src" "$dst"; then
    say "$LABEL is already loaded from the repo plist — a real run would change nothing"
  else
    say "would mkdir -p $LOCAL_DIR, install $src -> $dst (backing up a differing copy), boot out any loaded"
    say "$LABEL once no tick is running, bootstrap $DOMAIN, read it back and wait for $STAMP to move"
  fi
  say "dry run — nothing changed; act with: bash $REPO/migrations/0063-accounts-local-job.sh --confirm launchd"
  exit 0
fi

# 1. Precondition: the verb exists in the live layer. The off switch makes the probe touch the stamp
#    and print one line; it never runs a real pass.
probe="$(CC_ACCOUNTS_LOCAL=off "$CA_BIN" --local-refresh 2>/dev/null)"
if [ "$probe" != "local: disabled" ]; then
  err "CC_ACCOUNTS_LOCAL=off $CA_BIN --local-refresh did not print 'local: disabled' (got: ${probe:-nothing})"
  err "the live layer lacks the --local-refresh verb — converge first (bash $REPO/scripts/deploy-live.sh), then re-run"
  exit 1
fi

mkdir -p "$LOCAL_DIR" "$HOME/.claude/logs" "$LA" || { err "mkdir FAILED — nothing loaded"; exit 1; }

# 2. Identical bytes, already loaded: nothing to do.
if job_loaded && cmp -s "$src" "$dst"; then
  say "$LABEL already loaded from the repo plist — skip"
  exit 0
fi

# 3. Never boot out a running tick. Checked BEFORE installing, so a busy exit leaves the old bytes in
#    place and a re-run cannot mistake a never-loaded plist for a loaded one.
if job_loaded && ! wait_idle; then
  say "busy: re-run — $LABEL was running at every poll for ${WAIT_S}s; nothing changed"
  exit 75
fi

# 4. Install: back up a differing live copy beside it (a name launchd does not load), then tmp + mv.
bak=""
if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
  bak="$dst.bak-$(date +%Y%m%d%H%M%S)"
  cp -p "$dst" "$bak" || { err "backup of $dst FAILED — nothing changed"; exit 1; }
  say "backed up the previous plist to $bak"
fi
if ! cmp -s "$src" "$dst"; then
  tmp="$LA/.$LABEL.plist.tmp.$$"
  if ! { cp "$src" "$tmp" && mv -f "$tmp" "$dst"; }; then
    rm -f "$tmp"; err "install of $dst FAILED — nothing loaded"; exit 1
  fi
fi

# 5. Reload. Re-check running immediately before the bootout; a tick that began in the gap puts the
#    previous bytes back so the next run is not skipped as identical.
if job_loaded; then
  if job_running; then
    if [ -n "$bak" ]; then cp -p "$bak" "$dst"; fi
    say "busy: re-run — a tick started before the bootout; nothing reloaded"
    exit 75
  fi
  "$LC" bootout "$DOMAIN/$LABEL" 2>/dev/null || { err "bootout of $LABEL FAILED — left as it was"; exit 1; }
  i=0
  while job_loaded && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done
  if job_loaded; then err "$LABEL still loaded 20 s after bootout — not bootstrapped; re-run"; exit 1; fi
fi
before="$(stamp_mtime)"
if ! "$LC" bootstrap "$DOMAIN" "$dst"; then
  err "bootstrap of $LABEL FAILED — re-load it: launchctl bootstrap $DOMAIN $dst"
  exit 1
fi

# 6. Read back through a different call than the one that made the change.
out="$(job_print)" || { err "$LABEL bootstrapped but launchctl print cannot see it"; exit 1; }
printf '%s\n' "$out" | grep -E '^[[:space:]]*state = ' >/dev/null \
  || { err "$LABEL: launchctl print shows no state line"; exit 1; }
printf '%s\n' "$out" | grep -F 'run interval = 20' >/dev/null \
  || { err "$LABEL: launchctl print does not read back 'run interval = 20'"; exit 1; }
say "$LABEL loaded and read back (run interval = 20)"

waited=0
while [ "$(stamp_mtime)" = "$before" ]; do
  if [ "$waited" -ge "$STAMP_WAIT_S" ]; then
    err "$LABEL is loaded but $STAMP did not move in ${STAMP_WAIT_S}s — read $HOME/.claude/logs/accounts-local.err.log"
    exit 1
  fi
  sleep "$POLL_S"; waited=$((waited + POLL_S))
done
say "$LABEL ticked: $STAMP moved after ${waited}s"
say "agent: flip the fleet.manifest row staged→run"
exit 0
