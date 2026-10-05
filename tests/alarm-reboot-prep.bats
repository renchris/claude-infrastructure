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
  grep -q 'kalloc1024_gb=6.00' "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.kalloc" || false
  # .start is ONE line, ONE field: the epoch boot-resume.sh compares against the boot.
  [ "$(wc -l < "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" | tr -d ' ')" -eq 1 ] || false
  grep -qx '[0-9][0-9]*' "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" || false
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

# ── The .start pair (W3 P3a-i): the two scripts run together. Until 2026-10-04 this script appended
#    its kalloc reading to .start as a second line, and boot-resume.sh read the whole file as the
#    epoch, so every roster this script wrote was skipped at the reboot it was written for. ──
@test "paired: the roster this script writes is the one boot-resume.sh restores after the reboot" {
  B="$D/br"; mkdir -p "$B/registry" "$B/roles" "$B/tombs" "$HOME"
  echo desk-pane > "$B/roles/desk"
  printf '#!/bin/sh\necho "[{\\"session_id\\": \\"s-pair\\", \\"paneUUID\\": \\"1\\", \\"account\\": \\"claude-next\\", \\"cwd\\": \\"/x/pair\\", \\"name\\": \\"PAIRED-ONE\\"}]"\n' > "$D/sessions"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  start="$(cat "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start")"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$0.log"\n' > "$B/notify"; chmod +x "$B/notify"
  printf '#!/bin/bash\necho "[]"\n' > "$B/hbsess"; chmod +x "$B/hbsess"
  run env CC_BOOTTIME_OVERRIDE=$((start + 60)) CC_BOOT_RESUME_MODE=page \
      CC_BOOT_RESUME_ROSTER_DIR="$CC_REBOOT_PREP_DIR" CC_BOOT_RESUME_STATE_DIR="$B/state" \
      CC_REGISTRY_DIR="$B/registry" CC_ROLES_DIR="$B/roles" CC_SHUTDOWN_TOMB_DIR="$B/tombs" \
      CC_IDL="$B/idl.jsonl" CC_NOTIFY_BIN="$B/notify" CC_BACKLOG_BIN=/usr/bin/false \
      CC_RESUME_LAUNCH_BIN=/usr/bin/false CC_RESUME_LAYOUT_BIN="$B/none" CC_LAUNCHCTL_BIN=/usr/bin/true \
      CC_HEARTBEAT_DIR="$B/hb" CC_HB_SESSIONS_BIN="$B/hbsess" CC_HB_KITTEN_BIN=/usr/bin/false \
      CC_HB_PS_BIN=/usr/bin/true CC_HB_LSOF_BIN=/usr/bin/true \
      /bin/bash "$REPO/scripts/boot-resume.sh"
  [ "$status" -eq 0 ] || false
  grep -q 'PAIRED-ONE' "$B/notify.log" || false
  grep -q 'source: roster reboot-2020-01-01' "$B/notify.log" || false
  grep -q '"source":"roster"' "$B/idl.jsonl" || false
}
