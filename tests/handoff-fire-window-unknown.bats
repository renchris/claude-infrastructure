#!/usr/bin/env bats
# Pane-lifecycle fixes 2026-10-01, item 5 (docs/plans/pane-lifecycle-fixes-2026-10-01.md; evidence
# docs/research/selfclose-failures-2026-10-01.md M11).
#
# FLEET_V2 W7c, 2026-09-30: a `--window` fire's kitty launch answered no window id and kitty's window
# list could not be read. kitty HAD created window 47 running the brief, but spawn said "nothing
# launched", fire_cleanup removed the worktree and branch under the live session, and the re-fire
# started twin pane 48. An UNKNOWN outcome is now rc 13 end to end — kt_launch, spawn_frontmost,
# spawn — the same verdict the split arm already gave, and fire_cleanup keeps every resource on it.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Seams that do NOT resolve under $HOME (test-hermeticity-lint 5a/5b): absent paths, sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON CC_TERM_KITTY_TO
  eval "$(sed -n '/^kt_launch() {/,/^}/p;/^spawn_frontmost() {/,/^}/p;/^spawn() {/,/^}/p;/^fire_cleanup() {/,/^}/p' "$HF")"
  in_kitty() { return 0; }
  SURFACE=window FOLLOW=0 HF_ARGV=() FIRE_SPAWN_UNKNOWN=0
}

@test "kt_launch: no window id AND an unreadable window list ⇒ rc 13 (UNKNOWN), not an empty success" {
  kt() { return 1; }                           # the launch answered nothing
  hf_adopt_split_pane() { return 2; }          # kitty's list could not be read
  run kt_launch --type=os-window
  [ "$status" -eq 13 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"outcome UNKNOWN"* ]] || false
}

@test "kt_launch CONTROL: a READABLE list with no matching window is a plain failure (rc 0, no id)" {
  kt() { return 1; }
  hf_adopt_split_pane() { return 1; }
  run kt_launch --type=os-window
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "rc=$status out=$output"; false; }
}

@test "spawn --window: an UNKNOWN launch returns 13, marks FIRE_SPAWN_UNKNOWN, and never says 'nothing launched'" {
  kt() { return 1; }
  hf_adopt_split_pane() { return 2; }
  rc=0; spawn 2> "$BATS_TEST_TMPDIR/err" || rc=$?
  [ "$rc" -eq 13 ] || { echo "rc=$rc"; cat "$BATS_TEST_TMPDIR/err"; false; }
  [ "$FIRE_SPAWN_UNKNOWN" = 1 ] || false
  grep -q 'outcome UNKNOWN' "$BATS_TEST_TMPDIR/err"
  ! grep -q 'nothing launched' "$BATS_TEST_TMPDIR/err" || { cat "$BATS_TEST_TMPDIR/err"; false; }
}

@test "spawn --window CONTROL: a launch that plainly failed still says 'nothing launched' (rc 1)" {
  kt() { return 1; }
  hf_adopt_split_pane() { return 1; }
  rc=0; spawn 2> "$BATS_TEST_TMPDIR/err" || rc=$?
  [ "$rc" -eq 1 ] || { echo "rc=$rc"; false; }
  grep -q 'nothing launched' "$BATS_TEST_TMPDIR/err"
}

mk_worktree() {
  REPO="$BATS_TEST_TMPDIR/repo"; git init -q "$REPO"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  FIRE_CLEAN_WT="$BATS_TEST_TMPDIR/wt"; FIRE_CLEAN_BRANCH="fire/test"
  git -C "$REPO" worktree add -q -b "$FIRE_CLEAN_BRANCH" "$FIRE_CLEAN_WT"
  FIRE_CLEAN_POOL="" FIRE_CLEAN_DONE=0 SPAWNED_PANE="" FIRE_LIVE_PANE=""
}

@test "fire_cleanup: on an UNKNOWN spawn (rc 13) the worktree and branch are KEPT" {
  mk_worktree
  ( set +e; (exit 13); fire_cleanup ) 2> "$BATS_TEST_TMPDIR/err"
  [ -d "$FIRE_CLEAN_WT" ] || { echo "removed a worktree a live session may be running in"; cat "$BATS_TEST_TMPDIR/err"; false; }
  git -C "$REPO" rev-parse --verify -q "refs/heads/$FIRE_CLEAN_BRANCH" >/dev/null
  grep -q 'outcome UNKNOWN' "$BATS_TEST_TMPDIR/err"
}

@test "fire_cleanup: FIRE_SPAWN_UNKNOWN=1 keeps the worktree even when the exit code was rewritten" {
  mk_worktree
  ( set +e; FIRE_SPAWN_UNKNOWN=1; (exit 1); fire_cleanup ) 2>/dev/null
  [ -d "$FIRE_CLEAN_WT" ] || false
}

@test "fire_cleanup CONTROL: an ordinary failed fire (rc 1, nothing launched) still removes the worktree" {
  mk_worktree
  ( set +e; (exit 1); fire_cleanup ) 2>/dev/null
  [ ! -d "$FIRE_CLEAN_WT" ] || { echo "the ordinary cleanup stopped working"; false; }
}
