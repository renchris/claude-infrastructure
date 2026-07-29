#!/usr/bin/env bats
# comms alarm store hygiene — hooks/lib/comms-alarm.sh (the write chokepoint) and
# bin/cc-comms-alarm-sweep (audit / assert-clean / quarantine).
#
# WHY (backlog 817faf3a4968, measured 2026-07-29): ~/.claude/autonomy/comms-alarms held 1273 records
# and 511 of them (40.1%) were test fixture data — tests/cc-notify.bats fixtured CC_REGISTRY_DIR and
# CC_MAILBOX_DIR but not CC_COMMS_ALARM_DIR, so its three inbox-unwritable tests appended to the
# operator's LIVE store on every run. cc-inbox-guard phones once per enqueue-fail record, so those
# 510 records were 510 pages about a failure that never happened; and every rebuild that re-derives
# constants from primary disk truth read a 40%-fixture denominator.
#
# Harness rules (this repo's earned ones):
#   1. `|| false` on every non-final `[[ ]]` / `!` / `A && B` — bats does not trap those (errexit
#      exempts them), so without it the assertion is DEAD. Bare `[ ]` IS live.
#   2. POSITIVE CONTROLS are mandatory here. A sweep that moved EVERYTHING would satisfy every
#      "the fixture record left the root" assertion, and a divert that fired unconditionally would
#      satisfy every "it did not reach the root" assertion. Both are proven falsifiable below.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="$REPO/bin/cc-comms-alarm-sweep"
  GUARD="$REPO/bin/cc-inbox-guard"
  LIB="$REPO/hooks/lib/comms-alarm.sh"

  # Fixture $HOME: the subject resolves its live-default store under it, and the divert decision is
  # "is the target dir the live default?" — so a real $HOME would make this suite the very leak it
  # tests. Hermetic, hence NOT on the test-hermeticity ratchet's allowlist.
  export HOME="$BATS_TEST_TMPDIR/home"
  LIVE="$HOME/.claude/autonomy/comms-alarms"
  mkdir -p "$LIVE"

  STORE="$BATS_TEST_TMPDIR/store"
  mkdir -p "$STORE"
  unset CC_COMMS_ALARM_DIR CC_COMMS_ALARM_TEST_ORIGIN

  # shellcheck source=/dev/null
  . "$LIB"
}

# the exact literal triple the leaking suite wrote (rule R1)
fixture_r1() { printf '{"kind":"enqueue-failed","target":"AAAAAAAA-1111-2222-3333-444444444444","from":"claude-next","msg":"cannot persist","ts":"2026-07-20T09:40:22Z"}\n' > "$1"; }
# verbatim from the live store: a REAL undelivered alarm whose target ALSO appears as a literal in
# tests/cc-reconcile.bats. The "appears in tests/" classifier would have destroyed 256 of these.
real_uuid_in_tests() { printf '{"kind":"undelivered","uuid":"D08B4FC0-9253-4F54-A699-7D45CE568F84","reason":"LIVE session, 382 message(s) unconsumed for 102415s past deadline","ts":"2026-07-20T15:37:56Z"}\n' > "$1"; }
# verbatim from the live store: a REAL alarm whose target is not a UUID at all. The
# "structurally synthetic target" classifier would have destroyed 23 of these.
real_synthetic_looking() { printf '{"kind":"undelivered","uuid":"DESK-UUID-1","reason":"17 message(s) unconsumed 16896s AND owner liveness INDETERMINATE","ts":"2026-07-26T22:58:48Z"}\n' > "$1"; }

n_root() { find "$1" -maxdepth 1 -type f \( -name '*.json' -o -name '*.json.handled' \) 2>/dev/null | grep -c . || true; }
n_leak() { find "$1/test-leak" -type f -name '*.json' 2>/dev/null | grep -c . || true; }

# ── the chokepoint ──────────────────────────────────────────────────────────────────────────────

@test "test-origin: a bats context is self-identifying, and names the suite file" {
  run comms_alarm_test_origin
  [ "$status" -eq 0 ]
  [ "$output" = "bats:cc-comms-alarm-sweep.bats" ]
}

@test "test-origin POSITIVE CONTROL: with no harness vars it reports PRODUCTION (rc 1, empty)" {
  # Without this, every divert assertion below could pass because the detector says "test" always.
  run env -u BATS_TEST_FILENAME -u BATS_TEST_TMPDIR -u BATS_RUN_TMPDIR -u CC_COMMS_ALARM_TEST_ORIGIN \
    bash -c ". '$LIB'; comms_alarm_test_origin"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a FIXTURE-context write to the LIVE default is DIVERTED out of the root, not appended" {
  run comms_alarm_write enqueue-fail '{"kind":"enqueue-failed","target":"X","msg":"cannot persist"}'
  [ "$status" -eq 1 ]                      # a real verdict, not a silent success
  [ "$(n_root "$LIVE")" -eq 0 ]            # the live root — the thing that was 40% fixture — is clean
  [ "$(n_leak "$LIVE")" -eq 1 ]            # the evidence is preserved, never discarded
}

@test "the diverted record is STAMPED test_origin naming the suite (no magic-UUID matching needed)" {
  comms_alarm_write enqueue-fail '{"kind":"enqueue-failed","target":"X","msg":"cannot persist"}' || true
  f="$(find "$LIVE/test-leak" -type f -name '*.json' | head -1)"
  [ -n "$f" ]
  [ "$(jq -r .test_origin "$f")" = "bats:cc-comms-alarm-sweep.bats" ]
  [ "$(jq -r .kind "$f")" = "enqueue-failed" ]   # the payload survives the stamp
}

@test "the divert SHOUTS, and the shout names the two-line fix" {
  run comms_alarm_write enqueue-fail '{"kind":"enqueue-failed","target":"X"}'
  [[ "$output" == *"HERMETICITY VIOLATION"* ]] || false
  [[ "$output" == *"CC_COMMS_ALARM_DIR"* ]] || false
  [[ "$output" == *"setup()"* ]] || false
}

@test "a fixture write to a FIXTURED dir lands there, stamped, rc 0 — not diverted" {
  export CC_COMMS_ALARM_DIR="$STORE"
  run comms_alarm_write enqueue-fail '{"kind":"enqueue-failed","target":"X","msg":"cannot persist"}'
  [ "$status" -eq 0 ]
  [ "$(n_root "$STORE")" -eq 1 ]
  [ "$(n_leak "$STORE")" -eq 0 ]
  f="$(find "$STORE" -maxdepth 1 -type f -name '*.json' | head -1)"
  # stamped even here, so test_origin is a TOTAL signal every reader can key on
  [ "$(jq -r .test_origin "$f")" = "bats:cc-comms-alarm-sweep.bats" ]
}

@test "POSITIVE CONTROL: a PRODUCTION write reaches the live root, unstamped (divert is conditional)" {
  # The load-bearing control. If the chokepoint diverted unconditionally it would break the very
  # backstop it protects — a real enqueue failure would vanish from the store the guard escalates.
  run env -u BATS_TEST_FILENAME -u BATS_TEST_TMPDIR -u BATS_RUN_TMPDIR -u CC_COMMS_ALARM_DIR \
    -u CC_COMMS_ALARM_TEST_ORIGIN HOME="$HOME" \
    bash -c ". '$LIB'; comms_alarm_write enqueue-fail '{\"kind\":\"enqueue-failed\",\"target\":\"REAL\"}'"
  [ "$status" -eq 0 ]
  [ "$(n_root "$LIVE")" -eq 1 ]
  [ "$(n_leak "$LIVE")" -eq 0 ]
  f="$(find "$LIVE" -maxdepth 1 -type f -name '*.json' | head -1)"
  [ "$(jq -r '.test_origin // "ABSENT"' "$f")" = "ABSENT" ]
}

@test "CC_COMMS_ALARM_TEST_ORIGIN declares a fixture context for harnesses bats does not run" {
  run env -u BATS_TEST_FILENAME -u BATS_TEST_TMPDIR -u BATS_RUN_TMPDIR HOME="$HOME" \
    CC_COMMS_ALARM_TEST_ORIGIN="selftest:foo" \
    bash -c ". '$LIB'; comms_alarm_write enqueue-fail '{\"kind\":\"enqueue-failed\"}'"
  [ "$status" -eq 1 ]
  [ "$(n_root "$LIVE")" -eq 0 ]
  f="$(find "$LIVE/test-leak" -type f -name '*.json' | head -1)"
  [ "$(jq -r .test_origin "$f")" = "selftest:foo" ]
}

# ── the store assertion + sweep ─────────────────────────────────────────────────────────────────

@test "--assert-clean is RED on the legacy contamination and names the matching rule" {
  fixture_r1 "$STORE/enqueue-fail-1.json.handled"
  real_uuid_in_tests "$STORE/undelivered-1.json"
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --assert-clean
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONTAMINATED — 1 of 2"* ]] || false
  [[ "$output" == *"R1 enqueue-fail/cannot-persist=1"* ]] || false
}

@test "--assert-clean is GREEN on a store of only real records" {
  real_uuid_in_tests "$STORE/undelivered-1.json"
  real_synthetic_looking "$STORE/undelivered-2.json"
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --assert-clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLEAN"* ]] || false
}

@test "--sweep quarantines the fixture record and KEEPS both real ones (positive control)" {
  fixture_r1 "$STORE/enqueue-fail-1.json.handled"
  real_uuid_in_tests "$STORE/undelivered-1.json"
  real_synthetic_looking "$STORE/undelivered-2.json"
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --sweep
  [ "$status" -eq 0 ]
  [ ! -e "$STORE/enqueue-fail-1.json.handled" ]
  # These two are the records the two REJECTED classifiers would have destroyed. Their survival is
  # the whole reason origin is decided by literal rules and not by the shape of a target token.
  [ -e "$STORE/undelivered-1.json" ]
  [ -e "$STORE/undelivered-2.json" ]
}

@test "R1 needs ALL THREE fields — same UUID, different msg, is KEPT (the rule cannot widen)" {
  printf '{"kind":"enqueue-failed","target":"AAAAAAAA-1111-2222-3333-444444444444","msg":"disk full","ts":"2026-07-20T09:40:22Z"}\n' > "$STORE/enqueue-fail-real.json"
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --sweep
  [ -e "$STORE/enqueue-fail-real.json" ]
  [[ "$output" == *"nothing to sweep"* ]] || false
}

@test "R0: any record carrying test_origin is fixture-origin regardless of its payload" {
  printf '{"kind":"undelivered","uuid":"D08B4FC0-9253-4F54-A699-7D45CE568F84","reason":"looks utterly real","test_origin":"bats:x.bats"}\n' > "$STORE/undelivered-1.json"
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --sweep
  [ "$status" -eq 0 ]
  [ ! -e "$STORE/undelivered-1.json" ]
}

@test "the sweep is ARCHIVAL, never deletion — the record is in quarantine with a rule-stamped manifest" {
  fixture_r1 "$STORE/enqueue-fail-1.json.handled"
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --sweep
  q="$(find "$STORE/quarantine" -type f -name 'enqueue-fail-*' | head -1)"
  [ -n "$q" ]
  [ "$(jq -r .target "$q")" = "AAAAAAAA-1111-2222-3333-444444444444" ]
  m="$(find "$STORE/quarantine" -name manifest.jsonl | head -1)"
  [ -n "$m" ]
  [ "$(jq -r .rule "$m")" = "R1" ]
}

@test "--dry-run reports the census and mutates NOTHING" {
  fixture_r1 "$STORE/enqueue-fail-1.json.handled"
  real_uuid_in_tests "$STORE/undelivered-1.json"
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --sweep --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD quarantine 1 of 2"* ]] || false
  [ -e "$STORE/enqueue-fail-1.json.handled" ]
  [ ! -d "$STORE/quarantine" ]
}

@test "quarantine and test-leak are NEVER re-scanned (the sweep cannot eat its own output)" {
  fixture_r1 "$STORE/enqueue-fail-1.json.handled"
  CC_COMMS_ALARM_DIR="$STORE" "$SWEEP" --sweep >/dev/null
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --assert-clean
  [ "$status" -eq 0 ]
  # still there after a second pass — quarantine is a destination, not a queue
  [ -n "$(find "$STORE/quarantine" -type f -name 'enqueue-fail-*' | head -1)" ]
}

@test "an absent store dir is LOUD (exit 2), never a silent-green 'clean'" {
  CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/nope" run "$SWEEP" --assert-clean
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not exist"* ]] || false
}

@test "--audit counts the diverted records so they are visible, not merely absent from the root" {
  real_uuid_in_tests "$STORE/undelivered-1.json"
  mkdir -p "$STORE/test-leak"
  fixture_r1 "$STORE/test-leak/enqueue-fail-x.json"
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"diverted (test-leak) 1"* ]] || false
  [[ "$output" == *"fixture-origin ..... 0"* ]] || false
}

@test "--selftest is GREEN (the tool's own RED-proof, chained into the corpus)" {
  run "$SWEEP" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREEN"* ]] || false
}

@test "an unknown argument is a usage error, not a default-to-audit" {
  CC_COMMS_ALARM_DIR="$STORE" run "$SWEEP" --wat
  [ "$status" -eq 2 ]
}

# ── the operator-paging fix ─────────────────────────────────────────────────────────────────────

@test "cc-inbox-guard does NOT page for a test_origin record, but DOES for a real one" {
  # This is the measured harm: the guard phones once per enqueue-fail record, and 510 of the 511 in
  # the live store were fixture. Excluding them by FIELD is what test_origin exists for.
  A="$BATS_TEST_TMPDIR/alarms"; mkdir -p "$A" "$BATS_TEST_TMPDIR/mbox"
  printf '{"kind":"enqueue-failed","target":"T1","msg":"cannot persist","test_origin":"bats:x.bats"}\n' > "$A/enqueue-fail-fix.json"
  printf '{"kind":"enqueue-failed","target":"T2","msg":"real failure"}\n' > "$A/enqueue-fail-real.json"
  run env CC_COMMS_ALARM_DIR="$A" CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox" \
    CC_INBOX_GUARD_STATE_DIR="$BATS_TEST_TMPDIR/gstate" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl" \
    "$GUARD" sweep --dry-run
  [[ "$output" == *"SKIP [enqueue-fail] T1"* ]] || false
  [[ "$output" == *"test_origin=bats:x.bats"* ]] || false
  # POSITIVE CONTROL: the real record still escalates — the skip is keyed on the field, not the loop.
  [[ "$output" == *"WOULD-ESCALATE [enqueue-fail] T2"* ]] || false
}

@test "cc-inbox-guard consumes a fixture record without phoning (no page, but not left to re-fire)" {
  A="$BATS_TEST_TMPDIR/alarms"; mkdir -p "$A" "$BATS_TEST_TMPDIR/mbox"
  P="$BATS_TEST_TMPDIR/push.log"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$P" > "$BATS_TEST_TMPDIR/push"
  chmod +x "$BATS_TEST_TMPDIR/push"
  printf '{"kind":"enqueue-failed","target":"T1","msg":"cannot persist","test_origin":"bats:x.bats"}\n' > "$A/enqueue-fail-fix.json"
  env CC_COMMS_ALARM_DIR="$A" CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox" \
    CC_INBOX_GUARD_STATE_DIR="$BATS_TEST_TMPDIR/gstate" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl" \
    CC_INBOX_GUARD_PUSH_BIN="$BATS_TEST_TMPDIR/push" "$GUARD" sweep >/dev/null 2>&1 || true
  [ ! -s "$P" ]                                    # the operator's phone stayed silent
  [ ! -e "$A/enqueue-fail-fix.json" ]              # consumed, so it cannot re-fire every sweep
  [ -e "$A/enqueue-fail-fix.json.handled" ]
}
