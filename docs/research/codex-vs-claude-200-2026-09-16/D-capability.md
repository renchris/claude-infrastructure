# D — Capability: OpenAI GPT-6 "Astra" vs Anthropic Claude Fable 5.1

Research date **2026-09-16**. All figures dated. Vendor-self-reported vs independent labelled on every row.

**Headline for the $200/mo decision:** on coding/agentic *quality* the two are a statistical tie under every
neutral instrument found. They separate on **token burn per unit of work**, where Astra wins decisively
(~58% of Fable 5.1's tokens per coding-agent task, ~35% on the general index) — but that advantage is an
**API-economics** fact that does **not** transfer cleanly to a subscription, because both vendors cut
subscription quota in September and Anthropic's headline price cut is a *cache-read* discount that
subscription metering does not pass through.

---

## 0. The two models, dated

| | GPT-6 Astra | Claude Fable 5.1 |
|---|---|---|
| Released | **2026-09-03** | **2026-09-01** |
| API list price | $10 / $50 per Mtok in/out | $10 / $50 per Mtok in/out |
| Cache read | $1.00/Mtok ($2.00 above 272K) | **$0.25/Mtok** (75% cut vs Fable 5) |
| Cache write | $12.50/Mtok | $12.50/Mtok |
| Context | 1.05M | 1M |
| Max output | 128K | 128K |
| Knowledge cutoff | 2026-04-30 | 2026-06 |
| Effort levels | low … max ("Fast mode" 2.5× speed at 2× price) | low / medium / high / xhigh / max (default **High** in Claude Code, Medium in Claude.ai) |
| Coding harness | Codex | Claude Code, Cursor |

Sources: [Anthropic launch post](https://www.anthropic.com/claude-fable-and-mythos-5-1) (vendor),
[DataCamp head-to-head](https://www.datacamp.com/blog/gpt-6-astra-vs-claude-fable-5-1) (2026-09),
[AA comparison page](https://artificialanalysis.ai/models/comparisons/gpt-6-astra-vs-claude-fable-5-1).

🚨 **List price identical. Everything that matters is downstream of it.**

---

## 1. Head-to-head coding / agentic benchmarks

### 1a. Vendor self-reported (each vendor ran the other's model in its own scaffold)

| Benchmark | Astra | Fable 5.1 | Opus 5 | GPT-5.6 Sol | Reported by |
|---|---|---|---|---|---|
| **Terminal-Bench 4.0** | **57.7%** (one source 57.9%) | 55.8% | 52.3% | 37.3% | Both vendors publish ~same pair |
| **Terminal-Bench-Science 0.1** | **64.6%** | 52.6% | 29.0% | 22.4% | OpenAI / Anthropic |
| **DeepSWE v1.1** (113 agentic tasks) | **74.1%** | 67.4% | ~73.7% | 72.7% | OpenAI table; Muse Spark 1.3 leads at 75.4% |
| **FrontierCode 1.1 Extended** | 64.5% | 64.9% *(Fable 5)* | 53.4% | — | OpenAI — effectively tied |
| **FrontierCode Main** | 53.3% | 53.5% *(Fable 5)* / 50.9% (5.1) | 53.4% | — | OpenAI — tied |
| **CursorBench 3.2.0** | not published | **73.4%** | 70.0% | 67.2% | Anthropic only |
| **AutomationBench** | **41.4%** | 31.4% | 26.9% | 18.1% | OpenAI |
| **OSWorld 2.0** | **72.6%** | 77.9% partial / 41.7% strict | 75.4%p / 39.6%s | 65.7% | ⚠️ *different scoring modes — not comparable as printed* |
| **SWE-bench Pro** | — | **81.2% (#1)** | 79.2% | — | leaderboard, 2026-09-08 |
| **HLE (with tools)** | 57.2% | **65.0%** | 63.6% | — | each vendor |
| **FrontierMath Tier 4 v2** | **97.6%** | 87.8% | 73.2% | — | OpenAI (⚠️ OpenAI funded FrontierMath and has exclusive access) |

**Read:** on *coding specifically* the vendor tables give Astra ~+2pp on Terminal-Bench 4.0 and ~+7pp on
DeepSWE, and give Fable the only CursorBench number and the SWE-bench Pro #1. Nothing here is a clean win.

### 1b. SWE-bench Verified — **saturated, do not use**

- Fable 5 scored **95%**. Anthropic **did not headline a SWE-bench Verified number for 5.1 at all**, and
  neither did OpenAI for Astra. Multiple sources now describe Verified as contaminated; SWE-bench **Pro**
  and DeepSWE v1.1 are the successors ("tasks written from scratch, not adapted from existing commits").
- ⇒ Any comparison built on SWE-bench Verified in Sept 2026 is measuring a dead eval.

### 1c. 🚨 Contested: ARC-AGI-3 — the harness, not the model

| | Score | Harness |
|---|---|---|
| Astra, OpenAI-reported | **99.9%** | OpenAI **Provider Adapter** (preserves opaque reasoning state between requests, compacts long conversations) |
| Astra, **ARC Prize independent** | **62.7%** | ARC Prize **Standard** harness |
| Claude Opus 5 | 30.2% | Standard |
| GPT-5.6 Sol | 7.8% (standard) | — |

OpenAI had previously shown the harness choice alone moved Sol from **13.3% → 38.3%**. So the 99.9% is not
comparable to any competitor number.
Source: [WinBuzzer, 2026-09-04](https://winbuzzer.com/2026/09/04/gpt-6-astra-arrives-with-major-gains-staged-access-and-new-questions-about-its-benchmarks-xcxwbn/).

**Generalise the lesson:** every "Astra vs Fable" table in the wild mixes harnesses (Codex vs Claude Code).
The agent is part of the measurement.

---

## 2. Independent leaderboards

### 2a. Artificial Analysis **Coding Agent Index** — the most decision-relevant board

Composition (from AA's own page): **DeepSWE v1.1 + Terminal-Bench 4.0 + SWE-Atlas-QnA, equally weighted.**
⚠️ One third of it is a **Q&A** benchmark, not agentic execution.

**Live comparison page, index v1.5, read 2026-09-16:**

| Agent + model (max effort) | Index | **Cost/task** | **Tokens/task** |
|---|---|---|---|
| Claude Code — **Fable 5.1** | **62** | **$12.39** | **5.7M** |
| Codex — **GPT-6 Astra** | **62** | **$7.47** | **3.3M** |
| Claude Code — Opus 5 | 60 | $10.79 | 11.4M |
| Codex — GPT-5.6 Sol | 55 | $6.58 | 10.2M |

**Full board snapshot, 2026-09-15** (via BenchLM mirror): Claude Code–Fable 5.1 (max, w/ fallback) **62.2%**
· Devin Fusion CLI–Fable 5.1 XHigh+SWE-2 **61.7%** · Codex–Astra (max) **61.6%** · Claude Code–Opus 5 (max)
**59.7%** · Codex–Sol (max) 54.6% · Muse Code–Muse Spark 1.3 54.3% · Opencode–GLM-5.3 53.6% ·
Kimi Code CLI–Kimi K3 51.9% · Grok Build–Grok 4.6 (xhigh) 47.0% · Antigravity–Gemini 3.8 Flash (high) 41.9%.

🚨 **The index was revised mid-month and the numbers moved a lot.** At launch (v1.0/v1.1, ~2026-09-09)
sources quote **Astra 67.0 vs Fable 5.1 70** (or 67.2). By v1.5 both sit at **62**. *Any figure in the
60s-vs-70 range is from a superseded version.* Cite the version or don't cite the number.

### 2b. Artificial Analysis **Intelligence Index** — also revised mid-month

- **v4.1.1 / launch (2026-09-01):** Fable 5.1 **66** (max), Opus 5 63, Fable 5 62, Sol 61, Grok 4.6 61.
- **v4.2 (2026-09-05):** interim overhaul — added AA-Briefcase + GDP.pdf, **removed GPQA Diamond as
  saturated**, raised private held-out weighting from 20% → **40%**. Fable 5.1 stayed #1, Astra #2.
- **v4.3 (live, read 2026-09-16):** **Astra 53 · Fable 5.1 53 — a dead tie.**
- AA's own caveat: the 95% CI on the index is **< ±1 point**, so the Astra-61.2 vs Sol-60.9 gap at launch
  was statistically flat. The same caveat kills any 1-point Astra/Fable claim.

Cost to run the whole Intelligence Index (v4.3 page): **Astra $5,324 · Fable 5.1 $13,129** — 2.5×.

### 2c. LMArena / Arena **agent leaderboard** — the one neutral single-harness board

Read live from [arena.ai/leaderboard/agent](https://arena.ai/leaderboard/agent?rankBy=labs), **dated
2026-09-15**:

| Rank | Model | Net improvement | Confirmed success |
|---|---|---|---|
| 1 | **Claude Fable 5.1 (Max)** | **13.71% ± 1.72** | 19.83% ± 2.75 |
| 2 | **GPT-6 Astra (Max)** | **11.54% ± 2.10** | 17.70% ± 3.26 |

**Error bars overlap** ([11.99, 15.43] vs [9.44, 13.64]). Fable leads; the lead is not significant.
Board also tracks steerability, bash-failure recovery and tool-hallucination rate.
⚠️ Earlier snapshots circulating as "14.51% vs 12.55%" are a few days stale — this board moves.

### 2d. **Aider polyglot — dead for this question.** Leaderboard last shows **GPT-5 (high) at 88.0%**
leading, 22 models tracked. Neither Astra nor Fable 5.1 is on it. Do not use.

### 2e. **SWE-rebench** (decontaminated, rolling window) — **neither model is on it.**
Current window 2026-05-15 → 2026-07-01, 111 problems / 65 repos: Fable 5 **64.5% ±1.41** (#1),
Opus 5 **63.4% ±1.35**, Sol **62.3% ±1.83**. No Astra, no Fable 5.1 entry.
⇒ The best contamination-controlled board has not yet rated either subject.

### 2f. **METR time horizons** — no direct measurement of either model.
METR's page lists nothing for Astra, Sol, Fable 5.1, Fable 5 or Opus 5, and states it "may not have
measurements for some time after release, or may skip certain releases entirely."
The only figure found: **UK AISI measured Astra's no-CoT time horizon at 30.9 min vs 3.6 min for Sol**; a
LessWrong estimate puts Astra's 50% horizon at **8 min – 1 hr, probably 15–40 min**. **No Fable 5.1
counterpart exists**, so this axis cannot adjudicate the two.

---

## 3. 🚨 Token efficiency — the axis that actually decides a quota-limited plan

### 3a. Measured, independent (Artificial Analysis)

| Measurement | Astra | Fable 5.1 | Ratio |
|---|---|---|---|
| Output tokens / task, Intelligence Index (max) | **27k** | **78k** | Astra = **35%** |
| Output tokens to run whole index | **60M** | **188M** | Astra = **32%** |
| Tokens / task, Coding Agent Index (max) | **3.3M** | **5.7M** | Astra = **58%** |
| Cost / task, Coding Agent Index (max) | **$7.47** | **$12.39** | Astra = **60%** |
| Output speed | 52 tok/s | 66 tok/s | Fable faster |
| Time to first token | 336.8s | 282.9s | Fable faster |

AA's own framing: Astra "uses **one third** of the tokens of GPT-5.6 Sol (max) in Codex, and **one fifth**
of the tokens of Claude Opus 5 (xhigh)"; it "ties Claude Fable 5.1 at ~60% of the cost per task, driven by
**the lowest token use of any agent in the Index**."

### 3b. Fable 5.1 got *chattier*, deliberately

- **1.7× the output tokens of Fable 5** (143.7M vs 83M on the index) for a higher score.
- Across five effort levels output spans an **11× range: 13.1M (low) → 143.7M (max)** for index **58 → 66**.
- One practitioner's Claude Code logs: **1,207 tokens/turn on 5.1 vs 990 on Fable 5 (+22%)**.
- **The effort lever is the biggest single value knob available.** xhigh scores **65 vs max's 66** at
  **$2.72 vs $3.76/task** — 1 index point for 28% of the cost. Low effort runs **$0.82/task**.

### 3c. Real-world practitioner runs — note they **invert** the AA ordering

- One tester, 2026-09-06, same task suite: **Astra $198 in tokens vs Fable 5.1 $113** — Astra ~75% *more*
  expensive. Astra via Codex with "Ultra Thinking"; Fable via a third-party harness. Scores 90% vs 92.5%
  on the tester's own KingBench 3. The author warns the gap "reflects these particular tools and settings."
- Reported Astra habits that inflate token cost: defaults to landing-page layouts unasked, recurring green
  colour schemes, generic card/grid UI, **over-complicates simple requests**.
- One physics-sim probe: **Astra 6 turns / 9 tool calls / 5.0 rubric** vs **Fable 5.1 2 turns / 1 tool call
  / 4.3 rubric** — i.e. Astra *did more work* for a slightly better answer on that task.

⚠️ **These two bodies of evidence disagree and I could not reconcile them.** AA measures at max effort in
each vendor's own first-party harness over a fixed suite; the practitioner runs vary harness, effort and
task. The AA numbers are the better-controlled instrument; the practitioner numbers are the better proxy
for *this* operator's workload. Treat token efficiency as **direction-established (Astra leaner per task in
controlled conditions), magnitude unsettled.**

---

## 4. Behaviour in long autonomous runs

| Axis | Astra | Fable 5.1 |
|---|---|---|
| Context | 1.05M; **charges a long-context surcharge** — cache read $1→$2/Mtok above 272K | 1M; **no long-context surcharge** (a 10M-tok retrieval workload: Fable $150, Astra $275) |
| Long-context retrieval | **MRCR v2: 100%** at 256–512K, **96.3%** at 512K–1M (vs Sol 91.5 / 73.8) — *OpenAI-reported* | **No published MRCR/needle figure for 5.1.** Closest datum: Opus 4.6 scored 76% on MRCR v2 8-needle at 1M |
| Context management | "keeps **notes** across context windows instead of repeatedly compressing into a single summary"; earlier windows "stay searchable" | Anthropic markets "multi-day autonomous sessions", unattended runs over a 200K-token codebase, self-written tests, vision self-verification, failure recovery |
| Thinking control | reasoning effort low…max | **adaptive thinking always on** + 5 discrete effort levels |
| Known failure | **context-management experiment bug caused early stops and replies to stale messages**, ~4,000–5,000 users, confirmed 2026-09-12 | — |
| Chattiness at high effort | — | "At xhigh and especially max, Fable 5.1 can **think for longer before starting to write**" |
| Turn/tool behaviour | more turns + more tool calls on the one probe measured (6/9) | fewer turns, fewer tool calls (2/1), marginally lower rubric |

**Gap I could not close:** no published max-sustained-turn-count for either model, and **no long-context
degradation curve for Fable 5.1 at all**. Astra's MRCR numbers are vendor-run and unreplicated. Anyone
deciding on "degradation at long context" is currently choosing on one vendor's self-report vs silence.

---

## 5. 🚨 Degraded / quantized serving to subscription users

### 5a. Astra — **degradation officially confirmed; quantization not**

- Week of **2026-09-08**: widespread reports Astra "got dumber" — worse code, faster answers, more
  inconsistency. Users speculated quantization ("they probably get quantized so they're not burning the
  company as much money"). **OpenAI has never confirmed quantizing a shipped model.**
- **2026-09-12, Tibo Sottiaux (Codex/ChatGPT lead) postmortem confirmed three real causes:**
  1. **legacy skills misfiring** — skills written for prior models "triggered too aggressively or prevented
     Astra from checking its own work";
  2. **context-management experiment bug** — "caused early stops and replies to stale messages", ~4–5k users;
  3. 🚨 **"misconfigured serving engines that degraded quality for a long tail of traffic."**
- OpenAI ran a **full usage reset for Codex and Astra users at midnight 2026-09-12→13**.
- **Still unexplained:** reports that **xHigh reasoning burned *less* quota than Medium**, and usage caps
  **up to 4× tighter than launch week** (no primary OpenAI confirmation of the 4× figure).
- Precedent: **GPT-5.6 Sol, July 2026** — same backlash; Sottiaux admitted "been experimenting with
  reasoning effort" but denied deliberate weakening.

**⇒ This is the strongest evidence in the whole brief: a first-party admission that serving infrastructure
degraded output quality for a traffic tail, on the model in question, four days ago.**

### 5b. Anthropic — **routing-to-a-weaker-model is a documented, standing behaviour**

- Not quantization, but the same user-visible effect: when Fable's **safety classifiers** flag a request
  (cybersecurity, bio/chem, model distillation, "frontier LLM training"), the request is **served by a less
  capable model (Opus)** instead. Anthropic **initially planned to degrade silently and reversed after
  backlash on 2026-06-11** — the policy is now to downgrade *transparently*.
- Practical bite on coding: the **2026-07-02 Fable 5 relaunch** drew reports that security-adjacent words
  ("vulnerable", "unsafe", "hook") and systems work in C/C++/Rust/Win32 kicked requests down to Opus 4.8 —
  *"didn't even let me search for dead code without switching to Opus."* Anthropic said the model was not
  technically degraded; the guardrails were over-firing. No postmortem.
- **Fable 5.1 is reported to have a materially less trigger-happy safety layer**, but I found no
  quantitative measurement of the downgrade rate on 5.1 — this is a reported impression, not a number.
- **2026-09-03:** genuine outage — elevated errors on Mythos 5.1 / Fable 5.1 / Opus 5, resolved 16:16 UTC.
  Availability, not quality.
- **Precedent, and Anthropic's standing denial:** the Aug 5 – Sep 5 **2025** "Model output quality"
  incident (Sonnet 4, Haiku 3.5, Opus 3), resolved 2025-09-17 with an engineering-blog postmortem, states:
  *"we never intentionally degrade model quality as a result of demand or other factors."*

**⇒ Both vendors have a live, documented mechanism by which a subscription user can receive worse output
than the benchmark model: OpenAI's is an infrastructure defect they admitted; Anthropic's is a deliberate,
disclosed safety-routing downgrade that disproportionately hits security-adjacent and systems coding.**

---

## 6. Subscription economics — where the API numbers stop applying

### Claude Max $200 (20×)
- Dual meter: rolling **5-hour** window + a **weekly** cap. **Fable 5/5.1 may consume up to 50% of the
  weekly allowance** — unchanged for 5.1.
- 🚨 **The headline "25–45% cheaper" is a *cache-read* discount and subscription users get no cache
  discount.** On a subscription you pay Fable 5.1's **1.7× output-token appetite** with none of the offset.
- Launch-week reports: Max users draining a 5-hour window in **15–30 minutes**; one developer reported a
  **full Max-20× 5-hour quota gone in 52 minutes from a single prompt** (sub-agent fan-out); others capped
  in ~4 minutes on heavy cache activity. One careful analysis: *"you might have 1/3 to 1/4 the real
  Fable-minutes that you did yesterday."* Anthropic reset limits at launch and offered boosts to mid-Sept.
- **2026-09-14: Claude Code weekly capacity effectively cut ~17%** — the temporary +50% boost ended and was
  replaced by a permanent +25% (150 → 125 on a 100 baseline). Announced by Anthropic's ClaudeDevs account
  in late August; not hidden.
- Mitigation that is fully in the operator's hands: **run at High/xhigh, not max** (1 index point for ~28%
  less spend), **low for subagents**, and **edit rather than rewrite whole files**.

### ChatGPT Pro $200 (20×)
- **Astra is metered at roughly half the message rate of GPT-5.6 Sol on every plan**, per OpenAI
  (2026-09-05): Pro 20× gets **100–900 Astra messages / 5h** vs 200–2,000 for Sol; Plus 5–45 vs 10–100.
- **GPT-6 Pro: 200 messages/week on $200**, 50/week on $100. On $200, hitting the GPT-6 Pro weekly cap
  auto-falls back to GPT-5.6 Thinking (Medium).
- Codex and ChatGPT Work **share one Astra quota**.
- 🚨 **Rollout risk:** staged launch left paying subscribers without access for days; Altman called it
  "messy" and apologised **2026-09-04**; OpenAI banked one reset per day of missing access. On
  **2026-09-10 OpenAI paused new $200 Pro subscriptions** to protect quality for existing users.
- Reported caps **up to 4× tighter** than launch week — widely reported, **not** officially confirmed.

---

## 7. Adversarial pass — what I checked because it would have broken the answer

1. **"Is the Coding Agent Index measuring the model or the harness?"** — The harness. Rows are
   *Claude Code + Fable 5.1* vs *Codex + Astra*; Devin Fusion CLI with Fable 5.1 XHigh scores 61.7 and with
   Astra XHigh 58.9, i.e. **holding the harness fixed, Fable leads by 2.8pp**. That is the closest thing to
   a controlled model-vs-model reading in the index, and it favours Fable.
2. **"Are the widely-quoted 67-vs-70 Coding Agent numbers current?"** — No. Superseded by v1.5 (62/62).
   Three secondary sites still quote the old pair as live.
3. **"Do the independent boards agree?"** — Directionally yes, all within noise: AA Coding Agent 62/62,
   AA Intelligence 53/53, Arena agent 13.71 vs 11.54 (overlapping). **No neutral instrument separates them
   on quality.**
4. **"Is a secondary source's claim traceable?"** — One search result attributed an LMArena figure
   ("14.51% vs 12.55%") to an explainx article; **fetching that article showed it contains no LMArena
   figures at all.** I replaced it with a live read of arena.ai dated 2026-09-15. Treat search-engine
   synthesised numbers as unsourced until the page is opened.
5. **"Does the WebFetch summariser extract numbers reliably?"** — Not always. The same AA pages yielded
   Intelligence Index values of 66, 65.7, 61.2 and 53 depending on page and date. Most of that is real
   version churn (v4.1.1 → v4.2 → v4.3 in nine days), but **any single figure here should be re-read
   before it becomes a decision input.**
6. **"Is Astra even obtainable on a $200 plan right now?"** — New $200 Pro signups were **paused on
   2026-09-10**. If the decision is "which to *buy*", this may be dispositive on availability alone.
7. **"Does Fable's cheaper cache reach a subscriber?"** — No. This inverts the API verdict for subscription
   use and is the single most decision-relevant asymmetry found.

---

## 8. Named gaps and uncertainties

- **No METR measurement of either model.** The time-horizon axis is unavailable, not merely unfavourable.
- **No SWE-rebench entry for either model** — the best decontaminated board is silent on both.
- **No long-context degradation curve for Fable 5.1.** Astra's MRCR v2 figures are vendor-run, unreplicated.
- **No published max-sustained-turn-count** for either model.
- **Token-efficiency magnitude is unsettled** — AA (controlled) says Astra is ~40% cheaper per coding task;
  a practitioner suite (uncontrolled) says Astra cost 75% *more*. Direction ≠ magnitude.
- **Quantization is unconfirmed for both.** Astra has a confirmed *serving-engine misconfiguration*;
  Anthropic has a confirmed *safety-routing downgrade*. Neither is quantization, and conflating them
  overstates the case.
- **Both quota regimes tightened in September 2026** (Claude Code −17% on 2026-09-14; Astra metered at ~½
  Sol's rate, reportedly up to 4× tighter than launch week). Any value model built on launch-week limits is
  already stale — **re-read both `/usage` meters before deciding.**

---

## Sources

- [Introducing Claude Fable 5.1 and Claude Mythos 5.1 — Anthropic](https://www.anthropic.com/claude-fable-and-mythos-5-1) (vendor, 2026-09-01)
- [Benchmarking GPT-6 Astra — Artificial Analysis](https://artificialanalysis.ai/articles/benchmarking-gpt-6-astra) (independent, 2026-09-09)
- [Claude Fable 5.1 tops the AA Intelligence Index](https://artificialanalysis.ai/articles/claude-fable-5-1) (independent, 2026-09-01)
- [AA model comparison: Astra vs Fable 5.1](https://artificialanalysis.ai/models/comparisons/gpt-6-astra-vs-claude-fable-5-1) (independent, read 2026-09-16)
- [AA Claude Code vs Codex coding-agent comparison](https://artificialanalysis.ai/agents/coding-agents/comparisons/claude-code-vs-codex) (independent, index v1.5)
- [AA Coding Agents leaderboard](https://artificialanalysis.ai/agents/coding-agents) / [BenchLM mirror, 2026-09-15](https://benchlm.ai/benchmarks/aacodingagents)
- [Arena agent leaderboard](https://arena.ai/leaderboard/agent?rankBy=labs) (independent, read 2026-09-15)
- [SWE-rebench leaderboard](https://swe-rebench.com/) (independent, window 2026-05-15→07-01)
- [METR task-completion time horizons](https://metr.org/time-horizons/) (independent; no entry for either model)
- [WinBuzzer: Astra benchmark questions](https://winbuzzer.com/2026/09/04/gpt-6-astra-arrives-with-major-gains-staged-access-and-new-questions-about-its-benchmarks-xcxwbn/) (2026-09-04)
- [AA Intelligence Index v4.2 overhaul — TrendingTopics](https://www.trendingtopics.eu/gpt-6-still-behind-fable-5-1-as-artificial-analysis-overhauls-intelligence-index/) (2026-09-05)
- [Vellum: GPT-6 Astra benchmarks explained](https://www.vellum.ai/blog/gpt-6-astra-benchmarks-explained)
- [DataCamp: Astra vs Fable 5.1](https://www.datacamp.com/blog/gpt-6-astra-vs-claude-fable-5-1)
- [Two Meters: Fable 5.1 cheaper on API, hungrier on Max — paddo.dev](https://paddo.dev/blog/fable-5-1-two-meters/) (2026-09-03)
- [Decrypt: Astra users say it got dumber](https://decrypt.co/378101/gpt-6-astra-openai-model-dumber-nerfed) (2026-09-12)
- [Codex Weekly: Astra bugs, Sept 12 postmortem — Big Hat Group](https://www.bighatgroup.com/blog/codex-weekly-2026-09-14/) (2026-09-14)
- [Unite.AI: Altman apologises for staged Astra launch](https://www.unite.ai/sam-altman-apologizes-as-gpt-6-astra-staged-launch-denies-paid-access/) (2026-09-04)
- [The Decoder: Astra at half the rate of Sol](https://the-decoder.com/openai-rolls-out-gpt-6-astra-to-top-tier-chatgpt-plans-at-half-the-rate-of-gpt-5-6-sol/) (2026-09-05)
- [explainx: Claude Code limits cut 17%](https://explainx.ai/blog/anthropic-claude-code-limits-17-percent-cut-september-2026-august-2026) (2026-09-14)
- [explainx: Astra usage limits cut 4x](https://explainx.ai/blog/openai-gpt-6-astra-usage-limits-cut-4x-september-2026) (unconfirmed by OpenAI)
- [Anthropic status: Model output quality incident](https://status.claude.com/incidents/72f99lh1cj2c) (2025-08-05→09-05, resolved 2025-09-17)
- [BleepingComputer: Fable relaunch nerfed performance](https://www.bleepingcomputer.com/news/artificial-intelligence/claude-fable-relaunch-disappoints-users-with-nerfed-performance/) (2026-07-02)
- [Understanding AI: Anthropic's Fable is the most locked-down public model](https://www.understandingai.org/p/anthropics-fable-is-the-most-locked) (2026-06)
- [MindStudio: Astra vs Fable coding cost](https://www.mindstudio.ai/blog/gpt-6-astra-coding-cost) (2026-09-06) · [benchmark comparison](https://www.mindstudio.ai/blog/gpt6-astra-benchmark-comparison)
- [CodingFleet: SWE-bench Pro leaderboard](https://codingfleet.com/blog/swe-bench-pro-leaderboard-2026/) (2026-09-08) · [DeepSWE v1.1 leaderboard](https://codingfleet.com/blog/deepswe-v11-leaderboard-2026/)
- [Aider code-editing leaderboard](https://aider.chat/docs/leaderboards/edit.html) (stale for this question)
- [LessWrong: Estimating GPT-6 Astra's no-CoT time horizon](https://www.lesswrong.com/posts/ntKx9YHWCwxSeGbRB/estimating-gpt-6-astra-s-no-cot-time-horizon)
