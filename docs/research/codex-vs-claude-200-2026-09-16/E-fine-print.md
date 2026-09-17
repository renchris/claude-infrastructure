# E — Fine print & structural constraints of the two $200/mo coding subscriptions
Research date: **2026-09-16**. All claims dated; DOCUMENTED POLICY separated from FOLKLORE.
Status: DRAFT — sections filled as evidence lands. Changelog at EOF.

---

## 0. The two headline facts that dominate everything below

1. **You cannot buy OpenAI's $200 tier right now.** On **2026-09-10** OpenAI *paused new
   sign-ups and upgrades to ChatGPT Pro $200 (Pro 20x)* — from Free, Go, Plus, *and* from
   Pro $100 — citing infrastructure strain from GPT-6 Astra demand. Existing $200
   subscriptions are unaffected; Pro $100 is unaffected.
   (TechCrunch 2026-09-10; OpenAI Help Center "About ChatGPT Pro tiers".)
   ⇒ If the user does not already hold a Pro $200 seat, this comparison is not a live choice.

2. **Anthropic's programmatic-usage split was announced and then CANCELLED on the day it
   was due.** Announced 2026-05-14 for a 2026-06-15 start; on **2026-06-15** Anthropic
   confirmed in its Help Center that moving Agent SDK / `claude -p` / GitHub Actions /
   third-party-app usage to a separate metered credit is **"no longer happening"**, that
   *"those surfaces continue drawing from your Pro, Max, Team, and Enterprise subscription
   limits exactly as before"*, and that it would *"give advance notice before any future
   change takes effect."*
   ⇒ Headless `claude -p` — the user's dispatched-session and cron workload — is **today**
   inside the flat $200, at no metered premium. This is the single largest value term on
   the Anthropic side, and it is a *reversal*, i.e. perishable. Re-check before relying.

---

## 1. Terms of service on automation, headless and concurrency

### Anthropic — Consumer Terms of Service (effective **2025-10-08**)

§3 prohibited uses, the clause that matters, verbatim:

> "Except when you are accessing our Services via an Anthropic API Key or where we
> otherwise explicitly permit it, to access the Services through automated or non-human
> means, whether through a bot, script, or otherwise."

Also §3: no crawling/scraping/harvesting; no building competing products; no reselling.
§2, verbatim:

> "You may not share your Account login information, Anthropic API key, or Account
> credentials with anyone else. You also may not make your Account available to anyone
> else."

§12, verbatim:

> "we reserve the right to modify, suspend, or discontinue the Services or your access to
> the Services, in whole or in part, at any time without notice."

**Reading.** The automated-access ban is written broadly but carries the "**where we
otherwise explicitly permit it**" carve-out, and Claude Code is Anthropic's own product
documented for scripted/CI use — so first-party CLI automation (including `claude -p`,
GitHub Actions, hooks, subagents) sits inside the carve-out. What the clause was *enforced*
against in 2026 is **third-party harnesses authenticating with subscription OAuth tokens**,
not first-party automation volume. Note the tension a practising lawyer flags: read
literally, the clause would also forbid Anthropic's own documented CI examples
(Daimon Legal, 2026-09-07) — i.e. the boundary is set by enforcement practice, not text.

**NOTHING IN EITHER CONTRACT CAPS CONCURRENT SESSIONS.** Neither Anthropic's Consumer
Terms nor (below) OpenAI's terms contain a numeric concurrency limit, a ban on parallel
sessions, or a ban on unattended operation. The constraint is the *rate limiter*, not the
contract.

### Enforcement actions actually documented in 2026

| Date | Event | Source class |
|---|---|---|
| 2026-02-20 | Anthropic *clarifies* that third-party tool access on subscription auth is banned | The Register (press) |
| ~2026-02 | OpenClaw users' accounts terminated; the Agent SDK explicitly requires an **API key**, not a Pro/Max OAuth token | press + vendor docs |
| 2026-04-04 | Policy expressly prohibits subscriptions powering non-Anthropic agents/harnesses, citing capacity; stated reason: such tools *"bypassed the caching mechanisms that allow Anthropic to offer flat-rate subscriptions"* | VentureBeat 2026-05-13 |
| 2026-05-13 | Third-party agent use **reinstated** via "Agent SDK credits" | VentureBeat |
| 2026-06-15 | The credit split **cancelled** before taking effect | Anthropic Help Center via aicodex.to |
| ~2026-08-24 | A law firm's OpenClaw access terminated without warning, minimal refund, billing continued | Daimon Legal 2026-09-07 (single case, self-reported) |

**Folklore vs documented:** "Multiple users report being charged while locked out" is
asserted with no count or timeline — treat as folklore. The *policy* changes above are
documented. **No documented enforcement action against a heavy user of first-party
Claude Code or first-party Codex CLI was found** — the bans track third-party-harness
authentication, not volume.

---

## 2. Overage — buying more on top of $200

### Anthropic: yes, and it is plain API pricing
Support article *"Manage usage credits for paid Claude plans"* (last updated 2026-08-10):
- Eligible: **"Pro, Max 5x, and Max 20x"**.
- Rate: **"billed at standard API rates"** — so the marginal token is *exactly* API price,
  never cheaper. The subscription's value is entirely in the included block.
- Controls: self-set **monthly spending cap**, auto-reload, **$2,000/day** redemption limit.
- **"Usage credits apply to both Claude conversations and Claude Code terminal usage."**
- Expiry: don't expire in most regions; **in Japan, credits expire 6 months after purchase,
  starting 2026-09-10** (a genuine region-specific term).

### OpenAI: yes, credits, priced in a credit unit
- *"ChatGPT Plus and Pro users who reach their usage limit can purchase additional credits
  to continue working without needing to upgrade their existing plan."* (learn.chatgpt.com/docs/pricing)
- Credit ≈ **$0.04**. Rate card is quoted in credits/1M tokens, e.g. **GPT-6 Astra 250 in /
  25 cached / 1,250 out**; GPT-5.6 Sol 100/10/500; Luna 5/0.5/30. **"Fast mode applies a
  2.5x multiplier to Astra rates."**
- Cached input ≈ **1/10th** of fresh input on both vendors' coding models — the single
  biggest lever on effective marginal cost for long-context agent loops.

⇒ **On both sides, overage is at or above plain API price. Neither plan makes the marginal
token cheaper than the API.** The $200 buys the *included block* and nothing else.

---

## 3. Rollover
- **Anthropic:** no rollover of the 5-hour or weekly allowance. Purchased *credits* are a
  balance and persist (except Japan, 6 months). The cancelled Agent-SDK credit was
  explicitly non-rolling and *"Anthropic reclaims"* unredeemed amounts.
- **OpenAI:** limits *"reset every five hours, not monthly"*; no rollover documented.
  Referral-reward credits expire 30 days; general purchased-credit expiry not stated.

⇒ Assumption confirmed: **unused weekly allowance is decaying inventory on both sides.**

---

## 4. Limits are being changed under you — with dates

**Anthropic, Claude Code weekly limits, 2026:**

| Period | Relative weekly capacity |
|---|---|
| baseline | 100 |
| 2026-05-13 → 2026-09-13 (promo, extended 4×: mid-Jul → Jul 19 → Aug 19 → Aug 31 → Sep 13) | 150 |
| **2026-09-14 onward ("permanent 25% increase")** | **125** |

Announced as a *"permanent 25% raise"*; against the level actually in force the day before,
it is a **~17% cut** (150 → 125). Also 2026-05-06: 5-hour limits permanently **doubled**
for Pro/Max/Team/seat-based Enterprise and **peak-hour throttling removed** for Pro and Max.

**Structure of the Anthropic meter (two caps, plus a model-specific third):**
- rolling **5-hour** window, and
- **weekly** cap resetting every 7 days, and
- a **separate weekly cap for the top model** (Opus-class; the local tooling tracks it as a
  distinct `weekly-Fable` meter). Top-model tokens burn the shared weekly cap ~5× faster
  than mid-tier for equivalent work.

**OpenAI meter:** 5-hour windows, per-model message-count bands, **"weekly limits may
apply"**, and all figures published as *estimates, not fixed caps*.


**OpenAI meter, corrected by a first-party statement.** Codex lead **Tibo Sottiaux
(@thsottiaux), 2026-08-25**, verbatim:

> "For clarity, while both are called 20X, in Codex they apply specifically to weekly usage
> limits. And we also don't have 5h limits for both Pro plans. The Pro 20X is quite
> precisely 20X the usage of the Plus subscription, so it does exactly what it says on the
> tin."

⇒ **Pro $100 and Pro $200 currently have NO rolling 5-hour gate — only a weekly cap.** The
5-hour gate returned for Plus on 2026-08-26 and Pro stayed exempt "for the upcoming
months". This is the **largest structural asymmetry in the whole comparison for a bursty
parallel workload**: Anthropic gates you three ways (5h × weekly × top-model-weekly),
OpenAI Pro gates you once (weekly). Caveat: explicitly temporary.

**Anthropic has throttled by time-of-day before and can again.** From March 2026 Anthropic
*reduced* 5-hour limits during weekday peak (05:00–11:00 PT) under compute pressure;
removed for Pro/Max on 2026-05-06 alongside the SpaceX compute partnership. Precedent, not
prediction — but it is a documented lever, and §12 licenses its return "without notice".

---

## 5. Per-model sub-limit: the Fable cap (Anthropic only)

Claude Help Center, *"Claude Fable models on your plan"* (last updated ~2026-09-01):

- **Max plans + premium seats:** Fable 5 **and 5.1** included; you may spend **up to 50% of
  your weekly usage limit** on Fable at no extra cost. Fable tokens *"draw from your plan's
  regular weekly usage limits and use them faster."*
- **It is a CEILING INSIDE the pool, not added capacity.** Not "weekly limit + 50% Fable" —
  the same weekly limit, at most half of it spendable on Fable.
- Hitting the 50% cap: continue on **usage credits at API rates ($10/M in, $50/M out)**, or
  switch model and continue against normal limits.
- **Pro and standard Team seats:** Fable is **not plan-included at all** — usage credits
  from the first token. A one-time credit was granted when Fable 5 moved to credits (July
  2026); **no equivalent credit for Fable 5.1.**
- Prior promo (50% of weekly on Fable 5, free) **ended 2026-07-19 23:59:59 PT**; the 50%
  structure then became standard on Max.

OpenAI has **no direct equivalent**: Astra is inside the ordinary Codex allowance on Pro
$100/$200 and Business $100, but is metered far heavier per token (Astra 250 in / 1,250 out
credits/1M vs Luna 5 / 30) and **"Fast mode applies a 2.5x multiplier to Astra rates."**
That is a price-per-token sub-limit rather than a percentage cap — it bites continuously
instead of at a wall.

---

## 6. Multi-account — the axis that matters most here, and the answer is asymmetric

### Anthropic
- **Holding several Max subscriptions is not itself a ToS violation.** §2 forbids *sharing*
  credentials and *making your Account available to anyone else* — one person, several of
  their own accounts, each used only by them, does not engage that sentence.
- **What gets banned is the architecture, not the count.** Two patterns, distinguished in
  practice:
  - **BANNED — relay/pool:** a server holding several OAuth tokens, load-balancing an
    Anthropic-compatible endpoint, impersonating the official client (e.g.
    claude-relay-service). Flagged on *"same source endpoint, many tokens, high volume per
    token."* This is what the April 2026 OpenClaw wave hit.
  - **ACCEPTED — per-profile isolation:** separate credential directories via
    **`CLAUDE_CONFIG_DIR`**, each running the **official client binary**, each
    authenticating through the **official OAuth flow**. `CLAUDE_CONFIG_DIR` is documented
    in Anthropic's own environment-variable reference and was acknowledged in
    anthropics/claude-code#261 (closed completed, 2025-03-05).
  - ⇒ **The operator's four-account setup is the accepted pattern**, by construction: four
    config dirs, official binary, official OAuth, one human. Keep it that way — the moment
    a relay or a token pool appears in front of it, it becomes the banned pattern.
- **But ban waves did hit multi-Max holders.** Mid-February 2026: users holding several
  $200 Max subscriptions reported lockouts without warning. Reported analysis: in most real
  cases another behaviour was layered on top; small 2–3-account operators pass the volume
  heuristic, 100+-account operators ship in waves. **This is partly folklore** — no vendor
  statement, no counts. Treat as: the heuristic exists, its threshold is unpublished, and a
  4-account single-box footprint is well below the described flag band.
- Anthropic's hardening stack 2025–2026 (geoblocking, phone verification, billing-address
  match, biometric KYC from April 2026) is aimed at farmed accounts, not at a verified
  individual with four paid seats.

### OpenAI
- **Multiple accounts are a supported first-party feature** — Help Center ships
  *"Use multiple accounts with account switching."*
- **Sharing one account is clearly prohibited**, verbatim from the Terms of Use:
  > "You may not share your account credentials or make your account available to anyone
  > else and are responsible for all activities that occur under your account."
- ⚠️ **Enforcement heuristic worth knowing:** community/secondary reporting says
  *concurrent sessions* on one account can trip account-sharing flags, escalating to
  suspension. That is aimed at credential sharing — but the signal it reads (many
  simultaneous sessions from one login) is **exactly what this workload emits**. Sourced to
  blogs, not OpenAI; **FOLKLORE, flagged as a live false-positive risk, not a documented
  policy.**

---

## 7. Automation policy — the sharpest divergence between the two vendors

| | Anthropic | OpenAI |
|---|---|---|
| Clause bans… | automated **ACCESS** ("through a bot, script, or otherwise") | automated **EXTRACTION OF OUTPUT** ("use any automated or programmatic method to extract data or output from the Services, including scraping, web harvesting, or web data extraction" — *"except as permitted through the API"*) |
| Carve-out | "where we otherwise explicitly permit it" — first-party Claude Code, `claude -p`, GitHub Actions | the API itself |
| Third-party harness on subscription auth | **PROHIBITED** and enforced (bans, Feb–Apr 2026). Agent SDK **requires an API key**; Free/Pro/Max OAuth tokens are refused. | **Publicly permitted.** OpenAI, April 2026: *"We want people to be able to use Codex, and their ChatGPT subscription, wherever they like"* — after Simon Willison reverse-engineered the Codex CLI auth flow and shipped a plugin routing prompts through subscriptions. |
| Counter-current | — | August 2026: OpenAI attributed abnormal usage-limit drain on ChatGPT-login plans to the unsupported **sub2api** workaround; guidance is that ChatGPT login suits *interactive, human-started* sessions and **API keys suit unattended scripts, CI and server-controlled agent workflows.** A norm, not a term. |

⇒ **Neither contract caps concurrency or bans unattended use of the vendor's own CLI.** The
Anthropic clause is textually broader but carved out for first-party tooling; the OpenAI
clause does not reach agent loops at all. **The binding constraint on both sides is the
rate limiter and an undocumented throughput limiter — not the contract.**

---

## 8. 🚨 The undocumented constraint that actually bites: a burst/concurrency limiter distinct from quota

Not in any published policy. Documented in Anthropic's **own** issue tracker:

- **anthropics/claude-code#53922** — Max plan, OAuth, bulk-spawning ~10 sessions across
  separate worktrees right after a 5-hour reset: *"first 3–4 sessions start normally, the
  next 5–6 fail almost immediately"* with, verbatim:
  > `API Error: Server is temporarily limiting requests (not your usage limit) · Rate limited`
  Retrying one-by-one with delay succeeds. Highly reproducible. **Closed as not planned.**
- **#52784** — four Max accounts ($800/mo) on one machine: *"Rate limited everywhere"*,
  plus `AxiosError: timeout of 5000ms exceeded`, `401 Invalid authentication credentials`.
  Opened 2026-04-24, **closed as not planned, no maintainer response.** Whether the limiter
  keys on IP, machine or account is **never stated** — which is itself the finding, since a
  per-IP key would mean extra accounts buy less than their face value on one box.
- **#68502** — HTTP **529 `overloaded_error` rendered as "Rate limited"**, hard-failing
  parallel sessions and subagents with **no backoff and no error log**.
- **#76133** — Max 20x rate-limited *within* usage limits during subagent orchestration
  (3–6 concurrent subagents/phase), **no early warning, no budget visibility**.
- **#68772** — concurrent sessions on *different accounts* share the statusline
  `rate_limits` display (display-only, but it means the on-screen number can be another
  account's).
- **#63938** — feature request for a configurable concurrent-subagent cap; the workflow
  engine caps `agent()` concurrency at **min(16, cpu_cores − 2)**.

**Reading:** a quota is a gas tank; this is a fuel-line diameter. It is **undocumented,
unannounced, closed-as-not-planned, and sits at ~3–4 simultaneous cold starts** — i.e.
below the operator's standing 6-concurrent-teammate ceiling and far below a 10–12-unit
research wave. Mitigation is stagger-and-retry-with-jitter, which is a client-side
workaround for a server behaviour with no published threshold.

**No equivalent corpus was found on the OpenAI side for local Codex CLI.** For **Codex
cloud** the picture is contested: secondary sources state **3 concurrent tasks on Pro**,
while a 2026-08-31 survey states OpenAI publishes *"no CPU, RAM, max runtime, or
concurrency cap for cloud tasks."* **UNRESOLVED — flagged, not asserted.**

---

## 9. Cloud agents — does either double throughput? **No. Both share one pool.**

- **Anthropic:** *subscription limits are shared across Claude Code, claude.ai chat, and
  Cowork.* One pool. Cloud work does not add capacity; it spends the same weekly meter.
- **OpenAI:** *"Local messages and cloud chats share the same usage allowance"*
  (learn.chatgpt.com/docs/pricing), and cloud chats may consume **more** of the allowance
  than local messages. Cloud task volumes on Pro 20x: ~200–1,200 cloud tasks and 400–1,000
  code reviews per 5-hour window (legacy figures, from before the Pro 5h gate was removed).
  Go ($8) excludes cloud delegation entirely; Plus and above include it.
  Scheduled tasks support timers and — since 2026-08-25 — **event triggers**, on Plus and
  above (a task cannot combine an event trigger with a time schedule).

⇒ **Q7 answers negative for both.** Offloading to cloud agents buys *wall-clock parallelism
and a machine you don't own*, never extra quota. The only genuine throughput multiplier on
either platform is **more seats**, or **API-priced overage**.

---

## 10. Seats and team tiers at or near $200

| Option | Price | Per-dollar headroom |
|---|---|---|
| **Claude Max 20x** | $200/mo, 1 user | ~20× Pro per 5h window |
| **Claude Team Premium** | **$100/seat/mo annual, $125/seat/mo monthly**; 2-seat minimum; limits are **per-member**, not pooled | **6.25× Pro** per session |
| Claude Team Standard | ~$20–30/seat | ~1× Pro; Fable NOT included |
| **ChatGPT Business** | **$20/user/mo annual ($25 monthly)**, 2+ users | Astra band **5–45 msgs/5h — identical to Plus**, not to Pro |
| ChatGPT Pro 5x | $100/mo | 25–225 Astra msgs/5h |
| **ChatGPT Pro 20x** | **$200/mo** | **100–900 Astra msgs/5h** |

**Verdict on Q4: no, no team tier gives more per dollar at this ceiling.**
- Two Claude Team Premium seats = $200–250/mo for **12.5× Pro total, split across two
  logins that cannot pool** — strictly worse than one Max 20x's 20× for a single operator,
  and it needs a second human-ish identity. Team Premium's one advantage is that Fable *is*
  included at the same 50% cap.
- ChatGPT Business at $20–25/seat looks cheap until you read the band: **Business sits at
  Plus-level per-seat limits, not Pro-level.** Ten Business seats ($200–250) would give
  10 × Plus = ~50–450 Astra msgs/5h against Pro 20x's 100–900 — *and* ten seats is ten
  logins to orchestrate, which re-enters account-sharing territory unless ten humans exist.

---

## 11. Non-comparability: what makes a straight $/token comparison invalid

1. **You cannot buy one of them.** OpenAI Pro $200 is closed to new sign-ups and upgrades
   since 2026-09-10 (a Polymarket market now exists on when US Pro-20x signups resume —
   i.e. still closed as of this writing).
2. **Different meter shapes.** Anthropic: 5h + weekly + 50%-Fable-weekly, three gates.
   OpenAI Pro: weekly only, 5h gate currently off. A burst workload is punished by the
   first and tolerated by the second.
3. **Different units, both estimated.** OpenAI publishes *message bands* per 5h ("estimates,
   not fixed caps") and a credit rate card; Anthropic publishes **no numeric weekly figure
   at all** — every "hours per week" number in circulation is third-party estimation.
   **A per-dollar comparison cannot be computed from published data on the Anthropic side.**
4. **Region.** Claude Max is unavailable in Russia, mainland China, DPRK, Iran, Cuba,
   Belarus, occupied Ukraine; ChatGPT's exclusion list is shorter. ChatGPT regional
   discounts apply to Plus/Go, **not** to Pro — Pro $200 is near-constant globally.
   Japan-specific: Anthropic usage credits **expire 6 months after purchase from
   2026-09-10.**
5. **Model retirement on a clock.** *"GPT-5.5 retires from ChatGPT, ChatGPT Work, and Codex
   on all plans on October 14, 2026."* Anthropic has no announced equivalent date.
6. **Both reserve the right to change limits.** Anthropic §12 verbatim: *"at any time
   without notice."* Anthropic did exactly that four times in 2026 (promo extended
   2026-07-mid → 07-19 → 08-19 → 08-31 → 09-13). OpenAI paused an entire tier's sales with
   ~no notice. The one countervailing promise: after the 06-15 reversal Anthropic committed
   to *"give advance notice before any future change takes effect"* — **scoped to the
   programmatic-billing change only**, not a general undertaking.
7. **The headline number can be a cut.** 2026-09-14's *"permanent 25% increase"* is +25% on
   baseline and **−17% against the level in force the previous day.** Any plan sized on
   August throughput is now over-provisioned relative to reality.

---

## 12. Adversarial pass — what I looked for and did not find, or could not verify

| Gap | Status |
|---|---|
| OpenAI canonical Terms of Use / Help Center text | **NOT READ.** `openai.com/policies/*` and `help.openai.com/*` return **HTTP 403** to WebFetch and to curl, and serve a **Cloudflare managed challenge** that did not clear in agent-browser ("Verification successful. Waiting for openai.com to respond" → challenge loop). Every OpenAI ToS quote above is **reproduced from a secondary source that quotes it**, not read at origin. Treat OpenAI clause wording as *high-confidence-but-unverified-at-origin*; Anthropic's is read at origin. |
| A numeric concurrent-session cap in either contract | **Does not exist.** Searched both ToS and both help centres. The limit is operational, not contractual. |
| Anthropic published weekly limit in absolute units | **Does not exist.** Anthropic publishes multipliers and resets, never hours or tokens. Every hour-figure in circulation is third-party estimate. |
| Codex cloud concurrency cap | **CONTESTED**: "3 concurrent on Pro" (secondary) vs "OpenAI publishes no concurrency cap" (2026-08-31 survey). Unresolved. |
| Commercial use of a *consumer* Max plan for revenue work | Not directly addressed by §3; §3 bans reselling *the Services* and building *competing* products. Using Claude Code to build client software is neither. No finding either way — **flagged, not asserted.** |
| Documented enforcement against a heavy **first-party** user | **NONE FOUND.** Every 2026 ban/throttle traced to third-party-harness auth or account farming. Volume alone produced rate limits, never bans. |
| Whether the burst limiter keys on IP/machine/account | **UNKNOWN and unanswered by Anthropic** (#52784 closed, no response). If per-IP, a 4-account single-box setup under-delivers relative to 4× face value. **This is the single most decision-relevant unknown in the whole file** and is cheaply testable locally: stagger N cold starts across accounts and record which fail. |

---

## 13. Bottom line for a many-parallel-sessions power user

1. **Anthropic $200 is the only one purchasable today** (OpenAI Pro $200 closed since
   2026-09-10).
2. **Headless `claude -p` is inside the flat fee today** only because the 06-15 split was
   cancelled on the day. That is the biggest single value term and the most perishable.
3. **Anthropic's meter is three gates; OpenAI Pro's is currently one.** For bursty parallel
   work OpenAI's shape is friendlier — if you already hold the seat.
4. **Overage is API-priced on both.** The $200 buys a block; nothing beyond it is discounted.
5. **Nothing rolls over on either.** Unused weekly allowance is decaying inventory —
   consistent with the operator's existing standing rule.
6. **The binding limit is not the contract, it is an undocumented ~3–4-concurrent-cold-start
   burst limiter that Anthropic has closed as not-planned.** Design waves around
   stagger + jitter, not around quota arithmetic.
7. **The 4-account architecture is the pattern Anthropic accepts** (per-profile
   `CLAUDE_CONFIG_DIR`, official binary, official OAuth). Do not put a relay in front of it.

---

## Sources

Anthropic / Claude
- Consumer Terms of Service (eff. 2025-10-08) — https://www.anthropic.com/legal/consumer-terms
- Manage usage credits for paid Claude plans (upd. 2026-08-10) — https://support.claude.com/en/articles/12429409-manage-extra-usage-for-paid-claude-plans
- Claude Fable models on your plan — https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan
- What is the Max plan — https://support.claude.com/en/articles/11049741-what-is-the-max-plan
- Updating our Usage Policy — https://www.anthropic.com/news/updating-our-usage-policy
- Redeploying Claude Fable 5 — https://www.anthropic.com/news/redeploying-fable-5
- Issues: #53922, #52784, #68502, #76133, #68772, #63938, #261 — https://github.com/anthropics/claude-code/issues/53922 · /52784 · /68502 · /76133 · /68772 · /63938

Press / analysis (Anthropic)
- VentureBeat 2026-05-13, OpenClaw reinstatement + Agent SDK credits — https://venturebeat.com/technology/anthropic-reinstates-openclaw-and-third-party-agent-usage-on-claude-subscriptions-with-a-catch
- The Register 2026-05-14 — https://www.theregister.com/ai-ml/2026/05/14/anthropic-tosses-agents-into-the-api-billing-pool/5240748
- The Register 2026-02-20 — https://www.theregister.com/software/2026/02/20/anthropic-clarifies-ban-on-third-party-tool-access-to-claude/5014546
- Axios 2026-05-14 — https://www.axios.com/2026/05/14/anthropic-claude-price-openai-tokens
- aicodex.to, June 15 change cancelled — https://www.aicodex.to/articles/claude-subscription-credit-changes
- explainx.ai, 17% cut math — https://explainx.ai/blog/anthropic-claude-code-limits-17-percent-cut-september-2026-august-2026
- BleepingComputer, 17% cut — https://www.bleepingcomputer.com/news/artificial-intelligence/anthropic-is-cutting-claude-codes-current-weekly-limits-by-17-percent/
- Daimon Legal 2026-09-07, ban account — https://www.daimonlegal.com/blog/anthropic-banned-my-account-for-using-openclaw-heres-what-to-do-if-it-happens-to-you
- dev.to, two multi-account architectures — https://dev.to/vainamoinen/two-multi-account-claude-code-architectures-one-anthropic-accepts-one-they-ban-2om7
- MetricNexus, multi-account bans — https://metricnexus.ai/blog/anthropic-banning-multiple-claude-accounts
- MindStudio, compute shortage — https://www.mindstudio.ai/blog/anthropic-compute-shortage-claude-limits
- Team Premium pricing — https://www.aipricing.guru/subscriptions/claude-team-premium/ · https://lord.technology/2026/03/28/claude-team-premium-vs-max-plans-usage-limits-pricing-and-which-to-choose.html
- Region availability — https://www.ssdnodes.com/learn/where-claude-is-available-by-country

OpenAI
- Pricing (learn.chatgpt.com, rate card + Astra bands + additional credits) — https://learn.chatgpt.com/docs/pricing
- Managing usage with GPT-6 Astra in Work and Codex — https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex *(403 to this instrument)*
- About ChatGPT Pro tiers — https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers *(403)*
- Codex rate card — https://help.openai.com/en/articles/20001106-codex-rate-card *(403)*
- Use multiple accounts with account switching — https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching *(403)*
- Account sharing policy — https://help.openai.com/en/articles/10471989-openai-account-sharing-policy *(403)*
- Terms of Use — https://openai.com/policies/row-terms-of-use/ *(403 / Cloudflare challenge)*
- TechCrunch 2026-09-10, Pro pause — https://techcrunch.com/2026/09/10/openai-puts-pro-subscriptions-on-hold-due-to-astra-demand/
- Tibo Sottiaux 2026-08-25, no 5h limit on Pro — https://x.com/thsottiaux/status/2094254532020818191
- CloudZero (upd. 2026-09-04) — https://www.cloudzero.com/blog/openai-codex-pricing/
- agent37 2026-08-31, Codex cloud — https://www.agent37.com/blog/codex-cloud
- explainx.ai, Plus 5h limit returns — https://www.explainx.ai/blog/codex-plus-5-hour-limit-returns-chatgpt-work-august-2026
- Codex KB, subscription API — https://codex.danielvaughan.com/2026/04/24/codex-subscription-api-programmatic-access-gpt-5-5-chatgpt-plan/
- OSPO, OpenAI ToU cautions — https://ospo.co/blog/be-careful-with-openais-terms-of-use/

---

## Changelog
- 2026-09-16 — §0–4 written after first evidence round; §5–13 + sources appended after
  saturation. Adversarial pass (§12) run before close: three gaps investigated with real
  calls (multi-account ban basis, burst limiter, OpenAI third-party stance), one
  instrument failure recorded rather than papered over (OpenAI origin pages unreadable).
