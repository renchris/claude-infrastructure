#!/usr/bin/env bash
# lr-recon-rig.sh — the FLEET_V2 W5 synthetic cohort rig: the lr_recon daemon, in act mode, against the
# REAL actuators (lr-handoff, handoff-fire, lr-transplant, lr-fire-resume, cc-tui) and a fake claude.
#
#   bash tests/rig/lr-recon-rig.sh --n 5  --faults tests/rig/faults/none.json
#   bash tests/rig/lr-recon-rig.sh --n 30 --faults tests/rig/faults/matrix30.json
#   bash tests/rig/lr-recon-rig.sh --teardown        # close the rig window, stop the rig daemon
#
# What is real and what is not. Real: the daemon (python3 -m lr_recon), every actuator it spawns, kitty
# (a dedicated OS window titled `lr-rig`, opened with --keep-focus, closed at the end), zsh at every pane
# root. Fake: `claude` (tests/rig/stub-claude.py, first on PATH and LR_CLAUDE_BIN), `claude-accounts`
# (tests/rig/fake-claude-accounts.py: --place over the rig's own facts) and `cc-notify` (logs pages).
#
# Isolation is by HOME. Everything runs with HOME=/tmp/lr-rig/home: accounts.json there names four
# throwaway config dirs (/tmp/lr-rig/cfg-{a,b,c,d}, linked in as ~/.claude-next … ~/.claude-quaternary,
# which is what the generated account map resolves), the registry and the resume-debt store are the
# rig's, and ~/.claude/{scripts,hooks,lib} link to THIS checkout. LR_STATE_DIR=/tmp/lr-rig/lr (recon.on
# lives there), LR_RECON_ROOT=/tmp/lr-rig/state. No real ~/.claude*, ~/.reso or live pane is written.
#
# The daemon is NOT a launchd job here (loading one is the operator's step): a detached supervisor
# (scripts/lib/detach.sh) plays launchd — KeepAlive with a 10 s throttle, and the watchdog every 30 s —
# and the rig daemon runs with LR_RECON_RIG=1, so it refuses every session whose registry row lacks
# rig:true. That refusal is asserted with one planted non-rig row before the cohort starts.
#
# The expected status line is derived from the fault matrix BEFORE the run (rig_lib.py expected) and
# compared with what `cc-lr status --cohort <cid> --root /tmp/lr-rig/state` prints at the end.
# Exit: 0 the line matched and the launch-log audit passed · 1 mismatch or audit failure · 2 usage/setup.
set -uo pipefail

RIG=/tmp/lr-rig
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
KITTEN="${LR_KITTEN_BIN:-/Applications/kitty.app/Contents/MacOS/kitten}"
REAL_HOME="$HOME"
# B1 of the W5 contract: argv0 must end in /claude, which only exec -a onto the framework binary keeps
PYAPP="$(/usr/bin/python3 -c 'import sys;print(sys.base_prefix)')/Resources/Python.app/Contents/MacOS/Python"
N="" FAULTS="" TIMEOUT_S="" TEARDOWN_ONLY=0 PANES_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --n) N="$2"; shift 2 ;;
    --faults) FAULTS="$2"; shift 2 ;;
    --timeout) TIMEOUT_S="$2"; shift 2 ;;
    --teardown) TEARDOWN_ONLY=1; shift ;;
    --panes-only) PANES_ONLY=1; shift ;;   # debug: build HOME + panes, start nothing, keep it up
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "lr-recon-rig: unknown argument $1" >&2; exit 2 ;;
  esac
done

log() { printf '[rig %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "lr-recon-rig: $*" >&2; exit 2; }
write_env() { # the environment every rig process runs under (daemon, stubs, actuators, supervisor)
  cat > "$RIG/env.sh" <<EOF
export HOME="$RIG/home" USER="${USER:-rig}" LOGNAME="${LOGNAME:-rig}" TERM="${TERM:-xterm-256color}"
export PATH="$RIG/bin:$RIG/home/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8 TMPDIR="$RIG/tmp/" LR_RIG="$RIG" LR_RIG_SPECS="$RIG/specs"
export LR_STATE_DIR="$RIG/lr" LR_RECON_ROOT="$RIG/state" LR_RECON_RIG=1
export LR_CLAUDE_BIN="$RIG/bin/claude" LR_ACCOUNTS_BIN="$RIG/bin/claude-accounts"
export CC_TERM_KITTY_TO="$SOCK" LR_KITTEN_BIN="$KITTEN" LR_IDLE_FANOUT="${IDLE_FANOUT:-off}"
export LR_RECON_CLOCK_SKEW_FILE="$RIG/state/clock-skew" CC_RESUME_DEBT_DIR="$RIG/home/.claude/autonomy/resume-debt"
export LR_PRESEED_DONE=1 LR_RIG_PYAPP="$PYAPP" CC_KITTY_CONF="$REAL_HOME/.config/kitty/kitty.conf"
export CC_TERM_KITTY_PID="${SOCK##*-}" DISABLE_AUTOUPDATER=1 CC_TERM=kitty
EOF
}
rigenv() { env -i /bin/bash -c '. "$0"; exec "$@"' "$RIG/env.sh" "$@"; }

# ── teardown (also the first act of every run: a previous rig never leaks into this one) ────────────
teardown() {
  [ -d "$RIG" ] || return 0
  touch "$RIG/stop" 2>/dev/null
  local pid
  for f in "$RIG/supervisor.pid" "$RIG/state/daemon.pid"; do
    pid="$(cat "$f" 2>/dev/null)"; [ -n "$pid" ] && kill -CONT "$pid" 2>/dev/null && kill "$pid" 2>/dev/null
  done
  if [ -s "$RIG/windows" ] && [ -n "${SOCK:-}" ]; then
    while read -r wid; do
      [ -n "$wid" ] && "$KITTEN" @ --to "$SOCK" close-window --match "id:$wid" >/dev/null 2>&1
    done < "$RIG/windows"
  fi
  # a window the daemon's R path opened is also in the rig OS window: close by its title
  [ -n "${SOCK:-}" ] && "$KITTEN" @ --to "$SOCK" close-window --match "title:^lr-rig" >/dev/null 2>&1
  # the R path opens a NEW os-window in the rig's cwd: only rig windows ever run under /tmp/lr-rig
  [ -n "${SOCK:-}" ] && "$KITTEN" @ --to "$SOCK" close-window --match "cwd:^(/private)?/tmp/lr-rig/" >/dev/null 2>&1
  pkill -f "$RIG/bin/claude" 2>/dev/null
  return 0
}

SOCK="${CC_TERM_KITTY_TO:-}"
[ -n "$SOCK" ] || SOCK="$("$REPO/bin/cc-kitty-socket" 2>/dev/null | head -1)"
[ -n "$SOCK" ] || die "no live kitty socket (cc-kitty-socket found none)"
if [ "$TEARDOWN_ONLY" -eq 1 ]; then teardown; log "torn down"; exit 0; fi
[ -n "$N" ] && [ -f "$FAULTS" ] || die "usage: --n 5|30 --faults FILE"

teardown
case "$RIG" in /tmp/lr-rig) rm -rf /tmp/lr-rig ;; *) die "refusing to clear $RIG" ;; esac
mkdir -p "$RIG"/{bin,specs,work,tmp,lr,state,home/.claude/bin} || die "mkdir $RIG"

# ── 1. the rig HOME ───────────────────────────────────────────────────────────────────────────────
python3 "$HERE/rig_lib.py" home "$RIG" || die "rig home"
IDLE_FANOUT="$(python3 -c 'import json,sys;print("on" if json.load(open(sys.argv[1])).get("idle_fanout") else "off")' "$FAULTS")"
write_env
for d in scripts hooks lib model-config.yaml; do ln -s "$REPO/$d" "$RIG/home/.claude/$d"; done
mkdir -p "$RIG/home/bin" "$RIG/home/.claude/autonomy/resume-debt" "$RIG/home/.reso/bin"
ln -s "$REPO/bin/reso-resume-one" "$RIG/home/.reso/bin/reso-resume-one"   # the R path's launcher
for b in "$REPO"/bin/*; do ln -s "$b" "$RIG/home/.claude/bin/$(basename "$b")"; done
ln -sf "$REPO/bin/it2-wrapper" "$RIG/home/.claude/bin/it2"   # install.sh installs it under this name
ln -sf "$HERE/claude" "$RIG/bin/claude"
ln -sf "$HERE/fake-claude-accounts.py" "$RIG/bin/claude-accounts"
ln -sf "$HERE/fake-claude-accounts.py" "$RIG/home/.claude/bin/claude-accounts"
ln -sf "$HERE/fake-claude-accounts.py" "$RIG/home/bin/claude-accounts"   # LRH:619 reads $HOME/bin
printf '#!/bin/sh\nprintf "%%s\\t%%s\\n" "$(date +%%s)" "$*" >> "%s/pages.log"\n' "$RIG/state" > "$RIG/bin/cc-notify"
chmod +x "$RIG/bin/cc-notify"; ln -sf "$RIG/bin/cc-notify" "$RIG/home/.claude/bin/cc-notify"
cat > "$RIG/home/.zshrc" <<EOF
export PATH="$RIG/bin:$RIG/home/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
PS1='rig%% '
unsetopt BEEP
# the pane address every screen read needs (contract C60): the operator's zshrc makes it, ours must
export CC_PANE_ID="\$KITTY_WINDOW_ID" ITERM_SESSION_ID="w0t0p0:\$KITTY_WINDOW_ID"
EOF

N_SPECS="$(python3 "$HERE/rig_lib.py" expand "$FAULTS" "$RIG/specs.json")" || die "expand $FAULTS"
[ "$N_SPECS" = "$N" ] || die "--n $N but $FAULTS expands to $N_SPECS sessions"
EXPECTED="$(python3 "$HERE/rig_lib.py" expected "$FAULTS")"
printf '%s\n' "$EXPECTED" > "$RIG/expected.line"
log "expected (derived from $(basename "$FAULTS") before the run): $EXPECTED"
python3 - "$RIG" <<'PY' || die "specs"
import json, os, sys
rig = sys.argv[1]
for s in json.load(open(os.path.join(rig, "specs.json"))):
    json.dump(s, open(os.path.join(rig, "specs", s["sid"] + ".json"), "w"))
    os.makedirs(os.path.join(rig, "work", "s%02d" % s["n"]), exist_ok=True)
PY

# ── 2. panes: one tab per session in one OS window titled lr-rig ──────────────────────────────────
: > "$RIG/windows"
# A control window owns the OS window's active tab, so no session pane is ever the focused one
# (a focused LIMITED pane is HOLD-FOCUS by the safe default, decision 7).
first="$("$KITTEN" @ --to "$SOCK" launch --type=os-window --os-window-title lr-rig --keep-focus \
        --title "lr-rig control" /usr/bin/env /bin/sleep 86400)" || die "kitty launch of the control window"
echo "$first" >> "$RIG/windows"
while IFS=$'\t' read -r n sid stale; do
  cwd="$RIG/work/s$(printf %02d "$n")"
  if [ "$stale" = True ]; then # the dead session: a transcript and a request, never a process
    rigenv "$RIG/bin/claude" --rig-write-dead "$sid" --rig-cwd "$cwd" || die "dead session $sid"
    continue
  fi
  where=(--type=tab --match "id:$first")
  wid="$("$KITTEN" @ --to "$SOCK" launch "${where[@]}" --keep-focus --title "lr-rig s$n" \
        --cwd "$cwd" --env ZDOTDIR="$RIG/home" --env CLAUDE_CONFIG_DIR="$RIG/home/.claude-next" \
        /usr/bin/env /bin/zsh -f -c "for v in \${(k)parameters[(I)CLAUDE*]} \${(k)parameters[(I)ANTHROPIC*]} ITERM_SESSION_ID CC_PANE_ID; do unset \$v; done; . $RIG/env.sh; export ZDOTDIR=$RIG/home CLAUDE_CONFIG_DIR=$RIG/home/.claude-next; cd $cwd && exec zsh -ic 'claude --session-id $sid; exec zsh -i'")" \
    || die "kitty launch for s$n"
  echo "$wid" >> "$RIG/windows"
done < <(python3 -c 'import json,sys
for s in json.load(open(sys.argv[1])): print("%d\t%s\t%s" % (s["n"], s["sid"], s["stale_request"]))' "$RIG/specs.json")
log "opened $(wc -l < "$RIG/windows" | tr -d ' ') rig panes on $SOCK"

# every live stub reaches its starting state (limit death written, or idle at rest) before anything
t0=$(date +%s)
until python3 "$HERE/rig_lib.py" booted "$RIG"; do
  [ $(( $(date +%s) - t0 )) -lt 90 ] || { teardown; die "stubs did not boot within 90 s"; }
  sleep 1
done

[ "$PANES_ONLY" -eq 1 ] && { log "panes only: $RIG is up; source $RIG/env.sh to drive it"; exit 0; }

# ── 3. the refusal: a planted non-rig registry row must never become a record ────────────────────
python3 "$HERE/rig_lib.py" plant-foreign "$RIG" || die "plant foreign row"
python3 "$HERE/rig_lib.py" plant-faults "$RIG" || die "plant legacy holders / stale requests"

# ── 4. cut over UNDER THE RIG ROOT ONLY, start the supervisor (launchd stand-in) ──────────────────
printf 'act\n' > "$RIG/state/mode"; : > "$RIG/lr/recon.on"
# A matrix with idle sessions exercises the idle fan-out, which is OFF by default twice over
# (LR_IDLE_FANOUT, and fan-out-origin records are PLAN-ONLY without autorecover.on). The rig turns
# both on for ITS OWN root only; the real ~/.reso/limit-recover is never touched.
[ "$IDLE_FANOUT" = on ] && : > "$RIG/lr/autorecover.on"
cat > "$RIG/supervisor.sh" <<EOF
#!/bin/bash
# KeepAlive + ThrottleInterval 10 for the daemon, StartInterval 30 for the watchdog.
cd "$REPO/scripts/limit-recover" || exit 1
last_wd=0
while [ ! -e "$RIG/stop" ]; do
  /usr/bin/python3 -m lr_recon >> "$RIG/state/reconciler.out" 2>> "$RIG/state/reconciler.err" &
  echo \$! > "$RIG/state/daemon.pid"
  while kill -0 "\$(cat "$RIG/state/daemon.pid")" 2>/dev/null && [ ! -e "$RIG/stop" ]; do
    now=\$(date +%s)
    if [ \$((now - last_wd)) -ge 30 ]; then /bin/bash "$REPO/scripts/limit-recover/lr-recon-watchdog.sh" >/dev/null 2>&1; last_wd=\$now; fi
    sleep 1
  done
  wait 2>/dev/null
  [ -e "$RIG/stop" ] || { echo "\$(date +%s) daemon exited; restart in 10 s" >> "$RIG/state/supervisor.log"; sleep 10; }
done
EOF
. "$REPO/scripts/lib/detach.sh"
SUP="$(detach "$RIG/state/supervisor.out" /usr/bin/env -i /bin/bash -c '. "$0"; exec /bin/bash "$1"' \
       "$RIG/env.sh" "$RIG/supervisor.sh")" || die "supervisor spawn"
echo "$SUP" > "$RIG/supervisor.pid"
log "rig daemon supervisor pid $SUP (recon.on + mode=act under $RIG only)"

# ── 4b. the operator's verb: while the reconciler is live, cc-lr QUEUES cc-lr-origin requests ─────
# (census-origin records stay PLAN-ONLY without autorecover.on, which the rig never creates.)
t0=$(date +%s)
until [ -n "$(find "$RIG/state/heartbeat" -newermt "-15 seconds" 2>/dev/null)" ]; do
  [ $(( $(date +%s) - t0 )) -lt 60 ] || { teardown; die "the rig daemon wrote no heartbeat within 60 s"; }
  sleep 1
done
SRC="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("source","next"))' "$FAULTS")"
rigenv "$REPO/bin/cc-lr" recover --limited --account "$SRC" > "$RIG/state/cc-lr-recover.log" 2>&1
log "cc-lr recover --limited --account $SRC → rc $? · $(ls "$RIG/lr/requests" 2>/dev/null | grep -c 'cc-lr.json') cc-lr request(s) queued"

# ── 5. drive: daemon faults at their moment, then wait for the cohort to settle ─────────────────
[ -n "$TIMEOUT_S" ] || { [ "$N" -le 5 ] && TIMEOUT_S=900 || TIMEOUT_S=2700; }
python3 "$HERE/rig_lib.py" drive "$RIG" "$TIMEOUT_S"; drive_rc=$?

# ── 6. read the result the way the operator would, then audit ─────────────────────────────────────
CID="$(python3 "$HERE/rig_lib.py" cohort "$RIG")"
echo
echo "\$ cc-lr status --cohort $CID --root $RIG/state"
STATUS="$(rigenv "$REPO/bin/cc-lr" status --cohort "$CID" --root "$RIG/state")"
printf '%s\n' "$STATUS"
GOT="$(printf '%s\n' "$STATUS" | sed -n 's/^DoD: //p' | head -1)"
echo
python3 "$HERE/rig_lib.py" audit "$RIG/state" "$RIG/specs.json" "$RIG/home"; audit_rc=$?
python3 "$HERE/rig_lib.py" refusal "$RIG"; refusal_rc=$?
echo
if [ "$GOT" = "$EXPECTED" ]; then log "DoD line MATCHES the matrix-derived expectation"; line_rc=0
else log "DoD line MISMATCH"; echo "  expected: $EXPECTED"; echo "  got:      $GOT"; line_rc=1; fi
[ "${LR_RIG_KEEP:-0}" = 1 ] || teardown
[ $line_rc -eq 0 ] && [ $audit_rc -eq 0 ] && [ $refusal_rc -eq 0 ] && [ $drive_rc -eq 0 ] && exit 0
exit 1
