#!/usr/bin/env bats
# land-failed-gc.sh — bounds refs/land/failed/* by pruning ONLY pins that are old, proven landed by
# content, and named by no open backlog row; every deletion journaled first.
#
# Fixtures are a bare origin plus a working clone under $BATS_TEST_TMPDIR. The backlog is a stub
# printing a fixed open-row fold, so the row guard is drivable without the live ledger.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO_ROOT/scripts/land-failed-gc.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@example.invalid
  export GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@example.invalid
  export LAND_GC_FETCH=off
  export CC_LAND_GC_JOURNAL="$BATS_TEST_TMPDIR/journal.jsonl"
  U="$BATS_TEST_TMPDIR/up.git"; W="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$U"; git init -q "$W"
  git -C "$W" symbolic-ref HEAD refs/heads/main
  printf 'seed\n' > "$W/seed.txt"; git -C "$W" add -A; git -C "$W" commit -qm seed
  git -C "$W" remote add origin "$U"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
  OPEN="$BATS_TEST_TMPDIR/open.json"; printf '[]\n' > "$OPEN"
  export CC_LAND_GC_BACKLOG_BIN="$BATS_TEST_TMPDIR/cc-backlog"
  printf '#!/bin/sh\n[ "$1" = list ] && cat "%s"\n' "$OPEN" > "$CC_LAND_GC_BACKLOG_BIN"
  chmod +x "$CC_LAND_GC_BACKLOG_BIN"
  OLD="20260901T000000Z"; NEWS="20260929T000000Z"
  LAND_GC_NOW="$(date -j -u -f '%Y%m%dT%H%M%SZ' 20260930T000000Z +%s 2>/dev/null || date -u -d '2026-09-30 00:00:00' +%s)"
  export LAND_GC_NOW
}

# $1=pin name  $2=landed|unlanded — a branch commit pinned, and (landed) the same bytes on trunk
pin() {
  git -C "$W" checkout -q -b "b-$1" main
  printf 'work %s\n' "$1" > "$W/f-$1.txt"; git -C "$W" add -A; git -C "$W" commit -qm "work $1"
  git -C "$W" update-ref "refs/land/failed/$1" HEAD
  git -C "$W" checkout -q main
  if [ "$2" = landed ]; then
    printf 'work %s\n' "$1" > "$W/f-$1.txt"; git -C "$W" add -A; git -C "$W" commit -qm "land $1 under another sha"
    git -C "$W" push -q origin main; git -C "$W" fetch -q origin
  fi
}
has() { git -C "$W" rev-parse -q --verify "refs/land/failed/$1" >/dev/null; }
gc()  { bash "$SUT" --repo "$W" "$@"; }

@test "an OLD pin proven landed is pruned, journaled with its sha, and restorable from the journal" {
  pin "$OLD-s1-landed" landed
  sha="$(git -C "$W" rev-parse "refs/land/failed/$OLD-s1-landed")"
  run gc
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! has "$OLD-s1-landed" || false
  jq -e --arg s "$sha" 'select(.event=="pruned" and .sha==$s)' "$CC_LAND_GC_JOURNAL" >/dev/null
  echo "$output" | grep -q 'pruned-landed=1'
  git -C "$W" update-ref "refs/land/failed/$OLD-s1-landed" "$sha"   # the restore recipe works
  has "$OLD-s1-landed"
}

@test "an OLD pin holding UNLANDED content is KEPT" {
  pin "$OLD-s2-unlanded" unlanded
  run gc
  [ "$status" -eq 0 ]
  has "$OLD-s2-unlanded"
  echo "$output" | grep -q 'kept-unlanded=1'
  [ ! -s "$CC_LAND_GC_JOURNAL" ]
}

@test "a YOUNG pin is kept even when landed" {
  pin "$NEWS-s3-young" landed
  run gc
  has "$NEWS-s3-young"
  echo "$output" | grep -q 'kept-young=1'
}

@test "a pin an OPEN backlog row names is kept — its falsifier must not lose its subject" {
  pin "$OLD-s4-named" landed
  printf '[{"title":"re-land x","falsifier":"land-content-verify.sh refs/land/failed/%s"}]\n' "$OLD-s4-named" > "$OPEN"
  run gc
  has "$OLD-s4-named"
  echo "$output" | grep -q 'kept-open-row=1'
}

@test "an unreadable backlog deletes NOTHING (exit 2), even over a prunable pin" {
  pin "$OLD-s5-landed" landed
  printf '#!/bin/sh\nexit 1\n' > "$CC_LAND_GC_BACKLOG_BIN"
  run gc
  [ "$status" -eq 2 ]
  has "$OLD-s5-landed"
}

@test "an unwritable journal deletes nothing" {
  pin "$OLD-s6-landed" landed
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 500 "$BATS_TEST_TMPDIR/ro"
  CC_LAND_GC_JOURNAL="$BATS_TEST_TMPDIR/ro/j.jsonl" run gc
  chmod 700 "$BATS_TEST_TMPDIR/ro"
  has "$OLD-s6-landed"
  echo "$output" | grep -q 'journal-fail=1'
}

@test "--dry-run and --max: nothing deleted on a dry run; --max bounds the verifies, oldest first" {
  pin "20260801T000000Z-s7-a" landed
  pin "20260802T000000Z-s7-b" landed
  run gc --dry-run
  has "20260801T000000Z-s7-a"; has "20260802T000000Z-s7-b"
  run gc --max 1
  ! has "20260801T000000Z-s7-a" || false
  has "20260802T000000Z-s7-b"
  echo "$output" | grep -q 'deferred=1'
}

@test "a live lock holder makes a second pass exit without verifying" {
  pin "$OLD-s8-landed" landed
  mkdir -p "$CLAUDE_CONFIG_DIR/autonomy/.land-failed-gc.lock"
  sleep 30 & holder=$!
  printf '%s\n' "$holder" > "$CLAUDE_CONFIG_DIR/autonomy/.land-failed-gc.lock/pid"
  run gc
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'another pass'
  has "$OLD-s8-landed"
  run gc                      # the holder is dead now: the lock is reclaimed and the pin pruned
  ! has "$OLD-s8-landed"
}
