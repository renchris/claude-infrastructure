#!/usr/bin/env bats
# 471d2f3f98df — the LOUD alarm must not drop the message it failed to deliver.
#
# The incident (measured 2026-08-10, announce-alarm-20260810T083423Z-77996-29584.json): a full terminal
# report announced to an unset role produced an alarm record holding the VERDICT and the DETAIL and none
# of the report. The operator learned THAT an announce failed and never what it said — a silent loss
# converted into a loud loss, not into a recoverable one. cc-announce's own spec calls itself F1 of the
# never-let-completion-go-silent bar, so a record you cannot replay from is the bar unmet.
#
# The cause is not the empty `event` field the incident record also showed: `announce()` holds the message
# in `$msg` and simply never passes it to write_alarm/write_degrade. That reading predicts two things the
# incident never claimed, and both are pinned below: the DEGRADE record drops the body on the same
# omission, and a record you can actually re-issue from needs the --from attribution too.
#
# Each assertion is a DISCRIMINATOR: every one of these reds against the pre-fix bin/cc-announce (verified
# by running this file at its parent commit), so none of them can pass because some other field happens to
# carry the text.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  A="$REPO/bin/cc-announce"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_ANNOUNCE_RETRY_SLEEP=0
  mkdir -p "$CC_ROLES_DIR"
  # a body distinctive enough that finding it anywhere in the record is proof, and long enough that a
  # truncating implementation cannot pass by accident.
  MSG="WAVE COMPLETE: 6 rows closed, 2 commits landed, gates green - operator must decide on the migration"
}

# a stub cc-notify scripting one cc-notify outcome; never touches a real inbox or a real session.
stub() { # <mode>
  local p="$BATS_TEST_TMPDIR/stub-$1.sh" body
  case "$1" in
    unresolved) body='echo "cc-notify: cannot resolve target — not a live session name or a pane UUID" >&2; exit 3' ;;
    writefail)  body='echo "cc-notify: FAILED to write inbox — message NOT delivered" >&2; exit 5' ;;
    nowatch)    body='echo "cc-notify: delivered to inbox [T] (live session, NO watcher armed — drains on its NEXT turn; delivered but not a guaranteed instant wake)" >&2; exit 0' ;;
    verified)   body='echo "cc-notify: delivered to inbox [T] (live session, wake-path armed — its cc-await-ping watcher wakes it within a poll)" >&2; exit 0' ;;
  esac
  { echo '#!/bin/bash'; echo "$body"; } > "$p"
  chmod +x "$p"; echo "$p"
}
alarm_json()   { cat "$CC_ANNOUNCE_ALARM_DIR"/announce-alarm-*.json 2>/dev/null; }
degrade_json() { cat "$CC_ANNOUNCE_ALARM_DIR"/announce-degrade-*.json 2>/dev/null; }

@test "UNRESOLVED: the alarm record carries the message body, in its own field (the incident's exact shape)" {
  CC_NOTIFY_BIN="$(stub unresolved)" run "$A" ghost-desk "$MSG"
  [ "$status" -eq 5 ]
  # the field, not merely the text: `detail` already quotes cc-notify's stderr, so a substring match
  # against the whole record could pass on a message that happened to echo back in the error string.
  got="$(alarm_json | jq -r '.body // "MISSING"')"
  [ "$got" = "$MSG" ]
}

@test "WRITEFAIL: the body is retained where NOTHING else on disk holds it" {
  # the sharp half of the incident. On verdict=MAILBOX the message did reach an inbox and is recoverable
  # there; on WRITEFAIL (and UNRESOLVED) the inbox write never happened, so the record is the only copy
  # that could ever exist. If the body is dropped here it is destroyed, not merely un-indexed.
  CC_NOTIFY_BIN="$(stub writefail)" run "$A" some-desk "$MSG"
  [ "$status" -eq 5 ]
  [ "$(alarm_json | jq -r '.body // "MISSING"')" = "$MSG" ]
}

@test "a record you cannot re-issue from is not replayable: --from is retained beside the body" {
  CC_NOTIFY_BIN="$(stub unresolved)" run "$A" --from wave-lead ghost-desk "$MSG"
  [ "$status" -eq 5 ]
  [ "$(alarm_json | jq -r '.body // "MISSING"')" = "$MSG" ]
  [ "$(alarm_json | jq -r '.from // "MISSING"')" = "wave-lead" ]
}

@test "the DEGRADE record drops it on the same omission — the half the incident never claimed" {
  CC_NOTIFY_BIN="$(stub nowatch)" run "$A" idle-desk "$MSG"
  [ "$status" -eq 0 ]
  [ "$(degrade_json | jq -r '.body // "MISSING"')" = "$MSG" ]
}

@test "NEGATIVE HALF: a VERIFIED announce writes no record at all, so retaining the body did not start recording every message" {
  # the pair to the four above. Persisting a body is only safe if it did not turn the success path into a
  # transcript of everything the fleet ever announced.
  CC_NOTIFY_BIN="$(stub verified)" run "$A" live-desk "$MSG"
  [ "$status" -eq 0 ]
  [ -z "$(alarm_json)" ]
  [ -z "$(degrade_json)" ]
}
