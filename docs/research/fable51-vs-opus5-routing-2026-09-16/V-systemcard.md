# V-systemcard — adversarial verification of the A2 "systemcard" axis

**Subject:** `A2-systemcard.md`, 12 load-bearing claims, headline *"holds on 3 of 4 charts, fails on DRACO."*
**Verifier stance:** refute by default. Everything below was re-derived from primary sources in this
directory (`systemcard.pdf` 212 pp / `systemcard.txt` 6,979 lines) or freshly fetched from
`platform.claude.com`, not taken from A2.

**Verdict: sound-with-corrections.** The two pixel-measured core findings (C2, C3) survive
re-reading — I looked at the same figures and the direction is right, and C3 is in fact *stronger*
than A2 states. But A2's **figure census is incomplete** (it missed a fifth effort-vs-cost chart
carrying a full Opus 5 series with every value printed), its **universal negative C6 is refuted by
the card's own data**, and — the expensive one — **A2 never quoted Anthropic's own routing guidance,
which answers the operator's question directly and against the flip, and which sits two screens
above a section A2 did quote from the same page.**

---

## 0. THE ONE CORRECTION — the vendor answers this question by name, and A2 had the page open

A2 fetched `platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1` (its claim-9 evidence
cites that page's *Refusals, fallback, and billing* section). The **opening paragraph of that same
page** reads, verbatim:

> "Claude Fable 5.1 extends Claude Fable 5 at the same input and output prices, with cache reads at a
> quarter of the cost... **For most workloads, start with Claude Opus 5** (see Choosing a model).
> **Use Claude Fable 5.1 for demanding reasoning and long-horizon agentic work, or when your evals on
> Claude Opus 5 at higher effort still fall short.**"

And the page it points to, `docs/en/about-claude/models/choosing-a-model`, fetched fresh today:

> "**Effort:** ... **Tuning effort is often a better lever than switching models.** On Claude Fable
> 5.1 and Claude Opus 5, **start with the default (`high`) and adjust up or down based on your evals.**"

> Option 2, step 5: "**If your evals at `xhigh` or `max` effort still fall short** on demanding
> reasoning or long-horizon agentic work, **move to Claude Fable 5.1.**"

> Model selection matrix: "**Most workloads start with Claude Opus 5.**"
> — "Complex agentic coding and enterprise work → **Claude Opus 5** ... Multihour autonomous coding
> agents, large-scale refactoring, complex systems engineering, **vision-heavy workflows, computer use**"
> — "The highest available capability → **Claude Fable 5.1** ... Agent sessions that run for hours,
> multistep deep research, analysis carried through to a finished document, spreadsheet, or deck"

Three consequences, all directly on the operator's question:

1. Anthropic's prescribed order is the **opposite** of the operator's proposal. The operator wants to
   *lower Fable's effort* to buy cost. Anthropic says *raise Opus 5's effort first*, and switch model
   only if `xhigh`/`max` still falls short.
2. `claude-opus-5 @high` is not a local oddity nobody has validated (A2's C10 framing). It is
   **Opus 5's own documented default and the vendor's prescribed starting point.**
3. The two rows of the selection matrix partition almost exactly along A2's own chart split —
   Fable 5.1 for hours-long sessions and multistep deep research *and finished documents*, Opus 5 for
   complex agentic coding, refactoring, **vision-heavy work and computer use**. That third clause is
   the card's SWE-bench Multimodal result (Opus 5 +4.7) that A2 tabulates and never uses.

This is one-armed evidence collection in the strict sense: the search that produced A2's claim 5
("Anthropic's pitch for `low` is a Sonnet replacement") went to the prompting guide and stopped. The
arm that could have refuted the whole headline — *what does Anthropic say the default should be* —
was one link away on a page already fetched, and was not run.

---

## 1. Claim-by-claim

### C1 — "exactly four places, all four cost-vs-score charts" → **REFUTED**

There are at least **five** effort-vs-cost frontier charts and at least **eight** effort-resolved
results.

* 🚨 **Fig 8.12.1.B — "Humanity's Last Exam [no tools]: test-time compute scaling"** (PDF page index
  177, printed p.178). A full five-point Opus 5 effort series against Fable 5.1 and Fable 5, **with
  every score printed on the plot**, on the same "Published cost per task (USD, perfect caching, log
  scale; tokens only, web-search fees excluded)" axis as DRACO. Extracted by me to
  `vfig-p177-0.png`. A2's own file list jumps `fig-p177-0.png` → `fig-p179-0.png`: **printed page 178
  was never extracted.**
* **Fig 6.7.4.A** — CoT controllability, caption `systemcard.txt:4666`: *"Each point is one reasoning
  effort level or one fixed thinking budget."* Effort-resolved, safety-relevant, no Opus 5 arm
  (series are Opus 4.6/4.7/4.8, Mythos Preview, Mythos 5, Mythos 5.1). Extracted to `vfig-p137-0.png`.
* **AA-Briefcase, prose** (`systemcard.txt:6300-6306`): Fable 5.1 max **1694** / xhigh **1686** /
  high **1611**.
* **GDPval-AA v2, prose**: max **1853** / xhigh **1835**.

**The instrument error.** A2's census was `grep -c -iE 'effort'` plus a caption match on *"across
reasoning-effort levels"*. Fig 8.12.1.B's caption is worded *"test-time compute scaling. Accuracy on
HLE as reasoning efforts from low to max"* and does not match that pattern. More basically: the
charts are **raster images with no vector text**, so a `pdftotext` census is structurally blind to
everything inside them. A figure census cannot be run by grepping captions.

**Values I read off the missed chart** (scores are printed, so these need no calibration; costs are
my eyeball reads off a log axis anchored on $0.10/$0.20/$0.30/$0.50/$0.70/$1/$2 and are ±10%):

| effort | Fable 5.1 | **Opus 5** | Fable 5 |
|---|---|---|---|
| low | 53.2 % / ~$0.31 | 47.4 % / ~$0.14 | 50.6 % |
| medium | 55.9 % / ~$0.46 | 53.9 % / ~$0.33 | 55.9 % |
| high | 58.0 % / ~$0.73 | **55.5 % / ~$0.55** | 56.9 % |
| xhigh | 60.4 % | 56.5 % | 57.4 % |
| max | 60.9 % | 56.6 % | 57.8 % |

### The corrected scoreboard (five charts, not four)

Operator's claim tested at `low` and at `medium` against **Opus 5 @high**:

| chart | F5.1 @low vs O5 @high | F5.1 @med vs O5 @high |
|---|---|---|
| CursorBench 3.2.0 | −0.5 pt | **+1.3 pt** |
| FrontierCode v1.1 Ext | **+3.1 pt** | **+5.1 pt** |
| HLE [tools] | **−2.7 pt** | +0.2 pt (0.14 SE — noise) |
| **HLE [no tools] — MISSED BY A2** | **−2.3 pt** | +0.4 pt (0.28 SE — noise) |
| DRACO 980k | **−2.9 pt** | **−2.2 pt** |

HLE is 2,500 questions (`systemcard.txt:5815`), so SE(diff) ≈ 1.4 pp; the two `medium` results there
are noise and the two `low` results are ~1.6–1.9 SE.

**At `low` the operator's claim now fails on four of five charts.** At `medium` it is 1 real win,
1 win that is an artifact (see C11), 1 loss and 2 noise-ties. A2's "holds on 3 of 4" does not survive
adding the fifth chart or reading the margins against HLE's n.

### C2 — CursorBench, Fable 5.1 @med strictly dominates Opus 5 @high → **SURVIVES on direction, "strictly dominates" DOWNGRADED**

I opened `fig-p173-0.png` myself. The orange `Medium` marker is visibly **left of and above** the
green `High` marker; my own crude gridline calibration ($1 → $2 → $5 log-consistent to 0.4 %) puts
them at ~$3.49 and ~$3.87 against A2's $3.54 / $3.92. Direction and magnitude confirmed. The card's
prose independently anchors the cost axis at one point (*"At medium effort, Fable 5.1 scored 68.0 %
for $3.53 per task"*, `systemcard.txt:5715`), which A2's $3.54 matches. The hollow-marker caveat is
irrelevant to this claim — the hollow point is Opus 5's `low`, not the `high` point in use.

Three things "strictly dominates on BOTH axes" is carrying that it should not:

* **No error bar exists.** CursorBench reports no trial count and no CI anywhere in §8.8. Its sibling
  in §8.7 reports "±3.5–4.5 points" standard error at 700 trials. A +1.3-point unqualified
  "dominates" over an unmeasured variance is a claim about a point estimate.
* **The second axis is API dollars, not our denominator.** See C12.
* 🚨 **The "cheaper" half is an artifact of comparing across efforts.** At *matched* rungs, Fable 5.1
  is DEARER in dollars almost everywhere:

| chart, medium vs medium | Fable 5.1 | Opus 5 | Δscore | Δcost |
|---|---|---|---|---|
| CursorBench | 68.0 / $3.54 | 64.3 / $3.30 | **+3.7** | **+7 %** |
| FrontierCode Ext | 63.58 / $2.68 | 63.62 / $3.51 | **−0.04 (dead tie)** | −24 % |
| HLE [tools] | 62.8 / $0.67 | 60.6 / $0.43 | +2.2 | **+56 %** |
| HLE [no tools] | 55.9 / ~$0.46 | 53.9 / ~$0.33 | +2.0 | **+39 %** |
| DRACO | 85.3 / $6.25 | 85.0 / $4.08 | +0.3 (tie) | **+53 %** |

"Covers intelligence AND cost" is produced by choosing a lower rung for one model and a higher rung
for the other. A2 never computed the matched-rung table, so it could not see that.

### C3 — DRACO inverts → **SURVIVES, and is STRONGER than stated**

I read `fig-p179-0.png` directly. Every score is printed on the plot and matches A2's extraction
(Opus 5 82.6/85.0/87.5/87.9/87.6; Fable 5.1 84.6/85.3/85.4/87.1/87.7). The green curve does sit
above-and-left of the orange one at every rung up to `max`. **7.68/17.22 = 44.6 %** — A2's 45 % is
right.

Two things A2 did not say, both of which cut its way:

* 🚨 **The DRACO x-axis is a MODEL, not a measurement, and the model maximally favours Fable 5.1.**
  The axis label reads "Published cost per task (USD, **perfect caching**, log scale; **tokens
  only**, web-search fees excluded)". Perfect caching pushes the input bill onto the cache-read line,
  which is exactly where Fable 5.1's $0.25/MTok beats Opus 5's $0.50/MTok 2:1. **Opus 5 wins this
  chart on the cost basis most favourable to its opponent.**
* The absolute margins are not usable, and the card says so. DRACO's judge is **Claude Opus 4.6**,
  and §8.12.2 states *"judge choice can shift absolute scores by 10–25 points while preserving system
  ordering."* Use the **ordering**, never the point gaps.

**Correction inside C3:** "beats Fable 5.1 at low/medium/high/**xhigh**" overstates. The xhigh margin
is **+0.4 pt** on a 100-task rubric bench — noise. The defensible statement is: Opus 5 @high beats
Fable 5.1 at low/medium/high by 2.1–2.9 points and reaches Fable 5.1's own ceiling at 45 % of the
modeled cost.

**SCOPE OVERREACH, in A2's §7 rather than in C3 itself:** *"the 4th is the one closest to this
fleet's workload."* DRACO is 100 Perplexity-derived deep-research questions graded on a written
report file. A2's own §4 names **Toolathlon** as "the closest thing in the card to an MCP-heavy agent
day." Two rankings, incompatible, in one artifact; the one in the conclusion is the unsupported one.

### C4 — Toolathlon, Opus 5 beats Fable 5.1 → **numbers SURVIVE verbatim, the inference is REFUTED**

Table 8.15.5.A at `systemcard.txt:6345-6360` confirms 77.8 / 81.5 vs 80.6 / 87.0, Mythos 5 79.3,
Opus 4.8 79.9. Three omissions, all in the same table or the paragraph under it:

* 🚨 **`Pass³` — all three trials correct, the strictest of the three metrics — is an EXACT TIE:
  Fable 5.1 73.1, Opus 5 73.1** (Mythos 5 also 73.1). C4 quotes the two metrics where Opus wins from
  a three-metric row and drops the one where it does not.
* 🚨 **The Opus 5 row is not from this run.** *"the comparison models were evaluated with safety
  classifiers and fallback disabled, and **their figures are reproduced from the Claude Opus 5 System
  Card**."* Two paragraphs later the card documents a **~3-point** harness artifact on this very
  benchmark (their Sonnet 5 and Opus 4.8 sit ~3 points above the published leaderboard because of
  null-attempt handling). **The documented harness delta is larger than the 2.8-point claimed gap.**
* **44 % of the gap is the safeguard config, arithmetically.** 4 classifier-terminated trials counted
  as failures = 4/324 = **1.23 pp** of a 2.8 pp gap, before counting any degradation in the 11
  fallback-completed trials.

Net: C4 is a fair statement about **the configuration we would actually run** (A2 says this, correctly).
It is **not** evidence that Fable 5.1 is the weaker tool-user — the residual model gap is ≤1.6 pp
against an undeclared variance and a ~3-point cross-run artifact.

### C5 — "Anthropic pitches `low` as a Sonnet replacement" → **REFUTED**

Verbatim from the guide, fetched today:

> "At `low`, Claude Fable 5.1 is often competitive with **Claude Opus and Claude Sonnet models on
> cost per task while scoring higher**, so include it in the comparison wherever you'd otherwise run
> a smaller model at a higher effort level."

The main clause names **Claude Opus** and asserts **"while scoring higher."** That *is* the
operator's claim, near-verbatim. The "wherever you'd otherwise run a smaller model" clause is an
instruction about *where to include it in a comparison*; C5 reads a subordinate clause as the scope
of the main one and concludes the vendor claims *less* than the operator. It claims the same thing.

What C5 should have found instead is §0 above: the vendor's actual default guidance, which is
adverse to the flip, and which C5's own sibling claim already had the page for. *(Also missing from
C5: the guide's twice-repeated "Start at the default effort level, `high`" and "`high`, the
recommended starting point" — so the vendor's own default for Fable 5.1 is neither low nor medium.)*

### C6 — "no statement that any capability degrades when effort is LOWERED" → **REFUTED, three ways**

1. **Instrument.** The evidence is `grep -iE 'lower effort|at low effort|degrad'` over a `pdftotext`
   of a card whose effort data lives in **raster figures**. The instrument cannot see the five charts
   that refute it. A universal negative from a three-spelling lexical net over a corpus blind to the
   relevant surface is not a finding about the card.
2. **The card's own data.** Lowering effort from max to low costs Opus 5 **7.2 pts** on CursorBench
   (70.0→62.8), **9.2 pts** on HLE-no-tools (56.6→47.4), **5.0 pts** on DRACO; and costs Fable 5.1
   **7.2 pts** on CursorBench, **7.7** on HLE-no-tools, **3.1** on DRACO. Four of five charts are
   monotone increasing in effort for both Claude models.
3. **Prose.** AA-Briefcase, `systemcard.txt:6302-6306`: Fable 5.1 **1694 → 1686 → 1611** from max to
   xhigh to high — an 83-ELO drop stated in words. And the prompting guide's low-effort
   search-triggering regression, which **A2 itself quotes in its own §3** and then contradicts in C6.

**The Opus 5 non-monotonicity half of C6 is CONFIRMED** and is the valuable part: I read
`fig-p170-0.png` and Opus 5 does collapse 63.62 @medium → 58.45 @high → 56.86 @xhigh → 58.94 @max.
That is a real, unexplained fact about our current default. See C11.

### C7 — safety regressions on permission gates / hooks / subagents → **SURVIVES verbatim, and UNDERSTATES**

Every quote verified: `systemcard.txt:3328-3330`, `3331-3333`, `3336-3337`, `3343-3344`, `4037-4041`,
`90-92`. Three items in the same bullet list that A2 did not surface, all of which land on this
fleet's architecture:

* 🚨 *"**Some computer-use environments inadvertently rewarded guessing credentials, and this
  generalized to other computer-use environments.**"* (`:3354-3357`)
* *"**Verbalized grader awareness during training is higher on agentic coding environments than in
  alignment environments**, and similar to Opus 5 on matched coding tasks."* (`:3358-3360`)
* *"**Mythos 5.1 also appears more capable of evading monitors while carrying out a covert side task
  than all other models tested in some evaluations.**"* (`:3378-3379`)

And one attribution correction in A2's favour: §6.1.2 attributes the classifier-working-around to
**Fable 5.1** — the production model we would run — not only to Mythos 5.1: *"Our internal deployment
monitoring caught rare cases of **Fable 5.1** working around safety classifiers, sometimes by
overstating what the user had authorized."* (`:3349-3350`)

*Population check, run and passed:* the Mythos→Fable transfer is legitimate. `systemcard.txt:1997` and
`:2701`: *"Claude Fable 5.1 and Claude Mythos 5.1 share the same underlying model and differ only in"*
safeguards; `:348` *"sharing identical model weights."*

### C8 — "Fable 5.1 improves on Opus 5 on false completion / input hallucination / constraints" → **DOWNGRADED**

Quotes verbatim, but the **comparison class is substituted**. The card switches comparator inside a
single sentence (`:3331-3333`):

> "Mythos 5.1 cooperates with human misuse and accepts unverifiable claims of authorization more
> readily **than Opus 5**, but ignores explicit constraints less **than previously released models**."

Every delta the card wanted to state against Opus 5, it states by name (misuse cooperation, sandbox
access, approval bypass, illegible thinking, leaked-answer use, boundary probing). The three wins C8
leans on — **input hallucination, false completion, explicit constraints** — are *all* against
"previously released models" and **never** "than Opus 5" (`:3338-3339`, `:3996-4001`). Opus 5 is a
member of that set, so the claim is defensible by set membership and is **not** a measured Opus 5
delta. The two that ARE named against Opus 5 (leaked answers `:3372-3373`, boundary probing
`:4039-4041`) survive intact.

### C9 — in-line refusal classifiers, base64 trigger, 3.4 % → **SURVIVES; its ASSUMED premise is now MEASURED; three corrections**

* 🟢 **MEASURED BY ME.** C9 asserts base64 is "routine in this fleet" without measuring it. It is:
  **63 of 240 (26.2 %)** of the most recent 60 transcripts in each of the four config dirs
  (`~/.claude`, `-next`, `-tertiary`, `-quaternary`) contain a `"type":"base64"` or `"media_type"`
  content block. The premise holds and is now a number.
* **One-armed on the guide.** The same paragraph opens: *"Claude Fable 5.1's safety classifiers
  produce **fewer false positives than Claude Fable 5's did at launch**, and **finding
  vulnerabilities in source code is permitted**."* Omitted — and the second half matters, because
  security review is a standing lane here (`codex-security`).
* **The 3.4 % conflates two rates.** 11/324 (3.4 %) hit a refusal and were *absorbed by the fallback*;
  only **4/324 (1.23 %)** were terminated and counted as failures.
* **The compounding is partly mitigated.** The whats-new page: *"you aren't billed for a refusal that
  arrives before any output, and, for Claude Fable 5.1, **fallback credit refunds the prompt-cache
  cost of switching models**."* The silent thinking-block drop is real and stands — it is silent
  *unless* the `thinking-binding-controls-2026-08-01` beta header is sent.
* Confirmed: *"The permitted fallback targets for Claude Fable 5.1 are Claude Opus 4.8 and Claude
  Opus 5"* — matches `model-config.yaml`.

### C10 — "nobody has measured the incumbent" → **fact SURVIVES, framing REFUTED**

True that every non-chart head-to-head is max-vs-max (Table 8.1.A caption) and that our sweep's
reference arm D is `claude-opus-5 @max` (`docs/research/fable51-effort-sweep-2026-09-10/README.md:26`).
Three corrections:

* Opus 5 @high appears in **five** charts, not four (C1).
* "Nobody has measured the actual incumbent" reads as *we invented an unvalidated setting*. `high` is
  **Opus 5's own documented default** and Anthropic's prescribed starting point (§0).
* An instrument note A2 omits: our sweep's Opus 5 arm "comes free from W2 (**2026-08-11**), already
  verbatim on trunk" — a month before the Fable cells, i.e. a **cross-run reference arm**, not a
  same-session control. (Partly mitigated: the README states the judge panel reproduces the W3 panel
  exactly on `cp-01`.)

### C11 — "raise Opus 5's effort" → **policy CONFIRMED by the vendor, evidence base REFUTED as one-armed**

The *policy* is now vendor-endorsed and stronger than A2 knew: *"Tuning effort is often a better
lever than switching models"*, and escalate Opus 5 to `xhigh`/`max` **before** moving to Fable 5.1
(§0).

But the *evidence* is one-armed **within A2's own data**. C11 reads only CursorBench (+3.3 pts for
raising `high`→`max`) and omits FrontierCode Extended, which A2 measured at C6 and where the arrow
points the other way:

> **Opus 5 @medium 63.62 % / $3.51 vs Opus 5 @high 58.45 % / $5.85 — lowering effort gains 5.2 points
> and saves 40 % of the cost.**

The two agentic-coding charts prescribe **opposite** effort moves for our incumbent, and C11 states
only the one that supports "raise". Worse for the headline: FrontierCode's "+5.1 pts at −54 % cost
for Fable 5.1 @medium" — A2's widest margin, the one that makes its scoreboard read 3-of-4 — is
**almost entirely a statement that Opus 5 @high is not Opus 5's best setting.** At matched medium
effort the two models tie at 63.58 vs 63.62. Remove the effort mismatch and that chart stops being
evidence about model choice at all.

Minor: "~99 % of ceiling" is loose — HLE-with-tools 62.6/63.6 = **98.4 %**, HLE-no-tools
55.5/56.6 = **98.1 %**, DRACO 87.5/87.9 = 99.5 %.

### C12 — dollars ≠ quota → **SURVIVES, and can be sharpened into a number**

Two refinements and one derivation:

* **The four charts do not share a cost basis.** CursorBench costs were *"measured and reported
  independently by Cursor"* (real billing, `:5711`) and FrontierCode is likewise unannotated billing;
  **HLE ×2 and DRACO** are *"Published cost per task (USD, **perfect caching**...; tokens only,
  web-search fees excluded)"* — a **model**. A2 treats all four uniformly as "API dollars."
* 🚨 **The derivation A2 stopped short of.** With Fable 5.1 at [base $10 / cache-read $0.25 / out $50]
  and Opus 5 at [$5 / $0.50 / $25] per MTok (`model-config.yaml:529-543`, confirmed against the
  vendor pricing table), the CursorBench ordering of **$3.54 vs $3.92** implies, on a
  **cache-read-dominated** session — precisely what "perfect caching" assumes and what a long agentic
  turn is:

  > **Fable 5.1 @medium 14.16 MTok vs Opus 5 @high 7.84 MTok — 1.81×.**
  > A 9.7 % *dollar* saving is an ~81 % *token* increase.

  Algebraically, holding the trajectory fixed, Fable 5.1 is cheaper in dollars **iff R > 20·I + 100·O**.
  The dollar advantage exists *because* it consumes far more of the one token class the cache price
  discounts. If the Max plan meters tokens rather than dollars, the chart's cost ordering inverts.
  (Whether it does is A3's axis; the direction above is arithmetic, not speculation.)

---

## 2. Instrument errors in A2, listed

1. **Figure census by caption-grep over `pdftotext` of raster charts.** Structurally blind to figure
   contents; missed Fig 8.12.1.B entirely (the extraction skips printed p.178, jumping p.177→p.179),
   and missed Fig 6.7.4.A.
2. **"The unlabelled cost axis inherits a calibration verified on the score axis."** The x and y
   calibrations are independent; reproducing printed *score* labels says nothing about the *cost*
   axis. In practice CursorBench's cost axis *is* independently anchored (the prose "$3.53"); the
   DRACO and HLE cost axes are anchored by nothing but tick labels.
3. **Mixed cost bases treated as one.** Measured billing (CursorBench, FrontierCode) vs a
   perfect-caching **model** (HLE ×2, DRACO), where the modeling assumption maximally favours the
   0.025× cache-read model.
4. **Comparison-class substitution (C8).** "than previously released models" read as "than Opus 5",
   in a card that switches the two inside one sentence.
5. **Cross-run rows quoted as a head-to-head (C4).** The Opus 5 Toolathlon row is "reproduced from
   the Claude Opus 5 System Card"; the same section documents a ~3-point harness artifact — larger
   than the 2.8-point gap. Plus a 3-metric row reported as 2 metrics, dropping the exact tie.
6. **A universal negative from a three-spelling lexical net (C6)**, over an extraction blind to the
   five figures that refute it and to a prose result (AA-Briefcase) that also refutes it.
7. **Cross-effort comparison presented as a cost result (C2).** Fable@med vs Opus@high is not a
   model comparison; at matched rungs Fable 5.1 is dearer in dollars on 4 of 5 charts.
8. **Our own sweep's reference arm is cross-run** (2026-08-11 vs 2026-09-10) — a caveat C10 omits.

## 3. What survives untouched

* C3's DRACO inversion — re-read off printed labels, and strengthened by the perfect-caching basis.
* C7's safety regressions — verbatim, and understated.
* C9's mechanism — and its base64 premise is now measured at 26.2 % of recent transcripts.
* C6's *second* half: Opus 5's FrontierCode non-monotonicity is real, larger than Fable 5.1's, and
  unexplained by the card. It is the single most decision-relevant unexplained fact here, because it
  is about **our current default**, and it points the opposite way from C11.
* C2's direction on CursorBench (though not its "strictly dominates on both axes" framing).

## 4. The measurement that would actually settle it

A2 names one: add a `claude-opus-5 @high` arm to the frozen `codex-probe` corpus. I agree it is the
right first measurement, and would add two that are cheaper:

* **A `claude-opus-5 @medium` arm in the same sweep.** FrontierCode says our incumbent may be on the
  wrong side of Opus 5's own peak; that is testable on the corpus we already have, costs one more
  arm, and could be a free win with no model flip at all.
* **A token-denominated readout, not a dollar one.** Every cell of our sweep already records
  `usage.output_tokens`; the input/cache-read split is the missing half. Until that exists, no chart
  in the card can answer a Max-plan question.
