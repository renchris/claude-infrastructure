# A6: process and governance causes

## Findings

1. **No-apply was a deliberate choice, and nothing downstream picked the work back up.** Commit `82f08302a` (09-21 01:50 -0500) says: "Nothing here edits MEMORY.md, moves a topic file, or calls cc-memory-rotate." The reason is in `scripts/jev/promote-memory.sh:25-27`: "Eviction stays a human read, because a wrong demotion is invisible until the day the missing rule would have fired." After that, no backlog row (0 of 22 Jev rows) and no decision packet (0 of 4) asked anyone to apply the 19 swaps. VERDICT.md:113 ("The one thing that is the operator's") asks about unattended consent instead. The S4 recap (operator prompt 09-22T00:21) says "Next action is yours: decide whether it may run unattended".
2. **The operator's "Yes" to unattended mode bought zero calls, and the design meant it could not buy any.** The batch only calls when the corpus changes (`jev-batch.sh:46-51,81-83`). The corpus is orphans plus anchors, and only applying swaps would change it. Result: 146 ticks logged "corpus unchanged — no call made", 57 of them after 09-25 (measured: grep `jev-batch.log`). Packet `ea7a241bdf78` had predicted this in its own text: "The engineering value of the autonomous version is near zero here: the corpus it reads changes on the order of days."
3. **The unattended path cannot find the API key.** 7 ticks logged `REFUSED — jev not available`. They include the only 2 ticks that saw a changed corpus (`a05ff58e`, 09-22T23:51Z and 09-23T00:25Z; log lines 80-83). Every successful run after the armed pass was a tool call the agent made in S4 (00:48, 03:09, 03:17 and 03:43Z on 09-22). Estimated: launchd runs without the agent-secrets key in its environment, based on the refusals falling at the 30-minute tick cadence.
4. **ZDR fail-closed used up about 35 hours of a roughly 7-day window.** Packet `c3752f5fca96` ("Jev needs Zero Data Retention…") was open from 09-19T16:03Z to 09-21T03:11Z. During that time the in-hook arm made "372 calls in 25 hours, every one of them a 403" (`anti-deference-nudge.sh:273-274`). The operator's first `cc-jev rank --yes` ran "224 calls in, zero rows written" (S3 09-21T04:53Z), because ZDR was on by default in the new script.
5. **The predict-land false close came from a governance nudge.** At 07:23:01Z `cc-backlog add` warned: "this row cannot retract itself … a --falsifier makes that self-retracting" (`bin/cc-backlog:1802`). The S4 agent (f41a5f25) replied at 07:23:10Z: "Adding a falsifier that detects *mootness*, not arming". At 07:24:42Z it stored `test -e …/scripts/jev/predict-land.sh`. That probe tests whether the instrument exists, not whether the measurement was done.
6. **The system then carried out that falsifier.** At 08:06Z the venue flipped to `cloud` ("eligible … premise clear"), and a cloud worker built the script on a VM with no `land.log`. Its doc: "The file did not exist; it does now, and this artifact is why" (`jev-predict-land-2026-09-21.md:14`). At 16:48Z the row was blocked on the operator arming it. `cc-premise sweep --close-falsified` (`bin/cc-premise:2911`; `autonomy-sweep.sh:1496`, every 6h) skips only rows that are *claimed*, not *blocked*, so it closed the row at 09-22T03:00Z. Row `3aac8393d7ba` then closed as "MOOT — its gated item is closed" (09-22T18:52Z). The operator was never asked to arm it.
7. **The rule that forbids this was already in force and was ignored.** `.claude/rules/agent-operating-lessons.md:46` "Arming ≠ mootness" (lesson from `4cc96a231`, 09-17) says: "a probe detecting the precondition ARRIVING deletes the row at the instant it becomes actionable; say exit 0 aloud as a sentence about the row". Said aloud, this falsifier reads "the script exists ⇒ the row is not needed".
8. **Governance artifacts outnumber outcome artifacts.** Jev-citing text written 09-18..09-23:
   - 10 of the 55 `docs/lessons/*` files added in that period cite Jev (`git log --diff-filter=A` plus `grep -il jev`).
   - 0 memory topic files mention Jev (grep of the memory dir).
   - 14 research files come to 5,061 lines and 51,787 words (`wc`).
   - 0 lines of MEMORY.md changed.
9. **Most Jev backlog rows are landing overhead.** 22 rows touch Jev: 17 name it in `add`, plus 5 later. 16 of the 22 are re-land, post-land-RED or landing-hazard rows. Only 5 carry an outcome:
   trial ruling, API key and rank evaluation (all done; the ranking saturated), predict-land (false close) and `217241f4dfcb` (still blocked on the operator). The sixth, `3aac8393d7ba`, closed as moot.
10. **All 4 Jev decision packets reached a terminal state, but none produced an applied outcome.** `b1fe1071dad4` was vetoed ("trial is declined"). `c3752f5fca96` was actioned (ZDR off for the pilot). `ea7a241bdf78` was actioned, and bought 0 launchd calls. `shipland-esc-85be1d228` was actioned: the land gate escalated predict-land's own test fixture strings (a literal RSA private-key PEM header) and needed a human land.

## Guard table

| # | Guard (receipt) | What it blocks | Did it ever block something real? |
|---|---|---|---|
| 1 | ZDR fail-closed (`evaluate.mjs:30,58,105`; `rank-memory.sh:244`; `promote-memory.sh:392`) | Every call on the hobby plan (403) | **Yes**: 372 in-hook 403s; 224-call empty rank run; ~35h consent wait |
| 2 | Egress allowlist (`jev.sh:95-102`; `cc-jev:106-116`; `2db1d3336`) | Hosts not in `egress.allow` | Needed an operator edit first; no block seen in the 8 batch outputs |
| 3 | Kill switch / `jev_available` (`jev.sh:117-124`) | No key, no deps, `CC_JEV=0` | **Yes**: 7 launchd refusals, including the only 2 changed-corpus ticks |
| 4 | Billing window (`jev.sh:197-214`; `jev-batch.sh:134`; `arm.sh:74`; `promote:406`; `predict-land.sh:427`) | Calls after 2026-09-25 | **Never fired** (0 log lines). After 09-25 the corpus gate at `jev-batch.sh:81` runs first |
| 5 | Arm sentinel (`jev-batch.sh:55-58`; `arm.sh:5-9`) | Scheduled calls without a human arm | 20 "not-armed" ticks; armed once, 09-21T16:43Z |
| 6 | TTY-only consent (`44-jev-batch-activate.sh:71-89`) | Arming from a non-terminal | **Yes**: the operator's 16:05Z run gave "Not armed"; he armed by hand 38 minutes later |
| 7 | Corpus-unchanged gate (`jev-batch.sh:46-84`) | Re-running a finished pass | **Yes**: 146 ticks, and it is the permanent block under no-apply |
| 8 | Completeness stamp / resume bound (`75aa4097c`; `jev-batch.sh:70-76`) | Re-buying completed passes | Fixed a live loop ("re-ran a completed pass on three consecutive ticks") |
| 9 | Preflight (`promote:447-455`; `rank:235-255`; `predict-land.sh:462-467`) | A dead route spending the whole budget | 8 of 8 batch preflights OK; added after the 224-call dead run |
| 10 | `--yes` plan gate (`promote:388`; `rank:232`; `pilot.sh:120`) | Sending without typed consent | Operator-typed each time; no evidence it held anything back |
| 11 | Position-bias control (`promote:138-177,580-595`) | A swap list driven by slot order | **Passed**: 0 of 12 and 1 of 13 (7%), both under the 20% ceiling |
| 12 | Operator-directive hold-out (`promote:195-214`) | Demoting `feedback-*` rules | Held out 1 (`feedback-handoff-splitright-default.md`) |
| 13 | **No-apply** (`promote:25-27,254`; `82f08302a`) | Any MEMORY.md or topic-file edit | **Yes, on every run**: 19 swaps unapplied |
| 14 | predict-land null gate, exit 5 (`predict-land.sh:157`) | Spending when the target bar cannot be reached | **Did not fire**: exit 0, bar reachable on all 3 definitions (backlog 23102) |
| 15 | predict-land arm token (`predict-land.sh:52,440-470`) | Sending diffs without its own arm | **Yes**: never armed (no arm file), 0 calls; the row was closed before the operator was asked |
| 16 | Deference arm retired (`anti-deference-nudge.sh:265-280`; `c0d42c885`) | In-hook calls | Retired 09-21 after 0 marginal detections |

Scratch: `/tmp/jev-pm/a6-*.txt`.
