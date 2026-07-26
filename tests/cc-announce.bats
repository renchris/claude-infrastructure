#!/usr/bin/env bats
# comms-safety — F1 cc-announce: the VERIFIED-or-LOUD announce primitive. The tool's --selftest RED-proves
# the never-silent contract with a stub cc-notify; these bats add CLI-level regression on the exit-code
# contract (0=verified, 5=alarm) and the alarm/degrade records. The incident: a terminal announce that
# SILENTLY degraded to disk-truth (SendMessage → unresolvable). cc-announce must never do that.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  A="$REPO/bin/cc-announce"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_ANNOUNCE_RETRY_SLEEP=0
  mkdir -p "$CC_ROLES_DIR"
}

# a stub cc-notify that emits <mode>'s outcome and logs its args to $BATS_TEST_TMPDIR/stub.log
stub() { # <mode>
  local p="$BATS_TEST_TMPDIR/stub-$1.sh" body
  case "$1" in
    verified)     body='echo "cc-notify: delivered to inbox [T] (live session, wake-path armed — its cc-await-ping watcher wakes it within a poll)" >&2; exit 0' ;;
    nowatch)      body='echo "cc-notify: delivered to inbox [T] (live session, NO watcher armed — drains on its NEXT turn; delivered but not a guaranteed instant wake)" >&2; exit 0' ;;
    mailbox)      body='echo "cc-notify: [T] mailbox only — target is NOT a live session (closed/recycled pane); no drain will run" >&2; exit 0' ;;
    unresolved)   body='echo "cc-notify: cannot resolve target — not a live session name or a pane UUID" >&2; exit 3' ;;
    writefail)    body='echo "cc-notify: FAILED to write inbox — message NOT delivered" >&2; exit 5' ;;
    unverifiable) body='echo "cc-notify: delivered to inbox [T] (liveness UNVERIFIABLE — no session registry/pane list; recorded)" >&2; exit 0' ;;
  esac
  { echo '#!/bin/bash'; echo "printf '%s\\n' \"\$*\" >> \"$BATS_TEST_TMPDIR/stub.log\""; echo "$body"; } > "$p"
  chmod +x "$p"; echo "$p"
}
n_alarm() { find "$CC_ANNOUNCE_ALARM_DIR" -name 'announce-alarm-*.json' 2>/dev/null | wc -l | tr -d ' '; }
n_degrade() { find "$CC_ANNOUNCE_ALARM_DIR" -name 'announce-degrade-*.json' 2>/dev/null | wc -l | tr -d ' '; }

@test "selftest passes and runs all 12 never-silent checks (a zero-check suite must not 'pass')" {
  run "$A" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 12 ]
}

@test "wake-path armed → VERIFIED, exit 0, no alarm" {
  CC_NOTIFY_BIN="$(stub verified)" run "$A" some-target "done"
  [ "$status" -eq 0 ]
  [ "$(n_alarm)" -eq 0 ]
  [ "$(n_degrade)" -eq 0 ]
}

@test "live-but-no-watcher → recorded DEGRADE, exit 0, NO alarm (F5: live ≠ a confirmed wake)" {
  CC_NOTIFY_BIN="$(stub nowatch)" run "$A" idle-desk "shipped"
  [ "$status" -eq 0 ]
  [ "$(n_alarm)" -eq 0 ]
  [ "$(n_degrade)" -ge 1 ]
}

@test "unresolvable target → LOUD alarm + non-zero (the SendMessage bug: desk is not resolvable)" {
  CC_NOTIFY_BIN="$(stub unresolved)" run "$A" ghost-desk "done"
  [ "$status" -ne 0 ]
  [ "$(n_alarm)" -ge 1 ]
}

@test "mailbox-only (disk-truth) → LOUD alarm + non-zero (RELOAD is not a WAKE)" {
  CC_NOTIFY_BIN="$(stub mailbox)" run "$A" recycled-desk "shipped"
  [ "$status" -eq 5 ]
  [ "$(n_alarm)" -ge 1 ]
}

@test "inbox-unwritable (exit 5) → LOUD alarm + non-zero (a message that cannot persist is not delivered)" {
  CC_NOTIFY_BIN="$(stub writefail)" run "$A" busy-desk "done"
  [ "$status" -ne 0 ]
  [ "$(n_alarm)" -ge 1 ]
}

@test "unverifiable-but-alive (liveness unconfirmed) → exit 0 but a degrade record (recorded, never silent)" {
  CC_NOTIFY_BIN="$(stub unverifiable)" run "$A" busy-alive "done"
  [ "$status" -eq 0 ]
  [ "$(n_degrade)" -ge 1 ]
}

@test "role map: a role token resolves to its mapped target via CC_ROLES_DIR" {
  printf 'MAPPED-UUID-9\n' > "$CC_ROLES_DIR/desk"
  CC_NOTIFY_BIN="$(stub verified)" run "$A" desk "done"
  [ "$status" -eq 0 ]
  grep -q 'MAPPED-UUID-9' "$BATS_TEST_TMPDIR/stub.log"
}

@test "the alarm record carries the verdict (auditable, not a bare failure)" {
  CC_NOTIFY_BIN="$(stub mailbox)" run "$A" recycled-desk "shipped"
  rec="$(find "$CC_ANNOUNCE_ALARM_DIR" -name 'announce-alarm-*.json' | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.verdict' "$rec")" = "MAILBOX" ]
  [ "$(jq -r '.kind' "$rec")" = "alarm" ]
}

@test "missing message → usage error (exit 2)" {
  CC_NOTIFY_BIN="$(stub verified)" run "$A" only-a-target
  [ "$status" -eq 2 ]
}

# ── the CALLER CONTRACT (incident 2026-07-26, backlog 0298535c1584) ──────────────────────────────────
# The resolver-availability rewrite made cc-notify's OWN rc honest. It cannot make the rc a CALLER sees
# honest: `timeout` reports 124 whatever the child exits with. Reproduced against the post-rewrite
# binary — rc 124, EMPTY stderr, and the message already in the target's inbox. `enqueued=` is the only
# thing that can separate those two worlds, and this is where it gets read.

# a stub cc-notify that emits <stderr-line> and exits <rc>, logging one line per invocation
rcstub() { # <name> <rc> <stderr-line>
  local p="$BATS_TEST_TMPDIR/stub-$1.sh"
  { echo '#!/bin/bash'
    echo "printf '%s\\n' \"\$*\" >> \"$BATS_TEST_TMPDIR/stub.log\""
    echo "echo '$3' >&2"
    echo "exit $2"; } > "$p"
  chmod +x "$p"; echo "$p"
}
n_calls() { grep -c '' "$BATS_TEST_TMPDIR/stub.log" 2>/dev/null || echo 0; }

@test "rc 124 with enqueued=1 → recorded DEGRADE (exit 0, no alarm): the delivery stands, the verdict does not" {
  local p; p="$(rcstub killedenq 124 'cc-notify: verdict=interrupted enqueued=1 uuid=T reason=signal')"
  CC_NOTIFY_BIN="$p" run "$A" loaded-peer "incident advisory"
  [ "$status" -eq 0 ]
  [ "$(n_alarm)" -eq 0 ]
  [ "$(n_degrade)" -ge 1 ]
  [ "$(n_calls)" -eq 1 ]              # no retry: the send was killed, not merely slow
}

@test "rc 124 WITHOUT enqueued=1 → LOUD alarm + non-zero: undelivered stays undelivered" {
  local p; p="$(rcstub killednoenq 124 'cc-notify: verdict=interrupted enqueued=0 uuid=T reason=signal')"
  CC_NOTIFY_BIN="$p" run "$A" loaded-peer "incident advisory"
  [ "$status" -ne 0 ]
  [ "$(n_alarm)" -ge 1 ]
  [ "$(n_calls)" -eq 1 ]
}

@test "rc 4 RESOLVER UNAVAILABLE is not read as a bad address — it alarms, and it KEEPS its retry" {
  # cc-notify's own guidance for rc 4 is "retry, do NOT treat as a bad address": an unreadable registry
  # is transient in a way a wrong name is not. The no-retry rule must not swallow this case.
  local p; p="$(rcstub resolverdown 4 'cc-notify: verdict=degraded enqueued=0 uuid= reason=resolver-unavailable')"
  CC_NOTIFY_BIN="$p" run "$A" loaded-peer "incident advisory"
  [ "$status" -ne 0 ]
  [ "$(n_alarm)" -ge 1 ]
  [ "$(n_calls)" -eq 2 ]
}

@test "rc 6 AMBIGUOUS prefix → alarm with NO retry (an ambiguous address does not resolve itself)" {
  local p; p="$(rcstub ambiguous 6 'cc-notify: verdict=ambiguous enqueued=0 uuid= reason=ambiguous-prefix')"
  CC_NOTIFY_BIN="$p" run "$A" loaded-peer "incident advisory"
  [ "$status" -ne 0 ]
  [ "$(n_alarm)" -ge 1 ]
  [ "$(n_calls)" -eq 1 ]
}

@test "CONTROL: the retry loop still exists where a retry can help (no-watcher degrade costs 2 calls)" {
  # Without this control, the four tests above would also pass on a build that simply deleted retries.
  local p; p="$(stub nowatch)"
  CC_NOTIFY_BIN="$p" run "$A" idle-desk "routine ping"
  [ "$status" -eq 0 ]
  [ "$(n_calls)" -eq 2 ]
}

# ── the machine-readable verdict token: callers must key on status, never on prose ────────────────
@test "verdict token: wake-path armed → verdict=VERIFIED on stderr" {
  CC_NOTIFY_BIN="$(stub verified)" run "$A" desk "done"
  [ "$status" -eq 0 ]
  run grep -q '^cc-announce: verdict=VERIFIED$' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "verdict token: live-but-no-watcher → verdict=DEGRADED (the exit code alone cannot say this)" {
  CC_NOTIFY_BIN="$(stub nowatch)" run "$A" desk "done"
  [ "$status" -eq 0 ]                                   # SAME exit code as VERIFIED — that is the point
  run grep -q '^cc-announce: verdict=DEGRADED$' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "verdict token: an alarmed announce reports verdict=ALARM(<verdict>)" {
  CC_NOTIFY_BIN="$(stub mailbox)" run "$A" desk "done"
  [ "$status" -eq 5 ]
  run grep -q '^cc-announce: verdict=ALARM(MAILBOX)$' <<<"$output"
  [ "$status" -eq 0 ]
}
