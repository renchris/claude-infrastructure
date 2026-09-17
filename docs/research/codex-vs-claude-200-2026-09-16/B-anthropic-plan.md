# B — The Anthropic $200/mo plan, as of 2026-09-16

Researched live against anthropic.com / claude.com / support.claude.com / platform.claude.com /
code.claude.com on 2026-09-16. **My model knowledge cutoff is May 2026, so every fact about Fable
5.1, the 50% Fable rule, usage credits, and the September 2026 limit change could only come from
the web** — none of it is recall, and all of it is cited below.

---

## Headline answers

| # | Question | Answer |
|---|---|---|
| 1 | Plan name | **Claude Max 20x**, $200/mo. Still the top individual tier. |
| 2 | Fable 5.1 | `claude-fable-5-1`, launched **2026-09-01**. **Included** on Max — but capped at **50% of the weekly limit**, drawn from the *same* pool, not additive. |
| 3 | API price | $10 in / $50 out / $12.50 5m-cache-write / $20 1h-cache-write / **$0.25 cache read** per MTok. |
| 4 | Window | **1M context / 128K max output.** |
| 5 | Hours table | **The current version does not exist.** The famous "240–480 h Sonnet / 24–40 h Opus" table is July-2025 and names retired models. |
| 6 | Frontier accounting | Yes, different — Fable has a 50% weekly ceiling, Opus has its own weekly reset. **Cache reads DO draw on plan limits** (unlike API ITPM). |

---

## Facts with sources

| # | Fact | Exact wording (where quotable) | Source | Published / updated |
|---|---|---|---|---|
| 1.1 | The $200 tier is **Max 20x** | "$200 per month"; includes "20 times the Pro plan's per-session usage allowance" | [support.claude.com/…/11049741-what-is-the-max-plan](https://support.claude.com/en/articles/11049741-what-is-the-max-plan) | updated "today" (2026-09-16) |
| 1.2 | Max 5x is the $100 tier | "five times the Pro plan's per-session usage allowance" | same | 2026-09-16 |
| 1.3 | 5-hour rolling window | "Your session-based usage limit will reset every five hours" | same | 2026-09-16 |
| 1.4 | Weekly limit, all models | "a weekly usage limit that applies across all models"; "The weekly limit resets at a fixed time each week that is assigned to your account" | same | 2026-09-16 |
| 1.5 | Anthropic reserves discretion | may "limit your usage in other ways, such as weekly and monthly caps or model and feature usage, at our discretion" | same | 2026-09-16 |
| 1.6 | Exhaustion = **hard stop with named options, not a silent downgrade** | Errors are `You've hit your session limit` / `You've hit your weekly limit`; that window is "shared across all models, so the developer can't restore access by switching models with `/model`" | [code.claude.com/docs/en/costs](https://code.claude.com/docs/en/costs) § When a developer asks about a limit; error strings on [/docs/en/errors](https://code.claude.com/docs/en/errors) | live 2026-09-16 |
| 1.7 | Model-family limits *are* escapable | "After the model-specific 'You've hit your Opus limit' or 'You've hit your Sonnet limit' message, switching to a model outside that family with `/model` does keep the developer working." | code.claude.com/docs/en/costs | live |
| 1.8 | Option A at exhaustion: **usage credits** (pay-as-you-go) | "Usage credits allow individuals subscribed to paid Claude plans to continue using Claude seamlessly after reaching their included usage limits", billed at "standard API rates" | [support.claude.com/…/12429409-manage-usage-credits](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans) | 2026-08-10 |
| 1.9 | Usage credits are **opt-in**, cover Claude Code | "Usage credits apply to both Claude conversations and Claude Code terminal usage." Enabled in Settings > Usage; `/usage-credits` in CC | same + code.claude.com/docs/en/costs | 2026-08-10 |
| 1.10 | Option B: **wait and auto-resume** | CC v2.1.234+ can "wait and continue the interrupted task automatically after the reset"; fleet-controlled via `autoContinueAtUsageLimit` | code.claude.com/docs/en/costs | live |
| 1.11 | Pool is shared across surfaces | Claude Code allowance "is shared with Claude chat and Cowork" | code.claude.com/docs/en/costs | live |
| 2.1 | Model ID + alias | Claude API ID **`claude-fable-5-1`**; alias identical (dateless IDs are their own pinned snapshot) | [platform.claude.com/docs/en/models/overview](https://platform.claude.com/docs/en/models/overview) | live 2026-09-16 |
| 2.2 | Release date | "Claude Fable 5.1 and Claude Mythos 5.1 launch" — **September 1, 2026** | [support.claude.com/…/12138966-release-notes](https://support.claude.com/en/articles/12138966-release-notes); [anthropic.com/claude-fable-and-mythos-5-1](https://www.anthropic.com/claude-fable-and-mythos-5-1) | 2026-09-01 |
| 2.3 | Included on all paid plans | "Claude Fable 5 and Claude Fable 5.1 are available on all paid plans (Pro, Max, Team, and Enterprise)." | [support.claude.com/…/15424964-claude-fable-models-on-your-plan](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan) | updated ~2026-08-30 ("over 2 weeks ago") |
| 2.4 | **The 50% rule — a ceiling, not a bucket** | "You can use up to 50% of your weekly limit on Fable models, but your use of other models draws from the same usage limits and you can never use more than your weekly limit." | same | ~2026-08-30 |
| 2.5 | Who gets it free | Max / premium Team / premium Enterprise: "you can use up to 50% of your weekly usage limits on Fable models at no extra cost". **Pro and standard seats do not** — Fable runs on pay-as-you-go usage credits there | same | ~2026-08-30 |
| 2.6 | At the 50% wall | "You can continue in one of two ways: keep using Fable models with usage credits, or switch to another Claude model to keep working within your plan's usage limits." | same | ~2026-08-30 |
| 2.7 | Fable burns the meter faster | Fable models "draw from your plan's regular weekly usage limits and use them **faster than other Claude models**" (mechanism unstated) | same | ~2026-08-30 |
| 2.8 | **Claude Code version floor** | "In Claude Code, Fable 5 requires version 2.1.170 or later and **Fable 5.1 requires version 2.1.255 or later**." | same | ~2026-08-30 |
| 2.9 | Never a default | "Neither Fable model is the account-type default on any plan or provider. Select one explicitly" | [code.claude.com/docs/en/model-config](https://code.claude.com/docs/en/model-config) | live |
| 2.10 | Fable billing routing in CC | "Fable usage can bill to usage credits instead of drawing on your plan's included limits." | same | live |
| 3.1 | **Fable 5.1 API pricing** | Input **$10/MTok** · 5m cache write **$12.50/MTok** · 1h cache write **$20/MTok** · cache read **$0.25/MTok** · output **$50/MTok** | [platform.claude.com/docs/en/about-claude/pricing](https://platform.claude.com/docs/en/about-claude/pricing) | live 2026-09-16 |
| 3.2 | The cache-read cut is the whole story | "Cache hits and refreshes on Claude Fable 5.1 and Claude Mythos 5.1 are priced at 0.025x the base input price. All other models use the standard 0.1x multiplier." Fable **5.0** cache read is $1/MTok — 5.1 is **4× cheaper** on that line at identical sticker | same | live |
| 3.3 | Batch | Fable 5.1 batch: $5 in / $25 out per MTok (50% off) | same | live |
| 3.4 | vs Opus 5 | Opus 5 is $5 / $25 / $6.25 / $10 / $0.50 — i.e. **Fable 5.1 is exactly 2× Opus 5 on input and output**, but **2× *cheaper* on cache reads** ($0.25 vs $0.50) | same | live |
| 4.1 | **Context window** | Fable 5.1: **1M tokens** (same as Opus 5 and Sonnet 5) | [platform.claude.com/docs/en/models/overview](https://platform.claude.com/docs/en/models/overview) | live |
| 4.2 | **Max output** | **128K tokens** (synchronous Messages API) | same | live |
| 4.3 | Long context is not surcharged | "Claude 4.6 and later models … include the full 1M token context window at standard pricing" | platform pricing page | live |
| 4.4 | Thinking is always on | Fable 5.1 thinking: "Adaptive (always on)", default effort `high`; "You can't turn off thinking on Fable models" | models overview + code.claude.com/docs/en/costs | live |
| 4.5 | Knowledge cutoff | Reliable knowledge cutoff **Jun 2026**; retirement not sooner than **2027-09-01** | models overview | live |
| 4.6 | Tokenizer caveat | 4.7-and-later models use a newer tokenizer producing "approximately 30% more tokens for the same text" — so 1M tokens ≈ 555k words, not 750k | platform pricing page | live |
| 5.1 | **No current hours table** | See "Unknowns" below — checked five candidate official pages, none carries one | — | — |
| 5.2 | The *historical* table (STALE, do not quote as current) | "240 to 480 hours of **Sonnet 4** and 24 to 40 hours of **Opus 4** per week" for the $200 Max plan | July 2025 Anthropic weekly-limit announcement, as reported by [techcrunch.com](https://techcrunch.com/2025/07/28/anthropic-unveils-new-rate-limits-to-curb-claude-code-power-users/) | 2025-07-28 — **names two retired models** |
| 6.1 | Opus has its own weekly reset | "Weekly limits: Check when your plan's weekly usage limit resets **for Opus only and all other models**." | [support.claude.com/…/9797557-usage-limit-best-practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices) | updated "today" (2026-09-16) |
| 6.2 | 🚨 **Cache reads DO draw on subscription limits** | "Claude Code re-reads that history at the cached token rate, so a one-line question in a session that has been open all day still draws usage for the whole conversation." | [code.claude.com/docs/en/costs](https://code.claude.com/docs/en/costs) § Why usage climbs in a long session | live |
| 6.3 | …but cache reads do **NOT** count toward **API** ITPM | "`cache_read_input_tokens` (tokens read from cache) ✗ **Do NOT count toward ITPM** for most models" | [platform.claude.com/docs/en/api/rate-limits](https://platform.claude.com/docs/en/api/rate-limits) | live |
| 6.4 | Cache TTL differs by funding source | "The lifetime is **an hour on a subscription** and drops to **five minutes once you're drawing on usage credits**" | code.claude.com/docs/en/costs | live |
| 6.5 | Fable API rate limit is far tighter than Opus | Start tier: Fable 5.x **500K ITPM / 100K OTPM** vs Opus 5 **2M / 400K**. Fable 5.1 and 5.0 share **one combined** bucket | platform rate-limits page | live |

### 6.2 vs 6.3 — the distinction that matters, stated plainly

These two are not in conflict and it is easy to mis-read one as the other:

- **API rate limits** (org-tier ITPM/OTPM, the Console) — cache reads are **free of the limit**.
- **Subscription usage limits** (the 5-hour and weekly windows a Max seat spends) — cache reads
  **are metered**, merely at the cheaper cached rate.

For a heavy Claude Code user on Max 20x, **6.2 is the operative rule**: a long-lived session
re-sends its whole history every turn, and every one of those turns spends plan quota. Anthropic's
own remedy list is `/clear` between unrelated tasks, resume-from-summary, and avoiding cache misses
(a miss "reprocesses your full context" at full price).

---

## The September 2026 limit change — flagged, partly unverifiable

⚠️ **Community/press, with an official-statement provenance I could not confirm on an Anthropic-owned page.**

BleepingComputer (pub. **2026-08-29**) quotes Anthropic directly: *"Starting September 14, we're
permanently raising standard weekly limits in Claude Code by 25% for Pro, Max, Team, and seat-based
Enterprise plans."* The article attributes this to an Anthropic post on X that was deleted and
reposted, and frames the net effect as a **~17% cut** versus the temporary +50% boost that expired
the same day (125% of baseline replacing 150%).
Source: [bleepingcomputer.com](https://www.bleepingcomputer.com/news/artificial-intelligence/anthropic-is-cutting-claude-codes-current-weekly-limits-by-17-percent/)

**What I could not do:** find this on anthropic.com/news, claude.com/blog, the support release
notes, or the Claude Code changelog. Searches restricted to Anthropic-owned domains returned
nothing for it. The most recent limits post on anthropic.com is
[Higher usage limits and a SpaceX compute deal](https://www.anthropic.com/news/higher-limits-spacex)
(**2026-05-06**), which doubled the *5-hour* rate limits and removed the peak-hours reduction — a
different change.

⇒ Treat "weekly limits are 125% of baseline since 2026-09-14" as **probable but not officially
documented**. It is two days old as of this research and is the kind of fact that should be read off
`/usage` on the live account rather than quoted from here.

---

## Unknowns / not published

1. **No current hours-per-week table exists.** Checked, all live on 2026-09-16, none carries one:
   `claude.com/pricing` · `support.claude.com/…/11049741-what-is-the-max-plan` ·
   `support.claude.com/…/11145838-use-claude-code-with-your-pro-or-max-plan` ·
   `support.claude.com/…/9797557-usage-limit-best-practices` · `code.claude.com/docs/en/costs`.
   The Max plan article gives a multiplier ("20 times the Pro plan's per-session usage allowance")
   and nothing absolute. **The 240–480 h / 24–40 h figures are from July 2025 and name Sonnet 4 and
   Opus 4, both retired** — do not present them as current. Anthropic's own current position is that
   usage is read from the product: `/usage` in Claude Code, or Settings > Usage on claude.ai.

2. **The absolute size of one "unit" of the weekly limit is not published** in any form — not tokens,
   not messages, not hours. Everything official is relative (5x, 20x, "50% of your weekly limit").

3. **How Fable "uses limits faster" is not specified.** The support article states the effect and
   not the mechanism. Whether the meter is weighted by the 2× token price, by compute, or by
   something else is unstated. Notably the always-on thinking (4.4) is itself billed as output, so
   at least part of the effect needs no special weighting to explain.

4. **No `You've hit your Fable limit` error exists** in the Claude Code error reference — only
   session / weekly / Opus / Sonnet / spend variants. Consistent with the Fable 50% wall routing to
   usage credits or a model switch rather than to a hard stop, but I found no page stating that
   directly.

5. **Whether the 50% Fable ceiling is measured against the boosted or baseline weekly limit** is not
   stated anywhere, and interacts with the unverified September 14 change.

6. **Anthropic publishes no hard-stop-vs-fallback statement for Claude Code.** `code.claude.com/docs/en/model-config`
   documents only *availability*-based fallback (primary model overloaded) and *classifier*-based
   fallback, plus `opusplan`'s planned mode switch. **There is no documented usage-threshold
   auto-downgrade.** The old community-reported "Opus for the first 50%, then Sonnet" behaviour is
   not in current docs; GitHub issues #3434 / #12487 / #16875 are **community** reports of
   silent-fallback behaviour and its inconsistencies, not documentation.

7. **`support.claude.com/en/articles/11014257-about-claude-max-plan-usage`** — the article several
   search engines still surface as the canonical Max-usage page — now returns **HTTP 404** under
   both the `support.anthropic.com` and `support.claude.com` hosts. Its content appears to have been
   folded into 11049741. Any prior citation of it is dead.

---

## Local corroboration (non-web, for cross-check only)

`~/.claude/model-config.yaml` (this machine, updated 2026-09-03) independently agrees on the ID and
the economics: `frontier_latest: claude-fable-5-1`, flipped 2026-09-03 after `cc-upgrade-gate` on
2.1.260 returned GREEN. Its own note: base rates are unchanged from Fable 5 at $10/$50, the tokenizer
carries over, and *"the cache-read line item drops 4×, so 5.1 is materially CHEAPER per session than 5
at the same sticker."* It also records three breaking changes vs Fable 5 (thinking always-on, so any
`thinking: disabled` request is demoted; thinking blocks are model-bound one-directionally — 5.1 reads
earlier models' blocks but not vice-versa; see `/models/fable-5-1/whats-new-fable-5-1`). Treat this as
corroboration of the web sources, not as a source in its own right.

---

## Sources

- [claude.com/pricing](https://claude.com/pricing)
- [support.claude.com — What is the Max plan?](https://support.claude.com/en/articles/11049741-what-is-the-max-plan)
- [support.claude.com — Claude Fable models on your plan](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan)
- [support.claude.com — Manage usage credits for paid Claude plans](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans)
- [support.claude.com — Usage limit best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices)
- [support.claude.com — Use Claude Code with your Pro or Max plan](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan)
- [support.claude.com — Release notes](https://support.claude.com/en/articles/12138966-release-notes)
- [platform.claude.com — Pricing](https://platform.claude.com/docs/en/about-claude/pricing)
- [platform.claude.com — Models overview](https://platform.claude.com/docs/en/models/overview)
- [platform.claude.com — Rate limits](https://platform.claude.com/docs/en/api/rate-limits)
- [code.claude.com — Manage costs effectively](https://code.claude.com/docs/en/costs)
- [code.claude.com — Model configuration](https://code.claude.com/docs/en/model-config)
- [code.claude.com — Errors](https://code.claude.com/docs/en/errors)
- [anthropic.com — Introducing Claude Fable 5.1 and Claude Mythos 5.1](https://www.anthropic.com/claude-fable-and-mythos-5-1)
- [anthropic.com — Higher usage limits and a SpaceX compute deal](https://www.anthropic.com/news/higher-limits-spacex)
- **(press)** [bleepingcomputer.com — Anthropic is cutting Claude Code's current weekly limits by 17%](https://www.bleepingcomputer.com/news/artificial-intelligence/anthropic-is-cutting-claude-codes-current-weekly-limits-by-17-percent/)
- **(press, historical)** [techcrunch.com — Anthropic unveils new rate limits](https://techcrunch.com/2025/07/28/anthropic-unveils-new-rate-limits-to-curb-claude-code-power-users/)
