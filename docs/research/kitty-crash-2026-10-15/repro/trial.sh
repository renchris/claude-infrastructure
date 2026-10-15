#!/bin/bash
# trial.sh — ONE repro trial of the 2026-10-15 kitty crash, in a FRESH throwaway kitty.
#
#   trial.sh <action> <ctx> <delay_ms> [panes]
#     action   move   detach-window --target-tab (kitty-pane-menu "Move to <window>")
#              close  close-window over remote control (kitty-confirm-close's close)
#              exit   the last pane's child process exits (SIGTERM to its sleep)
#              menu   the REAL bin/kitty-pane-menu code path, driven with KPM_* test hooks (see
#                     repro/README) — only meaningful against a build of the menu that has them
#     ctx      idle    the throwaway kitty is the front app and has been idle >= 1.5 s
#              helper  the stand-in helper app activates, shows an NSMenu, cancels it, exits;
#                      the action fires <delay_ms> after it exits (the incident: ~35 ms)
#     panes    panes in the fullscreen window before the trial (default 1). With 2, the extra
#              pane is closed 1 s before the action, as pane 8 was in the incident.
#
# Prints ONE TSV row on stdout:
#   action ctx delay panes crashed kitty_rc fs_verified front_pid_before kitty_pid ips detail
#
# SAFETY. Every `kitty @` here carries --to unix:<this trial's own socket>; no osascript and no
# `tell application "kitty"` anywhere (that addresses the LIVE app by name). The only processes
# signalled are this script's own $! child (re-checked by comm before the kill) and a sleep whose
# parent pid is that child.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="${KCR_RUN:-$HOME/Development/.worktrees/kitty-repro}"
PROBE="$RUN/probe"
CONF="$RUN/conf/kitty.conf"
K=/Applications/kitty.app/Contents/MacOS/kitty
ACTION="$1" CTX="$2" DELAY="${3:-0}" PANES="${4:-1}"
SOCK="$RUN/k-$$.sock"
LOG="$RUN/logs/trial-$$.log"
mkdir -p "$RUN/logs"
: > "$LOG"
msleep() { perl -e "select(undef,undef,undef,$1/1000)"; }
note() { printf '%s %s\n' "$(perl -MTime::HiRes=time -e 'printf "%.3f", time')" "$*" >> "$LOG"; }
KR() { "$K" @ --to "unix:$SOCK" "$@"; }
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ACTION" "$CTX" "$DELAY" "$PANES" "$@"; }

MARK="$RUN/logs/mark-$$"; : > "$MARK"
env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    LANG=en_US.UTF-8 TMPDIR="${TMPDIR:-/tmp}" \
    "$K" --config "$CONF" -o allow_remote_control=socket-only -o confirm_os_window_close=0 \
    --listen-on "unix:$SOCK" --title kcrash-repro-A /bin/sleep 900 >> "$LOG" 2>&1 &
KPID=$!
note "launched kitty pid $KPID"

mine() { # the pid is still OUR kitty
  [ "$(ps -o ppid= -p "$KPID" 2>/dev/null | tr -d ' ')" = "$$" ] &&
    ps -o comm= -p "$KPID" 2>/dev/null | grep -q '/kitty.app/Contents/MacOS/kitty$'
}
cleanup() {
  if kill -0 "$KPID" 2>/dev/null && mine; then
    # Leave fullscreen on anything still fullscreen, then terminate OUR kitty by pid.
    for pw in $("$PROBE" fs "$KPID" | awk -F'\t' '$7 ~ /4/ {print $1}'); do
      wid=$(KR ls 2>/dev/null | /usr/bin/python3 -c '
import json,sys
for o in json.load(sys.stdin):
    if str(o.get("platform_window_id")) == sys.argv[1]:
        print(o["tabs"][0]["windows"][0]["id"]); break' "$pw")
      [ -n "$wid" ] && KR action --match "id:$wid" toggle_fullscreen >/dev/null 2>&1 && sleep 2
    done
    kill -TERM "$KPID" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$KPID" 2>/dev/null || break; sleep 0.5; done
  fi
  wait "$KPID" 2>/dev/null
  rm -f "$SOCK" "$MARK"
}
trap cleanup EXIT

for _ in $(seq 1 60); do [ -S "$SOCK" ] && KR ls >/dev/null 2>&1 && break; sleep 0.25; done
[ -S "$SOCK" ] || { row 0 - - - "$KPID" - "no socket"; exit 1; }
ls_json() { KR ls 2>/dev/null; }
A=$(ls_json | /usr/bin/python3 -c 'import json,sys; t=json.load(sys.stdin); print(t[0]["tabs"][0]["windows"][0]["id"])')
B=$(KR launch --type=os-window --title kcrash-repro-B /bin/sleep 900 2>>"$LOG")
EXTRA=""
[ "$PANES" = 2 ] && EXTRA=$(KR launch --match "id:$A" --type=window /bin/sleep 900 2>>"$LOG")
read -r TABB PWA < <(ls_json | /usr/bin/python3 -c '
import json,sys
a,b=int(sys.argv[1]),int(sys.argv[2]); tb=pw=""
for o in json.load(sys.stdin):
    for t in o["tabs"]:
        ids=[w["id"] for w in t["windows"]]
        if b in ids: tb=t["id"]
        if a in ids: pw=o["platform_window_id"]
print(tb,pw)' "$A" "$B")
note "A=$A B=$B extra=$EXTRA tabB=$TABB pwA=$PWA"

KR focus-window --match "id:$A" >/dev/null 2>&1
KR action --match "id:$A" toggle_fullscreen >/dev/null 2>&1
fs=0
for i in $(seq 1 40); do
  if "$PROBE" fs "$KPID" | awk -F'\t' -v p="$PWA" '$1 == p && $7 ~ /(^|,)4(,|$)/ {f=1} END {exit !f}'; then fs=1; break; fi
  if [ "$i" = 16 ]; then KR focus-window --match "id:$A" >/dev/null 2>&1; KR action --match "id:$A" toggle_fullscreen >/dev/null 2>&1; fi
  sleep 0.25
done
note "fullscreen verified=$fs"
sleep 1.5   # let the ENTER transition finish: "idle" means no transition in flight

if [ -n "$EXTRA" ]; then KR close-window --match "id:$EXTRA" >/dev/null 2>&1; note "closed extra $EXTRA"; sleep 1; fi

CHILD=$(ls_json | /usr/bin/python3 -c '
import json,sys
for o in json.load(sys.stdin):
    for t in o["tabs"]:
        for w in t["windows"]:
            if w["id"] == int(sys.argv[1]): print(w.get("pid") or "")' "$A")

case "$CTX" in
  helper) note "helper start"; "$PROBE" helper 250 300 2>>"$LOG"; note "helper exited"; [ "$DELAY" -gt 0 ] && msleep "$DELAY" ;;
  idle) : ;;
  *) row 0 - "$fs" - "$KPID" - "bad ctx"; exit 2 ;;
esac
FRONT=$("$PROBE" front)
note "front=$FRONT action=$ACTION"
case "$ACTION" in
  move)  KR detach-window --match "id:$A" --target-tab "id:$TABB" >>"$LOG" 2>&1 ;;
  close) KR close-window --match "id:$A" >>"$LOG" 2>&1 ;;
  exit)  if [ -n "$CHILD" ] && [ "$(ps -o ppid= -p "$CHILD" | tr -d ' ')" = "$KPID" ]; then kill -TERM "$CHILD"; else note "child $CHILD not ours"; fi ;;
  menu)  KCR_SOCK="$SOCK" KCR_WID="$A" "$HERE/menu-drive.sh" >>"$LOG" 2>&1 ;;
esac
note "action sent"

crashed=0
for _ in $(seq 1 24); do kill -0 "$KPID" 2>/dev/null || { crashed=1; break; }; sleep 0.25; done
rc=-
if [ "$crashed" = 1 ]; then wait "$KPID"; rc=$?; fi
sleep 0.5
ips=$(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'kitty-*.ips' -newer "$MARK" 2>/dev/null | head -1)
detail=$( [ "$crashed" = 0 ] && ls_json | /usr/bin/python3 -c 'import json,sys; print("oswins=%d" % len(json.load(sys.stdin)))' 2>/dev/null)
note "crashed=$crashed rc=$rc ips=$ips $detail"
row "$crashed" "$rc" "$fs" "$FRONT" "$KPID" "${ips:--}" "${detail:-log=$LOG}"
