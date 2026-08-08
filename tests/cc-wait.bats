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

@test "rc 5: ORPHANED waiter ⇒ ABORTED (exit 6), no deadline claim — and it DOES page (G10)" {
  # Title corrected 2026-08-08. This read "nobody paged", which was the behaviour until G10 and is
  # now the defect: an abort that alarms nobody is the same silent loss the contract rung exists to
  # end. "Nobody alive to page" also mis-described the transport — a page is a MAILBOX write, durable
  # by design, so on rc 5 the line stays unacked for cc-inbox-guard and the successor's adoption
  # inherits it. Every assertion that still holds is untouched: ABORTED, exit 6, never a deadline.
  run env CC_AWAIT_BIN="$(awaiter_rc 5)" CC_WAIT_PAGE_CMD="$(page_recorder)" \
    "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 6 ]
  cf="$(contract_file)"
  [ "$(jq -r '.status' "$cf")" = "ABORTED" ]
  [[ "$output" != *"past deadline"* ]] || false
  [[ "$output" == *"provably gone"* ]] || false
  [ -s "$(pages_log)" ]
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

# ══ G10 — AN ABORTED CONTRACT THAT ALARMS NOBODY IS THE SAME SILENT LOSS, ONE LEVEL UP ═══════════
# rc 0 and rc 4 close SATISFIED; rc 2 closes TIMED_OUT and pages. EVERYTHING else fell into a
# catch-all that closed ABORTED and paged no one — so cc-await-ping's measured 144 (the harness's
# sentinel for "the watcher's process GROUP was SIGTERMed", backlog 5b77e20d9db6) closed the
# contract in silence. The wait is over, the waiter is not woken, and nothing says so. The rung
# below the watcher exists precisely to survive the watcher; a mute abort forfeits that.
#
# ABORTED stays distinct from TIMED_OUT and the exit code stays 6 — only 5 is a statement about the
# WAITEE. What changed is that both now reach the pager.
pages_log() { printf '%s' "$BATS_TEST_TMPDIR/pages.log"; }
page_recorder() {   # a --on-timeout page transport that RECORDS instead of swallowing
  local p="$BATS_TEST_TMPDIR/pagerec"
  cat > "$p" <<REC
#!/bin/bash
printf '%s\n' "\$*" >> "$(pages_log)"
REC
  chmod +x "$p"; printf '%s' "$p"
}

@test "G10 POSITIVE CONTROL: the deadline (rc 2) reaches the pager — the recorder is not inert" {
  run env CC_AWAIT_BIN="$(awaiter_rc 2)" CC_WAIT_PAGE_CMD="$(page_recorder)" \
    "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 5 ]
  [ -s "$(pages_log)" ]
  grep -q 'past deadline' "$(pages_log)"
}

@test "G10 NEGATIVE CONTROL: a SATISFIED contract (rc 0) pages nobody" {
  run env CC_AWAIT_BIN="$(awaiter_rc 0)" CC_WAIT_PAGE_CMD="$(page_recorder)" \
    "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 0 ]
  [ ! -s "$(pages_log)" ]
}

@test "G10 THE HOLE: rc 144 (the group-kill sentinel) closes ABORTED and STILL pages" {
  run env CC_AWAIT_BIN="$(awaiter_rc 144)" CC_WAIT_PAGE_CMD="$(page_recorder)" \
    "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 6 ]
  [ "$(jq -r '.status' "$(contract_file)")" = "ABORTED" ]
  [ -s "$(pages_log)" ]
  grep -q 'ABORTED' "$(pages_log)"
  ! grep -q 'past deadline' "$(pages_log)" || false   # never a false claim about the WAITEE
}

@test "G10: rc 143 (the watcher alone was TERMed) pages too — same silence, different number" {
  run env CC_AWAIT_BIN="$(awaiter_rc 143)" CC_WAIT_PAGE_CMD="$(page_recorder)" \
    "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 6 ]
  [ -s "$(pages_log)" ]
}

@test "G10: rc 3 (nothing to watch) pages — an unowned wait is exactly what this rung is for" {
  run env CC_AWAIT_BIN="$(awaiter_rc 3)" CC_WAIT_PAGE_CMD="$(page_recorder)" \
    "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout reobserve
  [ "$status" -eq 6 ]
  [ -s "$(pages_log)" ]
}

@test "G10: an ABORTED escalate goes to the ESCALATION target, not silently to the waiter" {
  run env CC_AWAIT_BIN="$(awaiter_rc 144)" CC_WAIT_PAGE_CMD="$(page_recorder)" \
    CC_WAIT_PAGE_TARGET="DESK-0000-0000-0000-000000000000" \
    "$WAIT" --waiter "$UUID" --waitee peer --signal ping --deadline 60 --on-timeout escalate
  [ "$status" -eq 6 ]
  grep -q 'DESK-0000-0000-0000-000000000000' "$(pages_log)"
}
