# C — Measured throughput of the two $200 AI coding subscriptions

Research date: 2026-09-16. Window covered: ~2026-06-01 → 2026-09-16.
Subjects: **(a)** OpenAI ChatGPT Pro $200 ("Pro 20x") via Codex CLI with **GPT-6 Astra**; **(b)** Anthropic Claude Max 20x $200 via Claude Code with **Fable 5.1**.

---

## 0. The five findings that change a decision

1. **You cannot buy plan (a) right now.** OpenAI paused new ChatGPT Pro $200 sign-ups and upgrades on ~2026-09-10 citing Astra demand; a cancelled/downgraded/refunded/failed subscription **cannot be restored during the pause**. Existing subs unaffected. No reopen date.
2. **Plan (b) got 17% smaller two days ago.** The +50% Claude Code promo ended 2026-09-13; the "permanent +25%" took effect 2026-09-14 — Anthropic's own clarification says this "works out to a **17% reduction** in weekly limits on Claude Code" versus the level users had all summer.
3. **Both models roughly doubled their burn rate at launch, and both are measured.** Fable 5.1 emits **2.04x** the output tokens/turn of Fable 5 (783 → 1,596, n=7,835 turns, from local `.jsonl` logs). Astra's weekly drain was measured at **~5x** an established Sol baseline by one Pro user.
4. **The single best-instrumented number on either side is Codex's:** across 3,808 sessions / 59.2B input tokens (Jul–Sep 2026, open-source audit script), the $200 weekly window reached 99% in a **median of 25 hours** of wall-clock window time — fastest 7h, slowest 93h.
5. **The published "value per dollar" verdicts are an accounting artifact.** The one study that priced both from local logs found 43x (Codex) vs 94x (Claude) API-equivalent — then showed the 2x gap comes *entirely* from Anthropic's 2x cache-write price, and that **actual output work was near-identical (~$977 vs ~$911/mo)**. Anyone quoting the multiplier without this caveat is quoting a cache-accounting difference.

---

## 1. The table

| claim | plan | number | MEASURED / REPORTED / RUMOR | date | link |
|---|---|---|---|---|---|
| Fable 5.1 output tokens per turn vs Fable 5 | (b) Max 20x | 1,596 vs 783 tok/turn = **2.04x**; 2.07x across all sessions; Opus 5 ref 637 | **MEASURED** — instrument: `~/.claude/projects/**/*.jsonl`, dedup on `(sessionId, message.id)`, field `message.usage.output_tokens` | 2026-09-02 | [claude-code#91623](https://github.com/anthropics/claude-code/issues/91623) |
| Weekly quota 0% → 88% in ~22h on Fable 5.1 | (b) Max 20x | 79%→81%→88% at 16:22/16:45/18:31 UTC; Fable bucket 99%→100%; ~4–5 pp/hour | **MEASURED** — instrument: `GET /api/oauth/usage` with `anthropic-beta: oauth-2025-04-20` | 2026-09-02 | [claude-code#91623](https://github.com/anthropics/claude-code/issues/91623) |
| 5% more turns produced 88% more output tokens | (b) Max 20x | 10,633 turns (09-02) vs 10,093 (08-14) | **MEASURED** — same jsonl corpus | 2026-09-02 | [claude-code#91623](https://github.com/anthropics/claude-code/issues/91623) |
| One day's token volume on Pro 20x | (a) Pro $200 | **1,212,053,536 tokens** in one local day (Astra 31.85M/172 calls; Sol 1.109B/3,936 calls; auto-review 71M/454 calls) | **MEASURED** — instrument: Codex rollout JSONL, `token_count.info.last_token_usage` | 2026-09-05 | [codex#43222](https://github.com/openai/codex/issues/43222) |
| Weekly quota consumed in one day, same run | (a) Pro $200 | 64% → 70% → **95%** used over one session-day; 10,080-min weekly window | **MEASURED** — `token_count.rate_limits`, `limit_id: "codex"`, `plan_type: "pro"` | 2026-09-05 | [codex#43222](https://github.com/openai/codex/issues/43222) |
| Cache-read share of input | (a) Pro $200 | Astra **96.33%** cached, Sol **98.45%** cached | **MEASURED** — same rollout logs | 2026-09-05 | [codex#43222](https://github.com/openai/codex/issues/43222) |
| Hours to burn the $200 weekly window | (a) Pro $200 | window hit 99% **13 times**, 100% **11 times**; **median 25h**, min 7h, max 93h | **MEASURED** — 3,808 session files, 59.2B input / 129M output tok, via open-sourced [`codex-rollout-audit`](https://github.com/relux-works/codex-rollout-audit) on `~/.codex/sessions` | 2026-09-11 | [relux.works](https://relux.works/en/blog/codex-goal-token-burn/) |
| Goal-mode's share of consumption | (a) Pro $200 | **52 of 3,808 sessions (1.5%) ate 29.2B of 59.2B input tokens (~50%)** | **MEASURED** — same corpus | 2026-09-11 | [relux.works](https://relux.works/en/blog/codex-goal-token-burn/) |
| Idle/waiting burn rate in a long run | (a) Pro $200 | 188M input tok/hr (worst); 83M/hr (7.8h session); 20M/hr (92h session); **10–15M/hr with Astra's sleep tool** | **MEASURED** — per-turn timestamps from rollout logs | 2026-09-11 | [relux.works](https://relux.works/en/blog/codex-goal-token-burn/) |
| Weekly burn 5x faster than own baseline after paid reset | (a) Pro | 20% of weekly normally lasts 10+h; consumed in **~2h** after an **$80** paid reset | **REPORTED** — user's own multi-week historical comparison, same build/workflow; no telemetry dump shown | 2026-09-11 | [codex#44894](https://github.com/openai/codex/issues/44894) |
| Token-consumption spike above a request-size threshold | (a) unstated | spikes above **~272k tokens** per request | **REPORTED** — no instrument named, no quantified delta, no staff confirmation | 2026-09-05 | [codex#42901](https://github.com/openai/codex/issues/42901) |
| 5-hour window 0%→100% from one bash script; weekly 53%→67% | (b) Max Team | 0→100% (5h), +14pp weekly, script ran ~5s, CC 2.1.263, after a `/goal` long-run resumed at reset | **REPORTED** — in-client `/usage` percentages, no independent instrument; open, no staff reply | 2026-09-07 | [claude-code#92654](https://github.com/anthropics/claude-code/issues/92654) |
| Weekly token volume on Max 20x | (b) Max 20x | 190M tokens (wk of Jul 29) → **1.22B** the next week; 33M in one afternoon's setup; peak 51 concurrent sessions, 190 req/min, 1,555 sessions spawned in a day | **MEASURED** — instrument: [`tare`](https://github.com/kelviq/tare) reading local Claude Code session logs | 2026-08-14 | [kelviq.com](https://www.kelviq.com/blog/claude-code-usage-limits-where-tokens-go/) |
| Re-shipped context share of all tokens | (b) Max 20x | **87%** of all tokens were the same context re-sent | **MEASURED** — `tare` | 2026-08-14 | [kelviq.com](https://www.kelviq.com/blog/claude-code-usage-limits-where-tokens-go/) |
| Window already 83% full before work started; exhausted in 10 min | (b) Max 20x | 83% → 100% in 10 min | **MEASURED (post-hoc)** — `tare` reconstructs window fill at lockout moment | 2026-08-14 | [kelviq.com](https://www.kelviq.com/blog/claude-code-usage-limits-where-tokens-go/) |
| Official 5-hour message allowance | (a) Pro $200 | **100–900** Astra messages / 5h (Plus 5–45; Pro 5x 25–225); weekly cap sits *on top* | **REPORTED** (official-derived, secondary) — OpenAI Help Center is the primary but returns 403 to automated fetch | 2026-09 | [help.openai.com (403)](https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex) · [codexusage.dev](https://www.codexusage.dev/limits/astra) |
| Official 5-hour message allowance | (b) Max 20x | "at least **900 messages** every 5 hours, often more" | **REPORTED** (official Anthropic support text, but explicitly indicative not guaranteed) | current | [support.anthropic.com](https://support.anthropic.com/en/articles/11014257-about-claude-max-plan-usage) |
| Fable share of the weekly pool | (b) Max 20x | **up to 50% of weekly usage limits** on Fable models at no extra cost; then credits or switch model | **MEASURED-equivalent (official policy text)** | current | [support.claude.com](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan) |
| Weekly limit change | (b) Pro/Max/Team/Ent | promo +50% ends 2026-09-13; permanent +25% from 2026-09-14 = **−17% vs current** | **MEASURED-equivalent (vendor's own words)** | 2026-08-29 | [@ClaudeDevs](https://x.com/ClaudeDevs/status/2093742321473065266) · [BleepingComputer](https://www.bleepingcomputer.com/news/artificial-intelligence/anthropic-is-cutting-claude-codes-current-weekly-limits-by-17-percent/) |
| Pro $200 sign-ups paused | (a) Pro $200 | new subs + upgrades halted; cancelled/refunded subs **not restorable** during pause | **MEASURED-equivalent (vendor statement)** — Thibault Sottiaux: "Demand for Astra is really unprecedented." | 2026-09-10 | [TechCrunch](https://techcrunch.com/2026/09/10/openai-puts-pro-subscriptions-on-hold-due-to-astra-demand/) · [Fortune](https://fortune.com/2026/09/11/openai-astra-chatgpt-pro-pause/) |
| API-equivalent value of each $200 sub | both | Codex **$8,610/mo (43x)**; Claude Max **$18,900/mo (94x)** — but output-work value **$977 vs $911**, i.e. near-parity | **MEASURED (Codex arm) / EXTRAPOLATED (Claude arm)** — script over `.codex` + `.claude` logs; Codex at 99% of quota, **Claude from one day at 10% of quota ×10, author calls it unreliable** | 2026-05-30 | [codelynx.dev](https://codelynx.dev/posts/codex-claude-max-subscription-value) |
| Cost per Intelligence Index task | both | Astra (max) **$1.67** vs Fable 5.1 (max) **$3.76** → Astra at 44%. *Elsewhere reported as $3.26 vs $7.63 — same ~40% ratio, different absolutes* | **MEASURED** — Artificial Analysis prices input/cache-hit/cache-write/reasoning/answer tokens per task on a fixed benchmark set | 2026-09 | [Artificial Analysis](https://artificialanalysis.ai/models/comparisons/gpt-6-astra-vs-claude-fable-5-1) · via [DataCamp](https://www.datacamp.com/blog/gpt-6-astra-vs-claude-fable-5-1) |
| Same 12 tasks, real API spend | both | Astra **$198** vs Fable 5.1 **$113** — Astra **75% MORE**. *Directly contradicts the row above* | **MEASURED but CONFOUNDED** — different harnesses (Codex vs "Veridant"), Ultra Thinking on Astra only; authors state they "didn't isolate the exact cause" and that "subscription plan value wasn't part of this comparison" | 2026-09-06 | [MindStudio](https://www.mindstudio.ai/blog/gpt-6-astra-coding-cost) |
| Effort setting spans 11x in token use | (b) Fable 5.1 | 13.1M tok at low effort → **143.7M at max** | **MEASURED** — Artificial Analysis | 2026-09 | [Artificial Analysis](https://artificialanalysis.ai/articles/claude-fable-5-1) |
| Codex /goal single unattended run | (a) | **~25h, ~13M tokens, ~30k LOC** (design tool from scratch); separately 14h device driver; 18h → 14 of 18 backlog features passing CI | **REPORTED** — user anecdotes, token count given for one but no instrument named | 2026-07/08 | [MindStudio](https://www.mindstudio.ai/blog/codex-goal-ralph-loop-14-hour-autonomous-task) · [danielvaughan](https://codex.danielvaughan.com/2026/07/23/codex-cli-goal-mode-long-horizon-autonomous-workflows-ralph-loop-token-budgets/) |
| Max 20x 5-hour quota gone in 52 min from one prompt; others in 4 min | (b) Max 20x | 52 min / 4 min | **RUMOR** — X trending-topic aggregation, no primary post located, no dashboard, no instrument | 2026-09-02 | [X trending](https://x.com/i/trending/2095065746803966148) |
| "$200 plan exhausted in 12 hours" | (a) | 12h | **RUMOR** — surfaced only as an SEO-page summary; no primary post found | 2026-09 | [morphllm](https://www.morphllm.com/codex-pricing) |
| "Max 20x ≈ 300 weekly hours of Opus 4.7" | (b) | 300 h/wk | **RUMOR — and near-certainly stale**: names a model (Opus 4.7) superseded well before Sep 2026; no instrument; appears only in the pricing-SEO corpus | 2026 undated | [Superblocks](https://www.superblocks.com/blog/claude-code-pricing) |

---

## 2. How often users hit the wall, and what it feels like

**(b) Claude Code / Fable 5.1 — the wall is LOUD, LAYERED, and a DOWNGRADE, not a cutoff.**
Three distinct walls, and users hit the Fable one first. Verbatim, from #91623:

```
2026-09-02T16:45Z  You've reached your Fable limit. Run /usage-credits to continue or switch models with /model.
2026-09-02T18:53:43Z  You've hit your session limit - resets 10pm (Europe/Lisbon)
```

- **Fable sub-bucket (≤50% of weekly).** Official policy: at the cap you "keep using Fable models with usage credits, or switch to another Claude model." So the *first* wall is a **soft downgrade** — the session continues on a lesser model or on paid credits.
- **5-hour session wall.** Hard stop with a named reset time in local TZ.
- **Weekly wall.** Hard stop.
- Observed disproportion: one account read Fable **100%** while weekly was only **57%** — i.e. the 50% Fable sub-cap binds long before the plan does (#91623, secondary account).
- Frequency: this is the dominant complaint class post-2026-09-01. Reports of 5h 0→100% from a *single* short action are real and open (#92654, 2026-09-07, no staff reply).

**(a) Codex / Astra — the wall is QUIET and partly INVISIBLE.**
- Codex reports "reached the model usage limit" while `/status` shows **general weekly 82% remaining, gpt-reserve 100% remaining, and Astra-specific limit not shown at all** — the user could not determine which limit fired, when it resets, or how much Astra capacity remained (#43006, 2026-09-05, **closed as not planned**, no staff response).
- Two stacked pools: 5-hour window *and* a weekly cap on top; you can exhaust the 5-hour with most of the week intact.
- Paid escape hatches exist and are used: **$80 instant weekly reset** pulls the next allowance forward (#44894), plus promotional "banked resets."
- Frequency: high and clustered around Astra's 2026-09-03 rollout; OpenAI ran a **global usage reset on 2026-09-07** and two banked-reset waves on 09-03/09-04, which is itself evidence the wall was being hit broadly.

> **Asymmetry worth stating plainly:** Anthropic's wall tells you which bucket, what to do, and when it resets. OpenAI's wall, for Astra specifically, did not surface the bucket at all — and the issue asking for it was closed as not planned.

---

## 3. Plan terms that CHANGED in 2026 (dated)

**Anthropic (b):**
| date | change |
|---|---|
| 2026-04 | peak-hours restriction removed for Pro and Max |
| 2026-05-06 | hourly limits doubled |
| 2026-05-13 | weekly limits +50% (promo), through 2026-07-13 |
| 2026-07-13 → 07-19 → 09-13 | promo extended twice |
| 2026-07-19 23:59:59 PT | Fable promotional inclusion for **Pro** ends — Fable 5/5.1 no longer in Pro plan limits at all; credits from the start |
| 2026-08-29 | announced: permanent +25% baseline from 09-14 |
| **2026-09-01** | **Fable 5.1 ships; usage counters zeroed; sessions pinned to the `fable` alias silently moved 5 → 5.1** (a model swap with no notice — #91623) |
| **2026-09-14** | promo ends, +25% permanent takes effect ⇒ **net −17%** vs the summer level |

**OpenAI (a):** (timeline compiled by codexusage.dev; each row attributed to an official announcement — treat the compilation as secondary, the underlying events as corroborated by TechCrunch/Fortune for the big ones)
| date | change |
|---|---|
| 2026-06-11 | banked rate-limit resets (30-day validity) for personal Plus/Pro |
| 2026-07-09 | GPT-5.6 family GA with per-model 5-hour message ranges; **launch figures "later adjusted without dated notice"** |
| 2026-07-30 / 08-21 | metered API price cuts (Luna −80%, Terra −20%, Sol −20%+) — **API only, not subscription allowances** |
| 2026-08-24 | Business Premium seats: **5-hour rolling limit removed entirely** at $100–125/seat |
| **2026-09-03** | Astra integrated across Codex surfaces; **draws from the existing shared Work+Codex pool — no separate Astra quota** |
| 2026-09-03/04, 09-07 | two banked-reset waves, then a **global usage reset** ~18:00 PT |
| **2026-09-10** | **Pro $200 new sign-ups and upgrades PAUSED** |
| 2026-09-09→11 | unconfirmed quota anomalies (quota moving while idle, reset timestamps shifting) across ≥5 open issues; **no OpenAI root-cause statement** |

---

## 4. Long autonomous runs vs interactive use

**Codex is materially better for long unattended runs, and this is the one axis where the measured evidence is one-sided.**

- `/goal` (Ralph-loop) runs are a first-class product feature with multi-hour intent; measured single runs of ~25h/13M tok/30k LOC, 18h, 14h.
- Astra ships a **sleep tool** that drops idle burn from 83–188M input tok/hr to **10–15M/hr** — i.e. an explicit mechanism for a run that is *waiting* rather than working (relux.works). Nothing equivalent is documented on the Claude side.
- Codex subagents went GA 2026-03-14 with a manager agent spawning **up to 8 parallel cloud sandboxes**.
- **Counter-evidence, and it is the important one:** the same measured corpus shows goal mode is *why* the wall arrives — **1.5% of sessions consumed 50% of all tokens.** A long autonomous run on plan (a) is affordable in wall-clock hours and expensive in quota. The median window survives 25h; a 93h run existed but at 20M tok/hr.
- **Claude Code's parallelism is local, not managed:** multiple terminal sessions, no built-in orchestration dashboard. On plan (b) the measured peak was **51 concurrent sessions at 190 req/min** — so high fan-out is *achievable*, it just burns the window proportionally, and Fable's 50% sub-cap binds first.
- For **interactive** use the evidence does not separate them on throughput; the differentiator claimed everywhere is output quality per turn, which is a benchmark question, not a subscription question.

⚠️ Much of the "Codex wins long-horizon / Claude wins fast feedback" framing circulating in comparison blogs is **stale**: it cites GPT-5/5.5, Opus 4.6/4.7 and Sonnet 4.5, i.e. pre-Astra, pre-Fable-5.1. Treat any such post as describing a different product generation.

---

## 5. Published head-to-heads, and whether the methodology holds

| study | date | method | verdict on methodology |
|---|---|---|---|
| **Artificial Analysis** Intelligence Index v4.3 | 2026-09 | Both models on one fixed 10-eval suite; prices **every token class** (input, cache hit, cache write, reasoning, answer) per task | **Soundest available.** Task difficulty normalized by construction (identical benchmark). Limitation: benchmark tasks ≠ agentic repo work, and it prices **API rates, not subscriptions**. Also note the two absolute figures in circulation ($1.67/$3.76 vs $3.26/$7.63) differ by index version/effort config — the **ratio (~40–44%) is stable, the absolutes are not**; quote the ratio. |
| **codelynx.dev** subscription value | 2026-05-30 | Local `.codex` + `.claude` logs re-priced at official API rates | **Best framing, weak Claude arm.** Codex measured at 99% of quota ("basically real"); **Claude extrapolated from ONE DAY at 10% of quota ×10, which the author himself calls unreliable.** Its real contribution is the refutation: 43x vs 94x is a **cache-write pricing artifact**, output work was $977 vs $911. **Pre-dates both current models — stale on models, durable on method.** |
| **MindStudio** cost test | 2026-09-06 | 12 identical tasks (8 KingBench + 4 long-horizon app builds) | **Confounded.** Ran Astra through Codex with **Ultra Thinking** and Fable through a different harness ("Veridant"); authors state they "didn't isolate the exact cause." Token-counting method undisclosed. Explicitly not a subscription comparison. |
| **particula.tech** "4x token gap" | dated 2026-04-06 | n=1 Express.js refactor + one Figma benchmark | **Unsound.** 1–2 tasks, no difficulty normalization, no token instrument named, and it concedes Claude "caught a race condition that Codex missed" while still scoring Claude worse on efficiency — comparing unequal outputs. |
| **mattwigdahl** head-to-head | **2025-10-03** | 4 runs, one shared SPEC.md, explicitly "not a quantitative benchmark" | **Honest but obsolete** — Sonnet 4.5 / Opus 4.1 / GPT-5 era. Do not cite for 2026. |
| **morphllm / duet / aivy / firecrawl / codegenes / coursiv / choosely / explainx / layer3labs / codexusage / blog.laozhang** etc. | various | — | **Treat as a single contaminated corpus.** Near-identical templates, cross-citing each other, mixing tiers and model generations, no primary instrument. Useful only as a pointer to a primary source (the codexusage.dev *change log* is the one genuinely useful artifact, and only because each row names an official announcement that can be checked independently). |

**The gap nobody has filled:** there is **no published, normalized, subscription-level head-to-head** of Codex Pro $200 + Astra against Claude Max 20x + Fable 5.1 that (i) runs the same tasks, (ii) in each product's native harness at a matched effort level, and (iii) reports *how far into each plan's quota* the run got. Every study is either API-token pricing or an unnormalized anecdote. The closest instrument pair that *could* produce it already exists and is open source: [`codex-rollout-audit`](https://github.com/relux-works/codex-rollout-audit) and [`tare`](https://github.com/kelviq/tare).

---

## 6. Adversarial pass — contradictions, not averages

1. **Astra is 44% of Fable's cost (Artificial Analysis) vs Astra costs 75% MORE than Fable (MindStudio).** Do not average these. They are reconcilable: AA fixes the benchmark and prices token classes uniformly; MindStudio ran Astra at **Ultra Thinking** in Codex and Fable at an unstated effort in a different harness. **The variable is effort setting and harness, not the model.** Corroborating: Fable 5.1's own effort ladder spans **11x** in output tokens (13.1M low → 143.7M max). ⇒ *Any cost comparison that does not pin effort on both sides is measuring the effort knob.*
2. **"Codex wins on value per dollar" (morphllm: 43x, "1.4–4x more tokens per task on Claude") vs codelynx's own data.** The same 43x figure's author computed Claude at **94x** and then showed both numbers are inflated by cache accounting, with real output work at parity. The SEO corpus quotes the multiplier that suits its conclusion and drops the refutation that sits in the same article.
3. **Two different absolute AA cost pairs are circulating** ($1.67/$3.76 and $3.26/$7.63). Same ~40% ratio. I could not resolve which index version each belongs to; **quote the ratio, not the dollars.**
4. **Coding-index scores contradict too:** one source has both at 62 on Coding Agent Index v1.4; another has Astra 67 vs Fable 70; KingBench 3 has Astra 90% vs Fable 92.5%. All three agree Fable ≥ Astra on quality and Astra cheaper per task — the magnitudes disagree. Directionally safe, numerically not.
5. **The "300 weekly hours of Opus 4.7" figure is a trap.** It names a model generation that was already superseded, appears only in the pricing-SEO corpus, and has no instrument. Anthropic publishes *no* hour figure; the support page gives only "at least 900 messages / 5 hours." **Any hours-per-week number for Max 20x is reconstruction, not measurement** — several of these sites admit as much ("indicative reconstructions based on telemetry shared by users").
6. **Sub-cap asymmetry I nearly missed, and it inverts the naive reading.** Astra **shares** the Work+Codex pool (no separate quota), while Fable is **capped at 50% of the weekly pool**. So on plan (b) a Fable-only workflow can only ever reach half the plan — the observed "Fable 100% at weekly 57%" is the *designed* behaviour, not a bug. Plan (a) has no such structural ceiling on its top model.
7. **Reddit is effectively unsourceable here.** Repeated `site:reddit.com` and subreddit-targeted queries returned zero relevant hits through this search index. Every "Reddit says…" claim I encountered arrived *second-hand* through SEO pages or X trending-topic pages that cite no primary post. **I have therefore rated all such claims RUMOR and have not used any of them as load-bearing.** The brief asked specifically for r/ChatGPTPro, r/ClaudeAI, r/ChatGPTCoding — treat their absence here as an instrument limitation, not as evidence those communities are quiet.
8. **X/Twitter is the same problem, with one exception.** The X results returned were *trending-topic aggregation pages*, not posts — no author, no timestamp, no screenshot. The single usable X source is [@ClaudeDevs](https://x.com/ClaudeDevs/status/2093742321473065266), a first-party vendor account.
9. **GitHub issues are the highest-quality vein and are systematically ignored by the comparison blogs.** #91623, #43222 and the relux corpus contain the only reproducible instruments found. **Note the survivorship bias in the opposite direction, though:** issue trackers collect *anomalies*, so their burn rates are an upper tail, not a central tendency. The relux 3,808-session corpus is the only source that gives a distribution (median 25h, range 7–93h) rather than an incident.
10. **Zero staff responses.** Across every Anthropic and OpenAI issue read (#91623, #92654, #43222, #43006, #42901, #44894), **not one carried a vendor reply**; #43006 was closed as not planned. Both vendors' *actions* (counter resets, global resets, banked resets, the sign-up pause) acknowledge the load; neither has published a root-cause statement.

---

## 7. Blockers / what I could not establish

- **No primary Reddit or X user posts reached** (search-index limitation, stated above). Every Reddit-attributed number here is second-hand and rated RUMOR.
- **OpenAI Help Center returns HTTP 403 to automated fetch** — the official Astra limit table (100–900 msgs/5h on Pro 20x) is corroborated only via secondary compilations. Worth a manual browser check before anyone relies on it.
- **No post-2026-09-14 data.** The −17% Claude cut is two days old; there is not yet a measured account of what the new weekly ceiling buys. The correct instrument (`tare`, or `GET /api/oauth/usage`) exists and could answer this locally within one week.
- **No Fable 5.1-era equivalent of the relux distribution study.** The Claude-side numbers are single-account incidents (n=1 each). The asymmetry in evidence quality between the two plans in this report is real and should not be read as an asymmetry in the products.
- **The `tare` and `codex-rollout-audit` figures are single-user corpora.** Both name their instrument and are reproducible, which is why they are rated MEASURED — but neither is a population sample.

## Sources

Primary/measured: [claude-code#91623](https://github.com/anthropics/claude-code/issues/91623) · [claude-code#92654](https://github.com/anthropics/claude-code/issues/92654) · [codex#43222](https://github.com/openai/codex/issues/43222) · [codex#43006](https://github.com/openai/codex/issues/43006) · [codex#42901](https://github.com/openai/codex/issues/42901) · [codex#44894](https://github.com/openai/codex/issues/44894) · [relux.works](https://relux.works/en/blog/codex-goal-token-burn/) + [codex-rollout-audit](https://github.com/relux-works/codex-rollout-audit) · [kelviq.com](https://www.kelviq.com/blog/claude-code-usage-limits-where-tokens-go/) + [tare](https://github.com/kelviq/tare) · [codelynx.dev](https://codelynx.dev/posts/codex-claude-max-subscription-value) · [Artificial Analysis](https://artificialanalysis.ai/models/comparisons/gpt-6-astra-vs-claude-fable-5-1)
Vendor: [@ClaudeDevs](https://x.com/ClaudeDevs/status/2093742321473065266) · [support.claude.com Fable allowances](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan) · [support.anthropic.com Max usage](https://support.anthropic.com/en/articles/11014257-about-claude-max-plan-usage) · [help.openai.com Astra usage (403)](https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex)
Press: [TechCrunch](https://techcrunch.com/2026/09/10/openai-puts-pro-subscriptions-on-hold-due-to-astra-demand/) · [Fortune](https://fortune.com/2026/09/11/openai-astra-chatgpt-pro-pause/) · [BleepingComputer](https://www.bleepingcomputer.com/news/artificial-intelligence/anthropic-is-cutting-claude-codes-current-weekly-limits-by-17-percent/) · [Help Net Security](https://www.helpnetsecurity.com/2026/07/13/claude-code-weekly-limits-promotion-extended/)
Secondary/flagged: [DataCamp](https://www.datacamp.com/blog/gpt-6-astra-vs-claude-fable-5-1) · [MindStudio cost](https://www.mindstudio.ai/blog/gpt-6-astra-coding-cost) · [MindStudio /goal](https://www.mindstudio.ai/blog/codex-goal-ralph-loop-14-hour-autonomous-task) · [codexusage.dev changes](https://www.codexusage.dev/changes) · [particula.tech](https://particula.tech/blog/codex-vs-claude-code-cli-agent-comparison) · [mattwigdahl (2025)](https://mattwigdahl.substack.com/p/claude-code-vs-codex-cli-head-to)
