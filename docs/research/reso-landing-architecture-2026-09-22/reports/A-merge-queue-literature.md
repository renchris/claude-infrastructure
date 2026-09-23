# A — Merge-queue literature: concurrency models, batching/bisection/speculation math, failure modes

Wave 1, worker A · 2026-09-23 · for the reso-management-app landing-architecture decision.
The subjects are architectural patterns. Pricing tiers, vendor performance claims and company profiles are excluded.

**Evidence tags:** **[E]** empirical: a measurement from a cited paper or production report · **[V]** documented mechanism: project or product docs describing how a system behaves (not how well it performs) · **[D]** derived here: a formula or simulation, with its assumptions stated.

---

## 0. Findings that bear on the decision

1. **GitHub merge queue is not available for reso's repo.** docs.github.com lists exactly two eligible cases: "any public repository owned by an organization, or … private repositories owned by organizations using GitHub Enterprise Cloud" ([reusable source](https://github.com/github/docs/blob/main/data/reusables/gated-features/merge-queue.md), fetched from `main` today). A User-owned private repo matches neither case. Even where it is available, it is a *speculative-prefix* queue that runs one CI build per PR: "Merge limits do not combine `merge_group` **builds**" ([docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)). Its throughput therefore comes from parallel remote runners, which reso does not have. **[V]**
2. **On one machine, verify capacity is the binding constraint, and only batching raises it.** Throughput is at most `s / (V·c)`, where `s` is how many verifies the box can run at full speed and `c` is verifies per change. Speculation (Zuul, GitHub MQ, GitLab trains, Graphite and Aviator parallel mode) raises throughput only when idle workers exist. On a saturated box it spends CPU on prefixes that later get invalidated. Vitest in run mode "uses all available parallelism" ([vitest](https://vitest.dev/config/maxworkers)), so a full-suite run gives `s≈1`. Uber measured that optimistic speculation's throughput "is limited by the number of contiguous changes that succeed" and stays flat as workers are added ([EuroSys'19 §8.3](https://www.masoud.io/docs/eurosys19.pdf)). **[D]+[E]**
3. **Batching math.** Under Dorfman pooling, verifies per change are `c = 1/b + 1 − (1−p)^b`. The best batch size is `b* ≈ 1/√p` and the minimum cost is `≈ 2√p`. That is a 2.35× capacity gain at p=5%, 1.7× at 10%, 1.2× at 20%, and nothing once p is above roughly 0.3 (Ungar's bound for any group test is 0.38). The empirical record agrees: at Ericsson batching saved 72% of executions, and 42% once flakes were included; with flakes the best batch size fell from 9 to 4 ([Najafi FSE'19](https://users.encs.concordia.ca/~shang/pubs/Armin_FSE_2019.pdf)). Batching pays when fewer than 40% of builds fail ([EMSE'25](https://mcislab.github.io/publications/2025/emse_scale.pdf), citing Beheshtian TSE'21). **[D]+[E]**
4. **reso's current pattern (direct push with a CAS retry) holds up at average load and has a cliff under bursts.** This depends on whether a retry re-verifies (see §2.4; reso's actual retry path is not verified here):
   - **If a retry re-verifies:** a round succeeds with probability `q = e^(−λV)`. In reso's busy periods, `λV = 419 s / 429 s ≈ 0.98`, so q≈0.37: about 2.7 verifies per land, and 10% of landers use up all 5 rounds.
   - **A synchronized burst of 15 landers:** 5 land, 10 give up, and 65 verifies are spent.
   - **Contention makes it worse.** Each verify stretches under load, which widens the CAS window, which causes more retries. That is a self-sustaining collapse, the "metastable failure" pattern ([Bronson HotOS'21](https://sigops.org/s/conferences/hotos/2021/papers/hotos21-s11-bronson.pdf)).
   - **If a retry only rebases and pushes:** landing is fast, but the tree that lands was never verified. Uber measured a 5% chance of a real conflict with 2 concurrent potentially-conflicting changes, rising to 40% with 16. **[D]+[E]**
5. **Flakes set how large a batch can be, and reso's load produces them.** At Google, 1.5% of test runs flake, 16% of tests have some flakiness, and 84% of pass→fail transitions involve a flaky test ([Google Testing Blog](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html)). 46.5% of flaky tests are resource-affected ([RAFT, TSE'24](https://arxiv.org/abs/2310.12132)), and reso verifies at load 50–250 on 10 cores. In simulation, retrying a *singleton* once before ejecting it cut false ejections about 10× (4.3%→0.3%) for about 2% more verifies. It must be switched off near capacity (§2.7). **[E]+[D]**
6. **Recommended pattern, derived and not an industry citation.** A single-owner local batch queue: bors-ng semantics on localhost, or the "flat combining" pattern ([Hendler SPAA'10](https://people.csail.mit.edu/shanir/publications/Flat%20Combining%20SPAA%2010.pdf)). Its rules:
   - Verify the exact candidate (tip plus an ordered prefix), then land it with a fast-forward/CAS push that doubles as the fencing token.
   - Bisect only in prefix-safe form.
   - Set `b_max ≈ 1/√p` (4–8), use load-aware singleton retry, and retry timeouts rather than bisecting them.

   Expected effect at V=419 s and p=5%: capacity about 21.5/h against 8.6/h for a serial queue, and a burst of 15 drains in about 42 min against about 105 min. At V=209 s (tsc plus the full suite, without the union-related step) the drain is about 21 min against about 52 min. **[D]**
7. **Unknowns that decide the numbers:** p (per-change real failure rate at queue entry), f (per-run flake rate), V unloaded, and whether reso's CAS retry re-verifies. Each can be measured from lander logs (§6).

---

## 1. Design table (a)

**"Verify-once?"** means **Y** when the exact tree that lands is the tree that was verified *and* the no-failure path costs at most 1 verify per change. **Y\*** means the landed tree is verified exactly but failures ahead force re-verification. **N** means it lands trees that were never verified as such (a stale base).

| System | Concurrency model | Verify-once? | Failure handling | Constraints / notes |
|---|---|---|---|---|
| **bors-ng** | **Batch.** All r+ PRs are merged into one `staging` commit and tested; the tested commit is fast-forwarded. One staging branch means one batch at a time. [V] ([README](https://github.com/bors-ng/bors-ng)) | Y | Failed batch → `Enum.split(patch_links, div(count, 2))`, both halves cloned as new batches with the lower half first; a single-PR failure → `:failed` ([divider.ex](https://github.com/bors-ng/bors-ng/blob/master/lib/worker/batcher/divider.ex)). **Timeouts are bisected like failures** ([batcher.ex](https://github.com/bors-ng/bors-ng/blob/master/lib/worker/batcher.ex)). `max_batch_size` exists. PRs with different priority are never batched together ([docs](https://bors.tech/documentation/)). | Repo archived: "If you want to implement a workflow like this, use GitHub's built-in merge queue" ([README](https://github.com/bors-ng/bors-ng)). A batch crash left the remaining PRs un-requeued ([#579](https://github.com/bors-ng/bors-ng/issues/579)). |
| **Rust homu/bors + rollups** | **Serial** (one PR per CI cycle), plus rollups: human-curated manual batches. [V] | Y | A failed rollup is bisected by log analysis; the culprit gets `@bors r-` and the rollup is rebuilt. Spurious failures use `@bors retry`. | CI takes about 3.5 h, which "scales poorly". `rollup=never` for large or perf-sensitive PRs ([forge](https://forge.rust-lang.org/release/rollups.html)). |
| **Zuul gate** (dependent pipeline) | **Speculative prefix.** Changes are tested "with the assumption they pass" ([gating](https://zuul-ci.org/docs/zuul/latest/gating.html)). Windowed like TCP: window 20 by default, +1 per merge (linear), ÷2 per failure (exponential), floor 3 ([pipeline](https://zuul-ci.org/docs/zuul/latest/config/pipeline.html)). [V] | Y\* | The failing change is dropped; "each change behind it ignores whatever tests have been completed and are tested again without the change in front" ([pipeline](https://zuul-ci.org/docs/zuul/latest/config/pipeline.html)). Pre-run (infra) failures are retried, `attempts` default 3; main-playbook failures are reported immediately ([job](https://zuul-ci.org/docs/zuul/latest/config/job.html)). | Needs a pool of test nodes. The window shrinks after failures, so recovery is slow (AIMD). Coupled projects share queues. |
| **GitHub merge queue** | **Speculative prefix per PR.** A `merge_group` is base + PRs ahead + this PR. Build concurrency is 1–100, and group min/max size is 1–100 plus a wait time. [V] ([docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue), [rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)) | Y\* | A failing PR is removed from the queue and the groups behind it are re-created. With "only merge non-failing PRs" **off**, a failed PR merges if a later group containing it passes ("useful if you have intermittent test failures"). Jumping the queue causes "a full rebuild of all in-progress pull requests". A status-check timeout assumes failure. | PR-based; requires required checks and a `merge_group` trigger (or `gh-readonly-queue/*` for third-party CI). Wildcard branch rules are not supported. Availability: §4. |
| **GitLab merge trains** | **Speculative prefix**, up to 20 pipelines in parallel by default. [V] ([docs](https://docs.gitlab.com/ci/pipelines/merge_trains/)) | Y\* | The failing MR is removed; pipelines behind it are cancelled and restarted without it. The `retry` keyword absorbs intermittent jobs. "Merge immediately" restarts all pipelines. | PR/MR-based, remote CI. |
| **Mergify** | **Speculative prefix** (`max_parallel_checks`) + **batches** (`batch_size` fixed or `{min,max}`, `batch_max_wait_time`) + "two-step CI" (fast checks before the queue, exhaustive checks in the queue). [V] ([batches](https://docs.mergify.com/merge-queue/batches/), [performance](https://docs.mergify.com/merge-queue/performance/)) | Y\* | A failed batch is split into `max_parallel_checks` parts (at least 2), which are tested in parallel **as prefixes** (e.g. [1,2] and [1,2,3]); a passing first split merges; a singleton that fails is the culprit. `batch_max_failure_resolution_attempts` caps the number of splits. `skip_intermediate_results` treats an earlier failure as transient if a later passing batch contains the PR. | States an "RCV theorem": a queue optimises only 2 of reliability, cost and velocity. |
| **Aviator MergeQueue** | Serial by default. **Parallel mode**: draft PRs over the queued prefix, capped by "max bot builds in parallel". **Batching**: `batch_size` default 1, `batch_max_wait_minutes` default 0. **Affected targets** split the queue into disjoint queues. [V] ([parallel](https://docs.aviator.co/mergequeue/concepts/parallel-mode), [batching](https://docs.aviator.co/mergequeue/concepts/batching), [affected targets](https://docs.aviator.co/how-to-guides/affected-targets)) | Y\* | A failure at the top closes all later draft PRs and restarts the queue without the failing PR. A failed batch goes into "two bisected batches" (5 → 3+2). **Optimistic validation** (default true; `optimistic_validation_failure_depth` capped at 3) waits on later prefixes before ejecting, so "real errors will take longer to be kicked out" ([flaky](https://docs.aviator.co/mergequeue/concepts/managing-flaky-tests-in-mergequeue)). | "Skip the line" resets all parallel PRs. |
| **Graphite MQ** | Stack-aware. **Parallel CI** is speculative ("similar to branch prediction"). Batching is in private beta. Fast-forward merge. [V] ([docs](https://graphite.com/docs/merge-queue-optimizations)) | Y\* | A failing stack is evicted and later runs are cancelled and restarted. A failed batch is isolated either by **full parallel isolation** (the default: every stack tested in parallel) or by **bisection** (fewer runs). | The docs warn that a flake forces restarting "CI runs on any subsequently enqueued PR's". |
| **Trunk Merge Queue** | **Predictive testing** (prefix speculation) + **batching** (target size and max wait; the docs recommend 4 PRs / 5 min). [V] ([batching](https://docs.trunk.io/merge-queue/concepts-and-optimizations/batching)) | Y\* (relaxed by optimistic merging) | A failed batch goes to a separate bisection queue and is split in half recursively. **Bisection concurrency is configured separately from queue concurrency.** **Pending failure depth** holds a failure while successors run. **Optimistic merging** lets a later passing PR validate the ones ahead ([optimistic](https://docs.trunk.io/merge-queue/concepts-and-optimizations/optimistic-merging)). | Optimistic merging is advised only when flakiness is under 5%. Accepted cost: "you essentially give up the proof that every pull request in complete isolation can safely be merged". |
| **Uber SubmitQueue** | A speculation tree/graph over binary outcomes. Builds are ranked by `P(needed)` from logistic regression (≈100 features, 97% accuracy). A conflict analyzer on build-target hashes lets independent changes run in parallel ([EuroSys'19](https://www.masoud.io/docs/eurosys19.pdf)). The 2025 version adds a **speculation threshold** and **BLRD**, which lets a small change bypass a large conflicting one when all its speculative outcomes agree ([arXiv 2501.03440](https://arxiv.org/abs/2501.03440)). | Y (the chosen path's build decides) | Builds on mis-speculated paths are aborted; failing changes are rejected. | Speculate-all needs `2^n − 1` builds for n changes, only n of which are ever used. Evaluated with 100–500 workers. Before the threshold, 40–65% of builds were aborted prematurely **[E]**. |
| **Google TAP** | **Presubmit**: a fast per-change subset; "a change that passes the presubmit has a very high likelihood (95%+) of passing the rest" and is "optimistically" integrated. **Post-submit**: batched "milestones", typically cut every 45 min at peak ([SWE book ch.23](https://abseil.io/resources/swe-book/html/ch23.html); [ICSE-SEIP'17](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/45861.pdf)). [E] | **N** (lands before full verification) | A failing batch is split into individual changes and rerun; culprit finders binary-search; changes are auto-rolled back when confidence is high; norm is "fix or roll back". | Testing every change individually made compute grow "quadratically"; milestone delays reached 9 h **[E]**. |
| **Chromium CQ** (LUCI CV) | **Per-CL tryjobs** against tip of tree (rebased), no batching ([design](https://www.chromium.org/developers/testing/commit-queue/design/), [cq.md](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/infra/cq.md)). [V] | **N** (not re-verified against commits that land in between; successful tryjobs are reused unless older than 1 day) ([CV config docs mirror](https://pkg.go.dev/github.com/xinghun61/luci-go/cq/api/config/v2)) | Failed shards are retried and re-tested without the patch to separate real from flaky failures. The tree-status verifier waits for an open tree. The post-submit waterfall and tree closures catch escapes. | Trybot target: median under 40 min, p90 around 1 h. |
| **ChromeOS CQ** ("paladin", historical) | **Batch**: "takes the current set of approved changes, applies them to the tip-of-tree", 57 builders ([doc](https://chromium.googlesource.com/chromiumos/docs/+/refs/heads/firmware-rammus-11275.B/cros_commit_pipeline.md)). [V] | Y (per batch) | On failure CLs are re-submitted; sheriffs attribute failures by hand. Uber's critique: "shippable batches, and not shippable commits" ([EuroSys'19 §2.2](https://www.masoud.io/docs/eurosys19.pdf)). | Cycle takes hours. |
| **Jane Street build-bot** | Serial, then speculation + "merging multiple requests together" + hierarchical feature trees ([blog](https://blog.janestreet.com/making-never-break-the-build-scale/)). [E] | Y | A batch failure falls back to individual requests "to ensure forward progress". | Serial bound "at least m·n minutes"; volume fell to 30–40 requests a week and latency reached 24 h. |

---

## 2. Math (b)

**Notation.**
- `V`: wall time of one verify on an otherwise idle machine.
- `s`: number of verifies the machine runs concurrently at full speed (≈1 for a CPU-saturating suite).
- `p`: per-change probability of a real failure (independent).
- `f`: per-run flake probability.
- `λ`: arrival rate of ready changes.
- `b`: batch size; `w`: speculation window.
- `c`: expected verifies per change.

Serial capacity is `1/V`.

### 2.1 Serial FIFO queue (bors with b=1, homu, a lock-based lander) [D]

- Capacity: `μ = 1/V`.
- Latency: M/D/1 gives `E[T] = V + ρV / (2(1−ρ))`, with `ρ = λV`.

| V | λ=2/h | 4/h | 6/h | 8/h |
|---|---|---|---|---|
| 419 s (measured verify-window p50) | 483 s | 601 s | 904 s | 3251 s (ρ=0.93) |
| 209 s (tsc 42 + full vitest 167) | 223 s | 241 s | 265 s | 300 s |

A burst of 15 drains in `15·V`: 105 min at 419 s, 52 min at 209 s.

### 2.2 Batch + culprit finding (bors, Aviator/Trunk/Mergify batches, TAP milestones)

**Dorfman** (test the batch; if it fails, test each member) [D, from [Dorfman 1943](https://doi.org/10.1214/aoms/1177731363)]:
`c_D(b,p) = 1/b + 1 − (1−p)^b`. For small p, `b* ≈ 1/√p` and `c* ≈ 2√p`.
Break-even: at b=2 batching wins only for `p < 1 − 1/√2 ≈ 0.29`. Ungar proved group testing beats one-by-one testing only for `p < (3−√5)/2 ≈ 0.38` ([Ungar 1960](https://onlinelibrary.wiley.com/doi/abs/10.1002/cpa.3160130105)).

**Recursive bisection, bors-style** (a node is tested iff its parent failed; `b = 2^k`) [D]:
`c_B(b,p) = [1 + 2·Σ_{d=0}^{k−1} 2^d·(1 − (1−p)^{2^{k−d}})] / b`.
With exactly one culprit this costs `1 + 2·log2 b` verifies. A divide-and-conquer bisection costs "between 2log(n) and 2n+1 batch tests" ([EMSE'25](https://mcislab.github.io/publications/2025/emse_scale.pdf)). Git-bisect-style `log2 b` assumes a single culprit and no flakes.

Verifies per change, computed (D = Dorfman, B = bisect, S = bisect down to 4, then individual — "BatchStop4"):

| p | b=2 | b=4 | b=8 | b=16 | b* (Dorfman) | gain at b* |
|---|---|---|---|---|---|---|
| 0.02 | 0.54 | 0.33 | D .27 / B .24 | D .34 / B .21 | 8 | 3.65× |
| 0.05 | 0.60 | 0.44 | D .46 / B .40 | D .62 / B .41 | 5 | 2.35× |
| 0.10 | 0.69 | D .59 / B .61 | D .70 / B .63 | D .88 / B .67 | 4 | 1.68× |
| 0.20 | 0.86 | D .84 / B .91 | D .96 / B .99 | 1.03–1.05 | 3 | 1.22× |
| 0.30 | 1.01 | D 1.01 / B 1.14 | 1.07–1.25 | 1.06–1.31 | ~1 | none |

Capacity is `3600 / (V·c)` changes per hour [D]:

| p | V=419 s: b=1 / 4 / 8 | V=209 s: b=1 / 4 / 8 |
|---|---|---|
| 0.02 | 8.6 / 26.2 / 35.7 | 17.2 / 52.4 / 71.6 |
| 0.05 | 8.6 / 19.5 / 21.5 | 17.2 / 39.1 / 43.1 |
| 0.10 | 8.6 / 14.0 / 13.7 | 17.2 / 28.1 / 27.4 |
| 0.20 | 8.6 / 9.5 / 8.7 | 17.2 / 19.0 / 17.4 |

**Empirical anchors [E]:**
- **Ericsson, 3 systems, 9 months, batch sizes 1–20:** batching saved 72% of executions. With flakes, the best batch size and savings fell "from a BatchSize of 9 and execution savings of 72% to 4 and 41%". "The higher the FlakeRate the smaller the BatchSize" ([Najafi FSE'19](https://users.encs.concordia.ca/~shang/pubs/Armin_FSE_2019.pdf)).
- **Ericsson + Chrome with parallel machines:** a constant batch of 4 kept the observed feedback time with "up to 72% fewer machines"; an adaptive "BatchAll" did so with up to 91% fewer ([Fallahzadeh FSE'23](https://arxiv.org/abs/2308.13129)).
- **Break-even and base rates:** batching pays when fewer than 40% of builds fail (Beheshtian TSE'21, cited in [EMSE'25](https://mcislab.github.io/publications/2025/emse_scale.pdf)). Observed build failure rates: Chrome 8.5%, Google presubmit 16.42%, Google post-submit 23.12%.
- **Cross-check:** Ungar's 0.38 bound lines up with the empirical 40% threshold.

**Verification-cost caveat for reso [D].** Batching saves verifies only if `V(b)` stays roughly flat in b:
- The **full vitest** (167 s) and **tsc** (42 s) are whole-project runs, so they are independent of b.
- The **union `vitest related`** grows with b toward the full suite.

In a queue that already runs the full suite, the related step adds no gating power and only fails faster (unverified assumption: 'related' covers nothing that 'full' misses).

### 2.3 Speculative prefix (Zuul, GitHub MQ, GitLab trains, Aviator/Graphite parallel, Trunk predictive) [D]

Take a saturated round of `w` prefix verifies, with the first failure at index `J ~ Geom(p)`.
- Changes resolved per round: `R(w,p) = (1 − (1−p)^w) / p`. This is **capped at 1/p** however large w gets.
- Verifies per resolved change: `w·p / (1 − (1−p)^w) ≈ 1 + p(w−1)/2`.

| p | w=4 | w=8 | w=20 (Zuul default) | cap 1/p |
|---|---|---|---|---|
| 0.05 | 1.08 v/c, 3.7 c/rnd | 1.19, 6.7 | 1.56, 12.8 | 20 |
| 0.10 | 1.16, 3.4 | 1.40, 5.7 | 2.28, 8.8 | 10 |
| 0.20 | 1.36, 3.0 | 1.92, 4.2 | 4.05, 4.9 | 5 |

- **With a worker farm**, throughput is roughly `R/V`, and speculation is how you buy parallelism.
- **On one machine under processor sharing**, throughput stays at most `s/V` whatever `w` is, and every invalidated prefix is CPU taken from the head. Speculation therefore **lowers** throughput when `s≈1`, and it never cuts verifies below 1 per change the way batching does.
- **Empirical [E]** ([EuroSys'19](https://www.masoud.io/docs/eurosys19.pdf)):
  - "Optimistic" (Zuul-like) had P50 turnaround 7.3–9.6× Oracle and throughput "remains unchanged as we increase the number of workers".
  - SubmitQueue was within 1.2× of Oracle only with 500 workers at 500 changes/h.
  - Single-Queue turnaround was 80×/129×/132× Oracle (P50/P95/P99).
  - SubmitQueue's builds-to-changes ratio was 3.39–5.43 before the speculation threshold and 1.85–2.57 after ([arXiv 2501.03440](https://arxiv.org/abs/2501.03440)).

### 2.4 OCC direct push with CAS retry (reso's family; also GitHub's "require branches up to date") [D]

GitHub's overview names this as the pattern a merge queue replaces: it "provides the same benefits as the **Require branches to be up to date** … but does not require a pull request author to update their pull request branch and wait for status checks" ([reusable](https://github.com/github/docs/blob/main/data/reusables/pull_requests/merge-queue-overview.md)).

- A CAS round succeeds iff no other push lands between fetch and push: `q = e^(−λ·W)`.
- **If a retry re-verifies:** `W ≈ V`, `E[verifies/land] ≈ 1/q`, and `P(use up R rounds) = (1−q)^R`.
  - λV = 0.5 → q = 0.61, 1.65 v/land, 0.9% use up all 5 rounds.
  - **λV = 1.0 (reso busy: 419/429)** → q = 0.37, 2.72 v/land, **10%** use up all 5 rounds.
  - λV = 2 → q = 0.14, 7.4 v/land, 48% use up all 5 rounds.
  - λV = 3 → q = 0.05, 20 v/land, 78% use up all 5 rounds.
- **In a synchronized burst of N with cap R**, one lander wins per round: verifies are `Σ_{i<min(N,R)} (N−i)`. For N=15, R=5: **5 land, 10 give up, 65 verifies**. Simulation reproduced this.
- **CPU contention closes a feedback loop.** Under processor sharing, `V` grows with the number of concurrent verifies. That widens `W`, lowers `q`, and adds retries, which add load. This is the metastable pattern: "a system degrades in response to a transient stressor … but fails to recover after the stressor is removed", with retries as a named trigger ([Bronson HotOS'21](https://sigops.org/s/conferences/hotos/2021/papers/hotos21-s11-bronson.pdf)).
- **If a retry only rebases and pushes:** `W` is about one push round trip, so `q≈0.99` at 5 s. But a land is *stale* (the landed tree was never verified) whenever main moved during the verify, with probability about `1 − e^(−λV)`: 63% at λV=1. Uber's data on the consequence **[E]**: a 5% chance of a real conflict with 2 concurrent potentially-conflicting changes and 40% with 16; changes 1–10 h stale had a "10% to 20% chance of making the mainline red" ([EuroSys'19 §2.1](https://www.masoud.io/docs/eurosys19.pdf)).
- **Starvation is built in.** Lander i succeeds per round with `e^(−λ·V_i)`, so landers with long verifies (big diffs, wide 'related' sets) lose CAS races systematically.

### 2.5 Latency against b [D]

With a self-sizing batch (take everything waiting, up to `b_max`):
`E[T] ≈ R_res + V·[1 + (1 − (1−p)^b)·(1 + log2 b)]`, where `R_res` is the residual of the verify in flight (0 when idle, about V/2 when busy). This is a rough bound; the simulation in §2.6 is authoritative.

**Burst of N=15 simultaneous landers:**

| p | serial, V=419 | batch ≤8, V=419 | serial, V=209 | batch ≤8, V=209 |
|---|---|---|---|---|
| 0.02 | 105 min | 25 min (3.6 verifies) | 52 min | 13 min |
| 0.05 | 105 min | 42 min (6.0) | 52 min | 21 min |
| 0.10 | 105 min | 66 min (9.4) | 52 min | 33 min |
| 0.20 | 105 min | 104 min (14.8) | 52 min | 52 min |

### 2.6 Simulation: five landing policies on one machine [D]

**Model.** Discrete events with processor sharing (each of k active verifies runs at `min(1, s/k)`). V = 300 s idle, 14 days of Poisson arrivals, `b_max` = 8, `w` = 4, CAS cap = 5.
**Policies.** A = OCC that re-verifies on each retry · B = OCC that verifies once, then rebases and pushes · C = serial FIFO · D = batch + bors bisection · E = speculative prefix.

| s, p, f | λ | A | B (p50/p95; stale) | C | D (p50/p95; v/land) | E |
|---|---|---|---|---|---|---|
| s=1, .05, 0 | 4/h | **collapse** (92% give up) | 354/1008; 36% stale | 300/735 | 300/572; 1.01 | 359/1066 |
| s=1, .05, 0 | 8/h | collapse | 740/2587; 68% stale | 516/1514 | **358/731; 0.91** | 829/2511 |
| s=1, .05, 0 | 16/h | collapse | unstable | unstable (above 12/h) | **478/2519; 0.68** | unstable |
| s=1, .05, 0 | burst 15 | 5/15 land, 13 v/land | drain 75 min, 93% stale | drain 75 min | **drain 15 min; 0.2 v/land** | drain 75 min |
| s=3, .05, 0 | 8/h | 67% give up | 300/339; 49% stale | 516/1514 | 358/731 | **300/373** |
| s=3, .05, 0 | 16/h | collapse | 300/496; 73% stale | unstable | 478/2519 | **300/552** |
| s=1, .10, .03 | 8/h | collapse; 15% false rejects | 745/2587 | 516/1514; 2.8% false rejects | **381/1224; 2.0% false rejects** | 1094/4100 |

**Reading:**
- **When `s≈1`**, batching (D) dominates on every axis.
- **When `s≥3`**, i.e. idle capacity exists, the speculative prefix (E) has the best latency. D as simulated uses only one verify slot. A hybrid (batch, plus prefix-parallel bisection when slots are idle) takes the best of both.
- **OCC-reverify (A) is fine only at low λ.** The model's collapse at s=1 and 4/h is sharper than reso's lived experience (76 lands a week at an average of 0.45/h, λV ≈ 0.05). The cliff it predicts is under *bursts*.

### 2.7 Flakes [D]+[E]

- A batch fails with probability `1 − (1−p)^b·(1−f)`. Each flaky batch failure buys a spurious bisection, and a flake on a singleton leaf ejects an innocent change.
- **Measured rates [E]:**
  - **Google:** 1.5% of test runs flaky, 16% of tests flaky, 84% of pass→fail transitions involve flakes ([blog](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html)).
  - **Resource-affected flakes:** 46.5% of flaky tests are resource-affected across 52 projects and 27 resource configurations ([RAFT](https://arxiv.org/abs/2310.12132)).
  - **Suite-level compounding [D]:** per-run `f` for a whole suite is `1 − Π(1 − f_test)`, so a suite run at load 50–250 plausibly has f in the 5–10% range. This is an assumption; measure it.
- **Retry policies, simulated with a single verifier, V = 300 s, b_max = 8:**
  - **No retry**, p = .05, f = .05, 8/h: false ejection 4.3%, 0.96 v/land, p95 828 s.
  - **Retry a singleton once before ejecting**, same setting: false ejection **0.3%**, 0.98 v/land, p95 1091 s. At p = .10 and 16/h, near capacity, it tips the queue into overload (p50 2142 s → 37227 s). It must be load-aware.
  - **Retry the whole batch once before bisecting:** it charges an extra verify at every real failure and collapses capacity at p ≥ .10 and 16/h. Do not use it.
- **Documented mitigations [V]:**
  - GitHub: "only merge non-failing PRs" = off.
  - Mergify: `skip_intermediate_results`.
  - Trunk: pending failure depth + optimistic merging.
  - Aviator: optimistic validation (depth ≤ 3).
  - Zuul: `attempts` for infra failures only.
  - GitLab: `retry` keyword.
  - Chromium CQ: retry failed shards, then retest without the patch.

### 2.8 Is a pre-queue check worth running on one machine? [D]

Each lander could run a cheap check (tsc, or tsc + related) before entering the queue. It lowers the queue's failure rate from `p_raw` to `p_q = p_raw·(1−catch)` and costs `V_pre` of shared CPU per change. It pays iff `V_pre + c(b, p_q)·V_q < c(b, p_raw)·V_q`.

Two cases, with `V_q` = 209 s:
- **tsc + related (154 s):** almost never pays. At p_raw 0.10 with catch 0.8 and b=8 it costs 204 s per change against 132 s. It breaks even only around p_raw ≈ 0.3.
- **tsc only (42 s):** pays from p_raw ≈ 0.10 with catch 0.5 (125 s against 132 s at b=8).

Lesson: on a shared CPU, a lander's local verify is not free parallelism; it competes with the queue. Google's version of this pattern is a *fast subset* presubmit ([SWE book](https://abseil.io/resources/swe-book/html/ch23.html)), and Mergify's is "two-step CI".

---

## 3. Failure modes (c)

| Failure mode | Mechanism | Where documented | Mitigations (documented [V] / derived [D]) | reso relevance |
|---|---|---|---|---|
| **Flaky-test batch poisoning** | One flake fails the whole batch → spurious bisection, restarts for everything behind | Graphite ([docs](https://graphite.com/docs/merge-queue-optimizations)); GitHub ("false negatives … hold up the queue"); Najafi (savings 72%→42%) | Optimistic validation / pending failure depth / skip_intermediate_results / "non-failing only" off [V]; singleton retry, load-aware [D]; smaller b as f rises [E] | High: load 50–250 feeds resource-affected flakes |
| **Flake ejects an innocent change** | A flake on a singleton leaf, or at the head of a prefix queue | Chromium CQ retries shards and retests without the patch to exonerate ([cq.md](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/infra/cq.md)) | Retry the leaf once; a no-patch control run [V] | High |
| **Head-of-line blocking (hung or slow head)** | The head never reports, and everything behind waits | GitHub: head "hung in AWAITING_CHECKS, blocking ~23 PRs" (Jul 10 2026, [#15254](https://github.com/orgs/community/discussions/15254)); a missing `merge_group` trigger deadlocks the queue | Status-check timeout that treats silence as failure (GitHub) [V]; per-verify wall-clock timeout plus a watchdog [D] | Medium: verify p95/p50 ≈ 6.9× |
| **Timeout treated as a content failure** | Infra stalls trigger bisection or rejection | bors-ng bisects on timeout ([batcher.ex](https://github.com/bors-ng/bors-ng/blob/master/lib/worker/batcher.ex)) | Zuul retries only infra-phase failures (`attempts`=3) [V]; retry the same batch on timeout, never bisect [D] | Medium |
| **Lander/queue crash mid-batch** | State held in process memory; a partial land | bors-ng: batch crash, "remaining PR's are not re-queued" ([#579](https://github.com/bors-ng/bors-ng/issues/579)) | Durable queue state; a lease with TTL **plus fencing**: "the storage server … rejects the request with token 33" ([Kleppmann](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)). In git, the final `push --force-with-lease=main:<tested-base>` (or a plain fast-forward-only push) *is* the fence ([git-push](https://git-scm.com/docs/git-push)) [V]+[D] | High for a local lander: a zombie verifier must not be able to land |
| **Retry storm / metastable collapse** | CAS losses → re-verify → more CPU → longer V → more CAS losses | [Bronson HotOS'21](https://sigops.org/s/conferences/hotos/2021/papers/hotos21-s11-bronson.pdf) (the general pattern); §2.4/§2.6 [D] | Serialize verification (a queue), capped retries with backoff, admission control | **High** if reso's retry re-verifies |
| **Starvation / unfairness** | OCC: long-verify landers lose races. FIFO: small changes wait behind large ones. Queue jumping: rebuilds. Zuul: window halves on each failure | Uber: "delays in landing smaller changes blocked by larger conflicting ones", fixed by BLRD bypass ([arXiv 2501.03440](https://arxiv.org/abs/2501.03440)); GitHub: jump = "full rebuild of all in-progress" | FIFO + b_max; no priority lanes except emergencies; bypass only when all speculative outcomes agree (BLRD) [V] | Medium |
| **Stale-base / semantic conflict** | Two changes each pass against old main and break together | Uber: 5%→40% real-conflict probability for 2→16 concurrent changes; 10–20% breakage at 1–10 h staleness [E]. Chromium reuses tryjobs up to 1 day old [V] | Verify the exact candidate (tip + prefix) [V]; conflict analysis to skip re-verify only when dependency closures are disjoint (Uber target hashes, Aviator affected targets) [V] | **High** for any verify-once-then-rebase variant |
| **Masked failure / non-bisectable history** | "Last prefix wins" lands commits that failed on their own | Trunk: an earlier genuine failure masked by a later fix can merge both ([optimistic](https://docs.trunk.io/merge-queue/concepts-and-optimizations/optimistic-merging)); Uber on batch CQs: "shippable batches, and not shippable commits" | Keep it off unless f is high; if on, tag batch-landed ranges for later bisect/revert tooling | Low–medium (deploys come from a release branch) |
| **Unsafe parallel bisection** [D] | Testing disjoint halves *against the same base* in parallel can admit a pair that only breaks together | Derived. The safe forms are documented: bors tests halves serially through one staging branch; Mergify tests *prefixes* ([1,2], [1,2,3]) in parallel | Every candidate must be `tip + ordered prefix` | High for any home-grown bisection |
| **Red main poisons every lander** [D] | Landers verify on top of main, so one broken commit fails every later verify | TAP norm: "strongly discourages committing any new work on top of known failing tests" ([SWE book](https://abseil.io/resources/swe-book/html/ch23.html)) | Gate every land on exact-candidate verify; fast auto-revert as a backstop | High: why post-submit-only (TAP/Chromium) is a poor fit even though deploys are separate |

---

## 4. GitHub merge queue availability verdict (d)

**Verdict: NOT AVAILABLE for reso (User-owned, private). [V]**

- **Availability.** The eligibility text on `github/docs@main` reads: "Pull request merge queues are available in any public repository owned by an organization, or in private repositories owned by organizations using GitHub Enterprise Cloud" ([source](https://github.com/github/docs/blob/main/data/reusables/gated-features/merge-queue.md); [rendered](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)). User-owned repos are excluded at any visibility. A GitHub staff answer on 2024-09-05 said it is not supported on the Team plan ([#131130](https://github.com/orgs/community/discussions/131130)). A 2026-08-24 user comment reports it appearing on a Team org; that is unconfirmed, contradicts the docs, and is irrelevant to User-owned repos ([#201908](https://github.com/orgs/community/discussions/201908)).
- **Requirements, even where available:**
  - PR-based: a PR "has passed all required branch protection checks" before it can be queued.
  - Required status checks via branch protection or rulesets.
  - CI must run on `merge_group` (Actions) or on `gh-readonly-queue/{base_branch}` branches (third-party CI).
  - The "Require merge queue" rule is repository-level only; wildcard branch rules are unsupported.
  - Build concurrency 1–100 and group size 1–100.
  ([docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue), [rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets))
- **Actions minutes.** `merge_group` runs on GitHub-hosted runners in private repos draw on the account's minutes quota. Usage "is **free** for **self-hosted runners**" ([billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)). If eligibility ever changed, a self-hosted runner on the same M1 Max could run the queue checks, but that runner would still be the single machine.
- **Architectural fit, even if eligible.** It moves reso from direct push to PRs + remote-reported checks. It verifies once per PR, with no batching of builds. Its speedup comes from build concurrency on multiple runners. On one machine that means speculative-prefix CPU contention (§2.3).

---

## 5. Implications for reso's architecture (derived) and alternatives considered

**Recommended pattern: a single-owner local batch queue** (bors semantics on localhost, or flat combining where the lease holder combines everyone's pending work) [D]:
1. **Enqueue, don't push.** Landers write their ready change durably to a queue: a ref namespace or a spool directory. An optional cheap pre-check (tsc only) is worthwhile only if p_raw ≥ ~0.1 (§2.8).
2. **One verifier holds a lease.** It builds `candidate = main + ordered prefix of up to b_max`, runs tsc + full vitest **once** on that exact tree, then lands it with a fast-forward/CAS push against the tested base. The CAS is the fencing token, so a zombie verifier cannot land.
3. **Failure handling.** Bisect prefix-safely (bors order: land the first half if it passes, then test the rest on the new tip). Retry a failing singleton once only while the queue is short. Retry a timeout on the same batch instead of bisecting it.
4. **Size the batch by p.** `b_max ≈ 1/√p`: 4–8 for p between 2% and 6%. Shrink it as f rises (Najafi). Recompute from weekly logs.
5. **Expected effect at p = 5%.** Capacity about 21.5/h at V = 419 s, or about 43/h at 209 s, against 8.6/h or 17/h serial. A burst of 15 drains in about 42 or 21 min against 105 or 52 min. Removing N−1 concurrent full-suite runs also shrinks V and the resource-affected flake rate. That last effect is a direction I infer, and its size is unmeasured.
6. **If s > 1 is real** (a verify leaves cores idle), add prefix-parallel bisection and a speculative next batch (Trunk-style separate bisection concurrency). Otherwise stay at one slot.

**Alternatives considered:**

| Alternative | Why ruled out or deferred |
|---|---|
| GitHub merge queue | Unavailable for User-owned private repos (§4); PR + remote-CI model; no build batching |
| Hosted queues (Mergify, Aviator, Trunk, Graphite) | All orchestrate PRs + remotely reported checks; reso verifies locally with no required checks; their parallel/speculative modes buy nothing on one machine. Deferred, not impossible (self-hosted runner) |
| Zuul-style speculative prefix on one machine | s≈1 (vitest run mode uses all cores): same capacity ceiling, wasted prefixes (§2.3); worse than serial at s=1 in simulation |
| SubmitQueue ML speculation | Built for 100–500 workers; builds-to-changes 1.85–5.43 is waste this box cannot absorb. Its **conflict analyzer** idea transfers (next row) |
| OCC with conflict-aware skip (incremental option) | Keep direct push, but after a CAS loss re-run only tsc (42 s) when the intervening commits' changed files ∪ their dependents are disjoint from this change's related graph; otherwise re-verify fully. Much less change than a queue. Residual risk: global or type-level effects the related graph misses; no batching gain. **Viable fallback** |
| OCC that verifies once, then rebases and pushes | Fast, but 36–68% of lands are stale at 4–8/h (§2.6) with Uber-scale conflict rates |
| TAP/Chromium: land optimistically, detect post-submit, auto-revert | Deploys come from a release branch, so production is safe. But a red main fails every lander's verify on top of it (§3, last row); the queue's throughput depends on main staying green |
| Status quo (OCC that re-verifies on retry, cap 5) | Fine at average λV≈0.05. Burst cliff: with 15 synchronized landers, 5 land and 65 verifies are spent; CPU feedback makes it metastable (§2.4) |

---

## 6. Adversarial self-pass (integrated) and open uncertainties

**Gaps I checked with tool calls:**
- **Is s≈1 real?** Vitest run mode "uses all available parallelism" ([vitest](https://vitest.dev/config/maxworkers)). Supports s≈1 during the full-suite phase. tsc is largely single-threaded, so s is somewhat above 1 overall. This is why the s=3 rows exist and why the ranking flips toward speculation there.
- **Is bors bisection safe against pairwise conflicts?** The split code is confirmed ([divider.ex](https://github.com/bors-ng/bors-ng/blob/master/lib/worker/batcher/divider.ex)). My claim that halves run serially on the updated tip is *inferred* from the single `staging` branch, not read in the code; I label it as a derived safety rule.
- **Is the GitHub verdict current?** The eligibility text was fetched from `github/docs@main` on 2026-09-23. I found a contradicting 2026-08 anecdote and flagged it.
- **Are the thresholds consistent?** Dorfman break-even (0.29–0.31), Ungar (0.38) and the empirical threshold (40%) agree.

**What a hostile reviewer would still say:**
- **"The model's OCC collapse contradicts reso's 76 lands a week."** Correct at *average* load (λV≈0.05). The cliff is a burst prediction. reso's verify p95/p50 ≈ 2887/419 ≈ 6.9× fits a tail of multi-round re-verifies *or* contention. **Not verified**: read the rounds-per-land histogram from lander logs, and confirm whether a CAS retry re-verifies.
- **"p and f are invented."** Yes, they are parameters. Measure p as the fraction of land attempts failing on content, and f from same-tree reruns (split out a run-at-high-load bucket to test the RAFT effect). Then read b* from the §2.2 table.
- **"V is unknown."** 419 s is measured under load; unloaded V is unmeasured. The tables bracket it with 209 s and 419 s.
- **"Processor sharing is idealized."** Memory pressure makes real oversubscription worse than processor sharing, so the directional result (batch beats speculation at s≈1) is conservative.
- **"The union `vitest related` may cover tests the full run skips."** If so, V(b) grows with b and the batching gain shrinks. Check the vitest config.

---

## 7. Sources

**Primary docs**
- GitHub: [managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) · [availability reusable](https://github.com/github/docs/blob/main/data/reusables/gated-features/merge-queue.md) · [overview reusable](https://github.com/github/docs/blob/main/data/reusables/pull_requests/merge-queue-overview.md) · [ruleset rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets) · [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- Zuul: [gating](https://zuul-ci.org/docs/zuul/latest/gating.html) · [pipeline](https://zuul-ci.org/docs/zuul/latest/config/pipeline.html) · [job](https://zuul-ci.org/docs/zuul/latest/config/job.html)
- bors-ng: [README](https://github.com/bors-ng/bors-ng) · [divider.ex](https://github.com/bors-ng/bors-ng/blob/master/lib/worker/batcher/divider.ex) · [batcher.ex](https://github.com/bors-ng/bors-ng/blob/master/lib/worker/batcher.ex) · [#579](https://github.com/bors-ng/bors-ng/issues/579) · [reference](https://bors.tech/documentation/)
- Rust: [rollups](https://forge.rust-lang.org/release/rollups.html)
- GitLab: [merge trains](https://docs.gitlab.com/ci/pipelines/merge_trains/)
- Mergify: [batches](https://docs.mergify.com/merge-queue/batches/) · [performance](https://docs.mergify.com/merge-queue/performance/)
- Aviator: [parallel mode](https://docs.aviator.co/mergequeue/concepts/parallel-mode) · [batching](https://docs.aviator.co/mergequeue/concepts/batching) · [flaky tests](https://docs.aviator.co/mergequeue/concepts/managing-flaky-tests-in-mergequeue) · [affected targets](https://docs.aviator.co/how-to-guides/affected-targets)
- Graphite: [optimizations](https://graphite.com/docs/merge-queue-optimizations)
- Trunk: [batching](https://docs.trunk.io/merge-queue/concepts-and-optimizations/batching) · [optimistic merging](https://docs.trunk.io/merge-queue/concepts-and-optimizations/optimistic-merging)
- Chromium: [cq.md](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/infra/cq.md) · [CQ design](https://www.chromium.org/developers/testing/commit-queue/design/) · [LUCI CV config docs (mirror)](https://pkg.go.dev/github.com/xinghun61/luci-go/cq/api/config/v2) · [ChromeOS pipeline](https://chromium.googlesource.com/chromiumos/docs/+/refs/heads/firmware-rammus-11275.B/cros_commit_pipeline.md)

**Papers and production reports**
- Uber: Ananthanarayanan et al., [EuroSys'19](https://dl.acm.org/doi/10.1145/3302424.3303970) ([PDF](https://www.masoud.io/docs/eurosys19.pdf)) · Juloori et al., [CI at Scale, arXiv 2501.03440](https://arxiv.org/abs/2501.03440)
- Google: [SWE at Google ch.23](https://abseil.io/resources/swe-book/html/ch23.html) · Memon et al., [Taming Google-Scale Continuous Testing](https://research.google/pubs/pub45861/) · [Flaky tests at Google](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html)
- Batch testing: [Najafi, Rigby, Shang FSE'19](https://users.encs.concordia.ca/~shang/pubs/Armin_FSE_2019.pdf) · [Fallahzadeh, Bavand, Rigby FSE'23](https://arxiv.org/abs/2308.13129) · [EMSE'25 contrasting study](https://mcislab.github.io/publications/2025/emse_scale.pdf) · [Beheshtian et al. TSE](https://doi.org/10.1109/TSE.2021.3070269)
- Group testing: [Dorfman 1943](https://doi.org/10.1214/aoms/1177731363) · [Ungar 1960](https://onlinelibrary.wiley.com/doi/abs/10.1002/cpa.3160130105)
- Flakes and resources: [RAFT (TSE'24)](https://arxiv.org/abs/2310.12132)
- Failure dynamics and coordination: [Metastable failures, HotOS'21](https://sigops.org/s/conferences/hotos/2021/papers/hotos21-s11-bronson.pdf) · [Kleppmann on fencing](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html) · [git push CAS](https://git-scm.com/docs/git-push) · [Flat combining SPAA'10](https://people.csail.mit.edu/shanir/publications/Flat%20Combining%20SPAA%2010.pdf)
- Other: [Jane Street, never break the build](https://blog.janestreet.com/making-never-break-the-build-scale/) · [Hoff background, quoting the Not Rocket Science rule](https://github.com/channable/hoff/blob/master/doc/background.md) · [vitest maxWorkers](https://vitest.dev/config/maxworkers)
- Community threads: [#131130](https://github.com/orgs/community/discussions/131130) · [#201908](https://github.com/orgs/community/discussions/201908) · [#15254](https://github.com/orgs/community/discussions/15254)
