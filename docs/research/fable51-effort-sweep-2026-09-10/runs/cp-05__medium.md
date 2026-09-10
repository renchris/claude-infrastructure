Reviewing the bats file as text only. Three defects found.

**1. The "all six event dirs" reap test only exercises five directories.**

Where: lines 164–168 and 173–177, e.g.
```
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
  [ ! -f "$CC_TEARDOWN_RECORDS_DIR/old.json" ];   [ -f "$CC_TEARDOWN_RECORDS_DIR/new.json" ]
```
Why it is wrong: the setup comment and the test title both say the sweep age-reaps six dirs, but the seeded set is pages, comms-alarms, push-records, completion, and teardown. The announce-alarm dir (`CC_ANNOUNCE_ALARM_DIR`, one of the four drained sources named in the header) is never seeded or asserted. If the reaper stops reaping that dir, or its horizon collapses to zero and deletes live alarms, this test stays green. The failure-distinct pair the L2 comment promises is not enforced for that class.

**2. The open-packet dedup assertion passes if the second sweep crashes.**

Where: lines 131–132
```
  run bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]      # deduped on the second run
```
Why it is wrong: neither `run` in this test checks `$status`. The only proof of dedup is that the notify count did not grow. A second run that exits nonzero before reaching the notify step, for example by failing to parse the packet it wrote a `.seen` marker for, also leaves the count at one. The test then reports dedup as working when nothing was deduped.

**3. The 7-day horizon pin accepts any value that starts with 7.**

Where: lines 215–216
```
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
```
Why it is wrong: the pattern is an unanchored substring and only the exit status is checked, not the count. A sweep whose default became `CC_EVENT_TTL_DAYS:-70` or `:-700` still matches, so the test asserts the horizon is 7 days while it could be ten or a hundred times longer. The test's own comment names the reason this pin exists, which is that the horizon must sit in a specific range relative to the lint floor, and that range is not what the check enforces.
