#!/usr/bin/env bats
# cc-restore (W3 P5) — the one operator command for a planned or deaf-kitty restart.
#
# NOTHING HERE CAN SIGNAL OR LAUNCH THE REAL KITTY. ps, kill, open, kitten, boot-resume, the build
# check, rebind, cc-sessions, lsof and zprint are stubs that record their argv; the state and
# heartbeat dirs are under $BATS_TEST_TMPDIR; and the subject itself refuses to run under a bats
# harness unless every one of those seams names a stub (pinned below). The "kitty" is a `sleep`
# this file starts: the kill stub never signals it, it only edits the ps stub's table.
# What these pin: --confirm must name the main kitty; the lock is taken before any signal; the
# restart runs in its own session; --dry-run signals nothing; --abort releases the lock; the fd
# limit and the kitten backoff; rebind runs after .done and is keyed on sids, not map lines.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="$REPO/bin/cc-restore"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"; mkdir -p "$HOME"
  export CC_BOOT_RESUME_STATE_DIR="$T/state" CC_HEARTBEAT_DIR="$T/hb"
  export RESTORE_LOCK_BOOT_UUID=UUID-T CC_BOOTUUID_OVERRIDE=UUID-T
  export CC_RESTORE_TERM_WAIT_S=0 CC_RESTORE_EXIT_WAIT_S=1 CC_RESTORE_SOCKET_WAIT_S=4 CC_RESTORE_K_BACKOFF_S=0
  export CC_RESTORE_ROUND_SLEEP_S=0 CC_RESTORE_LAND_POLL_S=0.2 CC_RESTORE_K_TIMEOUT_S=5
  export CC_RESTORE_SOCKET_TMPL="unix:$T/kitty-{pid}"
  export S1=11111111-aaaa-4aaa-8aaa-000000000001 S2=11111111-aaaa-4aaa-8aaa-000000000002
  sleep 600 & KP=$!; export KP
  export NEWPID=55555
  LSTART='Thu Oct  1 13:40:01 2026'

  export CC_RESTORE_PS_BIN="$T/ps"
  cat > "$CC_RESTORE_PS_BIN" <<'SH'
#!/bin/bash
case "$*" in
  *lstart=,args=*) cat "$0.kitty" 2>/dev/null ;;
  *stat=*)         printf 'S\nZ\nR\nZ\n' ;;
  *pid=,args=*)    n="$(cat "$0.lands-left" 2>/dev/null || echo 0)"
                   if [ "$n" -gt 0 ]; then echo "777 /bin/bash /repo/scripts/ship-land.sh"; [ "$n" -lt 999 ] && echo $((n - 1)) > "$0.lands-left"; fi
                   echo "888 claude --resume x  # a brief that mentions ship-land.sh" ;;
esac
exit 0
SH
  echo "$KP $LSTART /Applications/kitty.app/Contents/MacOS/kitty" > "$CC_RESTORE_PS_BIN.kitty"
  echo "4343 $LSTART /Applications/kitty.app.staged/Contents/MacOS/kitty --instance-group sandbox" >> "$CC_RESTORE_PS_BIN.kitty"

  export CC_RESTORE_KILL_BIN="$T/kill"
  cat > "$CC_RESTORE_KILL_BIN" <<'SH'
#!/bin/bash
# Never signals anything. Records the call, whether the restore lock was held, and its caller's
# process group; then edits the ps table the way the signal would have.
lock=no; [ -f "$CC_BOOT_RESUME_STATE_DIR/restore.lock/holder" ] && lock=yes
echo "$* lock=$lock ppid=$PPID pgid=$(/bin/ps -o pgid= -p $PPID | tr -d ' ')" >> "$0.log"
sig="$1"; pid="$2"
[ "$sig" = "-TERM" ] && [ -f "$0.ignore-term" ] && exit 0
[ -f "$0.immortal" ] && exit 0
grep -v "^$pid " "$CC_RESTORE_PS_BIN.kitty" > "$CC_RESTORE_PS_BIN.kitty.tmp"; mv "$CC_RESTORE_PS_BIN.kitty.tmp" "$CC_RESTORE_PS_BIN.kitty"
exit 0
SH
  export CC_OPEN_BIN="$T/open"
  cat > "$CC_OPEN_BIN" <<'SH'
#!/bin/bash
echo "$*" >> "$0.log"
[ -f "$0.dead" ] && exit 0
echo "$NEWPID Mon Oct  5 09:00:00 2026 /Applications/kitty.app/Contents/MacOS/kitty" >> "$CC_RESTORE_PS_BIN.kitty"
: > "$BATS_TEST_TMPDIR/kitty-$NEWPID"
SH
  export CC_RESTORE_KITTEN_BIN="$T/kitten"
  cat > "$CC_RESTORE_KITTEN_BIN" <<'SH'
#!/bin/bash
echo "$(date +%s) $*" >> "$0.log"
if [ -f "$0.slow-once" ]; then rm -f "$0.slow-once"; sleep 3; exit 1; fi
echo '[]'
SH
  export CC_RESTORE_BOOT_RESUME="$T/boot-resume"
  cat > "$CC_RESTORE_BOOT_RESUME" <<'SH'
#!/bin/bash
echo "argv: $*" >> "$0.log"
ev=""; kp=""; plan=0
while [ $# -gt 0 ]; do case "$1" in --event) ev="$2"; shift 2 ;; --kitty-pid) kp="$2"; shift 2 ;; --plan-only) plan=1; shift ;; *) shift ;; esac; done
if [ "$plan" = 1 ]; then cat "$0.plan"; exit 0; fi
echo "env: CC_TERM_KITTY_TO=${CC_TERM_KITTY_TO:-} KITTY_WINDOW_ID=${KITTY_WINDOW_ID:-unset}" >> "$0.log"
id="${kp:-$ev}"; d="$CC_BOOT_RESUME_STATE_DIR/events/$id"; mkdir -p "$d"
n=$(( $(cat "$0.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$0.n"
echo "1784800000 load1=2.0 ncpu=8 per_core=0.25 gate=6 round=$n" >> "$d/load.log"
[ -f "$0.rc" ] && exit "$(cat "$0.rc")"
[ -f "$0.hang" ] && sleep 30
printf 'cc-resume-layout: map sid=%s wid=7 oswin=1\n' "$S1" >> "$d/map"   # S2 is a maybe row: no map line
printf '%s\n%s\n' "$S1" "$S2" > "$d/launched"
printf 'next\t%s\t/x/a\tmain\tA\tINTERRUPTED\nnext\t%s\t/x/b\tmain\tB\tAT-REST\n' "$S1" "$S2" > "$d/rows.tsv"
[ "$n" -ge "$(cat "$0.rounds" 2>/dev/null || echo 1)" ] && echo "$ev" > "$d.done"
exit 0
SH
  printf 'boot-resume: plan event=1 kind=restart source=heartbeat anchor=1 sessions=2 retired=1\nrow\tnext\t%s\t/x/a\tmain\tA\tclaude-opus-5-5\thigh\tk%sw7\t2\t-\tauto\nrow\tnext3\t%s\t/x/b\tfeat\tB\t-\t-\tk%sw7\t1\t-\tplan\nretired\tC (cccc): terminal self-close marker\nboot-resume: plan verdict=planned rows=2 retired=1 launches=0 exhausted=0 no_model=1\n' \
    "$S1" "$KP" "$S2" "$KP" > "$CC_RESTORE_BOOT_RESUME.plan"
  export CC_RESTORE_SWAP_BIN="$T/swap"
  printf '#!/bin/bash\necho "$*" >> "$0.log"\necho "live  /Applications/kitty.app  stock  v0.48.2"\n[ -f "$0.rc" ] && exit "$(cat "$0.rc")"\nexit 0\n' > "$CC_RESTORE_SWAP_BIN"
  export CC_RESTORE_REBIND_BIN="$T/rebind"
  cat > "$CC_RESTORE_REBIND_BIN" <<'SH'
#!/bin/bash
done=no; [ -e "$1.done" ] && done=yes
echo "$* done=$done lock=$([ -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ] && echo held || echo free) maps=$(cat "$1"/*.map 2>/dev/null | sed -n 's/.*sid=\([^ ]*\) wid=\([^ ]*\).*/\1:\2/p' | tr '\n' ',')" >> "$0.log"
echo "rebind: forward old=249 → sid=x"
echo "cc-restore-rebind: verdict=OK forwards=1"
SH
  # the layout's dry run: records the rows it was given; prints a recorded tree only when .tree exists
  export CC_RESTORE_LAYOUT_BIN="$T/layout"
  cat > "$CC_RESTORE_LAYOUT_BIN" <<'SH'
#!/bin/bash
echo "$*" >> "$0.log"; cat > "$0.rows"
[ -f "$0.rc" ] && exit "$(cat "$0.rc")"
if [ -f "$0.tree" ]; then
  echo "cc-resume-layout: tree oswin=1 src=k${KP}w7 platform_window_id=900 tabs=1 panes=3 claude=2 shells=1 layout=splits:H:0.33(p,V(p,p)) display=DISPLAY-A display_rect=0,0,1728x1117 fullscreen=1"
  echo "DRY [CC-DESK-1 k${KP}w7] head next3 $S2 /x/b model=m permission_mode=plan pane=#1" >&2
  echo "DRY [CC-DESK-1] place on display DISPLAY-A (0,0 1728x1117)" >&2
  echo "DRY [CC-DESK-1 k${KP}w7] vsplit next $S1 /x/a pane=#2 next-to=#1 bias=66.6667" >&2
  echo "DRY [CC-DESK-1 k${KP}w7] hsplit shell /x/tools pane=#3 next-to=#2" >&2
  echo "cc-resume-layout: layout tree_windows=1 shells=1 placed=0 placed_failed=0"
else
  echo "DRY [CC-DESK-1 k${KP}w7] head next3 $S2 /x/b pane=#1" >&2
  echo "DRY [CC-DESK-1 k${KP}w7] vsplit next $S1 /x/a pane=#2 next-to=#1" >&2
fi
echo "cc-resume-layout: verdict=ok launched=0 shed=0 failed=0 windows=1 fullscreen_ok=0 fullscreen_failed=0 maybe=0 stopped=none"
SH
  export CC_RESTORE_SESSIONS_BIN="$T/sessions"
  printf '#!/bin/bash\ncat "$0.json" 2>/dev/null || echo "[]"\n' > "$CC_RESTORE_SESSIONS_BIN"
  live_after "$S1:7" "$S2:8"
  export CC_RESTORE_LSOF_BIN="$T/lsof"
  printf '#!/bin/bash\necho "COMMAND PID USER FD"\ni=0; n="$(cat "$0.n" 2>/dev/null || echo 40)"\nwhile [ "$i" -lt "$n" ]; do echo "kitty $2 u $i"; i=$((i + 1)); done\n' > "$CC_RESTORE_LSOF_BIN"
  export CC_RESTORE_ZPRINT_BIN="$T/zprint"
  printf '#!/bin/bash\necho "data.kalloc.1024 1024 0K 0K 0K 0 4194304 0"\n' > "$CC_RESTORE_ZPRINT_BIN"
  chmod +x "$T"/ps "$T"/kill "$T"/open "$T"/kitten "$T"/boot-resume "$T"/swap "$T"/rebind "$T"/sessions "$T"/lsof "$T"/zprint "$T"/layout

  # the heartbeat tick, over stubs: two sessions in the "kitty"
  export CC_HB_SESSIONS_BIN="$T/hb-sessions"
  printf '#!/bin/bash\ncat "$0.json"\n' > "$CC_HB_SESSIONS_BIN"
  printf '[{"session_id":"%s","account":"claude-next","cwd":"/x/a","name":"A","kitty_pid":%s,"paneUUID":"249","pid":1},{"session_id":"%s","account":"claude-next","cwd":"/x/b","name":"B","kitty_pid":%s,"paneUUID":"250","pid":1}]' \
    "$S1" "$KP" "$S2" "$KP" > "$CC_HB_SESSIONS_BIN.json"
  export CC_HB_KITTEN_BIN="$T/hb-kitten"; printf '#!/bin/bash\necho "[]"\n' > "$CC_HB_KITTEN_BIN"
  chmod +x "$CC_HB_SESSIONS_BIN" "$CC_HB_KITTEN_BIN"
  export CC_HB_PS_BIN=/usr/bin/true CC_HB_LSOF_BIN=/usr/bin/true CC_ROLES_DIR="$T/roles"
  unset KITTY_PID KITTY_LISTEN_ON
  export KITTY_WINDOW_ID=99                    # the operator runs it from a kitty pane: must not be inherited
  EVENTS="$CC_BOOT_RESUME_STATE_DIR/events"
}

teardown() { kill "$KP" 2>/dev/null || true; [ -z "${BG:-}" ] || kill "$BG" 2>/dev/null || true; }

live_after() { # <sid:pane>... → what cc-sessions --json shows after the restore (in the new kitty)
  local out="" x
  for x in "$@"; do out="$out{\"session_id\":\"${x%%:*}\",\"paneUUID\":\"${x##*:}\",\"kitty_pid\":$NEWPID,\"pid\":1},"; done
  printf '[%s]' "${out%,}" > "$CC_RESTORE_SESSIONS_BIN.json"
}
ev_of() { sed -n 's/^lock taken event=//p' <<<"$output" | head -n 1; }
kills() { grep -c -- "^$1 $KP " "$CC_RESTORE_KILL_BIN.log" 2>/dev/null || true; }
no_signal() { [ ! -e "$CC_RESTORE_KILL_BIN.log" ] && [ ! -e "$CC_OPEN_BIN.log" ]; }

# ── refusals ──────────────────────────────────────────────────────────────────────────────────────
@test "--restart-kitty without --confirm refuses and signals nothing" {
  run "$SUBJ" --restart-kitty
  [ "$status" -eq 2 ]
  [[ "$output" == *"pass --confirm <main kitty pid>"* ]] || false
  no_signal
}

@test "--confirm with a pid that is not the main kitty refuses: the sandbox kitty and a stale pid alike" {
  run "$SUBJ" --restart-kitty --confirm 4343                       # a real kitty, but --instance-group
  [ "$status" -eq 3 ]
  [[ "$output" == *"--confirm 4343 is not the main kitty (pid $KP)"* ]] || false
  run "$SUBJ" --restart-kitty --confirm 1
  [ "$status" -eq 3 ]
  no_signal
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ]
}

@test "under bats it refuses unless every actuator is a stub: an unset seam, or one naming the real binary" {
  CC_RESTORE_KILL_BIN="" run "$SUBJ" --restart-kitty --confirm "$KP"
  [ "$status" -eq 2 ]
  [[ "$output" == *"REFUSED under a bats harness: CC_RESTORE_KILL_BIN"* ]] || false
  CC_OPEN_BIN=/usr/bin/open run "$SUBJ" --restart-kitty --confirm "$KP"
  [ "$status" -eq 2 ]
  [[ "$output" == *"REFUSED under a bats harness: CC_OPEN_BIN"* ]] || false
  CC_HEARTBEAT_DIR="" run "$SUBJ" --restart-kitty --dry-run
  [ "$status" -eq 2 ]
  no_signal
}

@test "preflight runs kitty-build-swap.sh status and refuses when it fails" {
  echo 1 > "$CC_RESTORE_SWAP_BIN.rc"
  run "$SUBJ" --restart-kitty --confirm "$KP"
  [ "$status" -eq 3 ]
  grep -qx status "$CC_RESTORE_SWAP_BIN.log"
  [[ "$output" == *"kitty-build-swap.sh status failed"* ]] || false
  [[ "$output" == *"verdict=PREFLIGHT-FAILED"* ]] || false
  no_signal
}

@test "two main kittys is not a target: refuses rather than pick one" {
  echo "6000 Thu Oct  1 13:40:01 2026 /Applications/kitty.app/Contents/MacOS/kitty" >> "$CC_RESTORE_PS_BIN.kitty"
  run "$SUBJ" --restart-kitty --confirm "$KP"
  [ "$status" -eq 3 ]
  [[ "$output" == *"expected exactly one main kitty, found 2"* ]] || false
  no_signal
}

# ── --dry-run ─────────────────────────────────────────────────────────────────────────────────────
@test "--dry-run needs no --confirm, prints the pid, sessions, windows, retired, ledger and every command, and signals nothing" {
  run "$SUBJ" --restart-kitty --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"main kitty: pid $KP "* ]] || false
  [[ "$output" == *"sessions to restore: 2"* ]] || false
  # the window section is the layout's own dry run over the planned rows (11 columns, '-' cells padded)
  grep -qx -- '--desktops --restore --dry-run' "$CC_RESTORE_LAYOUT_BIN.log"
  [ "$(awk -F'\t' '{ print NF }' "$CC_RESTORE_LAYOUT_BIN.rows" | sort -u)" = 11 ]
  [ "$(awk -F'\t' -v s="$S2" '$2 == s { print $6 }' "$CC_RESTORE_LAYOUT_BIN.rows")" = $'\037' ]
  [[ "$output" == *"windows planned: 1 (from the layout's own dry run; no recorded tree, so one row of panes per window)"* ]] || false
  [[ "$output" == *"window 1: 2 pane(s) · split: one row · display not recorded"* ]] || false
  [[ "$output" == *"    head B  (pane=#1)"* ]] || false
  [[ "$output" == *"    vsplit A  (pane=#2 next-to=#1)"* ]] || false
  [[ "$output" == *"sessions left retired: 1"* ]] || false
  [[ "$output" == *"C (cccc): terminal self-close marker"* ]] || false
  [[ "$output" == *"ledger: $EVENTS/<epoch>/launched"* ]] || false
  [[ "$output" == *"$CC_RESTORE_KILL_BIN -TERM $KP"* ]] || false
  [[ "$output" == *"$CC_OPEN_BIN -a /Applications/kitty.app"* ]] || false
  [[ "$output" == *"--event <epoch> --kind restart --roster-dir $EVENTS/<epoch>/hb"* ]] || false
  [[ "$output" == *"$CC_RESTORE_REBIND_BIN $EVENTS/<epoch>"* ]] || false
  [[ "$output" == *"--restart-kitty --confirm $KP"* ]] || false
  [[ "$output" == *"verdict=DRY-RUN-OK sessions=2"* ]] || false
  no_signal
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ]
  [ ! -d "$EVENTS" ]
  grep -q -- '--kind restart --plan-only' "$CC_RESTORE_BOOT_RESUME.log"
  [ ! -e "$CC_BOOT_RESUME_STATE_DIR/restore-v2" ]
}

@test "--dry-run with a recorded tree prints each window's panes, split, display and shell panes as the layout plans them" {
  : > "$CC_RESTORE_LAYOUT_BIN.tree"
  run "$SUBJ" --restart-kitty --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"windows planned: 1 (from the layout's own dry run; recorded split tree replayed)"* ]] || false
  [[ "$output" == *"window 1: 3 pane(s): 2 claude, 1 shell · was k${KP}w7 · split splits:H:0.33(p,V(p,p)) · display DISPLAY-A (0,0 1728x1117) · fullscreen"* ]] || false
  [[ "$output" == *"    vsplit A  (pane=#2 next-to=#1 bias=66.6667)"* ]] || false
  [[ "$output" == *"    hsplit shell tools  (pane=#3 next-to=#2)"* ]] || false
  [[ "$output" == *"cc-resume-layout: layout tree_windows=1 shells=1"* ]] || false
  no_signal
}

@test "--dry-run still prints a window plan when the layout's dry run fails: grouped by recorded window, and says so" {
  echo 3 > "$CC_RESTORE_LAYOUT_BIN.rc"
  run "$SUBJ" --restart-kitty --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"windows planned: 1 (the layout's dry run gave no plan; grouped by recorded window)"* ]] || false
  [[ "$output" == *"old window k${KP}w7: 2 pane(s) in one row: B, A"* ]] || false
}

# ── the restart ───────────────────────────────────────────────────────────────────────────────────
@test "a restart: lock before any signal, snapshot, TERM, open by path, event restore, rebind after .done, verdict" {
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ev="$(ev_of)"; [[ "$ev" =~ ^[0-9]+$ ]] || false
  # the lock was held when the first signal went out, and is free at the end
  [ "$(head -n 1 "$CC_RESTORE_KILL_BIN.log" | cut -d' ' -f1-3)" = "-TERM $KP lock=yes" ]
  [ "$(kills -TERM)" -eq 1 ] && [ "$(kills -KILL)" -eq 0 ] || false # it exited on TERM: no KILL
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ]
  # the snapshot the restore reads, with the kalloc reading and the zombie count (gap 20)
  [ "$(jq -r '.[].session_id' "$EVENTS/$ev/hb/$KP/hb.roster.json" | grep -c .)" -eq 2 ]
  [ "$(cat "$EVENTS/$ev/kalloc")" = "4.00" ]
  [ "$(cat "$EVENTS/$ev/zombies")" = "2" ]
  [[ "$output" == *"heartbeat copied"* ]] || false
  # the new kitty is opened by path, with no -n
  [ "$(cat "$CC_OPEN_BIN.log")" = "-a /Applications/kitty.app" ]
  # the event restore: the event IS the epoch the lock took, no --kitty-pid, the snapshot as roster
  grep -qx "argv: --event $ev --kind restart --roster-dir $EVENTS/$ev/hb" "$CC_RESTORE_BOOT_RESUME.log"
  grep -qx "env: CC_TERM_KITTY_TO=unix:$BATS_TEST_TMPDIR/kitty-$NEWPID KITTY_WINDOW_ID=unset" "$CC_RESTORE_BOOT_RESUME.log"
  [[ "$output" == *"load 1784800000 load1=2.0"* ]] || false
  # rebind: after the .done marker and after the lock is released; S2 had no map line, and is keyed by sid
  grep -q "^$EVENTS/$ev done=yes lock=free maps=$S1:7,$S2:8,$" "$CC_RESTORE_REBIND_BIN.log"
  [[ "$output" == *"rebind: forward old=249"* ]] || false
  # the crash page will not page for this pid: its death was planned, and its fleet is back
  [ "$(cat "$EVENTS/$KP.planned")" = "$ev" ] && [ -e "$EVENTS/$KP.done" ] || false
  [[ "$output" == *"cc-restore: verdict=RESTORED restored=2/2 maybe=0 dup=0 shed=0 events=$EVENTS/$ev"* ]] || false
  [ ! -e "$CC_BOOT_RESUME_STATE_DIR/restore-v2" ]
}

@test "DETACH: the restart runs in a new session, so it outlives the kitty (and the pane) it was started from" {
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 0 ]
  wline="$(grep -m1 '^worker pid=' <<<"$output")"
  wpid="$(sed -n 's/^worker pid=\([0-9]*\) sid=.*/\1/p' <<<"$wline")"; wsid="$(sed -n 's/^worker pid=[0-9]* sid=\([0-9]*\) .*/\1/p' <<<"$wline")"
  [ -n "$wpid" ] && [ "$wpid" = "$wsid" ] || false                  # a session leader: sid == pid
  # independent of what the subject says about itself: the process that called kill led its own
  # process group, and that group is not this test's
  kl="$(head -n 1 "$CC_RESTORE_KILL_BIN.log")"
  [ "$(sed -n 's/.* ppid=\([0-9]*\) .*/\1/p' <<<"$kl")" = "$wpid" ]
  [ "$(sed -n 's/.* pgid=\([0-9]*\)$/\1/p' <<<"$kl")" = "$wpid" ]
  [ "$wpid" != "$(/bin/ps -o pgid= -p $$ | tr -d ' ')" ]
}

@test "a kitty that ignores SIGTERM gets SIGKILL after the wait" {
  : > "$CC_RESTORE_KILL_BIN.ignore-term"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 0 ]
  [ "$(kills -TERM)" -eq 1 ] && [ "$(kills -KILL)" -eq 1 ] || false
  [[ "$output" == *"still alive: SIGKILL"* ]] || false
}

@test "a kitty that will not exit: nothing is relaunched, the lock is released, exit 4" {
  : > "$CC_RESTORE_KILL_BIN.immortal"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 4 ]
  [[ "$output" == *"did not exit; nothing was relaunched"* ]] || false
  [ ! -e "$CC_OPEN_BIN.log" ] && [ ! -e "$CC_RESTORE_BOOT_RESUME.n" ] || false
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ] && [ ! -e "$EVENTS/$(ev_of).inprogress" ]
}

@test "no heartbeat for the kitty: stops before any signal (there would be nothing to restore from)" {
  echo '[]' > "$CC_HB_SESSIONS_BIN.json"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 6 ]
  [[ "$output" == *"no heartbeat for kitty $KP"* ]] || false
  no_signal
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ]
}

@test "in-flight lands are waited for (by PROGRAM, not by a brief that mentions one); --land-wait bounds it" {
  echo 2 > "$CC_RESTORE_PS_BIN.lands-left"
  run "$SUBJ" --restart-kitty --confirm "$KP" --land-wait 30
  [ "$status" -eq 0 ]
  [ "$(grep -c '^waiting for 1 in-flight lands (pids 777)' <<<"$output")" -eq 2 ]
  echo 999 > "$CC_RESTORE_PS_BIN.lands-left"; rm -f "$CC_RESTORE_BOOT_RESUME.n"
  echo "$KP Thu Oct  1 13:40:01 2026 /Applications/kitty.app/Contents/MacOS/kitty" > "$CC_RESTORE_PS_BIN.kitty"
  rm -rf "$EVENTS"; sleep 1
  run "$SUBJ" --restart-kitty --confirm "$KP" --land-wait 1
  [[ "$output" == *"still 1 land(s) in flight after 1 s; going ahead"* ]] || false
}

# ── limits on kitty's socket ──────────────────────────────────────────────────────────────────────
@test "fd limit: a new kitty holding more than 180 descriptors stops the restore before any launch" {
  echo 200 > "$CC_RESTORE_LSOF_BIN.n"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 6 ]
  [[ "$output" == *"kitty $NEWPID holds 200 file descriptors, over the limit of 180"* ]] || false
  [[ "$output" == *"verdict=STOPPED"* ]] || false
  [ ! -e "$CC_RESTORE_BOOT_RESUME.n" ]
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ]
}

@test "a kitten call that times out is followed by a pause, and calls never overlap" {
  export CC_RESTORE_K_TIMEOUT_S=1 CC_RESTORE_K_BACKOFF_S=2
  : > "$CC_RESTORE_KITTEN_BIN.slow-once"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 0 ]
  [[ "$output" == *"kitty did not answer within 1 s; pausing 2 s before the next call"* ]] || false
  [ "$(grep -c . "$CC_RESTORE_KITTEN_BIN.log")" -eq 2 ]
  t1="$(sed -n 1p "$CC_RESTORE_KITTEN_BIN.log" | cut -d' ' -f1)"; t2="$(sed -n 2p "$CC_RESTORE_KITTEN_BIN.log" | cut -d' ' -f1)"
  [ $((t2 - t1)) -ge 3 ]                                           # 1 s timeout + 2 s pause
}

@test "a new kitty that never answers: exit 5, lock released, no launch" {
  : > "$CC_OPEN_BIN.dead"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 5 ]
  [[ "$output" == *"did not answer on its socket within 4 s"* ]] || false
  [[ "$output" == *"cc-restore --after-crash"* ]] || false
  [ ! -e "$CC_RESTORE_BOOT_RESUME.n" ] && [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ]
}

# ── rounds, partial ───────────────────────────────────────────────────────────────────────────────
@test "the restore runs boot-resume again until the event is marked done" {
  echo 3 > "$CC_RESTORE_BOOT_RESUME.rounds"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_RESTORE_BOOT_RESUME.n")" -eq 3 ]
  [[ "$output" == *"restore round 3:"* ]] || false
  [ "$(grep -c '^load ' <<<"$output")" -eq 3 ]                      # each load line relayed once
}

@test "a session that did not come back makes the verdict PARTIAL (exit 1), and a duplicate is counted" {
  live_after "$S1:7" "$S1:9"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=PARTIAL restored=1/2 maybe=1 dup=1 shed=0"* ]] || false
}

# ── the lock ──────────────────────────────────────────────────────────────────────────────────────
@test "the lock is restore-lock.sh's: a restore holding the lib's lock blocks cc-restore, which signals nothing" {
  /bin/bash -c '. "$1"; restore_lock_take 4242 && sleep 30' _ "$REPO/scripts/lib/restore-lock.sh" & BG=$!
  i=0; while [ ! -f "$CC_BOOT_RESUME_STATE_DIR/restore.lock/holder" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 2 ]
  [[ "$output" == *"another restore holds the lock"* ]] || false
  no_signal
}

@test "…and the other way: while cc-restore holds it the lib refuses (rc 1); a dead holder's lock is reclaimed" {
  echo 999 > "$CC_RESTORE_PS_BIN.lands-left"
  "$SUBJ" --restart-kitty --confirm "$KP" --land-wait 60 > "$BATS_TEST_TMPDIR/bg.out" 2>&1 & BG=$!
  i=0; while [ ! -f "$CC_BOOT_RESUME_STATE_DIR/restore.lock/holder" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  run /bin/bash -c '. "$1"; restore_lock_take 4242' _ "$REPO/scripts/lib/restore-lock.sh"
  [ "$status" -eq 1 ]
  # --abort while it is still waiting for lands: nothing was signalled, the lock is released
  run "$SUBJ" --abort
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped; lock released (phase was: lands)"* ]] || false
  wait "$BG" || true
  grep -q 'verdict=ABORTED .* kitty was not touched, nothing was signalled' "$BATS_TEST_TMPDIR/bg.out"
  [ "$(kills -TERM)" -eq 0 ] && [ ! -e "$CC_OPEN_BIN.log" ] || false
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ] && [ -z "$(find "$EVENTS" -maxdepth 1 -name '*.inprogress')" ] || false
  # a lock left by a holder that died is reclaimed by the next run
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR/restore.lock"
  echo '{"event":"1","pid":1,"lstart":"Thu Jan 1 00:00:00 1970","boot":"UUID-T","at":1}' > "$CC_BOOT_RESUME_STATE_DIR/restore.lock/holder"
  echo 0 > "$CC_RESTORE_PS_BIN.lands-left"
  run "$SUBJ" --restart-kitty --confirm "$KP" --no-wait
  [ "$status" -eq 0 ]
}

@test "--abort after kitty closed stops new launches and says how to bring back the rest" {
  : > "$CC_RESTORE_BOOT_RESUME.hang"
  "$SUBJ" --restart-kitty --confirm "$KP" --no-wait > "$BATS_TEST_TMPDIR/bg.out" 2>&1 & BG=$!
  i=0; while [ ! -s "$CC_RESTORE_BOOT_RESUME.n" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
  run "$SUBJ" --abort
  [ "$status" -eq 0 ]
  wait "$BG" || true
  grep -q 'verdict=ABORTED .* `cc-restore --after-crash` brings back the rest' "$BATS_TEST_TMPDIR/bg.out"
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ]
  [ ! -e "$CC_RESTORE_REBIND_BIN.log" ]                             # not done: nothing to rebind yet
}

@test "--abort with no restore running says so; a dead holder's lock is cleared" {
  run "$SUBJ" --abort
  [ "$status" -eq 0 ]
  [[ "$output" == *"no restore is running"* ]] || false
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR/restore.lock" "$EVENTS"; : > "$EVENTS/7.inprogress"
  echo '{"event":"7","pid":1,"lstart":"Thu Jan 1 00:00:00 1970","boot":"UUID-T","at":1}' > "$CC_BOOT_RESUME_STATE_DIR/restore.lock/holder"
  run "$SUBJ" --abort
  [ "$status" -eq 0 ]
  [ ! -d "$CC_BOOT_RESUME_STATE_DIR/restore.lock" ] && [ ! -e "$EVENTS/7.inprogress" ] || false
  [ ! -e "$CC_RESTORE_KILL_BIN.log" ]
}

# ── --after-crash ─────────────────────────────────────────────────────────────────────────────────
dead_kitty() { # a heartbeat for a kitty pid that is not running
  DK=4141
  mkdir -p "$CC_HEARTBEAT_DIR/UUID-T/$DK"
  printf '[{"session_id":"%s","paneUUID":"249"},{"session_id":"%s","paneUUID":"250"}]' "$S1" "$S2" > "$CC_HEARTBEAT_DIR/UUID-T/$DK/hb.roster.json"
  echo 1784800000 > "$CC_HEARTBEAT_DIR/UUID-T/$DK/hb.start"
  : > "$CC_RESTORE_PS_BIN.kitty"                                    # no kitty at all
}

@test "--after-crash: never kills; opens kitty when none runs; restores the dead kitty's fleet as its own event" {
  dead_kitty
  run "$SUBJ" --after-crash
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"dead kitty: pid $DK"* ]] || false
  [ ! -e "$CC_RESTORE_KILL_BIN.log" ]
  [ "$(cat "$CC_OPEN_BIN.log")" = "-a /Applications/kitty.app" ]
  grep -Eqx "argv: --event [0-9]+ --kind crash --kitty-pid $DK --roster-dir $EVENTS/$DK/hb" "$CC_RESTORE_BOOT_RESUME.log"
  [ -s "$EVENTS/$DK/hb/$DK/hb.roster.json" ]
  [[ "$output" == *"verdict=RESTORED restored=2/2"* ]] || false
  # a second run has nothing left to do
  run "$SUBJ" --after-crash
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to restore"* ]] || false
}

@test "--after-crash with a kitty already up does not open another" {
  dead_kitty
  echo "$NEWPID Mon Oct  5 09:00:00 2026 /Applications/kitty.app/Contents/MacOS/kitty" > "$CC_RESTORE_PS_BIN.kitty"
  : > "$BATS_TEST_TMPDIR/kitty-$NEWPID"
  run "$SUBJ" --after-crash --kitty-pid "$DK"
  [ "$status" -eq 0 ]
  [ ! -e "$CC_OPEN_BIN.log" ]
}

@test "--after-crash on a kitty a planned restart ended continues THAT event, so its ledger keeps counting" {
  dead_kitty
  mkdir -p "$EVENTS/1791000000/hb/$DK"; cp "$CC_HEARTBEAT_DIR/UUID-T/$DK"/* "$EVENTS/1791000000/hb/$DK/"
  echo 1791000000 > "$EVENTS/$DK.planned"
  run "$SUBJ" --after-crash
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"continuing that event"* ]] || false
  grep -qx "argv: --event 1791000000 --kind restart --roster-dir $EVENTS/1791000000/hb" "$CC_RESTORE_BOOT_RESUME.log"
  [ -e "$EVENTS/$DK.done" ]
}

@test "--after-crash --dry-run prints the plan and the commands and launches nothing" {
  dead_kitty
  run "$SUBJ" --after-crash --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dead kitty: pid $DK"* ]] || false
  [[ "$output" == *"--kind crash --kitty-pid $DK --roster-dir $EVENTS/$DK/hb"* ]] || false
  no_signal
  [ ! -d "$EVENTS" ]
}

# ── --compare ─────────────────────────────────────────────────────────────────────────────────────
hb_dir() { # <dir> <kitty-ls os-window id> <pane of S1> <pane of S2> <account of S2>
  mkdir -p "$1"
  printf '[{"session_id":"%s","paneUUID":"%s"},{"session_id":"%s","paneUUID":"%s"}]' "$S1" "$3" "$S2" "$4" > "$1/hb.roster.json"
  printf '%s\tclaude-next\tclaude-opus-5-5\thigh\tauto\tmain\t1\n%s\t%s\tclaude-opus-5-5\t\037\tplan\tfeat\t1\n' "$S1" "$S2" "$5" > "$1/hb.session.tsv"
  printf '[{"id":%s,"platform_window_id":900,"tabs":[{"windows":[{"id":%s},{"id":%s}]}]}]' "$2" "$3" "$4" > "$1/hb.kitty-ls.json"
  printf '900\tDISPLAY-A\t0\t0\t10\t10\t1\t0\t0\t10\t10\n' > "$1/hb.displays.tsv"
  echo 1784800000 > "$1/hb.start"
}
compare_fixture() {
  E="$EVENTS/1791000000"
  hb_dir "$E/hb/4141" 3 249 250 claude-next
  printf 'next\t%s\t/x/a\tmain\tA\tINTERRUPTED\nnext\t%s\t/x/b\tmain\tB\tAT-REST\n' "$S1" "$S2" > "$E/rows.tsv"
  printf '%s\n%s\n' "$S1" "$S2" > "$E/launched"
  echo '2026-10-05T10:00:00Z rebind: forward old=249 → sid=x new_pane=7 writer=lib migrated=0' > "$E/rebind.log"
}

@test "--compare: every session back with the same account, model, effort, mode, window, position and display ⇒ MATCH" {
  compare_fixture
  hb_dir "$BATS_TEST_TMPDIR/after" 1 7 8 claude-next                # new window and pane ids: still the same window
  run "$SUBJ" --compare "$E" --after "$BATS_TEST_TMPDIR/after"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"11111111  match  account claude-next | model claude-opus-5-5 | effort high | permission auto | window w1(2 panes) | position 1 | display DISPLAY-A"* ]] || false
  [[ "$output" == *"rebind: forward old=249"* ]] || false
  [[ "$output" == *"compare verdict=MATCH sessions=2 match=2 diff=0 missing=0 dup=0 maybe=0"* ]] || false
}

@test "--compare: a changed account, a swapped position and a missing session are each named ⇒ DIFF, exit 1" {
  compare_fixture
  hb_dir "$BATS_TEST_TMPDIR/after" 1 8 7 claude-tertiary            # S2 changed account
  printf '[{"id":1,"platform_window_id":900,"tabs":[{"windows":[{"id":7},{"id":8}]}]}]' > "$BATS_TEST_TMPDIR/after/hb.kitty-ls.json"   # and the two swapped places
  run "$SUBJ" --compare "$E" --after "$BATS_TEST_TMPDIR/after"
  [ "$status" -eq 1 ]
  [[ "$output" == *"account claude-next→claude-tertiary ✗"* ]] || false
  [[ "$output" == *"position 1→2 ✗"* ]] || false
  [[ "$output" == *"verdict=DIFF"* ]] || false
  printf '[{"session_id":"%s","paneUUID":"7"}]' "$S1" > "$BATS_TEST_TMPDIR/after/hb.roster.json"
  sed -i '' 2d "$BATS_TEST_TMPDIR/after/hb.session.tsv"
  run "$SUBJ" --compare "$E" --after "$BATS_TEST_TMPDIR/after"
  [ "$status" -eq 1 ]
  [[ "$output" == *"11111111  MISSING: not live after the restore"* ]] || false   # the 8-char prefix is shared; one line says MISSING
  [[ "$output" == *"missing=1"* ]] || false
  [[ "$output" == *"maybe=1"* ]] || false
}

@test "--compare on a dir with no snapshot is a usage error, not a pass" {
  mkdir -p "$EVENTS/5"
  run "$SUBJ" --compare "$EVENTS/5"
  [ "$status" -eq 2 ]
}

@test "runs under the system python3 (the launchd and Terminal.app interpreter)" {
  run /usr/bin/python3 "$SUBJ" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--restart-kitty --confirm <pid>"* ]] || false
}
