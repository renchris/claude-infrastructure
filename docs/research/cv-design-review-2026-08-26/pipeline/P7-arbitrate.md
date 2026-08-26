# P7 — ARBITRATE

**Stage:** verification and consolidation. Turns the raw output of every detector into one ordered
report, and decides which findings are allowed to be *asserted* rather than merely *said*.

**Governing constraint (ratified June 2026, not reopened here):** taste stays human; gates adjudicate
correctness and coverage only. This stage therefore has an `asserted` rung that a model can never
reach on its own word, and an `advisory` rung that is terminal for judgement findings. It is not a
CI gate and its default exit code is not a verdict on design quality.

---

## 1. Contract

### 1.1 Inputs — all files on disk, all written by earlier stages

```
$RUN/                                   # e.g. /tmp/dp-a1b2  (one route × one viewport × one theme)
  run.json                              # P1 capture manifest
  facts/snapshot.json                   # P2 DOMSnapshot fact-pack (~854 tok serialised) + box index
  findings/dom.json                     # P3 deterministic rules      → layer:dom
  findings/xcheck.json                  # P4 DOM-vs-pixels cross-check → layer:pixel
  findings/model.full.json              # P5 blind full-page VLM pass  → layer:judgement
  findings/model.crop-*.json            # P5 crop-refinement passes    → layer:judgement
  findings/saliency.json                # P6, OPTIONAL, licence-gated  → layer:pixel, advisory-only
  shots/*.png                           # the frames every finding refers to
```

`run.json` MUST carry these fields or the stage refuses to run:

```json
{
  "route": "/dashboard", "commit": "9f21c0a", "viewport": [1280, 900], "dpr": 2,
  "device_scale_factor_pinned": true,
  "clamp_safe": true,
  "corpus_version": "1.0",
  "control_hash": "sha256:7c1e…",
  "model": { "id": "claude-opus-5", "prompt_sha": "sha256:2ab9…", "passes": 4 }
}
```

`device_scale_factor_pinned` exists because headless and headed Retina disagree on line-box rounding
by ~1.5 px over four paragraphs. Unpinned, every geometric finding carries a phantom offset, and
arbitrating a 1 px claim against a 1.5 px instrument error is arithmetic theatre. If it is `false`,
**every finding of class `misalignment`, `grid-violation` or `optical-centre` is forced to
`abstained` with reason `instrument-unpinned`** — not rejected, not asserted. Abstention routes to a
re-run; a rejection routes nowhere.

`clamp_safe` is A11's assertion `w ≤ 2000 && h ≤ 2000 && bytes ≤ 3_932_160`, computed on the written
PNG. If `false`, the model did not see what the browser rendered — the Read tool degraded it through
palette-PNG (256 colours) before the model got it. **Every `layer:judgement` finding in that run is
capped at `advisory` and may not be re-grounded**, because the predicate would be tested against a
frame the model never saw. Colour-class model findings are dropped to `abstained` outright: a
256-colour palette cannot carry a 5/255 drift.

### 1.2 Outputs

```
$RUN/arbitrated/
  report.json           # every finding, every status, every promotion record — the machine artifact
  report.md             # the ordered report an agent reads (§7)
  arbitration.jsonl     # append-only audit: one line per merge, promotion attempt, demotion, rejection
  requests.json         # re-capture / re-ground requests this stage could not satisfy itself
  control.diff.json     # what the clean control also said, and what was therefore marked baseline
```

**No finding is ever removed from `report.json`.** Deduplication sets `rollup_parent`; control
subtraction sets `status:"baseline"`; the verifier sets `status:"rejected"` with a cited counter-fact.
All three remain in the file, in §5 of the rendered report. This is the single most important
structural decision in the stage and §2.4 gives the measurement behind it.

### 1.3 Exit codes

| code | meaning |
|---|---|
| 0 | ran to completion; findings may exist (this is the default and it is **not** a quality verdict) |
| 2 | ran to completion **and** `--exit-on-blocker` was passed **and** ≥1 `asserted` + `blocker` finding exists |
| 3 | control gate failed or is stale — **fail closed**, no report is written |
| 4 | input malformed: a required `run.json` field is absent, or a findings file references a `backendNodeId` absent from `facts/snapshot.json` |

Exit 2 is opt-in. A CI wiring that gates on `advisory` findings re-adopts VLM scoring as a blocking
gate and contradicts the June ruling; the flag is named so that wiring has to be written deliberately.

### 1.4 Invocation

```bash
design-arbitrate \
  --run /tmp/dp-a1b2 \
  --control ~/.cache/design-review/control/7c1e4b0f \
  --verify-model claude-opus-5 \
  --reground-budget 12 \
  --advisory-cap 5 \
  --out /tmp/dp-a1b2/arbitrated

design-arbitrate --gate-control --rules bench/detect_dom.py --prompt prompts/judge.md   # §6
```

Plain CLI, JSON + PNG to disk, agent `Read`s the PNG. Not MCP: image bytes are charged against
`MAX_MCP_OUTPUT_TOKENS` (default 25 000) with `maxResultSizeChars` explicitly not applying to
image-returning tools, and a dead stdio server vanishes from the tool list silently — disqualifying
for the layer whose entire job is stopping a model from guessing.

---

## 2. Deduplication — a key that spans the CLAIM, and a merge that never deletes

### 2.1 The measured bug this replaces

`bench/detect_dom.py` suppressed a real colour-token drift on the primary button because an unrelated
`token-drift` finding already sat on that element in the baseline. The key was `(rule, target)`. It
scored 0/1 until the key grew a third component, then 1/1. Two lessons, and the second is the one
usually missed: the key was too narrow, **and the action on a key collision was `delete`.**

### 2.2 The key

```python
claim_key = sha1("\x1f".join([defect_class, target_key, observable_bucket])).hexdigest()[:12]
```

**`defect_class`** — a closed vocabulary, not the rule id. Rule ids map many-to-one into it, and this
mapping is the *only* thing that lets a DOM finding and a model finding meet at all: the rule says
`contrast`, the model says "this caption is washed out". Both normalise to `contrast`.

```
contrast · contrast-varies · misalignment · spacing-inconsistency · grid-violation ·
token-drift · overflow-clip · target-size · occlusion · hierarchy-inversion ·
label-missing · numeric-alignment · orphan-element · motion-timing · substrate-disagreement
```

Anything a model emits that does not normalise into this list is admitted under
`defect_class:"unclassified"` and is **never merged with anything** — a model that invents a category
is describing something no rule was looking for, which our baseline measured three times in thirteen
pages (orphan legend, unlabelled icon button with smallest hit target, left-aligned numeric columns).
Auto-merging an unclassified finding is how those get lost.

**`target_key`** — `backendNodeId` from `DOMSnapshot.captureSnapshot`, never a CSS selector and never
a bounding box. A model finding arrives with `bbox_raster` only; the arbitrator resolves it to a node
**before** keying, via `DOM.getNodeForLocation` at the bbox centroid:

```json
{"method":"DOM.getNodeForLocation",
 "params":{"x": 312, "y": 604, "includeUserAgentShadowDOM": false}}
```

then walks up to the nearest ancestor carrying a `layout` entry in the fact pack. This is the whole
cross-substrate merge mechanism: **both sides key on a node id the browser issued**, so "the same
defect seen by the screen and by the model" is a hash collision rather than a similarity judgement.
A model box is a 68-mAP estimate of something `getBoundingClientRect()` returns exactly; it is used
to *find* the node and then discarded.

**`observable_bucket`** — the quantised measured value, or the empty string.

| observable | bucket | why this granularity |
|---|---|---|
| contrast ratio | `round(v, 1)` | 0.1 is below any decision boundary (4.5, 3.0) and above float noise; finer splits one defect into two rows |
| distance / size, px | `round(v)` at 1 px | the smallest real defect in the corpus is 1 px, so 1 px is the floor; 2 px would merge a 1 px misalignment with its clean neighbour |
| colour | **exact sRGB hex, unquantised** | a 5/255 drift *is* a defect class we measured Opus 5 miss. Quantising colour re-creates the swallowed-token-drift bug at a different level |
| duration / easing | `round(ms)` + exact easing string | `getComputedTiming()` returns these with `auto` resolved; they are already exact |
| no number (judgement) | `""` | see below |

A numberless claim keys on class + target alone — which is exactly the pre-fix behaviour, so it is
guarded: two numberless claims of the same class on the same node **are** the same claim, and that is
sound precisely because neither carries an observable that could distinguish them.

### 2.3 Three merge tiers, and only tier 1 collapses

| tier | condition | action |
|---|---|---|
| **T1 EXACT** | identical `claim_key` | collapse: child gets `status:"merged"`, `rollup_parent:<id>`; parent gains `seen_in:["full","crop-2"]` |
| **T2 CORROBORATION** | same `(defect_class, target_key)`, **different** `observable_bucket` | **never collapse.** If the two observables agree within the stated tolerance → link `corroborates`. If they do not → mint a new finding of class `substrate-disagreement` |
| **T3 SPATIAL** | different `target_key`, same class, `IoU(bbox_css) ≥ 0.90` | if one node is a DOM ancestor of the other, keep the **deepest**, merge the ancestor into it. Otherwise leave both and link `adjacent` |

T1 is the across-crops case and it is the only safe collapse, because an identical key means an
identical claim by construction.

T2 is where the original bug lived, and the answer is a *third* finding rather than a choice. Two
instruments reading the same node and disagreeing beyond tolerance means one of them is lying, which
is more valuable than either reading. It renders as:

```
[substrate-disagreement] div.hero > .hero-caption
  the deterministic layer reports 10.36:1 (blended backdrop #1E3A8A); the cross-check
  reports 4.81:1 at the left edge and 1.57:1 at the right. The scalar is sampling one
  endpoint of a gradient. Trust the pair, not the scalar.
```

That is the measured nine-point swing, surfaced as an event with a culprit instead of resolved by
precedence. Severity `major`, always (§4).

T3's threshold is 0.90 and the reason is in the live data: `findings_xcheck.json` reports
`xcheck-optical-centre` twice on the same defect — once on `div.glyph-btn` and once on its child
`span.glyph`, boxes nearly coincident. Those must merge. Adjacent KPI cards in the same corpus sit at
IoU 0 and must not. 0.5 would be a similarity heuristic; 0.90 plus an ancestor test is a structural
one, and the ancestor test is what does the work — IoU only nominates candidates.

### 2.4 Why merges LINK and never DELETE

Blind Opus 5 found **3 real defects nobody injected** across 13 pages, and **0 false positives**
including on the control. By the Rule of Three, an observed 0/13 gives a 95% upper bound on the
false-positive rate of **3/13 = 23.1%**. The novel-true-positive rate over the same pages is
**3/13 = 23.1%**. These are the same number. With this sample, *a finding you are about to discard is
exactly as likely to be a defect nobody was looking for as it is to be noise.* Any operation whose
failure mode is silent deletion therefore has no positive expected value here, and that includes
deduplication. Linking costs one field; deletion cost us a real defect once already.

### 2.5 Control subtraction is the same operation, and carries the same trap

`findings_xcheck.json` fires `xcheck-optical-centre` on `clean.html` identically to how it fires on
`align-1px`. A run that does not subtract its control reports the control's own noise as a defect on
every page. But subtraction is *deletion*, which §2.4 just forbade. Resolution:

- Subtraction matches on **`claim_key`**, i.e. class + node + observable. Same class, same node, and
  the observable in the same bucket as the control ⇒ `status:"baseline"`, rendered in §5.
- Same class, same node, **different bucket** ⇒ **not baseline.** It is a regression on a known-noisy
  element and it stays at full status. This is the swallowed-token-drift bug stated as a rule: the
  element being noisy is not a licence to ignore a different number on it.
- The subtraction is per-`claim_key` and logged, one line each, to `arbitration.jsonl`. There is no
  code path in this stage that removes a finding without writing why.

---

## 3. Promotion — from "the model said so" to "asserted"

### 3.1 The rungs

| status | what it means | who may mint it |
|---|---|---|
| `asserted` | a falsifiable predicate over browser-supplied facts **was executed and did not fail** | the arbitrator only |
| `advisory` | a judgement for which no substrate predicate exists | the arbitrator, on a model finding the verifier declared unfalsifiable |
| `abstained` | an axis we know we could not check on this run | the deterministic layer's `INDETERMINATE`, or an instrument fault (§1.1) |
| `rejected` | a predicate was executed and failed, three times independently (§3.4) | the arbitrator only |
| `baseline` / `merged` | present on the control at the same bucket / rolled into another finding | §2.3, §2.5 |

**The single rule that defines this stage:** *assertion requires a falsifiable predicate that was
actually executed.* Not "a model with high confidence", not "two models agreed", not "it looks
right". A claim that cannot be written as a predicate over `facts/snapshot.json` or over a re-capture
has a permanent ceiling of `advisory`, and that ceiling is what implements the June ruling in code
rather than in prose.

### 3.2 The three admission routes to `asserted`

**Route A — DOM-determined arithmetic.** `layer:dom`, `confidence:determined`. Auto-asserted, no
model pass, no verifier. The browser computed it; asking a model to re-check it can only introduce
error. Measured 9/9 with 0 control false positives. **No model finding may overrule a Route-A
assertion** — a contradiction between them mints a `substrate-disagreement` (§2.3) and both survive.

**Route B — cross-check disagreement.** `layer:pixel`, `confidence:measured`. Asserted iff the
finding carries *both* operands and the tolerance it exceeded, e.g. `{"dom": 8.0, "pixel": 13.2,
"tol_px": 1.0}`. A cross-check finding missing an operand is `abstained`, not asserted — the
provisional centroid arm ships disabled behind `--x2` for exactly this reason (it compares ink to the
element's own post-transform box, so its number is invariant under the compensation it claims to
verify, and its background is the crop's modal colour so a square crop's corners count as ink). A
number nobody can reproduce from named operands is not evidence.

**Route C — re-grounding a model finding.** The only route by which "the model said so" becomes a
fact. Four steps, all mechanical:

1. Resolve the model's `bbox_raster` to a `backendNodeId` (§2.2). Failure ⇒ `advisory`, reason
   `unlocatable`.
2. Ask the verifier for a **predicate**, not a verdict (§3.3).
3. Evaluate the predicate against `facts/snapshot.json` — in the arbitrator, in Python, with no model
   in the loop.
4. True ⇒ `asserted`, `evidence:"regrounded"`, and `layer` flips from `judgement` to `dom` or
   `pixel` depending on which fact table the predicate read. False ⇒ §3.4. No predicate available ⇒
   `advisory`, terminal.

The flip in step 4 matters: once re-grounded, the finding is no longer an opinion and stops being
subject to the advisory cap. Its `origin:"model"` field is retained forever, so we can measure later
whether model-originated assertions hold up as well as rule-originated ones.

### 3.3 The verifier returns a TEST, not a verdict

This is the answer to "a verify stage can also delete valid findings": the verifier is given no
authority to delete, because it does not emit verdicts. It emits a predicate that the arbitrator
runs. A predicate is reproducible, inspectable, and re-runnable on the next commit; a verdict is
none of those.

**Verifier context — exactly three things, and no more:**

1. the finding's `claim` string and its resolved `backendNodeId`;
2. the fact-pack rows for that node and its ancestors up to the nearest stacking context (typically
   6–20 rows; the *entire* fact pack is ~854 tokens, so this is cheap enough that withholding is not
   a budget decision);
3. **at most one** image: a `--clip`ped re-capture of the disputed region at ≤1000×1000 CSS px @2
   (~1 600 tokens), and only when `--reground-budget` allows. Never the annotated overlay as a
   standing input — the same findings as JSON coordinates are ~840 tokens against ~3 240 for an
   overlay that must be supplied *in addition to* the clean frame, and beyond 20 image blocks per
   request oversized images are rejected rather than downscaled.

**Verifier prompt (verbatim):**

```text
You are converting one design-review finding into a TEST. You are not deciding whether the
finding is true. Do not agree with it and do not argue with it.

FINDING
  class:  {defect_class}
  node:   backendNodeId {node_id}  ({tag}.{classes})
  claim:  "{claim}"

BROWSER FACTS FOR THAT NODE AND ITS ANCESTORS
{fact_rows}

Write ONE predicate over these facts that is TRUE exactly when the claim holds, using only:
  facts.node["<id>"].<field>          field access
  == != < <= > >=                     comparison
  and · or · not                      boolean
  abs(x) · min(x,y) · max(x,y)        arithmetic
  numeric and double-quoted string literals

The predicate must be able to come out FALSE on some page. A predicate that is true of every
page is not a test. If the claim is about whether the page reads well, is balanced, is
confusing, or draws the eye wrongly, there is no such predicate and you must say so.

Reply with JSON and nothing else:
  {"predicate": "<expression>", "reads": ["<field>", ...], "falsifiable_by": "<one sentence
   naming a concrete page state that would make this predicate false>"}
or
  {"predicate": null, "why": "<one sentence: which part of the claim no browser fact can settle>"}
```

`falsifiable_by` is not decoration; it is checked. A predicate whose `falsifiable_by` names no page
state, or which the arbitrator evaluates as constant-true against a synthetic mutation of the named
fields, is discarded as vacuous and the finding falls to `advisory`. Two of our own instruments have
already shipped a number that was invariant under the thing it measured; a predicate that cannot fail
is the same defect one layer up.

**Evaluation** is ~40 lines of Python: `ast.parse` the expression, walk it against an allowlist of
node types (`Expression, BoolOp, UnaryOp, Compare, Call, Attribute, Subscript, Name, Constant`), an
allowlist of call targets (`abs, min, max`), and a single bound name `facts`. Anything else raises
and the finding falls to `advisory` with reason `predicate-rejected`. No `eval` of model output
without that gate, ever.

### 3.4 How many verifiers: ONE, sampled asymmetrically

**One verifier, on the promotion path.** Not three, not a panel, not a majority vote. Three reasons,
in order of force:

1. **Ensembling buys nothing over a predicate.** Once the verifier's job is to write a test rather
   than to render an opinion, running the test twice returns the same answer. What a second verifier
   would vary is the *predicate*, and a disagreement between two predicates is not a signal about the
   finding — it is a signal that one of them is badly written, which `falsifiable_by` already catches
   more cheaply.
2. **Aggregated model judgement is measurably unreliable at exactly this task.** Rubric scoring shows
   16–39 % top-1 ranking reversals from reordering alone; pairwise order-invariant consistent accuracy
   runs ~30–37 % against a 25 % chance baseline. A vote over three such judges is a vote over three
   correlated coin flips presented as a quorum.
3. **Intrinsic self-refinement is abandoned upstream.** Critique-your-own-output loops without an
   external signal often fail to improve and degrade performance (Huang et al., ICLR 2024; Kamoi
   et al., TACL 2024). The field moved to generator/verifier separation with *tool-grounded* critique,
   which is precisely what routing the verdict through an executed predicate produces.

**The asymmetry.** Rejection is the destructive direction and it is where a valid finding dies, so it
is made three times harder than promotion:

| outcome | sampling |
|---|---|
| predicate evaluates **true** → `asserted` | 1 sample |
| predicate evaluates **false** → would reject | **re-sample the predicate 3× independently** (fresh context, no prior predicate shown). Reject only if **all three** evaluate false and read overlapping fields. Any split ⇒ `advisory` with reason `predicate-unstable` |
| predicate is `null` | 1 sample → `advisory`, terminal |

Cost is bounded and paid only on the rejection path: ~600 tokens × 3 × (number of failing findings),
which on our corpus is a handful per page. This is the operational form of §2.4's arithmetic — with
the FP-rate upper bound and the novel-TP rate indistinguishable at 23.1 % each, the stage must be
harder to talk *out* of a finding than into one.

**Where a second opinion IS warranted** and is not a verifier: comparing two candidate designs. If
that ever happens, permute over 3–5 orderings (which recovers about two-thirds of the benefit of ten;
exact balancing buys essentially nothing) and report discrimination spread and swap-consistency,
never mean agreement. That is P8's problem, not this stage's.

---

## 4. Severity — computed, never asked for

Severity is a two-axis lookup. **The model never sets it**, for the same reason it does not set
verdicts: the reliability numbers above apply to graded judgement even more than to binary ones.

| impact class | asserted | advisory |
|---|---|---|
| **A — access/function denied**: contrast below the applicable floor, text clipped by `overflow:hidden`, occlusion of interactive content, target < 24 px | `blocker` | `major` |
| **B — systematic inconsistency**: grid violation, token drift, spacing distribution outlier, numeric-column alignment | `major` | `minor` |
| **C — local/cosmetic**: 1 px edge, optical centring, single-instance radius or shadow drift | `minor` | `note` |
| **D — instrument conflict**: `substrate-disagreement` | `major` (always) | n/a |
| **E — unverified axis**: any `abstained` finding | `unverified` — a rung of its own, deliberately not on the severity scale | |

Three rules make the table load-bearing rather than decorative:

- **`blocker` requires `asserted`.** A model alone can never mint one. This is the June ruling
  expressed as an unreachable cell.
- **Advisory is capped one rung below its asserted twin.** The same claim, unproven, is worth strictly
  less, and the report must show that difference rather than assert it in a footnote.
- **`substrate-disagreement` is `major` unconditionally**, above the severity its underlying class
  would have earned. An instrument that lies is worse than the defect it lied about, because it
  silently taxes every future run. The gradient case is the live instance: adopting
  `blendedBackgroundColors` naively converts an honest `INDETERMINATE` into a confident false PASS,
  and a pass routes nowhere while an abstention routes somewhere.

**Impact-class assignment is per-repo weighted, not global.** The three apps are three different
problems: `reso-management-app` (Next 16 / React 19 / Tailwind 4) is a design-system conformance
problem where class B is the point; `reso-landing-app` (Next 14, purchased template) is marketing
aesthetics where class B token drift is often intentional and demotes to C; `reso-web-app` sits
between. The weighting lives in `arbitrate.weights.json` keyed by repo, ships with all three at
identity, and is the one knob in this stage a human is expected to turn.

---

## 5. Confidence — bands from the evidence route, and an honest label when unmeasured

Never emit a probability a model produced. The band is a function of *how* the finding was promoted,
which is a fact about our own pipeline rather than an estimate of anything.

| band | route | declared operator-accept rate | measured? |
|---|---|---|---|
| `determined` | Route A — the browser computed it | ≥ 0.95 | partially: 9/9 with 0 control FP on the corpus |
| `measured` | Route B — two substrate readings past a stated tolerance | ≥ 0.85 | 1/2 pixels-only, 0 control FP, n = 2 |
| `regrounded` | Route C — predicate generated and executed true | ≥ 0.75 | **UNVERIFIED — no outcome data exists** |
| `suspected` | judgement, no predicate | *no number is quoted* | — |

`suspected` deliberately carries no number. We measured 0 false positives from blind review over 13
pages, which is encouraging and — Rule of Three again — bounds the rate only at 23.1 %. Publishing
"0 %" from that sample would be a figure with a half-life shorter than the report that quotes it.

**Rendering rule:** every band that is declared but not measured renders with a `†`, and the report
header states how many findings carry an unmeasured band. A calibration nobody has checked, rendered
identically to one that has been, is the failure this footnote exists to prevent.

**Recalibration ledger.** `~/.cache/design-review/outcomes.jsonl`, one line per finding, appended by
whatever downstream tooling observes the disposition:

```json
{"claim_key":"a91f0c2e4b77","band":"regrounded","route":"C","repo":"reso-management-app",
 "disposition":"edited|dismissed|deferred","commit_fixed":"3ab19f0","ts":"2026-09-02T11:04:12Z"}
```

**The recalibration rule is deletion, not tuning.** If a band's observed accept rate falls outside its
declared range across two consecutive windows of ≥ 20 findings, the rung is **removed** and its
findings fall to the rung below. It is not re-tuned downward. A route whose evidence is sound should
produce accepted findings; if it does not, the route is unsound and lowering the advertised number
only launders that fact. `determined` is exempt: it is arithmetic, and a low accept rate there means
the *rule* is wrong, which is a P3 bug report, not a calibration event.

---

## 6. The false-positive budget, and the gate that enforces it before anything ships

~20 % false positives is where an AI reviewer loses human credibility regardless of catch rate. Our
two measured zero-FP runs are the baseline to defend, and defending a measured zero is the only bar
this corpus is large enough to test.

### 6.1 The bar

| rung | budget on the clean control | why this number |
|---|---|---|
| `asserted` | **0, absolutely** | testable at n = 1. Both deterministic layers and blind Opus 5 measured 0/13. A single asserted FP on a control is a *rule* defect, and a rule that fires on a page with no defect will fire on every page |
| `advisory` | **≤ 1 per control page**, each with a row in `control-allowlist.json` carrying a `falsifier` | the credibility cliff is about the ratio a reader perceives; one opinion beside a header stating the asserted count is not what 20 % feels like |
| `abstained` | unbudgeted | an abstention is the honest output of a blind instrument and is what routes work to the next layer. Budgeting it creates pressure to guess |

### 6.2 Why the control corpus must reach n ≥ 16 before any *rate* is quoted

Rule of Three: with zero observed events in *n* trials, the 95 % upper bound on the rate is 3/*n*.

- n = 13 (today) → 3/13 = **21.1 %**, which does **not** clear the 20 % cliff.
- n = 15 → 3/15 = **20.0 %**, exactly at it, which is not under it.
- **n = 16 → 3/16 = 18.75 %**, the first n that is strictly under.

So: **16 clean pages, and until we have them, no false-positive *rate* may appear in any report or
README.** The absolute-zero rule of §6.1 is enforceable at n = 1 and is what actually gates shipping;
the rate claim waits for the sample. Quoting 0 % from 0/13 is publishing a figure whose confidence
interval contradicts the sentence it is in.

The 16 must include **real pages from the three apps**, not only the synthetic corpus. The synthetic
control was not clean: its first run flagged four defects on the hand-authored baseline, three of
which were real WCAG failures the author wrote without noticing (white on blue-600 at 3.68:1,
blue-100 on blue-600 at 3.01:1, both under 4.5:1). A control written by the author encodes the
author's blind spots.

### 6.3 The gate

```bash
design-arbitrate --gate-control --rules bench/detect_dom.py --prompt prompts/judge.md
```

Control identity is a hash, and it covers everything that can change a finding:

```
control_hash = sha256(
    sha256(rules_source) ‖ sha256(xcheck_source) ‖ sha256(prompt_text) ‖
    model_id ‖ prompt_sha ‖ viewport ‖ dpr ‖ device_scale_factor ‖ corpus_version )
```

- Any component changes ⇒ the stored control run is **stale** ⇒ **exit 3, fail closed, no report
  written.** A missing or stale control must never render as a pass: a fail-safe default that mimics
  the healthy output is unfalsifiable, and 164/164 UNKNOWNs once read as a calm restart in this fleet.
- The gate is a **pre-ship** gate, not a per-run one. Per-run, `run.json.control_hash` is compared and
  a mismatch is exit 3 as well; the control run itself is refreshed deliberately.
- **Control pages are interleaved with real pages in the same batch, under indistinguishable
  filenames** (`p07.png`, not `clean.png`). A prompt that can recognise the control can special-case
  it, and a control the instrument can see is not a control. This also keeps the batch under the
  20-image-block ceiling where oversized images are rejected rather than downscaled.
- Every `control-allowlist.json` row carries `falsifier`: a predicate (same DSL as §3.3) that, when it
  evaluates true, retires the allowance automatically. A permanent allowance is a permanent lie.

### 6.4 What the gate cannot catch

It measures FPs against pages we declared clean. It says nothing about **false negatives**, and the
corpus is explicit that the most dangerous failure available is a confident clean report from a
single-substrate agent. That is why §7 gives abstentions their own section above advisories rather
than hiding them: the report's honesty about what it did *not* check is the only defence against the
failure the FP budget structurally cannot see.

---

## 7. The report — ordered by actionability, not by severity

The consumer is a Claude Code agent that will act by editing source. A finding it cannot localise to
a component is a report, not an edit. So the sort key is *how close this finding is to a diff*, with
severity as the tie-break inside each band.

### 7.1 Shape of `report.md`

```text
DESIGN REVIEW  /dashboard @1280x900 dpr2  ·  commit 9f21c0a  ·  control 7c1e4b0f
instrument: dsf pinned ✓ · clamp_safe ✓ · model claude-opus-5, 4 passes
ASSERTED 6  ·  UNVERIFIED 3  ·  ADVISORY 4†  ·  baseline/merged/rejected 11 (§5)
† 4 findings carry a declared-but-unmeasured confidence band

§1  ASSERTED, SOURCE-ATTRIBUTED       — a file:line and a one-line change
§2  ASSERTED, NOT ATTRIBUTED          — true, but you must find the component
§3  UNVERIFIED AXES                   — what nothing in this run could check
§4  ADVISORY (judgement, capped at 5) — opinions, explicitly not facts
§5  APPENDIX                          — baseline · merged · rejected, each with its reason
```

The header can never render "clean". It renders counts including `UNVERIFIED`, so a page on which
every instrument abstained reads as *three axes unchecked*, not as *no problems found*.

### 7.2 Why abstentions sit above advisories

An abstention is a **known hole**; an advisory is an **opinion**. The deterministic layer's most
valuable output on the gradient page was not a finding but
`contrast-indeterminate: cannot compute a ratio, backdrop is an image/gradient — requirement 4.5:1
is UNVERIFIED for this text`. Every silent pass that should have been an abstention is a defect
shipped. Ranking opinions above known holes would invert exactly that.

Each §3 entry names **why** it could not be settled and **which stage owns the retry**:

```text
[contrast-indeterminate] .hero .hero-caption
  backdrop is a gradient; no scalar can represent it. Owner: P4 cross-check (--x2 arm),
  which resolves this class deterministically at 4.81:1 left / 1.57:1 right.
  Not run here: cross-check output absent from this run.
```

### 7.3 The advisory cap

`--advisory-cap 5` per page, sorted by the verifier's `why` specificity, remainder written to
`report.json` only and pointed at by one line. Rationale: the credibility cliff is a perceived ratio,
and five opinions under a header stating six asserted facts reads as a minority. **UNVERIFIED — 5 is
a judgement, not a measurement.** One probe settles it: run the pipeline on 20 real pages across the
three apps at caps of 3, 5 and 10, and record operator dismissal rate per section; the cap is the
largest value at which §4 dismissal stays under §1 dismissal.

### 7.4 One finding, rendered

```json
{
  "id": "F07", "claim_key": "a91f0c2e4b77",
  "defect_class": "numeric-alignment", "origin": "model", "layer": "dom",
  "status": "asserted", "severity": "major", "confidence": "regrounded",
  "target_key": "b1741", "target_path": "table.bookings > tbody > tr > td.amount",
  "claim": "the amount column is left-aligned, so the digits do not line up",
  "predicate": "facts.node[\"b1741\"].computed[\"text-align\"] == \"left\" and facts.node[\"b1741\"].role == \"cell\"",
  "predicate_result": true,
  "falsifiable_by": "the same column with text-align:right would make this false",
  "observed": {"text-align": "left", "siblings_same_class": 7},
  "bbox_css": [812, 344, 96, 22], "bbox_raster": [1624, 688, 192, 44],
  "seen_in": ["full", "crop-2"], "corroborates": [], "conflicts": [],
  "source": {"file": "app/(app)/bookings/BookingTable.tsx", "line": 118, "how": "react-fiber"},
  "fix": "add text-right to the amount cell class list"
}
```

`source` is populated by P2, not here (§8). `fix` is a single line and is present only when the
predicate's `reads` fields determine it; the arbitrator never invents one.

---

## 8. What this stage cannot do — and who owns it

| not this stage | owner | note |
|---|---|---|
| **Source attribution** (`file:line`) | **P2 extract.** `DOM.getNodeForLocation` → node, then React fiber / component-stack metadata → source, which is what Next.js's own dev-overlay click-to-source uses | Without it §1 is empty and every finding lands in §2. This is the highest-leverage missing component in the whole pipeline and it was never assigned in the research wave |
| **Re-capturing a crop for re-grounding** | **P1 capture.** This stage writes `requests.json` and, if the crop is absent, the finding falls to `advisory` rather than blocking | Arbitrate must never shell out to a browser; a stage that captures is a stage that can disagree with its own inputs |
| **Deciding whether the page is good** | **the human.** Ratified June 2026 | No rung above `advisory` exists for it, by construction |
| **Ranking two candidate designs** | **P8**, with 3–5 order permutations and swap-consistency reported, never mean agreement | Order alone moves top-1 by 16–39 % |
| **Finding a defect no substrate saw** | **nothing.** §3 UNVERIFIED is the only honest response | The FP budget is structurally blind to this (§6.4) |
| **Proving an FP *rate*** | **P0 corpus**, which must reach 16 clean pages including real app pages | §6.2 |
| **Saliency admission** | **operator.** UMSI++ weights carry no licence file | Until resolved, `findings/saliency.json` is read but every finding from it is forced to `advisory` regardless of route |

---

## 9. Marked UNVERIFIED, with the one probe that settles each

| claim | why unverified | the one probe |
|---|---|---|
| `regrounded` findings are accepted ≥ 75 % of the time | no outcome data exists; the ledger (§5) has never been populated | run the pipeline over 100 findings across the three apps, log dispositions, compare against the declared band |
| 3× re-sampling makes rejection materially safer than 1× | the asymmetry is argued from the 23.1 %/23.1 % symmetry, not measured | replay the 13-page corpus, force every model finding down the rejection path at 1× and 3×, and count how many injected defects each kills |
| `IoU ≥ 0.90` + ancestor test is the right T3 merge rule | validated only against the two live duplicate pairs in `findings_xcheck.json` | sweep 0.5–0.95 over the corpus and report merges of *distinct* defects at each threshold; the right value is the largest with zero such merges |
| advisory cap of 5 | pure judgement | §7.3 |
| an unclassified model finding should never auto-merge | derived from 3 novel true positives in 13 pages; small sample | grow the corpus and count how often two unclassified findings on one node were the same defect |
| the predicate DSL is expressive enough for the classes we care about | written against the corpus's 15 classes, not against real app pages | run the verifier over 50 real-app model findings and count `predicate: null` — if it exceeds ~50 %, the DSL is the bottleneck, not the model |

---

## 10. The two sentences this stage exists to make true

**A finding is asserted only when a predicate that could have failed was executed and did not.**
Everything else is advisory, abstained, or in the appendix — and the appendix is never empty, because
nothing is ever deleted.





