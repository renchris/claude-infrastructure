I found four defects, all in the tests' assertions. The first is the clearest.

**1.**
- **What:** The test claims to cover all six age-reaped event dirs but exercises only five. The announce-alarm dir is never populated or checked.
- **Where:** line 163, `@test "all six event dirs: records past the horizon are reaped, young ones kept" {`. Lines 164–168 and 173–177 cover pages, comms-alarm, push-records, completion and teardown. The dir exported at line 12, `export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"`, has no `mk_old`/`mk_young` and no assertion.
- **Why it is wrong:** If the sweep's reap of `cc-announce-alarms` is missing, or reaps young records, this test still passes. The file's own header (lines 21–24) names this class of gap as the risk, and the test title says the class is covered when it is not.

**2.**
- **What:** The "old shape is gone" pin matches one literal string. It does not cover the class it names, "neither rc-discarded nor stderr-discarded".
- **Where:** line 393, `run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"`, followed by line 394, `[ "$output" = "0" ]`.
- **Why it is wrong:** The notify call is now role-addressed (line 82 asserts `--role desk`). Any regression that discards rc or stderr but words the call differently gives count 0 and passes. Examples: `"$NOTIFY" --role desk "$summary" >/dev/null 2>&1 || true`, or the same call with a different variable name. The data-loss bug could return and this test would stay green.

**3.**
- **What:** The test title states a false magnitude, and the assertion only checks that a source string exists, not that the horizon is 7 days.
- **Where:** line 214, `@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {`, and line 215, `run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"`.
- **Why it is wrong:**
  - **Magnitude:** 7 days is 604,800 s against the stated floor of 6,000 s (line 213). That is about 100×, two orders of magnitude, not three.
  - **Grep:** `grep -c` succeeds if the text appears anywhere, including a comment or an unused default. It never checks that the effective horizon is 7 days. The 9-day-old file at line 160 only shows the horizon is under 9 days.
  - **Interval:** Line 213 says the sweep runs every 600 s, but line 346 says records re-surface "every 300 s". One of them is wrong, and it changes the floor the comparison uses.

**4.** (weakest)
- **What:** The test claims the summary distinguishes queued fires from no-change fires, but it only asserts that one label is present and another is absent. It has no queued-fire case.
- **Where:** line 409, `grep -q "no-change: surfaced, NOT dispatched" "$CC_NOTIFY_BIN.log"`, and line 410, `! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false`.
- **Why it is wrong:** Line 410 passes whenever that exact string is absent. That includes the case where the sweep never emits it, or spells it differently such as `->`. A summary that dropped the queued-fire label entirely would pass. Other tests in the file add explicit positive controls for exactly this reason (lines 250, 376), and this one has none.
