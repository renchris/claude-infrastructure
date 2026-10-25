#!/bin/bash
# migration-class: c10
# migration-step: reload three launchd jobs so they start under /bin/bash -c instead of a login zsh: com.chrisren.autonomy-sweep, com.chrisren.dl-sweep and com.chrisren.cc-reaper (lockup incident 2026-10-25, DESIGN C4 R5); launchctl is machine-wide, so this is yours
# migration-run: bash ~/Development/claude-infrastructure/migrations/0083-spawner-plists-bash.sh --confirm launchd
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0083-spawner-plists-bash.sh" --verify
# migration-batch-hold: manual — reloads LIVE launchd jobs; launchctl is machine-wide
#
# WHY (~/incident-2026-10-25/solution/DESIGN.md C4 R5; fleet-governor.md R5)
# ───────────────────────────────────────────────────────────────
#   The three jobs started as `/bin/zsh -lc …`: a login shell that reads the profile files and forks
#   its startup helpers before the job's first line. The reaper is a mitigation tool and the other two
#   are spawners, and all three must start on a sick box; a mitigation must not depend on a login zsh.
#   The repo plists now run `/bin/bash -c` with the login shell's PATH order written out, so every
#   command resolves exactly as it did under -l. The scripts themselves were already /bin/bash
#   (autonomy-sweep, cc-reaper) or are 3.2-clean (dl-sweep, which ran under `env bash`).
#
# The plist bytes land at converge: install.sh copies launchd/*.plist into ~/Library/LaunchAgents.
# launchd re-reads a plist only on a reload, so the old zsh form keeps running until one. This
# migration is that reload, and --verify reads the effect back from `launchctl print` (the line
# `program = /bin/bash`), so a converge that already reloaded all three reads as live.
#
#   0083-spawner-plists-bash.sh [--dry-run | --verify | --confirm launchd | --undo]
#
# A bare run is a dry run: it prints the plan and changes nothing. `--confirm launchd`, per label:
#   1. a job already loaded from the repo bytes with the effect visible is left alone (re-run = no-op);
#   2. never boots out a running tick: waits up to CC_0083_WAIT_S (130 s), else that label exits 75
#      `busy: re-run` with nothing changed;
#   3. backs up a differing ~/Library/LaunchAgents copy beside it (.bak-<stamp>), installs the repo
#      plist via tmp + mv, boots out the old job (tolerating not-loaded), bootstraps it, reads back.
# `--undo` puts each label's newest .bak-* back and reloads it the same way. The next converge
# re-installs the repo plist, so the durable undo is `git revert` of the plist commit.
# Exit: 0 all live · 1 failure · 2 usage · 75 a job was busy (re-run).
#
# Nothing here kills a process: a bootout ends a job only between ticks (step 2), and none of these
# jobs is a pty session leader.
# Seams: CC_0083_LAUNCHCTL (default launchctl) · CC_MIGRATION_LA_DIR · CC_MIGRATION_REPO ·
# CC_0083_WAIT_S · CC_0083_POLL_S (default 2) · HOME.
set -uo pipefail

N=0083
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CC_MIGRATION_REPO:-$(cd "$here/.." && pwd)}"
LC="${CC_0083_LAUNCHCTL:-launchctl}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
WAIT_S="${CC_0083_WAIT_S:-130}"
POLL_S="${CC_0083_POLL_S:-2}"
DOMAIN="gui/$(id -u)"
LABELS=(com.chrisren.autonomy-sweep com.chrisren.dl-sweep com.chrisren.cc-reaper)
EFFECT_RE='^[[:space:]]*program = /bin/bash$'
EFFECT_TXT='program = /bin/bash'

say() { printf '%s: %s\n' "$N" "$*"; }
err() { printf '%s: %s\n' "$N" "$*" >&2; }

job_print()   { "$LC" print "$DOMAIN/$1" 2>/dev/null; }
job_loaded()  { job_print "$1" >/dev/null; }
job_running() { job_print "$1" | grep -E '^[[:space:]]*state = running' >/dev/null; }
job_live()    { job_print "$1" | grep -E "$EFFECT_RE" >/dev/null; }
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
  --undo) mode=undo ;;
  --confirm) [ "${2:-}" = launchd ] || { err "--confirm must name its target: --confirm launchd"; exit 2; }
             mode=apply ;;
  *) err "unknown argument $1 (use --dry-run, --verify, --confirm launchd or --undo)"; exit 2 ;;
esac

if [ "$mode" = verify ]; then
  rc=0
  for label in "${LABELS[@]}"; do
    if job_live "$label"; then say "live — $label shows '$EFFECT_TXT'"
    else err "NOT live — launchctl print $DOMAIN/$label lacks '$EFFECT_TXT'"; rc=1; fi
  done
  exit "$rc"
fi

for label in "${LABELS[@]}"; do
  src="$REPO/launchd/$label.plist"
  [ -f "$src" ] || { err "MISSING $src — the wiring commit did not land intact; refusing"; exit 1; }
  plutil -lint -s "$src" >/dev/null 2>&1 || { err "$src does not lint (plutil -lint); refusing"; exit 1; }
  grep -q '<string>/bin/zsh</string>' "$src" && { err "$src still starts /bin/zsh — refusing to reload it"; exit 1; }
done

if [ "$mode" = dry ]; then
  for label in "${LABELS[@]}"; do
    if job_live "$label" && cmp -s "$REPO/launchd/$label.plist" "$LA/$label.plist"; then
      say "$label is already loaded from the repo plist with '$EFFECT_TXT' — a real run would change nothing"
    else
      say "would install $REPO/launchd/$label.plist -> $LA/$label.plist (backing up a differing copy), boot out"
      say "$label once no tick is running, bootstrap $DOMAIN and read back '$EFFECT_TXT'"
    fi
  done
  say "dry run — nothing changed; act with: bash $REPO/migrations/0083-spawner-plists-bash.sh --confirm launchd"
  exit 0
fi

mkdir -p "$LA" || { err "mkdir $LA FAILED — nothing loaded"; exit 1; }

# Reload one label from <src>. rc 0 done · 1 failure · 75 busy. $3=1 reads back the effect.
reload_one() {
  local label="$1" src="$2" want="$3" dst="$LA/$1.plist" bak="" tmp i out
  if [ "$want" = 1 ] && job_live "$label" && cmp -s "$src" "$dst"; then
    say "$label already loaded from the repo plist with '$EFFECT_TXT' — skip"
    return 0
  fi
  # Never boot out a running tick. Checked BEFORE installing, so a busy exit leaves the old bytes.
  if job_loaded "$label" && ! wait_idle "$label"; then
    say "busy: re-run — $label was running at every poll for ${WAIT_S}s; nothing changed"
    return 75
  fi
  if [ "$want" = 1 ] && [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
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
  if [ "$want" = 1 ]; then
    printf '%s\n' "$out" | grep -E "$EFFECT_RE" >/dev/null \
      || { err "$label: launchctl print does not read back '$EFFECT_TXT'"; return 1; }
    say "$label reloaded and read back ('$EFFECT_TXT')"
  else
    say "$label restored from $src and reloaded"
  fi
  return 0
}

worst=0
for label in "${LABELS[@]}"; do
  if [ "$mode" = undo ]; then
    b=""
    for f in "$LA/$label.plist.bak-"*; do [ -f "$f" ] && b="$f"; done
    if [ -z "$b" ]; then say "$label: no .bak-* beside $LA/$label.plist — nothing to undo"; continue; fi
    reload_one "$label" "$b" 0; rc=$?
  else
    reload_one "$label" "$REPO/launchd/$label.plist" 1; rc=$?
  fi
  if [ "$rc" -eq 1 ] || { [ "$rc" -eq 75 ] && [ "$worst" -eq 0 ]; }; then worst=$rc; fi
done
[ "$worst" -eq 0 ] && [ "$mode" = apply ] && say "all three jobs live under /bin/bash"
exit "$worst"
