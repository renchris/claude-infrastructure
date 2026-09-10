I'll review the test file text only and report defects I can point at.

**Findings: one clear defect, one weaker check.**

**Defect 1**

1. **What** — The "all six event dirs" reap test only exercises five directories; the announce-alarms dir is never seeded or asserted, so a reaper that skips or over-reaps that dir stays green.
2. **Where** — lines 148 to 161, test `@test "all six event dirs: records past the horizon are reaped, young ones kept" {`. The seeding block is:
   ```bash
   mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
   mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
   mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
   mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
   mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
   ```
   There is no `mk_old`/`mk_young` line and no `[ ! -f ... ]`/`[ -f ... ]` pair for `$CC_ANNOUNCE_ALARM_DIR`.
3. **Why it is wrong** — The file header and the setup comment both say the sweep age-reaps six dirs, and cc-announce-alarms is one of the drained dirs. If the sweep's reap loop omits that dir (old alarms accumulate forever) or applies a zero horizon to it (young alarms are deleted before the desk is notified), this test still passes. The test name claims coverage of a class it does not cover.

**Defect 2 (weaker)**

1. **What** — The horizon test asserts a substring that also matches wrong horizons, so it does not actually pin the value to 7 days.
2. **Where** — line 195: `run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"`
3. **Why it is wrong** — The pattern is an unanchored substring. A sweep with `CC_EVENT_TTL_DAYS:-70` or `:-700` matches and the test passes, while the test name states the horizon "is 7 days". The pairing with the 9-day-old fixture in the reap test would catch an increase, but this test on its own proves nothing about the value beyond a leading digit 7, and the `grep -c` count output is discarded rather than checked.

Everything else I checked holds up: the `notify_count` precedence, the negated-pipeline `|| false` idiom, the env-prefixed `run` call, the append-only IDL grep assertions, and the failure-distinct positive controls for the seen-marker gate.
