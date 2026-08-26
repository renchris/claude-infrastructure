# P12 — REDTEAM: attacking the assembled pipeline

**Stage position:** outside the dataflow. P12 consumes what P1–P11 *write* and what they *assume*,
and emits refutations plus executable cross-stage assertions. It is the only stage whose subject is
the composition rather than a page.

**Date:** 2026-08-26 · **Substrate:** `../README.md`, `../agents/A15-hostile-review.md`,
`../agents/A14-redteam-premises.md`, the eight sibling specs in this directory as written at
01:46 today, and live reads of the three target repos.

**Disposition: refute.** Every claim below either kills a design choice or is dropped. Where a
sibling already fixed something, it is credited and the attack moves to why the fix did not
propagate.

---

## 0. CONTRACT

### 0.1 Invocation

```bash
dr redteam --run <run-dir> [--strict] [--pins pins.json] [--out <dir>]
dr redteam --spec-audit <pipeline-dir>          # static: reads P*.md + schemas, no run needed
```

### 0.2 Inputs

| | Input | Source | Required |
|---|---|---|---|
| I1 | `<run-dir>` — one completed pipeline run: `manifest.json`, `facts/`, `findings/*.json`, `plan.json`, `route-plan.json`, `arbitrated/report.json`, `attribution.json` | P1–P8 | for `--run` |
| I2 | The transcript of the consuming agent's conversation (JSONL) | Claude Code `~/.claude/projects/<slug>/*.jsonl` | for A1 (image-block ledger) |
| I3 | `pins.json` — one row per un-owned external contract, each with a runnable probe | this stage defines the schema (§R5) | optional; absent ⇒ A5 abstains |
| I4 | A **clean corpus** ≥ 300 screens known-good by construction | §R6 — mined from git history, not authored | for A6 |

### 0.3 Outputs

```
<out>/
  refutations.json     # one record per attack, with status and the design change it demands
  assertions.json      # machine verdicts for A1–A7, each PASS | FAIL | ABSTAIN
  redteam.md           # this document's live half, regenerated
```

`assertions.json` record shape:

```jsonc
{ "id": "A1", "name": "image-block-ledger-single-owner",
  "verdict": "FAIL",
  "observed": { "budgets_declared": [16, 12, 12, 8], "owners": ["P2","P5","P4","P6"],
                "shared_ceiling": 20, "running_total_owner": null },
  "why": "four stages hold independent budgets against one per-request resource none can observe",
  "blunts": "P0-LEDGER: one on-disk block ledger, decremented by every stage, read by the agent" }
```

### 0.4 Failure modes this stage owns

| Failure | Detection | Action |
|---|---|---|
| An attack that only restates A15 | every refutation must cite a *sibling spec line* or a *live repo read*, not only the research wave | drop it |
| An attack with no design change | schema: `blunts` is required and non-empty | reject the record |
| An attack whose premise is already fixed upstream | grep the sibling specs before filing | downgrade to "fixed in Pn, did not propagate" — which is itself a finding (§R0) |
| A confident refutation of something unmeasured | `status: "UNVERIFIED"` plus a `probe` field naming one runnable experiment | required; §7 |

### 0.5 What this stage CANNOT do

| Cannot | Why | Owner |
|---|---|---|
| Decide whether a refuted stage should be cut or fixed | that is a cost/value call on the operator's own time | the human |
| Measure the false-positive rate | needs the clean corpus (I4) that does not exist yet | P4 SCREEN + whoever builds §R6 |
| Prove anchoring | needs a two-arm A/B on live pages, not an argument | §R3's probe; P6 PROMPT must run it |
| Attribute a finding to source | P8 owns it; P12 only attacks its input contract | P8 ATTRIBUTE |

---

## R0. The propagation defect — a correction that lands in one file and reaches none

**Mechanism.** Twelve siblings were briefed from one paragraph. That paragraph says
`reso-management-app` is *"Next 16 / React 19 / Tailwind 4, design-system conformance"* and
`reso-web-app` is *"Next 13, between the two."* Both are false, and the falsity is load-bearing
because two stages take a **resolved token file** as a required input.

**Evidence (live reads, today, `package.json` + configs):**

| App | Brief says | Actually |
|---|---|---|
| `reso-management-app` | Next 16 / React 19 / Tailwind 4 | Next 16.2.6, React 19.2.8, **Tailwind 4.2.4 AND Panda CSS 1.9.0** with `@park-ui/panda-preset` — two atomic-CSS engines in one PostCSS chain (`postcss.config.cjs` loads both), plus `theme.tsx`, plus `@theme` blocks in ≥4 source files |
| `reso-web-app` | Next 13 | **Next 15.5.24**, React 18, **Chakra UI 2 + Emotion 11**, no Tailwind, no Panda — runtime-hashed `css-<hash>` class names |
| `reso-landing-app` | Next 14, purchased template | Next 14.2.11, Tailwind 3.4.7 — the one row the brief got right |

**P8 already measured this** (`P8-attribute.md:107-109`) and built its §3 around three class-naming
regimes. **Nothing else did.** P4 SCREEN takes `--tokens tokens/<app>.resolved.json` — a *flat map*
`name → value` — plus `--profile reso-management-app`. In the management app there is no single map:
a colour legal under `panda.config.ts` `semanticTokens` and absent from the Tailwind `@theme` layer
is simultaneously conformant and drifted, so P4's K-family rules emit a confident `FAIL` whose truth
value depends on which resolver ran. In `reso-web-app` the Chakra theme is a **JS object evaluated
at runtime**: the flat map has no source, absent tokens ⇒ `INDETERMINATE` by P4's own contract, and
100% of that app's conformance surface routes to the vision tier that was never meant to answer
conformance questions.

**Blunt it.** (i) A per-app profile is not a string but a **resolved artifact with provenance** —
`{"engine": [...], "source": "<path>", "resolved_at": "<sha>", "coverage": 0.0-1.0}` — and a profile
with more than one engine must carry one map per engine plus an explicit precedence rule, or refuse.
(ii) Make `profiles.json` a P0 artifact generated by reading the repo, and have every stage assert
against it; a stage taking a per-app premise from prose inherits a stale brief by construction.
(iii) **Re-issue the brief.** Eleven of twelve specs are being written right now against two false
premises, and the one sibling that checked cannot tell the others.

**Falsifier.** `dr redteam --spec-audit` greps every sibling spec for the strings `Next 13`,
`Tailwind 4`-without-`Panda`, and `"between the two"`; a hit is a stage built on the stale brief.

---

## R1 — (a) ERROR COMPOUNDING

### R1.1 Four budgets, one resource, no ledger — assertion `A1`

**Mechanism.** The `>20 image blocks per request` cliff is cited by **four** stages, and each sets
its own budget against it:

| Stage | Line | Its budget | Its reasoning |
|---|---|---|---|
| P2 DECOMPOSE | `P2:66` | `cap: 16` (13 spent, 3 reserved) | "block budget" |
| P5 ROUTE | `P5:55` | `ceiling: 12`, granted 2 | image-block ledger |
| P4 SCREEN | `P4:494` | `--max-crops 12`, hard cap **19** | "19 leaves one block for the page overview" |
| P6 PROMPT | `P6:698` | hard cap **8** | "keeps a 2.5× margin from a hard-fail cliff" |

Each number is defensible alone. None is a *ledger*. The resource is per-request and the consumer is
a **Claude Code agent whose conversation already holds images before any stage runs** — and P1
additionally writes `read/<cell>.index.png` and `read/<cell>.fNN@Nx.png` frames it invites the agent
to Read as a table of contents. Worst case an obedient agent builds from the four contracts as
written: 1 index + 12 P4 crops + 2 P5 grants + P2's 13 = **28**, against a cliff at 20 whose failure
is *rejection, not downscaling*. The stage that trips it is whichever runs last.
`grep -n '20 image blocks' *.md` returns those four lines and nothing reconciling them.

**Blunt it.** Add **P0-LEDGER**: `<run>/blocks.json`, `{"ceiling": 19, "spent": N, "entries":
[{"stage":"P4","image":"crops/c07.png","visual_tokens":2448}]}`. Every stage writing a model-facing
image appends and decrements; a stage that would exceed the ceiling **writes the image anyway and
marks it `deliverable: false`** — refusing to write destroys evidence, refusing to *deliver* costs
nothing. The agent-facing rule is one report-header line: *"Read only images where `deliverable:
true`; there are N."* Ceiling 19 is P4's number, the only one derived from the cliff rather than
from a margin, less a reserve equal to the agent's pre-existing image count, written into the ledger
before the run. **UNVERIFIED:** whether the cliff counts per *conversation* or per request — U1
below settles it in four minutes and decides whether the ledger is per-run or per-turn.

### R1.2 Fail-closed at every stage composes into fail-never — assertion `A2`

**Mechanism.** Each stage is individually right to refuse rather than guess. Composed, the
preconditions multiply, and every one of them is an environmental property of a *live* page:

| Stage | Refusal | Environmental trigger |
|---|---|---|
| P1 | `exit 11 UNSTABLE` — two rasters must be sha-identical, 3 attempts, ≤1.25 s settle | any rAF ticker, live counter, carousel, video poster, `IntersectionObserver` animation |
| P3 | `exit 4` — CDP session closed | a stage crash anywhere upstream |
| P3 | `exit 5` — `documents.length > 1` under `--frames=strict` | any cross-origin iframe: Stripe, Intercom, a map, an ad |
| P4 | `exit 2` — `capturedAt` differs by more than 0 between shot and snapshot | clock skew, any retry |
| P5 | `exit 2` — dpr/clamp/colorScheme assertions | an unpinned run |

The refusals correlate with **liveness**, and liveness correlates with the pages that matter. The
corpus dashboard converges; the production dashboard with a revenue counter and an Intercom iframe
returns `exit 11` and `exit 5` forever. A pipeline whose dominant output on real apps is a refusal
has 100% precision over an empty set — "sees fine, critiques plausibly, changes nothing" with a
fail-closed alibi. P1 §6.2 records that its three-attempt gate was *needed* on a plain webfont case
and cleared on retry one: one convergence, on a corpus page, with no live data. The gate has never
been measured on any of the 105 real routes.

**Blunt it.** **No stage may exit non-zero for a reason that invalidates only a SUBSET of findings.**
P7 already built the right primitive for one field — `device_scale_factor_pinned:false` forces
`misalignment|grid-violation|optical-centre` to `abstained` with reason `instrument-unpinned` rather
than failing the run. Generalise it to a run-level **degradation vector**:
`{"stability":"converged|drifting","frames":"single|multi","instrument":"pinned|unpinned",
"clamp":"safe|degraded"}`, written by whichever stage observed it and consulted per finding class by
P7. Four of the five exits become degradations — `exit 11` ⇒ `stability:drifting`, pixel-diff
findings abstain and DOM findings stand; `exit 5` ⇒ `frames:multi`, iframe-subtree findings abstain.
Only `exit 4` (dead session) is a genuine run failure, because it invalidates everything.

**Falsifier.** Run P1 unchanged over 20 sampled `reso-management-app` routes against a real dev
server with seeded data. If ≥18 converge I withdraw R1.2. Stated as a prediction: fewer than 12.

### R1.3 The abstention set is not small, and the budget silently converts it to a pass — assertion `A3`

**Mechanism.** The README's affordability argument is: *"the abstention set is exactly the vision
layer's job queue, and it is small, which is what makes the vision spend affordable."* P4's own
contract prints the census it produces:

```json
{"census": {"subjects": 1841, "pass": 1732, "fail": 14, "indeterminate": 95, "out_of_scope": 0}}
```

**95 abstentions on one page.** P5's ceiling is 12 image blocks and it grants 2, so ROUTE must drop
83 of 95 — while the README's governing sentence is *"an abstention routes to the vision layer, a
pass routes nowhere."* A dropped abstention routes nowhere. **The budget converts 87% of the honest
abstentions back into silent passes** — the `fail-safe-default-mimics-the-healthy-state` failure the
abstention was invented to prevent, re-entering through the routing layer. The two numbers sit in
two sibling specs, contradict each other, and neither cites the other (`P4:0.3` against `P5:1.2`).

**Blunt it.** (i) **Type the abstentions.** Most of 95 will be one or two *classes* (a gradient
behind a hero; a `<canvas>`), not 95 independent questions — collapse by
`(rule, backdrop-signature)` before routing, so one crop answers a class. **UNVERIFIED**; U3 below
histograms `INDETERMINATE` by rule over 10 real routes in 20 minutes and either rescues the
affordability claim or kills it. (ii) **Print the deficit** — every report header carries
`coverage: {subjects: N, adjudicated: M, unadjudicated_by_budget: K}`; an unanswered question must
be visible as unanswered, not absent. (iii) **Rank abstentions by consequence**, since one on a
12-px legend and one on the primary CTA are not interchangeable and document order is not a ranking.

### R1.4 Coordinate frames compound into a plausible wrong file — assertion `A4`

**Mechanism.** P8's worst failure is *"a plausible file path that is wrong, because the consumer is
an agent that will edit it without a human reading the diff first."* Its load-bearing input is
`backend_node_id`, **"PRESENT iff origin != vlm"** — but VLM findings are the only class with
non-substitutable value (2/2 gestalt plus the 3 unasked), so **100% of the pipeline's unique output
enters attribution through the degraded coordinates → node path.** Compose that with cropping: a
crop finding's coordinates are in crop space, and recovering page space needs P2's crop rect, the
DPR, and the scroll offset — three multiplications, each owned by a different stage, none carried on
the finding record. An off-by-one in crop origin returns a node one row up in a table: real element,
real file, wrong answer, and `DOM.getNodeForLocation` reports no error at all.

**Blunt it. Forbid the model from emitting coordinates.** Have P2 mint a caption-numbered **region
label** into each crop's delivered caption (`region c07 — "the KPI row, second card"`) and require
every model finding to name one. Attribution becomes a lookup in `plan.json`, which already holds
the rect and — if P2 asks P3 — the `backendNodeId` of the crop's dominant element: arithmetic
replaced by a join. P7 gains one rejection, `coordinate-frame-unproven`, for any crop-framed finding
citing a page-space coordinate.

---

## R2 — (b) THE CROP DECOMPOSITION DESTROYS EXACTLY WHAT OPUS 5 IS BEST AT

This is the attack worth the budget. It is not a tuning objection: the justification for the
decompose stage does not transfer to our task.

### R2.1 The 18.9% → 48.1% lever is measured on the inverse task, on zero web pages

Crop-refinement is in this pipeline because ScreenSeekeR moved OS-Atlas-7B from 18.9% to 48.1% on
ScreenSpot-Pro with no model change — *"a bigger delta than every model upgrade combined."* Three
facts from the same substrate disqualify the transfer:

1. **ScreenSpot-Pro contains zero web screenshots** — 1,581 instructions over 23 professional
   desktop applications (VSCode, Photoshop, AutoCAD, MATLAB).
2. **Every ScreenSpot variant scores point-in-box, not IoU** — no box-quality term, so the headline
   certifies nothing about the property a design reviewer needs.
3. **It measures grounding — "here is a name, find the widget."** Our task is the inverse: *here is
   a region, name the unnamed thing wrong with it.* Crop-and-zoom helps when the target is known and
   the binding constraint is angular resolution. Ours is not resolution. It is **comparison**.

### R2.2 All three unasked findings are page-global quantifications — no crop can produce any of them

The blind run's three real defects nobody injected, restated as the logical form of each claim:

| Finding | Logical form | Minimum sufficient frame |
|---|---|---|
| orphan legend — a caption promising grey rows that do not exist | ∃ caption ∧ ¬∃ referent | the caption **and** the entire table it references |
| unlabelled icon button with the **smallest** hit target on the page | argmin over every interactive target | **every** interactive element on the page |
| numeric columns left-aligned so digits do not line up | within-column and across-column alignment comparison | the whole column plus a neighbouring column |

All three quantify over a set larger than any crop. Two are unfalsifiable *inside* a crop by
construction: a model shown one button in isolation cannot know it is the smallest, and a model
shown a caption cannot know its referent is absent from a region it was never given. The same holds
for one of the two injected defects it caught — *inverted action hierarchy* is a relation between
the primary and the secondary action, and a crop tight enough to raise resolution on either has by
definition excluded the other.

**Of the five defects Opus 5 uniquely found blind, four are structurally unreachable from a crop.**
The fifth (text washed out over a gradient) is now settled deterministically by the cross-check at
zero model cost. Crop refinement's measured marginal value on our own corpus is therefore **zero**,
and its measured marginal risk is the loss of four of five unique findings.

### R2.3 The remaining defence is resolution, and Opus 5 is 0/2 there

The honest case for cropping is that the sub-perceptual class (1 px misalignment, 5/255 colour
drift) becomes visible at higher effective resolution. Two refutations. First, Opus 5 scores **0/2**
there and nothing in the substrate says a crop moves it — the DiffSpot ceiling is 47.2% best-of-13,
hard-tier recall below 23% for *every* model, `line-height` median recall **4.0%**, all measured on
tight, single-property, already-framed comparisons, i.e. on the crop's best case. Second and
decisively: that class is answered **exactly and for free** by `getBoundingClientRect()` and the
computed style. Spending the most expensive lever to make a model guess a number the browser returns
violates the architecture's own rule — *the grounder supplies identity, the DOM supplies geometry.*

### R2.4 Blunt it

1. **The global pass is mandatory, first, blind, and unbudgeted** — whole frame at best clamp-safe
   fidelity, never traded against crop budget. P2's `phases[0]` already reads *"asked and FROZEN
   first"*; add *"and its block is not fungible with `phases[1]`."*
2. **Crops may only answer questions the GLOBAL pass raised** — never the deterministic layer's
   abstentions, never speculatively. A follow-up to nothing is a guess at what matters.
3. **Ban superlatives and existentials in crop output.** P6's crop schema rejects any `problem`
   matching `/\b(smallest|largest|only|most|least|no other|missing|absent|nowhere)\b/` with *"this
   claim quantifies over the page; ask it at global scope."* Mechanical, and it closes R2.2's hole.
4. **No crop finding reaches `asserted` without a global re-ask** — P7 gains `scope_mismatch`; the
   re-ask costs the one image block R1.1's ledger reserve exists for.
5. **U4 gates the whole stage** (§8): if the 6-crop arm does not strictly dominate the full-page arm
   on our own corpus, P2 costs image blocks and buys nothing.

---

## R3 — (c) THE FACT-PACK ANCHORS THE JUDGE. Evidence both ways, and one probe that settles it

### R3.1 The README answers a cost question with a cost answer, and anchoring is not a cost question

The substrate's licence to hand over the facts is *"~854 tokens — FEWER than one screenshot. There
is no context-budget argument for withholding facts from the judge."* True, and irrelevant.
**Anchoring is a conditioning claim, not a budget claim.** Nobody proposed withholding facts because
they were expensive; the risk is that conditioning the judge on a taxonomy changes the distribution
of what it reports. The README refutes an argument nobody made, then treats the real one as settled.

### R3.2 Evidence FOR anchoring — four items, two of them mechanical

**(1) Mechanical crowding-out, no psychology required.** P6's schema caps `findings` at
`maxItems: 7` on a whole-page call, hard-rejecting above it (*"the model must rank and cut, that is
the work"*). Hand that call `findings_dom.json` carrying P4's example census of **14 FAILs** and
every FAIL the model echoes consumes one of seven slots, while the unasked findings are by
definition the lowest-prior items in the ranking. **A cap of 7 under a prior of 14 arithmetically
guarantees the discretionary tail is cut first** — and nothing notices, because the output is
well-formed and every finding in it is real.

**(2) This judge class is measurably sensitive to framing alone.** Rubric scoring shows **16–39%
top-1 ranking reversals from REORDERING ALONE**, and pairwise order-invariant consistent accuracy
runs ~30–37% against a 25% chance baseline. If permuting identical content moves top-1 by up to 39
points, *"inserting 854 tokens of typed, pre-verdicted claims is inert on the output distribution"*
is not a tenable null. That does not fix the effect's direction; it refutes "no effect" as the
default assumption, which is what the pipeline currently assumes.

**(3) The unasked findings live outside every taxonomy we have.** *"None is reachable by any rule I
wrote, because none is a violation."* A fact-pack is a schema of what this pipeline counts as a
defect; handing a model a schema and asking an open question gets answers inside the schema.

**(4) A defect-prior is the measured precondition for invention on this task.** The local 27B model
invented a misalignment at 2 of 3 resolutions — *"the failure mode is a confident false positive."*
Different model, and I will not launder it into a claim about Opus 5; but same task, same direction,
and the pipeline is about to hand the judge 14 FAILs — the strongest available prior that this page
is defective. The blind run's zero false positives were measured with **no** such prior.

### R3.3 Evidence AGAINST — stated honestly, because it changes the remedy

- **P6 anticipated part of it**: `factpack` goes to *"pass-2 and crop/adjudicate only"*,
  `findings_dom` to *"pass-2 and adjudicate only"*. Pass 1 is already blind. What survives is what
  happens *after* pass 1, and the consumer.
- **Facts and verdicts are not the same prime.** A number ("this text is 14 px, its neighbour 16")
  tells the model what is true; a verdict (`token-drift FAIL on .btn-primary`) tells it what counts
  as reportable. **The first is a legitimate aid — it is what stops the model computing a number it
  cannot compute. The second is the anchor.** No sibling spec draws this line; it is the most
  valuable single distinction in this attack.
- **The pack prevents a worse failure** — sub-perceptual invention — by sourcing numbers the model
  would otherwise guess. Deleting it is not the fix.

### R3.4 Blunt it

1. **Split the artifacts at the contract level.** `factpack.json` (values) may enter any call.
   `findings_dom.json` (verdicts) may enter **only** `adjudicate`. A `gestalt` or `crop` call
   receiving verdicts is a schema violation, rejected before the API call.
2. **The blind pass is a separate API request with its own message list**, not a turn in the
   agent's conversation. This is the composition hole nobody owns: P5 spends calls and P6 composes
   them, but the consumer is a Claude Code agent whose conversation is append-only and already
   holds `plan.json` and `route-plan.json`. An agent that reads `findings_dom.json` at turn 3 and
   looks at the screenshot at turn 5 **has run the anchored arm while every contract believes it
   ran the blind one.** Blindness is a property of the request; only a stage that owns the request
   can guarantee it.
3. **Reserve slots rather than capping.** Keep `maxItems: 7` for *corroborated* findings, and add a
   non-fungible `unprompted: maxItems 3` array whose schema forbids citing any fact-pack path. An
   empty `unprompted` is information; a crowded-out finding is not.
4. **Freeze and hash pass 1 before any fact is shown** — `gestalt.blind.json` plus its sha in the
   run manifest, so no later stage can retroactively edit it and P12 can assert it (`A7`).

### R3.5 The probe — 3 arms, 39 calls, and it is the highest-value experiment in this whole wave

Nobody owns this and it settles the pipeline's central bet.

```
for page in corpus(13):
  A = judge(shot)                                        # blind — the measured baseline
  B = judge(shot, factpack.json)                         # facts only, no verdicts
  C = judge(shot, factpack.json, findings_dom.json)      # facts + verdicts — what the pipeline plans
```

Score per arm, per page: **(i) unprompted-finding count** — findings citing no fact-pack path and
matching no injected defect (the blind run scored 3 across 8 pages, so this is a live signal);
**(ii) false positives on the clean control**, 5× per arm, because a near-zero rate has no
resolution without repetition; **(iii) injected-defect recall.** Report per-page paired differences
with an interval, never a p-value — n = 13.

Decision rule, stated before the data: **if arm C's unprompted count is below arm A's by more than
one finding across the corpus, verdicts never enter a gestalt call.** If arm B matches arm A, the
facts/verdicts split in R3.4(1) is confirmed and the fact-pack ships. 39 calls, under 100 k tokens.

---

## R4 — (d) THE PIPELINE'S CEILING ON OUR OWN CORPUS IS ALREADY REACHED BY ~430 LINES AND ONE PROMPT

### R4.1 The arithmetic

| Component | Lines / cost | Corpus recall | FP on control |
|---|---|---|---|
| `detect_dom.py` rules | ~250 lines, **80 ms/page** | 9/9 DOM-determined, honest INDETERMINATE on the gradient | 0 |
| `detect_xcheck.py` | ~180 lines NumPy, no model, no GPU | the gradient case, deterministically (4.81:1 vs 1.57:1) | 0 |
| one screenshot + one prompt, blind | ~1,600 image tokens | 2/2 judgement, **plus 3 real defects nobody injected** | 0 |
| **union of the three** | **~430 lines + one call** | **11 / 11** | **0** |

The substrate states the union outright: *"The union of the first three is 11 of 11."* **The
twelve-stage pipeline's ceiling on this corpus is 11/11, which the union already reaches.** Expected
marginal recall from eight additional stages: **0.0**. Expected marginal false positives: ≥ 0. On
the only instrument we have that measures what we actually do, the composition can only lose.

### R4.2 The wall clock, on the real surface

`reso-management-app` has **105 page files** (`find src -name 'page.tsx' | wc -l`, today).
P1's own measured budget is *"six cells land around 20–35 s wall clock"* — 3.3–5.8 s per cell,
where a cell is one (route × viewport × theme × state). At P1's default 3 viewports × 2 themes and
**zero** auth or data states:

```
105 routes × 3 viewports × 2 themes = 630 cells × 3.3–5.8 s = 35–61 minutes
```

That is **capture alone, before a single model call**, for one app, on the happy path, with none of
A15's data-state axis. Add auth × seeded-data × empty × error states and it is hours. The baseline
it must beat — 105 one-viewport screenshots and 105 blind prompts — is a few minutes of capture and
roughly **168 k image tokens (~$0.84)**.

### R4.3 The honest counter, which is also the recommendation

Three things here are genuinely not in the baseline, and none is model scaffolding: **P4's closed
census** (`pass + fail + indeterminate + out_of_scope == subjects`, asserted at exit — the March
corpus's *"60% automated"* had an unfalsifiable denominator, and an enumerated one costs no model
call); **P8's attribution**, the only stage whose output is a write target; and **P7's dedup key
that spans the claim**, which the bench proved necessary by losing a real defect to `(rule, target)`.

**Blunt it: ship the spine, then make each stage beat it.** The spine is `capture-one-shot →
detect_dom → detect_xcheck → one blind judge call → attribute`. Measure it on the corpus and on 20
real routes. Then **no stage ships until it beats the spine on a stated metric** — P2 on U4's crop
A/B, P5 on abstention-class reduction, P6 on U5's three arms, P7 on FP rate over the clean corpus.
A stage that cannot name the number it improves is overhead wearing a contract.

---

## R5 — (e) MAINTENANCE HALF-LIFE: ~19 un-owned contracts against the baseline's ~4

**Mechanism.** Maintenance burden tracks **contracts you do not own**, not lines. Enumerated from
the eight sibling specs: `DOMSnapshot.captureSnapshot` + its 32-property whitelist ·
`Accessibility.getFullAXTree` · `Page.getLayoutMetrics().cssContentSize` · `DOM.getNodeForLocation` ·
the CDP `Animation` domain and `setPlaybackRate` · `getPlatformFontsForNode` · `page.clock.install()` ·
`addInitScript` · `--force-device-scale-factor` · `transformations.oversized_image` · the Read tool's
clamp ladder (2000 px / 3.75 MiB / palette-PNG → descending-JPEG → resize) · the `>20 image blocks`
cliff · `⌈w/28⌉ × ⌈h/28⌉` · the 2576 px / 4,784-token tier · React fiber debug metadata · Next's
dev-overlay click-to-source · Emotion `autoLabel` via the SWC transform · Panda's atomic-class
invertibility · `sourceMappingURL` in generated CSS. **Nineteen** — and two of them (the clamp
ladder, the 20-block cliff) are *undocumented client behaviour measured empirically*, i.e. they can
change in a point release with no changelog entry. `detect_dom.py` + `detect_xcheck.py` depend on
`getComputedStyle`, a PNG, and NumPy. **Four.**

**Evidence, from this operator's own repos.** The March 2026 corpus described an architecture whose
subject route was deleted 2026-04-25, whose 1,974-line instrument was deleted, and whose central bet
was refuted by June — **and none of the four documents carries a staleness banner.** The
`visual-design-iterator` agent was built in a two-day burst (three commits, all 2026-03-21), has had
**zero substantive change in five months**, and still curls the deleted route. Our measured half-life
for a bespoke visual-review scaffold: two days of build, three months to falsity, five months as a
live-looking orphan. A4's ~18-month field estimate was measured on published frameworks with
maintainers, and is generous here.

**Blunt it.** (i) **`pins.json` — one row per un-owned contract with a runnable probe**, run every
invocation; a failed probe degrades the *named capability* (R1.2's vector), never the run.
(ii) **Concentrate every client-behaviour pin in P1 plus one `client-probe` module** — nineteen
contracts across eight stages is nineteen places to discover a break. (iii) **No stage may depend on
undocumented client behaviour without a runtime probe.** The clamp probe is real and cheap: render
one PNG at 1,999 px and one at 2,001 px, each carrying a 256-step grey ramp and a labelled patch
pair differing by 5/255; Read both; ask which pair differs. If the 2,001 px image can no longer
resolve it, the ladder is live and quantising; if both resolve it, the ladder changed and every
`clamp_safe` assertion in P5 and P7 is stale in our favour. Either result is news. **UNVERIFIED**
until run. (iv) **Every doc here gets a staleness banner with the sha it was measured against** —
the March corpus's failure was not being wrong, it was being *silently* wrong for three months.

---

## R6 — (f) TRUST ECONOMICS: the zero-FP claim does not exclude the credibility threshold

### R6.1 The rule of three kills the safety claim as stated

The pipeline's central safety argument is *"our two zero-FP runs are the baseline to defend."* Both
were on a **13-page corpus with one clean control**. With zero events in *n* trials the 95% upper
confidence bound is **3/n**; at n = 13 that is **23%** — and the substrate's own credibility
threshold is *"~20% false-positive rate is where an AI reviewer loses human credibility regardless
of catch rate."*

**We have not measured a false-positive rate near zero. We have measured that it is below 23%, and
23% is above the abandonment threshold.** Every FP argument in every sibling spec rests on a bound
that does not exclude the failure mode.

### R6.2 The denominator gets worse at scale, and the advisory tier fires forever

P4's census example is **1,841 subjects on one page** — across 105 routes, **193,305 subject-checks
per audit**. A per-subject FP rate of 1 × 10⁻⁴, twenty times better than anything measured anywhere
in this substrate, yields **~19 false findings per audit**, delivered to an agent that acts on them
by editing source. The operator's memory corpus already names the outcome: *prescribed remedy worse
than the bug*.

The second mechanism is polarity. P7 renders `ASSERTED 6 · UNVERIFIED 3 · ADVISORY 4 ·
baseline/merged/rejected 11` per page — across 105 routes, ~630 asserted, ~315 unverified, ~420
advisory. **Advisory is terminal for judgement findings by the June ruling**, correctly, which makes
it a tier that never converts to an edit and reprints at every audit. A channel that always fires
carries as few bits as one that never does; 420 unactionable items per audit is the thing the
reviewer learns to skip, and once skipped it takes the asserted findings with it.

### R6.3 Blunt it — and the decisive experiment is nearly free

1. **State the FP budget per 1,000 subject-checks**, never per run — a per-run rate over a variable
   denominator is the unfalsifiable-denominator defect P4's census exists to kill, re-entering
   through the safety claim.
2. **Build the clean corpus for free and size it to the claim.** Bounding per-page FP at ≤1% with
   95% confidence needs **~300 clean pages** (3/300). Mine screens from the three apps' own git
   history that shipped and were never subsequently touched by a visual-bug fix — 105 routes × 3
   viewports is 315. **Every finding on that set is a false positive by construction, at zero
   labelling cost.** Cheapest decisive experiment in the wave, and no stage owns it.
3. **Per-rule FP ledger with automatic demotion.** Every finding carries `rule_id`; every rule
   carries a running FP count over that corpus; a rule crossing its class budget loses `asserted`
   status and any auto-fix privilege, mechanically rather than by review.
4. **Cap and rank the advisory tier, or do not render it.** Top 3 per audit; the rest go to a file
   the report *names* but does not print. A named store is a legal drop; a printed list nobody
   reads is not.

---

## R7 — WHAT THE LATE SIBLINGS ALREADY FIXED, AND WHAT SURVIVES

P9–P13 were written to disk after this attack was drafted. Three of them engage claims above
directly. Re-aimed here rather than quietly dropped, because a red-team that does not re-check its
own premises against the tree is the `scan-revision-predates-the-fix` defect.

**P11 ORCHESTRATE explicitly refutes R1.1 — on one of the two paths, and the pipeline's chosen path
is the other one.** `P11:315-317`: *"The `>20 image blocks in one request` cliff never fires, because
`--call-concurrency` bounds requests in flight, not blocks per request, and P5 caps a single request
at 12 image blocks. Both bounds hold independently."* That is **correct and sufficient for the API
path** — `dr` owns those requests and bounds them in code. R1.1's four-budget table is superseded
there and I withdraw it for that path.

It does not hold for the path the README chose as the integration surface. `P11:507-513` shows the
other guard: `read_order` is *"**≤ 6 paths**, ranked, and the agent is **instructed** to read them in
order and stop when it has enough"* — and names the exact failure, *"An agent that globs
`cells/**/crops/*.png` and Reads them will hit that cliff."* So: **one path is bounded by code, the
other by a sentence in a report.** An instruction is a request a model can decline, and it cannot see
the images already in the agent's conversation before the run began. The re-aimed assertion `A1` is
therefore not "nobody owns the budget" — P11 does — but **"the agent path's bound is advisory."** The
blunt is unchanged and cheaper than before: `read_order` gains a `deliverable: false` flag and a
`spent/ceiling` pair the agent must decrement, converting an instruction into a ledger. U1 still
decides whether the ceiling is per-request or per-conversation, and only the second case makes P11's
`--call-concurrency` bound insufficient on its own path too.

**P11 already adopted R2.4's ordering, which strengthens R2 rather than weakening it.** `P11:305-312`
defines the call graph as `C1 global → its findings name regions → C2..Cn crop calls on those
regions`, and states the mechanism exactly right: *"Issuing C1 and C2 concurrently on guessed regions
discards the mechanism and keeps the cost."* That is R2.4(1) and R2.4(2) already built. **But the
same block routes `P4's INDETERMINATE set → adjudicate call`**, so the deterministic layer's
abstentions still buy model calls that the global pass never pointed at — R2.4(2)'s other half, still
open. And P11 calls crop-refinement *"the single biggest measured lever in the whole pipeline"*,
which is the ScreenSpot-Pro transfer R2.1 refutes: **zero web screenshots, point-in-box not IoU, and
the inverse task.** The ordering is right; the sizing is inherited from a benchmark that cannot
license it. **U4 remains the gate.**

**P10 EVAL owns the acceptance test — R6.1 survives it and gets sharper.** My §9 said the pipeline
was about to be built without an acceptance test. **That is now false and I withdraw it**: P10 is the
acceptance gate, and its §5.3 `abstention_recall` / `false_abstention_rate` pair is the best idea in
the directory — it scores the abstention in *both* directions and its worked example REJECTs exactly
the naive `blendedBackgroundColors` adoption that would improve every other number. R1.3's silent
re-conversion of abstentions into passes is a `abstention_recall` failure by construction, so P10
already has the sensor; what it lacks is the *routing* fix, which stays R1.3's.

What survives is the **sample size**, and P10's own choice makes it acute. `P10:346-348` defines the
credibility metric as `fp_per_control_page` — *"deliberately an absolute count, not a rate: a rate
lets a large corpus dilute a real FP into invisibility."* The instinct is right and orthogonal to the
problem: the corpus has **one** control page. An absolute count over one page cannot distinguish a
true 0% FP rate from a 20% one, because both most often read `0`. The rule-of-three bound in R6.1
binds P10's metric exactly as it binds every prose claim, and §R6.3(2)'s 315-page clean corpus —
mined free from git history — is what gives `fp_per_control_page` the resolution to mean anything.
**Assertion `A6` is therefore aimed at P10, not against it: it asserts the denominator P10's metric
needs and does not yet have.**

---

## 7. THE SEVEN ASSERTIONS — what `dr redteam` actually executes

Each is a function of on-disk artifacts, returns `PASS | FAIL | ABSTAIN`, and names the stage that
must change. This is the runnable half of this document.

| id | Assertion | Reads | FAIL when | Owner of the fix |
|---|---|---|---|---|
| `A1` | **the agent path's block bound is a ledger, not an instruction** (re-aimed by R7) | `read_order` in `report.json`, `blocks.json`, agent transcript | `read_order` carries no `spent`/`ceiling` pair or no `deliverable` flag, or `spent > ceiling` | P11 ORCHESTRATE |
| `A2` | **no exit invalidates only a subset** | every stage's exit-code table | any non-zero exit whose stated cause leaves ≥1 finding class valid | P1, P3, P4, P5 |
| `A3` | **coverage deficit is printed** | `arbitrated/report.json` header | `indeterminate > adjudicated` and no `unadjudicated_by_budget` field | P5, P7 |
| `A4` | **no page-space coordinate from a crop** | every `findings/model.crop-*.json` | any finding with `frame: crop:*` citing a page-space rect | P2, P6, P7 |
| `A5` | **every un-owned contract has a live probe** | `pins.json` vs the grep of CDP/client identifiers across all specs | any identifier used with no probe row | P1 + `client-probe` |
| `A6` | **FP bound is below the credibility floor** | clean-corpus run | `3/n_clean ≥ 0.20`, i.e. fewer than 15 clean pages, or no clean-corpus run at all | P4 + whoever builds §R6.3(2) |
| `A7` | **the blind pass is request-isolated and hashed** | run manifest | `gestalt.blind.json` absent, or its sha not recorded before any `findings_dom.json` read appears in the transcript | P6 |

`--strict` makes any FAIL exit 1. Default exit is 0 with the verdicts on disk, because this stage
advises and does not gate — the June ruling binds P12 exactly as it binds the judge.

---

## 8. UNVERIFIED REGISTER — five probes, each decisive, all cheap

Nothing below is asserted. Each row names one experiment and what it decides.

| | Claim held open | The one probe | Cost | Decides |
|---|---|---|---|---|
| U1 | Does the 20-block cliff count per **request** or per **conversation**? | Read 21 small PNGs in one turn; then 21 across 21 turns; compare the error | ~4 min | whether R1.1's ledger is per-run or per-turn |
| U2 | Does P1's stability gate converge on **live** pages? | run P1 unchanged over 20 sampled `reso-management-app` routes against a real dev server | ~30 min | R1.2 — I predict <12 of 20 converge |
| U3 | Are the 95 abstentions ~95 questions or ~3 classes? | run `detect_dom.py` on 10 real routes, histogram `INDETERMINATE` by `(rule, backdrop-signature)` | ~20 min | whether the affordability argument survives |
| U4 | Does crop-refinement improve **anything** on our corpus? | blind prompt on full page vs the same page as 6 crops, all 13 pages, count finds + FPs | ~2 h | whether P2 exists |
| U5 | Does the fact-pack suppress unprompted findings? | §R3.5's three arms A/B/C over 13 pages, 5× on the control | ~39 calls, <100 k tokens | the pipeline's central bet |

**U5 is the one to run first.** Every other stage's design is downstream of whether handing the
judge 854 tokens of verdicts costs us the capability that is the only reason a judge is in the
pipeline at all.

---

## 9. THE SINGLE ASSUMPTION MOST LIKELY TO BE WRONG

**That the composition is additive.** Every sibling spec is written as though its stage adds a
capability to a growing total. Measured on our own corpus, the total is already **11/11 with zero
false positives**, reached by ~430 lines of Python and one prompt. From there, a stage can only
subtract — by consuming the image blocks the global pass needs (R1.1), by refusing on the pages
that matter (R1.2), by dropping 83 of 95 honest abstentions into silent passes (R1.3), by cropping
away four of the five findings only this judge produces (R2.2), by anchoring the fifth out of the
output (R3.2), or by minting the nineteenth false positive in an audit and losing the operator
(R6.2). Each of those is a *good stage doing its job*.

The pipeline is not short of perception, and — since P10 landed — it is no longer short of an
acceptance *design* either. It is short of the **runs**: P10 specifies `abstention_recall`,
`false_abstention_rate` and `fp_per_control_page`, and every one of them is currently computed over
a 13-page corpus with **one** control. A specification of a measurement is not a measurement. That
is why §8's five probes outrank every remaining line of specification in this directory — U5 above
all, because it decides whether the judge in the pipeline is still the judge we measured.

---

## 10. WHAT P12 CANNOT DO

| Cannot | Why | Owner |
|---|---|---|
| Decide whether a refuted stage is cut or fixed | a cost/value call on the operator's time and taste | the human |
| Run U1–U5 | they need a browser, a dev server with seeded data, and API calls; P12 is a static and artifact-level auditor | P1 (U1, U2), P4 (U3), P2 (U4), P6 (U5) |
| Build the clean corpus | it is a git-history mining job over three repos, and the mining rule is a judgement about what counts as a visual-bug fix | P4 SCREEN |
| Measure the FP rate | needs the corpus above | P4 + P7 |
| Fix the stale brief | eleven specs are being written right now against two false per-app premises; only the brief's author can re-issue it | whoever fires the wave — see §R0 |

