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

@test "selftest passes 7/7 (a zero-check suite must not 'pass')" {
  run "$P" --selftest
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | grep -c '^  ok ')"; [ "$n" -eq 7 ]
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
