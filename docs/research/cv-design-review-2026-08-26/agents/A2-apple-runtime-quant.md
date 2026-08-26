# A2 — Apple Silicon VLM runtime + quantization for a warm agent-loop endpoint

**Target hardware (verified on this machine, 2026-08-26):** Apple M1 Max, 32-core GPU,
68,719,476,736 B (64 GiB) unified memory, macOS 15.7.9 (24G830), `iogpu.wired_limit_mb = 0`
(i.e. never raised — running on the OS default ceiling).
**Consumer:** an agent loop that hits a resident local endpoint many times per design-review
iteration with screenshots up to 2560 px wide. Cold-per-call loading is disqualifying.

## Chip-attribution legend (read this before trusting any number below)

Nearly every fast VLM number published in 2026 is from **M4 Max / M5 Pro**, not M1 Max. M1 Max is
400–410 GB/s bandwidth and 32 GPU cores; M4 Max is 546 GB/s and 40 cores
([cpu-monkey M4 Max vs M1 Max](https://www.cpu-monkey.com/en/compare_cpu-apple_m4_max_16_cpu_40_gpu-vs-apple_m1_max_32_gpu)).
Decode is bandwidth-bound (M1 Max holds up well, ~75% of M4 Max); **prefill and vision encoding are
compute-bound, and that is where M1 Max falls furthest behind.** Every number in this doc is tagged:

- `[M1MAX]` measured on M1 Max — trust directly
- `[M4/M5]` measured on newer silicon — treat as an optimistic ceiling for M1 Max
- `[DERIVED]` my extrapolation, stated as such, not a measurement

---

## 1. Runtime comparison table

Scores: ●●● strong · ●●○ workable · ●○○ weak · ○○○ not viable.

| Runtime | VLM coverage | Image-encoder support | Prompt-cache / KV reuse | Server mode | tok/s on M1 Max | Memory overhead | Install friction | Verdict |
|---|---|---|---|---|---|---|---|---|
| **oMLX** (`jundot/omlx`) | ●●● — inherits the whole mlx-vlm zoo (Qwen3.x-VL, GLM-4V, Pixtral, DeepSeek-OCR, DOTS-OCR, GLM-OCR) | ●●● native mlx-vlm vision path; auto-detects OCR models | ●●● **best measured.** vLLM-style paged KV, prefix sharing + copy-on-write, hot(RAM)/cold(SSD) tiers that survive a server restart | ●●● OpenAI `/v1/*` **and** Anthropic `/v1/messages`, admin API, menu-bar, multi-model with pinning + per-model TTL + LRU evict | **`[M1MAX]` prefill 1.7 s @ 8K ctx vs 49.4 s for LM Studio MLX and 37.8 s for GGUF; ~30 eff tok/s vs GGUF's 16** | Highest — paged cache + SSD tier (SSD cache default max 92.6 GB on a 64 GB M1 Max) | Low: `brew tap` + `brew install` | **Recommended serving layer** |
| **mlx-vlm** (`Blaizzy/mlx-vlm` 0.6.16, 2026-08-24) | ●●● broadest and freshest — new architectures land here *first* | ●●● reference implementation for VLM vision towers | ●●● Automatic Prefix Caching (block-level, warm + persistent disk) + **Vision Feature Cache** (LRU of *projected* vision features, keyed by image path) | ●●○ FastAPI, OpenAI-compatible `/v1/chat/completions`, `/v1/embeddings`, `/v1/rerank`, dynamic model load/unload | `[M4/M5]` vision cache 550–825 prompt TPS vs ~48 baseline (11×+) on repeated images; no M1 Max VLM figure published | Moderate | Low: `pip install -U mlx-vlm`; Python ≥3.10 | **Fallback + the upstream oMLX rides on** |
| **llama.cpp + GGUF** (libmtmd/mtmd) | ●●○ good but lags: Gemma 3/4, Qwen2-VL, Qwen2.5-VL, Pixtral 12B, InternVL 2.5/3, SmolVLM, Mistral Small 3.1, Llama 4 Scout, Moondream2, MiniCPM-V | ●●● real `mmproj` support, `-hf` auto-download, projector GPU-offloaded by default | ●○○ **the weak column.** With `--mmproj` loaded, `has_mtmd` is set on *all* slots and blocks **cache reuse, slot save/restore, and context shift — even for text-only turns** (issue #21133). Each image ≈1000+ KV tokens ≈128 MiB serialized KV state; `--cache-prompt` + images has an OOM report (#22629) | ●●● mature `llama-server`, OpenAI-compatible, battle-tested | `[M1MAX]` 7B: PP 530 t/s / TG 61 t/s @ Q4_0 (llama.cpp discussion #4167, Nov 2023 — floor, not ceiling). `[M1MAX]` Qwen3.5-35B-A3B prefill 37.8 s @ 8.5K | Lowest | Low (`brew install llama.cpp`) | **Escape hatch** when a model has GGUF+mmproj but no MLX port |
| **LM Studio** | ●●○ GGUF vision + a unified MLX engine (mlx-lm + mlx-vlm via "VisionAddOns") | ●●○ works, but the MLX engine **pins an older mlx-vlm** — issue #339 asks for ≥0.6.2 because a missing `qwen3_5_moe_vision` type blocks Holo 3.1 | ●○○ `[M1MAX]` **measured broken for Qwen3.5 multimodal — 49.4 s prefill at 8K.** Text-only VLM chats do cache (25× faster follow-up TTFT `[M3]`) | ●●● headless service, JIT load, idle-TTL (default 60 min), `ttl=0` pins a model permanently, auto-evict | `[M1MAX]` Gemma 12B GGUF 22.2 eff tok/s vs MLX-bf16 17.2 | Moderate (GUI unless headless) | Lowest (GUI installer) | **Good default for humans, bad default for an agent loop** — the prefill number disqualifies it |
| **Ollama** | ●○○ Qwen3-VL is **cloud-only** on Ollama with "local soon"; local set is Qwen2.5-VL, Gemma 3/4, Llama 3.2 Vision, LLaVA | ●○○ **does not wire up standalone `mmproj` sidecars** — Qwen 3.6 loads text fine and vision input fails | ●○○ opaque; `OLLAMA_KEEP_ALIVE=-1` keeps the model resident but there is no prefix-cache story | ●●● trivially good API | `[M1MAX]` **Qwen2.5-VL 7B: 24–30 s per image.** `[M1MAX]` Qwen3-30B-A3B 26.0 eff tok/s vs llama.cpp's 41.4 — a ~37% Go-wrapper tax on the *same* engine | Moderate | Lowest | **Rule out.** Slowest wrapper, weakest vision plumbing |
| **Core ML + ANE** | ●○○ FastVLM (0.5B/1.5B/7B) ships Core ML export; almost nothing else | ●●○ ANE is genuinely good at the *ViT*; the LLM half is the problem | ○○○ no KV-reuse story; Core ML caches are opaque | ○○○ no server; you build one | `[M4]` Llama 3.2 1B: ANE 47–62 tok/s vs GPU ~204; DeepSeek-R1 8B: ANE ~9.3 vs GPU ~50 | Lowest (8B model ≈500 MB on ANE vs ≈8 GB on GPU) | **Highest** — Core ML conversion is the whole project | **Not a standalone path.** See §4 |
| **MPS / PyTorch** | ●●● anything HF Transformers loads | ●●● full fidelity | ●○○ HF `DynamicCache` only; no server-grade prefix reuse | ○○○ you write it | Consistently the slowest Apple-Silicon path; no credible 2026 M1 Max VLM benchmark bothers to include it | Highest (fp16/bf16 weights, no 4-bit Metal kernels) | Moderate | **Reference/debug only.** Use it to establish ground-truth quality, never to serve |
| **vLLM on Metal** | — | — | — | — | — | — | — | **Upstream vLLM has no Metal backend.** What exists is `waybarrios/vllm-mlx` — a vLLM-*style* server built natively on MLX (arXiv:2601.19139, Jan 2026). Real, Apache-2.0, 1.5k★, continuous batching + trie prefix cache + content-hashed vision-embedding cache. `[M4/M5]` only — **zero M1 Max data** |

---

## 2. Runtime notes that decide the choice

**oMLX is mlx-vlm plus the operations layer.** It states it serves "other mlx-vlm models," so VLM
*coverage* is inherited; what it adds is exactly the three things this brief asks for — residency
(pin / TTL / LRU), prefix reuse that survives restart, and the only **M1 Max-measured** prefill win
in the corpus. Release cadence as of 2026-08-24 is multiple releases per week (0.6.3rc3), including
VLM-specific fixes (`0.6.1` restored Qwen3.8 vision-embedding loading; `0.6.3rc3` added tool-result
image support). Requires macOS 15.0+ — **this machine is 15.7.9, so it qualifies.**

**llama.cpp's multimodal cache defect is the single biggest runtime discriminator.** `libmtmd`
itself is fine — models load, the projector offloads to GPU by default. The problem is
`slot.prompt.tokens.has_mtmd`, which is a *capability* flag set whenever `--mmproj` is loaded, not a
*data* flag set when an image is actually present. It disables cache reuse, slot save/restore and
context shift for the whole server, permanently. For a loop that re-sends a large stable system
prompt on every iteration, that is the exact feature you needed.

**Ollama is out on two independent grounds** — the `mmproj` sidecar gap (a whole class of current
models simply cannot see images) and a measured 37% wrapper tax over the identical llama.cpp engine
on M1 Max.

---

## 3. Quantization guidance

### 3a. The vision tower and the language model must be quantized differently

This is the clearest, best-corroborated finding in the whole search, and it is corroborated from
three independent directions:

| Source | Finding |
|---|---|
| **Academic** — *Rethinking Small VLM Quantization* (Shin et al., arXiv 2607.08029) | Component-wise: vision encoder at 8-bit is near-lossless; at 4-bit shows a noticeable drop on fine-grained visual understanding; at 3-bit collapses on document understanding and spatial reasoning. **The projection layer is the worst bottleneck** — aggressive quantization there hurts more than the same reduction on the vision encoder. Reported bands vs FP baseline: OCRBench ~95% @8-bit → 88–92% @4-bit → 65–75% @3-bit; DocVQA ~93% → 85–90% → 50–68%; ChartQA ~91% → 82–87% → 45–60%. **Spatial/layout tasks were the most sensitive class measured, at 8–15% accuracy loss at 4-bit.** |
| **Practitioner (MLX)** — mlx-optiq | Every OptiQ VLM ships with the **language tower at mixed 4/8-bit and the vision tower at bf16 in a sidecar**, on the explicit reasoning that the vision tower "is a small fraction of the weights, so quantizing it costs quality for very little disk." (Mage-VL 5B → 3.7 GB total with a bf16 vision tower.) |
| **Practitioner (llama.cpp)** — issues #18881, discussion #15453 | Consensus: "vision components of VLMs are always sensitive to quantization, so it's best to leave them in higher precision"; mmproj ships bf16/f16/q8 because "the impact on speed and memory from using a smaller quant is negligible, but overall quality could be impacted." |

**Recipe:** LLM 4-bit (mixed 4/8 if the converter supports a sensitivity predicate) · **projector
8-bit minimum, never below** · vision encoder 8-bit or fp16. Do not accept a "4-bit VLM" that
quantized the tower uniformly.

### 3b. Is 4-bit acceptable for spatial/layout work? — Qualified yes, with the caveat below

4-bit on the *language* half is fine. 4-bit on the *vision* half is where the 8–15% spatial loss
comes from, and it buys almost nothing because the tower is a small share of the weights. So the
honest answer is: **4-bit is acceptable if and only if it is asymmetric.** A uniform 4-bit VLM is
the configuration the measurements indict.

### 3c. 🚨 M1-specific trap: bf16 is *software-emulated* on M1/M2

Metal has native bf16 only from the Apple6 GPU family onward; **M1 and M2 do not.** MLX therefore
emulates bf16 in software while fp16 runs at full hardware rate. Measured:

- `[M2 Max]` omlx issue #604: pp1024 544.0 tok/s (bf16) → **712.4 tok/s (fp16), +31%**; pp4096
  619.4 → 768.4 (+24%); pp8192 613.4 → 658.1 (+7%). The gain concentrates in **prompt processing**,
  which is exactly the phase a screenshot loop is bound by.
- `[M1MAX]` famstack: Gemma 12B effective throughput MLX-bf16 **17.2** → MLX-fp16 **20.0** eff tok/s.

**This compounds catastrophically with §3a.** The correct recipe leaves the vision tower
*unquantized* — and most MLX HF checkpoints ship bf16, so on M1 Max the one component you
deliberately kept at high precision is the one component running through a software-emulation path,
during the compute-bound phase. **On M1 Max, convert the vision tower to fp16, not bf16.**
`mlx_vlm.convert` accepts a `--dtype float16`; verify it applies to the vision tower on your chosen
checkpoint before assuming. (GGUF sidesteps this entirely — mmproj files are f16.)

### 3d. KV-cache quantization

mlx-vlm exposes `--kv-bits` (8-bit default) and `--kv-quant-scheme {uniform,turboquant}`. TurboQuant
claims 76% KV reduction. Relevant here only if you keep long multi-turn context; a
one-screenshot-one-question loop does not need it, and 8-bit KV is the safe setting.

---

## 4. Does the ANE matter? — Honest verdict: **not as a path, but no longer irrelevant as a co-processor**

**As a standalone serving path: no.** Three hard mechanical limits, not opinions:

1. **Context ceiling.** ANE LLM implementations cap at 512–2048 tokens (some reach 4096). A single
   un-downscaled 2560 px screenshot is ~4,700 image tokens on a Qwen-VL (see §5b) — *the image alone
   does not fit.*
2. **32 MB SRAM cliff.** Performance drops ~30% once working set exceeds it.
3. **Core ML overhead.** 2–4× on small ops vs direct hardware access; Core ML also prevents direct
   ANE programming.

Measured `[M4]`: Llama 3.2 1B ANE 47–62 tok/s vs GPU ~204; DeepSeek-R1 8B ANE ~9.3 vs GPU ~50;
GPU is 2–5× faster on raw generation. ANE's one real win is power — an 8B model occupies ~500 MB on
ANE vs ~8 GB on GPU — which matters for background/battery work, not for an interactive loop.

**The 2026 update that changes the nuance:** the *shape* the field converged on is ANE-for-prefill
(batched, convolution-shaped, compute-bound) + GPU-for-decode (bandwidth-bound). `ane-infer`
implements it via reverse-engineered private APIs and reports matching llama.cpp decode. oMLX
shipped it as a product feature in the last ten days — 0.6.1 "dual-ANE/GPU prefill", 0.6.2
"built-in ANE/GPU split tuner", 0.6.3rc2 "CPU sharing for ANE prefill". **Caveat that keeps this
out of the recommendation:** the M1's 16-core ANE is ~11 TOPS against the M4's ~38, oMLX's newest
accelerator work names M5 (`NAX`) explicitly, and **no published measurement of ANE-prefill on M1
Max exists.** Treat it as a free upside if oMLX's tuner elects to use it — never as a plan.

**Apple's own FastVLM is the honest counter-example and worth knowing about.** Its FastViT-HD
encoder emits 4× fewer tokens than FastViT and 16× fewer than ViT-L/14 at 336 px, giving 3×–85×
TTFT reduction (0.5B vs LLaVA-OneVision-0.5B; 7B is 7.9× vs Cambrian-1-8B). Apple ships both Core ML
and MLX runtimes. If per-iteration latency ever becomes the binding constraint over answer quality,
FastVLM-1.5B is the model to try — but the README does not name the chip for its TTFT claims, and
0.5B/1.5B class models are unlikely to carry design-review judgment.

---

## 5. M1 Max throughput, and what a screenshot actually costs

### 5a. The only real M1 Max measurements found

| Measurement | Value | Source |
|---|---|---|
| M1 Max spec | 32 GPU cores, 400–410 GB/s | llama.cpp #4167 / cpu-monkey |
| LLaMA-7B Q4_0, llama.cpp | **PP 530 t/s · TG 61 t/s** (Q8_0: 537/40; F16: 600/23) | llama.cpp discussion #4167, 2023-11-25 — an old floor |
| Gemma 4 26B-A4B 4-bit, oMLX, **VLM turn with a portrait image** | **TTFT 0.85 s · 55.9 tok/s decode** | lilting.ch, M1 Max 64 GB |
| Same model, text prefill 828 tok | 352 t/s cold → 469 t/s warm; TTFT 2.35 s cold | lilting.ch |
| Same model, text prefill 1555 tok | 394 t/s cold → **1,213 t/s warm (+208%)**; TTFT 1.27 s warm | lilting.ch |
| Gemma 4 31B dense 4-bit | 14–15 tok/s, TTFT ~4.4 s | lilting.ch |
| Cold start (load + first-inference warmup) | **~20–22 s total** (9.7–11.9 s load + 9–10 s warmup tax) | lilting.ch |
| Qwen3.5-35B-A3B @ 8.5K ctx, prefill | oMLX **1.7 s** · LM Studio GGUF 37.8 s · LM Studio MLX 49.4 s | famstack, M1 Max 64 GB / 24-core |
| Same, effective tok/s @ 1.5K ctx | oMLX ~30 · GGUF 16 · MLX 12 | famstack |
| Qwen2.5-VL 7B under Ollama | **24–30 s per image** | via insiderllm |

⚠️ The famstack M1 Max is the **24-GPU-core** binned part; this machine is the **32-core** part, so
famstack's prefill numbers are conservative by roughly a third for the compute-bound phase.

### 5b. What a 2560 px screenshot costs — and the single biggest lever in this whole document

**Qwen2.x/3.x-VL** tokenize at one token per 28×28 px block (patch 14, 2×2 merge):

| Input | Pixels | Image tokens | Prefill @ 400 t/s `[DERIVED from M1MAX]` |
|---|---|---|---|
| 2560×1440 native | 3,686,400 | **≈4,702** | **≈11.8 s** |
| 1344×756 (capped to ~1 MP) | 1,016,064 | **≈1,296** | **≈3.2 s** |

The default `preprocessor_config.json` sets `max_pixels = 12,845,056` — the *architectural ceiling*,
**12.8× Qwen's own recommended 1,003,520.** A 2560×1440 screenshot is below 12.8 M px, so nothing
downscales it and you pay all 4,702 tokens.

🚨 **And the un-downscaled path is also the less accurate one.** mlx-vlm issue #1175 (opened
2026-05-12, fixed in PR #1213) measured exactly the workload in this brief — visual grounding on UI
screenshots:

- **mean IoU 0.542 at 12.8 M px → 0.736 at 1 M px — a 35.8% accuracy gain from downscaling.**
- Secondary UI-Vision run (N=20): 0.407 → 0.435.

**Downscale client-side to ≤1,003,520 px and you get ~3.7× less prefill AND better spatial
accuracy.** There is no trade-off to make here. Do it before anything else.

**Gemma 3/4** behave differently and better for latency: SigLIP-400M at 896×896 → 64×64 patches
pooled to a **fixed 256 soft tokens per crop**, with Pan-&-Scan adding a bounded number of crops for
wide/text-heavy images (≤~1,280 tokens total). That fixed budget is why lilting measured a **0.85 s
VLM TTFT on M1 Max** — the number is real, but it is a property of Gemma's encoder, not of the
runtime, and it does not transfer to a Qwen-VL at native screenshot resolution.

### 5c. Cross-silicon reference (upper bounds only)

`[M4/M5]` contracollective, 2026-06-14 — Qwen2.5-VL 7B 4-bit: **M4 Pro** MLX encode 320 ms, prefill
410 t/s, decode 28 t/s, total 2.4 s for a 50-token answer (llama.cpp Q4_K_M: 480 ms / 340 / 24 /
3.0 s); **M5 Pro** MLX 240 ms / 560 / 38 / 1.7 s. Qwen2.5-VL **3B** on M5 Pro MLX: 130 ms / 720 / 62
/ 0.9 s. Moondream 2 (1.86B) on M4 Pro: 95 ms encode, 78 tok/s, 0.7 s total. MLX beat llama.cpp by
30–40% on *encode* latency specifically, attributed to ViT-specific kernels. **For short responses,
encode + prefill dominate total latency, not decode throughput** — which is precisely the agent-loop
regime.

`[DERIVED]` M1 Max 32-core for Qwen2.5-VL-7B 4-bit, interpolating on bandwidth (decode) and GPU
compute (encode/prefill) against M4 Pro: **encode ~400–500 ms, prefill ~300–400 t/s, decode ~26–30
tok/s.** With a 1,296-token downscaled screenshot that is ≈3.5–4.5 s to first token and ≈2 s for a
50-token answer — **a ~6-second iteration.** Stated as a derivation. Measure it before you plan on it.

---

## 6. Keeping the model resident, and 64 GB memory behaviour

**Why residency is non-negotiable:** `[M1MAX]` cold start is ~20–22 s (9.7–11.9 s load + a 9–10 s
first-inference warmup tax that a naive keep-alive test will miss entirely).

| Runtime | Residency mechanism |
|---|---|
| **oMLX** | Pin the model in the admin panel (always loaded) + per-model TTL + LRU evict. Multi-model in one process. **The best fit.** |
| **mlx-vlm** | Server holds one model; dynamic load/unload with caching. Keep the process up. |
| **LM Studio** | Headless service; JIT-loaded models default to 60-min TTL; **load manually with `ttl=0` to pin permanently** and let others JIT-evict around it. |
| **llama.cpp** | `llama-server` is resident by construction. |
| **Ollama** | `OLLAMA_KEEP_ALIVE=-1`. Note ollama#9410 reports the setting is honored but the GPU is not actually permanently held — verify with `ollama ps`, don't trust the env var. |

### `iogpu.wired_limit_mb` on this machine

Currently `0` — the OS default ceiling, never raised. The sysctl is a **ceiling, not an
allocation**: raising it costs nothing by itself and changes only what a later allocation is
permitted to wire. It takes effect immediately with no reboot, and **resets to 0 on every boot**
(script it at login if you want it persistent). For 64 GB the consistent guidance is ~56 GB,
leaving ~8 GB for macOS:

```
sudo sysctl iogpu.wired_limit_mb=57344
```

Overshooting is not a soft failure — "the whole machine hitches, the window server stutters, and in
the extreme the system can become unstable under memory pressure." Never set it to installed
capacity.

**Budget reality on this machine.** lilting's M1 Max 64 GB run auto-allocated **50.4 GB to the model
and 56 GB to the process** for a 15.26 GB 4-bit Gemma 4 26B-A4B — the runtime will happily claim
most of the box for cache. Meanwhile this machine also runs the agent session, a browser and an
editor. A **7–9B VLM at 4-bit (~5–7 GB weights)** leaves comfortable headroom; a 30B-class VLM does
not, once you add oMLX's paged KV and a 92.6 GB default SSD-cache ceiling. Also budget **1–2 GB
transient headroom** for the high-resolution image spike during vision encoding.

---

## 7. Recommended stack — exact commands

**Serve with oMLX; model = a Qwen3-VL-8B-class MLX 4-bit with an unquantized (fp16-on-M1) vision
tower; downscale every screenshot to ≤1,003,520 px before it leaves the agent.**

Rationale in one line each: oMLX is the only runtime with an **M1 Max-measured** prefill win
(1.7 s vs 37.8/49.4 s at 8K) *and* first-class residency (pin/TTL/LRU); it inherits mlx-vlm's VLM
coverage, so model support is not a trade; llama.cpp's `has_mtmd` flag structurally disables the
cache reuse this loop depends on; Ollama and LM Studio are measured slower on this exact chip.

```bash
# 1. Raise the wired-memory ceiling (immediate, resets at boot — script it at login to persist)
sudo sysctl iogpu.wired_limit_mb=57344

# 2. Serving layer
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx
omlx serve            # OpenAI /v1/* + Anthropic /v1/messages; pin the model in the admin panel

# 3. Direct-from-upstream fallback (also what to use if a brand-new architecture is not in oMLX yet)
pip install -U mlx-vlm                       # 0.6.16, 2026-08-24
APC_ENABLED=1 APC_NUM_BLOCKS=4096 \
  mlx_vlm.server --model mlx-community/Qwen3-VL-8B-Instruct-4bit \
                 --port 8080 --vision-cache-size 20 --kv-bits 8

# 4. GGUF escape hatch — for a model with mmproj but no MLX port. Accept no prompt-cache reuse.
brew install llama.cpp
llama-server -hf ggml-org/Qwen2.5-VL-7B-Instruct-GGUF --port 8081 -ngl 99
#   mmproj is GPU-offloaded by default; --no-mmproj-offload disables. Keep mmproj at f16.

# 5. MANDATORY client-side preprocessing — the highest-leverage line in this document.
#    1344x756 = 1,016,064 px; both dims are multiples of 28, so no re-rounding loss.
#    ~1,296 image tokens instead of ~4,702, and +35.8% grounding IoU.
sips -Z 1344 shot.png --out /tmp/shot-1344.png
```

**Two build-time checks before you commit to a checkpoint:**
1. Confirm the checkpoint's **projector and vision tower are not 4-bit** (§3a). If you convert it
   yourself: `mlx_vlm.convert --hf-path <model> --mlx-path <out> --quantize --q-bits 4` and verify
   the vision-tower tensors stayed high-precision.
2. On this M1 Max, get the high-precision parts to **fp16, not bf16** (§3c) — worth +16–31% on
   prompt processing, the phase this workload is bound by.

---

## 8. Adversarial pass — the strongest case *against* local serving on this M1 Max

I ran this as a deliberate pass and it found three things I had assumed away. Two survive.

**8a. The vision feature cache — the headline 11×/28× speedup — does not help this workload at all.**
mlx-vlm's cache is "keyed by image path"; vllm-mlx's is content-hashed. **Every design-review
iteration presents a *new* screenshot**, so every request is a cache miss on the vision half. The
28× (21.7 s → 0.78 s) and 11×+ figures are all *multi-turn-about-the-same-image* numbers. What
prefix caching *does* buy you here is the stable system prompt and few-shot preamble — real, but
much smaller. **Budget the full vision-encode + full image-token prefill on every single
iteration.** Any plan built on the cache numbers is built on the wrong measurement.

**8b. Prefill, not decode, is the wall — and the published decode numbers hide it.** famstack's
title is the finding: `[M1MAX]` **57 tok/s on screen, 3 tok/s in practice** — MLX reported 57 tok/s
in the UI while delivering 3 tok/s of effective throughput at 8.5K context, because 49.4 s went to
prefill before a token appeared. Combine with §5b: at native 2560 px you add ~4,700 image tokens to
every request. Worst realistic case on this machine — a Qwen-VL at native resolution on a runtime
with broken multimodal caching — is **30–50 s per iteration**, matching the independent `[M1MAX]`
Ollama observation of 24–30 s per image. **At that latency the agent loop is not interactive and a
cloud VLM wins outright.** This is the real argument and it is not weak.

**The rebuttal, stated with its own numbers, because it is also strong:** every term in that worst
case is a configuration choice, not a hardware limit. Downscaling removes 3.7× of the prefill and
*improves* accuracy (#1175). oMLX's tiered cache removes another order of magnitude on the stable
prefix (1.7 s vs 49.4 s, same chip, same model). fp16-over-bf16 adds 16–31% on prompt processing on
this specific silicon. The `[M1MAX]` existence proof is lilting's **0.85 s VLM TTFT with 55.9 tok/s
decode** on a 4-bit VLM. The honest verdict: **M1 Max is fast enough for a ~5–8 s design-review
iteration, and hopelessly slow for a ~1 s one** — and it only reaches the former if you make all
three configuration choices. Get any one wrong and you land in the 30-second regime.

**8c. Two axes I initially assumed irrelevant, checked, and now flag:**
- **bf16 emulation on M1/M2** (§3c). I nearly recommended "leave the vision tower at bf16" straight
  from the quantization literature — which on *this chip* would have put the most latency-critical
  component on a software-emulated path. Measured: 24–31% of prompt-processing throughput.
- **ANE re-entering via prefill** (§4). My prior was "ANE is dead for LLMs," which the aggregate
  tok/s numbers support. Then oMLX shipped dual-ANE/GPU prefill in the last ten days. The verdict
  does not change for M1 Max (no measurement exists, and M1's ANE is ~3.5× weaker than M4's), but
  "ANE is irrelevant" is now a stale claim, not a durable one.

---

## 9. Blockers, uncertainties, and what to measure first

- **No published M1 Max VLM benchmark exists at all.** Every VLM latency table in the 2026 corpus is
  M4 Pro / M4 Max / M5 Pro. The M1 Max numbers in §5a are text-model numbers plus one Gemma-4 VLM
  TTFT. §5c's M1 Max estimates are labeled `[DERIVED]` and should be replaced by a local measurement
  before any latency budget is committed.
- **oMLX's 1.7 s prefill was measured on a *text* model** (Qwen3.5-35B-A3B), not a VLM. The tiered
  KV cache should apply to the text prefix of a VLM request identically, but that is inference, not
  measurement. Verify on your actual model.
- **oMLX freshness vs mlx-vlm freshness.** oMLX is on release candidates shipping several times a
  week (0.6.3rc3, 2026-08-24). That is healthy velocity and also RC-grade stability. mlx-vlm 0.6.16
  landed the same day. Pin versions.
- **Not verified: whether `mlx_vlm.convert --dtype float16` actually applies to vision-tower
  tensors.** The flag exists for mlx-lm conversion and omlx#604 was closed "planned." Inspect the
  output safetensors dtypes rather than trusting the flag.
- **Not investigated (out of the brief's scope):** which *model* is best for design-review judgment.
  This document covers runtime and quantization only. The model choice interacts strongly with §5b —
  Gemma-family fixed-256-token encoding is dramatically cheaper per screenshot than Qwen-VL's
  dynamic tokenization, at the cost of fine detail on a 2560 px input. That trade deserves its own
  measurement.

---

## Sources

**Runtimes** · [Blaizzy/mlx-vlm](https://github.com/Blaizzy/mlx-vlm) · [mlx-vlm on PyPI (0.6.16, 2026-08-24)](https://pypi.org/project/mlx-vlm/) · [jundot/omlx](https://github.com/jundot/omlx) · [omlx releases](https://github.com/jundot/omlx/releases) · [llama.cpp multimodal docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md) · [llama.cpp mtmd tools](https://github.com/ggml-org/llama.cpp/tree/master/tools/mtmd) · [waybarrios/vllm-mlx](https://github.com/waybarrios/vllm-mlx) · [vllm-mlx model list](https://github.com/waybarrios/vllm-mlx/blob/main/docs/reference/models.md) · [LM Studio unified MLX engine](https://lmstudio.ai/blog/unified-mlx-engine) · [lmstudio-ai/mlx-engine#339](https://github.com/lmstudio-ai/mlx-engine/issues/339) · [Ollama Qwen3-VL](https://ollama.com/blog/qwen3-vl)

**Defects / limitations** · [llama.cpp#21133 — has_mtmd blocks cache reuse & slot save/restore](https://github.com/ggml-org/llama.cpp/issues/21133) · [llama.cpp#22629 — multimodal prompt-cache OOM](https://github.com/ggml-org/llama.cpp/issues/22629) · [llama.cpp#18881 — quantized mmproj request](https://github.com/ggml-org/llama.cpp/issues/18881) · [llama.cpp#15453 — Q4_0 for mmproj](https://github.com/ggml-org/llama.cpp/discussions/15453) · [ollama#9410 — KEEP_ALIVE does not actually pin](https://github.com/ollama/ollama/issues/9410) · [mlx-vlm#1175 — default max_pixels degrades grounding 0.736→0.542 IoU](https://github.com/Blaizzy/mlx-vlm/issues/1175) · [omlx#604 — bf16 vs fp16 on M1/M2](https://github.com/jundot/omlx/issues/604)

**M1 Max measurements** · [famstack pt.1 — 57 tok/s on screen, 3 in practice (M1 Max 64 GB)](https://famstack.dev/guides/mlx-vs-gguf-apple-silicon/) · [famstack pt.2 — same engine, 37% slower](https://famstack.dev/guides/mlx-vs-gguf-part-2-isolating-variables/) · [lilting.ch — oMLX 0.3.9.dev2 on M1 Max 64 GB](https://lilting.ch/en/articles/omlx-039-dev2-m1-max-tested) · [llama.cpp discussion #4167 — Apple Silicon PP/TG table](https://github.com/ggml-org/llama.cpp/discussions/4167) · [starmorph — Apple Silicon inference optimization (2026-04-10)](https://blog.starmorph.com/blog/apple-silicon-llm-inference-optimization-guide)

**Other-silicon measurements** · [contracollective — MLX vs llama.cpp for Qwen2.5-VL/Moondream/LLaVA, M4 Pro & M5 Pro](https://contracollective.com/blog/local-vision-llm-apple-silicon-mlx-qwen-vl-moondream-2026) · [arXiv 2601.19139 — vllm-mlx, M4 Max only](https://arxiv.org/html/2601.19139v2) · [insiderllm — local vision models by GPU tier](https://insiderllm.com/guides/vision-models-locally/)

**Quantization** · [arXiv 2607.08029 — Rethinking Small VLM Quantization (Shin, Kim, Kim, Yoo, Kim)](https://arxiv.org/pdf/2607.08029) · [mlx-optiq blog](https://mlx-optiq.com/blog/) · [mlx-optiq](https://mlx-optiq.pages.dev/) · [MBQ — Modality-Balanced Quantization, CVPR 2025](https://openaccess.thecvf.com/content/CVPR2025/papers/Li_MBQ_Modality-Balanced_Quantization_for_Large_Vision-Language_Models_CVPR_2025_paper.pdf)

**ANE / Core ML** · [insiderllm — ANE for LLM inference, what actually works (2026-03-05)](https://insiderllm.com/guides/apple-neural-engine-llm-inference/) · [apple/ml-fastvlm](https://github.com/apple/ml-fastvlm) · [FastVLM (CVPR 2025)](https://machinelearning.apple.com/research/fast-vision-language-models) · [thebasedcapital/ane-infer](https://github.com/thebasedcapital/ane-infer) · [arXiv 2603.06728 — Orion: programming Apple's Neural Engine](https://arxiv.org/abs/2603.06728) · [Deploying Transformers on the ANE](https://machinelearning.apple.com/research/neural-engine-transformers)

**Memory / models** · [contracollective — raising the wired limit (2026)](https://contracollective.com/blog/mac-unified-memory-wired-limit-gpu-large-local-llm-2026) · [Qwen2.5-VL-7B-Instruct model card (min_pixels/max_pixels)](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct) · [Gemma explained — what's new in Gemma 3 (256 soft tokens, Pan & Scan)](https://developers.googleblog.com/gemma-explained-whats-new-in-gemma-3/) · [Gemma 3 technical report](https://arxiv.org/pdf/2503.19786) · [LM Studio idle TTL & auto-evict](https://lmstudio.ai/docs/app/api/ttl-and-auto-evict) · [LM Studio headless](https://lmstudio.ai/docs/developer/core/headless) · [cpu-monkey M4 Max vs M1 Max](https://www.cpu-monkey.com/en/compare_cpu-apple_m4_max_16_cpu_40_gpu-vs-apple_m1_max_32_gpu)
