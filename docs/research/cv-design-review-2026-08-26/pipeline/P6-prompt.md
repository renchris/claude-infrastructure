# P6 — PROMPT: how to ask Opus 5 for spatial judgement

**Stage owner:** the prompt-construction module of the CLI (`dr prompt build`), plus the three
verbatim templates in `prompts/`. **Consumer:** Claude Opus 5 via the Messages API, or a Claude Code
agent reading the same templates off disk. **Date:** 2026-08-26.

This stage does not capture, does not measure, does not adjudicate. It *composes a request* and
*constrains a reply*. Everything below is specification; the three templates in §4–§6 are the
deliverable and are meant to be copied verbatim into `prompts/{gestalt,crop,adjudicate}.md`.

---

## 0. CONTRACT

### 0.1 Inputs

| Input | Type | Source stage | Required |
|---|---|---|---|
| `shot` | PNG path, sRGB, device px | P-capture | yes |
| `factpack` | JSON, ~854 tokens, shape in §2.1 | P-deterministic (`DOMSnapshot.captureSnapshot`) | pass-2 and crop/adjudicate only |
| `findings_dom` | `[{rule,target,detail,severity}]` | P-deterministic (`detect_dom.py`) | pass-2 and adjudicate only |
| `indeterminates` | subset of `findings_dom` with `verdict:"INDETERMINATE"` | P-deterministic | adjudicate only |
| `xcheck` | `[{rule,target,left,right,detail}]` | P-xcheck (`detect_xcheck.py`) | adjudicate only |
| `context` | `{route, app, viewport, dpr, crop_rect, neighbours[]}` | P-capture + a11y tree | crop only |
| `tree_seed` | int | the CLI, per call | yes |
| `app_profile` | `landing` \| `management` \| `web` | repo config | yes |

### 0.2 Outputs

One JSON object per call, schema-validated by the CLI **before** the acting agent ever sees it.
Rejection is a hard error, not a warning — a malformed judgement is worse than no judgement.

```jsonc
{
  "call": "gestalt" | "crop" | "adjudicate",
  "tree_seed": 8823,                     // echoed; proves which branch order was served
  "branches_examined": ["hierarchy","rhythm","legibility","affordance","conformance","integrity"],
  "clean_assertion": "…",                // REQUIRED, non-empty, even when findings is non-empty
  "findings": [ /* §3.3 */ ],            // MAY be empty. Empty is a valid, expected answer.
  "noticed_but_not_reporting": [ /* free prose, ≤3 items */ ],
  "needs_measurement": [ /* §3.4 — routes BACK to P-deterministic */ ],
  "verdict": "…"                         // adjudicate only: "PASS"|"FAIL"|"STILL_INDETERMINATE"
}
```

### 0.3 Failure modes this stage owns, and what each does

| Failure | Detection | Action |
|---|---|---|
| Model emits an uncited number | schema: no free-numeric field exists in `findings` (§3.3) | reject the call, retry once with the violated field named; second failure → drop the finding, log |
| Model prescribes a fix containing a magnitude | `remedy_hypothesis` regex `\b\d+(\.\d+)?\s?(px|rem|%|:1|pt)\b` | strip `remedy_hypothesis`, keep `problem`, log |
| Model claims a sub-perceptual defect (≤2 px, ≤8/255 colour) | any finding whose `class` is `alignment`/`colour` and whose evidence cites no factpack path | route to `needs_measurement`, do **not** surface |
| Empty `clean_assertion` | schema | reject the call. Silence is not an answer here |
| >7 findings on a whole-page call | schema `maxItems: 7` | reject; the model must rank and cut, that is the work |
| Model refuses / hedges the whole page | `findings==[] && clean_assertion` matches `/cannot|unable|unclear/i` | escalate to a crop call on the largest three regions |
| Image rejected by the API | HTTP 400 `oversized_image` (we set `transformations.oversized_image:"error"`) | fail loud with the target size; never let a silent resize destroy evidence |

### 0.4 The one thing the contract guarantees

**Every number in the output is either copied from the fact-pack or absent.** Not "discouraged" —
structurally absent, because the schema has no slot for an uncited scalar. See §1.2.

---

## 1. Six frame decisions, each with its reason

### 1.1 The gestalt pass runs BLIND. The fact-pack enters at pass 2.

Our measured, irreplaceable result — three real defects nobody injected and no rule was looking for —
was produced by a **blind** run. Handing the model 13 WCAG failures, a spacing histogram and a token
list *before* it looks is priming: it converts an open perceptual question into a verification task
against someone else's checklist, and the emergent finding is exactly what a checklist cannot contain.

> ⚠️ **Stated tension with the substrate.** The substrate says: *"the COMPLETE deterministic fact-pack
> serialises to ~854 tokens — FEWER than one screenshot. There is no context-budget argument for
> withholding facts from the judge."* I agree and do not contradict it. My reason for withholding on
> pass 1 is **contamination, not budget**, and it applies to exactly one call out of three. Pass 2,
> the crop call and the adjudication call all receive the complete fact-pack. Nothing is withheld
> from the pipeline; one call is ordered before it.

Sequence per page: **gestalt (blind) → reconcile (fact-pack + the blind findings) → crops (fact-pack)**.
The reconcile step is a *second turn in the same conversation*, so the blind findings are already in
context and cost nothing to re-send.

### 1.2 The measurement ban is enforced by TYPE, not by instruction

An instruction — "do not estimate pixel distances" — is a prohibition the model can violate in prose
while sounding compliant ("the gap looks like roughly 12 px"). The local-VLM measurement is the
warning: at two of three resolutions it **invented a misalignment**, confidently, in fluent language.
Opus 5 is 0/2 on sub-perceptual precision; the danger is not that it misses, it is that a prompt which
*invites* precision converts a miss into a fabrication.

So `findings[].evidence` is a **tagged union with no numeric member**:

```jsonc
"evidence": [
  {"kind":"factpack", "path":"contrast.worst[0].wcag", "why":"…"},   // a number, but a CITED one
  {"kind":"visual",   "region":"the three cards under the KPI row", "why":"…"},  // prose, no number
  {"kind":"semantic", "element":"button[name='Export']", "why":"…"}
]
```

There is no `{"kind":"measured","px":12}`. If the model wants one, its only legal move is
`needs_measurement`, which routes the question back to the deterministic stage. This is the
enforce-at-the-chokepoint pattern: the gate lives on the artifact, not in the exhortation.

### 1.3 Rubric TREE for coverage; never a rubric SCORE

Two measurements point opposite ways and both are real. WebDevJudge: **rubric trees** raised
inter-annotator agreement from 65% to **89.7%**. Rubric *scoring*: **16–39% top-1 ranking reversals
from reordering alone**, with some judges first-biased and some last-biased, so a fixed order cannot
be corrected for. They measure different objects — a tree is a **partition of coverage**, a score is a
**ranked comparison** that inherits multiple-choice position bias. So:

- **Keep** the six-branch tree (§3.1) as a coverage obligation, and require `branches_examined` in the
  output so a skipped branch is visible.
- **Ban** any score, grade, rank, 1–5 rating, or "overall quality" field. `mllm-ui-judge` rated ten
  screenshots 1–5 and got 3.5–4.0 on all of them — range compression, invisible if you only compare
  means (judge 3.65 vs human 3.82).
- **Randomise the branch order per call** from `tree_seed`, and echo the seed. Permuting over 3–5
  orderings recovers ≈⅔ of the K=10 benefit; exact balancing buys essentially nothing.
- **Swap-recheck only `severity:"blocker"` findings** — one extra call with the reversed branch order,
  and only a finding that survives both is allowed to carry `blocker`. Reason for gating on severity:
  the reversal harm is real but 2× cost on every call is not, and blockers are the only findings that
  will actually consume a human's attention.

### 1.4 "Nothing wrong here" is an assertion, not a silence

Zero false positives — including on the clean control — is worth more than any catch-rate improvement,
because ~20% FP is where an AI reviewer loses credibility regardless of recall. The prompt must make a
clean verdict *feel like completed work*, or the model will manufacture a finding to justify the call.
Four mechanisms, all in the templates: **`clean_assertion` required and non-empty**, so an empty
`findings` array is a result rather than an omission; **a stated prior** in the system block that most
screens are correct and our control correctly produced nothing; **`noticed_but_not_reporting`**, which
gives a hunch somewhere to go that is not a claim (written to disk for the eval stage, never surfaced
to the acting agent); and **a confidence floor of 0.6** for surfacing (§7).

### 1.5 Problems, not prescriptions — with one carve-out for our consumer

OneRedOak states it verbatim: *"Instead of 'Change margin to 16px', say 'The spacing feels inconsistent
with adjacent elements.'"* A wrong prescription is a false positive; a wrong problem description is
still a conversation. But our consumer is an agent that **edits source**, so pure critique loses the
loop. Carve-out: `problem` is required prose with no magnitude; `remedy_hypothesis` is optional,
labelled a hypothesis in the key itself, and **stripped by the CLI if it contains a magnitude** (§0.3).
The agent may act on a direction ("these should share the container's left edge"); never on a number
the model invented.

### 1.6 Context travels as TEXT; a second image is never context

The measured overlay result generalises: an overlay is a full second image (~3,240 tokens) against
~840 for the same findings as JSON. A "context thumbnail" beside a crop is the same trade with worse
content — a downscaled thumbnail is exactly the fidelity we spent the crop to escape. So a crop call
carries **one** image and a `PAGE CONTEXT` text block (§5.2).

---

## 2. Presenting the fact-pack so the model reasons FROM it

### 2.1 Format: a labelled, path-addressable block — not prose, not a table

The fact-pack is injected verbatim as JSON inside a fenced block with a `FACT PACK` header, because
every finding's `evidence[].path` must be a **literal JSONPath into that block**. Prose ("contrast is
about 4.4:1 in places") has no addressable path and cannot be cited; a Markdown table forces the model
to re-transcribe values, which is exactly where transcription drift enters.

```
<FACT PACK route="/dashboard" captured="2026-08-26T07:20:20.223Z" viewport="1440x900" dpr="2">
{ "meta": {...}, "spacing": {...}, "type": {...}, "palette": {...}, "shape": {...},
  "alignment": {...}, "contrast": {...}, "targets": {...}, "clipping": [...],
  "zorder": {...}, "focus": {...} }
</FACT PACK>
```

Field shape is A7's, unchanged — `spacing.histogram`, `type.sizes`, `contrast.worst[]`,
`targets.smallest[]`, `alignment.leftEdges`, `clipping[]`, `focus.noVisibleRing`. Three presentation
rules on top:

1. **Every backdrop that is a gradient or an image is emitted as `"backdrop":"VARIES"`**, never as a
   scalar colour. This is the load-bearing one. `blendedBackgroundColors` samples one colour per text
   run and on our gradient page returned the left stop: 10.36:1 reported where the text actually sits
   at 1.22:1. Emitting the scalar would hand the model a **confident false PASS**, and the model has
   no way to know the number is a fiction. An abstention routes to adjudication; a pass routes nowhere.
2. **Counts are emitted with their denominators.** `"wcagFailures": 13` alone invites "13 is a lot";
   `"measured": 99, "wcagFailures": 13` lets the model reason about a rate. Every count field in the
   pack ships beside the population it was drawn from.
3. **`"INDETERMINATE"` is a first-class value, spelled out**, never `null` and never omitted. A missing
   key reads as "not applicable"; the explicit token reads as "we tried and could not".

### 2.2 The four sentences that make the model use the numbers

These go in the user turn immediately above the fact block, verbatim:

> The block below is measured, not estimated. It came from the browser's own layout and compositor —
> `DOMSnapshot.captureSnapshot` — for the exact frame in the image, in the same browser pass, so a
> pixel and a number here describe the same render. Where it says `INDETERMINATE` or `VARIES`, the
> measurement genuinely could not be taken; treat that as an open question, not as a pass. Any number
> you use in a finding must be copied from this block with its path.

Every clause is load-bearing, and the third most of all: *INDETERMINATE is an open question, not a
pass* is the only thing standing between an honest abstention and a confident false close.

### 2.3 What is deliberately NOT in the fact-pack

- **No `findings_dom` on the gestalt pass** (§1.1).
- **No source paths / component names.** Pixel-to-source attribution is unowned (A15 M2) and a
  half-guessed `file:line` in a finding is worse than none — the agent will open the wrong file.
- **No saliency map.** It is a second image and its licence is unresolved. When it lands it enters as
  *one image plus one statistic* ("the element you named primary captures 4% of predicted attention
  mass; the largest mass, 31%, is on the hero image"), never as a score.
- **No previous-run findings.** Anchoring on the last review's output is intrinsic self-refinement,
  which the literature abandoned (Huang et al. ICLR 2024; Kamoi et al. TACL 2024) — it degrades rather
  than improves without an external signal.

---

## 3. Shared blocks used by all three templates

### 3.1 The six-branch coverage tree

Emitted in an order permuted from `tree_seed`. Branch names are stable; only order moves.

| Branch | The question | Why it is a branch |
|---|---|---|
| `hierarchy` | Does the visual weight match the actual importance of the actions? | our blind run's inverted-action-hierarchy catch |
| `rhythm` | Do repeated elements repeat, and do groups group? | orphan-legend class |
| `legibility` | Can every piece of text actually be read where it sits? | washed-out-over-gradient catch |
| `affordance` | Can you tell what is clickable, and what each control does? | unlabelled-icon-button catch |
| `conformance` | Does this look like it came from the same system as the rest of the app? | `management` profile's dominant class |
| `integrity` | Does the page tell the truth — do labels, captions and counts match what is shown? | table caption promising grey rows that do not exist |

`integrity` is the branch that produced the finding no rule could reach, and it is the one no
deterministic layer can grow into. It is never dropped, whatever the app profile.

### 3.2 The system block (identical in all three calls)

```text
You are reviewing a screen from a production web application, the way a senior product designer
reviews a build before it ships — looking at it, not auditing it against a list.

Three things about how you see, established by measurement on this exact setup:

1. You are very good at whether a screen MAKES SENSE. On our ground-truth corpus you found every
   judgement-level defect we had planted, and you found three real defects nobody planted and no
   rule was looking for — a caption promising rows that did not exist, an unlabelled icon button
   with the smallest hit target on the page, and numeric columns left-aligned so the digits did not
   line up. That is the capability nothing else here has. It is why you are being asked.

2. You cannot see below about 3 pixels or about 8 levels of 255 in colour. On the same corpus you
   scored 0 of 2 on a 1px misalignment and a 5/255 colour drift. This is not a flaw to work around;
   it is a boundary to respect. Everything below that threshold is measured for you by the browser
   and handed to you as numbers. A model that guesses in this band does not miss quietly — it
   invents a defect that is not there, confidently. We measured that too, on a different model.

3. You have never produced a false positive on this corpus, including on the clean control, where
   the correct answer was nothing. That record is worth more to us than any additional catch.
   Most screens we send you are correct. "I looked and this is sound" is a complete, expected,
   valued answer, and it is the right answer more often than not.

You never state a measurement you were not given. Not a pixel gap, not a contrast ratio, not a
font size, not a percentage. If a claim needs a number you do not have, you say what needs measuring
and we measure it. This is a hard rule and it is enforced by the output schema, not by your
judgement: there is no field to put an uncited number in.

You describe problems, not prescriptions. "These three cards do not share a left edge with the
heading above them" is a finding. "Set margin-left to 16px" is a guess wearing a finding's clothes.
```

### 3.3 The finding object

```jsonc
{
  "branch": "hierarchy",
  "class": "hierarchy|rhythm|legibility|affordance|conformance|integrity",
  "problem": "…",                 // required prose, NO magnitudes
  "where": "…",                   // plain-language locator; a11y name/role preferred over coordinates
  "why_it_matters": "…",          // required — the sentence a designer would say to a PM
  "evidence": [ /* §1.2 tagged union */ ],
  "confidence": 0.0,              // 0–1; <0.6 is not surfaced (§7)
  "severity": "blocker|worth-fixing|nitpick",
  "remedy_hypothesis": "…"        // optional, stripped if it contains a magnitude
}
```

`severity` is a 3-level ordinal with anchored definitions given in the template, not a score:
**blocker** = a user cannot complete a task, or cannot read required text; **worth-fixing** = the
screen works but reads as unfinished; **nitpick** = you would mention it and not block on it.
Three levels, not four, because the fourth level in OneRedOak's scheme
(`[High-Priority]`/`[Medium-Priority]`) is a distinction no reader of our output acts on differently.

### 3.4 The `needs_measurement` object — the escape hatch that makes the ban survivable

```jsonc
{ "question": "the exact quantity you want",
  "region": "plain-language locator",
  "what_would_change": "which of your findings this decides, and how" }
```

The third field is mandatory and is the whole point: a measurement request that does not change a
verdict is curiosity, and the CLI drops it. This is the queue that P-deterministic and P-xcheck read.

---

## 4. TEMPLATE A — whole-page gestalt (pass 1, BLIND)

**Image:** one viewport-height capture at 1440×900 CSS px @ DPR 2 → 2880×1800 device px, which the
capture stage downscales to **2419×1512** before sending — the largest 16:10 frame inside the
4,784-visual-token tier (§7.1), an effective 1.68× CSS detail. **Not** a full-page stitch: a
2500 px-tall shot delivers 0.80× effective detail, worse than a plain 1× viewport shot at any DPR.
Below-the-fold content is a separate call with its own scroll offset, never a taller image.

**No fact-pack. No DOM findings. No overlay.** Model: `claude-opus-5`, `effort: high`,
`temperature: 1.0` (the default; we are eliciting judgement, not extraction — and our zero-FP result
was measured at the default, so lowering it is an unvalidated change to the one property we are
protecting).

System block: §3.2 verbatim. User turn:

````text
Here is <ROUTE> from <APP_NAME>, at <VIEWPORT> CSS pixels, <FOLD_NOTE>.

<APP_PROFILE_LINE>

Look at it first. Before you check anything, tell me what you notice — the way you would if this
were on a screen in front of you and someone asked "what do you think?". Spend that first look on
what the page is trying to do and whether it does it.

Then walk these, in this order:

  1. <BRANCH_1_NAME> — <BRANCH_1_QUESTION>
  2. <BRANCH_2_NAME> — <BRANCH_2_QUESTION>
  3. <BRANCH_3_NAME> — <BRANCH_3_QUESTION>
  4. <BRANCH_4_NAME> — <BRANCH_4_QUESTION>
  5. <BRANCH_5_NAME> — <BRANCH_5_QUESTION>
  6. <BRANCH_6_NAME> — <BRANCH_6_QUESTION>

That list is a floor, not a ceiling. The most valuable thing you have ever given us came from
outside it: three real defects nobody asked about, in a run where we gave you no list at all. So
if something is wrong with this page and none of those six names it, that finding is worth more
than all six, and it goes in the output with `branch: "other"`. Do not compress it to fit a
category, and do not drop it because it has no category.

Two things you are NOT doing here:

  - You are not measuring. If something looks like it might be off by a hair — an edge that might
    not line up, a grey that might be a shade different from its neighbour — do not call it. Put
    it in `needs_measurement` and say what would change if the number came back either way. The
    browser measured this page to the pixel and will answer you. A guess in that band is not a
    near-miss, it is a fabrication, and an agent will act on it.
  - You are not grading. No score, no rating, no "overall this is a 7". We do not want one and
    we will discard it.

Report at most 7 findings. If you have more than 7, that itself is a finding about the page — rank
them, report the top 7, and put the rest in `noticed_but_not_reporting`. Ranking is part of the
work: an unranked list of everything is what a linter produces, and we already have one.

If the page is sound, say so and say what you checked. That is a complete answer and it is the
answer we get most often. Do not go looking for something to report.

Return only this JSON:

```json
{
  "call": "gestalt",
  "tree_seed": <SEED>,
  "first_look": "2-4 sentences, plain language, what you noticed before checking anything",
  "branches_examined": ["...", "..."],
  "clean_assertion": "what you checked and found sound — required, even if you also found problems",
  "findings": [ /* at most 7, schema below */ ],
  "noticed_but_not_reporting": [ "...", "..." ],
  "needs_measurement": [ { "question": "...", "region": "...", "what_would_change": "..." } ]
}
```

Each finding:

```json
{
  "branch": "one of the six above, or \"other\"",
  "class": "hierarchy|rhythm|legibility|affordance|conformance|integrity",
  "problem": "what is wrong, in a sentence, with no numbers in it",
  "where": "where on the page, by what it is — \"the Export button in the table header\", not coordinates",
  "why_it_matters": "the sentence you would say to a PM who asked why this needs fixing",
  "evidence": [ { "kind": "visual|semantic", "region": "...", "why": "..." } ],
  "confidence": 0.0,
  "severity": "blocker|worth-fixing|nitpick",
  "remedy_hypothesis": "optional, a direction not a magnitude, or omit it"
}
```

severity means exactly:
  blocker      — a user cannot finish a task here, or cannot read text they need
  worth-fixing — it works, but the screen reads as unfinished
  nitpick      — you would mention it in passing and would not hold a release for it
````

**`<APP_PROFILE_LINE>` is one sentence, chosen by profile** (three apps, three different problems):

- `landing` — *"This is a marketing page built from a purchased template. Judge it as a visitor who has never heard of us: does it earn the next scroll? Design-system conformance is not the question here."*
- `management` — *"This is an internal product surface on our own design system. Consistency with the rest of the app is a first-class concern: an element that is fine in isolation but unlike its siblings is a real finding."*
- `web` — *"This is a public product surface. Both readings apply: it must persuade a stranger and it must look like it belongs to the same product as the app behind it."*

### 4.1 Pass 2 — reconciliation (second turn, same conversation)

````text
Here is what the browser measured on the same frame you just looked at.

<FACT PACK …>   ← §2.1 block, plus the §2.2 four sentences immediately above it

<DOM FINDINGS>  ← findings_dom, as JSON

Three jobs, in this order:

1. Any finding of yours that this data CONTRADICTS — withdraw it, and say which path contradicts
   it. Withdrawing is a good outcome, not an embarrassment; it is the reason we run this pass.

2. Any finding of yours that this data CONFIRMS — attach the citation. Move the number out of your
   description and into `evidence[].path`.

3. Anything in the DOM findings that you looked straight at and did not see — say so, in one line
   each. We want to know where your eye and the numbers disagree, because that gap is where the
   defects we cannot catch any other way live. Do not adopt a DOM finding you cannot see; a rule
   firing is not the same as a problem existing, and you telling us "that one is invisible to a
   user" is itself the finding.

Do NOT go looking for new findings in this data. You are reconciling, not re-reviewing. If the
numbers make you notice something genuinely new about the page, it goes in `noticed_but_not_reporting`
with a one-line note, and we will send you a crop.

Return the same JSON shape, with `"call": "gestalt-reconciled"` and two extra keys:
`"withdrawn": [ {"problem": "...", "contradicted_by": "factpack path"} ]` and
`"dom_findings_i_cannot_see": [ {"rule": "...", "target": "...", "note": "..."} ]`.
````

Rule 3 is the highest-value clause in the whole stage and is not obvious: the model's *disagreement*
with the linter is a signal neither layer produces alone. A DOM rule that fires on something no
reader would ever perceive is a false positive in the linter, and the only instrument we have that can
say so is an eye. This is the same shape as the DOM-vs-pixels cross-check, run at the semantic level.

---

## 5. TEMPLATE B — single-crop interrogation

Crop refinement is the largest measured lever available anywhere in this pipeline: ScreenSeekeR took a
model from **18.9% → 48.1%** on ScreenSpot-Pro with no model change — a bigger delta than every model
upgrade in the substrate combined. The prompt's job is to buy that detail *without* buying the
disorientation that comes with losing the page.

### 5.1 The crop budget

**≤966×966 CSS px at DPR 2** (= 1932×1932 device, 69×69 = 4,761 of 4,784 visual tokens; 70×70 = 4,900
exceeds it). Derivation and the full frame table are in §7.1. Note that this lands 68 device px
*inside* the Read tool's 2000×2000 clamp — the binding constraint is the token tier, not the clamp,
and anything larger is recompressed rather than sharper. A crop is expanded to the nearest whole
element boundary from the DOM box, then padded to a minimum of 120 CSS px per side so a lone control
is never presented floating in white.

### 5.2 The PAGE CONTEXT block (text, never a second image)

Assembled by the CLI from the a11y tree and `getBoundingClientRect`, injected above the image:

```text
<PAGE CONTEXT>
route:            /dashboard
crop:             x=744 y=212 w=624 h=388 CSS px, of a 1440x2960 page
position:         upper-right quadrant; entirely above the fold (fold at y=900)
this region is:   the "Revenue by region" card, role=region, inside <main>
directly above:   the KPI strip — 4 sibling cards, roles=region, names "MRR" "Churn" "ARPU" "NRR"
directly below:   the "Recent activity" table, role=table, 8 rows
to its left:      the "Revenue by month" card — its SIBLING, same component, same size
to its right:     page gutter, empty
page repeats:     this card shape appears 6 times on the page; you are seeing 1 of the 6
</PAGE CONTEXT>
```

The `page repeats` and `to its left … its SIBLING` lines are the load-bearing ones. Most conformance
findings are comparative — *unlike its siblings* — and a crop destroys exactly the comparison that
makes them visible. Naming the sibling in text restores the comparison at ~40 tokens instead of ~3,240
for a second image.

### 5.3 The template

System block: §3.2 verbatim. User turn:

````text
<PAGE CONTEXT>
…
</PAGE CONTEXT>

<REASON FOR THIS CROP>
<one of:
  "The deterministic layer could not resolve <X> here and needs an eye."
  "You said in your page review: '<quoted finding>'. I am showing you the region at full detail."
  "A rule fired here that you did not see when you looked at the whole page."
  "Nothing fired here. This is a control crop.">
</REASON FOR THIS CROP>

<FACT PACK scope="crop" …>
{ …the fact-pack, filtered to nodes intersecting the crop rect, plus page-level distributions
  (spacing.histogram, type.sizes, palette) UNFILTERED so "unlike the rest of the page" stays askable… }
</FACT PACK>

The image is this region at full capture resolution — no downscaling, so what you are seeing is
what a user with this display sees, at the size they see it.

Answer the question in the REASON block first, in one sentence, before anything else.

Then: is anything else wrong in this region? Same six branches, same rules. You are looking at a
piece of a page, so two failure modes are yours to avoid, and they pull in opposite directions:

  - Do not report a problem that only exists because I cropped it. A heading with no body text
    under it, a card with a cut-off edge, an element that looks unbalanced in isolation — check
    the PAGE CONTEXT block before you call any of those. If the context does not settle it, say
    so rather than calling it; "I would need to see this in the whole page" is a real answer.
  - Do not lose the page either. This region belongs to a screen. "Fine on its own, wrong here"
    is exactly the kind of finding this crop exists to surface — the context block tells you what
    its siblings are and how many times this shape repeats.

You now have detail you did not have at page scale. Use it on things that NEED detail: whether text
sits legibly on what is behind it, whether an icon reads as its meaning at its actual rendered size,
whether a control looks pressable. Do not use it to eyeball distances — that is still measured for
you, and the numbers for this region are in the fact-pack above.

Return only this JSON:

```json
{
  "call": "crop",
  "tree_seed": <SEED>,
  "answer_to_reason": "one sentence, first",
  "branches_examined": ["...", "..."],
  "clean_assertion": "what you checked in this region and found sound — required",
  "findings": [ /* at most 4; same schema as the page call */ ],
  "context_limited": [ "anything you could not decide without seeing more of the page" ],
  "noticed_but_not_reporting": [ "..." ],
  "needs_measurement": [ { "question": "...", "region": "...", "what_would_change": "..." } ]
}
```
````

**Findings cap is 4, not 7**: a region yielding more than four distinct problems at full detail is a
page-level structural finding, and belongs in the gestalt call where the model can see what it is
structural *relative to*.

**`context_limited` is not a failure field** — it is the crop call's abstention, and the CLI treats it
as a routing instruction: re-ask at page scale rather than press for a verdict the model has told you
it cannot reach.

**Control crops are real, and the reason line is honest about it.** 1 in 10 crop calls (§7.2) is a
region where nothing fired. The point is not to trick the model; it is to measure whether a crop call
*without* a defect to find produces one anyway. If it does, the pipeline's false-positive generator is
the crop framing, not the model.

---

## 6. TEMPLATE C — adjudicating one INDETERMINATE

This is the highest-risk call in the pipeline, structurally: every other call asks an open question,
this one asks the model to **close** one, and the framing itself pushes toward a verdict. The
deterministic layer's abstention is the most valuable output it produces, and a sloppy adjudication
prompt spends that value in one turn by converting an honest `INDETERMINATE` into a confident `PASS`.

**Scope note:** contrast-over-a-gradient is *no longer* in this queue — the DOM-vs-pixels cross-check
settles it deterministically (4.81:1 left third vs 1.57:1 right) with no model call. What reaches this
template is the residue: backdrop images, layered compositing the cross-check's tolerance cannot
separate, text over video or canvas, and any case where `xcheck` itself abstains.

**One INDETERMINATE per call.** Never a batch. A batch invites the model to be consistent across items
rather than correct on each, and the position-bias literature is unambiguous that a list of judgements
is a different, worse instrument than a judgement.

System block: §3.2 verbatim, plus this paragraph appended:

```text
This call is different from a page review. You are settling one open question that the browser could
not settle. Three answers are available and the third is real: PASS, FAIL, and STILL_INDETERMINATE.
The costs are not symmetric and you should decide as if they are not. A wrong FAIL costs a person
thirty seconds to look and disagree. A wrong PASS closes the question forever — nothing downstream
re-opens it, the defect ships, and the abstention that would have caught it has been spent. If you
are not sure, STILL_INDETERMINATE is the correct answer, it is not a failure to answer, and it
routes the question to a person rather than into the ground.
```

User turn:

````text
The deterministic layer stopped here and said it could not decide. This is the question it could
not answer:

<INDETERMINATE>
rule:     contrast-indeterminate
target:   h2.hero-title  ("Everything your team ships, in one place")
detail:   cannot compute a ratio — the backdrop resolves to a background-image, so the
          requirement 4.5:1 is UNVERIFIED for this text
</INDETERMINATE>

Why it could not decide: <one line, generated from the rule's own abstention reason>

What the browser DOES know about this element:

<FACT PACK scope="element+ancestors" …>
{ …the element, its ancestor chain with every resolved background layer, its computed type
  (size / weight / family / line-height), its box, and the page-level palette… }
</FACT PACK>

<CROSS-CHECK>          ← present only when detect_xcheck.py produced a row for this target
[xcheck-contrast-varies] contrast is not one number across this text: 4.81:1 at the left edge and
1.57:1 at the right. Any single computed value is a fiction, and the right end is the one that
fails a reader.
</CROSS-CHECK>

The image is that element and its immediate surroundings, at capture resolution.

Answer this question and only this question. Do not review the region. Do not report anything else
you notice here — if something else is wrong, put one line in `noticed_but_not_reporting` and we
will send a separate crop.

To answer it, ask yourself the thing the browser cannot: reading this at the size it is rendered,
in the place it sits, can a person read it comfortably? Not "is there a ratio somewhere that
passes" — whether the text is legible where it actually is, over what is actually behind it. If the
backdrop varies across the text, the part that matters is the worst part, because a reader reads
the whole word.

If a cross-check block is present above, it is measured and you should treat its numbers as settled.
Your job then is not to re-derive them — it is to say whether the failure it measured is one a reader
would actually experience, or an artifact of where the tool sampled.

If you cannot tell — if the answer depends on a rendering detail below what you can see, or on the
image behind the text loading differently, or on a state you are not being shown — say
STILL_INDETERMINATE and name exactly what a person should look at. That answer sends this to a
human, which is where it belongs if you are not sure.

Return only this JSON:

```json
{
  "call": "adjudicate",
  "target": "<echo the target verbatim>",
  "verdict": "PASS" | "FAIL" | "STILL_INDETERMINATE",
  "reasoning": "2-4 sentences. What you looked at and what decided it.",
  "evidence": [ { "kind": "visual|factpack|xcheck", "path_or_region": "...", "why": "..." } ],
  "confidence": 0.0,
  "if_still_indeterminate": {
    "what_a_person_should_look_at": "...",
    "what_would_settle_it": "the measurement or the state that would close this"
  },
  "noticed_but_not_reporting": [ "..." ]
}
```

`verdict: "PASS"` means: I looked at this and a reader is fine. It is a claim, and it closes the
question. Only say it if you would say it to the person who has to ship this.
````

### 6.1 What the CLI does with each verdict

| Verdict | Routing | Why |
|---|---|---|
| `FAIL` | becomes a finding at the severity the rule declares, evidence carries the adjudication | the deterministic rule already knows how bad its own class is |
| `PASS` with `confidence ≥ 0.75` | the `INDETERMINATE` is closed and recorded with the adjudication attached | auditable: the close is a claim with a name on it, never a silent drop |
| `PASS` with `confidence < 0.75` | treated as `STILL_INDETERMINATE` | a hedged close is the exact failure this template exists to prevent |
| `STILL_INDETERMINATE` | surfaces to the operator as a named open question with `what_a_person_should_look_at` | this is the designed path, not the error path |

The 0.75 floor is higher than the 0.6 surfacing floor for findings (§7) and the asymmetry is
deliberate: a finding at 0.6 costs a human a glance, a close at 0.6 costs a shipped defect.

---

## 7. Every threshold, with the arithmetic or the argument behind it

### 7.1 Image sizing — derived from the token formula, not chosen

`tokens = ⌈w/28⌉ × ⌈h/28⌉`; high-resolution tier caps at 2,576 px long edge **and** 4,784 visual
tokens. Both bind, and for wide frames the **token count binds first** — a fact our sizing guidance
did not previously state:

| Frame | CSS × DPR | Device px | Patches | Fits 4,784? | Delivered as |
|---|---|---|---|---|---|
| Desktop review | 1440×900 @2 | 2880×1800 | 104×65 = 6,760 | **no** | **2419×1512** (87×54 = 4,698), effective **1.68× CSS** |
| Desktop at 2576 long edge | — | 2576×1610 | 92×58 = 5,336 | **no** | the long-edge cap alone is not sufficient |
| Tablet | 768×1024 @2 | 1536×2048 | 55×74 = 4,070 | yes | native DPR 2 |
| Mobile | 375×812 @2 | 750×1624 | 27×58 = 1,566 | yes | native DPR 2 |
| Square crop | ≤966×966 @2 | ≤1932×1932 | 69×69 = 4,761 | yes | native DPR 2, no downscale |

So the standard 1440 desktop review width **cannot** be delivered at full DPR 2 inside the tier, and
the honest maximum is 1.68×. That is the arithmetic reason crop refinement is not an optimisation here
but the only route to true 2× detail — and it independently re-derives the ScreenSeekeR result from
our own token physics. Anything the 1.68× page pass cannot resolve goes to a crop; nothing is served
by raising DPR.

`--force-device-scale-factor` is pinned at capture (headless and headed Retina disagree on line-box
rounding by ~1.5 px over four paragraphs). Unpinned, every geometric statement in a fact-pack inherits
a phantom offset, and the prompt would then be citing a fiction with a path attached.

### 7.2 Everything else

| Threshold | Value | Reason |
|---|---|---|
| Images per request | 1 normally, hard cap **8** | >20 image blocks tightens the per-image cap and **rejects** oversized images rather than downscaling. 8 keeps a 2.5× margin from a hard-fail cliff |
| Findings, page call | **7** | a reviewer flagging 40 to catch 8 is net negative; Percy retired red-pixel overlays because reviewers scanned everything. A cap forces ranking, which is the human behaviour we want |
| Findings, crop call | **4** | more than four distinct problems in one region is a page-level structural finding, not a crop finding |
| Surfacing floor | `confidence ≥ 0.6` | **UNVERIFIED — policy, not measurement.** See U3 |
| Close floor (adjudicate PASS) | `confidence ≥ 0.75` | a wrong finding costs a glance; a wrong close ships a defect and spends the abstention |
| Control / decoy rate | **10%** of calls | over a 40-screen run that is 4 control calls, so a single FP reads 25% — above the 20% credibility line, i.e. the sample is powered to detect a budget breach *within one run*. At 5% a single FP reads 50% and the estimate is too noisy to act on; above 10% you are paying for measurement instead of review |
| Branch-order permutation | every call, seeded, echoed | 3–5 orderings recover ≈⅔ of the K=10 benefit; exact balancing buys essentially nothing |
| Swap-recheck | `severity:"blocker"` only | 16–39% reversal is real harm, but 2× cost on every call is not; blockers are the only findings that consume attention |
| Temperature | **1.0** (default) | our zero-FP result was measured at the default. Lowering it is an unvalidated change to the property we are protecting. See U7 |
| Schema-violation retries | **2**, then drop the finding | a third attempt is the model arguing with the schema |
| `transformations.oversized_image` | `"error"` | a silent resize destroys the evidence and produces a confident finding about a frame nobody saw |

---

## 8. What this stage CANNOT do — and who must own it

| Cannot | Owner |
|---|---|
| Verify or produce any number | **P-deterministic** (`DOMSnapshot.captureSnapshot`, 32.7 ms whole-tree) and **P-xcheck** (~180 lines NumPy) |
| See below ~3 px or ~8/255 | **P-deterministic.** The prompt does not merely decline this — it forbids attempting it, because the measured failure mode of a model pushed into this band is a confident invented defect, not a miss |
| Map a finding to `file:line` | **UNOWNED — the biggest hole in the pipeline** (A15 M2). The consumer is an agent that edits source; until an attribution stage exists, every finding lands as a report a human must interpret. The prompt refuses to guess a path, which makes the hole visible rather than plausible |
| See motion | **P-motion** — `getComputedTiming()` returns duration/easing/delay with `auto` resolved. Trap: CDP `Animation.setPlaybackRate(0)` controls WAAPI but not rAF, and Playwright's `page.clock` patches rAF but not the document timeline; a harness using one reports "0 animations found" on a GSAP page as a false green |
| Rank or score two designs | **Nobody — out of scope by ratified decision** (June 2026: *taste stays human, gates adjudicate correctness/coverage only*). Order-invariant consistent accuracy is ~30–37% against a 25% chance baseline. There is no prompt that fixes this |
| Act as a CI gate | **Nobody.** The CLI must exit 0 on findings. A nonzero exit re-adopts VLM scoring as a blocking gate and contradicts the ratified decision |
| Know whether it was right | **P-eval** — the 13-page corpus, re-run against the clean control before any prompt change ships |
| Choose which crops to request | **P-router** — the abstention router; this stage consumes its queue and does not build it |
| Predict pre-semantic attention | **A saliency specialist** (UMSI++ CC 0.833 vs frontier VLM 0.408). Licence unresolved; enters as one image plus one statistic, never a score |

---

## 9. UNVERIFIED, each with the one probe that settles it

| | Claim | Probe |
|---|---|---|
| **U1** | Blind-first ordering (§1.1) preserves the emergent-finding capability that fact-pack-first would suppress | Run the 13-page corpus twice — arm A blind-then-reconcile, arm B fact-pack-first — and count findings tagged `branch:"other"` in each. The blind baseline produced 3 across 8 pages; a collapse toward 0 in arm B is visible at this n even though the n is small |
| **U2** | A textual `PAGE CONTEXT` block is as good as a context thumbnail, at ~40 tokens against ~3,240 | 20 crop calls on regions carrying a known sibling-mismatch defect: arm A text only, arm B text + a 512 px thumbnail. Compare recall and cost. If arm B wins on recall, the token argument loses and the thumbnail ships |
| **U3** | `confidence ≥ 0.6` is the right surfacing floor | Log every finding with its confidence over one full three-app run, have the operator adjudicate, plot precision against threshold, take the knee. Until then the value is a policy choice wearing a measurement's clothes |
| **U4** | A schema with no numeric field actually stops fabrication rather than displacing it into `problem` prose | Regex every `problem` string in one full run for `\b\d+(\.\d+)?\s?(px\|rem\|%\|:1)\b`. A nonzero count means the ban leaked and `problem` needs the same strip that `remedy_hypothesis` gets |
| **U5** | The 7-finding cap does not suppress real defects | Run the corpus capped and uncapped; count corpus-known defects appearing only at positions 8+ in the uncapped arm. Zero ⇒ the cap is free |
| **U6** | Swap-rechecking blockers changes anything | 30 blocker findings re-run with reversed branch order; count verdict changes. Under 5% ⇒ delete the second call and its cost |
| **U7** | Temperature 1.0 is right for a zero-FP objective | Clean control × 10 runs at temperature 1.0 and × 10 at 0.3; count findings in each. Any finding on the control at either setting is the answer |

---

## 10. Acceptance for this stage

The prompt stage is done when, on the 13-page corpus:

1. **Zero findings on the clean control** across 10 runs of Template A — the property being defended.
2. **Both judgement/semantic defects still found** blind (inverted hierarchy, washed-out text) — no
   regression against the baseline the templates were written to preserve.
3. **Zero uncited numbers** in any output field across the full run (U4's regex, count 0).
4. **The gradient page's `INDETERMINATE`** reaches Template C only when `xcheck` abstained, and
   Template C returns `FAIL` or `STILL_INDETERMINATE` — never `PASS`.
5. **At least one `branch:"other"` finding** somewhere in the run. If the templates produce none, they
   have optimised the checklist and killed the capability that justified the stage.
