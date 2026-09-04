# Computer vision for 100th-percentile web design review

**Date:** 2026-08-26 · **Machine:** Apple M1 Max, 64 GB unified, 32-core GPU
**Question:** what tooling gives our Claude Code sessions genuine visual understanding — spatial
recognition, not image-to-text OCR — so we can run 100th-percentile design review of
`reso-management-app`, `reso-web-app` and `reso-landing-app`? Local models for this Mac, and
cloud/API, on the pattern of Parakeet/Whisper-v3-Turbo locally and the Mistral OCR API in the cloud.

**Method:** 15 parallel research agents (reports in `agents/`) plus a purpose-built ground-truth
defect corpus measured three ways on this machine (`../../../bench/`). Where the agents and the
bench disagree, the bench wins; where agents disagree with each other, both are named.

---

## The answer

**Buy pixels and an eval, not models.** Perception is not our binding constraint, and the analogy to
Parakeet and Mistral OCR does not transfer. Speech recognition and OCR are narrow tasks with crisp
ground truth, high volume, and open models that genuinely match or beat hosted ones. Design critique
has none of those properties. What we are short of is not a better eye — it is (a) the discipline of
never asking a model to compute what the browser already knows, (b) any acceptance test at all, and
(c) a settled decision about what the review is *for*, which we made in June 2026 and then lost.

Three measurements, all taken on this machine today, carry the argument:

| Detector | DOM-determined | Pixels-only | False positives on the clean control |
|---|---|---|---|
| **Deterministic rules** (~250 lines, 80 ms/page) | **9 / 9** | 0 / 2 (1 honest abstention) | **0** |
| **DOM-vs-pixels cross-check** (~180 lines NumPy, no model) | — | **1 / 2** | **0** |
| **Claude vision, blind** (8 pages, no ground truth) | 2 / 4 | **2 / 2** | **0** |
| **Local `Qwen3.8-27B-4bit`** (MLX, this Mac) | not run | 1 of 3 resolutions correct | invented a defect at 2 of 3 resolutions |

**The union of the first three is 11 of 11**, and each covers precisely what the others cannot. That
complementarity *is* the architecture. The fourth row is why no local model is in it.

📌 **Row 2 was re-measured on a second host on 2026-09-03 and both of its arms were found broken** —
the contrast arm silently produced nothing, the centroid arm produced a frozen number. Both are fixed
(§2), and the corrected reading of that row is **1 / 2 claimed outright, 1 / 2 routed as an explicit
abstention, 0 false positives** — the second is `optical-centering`, where the layer now measures the
offset exactly (2.00px) but declines to say whether it is a defect, because that depends on a font
fact no substrate exposes. The row's headline number is unchanged; what changed is that it is now
true for a reason, on two machines.

⚠️ **This table is a correction.** The first version scored three pixels-only defects and reported
6 of 7. Building the cross-check exposed the reason: the `optical-centering` variant injected an
*empty* CSS rule, so its render was **SHA-256 identical to the control**. It was a null test item, and
both the deterministic layer and the blind reviewer were *right* to report nothing on it — I had
scored a correct abstention as a miss, against both. The corpus now injects a real delta (the base
carries optical compensation; the variant removes it), and the honest population is 9 DOM-determined
plus 2 pixels-only. **A corpus needs its own control run before it is allowed to grade anything**, and
mine did not get one until a third detector disagreed with it.

---

## 1. What we measured, and why it settles more than the literature does

The corpus (`bench/corpus/build_corpus.py`) renders one realistic dashboard thirteen ways: a clean
control plus twelve variants, each carrying exactly one injected defect at a known location with a
known magnitude. Nine defects are fully determined by the DOM. Three are invisible to it *by
construction* — the computed styles are correct and the rendering is still wrong.

That split is the whole instrument. It is the same shape as **DiffSpot** (arXiv 2605.29615, May
2026), which mutates one CSS property, re-renders, and asks what changed — and on which the best of
thirteen models scores **47.2%**, with hard-tier recall below 23% for every model and `line-height`
median recall at **4.0%**. We reproduced that difficulty independently.

**Three findings the corpus produced that no report predicted:**

**The "clean" control was not clean.** The first run flagged four defects on the hand-authored
baseline. Three were real WCAG failures I had written myself without noticing — white on blue-600 is
3.68:1, blue-100 on blue-600 is 3.01:1, both under the 4.5:1 floor. A deterministic linter earned its
keep before it ever saw an injected defect. (Fixed by moving to blue-700: 6.70:1 and 5.49:1.)

**Deduplicating findings by `(rule, target)` silently swallowed a real defect.** The colour-token
drift on the primary button was suppressed because an unrelated `token-drift` finding already existed
on that same element in the baseline. The key has to span the claim, not just its location — the
`assertion-span-must-equal-its-subject` failure, reproduced live. It scored 0/1 until fixed, then 1/1.

**Claude's blind review found three real defects nobody injected and no rule was looking for:** a
table caption promising grey rows that do not exist, an unlabelled icon button with the smallest hit
target on the page, and numeric columns left-aligned so the digits do not line up. None is reachable
by any rule I wrote, because none is a *violation* — each is a judgement about whether the page makes
sense. **That is the capability that cannot be replaced, and it is the one the deterministic layer
cannot grow into.**

### The local model, measured

No M1 Max VLM benchmark exists in public — A2 searched and found every fast Apple-Silicon number is
M4 Pro/Max or M5. So here is one, on the hierarchy-inversion page, `mlx-community/Qwen3.8-27B-4bit`
(released 2026-08-14), 16.1 GB resident, cold vision encode every row because a review loop never
shows the same screenshot twice:

| Input width | Megapixels | Image tokens | Wall clock | Prefill | Decode | Peak GPU | Verdict |
|---|---|---|---|---|---|---|---|
| 2560 px | 4.61 | ~1456 | **65.8 s** | 78.4 t/s | 16.7 t/s | 19.6 GB | wrong — invented a misalignment |
| **1344 px** | **1.27** | ~396 | **30.2 s** | 78.6 t/s | 12.3 t/s | 19.0 GB | **correct** |
| 1024 px | 0.74 | ~225 | **21.1 s** | 66.2 t/s | 12.6 t/s | 18.1 GB | wrong — invented a misalignment |

Two things fall out. **Accuracy is non-monotonic in resolution with a sweet spot near 1 MP**, which
independently reproduces mlx-vlm#1175 (mean IoU 0.542 at 12.8 MP → 0.736 at 1 MP) on different
hardware and a different task. And **the failure mode is a confident false positive** — at two of
three resolutions it named a misalignment that is not in the page. A detector that invents defects is
worse than no detector, because an agent *acts* on them.

21–66 s per screenshot also settles the interactivity question: this is a batch tool, not a loop
participant.

---

## 2. The architecture: three substrates, and never mix up which answers what

| Substrate | Answers | Never ask it |
|---|---|---|
| **Computed styles / CDP box model** | every question with a number in the answer — spacing, alignment, contrast against a solid backdrop, overflow, target size, token conformance, animation duration and easing | whether it looks good |
| **Accessibility tree** | semantic conformance, element identity, attribution back to source | anything perceptual — a perfectly valid a11y tree coexists with text overlap and occlusion |
| **Pixels (a frontier VLM)** | hierarchy, attention, "does this page make sense", contrast over a gradient, anything where the styles are right and the render is wrong | any number |

The governing rule, from A4 and confirmed by the bench: **the grounder supplies identity, the DOM
supplies geometry.** A model-produced bounding box is a 68-mAP estimate of something
`getBoundingClientRect()` returns exactly, for free, with no hallucination risk. Forbid the judge from
computing any distance from a box a model drew.

An agent using one substrate has a *silent* blind spot — it emits a confident clean report. That is
the most dangerous failure mode available to us and it is why the split is the architecture rather
than an optimisation.

### The seam, made explicit

The deterministic layer's most valuable output is not a finding, it is an **abstention**. On the
gradient-backdrop page it returns `contrast-indeterminate: cannot compute a ratio, backdrop is an
image/gradient — requirement 4.5:1 is UNVERIFIED for this text`, rather than a pass. Every silent
pass that should have been an abstention is a defect shipped. The abstention set is exactly the
vision layer's job queue, and it is small, which is what makes the vision spend affordable.

**Use `DOMSnapshot.captureSnapshot`, and do not let it delete that abstention.** A7 found the call
returns the compositor's own *blended* background colour per text run — the correct contrast operand,
which every JS ancestor-walk (including this bench's first version) merely approximates. Measured here:
**7.8 ms**, populated for 31 of 83 layout nodes, and it correctly resolves alpha and layered backdrops.
It is also 29× faster than the in-page `getComputedStyle` loop most tooling uses and 177× faster than
the per-node CDP walk, and the entire fact-pack serialises to ~854 tokens — *less than a screenshot*.
There is no context-budget argument for withholding facts from the judge.

But it samples **one** colour per text run, and on our gradient page it returned `rgb(30, 58, 138)` —
the gradient's leftmost stop:

| Sample point | Contrast vs white | Verdict |
|---|---|---|
| left stop `#1E3A8A` — **what CDP reported** | **10.36:1** | PASS |
| mid `#3B82F6` | 3.68:1 | FAIL |
| right `#DBEAFE` — where the text actually sits | **1.22:1** | FAIL |

A nine-point swing across a single text run, and the scalar reports the passing end. **Adopting the
blended colour naively converts an honest `INDETERMINATE` into a confident false PASS, which is
strictly worse** — an abstention routes to the vision layer, a pass routes nowhere. This is the
fail-safe-default-mimics-the-healthy-state trap, and it would have been invisible: the rule gets
*better* on solid and layered backdrops at the same moment it goes blind on varying ones.

The rule that survives both findings: **take the blended colour, and keep the abstention whenever the
resolved backdrop chain contains a gradient or an image**, because no scalar can represent a backdrop
that varies across the element it sits on.

### The third layer: measure the DISAGREEMENT, not either side

A5's sharpest claim is that the high-value defects live in the *gap* between the two descriptions
rather than in either one, and that the cross-check is therefore the thing to build first — about 200
lines of NumPy, no model, no GPU. Built it (`bench/detect_xcheck.py`) and it holds. It is not a third
detector; it is a comparator that fires only where the DOM's claim and the rendered pixels disagree by
more than a stated tolerance, which means it needs no aesthetic judgement and no learned model.

The validated arm settles the gradient case that the scalar could not:

```
contrast-on-gradient
  [xcheck-contrast-varies] contrast is not one number across this text: 4.81:1 at
  the left edge and 1.57:1 at the right. Any single computed value is a fiction,
  and the right end is the one that fails a reader.
```

Sampling the backdrop separately in the left and right thirds turns "unrepresentable" into two
numbers and a verdict — no VLM call, no abstention, zero findings on the control. **That moves
contrast-over-a-gradient out of the vision layer's queue entirely.**

⚠️ **Correction 2026-09-03: "the validated arm" was validated on one host, and it did not survive the
second.** Re-run on Linux, where `Helvetica` falls back to Liberation Sans, this check produced
**nothing at all** on the gradient page — no finding, no abstention, a silent pass. The cause is that
it sampled the backdrop as each band's **modal colour**, and *under a gradient no backdrop colour
repeats* (every column differs) while the text's own solid fill repeats hundreds of times. **The mode
of the band is therefore the text**, the check compared the text to itself, got ~1:1 at both ends,
found no delta and said nothing. It worked on macOS only because Helvetica painted few enough white
pixels to lose the mode — a verdict turning on a font substitution.

Fixed by reading the backdrop as the band's **median** instead: the median of a gradient band is its
middle column, a real backdrop colour, and a minority of ink does not move it. Deliberately *not*
fixed by filtering the ink out first — filtering on "close to the text colour" would discard the
backdrop precisely where it is closest to the text, which is exactly where contrast is worst, and the
check would go quiet on its own worst case. Ink domination is handled by an explicit abstention
instead. Post-fix on this host: **5.89:1 left, 1.73:1 right**, zero findings on the control.

**The generalisable lesson is the one this document already keeps re-learning:** a detector that goes
*silent* fails invisibly. Both of §2's pixel arms were broken in the same direction — one returned a
frozen number, the other returned nothing — and neither had a sensor pointed at it. The corpus caught
both only because a second host disagreed with the first.

🚨 **The centroid arm was PROVISIONAL and shipped disabled** (`--x2` to enable), because trying to
validate it found two defects in it, and both are instances of the exact failure this document warns
about — a plausible number nobody checked. (a) It compares ink to the element's **own** box, and
`getBoundingClientRect` returns the *post*-transform box, so a `translate` moves box and ink together
and the measured offset is **invariant under the very compensation it is supposed to verify**. (b) Its
background is the crop's modal colour, so on a round button the square crop's corners — page
background outside the circle — count as ink and swamp a 16px glyph. Both fixes are known (measure
against the container; mask to the painted shape) and neither is done. Shipping it on would have
handed the pipeline a confident number with no ground truth behind it.

✅ **FIXED 2026-09-03 — both arms, plus a third defect the fix exposed. X2 now ships ENABLED**
(`--no-x2` to disable). The measurement that settles it, on two pages whose only difference is
`transform: translate(2px,2px)` vs `none`:

| arm | `clean.html` | `optical-centering.html` |
|---|---|---|
| old — own box, modal background | dx −1.59  dy +1.73 | dx −1.59  dy +1.73 |
| new — container, shape-masked, edge-eroded | dx **+0.17**  dy +3.77 | dx **−1.83**  dy +1.77 |

The old arm returns the **same number to two decimals on both pages**. It was not imprecise, it was
blind by construction, and it would have gone on reporting that number with total confidence — the
strongest evidence in this wave for why a plausible number is worse than no number. The new arm
recovers the injected offset **exactly: 2.00px left and 2.00px up**.

**Fix (a) — measure against the container.** The subject is the parent's box, and the candidate gate
is the parent's own claim (`align-items:center` **and** `justify-content:center`). That is what makes
it a cross-check rather than a measurement: the DOM asserts "I centre this child" and the pixels are
asked whether they agree. The parent is not the transformed node, so the invariance is gone.

**Fix (b) — mask to the painted shape, built analytically from the container's `border-radius`.** The
colour test *could not* have done this: the glyph is `#FFFFFF` and the page behind the round button is
also `#FFFFFF`, so the corners are indistinguishable from ink **by colour and separable only by
shape**. The DOM supplies the geometry; the pixels supply only the ink distribution.

**The third defect, found by validating the fix — the antialiased ring.** A painted circle has a ~1px
edge where blue blends to white, and the outer half of that ring is *nearer white than blue*, so a
nearest-of-two split calls it ink. Roughly **10 stray pixels**, at the maximum distance from the
centre, moved `dy` by **5.5px** on a 44px button while the glyph's own 96 pixels sat still — and the
ink bounding box read 0–36px for a glyph 16px tall. The number stayed entirely plausible throughout.
Fixed by eroding the mask 2px past the boundary before any pixel is classified. **This is the same
failure as (a) and (b) one level down, and it was only visible because the fix made the number move at
all: a broken measurement that never changes cannot be caught by watching it change.**

⚠️ **And X2 does not adjudicate — it ABSTAINS, emitting `xcheck-optical-indeterminate`.** On the clean
control the compensated glyph still sits **3.77px** below the container's centre, because the
compensation was authored against macOS/Helvetica and this host's fallback face puts U+25B6 lower in
the em box. (The horizontal compensation transfers: 0.17px residual. The vertical one does not.) **The
residual is a property of the font**, and no substrate in this pipeline exposes a glyph's intrinsic
optical centre — so "is 3.77px correct compensation or a defect?" is not answerable by arithmetic, and
any threshold separating it from 1.77px would be a constant tuned to this corpus on this host. P5-route
already classes `optical-alignment` as unscreenable. X2's honest product is the measurement plus an
explicit UNVERIFIED, which the router turns into a cropped question.

---

## 3. Local models: no

Not on quality, not on latency, and not on the analogy.

- **Quality.** The open entrant in *MLLM as a UI Judge* scored **53% on pairwise design preference —
  chance** — against 90–93% for frontier models on clear cases (arXiv 2510.08783). Chance-level design
  advice is actively misleading, not merely worse. Our own measurement above agrees: correct at one
  resolution out of three, confidently wrong at the other two.
- **Latency.** 21–66 s per screenshot, measured here.
- **Quantization.** Spatial and layout reasoning is the *most* quantization-sensitive class measured
  (8–15% loss at 4-bit; the projector is the worst bottleneck; arXiv 2607.08029). A uniform 4-bit
  checkpoint — which is what `mlx-community/*-4bit` gives you by default, and what we measured — is
  precisely the configuration to reject. The correct recipe is 4-bit LLM, ≥8-bit projector, 8-bit or
  fp16 vision tower, and on M1/M2 **fp16 not bf16**, because bf16 is software-emulated on this silicon.
- **The analogy fails on all four properties.** Local speech won because ASR is narrow, has crisp
  ground truth (WER), is high-volume, and is latency-sensitive — and because open 0.6–2.5B models
  literally top the leaderboard. Design critique is open-ended, has no ground truth, is low-volume,
  and tolerates seconds of latency. Nothing transfers.

**Where a local model would earn a place:** bulk anomaly *screening* over a large corpus of
screenshots where the cost of a cloud call per shot is the binding constraint and a 50% hit rate is
acceptable because a second pass adjudicates. We do not have that workload. If we ever do, the config
is `Qwen3.5-35B-A3B` (MoE, ~3B active, roughly 9× cheaper prefill) at ~1344 px, not a dense 27B.

---

## 4. Cloud: default to the vision we already have

The delta over Claude's own vision is narrow and not where intuition puts it. Four free levers come
before any new vendor:

1. **Pin the high-resolution tier and capture at ~2576 px long edge.** Claude 4.7+ ships a
   2576 px / 4,784-visual-token tier automatically; the old 1568 px guidance in our March corpus is
   stale. Opus 4.6 → 4.7 on ScreenSpot-Pro went 69.0% → 79.5% attributed mainly to accepting ~3.3×
   more pixels. **If our pipeline downsamples, we inherit the old score whatever model we buy.**
2. **Take localisation out of the model entirely** — the accessibility tree and `getBoundingClientRect`
   are exact and free.
3. **Crop and zoom rather than downscale.** ScreenSeekeR took OS-Atlas-7B from 18.9% → **48.1%** on
   ScreenSpot-Pro with no model change — a larger delta than every model upgrade combined.
4. **Run the deterministic layer first** so the model is only asked the residue.

Set `transformations: {"oversized_image": "error"}` so a silent resize becomes a 400 naming the exact
target size, rather than quietly destroying the evidence.

**The one genuine gap:** you cannot crop when the question is global — full-page rhythm, whole-frame
sharpness. Claude's high-res tier caps at ~3.75 MP, so a 3840×2160 retina capture loses ~55% of its
pixels. If that case matters, OpenAI's `detail: "original"` is the only documented no-downscale path.
Gemini is worth a call only where there is no accessibility tree at all — canvas, WebGL, PDF comps,
competitor screenshots.

---

## 5. Specialist CV: no, with exactly one exception

Frontier general VLMs have overtaken every open GUI specialist: Claude Opus 4.5 → 4.6 → 4.8 on
ScreenSpot-Pro ran 45.7% → 83.1% → 87.9%, against the best open specialist Holo2-235B at 70.6–78.5%.
Microsoft's own OmniParser successor states it "does **not** rely on separate models to parse the
screen." Scaffold half-life in this field is roughly 18 months. A specialist buys an *inventory*, not
*precision*.

**The exception is saliency, and it is principled rather than accidental.** On the same test set, same
metric, same images (UIGaze, arXiv 2604.26352): UI-trained **UMSI++ scores CC 0.833** against the best
frontier VLM at **CC 0.408** — GPT-5.4 0.408, Claude Opus 4.6 0.344, Gemini 3.1 Pro 0.144. The gap is
2× and the mechanism explains it: early gaze is *pre-semantic*, and a VLM reasons semantically. The
VLM even improves with longer simulated viewing (0.217 at 1 s → 0.408 at 7 s), which is exactly
backwards for the reflexive first second where hierarchy either works or does not.

So saliency is the one place a small specialist model beats everything hosted. Use it as **a second
image plus one decision-relevant statistic** — "the element you named primary captures 4% of predicted
attention mass; the largest mass, 31%, is on the hero image" — never as a score. Blocker: UEyes/UMSI++
weights carry **no license file**; that must be resolved before any non-personal use.

---

## 6. The benchmarks cannot decide this for us

This is the most consequential negative finding in the wave, because it invalidates the obvious way to
pick a model.

- **ScreenSpot-Pro contains zero web screenshots.** It is 1,581 instructions over 23 professional
  *desktop* applications — VSCode, Photoshop, AutoCAD, MATLAB. Every "SOTA on ScreenSpot-Pro" headline
  is evidence about CAD panels. *(This corrects A3, which treated it as the benchmark closest to our
  task; A4 read the benchmark's composition and is right.)*
- **Every ScreenSpot variant scores point-in-box, not IoU.** A prediction counts if a *point* lands
  inside the box. There is no box-quality term, so a model can score 96% with edges tens of pixels
  wrong. **No published number in this field certifies the property a design reviewer needs.**
- **The aggregators are unreliable.** llm-stats' board self-declares "0 verified results, 25
  self-reported". benchlm says Opus 4.6 scores 83.1% on ScreenSpot-Pro; Anthropic's own system card
  says 69.0%. Fourteen points apart. Read vendor system cards, never aggregators.
- **Judgement benchmarks say the judge is the weak link.** WebDevJudge: humans 84.82%, best models
  66.06%. WiserUI-Bench: frontier MLLMs barely above the 50% line, and order-invariant consistent
  accuracy **~30–37%** against a 25% chance baseline. Rubric scoring shows **16–39% top-1 ranking
  reversals from reordering alone**. Even a purpose-built fine-tune reaches 74.25% average but only
  44.30% consistent.
- **The web-specific number to use instead** is WebClick (1,639 real web screenshots): Holo1.5-7B
  90.24, UGround-7B 82.37, stock Qwen2.5-VL-7B 74.37, OmniParser v2 **40.7 at default thresholds**.

Corollary: **the corpus in `bench/` is not a nice-to-have.** It is the only instrument we have that
measures the thing we actually do.

---

## 7. What the June 2026 decision already settled

A13's audit found the answer to the biggest question was already on disk and had been lost.

The March 2026 corpus describes an architecture whose subject (`/preview/luxury-menu`), instrument
(`scripts/visual-validate.ts`, 1,974 lines) and central bet (autonomous VLM-judge quality gating to
85–90+) were all deleted or refuted by June — and not one of the four documents carries a staleness
banner. `docs/reference-images/` and `~/.claude/hooks/visual-preview.sh` were never built at all. The
`visual-design-iterator` agent *was* built, 568 lines, still on disk, and its first action curls a
route deleted on 2026-04-25 — a live-looking orphan.

Two June measurements outrank everything the March layer asserts:

- The pixel-VRT lane that "automation" actually shipped caught **0 of 6** real bugs prospectively.
  Regression-lock is not prospective detection.
- The campaign ratified: *"Do NOT run the heavy RE-DERIVE path (VLM 'is-it-great' gate / tournament …
  correlate with regression-to-the-mean; taste stays human, gates adjudicate correctness/coverage
  only."*

**That decision stands and this work does not reopen it.** The sanctioned role for the VLM is advisory
triage, never a CI gate. Everything in §2 is a correctness-and-coverage instrument; the taste question
stays with the operator.

The one thing the campaign promised and never produced is the north-star taste yardstick
(`DESIGN_PAGE_METHODOLOGY_PHASE1B_NORTHSTAR.md`, absent, no add-commit in `git log --all`). That gap is
still open.

Also corrected, because our budgets rest on them: the image-token formula is patch-based
`⌈w/28⌉ × ⌈h/28⌉`, not the `/750` in our docs; the API file limit is 10 MB, not 5; Claude models now
return absolute pixel coordinates, so "cannot localize" is stale.

---

## 8. What to build

Nothing in this list is a model purchase.

**Already built, in `bench/`** — keep and extend:
- `corpus/build_corpus.py` — 13-page ground-truth corpus, `detectable_by` split, clean control.
- `capture.py` — screenshot + full layout/style snapshot in one browser pass, so a pixel finding and a
  DOM finding describe the same frame. sRGB pinned, LCD text off, reduced motion, fonts awaited.
- `detect_dom.py` — nine general design-lint rules with an explicit `INDETERMINATE` verdict.
- `bench_local_vlm.py` — the resolution/latency sweep.
- `detect_xcheck.py` — the DOM-vs-pixels comparator; all three arms now validated and enabled.
- `verdict.py` *(added 2026-09-03)* — the single predicate for CLAIM vs ABSTENTION. Both detectors,
  the router and the budget ask that question, and one of them answering it differently would either
  report the seam as a defect or spend a model call re-asking a settled question.
- `route.py` *(added 2026-09-03)* — the abstention router; see item 1 below.
- `profiles.py` *(added 2026-09-03)* — the per-app rule weightings; see the per-app note below.
- `fp_budget.py` *(added 2026-09-03)* — the false-positive budget; see item 2 below.

Reproducing the whole thing is four commands, in this order — the corpus's rendered pages, shots and
snapshots are gitignored on purpose, so a run always regenerates them:

```bash
python3 corpus/build_corpus.py corpus/out && python3 capture.py corpus/out
python3 detect_dom.py corpus/out && python3 detect_xcheck.py corpus/out
python3 route.py corpus/out --profile reso-management
python3 fp_budget.py corpus/out --profile reso-management   # exit 1 = budget breached
```

`capture.py` honours `BENCH_CHROMIUM_PATH` for a host that ships a pre-baked browser and forbids
`playwright install`; without it the Playwright build number must match the installed browsers.

**How it reaches a session — a plain CLI, not an MCP server.** A11 checked the assumption and it was
wrong in our favour: an MCP tool *can* return image content to Claude Code. But image data is charged
against `MAX_MCP_OUTPUT_TOKENS` (default 25,000), and the `anthropic/maxResultSizeChars` escape hatch
explicitly "has no effect on tools that return image content" — so an MCP image tool has exactly one
lever, a session-global env var. A CLI that writes a JSON findings file and an annotated PNG, and lets
the agent `Read` the PNG, chooses its own output resolution and therefore stays inside the Read
ladder by construction. Fewer moving parts, and it is already the fleet's habit.

**Division of labour inside the perception layer**, from A5 and confirmed by the bench: **learned
models for semantics and grouping, classical CV for every number.** "Uneven spacing" is a claim about
a distribution of distances — connected components, sort, diff, histogram is the entire computation,
tens of milliseconds of NumPy on one core, and exact rather than probabilistic. A detector emitting
`{"label": "card", "score": 0.91}` has not started on the question. The decisive property is not mean
accuracy but the shape of failure: **classical CV fails by returning an obviously wrong number; a
learned model fails by returning a plausible one.** For a measurement layer feeding an agent that will
act on it, legible failure is worth more than a higher average. (The one place the gap runs the other
way: SAM's masks track rendered edges *better* than natural ones, because a rendered edge is a true
step function — but SAM is not semantic, so it will happily return a pixel-perfect mask of a gradient
band.)

**To add, in order:**
1. ✅ **The abstention router — BUILT 2026-09-03, `bench/route.py`.** (The cross-check in
   `bench/detect_xcheck.py` already removes the gradient case from this queue.) Deterministic pass
   first; its `INDETERMINATE` set plus the pages it cannot reason about become the VLM's queue,
   cropped to the region in question.

   **The queue is small, and that is now a measurement rather than a hope.** Over the 13-page corpus:
   16 findings settled deterministically, **15 abstentions raised → 2 routed.**

   | | | |
   |---|---:|---|
   | abstentions raised | 15 | |
   | − resolved free by the cross-check | 2 | the gradient pair — a full verdict for zero tokens |
   | − unchanged vs the baseline capture | 11 | the same button, on 11 renders of the same page |
   | **= routed to a model** | **2** | the first look, and the one that actually moved |

   Three subtractions, and **the middle one was not in the design** — it came out of running the
   thing. X2's abstention fires on a component present on every page, so without it the router
   demanded 26 image blocks against a session ceiling of 12: a context split to re-ask the same
   question about the same button thirteen times. An abstention whose *measurement* matches the
   baseline within tolerance is a property of the design, not of the change under review. On a corpus
   the baseline is the clean control; in production it is the last reviewed capture of that page.
   The comparison is over structured `measure` fields, not the rendered detail string — comparing
   prose compares presentation, and 2.9 vs 3.0 would have read as news.

   Also **a correction to P5-route's own T1 formula**, which subtracts any target carrying an
   `xcheck-*` finding. `xcheck-optical-indeterminate` *is* an abstention, so under that shorthand an
   abstention resolves itself and leaves the queue silently. A resolution has to be a CLAIM — hence
   `verdict.py` as one shared predicate rather than a string prefix test in three places.

   The rest of the stage is implemented as specified: the NEVER list is an assertion that refuses a
   question rather than a comment (`if the answer has a number in it, the model does not get the
   question`), T2 fires once per page and no profile may weight it to zero, crops carry 16px of bleed
   and cluster at 32px, and the device scale is chosen as **the largest that still clears all three
   ceilings** — `raster ≤ 2000`, `bytes ≤ 3,932,160`, and `⌈w/28⌉ × ⌈h/28⌉ ≤ 4784` — rather than
   fixed, which is §4 lever 3 written as arithmetic instead of as advice. The corpus's region crops
   come out at 67×73px @1.5x = **9 visual tokens**.
2. ✅ **A false-positive budget — BUILT 2026-09-03, `bench/fp_budget.py`.** ~20% FP is where an AI
   reviewer loses credibility regardless of catch rate. Our two zero-FP runs are the baseline to
   defend; every rule added must be re-run against the clean control before it ships. The script is
   that re-run, and it exits non-zero when the budget breaks.

   It runs **both detectors from source** rather than reading their findings JSON, so it can never
   certify a stale artifact against rules that have since changed. Current state: **0 false positives
   on the control**, 11 of 12 declared rules exercised, off-target claims 1 of 16 novel (6%, against
   the 20% threshold).

   Three things it deliberately does *not* do. It **does not count an abstention as a false
   positive** — that would report the seam as the defect; abstentions get their own budget, because
   they fail differently (a false positive costs trust, an abstention costs a model call). It **does
   not gate the corpus's second FP class** — a claim on an unmodified element of a defect page —
   because the manifest's target is a CSS selector and a finding's target is a captured path, so
   matching them is a heuristic; a gate built on a heuristic fails in both directions and gets
   bypassed within a month, so those are listed for a human instead. And it **names declared rules
   that never fired at all** (`xcheck-zero-ink` today): a rule the corpus cannot exercise has not been
   re-run against the control in any meaningful sense, and must not read as coverage.
3. **Order-randomised comparison.** If we ever compare two designs, permute over 3–5 orderings —
   that recovers about two-thirds of the benefit of ten, and exact balancing buys essentially nothing.
   Report discrimination spread and swap-consistency, never mean agreement.
4. **Motion, deterministically.** `getComputedTiming()` returns duration, easing, delay, iterations
   with `auto` resolved — "this transition is 400 ms and eases wrong" is an assert, not a vision task.
   Note the trap: CDP `Animation.setPlaybackRate(0)` controls WAAPI but not `requestAnimationFrame`,
   while Playwright's `page.clock` patches rAF but not the document timeline. A harness using one has
   a silent hole, and a GSAP page reports "0 animations found" as a false green.
5. **Saliency, second image only**, once the UMSI++ licence question is answered.

**Per-app, because they are three different problems:** `reso-landing-app` (Next 14, purchased
template) is largely a marketing-aesthetics problem; `reso-management-app` (Next 16, React 19,
Tailwind 4) is mostly design-system conformance, where the deterministic layer does nearly all the
work; `reso-web-app` (Next 13) sits between. One review harness, three different rule weightings.

✅ **BUILT 2026-09-03, `bench/profiles.py`**, and the shape it took is worth stating because the
obvious implementation is unsafe. A weight orders findings and sizes the model-call queue; **it never
decides truth.** So:

- **Accessibility and correctness are pinned at 1.0 in every profile** — `contrast`, `touch-target`,
  `overflow`, `xcheck-zero-ink`, `xcheck-contrast-varies`, and every abstention. 2.54:1 is 2.54:1 in a
  landing page and in a dashboard. An app that wants those quieter wants a different *requirement*,
  not a different weight, and a profile file that could silence them is a way to make a report look
  clean rather than be clean.
- **Nothing is deleted.** A finding under the mute threshold is flagged and counted on its own line,
  never dropped — a weighting scheme able to vanish a finding would reintroduce the silent pass one
  layer above the rules.
- **The page-level judgement call is never weighted to zero** (P5-route T2). A profile may damp its
  rank; cutting it converts the reviewer into a linter with a screenshot.

What differs, then, is the conformance family. On `reso-landing-app` `token-drift` and
`grid-violation` drop to 0.2 — a purchased template is measured against tokens it never agreed to, so
those findings are arithmetically true and almost entirely noise, which is precisely the ~20% budget
being spent per-app instead of by loosening a rule for everyone and blinding the dashboard where the
same rules are the whole point. On `reso-management-app` they run 1.75–2.0 and the aesthetic classes
damp to 0.5–0.75. `reso-web-app` is deliberately flat: no evidence either way, so none is invented.
Measured on the corpus, the same 16 claims yield **5 muted under `reso-landing` and 0 under
`reso-management`** — the profile is visibly doing something, and `fp_budget.py` prints exactly what
it muted so a weighting change can never be silent.

⚠️ The multipliers themselves are **ordinal and uncalibrated.** They break ties in the intended
direction; they are not evidence about how much worse one class is than another, and the corpus has
never had enough competing findings on one page for the ranking to be exercised.

---

## 9. What would change this answer

- A local model that clears ~70% on a DiffSpot-shaped eval at under 10 s per screenshot on this Mac.
- A published web-UI defect-localisation benchmark that scores IoU and false positives. None exists.
- A licence for UMSI++, which would move saliency from "promising" to "shippable".
- Evidence that our review bottleneck is *finding* problems rather than *acting* on them. A15's
  sharpest point is that this whole wave assumed perception was the constraint, and the most probable
  failure is a system that sees fine, critiques plausibly, and changes nothing.

## 10. Provenance

15 agent reports in `agents/` (A1–A15; A5 re-fired twice — see below). Bench code and raw results in
`bench/`, including `corpus/out/findings_dom.json`, `local_vlm_results.json` and `corpus/out/blind_key.json`.

**A note on the wave's own failure mode, which is a repo defect worth fixing.** The `deep-research`
agent type grants `Read, Glob, Grep, Bash, WebSearch, WebFetch, Agent, ToolSearch, Skill` — and **no
`Write`**. Our mandatory field-7 Delivery contract instructs every agent to write its findings to an
absolute path, so all fifteen had to satisfy it by streaming a 300-line markdown document through a
single Bash heredoc. Ten succeeded. A5 stalled mid-stream doing exactly that, its last words being
*"Write tool is disabled; creating the mandated file via heredoc instead."* The contract and the tool
grant are in conflict. **Fixed in this commit** (`Scope (grown): +repair the deep-research Delivery-
contract conflict`): `Write, Edit` added to `agents/deep-research.md`. That grant widens no
capability — the agent already had `Bash` and could always create files — it only replaces a fragile
channel with the first-class one. A contract an agent cannot satisfy with a proper tool is a contract
that fails under load, and it failed at 2/15.

Both stalled axes were re-fired on `general-purpose` with an explicit write-incrementally instruction
and delivered in full, so coverage is 15/15 with no axis dropped.

**On recovery generally, since it came up:** `/limit-recover`'s *audit principle* is the right
instinct for any cut-off subagent — disk-truth audit every slot, re-run anything not provably
complete, never accept a partial. Its *machinery* is not: it is built for a quota or login cliff and
recovers by transcript transplant to another account. A mid-stream API stall has no reset to wait for
and no account to move to. Audit with it; recover by re-firing.
