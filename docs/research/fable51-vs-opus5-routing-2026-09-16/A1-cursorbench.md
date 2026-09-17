# A1 — CursorBench, read directly (2026-09-16)

Axis: the operator's primary cited source, <https://cursor.com/cursorbench>.
Every number below is **QUOTED from the vendor's own leaderboard**, never measured by us.
Instrument control: the board was fetched **twice with different prompts** and the six rows
in play came back **byte-identical** both times; a third-party aggregator (benchlm.ai)
independently reports the same two headline figures (51.8% / 46.6%) and the same version.

---

## 0. THE HEADLINE, BEFORE THE CAVEATS

**The operator's premise is real and it is readable off this source.** On the live board
there is not one qualifying point but **four**, and one of them is a *strict* dominance:

> **Fable 5.1 @ Medium (46.8%, $7.05/task) scores higher AND costs less than Opus 5 at
> High, Extra High, AND Max — all three of our upper configurations, simultaneously.**

And the single most decision-relevant row for this fleet:

> **Our actual default — Opus 5 @ High — ranks 8th at 44.7% / $9.00, BELOW the CHEAPEST
> Fable 5.1 configuration on the board (Fable 5.1 Low, 45.1% / $5.44, rank 7).**

That is the premise stated as sharply as the data allows. §4 and §5 are why it does not
settle the routing question on its own.

---

## 1. THE BOARD AS PUBLISHED — CursorBench **4.0**

**Version: CursorBench 4.0, published Sep 10, 2026.** This is NOT the 3.2.0 board that
either the SSOT comment or the Fable 5.1 launch post cites. See §6 — that reconciliation
is load-bearing and it kills a time series.

Columns, verbatim: `Model` · `Score` · `Cost / task` · `Tokens / task` · `Steps / task`.

Effort naming on the board is **Low / Medium / High / Extra High / Max** — a 1:1 map onto
Claude Code's own `low|medium|high|xhigh|max` ladder (Epoch AI's methodology page confirms
the same five-level enumeration). So "Extra High" = our `xhigh`. No translation needed.

### The two models in play, all efforts (verbatim rows)

| Rank | Model | Score | Cost/task | Tokens/task | Steps/task |
|---:|---|---:|---:|---:|---:|
| 1 | **Fable 5.1 Max** | **51.8%** | $17.28 | 117,236 | 128 |
| 2 | **Fable 5.1 Extra High** | **51.6%** | $13.01 | 87,294 | 101 |
| 3 | **Fable 5.1 High** | **49.2%** | $9.08 | 58,438 | 77 |
| 4 | **Fable 5.1 Medium** | **46.8%** | $7.05 | 45,411 | 63 |
| 5 | **Opus 5 Max** | **46.6%** | $11.95 | 85,384 | 106 |
| 6 | **Opus 5 Extra High** | **46.1%** | $11.43 | 80,094 | 103 |
| 7 | **Fable 5.1 Low** | **45.1%** | $5.44 | 34,795 | 51 |
| 8 | **Opus 5 High** ← *our default today* | **44.7%** | $9.00 | 61,405 | 86 |
| 9 | **Opus 5 Medium** | 43.3% | $6.94 | 45,272 | 72 |
| 14 | **Opus 5 Low** | 40.7% | $4.87 | 31,995 | 57 |

Every Fable 5.1 rung outranks every Opus 5 rung. The two ladders **interleave only once**:
Fable 5.1 Low (45.1) slots between Opus 5 xHigh (46.1) and Opus 5 High (44.7).

For orientation, the nearest competitors: GPT-5.6 Sol Max 41.7% / $8.23 (rank 10),
Muse Spark 1.3 Max 41.6% / $2.64 (11), Grok 4.6 xHigh 41.4% / $6.10 (12),
Sonnet 5 Max 34.1% / $7.17 (23), Composer 2.5 27.7% / $0.68 (36).
43 rows total; GPT-5.6 Luna Low is last at 16.0% / $0.03.

---

## 2. THE COST AXIS — WHAT IT IS, AND WHY IT IS **NOT OUR COST**

Cursor's methodology, verbatim:

> "Avg cost / task is computed by applying each model's **published per-million-token
> pricing** (input, cache read, cache write, and output) to the tokens it used on each task."

🚨 **This fleet does not pay published per-token pricing.** We run 4 Claude Max
subscriptions; the binding constraint is the **weekly quota**, and for Fable specifically
the `frontier_access.source: plan-usage` ceiling of "≤50% of limits". So the `$` column is
a *derived* figure over a price list we are not billed against — it is **QUOTED, and it is
about a different economy than ours**. Treating it as our cost is the same class of error
as reading a vendor's list price as a contract rate.

**The recast that does apply to us is the TOKENS column**, because quota is metered on
consumption. And it points the same way, harder:

| Comparison | Score | Cost | Tokens |
|---|---|---|---|
| Fable 5.1 Medium vs **Opus 5 High** | +2.1pp | **−21.7%** ($7.05 vs $9.00) | **−26.0%** (45,411 vs 61,405) |
| Fable 5.1 Low vs **Opus 5 High** | +0.4pp | **−39.6%** ($5.44 vs $9.00) | **−43.3%** (34,795 vs 61,405) |
| Fable 5.1 Medium vs Opus 5 Max | +0.2pp | −41.0% | −46.8% |

Fable 5.1's cheap rungs consume **fewer tokens** for equal-or-better score, which is the
axis a quota-metered fleet actually spends. The $ figure understates that direction if
anything, because Fable's list price is 2× — so the token win is being *taxed* in the $
column and still wins.

⚠️ **UNVERIFIED, and it is the one thing that could invert this**: whether Max-plan **quota
draw** is proportional to tokens, or whether Fable carries a per-token quota multiplier
(and whether the separate weekly-Fable limit `claude-accounts` reports is drawn first).
CursorBench cannot answer this and neither can I from this axis. If Fable draws quota at
a premium per token, the token win shrinks or reverses. **Flagging for the lead as the
decisive unknown on the cost side.**

---

## 3. THE OPERATOR'S EXACT COMPARISON — NAMED COORDINATES

The question was: *is there a (Fable 5.1 @ low or medium) point that BOTH scores ≥ and
costs ≤ a (Opus 5 @ high or xhigh) point?* **Yes — all four cells qualify.**

| # | Fable 5.1 point | Opus 5 point | Δ score | Δ cost | Δ tokens | Dominates? |
|---|---|---|---:|---:|---:|---|
| 1 | **Medium** 46.8% / $7.05 | **High** 44.7% / $9.00 | **+2.1pp** | −$1.95 | −16.0k | ✅ strict |
| 2 | **Medium** 46.8% / $7.05 | **Extra High** 46.1% / $11.43 | **+0.7pp** | −$4.38 | −34.7k | ✅ strict |
| 3 | **Low** 45.1% / $5.44 | **High** 44.7% / $9.00 | **+0.4pp** | −$3.56 | −26.6k | ✅ strict |
| 4 | *(bonus, beyond the ask)* **Medium** 46.8% / $7.05 | **Max** 46.6% / $11.95 | **+0.2pp** | −$4.90 | −40.0k | ✅ strict |

**The strongest cell is #1** — Fable 5.1 Medium over Opus 5 High, our live default — and it
is strongest precisely because its score gap (2.1pp) is the only one large enough to
survive §4's variance disclaimer. Cells #3 and #4 (0.4pp, 0.2pp) are inside the noise the
page itself warns about and should be read as **ties on score with a real cost win**, not
as Fable beating Opus.

Note the asymmetry that makes cell #1 the honest headline: it does not require believing
Fable is *better*. At 2.1pp it is at least not-worse, and it gets there on 26% fewer tokens
and 23 fewer agent steps (63 vs 86).

---

## 4. WHAT THE BOARD DOES **NOT** PUBLISH — the limits on all of the above

Read directly off the page, and the absences matter more than the presences:

- 🚨 **Cursor's own disclaimer, verbatim**: *"Results are subject to variance; small
  differences in scores may not be statistically meaningful."* The page ships this
  precisely because differences like 0.4pp and 0.2pp are in the table. **Cells #3 and #4
  above are exactly what this sentence is about.** Cell #1's 2.1pp is the only gap with
  any claim to signal, and even that has no interval attached.
- **No n.** The page does not state how many tasks are in the benchmark.
- **No runs-per-task, no pass@k, no confidence intervals, no error bars.** Nothing on the
  page establishes whether a cell is one sample or many. Absent a stated n, every gap here
  is an unbounded point estimate.
- **No harness disclosure.** The page does not say what scaffold runs the models, nor
  whether the effort levels are the vendor's or Cursor's own naming. It is Cursor's
  eval, so the safe assumption is **Cursor's agent harness, not Claude Code's** — different
  tool surface, different system prompt, different context management, different
  compaction behaviour. A ranking measured in one harness is a claim about that harness
  (cf. the corpus rule that a rendering verdict is only true at its measured geometry).
- **Vendor-run benchmark of a product Cursor sells access to.** Not disqualifying, but it
  is a first-party board, not an independent replication.

**Net:** this board supports "Fable 5.1's cheap rungs are at least cost-competitive with
Opus 5's expensive rungs on agentic coding, in Cursor's harness." It does not support a
precise ordering between adjacent cells, and it cannot support "Fable 5.1 Low ≥ Opus 5
High" as a *quality* claim — only as a tie with a cost win.

---

## 5. TASK DISTRIBUTION — HOW WELL DOES IT PROXY **OUR** WORK?

The page, verbatim: *"We evaluate agents on **ambiguous, multi-file tasks from real Cursor
sessions**."* The 4.0 changelog, verbatim: *"Introduced new **long-horizon problems**
focused on **edit, refactor, investigation, intent understanding, managing jobs, and design
adherence**."*

**This is agentic multi-turn work in a real repo, not single-shot.** The `Steps / task`
column is the structural proof: 51–128 agent steps per task across the cells in play. A
single-shot benchmark cannot produce that column.

Proxy quality for this fleet, by work class:

| Our work class | Proxy quality | Why |
|---|---|---|
| Long agentic infra sessions (hooks, bash, tests, multi-file edits) | **GOOD** | This is literally the measured shape — multi-file, long-horizon, ambiguous, tool-driven. |
| "Managing jobs" / orchestration | **GOOD, and newly so in 4.0** | 4.0 explicitly added it. Closest public proxy to our dispatch/wave work that exists. |
| Instruction-following under a large resident ruleset | **PARTIAL** | 3.2 added instruction-following problems; but nothing here tests a ~94KB always-loaded CLAUDE.md, which is a defining feature of our sessions. |
| Code review / defect recall | **WEAK** | Not the measured shape, and this is exactly where **our own** measurement disagrees — see below. |
| Research synthesis over web sources, adversarial judging | **NOT MEASURED AT ALL** | No web-research or judge-panel component. Silent on `research_adversarial`, `workflow_judge`, `eval_judge`. |

🚨 **The disagreement with our own sweep is real but is NOT a contradiction — the two
measure different task classes, and they disagree in the direction their shapes predict.**
`docs/research/fable51-effort-sweep-2026-09-10/` (MEASURED BY US, 45 cells, ~$182) found
Opus 5 @max 12/25 beating every Fable 5.1 effort (best 10/25) on **anchored review of a
single file** — single-shot defect recall, one sample per cell. CursorBench measures
**multi-file long-horizon agentic execution**. The honest synthesis is not "one of them is
wrong": it is that we currently have evidence Fable 5.1 is **weaker at single-shot review
recall** and **stronger at long-horizon agentic execution**, from two instruments each
measuring one of those and neither measuring the other.

That reading has a direct routing consequence and it points *against* a blanket flip:
the SSOT already routes `research_adversarial` and review-gate teammates to frontier, which
is the surface our own sweep says Fable 5.1 is *worse* at — while CursorBench says the
lead-session surface, which the SSOT keeps on Opus, is where Fable 5.1 is better. **Both
instruments, taken together, suggest the current SSOT may have the two assignments
backwards.** That is a hypothesis this axis raises and cannot settle; it belongs to the
lead's synthesis.

---

## 6. VERSION RECONCILIATION — 🚨 **THREE DIFFERENT BENCHMARKS, NOT A TIME SERIES**

| Source | Version | Figures | Attribution |
|---|---|---|---|
| SSOT `roles.teammate_frontier` comment (2026-06-11) | 3.1/3.2-era | Fable@high **70.6%** / $11 vs Opus@max **63.8%** | **Fable 5 vs Opus 4.8.** The SSOT says so itself, verbatim: *"Every benchmark number in the comments below was measured on Fable 5 and is NOT re-attributed — routing claims move, measurements stay."* |
| Anthropic Fable 5.1 launch post (2026-09-06) | **3.2.0** | Fable 5.1 **73.4%** @max vs Fable 5 **70.5%** @max | Fable 5.1 vs Fable 5. **Opus 5 is not in this pair at all.** |
| Anthropic Opus 5 launch post (earlier) | **3.2** | Opus 5 @max "within 0.5% of Fable 5's peak, at **half the cost per task**" ($2.34 vs $3.76) | Opus 5 vs **Fable 5** |
| **cursor.com/cursorbench, TODAY** | **4.0** (Sep 10, 2026) | Fable 5.1 Max **51.8%** / $17.28 vs Opus 5 Max **46.6%** / $11.95 | Fable 5.1 vs Opus 5 |

**Today's board is a DIFFERENT BENCHMARK VERSION from every prior datapoint we hold.**
Third-party coverage states it plainly: *"Because the difficulty increased, all AI models
score lower on 4.0 than they did on 3.x, so scores across the two versions are not directly
comparable."*

Three consequences, and the second is the trap:

1. **Do not construct a trend.** 70.6 → 73.4 → 51.8 is not a decline; it is three different
   yardsticks. A benchmark that re-versioned is not a time series.
2. 🚨 **The COST figures re-versioned too, and by more than the scores.** Opus 5 @max on
   3.2 was **$2.34/task**; on 4.0 it is **$11.95/task** — 5.1×. Fable Max went $3.76 → $17.28.
   4.0's tasks are simply much longer-horizon. **So the 3.2-era cost ratio (Opus at "half
   the cost per task") has been INVERTED on 4.0** — Opus 5 Max now costs $11.95 against
   Fable 5.1 Medium's $7.05 for a *lower* score. Anyone reasoning from the remembered
   "Opus is half the cost" line is reasoning from a superseded board. The SSOT's
   `max_fable_spawns_per_session` rationale cites a *"CursorBench $18-vs-$15 band per
   task"* which matches neither 3.2 nor 4.0 and should be re-derived, not quoted.
3. **The SSOT's `70.6% vs 63.8%` comment is correctly labelled and is NOT stale in the way
   it looks** — it is an honest Fable 5 / Opus 4.8 record that the SSOT explicitly declines
   to re-attribute. It is simply no longer *relevant* to a Fable 5.1 / Opus 5 decision.
   Leave the measurement; the routing claim above it is what is in question.

---

## 7. WHAT THIS AXIS SETTLES AND WHAT IT DOES NOT

**SETTLES (on this source, as QUOTED vendor data):**
- The operator's premise is not a misreading. Fable 5.1 Medium strictly dominates Opus 5 at
  High, Extra High and Max on both score and cost, on CursorBench 4.0.
- Our live default, Opus 5 @ High, is the **8th** row and sits below Fable 5.1's cheapest rung.
- The task shape measured (long-horizon, multi-file, ambiguous, job-managing) is a good
  proxy for our agentic infra sessions.

**DOES NOT SETTLE:**
- Statistical significance of any gap — no n, no runs, no CI, and the page's own disclaimer
  disowns small differences. Only the 2.1pp Medium-vs-High cell has any margin at all.
- Our actual cost. The $ column is published-token-price arithmetic against a price list a
  Max-plan fleet is not billed on. The quota-draw question is the real one and is open.
- Harness transferability. Measured in Cursor's agent, not Claude Code's.
- Anything about research synthesis, adversarial review, or judge panels — three of the six
  SSOT roles currently pinned to frontier are simply not in this benchmark's scope.
- Whether Fable 5.1 Medium's win survives a 94KB resident-instruction session, which is our
  single most distinctive workload property and is untested by anyone.

---

## Sources
- [Cursor · CursorBench](https://cursor.com/cursorbench) — the live 4.0 board; fetched twice, identical
- [CursorBench | Epoch AI](https://epoch.ai/benchmarks/cursorbench) — effort-level enumeration
- [CursorBench Leaderboard & Scores — September 2026 | BenchLM.ai](https://benchlm.ai/benchmarks/cursorbench) — independent corroboration of 51.8 / 46.6 and the 4.0 version
- [Introducing Claude Fable 5.1 and Claude Mythos 5.1 \ Anthropic](https://www.anthropic.com/claude-fable-and-mythos-5-1) — 3.2.0 figures, cache-read pricing, effort defaults
- [Introducing Claude Opus 5 \ Anthropic](https://www.anthropic.com/news/claude-opus-5) — the 3.2 "half the cost per task" claim
- [Cursor releases CursorBench 4.0 ... | daily.dev](https://daily.dev/posts/cursor-releases-cursorbench-4-0-with-harder-instruction-following-and-long-horizon-tasks-wa9xuaf5w) — 4.0 non-comparability with 3.x
