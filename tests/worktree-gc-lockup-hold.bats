#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats (every @test body is its own subshell; `run` sets $output there).
#
# worktree-gc-infra-run.sh's LOCKUP HOLD (incident 2026-10-25, DESIGN.md C6). At 13:31 on the boot
# after the lockup the sweep removed 49 worktrees, 11 of them the cwds of sessions still to be
# resumed ("clean · idle · landed" is what an interrupted session's worktree looks like). For the
# boot after a lockup — classified LOCKUP_* in lockwatch/boot-<epoch>.json, or distrusted by
# boot-resume (boot-resume/distrust-<epoch>) — the worktree of every session of the previous boot
# (tombstones, alarm roster, heartbeat rosters of the 24 h before the boot) goes into the janitor's
# own never-touch list, CC_WTGC_EXCLUDE. Contracts, read from the env the janitor stub receives:
# held on either trigger, a subdirectory cwd held by its worktree root, nothing held on a clean
# boot, and CC_WTGC_LOCKUP_HOLD=off as the rollback.
# RED-proof: against origin/main's worktree-gc-infra-run.sh no case's EXCLUDE names a held path.

bats_require_minimum_version 1.5.0

load helpers/cc-stub

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SUT="$REPO_ROOT/scripts/worktree-gc-infra-run.sh"
  export CC_WTGC_INFRA_REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$CC_WTGC_INFRA_REPO"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  ENVFILE="$BATS_TEST_TMPDIR/gc.env"
  export CC_WTGC_INFRA_GC="$BIN/gc-stub.sh" CC_WTGC_GIT="$BIN/git" CC_WTGC_INFRA_FETCH_BACKOFF=0
  cc_stub "$BIN" git "$(printf '#!/bin/bash\nexit 0\n')"
  # the wrapper runs its janitor as `bash "$GC_SH"`, so this stub is a script body, never exec'd
  cat > "$CC_WTGC_INFRA_GC" <<EOF
printf 'EXCLUDE=%s\n' "\$CC_WTGC_EXCLUDE" >> "$ENVFILE"
echo 'worktree-gc: removed 0 worktree(s) · disposed 0 abandoned · 0 landed-dirt · kept 2 · deleted 0 branch(es) · 0 refusal(s)'
echo 'worktree-gc: counts removed=0 disposed=0 landed_dirt=0 kept=2 branches_deleted=0 refusals=0 elapsed=1s lock_staleness_window=3600s dry_run=0'
EOF
  A="$BATS_TEST_TMPDIR/autonomy"; export CC_WTGC_AUTONOMY_DIR="$A" CC_WTGC_BOOTTIME=1784800000
  export CC_SHUTDOWN_TOMB_DIR="$A/shutdown-tombstones" CC_HEARTBEAT_DIR="$A/heartbeat" \
         CC_LOCKWATCH_DIR="$A/lockwatch" CC_BOOT_RESUME_STATE_DIR="$A/boot-resume"
  mkdir -p "$CC_SHUTDOWN_TOMB_DIR" "$CC_HEARTBEAT_DIR/U/7" "$CC_LOCKWATCH_DIR" "$CC_BOOT_RESUME_STATE_DIR"
  # two worktrees (a .git FILE at their roots): one a tombstone's cwd, one holding a roster cwd below it
  W1="$BATS_TEST_TMPDIR/wt/one"; W2="$BATS_TEST_TMPDIR/wt/two"; mkdir -p "$W1" "$W2/sub/dir"
  echo "gitdir: x" > "$W1/.git"; echo "gitdir: x" > "$W2/.git"
  printf '{"session_id":"s1","cwd":"%s","endedAt":1784799800}\n' "$W1" > "$CC_SHUTDOWN_TOMB_DIR/s1.json"
  printf '{"session_id":"s0","cwd":"%s/never","endedAt":1784600000}\n' "$BATS_TEST_TMPDIR" > "$CC_SHUTDOWN_TOMB_DIR/s0.json"   # > 24 h before
  echo 1784799000 > "$CC_HEARTBEAT_DIR/U/7/hb.start"
  printf '[{"session_id":"s2","cwd":"%s/sub/dir"}]\n' "$W2" > "$CC_HEARTBEAT_DIR/U/7/hb.roster.json"
}
excl() { sed -n 's/^EXCLUDE=//p' "$ENVFILE" | tr ':' '\n'; }

@test "hold: after a LOCKUP_* boot the previous boot's worktrees are excluded, a subdirectory cwd by its root" {
  echo '{"class":"LOCKUP_DEVFS"}' > "$CC_LOCKWATCH_DIR/boot-1784800000.json"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  excl | grep -qx "$W1"
  excl | grep -qx "$W2"
  ! excl | grep -q 'never' || false                              # a tombstone older than 24 h holds nothing
  grep -q 'lockup hold (boot class LOCKUP_DEVFS) — 2 worktree(s)' "$HOME/.claude/logs/worktree-gc-infra.log"
}

@test "hold: boot-resume's distrust marker holds them too, before any classifier exists" {
  echo 'kitty tree 34000s older than the heartbeat' > "$CC_BOOT_RESUME_STATE_DIR/distrust-1784800000"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  excl | grep -qx "$W1"
  grep -q 'lockup hold (boot-resume: kitty tree 34000s older than the heartbeat)' "$HOME/.claude/logs/worktree-gc-infra.log"
}

@test "hold: a clean boot holds nothing, and CC_WTGC_LOCKUP_HOLD=off is the rollback" {
  echo '{"class":"CLEAN"}' > "$CC_LOCKWATCH_DIR/boot-1784800000.json"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  ! excl | grep -qx "$W1" || false
  : > "$ENVFILE"
  echo '{"class":"LOCKUP_DEVFS"}' > "$CC_LOCKWATCH_DIR/boot-1784800000.json"
  CC_WTGC_LOCKUP_HOLD=off run bash "$SUT"
  [ "$status" -eq 0 ]
  ! excl | grep -qx "$W1" || false
}
