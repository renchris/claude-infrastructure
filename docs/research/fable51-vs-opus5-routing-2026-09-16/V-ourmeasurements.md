# V — adversarial verification of A4 (`our measurements` axis)

**Date:** 2026-09-16 · **Mode:** read-only · **Subject:** `A4-our-measurements.md`
**Scratch (mine):** `v/census2.py` `v/ttlcheck.py` `v/stats.py` `v/stats2.py` `v/price.py` `v/dedupe.py`

**Verdict: sound-with-corrections.** The statistical spine (claims 1–4, 10, 11) reproduces
exactly from primary sources and survives every attack I could mount, including the two that
should have killed it. The **cost half (claims 6 and 7) is materially wrong and its sign is
inverted**, by an error this repository has already named and corrected in five prior artifacts.
Two supporting claims (3's framing, and the "@max is not an upper bound on @high" unknown) are
overreads of sources that say the opposite in their own next sentence.

A4's *operational* conclusion — do not flip the default on this evidence — survives. Its
*reason* for surviving changes: not "cost is ~parity favouring Fable by 5%, quality unmeasured"
but "cost is ~parity favouring **Opus** by 1–6%, quality unmeasured". Under the fleet's own
lexicographic rule that is a different row of the table (`within noise + HIGHER cost ⇒ Keep A`
rather than `within noise + lower cost ⇒ ADOPT B`), and it is the row that matters.

---

## R1 — REFUTED, decisive: the cost counterfactual priced 100% of cache writes at the 5-minute rate, and this fleet writes 60.7% one-hour cache

**Claims hit:** 6 (sign inverted), 7 (break-even margins wrong in direction, not just size).

### The error

A4's §5.1/§5.2 arithmetic is internally correct — I reproduced every figure to 4 decimals — but
it prices `cache_creation_input_tokens` at a flat **1.25× base input** for both models. That is
the **5-minute-TTL** rate. Anthropic charges **2× base input** for a **1-hour** cache write.

The discriminating field is `message.usage.cache_creation.{ephemeral_5m_input_tokens,
ephemeral_1h_input_tokens}`, present in every transcript row. A4's own `census.py` reads
`cache_creation_input_tokens` and never opens the sub-object.

**Measured (mine, `v/ttlcheck.py`, same 25% fixed-seed sample A4 used, sub-object complete —
`c5 + c1h == cc` exactly, 0 rows missing):**

| model @ effort | turns | cache-write tok | **1h share** |
|---|---|---|---|
| **claude-opus-5 @high** | 64,955 | 367,861,635 | **60.7%** |
| claude-opus-5 @xhigh | 7,071 | 46,312,703 | 27.0% |
| claude-opus-5 @max | 2,748 | 19,548,019 | 18.6% |
| claude-fable-5-1 @max | 1,052 | 12,991,285 | 41.9% |
| claude-fable-5-1 @high | 383 | 4,022,478 | 12.2% |

### The rate card, from A4's own cited bundle

`docs/research/codex-vs-claude-200-2026-09-16/B-anthropic-plan.md` row **3.1**, sourced to
`platform.claude.com/docs/en/about-claude/pricing`, marked **live 2026-09-16** — i.e. today, in
the same research bundle A4 cites for its claim 8:

> Fable 5.1 API pricing — Input **$10/MTok** · 5m cache write **$12.50/MTok** · **1h cache write
> $20/MTok** · cache read **$0.25/MTok** · output **$50/MTok**

and row **3.4**: *"Opus 5 is $5 / $25 / $6.25 / $10 / $0.50"* — the `$10` is the 1h write.

### The sign flips

`v/price.py`, one variable changed per row:

| scenario | Opus 5 $/turn | Fable 5.1 $/turn | F/O | verdict |
|---|---|---|---|---|
| **A4 as published** (msgid dedupe, flat 1.25×) | 0.1607 | 0.1523 | **0.948** | Fable cheaper |
| A4's own token profile + correct TTL pricing | 0.1732 | 0.1773 | **1.024** | **OPUS cheaper** |
| my re-run of A4's census + correct TTL | 0.1814 | 0.1832 | **1.010** | **OPUS cheaper** |
| repo-critic dedupe key + correct TTL (see R2) | 0.1822 | 0.1934 | **1.062** | **OPUS cheaper** |

Sensitivity on the one input: crossover sits at **~50% 1h share**. Below it Fable is cheaper,
above it Opus. We measure **60.7%** — on the Opus side, but only just.

| 1h share | 0% | 25% | 50% | **60.7% (measured)** | 75% | 85% | 99.7% |
|---|---|---|---|---|---|---|---|
| F51/O5 | 0.934 | 0.967 | 0.997 | **1.010** | 1.026 | 1.037 | 1.053 |

### Break-even, corrected

A4's crossover algebra `CR > 25·CW + 100·OUT` is only valid at a uniform 1.25×. With the TTL
split it becomes `CR > 25·CW5m + 40·CW1h + 100·OUT + 20·INP`:

| | A4's threshold (1.25× flat) | corrected threshold | measured CR | corrected margin |
|---|---|---|---|---|
| A4's numbers | 191,900 | **241,799** | 225,422 | **0.932× — Opus cheaper** |
| my re-measure | 195,100 | **246,711** | 239,447 | **0.971× — Opus cheaper** |

Break-even cache-write is **5,451 tok/turn**, not 6,817; measured is **5,664**. A4's stated
"1.2× margin in Fable's favour, fragile" is in fact **0.96× — already 4% on the wrong side**.

### Why this is an instrument error and not a difference of opinion

This repo has corrected exactly this mistake five times, and the corrections are in files A4 read
or cites siblings of:

- `usage-telemetry-100p-2026-08-16/critic.md:39` — *"**The cache-write multiplier is wrong in five
  artifacts, and the correct value is a durably recorded field nobody used.** A3, A5, A6, A7 and A0
  all price cache-creation at ×1.25 (the 5-minute-TTL rate). … **99.7% of cache-creation tokens are
  `ephemeral_1h_input_tokens`** … The 1-hour cache write lists at **2× base input, not 1.25×**."*
- `usage-telemetry-100p-2026-08-16/skeptic-exchange-rate.md:184` — *"85.1% of deduped
  cache-creation is `ephemeral_1h_input_tokens` … at **2× base input ($10/Mtok Opus)**, not the
  1.25× ($6.25) the artifact used flat … a 1.51× understatement."*
- `usage-telemetry-100p-2026-08-16/vendor-ground-truth.md:60` — *"write **1.25×** at 5-min TTL,
  **2×** at 1-hour TTL."*
- `handoff-high-value-capture-2026-08-19.md:272` — *"99.9% of cached input is `ephemeral_1h`, so
  the multiplier is **2.00×**, not the 1.25× three of this repo's own cost documents use."*

A4 is the sixth. The correcting row was in a sibling file of the bundle it cited for claim 8.

### Second-order finding, surviving the correction

The 1h share is **not stable**: 99.7% (critic, Aug, pooled) → 85.1% (skeptic, Aug, different
window) → **60.7%** (mine, today, opus-5@high specifically). A verdict whose sign turns on a
fleet-configuration variable that has moved ~40 points in a month is not a verdict. **The honest
statement is parity with an undetermined sign** — which strengthens A4's meta-conclusion ("a ~5%
margin cannot move a default on unmeasured quality") while destroying the claim it rests on.

---

## R2 — REFUTED (narrower): the census dedupe key differs from this repo's established one, and the two disagree by 1.36× on the output line

**Claim hit:** 5 (numbers), and it feeds 6/7.

A4 dedupes assistant turns on `(sessionId, message.id)`. `usage-telemetry-100p-2026-08-16/critic.md`
item 2 establishes the key as **`(file, requestId)` taking the MAX per counter**, and records that
failing to dedupe by `requestId` understated A7's ratios ~2.1×.

Measured both keys on the identical sample (`v/dedupe.py`, `claude-opus-5 @high`):

| key | turns | out/turn | cacheRead/turn | cacheWrite/turn |
|---|---|---|---|---|
| A4's `(sessionId, message.id)` | 62,439 | **562** | 228,392 | 5,724 |
| repo's `(file, requestId)` MAX | 63,145 | **763** | 227,921 | 5,763 |
| ratio | 1.011 | **1.357** | 0.998 | 1.007 |

Cache read and write agree to 0.3%; **output disagrees by 36%**. Output is one of the three terms
in the pricing and the term with the largest per-token price gap between the models (2×). The
direction is adverse to A4: at 763 out/turn even A4's *own* (wrong) 1.25× threshold gives a margin
of 1.03× instead of 1.17× — i.e. fixing the dedupe key alone nearly erases its Fable advantage
before the TTL correction touches it.

**Also: the census is not reproducible to the precision quoted.** Same script, same seed 11, same
25% fraction, ~1 hour later: total assistant turns **78,199** vs A4's 74,116 (+5.5%);
opus-5@high **64,955** vs 60,638 (+7.1%); cacheRead/turn **239,447** vs 225,422 (+6.2%). The
corpus is live and appends during the measurement. A 6%-drifting input cannot support a 5%
conclusion. The *share* claim survives (83.1% vs A4's 81.8%).

---

## R3 — REFUTED (framing): "No Opus 5 quality panel of any kind has ever been run at any effort" is the cited source's sentence read past its own positive control

**Claim hit:** 3 (framing only — the load-bearing narrow form survives).

A4 quotes `routing-economics.md` F6 and then restates it with two added words. F6's full text:

> **F6** | Flat visible output across the flip is evidence of iso-length, not iso-quality. No
> Opus-5 quality panel has ever been run at any effort. | … **Positive control: the file *does*
> record a completed Opus-5 arm (T4, 2026-08-11), so the absence is of an Opus-5 *effort* panel
> specifically, not of Opus-5 evidence generally.**

A4's claim 3 reads *"No Opus 5 quality panel **of any kind** has ever been run at any effort"* — and
its own table two lines above lists two Opus-5 quality arms (T4 arm D, and `o5@max` in T6). The
source anticipated this exact misreading and shipped a control against it; A4 quoted the headline
and dropped the control.

**What survives, and it is the real finding:** there is no `claude-opus-5 @high` arm in any probe.
I re-grepped independently — every `--effort high` + `claude-opus-5` co-occurrence in `docs/` is an
operational session's argv (`orchestration-units/A2-spawn-path.md:169`,
`backlog-pipeline-recon/recon-bottleneck.md:71`, `silver-platter-enforcement/*` goldset rows), never
a scored arm. Only two model-comparison quality panels exist in the corpus at all
(`codex-probe-w3-verdict-2026-08-11.md`, `fable51-effort-sweep-2026-09-10`), both `--tools ""`.

**One thing A4 should have said and did not:** the experiment it proposes as its recommendation was
already specified and prescribed a month ago and never run —
`routing-economics.md` **R2**: *"Run the owed Opus-5 effort panel (D3's remainder) before touching
`default` again. Reuse the existing harness … Arms: Opus-5 @ {high, xhigh, max} on the four T1 task
classes. Cost ≈ 27 worker runs ≈ 0.5–1 weekly pp."* That it has sat 31 days unexecuted is itself
decision-relevant and A4 presents it as a fresh proposal.

---

## R4 — REFUTED: the "Opus 5 @max may not be an upper bound on @high" unknown is contradicted by the table it cites, and the source labels that row INFERRED and confounded

**Hit:** A4's stated unknown #2.

A4: *"F2/F3 … measure xhigh as carrying MORE thinking than max on Opus 5 (1,173 vs 1,058 tok/turn),
so the effort enum's nominal ordering is not the observed ordering — meaning 'Opus 5 @max' may not
be an upper bound on 'Opus 5 @high'."*

The cited table, `routing-economics.md` F2, in full: *"Opus-5 thinking tokens/turn: low 210 ·
medium 636 · **high 884** · **max 1,058** · **xhigh 1,173**. Cell n: high 65,904 · max 61,368 ·
xhigh 8,374."*

- The table says **high (884) < max (1,058)**, on the two largest cells in the sample. The
  anomaly is strictly `xhigh > max`. It cannot license doubt about `max > high`; it says the
  opposite.
- F3 is tagged **INFERRED**, not MEASURED (thinking tokens are derived via a chars→tokens divisor,
  not read from a field), and carries its own warning A4 dropped: *"⚠️ **Confounded**: efforts were
  not randomly assigned … The confound pushes xhigh's number up, so ×1.33 is an upper bound and
  **the true xhigh/max ordering is not established.**"*
- And thinking-token volume is not quality; the source's own F6 is the rule against reading a
  length signal as a quality signal.

---

## R5 — REFUTED (double standard): A4 applies a strict significance test to the quality evidence and a lenient one to the quota evidence it quotes in the other direction

**Claim hit:** 8 (its use, not its text — the text is verbatim accurate and survives).

A4 correctly rules p = 0.6875 "statistically empty". It then cites, as evidence *"pointing against
a Fable discount"*, **F7**: *"1.27× Opus (bootstrap median; **90% CI [0.79, 1.88]**)"* — an
interval that contains 1.00 comfortably, at a *90%* level. Its source names it as an open
falsifier with a cheap test: *"**The Fable refutation (F7) rests on a 90% CI of [0.79, 1.88].**
A single account-week of deliberately Fable-only load would collapse that interval. … A measured
ratio ≤0.75 would **resurrect the arbitrage and make Fable the correct default for
judgment-dense slots.**"* A4 quotes F7's point estimate and omits that its own author lists it as
unresolved and potentially decision-reversing.

**Two stale-premise problems with the same citation, both unflagged:**

1. **F7 and F9 are Fable 5, not Fable 5.1**, measured 2026-08-16, before the 5.1 adoption
   (2026-09-03). F7's unit is *quota drawn per list-price dollar* — and the denominator changed
   under it. Fable 5's cache read is $1.00/MTok; 5.1's is $0.25. The same token stream now costs
   4× fewer list dollars on the dominant line, so a per-dollar draw ratio mechanically **rises**
   under 5.1 without the model being any worse. The statistic does not transfer.
2. **F9's 3.1× is priced on Fable 5's card.** Re-pricing F9's own reported profile (337K cache
   read, 2,182 out, residual ⇒ ~13.5K cache write) at Fable **5.1** rates gives ≈$0.362/turn
   against Opus's $0.197 — **~1.8×, not 3.1×**. A4 cites it as *"same direction as my §5.2
   realized figures"* without noting the price card halves it.

The *core* of claim 8 is untouched and is A4's strongest contribution: `codex-vs-claude-200-2026-09-16`
§C1 is verbatim as quoted, dated today, and its instruction — *"Do not use the cache-read price as
a reason to prefer either plan until the weekly meter is fitted"* — independently voids A4's own
§5.1. A4 states this against itself, which is to its credit.

---

## R6 — PARTIAL: "design power 4.8%" is post-hoc power, algebraically redundant with the p-value it accompanies

**Claim hit:** 2 (headline figure only; the prospective figures survive).

I reproduced A4's simulation exactly (`v/stats2.py`, 20,000 trials): 0.048 / 0.131 / 0.395 against
its 4.8% / 12.7% / 39.1%. The arithmetic is right. The **4.8%** figure is power computed at the
*observed* effect size, which is a deterministic monotone function of the observed p = 0.6875 and
carries no information beyond it (Hoenig & Heisey 2001). A4 leads its headline with it —
*"design power 4.8%"* — as though it were an independent property of the design. It is not; it is
p = 0.69 wearing a design's clothes.

The **prospective** figures (40-vs-28, 50-vs-28) are legitimate design facts, and they are what
supports the conclusion. But they are also **model-dependent in a way A4 did not state**: its
simulation draws the two arms as independent binomials at their marginal rates. Modelling the
pairing instead — conditioning on the 21 defects no arm reached, so the 15 reachable ones carry the
conditional rates — gives **24.6% power at 40-vs-28**, nearly double A4's 13.1%. At 50-vs-28 the
two models agree (0.365 vs 0.395).

**Net:** the conclusion *"badly underpowered"* stands; the specific numbers are soft by up to 2×
and the headline number should be struck rather than corrected.

---

## S1 — SURVIVED, fully: the sign-test recomputation (claim 1)

I re-derived from `runs/scores.jsonl` + `runs/index.jsonl` independently (`v/stats.py`),
re-implementing `judge.py`'s quota-fault rule and ≥2-of-3 majority. Every number matches:

| comparison | both | neither | Opus-only | Fable-only | discordant | exact sign-test p |
|---|---|---|---|---|---|---|
| o5@max vs f51@high, PAIRED 25 | 7 | 12 | 4 | 2 | 6 | **0.6875** |
| o5@max vs f51@medium, PAIRED 25 | 7 | 12 | 4 | 2 | 6 | **0.6875** |
| o5@max vs f51@high, ALL 36 measured | 8 | 22 | 4 | 2 | 6 | 0.6875 |
| o5@max vs f5@xhigh, ALL 36 | 8 | 23 | 4 | 1 | 5 | 0.3750 |
| brief level, o5@max vs f51@high | — | — | W2 | L0 | T3 | **0.50** |

Recall totals reproduce the README table exactly (TOTAL 6/10/10/9/9/9/12; PAIRED 6/9/9/8/9/9/11),
0 parse failures, paired briefs `['cp-01','cp-02','cp-04','cp-05','cp-09']`. **21 of 36 defects
found by no arm at majority** — confirmed (20 of 36 at the ≥1-judge union ceiling).

**The attack that should have killed it, and did not.** Binarising 3 judge votes to a majority
throws away resolution, so a vote-level (0–3) paired analysis could have recovered a signal A4's
binarisation destroyed. It does not: vote-level sum of differences **+6** over 25 defects,
7 non-zero, 5 positive / 2 negative, sign p = **0.4531**, exact permutation p = **0.5298**.
Same for f51@medium (p = 0.4495). **Claim 1 is robust to the analysis choice.**

**One rhetorical overreach worth naming.** "Statistically empty" and "indistinguishable from
noise" overstate a weak but perfectly consistent direction that never once reverses:
o5@max is strictly top of all **7** arms (12 / 10 / 10 / 9 / 9 / 9 / 6); it loses **zero** of 5
briefs to f51@high; vote-level difference is +6; and restricted to the 15 defects *any* arm
reached, o5@max is **12/15 (80%)** against f51@high's **10/15 (67%)**. None of that is
significant. All of it points one way. "Underpowered and directionally one-sided" is the accurate
phrase; "empty" is not.

---

## S2 — SURVIVED: the decision-rule claim (4)

Verified verbatim against `~/.claude/model-routing-freewin-probe.md` §Purpose (lines 252–270). The
table and the "within noise" definition — *"an adversarially-verified LLM-judge panel cannot
reliably distinguish the outputs (default-to-refute; **majority of ≥3 independent judges must call
it a tie**)"* — are exactly as quoted, including the `Within noise | Higher | Keep A` row. The T6
panel scored per-defect anchored credit and was never asked for an arm-vs-arm tie verdict, so the
rule's own instrument was indeed not run. **A non-significant recall difference is not a certified
tie** — correct, and it is the single most load-bearing sentence in A4.

⚠️ **Provenance mislabel:** this claim was returned tagged `quoted-from-vendor`. The source is
`~/.claude/model-routing-freewin-probe.md`, an operator/fleet document. In a brief that demands
MEASURED/QUOTED/ASSUMED discipline, tagging our own standing decision rule as vendor material is
itself an instrument error the synthesis will read.

**Omission, one-armed:** A4 quotes the freewin probe's T5 caveat (*"Still not a reseat: T6 is
single-sample and recall-only"*) and drops the sentence immediately before it, which cuts the other
way: *"Evidence added by T6 (2026-09-10) … Opus-5@max's 12/36 beats `claude-fable-5-1` at EVERY
effort … and 5.1's own recall is flat from medium upward — so **'Fable at a higher effort would
close it' is no longer the open reading it was under T4.'"* That is our own standing file's
current reading of the same data.

---

## S3 — SURVIVED: T4's limits (10), the D6 base-rate critique (9), workload coverage (11)

- **Claim 10** verified verbatim against `model-routing-freewin-probe.md:31` and §T5: recall 13 v 9,
  non-overlap 5 v 1, unique hits 2 v 0, citation 96% v 93%; *"cannot separate 'Opus 5 > Fable 5'
  from 'max > xhigh'"*; *"the highest-value open routing question in this file"*; Fable **5**, not
  5.1; scored on non-overlap where the rule inverts. All correct.
- **Claim 9** verified: `model-config.yaml:542-543` — *"⚠️ That verdict is BASE-RATE-ONLY; re-check
  it against Fable 5.1's 0.025× cache reads before reusing it."* The SSOT does retract D6's cost
  half, and the re-do had not been done. (A4's re-do is the one R1 refutes — but the *gap* it
  named was real.)
- **Claim 11** verified: only two model-comparison quality panels exist in `docs/research/**`, both
  `--tools "" --setting-sources ""` `num_turns=1`. Nothing agentic, multi-file, or derivation-panel
  has ever been scored. Fleet share re-measured at **83.1%** (A4: 81.8%).

**One correction inside claim 7's evidence list.** A4 cites the SSOT's *"gains over Fable 5 are
largest at the HIGHER settings"* as a live vendor delta raising output. `model-config.yaml:832` is
followed two lines down by *"✅ **MEASURED 2026-09-10** … **the sentence above is now HISTORY**"*,
and the sweep refuted its quality half (recall flat from medium up; xhigh/max *below* high). It is
also a Fable-5.1-vs-Fable-5 statement repurposed as a Fable-vs-Opus one. **And A4's own census
contradicts the output half of claim 7**: our `fable-5-1 @high` turns emit **231** out/turn (my
re-run: 30) against `opus-5 @high`'s 550 (mine: 535) — Fable emits *less*. A4 notes this in §5.4
and never carries it back to §5.2, where it is directly contrary. The **cache-write** half of
claim 7 *does* hold empirically (fable-5-1@high 10,503 cw/turn vs opus-5@high 5,664).

---

## What the operator's question actually turns on, after this pass

1. **The cost tiebreak points at Opus, not Fable — but by 1–6%, on an input that drifts.** The
   operator's premise (cache reads make the 2× sticker misleading) is *directionally right about
   the cache-read line* and *wrong about the total*, because 60.7% of this fleet's cache writes are
   1-hour and Fable pays 2× on them too. Corrected: F51/O5 = **1.01–1.06×**.
2. **On the fleet's real meter (quota, not dollars) there is no reading under which the cache-read
   discount helps.** If cache read draws zero (A6's fit, R²=0.974), the meter is driven by output +
   cache write, where Fable is 2× Opus on both. If it draws proportionally, §C1 says we cannot say.
   Either way the dollar argument does not transfer to a Max seat, and A4's claim 8 is right that
   this is the highest-value open measurement.
3. **Quality is genuinely unmeasured at the incumbent's setting**, and that half of A4 is sound.
   The cheapest thing that would move this is `routing-economics.md` **R2**, specified 2026-08-16,
   never run: Opus-5 @ {high, xhigh, max} on the existing frozen corpus and blind panel.
4. **Reading the sweep as "Opus 5 wins" remains unsupported** — but so does reading it as a tie,
   and the direction has never once reversed across 7 arms, 5 briefs, 25 defects and two analysis
   choices.
