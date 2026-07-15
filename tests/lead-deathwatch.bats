#!/usr/bin/env bats
# L1 — lead-deathwatch orchestrator + cc-deathwatch-kqueue helper. The tool's own --selftest RED-proves
# L1-b/c/d/e against real kqueue exits; these bats add CLI-level regression + the git-checkpoint WIP
# capture path the selftest (empty worktree) does not exercise.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DW="$REPO/scripts/lead-deathwatch.sh"
  export CC_DEATH_RECORDS_DIR="$BATS_TEST_TMPDIR/records"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/noop"; chmod +x "$BATS_TEST_TMPDIR/noop"
  export CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/noop"   # never send a real page
}

@test "selftest passes and runs all 7 checks (a zero-check suite must not 'pass')" {
  run "$DW" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 7 ]
}

@test "--once on a real child exit writes a well-formed death record via kqueue" {
  sleep 1 & child=$!
  cstart="$(ps -o lstart= -p "$child" | sed 's/^ *//;s/ *$//')"
  printf '%s\t%s\treal\twaiterR\t\n' "$child" "$cstart" > "$BATS_TEST_TMPDIR/wl"
  run "$DW" --once "$BATS_TEST_TMPDIR/wl" 5
  [ "$status" -eq 0 ]
  rec="$(ls "$CC_DEATH_RECORDS_DIR"/death-real-*.json | head -1)"
  [ -f "$rec" ]
  [ "$(jq -r '.kind' "$rec")" = "death" ]
  [ "$(jq -r '.reason' "$rec")" = "exit" ]
  [ "$(jq -r '.waiter' "$rec")" = "waiterR" ]
}

@test "{pid,start} guard: a live pid with a wrong start yields DEATH(recycled), not a false-alive" {
  sleep 30 & live=$!
  printf '%s\tWRONG_START\trecyc\twaiterY\t\n' "$live" > "$BATS_TEST_TMPDIR/wl"
  run "$DW" --once "$BATS_TEST_TMPDIR/wl" 3
  [ "$status" -eq 0 ]
  rec="$(ls "$CC_DEATH_RECORDS_DIR"/death-recyc-*.json | head -1)"
  [ "$(jq -r '.reason' "$rec")" = "recycled" ]
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
}

@test "L1-e: a SIGKILLing kqueue helper yields a watcher-died alarm record and exit 3" {
  printf '#!/bin/bash\nkill -9 $$\n' > "$BATS_TEST_TMPDIR/kqkill"; chmod +x "$BATS_TEST_TMPDIR/kqkill"
  printf '11111\ty\tv\tw\t\n' > "$BATS_TEST_TMPDIR/wl"
  CC_DEATHWATCH_KQ="$BATS_TEST_TMPDIR/kqkill" run "$DW" --once "$BATS_TEST_TMPDIR/wl" 3
  [ "$status" -eq 3 ]
  alarm="$(ls "$CC_DEATH_RECORDS_DIR"/alarm-*.json | head -1)"
  [ "$(jq -r '.alarm' "$alarm")" = "watcher-died" ]
}

@test "L1-b: capture checkpoints orphaned WIP into a ref WITHOUT touching the worktree" {
  wt="$BATS_TEST_TMPDIR/wt"; mkdir -p "$wt"
  git -C "$wt" init -q; git -C "$wt" config user.email t@t; git -C "$wt" config user.name t
  echo committed > "$wt/a.txt"; git -C "$wt" add a.txt; git -C "$wt" commit -qm seed
  echo "tracked-change" >> "$wt/a.txt"          # a tracked modification (orphaned WIP)
  echo "UNTRACKED-WIP" > "$wt/b.txt"            # an untracked file (orphaned WIP)
  # a helper stub emitting a DEATH for a member whose worktree is $wt (field 5)
  printf '#!/bin/bash\nprintf "DEATH\\twtmember\\t424242\\texit\\twaiterX\\n"\n' > "$BATS_TEST_TMPDIR/kqemit"; chmod +x "$BATS_TEST_TMPDIR/kqemit"
  printf '424242\tx\twtmember\twaiterX\t%s\n' "$wt" > "$BATS_TEST_TMPDIR/wl"
  CC_DEATHWATCH_KQ="$BATS_TEST_TMPDIR/kqemit" run "$DW" --once "$BATS_TEST_TMPDIR/wl" 1
  [ "$status" -eq 0 ]
  # a checkpoint ref was written capturing the WIP
  ref="$(git -C "$wt" for-each-ref --format='%(refname)' 'refs/deathwatch/**' | head -1)"
  [ -n "$ref" ]
  # the checkpoint's tree contains BOTH the untracked file and the tracked change (WIP captured)
  git -C "$wt" cat-file -e "$ref:b.txt"
  git -C "$wt" show "$ref:a.txt" | grep -q tracked-change
  # the working tree was NOT touched (b.txt still present, a.txt still modified — plumbing, no checkout)
  [ -f "$wt/b.txt" ]
  grep -q tracked-change "$wt/a.txt"
  # the record names the checkpoint ref
  rec="$(ls "$CC_DEATH_RECORDS_DIR"/death-wtmember-*.json | head -1)"
  [ -n "$(jq -r '.checkpoint_ref' "$rec")" ]
}
