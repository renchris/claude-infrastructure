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
| **DOM-vs-pixels cross-check** (~180 lines NumPy, no model) | — | **2 / 2** † | **0** |
| **Claude vision, blind** (8 pages, no ground truth) | 2 / 4 | **2 / 2** | **0** |
| **Local `Qwen3.8-27B-4bit`** (MLX, this Mac) | not run | 1 of 3 resolutions correct | invented a defect at 2 of 3 resolutions |

**The union of the first three is 11 of 11**, and each covers precisely what the others cannot. That
complementarity *is* the architecture. The fourth row is why no local model is in it.

† **The cross-check row was 1 / 2 when this was written.** Its second arm shipped disabled because
validating it found two defects in it; both were repaired on 2026-09-02 and it now scores 2 / 2 with
the same 0 false positives, which also makes it the only layer that covers both pixels-only defects
without a model. The repair, what it cost, and the third defect it uncovered on the way — a *silent
false negative* in the arm that was already shipped, on the exact page built to exercise it — are in
§11.

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

🚨 **The centroid arm is PROVISIONAL and ships disabled** (`--x2` to enable), because trying to
validate it found two defects in it, and both are instances of the exact failure this document warns
about — a plausible number nobody checked. (a) It compares ink to the element's **own** box, and
`getBoundingClientRect` returns the *post*-transform box, so a `translate` moves box and ink together
and the measured offset is **invariant under the very compensation it is supposed to verify**. (b) Its
background is the crop's modal colour, so on a round button the square crop's corners — page
background outside the circle — count as ink and swamp a 16px glyph. Both fixes are known (measure
against the container; mask to the painted shape) and neither is done. Shipping it on would have
handed the pipeline a confident number with no ground truth behind it.

✅ **Both fixes landed 2026-09-02 and the arm is now on by default** (`--x2` is a no-op kept so an old
invocation does not break). It scores **1 / 1 on `optical-centering` with 0 findings on the control**,
against 0 / 1 with **2** control false positives before. The quarantine was the right call and the
paragraph above stands as written; §11 records what the repair actually took, including the two
further defects it exposed that this paragraph did not predict.

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
- `detect_xcheck.py` — the DOM-vs-pixels comparator, all three arms live (§11).
- `route.py` — the abstention router, with a `--selftest` that RED-proves it both ways.
- `profiles.py` — the per-app rule weightings, and the invariant that keeps them safe.
- `fp_budget.py` — the false-positive gate; exits non-zero on a noisy control.
- `review.py` — the CLI: `review.json` + an annotated PNG per page + the cropped queue.

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
1. ✅ **The abstention router** — `bench/route.py`, built 2026-09-02. (The cross-check in `bench/detect_xcheck.py` already removes the gradient case from this queue.) Deterministic pass first; its `INDETERMINATE` set plus the pages it
   cannot reason about become the VLM's queue, cropped to the region in question.
2. ✅ **A false-positive budget** — `bench/fp_budget.py`, built 2026-09-02. ~20% FP is where an AI reviewer loses credibility regardless of catch
   rate. Our two zero-FP runs are the baseline to defend; every rule added must be re-run against the
   clean control before it ships.
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
✅ Built 2026-09-02 as `bench/profiles.py` — see §11 for the invariant that makes a weighting safe.

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

---

## 11. The pipeline, built and measured (2026-09-02)

Items 1 and 2 of §8's build list, the per-app weightings, and the X2 repair §2 quarantined. Five new
files in `bench/`, run end to end from a clean rebuild on every claim below. Everything here is a
measurement taken on 2026-09-02, on Linux/Chromium 141 rather than the M1 Max the rest of this
document was written on — which turned out to matter, twice.

| Layer | DOM-determined | Pixels-only | False positives on the control |
|---|---|---|---|
| `detect_dom.py` (unchanged) | **9 / 9** | 0 / 2 (1 honest abstention) | **0** |
| `detect_xcheck.py` **all three arms** | — | **2 / 2** | **0** |

The cross-check now covers **both** pixels-only defects that are measurements, leaving exactly one —
`hierarchy-inversion` — for the vision layer. That is the whole point of the split, and it is now the
observed shape of the queue rather than a prediction about it.

### What repairing X2 actually cost, and the two defects it exposed

The two known defects were real and both fixes worked as §2 predicted. Neither was the expensive part.

**X3 was silently returning nothing, on the page built to exercise it.** The arm that *shipped* — the
one this document's §2 quotes a working transcript from — found zero findings on `contrast-on-gradient`
here. Its comment says it samples "the modal non-ink colour"; its code sampled the modal colour, and on
a gradient the ink wins that vote outright, because every backdrop column is a slightly different
colour while the glyph pixels are all one colour. The left third of the caption came back `#FFFFFF` —
the text's *own* colour — for a reported contrast of **1.00:1**. The fix is to drop pixels near the
foreground and take the **median** of the rest, a mode being meaningless on a ramp where no value
repeats. Now: 6.15:1 left, 1.73:1 right, and the gradient case leaves the vision queue as designed.
**This is the failure mode the document's own thesis is about, found in the document's own code**, and
the only reason it surfaced is that a second machine rendered the page differently. A detector that
returns nothing looks exactly like a page with nothing wrong.

**The control was not optically clean, and could not have been.** The play mark was `&#9654;` at 16px
with a `translate(2px, 2px)` compensation whose constant was *measured on macOS/Helvetica*. On a box
with DejaVu the same glyph's ink sits down-right instead of up-left, so that compensation pushes it
further off: measured 3.4px below the button's centre on `clean.html`. A correct X2 therefore fires on
the control, and the corpus grades a working detector as a false positive because a font is missing.
Fixed at the source — the mark is now a CSS border triangle, whose ink is a right triangle with
vertices (0,0) (14,8) (0,16) and whose centroid is at `14/3`, exactly `14/2 − 14/3 = 2.33px` left of
its own box centre, on every machine. The compensation is that number rather than a measurement.
**A ground truth that depends on an installed font is not ground truth**, and this corpus had shipped
one for a week. (Second-order: removing the glyph's `font-size` left the 16px type step used exactly
once, and `type-scale` promptly fired on the control. Button labels now carry it, `line-height` pinned
so no box moves. A scale step exercised exactly twice is one edit from turning the control noisy.)

X2 after both repairs, on the same corpus: **0 / 1 with 2 control false positives → 1 / 1 with 0.** The
measured offset moves from `+0.27, +3.44` on the compensated page to `−1.73, +1.44` on the
uncompensated one — a clean 2px shift in both axes, which is the proof that defect (a) is really gone.
Measuring against the container rather than the element's own post-transform box is what makes the
compensation *visible* to the measurement instead of cancelling out of it.

Two implementation notes worth keeping, because both were only found by building it:

- **The shape mask needs its holes filled.** Masking by "differs from the colour sampled outside the
  box" removes the square crop's corners exactly as §2 prescribed — and also removes white ink on a
  coloured control sitting on a white page, which is at distance *zero* from that colour. The glyph
  punches a hole in the shape it sits inside. Row-and-column span closure fixes it for every shape UI
  actually paints, and the AND of the two cannot leak past the mask's own extent.
- **The antialiased rim is bigger than the mark.** A 44px circle's rim is ~138 perimeter pixels against
  a 16px glyph's ~90, and every one of them differs from the fill. Without a 2px erosion the rim *is*
  the measurement — the same swamping failure as defect (b), wearing different clothes.

### The router (`route.py`)

Three disjoint states, and the disjointness is the design: **DETERMINED** (a rule returned a number —
never sent to a model), **RESOLVED** (an abstention the pixel cross-check answered), **QUEUED**.

Measured over the 13-page corpus: **17 determined · 2 resolved · 13 queued**, and the queue is
**2.1% of elements**. The 13 are one page-level residue job each — the "does this page make sense"
question no rule is shaped to ask — and **zero abstentions**, because the cross-check answered both.
That is §2's claim about the seam, now a number: the entire gradient case costs no vision spend.

The queue's crops are integer nearest-neighbour zoomed to ≥768px long edge and capped at the tier's
2576px, and a full frame that would exceed ~3.75 MP records `pixels_lost` in the job rather than
downscaling quietly. Every job ships the DOM's exact geometry as `facts` plus a `forbid` line: the
grounder supplies identity, the DOM supplies geometry, and shipping the geometry *with* the crop is
what makes that rule enforceable instead of aspirational. **`route.py` calls no model and has no
`--judge` flag**, deliberately — §7's June 2026 ratification is not reopened here.

`route.py --selftest` RED-proves it in both directions, because a healthy router and a blind one look
identical from outside: on this corpus success means QUEUED reads 0 abstentions, and so does a router
that has stopped *seeing* abstentions. It withholds the cross-check's answer and asserts the
abstention comes back out as a real cropped file on disk, then restores it and asserts it does not.
Writing that test found a third bug: `768 // 1264` is 0 but `768 // 500` is **1**, so floor division
left a 500px crop un-zoomed and 268px below the minimum the function existed to guarantee.

### The false-positive budget (`fp_budget.py`)

Two budgets, because conflating them is how a bench flatters itself. **Control FP: budget 0, got 0** —
a hard gate that exits non-zero, since a rule firing on the control makes its findings everywhere else
worth nothing. **Off-target FP on the variants: 17 on-target, 2 off-target of 19 → 10.5%**, against
the ~20% credibility budget.

Both remaining off-target findings are the *same* two, and they are **correct reports**: the
`contrast-on-gradient` injection puts the gradient behind `.hero-title` as well as `.hero-caption`, and
the manifest's target names only the caption. They are counted against us anyway. A scorer that
exonerates whatever it recognises is not a scorer, so the printed number is a **ceiling** on the true
rate rather than an estimate of it.

### Per-app weightings (`profiles.py`)

`reso-management` ×1.6 conformance / queue 2 · `reso-landing` ×0.4 conformance with `token-drift`
suppressed outright / queue 5 · `reso-web` between / queue 3. On a purchased template, drift from
*our* tokens is not a finding, it is a restatement of the fact that we bought the template —
`reso-landing` drops 3 of 17 findings on that basis and nothing else changes.

**The invariant that makes a weighting safe, and it is checked rather than asserted: a weight may
suppress or reorder, never create.** No profile runs a detector, lowers a threshold or relaxes a
tolerance, so the zero-FP control result holds under all four *by construction* — and `fp_budget.py`
re-scores the control under every profile on every run rather than trusting that sentence.
**Accessibility has a floor of 1.0 that no profile may go under**, which is a policy: a marketing
page's contrast failure is a contrast failure. Conformance-to-our-design-system is the only axis a
profile may turn down, because it is the only one that is genuinely a claim about which codebase you
are in.

### Reproducing it

```bash
cd bench && python3 -m venv .venv && .venv/bin/pip install numpy pillow playwright
.venv/bin/python corpus/build_corpus.py corpus/out
.venv/bin/python capture.py corpus/out          # BENCH_CHROMIUM=<path> if not a playwright install
.venv/bin/python detect_dom.py corpus/out       # control: 0 findings
.venv/bin/python detect_xcheck.py corpus/out    # control: 0 findings; 2/2 pixels-only
.venv/bin/python route.py corpus/out --selftest # both directions
.venv/bin/python fp_budget.py corpus/out        # the gate; non-zero exit on a breach
.venv/bin/python review.py corpus/out --profile reso-management --out /tmp/review
```

`capture.py` gained one env var, `BENCH_CHROMIUM`, because `channel="chromium"` resolves against the
build the pip package was pinned to and fails with "please run playwright install" on any box where
the browser was provisioned separately. Absent the override nothing changes.

### What this does not settle

§9's list is unchanged, and A15's point survives everything above: this wave assumed perception was
the constraint, and the most probable failure is still a system that sees fine, critiques plausibly,
and changes nothing. What was built here is the *cheap* half — the half that answers with numbers and
declines to guess. Whether anything acts on its output is not yet measured. The residue job is one
question per page and no session has yet been observed answering one.
