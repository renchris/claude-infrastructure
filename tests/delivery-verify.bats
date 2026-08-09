#!/usr/bin/env bats
# delivery-verify — the P0-7 page-delivery PROBE. Synthesizes a DEAD-desk page, drives it through the real
# phone channel (push-send.sh), and returns an HONEST accepted / unwired / failed verdict; --desk also wakes
# the desk role via cc-announce; --receipt confirms device delivery. Stubs both legs (no phone, no panes).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/scripts/delivery-verify.sh"
  export CC_DELIVERY_PROBE_LOG="$BATS_TEST_TMPDIR/probe.log"
  export CC_DELIVERY_POLL_SLEEP=0
}
# stub push-send with a baked send-rc/out and receipt-rc (no env propagation to reason about).
mkpush() { # <name> <send_rc> [send_out] [rcpt_rc]
  local p="$BATS_TEST_TMPDIR/push-$1.sh"
  cat > "$p" <<EOF
#!/bin/bash
case "\${1:-}" in
  send)    [ -n '$3' ] && printf '%s\n' '$3'; exit $2 ;;
  receipt) exit ${4:-0} ;;
  *)       exit 2 ;;
esac
EOF
  chmod +x "$p"; echo "$p"
}
mkann() { local p="$BATS_TEST_TMPDIR/ann-$1.sh"; { printf '#!/bin/bash\n'; printf 'exit %s\n' "$2"; } > "$p"; chmod +x "$p"; echo "$p"; }

# CHANGED 2026-08-09 — was `-eq 7`, the class 404c832a retired for activation-watch (whose count had
# already been bumped 7 → 14 → 18 → 26 by four commits that did nothing but ADD checks). An exact
# ok-count is a tripwire on the growth of the very suite it guards — the NUMBER, not a defect, is what
# gets "fixed" — and it never asserted the premise in its own name: `-eq 7` conflates "non-vacuous"
# with "exactly this many", so a reporter claiming 14 passed while rendering 7 `ok` lines sails
# through. What survives is that premise, as the two independent things that make a suite non-vacuous:
#   FLOOR — a DOWNWARD ratchet. Growth passes freely; a DELETED check reds, and lowering the floor has
#           to be a deliberate edit (memory: downward-ratchet-catches-the-over-scoped-marker).
#   TALLY — the summary's own `N passed` must equal the `  ok ` lines it actually rendered. That is the
#           vacuous-pass class this test is named for (memory: claimed-outcome-vs-checked-outcome).
# The count is environment-stable: 7 unconditional okp/badp sites, each emitting exactly one line.
@test "selftest passes, is non-vacuous (floor), and its tally matches what it rendered" {
  floor=7                         # raise when checks are added; LOWERING it is a deliberate act
  run "$P" --selftest
  [ "$status" -eq 0 ]
  # `|| true` normalizes grep's rc-1-on-zero-matches, which would otherwise abort the test HERE and
  # never reach the floor. It swallows no verdict — the count is data, the assertions below are the
  # verdict (contrast memory: claimed-outcome-vs-checked-outcome).
  ok_lines="$(printf '%s' "$output" | grep -c '^  ok ' || true)"
  claimed="$(printf '%s' "$output" | sed -n 's/^delivery-verify --selftest: \([0-9][0-9]*\) passed,.*/\1/p')"
  [ "$ok_lines" -ge "$floor" ]
  # Two statements, never `[ -n "$claimed" ] && [ ... ]`: in an `&&` list set -e sees only the command
  # after the FINAL `&&`, so a short-circuit on the left half is ABSORBED and an unparseable summary
  # would pass vacuously — the very class this test exists to catch (tests/bats-assert-liveness.bats
  # classifies that shape `and-absorbed`).
  [ -n "$claimed" ]
  [ "$claimed" = "$ok_lines" ]
}

@test "phone accepted → PROBE PASSED (exit 0), a synthetic DEAD page fired, logged PASS" {
  CC_PUSH_SEND_BIN="$(mkpush ok 0)" run "$P"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ACCEPTED the DEAD page'
  echo "$output" | grep -q 'PROBE PASSED'
  grep -q 'PASS' "$CC_DELIVERY_PROBE_LOG"
}

@test "phone inert (push-send exit 3) → PROBE UNWIRED (exit 3) — never a false green" {
  CC_PUSH_SEND_BIN="$(mkpush inert 3)" run "$P"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'NOT WIRED'
  echo "$output" | grep -q 'PROBE UNWIRED'
}

@test "phone rejected (push-send exit 5) → PROBE FAILED (exit 5)" {
  CC_PUSH_SEND_BIN="$(mkpush bad 5)" run "$P"
  [ "$status" -eq 5 ]
  echo "$output" | grep -q 'PROBE FAILED'
}

@test "--receipt + device confirms → DELIVERED to a device (exit 0)" {
  CC_PUSH_SEND_BIN="$(mkpush rok 0 'receipt=RCPT9' 0)" run "$P" --receipt --poll-tries 2
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'DELIVERED to a device'
}

@test "--receipt + device silent → accepted but UNCONFIRMED (exit 0, warned)" {
  CC_PUSH_SEND_BIN="$(mkpush rno 0 'receipt=RCPT9' 6)" run "$P" --receipt --poll-tries 2
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'UNCONFIRMED'
}

@test "--desk + announce verified → both legs PASS (exit 0)" {
  CC_PUSH_SEND_BIN="$(mkpush ok 0)" CC_ANNOUNCE_BIN="$(mkann ok 0)" run "$P" --desk
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'DESK leg — cc-announce VERIFIED'
}

@test "--desk + announce alarmed → PROBE FAILED (exit 5) even with phone OK" {
  CC_PUSH_SEND_BIN="$(mkpush ok 0)" CC_ANNOUNCE_BIN="$(mkann bad 5)" run "$P" --desk
  [ "$status" -eq 5 ]
  echo "$output" | grep -q 'DESK leg — cc-announce did NOT verify'
}
