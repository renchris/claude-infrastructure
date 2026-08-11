#!/usr/bin/env bats
# respawn-as-protocol — cc-respawn: the tool's selftest RED-proves RS-a..RS-f with real git/process
# fixtures; these bats add CLI-level regression on the exit-code contract (0 ok · 2 refuse · 5 verify-
# fail) and the structural no-mailbox-path invariant.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # CC_RESPAWN_BIN lets the same assertions run against a scratch MUTANT copy of the subject, which
  # is how the prefix-match tests below were proven able to go RED (see their header).
  T="${CC_RESPAWN_BIN:-$REPO/bin/cc-respawn}"
  # hermeticity: the subject resolves its records dir under $HOME, so an unfixtured run would read
  # and WRITE the operator's live ~/.claude/respawn (scripts/test-hermeticity-lint.sh rule 1).
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset KITTY_WINDOW_ID
  export CC_RESPAWN_RECORDS_DIR="$BATS_TEST_TMPDIR/records"
}
mkwt() {
  # `git -C ""` is a NO-OP, not an error — an empty $1 would write this identity into the cwd repo.
  : "${1:?mkwt: repo path required}"
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
  [[ "$output" == *"$BATS_TEST_TMPDIR/brief.md"* ]] || false
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

# ── member discovery must be TOKEN-EXACT, not a substring ──────────────────────────────────────────
# The pre-fix subject found a member with `grep -F -- "--agent-name $member"`, so `--agent-name
# tm-api` also matched a live `--agent-name tm-api-worker` — and BOTH verbs then inverted:
# verify-spawned reported a successor that was never spawned as live (a FALSE GO, rc 0), and
# verify-stopped reported a member that IS stopped as STILL ALIVE (rc 5, blocking the respawn
# forever). Every member name that is a PREFIX of a sibling's hits this, which the tm-<area> /
# tm-<area>-worker convention makes ordinary. Both assertions below were RED-proved against a
# scratch copy carrying the old grep line (CC_RESPAWN_BIN=<mutant> bats …).
#
# `; true` prevents bash's implicit-exec optimization — a bare -c 'sleep N' execs sleep and the
# --agent-name argv disappears from ps, which would make these tests pass for the wrong reason.
# The settle budget is sized for THIS box's real load band (measured at 3-4 run-queue/core with
# sibling suites live), not for an idle bench — a bound that only fits the bench turns into a
# permanent non-verdict the moment the machine is busy. It returns NON-ZERO on failure to settle,
# which under bats' set -e fails the test — the vacuous pass this guards is a sibling that never
# became visible in ps, under which the prefix tests below would go green for the wrong reason.
spawn_fake() { # <member> → FAKE_PID, once the argv is actually VISIBLE in ps
  bash -c 'sleep 60; true' fake-claude --agent-name "$1" &
  FAKE_PID=$!
  for _ in $(seq 1 150); do
    ps -p "$FAKE_PID" -o command= 2>/dev/null | grep -q -- "--agent-name $1" && return 0
    perl -e 'select(undef,undef,undef,0.1)'
  done
  reap_fake
  return 1
}
reap_fake() {
  [ -n "${FAKE_PID:-}" ] || return 0
  kill "$FAKE_PID" 2>/dev/null || true
  wait "$FAKE_PID" 2>/dev/null || true
  FAKE_PID=""
}
# The in-test reap runs before the assertions so nothing lingers; this is the net for the path where
# an assertion FAILS and never reaches it. Idempotent — reap_fake clears FAKE_PID.
teardown() { reap_fake; }

@test "RS-f: a PREFIX sibling is not the successor — verify-spawned FAILS LOUD (no false GO)" {
  M="tm-bats-api-$$-$BATS_TEST_NUMBER"
  spawn_fake "$M-worker"
  run "$T" verify-spawned --member "$M"
  reap_fake
  [ "$status" -eq 5 ]
  [[ "$output" == *"FAILED LOUD"* ]] || false
  grep -q '"outcome":"spawn-missing"' "$CC_RESPAWN_RECORDS_DIR/$M.jsonl"
}

@test "RS-c: a PREFIX sibling is not the target — verify-stopped reports OK (no permanent block)" {
  M="tm-bats-api-$$-$BATS_TEST_NUMBER"
  spawn_fake "$M-worker"
  run "$T" verify-stopped --member "$M"
  reap_fake
  [ "$status" -eq 0 ]
  [[ "$output" == *"no '$M' teammate process exists"* ]] || false
}

@test "positive control: an EXACT --agent-name process is still found by both verbs" {
  M="tm-bats-exact-$$-$BATS_TEST_NUMBER"
  spawn_fake "$M"
  run "$T" verify-spawned --member "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FAKE_PID"* ]] || false
  run "$T" verify-stopped --member "$M"
  reap_fake
  [ "$status" -eq 5 ]
}

@test "structural: the tool has NO send-to-target code path (GO cannot be expressed as a message)" {
  # The RS-a naive form is a GO delivered by mailbox/message. cc-respawn must be structurally unable
  # to express it: no invocation of cc-notify / SendMessage / mailbox writes anywhere in the source.
  # (The brief TEXT tells the SUCCESSOR how to announce — that is content, not an invocation.)
  ! grep -nE '^[[:space:]]*(cc-notify|SendMessage)' "$T"
}
