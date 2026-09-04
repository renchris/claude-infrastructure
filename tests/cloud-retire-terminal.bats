#!/usr/bin/env bats
# cloud-retire-terminal.sh — retires the declarations that can never return anything, so the return
# sweep's working set stops being a monotone-growing history. Every arm below runs the REAL script
# against a REAL git fixture (a bare origin + a clone), and the retire verb is the REAL bin/cc-cloud
# rather than a stub: what is under test is the verdict, and a stubbed store would let a wrong
# verdict write a right-looking marker.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="$REPO/scripts/cloud-retire-terminal.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/cloud"; mkdir -p "$CC_CLOUD_STATE"
  export CLOUD_RETIRE_CLOUD_BIN="$REPO/bin/cc-cloud"
  export CLOUD_RETIRE_TRUNK="origin/main"
  export CC_RETIRE_MIN_AGE_H=6

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init --bare --quiet "$ORIGIN"
  git init --quiet "$WORK"
  git -C "$WORK" config user.email t@t
  git -C "$WORK" config user.name t
  git -C "$WORK" config commit.gpgsign false
  echo base > "$WORK/base.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm base
  git -C "$WORK" branch -M main
  git -C "$WORK" remote add origin "$ORIGIN"
  git -C "$WORK" push -q origin main
  export CLOUD_RETIRE_REPO="$WORK"
}

# `<id>` gets a declaration naming `<branch>`, declared `<age_h>` hours ago.
decl() { # <id> <branch> <age_h>
  local id="$1" br="$2" age="${3:-48}" at
  at=$(( $(date +%s) - age * 3600 ))
  printf 'id=%s\nbranch=%s\nremote=origin\nrepo=%s\npaths=\nitem=item-%s\ndeclared_at=%s\n' \
    "$id" "$br" "$CLOUD_RETIRE_REPO" "$id" "$at" > "$CC_CLOUD_STATE/$id.decl"
}
retired() { [ -f "$CC_CLOUD_STATE/$1.retired" ]; }

# A branch carrying work that IS on the trunk by patch id but NOT by ancestry — the shape ship-land
# actually produces, since it rebases before it pushes. Ancestry would call this unlanded.
push_landed_branch() { # <branch>
  git -C "$WORK" checkout -q -b "$1" main
  echo landed > "$WORK/landed.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "feat: landed"
  git -C "$WORK" push -q origin "$1"
  git -C "$WORK" checkout -q main
  # the SAME PATCH reaches the trunk as a DIFFERENT OBJECT — same diff, different sha and subject,
  # which is exactly what ship-land's rebase-then-re-author produces. `git cherry` compares patch
  # ids, so it sees this; ancestry cannot.
  echo landed > "$WORK/landed.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "feat: landed (re-authored on trunk)"
  git -C "$WORK" push -q origin main
}

@test "a declaration whose branch is GONE from origin is retired" {
  decl s-gone claude/fire-never-created 48
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  retired s-gone
  echo "$output" | grep -q 'gone=1'
}

@test "a declaration whose branch is patch-equivalent on the trunk is retired — cherry, not ancestry" {
  push_landed_branch claude/fire-landed
  decl s-landed claude/fire-landed 48
  # the control on the INSTRUMENT: ancestry says this branch is unmerged, which is why the subject
  # must not use it (scripts/branch-prune-landed.sh header: 1 of 97 by ancestry vs 56 by patch id).
  git -C "$WORK" fetch -q origin
  run git -C "$WORK" merge-base --is-ancestor "refs/remotes/origin/claude/fire-landed" origin/main
  [ "$status" -ne 0 ]
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  retired s-landed
  echo "$output" | grep -q 'landed=1'
}

@test "a live branch carrying UNLANDED work is KEPT — the population this must never touch" {
  git -C "$WORK" checkout -q -b claude/fire-live main
  echo work > "$WORK/work.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "feat: real work"
  git -C "$WORK" push -q origin claude/fire-live
  git -C "$WORK" checkout -q main
  decl s-live claude/fire-live 48
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  ! retired s-live || false
  echo "$output" | grep -q 'kept=1'
}

@test "a declaration YOUNGER than the min age is held — 'not created yet' is not 'never created'" {
  # Without this the pass retires every fire the moment it is declared: a session fired four minutes
  # ago has no branch on origin YET, which is the same observation as never having one.
  decl s-young claude/fire-booting 1
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  ! retired s-young || false
  echo "$output" | grep -q 'young-held=1'
  # THE POSITIVE CONTROL, one axis moved — the age. A guard that held EVERYTHING would pass the
  # assertion above while retiring nothing, ever (memory: positive-control-the-denominator).
  CC_RETIRE_MIN_AGE_H=0 run bash "$SUBJ"
  retired s-young
}

@test "a remote answering with ZERO heads is a SENSOR FAILURE, not an empty remote" {
  # Failing open here retires the whole store on one bad read. It must exit 69 and write nothing.
  decl s-a claude/fire-a 48
  decl s-b claude/fire-b 48
  local empty="$BATS_TEST_TMPDIR/empty.git"
  git init --bare --quiet "$empty"
  git -C "$WORK" remote set-url origin "$empty"
  run bash "$SUBJ"
  [ "$status" -eq 69 ]
  ! retired s-a || false
  ! retired s-b || false
  echo "$output" | grep -q 'SENSOR FAILED'
}

@test "an UNREADABLE remote is a sensor failure too, and nothing is retired" {
  decl s-c claude/fire-c 48
  git -C "$WORK" remote set-url origin "$BATS_TEST_TMPDIR/does-not-exist.git"
  run bash "$SUBJ"
  [ "$status" -eq 69 ]
  ! retired s-c
}

@test "--dry-run names what it would retire and writes no marker" {
  decl s-dry claude/fire-absent 48
  run bash "$SUBJ" --dry-run
  [ "$status" -eq 0 ]
  ! retired s-dry || false
  echo "$output" | grep -q 'would retire s-dry'
}

@test "an already-terminal declaration is never re-examined" {
  decl s-done claude/fire-absent 48
  : > "$CC_CLOUD_STATE/s-done.returned"
  decl s-old claude/fire-absent 48
  : > "$CC_CLOUD_STATE/s-old.retired"
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'examined=0'
}

@test "--max bounds what one pass writes, and the counts still report the whole population" {
  local i
  for i in 1 2 3; do decl "s-m$i" "claude/fire-absent-$i" 48; done
  run bash "$SUBJ" --max 1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'gone=3'
  echo "$output" | grep -q 'retired=1'
}
