# F: how claude-infrastructure handles concurrent landers, and what transfers to reso

**Vintage.** claude-infra `origin/main` @ `7f369183c` (worktree `research/reso-landing-arch`).
`~/.claude/land.log` snapshot 2026-09-23T05:05Z, 11,894 rows. The **7d window** is 2026-09-16 → 09-23.
Every land.log figure below is my own parse of the raw store. It follows `scripts/gate-red-census.sh`'s pinned denominator rules: invocations are keyed on the presence of `"tool":"ship-land"` (trap 1), and `stage:"round"` rows are excluded from attempt denominators (trap 5).
The reso files cited were read read-only in `/Users/chrisren/Development/reso-management-app`, which is on a **detached HEAD at `0c0b1b37c` (2026-09-22)**. I did not verify that this checkout equals reso's `origin/main`.
Tags: **[E]** = empirical (measured or cited) · **[R]** = reasoned.

---

## 0. Five findings that decide the reso design

1. **The lock is dead ground here. Stale optimistic rounds are the whole cost.** [E]
   - In the CAS lane, lock hold is p50 3s and wait is p50 0s / p90 1s.
   - 44% of the rounds that reach the lock are stale (exit 42): 293 stale vs 374 landed in 7d.
   - A round's stale probability climbs with its length: **0.16 at 2-4 min → 0.37 at 4-7 → 0.52 at 7-10 → 0.66 at 10-15 → 0.84 at 15-30 min** (n=1,124 rounds, 14d).
   - Reso's verify window (p50 419s) sits exactly where this curve is steepest. Every second of suite kept inside reso's CAS window buys stale rounds.
2. **Claude-infra's round bound terminates. Reso's does not force progress.**
   - Claude-infra: 3 rounds, then an in-lock re-gate that no sibling can invalidate. Taken by **8.8% of successful lands** (33/374, 7d) [E]. `ship-land.sh:5326-5341`.
   - Reso: 5 rounds, then **exit 8 with nothing landed** (`reso scripts/ship-land.sh:921-946`) [E].
   - The fallback only works because every on-box lander honours one mutex [R]. And its own price is measured: **fallback-lane hold p50 184s, p90 299s, max 519s, vs 3s in the CAS lane**. The ratchet arms grew and ran inside the lock [E].
3. **Much of the latency is not the land itself.** [E]
   - Per invocation: `total_s` p50 873s, p95 3,786s, p99 4,756s (7d, n=374).
   - Time-to-trunk (start → lock release after content-verify) is only **p50 276s / p95 3,002s**.
   - The gap is a post-release tail: **lock release → attest** grew 84s (W33) → 619s (W39). That is 60-70% of a clean land.
   - The tail is O(refs): `stranded-sweep.sh:195` runs `git cherry` over **all 3,031 local branches**, 2,531 of them `ship/backup-*`. I sampled 0.17s per branch at load 156-207, which gives ≈8.5 min.
   - v2's target (R1: p50 ≤ 30s, p99 ≤ 3 min, `LAND_PIPELINE_V2.md:212`) **was never met**. It was not even measurable until 2026-08-11.
4. **The one queue-shaped path this repo runs is exactly where rebase conflicts concentrated.** [E]
   - The path is the re-land retry of failed lands, drained later.
   - Exit 5 ran at 13-33% of terminal attempts in W33-W36. It was carried by retry storms on aged `claude/fire-*` branches: W35 had 40 of 41 conflicting branches in that class, and only 9 ever landed.
   - One branch retried 112× over 5 days because ship-land discarded rerere resolutions (`b5f685081`).
   - This is the residency law (conflicts climb with branch age) confirmed in this repo's own ledger. After the fixes, W39 has 4 exit-5 rows. For reso: any design that holds a branch before landing (a queue, batch, or window) inherits this.
5. **One lock transfer is concrete.** [E]
   - Reso's dead-holder reap is a bare rename (`reso scripts/land-lock.sh:88-110`).
   - Claude-infra rejected exactly that design in writing: *"A rename-claim does not fix it either: A renames the dead lock away and recreates it, and B's rename then carries off A's LIVE lock"* (`scripts/land-lock.sh:379-384`). Its reap mutex plus generation re-check closed a reproduced **3-simultaneous-holders** race (`land-architecture-100p-2026-08-10.md:145-150`).
   - Reso only takes the lock for drizzle ranges and the v1 kill switch, so exposure is small but not zero.

---

## 1. The concurrency model at the push

- **Two levels.** [E]
  - (i) A **per-repo mutex** on this box, keyed on `--git-common-dir` so every worktree collides (`scripts/land-lock.sh:13-19, 47-57`). It is taken with `mkdir` and records `pid+lstart` holder identity. Rule H2: never reap a LIVE holder at any age; page instead (`land-lock.sh:204-231, 331-362`).
  - (ii) **The remote's non-ff rejection is the only global arbiter.** Cloud VMs push straight to origin and bypass the `/tmp` lock (`land-architecture-100p:127-133`, G2 hostile iii). Their collisions surface as exit 7, or as a failed content-verify followed by bounded auto-retry.
- **Optimistic CAS, adopted 2026-07-25** (`docs/research/land-gate-serialization-2026-07-25.md:31-56`). [E]
  - Unlocked: fetch → rebase → gate, recording `GATE_BASE` and `GATE_HEAD` (`ship-land.sh:4762-4806`).
  - Locked child (`ship-land.sh:4810-4851`): a last-moment bounded fetch, then the check `origin/main == GATE_BASE ∧ HEAD == GATE_HEAD`.
  - If the check fails: exit 42, release, re-rebase and re-gate unlocked.
  - If it passes: push, `land-verify.sh` content-verify, a bounded auto-retry of 2, and rollback (`:4880-5015`).
  - Round loop: `ship-land.sh:5287-5324`.
- **Termination.** After `SHIP_LAND_GATE_ROUNDS` rounds (default 3), the land takes an in-lock rebase plus statics+ratchets re-gate that cannot be invalidated (`:5326-5341`). `run_gate` refuses to start any bats suite while `IN_LAND_LOCK=1`, in both lanes.
- **What a land proves.** The land proves no full suite: `GATE_EFFECTIVE_FULL=0`, and `stamp_gate_green` does nothing (`ship-land.sh:123-125, 283-286`). The full corpus runs once per trunk tip in a singleton post-land verifier (`postland-verify.sh:3-16`). **Deploy, not land, waits for green.**
- **The hot path is a verify window, not a queue.** 7d lock-queue depth: 0 on 665 acquisitions, 1-3 on 111 [E]. Concurrent distinct-worktree lands per minute: mean 4.2, p90 8, max 10 (`~/.claude/autonomy/briefs/land-gate-concurrency-RESEARCH-2026-09-09.md:76-84`). Once, 25 concurrent shippers were observed (`shipland-reland-row-explosion-2026-09-09.md:53`).

## 2. Measured latency, throughput, and whether the targets were met

| Metric (7d unless noted) | Value | Source |
|---|---|---|
| Successful lands | **374 (53.4/day; peak 79 on 09-20)** | land.log parse |
| Terminal attempts | 636: exit 0 58.8% · 6 (gate red) 25.0% · 11 (double-fire refused) 5.7% · 143 (SIGTERM) 3.9% · 5 (rebase conflict) 2.7% · 9 (gate killed) 1.3% · other 2.5% | land.log |
| `total_s`, per invocation, landed | p50 **873s** · p90 2,867 · p95 **3,786** · p99 4,756 · max 9,972 | land.log |
| Time-to-trunk (start → lock release) | p50 **276s** · p90 1,999 · p95 **3,002** · p99 3,925 | land.log, lock row joined to tool row |
| Per unit (first attempt → landed, chaining failed attempts ≤48h) | p50 968s · p90 3,722 · p95 **6,041** · p99 18,514. 71% land on their first invocation | land.log |
| Rounds per landed change | 1: 65.5% · 2: 17.9% · 3: 7.8% · 4 (fallback): 8.8% | land.log |
| Marginal cost per extra round (p50 `total_s`) | 1 round 761s · 2: 1,339 · 3: 1,867 · 4: 3,546. Earlier measurement: "a four-round land is 8.6x a clean one" | land.log; `ship-land.sh:85-90` |
| P(stale \| reached lock) | **0.44**. A geometric model with p=0.44 predicts rounds 1/2/3/4 at 0.56/0.25/0.11/0.085; measured 0.655/0.179/0.078/0.088, so rounds are roughly independent | land.log [E]; model [R] |
| Lock hold, CAS lane / fallback lane | p50 3s, p99 152s / **p50 184s, p90 299s, max 519s** | release rows joined to tool rows |
| Lock wait | p50 0 · p90 1s · p99 336s | land.log |
| `gate_s`, 1-round lands | p50 216s · p90 485s. Ratchet arms `gate_arms_s` p50 161-228s in W38-W39 (were 619s in W37) | land.log |
| Verifier (post-land full suite) | 40 stamps/7d. `run_s` p50 **11,302s (3.1h)**. 27 red · 6 green · 6 cut · 1 hung. ~693 suites | `~/.claude/autonomy/postland/stamps` |

**Weekly trend** (landed lands):

| Week | Median land (total_s) | p95 total_s | Median gate time | Median ratchet-arm time | % needing >1 round | Median post-release tail |
|---|---|---|---|---|---|---|
| W33 | 286 | 739 | 168 | 126 | 15% | 84 |
| W34 | 402 | 887 | 163 | 115 | 6% | 182 |
| W35 | 478 | 1,910 | 254 | 134 | 12% | 210 |
| W36 | 713 | 3,381 | 419 | 299 | 32% | 283 |
| W37 | **1,280** | **5,105** | 844 | **619** | **52%** | 374 |
| W38 | 747 | 3,711 | 240 | 161 | 28% | 471 |
| W39 | 1,059 | 3,547 | 365 | 228 | 39% | **619** |

- **W37 → W38.** The `--selftest` memo (`78e39b2fb`, 09-09) and the pipefail per-file memo (`d3a34c0d0`, 09-11) cut median ratchet-arm time from 619 → 161s. The share of lands needing more than one round fell from 52% → 28% [E]. That is the only latency lever with a measured effect this month.
- **Targets.** [E]
  - **R1** (p50 ≤ 30s, p99 ≤ 3 min, load-indifferent; `LAND_PIPELINE_V2.md:212`) and **§7 acceptance** (the first 20 v2 lands at the same bounds, `:752`) were **never met**.
    - `land.log` carried no duration until `514c921e9` (2026-08-11). *"The criterion was narrated for v2's entire life"* (`land-architecture-100p:1031-1035`).
    - First measurable week, W33: p50 286s, which is **9.5x** the target.
    - Today: p50 873s (29x) and p99 4,756s (26x). Time-to-trunk: p50 276s (9x).
  - §7 "wait_s ≈ 0" **is met**. "Zero exit-9" is **not**: 8 in 7d.
  - From the 100p gap list:
    - P1 (hold ≤ 5s) is met for the CAS lane only.
    - P2 (gate-red ≤ 10%/day) is **not met**: 25%/7d, 18.4% in W39.
    - P3 (re-round ≤ 10s) was declared unreachable by its own implementer (`land-architecture-100p:622-633`).
- **Throughput headroom.** At a 3s hold the mutex caps out around 28,000 lands/day [R]. The binding term is stale-rounds × round cost plus the gate-red loops, not serialization. The 1,280s median week is when both peaked.

---

## 3. (a) Mechanism table

| # | Mechanism | file:line | What it does | Measured effect | Transfers to reso? | Why |
|---|---|---|---|---|---|---|
| 1 | Repo-keyed land mutex | `scripts/land-lock.sh:13-19,47-57` | Serializes on-box landers across all worktrees | v1 pre/post split: wait p90 1,961 → 77s; exit-75 starvation 19 → 0 (`land-architecture-100p:221-225`) | **No** (reso already chose the stronger form) | Reso measured its old whole-pipeline lock at 49% overlap, max 4 simultaneous holders, 27 live steals over 277 lands, p95 wait 28 min, and dropped it for remote CAS (`reso ship-land.sh:14-24`). The remote is the true global arbiter here too (G2 iii) |
| 2 | Lock covers only fetch → CAS → push → verify | `ship-land.sh:4810-4851, 5017-5023`; P1 `145fab7d` | Nothing heavy inside the critical section | Hold 72s → 3s (`LAND_PIPELINE_V2.md:30`); 7d CAS-lane p50 3s | **Adapted** | Reso has no lock, but the principle maps onto its **CAS window**. Reso's pre-push hook runs the full suite *inside* the push (`reso ship-land.sh:895-897`), so the whole suite sits between base-read and remote update. Claude-infra's curve (§0.1) says every suite-minute in that window raises P(stale) [R] |
| 3 | Bounded rounds + un-invalidatable fallback | `ship-land.sh:5291-5341` | 3 optimistic rounds, then an in-lock statics+ratchets re-gate that cannot be invalidated | 8.8% of lands take it; the 3h10m "livelock" was 3 rounds x ~60 min, bounded (`docs/lessons/optimistic-round-cannot-outrun-its-contention.md`); `SHIP_LAND_GATE_ROUNDS=0` turned a 3h livelock into a 27-min wait | **Adapted** | Reso's exhaustion arm fails the land (exit 8). Forced progress needs a round nobody can invalidate, which needs a lock all on-box landers honour, taken **only on exhaustion** (reso already has the narrow drizzle-mutex shape). The work inside it must stay O(seconds): claude-infra's fallback degraded to a 184s p50 hold as its ratchet arms grew [E] |
| 4 | Content-verify after push, bounded auto-retry, rollback | `ship-land.sh:4880-5015`; `scripts/land-verify.sh` | Checks every landed path is content-identical on trunk; a drop triggers re-rebase, re-gate, re-push, at most 2 retries | Closes the `dfacccd` drop class (`SHIP_LAND_HARDENING_PLAN.md:26-41`) | **Yes (present)** | Reso has `content_verify` (`reso ship-land.sh:875`). Keep verifying by content; a count reads 0 after a sibling rebase |
| 5 | Backup ref + stranded-sweep | `ship-land.sh:5265-5274`; `post_release_finish` `:1600-1675`; `stranded-sweep.sh:195-214` | Rollback point per land; post-land scan for dropped commits | **Cost regression:** the post-release tail grew 84 → 619s p50 as local branches reached 3,031, of which 2,531 are `ship/backup-*` | **Adapted** | Keep the backup ref. Never run an O(refs) scan on the land's wall-clock: scope it to your own anchors (`--mine`), or run it off-path |
| 6 | Atomic dead-holder reap | `land-lock.sh:370-412` (reap mutex + generation token incl. inode + staleness re-check) | Only one reaper deletes, and only the exact dead lock it judged | Fixed 3 simultaneous holders from 6 concurrent acquirers on one dead-pid lock (`land-architecture-100p:145-150`, `145fab7d`) | **Yes** | Reso's `try_acquire` reaps with a bare `mv` (`reso land-lock.sh:88-110`). The comment "Lost the rename ⇒ another thief won" (`:103`) holds only if B renames before A's `mkdir`. Otherwise B carries off A's live lock [R], the race claude-infra names at `:379-384` |
| 7 | Pinned `lstart` dialect (`TZ=UTC LC_ALL=C`, trimmed; unreadable ⇒ honour holder) | `land-lock.sh:120-168` | A cross-locale reader can no longer mistake a live holder for a recycled pid | Same pid renders differently under the session's LANG vs launchd's `LC_ALL=C` (measured 2026-08-21) | **Already in reso** | `reso land-lock.sh:28-30,69,78-86` pins the same dialect |
| 8 | Union scope + own-set attribution | `ship-land.sh:180-183, 289-293, 2402-2421, 2576-2596` | A re-round smokes own diff ∪ the sibling delta; a red from the sibling delta still blocks but is labelled "NOT a verdict about your code" | Fixed "fix it, do not retry unchanged" misdirecting landers at a sibling's already-filed red (`fb178d6d8d14`, `ccfdd36fa`) | **Yes** | Reso runs a union suite (`reso ship-land.sh:502-534`). Without own/sibling attribution, a red trunk turns every mid-gate sibling land into a false conviction of the next lander (`:2587-2590`) |
| 9 | Per-file verdict memo (blob + checker version + config-by-value; rc 0 only; store shared in `<git-common-dir>`) | `scripts/lib/gate-memo.sh:23-35, 101-123`; `ship-land.sh:3125-3181` | Carries earned greens across rounds and across worktrees; unknown ⇒ miss | Statics 2.2s → 0.14s, 0.1% of cost (the wrong term, `land-architecture-100p:622-633`); selftest + pipefail tiers took median arm time 619 → 161s; 688,633 entries, **no eviction** | **Adapted** | Per-file keying fits lints, not a vitest suite. **The invariant transfers:** reso's per-tree presubmit token records `env_sig` "Recorded, not matched" (`reso ship-land.sh:793-795`). Claude-infra's `.shellcheckrc` incident (identical blob and salt across an rc 0 → 1 flip, so "a red lands green") is why config and environment inputs are hashed **into the key** (`gate-memo.sh:101-123`). A tree key also misses on every CAS re-round: a rebase onto a moved trunk always changes the tree (`land-gate-serialization:96-97`) [E] |
| 10 | `--precheck` shift-left | `ship-land.sh:8-27, 5028-5056` | Same `run_gate` on the same range; no lock, no row, no ref, no push; shares only the rc-0 memo | Gate-red is 25% of terminal attempts (7d). Each red costs a full land cycle, and precheck finds it without one | **Yes** | One implementation, two entry points. Never a second authority (`:5037-5044`) |
| 11 | Singleton post-land verifier; tree-keyed stamps; only a real verdict skips a re-run | `postland-verify.sh:3-16, 4062-4074`; stamps `~/.claude/autonomy/postland/stamps/<tree>.json` | The verifier checks the trunk tip only (post-land batching), bisects a red, auto-reverts the culprit; a CUT re-runs, green/red/hung skip | Cycle 3.1h p50 (7d), 15% green. Auto-revert only 12% successful at one point; 30.3% of consecutive convictions alternate A/B, and an innocent revert was stopped only by a conflict (`land-architecture-100p:1110-1116`) | **Already in reso (shape)** | Reso's `stamped()` already uses verdict polarity (`reso postland-verify.sh:221-225`), so the comment at `reso ship-land.sh:776-777` looks stale. Import instead claude-infra's two-load-window corroboration before minting a RED (C29; `LAND_PIPELINE_V2.md:508`) |
| 12 | Smoke load shed (skip at load ≥ 8/core) + land gate exempt from cc-bats admission | `ship-land.sh:115-121, 1906`; `:2213-2247` | Never waits; skips the suite and still lands, relying on the verifier | Smoke `skipped`/`none` on 41-67% of lands per week (W33-W39). cc-bats rc-75 refusals had been 1,045 flake rows, 56% of all (`:2218-2222`) | **No** for the shed; **yes** for "refuse, never wait" | The shed is safe only because a verifier plus auto-revert backs it ("LANDED ≠ TESTED", `docs/lessons/a-landed-verdict-is-not-a-tested-verdict.md`). Reso's pre-push suite is its pre-land proof. Reso's `cc-sem reso-land` refusal (exit 10) already has the right polarity |
| 13 | Signal trap + attest-every-exit + in-flight marker + failure inbox | `ship-land.sh:5346-5353, 1413-1453, 887-929` | A killed land attests `128+N`; a second `/ship` on a worktree is refused (exit 11); failures write `refs/land/failed/*` plus a re-land row | Exit 143 was 13-17% of terminal attempts in W33-W37 (e.g. W33: 182 rows over 46 branches), 3.9% now; exit 11 is 5.7% of attempts. Pre-P4, killed lands recorded nothing (`LANDING_GATE_ROOT_CAUSE:21`) | **Yes** | Harness process-group kills, outer `timeout` wrappers, and TERM→KILL sweeps all recur for any bash lander run from agent sessions |
| 14 | Bounded in-lock network (exit 10 = machine verdict, retryable) | `ship-land.sh:399-470` (`git_net` `:434`) | A hung fetch/push cannot wedge the mutex, and is never read as a red | Closed the "live-hung holder wedges the box" defect (`land-architecture-100p:156-158`) | **Already in reso** | Reso's push timeout returns 12, TERMINAL. It used to read a timeout as transient, and that was its "five-round loop" (`reso ship-land.sh:893-907`) |
| 15 | 6 vs 9 exit vocabulary (tree verdict vs machine non-verdict) | `ship-land.sh:127-143, 3040-3123` | "Fix your tree" vs "retry when quieter" | Collapsing the two drove the 2026-07-26 kill → "RED" → dispatcher-retry runaway (`f8e40b4c577d`) | **Yes** | Any suite in reso's land path needs the same split, and must assert the `1..N` plan line: a deferral has zero `not ok` |
| 16 | Re-land row identity per branch + rerere-aware rebase | `017650872`, `aa1886a5e`, `b5f685081`; `rebase_onto_trunk` `ship-land.sh:4664` | One row per stuck branch; a rerere-resolved conflict continues instead of exiting 5 | Before: 41 rows for one branch; 789 failed lands threw away rerere's resolution; one branch retried 112× | **Yes, if reso adds any retry drain** | Otherwise the drain becomes the conflict generator (§0.4) |

---

## 4. (b) Decisions and rejected alternatives, quoted

| Alternative | Verdict | Quoted reason | Ground still valid? |
|---|---|---|---|
| **Speculative merge queue (Zuul/bors batching)** | Rejected | *"solves throughput but keeps latency ≥ corpus-time (fails R1) and keeps N-corpora concurrency (fails the load reality). Post-land + revert dominates on a single box with a trusted-author fleet."* (`LAND_PIPELINE_V2.md:761-763`) | **Decayed.** The corpus left the land two days later (`D-decisions.md:233-235`). Re-rejected on residency (below) |
| **Batching / windowing / speculation at land time** | Rejected 2026-08-10 | *"Batching exists to amortise a ~30-min CI gate and is paid for with bisection/ejection machinery … both levers are worthless here"*; *"batching also breaks auto-revert's culprit-granularity (an innocent author gets reverted with the guilty one)"* (`land-architecture-100p:445-450`) | **Economic ground decayed:** "0-second median gate" (`H-sota.md:72,79-87`) vs median ratchet-arm time of 623s on 09-09. **Residency and attribution grounds stand** (next row) |
| **Any residency-adding design** (queue, batch, window, speculative tree) | Rejected | *"conflict rate 55% at <6h → 78% at 6-24h → 91% at 24-72h → 95% at 72-168h … Any residency-adding design converts ~0% into 55-91%"* (`land-architecture-100p:451-457`; table `H-sota.md:106-111`, an upper bound because it includes dead branches) | **Confirmed by later data:** the exit-5 wave of W33-W36 sat on re-landed aged branches (§0.4) |
| **Two-phase / intent lock** (a delegated push-only writer) | Rejected, on correctness | *"the rebase must sit in the same critical section as the push or the 2026-07-11 race reopens; with the CAS design the 'rebase' inside the lock is the degenerate check that no rebase is needed"* (`land-gate-serialization:98-100`) | Yes |
| **Ticket-lander daemon** (single lander) | Ranked second, not adopted | *"the only design where a dead author is a non-event, but dies on launchd fragility … a wedged lock today starves one session, a wedged lander stops the fleet"* (`land-architecture-100p:467-473`). Only its **inbox half** was adopted (`:475-478`) | Yes |
| **Landing broker** | Never considered; priced | *"a protocol rebuild, not a purchase"*, aimed at a lock at 0.7-4.8% utilization (`D-decisions.md:324-330`) | Yes |
| **Built single landers** | Live, synchronous | `desk-land.sh` (delegated, "SYNCHRONOUS by design"); `cloud-reconcile.sh` (serialized multi-branch drain: smallest-diff-first, continues past failure, landedness by content, default-off behind `CONFIRM=1`) (`C-priorart.md:28-29`) | n/a |
| **Gate-concurrency semaphore** | **Built, tested, forbidden** (`refs/proposals/gate-slot-semaphore` = `3d052701`, 602 insertions) | *"It would queue 45 minutes to protect 29 seconds"*; *"Fail-open makes it buy latency, not protection"*; *"It loses on subject size, not on mechanism — the reasoning is reusable if a corpus ever returns to the land"* (`land-gate-serialization:297-332`) | **Reopen condition met on 09-09** ("the arms are the returned corpus"). Kept as a contingency, below the memo (`land-gate-concurrency-RESEARCH:107-137`). **Directly relevant to reso**, which does run a suite in its land path |
| **Load-keyed admission (`gate_admit`)** | Deleted; its absence is test-asserted | *"five concurrent gates sat at load 16-18 waiting for a ceiling of 8 while their own corpora were the load"*; R7: *"Shedding = SKIP … never wait-then-run-anyway"* (`land-gate-serialization:220`; `LAND_PIPELINE_V2.md:235-237`) | Yes |
| **Gate in the lock (v1)** | Structurally forbidden | *"a held machine-wide mutex plus a 20-53 min corpus produced a 3h36m lock holder … a multi-day jam"* (`ship-land.sh:4820-4823`) | Yes |
| **CAS optimistic rounds** | **Adopted** 2026-07-25 | *"the GATE proves the FINAL rebased tree green; the LOCK covers ONLY the race window"* (`land-gate-serialization:33-34`) | Its cost premise, *"a stale-gate re-round is seconds … a rounding error"*, is **refuted** (`ship-land.sh:77-99`: arms p50 137s / p99 2,842s; 149/294 rounds stale on 09-09, burning 34.1h of arms for zero lands) |
| **Retry reuse** (a stale re-round reuses the prior round's passing suites) | Rejected | *"arm-level keying skips only 27-46% of re-rounds"*; *"strictly dominated"* by a per-file memo that also serves siblings' first rounds (`land-gate-concurrency-RESEARCH:172-188`) | Yes |
| **Whole-gate verdict cache** (trunk sha, diff hash) | Rejected | *"N landers on one trunk sha do not share a verdict — each has a different diff"*; red-laundering via unkeyed inputs (`:139-157`) | Yes. Reso's per-tree token is this shape |
| **Changed-file-scoped gate as proof** | Rejected as proof; shipped as best-effort smoke | *"unsound here (tests read docs; semantic coupling is unmapped)"* (`land-gate-serialization:88-91`); v2 *"escapes it by changing what the selection is for"* (`:221`) | Yes |
| **Second Mac / off-box CI for the verdict** | Rejected | host-coupled corpus; *"a protocol rebuild, not a purchase"*; the real lever was a $0 plist key, worth ~3x (`LAND_PIPELINE_V2.md:800-918`) | Yes |

---

## 5. (c) Failure modes this repo hit that a reso lander must pre-empt

| Failure mode | claude-infra evidence [E] | Reso exposure | Pre-emption |
|---|---|---|---|
| **Livelock by invalidation**: a round is longer than the quiet gaps between sibling lands | 3h10m land = 3 rounds x ~60 min; 0 of 21 trunk gaps ≥ 60 min (`optimistic-round-cannot-outrun-its-contention.md`). P(stale) 0.16 → 0.84 across 2-30 min rounds | Full suite inside the CAS window; 5 rounds; exhaustion = exit 8 | Shrink the window, not the retry count. Ask whether any gap histogram bucket fits one round; give exhaustion a forced-progress arm |
| **Corpus silently re-entering the land path** | Ratchet arms are O(corpus): 218 → 626 suites; median arm time 112 → 623s while the design still called a re-round "seconds"; no cost ratchet (`land-gate-concurrency-RESEARCH:86-98, 346-351`) | Pre-push full suite grows with the vitest corpus | A wall-clock budget on the in-window phase that goes **loud**, never sheds |
| **Load amplification under concurrent landers** | Median arm time 356s with 0-1 concurrent landers → 1,080s at 8-9, a knee at N≈5 (`:63-74`) | Unlocked suites across N sessions | Count-keyed refusal (cc-sem), never a wait |
| **The fallback becomes the convoy** | Fallback hold p50 184s / max 519s vs 3s; waiters queued behind it go stale (P(stale\|waited) 95.8%/1d, `land-architecture-100p:1009`) | Any future forced-progress lock | Only O(seconds) work inside it |
| **Lock steals / double holders** | Non-atomic reap → 3 simultaneous holders; cross-locale lstart → a live holder reaped (`land-lock.sh:120-153, 379-384`) | Reso fixed the TTL steal (27/277) and the dialect; **the rename-reap race remains** (`reso land-lock.sh:103-106`) | Reap mutex plus generation (inode) re-check inside it |
| **Rebase-dropped commits / count-based "landed"** | `dfacccd`: `rev-list --count == 0` read as landed after a sibling's rebase (`SHIP_LAND_HARDENING_PLAN.md:28-35`); a rebased land rewrites objects, so `--is-ancestor` on a cited pre-rebase sha is rc 1 over content that did land (rules `:60`) | Present, and mitigated by content_verify | Verify by path content on trunk, never by count or pre-rebase sha |
| **Phase-budget kills read as reds** | One budget cut named a different suite each run with zero `not ok`, and was reported as "a VERDICT about your diff" (`docs/lessons/a-phase-budget-cut-names-a-different-suite-each-run.md`); the killed pre-push suite was reso's own old five-round loop | Push timeout (`LAND_PUSH_TIMEOUT`) is a phase budget | A kill is a non-verdict (reso's exit 12 is right). Assert the plan line; re-run and compare the named suite |
| **Killed lands leave no trace** | Exit 143 at 13-17% of weekly attempts; no signal trap pre-P4; outer `timeout 900` killed a clean land at 936s (`never-wrap-ship-in-your-own-timeout.md`); TERM→KILL sweeps killed ≥11 gate drivers (`LANDING_GATE_ROOT_CAUSE:57`) | Same harness and same agents | Trap and attest; failure inbox; in-flight marker; no outer timeout |
| **The worktree mutated under an in-flight land** | A tracked-file edit re-armed the rebase refusal after 444s of queueing; removing the worktree turned every git call into exit 128 (`never-write-a-tracked-file-while-ship-is-in-flight.md`) | Same | The tree belongs to the lander from fire to verdict |
| **Non-verdicts read as verdicts** | cc-bats rc 75 accounted for 56% of flake rows; a cut stamp that skipped re-runs merely by existing stranded trees unverified (`postland-verify.sh:4062-4070`); a deferral has 0 `not ok`; a selector death was read as a lint-only land (`ship-land.sh:2427-2452`) | Any suite, token or stamp in the path | Three-state verdicts; a token is minted only on green (reso already does this, `reso ship-land.sh:771-782`) |
| **Retry drains on aged branches** | Exit 5 at 13-33% of terminal attempts in W33-W36, concentrated on `claude/fire-*` re-lands; 789 discarded rerere resolutions; 41 tickets for one branch | Only if reso adds a retry or deferred-land queue | Dedupe per branch; honour rerere; bound retries; re-land fresh |
| **Unkeyed environment in a verdict key** | `.shellcheckrc` flip made "a red lands green"; `unattended-path-lint`'s verdict depended on the invoker's PATH, so it was excluded from the memo (`ship-land.sh:3155-3162`) | `env_sig` "Recorded, not matched" (`reso ship-land.sh:793`) | Match every verdict-changing input, or do not reuse the verdict |
| **O(refs) housekeeping on the land's clock** | Post-release tail 84 → 619s; 2,531 backup refs | Reso mints `backup/<branch>-preship` (`reso ship-land.sh:814`) | Scope scans to your own anchors; reap on success |

---

## 6. Claims I refuted or corrected during the adversarial pass

1. **The "stamps keyed on pre-rebase shas" lesson is an instrument artifact.**
   - The lesson is `docs/lessons/verdict-store-keyed-on-shas-the-subject-never-carried.md`, hooked at `.claude/rules/agent-operating-lessons.md:233`.
   - Stamp files are named by **TREE** hash; `git cat-file -t` reports `tree` on the newest 6.
   - The lesson's loop runs `git merge-base --is-ancestor <tree> origin/main`, which exits **128** ("is a tree, not a commit"). Its `&& ANCESTOR || not-on-trunk` then read that 128 as "not on trunk".
   - Checked the right way, **30 of the 30 newest stamps' `commit` fields are ancestors of `origin/main`** (2026-09-17 → 09-23).
   - The verifier is tree-keyed by design (`postland-verify.sh:7-8`). The lesson's *principle* stands; its *measurement* does not.
2. **A false premise sits at `ship-land.sh:2224-2229`.** It says *"the gate runs INSIDE [the land-lock], so at most ONE land gate per repo runs at a time"*, and repeats it in `docs/lessons/the-land-gate-is-admission-exempt.md`. v2 gates run **unlocked** (`ship-land.sh:5287-5290`). This was flagged on 09-09 (`land-gate-concurrency-RESEARCH:242-251`) and is still on trunk. So land-gate bats concurrency is **unbounded**: a 7d mean of 4.2 and a max of 10 concurrent landers.
3. **"0 exit-5 in 1,021 v2 lands"** (`H-sota.md:118-119`) did not hold from W33 to W36. It supports the residency law rather than weakening it (§0.4).
4. **The P5 verifier bar "MET: 0.88h"** (`land-architecture-100p:1062`) has regressed to a **3.1h p50** over the last 7d (40 stamps, ~693 suites, 15% green).
5. **The header line "exit 9 now rare — only LANE=v1's corpus can earn it"** (`ship-land.sh:130`) is contradicted: 8 exit-9 in 7d, reachable through `arm_nonverdict → GATE_KILLED` (`:3117-3123`).

## 7. Uncertainties and gaps

- **The tail's split between `ship-backup-reap` and `stranded-sweep` is inferred** from the loop code, a 40-branch `git cherry` sample, and the matching growth curve. I did not time it end to end, and did not run `stranded-sweep` itself.
- **Per-round stale curve bias:** round length is the *gate* delta, excluding the rebase, and trunk movers include off-box pushes and auto-reverts, so it is not a pure function of the land rate. Applying it to reso's ~11 lands/day is **[R]**; only its shape transfers.
- **Reso reads** are from a detached `0c0b1b37c` checkout. I did not locate where reso's pre-push hook *consumes* the presubmit token: a `presubmit` grep over `scripts/` hits only `ship-land.sh` and `presubmit-always.ts`.
- **The reso rename-reap race** comes from reading the code. I did not reproduce it.
- **Not examined:** `deploy-live` convergence detail, or the `cc-dispatch` re-land drain internals.

## 8. Reproduction (read-only)

- **Parse:** `python3` over `~/.claude/land.log`. Invocations: `tool=="ship-land"`. Attempts: `stage!="round"`. Lock rows: `event=="release"`.
- **Joins:** lock row to tool row on (repo, branch), taking the release ≤ 30-60 min before the tool row.
- **Stamps:** `ls -t ~/.claude/autonomy/postland/stamps/*.json`, then `--is-ancestor` on each stamp's `.commit` field.
- **Sweep cost:** `git cherry origin/main <br>` over every 75th of 3,031 `refs/heads` (40 branches, 6.76s) at load 156-207.
