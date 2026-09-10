I reviewed the full text of the brief and found four defects.

**1. The "all six event dirs" reap test seeds and asserts only five directories.**

Where: lines 163 to 177

```bash
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

Why it is wrong: the setup comment says the sweep age-reaps six event dirs, and the file header names cc-announce-alarms as a drained dir. That directory, exported as CC_ANNOUNCE_ALARM_DIR at line 12, is neither seeded nor asserted here. A reaper that stops reaping that dir, or a horizon that collapses to zero and deletes live alarms from it, leaves this test green. The failure-distinct pair the header comment describes is missing for one of the six dirs the test title claims to cover.

**2. The horizon pin matches any TTL value that merely starts with 7.**

Where: line 215

```bash
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
```

Why it is wrong: the pattern is an unanchored substring. A default of 70, 700, or 7.5 days matches it too, and so does the string appearing only inside a comment. The test title asserts the horizon is exactly 7 days, but a change to any of those values passes. Line 216 only requires at least one match.

**3. Two tests never check the sweep's exit status, so a crash after the side effect passes as success.**

Where: lines 129 to 130 and lines 267 to 269

```bash
  run bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
```

```bash
  run bash "$SWEEP"
  run bash "$CC_BACKLOG_BIN" list --open
  echo "$output" | grep -q "carry this out"
```

Why it is wrong: if the sweep notifies the desk, or appends the backlog item, and then dies before writing its IDL record or transitioning the packet, these tests still pass. The only test that asserts exit 0 on its own runs the nothing-new path at line 151, which never reaches the decision or notify code. Every other test in the file asserts status, so these two are the gaps.

**4. The notify counter counts log lines, not invocations.**

Where: line 64, together with line 41 in the stub

```bash
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
```

```bash
echo "$@" >> "$0.log"
```

Why it is wrong: the stub writes every argument verbatim, and the sweep passes the summary as an argument per the pin at line 392. Any newline inside the summary, such as a multi-item listing, produces more than one line per call. Every check of the form `notify_count -eq 1` then fails for a single correct notify, and a dedup regression that calls twice with short summaries is indistinguishable from one call with a two-line summary. The helper measures the wrong quantity for what the tests use it to prove.
