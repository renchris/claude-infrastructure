#!/usr/bin/env bash
# lr-recon-canary.sh — the FLEET_V2 W5b REAL canaries: the lr_recon daemon, in act mode, moving a real
# throwaway Claude Code session across accounts in its own kitty window, through the real actuators.
#
#   bash tests/rig/lr-recon-canary.sh --canary 1   # cross-account idle no-prompt move
#   bash tests/rig/lr-recon-canary.sh --canary 2   # + a draft typed after confirm: UNCONFIRM, HOLD-DRAFT,
#                                                  #   the draft clears, re-plan, MOVED
#   bash tests/rig/lr-recon-canary.sh --canary 3   # + the watcher SIGKILLed after /exit: B rescues in place
#   bash tests/rig/lr-recon-canary.sh --canary 4   # + SIGKILL of the reconciler mid-cohort: adoption, no
#                                                  #   second /exit
#   bash tests/rig/lr-recon-canary.sh --teardown   # stop the canary daemon, close ONLY canary windows,
#                                                  # remove recon-canary/canary.on
#
# What is real: claude (cc-claude-bin, haiku, a fresh --session-id per canary), the accounts, the
# placement (claude-accounts --place), capacity admission, every actuator, kitty, the shared
# ~/.reso/limit-recover locks/runs/ledger the live poller also uses. What is scoped: the daemon runs
# with LR_RECON_CANARY=<every canary sid so far> and LR_RECON_ROOT=~/.reso/limit-recover/recon-canary,
# so it sees and acts on those sessions only, and its cutover switch is recon-canary/canary.on — the
# operator's recon.on / autorecover.on are never read as its switch and never written. The account
# fact that makes the session idle-eligible is written into recon-canary/facts only ("scoped canary"),
# so no other routing reads it. Pages go to /tmp/lr-canary/pages.log, never an inbox.
#
# Windows: one OS window titled lr-canary, a control window holding its active tab (so no canary pane
# is ever the focused one), one tab per canary session. Nothing here types into any other window.
# Exit: 0 every verdict check held · 1 a check failed · 2 usage/setup.
set -uo pipefail

D="${LR_CANARY_DIR:-/tmp/lr-canary}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
LR="$HOME/.reso/limit-recover"
CR="$LR/recon-canary"
KITTEN="${LR_KITTEN_BIN:-/Applications/kitty.app/Contents/MacOS/kitten}"
SRC_ACCT="${LR_CANARY_SOURCE:-next}"
SRC_CFG="$HOME/.claude-next"
MODEL="${LR_CANARY_MODEL:-claude-haiku-4-5-20251001}"
N="" TEARDOWN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --canary) N="${2:-}"; shift 2 ;;
    --teardown) TEARDOWN=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "lr-recon-canary: unknown argument $1" >&2; exit 2 ;;
  esac
done
log() { printf '[canary %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }
die() { echo "lr-recon-canary: $*" >&2; exit 2; }

mkdir -p "$D"/hook "$D"/win "$D"/work "$D"/bin || die "mkdir $D"
SOCK="$(cat "$D/sock" 2>/dev/null)"
if [ -z "$SOCK" ] || ! "$KITTEN" @ --to "$SOCK" ls >/dev/null 2>&1; then
  SOCK="$("$REPO/bin/cc-kitty-socket" 2>/dev/null | head -1)"
  [ -n "$SOCK" ] || die "no live kitty socket"
  printf '%s\n' "$SOCK" > "$D/sock"
fi

stop_daemon() {
  : > "$D/stop"
  local f pid
  for f in "$D/supervisor.pid" "$D/daemon.pid"; do
    pid="$(cat "$f" 2>/dev/null)"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done
  for _ in $(seq 1 30); do
    pid="$(cat "$D/daemon.pid" 2>/dev/null)"
    { [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; } && break
    sleep 1
  done
  rm -f "$D/stop" "$D/supervisor.pid" "$D/daemon.pid"
}

if [ "$TEARDOWN" = 1 ]; then
  stop_daemon
  rm -f "$CR/canary.on"
  if [ -s "$D/windows" ]; then
    while read -r wid; do
      [ -n "$wid" ] && "$KITTEN" @ --to "$SOCK" close-window --match "id:$wid" >/dev/null 2>&1
    done < "$D/windows"
    : > "$D/windows"
  fi
  log "torn down: daemon stopped, canary windows closed, $CR/canary.on removed"
  exit 0
fi
case "$N" in 1|2|3|4) ;; *) die "usage: --canary 1|2|3|4 | --teardown" ;; esac

# ── 1. the OS window and its control window ─────────────────────────────────────────────────────
ctl="$(cat "$D/control" 2>/dev/null)"
if [ -z "$ctl" ] || ! "$KITTEN" @ --to "$SOCK" ls --match "id:$ctl" >/dev/null 2>&1; then
  prev="$("$KITTEN" @ --to "$SOCK" ls 2>/dev/null | /usr/bin/python3 -c '
import json, sys
for ow in json.load(sys.stdin):
    for t in ow.get("tabs", []):
        for w in t.get("windows", []):
            if ow.get("is_focused") and t.get("is_focused") and w.get("is_focused"):
                print(w["id"]); sys.exit(0)' 2>/dev/null)"
  ctl="$("$KITTEN" @ --to "$SOCK" launch --type=os-window --os-window-title lr-canary --keep-focus \
         --title "lr-canary control" /usr/bin/env /bin/sleep 86400)" || die "kitty launch of the control window"
  printf '%s\n' "$ctl" > "$D/control"; printf '%s\n' "$ctl" >> "$D/windows"
  [ -n "$prev" ] && "$KITTEN" @ --to "$SOCK" focus-window --match "id:$prev" >/dev/null 2>&1
fi

# ── 2. one throwaway real session on the source account ─────────────────────────────────────────
SID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
CWD="$D/work/c$N-${SID:0:8}"
mkdir -p "$CWD" || die "mkdir $CWD"
bash "$REPO/scripts/limit-recover/lr-preseed-env.sh" "$SRC_CFG" "$CWD" >/dev/null 2>&1 || true
BIN="$("$REPO/bin/cc-claude-bin" 2>/dev/null | head -1)"
[ -x "$BIN" ] || die "cc-claude-bin resolved no claude binary"
WIN="$("$KITTEN" @ --to "$SOCK" launch --type=tab --match "id:$ctl" --keep-focus --title "lr-canary c$N" \
       --cwd "$CWD" /usr/bin/env /bin/zsh -ic \
       "CLAUDE_CONFIG_DIR=$SRC_CFG $BIN --model $MODEL --session-id $SID; exec zsh -i")" \
  || die "kitty launch of the canary session"
printf '%s\n' "$WIN" > "$D/win/$SID"; printf '%s\n' "$WIN" >> "$D/windows"; printf '%s\n' "$SID" >> "$D/sids"
log "canary $N: session $SID in kitty window $WIN on $SRC_ACCT, cwd $CWD"
python3 "$HERE/canary_lib.py" prime "$D" "$SID" || die "the canary session never came to rest"

# ── 3. the canary daemon: its own tree, act mode, every canary sid so far ────────────────────────
stop_daemon
mkdir -p "$CR" || die "mkdir $CR"
printf 'act\n' > "$CR/mode"; : > "$CR/canary.on"
python3 "$HERE/canary_lib.py" seed "$CR" "$SRC_ACCT" "$SID" "$N" || die "seed"
case "$N" in
  2) : > "$D/hook/$SID.after-confirm" ;;
  3) : > "$D/hook/$SID.before-relaunch" ;;
esac
# shellcheck disable=SC2016 # the generated notifier expands $*, not this shell
printf '#!/bin/sh\nprintf "%%s\\t%%s\\n" "$(date +%%s)" "$*" >> "%s/pages.log"\n' "$D" > "$D/bin/notify"
chmod +x "$D/bin/notify"
CANARY_SIDS="$(tr '\n' ',' < "$D/sids")"
cat > "$D/env.sh" <<EOF
export HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-}" LANG=en_US.UTF-8
export PATH="$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LR_RECON_CANARY="$CANARY_SIDS" LR_RECON_ROOT="$CR" LR_NOTIFY_BIN="$D/bin/notify"
export LR_IDLE_FANOUT=on HF_CANARY_HOOK="$HERE/lr-recon-canary-hook.sh" LR_CANARY_DIR="$D" LR_KITTEN_BIN="$KITTEN"
EOF
cat > "$D/supervisor.sh" <<EOF
#!/bin/bash
# launchd stand-in: KeepAlive with ThrottleInterval 10 for the daemon, StartInterval 30 for the watchdog
cd "$REPO/scripts/limit-recover" || exit 1
last_wd=0
while [ ! -e "$D/stop" ]; do
  /usr/bin/python3 -m lr_recon >> "$CR/reconciler.out" 2>> "$CR/reconciler.err" &
  echo \$! > "$D/daemon.pid"
  while kill -0 "\$(cat "$D/daemon.pid")" 2>/dev/null && [ ! -e "$D/stop" ]; do
    now=\$(date +%s)
    if [ \$((now - last_wd)) -ge 30 ]; then /bin/bash "$REPO/scripts/limit-recover/lr-recon-watchdog.sh" >/dev/null 2>&1; last_wd=\$now; fi
    sleep 1
  done
  wait 2>/dev/null
  [ -e "$D/stop" ] || { echo "\$(date +%s) daemon exited; restart in 10 s" >> "$D/supervisor.log"; sleep 10; }
done
EOF
# shellcheck source=/dev/null
. "$REPO/scripts/lib/detach.sh"
# shellcheck disable=SC2016 # $0/$1 are the inner shell's, on purpose
SUP="$(detach "$D/supervisor.out" /usr/bin/env -i /bin/bash -c '. "$0"; exec /bin/bash "$1"' \
       "$D/env.sh" "$D/supervisor.sh")" || die "supervisor spawn"
echo "$SUP" > "$D/supervisor.pid"
log "canary daemon supervisor pid $SUP · LR_RECON_CANARY=${CANARY_SIDS%,} · root $CR"

# ── 4. drive, then read the verdict the way the operator would ───────────────────────────────────
python3 "$HERE/canary_lib.py" drive "$D" "$CR" "$SID" "$N" "${LR_CANARY_TIMEOUT:-1200}"; drive_rc=$?
CID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("cohort_id",""))' "$CR/sessions/$SID.json" 2>/dev/null)"
echo
echo "\$ cc-lr status --cohort $CID --root $CR"
LR_RECON_CANARY="$CANARY_SIDS" "$REPO/bin/cc-lr" status --cohort "$CID" --root "$CR"
echo
python3 "$HERE/canary_lib.py" verify "$D" "$CR" "$SID" "$N"; verify_rc=$?
[ -s "$D/hook.log" ] && { echo "hook log:"; grep -F "$SID" "$D/hook.log"; }
[ -s "$D/pages.log" ] && { echo "pages (canary log, not an inbox): $(wc -l < "$D/pages.log" | tr -d ' ')"; }
[ -s "$D/supervisor.log" ] && { echo "supervisor:"; tail -3 "$D/supervisor.log"; }
stop_daemon
log "canary daemon stopped (canary.on stays until --teardown)"
[ "$drive_rc" -eq 0 ] && [ "$verify_rc" -eq 0 ] && exit 0
exit 1
