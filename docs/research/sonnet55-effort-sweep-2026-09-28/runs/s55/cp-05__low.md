I found two defects.

**1. The "all six event dirs" test only exercises five dirs.**
- **What:** The test claims to cover six event dirs but sets up and asserts on only five. The announce-alarm dir (`CC_ANNOUNCE_ALARM_DIR`) is never checked.
- **Where:** Lines in the test `@test "all six event dirs: records past the horizon are reaped, young ones kept" {`. The setup ends with:
  `mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"`
  The final assertion is:
  `[ ! -f "$CC_TEARDOWN_RECORDS_DIR/old.json" ];   [ -f "$CC_TEARDOWN_RECORDS_DIR/new.json" ]`
- **Why it is wrong:** The suite header says the sweep age-reaps six dirs, and this test is the only reap coverage. The announce-alarm dir is the only sweep-drained dir missing from the list. If the sweep never reaped it, or reaped it with a collapsed horizon that ate live alarms, this test would still pass. The "six" in the title overstates what is proven.

**2. The horizon test's title and assertion do not match.**
- **What:** The test is titled "three orders of magnitude above the lint floor", but 7 days is about 100× the 6,000 s floor, two orders of magnitude. The body never checks any magnitude. It only checks that the literal `CC_EVENT_TTL_DAYS:-7` appears in the script and that the lint script exits 0.
- **Where:** `@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {` and `run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"`
- **Why it is wrong:** `grep -c` exits 0 whenever the count is at least 1. The text could appear in a comment, or in a dead or overridden line, and the test would still pass without proving the effective horizon is 7 days. The stated margin is wrong and is not what is verified.
