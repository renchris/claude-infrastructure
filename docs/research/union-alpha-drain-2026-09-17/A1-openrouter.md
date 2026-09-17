# A1 — OpenRouter `stealth/union-alpha`: the hard facts

Researched 2026-09-17 ~04:40 UTC. **The model was created 2026-09-16T14:42:03Z — it is ~14 hours old.**
Stance: default-to-refute. Every number below is either read directly out of OpenRouter's own APIs/HTML
(labelled **[OR-API]**) or quoted from a named source with its date. Forum/blog claims are labelled.

---

## VERDICT (5 lines)

1. **FREE?** Yes, $0/$0 in and out, confirmed in OpenRouter's own catalogue. But it is **not** a `:free`
   variant — it is a $0-priced standard model served by the single provider `Stealth`.
2. **HOW LONG?** **No end date exists on OpenRouter.** OpenRouter's launch post says only "It is free."
   The "one week" (→ ~2026-09-23) is **OpenCode's** claim about **OpenCode Zen**, a different channel.
   Precedent: the prior stealth model **Ox Alpha lasted 6 days (Aug 20→26)** and was then **deleted from
   the catalogue** — no reroute, no price appearing, requests simply stop resolving.
3. **RATE CEILING.** The public docs' free-tier caps (20 RPM / 50–1000 RPD) are scoped to IDs ending in
   `:free` and therefore **do not apply**. The real, undocumented cap is in the endpoint record:
   **`limit_rpm: 100`, `limit_rpd: null`, `capacity_tpm: null`** — 100 req/min, no daily cap, no token
   cap. No concurrency limit is published. Cloudflare DDoS protection and the AUP's "reasonable request
   volume" clause are the unquantified backstops.
4. **DATA SHARED?** **Prompts and completions ARE retained by an anonymous third party for an
   unspecified period**, and OpenRouter states they are **not used for training** for this endpoint.
   There is **no opt-out that preserves access** — the Stealth EULA's own words: "you should refrain
   from accessing or using the Stealth Models." OpenCode's contradicting "zero-retention" claim is
   refuted by OpenRouter's own field `retainsPrompts: true`.
5. **TOOL-CAPABLE?** Yes, but **crippled for a pipeline**: `tool_choice` supports **`auto` only** —
   `none`, `required`, and named-function are all `false`. No `structured_outputs` (strict JSON schema),
   no `seed` (explicitly excluded), no reasoning, **no prompt caching** (`supports_implicit_caching:
   false`). Streaming and images are supported.

**One-line recommendation for the stated use case (24/7 automated backlog drain):** the binding
objections are not technical — they are (a) the anonymous-provider retention of every prompt, (b) the
AUP's ban on "excessive" volume and on submitting third-party/financial/sensitive content, and (c) a
dependency that has a measured 6-day precedent for vanishing without notice.

---

## 1. Free right now? End date? What happens when it ends?

**Free: YES, confirmed at source.**

`GET https://openrouter.ai/api/v1/models` → `stealth/union-alpha` **[OR-API]**:
```json
"pricing": { "prompt": "0", "completion": "0" }
```
Model-page flight payload adds `"pricing_json":{"openai:prompt_tokens":"0","openai:completion_tokens":"0","openai:cached_prompt_tokens":"0"}`, `"is_free":true`, `"discount":0`.
<https://openrouter.ai/api/v1/models> · <https://openrouter.ai/stealth/union-alpha>

**End date on OpenRouter: NONE STATED. This is the single most-misreported fact.**

- OpenRouter's own launch thread (@OpenRouter, **2026-09-16 14:48:22 UTC**, read verbatim via
  fxtwitter) says, in full: "Notes for this stealth model: 💰 It is free 🔑 This time, the provider does
  not train on your prompts or completions". **No duration.**
  <https://x.com/OpenRouter/status/2100235351575191751>
- The "one week" comes from **OpenCode**, 2026-09-16 14:52:40 UTC: "Union Alpha (stealth model) is free
  for the next week — no data training — built for agentic coding — supports images".
  <https://x.com/opencode/status/2100236430890991782>
  OpenCode is a **separate distribution channel** (`opencode.ai/zen`, model id `union-alpha`, served over
  `https://opencode.ai/zen/v1/messages`). Its promise does not bind OpenRouter.
- OpenCode's own docs say only "available on OpenCode for a **limited time**" — no date.
  <https://opencode.ai/docs/zen/>
- Corroboration: *"Neither platform committed to a date… Pricing after the preview has not been
  disclosed anywhere."* — progressiverobot.com, 2026-09-16.
  <https://www.progressiverobot.com/2026/09/16/union-alpha-stealth-coding-model-free-opencode-openrouter/>

**Nothing technical encodes an end.** `expiration_date: "2098-12-31"` and
`deprecation_date: "2098-12-31T16:00:00.000Z"` are OpenRouter's "no scheduled removal" placeholders **[OR-API]**.

**What actually happens at the end — answered empirically, not by guess.** The immediately prior stealth
model, `stealth/ox-alpha` (created 2026-08-20T20:04:55Z), ran ~6 days and was then retired. Today:

- `GET /api/v1/models` → `stealth/ox-alpha` is **ABSENT** from the 444-model catalogue **[OR-API]**.
- `GET /api/v1/models/stealth/ox-alpha/endpoints` → `"endpoints": []` — **zero endpoints** **[OR-API]**.
- Its page now carries the reveal banner, verbatim: *"This stealth model was developed and operated by
  ZAI, revealed to be ZAI GLM-5.3-Flash. Prompts and completions for this model **were retained by the
  provider** and are not used for training; all other use is governed by the Stealth Model Terms."*
  <https://openrouter.ai/stealth/ox-alpha>
- The revealed successor `z-ai/glm-5.3-flash` exists as a **separate, paid** id at $0.09/M in,
  $0.30/M out **[OR-API]** — a different slug, so no silent reroute and no silent billing.

So the failure mode is **404/503, not a surprise invoice**. Per OpenRouter's own error table, a model
with no serving provider returns `404` ("unknown model or no provider can serve the request") or `503`
("No available model provider meets your routing requirements").
<https://openrouter.ai/docs/api_reference/limits>

The Stealth EULA makes the abruptness contractual (§2b Availability): *"Stealth Models are made
available on the Service for a limited time… we cannot guarantee availability… may be removed from our
Stealth Program **at any time** upon request of the Stealth Provider or at OpenRouter's sole discretion,
**with or without notice to you**."* <https://openrouter.ai/terms/stealth> (Updated: September 14, 2026)

**Consequence for a 24/7 pipeline:** pin a fallback. OpenRouter supports a `models` fallback array;
without one, the pipeline dies silently at an unannounced moment, plausibly within days.

---

## 2. Rate limits that actually bind

**The documented free-tier caps DO NOT APPLY — check the scoping clause.** The docs say, verbatim:

> "**Free usage limits**: If you're using a free model variant (**with an ID ending in `:free`**), the
> following limits apply:" — then the table: `<10 credits → 20 RPM / 50 RPD`; `≥10 credits → 20 RPM /
> 1000 RPD`.
> <https://openrouter.ai/docs/api_reference/limits>

`stealth/union-alpha` **does not end in `:free`**. I verified there is no `:free` variant of it: scanning
all 444 catalogue entries, only 4 models are $0-priced and not `:free` — `stealth/union-alpha`,
`google/lyria-3-pro-preview`, `google/lyria-3-clip-preview`, `openrouter/free` **[OR-API]**.
⚠️ The third-party mirror unorouter.com lists a page for `stealth/union-alpha:free`. **That id does not
exist in OpenRouter's catalogue** — treat that site as an unreliable normaliser.

**The real cap, read out of the endpoint record on the model page [OR-API]:**

| Field | Value | Reading |
|---|---|---|
| `limit_rpm` | **100** | 100 requests/minute on this endpoint |
| `limit_rpd` | `null` | **no daily request cap** |
| `capacity_tpm` | `null` | no tokens/minute cap published |
| `max_prompt_tokens` | `null` | no per-request input cap below the 262 144 context |
| `is_deranked` / `is_disabled` / `is_hidden` | `false` | endpoint is live and normally ranked |

**I falsified the obvious objection that `100` is a template default.** Sampling other model pages for
the same field: `openai/gpt-5` → `null`, `z-ai/glm-4.6` → `null`, `anthropic/claude-sonnet-4.5` → `null`,
`moonshotai/kimi-k2` → `50`. So `limit_rpm` is per-endpoint and genuinely set; **100 is specific to
union-alpha**. (Model-level `limit_rpm: 0 / limit_rpd: 0` is the "unset" sentinel and is not the operative
value.)

**Zero-credit vs credit-holding account.** The `:free` credit-threshold table is the only place credits
change a rate limit, and it doesn't reach this model. What *does* reach it:

> "If your account has a **negative** credit balance, you may see 402 errors, **including for free
> models**. Adding credits to put your balance above zero allows you to use those models again."
> <https://openrouter.ai/docs/api_reference/limits>

Negative, not zero — a fresh zero-balance account should be able to call it. **I could not verify this
empirically: no OpenRouter API key exists on this machine** (checked env and shell rc files). See UNKNOWNS.

**Concurrency: no documented limit anywhere**, at either the platform or endpoint level. Not stated ⇒
unknown, not unlimited.

**The unquantified backstops, both of which a 24/7 drain will meet first:**
1. *"**DDoS protection**: Cloudflare's DDoS protection will block requests that dramatically exceed
   reasonable usage."* — no number given. <https://openrouter.ai/docs/api_reference/limits>
2. 🚨 **The Stealth AUP, Exhibit A (iv)** — the one that matters for this use case, verbatim: *"exceed or
   bypass any rate limits, API calls, restrictions, or safety measures on the Stealth Models or **use the
   Stealth Models in a manner that exceeds reasonable request volume or constitutes excessive or abusive
   usage**"*, enforced by §5: *"OpenRouter retains the right to terminate or suspend your access to
   Stealth Models in the event of any breach **or suspected breach**."* <https://openrouter.ai/terms/stealth>

**429 mechanics for the pipeline** (all from the limits doc):
- Successful responses carry **no** `X-RateLimit-*` headers. Only an OpenRouter-side 429 carries
  `X-RateLimit-Limit/Remaining/Reset`; `Retry-After` appears only when every provider returned a hint.
- Poll `GET /api/v1/key` for `free_model_daily_requests {used, limit, remaining}` and `limit_remaining`.
- **Mid-stream 429s do not arrive as HTTP 429** — they arrive as an SSE event with
  `finish_reason: "error"` and an inline `error.code: 429`, because 200 was already sent. A streaming
  pipeline that only checks HTTP status will treat these as successful short completions.
- Upstream-provider 429s carry `error.metadata.provider_code`.

**Capacity, as claim not fact:** community post @Ananth7e (2026-09-16 15:24 UTC) asserts "5T tokens per
day of capacity" — **unsourced, third-party, uncorroborated**. <https://x.com/Ananth7e/status/2100244546701660283>
Note by contrast that for Ox Alpha OpenCode published a capacity figure (100T tok/day) and called limits
near-unlimited; **no equivalent claim was made for Union Alpha** — flagged independently by
progressiverobot.com (2026-09-16): *"plan for throttling rather than assuming the previous generosity
carries over."*

---

## 3. Context, output, and capabilities

All **[OR-API]** unless noted, from `/api/v1/models`, `/api/v1/models/stealth/union-alpha/endpoints`,
and the model page's endpoint record.

| Capability | Value | Source field |
|---|---|---|
| Context window | **262 144** tokens (marketing says "256K") | `context_length` |
| Max output | **131 072** tokens | `max_completion_tokens` |
| Max input | no separate cap | `max_prompt_tokens: null` |
| **Tool / function calling** | **YES, but `auto` only** | `supports_tool_choice: {none:false, auto:true, required:false, function:false}`; `supports_tool_parameters: true` |
| Streaming | **YES** | `stream` documented for this model in its own `llms.txt`; `isAbortable/can_abort: true` |
| Structured output | **JSON mode likely; strict schema NO** | `response_format` present; **`structured_outputs` ABSENT** (360 of 444 catalogue models have it) |
| Prompt caching | **NO** | `supports_implicit_caching: false`; no `input_cache_read/write` price SKUs |
| Images | **YES** | `input_modalities: ["text","image"]`, `supports_multipart: true`, `max_tokens_per_image: null` |
| Long system prompts | no separate limit; bounded only by the 262 144 context | — |
| Reasoning tokens | **NO** | `supports_reasoning: false`; no `reasoning`/`include_reasoning`/`reasoning_effort` |
| Determinism | **`seed` explicitly excluded** | `excluded_parameters: ["seed"]` |
| Other params | `max_tokens, temperature, top_p, tools, tool_choice, response_format` — **that's all**. No `stop`, `top_k`, `frequency_penalty`, `presence_penalty`, `logprobs`, `logit_bias`, `parallel_tool_calls` | `supported_parameters` |
| Moderation | **not moderated by OpenRouter** | `is_moderated: false`, `moderation_required: false` |
| BYOK | **not possible** | `byokEnabled: false`, `is_byok: false` |
| Quantization | **unknown** | `quantization: "unknown"` |
| Region | not disclosed | `provider_region: null` |
| HIPAA | **not eligible** | `is_hipaa_eligible: false` |

🚨 **The `tool_choice: auto`-only restriction is the sharpest technical finding for an automated
pipeline.** You cannot force a tool call (`required`), cannot pin a specific function, and cannot
suppress tools (`none`). Any orchestration step that depends on a guaranteed structured tool call must
be rewritten to tolerate the model answering in prose instead. Combined with the absence of
`structured_outputs` and `seed`, the extraction layer must be defensive and non-reproducible run-to-run.

Note a channel difference: on **OpenCode Zen** the same model is served over an **Anthropic Messages**
shape (`https://opencode.ai/zen/v1/messages`, `@ai-sdk/anthropic`) while every other Zen model uses
`/chat/completions` + `@ai-sdk/openai-compatible` (<https://opencode.ai/docs/zen/>), and OpenCode's price
table lists **Cached Read: Free** for it. On OpenRouter it is OpenAI-shaped
(`pricingStrategy: "openai_chat_completions"`) with caching **off**. Capabilities are channel-dependent;
do not carry a claim from one to the other.

---

## 4. DATA POLICY — the decisive one

### The corrected answer (I got this wrong on the first pass; the correction is the finding)

OpenRouter exposes **two** data-policy records and they disagree. The **provider-level** default for the
`Stealth` adapter, from `GET /api/frontend/v1/all-providers` **[OR-API]**:

```json
{"name":"Stealth","slug":"stealth","dataPolicy":{
  "training": true, "trainingOpenRouter": false, "retainsPrompts": true,
  "canPublish": false, "termsOfServiceURL":"https://openrouter.ai/terms/stealth",
  "requiresUserIDs": true }, "byokEnabled": false, "moderationRequired": false}
```

The **endpoint-level** record for *this* model, embedded in the model page **[OR-API]**:

```json
"data_policy":{"training": false, "trainingOpenRouter": false, "retainsPrompts": true,
               "canPublish": false, "requiresUserIDs": true}
```

**The endpoint record governs**, and it is corroborated three ways: the model page's own banner, the
OpenRouter launch post, and the identically-worded banner now on the retired Ox Alpha page. Do not quote
the provider-level `training: true` as a fact about Union Alpha.

### The operative statements, verbatim

**On-page banner** (<https://openrouter.ai/stealth/union-alpha>, typo theirs):
> "This stealth model is developed and operated by a third-party model provider. Prompts and completions
> for this model **may retained by the provider but are not used for training**; all other use is
> governed by Stealth Model Terms"

**OpenRouter launch post** (2026-09-16 14:48:25 UTC): *"🔑 **This time**, the provider does not train on
your prompts or completions"* — the "this time" is itself informative: training was the norm for prior
stealth models. <https://x.com/OpenRouter/status/2100235351575191751>

**Stealth Program EULA, §1** (<https://openrouter.ai/terms/stealth>, updated 2026-09-14), the parts that
bind regardless of the training flag:
> "…you understand and acknowledge that: (i) **your User Content may be collected by us and shared with
> the Stealth Provider**; (ii) upon request from each Stealth Provider, OpenRouter **may not, in certain
> instances, disclose the name or origin of Stealth Providers to you**; and (iii) if the Stealth Model
> listing indicates User Content will be used for Stealth Model Training, your User Content will be
> logged in full and retained by the Stealth Provider for Stealth Model Training. **If you do not want
> your User Content to be provided to Stealth Providers for Stealth Model training, then you should
> refrain from accessing or using the Stealth Models.**"

**§3 Payment** states the bargain in one sentence:
> "**In consideration for the provision of your User Content to each Stealth Provider**, access to the
> Stealth Models is provided to you free of charge."

**§4 License** grants OpenRouter — unconditionally, i.e. not gated on the training flag —
> "a non-exclusive, **irrevocable, perpetual**, transferable, worldwide, fully paid-up, royalty-free
> license to (i) copy, store, use, host, and distribute your User Content to operate, provide, and
> improve the Service…"
and the training-sublicense arm **only** "to the extent you access or use a Stealth Model **whose listing
discloses use of User Content for Stealth Model training**" — which, for Union Alpha, it does not.

**Mitigation actually offered (§4):** *"User Content provided to Stealth Providers will contain a hashed
identifier, such that each individual user will not be identified or identifiable to the Stealth
Provider, and OpenRouter will contractually prohibit Stealth Providers from attempting to re-identify."*
This is what `requiresUserIDs: true` means in practice. **§2c** is blunt: *"To the extent you provide any
personal data… in an Input to a Stealth Model… such Input and all personal data contained therein **will
be provided to the Stealth Provider**."*

### Retention period: retained, duration UNDISCLOSED

`retainsPrompts: true` with **no `retentionDays` field**. OpenRouter's own provider-logging table renders
exactly this case as **"Prompts are retained for unknown period"** (the renderer's literal string;
`retentionDays === undefined && retainsPrompts` branch). <https://openrouter.ai/docs/guides/privacy/provider-logging>

### 🚨 The cross-channel contradiction — resolve it against the weaker claim

**OpenCode's docs assert the opposite:** *"Union Alpha Free is a stealth model available on OpenCode for
a limited time. **Its provider follows a zero-retention policy** and does not use your data for model
training."* <https://opencode.ai/docs/zen/> — echoed by @Ananth7e ("zero data retention") and by
llmrumors.com. **OpenRouter's own structured field and banner say prompts ARE retained.** For a decision
about routing through **OpenRouter**, OpenRouter's statement is the operative one: **retained, for an
unknown period, by a provider whose identity is deliberately withheld and whose compliance you cannot
audit.** progressiverobot.com (2026-09-16) reached the same rule independently: *"treat the weaker claim
as the operative one."*

### Is there an opt-out, and does it disable access?

- **OpenRouter's own storage is already off by default** — *"OpenRouter does not store your prompts or
  responses, unless you opt in"* to Private Input/Output Logging or to "OpenRouter Use of Inputs/Outputs"
  (the latter buys a 1% discount). Both off by default. Metadata (token counts, latency) is always
  stored. <https://openrouter.ai/docs/guides/privacy/data-collection>
- **The training opt-out probably does not block this model**, because this endpoint's `training` flag is
  already `false`: *"If you opt out of training in your account settings, OpenRouter will not route to
  providers that train."*
- **The retention filter DOES block it.** `provider.data_collection: "deny"` is documented as *"use only
  providers which do not collect user data"*; `Stealth` has `retainsPrompts: true`, and it is the **only**
  endpoint for this model — so `deny` leaves zero eligible providers and the request fails (404/503).
  <https://openrouter.ai/docs/guides/routing/provider-selection#requiring-providers-to-comply-with-data-policies>
  Same for `provider.zdr: true` (ZDR-only routing).
- **So: the only opt-out that preserves the provider's non-retention is not using the model.** The EULA
  says so in as many words (§1, quoted above).

### Two AUP clauses that bear directly on an automated backlog drain over a real codebase

> "(iii) submit or upload to the Stealth Models any information or data that is subject to safeguarding
> and/or limitations on distribution… including… **financial information, or other categories of
> sensitive information**"
> "(i) **access or use the Stealth Models on behalf of any third party**, or grant access to the Stealth
> Models (including any related API key) to any third party"
> "(viii) **publicly disseminate confidential technical information regarding the performance** of the
> Stealth Models"

A pipeline that reads customer-facing product repos, venue/billing data, or works items on behalf of a
paying client is squarely in the blast radius of (i) and (iii). (viii) additionally means publishing your
own benchmark numbers is a breach.

---

## 5. Identity and provenance

**Stated as fact by OpenRouter:**
- Author/creator slug is literally `stealth`; `"creator" content="stealth"` in the page metadata.
  `hugging_face_id: null`, `knowledge_cutoff: null`, `quantization: "unknown"` **[OR-API]**.
- Banner: *"developed and operated by a **third-party model provider**"*; EULA §1: OpenRouter *"does not
  develop any Stealth Models"* and *"may not, in certain instances, disclose the name or origin"*.
- Description (verbatim, and note the trailing ellipsis is theirs): *"Union Alpha is a multimodal model
  built for research, coding, and agentic workflows, while delivering frontier-level performance across a
  broad range of general-purpose tasks. Union Alpha is a stealth model...."*
- **No parameter count, no family, no lab, no knowledge cutoff is stated anywhere by OpenRouter.**
- There is an official X handle, **@unionalphaai**, referenced in OpenRouter's launch post.

**Benchmark claims — vendor-stated, not independently reproduced:**
- OpenRouter marketing: "Frontier-level general-purpose performance."
- **Alex Atallah (OpenRouter CEO)**, 2026-09-16 15:19 UTC, posting a DeepSWE chart: *"This free model
  also outperforms 5.6 Sol on Terminal-Bench 2.1 and SWE-Bench Verified. And outperforms Opus 5 on TBench
  2.1."* <https://x.com/alexatallah/status/2100243109401469062> — **first-party vendor claim with a chart
  image; no methodology published, not reproduced by anyone.**
- Community (@Ananth7e, same day): "scored 74 on DeepSWE, matching gpt-6 astra… lands around 50%
  terminal-bench v4 at ~$1.5-2/task" — **third-party, unsourced.** The `$1.5-2/task` figure is the only
  public hint at eventual pricing and it is a stranger's estimate.
- A reviewer who looked at the underlying numbers found them non-reproducible: *"The first is a dated
  third-party evaluation with visible methodology limits, while the second does not publish enough detail
  to reproduce the score."* — blog.buildfastwithai.com, 2026-09-16.

**⚠️ SPECULATION — clearly labelled, and none of it is confirmed:**
- Named guesses circulating: **GLM/Z.ai, Moonshot/Kimi, "GPT-6 Sol", "a new Claude Opus"**. Every source
  that names one also disclaims it. llmrumors.com (2026-09-16): *"Neither the listing nor those
  specifications establish that it is GPT-6 Sol, a new Claude Opus, or any other named successor."*
- **The one non-forum signal**, and I label it an inference rather than a fact: on OpenCode Zen, Union
  Alpha is the **only** model routed through an **Anthropic Messages**-shaped endpoint
  (`/zen/v1/messages`, `@ai-sdk/anthropic`) while every sibling uses `/chat/completions` +
  `@ai-sdk/openai-compatible` (<https://opencode.ai/docs/zen/>). That is evidence about the **upstream API
  shape**, not about the lab — many providers ship Anthropic-compatible endpoints. On OpenRouter it is
  OpenAI-shaped. **Do not convert this into a lab name.**
- **The base rate is worth more than the guesses:** the immediately prior stealth model, Ox Alpha, was
  revealed on day 6 to be **Z.ai GLM-5.3-Flash** — stated on OpenRouter's own page today. Union Alpha has
  a *different* capability profile (262 144 ctx vs Ox Alpha's ~1 048 576; text+image vs
  text+image+**video**; `supports_reasoning: false` vs Ox Alpha's reasoning-model description), so it is
  **not** a relabelled Ox Alpha.

---

## 6. Reported real-world behaviour in the last ~2 weeks

🚨 **The premise is not satisfiable, and that is the finding.** The model was created
**2026-09-16T14:42:03Z** and announced at 14:48 UTC. At the time of writing it is **~14 hours old.**
There is no two-week record, and any source claiming one is describing a different model (most likely Ox
Alpha, Aug 20–26).

**What OpenRouter itself measures right now [OR-API], re-polled 2026-09-17 04:41 UTC:**

| Metric | Value |
|---|---|
| `status` | `0` (normal) |
| `uptime_last_5m` | **100 %** |
| `uptime_last_30m` | **99.9971 %** |
| `uptime_last_1d` | **99.9894 %** |
| `latency_last_30m` | **`null`** |
| `throughput_last_30m` | **`null`** |

🚨 **OpenRouter is publishing no speed data at all.** Latency and throughput were `null` on my first poll
and still `null` ~14 hours and (reportedly) billions of tokens later. **You cannot size a pipeline's
throughput from any published number.** Independently observed the same day: *"both the latency and
throughput fields return null, so OpenRouter is publishing no speed data at all"* — progressiverobot.com.

**Practitioner reports: none of substance exist yet.** I searched for first-hand reports of reliability,
throttling, tool-call failures and truncation and found **zero** with measurements. Every article dated
2026-09-16 restates the listing. Explicitly:
- *"Unlike Omen Alpha, there is not yet a reliable universal Union Alpha throughput figure that can be
  treated as a standard speed benchmark."* — blog.buildfastwithai.com, 2026-09-16, which **did not run
  the model**.
- llmrumors.com (2026-09-16): no reliability, latency, throttling, truncation or tool-calling failures
  reported; frontier positioning is *"the listing's positioning, not an independently established
  result."*
- progressiverobot.com (2026-09-16): no tool-calling or throttling observations.
- No r/LocalLLaMA, HN or GitHub-issue thread with measured behaviour surfaced. The only GitHub activity
  found is free-tier *aggregator* listings adding the offer (luongnv89/freetokens #412/#413, #414 for
  Cline) — i.e. people cataloguing that it is free, not reporting how it behaves.

**Adoption anecdotes (label: anecdote, single day, uncorroborated):** ~1.96–2 B tokens on day zero
(daily.dev, kucoin, 2026-09-16); engagement of 9.8 K likes / 1.7 M views on the OpenCode post. Adoption
is not reliability.

**The nearest thing to a real-world signal is the precedent, not the model:** Ox Alpha ran 6 days under
heavy load and then vanished from the catalogue. Plan for that shape.

---

## Adversarial pass — what I checked because it would have falsified me

| Challenge | Result |
|---|---|
| "The provider trains on your data" (my first read of `all-providers`) | **REFUTED by me.** That was the Stealth *adapter's* default record; the *endpoint* record says `training: false`, corroborated by the page banner, OpenRouter's post, and the Ox Alpha reveal banner. Corrected above. |
| "`limit_rpm: 100` is just a template default" | **REFUTED.** Sampled 4 other models: gpt-5/glm-4.6/sonnet-4.5 → `null`; kimi-k2 → `50`. The field is set per endpoint. |
| "The 20 RPM / 50-1000 RPD free caps apply" | **REFUTED.** The docs scope them to ids ending `:free`; this id does not, and no `:free` variant exists in the catalogue. |
| "A `union-alpha:free` id exists" (unorouter.com) | **REFUTED.** Not present in any of 444 catalogue entries. Third-party mirror is unreliable. |
| "Zero-retention" (OpenCode, @Ananth7e, llmrumors) | **REFUTED for the OpenRouter channel** by `retainsPrompts: true` + the on-page banner. Channel-dependent claims must not be carried across. |
| "When the free window ends it silently reroutes / starts charging" | **REFUTED by precedent.** Ox Alpha → endpoints `[]`, delisted from `/api/v1/models`; the paid successor is a *different slug*. Failure is 404/503. |
| "It's a relabelled Ox Alpha / GLM-5.3-Flash" | **REFUTED on capabilities** (context 262 K vs ~1 M; no video input; `supports_reasoning: false`). Identity still unknown. |
| "It supports structured outputs" (claimed by at least one summary) | **REFUTED.** `response_format` yes, `structured_outputs` absent — 360/444 models have that flag and this one does not. |
| "Tool calling works like any other model" | **REFUTED.** `tool_choice` is `auto`-only; `required`, `none` and named-function are all `false`. |
| Is there an OpenRouter key on this box to measure limits empirically? | **No** — env and shell rc files carry none. All rate-limit numbers above are read from OpenRouter's records, not measured. |

---

## UNKNOWNS (say UNKNOWN, don't guess)

1. **When the free window actually ends on OpenRouter.** UNKNOWN. No date is stated or encoded.
   OpenCode's "one week" (→ ~2026-09-23) binds OpenCode Zen, not OpenRouter. Ox Alpha's 6 days is the
   only base rate.
2. **What it will cost afterwards.** UNKNOWN. Not disclosed anywhere. The only number in circulation
   ($1.5-2/task) is a stranger's estimate on X.
3. **Whether `limit_rpm: 100` is per-API-key, per-account, or global across the endpoint.** UNKNOWN —
   the field is undocumented. Note the docs' warning that extra accounts/keys don't help: *"Making
   additional accounts or API keys will not affect your rate limits, as we govern capacity globally."*
4. **Concurrency ceiling.** UNKNOWN — no concurrency limit is published at any level.
5. **Tokens-per-minute ceiling.** UNKNOWN — `capacity_tpm: null`. Only requests are capped.
6. **Whether a $0 non-`:free` model counts against `free_model_daily_requests`.** UNKNOWN. The doc hedges:
   the counter reports the ceiling "when these limits apply to your account", and "accounts and endpoints
   **exempt** from free-model limits… are not gated by it." Resolvable in one call to
   `GET /api/v1/key` with a real key — **which this machine does not have.**
7. **Whether a zero-balance (never-purchased) account can call it at all.** UNKNOWN empirically. Docs say
   402 applies to a *negative* balance; zero should be fine. Untested.
8. **Actual latency, time-to-first-token and tokens/sec.** UNKNOWN. OpenRouter publishes `null` for both
   speed fields and nobody has measured it publicly.
9. **Retention period.** UNKNOWN by construction — `retainsPrompts: true` with no `retentionDays`;
   OpenRouter's own table renders this as "retained for unknown period".
10. **Who makes it, parameter count, family, knowledge cutoff.** UNKNOWN and contractually withheld
    (EULA §1(ii)). All named guesses are speculation.
11. **Whether `response_format: {"type":"json_object"}` actually works**, given `structured_outputs` is
    absent. Untested — one call would settle it.
12. **Whether the account-wide privacy setting (which has "separate settings for paid and free models")
    treats a $0 non-`:free` model as "free".** UNKNOWN; affects whether an existing privacy setting
    silently blocks the model.
13. **Whether OpenRouter would treat a 24/7 automated drain as "excessive or abusive usage"** under AUP
    (iv). UNKNOWN and unquantified; enforcement is discretionary and triggered by *suspected* breach.
14. **Behaviour under sustained load** — throttling shape, output truncation at long outputs, tool-call
    reliability across long agent loops. UNKNOWN; the model is ~14 hours old and no one has published
    anything.

---

### Sources

- <https://openrouter.ai/stealth/union-alpha> · <https://openrouter.ai/stealth/union-alpha/llms.txt>
- <https://openrouter.ai/api/v1/models> · <https://openrouter.ai/api/v1/models/stealth/union-alpha/endpoints>
- <https://openrouter.ai/api/v1/models/stealth/ox-alpha/endpoints> · <https://openrouter.ai/stealth/ox-alpha>
- <https://openrouter.ai/api/frontend/v1/all-providers>
- <https://openrouter.ai/terms/stealth> (Stealth Program EULA, updated 2026-09-14)
- <https://openrouter.ai/docs/api_reference/limits> · <https://openrouter.ai/docs/guides/privacy/provider-logging>
- <https://openrouter.ai/docs/guides/privacy/data-collection> · <https://openrouter.ai/docs/guides/routing/provider-selection>
- <https://opencode.ai/docs/zen/>
- <https://x.com/OpenRouter/status/2100235351575191751> · <https://x.com/opencode/status/2100236430890991782>
- <https://x.com/alexatallah/status/2100243109401469062> · <https://x.com/Ananth7e/status/2100244546701660283>
- <https://www.progressiverobot.com/2026/09/16/union-alpha-stealth-coding-model-free-opencode-openrouter/>
- <https://blog.buildfastwithai.com/union-alpha-review> · <https://www.llmrumors.com/news/union-alpha-openrouter-mystery-model>
