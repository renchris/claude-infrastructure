#!/usr/bin/env bats
# scripts/lockwatch/boot_classify.py (DESIGN C7, logic half). Every input is a fixture under
# $BATS_TEST_TMPDIR: report dirs, logs, lockwatch state and transcripts. No log collect runs
# (CC_BC_NO_LOG=1); the fixtures are excerpts of the real converted stall reports.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  BC="$REPO/scripts/lockwatch/boot_classify.py"
  FX="$REPO/tests/fixtures/lockwatch"
  for c in /Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11 \
    /Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 \
    /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 \
    /usr/bin/python3; do
    if [ -x "$c" ]; then PY="$c"; break; fi
  done
  export CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lw" CC_FX_ROOT="$BATS_TEST_TMPDIR/fx"
  export CC_BC_REPORT_DIRS="$BATS_TEST_TMPDIR/reports" CC_BC_LOGS_DIR="$BATS_TEST_TMPDIR/logs"
  export CC_BC_NO_LOG=1 CC_BC_BOOT=FIXTURE-CUR-BOOT CC_BC_SHUTDOWN_REASON="ap_shutdown"
  mkdir -p "$CC_LOCKWATCH_DIR/run/FIXTURE-PREV-BOOT" "$CC_FX_ROOT" "$CC_BC_REPORT_DIRS" "$CC_BC_LOGS_DIR"
  export CC_FX_TRANSCRIPT_ROOTS="$BATS_TEST_TMPDIR/tr"
  cp -R "$FX/incident/transcripts" "$CC_FX_TRANSCRIPT_ROOTS"
  touch "$CC_FX_TRANSCRIPT_ROOTS"/*/*.jsonl
  # wtmp stub: the previous boot started 10-21 14:06 (hermetic; the real `last` reads this box)
  printf '#!/bin/bash\necho "reboot time                                Sun Oct 25 13:16"\necho "reboot time                                Wed Oct 21 14:06"\n' >"$BATS_TEST_TMPDIR/last"
  chmod +x "$BATS_TEST_TMPDIR/last"
  export CC_BC_LAST="$BATS_TEST_TMPDIR/last"
  EPOCH=1792952212          # 2026-10-25 13:16:52 CDT, the boot after the incident
  RT=202610251315           # report mtime: 13:15 local, just before that boot
}

classify() { perl -e 'alarm 120; exec @ARGV' -- "$PY" -I "$BC" run --boot-epoch "$EPOCH" "$@"; }
out() { echo "$CC_LOCKWATCH_DIR/boot-$EPOCH.json"; }
field() { "$PY" -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2]))' "$(out)" "$1"; }
report() { cp "$FX/stall/$1" "$CC_BC_REPORT_DIRS/$2"; touch -t "$RT" "$CC_BC_REPORT_DIRS/$2"; }

@test "the 10-25 shutdown-stall excerpt classifies LOCKUP_DEVFS, high confidence, first signal 03:50:19, cause attributed" {
  report shutdown_stall_2026-10-25-excerpt.shutdownStall shutdown_stall_2026-10-25-131537_X.shutdownStall
  run classify
  [ "$status" -eq 0 ]
  [ "$(field class)" = LOCKUP_DEVFS ]
  [ "$(field confidence)" = high ]
  [ "$(field first_signal_ts)" = 2026-10-25T08:50:19Z ]
  grep -q 'kill -KILL 94459 68298' "$(out)"
  grep -q 'zombie_leaders=\[68298' "$(out)"
}

@test "mutant: the same report with the lstat leaves renamed is not LOCKUP_DEVFS (the signature is the user-frame leaf)" {
  sed 's/lstat + 8/stat64 + 8/' "$FX/stall/shutdown_stall_2026-10-25-excerpt.shutdownStall" \
    >"$CC_BC_REPORT_DIRS/shutdown_stall_2026-10-25-131537_X.shutdownStall"
  touch -t "$RT" "$CC_BC_REPORT_DIRS/shutdown_stall_2026-10-25-131537_X.shutdownStall"
  run classify
  [ "$status" -eq 0 ]
  [ "$(field class)" != LOCKUP_DEVFS ]
}

@test "the 10-21 stall (no tty pattern) classifies CLEAN" {
  report shutdown_stall_2026-10-21-excerpt.shutdownStall shutdown_stall_2026-10-21-140204_X.shutdownStall
  run classify
  [ "$status" -eq 0 ]
  [ "$(field class)" = CLEAN ]
}

@test "a .panic boot gets no class: deferred to panic_scan" {
  report panic-full-fixture.panic panic-full-2026-10-25-131000.0002.panic
  report shutdown_stall_2026-10-25-excerpt.shutdownStall shutdown_stall_2026-10-25-131537_X.shutdownStall
  run classify
  [ "$status" -eq 0 ]
  [ "$(field class)" = None ]
  [ "$(field deferred_to)" = panic_scan ]
}

@test "no evidence: LOCKUP_UNKNOWN only when kern.shutdownreason says force_off, else CLEAN" {
  CC_BC_SHUTDOWN_REASON="force_off ap_shutdown" run classify
  [ "$status" -eq 0 ]
  [ "$(field class)" = LOCKUP_UNKNOWN ]
  rm -f "$(out)"
  rm -rf "$CC_FX_ROOT/FIXTURE-CUR-BOOT-postboot"
  CC_BC_SHUTDOWN_REASON="ap_shutdown" run classify
  [ "$(field class)" = CLEAN ]
}

@test "preserve runs before classify: the copy is kept, and a source report deleted afterwards still classifies" {
  report shutdown_stall_2026-10-25-excerpt.shutdownStall shutdown_stall_2026-10-25-131537_X.shutdownStall
  printf '{"ts":"2026-10-25T08:50:30Z","boot":"FIXTURE-PREV-BOOT","from":0,"to":2,"verdict":"devfs_poison(ttys063)"}\n' \
    >"$CC_LOCKWATCH_DIR/levels.jsonl"
  run classify
  [ "$status" -eq 0 ]
  pd="$CC_FX_ROOT/FIXTURE-CUR-BOOT-postboot"
  [ -f "$pd/DiagnosticReports/shutdown_stall_2026-10-25-131537_X.shutdownStall" ]
  [ -f "$pd/lockwatch/levels.jsonl" ]
  [ -f "$pd/.preserved" ]
  [ "$(field preserved_dir)" = "$pd" ]
  rm "$CC_BC_REPORT_DIRS/shutdown_stall_2026-10-25-131537_X.shutdownStall"
  run classify --force
  [ "$status" -eq 0 ]
  [ "$(field class)" = LOCKUP_DEVFS ]
}

@test "a re-run is idempotent: the boot file is not rewritten (the sentinel pages once per boot)" {
  report shutdown_stall_2026-10-21-excerpt.shutdownStall shutdown_stall_2026-10-21-140204_X.shutdownStall
  run classify
  [ "$status" -eq 0 ]
  m1="$(stat -f %m:%i "$(out)")"; s1="$(shasum "$(out)")"
  sleep 1.1
  run classify
  [ "$status" -eq 0 ]
  [ "$(stat -f %m:%i "$(out)")" = "$m1" ]
  [ "$(shasum "$(out)")" = "$s1" ]
}

@test "CC_SENTINEL_BOOT_CLASSIFY=off writes nothing" {
  CC_SENTINEL_BOOT_CLASSIFY=off run classify
  [ "$status" -eq 0 ]
  [ ! -e "$(out)" ]
}
