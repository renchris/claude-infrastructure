#!/usr/bin/env bats
# reap-freshness.bats — the DECISION-FRESHNESS LEASE (SESSION_REGISTRY_V2 §4.3, R1).
#
# The lease is the mechanism that makes "a reap decision is never more than 60s stale" structural
# instead of aspirational: cc-teardown REFUSES a decision older than the lease, so a slow sweep
# reaps NOTHING rather than acting on a verdict the world outran (the 2026-07-24 live-conversation
# reaps happened on evidence frozen at sweep start and acted on minutes later).
#
# Assertion style: `[ ]` throughout — a non-final `[[ ]]`/`(( ))` is errexit-EXEMPT under bats and
# therefore a DEAD assertion (memory: bats-dead-assertions-errexit-exemptions). Where `[[ ]]` is
# unavoidable it carries `|| false`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Fixture $HOME FIRST: cc-teardown resolves its records dir, the it2 shim and the beat/who libs
  # under $HOME by default. An unfixtured suite would read the operator's LIVE session registry and
  # could act on a REAL pane — the one class of test defect this subsystem must never ship.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  T="$REPO/bin/cc-teardown"
  export CC_TEARDOWN_RECORDS_DIR="$BATS_TEST_TMPDIR/rec"
  export CC_TEARDOWN_SELF_UUID="none"
  # Mock rig: a live registry row, a pane list that contains it, and an OK work-safety gate — so
  # every refusal this suite observes is attributable to the LEASE and nothing else.
  printf '#!/bin/bash\necho "[{\\"paneUUID\\":\\"U9\\",\\"name\\":\\"t\\",\\"pid\\":'"$$"',\\"cwd\\":\\"/tmp\\",\\"session_id\\":\\"s\\"}]"\n' > "$BATS_TEST_TMPDIR/cc-sessions"
  printf '#!/bin/bash\n[ "$1" = session ] && [ "$2" = list ] && { echo "[{\\"id\\":\\"U9\\"},{\\"id\\":\\"DESK\\"}]"; exit 0; }\nexit 0\n' > "$BATS_TEST_TMPDIR/it2"
  printf '#!/bin/bash\necho "{\\"decision\\":\\"OK\\",\\"git_state\\":\\"clean\\"}"; exit 0\n' > "$BATS_TEST_TMPDIR/gate"
  chmod +x "$BATS_TEST_TMPDIR/cc-sessions" "$BATS_TEST_TMPDIR/it2" "$BATS_TEST_TMPDIR/gate"
  export CC_TEARDOWN_SESSIONS_BIN="$BATS_TEST_TMPDIR/cc-sessions"
  export IT2_BIN="$BATS_TEST_TMPDIR/it2"
  export CC_TEARDOWN_GATE_BIN="$BATS_TEST_TMPDIR/gate"
}

reason_kind() { # → the reason_kind of the newest decision record
  local rec
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' 2>/dev/null | head -1)"
  [ -n "$rec" ] || return 1
  jq -r '.reason_kind // empty' "$rec" 2>/dev/null
}

@test "A3: a STALE decision (older than the 60s lease) is REFUSED (exit 2) and recorded as stale-decision" {
  run "$T" U9 --done-evidence "x" --decided-at "$(( $(date +%s) - 120 ))"
  [ "$status" -eq 2 ]
  [ "$(reason_kind)" = "stale-decision" ]
}

@test "A4 POSITIVE CONTROL: a FRESH decision is NOT refused by the lease" {
  # Beside the absence assertion above: proves the lease can PASS, so A3's refusal is attributable
  # to staleness and not to a rig that refuses everything. A fresh call must not produce the
  # stale-decision record; whatever it does downstream is another gate's business.
  run "$T" U9 --done-evidence "x" --decided-at "$(date +%s)"
  [ "$(reason_kind)" != "stale-decision" ]
}

@test "the lease is MANDATORY: an autonomous teardown with NO --decided-at is refused (an opt-in lease is not a lease)" {
  run "$T" U9 --done-evidence "x"
  [ "$status" -eq 2 ]
  [ "$(reason_kind)" = "lease-missing" ]
}

@test "a decision from the FUTURE is refused (bad clock / forged decision, never freshness)" {
  run "$T" U9 --done-evidence "x" --decided-at "$(( $(date +%s) + 3600 ))"
  [ "$status" -eq 2 ]
  [ "$(reason_kind)" = "lease-future" ]
}

@test "boundary: exactly AT the lease passes, one second past it refuses" {
  # The clock is PINNED (CC_CLASSIFY_NOW — the same seam the lease reads). Computing the offset from
  # a live `date` here makes the 60-vs-61 boundary race a real second tick between the test's clock
  # and the script's, which is a flaky TEST, not a real defect. Pin both sides to the same instant.
  NOW=1785000000
  CC_CLASSIFY_NOW="$NOW" run "$T" U9 --done-evidence "x" --decided-at "$(( NOW - 60 ))"
  [ "$(reason_kind)" != "stale-decision" ]
  rm -rf "$CC_TEARDOWN_RECORDS_DIR"
  CC_CLASSIFY_NOW="$NOW" run "$T" U9 --done-evidence "x" --decided-at "$(( NOW - 61 ))"
  [ "$status" -eq 2 ]
  [ "$(reason_kind)" = "stale-decision" ]
}

# The next three are DIFFERENTIAL by construction. Asserting only "the switch made it pass" is
# vacuous on a tree that has no lease at all (verified: that shape went GREEN against the pristine
# pre-change tree, proving nothing). Each therefore pins BOTH arms — switch-off refuses, switch-on
# passes — so the test can only go green where the lease genuinely exists AND is genuinely bypassable.

@test "kill switch CC_REAP_LEASE=off disables the lease — and WITHOUT it the same call refuses" {
  run "$T" U9 --done-evidence "x" --decided-at "$(( $(date +%s) - 9999 ))"
  [ "$status" -eq 2 ]
  [ "$(reason_kind)" = "stale-decision" ]
  rm -rf "$CC_TEARDOWN_RECORDS_DIR"
  CC_REAP_LEASE=off run "$T" U9 --done-evidence "x" --decided-at "$(( $(date +%s) - 9999 ))"
  [ "$(reason_kind)" != "stale-decision" ]
}

@test "CC_REAP_DECISION_MAX_STALE_S widens the lease — and at the default the same call refuses" {
  run "$T" U9 --done-evidence "x" --decided-at "$(( $(date +%s) - 120 ))"
  [ "$status" -eq 2 ]
  [ "$(reason_kind)" = "stale-decision" ]
  rm -rf "$CC_TEARDOWN_RECORDS_DIR"
  CC_REAP_DECISION_MAX_STALE_S=600 run "$T" U9 --done-evidence "x" --decided-at "$(( $(date +%s) - 120 ))"
  [ "$(reason_kind)" != "stale-decision" ]
}

@test "--force-adopted (operator-only) exempts the lease — and without it the same call refuses" {
  run "$T" U9 --done-evidence "x"
  [ "$status" -eq 2 ]
  [ "$(reason_kind)" = "lease-missing" ]
  rm -rf "$CC_TEARDOWN_RECORDS_DIR"
  run "$T" U9 --done-evidence "x" --force-adopted
  [ "$(reason_kind)" != "lease-missing" ]
}

@test "the sole autonomous caller actually STAMPS the lease (a lease nobody stamps inerts the reaper)" {
  # The R4 trap in miniature: shipping the enforcement without the caller-side stamp would make
  # every reap refuse and report a healthy 100% abstain. Pin the wiring, not just the gate.
  run grep -c -- '--decided-at "\$decided_at"' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "every reaped line carries decided_age (the A8 acceptance read is emitted, not narrated)" {
  run grep -c 'decided_age=' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
