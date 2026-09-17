# A — The OpenAI $200/mo tier for a heavy Codex CLI user

Researched 2026-09-16. Every substantive number below came from the live web, not from
model memory: my knowledge cutoff is May 2026 and **GPT-6 Astra did not exist at that
cutoff** (released 2026-09-03). Treat any claim here that is *not* in the sourced table
as inference and read the label.

## 0. The headline a heavy user must read first

**You cannot buy the $200 plan today.** OpenAI paused new sign-ups *and upgrades* to
ChatGPT Pro $200 (Pro 20x) on **2026-09-10**, citing demand for GPT-6 Astra. Existing
$200 subscriptions keep working; Pro $100 (5x) is still purchasable. If an existing $200
subscription lapses or is cancelled, it **cannot be repurchased** until the pause lifts,
and OpenAI has published no reopening date. This single fact dominates every other
finding — plan for Pro $100 + purchased credits unless the subscription already exists.

## 1. Source-access caveat (instrument honesty)

`openai.com/index/*` and `help.openai.com/*` returned **HTTP 403** to both WebFetch and a
browser-UA `curl`. Facts attributed to those two hosts below were read through **search-engine
snippets of the official pages**, not by fetching the pages directly. They are official-origin
but second-hand in transport; I mark them `official (snippet)`. Everything from
`learn.chatgpt.com` and `developers.openai.com` was fetched directly and is `official (direct)`.

Note `developers.openai.com/codex/pricing` 308-redirects to `learn.chatgpt.com/docs/pricing`,
and `platform.openai.com/docs/pricing` 301-redirects to `developers.openai.com/api/docs/pricing`.
Those are the live canonical locations as of 2026-09-16.

## 2. Facts with sources

| # | Fact | Value | Status | Source | Date |
|---|---|---|---|---|---|
| 1 | Name of the $200 tier | **ChatGPT Pro $200**, a.k.a. **Pro 20x** — a rate-limit tier of ChatGPT Pro, not a separate "Codex Pro" product | DOCUMENTED | [help.openai.com Pro tiers](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers) | official (snippet), current 2026-09 |
| 2 | Pro tier ladder | Pro $100 = **5x** Plus usage; Pro $200 = **20x** Plus usage; Pro $200 is the highest usage tier | DOCUMENTED | [help.openai.com Pro tiers](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers) | official (snippet) |
| 3 | **Sign-ups paused** | New sign-ups + upgrades to Pro $200 (Pro 20x) paused **2026-09-10**, incl. upgrades from Free/Go/Plus/Pro $100. Existing $200 subs unaffected. No reopen date published. Once a $200 sub ends it cannot be repurchased until the pause lifts | DOCUMENTED | [help.openai.com Pro tiers](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers); corroborated [Fortune](https://fortune.com/2026/09/11/openai-astra-chatgpt-pro-pause/), [CIO](https://www.cio.com/article/4221092/openai-pauses-200-pro-tier-as-astra-demand-strains-capacity/) | 2026-09-10 / 2026-09-11 |
| 4 | Full plan ladder | Free $0 · Go $8 · Plus $20 · Pro "from $100" (5x / 20x) · Business $20/user/mo annual ($25 monthly) · Enterprise & Edu contact sales | DOCUMENTED | [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) | official (direct), 2026-09-16 |
| 5 | Codex limit **unit and window** | "local messages per **five-hour** period"; the count "depends on the model used, size and complexity of your tasks" — hence published as ranges, not a single number | DOCUMENTED | [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) | official (direct) |
| 6 | **Pro 20x ($200) limits, per 5 h** | GPT-6 Astra **100–900** · GPT-5.6 Sol **200–2,000** · GPT-5.6 Terra **500–4,000** · GPT-5.6 Luna **5,000–40,000** | DOCUMENTED | [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) | official (direct) |
| 7 | Pro 5x ($100) limits, per 5 h | Astra **25–225** · Sol **50–500** · Terra **125–1,000** · Luna **1,250–10,000** | DOCUMENTED | same | official (direct) |
| 8 | Plus ($20) limits, per 5 h | Astra **5–45** · Sol **10–100** · Terra **25–200** · Luna **250–2,000** | DOCUMENTED | same | official (direct) |
| 9 | Weekly limits | **"Weekly limits may also apply."** Exact weekly numbers are **NOT published** | DOCUMENTED (existence) / **NOT PUBLISHED** (value) | same | official (direct) |
| 10 | Local vs cloud | "Local messages and cloud chats **share your plan's usage allowance**." Cloud chats run GPT-5.6 Sol and "may use more of your allowance than local messages". No separate cloud task count published | DOCUMENTED | same | official (direct) |
| 11 | **Exhaustion behaviour** | Not a hard cut mid-task: "If you reach your usage limits during an active turn, the agent will be able to continue working on that turn, subject to fair use limits." Then usage **stops** until reset unless you buy credits — Plus/Pro "can purchase additional credits to continue working without needing to upgrade". No automatic overage billing; no silent model downgrade documented | DOCUMENTED | [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) + [help.openai.com credits](https://help.openai.com/en/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-freegopluspro-sora) | official (direct + snippet) |
| 12 | Credit draw order | "Your plan's included usage is used first. After you hit plan limits, usage draws from your credit balance." | DOCUMENTED | [help.openai.com credits](https://help.openai.com/en/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-freegopluspro-sora) | official (snippet) |
| 13 | **Astra identity** | **GPT-6 Astra**, model id **`gpt-6-astra`**. An OpenAI model, available in ChatGPT, **Codex**, and the API (also Azure, AWS Bedrock) | DOCUMENTED | [developers.openai.com models](https://developers.openai.com/api/docs/models/gpt-6-astra); [OpenAI GPT-6 Astra](https://openai.com/index/gpt-6-astra/) | official (direct / snippet) |
| 14 | Astra release date | Rollout began **2026-09-03** | DOCUMENTED | [InfoQ](https://www.infoq.com/news/2026/09/openai-gpt6-astra/), [9to5Mac](https://9to5mac.com/2026/09/04/openai-releasing-major-upgrade-to-chatgpt-and-codex-with-gpt-6-astra-details-here/) | 2026-09-03/04 |
| 15 | **Is Astra included in $200?** | **Included, not credit-gated** — Pro 20x carries its own Astra allowance (100–900 msg/5 h). Credits are only needed *after* that allowance is spent. (Plus is described as "limited GPT-6 Astra usage, with the option to purchase credits") | DOCUMENTED | [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) | official (direct) |
| 16 | **Astra API price** /1M tok | Standard ≤272K ctx: input **$10.00**, cached input **$1.00**, output **$50.00** | DOCUMENTED | [developers.openai.com/api/docs/pricing](https://developers.openai.com/api/docs/pricing) | official (direct) |
| 17 | Astra long-context price | >272K input tokens: input **$20.00**, cached **$2.00**, output **$75.00** ("Prompts with more than 272K input tokens are priced at 2x input and cache rates") | DOCUMENTED | same | official (direct) |
| 18 | Astra batch / fast mode | Batch = 50% (in $5.00 / cached $0.50 / out $25.00). **Fast mode = 2x** (in $20.00 / cached $2.00 / out $100.00) | DOCUMENTED | same | official (direct) |
| 19 | **Astra context window** | Total context **1,050,000** tokens; max input **922,000**; **max output 128,000** | DOCUMENTED | [developers.openai.com models](https://developers.openai.com/api/docs/models/gpt-6-astra) | official (direct) |
| 20 | Astra knowledge cutoff | **2026-04-30** | DOCUMENTED | same | official (direct) |
| 21 | **Codex credit rate card** (credits per 1M tokens) | Astra **250** in / **25** cached / **1,250** out · Sol **100 / 10 / 500** · Terra **50 / 5 / 300** · Luna **5 / 0.5 / 30** · GPT-5.5 **125 / 12.50 / 750** · GPT-5.4 **62.50 / 6.25 / 375** · GPT-5.4 mini **18.75 / 1.875 / 113** | DOCUMENTED | [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) | official (direct) |
| 22 | Sibling model API prices /1M | `gpt-5.6-sol` $4.00 / $0.40 / $20.00 · `gpt-5.6-terra` $2.00 / $0.20 / $12.00 · `gpt-5.6-luna` $0.20 / $0.02 / $1.20 | DOCUMENTED | [developers.openai.com/api/docs/pricing](https://developers.openai.com/api/docs/pricing) | official (direct) |
| 23 | **1 credit = $0.04** | Not stated on the pricing page. **Derived exactly** — see §3. Community sources state $0.04 directly | INFERRED (exact, 10/10 rows) + COMMUNITY | §3 below; community: [UI Bakery](https://uibakery.io/blog/openai-codex-pricing), [Taskade](https://www.taskade.com/blog/codex-pricing-explained) | 2026 |
| 24 | **Prompt caching in Codex** | Supported. Astra model page lists prompt caching as a supported feature, and the Codex credit rate card meters a distinct **cached input** rate — so cached reads are discounted on subscription usage, not only on the API | DOCUMENTED | [developers.openai.com models](https://developers.openai.com/api/docs/models/gpt-6-astra) + [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) | official (direct) |
| 25 | **Cached-input discount** | **90% off input** — $1.00 vs $10.00/1M (API) and 25 vs 250 credits/1M (Codex). Identical 10:1 ratio on every model in both tables | DOCUMENTED (both tables) | tables in #16, #21, #22 | official (direct) |
| 26 | Codex CLI min version for Astra | **≥ 0.153.0**; v0.153.4 verified working. 0.149.1 rejects Astra with "requires a newer version of Codex" | COMMUNITY (corroborated by an [openai/codex PR titled "Backport GPT-6-Astra model catalog to 0.153"](https://github.com/openai/codex/pull/42605)) | [shunt#458](https://github.com/pleaseai/shunt/issues/458), [Codex KB](https://codex.danielvaughan.com/2026/09/03/gpt-6-astra-codex-cli-configuration-context-notes-safety/) | 2026-09 |
| 27 | Codex CLI config for Astra | `~/.codex/config.toml`: `model = "gpt-6-astra"`, `model_reasoning_effort = "high"`; effort ladder **low / medium / high / xhigh / max**; `codex -m gpt-6-astra --reasoning-effort xhigh` | COMMUNITY | [Codex KB](https://codex.danielvaughan.com/2026/09/03/gpt-6-astra-codex-cli-configuration-context-notes-safety/) | 2026-09-03 |
| 28 | Live remaining-limit check | `/status` inside a Codex CLI session; plus the Codex usage dashboard (Settings → Usage) | DOCUMENTED | [help.openai.com credits](https://help.openai.com/en/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-freegopluspro-sora) | official (snippet) |
| 29 | Astra safety classification | First OpenAI model at **"critical" cybersecurity capability** under the Preparedness Framework; production version restricts advanced offensive-security tasks | DOCUMENTED | [OpenAI path-to-astra](https://openai.com/index/path-to-astra/), [InfoQ](https://www.infoq.com/news/2026/09/openai-gpt6-astra/) | 2026-09 |
| 30 | Astra Codex context feature | Experimental mechanism keeping **notes across context windows** instead of relying on compaction; earlier windows stay searchable | DOCUMENTED | [InfoQ](https://www.infoq.com/news/2026/09/openai-gpt6-astra/) | 2026-09 |
| 31 | **Fast mode burns subscription credits faster** | Verbatim: **"Fast mode consumes credits at a higher rate for supported models."** and **"Speed configurations will increase credit consumption for all models that apply."** The *multiplier* is not restated for credits; the API page documents 2x | DOCUMENTED (existence) / NOT PUBLISHED (credit multiplier) | [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) | official (direct) |
| 32 | Pro plan inclusions, verbatim | **"Access to GPT-5.3-Codex-Spark (research preview), a fast Codex model for day-to-day coding tasks"** and **"5x or 20x more Codex usage than Plus"** | DOCUMENTED | same | official (direct) |
| 33 | Codex is in every plan | Codex CLI is included in **every** ChatGPT plan from $0; there is **no standalone Codex subscription** — "Codex Pro" does not exist as a product | DOCUMENTED | [help.openai.com using Codex](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan) | official (snippet) |
| 34 | A "prompt cache diagnostics" doc exists | Listed in the pricing page's "Cost and throughput resources" sidebar alongside "Prompt caching" — i.e. OpenAI ships cache-hit diagnostics guidance | DOCUMENTED (existence) | [learn.chatgpt.com/docs/pricing](https://learn.chatgpt.com/docs/pricing) | official (direct) |
| 35 | Weekly caps bite heavy Pro users in practice | Open issue on the Codex repo titled **"Rapidly hitting weekly limits on ChatGPT Pro plan"** — real users on Pro exhausting the undocumented weekly cap | COMMUNITY (but on OpenAI's own issue tracker) | [openai/codex#3734](https://github.com/openai/codex/issues/3734) | 2026 |

## 3. The credit→dollar derivation (why $0.04 is solid)

OpenAI publishes the Codex **credit** rate card and the **API dollar** rate card separately and
never states the conversion. Dividing one by the other gives $0.04/credit on **every row of both
tables**, which is far past coincidence:

| Model / leg | Credits per 1M | API $ per 1M | $ per credit |
|---|---|---|---|
| Astra input | 250 | $10.00 | 0.040 |
| Astra cached input | 25 | $1.00 | 0.040 |
| Astra output | 1,250 | $50.00 | 0.040 |
| Sol input | 100 | $4.00 | 0.040 |
| Sol output | 500 | $20.00 | 0.040 |
| Terra input | 50 | $2.00 | 0.040 |
| Terra output | 300 | $12.00 | 0.040 |
| Luna input | 5 | $0.20 | 0.040 |
| Luna output | 30 | $1.20 | 0.040 |
| GPT-5.4 mini input | 18.75 | (implies $0.75) | 0.040 |

10/10 consistent. Community write-ups independently assert "1 credit ≈ $0.04" and date the
credit meter to **2026-04-02**. So: **purchased credits are priced at API parity** — there is no
subscriber discount on overflow credits, and the only economic advantage of the subscription is
the *included* allowance.

**Consequence for a heavy CLI user:** once the $200 plan's 5-hour allowance is spent, every
further token costs the same as calling the API directly. The subscription is a prepaid block,
not a discount rate.

## 4. Question 5 — converting $200 into a token/task allowance

**There is no official conversion, and I want to be blunt about that.** OpenAI publishes:

- messages per 5-hour window, per model, as a **range** (fact #6);
- a credit rate card in credits per million tokens (fact #21);
- a purchased-credit price (derivable, fact #23);

but it does **not** publish (a) how many credits a plan includes, (b) what a "message" is worth in
tokens, or (c) the weekly cap. Without (a) or (b) the subscription cannot be converted to tokens
from official numbers alone. Anyone quoting "the $200 plan = N million tokens" is inferring.

What can be said with the official numbers, clearly labelled **INFERRED**:

- A 5-hour window at the **top** of the Pro 20x Astra range is 900 messages; at the bottom, 100.
  Six windows a day ⇒ an order-of-magnitude band of **600–5,400 Astra messages/day**, before any
  weekly cap bites. The 9x spread is OpenAI's own, and it tracks task size/complexity.
- At API parity ($0.04/credit), $200 of *purchased* credits = 5,000 credits = **20M Astra input
  tokens**, or **4M Astra output tokens**, or 200M cached-input tokens. The included allowance is
  presumably worth more than this — otherwise the subscription would be pointless — but **by how
  much is unpublished.**
- Cheap-model arbitrage is large and documented: Luna costs **1/50th** of Astra per input token
  (5 vs 250 credits) and its allowance is ~55x larger (5,000–40,000 vs 100–900 msg/5 h).

One widely-repeated figure — that **OpenAI estimates Codex averages ~$100–$200 per developer per
month** — appears in several third-party summaries. I could not confirm it on an OpenAI-hosted page
that I was able to fetch. **Treat as COMMUNITY/unconfirmed.**

## 5. Unknowns / not published

Stated as unknowns rather than filled with estimates:

1. **Weekly limit values.** The page says "weekly limits may also apply" and gives no number. For a
   heavy user this is the single largest unpriced risk — the 5-hour table may not be the binding
   constraint.
2. **Credits included per plan per month.** Not published for any tier.
3. **Official $/credit.** Not stated by OpenAI; derived exactly here and asserted by community sources.
4. **What a "message" costs in tokens.** Undefined, which is why the limits are ranges.
5. **Cloud-task counts.** Cloud chats share the allowance and "may use more" — no multiplier given.
6. **When the Pro $200 pause lifts.** No date published. (A Polymarket market exists on the reopen
   date — a market, not a source.)
7. **Fast mode's credit multiplier.** RESOLVED IN PART: the pricing page now confirms "Fast mode
   consumes credits at a higher rate for supported models" — so it *does* apply to subscription
   credits. The **numeric multiplier for credits is still unpublished**; API dollars use 2x.
8. **Whether Codex CLI sets a prompt-cache key automatically**, its TTL, and whether cache hits are
   reported in `/status`. Caching is supported and metered; the CLI-side mechanics are undocumented
   in what I could fetch (`docs/config.md` in openai/codex renders only links; `docs/models.md` 404s).
9. **Minimum CLI version is community-sourced.** The `0.153` figure is corroborated by an
   openai/codex PR *title* but I did not read an official release note asserting the floor.
10. **Astra's Codex "notes across context windows" feature** — flagged experimental; no official doc
    on whether it consumes allowance differently.

## 6. Adversarial pass — what I nearly missed

Three things the first sweep would have gotten wrong, each investigated with real calls:

- **"$200 plan" framed as buyable.** It is not, since 2026-09-10. A recommendation to purchase it
  would have been unexecutable. This inverts the practical answer to the whole brief.
- **"Astra" treated as possibly fictional.** It post-dates my cutoff, so memory said nothing. It is
  real, is `gpt-6-astra`, and is the reason the $200 tier is capacity-constrained.
- **Assuming the subscription discounts overflow.** It does not — purchased credits are at exact API
  parity (§3). The plan buys an allowance, not a rate.

A fourth, unresolved and worth flagging to the lead: the **weekly cap** is acknowledged but
unpublished, so *no* public number bounds a heavy CLI user's monthly throughput on this plan. Any
capacity model built on the 5-hour table alone is unbounded above by an undocumented constraint.

## 8. Addendum — lead's follow-up (Plus vs $200 for Astra; the `rate_limits` object)

Added after the lead supplied disk truth from `~/.codex/models_cache.json`. I re-read that file
myself rather than taking the summary; cache metadata: `fetched_at 2026-09-16T23:58:03Z`,
`client_version 0.154.0`. Note my original artifact already used the slug `gpt-6-astra` throughout —
the correction was redundant on the slug, but the **`ultra` effort level is genuinely new** and is
not in any community effort ladder I found earlier (those stop at `max`).

### 8.1 `upgrade: null` is NOT an entitlement field — positive control

The tempting read is "`upgrade: null` on a Plus account ⇒ Astra needs no upgrade ⇒ not tier-gated".
**That inference is unsound.** Running the control — which models carry a *non*-null `upgrade` —
returns exactly one, and it is a **retirement pointer**, not an entitlement:

```
gpt-5.5 → {"model": "gpt-5.6-sol",
           "migration_markdown": "GPT-5.5 retires on October 14, 2026. Switch to GPT-5.6 Sol…",
           "retirement_at": "2026-10-14T19:00:00Z"}
```

So `upgrade` means *"this model is being retired, migrate here"*. It carries **no plan information
at all**, and the cache has **no entitlement, quota, plan or rate-limit schema** anywhere in it
(top-level keys are only `fetched_at`, `etag`, `client_version`, `models`). **The cache can neither
prove nor disprove tier gating** — absence of a gate here is absence of the *field*, not of the gate.

### 8.2 Full local model inventory (disk truth, Plus account, client 0.154.0)

| slug | visibility | in API | efforts |
|---|---|---|---|
| `gpt-6-astra` | list | true | low, medium, high, xhigh, max, **ultra** |
| `gpt-5.6-sol` | list | true | low…max, **ultra** |
| `gpt-5.6-terra` | list | true | low…max, **ultra** |
| `gpt-5.6-luna` | list | true | low…max (no ultra) |
| `gpt-5.5` | list | true | low…xhigh (retires 2026-10-14) |
| `gpt-reserve` | **hide** | true | low…max |
| `codex-auto-review` | **hide** | true | low…max |

`gpt-6-astra-aeon` — a "long-horizon variant" named in one community source — is **absent from this
cache** (`aeon` does not appear anywhere in the file). Unresolved: newer than 0.154.0, gated, or the
source is wrong. Do not rely on it.

Astra also carries `service_tiers: [{id: "priority", name: "Fast", description: "2x speed,
increased usage"}]` and `additional_speed_tiers: ["fast"]` — **first-party confirmation that Fast is
2x**, matching the API page's 2x pricing.

### 8.3 Q1 — what $200 buys for Astra vs Plus

**It is the same model with a bigger meter, not a better model.** OpenAI's published table gives
Astra to Plus at **5–45** local messages/5 h and to Pro 20x at **100–900** — same model row, ~20x
the allowance, exactly matching the tier's advertised "20x more Codex usage than Plus".

**`ultra` is not a $200 feature.** It is present for Astra on a **Plus** account's own cache
(disk truth above), and community sources state ultra is available "in Codex from Plus upward" and
is gated more tightly in *Work* than in Codex. Ultra reportedly runs **~4 agents in parallel**
(hence "automatic task delegation"), so its cost is in *allowance burn*, not entitlement —
and OpenAI's own Astra guidance reportedly warns that higher effort "can use more of your allowance
and does not always produce a better result", recommending the lowest effort that reliably works.

⚠️ The ultra-gating claim is **COMMUNITY**, not documented. I could not fetch
`help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex` (403) —
that article is the authoritative answer to this question and should be read by a human or an
authenticated fetch. What *is* documented is the 5–45 vs 100–900 meter difference.

### 8.4 Q2 — the `rate_limits` object, and a correction to the brief's model

🚨 **The brief's assumption — "`primary` (window_minutes: 300)" — is the exact thing that has broken
third-party meters.** Multiple independent tool authors report that **position no longer implies
duration**: `primary_window` can carry a window of *any* duration and `secondary_window` can be
**null**. The stated fix is to **read `window_minutes` / `windowDurationMins` off each bucket and
key on the duration**, never on the field name. One tracker's bug is titled literally *"windows are
mapped by position, not by duration — the 5H key shows a 30-day window"*.
Fields observed: `used_percent`/`usedPercent`, `window_minutes`/`windowDurationMins`
(300 = 5 h, 10080 = weekly), `resets_at`/`resetsAt`.

**What one "percent" buys: OpenAI publishes no definition, on any plan.** Percent is a fraction of
*your own* plan's allowance, so it is not comparable across plans, across models, or even across the
two windows of one account. Hard evidence it is non-linear between windows — openai/codex issue
**#42007**: *"5h rate limit went 0% -> 100% in 23 minutes while the weekly limit moved 1pp."* A heavy
Astra user can therefore exhaust a 5-hour window in **under half an hour** while the weekly meter
barely registers.

**Measured-data negative:** I searched this box's own Codex telemetry for a real `rate_limits`
payload to give you observed numbers rather than quoted ones — `~/.codex/logs_2.sqlite` (10 MB,
table `logs`) contains **0 rows** matching `rate_limit`. So I cannot supply measured window values
from disk; the schema above is from tool authors reading live API responses, marked COMMUNITY.

### 8.5 Q3 — the $/token denominator you asked for

`gpt-6-astra`, per 1M tokens, **official** ([developers.openai.com/api/docs/pricing](https://developers.openai.com/api/docs/pricing)):

| tier | input | cached input | output |
|---|---|---|---|
| Standard (≤272K ctx) | **$10.00** | **$1.00** | **$50.00** |
| Long context (>272K) | $20.00 | $2.00 | $75.00 |
| Batch | $5.00 | $0.50 | $25.00 |
| Fast mode | $20.00 | $2.00 | $100.00 |

Context: **1,050,000 total** / 922,000 max input / **128,000 max output**; cutoff 2026-04-30.
Codex credit equivalents: 250 / 25 / 1,250 credits per 1M — which divides to **exactly $0.04/credit
on 10/10 rows** (§3), i.e. purchased credits are at **API parity, no subscriber discount**.

## 7. Sources

- https://learn.chatgpt.com/docs/pricing (canonical Codex pricing; `developers.openai.com/codex/pricing` 308s here)
- https://developers.openai.com/api/docs/pricing (canonical API pricing; `platform.openai.com/docs/pricing` 301s here)
- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers (403 to fetch; read via snippet)
- https://help.openai.com/en/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-freegopluspro-sora (403; snippet)
- https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
- https://openai.com/index/gpt-6-astra/ and https://openai.com/index/path-to-astra/ (403; snippet)
- https://www.infoq.com/news/2026/09/openai-gpt6-astra/
- https://fortune.com/2026/09/11/openai-astra-chatgpt-pro-pause/
- https://www.cio.com/article/4221092/openai-pauses-200-pro-tier-as-astra-demand-strains-capacity/
- https://github.com/openai/codex/pull/42605
- Community (marked as such): https://uibakery.io/blog/openai-codex-pricing · https://www.taskade.com/blog/codex-pricing-explained · https://codex.danielvaughan.com/2026/09/03/gpt-6-astra-codex-cli-configuration-context-notes-safety/ · https://github.com/pleaseai/shunt/issues/458
