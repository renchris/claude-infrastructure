<!-- markdownlint-configure-file {
  "MD013": false
} -->

# R5: Agentic video-understanding frameworks and research systems (2026-10-24)

Axis: agent frameworks and research systems that "watch" video by tool-calling over frames, memory and search, plus the framework loaders (LlamaIndex, LangChain, Haystack, DSPy). For each one: the architecture, its benchmark wins, and whether the code can be used today by a Claude Opus 5.5 agent in Claude Code. Claude Code has no video or audio input; it takes text, images (clamped to 2000 px) and PDF.

Labels: **MEASURED** means I ran the named command today. **DOCUMENTED** means a README, source file, paper or vendor page says it; I did not run it. **INFERRED** means my own reasoning. Every GitHub star count, push date and commit count was MEASURED today with `gh api repos/<owner>/<repo>` (or `curl api.github.com/repos/...`). Benchmark numbers are the authors' own unless marked independent. Nothing was installed, no account was created and no video was uploaded. Scratch copies of fetched pages are in `/tmp/r5-fetch/`; they will not survive a reboot, so the URL is the citation of record.

Staleness rule from the brief: anything whose newest evidence is older than 2026-04-24 (six months) is flagged **STALE**.

What this extends: the prior report cited only Deep Video Discovery's LVBench numbers (`../../video-understanding-human-parity-2026-10-23/agents/F2-sota-vs-human-benchmarks.md:25`, `:28`, `:124`), and F3 named DeltaStreamer and Video-RSI without reading them (`.../F3-tinycloud-and-agent-video-tools-now.md:120-122`). Everything below is new.

## Narrative

**One architecture has won.** Nearly every serious 2025-2026 system has the same shape. An offline pass builds an index: captions per clip, a transcript, embeddings, and sometimes an entity graph. A reasoning LLM then runs a loop with search tools over that index, and fetches frames for a time window only when the text is not enough. Systems with this shape include Deep Video Discovery (DVD), EGAgent, CFD, VideoExplorer, WorldMM, DeltaStreamer and NVIDIA VSS's agent layer (DOCUMENTED, entries below). DVD has exactly three tools: `global_browse_tool`, `clip_search_tool` and `frame_inspect_tool`, the last capped at 50 frames per call. Its prompt tells the agent to "always make a CONFIRM with `frame_inspect_tool`" (DOCUMENTED, `dvd/dvd_core.py`, `dvd/build_database.py`). That is our own October pipeline with Claude as the orchestrator and `Read` on JPEGs as the frame-inspect tool (INFERRED). These designs therefore do not need to be adopted as software. They are recipes Claude Code can run itself.

**The orchestrator matters more than the framework.** DVD on LVBench scores 74.2 with o3, 68.5 with DeepSeek-R1 and 57.3 with Qwen3-32B (DOCUMENTED, arXiv 2505.18079 Table 7 text). The 2024-era agents (VideoTree, VideoAgent) score 28.8 and 29.3 on LVBench with open models (DOCUMENTED, DVD Table 3 and CFD Appendix D). On Video-MME long, VideoTree's 54.2 is now beaten by a single pass of Qwen3-VL-32B at 69.0 (DOCUMENTED, CFD Table 3). So older agent wrappers add little on top of a modern VLM. The benefit that remains is for very long video (an hour or more) and for text-only reasoners like Claude, which cannot take the video natively (INFERRED).

**Independent evidence is thin, and the one audit we have is a warning.** "Accuracy and Cost Claims Do Not Survive Re-Execution in Agentic VideoQA" (arXiv 2607.01469, 2026-07-01) ran the same agent comparison twice on identical inputs. The +7.33-point effect from the first run reversed to −4.05 points in the second. The spread between runs (8.05 points) was 1.32× the median gain that seven recent agentic VideoQA papers report (6.10 points) (DOCUMENTED). DVD's own three-run LVBench variance is small (mean 74.0, variance 0.125; DOCUMENTED, Appendix B.1), but no third party has re-run DVD. The CFD authors left DVD and EGAgent out of their head-to-head because "their public implementations were not yet available" (DOCUMENTED). That conflicts with DVD's code being public since 2025-07-08, which is a further sign of how little cross-checking happens. Treat every per-system gain below 8 points as within noise unless it has been repeated (INFERRED).

**The one benchmark that measures Opus 5.5 as a video agent is BVB.** The agent gets only `bash` plus a `frames(timestamps | count, start, end)` tool and must rebuild an indoor video as an animated Blender scene. That is exactly Claude Code's modality path. On the live leaderboard fetched today, Claude Opus 5.5 (xhigh) scores 72.4 overall, ranked 6th. GPT-6 Astra (xhigh) scores 76.3, and Gemini 4 Argon (high) scores 72.7 at $0.31 per video against Opus 5.5's $1.95 (DOCUMENTED, third-party leaderboard CSV `https://yoloytang.me/BVB/results.csv`). That gap concerns spatial layout and motion in rebuilt scenes, not QA on talking-head video.

**Code you can use today is rare.** Only three systems ship an agent-facing interface:
- **DVD:** MIT licence, `mcp_server.py` with one `query_video` tool. It calls only OpenAI or Azure, and its default config is `LITE_MODE = True`, which uses subtitles only.
- **NVIDIA VSS 3.3.0** (released 2026-10-21): agentskills.io skills that name Claude Code as a host, a `vss` CLI and MCP. It needs NVIDIA GPUs on Linux, so it cannot run on this Mac.
- **Microsoft MMCTAgent:** MCP-native, but tied to Azure, Neo4j and Blob storage.

Everything else is a benchmark harness, typically needing 1 to 8 A100- or H100-class GPUs and dataset-specific preprocessing (DOCUMENTED, READMEs). Many are STALE: the DVD repo's last commit is 2025-11-03, HKUDS VideoRAG 2026-03-18, VideoTree 2025-06-23, both VideoAgents 2024-12 and 2025-04, and OmAgent's last release is 2025-02-24 (MEASURED).

**The general frameworks do not understand video. They pass it on.**
- **LlamaIndex:** `VideoAudioReader` runs Whisper over the soundtrack, and the multimodal guide marks video "🛑 not available" (DOCUMENTED).
- **LangChain:** `YoutubeLoader` is transcript-only. `langchain-google-genai` v4.4.2 (2026-10-13) forwards video to Gemini, including Gemini's agentic video mode (DOCUMENTED, `chat_models.py:560`).
- **Haystack:** an official `twelvelabs-haystack` integration, with commits from 2026-06-25 to 2026-10-19 (MEASURED).
- **DSPy:** 3.4.1 (2026-10-12) has `Image`, `Audio` and a generic `File` data-URI type, but no video-understanding type (MEASURED, `gh api .../dspy/adapters/types`).

The "DSPy-style" idea, optimising the harness instead of the weights, shows up in video only as research: Video-RSI (2026-09) and VideoResearcher (2026-09).

**Spatial and motion.** Most systems turn frames into captions, so motion reaches the reasoner only as words (INFERRED). Four exceptions:
- **DeltaStreamer** records explicit frame-to-frame deltas and tracks with SAM2.1.
- **VSS** runs 2D and 3D detection and tracking (RT-CV, multi-view 3D tracking).
- **Fan et al.'s VideoAgent** keeps object re-ID tracking memory.
- **BVB** scores layout and motion through V-JEPA 2.1 latent similarity.

None of them ships optical-flow measurement as an agent tool, so the July finding that motion has to be measured, not captioned, still holds (`docs/research/agent-video-understanding-2026-07-26.md:252-270`; INFERRED from READMEs).

**What this means for us (INFERRED).** Do not install a framework. Borrow three designs:
1. **DVD's tool trio**, with a mandatory frame confirm.
2. **CFD's Visual-Need Router.** Caption once, then fetch frames only for appearance, on-screen text and attribute questions. CFD sends 46.2% of Video-MME questions to frames and catches 127 of the 133 cases where frames help (DOCUMENTED).
3. **VTS's zoom_in / zoom_out / shift tree navigation**, for backtracking.

All three can be implemented as local scripts plus `Read`, with no frame egress beyond Anthropic. VSS is worth revisiting only if a Linux NVIDIA box becomes available.

## Comparison table (ranked by importance to an agent builder)

| # | System | Architecture | Best reported result (author-reported unless noted) | Code usable today? | Activity (MEASURED) |
|---|---|---|---|---|---|
| 1 | Deep Video Discovery (Microsoft, NeurIPS 2025) | Caption DB (2 fps, 10 s clips) + o3 orchestrator + 3 tools (global browse, clip search, frame inspect ≤50 frames) | LVBench 74.2, 76.0 with transcripts; LongVideoBench-long 71.6 | Yes, partly: MIT; `mcp_server.py`; OpenAI/Azure only; default lite mode = subtitles only | 426★, last commit 2025-11-03 (**STALE**) |
| 2 | NVIDIA VSS blueprint 3.3.0 (Metropolis) | Real-time CV/VLM/embedding layer → Elasticsearch → MCP agent; LVS chunk-caption-aggregate | No public QA benchmark; vendor workflows only | Yes, on NVIDIA Linux GPUs only; Claude Code skills + `vss` CLI | 1,941★, v3.3.0 2026-10-21, ≥100 commits since 2026-04-24 |
| 3 | REPAIR re-execution audit (arXiv 2607.01469) | Evaluation protocol | Run-to-run spread 8.05 pp > median reported gain 6.10 pp | Protocol, not a tool | 2026-07-01 |
| 4 | BVB / Mini-BVB (arXiv 2609.15478) | `bash` + `frames` harness; rebuild video in Blender | Opus 5.5 xhigh 72.4 (#6); GPT-6 Astra 76.3; Gemini 4 Argon 72.7 (third-party leaderboard) | Yes: Docker harness, LiteLLM | 114★, pushed 2026-10-23 |
| 5 | EGAgent (Meta, ACL 2026) | Planner + visual search (SigLIP 2), transcript search, SQL entity-graph search | EgoLifeQA 57.5; Video-MME long 74.1 | Research code, CC-BY-NC-4.0 | 66★, pushed 2026-10-13 |
| 6 | CFD Caption-once, Frames-on-Demand (Huawei/QMUL, 2026-09) | Edge caption index (story skeleton + micro-log) + cloud MLLM + Visual-Need Router | Video-MME 67.5 with 5.8 frames; LVBench 52.9 (open models) | No repo found | paper 2026-09-10 |
| 7 | VideoExplorer / VideoDeepResearch (RUC/BAAI, KDD 2026) | Planner + temporal grounder (Qwen2.5-7B) + scalable perception; SFT + trajectory DPO | "significant advantage" on MLVU, LVBench, VideoMMMU (vendor) | Research code; 8×H100 eval | 154★, last push 2025-11-17 (**STALE**) |
| 8 | Video-RSI (2026-09) + VideoResearcher (2026-09) | Frozen models; an Editor agent evolves harness code and tools | Video-RSI Video-MME long 73.4→80.0 with frames 38.6→21.6 | Video-RSI: Linux, Landlock sandbox, OpenAI-compatible API | 37★, pushed 2026-10-13 |
| 9 | VideoTreeSearch (VTS, 2026-07) ← VideoTree (CVPR 2025) | Scene-boundary tree; zoom_in/zoom_out/shift/answer; SFT + RL | VTS: +12.5 mIoU CG-Bench; up to +7.1 acc vs agent baselines; VideoTree LVBench 28.8 | VTS repo has 5★; VideoTree 1 FPS EgoSchema scripts | VTS pushed 2026-09-23; VideoTree 2025-06-23 (**STALE**) |
| 10 | DeltaStreamer (Nankai/ByteDance, 2026-10) | Streaming: change-aware DAG memory + query planner + frame replay; SAM2.1 tracking; Whisper | OVO-Bench 66.07; StreamingBench 59.53 | Inference code, needs Qwen3.6-27B on NVIDIA | 87★, pushed 2026-10-22 |
| 11 | HKUDS VideoRAG / Vimo (KDD 2026) | Graph-RAG knowledge graph + multimodal context encoding; desktop app | Video-MME long 60.2 (MiniCPM-V base); LongerVideos benchmark | Source runs; macOS app "coming soon"; single RTX 3090 | 3,422★, last push 2026-03-18 (**STALE**) |
| 12 | Video-RAG (Leon1207, NeurIPS 2025) | Single-turn RAG over OCR + ASR + object-detection texts fed to LVLM | Beats GPT-4o and Gemini-1.5-Pro on Video-MME with a 72B model | Plug-and-play into any LVLM | 462★, pushed 2026-06-26 |
| 13 | LongVT (CVPR 2026) + ParaVT + VideoMind (ICLR 2026) | Open-weight VLMs trained for native `crop_video` / grounding tool calls (Chain-of-LoRA roles in VideoMind) | VideoMind-7B Charades-STA mIoU 50.2; LongVT "outperforms" on 4 benchmarks | Weights on HF; GPU | LongVT 272★ 2026-06-24; ParaVT 57★ 2026-10-08; VideoMind 362★ 2026-02-08 (**STALE**) |
| 14 | Ego-R1 (NTU, TPAMI 2026) | RL-trained 3B Chain-of-Tool-Thought over RAG, Video-LLM, VLM tools; week-long egocentric | Ego-R1 Bench (44.3 h) 46.0 vs Gemini-1.5-Pro 38.3 | Research code + 25K CoTT data | 170★, pushed 2026-06-10 |
| 15 | WorldMM (CVPR 2026 Highlight) | Episodic + semantic + visual memories; adaptive retrieval agent | +8.4% average over prior SOTA on 5 long-video QA sets | Research code, uv-pinned | 129★, pushed 2026-07-29 |
| 16 | Vgent (KAUST, NeurIPS 2025 spotlight) | Offline clip graph + retrieval + structured verification | +3.0 to 5.4% on MLVU; +8.6% vs video-RAG | 8×A100 suggested | 53★, pushed 2025-11-30 (**STALE**) |
| 17 | Microsoft MMCTAgent | Planner/critic swarm over Neo4j temporal KG; MCP server | No standard benchmark | MCP yes; Azure OpenAI/Neo4j/Blob | 83★, pushed 2026-08-26 |
| 18 | VideoAgent ×2 (Stanford ECCV 2024; Fan et al. ECCV 2024) + OmAgent | LLM-as-agent over CLIP/VLM tools; structured memory + object re-ID; divide-and-conquer | EgoSchema 54.1 / NExT-QA 71.3 (Stanford) | Run, but dated (Video-LLaVA, GPT-4-era) | 155★ 2025-04 / 335★ 2024-12 / OmAgent release 2025-02 (all **STALE**) |
| 19 | Framework loaders: LlamaIndex, LangChain, Haystack, DSPy | Transcript loaders, or pass-through to Gemini / TwelveLabs | n/a | Yes, but no native video understanding | All active (Oct 2026) |

## Entries

### 1. Deep Video Discovery (DVD), Microsoft Research Asia

- **Gives an agent:** a deep-research loop over one long video. A caption-and-embedding database is built first. The orchestrator then calls `global_browse_tool` (overview from clip captions, top-k 300), `clip_search_tool` (embedding search over clips, top-k 16) and `frame_inspect_tool` (VQA over at most 50 frames for given HH:MM:SS ranges), then `finish` (DOCUMENTED, `dvd/dvd_core.py`, `dvd/build_database.py`).
- **Modality path:** yt-dlp download, decoded at **360p, 2 fps**, cut into **10 s clips**, captioned by `gpt-4.1-mini` and embedded with `text-embedding-3-large`. The orchestrator is `o3`, with `MAX_ITERATIONS = 3` (DOCUMENTED, `dvd/config.py`). The paper used 5 s clips and GPT-4.1 captions for LVBench. Audio: optional transcript (+1.8 points on LVBench). **Default `LITE_MODE = True` removes frame inspection and pixels and uses only SRT subtitles** (DOCUMENTED, `config.py`; README 2025-07-16).
- **Results (author-reported):**
  - LVBench 74.2, or 76.0 with transcripts; earlier v1 figures were 71.9 / 74.1.
  - LongVideoBench long 71.6, Video-MME long 67.3, EgoSchema val 76.6.
  - On the pure OpenAI API path the score is 71.9, and only 24% of LVBench items passed the content filter unfiltered (Appendix table).
  - Orchestrator swaps: DeepSeek-R1 68.5, Qwen3-32B 57.3.
  - Three runs: mean 74.0, variance 0.125 (DOCUMENTED, arXiv 2505.18079 HTML).
- **Independent evidence:** none found. Third-party leaderboards copy the paper's number (benchmarklist "imported 2026-05-28").
- **Claude fit:** `mcp_server.py` exposes one FastMCP tool, `query_video(video_url, question)`. It downloads, decodes, captions and runs the agent, all through OpenAI or Azure (DOCUMENTED, source read). The README still lists "Implement MCP server" as unchecked, so the server exists but is not presented as finished. As a dependency: every frame and caption goes to OpenAI or Azure, and the o3 orchestrator duplicates Claude's job. **Best use:** copy the tool contract into Claude Code, with Claude as orchestrator and `Read` as frame inspect (INFERRED).
- **Maturity:** NeurIPS 2025; code first released 2025-07-08; 426★; last commit 2025-11-03 (MEASURED). **STALE.**
- **Pricing:** MIT; API costs not published (unknown).

### 2. NVIDIA AI Blueprint: Video Search and Summarization (VSS) 3.3.0 (Metropolis)

- **Gives an agent:** a full video-analytics stack in three layers:
  - real-time video intelligence: RT-CV 2D/3D detection and tracking, RT-Embed embeddings, RT-VLM dense captions and incidents;
  - downstream analytics: behaviour analytics, alerts, Elasticsearch;
  - an agent layer that reaches search, Q&A, long-video summarisation (LVS) and clip retrieval through MCP (DOCUMENTED, README).
- **3.3.0 (2026-10-21) is aimed squarely at coding agents:**
  - a `vss` CLI "as the supported way to operate a running deployment from a coding agent", with command groups `vios`, `vlm`, `summarize`, `search`, `memory` and `analytics`;
  - agentskills.io skills that name "Claude Code, Codex, NemoClaw";
  - Elasticsearch-backed agent memory, with introspection that "requests at most three grounded VLM follow-ups";
  - Adaptive EVS video-token pruning (DOCUMENTED, release notes and `skills/README.md`).
- **Modality path:** native video into NVIDIA VLMs (Cosmos3 Nano Reasoner) with chunked dense captions; LLM is Nemotron 3.5 Lightning 30B-A3B. Live RTSP is supported. Audio is not prominent in the README.
- **Deployment:** Docker Compose or Helm on Ubuntu 24.04 x86, DGX Spark/Station or Jetson Thor. The base and LVS profiles need 1 shared H100 or RTX PRO 6000 Blackwell, or 2 dedicated; search needs 2 to 4. A remote LLM or VLM reduces but "does not remove the GPU required by the profile services". **No macOS support** (DOCUMENTED, docs.nvidia.com/vss prerequisites).
- **Spatial and motion claims:** the strongest of any entry. Multi-view 3D tracking, BEV fusion and trajectories. These are vendor claims with no independent eval found.
- **Claude fit:** best-in-class integration (skills plus CLI plus MCP), but all of it runs off-machine on a GPU box. Video stays on your own infrastructure if self-hosted.
- **Pricing:** Apache-2.0 code. Self-hosted NIM is free for development on up to 16 GPUs through the NVIDIA Developer Program. Production NIM needs NVIDIA AI Enterprise, about $4,500 per GPU per year (secondary sources, 2026; not verified on NVIDIA's page today). Launchable: 2× RTX PRO 6000 on AWS, at AWS rates.
- **Maturity:** 1,941★; ≥100 commits since 2026-04-24; v3.2.0 2026-06-16, v3.2.1 2026-07-23, v3.3.0 2026-10-21 (MEASURED).

### 3. REPAIR: "Accuracy and Cost Claims Do Not Survive Re-Execution in Agentic VideoQA" (arXiv 2607.01469, 2026-07-01)

- **Gives an agent builder:** a way to discount the numbers. Static-SAGE and Dynamic-SAGE were run twice on 1,283 identical SAGE-Bench pairs with the same config, tools, prompts and backbone. The paired effect went from +7.33 to −4.05, both individually significant. The run-to-run spread (8.05 pp) exceeds six of the seven reported gains of recent agentic VideoQA systems (median 6.10 pp). Fewer visible tool calls "do not imply reproducible reductions in primitive computation or latency" (DOCUMENTED, abstract and §5.2).
- **Claude fit:** use the protocol (paired comparison repeated at least twice) for any A/B test of our own video harness. It is a method, not a tool.
- Label: DOCUMENTED (independent of the systems it critiques).

### 4. BVB (Blender-VideoBench) and the Mini-BVB harness (arXiv 2609.15478)

- **What it measures:** an agent in a Docker Blender 4.2 sandbox has only `bash` and `frames` (frames at given timestamps, or `count=N` evenly spaced within start/end). It must rebuild one of 288 VSI-Bench indoor videos as an animated `.blend`, under a $3 cost cap. Scoring: Dual VQA (`gpt-5.4-mini` on 16 frames of the render) and V-JEPA 2.1 latent similarity on 64 frames, split into layout and motion (DOCUMENTED, README and `sandbox/README.md`).
- **Opus 5.5 numbers (third-party leaderboard, fetched 2026-10-24, MEASURED fetch of `results.csv`):**

  | Model | Effort | Overall | Rank | Cost per video | Minutes per video |
  |---|---|---|---|---|---|
  | GPT-6 Astra | xhigh | 76.3 | #1 | $1.72 | n/a |
  | Gemini 4 Argon | high | 72.7 | #5 | $0.31 | n/a |
  | Claude Opus 5.5 | xhigh | 72.4 | #6 | $1.95 | 13.8 |
  | Claude Sonnet 5.5 | xhigh | 72.3 | #7 | n/a | n/a |
  | Claude Opus 5.5 | high | 68.1 | #20 | $0.49 | n/a |

  The repo CSV snapshot (2026-09-14) predates the Opus 5.5 rows.
- **Why it matters:** it is the only benchmark found that tests Claude in exactly our modality path (frames pulled by tool calls, no audio). The spatial and motion axis is independently evidenced, though by a single-lab benchmark.
- **Maturity:** 114★, pushed 2026-10-23 (MEASURED). On 2026-10-19 the authors fixed missing multiple-choice options in Dual VQA, so earlier numbers may shift (DOCUMENTED).

### 5. EGAgent: "Agentic Very Long Video Understanding" (Meta Reality Labs, ACL 2026)

- **Architecture:** a planning agent with three tools:
  - visual search over SigLIP 2 embeddings;
  - audio-transcript search, either an LLM reading transcript windows or BM25;
  - SQL queries over an entity scene graph (people, places, objects, relations over time) stored in SQLite (DOCUMENTED, paper §3 and README).
- **Results:** EgoLifeQA 57.5 (state of the art) and Video-MME long 74.1. With a Gemini 2.5 Pro backbone it adds +10.7 points over uniform-sampling Gemini 2.5 Pro (46.8). It also helps a GPT-4.1 backbone (DOCUMENTED).
- **Claude fit:** the entity-graph-in-SQLite idea suits multi-day recordings (meetings, wearables). The licence is **CC-BY-NC-4.0**, so copy the idea, not the code.
- **Maturity:** 66★, created 2026-01-16, pushed 2026-10-13, 4 commits since 2026-04-24 (MEASURED).

### 6. CFD: Caption-once, Frames-on-Demand (arXiv 2609.11899, 2026-09-10)

- **Architecture:** an edge device makes one captioning pass into a two-track narrative index (an event-level story skeleton plus a clip-level micro-log), cached across queries. A cloud MLLM then reasons "story-first". A per-query **Visual-Need Router** fetches bounded keyframes only for perceptual questions (appearance, on-screen text, attributes) and keeps temporal and structural questions in text (DOCUMENTED).
- **Results:**
  - Video-MME 67.5 overall with 5.8 frames at answer time (Qwen3-VL 32B), versus VideoTree 60.6 and VideoLucy 64.7.
  - LVBench 52.9 versus MemVid 44.4, VCA 41.3, VideoTree 28.8 and VideoAgent 29.3, all on open models.
  - The router sends 46.2% of questions to frames and catches 127 of 133 frame-helpful cases (DOCUMENTED, Table 3, Appendix D, Table 16).
- **Claude fit:** the most directly portable cost design for Claude, where every image costs tokens and context. A router prompt plus our existing sheet and crop tools would do it (INFERRED). No code repo found.

### 7. VideoExplorer, formerly VideoDeepResearch (RUC / BAAI; KDD 2026)

- **Architecture:** planner, temporal grounder and "temporally scalable" perception, in a loop: sub-question, locate, perceive, repeat. Planner and grounder are Qwen2.5-7B, with LanguageBind for clip embedding. Training is SFT then trajectory-level DPO. The KDD version adds sub-agents (DOCUMENTED, arXiv 2506.10821 v6 and README).
- **Results:** "significant advantage" on MLVU, LVBench, VideoMMMU and MH-NIAH. Evaluated on 8×H100 (DOCUMENTED, vendor claims).
- **Code:** `RUC-NLPIR/VideoDeepResearch` (old URL redirects), 154★, last push 2025-11-17 (MEASURED), **STALE**. Dataset on HF (`avery00/VideoExplorer-Dataset`).

### 8. Video-RSI (2026-09) and VideoResearcher (arXiv 2609.19664): harness self-improvement, the closest thing to DSPy for video

- **Video-RSI:** model weights stay frozen. A Solver runs, and an Editor investigates its training failures by "revisiting videos" for new visual, transcript and OCR evidence. The Editor then rewrites prompts, tools, memory and execution code, and keeps a revision only if it wins on paired accuracy and frame cost on a private gate set (DOCUMENTED, README). Results, initial harness → evolved, with DeepSeek-V4-Pro + Qwen3.6-Plus:

  | Benchmark | Accuracy | Frames per question |
  |---|---|---|
  | Video-MME long | 73.4 → 80.0 | 38.6 → 21.6 |
  | MLVU | 62.4 → 72.9 | n/a |
  | EgoSchema subset | 71.4 → 78.2 | n/a |

  Frame counts exclude the Editor's own investigation (DOCUMENTED).
- **VideoResearcher:** a training-free multi-agent system that designs, tests and refines executable video tools. It claims state of the art among self-improving agents, "approaching the human-designed upper bound" (DOCUMENTED, abstract). No repo found.
- **Claude fit:** this is the right shape for improving our own `/watch`-style harness offline. Note that REPAIR (#3) says gains under about 8 points need repeated runs. Video-RSI needs Linux with Landlock and seccomp, so it does not run on macOS.
- **Maturity:** Video-RSI 37★, pushed 2026-10-13, MIT (MEASURED).

### 9. VideoTreeSearch (VTS, arXiv 2607.16189) and its ancestor VideoTree (UNC, CVPR 2025)

- **VideoTree (2024):** query-adaptive k-means clustering of 1 fps frame features into a coarse-to-fine tree of captions for an LLM. EgoSchema 61.1, NExT-QA 75.6 (DOCUMENTED). It is weak on hour-long video with open models (LVBench 28.8 per DVD and CFD tables). Repo 172★, last push 2025-06-23, **STALE**.
- **VTS (2026-07):** builds a non-uniform tree from scene boundaries, and a trained agent navigates it with `zoom_in`, `zoom_out`, `shift` and `answer`. Backtracking is an explicit primitive, used in about 60% of trajectories, averaging 4.8 turns. Results: +12.5 mIoU on CG-Bench and +7.4 T-F1 on Haystack-Ego4D over prior agents, and up to +7.1 accuracy on Video-MME, MLVU and LVBench (DOCUMENTED).
- **Claude fit:** the four-action tree is a cheap, prompt-only design for Claude with a scene-cut list. Note our measured trap that cut lists are a lower bound (commit 11f8feeb2).
- **Code:** `CeeZh/VTS`, 5★, MIT, pushed 2026-09-23 (MEASURED).

### 10. DeltaStreamer (Nankai / ByteDance, arXiv 2610.19849, 2026-10-14)

- **Architecture:** streaming. It continuously records explicit visual deltas between consecutive frames into a hierarchical DAG memory, with entity index and evidence pointers. A query planner then retrieves and **replays historical frames** when text memory is missing detail. Tools: SAM2.1 tracking, Whisper base, Qwen3.6-27B for observation and planning (DOCUMENTED, README).
- **Results:** OVO-Bench 66.07, StreamingBench 59.53 (DOCUMENTED). A downstream livestream-companion app has shipped.
- **Spatial and motion:** the only research system here that stores *change* explicitly instead of per-frame descriptions. That is closest to the motion gap we measured.
- **Code:** inference code, no training needed, NVIDIA GPUs. 87★, pushed 2026-10-22 (MEASURED).

### 11. HKUDS VideoRAG and the Vimo desktop app (KDD 2026)

- **Architecture:** graph-driven knowledge indexing across videos plus multimodal context encoding. It claims "hundreds of hours" on a single RTX 3090 (DOCUMENTED).
- **Results:** Video-MME long 60.2 versus MiniCPM-V 56.3 with subtitles; LongerVideos benchmark of 160+ videos and 134+ hours. The README itself warns that "the score may show slight fluctuations across runs" (DOCUMENTED).
- **Claude fit:** the Vimo macOS Apple Silicon beta is still "coming soon". Source runs as a server with an Electron UI, and there is no MCP. HKUDS's separate `VideoAgent` repo (1,972★, EMNLP 2026, pushed 2026-07-22) is mostly editing and remixing, not understanding.
- **Maturity:** 3,422★, last push 2026-03-18, 0 commits since 2026-04-24 (MEASURED). **STALE.**

### 12. Video-RAG (NeurIPS 2025)

- **Architecture:** single-turn and training-free. External tools extract OCR, ASR and object-detection text, which is retrieved and appended to the LVLM prompt with the frames (DOCUMENTED).
- **Results:** state of the art on Video-MME with a 72B model, beating GPT-4o and Gemini-1.5-Pro (vendor claim, 2024-era baselines).
- **Claude fit:** this is already our pipeline (OCR, ASR, detections as text). Its value is as a citation that auxiliary text helps more than extra frames.
- **Code:** `Leon1207/Video-RAG-master`, 462★, pushed 2026-06-26 (MEASURED).

### 13. Trained tool-calling video VLMs: LongVT (CVPR 2026), ParaVT, VideoMind (ICLR 2026), SAGE (CVPR 2026)

- **LongVT:** the model calls its own temporal grounding as a native `crop_video` tool to zoom in and resample frames. Three-stage SFT and RL; weights, data and demo on HF since 2025-11-28. **ParaVT** (2026-05-20) adds parallel tool calls (DOCUMENTED).
- **VideoMind:** planner, grounder, verifier and answerer roles on one base model with switched LoRAs ("Chain-of-LoRA"). 2B/7B results: Charades-STA mIoU 45.2/50.2, Video-MME long 46.3/49.2 (DOCUMENTED).
- **SAGE (AllenAI):** an any-horizon orchestrator trained with RL. Its SAGE-Flash variant uses Gemini-2.5-Flash as a tool (71.8 on SAGE-Bench) (DOCUMENTED, secondary). Repo `allenai/SAGE` 70★, last push 2025-12-17, **STALE**.
- **Claude fit:** these could serve as a local *tool* Claude calls ("find the moment where X"), especially VideoMind's grounder for timestamps. All need CUDA GPUs; none ships an MCP server (INFERRED).
- **Maturity:** LongVT 272★ (2026-06-24), ParaVT 57★ (2026-10-08), VideoMind 362★ (2026-02-08, **STALE**) (MEASURED).

### 14. Ego-R1 (NTU S-Lab et al., TPAMI 2026)

- **Architecture:** a Qwen2.5-3B agent trained with SFT on 25K Chain-of-Tool-Thought traces, then GRPO. It calls a hierarchical RAG index (10 s and 600 s segments), a Video-LLM and a VLM over week-long egocentric video (DOCUMENTED).
- **Results:** 46.0 on Ego-R1 Bench (44.3 h average) versus Gemini-1.5-Pro 38.3 and VideoAgent 32.6 (DOCUMENTED, Table 1).
- **Code:** usable for research, with a veRL training stack. 170★, pushed 2026-06-10, Apache-2.0 (MEASURED).

### 15. WorldMM (CVPR 2026 Highlight)

- **Architecture:** episodic memory (multi-scale events), semantic memory (continuously updated concepts) and visual memory (scene detail). An adaptive retrieval agent picks the memory source and granularity until it has enough (DOCUMENTED).
- **Results:** +8.4% average over the previous state of the art on five long-video QA benchmarks (DOCUMENTED). That is barely above REPAIR's 8.05-point noise band.
- **Code:** 129★, pushed 2026-07-29, uv-pinned, EgoLife-specific preprocessing (MEASURED).

### 16. Vgent (KAUST / Meta, NeurIPS 2025 spotlight)

- **Architecture:** an offline graph over clips preserving semantic relations, then retrieval, then a structured verification step to cut retrieval noise, then generation (DOCUMENTED).
- **Results:** +3.0 to 5.4% over base LVLMs on MLVU and +8.6% over prior video-RAG (DOCUMENTED). The gains sit inside REPAIR's noise band.
- **Code:** "Suggest to run on 8 A100 GPUs", torchrun scripts per benchmark. 53★, last push 2025-11-30, no licence file (MEASURED). **STALE.**

### 17. Microsoft MMCTAgent

- **Architecture:** a "critical thinking" planner and critic. Two orchestrations: a Graph Agent swarm (Planner, Video, Image) traversing a Neo4j temporal knowledge graph, and a deterministic Graph State pipeline. Video ingestion does scene segmentation into the KG. An MCP server is built in (DOCUMENTED, README).
- **Claude fit:** MCP-reachable, but the defaults are Azure OpenAI, Neo4j and Azure Blob, so video and frames leave the machine. The production app shown (DigitalGreen) is not in the repo.
- **Maturity:** 83★, MIT, pushed 2026-08-26, 1 commit since 2026-04-24 (MEASURED).

### 18. The 2024 classics: VideoAgent (Stanford), VideoAgent (memory-augmented, Fan et al.), OmAgent (Om AI)

- **Stanford VideoAgent:** an LLM agent iteratively asks for more frames through CLIP retrieval and VLM captions. EgoSchema 54.1 / NExT-QA 71.3 using about 8.4 frames. The repo README still carries leftover VisDiff text; 155★, pushed 2025-04-16.
- **Fan et al. VideoAgent:** structured memory of temporal event descriptions plus **object-centric tracking state with re-ID**. Tools are segment localisation and object-memory queries; it needs a Video-LLaVA server and an RTX 4090. 335★, pushed 2024-12-05.
- **OmAgent:** divide-and-conquer video agent and a general multimodal agent framework. 2,669★, but its last release is v0.2.4 (2025-02-24). Of its 3 commits since 2026-04-24, all are a TwelveLabs integration PR from a TwelveLabs employee, merged 2026-10-16 (MEASURED).
- **Assessment:** all **STALE**, and superseded by single-pass modern VLMs on standard benchmarks (CFD Table 3). Useful only as history, and for the object-memory idea.

### 19. General framework loaders: LlamaIndex, LangChain, Haystack, DSPy

- **LlamaIndex:**
  - `VideoAudioReader` = Whisper over the mp4 audio track, last changed 2025-05-01 (DOCUMENTED, source).
  - The multimodal guide's support table marks Video "🛑 not available" (DOCUMENTED).
  - Readers exist for YouTube transcripts, Bilibili and Kaltura, plus `llama-index-retrievers-videodb`, which delegates to VideoDB's cloud (MEASURED, directory listing).
- **LangChain:**
  - `YoutubeLoader` = transcripts via youtube-transcript-api (DOCUMENTED, secondary).
  - `langchain-google-genai` libs/genai v4.4.2 (2026-10-13) sends video parts with `video_metadata` offsets to Gemini and handles Gemini's "agentic video responses" (DOCUMENTED, `chat_models.py:560-624`).
- **Haystack:** official `twelvelabs-haystack` (9 commits, 2026-06-25 to 2026-10-19), plus `whisper`, `funasr` and `google_genai` integrations (MEASURED).
- **DSPy:** 3.4.1 (2026-10-12) has `Image`, `Audio` and a generic `File` data-URI type. Its vendored `lm15` video module covers video *generation* jobs (DOCUMENTED, source). No video-understanding signature type was found.
- **Assessment:** none of these understands video. Each either transcribes, or forwards the video to Gemini, TwelveLabs or VideoDB. For a Claude Code agent they add nothing over calling those APIs directly, and they add a Python runtime (INFERRED).

## Not found, dead, or out of scope

- "VideoExplorer" as a separate repo: `yhy-2000/VideoExplorer` returns 404. The code lives at `RUC-NLPIR/VideoDeepResearch` (MEASURED).
- `yhy-2000/VideoDeepResearch` is a 301 redirect to `RUC-NLPIR/VideoDeepResearch` (MEASURED).
- `Leon1207/Video-RAG` returns 404; the repo is `Leon1207/Video-RAG-master` (MEASURED).
- CFD and VideoResearcher: no public code repo found (web and GitHub search).
- DSPy video-understanding module or type: not found. Search hits were video *generation* (`leockl/vidspy`).
- Haystack: no deepset-native frame or video component, only the TwelveLabs pass-through.
- Out of scope here, but worth another axis: VideoDB Director (1,560★, last push 2026-01-23, **STALE**; a cloud-backed agent framework) and agent-integration repos such as `mupozg823/timecode-agent` (52★, 2026-08-06) and `JazerJu/video-miner` (33★, 2026-09-27).

## Sources

- https://github.com/microsoft/DeepVideoDiscovery and https://arxiv.org/abs/2505.18079 (HTML v4 read)
- https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization (README, release v3.3.0, `skills/README.md`); https://docs.nvidia.com/vss/latest/prerequisites.html
- https://arxiv.org/abs/2607.01469 (REPAIR)
- https://github.com/yunlong10/BVB ; https://yoloytang.me/BVB/results.csv ; https://arxiv.org/abs/2609.15478
- https://github.com/facebookresearch/egagent ; https://arxiv.org/abs/2601.18157
- https://arxiv.org/abs/2609.11899 (CFD)
- https://github.com/RUC-NLPIR/VideoDeepResearch ; https://arxiv.org/abs/2506.10821
- https://github.com/bingjunluo/Video-RSI ; https://arxiv.org/abs/2609.19664
- https://github.com/CeeZh/VTS ; https://arxiv.org/abs/2607.16189 ; https://github.com/Ziyang412/VideoTree ; https://arxiv.org/abs/2405.19209
- https://github.com/BBBBchan/DeltaStreamer ; https://arxiv.org/abs/2610.19849
- https://github.com/HKUDS/VideoRAG ; https://arxiv.org/abs/2502.01549 ; https://github.com/HKUDS/VideoAgent
- https://github.com/Leon1207/Video-RAG-master ; https://arxiv.org/abs/2411.13093
- https://github.com/EvolvingLMMs-Lab/LongVT ; https://github.com/EvolvingLMMs-Lab/ParaVT ; https://github.com/yeliudev/VideoMind ; https://arxiv.org/abs/2512.13874 ; https://github.com/allenai/SAGE
- https://github.com/egolife-ai/Ego-R1 ; https://arxiv.org/abs/2506.13654
- https://github.com/wgcyeo/WorldMM ; https://arxiv.org/abs/2512.02425
- https://github.com/xiaoqian-shen/Vgent ; https://arxiv.org/abs/2510.14032
- https://github.com/microsoft/MMCTAgent
- https://github.com/wxh1996/VideoAgent ; https://github.com/YueFan1014/VideoAgent ; https://github.com/om-ai-lab/OmAgent ; https://arxiv.org/abs/2406.16620
- https://developers.llamaindex.ai/python/framework/module_guides/models/multi_modal/ ; https://github.com/langchain-ai/langchain-google ; https://github.com/deepset-ai/haystack-core-integrations/tree/main/integrations/twelvelabs ; https://github.com/stanfordnlp/dspy
- NIM pricing (secondary): https://pi3g.com/nvidia-ai-enterprise-subscription-cost-in-2026/ ; https://developer.nvidia.com/blog/access-to-nvidia-nim-now-available-free-to-developer-program-members
