#!/bin/bash
# run.sh — the 2026-10-15 kitty crash repro matrix, against ONE throwaway kitty that is relaunched
# only when a trial kills it (a cold kitty start measured ~2 min at load 58, so one kitty per trial
# would cost hours).
#
#   run.sh <reps> <cell>...       cell = action:ctx[:delay_ms[:post[:panes]]]
#   env: KCR_BFS=1      the destination B is ALSO native fullscreen on its own Space (the incident:
#                       every OS window was; the move destination a87e was one of them)
#        KCR_EXTRA=N    N more one-pane native-fullscreen OS windows, created once per kitty
#        KCR_AFS=0      CONTROL: leave A windowed (never fullscreen) — the same destroy, no transition
#        KCR_ENV="K=V …" extra environment for the throwaway kitty, e.g. NSZombieEnabled=YES
#                       MallocScribble=1 — a use-after-free then fails on EVERY occurrence instead
#                       of only when the freed memory happens to be reused
#        KCR_KITTY=PATH the throwaway's kitty binary (default the installed app's), e.g. a patched
#                       build's <bundle>/Contents/MacOS/kitty; `kitty @` runs that bundle's kitten
#     action  move   detach-window --target-tab   (kitty-pane-menu "Move to <window>")
#             close  close-window                 (kitty-confirm-close's close)
#             exit   the pane's child process exits
#             closeos the close_os_window action on A (--self; kitty's own OS-window close, the red button's path)
#             fsoff-move | fsoff-close  the CANDIDATE GUARD: toggle A's fullscreen off, poll the
#                    probe until A's window is no longer on a type-4 Space, settle 1 s, then act
#     ctx     idle   throwaway kitty is the front app, nothing in flight for >= 1.5 s
#             helper the stand-in helper (probe helper) activates, pops an NSMenu, cancels it,
#                    exits; the action fires <delay_ms> after it exits
#             settle like helper, then the GUARD's settle: wait until the throwaway kitty is the
#                    front app again, plus <delay_ms>, before the action (the candidate fix)
#     post    none | activate | menu — `activate`: ~100 ms after the action, re-activate the
#             throwaway kitty by an Apple Event to its PID (what refocus()'s osascript did at .558,
#             without addressing any app by name). `menu`: the menu's whole tail — equalize_tab_of
#             (`action --self layout_action equalize`), then the AE activate.
#     panes   panes in A before the trial (default 1). With 2, the extra pane is closed 1 s before
#             the action (pane 8 left window 5 shortly before the move).
#
# Rows append to $RUN/results.tsv:
#   ts rep action ctx delay post panes bfs extra crashed rc fs front_before front_at_action kitty_pid ips note
#
# SAFETY: every `kitty @` carries --to unix:$SOCK (this run's own socket, never /tmp); the kitty is
# launched under `env -i`, so no KITTY_LISTEN_ON / KITTY_WINDOW_ID / ITERM_SESSION_ID of the live
# instance leaks in; the only pids signalled are our own $! kitty (re-checked) and sleeps whose
# parent is that kitty. No osascript, no `tell application "kitty"`.
set -u
RUN="${KCR_RUN:-$HOME/Development/.worktrees/kitty-repro}"
PROBE="$RUN/probe"
CONF="$RUN/conf/kitty.conf"
K="${KCR_KITTY:-/Applications/kitty.app/Contents/MacOS/kitty}"
SOCK="$RUN/k.sock"
RES="${KCR_RES:-$RUN/results.tsv}"
LOG="$RUN/logs/run-$$.log"
mkdir -p "$RUN/logs" "$RUN/cache"
[ -s "$RES" ] || printf 'ts\trep\taction\tctx\tdelay\tpost\tpanes\tbfs\textra\tcrashed\trc\tfs\tfront_before\tfront_at_action\tkitty_pid\tips\tnote\tload\tfront_pre\tguard_rc\tdisplay\n' > "$RES"
# Nothing of the LIVE kitty may reach a `kitty @` payload: KITTY_WINDOW_ID is what --self and
# `launch` resolve their "self" window from, and this shell runs inside the live kitty.
unset KITTY_WINDOW_ID KITTY_LISTEN_ON KITTY_PID
REPS="$1"; shift

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
msleep() { perl -e "select(undef,undef,undef,$1/1000)"; }
note() { printf '%s %s\n' "$(now)" "$*" >> "$LOG"; }
KR() { "$K" @ --to "unix:$SOCK" "$@"; }
# kitty 0.48.2 IGNORES `action --match` (the client sends match_window, the server reads match) and
# acts on the ACTIVE window. --self + KITTY_WINDOW_ID is the only exact target; the window must
# exist, or kitty falls back to the active window again (rc/base.py windows_for_match_payload).
KSELF() { local w="$1"; shift; KITTY_WINDOW_ID="$w" "$K" @ --to "unix:$SOCK" action --self "$@"; }
py() { /usr/bin/python3 -c "$@"; }
KPID=""

mine() { [ -n "$KPID" ] && [ "$(ps -o ppid= -p "$KPID" 2>/dev/null | tr -d ' ')" = "$$" ] &&
         ps -o comm= -p "$KPID" 2>/dev/null | grep -q '/kitty\.app[^/]*/Contents/MacOS/kitty$'; }

launch_kitty() {
  local kenv=()
  read -r -a kenv <<<"${KCR_ENV:-}"
  rm -f "$SOCK"
  env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
      LANG=en_US.UTF-8 TMPDIR="${TMPDIR:-/tmp}" KITTY_CACHE_DIRECTORY="$RUN/cache" ${kenv[@]+"${kenv[@]}"} \
      "$K" --config "$CONF" -o allow_remote_control=socket-only -o confirm_os_window_close=0 \
      --instance-group=kcrash-repro --listen-on "unix:$SOCK" --title kcrash-repro-B /bin/sleep 86400 >> "$LOG" 2>&1 &
  KPID=$!
  local t0; t0=$(now)
  for _ in $(seq 1 1200); do [ -S "$SOCK" ] && KR ls >/dev/null 2>&1 && break; kill -0 "$KPID" 2>/dev/null || break; sleep 0.25; done
  note "kitty $KPID up after $(perl -e "printf '%.1f', $(now) - $t0") s"
  [ -S "$SOCK" ] || return 1
  local b w; b=$(tree | py 'import json,sys; print(json.load(sys.stdin)[0]["tabs"][0]["windows"][0]["id"])')
  [ "${KCR_BFS:-0}" = 1 ] && make_fs "$b"
  for _ in $(seq 1 "${KCR_EXTRA:-0}"); do
    w=$(KR launch --type=os-window --title kcrash-repro-X /bin/sleep 86400 2>>"$LOG"); make_fs "$w"
  done
  return 0
}
make_fs() { # <kitty window id> -> 0 iff its OS window reads native fullscreen
  local p i; p=$(pw_of "$1")
  KR focus-window --match "id:$1" >/dev/null 2>&1
  KSELF "$1" toggle_fullscreen >/dev/null 2>&1
  for i in $(seq 1 40); do
    is_fs "$p" && { sleep 1.5; return 0; }
    [ "$i" = 16 ] && { KR focus-window --match "id:$1" >/dev/null 2>&1; KSELF "$1" toggle_fullscreen >/dev/null 2>&1; }
    sleep 0.25
  done
  note "make_fs $1 ($p): NOT fullscreen"; return 1
}

quit_kitty() {
  mine || return 0
  for pw in $("$PROBE" fs "$KPID" | awk -F'\t' '$7 ~ /(^|,)4(,|$)/ {print $1}'); do
    w=$(KR ls 2>/dev/null | py 'import json,sys
for o in json.load(sys.stdin):
    if str(o.get("platform_window_id")) == sys.argv[1]: print(o["tabs"][0]["windows"][0]["id"]); break' "$pw")
    [ -n "$w" ] && KSELF "$w" toggle_fullscreen >/dev/null 2>&1 && sleep 2.5
  done
  KR action quit >/dev/null 2>&1
  for _ in $(seq 1 40); do kill -0 "$KPID" 2>/dev/null || break; sleep 0.25; done
  mine && kill -KILL "$KPID"
  wait "$KPID" 2>/dev/null
  rm -f "$SOCK"
}
trap quit_kitty EXIT

tree() { KR ls 2>/dev/null; }
# B = the first OS window (the launch window) — the persistent move destination. `tree` lists OS
# windows in creation order, so t[0] is B for the kitty's whole life.
b_tab() { tree | py 'import json,sys; t=json.load(sys.stdin); print(t[0]["tabs"][0]["id"])'; }
# close every pane in B except its first, so B never empties
trim_b() {
  for w in $(tree | py 'import json,sys
t=json.load(sys.stdin); ws=[w["id"] for tb in t[0]["tabs"] for w in tb["windows"]]
print(" ".join(map(str, ws[1:])))'); do KR close-window --match "id:$w" >/dev/null 2>&1; done
}
pw_of() { tree | py 'import json,sys
for o in json.load(sys.stdin):
    for tb in o["tabs"]:
        if any(w["id"] == int(sys.argv[1]) for w in tb["windows"]): print(o["platform_window_id"])' "$1"; }
child_of() { tree | py 'import json,sys
for o in json.load(sys.stdin):
    for tb in o["tabs"]:
        for w in tb["windows"]:
            if w["id"] == int(sys.argv[1]): print(w.get("pid") or "")' "$1"; }
is_fs() { "$PROBE" fs "$KPID" | awk -F'\t' -v p="$1" '$1 == p && $7 ~ /(^|,)4(,|$)/ {f=1} END {exit !f}'; }

# ── phase 2: drive the LANDED fix (docs/research/kitty-crash-2026-10-15/README.md § Phase 2) ──────
# LANDED = the deployed bin dir (its files are symlinks into the shared checkout after a converge).
LANDED="${KCR_LANDED:-$HOME/.claude/bin}"
GUARD="$LANDED/kitty-fullscreen-guard"
SCR="$RUN/menu-bin"; FAKE="$RUN/fakebin"; OSALOG="$RUN/logs/osascript-$$.log"; MENULOG="$RUN/logs/menu-$$.log"
ACTLOG="$RUN/logs/pane-actions.jsonl"
# A scratch bin: the landed menu, confirm-close and guard (symlinks — the menu resolves siblings by
# abspath(__file__), the guard its kitten by realpath), beside a FAKE native helper, plus a fake
# osascript first on PATH that LOGS and REFUSES anything naming kitty (that addresses the LIVE app).
setup_scratch() {
  mkdir -p "$SCR" "$FAKE"
  local f; for f in kitty-pane-menu kitty-confirm-close kitty-fullscreen-guard; do ln -sf "$LANDED/$f" "$SCR/$f"; done
  cat >"$SCR/kitty-pane-menu-native" <<'SH'
#!/bin/bash
# Capability markers the menu greps for: KPM-WINDOWS-MODE-V1 KPM-DISPLAY-GEOM-V1 KPM-CURSOR-HIT-V1
[ "${1:-}" = --windows ] && exec "$HOME/.claude/bin/kitty-pane-menu-native" --windows
printf '%s menu items: %s\n' "$(perl -MTime::HiRes=time -e 'printf "%.3f", time')" "$*" >>"$KCR_MENU_LOG"
"$KCR_PROBE" helper 250 300 >/dev/null 2>&1   # the real helper's activate / pop / quit, then the pick
case "$KCR_MENU_PICK" in
  new) echo "Move to New Window" ;;
  close) echo "Close Pane" ;;
  move) for a in "$@"; do case "$a" in Paste|"Move to New Window"|"Close Pane") ;; *) echo "$a"; exit 0 ;; esac; done ;;
esac
SH
  cat >"$FAKE/osascript" <<'SH'
#!/bin/bash
in=""; [ "${1:-}" = - ] && in="$(cat)"
ts="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
case "$* $in" in
  *'application "kitty"'*|*kovidgoyal*) printf '%s REFUSED %s\n' "$ts" "$*" >>"$KCR_OSALOG"; exit 1 ;;
esac
printf '%s ok %s\n' "$ts" "$(printf '%s' "$* $in" | tr '\n' ' ' | cut -c1-200)" >>"$KCR_OSALOG"
case "$in" in *"display dialog"*) echo "Close" ;; esac
exit 0
SH
  chmod +x "$SCR/kitty-pane-menu-native" "$FAKE/osascript"
}
run_menu() { # <pick> -> the landed menu's rc; env -i so nothing of the live kitty leaks in
  env -i HOME="$HOME" USER="$USER" LANG=en_US.UTF-8 TMPDIR="${TMPDIR:-/tmp}" \
      PATH="$FAKE:/Applications/kitty.app/Contents/MacOS:/usr/bin:/bin:/usr/sbin:/sbin" \
      KITTY_LISTEN_ON="unix:$SOCK" CC_TERM_KITTY="$K" CC_KITTY_PANE_ACTIONS_LOG="$ACTLOG" \
      CC_SPAWN_LOG_FILE="$RUN/logs/pane-spawns.jsonl" KCR_MENU_PICK="$1" KCR_PROBE="$PROBE" \
      KCR_MENU_LOG="$MENULOG" KCR_OSALOG="$OSALOG" "$SCR/kitty-pane-menu" >>"$LOG" 2>&1
}
run_guard() { # <wid> <scope> -> the landed guard's rc
  env -i HOME="$HOME" USER="$USER" LANG=en_US.UTF-8 TMPDIR="${TMPDIR:-/tmp}" \
      PATH="$FAKE:/Applications/kitty.app/Contents/MacOS:/usr/bin:/bin:/usr/sbin:/sbin" \
      CC_TERM_KITTY="$K" CC_KITTY_PANE_ACTIONS_LOG="$ACTLOG" KCR_OSALOG="$OSALOG" \
      "$GUARD" --window "$1" --to "unix:$SOCK" --mode toggle --scope "${2:-pane}" --tool kcrash-repro >>"$LOG" 2>&1
}
# Origin of a display other than the main one, in global points (KCR_DISPLAY=2|3 picks it).
display_origin() {
  py 'import ctypes, ctypes.util, sys
cg = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
class R(ctypes.Structure): _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double), ("w", ctypes.c_double), ("h", ctypes.c_double)]
cg.CGDisplayBounds.restype = R; cg.CGMainDisplayID.restype = ctypes.c_uint32
ids = (ctypes.c_uint32 * 8)(); n = ctypes.c_uint32()
cg.CGGetActiveDisplayList(8, ids, ctypes.byref(n))
others = [i for i in ids[:n.value] if i != cg.CGMainDisplayID()]
k = int(sys.argv[1]) - 2
if 0 <= k < len(others):
    r = cg.CGDisplayBounds(others[k]); print("%dx%d" % (r.x + 80, r.y + 80))' "$1"
}
probe_rows() { "$PROBE" fs "$KPID" | awk -v t="$(now)" '{print t "\t" $0}' >>"$LOG"; }

trial() { # rep action ctx delay post panes
  local rep="$1" action="$2" ctx="$3" delay="$4" post="$5" panes="$6"
  local A PWA TABB CHILD EXTRA="" fs=0 fb fa="-" fpre="-" crashed=0 rc="-" ips mark nt="" grc="-" pos="" ld
  if ! kill -0 "$KPID" 2>/dev/null; then launch_kitty || { note "launch failed"; return 1; }; fi
  trim_b; TABB=$(b_tab)
  [ "${KCR_DISPLAY:-1}" != 1 ] && pos=$(display_origin "$KCR_DISPLAY")
  if [ "$ctx" = autofs ]; then
    # AppKit's automatic fullscreen of a new window: open A while a fullscreen window (B) is key,
    # then destroy it inside the window where any enter animation would run.
    KR focus-window --match "id:$(tree | py 'import json,sys; print(json.load(sys.stdin)[0]["tabs"][0]["windows"][0]["id"])')" >/dev/null 2>&1; sleep 1
  fi
  A=$(KR launch --type=os-window ${pos:+--os-window-position "$pos"} --title kcrash-repro-A /bin/sleep 86400 2>>"$LOG")
  PWA=$(pw_of "$A"); CHILD=$(child_of "$A")
  [ "$panes" = 2 ] && EXTRA=$(KR launch --match "id:$A" --type=window /bin/sleep 86400 2>>"$LOG")
  if [ "$ctx" = autofs ]; then msleep "$delay"; fs="auto"
  elif [ "${KCR_AFS:-1}" = 1 ]; then make_fs "$A" && fs=1; else KR focus-window --match "id:$A" >/dev/null 2>&1; sleep 1.5; fi
  if [ -n "$EXTRA" ]; then KR close-window --match "id:$EXTRA" >/dev/null 2>&1; sleep 1; KR focus-window --match "id:$A" >/dev/null 2>&1; sleep 0.5; fi
  fb=$("$PROBE" front)
  mark="$RUN/logs/mark-$$-$rep"; : > "$mark"
  note "rep=$rep $action/$ctx/$delay/$post/$panes bfs=${KCR_BFS:-0} extra=${KCR_EXTRA:-0} display=${KCR_DISPLAY:-1} pos=${pos:--} A=$A pwA=$PWA tabB=$TABB child=$CHILD fs=$fs front=$fb"
  case "$ctx" in
    idle|autofs) ;;
    helper) "$PROBE" helper 250 300 2>>"$LOG"; [ "$delay" -gt 0 ] && msleep "$delay" ;;
    settle) "$PROBE" helper 250 300 2>>"$LOG"
            for _ in $(seq 1 40); do [ "$("$PROBE" front)" = "$KPID" ] && break; msleep 25; done
            [ "$delay" -gt 0 ] && msleep "$delay" ;;
    # A is NOT the active kitty window: B (first OS window) takes focus. With B on another Space of
    # the same display, A's Space goes to the background — the guard must refuse, never pull the
    # operator across Spaces. With A on another display (KCR_DISPLAY), A stays visible, unfocused.
    unfocus) KR focus-window --match "id:$(tree | py 'import json,sys; print(json.load(sys.stdin)[0]["tabs"][0]["windows"][0]["id"])')" >/dev/null 2>&1; sleep 1.5 ;;
  esac
  probe_rows
  case "$action" in
    fsoff-*) KSELF "$A" toggle_fullscreen >/dev/null 2>&1
             for _ in $(seq 1 60); do is_fs "$PWA" || break; msleep 100; done
             is_fs "$PWA" && nt="${nt}still-fs;"; sleep 1; action="${action#fsoff-}"; nt="${nt}fsoff;" ;;
    guard-*) fpre=$("$PROBE" front); note "guard start"; run_guard "$A" pane; grc=$?; note "guard rc=$grc"; probe_rows
             if [ "$grc" = 0 ]; then action="${action#guard-}"; else action="refused"; nt="${nt}guard-refused;"; fi ;;
  esac
  [ "$fpre" = "-" ] && fpre=$("$PROBE" front)
  ld=$(sysctl -n vm.loadavg | awk '{print $2}')
  note "action $action load=$ld front_pre=$fpre"
  case "$action" in
    move)  KR detach-window --match "id:$A" --target-tab "id:$TABB" >>"$LOG" 2>&1 ;;
    close) KR close-window --match "id:$A" >>"$LOG" 2>&1 ;;
    closeos) KSELF "$A" close_os_window >>"$LOG" 2>&1 ;;
    exit)  if [ -n "$CHILD" ] && [ "$(ps -o ppid= -p "$CHILD" | tr -d ' ')" = "$KPID" ]; then kill -TERM "$CHILD"; else nt="child-not-ours"; fi ;;
    menu-*) run_menu "${action#menu-}"; grc=$?; nt="${nt}menu-rc=$grc;" ;;
    refused) ;;
  esac
  probe_rows
  case "$post" in
    activate) msleep 100; "$PROBE" activate "$KPID" 2>>"$LOG" ;;
    menu) KSELF "$A" layout_action equalize >/dev/null 2>&1
          KR ls >/dev/null 2>&1; "$PROBE" activate "$KPID" 2>>"$LOG" ;;
  esac
  fa=$("$PROBE" front)
  for _ in $(seq 1 12); do kill -0 "$KPID" 2>/dev/null || { crashed=1; break; }; sleep 0.25; done
  if [ "$crashed" = 1 ]; then wait "$KPID"; rc=$?; sleep 3; fi
  zl=$(grep -c 'deallocated instance' "$LOG" 2>/dev/null); [ "${zl:-0}" -gt "${ZSEEN:-0}" ] && { nt="${nt}ZOMBIE($(grep 'deallocated instance' "$LOG" | tail -1 | grep -o '\-\[[^]]*\]'));"; ZSEEN=$zl; }
  # Only THIS throwaway's crash report counts — the live kitty may write its own.
  ips=$(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'kitty-*.ips' -newer "$mark" 2>/dev/null \
        | while read -r f; do grep -q "\"pid\" *: *${KPID}[,}]" "$f" 2>/dev/null && { echo "$f"; break; }; done)
  if [ "$crashed" = 0 ]; then
    if [ -n "$(pw_of "$A")" ] && [ "$action" != move ] && [ "$action" != menu-move ] && [ "$action" != menu-new ]; then nt="${nt}A-still-present;"; fi
    # a leftover fullscreen A (refused, or the action failed) leaves fullscreen before the next trial
    if [ -n "$PWA" ] && is_fs "$PWA"; then KR focus-window --match "id:$A" >/dev/null 2>&1; KSELF "$A" toggle_fullscreen >/dev/null 2>&1; sleep 2.5; nt="${nt}fs-left;"; fi
    [ -n "$(pw_of "$A")" ] && [ "$action" != move ] && [ "$action" != menu-move ] && KR close-window --match "id:$A" >/dev/null 2>&1
    # menu-new leaves A in a NEW windowed OS window; close it so the next trial starts clean
  fi
  rm -f "$mark"
  note "crashed=$crashed rc=$rc ips=$ips guard_rc=$grc"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%H:%M:%S)" "$rep" "$2" "$ctx" "$delay" "$post" "$panes" "${KCR_BFS:-0}" "${KCR_EXTRA:-0}" \
    "$crashed" "$rc" "$fs" "$fb" "$fa" "$KPID" "${ips:+${ips##*/}}" "${nt:--}" "$ld" "$fpre" "$grc" "${KCR_DISPLAY:-1}" | tee -a "$RES"
  sleep 1
}

setup_scratch
for rep in $(seq 1 "$REPS"); do
  for cell in "$@"; do
    IFS=: read -r a c d p n <<<"$cell"
    trial "$rep" "$a" "$c" "${d:-0}" "${p:-none}" "${n:-1}"
  done
done
