#!/usr/bin/env bats
# stranded-sweep.sh — detect commits stranded on local branches (content never landed).
# Builds scratch repos (bare "origin" + working clone) in BATS_TEST_TMPDIR so
# origin/<trunk> tracking works. No network, no real repo touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="$REPO/scripts/stranded-sweep.sh"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK"
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m "base"
  git push -q -u origin main
}

@test "clean: all commits landed → exit 0, '0 stranded'" {
  run bash "$SWEEP" main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 stranded"
}

@test "GATE 2: synthetic stranded (new file never merged) → exit 1, names sha+path+cherry-pick" {
  git checkout -q -b feature
  echo hello > newfile.txt
  git add newfile.txt
  git commit -q -m "add newfile"
  sha="$(git rev-parse --short HEAD)"
  run bash "$SWEEP" main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "$sha"
  echo "$output" | grep -q "newfile.txt"
  echo "$output" | grep -q "cherry-pick"
}

@test "GATE 1: race simulation — sibling lands only C2, C1 stranded" {
  git checkout -q -b featureF
  echo A > fileA.txt; git add fileA.txt; git commit -q -m "C1 fileA"
  c1="$(git rev-parse --short HEAD)"
  echo B > fileB.txt; git add fileB.txt; git commit -q -m "C2 fileB"
  c2="$(git rev-parse HEAD)"

  # sibling lands ONLY C2 onto origin/main (a rebase-land that dropped C1)
  git checkout -q main
  git cherry-pick "$c2" >/dev/null 2>&1
  git push -q origin main

  git checkout -q featureF
  run bash "$SWEEP" main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "$c1"
  echo "$output" | grep -q "fileA.txt"
}

@test "false-positive guard: path also on trunk with different content → NOT flagged" {
  # both sides touch fileX; branch commit is a `+` (not patch-equiv) but fileX exists on trunk
  echo original > fileX.txt; git add fileX.txt; git commit -q -m "seed fileX"
  git push -q origin main

  git checkout -q -b diverge
  echo branchside > fileX.txt; git add fileX.txt; git commit -q -m "branch edits fileX"

  # trunk moves fileX differently (so branch commit is NOT patch-equivalent to trunk)
  git checkout -q main
  echo trunkside > fileX.txt; git add fileX.txt; git commit -q -m "trunk edits fileX"
  git push -q origin main

  git checkout -q diverge
  run bash "$SWEEP" main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 stranded"
}

# --- --mine <sid> (T-P9-4): ownership-decidable sweep. Two stranded branches with
# distinct Session-Id trailers; --mine attributes the drop, default mode is unchanged.
seed_two_owned_strands() {
  git checkout -q -b featA main
  echo aaa > fileA.txt && git add fileA.txt
  git commit -q -m "$(printf 'add fileA\n\nSession-Id: SID-A\n')"
  git checkout -q -b featB main
  echo bbb > fileB.txt && git add fileB.txt
  git commit -q -m "$(printf 'add fileB\n\nSession-Id: SID-B\n')"
}

@test "--mine: reports only own-session drop, silent on peer → exit 1, own file only" {
  seed_two_owned_strands
  run bash "$SWEEP" --mine SID-A main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "fileA.txt"
  ! echo "$output" | grep -q "fileB.txt"
  echo "$output" | grep -q "SID-A"
}

@test "--mine: only a peer is stranded → exit 0 (decidable pass)" {
  git checkout -q -b featB main
  echo bbb > fileB.txt && git add fileB.txt
  git commit -q -m "$(printf 'add fileB\n\nSession-Id: SID-B\n')"

  run bash "$SWEEP" --mine SID-A main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 own-session"
}

@test "default mode unchanged: both stranded reported → exit 1" {
  seed_two_owned_strands
  run bash "$SWEEP" main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "fileA.txt"
  echo "$output" | grep -q "fileB.txt"
}

@test "--mine accepts trunk in any arg order (--mine SID then trunk)" {
  seed_two_owned_strands
  run bash "$SWEEP" --mine=SID-B main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "fileB.txt"
  ! echo "$output" | grep -q "fileA.txt"
}
