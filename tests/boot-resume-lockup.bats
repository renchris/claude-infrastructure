#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats (every @test body is its own subshell; `run` sets $output there).
#
# boot-resume.sh DETECT after a LOCKUP boot (incident 2026-10-25, DESIGN.md C6). In a lockup the
# process table hangs, so a heartbeat census can "answer" and see nobody: kitty 1881's 13:09 roster
# was [], its kitty tree from 03:45. An empty heartbeat roster therefore stops being the answer when
# (a) the boot classifier filed this boot LOCKUP_* (lockwatch/boot-<epoch>.json), or (b) the
# heartbeat's kitty tree is more than 2 ticks older than the heartbeat. The search then falls
# through to the alarm roster (alarm-reboot-prep.sh --files-only), the tombstones and the registry.
# Contracts: (a) and (b) each fall through, said in the IDL `lockup_distrust`; a CLEAN boot with a
# fresh tree still ends the search on the empty roster; CC_BOOT_RESUME_LOCKUP_DISTRUST=off restores
# that; the distrusted boot leaves boot-resume/distrust-<epoch> for the worktree GC's hold.
# RED-proof: against origin/main's boot-resume.sh cases 1-3 log reason no-open-sessions, n_open 0.

bats_require_minimum_version 1.5.0

load helpers/cc-stub
load helpers/boot-resume-env

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # also in the helper; the hermeticity ratchet reads setup() itself
  export CC_FIRE_CAPACITY_GATE=off
  boot_resume_setup
  export CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lockwatch"; mkdir -p "$CC_LOCKWATCH_DIR"
  export CC_BOOT_RESUME_MODE=page
  # the empty heartbeat, taken after the alarm roster below, with a kitty tree written at its tick
  hbeat UUID-PREV 4001 1784799700 '[]'
  HBD="$CC_HEARTBEAT_DIR/UUID-PREV/4001"
  echo '[]' > "$HBD/hb.kitty-ls.json"; touch -t "$(date -r 1784799700 +%Y%m%d%H%M.%S)" "$HBD/hb.kitty-ls.json"
  # the files-only roster taken at the lockup, before the heartbeat's tick
  roster 2020-01-01 1784799600 "[$(rrow f1 claude-next /x/f1 FILES-ONE),$(rrow f2 claude-tertiary /x/f2 FILES-TWO)]"
}
boot_class() { printf '{"class":"%s","confidence":"high"}\n' "$1" > "$CC_LOCKWATCH_DIR/boot-1784800000.json"; }

@test "lockup: a LOCKUP_DEVFS boot falls through the empty heartbeat to the files-only roster" {
  boot_class LOCKUP_DEVFS
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"source":"roster"' "$CC_IDL"
  grep -q '"lockup_distrust":"boot class LOCKUP_DEVFS"' "$CC_IDL"
  grep -q '"n_open":2' "$CC_IDL"
  grep -q 'FILES-ONE' "$CC_NOTIFY_BIN.log"; grep -q 'FILES-TWO' "$CC_NOTIFY_BIN.log"
  [ "$(cat "$CC_BOOT_RESUME_STATE_DIR/distrust-1784800000")" = "boot class LOCKUP_DEVFS" ]
}

@test "lockup: a kitty tree more than 2 ticks older than its heartbeat is distrust enough, with no classifier" {
  touch -t "$(date -r 1784798000 +%Y%m%d%H%M.%S)" "$HBD/hb.kitty-ls.json"     # 1700 s before the tick
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"source":"roster"' "$CC_IDL"
  grep -q '"lockup_distrust":"kitty tree 1700s older than the heartbeat"' "$CC_IDL"
}

@test "lockup: with no alarm roster the tombstones answer, and the registry joins them" {
  boot_class LOCKUP_UNKNOWN
  rm -f "$CC_BOOT_RESUME_ROSTER_DIR"/reboot-*
  tomb t1 1784799800; tomb t2 1784799802
  reg_entry g1 1784795000000 claude-quaternary /Users/x/wt-g GHOST-ONE
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"source":"tombstones"' "$CC_IDL"
  grep -q '"reg_joined":1' "$CC_IDL"
  grep -q 'T-t1' "$CC_NOTIFY_BIN.log"; grep -q 'GHOST-ONE' "$CC_NOTIFY_BIN.log"
}

@test "lockup: a CLEAN boot with a fresh tree still ends the search on the empty roster" {
  boot_class CLEAN
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'no-open-sessions' "$CC_IDL"
  grep -q '"source":"heartbeat"' "$CC_IDL"
  grep -q '"lockup_distrust":""' "$CC_IDL"
  [ ! -e "$CC_BOOT_RESUME_STATE_DIR/distrust-1784800000" ]
}

@test "lockup: CC_BOOT_RESUME_LOCKUP_DISTRUST=off is the rollback" {
  boot_class LOCKUP_DEVFS
  CC_BOOT_RESUME_LOCKUP_DISTRUST=off run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'no-open-sessions' "$CC_IDL"
  grep -q '"source":"heartbeat"' "$CC_IDL"
}
