---
axis: "critic — completeness review of the 9-axis usage-telemetry wave"
status: complete
date: 2026-08-16
scope: all 13 artifacts in docs/research/usage-telemetry-100p-2026-08-16/
headline: >-
  The wave measured token SHAPE exhaustively and the operator's actual meter not at all — the
  list-price-dollar → weekly_pct bridge is ASSUMED in five artifacts, tested by two, and found
  unidentifiable by both — so the wave's two largest recommendations (spend the headroom; recycle
  at 200K) point in opposite directions on the same undecided coefficient, and the one experiment
  that would settle it costs ~3 pp of one account's quota and nobody ran it.
load_bearing_claim: >-
  Cache-read's weight against the Max weekly meter is the hinge of this entire wave: A1 puts it at
  ~0 (making context re-read free and recycling quota-NEGATIVE), A3/A6/A7 price it at 0.1x input in
  list dollars (making context re-read 58-66% of the bill and recycling the largest lever). Both are
  built on, both are unverified, and they cannot both be the basis of an action.
---

# Completeness critic — what this wave did not run, and what it cannot yet answer

## Headline

**Nine axes measured what tokens the fleet moves. None measured what the operator actually spends.**
Every artifact except A1 and A2 prices work in *API list dollars*; the operator pays in
`weekly_pct` on four Max subscriptions. That bridge is crossed by a "therefore" in A3, A5, A6, A7
and A0, is graded MEASURED in most of them, and is in fact **ASSUMED** — A6's skeptic ran the
discriminating regression (§5 of `skeptic-routing-economics.md`) and found the fleet has **no
instrument that can tell the candidate meters apart** (cumulative R² 0.945 for priced-dollars vs
0.953 for output-tokens-only; a properly differenced form yields 11 movement windows in 6 days and
R² 0.13–0.16 for all four hypotheses). A1 tried and returned a boundary solution whose
unconstrained sign is negative.

That single unresolved coefficient makes the wave's two biggest recommendations mutually
exclusive, and neither author noticed, because they ran in parallel and neither cites the other.

Three further completeness failures, all of which I checked rather than asserted:

1. **The cache-write multiplier is wrong in five artifacts, and the correct value is a durably
   recorded field nobody used.** A3, A5, A6, A7 and A0 all price cache-creation at ×1.25 (the
   5-minute-TTL rate). I sampled 250 files across all four roots, deduped by `(file, requestId)`:
   **99.7% of cache-creation tokens are `ephemeral_1h_input_tokens`** (73.3M of 73.5M; the
   exchange-rate skeptic measured 85.1% on a different window). The 1-hour cache write lists at
   **2× base input, not 1.25×**. A3 named this as its own falsifier #2 and did not resolve it,
   despite the resolving field sitting in `message.usage.cache_creation` in every transcript.
2. **A7 never deduped by `requestId`, so its waste ratios are all understated ~2.1×.** Its 30-day
   base of 131.0B tokens / $107,876 is 2.14× A3's deduped 30-day figure (61.3B / ≈$50.4K). Its
   *per-turn* cost is fine ($0.1673, matching A6-skeptic's deduped $0.1696 — a clean positive
   control that only the total is double-counted), but its numerators are event-counted, so every
   "% of spend" in its ranked waste table divides a correct numerator by an inflated denominator.
   Haphazard waste is ~9% of spend, not 4.1%, and the headline ratio is ~2.6×, not 5.8×.
3. **The whole scarcity/saturation verdict rests on n=4.** I re-derived the store myself: 5,037 rows,
   four complete windows, ending 91 / 92 / 100 / 85%. That is **one window per account** from a
   6-day-old store, and it now carries the load for A0, A2-skeptic, A6, A6-skeptic and A9 —
   including the REJECT verdicts on A2's two largest recommendations.

---

## 1. What modality was not run

### The four the brief names, answered directly

| Check | Answer | Detail |
|---|---|---|
| **Did anyone read the RAW OAuth usage API response?** | **YES — A1 only, and it is the wave's best single piece of primary evidence.** | `exchange-rate.md` §"The raw payload" captures a verbatim HTTP 200 for all 4 accounts, including `limit_dollars`/`used_dollars`/`remaining_dollars` (null on Max), `spend.used = {amount_minor, USD, exponent:2}`, and nine codenamed buckets. **Not run:** nobody investigated the nine null buckets (`nimbus_quill` returns `utilization: 0.0` — populated, not null, and unexplained), nobody re-issued after a load event to see which buckets move, and nobody checked whether `seven_day_opus`/`seven_day_sonnet` ever populate. A1's own R4 proposes recording them; no one measured them. |
| **Did anyone measure the resident tax with a real tokenizer?** | **NO — and the tokenizer was available at zero quota cost.** | A4 explicitly abstained: *"tiktoken is not installed, transformers has no offline Claude vocabulary, and `anthropic.count_tokens` needs a network call on the operator's credentials."* I checked: **`anthropic` 0.105.2 IS installed and `client.messages.count_tokens` exists.** The count-tokens endpoint does not consume message quota. A4's substitute (2.70 B/token from a matched natural experiment, 0.2% residual) is *good* — arguably better than a naive tokenizer call on a different prompt assembly — but it means the wave's three published figures for the same file (**A4: 23,697 tok · A6-R6: ~6.5K tok · A6-skeptic: ~16K tok**) were never settled by the one instrument that could settle them in one call. |
| **Did anyone do the Fable-50%-weighting arbitrage arithmetic?** | **YES, twice, both refuting the arbitrage — and the more interesting half was left undone.** | A6 F7/F8: pooled 2-hour-window fit, Fable draws **1.27× Opus per list dollar** (90% CI [0.79, 1.88], P(ratio<0.75)=0.040); `accounts.json:frontier.coupling = 0.5` is measurement-consistent, and β from the weekly bucket matches β from the Fable bucket ÷ 2 to 2%. Skeptic: **1.79×**, CI [1.67, 1.90], P(<0.75)=0.000. Two estimators, disagreeing 1.4× on magnitude, agreeing absolutely on sign. **Not run:** the scheduling consequence. Fable's *sub-cap* peaked at 60/39/64/33% while `weekly_all` hit 85–100% — so **`weekly_all` binds first on every account and the Fable bucket has never been the constraint**. That one-line consequence of A6's own F10 is stated nowhere, and it means Fable routing can ignore the Fable bucket entirely. |
| **Did anyone test whether the 1-hour prompt-cache TTL is reachable from the CLI?** | **YES — A8 finding 17, and it is already on.** Two more independent confirmations exist and were never joined to it. | A8: vendor doc — *"On a Claude subscription, Claude Code requests the one-hour TTL automatically"*; `ENABLE_PROMPT_CACHING_1H` matters only on usage credits (`credits_on` False on 5,017/5,017 rows), `FORCE_PROMPT_CACHING_5M` overrides. Independent confirmation 1: A3's behavioural 65-minute miss cliff. Independent confirmation 2 (mine, and the skeptic's): `ephemeral_1h_input_tokens` is 99.7% of cache-creation. **Three instruments, one answer, zero joins** — and because nobody joined them, five artifacts still price cache-writes at the 5-minute multiplier. |

### The modalities nobody used at all

| # | Un-run modality | Which answer it would change |
|---|---|---|
| M1 | **A live quota probe.** A1 named two (falsifiers #2 and #3): a high-output/low-cache-read session, and a large-cached-context/near-zero-output session, each on a quiet account, reading the `weekly_pct` delta. Predicted cost ≈ **3 pp of one account's week**. This is the *only* experiment that separates "cache-read is free against the Max meter" from "cache-read is 66% of the bill" — the hinge in §3.1 below. Nobody ran it, in a wave whose whole subject is quota. | A1 R1, A3 R4/R5, A7 R1 (all of them) |
| M2 | **The OTel A/B.** A8's load-bearing claim — enabling `CLAUDE_CODE_ENABLE_TELEMETRY=1` costs zero prompt tokens — is INFERRED from architecture. A8 says so and calls the test cheap: N matched turns, telemetry off then on, compare `input_tokens`. Not run. The entire "telemetry that is not itself bloat" answer rests on it. | A8 R2/R3 |
| M3 | **A subagent-side cache-TTL measurement.** A8 finding 19 (vendor doc): *"the automatic one-hour TTL applies to the main conversation"* — subagents get 5 minutes and never read the parent's prefix. A3's 65-minute cliff is measured **on main-chain gaps only**. Nobody re-ran A3's miss-fraction instrument on `isSidechain` records. At the standing N=10–13 fan-out this is the difference between "the 1h TTL is universal" and "13 cold 5-minute prefixes per wave". | A3 §2, A8 R7, A6-skeptic's subagent-lane finding |
| M4 | **A quality measurement of any kind.** The operator's question (b) is "spend tokens *well*". Nine axes produced zero quality observations. A6 correctly refuses to infer quality from token shape (F6: flat visible output is iso-*length*, not iso-*quality*) and recommends two panels (R2 Opus-5 effort grid, R4 the open T5) — **both recommended, neither run**, in a wave with 374 pp of nominally idle quota and an existing blind 4-judge harness. | Everything about question (b) |
| M5 | **A `cc-offload` cloud-usage join.** Every token figure is a lower bound by an unquantified amount because 103 declared cloud sessions bill the same weekly meter and write no local transcript. A2 named the test (`GET /v1/code/sessions/<id>` → `external_metadata.usage`); nobody ran it. This biases every tokens-per-pp figure **upward**, i.e. quota is even cheaper than published. | A1 §abstentions, A2 F3, A2-skeptic §4 caveat, A0 |
| M6 | **A record-level dedupe audit across the wave.** A3, A1-skeptic, A6-skeptic and A0 dedupe by `requestId`/`message.id`. **A5, A6 and A7 dedupe by realpath only** — A6 was caught by its skeptic; A5 and A7 were not. Nobody ran the trivial cross-check (compare each artifact's fleet total against A3's deduped 62.175B) that would have caught all three in one command. | A5's 0.6–1.2%, A7's entire ranked waste table |
| M7 | **Any use of `/usage` or `/insights`.** A8 finding 14 documents that `/usage` already renders per-**skill**, per-**subagent**, per-**plugin** and per-**MCP-server** attribution — the exact "where do the tokens go by *actor*" cut A3 could not produce. Nobody ran the command once and screenshotted its output, which would have been a free ground-truth check on the whole spend census. | A3 §4, A8 R6 |
| M8 | **A second-window replication of the utilization verdict.** The store starts 2026-08-10. Four complete windows exist, one per account. Nobody looked for older evidence (A2's 19 transcript-derived account-weeks imply a fleet steady state nearer **70%** of the corrected ceiling, not 92%) and nobody reconciled the two. | §3.3 below |

---

## 2. Load-bearing across multiple axes, verified in none

Ranked by how much collapses if the claim is false.

| # | Claim | Relied on by | Actually verified? |
|---|---|---|---|
| **C1** | **The Max weekly meter is denominated in API-list-dollar-equivalent** (so cache-read costs 0.1×, cache-creation 1.25×, output 25×, and a cost decomposition in dollars is a statement about quota). | A3 (entire cost column + R4/R5), A5 (every $ figure + the 0.6–1.2% verdict), A6 (F1 → R1, R3, R6), A7 (the crossover rule, the ranked waste table), A0 (the $2,960/window figure). | **NO.** A1's fit *prefers* a monetary unit but cannot exclude output-only (R² 0.764 for the single dollar scalar vs 0.697 for output-only). A6-skeptic ran the direct comparison and reports the meters are **indistinguishable with this instrument**. A5 states plainly *"Do not read 0.6–1.2% as 0.6–1.2% of the weekly allowance"* — and then the wave reads all of them exactly that way. **Status: ASSUMED in 5 artifacts, graded MEASURED in most of them.** |
| **C2** | **Cache-read is ~free against the weekly meter** (`opus_cr = 0.0000`). | A1 headline + R1/R2, A0's addendum ("96% of tokens cost 0% of quota — the single most decision-changing result in the wave"). | **NO — it is a boundary solution.** A1-skeptic §4: the unconstrained OLS estimate is **negative** (−0.0032; ridge −0.008…−0.012), `cond(X)=62,433`, `corr(out,cr)=0.906`, and cache-read *alone* explains R²=0.353 of weekly-pp variance. NNLS pins it at zero because the constraint forbids negative; that is not a measurement of zero. And A1's own finding #15 (dollar-weighting is the best single-parameter model) implies cache-read is **66% of the bill** — the artifact endorses two findings that contradict each other, for an R² gap of 0.06. |
| **C3** | **The fleet's steady state is 85–100% weekly utilization** (⇒ there is no headroom to spend). | A0 headline, A2-skeptic's REJECT of R1/R5, A6 F10 + R5, A6-skeptic ("best-verified finding in the artifact"), A9 headline. | **PARTIALLY — n=4, one window per account, from a 6-day store.** I reproduced it exactly (91/92/100/85, four roll events, each advancing the anchor by exactly 7d). But every author treats one observation per account as the steady state. A2-skeptic names this as its own falsifier #2 and it remains open; A6-skeptic adds the qualification the others omit — `next3` is at 21% five days into its *current* window, so utilization is **non-stationary**, and a 6-day scarcity verdict is as much a snapshot as the 1–4% reading it corrects. |
| **C4** | **Cache-creation is priced at ×1.25.** | A3, A5, A6, A7, A0 — every cost column in the wave. | **NO, and it is refuted by a durably recorded field.** Measured by me: `ephemeral_1h_input_tokens` = **99.7%** of cache-creation (n=14,662 deduped events across 250 files / 4 roots); A1-skeptic independently measured 85.1% on its window. The 1-hour write lists at **2×**. Correcting A6-skeptic's deduped decomposition: cache-creation rises 23.4% → **~32.9%** of an Opus-5 message's marginal cost, cache-read falls to ~57.6%, output to **~9.5%**. Direction of A6's conclusion strengthens; every published magnitude moves. |
| **C5** | **A7's crossover constant `p_cw/p_cr = 12.5`.** | A7 R1 — the recycle decision rule proposed for `CLAUDE.md` § Context Stewardship. | **NO — it is C4 in disguise.** At the true 1-hour rate the ratio is **20**, and `R*` is linear in it: at 200K occupancy `R*` goes 9.4 → **13.2**; at 400K 4.9 → **6.5**. The published thresholds ("≥250K ⇒ recycle if ≥8 turns remain") are ~35% too aggressive *before* considering C2, which may invert the rule entirely (§3.1). |
| **C6** | **A5's telemetry share, 0.6–1.2% of throughput.** | A5 headline + R5/R6 ("do not pursue injection-byte savings"); the wave's answer to operator question (c). | **NO — numerator and denominator are on different bases.** A5's denominator (98,367 "turns", $20,435) is record-summed and therefore ~2.2× inflated; its numerators (305 forced-turn *events*, per-session injection bytes) are event-counted. Rebasing the denominator alone puts telemetry nearer **1.4–2.6%**. The conclusion ("not eating the budget") survives with a much thinner margin than published, and A5's own falsifier #1 says the headline inverts at ~10×. |

---

## 3. Where two axes contradict each other

### 3.1 — THE contradiction: is context re-read free, or is it the whole bill?

| Side | Claim | Action it licenses |
|---|---|---|
| **A1 + A0** | Cache-read = **0.0 pp/Mtok**. 96% of tokens cost 0% of quota. *"Removes the standing incentive to trim context."* | Grow contexts. Never recycle for cost. Spend on fan-out. |
| **A3 + A6 + A7** | Cache-read = **58–66% of marginal cost**. A7 simulates a 22.3% saving from recycling at 200K and proposes it as a rule in `CLAUDE.md`. | Recycle aggressively at a token-absolute threshold. |

These are not two framings of one fact. On the operator's actual meter, **a recycle converts free
cache-read into charged cache-creation**: it pays `(T+B)` fresh cache-creation tokens — the
second-most-expensive class under A1 — to avoid cache-read tokens that A1 says cost nothing. If A1
is right, A7's R1 is not a 22.3% saving, it is a **quota-negative** policy whose entire measured
benefit is denominated in a currency the operator does not spend.

Neither artifact cites the other. A1 R1 and A7 R1 would both be landed in `CLAUDE.md`
§ Context Stewardship, where they would contradict each other in adjacent paragraphs.

**Which side has better evidence: neither, and that is the finding.** A1's zero is a constrained
boundary vertex with a negative unconstrained estimate. A3/A6/A7's 0.1× is Anthropic's published
*API* multiplier applied to a *subscription* meter — assumption C1. The deciding experiment is
A1's falsifier #3 (replay a large cached context with near-zero output on a quiet account; A1
predicts ≈0 pp, the list-dollar model predicts ~1 pp per 2B cache-read tokens). It costs a few
percentage points of one account's week. **Nothing in this wave should be landed on either side
until that probe runs.**

### 3.2 — "Spend the standing headroom" vs "the fleet is at 92%"

| Says spend more | Says the fleet is near-saturated |
|---|---|
| A1 R2 — *"374 pp ≈ 292M output tokens ≈ $27.5K expiring in 2–7 days"* | A0 headline — four windows ended 91/92/100/85% |
| A3 R7 — *"every account's weekly pace reads BEHIND (3/1/18/3%)"* | A2-skeptic — R1 and R5 would consume **26–74×** the remaining headroom and wall the fleet in 1.5–2 days |
| A7 R5 — *"the actual defect this window is underspend — every account's weekly reads 1–18%"* | A6 F10 + R5, A9 §5 — the point-in-time readout understates by up to 89 pp after a stagger |
| A2 R1/R5 — unpark the venue filter (+168–480 M/day), 24/7 recycling lane | |

**The saturation side wins decisively.** It is meter-native (Anthropic's own counter, not a token
proxy), it is anchored on four observed roll events, and it was independently reproduced by five
agents including two skeptics. I reproduced it again: 5,037 rows, roll events at exactly +7d, and
the terminal readings 91/92/100/85 — with `next3` sitting at **exactly 100 for 11.2 hours**.

The failure mode here is structural, not individual: **three artifacts wrote "spend the headroom"
recommendations from the same false premise in the brief, at the same time as three others were
refuting it.** A1's R2 survived its own skeptic review ("KEEP — renumber") because the skeptic
attacked the *quantity* (292M → 45–135M) and not the *premise*.

### 3.3 — Is 92% the steady state, or a recent spike?

A2's transcript history: fleet daily burn median **62.5 M/day** over 34 days ⇒ ~437 M/week fleet.
A2-skeptic's corrected per-account cap: **143–178 M/account-week** ⇒ ~620 M/week fleet ceiling.
That implies a 34-day steady state near **70%**, not 92%. Both figures are in the wave; nobody put
them beside each other. Unresolved, and it decides whether ~8 pp/account-week is the entire prize
(A2-skeptic's R8 promotion) or whether there is a real 30% gap in the longer run.

### 3.4 — Three values for one file

The duplicated `CLAUDE.md`: **A4 = 23,697 tokens** (2.70 B/token, natural experiment, 0.2%
residual) · **A6 R6 = ~6.5K tokens** (citing `opus5-adaptation` at "94% / 356 of 377 lines /
25.8 KB") · **A6-skeptic = ~16K tokens** (correctly finds the files byte-identical at 63,983 B,
then converts at ~4 B/token). A4 has by far the best evidence and A6's premise is stale. A6-skeptic
also lands the one point A4 understates: the correct action is to **stop the second load without
destroying the versioned mirror**, and A4's R1 already names the silent-skip hazard in
`scripts/deploy-parity-assert.sh:731,742`. Settleable in one `count_tokens` call.

### 3.5 — A2's "binding constraint" label

A2 F11 calls the cloud-only venue filter *"⛔ THE BINDING CONSTRAINT"*. Its skeptic reproduced every
underlying number (743 parked records, exit 3, exit 126) and rejected the label: *you cannot be
constrained out of a resource you already spend 92% of.* Skeptic wins. The venue filter is a real
throughput defect on a different axis, and A2's R2 (dispatcher liveness) survives untouched.

---

## 4. What the operator's three-part question still does not have an answer to

### (a) Maximize the weekly limits across accounts — **partially answered; the number is not converged and the renderer does not exist**

What is known: the meter is a monetary unit; a durable 6-day series exists; the last complete
windows ended 85–100%; resets are staggered; the EDF router already scores correctly.

What is not:

- **The ceiling.** Five estimates for one quantity: 86 M weighted tok/account-week (A2, then
  abstained) · 143–178 M (A2-skeptic) · 78 M Opus-output-equivalent (A1) · 33–41 M (A1-skeptic) ·
  26 M (A0's 2.99× recalibration). A **~5× spread**, unreconciled, and no artifact attempts the
  reconciliation. You cannot plan against a ceiling you know to a factor of five.
- **Whether 92% is steady state** (§3.3).
- **The renderer.** A9 R1 and A0's burn-ratio proposal are the same fix and neither is built:
  `claude-accounts --readout` still shows a raw point-in-time percentage that inverted this
  investigation's premise. Until it exists, every future session re-derives this from 7 GB.
- **The scheduling problem nobody formulated.** Four staggered windows + a per-wave cap of 2
  items/account (`CC_WAVE_MAX_PER_ACCT`) + an account fixed at process launch (A2 F17) = a
  deadline-constrained placement problem. A2 R3/R4 and A2-skeptic's counter-proposal are opposite
  heuristics; nobody wrote down the objective.

### (b) Spend tokens well, without penny-pinching or cutting quality — **NOT ANSWERED, and not answerable from what was measured**

This is the blunt one. **Nine axes produced zero observations of output quality.** Every "spend
well" claim in the wave is a claim about token *shape* — mutations per Mtok, input:output ratios,
thinking-token proxies — and A6 is explicit that shape cannot license a quality conclusion (F6),
while A6-skeptic shows the one quality-adjacent metric attempted (thinking tokens) goes **negative
on three of five effort rungs** and is not identified at all.

Compounding it: **the value side has no instrument.** `cc-value` attributes 0 of 470 commits
because its `Session-Id:` trailer was measured extinct on 2026-08-12 and two sibling consumers were
fixed while it was not (A9 §4b). Only 4.0% of commits carry a joinable trailer (A3 §3). A3
substituted file-mutation counts and correctly graded the inference; A7 substituted backlog-ledger
closures. Neither is a quality measure.

So the honest state of (b): *we know the token shape precisely and we know nothing about whether
the tokens bought anything.* The two probes that would start answering it (A6 R2's Opus-5 effort
panel, A6 R4's T5 Opus-5-vs-Fable-at-matched-effort) were recommended by both the axis and its
skeptic, cost ~1 pp of quota each, and were not run.

### (c) Telemetry that is not itself bloat — **best answered of the three, with two caveats**

A8 found the right shape (native OTel, 8 metrics / 15 events, out-of-band, enabled in 0 of 5 config
dirs) and A5 measured the incumbent's own cost. Caveats: the zero-token claim is INFERRED and its
A/B was not run (M2); and A5's share is mis-based (C6) and expressed in list dollars rather than
quota, so the wave's answer to (c) is *"telemetry is a small share of a currency the operator does
not spend."* A5 could have joined to `account-utilization.jsonl` — five other axes found it — and
did not, because it accepted the brief's false premise (its finding 23 cites the brief as the
evidence for the absence, with no positive control).

---

## 5. Recommendations that would cut quality

The operator rule is absolute. Four candidates; two are real.

| Rec | Verdict |
|---|---|
| **A2 R1 (unpark the venue filter) and A2 R5 (24/7 self-recycling lane)** | **REAL VIOLATIONS — already caught.** A2 grades both LOW risk; its skeptic shows their own stated effects are 26–74× the remaining weekly headroom and would wall all four accounts within ~2 days. A weekly wall is unrecoverable inside the window, kills in-flight work (the repo ships `limit-recover` for exactly this), and `next3` demonstrated it for 11.2 hours. That is a **quality event caused by a throughput optimization** — the forbidden trade in an unfamiliar costume. Quality risk is HIGH, not LOW. Correctly rejected; recording it here so the verdict travels with the wave. |
| **A6 R3 (raise the reasoning floor to `xhigh`)** | **REAL VIOLATION, in the direction nobody guards.** Labelled `quality_risk: NONE` while being an unproven quality *change*. Its factual basis (F3's "+33% thinking") is refuted by its skeptic under two sampling defects; the SSOT itself records that Opus 5 `max` is *"prone to overthinking"* and that quality is **not monotone in effort** on this model; and the repo's one certified effort probe found `xhigh` *regressing* (a fabricated diff against a non-existent file). A6's own N5 forbids this — but N5 is written asymmetrically ("never adopt a **cheaper** model or effort on an unproven iso-quality claim") and R3 walked through the gap. **Make N5 symmetric.** |
| **A7 R1 (token-absolute recycle rule in `CLAUDE.md`)** | **NOT a violation as argued, but it is the most dangerous recommendation in the wave.** A7 is careful — it forbids selling R1 as a saving, cites the Hold test, grades MEDIUM below 250K, and names the unrun A/B (turn inflation ≥1.4× at C=200K inverts it) as its top falsifier. But: its crossover constant is wrong by 60% (C5), its saving may be denominated in a free currency (§3.1), and its own T (62,543) is a median that a handoff-fired worker with a long brief exceeds by 2–3× — A7's falsifier #5 says the rule would then be wrong *specifically for dispatched workers, the population that recycles most*. Landing a token-absolute threshold into always-resident policy, on a constant derived from an unverified meter, is how a cost model becomes a quality rule by accident. **Do not land R1 until M1 and A7's own A/B run.** |
| **A3 R1 / R2 / A9 R5 (delete `cache-expiry-warning.sh`)** | **NOT a violation — the opposite.** The hook currently injects *"Consider /clear or /compact to reduce token cost"* into model context on a falsified 5-minute premise, ~85% false-positive, on a per-account file any sibling clobbers. It is a standing instruction to make the forbidden trade. Deleting it raises the floor. Independently reached by A3 and A9. |

---

## 6. The single highest-value thing this wave found

**`~/.claude/logs/account-utilization.jsonl` exists — 5,037 rows, four accounts, six days, written
free by a sweep already paid for — and its four roll events show the fleet finishing its last
complete weekly windows at 91 / 92 / 100 / 85%, which inverts the goal's founding premise from
"we are under-utilizing, spend more" to "we are near-saturating, and the failure mode is a wall".**

Why it beats the runners-up:

- **It changes the sign of the program, not the size of a number.** Four artifacts wrote
  "spend the headroom" recommendations; two of them (A2 R1, R5) would have walled all four accounts
  within two days of landing. Under the operator's absolute rule, preventing a quality event
  outranks capturing a token saving.
- **It is meter-native.** Every other headline in this wave is a token proxy joined across an
  unverified bridge (C1). This one reads Anthropic's own counter, sampled 1,256 times.
- **It cost nothing to find and costs nothing to keep.** No new collector, no new network call, no
  new quota. A9 R1 (render the completed-window statistic) and A0's burn-ratio are ~80 LOC over
  data already on disk. Retention is safe: `rotate-autonomy-logs.sh` triggers at 25 MiB against
  1.38 MB after six days — roughly 113 days to first rotation, 8 kept.
- **Runner-up, and why it loses:** A4's duplicated `CLAUDE.md` — 23,697 tokens on 83.5% of
  sessions, quality risk NONE *by construction* (the bytes removed are md5-identical to bytes that
  remain). It is the best *action* in the wave and should be landed first. It loses the top slot
  because it makes every session cheaper without changing what the telemetry programme is for,
  and because its magnitude is still one `count_tokens` call away from being settled.
- **Second runner-up:** the record-level duplication trap (one API response written as up to 8
  transcript lines, mean 2.37). It corrected A1's headline by 2.2×, A6's cost decomposition, and —
  uncaught — A5's and A7's totals. It is the highest-leverage *methodological* finding, but it
  changes numbers, not direction.

---

## 7. What would falsify this critique

1. **C4 is the load-bearing measurement I added.** If `ephemeral_1h_input_tokens` is *not* billed at
   the 2× 1-hour rate on subscription requests — e.g. if Anthropic prices subscription cache-writes
   flat regardless of requested TTL — then ×1.25 is right, C4 and C5 both fall, and A7's crossover
   is correct as published. Test: Anthropic's pricing page for the 1-hour cache multiplier, plus one
   probe request with a known TTL against the credits meter.
2. **My A7-duplication inference is arithmetic, not a re-run.** I infer it from A7's 131.0B/30d
   against A3's deduped 61.3B/30d and from the absence of any `requestId`/`message.id` dedupe in
   A7's method. If A7 deduped and did not say so, its ratios stand as published. Settled by one
   re-run of A7's extractor with a dedupe key.
3. **§3.1 assumes recycling pays cache-creation at the charged rate.** If a recycled session's cold
   prefix is served from a machine-level cache it does not re-write, the quota-negative claim
   weakens. A8 finding 20 says the opposite (cache is scoped per-machine *and* per-directory,
   worktrees included), which is why I state it as I do — but I did not measure a recycle's actual
   cache-creation cost.
4. **The n=4 objection cuts both ways.** If windows 5–8 come in at 40–60%, C3 falls, the
   saturation verdict weakens, and A1 R2 / A3 R7 / A7 R5 regain their footing. The store already
   does the work; this needs four weeks of retention and nothing else.
5. **I did not re-run any axis's primary extraction.** My verifications are: the utilization store
   (full re-parse, 5,037 rows, per-window min/max), the ephemeral cache-creation split (250-file
   sample, 14,662 deduped events), the tokenizer availability check, and the rotation retention
   parameters. Everything else in this document is cross-reading of the thirteen artifacts against
   each other, which is exactly the modality none of them could run on themselves.
