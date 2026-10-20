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
#
#   bash lr-band-reload.sh --dispatcher                 # dry run for com.claude.dispatcher
#   bash lr-band-reload.sh --confirm dispatcher-band    # reload the dispatcher only, then verify
#
# The dispatcher (wave 5: it ran ProcessType Background, PRI 4, and fired nothing from 2026-10-17)
# is a separate consent because it is a separate job with its own quiet point: it waits until no
# pass is in its actuation phase (no `cc-backlog claim` or handoff-fire descendant), installs the
# repo plist from the converged shared checkout, enables + bootstraps (enable first: a label in
# launchd's disabled DB refuses bootstrap with a bare EIO), kickstarts one pass (RunAtLoad is
# false), and verifies `spawn type = interactive` plus that pass's own dispatch-band.log line.
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

DISP_LABEL=com.claude.dispatcher
DISP_CONSENT="dispatcher-band"
DISP_SRC="${LR_BAND_DISPATCHER_PLIST:-${CC_REPO:-$HOME/Development/claude-infrastructure}/launchd/$DISP_LABEL.plist}"
DISP_BIN="${LR_BAND_DISPATCHER_BIN:-$HOME/.claude/bin/cc-dispatch}"
DISP_BAND_LOG="${LR_BAND_DISPATCHER_LOG:-$HOME/.claude/autonomy/dispatch-band.log}"

MODE=dry TARGET=rail
case "${1:-}" in
  '') ;;
  --dispatcher) TARGET=dispatcher ;;
  --confirm)
    case "${2:-}" in
      "$CONSENT")      MODE=apply ;;
      "$DISP_CONSENT") MODE=apply TARGET=dispatcher ;;
      *) echo "lr-band-reload: --confirm must name the target: --confirm $CONSENT | --confirm $DISP_CONSENT" >&2; exit 2 ;;
    esac ;;
  -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
  *) echo "lr-band-reload: unknown argument '$1' (use --confirm $CONSENT or --confirm $DISP_CONSENT)" >&2; exit 2 ;;
esac

fail() { echo "✗ $*" >&2; echo "lr-band-reload: verdict=FAILED" >&2; exit 1; }
loaded() { launchctl print "$DOMAIN/$1" >/dev/null 2>&1; }
job_pid() { launchctl print "$DOMAIN/$1" 2>/dev/null | awk '$1 == "pid" && $2 == "=" {print $3; exit}'; }
spawn_type() { launchctl print "$DOMAIN/$1" 2>/dev/null | sed -n 's/^[[:space:]]*spawn type = //p' | head -1; }
descendants() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do echo "$c"; descendants "$c"; done; }

# ── the dispatcher target ──────────────────────────────────────────────────────────────────────────
if [ "$TARGET" = dispatcher ]; then
  [ -f "$DISP_SRC" ] || fail "dispatcher plist missing: $DISP_SRC"
  plutil -lint "$DISP_SRC" >/dev/null 2>&1 || fail "plutil -lint failed: $DISP_SRC"
  case "$(plutil -p "$DISP_SRC" 2>/dev/null)" in *'"ProcessType" => "Interactive"'*) ;; *) false ;; esac \
    || fail "$DISP_SRC has no ProcessType Interactive: the shared checkout is not converged yet (scripts/deploy-live.sh)"
  grep -q 'dispatch-band.log' "$DISP_BIN" 2>/dev/null \
    || fail "$DISP_BIN has no band self-check: the live layer is not converged yet (scripts/deploy-live.sh)"
  [ -f "$LIVE/lr_recon/band.py" ] || fail "$LIVE/lr_recon/band.py missing: the live layer is not converged yet"
  echo "✓ preflight: $DISP_SRC lints and declares ProcessType Interactive; the live cc-dispatch logs its band"
  if [ "$MODE" = dry ]; then
    echo "  would: bootout + enable + bootstrap + kickstart $DISP_LABEL (now: spawn type $(spawn_type "$DISP_LABEL" || true))"
    echo "(dry run — nothing changed. Apply with: bash $0 --confirm $DISP_CONSENT)"
    exit 0
  fi
  # quiet point: no pass mid-claim or mid-fire. A pass still deciding (e.g. stuck in a rank read at
  # PRI 4) is safe to stop: cc-dispatch's TERM trap releases its singleton lock.
  disp_acting() { local p d; p="$(job_pid "$DISP_LABEL")"; [ -n "$p" ] || return 1
    for d in $(descendants "$p"); do
      case "$(ps -o command= -p "$d" 2>/dev/null)" in *'cc-backlog claim'*|*handoff-fire*) return 0 ;; esac
    done
    return 1; }
  deadline=$(( $(date +%s) + QUIET_MAX_S ))
  while disp_acting; do
    [ "$(date +%s)" -lt "$deadline" ] || fail "a dispatcher pass was claiming or firing for ${QUIET_MAX_S}s; nothing reloaded, re-run later"
    sleep 5
  done
  mkdir -p "$AGENTS" || fail "mkdir $AGENTS failed"
  dst="$AGENTS/$DISP_LABEL.plist"
  if loaded "$DISP_LABEL"; then
    launchctl bootout "$DOMAIN/$DISP_LABEL" 2>/dev/null || fail "bootout $DISP_LABEL failed"
    i=0; while loaded "$DISP_LABEL" && [ $i -lt 40 ]; do sleep 0.5; i=$((i + 1)); done
    loaded "$DISP_LABEL" && fail "launchd still holds $DISP_LABEL 20 s after bootout"
  fi
  cp "$DISP_SRC" "$dst.tmp.$$" && mv -f "$dst.tmp.$$" "$dst" || fail "install $dst failed"
  launchctl enable "$DOMAIN/$DISP_LABEL" 2>/dev/null || echo "  (enable rc=$? — continuing; bootstrap is the verdict)"
  ok=0
  for _ in 1 2 3 4 5; do
    if launchctl bootstrap "$DOMAIN" "$dst"; then ok=1; break; fi
    sleep 2
  done
  [ $ok -eq 1 ] || fail "launchctl bootstrap $DOMAIN $dst failed 5 times"
  echo "✓ bootstrapped $DISP_LABEL from $DISP_SRC"
  t0="$(date +%s)"
  launchctl kickstart "$DOMAIN/$DISP_LABEL" >/dev/null 2>&1 || echo "  (kickstart failed — waiting for the next StartInterval pass instead)"
  rc=0
  st="$(spawn_type "$DISP_LABEL")"
  case "$st" in
    interactive*) echo "✓ $DISP_LABEL spawn type = $st" ;;
    *) echo "✗ $DISP_LABEL spawn type = ${st:-unreadable} (want interactive)" >&2; rc=1 ;;
  esac
  p="$(job_pid "$DISP_LABEL")"
  if [ -n "$p" ]; then echo "── ps -M $DISP_LABEL (pid $p)"; ps -M -p "$p"; fi
  # the first pass after t0 logs its own base priority (bin/cc-dispatch band_check)
  line="" end=$(( $(date +%s) + WAIT_S ))
  while [ "$(date +%s)" -lt "$end" ]; do
    line="$(awk -v t="$t0" '$1 >= t' "$DISP_BAND_LOG" 2>/dev/null | tail -1)"
    [ -n "$line" ] && break
    sleep 2
  done
  case "$line" in
    *' floor=31 ok') echo "✓ dispatch-band.log: $line" ;;
    '') echo "✗ no dispatcher pass logged its band in $DISP_BAND_LOG within ${WAIT_S}s" >&2; rc=1 ;;
    *)  echo "✗ dispatch-band.log: $line (want floor=31 ok)" >&2; rc=1 ;;
  esac
  [ $rc -eq 0 ] && echo "lr-band-reload: verdict=ok" || echo "lr-band-reload: verdict=FAILED" >&2
  exit $rc
fi

# 1. preflight: the live layer must already carry the Interactive band (i.e. it was converged).
for l in "${LABELS[@]}"; do
  src="$LIVE/$l.plist"
  [ -f "$src" ] || fail "live plist missing: $src"
  plutil -lint "$src" >/dev/null 2>&1 || fail "plutil -lint failed: $src"
  case "$(plutil -p "$src" 2>/dev/null)" in *'"ProcessType" => "Interactive"'*) ;; *) false ;; esac \
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
  for c in $(pgrep -P "$p" 2>/dev/null); do
    case "$(ps -o command= -p "$c" 2>/dev/null)" in *lr-recon-act*) return 0 ;; esac
  done
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
