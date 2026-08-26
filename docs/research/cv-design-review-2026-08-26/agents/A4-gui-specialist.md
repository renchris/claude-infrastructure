# A4 — GUI-specialist perception models as a grounding layer for a design-review agent

Research date: 2026-08-26. All numbers web-verified this session; every claim carries a URL.
Scope: models that take a screenshot and return structured elements with coordinates, judged as a
**measured-geometry layer beneath a design-critique judge**, for **desktop + mobile-web (Next.js/React)**
screenshots.

---

## 0. The three findings that reframe the question

Read these before the table; they change how every number below should be interpreted.

**F1 — ScreenSpot-Pro contains ZERO web screenshots.** It is 1,581 instructions over 23 *professional
desktop applications* (VSCode, PyCharm, Photoshop, AutoCAD, SolidWorks, MATLAB, Blender, Office) on
Windows/macOS/Linux. The paper states it draws on "professional desktop environments" only and
explicitly excludes browser screenshots. Targets occupy **0.07%** of screen area on average (vs 2.01%
in ScreenSpot). Source: <https://arxiv.org/html/2504.07981v1>. Every "SOTA on ScreenSpot-Pro" headline
in this space is therefore **evidence about CAD and IDE panels, not about your Next.js pages.**

**F2 — Every ScreenSpot variant scores point-in-box, not IoU.** A prediction counts as correct if the
predicted *point* falls inside the ground-truth box. There is no box-quality term in the metric at all
("what matters is where to click, not how well a region matches an ambiguous visual blob").
Sources: <https://www.alphaxiv.org/benchmarks/national-university-of-singapore/screenspot-pro>,
<https://arxiv.org/html/2401.10935>. **Consequence: a model can score 96% on ScreenSpot-v2 while its
box edges are tens of pixels wrong.** None of the accuracy numbers in this document certify the one
property a design reviewer needs — edge-accurate geometry. This is the single most important caveat
in the report.

**F3 — Frontier general VLMs have overtaken every open specialist on the specialist benchmark.**
Aggregator leaderboards as of 2026-08-25/26 put Claude Opus 4.8 at **87.9%** and GPT-5.2/5.4 at
**86.3%/85.4%** on ScreenSpot-Pro, against the best open specialist Holo2-235B-A22B at 70.6–78.5%.
Anthropic's own Opus 4.8 system card (2026-05-28) contains a ScreenSpot-Pro section, so this is not
purely aggregator invention — but the leaderboard values themselves are **self-reported and
unverified** by the aggregators' own admission.
Sources: <https://benchlm.ai/benchmarks/screenspot-pro>, <https://llm-stats.com/benchmarks/screenspot-pro>,
<https://www-cdn.anthropic.com/0b4915911bb0d19eca5b5ee635c80fef830a37ea.pdf>.
The premise "a general VLM hallucinates spatial facts, a specialist returns measured boxes" was
solidly true in 2024–2025 and is **half-false in mid-2026**: on *localization* the frontier VLM now
wins. What survives is the other half — a VLM emits *one* coordinate per query and no inventory, and
neither it nor the specialist emits *measured edges*.

---

## 1. The table

`Inventory` = parses the whole screen and returns N elements. `Ground` = takes one referring expression,
returns one location. This distinction is the (b) answer and it is nearly binary — see §2.

| Model / tool | Kind | Task it solves | Output schema | Local on Apple Silicon | Size | Accuracy evidence (exact split) | License | Maintenance |
|---|---|---|---|---|---|---|---|---|
| **OmniParser v2** (Microsoft) | **Inventory** | Whole-screen parse → interactable regions + icon captions + OCR text | `list[{type: "text"\|"icon", bbox: [x1,y1,x2,y2] normalized 0–1, interactivity: bool, content: str, source: "box_ocr_content_ocr"\|"box_yolo_content_yolo"}]` + annotated SoM image | **Yes, easily** — YOLOv8-n + Florence-2-base; 0.8 s/frame on a single 4090, 0.6 s on A100; CPU/MPS viable | detector ~3M params (YOLOv8n); captioner Florence-2-base 0.23B | ScreenSpot-Pro **39.5–39.6%** (desktop apps, not web). **On web: WebClick 40.7% at default YOLO params, 58.8% after threshold tuning (conf 0.05 / IoU 0.1)**; 50.6 elements detected per image | Mixed: `icon_detect` (YOLOv8) **AGPL-3.0** — commercial blocker; `icon_caption` MIT; **new `icon_detect_v3` (YOLOv9-E, added 2026/07) is MIT** | **Active** — 2026/07 update added the MIT YOLOv9-E detector (HF PR #37). No v3 product release. |
| **UI-DETR-1** (racineai) | **Inventory** | Class-agnostic UI element detection, tuned for web | `{xyxy: [...], confidence: float}` per element, sequential IDs, SoM overlay. **No labels, no text, no interactivity flag** | **Yes** — RF-DETR-M, 0.82 s/image | RF-DETR-Medium (~30M-class) | **WebClick 70.8% overall** — agentbrowse 66%, calendars 64%, humanbrowse 83%; vs OmniParser v2 58.8% tuned. 82.3 elements/image | **MIT** | Released 2025-10-01; single-author HF model, low activity — **maintenance risk** |
| **UGround-V1** (OSU-NLP + Orby) | Ground | Referring expression → click point | single string `"(x, y)"`, ints in `[0,1000)` | 2B/7B yes; 72B no | 2B / 7B / 72B (Qwen2-VL) | **ScreenSpot Web-Text/Web-Icon: 81.3/68.9 (2B), 90.9/84.0 (7B), 90.4/87.9 (72B)**. **WebClick 71.69 (2B), 82.37 (7B)**. ScreenSpot-Pro 31.1 (72B) | **Apache-2.0** | ICLR'25 Oral. **There is no UGround-V2** — the README lists only Initial + V1 (2B/7B/72B, Jan 2025). Effectively frozen. |
| **UI-TARS / 1.5** (ByteDance) | Ground + act | End-to-end GUI agent; grounding is a sub-skill | thought + atomic action with grounded `(x,y)` args | 2B/7B yes; 72B no | 2B / 7B / 72B; 1.5-7B | ScreenSpot-v2 91.6 (7B), 90.3 (72B); **1.5-7B ScreenSpot-v2 94.2**. ScreenSpot-Pro 38.1 (72B). **WebClick 64.23 (2B), 80.67 (7B)**. ⚠️ **Reproduction gap: issue #215 reports ~40 vs claimed 48 on ScreenSpot-Pro for 1.5-7B, no maintainer reply** | **Apache-2.0** (open sizes) | Active repo, but **UI-TARS-2 (Sept 2025) is a report with closed weights**; larger 1.5 gated behind `TARS@bytedance.com`. Open line is 1.5-7B. |
| **Holo1 / Holo1.5 / Holo2 / Holo3** (H Company) | Ground (+ nav) | UI localization + UI-VQA, web-first | point/box coordinates for one instruction | 3B/4B/7B/8B yes; **30B-A3B and 35B-A3B yes on 64 GB (3B active)**; 72B/235B no | Holo1 3B/7B · Holo1.5 3B/7B/72B · Holo2 4B/8B/30B-A3B/235B-A22B · **Holo3-35B-A3B** | **Web-specific:** Holo1-3B/7B WebClick **81.50 / 84.03**; **Holo1.5-7B WebClick 90.24, GroundUI-Web 84.00, Showdown 72.17**; **Holo2-8B WebClick-v1 89.5**. ScreenSpot-v2 93.31 (1.5-7B), 93.2 (2-8B), ScreenSpot-Pro 57.94 / 58.9; Holo2-30B-A3B SSPro 66.1, OSWorld-G 76.1; **Holo2-235B-A22B SSPro 78.5, OSWorld-G 79.0**; Holo3-35B-A3B OSWorld-Verified 77.8, AndroidWorld 79.3 | **Apache-2.0** for Holo1, Holo1.5-7B, **Holo2-4B/8B, Holo3-35B-A3B**. **Holo2-30B-A3B and 235B-A22B: non-commercial / research-only** | **Most active line in the field** — Holo1 (Jun 2025) → 1.5 (Sep 2025) → 2 (Nov 2025) → 2-235B (Feb 2026) → **Holo3 (Mar 2026)** |
| **UI-Venus-1.5** (Ant Group) | Ground (+ nav) | GUI grounding + navigation | point coordinates, one expression at a time | 2B/8B yes; 30B-A3B yes on 64 GB | 2B / 8B / 30B-A3B (Qwen3-VL) | **ScreenSpot-v2 96.2% — highest open number recorded.** ScreenSpot-Pro 68.4 (8B) / 69.6 (30B-A3B); OSWorld-G 70.6; UI-Vision 54.7; WebVoyager 76.0; AndroidWorld 77.6 | **Apache-2.0** | Tech report 2026-02-09/25, weights on HF `inclusionAI/ui-venus`. Active. |
| **GUI-Actor** (Microsoft) | Ground, **multi-candidate** | Coordinate-free grounding via an attention head | **attention map over visual patch tokens** from an `<ACTOR>` token — **can emit multiple candidate regions in one forward pass** | 2B/3B/7B yes | 2B / 3B / 7B (Qwen2-VL, Qwen2.5-VL) | ScreenSpot 88.3 / ScreenSpot-v2 89.5 / ScreenSpot-Pro 40.7 (44.2 with verifier) | Not stated on the project page; HF repo is `microsoft/GUI-Actor-7B-Qwen2.5-VL` — **verify before commercial use** | arXiv 2506.03143, 2025. Research artifact; low ongoing activity. |
| **Aria-UI** (Rhymes AI) | Ground | Instruction → point, high-res tolerant | point normalized to `[0,1000]` | 25.3B MoE / 3.9B active — **yes on 64 GB** | 25.3B total / 3.9B active | **ScreenSpot Web-Text 86.5 / Web-Icon 76.2**, avg 82.4 | Base Aria is **Apache-2.0**; Aria-UI checkpoints released, license not restated on the paper page — verify | Dec 2024. **Stale** — no 2025/2026 successor found. |
| **ShowUI** (Show Lab / MSR) | Ground (+ act) | Lightweight VLA for GUI | point/action | Yes | 2B | ScreenSpot avg 75.1; **Web-Text 81.7 / Web-Icon 63.6**; ScreenSpot-Pro 7.7 | Repo is MIT-family; verify checkpoint terms | CVPR 2025. **Superseded** — 5–8× worse than 2026 models on web. |
| **SeeClick** | Ground | The original GUI-grounding fine-tune | point | Yes | 9.6B (Qwen-VL) | ScreenSpot avg 53.4; ScreenSpot-Pro 1.1 | Research | **Obsolete** (ICLR 2024). Historical baseline only. |
| **CogAgent** (Zhipu) | Ground (+ act) | High-res GUI agent | point/box + action | 18B — marginal | 18B; CogAgent-9B-20241220 | ScreenSpot avg 47.4; **Web-Text 70.4 / Web-Icon 28.6**; ScreenSpot-Pro 7.7 | Research-restricted (Zhipu model license) | **Superseded.** |
| **Ferret-UI / Ferret-UI 2 / Ferret-UI Lite** (Apple) | Ground + referring + VQA | UI understanding incl. **Webpage** platform in v2 | referring/grounding text with boxes | Lite (3B) would be, **if weights existed** | UI-2: 7B/13B class; **Lite: 3B** | **Ferret-UI Lite (2026-02): ScreenSpot-v2 91.6, ScreenSpot-Pro 53.3, OSWorld-G 61.2, AndroidWorld 28.0, OSWorld 19.8** | **No public weights, no license stated.** Apple research publication only | Papers only: UI (2024-04) → UI-2 (2024-10) → **Lite (2026-02)**. **Not usable as a dependency.** |
| **OS-Atlas** | Ground | Foundation action model | point/action | 7B yes | 4B / 7B | ScreenSpot-v2 87.1; ScreenSpot-Pro 18.9 | Apache-2.0 | 2024-10. Superseded but still the standard baseline row. |
| **ScaleCUA** (OpenGVLab) | Ground + act | Cross-platform CUA incl. web | action + coords | 3B/7B yes; 32B on 64 GB | 3B/7B/32B | ScreenSpot-v2 **94.7**; ScreenSpot-Pro 59.2; OSWorld-G 60.6 | Open-source (repo); verify checkpoint terms | ICLR 2026 Oral. Active. |
| **OpenCUA** (xlang-ai) | Ground + act | Open CUA foundations | action + coords | 7B yes; 72B no | 7B / 32B / 72B | ScreenSpot-Pro **60.8**; UI-Vision 37.3; #1 OSWorld-Verified at release | Open-source; verify | NeurIPS 2025 Spotlight. Active. |
| **Fara-7B / Fara1.5** (Microsoft) | **Act only** | Pixel-in / action-out web agent | one atomic action per step, grounded args — **no inventory, no standalone box API** | 4B/9B yes; 27B on 64 GB | Fara-7B; **Fara1.5-4B/9B/27B** (Qwen3.5) | Online-Mind2Web 57.3/63.4/**72.3**; WebVoyager 80.8/86.6/**88.6**; ScreenSpot-Pro ~52 (9B); OSWorld-G Refined ~58 | **MIT** (both) | **Very active** — Fara-7B 2025-11-24, **Fara1.5 weights 2026-07-22**. SOTA open web agent. |
| **MolmoWeb** (AI2) | Act (pointing lineage) | Fully-open web agent + open data | actions with points | 4B/8B yes | 4B / 8B | WebVoyager 78.2 pass@1 / 94.7 pass@4; Online-Mind2Web 35.3 pass@1; beats Fara-7B, UI-TARS-1.5-7B, Holo1-7B at scale | Fully open (weights + MolmoWebMix data); confirm exact license | 2026-04-09. Active. |
| **WebSight / VLM_WebSight (Sightseer)** (HuggingFaceM4) | **Neither** | Screenshot → **HTML/CSS code**, not element boxes | HTML string | Yes (8B class) | ~8B | No grounding benchmark; evaluated on code/render similarity | Dataset **CC-BY-4.0**; model open | 2024. **Stale.** Interesting as a *geometry-by-reconstruction* idea (§4), useless as a detector. |
| **UICrit** (dataset) | — | 3k design critiques with **bounding boxes + design-quality ratings** | critique text + box + rating | n/a | n/a | Human-designer agreement study (UIST'24) | Research dataset | 2024. **The only design-critique-grounded box corpus found.** |
| **UIClip** (CLIP-based) | — | Design **quality score** + suggestions from a screenshot | scalar score + suggestion text — **no coordinates** | Yes (CLIP-scale) | CLIP-scale | Highest agreement with 12 human designers vs baselines (UIST'24) | Research | 2024. Stale but re-usable as a reward/scorer. |
| **CDP `DOMSnapshot.captureSnapshot`** (baseline, not a model) | **Inventory, exact** | Flattened DOM incl. iframes + shadow DOM, whitelisted **computed styles**, `offsetRects`/`clientRects`/`scrollRects`, paint order, blended background colors | typed JSON, **sub-pixel-exact layout rects** | **Yes, free, ~ms** | 0 | Exact by construction — no error term to benchmark | Browser API | Chromium-tracked, permanently maintained |

---

## 2. (b) Inventory vs. single-expression grounding — the split is almost total

**Only three entries in the table parse a whole screen: OmniParser v2, UI-DETR-1, and CDP DOMSnapshot.**
Everything else — UGround, UI-TARS, Holo*, UI-Venus, Aria-UI, ShowUI, SeeClick, CogAgent, Ferret-UI,
ScaleCUA, OpenCUA, Fara, MolmoWeb — is a **grounding** model: one referring expression in, one point out.
Verified individually on the model cards (e.g. Holo1.5-7B "grounds one referring expression at a time,"
not bulk inventory; UGround emits a single `"(x, y)"` string; UI-Venus-1.5 "generates single expressions
for element identification rather than inventories").

Two things soften the binary:

- **GUI-Actor is the interesting middle.** Its `<ACTOR>` token attends over all visual patches and it
  "can generate multiple candidate action regions in a single forward pass" at no extra inference cost
  (<https://microsoft.github.io/GUI-Actor/>). That is the only architecture in the field whose *native
  output* is a spatial distribution rather than a token-sequence coordinate. For a design reviewer that
  matters: attention mass is a continuous field you can threshold, not a single guess.
- **You can fake an inventory from a grounder, badly.** Loop N referring expressions ("the primary CTA",
  "the nav bar", …) and collect points. Cost is N forward passes; the output is points, not boxes; and
  you must already *know* what to ask for — which is precisely what a reviewer scanning for unknown
  defects does not know. Do not build on this.

**For a design reviewer the inventory kind is required and the field has almost stopped building it.**
The whole 2025–2026 research push went to grounding, because grounding is what an *agentic clicker*
needs. OmniParser is the only vendor-backed inventory tool, and its last real modelling change was
Feb 2025 (the 2026/07 update swapped in a YOLOv9-E detector — a licensing and speed change, not a new
capability).

---

## 3. (c) Web-specific accuracy — the numbers that actually apply to you

Ranked by the only benchmark built from real web screenshots. **WebClick** (H Company): 1,639 English
web screenshots from 100+ sites, three buckets — agentbrowse 36%, humanbrowse 31.8%, calendars 32.2% —
pixel-level click-target boxes, **Apache-2.0**. <https://huggingface.co/datasets/Hcompany/WebClick>

| Model | WebClick | ScreenSpot Web-Text | ScreenSpot Web-Icon | GroundUI-Web | Kind |
|---|---|---|---|---|---|
| Holo1.5-7B | **90.24** | — | — | 84.00 | Ground |
| Holo2-8B | **89.5** | — | — | — | Ground |
| Holo1-7B | 84.03 | — | — | — | Ground |
| UGround-V1-7B | 82.37 | **90.9** | **84.0** | — | Ground |
| Holo1-3B | 81.50 | — | — | — | Ground |
| UI-TARS-7B | 80.67 | — | — | — | Ground |
| Qwen2.5-VL-7B (generalist) | 74.37 | — | — | — | Ground |
| UGround-V1-72B | — | 90.4 | 87.9 | — | Ground |
| Aria-UI | — | 86.5 | 76.2 | — | Ground |
| UGround-V1-2B | 71.69 | 81.3 | 68.9 | — | Ground |
| Qwen2.5-VL-3B (generalist) | 71.15 | — | — | — | Ground |
| **UI-DETR-1** | **70.8** | — | — | — | **Inventory** |
| UI-TARS-2B | 64.23 | — | — | — | Ground |
| **OmniParser v2 (tuned)** | **58.8** | — | — | — | **Inventory** |
| **OmniParser v2 (default params)** | **40.7** | — | — | — | **Inventory** |
| ShowUI-2B | — | 81.7 | 63.6 | — | Ground |
| CogAgent-18B | — | 70.4 | 28.6 | — | Ground |
| GPT-4o (2024 generalist) | — | 12.2 | 7.8 | — | Ground |

Four things to read off this table:

1. **Web is easier than ScreenSpot-Pro and harder than ScreenSpot.** Holo1.5-7B: ScreenSpot-v2 93.3 →
   WebClick 90.2 → ScreenSpot-Pro 57.9. The dataset card states models "generally underperform on
   WebClick compared to Screenspot benchmarks."
2. **The web gap between a specialist and a stock generalist has collapsed to ~8 points at 7B.**
   Holo1.5-7B 90.24 vs Qwen2.5-VL-7B 74.37 is a 16-point gap; Holo1-7B 84.03 vs Qwen2.5-VL-7B 74.37 is
   ~10. At 2026 frontier scale (F3) the sign likely flips. Fine-tuning for GUI grounding buys much less
   on web than the ScreenSpot-Pro headlines imply, because web layouts were already in the base VLM's
   pretraining distribution.
3. **The two inventory tools are the two worst rows.** UI-DETR-1 70.8 and OmniParser 58.8 sit below
   every 7B grounder. And note this metric is *coverage* — did any produced box contain the ground-truth
   click point — not box quality. OmniParser misses ~41% of web click targets **entirely** at default
   settings.
4. **Threshold tuning is worth +18 points to OmniParser (40.7 → 58.8).** Anyone quoting OmniParser web
   performance without stating conf/IoU thresholds is quoting noise.
   Source: <https://huggingface.co/blog/paulml/ui-detr-1>

**Android/iOS transfer risk, flagged as asked:** SeeClick, CogAgent, Ferret-UI (v1), and the AndroidWorld
-optimised lines (Holo3's headline gain is AndroidWorld 67→79.3) are mobile-app-weighted. Ferret-UI 2 did
add **Webpage** as a first-class platform (iPhone/Android/iPad/Webpage/AppleTV) — but has no public
weights, so the point is moot. The three lines with *demonstrated, measured* web strength are
**Holo\*/H Company** (they built WebClick), **UGround** (web-text 90.9 / web-icon 84.0), and
**Fara/MolmoWeb** (browser-native training data). UI-Venus-1.5's 96.2 ScreenSpot-v2 is an aggregate
across mobile+desktop+web with no published web split — **treat it as unproven on web.**

---

## 4. (d) Can any of this produce design-critique geometry? Honest answer: no, and here is exactly why

**What a design reviewer needs**: element edges accurate to ~1px so that "these two cards are misaligned
by 3px" is a measurement rather than a guess; spacing gaps between *adjacent* elements; a containment
hierarchy so "inside the card" is meaningful; typography metrics (baseline, cap-height, line-height);
and *non-interactive* elements — headings, body copy, dividers, whitespace, background bands.

**What every model in the table gives**: a click-target locus for *interactable* things.

Five concrete gaps, each traceable to a design decision the field made on purpose:

| Gap | Evidence |
|---|---|
| **G1 — Grounders emit points, not boxes.** UGround, Aria-UI, UI-TARS, Holo\*, UI-Venus all return a coordinate. A point has no edges, so **alignment and spacing are not computable at all** from a grounder's output. | UGround card: output is `"(x, y)"` in `[0,1000)`. Aria-UI: "grounded pixel coordinates normalized to [0,1000]", explicitly "rather than bounding boxes." |
| **G2 — No benchmark in the field measures box quality.** All ScreenSpot variants are point-in-box. There is no IoU term, no edge-error term, nothing. So even the detectors' box accuracy is **unmeasured, not merely poor**. | <https://www.alphaxiv.org/benchmarks/national-university-of-singapore/screenspot-pro> |
| **G3 — Detector boxes are known to be wrong at the granularity that matters.** OmniParser's documented failure modes are exactly ours: "fails to detect the bounding boxes with correct granularity," OCR box precision "off, particularly with overlapping text," systematic misses at screen edges. A ±5px box error and a 3px design defect are the same magnitude — **the instrument's noise floor is above the signal.** | <https://arxiv.org/html/2408.00203v1>, <https://learnopencv.com/omniparser-vision-based-gui-agent/> |
| **G4 — No hierarchy, no containment, no z-order.** OmniParser returns a **flat list** and actively *removes overlaps* in stage 3 (OCR boxes merged with YOLO boxes, overlap removal). Nesting is destroyed by construction. UI-DETR-1 is **class-agnostic** — no types at all, just `xyxy` + confidence. "Is this button inside that card?" is unanswerable. | <https://deepwiki.com/microsoft/OmniParser/2.2-icon-detection-and-captioning-models>, <https://huggingface.co/racineai/UI-DETR-1> |
| **G5 — Interactable-only bias.** OmniParser's stated purpose is "interactable regions." A design review is mostly about things you never click: heading hierarchy, body-copy measure, whitespace rhythm, divider weight. The detector was trained to ignore them. | <https://huggingface.co/microsoft/OmniParser-v2.0> |

**The one partial workaround that is real, not hopeful.** OmniParser *does* emit an OCR text layer with
boxes alongside icons (`source: box_ocr_content_ocr`), and text boxes are the most geometrically stable
things on a page. Left edges of a text run are a genuinely usable alignment signal. That gets you
**text-column alignment**; it does not get you card/container alignment, padding, or grid inference.

**The workaround the design-critique literature actually found.** UICrit's authors report that LLMs have
poor object localization for critique, and that **visual prompting** — writing coordinate rulers along
the edges of the screenshot before showing it to the model — measurably improves the boxes the model
produces for each critique. That is a *prompt-side* fix, not a model, and it is the closest thing to a
validated technique in this specific direction. <https://arxiv.org/html/2407.08850v2>

**The reconstruction route, named for completeness and rejected.** WebSight-derived screenshot→HTML
models (`HuggingFaceM4/VLM_WebSight_finetuned`, 2M synthetic pairs, CC-BY-4.0) produce code you could
render and measure. But you would be inferring geometry you already possess, through a lossy generative
step, on a 2024 synthetic-HTML distribution that looks nothing like a modern Next.js app. Rejected.

---

## 5. Adversarial pass — the strongest case that this whole class is the wrong tool

**Stated at full strength.** Every model here was trained, benchmarked, and rewarded on one task:
*given an instruction, produce a coordinate a mouse can be sent to.* The loss function never contained a
term for edge accuracy. The benchmark metric (point-in-box) explicitly discards edge accuracy as
irrelevant. The detectors deliberately flatten hierarchy and filter to interactables. The evaluation
suites contain zero web screenshots at the professional tier and only click-target boxes at the web tier.
A design reviewer asking these models for alignment edges is asking a rangefinder for a floor plan: it
was optimised to tell you *where*, under a metric that pays nothing for *how big*, and it will answer
confidently either way. **The failure mode is silent** — the model returns a plausible box, the judge
reasons over it, and the "measurement" that was supposed to stop hallucination is itself a hallucination
with a number attached.

**And the killer for your specific case: your screenshots are web pages you render yourself.** Chrome
DevTools Protocol `DOMSnapshot.captureSnapshot` returns the flattened DOM including iframes and shadow
DOM, whitelisted **computed styles**, `offsetRects`/`clientRects`/`scrollRects`, paint order, and blended
background colors — **exact, sub-pixel, in milliseconds, for free**
(<https://chromedevtools.github.io/devtools-protocol/tot/DOMSnapshot/>). Every gap G1–G5 disappears:
exact edges, full nesting, every element including non-interactive ones, real typography metrics, real
z-order. Paying 0.8 s/frame and a 41% miss rate for a *worse* version of data you already have is a
strictly dominated choice. The CV literature exists because desktop-app agents have no DOM. **You do.**

**What would have to be true for a GUI-specialist model to earn its place anyway.** Four conditions;
three of them are real for this project:

1. **The artifact under review has no DOM.** A Figma export, a PNG from a designer, a competitor
   screenshot, a video frame, a PDF spec. This is genuinely common in design review and CDP cannot touch
   it. ✅ real.
2. **The rendered pixels and the DOM disagree, and pixels are the truth.** `overflow: hidden` clipping,
   a wrong-aspect-ratio image, a webfont that failed to load, a z-index overlap, a transform that moves
   paint away from layout. The industry converged on exactly this argument: DOM diffs miss clipping and
   aspect-ratio faults, which is why visual-testing vendors run CV over screenshots rather than DOM
   comparison (<https://percy.io/blog/visual-regression-testing-tools>). ✅ real — and it is the single
   strongest argument for keeping pixels in the loop.
3. **You need a *perceptual* inventory, not a *structural* one.** The DOM has ~3,000 nodes; a human sees
   ~40 things. A detector that returns 82 salient regions (UI-DETR-1) is a **saliency prior** that
   collapses DOM noise to what a viewer actually perceives as an element. This is a legitimate,
   non-substitutable use and it does not require box precision at all. ✅ real.
4. **The model's boxes are edge-accurate.** ❌ **Unproven and probably false** — no benchmark measures it
   (G2), the documented failure modes say otherwise (G3), and nothing in the training objective rewards
   it. Do not build any alignment/spacing arithmetic on model-produced boxes.

**Sub-check I ran to avoid assuming this away**: is there a UI benchmark that scores mAP/IoU rather than
point-in-box? The only one surfaced is the UI-DETR-1 vs OmniParser comparison, which lists mAP@0.5 and
AP@[.5:.95] as *available metrics* but **publishes neither** — it reports only WebClick point coverage.
So the honest state is: **nobody has published an IoU number for UI element detection on web screenshots.**
That absence is the finding.

**Second sub-check: is the specialist premise still true at all?** Partly refuted, per F3. Claude Opus
4.5 scored 45.7% on ScreenSpot-Pro; Opus 4.6 scored 83.1%; Opus 4.8, 87.9% — a two-release jump that put
the frontier general model 9–17 points above the best open specialist. On *localization*, the specialist
advantage is gone. What did **not** change is that a general VLM still produces **one queried coordinate,
never an inventory, and never a measured edge**. So the correct restatement of your hypothesis is:
*a specialist buys you an INVENTORY, not PRECISION; and a frontier VLM now buys you better single-target
localization than any specialist you can self-host.*

---

## 6. What a design-review agent gains from each

| Model / tool | The concrete thing it adds to a design reviewer | Verdict |
|---|---|---|
| **CDP `DOMSnapshot`** | Exact boxes, computed styles, nesting, paint order, non-interactive elements. Every alignment/spacing/grid computation you will ever want, exactly, for free. | **The primary geometry source. Non-negotiable for web.** |
| **UI-DETR-1** | A **perceptual saliency prior** — 82 regions/image, class-agnostic, MIT, 0.82 s. Collapses a 3,000-node DOM into "what a human sees as an element," and works on DOM-less artifacts (Figma PNGs, competitor shots). Best web-measured inventory model. | **Adopt for the perceptual layer.** Never for measurement. Watch the maintenance risk (single-author, 2,656 training images). |
| **OmniParser v2** | The only vendor-backed inventory tool: separates `text` vs `icon`, carries an OCR text layer with boxes, ships an `interactivity` flag and an SoM-annotated overlay image. The **OCR text boxes** are its genuinely useful design-review output (text-column left edges). New MIT `icon_detect_v3` removes the AGPL blocker. | **Adopt for the OCR/text layer + SoM overlay.** Do not rely on its icon recall (41% web miss at default thresholds). **Tune thresholds to conf 0.05 / IoU 0.1 or you lose 18 points.** |
| **Holo1.5-7B / Holo2-8B** | Best-measured **web** referring-expression grounding on the planet (WebClick 90.2 / 89.5), Apache-2.0, runs locally. Turns "the primary CTA in the hero" into a verified location so a critique can be *attached* to a region. | **Adopt as the referring-expression resolver** — the judge's "point at the thing I'm complaining about" tool. |
| **UGround-V1-7B** | Apache-2.0, the only model publishing **explicit web-text/web-icon splits** (90.9 / 84.0). Simplest possible interface: text in, `(x,y)` out. | Viable fallback to Holo. Frozen since Jan 2025 — no V2 exists. |
| **UI-Venus-1.5-8B** | Highest ScreenSpot-v2 recorded (96.2), Apache-2.0, Qwen3-VL base, current (Feb 2026). | **Hold.** No published web split — unproven on your distribution. Re-evaluate if H Company stalls. |
| **GUI-Actor-7B** | Multiple candidate regions per forward pass as an **attention field**, not a point. The only architecture whose output shape suits "find all the things like this." | **Watch.** Most interesting research direction for inventory-from-grounding; license unclear; low activity. |
| **Fara1.5 (4B/9B/27B)** | MIT, current (weights 2026-07-22), SOTA open web agent. Drives a browser to *reach* the states you want to review (logged-in, error, empty, mobile breakpoint). | **Adopt as the state-reacher**, not as a perception layer. It emits actions, not inventories. |
| **MolmoWeb-8B** | Fully open incl. training data; beats Fara-7B/UI-TARS-1.5-7B/Holo1-7B at scale on web navigation. | Alternative to Fara if licence/data provenance matters more than raw score. |
| **UI-TARS-1.5-7B** | Apache-2.0, ScreenSpot-v2 94.2, WebClick 80.67 (7B). | Adequate but strictly dominated by Holo on web, and carries an **open, unanswered reproducibility issue** (#215). |
| **Aria-UI / ShowUI / SeeClick / CogAgent / OS-Atlas** | Historical baselines. Aria-UI's web numbers (86.5/76.2) are still respectable; the rest are 5–8× behind on ScreenSpot-Pro. | **Skip.** Cite as baselines only. |
| **Ferret-UI 2 / Ferret-UI Lite** | Ferret-UI 2 explicitly includes **Webpage** as a platform; Lite is a strong 3B (ScreenSpot-v2 91.6, ScreenSpot-Pro 53.3). | **Unusable — no public weights.** Track only. |
| **UICrit** | 3k human critiques **with bounding boxes and quality ratings** — the only supervision signal in existence for "which region is the defect." Plus the validated **coordinate-ruler visual-prompting** trick. | **Adopt the visual-prompting technique immediately; hold the dataset as eval/reward material.** |
| **UIClip** | A scalar design-quality score with high agreement against 12 human designers. No coordinates. | Useful as an **A/B regression scorer** ("did this change make it worse?"), not as a grounding layer. |
| **WebSight-derived** | Nothing. Screenshot→HTML on a 2024 synthetic distribution. | **Skip.** |

---

## 7. Recommended pairing

**CDP `DOMSnapshot.captureSnapshot` for measurement + UI-DETR-1 for perceptual saliency + Holo2-8B
(Apache-2.0) for referring-expression grounding — with the judge forbidden from computing any distance
from a model-produced box.**

The division of labour, stated as a contract:

- **Geometry is DOM-only.** Every alignment edge, spacing gap, and inferred grid comes from
  `clientRects` + computed styles. This is exact, so the judge's spatial claims are measurements and the
  original hypothesis (measured, not hallucinated) is fully satisfied — just not by a CV model.
- **Salience is CV-only.** UI-DETR-1 (MIT, 0.82 s, 82 regions/image, WebClick 70.8%) answers "what does a
  viewer perceive as one element" — the question the DOM cannot answer because it has no notion of a
  perceptual unit. Union its regions with DOM nodes by IoU to attach a `perceptually_salient` flag; drop
  DOM nodes with no CV support from the review surface. Add **OmniParser v2's OCR layer** (MIT
  `icon_detect_v3`, thresholds pinned at conf 0.05 / IoU 0.1) when you need text spans the DOM splits
  across inline elements.
- **Reference resolution is grounder-only.** Holo2-8B turns the judge's natural-language target
  ("the secondary button in the pricing card") into a point; you then snap that point to the enclosing
  DOM node and inherit its exact box. **This is the pattern that makes a grounder useful despite G1** —
  the model supplies *identity*, the DOM supplies *geometry*.
- **Fallback for DOM-less artifacts** (Figma PNG, competitor screenshot, video frame): UI-DETR-1 +
  OmniParser OCR + Holo2-8B alone, with **all numeric spacing/alignment claims suppressed** and the
  critique restricted to qualitative judgments. Emit an explicit `geometry_source: cv_only` flag so a
  downstream reader knows the measurements are absent, not zero.
- **Prompt-side**: apply UICrit's coordinate-ruler visual prompting on every screenshot handed to the
  judge VLM. Cheapest measured win available.

Why Holo2-8B over the alternatives: it is Apache-2.0 (Holo2-30B-A3B and 235B-A22B are **not** — research
licences), it is 8B so it runs on an M-series laptop, it is the current member of the only actively
maintained line in the field (Holo1→1.5→2→2-235B→**Holo3**, five releases in ten months), and it holds
the best *measured web* grounding number in existence (WebClick-v1 89.5, ScreenSpot-v2 93.2). If you can
spend 64 GB and accept a research licence, **Holo3-35B-A3B is Apache-2.0 with only 3B active parameters**
— re-benchmark it on WebClick before switching, since H Company has not published its web split.

**Falsifier for this recommendation**: if a future benchmark publishes **IoU/mAP** for UI element
detection on web screenshots and a model clears ~0.9 mAP@[.5:.95], G2–G3 dissolve and the CV layer could
take over measurement for DOM-less artifacts. Until such a number exists, the DOM does the measuring.

---

## 8. Blockers and uncertainties, named

- **Apple-Silicon runnability is inferred, not tested.** Parameter counts and MoE active-param figures
  are from model cards; I did not verify MLX / llama.cpp / mlx-vlm support for the **Qwen3-VL** (Holo2,
  UI-Venus-1.5) or **Qwen3.5** (Holo3, Fara1.5) vision stacks. Newest base architectures typically lag
  MLX by weeks-to-months. **Verify before committing.**
- **The F3 leaderboard values are self-reported aggregations.** llm-stats states all 25 entries are
  self-reported, unverified. Anthropic's system card confirms the *evaluation exists*; I could not
  extract the exact figure (both system-card PDFs exceeded the fetch size limit). Treat 87.9% as
  indicative, not established. Several leaderboard entries (Muse Spark, Muse Glimmer, Qwen3.8 Max) I
  could not independently corroborate.
- **H Company's own Holo2-235B claim (78.5% ScreenSpot-Pro) disagrees with benchlm's listing (70.6%).**
  Different harnesses/prompts. Expect ±8 points between any two sources on this benchmark.
- **UI-TARS-1.5-7B's ScreenSpot-Pro number is disputed** — a user reproduces ~40 against a claimed 48,
  using the official prompt template and post-processing, with no maintainer response
  (<https://github.com/bytedance/UI-TARS/issues/215>).
- **GUI-Actor's license is not stated** on the project page. Verify on the HF repo before use.
- **Aria-UI's checkpoint license** is not restated on the paper site (base Aria is Apache-2.0).
- **UI-DETR-1's training set is 2,656 images** collected Jan–Jun 2024. Its 70.8% WebClick result is
  strong for that budget but the model is one person's fine-tune with no institutional backing.
- **`ScreenSpot-v2` numbers are not comparable across papers** — some report ScreenSpot, some
  ScreenSpot-v2, some "agent setting" vs "standard setting," and the web split is published by only a
  handful (UGround, Aria-UI, ShowUI, CogAgent).

---

## 9. Sources

- ScreenSpot-Pro paper: <https://arxiv.org/html/2504.07981v1> · benchmark repo: <https://github.com/likaixin2000/ScreenSpot-Pro-GUI-Grounding> · metric: <https://www.alphaxiv.org/benchmarks/national-university-of-singapore/screenspot-pro>
- SeeClick / ScreenSpot metric: <https://arxiv.org/html/2401.10935>
- Leaderboards: <https://gui-agent.github.io/grounding-leaderboard/> · <https://benchlm.ai/benchmarks/screenspot-pro> · <https://llm-stats.com/benchmarks/screenspot-pro>
- OmniParser: <https://github.com/microsoft/OmniParser/blob/master/README.md> · <https://huggingface.co/microsoft/OmniParser-v2.0> · <https://arxiv.org/html/2408.00203v1> · <https://deepwiki.com/microsoft/OmniParser/2.2-icon-detection-and-captioning-models> · <https://learnopencv.com/omniparser-vision-based-gui-agent/>
- UI-DETR-1: <https://huggingface.co/blog/paulml/ui-detr-1> · <https://huggingface.co/racineai/UI-DETR-1>
- UGround: <https://github.com/OSU-NLP-Group/UGround/blob/main/README.md> · <https://huggingface.co/osunlp/UGround-V1-7B>
- UI-TARS: <https://huggingface.co/ByteDance-Seed/UI-TARS-1.5-7B> · <https://arxiv.org/pdf/2501.12326> · <https://arxiv.org/html/2509.02544v1> · <https://github.com/bytedance/UI-TARS/issues/215>
- H Company: <https://hcompany.ai/blog/holo-1-5> · <https://huggingface.co/Hcompany/Holo1.5-7B> · <https://hcompany.ai/holo2> · <https://huggingface.co/Hcompany/Holo2-8B> · <https://huggingface.co/Hcompany/Holo2-235B-A22B> · <https://huggingface.co/Hcompany/Holo3-35B-A3B> · <https://huggingface.co/datasets/Hcompany/WebClick> · <https://arxiv.org/pdf/2506.02865>
- UI-Venus-1.5: <https://arxiv.org/html/2602.09082v1> · <https://huggingface.co/inclusionAI/UI-Venus-1.5-8B> · <https://github.com/inclusionAI/UI-Venus>
- GUI-Actor: <https://microsoft.github.io/GUI-Actor/> · <https://huggingface.co/microsoft/GUI-Actor-7B-Qwen2.5-VL>
- Aria-UI: <https://arxiv.org/html/2412.16256v1> · <https://ariaui.github.io/>
- ShowUI: <https://arxiv.org/pdf/2411.17465>
- Ferret-UI: <https://machinelearning.apple.com/research/ferretui-mobile> · <https://machinelearning.apple.com/research/ferret-ui-2> · <https://machinelearning.apple.com/research/ferret-ui>
- ScaleCUA: <https://github.com/OpenGVLab/ScaleCUA> · OpenCUA: <https://opencua.xlang.ai/>
- Fara: <https://www.microsoft.com/en-us/research/articles/fara1-5-computer-use-agent/> · <https://huggingface.co/microsoft/Fara-7B> · <https://github.com/microsoft/fara>
- MolmoWeb: <https://arxiv.org/abs/2604.08516>
- WebSight: <https://huggingface.co/datasets/HuggingFaceM4/WebSight> · <https://huggingface.co/HuggingFaceM4/VLM_WebSight_finetuned>
- Design critique: UICrit <https://arxiv.org/html/2407.08850v2> · UIClip <https://arxiv.org/html/2404.12500v1> · <https://uimodeling.github.io/uiclip/>
- DOM baseline: <https://chromedevtools.github.io/devtools-protocol/tot/DOMSnapshot/> · <https://percy.io/blog/visual-regression-testing-tools>
- Anthropic Opus 4.8 system card: <https://www-cdn.anthropic.com/0b4915911bb0d19eca5b5ee635c80fef830a37ea.pdf>
