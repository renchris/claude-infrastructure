#!/bin/bash
# lr-recon-launchd.sh — load the lr-reconciler, its watchdog and the rig launchd jobs (FLEET_V2 W5,
# operator step 1). Repo SSOT for the three plists is this directory; nothing else installs them.
#
#   bash lr-recon-launchd.sh                          # dry run: lint + print what it would do, exit 0
#   bash lr-recon-launchd.sh --confirm lr-reconciler  # install + bootstrap + verify
#   bash lr-recon-launchd.sh --verify                 # verify only (no writes)
#
# Order: the rig job first (on-demand: RunAtLoad/KeepAlive false, so loading it starts nothing), then
# the real reconciler, then its watchdog. Loading the real reconciler is SAFE on its own: it acts only
# when ~/.reso/limit-recover/recon.on exists AND recon/mode says act, and this script writes neither.
#
# Re-runnable: a job whose installed plist is byte-identical to the SSOT and that launchd already
# holds is left alone; a changed plist is booted out and bootstrapped again (never a bare `load`).
# Verdict by exit code: 0 every job verified · 1 a step failed (named on stderr) · 2 usage/refused.
# Verification reads back through DIFFERENT calls than the ones that changed state: `launchctl print`
# for each label, and a fresh heartbeat write (mtime newer than the bootstrap) for the reconciler.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UID_N="$(id -u)"
DOMAIN="gui/$UID_N"
AGENTS="${LR_LAUNCHD_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
LR_STATE_DIR="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
RECON_ROOT="$LR_STATE_DIR/recon"
RIG_DIRS=(/tmp/lr-rig/state /tmp/lr-rig/lr /tmp/lr-rig/home)
LABELS=(com.reso.lr-reconciler-rig com.reso.lr-reconciler com.reso.lr-reconciler-watchdog)
HB_WAIT_S="${LR_LAUNCHD_HB_WAIT_S:-45}"
CONSENT="lr-reconciler"

MODE=dry
case "${1:-}" in
  '') ;;
  --verify) MODE=verify ;;
  --confirm)
    if [ "${2:-}" != "$CONSENT" ]; then
      echo "lr-recon-launchd: --confirm must name the target: --confirm $CONSENT" >&2; exit 2
    fi
    MODE=apply ;;
  -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
  *) echo "lr-recon-launchd: unknown argument '$1' (use --confirm $CONSENT | --verify)" >&2; exit 2 ;;
esac

fail() { echo "✗ $*" >&2; exit 1; }
loaded() { launchctl print "$DOMAIN/$1" >/dev/null 2>&1; }

# 1. lint every SSOT plist before touching anything.
for l in "${LABELS[@]}"; do
  src="$HERE/$l.plist"
  [ -f "$src" ] || fail "SSOT plist missing: $src"
  plutil -lint "$src" >/dev/null 2>&1 || fail "plutil -lint failed: $src"
done
echo "✓ plutil -lint: ${#LABELS[@]} SSOT plists"

if [ "$MODE" = dry ]; then
  for l in "${LABELS[@]}"; do
    dst="$AGENTS/$l.plist"
    if loaded "$l" && cmp -s "$HERE/$l.plist" "$dst"; then state="loaded, identical — leave"
    elif loaded "$l"; then state="loaded, plist differs — bootout + bootstrap"
    else state="not loaded — install + bootstrap"; fi
    echo "  would: $l ($state)"
  done
  echo "  would: mkdir $RECON_ROOT ${RIG_DIRS[*]} (launchd does not create log parents)"
  echo "(dry run — nothing changed. Apply with: bash $0 --confirm $CONSENT)"
  exit 0
fi

if [ "$MODE" = apply ]; then
  # launchd does not create a StandardOutPath parent: a missing one makes the job exit 78 at spawn.
  mkdir -p "$RECON_ROOT" "${RIG_DIRS[@]}" "$AGENTS" || fail "mkdir of the log/state dirs failed"
  T0="$(date +%s)"
  for l in "${LABELS[@]}"; do
    src="$HERE/$l.plist" dst="$AGENTS/$l.plist"
    if loaded "$l" && cmp -s "$src" "$dst"; then echo "· $l already loaded from the SSOT copy"; continue; fi
    if loaded "$l"; then
      launchctl bootout "$DOMAIN/$l" 2>/dev/null || fail "bootout $l failed"
      # bootout is asynchronous: wait (bounded) until launchd no longer holds the label.
      i=0; while loaded "$l" && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
    fi
    cp "$src" "$dst.tmp.$$" && mv -f "$dst.tmp.$$" "$dst" || fail "install $dst failed"
    plutil -lint "$dst" >/dev/null 2>&1 || fail "installed copy does not lint: $dst"
    launchctl bootstrap "$DOMAIN" "$dst" || fail "launchctl bootstrap $DOMAIN $dst failed"
    echo "✓ bootstrapped $l"
  done
fi

# 2. verify — read back with calls that did not make the change.
rc=0
for l in "${LABELS[@]}"; do
  if loaded "$l" && cmp -s "$HERE/$l.plist" "$AGENTS/$l.plist"; then echo "✓ launchctl print $DOMAIN/$l"
  else echo "✗ $l is not loaded from the SSOT copy" >&2; rc=1; fi
done
hb="$RECON_ROOT/heartbeat"
since="${T0:-0}"
[ "$MODE" = verify ] && since=$(( $(date +%s) - 30 ))
i=0; fresh=0
while [ $i -lt "$HB_WAIT_S" ]; do
  m="$(stat -f %m "$hb" 2>/dev/null || echo 0)"
  if [ "$m" -ge "$since" ] && [ "$m" -gt 0 ]; then fresh=1; break; fi
  sleep 1; i=$((i + 1))
done
if [ $fresh -eq 1 ]; then echo "✓ reconciler heartbeat fresh ($hb, mtime $(stat -f %Sm "$hb"))"
else echo "✗ no fresh reconciler heartbeat at $hb within ${HB_WAIT_S}s — read $RECON_ROOT/reconciler.err" >&2; rc=1; fi
[ -f "$LR_STATE_DIR/recon.on" ] && echo "· recon.on is present (the daemon may act if recon/mode=act)" \
  || echo "· recon.on absent: the reconciler observes and plans only (the safe default)"
[ $rc -eq 0 ] && echo "lr-recon-launchd: verdict=ok" || echo "lr-recon-launchd: verdict=FAILED" >&2
exit $rc
