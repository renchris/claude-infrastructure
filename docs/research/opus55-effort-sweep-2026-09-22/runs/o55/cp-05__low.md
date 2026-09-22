I found two defects.

### 1. The "all six event dirs" reap test covers only five directories

**What:** The test claims to check the age-reap of all six write-only event dirs, but it never seeds or checks `CC_ANNOUNCE_ALARM_DIR`. So if the reaper skips the announce-alarm dir, or eats young records in it, this test still passes.

**Where:** lines of the test body (`@test "all six event dirs: records past the horizon are reaped, young ones kept"`), which list only these five:
```
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

**Why it is wrong:** Setup and the header name `cc-announce-alarms/` (`CC_ANNOUNCE_ALARM_DIR`) as one of the drained event dirs. The test's own L2 comment says each dir needs the "OLD reaped AND YOUNG kept" pair. That pair is missing for the sixth dir. A sweep whose reaper:
- never touches `$CC_ANNOUNCE_ALARM_DIR`, or
- runs there with a zero horizon and deletes live alarms,

still turns this test green, even though the test name asserts coverage of all six.

### 2. The "old shape is gone" guard pins one exact spelling, not the class of discard it claims to forbid

**What:** The test claims the notify call is "neither rc-discarded nor stderr-discarded". It actually only asserts that one verbatim string is absent, plus that a few unrelated tokens are present.

**Where:** in `@test "the old shape is gone: ..."`:
```
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
  [ "$output" = "0" ]
```

**Why it is wrong:** Any reintroduction of the discard in a different spelling passes this test. Examples:
- `"$NOTIFY" --role desk "$summary" 2>/dev/null || true`
- `"$NOTIFY" "$DESK_TARGET" "$summary" &>/dev/null || :`

The remaining asserts check only that `notify_verdict:=unreadable` and `CC_SWEEP_OS_CHANNEL` appear somewhere in the file, which doesn't show they are wired to the notify call. So the data-loss shape the test says it "pins so they cannot come back" can return and the test stays green. Behavioural coverage elsewhere in the suite is the only real protection.
