#!/bin/bash
# migration-class: c10
# migration-step: reload two launchd jobs so their throttled plists take effect: com.claude.session-search-sweep (index sweep at most every 300 s) and com.claude.public-publish (daily instead of every 3 h); launchctl is machine-wide, so this is yours (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md O3)
# migration-run: bash ~/Development/claude-infrastructure/migrations/0065-load-plist-throttles.sh --confirm launchd
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0065-load-plist-throttles.sh" --verify
# migration-batch-hold: manual — reloads LIVE launchd jobs; launchctl is machine-wide
#
# WHAT THIS RELOADS (load plan O3, docs/research/load-hook-timeouts-2026-10-11/DESIGN.md "O3")
# ───────────────────────────────────────────────────────────────
#   com.claude.session-search-sweep  EnvironmentVariables SESSION_INDEX_SWEEP_MIN_INTERVAL_S=300.
#       StartInterval stays 60; the script's own knob (hooks/session-index-sweep.sh "Cadence knob")
#       makes every tick inside 300 s of the last real pass exit before touching the DB, instead of
#       walking ~17k project directories each minute.
#   com.claude.public-publish        StartInterval 10800 → 86400 (daily; fleet.manifest agrees).
#
# The plist bytes land at converge: install.sh copies launchd/*.plist into ~/Library/LaunchAgents,
# and for a `run`-declared label whose plist changed it reloads the job itself — UNLESS the job is
# executing at that instant, when it prints "not reloaded (new plist applies at its next load)".
# launchd re-reads a plist only on a reload, so a skipped reload leaves the old cadence running
# until the next login. This migration is that reload, and its --verify reads the effect back from
# `launchctl print`, so a converge that already reloaded both reads as live and needs nothing.
#
#   0065-load-plist-throttles.sh [--dry-run | --verify | --confirm launchd]
#
# A bare run is a dry run: it prints the plan and changes nothing. `--confirm launchd`, per label:
#   1. a job already loaded from the repo bytes with the effect visible is left alone (re-run = no-op);
#   2. never boots out a running tick: waits up to CC_0065_WAIT_S (130 s) for it to end, otherwise
#      that label exits 75 `busy: re-run` with nothing changed (public-publish ticks can run long);
#   3. backs up a differing ~/Library/LaunchAgents copy beside it, installs the repo plist via tmp +
#      mv, boots out the old job (tolerating not-loaded), bootstraps it, reads `launchctl print` back.
# Exit: 0 both live · 1 failure · 2 usage · 75 a job was busy (re-run).
# Undo: restore the printed .bak-* copy over ~/Library/LaunchAgents/<label>.plist, then
#       launchctl bootout gui/$(id -u)/<label>; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<label>.plist
#
# The verifier is config-dir invariant (launchd is singular; migrations/README.md "per-config-dir loop").
# Seams: CC_0065_LAUNCHCTL (default launchctl) · CC_MIGRATION_LA_DIR · CC_MIGRATION_REPO ·
# CC_0065_WAIT_S · CC_0065_POLL_S (default 2) · HOME.
set -uo pipefail

N=0065
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CC_MIGRATION_REPO:-$(cd "$here/.." && pwd)}"
LC="${CC_0065_LAUNCHCTL:-launchctl}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
WAIT_S="${CC_0065_WAIT_S:-130}"
POLL_S="${CC_0065_POLL_S:-2}"
DOMAIN="gui/$(id -u)"
LABELS=(com.claude.session-search-sweep com.claude.public-publish)

say() { printf '%s: %s\n' "$N" "$*"; }
err() { printf '%s: %s\n' "$N" "$*" >&2; }

# The line `launchctl print` shows once the new plist is the loaded one (format read off live jobs
# 2026-10-12: env as `<TAB><TAB>KEY => value` under `environment = {`, cadence as `run interval = N seconds`).
effect_re() {
  case "$1" in
    com.claude.session-search-sweep) printf '%s' '^[[:space:]]*SESSION_INDEX_SWEEP_MIN_INTERVAL_S => 300$' ;;
    com.claude.public-publish)       printf '%s' '^[[:space:]]*run interval = 86400 seconds$' ;;
  esac
}
effect_txt() {
  case "$1" in
    com.claude.session-search-sweep) printf 'SESSION_INDEX_SWEEP_MIN_INTERVAL_S => 300' ;;
    com.claude.public-publish)       printf 'run interval = 86400 seconds' ;;
  esac
}

job_print()   { "$LC" print "$DOMAIN/$1" 2>/dev/null; }
job_loaded()  { job_print "$1" >/dev/null; }
job_running() { job_print "$1" | grep -E '^[[:space:]]*state = running' >/dev/null; }
job_live()    { job_print "$1" | grep -E "$(effect_re "$1")" >/dev/null; }
# Waits (bounded) for a running tick to end. rc 0 = not running now, rc 1 = still running at the bound.
wait_idle() {
  local waited=0
  while job_running "$1"; do
    [ "$waited" -ge "$WAIT_S" ] && return 1
    sleep "$POLL_S"; waited=$((waited + POLL_S))
  done
  return 0
}

mode=""
case "${1:-}" in
  ''|--dry-run) mode=dry ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = launchd ] || { err "--confirm must name its target: --confirm launchd"; exit 2; }
             mode=apply ;;
  *) err "unknown argument $1 (use --dry-run, --verify or --confirm launchd)"; exit 2 ;;
esac

if [ "$mode" = verify ]; then
  rc=0
  for label in "${LABELS[@]}"; do
    if job_live "$label"; then say "live — $label shows '$(effect_txt "$label")'"
    else err "NOT live — launchctl print $DOMAIN/$label lacks '$(effect_txt "$label")'"; rc=1; fi
  done
  exit "$rc"
fi

for label in "${LABELS[@]}"; do
  src="$REPO/launchd/$label.plist"
  [ -f "$src" ] || { err "MISSING $src — the wiring commit did not land intact; refusing"; exit 1; }
  plutil -lint -s "$src" >/dev/null 2>&1 || { err "$src does not lint (plutil -lint); refusing"; exit 1; }
done

if [ "$mode" = dry ]; then
  for label in "${LABELS[@]}"; do
    if job_live "$label" && cmp -s "$REPO/launchd/$label.plist" "$LA/$label.plist"; then
      say "$label is already loaded from the repo plist with '$(effect_txt "$label")' — a real run would change nothing"
    else
      say "would install $REPO/launchd/$label.plist -> $LA/$label.plist (backing up a differing copy), boot out"
      say "$label once no tick is running, bootstrap $DOMAIN and read back '$(effect_txt "$label")'"
    fi
  done
  say "dry run — nothing changed; act with: bash $REPO/migrations/0065-load-plist-throttles.sh --confirm launchd"
  exit 0
fi

mkdir -p "$LA" || { err "mkdir $LA FAILED — nothing loaded"; exit 1; }

# One label end to end. rc 0 live · 1 failure · 75 busy.
reload_one() {
  local label="$1" src="$REPO/launchd/$1.plist" dst="$LA/$1.plist" bak="" tmp i out
  if job_live "$label" && cmp -s "$src" "$dst"; then
    say "$label already loaded from the repo plist with '$(effect_txt "$label")' — skip"
    return 0
  fi
  # Never boot out a running tick. Checked BEFORE installing, so a busy exit leaves the old bytes.
  if job_loaded "$label" && ! wait_idle "$label"; then
    say "busy: re-run — $label was running at every poll for ${WAIT_S}s; nothing changed"
    return 75
  fi
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    bak="$dst.bak-$(date +%Y%m%d%H%M%S)"
    cp -p "$dst" "$bak" || { err "backup of $dst FAILED — $label left as it was"; return 1; }
    say "backed up the previous $label plist to $bak"
  fi
  if ! cmp -s "$src" "$dst"; then
    tmp="$LA/.$label.plist.tmp.$$"
    if ! { cp "$src" "$tmp" && mv -f "$tmp" "$dst"; }; then
      rm -f "$tmp"; err "install of $dst FAILED — $label not reloaded"; return 1
    fi
  fi
  if job_loaded "$label"; then
    # A tick that began in the gap: put the previous bytes back so the next run is not skipped.
    if job_running "$label"; then
      if [ -n "$bak" ]; then cp -p "$bak" "$dst"; fi
      say "busy: re-run — a $label tick started before the bootout; nothing reloaded"
      return 75
    fi
    "$LC" bootout "$DOMAIN/$label" 2>/dev/null || { err "bootout of $label FAILED — left as it was"; return 1; }
    i=0
    while job_loaded "$label" && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done
    if job_loaded "$label"; then err "$label still loaded 20 s after bootout — not bootstrapped; re-run"; return 1; fi
  fi
  if ! "$LC" bootstrap "$DOMAIN" "$dst"; then
    err "bootstrap of $label FAILED — re-load it: launchctl bootstrap $DOMAIN $dst"
    return 1
  fi
  # Read back through a different call than the one that made the change.
  out="$(job_print "$label")" || { err "$label bootstrapped but launchctl print cannot see it"; return 1; }
  printf '%s\n' "$out" | grep -E "$(effect_re "$label")" >/dev/null \
    || { err "$label: launchctl print does not read back '$(effect_txt "$label")'"; return 1; }
  say "$label reloaded and read back ('$(effect_txt "$label")')"
  return 0
}

worst=0
for label in "${LABELS[@]}"; do
  reload_one "$label"; rc=$?
  if [ "$rc" -eq 1 ] || { [ "$rc" -eq 75 ] && [ "$worst" -eq 0 ]; }; then worst=$rc; fi
done
[ "$worst" -eq 0 ] && say "both jobs live with their throttles"
exit "$worst"
