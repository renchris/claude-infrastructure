# H1: the CAS lane is enough at 15 landers (the contrarian case), and where it breaks

Scope: this argues against "a merge queue: one lander, batch + verify-once + bisect-on-fail". Every number comes from `~/.reso/land.log` v3 rows with `ts_start ≥ 2026-09-16T04:59Z`, read at about 05:05Z on 09-23. Code is cited from `origin/main` @ `f12e70559`, and the simulations from `/tmp/rla/wave1/h1/`. Empirical claims are marked **[E]** and modelled ones **[M]**.

## Verdict

- **The four listed fixes are not enough.** With the token honoured, ref-lock treated as a race and ROUNDS_MAX/backoff retuned, the lane still falls into congestion collapse. **[M]** It starts falling behind at an offered rate Λ ≈ 10–12 lands/h (N≈10 at a 45-min cadence). At N=15 it delivers 2.9 lands/h of the 18.8 offered, with code-land p50 ≈ 8 h. Today's lane (C0) behaves the same.
- **The case does hold at N=15, but only with two fixes the brief did not list:**
  - **(5)** Take the existing `cc-sem reso-land` K=1 slot *before* the fetch and hold it through the push, keeping it across a lost push.
  - **(6)** Carry the suite/tsc verdict across a rebase whose incoming commits are disjoint from the diff.

  With these, at N=15 and a 45–60-min cadence, CAS beats a queue on blended latency by 10–18%. **[M]** The 60% of lands that are non-code keep p50 14 s, where a queue gives 39–86 s. Code lands pay +4–23% at p50 and +16–42% at p90.
- **Break-even (blended mean latency, all lands): Λ\* ≈ 24 lands/h with Poisson arrivals, and 25–28/h with synchronized wave dispatch.** That is N\* ≈ 18–20 at a 45-min cadence, 12–17 at 30 min, and 24–27 at 60 min. **[M]** With wave-6-style coupled work (q=0.72) it drops to Λ\* ≈ 19–21/h, or N\* ≈ 15 at 45 min. **At 15 sessions × 30-min cadence the queue wins.** On code-land p90 alone the queue already leads from N≈10.
- **At N ≤ 20 the queue's win comes from serialization, not batching.** The simulated mean batch is 1.23 at N=15 and 1.42 at N=20, which confirms the "modal batch is one rider" record in `learnings.md:1765-1768`. **[M]** The same serialization is available inside the lane from the slot that already exists.

## (a) The counterfactual verify window: today minus the duplicate pre-push suite

Code rounds that reached a push, n=66 **[E]**:

| stage (s) | p50 | p90 | p95 | mean |
|---|---|---|---|---|
| reconcile | 1 | 2 | 2 | 1 |
| tsc | 47 | 121 | 138 | 57 |
| sem_wait (reso-land K=1, **inside** the window) | 0 | 140 | 187 | 44 |
| union suite | 148 | 203 | 215 | 150 |
| push, including the hook's full `pnpm test:unit` | 167 | 251 | 277 | 183 |
| **V today** | **419** | **626** | **688** | 436 |
| hook-suite share (push − non-code push p50 of 4 s) | 163 | 247 | 273 | 179 |
| **V_cf1**: hook suite removed, push = non-code median 4 s | **225** | **398** | **451** | 257 |
| V_cf1, bootstrap with push drawn from the non-code distribution (p50 4, p90 27) | 241 | 412 | 482 | 266 |
| **V_cf2**: also sem wait moved out of the window | **200** | **300** | **339** | 213 |
| slot hold under fix (5): reconcile + suite + push, tsc outside | – | – | – | 158 |
| carried retry: reconcile + push | – | – | – | 14 |

- **P(no competing land during V) = e^(−λV) falls below 0.5 at λ\* = ln2/V.**
  - Today: 6.0/h at the p50 window and 5.9/h over the whole distribution.
  - V_cf1: 11.1/h at p50, 6.3/h at p90, 10.3/h over the distribution.
  - V_cf2: 12.5/h at p50, 12.1/h over the distribution.
- **The loss mechanism is exactly "another land during V".** Windows were rebuilt backward from `ts_end`. All 75 won rounds had 0 competing lands in the window, and all 25 lost rounds (19 non-fast-forward, 6 ref-lock) had at least one. **[E]** (`a3.py`)
- **The lane's own slot manufactures losses.** P(loss | sem_wait>0) = 19/24 = **0.79**, against P(loss | sem_wait=0) = 6/32 = **0.19**. **[E]** Mechanism check (`a10.py`):
  - In 8 of the 19, the winner was the slot holder immediately before us (its suite ended within ±20 s of our acquisition).
  - In 10, an earlier code lander's push phase (its hook suite, 154–241 s) overlapped our window.
  - 1 was a non-code land.

  Cause: reconcile's `git fetch` (`ship-reconcile.sh:78`) runs before tsc and before `run_suite` takes the slot (`ship-land.sh:840-845, 548`), so the slot queue sits inside the window. As a result, plain Poisson under-predicts today's losses: 0.32 predicted against 0.45 observed, and 0.47 against 0.73 in the top bin.

**Arrival rates [E]:**
- **Wave-6 peak:** 14 lands in 2.42 h (09-23 02:45–05:10Z) = **5.8/h**; 09-22 18:45–20:20Z = 3.2/h.
- **Busiest hour of the week:** 10 lands in 60 min (8 in 30 min) from 09-21 04:51Z.
- **Concurrency:** at most 5 distinct landers per hour and at most 4 attempts in flight.
- **Code-round loss rate in the 02:45Z window:** 17/28 = 0.61.
- **Target load:** 15 sessions at one land per 30–60 min is Λ = 15–30/h, or **2.6–5.2× the wave-6 peak**.

At 45 min (Λ = 20, competing λ = 18.7/h), P(no competing land):

| window | P(no competing land) |
|---|---|
| today, p50 V | 0.11 |
| V_cf1 | 0.31 |
| V_cf2 | 0.35 |
| slot hold under fix (5), only non-code lands can compete (λ = 11.2/h) | 0.61 |
| carried retry | 0.93 |

**Census corrections [E]:**
- 2 rows are `exit 0, rounds 0`: dry-runs logged as `landed`. One head, `85d23a404`, is not on origin/main. True lands = 75, not 76.
- Code units only: p50 540 s, p90 3282 s, p95 4011 s. The shared p50 of 74 s is dominated by the 45 non-code units (p50 19 s).

## (b) Model: P(CAS loss), rounds and latency against N

**Closed form (Poisson competitors; ignores the slot).**
- p(λ) = E_V[e^(−λV)] over the empirical V.
- E[rounds] = 1/p, and P(exhausted at R=5) = (1−p)^5.
- With carry: E[L] = E[V1] + (1−p1)·R, where R = [(1−q)E[Vc] + q·E[V1]] / [1 − (1−q)(1−pc) − q(1−p1)].
- λ = Λ(N−1)/N, with Λ = 60N/Tc per hour.

Fitted inputs: f_code = 0.40 (30 of 75 units); the V distributions in (a); q = 0.42/0.72 and q_nc = 0.17 (see fix 6). Results (`analytic.py`) **[M]**:

| scenario | Λ/h | today: P(loss) · E[rounds] · P(exh5) | V_cf1: P(loss) · E[rounds] · E[L] | V_cf2 + carry, q=.42/.72: E[L] |
|---|---|---|---|---|
| wave-6 peak | 5.8 | 0.42 · 1.7 · 0.01 | 0.27 · 1.4 · 350 s | 237 / 256 s |
| N=15 @60 min | 15 | 0.79 · 4.7 · 0.30 | 0.60 · 2.5 · 636 s | 283 / 356 s |
| N=15 @45 min | 20 | 0.87 · 7.5 · **0.49** | 0.70 · 3.3 · 839 s | 303 / 409 s |
| N=15 @30 min | 30 | 0.94 · 18 · 0.75 | 0.82 · 5.6 · 1415 s | 334 / 511 s |

**Discrete-event simulation.** It adds the K=1 suite slot, measured flake reds and re-attempt gaps, and invariant 6 for the queue. `sim3.py`/`sim4.py`; 3 seeds × 195 h per cell.
- **Calibration:** C0 at N=5 / 45 min gives Λ 5.8/h and first-round loss 0.44. Observed: 5.8/h, and 0.45 for the week (0.61 in the peak window).

Configurations:
- **C0:** today.
- **C2:** the four listed fixes.
- **C7:** C2 + fix 5 (admit → fetch → suite → push under the slot, kept on a lost push; tsc outside the slot and re-run only after a non-disjoint move) + fix 6 (carry).
- **Q:** one lander, batch ≤ 10, verify once. A red ejects every rider (invariant 6, `learnings.md:2567`).

Poisson arrivals, Tc = 45 min. Cells are code p50 / p90 (s); nc = non-code p50 / p90; blend = mean over all lands **[M]**:

| N (offered Λ/h) | C0 today | C2 listed fixes | C7, q=.42 | C7, q=.72 | Q queue |
|---|---|---|---|---|---|
| 5 (6.3) | 713 / 1894 | 266 / 834 | 224 / 545 · nc 14/71 · blend 140 | 226 / 550 · blend 137 | 226 / 534 · nc 19/176 · blend 153 |
| 10 (12.6) | 3268 / 14153, delivers 7.1/h | 1012 / 9677, delivers 9.0/h | 268 / 668 · blend 163 | 268 / 651 · blend 164 | 253 / 545 · nc 34/235 · blend 177 |
| **15 (18.8)** | **collapse: 2.9/h delivered** | **collapse: 2.9/h** | **319 / 805 · nc 14/80 · blend 189** | 346 / 916 · blend 211 | **272 / 566 · nc 62/348 · blend 211** |
| 20 (24.5) | collapse | collapse | 416 / 1034 · blend 240 | 482 / 1221 · blend 273 | 291 / 606 · nc 99/405 · blend 242 |
| 25 (29.4) | collapse | collapse | 659 / 1610 · blend 358, slot 0.81 | 837 / 1946 · blend 432 | 313 / 652 · blend 277 |

Blended mean, C7 (q=.42) against Q:

| cadence | N=10 | N=15 | N=20 | N=25 |
|---|---|---|---|---|
| Tc=30, Poisson | 184 vs 207 | 261 vs 247 | 421 vs 295 | – |
| Tc=60, Poisson | – | 166 vs 193 | 196 vs 215 | 235 vs 244 |
| Tc=45, synchronized waves | – | 206 vs 244 | 254 vs 266 | 331 vs 292 |
| Tc=30, synchronized waves | – | 247 vs 270 | 366 vs 311 | – |

At N=30 / Tc=60 (Poisson) it is 312 vs 264. The wave-dispatch model (`sim4.py`) has every session release on a common boundary and land in U(0.3,1.0)·W; it hurts the queue's non-code lands more than it hurts CAS.

With the band fix (flake 0.10 → 0.03) at N=15 / 45 min: C7 is 291/687, blend 171, against Q 262/471, blend 196.

## (c) The targeted fixes and their measured effects

| # | fix | where | measured effect [E] | modelled effect [M] | status |
|---|---|---|---|---|---|
| 1 | Pre-push hook honours the tree token | `pre-push:130-150` runs `pnpm test:unit` unconditionally; token written at `ship-land.sh:782-811`, called at `:622` | V p50 −163 s (419 → 225–241), p90 626 → ~400. Removes 6 hook reds a week, **0 of them caused by the diff**: all 6 patches later landed with the identical patch-id, and tree `b7a3bdf32` went red at 19:17Z then green at 19:33Z unchanged. Hook reds plus their re-attempt gaps = 12.6% of all unit-seconds. | Necessary but **not sufficient**: C1 still collapses at N=15. | Not built. W3b honours only `mode=full` (`learnings.md:2682`), while union is the default. The data-blob scope arm looks covered (the always-run set lists `venueContentBounds`/`venueSvgData`), but W3b arm 5 must prove it. |
| 2 | "cannot lock ref … but expected" counts as a race | `ship-land.sh:894` | 6 of 25 losses (24%) exited 9 with "NOT by a race". Re-attempt gaps were 10–44 s; 7.2% of unit-seconds, mostly the lost round's verify that a retry pays anyway. | Small (N=5 p90: 864 → 834). Its value is an honest message. | **Landed during this research:** `c8eed1e25`, 2026-09-23T05:20Z |
| 3 | Declare the test band so load stops timing out vitest workers | `vitest.config.ts:55` (`VITEST_TIMEOUT_FACTOR`) | 15 red verdicts; 13 later landed byte-identical. 2 were trunk-state: `presubmit-always.test.ts` broken on trunk by a suite-less land, which the `ship-land.sh:629` trigger allows. 1 looks real. Reds cost 24.6% of unit-seconds. Union-suite time tracks load (r=0.58) and not files selected (r=0.02). | Flake 0.10 → 0.03: C7 at N=15 goes 319/805 → 291/687. **Upper bound**: I cannot tell from `land.log` which reds were timeouts. | Not built |
| 4 | Retune ROUNDS_MAX and backoff | `ship-land.sh:43, 933` | 1 exhaustion all week (`sec-w6-w4a7b-deaction`, 5 rounds, 39.6 min). A 1–4 s jitter is under 1% of V: the losses come from the window, not from synchronized retries. | None on latency. With carry, cheap rounds make a higher ROUNDS_MAX safe. | Not a lever |
| 5 | **Take the reso-land slot before fetch and hold it through push, keeping it on a lost push** | move the `cc-sem` wrap (`ship-land.sh:548`) from around `run_suite` to around reconcile → push | Removes the 0.79-vs-0.19 slot effect. Code-vs-code races become impossible; only non-code lands (window p50 14 s) can move trunk under a holder. | **This is the fix that prevents collapse.** C2 → C3 at N=15 / 45 min: 2.9 → 14.1 lands/h delivered. | Not built. Needs `CC_SEM_WAIT_RESO_LAND` (300 s, `cc-sem.sh:97`) raised, or refusal turned into a re-queue. |
| 6 | **Carry the verdict across a disjoint rebase**. This covers "rebase-only re-verify", "token carry" and the fast path. | new rule: token(T') := token(T) when T' = rebase(T, incoming) and incoming is disjoint from my diff's module closure (no escalate file, no shared file) | From a regex import graph of origin/main (1,933 files, 4,849 edges; `graph.py`, `a7.py`): **58%** of land pairs within 60 min are fully disjoint (q=0.42). Among the 25 wave-6 lost rounds only **28%** are (q=0.72): 12 share tests, 4 hit an escalate file, 2 are tsc-only. 5 of 6 losses caused by non-code lands were disjoint (q_nc=0.17). File overlap was 2/25, both on `tests/presubmit-always.txt`. | C3 → C4 at N=15: p50 1928 → 423, p90 5981 → 1324. Under fix 5, only the non-code (q_nc) and tsc-recheck roles matter. | Not built; carries a soundness risk (see (e)) |
| 7 | Non-code fast path | already the case | Non-code window p50 14 s; 1 loss in 48 rounds. The fix is to keep them *out* of any serialization. | C8 (non-code also takes the slot) raises their p50 from 14 to 53 s at N=15 and loses on blend. | Keep as is |

## (d) What a queue costs that CAS does not

| cost | evidence |
|---|---|
| Non-code lands (60% of lands) get slower | **[M]** At N=15 / 45 min, non-code p50/p90 goes 14/80 s → 62/348 s. Under waves at N=25: 15 → 205 s. A queue fast lane would race the queue's own pushes and need fix 6 anyway. |
| A single point of failure for 100% of lands | **[E]** The last central serialization point in this repo, the land-lock, recorded a 47-hour wedge, 27 steals of a live holder, 153 overlapping holds and a 28-min p95 wait (`ship-land.sh:14-24`; `learnings.md:1812`). Under CAS a stuck session blocks only itself. |
| Sessions stop owning their outcome | Invariant 4 (`learnings.md:2565`): "Landing stays free, continuous, agent-driven and SYNCHRONOUS. No merge queue…". A queued land outlives the enqueuing session: context limits, `/clear` and crashes all leave a red rider with nobody to fix it. |
| Bisect conflicts with invariant 6 | "never re-roll a red until it comes up green" (`learnings.md:2567`). With 14 of 15 reds not caused by the diff **[E]**, a bisect whose halves pass is mostly a re-roll. Honest queues therefore eject the whole batch, which at a mean batch of 1.2–1.6 is small but not zero. |
| Batching buys little at this scale | **[M]** Mean batch 1.23 at N=15, 1.42 at N=20, 1.7–2.2 at N=25–30. The queue's advantage is the absence of races, not amortization. |
| Integration surface to rebuild | Reconcile's migration strategy (cherry-pick when origin gained migrations, `ship-reconcile.sh:163-165`); the per-session drop confirmation `SHIP_CONFIRMED_DROP` (`ship-land.sh:~405-424`); content-verify, backup refs and the drizzle mutex. Every one needs a queue-side twin. |
| Operator visibility | Today one `land.log` row per attempt carries per-stage timings; that is what made this analysis possible. A queue needs new telemetry: depth, batch composition, rider attribution. |

## (e) Where the contrarian case fails

1. **The brief's fix list does not save the lane.** C2 collapses between N=10 and 15 at a 45-min cadence (N≈10 at 30 min, ≈15 at 60 min). The case depends entirely on fixes 5 and 6, which are unbuilt; fix 6 is new code.
2. **The code-land tail is worse from N≈10.** C7 p90 is +23% at N=10, +42% at N=15 and +71% at N=20 (45 min, Poisson). A code session waits noticeably longer than it would in a queue.
3. **The slot is a hard ceiling for CAS and only a soft one for a queue.** CAS needs at least one suite per code land (plus re-verifies); a queue needs one per batch. When slot use passes about 0.7–0.8 (Λ ≈ 28–30/h), C7 latency runs away while the queue's batches simply grow.
4. **Fix 6 has a soundness risk.** The import graph was built with a regex; it misses dynamic imports and fs reads. The always-run set (159 specs) exists precisely because some test inputs are not in the module graph. A wrong carry puts a red tree on trunk, which the post-land verifier then catches; deploy stays gated (R2).
5. **The prior rejection's premise no longer holds.** "With the gate off the land path there is nothing to batch" (`learnings.md:1767-1768`) was written before W3a put a 151-s p50 union suite back on the land path. Neither design meets R1 (p50 ≤ 60 s) for code lands. CAS meets it only for non-code lands.
6. **Coupled work pulls the break-even down.** With q=0.72 it falls to N\* ≈ 15 at a 45-min cadence.

**Break-even stated plainly.** On blended mean latency, Λ\* ≈ 24 lands/h (Poisson) to 25–28/h (waves). That is **N\* ≈ 18–20 at a 45-min cadence**, 12–17 at 30 min and 24–27 at 60 min. It is lower (≈15 at 45 min) when sessions work on coupled surfaces, as wave 6 did. On code-land latency alone, the queue is ahead from N≈10.

## Alternatives considered

- **Raise the reso-land slot to K=2.** Ruled out as unmeasurable here. Suite time rises with load (p50 106 s at load <60, 179 s at ≥150), and the box sits at 200–270.
- **Full mutex, where non-code lands also take the slot (C8).** It hurts 60% of lands and loses to C7 on blended latency once N ≥ 15.
- **More ROUNDS_MAX or backoff.** No effect, as shown in fix 4.

## Adversarial pass

These were checked with real calls:
- **"The slot effect is just busy periods."** The mechanism check in (a) attributes 18 of the 19 slot-wait losses to the slot or the hook-suite overlap; the other 1 was a non-code land.
- **"The hook reds were real catches."** All 6 had identical patch-ids when they landed, and one flipped red to green on an identical tree. I cannot separate flake from trunk-state for the other 5.
- **"Poisson arrivals flatter CAS."** Under synchronized waves, CAS's blended edge grows, but its code-land p90 stays 23–32% behind the queue.

What remains unmodelled:
- Load feedback: 15 sessions mean more load and longer stages, which hurts CAS more.
- The sim's queue is idealized: no daemon downtime and no handoff cost.
- f_code is held at 0.40.

## Reproduction

`/tmp/rla/wave1/h1/`:
- Census and validation: `a1`–`a10`.
- Closed form: `analytic.py`.
- Import graph: `graph.py` (pickled to `graph.pkl`).
- Simulations: `sim2.py`, `sim3.py` and `sim4.py` (waves), with outputs in `s2_*`, `s3_*` and `s4_*`.

All reads of reso were `git show`/`log`/`cat-file`; nothing in reso was modified.
