# reso landing architecture at 15+ concurrent landers — bottlenecks, target design, phased plan

**Date:** 2026-09-22 (measurement window closes 2026-09-23T04:59Z) · **Status:** research. This is a
design, not an implementation; nothing in reso was edited · **Evidence:**
`reso-landing-architecture-2026-09-22/`. It holds the census and model scripts with their output,
and the nine per-axis reports in `reports/` that this synthesis rests on. Code citations are reso
`origin/main` **754a4693d** unless marked. `c8eed1e25` landed during the research and shifts
`ship-land.sh` lines ≥ 889 by +4.

**The operator's question, verbatim (2026-09-22):** *"Do we need a dedicated Opus 5.5 max reasoning
/handoff research session to investigate and come back with the 100th percentile absolute perfection
implementation of the architecture and workflow of our landing to origin main? We expect to have 15+
concurrent high-volume Claude Code sessions close to all times (optimally), so we need to not be
congested/held-up/blocked landing when there are multiple commits and pushes being attempted or
queued. What are the bottlenecks and how can we eliminate or alievate them?"*

**Scope (frozen):** a design document answering that question for reso-management-app's land path:
measured bottlenecks, the target architecture, and a phased implementation plan with a Phase 0.

---

## 1. The answer

**reso's land path congests because verification runs inside the push's compare-and-swap window,
and runs there twice.** Each sibling land throws away minutes of the loser's work, and the loser
repeats all of it.

- A code land's window (fetch → reconcile → typecheck → admitted union suite → `git push`, whose
  pre-push hook runs the **entire** unit suite again) is **7 minutes at the median**.
- In a busy quartile the trunk advances every **2.5–7 minutes**.
- Past about **6 concurrent landers**, adding landers makes throughput *fall*. That is congestion
  collapse, not a slowdown, and wave 6's 75–82-minute units were its visible edge.
- Half of all landing time last week went to attempts that did not land: **4.8 h failed against
  4.9 h succeeded** (H2).

**The fix is structural, and no tuning of the current lane reaches 15.** The brief's four listed
fixes still collapse at N≈10–15 in both independent models built for this document (§4). The
design that does reach it:

> **Verify each change once, commit through one short serialized step, and batch that step when it
> is busy.** Every land takes one turn to move trunk (non-code lands first, code lands in order).
> Nothing another session does can invalidate a verification in progress, and a lost race stops
> costing a re-verification. At 15+
> high-volume sessions, one elected *combiner* runs that turn for every ready change at once: one
> verification, one fast-forward push, bisect if red.

Model results (landsim v2, after the wave-2 red-team corrected v1). Each cell assumes a 30-min
per-session land cadence ("high-volume") and wave-peak background load, and applies E's measured
interference law. Phases 2–4 include Phase 2's keying of the shell-out specs (suites at 0.6×).
Re-derive: `reso-landing-architecture-2026-09-22/run_model.sh` (`scenarios.py keyed`).

| N concurrent sessions | Today, as shipped | **Phase 2**: serialized lane | **Phase 3**: combiner, full suite on any moved candidate | **Phase 4**: + re-check pruning |
|---|---|---|---|---|
| 8 · lands/h · **p95** | 3.4/h · **431 min** | 13.8/h · **7.3 min** | 14.3/h · **9.7 min** | 14.8/h · **6.2 min** |
| 15 | 1.8/h · **collapsed (21 h)** | 25.0/h · **16.6 min** | 25.4/h · **13.4 min** | 26.7/h · **8.3 min** |
| 25 | 1.2/h · collapsed | 29.2/h · 45.7 min (at its ceiling) | 38.6/h · **18.0 min** | 42.2/h · **13.5 min** |
| 40 | 1.3/h · collapsed | 29.5/h · 98.9 min (at its ceiling) | 54.6/h · **33.4 min** | 57.3/h · **29.7 min** |
| non-code lands at N=15 (p50 / p95) | fast, but their sessions sit in collapsed code lands | 1.5 / 3.6 min | 0.4 / 3.9 min | 0.2 / 1.5 min |
| verification core-min per landed change, N=15 | ~159 | 3.8 | 6.4 | 4.3 |

At a 45-min cadence, Phase 2 alone holds N=15 at a **9.8-min** p95. There it beats the unpruned
combiner (12.0), which pays for Phase A *and* a re-verification whenever trunk moved. N=40 at a
30-min cadence offers ~80 lands/h, and every design here tops out near 55–58. That is **this Mac's
verification capacity**: one full suite per code change, ~42–49 clean verifications/h (E). Past it,
the lever is per-change cost (Phase 5), not coordination.

**Recommendation (conviction 86%):**

- **Phase 2 now.** It takes days and needs no daemon:
  - one full suite per land instead of two, which the pre-push hook honours;
  - the 23 shell-out specs keyed on their declared inputs;
  - every land taking a FIFO turn from before its fetch through its push, with non-code lands
    jumping the queue.

  It moves today's scale (N≈8) from a 48-min measured p95 to about 7 min. It carries N=15 at a
  45-min cadence. Its ceiling is ~29 lands/h.
- **Phase 3 when the measured peak passes ~20 lands/h** (the lane at 70% of its ceiling). That is
  the combiner: group commit behind the same turn, which removes the ceiling.
- **Phase 4 once pruning is proven in shadow mode**, to cut the combiner's re-verifications.

§8 says what would move the conviction and lists the **four standing reso rulings** this plan asks
the operator to amend (R1–R4). None blocks Phase 1.

---

## 2. Measured baseline (7 days, 2026-09-16T04:59Z → 2026-09-23T04:59Z)

Source: reso's own telemetry `~/.reso/land.log` (v3 rows). There is one row per landing *attempt*,
written by `scripts/ship-land.sh`'s EXIT trap, so killed and refused attempts are counted, not only
survivors. Re-derive:
`python3 reso-landing-architecture-2026-09-22/land_census.py --since 2026-09-16T04:59:00Z --until 2026-09-23T04:59:00Z`.

| measure | value |
|---|---|
| landing attempts / landed | 108 / 76 (75 true lands: one was a dry-run logged as `landed`, H1). 31 carried code |
| **per-unit latency** (first attempt → landed) | all units p50 **74 s** · p90 **23.6 min** · p95 **48.1 min** · max **82.3 min**; **code units p50 9.0 min · p95 66.9 min** (H1) |
| units needing >1 attempt | 18, which spent **5.8 wall-h** before their landing attempt began |
| waste | failed attempts **4.8 h** of box time vs successful **4.9 h**. Waves of 5–12 distinct landers failed **47–60%** of attempts; single-lander waves ~0–5% (H2) |
| **verify window per code round** (reconcile + tsc + admission + suite + push) | p50 **419 s** · p90 627 s · p95 694 s |
| **inter-land gap on trunk** | p10 **154 s** · p25 **429 s** · p50 752 s |
| stage medians (code rounds) | reconcile 1 s · tsc 46 s · admission wait 0 s (p90 152 s) · **union suite 150 s** (full-mode 215 s, n=9) · **push 167 s** |
| push on non-code rounds (hook runs no suite) | p50 **4 s** |
| rejected pushes | 19 client non-fast-forward (retried) · **5 GitHub ref-lock races filed as "not a race" (exit 9)** · 6 pre-push unit-test failures · 3 other hook refusals · 2 push timeouts |
| the full unit suite | 381–399 files, ~4,900 tests; 99–243 s wall, depending on concurrent load (D) |
| what the suite's time is made of (D) | the always-run set is 159 of 419 specs but **92% of test-phase time**. **23 shell-out specs that test bash scripts are 53%**; `ship-land.test.ts` 64 s, `worktree-pool-ownership.test.ts` 45 s and `mem-leash.test.ts` 33 s are 40% of the suite on their own. 48 DB-fixture specs take 117 s (each fixture applies all 95 migrations); jsdom takes 20 s. **Union time does not move with diff size** (p50 144 / 148 / 157 s for <10 / 10–30 / 30+ selected files) |
| what slows a suite (E) | **each other concurrently running suite adds +45 s** to a union suite and **+49 s** to the hook suite (R² 0.36 → 0.73 and 0.56 → 0.84 with that term). Ambient load1 costs 0.2–0.3 s/unit and is indistinguishable from zero below load1 100. The best throughput per unit of latency is at **~2 concurrent suites** |
| admission lanes (B1, `cc-sem.sh:86-101`) | the land's union suite: `reso-land` **K=1** (box-wide serial, unordered polling, refusal at 300 s). The hook's full suite: `general` **K=3**, shared with `next build`, `design:gate` and every session's `test:unit` |
| in-flight concurrency (30-s samples) | max **4** simultaneous attempts, mean 2.0 when busy; busiest hour 14 attempts. N=15 is therefore a projection, and §4 is a model |
| trunk verification after a land (B2) | **effectively none**: reso's `postland-verify.sh` has no scheduler (V3 W4a unbuilt): 3 stamps against 77 lands, the newest green 71 h old. The pre-push hook's full suite is reso's only full-suite check before trunk |

---

## 3. The bottlenecks

Each row gives the mechanism with a file:line, its measured price over the window, and how it binds
at N=15.

| # | Bottleneck | Mechanism | Measured price (7 d) | At N=15 |
|---|---|---|---|---|
| **B1** | **Verification inside the CAS window** | Every round verifies (tsc `ship-land.sh:632-653`, union suite `:659-669`) and only *then* pushes. The push succeeds only if trunk did not move since the round's fetch (`:889-892` → rc 99, 5 rounds `:43`). A lost round repeats *all* of it. Every one of 75 won rounds had 0 competing lands inside its window, and every one of 25 lost rounds had ≥1 (H1) | 24 lost-race rounds = **3.4 wall-h**; 18 units needed retries (**5.8 wall-h**) | **Collapse.** Model v2: today's lane lands 1.8/h against ~28/h offered. H1's independent model shows the same between N=10 and N=15 |
| **B2** | **The same tree verified twice, and the second run sits inside `git push`** | `pre-push:130-150` runs the full `pnpm test:unit` on any `src\|lib\|replicache` TS change. The tree token `ship-land.sh:771-811` writes **has no reader**: the hook-side skip (V3 "W3b") was never built. As designed, it honours only a `mode=full` token (reso `docs/infra-deploy/learnings.md:2682`), and 47 of 50 tokens on disk are `union`. Git runs a pre-push hook **after** reading the remote ref and **before** sending the update, and it runs it **even for a push it already knows is doomed** (reproduced, §3.1). The always-run set is 92% of suite time, so the round pays for two nearly full suites | 62 code rounds × mean **179 s** = **3.1 wall-h**; 43% of the median window. 18 non-fast-forward rounds each still paid 114–299 s of hook suite (H2) | Every code land; 0 of 32 code-land pairs with overlapping push windows both landed (H2) |
| **B3** | **Admission wait sits inside the window** | Reconcile's `git fetch` (`ship-reconcile.sh:78`) runs *before* `run_suite` takes the `reso-land` slot (`ship-land.sh:547-548, 840-845`). Whatever the slot queue costs is window time | **P(round lost \| waited for the slot) = 0.79 vs 0.19 without a wait** (19/24 vs 6/32); 18 of 19 attributed to the slot holder or an overlapping hook suite (H1) | Grows with every added code lander |
| **B4** | **Admission is split, unordered and partly dead** | `reso-land` K=1 bounds the union suite. The hook's suite is admitted in `general` K=3, so the box runs 1 union + up to 3 full suites at once. No FIFO: a 299-s waiter can lose to a newcomer and exit 10. The memory floor is discarded (`cc-sem.sh:271 … \|\| true`). Much of the box's load is *unadmitted*: `tsc` (2.3 GB each), claude-infrastructure's own land lane (633 lands / 112 gate-hours in the same 7 days), Chrome helpers (H2 row 5; E) | admission wait **0.9 wall-h**, p90 152 s; `reso-land` held **65.6%** of samples in the 05:00–05:10Z burst (B1); 3 exit-10 refusals | Even the recommended design degrades past N=25 at K=1 (p95 32 min) against 18 min at K=2 (§4.4) |
| **B5** | **Race misclassification** | GitHub's server-side refusal `cannot lock ref … is at X but expected Y` fell to exit 9 "REJECTED and NOT by a race". **Fixed on trunk during this research** (`c8eed1e25`, verified by ancestry) | 5–6 of 15 exit-9s in the window | Closed |
| **B6** | **The push's clock is shorter than its hook** | `PUSH_TIMEOUT=120` (`ship-land.sh:45`) wraps a hook suite whose p50 is ~163 s. Exit 12 is TERMINAL (`:901-907`). Sessions survive only by exporting `LAND_PUSH_TIMEOUT=900` because a rules lesson says so (H2 row 2) | 3 exit-12 rows at exactly 120 s, one killed *after* a green hook | Moot once B2 is fixed |
| **B7** | **Nondeterministic verification** | Every fixed-port and fixed-path hazard is **already fixed** (every socket suite binds port 0; `/tmp` literals are pid-scoped; `tmpdir()` goes through `mkdtemp`). One shared-state touch remains: `postland-verify.test.ts:82,96` omit `POSTLAND_TIP_REF` and fetch the shared `origin/main` ref (C). **What remains is load**: neither `run_suite` nor the push sets `CI=true` or `VITEST_TIMEOUT_FACTOR` (`vitest.config.ts:9,54-55`), so there are no retries and the timeouts are 15 s. The lane maps *any* red to exit 6, with no "timeouts only ⇒ non-verdict" arm (H2 row 4) | 15 verification reds. **5 went green on the identical tree** next attempt; 8 of 9 land-suite reds were `scripts/__tests__` shell-out specs at load 140–266. Of the 6 reds where the union passed and the hook failed: 3 were the old fixed-port bug, 1 looks like a load flake, 2 are unattributable, **none a demonstrated selector miss** (C, D) | A false red costs a whole attempt today. In any batching design it poisons a batch, so the flake rate is a first-class model input (§4.4) |
| **B8** | **Exit codes collide across scripts** | `ship-reconcile.sh`'s codes pass through unchanged (`ship-land.sh:843`). Reconcile **6** (a sequence that *stopped* with no conflicted paths; it prints a false "commit already upstream", `ship-reconcile.sh:247-259`) is logged as `statics-red`. Reconcile **7** ("never started, safe to retry") is logged as `escalation-parked`, and the `/ship` table tells the agent it is a "**destructive migration PARKED — operator decision**" (`ship.md:68-69`) (B1 §2.3) | 1 false "already upstream" in the window: the same 4 commits rebased cleanly onto the same base 21 s later. The likely trigger is a mid-sequence `index.lock` from session tooling that runs `git status` without `--no-optional-locks` (§9) | Grows with every session whose tooling polls git |
| **B9** | **The land verifies code its diff cannot reach** | 53% of suite time is shell-out specs of bash scripts, run on every code land although a `src\|lib\|replicache` diff cannot affect them | **140–170 s per code land** avoidable by keying those specs on their declared inputs (D) | Sets the floor of every design's commit step |
| **B10** | **Nothing verifies trunk after a land** | reso's `postland-verify.sh` has no scheduler, verifies only the tip at kick time, and has no bisect (`:553-563`) (B2) | 3 stamps / 77 lands; 111 commits behind the last green | Forbids simply deleting the hook suite (§5.6 C11). Separately it threatens `/deploy` (§9) |
| **B11** | **No unit-level telemetry** | A land.log row is one *attempt*. Nothing links the attempts of one change, so the operator's number, p95 unit latency, is computed nowhere. This document joins attempts on branch name | — | Needed to know when the other rows are fixed |

### 3.1 The push-protocol mechanism behind B2, reproduced

A throwaway pair of local repositories (no network, nothing of reso's touched), git 2.54.0:

- **Case 1:** the remote moved before the push started. Git already knew the push would be rejected
  ("fetch first"). **The pre-push hook ran anyway.** In reso that is a full `pnpm test:unit` spent
  on a push that cannot succeed.
- **Case 2:** a sibling pushed *while the hook ran*. The server refused with `cannot lock ref
  'refs/heads/main': is at 1e29… but expected 5f10…` / `[remote rejected] (incorrect old value
  provided)`, exactly B5's wording.

So a pre-push hook's duration is not just latency: it is **race-window width**. A design that leaves
a multi-minute hook inside `git push` leaves the race open however the rest is tuned.

---

## 4. The model

### 4.1 What is modelled

`landsim.py` is a discrete-event simulation: pure Python, fixed seeds, 48 simulated hours × 3 seeds
per cell.

- **Sessions.** N sessions work for Exp(T_work) (30 min by default = "high-volume"), then land one
  change (55% touch code), blocked until it resolves.
- **Failures.** 5% of code changes carry a real defect, and the author fixes it in Exp(10 min). A
  flaky red occurs at 3% per suite run and re-invokes after 60 s.
- **Stage laws.** Fitted from land.log: `tsc=28+0.23L`, `union=121+0.27L`, `full=143+0.36L` at
  background load L. **Plus E's measured interference**: every *other* concurrently running suite
  adds +45 s to a union suite, +49 s to a full suite and +11 s to tsc. v1 of this model charged
  concurrency only through load1 (~1 s per suite). The wave-2 red-team showed that flattered the
  combiner, and v2 corrects it (§4.4).
- **Phase A runs the full suite** (union ≈ full in cost, D/E). Its verdict is then a `mode=full`
  record for the exact tree, so a lone ticket landing on the trunk it was verified on needs no
  second run. v1 let the combiner skip its suite in that case while Phase A had run only the union:
  a second flattering bug the red-team found.
- **Non-code lands jump the queue** in the serialized lane and the combiner (§5.4), and code and
  non-code latencies are reported separately.
- **Policies:**

| Policy | What it is |
|---|---|
| **P0** | Today: optimistic CAS, 5 rounds. Each round runs tsc + admitted union suite + the hook's full suite inside the push |
| **P1 / P1f** | P0 with the waste removed: the hook honours the token, a doomed push is skipped, ref-lock = race. P1f runs one *full* suite in place of union + hook. A lost round still re-verifies |
| **P2** | P1 plus cheap revalidation of a lost round (incremental tsc, and a partial suite only when the incoming delta intersects the change's tests, probability 1−(1−q)^k) |
| **PS** | **Phase 2's serialized lane**: every land takes one turn from before its fetch through its push, and non-code lands are served before waiting code lands. Code runs tsc + one full suite inside it |
| **P3** | Verify in parallel (Phase A), then commit through one FIFO critical section that revalidates as in P2 |
| **P4** | The brief's literal hypothesis: enqueue *unverified*, one lander verifies trunk+batch in full, bisect a red batch |
| **P5 / P5f** | **Recommended**: Phase A (full suite, K=2) in each session, then one combiner that group-commits every ready ticket, non-code first. P5f re-runs the full suite on any candidate that differs from a ticket's verified tree (Phase 3, no pruning); P5 prunes (Phase 4) |

### 4.2 Validation against the week

Today's lane at the shipped admission (K=1):

- Measured 92% single-round lands at N≈2 (the time-averaged in-flight count). The model gives
  88–89% at N=2.
- Measured p95 48 min and max 82 min at N≈4–5. The model gives p95 27–38 min and max 83–119 min at
  N=4.
- The model's throughput falls between N=6 and N=8 (7.4 → 3.9 lands/h at background 45):
  **today's lane saturates at about 6 concurrent landers**.
- H1's independent simulation, calibrated at N=5 and a 45-min cadence, reproduced the measured 5.8
  lands/h and first-round loss 0.44 (measured 0.45).

`scenarios.py validate`.

### 4.3 Results

The §1 table is `scenarios.py keyed` at a 30-min cadence. Each cell below gives lands/h · p95
minutes; "keyed" means Phase 2e's shell-out keying is on (suites at 0.6×).

| cadence | N | PS (Phase 2) | P5f (Phase 3) | P5 (Phase 4) |
|---|---|---|---|---|
| 45 min, keyed | 8 / 15 / 25 / 40 | 9.7 · 6.7 / 18.4 · **9.8** / 27.4 · 29.9 / 29.5 · 75.4 | 10.2 · 8.5 / 18.2 · **12.0** / 29.6 · 15.0 / 43.6 · 21.3 | 10.1 · 5.7 / 18.7 · **7.0** / 31.1 · 9.7 / 47.8 · 16.4 |
| 30 min, keyed | 8 / 15 / 25 / 40 | 13.8 · 7.3 / 25.0 · **16.6** / 29.2 · 45.7 / 29.5 · 98.9 | 14.3 · 9.7 / 25.4 · **13.4** / 38.6 · 18.0 / 54.6 · 33.4 | 14.8 · 6.2 / 26.7 · **8.3** / 42.2 · 13.5 / 57.3 · 29.7 |
| 30 min, **not** keyed (ruling R2 refused) | 8 / 15 / 25 / 40 | 13.3 · 13.7 / 20.4 · 34.1 / 21.6 · 81.6 / 21.9 · 154 | 13.2 · 15.3 / 22.7 · 22.0 / 33.9 · 29.7 / 40.4 · 60.8 | 14.3 · 9.4 / 25.5 · 14.1 / 37.5 · 25.1 / 42.4 · 57.5 |

- **PS is a large, cheap win with a hard ceiling:** ~29 lands/h keyed, ~21 not keyed. Serializing
  every land removes every lost race, so collapse is gone, and each code change is verified exactly
  once. At a 45-min cadence that makes PS *better* than the unpruned combiner up to N=15.
- **The combiner removes the ceiling.** Group commit shares one verification among everything
  waiting, which is worth it where PS's ceiling binds: from N≈15–20 at a 30-min cadence, and 2–3×
  at N=25–40. Unpruned, it pays for Phase A *and* a re-verification whenever trunk moved, which is
  why pruning (P5) matters most here.
- **Near 55–60 lands/h every design meets this Mac's verification capacity.** At N=40 × 30 min
  (offered ~80/h) the combiner's p95 is 30–33 min however it is tuned.
- **Keying is the largest single lever after serialization.** Without it, every column roughly
  doubles its p95 at N≥15.
- **The literal hypothesis (P4, enqueue unverified)** uses the least CPU but is slower wherever load
  is real: 19.8 vs 14.1 min (P5, not keyed) at N=15, and 76 vs 58 at N=40. Unverified tickets poison
  batches, and a bisect stalls everyone behind it (§4.4 flake rows).

### 4.4 What the verdict rests on

All rows are keyed, at a 30-min cadence, background 150.

| scenario | P5 (pruned) p95 at N=15 / 25 / 40 |
|---|---|
| q=0.10 (pruning very effective) | 7.0 / 11.2 / 28.1 |
| **q=0.42** (H1's measured share of land pairs whose closures intersect) | **9.1 / 13.8 / 29.0** |
| q=0.72 (H1's figure for wave-6's coupled work) | 9.6 / 14.4 / 27.8 |
| q=1.0 (every rebase needs a partial re-run) | 9.9 / 15.0 / 27.4 |
| **no pruning at all** (pf = tf = 1) | **13.1 / 17.6 / 30.3** |

| flake rate per suite run, N=15 | PS | P5f | P5 | P4 (enqueue unverified) |
|---|---|---|---|---|
| 3% | 16.6 | 13.4 | 8.3 | 10.0 |
| 10% | 21.5 | 17.3 | 10.4 | 13.2 (non-code p95 11.6) |

- **Pruning risk never becomes throughput risk.** The combiner holds in every q row, including "no
  pruning at all", because group commit amortizes an expensive commit step. So it can be built
  *before* pruning.
- **Admission width binds after everything else** (`scenarios.py admission`, P5f keyed). At K=1,
  p95 is 15.2 / 32.2 / 71.0 min at N=15 / 25 / 40; K=2 gives 13.4 / 18.0 / 33.4; K=3 gives
  13.3 / 18.9 / 27.2. E measured the best throughput per unit of latency at ~2 concurrent suites.
  **Phase A runs at K=2 (K=3 once N>30), and the combiner gets its own single slot.**
- **The corrected load law penalizes the combiner, not the lane** (`scenarios.py law`). Moving from
  v1's load1 term to E's measured +45–49 s per concurrent suite leaves PS unchanged: it runs one
  suite at a time. It raises the unkeyed combiner's p95 from 14.9 to 22.0 at N=15 and from 29.1 to
  60.8 at N=40. That is why v2's headline rests on keying, and why the Phase 3/4 acceptance targets
  in §7 are set from v2, not v1.

### 4.5 A second, independent model, and where it disagrees

H1 built its own simulator as a devil's advocate arguing that the lane suffices (`reports/h1/`,
3 seeds × 195 h per cell; Poisson and synchronized-wave arrivals). It agrees on four points:

- The brief's listed fixes **collapse between N=10 and N=15** (45-min cadence).
- **Serialization is what prevents collapse.** Its "fix 5", holding the existing slot from before
  the fetch through the push, takes N=15 from 2.9 to 14.1 lands/h delivered.
- **Batching wins beyond a break-even**: Λ\* ≈ 24 lands/h, i.e. N\* ≈ 18–20 at a 45-min cadence,
  **12–17 at 30 min**, and **≈15 at 45 min for coupled work like wave 6**.
- **The queue's win at N ≤ 20 is serialization, not batching**: mean batch 1.23 at N=15, 1.42 at
  N=20.

It disagrees on non-code lands. H1 keeps them *out* of the serialization (their window is 14 s) and
pays with a verdict carry across disjoint rebases, a new mechanism with a soundness risk. H1's
queue raised non-code p50/p90 from 14/80 s to 62/348 s at N=15.

**This plan takes the other side on purpose, and priority pays most of H1's price back.** Every
land takes the turn, so no carry is needed for soundness. Non-code lands are served before waiting
code lands: in the serialized lane at N=15 (30-min cadence, keyed) their p50/p95 is 1.5 / 3.6 min.
Without priority, a plain FIFO turn made it 9.7 / 25 min (red-team #3). Phase 4's pruning brings it
to 0.2 / 1.5 min by letting a provably disjoint non-code change ride the in-flight push. §6 records
H1's variant as the principal alternative.

---

## 5. Target architecture — "verify once, commit by combining"

### 5.1 Shape

```
 session worktree (×N, parallel)                 one elected combiner (serial turn)
 ───────────────────────────────                 ──────────────────────────────────
 preflight · esc_scan (DROP parks) · class
 reconcile onto trunk
 PHASE A — presubmit, admitted (K=2):
   tsc (incremental) + union suite ──► verdict record keyed by (tree, env)
   skipped if a green record for this exact
   tree+env already exists
 publish TICKET (local; never a pushed ref) ───►  take ready tickets: non-code first, then a
 wait on RESULT  (or --async + notify)            code batch (≤ Bmax; a drizzle ticket rides alone)
                                                   fetch trunk · cherry-pick each onto it (scratch
                                                   worktree; conflict ⇒ eject that ticket)
                                                   VERIFY the combination (§5.3), own admission slot
                                                   green ⇒ full-suite verdict record for the tree
                                                        ⇒ ONE fast-forward push (the hook reads it)
                                                        ⇒ content-verify every ticket ⇒ RESULTs
                                                   red   ⇒ bisect · isolated re-run (R4) · known-red
 adopt landed commits (content-verified) ◄───────  RESULT + cc-notify to each ticket's owner
```

Phase 2's serialized lane is this picture without Phase A and without batching: each session runs
the combiner's turn for itself, one at a time. Phase 3 changes who runs the turn and how much it
carries, not its contract.

### 5.2 Components and the invariant each carries

| Component | What it is | Invariant |
|---|---|---|
| **Verdict record** (exists: `~/.reso/presubmit/<tree>.json`, `ship-land.sh:771-811`) | "This exact tree passed these checks, in this environment." Written only on a real green | **I1: each (tree, env, check) is verified at most once, box-wide.** Every gate consults it, including the pre-push hook, which today does not (B2). The environment signature is **matched on read**; today `:793-795` records it and nothing matches it. claude-infrastructure paid for the unmatched version: a `.shellcheckrc` flip "let a red land green" (F §3 row 9) |
| **The turn** | A lease with two queues (non-code served first, then code in FIFO order). Acquisition is claude-infrastructure's `mkdir` + `pid+lstart` identity + reap mutex + generation re-check (`scripts/land-lock.sh:370-412`), reaped **only when the holder's pid is dead**. Three pieces are **new code, not a port**, because that script has no self-abort and treats a live over-budget holder as "needs a human" (`:204-232`; red-team #1):<br>(a) **every network call inside the turn is bounded**: `timeout` on fetch, `ls-remote` and push, plus `ServerAliveInterval` for the SSH remote. Today `ship-reconcile.sh:78` and `ship-land.sh:277,753` fetch unbounded;<br>(b) **a watchdog side process** heartbeats the lease. Past the hard hold bound it kills the holder's own process group, so a hung holder dies and is then reaped as dead. A live holder is never stolen;<br>(c) **a waiter bound**: a session waiting longer than it falls back to today's optimistic lane (with Phase 2's fixes) instead of waiting forever.<br>The turn runs in a **detached child**, never inside the Claude Code Bash call: a waiting land can outlast the tool's 600-s ceiling, and a killed tool call must not orphan a holder mid-push (red-team #3) | **I2: no on-box land can move trunk under a verification in progress; nothing can hold the turn forever; correctness never depends on the lease.** Trunk advancement is still decided by GitHub's ref compare-and-swap plus content-verify (`ship-land.sh:14-24`). A false takeover wastes work; it can never lose or double a land. reso's own reap is a bare rename with a documented 3-holder race (F §3 row 6) and is not reused |
| **Phase A presubmit** (today's round 1 minus the push) | reconcile → tsc → the **full** suite (keyed as in Phase 2e), admitted at K=2, in the session's own worktree. It writes a `mode=full` verdict record for the exact tree | Author defects and most flakes are caught **before** they reach a batch. A lone ticket that lands on the trunk it was verified on needs no second run. The P4 → P5 gap in §4.3 is this component |
| **Ticket spool** `~/.reso/landq/tickets/<id>.json` | Written by atomic rename; carries branch, head, tree, verified base, changed files, ship class and owner address. **Local only**: never pushed as a ref, so no Amplify auto-branch risk (B2 table) and no extra Actions runs | **I3: a ticket is data, not a process.** Any process can die and nothing is lost |
| **Combiner** | An **on-demand detached process** that holds the turn while it works. The first publisher that finds no live combiner spawns it; it drains the spool and exits after ~30 s idle. **No launchd agent, no permanent daemon.** It runs in its own persistent worktree (warm `tsconfig.tsbuildinfo`, `node_modules`) where no statusline or sweeper runs `git status`. Its heartbeat comes from the turn's watchdog side process, never from its main loop, so a long suite cannot make it look dead (red-team #4) | **I4: a wedged combiner cannot stop the fleet.** It is replaced only when its pid is dead; a hung one is killed by its own watchdog past the hard bound, then replaced. Past its waiter bound, a session degrades to the direct lane. reso killed a persistent lander daemon twice ("a wedged train blocks all sessions — worst 3am failure", B2 C4) and claude-infrastructure ranked one second for the same reason (F §4); both halves of that failure are designed out |
| **Write-ahead journal** `~/.reso/landq/journal.jsonl` | Before every push the combiner appends `{candidate tip sha, ticket id → landed commit shas}` and fsyncs | **I10: landedness after a crash is decided by ancestry of the journaled tip, never by content inference.** A ticket whose file a later ticket in the same batch rewrote would otherwise read as "not landed" and be re-picked (red-team #5) |
| **Group commit** | One push carries every ticket that verified green, as **distinct rebased commits, never squashed** | **I5: per-commit attribution survives.** Patch-ids are preserved for `worktree-gc`'s landedness test and for any future postland bisect (B2 C14) |
| **Adoption** | On `landed`, the session's branch is moved onto the landed commits (red-team #6), in one of three cases:<br>(i) **the synchronous default**: the tree is clean because ship-land refuses a dirty one and the session is blocked, so `reset --keep <landed head>`;<br>(ii) **commits made after the ticket** (`--async`): `rebase --onto <landed head> <ticket head>`;<br>(iii) **uncommitted edits to a file the batch touched**: adoption is deferred, never forced. The *next* `ship-land.sh` invocation, and `landq adopt` at session close, read the RESULT for this branch and adopt first, so a landed ticket is never re-published as an "already upstream" empty pick | **I6: the session ends with HEAD reachable from trunk.** This is the precondition reso's invariant 4 exists to protect (B2 C1, C14): `wrap-ledger`'s `UNLANDED = AHEAD>0 OR CHERRY` then reads 0 |
| **Bisect, isolated re-run, known-red** | A red batch splits in halves. A single red ticket re-runs its failing spec files once, in isolation, on the same tree, before conviction (policy R4). A red that reproduces on **bare trunk** opens a trunk-red record rather than convicting a rider (the V3 W4b "known-red exclusion" is designed but unbuilt) | **I7: a flake never convicts an author, and one bad trunk commit cannot stall every land** (B2 C8) |
| **Direct lane** (Phase 2's serialized lane) | Kept as the fallback. `LAND_QUEUE=off` restores it, the same pattern as `LAND_LANE=v1` (`ship-land.sh:81-85`) | **I8: degrade, never wedge** |
| **Telemetry v4** | A `unit` id across attempts. Per ticket: Phase A s, turn wait s, turn s, batch size, verification-set size, bisects. `ts_start` is taken in the first process, not after the re-exec (H2 row 10) | **I9: the operator's number is computed by the system** |

### 5.3 What the combiner verifies

- **Phase 3, no pruning.** When the candidate differs from every ticket's verified tree (trunk
  moved, or the batch holds more than one ticket), the combiner runs incremental tsc plus the
  **full unit suite** on the candidate, once per batch. The resulting verdict record is `mode=full`,
  which is exactly what reso's hook-skip ruling honours (C11). A lone ticket on an unmoved trunk
  already *has* a `mode=full` record from Phase A, and it is pushed as verified. Group commit
  amortizes the rest: §4.4's "no pruning" row is this configuration.
- **Phase 4, pruning.** A ticket verified green on `base_i + change_i` lands on `trunk + earlier
  members`. A test whose inputs touch only one side has already passed on identical inputs, and only
  a test whose inputs touch **both** sides has never run on this combination. So the combiner runs:
  - tsc, incremental and warm;
  - `related(change_i) ∩ related(everything else since base_i)` on the **candidate's** module graph,
    so an edge the other side added is seen;
  - every test whose *declared* file inputs intersect both sides.

  Pruning ships only after a shadow period in which the pruned and full verdicts are computed side
  by side on every batch and never disagree.
- **Why the declared-inputs guard is mandatory.** `vitest related` walks static imports. A test that
  reads a file by path (shell scripts under test, floor-plan JSON blobs, `pre-push:63-69`) is
  invisible to it, and that is why `tests/presubmit-always.txt` exists. claude-infrastructure
  rejected a changed-file-scoped gate *as proof* for the same reason (F §4).

### 5.4 Non-code lands

A docs-, scripts- or data-only ticket needs no suite of its own, unless it touches a declared input
of the shell-out specs.

- The turn serves non-code lands first, in the Phase 2 lane and in the combiner alike, and they push
  in seconds.
- A non-code land that arrives while a code land holds the turn waits for that holder only, not for
  the code queue. Modelled at N=15 (30-min cadence, keyed), p50/p95 is **1.5 / 3.6 min**, where
  today's p50 is ~20 s. A plain FIFO turn made it 9.7 / 25 min (red-team #3), which is why priority
  is part of Phase 2, not a tuning option.
- Phase 4 removes most of the remaining wait: a non-code ticket whose files intersect no declared
  test input rides the in-flight push, sound by the §5.3 argument (modelled 0.2 / 1.5 min).

### 5.5 Failure modes

| Failure | What happens | Why nothing is lost or doubled |
|---|---|---|
| **Poisoned batch** | Bisect by halves; land green halves at once; eject the culprit to its owner with the failing specs | Halves re-derive from the spool |
| **Flaky test** | One isolated re-run on the identical tree (R4). Green ⇒ recorded in a flake ledger against that spec, and the ticket lands. Red again ⇒ convicted. A spec flaking twice in 7 days goes to quarantine with an owner | A flake costs one re-run, never a batch, and never silently |
| **Red trunk** | A failure that also reproduces on bare trunk opens a trunk-red record, and batches are judged on "no new reds" until it clears | One bad commit cannot stall every land (B2 C8) |
| **Combiner crash mid-batch** | The holder's pid is dead ⇒ the next waiter reaps it under the reap mutex and spawns a combiner. That combiner first reads the journal (I10). If the last journaled candidate tip is an ancestor of `origin/main`, its tickets are marked `landed` with the journaled shas and never re-picked; if it is not, nothing of that batch was pushed and it is re-processed | The push is one atomic ref update, and landedness is decided by the journaled tip's ancestry, not by content inference, which misreads in-batch supersession (red-team #5) |
| **Holder or combiner hang** (a stuck suite, or a network call despite its timeout) | Never taken over while its pid lives: stealing a live holder is exactly v1's failure (`ship-land.sh:18`). Its own watchdog kills its process group at the hard bound; it then reads as dead and is reaped. Waiters past their bound fall back to the direct lane, so the fleet keeps landing in the meantime | Correctness is GitHub's CAS, never the lease (I2); the worst case is one bounded stall, then degraded-but-moving |
| **A session's tool call times out while its land waits** (Claude Code's Bash ceiling is 600 s) | Nothing happens to the land: the turn runs in a detached child (I2), and the session re-attaches to its RESULT | The holder is never the tool-call process, so killing the tool call cannot orphan a push or a suite |
| **Session dies while waiting** | Its ticket still lands and its RESULT persists; a successor adopts it by branch name | Tickets never depended on the session |
| **Rebase conflict** | Eject that ticket (`conflict`, with paths); the owner resolves it and re-publishes. Rerere runs with `-c rerere.autoupdate=false` in the combiner, so a staged replay cannot masquerade as a clean stop (B1 §2.4) | Same outcome as today's exit 5, minutes sooner |
| **Outside push** (the operator, a hotfix) | The combiner loses the ref CAS ⇒ re-fetch, re-verify (bounded), retry | CAS is still the arbiter |
| **Migrations** (`drizzle/` `_journal.json`) | A drizzle ticket is a batch of one and runs `ship-reconcile.sh`'s resolver on the candidate (it regenerates at the next index, B1 §2.2); DML and DDL-mismatch exits go back to the owner. The narrow drizzle mutex becomes redundant, because every land already takes the turn; it currently holds for 333–2,377 s while code lands win its races (B1 S17) | The DROP scan stays in Phase A (it parks before a ticket exists) and is re-asserted on the candidate (B2 C10) |
| **The operator's `/deploy`** | Untouched. `/deploy` fast-forwards `origin/release` to a green-stamped ancestor (`deploy-release.sh:55-64`); the combiner never touches `release`. Group commit makes fewer, larger tips | Landing stays free (Amplify auto-build is off on `main`, Path F ignores `main`, Actions billed $0: B2); deploying stays the operator's and money-spending |
| **Residency** (branches that wait conflict more: 55% at <6 h → 91% at 24–72 h in claude-infrastructure, F §4) | Turn residency is minutes, against today's 48-min p95 livelock. A ticket older than its bound is ejected back to its owner, never aged in place | No aged-branch retry drain is created (F §5) |

### 5.6 The standing reso decisions this design respects or amends (B2 §c)

| reso decision | This design |
|---|---|
| **C1 / invariant 4**: "Landing stays free, continuous, agent-driven and SYNCHRONOUS. No merge queue, no PR lane, no off-box lander" (`learnings.md:2565`) | Keeps its *reason*: synchronous per session, HEAD reachable from trunk (I6), on-box, free. **Amends its letter in Phase 3 (ruling R3).** Phase 2 needs no amendment: a FIFO turn is not a queue of other people's work |
| **C2**: merge queue rejected twice ("latency ≥ gate time; modal batch one rider; GHEC-only") | Its premise changed: "with the gate off the land path there is nothing to batch" predates W3a putting a 150-s suite back on the path. "Modal batch one rider" is true below ~20 landers (H1: 1.23 at N=15) and is why Phase 2 (serialization without batching) comes first. GitHub merge queue stays rejected (§6) |
| **C3**: the 2026-07-03 "ephemeral group-commit train" (land-lock winner drains requests, cherry-picks onto a scratch worktree, one gate, one FF push, **no daemon**), deferred until "batch-green rate >0.7 AND coincident gated ships ≥2/burst" | **Phase 3 is this design**, with bisect and isolated re-run in place of "reject the whole train", and with Phase A in front. **Both triggers have plausibly fired** (suite-green 0.88; 2.42 gated attempts per active 30-min bucket, B2 §0.4). That is a proxy measurement, which Phase 1 makes formal |
| **C4**: persistent lander daemon killed twice | Designed out (I4) |
| **C5**: never run-anyway, never land-unproven | The combiner never pushes a batch whose verification was cut, shed or unadmitted; a cut re-queues |
| **C6**: nothing verdict-only on the land path; operator ruling 2026-09-13, "reduce anything if anything adds to the landing load congestion" | Every phase *reduces* land-path verification: two suites → one per land (Phase 2) → one per batch (Phase 3) → an intersection (Phase 4) |
| **C7**: $0 on gating | All on-box |
| **C8**: no auto-revert in reso (banned inside migration ranges) | None is added. The known-red record is the W4b substitute, built where it is needed |
| **C10**: migrations serialize | Drizzle tickets ride alone (§5.5) |
| **C11**: the hook suite is **gated on a token, honoured only for `mode=full`**; never deleted outright (`learnings.md:2657, 2682, 3156`) | Honoured literally. Phase 2 makes the land-time suite the full suite so the token *is* `mode=full` (ruling R1: the 2026-09-14 ruling had chosen union for the land-time suite). A bare `git push` outside the lane still runs the full suite |
| **C13**: only one cache (the tree-keyed stamp/token) | The verdict record *extends* the existing token (env matched, full mode); there is no new cache |
| **C14**: per-session lands, `UNLANDED = AHEAD>0 OR CHERRY` | Adoption (I6) |

---

## 6. Alternatives considered

| Alternative | Evidence | Verdict |
|---|---|---|
| **The brief's four listed fixes only** (hook honours token, ref-lock = race, test band, retuned rounds/backoff) | Both models: collapse between N=10 and N=15 (H1: 2.9 of 18.8 lands/h at N=15). Rounds/backoff: 1 exhaustion all week; a 1–4 s jitter is <1% of the window (H1 fix 4) | Necessary pieces, not a design; folded into Phase 2 |
| **H1's "C7": serialize only code lands through the slot, keep non-code lands optimistic, carry verdicts across disjoint rebases** | Best blended latency up to its break-even (N=15, 45 min: code p50/p90 319/805 s, non-code 14/80 s); loses to a queue beyond N\*≈12–17 (30 min) or ≈15 (coupled work). Needs the carry, which is a graph-based soundness risk, *in Phase 2* (H1 §e) | **The principal alternative.** Rejected for Phase 2 because it needs the riskiest mechanism first. Its non-code speed returns in Phase 4, once that mechanism is proven in shadow |
| **Optimistic CAS + cheap revalidation** (P2) | Model v2 (base grid, unkeyed, background 150): 18.2 min at N=15 but 149 min at N=40, because lost rounds still cost re-verification and concurrent suites slow each other. v1 showed it fragile in q as well (91.9 min at N=40 when every rebase intersects) | Rejected: its throughput depends on pruning being sound *and* effective |
| **The literal merge queue: enqueue unverified, one lander, batch + verify-once + bisect** (P4) | Least CPU (3.7–5.7 core-min/land), but slower wherever load is real: 19.8 vs 14.1 min for P5 at N=15, 76 vs 58 at N=40 (v2, 30-min cadence, unkeyed); non-code lands wait behind code batches (non-code p95 18 min at N=15). Batch theory agrees: Dorfman's cost per change `1/b + 1 − (1−p)^b` puts the optimal batch at ≈1/√p, and flakes cut Ericsson's measured savings from 72% to 41% (A §2) | **Corrected, not rejected**: P5 is P4 with Phase A in front and bisect + isolated re-run instead of batch poisoning |
| **GitHub merge queue** | Available only for "public repository owned by an organization, or … private repositories owned by organizations using GitHub Enterprise Cloud" (github/docs `data/reusables/gated-features/merge-queue.md`, A §4). reso is **User-owned and private** (`gh api` → `owner.type: User`). It would also run one CI build per PR on paid minutes and need a PR per agent land (C7) | Rejected |
| **Speculative stacking** (Zuul/SubmitQueue: verify trunk+c1, trunk+c1+c2 in parallel) | On one machine it multiplies CPU on the saturated resource: vitest already "uses all available parallelism", and speculative throughput is capped by runs of consecutive successes (A §2; SubmitQueue EuroSys'19 §8.3). reso killed speculative rebase chains in 2026-07 (the journal trap, B2 C4) | Rejected on this box |
| **claude-infrastructure's design** (gate unlocked, a 3-s lock around check-then-push, an in-lock fallback after 3 rounds) | 44% of rounds that reach its lock are stale, rising 0.16 → 0.84 as rounds grow from 2–4 to 15–30 min. Its fallback convoyed to a 184-s p50 hold; land p95 63 min (F §0, §2) | Rejected as the model: it keeps verification inside the race. Its lock *implementation* is adopted for the turn (I2) |
| **A machine-wide lock around the whole pipeline** (reso v1) | p95 wait 28 min, one 47-h wedge, 27 steals of a live holder, 49% of lands overlapping anyway (`ship-land.sh:14-24`) | Rejected (historical). The turn differs on every recorded failure cause: it never steals a live holder, it is FIFO, it holds one suite rather than a 2,254-s `design:gate`, and it has a self-abort bound |
| **Whole-gate verdict cache (trunk sha, diff hash) / retry reuse** | claude-infrastructure rejected both: N landers on one trunk share no verdict, and unkeyed inputs launder reds (F §4) | Rejected; the verdict record is keyed on the whole tree + a matched environment |

---

## 7. Phased plan

All implementation is in **reso-management-app**. Every unit lands through reso's own `/ship` (free);
`/deploy` is the operator's and is never part of this plan. The implementing lead records the working
plan by **extending an existing file** under reso's `docs/infra-deploy/`, because reso's docs gate E3
refuses a `docs/` addition without a deletion (`pre-push:505-515`). This document is the design
record it cites.

### Phase 0 — Orchestration

| Wave | Units (one task each) | Locus | Blocked by | Branches |
|---|---|---|---|---|
| **W1** | **U1** harness + `LAND_LOG` override + unit id (Phase 1) · **U2** pre-push reads the verdict record (2a) · **U3** `ship-land.sh`: full-suite-once, the turn, band, non-verdict arm, exit-code namespace (2a–2d) · **U4** shell-out spec input keying (2e, ruling R2) | **S** ×4, one dispatched session each | U4 behind ruling R2; the rest none. Files are disjoint: `scripts/land-harness/**` · `scripts/hooks/pre-push` · `scripts/ship-land.sh` + `scripts/land-log-audit.py` + `.claude/commands/ship.md` · `tests/presubmit-always.txt` + `scripts/checks/presubmit-always.ts` + a new inputs manifest | `land-w1-harness` · `land-w1-hook` · `land-w1-lane` · `land-w1-keying` |
| **W2** | **U5** `scripts/landq/` core: spool, results, the turn's lease (a port of claude-infrastructure `land-lock.sh:370-412`), journal · **U6** combiner: candidate build, full-suite verification, group commit, bisect, isolated re-run, known-red · **U7** crash-injection suite over U5+U6 | **S** ×3 | W1 landed and Phase 3's trigger met (below). U6 and U7 start when U5's interface is committed | `land-w2-landq` · `land-w2-combiner` · `land-w2-crash` |
| **W3** | **U8** `ship-land.sh` integration: Phase A → publish → wait/adopt, `--async`, bounded fallback, `LAND_QUEUE=off` | **S** | U5–U7 | `land-w3-integrate` |
| **W4** | **U9** module-graph engine + declared inputs for every always-run spec · **U10** shadow comparator (pruned vs full verdict per batch) | **S** ×2 | W3 in production ≥ 7 days | `land-w4-graph` · `land-w4-shadow` |
| **W5** | Tuning: batch bound, Phase A scope, flake quarantine thresholds, DB-fixture template | **L**: one lead-inline session. Each knob is a constant in files the earlier waves own, and splitting them would only add merge loops | W4 shadow clean | lead's own worktree |

- **Unit size band:** 40–150K output tokens ≈ 30–75 min ≈ 3–6 files per unit. U3 and U6 are the
  largest; each splits along its dash-separated items if its brief passes 150 lines.
- **Each S fire:** `handoff-fire.sh --prompt-file <brief> --worktree <branch> --notify-back <lead>
  --goal '<the phase's acceptance line> — proven by <the harness or census command, printed>; do not
  push to origin/main by hand, do not /deploy'`.
- **Lead context budget:** hold ≥ 50% of the window for decisions. The lead reads completion pings
  and runs each phase's acceptance command itself, never unit diffs in full.
- **Succession point:** recycle the lead (`handoff-fire.sh --recycle`) at every wave boundary, after
  the acceptance numbers are written into the plan. No single lead session carries two waves.

### Phase 1 — Instrument first (U1)

- **Harness** `scripts/land-harness/`:
  - A scratch clone whose `origin` is a **local bare repo** (`git clone --bare --shared`), so
    nothing reaches GitHub.
  - N synthetic landers in N worktrees. Each loops: Exp(T_work) → a synthetic change (docs /
    leaf-module TS / shared-module TS, mix configurable) → land.
  - **Stub mode** puts a `pnpm` shim on PATH that sleeps per the fitted stage laws, including E's
    +45 s per concurrent suite, and fails at p_self / p_flake. It tests coordination at N=15–40 in
    minutes at ~0 CPU.
  - **Real mode** runs the real suites, on a quiet box only.
- **Telemetry:** a `unit` id across attempts; `ts_start` taken before the re-exec.
- **Measure what the models assumed:**
  - q, the share of land pairs whose closures intersect. H1 already estimated **0.42 overall and
    0.72 for wave-6's coupled work** with a regex graph; Phase 1 re-measures it with a real one.
  - The flake rate per spec.
  - The real per-session land cadence at peak.
- **Acceptance:** stub mode reproduces both models' collapse (harness throughput *falls* from N=8 to
  N=15 on today's lane) and PS's ceiling (~20 lands/h at the fitted laws). Nothing is built on the
  model until the harness agrees with it.

### Phase 2 — The serialized lane (U2, U3, U4)

- **2a · One full suite per land, honoured by the hook (U2 + U3; ruling R1):**
  - `run_suite` runs `vitest run`, the full suite, in place of the union selector.
  - The union costs about what the full suite costs: the always-run set is 92% of it (D), union
    96–101 s vs full 108 s alone (E).
  - It writes a `mode=full` verdict record.
  - `pre-push` skips `pnpm test:unit` only when a record for `HEAD^{tree}` is green, lists
    `test:unit`, is `mode=full`, is inside its TTL, and has a **matching** env signature. It prints
    a one-line receipt either way. Any mismatch runs the suite: this is fail-safe, and C11's polarity
    is kept.
- **2b · The turn (U3), exactly as specified in §5.2:**
  - Every land acquires the lease **before its fetch** and holds it through push and
    content-verify, keeping it across a lost push. Non-code lands are served first and hold it only
    for their push.
  - Every network call inside it is bounded; a watchdog side process heartbeats it and kills a
    holder that passes the hard bound; a waiter past its bound falls back to the optimistic lane.
  - It runs in a **detached child** that the session's `ship-land.sh` waits on and can re-attach
    to, never inside the Bash tool call.
  - This replaces `cc-sem reso-land`'s unordered polling and 300-s refusal for this path, closes B3,
    and makes the drizzle mutex redundant.
  - Acquisition and reaping are claude-infrastructure's (never reso's bare-rename reap). The
    watchdog, the bounds and the fallback are new code.
- **2c · Band and verdict hygiene (U3):**
  - `run_suite` exports `CI=true` (vitest's retry 2) and a `VITEST_TIMEOUT_FACTOR` the caller
    declares from measured concurrency.
  - A suite whose failures are *all* timeouts is a non-verdict: re-run once, never exit 6. This is
    the lane arm of `postland-verify.sh:148-182`'s `suite_failed_only_on_time`.
  - `PUSH_TIMEOUT` stops being below the hook's p50 (moot once 2a lands).
- **2d · Exit-code namespace (U3):**
  - Reconcile's codes are re-mapped into their own range at `ship-land.sh:843`, so a passing
    `index.lock` can no longer read as a parked destructive migration.
  - Reconcile's rc-6 message stops asserting "already upstream" for a stop it cannot attribute.
  - The `/ship` table is corrected to match.
- **2e · Key the 23 shell-out specs on declared inputs (U4; ruling R2):**
  - They run only when the landing range touches their declared inputs (`scripts/**` plus any file
    they read), and the verdict record lists what was keyed out.
  - Saves **140–170 s per code land** (D), and it shortens every later phase's turn as well.
- **Acceptance:**
  - production census (7 days containing a wave of ≥ 6 landers): code-round `push_s` p50 ≤ 10 s
    (from 167), 0 lost-race rounds between on-box lands, p95 unit latency ≤ 15 min (from 48);
  - harness stub (v2 laws), keyed: N=8 p95 ≤ 10 min (model 7.3); N=15 at a 45-min cadence
    p95 ≤ 15 min (model 9.8); non-code p95 ≤ 5 min at N=15 (model 3.6);
  - fault injection: a holder whose fetch hangs, and a holder whose suite hangs, each release the
    turn within the hard bound, and waiters past their bound land through the fallback;
  - a planted all-timeouts red is re-run, not convicted.

### Phase 3 — The combiner (U5, U6, U7, then U8; ruling R3)

- **Trigger, measured and not assumed:** build when the census shows peak Λ > 20 lands/h, or the
  turn busy > 70% of a peak hour. That is the Phase 2 lane at ~70% of its keyed ceiling (~29/h),
  where its p95 starts to climb (§4.3). At the operator's stated 15+ high-volume sessions and a
  30-min cadence (~25/h offered), this holds on the first busy day. This mirrors how reso deferred
  its own group-commit train behind telemetry (C3).
- **U5:** spool and results (atomic rename, local only); the lease reused from 2b unchanged
  (watchdog heartbeat, dead-pid-only takeover); the **write-ahead journal** (I10).
- **U6:**
  - persistent combiner worktree;
  - non-code first, then a code batch (drizzle tickets alone);
  - candidate by cherry-pick with `--empty=drop` onto freshly fetched trunk, ejecting on conflict;
  - when the candidate differs from every ticket's verified tree: incremental tsc + the **full**
    suite (keyed) under the combiner's own single admission slot (no priority inversion behind
    Phase A), producing a `mode=full` record. A lone ticket on an unmoved trunk is pushed on its
    Phase A record;
  - journal, then one push, content-verify, RESULTs + `cc-notify`;
  - bisect, isolated re-run (R4), known-red record.
- **U7 · crash and fault injection:**
  - kill -9 the combiner at every step boundary: after fetch, after cherry-pick, mid-suite, after
    the journal write, after push before RESULT, after RESULT;
  - include the **in-batch supersession** case (ticket B rewrites a file ticket A changed) and a
    hung suite;
  - assert that every ticket ends `landed` exactly once or is still pending, that no landed ticket
    is re-picked, and that trunk content equals the union of landed tickets.
- **U8 · integration:** preflight → Phase A (K=2) → publish → wait (default) or `--async` → adopt
  (§5.2's three cases). Past the bound it falls back to the Phase 2 lane; `LAND_QUEUE=off` restores it.
- **Acceptance:** targets are set from landsim v2, keyed, at a 30-min cadence:
  - harness stub N=15 p95 ≤ 16 min, N=25 ≤ 22 min, N=40 ≤ 40 min (model 13.4 / 18.0 / 33.4);
  - U7: 100% of injected crashes and hangs lose nothing and double nothing;
  - production: p95 unit latency ≤ 15 min over 7 days containing a wave of ≥ 10 landers.

### Phase 4 — Pruning (U9, U10)

- **U9:** a static import graph of the candidate (TS resolution plus `vitest.config.ts` aliases)
  cached per tree, the §5.3 rule, and declared inputs for every always-run spec, with a lint that
  refuses an undeclared one.
- **U10:** shadow mode computes the pruned set, still runs the full set, and logs every
  disagreement.
- **Acceptance:** ≥ 200 batches and ≥ 14 days with **0** pruned-green / full-red disagreements;
  *then* enable. Harness keyed at a 30-min cadence: N=15 p95 ≤ 10 min and N=25 ≤ 16 min (model
  8.3 / 13.5); turn p50 ≤ 30 s; non-code p50 ≤ 20 s (they ride the in-flight push, §5.4).

### Phase 5 — Tune, and the box's own ceiling (W5)

**Every design meets this Mac's verification capacity near 55–60 lands/h**, i.e. N≈40 at a 30-min
cadence (§4.3). Past it the levers are per-change cost, not coordination:

- whether Phase A runs only `related(diff)` and leaves the always-run set to the combiner (Phase 1
  measures the always-run share);
- a migrated-template DB for the 48 fixture specs (117 s, D);
- extending declared-input keying beyond the shell-out specs;
- admission K=3 for Phase A once N>30 (§4.4).

Then:

- batch bound: A §2 puts the optimum near 1/√p;
- flake quarantine thresholds;
- a `land-queue-status` view: turn holder, depth, oldest ticket, p95 unit latency over 24 h.

---

## 8. Conviction, and the rulings this asks for

**Recommendation conviction: 86%.**

**What supports it:**

- Two independently built models agree on every structural claim: collapse, serialization, the
  break-even (§4.5).
- Each model was validated against the week's measured rounds and latency (§4.2).
- claude-infrastructure's own lane empirically confirms that window length drives staleness
  (F §0.1).
- reso's own 2026-07-03 design deferred exactly this train behind triggers that have plausibly fired
  (§5.6 C3).
- **A wave-2 red-team** (a different model on purpose; `reports/wave2-redteam.md`, verdict
  SOUND-WITH-FIXES) found six defects in the first draft. All six are fixed above:
  - #1: the turn could wedge on a live hung holder (§5.2 I2: bounded network, a watchdog, the
    waiter fallback);
  - #2: model v1 flattered the combiner (v2: E's interference law, full-suite Phase A; the targets
    were re-set);
  - #3: non-code lands waited 9.7 min in a plain FIFO (priority; the detached turn);
  - #4: heartbeat takeover of a live holder (dead-pid-only);
  - #5: content-inferred crash recovery (the write-ahead journal);
  - #6: adoption off the clean path (three cases).

  The structure of the recommendation survived; its numbers moved.

**What would move it above 90%:**

- The Phase 1 harness in stub mode reproducing v2's curves: collapse between N=6 and N=15 on
  today's lane, the Phase 2 lane's ~29 lands/h keyed ceiling, and the non-code priority figures.
- The real per-session land cadence measured at 15 concurrent sessions.
- The keyed suite factor measured (the model assumes 0.6× from D's 53% test-phase share).

If cadence at 15 sessions proves slower than ~45 min, Phase 2 alone carries the target (p95 9.8 min
modelled) and Phase 3 waits on its trigger. The design does not change; only its timing does.

**Four rulings, each amending a standing reso decision. None blocks Phase 1:**

| # | Decision | Conviction | Evidence / options |
|---|---|---|---|
| **R1** | Make the land-time suite the **full** suite (one run) instead of the union (the 2026-09-14 ruling), so the pre-push hook can skip on a `mode=full` record as W3b was designed | 93% | Union ≈ full in cost (D, E); today both run (B2); the only full-suite check before trunk *is* the hook (B10). Option B: keep union + build W3b as designed; it changes ~6% of lands (B2 §0.3) |
| **R2** | Let the 23 shell-out specs be keyed on declared inputs, so a verdict record may certify "full minus specs whose inputs this range does not touch" | 85% | 140–170 s per code land (D). In v2 it is the largest lever after serialization: without it, every design's p95 roughly doubles at N≥15 (§4.3). Risk: an undeclared input. Guard: a lint, plus a weekly unkeyed full run whose disagreements are logged. Option B: keep them unconditional and pay the time |
| **R3** | Amend V3 invariant 4 / §8's "no merge queue" to admit an **on-box, synchronous** combiner (Phase 3) | 85% | §4.3–4.5; C3's triggers; I4 answers the daemon objection. Option B: stay on the Phase 2 lane and accept its ceiling: ~29 lands/h keyed, so p95 46 min at N=25 × 30 min (~21/h and 82 min unkeyed) |
| **R4** | Flake policy vs invariant 6 ("never re-roll a red until it comes up green", `learnings.md:2567`): one isolated re-run on the identical tree, **every such event recorded** in a flake ledger, and a spec that flakes twice in 7 days is quarantined with an owner | 80% | 5 of 15 reds went green on the identical tree and 14 of 15 were not caused by the diff (H1). Today the *session* re-rolls silently, which is less honest than a recorded single re-run. Option B: eject the whole batch on any red (H1's "honest queue"). Measuring the per-spec flake rate in Phase 1 decides it |

---

## 9. Adjacent findings (outside the land-path design; each has an owner)

| Finding | Evidence | Owner |
|---|---|---|
| **`/deploy` will start refusing in ~4–5 days** unless a green stamp is minted: it searches only `--max-count=200` for a green ancestor, 111 of 200 are used, and trunk gains ~20 commits/day | `deploy-release.sh:57`; B2 §a; W4a scheduler and W4b window fix unbuilt | reso / operator (`/deploy` is theirs) |
| **reso's postland verifier is not scheduled** (3 stamps / 77 lands) | B2 §0.2; D §A1 | reso (V3 W4a) |
| **claude-infrastructure tooling contends for `index.lock` inside reso worktrees**: `git status` without `--no-optional-locks` in `statusline.sh:309`, `cc-husk-sweep:259`, `operator-readout.sh:1475`, `teammate-checkpoint.sh:294`, `waiting-recycle.sh:1136`. The likely cause of the false "already upstream" stop | B1 §2.4 | this repo |
| `ship-reconcile.sh:57-58`'s sequencer-recovery check tests `.git/sequencer` literally, which never exists in a linked worktree | B1 S6 | reso |
| `land-tools.sh` R1: a concurrent fresh materialise can `rm -rf` a sibling's live target, leaving the box with no hooks, silently | B1 §4 | reso |
| Only `ship-land.sh` is pinned to trunk's copy; `ship-reconcile.sh`, `cc-sem.sh`, `mem-leash.sh` and `land-lock.sh` run the *branch's* copy | B1 §4 | reso (the combiner removes it by construction) |
| `window-named-properties.test.ts:4` imports a generator whose unguarded `main()` rewrites the committed JSON, so its staleness check can never fail | C | reso |
| `postland-verify.test.ts:82,96` fetch the shared `origin/main` ref | C | reso |
| The "stamps keyed on pre-rebase shas" lesson is an instrument artifact: `--is-ancestor` on a *tree* exits 128, and all 30 newest stamps' commits are on trunk | F §6.1 | this repo (`docs/lessons/verdict-store-keyed-on-shas-the-subject-never-carried.md`) |

---

## 10. Method and evidence

- **Census:** `land_census.py` over `~/.reso/land.log`, window pinned (the log is live).
- **Model:** `landsim.py` **v2** (policies P0–P5, PS) + `scenarios.py` (validate, phases, keyed,
  sensitivity, admission, law); `run_model.sh` re-derives `model_output.txt`. v1, which the
  red-team corrected, is preserved in this directory's first commit, and `scenarios.py law`
  reproduces the one change that mattered most (v1's load1 term vs E's interference law).
- **Push-protocol reproduction:** two local repos and a sleeping pre-push hook (§3.1); ~30 lines of
  shell, re-runnable anywhere.
- **Per-axis reports** in `reports/`, each written by a research subagent from primary sources:

| Report | What it covers |
|---|---|
| A-merge-queue-literature | Bors, Zuul, GitHub MQ, Mergify, Aviator, Graphite, Trunk, SubmitQueue, TAP, CQ; batch math; failure modes |
| B1-reso-landtime-mechanics | reconcile, cc-sem, land-tools, land-lock, pre-push |
| B2-reso-downstream-roadmap | what consumes trunk; V3 status; reso's recorded decisions C1–C14 |
| C-test-concurrency-census | test hazards and a lint proposal |
| D-suite-cost-profile | full / union / always-run costs, slowest specs, tsc |
| E-load-capacity | the inflation law, CPU per land, capacity knee |
| F-claude-infra-contrast | this repo's lane as an empirical control |
| H1-contrarian-cas-suffices | devil's advocate with an independent simulator; scripts in `reports/h1/`, archived as run (their paths point at the original scratch directory; `graph.py` regenerates the pickled import graph) |
| H2-hostile-reviewer | 11 ranked blind spots, 15 refuted |
| wave2-redteam (+ `wave2-redteam-probe.py`) | a red-team of the first draft on a different model; six defects, all fixed (§8) |

- **Not done, deliberately:**
  - No reso unit-test run. The box sat at load 200–270, so a run would have measured the contention
    and added to it. Hundreds of logged runs (land.log, verifier logs, vitest result caches) served
    instead.
  - No load test pushing to origin, and no edit in reso.
