#!/bin/bash
# lr-band-reload.sh — reload com.reso.lr-reconciler and com.reso.lr-reset-poller from the live layer
# so both run in the Interactive band (PRI 31), then read the band back. Operator step for lever A1 of
# docs/research/lr-sustained-load-2026-10-20/REPORT.md: a plist edit does nothing until the job is
# booted out and bootstrapped again, and agents may not reload launchd jobs.
#
#   bash lr-band-reload.sh                     # dry run: preflight + print what it would do, exit 0
#   bash lr-band-reload.sh --confirm lr-band   # reload both jobs, then verify
#
# Order: wait (bounded) until the reconciler has no lr-recon-act child, so no move is orphaned
# mid-act (as ~/.reso/limit-recover/design-v2/lr-restart-at-boundary.sh does); then for each job
# install the live plist into LaunchAgents, bootout, wait until launchd lets go, bootstrap (retried:
# a re-bootstrap right after a bootout can fail with "Bootstrap failed: 5", REPORT §4 A1 risk).
# Re-runnable. Verdict by exit code: 0 both verified · 1 a step or a read-back failed · 2 usage/refused.
# Read-back uses different calls than the change: `launchctl print` must say `spawn type =
# interactive`, `ps -M` is printed for each live pid, and the new reconciler's own recon/band.log
# line (lr_recon/band.py, its base priority) must read pid=<new pid> ... ok.
set -uo pipefail

UID_N="$(id -u)"
DOMAIN="gui/$UID_N"
LIVE="${LR_BAND_LIVE_DIR:-$HOME/.claude/scripts/limit-recover}"
AGENTS="${LR_LAUNCHD_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
RECON_ROOT="${LR_STATE_DIR:-$HOME/.reso/limit-recover}/recon"
WAIT_S="${LR_BAND_WAIT_S:-300}"
QUIET_MAX_S="${LR_BAND_QUIET_MAX_S:-1800}"
LABELS=(com.reso.lr-reconciler com.reso.lr-reset-poller)
CONSENT="lr-band"

MODE=dry
case "${1:-}" in
  '') ;;
  --confirm)
    [ "${2:-}" = "$CONSENT" ] || { echo "lr-band-reload: --confirm must name the target: --confirm $CONSENT" >&2; exit 2; }
    MODE=apply ;;
  -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
  *) echo "lr-band-reload: unknown argument '$1' (use --confirm $CONSENT)" >&2; exit 2 ;;
esac

fail() { echo "✗ $*" >&2; echo "lr-band-reload: verdict=FAILED" >&2; exit 1; }
loaded() { launchctl print "$DOMAIN/$1" >/dev/null 2>&1; }
job_pid() { launchctl print "$DOMAIN/$1" 2>/dev/null | awk '$1 == "pid" && $2 == "=" {print $3; exit}'; }
spawn_type() { launchctl print "$DOMAIN/$1" 2>/dev/null | sed -n 's/^[[:space:]]*spawn type = //p' | head -1; }

# 1. preflight: the live layer must already carry the Interactive band (i.e. it was converged).
for l in "${LABELS[@]}"; do
  src="$LIVE/$l.plist"
  [ -f "$src" ] || fail "live plist missing: $src"
  plutil -lint "$src" >/dev/null 2>&1 || fail "plutil -lint failed: $src"
  plutil -p "$src" 2>/dev/null | grep -q '"ProcessType" => "Interactive"' \
    || fail "$src has no ProcessType Interactive: the live layer is not converged yet (scripts/deploy-live.sh)"
done
[ -f "$LIVE/lr_recon/band.py" ] || fail "$LIVE/lr_recon/band.py missing: the live layer is not converged yet"
echo "✓ preflight: both live plists lint and declare ProcessType Interactive"

if [ "$MODE" = dry ]; then
  for l in "${LABELS[@]}"; do echo "  would: bootout + bootstrap $l (now: spawn type $(spawn_type "$l" || true))"; done
  echo "(dry run — nothing changed. Apply with: bash $0 --confirm $CONSENT)"
  exit 0
fi

# 2. wait for a quiet reconciler: no lr-recon-act child (an actuator mid-move).
acting() { local p c; p="$(job_pid com.reso.lr-reconciler)"; [ -n "$p" ] || return 1
  for c in $(pgrep -P "$p" 2>/dev/null); do ps -o command= -p "$c" 2>/dev/null | grep -q 'lr-recon-act' && return 0; done
  return 1; }
deadline=$(( $(date +%s) + QUIET_MAX_S ))
while acting; do
  [ "$(date +%s)" -lt "$deadline" ] || fail "the reconciler was mid-act for ${QUIET_MAX_S}s; nothing reloaded, re-run later"
  sleep 5
done

# 3. reload each job.
mkdir -p "$AGENTS" "$RECON_ROOT" || fail "mkdir $AGENTS $RECON_ROOT failed"
old_recon="$(job_pid com.reso.lr-reconciler)"
for l in "${LABELS[@]}"; do
  src="$LIVE/$l.plist" dst="$AGENTS/$l.plist"
  if loaded "$l"; then
    launchctl bootout "$DOMAIN/$l" 2>/dev/null || fail "bootout $l failed"
    i=0; while loaded "$l" && [ $i -lt 40 ]; do sleep 0.5; i=$((i + 1)); done
    loaded "$l" && fail "launchd still holds $l 20 s after bootout"
  fi
  cp "$src" "$dst.tmp.$$" && mv -f "$dst.tmp.$$" "$dst" || fail "install $dst failed"
  ok=0
  for _ in 1 2 3 4 5; do
    if launchctl bootstrap "$DOMAIN" "$dst"; then ok=1; break; fi
    sleep 2
  done
  [ $ok -eq 1 ] || fail "launchctl bootstrap $DOMAIN $dst failed 5 times"
  echo "✓ bootstrapped $l from $src"
done

# 4. read back.
rc=0
for l in "${LABELS[@]}"; do
  st="$(spawn_type "$l")"
  case "$st" in
    interactive*) echo "✓ $l spawn type = $st" ;;
    *) echo "✗ $l spawn type = ${st:-unreadable} (want interactive)" >&2; rc=1 ;;
  esac
done
new_recon="" band_ok=0
end=$(( $(date +%s) + WAIT_S ))
while [ "$(date +%s)" -lt "$end" ]; do
  new_recon="$(job_pid com.reso.lr-reconciler)"
  if [ -n "$new_recon" ] && [ "$new_recon" != "$old_recon" ] \
     && grep -q "^[0-9]* pid=$new_recon pri=[0-9]* floor=31 ok\$" "$RECON_ROOT/band.log" 2>/dev/null; then
    band_ok=1; break
  fi
  sleep 2
done
for l in "${LABELS[@]}"; do
  p="$(job_pid "$l")"
  if [ -n "$p" ]; then echo "── ps -M $l (pid $p)"; ps -M -p "$p"
  else echo "── $l: no process right now (a StartInterval job between ticks); spawn type above is the read"; fi
done
if [ $band_ok -eq 1 ]; then echo "✓ band.log: $(grep "pid=$new_recon " "$RECON_ROOT/band.log" | tail -1)"
else echo "✗ no 'pid=${new_recon:-?} ... ok' line in $RECON_ROOT/band.log within ${WAIT_S}s (tail: $(tail -1 "$RECON_ROOT/band.log" 2>/dev/null))" >&2; rc=1; fi
[ $rc -eq 0 ] && echo "lr-band-reload: verdict=ok" || echo "lr-band-reload: verdict=FAILED" >&2
exit $rc
