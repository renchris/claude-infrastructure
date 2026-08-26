# A5 — CV primitives as a measurement layer beneath a web design-review agent

**Question.** Which computer-vision primitives — learned (open-vocabulary detection, segmentation,
pointing, dense features) and classical — are worth running locally on an M1 Max (64 GB unified,
32-core GPU, macOS, torch+MPS) as the *measurement* layer under a design-review agent?

**The target transformation.** Turn "the spacing looks uneven" into "these four cards have gaps of
16, 16, 16 and 23 px." Everything below is judged on whether it produces a **number with units**,
not a description.

**Date of research: 2026-08-26.** Every model name and version was re-checked against the live web;
the author's priors were treated as provisional and several were wrong (see §0).

---

## 0. Corrections to priors (things that changed since ~May 2026)

| Prior | Actual, as of 2026-08-26 | Source |
|---|---|---|
| "SAM 2 is current; SAM 3 may not exist" | **SAM 3 shipped Nov 2025**; **SAM 3.1** shipped **2026-03-27** as a drop-in replacement. SAM 3 adds *Promptable Concept Segmentation* — a text or exemplar prompt returns **every** instance of a concept, not one mask per prompt. | [ai.meta.com/blog/segment-anything-model-3](https://ai.meta.com/blog/segment-anything-model-3/) · [ai.meta.com SAM3 paper](https://ai.meta.com/research/publications/sam-3-segment-anything-with-concepts/) |
| "DINOv2 is the dense-feature backbone" | **DINOv3** (Aug 2025), 1.7 B curated images, up to 7 B params, distilled ViT-S/B/L + ConvNeXt variants, **commercial licence**, explicitly optimised for *dense* features via Gram anchoring. | [ai.meta.com/blog/dinov3-self-supervised-vision-model](https://ai.meta.com/blog/dinov3-self-supervised-vision-model/) · [arxiv 2508.10104](https://arxiv.org/pdf/2508.10104) |
| "Molmo points, roughly" | **MolmoPoint** (2026) adds grounding tokens; **MolmoPoint-GUI-8B = 61.1 on ScreenSpot-Pro, 70.0 on OSWorld-G** — SOTA among fully open models, and trained partly on **HTML-rendered screenshots with auto-extracted bounding boxes**. | [allenai.org/blog/molmopoint](https://allenai.org/blog/molmopoint) · [arxiv 2603.28069](https://arxiv.org/html/2603.28069v1) |
| "Grounding DINO 1.6 is open" | Grounding DINO **1.5/1.6 Pro are API-only** (IDEA Research / DeepDataSpace). Only the original **Grounding DINO (Swin-T/Swin-B, 2023)** and **Grounding DINO 1.5 Edge** distillations are locally runnable; 1.5 Pro is a hosted endpoint. | [arxiv 2405.10300](https://arxiv.org/pdf/2405.10300) |

---

## 1. Learned primitives — what actually runs on an M1 Max, by what route

### 1.1 The Apple-Silicon routing rule

There are four routes, and which one a model takes is the single biggest determinant of whether it
is usable:

1. **PyTorch + MPS** — works for pure-PyTorch models with no custom CUDA/Triton kernels. Slower than
   an NVIDIA card but fine for a per-screenshot batch of one.
2. **HuggingFace `transformers` reimplementation** — the escape hatch when the *official* repo has a
   CUDA-only dependency. This is how SAM 3 becomes runnable at all on this machine (below).
3. **MLX / `mlx-vlm`** — Apple's own array framework. Native Metal, unified-memory friendly.
   `mlx-vlm` supports Qwen2-VL, LLaVA, Idefics, **Molmo**, PaliGemma, **Florence-2**, and OCR
   specialists. ([github.com/Blaizzy/mlx-vlm](https://github.com/Blaizzy/mlx-vlm))
4. **Core ML / ONNX Runtime (CoreMLExecutionProvider)** — best latency for the small fixed-shape
   models (a YOLO detector, a CLIP image tower), worst ergonomics.

**The trap to know about before you start.** SAM 3's official `facebookresearch/sam3` has a **hard
dependency on Triton** — CUDA-only, no Metal backend — for its Euclidean distance-transform step,
so the official checkpoint path is **dead on Apple Silicon**. The working route is the HF
`transformers` implementation from main, which avoids Triton entirely; a `.pin_memory()` call in the
video processor also has to be removed for MPS video inference.
([huggingface.co/facebook/sam3/discussions/11](https://huggingface.co/facebook/sam3/discussions/11))
SAM 2 has its own long-running MPS complaints (`Placeholder storage has not been allocated on MPS
device`) — [facebookresearch/sam2#687](https://github.com/facebookresearch/sam2/issues/687),
[#34](https://github.com/facebookresearch/sam2/issues/34) — and Ultralytics' SAM 3 wrapper still
fails on MPS for the same `pin_memory()` reason
([ultralytics#22954](https://github.com/ultralytics/ultralytics/issues/22954)).
**Generalisable lesson: "open weights" is not "runs here." Check the kernel dependencies, not the
licence.**

### 1.2 Per-model verdict

| Model | Status 2026-08 | Route on M1 Max | Rough 1440p latency | Licence | Verdict for design review |
|---|---|---|---|---|---|
| **Grounding DINO** (Swin-T 172 M / Swin-B) | 2023 weights still the only *open* ones | PyTorch+MPS, or HF `transformers` | ~1.5–4 s/image (est., MPS, fp32) | Apache-2.0 | **Marginal.** Text-conditioned boxes, but on natural-image priors — see §2 |
| **Grounding DINO 1.5 Pro / 1.6 Pro** | **API-only** (IDEA / DeepDataSpace); 1.5 Pro = 54.3 AP COCO, 55.7 AP LVIS-minival ([arxiv 2405.10300](https://arxiv.org/pdf/2405.10300)) | none — hosted | n/a | proprietary | **Excluded** — not a local measurement layer |
| **SAM 3 / SAM 3.1** | SAM 3 Nov 2025; **SAM 3.1 2026-03-27** ([ai.meta.com](https://ai.meta.com/blog/segment-anything-model-3/)) | **HF `transformers` only** (Triton blocks the official repo) | seconds/image; SAM ViT-B embedding measured at **1.9 s on M2 Ultra**, ~45 ms/mask thereafter ([geo-ai](https://geo-ai.medium.com/segment-anything-model-sam-on-apple-silicon-m1-and-m2-5cdb3f781b27)) — expect **3–5 s** on a 32-core M1 Max | SAM licence (permissive, check 3.1 terms) | **Interesting but not a measurement tool.** Masks are *pixel-accurate to the rendered edge*, which is exactly what you want; but SAM is **not semantic** and will happily segment a gradient |
| **SAM 2** | superseded | PyTorch+MPS, buggy | — | Apache-2.0 | Skip — SAM 3 supersedes and its video tracking is irrelevant to a static screenshot |
| **Florence-2** (0.23 B base / 0.77 B large) | still current; **no Florence-3** found as of 2026-08-26 | **MLX via `mlx-vlm`** — first-class support | sub-second to ~2 s | **MIT** | **Yes, as a captioner/region-proposer.** MIT + tiny + runs in MLX is a rare combination. It is the captioner half of OmniParser V2 |
| **OWLv2 / OWL-ViT** | current | HF `transformers` + MPS | ~1–3 s (est.) | Apache-2.0 | Weak on UI; its value is *open-vocabulary recall*, not localisation precision |
| **MolmoPoint-GUI-8B** | **2026**, SOTA open: **61.1 ScreenSpot-Pro, 70.0 OSWorld-G** ([allenai](https://allenai.org/blog/molmopoint)) | Molmo family is in `mlx-vlm`; 8 B at 4–8 bit fits 64 GB trivially | several seconds/query (autoregressive) | Apache-2.0 (Ai2) | **Yes — but as a *pointer*, not a measurer.** It returns a point, not a box with subpixel edges. Crucially it was **trained on HTML-rendered screenshots with auto-extracted boxes**, so it is one of the few models with *no* domain gap |
| **DINOv2 / DINOv3** | **DINOv3** Aug 2025, ViT-S/B/L/H+ distillations + ConvNeXt ([ai.meta.com](https://ai.meta.com/blog/dinov3-self-supervised-vision-model/)) | PyTorch+MPS; ViT-S/B are fast | ViT-S ~200–400 ms (est.) | DINOv3 commercial licence | **Yes, for *similarity*, not geometry.** Patch-token cosine similarity answers "are these six cards visually the same component?" without any labels |
| **YOLO-World → YOLOE** | **YOLOE** (Real-Time Seeing Anything) supersedes: +3.5 AP over YOLO-Worldv2 on LVIS, 1.4× faster, re-parameterises to zero extra cost ([ultralytics](https://docs.ultralytics.com/models/yoloe)) | Ultralytics + MPS, or CoreML export | tens of ms | **AGPL-3.0** ⚠️ | **Licence is the blocker**, not capability. AGPL contaminates a hosted review agent unless you buy the Ultralytics commercial licence |
| **CLIP / OpenCLIP** | mature | MLX or PyTorch+MPS; image tower exports cleanly to Core ML | ~20–80 ms/crop | MIT | **Yes, as a cheap classifier over crops** — "is this crop a button / an avatar / a logo?" via zero-shot text prompts. Also the retrieval index for "find me every instance of this component" |
| **OmniParser V2** (YOLOv8 icon detector + Florence-2 captioner) | **39.5–39.6 ScreenSpot-Pro**, 60 % lower latency than V1; a **YOLOv9-E** region detector was added **July 2026** ([microsoft/OmniParser](https://github.com/microsoft/omniparser)) | Ultralytics + MPS for the detector; MLX for Florence-2 | ~0.5–1.5 s | detector AGPL-adjacent; check per-component | **The most directly relevant learned system** — it is the only one on this list *trained on screenshots* |

**Reading the table.** The learned models split cleanly into two jobs, and neither job is
measurement:

- **Naming things** — Florence-2, CLIP, MolmoPoint, OmniParser. "That region is a primary button."
- **Grouping things** — DINOv3 patch similarity, CLIP embeddings. "These six regions are the same
  component repeated."

Not one of them returns "23 px". Every pixel number in the target sentence comes from §3.

---

## 2. The domain gap — stated plainly, with numbers

**Verdict: the gap is real, it is large, and it is measured. Do not assume transfer.**

Four independent measurements, from four different research communities, all point the same way.

### 2.1 Rendered UI is a different visual distribution, structurally

The GUI-detection literature states the difference as a property of the data, not a training
accident: *"GUI element detection is a domain-specific case of object detection, in which objects
overlap more often, and are located very close to each other, plus the number of object classes is
considerably lower, yet there are more objects in the images compared to natural images. Studies
that have been carried out on comparing various object detection models might not apply to GUI
element detection."* ([arxiv 2408.03507](https://arxiv.org/pdf/2408.03507))

Concretely, a screenshot violates almost every prior a COCO-trained detector encodes:

| Natural-image prior | What a rendered UI does |
|---|---|
| Objects have texture, shading, occlusion boundaries | Flat fills, hard 1-px anti-aliased edges, zero texture |
| Objects rarely tile identically | The *same component repeats* 6× with pixel-identical rendering |
| Object scale/aspect follows a smooth distribution | Scales snap to a design system's 4/8-px grid |
| Background is scene, not signal | **Whitespace IS the content** being reviewed |
| Text is incidental | Text is 60–80 % of the pixels that matter |

### 2.2 The hardest number: even the *best* learned detector cannot hit pixel accuracy

The largest empirical study of GUI element detection (7 methods, >50 k GUI images, ESEC/FSE '20)
found deep learning beats old-fashioned CV on non-text widgets — **and that the winner, Faster
R-CNN, reaches only `F1 = 0.438` at `IoU > 0.9`.**
([arxiv 2008.05132](https://arxiv.org/abs/2008.05132) ·
[github.com/MulongXie/UIED](https://github.com/MulongXie/UIED))

Read that as a design-review requirement, not a leaderboard entry. `IoU > 0.9` on a 200×48 button
still permits a ~5 px boundary error. **A measurement layer that is wrong about the box edge is
wrong about every gap, every alignment, and every margin computed from it.** The best available
learned detector is right *less than half the time* at a tolerance that is still ten times looser
than "16 vs 23 px" needs. This single number is the strongest argument in this document for the
classical layer.

The same paper's secondary finding is quietly useful: **more anchor scales/aspect ratios barely
helped**, because *"the scales and aspect ratios of GUI elements follow standard distributions."*
That regularity is exactly what a projection profile or a histogram of gaps exploits directly, with
no model at all.

### 2.3 Generalist VLMs collapse on high-resolution UI

ScreenSpot-Pro (23 apps, 5 industries, 3 OSes, professional high-res screenshots) measures the gap
in the bluntest possible way: **generalist MLLMs including GPT-4o and Qwen2-VL-7B score below 2 %**,
while *specialist* 7 B GUI models — OS-Atlas-7B 18.9 %, UGround-7B 16.5 %, AriaUI 11.3 % — do an
order of magnitude better, and even the SOTA search-augmented method reaches only ~48 %.
([arxiv 2504.07981](https://arxiv.org/abs/2504.07981))

Below 2 % is not "degraded transfer." It is *no* transfer. The models that do work — MolmoPoint-GUI,
OmniParser, OS-Atlas, UI-TARS — all share one property: **screenshots in the training set.**
MolmoPoint's screenshot data was generated by *rendering HTML and auto-extracting the boxes*
([arxiv 2603.28069](https://arxiv.org/html/2603.28069v1)), i.e. they closed the gap by
manufacturing in-domain data, not by hoping for generalisation.

### 2.4 Saliency transfers worst of all — and it is quantified

This is the cleanest single measurement of the gap anywhere in this document. UMSI, a saliency model,
was evaluated on UI screenshots. **Trained on natural-scene / proxy data it scores AUC 0.778;
retrained on UEyes (real eye-tracking over 1,980 UI screenshots, 62 participants, webpage + desktop
+ mobile + poster) it scores AUC 0.878.** The paper's own conclusion is that eye-movement data over
*interfaces* "yields superior performance to training with proxy data, such as mouse movements or
manual annotations, **or even training with data collected from viewing of natural scenes**."
([UEyes, CHI '23](https://dl.acm.org/doi/10.1145/3544548.3581096) ·
[dataset, arxiv 2402.05202](https://arxiv.org/pdf/2402.05202))

A 10-point AUC swing from domain alone. **If you want a saliency map for hierarchy critique, use a
UI-trained one (UEyes-finetuned UMSI) or none.** A natural-image saliency model on a screenshot
will fire on the photograph in the hero and go quiet on the call-to-action.

### 2.5 The one place the gap runs the *other* way

Segmentation is the exception. SAM's masks follow rendered edges *better* than natural edges,
because a rendered edge is a genuine step function with no motion blur, no depth of field, no
shadow. The failure mode is not imprecision — it is that **SAM is not semantic**
([facebookresearch/segment-anything](https://github.com/facebookresearch/segment-anything)): it will
return a beautiful, pixel-exact mask of a background gradient band, or split one card into its
image, its heading, and its body, with no signal about which grouping you wanted. SAM 3's concept
prompts partially fix this — but the concepts it knows are natural-image concepts.

**Net.** Use learned models for *semantics and grouping*, and only ones with screenshots in their
training data. Use classical CV for *every number*. Anything else is assuming a transfer that four
separate literatures say does not happen.

---

## 3. Classical CV — the actual measurement layer

A screenshot is the **best case** for classical CV that exists: no lens, no noise, no illumination
variance, axis-aligned rectangles, quantized colours, deterministic re-rendering. Every assumption
that makes Canny fragile on a photograph is *satisfied* here. This is why UIED — the hybrid that
beat every pure approach — uses "old-fashioned CV approaches to locate the elements and a CNN
classifier to achieve classification"
([github.com/MulongXie/UIED](https://github.com/MulongXie/UIED)). Localise classically; classify
neurally. That division is the whole design.

### 3.1 The table — function → defect

| # | Technique | Concrete call | Output | Exact design defect it detects |
|---|---|---|---|---|
| C1 | **Connected components** | `cv2.connectedComponentsWithStats(bin, connectivity=8)` · `skimage.measure.label` + `regionprops` ([pyimagesearch](https://pyimagesearch.com/2021/02/22/opencv-connected-component-labeling-and-analysis/) · [datacarpentry](https://datacarpentry.github.io/image-processing/08-connected-components.html)) | per-blob `x, y, w, h, area, centroid` | **Element bounds to the exact pixel.** Everything downstream is arithmetic on these. Catches: inconsistent card heights, a button 2 px taller than its sibling |
| C2 | **Edge + contour** | `cv2.Canny` → `cv2.findContours(RETR_TREE)` → `cv2.boundingRect` · `skimage.feature.canny` | nested box tree | **Containment hierarchy** and **padding**: `parent.box − child.box` per side gives the four padding values. Catches asymmetric padding (`16/16/16/12`) |
| C3 | **Line segments** | `cv2.createLineSegmentDetector` (**restored in OpenCV ≥4.5.4** after the NFA code was MIT-relicensed — absent 3.4.6–3.4.15 and **4.1.0–4.5.3**, [opencv_contrib#2524](https://github.com/opencv/opencv_contrib/issues/2524)) · fallback `cv2.ximgproc.createFastLineDetector` (~10× faster, less accurate) · `cv2.HoughLinesP` · `skimage.transform.hough_line` | line segments with endpoints + angle | **Alignment.** Cluster segment x-coords → the vertical rules the design actually uses. A left edge 3 px off its column is a cluster outlier. Also catches **non-axis-aligned** artifacts: a "horizontal" divider at 0.4° |
| C4 | **Projection profiles** | `binary.sum(axis=0)` / `.sum(axis=1)`; peaks via `scipy.signal.find_peaks`; valleys = gutters | 1-D signal per axis | **Grid and rhythm inference.** Vertical projection zeros = column gutters; horizontal = row gaps. This is the classical document-layout primitive (*"horizontal projection identifies text lines, vertical projection detects columns"*) and it works because UI is axis-aligned. **Directly produces `16, 16, 16, 23`** |
| C5 | **Distance transform / morphology** | `cv2.distanceTransform(inv_bin, DIST_L2, 5)` · `cv2.morphologyEx(..., MORPH_CLOSE/OPEN)` · `skimage.morphology.binary_closing` | whitespace field, merged regions | **Whitespace measurement + grouping.** The distance transform's local maxima are the *widest whitespace channels* — the visual separators. A `MORPH_CLOSE` with a kernel of size *k* merges anything closer than *k*, which **operationalises proximity-grouping**: the *k* at which two blobs merge IS their perceptual distance. Catches "the label is closer to the wrong field" |
| C6 | **Template matching** | `cv2.matchTemplate(img, tmpl, cv2.TM_CCOEFF_NORMED)` + `cv2.minMaxLoc` / NMS | match locations + scores | **Repeated-component divergence.** Crop one card, match across the page: score 1.00 for identical instances, 0.94 for the one whose border-radius differs. Catches inconsistent instances of a design-system component |
| C7 | **Sub-pixel registration** | `skimage.registration.phase_cross_correlation(a, b, upsample_factor=100)` — registers *"to within 1/upsample_factor of a pixel"* ([skimage docs](https://scikit-image.org/docs/stable/api/skimage.registration.html)) | (dy, dx) to 0.01 px | **Off-by-a-fraction offsets** invisible to eye and to box arithmetic. Two supposedly identical rows differing by 0.5 px from a fractional-em line-height |
| C8 | **Colour quantization** | `cv2.kmeans` in **Lab** (`skimage.color.rgb2lab`), or `PIL.Image.quantize(method=MEDIANCUT)`; count unique RGB with `np.unique(px, axis=0)` | palette + pixel-share per colour | **Palette sprawl** — the literal count of distinct colours actually painted. Also **near-duplicate colours**: two greys 1.5 ΔE apart is a token bug, not a design choice. Lab, not RGB, because ΔE is perceptual |
| C9 | **Contrast (derived, not CV)** | WCAG relative-luminance ratio computed on C8's foreground/background pairs | ratio per text region | **Accessibility failures**: 3.8:1 body text. Needs C1+C8 to know *which* pair to compare — that is the CV part |
| C10 | **Text bounds** | Vision.framework `VNRecognizeTextRequest` (native, free, fast on macOS) or `cv2.dnn` EAST/DB | word/line boxes + strings | **Type scale and leading**: cluster cap-heights → the actual font-size ramp; baseline deltas → leading. Catches a 7-step type scale that should be 4 |
| C11 | **Classical saliency** | `cv2.saliency.StaticSaliencySpectralResidual_create()` · `StaticSaliencyFineGrained_create()` (opencv-contrib) ([docs.opencv.org](https://docs.opencv.org/4.x/da/dd0/classcv_1_1saliency_1_1StaticSaliencyFineGrained.html)) | float saliency map | Weak on UI — see §4. Useful only as a **cheap baseline** to contrast against a UI-trained model |
| C12 | **Frequency / autocorrelation** | 2-D FFT magnitude, or autocorrelation + `skimage.feature.peak_local_max` | dominant periods (px) | **The base grid, discovered not assumed.** The autocorrelation peak period is the repeat unit — tells you the page is on an 8-px grid, so 23 is a violation and 24 would not be |
| C13 | **Blur / asset quality** | `cv2.Laplacian(gray, cv2.CV_64F).var()` | scalar sharpness | **Upscaled raster assets** — a 1× logo on a 2× display. Low Laplacian variance in a region whose neighbours are crisp |
| C14 | **Structural diff** | `skimage.metrics.structural_similarity(a, b, full=True)` | per-pixel SSIM map | **Responsive-breakpoint and state regressions** — what changed between 1440 and 1280, or hover vs rest, localised to a region |

### 3.2 Why classical wins here specifically

- **It answers the question that was asked.** "Uneven spacing" is a claim about a *distribution of
  distances*. C1 → sort → diff → histogram is the whole computation. A detector that emits
  `{"label": "card", "score": 0.91}` has not started.
- **It is exact, not probabilistic.** `IoU > 0.9` at F1 0.438 (§2.2) vs a connected-component bound
  that is correct by construction on an anti-aliased-edge image.
- **It is auditable.** Every number traces to pixels. A reviewer can be shown the overlay.
- **It is fast.** The entire C1–C8 chain on a 1440×2400 screenshot is **tens of milliseconds** of
  NumPy/OpenCV on one M1 Max core — three orders of magnitude cheaper than any model in §1.
- **Its failure mode is legible.** Classical CV fails by returning an obviously wrong number
  (a blob that swallowed the whole page). Learned models fail by returning a *plausible* wrong
  number. For a measurement layer, legible failure is worth more than a higher mean score.

### 3.3 Where classical genuinely fails

Be honest about the limits, because they define what §1 is for:

1. **Gradients, shadows, glassmorphism, blur backdrops.** Thresholding and connected components
   assume a step edge. A `backdrop-filter: blur(20px)` card has no edge. → needs SAM or a DOM box.
2. **Semantics.** C1 finds a rectangle. It cannot say "primary CTA" vs "disabled secondary." →
   Florence-2 / CLIP crop classification.
3. **Overlap and z-order.** Connected components merge a badge overlapping an avatar into one blob.
   → SAM's instance masks, or the DOM.
4. **Photographic content.** A hero image is a texture bomb: Canny explodes, projection profiles go
   flat. → mask it out first (this is a legitimate SAM use), or take its bounds from the DOM.
5. **"Is this *good*?"** No classical operator has an opinion. The whole point of the measurement
   layer is that judgment stays with the model reading the numbers.

---

## 4. Saliency and visual-weight maps for hierarchy critique

**Which of the primitives can produce a map usable for hierarchy critique?** Four candidates, in
descending order of trustworthiness on UI.

### 4.1 UEyes-finetuned UMSI — the only one with UI ground truth

The one to use. UEyes is real eye-tracking: **62 participants × 1,980 UI screenshots**, 495 each of
webpage / desktop / mobile / poster, with multi-duration saliency maps *and scanpaths*, dataset and
models public. Finetuning UMSI on it took AUC **0.778 → 0.878**.
([CHI '23](https://dl.acm.org/doi/10.1145/3544548.3581096) ·
[arxiv 2402.05202](https://arxiv.org/pdf/2402.05202))

- **Runs on M1 Max?** Yes — UMSI is a small encoder-decoder CNN; PyTorch+MPS, well under a second.
- **The scanpath output matters more than the heatmap.** A heatmap says "the eye goes here." A
  *scanpath* says "the eye goes here **first**, then here." Hierarchy is an ordering claim, so the
  scanpath is the artifact that can be checked against the designer's intent: *"your primary CTA is
  fixation #4."* That is a measured fact, and it is the closest thing in this whole document to a
  learned model producing a number worth arguing about.

### 4.2 SUM (Saliency Unification through Mamba) — the 2025/26 generalist

WACV 2025 Oral; a Mamba+U-Net hybrid whose Conditional Visual State Space block *"dynamically adapts
to various image types, including natural scenes, **web pages**, and commercial imagery."*
([github.com/Arhosseini77/SUM](https://github.com/Arhosseini77/SUM) ·
[arxiv 2406.17815](https://arxiv.org/html/2406.17815))

Web pages are an explicit conditioning mode, which is the property that matters. **Caveat for this
machine:** Mamba's selective-scan is usually a custom CUDA kernel; expect either a slow pure-PyTorch
fallback path on MPS or real porting work. Verify before committing — this is the same trap as SAM 3
and Triton (§1.1).

### 4.3 VLM-as-saliency — do not

UIGaze (2026) asks exactly this question — *"How Closely Can VLMs Approximate Human Visual Attention
on User Interfaces?"* ([arxiv 2604.26352](https://arxiv.org/pdf/2604.26352)). It benchmarks VLMs
against UI eye-tracking rather than assuming equivalence, and positions purpose-built UI saliency
models as the reference. Combined with the sub-2 % ScreenSpot-Pro result (§2.3), asking a VLM "where
does the eye go" returns a *plausible narrative*, not a map. That is the single most dangerous
output shape for a review agent, because it is unfalsifiable.

### 4.4 The classical baseline — and why it under-performs here

`cv2.saliency.StaticSaliencySpectralResidual` and `StaticSaliencyFineGrained` (opencv-contrib,
[docs](https://docs.opencv.org/4.x/da/dd0/classcv_1_1saliency_1_1StaticSaliencyFineGrained.html))
run in milliseconds and need no model. Both implement *bottom-up, centre-surround / spectral-residual
contrast* — which on a screenshot fires on **the photograph in the hero and on any high-frequency
texture**, and stays quiet on a large flat colour block that is the actual visual anchor. Keep it
only as a **control**: if the UI-trained map and the spectral-residual map agree, the finding is
robust; if they disagree, the UI-trained one is right and you have learned that the page's hierarchy
is carried by *layout*, not by local contrast.

### 4.5 A classical "visual weight" map that is arguably better than any of them

For hierarchy critique specifically, you can compute visual weight *compositionally* from §3, and it
has a property no learned map has: **every term is inspectable and attributable.**

```
weight(element) =  area(C1)
                 × contrast_vs_background(C8/C9)      # ΔE in Lab, not RGB
                 × isolation(C5 distance transform)   # whitespace around it = emphasis
                 × (1 / (1 + normalized_position))    # F/Z-pattern position prior from UEyes
```

Rank elements by this and compare the ranking to the *semantic* hierarchy (h1 > h2 > body > caption,
CTA > secondary) that the DOM or Florence-2 supplies. **A rank inversion is the hierarchy defect,
stated as a measured fact:** *"the secondary 'Learn more' link has 2.3× the visual weight of the
primary CTA — it is larger, has higher contrast against its background, and sits in more
whitespace."* No eye-tracking model needed, and every clause is a number you can point at on the
overlay. Use UMSI/UEyes to *validate* this ranking, not to replace it.

---

## 5. The consolidated table

Speeds are for **one 1440×2400 screenshot** on M1 Max / 64 GB / 32-core GPU. Figures marked *(est.)*
are extrapolated from the nearest published Apple-Silicon measurement and should be re-measured
before anyone depends on them.

| Technique | CV task | Output type | Apple-Silicon feasibility | Speed | Design question it answers | Licence |
|---|---|---|---|---|---|---|
| **Connected components** (`connectedComponentsWithStats`) | segmentation of flat regions | boxes + centroids + areas | **Native** (NumPy/OpenCV, CPU) | **~5–20 ms** | *Where exactly is every element?* | BSD-3 (OpenCV) |
| **Canny + contour tree** | edge detect + hierarchy | nested boxes | **Native** | ~10–30 ms | *What is the padding on each side, and does it match its siblings?* | BSD-3 |
| **LSD / FastLineDetector / Hough** | line detection | segments + angles | **Native** (LSD present in OpenCV ≥4.5.4) | ~20–80 ms | *Do these six left edges share a column, or is one 3 px off?* | BSD-3 |
| **Projection profiles** | 1-D layout analysis | gap/gutter series | **Native** (pure NumPy) | **~2 ms** | ***"These four cards have gaps of 16, 16, 16 and 23 px."*** | n/a |
| **Distance transform + morphology** | whitespace field / grouping | float map, merge thresholds | **Native** | ~10–40 ms | *Is this label grouped with the right field? Is the whitespace rhythm consistent?* | BSD-3 |
| **Template matching** (`TM_CCOEFF_NORMED`) | repeated-instance detection | locations + similarity | **Native** | ~30–150 ms/template | *Are all six instances of this component actually identical?* | BSD-3 |
| **Phase cross-correlation** | sub-pixel registration | (dy, dx) to 0.01 px | **Native** (`skimage`) | ~10–50 ms | *Is this row offset by a fraction of a pixel?* | BSD-3 (scikit-image) |
| **Lab k-means / median-cut quantization** | colour clustering | palette + share | **Native** | ~50–200 ms | *How many colours are actually painted? Which two are near-duplicates?* | BSD-3 / MIT-PIL |
| **WCAG luminance ratio** (derived) | — | ratio per text region | **Native** | <1 ms | *Does body text pass 4.5:1?* | n/a |
| **Vision.framework text recognition** | OCR / text bounds | word boxes + strings | **Native, Apple-optimised** | ~100–300 ms | *What is the real type scale and leading?* | Apple SDK |
| **FFT / autocorrelation** | periodicity | dominant periods | **Native** | ~20–60 ms | *What base grid is this page actually on — 4 px or 8 px?* | n/a |
| **Laplacian variance** | blur estimate | scalar/region | **Native** | ~5 ms | *Is that logo an upscaled 1× asset?* | BSD-3 |
| **SSIM** (`structural_similarity`) | structural diff | per-pixel map | **Native** | ~50–150 ms | *What changed between breakpoints or states?* | BSD-3 |
| **`cv2.saliency` spectral-residual / fine-grained** | bottom-up saliency | float map | **Native** | ~10–40 ms | *(control only)* — biased toward photos and texture | BSD-3 (contrib) |
| **UMSI finetuned on UEyes** | UI saliency + **scanpath** | heatmap + fixation order | **Yes**, PyTorch+MPS, small CNN | **~0.2–0.8 s** *(est.)* | *Is the primary CTA the first fixation, or the fourth?* | research/academic — **check before commercial use** |
| **SUM (Mamba)** | multi-domain saliency, web-page conditioned | heatmap | ⚠️ **Verify** — selective-scan is typically a CUDA kernel | unknown on MPS | *Saliency without the UI-only ceiling* | research (GitHub) |
| **DINOv3 ViT-S/B** | dense self-supervised features | patch embeddings | **Yes**, PyTorch+MPS | ~0.2–0.6 s *(est.)* | *Are these regions the same component, without labels?* | DINOv3 licence (commercial-permitting) |
| **CLIP / OpenCLIP image tower** | zero-shot crop classification / retrieval | embedding + text sim | **Yes** — MLX, or Core ML export | ~20–80 ms/crop | *Is this crop a button, an avatar, a logo?* | MIT |
| **Florence-2** (0.23 B / 0.77 B) | caption / region proposal / grounding | text + boxes | **Yes — first-class in `mlx-vlm`** | ~0.3–2 s | *What is this region, in words?* | **MIT** |
| **OmniParser V2** (YOLO detector + Florence-2) | screen parsing | interactable regions + captions | **Yes** (Ultralytics MPS + MLX) | ~0.5–1.5 s | *What are the interactive elements?* (39.5 % ScreenSpot-Pro) | mixed — **YOLO half is AGPL-adjacent** |
| **MolmoPoint-GUI-8B** | pointing / GUI grounding | (x, y) points | **Yes** — Molmo in `mlx-vlm`, 8 B fits 64 GB | seconds (autoregressive) | *Where is the element I described in words?* (61.1 ScreenSpot-Pro) | Apache-2.0 |
| **SAM 3 / 3.1** | promptable concept segmentation | pixel masks | ⚠️ **HF `transformers` route only** — official repo needs Triton (CUDA) | ~3–5 s *(est.)* | *What are the exact bounds of this soft-edged / gradient / overlapping thing?* | SAM licence |
| **Grounding DINO (open, Swin-T/B)** | open-vocab detection | boxes + scores | **Yes**, PyTorch+MPS | ~1.5–4 s *(est.)* | *(weak on UI — prefer OmniParser)* | Apache-2.0 |
| **OWLv2** | open-vocab detection | boxes + scores | **Yes**, HF+MPS | ~1–3 s *(est.)* | *(weak on UI)* | Apache-2.0 |
| **YOLOE / YOLO-World** | real-time open-vocab detect+segment | boxes/masks | **Yes**, fast, Core ML export | tens of ms | *(capable, but)* | **AGPL-3.0 — the blocker** |
| **Grounding DINO 1.5/1.6 Pro** | open-vocab detection | boxes | ❌ **API-only** | n/a | — | proprietary |

### 5.1 Pipeline sketch — composing these into measurable design facts

Seven stages. Note where the learned models sit: **stages 2 and 6 only**. Everything numeric is
classical.

```
┌─ 0. CAPTURE ────────────────────────────────────────────────────────────────┐
│  Deterministic screenshot at a pinned DPR + viewport (1440×2400 @2x).       │
│  Simultaneously dump the DOM box tree (see §6) — they are cross-checks,     │
│  not alternatives.                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
            │
┌─ 1. PRIMITIVE EXTRACTION (classical, ~100 ms total) ────────────────────────┐
│  C10 Vision.framework  → text boxes + strings                               │
│  C1  connectedComponents (on ¬text mask) → graphical element boxes          │
│  C2  Canny+contours    → containment tree                                   │
│  C8  Lab k-means       → palette, per-element fg/bg pairs                   │
│  ⇒ ELEMENT TABLE: {id, box, kind∈{text,graphic}, fg, bg, parent}            │
└─────────────────────────────────────────────────────────────────────────────┘
            │
┌─ 2. SEMANTIC LABELLING (learned — the ONLY place a model touches geometry's │
│     meaning, never its numbers) ────────────────────────────────────────────┐
│  CLIP zero-shot over crops  → {button, input, avatar, logo, icon, card}     │
│  Florence-2 (MLX) on ambiguous crops → caption / region grounding           │
│  Optional: OmniParser V2 → interactable-region set as a second opinion      │
│  Optional escape hatch: SAM 3 ONLY for soft-edged/overlapping elements      │
│     that C1 merged or missed (gradients, blur backdrops, badge-on-avatar)   │
└─────────────────────────────────────────────────────────────────────────────┘
            │
┌─ 3. STRUCTURE INFERENCE (classical) ────────────────────────────────────────┐
│  C4 projection profiles → columns, rows, gutters                            │
│  C12 autocorrelation    → the base grid unit (4? 8?) — DISCOVERED           │
│  C3 line clustering     → the alignment rails actually in use               │
│  C5 morphological closing sweep → proximity groups at each k                │
│  ⇒ LAYOUT MODEL: {grid_unit, columns[], rails[], groups[]}                  │
└─────────────────────────────────────────────────────────────────────────────┘
            │
┌─ 4. MEASUREMENT (classical — this is where the numbers are born) ───────────┐
│  gaps      = pairwise edge distances within each group      → [16,16,16,23] │
│  alignment = |element.left − nearest_rail|                  → [0,0,0,3]     │
│  padding   = parent.box ⊖ child.box, per side               → [16,16,16,12] │
│  scale     = cluster(cap_heights)                           → [12,14,16,32] │
│  palette   = |unique colours|, pairwise ΔE                  → 34 colours,   │
│                                                                2 pairs <2ΔE │
│  contrast  = WCAG ratio per text region                     → 3.8:1 ✗       │
│  identity  = C6 template scores across repeated components  → [1.0,…,0.94]  │
└─────────────────────────────────────────────────────────────────────────────┘
            │
┌─ 5. DEFECT PREDICATES (pure arithmetic — the falsifiable layer) ────────────┐
│  uneven_spacing  : max(gaps) − min(gaps) > tolerance                        │
│  off_grid        : any value mod grid_unit ≠ 0                              │
│  misaligned      : alignment residual > 1 px                                │
│  scale_sprawl    : |distinct type sizes| > 6                                │
│  palette_sprawl  : |distinct colours| > 12, or any pair ΔE < 2              │
│  component_drift : template score < 0.98 among nominal siblings             │
│  contrast_fail   : WCAG ratio < 4.5 (body) / 3.0 (large)                    │
│  Each emits: (defect, [element ids], measured value, expected value)        │
└─────────────────────────────────────────────────────────────────────────────┘
            │
┌─ 6. HIERARCHY CRITIQUE (§4 — one learned map, one classical) ───────────────┐
│  visual_weight ranking (§4.5, classical, attributable)                      │
│  UMSI/UEyes scanpath → predicted fixation ORDER                             │
│  Defect: rank inversion between visual weight and semantic importance       │
└─────────────────────────────────────────────────────────────────────────────┘
            │
┌─ 7. NARRATION (the LLM's only job) ─────────────────────────────────────────┐
│  Turn the defect tuples into prose. The model NEVER estimates a number;     │
│  it only reads, ranks by severity, and explains. Every sentence it writes   │
│  carries an id and a measurement that can be re-derived from the pixels.    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**The load-bearing property of this pipeline:** stage 7 cannot hallucinate a measurement, because
stage 4 is the only producer of numbers and stage 5 is the only producer of verdicts. The model is
downstream of both. That is the whole reason to build a measurement layer at all.

---

## 6. Adversarial pass — "the DOM already has exact geometry, so none of this is needed"

### 6.1 The strongest case against everything above

Put honestly, because it is very strong, and a lot of it is simply correct.

**A1 — The DOM is not an estimate; it is the ground truth the pixels were *generated from*.**
Every number in §4 of the pipeline is being *recovered* from a rasterisation of data the browser
already holds exactly. `element.getBoundingClientRect()` returns *"the smallest rectangle which
contains the entire element, including its padding and border-width"*
([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Element/getBoundingClientRect)) as
floating-point CSS pixels. There is no thresholding, no anti-aliasing ambiguity, no k-value to tune.
Reconstructing that from pixels is an information-losing round trip performed for no reason. A
connected-component bound is *inferred*; a DOMRect is *authoritative*.

**A2 — It is free, instant, and exact.** One `document.querySelectorAll('*')` + `getBoundingClientRect`
over a few thousand nodes runs in single-digit milliseconds and returns sub-pixel floats. The
classical chain in §3 is "tens of milliseconds"; the learned chain is *seconds*. And the DOM's
numbers are exact where the CV numbers carry ±1 px of anti-aliasing uncertainty on every edge.

**A3 — It solves the exact stated problem, better.** *"These four cards have gaps of 16, 16, 16 and
23 px"* is `rects[i+1].left − rects[i].right` on four nodes. Four subtractions. §3's projection
profile has to first *find* the cards, and it will merge two cards whose gap is 0, split one card
that contains a light divider, and be defeated entirely by a card with a `backdrop-filter`.

**A4 — The DOM carries semantics *for free* that §1's models are being paid seconds per screenshot
to guess badly at.** ScreenSpot-Pro says GPT-4o scores **under 2 %** at locating an element by
description (§2.3). `querySelector('[data-testid="cta"]')` scores 100 %, in a microsecond. Role,
tag, ARIA label, class list, `getComputedStyle`, the *design-token variable name* — the DOM has all
of it. The entire §1 model list is an expensive, lossy, less accurate reimplementation of
`getComputedStyle`.

**A5 — Defect predicates get *better* inputs from the DOM.** Off-grid detection wants the declared
`gap: 23px`, not a measured 23. Palette sprawl wants the set of `--color-*` custom properties
actually resolved, not a k-means of the painted pixels, which will invent 40 "colours" out of
anti-aliasing fringes and a JPEG hero. Type-scale sprawl wants `font-size`, not clustered
cap-heights. **In each case the CV version is a noisy estimator of a value that is sitting right
there as a string.**

**A6 — And it is actionable.** "Card 3's gap is 23 px" is a finding. `.card-grid { gap: 23px }` at
`styles/cards.css:47` is a **fix**. CV cannot produce the second, ever. A review that cannot name
the selector has offloaded the hard half onto the human.

**A7 — The prior art agrees.** The mature tooling in this space — accessibility linters, design-token
auditors, visualisation linters like VizLinter and GeoLinter which check *specifications* against
best practices ([arxiv 2310.13707](https://arxiv.org/pdf/2310.13707)) — all operate on the
declarative source, not the render. Visual-regression tools that *do* use pixels use them for one
narrow thing: **diffing against a baseline**, not measuring.

**A8 — CV's own literature convicts it.** §2.2's headline number, `F1 = 0.438 at IoU > 0.9` for the
best learned GUI detector, is not an argument for CV. It is an argument that *recovering element
bounds from a screenshot is a hard, unsolved problem which the DOM makes trivially easy.*

**A conscientious summary of A1–A8: for a web page you control, in a browser you drive, the DOM is
strictly better for element bounds, spacing, padding, type scale, declared colour, and every fix
suggestion. If the pipeline in §5 were justified only by those, it should not be built.**

### 6.2 What the DOM cannot reveal

Eleven classes. They divide cleanly into three kinds, and the third kind is the one that matters.

---

#### Kind 1 — "The DOM describes intent; only pixels record the outcome"

**D1. Zero-ink elements.** A node with a DOMRect of `200×48` at a valid position may paint **nothing**:
`opacity: 0`, `color` equal to its background, occluded by a higher `z-index` sibling, clipped by an
ancestor's `overflow: hidden`, `transform: scale(0)`, `clip-path` to empty, a font that never loaded
so the glyphs are invisible, or `content-visibility: hidden`. The DOM reports a healthy box for every
one of these. **Only the rendered pixels can say the element is not there.** This is the single most
important entry on the list, because it is a *silent* failure in exactly the direction a DOM-only
reviewer is blind to: it reports a layout that is correct and a page that is broken.

**D2. Occlusion and stacking.** DOM boxes overlap constantly and legitimately (a sticky header, a
dropdown, a tooltip). Nothing in the box tree says *which one the user sees* — that requires
resolving stacking contexts, `z-index`, paint order, and opacity together, which is the compositor's
job, not a queryable one. "Is this text readable, or has a modal backdrop landed on top of it?" is a
pixel question.

**D3. Composited colour ≠ computed colour.** `getComputedStyle().color` returns the *declared,
resolved* value — but `mix-blend-mode`, `filter`, `backdrop-filter`, `opacity` on an ancestor, and
`background-blend-mode` are all applied **at the rendering stage, after style computation**
([Sara Soueidan on compositing/blending](https://www.sarasoueidan.com/blog/compositing-and-blending-in-css/)
· [MDN mix-blend-mode](https://developer.mozilla.org/en-US/docs/Web/CSS/mix-blend-mode)). So a
contrast check computed from CSS is *wrong whenever any of those are in play* — a recognised
limitation of standard contrast checkers, which evaluate base colour values without accounting for
blend modes or filters. **A WCAG ratio is only trustworthy if it is sampled from the actual painted
pixels.** This one is not a nuance; it is a correctness bug in every DOM-only accessibility audit of
a page using modern compositing.

**D4. Transforms lie about position — in the API's own return value.** If an element is moved with a
transform, `getBoundingClientRect()` returns `left`/`top` from *before* the translation and `x`/`y`
from *after* it. Scale, rotation and shear change the visual appearance without changing the
starting position, and the DOMRect is only the axis-aligned bounding box of the transformed shape,
not the shape ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Element/getBoundingClientRect)
· [CSSOM transform interaction, W3C](https://lists.w3.org/Archives/Public/www-style/2010Aug/0615.html)).
A rotated card's DOMRect describes a rectangle that does not exist on screen. Overflow bounds
computed at end-of-layout can also *increase* from paint-level effects like transforms. Ask the DOM
where a rotated element is and it will answer confidently and incorrectly.

**D5. Rendered type ≠ specified type.** `font-size: 16px` with `font-family: Inter` tells you nothing
about what was painted if Inter did not load. Fallback fonts have different **x-height and
cap-height at the same font-size** — which is exactly why `font-size-adjust` exists
([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/font-size-adjust) ·
[Chrome's own guidance on visually-stable fallbacks](https://github.com/GoogleChrome/modern-web-guidance/blob/main/skills/modern-web-guidance/guides/visual-design/visually-stable-font-fallbacks.md)).
The DOM's `font-size` is a specification; the **ink extent** of the glyphs is the design fact, and
only OCR/CV measures it. Related: a DOMRect includes half-leading above and below the text, so a
label that is *box-centred* is usually *optically low* — the DOM literally cannot see the
discrepancy because it has no representation of the ink.

---

#### Kind 2 — "The DOM has no node for it"

**D6. Content inside opaque leaves.** A `<canvas>`, a WebGL surface, a `<video>` frame, a rasterised
chart, a cross-origin `<iframe>`, a PDF embed, a Lottie animation — each is **one DOM node with one
box and no interior structure**. Every design fact inside it (is the chart legible? does the video
poster frame have text baked into it at 2.9:1? is the map label clipped?) is invisible to the DOM
and trivially visible to CV. Note that this class is *growing*: canvas-rendered UI (Figma, Google
Docs, most data-grid libraries at scale) turns the whole surface into D6.

**D7. Raster asset content.** The DOM knows an `<img>` occupies 320×180. It does not know the logo
inside it is an upscaled 1× asset that is visibly soft on a 2× display (`cv2.Laplacian` variance,
C13), that the subject is cropped through someone's forehead, that the photo's dominant colour
clashes with the palette, or that white text was baked into a light region of the JPEG. To a
DOM-only reviewer, every image is a grey rectangle.

**D8. Pseudo-elements, decorations, and paint that extends past the box.** `::before` / `::after`
have **no DOM node** and no `getBoundingClientRect`. `box-shadow`, `filter: drop-shadow`, `outline`,
and `text-shadow` paint *outside* the border box and are excluded from the DOMRect entirely — yet a
shadow is a major contributor to perceived spacing and visual weight. Two cards with identical
DOMRects and different shadow spreads have different *perceived* gaps. The measurement the human eye
makes includes the shadow; the measurement the DOM makes does not.

---

#### Kind 3 — "It is not a property of any node" *(the class that actually justifies the pipeline)*

This is where the DOM is not merely incomplete but **categorically inapplicable**, and it is the
answer to the question the whole exercise is about.

**D9. Emergent, whole-image properties.** *"The page feels crowded."* *"The eye doesn't know where to
go."* *"The hierarchy is flat."* *"There's no focal point."* These are properties of the **composited
raster**, not of any element or any pair of elements. There is no node to query, and no amount of
per-node data sums to them. Concretely:

- **Whitespace as a field.** §3's `cv2.distanceTransform` measures the *shape and continuity of the
  negative space* — the channels the eye actually travels. You cannot get that from boxes, because
  whitespace is precisely what is between the boxes and belongs to none of them. "Crowded" is
  quantifiable as ink-density and mean whitespace-channel width; both are image statistics.
- **Visual weight and fixation order** (§4). Whether the primary CTA is the first thing seen is a
  fact about the rendered image and a human visual system. UEyes exists because this is measurable —
  and it measures screenshots, not DOMs.
- **Gestalt grouping.** *Which* things read as a group is set by proximity, similarity and enclosure
  in the render. The DOM's grouping is `<div>` nesting, which is a *code* structure that frequently
  disagrees with the perceptual one — that disagreement is itself a common and important design
  defect ("these look like one group but behave as two"), and detecting it **requires both
  representations**. The perceptual-grouping literature for GUIs works this way for exactly this
  reason ([arxiv 2206.10352](https://arxiv.org/pdf/2206.10352)).
- **Optical vs geometric alignment.** A circular avatar and a square thumbnail with identical
  DOMRects are *not* optically aligned; a triangular play-button glyph centred by box is visibly
  right-of-centre. Optical correction is a real design practice, and its unit is ink centroid, not
  box centre. `regionprops.centroid` (C1) computes it; the DOM cannot represent it.

**D10. Cross-engine, cross-device, cross-state divergence.** The DOM is *identical* in Safari and
Chrome and Firefox. The pixels are not — font smoothing, sub-pixel positioning, `1px` borders at
fractional DPR (a 1 CSS-px hairline at DPR 1.5 rasterises to a blurred 2 device-px band), scrollbar
gutters, and the OS text-rendering stack all differ. A design defect that exists only in one engine
or at one DPR is **definitionally invisible to a DOM-only review**, because the DOM is the thing
that is the same in both. The same argument covers print stylesheets, email HTML, and dark-mode
forced-colors rendering.

**D11. Surfaces where there is no DOM at all.** A competitor's product. A Figma export. A design
mockup being compared to the built page. A stakeholder's screenshot in a ticket. A native app. A PDF.
A video frame of the product. A DOM-only reviewer can review exactly one artifact — *your own page,
in a browser you are driving, right now*. The CV layer reviews any image. For a design-review agent
this is not an edge case; comparing the built page against the mockup is one of the primary jobs, and
**one side of that comparison never has a DOM.**

### 6.3 The synthesis — the actual division of labour

The adversarial case wins on the *stated example* and loses on the *stated goal*.

- **"Uneven spacing → 16, 16, 16, 23"** is genuinely a DOM job. Four subtractions, exact, with the
  offending selector attached. §6.1 A3 is correct and should be conceded without qualification.
- But *"the spacing looks uneven"* was an **impression**, and the class of impressions a design
  reviewer must convert includes "crowded", "unbalanced", "no focal point", "these don't feel like
  the same component", "the eye goes to the wrong place", "it looks broken on Safari". **The DOM can
  measure the first impression and cannot even represent the rest.**

The right architecture follows directly, and it is **not** "CV instead of DOM" or "DOM instead of
CV". It is:

> **The DOM is the primary measurement instrument. CV is the instrument that measures the
> DOM's blind spots — and, more importantly, it is the *oracle that checks the DOM against
> reality*.**

That second role is the one no amount of DOM introspection can fill, and it is worth stating as a
rule:

**Every high-value finding in this document comes from a DISAGREEMENT between the two
representations, not from either alone.**

| DOM says | Pixels say | The defect |
|---|---|---|
| element at (120, 400), 200×48 | nothing painted there | **D1** — zero-ink: occluded, transparent, or clipped |
| `color: #333` on `#fff` → 12.6:1 | sampled ratio 2.9:1 | **D3** — a blend mode / filter / ancestor opacity destroyed the contrast |
| six siblings, same classes | template match 1.0, 1.0, 1.0, 1.0, 1.0, **0.94** | component drift in one instance |
| `gap: 16px` uniformly | measured 16, 16, 16, **23** | a sibling has an unaccounted margin, shadow, or transform |
| box-centred label | ink centroid 2 px low | **D5** — half-leading; optically misaligned |
| `<div>` nesting says 2 groups | morphological closing merges at k=8 into 1 | **D9** — code structure ≠ perceptual structure |
| h1 is the most important element | visual-weight rank puts it 4th | **D9** — hierarchy inversion |
| identical DOM in Chrome and Safari | SSIM map differs in the nav | **D10** — engine-specific rendering defect |

A finding in that table is *stronger than either source could produce alone*, because a disagreement
between two independent instruments is evidence in a way a single reading never is. **That is the
argument for building the CV layer, and it is the only argument that survives §6.1.**

**Corollary — the cheapest useful version of this system.** If only one thing gets built, build the
**cross-check**, not the pipeline: capture the DOM box tree and the screenshot together, rasterise
each DOMRect's region, and assert (a) it has non-background ink, (b) its sampled fg/bg contrast
matches the computed one, and (c) its ink centroid matches its box centre. That is perhaps 200 lines
of NumPy, runs in milliseconds, needs no model whatsoever, and catches D1, D3 and D5 — three of the
four defect classes that ship to production undetected today.

---

## 7. Recommendation

### 7.1 Build order

| Tier | What | Why here | Cost |
|---|---|---|---|
| **T0 — build first** | DOM box tree + screenshot, and the **three cross-check assertions** (ink present · sampled contrast · ink centroid) | Highest value per line of code in this entire document. Catches D1/D3/D5. No model, no GPU. | ~200 lines NumPy |
| **T1** | Classical measurement chain C1–C5, C8, C10, C12 (§3) | Produces every number, on any image, DOM or not. ~100 ms/screenshot on one core. | a day or two |
| **T2** | Defect predicates + the classical visual-weight ranking (§4.5, §5 stage 5) | Turns numbers into falsifiable verdicts with an attributable formula. | small |
| **T3** | CLIP crop classification + **Florence-2 via `mlx-vlm`** | Semantics only. MIT, tiny, MLX-native — the only learned model with no adoption friction on this machine. | moderate |
| **T4 — only if T0–T3 leave a real gap** | **SAM 3 via HF `transformers`** for soft-edged/overlapping elements; **UMSI finetuned on UEyes** for fixation order | Both are genuinely useful and both carry setup risk (Triton; licence). Do not start here. | high |
| **Skip** | Grounding DINO (any version), OWLv2, YOLO-World/YOLOE, generalist VLM grounding | Natural-image priors, <2 % ScreenSpot-Pro class performance, or AGPL. Nothing they give you is worth the seconds. | — |

### 7.2 The three findings that most change the design

1. **Classical CV is not the fallback here — it is the primary measurement layer.** The best learned
   GUI detector reaches `F1 = 0.438 at IoU > 0.9` (§2.2). A screenshot is the ideal case for
   thresholding and connected components. Every pixel number should come from §3.
2. **Only use learned models with screenshots in their training set.** GPT-4o scores **below 2 %** on
   ScreenSpot-Pro; MolmoPoint-GUI-8B scores 61.1 because Ai2 rendered HTML to manufacture in-domain
   data. Natural-image transfer to rendered UI does not happen — measured four different ways (§2).
3. **"Open weights" ≠ "runs on this machine."** SAM 3's official repo is Triton-gated and therefore
   dead on Apple Silicon; the HF `transformers` reimplementation is the only route. Check kernel
   dependencies before licence.

### 7.3 Open questions this agent could not settle

- **SUM's Mamba selective-scan on MPS** — unverified. If it has a pure-PyTorch fallback it is the
  best generalist saliency option; if not, it is a port, not an install.
- **UEyes / UMSI weights licensing** for commercial use — the dataset and models are described as
  publicly available, but the specific terms were not read.
- **All latency figures marked *(est.)*** are extrapolations from an M2 Ultra SAM measurement and
  general MPS behaviour. They should be benchmarked on the actual M1 Max before any of them is
  quoted as a fact — this repo's own experience is that published performance figures go stale
  within days.
- **SAM 3.1 (2026-03-27) vs SAM 3 on Apple Silicon** — whether 3.1's changes affect the Triton
  dependency was not verified.

---

## Sources

- [ai.meta.com — SAM 3 / SAM 3.1 blog](https://ai.meta.com/blog/segment-anything-model-3/)
- [ai.meta.com — SAM 3: Segment Anything with Concepts](https://ai.meta.com/research/publications/sam-3-segment-anything-with-concepts/)
- [huggingface.co/facebook/sam3 — "Cannot run on Apple Silicon due to Triton"](https://huggingface.co/facebook/sam3/discussions/11)
- [facebookresearch/sam2#687 — SAM2 on Apple Silicon](https://github.com/facebookresearch/sam2/issues/687)
- [ultralytics#22954 — SAM3 MPS pin_memory failure](https://github.com/ultralytics/ultralytics/issues/22954)
- [facebookresearch/segment-anything](https://github.com/facebookresearch/segment-anything)
- [ai.meta.com — DINOv3](https://ai.meta.com/blog/dinov3-self-supervised-vision-model/) · [arxiv 2508.10104](https://arxiv.org/pdf/2508.10104)
- [allenai.org — MolmoPoint](https://allenai.org/blog/molmopoint) · [arxiv 2603.28069](https://arxiv.org/html/2603.28069v1)
- [arxiv 2405.10300 — Grounding DINO 1.5](https://arxiv.org/pdf/2405.10300)
- [microsoft/OmniParser](https://github.com/microsoft/omniparser) · [OmniParser V2, Microsoft Research](https://www.microsoft.com/en-us/research/articles/omniparser-v2-turning-any-llm-into-a-computer-use-agent/)
- [microsoft/Florence-2-large (MIT)](https://huggingface.co/microsoft/Florence-2-large)
- [Blaizzy/mlx-vlm](https://github.com/Blaizzy/mlx-vlm) · [MLX-VLM compatibility report, Jan 2026](https://github.com/Blaizzy/mlx-vlm/issues/661)
- [docs.ultralytics.com — YOLOE](https://docs.ultralytics.com/models/yoloe) · [YOLO-World](https://docs.ultralytics.com/models/yolo-world) · [arxiv 2401.17270](https://arxiv.org/abs/2401.17270)
- [arxiv 2504.07981 — ScreenSpot-Pro](https://arxiv.org/abs/2504.07981)
- [arxiv 2008.05132 — Object Detection for GUI: Old Fashioned or Deep Learning or a Combination?](https://arxiv.org/abs/2008.05132) · [MulongXie/UIED](https://github.com/MulongXie/UIED)
- [arxiv 2408.03507 — GUI Element Detection Using SOTA YOLO Models](https://arxiv.org/pdf/2408.03507)
- [arxiv 2206.10352 — Unsupervised Inference of Perceptual Groups of GUI Widgets](https://arxiv.org/pdf/2206.10352)
- [UEyes, CHI '23](https://dl.acm.org/doi/10.1145/3544548.3581096) · [UEyes dataset, arxiv 2402.05202](https://arxiv.org/pdf/2402.05202)
- [arxiv 2604.26352 — UIGaze: How Closely Can VLMs Approximate Human Visual Attention on UIs?](https://arxiv.org/pdf/2604.26352)
- [Arhosseini77/SUM](https://github.com/Arhosseini77/SUM) · [arxiv 2406.17815](https://arxiv.org/html/2406.17815)
- [OpenCV — StaticSaliencyFineGrained](https://docs.opencv.org/4.x/da/dd0/classcv_1_1saliency_1_1StaticSaliencyFineGrained.html) · [FastLineDetector](https://docs.opencv.org/3.3.1/df/d4c/classcv_1_1ximgproc_1_1FastLineDetector.html)
- [opencv_contrib#2524 — Restore LineSegmentDetector, MIT-relicensed NFA](https://github.com/opencv/opencv_contrib/issues/2524) · [opencv#14576](https://github.com/opencv/opencv/issues/14576)
- [PyImageSearch — OpenCV connected component labeling](https://pyimagesearch.com/2021/02/22/opencv-connected-component-labeling-and-analysis/) · [Data Carpentry — connected components](https://datacarpentry.github.io/image-processing/08-connected-components.html)
- [scikit-image — registration / phase_cross_correlation](https://scikit-image.org/docs/stable/api/skimage.registration.html) · [image registration example](https://scikit-image.org/docs/stable/auto_examples/registration/plot_register_translation.html)
- [MDN — getBoundingClientRect](https://developer.mozilla.org/en-US/docs/Web/API/Element/getBoundingClientRect) · [W3C CSSOM/transforms thread](https://lists.w3.org/Archives/Public/www-style/2010Aug/0615.html)
- [MDN — mix-blend-mode](https://developer.mozilla.org/en-US/docs/Web/CSS/mix-blend-mode) · [Sara Soueidan — Compositing and Blending in CSS](https://www.sarasoueidan.com/blog/compositing-and-blending-in-css/)
- [MDN — font-size-adjust](https://developer.mozilla.org/en-US/docs/Web/CSS/font-size-adjust) · [GoogleChrome/modern-web-guidance — visually-stable font fallbacks](https://github.com/GoogleChrome/modern-web-guidance/blob/main/skills/modern-web-guidance/guides/visual-design/visually-stable-font-fallbacks.md)
- [Segment Anything on Apple Silicon M1/M2 — measured timings](https://geo-ai.medium.com/segment-anything-model-sam-on-apple-silicon-m1-and-m2-5cdb3f781b27)
- [arxiv 2310.13707 — GeoLinter (design-linter prior art)](https://arxiv.org/pdf/2310.13707)
