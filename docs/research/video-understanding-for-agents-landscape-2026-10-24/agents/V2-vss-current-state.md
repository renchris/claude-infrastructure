# V2: NVIDIA VSS as of 2026-10-24, from primary sources

The question was whether the GTC 2026 talk https://www.youtube.com/watch?v=3yPQHcEZDaI is applicable and helpful. V1 (`V1-vss-talk-watched.md`) covers what the talk says. This file covers what VSS 3.3.0 is today, the version that ships now.

**Labels.**
- **MEASURED**: I read or counted it myself today; the command or file is named.
- **DOCUMENTED**: NVIDIA or a model card says it (vendor claim). The URL or file:line is given.
- **INFERRED**: my reasoning.

Docs were fetched as Markdown (`<page>.md`, per the docs' own `llms.txt`) into `/tmp/v2-vss-src/docs/`. Repo facts come from `gh api` and HF facts from `huggingface.co/api`. File:line references point at those local copies.

## 0. Verdict

**As software for us: not applicable. As a source of patterns: moderately helpful, and one prompt can be lifted almost verbatim.**

| Question | Answer | Basis |
|---|---|---|
| Runs on our Apple-Silicon Macs? | **No.** NVIDIA's quickstart says "A Windows or Mac machine can be used as the browser or coding-agent client, but it is not the validated Docker Compose deployment host … point the agent at a supported Linux deployment host instead." | DOCUMENTED, `getting-started_quickstart.md:180-183` (docs.nvidia.com/vss/getting-started/quickstart) |
| Can we use it hosted, with nothing uploaded? | **No.** The hosted path is build.nvidia.com's free trial endpoint. Its terms forbid "any confidential information" (§2.6(a)). They also let NVIDIA use "User Content and Generated Content to improve NVIDIA products and services, including AI models" (§3.3(iv)). Production use is excluded (§1.2). | DOCUMENTED, NVIDIA API Trial Terms PDF (dated 2025-10-07 in its PDF metadata; MEASURED with `pdfinfo`) |
| Is it meant for meetings? | **No.** It targets CCTV and physical spaces: warehouse, smart city, alerts, RTSP cameras. It has no ASR component, no OCR and no diarization in 3.3.0. Audio exists only if you swap the VLM for Nemotron-3-Nano-Omni on a separate GPU (§4). | DOCUMENTED (README use cases; `configure-the-vlm.md:288-303`); MEASURED: the words OCR, Whisper, Parakeet, Riva and diariz… appear in none of the 26 downloaded doc pages (grep) |
| Claude Code integration? | **Yes, the strongest of any GPU stack.** It ships 24 agentskills.io skills "validated using Claude Opus 5", which install by symlinking into `~/.claude/skills/`. Skills drive a `vss` CLI. Two MCP servers sit underneath. Every one of them needs a running Linux/NVIDIA deployment. | DOCUMENTED (`vision-agent_agent-skills.md:12-13`, `quickstart.md:190-205`); MEASURED: 24 `SKILL.md` in the repo tree (`gh api …/git/trees/develop?recursive=1`) |
| What is worth taking? | Ideas, not deployments (§8):<br>(1) the subject-anchored, per-criterion critic prompt (Apache-2.0);<br>(2) query decomposition into hard filters plus semantic query plus an action-routing rule;<br>(3) a memory ladder that answers from stored records before re-watching, capped at 3 visual follow-ups;<br>(4) an fps-by-task rule capped at 60 frames per window. | INFERRED |

## 1. What VSS is today

- **Identity.** "NVIDIA AI Blueprint for Video Search and Summarization". It is a reference architecture in three layers: real-time video intelligence (RT-CV, RT-Embed, RT-VLM), downstream analytics (behaviour analytics, alerts, Elasticsearch), and agent/offline tools reachable "via the Model Context Protocol" (DOCUMENTED, README:30-32, 61-65).
- **Repo** `NVIDIA-AI-Blueprints/video-search-and-summarization` (MEASURED, `gh api repos/…`, 2026-10-24):

  | Field | Value |
  |---|---|
  | Stars | 1,941 |
  | Forks | 413 |
  | Open issues | 246 |
  | License | Apache-2.0 (repo) |
  | Default branch | `develop` |
  | Last commit | 337d95e87, 2026-10-23T23:55:45Z, "chore(osrb): sync inventory.csv…" |
  | Last push | 2026-10-24T03:07:29Z |
  | Tree size | 11,010 paths |

- **Releases** (MEASURED, `gh api …/releases`): v3.3.0 2026-10-21 · v3.2.1 2026-07-23 · v3.2.0 2026-06-16 · v3.1.0 2026-03-18 · v2.4.1 2026-01-28 · v2.4.0 2025-09-24 · v2.3.1 2025-07-04 · v2.3.0 2025-04-21 · "VSS 2.0.0" (tag v1.0) 2025-03-15.
  - The talk's "VSS 3.0" has no GitHub release. The 3.0.0 docs call it "an early access release … some features in an alpha state" (DOCUMENTED, `release-notes.md:1060-1062`).
- **What is new in 3.3.0** (DOCUMENTED, release v3.3.0 body; `release-notes.md:15-78`):
  - `vss-build-vision-ai`, a single deployment skill that replaces `vss-deploy-profile`.
  - Skills reorganized into `deployment/`, `operations/`, `tools/` and `benchmarking/`.
  - The `vss` CLI is now "the supported way to operate a running deployment from a coding agent". Its groups are `vios`, `vlm`, `summarize`, `search`, `memory` and `analytics`.
  - Elasticsearch agent memory, plus "bounded memory introspection" ("at most three grounded VLM follow-ups").
  - Adaptive EVS video-token pruning in RT-VLM, for local vLLM Qwen3-VL-based models only.
  - Docs moved to Fern.
- **Licensing is split, and R5 had it wrong.** The repo is Apache-2.0, but "the blueprint microservices are governed by the NVIDIA Software and Model Evaluation License Agreement". NIMs fall under the NVIDIA Software License plus AI Product terms, and models under the NVIDIA Open Model License. Elasticsearch is under the Elastic License (DOCUMENTED, `appendix_license-information.md:12-36`). The README adds that an "NVIDIA AI Enterprise developer licence [is] required to local host NVIDIA NIM" (README:108).
- **Containers** (MEASURED, NGC catalog search API `q=vss`):
  - About 30 images under `nvcr.io/nvidia/vss-core/*`, most modified 2026-10-16. They include `vss-agent`, `vss-rt-vlm`, `vss-rt-embed`, `vss-rt-cv`, `vss-video-summarization`, `vss-alert-ms`, `vss-vios-*` and `vss-vios-mcp`.
  - The 2.x images (`nvidia/blueprint/vss-engine`) were last modified 2026-01-28.
  - An NGC Personal API Key is needed to pull (DOCUMENTED, `prereq.txt:210-221`).

## 2. Components (3.3.0 defaults)

| Role | Default model | Notes / alternatives | Source |
|---|---|---|---|
| VLM (RT-VLM, critic, LVS chunks) | **Cosmos3 Nano Reasoner**: BF16 for base/alerts/LVS; FP8 for search, so it can share a GPU with the critic | Swappable for any OpenAI-compatible VLM. The docs show `gpt-5.6`, Reka, `cosmos-reason2-8b`/`-2b` NIMs, vLLM `Qwen/Qwen3-VL-8B-Instruct`, Nemotron-3-Nano-Omni, and Cosmos3 Super (manual setup). "Alert verification … optimized with Cosmos3 Nano Reasoner … might not work with other models." | DOCUMENTED, `configure-the-vlm.md:21-55, 106-236, 288-411` |
| LLM (planner, query decomposition, report) | **Nemotron 3.5 Lightning 30B-A3B** | LVS perf runs used "Nemotron 3 Nano". The VA-MCP example config still names `meta/llama-3.1-70b-instruct`. The license page still lists Nemotron-Nano-9B-v2. | DOCUMENTED, README:58-59; `video-summarization-performance.md` test config; `video-analytics-mcp-server.md` config |
| Video embedding (search) | **Cosmos-Embed1-448p** (`cosmos-embed1-448p-anomaly-detection` in the search benchmark) | — | DOCUMENTED, `search-performance.md:41-46` |
| Object/attribute embedding | RADIO-CLIP, SigLIP2 (inside RT-CV) | — | DOCUMENTED, `release-notes.md` 3.1.0 |
| CV detection and tracking | RT-DETR 2D (EfficientViT-L2), Grounding DINO / MaskGroundingDINO, TrafficCamNet Transformer Lite, Sparse4D 2.1, MV3DT + BEV fusion | Warehouse and smart-city use cases | DOCUMENTED, `appendix_license-information.md:14-25`; README:80 |
| Place search in VA-MCP | `sentence-transformers/all-MiniLM-L6-v2` | — | DOCUMENTED, `video-analytics-mcp-server.md` config table |
| ASR / OCR / diarization | **None in 3.3.0** | Audio only through an Omni VLM (§4) | MEASURED by grep (see §0) |
| Storage / bus | Elasticsearch 9.3.3, Kafka/Redis, VIOS (RTSP/ONVIF/Milestone) | — | DOCUMENTED, README:81-93; license page |

**LVS (long-video summarization) mechanics.** The 3.2 test configuration (DOCUMENTED, `video-summarization-performance.md`):
- 10 s chunks, 20 frames per chunk (2 fps), about 9k vision tokens per chunk.
- "Output max tokens 100" per chunk caption.
- Then CA-RAG LLM aggregation.

INFERRED: 100 tokens per 10 s chunk cannot carry slide text. This design discards exactly what our meeting spec found decisive: on-screen text, OCR 0.92 vs transcript-only 0.50/0.39 (`v2-spec.md` §0, via V1 §8).

## 3. Hardware, and macOS

**Validated GPUs** (DOCUMENTED, `prereq.txt:69-78`): H100, GB300, RTX PRO 6000 Blackwell, L40S, DGX Spark, IGX Thor, AGX Thor. The RTX PRO 4500 Blackwell is limited to the alerts profile. "OTHER" is available as an experimental profile.

**OS** (DOCUMENTED, README:135-141): Ubuntu 24.04 on x86, DGX OS on Station/Spark, IGX-SW/JetPack on Thor/Orin. Linux only.

**Minimum host** (DOCUMENTED, `prereq.txt:175-183`): 18-core CPU, 128 GB RAM, 1 TB SSD, 1 Gbps NIC, plus the GPUs the profile needs.

**GPUs per profile** (DOCUMENTED, `prereq.txt:289-294`):

| Profile | Shared | Dedicated | Remote LLM | Remote VLM | Remote LLM+VLM |
|---|---|---|---|---|---|
| base | 1 | 2 | 1 | 1 | **1** |
| lvs | 1 | 2 | 1 | 1 | **1** |
| search | 2 | 2–4 | 2 | 2 | **2** |

Even with both models remote, a local NVIDIA GPU is still required.
- Edge platforms (Spark/Thor) take base and alerts only.
- Search runs on Spark and AGX Thor only, and only with a remote LLM and VLM.
- "The LVS profile is not supported on these edge platforms" (`prereq.txt:295-302`).

**Cosmos3-Nano Reasoner NIM** (DOCUMENTED, docs.nvidia.com/nim/vision-language-models/1.7.0/support-matrix.html):
- "Any NVIDIA GPU with … > 56 GB" at BF16.
- The smallest listed SKU is the L40S at 48 GB, FP8.
- Compute capability ≥ 7.0 (8.9 for FP8).
- The NIM page calls the reasoner "Cosmos3-Nano (8B)".

**Throughput** (DOCUMENTED, `video-summarization-performance.md`, VSS 3.2, Cosmos3 Nano FP8):
- LVS on 1 H100, VLM and LLM colocated: 60 min of video in 265 s, which is 13.6x real time (INFERRED arithmetic).
- On a 4+4 H100 topology: 64.7 s.
- The talk's 277 s on H100 (V1 §7) is consistent with this.

**macOS / Apple Silicon:**
- Nothing in the deployment runs on a Mac (DOCUMENTED, quote in §0).
- The one Mac-side piece is the `vss` CLI and the skills acting as a client.
  - The CLI is pure Python: `nvidia-vss-cli`, `requires-python >=3.13,<3.15`. Its dependencies are click plus `nvidia-vss-core` (aiohttp, elasticsearch, httpx, opencv-python-headless, pydantic, PyYAML, tenacity), with no CUDA (DOCUMENTED, `libs/vss/{cli,core}/pyproject.toml`).
  - INFERRED: it should install on macOS. NOT RUN; I did not execute downloaded code.

## 4. Audio

- **3.x has no transcription service.** Audio comes only from an omni VLM. With `ENABLE_AUDIO=true` and `omni` in `VLM_NAME`, the agent sends the whole MP4 inline (`data:video/mp4;base64,…`) to a **remote** Nemotron-3-Nano-Omni-30B-A3B served by vLLM on another GPU. "VSS does not bundle Omni weights."
  - "Cosmos and other VLMs ignore the audio track … falls back to JPEG frame sampling" (DOCUMENTED, `configure-the-vlm.md:288-372`; `appendix_faq.md:133`).
- RT-VLM returns an `audio_transcript` field per chunk when `enable_audio` is set on an Omni model (DOCUMENTED, `real-time-vlm.md:1715-1752`; `release-notes.md:599-600`).
- Known issue: the audio configuration hits "multiple retry issues with videos that are missing audio or non-compatible audio streams" (DOCUMENTED, `release-notes.md:1038`).
- History: VSS 2.3.0 (2025-04) added "Support for Audio in Summarization and Q&A" (DOCUMENTED, `rn2x.md:63`). The note does not name the engine.
- INFERRED: an LLM-written `audio_transcript` per chunk gives no word timings, no speaker turns and no WER guarantee. Our spec's Parakeet path (word ms, 81.3 % speaker-word accuracy, `v2-spec.md` S8) is strictly richer for meetings.

## 5. Agent and tool interfaces

| Interface | What it exposes | Usable from our Mac? | Source |
|---|---|---|---|
| **Video-Analytics MCP** (VA-MCP), `nat mcp serve`, port 9901, streamable-http or SSE | 7 tools over **Elasticsearch incident/metric data**: `get_incident`, `get_incidents` (with filter `vlm_verdict` = confirmed/rejected/…), `get_sensor_ids`, `get_places`, `get_fov_histogram`, `get_average_speeds`, `analyze`. It answers questions about an analytics database, not "ask this video". No auth. | Only as a client of a deployed stack | DOCUMENTED, `video-analytics-mcp-server.md`; `appendix_known-limitations.md` ("MCP servers … lack authentication") |
| **VSS Orchestrator MCP**, port 9988 | 9 deployment tools: `profiles`, `prereqs`, `docker_generate`, `docker_read`, `docker_up`, `docker_status`, `docker_list`, `docker_logs`, `docker_down` | Must run on the GPU host | DOCUMENTED, `orch-mcp.md` |
| **Docs MCP**, `https://docs.nvidia.com/vss/_mcp/server` | Documentation search, not video | Yes, but it holds only docs | DOCUMENTED, `llms.txt` |
| **`vss` CLI** | `vss vlm run`, `search run <embed\|attribute\|tag\|fusion\|object>`, `summarize`, `memory get/query/introspect`, `vios timeline`, `analytics`. It can also target **a bare OpenAI-compatible VLM** (vLLM, a NIM, Inference Hub) with a local file via `--use-base64`. | Client side yes (INFERRED). Pointing it at a local mlx-vlm server is conceivable but untested and pointless: Claude is our VLM. | DOCUMENTED, `cli-README.md:117-145` |
| **Agent skills** (24, Early Access, "validated using Claude Opus 5") | Deploy, operate and benchmark. `vss-ask-video`, `vss-summarize-video`, `vss-search-archive`, `vss-generate-video-report`, `vss-evaluate-caption-accuracy`, `vss-benchmark-vlm-qa`, … | They install, but every one needs a running deployment | DOCUMENTED, `vision-agent_agent-skills.md`; MEASURED count, repo tree |

## 6. Cosmos models: sizes, licences, HF availability, Apple Silicon

HF numbers below are MEASURED with `huggingface.co/api/models/<id>` on 2026-10-24.

| Model | Size | License / gating | HF | Apple Silicon |
|---|---|---|---|---|
| **Cosmos3-Nano** (VSS default VLM, as "Cosmos3 Nano Reasoner") | 16B total. It is a Mixture-of-Transformers: a reasoner tower of **Qwen3-VL-8B architecture** (36 layers, hidden 4096) plus a diffusion generator tower | OpenMDW-1.1, **not gated** | `nvidia/Cosmos3-Nano`, 123,602 downloads, created 2026-03-10 | Official: Linux on Ampere/Hopper/Blackwell; runtimes PyTorch, vLLM(-Omni), SGLang, Diffusers. Community: `Hob-forge/Cosmos3-Nano-GGUF`, 414 downloads, which extracts the reasoner, re-keys it to `Qwen3VLForConditionalGeneration` and runs it in llama.cpp. Q4_K_M is 5.03 GB (MEASURED, HF tree API); its card claims image understanding only. MLX ports exist only for the **generator** (`Reza2kn/Cosmos3-Nano-MLX-4bit`, text-to-image, "no mlx-vlm support exists"). INFERRED: the re-keyed reasoner should load in mlx-vlm `qwen3_vl`. Untested. |
| Cosmos3-Edge | 4B; 2B dense LLM trained from scratch | OpenMDW-1.1 | 105,918 downloads | Linux only ("not tested on other OS") |
| Cosmos3-Super | 64B total; reasoner of Qwen3-VL-32B architecture | OpenMDW-1.1 | 64,374 downloads | Linux only |
| Cosmos-Reason2-2B / 8B (the talk's model; still offered as a NIM) | 2B / 8B; Qwen3-VL base (R3 §11) | NVIDIA Open Model License; HF gated `auto` | 577,788 / 83,344 downloads | Community MLX for 2B (`hzang/Cosmos-Reason2-2B-4bit`/`-8bit`) and community GGUFs for 8B (`prithivMLmods/…`, `mradermacher/…`). Untested by us. |
| Cosmos-Embed1-448p | — | NVIDIA Open Model License | 12,946 downloads | Not checked |
| Nemotron-3-Nano-Omni-30B-A3B (VSS's audio VLM) | about 31B, 3B active | NVIDIA Open Model Agreement | 199,092 downloads | **Yes, in principle.** mlx-vlm has `models/nemotron_h_nano_omni/` with `audio.py` (`SoundEncoder`) and video pruning (DOCUMENTED, source via `gh api`, mlx-vlm v0.7.10 released 2026-10-21). `mlx-community/…-Reasoning-4bit` exists, and GGUFs exist (lmstudio-community, 30,940 downloads). R3 §4 already lists it, with a ≤2 min video limit. Untested by us. |
| Nemotron 3.5 Lightning 30B-A3B (VSS LLM) | 30B, 3B active | NVIDIA license | NVFP4 921,776 downloads | GGUF (`ggml-org/…`, `unsloth/…`) and MLX (`TensorFold/…-oQ4`). Irrelevant to us: Claude is the LLM. |

`build.nvidia.com/nvidia/cosmos-reason2-8b` now serves the **byte-identical** page of `cosmos3-nano-reasoner` (MEASURED, `cmp` of the two curl downloads). NVIDIA has effectively retired Reason2 as the hosted default.

## 7. Hosted API, pricing and data egress

- **build.nvidia.com blueprint page:**
  - It offers "Launchable" plus "Enterprise"; models cosmos3-nano-reasoner and nemotron-3.5-lightning-30b-a3b.
  - Upload an .mp4 and the free development API runs: "Your API requests may be rate limited … Upgrade Coming Soon!"
  - "Sessions end after 5 minutes of inactivity."
  - Its governing-terms footer still cites Llama-3.1-70b and Llama 3.2 retrieval models, which looks stale from 2.x (MEASURED, page text).
- **Cosmos3 Nano Reasoner page:**
  - "Downloadable · Free Endpoint".
  - Prompt guidance "up to 400 tokens … max 1000"; reasoning is switched on by a `<think>` format string (MEASURED, page text).
- **Data terms** (DOCUMENTED, NVIDIA API Trial Terms of Service):
  - The trial is for "limited trial purposes only and without use … in production".
  - §2.3: content is not stored after the session "except as stated".
  - §2.6(a): you may not submit "any confidential information".
  - §3.3(iv): NVIDIA collects "User Content and Generated Content to improve NVIDIA products and services, including AI models", and usage is "logged … and shared with third party service providers".
  - §4.3: no personal data.
  - INFERRED: corporate meeting recordings are excluded on three counts (confidential, personal data, training use).
- **Paid paths:**
  - A Brev Launchable on 2x RTX PRO 6000 SE on AWS ("starting at $10/hour" per the talk, V1 §2) (DOCUMENTED, `brev-launchable.md`).
  - Self-hosted production needs NVIDIA AI Enterprise via an account manager (talk [30:05]).
  - R5 cites about $4,500 per GPU per year from secondary sources. I found no price on NVIDIA's own pages today (not re-verified).
- **Egress when self-hosted:**
  - Video stays on your hardware. Pulling containers and weights needs NGC, and HF for Omni.
  - If you configure a remote VLM such as OpenAI or Reka, frames go there (DOCUMENTED, `configure-the-vlm.md:106-175`).
  - Security posture: no TLS between components and no authentication on the agent or MCP servers ("assumed to be provided by network-level security") (DOCUMENTED, `appendix_known-limitations.md`).

## 8. Independent evaluation

- **VSS:** I found no third-party accuracy evaluation. The web search ("NVIDIA VSS blueprint … independent review evaluation 2026") returned only NVIDIA pages and an eWeek article (2025-05) repeating Pegatron's self-reported "67 % reduction in defects".
- **VSS's own benchmarks are latency and throughput only.** The search benchmark is 121 queries over 17 vad-r1-v2 clips (72.28 MB), Top-K 5, critic on. It reports E2E latency, P90 and QPS, but no recall (DOCUMENTED, `search-performance.md:20-60`).
  - Accuracy tooling does ship: `benchmark-video-search` ("retrieval quality"), `vss-benchmark-vlm-qa` and `vss-evaluate-caption-accuracy` (LLM judge), plus NAT QA and trajectory evaluators. No results are published.
- **Cosmos3 (vendor), Cosmos 3 technical report Table 10** (research.nvidia.com/labs/cosmos-lab/cosmos3/technical-report.pdf; arXiv 2606.02800):
  - **Video-MME, LVBench, MLVU, LongVideoBench and EgoSchema do not appear anywhere in the report** (MEASURED, grep of `pdftotext` output). The only general video row is MVBench.
  - Cosmos3-Nano against its own base Qwen3-VL-8B (DOCUMENTED, vendor-run):

    | Benchmark | Cosmos3-Nano | Qwen3-VL-8B |
    |---|---|---|
    | MVBench | 73.2 | 69.1 |
    | VideoPhy2 | 45.6 | 28.2 |
    | DocVQA | 94.2 | 95.6 |
    | InfoVQA | 81.8 | 83.4 |
    | OCRBench-v2 | 60.1 | 64.1 |
    | HallusionBench | 45.3 | 50.5 |
    | General average | 69.6 | 68.9 |

  - INFERRED: Cosmos3's gains are physical-AI ones, and it is *worse* than plain Qwen3-VL-8B at reading documents and screens and on hallucination. That is the wrong trade for meeting recordings.
- **Cosmos-Reason2:** only vendor numbers (Physical AI Bench; R3 §11). Third-party aggregators (benchmarklist.com, benchlm.ai) re-import vendor scores; I found no independent Video-MME or LVBench result.
- **General caution:** REPAIR (arXiv 2607.01469, R5 §3) shows run-to-run spread of 8.05 pp in agentic VideoQA. Any VSS-style critic loop should be A/B tested with repeated paired runs.

## 9. Reusable ideas vs reusable code and models

### 9a. Ideas (architecture patterns; all INFERRED as fits for us)

1. **A subject-anchored, per-criterion critic** (`libs/vss/core/src/vss_core/search_core/critic.py:131-254`, Apache-2.0).
   - Step 1 derives at most 3 criteria from the user prompt alone, before looking at frames, plus a `subject:` key.
   - Step 2 marks each criterion true or false against *that same subject*.
   - Rules: no criteria invented from what is visible; an absence counts only when the user asked for it; never an empty object.
   - Verdict logic (`critic.py:292-310`): a self-reported "confirmed" is honoured only when every criterion is true, and "rejected" only when at least one is false. Anything else becomes UNVERIFIED.
   - Fit: our skill's full-res `Read` confirm step can adopt this almost verbatim, for meetings as well ("subject: slide titled X", "shows Q3 revenue", "speaker is presenting").
2. **Decompose, then route.** One LLM call returns a rewritten `query`, an `attributes` list, a `has_action` flag, `object_ids` and source/time bounds. Deterministic rules then pick the action: `object`, `embed`, `fusion` or `attribute`. `--original-query` is carried through so the critic checks against what was actually asked (DOCUMENTED, `search-performance.md:55-80`).
   - Meeting analogue: hard filters (speaker, window, screen-state id) and a semantic channel (transcript plus OCR), as V1 §8 already noted.
3. **A memory ladder before re-watching** (`skills/operations/vss-ask-video/SKILL.md:86-130`): hot context → agent Markdown notes → structured store → bounded introspection (≤10 records, ≤3 VLM follow-ups, 180 s; `cli-README.md:404-408`) → an exact-window VLM call.
   - If evidence is still missing: "name the missing information and ask the user … The question stays open."
   - Fit: maps onto our evidence package. Answer from the index unit and window units first, then open keyframes, then a fresh frame extract.
4. **Fps by task, with a frame cap.** Skim 0.5 fps, locate 1 fps, inspect 2 fps. Above 60 frames per window, sample 60 evenly spaced frames; "prefer a shorter window before raising FPS" (`vss-ask-video/SKILL.md:210-228`). Cheap to state in our skill's sampling guidance.
5. **Content-adaptive token pruning (Adaptive EVS).** Drop frames by similarity, using a threshold (default 0.4) and a token budget per clip. This is the same idea as our luma-diff cut detection and screen-state dedup, so it confirms rather than adds.
6. **An explicit UNVERIFIED state and zero-result honesty.** The report skill must "return an explicit zero-results report … do not invent incidents" (`vision-agent_agent-skills.md`, report error handling). This matches our citation-lint stance.
7. **Skills drive a CLI, not raw REST.** NVIDIA moved its own skills off hand-built curl calls onto a typed CLI in 3.3.0. This is design evidence for keeping our video skill's helpers as scripts with stable flags.

### 9b. Code and models (what could actually be run or imported)

| Asset | License | Runs on Mac? | Worth it for us? |
|---|---|---|---|
| `critic.py` prompt and verdict parser | Apache-2.0 | Text only, so yes | **Yes**, copy the prompt and verdict rules (with attribution) into the skill's confirm step |
| `vss` CLI / `vss_core` | Apache-2.0 (repo) | Probably as a client (INFERRED) | No: nothing to talk to without a deployment |
| 24 skills | Apache-2.0 (repo) | They load, but need a deployment | Read as examples of skill structure only |
| VSS containers and NIMs | NVIDIA Software and Model Evaluation License / AI Enterprise | No | No |
| Cosmos3-Nano reasoner | OpenMDW-1.1 | Community GGUF via llama.cpp (image); mlx-vlm untested | No: worse than Qwen3-VL-8B on DocVQA, OCR and hallucination (Table 10) |
| Cosmos-Reason2-2B/8B | NVIDIA Open Model License | Community MLX/GGUF | No (physical-AI tuned; R3 §11) |
| Nemotron-3-Nano-Omni-30B-A3B | NVIDIA Open Model Agreement | mlx-vlm with audio (DOCUMENTED source) | Maybe, as a later on-device experiment for same-pass audio+video on ≤2 min windows. It does not replace Parakeet word timings. Already flagged in R3 §4/§260; unmeasured RAM. |
| Cosmos-Embed1 | NVIDIA Open Model License | Not checked | No: our search channel is text (transcript plus OCR) |

## 10. Corrections to earlier files

- **R5 §2, "Apache-2.0 code":** only the repo is Apache-2.0. The microservice containers are under the NVIDIA Software and Model Evaluation License, and local NIM hosting needs an AI Enterprise developer licence (§1).
- **R5 §2, "Audio is not prominent":** precise version: no ASR at all; optional audio only through a remote Nemotron-3-Nano-Omni VLM; per-chunk `audio_transcript` (§4).
- **R5 §2, skills "name Claude Code, Codex, NemoClaw":** the docs also say they were "validated using Claude Opus 5" and install into `~/.claude/skills/<name>`.
- **V1, "MCP is not named anywhere in the talk":** still true for the talk. In 3.3.0, MCP covers analytics-DB queries (VA-MCP) and deployment (Orchestrator MCP), not video Q&A. Video Q&A goes through the CLI (`vss vlm run`).
- **The talk's model pair** (Nemotron Nano v2 9B + Cosmos Reason 2 8B) has been replaced by Nemotron 3.5 Lightning 30B-A3B + Cosmos3 Nano Reasoner (README:58-59).

## 11. Caveats

- Doc pages were read as `.md` exports. Tabbed tables (the GPU table per SKU) showed one tab's numbers, probably the H100 default. Other SKUs may differ.
- HF download counts are a live snapshot. Community GGUF and MLX conversions are unvetted, and I ran none of them.
- No VSS component, CLI, model or skill was executed. Every capability claim is DOCUMENTED, not MEASURED.
- The trial-terms PDF is dated 2025-10-07. build.nvidia.com links to it as the current governing terms.

## Sources

- https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization (README, release v3.3.0, `libs/vss/cli/README.md`, `libs/vss/{cli,core}/pyproject.toml`, `libs/vss/core/src/vss_core/search_core/critic.py`, `skills/operations/vss-ask-video/SKILL.md`)
- https://docs.nvidia.com/vss/llms.txt and these pages (with `.md` appended): getting-started/prerequisites, getting-started/quickstart, vision-agent/vss-agents/agent-customization/customize-models/configure-the-vlm, vision-agent/vss-agents/video-analytics-mcp-server, vision-agent/agent-harnesses/nemo-claw/vss-orchestrator-mcp, vision-agent/agent-skills, appendix/performance/agent-workflows/{video-summarization,search}-performance, appendix/known-limitations, appendix/license-information, appendix/faq, release-notes, release-notes/vss-2-x-release-notes, system-components/vision-microservices/real-time-vlm, appendix/additional-deployments/brev-launchable
- https://docs.nvidia.com/nim/vision-language-models/1.7.0/support-matrix.html
- https://build.nvidia.com/nvidia/video-search-and-summarization ; https://build.nvidia.com/nvidia/cosmos3-nano-reasoner ; https://build.nvidia.com/nvidia/cosmos-reason2-8b
- https://assets.ngc.nvidia.com/products/api-catalog/legal/NVIDIA%20API%20Trial%20Terms%20of%20Service.pdf
- NGC catalog search API: https://api.ngc.nvidia.com/v2/search/catalog/resources/CONTAINER?q=…vss
- https://huggingface.co/nvidia/Cosmos3-Nano , /nvidia/Cosmos3-Edge , /nvidia/Cosmos3-Super , /nvidia/Cosmos-Reason2-8B , /nvidia/Cosmos-Embed1-448p , /nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-BF16 , /Hob-forge/Cosmos3-Nano-GGUF , /Reza2kn/Cosmos3-Nano-MLX-4bit , /hzang/Cosmos-Reason2-2B-4bit , /mlx-community/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-4bit
- https://github.com/Blaizzy/mlx-vlm (`mlx_vlm/models/nemotron_h_nano_omni/`)
- https://research.nvidia.com/labs/cosmos-lab/cosmos3/technical-report.pdf (arXiv 2606.02800), Table 10
- https://www.eweek.com/news/nvidia-ai-blueprint-video-search/ (the only third-party item found; customer self-report)
- Local copies: `/tmp/v2-vss-src/` (README.md, docs/*.md, hf/*, paper/cosmos3.txt, terms/trial.txt, critic.py, cli-README.md, ask-video-SKILL.md, tree.txt)
