# A10 — ADVERSARIAL: does "free model generates, Opus 5 validates at the end" save anything?

**Axis:** attack the load-bearing assumption of the union-alpha proposal using this box's own
measurements. **Date:** 2026-09-16. **Sources:** every number below carries its file and line.

---

## VERDICT

**NO. Generate-cheap / verify-expensive does not hold on this box, and it fails for a reason the
proposal's own framing cannot see.**

Three independent measurements, each sufficient on its own:

1. **Verification costs the same as generation when the validator has no oracle.** Measured
   apples-to-apples on one vendor's quota bucket: 18 generation runs cost **+5.0pp**, 18 judge runs
   over the same 9 briefs cost **+21pp** — **4.2× per run, ≈1.05× per output judged**
   (`codex-probe-w3-verdict-2026-08-11.md:367-370`). Derived independently from the fleet's cost
   structure — output tokens are **13.1%** of an Opus-5 turn's marginal cost, context is **86.8%**
   (`usage-telemetry-100p-2026-08-16/routing-economics.md` F1, n=65,904 turns) — the same answer
   falls out: the validator must load the same task context *plus* the generator's output, so it
   pays the 87% slice regardless of who wrote the tokens. **Two methods, one number: V ≈ 1.0 × G.
   The saving is zero before any rework.**

2. **Validation is a filter, and half the measured defect is omission, which no filter can catch.**
   The proposal assumes errors of *commission*. On the frozen 36-defect corpus the cheap arm's
   failure is at least half *omission*: `fable-5.1@low` **6/36** against `opus-5@max` **12/36**
   (`fable51-effort-sweep-2026-09-10/README.md`). A validator can reject what it is shown; it
   cannot supply what was never generated. To know that six defects are missing it would have to
   find them — i.e. do the generation. **There is no validator, at any price, that recovers recall.**

3. **In an unattended chain a weak generator AMPLIFIES the measured failure mode, because the
   binding constraint is latency and selection, not correctness.** 90% of stranded cloud branches
   would have landed had they been landed an hour after their push; 52% of non-delivering sessions
   died because trunk moved past them (`drain-pipeline-productivity-2026-09-16.md` §1). Validation
   is a *latency* insert on the one axis measured as decisive. And the already-measured collapse
   shape is 18 backlog items → **242 branches**, each re-implemented 8–25 times, *"cannot be merged,
   only chosen between"* (`DRAIN_CIRCUIT_2026-09-01.md:372`). A cheaper generator raises attempt
   rate; the validator's job degenerates from *check one answer* to *set-cover over N divergent
   ones*, which on this box was solved by a **script**, not a model.

**THE ONE NARROW SLOT (it exists, and it is not what was proposed):** high-volume classification of
existing store text into a **closed enum with a deterministic post-check** — concretely, the **296
blocked backlog rows**, of which 281 (94.9%) carry no impossibility class and 158 (53%) have `needs`
byte-identical to `title`. There the expensive model is **not the validator at all**; a script is
(`class ∈ {4 strings}`, `needs != title`), and Opus 5 arbitrates only the abstentions. Expected
value: unblocks the 86% of live rows the dispatcher is structurally blind to. §5.

---

## 1. THE VERIFICATION-COST RATIO — and why a single ratio is the wrong question

The probe corpus contains **two** verification regimes with a **~40× cost spread between them**. The
spread is not noise and it is not about model or effort. It is entirely about **whether an oracle
already exists**.

### 1a. Regime A — ORACLE-ASSISTED (ground truth handed in, `--tools ""`, no repo)

T6, `fable51-effort-sweep-2026-09-10/README.md`. The first probe in the file that could measure cost
per cell (`claude -p --output-format json` returns `usage.output_tokens` + `total_cost_usd`).

| side | unit | n | cost |
|---|---|---|---|
| GENERATION | arm cells (`fable-5.1` @ low…max, one fresh context per brief×effort) | 43 measured | **$132.91** (+ **$37.46** burned on 17 HTTP-429 rows that produced no output) |
| VERIFICATION | judge calls (`claude-opus-5 @xhigh`, 3 judges × 7 defective briefs) | 21 calls / **147 rows** | **$11.82**, 0 parse failures |

- Per generation cell: **$3.09**. Per single judgment: **$0.080**. → **0.026×**.
- At 3-judge panel strength per output: $0.241 vs $3.09 → **7.8%**.
- Including the quota-fault waste on the generation side, judging is **6.9%** of generation.

**What bought that price.** `judge.py:6` — the judge sees *"the brief, the ground-truth list and the
labelled outputs — no tools, no repo, no memory."* The ground truth is **pre-existing**
(`tests/fixtures/codex-probe/`, 36 anchored defects, asserted by `verify-corpus.sh`, gated by
`tests/codex-probe-corpus.bats`). The judge is not deciding what is true; it is **matching against a
list someone else already made true**. That is a bounded predicate, and T1 already certified that
class as iso-quality at reduced effort (`model-routing-freewin-probe.md` T1: *"iso-quality on BOUNDED
judgment — extract ONE well-defined predicate / verify ONE claim"*, → `effort_defaults.verify_judge:
xhigh` as a certified free win).

### 1b. Regime B — RE-GROUNDING (no oracle; the judge must open the source)

T4/W3, `codex-probe-w3-verdict-2026-08-11.md:367-370`. This is the **only** apples-to-apples cost
measurement in the corpus: same vendor, same quota bucket, same 9 briefs, **same n=18** on both sides.

| side | what ran | bucket movement |
|---|---|---|
| GENERATION (W2) | 18 arm runs (2 Codex configs × 9 briefs) | 22.0 → 27.0 = **+5.0pp** |
| VERIFICATION (W3) | 18 judge runs (2 Codex judges × 9 briefs) | 22.0 → 37.0 → ~43 = **+21pp** |

- **Per run: 4.2×.** (Conservative reading, if the bucket did not reset between W2 and W3: 27→43 =
  16pp → **3.2×**. Both readings give verification > generation.)
- **Normalised per output judged** — each judge run ingests all **four** arm outputs for its brief —
  21/(18×4) = 0.29pp vs 5.0/18 = 0.28pp → **1.05×. Verifying one answer costs what producing one
  answer costs.**

The doc's own conclusion: *"that is the cost of judging, not of the arms, and it is why the mixed
panel is a per-probe instrument and not a standing one."*

**Corroboration from a third, independent probe.** T2 re-probe (`model-routing-freewin-probe.md`):
18 workers + **3 judges**, *"judges Opus-max, **WITH repo access** — they spot-checked citations
**byte-for-byte against source**"*; 21 agents, ~2.9M subagent tokens. And the netpositivity wave
(`backlog-drain-netpositivity-2026-08-25.md` §8): **12 recon axes → 10 adversarial verifiers** → 23
agents, 4.13M tokens — verification at **0.83× generation by agent count**, and the verifiers were
the same tier as the generators.

### 1c. The two regimes side by side

| | Regime A (oracle) | Regime B (re-ground) |
|---|---|---|
| Validator's question | *does this output match the known list?* | *is this claim true of the source?* |
| Tools | none (`--tools ""`) | full repo access, byte-for-byte cite checks |
| Cost vs generation | **0.026× / output** · 7.8% at panel strength | **~1.05× / output** · 4.2× at panel strength |
| Precondition | somebody already did the grounding work, once | nobody has; the validator does it every time |

**The operator's proposal is Regime B by construction.** A free model generating *novel* work has,
by definition, no pre-existing ground-truth list to check against. The 40× cheap number is not
available to it. **Quoting Regime A's ratio for a Regime B task is the whole error.**

### 1d. The cost-structure derivation — why V ≈ G was inevitable

`usage-telemetry-100p-2026-08-16/routing-economics.md` F1, measured over 65,904 Opus-5 turns:

```
marginal cost of one Opus-5@high turn = $0.1970
  cache read      62.7%
  cache creation  24.1%
  output          13.1%      ← the ONLY slice a different generator can remove
  fresh input      0.05%
```

**Replacing the generator can recover at most 13.1% of a turn's cost — and only if the generated
tokens never enter the validator's context.** Validation requires exactly that they do, where they
land in the **24.1% cache-creation slice**, billed at 1.25× — or **2×** for the **60.7% of this
fleet's opus-5@high cache writes that are `ephemeral_1h`** (`model-config.yaml:569-573`). So the
proposal moves work out of the cheap slice and into the expensive one.

It is worse than neutral because **the cheap generator is more verbose.** W3 finding volume, panel
mean over 9 briefs:

| arm | findings reported | ground-truth | judged FALSE POSITIVE |
|---|---|---|---|
| A `claude-fable-5` | 74.2 | 9 | 4.5 (**6%**) |
| B `gpt-5.6-sol`@xhigh | **141.0** | 9 | 30.2 (**21%**) |
| C `gpt-5.6-sol`@ultra | **146.8** | 10 | 31.8 (**22%**) |
| D `claude-opus-5` | 101.2 | **13** | 7.0 (**7%**) |

To validate the cheap arm the validator reads **1.4× the volume** and must **refute 4.3× as many
false positives** (30.2 vs 7.0) to extract **69% as much truth** (9 vs 13). Every one of those three
multipliers lands on the validator's bill.

### 1e. The rework term, which is what actually closes it

```
baseline        = G                      (Opus 5 does the work, self-checked)
proposal        = 0 + V + p·(V + G)      (free gen, validate, rework on reject)
with V ≈ 1.0·G  = G·(1 + 2p)
```

**Any p > 0 is a loss, and p is not small.** Measured proxies on this box:

- **`backlog-drain-netpositivity-2026-08-25.md` §7: "All ten claims that reached adversarial
  verification were refuted or re-scoped."** — p = **10/10** on research claims, where BOTH sides
  were Opus-tier. And the reason is fatal to the cheap-skim model: *"every one failed the same way —
  a real number attached to the wrong denominator, the wrong population, or the wrong conclusion.
  The counts were fine; the **folds** were not."* A validator cannot detect a wrong fold by reading
  the output. **It has to re-run the fold — which is the generation work.**
- The same session's own self-corrections were also fold errors: *"`reopen` is lease churn, not
  rework. 1,764 reopen events, but only 17 ids were ever done-then-reopened."*

---

## 2. THE FABRICATION PROBLEM — what validation has to DO

### 2a. What reduced capability actually produced (T1 / T2 grid)

Every one of these is an artifact that **reads as correct**:

| config | fabrication | how it was caught |
|---|---|---|
| Opus 4.8 @ **medium** | invented a `// NEVER <Link>` comment at `MobileListSwitcher.tsx:119` | **the file was opened; it does not exist** |
| Opus 4.8 @ **low** | invented a function `computePull` | **`grep`-confirmed absent** |
| Opus 4.8 @ **xhigh** (T1 d1) | **hallucinated a fabricated diff** | judge panel, high confidence |
| Sonnet 5 @ **xhigh** | systematic **wrong-file** citations — attributed `resolveGroupConfig` to `databaseActions.ts`; it lives in `drizzle/db.ts` | **all 4 judges**, with repo access |
| `gpt-5.6-sol` @xhigh/@ultra | **zero fabricated code** (0 of 1,420 quoted lines absent) but **33–40% of quoted lines >3 lines from the cited number**, degrading sharply above ~600-line files | a **script** extracted all 1,420 lines and matched them against the file at `pre_fix_ref` |

**The mechanism, stated by the probe itself:** *"MAX effort holds the grounding floor"* — and it is
**tier-independent**. Opus's own reduced-effort configs fabricate. This is why a free/cheap model is
a bad prior here even though the specific candidate is unmeasured: free is free *because* it is not
being run at a frontier tier's max effort, and max effort is the load-bearing variable.

### 2b. So what must validation do? **Byte-for-byte re-grounding. It is not a skim.**

The record is unambiguous about what it took to catch these:

- T2 re-probe judges: *"Opus-max, **WITH repo access** — they spot-checked citations **byte-for-byte
  against source**, per-brief shuffled labels."*
- W3 judges: *"cites checked byte-for-byte against the real tree."*
- W3's operational note, independent of its verdict: *"A 33–40% mis-located citation rate is a real
  cost in a verification slot on files over ~600 lines, **because the consumer of an adversarial
  finding re-locates every claim by hand**."*

**And the reason a skim is structurally impossible is stated best elsewhere in this repo**
(`agent-video-understanding-2026-07-26.md:366-367`):

> **"classical CV fails by returning an obviously wrong number; a learned model fails by returning a
> plausible one."**

A weak generator's failure mode is *optimised to survive inspection*. `computePull` is a plausible
function name. `// NEVER <Link>` is a plausible comment. A line number off by eleven is a plausible
line number. **The validator's cheapest possible check — "does this read as correct?" — is exactly
the check the failure is shaped to pass.**

### 2c. The deeper finding: even a 4-judge frontier panel could not decide

This is the part that should end the "validate at the end" framing outright. On the W3 corpus the
**same four judges agreed 98–99% on the anchored ground-truth table** — and then **inverted the
ranking** on the unanchored one:

| judge | vendor | clusters scored FALSE POSITIVE (A/B/C/D) |
|---|---|---|
| JA1 | anthropic | 2 / 3 / 2 / 6 |
| JA2 | anthropic | 2 / 2 / 2 / 5 |
| JC1 | codex | 6 / **65** / **69** / 9 |
| JC2 | codex | 8 / **49** / **52** / 8 |

*"The panel agrees almost completely about what was found; it disagrees violently about what counts
as a finding."* The byte-for-byte citation rule is **ambiguous** between *"the cited line does not
support the claim"* (a false positive) and *"the line number is off by eleven"* (a real finding with
a bad pointer) — and the two vendors read it opposite ways, consistently, with **no own-family
favouritism in either direction**.

**A single Opus-5 validator would have returned one of those two readings as a confident number and
never known the other existed.** So "validate at the end" is not merely priced wrong — on the exact
axis where a cheap generator fails (citation fidelity), **one validator is not decisive at any
price**, and the instrument that *was* decisive was a **deterministic script** that extracted 1,420
lines and matched them against the file at ~zero cost.

**Conclusion for Q2: validate-at-the-end is a full re-grounding, not a skim — and on the cheap
tier's characteristic defect it is still not conclusive.**

---

## 3. WHERE IT GENUINELY WORKS — the certified shapes on this box

The evidence does not say "never". It says the win exists **only where an oracle or a deterministic
checker carries the verification**, so the expensive model is not the validator at all.

### 3a. The four certified / measured shapes

| # | Shape | Evidence on this box | Ratio achieved |
|---|---|---|---|
| **S1** | **Oracle-assisted scoring.** Ground truth pre-exists; validator matches against a list, no tools. | T6 `judge.py` — 21 calls, 147 rows, **$11.82**, 0 parse failures, and **externally calibrated**: on `cp-01` it reproduced the 4-judge W3 panel's scores exactly. | **0.026×** |
| **S2** | **Deterministic checker, model never validates content.** | W3's citation script: 1,420 quoted lines matched against the real file → definitive answer where a 4-judge panel split 49–69 vs 2–3. Also `bench/score.py` (483 lines) — *"the false-positive budget, as a gate that can fail"*, exits non-zero; `9a11c84feeef`. | **~0** |
| **S3** | **Abstention router — deterministic pass first, its INDETERMINATE set becomes the expensive model's queue, cropped.** | `cv-design-review-2026-08-26/README.md:374`, built and verified running: `bench/route.py` (449 lines, `c811b9415a93`); run end-to-end 2026-09-11 → `✓ GATE PASSED`, **11/11 screenable defects caught, 0 missed, 0 control findings**. | pays the expensive tier only on abstentions |
| **S4** | **Cheap ADVISORY gate whose output an expensive model independently ratifies.** | `research-decomposition-critic` pinned `model: sonnet` — and the probe's own note says why it survives: *"the lead **independently ratifies** its APPROVE/REVISE output → the cheap-classifier/advisory-gate carve-out applies; **not a quality-for-cost trade**."* | n/a — cannot reach production |

**Note the inversion in S4.** The one certified cheap-model slot on this box puts the *cheap* model
in the *verification* seat, advisory-only, with the expensive model deciding. That is the opposite
of the proposal.

**And the one genuine cheap-GENERATION free win is narrower than it sounds.** `workflow_synthesis_worker:
claude-sonnet-5` is certified (ties Opus-4.8@max, 3/3 hard-brief ties, ~2–3× lighter quota) — under
**two hard requirements**: *effort MUST be `max`* (low/med/high/xhigh **all** fall below the grounding
floor) and *briefs MUST carry a ~15–25 call saturation bound*. "Free" and "max effort on a frontier
tier" are not compatible descriptions of the same model.

### 3b. What the shapes have in common — the admission test

A task fits **only if all four hold**:

1. The **output space is closed** (an enum, a path, a number, a boolean) — not prose.
2. A **checker exists that costs ~0** and returns a verdict the expensive model would not overturn.
3. The failure mode is **commission, not omission** — a wrong answer, not a missing one.
4. The **blast radius of a false pass is bounded** — nothing lands on it unreviewed.

The proposal's target (unattended drain work: read a repo, find the defect, write and land a fix)
fails **all four**. Open-ended repo grounding is precisely the axis T1/T2 identified as the one where
the floor is real.

### 3c. Concrete drain sub-tasks that DO fit — named, with numbers

| Sub-task | Why it fits | Size |
|---|---|---|
| **Classify the blocked pile into the 4-class impossibility enum** (`needs-credential` · `needs-human` · `not-yet-true` · `no-capacity`) | Closed enum (S1/S2). Checker is free: class ∈ 4 strings; `needs != title`. **281 of 296 blocked rows (94.9%) carry no class**; **158 (53%) have `needs` byte-identical to `title`**; **238 (80%) were never claimed by any worker** | **296 rows** — and `~28%` (band 40–135) are judged *"agent work wearing a park"* |
| **`re-land <branch>` row adjudication** | Decided by `git merge-base --is-ancestor <sha> origin/main`, exit code. Zero model judgment needed to verify | **590 rows lifetime (16.7% of everything ever filed)**; 19 open today; the single largest 30-day inflow generator at **28.7%** |
| **Stranded-branch selection** | Already solved by a **greedy set-cover script**: 313 branches → **95 distinct absent paths** → **52 branches cover every one**. A cheap model can only summarise; the decision is deterministic | 313 branches / 72 items |
| **Dedupe + premise-falsifier drafting** | Bounded predicate per row; the falsifier is a **command whose exit code is the check**. `cc-backlog freshness`: **"never validated: 457 of 501 live rows"** | 457 rows |
| **Retrieval / file:line lookup** | The existing `research_retrieval: claude-haiku-4-5` slot. Bounded, checkable by opening the file | ⚠️ **never probed in this fleet** and at **0.06% of output tokens** — an unmeasured slot, not a proven one |

**Not on this list, deliberately:** anything that writes code, anything that closes a backlog row on
prose evidence, anything that lands.

---

## 4. THE SILENT-FAILURE MODE — a weaker generator AMPLIFIES it, measurably

The question is whether a bad generation that passes weak validation gets committed and landed. On
this box it already does, and the amplification argument is arithmetic, not analogy.

### 4a. What the chain already does wrong unsupervised

| Measured pathology | Number | Source |
|---|---|---|
| Cloud closures citing evidence about a branch **their session never touched** | **21 of 29 (72%)** — 15 cite the identical path pair across 15 sessions and 13 ids; split perfectly dated at the 08-25 `fill-paths` fix; root cause a **shell global** (`cloud-reconcile.sh:740-763`). *"13 backlog rows are closed today on evidence naming a deliverable their session never produced"* | drain §2 |
| Closures mechanically **not-delivered** | **47.2%** (1,612 of 3,413); delivered 33.4%; ambiguous 19.4% | drain §2 |
| The one week the drain looked like it would reach zero | **54% of that week's closes were retractions** (`moot`/`superseded`/`already-true`) | drain, Verdict |
| Item thrash | **244 claims over 17 ids, each re-claimed 8–23×, 1 of 17 ever reached `done`** → conversion **0.4%** | `DRAIN_CIRCUIT:141` |
| …and the re-implementations | **18 items → 242 branches (77%)**; *"Every re-attempt produced its own blob for the same file, so the branches **cannot be merged, only chosen between**"* | `DRAIN_CIRCUIT:372` |
| Cloud yield | **19.9%** — 708 declarations → 146 sessions delivering 212 commits | drain §1 |
| **A braked run still reported `result:"DONE"`** | A `PreToolUse` deny reached a Workflow agent mid-run and beat `bypassPermissions` — **and the halted run reported success** | `oversight-at-scale-2026-08-19.md` §1.4 |
| The chain has **no vocabulary for failure** | Workflow journal vocabulary is *exactly* `{started, result}` — **no `error`, no `failed`**. One tested run: **6 started · 5 did work · 3 recorded a result** | `oversight-at-scale` §2 row 5 |
| The detectors built to catch the collapse were **starved by it** | §2b-v (drain-chain liveness) and §2b-vi (the "is draining winning?" report) executed **0 times/day since 2026-09-08**; the standing alarm's glob was broken by a rename and *"is right today only by accident"*. **The chain's death was detected by a human.** | drain §4 |

### 4b. Why a weaker generator amplifies rather than dampens — four mechanisms

**(1) The verifier is already outrun, and rate×duration is the governing quantity.** The repo's own
lesson (`memory/verify-throughput-below-trunk-velocity.md`), measured 2026-07-30: **105 commits
landed to `origin/main` in 3 hours** while one `postland-verify` run takes **0.8–3.1 h** over a
177-suite corpus. Day's tally: **7 RED, 1 CUT, 1 HUNG, 1 STALL, 0 GREEN**. `deploy-live` is
fail-closed on a green stamp, so the live layer sat **50–78 commits behind trunk** — *everything
landed that day was INERT*. The rule it produced:

> *"For any 'gate is never green' symptom, measure the RACE before debugging the artifact — producer
> rate vs verifier wall-clock. **If `rate × duration > 1` the pipeline can never converge** and the
> fix is architectural, never another test fix."*

At the measured values `rate × duration` was **28–108**. **A free generator is a direct multiplier on
`rate`.** It does not dampen the failure mode; it drives an already-diverging loop further from
convergence. This is the single most decisive measured argument against unattended cheap generation
on this box.

**(2) Validation is a latency insert on the axis measured as decisive.** 52% of non-delivering cloud
sessions died `superseded`/`conflict` — *trunk moved past them* — and the repo's own replay shows
**90% of stranded branches would have landed had they been landed an hour after their push**. Add to
that the dose-response on staleness (`backlog-drain-netpositivity` §2): rows closed after a week are
**premise-dead 23.4%** of the time vs **4.2%** under a day — **monotone, 5.6× across the range** —
against a tree that moves **p50 415 commits** between filing and reading, with only **5.8% of
completions landing against an unchanged tree**. **Every hour the validator holds an artifact
converts delivered work into a retraction**, and a validator doing full re-grounding (§2b) is an
*hours*-scale insert, not a minutes-scale one.

**(3) Rejection has nowhere to be recorded, so a weak generator's extra rejects become thrash, not
signal.** The journal vocabulary is `{started, result}`. The measured consequence of a reject-loop
already exists: `cc-backlog-reap` writes `block`, later writes `unblock`, the item returns to open,
the dispatcher re-claims it — *"5 minutes later, forever"* (`DRAIN_CIRCUIT:149`). **17 ids, 244
claims, 1 done.** A validator that rejects more often feeds exactly this oscillator. `scripts/
thrash-block-recover.sh` *"already exists and correctly handles precisely this oscillation — and is
wired to nothing."*

**(4) The failure the chain cannot see is the one the cheap tier produces most.** 21 of 29 cloud
closures cited evidence about a branch their session never touched — a **claimed-outcome-vs-checked-
outcome** failure (`memory/claimed-outcome-vs-checked-outcome.md`: *"A wrapper that discards its
transport's return code, whose caller then writes a success marker, has silently deleted the
message… the failure is invisible from both ends"*). A generator that produces *plausible* evidence
strings rather than true ones is producing exactly the artifact this chain has already proven it
cannot distinguish. **A false PASS here is not caught later — the damping marker guarantees it is
never retried.**

### 4c. The one honest counter-consideration, and why it does not rescue the plan

A weaker generator *could* dampen thrash if the validator's reject were **cheap and terminal** —
i.e. Regime A. It is not (§1b), and rejection is not terminal (§4b-3). So both preconditions for the
dampening story are measured false on this box.

---

## 5. THE HONEST STEELMAN — the narrowest slot that survives

### 5a. What has to be true

The proposal survives **only** with all five of these, and each is a measured requirement, not a
preference:

| | Requirement | Because |
|---|---|---|
| **R1** | The verification is **Regime A** — a checker or oracle already exists, and Opus 5 is *not* the validator of content | §1a/§1c: the 40× spread is entirely this |
| **R2** | The output space is a **closed enum / path / boolean**, never prose | §2b: prose fabrication survives inspection by construction |
| **R3** | The task's defect mode is **commission**, and **recall is not part of the deliverable** | §Verdict-2: no validator recovers omission (6/36 vs 12/36) |
| **R4** | The cheap output **never enters Opus 5's context in bulk** | §1d: 86.8% of the cost is context; ingesting output is the expensive slice |
| **R5** | Nothing **lands** on a pass; the pass changes a **store field**, reversibly | §4a: 47.2% of closures are already not-delivered; a false pass on a land is unrecoverable |

### 5b. The slot

> **Bulk re-classification of existing backlog-store text into the four-class impossibility enum,
> with a free/cheap model proposing the class and a SCRIPT — not Opus 5 — validating it.**

- **R1 ✅** the checker is `class ∈ {needs-credential, needs-human, not-yet-true, no-capacity}` plus
  `needs != title`, both free. `bin/cc-backlog:1120-1132` already enforces the gate on `add
  --why-not-now`; the defect is that `block --needs` validates only **non-emptiness**
  (`cmd_transition`) — so the checker *already exists in the codebase* and merely isn't on this path.
- **R2 ✅** four strings.
- **R3 ✅** every row's text is already present; nothing must be *discovered*.
- **R4 ✅** one row's `title` + `needs` is tens of tokens; batched, this never approaches a context
  charge comparable to generation.
- **R5 ✅** it sets a field on a JSONL row. Reversible, auditable, lands nothing.

**Opus 5's role is the abstention queue only** (shape S3) — the rows the cheap model marks
low-confidence, plus a seeded audit sample. That is the `bench/route.py` architecture, already built
and verified working on this box (11/11 caught, 0 missed, 0 control findings).

### 5c. Expected value — stated in the currency that binds

- **Population:** 296 blocked rows. **281 (94.9%)** carry no class; **158 (53%)** have `needs`
  byte-identical to `title`; **238 (80%)** went straight to blocked, never claimed.
- **Yield:** hand-judged on a seeded sample of 25, **~28% are "agent work wearing a park"** — honest
  band **40–135 rows**. Those rows are *drainable work the dispatcher cannot see*: `cc-dispatch`
  selects `status=="open"` only (`bin/cc-dispatch:1921`), so **296 of 343 live rows (86%) are
  structurally invisible to both lanes** and the real drainable queue is **47 rows, not 342**.
- **Value:** converting 40–135 blocked rows to `open` **roughly doubles-to-quadruples the drainable
  queue**. Against the measured throughput lever — *"rows-per-session is the only lever that has ever
  mattered — not venue, not model, not quota"* (5.5 rows/session on the local lane vs 1.5 on the
  ordinary lane) — this is the highest-value thing a bulk classifier can do here.
- **Cost:** at Regime A prices (**$0.080 per judgment**, T6-measured), classifying and 3-judge-
  auditing 296 rows is **< $80 of expensive-tier equivalent**, and the *generation* half is free.

### 5d. 🚨 The steelman's own fatal caveat — the currency is wrong

**The saving being optimised is not the binding constraint, and this box has measured which one is.**

- `accounts.json` carries `spend.usage_credits_authorized=false` and `frontier.credits_authorized=
  false` → **zero dollar exposure**. Opus 5 tokens are *already* free in dollars; they cost **quota**.
- And quota is measured **not scarce** at the moment this would run: **"3.19 account-weeks of weekly
  quota expired unused"** in the same 30-day window in which the actionable backlog was **47 rows**.
  The drain audit's own verdict sentence: **"Quota is not scarce; drainable work is. Buying more
  venue capacity buys nothing."**
  *(Honest tension, dated: `routing-economics` F10 measured peak weekly utilisation at 91/92/100/85%
  in the cycle ending 2026-08-16 — quota WAS scarce then. The constraint flipped between August and
  September. Re-measure before relying on either; do not quote a stale side.)*
- **Realisation risk is measured and it is severe.** The one certified cheap-generation free win on
  this box — `workflow_synthesis_worker: claude-sonnet-5`, certified 2026-07-01 — delivered **537 of
  157,038 assistant turns (0.34%)** and **0.01% of output tokens**, because it is realisable only
  inside Dynamic Workflows, *"which the fleet barely runs"* (`routing-economics` F13). **A certified
  free win on this box has a measured realisation rate near zero.** The union-alpha plan would face
  the identical gap, and nothing in the proposal addresses it.

**So the steelman's honest expected value is: a real but small operational win (40–135 rows
unblocked), whose value comes entirely from the CLASSIFICATION, not from the generator being free —
and it would be very nearly as cheap to run on Opus 5 directly**, because at Regime A prices the
whole 296-row job costs under $80 of expensive-tier equivalent against a quota bucket with 3.19
account-weeks expiring unused.

---

## 6. ADVERSARIAL SELF-PASS — what a hostile reviewer says I missed

Three gaps, investigated with real tool calls, integrated above and recorded here.

**G1 — "You conflated a 3–4 judge PANEL with a single validator; the proposal has one."** Correct
and it is the strongest counter. I therefore normalised per output judged, not per panel: W3 gives
**1.05×**, not 4.2×, for a single validator (§1b). **The conclusion survives at the corrected number
— V ≈ G means the saving is zero before rework — and it is independently confirmed by the cost
structure (§1d), which never mentions panels.** But §2c is the sting in the tail: a *single*
validator is also **not decisive** on the cheap tier's characteristic defect, so the 4× discount for
dropping to one judge is bought with the verdict's reliability.

**G2 — "Everything you cite is Claude-family and one Codex run. A genuinely free frontier model is
unmeasured here."** Conceded, and it is the honest limit of this axis. Two things narrow it:
(a) the governing finding is **model-independent** — *"MAX effort holds the grounding floor,"* and
**Opus's own** medium and low configs fabricated (§2a), so this is a statement about effort, not
about vendor; (b) the one cross-vendor datapoint is unfavourable and ran on a **deliberately
friendly field**: the corpus is drawn from defects a Claude model already missed once (*"That tilts
the field toward the candidate… The candidate had the friendly field and returned no unique coverage
on it"*) — Codex-only ground-truth findings = **0 at every vote threshold**, coverage `A∪D∪B` = 14
(+0 over `A∪D`). **Bad prior, not a measurement of the specific candidate. Anyone adopting should
run T4's own harness — corpus, judge pipeline and blinding all already exist and are frozen.**

**G3 — "You assumed validation means an LLM reading prose. What about just running the tests?"**
This is the right instinct and it is where the steelman came from (S2/S3). But it does **not** rescue
the general plan, for a measured reason I would otherwise have missed: **the deterministic verifier
has its own throughput ceiling and this box has already blown through it.** `postland-verify` = 177
suites, 0.8–3.1 h, against 105 commits/3 h → **7 RED, 1 CUT, 1 HUNG, 1 STALL, 0 GREEN in one day**,
live layer 50–78 commits behind, everything landed that day inert. `rate × duration = 28–108`. A free
generator multiplies `rate`. **The deterministic-gate answer is only available at a generation rate
the gate can keep up with — which is a cap on how free you are allowed to make generation.** That
inverts the proposal's premise: cheap generation is not a way to do more work, it is a way to
overwhelm the only verification that was ever cheap.

**One further thing I nearly assumed away.** I initially treated the defect as commission and priced
the validator accordingly. The recall table (6/36 vs 12/36) forced the correction that became
Verdict-2 — and the shape is the repo's own recorded lesson,
`memory/search-summary-is-not-a-reading-of-the-source.md`: *"a search tool returns synthesized prose,
and synthesized prose reads exactly like a finding. There is no marker distinguishing 'I read the
listings' from 'an aggregator described them.'"* **A cheap generator's output carries no marker for
what it did not look at, and that is precisely the information a validator needs and can never have.**

---

## 7. BLOCKERS / UNCERTAINTIES, named

1. **No candidate model was measured.** "union-alpha" appears **nowhere** on this box (grepped
   `claude-infrastructure`, `~/.claude/*.md`, `~/.claude/rules`, the fde repo → 0 hits). Everything
   here is a prior derived from mechanism + the one cross-vendor probe, not a measurement of it.
2. **The W3 bucket figure is directional by the probe's own insistence.** *"No $/finding figure was
   computed here, and none should be quoted from this probe."* I used it for a **ratio between two
   equal-n arms on the same bucket**, which is the one use it supports, and I gave both readings of
   the ambiguous `22.0 → 37.0 → ~43` (16pp vs 21pp → 3.2× vs 4.2×). Neither changes the sign.
3. **T6's cost is per-cell and honest; T2's is not separable.** T2 reports 21 agents / 2.9M tokens
   without a worker/judge split. I did not impute one.
4. **No Opus-5 effort quality panel has ever been run** (`routing-economics` F6). Every certified
   effort result in the file is Opus **4.8** or scores Opus 5 only as a cost anchor. So "Opus 5
   validating at high effort" is itself an **uncertified** configuration.
5. **Quota scarcity flipped between Aug 16 and Sep 16** (§5d). Re-measure; do not quote either side.
6. **`research_retrieval: claude-haiku-4-5` has never been probed in this fleet** and produced 0.06%
   of output tokens — the nearest existing cheap-tier slot is unmeasured, so §3c's retrieval row is
   a candidate, not evidence.

---

## 8. SOURCES

- `~/.claude/model-routing-freewin-probe.md` — T1, T2 + effort grid, T4, T5, T6; § Purpose decision
  rule; § Harness reality (effort pinnable only in Workflows + teammate settings).
- `claude-infrastructure/docs/research/codex-probe-w3-verdict-2026-08-11.md` — §3 volume/FP table,
  citation-accuracy table, §4 judge agreement, §7.3 the bucket cost figures (:367-370).
- `.../docs/research/fable51-effort-sweep-2026-09-10/README.md` + `judge.py` — per-cell measured cost,
  recall grid, judging cost $11.82/147 rows.
- `.../docs/research/usage-telemetry-100p-2026-08-16/routing-economics.md` — F1 (13.1% output /
  86.8% context), F6, F10, F13, F18.
- `.../docs/research/drain-pipeline-productivity-2026-09-16.md` — verdict, §1, §2, §3, §4, §5.
- `.../docs/plans/DRAIN_CIRCUIT_2026-09-01.md` — :141 thrash, :149 oscillator, :372 branch fan-out,
  §1.5 telemetry blindness.
- `.../docs/research/backlog-drain-netpositivity-2026-08-25.md` — §2 staleness dose-response, §7
  ten-of-ten refutation, §8 wave cost.
- `.../docs/research/oversight-at-scale-2026-08-19.md` — §1.4 braked-run-reports-DONE, §2 matrix.
- `.../docs/research/cv-design-review-2026-08-26/README.md:374` + `-pipeline-verification-2026-09-11.md`
  — the abstention router, built and verified.
- `.../docs/research/agent-video-understanding-2026-07-26.md:366` — legible vs plausible failure.
- `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/` —
  `verify-throughput-below-trunk-velocity.md`, `claimed-outcome-vs-checked-outcome.md`,
  `search-summary-is-not-a-reading-of-the-source.md`, `miscalibrated-check-is-a-deleted-check.md`,
  `verification-harness-vacuous-pass-traps.md`.
- `~/.claude/model-config.yaml` — roles ladder, `workflow_synthesis_worker` conditions,
  ephemeral_1h cache-write note (:569-573).
