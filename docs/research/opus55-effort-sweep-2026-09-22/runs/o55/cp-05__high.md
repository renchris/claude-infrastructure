# Review of `tests/autonomy-sweep.bats`

I found one clear defect and two lesser ones.

---

### Defect 1: the "all six event dirs" reap test only covers five dirs

**What:** The test says it covers all six age-reaped event dirs, but it seeds and asserts only five. The announce-alarm dir (`CC_ANNOUNCE_ALARM_DIR`) is never exercised.

**Where:** Line 163, then lines 164–168 (seeding) and 173–177 (assertions).

```bash
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

**Why it is wrong:** The six write-only event dirs are pages, announce-alarms, comms-alarms, push-records, completion and teardown. Inbox-guard is a separate damping case with its own tests at lines ~190–212. The test never touches `$CC_ANNOUNCE_ALARM_DIR` (exported at line 12), so two failures in that dir stay invisible:

- The reaper skips it entirely, and old alarms pile up forever.
- Its horizon collapses to 0, and it deletes live alarms.

In either case the test is still green. This breaks the failure-distinct pair ("OLD reaped AND YOUNG kept") that the L2 comment at lines 156–158 promises, and the title claims coverage the test does not have.

---

### Defect 2: the second run in the new-alarm test is never checked for "abstains"

**What:** The test title and comment say the second run "abstains", but after that run the test only checks the exit status and the notify count.

**Where:** Line 75 (title), lines 84–87.

```bash
@test "a new alarm → one notify to the desk role; a second run (nothing new) abstains" {
  # second run: the alarm is now .seen → nothing new → abstain, still exactly ONE notify total
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
```

**Why it is wrong:** Suppose the second run finds the deduped record, skips the notify, and writes a `"disposition":"fired"` IDL record, or writes no IDL record at all. That violates the header contract ("writes one {fired|abstained} IDL record") and the stated abstain behaviour. The test still passes, because no line greps `$CC_IDL` for `"disposition":"abstained"` after the second run.

---

### Defect 3 (conditional): `notify_count` counts log lines, not calls

**What:** `notify_count` counts lines in the stub's log, but the stub writes the summary argument verbatim. One cc-notify call whose summary contains a newline is therefore counted as several notifies.

**Where:** Line 64 and stub line 41.

```bash
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
```
```bash
echo "$@" >> "$0.log"
```

**Why it is wrong:** The setup comment says the stub logs "every call", and every dedup and "exactly one notify" assertion relies on one line meaning one call. Examples are lines 79, 87, 108, 130/132 and 146, plus the `-eq 2` re-surface check in the mailbox-only test.

If the sweep's summary is multi-line, for example a per-record listing or a separate `no-change: surfaced, NOT dispatched` line, one call gives a count of 2 or more:

- The `-eq 1` checks fail even though exactly one notify happened.
- The `-eq 2` re-surface check can pass after only one sweep has notified.

These assertions pass or fail for the wrong reason. This only bites if the sweep's summary contains a newline, which I cannot see from this file.

---

I found nothing else I can point to: the other tests, the negation idioms (`! … || false`), the hermetic stubs and the env redirections all look correct as written.
