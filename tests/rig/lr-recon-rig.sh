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
#
# Safety (B1 review S1-S4, S9). LR_RIG_ROOT moves the root (the load harness passes one per arm,
# /tmp/lrh-<id>-cure|red); only /tmp/lr-rig and that exact shape are ever created or cleared, never a
# path with `..`. Every kill by pidfile is by verified identity (pid, lstart, argv; rig_lib.py
# kill-verified), because pids here advance ~800/s and a stale pidfile names somebody else within
# minutes. `launchctl` and `osascript` are logging no-ops first on the rig PATH (tests/rig/shims), so
# the cc-lr path can never kickstart the real poller. Each rig OS window has one tab: a control window
# and at most 2 members, which leaves room for a successor in the source's own OS window (placement
# rule 1); a sampler aborts the run if a rig pane ever shares an OS window with a non-rig one.
# A matrix with "go_barrier": true boots every member alive and kills it at $RIG/go + die_at_s; the
# cc-lr request runs only on the legacy path (LR_RIG_REQUEST=cc-lr, the default without go_barrier).
# Exit: 0 the line matched and the launch-log audit passed · 1 mismatch or audit failure · 2 usage/setup
# · 3 NO-VERDICT containment (a rig pane sat in a non-rig OS window; the run proves nothing either way).
set -uo pipefail

RIG="${LR_RIG_ROOT:-/tmp/lr-rig}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
KITTEN="${LR_KITTEN_BIN:-/Applications/kitty.app/Contents/MacOS/kitten}"
KITTY_REAL="${LR_RIG_REAL_KITTY:-/Applications/kitty.app/Contents/MacOS/kitty}"
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
# S9: a case pattern's `*` matches `/`, so `/tmp/lrh-a-red/../../Users/x` passed the old glob. The root
# is exactly /tmp/lr-rig or matches a regex anchored at both ends, and never contains `..`. This runs
# before anything is created, cleared or closed.
rig_root_ok() {
  local re='^/tmp/lrh-[0-9A-Za-z]+-(cure|red)$'
  case "$1" in *..*) return 1 ;; esac
  [ "$1" = /tmp/lr-rig ] || [[ $1 =~ $re ]]
}
rig_root_ok "$RIG" || die "refusing root $RIG (only /tmp/lr-rig or /tmp/lrh-<id>-cure|red, never ..)"
RIG_TAG="$(basename "$RIG")"   # window titles and teardown matches are per root
write_env() { # the environment every rig process runs under (daemon, stubs, actuators, supervisor)
  cat > "$RIG/env.sh" <<EOF
export HOME="$RIG/home" USER="${USER:-rig}" LOGNAME="${LOGNAME:-rig}" TERM="${TERM:-xterm-256color}"
export PATH="$RIG/bin:$RIG/home/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8 TMPDIR="$RIG/tmp/" LR_RIG="$RIG" LR_RIG_SPECS="$RIG/specs"
export LR_STATE_DIR="$RIG/lr" LR_RECON_ROOT="$RIG/state" LR_RECON_RIG=1
export LR_CLAUDE_BIN="$RIG/bin/claude" LR_ACCOUNTS_BIN="$RIG/bin/claude-accounts" CC_RESUME_CLAUDE_BIN="$RIG/bin/claude"
export CC_TERM_KITTY_TO="$SOCK" LR_KITTEN_BIN="$KITTEN" LR_IDLE_FANOUT="${IDLE_FANOUT:-off}"
export LR_RECON_CLOCK_SKEW_FILE="$RIG/state/clock-skew" CC_RESUME_DEBT_DIR="$RIG/home/.claude/autonomy/resume-debt"
export LR_PRESEED_DONE=1 LR_RIG_PYAPP="$PYAPP" CC_KITTY_CONF="$REAL_HOME/.config/kitty/kitty.conf"
export CC_TERM_KITTY_PID="${SOCK##*-}" DISABLE_AUTOUPDATER=1 CC_TERM=kitty
export LR_RIG_TAG="$RIG_TAG" LR_RIG_REAL_KITTY="$KITTY_REAL" CC_LR_POLLER_LABEL=rig.invalid
EOF
}
# S2: never `kill $(cat pidfile)`. rig_lib checks the recorded (pid, lstart) and the argv first.
killv() { /usr/bin/python3 "$HERE/rig_lib.py" kill-verified "$RIG" "$1" "${2:-TERM}"; }
record_id() { /usr/bin/python3 "$HERE/rig_lib.py" record-id "$1" "${2:-}"; }
# shellcheck disable=SC2016 # $0/$@ are the inner shell's, on purpose
rigenv() { env -i /bin/bash -c '. "$0"; exec "$@"' "$RIG/env.sh" "$@"; }

# ── teardown (also the first act of every run: a previous rig never leaks into this one) ────────────
teardown() {
  [ -d "$RIG" ] || return 0
  touch "$RIG/stop" 2>/dev/null
  local f
  # S3: processes first, by verified identity, so no live actuator opens a window after the windows
  # are closed. The pidfiles (supervisor, daemon, the planted sleeps) carry a recorded lstart; the
  # sweep takes every other process whose argv names this root or that runs under its env.
  for f in "$RIG/supervisor.pid" "$RIG/state/daemon.pid" "$RIG"/*.pid; do
    [ -e "$f" ] && killv "$f" CONT,TERM
  done
  /usr/bin/python3 "$HERE/rig_lib.py" sweep "$RIG" TERM >/dev/null
  if [ -s "$RIG/windows" ] && [ -n "${SOCK:-}" ]; then
    while read -r wid; do
      [ -n "$wid" ] && "$KITTEN" @ --to "$SOCK" close-window --match "id:$wid" >/dev/null 2>&1
    done < "$RIG/windows"
  fi
  # a window the daemon's R path opened carries this root's title or cwd: close by both, per root
  [ -n "${SOCK:-}" ] && "$KITTEN" @ --to "$SOCK" close-window --match "title:^${RIG_TAG}( |\$)" >/dev/null 2>&1
  [ -n "${SOCK:-}" ] && "$KITTEN" @ --to "$SOCK" close-window --match "cwd:^(/private)?${RIG}/" >/dev/null 2>&1
  return 0
}
# S3: an R window can open late, after the first pass. Sweep again ~30 s on and list what survived.
late_sweep() {
  [ -d "$RIG" ] || return 0
  sleep 30
  /usr/bin/python3 "$HERE/rig_lib.py" sweep "$RIG" KILL "$RIG/rig-result.json" >/dev/null
  [ -n "${SOCK:-}" ] && "$KITTEN" @ --to "$SOCK" close-window --match "cwd:^(/private)?${RIG}/" >/dev/null 2>&1
  return 0
}

SOCK="${CC_TERM_KITTY_TO:-}"
[ -n "$SOCK" ] || SOCK="$("$REPO/bin/cc-kitty-socket" 2>/dev/null | head -1)"
[ -n "$SOCK" ] || die "no live kitty socket (cc-kitty-socket found none)"
if [ "$TEARDOWN_ONLY" -eq 1 ]; then teardown; log "torn down"; exit 0; fi
[ -n "$N" ] && [ -f "$FAULTS" ] || die "usage: --n 5|30 --faults FILE"

teardown
rig_root_ok "$RIG" && rm -rf -- "${RIG:?}"   # re-checked at the point of use (S9)
mkdir -p "$RIG"/{bin,specs,work,tmp,lr,state,home/.claude/bin} || die "mkdir $RIG"
# S4: launchctl and osascript resolve to logging no-ops before any real one on the rig PATH
for s in launchctl osascript; do ln -sf "$HERE/shims/$s" "$RIG/bin/$s"; done
: > "$RIG/started"   # the mtime the real-HOME check below compares against

# ── 1. the rig HOME ───────────────────────────────────────────────────────────────────────────────
python3 "$HERE/rig_lib.py" home "$RIG" || die "rig home"
IDLE_FANOUT="$(python3 -c 'import json,sys;print("on" if json.load(open(sys.argv[1])).get("idle_fanout") else "off")' "$FAULTS")"
write_env
for d in scripts hooks lib model-config.yaml; do ln -s "$REPO/$d" "$RIG/home/.claude/$d"; done
mkdir -p "$RIG/home/bin" "$RIG/home/.claude/autonomy/resume-debt" "$RIG/home/.reso/bin"
# The R path's launcher. The R window is created by `kitty @ launch` from KITTY's environment (the
# operator's HOME, zshrc and PATH), never the daemon's, so an unwrapped engine gated against the real
# ~/.claude budget and would have resumed on the real claude and a real config dir (W5 N=30,
# pane-closed-after-exit). The wrapper re-enters the rig before the engine runs.
cat > "$RIG/home/.reso/bin/reso-resume-one" <<EOF
#!/bin/bash
for v in \$(compgen -e | grep -E '^(CLAUDE|ANTHROPIC)'); do unset "\$v"; done
. "$RIG/env.sh"
export ZDOTDIR="$RIG/home" CC_PANE_ID="\${KITTY_WINDOW_ID:-}" ITERM_SESSION_ID="w0t0p0:\${KITTY_WINDOW_ID:-}"
exec "$REPO/bin/reso-resume-one" "\$@"
EOF
chmod +x "$RIG/home/.reso/bin/reso-resume-one"
for b in "$REPO"/bin/*; do ln -s "$b" "$RIG/home/.claude/bin/$(basename "$b")"; done
ln -sf "$REPO/bin/it2-wrapper" "$RIG/home/.claude/bin/it2"   # install.sh installs it under this name
ln -sf "$HERE/claude" "$RIG/bin/claude"
ln -sf "$HERE/fake-claude-accounts.py" "$RIG/bin/claude-accounts"
ln -sf "$HERE/fake-claude-accounts.py" "$RIG/home/.claude/bin/claude-accounts"
ln -sf "$HERE/fake-claude-accounts.py" "$RIG/home/bin/claude-accounts"   # LRH:619 reads $HOME/bin
# shellcheck disable=SC2016 # the generated stub expands these, not this shell
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

# ── 2. panes: OS windows titled $RIG_TAG, one tab each, a control window plus ≤2 members ──────────
: > "$RIG/windows"
# B1 review S1: placement rule 2 scans EVERY kitty OS window for room (pane-placement.sh), so a rig
# whose own window is full puts a successor into the operator's fullest window. One tab and at most
# 3 panes per rig OS window keeps rule 1 (room in the source's own window) true for every member.
# A control window owns each OS window's active window, so no session pane is ever the focused one
# (decision 7, ruled 2026-09-30, moves a focused LIMITED pane by default; the rig keeps every
# session pane unfocused so it never types beside the operator. LR_MOVE_FOCUSED=off holds instead).
# --keep-focus does not stop a NEW OS window taking focus (measured in the W5 rig), so the window the
# operator had focused is read first and handed back once the rig window exists.
prev_focus="$("$KITTEN" @ --to "$SOCK" ls 2>/dev/null | /usr/bin/python3 -c '
import json, sys
for ow in json.load(sys.stdin):
    for t in ow.get("tabs", []):
        for w in t.get("windows", []):
            if ow.get("is_focused") and t.get("is_focused") and w.get("is_focused"):
                print(w["id"]); sys.exit(0)' 2>/dev/null)"
MEMBERS_PER_OS_WINDOW=2
first="" in_win=0
open_os_window() { # a new rig OS window with its control window, cwd under the root (containment)
  first="$("$KITTEN" @ --to "$SOCK" launch --type=os-window --os-window-title "$RIG_TAG" --keep-focus \
          --cwd "$RIG/work" --title "$RIG_TAG control" /usr/bin/env /bin/sleep 86400)" \
    || die "kitty launch of a control window"
  echo "$first" >> "$RIG/windows"
  [ -n "$prev_focus" ] && "$KITTEN" @ --to "$SOCK" focus-window --match "id:$prev_focus" >/dev/null 2>&1
  in_win=0
}
while IFS=$'\t' read -r n sid stale; do
  cwd="$RIG/work/s$(printf %02d "$n")"
  if [ "$stale" = True ]; then # the dead session: a transcript and a request, never a process
    rigenv "$RIG/bin/claude" --rig-write-dead "$sid" --rig-cwd "$cwd" || die "dead session $sid"
    continue
  fi
  { [ -z "$first" ] || [ "$in_win" -ge "$MEMBERS_PER_OS_WINDOW" ]; } && open_os_window
  in_win=$((in_win + 1))
  where=(--type=window --location=vsplit --match "window_id:$first")   # a TAB match: the tab holding $first
  wid="$("$KITTEN" @ --to "$SOCK" launch "${where[@]}" --keep-focus --title "$RIG_TAG s$n" \
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
# D1.9: the reconciler acts on a record nobody asked for only with its OWN zero-human marker too.
# A go_barrier matrix has no cc-lr request, so its records are census-origin: it mirrors production,
# where both markers exist (B1 §6.3; LR_RIG_AUTORECOVER=off turns that off).
GO_BARRIER="$(python3 -c 'import json,sys;print("on" if json.load(open(sys.argv[1])).get("go_barrier") else "off")' "$FAULTS")"
AUTORECOVER="${LR_RIG_AUTORECOVER:-$GO_BARRIER}"
{ [ "$IDLE_FANOUT" = on ] || [ "$AUTORECOVER" = on ]; } && : > "$RIG/lr/autorecover.on" && : > "$RIG/state/autorecover.on"
[ -n "$TIMEOUT_S" ] || { [ "$N" -le 5 ] && TIMEOUT_S=900 || TIMEOUT_S=2700; }
# S3: a per-arm deadman. The supervisor stops the daemon and exits once $RIG/deadline has passed, or
# once its owner (this script, unless LR_RIG_KEEP=1; or LR_RIG_OWNER_PID/LSTART, the harness) is gone,
# so a rig whose driver died never keeps polling the main kitty.
echo $(( $(date +%s) + TIMEOUT_S + 1800 )) > "$RIG/deadline"
OWNER_PID="${LR_RIG_OWNER_PID:-}" OWNER_LSTART="${LR_RIG_OWNER_LSTART:-}"
if [ -z "$OWNER_PID" ] && [ "${LR_RIG_KEEP:-0}" != 1 ]; then OWNER_PID=$$; fi
if [ -n "$OWNER_PID" ] && [ -z "$OWNER_LSTART" ]; then OWNER_LSTART="$(ps -o lstart= -p "$OWNER_PID" | xargs)"; fi
cat > "$RIG/supervisor.sh" <<EOF
#!/bin/bash
# KeepAlive + ThrottleInterval 10 for the daemon, StartInterval 30 for the watchdog.
cd "$REPO/scripts/limit-recover" || exit 1
last_wd=0
deadman() { # 0 = this arm must stop now
  [ "\$(date +%s)" -ge "\$(cat "$RIG/deadline" 2>/dev/null || echo 0)" ] && return 0
  [ -n "$OWNER_PID" ] && [ "\$(ps -o lstart= -p "$OWNER_PID" 2>/dev/null | xargs)" != "$OWNER_LSTART" ] && return 0
  return 1
}
while [ ! -e "$RIG/stop" ]; do
  /usr/bin/python3 -m lr_recon >> "$RIG/state/reconciler.out" 2>> "$RIG/state/reconciler.err" &
  dpid=\$!
  echo "\$dpid" > "$RIG/state/daemon.pid"
  /usr/bin/python3 "$HERE/rig_lib.py" record-id "$RIG/state/daemon.pid"
  while kill -0 "\$dpid" 2>/dev/null && [ ! -e "$RIG/stop" ]; do
    now=\$(date +%s)
    if [ \$((now - last_wd)) -ge 30 ]; then
      /bin/bash "$REPO/scripts/limit-recover/lr-recon-watchdog.sh" >/dev/null 2>&1; last_wd=\$now
      # our own unreaped child, so its pid cannot have been reused: a plain kill is exact here
      if deadman; then echo "\$now deadman: deadline or owner gone" >> "$RIG/state/supervisor.log"; : > "$RIG/stop"; kill "\$dpid" 2>/dev/null; fi
    fi
    sleep 1
  done
  wait 2>/dev/null
  [ -e "$RIG/stop" ] || { echo "\$(date +%s) daemon exited; restart in 10 s" >> "$RIG/state/supervisor.log"; sleep 10; }
done
EOF
# shellcheck source=/dev/null
. "$REPO/scripts/lib/detach.sh"
# shellcheck disable=SC2016 # $0/$1 are the inner shell's, on purpose
SUP="$(detach "$RIG/state/supervisor.out" /usr/bin/env -i /bin/bash -c '. "$0"; exec /bin/bash "$1"' \
       "$RIG/env.sh" "$RIG/supervisor.sh")" || die "supervisor spawn"
echo "$SUP" > "$RIG/supervisor.pid"
record_id "$RIG/supervisor.pid" || die "supervisor $SUP gone before its identity was recorded"
log "rig daemon supervisor pid $SUP (recon.on + mode=act under $RIG only)"

# ── 4b. the operator's verb: while the reconciler is live, cc-lr QUEUES cc-lr-origin requests ─────
# (census-origin records stay PLAN-ONLY without autorecover.on, which only idle fan-out and
# go_barrier matrices create.)
t0=$(date +%s)
until [ -n "$(find "$RIG/state/heartbeat" -newermt "-15 seconds" 2>/dev/null)" ]; do
  [ $(( $(date +%s) - t0 )) -lt 60 ] || { teardown; die "the rig daemon wrote no heartbeat within 60 s"; }
  sleep 1
done
SRC="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("source","next"))' "$FAULTS")"
# go_barrier: every member is alive until now; each dies at go + its die_at_s, so detection is the
# daemon's own (the clock starts at death). The legacy path dies at boot and is driven by cc-lr.
[ "$GO_BARRIER" = on ] && : > "$RIG/go" && log "go: members die at go + die_at_s"
REQUEST="${LR_RIG_REQUEST:-}"
[ -n "$REQUEST" ] || { [ "$GO_BARRIER" = on ] && REQUEST=none || REQUEST=cc-lr; }
if [ "$REQUEST" = cc-lr ]; then
  rigenv "$REPO/bin/cc-lr" recover --limited --account "$SRC" > "$RIG/state/cc-lr-recover.log" 2>&1
  recover_rc=$? nq=0
  for f in "$RIG"/lr/requests/*cc-lr.json; do [ -e "$f" ] && nq=$((nq + 1)); done
  log "cc-lr recover --limited --account $SRC → rc $recover_rc · $nq cc-lr request(s) queued"
else
  log "no cc-lr request (LR_RIG_REQUEST=$REQUEST): the daemon detects on its own"
fi

# ── 5. drive: daemon faults at their moment, then wait for the cohort to settle ─────────────────
# S1 containment sampler: every 5 s while the drive runs; a hit is NO-VERDICT, never PASS or FAIL
(
  while [ ! -e "$RIG/drive.done" ] && [ ! -e "$RIG/stop" ]; do
    hits="$("$KITTEN" @ --to "$SOCK" ls 2>/dev/null | /usr/bin/python3 "$HERE/rig_lib.py" containment "$RIG")"
    [ -n "$hits" ] && { printf '%s\t%s\n' "$(date +%s)" "$hits" >> "$RIG/state/containment.hit"; exit 0; }
    sleep 5
  done
) &
SAMPLER=$!
python3 "$HERE/rig_lib.py" drive "$RIG" "$TIMEOUT_S"; drive_rc=$?
: > "$RIG/drive.done"; kill "$SAMPLER" 2>/dev/null; wait "$SAMPLER" 2>/dev/null
if [ "$drive_rc" -eq 3 ]; then
  /usr/bin/python3 "$HERE/rig_lib.py" result "$RIG" verdict="NO-VERDICT containment" drive_rc=3 \
    "containment=$(head -1 "$RIG/state/containment.hit" | cut -f2-)"
  teardown; late_sweep
  log "NO-VERDICT containment: $(head -1 "$RIG/state/containment.hit")"
  exit 3
fi

# ── 6. read the result the way the operator would, then audit ─────────────────────────────────────
CID="$(python3 "$HERE/rig_lib.py" cohort "$RIG")"
echo
echo "\$ cc-lr status --cohort $CID --root $RIG/state"
STATUS="$(rigenv "$REPO/bin/cc-lr" status --cohort "$CID" --root "$RIG/state")"
printf '%s\n' "$STATUS"
GOT="$(printf '%s\n' "$STATUS" | sed -n 's/^DoD: //p' | head -1)"
python3 "$HERE/rig_lib.py" timings "$RIG"
echo
python3 "$HERE/rig_lib.py" audit "$RIG/state" "$RIG/specs.json" "$RIG/home"; audit_rc=$?
python3 "$HERE/rig_lib.py" refusal "$RIG"; refusal_rc=$?
# The header's promise, checked: nothing the rig runs may write the real capacity-admit store. Report
# only — a real session elsewhere on the box may legitimately write it during the run.
real_w="$(find "$REAL_HOME/.claude/autonomy/capacity-admit" -maxdepth 1 -name '*.refusals' -newer "$RIG/started" 2>/dev/null | tr '\n' ' ')"
echo "real-HOME capacity-admit writes during the run: ${real_w:-none}"
# S4: what the shims swallowed (a kickstart here would have reached the real poller)
echo "launchctl/osascript shim calls: $(wc -l < "$RIG/state/shims.log" 2>/dev/null | tr -d ' ' || echo 0) ($RIG/state/shims.log)"
echo
# B1 review C10: the line's fixed 120 s p95 term reads the box's band at 15-40/core, not the code.
# The verdict compares the line WITHOUT it; the p95 is reported beside it (and in `timings` above).
nop95() { printf '%s\n' "$1" | sed 's/ · p95 detect→engaged .*$//'; }
P95_TERM="$(printf '%s\n' "$GOT" | sed -n 's/^.* · \(p95 detect→engaged .*\)$/\1/p')"
if [ "$(nop95 "$GOT")" = "$(nop95 "$EXPECTED")" ]; then
  log "DoD line MATCHES the matrix-derived expectation (p95 term reported, not judged: ${P95_TERM:-none})"; line_rc=0
else log "DoD line MISMATCH"; echo "  expected: $EXPECTED"; echo "  got:      $GOT"; line_rc=1; fi
/usr/bin/python3 "$HERE/rig_lib.py" result "$RIG" drive_rc="$drive_rc" audit_rc="$audit_rc" \
  refusal_rc="$refusal_rc" line_rc="$line_rc" "got=\"$GOT\"" "expected=\"$EXPECTED\""
if [ "${LR_RIG_KEEP:-0}" != 1 ]; then
  teardown; late_sweep
  log "result: $RIG/rig-result.json (leftovers $(/usr/bin/python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("leftovers",[])))' "$RIG/rig-result.json"))"
fi
[ $line_rc -eq 0 ] && [ $audit_rc -eq 0 ] && [ $refusal_rc -eq 0 ] && [ $drive_rc -eq 0 ] && exit 0
exit 1
