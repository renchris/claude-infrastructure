#!/usr/bin/env bats
# jev-anti-deference-arm — the SAFETY invariants of the semantic arm spliced into
# hooks/anti-deference-nudge.sh. The arm's value case is elsewhere; this file only proves it
# cannot make the hook worse.
#
# The claims, each with its own test, because the argument for landing this rests on all of them
# and a prose assertion of any one is worth nothing:
#   1. With Jev unreachable the hook is exactly the hook it was.        (fail-safe)
#   2. It can only ADD a fire on the `no-tell` population.              (strictly additive)
#   3. It respects the calibrated threshold - a mid-band answer is silence, not a weak yes.
#   4. A hanging gateway can neither hang the hook nor change it.       (bounded)
#   5. The kill switch works even when everything else is present.
#   6. An established lexical arm keeps its own verdict.                (precedence preserved)
#
# 🚨 These run against tests/fixtures/jev-mock-gateway.mjs, NOT against Jev. They prove the
# WIRING. Whether Jev's verdicts are any good on this population is UNMEASURED - no Jev call has
# ever been made from this machine (docs/research/jev-at-cost-api-2026-09-18.md §5).

setup() {
  # Fixture $HOME before anything else. The subject reads and writes under ~/ (state dirs,
  # the IDL, decision packets), so an unfixtured suite would run against the operator's live
  # tree and make every result in this file untrustworthy — the land gate's
  # test-hermeticity ratchet refuses the land for exactly this, and it was right to.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/anti-deference-nudge.sh"
  MOCK="$REPO/tests/fixtures/jev-mock-gateway.mjs"
  export ANTIDEF_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export ANTIDEF_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export ANTIDEF_MAX=3
  export WRAP_TRUNK="origin/main"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_IDL="$BATS_TEST_TMPDIR/cc-idl.jsonl"
  command -v node >/dev/null || skip "node not installed"
  [ -d "$REPO/node_modules/ai" ] || skip "deps not installed"
  # A message carrying NO lexical tell of any of the four arms - this is the 94.7% population.
  # It identifies remaining work and yields, which is the E0 shape the arm exists to catch.
  TELLFREE="I read through the three retry paths and mapped where their backoff constants diverge."
}
# `|| true` guards the STATUS, not just the noise: under bats' errexit a kill whose target
# was already reaped returns 1 and aborts the body, so a test that passed on its own merits
# goes red under load — and only under load. A trailing `; return 0` does not shield it.
teardown() { [ -n "${MPID:-}" ] && { kill "$MPID" 2>/dev/null || true; }; return 0; }

# The TRANSIENT identity form (`git -c …`) is used deliberately: it cannot persist to any
# config. This repo is ONE bare repo behind ~100 shared worktrees, so a fixture running
# `git config user.email` re-authors every session on the machine — 9 mis-attributed commits
# here and 214 on reso, 2026-08-05. `git -C "$w"` is not a fix either: an all-expansion path is
# empty exactly when the accident happens, and `git -C ""` is a documented no-op.
mkrepo() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"
  git clone -q "$o" "$w"
  ( cd "${w:?fixture repo path required}" || exit 1
    git checkout -q -b main
    echo base > base.txt
    git add base.txt
    git -c user.email=fixture@example.invalid -c user.name=fixture commit -q -m base
    git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}

mkfix() {
  local path="$BATS_TEST_TMPDIR/txt-${BATS_TEST_NUMBER}-$RANDOM.jsonl"
  jq -nc --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$path"
  printf '%s' "$path"
}
# $2 (optional) steers the mock's CHOICE answer. The arm fires only when the boolean clears the
# threshold AND blocker_class is "drivable", so a test that wants the fire path must say so.
start_mock() {
  PORTF="$BATS_TEST_TMPDIR/port.$RANDOM"
  MOCK_CHOICE="${2:-}" node "$MOCK" "$1" > "$PORTF" &
  MPID=$!
  local _; for _ in $(seq 1 25); do [ -s "$PORTF" ] && break; sleep 0.2; done
  PORT="$(tr -d '[:space:]' < "$PORTF")"
  [ -n "$PORT" ] || { echo "mock failed to bind"; return 1; }
  export AI_GATEWAY_API_KEY=dummy
  export CC_JEV_BASE_URL="http://127.0.0.1:$PORT"
}
runhook() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "sid-$RANDOM" "$1" "$2" | bash "$HOOK"; }

@test "1. no key: the hook is exactly today's hook - silent on a tell-free message" {
  local w f; w="$(mkrepo n1)"; f="$(mkfix "$TELLFREE")"
  run env -u AI_GATEWAY_API_KEY bash -c "printf '{\"session_id\":\"s\",\"transcript_path\":\"$f\",\"cwd\":\"$w\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run jq -r '.reason' "$ANTIDEF_IDL"
  [ "$output" = "no-tell" ]
}

@test "2. confident Jev ADDS a fire on the no-tell population" {
  start_mock ok drivable
  local w f; w="$(mkrepo n2)"; f="$(mkfix "$TELLFREE")"
  run runhook "$f" "$w"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]] || false
  [[ "$output" == *"semantic"* ]] || false
  run jq -r 'select(.disposition=="fired")|.reason' "$ANTIDEF_IDL"
  [ "$output" = "semantic-deference" ]
}

@test "3. mid-band probability is SILENCE, not a weak yes" {
  start_mock lowp
  local w f; w="$(mkrepo n3)"; f="$(mkfix "$TELLFREE")"
  run runhook "$f" "$w"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run jq -r '.reason' "$ANTIDEF_IDL"
  [ "$output" = "no-tell" ]
}

@test "4. a hanging gateway cannot hang or change the hook" {
  start_mock slow
  export CC_JEV_TIMEOUT_MS=600
  local w f; w="$(mkrepo n4)"; f="$(mkfix "$TELLFREE")"
  run runhook "$f" "$w"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run jq -r '.reason' "$ANTIDEF_IDL"
  [ "$output" = "no-tell" ]
}

@test "5. CC_JEV=0 disables the arm with a key and a reachable gateway present" {
  start_mock ok drivable
  export CC_JEV=0
  local w f; w="$(mkrepo n5)"; f="$(mkfix "$TELLFREE")"
  run runhook "$f" "$w"
  [ -z "$output" ]
  run jq -r '.reason' "$ANTIDEF_IDL"
  [ "$output" = "no-tell" ]
}

@test "6. precedence: an established lexical arm keeps its own FIRE_KIND" {
  start_mock ok drivable
  local w f; w="$(mkrepo n6)"
  # A count-only handover - category-not-idea's population. Jev would also say "defers" here,
  # so this is the test that proves the new arm cannot steal an established arm's verdict.
  f="$(mkfix "Repo is clean, three commits landed. One item still needs your call.")"
  run runhook "$f" "$w"
  [[ "$output" == *'"decision":"block"'* ]] || false
  run jq -r 'select(.disposition=="fired")|.reason' "$ANTIDEF_IDL"
  [ "$output" = "category-not-idea" ]
}

# THE CARVE-OUT, EXPRESSED AS A TYPE. This is the test that justifies asking two questions
# instead of one: a confident "yes it defers" must NOT fire when the wall is genuinely the
# operator's. Without this the arm would nag on exactly the legitimate surfaces the top of
# anti-deference-nudge.sh says it must never touch.
@test "7. blocker_class VETOES a confident boolean when the wall is the operator's" {
  start_mock ok value_fork
  local w f; w="$(mkrepo n7)"; f="$(mkfix "$TELLFREE")"
  run runhook "$f" "$w"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run jq -r '.reason' "$ANTIDEF_IDL"
  [ "$output" = "no-tell" ]
}

@test "8. a credential wall is likewise never nagged" {
  start_mock ok credential_or_sudo
  local w f; w="$(mkrepo n8)"; f="$(mkfix "$TELLFREE")"
  run runhook "$f" "$w"
  [ -z "$output" ]
}
