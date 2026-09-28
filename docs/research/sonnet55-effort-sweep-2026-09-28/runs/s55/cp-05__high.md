I found two defects, both in the age-reap section. The rest of the file holds up, including the `! cmd || false` idiom that keeps `set -e` from swallowing negations.

**1. The "all six event dirs" test covers only five dirs.**
- **What** — The test claims to check all six reaped event dirs, but it seeds and asserts on only five.
- **Where** — line 163: `@test "all six event dirs: records past the horizon are reaped, young ones kept" {`. The seeding is lines 164–168, from `mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"` to `mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"`. The assertions on lines 173–177 mirror those five.
- **Why it is wrong** — `setup` exports six event dirs that the sweep can delete from: pages, announce-alarms, completion, comms-alarms, push-records and teardown. `CC_ANNOUNCE_ALARM_DIR` is never given an old or young record here, and no other test does it either. If the sweep never reaped that dir, or reaped it with a collapsed horizon that ate young alarms, this suite would stay green. The header comment says every case asserts the pair "OLD reaped AND YOUNG kept", and that pair is never asserted for that dir.

**2. The horizon test cannot tell whether the horizon is 7 days, and its name misstates the margin.**
- **What** — The test only greps for a substring in the script and runs the lint. It never checks the effective horizon, and it describes 7 days as "three orders of magnitude" above a 6,000 s floor.
- **Where** — line 214: `@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {`, and line 215: `run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"`.
- **Why it is wrong**
  - 7 days is 604,800 s against 6,000 s, about 100×, which is two orders of magnitude, so the stated margin is wrong.
  - `CC_EVENT_TTL_DAYS:-7` is an unanchored pattern that also matches `:-70`, `:-7000` and similar. It also matches the text in a comment or a dead branch. Any of those would leave the test green with a horizon that is not 7 days, or one that is never applied.
  - The only other check is that the lint exits 0, and it does so for any horizon above its floor.
