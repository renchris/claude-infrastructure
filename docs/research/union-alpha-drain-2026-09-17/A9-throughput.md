# A9 — Would the free tier physically sustain a 24/7 agentic pipeline, and is there a gateway win decoupled from union-alpha?

Measured 2026-09-16/17. Read-only: nothing was configured, no credential was created or used, no request was sent to OpenRouter or Cloudflare with a key.

---

## VERDICT

| | |
|---|---|
| **Measured demand, one drain link** | 130 requests · 29.0M prompt tokens · 75K output · 1.45 h (medians, n=40 infra-lane links) |
| **Measured demand, 24/7 continuous** | **1,078–1,687 requests/day · 255–306M prompt tokens/day · 0.59–1.19M output tokens/day · 7.4–8.3 links/day** |
| **Published supply, OpenRouter free** | 20 RPM always · **50 requests/day** unfunded · 1,000/day once ≥$10 credits purchased all-time |
| **Ratio, this box's actual tier** | 50 ÷ 45–70 req/h ⇒ **exhausted in 43–67 minutes**; **0.38 links/day — it cannot complete a single link** |
| **Ratio, if $10 is spent** | 1,000 ÷ 45–70 req/h ⇒ **14.3–22.2 h/day**; **7.7 links/day** |
| **Independent hard stop** | **20.4% of measured requests (30.7% infra-lane) exceed union-alpha's 262,144-token ceiling.** p90 = 295,065; max = 440,149 |
| **Prompt caching on the free tier** | **NONE.** `supports_implicit_caching: false`; no `input_cache_read`/`input_cache_write` price keys; no `cache_control` parameter — and this is true of **all 24** zero-priced models in OpenRouter's catalogue, not just union-alpha |
| **Free-tier verdict** | **TOY at the tier we are on. BURST (≈14–22 h/day) only if the operator authorizes a $10 credit purchase — which `spend.usage_credits_authorized: false` forbids. NOT A SUBSTRATE in either case: the preview is ~1 week old and the stealth EULA lets it vanish "with or without notice."** |
| **Gateway verdict, decoupled from union-alpha** | **YES it can front first-party OAuth traffic — Anthropic documents it. NO it is not worth it as a fleet default.** It adds exactly one thing this box lacks (per-subagent parent-child cost attribution) against three *silent* degradation modes, two of which cost ~10× input on every session with no error raised. Correct shape if wanted: one opt-in lane, never `ANTHROPIC_BASE_URL` in `~/.zshrc`. |
| **The finding that outranks all of the above** | The funded free-tier ceiling (7.7 links/day) sits **within 5% of the lane's own historical throughput (7.35 links/day)**. Capacity was never the constraint. `next3` is on track to strand ~47pp of 93 this week and 3.19 account-weeks expired unused in the last 30 days. **Free capacity solves a problem this box does not have.** |

---

## PART 1 — DEMAND SIDE (measured locally)

### Corpus and method

150 drain-lane sessions, the complete recorded population of both lanes' worktree project dirs across all five config roots:

- `-Users-chrisren-Development--worktrees-drain-lane-infra` — 40 sessions, 2026-09-04T12:36Z → 2026-09-09T23:54Z
- `-Users-chrisren-Development--worktrees-wt-drain-lane-reso` — 110 sessions, 2026-09-07 → 2026-09-08

Deduped on `message.id` before summing. This is load-bearing: Claude Code writes one streaming assistant message once per content block, same `message.id`, same complete `usage` object on every copy. Measured in the 7-day fleet corpus: **115,453 of 195,853 records (58.9%) are repeats; summing lines over-counts by 2.47×** (`cc-quota-price --census`, which encodes this as a RED-provable invariant).

### Per link — the `--recycle` chain link, infra lane

| statistic | median | mean |
|---|---:|---:|
| model requests | **130** | 151 |
| fresh `input_tokens` | 261 | 302 |
| `cache_creation_input_tokens` | 285,574 | 393,946 |
| `cache_read_input_tokens` | **28,716,637** | 35,411,905 |
| `output_tokens` | 75,356 | 82,167 |
| wall clock (first→last transcript ts) | **1.45 h** | 3.37 h |
| total prompt tokens (in + cc + cr) | **29.0M** | 35.8M |

Lane totals: 6,049 requests · 12,084 fresh input · 15,757,860 cache_creation · **1,416,476,200 cache_read** · 3,286,698 output · 134.8 h summed wall.

Reso lane (110 sessions, many short restarts): 5,830 requests · 23,274,704 cache_creation · 1,032,022,602 cache_read · 4,121,905 output · 82.9 h.

### Per hour, and the 24 h extrapolation

| | infra lane | reso lane |
|---|---:|---:|
| requests / active hour | 44.9 | 70.3 |
| prompt tokens / active hour | 10,626,899 | 12,732,013 |
| output tokens / active hour | 24,386 | 49,730 |
| **⇒ requests / 24 h** | **1,078** | **1,687** |
| **⇒ prompt tokens / 24 h** | **255M** | **306M** |
| **⇒ output tokens / 24 h** | **585K** | **1.19M** |

**Two independent denominators agree, which is the reason to trust this.** The infra chain's calendar span is 2026-09-04T12:36Z → 2026-09-09T23:54Z = 131 h. 1.432 B prompt tokens over 131 *calendar* hours = **10.9M/calendar-hour**, within 3% of the 10.63M/active-hour figure. The lane genuinely ran near-continuously, so the active-wall rate is not an artifact of ignoring idle time. Likewise 40 links ÷ 5.44 days = **7.35 links/day observed**, against 7.4 extrapolated.

### The unit that actually matters: requests per row closed

The drain productivity audit measures **5.5 rows closed per drain session** (`docs/research/drain-pipeline-productivity-2026-09-16.md` §5, against 1.5 for an ordinary session). At 130 requests/link that is **≈24 model requests per backlog row closed**. This is the fair denominator for any "could a leaner harness do it?" argument, and it is used in Part 2.

### Coverage and error bars, stated honestly

- **Population, not sample.** All 150 sessions in both lanes' project dirs were read. No sampling error.
- **Wall clock includes idle tails.** Three infra sessions span 10–26 h (d6b63f87 = 25.75 h, 7a4524e7 = 17.44 h, e7693813 = 10.49 h). Per-hour rates are therefore **conservative**; peak burst is higher. The median link's 1.45 h / 130 requests = 40 s per request is the working figure.
- **The token→quota converter is currently ABSTAINING.** `cc-quota-price --since 7d` and `--since 30d --bucket-h 12` both return `ABSTAIN — insufficient movement: 0 bucket(s) with a positive Δweekly_pct, below the floor of 12`. `weekly_pct` is an integer percent and the window is too quiet to fit a price. **Consequence: no statement below about what a drain link costs *in quota* can be published from this box's own fit today.** Any quota-cost claim here is list-price order-of-magnitude, explicitly labelled.
- **Harness-specific.** These numbers describe Claude Code / Opus 5 @ high effort with the full local tool surface. A different harness would move them; §2 bounds that.
- `~/.claude/logs/handoffs.jsonl` was checked and is **not usable for this**: it rotates ~4 days (oldest row 2026-09-14) and contains admission-gate verdicts, not per-link token accounting. `grep -c drain` = 0.

---

## PART 2 — SUPPLY SIDE

### What union-alpha actually is (live from `GET /api/v1/models`, 2026-09-17)

```json
{"id": "stealth/union-alpha", "name": "Union Alpha",
 "context_length": 262144,
 "pricing": {"prompt": "0", "completion": "0"},
 "top_provider": {"context_length": 262144, "max_completion_tokens": 131072, "is_moderated": false},
 "per_request_limits": null,
 "supported_parameters": ["max_tokens","response_format","temperature","tool_choice","tools","top_p"],
 "created": 1789569723}
```

From `GET /api/v1/models/stealth/union-alpha/endpoints`: provider "Stealth", quantization unknown, `uptime_last_30m: 99.997`, `uptime_last_1d: 99.989`, `latency_last_30m: null`, `throughput_last_30m: null`, **`supports_implicit_caching: false`**, and `supports_tool_choice: {none: false, auto: true, required: false, function: false}`.

Listed 2026-09-16 (yesterday). OpenCode/OpenRouter collaboration, free preview reported at roughly one week.

### Prompt caching: absent, and absent everywhere on the free tier

Three independent confirmations, all from the live catalogue:

1. `supports_implicit_caching: false` on the union-alpha endpoint.
2. Its `pricing` dict has **no** `input_cache_read` / `input_cache_write` keys. Every caching-capable model has them — e.g. `anthropic/claude-sonnet-4.5`: `"input_cache_read": "0.0000003", "input_cache_write": "0.00000375", "input_cache_write_1h": "0.000006"`; `openai/gpt-5`: `"input_cache_read": "0.000000125"`.
3. `cache_control` is not in `supported_parameters`.

Swept across **all 24 zero-priced models** in the 444-model catalogue (union-alpha, `openrouter/free`, `z-ai/glm-5.2:free`, `thinkingmachines/inkling:free`, the nvidia/nemotron family, gemma-4, poolside laguna, cohere north-mini-code, …): **zero have cache price keys and zero accept `cache_control`.** Prompt caching is a property of the paid tier on OpenRouter, without exception.

### What caching's absence costs — and it is NOT cost

This is the part that inverts the obvious reading, so it is worth stating plainly.

**In dollars it costs nothing, because the model is free.** 29M uncached prompt tokens per link × $0 = $0. On a paid model the same link would be ~10× (Opus-5 list: 28.7M cache_read @ $1.50/MTok ≈ $43 vs 28.7M fresh input @ $15/MTok ≈ $430) — but that arithmetic simply does not reach a zero-priced endpoint.

**What it costs is latency, and that is the binding constraint.** Each of the 130 turns re-sends the full conversation prefix and the provider must prefill all of it from cold. The measured budget is **40 s per request inclusive of tool execution**, against a mean prompt of 209,549 tokens. That requires a sustained ≥5.5K tok/s prefill at 200K+ context on shared, unmetered, anonymous free capacity — and OpenRouter reports `throughput_last_30m: null` for union-alpha and for every free model sampled, so there is no published figure to check it against. Without caching, a drain link does not get more expensive; it gets **slower by however much the provider's cold prefill exceeds Anthropic's cache-read path**, and it is the only axis on which the free tier can fail quietly.

### The context ceiling kills it before any rate limit does

Per-request prompt size across the drain corpus, n = 11,871 deduped requests:

| | tokens |
|---|---:|
| mean | 209,549 |
| p50 | 199,155 |
| p75 | 251,825 |
| **p90** | **295,065** |
| p95 | 338,382 |
| p99 | 412,027 |
| max | 440,149 |

- **over 262,144 (union-alpha's ceiling): 2,425 / 11,871 = 20.4%** — infra lane alone **30.7%**
- over 200,000: 49.7%
- over 131,072: 90.8%

So roughly **one turn in five is a hard `400` from the model before any quota is touched**, and the p90 turn does not fit at all. Re-shaping the work to fit 262K means compacting ~3× more often, and each compaction is itself requests.

### Published caps, and what actually applies

`openrouter.ai/docs/api-reference/limits`, verbatim: free model variants **"with an ID ending in `:free`"** get **20 RPM** always, **50 requests/day** below 10 credits purchased all-time, **1,000 requests/day** at or above. Check remaining quota via `GET /api/v1/key` → `free_model_daily_requests`. Negative balance ⇒ `402` even on free models.

🚨 **`stealth/union-alpha` does not end in `:free`, so its cap is UNVERIFIED.** It is either exempt from the documented rule or governed by an unpublished stealth cap. I could not settle this without a key, and did not create one. Both readings are carried below. The settling instrument, for whoever does hold a key: one request, then read `X-RateLimit-*` response headers and `GET /api/v1/key`.

**A second supply ceiling exists and is unquantifiable:** each free model is served by a provider with its own capacity, and saturation returns `429` regardless of your own usage. There is no SLA and no published capacity figure for Union Alpha. (The prior stealth model, Ox Alpha, had a "100 trillion tokens/day" capacity claim from OpenCode; **no equivalent claim accompanies Union Alpha.**)

### The ratio

| cap | our demand | time to exhaust | links/day | rows/day (@24 req/row) |
|---|---|---|---:|---:|
| **50 RPD** — the tier this box is on | 45–70 req/h | **43–67 min** | **0.38** | 2.1 |
| **1,000 RPD** — needs a $10 purchase | 45–70 req/h | **14.3–22.2 h** | **7.7** | 41.7 |
| 20 RPM | 0.75–1.2 req/min | never binding | — | — |

**We are on the unfunded tier and it is policy, not accident.** `~/.claude/accounts.json`: `spend.usage_credits_authorized: false`, with `breach_note: "flip to true only on an explicit operator decision, and say why in the commit"`. No OpenRouter or Cloudflare credential exists anywhere on this box — `env` grep 0 hits, `~/.zshrc` 0 hits, no `~/.config/openrouter`.

**The steel-man, stated fairly.** At the funded tier and priced per *row* rather than per *link*, 1,000 RPD ÷ 24 requests-per-row ≈ **42 rows/day**, against a drainable queue of **47 rows**. On that arithmetic the free tier could in principle clear the whole actionable backlog in ~1.1 days. That is the strongest case for it and it should not be hidden. What defeats it is not the request cap — it is the 262K ceiling (20.4% of turns), the absent caching (latency, unmeasurable in advance), the tool-calling gap (`tool_choice.required: false`, `function: false`, which Claude Code's forced-tool paths rely on), and the fact that the model may be withdrawn without notice.

### Data policy — a hard gate this box already has a rule for

- Stealth Program EULA: *"your User Content may be collected by us and shared with the Stealth Provider"*; *"Stealth Models may be removed from our Stealth Program at any time upon request of the Stealth Provider or at OpenRouter's sole discretion, with or without notice."*
- Union Alpha's own listing: *"Prompts and completions may be retained by the provider but are not used for training."* Retained, by a provider whose identity OpenRouter *"may not, in certain instances, disclose."*
- The provider is anonymous, `is_moderated: false`, quantization unknown.

`~/.claude/providers.json` already encodes the governing rule for exactly this class of decision — `_the_cost_rule`: *"ASK WHAT IT BILLS, NOT WHAT IT CAN LOG INTO… Any provider whose answer here is true, or UNKNOWN, is documented and SKIPPED — never wired, never signed up for."* union-alpha **passes** the cost gate (`bills_outside_plan: false`) and **fails** `_the_detection_rule`'s third fact — it has no headless agent mode of its own; it needs a harness. And a drain lane's context routinely contains customer material (the mission board's Insomniac Denver / The Key Collection rows, tenant subdomains, SSM parameter names), so sending drain-link context to an anonymous retaining provider is a data decision, not an engineering one.

---

## PART 3 — THE GATEWAY, DECOUPLED FROM UNION-ALPHA

### (a) Can it sit in front of first-party OAuth subscription traffic? **YES — decisively, and Anthropic documents it.**

From `code.claude.com/docs/en/llm-gateway` § Subscriptions and gateways, verbatim:

> "`ANTHROPIC_BASE_URL` is the variable that points Claude Code at the gateway. Setting only that variable, without a gateway credential, doesn't replace the subscription. Requests still route through the gateway, but a saved claude.ai login remains the active credential, so its usage limits and billing apply. Gateways that pass this traffic on to Anthropic must forward the OAuth capability in `anthropic-beta`."

Corroborated in the binary (2.1.114, `claude-code-darwin-arm64/claude`): the auth-source resolver never consults the base URL. `tV()` walks `apiKeyHelper → ANTHROPIC_AUTH_TOKEN → CLAUDE_CODE_OAUTH_TOKEN → CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR → keychain claudeAiOauth.accessToken` with no host check anywhere. `RY()` — `let H=process.env.ANTHROPIC_BASE_URL; if(!H) return !0; return ["api.anthropic.com"].includes(new URL(H).host)` — exists only to gate *features*, not auth.

From the compatibility guide, the exact requirement: `anthropic-beta` must be forwarded **verbatim**, not allowlisted — *"When the developer authenticates with a claude.ai login, which is possible when `ANTHROPIC_BASE_URL` is set without a gateway credential variable, this header also carries an OAuth capability that the upstream requires, and stripping it fails those requests with `401`."*

Cloudflare's Anthropic endpoint is shape-compatible: `https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/anthropic`, authenticating the *gateway* with `cf-aig-authorization: Bearer {CF_AIG_TOKEN}` — a **different header** from `Authorization`, so the OAuth bearer can ride through untouched.

🚨 **The trap, and it is a money trap.** Setting a gateway *credential* variable (`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, or an `apiKeyHelper`) **replaces the subscription**: *"the credential replaces the subscription login for that session, and the subscription's usage limits don't apply. That traffic is billed per token to whoever owns the credential."* Any recipe that reads "set `ANTHROPIC_AUTH_TOKEN` to your Cloudflare token" silently converts this box's four Max plans into metered API spend — which `spend.usage_credits_authorized: false` forbids outright.

🚨 **And Anthropic rules out the union-alpha combination explicitly**: *"Anthropic doesn't endorse, maintain, or audit third-party gateway products, and doesn't support routing Claude Code to non-Claude models through any gateway."*

### (b) Would it give this box observability it lacks? **Almost none — one real gap.**

What already exists, measured:

| instrument | what it holds | coverage |
|---|---|---|
| `cc-quota-price --census` | deduped 4-class token census over all 5 config roots | 3,071 files / 79,284 billed responses / 7 d |
| session transcripts | per-request `usage`, `requestId`, `model`, `effort`, `timestamp`, `cwd`, `gitBranch`, `isSidechain` | every request, full bodies |
| `account-utilization.jsonl` | `session_pct`, `weekly_pct`, `fable_pct`, resets, `auth`, `credits_used` per account, ~6 min cadence | 8.5 MB; 5,374 samples / 7 d |
| `auth-timeseries.jsonl` | keychain state, token expiry, scopes per account | 7.8 MB |
| `cc-ctx-audit` | recycle-vs-wall outcomes, with an explicit null-window abstain | retrospective, whole history |
| `/tmp/cc-telemetry/<sid>.json` | the context-window denominator | 52 files (ephemeral, wiped on reboot) |
| transcripts, error tokens | 7 d: 429 ×233 · 500 ×65 · 529 ×17 · `rate_limit_error` ×21 · `overloaded_error` ×3 · `Prompt is too long` ×21 | surfaced errors only |

**The one genuine gap, and it is structural.** A subagent's transcript is a first-class top-level `<sid>.jsonl` carrying `isSidechain` — and **no pointer to its parent whatsoever**. Measured on this very subagent's own transcript: `grep -c 7d4e2b5d` (the lead's session id) = **0**; the 198 records expose no `parentSessionId`/`agentId`/`subagent_type` key; and no store under `~/.claude/logs/` maps subagent sid → parent sid (`pane-spawns.jsonl` records pane spawns, not in-process subagents). So this box can count a subagent's tokens and **cannot attribute them to the wave that spawned them.**

A gateway gets exactly that, on every request, as headers — no body parsing:

- `x-claude-code-session-id`
- `x-claude-code-agent-id` — *"present only on requests from an agent Claude Code spawned inside the session. Use it with the session ID to attribute cost to parallel agents."*
- `x-claude-code-parent-agent-id` — *"Identifier of the agent that spawned the requesting agent, present only for nested agents."*

That is the whole addition. Cloudflare's log fields (prompt, response, provider, timestamp, status, token counts, cost, duration, user agent) are otherwise a strict subset of what the transcripts already hold — this box has the **bodies**, which the gateway summarises. Retry tracking and TTFT are not in Cloudflare's documented log schema.

**Two things a gateway can never see, by construction:** the fast-mode availability check and the WebFetch domain-safety check call `api.anthropic.com` **directly**, not via `ANTHROPIC_BASE_URL`. Gateway observability is incomplete on day one.

**And the free log tier does not fit this box.** Cloudflare free: **100,000 logs per *account*, aggregate across all gateways** (paid: 10M per gateway); *"If your storage limit is reached, new logs will stop being saved"* unless Automatic Log Deletion is enabled. At this box's measured **79,284 billed responses/week**, the free log store fills in **≈8.8 days** — then it either goes silent or becomes an 8.8-day rolling buffer. `cc-quota-price --census` already covers the whole recorded history for free.

### (c) Risks it introduces

Four are documented silent-degradation modes; two of them cost ~10× input on every session with **no error raised**.

1. **Prompt caching breaks silently.** Compatibility guide: *"Forward `cache_control` unchanged wherever it appears, and don't convert block-form `system` or message content to plain strings."* Symptom when broken: *"**No error**: the conversation bills as uncached input on every turn, visible as high `input_tokens` with little or no cache activity in `usage`."* On the measured drain lane that is 28.7M cache_read per link becoming 28.7M fresh input — on a box whose own price converter currently **abstains** and therefore could not detect the regression from its quota series.
2. **The attribution block defeats caching the same way.** `api.anthropic.com` strips Claude Code's system-prompt attribution block only when it arrives unchanged as the *first* `system` array entry; *"prepending another system block, reordering the array, or converting it to a single string defeats the strip, and the block then reaches the model and the prompt cache key."* Same silent 10×, different cause.
3. **Stream aborts.** *"Claude Code counts every byte your gateway relays, including SSE `ping` events and comment lines, and aborts a stream that goes silent for 300 seconds by default."* A buffering or ping-stripping gateway kills streams during long thinking pauses — the exact failure mode a 24/7 unattended fleet cannot diagnose from a transcript.
4. **ToolSearch turns off.** Measured in the 2.1.114 binary, verbatim: `[ToolSearch:optimistic] disabled: ANTHROPIC_BASE_URL=${...} is not a first-party Anthropic host. Set ENABLE_TOOL_SEARCH=true (or auto / auto:N) if your proxy forwards tool_reference blocks.` Deferred-tool loading — which this session is using right now — is off by default behind any gateway.
5. **A hop in front of 100% of traffic.** Every request from a 24/7 autonomous fleet, through infrastructure this box has never operated, with zero existing credential. Cloudflare AI Gateway has no SLA obligation to this box's uptime needs.
6. **Anthropic watermarks non-first-party base URLs, and the client does it.** `bA9()` in the binary renders `Today's date is <date>` choosing among four apostrophe codepoints — `'` U+0027, `'` U+2019, `ʼ` U+02BC, `ʹ` U+02B9 — keyed on `K71()`, which is null on a first-party host and otherwise reports `{known: <host is a known lab domain>, labKw: <host contains a lab keyword>, cnTZ: <Asia/Shanghai|Asia/Urumqi>}`. Analytics also carries `apiBaseUrlHost` whenever the host is not `api.anthropic.com`. Routing through a gateway is detected and marked by the client itself. This is a fact to know before pointing the fleet at a proxy, not a prohibition.

---

## PART 4 — VERDICT AND THE NUMBER OF LINKS/DAY

**Free tier as a 24/7 substrate: a toy at the tier this box is on; a burst substrate at best if $10 is authorized; not a substrate at all in about a week.**

- **0.38 links/day** at 50 RPD — it cannot complete one link. 43–67 minutes of chain, then dead for the day.
- **7.7 links/day** at 1,000 RPD (14.3–22.2 h of a 24 h day), gated behind a credit purchase that `spend.usage_credits_authorized: false` explicitly reserves to the operator.
- Both figures are ceilings that **20.4% of measured turns cannot reach anyway**, because they exceed 262,144 tokens.
- Both are on a model listed yesterday, withdrawable "with or without notice," with a ~1-week free window and no published capacity or throughput figure.

**The decisive argument is on the demand side, not the supply side.** The funded free-tier ceiling (7.7 links/day) is within 5% of what the lane actually achieved (7.35 links/day). Capacity was never what stopped it. What stopped it, per `drain-pipeline-productivity-2026-09-16.md`: the local lane **has no scheduler at all**; `cc-dispatch` selects `status=="open"` only, so **296 of 343 live rows (86%) are structurally invisible** and the drainable queue is **47 rows, not 342**; and 47.2% of closures were mechanically not-delivered. Meanwhile **3.19 account-weeks of paid weekly quota expired unused in 30 days**, and the live readout below shows `next3` on track to strand **~47pp of 93** this week. Adding free capacity to a pipeline that is starving for eligible work and stranding paid capacity buys nothing.

**Gateway, decoupled: a real but narrow win, not worth a fleet-wide default.** It adds per-subagent parent-child cost attribution, which the transcripts structurally cannot produce. Against that: three documented silent-degradation modes (two costing ~10× input, invisible to a quota series that currently abstains), ToolSearch off by default, a free log tier that fills in 8.8 days, and a hop in front of every request on an unattended box. If it is wanted, the correct shape is **one opt-in lane** — `ANTHROPIC_BASE_URL` scoped to a single drain worktree's sessions, with the `anthropic-beta` OAuth passthrough verified by a green session before anything else moves — and **never** an export in `~/.zshrc`.

**The one free-tier use that is genuinely net-positive.** Union-alpha at 50 requests/day is well shaped for bounded, small-context, single-shot triage — specifically the **296-row blocked pile**, of which ~28% (honest band 40–135 rows) is measured to be *agent work wearing a park*. One row per request, ~2K of context each: ~105 requests ≈ 2 days at the unfunded cap, no caching needed, no 262K ceiling problem, no 24/7 anything, no credit purchase. **Constraint:** admissible only on rows carrying no customer content, because the provider is anonymous and retains prompts.

---

## Relayed verbatim — `claude-accounts --readout`, 2026-09-17T04:39Z

Reproduced in full because it is a rendered artifact; summarising it would re-create the second renderer the tool exists to delete.

```
| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| next | 0 | 0% | — | 94% | 7% | Sat 22:59 (in 2d 23h) | Tue Oct 13 01:19 (in 26d 1h) |
| next4 ← you | 14 | 17% | Thu 02:00 (in 2.3h) | 43% | 13% | Sun 04:00 (in 3d 4h) | Thu Oct 08 05:42 (in 21d 5h) |
| **next3** ➤ | 2 | 2% | Thu 01:00 (in 1.3h) | 7% | 0% | Tue 07:00 (in 5d 7h) | Thu Oct 01 14:39 (in 14d 14h) |
| next2 | 1 | 66% | Thu 00:40 (in 57m) | 100% | 76% | Sat 06:00 (in 2d 6h) | Mon 03:07 (in 4d 3h) |
- ○ `next2` — weekly **LIMITED** (100%)

➤ desk (bare `claude`) → **next3** — earliest weekly reset among 5h-safe accounts · weekly ↻ 5d 7h · 5h 2% · safe set
➤ general → **next3** · ➤ fable → **next3**
weekly drain — pp that DIE at reset (K=0.203 live · nowcast at the last 48h of pace):
  next3 strand ~47pp of 93 · p76 of its own 24h burns · start by T−29h (99h slack) · 5d left
  next no strand — on pace to fill the window · 2d left
  next4 no strand — on pace to fill the window · 3d left
  next2 no strand — on pace to fill the window · 2d left
Fable window: **permanent** (no expiry).

**Agent backends beyond Claude** — registry `~/.claude/providers.json`

| backend | routable | version | auth | plan | bills outside it? | model pinned |
|---|---|---|---|---|---|---|
| Codex CLI | ✅ | codex-cli 0.147.0 | ok | ChatGPT Plus | no | gpt-5.6-sol @ xhigh ✓proven |
| Pi · Codex backend | ✅ | 0.84.1 | ok | ChatGPT Plus | no | gpt-5.6-sol ✓proven |
| Pi · Claude backend | ⊘ skipped | 0.84.1 | credentials_not_configured | Claude Pro/Max (auth works, usage does NOT draw on the plan) | 🚨 **YES** | — |
| Antigravity | ⊘ skipped | 1.107.0 | ok | UNKNOWN | UNKNOWN | — |
| Gemini CLI | ⊘ skipped | 0.29.5 | ok | UNKNOWN | UNKNOWN | gemini-3-pro-preview ⚠unproven |
| Grok CLI | ⊘ skipped | not installed | — | UNKNOWN | 🚨 **YES** | — |
- ⊘ `pi-claude` — COST GATE FAIL — bills per token outside the Max plan
- ⊘ `antigravity` — NOT AN AGENT BACKEND — the binary is the VS Code editor launcher, no non-interactive mode
- ⊘ `gemini` — DEFERRED — plan tier UNKNOWN, so the cost gate cannot clear it
- ⊘ `grok` — COST GATE FAIL — API-key-only, and we hold no xAI plan

➤ non-Claude backends ready now: **2 of 2 routable** (6 known)
- 🚨 rows marked **YES** bill OUTSIDE a plan we hold — not wired, by policy (`accounts.json spend.usage_credits_authorized=false`)
```

Three lines of reading: `next2` is weekly-LIMITED at 100% and `next` at 94%, so the fleet is not uniformly idle — but `next3` sits at 7% with a 5-day window and is nowcast to **strand ~47pp**, which is the capacity a free tier would be duplicating. The provider registry is the SSOT a union-alpha row would join, and its `_the_cost_rule` is the gate that decides it. Nothing in this readout was changed by this research; it is a read.

---

## Alternatives considered and ruled out

| considered | ruled out because |
|---|---|
| Another zero-priced OpenRouter model with caching | None exists. All 24 zero-priced models lack cache price keys and `cache_control`. |
| `thinkingmachines/inkling:free` (1,048,576 ctx) to beat the 262K ceiling | Solves context, not caching, not the request cap, and the RPD cap binds first at 50/day. |
| Cloudflare AI Gateway caching to substitute for prompt caching | Cache key is SHA-256 of provider + endpoint + model + auth header + **full body**; docs: *"Any difference in the body — including messages, tools, or model parameters — will result in a separate cache entry."* An agentic loop's body changes every turn by construction. Hit rate ≈ 0. Semantic caching is listed as future work. |
| Cloudflare Unified Billing / BYOK to front Anthropic | Sets a gateway credential ⇒ **replaces the subscription and bills per token** (5% fee on credits purchased). Forbidden by `spend.usage_credits_authorized: false`. Also rate-limited to 200 req/60 s per gateway. |
| `handoffs.jsonl` as the demand instrument | Rotates ~4 days; holds admission-gate verdicts, not token accounting; `grep -c drain` = 0. |
| `cc-quota-price` fit to price a drain link in quota | **ABSTAINS** on both 7 d and 30 d — 0 buckets with positive Δ`weekly_pct` against a floor of 12. Reported as abstain, not imputed. |
| Measuring latency impact directly | Not possible read-only: OpenRouter reports `throughput_last_30m: null` and `latency_last_30m: null` for union-alpha and every free model sampled, and I did not send a request. Stated as an unmeasured risk, not a number. |

## Named uncertainties

1. **Whether the 50/1,000 RPD cap applies to `stealth/union-alpha` at all.** The documented rule matches ids ending in `:free`; this one does not. Both readings carried. Settling instrument: one request with a key, then `X-RateLimit-*` headers + `GET /api/v1/key` → `free_model_daily_requests`.
2. **Union-alpha's actual prefill throughput at 200K+ context.** Unpublished, `null` in OpenRouter's own stats, and unmeasurable read-only. This is the single largest unknown in the "burst substrate" case.
3. **How much a leaner harness would reduce the 130 req/link figure.** Bounded above by the requests-per-row unit (~24), which is harness-independent as a *closure* rate but not as a *request* rate.
4. **Whether Cloudflare AI Gateway forwards `cache_control`, the `system` array shape, and SSE pings correctly for Claude Code.** Cloudflare does not document it; Anthropic documents that getting it wrong fails **silently**. Would need a measured A/B (one gateway session vs one direct session, comparing `cache_read_input_tokens` in `usage`) before any lane is pointed at it.

## Sources

- [OpenRouter — API rate limits](https://openrouter.ai/docs/api-reference/limits)
- [OpenRouter — Union Alpha](https://openrouter.ai/stealth/union-alpha) · [Stealth program](https://openrouter.ai/stealth) · [Stealth Program EULA](https://openrouter.ai/terms/stealth)
- [OpenRouter — Prompt caching](https://openrouter.ai/docs/features/prompt-caching)
- live: `GET https://openrouter.ai/api/v1/models` and `.../models/stealth/union-alpha/endpoints`
- [Cloudflare AI Gateway](https://developers.cloudflare.com/ai-gateway/) · [Caching](https://developers.cloudflare.com/ai-gateway/configuration/caching/) · [Limits](https://developers.cloudflare.com/ai-gateway/reference/limits/) · [Pricing](https://developers.cloudflare.com/ai-gateway/reference/pricing/) · [Logging](https://developers.cloudflare.com/ai-gateway/observability/logging/) · [Anthropic provider](https://developers.cloudflare.com/ai-gateway/usage/providers/anthropic/)
- [Claude Code — Other LLM gateways](https://code.claude.com/docs/en/llm-gateway) · [Gateway compatibility guide](https://code.claude.com/docs/en/llm-gateway-protocol) · [Connect to a gateway](https://code.claude.com/docs/en/llm-gateway-connect)
- local: `~/Development/claude-infrastructure/docs/research/drain-pipeline-productivity-2026-09-16.md` · `~/.claude/bin/cc-quota-price` · `~/.claude/accounts.json` · `~/.claude/providers.json` · `~/.claude-versions/2.1.114/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude` · 150 drain-lane session transcripts across 5 config roots
