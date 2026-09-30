#!/usr/bin/env bats
# cc-desk-page — page the desk, and when no live desk takes it, the operator.
#
# The property under test is the path from a desk give-up to the fallback: cc-notify refusing
# (rc 3, the dead-role case), being cut at the bound (rc 124), or enqueueing to a box nobody reads
# (rc 0, verdict=mailbox-only) must each reach the operator rung, and only a real desk delivery may
# skip it. Each case also pins the idl line, because that line is how "did anyone get this page" is
# answered after the fact. cc-notify and lr-page are both stubs; HOME is fixtured.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$BATS_TEST_DIRNAME/../bin/cc-desk-page"
  export CC_DESK_PAGE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_DESK_PAGE_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  export CC_DESK_PAGE_LRPAGE_BIN="$BATS_TEST_TMPDIR/lr-page.sh"
  LR_LOG="$BATS_TEST_TMPDIR/lr.log"
  printf '#!/bin/bash\n[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"\necho "cc-notify: verdict=${STUB_VERDICT:-delivered} enqueued=1" >&2\nexit "${STUB_RC:-0}"\n' > "$CC_DESK_PAGE_NOTIFY_BIN"
  chmod +x "$CC_DESK_PAGE_NOTIFY_BIN"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\necho "lr-page: verdict=${STUB_LR_VERDICT:-posted} os=${STUB_LR_OS:-posted} phone=${STUB_LR_PHONE:-skipped}"\n' "$LR_LOG" > "$CC_DESK_PAGE_LRPAGE_BIN"
}

last() { tail -1 "$CC_DESK_PAGE_IDL" | jq -r "$1"; }
lr_calls() { [ -f "$LR_LOG" ] && wc -l < "$LR_LOG" | tr -d ' ' || echo 0; }

@test "a live desk takes it: delivered on the desk, read proven, the operator rung never runs" {
  run "$SUBJECT" --source t -- "hello"
  [ "$status" -eq 0 ]
  [ "$(last .delivered)" = true ]
  [ "$(last .channel)" = desk ]
  [ "$(last .read_proven)" = true ]
  [ "$(last .notified)" = role:desk ]
  [ "$(lr_calls)" = 0 ]
}

@test "dead desk (rc 3 unresolvable): the operator rung takes it via the Notification Center" {
  STUB_RC=3 STUB_VERDICT=unresolvable run "$SUBJECT" --source t -- "hello"
  [ "$status" -eq 0 ]
  [ "$(lr_calls)" = 1 ]
  grep -q -- '--title t -- hello' "$LR_LOG"
  [ "$(last .delivered)" = true ]
  [ "$(last .channel)" = notification-center ]
  [ "$(last .read_proven)" = false ]
  [ "$(last .notify_rc)" = 3 ]
}

@test "cc-notify cut at the bound (rc 124): the operator rung still runs" {
  STUB_SLEEP=5 CC_DESK_PAGE_TIMEOUT_S=1 run "$SUBJECT" -- "hello"
  [ "$status" -eq 0 ]
  [ "$(last .notify_rc)" = 124 ]
  [ "$(lr_calls)" = 1 ]
  [ "$(last .delivered)" = true ]
}

@test "rc 0 but only enqueued to a mailbox: not a desk delivery, the operator rung runs" {
  STUB_VERDICT=mailbox-only run "$SUBJECT" -- "hello"
  [ "$(lr_calls)" = 1 ]
  [ "$(last .channel)" = notification-center ]
}

@test "phone and banner both take it: the channel names both" {
  STUB_RC=3 STUB_LR_PHONE=sent run "$SUBJECT" -- "hello"
  [ "$(last .channel)" = notification-center+pushover ]
}

@test "nothing takes it: delivered:false, exit 1, the line says what each rung answered" {
  STUB_RC=3 STUB_VERDICT=unresolvable STUB_LR_VERDICT=failed STUB_LR_OS=failed run "$SUBJECT" -- "hello"
  [ "$status" -eq 1 ]
  [ "$(last .delivered)" = false ]
  [ "$(last .channel)" = none ]
  [ "$(last .os)" = failed ]
}

@test "the desk rung runs with cc-notify's own phone fallback switched off" {
  printf '#!/bin/bash\necho "fb=${CC_NOTIFY_PHONE_FALLBACK:-unset}" >> "%s"\necho "cc-notify: verdict=delivered" >&2\n' \
    "$BATS_TEST_TMPDIR/env.log" > "$CC_DESK_PAGE_NOTIFY_BIN"
  run "$SUBJECT" -- "hello"
  grep -q 'fb=0' "$BATS_TEST_TMPDIR/env.log"
}

@test "usage: no message, two messages and an unknown option all exit 2" {
  run "$SUBJECT"; [ "$status" -eq 2 ]
  run "$SUBJECT" a b; [ "$status" -eq 2 ]
  run "$SUBJECT" --nope x; [ "$status" -eq 2 ]
}
