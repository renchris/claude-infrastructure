# Row 15: the five rulings, final recommendations and the operator's ruling (2026-10-08)

Produced by workflow `wf_e55772c9-bd1` (per decision: a researcher aimed at what would move conviction, an adversarial critic, a judge). Written to disk by the research-program lead. No sealed set was opened.

**Operator ruling, 2026-10-08:** "all recommendations" and "proceed with your recommendations after" — every decision below is ruled as the judge's final recommendation, including `0ccbcf9fd49b`, whose recommendation changed from the filed `fresh-v5-if-40` to `second-read-v4` with a switch clause.

| decision | final recommendation | conviction |
|---|---|---|
| `a7fd5e2ee7c8` — The re-ask detector (the "router") decides whether you are asking again for completeness or pushing back. Should its next test against the s… | fix-then-gate-read, with four added preconditions. Make no standalone sealed read. | 86% |
| `8633d354bd41` — Which model should do the re-ask router's second, "careful" check when we lock it in? The router is the classifier that spots questions aske… | retune-haiku55-first, revised so that the rule cannot be passed by luck or by overfitting. All of this is pre-registered before any call: | 70% |
| `915d7fb98b7f` — When the certifying gate tests the re-ask router, where should the subtle re-asks come from? These are the ones the pattern list misses. The… | Choose fresh-v5-subtle, and pre-register it now as a contingent rule. It replaces the earlier wording, "once 400 candidates exist". | 74% |
| `0ccbcf9fd49b` — When the research program's final gate checks how well the re-ask router catches plain re-asks (the ones the regex patterns already match), … | second-read-v4, with one switch clause. This replaces the filed fresh-v5-if-40. | 74% |
| `17aff7158fa6` — When the certifying gate runs its re-ask classifier check (gate row 15) on sealed data, should that check wait for the machine's 1-minute lo… | bound-in-evaluate, revised from the researcher's version. (1) Before the reads-ledger write (scripts/research-kit/heldout.py:635), wait for 1-minute load <= 40  | 78% |

## `a7fd5e2ee7c8` (86%)

**Question:** The re-ask detector (the "router") decides whether you are asking again for completeness or pushing back. Should its next test against the sealed, never-seen test questions be the final certification check itself (gate row 15), run only after the detector is fixed and proven on practice questions under heavy machine load? The alternative is a separate sealed test run soon.

**Answer:** Run no separate sealed test now. Make the next sealed test the gate's own router check. A "soon" test needs the same fix first, so in practice it could only run days before the gate, which is about 1 to 2 weeks out, and every extra test uses up scarce test questions. Before the gate's test runs, add four guards, because the plan as filed has gaps that could waste the read or let it be re-run until it passes.

**Recommendation (ruled):**

fix-then-gate-read, with four added preconditions. Make no standalone sealed read.

The next sealed read is the gate's row 15. It runs only after all of these hold:
- The backup cold call at 4 s (the "hedge") passes RULE E1k's real-load run, meaning run 2 at load 150 or more with hedge-on fallback at most 0.03.
- The second, careful model call is pinned under a tuning-only rule written before any data is seen.
- The instrument is re-pinned with the load bound built in.

The four guards:

(1) Code guards before any read. Row 15 decrypts and logs a read only when three things are true: an explicit read-consent flag is set; CC_RESEARCH_ROUTER is a real command, never "off"; and rows 1-14 and 16-19 already passed in the same gate run. Otherwise it fails without reading. Today a session launched with the kill switch would run `/bin/bash -c off` on every item and still spend the read (heldout.py:581-582, :554-558, :629-640; gate_rows_b.py:357).

(2) A wider tuning-side proof. Add a warm-path, real-load replay of the 42 counted "regex-missed" tuning items (the subtle re-asks the pattern list misses) under the gate's load bound. A row held with the careful call silent counts as a miss. The E1k A/B covers none of these items, and the fallback metric cannot see this failure.

(3) A rule fixed in advance: a row-15 FAIL at the gate is final for those items. The next attempt waits for fresh items, and the same items are never re-read.

(4) Any third read of the v3 test set is stated as a disclosed cost, not treated as banned.

Re-open this decision only if ruling 2 pins a re-tuned Haiku 5.5 AND ruling 3 has the gate read a fresh v5 set. In that case a disclosed v3 preview, which shares no items with the gate's set, becomes a reasonable alternative. Conviction 86.

**Options:**

- **fix-then-gate-read (recommended, with the four guards)** — No sealed questions are used until the certification gate, and each sealed set is read at most once. TrueMemory 2.0's certificate waits on the router fix under either option. Sample noise alone gives row 15 about a 22% chance of failing with a Haiku 4.5 careful call, and 61-72% with Haiku 5.5. A failure blocks the certificate until fresh subtle re-ask items exist, about Nov 7 to Dec 8 at the measured 6-12 a day.
- **standalone-read-soon** — One extra sealed read: a third read of v3's subtle re-ask items. It cannot usefully run before the fix (otherwise it repeats the Oct 7 failure on timeouts), so it lands only days before the gate. If the gate also reads v3, the gate's read becomes the fourth. Its only real value is an early check of an untested Haiku 5.5 pin on items the gate will not reuse, and only if the gate waits for fresh v5.
- **one config-bound read the gate reuses (critique's alternative)** — Also one read, taken in the first low-load window after guards 1 and 2 pass and tied to the router's configuration id (with binary path and version hashed). The gate reuses that result while the id still matches, which moves the 73-minute read out of the gate's own 0.25-1 day window. It needs a named method edit to row 15's 'This run' wording (REPORT:606) plus new binding code, and it risks the router drifting between the read and the gate.

**Why the conviction moved:** Up 2 from 84 to 86. The gate is closer than the prior report assumed: E2 and E3 are done, and Stage 5 opened 2026-10-08 17:19Z (`cc-research budget` => stage 5 0.07 d of 2.5 d). The router fix chain (E1k run 2 still waiting for a load-150 window, with `uptime` => 48.9 at 14:01; ruling 2; a possible re-tune; your 0059 daemon restart; the load-bound edit) will likely run to or past Stage 8, so a "soon" read has no window to happen in. A soon read is also always one more sealed read on top of the gate's. Two things hold it below 90. First, the researcher's "forbidden third read" leg was overstated: that rule is scoped to waves, not to the method. Second, the critique's config-bound single read is a credible alternative a reasonable operator could prefer, and rulings 2 and 3 (which careful call, which test set) are still open.

**Critique, resolved:**

1. Number check: ACCEPTED. One correction: hedge-on p90 is 4.07 s per e1k-ab-run1.report.txt and plan:1683, not 3.97 s. I reproduced the pass odds by python: beta-binomial 0.776/0.388/0.276 at n=25 and 0.712/0.297/0.194 at n=31.

2. "Forbidden third read" overstated: ACCEPTED IN PART. The no-third-read rule appears only in wave scopes (plan:1056, :1115, :1283). Ruling 3 of the prior report proposes a disclosed third v3 read (rulings REPORT:20), and it lists the rule's binding status as an unknown (:138). REBUTTED on "counts equally against both options". A standalone read is always one more read: if the gate reads v3, the gate's read becomes the fourth; if the gate reads v5, the soon read is pure added cost to v3. So it survives as an extra-read cost, not a ban, and the +2 no longer rests on it.

3. The tuning proof misses the deciding stratum: ACCEPTED. tuning-v4.jsonl has strata other 340 and regex-matched 150, and its first 300 rows are 150/150, with 0 regex-missed (python count). The union join returns the fast call's non-relay label at the 8.5 s hold when the careful call is silent (e1h-score.py join, `if fo: return FL, max(f, cd)`). That is a recall miss, not a fallback. Fast call alone: 34/42 regex-missed (score alone(sonnet-off) => rm 34/42). The 7 items only Haiku 4.5's careful call catches take 4.96-6.23 s cold, so a cold call started at 4 s cannot finish by the 8.7 s give-up. Haiku 5.5's rescues take 1.8-2.2 s and could make it. One scope correction: "median 6.84 s, 71/294 over 9 s" covers all 294 regex-missed rows. On the 42 counted calls the figures are median 4.98 s and 2 over 9 s. The conclusion holds.

4. No rule for a FAIL at the gate: ACCEPTED. The cap row (REPORT:1104) limits repairs, not reads. At 22-72% failure odds per read, read-until-pass on the same items is a real risk, so a FAIL becomes final for those items.

5. Kill-switch collision: ACCEPTED, verified. hooks/research-precognition-nudge.sh:19 and :27 define CC_RESEARCH_ROUTER=off as the kill switch. gate_rows_b.py:357 passes the env var through as-is. heldout.py:581-582 refuses only an empty value, route() runs `/bin/bash -c <router>` (:554-558), and the ledger row is written before the first call (:629-640).

6. Timing: ACCEPTED. The on-budget sum is Stage 5 2.5 d + Stage 6 1 d + Stage 7 about 2 d (REPORT:1013) + Stage 8 0.25-1 d (REPORT:585), which gives about Oct 13-16, or about Oct 18-19 with Stage 4's 1.54x overrun. Either way the gate is about 1-2 weeks out, and the fix chain likely reaches it, so this strengthens fix-then-gate.

7. Missed option: ACCEPTED as a third option for the operator, NOT recommended over the base. With guards 1 and 3 the per-attempt re-read hazard is already closed, so its remaining benefit is timing: it moves the 73-minute read (plan:1360) out of the gate's window. Against that, it needs a method edit to row 15's 'This run' (REPORT:606) and new binding code.

## `8633d354bd41` (70%)

**Question:** Which model should do the re-ask router's second, "careful" check when we lock it in? The router is the classifier that spots questions asked again. The choices: (1) try once more to tune the newer, faster Haiku 5.5, keeping it only if it matches the older model's catch rate; (2) lock in the older, slower Haiku 4.5 now; or (3) run both models alongside the fast Sonnet check.

**Answer:** Re-tune Haiku 5.5 first under a strict rule written in advance, and lock in Haiku 4.5 automatically if Haiku 5.5 falls short. The re-tune costs one low-load night and does not delay anything, because the gate's next router check is waiting for new test data until about November 1-22. Haiku 5.5 tuning will be needed anyway by about mid-December, when Haiku 4.5 is likely retired.

**Recommendation (ruled):**

retune-haiku55-first, revised so that the rule cannot be passed by luck or by overfitting. All of this is pre-registered before any call:

(a) The brief change. Write it as a general rule for subtle re-asks. It must not quote or paraphrase any tuning prompt, and its author does not read the 3 prompts the union misses (v2:3eb113fd, v1:018b03b5, v2:77893fcb). Pin the binary and the effort level explicitly. Effort is not the lever: medium, low and as-built miss the same prompts.

(b) The bars. Haiku 5.5 must match Haiku 4.5's tuning numbers on two independent runs: at least 41/42 regex-missed and 162/163 pooled each run, or 82/84 and 324/326 with the two runs pooled. It must also not regress: relay decision on ordinary prompts at least 229/240, wrong relays at most 36/504, borderline at least 69/138. If any bar fails, the rule locks in the Haiku 4.5 union (Sonnet fast call plus Haiku 4.5).

(c) Before either model is locked in, run a matched-load, interleaved A/B of the two unions on tuning rows only. Use two warm daemons on separate sockets (as in wave E1g) and alternate rows. Measure the fallback rate, wrong in-time labels on re-ask rows, and the median decision time.

(d) Write the pick down for both outcomes of ruling 5 (the pending load limit on the gate's own read).
- With a load limit, the recall bars in (b) decide.
- Without one, an A/B fallback result above 0.03 at load 60 or more vetoes the slower union.
- In both cases, about 4 s more wait on most prompts in every certified session is a stated tiebreak toward Haiku 5.5.

Do not build the three-call union. On tuning data it catches nothing extra (162/163 and 41/42 either way). It raises wrong relays from 36 to 53 out of 504, keeps the 8.5 s p90, and adds a third type of resident worker to the daemon whose stalls caused the failed re-test.

Option convictions: re-tune first (revised) 70; lock in Haiku 4.5 now 28; three-call union 2.

At 70 this goes to the operator. The reasons it is not higher:
- Haiku 5.5 alone catches 32 of the 42 subtle re-asks, against 39 for Haiku 4.5 (paired test p=0.065).
- Any re-tune pass is scored on the same 42 tuning calls that it targets.
- If ruling 5 adds a load limit to the gate, Haiku 4.5's measured lead gives it the better first-gate odds: about 0.88, against 0.46-0.66, of reaching 24/25 on the regex-missed stratum.

**Options:**

- **retune-haiku55-first** — One low-load night of tuning-only calls (about 4,300 cold calls, no sealed data). The rule is written beforehand, followed by a matched-load A/B of both setups. Haiku 5.5 is locked in only if it matches Haiku 4.5's catch rate on two runs without adding wrong relays. Otherwise Haiku 4.5 is locked in automatically. Nothing on the critical path moves. Main risk: a brief that fits the 3 missed tuning prompts passes in tuning and then fails the gate, which has no re-test left.
- **pin-haiku45-now** — Locks in the best-measured setup: 41 of 42 subtle re-asks in tuning, about an 88% chance of passing the gate's subtle stratum if that holds. Costs: about 4 s more wait on most prompts in certified sessions (median decision 5.95 s against 2.17-2.37 s), and more timeouts under load (8 of 96 rows against 0 of 395 below load 150, on overlapping rows). A forced switch also comes when Haiku 4.5 retires, likely around mid-December, so the Haiku 5.5 tuning work still happens, just later.
- **three-call-union** — No extra re-asks caught (162/163 and 41/42, the same as the Haiku 4.5 union). Wrong relays rise from 36 to 53 of 504, the 8.5 s p90 stays, and a third worker type is added to the daemon whose silent workers caused the failed re-test. Rejected.

**Why the conviction moved:** Up from 66 to 70, a small net move.

What raised it, with new evidence for Haiku 5.5:
- A matched-row comparison of timeouts. Both runs used the same script on the first rows of tuning-v4: the Haiku 4.5 setup fell back on 8/96 rows below load 150 (5/18 at load 100-150), against 0/95 (E1j) and 0/300 (E1k run 1) for Haiku 5.5. Timeouts are the condition the one re-test actually failed on.
- The measured cost in production: the router holds every prompt in a certified session for up to 9 s, and the Haiku 4.5 union's median is about 4 s slower.
- The Haiku 5.5 tuning work has to happen by mid-December anyway, so doing it now wastes nothing.

What kept it from reaching the researcher's 78:
- The "Haiku 4.5's lead disappears under load" pillar is not supported. E1i's sealed read had zero wrong in-time labels on 93 answered re-asks, and the 7 rescues land at 4.96-6.23 s, below Haiku 4.5's 6.33 s median, so the all-row cut rate overstates their loss.
- The raised bar is still scored in-sample, on the very prompts the re-tune targets.
- If ruling 5 adds a load limit, Haiku 4.5's recall lead decides the first gate.

**Critique, resolved:**

1. Numbers verified. Accepted, with the correction: Haiku 4.5's 7 regex-missed rescues arrive at 4.96-6.23 s (python over tune.json => [4.96, 5.0, 5.14, 5.16, 5.72, 5.73, 6.23]; the 4.48 s is its single regex-matched rescue).

2. Accepted in substance; the critique's "contradicted" is softened.
- E1i recorded "Not one relay-gold prompt in either stratum got a wrong label in time" (plan, E1i section, "What the failure is made of").
- Under the researcher's model, about 0.75-1.4 such errors were expected among the 93 answered items: 13 regex-missed × 7/42 plus 80 regex-matched × 1/112, times a 26-50% cut. Seeing zero then has a chance of about 0.24-0.47, so it is weak evidence, not a refutation.
- Separately, the rescues arrive below Haiku 4.5's median, so the all-row cut rate overstates their loss. The claim is dropped as a reason.

3. Accepted and strengthened, because the rows match.
- Python over e1i-latency.json and e1j-latency.json, both from e1i-latency.py on the first N rows of tuning-v4.jsonl. Haiku 4.5 setup: below load 100, 3/78 fallbacks, median 5.97 s; load 100-150, 5/18. Haiku 5.5 setup: below load 100, 0/27; load 100-150, 0/68. E1k run 1 (Haiku 5.5): 0/300 at load 39-84.
- A mechanism is partly shown: the careful call answered first on 42/594 rows in the E1i read, against 48/178 in E1j step 5. A slow careful call rarely covers a stalled fast call.
- Still confounded by day, so the A/B in (c) is required.

4. Accepted.
- hooks/research-precognition-nudge.sh:11-19 routes every genuine prompt in a certifying or certified program session, with up to a 9 s wait.
- The Haiku 4.5 union's median is 5.95 s (result-e1i.txt), against Haiku 5.5's 2.17-2.37 s (e1k-ab-run1.report.txt).
- Caveat: truememory-2-0 is "registered" in programs.json today, so this cost starts at certification.

5. Accepted. Added: a general-rule brief whose author does not view the 3 missed prompts, replication on two runs, and no-regression bars. The remaining in-sample risk is what keeps conviction at or below 90.

6. Partly accepted. The "pay twice" argument is weaker as a reason to lock in Haiku 5.5. Rebutted as a reason against the re-tune: row 15 runs at every gate (lib/gate_rows_b.py:353-357 calls heldout.evaluate), and Haiku 4.5 likely retires around mid-December. So the Haiku 5.5 tuning is needed regardless, and a failed attempt now only moves that work earlier.

7. Accepted. The pick is now written for both outcomes of ruling 5 (76% in the rulings REPORT). With a load limit, Haiku 4.5's fallbacks are near zero (1 in 89 at load 0-40, e1i-load-bound.md CORRECTED table), so recall decides.

8. Partly accepted. The fast-side hedge works whichever careful model is pinned. But cold calls have never been measured above load 75 (rulings REPORT, Unknowns), and in E1k run 1 the hedge fired 14 times and won 0. So whether it evens out fallbacks between the two models under heavy load is unmeasured, and the matched A/B in (c) measures it.

## `915d7fb98b7f` (74%)

**Question:** When the certifying gate tests the re-ask router, where should the subtle re-asks come from? These are the ones the pattern list misses. The choice is between a fresh sealed test set (v5), which will not hold enough labeled items until somewhere between early and late November, and the old set v3, which has already been read twice and could be read now. The same question applies to the 2 pushback items.

**Answer:** Use a fresh v5, and write the timing rule now. Read v5 once it holds 40 labeled subtle re-asks, which should happen between about Nov 4 and Nov 24. If everything else the TrueMemory 2.0 certificate needs is ready first, wait at most 7 days, then read v5 as it stands. Reading v3 a third time would break a rule that was written twice, and that read passes a weak router 2 times in 3.

**Recommendation (ruled):**

Choose fresh-v5-subtle, and pre-register it now as a contingent rule. It replaces the earlier wording, "once 400 candidates exist".

(1) Seal one fresh set, v5, for subtle re-asks. If ruling 4 also picks fresh data for plain re-asks, the same set serves both. Seal it once 400 unused candidates exist (about Nov 4). After the two raters label it, if it holds fewer than 40 counted subtle re-asks, seal a top-up from later arrivals and pool it before any read.
- Why the floor is 40: below 40, the 0.95 bar allows only 1 miss, so a good router (true recall 0.976) fails 16-24% of the time at 30-39 items. At 40 it allows 2 misses and fails 7% of the time.
- Expected ready date: Nov 4 to about Nov 24.

(2) A timing cap, fixed now. Suppose every other TrueMemory 2.0 gate row and every other router prerequisite is ready before v5 reaches 40. The router prerequisites are a pass on the second real-load test, the careful-call pin with its restart, and the load bound. In that case, wait at most 7 days (you may pick another number). Then read v5 as it stands if it holds at least 20 counted items, and print its false-fail rate. Below 20, pool v5's items with v3's 25 as a disclosed third read, and only under a signed override of the standing "no v3 set read a third time" rule.

(3) Pushback: score it on v5's fresh pushback items. v3's 2 items join only under that same signed override.

(4) Do not ban the Haiku 5.5 re-tune (ruling 2) from drawing fresh subtle re-asks as tuning rows. That draw is ruling 2's decision, with the price stated in its packet: each ~14 candidates taken delays v5 about a day. For example, 100 candidates is about 7 days for roughly 6-11 more labeled re-asks.

(5) Whatever you rule: before anyone runs TrueMemory 2.0's gate with the router set, re-point the gate's test-set map off v3 (or make the scorer refuse a third read). Today the map still sends subtle re-asks and pushback to v3. The scorer notes earlier reads but does not refuse them, so the gate would spend the third read silently.

Conviction 74. That is below 90, so this goes to you.

**Options:**

- **Fresh v5 with a 7-day cap (recommended)** — The strongest test, and it keeps the no-third-read rule in the normal case. Ready about Nov 4 to Nov 24. If TrueMemory 2.0 is otherwise ready sooner, its certificate waits at most 7 more days. At 40 items a good router (0.976) passes 93% of the time and a weak one (0.90) passes 22%. At 20-39 items a good router fails 16-24% of the time, and that rate gets printed.
- **Fresh v5 with no cap** — Waits for 40 labeled subtle re-asks however long that takes, possibly until about Nov 24. Never reads v3 a third time. TrueMemory 2.0's certificate could wait about 3 weeks on this alone after everything else is ready.
- **Third read of v3 now** — No wait. You sign an override of the no-third-read rule written in two earlier rounds and of your own ruling that allowed only second reads. It is a weak test: given what the router already answered in the last read, it passes a 0.90 router 66% of the time. Every tuning miss sits in the kind of item that recent prompts are almost entirely made of.
- **Widened stratum** — Uses easier items that are already scored among ordinary prompts against a 0.90 floor. Every careful-call setup relays 24 of 24 of them on tuning data. In practice nothing tests subtle re-asks.

**Why the conviction moved:** 72 to 74, up 2 net.

What raised it:
- Reading v3 a third time breaks a pre-registration written in two earlier rounds, plus your ruling that granted only second reads. Sources: plan :777 ("should not carry a third verdict for any configuration chosen with these numbers in hand"), :1056, :1115, :1283 and :1062-1063.
- The power figures check out. A fresh read at 40 items passes a 0.976 router 0.929 of the time and a 0.90 router 0.223. The third read gives 0.968 and 0.659.
- The 7-day cap removes the open-ended delay that was the main objection.

What lowered it:
- TrueMemory 2.0 entered Stage 5 today (budget.json: stage 5 started 2026-10-08T17:19:54Z; budget 2.5 d, cap 3.75 d), so its gate could come before v5.
- The corrected yield is lower. 400 candidates give only about 24-46 counted subtle re-asks, so reaching 40 takes until somewhere between Nov 4 and about Nov 24.
- The cap length and the signed fallback override are value calls only you can make.

**Critique, resolved:**

I re-ran the miner's own functions, binned by timestamp, and ran Python over retired-v2.jsonl. No sealed set was opened.

1. The critic's verified items are accepted. I reproduced the pool: regex-missed (subtle re-asks) 648, regex-matched (plain re-asks) 684, pushback 51.

2. The arrival mix is accepted. Over 30 days, 408 subtle re-asks arrived, 12 of them gap-phrased (2.9%), so 97% follow a done-claim. Over 14 days: 187 arrived, 9 gap-phrased. retired-v2 subtle re-asks: gap-phrased 14 of 44 counted (0.318), after a done-claim 20 of 184 (0.109), 34 of 228 overall. Expected counted items at 400 candidates: about 46 by v2's yield, about 24 scaled to v3's 25/326. So 400 alone probably gives fewer than 40.

3. The step in the rule is accepted, and the binomial reproduces: 0.838 at 30 items, 0.760 at 39, 0.929 at 40. The floor is 40, met by top-up seals. Rebutted in part: a seal's dry run counts candidates, not counted items. Counted items are known only after labeling (plan :1330-1335 sealed, then labeled), so the rule tops up before any read rather than projecting.

4. Pushback breaking the pre-registration is accepted (plan :1056, :1115, :1283, :1062-1063). A v3 read now happens only under an explicit signed override, and only in the fallback branch.

5. The pre-registration counting for fresh data is accepted, and I add E1e's general principle (plan :777). This is what lifts conviction.

6. The unpriced ban on ruling 2 is partly accepted. The ban is dropped and its price stated (about 1 day per 14 candidates). The size of the draw is left to ruling 2 rather than fixed at 100 here.

7. "v3 cannot see the weak spot" was overstated; accepted. 545 of 648 in the pool follow a done-claim. The real difference is reuse and conditioning.

8. The minor counts are accepted and reproduced: 22 arrivals since the v4 seal (3 gap-phrased), 13.4-13.6 a day, so 400 is reached about Nov 4. The ceiling including Stage 9 is also accepted (plan E3c).

New finding: heldout.py:572-640 evaluate notes "read N time(s) before" but never refuses a read. The pinned instrument.json (2026-10-07T04:30:33Z) maps subtle re-asks and pushback to v3. gate_rows_b.py:357 reads it whenever CC_RESEARCH_ROUTER is set. So a gate run is a silent third read until the map is re-pointed.

The critic's below-20 branch uses v3 alone. I changed it to pool v5's fresh items with v3, which gives more information under the same override.

## `0ccbcf9fd49b` (74%)

**Question:** When the research program's final gate checks how well the re-ask router catches plain re-asks (the ones the regex patterns already match), which data should it use? Option one is the same 93-item test set read last time, which failed only because answers timed out under load. Option two is a fresh set, used once at least 40 usable items have built up.

**Answer:** Use the 93-item set again and label it as a second read. Every miss last time was a load timeout, and timeouts do not stick to particular prompts, so a second read is not an easier test. A 93-item test also catches a router that is still broken much more often than a 40-item test would: 87% of the time against 63%, for a router that misses 8% of re-asks.

**Recommendation (ruled):**

second-read-v4, with one switch clause. This replaces the filed fresh-v5-if-40.

What to do:
1. For the gate's read, score regex-matched (plain re-asks) on v4's 93 rater-agreed items, disclosed as a second read of the set whose first read failed, where all 13 misses were timeouts.
2. When ruling 3 seals v5 for regex-missed, seal the new regex-matched prompts in it too. Leave them unread for the next program's gate.
3. Switch this stratum to fresh data only once a fresh set has at least 93 counted items. That way freshness never costs test power. At about 3.5 prompts a day and a 0.345 yield, that is around late December, so v4 is what TM2's gate uses.
4. Drop fresh-v5-regardless.

Why:
- **Nothing biases a re-read.** Regex-matched labels have never missed: 14/14, 24/24 twice, 47/47, and 80/80 answered (plan :436, :590, :749, :1000, :1383). Timeouts also do not follow items once run position is held fixed. I compared fallback rows across E1i and E1j: they overlap on 3 rows (3, 10, 59), against 3.1-3.7 expected from position alone at windows of 5-20 rows. Every fallback came early in both runs, at the high-load start (python over e1i-latency.json and e1j-latency.json).
- **v4 gives the sharper test.** I re-ran the binomial math. At an 8% miss rate, n=93 passes 0.126 of the time, against 0.369 at n=40 and 0.263 at n=47. At a 2% miss rate the two sizes pass equally often (0.961 vs 0.954). At a miss rate exactly on the bar, n=93 is closer to a fair coin flip (0.50 vs 0.68).
- **Read correctly, the precedent supports v4.** E1h (c) at plan :1062-1063 and RULE 2' at :1279-1281 took fresh data only when it beat the reused set: about 60 counted vs 25, and 93 vs 47.
- **The wave's own ruling 4 already proposed this.** Plan :1577: "a disclosed second read of v4's regex-matched items".

In practice: for any gate before about Nov 10 this gives the same data as the filed option. Fresh v5 reaches 40 counted with probability 0.16 by Nov 4 at 3.5 a day, and 0.002 at 2.5 a day (Poisson thinning, python).

Separate question for the operator, outside this ruling: set a standing re-pin policy for row 15. The gate re-reads the pinned instrument at every certificate (gate_rows_b.py:351-362), and heldout.py only notes earlier reads without refusing them (:627-648). So the next gate needs either v5 or a third read of v4, and the plan's "no third read" norm (:1056, :1364) should be declared binding or not.

The packet's option text (decisions/0ccbcf9fd49b.json) is wrong. It should be replaced with the outcomes below before the operator reads it.

**Options:**

- **second-read-v4 (recommended; switch to fresh only once it has >= 93 items)** — The gate scores plain re-asks on the 93 already-rated items from last time, stated as a second read. A router that still misses 8% of re-asks gets through about 13% of the time. New plain re-asks are sealed with the next fresh set and kept unread for the following program's gate. This is the same data as the filed option for any gate before about Nov 10.
- **fresh-v5-if-40 (filed at 70)** — If the fresh set has at least 40 usable items when it is sealed, the gate scores those; otherwise it uses the same 93-item second read. Before about Nov 10 it almost always ends up using the 93 items anyway (16% chance of reaching 40 by Nov 4). If the gate slips later, it swaps in a 40-60 item test that lets an 8%-miss router through 26-37% of the time instead of 13%.
- **fresh-v5-regardless** — Always uses unseen prompts, but only about 34 items by Nov 4, 41 by Nov 10 and 47 by Nov 15. At 34 or fewer only one miss is allowed. A good router (2% misses) then fails about 15% of the time, while a bad one (8%) still passes about 23%. This is the weakest test of the three.

**Why the conviction moved:** The conviction moved from 70 to 74, and the recommendation flipped from fresh-v5-if-40 to second-read-v4.

The flip has three causes:
- The research removed the only real argument against a re-read, bias. The critique made that case stronger: with run position held fixed, the fallback overlap between runs is 3 observed against 3.1 expected, so there is no item effect at all.
- The 93-item set is measurably the sharper test where it matters, against a bad router (0.126 vs 0.369 false-pass at an 8% miss rate).
- The precedent claimed for fresh-v5-if-40 actually backs "fresh only when it is at least as large", which this recommendation keeps.

It stays below 90, so it goes to the operator. A reasonable operator could still want unseen data for the look of a "fixed as tooling" exit certificate that follows a failed read. The operator has twice preferred first reads when they were available (RULE 2 and RULE 2'). And for any gate before about Nov 10, the two leading options give the same data, so this is a value call, not a measured one.

**Critique, resolved:**

1. **The researcher's numbers.** Accepted. My binomial re-run matches exactly: n=93 gives 0.961/0.501/0.126/0.038 and n=40 gives 0.954/0.677/0.369/0.223 at miss rates 2/5/8/10%. Also, n=19 allows 0 misses and n=20 allows 1, per the ok/n<0.95 rule at heldout.py:707-710. The supply probabilities come out slightly different under Poisson thinning (0.16/0.59/0.87 for Nov 4/10/15 at 3.5 a day, against 0.11/0.64/0.92), with the same shape.

2. **Item dependence is confounded with run position.** Accepted, and it is stronger than the critique said. Fallback rows were E1i {3,5,6,7,10,56,58,59} at loads 103-145 and 84-91, and E1j <100 {1-4,9-12,14,15,23,39-43,48,49,57,59,82} at loads 203-355. Both runs walk tuning-v4 rows 0-99 in order (python over the latency JSON). Expected overlap with position held fixed is 3.1 (window 10), 3.4 (window 5) and 3.7 (window 20), against 3 observed. So the item effect is zero.

3. **v4 is the better test, yet the researcher recommended against it on precedent.** Accepted. The attempt cap at method REPORT §6.5 controls repeated testing, and under the measured model a re-read is an independent draw of the timeout noise.

4. **The precedent is overstated and miscited.** Accepted and verified. Plan :20-30 is the Phase 0 table, and E1h (c) is at :1062-1063. Fresh data was preferred only when it was larger than the reused set: 400 candidates is about 60 counted at v2's 34/228 yield (:1157) against v3's 25, and fresh v4's 93 against v3's 47 (:1000). MIN_SET=40 is a whole-set floor (heldout.py:85-86), not a per-stratum floor.

5. **The 40 threshold trades power for freshness.** Accepted. The recommendation now switches only at 93 or more.

6. **Competition for fresh supply.** Partly accepted. The Haiku 5.5 re-tune plan uses existing tuning data (haiku55 REPORT :5, :72), and regex-matched has never missed, so no re-tune has a reason to draw it. Any draw would only push the v5 branch later, which makes the two leading options even more alike.

7. **Read budget.** Accepted as a gap that sits outside this ruling. It is added as a separate operator question: a standing re-pin policy, with the "no third read" norm (:1056, :1364) declared binding or not. The recommendation also seals fresh regex-matched prompts unread for the next gate.

8. **The packet text is wrong.** Accepted and verified. decisions/0ccbcf9fd49b.json says "tests the timeout fix rather than recall" and "about 25-40 items by mid-November". Corrected outcomes are given above. The "0.9987 vs 0.212" power claim (rulings REPORT :76) is withdrawn.

9. **Conviction.** Accepted: 80 for fresh-v5-if-40 was too high. The critique's "better option" is adopted as the recommendation, at 74 rather than its 70, because the position-held overlap shows the bias case is fully gone, not just weakened. Plan :1577 also shows the E1j wave itself proposed the v4 second read.

## `17aff7158fa6` (78%)

**Question:** When the certifying gate runs its re-ask classifier check (gate row 15) on sealed data, should that check wait for the machine's 1-minute load to fall to 40 or below before each item, written into row 15 as a named method change?

**Answer:** Yes. Build the load wait into the gate's own check, and state on the certificate that row 15 was measured at load 40 or below, next to the real-load numbers from the hedge A/B test (hedge = a backup cold call started at 4 s). The wait is cheap insurance against losing the program's last sealed read to an evening load spike: a 73-minute read has about a 22% chance of running into one. It stays below 90% because waiting about a day for the second real-load test and the careful-model ruling costs nothing.

**Recommendation (ruled):**

bound-in-evaluate, revised from the researcher's version. (1) Before the reads-ledger write (scripts/research-kit/heldout.py:635), wait for 1-minute load <= 40 with a cap. If the cap expires, refuse and log no read. (2) Replace the uncapped per-item wait with a long, finite total cap that prints 'read spent, no verdict' when it fires, and launch the gate detached so a tool timeout or the job reaper cannot kill it. A resumable read is an optional extra. It means new per-item persistence, because rows are held in memory today and written only at the end with --record (heldout.py:655-670, :772-774), and gate row 15 passes no --record (lib/gate_rows_b.py:356). (3) Record 1-minute load on every row as proof the condition held. Drop the fallbacks-by-load-band display, which would be empty under the bound. (4) Write the bound on the certificate as a stated condition of row 15, with RULE E1k's A/B figures above load 150 beside it (hedge-on fallback rate, rows held with one call silent). (5) If ruling 2 (which careful model to pin) ends on Haiku 4.5, add a real-load check on tuning rows of recall on rows held with one call silent, because the bound would otherwise hide a hold-cut loss. Under a Haiku 5.5 pin the bound only removes timeout noise. Build it as a named row-15 edit with red-then-green tests. The bound adds to the hedge fix that the 'fixed as tooling' exit requires; it does not replace it.

**Options:**

- **bound-in-evaluate (recommended, revised)** — The gate's row-15 read waits for load 40 or below before it starts and before each item. It refuses without spending sealed data if load never drops, and the certificate says the check was measured at load 40 or below, next to the real-load hedge numbers. This protects the last sealed read from an evening spike. The cost is that the certificate describes quieter conditions than most live prompts see (about a third to a half of live prompts arrive at load 40 or below), which is why the real-load figures go next to it.
- **only-if-fix-fails** — Wait for the second real-load A/B run, expected the next evening the load passes 150, and add the bound only if the hedge-on fallback rate is above 0.03 there. Free today, since the gate is weeks away. If the hedge passes, the gate reads at whatever load happens, and a 73-minute read still has about a 22% chance of hitting a load-150 spike. At 0.03 fallbacks, the 93-item stratum (regex-matched: re-asks the patterns catch) passes 85% of the time instead of about 99.7% at 0.01.
- **no-bound** — Row 15 stays as written and measures the router under whatever load the machine has, so the certificate describes real conditions. The risk: an evening burst during the read (E1j unhedged: 22 fallbacks in 105 rows above load 150) can fail the program's one remaining exit read on timeouts rather than labels. Every miss in the 2026-10-07 read was a timeout.

**Why the conviction moved:** The decision was filed at 76, the researcher argued 83 and the critique 77; my verdict is 78. Two of the researcher's headline figures were overstated. The 55% failure figure applied the regex-missed error rate to the regex-matched stratum, and the 15-17% figure assumed a whole read at 0.03 fallbacks, while measured hedge-on fallbacks were 0 in 150 rows below load 84. Corrected, the bound is tail insurance. The tail is not small, though: by python over idl.jsonl, a 73-minute read started at a random minute overlaps a load >= 150 sample 21.9% of the time (3,309 start minutes), and this is the program's one remaining exit read. Points against the bound: by my own join of user-prompt timestamps to idl.jsonl load (446 prompts, 2026-10-06 to 10-08), only 33% of live prompts arrive at load <= 40, and the median is 75. A bounded certificate therefore describes conditions most live prompts do not see, and under a Haiku 4.5 pin it hides a hold-cut recall loss. Points for it: router.py:842-846 shows a live 'unavailable' result still blocks research verbs and relays the certificate on a completeness ask, so the gate's scoring of timeouts as full misses overstates live harm; and method row 6 (REPORT.md:597) already asks for a load control on timing rows. Disclosure plus the real-load companion figures answer most of the representativeness objection, which nets a small rise. It stays at or below 90 because deferring to A/B run 2 and ruling 2 is free, and a reasonable operator could prefer a certificate taken at real load.

**Critique, resolved:**

1. Wrong stratum for 41/42. ACCEPTED. Recomputed with python comb(): at n=93 and f=0.03, the pass rate is 0.852 with perfect labels, 0.757 at the pooled 1/163, and 0.447 only under the mismatched 1/42. E1i confirms the regex-matched labels are effectively perfect: 'regex-matched missed 13, and its counted fallbacks are 13' (plan :1383-1385 on origin/main). The 55% figure is dropped.
2. The 0.03 headline. ACCEPTED. Hedge-on was 0/150 at load 39-84 (plan E1k run 1 table), and time at >= 150 is 0.076 (python over idl.jsonl => 0.076). I add that a 73-minute read overlaps a >= 150 sample 21.9% of the time (0.354 for a 3-hour read), so the insurance is real; its payoff depends on run 2.
3. Live prompts arrive at higher load. ACCEPTED and strengthened. My join: 446 prompts; 0.33 at <= 40, 0.229 at >= 150, median 74.9 (<= 400 chars: 309 prompts; 0.314, 0.197). The critique found 0.45-0.46; the filters differ but the direction is the same. This is answered by disclosure on the certificate, not by dropping the bound.
4. Haiku 4.5 pin hides recall loss. ACCEPTED as a condition, not a reversal. Hold-cut rates are 20/26/50% by load band (reask-haiku55-decision REPORT.md, timing trace section). Under Haiku 4.5 an unbounded read likely fails (E1i: 0.15 fallbacks), and a bounded read hides the loss, so the recommendation adds a real-load check, on tuning rows, of recall on rows held with one call silent if ruling 2 lands there.
5. The by-band display is empty under a per-item bound. ACCEPTED. Per-row load is kept only as proof the condition held.
6. The uncapped wait can be killed. ACCEPTED, with one correction. Rows are NOT recorded per item: they sit in memory and are written only at the end with --record (heldout.py:655-670, :772-774), and gate row 15 passes no record (gate_rows_b.py:356). A resumable read therefore needs new code, so the recommended design is a long finite cap with 'read spent, no verdict' and a detached launch, with resume optional.
7. Minor overreach. ACCEPTED. 695 routed items in 73 min is about 6.3 s per item (plan :1360-1363), and the hedge-on load maximum was 83.9.
8. Live fallbacks are cheaper than the gate scores them. ACCEPTED, verified at router.py:842-846 and :1290-1291. This supports the bound modestly.
