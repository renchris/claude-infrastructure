# P10 — EVAL: the acceptance gate that makes "100th percentile" a checkable claim

**Stage owner:** `bin/design-eval` — a plain CLI, same surface rule as every other stage (README §8:
an MCP server that dies vanishes from the tool list, and a layer whose job is refusing to guess
cannot itself be silently absent).

**What this stage is for.** Every other stage produces findings. This one produces a **verdict about
the pipeline**, and it is the only path by which a pipeline build becomes the one agents run. It is
not a design gate — the June 2026 ruling stands: *taste stays human, gates adjudicate correctness and
coverage only*. EVAL gates the **instrument**, never the page.

**The claim it has to make checkable.** "100th percentile" is unfalsifiable as written. The
operational restatement this stage implements:

> On every defect class where a human designer is the reference, the pipeline finds what the best
> human finds; on every class where humans are structurally blind (1 px, 5/255), it finds what no
> human finds; and on every class where it can do neither, it **says so** rather than passing.

All three halves are measurable against a known-answer corpus. The third is the one nobody scores,
and it is the one that decides whether the pipeline is safe to act on.

---

## 0. CONTRACT

### 0.1 Invocation

```bash
design-eval run                                   # score a pipeline build against the corpus
  --pipeline  /path/to/checkout                   # the CLI under test; its git sha is recorded
  --corpus    bench/corpus/out                    # a BUILT corpus dir, with manifest.json
  --key       bench/corpus/key.local.json         # plaintext answer key (gitignored — §3.2)
  --model     claude-opus-5                       # judged model; resolved id is recorded (§8.3)
  --seeds     3                                   # branch-order permutations per judgement call
  --lane      t1,t2                               # which ground-truth tiers to score (§2)
  --out       eval/runs/<auto>
  [--compare  eval/runs/<baseline-id>]            # regression mode (§8)
  [--rescore-baseline]                            # replay stored responses under the new key (§9.6)
  [--promote]                                     # write .pipeline-pin on ACCEPT; refuses otherwise

design-eval self-test                             # mutate the SCORER, require each mutant RED (§9.2)
design-eval add-from-fix --repo <r> --fix-sha <s> # mint a T2 corpus item from a real fix (§2.3)
design-eval adjudicate --queue eval/wild.jsonl    # human rater UI for T3 wild findings (§6.2)
design-eval baseline-human --corpus <dir>         # capture/refresh the human key (§6.1)
```

### 0.2 Inputs

| | Input | Shape | Required | If absent |
|---|---|---|---|---|
| I1 | corpus dir | `manifest.json` (`corpus_version`, `tokens`, `control`, `defects[]`), `pages/`, `blind/`, `shots/`, `snapshots/` | yes | exit 2 |
| I2 | answer key | `{item_id: {class, target, detectable_by, magnitude, severity, rect_css, admit}}` | yes | exit 2 |
| I3 | human key | `human_key.json` — per item, per rater, the free-text findings and the adjudicated match | no | human-relative metrics report `NO_BASELINE`, never a pass |
| I4 | pipeline checkout | any tree containing the stage CLIs; `git rev-parse HEAD` must be clean | yes | exit 2 on a dirty tree — a score attributed to an unnamed diff is worthless |
| I5 | prior run | a previous `eval/runs/<id>/` with `raw/` responses intact | only in `--compare` | exit 2 |

**I4's clean-tree assertion is not fastidiousness.** The output of this stage is a promotion record.
A promotion attributed to `HEAD + unknown local edits` cannot be reproduced, cannot be reverted, and
cannot be compared to anything — the whole regression apparatus in §8 keys on that sha.

### 0.3 Outputs

```
eval/runs/2026-08-26T21-04Z_pipe-9f21c0a_opus-5_key-1.2/
  verdict.json          # the machine artifact — §0.4 shape; ONE verdict, all gate results
  scorecard.md          # the human artifact — per-class table, rendered, reproduced verbatim in a close
  matches.jsonl         # one row per (finding, defect) adjudication, with the match key that fired
  suspects.jsonl        # unanimous-miss items and control-suspect findings — NOT scored (§2.5)
  raw/<item>/<call>.json# the exact request (image sha, prompt sha, factpack sha, seed) + response
  leakcheck.json        # proof no item id or class name reached a model payload (§3.2)
  thresholds.json       # every threshold with its derived_from {file, sha, measured_on}
```

`verdict.json`:

```jsonc
{
  "schema": "design-eval/1",
  "verdict": "ACCEPT" | "REJECT" | "INSUFFICIENT_POWER" | "CORPUS_INVALID"
           | "UNRECONCILED" | "SUSPECT",
  "run_id": "2026-08-26T21-04Z_pipe-9f21c0a_opus-5_key-1.2",
  "pipeline_sha": "9f21c0a", "prompt_sha": "sha256:2ab9…",
  "corpus_version": "1.2", "key_version": "1.2", "control_render_sha": "sha256:7c1e…",
  "model": { "requested": "claude-opus-5", "resolved": "claude-opus-5-20260714", "seeds": [8823, 4417, 9102] },
  "gates": [
    { "id": "A1a", "name": "fp_on_control_high_med", "value": 0,    "bound": "<= 0",   "pass": true,
      "derived_from": { "what": "measured zero FPs, three detectors", "file": "README.md", "sha": "…" } }
  ],
  "metrics": { "…": "§5" },
  "suspect_count": 0,
  "promotable": true
}
```

### 0.4 Exit codes — and the rule that stops them collapsing

| Exit | Verdict | Meaning | Remedy — **different in every row** |
|---|---|---|---|
| 0 | `ACCEPT` | every active gate passed | promote |
| 1 | `REJECT` | a hard gate failed | fix the pipeline |
| 2 | — | usage / input error | fix the invocation |
| 3 | `INSUFFICIENT_POWER` | the gate that would have decided has too few observations (§7.2) | **grow the corpus** — the pipeline is not implicated |
| 4 | `CORPUS_INVALID` | a null item, a dirty control, an unstable capture, or a key leak | **fix the instrument** — no score in this run means anything |
| 5 | `UNRECONCILED` | a threshold's `derived_from` sha moved (§9.1) | re-derive the threshold, then re-run |
| 6 | `SUSPECT` | unanimous-miss or control-suspect items await human adjudication (§2.5) | adjudicate, then re-run |

🚨 **A consumer may treat only `0` as promotable and must not fold 1/3/4/5/6 into "failed".** Three of
those five say nothing about the pipeline at all, and a caller whose `*)` arm collapses them will
"fix" a corpus problem by editing detectors. This is the repo's own
`new-enum-member-falls-into-fail-closed-default` trap, pre-empted.

---

## 1. What EVAL cannot do, and who owns it

| Cannot | Why | Owner |
|---|---|---|
| Say a page is well designed | ratified June 2026; and the construct's own inter-rater reliability is α = 0.248 among designers, so a threshold on it would be a threshold on noise | the operator, unaided |
| Certify bounding-box quality against a standard | no published number does: every ScreenSpot variant scores point-in-box with no box-quality term, and the best learned GUI detector reaches F1 0.438 at IoU > 0.9 | nobody — EVAL reports the raw IoU distribution and gates only on *unlocalised* (§7 A4) |
| Prove the review improved the product | needs a longitudinal outcome (fix accepted / reverted / ignored) that only ATTRIBUTE observes | ATTRIBUTE writes the record; EVAL reads it (§5.5) |
| Find a defect class nobody has imagined | a corpus is a closed world by construction | the blind judge's open-ended pass; EVAL's job is to *count the novel rate*, §9.4 |
| Say what the review never looked at | EVAL scores the cells the corpus contains; it cannot enumerate the review surface a run failed to photograph | P13 THE HUMAN GAP — its `surface.json` is the denominator EVAL's coverage census (§2.4) reports against, and the two must not both try to own it |
| Decide whether the capture was faithful | that assertion lives upstream (`clamp_safe`, `device_scale_factor_pinned`, capture-twice) | CAPTURE — EVAL refuses to score a run whose manifest says either is false (exit 4) |

---

## 2. Ground truth: three tiers, one admissibility test

### 2.1 The tiers

| Tier | What it is | Count today | Grows by | Weakness it has, that the next tier covers |
|---|---|---|---|---|
| **T1 synthetic** | `bench/corpus/build_corpus.py` — one dashboard, 1 clean control + 12 single-defect variants, each with class / target / magnitude / `detectable_by` | 13 pages, 12 defects (9 DOM, 3 pixels) | generated; magnitudes rotate per minor version (§9.3) | it is *our* idea of a defect, at *our* chosen magnitudes |
| **T2 harvested** | a real fix in one of the three apps, replayed: parent commit = defect page, fix commit = control page | 0 — **this is the tier to build** | `design-eval add-from-fix` (§2.3) | slow to accumulate; only covers defects someone already fixed |
| **T3 wild** | defects found on a live page that nobody injected — the three Opus 5 found blind (orphan legend, unlabelled smallest-hit-target icon button, left-aligned numeric columns) | 3, unratified | the adjudication queue (§6.2) | has no key until a human makes one; enters as a *quarantined FP*, never as a silent TP |

**T1 alone cannot support the precision gate** and the eval says so mechanically: §7.2's power rule
returns `INSUFFICIENT_POWER` rather than a pass until the scored-finding count clears 60. That is how
"grow the corpus" becomes an enforced obligation instead of a recommendation nobody drains.

### 2.2 ADMISSIBILITY — the null-item guard

The measured incident this exists for: the `optical-centering` variant injected an **empty CSS rule**.
Its render was SHA-256 identical to the control. Two detectors correctly reported nothing and were
both graded as failing — the corpus convicted two right answers, and it took a *third* detector
disagreeing before anyone looked at the item. A corpus that can do that is not an instrument.

`design-eval` refuses to score a corpus that has not passed admissibility. Every variant carries four
build-time facts, all computed by the **same capture path the pipeline uses**, never a side channel:

```jsonc
{ "item": "optical-centering",
  "html_sha256":  "…",            // served document bytes
  "render_sha256":"…",            // PNG bytes at the pinned DPR and flags
  "dom_delta":    [ { "selector": ".btn-icon > svg", "prop": "transform",
                      "before": "none", "after": "translateX(-2px)" } ],
  "pixel_delta":  { "count": 1184, "max_channel": 37, "bbox_css": [612, 244, 32, 32] },
  "admit": true }
```

| Rule | Fires when | Build result |
|---|---|---|
| **N1 document reached** | `html_sha256 == control.html_sha256` | `NULL_ITEM` — the injection never reached the served page |
| **N2 render moved** | `render_sha256 == control.render_sha256` | `NULL_ITEM` — byte-identical to the control; **this is the measured bug** |
| **N3 tier honesty** | `detectable_by=="dom"` and `dom_delta == []` | `MISLABELLED` — no computed style changed, so no DOM rule can be expected to fire |
| **N4 tier honesty** | `detectable_by=="pixels"` and `pixel_delta.count == 0` | `MISLABELLED` — the exact optical-centering shape |
| **N5 magnitude honesty** | the declared `magnitude` disagrees with `pixel_delta.max_channel` or `dom_delta` by more than a stated factor | `MAGNITUDE_DRIFT` — warn, do not block |

Any `NULL_ITEM` or `MISLABELLED` ⇒ **exit 4, `CORPUS_INVALID`, and no score is emitted at all.** Not a
skipped item, not a warning: a corpus with a broken item has an unknown denominator, and every rate
computed over it is a fiction.

**The tolerance question, answered by refusing to have one.** `pixel_delta.count > 0` is an exact
test, admissible only because the capture stack is bit-reproducible — sRGB pinned, LCD text off,
reduced motion, fonts awaited, `--force-device-scale-factor` set, and CAPTURE's own capture-twice gate
(`stability.sha_a == sha_b`). If that gate ever reports `equal: false`, EVAL exits 4 rather than
inventing a noise tolerance to absorb it. **A tolerance invented to swallow instrument noise you have
not measured is how an unstable instrument becomes invisible** — and the number you would pick would
be exactly the number that hides the problem.

**Free localisation ground truth.** `pixel_delta.bbox_css` is the *derived* answer rect for every
pixels-only item — nobody hand-authors it, so nobody can hand-author it wrong. For DOM items the
answer target is the selector the generator injected against, which is exact by construction.

### 2.3 Growing T2 — one command, because a two-command filing cost never drains

```bash
design-eval add-from-fix --repo ~/Development/reso-management-app \
                         --fix-sha 4c1e77a --route /dashboard --viewport 1440x900
```

What it does, in order, refusing at the first step that fails:

1. Asserts the fix commit's diff touches only style-bearing files (`*.css`, `tailwind.config.*`,
   `className=` hunks in `*.tsx`). A behavioural fix is not a visual-defect item — reject, exit 2.
2. Builds and captures the route at `fix_sha^` (defect) and `fix_sha` (control), through the *pipeline's
   own* CAPTURE, with the same pins.
3. Runs the §2.2 admissibility test between them. `render_sha256` equal ⇒ **the fix changed no pixel on
   this route**, which is itself a finding worth surfacing, and the item is rejected.
4. Derives `rect_css` from `pixel_delta.bbox_css` and `dom_delta` from the two snapshots.
5. Asks for exactly two human fields — `class` (from the closed class list, §4.2) and `severity` —
   then writes the item and a `provenance: {repo, fix_sha, added_on}` record.

Steps 1–4 are machine. The human types two words. **If minting a corpus item costs more than that, the
queue of items-to-add will sit at a p90 of days and the corpus will stop tracking reality** — which is
the failure mode this whole tier exists to prevent.

### 2.4 The corpus grows on the axis it is thinnest, not the axis that is easy

Generating another spacing variant is trivial and worth almost nothing: the DOM layer is already 9/9
there. The scorecard therefore prints a **coverage census by (class × detectable_by × app-profile)**
and the growth rule is *fill the empty cells first*. Today's empty cells, from the manifest:

- `visual-hierarchy`, `semantic-coherence`, `optical-alignment` have **one item each**. Every
  judgement-class rate is currently a 1-of-1 measurement, i.e. 0% or 100% and nothing between.
- `landing` and `web` app profiles have **zero** items; all 13 pages are one management-style dashboard.
  Marketing aesthetics — the `reso-landing-app` problem — is entirely unmeasured.
- Every item is light theme, one viewport, one DPR.

**Growth target that makes the judgement gates meaningful:** ≥ 8 items per judgement class. Reason: at
n = 8 a gate set at 0.50 (§7 A2) separates a true rate of 0.8 from a true rate of 0.4 —
P(≥4 of 8 | p=0.8) = 0.995 versus P(≥4 of 8 | p=0.4) = 0.406 — which is the smallest n where the gate
is doing work rather than reporting a coin flip. Below that, §7.2 reports the class as
`INSUFFICIENT_POWER` and names the exact number of items still needed.

### 2.5 SUSPECT items — the corpus is a defendant too

Two symmetric arms, each promoted from a measured incident, and both are *abstentions by the eval*:

| Arm | Trigger | Why the item, not the detector, is the suspect | Result |
|---|---|---|---|
| **Unanimous miss** | every independent layer (DOM rules · cross-check · judge at every seed) scores 0 on one item | three uncorrelated detectors agreeing is weak evidence about the page and strong evidence about the *item* — exactly the optical-centering shape | the item is written to `suspects.jsonl`, **excluded from recall denominators**, and the run exits 6 |
| **Control suspect** | ≥ 2 independent layers report the *same* `(class, target)` on the clean control | measured: the first control run flagged four defects and **three were real WCAG failures the author wrote without noticing** (white on blue-600 at 3.68:1, blue-100 on blue-600 at 3.01:1) | the finding is **not** counted as a false positive; it goes to adjudication, and on ratification the control is fixed and the key version bumps |

Both arms fail toward *not scoring* rather than toward a number. A run that exits 6 has produced no
verdict about the pipeline — which is correct, because it has just produced evidence that the ruler is
bent, and a measurement taken with a bent ruler is not a smaller measurement, it is not one.

---

## 3. Blindness discipline — a filename is an answer key

### 3.1 The serving rule

The corpus already ships the right primitive: `out/blind/page-A.html … page-H.html` with
`blind_key.json` mapping letters to item ids. EVAL extends it to **every artifact that crosses into a
model request**:

- image path: `blind/page-C@2x.png`, never `contrast-on-gradient@2x.png`
- factpack, snapshot, crop captions, `route-plan.json` ask strings: item id and class name stripped
- the letter assignment is **re-randomised per run** from `hash(run_id, item_id)`, so a letter memorised
  from a transcript carries nothing to the next run
- PNG metadata: EVAL strips all ancillary text chunks (`tEXt`, `iTXt`, `zTXt`) before serving. A
  generator that writes its source filename into a `tEXt` chunk leaks the key through a channel no
  reviewer would think to check.

### 3.2 The leak check is mechanical, not a promise

Before any request is sent, EVAL scans the **fully serialised payload** — prompt text, every JSON
block, and the decoded PNG's non-IDAT chunks — for the literal item id, the class string, the
generator's variant filename, and the `css` snippet from the manifest. Any hit ⇒ exit 4, and
`leakcheck.json` records `{scanned_bytes, needles, hits: []}` on every run, so a run with a
*disabled* leak check is distinguishable from a run with a *clean* one. (`scanned_bytes: 0` is the
signature of the check having silently not run; the gate asserts it is non-zero.)

**What this does not defend.** It does not defend against a model that has memorised the corpus *page*
rather than its answers — the dashboard's markup is in this repo and in transcripts. §9.3 handles that
separately, and §10 P3 states the probe.

---

## 4. Matching a finding to a defect

### 4.1 The match key spans the CLAIM, not the location

Measured failure, reproduced live in the bench: deduplicating findings on `(rule, target)` **silently
swallowed a real defect** — the colour-token drift on the primary button was suppressed because an
unrelated `token-drift` finding already sat on that element. It scored 0/1 until the key was widened,
then 1/1. The same lesson binds the *matching* key here, because matching is dedup's mirror.

A finding `f` matches defect `d` iff **both** hold:

1. **Target agreement** — the strongest available key, tried in order and recorded in `matches.jsonl`:

   | | Key | Applies to | Verdict |
   |---|---|---|---|
   | K1 | `f.backend_node_id == d.backend_node_id` | any finding carrying a `DOM.BackendNodeId` — i.e. everything from the DOM and cross-check layers, free from the same `captureSnapshot` pass | `EXACT` |
   | K2 | normalised selector equality, or `d.target` is `f.target`'s parent or only text child | DOM findings whose node id was lost in transit | `EXACT` |
   | K3 | `IoU(f.rect_css, d.rect_css) >= 0.5` | judgement findings with no node id | `LOCALISED` |
   | K4 | centre of `f.rect_css` inside `d.rect_css` (or vice versa) | ditto | `WEAK` — counted, flagged, never promoted past `advisory` |
   | K5 | none of the above | — | `UNLOCALISED` — **not a match**, and §5.4 counts it |

2. **Class agreement** — `f.class == d.class`, or `f.class ∈ d.accepts[]` (a small hand-curated
   synonym set in the key, e.g. `optical-alignment` accepts `misalignment` *only when* the finding's
   own evidence cites ink centroid). Right target + wrong class is **`NEAR_MISS`**, reported in its own
   column, never folded into recall.

`IoU ≥ 0.5` is the standard detection convention and is used here for one reason: it is the only
localisation bar in this document that has to be *chosen* rather than derived, and choosing the
field's default is more honest than inventing a bespoke one. Note explicitly what it is **not**: it is
not a certification of box quality. No published number certifies that (every ScreenSpot variant scores
point-in-box; the best learned detector reaches F1 0.438 at IoU > 0.9), so §7 gates on the *unlocalised
rate* and merely reports the IoU distribution at 0.5 and 0.75.

### 4.2 The closed class list

Matching requires a closed vocabulary or every rename becomes a recall cliff. The list is the union of
the corpus manifest's `klass` values and the classes the judge is permitted to emit:

```
spacing-inconsistency · misalignment · token-drift · typographic-scale · grid-violation
contrast · overflow · accessibility · optical-alignment · visual-hierarchy
semantic-coherence · affordance · content-fit · motion
```

Adding a class is a **key-version bump** (§9.6), because it changes the denominator of every per-class
rate. A detector emitting a class outside the list has its finding counted as `UNCLASSIFIED` — which
counts against precision, deliberately: an uninterpretable finding costs a reader exactly as much as a
wrong one.

### 4.3 One finding may satisfy at most one defect

Greedy assignment in descending match strength (`EXACT` before `LOCALISED` before `WEAK`), each defect
consumed once. Surplus findings on a defect page that match no defect are **false positives**, exactly
as on the control — an unmodified element of a defect page is unmodified. That rule is already written
into the corpus manifest's own `scoring.false_positive` definition and is inherited here verbatim.

---

## 5. Metrics

Every metric is reported **per layer** (`dom` · `xcheck` · `judgement`) and **per class**, never only
in aggregate. An aggregate hides the one property the architecture depends on: that each layer covers
what the others cannot. A pipeline whose union recall is unchanged while the DOM layer silently
collapsed and the judge compensated is a pipeline that has become 60× slower and 1,000× more
expensive at the same score, and only the per-layer split can see it.

### 5.1 Recall — `recall[class][layer]` and `recall[class][union]`

Denominator = admissible items of that class, minus `suspects`. The union row is the number the
architecture claims (11/11 today across three layers); the per-layer rows are what regression testing
actually watches.

### 5.2 Precision and the two false-positive rates

- `precision` = TP / (TP + FP + UNCLASSIFIED), over all pages, all layers.
- `fp_per_control_page` = findings on control pages, by severity. **This is the credibility metric**
  and it is deliberately an absolute count, not a rate: a rate lets a large corpus dilute a real FP
  into invisibility, and the reader's experience is per page.
- `fp_on_unmodified_elements` = findings on defect pages matching no defect. Reported separately
  because it has a different cause — a rule over-firing versus a rule firing on the wrong page.

### 5.3 Abstention integrity — the two-sided metric nobody publishes

The substrate's sharpest claim is that the deterministic layer's most valuable output is an
*abstention*, because an abstention routes to the judge and a false pass routes nowhere. That makes
abstention a scored object, in both directions:

| Metric | Definition | Why both are needed |
|---|---|---|
| `abstention_recall` | of the items the DOM cannot determine, the fraction that produced an `INDETERMINATE` **or** a cross-check hit | a missing abstention is a *silent* pass — the highest-cost failure available to this pipeline, and the one no other metric can see |
| `false_abstention_rate` | abstentions raised on subjects the DOM fully determines ÷ all subjects | abstentions are the vision layer's job queue, so an abstention flood is a **cost** regression wearing safety's clothes; a layer can score 1.00 on the first metric by abstaining on everything |

The gradient case is the worked example: `contrast-on-gradient` must produce either
`contrast-indeterminate` from the DOM rules or `xcheck-contrast-varies` (measured: 4.81:1 left third,
1.57:1 right third). A run in which it produces a confident **PASS** — which is exactly what naively
adopting `blendedBackgroundColors` does, since that API returned the gradient's leftmost stop at
10.36:1 where the text actually sits at 1.22:1 — fails `abstention_recall` and is a REJECT. **This is
the one gate that catches a change which improves every other number while destroying the pipeline.**

### 5.4 Localisation

`localisation_mix` = the counts of `EXACT` / `LOCALISED` / `WEAK` / `UNLOCALISED` per layer, plus the
IoU distribution (report p50, and the fraction at ≥0.5 and ≥0.75) for judgement findings only.

One derived counter matters more than the distribution: **`node_id_droppable`** — judgement findings
that arrived without a `backend_node_id` when the region they name *has* one in the snapshot. That is
not a model failure, it is a ROUTE/PROMPT plumbing defect, and attributing it to the model would send
someone to improve a prompt to fix a missing field.

### 5.5 Actionability — the terminal metric

A15's sharpest point is that the probable failure of this whole programme is a system that **sees
fine, critiques plausibly, and changes nothing**. Everything above measures seeing. This measures the
loop closing, and on T1/T2 it is fully machine-checkable because the control render exists:

```
fix_verifiable_rate = |{ TP f : apply(derive_edit(f)) ⇒ re-render == control.render_sha256 }|
                      ────────────────────────────────────────────────────────────────────────
                      |{ TP f : the item has a control render }|
```

`derive_edit(f)` is not a model call. It is: take ATTRIBUTE's `targets[0]` (file + line + property),
take the control's computed value for that property on that node from the control snapshot, write it.
The item then re-renders through the same CAPTURE and its PNG must become byte-identical to the
control's. **Nothing about that chain is a judgement, so nothing about it can be argued with.**

Three sub-counters, because the chain fails in three different places and the remedies are opposite:
`attribution_missing` (ATTRIBUTE returned `UNATTRIBUTABLE`) · `attribution_wrong` (it named a file, the
edit landed, the render did not converge — **the dangerous one**, a plausible wrong path an agent
would have edited) · `edit_underdetermined` (the finding names a problem but no property, e.g. most
judgement findings).

Judgement findings will score near zero here **by construction**, and that is not a defect: "the
secondary button outweighs the primary" has no single property to revert. So `fix_verifiable_rate` is
gated only over `dom` + `xcheck` findings, and for judgement findings actionability degrades to the
human three-way vote in §6.2 — act / defer / reject — which is taste, and stays human.

---

## 6. The human baseline, given that designers do not agree

**The move that makes this tractable: never ask humans the question they disagree on.** Krippendorff's
α = 0.248 (four-way α = 0.114; 28.5% of pairs at ≥96% disagreement) is measured on **design
preference**. It is not a fact about human perception, it is a fact about that *construct*. Defect
*detection* is a different construct with a right answer, and human agreement on it is high. So the
human baseline is established on two tasks only, and preference is never one of them.

### 6.1 Task A — blind detection on known-answer items (`design-eval baseline-human`)

Protocol: a designer sees `blind/page-X.png` at native resolution, on a calibrated display, with the
page's stated purpose and nothing else, and writes free-text "what is wrong here". Ten minutes per
page, no zoom tooling beyond the OS's, no DOM inspector — the point is to measure the *human eye*, not
a human with our instrument. Their findings are matched against the key by §4's algorithm, adjudicated
once by a second designer where the match is `NEAR_MISS`.

This produces `human_key.json` — per class, `human_recall_best` (the single best rater) and
`human_recall_median`. Three raters is enough because the output is a per-class ceiling, not a
significance test, and the ceiling is set by the best rater.

**It is a stored artifact, refreshed only for items added since.** A human baseline re-collected every
run would rot the panel's attention and cost more than the pipeline. Each item's human answers carry
`rated_on` and the rater id; `design-eval baseline-human` only queues items with no record.

**The predicted shape, and why it is the point.** Humans will score at or near **zero** on
`token-color-drift` (5/255 on one channel — below the just-noticeable difference) and on `align-1px`.
They will score at or near **one** on `hierarchy-inversion` and `contrast-on-gradient`. That
asymmetry is exactly the 100th-percentile claim made checkable: the pipeline must **beat** the human
ceiling on the sub-perceptual classes (where the DOM layer is exact and the human is blind) and
**meet** it on the judgement classes. Two different bars, and neither is a single "score".

### 6.2 Task B — adjudicating wild findings, with a rubric tree (`design-eval adjudicate`)

For T3 findings there is no key, so the human makes one. The question is binary with a rubric, never a
ranking, and the rubric is copied rather than invented: WebDevJudge measured naive direct comparison at
**65%** inter-annotator agreement and rubric trees at **89.7% with ties / 94.0% without** — a 25-point
lift from the protocol alone, which is larger than any model difference in this document.

The tree, three nodes, asked in order and stopping at the first `no`:

1. **Is the claim true of the render?** (a factual question about pixels — high agreement expected)
2. **Would it degrade a real user's experience of this page?** (severity, not preference)
3. **Would you make the edit?** (act / defer / reject — this is the taste node, and it is the only one
   whose disagreement is expected and reported rather than resolved)

Three raters, majority. **Report α for the adjudication task itself, per node.** If node-1 or node-2
α < **0.67** for a class, that class is declared UNMEASURABLE and **removed from the acceptance gate**
— reported forever, gated never. 0.67 is Krippendorff's own published floor for tentative conclusions;
it is not a number this document chose. Node 3 is never gated at any α.

A ratified wild finding becomes a permanent scored item on the page where it was found, with
`ratified_on`. That **retroactively converts a past false positive into a true positive**, which is
why §9.6 forbids comparing precision across key versions without a re-score.

### 6.3 The operator is rater-of-record for taste, alone

Where the question is "is this good", there is one rater, no α, and no gate. That is not a compromise
with a small panel; it is the June 2026 ruling implemented: *taste stays human, gates adjudicate
correctness and coverage only.* A pipeline that reported an aesthetic score would be reopening a
ratified decision by arithmetic.

---

## 7. Acceptance thresholds

### 7.1 The gates

Every bound below is a number with a reason. Where the reason is "this is what we measured", the gate
**defends the measurement** rather than granting slack we did not need — slack granted at design time
is spent immediately and never recovered.

| | Gate | Bound | Scope | Reason for exactly this number |
|---|---|---|---|---|
| **A1a** | `fp_per_control_page` at severity high or medium | **= 0** | all layers | Measured: all three detectors scored **zero** FPs on the clean control. Zero is the observed baseline; a threshold above it would concede ground nobody has lost. |
| **A1b** | `fp_per_control_page` at severity low | **≤ 1** | all layers | One low-severity nit per page is inside what a reader forgives; two reads as noise. Weakest-justified number in the table — marked PROVISIONAL, replaced by the first ten control runs' observed distribution. |
| **A1c** | `precision` | **≥ 0.80** | all findings | ~20% false positives is where an AI reviewer loses human credibility *regardless of catch rate*. 0.80 **is** that boundary; the gate sits on it rather than inside it, so the failure is visible before credibility is spent. |
| **A2a** | `recall[class][union]` for DOM-determined classes: spacing · misalignment · token-drift · typographic-scale · grid-violation · contrast-solid · overflow · accessibility | **= 1.00** | union | Measured **9/9** today, and every one of these is arithmetic over `getBoundingClientRect` and computed styles. A miss is a rule regression, not a hard case. Any tolerance here converts a broken rule into an acceptable score. |
| **A2b** | `recall` for `contrast` over a varying backdrop | **= 1.00** | xcheck | The cross-check settles it deterministically — 4.81:1 left third vs 1.57:1 right third, no model, no abstention. Once a case is arithmetic it is held to arithmetic's standard. |
| **A2c** | `recall[class][judgement]` for visual-hierarchy · semantic-coherence · affordance · content-fit | **≥ 0.50** | judgement layer, ≥8 items/class | The nearest published ceilings: DiffSpot best-of-13 at **47.2%** (hard tier < 23% for every model; `line-height` median recall **4.0%**), WebDevJudge best model **66.06%** against humans at **84.82%**. 0.50 sits just above the best published result on the closest task and well under the human ceiling — a floor that says *at least as good as the field*, which is a reason. Gating higher would gate on noise. |
| **A2d** | `recall` for sub-perceptual classes (≤2 px geometry, ≤8/255 colour) **from the judgement layer** | **expected 0.00 — not gated** | judgement | Measured: blind Opus 5 scored **0/2** on a 1 px misalignment and a 5/255 drift. Asking for recall here asks the model to fail. |
| **A2e** | *precision* for sub-perceptual classes from the judgement layer | **= 1.00**, or the claim must appear in `needs_measurement` | judgement | The inversion that makes A2d safe. The local model's failure mode was **inventing** a misalignment at 2 of 3 resolutions, and a detector that invents defects is worse than no detector because an agent acts on it. Below the perceptual threshold the gate is on **abstention, not detection**. |
| **A3a** | `abstention_recall` | **= 1.00** | dom + xcheck | A silent pass routes nowhere. This is the single most expensive failure available to the pipeline and the corpus knows `detectable_by`, so it is exactly measurable. No tolerance. |
| **A3b** | `false_abstention_rate` | **≤ 0.05** | dom | The abstention set *is* the vision layer's spend. 5% is held against the observed indeterminate fraction in SCREEN's worked census (95 of 1,841 subjects = 5.2%). **UNVERIFIED against the three real apps** — §10 P1. |
| **A4** | `unlocalised_rate` | **≤ 0.10** | judgement | An unlocalised finding is not a weak finding, it is a **non-finding**: ATTRIBUTE cannot resolve coordinates it does not have, so it cannot become an edit. No IoU gate accompanies it, because no published number certifies box quality and any IoU bound here would be invented. |
| **A5** | `fix_verifiable_rate` | **≥ 0.70** | dom + xcheck TPs | PROVISIONAL, and labelled so. No precedent exists — this metric is new. 0.70 is chosen as *more often closed than not, by a margin that survives one bad class*, and is replaced by the first measured value once T2 reaches 30 items. Stating a provisional number beats stating none: an ungated metric is one nobody watches. |
| **A6a** | deterministic-layer determinism: `sha256(findings_dom.json)` identical across 5 runs | **exact** | dom + xcheck | They are pure functions of a fixed snapshot. Anything else is a bug, and it is free to check. |
| **A6b** | judgement-layer `stability@5` (mean pairwise Jaccard) and `flip_rate` | **reported, not gated** | judgement | Rubric scoring shows **16–39% top-1 reversals from reordering alone**, and order-invariant consistent accuracy of ~30–37% against a 25% chance baseline. Gating on stability would gate on a known property of the substrate. But it is **published every run**, because it is the error bar on every judgement claim, and an unpublished error bar is how a 30–37%-consistent system reads as reliable. |
| **A7** | seeds actually permuted: every judgement response's echoed `tree_seed` ∈ the seeds EVAL sent | **exact** | judgement | Without the echo you cannot distinguish "permuted, stable" from "never permuted". PROMPT already emits `tree_seed`; this gate is what makes it load-bearing. 3 seeds, because 3–5 orderings recover about two-thirds of the benefit of ten and exact balancing buys essentially nothing. |

### 7.2 The power rule — a gate with too few observations must abstain, not pass

A gate is **INACTIVE** and reports `INSUFFICIENT_POWER` (exit 3) rather than passing when its
denominator is below its stated minimum:

- **A1c precision: n < 60 scored findings.** For a 0.80 point estimate to carry a 95% CI half-width of
  ±0.10 needs n ≈ 62 (`1.96·√(0.8·0.2/n) ≤ 0.10`). Below that, a "pass" is a coin landing heads.
- **A2c per judgement class: n < 8 items.** §2.4's derivation — at n = 8 the 0.50 bound separates
  p = 0.8 (P(≥4/8) = 0.995) from p = 0.4 (0.406). At n = 1, which is today, it separates nothing.
- **A5: n < 30 T2 items** with a control render.

Exit 3 is a distinct code precisely so it cannot be read as a pipeline failure: it names the corpus as
the thing to change, and `scorecard.md` prints the exact shortfall — *"visual-hierarchy: 1 of 8 items;
7 more needed before this gate decides anything."*

### 7.3 What ACCEPT means, said plainly

`ACCEPT` = *this build may be the default agents run.* It does **not** mean the reviews are good, that
the pages are well designed, or that a human need not read the findings. It means: on a known-answer
corpus, this build finds everything arithmetic can find, never silently passes what it cannot compute,
does not invent defects below the perceptual threshold, keeps its false-positive count on clean pages
at the measured zero, and produces findings an agent can act on.

---

## 8. Regression when the model changes underneath

### 8.1 The problem this solves

Three shas move independently — the pipeline's, the prompt's, and the model's — and only the first two
are ours. A model alias can be re-pointed with no diff anywhere in our tree, and a pipeline that was
ACCEPTed yesterday can be a different instrument today with nothing to grep.

### 8.2 Replay, not re-measurement

Every accepted run stores `raw/<item>/<call>.json`: the exact request (image sha256, prompt sha256,
factpack sha256, seed) and the exact response. That makes a run **replayable**, which buys two things
nothing else does — a new key can be applied to old responses (§9.6), and a model change can be
isolated by holding every other input byte-identical.

```bash
design-eval run --compare eval/runs/<baseline-id> --model claude-opus-5
```

`--compare` asserts, and refuses (exit 2) on any mismatch it cannot hold constant: same
`corpus_version`, same `key_version` (unless `--rescore-baseline`), same image shas, same seeds, same
prompt sha. What remains different is the model, and the diff is therefore attributable.

### 8.3 The gate is on `lost`, never on the aggregate

Per item, the comparison is a three-way partition: `retained` · `lost` · `gained`.

| Partition of the corpus | Rule | Reason |
|---|---|---|
| DOM-determined items (A2a/A2b) and the abstention-integrity set (A3a) | **any** found → missed is **REJECT**, whatever the totals say | these are arithmetic; a regression here is a broken rule, and an aggregate that stays flat while composition churns is precisely how it hides |
| Judgement items | `lost > gained` ⇒ **REVIEW** (exit 6, with the items named), not REJECT | judgement churn at ~30–37% order-invariant consistency is the substrate's known behaviour, not evidence of a worse model |
| Novel classes (T3 lane) | rate reported, never gated | §9.4 |

**Aggregate recall is not a gate at any point in this document.** A build can hold recall flat while
replacing every finding it makes, and the replaced set is what a downstream agent experiences.

### 8.4 The canary

One item is designated the model canary: **`hierarchy-inversion`**. It is the item measured to work
blind on Opus 5, it requires no numbers, no rule can reach it, and it is the exact capability the
entire vision layer exists to buy. If it flips, the vision layer's premise has moved.

Run at **5 seeds; gate at ≥ 4 of 5.** With a true rate of 0.9 the test passes 91.9% of the time; with a
true rate of 0.5 it passes 18.7%. A single-shot 1-of-1 canary would fire on a coin flip and be ignored
within a month — an alarm that cries wolf carries as few bits as one that cannot fire.

### 8.5 Pinning the model id

`verdict.json` records `model.resolved` — the `model` field the API echoed in the response body, not
the string we sent. A run whose resolved id differs from the baseline's is a model change **even when
the alias we typed is identical**, and it triggers §8.3 automatically rather than waiting for someone
to notice. **UNVERIFIED**: whether this account's Messages API returns a dated snapshot id for
`claude-opus-5` or echoes the alias. §10 P2 names the one-call probe.

---

## 9. Preventing the eval from rotting

An acceptance gate is a policy artifact, and this repo's measured lesson about policy artifacts is that
**a resident rule restating a perishable fact has no path to learn the fact changed.** Six mechanisms,
each aimed at one decay path.

### 9.1 Every threshold names its source, and staleness is an EVENT not a date

`thresholds.json` carries, per gate, `derived_from: {what, file, sha, measured_on}`. On every run EVAL
re-reads those shas. **If any named sha differs from the current one, the run's verdict becomes
`UNRECONCILED` (exit 5)** — not REJECT, because nothing failed; the ruler's provenance moved and
somebody must look. A 180-day absolute backstop catches thresholds derived from something with no sha
(a published paper, a vendor system card).

Event-triggered beats calendar-triggered because the failure it models is a *change*, not an age. The
precedent is on disk and cost real time: a global ship-policy paragraph was FALSE two days after it was
written, and the calendar had nothing to say about it.

### 9.2 `design-eval self-test` — the eval's own mutants

The corpus grades detectors; nothing grades the corpus and nothing grades the scorer. Five mutants, one
per scoring site, each of which **must** go RED:

| Mutant | Must produce | Catches |
|---|---|---|
| Swap two items' answer keys | a recall drop on both | the key not being read at all |
| Delete one true finding from a detector's output | **exactly one** lost TP | matching too loose — a neighbour absorbing the deletion |
| Duplicate one true finding | **one** TP, not two | the measured `(rule, target)` dedup defect, replayed as a permanent control |
| Add one finding on a clean control | **exactly one** FP | the control page silently not being scored |
| Make one variant byte-identical to the control | **exit 4 `NULL_ITEM`**, no score | the optical-centering incident, promoted from a story into a test |

A green `self-test` is a precondition of `--promote`. One mutant per *site*, because a suite that goes
red as a whole credits no site with being covered.

### 9.3 Contamination

The corpus lives in this repo and in transcripts, so its answers will eventually be memorisable.
Two cheap defences and one honest limit:

- **Salted key.** The committed manifest carries `sha256(item_id ‖ class ‖ target ‖ salt)`; the
  plaintext key lives in a gitignored `key.local.json`. A reader of the repo gets the pages, not the
  answers.
- **Magnitude rotation.** Every corpus minor version re-rolls the injected magnitudes inside their
  class bands — a 23 px gap becomes 21 px, a 6 px radius becomes 7 px, a 5/255 drift becomes 4/255.
  Free, because the corpus is generated, and it invalidates a memorised *answer* without changing what
  is being tested.
- **The limit, stated:** neither defends against a model that memorised the *page*. §10 P3 is the probe
  that would detect it.

### 9.4 The novel-class rate — the anti-overfit alarm, with the right polarity

The T3 wild lane runs the judge on **pages it has never reviewed** and counts findings whose class or
target matches nothing in the key. A healthy pipeline produces some; the three Opus 5 found unprompted
(orphan legend, unlabelled smallest-hit-target icon button, left-aligned numeric columns) are the
existence proof.

Alarm condition: **zero novel findings across three consecutive wild-lane runs on previously unreviewed
pages.** Three runs and the unreviewed qualifier are both load-bearing — a single zero is far more
likely to mean the pages were clean than that the judge has collapsed onto the corpus, and an alarm
that fires on a clean page fires forever.

### 9.5 The eval must be the promotion path, or it is a detector with no owner

This repo has a measured case of **851 correct verdicts and 0 actions over 2 d 20 h**, because the
verdict had no actuator. So EVAL is wired at the chokepoint rather than run on a schedule:
`bin/design-review` reads `.pipeline-pin`, and `.pipeline-pin` is written by exactly one code path —
`design-eval run --promote` — which refuses on any verdict other than `ACCEPT` and on a red
`self-test`. There is no second writer. The gate is not something someone remembers to run; it is the
only door.

### 9.6 Comparisons are key-version-scoped

Ratifying a wild finding retroactively converts a past false positive into a true positive (§6.2), so a
precision number computed under key v1.2 is not commensurable with one under v1.3. `--compare` refuses
across key versions. `--rescore-baseline` is the sanctioned escape: it replays the baseline's **stored
raw responses** through the new key and re-derives its scorecard, which is possible only because §8.2
kept them. Without stored responses this rule would be unenforceable and every longitudinal chart in
`scorecard.md` would be quietly comparing two different rulers.

---

## 10. UNVERIFIED — each with the one probe that settles it

| | Claim | Why it is not settled | The one probe |
|---|---|---|---|
| **P1** | A3b's `false_abstention_rate ≤ 0.05` | 5.2% comes from SCREEN's worked example census (95 indeterminate of 1,841 subjects), which is an illustration, not a measurement of our apps | Run SCREEN over 10 routes of `reso-management-app` and 10 of `reso-landing-app`; take the observed indeterminate fraction and its spread. If the marketing app runs far higher — plausible, since gradients and background images are its idiom — the bound is **per app profile**, not global. |
| **P2** | The model can be pinned to an immutable id | We do not know whether `claude-opus-5` resolves to a dated snapshot in this account | One `POST /v1/messages` with `model: "claude-opus-5"`; read `response.model`. A dated id ⇒ pin it in `verdict.json` and alarm on change. The alias echoed back ⇒ §8.5's automatic detection is impossible and the canary (§8.4) becomes the **only** model-drift sensor, which raises its seed count from 5 to 9. |
| **P3** | Corpus contamination is not yet happening | The pages are in this repo and in transcripts | Serve the judge the **control** page renamed with a defect item's blind letter, and ask the standard gestalt question. If it reports the defect that is not there, the answers have been memorised and §9.3's magnitude rotation is insufficient — the corpus needs a second, never-committed page family. |
| **P4** | The capture is bit-reproducible, so `pixel_delta.count > 0` needs no tolerance | CAPTURE asserts `stability.sha_a == sha_b` within one session; we have not tested across a Chromium minor bump or a font-cache rebuild | Re-capture the whole corpus after the next Chromium update and diff every `render_sha256`. Non-zero drift ⇒ the corpus's stored render hashes must be **re-baselined at every capture-stack change**, and the admissibility test becomes a same-session comparison only. |
| **P5** | A1b (`≤ 1` low-severity FP per control page) | The weakest-justified number here; chosen from reader tolerance, not measurement | Run the full pipeline over 10 known-good pages across the three apps and record the low-severity finding distribution. Replace 1 with the observed p90. |
| **P6** | Human recall on sub-perceptual classes is ~0 | Asserted from first principles (5/255 is below the JND; 1 px is below a 2 px+ practical threshold at typical viewing distance), never measured on these raters | It is measured as a side effect of the first `baseline-human` run — no extra work. If a designer *does* catch the 1 px on a Retina display, the sub-perceptual band is narrower than assumed and A2d/A2e need their boundary re-drawn at the measured value. |

---

## 11. Interfaces this stage depends on, stated as demands

EVAL is a consumer of every other stage, and three of its gates are unimplementable without a field
somebody else must emit. Naming them here so they are not discovered at integration:

| Demand | On | Without it |
|---|---|---|
| Every finding carries `layer ∈ {dom, xcheck, judgement}` and, where one exists, `backend_node_id` | ARBITRATE's report schema | §5.1's per-layer split collapses to an aggregate, which cannot see a layer silently dying |
| Every judgement response echoes the `tree_seed` it was served | PROMPT | A7 is unenforceable; permuted and never-permuted look identical |
| The capture manifest carries `clamp_safe`, `device_scale_factor_pinned`, `stability.equal` | CAPTURE | EVAL cannot refuse an unfaithful frame, and every geometric score inherits a phantom offset |
| ATTRIBUTE writes `targets[0].{file, line, property}` and a `verdict` | ATTRIBUTE | §5.5's actionability metric — the terminal one — cannot be computed at all |
| A per-finding disposition record (`accepted` / `reverted` / `ignored`) written when an agent acts | ATTRIBUTE + the acting agent | The pipeline can never learn whether it changed anything, which is A15's predicted failure mode with no instrument pointed at it |

---

## 12. The one-line summary of the stage

**EVAL grades the instrument, abstains when the corpus cannot support a verdict, and is the only door
through which a pipeline build becomes the default.** Its hardest gate is not recall — it is
`abstention_recall = 1.00`, because that is the only gate that catches a change which improves every
other number while quietly converting an honest *"I cannot compute this"* into a confident pass.

