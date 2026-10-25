#!/bin/bash
# migration-class: c10
# migration-step: migration 0082 — install the compressor sentinel's plist with ProcessType Interactive and reload it, so lockprobe (the lockup sensor it hosts) and its captures run at PRI 31+ instead of the keyless PRI 20; launchctl is machine-wide, so this is yours
# migration-run: bash ~/Development/claude-infrastructure/migrations/0082-sentinel-interactive-band.sh --confirm launchd
# migration-subject: ~/Library/LaunchAgents/com.claude.compressor-sentinel.plist
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0082-sentinel-interactive-band.sh" --verify
# migration-batch-hold: manual — bounces the LIVE compressor sentinel (KeepAlive); launchctl is machine-wide
#
# ══ 0082 — the sentinel runs in the Interactive band (incident 2026-10-25, DESIGN H7) ══
# Pre-assigned as 0079 in ~/incident-2026-10-25/solution/DESIGN.md §6/§8 H7; 0079 and 0080 were
# already on trunk (the usage-levers migrations), so this is the next number lane D did not hold.
#
# WHY. The keyless plist measured PRI 20, not the interactive band its header claimed (DESIGN C2,
# F23). The sentinel now hosts lockprobe.py, the lockup sensor, and every capture it spawns inherits
# that band: at PRI 20 the 03:43:05 precursor snapshot came back empty. lockprobe's shadow audit
# refuses every pass_* until it and a capture child read PRI >= 31 back (`pass_band`), so without
# this step Phase 2 never arms. The repo plist already carries the key; launchd only re-reads the
# installed copy on a reload, and install.sh does not bounce a KeepAlive daemon by default.
#
# CLASS c10: it installs a launchd plist and bootout+bootstraps a live KeepAlive job (README.md:
# a migration that touches a plist declares c10 and waits for a human).
#
#   0082-sentinel-interactive-band.sh [--dry-run | --verify | --confirm launchd | --undo]
# Exit: 0 applied (or already applied) · 1 failure · 2 usage · 75 vetoed (the sentinel owes SIGCONT
# to frozen pids — install.sh's resident_bounce_vetoed; re-run once its ledger is empty).
# Verify reads back through `launchctl print` (spawn type), a different call than the one that
# made the change. --undo restores the newest .bak-0082-* copy and reloads the same way.
# Seams: CC_0082_LAUNCHCTL · CC_MIGRATION_LA_DIR · CC_MIGRATION_REPO · CC_SENTINEL_FROZEN_DB ·
# CC_0082_UNLOAD_WAIT_S (20). bash 3.2-safe.
set -uo pipefail

N=0082
LABEL=com.claude.compressor-sentinel
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CC_MIGRATION_REPO:-$(cd "$here/.." && pwd)}"
SRC="$REPO/launchd/$LABEL.plist"
LC="${CC_0082_LAUNCHCTL:-launchctl}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
DST="$LA/$LABEL.plist"
DOMAIN="gui/$(id -u)"
WAIT_S="${CC_0082_UNLOAD_WAIT_S:-20}"

say() { printf '%s: %s\n' "$N" "$*"; }
err() { printf '%s: %s\n' "$N" "$*" >&2; }

mode=""
case "${1:-}" in
  ''|--dry-run) mode=dry ;;
  --verify) mode=verify ;;
  --undo) mode=undo ;;
  --confirm) [ "${2:-}" = launchd ] || { err "--confirm must name its target: --confirm launchd"; exit 2; }
             mode=apply ;;
  *) err "unknown argument $1 (use --dry-run, --verify, --undo or --confirm launchd)"; exit 2 ;;
esac

declares_interactive() { # <plist> → rc 0 when it declares ProcessType Interactive
  [ "$(/usr/libexec/PlistBuddy -c 'Print :ProcessType' "$1" 2>/dev/null)" = Interactive ]
}
job_print()  { "$LC" print "$DOMAIN/$LABEL" 2>/dev/null; }
job_loaded() { job_print > /dev/null; }
# `launchctl print` renders the band as `spawn type = interactive (4)` (tests/lr-band-reload.bats).
loaded_interactive() { job_print | grep -E '^[[:space:]]*spawn type = interactive' > /dev/null; }
vetoed() {
  local db="${CC_SENTINEL_FROZEN_DB:-$HOME/.claude/logs/compressor-sentinel-frozen.tsv}"
  [ -s "$db" ]
}

reload() { # bootout, wait until unloaded, bootstrap, read back
  "$LC" bootout "$DOMAIN/$LABEL" 2>/dev/null || { err "bootout of $LABEL FAILED — the new bytes apply at its next load"; return 1; }
  local i=0
  while job_loaded && [ "$i" -lt "$WAIT_S" ]; do sleep 1; i=$((i + 1)); done
  if job_loaded; then err "$LABEL still loaded ${WAIT_S}s after bootout — not bootstrapped; re-run"; return 1; fi
  if ! "$LC" bootstrap "$DOMAIN" "$DST"; then
    err "bootstrap of $LABEL FAILED — it is NOT loaded; load it: launchctl bootstrap $DOMAIN $DST"
    return 1
  fi
  return 0
}

if [ "$mode" = verify ]; then
  rc=0
  declares_interactive "$DST" || { err "NOT live — $DST does not declare ProcessType Interactive"; rc=1; }
  if ! job_loaded; then err "NOT live — $LABEL is not loaded"; rc=1
  elif ! loaded_interactive; then err "NOT live — the loaded $LABEL is not in the interactive band (reload it)"; rc=1; fi
  [ "$rc" -eq 0 ] && say "live — $LABEL runs as ProcessType Interactive"
  exit "$rc"
fi

if [ "$mode" = undo ]; then
  bak=""
  for f in "$DST.bak-$N-"*; do [ -f "$f" ] && bak="$f"; done   # glob order is lexical = newest last
  [ -n "$bak" ] || { err "no $DST.bak-$N-* backup to restore — nothing done"; exit 1; }
  vetoed && { say "vetoed: re-run — $LABEL owes SIGCONT to frozen pid(s); nothing changed"; exit 75; }
  cp -p "$bak" "$DST" || { err "restore of $bak FAILED"; exit 1; }
  reload || exit 1
  say "undone — restored $bak and reloaded $LABEL"
  exit 0
fi

[ -f "$SRC" ] || { err "MISSING $SRC — the wiring commit did not land intact; nothing done"; exit 1; }
if ! declares_interactive "$SRC" || ! plutil -lint -s "$SRC" > /dev/null 2>&1; then
  err "$SRC does not declare ProcessType Interactive or fails plutil — refusing to install it"; exit 1
fi
# Premise re-derived at consumption: someone may have applied it already.
if [ -f "$DST" ] && declares_interactive "$DST" && job_loaded && loaded_interactive; then
  say "already applied — $LABEL is loaded in the interactive band"
  exit 0
fi

if [ "$mode" = dry ]; then
  say "would install $SRC over $DST (backup first), then bootout + bootstrap $LABEL"
  say "dry run — nothing changed; act with: bash $REPO/migrations/$N-sentinel-interactive-band.sh --confirm launchd"
  exit 0
fi

vetoed && { say "vetoed: re-run — $LABEL owes SIGCONT to frozen pid(s) (install.sh's veto); nothing changed"; exit 75; }
mkdir -p "$LA" || { err "mkdir $LA FAILED"; exit 1; }
if [ -f "$DST" ]; then
  bak="$DST.bak-$N-$(date +%Y%m%d%H%M%S)"
  cp -p "$DST" "$bak" || { err "backup of $DST FAILED — nothing changed"; exit 1; }
  say "backup $bak"
fi
tmp="$LA/.$LABEL.plist.tmp.$$"
if ! { cp "$SRC" "$tmp" && mv -f "$tmp" "$DST"; }; then
  rm -f "$tmp"; err "install of $DST FAILED"; exit 1
fi
cmp -s "$SRC" "$DST" || { err "$DST does not match $SRC after the install"; exit 1; }
say "installed $SRC -> $DST"
if job_loaded; then
  reload || exit 1
else
  "$LC" bootstrap "$DOMAIN" "$DST" || { err "bootstrap of $LABEL FAILED — load it: launchctl bootstrap $DOMAIN $DST"; exit 1; }
fi
if loaded_interactive; then
  say "done — $LABEL reloaded; launchd reports spawn type interactive"
  exit 0
fi
err "$LABEL reloaded but launchctl print does not show the interactive band"
exit 1
