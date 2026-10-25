#!/usr/bin/env bats
# compressor-sentinel-lockup.bats — the sentinel as LOCKWATCH HOST and the guards on its own killer
# (incident 2026-10-25; ~/incident-2026-10-25/solution/DESIGN.md C2 and the C7 host half).
#
#   (a) lockprobe respawn is rate-limited, a crashloop pages once; a live same-boot lockprobe is
#       ADOPTED, never spawned over; a pidfile whose lstart no longer matches is never signalled
#   (b) a forensics step listed in active.pids is never selected by the compressor actuator
#   (c) with the kill rung armed, an `expect` custody row and a pty-leader row survive retrip-over-debt
#   (d) a `ps` that never returns cannot stop the tick writing its row
#   (e) a cc-fleet STALLED fixture pages exactly once per episode
#   (f) the freeze row's boot-class pointer is idempotent, and the boot-class page fires once
#
# Every daemon run is a --ticks run under `perl -e 'alarm N; exec'`, so a regression that hangs fails
# instead of wedging the suite. No case reads or writes the live ~/.claude: HOME is the test dir and
# every lockwatch path is redirected. Stray children are reaped by the pids the stubs recorded.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/compressor-sentinel.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs" "$HOME/.claude/autonomy/pages"
  [ -f "$S" ] || false
  sed -n '/^[a-z_]*() {/,/^}/p' "$S" > "$D/lib.sh"
  bash -n "$D/lib.sh" || false
  STUB="$D/stub"; mkdir -p "$STUB" "$D/lw" "$D/pages"
  : > "$D/reap.pids"
  # lr-page stand-in: records one line per page, never posts anything.
  cc_stub "$STUB" lrpage.sh "$(printf '#!/bin/bash\nprintf "CALL %%s\\n" "$(printf "%%s" "$*" | tr "\\n" " ")" >> "%s/lrpage.calls"\n' "$D")"
  # The host runs lr-page as `/bin/bash <path>`, so it gets the stub's BODY path (under cc-shim the
  # stub itself is a link to a Mach-O, which bash cannot read as a script).
  LRPAGE="$(cc_stub_body "$STUB" lrpage.sh)"
}

teardown() {
  local p
  while read -r p; do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    kill -KILL "$p" 2>/dev/null || true      # test-owned sleeps/stubs only: no tty, not session leaders
  done < "$D/reap.pids"
}

# A bounded daemon run that can never trip the compressor axis (real vm sysctls, impossible
# thresholds), with the lockwatch host switched on and every path in the test dir.
run_host() { # <ticks> — extra env via exported vars
  run perl -e '$SIG{ALRM} = "DEFAULT"; alarm 90; exec @ARGV' -- env \
    CC_SENTINEL_LOG="$D/s.jsonl" CC_PAGES_DIR="$D/pages" CC_LOCKWATCH_DIR="$D/lw" \
    CC_SENTINEL_RUN_DIR="$D/br" CC_SENTINEL_LR_PAGE="$LRPAGE" \
    CC_SENTINEL_INTERVAL=1 CC_PANIC_SCAN=off CC_FREEZE_SCAN=off CC_SENTINEL_BOOT_CLASSIFY=off \
    CC_SENTINEL_TRIP_SEG_PCT=1000 CC_SENTINEL_TRIP_SEG_RATE=999999999 CC_SENTINEL_TRIP_CBU_MB=99999999 \
    CC_SENTINEL_TRIP_SWAP_MB=99999999 CC_SENTINEL_CLIFF_PCT=1000 CC_SENTINEL_CENSUS_EVERY=1000 \
    CC_SENTINEL_LOCKWATCH_BOUNDED=1 CC_SENTINEL_BOOTUUID=test-boot \
    /bin/bash "$S" --ticks "$1"
}

# A fake interpreter: lp_tick runs "$PY -I <script> run". It records "<epoch> <pid>" and then does
# what FAKE_LP says: exit with that rc, or `sleep` (stay alive), or `sleep-pidfile` (stay alive and
# write the lockprobe pidfile the way lane A's lockprobe does).
mkfakepy() {
  cc_stub "$STUB" fakepy - <<SH
#!/bin/bash
printf '%s %s\n' "\$(date +%s)" "\$\$" >> "$D/spawns"
echo "\$\$" >> "$D/reap.pids"
case "\${FAKE_LP:-1}" in
  sleep) exec sleep 60 ;;
  *) exit "\${FAKE_LP:-1}" ;;
esac
SH
  : > "$D/lp.py"
  export CC_LOCKPROBE_PY="$STUB/fakepy" CC_LOCKPROBE_SCRIPT="$D/lp.py"
}

spawns() { [ -f "$D/spawns" ] && wc -l < "$D/spawns" | tr -d ' ' || echo 0; }
# lr-page runs DETACHED (never awaited), so a count taken the instant `run` returns can race it. Wait
# until the count is unchanged for half a second, at most ~5 s.
pages() {
  local n=-1 m i=0
  while [ "$i" -lt 50 ]; do
    m="$([ -f "$D/lrpage.calls" ] && wc -l < "$D/lrpage.calls" | tr -d ' ' || echo 0)"
    if [ "$m" = "$n" ] && [ "$i" -ge 5 ]; then break; fi
    n="$m"; i=$((i + 5)); sleep 0.5
  done
  echo "$n"
}

# ══ (a) lockprobe host ════════════════════════════════════════════════════════════════════════════

@test "(a) respawn is rate-limited to once per CC_LOCKPROBE_RESPAWN_S and a crashloop pages ONCE" {
  mkfakepy
  export FAKE_LP=1 CC_LOCKPROBE_RESPAWN_S=3 CC_LOCKPROBE_LOOP_N=2 CC_SENTINEL_FLEET=off
  run_host 8
  [ "$status" -eq 0 ] || false
  n="$(spawns)"
  [ "$n" -ge 2 ] || false                       # positive control: it does respawn
  # Every gap between consecutive spawn DECISIONS honours the rate limit (the host logs the epoch it
  # decided at; the fake interpreter's own clock lags it by a variable exec delay under load).
  printf '%s\n' "$output" | sed -n 's/.*lockprobe SPAWN pid=[0-9]* at=\([0-9]*\).*/\1/p' > "$D/at"
  [ "$(wc -l < "$D/at" | tr -d ' ')" -ge 2 ] || false
  awk 'NR > 1 && $1 - prev < 3 { bad = 1 } { prev = $1 } END { exit bad }' "$D/at" || false
  [ -f "$D/pages/lockprobe-crashloop.page" ] || false
  [ "$(pages)" -eq 1 ] || false                 # the 3rd death is inside the same episode: no re-page
  grep -q 'crashloop' "$D/lrpage.calls" || false
  [ "$(awk -F'\t' '$2 == 1' "$D/lw/host/lockprobe-deaths.tsv" | wc -l | tr -d ' ')" -ge 2 ] || false
}

@test "(a) a clean exit (rc 0: the lease is held elsewhere) respawns but never counts toward a crashloop" {
  mkfakepy
  export FAKE_LP=0 CC_LOCKPROBE_RESPAWN_S=2 CC_LOCKPROBE_LOOP_N=1 CC_SENTINEL_FLEET=off
  run_host 5
  [ "$(spawns)" -ge 2 ] || false
  [ ! -s "$D/lw/host/lockprobe-deaths.tsv" ] || false
  [ ! -e "$D/pages/lockprobe-crashloop.page" ] || false
  [ "$(pages)" -eq 0 ] || false
}

@test "(a) a live same-boot lockprobe named by a matching pidfile is ADOPTED — no spawn over it" {
  mkfakepy
  export CC_SENTINEL_FLEET=off
  sleep 60 & lp=$!; echo "$lp" >> "$D/reap.pids"
  ep="$(bash -c '. "$1"; lp_lstart_epoch "$2"' _ "$D/lib.sh" "$lp")"
  [ -n "$ep" ] || false
  printf '%s %s test-boot\n' "$lp" "$ep" > "$D/lw/lockprobe.pid"
  run_host 4
  [ "$status" -eq 0 ] || false
  [ "$(spawns)" -eq 0 ] || false
  printf '%s\n' "$output" | grep -q "lockprobe adopted pid $lp" || false
  ! printf '%s\n' "$output" | grep -q 'MISMATCH' || false
  kill -0 "$lp" || false                        # never signalled
  [ "$(tail -1 "$D/s.jsonl" | jq -r .lp_pid)" = "$lp" ] || false
}

@test "(a) a pidfile whose lstart no longer matches its pid is treated as dead — and NEVER signalled" {
  mkfakepy
  export FAKE_LP=sleep CC_SENTINEL_FLEET=off
  sleep 60 & lp=$!; echo "$lp" >> "$D/reap.pids"
  printf '%s 1000000000 test-boot\n' "$lp" > "$D/lw/lockprobe.pid"   # a reused pid: wrong start time
  run_host 5
  [ "$status" -eq 0 ] || false
  printf '%s\n' "$output" | grep -q "identity MISMATCH" || false
  [ "$(spawns)" -ge 1 ] || false                # the host then spawns its own
  kill -0 "$lp" || false                        # and the impostor was never touched
}

@test "(a) the kill switch spawns nothing, and the host is off in a plain --ticks run" {
  mkfakepy
  export CC_SENTINEL_LOCKPROBE=off CC_SENTINEL_FLEET=off
  run_host 2
  [ "$(spawns)" -eq 0 ] || false
  unset CC_SENTINEL_LOCKPROBE
  run perl -e '$SIG{ALRM} = "DEFAULT"; alarm 60; exec @ARGV' -- env CC_SENTINEL_LOG="$D/t.jsonl" CC_PAGES_DIR="$D/pages" \
    CC_LOCKWATCH_DIR="$D/lw" CC_SENTINEL_INTERVAL=1 CC_PANIC_SCAN=off CC_FREEZE_SCAN=off \
    CC_SENTINEL_CENSUS_EVERY=1000 CC_SENTINEL_TRIP_SEG_PCT=1000 CC_SENTINEL_CLIFF_PCT=1000 \
    /bin/bash "$S" --ticks 2
  [ "$status" -eq 0 ] || false
  [ "$(spawns)" -eq 0 ] || false
  [ "$(tail -1 "$D/t.jsonl" | jq -r .lp_pid)" = "null" ] || false
}

# ══ (b) the forensics never-list ═════════════════════════════════════════════════════════════════

@test "(b) a sample pid listed in active.pids is never selected; the same shape unlisted is (control)" {
  printf '5001 1 200000 sample /usr/bin/sample 0\n5002 1 200000 sample /usr/bin/sample 0\n5003 1 200000 sample /usr/bin/sample 0\n' > "$D/exe"
  printf '5001 1 200000 /usr/bin/sample 777 2 -file /tmp/x\n5002 1 200000 /usr/bin/sample 778 2 -file /tmp/y\n5003 1 200000 /usr/bin/sample 779 2 -file %s/Library/Logs/cc-forensics/z\n' "$HOME" > "$D/ps"
  run bash -c '. "$1"; select_stop_targets "$2" "1 2" 102400 10 " 5001 " < "$3"' _ "$D/lib.sh" "$D/exe" "$D/ps"
  [ "$status" -eq 0 ] || false
  ! printf '%s\n' "$output" | grep -q '^5001 ' || false     # on the never-list
  printf '%s\n' "$output" | grep -q '^5002 ' || false       # control: same shape, selected
  ! printf '%s\n' "$output" | grep -q '^5003 ' || false     # a cc-forensics argv is spared by name too
}

@test "(b) fx_never_list keeps live same-boot rows only, and reads nothing when the host is off" {
  sleep 60 & live=$!; echo "$live" >> "$D/reap.pids"
  printf '%s 1 test-boot\n999999 1 test-boot\n%s 1 old-boot\n' "$live" "$live" > "$D/active.pids"
  run bash -c '. "$1"; LW_HOST=1 LW_BOOT=test-boot FX_ACTIVE="$2"; fx_never_list' _ "$D/lib.sh" "$D/active.pids"
  [ "$output" = " $live " ] || false
  run bash -c '. "$1"; LW_BOOT=test-boot FX_ACTIVE="$2"; fx_never_list' _ "$D/lib.sh" "$D/active.pids"
  [ "$output" = " " ] || false
}

# ══ (c) the pty guard on the kill rung ═══════════════════════════════════════════════════════════

mkpsmap() { # TAB rows "pid<TAB>lstart"; the stub prints "T <lstart>" for -o stat=,lstart=
  printf '%s\n' "$1" > "$D/psmap"
  cc_stub "$STUB" ps - <<'SH'
#!/bin/bash
pid=""; o=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-p" ]; then pid="$2"; shift; elif [ "$1" = "-o" ]; then o="$2"; shift; fi
  shift
done
[ -n "$pid" ] || exit 0
case "$o" in
  *stat=*) awk -F'\t' -v p="$pid" '$1==p { print "T " $2 }' "$PSMAP" ;;
  *)       awk -F'\t' -v p="$pid" '$1==p { print $2 }' "$PSMAP" ;;
esac
SH
}

run_kill() { # <now> — kill_escalate over $D/fdb, kill(1) recorded, never sent
  printf '1 0 0 launchd /sbin/launchd 1\n' > "$D/exef"
  : > "$D/kill.log"; : > "$D/snap.log"
  run env PATH="$STUB:$PATH" PSMAP="$D/psmap" FROZEN_DB="$D/fdb" SNAP="$D/snap.log" KILLLOG="$D/kill.log" \
    KILL_MIN_HOLD_S=30 RELINQUISH_GRACE_S=30 LW_BOOT=test-boot PTY_JSON="$D/pty.json" \
    LW_HOST="${LW_HOST:-0}" FX_ACTIVE="$D/active.pids" CC_SENTINEL_RUN_DIR="$D/br" \
    bash -c 'set -uo pipefail; kill() { printf "%s\n" "$*" >> "$KILLLOG"; return 0; }; . "$1"; kill_escalate "$2" retrip-over-debt "$3"' \
    _ "$D/lib.sh" "$1" "$D/exef"
}

@test "(c) KILL armed: an expect row and a pty-leader row survive retrip-over-debt; a node row dies (control)" {
  now="$(date +%s)"
  mkpsmap "$(printf '6001\tMon 26 Oct 01:00:00 2026\n6002\tMon 26 Oct 01:00:01 2026\n6003\tMon 26 Oct 01:00:02 2026')"
  printf '6001\tMon 26 Oct 01:00:00 2026\tproc\t%s\texpect\n6002\tMon 26 Oct 01:00:01 2026\tproc\t%s\tbash\n6003\tMon 26 Oct 01:00:02 2026\tproc\t%s\tnode\n' \
    $((now - 300)) $((now - 300)) $((now - 300)) > "$D/fdb"
  printf '{"v":1,"ts_epoch":%s,"boot":"test-boot","ttl_s":90,"leaders":[{"pid":6002,"pgid":6002,"tdev":"16/63","ppid":1,"state":"Ss"}],"master_holders":{"63":[4242]},"slave_holders":{},"orphan_slaves":[],"members_open":[]}\n' "$now" > "$D/pty.json"
  run_kill "$now"
  [ "$status" -eq 0 ] || false
  [ "$output" = "killed=1 spared=2" ] || false
  grep -qx -- '-KILL 6003' "$D/kill.log" || false            # positive control: the rung is live
  ! grep -q -- '-KILL 6001' "$D/kill.log" || false
  ! grep -q -- '-KILL 6002' "$D/kill.log" || false
  grep -q 'pid=6001 .*reason=pty-guard-comm' "$D/snap.log" || false
  grep -q 'pid=6002 .*reason=pty-guard$' "$D/snap.log" || false
  [ ! -s "$D/fdb" ] || false                                  # spared rows were resumed and dropped
}

@test "(c) a STALE pty.json guards nothing beyond the comm list — the pty-leader bash row is killed" {
  now="$(date +%s)"
  mkpsmap "$(printf '6002\tMon 26 Oct 01:00:01 2026')"
  printf '6002\tMon 26 Oct 01:00:01 2026\tproc\t%s\tbash\n' $((now - 300)) > "$D/fdb"
  printf '{"v":1,"ts_epoch":%s,"boot":"test-boot","ttl_s":90,"leaders":[{"pid":6002}]}\n' $((now - 600)) > "$D/pty.json"
  run_kill "$now"
  grep -qx -- '-KILL 6002' "$D/kill.log" || false
}

@test "(c) a custody row whose pid is a live forensics step is resumed, never killed (never-list)" {
  now="$(date +%s)"
  mkpsmap "$(printf '6004\tMon 26 Oct 01:00:04 2026')"
  printf '6004\tMon 26 Oct 01:00:04 2026\tproc\t%s\tsample\n' $((now - 300)) > "$D/fdb"
  printf '6004 1 test-boot\n' > "$D/active.pids"
  LW_HOST=1 run_kill "$now"
  ! grep -q -- '-KILL 6004' "$D/kill.log" || false
  grep -qx -- '-CONT 6004' "$D/kill.log" || false
  grep -q 'reason=never-list' "$D/snap.log" || false
}

@test "(c) an ABANDONED identity read holds the row: never killed, never dropped" {
  now="$(date +%s)"
  cc_stub "$STUB" ps "$(printf '#!/bin/bash\necho $$ >> "%s/reap.pids"\nexec sleep 60\n' "$D")"
  printf '6005\tMon 26 Oct 01:00:05 2026\tproc\t%s\tnode\n' $((now - 300)) > "$D/fdb"
  CC_SENTINEL_PS_DEADLINE_S=1 run_kill "$now"
  [ "${lines[${#lines[@]}-1]}" = "killed=0 spared=1" ] || { echo "out=<$output>"; false; }
  [[ "$output" == *"ABANDON statls"* ]] || false               # the read really was abandoned
  ! grep -q -- '-KILL 6005' "$D/kill.log" || false
  [ "$(cut -f1 "$D/fdb")" = "6005" ] || false
}

# ══ (d) a ps that never returns ══════════════════════════════════════════════════════════════════

@test "(d) with a stub ps that never returns, every tick still writes its row (and stuck reads are capped)" {
  cc_stub "$STUB" ps "$(printf '#!/bin/bash\necho $$ >> "%s/reap.pids"\necho x >> "%s/ps.calls"\nexec sleep 300\n' "$D" "$D")"
  t0="$(date +%s)"
  run perl -e '$SIG{ALRM} = "DEFAULT"; alarm 60; exec @ARGV' -- env PATH="$STUB:$PATH" CC_SENTINEL_LOG="$D/s.jsonl" \
    CC_PAGES_DIR="$D/pages" CC_SENTINEL_RUN_DIR="$D/br" CC_SENTINEL_INTERVAL=1 CC_PANIC_SCAN=off \
    CC_FREEZE_SCAN=off CC_SENTINEL_CENSUS_EVERY=1 CC_SENTINEL_PS_DEADLINE_S=2 \
    CC_SENTINEL_TRIP_SEG_PCT=1000 CC_SENTINEL_CLIFF_PCT=1000 /bin/bash "$S" --ticks 4
  [ "$status" -eq 0 ] || false
  [ "$(wc -l < "$D/s.jsonl" | tr -d ' ')" -eq 4 ] || false
  [ $(( $(date +%s) - t0 )) -lt 50 ] || false
  printf '%s\n' "$output" | grep -q 'ABANDON exeu' || false
  # cap: each census makes two reads (exec names, table); two stuck per read key, then no more forks
  [ "$(wc -l < "$D/ps.calls" | tr -d ' ')" -le 4 ] || false
  tail -1 "$D/s.jsonl" | jq -e '.n == null' > /dev/null || false   # blind census: null, never a 0
}

@test "(d) a FRESH procscan.json feeds the census with no ps fork at all" {
  cc_stub "$STUB" ps "$(printf '#!/bin/bash\necho x >> "%s/ps.calls"\n' "$D")"
  now="$(date +%s)"
  printf '{"v":1,"ts_epoch":%s,"boot":"test-boot","procs":[{"pid":7001,"ppid":1,"comm":"node","rss_mb":300,"path":"/opt/homebrew/bin/node"},{"pid":7002,"ppid":7001,"comm":"node","rss_mb":10,"path":"/opt/homebrew/bin/node"}]}\n' "$now" > "$D/procscan.json"
  run env PATH="$STUB:$PATH" CC_SENTINEL_RUN_DIR="$D/br" bash -c '. "$1"; LW_BOOT=test-boot LW_PROCSCAN="$2"; census_read 102400' _ "$D/lib.sh" "$D/procscan.json"
  [ "$status" -eq 0 ] || false
  [ "$output" = "2 1 310| 7001" ] || false   # 2 node, 1 orphan, 310 MB; only 7001 clears the floor
  [ ! -e "$D/ps.calls" ] || false
}

# ══ (e) producer freshness via cc-fleet ═════════════════════════════════════════════════════════

mkfleet() { # <json rows…>
  cc_stub "$STUB" fleet "$({ printf '#!/bin/bash\n'; for r in "$@"; do printf "echo '%s'\n" "$r"; done; })"
  # run as `/bin/bash <path>` by the host, so the BODY path (see LRPAGE in setup)
  CC_SENTINEL_FLEET_BIN="$(cc_stub_body "$STUB" fleet)"
  export CC_SENTINEL_FLEET_BIN CC_SENTINEL_FLEET_EVERY_S=1 CC_SENTINEL_LOCKPROBE=off
}

@test "(e) two STALLED labels (corroborated) → ONE page across repeated cc-fleet runs" {
  mkfleet '{"kind":"fleet-inert","state":"STALLED","detail":"evidence 900s old","subject":"com.claude.a"}' \
          '{"kind":"fleet-inert","state":"STALLED","detail":"evidence 950s old","subject":"com.claude.b"}'
  run_host 6
  [ "$status" -eq 0 ] || false
  [ "$(pages)" -eq 1 ] || { echo "$output"; cat "$D/lrpage.calls"; false; }
  [ -f "$D/pages/fleet-producers.page" ] || false
  grep -q 'com.claude.a' "$D/pages/fleet-producers.page" || false
  grep -q 'com.claude.b' "$D/pages/fleet-producers.page" || false
  [ "$(awk -F'\t' '$3 == 1' "$D/lw/host/fleet-episodes.tsv" | wc -l | tr -d ' ')" -eq 2 ] || false
}

@test "(e) ONE uncorroborated FAILING label waits CC_SENTINEL_FLEET_SOLO_S before paging" {
  mkfleet '{"kind":"fleet-inert","state":"FAILING","detail":"exit 1","subject":"com.claude.c"}'
  export CC_SENTINEL_FLEET_SOLO_S=3600
  run_host 3
  [ "$(pages)" -eq 0 ] || false                 # uncorroborated and young: no page yet
  export CC_SENTINEL_FLEET_SOLO_S=0
  run_host 3
  [ "$(pages)" -eq 1 ] || false
}

# ══ (f) the boot classifier, host half ═══════════════════════════════════════════════════════════

@test "(f) the freeze row carries the boot-class pointer, and a re-run writes no second row" {
  mkdir -p "$D/rc" "$D/panics"
  cc_stub "$STUB" sysctl - <<'SH'
#!/bin/bash
case "$2" in
  kern.boottime) printf '{ sec = 1786686149, usec = 597125 }\n' ;;
  kern.shutdownreason) printf 'btn_rst,finger_reset force_off\n' ;;
  *) exit 1 ;;
esac
SH
  printf 'Reset count: 0\nBoot faults: btn_rst,finger_reset force_off\n' > "$D/rc/ResetCounter-2026-08-13-224317.diag"
  touch -t "$(date -r 1786686149 '+%Y%m%d%H%M')" "$D/rc/ResetCounter-2026-08-13-224317.diag"
  for i in 1 2; do
    run env CC_FREEZE_RESET_DIRS="$D/rc" CC_PANIC_DIRS="$D/panics" CC_PANIC_LEDGER="$D/fz.jsonl" \
      CC_FREEZE_SAMPLERS="$D/none.jsonl" CC_LOCKWATCH_DIR="$D/lw" PATH="$STUB:$PATH" /bin/bash "$S" --freeze-scan
    [ "$status" -eq 0 ] || false
  done
  [ "$(wc -l < "$D/fz.jsonl" | tr -d ' ')" -eq 1 ] || false
  jq -e --arg p "$D/lw/boot-1786686149.json" '.kind == "freeze" and .boot_class == $p' "$D/fz.jsonl" > /dev/null || false
}

run_bc() { # <class-json or empty> — one bc_page_tick in a fresh process
  run env CC_SENTINEL_RUN_DIR="$D/br" bash -c '. "$1"; LW_DIR="$2/lw"; LW_HOST_DIR="$2/lw/host"; PAGES_DIR="$2/pages"
    LR_PAGE="$3"; BC_MODE=on; BOOT_EPOCH=1786686149; now="$(date +%s)"
    bc_page_tick "$now" "$now"; bc_page_tick "$now" "$now"' _ "$D/lib.sh" "$D" "$LRPAGE"
}

@test "(f) a LOCKUP_DEVFS verdict pages exactly once, across ticks AND across restarts" {
  printf '{"v":1,"class":"LOCKUP_DEVFS","confidence":"high","summary":"devfs_poison(ttys063) leader 68298"}\n' > "$D/lw/boot-1786686149.json"
  run_bc; [ "$status" -eq 0 ] || false
  run_bc
  [ "$(pages)" -eq 1 ] || false
  [ -f "$D/pages/boot-class-1786686149.page" ] || false
  grep -q 'LOCKUP_DEVFS' "$D/pages/boot-class-1786686149.page" || false
}

@test "(f) CLEAN and a panic boot (class null) page nothing, but are marked done" {
  printf '{"v":1,"class":"CLEAN"}\n' > "$D/lw/boot-1786686149.json"
  run_bc
  [ "$(pages)" -eq 0 ] || false
  [ -e "$D/lw/host/boot-class-1786686149.paged" ] || false
  rm -f "$D/lw/host/boot-class-1786686149.paged"
  printf '{"v":1,"class":null,"deferred_to":"panic_scan"}\n' > "$D/lw/boot-1786686149.json"
  run_bc
  [ "$(pages)" -eq 0 ] || false
}

# ══ migration 0082: the Interactive band (H7) ═════════════════════════════════════════════════════

mklaunchctl() { # stub: state in $D/lc.state ("unloaded" | "daemon" | "interactive"); calls in $D/lc.calls
  cc_stub "$STUB" launchctl - <<'SH'
#!/bin/bash
echo "$*" >> "$LC_CALLS"
st="$(cat "$LC_STATE")"
case "$1" in
  print) [ "$st" = unloaded ] && exit 113; [ "$st" = interactive ] && echo '	spawn type = interactive (4)' || echo '	spawn type = daemon (3)' ;;
  bootout) echo unloaded > "$LC_STATE" ;;
  bootstrap) if /usr/libexec/PlistBuddy -c 'Print :ProcessType' "$3" 2>/dev/null | grep -qx Interactive; then echo interactive; else echo daemon; fi > "$LC_STATE" ;;
esac
SH
  mkdir -p "$D/la"
  export LC_STATE="$D/lc.state" LC_CALLS="$D/lc.calls" CC_0082_LAUNCHCTL="$STUB/launchctl" \
         CC_MIGRATION_LA_DIR="$D/la" CC_MIGRATION_REPO="$REPO" CC_SENTINEL_FROZEN_DB="$D/frozen.tsv" \
         CC_0082_UNLOAD_WAIT_S=2
  : > "$D/lc.calls"
}
M() { bash "$REPO/migrations/0082-sentinel-interactive-band.sh" "$@"; }
keyless_live() { # the pre-0082 installed copy: the repo plist minus its ProcessType key
  cp "$REPO/launchd/com.claude.compressor-sentinel.plist" "$D/la/com.claude.compressor-sentinel.plist"
  /usr/libexec/PlistBuddy -c 'Delete :ProcessType' "$D/la/com.claude.compressor-sentinel.plist" > /dev/null
}

@test "0082: the repo plist declares ProcessType Interactive (the SSOT the migration installs)" {
  [ "$(/usr/libexec/PlistBuddy -c 'Print :ProcessType' "$REPO/launchd/com.claude.compressor-sentinel.plist")" = Interactive ] || false
}

@test "0082: a bare run is a dry run — nothing installed, nothing reloaded" {
  mklaunchctl; echo daemon > "$D/lc.state"
  keyless_live
  run M
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"dry run — nothing changed"* ]] || false
  ! grep -qE 'bootout|bootstrap' "$D/lc.calls" || false
  run M --verify
  [ "$status" -eq 1 ] || false
}

@test "0082: --confirm launchd backs up, installs, reloads, and --verify then reads it back as live" {
  mklaunchctl; echo daemon > "$D/lc.state"
  keyless_live
  run M --confirm launchd
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ls "$D"/la/com.claude.compressor-sentinel.plist.bak-0082-* > /dev/null || false
  cmp -s "$REPO/launchd/com.claude.compressor-sentinel.plist" "$D/la/com.claude.compressor-sentinel.plist" || false
  grep -q '^bootout' "$D/lc.calls" || false
  grep -q '^bootstrap' "$D/lc.calls" || false
  run M --verify
  [ "$status" -eq 0 ] || false
  run M --confirm launchd                      # idempotent
  [[ "$output" == *"already applied"* ]] || false
  run M --undo
  [ "$status" -eq 0 ] || false
  [ "$(cat "$D/lc.state")" = daemon ] || false
}

@test "0082: refuses (75) to bounce the sentinel while it owes SIGCONT to frozen pids" {
  mklaunchctl; echo daemon > "$D/lc.state"
  keyless_live
  printf '123\tMon\tproc\t1\tnode\n' > "$D/frozen.tsv"
  run M --confirm launchd
  [ "$status" -eq 75 ] || false
  ! grep -qE 'bootout|bootstrap' "$D/lc.calls" || false
}
