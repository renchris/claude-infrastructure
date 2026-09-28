Three findings. Only #1 is a clear defect; #2 is a weaker assertion gap, and #3 is a wrong claim in a test name that does not change what runs. I used nothing beyond the text of the brief.

## 1. The reap test claims six directories and exercises five

**What** — The test titled "all six event dirs" seeds and asserts only five directories, and never ages a record in `CC_ANNOUNCE_ALARM_DIR`.

**Where** —
- `tests/autonomy-sweep.bats:163`
  `@test "all six event dirs: records past the horizon are reaped, young ones kept" {`
- The seed block ends at `:168`
  `  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"`
- The assertions end at `:177`
  `  [ ! -f "$CC_TEARDOWN_RECORDS_DIR/old.json" ];   [ -f "$CC_TEARDOWN_RECORDS_DIR/new.json" ]`
- The directory left out is exported at `:12`
  `  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"`

**Why it is wrong** —
- Lines 21–22 and 155 say the sweep age-reaps six event dirs.
- `setup` exports six event-dir variables: pages, announce-alarms, completion, comms-alarms, push-records and teardown. `decisions/` and inbox-guard have their own tests.
- Lines 164–168 cover five of the six. By elimination the missing one is announce-alarms. Every write into that dir in the file is a fresh `a1.json` (lines 76, 138, 311, 331, 350, 368, 380), so no old record is ever placed there.
- If the sweep never reaps that dir, reaps it wrongly, or loses its reap step, this test stays green. The title still says all six are verified.

## 2. The final test's negative assertion has no positive control

**What** — The test's only guard against a no-change fire being counted as queued is a negated grep for a string that no test ever shows the sweep emitting, so it can pass vacuously.

**Where** —
- `tests/autonomy-sweep.bats:409`
  `  ! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false`
- The test starts at `:402`
  `@test "the summary distinguishes queued fires from no-change fires" {`

**Why it is wrong** —
- The test's only input is a no-change fire. `fired→backlog` appears nowhere else in the file, and no test that runs a queued fire (lines 112–123, 250–261, 263–271, 273–280, 282–292) greps the notify log.
- If the sweep words a queued fire any other way, line 409 is true for every input. That includes a sweep that wrongly counts the no-change fire as queued, and the test still passes under a title claiming it "distinguishes" the two.
- The file pairs its other negatives with positive controls (lines 250–261, 375–388). This one has none.
- Line 408 does check the no-change wording, so the gap is only in the negation.

## 3. The test name misstates the horizon-to-floor ratio (minor, not behavioral)

**What** — The test name says the 7-day horizon is three orders of magnitude above the lint floor, but by the file's own numbers it is about two.

**Where** —
- `tests/autonomy-sweep.bats:213`
  `# ── the horizon must outlive the reaper-horizon-lint floor (600 s sweep × 10 = 6,000 s) ────────`
- `tests/autonomy-sweep.bats:214`
  `@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {`

**Why it is wrong** — 7 days is 604,800 s and the stated floor is 6,000 s, a ratio of about 100×, not about 1,000×. The test checks neither ratio. It only greps for the literal `CC_EVENT_TTL_DAYS:-7` (line 215) and requires the lint to exit 0 (lines 217–218). The name therefore overstates the margin by 10× while the assertions stay the same.
