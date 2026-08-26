# A14 — Red-team: the two load-bearing premises

Adversarial brief. Default disposition: refute. Evidence gathered 2026-08-26; web-current past the ~May 2026 cutoff.

---

## Premise A — "Running a local vision model on the M1 Max is worth doing for web design review"

### Strongest disconfirming evidence

1. **The 64 GB-runnable class is at or near chance on exactly this task.** In *MLLM as a UI Judge* (arXiv 2510.08783), the open-weight entrant (Llama-3.2-11B-Vision) scored **53% on pairwise design preference — statistical coin-flip** — while GPT-4o/Claude 3.5 hit ~60% overall and **90-93% when human preference was clear**. It also diverged hardest on the subjective factors design review lives on ("Interesting": 4.50 vs human 5.82). https://arxiv.org/abs/2510.08783
2. **The open-vs-frontier gap on GUI understanding is ~17 points at the top — and the top open model doesn't fit in 64 GB.** ScreenSpot-Pro leaderboard (updated June 2026): Claude Opus 4.8 **0.879** native; best open model Qwen3.5-122B-A10B **0.704** (rank 6) — a 122B model, over the 64 GB budget at usable quant. The class that actually fits (Qwen3-VL-32B / Qwen3.6-27B / 30B-A3B) sits below that. https://llm-stats.com/benchmarks/screenspot-pro · https://gui-agent.github.io/grounding-leaderboard/ · https://insiderllm.com/guides/vision-models-locally/
3. **Latency is disqualifying for the only quality-adjacent local class.** MacStories measured Qwen2.5-VL-72B taking **~3.5 minutes to process one full-resolution screenshot on an M3 Ultra with 512 GB** (~100 GB RAM in use). The M1 Max has half the memory bandwidth (400 vs 819 GB/s) and a fraction of the GPU; the 72B class lands at roughly 5-10+ min/screenshot there. https://www.macstories.net/notes/notes-on-early-mac-studio-ai-benchmarks-with-qwen3-235b-a22b-and-qwen2-5-vl-72b/
4. **The privacy/cost argument buys ~nothing here.** A screenshot is ~1,600 input tokens under Claude's vision pricing (`(w×h)/750`), ≈ **$0.005-0.05 per review** depending on model tier — dozens of reviews/day costs under a dollar. https://docs.anthropic.com/en/docs/build-with-claude/vision The MacStories case *for* local VLMs rests explicitly on "not having to upload **private** images" — the operator's screenshots are of his own non-sensitive marketing and admin apps, so the one argument that carried that win is void here.
5. **Design2Code human eval:** GPT-4o-generated pages won **92%** of pairwise human preferences vs the baseline; fine-tuned open Design2Code-18B won 54%, WebSight-8B 45%. Webpage-level visual understanding is a frontier-gap task, not a solved-small task. https://aclanthology.org/2025.naacl-long.199.pdf

### Mechanism of failure

Design critique quality scales with **general multimodal reasoning**, which is precisely the axis on which open 27-72B models trail frontier hosted models. Worse than "worse": a reviewer at chance on pairwise preference emits fluent, confident, *directionally random* advice — the operator cannot tell which half to discard, so local output is **actively misleading, not degraded**. And the local stack is a two-horned dilemma: the fast class (27-32B dense, 3B-active MoE) is quality-inadequate; the quality-nearest class (72B+) is latency-inadequate on this hardware. Add maintenance: the open-VLM frontier turned over three times in ~12 months (Qwen3-VL → 3.5 → 3.6, per the local-VLM guides above), each with fresh quant/runtime/prompt-format churn — a standing engineering tax with no quality dividend.

### The analogy audit (this is where Premise A actually dies)

The speech and OCR wins had four properties; design critique has none of them:

| Property | ASR (Parakeet/Whisper) | Cloud OCR | Design critique |
|---|---|---|---|
| Open weights ≈ task frontier | **Yes — the Open ASR leaderboard is topped by open 0.6-2.5B models** (Canary Qwen 2.5B, 5.63% WER; Parakeet-TDT-0.6B #3 at 6.05%) | Specialist ≈ SOTA on hard docs | No — 17-pt gap, above (§2) |
| Crisp ground truth | WER | CER | **None** — the metric is taste |
| High volume | Continuous audio streams | Batch documents | Dozens of screenshots/day |
| Latency-sensitive | Real-time (RTFx 3386 matters) | Bulk throughput matters | Async; a 30 s API call is fine |

https://huggingface.co/blog/open-asr-leaderboard · https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2

Local speech won because **going local sacrificed zero quality** — the open model *was* the frontier — on a narrow, measurable, high-volume, latency-sensitive task. Local design review sacrifices the frontier on a broad, unmeasurable, low-volume, latency-tolerant task. The analogy transfers on zero of four properties.

### Conditions under which A would nonetheless hold

- **High-volume screening, not review**: crawling hundreds of pages nightly and flagging gross anomalies (broken layout, missing images) for frontier follow-up — volume economics can flip, and a small fast MoE suffices for gross defects.
- Screenshots become genuinely sensitive (client work under NDA, pre-launch confidential material).
- Open weights reach frontier parity on visual judgment (the ASR condition). Not currently in evidence; the gap on GUI benchmarks remains wide.

### Verdict

**Premise A fails.** The analogy that motivates it inverts on every property that made speech/OCR wins; the runnable class is chance-level on design preference; the near-quality class is minutes-per-screenshot on this hardware; and the privacy/cost benefit rounds to zero. — REFUTED for "review"; a narrow screening role survives.

---

## Premise B — "A specialist CV layer (detection, grounding, segmentation, saliency) adds real value over a frontier VLM + good screenshot + good prompt"

### Strongest disconfirming evidence

1. **The field's own trajectory: parser pipelines were crutches for pre-grounding models, and native models blew past them.** OmniParser V2 was SOTA on ScreenSpot-Pro at **39.5%** in Feb 2025 (Microsoft's own announcement); by mid-2026 Claude Opus 4.8 scores **87.9% natively** — the parser pipeline's ceiling is less than half the raw frontier model. https://www.microsoft.com/en-us/research/articles/omniparser-v2-turning-any-llm-into-a-computer-use-agent/ · https://llm-stats.com/benchmarks/screenspot-pro
2. **Microsoft — OmniParser's org — dropped the parser in its successor agent.** Fara-7B (Nov 2025): "It does **not rely on separate models to parse the screen**, nor on any additional information like accessibility trees." https://www.microsoft.com/en-us/research/blog/fara-7b-an-efficient-agentic-model-for-computer-use/
3. **End-to-end beats module pipelines when the base model is strong.** UI-TARS (screenshot-only, end-to-end) outperforms "heavily wrapped" GPT-4o frameworks with expert-crafted parsing on OSWorld/AndroidWorld. https://arxiv.org/abs/2501.12326 UGround (ICLR 2025 oral): structured representations "introduce **noise, incompleteness, and increased computational overhead**." https://arxiv.org/abs/2410.05243 Precedent in document AI: OCR-free Donut beat OCR→LM pipelines by removing OCR **error propagation** (ECCV 2022). https://github.com/clovaai/donut
4. **Frontier labs' revealed preference**: Anthropic computer use = screenshots + natively predicted coordinates, no parsing layer (since Claude 3.5 Sonnet, Oct 2024). https://simonwillison.net/2024/Oct/22/computer-use/ · https://workos.com/blog/anthropics-computer-use-versus-openais-computer-using-agent-cua
5. **Honest negative finding**: I could not pin a citable 2026 table showing set-of-mark prompting losing *outright* to raw screenshots on frontier models (search-level summaries report such ablations — SoM below screenshot-only, and stacking inputs on SoM dropping performance — but I could not trace the numbers to a verifiable table this session). Treat "SoM actively hurts" as plausible-unproven; "SoM no longer needed" is proven by §1-§4.

### Mechanism of failure

Every specialist module adds a **new error source upstream of the judge**: a wrong box, phantom icon, or misgrounded label enters the frontier model's context as authoritative-looking structure, and the model — trained to trust its prompt — reasons from it (the Donut/OCR error-propagation mechanism, transplanted). Meanwhile the module's *positive* contribution decays toward zero as native perception improves — the OmniParser arc (§1) ran SOTA→outclassed-2× in ~16 months. For **critique** specifically the case is worse than for agents: critique has no grounding bottleneck at all (nothing needs clicking); it needs judgment plus a handful of *measurements* — and a detector emits boxes, not verdicts.

**The steelman that must be answered**: frontier VLMs genuinely fail pixel-precision perception — *Vision Language Models Are Blind* (ACCV 2024): ~58.6% average on trivial tasks like "do these two lines intersect," Claude 3.5 Sonnet best at 74.9%. https://vlmsareblind.github.io/ · https://openaccess.thecvf.com/content/ACCV2024/papers/Rahmanzadehgervi_Vision_language_models_are_blind_ACCV_2024_paper.pdf Overlap, 1-px misalignment, and contrast are design-review bread and butter. But this argues for a **deterministic browser layer, not a learned CV layer**: `getBoundingClientRect` arithmetic, computed styles, and axe-core contrast checks answer these questions *exactly*, for free, forever — a learned detector answers them approximately, with weights to maintain. (EntWorld's ablation — a11y-tree+screenshot 53.7% vs screenshot-only 15.6% — shows structured side-info has real value, but the winning structure came from the **browser**, not from a vision model. https://arxiv.org/abs/2601.17722)

### Key question (c): base rate of abandonment

Perception scaffolds bolted onto general models have run a **~18-month half-life**: SoM-for-GPT-4V (2023) → native coordinates (Oct 2024); a11y-tree-only web agents (2023) → pixel-native agents (2024-25); OmniParser SOTA (Feb 2025) → outclassed 2× by native grounding, and its own org shipping a parser-free successor (Nov 2025). OmniParser remains maintained (YOLOv9-E detector added 2026/7 — https://github.com/microsoft/OmniParser), but its surviving niche is explicitly "models **without** native grounding" — i.e., the specialist layer is now a prosthetic for weak models. Bolting it onto a frontier judge buys the pipeline's failure modes without its one remaining use case; bolting it onto a *local* judge (Premise A + B combined) caps the system at the weak judge anyway.

### Key question (d): worst maintenance-to-marginal-accuracy component

**Saliency.** Its training corpora are ancient and proxy-based — SALICON (2015) is *mouse-tracking* standing in for gaze; MIT300 is 300 natural images / 39 observers from ~2012 (https://arxiv.org/pdf/2003.04942); design-specific importance models (UMSI line) date to ~2020 with no at-scale successor. Its output is an **unfalsifiable heatmap**: with no eye-tracking on the operator's actual audience, no observation can ever prove it wrong, so its marginal accuracy is not merely low but *unmeasurable* — the worst possible denominator. Runner-up: the OmniParser-class element detector (GPU-tuned multi-model stack, quarterly version churn, superseded by native grounding for any frontier judge).

### Conditions under which B would nonetheless hold

- The judge is a weak/local model without native grounding (i.e., B is rescued only by committing Premise A's error).
- Pixel-exact measurements are required — but there deterministic browser instrumentation strictly dominates learned CV.
- Massive-batch cost engineering, where a cheap detector pre-filters which pages earn a frontier call.

### Verdict

**Premise B fails for a frontier judge.** Every actor with skin in the game — including the team that built the best parser — moved to raw pixels as models got native perception; the residual VLM blindness is real but is answered by the DOM, not by more vision models. — REFUTED.

---

## If both premises are false: build this instead

Build a **capture-and-instrument harness around a frontier hosted VLM**, with zero learned components of our own. Concretely: a Playwright/CDP pipeline that produces (1) device-accurate screenshots — full-page plus per-viewport, correct DPR, both themes; (2) a compact **deterministic facts digest** computed from the live DOM at capture time — element bounding boxes and overlap/overflow arithmetic from `getBoundingClientRect`, computed-style inventory (fonts, spacing scale, color tokens), axe-core contrast and a11y violations — exactly the pixel-precision facts frontier VLMs are measurably blind to (vlmsareblind.github.io), obtained exactly rather than approximately; and (3) one well-engineered prompt encoding the operator's design standards, sent with screenshot + digest to the current frontier VLM. This keeps the only learned component *rented*: it upgrades for free on every API model release — the highest-option-value position under the observed ~18-month half-life of perception scaffolds — while every specialist function the CV stack promised (detection→bounding boxes, grounding→DOM node identity, segmentation→element tree, saliency→drop it, it was never falsifiable) is delivered by the browser's own render tree at zero maintenance and perfect accuracy. The M1 Max's role is running browsers, not models; the local-speech analogy stays honored where it's true (transcription of review dictation, where open weights genuinely are the frontier) and is retired where it was false.

---
*A14 · red-team · 2026-08-26 · saturation reached at 14 web calls; the one unpinnable claim (SoM strictly losing to raw screenshots on frontier models) is flagged as such in B§5 rather than laundered.*
