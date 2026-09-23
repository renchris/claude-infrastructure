# Review of `tests/autonomy-sweep.bats`

I found three defects. The first two are substantive; the third is lower-impact.

---

### 1. The "all six event dirs" reap test only covers five

**What:** The test says it checks all six age-reaped event dirs, but it never creates or checks a record in `CC_ANNOUNCE_ALARM_DIR`.

**Where:** Line ~176 (test header) and the five `mk_old`/`mk_young` pairs that follow:
```
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
```
```
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

**Why it is wrong:**
- Setup says "The sweep age-reaps six event dirs". The sixth is the announce-alarms dir (`cc-announce-alarms/`), which the header names as a drained escalation dir.
- If the sweep's reap of `CC_ANNOUNCE_ALARM_DIR` is missing, uses the wrong horizon (e.g. 0, eating live alarms), or targets the wrong path, this test stays green.
- So the "failure-distinct pair" guarantee the L2 comment promises is absent for one of the six dirs, while the test name claims full coverage.

---

### 2. The "old shape is gone" guard is vacuous

**What:** The regression pin only rejects one exact spelling of the old notify line, and that spelling can no longer occur, so the test cannot detect rc-discard or stderr-discard coming back.

**Where:** Lines ~393–394:
```
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
  [ "$output" = "0" ]
```
The follow-up checks only prove that strings exist somewhere in the file:
```
  run bash -c "grep -q 'notify_verdict:=unreadable' '$SWEEP'"
  run bash -c "grep -q 'CC_SWEEP_OS_CHANNEL' '$SWEEP'"
```

**Why it is wrong:**
- The sweep now addresses the desk with `--role desk`, which the earlier test asserts with `grep -q -- '--role desk'`. A line containing `"$DESK_TARGET"` is therefore already absent, so the count is always 0.
- A reintroduced `"$NOTIFY" --role desk "$summary" >/dev/null 2>&1 || true` would pass this test. So would any variant with different spacing or `2>/dev/null` alone.
- The two presence greps pass if the strings appear in a comment or dead code.
- The test's title claims "the notify call is neither rc-discarded nor stderr-discarded". Nothing in it checks the actual notify call for either property. The comment also claims "the exact three lines ... pinned", but only one pattern is rejected.

---

### 3. The horizon test's check and title don't match (lower impact)

**What:** The horizon test asserts only that the literal `CC_EVENT_TTL_DAYS:-7` appears somewhere in the script, and its title's magnitude claim is false.

**Where:** Lines ~229–231:
```
@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
```

**Why it is wrong:**
- **The check can pass for the wrong reason:** `grep -c` exits 0 on any match, including one in a comment or in an unused variable. The reaps could use a different horizon and this assertion would still pass.
- **The claim is false:** 7 days is 604,800 s. Against the 6,000 s floor, that is about 100×, which is two orders of magnitude, not three. The title misstates the margin the test is meant to guarantee.

---

I found no other defects. The remaining assertions:
- use the `! … || false` idiom correctly under bats' `set -e`;
- pair keep and reap checks for inbox-guard;
- pair the negative seen-marker checks with the positive controls.
