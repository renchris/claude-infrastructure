# A1 — Local open-weight VLMs for web-UI screenshot understanding (M1 Max / 64 GB)

Agent A1 · researched 2026-08-26 · every quantitative claim carries a URL · estimates are
labelled `[EST]`.

## Headline

**The `-VL` suffix is dead and that is the whole story.** Qwen shipped `Qwen3.5` on
2026-02-16 with **every size natively multimodal via early text-vision fusion — no separate
VL variant** ([Qwen3.5 blog](https://qwen.ai/blog?id=qwen3.5),
[Overshoot VLM survey 2026](https://www.overshoot.ai/blogs/vlm-survey-2026)). The March-2026
corpus this repo holds predates that. On the live **ScreenSpot-Pro** leaderboard (last updated
**2026-08-26**), the top open-weight entries are `Qwen3.5-122B-A10B` 0.704 and
**`Qwen3.5-27B` 0.703** — the 27B is statistically tied with a model 4.5× its size and is the
best UI-grounding model that fits on this machine
([llm-stats](https://llm-stats.com/benchmarks/screenspot-pro)).

**But the benchmark that matches the actual job says every one of these models fails it.** See
§6 (adversarial pass) before installing anything.

---

## 1. Ranked table

Sizes are the Ollama Q4-class download unless noted. "px/token" = image pixels represented by
one vision token — the physical limit on how small a detail can survive tokenization.

| # | Model | Params | Released | Vision encoder · resolution scheme · px/token | Quantized on-disk | Apple-Silicon support | Measurably GOOD at | Measurably BAD at | License |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Qwen3.5-27B** | 27B dense, hybrid Gated-DeltaNet + gated attention, 64 layers | 2026-02-24 | Native/dynamic res, `smart_resize`; patch 16 × 2×2 spatial merge → **32×32 px/token**; cap `IMAGE_MAX_TOKEN_NUM=16384` ≈ 16.8 Mpx — **no forced downscale of a 2560×1600 shot** ([vision_process.py](https://github.com/QwenLM/Qwen3-VL/blob/main/qwen-vl-utils/src/qwen_vl_utils/vision_process.py)) | **17 GB** Ollama `qwen3.5:27b`; **16.1 GB** [mlx-community 4bit](https://huggingface.co/mlx-community/Qwen3.5-27B-4bit) | Ollama `vision` tag at 27b ([library](https://ollama.com/library/qwen3.5)); mlx-vlm converted; MLX 4/8-bit on HF | **ScreenSpot-Pro 70.3** · OCRBench 89.4 · RefCOCO avg 90.9 · V\* 93.7 · CountBench 97.8 · MMMU-Pro 75.0 · MMStar 81.0 ([model card](https://huggingface.co/Qwen/Qwen3.5-27B)) | Dense 27B prefill on M1 Max — 4,000 vision tokens for one 2560×1600 shot (§4). Thinking-on **hurts** grounding | Apache-2.0 |
| 2 | **Qwen3.5-35B-A3B** | 35B total / **3B active** MoE | 2026-02-24 | same as above | **24 GB** Ollama `qwen3.5:35b`; ~22 GB MLX | **The only model Ollama's MLX preview explicitly accelerates** ([ollama.com/blog/mlx](https://ollama.com/blog/mlx)) | **OCRBench 91.0** (best in family) · ScreenSpot-Pro 68.6 · MMStar 81.9 · MMMU-Pro 75.1 · CountBench 97.8 ([card](https://huggingface.co/Qwen/Qwen3.5-35B-A3B)) | 1.7 pts behind 27B on ScreenSpot-Pro; RefCOCO 89.2 < 27B's 90.9 | Apache-2.0 |
| 3 | **Qwen3.5-9B** | 9.65B dense | 2026-03-02 | same | **6.6 GB** Ollama; MLX 4bit ~5.5 GB | Ollama + [mlx-community/Qwen3.5-9B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit) | ScreenSpot-Pro 65.2 · OCRBench 89.2 · RefCOCO 89.7 · CountBench 97.2 ([card](https://huggingface.co/Qwen/Qwen3.5-9B)) · **won a 3-way hands-on**: read fine print, correct count + names + file sizes off a busy LM Studio UI where Ministral-3 invented three fake rows ([XDA, 2026](https://www.xda-developers.com/tested-gemma-4-qwen-3-5-ministral-3-for-vision-tasks-only-one-understood-the-assignment/)) | 5.1 pts below 27B on ScreenSpot-Pro | Apache-2.0 |
| 4 | **Qwen3.8-27B** | 27B dense, native VL, 262K ctx | **2026-08-14** (12 days old) | same family | [mlx-community/Qwen3.8-27B-4bit](https://huggingface.co/mlx-community/Qwen3.8-27B-4bit) ~16 GB | MLX conversions already on HF | Qwen-Max-class open release ([repo](https://github.com/QwenLM/Qwen3.8)); native vision per [Codersera guide](https://codersera.com/blog/qwen-3-5-complete-guide-2026/) | **No published ScreenSpot-Pro / OCRBench for the open 27B.** The 0.845 on the leaderboard is *Qwen3.8-Max*, closed. Treat as unbenchmarked | Apache-2.0 |
| 5 | **GLM-4.6V-Flash** | 9B | 2025-12-08 | AIMv2-Huge ViT + MLP projector, 2D-RoPE + bicubic interp, **arbitrary aspect ratio up to 200:1**; 128K ctx ([VentureBeat](https://venturebeat.com/ai/z-ai-debuts-open-source-glm-4-6v-a-native-tool-calling-vision-model-for)) | ~5–6 GB at 4-bit `[EST]` | mlx-community collection lists it; no Ollama `vision` tag as of Aug 2026 (`glm-ocr` is the only tagged GLM) | **Native multimodal function-calling** — the model can call crop/zoom/chart tools on the image itself; **pixel-accurate HTML/CSS/JS reconstruction from a UI screenshot**; box grounding `[[xmin,ymin,xmax,ymax]]` ([Z.ai docs](https://docs.z.ai/guides/vlm/glm-4.6v)); Ref-L4 87.7 · OCRBench 84.7 · MMBench 86.9 · AI2D 89.2 | **Worst hallucinator on no-diff pairs: 24.2% false positives** (DiffSpot); overall DiffSpot 23.8% | **MIT** |
| 6 | **Gemma 4** (31B dense / 26B-A4B / 12B) | 30.7B / 25.2B-3.8B-active / 11.95B | 2026-07-02 | 550M ViT patch-16, aspect-ratio-preserving resize, **hard token budget ∈ {70,140,280,560,1120}** — 1120 is the ceiling ([tech report](https://arxiv.org/html/2607.02770v1), [llama.cpp note](https://dev.to/someoddcodeguy/a-quick-note-on-gemma-4-image-settings-in-llamacpp-39ng)). 12B is **encoder-free**: raw 48×48×3 RGB patches projected straight into the LLM | 26b ~16 GB, 31b ~18 GB `[EST]`; Ollama `gemma4` vision-tagged at e2b/e4b/12b/26b/31b | First-class: Ollama vision tag + mlx-vlm supports `gemma-4-26b-a4b-it` | InfographicVQA **92.0** (31B) / 89.3 (26B) · MMMU-Pro 76.9 · OmniDocBench-1.5 edit-dist 0.131 (lower better) · audio + 256K ctx | **The 1120-token cap is the disqualifier**: on a 2560×1600 shot that is ~3,657 px² ≈ **60×60 px per token**, ~3.5× coarser than Qwen. **No published ScreenSpot / ScreenSpot-Pro number at all**, and no grounding-output claim in the card | Apache-2.0 |
| 7 | **InternVL3.5-30B-A3B** | 30B/3B active (family 1B–241B) | 2025-08-26 | AnyRes dynamic tiling (448-px tiles + thumbnail) | ~18 GB `[EST]` | No Ollama tag; transformers/vLLM path; MLX not first-class | ScreenSpot 86.6 · ScreenSpot-v2 87.3 · OSWorld-G 42.4 ([arXiv 2508.18265](https://arxiv.org/html/2508.18265v1)) | **DiffSpot 15.0% — last of 13 models tested.** A year old; superseded on every axis by Qwen3.5. Overshoot flags "lower download adoption, limited SGLang docs" | Apache-2.0 |
| 8 | **Molmo2-8B** | 8B (+ 4B, 7B-O) | 2026-01-15 (v4 2026-04-02) | Not disclosed in abstract | ~5 GB `[EST]` | mlx-vlm lists Molmo family | **Point-driven grounding** — the only family whose primary output primitive is a *point*, not a box; video pointing F1 38.4 vs Gemini 3 Pro 20.0 ([arXiv 2601.10611](https://arxiv.org/abs/2601.10611)); fully open weights **+ data + training code** | **Zero published OCR / document / screenshot benchmarks.** Its wins are video counting/tracking, not static text-dense UI. 36,864 ctx | CC-BY-4.0 (Apache-2.0 per Overshoot for some variants) |
| 9 | **MiniCPM-V 4.6** | 1.3B | 2026-05-11 | phone-class | ~1 GB `[EST]` | Ollama `minicpm-v` is still 8b | Reaches Qwen3.5-2B level on OpenCompass/RefCOCO/OCRBench at 1.3B ([RITS](https://rits.shanghai.nyu.edu/ai/minicpm-v-4-6-a-1-3b-multimodal-model-built-for-phones/)) | Nowhere near UI-grounding grade. Useful only as a sub-second triage/router pass | Apache-2.0 |
| 10 | **Mistral Small 4 / Pixtral 12B** | 24B / 12B | 2026-03-16 / 2024-09-17 | Pixtral: native res, no external preprocessor | Ollama `mistral-small3.2:24b` vision-tagged | Ollama + mlx-vlm both list Pixtral | Small 4 unifies Magistral+Pixtral+Devstral ([Serenities](https://serenitiesai.com/articles/mistral-ai-models-2026-complete-guide)); Apache-2.0 with a hosted API escape hatch | **No competitive UI-grounding or ScreenSpot number published anywhere I could find in 2026.** Not in the ScreenSpot-Pro top 25 | Apache-2.0 |
| 11 | **Llama 4 Scout / Maverick** | 16×17B / 128×17B MoE | 2025-04 | Natively multimodal MoE, no external vision encoder | Ollama `llama4` vision-tagged | Ollama tag exists | Native early-fusion multimodality; huge context | **Absent from the ScreenSpot-Pro top 25 entirely.** Behemoth weights never shipped; Meta's 2026 frontier ("Muse Spark" 0.841, "Muse Glimmer-30B" 0.754) is **closed** ([Codersera](https://codersera.com/blog/llama-4-complete-guide-2026/)) | Llama Community Licence |
| — | *Kimi K2.5* | 1T / 32B active | 2026-04-20 | — | ~500 GB+ | none | **Best open model on DiffSpot at 42.2%** — better than Claude Opus 4.7 (38.9%) | **Cannot run on 64 GB.** Listed only to mark the ceiling | Modified MIT |

Not covered here by design (sibling agents): GUI specialists — **UI-Venus-1.5** ([arXiv 2602.09082](https://arxiv.org/pdf/2602.09082)), **MAI-UI** ([2512.22047](https://arxiv.org/pdf/2512.22047)), OS-Atlas, UGround, UI-TARS — and detection/segmentation. One crossover result belongs here anyway: see §6.4.

---

## 2. Resolution handling — the axis that actually decides this

Three distinct designs are in play, and they are **not** close:

| Scheme | Who | Behaviour on a 2560×1600 screenshot |
|---|---|---|
| **Native/dynamic (NaViT-like) with a huge cap** | Qwen3.5, Qwen3-VL | `smart_resize` keeps aspect ratio, forces both dims divisible by `patch×merge`, and only downscales if pixels exceed `max_pixels`. Default cap `IMAGE_MAX_TOKEN_NUM=16384`, `MAX_RATIO=200`. At 32×32 px/token, 4.10 Mpx → **4,000 tokens, zero downscale.** ([source](https://github.com/QwenLM/Qwen3-VL/blob/main/qwen-vl-utils/src/qwen_vl_utils/vision_process.py)) |
| **Aspect-preserving with a HARD token ceiling** | Gemma 4 | Budget is one of {70,140,280,560,1120}. 1120 is the max the model accepts. 4.10 Mpx / 1120 ≈ **3,657 px² ≈ 60×60 px per token.** Google's own guidance puts 280/560 at "charts, screens, UI reasoning" and reserves 1120 for "OCR, small text" — i.e. even the ceiling is an OCR budget, not a layout-fidelity budget. |
| **AnyRes tiling (448-px tiles + global thumbnail)** | InternVL3.5 | Preserves local detail per tile but the model reasons over tile-local crops plus a low-res global view; cross-tile 1–2 px alignment comparisons are the known weak case, and its DiffSpot score (15.0%) is consistent with that. |
| **Arbitrary aspect ratio, no stated cap** | GLM-4.6V | Up to 200:1 panoramas; 128K ctx. Docs do not publish a max-image-token figure — treat as unverified. |

**Winner for small-text and 1–2 px alignment evidence: Qwen3.5 / Qwen3-VL,** by a factor of
~3.5× in linear sampling density over Gemma 4, and it is the only family where the ceiling is
high enough that a full-page 2× Retina capture is not silently resampled.

**Caveat that undoes some of this locally:** the 32 px/token figure and the 16384 cap come from
`qwen-vl-utils`. **Ollama does not expose `min_pixels`/`max_pixels`** — its documented behaviour
is to resize large images down automatically. If you want the benchmark geometry, drive
`mlx-vlm` or `transformers` with explicit `max_pixels`, not `ollama run`.

---

## 3. Grounding — who can actually point

"Spatial recognition" in the useful sense means the model emits coordinates you can draw.

| Model | Output primitive | Format | Evidence |
|---|---|---|---|
| Qwen3.5 / Qwen3-VL | **box + point** (and 3D box) | normalized **0–1000** `[x1,y1,x2,y2]`; convert `x_px = x/1000 * img_w` | [Qwen3-VL README](https://github.com/qwenlm/qwen3-vl); RefCOCO avg **90.9** (27B) is a referring-expression *localization* score and cannot be obtained without box output |
| GLM-4.6V / -Flash | **box** | `[[xmin,ymin,xmax,ymax]]` in Quick-Start | [Z.ai docs](https://docs.z.ai/guides/vlm/glm-4.6v); Ref-L4-test 88.9 / 87.7 |
| InternVL3.5 | **box** | RefCOCO-style | ScreenSpot 86.6 / OSWorld-G 42.4 imply click-point emission |
| **Molmo2** | **point** (+ pixel tracking) | pointing, natively | [arXiv 2601.10611](https://arxiv.org/abs/2601.10611) — the only family designed around points rather than boxes |
| **Gemma 4** | **none published** | — | Model card and tech report carry no RefCOCO/ScreenSpot/grounding numbers at all |
| Molmo2 / Qwen split | — | — | If you need *"which pixel do I click"*, Molmo2 points; if you need *"draw me the box around the misaligned card"*, Qwen or GLM |

Practical note: **thinking mode makes grounding worse.** Qwen3-VL-8B-Instruct scores 54.6 on
ScreenSpot-Pro vs 46.6 for Qwen3-VL-8B-Thinking ([Qwen3-VL tech
report](https://arxiv.org/pdf/2511.21631)). Qwen3.5 ships **thinking-on by default** — disable it
for grounding calls: `"chat_template_kwargs": {"enable_thinking": false}`.

---

## 4. The 64 GB arithmetic

**Ceiling.** M1 Max 64 GB unified, 400 GB/s, 32-core GPU ≈ 10.4 TFLOPS FP32
([Apple](https://www.apple.com/newsroom/2021/10/introducing-m1-pro-and-m1-max-the-most-powerful-chips-apple-has-ever-built/)).
macOS wires the GPU at ~75–80% of RAM by default → **~48–51 GB usable by Metal**; raise with
`sudo sysctl iogpu.wired_limit_mb=57344` (56 GB) if needed
([ModelPiper](https://modelpiper.com/blog/iogpu-wired-limit-mb-mac)).

**Reserve for the rest of the desk** — macOS ~8 GB, Chrome/Dia with a dev server ~5 GB,
Claude Code CLI + node ~2 GB, iTerm/etc ~1 GB ⇒ **~16 GB reserved `[EST]`**. Working budget for
the model: **~45 GB**, capped by the ~48 GB wired limit.

**Per-model residency:**

```
Qwen3.5-27B  4-bit   weights 16.1 GB (measured, mlx-community)
                   + KV      ~1.0 GB @ 16K ctx  [EST: only 16 of 64 layers carry
                                                 attention (hybrid Gated-DeltaNet),
                                                 4 KV heads x 256 dim x 2 x fp16
                                                 ~= 64 KB/token]
                   + ViT activations ~2 GB transient @ 4,000 vision tokens [EST]
                   = ~19 GB  ->  ~26 GB headroom left.  COMFORTABLE.

Qwen3.5-35B-A3B 4-bit  weights 22-24 GB + ~1 GB KV + ~2 GB  = ~27 GB  ->  ~18 GB left.  FITS.

Qwen3.8-27B  4-bit   ~16 GB  ->  same as 27B.  FITS.

Gemma 4 31B  4-bit   ~18 GB [EST] + small KV (1120 img tokens)  ->  FITS EASILY.

Qwen3.5-122B-A10B    81 GB (Ollama Q4, measured)  ->  EXCEEDS the 48 GB wired limit
                                                      even before KV.  DOES NOT FIT.
```

**The largest thing that fits with a browser + Claude Code open is `Qwen3.5-35B-A3B` at ~27 GB.**
The largest *useful* thing is the dense `Qwen3.5-27B` at ~19 GB, which scores higher on
ScreenSpot-Pro and leaves 26 GB spare.

**Memory is not the binding constraint — prefill compute is.**

- Measured reference: **Qwen3-VL-8B, 4-bit, 1024×1024 image, cold cache, M4 Max = 21.7 s**
  end-to-end; the 4B does image encoding alone in 2.1 s
  ([arXiv 2601.19139](https://arxiv.org/html/2601.19139v1)).
- M4 Max 32-core ≈ 29.5 TFLOPS FP16 vs M1 Max ≈ 10.4 TFLOPS FP32 → **~2.8× slower**
  ([nanoreview](https://nanoreview.net/en/gpu-compare/apple-m4-max-gpu-32-core-vs-apple-m1-max-gpu-32-core)).
- ⇒ `[EST]` **~55–65 s** for an 8B at 1 Mpx on this box; scaling the LM half to a dense 27B puts
  a single full-page 2560×1600 review (4,000 vision tokens) in the **2–4 minute** range. This is
  a chained extrapolation across two hardware generations — treat the magnitude, not the digits.
- Corroborating: an M1 Max at 8.5K context saw MLX effective throughput collapse to **~3 tok/s**
  once prefill is counted, against a reported 51 tok/s decode
  ([Groundy](https://groundy.com/articles/mlx-vs-llamacpp-on-apple-silicon-which-runtime-to-use-for-local-llm-inference/)).
- **The MoE is the lever.** `35B-A3B` activates 3B params per token, so its prefill compute is
  ~3B-dense — roughly **9× cheaper per vision token than the 27B dense** — for a 1.7-point
  ScreenSpot-Pro give-up. It is also the only model Ollama's MLX path currently accelerates.
- **Vision-prefix caching is the second lever.** The same paper measures **13.1× speedup** on a
  cached 1024×1024 image (21.7 s → 0.78 s, 156 MB of cache). mlx-vlm ships a
  `VisionFeatureCache` (8 entries, LRU). Multi-turn design review over ONE screenshot is exactly
  the shape that wins here — pay the 60 s once, then iterate at sub-second.

**Runtime note, load-bearing:** Ollama **0.19 (2026-03-30)** replaced the llama.cpp/Metal backend
with **MLX on Apple Silicon**, requiring >32 GB unified memory; on M5 it took prefill 1,154 →
1,810 tok/s and decode 58 → 112 tok/s. **The preview accelerates only `Qwen3.5-35B-A3B`**, and
the announcement says nothing about vision/multimodal on the MLX path
([ollama.com/blog/mlx](https://ollama.com/blog/mlx)). Verify locally with `ollama -v` before
assuming the fast path applies to your image calls.

---

## 5. What changed since the March-2026 corpus

| Fact the corpus is likely to encode | Status 2026-08-26 |
|---|---|
| "Qwen3-VL is the vision line" | Superseded. Qwen3.5 (Feb 2026) folded vision into the base model; Qwen3.5 "outperforms Qwen3-VL models across reasoning, coding, agents, and visual understanding" per the [27B card](https://huggingface.co/Qwen/Qwen3.5-27B) |
| "Gemma 3, fixed 896×896" | Gemma 4 (2026-07-02) added variable aspect ratio and a 12B **encoder-free** variant, but capped image tokens at 1120 |
| "InternVL 3.5 is current" | Still the newest InternVL — **no InternVL 4** exists. OpenGVLab's 2026 output was `InternVL-U` (4B unified understanding+generation, 2026-03-06, [arXiv 2603.09877](https://arxiv.org/abs/2603.09877)), not a new VL flagship |
| "Llama 4 is the open multimodal contender" | Behemoth never shipped; Meta's 2026 models (Muse Spark, Muse Glimmer-30B) are closed |
| "GLM-4.5V" | GLM-4.6V + 4.6V-Flash landed 2025-12-08 under **MIT** with native multimodal function-calling |
| "Molmo is the pointing model" | Still true — **Molmo2** (2026-01) extended pointing to video/tracking |
| "MiniCPM-V 4.5 is the small one" | MiniCPM-V **4.6** (2026-05-11) is 1.3B and phone-class |
| — | **New, unbenchmarked:** `Qwen3.8-27B` shipped **2026-08-14**, dense, native VL, Apache-2.0 |

---

## 6. Adversarial self-pass — the strongest reason my top pick disappoints

### 6.1 The benchmark that matches the job says nobody can do it

**DiffSpot** (2026-05, [arXiv 2605.29615](https://arxiv.org/html/2605.29615v1)) is a code-driven
spot-the-difference benchmark on **web interfaces**: mutate exactly one CSS property in
self-contained HTML, re-render at a **1280×800 viewport**, ask the model what changed. 4,400
pairs (3,900 has-diff across 13 CSS operators × 3 difficulty tiers, plus 500 no-diff for
hallucination control). This is *precisely* the design-review task.

| Model | Overall acc | Notes |
|---|---|---|
| Gemini 3.1 Pro (closed) | **47.2%** | best of all 13 |
| Kimi K2.5 (open, 1T) | 42.2% | unusable locally |
| Gemini 3 Flash | 40.9% | |
| Claude Opus 4.7 | 38.9% | 0.4% false-positive on no-diff |
| GPT-5.4 | 38.3% | |
| Qwen3.5-397B | 37.6% | the flagship of my top pick's family |
| Qwen3-VL-235B-Thinking | 28.3% | |
| **GLM-4.6V-Flash 9B** | **23.8%** | but **24.2% false positives** on no-diff |
| GLM-4.6V 106B | 21.2% | 0.4% false positives |
| Qwen3-VL-30B-Instruct | 17.6% | 18–22% hallucination |
| Qwen3-VL-235B-Instruct | 15.9% | 100% specificity via **near-abstention** |
| **InternVL3.5-30B-A3B** | **15.0%** | last |

Hard-tier recall is **below 23% for every model tested**. Median recall on `line-height`
mutations is **4.0%**; `rounded` 13.3%; `gradient` best-case 26.7%. And critically:
*"neither bbox-level pixel change nor CLIP distance reliably predicts Recall"* — you cannot
buy your way out with a bigger model or a bigger image.

**So the 70.3 ScreenSpot-Pro does not transfer.** ScreenSpot-Pro is *retrieval given a named
target* ("find the Save button"). Design review is *open-ended change/defect detection with no
target named*. Different regime, and the open-ended one is unsolved.

Two honest caveats in my favour: DiffSpot did **not** test `Qwen3.5-27B`, `-35B-A3B` or `-9B`
(only the 397B), and it did not test Gemma 4. But the direction is unambiguous — the 397B
scored 37.6%, so a 27B will not be higher.

### 6.2 The evidence is destroyed before the LM sees it

At 32×32 px/token, a 1 px border or a 2 px baseline shift is **sub-token**. The tokenizer
averages it away. No amount of reasoning recovers a signal that was never encoded. Gemma 4 at
60×60 px/token is 3.5× worse still. This is a *representational* limit, not a capability gap,
and it is the mechanical explanation for DiffSpot's line-height result.

### 6.3 Your local runtime may not reproduce the benchmark geometry

The published numbers come from `transformers`/`vLLM` with explicit `min_pixels`/`max_pixels`.
**Ollama exposes neither and downsizes large images automatically.** A `ollama run qwen3.5:27b`
against a 2560-px screenshot is a different experiment from the one that scored 70.3. If you use
Ollama, capture at CSS-pixel scale (1280–1440 px wide), not @2×.

### 6.4 The thing that actually works is not a bigger model — it is cropping

The single best evidence in this whole corpus: **ScreenSeekeR's iterative focus refinement took
OS-Atlas-7B from 18.9% → 48.1% on ScreenSpot-Pro, a 254% relative gain, with no change of model**
([ScreenSpot-Pro paper](https://arxiv.org/html/2504.07981v1)). That is a bigger delta than every
model upgrade in this table combined. **GLM-4.6V's native multimodal function-calling — the model
calling its own crop/zoom tool on the image — is the only general VLM in the list that does this
structurally**, which is why it ranks above its raw scores.

Design implication for the consumer: **do not hand a full-page screenshot to one model and ask
"what's wrong".** Render component-level crops, or let the VLM drive its own crop tool, and
delegate 1–2 px verdicts to a pixel-diff / DOM-geometry check rather than to a VLM.

### 6.5 The axis I initially assumed irrelevant: hallucination asymmetry

I nearly ranked GLM-4.6V-Flash #2 on its UI→HTML strength. DiffSpot's no-diff control kills that:
**24.2% false positives**, the worst measured. For design review, a model that invents defects on
a correct page is worse than one that misses some — you lose trust in the whole pass. Claude
Opus 4.7, GPT-5.4 and full GLM-4.6V sit at 0.4%. The XDA hands-on shows the same failure shape in
miniature: Ministral-3 3B "invented three fake entries, including a 'gemma' model at 76 billion
parameters" off a busy LM Studio screenshot, while Qwen3.5-9B got "correct count, correct names,
correct file sizes."

**Always run a no-diff control screenshot through whatever you install, and measure its false-positive
rate before trusting any verdict.**

---

## 7. What I would actually install — 5 bullets

1. **`ollama pull qwen3.5:27b` (17 GB) — the default reviewer.** Highest open-weight ScreenSpot-Pro
   that fits (70.3, tied with a 122B), OCRBench 89.4, RefCOCO 90.9, box+point grounding on a
   0–1000 normalized grid, Apache-2.0, ~19 GB resident leaving ~26 GB for browser + Claude Code.
   **Send `enable_thinking: false` on grounding calls** — thinking costs ~8 points there.

2. **`ollama pull qwen3.5:35b` (24 GB) — the one you will actually use interactively.** 3B active
   params ⇒ roughly 9× cheaper prefill per vision token than the 27B dense, which is the binding
   constraint on an M1 Max; best-in-family OCRBench (91.0) for only −1.7 ScreenSpot-Pro. It is
   also the **only** model Ollama's MLX backend currently accelerates. If a full-page review takes
   minutes on the 27B, this is the fix.

3. **`pip install mlx-vlm` + `mlx-community/Qwen3.5-27B-4bit` (16.1 GB) — for anything where
   resolution fidelity matters.** This is the only path that lets you set `max_pixels` explicitly
   and reproduce the benchmark geometry, and it gives you `VisionFeatureCache` — the measured
   **13.1× speedup** on repeat queries against the same screenshot, which is exactly the multi-turn
   design-review loop. MLX is not installed on this box yet; this is the one install to add.

4. **`zai-org/GLM-4.6V-Flash` (9B, MIT) — as the second opinion, not the primary.** Two things no
   Qwen has: **native function-calling on the image itself** (it crops/zooms without you writing
   the loop — the mechanism worth +254% in the ScreenSeekeR result), and **pixel-accurate
   HTML/CSS/JS reconstruction from a screenshot**, which turns "describe the defect" into "show me
   the corrected markup". Gate it behind a no-diff control: 24.2% false-positive rate.

5. **Skip Gemma 4, InternVL3.5, Llama 4 and Pixtral for this job; keep `qwen3.5:9b` (6.6 GB) as
   the fast triage pass.** Gemma 4's hard 1120-image-token cap is disqualifying for 1–2 px
   evidence and it publishes no grounding number at all; InternVL3.5 is a year old and scored last
   on DiffSpot (15.0%); Llama 4 and Pixtral do not appear in the ScreenSpot-Pro top 25.
   Qwen3.5-9B at 65.2 ScreenSpot-Pro / 89.2 OCRBench is the cheapest thing that still reads fine
   print correctly, and it beat Gemma 4 E4B head-to-head on real screenshots.

**Also do this, and it matters more than the model choice:** capture at CSS-pixel scale, feed
component crops rather than full pages, run a no-diff control every session, and keep 1–2 px
alignment verdicts in a DOM-geometry / pixel-diff check — DiffSpot says no VLM in 2026, open or
closed, local or hosted, gets that right.

---

## 8. Blockers / uncertainties named

- **`Qwen3.8-27B` (2026-08-14) is 12 days old and unbenchmarked on UI.** Its family is the one
  that wins every row above. If a ScreenSpot-Pro number lands for the *open* 27B (not
  Qwen3.8-Max), it plausibly displaces pick #1. Someone should A/B it directly.
- **Ollama's MLX vision path is unverified.** The 0.19 announcement covers text decode/prefill and
  names only one model. Whether image encoding rides the MLX path or the legacy Metal path on
  2026-08 Ollama is unknown to me. `mlx-vlm` sidesteps the question.
- **DiffSpot never tested the models I recommend** (27B/35B-A3B/9B, or Gemma 4). The 397B result
  bounds them from above; the exact numbers are unmeasured.
- **My prefill timing is a two-generation extrapolation.** Measured: 8B @ 1 Mpx = 21.7 s on M4 Max.
  Everything about M1 Max seconds-per-screenshot is `[EST]`. Measuring it directly is a 10-minute
  job and should be the first thing done post-install.
- **GLM-4.6V-Flash Apple-Silicon support is asserted, not verified.** It appears in mlx-community
  collections; it has no Ollama `vision` tag. Confirm a working MLX conversion before planning on it.
- **Gemma 4 px/token is derived, not published.** Google publishes the token budget {70…1120} and
  patch-16, not a px/token figure; my 60×60 px/token is `1120 tokens ÷ 4.10 Mpx`, which is the
  right *information-density* comparison but not a claim about patch geometry.
