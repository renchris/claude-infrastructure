#!/usr/bin/env bats
# lr-recon-launchd.bats — FLEET_V2 W5 operator step 1, the installer for the three lr-reconciler jobs.
#
# Hermetic: launchctl is a fake on PATH that keeps its "loaded" set in a file and records every call;
# the agents dir, HOME and LR_STATE_DIR live under $BATS_TEST_TMPDIR. plutil is the real one, so the
# SSOT plists are genuinely linted. The fake bootstrap of the reconciler writes its heartbeat, which
# is the read-back the script verifies against.

SUT="$BATS_TEST_DIRNAME/../scripts/limit-recover/lr-recon-launchd.sh"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export LR_LAUNCHD_AGENTS_DIR="$BATS_TEST_TMPDIR/agents"
  export LR_LAUNCHD_HB_WAIT_S=3
  export FAKE_LOADED="$BATS_TEST_TMPDIR/loaded" FAKE_LOG="$BATS_TEST_TMPDIR/launchctl.log"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  : > "$FAKE_LOADED"
  cat > "$BATS_TEST_TMPDIR/bin/launchctl" <<'SH'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
case "$1" in
  print) grep -qx "${2##*/}" "$FAKE_LOADED" ;;
  bootstrap)
    l="$(basename "$3" .plist)"; echo "$l" >> "$FAKE_LOADED"
    [ "$l" = com.reso.lr-reconciler ] && { mkdir -p "$LR_STATE_DIR/recon"; touch "$LR_STATE_DIR/recon/heartbeat"; }
    exit 0 ;;
  bootout) grep -vx "${2##*/}" "$FAKE_LOADED" > "$FAKE_LOADED.n"; mv "$FAKE_LOADED.n" "$FAKE_LOADED" ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "dry run lints all three plists, changes nothing, exits 0" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plutil -lint: 3 SSOT plists"* ]]
  [[ "$output" == *"would: com.reso.lr-reconciler-rig (not loaded"* ]]
  ! grep -q bootstrap "$FAKE_LOG" 2>/dev/null
  [ ! -d "$LR_LAUNCHD_AGENTS_DIR" ]
}

@test "--confirm must name the target; a wrong or missing name is refused with rc 2 and no call" {
  run bash "$SUT" --confirm yes
  [ "$status" -eq 2 ]
  run bash "$SUT" --confirm
  [ "$status" -eq 2 ]
  ! grep -q bootstrap "$FAKE_LOG" 2>/dev/null
}

@test "apply installs and bootstraps rig, reconciler, watchdog in that order and verifies" {
  run bash "$SUT" --confirm lr-reconciler
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=ok"* ]]
  run grep -o 'bootstrap gui/[0-9]* .*/com.reso.lr-reconciler[a-z-]*.plist' "$FAKE_LOG"
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == *lr-reconciler-rig.plist ]]
  [[ "${lines[1]}" == *lr-reconciler.plist ]]
  [[ "${lines[2]}" == *lr-reconciler-watchdog.plist ]]
  for l in com.reso.lr-reconciler-rig com.reso.lr-reconciler com.reso.lr-reconciler-watchdog; do
    cmp -s "$BATS_TEST_DIRNAME/../scripts/limit-recover/$l.plist" "$LR_LAUNCHD_AGENTS_DIR/$l.plist"
  done
  [ -d "$LR_STATE_DIR/recon" ] && [ -d /tmp/lr-rig/state ]
  [ ! -e "$LR_STATE_DIR/recon.on" ]   # never writes the cutover file
}

@test "re-run is idempotent: identical loaded jobs are not bootstrapped again" {
  bash "$SUT" --confirm lr-reconciler
  : > "$FAKE_LOG"
  touch "$LR_STATE_DIR/recon/heartbeat"
  run bash "$SUT" --confirm lr-reconciler
  [ "$status" -eq 0 ]
  ! grep -q 'bootstrap\|bootout' "$FAKE_LOG"
}

@test "a changed installed plist is booted out and bootstrapped again" {
  bash "$SUT" --confirm lr-reconciler
  echo '<!-- drift -->' >> "$LR_LAUNCHD_AGENTS_DIR/com.reso.lr-reconciler-watchdog.plist"
  : > "$FAKE_LOG"
  touch "$LR_STATE_DIR/recon/heartbeat"
  run bash "$SUT" --confirm lr-reconciler
  [ "$status" -eq 0 ]
  grep -q 'bootout gui/[0-9]*/com.reso.lr-reconciler-watchdog' "$FAKE_LOG"
  [ "$(grep -c bootstrap "$FAKE_LOG")" -eq 1 ]
}

@test "no fresh heartbeat after bootstrap is a failure verdict, rc 1" {
  sed -i '' 's/touch "$LR_STATE_DIR\/recon\/heartbeat"/true/' "$BATS_TEST_TMPDIR/bin/launchctl"
  run bash "$SUT" --confirm lr-reconciler
  [ "$status" -eq 1 ]
  [[ "$output" == *"no fresh reconciler heartbeat"* ]]
}

@test "a failing bootstrap stops with rc 1 and names the job" {
  printf '#!/bin/bash\necho "$*" >> "$FAKE_LOG"\n[ "$1" = bootstrap ] && exit 5\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/launchctl"
  run bash "$SUT" --confirm lr-reconciler
  [ "$status" -eq 1 ]
  [[ "$output" == *"launchctl bootstrap"*"lr-reconciler-rig.plist failed"* ]]
}
