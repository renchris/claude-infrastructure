Two defects found; everything else in the file reads as sound.

**1. The "all six event dirs" test only exercises five dirs**
- **What:** The test claims to prove the age-reap covers all six event dirs, but it seeds and asserts on only five. The sixth, `CC_ANNOUNCE_ALARM_DIR`, is never given an old or young record.
- **Where:** line 163: `@test "all six event dirs: records past the horizon are reaped, young ones kept" {`. The seeding is at lines 164-168, and the assertions at lines 173-177 cover pages, comms-alarm, push-records, completion and teardown.
- **Why it is wrong:** The setup comment says the sweep age-reaps six event dirs, and `CC_ANNOUNCE_ALARM_DIR` is a directory the sweep reads. If the sweep never reaped that dir, or reaped it with a collapsed horizon that ate young alarms, this test would stay green. The suite's own "OLD reaped AND YOUNG kept" pair rule is therefore not met for one of the six dirs.

**2. The horizon test's title states a false magnitude and asserts nothing about it**
- **What:** The title claims 7 days is "three orders of magnitude" above the lint floor, but 7 days is 604,800 s against a floor of 6,000 s, about 100×, or two orders. The body never checks any magnitude either.
- **Where:** line 214: `@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {`
- **Why it is wrong:** The body only greps the sweep source for the literal `CC_EVENT_TTL_DAYS:-7` and checks that the lint script exits 0. If the horizon were changed to a value only about 10× the floor, the test would still pass as long as the string matched and the lint passed. It cannot fail for the reason its title gives.
