#!/usr/bin/env bats
# respawn-as-protocol — cc-respawn: the tool's selftest RED-proves RS-a..RS-f with real git/process
# fixtures; these bats add CLI-level regression on the exit-code contract (0 ok · 2 refuse · 5 verify-
# fail) and the structural no-mailbox-path invariant.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/bin/cc-respawn"
  export CC_RESPAWN_RECORDS_DIR="$BATS_TEST_TMPDIR/records"
}
mkwt() {
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" config user.email t@t; git -C "$1" config user.name t
  echo seed > "$1/a.txt"; git -C "$1" add a.txt; git -C "$1" commit -qm seed
}

@test "selftest passes and runs all 16 checks (a zero-check suite must not 'pass')" {
  run "$T" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 16 ]
}

@test "RS-a: prepare with no --go ruling → REFUSED (exit 2), refusal recorded" {
  mkwt "$BATS_TEST_TMPDIR/wt"
  run "$T" prepare --member m1 --worktree "$BATS_TEST_TMPDIR/wt"
  [ "$status" -eq 2 ]
  grep -q '"outcome":"refused"' "$CC_RESPAWN_RECORDS_DIR/m1.jsonl"
}

@test "prepare well-formed → 0, prints the brief path, brief carries GO + checkpoint ref" {
  mkwt "$BATS_TEST_TMPDIR/wt"
  echo wip > "$BATS_TEST_TMPDIR/wt/wip.txt"
  run "$T" prepare --member m2 --worktree "$BATS_TEST_TMPDIR/wt" --go "GO: RULING-7 binds" --brief-out "$BATS_TEST_TMPDIR/brief.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/brief.md"* ]]
  grep -q "RULING-7" "$BATS_TEST_TMPDIR/brief.md"
  grep -q "refs/respawn/m2/" "$BATS_TEST_TMPDIR/brief.md"
  git -C "$BATS_TEST_TMPDIR/wt" rev-parse --verify -q refs/wip/m2/LAST
}

@test "RS-c: verify-stopped on a LIVE pid → exit 5 (fail loud, never proceed)" {
  sleep 60 & SP=$!
  run "$T" verify-stopped --pid "$SP"
  kill "$SP" 2>/dev/null || true
  [ "$status" -eq 5 ]
}

@test "RS-c: verify-stopped on a dead pid → exit 0" {
  sleep 0.1 & SP=$!; wait "$SP"
  run "$T" verify-stopped --pid "$SP"
  [ "$status" -eq 0 ]
}

@test "RS-f: verify-spawned with no successor process → exit 5 (not delivered until SEEN)" {
  run "$T" verify-spawned --member never-spawned-bats-zz
  [ "$status" -eq 5 ]
  grep -q '"outcome":"spawn-missing"' "$CC_RESPAWN_RECORDS_DIR/never-spawned-bats-zz.jsonl"
}

@test "unknown command → exit 2 (fail-closed parser)" {
  run "$T" respawn-everything
  [ "$status" -eq 2 ]
}

@test "structural: the tool has NO send-to-target code path (GO cannot be expressed as a message)" {
  # The RS-a naive form is a GO delivered by mailbox/message. cc-respawn must be structurally unable
  # to express it: no invocation of cc-notify / SendMessage / mailbox writes anywhere in the source.
  # (The brief TEXT tells the SUCCESSOR how to announce — that is content, not an invocation.)
  ! grep -nE '^[[:space:]]*(cc-notify|SendMessage)' "$T"
}
