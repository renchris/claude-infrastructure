# A4 — What THIS FLEET has measured about Opus 5 vs Fable 5.1, and what it has not

**Axis:** our probes are MEASURED; a vendor benchmark is QUOTED. Where they disagree, say so.
**Date:** 2026-09-16 · **Mode:** read-only · **Scratch:** `census.py` (fleet token census, this session)

---

## HEADLINE

**The incumbent has never been benchmarked.** Every quality measurement this fleet owns of
`claude-opus-5` was taken at `--effort max`. Production runs `--effort high`. There is no
measurement, anywhere in this repo, of the configuration the operator is being asked whether to
keep — and the SSOT says so in its own comment. Separately, the one head-to-head we do own
(Opus 5 @max 12/36 vs Fable 5.1 @high 10/36) is **statistically empty**: I recomputed it from the
raw judge rows and it is 4 discordant defects against 2, exact two-sided sign test **p = 0.69**,
with a design whose power at the observed effect size is **4.8%**.

So the honest state is not "Opus 5 wins" and not "Fable 5.1 ties". It is: **on the one task class
we probed, at efforts neither of which is our production setting, we cannot tell them apart, and we
never could have.**

---

## 1. The Fable 5.1 effort sweep — exactly what it proves

`docs/research/fable51-effort-sweep-2026-09-10/README.md`, 2026-09-10, ~$182, 45 cells.
Method is good and the doc is honest about its own limits. My re-analysis of `runs/scores.jsonl`
reproduces its table exactly (o5@max TOTAL 12/36, PAIRED 11/25; f51@high 10/36, 9/25).

### 1.1 The 12-vs-10 is indistinguishable from noise — recomputed, not asserted

Recomputed per-defect majority credit (≥2 of 3 judges), paired over the 5 briefs where every arm
was measured (25 ground-truth defects):

| comparison | both | neither | Opus-only | Fable-only | discordant | exact sign-test p |
|---|---|---|---|---|---|---|
| o5@max vs f51@high | 7 | 12 | **4** | **2** | 6 | **0.6875** |
| o5@max vs f51@medium | 7 | 12 | 4 | 2 | 6 | **0.6875** |
| o5@max vs f5@xhigh (all 36) | 8 | 23 | 4 | 1 | 5 | 0.3750 |

At the **brief** level — the genuinely independent unit, since 6 defects inside one brief come from
one output and are not independent draws:

| comparison | Opus wins | losses | ties | sign-test p |
|---|---|---|---|---|
| o5@max vs f51@high | 2 | 0 | 3 | **0.50** |
| o5@max vs f51@medium | 2 | 1 | 2 | **1.00** |

Unpaired CI on the headline difference (12/36 − 10/36): **+5.6 pp, 95% CI [−15.7, +26.8] pp** —
contains zero, and contains a large Fable advantage too.

### 1.2 The design could never have detected the thing it was read as showing

The sign test at these discordant counts is **structurally incapable** of significance:

| discordant n | split needed for p ≤ 0.05 |
|---|---|
| 1–5 | **unreachable at any split** |
| 6 | 6 of 6 on one side |
| 8 | 8 of 8 on one side |
| 10 | 9 of 10 |

We observed n = 6 discordant. Only a **6–0 sweep** would have cleared 0.05; we got 4–2.

Monte-Carlo power (20,000 trials, n = 36 defects, one sample per cell):

| true recall gap | power to detect at α = 0.05 |
|---|---|
| 33% vs 28% (the observed rates) | **4.8%** |
| 40% vs 28% | 12.7% |
| 50% vs 28% (nearly double) | **39.1%** |

**A design that would miss a near-doubling of recall 61% of the time cannot license a routing
decision in either direction.** The root cause is the corpus's difficulty floor: **21 of 36
ground-truth defects (58%) were found by no arm at all** at majority vote, so most cells are 0–0
ties that carry no information.

⚠️ This is *not* a criticism of the sweep. It was built to place the four `fable51_*` effort keys
relative to **each other**, and for that — a within-model ladder where a tie is the adoption
criterion — it is fit for purpose and its verdicts stand. It is being **read outside its design**
when its `o5@max` reference column is treated as a cross-tier verdict. The doc itself says so:
*"it is not acted on here, because this item is the 5.1 ladder, not the frontier tier."*

### 1.3 Other limits the doc states and that bind here

- **One task class:** anchored review of a single pre-fix file, `--tools ""`, no memory, no repo,
  one turn. Nothing agentic, no multi-file work, no tool use, no long context.
- **Recall only.** False positives, citation accuracy and fabrication were **not scored** — so
  T1's "reduced effort fabricates" axis is unmeasured for both tiers.
- **One sample per cell.** No variance estimate exists within any cell.
- **2 of 45 cells unmeasured**, 1 arm failure, 17 rows lost to HTTP 429 ($37.46 for no output).
- The `o5@max` and `f5@xhigh` columns are **not fresh** — they are reused verbatim from the
  2026-08-11 W2/W3 run, so they are a month older than the Fable 5.1 arms and were produced by a
  different runner.

---

## 2. THE GAP — the incumbent configuration has never been benchmarked

**Searched:** every arm label in `docs/research/**`, `docs/plans/**` and the freewin probe.
`claude-opus-5` appears as a measured arm in exactly two places, and both are `@max`:

| where | arm | effort |
|---|---|---|
| `codex-probe-w3-verdict-2026-08-11.md` (arm D) | `claude-opus-5` | **max** |
| `fable51-effort-sweep-2026-09-10` (`o5@max`, reused from the above) | `claude-opus-5` | **max** |
| `judge.py` judges (scoring instrument, not an arm) | `claude-opus-5` | xhigh |

**There is no `claude-opus-5 @high` arm in any probe in this repository.** No quality panel of any
kind has ever been run on Opus 5 at any effort.

This is not my inference — three independent in-repo sources state it:

1. **The SSOT's own comment**, `model-config.yaml:760` on `effort_defaults.default: high`:
   > *"This is the guide's STARTING POINT, not a measured optimum — a real per-class sweep is still
   > owed … Restore `max` only with an Opus-5 probe that reproduces the above."*
   And it records that the prior `max` certification (T1) is **model-scoped to Opus 4.8** and
   explicitly does not transfer.
2. **`docs/research/usage-telemetry-100p-2026-08-16/routing-economics.md` F6** (MEASURED,
   documentary, with a positive control):
   > *"Flat visible output across the flip is evidence of **iso-length, not iso-quality**. No
   > Opus-5 quality panel has ever been run at any effort."*
   Its F4 adds that the 2026-08-01 `max → high` flip was **asserted, not measured**, and that the
   flip's only realized signal was −15.3% output/turn with flat visible output (146 → 143 tok).
3. **`docs/research/opus5-adaptation-2026-08-01.md`** — the source of the flip — argues it from
   Anthropic's *Prompting Claude Opus 5* guide ("stop reaching for max"), i.e. from **vendor
   guidance, QUOTED**, not from a local panel.

**Consequence for the question being settled.** The comparison on the table is *Fable 5.1 @ lower
effort* vs *Opus 5 @high*. The right-hand side of that comparison has never been measured against
anything. Every number we have is about Opus 5 @max, an arm we do not run, whose relationship to
@high is itself unestablished — and F2/F3 of the telemetry doc measure `xhigh` as carrying **more**
thinking than `max` on Opus 5 (1,173 vs 1,058 tok/turn), so the effort enum's nominal ordering is
not even the observed ordering.

---

## 3. The fleet's standing decision rule, and what it says to do on a tie

`~/.claude/model-routing-freewin-probe.md` § Purpose. The objective is **lexicographic**:
(1) quality first — *"100× more spend is warranted for a real 1% quality gain"*; (2) cost only
breaks ties.

| Quality(B) vs A | Cost(B) | Verdict |
|---|---|---|
| Within noise (judge-panel tie) | **Lower** | **ADOPT B — free win** |
| Higher | Lower or equal | ADOPT B |
| Higher | Higher | ADOPT B — quality-first pays |
| Lower (even ~1%) | Any | REJECT B |
| Within noise | **Higher** | **Keep A** |

**"Within noise" has a definition and this sweep does not meet it:** *"an adversarially-verified
LLM-judge panel cannot reliably distinguish the outputs (default-to-refute; **majority of ≥3
independent judges must call it a tie**)."* The T6 panel scored **anchored recall per defect** — it
was never asked to render a tie/win judgment between arms, so no judge ever called this tie. The
rule's own instrument was not run on this question. **A non-significant recall difference is not a
certified tie.** Reading it as one is the same defect the repo elsewhere names: absence of a
detected difference is not evidence of equivalence when power is 4.8%.

**T5 is the open item and it is exactly this question.** The probe file names it *"the highest-value
open routing question in this file"*:
> *"re-run arms A and D over the same frozen 9-brief corpus at **matched** effort (both @max, then
> both @xhigh), same blind mixed panel … The corpus, the harness and the judging pipeline all
> already exist, so this is cheap."*

T5 has not been run. T6 **strengthened** the case for running it but does not substitute for it,
and the probe file says so verbatim: *"Still not a reseat: T6 is single-sample and recall-only."*

---

## 4. What we concluded about Opus 5 vs Fable, and on what basis

### 4.1 §D6 — "the delta has largely closed" is a BASE-RATE argument, and the SSOT retracts its footing

`docs/research/opus5-adaptation-2026-08-01.md` §D6, in full, reasons from exactly two inputs:

- `pricing_per_mtok`: Fable `[10, 50]` vs Opus 5 `[5, 25]` — *"Fable is exactly 2×"* (**base rates
  only**), and
- the Opus 5 model card's claim that Opus 5 is *"comparable to — and in some cases ahead of"*
  Fable 5 on many evaluations (**QUOTED vendor**).

No local measurement. Its recommendation — *"Stop reflexively escalating to Fable — 2× the price
for a delta that has mostly closed"* — inherits both limitations.

🚨 **The SSOT itself has already flagged D6's cost half as void.** `model-config.yaml` § ECONOMICS
(Fable 5.1 block, 2026-09-03):
> *"This partially re-opens the delta that § Opus 5 adoption recorded as collapsed: the routing note
> there ('Opus 5 ≈ Fable at HALF cost') was computed **on base rates only**. Re-do that comparison
> on effective cost-per-task at activation, not on the $10-vs-$5 headline."*

That re-do was never done. **Section 5 below is the first time it has been done on fleet data.**

### 4.2 `OPUS5_ADOPTION_AND_PROMPTING_2026-07-24.md` and the adoption record

The Opus 5 adoption was a **lateral bump at identical pricing** ($5/$25, replacing Opus 4.8). The
`model-config.yaml` history block records the staging, the auto-mode live test, and the effort
re-sweep directive — but the re-sweep it directed (`opus5_*` per-class keys) is recorded as
**"PARTLY DONE"** in the adaptation doc's own §D3 heading. The effort ladder for our default model
is a set of labelled starting points, not measurements.

### 4.3 T4 (2026-08-11) — the one real head-to-head, and why it cannot settle this

`docs/research/codex-probe-w3-verdict-2026-08-11.md`: `claude-opus-5 @max` beat `claude-fable-5
@xhigh` on recall **13 v 9** of 36, pairwise non-overlap 5 v 1, unique hits 2 v 0, citation accuracy
96% v 93% — at half the list price. The probe file's own caveat is the binding one:

> *"the arms ran at the efforts the ladder actually assigns them … so T4 **cannot separate 'Opus 5 >
> Fable 5' from 'max > xhigh'** … The honest T4 claim is that the Fable premium is **not
> demonstrated** in this slot."*

Note also: that is **Fable 5**, not 5.1, and the slot was scored on **non-overlap**, where the
decision rule inverts (a tie means redundancy ⇒ reject). It does not transfer to a *substitution*
question about the lead's default model.

---

## 5. NEW MEASUREMENT (this session) — the cost claim, on our own token profiles

The operator's premise is that Fable 5.1's cache-read price ($0.25/MTok = 0.025× base input, vs
Opus 5's $0.50/MTok = 0.1×) makes it cheaper in absolute dollars on cache-read-dominated agentic
sessions. **I measured our fleet's actual per-turn token profiles and priced them.**

**Instrument (MEASURED, this session):** `census.py` — 25% fixed-seed file sample (1,988 of 7,971
`.jsonl`) across all four config dirs (`~/.claude`, `-secondary`, `-tertiary`, `-quaternary`,
realpath-deduped), assistant turns only, deduped on `(sessionId, message.id)`.

| config | turns | out/turn | cacheRead/turn | cacheWrite/turn |
|---|---|---|---|---|
| **claude-opus-5 @high** | **60,638** | 550 | 225,422 | 5,476 |
| claude-opus-5 @xhigh | 7,310 | 312 | 202,088 | 7,419 |
| claude-opus-5 @max | 3,102 | 227 | 241,035 | 7,350 |
| **claude-fable-5-1 @max** | 1,105 | 1,350 | 321,159 | 17,221 |
| claude-fable-5-1 @xhigh | 487 | 924 | 221,835 | 21,098 |
| claude-fable-5-1 @high | 441 | 231 | 159,175 | 10,333 |
| claude-sonnet-5 @high | 141 | 15 | 94,475 | 5,526 |

### 5.1 The price-only counterfactual — the operator's premise is CONFIRMED, but the margin is ~5%

Holding **Opus-5@high's own measured token profile fixed** and swapping only the rate card
(this isolates price from the task-mix confound):

| rate card | $/turn | cache-read line | cache-write line | output line | vs Opus 5 |
|---|---|---|---|---|---|
| **Opus 5** ($5/$25, read $0.50) | **$0.1607** | $0.1127 | $0.0342 | $0.0138 | 1.00× |
| **Fable 5.1** ($10/$50, read $0.25) | **$0.1523** | **$0.0564** | $0.0684 | $0.0275 | **0.95×** |
| Fable 5 ($10/$50, read $1.00) | $0.3214 | $0.2254 | $0.0684 | $0.0275 | 2.00× |

**So yes: at API list rates, on our real context profile, Fable 5.1 is ~5% CHEAPER per turn than
Opus 5 — despite 2× the sticker.** The cache-read line genuinely halves ($0.0564 vs $0.1127) and it
is 70% of an Opus turn's bill. That is a real effect and the 2× sticker is genuinely misleading.

### 5.2 …but the margin is fragile, and every documented 5.1 behaviour pushes it the wrong way

Fable is cheaper iff `0.25·CR > 6.25·CW + 25·OUT`, i.e. `CR > 25·CW + 100·OUT`:

| profile | CR | 25·CW + 100·OUT | verdict | ratio |
|---|---|---|---|---|
| opus-5 @high (measured) | 225,422 | 191,900 | Fable cheaper | **1.17×** |
| **opus-5 @xhigh (measured)** | 202,088 | 216,675 | **Opus cheaper** | 0.93× |
| opus-5 @max | 241,035 | 206,450 | Fable cheaper | 1.17× |
| fable-5-1 @high (measured) | 159,175 | 281,425 | Opus cheaper | 0.57× |

**Break-evens on the Opus@high profile:** cache-write **6,817 tok/turn** (measured: 5,476 — only a
**1.2× margin**); output **885 tok/turn** (measured: 550 — a 1.6× margin).

Three things push both terms up on Fable 5.1, and all three are **QUOTED vendor deltas** in
`model-config.yaml` § SEVEN BEHAVIOR DELTAS:

- *"**whole-file rewrites for small edits**"* — raises output **and** cache-write directly, and is
  the delta CLAUDE.md already flags as making the INTEGRATE-never-overwrite rule *more* load-bearing.
- *"denser prose"*, and gains *"largest at the HIGHER settings"* — raises output.
- *"parallel tool calling is more variable (may issue one call/turn where 5 batched several)"* —
  more turns for the same work, each re-reading the cached prefix.

And our own realized Fable turns are already past both break-evens: **fable-5-1 @high writes 10,333
cache tok/turn, 1.5× the break-even**, which is why its realized cost is **1.12× Opus@high**
(@xhigh and @max are **2.27×**).

⚠️ **Confound, stated:** the realized (1.12×/2.27×) figures are heavily task-mix-confounded. Our
Fable turns are short frontier-panel / derivation sessions — 72% of their bill is cache **write**,
against 21% for Opus — which is a session-length artifact (cold cache re-established often), not a
model property. **§5.1's price-only counterfactual is the clean comparison and §5.2's break-evens
are the honest risk statement.** Do not quote 2.27× as a model fact.

### 5.3 The fleet does not pay dollars — and whether the discount reaches a subscriber is UNRESOLVED

This is the load-bearing caveat on the whole cost argument, and it is from **today's** research,
`docs/research/codex-vs-claude-200-2026-09-16/README.md` § C1:

> *"**C1 — The cache-read price edge is an API fact, and whether it reaches a SUBSCRIBER is
> unresolved.**"* — three sources disagree and cannot all be right:

| source | says |
|---|---|
| `orchestration-units-2026-08-19/A6-quota-economics.md` local fit (R² = 0.974, 0→735M span) | cache-read has a **zero** coefficient on the **5-hour** meter |
| `code.claude.com/docs/en/costs` (vendor) | cache reads **do** draw on subscription limits |
| that report's arm D | the 5.1 cache-read cut is an API price that *"subscription metering does not pass through"* |

> *"⇒ **Do not use the cache-read price as a reason to prefer either plan until the weekly meter is
> fitted.** It remains the highest-value open measurement here."*

Against that, two of our own quota measurements point **against** a Fable discount:

- **F7 (2026-08-16, MEASURED,** n = 564 hourly obs, 2,000 bootstraps**):** per list-price dollar
  Fable draws weekly quota at **1.27× Opus** (90% CI [0.79, 1.88]); `P(ratio < 0.75) = 0.040`, so
  the "50% discount" hypothesis sits outside the interval. **"Fable's '50% of limits' is a SUB-CAP,
  not a discount."** F8: every Fable dollar charges **both** buckets (two independent β estimates
  agree to 2%).
- **F9 (2026-08-16, MEASURED):** a *realized* Fable 5 turn cost **3.1×** an Opus-5@high turn
  ($0.6145 v $0.1970, n = 7,199 v 65,904) — same direction as my §5.2 realized figures.

Partially countervailing, from today: finding #6, **1pp of Fable costs ≤0.59pp of weekly**, 35% of
intervals where Fable rose showed zero weekly movement (n = 438 intervals / 28,444 rows) — but the
report labels this an **upper bound** and says it does not contradict the documented sub-cap.

**Net:** the dollar argument is ~parity with a thin, fragile margin; the *quota* argument — which is
what actually binds this fleet — has measured evidence pointing the other way, and the decisive
coefficient is explicitly unfitted.

### 5.4 A number the operator may have seen, correctly attributed

`codex-vs-claude-200-2026-09-16/C-measured-throughput.md` reports *"Fable 5.1 emits 2.04× Fable 5's
output tokens/turn (783 → 1,596, n = 7,835 turns), Opus 5 ref 637."* This is rated MEASURED but its
link is **claude-code GH issue #91623** and the doc's own §7 says *"The Claude-side numbers are
single-account incidents (n = 1 each)"*. **It is a third party's box — QUOTED, not measured by us.**
Our fleet's own equivalents (§5, measured this session) are Fable-5-1 @high 231 / @xhigh 924 /
@max 1,350 against Opus-5 @high 550 — i.e. **our Fable@high emits *less* than our Opus@high**, which
that external figure would not have predicted. Task mix differs; do not read either as a model fact.

---

## 6. Workload classes — where evidence exists, and where there is none

**Our fleet's actual composition (MEASURED this session, 25% sample, 74,116 assistant turns):**
`claude-opus-5 @high` is **60,638 turns = 81.8%** of all fleet turns. That is the class the decision
is really about.

| # | Workload class | Share of fleet | Evidence on Opus 5 vs Fable 5.1 | Status |
|---|---|---|---|---|
| 1 | **Long agentic infra sessions** (lead sessions, tool loops, 225K cached prefix/turn) | **~82%** (60,638 turns) | **NONE, for any model at any effort.** No probe has ever scored an agentic session. Every panel ran `--tools ""`, one turn, no repo. | 🔴 **UNMEASURED** |
| 2 | **Multi-file implementation waves** (Agent Teams, dispatched sessions) | large, not separable in the census | **NONE.** No probe has scored a code-writing arm. The only 5.1-relevant input is a QUOTED vendor delta — *"whole-file rewrites for small edits"* — which is **adverse** and interacts with the File Update Rule. | 🔴 **UNMEASURED** |
| 3 | **Anchored single-file review** | small | **MEASURED** — T6 (2026-09-10) + T4 (2026-08-11). Underpowered across tiers (§1); the within-5.1 ladder verdicts are sound. | 🟡 **MEASURED, UNDERPOWERED across tiers** |
| 4 | **Adversarial verification / non-overlap** | `roles.research_adversarial` | **MEASURED but not equal-effort** — T4: Opus-5@max > Fable-5@xhigh (13 v 9). Confounded with max-vs-xhigh by the probe's own admission. Fable **5.1** never probed on this slot. | 🟡 **CONFOUNDED** |
| 5 | **Research synthesis** (open-ended repo grounding) | `research_worker`, workflow slots | **MEASURED on the WRONG MODELS** — T1/T2 + the effort grid are Sonnet-5 vs **Opus 4.8**. Certified finding: *"max effort holds the grounding floor"*, every reduced-effort config fabricated (Sonnet@xhigh wrong-file cites, Opus@med fabricated a comment, Opus@low fabricated `computePull`). **Explicitly model-scoped to 4.8; does not transfer to Opus 5 or to Fable 5.1.** | 🟡 **STALE MODEL** |
| 6 | **Derivation panels** (the frontier tier's actual routed job) | `/frontier-run`, `frontier_discovery_budget` | **NONE** — and the SSOT names the hole: *"Derivation panels (generative, not anchored review) are the one class this did not cover — re-probe there before restoring xhigh."* | 🔴 **UNMEASURED** |
| 7 | **Planning / architecture** | lead sessions | **NONE.** | 🔴 **UNMEASURED** |
| 8 | **LLM-judge / bounded verify** | `verify_judge` | **MEASURED** — T1 certified `xhigh` a free win, **on Opus 4.8**. | 🟡 **STALE MODEL** |

**The pattern:** our entire measured corpus is *anchored, single-turn, tool-free review of one
file*. The fleet's dominant workload — an 82%-share long agentic session with a 225K cached prefix
and heavy tool use — has never been measured for any model at any effort, and it is precisely where
the two QUOTED 5.1 deltas with operational teeth land (variable parallel tool-calling; fewer
progress updates at higher effort, which CLAUDE.md notes our stall/liveness surfaces read as stuck).

---

## 7. What follows for the flip

**No measurement in this repository supports flipping the default, and none supports keeping it
either.** Stated precisely, against the fleet's own decision rule:

- The rule's **"within noise"** row requires a judge panel to *call a tie*. That panel has not been
  run on this question (§3). A p = 0.69 recall difference at 4.8% power is **not** a certified tie —
  it is an absence of evidence.
- The rule's tie-breaker is **cost**, and cost is ~**parity** (0.95× on the clean price-only
  counterfactual, §5.1) with a **1.2× break-even margin** on cache-write that the vendor's own
  documented 5.1 behaviours push the wrong way (§5.2) — and the *quota* meter, which is what
  actually binds a Max seat, has measured evidence pointing **against** a Fable discount (§5.3).
- A ~5% dollar margin is, under this operator's stated lexicographic objective (*"100× more spend is
  warranted for a real 1% quality gain"*), **not a large enough tiebreak to move a default on
  unmeasured quality.**

**The cheap, decisive experiment already exists and is specified.** T5 is written, the corpus
(`tests/fixtures/codex-probe/`, gated by `tests/codex-probe-corpus.bats`), the runner
(`run-arms.sh`) and the blind judging pipeline (`judge.py`) are all on trunk and re-derivable. The
one change that makes it answer *this* question rather than the 5.1-ladder question:

> **add a `claude-opus-5 @high` arm** — our actual production configuration, the arm that has never
> been run — alongside `o5@max` and `f51@{medium,high}`, and **score arm-vs-arm tie/win judgments**
> (the rule's own instrument), not recall alone. Power demands more than one sample per cell;
> at these effect sizes the current design needs roughly an order of magnitude more paired defects,
> or a task class with a higher discrimination ceiling than a corpus 58% of which no arm solves.

