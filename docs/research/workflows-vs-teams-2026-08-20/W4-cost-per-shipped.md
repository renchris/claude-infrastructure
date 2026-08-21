# W4 — Cost per unit of implementation actually shipped

**Axis:** pressure-test and extend the strongest anti-workflow argument — the quota one.
**Date:** 2026-08-20 · **Box:** M1 Max, 10 cores, 64 GiB, CC 2.1.220 · **Method:** independent
re-derivation from **6,015 transcripts / 9.07 GB across all four per-account stores**, 30-day window,
realpath-deduped and **message.id-deduped**. Nothing was spawned; nothing on the live fleet was
touched. Labels: **MEASURED · DERIVED · INFERRED · QUOTED · REFUTED**.
Scanner: [`W4-scan.py`](W4-scan.py) (this directory) — every number below is reproducible from it.
Builds on `breaking-the-ceiling-2026-08-19/B4-quota-arithmetic.md` (commit `8b68f0861`); its scripts
were never committed, so this is a from-scratch re-derivation, not a re-run.

---

## 1. Verdict (5 lines)

1. **The quota finding REPRODUCES and survives the implementation cut.** Independently derived over
   30 days: teammate **51,235** output tokens per quota point vs workflow agent **8,522** = **6.01×**.
   Restricted to units that actually wrote files, it is **3.31×** (teammate 51,631 : workflow 15,615,
   n=481 vs 461) — squarely inside B4's published 2.43–3.53× band. **The rule's cost premise holds.**
2. **But the brief's mechanism is REFUTED. The gap does NOT grow with task length — it SHRINKS.**
   Size-controlled: **2.98×** at 1–10K output, **1.91×** at 10–50K, **1.22×** above 50K (n=4, weak).
   There is no "arrival tax amortised over a long life" effect, because the tax is **not per unit —
   it is per TURN**: cache-creation per response is 4.3–9.0K for *every* class. What differs is
   **output per turn: 317 for a workflow agent vs 1,115 for a teammate at matched size**, at
   identical tool density (1.24 vs 1.34 tools/response). The workflow agent is turn-fragmented.
3. **Efficiency is a hump, not a ramp — B4's "fewer, bigger units" needs an upper bound.** out/pp
   peaks at **61,168** in the 40–80K-output band (≈32 min, ≈60 responses, ≈3 files) and **collapses
   to 32,341 above 300K** (≈13 h, 310 responses), because per-turn cache-creation re-inflates from
   4,277 to 15,276 as the unit's own context grows. B4 saw this inversion at n=4 and dismissed it;
   at **n=203 / n=468** it is real. **The efficient implementation unit is 40–150K output tokens /
   60–120 turns / 3–6 files.**
4. **Workflow agents live ~100× below that band and never approach it**: median output **356** tokens,
   p99 **25,994**, and only **9.2%** ever exceed 10K (0.2% exceed 50K) — versus **94.4%** of teammates.
   Cost per unit that produced a confirmed commit: **teammate 11.6 pp · workflow agent 49.3 pp.**
5. **The wave arithmetic: N teammates wins at N=2, 5 and 12, under both exchange rates.** For an
   N-task wave at the measured task size, workflow costs **1.35–1.67× more per task**; N dispatched
   sessions cost **1.03–1.85× more**, converging to teammate parity only at N=12. **Quota gives the
   standing rule no reason to change — but it also gives dispatch no quota advantage; dispatch buys
   the lead's CONTEXT, not the fleet's QUOTA, and that distinction is currently blurred in CLAUDE.md.**

---

## 2. The numbers, with the command behind each cell

**Exchange rate.** `pp = out_Mtok × 7.93 + cache_creation_Mtok × 1.85` — **QUOTED** from A6's deduped
fit via B4 §2.4 (verified: it reproduces B4's published `teams-agent 167.2 pp` line exactly from
B4's own printed token totals). Cache-read is not billed on this fit. Every ratio below is also
computed under the **A1 raw fit (9.27 / 1.04)** as a sensitivity; §2.7 shows it changes no verdict.

**Instrument control — the dedupe is load-bearing** (repo memory: `transcript-lines-repeat-one-billed-response`):

| | naive line-sum | message.id-deduped | inflation |
|---|---|---|---|
| output tokens | 15,315,537 | 5,636,700 | **2.717×** |
| cache-creation | 127,664,247 | 61,629,985 | **2.071×** |

`python3` over a random 120-unit sample (seed 7). The inflation is **non-uniform between the two
token classes**, so a naive sum does not merely scale out/pp — it distorts it. Cross-*file* message.id
duplication in the same sample: **0 / 7,007 (0.00%)**, so realpath-dedupe was sufficient.

### 2.1 Class totals, 30 days — the re-derivation

`python3 W4-scan.py 720 u720.json` then the aggregation in §5.

| class | units | responses | output | cache-creation | pp | **out/pp** | med unit out |
|---|---:|---:|---:|---:|---:|---:|---:|
| main-session | 2,164 | 179,676 | 166,940,192 | 1,165,764,244 | 3,480.5 | **47,964** | 53,394 |
| teams-agent | 1,169 | 44,267 | 49,913,684 | 312,651,171 | 974.2 | **51,235** | 36,848 |
| workflow-agent | 1,781 | 45,796 | 5,042,478 | 298,223,937 | 591.7 | **8,522** | **356** |
| sidechain-subagent | 694 | 17,407 | 1,973,938 | 106,236,030 | 212.2 | **9,303** | 744 |

**teams : workflow = 6.01×** · main : workflow = 5.63× · teams : sidechain = 5.51×.

Class assignment is structural, from the transcript path plus one field, not from a heuristic:
`…/subagents/workflows/<wf>/agent-*.jsonl` → workflow-agent · `…/subagents/agent-*.jsonl` →
sidechain-subagent · `projects/<slug>/<uuid>.jsonl` carrying an `agentName` field → teams-agent ·
otherwise main-session. (`agentName`/`teamName` are written by the binary for named teammates only —
sampled and confirmed on 11 of 200 recent depth-1 files, e.g. `agentName:"dod-crosstalk"`,
`teamName:"session-fb8b3ffe"`.)

**B4's own 60-hour window, re-run at a different instant** (`W4-scan.py 60`): teams **47,048** :
workflow **7,729** = **6.09×** (n=17 vs 197). B4 measured 3.53× then 3.24× eight minutes later on the
same window with n=131 teammates. The direction is stable across three independent derivations and two
days; **the magnitude is a band, 3.2–6.1×, and must never be quoted as a digit.**

### 2.2 Does it hold for IMPLEMENTATION specifically? — yes, at 3.31×

A unit is IMPL if its own assistant messages contain ≥1 `Write` / `Edit` / `MultiEdit` /
`NotebookEdit` `tool_use` block.

| class | stratum | n | output | pp | **out/pp** | med out | med writes | med files |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| main-session | IMPL | 1,364 | 161,690,229 | 3,319.5 | 48,709 | 94,943 | 16 | 6 |
| main-session | read-only | 800 | 5,249,963 | 161.0 | 32,609 | 600 | 0 | 0 |
| teams-agent | IMPL | 481 | 25,659,667 | 497.0 | **51,631** | 45,384 | 6 | 2 |
| teams-agent | read-only | 688 | 24,254,017 | 477.2 | 50,822 | 31,886 | 0 | 0 |
| workflow-agent | IMPL | 461 | 3,801,467 | 243.5 | **15,615** | 5,542 | 1 | 1 |
| workflow-agent | read-only | 1,320 | 1,241,011 | 348.2 | 3,564 | 109 | 0 | 0 |
| sidechain-subagent | IMPL | 84 | 525,931 | 55.3 | 9,519 | 2,441 | 3 | 1 |
| sidechain-subagent | read-only | 610 | 1,448,007 | 156.9 | 9,227 | 332 | 0 | 0 |

- **IMPL stratum: teams : workflow = 3.31×** (n=481 vs 461 — both well powered).
- **read-only stratum: 14.26×.** So the headline 6.01× is *diluted upward* by read-only workflow
  agents. The implementation-specific penalty is the **smaller** of the two, and it lands almost
  exactly on B4's originally published 3.2–3.5×. **B4's number was right for implementation by
  coincidence of window, not by construction.**
- **461 workflow agents wrote files in 30 days.** The class is not read-only in practice — consistent
  with W1's live probe. The question was never CAN.

### 2.3 The mechanism — REFUTES the brief's hypothesis

The brief proposed: a teammate amortises one arrival tax across many turns, so the gap should **grow**
with task length. Size-controlled, it does the opposite.

| output band | class | n | out/pp | med cc | out/resp | cc/resp | tools/resp |
|---|---|---:|---:|---:|---:|---:|---:|
| 1K–10K | teams-agent | 45 | **26,034** | 90,385 | 702 | 11,564 | — |
| 1K–10K | workflow-agent | 496 | **8,727** | 188,370 | 94 | 5,391 | — |
| 10K–50K | teams-agent | 749 | **50,569** | 164,601 | 1,115 | 7,136 | 1.34 |
| 10K–50K | workflow-agent | 159 | **26,467** | 223,868 | 317 | 5,109 | 1.24 |
| >50K | teams-agent | 354 | **52,546** | 308,755 | 1,149 | 6,894 | 1.16 |
| >50K | workflow-agent | **4** | **43,226** | 503,161 | 1,094 | 8,994 | 1.08 |

**Class penalty, size-controlled: 2.98× → 1.91× → 1.22×.** It *shrinks* monotonically with unit size.
About half of the headline 6× is a **size-usage artifact** and about half is a **class property**, and
the class property fades as the unit grows.

**Why**, and this is the generalisable law:

```
out/pp  =  1 / ( 7.93e-6  +  1.85e-6 × (cc_per_turn / out_per_turn) )
```

This is an identity given the exchange rate, not a fit — the *finding* is the empirical behaviour of
its two inputs. **`cc_per_turn` is roughly class-independent** (4,277–9,003 across every class and
band). **`out_per_turn` is not** — a workflow agent emits **94–317** output tokens per response where a
teammate emits **702–1,149**. The tax is levied per turn; the workflow agent's turns are small; it
therefore pays full price 3–7× more often for the same delivered work.

**Adversarial check — is that just "more tool calls, less prose"?** No. At matched size (10–50K),
tool-call density is **1.24 vs 1.34 tools/response** — the workflow agent makes *fewer* — yet emits
**256 output tokens per tool call vs the teammate's 830**.

**Adversarial check — is it a model-mix artifact?** No. Opus 5 dominates every class:
main 1,814/2,164 · teams 1,001/1,169 · workflow 1,578/1,781 · sidechain 596/694. The exchange rate
applies uniformly.

### 2.4 The efficient unit SIZE — a hump, and B4's inversion was real

Efficiency vs unit lifetime, **all units**, then vs response count:

| lifetime | n | cc/resp | out/resp | out/pp |
|---|---:|---:|---:|---:|
| <1 min | 574 | 23,681 | 129 | 2,883 |
| 1–5 min | 791 | 9,734 | 206 | 10,500 |
| 5–15 min | 1,708 | 6,256 | 460 | 30,202 |
| 15–60 min | 1,597 | **4,462** | 730 | 51,964 |
| 1–4 h | 670 | 4,811 | 939 | **57,451** |
| 4–12 h | 319 | 6,625 | 871 | 45,456 |
| >12 h | 149 | **15,276** | 990 | 27,421 |

| responses | n | cc/resp | out/resp | out/pp |
|---|---:|---:|---:|---:|
| 1–10 | 1,277 | 18,351 | 455 | 12,107 |
| 10–30 | 1,794 | 8,225 | 591 | 29,677 |
| 30–60 | 1,340 | 5,436 | 663 | 43,309 |
| **60–120** | 827 | **4,277** | 864 | **58,522** |
| 120–250 | 420 | 6,047 | 918 | 49,709 |
| 250+ | 150 | 9,236 | 759 | 32,861 |

`cc_per_turn` is **U-shaped**: high when the arrival cost is spread over few turns, minimal at 30–120
turns, and rising again past 120 turns as each turn re-caches a larger accumulated context. So
"fewer, bigger" is right up to a point and **wrong past it** — B4 recorded the >200K inversion at
**n=4** and told readers not to build on it; at **n=203** (output) and **n=468** (>4 h) it is a real,
smooth, two-sided effect.

**The number a plan author can use — implementation units only, fine sweep:**

| unit output | n | out/pp | med lifetime | med responses | med files |
|---|---:|---:|---:|---:|---:|
| 0–2K | 172 | 2,250 | 11 min | 26 | 1 |
| 2–5K | 123 | 6,705 | 15 min | 40 | 1 |
| 5–10K | 118 | 15,891 | 15 min | 41 | 1 |
| 10–20K | 187 | 26,947 | 16 min | 31 | 1 |
| 20–40K | 304 | 49,986 | 17 min | 36 | 2 |
| **40–80K** | 567 | **61,168** | **32 min** | **60** | **3** |
| **80–150K** | 557 | **58,454** | **73 min** | **107** | **6** |
| 150–300K | 298 | 46,352 | 252 min | 211 | 10 |
| >300K | 64 | 32,341 | 773 min | 310 | 15 |

> **Plan-authoring rule: size each implementation task at 40–150K output tokens ≈ 30–75 min ≈ 60–110
> assistant turns ≈ 3–6 files.** Below 20K output you lose >2× to per-turn tax; above 300K you lose
> ~2× to context re-caching. **Split a wave when a task exceeds ~10 files or ~4 hours; merge tasks
> when any one would produce under ~20K output.** Teammates today sit at a median of 36,848 output —
> *slightly under-sized*, which is a free ~19% on the current practice.

### 2.5 Can a workflow agent even reach that band?

| class | n | life p50 | p90 | p99 | max | out p50 | p90 | p99 | max | ≥10K out | ≥50K out |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| main-session | 2,164 | 34 m | 7.9 h | 37.3 h | 240.6 h | 53,414 | 191,211 | 378,501 | 1,569,440 | 70.4% | 52.0% |
| teams-agent | 1,169 | 21 m | 2.6 h | 16.6 h | 311.6 h | 36,848 | 80,713 | 146,888 | 216,629 | **94.4%** | 30.3% |
| workflow-agent | 1,781 | 9 m | 26 m | 3.1 h | 10.6 h | **356** | 9,233 | 25,994 | 74,131 | **9.2%** | **0.2%** |
| sidechain-subagent | 694 | 7 m | 22 m | 4.7 h | 11.2 h | 747 | 8,131 | 27,248 | 85,073 | 6.8% | 0.3% |

**Nothing structural stops it** — the largest observed workflow agent produced **74,131** output tokens
over **10.6 h**, inside the efficient band, and those 4 units scored 43,226 out/pp (near teammate
parity). **What stops it is how the class is used:** 90.8% of workflow agents never clear 10K output,
and the median is 356. A rule change that said "carry implementation waves in workflows" would be
betting on a usage pattern with **4 instances in 30 days**.

### 2.6 Cost per unit of implementation ACTUALLY SHIPPED

"Shipped" proxies, both grepped over each class's own transcripts with `/usr/bin/grep` (the interactive
`grep` on this box is a ugrep shim — repo memory `interactive-grep-is-ugrep-not-usr-bin-grep`; the shim
returned **0 for a `"type":"assistant"` positive control**, i.e. it silently answers nothing):

- **loose** — the unit ran `git commit` at least once;
- **strict** — git's own commit line `[<branch> <sha>]` appears in a tool result.

| class | units | ran `git commit` | confirmed `[branch sha]` | class pp | **pp per confirmed commit** |
|---|---:|---:|---:|---:|---:|
| main-session | 2,164 | 1,218 (56.3%) | 649 (30.0%) | 3,480.5 | **5.36** |
| teams-agent | 1,169 | 327 (28.0%) | 84 (7.2%) | 974.2 | **11.60** |
| workflow-agent | 1,781 | 110 (6.2%) | **12 (0.67%)** | 591.7 | **49.31** |
| sidechain-subagent | 694 | 105 (15.1%) | 3 (0.43%) | 212.2 | **70.73** |

The 110 loose workflow "committers" have a **median output of 107 tokens and a median of 0 write
calls** — the string is a mention, not a commit. The strict count, **12 of 1,781**, is the real one.
This is the axis's title metric and it is the widest gap in the study: **routing implementation
through workflow agents costs 4.3× more quota per unit that produced a commit than teammates and
9.2× more than a plain session.** (Denominator caveat: it includes read-only workflow agents that
were never asked to commit — it is a *population* statement about how the class is actually used,
which is precisely what a standing rule governs.)

### 2.7 The wave arithmetic — N teammates vs an N-agent workflow vs N dispatched sessions

**Model.** One task requires **T = 45,000 output tokens** of implementation (the measured median IMPL
teammate unit, 45,384 — inside the efficient band). Worker cost per task, from §2.3 constants:

```
turns = T / out_per_turn ;  cc = turns × cc_per_turn ;  pp = T×7.93e-6 + cc×1.85e-6
```

| vehicle | out/turn | cc/turn | turns for T | cache-creation | **pp/task** |
|---|---:|---:|---:|---:|---:|
| teammate | 1,130 | 7,000 | 39.8 | 278,761 | **0.873** |
| dispatched session | 900 | 5,600 | 50.0 | 280,000 | **0.875** |
| workflow agent | 317 | 5,109 | 142.0 | 725,252 | **1.699** |

**Lead-side term, MEASURED medians** (a lead's own pp, by how many units it fanned out to):

| Agent-tool spawns | n | lead's own pp | lead's own out/pp | | `--notify-back` fires | n | lead's own pp | lead's own out/pp |
|---|---:|---:|---:|---|---|---:|---:|---:|
| 0 | 1,726 | 0.65 | 51,822 | | 0 (recycle only) | 1,065 | 1.20 | 57,139 |
| 1–2 | 150 | 1.27 | 56,053 | | 1 | 28 | 3.88 | 35,071 |
| 3–5 | 152 | 1.81 | 50,191 | | 2–3 | 24 | 3.56 | 42,157 |
| 6–11 | 100 | 2.44 | 40,795 | | 4–6 | 25 | 4.04 | 35,552 |
| 12+ | 36 | **5.73** | **27,014** | | 7–12 | 14 | 6.15 | 33,141 |

**Totals** (primary fit 7.93/1.85; the winner is unchanged under 9.27/1.04 — §2.7 sensitivity below):

| N | (a) N teammates | (b) N-agent workflow | (c) N dispatched sessions | winner |
|---:|---|---|---|---|
| **2** | 2×0.873 + 1.27 = **3.02 pp** | 2×1.699 + 1.27 = **4.67 pp** | 2×0.875 + 3.56 = **5.31 pp** | **(a)** |
| **5** | 5×0.873 + 1.81 = **6.17 pp** | 5×1.699 + 1.81 = **10.30 pp** | 5×0.875 + 4.04 = **8.41 pp** | **(a)** |
| **12** | 12×0.873 + 5.73 = **16.20 pp** | 12×1.699 + 5.73 = **26.11 pp** | 12×0.875 + 6.15 = **16.65 pp** | **(a)** |

per task shipped: N=2 → **1.51 / 2.33 / 2.65** · N=5 → **1.23 / 2.06 / 1.68** · N=12 → **1.35 / 2.18 / 1.39** pp.
Ratios to (a): workflow **1.55× / 1.67× / 1.61×**; dispatch **1.76× / 1.36× / 1.03×**.

**Sensitivity, A1 raw fit (9.27 / 1.04):** totals N=2 → 2.68 / 3.61 / 4.98; N=5 → 5.35 / 7.67 / 7.58;
N=12 → 14.21 / 19.79 / 14.65. **Winner (a) at every N under both rates.** Workflow's penalty narrows
to 1.35–1.43× because cache-creation is priced lower on that fit; it never reverses.

**Two things this table says that the current rule does not:**

1. **A workflow's per-task premium is 1.35–1.67×, not 3× and not 6×** — because at a full task size the
   class penalty is only 1.9×, and the lead term is shared. The honest cost argument against workflows
   for implementation is **1.5×, plus the fact that no workflow agent in 30 days actually carried a
   full-size task** (§2.5) — not the headline 6×.
2. **Dispatched sessions have NO quota advantage over teammates** — 1.03–1.76× *worse*, converging to
   parity only at N=12. Length-controlled, a dispatching lead is not cheaper than a spawning one:
   at 80–199 responses, out/pp is 63,350 (no fan-out) · 51,326 (≥3 Agent spawns) · **40,643 (≥3
   `--notify-back` fires)**; at 200+ they converge at 31,743 vs 32,341. **Dispatch buys the lead's
   CONTEXT WINDOW — the resource whose exhaustion kills sessions outright — not quota.** CLAUDE.md's
   "whose context absorbs the work" framing is correct and this axis supplies no reason to weaken it;
   but a plan author reading it should not expect a quota saving.

---

## 3. What I could NOT measure, and why

1. **The exchange rate is QUOTED, not re-fitted.** `7.93 / 1.85 pp per Mtok` comes from A6 via B4. I
   verified it reproduces B4's own published `pp` column from B4's own token totals, and I ran every
   ratio under the A1 alternative — but I did not independently regress tokens against the live weekly
   meter. If the true rate has drifted, all *absolute* pp figures move; every *ratio* moves less
   (§2.7 shows the direction is invariant).
2. **The workflow >50K band is n=4.** The 1.22× size-controlled figure is the least-powered number
   here and should not be quoted alone. It is the single measurement that would most change the
   verdict if it grew — and it can only grow by someone deliberately running big workflow agents.
3. **Workflow-orchestrating leads are not separable in my lead-side table.** `nspawn` counts `Agent`
   and `Task` tool calls; a workflow's internal `agent()` calls are not `Agent` tool_use blocks, so a
   workflow-heavy lead falls into the `0 spawns` bucket. Row (b)'s lead term therefore **borrows the
   teammate lead's curve** — INFERRED, and the direction of the error is unknown.
4. **The lead-side term is an association, not a causal estimate.** Leads that fan out are doing
   bigger jobs. I controlled for length (response count) and the effect survived (−19% for Agent
   spawns, −36% for dispatch fires at 80–199 responses), but I could not run the counterfactual.
5. **"Confirmed commit" is a text proxy.** `[branch sha]` in a tool result is specific to `git
   commit`'s own output, but a commit made by a hook, a script, or `/ship` may not surface that line
   in the agent's transcript at all — so 7.2% for teammates is a **floor**, not the true landing rate.
   The comparison between classes is fair (same proxy, same corpus); the absolute rates are not.
6. **Nothing was spawned and nothing was killed.** No probe sessions, no fires, no config touched —
   this axis is entirely filesystem reads plus `git show` of the two predecessor documents (which are
   not on `main`; they live on `claude/fire-20260819T170309Z-21035-1`).
7. **Cost of a FAILED workflow agent is unpriced.** W1 measured that a failed agent returns `null`,
   preserves its worktree and reports no path. Those units still appear in my corpus and still cost
   their pp, but I cannot tell a failed agent from a successful small one, so the workflow figures
   here include an unknown fraction of pure waste — biasing the workflow class *favourably*.

---

## 4. The decision this axis changes

**On cost alone, the standing rule survives — but its stated cost argument should be re-stated, and
one adjacent sentence in CLAUDE.md is wrong.**

| | change |
|---|---|
| **Keep** | "Code-writing tasks with 2+ files MUST use Agent Teams" — teammates are the cheapest vehicle per shipped task at N=2, 5 and 12, under both exchange rates. |
| **Replace** | *"Background subagents are for research/exploration only — never for code changes"* as a **capability** claim. It is false (461 workflow agents wrote files in 30 days; W1 ran one that committed). The true reasons are: **(i)** a workflow agent costs **1.5–1.7× more quota per shipped task** and, at how the class is actually used, **49.3 pp per confirmed commit vs 11.6**; **(ii)** W1's finding that it cannot LAND. State those, and the question stops recurring. |
| **Correct** | The plan-authoring implication of "a dispatched session's context lands in its own window." True and worth keeping — but it should say **explicitly that it is a CONTEXT lever, not a quota lever**. Measured: dispatch is 1.03–1.76× *more* pp per shipped task than teammates, and a dispatching lead's own out/pp is *lower* than a spawning lead's at matched length. |
| **ADD — the missing number** | Plans currently declare a *locus* per wave and never a *size*. Add one field: **task size 40–150K output tokens ≈ 30–75 min ≈ 60–110 turns ≈ 3–6 files.** Below 20K, merge tasks; above 300K or 10 files, split. This is worth more than the locus choice: the spread across size bands is **27× (2,250 → 61,168 out/pp)**, while the spread across vehicles at matched size is **1.9×**. |
| **Free win already on the table** | Teammates today have a median output of 36,848 — below the 40–80K peak. Sizing current teammate briefs into the peak band is **~+19% quota efficiency at zero risk and no rule change.** |

**The one sentence.** *The vehicle is worth 1.9×; the size of the job you put in it is worth 27× — so
the rule that matters is not "teammates, not workflows", it is "one task per unit, 40–150K output
tokens wide, and never below 20K."*

---

## 5. Reproduction

```bash
D=docs/research/workflows-vs-teams-2026-08-20
python3 $D/W4-scan.py 720 /tmp/u720.json      # 30d: 6,015 files -> 5,808 units, ~4 min
python3 $D/W4-scan.py  60 /tmp/u60.json       # B4's window, for the cross-check

# pp = out_Mtok*7.93 + cc_Mtok*1.85 ; then group by u['cls'] / u['nwrite']>0 / u['out'] band / u['life'] band.

# "shipped" proxies — NOTE: the interactive `grep` here is a ugrep shim and returns 0 even for a
# "type":"assistant" positive control. Use the real binary:
awk '$1=="workflow-agent"{print $2}' paths.txt | tr '\n' '\0' \
  | xargs -0 /usr/bin/grep -l -m1 -E '\[[A-Za-z0-9._/-]+ [0-9a-f]{7,10}\]' | sort -u | wc -l

# every figure in this file drifts — B4's fleet number moved 1.8% in eight minutes.
# Re-run the scanner; do not cite these digits a week from now.
```
