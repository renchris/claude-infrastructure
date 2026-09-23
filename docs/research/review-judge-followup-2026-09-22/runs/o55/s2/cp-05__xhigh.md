Five defects found: two clear coverage gaps, one weak regression pin, and two weaker assertion gaps. Line numbers are counted from line 1 = `#!/usr/bin/env bats`.

---

### 1. The "all six event dirs" reap test covers only five dirs

- **What:** The test named "all six event dirs" only creates and checks fixtures in five dirs, and nothing else in the file age-reap tests `CC_ANNOUNCE_ALARM_DIR`, one of the dirs the sweep drains.
- **Where:** lines 163–168 (and the matching assertions at 173–177):
  ```
  @test "all six event dirs: records past the horizon are reaped, young ones kept" {
    mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
    mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
    mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
    mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
    mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
  ```
- **Why it is wrong:** Suppose the sweep's reap of the announce-alarm dir breaks in either direction:
  - it never reaps, so old alarms pile up forever; or
  - its horizon collapses, so live alarms are deleted.
  
  In both cases this test still passes. It claims the old-reaped/young-kept pair for every dir, but proves it for five.

### 2. The "old shape is gone" pin only matches one exact spelling of a line the current code no longer uses

- **What:** The guard that is supposed to stop rc/stderr discarding from returning only greps one exact literal line built on `"$DESK_TARGET"`. That shape is already gone, so the guard can essentially never fire.
- **Where:** line 392:
  ```
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
  ```
  The comment at line 391 says `# The exact three lines that made this a data-loss bug, pinned so they cannot come back.`
- **Why it is wrong:**
  - The sweep now addresses the desk with `--role desk` (asserted at line 82), not `"$DESK_TARGET"`.
  - Suppose `>/dev/null 2>&1 || true` (or `2>/dev/null || :`, or a whitespace variant) comes back on the current call shape. Then `grep -c` prints `0` and the test passes.
  - Only one of the "three lines" is pinned. The unconditional `mark_seen` has no pin at all.
  - The remaining checks (lines 394–399) only prove that some strings exist and that the file parses. None of them shows the rc or stderr is actually used.

### 3. The negative assertion in the summary test is not tied to any real label

- **What:** The test asserts that `fired→backlog` is absent from the notify log. No test anywhere checks that a queued (change) fire actually emits that label, so the check can pass without testing anything.
- **Where:** line 409:
  ```
  ! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false
  ```
- **Why it is wrong:**
  - Suppose the sweep labels queued fires any other way, e.g. `fired → backlog`, `queued`, or `1 fired`. Then this line passes even when the summary also reports the no-change fire as queued.
  - That is exactly the "reads as '1 item queued' on a sweep that queued none" failure the comment at line 407 says the test guards against.
  - The file's own positive-control pattern (lines 250–261, 375–388) is missing here.

### 4. The 7-day horizon is only checked by a text grep; behaviorally it can be anything from seconds to 9 days

- **What:** The test that claims "the event horizon is 7 days" only checks that a substring appears somewhere in the script. The L2 old/young pair (lines 156–158) uses fixtures aged 9 days and about 0 seconds, so it cannot detect a horizon anywhere in between.
- **Where:** line 215:
  ```
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  ```
  and line 160:
  ```
  mk_old()   { mkdir -p "$(dirname "$1")"; printf 'x\n' > "$1"; touch -t "$(date -v-9d +%Y%m%d%H%M)" "$1"; }
  ```
- **Why it is wrong:**
  - `grep -c` exits 0 whenever the text appears anywhere, including a comment, an unused default, or `:-70`.
  - Suppose the actual reap used a hard-coded `-mtime +1` or a different variable, while the `CC_EVENT_TTL_DAYS:-7` text stayed in the file. Line 215 passes, and the young (age ≈0 s) and old (9 d) fixtures still pass.
  - Meanwhile, live records 1–7 days old would be deleted.
  - The comment's claim that the keep half catches a horizon that "collapsed … and ate live records" only holds for a horizon of a few seconds.
  - The test title's "three orders of magnitude" is also false: 604,800 s ÷ 6,000 s ≈ 100, which is two orders.

### 5. The "second run abstains" claim is never asserted

- **What:** The test title says the second run abstains, but no line after the second run checks the IDL disposition.
- **Where:** lines 85–87:
  ```
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  ```
  The only disposition grep is at line 83, before the second run: `grep -q '"disposition":"fired"' "$CC_IDL"`.
- **Why it is wrong:** Suppose the second run writes `"disposition":"fired"` again, or writes no IDL record at all, while not calling notify. The test still passes, even though its title says the run abstains.
