# A3 — Cloud/API vision models for web design review

**Read date: 2026-08-26.** Every price/limit below carries its vendor URL and the date the page was read.
Model lineup as of this date is **newer than the researcher's training cutoff (~May 2026)** — every model
name here was verified live, not recalled.

**Verdict up front:** the delta over Claude's own vision is **narrow and task-specific**, and it is *not*
where intuition puts it. Claude is **#1 on the benchmark closest to our task** (ScreenSpot-Pro UI grounding,
87.9%) and **#1 on OCR fidelity** (Roboflow 94.0/93.2). Its measured weakness is *generic multi-object
detection mAP* (54.4 vs Qwen3.8-Max 77.1) — a task web design review does not perform. The one genuine,
non-substitutable delta is **native full-resolution ingest**: OpenAI's `detail: "original"` is the only
cloud path that will read a 4K/Retina screenshot **without downscaling at all**. Everything else is
covered in-house or better served deterministically.

---

## 1. Capability matrix

Prices are **input** token prices; image cost is computed for **one 1920×1080 screenshot** so the column is
comparable. "Grounding" = can the model be asked for coordinates/boxes as a documented, supported feature.

| Provider · model | Spatial-reasoning evidence | Coordinate / bbox output? | Max res + downscale behaviour | Images/req | Cost per 1920×1080 shot | Multi-image compare |
|---|---|---|---|---|---|---|
| **Anthropic Claude Opus 5** (high-res tier) | **ScreenSpot-Pro #1 lineage: Opus 4.8 = 87.9%** (top of 17)¹; Roboflow detection 54.4 (rank ~9), **OCR 93.2**² | **Yes — first-class.** Dedicated `vision-coordinates` doc. **Absolute pixel** coords, points + boxes; `structured_outputs` schema for JSON³ | Long edge **2576 px**, budget **4784 visual tokens** (28×28 px patches). 1920×1080 **not resized**; 3840×2160 → 2576×1449⁴ | **100** (200k-ctx models) / 600; >20 images ⇒ per-image ≤2000 px⁴ | **2691 tok × $5/M = $0.0135**⁵ | Yes, joint analysis in one request; docs recommend `Image 1:` labels⁴ |
| **Anthropic Claude Sonnet 5** | same family; no separate ScreenSpot entry | same | same tier (4.7+)⁴ — *inferred for Sonnet 5, not stated by name* | same | 2691 × $2/M = **$0.0054**⁵ | same |
| **Anthropic Claude Haiku 4.5** (standard tier) | — | same API, lower accuracy | Long edge **1568 px**, **1568 tokens**. 1920×1080 → **1456×819**⁴ | same | 1560 × $1/M = **$0.0016**⁵ | same |
| **Anthropic Claude Fable 5** (frontier tier) | Roboflow **OCR 94.0 — #1 of 31**; overall 78.8 (#8); detection 56.4² | same | high-res tier | same | 2691 × $10/M = **$0.0269**⁵ | same |
| **Google Gemini 3.7 Flash** | Roboflow overall 84.6 (#2), **detection 69.4**, OCR 86.9²; recommended model for Google's Computer Use⁶ | **Yes — strongest declarative API.** `box_2d` = `[ymin,xmin,ymax,xmax]` **normalized 0–1000**, **plus segmentation masks** (polygon, 0–1000) + label, all in one call⁷ | Token-budgeted, not pixel-capped: `media_resolution` per **content item** — low 280 / medium 560 / **high 1120 (default, "optimal for most")** / **ultra_high 2240** tokens⁸ | **3,600** image files⁷ | high: 1120 × $0.75/M = **$0.00084**; ultra_high: **$0.00168**⁹ | Yes; per-image `media_resolution` lets you spend tokens on the diff image only⁸ |
| **Google Gemini 3.5 Flash** | Roboflow **overall #1 = 86.6%**; detection 68.7, OCR 91.1, reasoning 84.1² | same | same | same | high **$0.00168** / ultra_high **$0.00336** ($1.50/M)⁹ | same |
| **Google Gemini 3.1 Pro** | ScreenSpot-Pro **84.4% (#4)**¹; Roboflow overall 83.1, detection 67.4, OCR 92.6² | same | same | same | high $0.00224 / ultra_high $0.00448 ($2/M ≤200k ctx)¹⁰ | same |
| **Google Gemini 3.5 Flash-Lite** | budget tier; supports Computer Use⁶ | same | same | same | high **$0.000336** ($0.30/M)⁹ | same |
| **OpenAI GPT-5.6 Sol / Terra / Luna** | ScreenSpot-Pro: **GPT-5.4 = 85.4% (#2)**¹; Roboflow GPT-5.6 Sol overall 76.9, detection 68.2, OCR 90.7² | **Yes but weakest.** Own docs: model "struggles with tasks requiring precise spatial localization" and "precise coordinates"¹¹. Practitioner consensus: use detect-then-reason, not one-pass¹² | **32×32 patches × 1.2 multiplier.** `low` 512²; `high` 2048², 2500-patch cap; **`original` = 65,535×65,535 px, NO patch-budget limit** (5.6 only; 5.4/5.5 cap at 6000 px / 10,000 patches)¹¹ | **1,500**; 512 MB total payload¹¹ | high/original: 2040 patches ×1.2 = **2448 tok × $4/M = $0.0098** (Sol); Terra $2/M = **$0.0049**¹³ | Yes |
| **Alibaba Qwen3.8-Max** | **Roboflow detection #1 = 77.1%**, OCR 92.8, counting 82.4, overall 84.0 (#3)²; **ScreenSpot-Pro 84.5% (#3)**¹ | **Yes.** Qwen3-VL grounding emits **normalized 0–1000** coords (changed from absolute in Qwen2.5-VL)¹⁴ | Qwen3-VL family caps ~**1,310,720 px** (1280×32×32) recommended; 32× spatial compression¹⁴. 1920×1080 (2.07 MP) **is downscaled** | not published in sources read | ~1670 tok × $2/M ≈ **$0.0033** *(estimated — token count derived, not vendor-published)*¹⁵ | Yes (1M ctx, image+video in) |
| **Mistral OCR 4 / Document AI** | Document-domain only; no UI/spatial benchmark found | **Yes — paragraph-level bboxes + block-type labels + confidence scores**, 170 languages¹⁶ | Page-oriented; per-page resolution handling **not published** on the model card¹⁷ | page-based | **$4 / 1,000 pages** flat ($2 batch); **Document AI $5 / 1,000 annotated pages**¹⁶ˑ¹⁷ | n/a — not an image-pair comparator |
| **Moondream 3 (Moondream Cloud)** | Purpose-built grounded skills, not on ScreenSpot-Pro/Roboflow boards read | **Yes — dedicated endpoints**: `/detect`, `/point` (center coords), `/segment`, `/caption`, `/query`¹⁸ | not published in sources read | 1/req (skill endpoints) | $0.30/M in, $2.50/M out; **$5/mo free credits**¹⁸ | No native pair endpoint |
| **H Company Holo2** (UI specialist) | ScreenSpot-Pro **235B = 70.6%**, 30B = 66.1%, 8B = 58.9%¹ — i.e. **17 pts below Claude Opus 4.8** | Yes (GUI grounding native) | — | — | **No public API.** 4B/8B Apache-2.0; 30B/235B research-licence, commercial requires contacting H¹⁹ | — |
| **Microsoft OmniParser V2 / ByteDance UI-TARS** | Screen-parsing / GUI-agent OSS; UI-TARS-1.5 OSWorld 24.6@50²⁰ | Yes — OmniParser emits bboxes + semantic labels for interactable elements²⁰ | — | — | **Self-host only, no vendor API** | — |

**Superseded/absent from leaderboards:** Neither ScreenSpot-Pro (snapshot 2026-08-25) nor Roboflow Vision
Evals (updated 2026-08-20) has yet scored **Claude Opus 5**, **GPT-5.6 Sol**, or **Gemini 3.6/3.7** on
*both* boards — ScreenSpot-Pro's top entry is Opus **4.8**, not Opus 5. Treat cross-board rankings as
**one generation stale on the Anthropic and OpenAI rows.**

---

## 2. What published evaluations actually say about *spatial* work (not general VQA)

Two boards, and **they disagree, for a reason that decides this question.**

**ScreenSpot-Pro** — 1,581 expert instructions, 23 pro applications, 3 OSes, **full-screen high-resolution
professional UIs**, micro-average accuracy, localization only (no clicking/state/workflow)¹. This is the
benchmark whose *task shape is our task shape*: "given a natural-language description, find the element in
a big screenshot."

| Rank | Model | Score |
|---|---|---|
| 1 | **Claude Opus 4.8** | **87.9%** |
| 2 | GPT-5.4 | 85.4% |
| 3 | Qwen3.8 Max | 84.5% |
| 4 | Gemini 3.1 Pro | 84.4% |
| 5 | Meta Muse Spark | 84.1% |
| 6 | Claude Opus 4.6 | 83.1% |
| 9 | Gemini 3 Pro | 72.7% |
| 10 | Holo2-235B-A22B (UI specialist) | 70.6% |
| 17 | **Claude Opus 4.5** | **45.7%** |

**Roboflow Vision Evals** — 6 tasks, natural-image-heavy, detection scored as **mAP@50 over multiple
boxes**, all models at low reasoning effort, updated 2026-08-20²:

| Model | Overall | Detection | Counting | OCR | Extraction | Reasoning |
|---|---|---|---|---|---|---|
| Gemini 3.5 Flash | **86.6** | 68.7 | 81.1 | 91.1 | 94.8 | 84.1 |
| Gemini 3.7 Flash | 84.6 | 69.4 | 77.0 | 86.9 | 94.8 | 82.8 |
| Qwen3.8-Max | 84.0 | **77.1** | 82.4 | 92.8 | 87.6 | 73.5 |
| Gemini 3.1 Pro | 83.1 | 67.4 | 71.6 | 92.6 | 94.8 | 72.2 |
| **Claude Fable 5** | 78.8 | 56.4 | 63.5 | **94.0** | 92.8 | 66.2 |
| **Claude Opus 5** | 77.1 | **54.4** | 70.3 | 93.2 | 88.7 | 71.5 |
| GPT-5.6 Sol | 76.9 | 68.2 | 73.0 | 90.7 | 82.5 | 65.6 |

**Reconciling them — the load-bearing analysis.** Claude ranks ~#1 on one and ~#9 on the other because the
two measure *different capabilities that both get called "localization"*:

- **mAP@50 over many boxes** (Roboflow) rewards enumerating *every* instance with tight IoU. That is an
  object-detector's job. Claude is 23 points behind Qwen3.8-Max here, and this is real.
- **Single-target point-in-element on a dense professional UI** (ScreenSpot-Pro) rewards reading the
  interface semantically and hitting one target. Claude leads by 2.5 points.

Design review asks: *"is this button misaligned / is this text too small / does this element overlap"* —
**single-target, semantic, on a UI.** That is the ScreenSpot-Pro shape, not the mAP shape. **The benchmark
that flatters a cloud alternative is the one measuring a task we don't do.**

**The Opus 4.5 → 4.6 jump (45.7% → 83.1%, +37.4 pts)** is the largest single-generation move on that
board and coincides with Anthropic's high-resolution ingest work. It is strong evidence that **UI grounding
accuracy here is dominated by input resolution, not by model "spatial talent."** Buy pixels before you buy
a different vendor.

**Direct design-critique evidence is thin and negative for everyone.** The only 2026 paper found that
targets our exact task — *Learning to Detect UI Principle Violations via Reinforcement Learning*
(arXiv 2607.20690v2, 2026-08-04) — unified 19 principles (WCAG 2.2, dark patterns, cognitive/perceptual)
over ~10,000 generated Tailwind pages, 500-page held-out test set²¹. **Zero-shot VLM baseline: micro-F1
36%, precision 44%, recall 30%.** After GRPO RL training a 4.6B student: F1 **84%**, precision 94%.
Critically, the three principles that stayed broken after training — **Fitts's Law 36%, Miller's Law 54%,
Misdirection 55%** — are exactly the ones "requiring **relative spatial judgments**"²¹. The paper reports
no head-to-head frontier numbers, so **no published evaluation establishes that any frontier cloud model is
better than Claude at design critique specifically.** That gap is a blocker, named in §6.

**Counting is a documented failure mode across the board.** Roboflow's GPT-5.5 harness: **precise object
counting 30% (3/10 prompts)** against 78.9% spatial understanding²². Anthropic's own docs concede counting
"might not always be precisely accurate, especially with large numbers of small objects"⁴. Do not ask any
of these models "how many list items are misaligned" — ask "is this one misaligned," per element.

---

## 3. Hard image limits, and exactly how downscaling destroys design evidence

This is where the real differences live, and where Claude's docs are the most honest of the four.

**Claude — the resize rule is fully specified and it bites in a non-obvious place.** Claude sees images as
**28×28 px patches**; cost is `⌈w/28⌉ × ⌈h/28⌉` visual tokens. Two independent caps: an **edge limit** and a
**visual-token budget**, and Claude picks the largest aspect-preserving size satisfying both⁴ˑ³.

| Tier | Models | Max long edge | Max visual tokens | Effective megapixels |
|---|---|---|---|---|
| High-resolution | **Claude 4.7 and later** (incl. Opus 5, Fable 5) | 2576 px | 4784 | 4784 × 784 px = **3.75 MP** |
| Standard | all others (incl. Haiku 4.5) | 1568 px | 1568 | 1568 × 784 px = **1.23 MP** |

Consequences that matter for design evidence, from the vendor's own table⁴:

- **1920×1080 (a 1× desktop viewport) survives untouched on the high-res tier** (2691 tokens < 4784) and is
  **crushed to 1456×819 on the standard tier** — a 24% linear reduction. 11px caption text becomes 8.3px.
- **3840×2160 (a 2× Retina capture of that same viewport) is downscaled even on the high-res tier**, to
  2576×1449. **You lose 55% of the pixels you paid the browser to render.** For a design review whose whole
  point is hairline borders, 1px misalignments and 10–12px labels, this is the single biggest fidelity
  decision in the pipeline — bigger than model choice.
- **The token cap fires before the edge cap, and that is the classic silent bug.** Anthropic's own example:
  an A4 scan at 1075×1520 has *both* sides under 1568 px, but costs 39×55 = **2145 tokens > 1568**, so it is
  resized to **924×1307**³. Any coordinate computed against the original is then wrong by ~14%.
- Claude then **pads to the next multiple of 28 on bottom and right**. Normalizing against padded
  dimensions (924×1316) instead of resized (924×1307) skews every coordinate³.
- **Mitigation Anthropic ships and nobody else does:** `transformations: {"oversized_image": "error"}` on
  an image block turns a silent server-side resize into a **400 with the exact target dimensions**³. That
  converts "our design review quietly got worse when someone changed the capture size" from an undetectable
  regression into a build failure. This is a genuinely important safety rail for a design-review pipeline.
- **PDF pages are rasterized server-side at dimensions you don't control**, so returned coordinates
  "can't be reliably mapped back onto the page" — rasterize yourself³.
- **`tool_result` images are NOT auto-downscaled** — an oversized screenshot returned to the computer-use
  or browser-use toolset is **rejected**, not shrunk⁴.

**OpenAI — the only true full-resolution path.** `detail: "original"` on GPT-5.6 Sol/Terra/Luna accepts
**65,535 × 65,535 px with *no patch-budget limit***¹¹. GPT-5.5/5.4 cap `original` at 6000 px / 10,000
patches; GPT-5.2 and 4.1-mini have no `original` at all. OpenAI's own guidance names the use case:
`original` is for "tasks that require fine visual detail or precise coordinates, such as OCR, small-object
detection, or computer use"¹¹. **This is the one hard capability no other vendor in this matrix offers.**
A 3840×2160 Retina capture at `original` = 120×68 = 8160 patches × 1.2 = **9792 tokens ≈ $0.039 on Sol** —
and it is read at native resolution, versus Claude's 2576×1449 for $0.024. Note the irony: `low` "does not
always use fewer tokens than `high`"¹¹, so do not reach for it as a cost lever.

**Google — budget-based, and per-image, which is a real ergonomic win.** Gemini 3 has no published pixel
ceiling; it has a **token allocation per media item**: low 280 / medium 560 / high 1120 (default) /
**ultra_high 2240** — and setting resolution *per content item* is "exclusive to Gemini 3 models"⁸. So a
before/after pair can send the "after" at ultra_high and the "before" at low. `ultra_high` is documented as
"required for specific use cases such as computer use"⁸. **Google does not publish a pixel equivalent for
any level**⁸ — you cannot compute, from the docs, what fidelity your screenshot actually reaches. For a
pipeline whose correctness depends on 1px evidence, that is a documentation gap, not a feature.

**Alibaba — smallest ceiling of the majors.** Qwen3-VL's recommended max is **1,310,720 px (1280×32×32)**
with 32× spatial compression¹⁴ — **below a 1080p viewport (2.07 MP)**. The model that tops generic
detection mAP is the one that sees a desktop screenshot at ~63% of its pixels.

---

## 4. Is there a cloud API purpose-built for UI/screenshot understanding or design critique?

**Effectively no — the specialists are open weights, not services.**

| Candidate | Status | Why it doesn't close the gap |
|---|---|---|
| **H Company Holo2** | 4B/8B Apache-2.0; **30B/235B research-licence, commercial by contacting H**; no public API/pricing found¹⁹ | Its flagship 235B scores **70.6% ScreenSpot-Pro — 17.3 pts *below* Claude Opus 4.8**¹. A purpose-built UI model that loses to the general model. |
| **Microsoft OmniParser V2** | OSS, self-host²⁰ | Screen-*parser*, not critic: emits bboxes + semantic labels for interactable elements to feed a general VLM. Its output is a worse version of what the DOM already gives you on the web. |
| **ByteDance UI-TARS / UI-TARS-1.5** | OSS + desktop app²⁰ | GUI **agent** (act on screens), not design critic. Optimized for OSWorld/AndroidWorld task completion. |
| **Moondream 3 (Moondream Cloud)** | **Real hosted API**, $0.30/$2.50 per M, $5/mo free¹⁸ | The closest genuine analogue to Mistral-OCR-as-specialist: dedicated `/point`, `/detect`, `/segment` endpoints returning grounded output. But it is a *grounding* specialist, not a *design* specialist — and grounding is the axis the DOM already solves for web (§5). |
| **Mistral OCR 4 / Document AI** | Hosted, $4–5/1,000 pages, **paragraph bboxes + block types + confidence**¹⁶ˑ¹⁷ | Genuinely excellent at its job, and its job is **documents**, not rendered UI. Nothing in the model card claims screenshot/UI handling¹⁷. |
| **Applitools Eyes / Percy / Visual Regression Tracker** | Hosted commercial visual-QA platforms²³ | These are **diff-noise-filtering** products, not design critics. They answer "did this change" not "is this good." They belong in the deterministic layer, not the model layer. |
| **Gemini Computer Use** (`gemini-3.7-flash`) | Hosted, documented⁶ | Nearest thing to a UI-native cloud API. Emits **normalized 0–999 coordinates regardless of input dimensions**, recommended screen **1440×900**⁶. But it is an *actuation* model — its output is `click(x,y)`, not a critique. |

**Conclusion: the "specialist cloud API for design review" the Mistral-OCR analogy imagines does not
exist in August 2026.** The category is served by general VLMs plus deterministic tooling.

---

## 5. Adversarial pass — the strongest case that **no external cloud vision call is worth adding**

Steelmanning the null result, as instructed. Three findings from the adversarial pass materially weakened
the case for a cloud call, and one strengthened it.

**A. For web UI, localization is not a vision problem — it is a DOM problem, and Claude's own toolset
already exposes it.** The `browser_toolset_20260801` `read_page`/`find` members return **the accessibility
tree as text with every element tagged by reference** (`link "Pricing" [ref_5]`), and Claude acts on
`{"type":"ref","ref":"ref_2"}` targets²⁴. Anthropic's own guidance: *"Prefer references where the page has
a usable accessibility tree. A reference survives layout shifts and reflows that make pixel coordinates
fragile."*²⁴ Coordinates are the **fallback** for canvas, video, remote-desktop and cross-origin iframes²⁴.

> **This is the argument that most damages the cloud-grounding thesis.** Buying Gemini's `box_2d` or
> Qwen's 77.1 mAP purchases a *statistical estimate* of where an element is, when for a rendered web page
> `getBoundingClientRect()` and `getComputedStyle()` return the **exact, ground-truth** answer — position,
> size, font-size, line-height, color, z-index, overflow — for free, at zero latency, with zero
> hallucination risk. A model that is 77% right about a box is strictly worse than a browser that is 100%
> right about it.

**B. The same toolset already solves the small-text problem without a second vendor.** The `zoom` member
returns "a cropped, upscaled image of `region` … **for closer inspection of small text or controls**," and
"coordinates Claude emits after seeing the zoomed image are still full-viewport pixels"²⁴. Crop-and-zoom is
also what Anthropic's coordinates guide prescribes for fine targets³. **Downscaling destroys fine design
evidence only if you send the whole page in one frame.** Sending 6 crops at native resolution beats sending
one 4K frame to *any* model — and it is cheaper than the frontier call it replaces.

**C. Deterministic tooling outperforms every model on the checks that actually gate a release.** axe-core
computes contrast against computed backgrounds with **zero false positives** on the free extension²⁵;
Playwright `toHaveScreenshot()` gives pixel-exact regression²²; a certified contrast checker — not a
model's estimate — is the required arbiter for WCAG 2.2 AA 4.5:1²². The honest limit on the deterministic
side: automated tests catch only **20–30% of WCAG criteria**, and axe returns "needs review" rather than a
verdict when the background is a gradient or photograph²⁵. **That 70–80% residue is the only place a model
earns its keep — and it is judgment work (hierarchy, rhythm, density, taste), which is exactly where no
benchmark shows a cloud model beating Claude.**

**D. The documented blind spots are shared by every model in the matrix, so switching vendors cannot fix
them.** A screenshot cannot show hover/focus/active/disabled states, motion, below-fold content, alternate
data states, or another browser engine's rendering²². These are **capture-pipeline** problems. Spending
money on a second vendor to solve a capture problem is a category error.

**E. Non-capability costs a matrix hides.** A second vendor means a second data-processing surface for
screenshots that may contain customer data; a second key, quota and rate-limit ladder; a second failure
mode in the review path; and coordinate-frame skew between two different resize rules (Claude's 28-px
patch/pad math³ vs Gemini's 0–1000 normalization⁷ vs Qwen's 0–1000 over a 1.31 MP downscale¹⁴) — three
coordinate spaces to reconcile, each with its own silent-drift bug.

**Where the adversarial pass FAILED to kill the cloud call — the one surviving delta.** Point B assumes
you can always crop. You cannot when the design question is **global**: "is the vertical rhythm consistent
down this whole page," "does the eye land in the right place," "is this 4K marketing hero pixel-sharp." For
those, the frame must be whole *and* native, and **Claude's 3.75 MP ceiling downscales a Retina capture by
55%**⁴ while **GPT-5.6 `detail:"original"` does not downscale at all**¹¹. That is a real, documented,
non-substitutable capability difference — and it is the only one in this report.

---

## 6. Decision — when to call out to a non-Claude cloud model, and for what

**Default: don't.** Claude's own vision is the primary, and the pipeline's marginal dollar goes to
**capture fidelity and crop strategy**, not to a second vendor. Four ranked levers, cheapest first:

1. **Pin the resolution tier and make drift fail loudly.** Use a 4.7+/Opus 5 model (high-res tier) and set
   `transformations: {"oversized_image": "error"}` on every screenshot block³. Free, and it converts the
   #1 silent design-review regression (capture size changed → everything downscaled → coordinates and
   small-text judgments quietly degrade) into a 400 that names the exact target size.
2. **Take localization out of the model entirely.** For rendered web pages, use the browser-use
   accessibility tree + element refs²⁴, and `getBoundingClientRect`/`getComputedStyle` for geometry and
   type metrics. Ground truth beats a 54–77 mAP estimate from anyone.
3. **Crop and `zoom` instead of downscaling.** Per-region native-resolution crops preserve exactly the
   1px/10px evidence that a whole-page 4K frame loses on every provider except OpenAI `original`³ˑ²⁴.
4. **Run the deterministic gate first** (axe-core contrast, Playwright pixel-diff), and spend the model
   only on the 70–80% residue that rules cannot express²²ˑ²⁵.

Then, and only then, three narrow cases where an external call earns itself:

| Call out when… | Use | Why this one, and the cost |
|---|---|---|
| **The frame must be whole AND native-resolution** — full-page rhythm on a 2×/4K capture, marketing hero sharpness, anything where cropping destroys the question | **OpenAI GPT-5.6 Sol/Terra, `detail: "original"`** | The **only** documented no-downscale path (65,535² px, no patch cap)¹¹; Claude's high-res tier still cuts 3840×2160 to 2576×1449⁴. **~$0.039/4K image (Sol) / ~$0.020 (Terra)**¹³. This is the strongest-evidenced delta in the report. |
| **You need machine-consumable geometry on a surface with NO accessibility tree** — canvas/WebGL charts, embedded video, PDF-rendered design comps, a competitor's screenshot with no DOM | **Gemini 3.5/3.7 Flash** (`box_2d` 0–1000 + **segmentation masks**, per-item `media_resolution: ultra_high`)⁷ˑ⁸ | Only vendor shipping boxes **and masks** as a declared output contract⁷; Roboflow detection 68.7–69.4 vs Claude 54.4²; **$0.0017/shot at ultra_high — 8× cheaper than the Opus 5 call it replaces**⁹. Fall back to **Moondream `/point`** ($0.30/M, $5/mo free)¹⁸ if you want a narrow single-purpose specialist in the Mistral-OCR mould. |
| **High-volume batch triage** — thousands of screenshots/build where you need a cheap pre-filter before spending an Opus 5 judgment call | **Gemini 3.5 Flash-Lite** (~$0.00034/shot)⁹ or **Claude Haiku 4.5** ($0.0016/shot, standard tier)⁵ | Pure economics, no capability claim. Haiku keeps you single-vendor at 4.7× the price; Flash-Lite is the floor. |

**Explicitly ruled out, with reasons:**

- **Qwen3.8-Max** — tops generic detection mAP (77.1)² and is respectable on ScreenSpot-Pro (84.5)¹, but its
  **~1.31 MP ceiling is below a 1080p viewport**¹⁴. It downscales the exact evidence we care about. The
  strength is on a task we don't perform; the weakness is on the input we always send.
- **Mistral's line** — OCR 4 / Document AI are excellent and cheap ($4–5/1,000 pages, real bboxes)¹⁶,
  but they are **document** models. The operator's analogy is sound *as an analogy* and wrong *as a
  destination*: Mistral OCR is the right shape of thing, but nothing in Mistral's UI-facing catalogue does
  this job, and Claude already **leads OCR outright** (Fable 5 94.0, Opus 5 93.2 — ranks 1 and 2 of 31)².
- **Holo2 / OmniParser / UI-TARS** — the UI specialists have no commercial API¹⁹ˑ²⁰ and Holo2's flagship
  loses to Claude Opus 4.8 by 17.3 pts on the UI-grounding benchmark it was built for¹.
- **A second vendor purely for "better spatial reasoning"** — refuted. The benchmark closest to our task
  puts Claude first¹.

**If exactly one external call is added, add OpenAI `detail:"original"`, for full-frame native-resolution
reads only.** It is the only line in this matrix that buys a capability Claude does not have, rather than a
number on a benchmark measuring something else.

---

## 7. Blockers and uncertainties — stated, not smoothed

1. **Both leaderboards are one generation stale on the rows that matter.** ScreenSpot-Pro's top entry is
   **Claude Opus 4.8**, not Opus 5; it lists **GPT-5.4**, not 5.6; **Gemini 3.1 Pro**, not 3.5/3.6/3.7¹.
   Roboflow has Opus 5 and GPT-5.6 Sol but is natural-image-weighted². **No board scores the current
   lineup on the current UI task.** The ranking could move.
2. **No published head-to-head on design *critique*.** The one on-task 2026 paper (arXiv 2607.20690v2)
   reports a **36% zero-shot micro-F1** baseline and explicitly declines to give frontier-model numbers²¹.
   Every claim in §6 about which model *critiques* better is therefore an inference from grounding + OCR +
   reasoning proxies, not a measurement. **This is the biggest gap in this report** and the obvious
   candidate for an internal eval on our own screenshots.
3. **Latency is not credibly answerable from primary sources today.** Every vision-latency table found was
   still quoting **Gemini 2.5 Flash / Claude Haiku 3.5**²⁶ — a lineup two-plus generations retired.
   Artificial Analysis has intelligence rankings for the current models (Opus 5 = 63, GPT-5.6 Sol max = 61)
   but no vision-specific TTFT for them²⁷. **Do not quote a latency number for this decision; measure it.**
   Directionally only: Flash-class < Opus/Sol-class, and `ultra_high`/`original` cost latency by
   construction⁸ˑ¹¹.
4. **Gemini publishes no pixel equivalent for any `media_resolution` level**⁸ — so its true fidelity on a
   1920×1080 screenshot is **unknown from the docs**. The $0.0017 figure is a real price for an
   unspecified amount of resolution.
5. **The Qwen cost figure is derived, not vendor-published** — token count computed from the documented
   1.31 MP cap and 28×28 patching¹⁴ˑ¹⁵, priced at the Singapore endpoint. Beijing runs 60–70% cheaper¹⁵.
6. **Sonnet 5's resolution tier is inferred.** Anthropic's table says "Claude 4.7 and later models"⁴ and
   never names Sonnet 5. Verify with `transformations:{"oversized_image":"error"}` on a 1920×1080 image
   before relying on it — a 400 means standard tier, a 200 means high-res.
7. **Third-party leaderboards ≠ vendor claims ≠ our workload.** Roboflow runs all models at *low reasoning
   effort*², which systematically penalizes reasoning-heavy models on exactly the reasoning column.

---

## Sources

1. ScreenSpot-Pro leaderboard, snapshot **2026-08-25**, 17 models, 1,581 grounding instructions, micro-average accuracy — <https://benchlm.ai/benchmarks/screenspot-pro> (read 2026-08-26). Benchmark origin: <https://arxiv.org/pdf/2501.12326>, <https://gui-agent.github.io/grounding-leaderboard/>
2. Roboflow Vision Evals, updated **2026-08-20**, 31 models / 6 tasks, pricing updated 2026-08-26 — <https://playground.roboflow.com/evals> (read 2026-08-26)
3. Anthropic, *Coordinates and bounding boxes* — <https://platform.claude.com/docs/en/build-with-claude/vision-coordinates> (read 2026-08-26)
4. Anthropic, *Vision* (limits, tiers, resize table, Limitations) — <https://platform.claude.com/docs/en/build-with-claude/vision> (read 2026-08-26)
5. Anthropic pricing: Fable 5 / Mythos 5 $10 in · Opus 5 & 4.5–4.8 $5 · Sonnet 5 $2 · Sonnet 4.5/4.6 $3 · Haiku 4.5 $1 per MTok — <https://platform.claude.com/docs/en/about-claude/pricing> (read 2026-08-26). Image token counts from source 4; cost = tokens × rate.
6. Google, *Computer use* (gemini-3.7-flash recommended; normalized 0–999 coords; 1440×900) — <https://ai.google.dev/gemini-api/docs/computer-use> (read 2026-08-26)
7. Google, *Image understanding* (`box_2d` [ymin,xmin,ymax,xmax] 0–1000, segmentation masks, 3,600 images/req, 768×768 tiles @258 tok) — <https://ai.google.dev/gemini-api/docs/image-understanding> (read 2026-08-26)
8. Google, *Media resolution* (low 280 / medium 560 / high 1120 default / ultra_high 2240 tokens; per-item exclusive to Gemini 3) — <https://ai.google.dev/gemini-api/docs/media-resolution> (read 2026-08-26)
9. Google Gemini Developer API pricing, page last updated **2026-08-13**: 3.7 Flash & 3.6 Flash $0.75/$3.75 (to 2026-12-31, then $1.50/$7.50) · 3.5 Flash $1.50/$9.00 · 3.5 Flash-Lite $0.30/$2.50; Batch 50% — <https://ai.google.dev/gemini-api/docs/pricing> (read 2026-08-26)
10. Gemini 3 Pro context-tiered pricing $2/$12 ≤200k, $4/$18 above — secondary sources, 2026-08 (<https://apidog.com/blog/gemini-3-0-api-cost/>); **not confirmed on a Google primary page in this pass**
11. OpenAI, *Images and vision* (`detail` low/high/original/auto; 32×32 patches × 1.2; GPT-5.6 `original` = 65,535² px no patch cap; 1,500 images; 512 MB; "struggles with tasks requiring precise spatial localization") — <https://developers.openai.com/api/docs/guides/images-vision> (read 2026-08-26)
12. OpenAI Cookbook, *Getting the most out of GPT-5.4 for vision and document understanding* (detect-then-reason, strict coordinate contract) — <https://developers.openai.com/cookbook/examples/multimodal/document_and_multimodal_understanding_tips> (read via search 2026-08-26)
13. OpenAI pricing Aug 2026: GPT-5.6 Sol $4/$20 · 5.6 Terra $2/$12 · 5.5 $5/$30 · 5.4 $2.50/$15 — <https://www.aipricing.guru/openai-pricing/>, <https://www.morphllm.com/openai-api-pricing> (read 2026-08-26). **Secondary sources; not confirmed on OpenAI's own pricing page in this pass.**
14. Qwen3-VL grounding (normalized 0–1000; ~1,310,720 px = 1280×32×32 recommended max; 32× spatial compression) — <https://deepwiki.com/QwenLM/Qwen3-VL/5.2-spatial-understanding-and-2d-grounding>, <https://mintlify.wiki/QwenLM/Qwen3-VL/inference/pixel-control> (read 2026-08-26)
15. Qwen3.8-Max $2/$6 per M, $0.25 cached, 1M ctx, text+image+video in; Singapore endpoint, Beijing 60–70% cheaper; standard API access from 2026-08-03 — <https://openrouter.ai/qwen/qwen3.8-max>, <https://www.eesel.ai/blog/qwen-pricing> (read 2026-08-26)
16. Mistral OCR 4 announcement (released 2026-06-23; bounding boxes, block types, confidence scores, 170 languages; $4/1,000 pages, $2 batch) — <https://mistral.ai/news/ocr-4/> (read via search 2026-08-26)
17. Mistral OCR 4.0 model card ($4/1,000 pages, $5/1,000 annotated pages; paragraph-level bbox + structural block labels) — <https://docs.mistral.ai/models/model-cards/ocr-4-0> (read 2026-08-26)
18. Moondream 3 / Moondream Cloud (`/query`, `/detect`, `/point`, `/caption`, `/segment`; $0.30/M in, $2.50/M out, $5/mo free credits) — <https://docs.moondream.ai/api/>, <https://moondream.ai/blog/moondream-3-preview> (read via search 2026-08-26)
19. H Company Holo2 (4B/8B Apache-2.0; 30B-A3B & 235B-A22B research-only, commercial by contact; 235B = 70.6% ScreenSpot-Pro single-step, 78.5% @3 steps) — <https://hcompany.ai/holo2>, <https://huggingface.co/blog/Hcompany/introducing-holo2-235b-a22b> (read via search 2026-08-26)
20. Microsoft OmniParser V2 (Feb 2025) — <https://github.com/microsoft/omniparser>; ByteDance UI-TARS / UI-TARS-1.5 — <https://arxiv.org/pdf/2501.12326> (read via search 2026-08-26)
21. *Learning to Detect UI Principle Violations via Reinforcement Learning*, arXiv **2607.20690v2, 2026-08-04** (19 principles; ~10k Tailwind pages; 500-page test set; zero-shot F1 36%/P 44%/R 30% → post-RL F1 84%/P 94%; Fitts's Law 36%, Miller's Law 54%, Misdirection 55%) — <https://arxiv.org/html/2607.20690v2> (read 2026-08-26)
22. *Screenshot-Driven UI Development With Vision Models* (Roboflow GPT-5.5 harness: overall 76.1%, spatial 78.9% (15/19), **counting 30% (3/10)**; documented blind spots: hover/focus/active/disabled, motion, below-fold, one data state, one engine; WCAG 2.2 AA 4.5:1 via certified checker not model estimate) — <https://www.digitalapplied.com/blog/screenshot-driven-ui-development-vision-models-2026> (read 2026-08-26). **Third-party harness, one vendor — directional only; the article itself says "treat the 30% as a caution sign rather than a measurement."**
23. Applitools Eyes / Percy / Visual Regression Tracker — <https://percy.io/blog/visual-qa-testing>, <https://bug0.com/knowledge-base/visual-regression-testing-tools> (read via search 2026-08-26)
24. Anthropic, *Browser use tool* (accessibility tree with `[ref_N]`; `{"type":"ref"}` vs `{"type":"coordinate"}` targets; "a reference survives layout shifts and reflows that make pixel coordinates fragile"; `zoom` region crop-upscale "for closer inspection of small text or controls"; toolset images are **rejected not downscaled**) — <https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-tool> (read 2026-08-26)
25. axe-core coverage and limits (zero false positives on the free extension; "needs review" on gradient/photo backgrounds; automated tests catch 20–30% of WCAG criteria) — <https://access-proof.com/blog/what-is-axe-core-evidence-based-audits>, <https://web-accessibility-checker.com/en/blog/color-contrast-wcag-guide> (read via search 2026-08-26)
26. LLM API latency benchmarks 2026 — <https://www.edenai.co/post/llm-api-latency-benchmarks-speed-comparison-across-providers>, <https://www.kunalganglani.com/blog/llm-api-latency-benchmarks-2026> (read 2026-08-26). **Stale lineup (Gemini 2.5 Flash, Claude Haiku 3.5) — cited only to document that no current vision-latency table was found.**
27. Artificial Analysis leaderboards (Claude Opus 5 Intelligence Index 63; GPT-5.6 Sol max 61) — <https://artificialanalysis.ai/leaderboards/models> (read via search 2026-08-26)
