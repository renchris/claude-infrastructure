Three defects found. The rest of the file holds up: the negated assertions use the `|| false` guard correctly, the seen-dir and IDL checks are paired with positive controls, and the inbox-guard cases cover the failure-distinct combinations.

**1. The "all six event dirs" reap test exercises only five.**

What: The test that claims to cover every age-reaped event dir never seeds or asserts the announce-alarm dir, so reaping of that dir is unverified.

Where: lines 163 to 168, and the matching assertions at lines 173 to 177.

```
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

Why it is wrong: The setup comment at lines 21 and 22 says the sweep reaps six event dirs, and the only exported event dir absent from this test is the one set on line 12, `CC_ANNOUNCE_ALARM_DIR`. If the reaper skips that dir, old alarm records accumulate forever and this test stays green. If that dir's horizon collapses, young alarm records are deleted before the sweep can surface them, and the test still stays green. The old-reaped plus young-kept pair that the comment at lines 156 to 158 says each dir needs does not exist for this dir.

**2. Two tests discard the sweep's exit status.**

What: A sweep that produces the observed side effect and then exits nonzero is reported as a pass.

Where: line 129, followed directly by line 130.

```
  run bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
```

And lines 268 to 269, where the second `run` overwrites `$status` before anything reads it.

```
  run bash "$SWEEP"
  run bash "$CC_BACKLOG_BIN" list --open
```

Why it is wrong: The future-deadline open packet at line 127 is the only input of that shape in the suite. If the sweep calls cc-notify and then fails in expire-sweep or the IDL write, the notify count is still 1 and the test passes, although the launchd contract asserted at line 150 is broken for that input. The unannotated case at line 268 has the same gap, though the test at line 112 checks status on the same packet shape and partly covers it.

**3. The horizon check is a substring match, not a value check.**

What: The test titled "the event horizon is 7 days" only verifies that a literal prefix appears somewhere in the script.

Where: lines 215 to 216.

```
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
```

Why it is wrong: The pattern matches `:-70`, `:-7.5`, or a stale mention in a comment or a second unrelated reference. The reap test seeds files 9 days old and 0 days old, so it only catches horizons above 9 days or a collapse to zero. A default lowered to a few days, with the old literal surviving elsewhere in the script, passes this test, passes the reap test, and passes the lint floor, while live records inside the intended 7-day window are deleted.
