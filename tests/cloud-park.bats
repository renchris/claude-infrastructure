#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is *meant* to be test-local.
#
# cloud-park.sh — the writer half of the cloud park channel; scripts/cloud-return.sh step 8 is the
# reader half and is pinned by tests/cloud-return.bats § THE PARK.
#
# WHAT THIS SUITE IS GUARDING. A park is executed UNATTENDED on the operator's box, days later, by a
# sweep nobody is watching. Every defect available to this writer therefore surfaces there and not
# here, so the refusals are the point: a malformed park lands looking exactly like a good one, and
# the row it was supposed to take out of the dispatch wave stays in it.
#
# HERMETIC: a real git repo built in $BATS_TEST_TMPDIR with the file under test COPIED IN. Copied,
# not run in place — the script writes relative to its own parent directory, so running the repo's
# own copy would write docs/parks/ into the checkout the suite is running from.

setup() {
  command -v git >/dev/null 2>&1 || skip "git required"
  # Fixtured before anything runs: the subject shells out to git, which reads ~/.gitconfig, and a
  # suite that reaches the operator's live ~/ is untrustworthy whatever it then asserts.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SRC="${BATS_TEST_DIRNAME}/../scripts/cloud-park.sh"
  [ -f "$SRC" ] || skip "cloud-park.sh not found"

  export REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts"
  cp "$SRC" "$REPO/scripts/cloud-park.sh"; chmod +x "$REPO/scripts/cloud-park.sh"
  SUT="$REPO/scripts/cloud-park.sh"
  git init -q "$REPO"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
  git -C "$REPO" checkout -q -b claude/fire-20260829T172745Z-63903-1
}

@test "--selftest drives the guards with no repo at all" {
  run bash "$SUT" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"12/12"* ]] || false
}

@test "a park names the branch it was written on, and that branch is READ, never asserted" {
  # `branch:` is the whole reason a park cannot outlive its dispatch, so it must be a fact about
  # HEAD. If it were an argument, a worker could write any branch it liked and a stale entry would
  # be indistinguishable from a live one.
  run bash "$SUT" f85fce7c26f5 --needs "bash scripts/cloud-land-arm-diagnose.sh"
  [ "$status" -eq 0 ]
  [ -f "$REPO/docs/parks/f85fce7c26f5.md" ]
  grep -q '^branch: claude/fire-20260829T172745Z-63903-1$' "$REPO/docs/parks/f85fce7c26f5.md"
  grep -q '^needs: bash scripts/cloud-land-arm-diagnose.sh$' "$REPO/docs/parks/f85fce7c26f5.md"
}

@test "a second park APPENDS — one dispatch's statement never deletes another's" {
  bash "$SUT" f85fce7c26f5 --needs "the first step" >/dev/null
  git -C "$REPO" checkout -q -b claude/fire-later
  bash "$SUT" f85fce7c26f5 --needs "the second step" >/dev/null
  f="$REPO/docs/parks/f85fce7c26f5.md"
  [ "$(grep -c '^needs: ' "$f")" -eq 2 ]
  grep -q '^needs: the first step$' "$f"                       # history survives …
  [ "$(sed -n 's/^needs: *//p' "$f" | tail -1)" = "the second step" ]   # … and the LAST is the live one
  [ "$(sed -n 's/^branch: *//p' "$f" | tail -1)" = "claude/fire-later" ]
  [ "$(grep -c '^# park log' "$f")" -eq 1 ]                    # the header is written once, not per entry
}

@test "an id that is not the store's key shape is REFUSED, not written" {
  run bash "$SUT" "cc-offload brief.txt" --needs "a step"
  [ "$status" -eq 2 ]
  [[ "$output" == *"12 lowercase hex"* ]] || false
  [ ! -d "$REPO/docs/parks" ]
}

@test "an empty --needs is REFUSED — cc-backlog block rejects it, and a park nobody can execute is worse than none" {
  run bash "$SUT" f85fce7c26f5
  [ "$status" -eq 2 ]
  [[ "$output" == *"ONE non-empty line"* ]] || false
  [ ! -d "$REPO/docs/parks" ]
}

@test "a MULTI-LINE --needs is REFUSED — the reader takes one line, and the drop would be silent" {
  run bash "$SUT" f85fce7c26f5 --needs "$(printf 'run this\nthen run that')"
  [ "$status" -eq 2 ]
  [ ! -d "$REPO/docs/parks" ]
  # the positive control on the same axis: one line, same length class, is written
  run bash "$SUT" f85fce7c26f5 --needs "run this then run that"
  [ "$status" -eq 0 ]
}

@test "a DETACHED HEAD is REFUSED — a park with no branch is a permanent block" {
  git -C "$REPO" checkout -q --detach
  run bash "$SUT" f85fce7c26f5 --needs "a step"
  [ "$status" -eq 2 ]
  [[ "$output" == *"detached"* ]] || false
  [ ! -f "$REPO/docs/parks/f85fce7c26f5.md" ]
}

@test "it does NOT commit, land or notify — it says what the next step is and stops" {
  run bash "$SUT" f85fce7c26f5 --needs "a step"
  [ "$status" -eq 0 ]
  [ -n "$(git -C "$REPO" status --porcelain)" ]        # the file is left UNCOMMITTED, deliberately
  [[ "$output" == *"NOT in effect until this file is on trunk"* ]] || false
  [[ "$output" == *"cc-backlog block f85fce7c26f5 --needs"* ]] || false
}
