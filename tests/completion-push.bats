#!/usr/bin/env bats
# comms-safety — F5 completion-push: a program-terminal completion → an OPERATOR push via cc-announce (F1);
# never silent (a record captured before the push, stamped in both outcomes). Exercises the real F5→F1
# chain through a stub cc-notify.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/scripts/completion-push.sh"
  export CC_ANNOUNCE_BIN="$REPO/bin/cc-announce"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/al"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"; echo 'OP-UUID' > "$CC_ROLES_DIR/operator"
  export CC_ANNOUNCE_RETRY_SLEEP=0
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/records"
}
stub() { # <mode> — a stub cc-notify driving cc-announce's outcome
  local p="$BATS_TEST_TMPDIR/notify-$1.sh" body
  case "$1" in
    verified)   body='echo "cc-notify: delivered to inbox [T] (live session, wake-path armed)" >&2; exit 0' ;;
    unresolved) body='echo "cc-notify: cannot resolve target" >&2; exit 3' ;;
  esac
  { printf '#!/bin/bash\n'; printf '%s\n' "$body"; } > "$p"; chmod +x "$p"; echo "$p"
}
nrec() { find "$CC_COMPLETION_RECORDS_DIR" -name 'push-*.json' 2>/dev/null | wc -l | tr -d ' '; }

@test "selftest passes 3/3 (a zero-check suite must not 'pass')" {
  run "$C" --selftest
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | grep -c '^  ok ')"; [ "$n" -eq 3 ]
}

@test "deliverable → pushed VERIFIED (exit 0), record verdict=verified" {
  CC_NOTIFY_BIN="$(stub verified)" run "$C" fire --event "ship W6" --detail "11/11 merged"
  [ "$status" -eq 0 ]
  rec="$(find "$CC_COMPLETION_RECORDS_DIR" -name 'push-*.json' | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.verdict' "$rec")" = "verified" ]
}

@test "undeliverable → LOUD (exit 5), record + cc-announce alarm (never silent)" {
  CC_NOTIFY_BIN="$(stub unresolved)" run "$C" fire --event "ship W6"
  [ "$status" -eq 5 ]
  [ "$(nrec)" -ge 1 ]
  [ -n "$(find "$CC_ANNOUNCE_ALARM_DIR" -name 'announce-alarm-*.json' 2>/dev/null | head -1)" ]
}

@test "capture-before-notify: a record exists even for a FAILED push (never silent)" {
  CC_NOTIFY_BIN="$(stub unresolved)" run "$C" fire --event "ship"
  rec="$(find "$CC_COMPLETION_RECORDS_DIR" -name 'push-*.json' | head -1)"
  [ -n "$rec" ]
  [[ "$(jq -r '.verdict' "$rec")" == push-failed* ]]
}

@test "fire without --event → usage error (exit 2)" {
  run "$C" fire
  [ "$status" -eq 2 ]
}
