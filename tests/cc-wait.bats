#!/usr/bin/env bats
# L2 — cc-wait: the CONTRACTED wait primitive. Isolated via CC_WAIT_CONTRACTS_DIR / CC_MAILBOX_DIR.
# The tool's own `selftest` RED-proves the fail-closed refusals + contract-before-wait; these bats add
# CLI-level regression (a real contract file on disk, the real cc-await-ping signal path).

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite, and
  # which shrank in 0d23ec67 to reach this one). The subject resolves its own state under ~, so
  # unfixtured this suite reads and writes the operator's LIVE layer. Everything it asserts is
  # already redirected via CC_WAIT_CONTRACTS_DIR / CC_MAILBOX_DIR; this closes the residue.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WAIT="$REPO/bin/cc-wait"
  export CC_WAIT_CONTRACTS_DIR="$BATS_TEST_TMPDIR/contracts"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_WAIT_CONTRACTS_DIR" "$CC_MAILBOX_DIR"
  # stub await that returns instantly, selectable per-test
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/await-sig";  chmod +x "$BATS_TEST_TMPDIR/await-sig"
  printf '#!/bin/bash\nexit 2\n' > "$BATS_TEST_TMPDIR/await-to";   chmod +x "$BATS_TEST_TMPDIR/await-to"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/nopage";     chmod +x "$BATS_TEST_TMPDIR/nopage"
  export CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/nopage"   # swallow the timeout page (no real cc-notify)
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
}

@test "selftest passes and runs all 8 checks (a zero-check suite must not 'pass')" {
  run "$WAIT" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 8 ]
}

@test "REFUSED (exit 2) with no --deadline" {
  run env CC_AWAIT_BIN="$BATS_TEST_TMPDIR/await-to" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --on-timeout 're-observe peer'
  [ "$status" -eq 2 ]
}

@test "REFUSED (exit 2) with no --on-timeout" {
  run env CC_AWAIT_BIN="$BATS_TEST_TMPDIR/await-to" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60
  [ "$status" -eq 2 ]
}

@test "REFUSED (exit 2) with a reap on-timeout (the S-3b marquee)" {
  run env CC_AWAIT_BIN="$BATS_TEST_TMPDIR/await-to" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout 'reap peer'
  [ "$status" -eq 2 ]
}

@test "writes a valid contract to disk with all fields (enum action + note), then SATISFIED on signal" {
  run env CC_AWAIT_BIN="$BATS_TEST_TMPDIR/await-sig" "$WAIT" --waiter "$UUID" --waitee peer --signal mailbox-line --deadline 3600 --on-timeout reobserve --note 'peer effect (never reap)' --heartbeat none
  [ "$status" -eq 0 ]
  cf="$(ls "$CC_WAIT_CONTRACTS_DIR"/*.json | head -1)"
  [ -f "$cf" ]
  [ "$(jq -r '.waiter' "$cf")" = "$UUID" ]
  [ "$(jq -r '.waitee' "$cf")" = "peer" ]
  [ "$(jq -r '.expected_signal' "$cf")" = "mailbox-line" ]
  [ "$(jq -r '.heartbeat_expectation' "$cf")" = "none" ]
  [ -n "$(jq -r '.deadline' "$cf")" ]
  [ "$(jq -r '.on_timeout_action' "$cf")" = "reobserve" ]
  # the note carries the word 'reap' as free text and is stored VERBATIM — proof the guard never touched it
  [ "$(jq -r '.on_timeout_note' "$cf")" = "peer effect (never reap)" ]
  [ "$(jq -r '.status' "$cf")" = "SATISFIED" ]
}

@test "deadline path exits 5 (TIMED_OUT), pages a re-observe, never reaps" {
  run env CC_AWAIT_BIN="$BATS_TEST_TMPDIR/await-to" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 5 ]
  cf="$(ls "$CC_WAIT_CONTRACTS_DIR"/*.json | head -1)"
  [ "$(jq -r '.status' "$cf")" = "TIMED_OUT" ]
}

@test "REFUSED (exit 2) with a non-allowlisted action a denylist would miss (cleanup)" {
  run env CC_AWAIT_BIN="$BATS_TEST_TMPDIR/await-to" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout cleanup
  [ "$status" -eq 2 ]
}

@test "the real cc-await-ping signal path: a mailbox ping satisfies the contract" {
  ( sleep 1; printf '2026-07-14T10:00:00+0000 [peer] done\n' >> "$CC_MAILBOX_DIR/$UUID.md" ) &
  writer=$!
  run "$WAIT" --waiter "$UUID" --waitee peer --signal mailbox-line --deadline 10 --on-timeout reobserve --interval 1
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  cf="$(ls "$CC_WAIT_CONTRACTS_DIR"/*.json | head -1)"
  [ "$(jq -r '.status' "$cf")" = "SATISFIED" ]
}

# ══ THE WATCHER'S NON-ZERO CODES ARE VERDICTS, NOT ONE UNDIFFERENTIATED FAILURE (2026-07-31) ═════
# The deadline arm used to be a bare fall-through from `rc -eq 0`, while its comment asserted
# "cc-await-ping exit 2". So two designed verdicts were reported as their own opposite: rc 4 (the mail
# WAS delivered, only the cursor write failed) closed TIMED_OUT and paged "you may have missed your own
# wake" about a wake that happened, and rc 5 (orphaned — the waiter is provably gone) paged a corpse.
# Glob expansion, not `ls` (SC2012): the contracts dir holds exactly one file per test here.
contract_file() { local f; for f in "$CC_WAIT_CONTRACTS_DIR"/*.json; do [ -f "$f" ] && { printf '%s' "$f"; return 0; }; done; return 1; }
awaiter_rc() { local p="$BATS_TEST_TMPDIR/await-rc$1"; printf '#!/bin/bash\nexit %s\n' "$1" > "$p"; chmod +x "$p"; printf '%s' "$p"; }

@test "rc 4: the signal LANDED (cursor write failed) ⇒ SATISFIED, never a deadline page" {
  run env CC_AWAIT_BIN="$(awaiter_rc 4)" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 0 ]
  cf="$(contract_file)"
  [ "$(jq -r '.status' "$cf")" = "SATISFIED" ]
  [[ "$output" != *"past deadline"* ]] || false
}

@test "rc 5: ORPHANED waiter ⇒ ABORTED (exit 6), no deadline claim, nobody paged" {
  run env CC_AWAIT_BIN="$(awaiter_rc 5)" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 6 ]
  cf="$(contract_file)"
  [ "$(jq -r '.status' "$cf")" = "ABORTED" ]
  [[ "$output" != *"past deadline"* ]] || false
  [[ "$output" == *"provably gone"* ]] || false
}

@test "rc 3: nothing to watch ⇒ ABORTED, distinct from a timeout" {
  run env CC_AWAIT_BIN="$(awaiter_rc 3)" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 6 ]
  [ "$(jq -r '.status' "$(contract_file)")" = "ABORTED" ]
}

@test "DISCRIMINATOR: rc 2 still means the deadline, and still pages (the arm did not widen)" {
  run env CC_AWAIT_BIN="$(awaiter_rc 2)" "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 5 ]
  [ "$(jq -r '.status' "$(contract_file)")" = "TIMED_OUT" ]
}

@test "the timeout verdict names itself as designed, so its reader does not triage it as a fault" {
  # The harness renders any non-zero background exit as `failed with exit code N`, so the only place a
  # clean timeout can declare itself is the stderr the notification carries.
  run "$REPO/bin/cc-await-ping" "$UUID" --timeout 1 --interval 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"verdict=timeout"* ]] || false
  [[ "$output" == *"DESIGNED outcome"* ]] || false
  [[ "$output" == *"RE-ARM"* ]] || false
}
