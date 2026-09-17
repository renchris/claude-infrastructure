# A2 — Cloudflare "stealth/union-alpha" + AI Gateway: ground truth

Research date **2026-09-16**. Stance: default-to-refute. Documented fact vs. vendor-blog vs. community claim is labelled on every line.
No live API probe was possible — **no Cloudflare credential exists on this machine** (`env | grep -i cloudflare` empty, no `wrangler`, no `~/.wrangler`). Everything below is docs + live vendor APIs, not an executed request.

---

## VERDICT (5 lines)

1. **FREE?** — Effectively yes on Cloudflare, but *Cloudflare never says so*. CF publishes **no price at all** for `stealth/union-alpha` (its model page has no Model Info table — no pricing row, no pricing link), while every generated example on that page returns `"cost": 0` with `"keySource": "Unified"`. It is **not** a Workers AI model (absent from the Workers AI catalog and the Neuron price table), so the 10,000-Neuron/day free allowance is irrelevant; it bills as a **third-party model via Unified Billing**, whose documented prerequisite is *"Ensure your Cloudflare account has sufficient credits loaded before calling third-party models."*
2. **HOW LONG?** — **Cloudflare states no end date, no "preview", no "week".** The one-week framing is **OpenCode's**, about **OpenCode Zen**, not Cloudflare: *"Union Alpha Free is a stealth model available on OpenCode for a limited time."* A hard `2026-09-23` is a **community claim only** (a GitHub issue reading the 2026-09-16 announcement as "free for the next week"). Treat withdrawal as possible **without notice**.
3. **RATE CEILING for 24/7** — **200 requests / 60 seconds per gateway**, `429` on breach (the Unified Billing limit; BYOK-exempt, and you *cannot* BYOK a stealth provider). No documented daily cap, no documented concurrency cap, no documented token-per-minute cap. Free-plan side-limits that bite a 24/7 drain: **100,000 logs total across all gateways**, 10 gateways/account, 500 logs/s.
4. **DATA SHARED?** — **Yes, and this is the disqualifier.** OpenRouter's own page: *"developed and operated by a third-party provider who has chosen to remain anonymous during this preview … **Prompts and completions may be retained by the provider** but are not used for training."* Cloudflare maintains a **"Zero data retention" badge on 90 of 226 catalogue models and deliberately withholds it from `union-alpha`**; CF's ZDR switch is Unified-Billing-only and *"currently supported for OpenAI [and] Anthropic"* — so a stealth request **falls back to non-ZDR**. Separately, **AI Gateway logs full prompt+response bodies by default** (off-able).
5. **API SHAPE** — **OpenAI-compatible, Cloudflare-native routing.** `POST https://api.cloudflare.com/client/v4/accounts/$ACCT/ai/v1/chat/completions`, `Authorization: Bearer $CLOUDFLARE_API_TOKEN`, body `{"model":"stealth/union-alpha", "messages":[…]}`. Declares `tools`/`tool_choice`/`response_format`/`stream`/`reasoning_effort`. **Not** reachable as an AI-Gateway provider-native endpoint (`stealth` is not in the provider list).

**Recommendation in one line:** the transport works and is genuinely $0, but routing a 24/7 automated backlog drain — which by construction feeds repo contents, file paths and internal reasoning — into an **unidentified lab that reserves the right to retain prompts**, on an offer with **no contractual end date and no SLA**, is the wrong trade. Use it for throwaway/synthetic workloads only.

---

## 1. Exactly what is free, under which product, and is a paid plan required

| Claim | Status | Evidence |
|---|---|---|
| `union-alpha` is a **Workers AI** model | **REFUTED** | Absent from `https://developers.cloudflare.com/workers-ai/models/` (grep for `union-alpha` and `stealth` → 0 hits) and absent from every row of the Workers AI Neuron price table (`workers-ai/platform/pricing/`, which lists only `@cf/…` ids). Its id has no `@cf/` prefix. |
| It is a **third-party model billed via Unified Billing** | **CONFIRMED** | `ai-gateway/usage/rest-api/`: *"Third-party models are billed via Unified Billing."* + *"Third-party models use the `author/model` format"*. The doc page's own response payload carries `"gatewayMetadata": {"keySource": "Unified"}` — i.e. Cloudflare-managed credentials. |
| Cloudflare publishes a **price** for it | **REFUTED** | Peer third-party page `ai/models/openai/gpt-4.1-mini/` carries a Model Info table with `Context Window \| 1,047,576 tokens`, `Zero data retention \| Yes`, `Pricing \| View pricing in the Cloudflare dashboard ↗`. The `stealth/union-alpha` page has **no Model Info table at all** — grep for `dash.cloudflare.com`, `Context Window`, `Zero data retention` on `ai/models/stealth/union-alpha/index.md` returns nothing. The catalogue's `- Pricing listed` badge appears on **212 of 226** models and is contradicted by the page itself. |
| Cost is **0** | **SUPPORTED, by example not by policy** | All five generated examples on `ai/models/stealth/union-alpha/` end `"usage": { … "cost": 0 }`. Corroborated upstream: OpenRouter's live API returns `"pricing": {"prompt":"0","completion":"0"}` (`GET https://openrouter.ai/api/v1/models`), and its page FAQ says *"The pricing shown on this page for Union Alpha is zero, so you are not charged for prompt or completion tokens."* OpenCode Zen's price table lists `Union Alpha Free — Free / Free / Free`. |
| A **paid Workers plan** is required | **NO — but a funded Cloudflare account effectively is** | The "requires a paid billing method" list in `workers-ai/platform/pricing/` names only `@cf/` frontier models and does not include stealth. However `ai-gateway/usage/rest-api/` states: *"Ensure your Cloudflare account has [sufficient credits loaded] before calling third-party models or using prepaid credits for Workers AI."* Loading credits requires a payment method, and carries *"A 5% fee … applied to all credits purchased through Unified Billing."* **Whether a $0 model is actually gated on a non-zero balance is UNDOCUMENTED** — see UNKNOWNS. |
| The 10,000 Neurons/day free allowance applies | **REFUTED** | That allowance is scoped to Workers AI (`workers-ai/platform/pricing/`: *"Our free allocation allows anyone to use a total of 10,000 Neurons per day at no charge"*), and union-alpha is not a Workers AI model. Neurons are not the meter here. |

**AI Gateway itself is free:** *"AI Gateway's core features available today are offered for free … Core features include: dashboard analytics, caching, and rate limiting."* (`ai-gateway/reference/pricing/`, updated 2026-05-19).

## 2. Binding limits for 24/7 use

| Limit | Value | Source |
|---|---|---|
| **Requests/min (the binding one)** | **200 requests per 60 seconds per gateway**, `429` on breach | `ai-gateway/reference/limits/`: *"Unified Billing request rate \| 200 requests per 60 seconds per gateway⁴"*; footnote 4: *"This rate limit applies to requests that use Cloudflare-managed credentials through Unified Billing. When the limit is exceeded, AI Gateway returns a `429` error. This limit does not apply to requests that use your own provider keys through … (BYOK)."* **The BYOK escape hatch is unavailable**: `stealth` is not in `ai-gateway/usage/providers/` (24 providers listed; no `stealth`), so there is no key to bring. |
| Workers AI text-gen 300 rpm | **Does not apply** | `workers-ai/platform/limits/` §Text Generation is a Workers AI limit; union-alpha is not a Workers AI model. Its frontier-model table (20 rpm standard / 50 rpm with prepaid credits) names only `@cf/moonshotai/kimi-k2.6`, `@cf/moonshotai/kimi-k2.7-code`, `@cf/zai-org/glm-5.2`. |
| Daily cap | **None documented** for third-party models. (Workers AI's *"All limits reset daily at 00:00 UTC"* is Neuron-scoped.) |
| Concurrency | **UNDOCUMENTED** — no concurrency figure anywhere in `ai-gateway/reference/limits/` or `workers-ai/platform/limits/`. |
| Max input tokens (Cloudflare) | **UNDOCUMENTED.** No context-window badge in the catalogue entry, no Model Info table on the page. (By contrast 29 catalogue models carry `- Context: 1M tokens`, 5 carry `- Context: 262.1K tokens`.) |
| Max input / output (OpenRouter route) | `context_length: 262144`, `max_completion_tokens: 131072` — live `GET https://openrouter.ai/api/v1/models/stealth/union-alpha/endpoints`. **Do not assume Cloudflare inherits these**; it is the same upstream but CF documents nothing. |
| Log-storage ceilings that bite a 24/7 drain | Workers Free: **100,000 logs total across ALL gateways**; Workers Paid: 10M per gateway. `Log storage rate limit 500 logs/s`; `Log size stored 10 MB per log` (*"Logs larger than 10 MB will not be stored"*); 10 gateways/account free, 20 paid. All from `ai-gateway/reference/limits/`. |
| Documented throttling behaviour | `429 Too Many Requests` and *"your request will not be processed"* (`ai-gateway/features/rate-limiting/`). Spend limits also emit `429` and are *"eventually consistent … a burst of concurrent requests can briefly exceed the limit before enforcement catches up"* (`ai-gateway/features/spend-limits/`). |

**Upstream throughput is currently healthy but unguaranteed:** OpenRouter's endpoint record shows `uptime_last_1d: 99.989%`, `uptime_last_30m: 99.997%`, `latency_last_30m: null`, `throughput_last_30m: null` (no published perf figures). There is **no SLA of any kind** for a stealth model on any route.

## 3. Capability surface + minimal working curl

**Shape: OpenAI Chat Completions, served by Cloudflare's own REST API.** Not Anthropic-native on this route, not an OpenRouter passthrough you configure yourself.

Verbatim from `https://developers.cloudflare.com/ai/models/stealth/union-alpha/`:

```bash
curl https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/ai/v1/chat/completions \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{
  "model": "stealth/union-alpha",
  "messages": [
    { "content": "What is the capital of France? Answer in one word.", "role": "user" }
  ],
  "max_tokens": 16
}'
```

Workers binding form, same page: `await env.AI.run('stealth/union-alpha', { messages: […], max_tokens: 16 })`.

**Auth:** a Cloudflare API token with **Account → Workers AI → Read**. `ai-gateway/usage/rest-api/`: *"All `/accounts/{account_id}/ai/*` endpoints require the Workers AI permission… A token that holds only an `AI Gateway` permission returns `401` with error code `10000`."*

**Declared parameters** — from `ai/models/stealth/union-alpha/schema-input.json` (I fetched the raw schema; it is **model-specific, not a shared generic**: it differs from `openai/gpt-4.1-mini`'s, which additionally carries `input`, `instructions`, `max_output_tokens`, `reasoning`, `text`):

`messages` (roles `system|developer|user|assistant|tool`; `content` may be string **or array**), `temperature` 0–2, `max_tokens`, `max_completion_tokens`, `top_p`, `frequency_penalty`, `presence_penalty`, **`stream`**, `stream_options.include_usage`, **`tools`**, **`tool_choice`**, **`response_format`**, `modalities` (`text|audio`), `audio`, `reasoning_effort` (*"Optional reasoning control; availability and accepted values are model-dependent."*).

- **System prompts:** supported — the page's own "System Guidance" example passes `role: "system"` and it works.
- **Streaming:** declared in the Cloudflare schema (`stream`, `stream_options`). Not independently verified on this route.
- **JSON mode / structured output:** `response_format` is declared but **untyped** (`"response_format": {}` in the schema — no enum, no schema sub-object). Strength of support is unverified.
- **Tool calling — REFUTATION WORTH CARRYING:** OpenRouter's endpoint record reports `"supports_tool_choice": {"none": false, "auto": true, "required": false, "function": false}`. **Only `auto` works; you cannot force a tool call or force a named function.** For an autonomous backlog-drain loop that relies on forced structured tool output, that is a real constraint. Route-scoped caveat: this is measured on the OpenRouter endpoint, and Cloudflare declares `tool_choice` without qualification — but it is the same anonymous upstream.
- **Multimodal:** OpenRouter reports `text+image->text`. Cloudflare calls it "multimodal" in prose but its `modalities` enum is `text|audio` only. Image input **on the Cloudflare route is UNVERIFIED**.
- **Alternate shapes:** `ai-gateway/usage/rest-api/` documents four endpoints — `/ai/run`, `/ai/v1/chat/completions`, `/ai/v1/responses`, and `/ai/v1/messages` (Anthropic Messages schema, *"supports routing to Anthropic and other third-party models"*). Whether union-alpha specifically answers on `/ai/v1/messages` or `/ai/v1/responses` is **untested**. The older `gateway.ai.cloudflare.com/…/compat/chat/completions` unified endpoint is *"Deprecated for single-model calls."*

## 4. DATA POLICY — decisive

**(a) What the model's own route says.** OpenRouter's `stealth/union-alpha` page, verbatim:

> "Union Alpha is a stealth model. It is developed and operated by a third-party provider who has chosen to remain anonymous during this preview. OpenRouter routes requests to it and is not its developer, owner, or provider. **Prompts and completions may be retained by the provider** but are not used for training; all other use is governed by the Stealth Model Terms"

Sibling model "Ox Alpha" on the same page is blunter still: *"Prompts and completions **are** retained by the provider and are not used for training."*

**(b) The direct contradiction.** OpenCode Zen's docs claim the opposite: *"Its provider follows a zero-retention policy and does not use your data for model training."* Two routes to the same anonymous lab publish **incompatible retention claims**, and neither is auditable because the counterparty is undisclosed. Where two vendors disagree about a third party's behaviour, the conservative reading governs: **assume retention**.

**(c) What Cloudflare says: nothing — and its silence is structured.** Cloudflare's catalogue renders a **`Zero data retention`** badge. I counted it on **90 of 226** models (e.g. `alibaba/hh1-i2v`, `openai/gpt-4.1-mini` which also carries `Zero data retention | Yes` in its Model Info table). The `stealth/union-alpha` entry carries **only `- Third-party`**. That is not an omission pattern; it is the absence of an assertion Cloudflare makes freely elsewhere.

**(d) Cloudflare's ZDR switch does not reach this model.** `ai-gateway/features/unified-billing/` §Zero Data Retention:

> "ZDR routes Unified Billing traffic through provider endpoints that do not retain prompts or responses. Enable it with the gateway-level `zdr` setting… This setting only applies to Unified Billing requests that use Cloudflare-managed credentials. It does not apply to BYOK or other AI Gateway requests."
> "**ZDR is currently supported for: OpenAI, Anthropic.** If ZDR is enabled for a provider that does not support it, **AI Gateway falls back to the standard (non-ZDR) Unified Billing configuration.**"

`stealth` is neither. **Turning ZDR on changes nothing for union-alpha and fails open, silently.**

**(e) Cloudflare's own data terms bind Cloudflare, not the lab.** `workers-ai/platform/data-usage/` (updated 2026-04-21):

> "Cloudflare neither creates nor trains the AI models made available on Workers AI. **The models constitute Third-Party Services and may be subject to open source or other license terms that apply between you and the model provider.** Be sure to review the license terms applicable to each model (if any)."
> "Cloudflare does not make your Customer Content available to any other Cloudflare customer."
> "Cloudflare does not use your Customer Content to (1) train any AI models made available on Workers AI or (2) improve any Cloudflare or third-party services…"

Read literally: Cloudflare disclaims training, and then tells you the *provider's* terms are what govern — and **for an anonymous provider those terms cannot be read**. (Note also this page is titled for **Workers AI**; there is **no AI-Gateway-specific data-usage page at all** — `ai-gateway/llms.txt` lists 60+ pages and none covers data handling.)

**(f) What AI Gateway itself logs — full bodies, on by default.** `ai-gateway/observability/logging/`:

> "Your AI Gateway dashboard shows logs of individual requests, **including the user prompt, model response**, provider, timestamp, request status, token usage, cost, duration, and the user agent…"
> "**Logs, which include metrics as well as request and response data, are enabled by default for each gateway.** … If you are concerned about privacy or compliance and want to turn log collection off, you can go to settings and opt out of logs."

Two off-switches, both per-request-overridable:
- `cf-aig-collect-log: false` — skips the whole log entry.
- `cf-aig-collect-log-payload: false` — *"Payload storage is skipped. Metadata-only log entries are still saved."*
And: *"ZDR does not control AI Gateway logging. To disable request/response logging in AI Gateway, update the logging settings separately."*

**Net for question 4:** prompts are (i) stored in full by Cloudflare by default, defeasible; and (ii) sent to an **undisclosed lab that reserves retention rights**, **not** defeasible by any Cloudflare control.

## 5. AI Gateway as a separate question — and can it front first-party Claude on a subscription?

**What it buys for non-union traffic (all documented, all free):**

| Capability | Reality check |
|---|---|
| **Caching** | *"Caching is **disabled by default**"*, *"supported only for text and image responses, and it applies only to **identical requests**."* The cache key is SHA-256 over provider + endpoint + model + **the provider auth header** + **full request body** — *"caching is based on exact match of the entire request. Any difference in the body — including messages, tools, or model parameters — will result in a separate cache entry."* **For an agentic loop whose context grows every turn, the hit rate is ≈0.** CF's own example of a good fit is a support bot with a fixed menu. Limits: 25 MB cacheable request, 1-month TTL. |
| **Retries** | Gateway-level and per-request: `cf-aig-max-attempts` (max 5), `cf-aig-retry-delay` (max 60 s), `cf-aig-backoff` = constant/linear/exponential. Plus `cf-aig-request-timeout` in ms, measured *"on when the first part of the response comes back"* — streaming-safe. |
| **Fallback** | Genuinely useful, but the page documents it on the **deprecated Universal endpoint**; the current mechanism is **Dynamic Routing** (conditional routing + per-model timeouts/retries/budgets), invoked via the `/compat/chat/completions` endpoint, which the REST API does not cover. |
| **Spend / rate observability** | Spend limits scoped by model / provider / custom metadata, split-by-value or filter-by-value, `429` when over budget, *"eventually consistent"*. Rate limiting fixed or sliding. Analytics + GraphQL, per-request custom metadata (5 entries max), OpenTelemetry export, Logpush (Paid only: 10M req/mo, +$0.05/M). |
| **Cost** | Core features $0 on all plans. Only paid surfaces: Unified Billing's **5% credit fee**, Logpush overage, and Guardrails (billed as Workers AI `@cf/meta/llama-guard-3-8b` inference). DLP scanning is free on all plans. |

**Can it sit in front of Anthropic first-party traffic? Yes — Cloudflare ships a first-class recipe.** `ai-gateway/integrations/coding-agents/claude-code/`:

```bash
export ANTHROPIC_BASE_URL="https://gateway.ai.cloudflare.com/v1/<ACCOUNT_ID>/<GATEWAY_ID>/anthropic"
export ANTHROPIC_API_KEY="<CF_AIG_TOKEN>"
export ANTHROPIC_CUSTOM_HEADERS="cf-aig-authorization: Bearer <CF_AIG_TOKEN>"
```

> "The Anthropic endpoint exposes the same `/v1/messages` API that Claude Code expects. When AI Gateway supplies the Anthropic credentials for you — using either an Anthropic API key you store as a provider key (BYOK) or Unified Billing credits — the `ANTHROPIC_API_KEY` that Claude Code requires can be **any placeholder value**."

**Would that be compatible with OAuth / subscription (non-API-key) Claude auth? NO — not as Cloudflare documents it.** Anthropic's own `code.claude.com/docs/en/llm-gateway`, verbatim:

> "**While a gateway credential variable or `apiKeyHelper` is active, a developer's claude.ai subscription isn't used**: the credential replaces the subscription login for that session, and the subscription's usage limits don't apply. **That traffic is billed per token** to whoever owns the credential the gateway forwards…"

Cloudflare's recipe sets `ANTHROPIC_API_KEY` — a gateway credential variable. **Following Cloudflare's documented instructions therefore converts a Max/Pro subscription session into a per-token API bill.** For this operator's fleet (`accounts.json`: `spend.usage_credits_authorized=false`, zero dollar exposure, quota-bound not dollar-bound) that is a **category error**, not an optimisation: it moves work off a paid-for quota bucket and onto a live credit card.

**The one narrow path that would preserve the subscription — and why I do not recommend taking it.** Anthropic documents it explicitly:

> "`ANTHROPIC_BASE_URL` is the variable that points Claude Code at the gateway. **Setting only that variable, without a gateway credential, doesn't replace the subscription.** Requests still route through the gateway, but a saved claude.ai login remains the active credential, so its usage limits and billing apply. **Gateways that pass this traffic on to Anthropic must forward the OAuth capability in `anthropic-beta`.**"

And from `llm-gateway-protocol` §Request headers:

> "`anthropic-beta`: … Forward the header verbatim; don't allowlist individual values… **When the developer authenticates with a claude.ai login, which is possible when `ANTHROPIC_BASE_URL` is set without a gateway credential variable, this header also carries an OAuth capability that the upstream requires, and stripping it fails those requests with `401`.**"

So the theoretical config is: `ANTHROPIC_BASE_URL` → the CF Anthropic endpoint, **no** `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`, `cf-aig-authorization` supplied via `ANTHROPIC_CUSTOM_HEADERS`. Cloudflare's credential-precedence rule is even encouraging: *"**Provider key on the request** — if the request carries provider authentication (for example, an `Authorization` header), AI Gateway forwards it to the provider unchanged. BYOK and Unified Billing are not consulted."*

**Four reasons to treat this as unsupported, not clever:**
1. Cloudflare **nowhere documents** forwarding `anthropic-beta` verbatim. Strip it → `401` on every request, per Anthropic.
2. Anthropic requires gateways to forward `cache_control` unchanged or *"the conversation bills as uncached input on every turn"* — silently. Cloudflare documents no such guarantee, and CF's *own* cache key hashes the full body, which is a different (and conflicting) caching model.
3. Anthropic requires the gateway to **stream without buffering and forward SSE `ping` events**: *"Claude Code counts every byte your gateway relays… and aborts a stream that goes silent for 300 seconds."* Undocumented for CF.
4. Anthropic's blanket disclaimer: *"Anthropic doesn't endorse, maintain, or audit third-party gateway products."* Community reporting (unverified, 2026-04) further claims Anthropic blocked third-party harnesses from Max subscription limits — scope-ambiguous, but it is the direction of travel.

**Bottom line for Q5:** AI Gateway is a good, free observability/spend/retry layer for **API-key-billed** Anthropic traffic. It is **not** a way to put observability in front of subscription-authenticated Claude Code without an undocumented, unverified configuration that at minimum risks `401`s and cache-cost blowup. Explicitly: **no** for the subscription case as documented.

## 6. End date and what happens at expiry

- **Cloudflare states nothing.** No end date, no "preview", no "limited time" on `ai/models/stealth/union-alpha/`, in `ai/models/`, or in the AI Gateway / Workers AI changelogs (grep for `union`/`stealth` across both changelog pages → 0 hits). The page also carries **no "Last updated" date**, unlike sibling docs pages.
- **OpenCode states a time box, without a date:** *"Union Alpha Free is a stealth model available on OpenCode for a limited time."*
- **`2026-09-23` is a community claim only** — a GitHub issue characterising the 2026-09-16 announcement as *"free for the next week"*. **Not** stated by Cloudflare, OpenRouter, or OpenCode's docs. OpenRouter's API returns `"expiration_date": "2098-12-31"`, an obvious sentinel that carries no information.
- **What happens at expiry: UNDOCUMENTED on every route.** Cloudflare publishes no price for the model, so there is no fallback rate to fall back *to*. The realistic outcomes are (i) silent removal from the catalogue → hard errors on the model id, or (ii) a price appears and requests begin **drawing on Unified Billing credits at an unknown rate with no prior notice**. A 24/7 unattended pipeline is precisely the shape that would not notice (ii) until the bill. **Mitigation if you proceed anyway:** set an AI Gateway **spend limit** scoped `model: filter by value stealth/union-alpha` with a $0.01 budget — it blocks with `429` the moment a non-zero cost is recorded. Caveat from the docs: spend limits are *"eventually consistent"*, so a concurrency burst can overshoot.

---

## Adversarial pass — what I went looking for that would refute the optimistic read

1. **"The `cost: 0` proves it's free."** Weak on its own — it is a generated doc example, not a pricing statement, and Cloudflare's catalogue badge says `Pricing listed` while the page lists none. Corroborated only by third-party routes (OpenRouter API, OpenCode price table). **Cloudflare has made no pricing commitment for this model.**
2. **"Free means no account cost."** Partly false. The documented prerequisite for *any* third-party model call is loaded Unified Billing credits, and loading credits costs **5% on top**. Whether a $0 model bypasses the balance check is unverified.
3. **"The 300 rpm Workers AI text-gen limit applies."** Refuted — wrong product surface. The real ceiling is **200/60s**, and it is **per gateway**, which at least suggests horizontal room (free plan allows 10 gateways) — but sharding a pipeline across gateways to dodge a documented platform limit is the kind of thing that gets an account actioned, and CF documents no per-account third-party ceiling to tell you where the real wall is.
4. **"ZDR is available, just turn it on."** Refuted decisively: ZDR is OpenAI/Anthropic-only and **fails open** for unsupported providers, changing nothing while appearing enabled. This is the single most dangerous false-safety in the whole stack.
5. **"OpenCode says zero retention, so it's fine."** Refuted by OpenRouter's contradicting statement on the same model, and by Cloudflare withholding the ZDR badge it grants 90 other models. Three vendors, three different postures, one anonymous counterparty.
6. **"AI Gateway caching will cut the pipeline's cost."** Refuted for this workload: exact-match-on-full-body keying means an agentic loop with growing context has ~0 hit rate, and the cache key even includes the auth header.
7. **"Fallback can protect against the model disappearing."** Partly refuted: the documented fallback page is on the **deprecated** Universal endpoint, and the current Dynamic Routing path runs through `/compat/chat/completions`, which the REST API path used to call `stealth/union-alpha` does not cover. Whether a dynamic route can even name a `stealth/` model is **untested**.
8. **"Route Claude Code through the gateway for observability, keep the subscription."** Refuted as documented (Cloudflare's recipe kills the subscription and starts per-token billing); only an undocumented base-URL-only variant preserves it, with four concrete failure modes.
9. **Gap I nearly missed:** the free-plan log ceiling is **100,000 logs across ALL gateways**, not per gateway. A 24/7 drain at even 10 req/min exhausts that in ~7 days, after which logging either stops or auto-deletes — i.e. the observability you switched to AI Gateway *for* quietly ends.

---

## UNKNOWNS (say UNKNOWN, do not guess)

1. **Whether a non-zero Unified Billing credit balance is required to call a $0 third-party model.** Docs state the prerequisite generically; no exemption is documented for $0 models. **Untestable here — no Cloudflare credential on this machine.**
2. **Context window and max output tokens on the Cloudflare route.** UNKNOWN. OpenRouter's 262,144 / 131,072 is the same upstream but a different route; Cloudflare publishes neither.
3. **Whether streaming, image input, `response_format` JSON mode, and `reasoning_effort` actually work end-to-end on Cloudflare's route.** Declared in the schema; unverified by execution.
4. **Whether `tool_choice: "required"` / named-function forcing works on Cloudflare.** OpenRouter reports it does not on its endpoint; Cloudflare declares `tool_choice` without qualification. UNKNOWN which is authoritative.
5. **Whether `stealth/union-alpha` is addressable on `/ai/v1/messages` (Anthropic shape), `/ai/v1/responses`, or inside a Dynamic Route.** UNKNOWN.
6. **Concurrency limit.** UNKNOWN — no figure published for AI Gateway or Unified Billing.
7. **The upstream lab's identity, jurisdiction, retention period, and the text of OpenRouter's "Stealth Model Terms."** The terms page is JS-rendered and did not yield text to a plain fetch; the identity is deliberately withheld. **This is the load-bearing unknown for the operator's decision.**
8. **Whether Cloudflare forwards `anthropic-beta`, `cache_control`, and SSE pings unmodified on its Anthropic endpoint.** UNKNOWN — required for the subscription-preserving config to work at all.
9. **The real end date.** UNKNOWN on every primary source. `2026-09-23` is community inference from a 2026-09-16 announcement.

### Blocker for closing 1–5 properly
A single Cloudflare API token with `Workers AI → Read` would settle unknowns 1–5 in about six curls (a `cost` check, a `max_tokens: 200000` probe, a `stream: true` probe, a `tool_choice: "required"` probe, a `/ai/v1/messages` probe, and a rate-limit ramp). No such credential exists on this machine.

---

### Source index (all fetched 2026-09-16)

- https://developers.cloudflare.com/ai/models/stealth/union-alpha/ (+ `/index.md`, `/schema-input.json`)
- https://developers.cloudflare.com/ai/models/ (catalogue; 226 entries, 90 ZDR badges)
- https://developers.cloudflare.com/workers-ai/models/ · /platform/pricing/ · /platform/limits/ · /platform/data-usage/
- https://developers.cloudflare.com/ai-gateway/reference/pricing/ · /reference/limits/
- https://developers.cloudflare.com/ai-gateway/features/unified-billing/ · /features/caching/ · /features/rate-limiting/ · /features/spend-limits/
- https://developers.cloudflare.com/ai-gateway/observability/logging/
- https://developers.cloudflare.com/ai-gateway/usage/rest-api/ · /usage/chat-completion/ · /usage/providers/ · /usage/providers/anthropic/
- https://developers.cloudflare.com/ai-gateway/configuration/request-handling/ · /configuration/fallbacks/ · /configuration/bring-your-own-keys/
- https://developers.cloudflare.com/ai-gateway/integrations/coding-agents/claude-code/
- https://developers.cloudflare.com/changelog/product/ai-gateway/ · /changelog/product/workers-ai/
- https://openrouter.ai/stealth/union-alpha · https://openrouter.ai/api/v1/models · /api/v1/models/stealth/union-alpha/endpoints
- https://opencode.ai/docs/zen/ · https://opencode.ai/zen/v1/models
- https://code.claude.com/docs/en/llm-gateway · https://code.claude.com/docs/en/llm-gateway-protocol
- https://github.com/luongnv89/freetokens/issues/412 (community claim only)
