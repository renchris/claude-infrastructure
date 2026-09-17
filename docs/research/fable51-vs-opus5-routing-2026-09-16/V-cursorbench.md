# V — Adversarial verification of A1 (CursorBench axis), 2026-09-16

**Verdict: sound-with-corrections, but the corrections invert A1's cost conclusion and
dissolve its routing recommendation.**

A1's *transcription* is accurate — I re-fetched `cursor.com/cursorbench` with my own
extraction prompt and all 10 Opus/Fable rows came back identical, plus the 33 rows A1
did not print. Its *scepticism about what the board omits* (claim 5) is its strongest
work and I independently corroborated it at Epoch AI. What fails is the **interpretation
layer**: every dominance cell is CROSS-RUNG, the cost axis points the opposite way from
what A1 told the lead, and the one changelog entry that refutes its scope claim was on
the page it fetched twice.

---

## R1 — 🚨 CLAIM 7 IS FLATLY FALSE. The cost ratio did not invert.

A1: *"the 3.2-era cost ratio has INVERTED on 4.0 … Opus 5 Max now costs $11.95 against
Fable 5.1 Medium's $7.05 for a lower score. Anyone reasoning from the remembered 'Opus is
half the cost' line is reasoning from a superseded board."*

Computed from the board's own rows, **matched effort label on both sides**:

| rung | Fable $ | Opus $ | cheaper | Fable tok | Opus tok | fewer |
|---|---:|---:|---|---:|---:|---|
| Low | 5.44 | **4.87** | Opus | 34,795 | **31,995** | Opus |
| Medium | 7.05 | **6.94** | Opus | 45,411 | **45,272** | Opus |
| High | 9.08 | **9.00** | Opus | **58,438** | 61,405 | Fable |
| Extra High | 13.01 | **11.43** | Opus | 87,294 | **80,094** | Opus |
| Max | 17.28 | **11.95** | Opus | 117,236 | **85,384** | Opus |

**Opus 5 is cheaper at 5 of 5 matched rungs and uses fewer tokens at 4 of 5.**
Fable/Opus cost ratio at Max: 3.2-era 3.76/2.34 = **1.61×**; 4.0 17.28/11.95 = **1.45×**.
The ratio **narrowed**; the **sign never changed**. "Inverted" is manufactured by
switching rungs mid-sentence — A1's own evidence line does it in one breath
(*"Opus 5 Max $11.95 (5.1x) vs Fable 5.1 Max $17.28 (4.6x); Fable 5.1 Medium $7.05 beats
Opus 5 Max $11.95"*): the first clause preserves the ordering, the second changes the
comparison.

This is exactly attack (a): *a vendor chart read at one effort and quoted at another.*

**Consequence that survives and matters:** the real finding is **"Fable 5.1 delivers more
score per effort-label, so you can drop a rung"** — not "Fable is cheaper." Those have
completely different failure modes, and the second one is false.

---

## R2 — 🚨 CLAIM 6 IS BACKWARDS. The token axis probably favours OPUS, not Fable.

A1: *"The axis that does transfer is TOKENS, and it points the same direction more
strongly than the dollars do … Fable's 2x list price taxes the dollar column and it still
wins."*

Three independent refutations.

**(a) The two columns are arithmetically incompatible.** Cost ÷ Tokens gives the implied
blended price per MTok:

| | blended $/MTok | max unit price on its own list | |
|---|---:|---:|---|
| Opus 5 (all 5 rows) | **140.0 – 153.3** | $25 (output) | **5.6–6.1× IMPOSSIBLE** |
| Fable 5.1 (all 5 rows) | **147.4 – 156.3** | $50 (output) | **2.95–3.13× IMPOSSIBLE** |

Prices from the SSOT itself (`model-config.yaml:532-539`: `claude-opus-5: [5, 25]`,
`claude-fable-5-1: [10, 50]`, cache reads $0.25/MTok Fable vs $0.50 Opus). A blended rate
can never exceed the highest unit price on the list. **So `Tokens / task` is NOT the token
base the `Cost / task` column was computed over** — it is missing roughly 5× (Opus) to 3×
(Fable) of the billed volume, and the missing mass must be cache reads. A quota argument
built on that column is built on a quantity of unknown composition.

**(b) The direction is the opposite of what A1 argued.** Fable 5.1's cache reads are
**$0.25/MTok against Opus 5's $0.50** — the SSOT flags this at line 126 as *"the headline
is the CACHE READ, not the sticker"*, and the lead's own context block states it. Cache
reads are the dominant input line on long agentic sessions. So an equal dollar buys Fable
**twice** the cache-read tokens. The dollar column therefore **flatters** Fable relative
to raw consumption. A1 told the lead the dollar column *taxes* Fable — it subsidises it.

Under the only decomposition that reconciles the two columns (`Tokens/task` = generated
tokens; residual dollars = cache reads at each model's own rate):

| | implied total tokens/task |
|---|---:|
| Opus 5 High | **~15.0 M** |
| Fable 5.1 Medium | **~19.2 M** |

A **+28% token LOSS** for Fable where A1 reports a **−26.0% token win**. The decomposition
is an assumption; the *sign of the bias* is not — it follows from the 2× cache-read price
gap alone. **For a quota-metered fleet this is the whole cost question, and A1 pointed it
the wrong way.**

**(c) Cost and tokens are not two pieces of evidence.** Over the 10 Opus/Fable rows,
**r(cost, tokens) = 0.9971**, r(cost, steps) = 0.9731, r(tokens, steps) = 0.9844. A1
presents "+2.1pp score, −21.7% cost, −26.0% tokens, −26.7% steps" as four corroborating
facts. There are **two**: score, and run-size reported three ways.

---

## R3 — 🚨 CLAIM 8 IS REFUTED BY THE PAGE A1 FETCHED TWICE. CursorBench contains code review.

A1's §5 table: code review proxy quality **WEAK**, *"Not the measured shape"*;
claim 8: *"a WEAK-to-ABSENT proxy for code review … No web-research or judge-panel
component exists in the benchmark."*

The changelog, verbatim from **my own fetch**:

> **May 19, 2026: CursorBench 3.1** — Introduced problems focused on codebase
> understanding, **bugfinding**, planning, and **code review**. Improved grading criteria
> for some edit tasks.

A1 quotes the **3.2** entry and the **4.0** entry and omits the **3.1** entry — the only
one bearing on its claim. Versions are additive ("Introduced *new* long-horizon problems"),
so 4.0 contains the 3.1 review and bugfinding tasks.

This is attack (d) exactly: **name the arm that could have refuted the claim.** It was
four lines above the two entries A1 did quote, on a page it says it read twice.

---

## R4 — CLAIM 9 COLLAPSES WITH R3, AND ITS EVIDENCE STANDARD IS ASYMMETRIC.

A1's synthesis: *"they are not contradictory — each measures a task class the other does
not … Both instruments, taken together, suggest the current SSOT may have the two
assignments backwards."*

That rests entirely on **disjointness**, which R3 refutes. CursorBench 4.0 contains code
review and bugfinding; our sweep measured anchored review. The instruments **OVERLAP on
the exact axis where they disagree**, so they **CONFLICT**. A conflict demands
adjudication; it cannot be folded into a complementary synthesis that yields a routing
recommendation. **The "assignments are backwards" hypothesis has no support left.**

Second defect, independent: A1 treats our sweep (**n = 1 per cell, one file, recall only**,
and — as the lead already spotted — **with no Opus 5 @ high arm at all**) as settling the
review axis, while treating a **2.1pp** vendor gap with **no n** as signal. Opposite
standards applied to the two sides of its own synthesis.

---

## R5 — CLAIM 4's CARVE-OUT FOR THE 2.1pp CELL DOES NOT SURVIVE ARITHMETIC.

A1: *"Cell #1's 2.1pp is the only gap with any claim to signal."*

At p ≈ 0.455, unpaired, α = .05 two-sided, tasks needed **per arm**:

| gap | n required |
|---:|---:|
| 5.2pp (Fable Max vs Opus Max) | 705 |
| **2.1pp (the carve-out)** | **4,320** |
| 0.4pp | 119,078 |
| 0.2pp | 476,310 |

Feasibility bound on n: 43 configs × n tasks × ~$5/task mean ⇒ n = 200 costs ~$43k;
**n = 4,320 costs ~$929k of inference for one leaderboard.** So n is very likely in the
tens-to-low-hundreds. At n = 50…500 the SE of a difference is **9.96…3.15 pp**, making
2.1pp **0.21–0.67 SE** — statistically indistinguishable from the 0.4pp and 0.2pp gaps A1
correctly dismisses.

I could not pin n from score granularity: **no n ≤ 400 makes all 42 published scores exact
multiples of 1/n**, so grading carries partial credit (consistent with the changelog's
"improved grading criteria"), which blocks that inference but does not rescue the power.

**A1 applied the page's variance disclaimer to the two cells that hurt its thesis and
exempted the one that helps it.** Same disclaimer, same absent n, opposite treatment.

---

## R6 — CLAIM 3 CONTAINS A FALSE SENTENCE NEXT TO A TRUE TABLE.

*"Every Fable 5.1 rung outranks every Opus 5 rung."* False on A1's own rows: **Opus 5 Max
(46.6) and Opus 5 Extra High (46.1) both outrank Fable 5.1 Low (45.1)**. A1's very next
sentence says so. The rank numbers and the "interleave once" observation are correct; the
summary sentence is not, and it is the liftable one.

---

## R7 — BOTH OF A1's "INSTRUMENT CONTROLS" ARE CONTROLS THAT CANNOT FAIL.

A1 §0: *"the board was fetched twice with different prompts and the six rows came back
byte-identical; a third-party aggregator (benchlm.ai) independently reports the same two
headline figures."*

- **Two fetches of one static page** tests fetch determinism, not whether the numbers mean
  what is claimed. It could not have failed for any reason A1 cared about.
- **benchlm.ai is not independent.** Its own page, verbatim from my fetch: *"BenchLM tracks
  4.0 as **display-only** because it is a **first-party benchmark**"*, attributing to
  *"Cursor published the CursorBench 4.0 task set on September 10, 2026."* It republishes.
  It states no task count, no runs, no intervals, and runs no evaluation. **That is the
  same source laundered, not corroboration.**

---

## R8 — INSTRUMENT ERRORS A1 DID NOT RAISE

1. **🚨 A1 contradicts itself on the single load-bearing assumption.**
   §1: *"a 1:1 map onto Claude Code's own ladder … So 'Extra High' = our xhigh. No
   translation needed."* §4: *"the page does not say … whether the effort levels are the
   vendor's or Cursor's own naming."* Both cannot hold, and §1 is the one the headline
   rests on. I checked A1's cited support: **Epoch AI states only the enumeration**
   (*"Most models appear once per reasoning-effort level (Low, Medium, High, Extra High,
   Max)"*) and answers **NOT STATED** on provenance, harness, n, runs and grading. **A
   matching name LIST is not a matching PARAMETER.** Since R1 shows every dominance cell is
   cross-rung, the entire result is a claim about the effort-label mapping — and the
   effort-label mapping is precisely the one thing no source discloses.

2. **The cost column has a published history of being wrong, model-by-model.** Changelog:
   *Jul 9 — "Updated GPT-5.6 Sol, Terra, and Luna results to account for cache write
   costs"*; *Jul 30 — "Updated GPT-5.6 Terra and Luna results to account for adjusted
   pricing"*; *Aug 11 — "Updated Sonnet 5 results to account for adjusted pricing."* Three
   retroactive repricings, caught 1–3 months late, each for some models and not others.
   The Fable 5.1 / Opus 5 rows carry no such audit. **By the vendor's own changelog the
   cost column is the least reliable on the board** — and claims 2, 3, 6 and 7 all rest on it.

3. **Grading is undisclosed on both sources.** *"Improved grading criteria for some edit
   tasks"* implies graded, non-binary scoring; who or what grades is NOT STATED at
   cursor.com or Epoch AI. If grading is model-assisted, family bias is unexamined. A1
   never raised it.

4. **Cross-recency.** Fable 5.1 shipped 2026-09-06; Opus 5 shipped 2026-07-24. The board is
   a 4-day-old model against a 7-week-old one, published 4 days after the newer one landed.

5. **A1's SSOT critique applies its own defence inconsistently.** It defends the
   `70.6% vs 63.8%` comment as *"correctly labelled and NOT stale in the way it looks"*,
   then condemns the `$18-vs-$15 band` (`model-config.yaml:749`) for *"matching neither
   3.2 nor 4.0."* I read line 749 in context: it sits in a block headed *"corrected
   2026-06-11"*, i.e. a **3.0/3.1-era Fable 5 / Opus 4.8 figure** — the same class of
   correctly-dated record A1 just excused. One standard or the other.

6. **A1 names the right objection to the dollar axis and then substitutes a column that
   fails the same test.** It correctly says the $ column is *"about a different economy
   than ours"* — then pivots to Tokens, which R2(a) shows is not a consumption figure
   either. Naming an instrument error is not the same as escaping it.

---

## WHAT SURVIVES — and it is not nothing

- **CLAIM 1 (SURVIVES, verified).** 4.0 published Sep 10 2026; 3.2 Jul 8; 3.1 May 19; 3.0
  Mar 11 — all confirmed from my own fetch. Cross-version scores are not a time series.
  This is a real and important finding and it is A1's best original contribution.
- **CLAIM 5 (SURVIVES, strongest in the set).** No n, no runs-per-task, no pass@k, no CI,
  no error bars, no harness disclosure, no effort-naming provenance, no grader disclosure.
  Independently confirmed at Epoch AI, which answers NOT STATED on all five. A1 understated
  it if anything.
- **CLAIM 2 and 3's RAW TRANSCRIPTION (SURVIVES, verified byte-for-byte).** All 10 rows and
  all rank numbers are faithful. What fails is what was inferred from them, not the reading.
- **CLAIM 4's treatment of cells #3 and #4 (SURVIVES).** 0.4pp and 0.2pp are correctly
  called ties. A1 was right about those two and wrong only to exempt the third.
- **A1's own flagged unknowns (SURVIVE and are correctly prioritised).** Quota-draw
  proportionality, harness transferability, the 94KB-resident-ruleset property, the
  never-run Opus 5 @ high arm. All real, all open.

---

## THE NET, FOR THE LEAD'S SYNTHESIS

The operator's premise is **weaker than A1 reported, not stronger.** What the board
actually supports, after correction:

> On CursorBench 4.0, in Cursor's undisclosed harness, under Cursor's undisclosed
> effort-label mapping, with no n and no intervals, **Fable 5.1 scores 3.5–5.5pp above
> Opus 5 at every matched effort rung, while costing more at all five and using more
> tokens at four of five.** Whether the score gap is real is unknowable from this source;
> whether the *rung-drop* it implies survives a different harness is the actual question.

"Covers intelligence AND cost" is **half-refuted**: intelligence, plausibly and
unverifiably; cost, no — Opus 5 is cheaper at every matched rung, and on the consumption
axis this quota-metered fleet actually spends, the available arithmetic points at Fable
*costing more*, not less.
