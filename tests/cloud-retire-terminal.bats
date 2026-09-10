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

# ── the two strata that made the pile a fiction (2026-09-05/06) ──────────────────────────────────
# 332 pending declarations were 49 backlog items; 27 of those items were already DONE and held 137
# declarations, and 128 of the 180 open-item branches could not rebase onto trunk. Neither stratum
# had a verdict, so the lane's "pile" read as live work and the dispatcher's pile cap closed the
# lane on it. Both verdicts are terminal, both leave the branch on origin, and both are written
# INTO the marker so the ledger can tell harvested from abandoned.
decl_item() { # <id> <branch> <12-hex item> <age_h>
  local at; at=$(( $(date +%s) - ${4:-48} * 3600 ))
  printf 'id=%s\nbranch=%s\nremote=origin\nrepo=%s\npaths=\nitem=%s\ndeclared_at=%s\ncustody=%s\n' \
    "$1" "$2" "$CLOUD_RETIRE_REPO" "$3" "$at" "$1" > "$CC_CLOUD_STATE/$1.decl"
}
push_work_branch() { # <branch> <file> <content>
  git -C "$WORK" checkout -q -b "$1" main
  printf '%s\n' "$3" > "$WORK/$2"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "feat: $1"
  git -C "$WORK" push -q origin "$1"
  git -C "$WORK" checkout -q main
}
stub_backlog() { # <json array of {id,status}>
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  printf '#!/bin/bash\necho "cc-backlog $*" >>"%s"\nprintf %%s %q\n' "$BATS_TEST_TMPDIR/calls" "$1" > "$BATS_TEST_TMPDIR/stubs/cc-backlog"
  chmod +x "$BATS_TEST_TMPDIR/stubs/cc-backlog"
  export CLOUD_RETIRE_BACKLOG_BIN="$BATS_TEST_TMPDIR/stubs/cc-backlog"
}
stub_custody() {
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  printf '#!/bin/bash\necho "cc-custody $*" >>"%s"\n' "$BATS_TEST_TMPDIR/calls" > "$BATS_TEST_TMPDIR/stubs/cc-custody"
  chmod +x "$BATS_TEST_TMPDIR/stubs/cc-custody"
  export CLOUD_RETIRE_CUSTODY_BIN="$BATS_TEST_TMPDIR/stubs/cc-custody"
}

@test "SUPERSEDED: a live branch whose backlog item is already DONE is retired with that verdict, custody abandoned, branch untouched" {
  push_work_branch claude/fire-dup dup.txt "a second implementation"
  decl_item s-dup claude/fire-dup abcdef012345 48
  stub_backlog '[{"id":"abcdef012345","status":"done"},{"id":"0123456789ab","status":"open"}]'
  stub_custody
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  retired s-dup
  grep -q '^verdict=superseded$' "$CC_CLOUD_STATE/s-dup.retired"
  echo "$output" | grep -q 'superseded=1'
  grep -q 'cc-custody abandon s-dup' "$BATS_TEST_TMPDIR/calls"
  # the branch is NEVER deleted — origin keeps it for forensics
  git -C "$WORK" ls-remote --heads origin claude/fire-dup | grep -q claude/fire-dup
  # ONE backlog read per pass, never one per row
  [ "$(grep -c 'cc-backlog list --all --json' "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
}

@test "SUPERSEDED's reason NAMES the branch measurement — the two populations are separable in the store" {
  # A custody discharge is written ONCE (cc-custody refuses a second one on a marker no longer
  # open), so this reason is the store's final word on the row. `superseded` is the only verdict
  # that does not measure the branch — it reads the ITEM's status — and the case that costs
  # something is a sibling landing PART of a commit. The `git cherry` needed to tell the two apart
  # is already run one screen above, so the count is free; this pins that it reaches the store.
  push_work_branch claude/fire-dup2 dup2.txt "a second implementation"
  decl_item s-dup2 claude/fire-dup2 abcdef012345 48
  stub_backlog '[{"id":"abcdef012345","status":"done"}]'
  stub_custody
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  retired s-dup2
  grep -q '^verdict=superseded$' "$CC_CLOUD_STATE/s-dup2.retired"
  # the branch carries real unlanded work, so the reason must SAY SO and give the count
  grep -q 'cc-custody abandon s-dup2 .*superseded (item closed; branch holds 1 unlanded commit(s)' "$BATS_TEST_TMPDIR/calls"
}

@test "SUPERSEDED's reason says UNMEASURED when the cherry could not run — it never rounds to healthy" {
  # NEGATIVE CONTROL for the case above. Without it, a reason that hardcoded the alarming half would
  # pass case 11 and say the same thing about every row, which is how a signal stops carrying
  # information (repo memory: alarm-polarity-and-attention-budget). There are THREE branch states
  # here, not two, and the third is the one a lookup-miss would silently fold into "nothing was left
  # behind": the cherry did not answer at all. `landed` outranks `superseded`, so a patch-equivalent
  # branch never reaches this arm — an unreadable cherry is the only way to reach it without a count.
  push_work_branch claude/fire-dup3 dup3.txt "a second implementation"
  decl_item s-dup3 claude/fire-dup3 abcdef012345 48
  stub_backlog '[{"id":"abcdef012345","status":"done"}]'
  stub_custody
  # a git that refuses ONLY `cherry` and is otherwise the real one
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  cat > "$BATS_TEST_TMPDIR/stubs/git-nocherry" <<'SH'
#!/bin/bash
for a in "$@"; do [ "$a" = cherry ] && exit 3; done
exec git "$@"
SH
  chmod +x "$BATS_TEST_TMPDIR/stubs/git-nocherry"
  CLOUD_RETIRE_GIT_BIN="$BATS_TEST_TMPDIR/stubs/git-nocherry" run bash "$SUBJ"
  [ "$status" -eq 0 ]
  retired s-dup3
  grep -q '^verdict=superseded$' "$CC_CLOUD_STATE/s-dup3.retired"
  # UNCONDITIONAL: the row was discharged, and its reason must name the non-measurement
  grep -q 'cc-custody abandon s-dup3 ' "$BATS_TEST_TMPDIR/calls"
  grep -q 'cc-custody abandon s-dup3 .*superseded (branch NOT measured' "$BATS_TEST_TMPDIR/calls"
}

@test "SUPERSEDED fails OPEN: an unreadable backlog store yields no superseded verdict, and the branch is KEPT" {
  push_work_branch claude/fire-dup2 dup2.txt "work"
  decl_item s-dup2 claude/fire-dup2 abcdef012345 48
  export CLOUD_RETIRE_BACKLOG_BIN="$BATS_TEST_TMPDIR/does-not-exist"
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  ! retired s-dup2 || false
  echo "$output" | grep -q 'kept=1'
  echo "$output" | grep -q 'superseded=0'
}

@test "CONFLICT: a branch that cannot rebase onto the trunk is retired with that verdict; a CLEAN one is kept" {
  git -C "$WORK" merge-tree --write-tree main main >/dev/null 2>&1 || skip "git merge-tree --write-tree needs git >= 2.38"
  # the conflicting branch edits base.txt; so does trunk, differently
  push_work_branch claude/fire-conflict base.txt "the vm's version"
  push_work_branch claude/fire-clean clean.txt "no overlap"
  printf 'trunk moved\n' > "$WORK/base.txt"
  git -C "$WORK" add -A; git -C "$WORK" commit -qm "feat: trunk moved base.txt"; git -C "$WORK" push -q origin main
  decl_item s-conf  claude/fire-conflict 0123456789ab 48
  decl_item s-clean claude/fire-clean    0123456789ab 48
  stub_backlog '[{"id":"0123456789ab","status":"open"}]'
  stub_custody
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  retired s-conf
  grep -q '^verdict=conflict$' "$CC_CLOUD_STATE/s-conf.retired"
  ! retired s-clean || false
  echo "$output" | grep -q 'conflict=1'
  echo "$output" | grep -q 'kept=1'
  grep -q 'cc-custody abandon s-conf' "$BATS_TEST_TMPDIR/calls"
  ! grep -q 'cc-custody abandon s-clean' "$BATS_TEST_TMPDIR/calls" || false
}

@test "LANDED outranks SUPERSEDED, and only LANDED RETURNS custody — the others abandon it" {
  push_landed_branch claude/fire-landed2
  decl_item s-l2 claude/fire-landed2 abcdef012345 48
  stub_backlog '[{"id":"abcdef012345","status":"done"}]'
  stub_custody
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  grep -q '^verdict=landed$' "$CC_CLOUD_STATE/s-l2.retired"
  grep -q 'cc-custody return s-l2' "$BATS_TEST_TMPDIR/calls"
}
