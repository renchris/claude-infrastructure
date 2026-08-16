---
axis: "skeptic-routing-economics — adversarial review of A6 (model/effort routing economics)"
target: docs/research/usage-telemetry-100p-2026-08-16/routing-economics.md
verdict: SURVIVES-NARROWED
date: 2026-08-16
one_line: "The cost-shape half reproduces and even strengthens (output is 10.8%, not 13.1%, of an Opus-5@high message once you stop counting one API response up to 8 times); the effort-ladder half is refuted outright — the 5.6x and the xhigh>max ordering are artifacts of two compounding sampling defects, and deduped across the full corpus xhigh produces FEWER output tokens than high, which kills R3."
---

# Skeptic — A6 routing economics

## Verdict

**SURVIVES-NARROWED**, with the headline's two numbers refuted and its policy conclusion intact.

The load-bearing claim is a conjunction. Taken apart:

| Conjunct | Verdict |
|---|---|
| "Output tokens are 13.1% of the marginal cost of an Opus-5 turn (cache read 62.7%, cache creation 24.1%)" | **SURVIVES, corrected to 10.8% / 65.7% / 23.4%.** Reproduced on an independent seed; the correction makes the artifact's point *more* strongly. |
| "therefore effort, which moves **ONLY** output tokens, cannot be a material cost lever" | **NARROWED.** "Only" is false — a persisted output token is re-read as cache on every later turn of the session (measured slope 2.00, median 66 messages/session). Repricing for that roughly doubles output's share to ~19–32%. Still a minority; still not the dominant lever. |
| "the whole low→xhigh ladder spans a 14-point cost band at fixed context **while spanning 5.6x in thinking tokens**" | **REFUTED.** The 5.6x does not reproduce. It is an artifact of (a) counting one API response as up to 8 "turns" and (b) excluding 51% of the corpus. Deduped over the full corpus the ladder is **non-monotone**: xhigh yields the *fewest* output tokens of the top three rungs. |
| Headline: "the Fable 50% arbitrage is refuted" | **SURVIVES and strengthens.** My independent estimator puts Fable's quota draw per list-dollar at **1.79× Opus (90% CI [1.67, 1.90], P(ratio<0.75)=0.000)** — a much harder refutation than the artifact's 1.27 [0.79, 1.88], though the two point estimates disagree by 1.4×. |
| Headline: "the idle-lane premise is a post-reset snapshot artifact (91/92/100/85%)" | **SURVIVES exactly.** Reproduced to the percentage point. The best-verified finding in the artifact. |

The operator-facing conclusion — *never downgrade effort to save quota* — survives every attack.
What does **not** survive is the artifact's own inversion of it, **R3 (raise the floor to xhigh)**,
which is REJECT.

---

## 1. The two sampling defects, and how they compound

### Defect A — one API response is counted as up to 8 "turns"

Claude Code writes **one JSONL record per content block**, and each record repeats the
**identical, full `usage` object** for the whole API response.

```
$ python3 /tmp/… (60 random top-level transcripts, grouped by message.id)
records-per-message.id histogram: {1: 872, 2: 765, 3: 1553, 4: 223, 5: 28, 6: 10, 7: 3, 8: 3}
total message.ids 3457   multi-record ids with IDENTICAL output_tokens: 2585 of 2585
example: msg_011Cdrdc4kWPup5PshDEc4qR →
  [333, ["text"]]  [333, ["tool_use"]]  [333, ["tool_use"]]      ← 333 output tokens, counted 3×
```

Mean **2.37 records per API response**, and the factor is **cell-dependent** (measured
records/message: opus-5 `low` 1.77 · `high` 2.11 · `xhigh` 2.28 · `max` 2.34 · opus-4-8 `xhigh`
4.72). Because it varies by cell, it is not a common scale factor that cancels — it differentially
inflates exactly the cells being compared.

Worse for the thinking derivation: on a 3-record response, `output_tokens` is summed 3× while the
`text` chars are summed once and each `tool_use` JSON once. The estimator
`thinking = output − visible/3.6` therefore inherits a ~2.4× inflation on its first term and none
on its second. *(The repo memory `token-usage-from-transcripts` records the symlink double-count
trap; the artifact avoided that one and walked into this one, a level down.)*

### Defect B — 51% of the corpus was never opened

```
$ for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do …
/Users/chrisren/.claude              depth2=860  all=1816
/Users/chrisren/.claude-secondary    depth2=874  all=1703
/Users/chrisren/.claude-tertiary     depth2=791  all=1906
/Users/chrisren/.claude-quaternary   depth2=880  all=1566
                                     ---- 3405        7002
```

The artifact's stated universe is "~3,404 jsonl", and a `projects/*/*.jsonl` glob at seed 11 draws
**1,191** files — the artifact reports **1,190**. That is a byte-level identification of its glob:
it scanned **top-level session files only** and never opened `subagents/` (**3,597 files**, more
files than the top level).

Consequences the artifact reports as findings:

- *"`isSidechain` was absent on 157,058 of 157,058 assistant records, so I could not split lead vs
  subagent spend. Reported as null rather than imputed."* — the honest label is right, the cause is
  not. Subagent records are in the directory the scan skipped.
- **F13** (Sonnet "0.34% of turns") and **F18** (Haiku "0.06% of output") are computed on a
  population that structurally under-samples the exact slots those models are routed to. Measured
  model share by location (400-file samples, deduped by `message.id`):

  | population | files | messages | opus | fable | sonnet | haiku |
  |---|---|---|---|---|---|---|
  | top-level (what the artifact scanned) | 3,405 | 23,826 | 93.19% | 6.33% | **0.03%** | 0.27% |
  | `subagents/` (never opened) | 3,597 | 7,936 | 94.62% | 2.28% | **2.53%** | 0.42% |

  Sonnet's share is **84× higher** in the half that was excluded. The direction of F13's conclusion
  survives (Sonnet is still small fleet-wide) but its number does not, and the stated coverage
  ("35% file sample … 1,190 of ~3,404") is really **17% of 7,002, non-randomly missing the subagent
  lane**.

### Compounded: reproducing the artifact, then correcting it

Same pipeline, seed 11, `thinking = output − visible/3.6`:

| model\|effort | **depth-2 only (reproduces the artifact)** | **all depths, deduped by message.id** |
|---|---|---|
| opus-5 `low` | — (cell too small to rank) | **257** |
| opus-5 `medium` | 597 | **535 → deduped 191** |
| opus-5 `high` | 903  *(artifact: 884)* | **770 → deduped 408** |
| opus-5 `max` | 1,037 *(artifact: 1,058)* | **992 → deduped 632** |
| opus-5 `xhigh` | **1,173** *(artifact: 1,173 — exact)* | **565 → deduped 11** |

The depth-2 column lands on the artifact's numbers, including `xhigh = 1,173` **exactly**. Fixing
either defect alone moves `xhigh` below `high`; fixing both leaves `xhigh` at the bottom of the top
three. **F3 ("xhigh produces MORE thinking than max — the enum's nominal ceiling is not the
observed ceiling") is refuted**, and with it the "5.6×" that the headline is built on.

---

## 2. The thinking estimator has no floor — it goes negative

The artifact treats insensitivity to the chars→token divisor as robustness: *"the ratios are stable
across divisors 3.0–4.4 … because visible output is only 10–15% of `output_tokens`."* That is not
robustness. It means the subtracted term is negligible, i.e. **the estimator is `output_tokens`
with a ~4% shave, relabelled "thinking"** — and every claim about "reasoning depth" is a claim
about output volume.

The divisor was never calibrated. It can be, with a positive control the artifact did not run:
messages whose `content` contains **no `thinking` block at all**. On those, by the artifact's own
model, `visible_chars / output_tokens` should be ≈3.6.

Measured (deduped by `message.id`, all depths):

| model\|effort | calibration n (zero-thinking msgs) | measured chars/output-token | assumed |
|---|---|---|---|
| opus-5 `high` | 13,328 | **2.21** | 3.6 |
| opus-5 `max` | 9,431 | **2.05** | 3.6 |
| opus-5 `xhigh` | 2,449 | **2.76** | 3.6 |
| opus-5 `low` | 174 | **1.87** | 3.6 |
| opus-4-8 `xhigh` | 1,097 | **8.44** | 3.6 |

Substituting each cell's *measured* divisor, "thinking tokens per message" for Opus-5 becomes:
`low −237` · `medium 7` · `high 206` · `max 404` · `xhigh −118`.

**Three of five rungs are negative.** A quantity that goes negative on the majority of its cells
cannot support a "5.6× lever on reasoning depth" headline, and the per-cell divisor spread
(1.87–8.44) shows the estimator is not identified at all. The correct status for every absolute
thinking figure in the artifact is not INFERRED — it is **not recoverable**, which is what
ABSTAIN-never-impute requires.

*(F16 — thinking text is stripped to `""`, only the signature survives — is correct and I confirm
it. The artifact drew the right conclusion, that thinking must be derived; it then derived it with
an uncalibrated constant, which is the same class of error as the imputation
`CONTEXT_ECONOMY_V2` had to withdraw.)*

---

## 3. F1 reproduces — and improves against the artifact

Independent scan, **seed 97** (the artifact used 11), 2,450 of 7,002 files, all depths:

| | artifact (n=65,904 "turns") | mine, block-level (n=82,025) | mine, **deduped by message.id** (n=36,489 messages) |
|---|---|---|---|
| fresh input | 0.05% | 0.05% | **0.05%** |
| cache creation | 24.1% | 26.46% | **23.44%** |
| cache read | 62.7% | 61.18% | **65.72%** |
| **output** | **13.1%** | 12.31% | **10.80%** |
| $/unit | $0.1970 | $0.1848 | $0.1696 |

Priced from `model-config.yaml:pricing_per_mtok` `claude-opus-5: [5, 25]`, cache-write ×1.25,
cache-read ×0.1 — verified at `model-config.yaml:151`.

The decomposition is a ratio, so the duplication factor largely cancels; deduping shifts output
**down** to 10.8%. **F1 survives, and the artifact understated its own case.** `n=65,904 turns`
should read *n ≈ 27,800 API responses*.

F9 also reproduces: deduped, Fable-5@max **$0.5549/message** vs Opus-5@high **$0.1696** = **3.27×**
(artifact: 3.1×).

---

## 4. The mechanism the axis assumed away: "effort moves ONLY output tokens"

An output token that persists in the conversation is re-read as *cache* on every subsequent turn.
Measured within-session, Opus-5 only, deduped, 211 sessions with ≥25 Opus-5 messages:

```
within-session slope d(cache_read)/d(cumulative_output):  p25=1.68  median=2.00  p75=2.38
opus-5 messages per session:  p25=40  median=66  p75=134  p95=273
```

Taking a conservative causal share of 1.0 (the slope of 2.00 is **confounded** — cumulative output
co-moves with cumulative tool-result volume, so it is an upper bound), the marginal cost of one
extra Opus-5 output token is:

```
  25.00 $/Mtok   output
+  6.25 $/Mtok   cache creation (written once, at 1.25× $5)
+  0.50 $/Mtok × (remaining messages in session)   cache read
```

At the median 66 messages/session (≈33 remaining) that is **$47.75/Mtok — 1.9× the $25 the artifact
priced**; at p75, 2.6×; at p95, 4.0×. Repricing output at 1.9× moves its share from 10.8% to
**≈18.8%** (p75 ≈24%, p95 ≈32%).

**Unresolved and load-bearing:** whether *thinking* tokens specifically are re-sent across turns, or
stripped by the harness. Visible text and tool_use JSON certainly persist; if thinking does not,
the amplification does not apply to the effort lever itself. I could not settle this from
transcripts (thinking text is stripped locally, F16) and I **abstain** rather than impute. Either
way the flat assertion "effort moves ONLY output tokens" is not established, and it is doing real
work in the headline.

Direction of the correction: output's share roughly doubles, the ladder's cost band roughly
doubles, and the qualitative conclusion — *cache, not output, dominates* — **still holds**.

---

## 5. The bridge from list dollars to the operator's actual constraint is unmeasured

F1 is arithmetic over **list-price dollars**. On four Max subscriptions the operator does not spend
dollars; he spends **weekly_pct**. Every "therefore" in the artifact crosses that bridge, and the
crossing is assumed.

The artifact names this itself as falsifier #1 — *"if plan quota is metered on something other than
dollar-equivalent list price, e.g. on output tokens alone — then output is not 13.1% of marginal
cost, effort IS a material cost lever, and R1/R3 invert"* — and did not run it. I ran it.

Within-reset-segment cumulative fits of `weekly_pct` against each candidate meter (966 points,
4 accounts, transcripts deduped by `message.id`):

| meter hypothesis | pooled slope | pooled R² |
|---|---|---|
| priced $ (cache-read ×0.1) | 0.0257 | 0.9451 |
| **output tokens only** | 6.8218 | **0.9455** |
| **output $ only** | 0.2501 | **0.9531** |
| input-ish tokens (in+cc+cr) | 0.0195 | 0.8992 |
| all tokens, equal weight | 0.0194 | 0.8994 |

A 2-hour-differenced form (the artifact's design) yields only **11 windows with any movement** in
6 days — R² 0.13–0.16 for all four hypotheses, indistinguishable.

**Neither form can discriminate the metering basis.** The cumulative form is spurious-regression
prone (all series are monotone in time), so the fact that *output-only fits marginally best* is not
evidence for it — it is evidence that **the fleet has no instrument that can tell these apart**.
The honest status of "output is 13.1% of marginal cost, *therefore* effort is not a cost lever" is
therefore: **MEASURED in list dollars, ASSUMED in quota.** The artifact labels the whole chain
MEASURED.

This does not overturn the policy conclusion (see §7), because under *either* meter you should not
trade effort for cost. It does overturn the confidence, and it is the single measurement most worth
buying: the artifact's own proposed test — one 5-hour window of Opus-only vs Fable-only load at
matched volume on idle accounts — would settle both this and the Fable ratio.

---

## 6. What reproduced exactly

**F10 — the utilization peaks.** Reproduced to the point, segmenting on `weekly_reset_at` at hour
precision (the raw field carries sub-second jitter that fragments naive segmentation):

```
next   resetHR=2026-08-16T04 peakW= 91 peakF= 60 n=694
next2  resetHR=2026-08-15T11 peakW= 92 peakF= 39 n=476
next3  resetHR=2026-08-11T12 peakW=100 peakF= 64 n=124   ← hit the wall
next4  resetHR=2026-08-16T09 peakW= 85 peakF= 33 n=709
next   resetHR=2026-08-23T04 peakW=  3   (post-reset — the brief's 1-4% readings)
```

**F11 — the time-series store exists.** `~/.claude/logs/account-utilization.jsonl`, 1,378,853 B,
**5,025** records (the artifact said 5,013 — it has grown since). The brief's "no usage TIME-SERIES
store was found" is wrong and the artifact is right to say so.

**One qualification the artifact should carry.** `next3`'s current cycle (reset 2026-08-18) peaks
at **19–20%** five days in, against 100% last cycle. Scarcity is real but **not stationary**: F10
proves the *snapshot* is uninformative, which cuts against a 6-day scarcity verdict too. The
artifact's own falsifier 5 says this; it should be promoted into F10 rather than left at the end.

**F4, F6, F14, F15 — documentary.** Verified verbatim: `model-config.yaml:effort_defaults.default`
does say *"the guide's STARTING POINT, not a measured optimum"*; `~/.claude/commands/research.md`
does carry the ~15%-pricier Sonnet line; the freewin probe does carry the 2026-07-01 CRITICAL
CORRECTION and an open T5. All survive.

**F7's conclusion.** My estimator disagrees on the number and agrees hard on the verdict:

```
alpha (pp per Opus list-$) = 0.02338 ; beta (pp per Fable list-$) = 0.04182 ; beta/alpha = 1.79
bootstrap: median 1.79  90% CI [1.67, 1.90]  P(ratio<0.75)=0.000
corr(Opus$, Fable$) = 0.576
```

(My CI is over-tight — cumulative points inside a segment are serially correlated and the naive
bootstrap ignores it. Treat the *interval* as the artifact's, the *sign* as jointly confirmed by two
independent estimators.) **There is no 50% Fable discount.** F7 and F8 stand.

---

## 7. Per-recommendation verdicts

| # | Verdict | Why |
|---|---|---|
| **R1** — delete effort from the cost conversation, in writing | **KEEP — NARROWED** | The prohibition is right and quality-safe. But the comment block must **not** carry "5.6×" or "14-point band" (§1–2, refuted) and must not assert the quota claim as measured (§5). Correct wording: *output is ~11% of an Opus-5 message's priced marginal cost and ~19–32% once context amortization is counted; effort is therefore never a first-order cost lever, and its quality direction on Opus 5 is uncertified in both directions — so no effort change may be justified on cost grounds, up or down.* |
| **R2** — run the owed Opus-5 effort panel | **KEEP — strengthened** | My refutation makes this the *only* way to learn anything about the ladder: the observational corpus cannot answer it (non-monotone, confounded by task selection, and the thinking metric is not identified). Narrow one number: the "≈0.5–1 weekly pp" cost comes from F17, whose two estimators disagree by 1.7× and which is INFERRED; with accounts peaking at 85–100%, budget the panel from a measured pilot, not from `100/α`. |
| **R3** — raise the reasoning-slot floor to `xhigh` | **REJECT** | Three independent kills. **(a) Its factual basis is the artifact's own worst number.** "xhigh buys +33% thinking" is F3, which is an artifact of both sampling defects; deduped across the full corpus xhigh produces **fewer** output tokens than high (437 vs 733/msg) and its calibrated thinking estimate is **negative**. **(b) It contradicts the vendor evidence already in the SSOT.** `model-config.yaml:effort_defaults` records, from the Opus 5 system card and migration guide: *"`max` is 'prone to overthinking' and shows self-correction / re-verification loops at high effort (FrontierCode peaks at MEDIUM; FrontierBench best at xhigh, max within-noise). low/medium are STRONGER on Opus 5 than any prior Opus."* Quality is **not** monotone in effort on this model — so "more thinking, not less" is not a safety argument. **(c) The repo's one certified effort measurement points the other way.** T1 found xhigh *regressing*: on mechanical-search it "HALLUCINATED a fabricated diff against a non-existent file". The artifact cites this at F4 and then recommends its opposite. Under the operator rule, a change that **may** cut quality is rejected whatever it buys — and this one is labelled `quality_risk: NONE` while being an unproven quality change. It should be reclassified **HIGH**. |
| **R4** — close T5, reseat the Fable slots if Fable trails | **KEEP** | Best-supported action in the artifact. Fable's realized 3.27× premium reproduces, the 50%-discount defence is dead under two independent estimators, and T4 already has Opus-5 ahead at unequal effort. No quality cut: the probe's decision rule rejects any config that loses. |
| **R5** — correct the idle-lane premise everywhere | **KEEP** | F10/F11 reproduce exactly; this is the artifact's most solid contribution. Add the qualification from §6: `next3` is at 20% five days into the current cycle, so the corrected statement is *"utilization is non-stationary and a snapshot is uninformative in either direction"*, not *"quota is scarce"*. |
| **R6** — move the economy to context; de-duplicate CLAUDE.md | **KEEP — NARROWED, with the premise corrected upward and the arithmetic corrected downward** | The premise is **understated**: `~/.claude/CLAUDE.md` and the repo-root `CLAUDE.md` are **byte-identical** — 773 lines / 63,983 B each, 635/635 non-blank lines shared (100%), not "94% / 356 of 377 lines / ~25.8 KB". The duplicate is ~64 KB ≈ **16K tokens**, ~2.5× the claimed 6.5K. But the *comparison* is a unit error: "≈2.6% cut to the dominant cost component — larger than the entire effort ladder's realizable saving" compares a percentage **of a component** against a percentage **of the total**. Corrected: 16K of 226K cache-read tokens = 7.1% of cache read = **4.5% of marginal cost per message** — real, and still *smaller* than the ladder's stated −9.6%. And the quality risk is not "LOW pending a diff review": the repo copy is the **versioned SSOT/backup** of a live unsymlinked file (`.claude/CLAUDE.md` says so). The action must be *stop the second copy being loaded* without destroying the versioned artifact — a mechanism change, not a delete. |
| **R7** — probe Haiku for `research_retrieval`, gated on a deterministic re-check | **KEEP — NARROWED** | The gate is exactly right and N8 is the artifact's best rule. But the volume denominator is from the excluded-half population: Haiku is 0.27% of top-level messages and 0.42% of `subagents/` messages, and `research_retrieval` runs as a subagent. Recompute the share over `subagents/` before quoting "0.06%". Conclusion unchanged — this is capacity to route into, not a saving to book. |
| **R8** — do not act on the "Sonnet 5 ~15% pricier" line | **KEEP — NARROWED** | The documentary half is verified. The supporting statistic is not: "the certified Sonnet win is stranded at 0.34% of turns" is computed over the population that excludes subagents, where Sonnet's share is **84× higher** (2.53% vs 0.03%). Re-derive over `subagents/` + workflow runs before publishing the strandedness figure. |

### On the NEVER rules (N1–N8)

They survive and are the most valuable part of the artifact. Two amendments:

- **N1's justification must be re-sourced.** "The whole ladder is a 14-point cost band" is refuted.
  The rule stands on the corrected number (output ≈11% priced / ≈19–32% amortized) plus the
  stronger argument that the ladder's *quality* direction on Opus 5 is uncertified.
- **N5 is written asymmetrically and R3 walked straight through the gap.** It binds only
  *"a **cheaper** model or effort on an unproven iso-quality claim"*. On a model whose own vendor
  documentation says higher effort over-thinks, an *expensive* unproven change is the same defect.
  Make it symmetric: **never change effort or model in either direction on an unproven
  iso-or-better claim.**

---

## 8. What the agent got right

1. **The cost shape.** Cache read + cache creation dominate an Opus-5 message; output is a small
   minority. Reproduced on an independent seed, and deduping strengthens it (13.1% → 10.8%).
2. **The conclusion that follows from it** — effort is not where the money is, and an effort
   downgrade is a bad trade — survives every attack in this review, including the two corrections
   that move output's share *up*.
3. **F10 + F11.** The utilization time series exists, and the brief's 1–4% readings are a
   post-reset artifact over cycles that peaked at 91/92/100/85%. Reproduced to the point. This
   correction alone justifies the axis.
4. **The Fable refutation.** No 50% discount; a realized Fable message costs 3.27× an Opus-5@high
   one. Two independent estimators agree on the sign.
5. **The documentary work.** F4, F6, F14, F15 are accurate quotations, and F6/F11/F16 each carry a
   proper positive control beside the absence assertion — the house rule observed correctly.
6. **F16.** Thinking text genuinely is unrecoverable. The right conclusion was drawn; only the
   substitute estimator failed.
7. **Naming its own falsifiers.** Falsifier #1 is precisely the test that decides §5, and
   falsifier #3 anticipates the confound that §1 turns into a refutation. The artifact predicted
   where it would break.

---

## 9. What would falsify *this* review

1. **§1 rests on `message.id` grouping being the right unit.** If Claude Code re-emits a *new*
   `message.id` per content block on some binary versions, my dedup would merge distinct responses
   and under-count. Control: I verified 2,585 of 2,585 multi-record ids carry byte-identical
   `output_tokens`, which a genuine multi-response sequence would not.
2. **§4's amplification does not apply if the harness strips prior-turn thinking blocks** before
   re-sending. I could not measure this and abstained. If thinking is stripped, output's share stays
   near 10.8% and the artifact's "only output tokens" is nearly right for the effort lever
   specifically.
3. **§5's model comparison is spurious-regression prone.** Cumulative-vs-cumulative fits inflate all
   R². A properly differenced test with more movement windows could still separate the meters — and
   if it selects priced dollars, the artifact's bridge is sound and only its confidence label was
   wrong.
4. **My all-depth ladder could be confounded the other way.** `subagents/` skews toward short,
   bounded retrieval work; if `xhigh` is disproportionately routed there, its low output/message is
   selection, not effort. That does not rescue F3 — it means the observational ladder is
   uninterpretable in *both* samples, which is R2's whole point.
5. **If R2's randomized panel finds `xhigh` beating `high` on Opus 5**, R3 becomes correct on the
   evidence — but it would still have been REJECT when written, because it was recommended from a
   refuted number and against the vendor's documented direction.

---

## Appendix — commands

All scans deduplicate the four config dirs by `realpath` (`~/.claude-next{,2,3,4}` resolve into
them) and, unless stated, by `message.id` within each file. Scripts written to `/tmp/`:
`skep_scan.py` (seed 97 independent sample), `skep2.py` (depth2-vs-all, seed 11, chars/token
calibration), `skep3.py` (message.id dedup), `skep_ctx.py` (within-session cache growth),
`skep_meter.py` + the metering comparison (hourly token totals × `account-utilization.jsonl`).

Cross-file forks are **not** deduplicated by either the artifact or this review: a resumed session
copies prior messages into a new transcript, so fleet-wide *totals* are inflated in both. All
figures here are per-message means and per-cell ratios, which that defect largely cancels out of —
stated so no one reads a total off this page.
