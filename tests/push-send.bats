#!/usr/bin/env bats
# push-send — the callable, VERIFIED away-phone (Pushover) sender (P0-7 / G-P15-1). Trusts ONLY status:1 +
# HTTP 200; every lesser outcome (status:0, HTTP≠200, no creds, empty body) fails LOUD, never a false pass.
# Uses a stub curl (no network, no phone). The tool's --selftest RED-proves the whole discriminator.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/scripts/push-send.sh"
  export CC_PUSH_RECORDS_DIR="$BATS_TEST_TMPDIR/rec"
}
# a stub curl printing "<body>\n<code>" — the exact shape push-send parses from its -w format.
mkcurl() { # <name> <body> <code>
  local p="$BATS_TEST_TMPDIR/curl-$1.sh"
  cat > "$p" <<EOF
#!/bin/bash
printf '%s\n%s' '$2' '$3'
EOF
  chmod +x "$p"; echo "$p"
}

@test "selftest passes 7/7 (a zero-check suite must not 'pass')" {
  run "$P" --selftest
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | grep -c '^  ok ')"; [ "$n" -eq 7 ]
}

@test "status:1 + HTTP 200 → VERIFIED (exit 0, stdout status=1)" {
  CC_PUSH_CURL_BIN="$(mkcurl ok '{"status":1,"request":"REQ"}' 200)" PUSHOVER_TOKEN=t PUSHOVER_USER=u \
    run "$P" send --title T --message M
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^status=1'
}

@test "status:0 + HTTP 400 → LOUD FAIL (exit 5), errors surfaced (creds never echoed)" {
  CC_PUSH_CURL_BIN="$(mkcurl bad '{"status":0,"errors":["user key is invalid"]}' 400)" \
    PUSHOVER_TOKEN=SECRET_TOK PUSHOVER_USER=SECRET_USR run "$P" send --title T --message M
  [ "$status" -eq 5 ]
  echo "$output" | grep -qi 'user key is invalid'
  ! echo "$output" | grep -q 'SECRET_TOK'
  ! echo "$output" | grep -q 'SECRET_USR'
}

@test "HTTP 200 but status:0 → FAIL (exit 5) — the verify never trusts HTTP alone" {
  CC_PUSH_CURL_BIN="$(mkcurl soft '{"status":0,"errors":["message cannot be blank"]}' 200)" \
    PUSHOVER_TOKEN=t PUSHOVER_USER=u run "$P" send --title T --message M
  [ "$status" -eq 5 ]
}

@test "no creds → INERT (exit 3), a LOUD 'not wired' — never a syscall, never exit 0" {
  ( unset PUSHOVER_TOKEN PUSHOVER_USER
    CC_PUSH_CURL_BIN=/bin/false run "$P" send --title T --message M
    [ "$status" -eq 3 ]
    echo "$output" | grep -qi 'INERT' )
}

@test "empty response (network death) → FAIL (exit 5), never a false pass" {
  CC_PUSH_CURL_BIN="$(mkcurl empty '' '')" PUSHOVER_TOKEN=t PUSHOVER_USER=u \
    run "$P" send --title T --message M
  [ "$status" -eq 5 ]
  echo "$output" | grep -qi 'NO RESPONSE'
}

@test "receipt: last_delivered_at>0 → delivered (exit 0); ==0 → not-yet (exit 6)" {
  CC_PUSH_CURL_BIN="$(mkcurl rok '{"status":1,"last_delivered_at":1784000000,"acknowledged":1}' 200)" \
    PUSHOVER_TOKEN=t PUSHOVER_USER=u run "$P" receipt RCPT
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^delivered=1'
  CC_PUSH_CURL_BIN="$(mkcurl rno '{"status":1,"last_delivered_at":0}' 200)" \
    PUSHOVER_TOKEN=t PUSHOVER_USER=u run "$P" receipt RCPT
  [ "$status" -eq 6 ]
}

@test "verdict record is written redacted (verified/failed), never the creds" {
  rm -rf "$CC_PUSH_RECORDS_DIR"
  CC_PUSH_CURL_BIN="$(mkcurl ok '{"status":1,"request":"REQ"}' 200)" \
    PUSHOVER_TOKEN=SECRET_TOK PUSHOVER_USER=SECRET_USR run "$P" send --title T --message M
  rec="$(find "$CC_PUSH_RECORDS_DIR" -name 'push-*.json' | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.verdict' "$rec")" = verified ]
  ! grep -q 'SECRET_TOK' "$rec"
}
