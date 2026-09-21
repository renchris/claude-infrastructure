# A9 — The Jev operating envelope, measured. 2026-09-21

**Scope of this file:** the five constants a scheduled Jev job must be built against, each with its
receipt. **Zero Jev calls were made producing it.** Every number here comes from code on disk, the
343 recorded verdicts in `~/.claude/autonomy/jev-*.jsonl`, the AI SDK's own source in
`node_modules/`, a **local mock** A/B that needs no key, or the vendor's public docs.

**Headline — four of the five constants currently in the code are wrong or unsourced:**

| # | The constant in the code | What it should be |
|---|---|---|
| 1 | "~4 calls before throttling", budget `TOT/6`–`TOT/2` min | **14.8 calls/min measured over 146 consecutive calls**; the run took 9.9 min against a 24–73 min budget |
| 2 | retry on `reason == "rate-limited"` only | the string is RIGHT; the **`http` catch-all is the defect** — it merges terminal 403/402 with retryable 500 |
| 3 | "free until 2026-09-25… capped at $5/mo" | correct in substance, but **there is no functional date guard anywhere** — one display-only line |
| 4 | `# well under Jev's 32k-TOKEN state ceiling` | **32,000 total tokens** is confirmed for our route; the cap is **chars, not bytes, over the whole spec** |
| 5 | "`score` is rejected `invalid-response` — the runtime schema is stricter than the published type" | 🚨 **REFUTED. It was our MOCK's incomplete probability distribution.** `score` works through our exact code path |

---

## 1. The real rate limit

### Where "~4 calls" came from — found, and it is n=6 on one occasion

`git log -1 --format=%B 9ee09166e` (2026-09-19, `fix(jev-pilot): self-throttle…`), verbatim:

```
MEASURED on the free tier 2026-09-19, at a 3-second gap:

  call 1  ok 693ms · call 2  ok 650ms · call 3  ok 723ms · call 4  ok 1263ms
  call 5  rate-limited · call 6  rate-limited

Roughly four calls clear, then HTTP 429, recovering after some minutes.
```

That is the entire evidence base. **n=6, one burst, one day** — and that day was the day the
account made its *first ever* AI Gateway request (Addendum 3: *"The first real Jev calls ever made
from this machine"*), which is also the day Vercel's free monthly credit clock starts
(`/docs/ai-gateway/pricing`: *"Your free credits start when you make your first AI Gateway
request"*). It propagated into `pilot.sh:118-121` as `N/4 … N/2` minutes and then into
`rank-memory.sh:79-80` as `TOT/6 … TOT/2` — **the two scripts already disagree with each other**
(4 vs 6 calls/min) and neither number was ever re-measured.

### Achieved throughput, MEASURED from the recorded runs

Rows carry **no timestamp** (`{file, level, superseded, hook}` / `{sid, hook, p, class, jev_fire,
close_head}`), so the rate is derived from the run-start stamp **in the filename** — set at
`rank-memory.sh:66` / `pilot.sh:63`, i.e. at process start — against the file's **last-append
mtime**, over the **row count**.

| run | attempts | window (UTC) | seconds | **calls/min** |
|---|---|---|---|---|
| `jev-rank-20260921T050814Z.jsonl` | 146 attempts (140 rows + 6 skips) + 1 preflight | 05:08:14 → 05:18:07 | **593** | **14.8** |
| `jev-pilot-20260921T024237Z.jsonl` | 172 attempts (160 rows + 12 skips) | 02:42:37 → 02:55:46 | **789** | **12.2** (floor) |
| `jev-pilot-20260921T022258Z.jsonl` | 38 rows | 02:22:58 → 02:25:55 | **177** | **12.9** |

**The rank run is the clean instrument.** `rank-memory.sh` does no per-row I/O beyond
`head -c 3000` on a local file, so its wall clock is `Σ(call + 3 s gap) + Σ backoff`.
146 × 3 s = 438 s of mandated sleep, leaving **155 s for 147 calls** ≈ 1.05 s/call — squarely on
the measured 0.47–1.26 s round trip. **There is no room in that budget for a single backoff
ladder** (retry 1 alone sleeps 10 s; a full 5-retry ladder is 150 s). So ≥99% of 146 consecutive
calls cleared on the first attempt.

The pilot's 12.2/min is a **floor**, not an estimate: `pilot.sh:110` runs a full
`find $HOME/.claude*/projects -name "<sid>.jsonl"` **per row**, and that cost is inside the window.

**Both runs are GAP-BOUND, not throttle-bound.** At `CC_JEV_*_GAP=3` the ceiling is
60/(3 + 1.05) = **14.8/min**, which is exactly what the rank run achieved. The route was never the
constraint.

**Verdict on the budget line:** `rank-memory.sh:80` printed *"Budget roughly 24-73 minutes"* for
146 rules. It took **9.9 minutes**. Over-prediction of **2.4×–7.4×**.

### What actually binds, and what to build against

Vercel's own doc (`/docs/ai-gateway/rate-limits`, last_updated 2026-09-08) refuses to publish a
number and says why:

> On the free tier, AI Gateway enforces a lower limit per model… **Limits can change, so this page
> describes behavior rather than fixed numbers.** To confirm the current limit for a model, contact
> Vercel from your dashboard's **Support** entry.

and

> Some `429` responses include a `retry-after` header with the number of seconds to wait.
> **Honor it when it is present.**

⚠️ **A scheduled job must therefore be ADAPTIVE, not pre-budgeted.** Two unresolved causes for the
2026-09-19 429s that I cannot separate from disk — (a) a free-tier per-model limit that has since
changed, (b) a first-request/cold-account condition, (c) an upstream **provider** 429, which the
same doc says can arrive on either tier with the provider's own error body. All three say the same
thing: **do not encode a calls/minute constant.** Encode `retry-after` + exponential backoff and let
the observed rate be whatever it is.

🚨 **`retry-after` is thrown away today.** `evaluate.mjs:115-138` never reads response headers, so
neither `pilot.sh` nor `rank-memory.sh` can honour it; both sleep a fixed `10 × tries` seconds.

---

## 2. The failure taxonomy — 12 reasons, and one of them is a bucket

Complete enumeration. `reason` is produced in exactly two files.

| `reason` | source | exit | HTTP | class | today's retry? |
|---|---|---|---|---|---|
| `unavailable` | `jev.sh:140` | rc 1 | — | **TERMINAL** (kill switch `CC_JEV=0`, no key source, no `evaluate.mjs`, no `node_modules/ai`, no `node`) | no ✓ |
| `oversize` | `jev.sh:141` | rc 1 | — | **TERMINAL** (spec > `CC_JEV_MAX_STATE_B`) | no ✓ |
| `no-output` | `jev.sh:159` | rc 1 | — | **RETRYABLE** (child killed/crashed) | 🚨 no |
| `no-key` | `evaluate.mjs:60`, `:128` | 10 | — / **401** | **TERMINAL** | no ✓ |
| `bad-spec` | `evaluate.mjs:66,69,72,130` | **2** | 400 | **TERMINAL** (caller's fault) | no ✓ |
| `deps-missing` | `evaluate.mjs:93` | 10 | — | **TERMINAL** | no ✓ |
| `timeout` | `evaluate.mjs:127` | 10 | — | **RETRYABLE** (our own `AbortSignal`, 2500 ms) | 🚨 no |
| `unsupported-question` | `evaluate.mjs:129` | **2** | — | **TERMINAL** | no ✓ |
| `invalid-response` | `evaluate.mjs:131` | 10 | 200 | **TERMINAL** (a schema/validation mismatch, not a network event) | no ✓ |
| `no-model` | `evaluate.mjs:132` | 10 | 404 | **TERMINAL** | no ✓ |
| `rate-limited` | `evaluate.mjs:137` | 10 | **429** | **RETRYABLE** | **yes ✓** |
| `http` | `evaluate.mjs:138` | 10 | **everything else** | 🚨 **MIXED — see below** | no |

### The wording question, answered: `rate-limited` IS what the route returns

`rank-memory.sh:135` matches the literal string `rate-limited`. Double-confirmed:

- `node_modules/@ai-sdk/gateway/dist/index.js:234-252` defines `GatewayRateLimitError` with
  `this.name = "GatewayRateLimitError"` and `statusCode = 429` → matches `/RateLimit/i` on **name**
  at `evaluate.mjs:137`.
- The Gateway's documented 429 body is `{"error":{"message":"Rate limit exceeded","type":
  "rate_limit_exceeded"}}` → also matches `/rate.?limit/i` on **message**.

So the retry loop's trigger string is correct. **The defect is elsewhere.**

### 🚨 `http` is a catch-all that merges terminal with retryable

Measured by running the repo's own local mock through the real classifier (no key, no network):

```
err401  -> {"ok":false,"reason":"no-key"}            exit 10
err500  -> {"ok":false,"reason":"http"}              exit 10
garbage -> {"ok":false,"reason":"invalid-response"}  exit 10
no listener (ECONNREFUSED) -> {"ok":false,"reason":"http"}  exit 10
```

`http` therefore contains, indistinguishably:

| actually is | right action |
|---|---|
| **403 ZDR / plan-gated** (*"ZDR is only available for Pro and Enterprise plans. Current plan: hobby"*) | **abort in 2 s** — 146 calls of this is the incident `rank-memory.sh:85-107` was written about |
| **402 `quota_for_entity_exceeded`** (a Vercel budget is exhausted) | **abort** — retrying spends nothing but wall clock, forever |
| **egress blocked** by `agent-secrets`' CONNECT proxy (host absent from `~/.config/secrets/egress.allow`) | **abort**, name the file |
| **HTTP 500 upstream**, `ECONNREFUSED`, DNS | **retry with backoff** |

**The SDK already computes the answer and we discard it.**
`node_modules/@ai-sdk/gateway/dist/index.js:117-121`:

```js
isRetryable = statusCode != null && (statusCode === 408 || statusCode === 409 ||
              statusCode === 429 || statusCode >= 500)
```

Every thrown `GatewayError` carries `.statusCode` and `.isRetryable`. `evaluate.mjs:123-126` builds
the cause chain and reads only `.name` and `.message`. **Two fields, already on the object.**

**Build recommendation for the scheduled job** — emit `{reason, status, retryable}` from
`evaluate.mjs`, and have the caller branch on `retryable` rather than string-matching one reason.
Until that lands, the caller must treat `http` as **terminal after 1 retry** and print the message,
because today an unhandled-but-terminal `http` degrades into a silent skip — exactly the shape
`rank-memory.sh:154-163`'s 10-consecutive-skip abort exists to bound. That abort is the only thing
standing between a dead route and a 70-minute grind, and it costs 10 doomed calls to fire.

---

## 3. The 2026-09-25 cliff

### The repo's own record answers it, and the vendor now corroborates

`bin/cc-jev:113-115` (comment) and `:155-167` (`jev_free_window`):

> After it lapses the cost is not a cliff: $0.042/MTok in, $0 out, measured at ~960 calls/day
> ≈ $2.45/mo for the production arm, against a key already capped at $5/mo.

Vendor, checked because the money question deserves a primary source:

| source | what it says |
|---|---|
| `https://vercel.com/ai-gateway/models/jev` | `$0.042/1M input tokens`; output `0`; **`Context window: 32,000`**. **No cut-off statement, no free-window statement.** A published price for a live model = metered, not revoked. |
| `https://vercel.com/ai-gateway/models?freeTier=true` | **`typesafe-ai/jev \| evaluation \| 32K \| $0.04/1M \| $0.00/1M \| typesafe-ai`** — Jev **IS free-tier-eligible today.** |
| `https://vercel.com/docs/ai-gateway/pricing` | *"Every Vercel team account gets access to both a free tier and a paid tier… Your free credits start when you make your first AI Gateway request… Once you purchase credits, your account transitions to the paid tier and **the monthly free credit no longer applies**."* Auto top-up is *"disabled by default"*. |
| `https://vercel.com/docs/ai-gateway/rate-limits` | budgets reject with **`402` + `quota_for_entity_exceeded`**, distinct from a rate limit's `429`. |

**So: the key keeps working and starts drawing down the monthly included credit.** It does not hard-
fail on 2026-09-26, *provided Jev stays on the free-tier-eligible list* (it is there today —
re-check it, it is a vendor list that can change).

### 🚨 The guard question — and the honest answer is "there is none in code"

| candidate guard | state on disk |
|---|---|
| a hard date check in the script | **DOES NOT EXIST.** `CC_JEV_FREE_UNTIL` is read at **exactly one line — `bin/cc-jev:152`** — inside `jev_free_window()`, which only `printf`s. Nothing in `hooks/`, `scripts/` or any caller gates on the date. |
| a spend ceiling in code | **DOES NOT EXIST.** No `$`-amount is read or enforced anywhere; `$5/mo` appears only in display prose. |
| a key that expires | **NO.** `agent-secrets list` → `AI_GATEWAY_API_KEY (rotate by 2027-03-18)`. That is a **rotation reminder**, not an expiry. The key does not self-revoke. |
| the account's own ceiling | The **monthly included free credit** is the real bound, and exhausting it **fails the request** rather than billing a card — but only while the team holds **no purchased credits** and **auto top-up is off**. Neither is readable from this machine. |
| a Vercel **budget** | **Available and not set** (as far as disk can tell). This is the correct guard: it is server-side, cannot be bypassed by a script edit, and returns a distinguishable `402`. |

**Residual for the operator (dashboard-only, cannot be read from here):**
1. Confirm **no purchased AI Gateway Credits** and **auto top-up OFF** on the team holding this key.
2. Set a **budget** (`/docs/ai-gateway/observability-and-spend/budgets`) at e.g. $3/mo scoped to the
   API key. That converts "silent spend" into a `402` the taxonomy above can abort on.
3. Confirm whether the *"capped at $5/mo"* in `cc-jev:115` means an operator-set spend cap or is a
   restatement of the $5 monthly **free credit**. They are different guards and the code's wording
   does not distinguish them.

**Code-side recommendation:** a scheduled job should refuse to start when
`date -u +%F > ${CC_JEV_FREE_UNTIL}` unless `CC_JEV_PAID=1` is explicitly set. That is a one-line
gate and it is the difference between "metered on purpose" and "metered because nobody noticed".

---

## 4. The 32k ceiling — RESOLVED for our route

`jev-at-cost-api-2026-09-18.md:47-50` recorded the conflict as *"unresolved, and it binds whichever
route is bought"*. It is resolvable, because the three numbers describe **three different routes**:

| route | ceiling | do we use it? |
|---|---|---|
| direct `api.typesafe.ai` — vendor `models.md:15` | 64k/request, 32k for state + longest question | **no** |
| OpenRouter — `context_length 32000` | 32,000 | **no** |
| **Vercel AI Gateway** — `vercel.com/ai-gateway/models/jev` | **`Context window: 32,000`** | **YES** — this is the only route in the code |

The code path leaves no ambiguity: `evaluate.mjs:51` `MODEL = 'typesafe-ai/jev'`, resolved through
the default provider, which `evaluate.mjs:82-84` states *"can only ever talk to
ai-gateway.vercel.sh"*; `jev.sh:102` `CC_JEV_GATEWAY_HOST=ai-gateway.vercel.sh`; and
`~/.config/secrets/egress.allow:3` allowlists that one host. **32,000 tokens per request binds, and
the OpenRouter figure agrees with it.** The 64k figure is about a route we do not buy.

### What is SAFE, versus what is nominally allowed

The local bound is `jev.sh:141`:

```bash
if [ "${#spec}" -gt "$CC_JEV_MAX_STATE_B" ]; then printf '{"ok":false,"reason":"oversize"}'; return 1; fi
```

Three properties of that line that the name `..._MAX_STATE_B` hides:

1. **It measures the WHOLE SPEC, not `state`.** Measured on a real `rank` payload: the question
   envelope alone is **1,057 chars**, so the usable state budget is **22,943**, not 24,000.
2. **`${#spec}` counts CHARACTERS, not bytes.** `LC_ALL=en_US.UTF-8; s="é é é"` → `${#s}`=5,
   `wc -c`=8. Measured over the 480-file memory corpus at the 3,000-byte cap `rank-memory.sh` uses:
   mean **1.0073 bytes/char**, worst file **1.028**. So the mislabel is real but **benign at
   today's content** — 24,000 chars ≈ 24,175 bytes typical, ≈24,670 worst case. It would stop being
   benign on CJK or emoji-dense input.
3. **Bytes are a proxy for tokens and the conversion is unmeasured here.** Neither script records
   `usage.inputTokens`, although `evaluate.mjs:109` returns it. At ~3.5–4 bytes/token for English
   engineering prose, 24,000 chars ≈ **6,000–7,000 tokens ≈ 19–22% of the 32,000 ceiling**.

**SAFE cap to build against: 16,000 bytes on `state` alone** (≈4,000–4,600 tokens, ~14% of ceiling),
measured in **bytes** (`printf '%s' "$s" | wc -c`), with the question envelope budgeted separately.
That survives a 2× tokenizer surprise, a fatter question block, and non-ASCII content
simultaneously. The current 24,000-char whole-spec bound is *not unsafe* — it is simply not the
thing its name says it is, and it will stop being conservative the first time a caller sends a
bigger question block.

**The cheap upgrade:** record `usage.inputTokens` in every JSONL row. One field converts every
future byte cap from ASSUMED to MEASURED. It is already in the response and already discarded.

---

## 5. `score`, definitively — 🚨 the repo's finding is REFUTED, and it was a fixture defect

### The claim, in three places, all tracing to one measurement

- `scripts/jev/rank-memory.sh:142-147` — *"`score` is declared in the SDK types with exactly the
  shape our mock returns, and the identical round trip is still rejected `invalid-response` while a
  boolean through the same path succeeds — so **the runtime schema is stricter than the published
  type** and the primitive is not usable from here today."*
- `tests/jev-evaluate.bats:342-348` — same sentence.
- commit `a0ceab890` body — *"🚨 USES `choice`, NOT `score`, AND THAT IS MEASURED."*

### What it was actually measured against: **the mock**, not Jev

Recovered verbatim from the session transcript that produced it:

```
--- score:
{"ok":false,"reason":"invalid-response","ms":86}
--- raw mock reply for score:
{"answers":{"s":{"type":"score","score":3,"probabilities":{"3":1}}},...}
```

**`raw mock reply`.** No Jev call was involved. The word "runtime" in all three comments points at
the Gateway; the measurement never left `127.0.0.1`.

### The mechanism, read out of the SDK

`node_modules/ai/dist/index.js:14503-14530`, `validateEvaluationAnswers`, runs **client-side after
the response arrives** and throws `InvalidResponseDataError` (`:14416-14418`) — which
`evaluate.mjs:131` maps to `invalid-response`. For a `score` question it demands:

- `hasExactKeys(probabilities, criteria.map((_, i) => String(i)))` — a **COMPLETE** distribution
  over every level index (`:14425-14431`);
- `|Σ i·pᵢ − score| ≤ 1e-6` (`tolerance`, `:14322`) unless `rounding.scoreDecimals` is declared.

`tests/fixtures/jev-mock-gateway.mjs:63` emits `probabilities: { [String(pick)]: 1 }` — **one key**.
Its `choice` branch, eight lines above at `:51`, emits the complete map via `Object.fromEntries`.
**That asymmetry is the whole bug**, and it is why boolean and choice pass while score does not.

### The A/B that settles it — run locally, no key, no network, no tracked file edited

Both mock copies live in the scratchpad; `tests/fixtures/jev-mock-gateway.mjs` was **not modified**.

```
--- arm=asis        (probabilities: {"3":1})
{"ok":false,"reason":"invalid-response","ms":99}                       exit=10
--- arm=complete    (probabilities: {"0":0,"1":0,"2":0,"3":1})
{"ok":true,"answers":{"s":{"type":"score","score":3,
  "probabilities":{"0":0,"1":0,"2":0,"3":1}}},"usage":{...},"ms":95}   exit=0
```

**`score` works end-to-end through `scripts/jev/evaluate.mjs` unmodified.** The primitive is not
blocked. `GatewayEvaluationModel.supportedQuestionTypes` is `["choice","score","boolean"]`
(`@ai-sdk/gateway/dist/index.js:2275`) and the gateway's response schema accepts
`{type:'score', score:number, probabilities?}` (`:2355-2359`).

### What is still genuinely untested, and the one probe worth an operator run

Refuting the objection establishes ¬objection, not the claim. Two things remain unknown **about the
real route**:

1. **The score QUESTION shape has never been sent.** The SDK requires `criteria` to be an **ARRAY**
   of ≥2 ordered levels indexed from zero (`@ai-sdk/provider/dist/index.d.ts:2263-2266`), validated
   pre-flight at `ai/dist/index.js:14382-14386`. `rank-memory.sh:127-129` uses a `choice` question
   with an ordered **MAP**. **The array form has never left this machine.**
2. **Whether real Jev satisfies the weighted-mean identity at 1e-6.** If it rounds `score` to two
   decimals without declaring `rounding.scoreDecimals`, `validateEvaluationAnswers` rejects it —
   which would be a *genuine* `invalid-response` and would look identical to the fixture defect.

**The probe (one operator-run call, ~$0, ≈1 s):**

```bash
CC_JEV_ZDR=0 jq -n '{state:"A rule about following symlinks before deriving paths.",
  questions:{bite:{type:"score",
    instructions:"How often would this rule change what an engineer does on a future task?",
    criteria:["almost-never","occasionally","often","nearly-always"]}}}' \
  | bin/cc-jev ask -
```

**Before running it, make `evaluate.mjs` print the raw body on `invalid-response`** — `evaluate()`
returns `result.response.body` (`rawValue`, `@ai-sdk/gateway/dist/index.js:2329`), and without it a
rejection is unreadable and a second probe is needed. `abstain('invalid-response')` currently drops
it. That one change turns "score does not work" from a three-comment folk belief into a settled fact
in one call.

**Why it is worth the call:** `score` returns a *fractional* position in `[0, n-1]` plus the full
distribution — a genuinely continuous, sortable ordinal. `choice` returns a label plus a
distribution, and `rank-memory.sh` currently collapses 140 rules into **4 buckets**. A ranking over
4 ties is barely a ranking.

---

## Re-derive, never re-quote

```bash
cd ~/Development/claude-infrastructure

# 1 — where "~4 calls" came from
git log -1 --format=%B 9ee09166e

# 1 — achieved throughput (rows carry no timestamp; filename stamp = process start)
for f in ~/.claude/autonomy/jev-rank-20260921T050814Z.jsonl \
         ~/.claude/autonomy/jev-pilot-20260921T024237Z.jsonl; do
  printf '%s rows=%s start=%s end=%s\n' "$(basename "$f")" "$(wc -l <"$f"|tr -d ' ')" \
    "$(basename "$f" | sed 's/.*-\([0-9TZ]*\)\.jsonl/\1/')" \
    "$(TZ=UTC stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$f")"
done
python3 -c "print('rank calls/min =', 146/593*60, ' pilot =', 160/789*60)"

# 1 — the population the rank run drew from (must equal 146)
MEM=~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/memory
grep -c '](.*\.md)' "$MEM/MEMORY.md"

# 2 — every reason the code can emit
/usr/bin/grep -n "reason:" scripts/jev/evaluate.mjs hooks/lib/jev.sh

# 2 — classify each HTTP status through the real classifier, no key needed
#     (start tests/fixtures/jev-mock-gateway.mjs in mode err401|err500|garbage, then:)
#     printf '{"state":"s","questions":{"q":{"type":"boolean","instructions":"ok?"}}}' \
#       | env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL=http://127.0.0.1:$PORT node scripts/jev/evaluate.mjs

# 2 — the retryable field we discard
/usr/bin/grep -n "isRetryable = statusCode" -A 4 node_modules/@ai-sdk/gateway/dist/index.js

# 3 — is anything gated on the free-window date? (expect exactly ONE display-only line)
/usr/bin/grep -rn "CC_JEV_FREE_UNTIL" bin scripts hooks
agent-secrets list | grep AI_GATEWAY_API_KEY          # rotation date, NOT an expiry

# 4 — the ceiling on OUR route, and the local bound's true units
#     open https://vercel.com/ai-gateway/models/jev  -> "Context window: 32,000"
/usr/bin/grep -n "CC_JEV_MAX_STATE_B" hooks/lib/jev.sh
LC_ALL=en_US.UTF-8 bash -c 's="é é é"; echo "chars=${#s}"; printf "%s" "$s" | wc -c'

# 5 — the score A/B (copies only; never edit the tracked fixture)
SP=/tmp/jev-score-ab && mkdir -p $SP
cp tests/fixtures/jev-mock-gateway.mjs $SP/mock-asis.mjs
sed "s|probabilities: { \[String(pick)\]: 1 }|probabilities: Object.fromEntries(q.criteria.map((_, i) => [String(i), i === pick ? 1 : 0]))|" \
  $SP/mock-asis.mjs > $SP/mock-complete.mjs
# then run each with:  {"state":"…","questions":{"s":{"type":"score","instructions":"…",
#   "criteria":["almost-never","occasionally","often","nearly-always"]}}}
/usr/bin/grep -n "case \"score\"" -A 30 node_modules/ai/dist/index.js   # the validator
```

---

## The constants table — build the scheduled job against THIS

| constant | value | MEASURED / ASSUMED | receipt |
|---|---|---|---|
| sustained calls/min | **14.8** (146 calls / 593 s, gap-bound) | **MEASURED** | `jev-rank-20260921T050814Z.jsonl`, filename stamp → mtime |
| pilot calls/min (floor) | **12.2** (160 / 789 s, incl. per-row `find`) | **MEASURED** | `jev-pilot-20260921T024237Z.jsonl` |
| per-call round trip | **0.47–1.26 s**; ~1.05 s median implied | **MEASURED** | commit `9ee09166e` body; 593 s − 438 s sleep / 147 calls |
| inter-call gap | **3 s** (`CC_JEV_RANK_GAP` / `CC_JEV_PILOT_GAP`) — the actual binding constraint | **MEASURED** | `rank-memory.sh:141`, `pilot.sh:170` |
| "~4 calls before throttle" | 🚨 **DO NOT USE.** n=6, one burst, 2026-09-19, first-request day; does not reproduce | **ASSUMED** (was never more than n=6) | `git log -1 9ee09166e` |
| wall-clock budget formula | **`TOT × 4.1 s`** (gap + call), not `TOT/6`–`TOT/2` minutes | **MEASURED** | 146 × 4.06 s = 593 s observed |
| free-tier rate limit | **no published number; per-model; may change; honour `retry-after`** | **MEASURED** (vendor doc, 2026-09-08) | `/docs/ai-gateway/rate-limits` |
| retry trigger string | `reason == "rate-limited"` — **correct** | **MEASURED** | `GatewayRateLimitError`, `@ai-sdk/gateway:234-252` |
| terminal reasons | `unavailable · oversize · no-key · bad-spec · deps-missing · unsupported-question · invalid-response · no-model` | **MEASURED** | `evaluate.mjs:60-138`, `jev.sh:140-141` |
| retryable reasons | `rate-limited · timeout · no-output` · **the 5xx/408/409 half of `http`** | **MEASURED** | `@ai-sdk/gateway:117-121` `isRetryable` |
| `http` bucket | 🚨 **mixed — treat as terminal after 1 retry until `statusCode` is surfaced** | **MEASURED** | mock A/B: 500 and `ECONNREFUSED` both → `http` |
| abort-on-consecutive-skips | **10** (`CC_JEV_RANK_MAX_CONSEC_SKIP`) — the only dead-route brake today | **MEASURED** | `rank-memory.sh:158` |
| free window ends | **2026-09-25** | **MEASURED** (vendor promo; corroborated by search) | `bin/cc-jev:152` + vendor |
| after the window | **metered, not cut off** — $0.042/MTok in, $0.00 out; Jev is still **free-tier-eligible** | **MEASURED** | `vercel.com/ai-gateway/models/jev`, `…?freeTier=true` |
| spend guard in code | **NONE.** One display-only line; no date gate, no ceiling | **MEASURED** | `/usr/bin/grep -rn CC_JEV_FREE_UNTIL bin scripts hooks` |
| credential expiry | **none** — `rotate by 2027-03-18` is a reminder | **MEASURED** | `agent-secrets list` |
| budget-exhausted signal | **HTTP 402 `quota_for_entity_exceeded`** (≠ 429) — currently lands in `http` | **MEASURED** | `/docs/ai-gateway/rate-limits` |
| context ceiling, our route | **32,000 tokens per request (state + questions)** | **MEASURED** | `vercel.com/ai-gateway/models/jev` |
| local spec cap | **24,000 CHARACTERS over the whole spec** (not bytes, not `state`) | **MEASURED** | `jev.sh:141` `${#spec}`; `é` test |
| rank question envelope | **1,057 chars** ⇒ usable state **22,943** | **MEASURED** | rebuilt `rank-memory.sh:125-132` spec |
| corpus bytes/char | **1.0073** mean, **1.028** worst over 480 files | **MEASURED** | python over the memory dir |
| **safe cap on `state`** | **16,000 BYTES** (≈4,000–4,600 tok ≈14% of ceiling) | **ASSUMED** — rests on ~3.5–4 B/token, never measured here | record `usage.inputTokens` to convert this row to MEASURED |
| `score` usable? | **YES through our code path** — the prior "no" was a fixture defect | **MEASURED** (local A/B, no Jev call) | `ai/dist/index.js:14503-14530`; mock `:63` vs `:51` |
| `score` on the real route | **UNKNOWN** — the array-`criteria` question shape has never been sent | **ASSUMED** | worth one operator-run probe (§5) |

---

## Method warnings — three instrument errors I made or found, each cost a step

1. **`--include='*.sh' --include='*.mjs' --include='*.bats'` silently excluded `bin/cc-jev`**, which
   has **no extension**, so a grep for `CC_JEV_FREE_UNTIL` across `bin scripts hooks tests` returned
   hits from three of four directories and read as *"bin does not use it"* — the exact opposite of
   the truth (it is the **only** consumer). An extension filter is a claim about filenames, not about
   code. Grep `bin/` without `--include`.
2. **`MOCK_SCORE=2` set on the CLIENT did nothing** — the mock returned level 3 (its top) anyway,
   because the variable steers the **mock process**. That is verbatim the bug commit `a0ceab890`
   records having shipped once already with `MOCK_CHOICE`. A fixture knob set on the wrong side of
   the wire fails **silently, in the direction of "the default was fine"**.
3. **Neither JSONL schema records a timestamp, `ms`, or `usage`** — all three are already in
   `evaluate.mjs`'s return (`:107-114`) and all three are discarded before the row is written
   (`rank-memory.sh:169-170`, `pilot.sh:184-186`). Every rate figure in §1 had to be reconstructed
   from a filename and an mtime, which cannot see a mid-run pause and cannot separate call time from
   backoff time. Addendum 3 already filed the sibling defect (the fire reason missing from the pilot
   row). **Three fields — `ts`, `ms`, `input_tokens` — would make §1 and §4 direct reads instead of
   inferences.**

## Adversarial pass — what a hostile reviewer would push on

- *"Your 14.8/min could be one lucky window."* Two independent runs 26 minutes apart (12.9/min at
  02:22, 12.2/min at 02:42, 14.8/min at 05:08) plus 38+160+140 = 338 successful calls. The
  arithmetic exclusion of backoff is the load-bearing part: a **single** retry ladder is 150 s and
  the rank run had **≤81 s** of unaccounted time for 147 calls. It cannot hide one full ladder.
- *"Maybe the 2026-09-19 429s were real and the limit is bursty."* Granted, and that is exactly why
  §1 refuses to hand back a replacement constant. Both readings converge on the same build rule:
  **honour `retry-after`, back off, never pre-budget.**
- *"You proved the mock was wrong, not that `score` works on the real route."* Stated as the §5
  residual, with the untried question shape named and the probe written. The claim made here is
  narrow and exact: **the repo's stated CAUSE ("the runtime schema is stricter than the published
  type") is false**, and the evidence for it never left `127.0.0.1`.
- *"Is the cliff really benign?"* Only under two conditions this machine cannot read: no purchased
  credits, auto top-up off. Both are named in §3 as operator-owned, and a **budget** is proposed as
  the guard that makes the answer independent of them.
