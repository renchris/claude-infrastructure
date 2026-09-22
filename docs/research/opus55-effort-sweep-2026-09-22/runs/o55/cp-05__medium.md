# Review of `tests/autonomy-sweep.bats`

I found four defects. All four are tests that can pass without proving what they claim.

---

### 1. The "all six event dirs" reap test only covers five directories

**What:** The test says it covers all six age-reaped event dirs, but it seeds and asserts only five. The announce-alarm dir (`CC_ANNOUNCE_ALARM_DIR`) is never exercised.

**Where:** Lines 173–187, starting at:
```
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
```
The body only uses these five:
```
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

**Why it is wrong:** Suppose the sweep never reaps the sixth dir, or reaps it with a collapsed horizon that eats live alarms. The test stays green. That is exactly the failure the section's L2 comment ("OLD reaped AND YOUNG kept") says each case must catch.

---

### 2. The "old shape is gone" pin only matches one exact literal line

**What:** The test claims to prove the notify call is "neither rc-discarded nor stderr-discarded". It only checks that one verbatim string is absent, and that two identifiers appear somewhere in the file.

**Where:** Lines 391–393:
```
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
  [ "$output" = "0" ]
```
It then relies on:
```
  run bash -c "grep -q 'notify_verdict:=unreadable' '$SWEEP'"
```
and:
```
  run bash -c "grep -q 'CC_SWEEP_OS_CHANNEL' '$SWEEP'"
```

**Why it is wrong:** A reintroduced discard in any other spelling passes this test. Examples:
- `"$NOTIFY" --role desk "$summary" 2>/dev/null || :`
- different variable names, since the new call addresses `--role desk` rather than `$DESK_TARGET`

The two `grep -q` checks only prove the strings exist, and a comment would satisfy them. So the guard does not cover the class of regressions it names.

---

### 3. The 7-day horizon test is a substring grep

**What:** The test does not establish the horizon. It greps for a substring that also matches other values and also matches non-code text.

**Where:** Line 222:
```
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
```

**Why it is wrong:** Any of these would still pass:
- `${CC_EVENT_TTL_DAYS:-70}`
- `${CC_EVENT_TTL_DAYS:-7}` appearing only in a comment
- a real expression that is overridden elsewhere in the script

In each case the test still claims "the event horizon is 7 days".

---

### 4. The `decisions/` exemption test passes even if the reaper never runs

**What:** The test only asserts that an old decision packet survives. It never shows that a reap actually happened in the same run.

**Where:** Line 197:
```
  [ -f "$CC_DECISIONS_DIR/old.json" ]
```

**Why it is wrong:** If the reap step never executes (it errors out earlier, is skipped, or is gated off), the old packet trivially survives and the test goes green. It then asserts the exemption without the failure-distinct pair (an old event record reaped in the same run) that the section's own L2 rule requires.
