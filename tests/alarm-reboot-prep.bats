#!/usr/bin/env bats
# alarm-reboot-prep.sh — the agent half of the safe reboot order (host-memory.2). Every external
# reader is stubbed (ps, cc-sessions, zprint), so the verdicts are about the script, not this box.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/absent-repo"   # hermeticity: no live converge
  mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  S="$REPO/scripts/alarm-reboot-prep.sh"
  D="$BATS_TEST_TMPDIR"
  export CC_REBOOT_PREP_DIR="$D/autonomy" CC_REBOOT_PREP_DATE=2020-01-01
  printf '#!/bin/sh\ncat "%s/ps.out"\n' "$D" > "$D/ps"
  printf '#!/bin/sh\necho "[{\\"paneUUID\\": \\"1\\"}, {\\"paneUUID\\": \\"2\\"}]"\n' > "$D/sessions"
  printf '#!/bin/sh\necho "data.kalloc.1024 1024 0K 0K 0 0 6291456 0K 0"\n' > "$D/zprint"
  chmod +x "$D/ps" "$D/sessions" "$D/zprint"
  export CC_REBOOT_PREP_PS="$D/ps" CC_REBOOT_PREP_SESSIONS="$D/sessions" CC_REBOOT_PREP_ZPRINT="$D/zprint"
  : > "$D/ps.out"
}

@test "READY with no land in flight: records the start epoch, the roster and the kalloc reading" {
  printf '  101 /bin/zsh -l\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=READY"* ]] || false
  [ -s "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" ] || false
  grep -q 'kalloc1024_gb=6.00' "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" || false
  [ "$(grep -c paneUUID "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.roster.json")" -ge 1 ] || false
  [[ "$output" == *"live sessions      2 "* ]] || false
}

@test "NOT-READY (exit 3) while a ship-land.sh PROCESS runs, under a shell or directly" {
  printf '  201 bash /Users/x/.claude/scripts/ship-land.sh --land\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"verdict=NOT-READY reason=land-in-flight"* ]] || false
  printf '  202 /Users/x/.claude/scripts/ship-land.sh\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || false
}

@test "a session whose brief merely MENTIONS ship-land.sh is not a land (the pgrep -f false positive)" {
  printf '  301 /Users/x/.claude-284/node_modules/.bin/claude --append-system-prompt run ship-land.sh later\n  302 bash /Users/x/.claude/bin/cc-close-attrib claude ship-land.sh\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=READY"* ]] || false
}

@test "a staged root capture is printed as the step BEFORE the reboot; absent, it is not" {
  run bash "$S"
  [[ "$output" != *"root zone capture is STAGED"* ]] || false
  mkdir -p "$CC_REBOOT_PREP_DIR"
  echo 'echo capture' > "$CC_REBOOT_PREP_DIR/kalloc-root-capture.cmd"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"root zone capture is STAGED"* ]] || false
  [[ "$output" == *"bash $CC_REBOOT_PREP_DIR/kalloc-root-capture.cmd"* ]] || false
}

@test "a failed roster read is said, never rendered as zero sessions" {
  printf '#!/bin/sh\nexit 1\n' > "$D/sessions"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"unknown (cc-sessions failed"* ]] || false
  [ ! -e "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.roster.json" ] || false
}

@test "a pending kitty restart rides this reboot and is named; absent, nothing is said" {
  run bash "$S"
  [[ "$output" != *"ALSO the kitty restart"* ]] || false
  mkdir -p "$CC_REBOOT_PREP_DIR"
  echo "kitty 0.48.3 patched build from ~/kitty-dev" > "$CC_REBOOT_PREP_DIR/kitty-restart-pending"
  run bash "$S"
  [[ "$output" == *"ALSO the kitty restart: kitty 0.48.3 patched build from ~/kitty-dev"* ]] || false
}
