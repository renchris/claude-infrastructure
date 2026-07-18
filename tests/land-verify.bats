#!/usr/bin/env bats
# land-verify.sh — content-verify a landing (paths present + byte-identical on trunk).
# Scratch bare "origin" + working clone in BATS_TEST_TMPDIR so origin/<trunk> tracking
# works. No network, no real repo touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  VERIFY="$REPO/scripts/land-verify.sh"

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
  git commit -q -m base
  git push -q -u origin main
}

@test "green: add + edit both landed → exit 0" {
  base="$(git rev-parse main)"
  git checkout -q -b feature
  echo hi > newfile.txt
  echo edited >> base.txt
  git add -A && git commit -q -m "add newfile + edit base"
  head="$(git rev-parse HEAD)"

  # land BOTH onto trunk
  git checkout -q main && git merge -q --ff-only feature && git push -q origin main
  git fetch -q origin main
  git checkout -q feature

  run bash "$VERIFY" "$base..$head" origin/main "$head"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "content-identical"
}

@test "RED: dropped NEW file among landed edits → exit 1 names only the dropped file" {
  base="$(git rev-parse main)"
  git checkout -q -b feature
  echo hi > newfile.txt
  echo edited >> base.txt
  git add -A && git commit -q -m "add newfile + edit base"
  head="$(git rev-parse HEAD)"

  # trunk gets ONLY the base.txt edit (newfile.txt dropped — the incident class)
  git checkout -q main
  echo edited >> base.txt
  git add base.txt && git commit -q -m "edit base only"
  git push -q origin main
  git fetch -q origin main
  git checkout -q feature

  run bash "$VERIFY" "$base..$head" origin/main "$head"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "newfile.txt"
  # the landed edit must NOT be reported as a miss (per-path, not all-or-nothing)
  ! echo "$output" | grep -q "base.txt"
}

@test "content differs: edited file landed with different content → exit 1" {
  echo original > fileX.txt && git add fileX.txt && git commit -q -m "seed fileX" && git push -q origin main
  base="$(git rev-parse main)"

  git checkout -q -b diverge
  echo branchside > fileX.txt && git add fileX.txt && git commit -q -m "branch edits fileX"
  head="$(git rev-parse HEAD)"

  # trunk moved fileX to different content
  git checkout -q main
  echo trunkside > fileX.txt && git add fileX.txt && git commit -q -m "trunk edits fileX"
  git push -q origin main && git fetch -q origin main
  git checkout -q diverge

  run bash "$VERIFY" "$base..$head" origin/main "$head"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "fileX.txt"
  echo "$output" | grep -q "DIFFERS"
}

@test "deletion landed: deleted path not false-flagged → exit 0" {
  base="$(git rev-parse main)"
  git checkout -q -b delbranch
  git rm -q base.txt && git commit -q -m "delete base"
  head="$(git rev-parse HEAD)"

  # trunk also gets the deletion
  git checkout -q main && git rm -q base.txt && git commit -q -m "delete base on trunk"
  git push -q origin main && git fetch -q origin main
  git checkout -q delbranch

  run bash "$VERIFY" "$base..$head" origin/main "$head"
  [ "$status" -eq 0 ]
}

@test "usage: no range → exit 64" {
  run bash "$VERIFY"
  [ "$status" -eq 64 ]
}
