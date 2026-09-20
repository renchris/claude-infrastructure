# A `LANDED` verdict is not a TESTED verdict — read the smoke line

**The rule.** `ship-land` can land a commit whose suites never ran. Its smoke is **load-shed**: past
a load ceiling it prints `⏭ gate: smoke SKIPPED — this land is behaviorally UNGATED` and proceeds to
push. The statics (shellcheck, ratchets, lints) still ran; **no behavioural suite of your diff did**.
So `✓ ship-land: LANDED … content-verified` answers "did the bytes arrive", never "are they right".
After every land, read the smoke line, and if it shed, run your diff's suites yourself.

**Why shedding is correct and still dangerous.** Waiting for a slot is what starved five gates below
their own ceiling, so a SKIP is deliberately preferred to a wait (R7). The cost is stated in the
message itself: *"The post-land verifier is the only remaining net and it trails trunk by hours, so
a suite this diff breaks can sit RED on trunk until it catches up."* That sentence describes the
entire lifecycle of the defect class this repo keeps re-discovering — a red landing, sitting on
trunk for dozens of commits, tripping every subsequent lander, and finally costing a ~50-minute
corpus, a bisect, a failed auto-revert and a dispatched worker to repair.

**The measurement (2026-09-20, claude-infrastructure).** Land `38e1e48f1` *added a lint whose entire
purpose is to compensate for shed smoke* — and its own land shed at `1-min load 86.80 ≥ ceiling 80`,
so `tests/ship-land.bats` and `tests/postland-verify.bats` never ran against a diff that modified
`ship-land.sh` and `postland-verify.sh`. The irony is the point: the shed is not a rare event on
this box, it is the common one, and it lands changes to the landing rail untested.

**The second-order trap.** Verifying afterwards runs into the *other* admission gate: `cc-bats`
refuses when concurrent roots or load are high, printing `REFUSED … this is a DEFERRAL, not a test
result` and exiting without a TAP plan line. A deferral has **zero** `not ok` lines, so any harness
counting `grep -c '^not ok'` scores it as a pass. Always assert the plan line (`1..N`) before
believing a verdict; treat its absence as *unknown*, never as *green*. Measured in the same session:
a mutant that genuinely survives and a suite that never ran are indistinguishable on the `not ok`
count alone, and one mutation cell was scored "SURVIVED" purely because its `sed` had failed and a
second because its suite was shed.

**The lever when verification genuinely cannot wait.** `cc-bats` ships a recorded waiver —
`CC_BATS_WAIVER_REASON='<why>' CC_BATS_MAX_ROOTS=0 bats <suite>` — written to
`~/.claude/state/bats-waivers.jsonl`. It is the right tool for *post-land verification of an ungated
land* (the land gate is itself admission-exempt, bounded by the land-lock instead), and the wrong
tool for ordinary impatience. State the reason honestly; it is auditable.

**Companions.** `the-land-gate-is-admission-exempt` (why waiting for a slot before `/ship` waits on a
ceiling that does not apply), `a-gate-refusal-is-not-a-gate-result` and
`bats-shortfall-nonverdict` (the no-plan-line family).
