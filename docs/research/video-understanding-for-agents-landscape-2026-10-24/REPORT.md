<!-- markdownlint-configure-file {
  "MD013": false
} -->

# Video understanding for agents: the landscape for a Claude Opus 5.5 agent (2026-10-24)

Our agent is Claude Opus 5.5 in Claude Code. It has **no video or audio input**: text, images and PDF only, with every image Read clamped to 2000 px per side, and the API capped at 600 images per request (MEASURED and DOCUMENTED, `HP:43-45`). So every product below reaches it through a tool. This draft merges the ten axis reports (R1-R10), the completeness critic (C1) and an adversarial check of a 37-entry sample (§7). Every correction from that check is applied.

Labels: **MEASURED** = retrieved or run by us (an API read, a curl, our own probe). **DOCUMENTED** = a vendor page, card, paper or repo says it. **INFERRED** = our reasoning. **ESTIMATED** = arithmetic on documented prices (a kind of INFERRED). Short cites: `R1:53` = `agents/R1-agent-native-startups.md` line 53 (likewise R2-R10, C1, V1); `HP` = `../../video-understanding-human-parity-2026-10-23/REPORT.md`; `SK` = `skills/video-understanding/SKILL.md`. Prices are as read on 2026-10-24 unless another date is given.

## Bottom line: what to use today, by job

1. **Private or local footage: keep our local transcode** (ffmpeg, FluidAudio Parakeet ASR, Apple Vision OCR, targeted 2000 px Reads). It is the only route where Claude sees the pixels itself and nothing leaves the machine except to Anthropic. It scored 23-24/24 against 11/24 for transcript-only on our probe (MEASURED, `HP:15`). Add a local Qwen3.6 (vision) or Qwen3-Omni-30B-A3B (vision plus audio) sub-model on mlx-vlm for triage only (`R3:54`, `R3:81`).
2. **Public long-video Q&A: Gemini 3.8 Flash in agentic mode**, on a paid key or Vertex, escalating to **Gemini 4 Argon** (GA 2026-10-13, paid tier only). It is the only first-class native video-plus-audio path. Cost is about $0.27/h at low resolution until 2026-12-31, then double (ESTIMATED, `R10:311`). Keep our own ASR for timestamps, because Gemini's drift on long media (`R10:273-274`).
3. **Meeting recordings: local Parakeet, tuned diarization, OCR of the screen share, keyframes.** The notetaker MCPs (Fireflies, Fathom, Granola, Otter) return transcripts only. Recall.ai is the only capture API that hands an agent pixels, at 360p and 2 fps, in its cloud (`R8:173`, `R8:301`).
4. **Screen recordings and UI: Jam MCP** (frames plus console and network logs) or **Replay MCP** (recorded runtime state) for web bugs; **screenpipe** for local screen history; our pipeline at ≥1080p with OCR for everything else. The one independent UI-video eval (GUIDE) found Claude 4.5 Sonnet with 32 sampled frames best on 3 of 4 tasks (`R8:105`, `R8:129`, `R8:268`).
5. **Motion and 3-D space: no product closes the gap.** Independent boards keep frontier models 20-60 points below humans (DOCUMENTED, `HP:20`). Measure instead: our motion probes, plus tracks and points from Molmo2-8B (local) or SAM 3.1 (Meta-hosted at $0.20 per 1,000 frames), and Gemini Robotics-ER 2 for moment finding. Elorian Glimpse (launched 2026-10-15) is the one new model pitched at this gap. Its numbers are self-reported, so test it before trusting it (`C1:33`).
6. **Search over many videos: Marengo 3.5** (segments the video itself and embeds the audio) **or Gemini Embedding 2 plus a transcript index**, hosted. Fully local: Qwen3-VL-Embedding plus its reranker in LanceDB OSS or Qdrant. Zero-code: VideoDB's hosted MCP, if uploading is acceptable. Never average CLIP vectors over keyframes (`R9:38`, `R9:325-333`).
7. **Evidence warning.** No commercial video service has an independent evaluation (`R10:23-28`). The check of 37 entries found something to correct in every one, and an error that would change a decision in 12 of them (§7).

## 1. The three architectures

What Claude receives decides what it can know. Every product maps to one of three routes (taxonomy from `R4:21-27`, extended; INFERRED).

| Route | What Claude gets | What is lost | Typical cost and egress | Products |
|---|---|---|---|---|
| **A. Native-video model** (another model takes frames and often audio, Claude gets its text) | Prose or JSON with timestamps, written by another model | Claude never sees pixels, so it cannot check the answer. Default sampling is 1-2 fps; Google, Amazon and Perceptron all warn that fast or brief events are missed (`R2:271-273`). Hosted APIs silently cap tokens per video: Qwen VL about 32K, Seed 80K, Nova 960 frames at 672x672 (`R2:268`). Timestamps drift on long media (`R10:273`) | $0.03-1.75/h. The whole file leaves the machine, unless the model runs locally | Gemini (API, Vertex, CLI, Live), Gemini 4 Argon, Qwen3.8-Omni, Seed 2.1, Meta Muse, Elorian Glimpse, Amazon Nova 2, Robotics-ER 2, Perceptron, TwelveLabs Pegasus analyze; relays (claude-video Gemini engine, Watch Any Video, Z.ai Vision MCP, openrouter MCP); **locally**: Qwen3.6/3.8, Qwen3-Omni, Molmo2, MiniCPM, Nemotron Omni on mlx-vlm or llama.cpp |
| **B. Server-side text or vector index** (video turned once into text tracks or embeddings, which the agent queries) | Captions, transcripts, OCR, labels and vectors with times, plus clip links | Whatever the indexer did not write down: layout, motion continuity, identity over time, paralinguistics (`HP:126`). Tinycloud cuts any result over 6,000 characters to a one-line summary (`HP:125`) | $1.00-11.40/h hosted. Upload, except for self-hosted indexes | Cloudglue/Tinycloud, TwelveLabs Jockey and Marengo, Memories.ai, VideoDB, Mixpeek, Reka Vision, Valossa, Azure Content Understanding and Video Indexer, Bedrock Data Automation, Rekognition, Snowflake and BigQuery SQL, NVIDIA VSS (self-hosted), embedding APIs plus vector stores, notetaker MCPs (transcript-only index), screenpipe (local index), Pixeltable (local) |
| **C. Local transcode** (frames, ASR and numeric probes made by tools; Claude reads the pixels) | Chosen frames up to 2000 px, a transcript, measurements | Anything between samples; hearing; continuous motion; Claude must choose where to look, which is where recent Opus versions rank lowest (VideoGAIA, §4) | $0 for tools plus $0.08-2.66/h of Opus input (ESTIMATED, `R10:308`). Frames go only to Anthropic | Our `skills/video-understanding`, claude-video (local engine), claude-real-video, claude-eyes, watch-skill, mcp-video-analyzer, claude-video-vision, videoctx, ffmpeg-skill; vendor-side variants that still hand Claude frames: Jam `getFrames`, Recall.ai frame stream, LiveKit and Pipecat cascaded mode, Mux `@mux/ai` with Claude; browser MCP screenshots (weakest) |

Two add-ons cut across the routes. **G, geometry as data:** tracks, boxes, points, pose and camera trajectory, from VLM Run (SAM 3.1, ViTPose), Perceptron, Molmo2, SAM 3.1, Robotics-ER 2, Cosmos 3, Vidi2, Depth Anything 3 and VGGT, YOLO trackers, and VSS's CV layer. This is the only output that answers "where and when did X move" with numbers an agent can check (`R2:271-273`, `R1:185`). **R, replace the video with recorded state:** Replay's runtime recording, Jam's console and network logs, PostHog events. For UI bugs this carries what a watcher would miss (`R8:21-31`, INFERRED).

## 2. Ranked tables by category

Columns: route (A, B, C, +G), where it runs, price, evidence strength, and Claude Code fit including egress. Ranked by importance to an agent builder.

### 2.1 Agent-native startups

| # | Name | What it gives an agent | Route | Where | Price | Evidence | Claude fit |
|---|---|---|---|---|---|---|---|
| 1 | **TwelveLabs** Pegasus 1.6, Marengo 3.5, Jockey (`R1:53`, `R1:63`) | Pegasus 1.6 (2026-10-06) analyses up to 2 h of a source up to 4 h, 261,120-token context, text or JSON with timestamped segments. Marengo 3.5 gives **embeddings only**; its search runs on Marengo 3.0 indexes. Jockey (GA 2026-10-15) reasons over a hosted knowledge store | A (Pegasus), B (Jockey) | Cloud; Pegasus 1.2/1.5 also on Bedrock (no 1.6 there) | $1.75/h video input plus $7.50/M output; Free, Plus $29/mo, Pro $99/mo; **overage only on Pro**; $4 per 1,000 searches on Marengo 3.0 | Vendor only. Homepage: "+13.1% vs Gemini 3.1 Pro on Multimodal Prompting" and "#1 on Video-MME"; the official Video-MME board has no Pegasus row (MEASURED, verifier) | Claude Code plugin still defaults to Pegasus 1.5 (PR #7 for 1.6 open, unmerged). Jockey is an OAuth remote MCP. Uploads everything; the privacy policy (2026-01-12) uses data and outputs "to improve the Twelve Labs Services" |
| 2 | **VideoDB** (`R1:93`, `R9:201`) | 89 MCP tools: index, search, ask, edit, subtitles, live RTSP alerts, desktop capture; playable evidence clips. Analyzer graph: transcript, scene VLM, OCR, COCO object detection, activity recognition | B (+G detections) | Cloud; SDK Apache-2.0 | Unpublished ("talk to us"); $20 free credits; third parties list $20/mo Pro | Vendor-run action-retrieval benchmark only (Hit@10 40.39, data downloadable) | `/plugin marketplace add video-db/skills` adds the hosted MCP; `npx skills add` installs the skill **without** the MCP. Media stored until deleted; transcription audio used "to improve our algorithms" |
| 3 | **Memories.ai** Video Datalake (`R1:71`) | Index once, then `search_moments` and `get_moment`: captions, transcripts, speakers, faces, live-stream SSE. Its "events" are **safety detections**, a paid add-on | B | Cloud | $0.05/min at fps 1 ($3.00/h), about $0.90/h at fps 0.3; `get_moment` $0.008; derived reads $0.001; optional $20/mo starter | None; its comparison pages now 404 | Hosted OAuth MCP plus plugin (1 star, last push 2026-07-27). Uploads; training terms unreadable |
| 4 | **VLM Run** Gateway MCP (`R1:108`) | `read_video` returns prose, JSON, **SAM 3.1 per-frame tracks** (up to 128 frames) or **ViTPose keypoints** | A+G | Cloud gateway (beta); open-weight models | Default qwen3.8-27b $0.35/$2.55 per M; vendor estimator about $0.20/h at 0.25 fps; SAM 3.1 about $0.035 per clip | Vendor only | Hosted MCP with `readOnlyHint`; anonymous free tier. **The gateway does sample frames**, at resolution presets up to 640x480, too low for small text (verifier). Vendor says inputs are not stored or trained on |
| 5 | **Elorian Glimpse** (`C1:33`) | A hosted visual-reasoning model that re-watches short intervals more densely while it reasons | A, no audio | Cloud (OpenRouter, Vercel, Together) | $0.60/$3.00 per M (MEASURED, OpenRouter) | Self-reported only: TOMATO 93.6, Video-MME-v2 with subtitles 56.68 | Skill script posting the clip; egress; data terms unchecked. Research preview, launched 2026-10-15/17 |
| 6 | **Perceptron** Mk1.5 (`R1:116`, `R2:211`) | Grounded `<clip>` moments and `<track>` timestamped boxes and points; accepts caller-chosen timestamped frames | A+G | Cloud | $0.15/$1.50 per M | Vendor only; its docs warn sampling misses brief events | Hosted MCP; one media item per call; 36,864-token context, so short clips only |
| 7 | **Mixpeek** (`R1:143`, `R9:214`) | Hosted multimodal retrieval: transcript, Gemini-written descriptions, OCR, faces, Gemini Embedding 2 vectors, moment merging | B | Cloud; dedicated or bring-your-own-cloud on Enterprise | Video index $0.05/min ($3.00/h); multimodal understanding $0.0292/min ($1.75/h), "as of August 2026" (re-read 2026-10-24) | Vendor only | Hosted MCP (docs disagree: 48 to 91 tools). Content goes on to **Google Gemini** (privacy policy 2026-08-31). Read-only only through the App server's `mixpeek:read` OAuth scope |
| 8 | **Cloudglue / Tinycloud** (`R1:131`) | Describe, extract, search, chat; server-written text tracks | B | Cloud | $2.40-3.60/h | None | CLI, 8 skills, plugin, MCP; uploads. No release since 0.3.25 (2026-09-01); team of 3 |
| 9 | **Reka Vision** (`R1:135`) | Index, search, Q&A, clips | B | Cloud; Reka Edge weights local | $3.00/h; 3 h free | None | Local stdio `reka-mcp` wrapping the cloud; free-tier usage may train its models |
| 10 | Overshoot, Coactive, Imaginario, vertical YC entrants (`R1:151`, `R1:165`) | Live-stream addressing (Overshoot); enterprise tagging; camera-search verticals | A, B | Cloud | Overshoot list passthrough; others sales-led | Vendor only | Overshoot has **pivoted** to inference optimisation; the others have no Claude integration |

### 2.2 Frontier models with native video, via API

| # | Name | What it gives an agent | Route | Where | Price | Evidence | Claude fit |
|---|---|---|---|---|---|---|---|
| 1 | **Gemini 3.8 Flash**, static and agentic (`R2:65`) | Video file, GCS object or public YouTube URL in; text or JSON with MM:SS out. Agentic mode navigates the timeline itself (transcript first, then segments) | A, with audio | Cloud (AI Studio, Vertex) | $0.75/M input until 2026-12-31, then $1.50: about $0.27/h low resolution, $0.81 high (ESTIMATED) | Gemini 3 Flash on Video-MME-v2: 42.5 vs human 90.7 (owner-run). 3.8 Flash: self-reported only. Agentic "up to 88% fewer tokens": vendor-run | Skill or CLI; whole file to Google. Paid tier is not used for training; free tier is (`R4:35`) |
| 2 | **Gemini 4 Argon** (`R2:91`) | The quality tier for hard long-video questions | A, with audio | Cloud, **paid tier only**; GA 2026-10-13 ("Stable"), not Fairwind-limited as R10 had it (verifier) | $2/$10 per M until 2026-11-30, then $4/$20: $0.72/h low now, $1.44 from 2026-12-01; high resolution exceeds one call | Google-run LVBench 91.7 at 1 fps (§4). Agentic video **is** listed in the AI Studio video doc (verifier; R2:24-27 read the `.md.txt` copy) | Same as Flash |
| 3 | **Gemini 3.5 Flash-Lite** (`R2:107`) | Cheapest native audio-plus-video bulk pass; supports agentic mode | A | Cloud | $0.30/M: about $0.11/h low | Vendor only | Pre-pass before escalating flagged segments |
| 4 | **ByteDance Seed 2.1** Pro/Turbo (`R2:142`) | Timestamp-interleaved frames, 0.2-5 fps, frame and token budget control | A; audio on "some models" | Cloud (BytePlus) | Turbo $0.50/$2.50 per M; about $0.04/h because of the 80K-token cap (ESTIMATED) | Self-reported TOMATO 79.5. Independent: Seed 2.0 Pro tops VideoGAIA at 58.3 and scores 43.3 on Video-MME-v2 | OpenAI-compatible; doc says data is not retained for training |
| 5 | **Qwen3.8-Omni-Flash** (`R2:113`) | Gemini-like omni model with audio, agentic watching, tools | A, with audio | Cloud (Alibaba, multi-region) | $0.15/$0.47 per M: about $0.03/h (ESTIMATED) | Vendor only | 20-line OpenAI-SDK skill; Alibaba training terms unverified |
| 6 | **Gemini Robotics-ER 2** (`R2:202`, `R8:197`) | Points, boxes, trajectories, object tracking in video, moment finding, task-progress detection | A+G | Cloud, preview (2026-07-30); ER 1.6 shut down | $1/$5 per M until 2026-12-31, then $2/$10 | **Vendor-reported** (R2 said none): moment finding 91.3%, 0.96 s mean error; progress 57.4% (verifier) | Skill returning JSON. The streaming variant lacks structured output |
| 7 | **Meta Muse Spark 1.3 / Wonder**, plus hosted **SAM 3.1** (`R2:160`, `R2:222`) | mp4 with embedded audio (audio on 1.3 "not fully supported"); SAM 3.1 text-prompted tracks | A; A+G | Cloud (api.meta.ai) | Spark $1.25/$4.25; Wonder $4/$20; Contributor mode $0.10/$0.20 **trains on your data**; SAM 3.1 $0.20 per 1,000 frames | Vendor only; the Wonder card lists 3-D spatial reasoning as a known limitation | `fps` is a request parameter (verifier). Meta also runs an **Anthropic Messages-compatible endpoint**, so a skill can use the Anthropic SDK |
| 8 | **Amazon Nova 2** Lite (GA), Omni and Pro (preview) (`R2:184`, `R2:195`) | Lite: frames only, every frame distorted to 672x672, no audio | A | Bedrock | Lite $0.30/M: about $0.08/h. Omni and Pro in-region us-east-1: Pro $1.375/M, Omni audio $1.10/M (global rates are lower) | Vendor only; docs admit "limited spatial reasoning". Omni and Pro in preview for over 10 months | Stays in your AWS account |
| 9 | **Qwen VL API** models (`R2:131`) | Cheap video QA without audio | A | Cloud | $0.005-0.07/h because of a roughly 32K-token-per-video cap (ESTIMATED) | Vendor only | Send a curated image list to avoid the silent downscale |
| 10 | **Gemini Live API** (`R2:175`) | Real-time camera or screen plus mic over WebSocket | A, streaming | Cloud | About $0.42/h of streamed audio and video | Vendor only | Poor fit: Claude Code has no streaming surface; at most 1 fps |
| 11 | OpenAI GPT-6, xAI Grok 4.7, Mistral Large 4 (`R2:230-251`) | **No video input**; OpenAI takes up to 1,500 images per request | C-like | Cloud | n/a | Absence documented | No advantage over Claude for video |

### 2.3 Open-weight video models (local sub-models)

All free weights (2026-10-24). The pattern for Claude is a localhost server (`mlx_vlm.server`, `llama-server`, vLLM) behind a skill or MCP tool that returns text, times or points; nothing leaves the machine after the download (`R3:19`, `R3:257-264`). **Treat every card's Video-MME as an upper bound:** third-party runs are 7-12 points lower, and on Video-MME-v2 the best open model scores 39.1 against 90.7 for humans (`R3:14`).

| # | Name | What it gives an agent | Route | Runs on | Evidence | Claude fit and caveats |
|---|---|---|---|---|---|---|
| 1 | **Qwen3.6-27B / 35B-A3B** (+ Qwen3.5 sizes) (`R3:54`) | Default local video QA with timestamps, thinking and tool calls; no audio | A | Mac 32-64 GB at 4-bit (about 16-20 GB), Apache-2.0 | Card: 82.5 Video-MME without subtitles; OpenBMB re-run 75.7 (35B-A3B) and 70.2 (27B); Video-MME-v2 Qwen3.5-27B 31.4 | Replaces Qwen3-VL, which SK:144 still names |
| 2 | **Qwen3-Omni-30B-A3B** Instruct and Thinking (`R3:81`) | Hears the video's audio while watching | A, with audio | mlx-vlm `use_audio_in_video` (default False); BF16 needs at least 78.85 GB for a 15 s clip (vendor minimum) | Card: Video-MME 70.5; independent Video-MME-v2 17.1 | The **Captioner variant is audio-only**. llama.cpp's ggml-org GGUF lists audio and vision but not video with audio; `vllm serve` exposes the thinker only. Released 2025-09 (older than 6 months) |
| 3 | **Molmo2-8B / 4B** (`R3:107`) | Video pointing, counting and tracking as frame index plus x,y | A+G | mlx-vlm `molmo2`; Apache-2.0, training data partly non-commercial | Vendor paper: Molmo2-Track J&F 56.2 vs Gemini 3 Pro 44.6; no replication | The best open answer to "where and when did X move". Have Claude verify sample points at 2000 px |
| 4 | **Nemotron-3-Nano-Omni-30B-A3B** (`R3:95`) | Video up to 2 min plus audio up to 1 h | A, with audio | mlx-vlm, GGUF, vLLM | Secondary-source numbers only | Set `video_pruning_rate=0` on short clips |
| 5 | **MiniCPM-V 4.7** 35B-A3B and 1B (`R3:131`) | High-fps video via stacked sub-frames | A | mlx-vlm `minicpmv4_7` (BF16 needs about 71 GB; 4-bit about 23.5 GB); Apache-2.0 | Vendor chart at the default 16x compression: Video-MME 74.70, MotionBench 68.02 (the often-quoted 76.40 is the 4x column; Qwen3.6-27B scores higher on MotionBench, 69.11) | The UI-oriented prompt on the card is generic, not a UI benchmark (verifier) |
| 6 | **Qwen3.8-27B** (`R3:72`) | Newest open Qwen, strongest agentic multimodal score at 27B | A | Same as Qwen3.6 | OpenBMB: MotionBench 65.11, below Qwen3.6-27B | Use 3.6 for video until measured |
| 7 | **Keye-VL-2.0-30B-A3B** (`R3:149`) | "When does X happen" temporal grounding | A | GGUF, SGLang; no MLX build | Vendor TimeLens lead | Timestamp finder; MLX path unverified |
| 8 | **Gemma 4** (`R3:121`) | Clips of 60 s or less at 1 fps; audio up to 30 s | A | Widest runtime support | No video scores on cards | Short clips and audio snippets only |
| 9 | **NVIDIA Cosmos 3 Reasoner** (`R8:218`) | Physical-world video reasoning at 4 fps, 2D/3D points and boxes | A+G | Datacentre GPU; OpenMDW-1.1 | Vendor only | **Cosmos-Reason2 is superseded**: its repo is in limited maintenance and its HF collection archived (verifier) |
| 10 | **Vidi1.5-9B** (ByteDance) (`C1:178`) | Temporal retrieval only | A | Local GPU; CC-BY-NC-4.0 | Vendor benchmarks | **No boxes in the open weights**; Vidi2/2.5 spatio-temporal grounding is demo-only and needs an upload (verifier) |
| 11 | Server-class omni and video MoEs: MiMo-V2.5/V2.6, Muse Spark Open (816B), Ming-flash-omni 2.0, Kimi K3.1 Pro, Step-5, MiniMax M3.1, Ling-3.0-flash-VL (`R3:160`, `C1:86-131`) | Video (some with audio) in OpenAI-style messages | A | API via OpenRouter ($0.06-2 per M input); self-host needs a GPU server | No video benchmarks on the cards | API sub-tools with egress. Muse Spark Open is Meta's "most powerful American open-weight model" claim, not "largest"; its DaVinci Resolve demo ran through Meta's agent and does not prove native video input (verifier) |
| R | Runtimes: **mlx-vlm 0.7.10**, **llama.cpp libmtmd** (`R3:240`, `R3:247`) | Native video on Apple Silicon; model-agnostic ffmpeg video in llama.cpp | — | Local, MIT | MEASURED repo facts | **Trap:** mlx-vlm silently falls back to 16 stills for models without a video processor (`R3:17`) |

### 2.4 Agent integrations: MCP servers, skills, CLIs

| # | Name | What it gives an agent | Route | Where | Price | Evidence | Claude fit and egress |
|---|---|---|---|---|---|---|---|
| 1 | **claude-video** `/watch` (`R4:93`) | URL or file to frames plus transcript, or a Gemini-written answer | C or A | Local or Google | Free | None; open issues: ffmpeg 9 extracts zero frames (#99, #117), Whisper invents dialogue on silent video (#222) (`R10:283-290`) | 19,118 stars. **Gemini is the default whenever a key resolves** (`--engine auto`, model gemini-3.7-flash); with it, Claude sees no frames. Pin `WATCH_ENGINE=local`. Its "balanced" cap is 100 frames **per video**, not per hour |
| 2 | **watch-skill** (`R4:131`) | Index then ask, with OCR, transcripts and deterministic verification contracts; 39 MCP tools | C | Local-first, MIT | Free | Vendor-run benchmark vs an unnamed API (groundedness 89.7% vs 27.9%) | **Best egress design found:** a cloud engine needs separate consent even with a key present. DeepWatch is a DeepSeek-centred workspace that adds nothing for Claude |
| 3 | **claude-real-video** (crv) (`R4:101`) | Scene-change keyframes, contact sheets, time windows, local diarization, SQLite memory; 5-tool MCP | C | Local, MIT core | Free; Pro $29 one-time (camera-motion labels, OCR); Codex build $9.90 adds OCR | Self-measured only | The **free core has no OCR**; small text relies on `--frame-width 1600`. 2,257 stars |
| 4 | **claude-eyes** (`R4:139`) | Five-track index (cuts, words said, words shown with positions, loudness, palette), full-resolution `crop --box`, burst | C | Local, MIT | Free | Self-test: 88/92 cuts, 0/8 dissolves | Closest to our design; skill plus `eyes --json`, no MCP yet |
| 5 | **mcp-video-analyzer** (`R4:116`) | 8 tools: transcript, OCR, timeline, frames at a time, bursts | C | Local | Free | None | Egress traps: `OPENAI_API_KEY` sends audio to OpenAI; `TWELVELABS_API_KEY` sends URLs to TwelveLabs (`R4:79-80`) |
| 6 | **Gemini CLI** as sidecar (`R4:108`) | `gemini -p "... @clip.mp4"` returns Gemini's native audio-visual answer | A | Local CLI, Google model | Free login or API rates | Vendor only | Files over 20 MB refused. Do not use "key-free" bridge MCPs that reuse its OAuth; they break its terms |
| 7 | **Z.ai Vision MCP** (`C1:57`) | `video_analysis` on clips of 8 MB or less, plus screenshot OCR and UI diff | A | Local npx, Z.ai cloud (GLM-5.3-Flash) | GLM Coding Plan from $18/mo | No video eval; 47,418 npm downloads in 30 days (MEASURED) | One-line `claude mcp add`; egress to a China-HQ vendor |
| 8 | **Watch Any Video** (`R4:151`) | Zero-install remote MCP relaying to Gemini's paid tier | A | Cloud | $8/mo or $60/yr for 20 h | Vendor ("Answers can be wrong") | Whole file to Google via the vendor |
| 9 | **Mux** `@mux/ai` + `@mux/mcp` (`C1:155`) | Summaries, chapters, moderation, burned-in-caption checks over Mux-hosted video, with **Claude as the vision model** if chosen | C (cloud) | Mux cloud | Usage plus tokens, unknown | Self-run evals published per push | The video must live in Mux |
| 10 | Hosted vendor connectors: TwelveLabs plugin and Jockey, Memories.ai plugin, VideoDB, Valossa (`R4:143-174`) | Search and Q&A over a hosted library | B | Cloud | See §2.1, §2.6 | Vendor only | Use for public video only (`R4:86`) |
| 11 | **Browser MCPs** (Playwright, Chrome DevTools, Claude in Chrome) (`R4:197`) | Screenshots of a playing page; DOM access | C (degenerate) | Local browser; Claude in Chrome is proprietary | Free / paid Claude plans | None | Weakest route. Playwright's default view is an accessibility snapshot and its video recording is opt-in (`--caps=devtools`); Chrome DevTools MCP has `screencast_start`. A page script can seek `video.currentTime`, so timing is slow but controllable (INFERRED, verifier) |
| 12 | Transcript-only YouTube MCPs (`R4:211`) | Captions and metadata | B (text) | Local | Free | Our probe: transcript-only 11/24 vs 23-24/24 full pipeline (`HP:15`) | Fine for speech-only questions |

SDK fact that constrains every custom tool: Claude Agent SDK tools can return image blocks, but **audio blocks reach Claude as a file path (TypeScript) or are dropped (Python)**. A tool that "returns audio to Claude" gives it nothing to hear (`R4:43`, DOCUMENTED).

### 2.5 Agent frameworks and research systems

| # | Name | What it gives an agent | Route | Where | Evidence | Claude fit |
|---|---|---|---|---|---|---|
| 1 | **Deep Video Discovery** (MSRA) (`R5:81`) | Three tools (global browse, clip search, frame inspect) with a mandatory frame "CONFIRM" | B then C | Local orchestration, OpenAI/Azure models; MIT; last commit 2025-11-03 (stale) | Author-reported LVBench 74.2 with o3. Corrected: 71.6 is LongVideoBench **val overall** (long subset 68.6); the 3-run mean 74.0 is the transcript setting. Only 24% of its LVBench requests passed Azure content filtering unfiltered (verifier) | Copy the tool contract, with Claude as orchestrator and Read as frame inspect. Repo defaults differ from the paper (10 s clips, gpt-4.1-mini), and the default `LITE_MODE` removes the frame tool the prompt demands |
| 2 | **NVIDIA VSS 3.3.0** (`R5:96`, `R8:246`, V1) | Self-hosted CV, embeddings and VLM captions behind an agent; Claude Code skills, `vss` CLI, Video Analytics MCP | B+G | Linux NVIDIA GPUs, Jetson Thor, DGX Spark; no macOS; Apache-2.0 | Vendor only | Best agent integration in its class, but not for this Mac or for meetings (`V1:9-16`). Audio transcription is an opt-in flag; `VLM_MODE=remote` sends frames off the box (verifier) |
| 3 | **CFD** caption-once, frames-on-demand (`R5:147`) | A Visual-Need Router: fetch frames only for appearance, on-screen text and attribute questions | B then C | Paper only | Author-reported: 46.2% of questions routed to frames, 127/133 frame-helpful cases caught | The most portable cost design for Claude: a router prompt plus our sheet and crop tools |
| 4 | **BVB / Mini-BVB** harness (`R5:120`) | Benchmark where the agent has only bash plus a frames tool | C | Docker | Third-party leaderboard with Opus 5.5 (§4) | Reusable to score our own pipeline |
| 5 | **REPAIR** audit (`R5:114`) | Repeated paired runs: one +7.33-point effect reversed to −4.05 | — | Paper | Independent | Use its protocol for any A/B of our harness |
| 6 | **Realtime frameworks**: LiveKit Agents, Pipecat, Google ADK Live, Stream Vision-Agents (`C1:70`, `R1:161`) | Live camera or screen feeds into voice agents | C (cascaded) or A (realtime model) | Self-host, Apache-2.0 / BSD-2 | No video evals; docs say about 1 fps cannot see motion | Claude fits only LiveKit's and Pipecat's cascaded mode, about one still per turn (LiveKit sends the frame at native size). **ADK Live runs on the Gemini Live API only** (verifier) |
| 7 | **EGAgent** (Meta) and **M3-Agent** (ByteDance) (`R5:137`, `C1:195`) | Entity graph over time (SQLite); entity-centric memory of faces and voices | B | Research code; EGAgent CC-BY-NC, M3-Agent Apache-2.0 (stale) | Author-reported | Designs to borrow for multi-day or person-centric footage |
| 8 | **Video-RSI**, **VTS**, **DeltaStreamer** (`R5:162`, `R5:177`, `R5:184`) | Harness self-improvement; zoom/shift tree navigation with backtracking; change memory with SAM2.1 tracks | — | Linux or CUDA research code | Author-reported | Recipes, not installs |
| 9 | **HKUDS VideoRAG / Vimo** (`R5:191`) | Graph-RAG over many videos; desktop app | B | Local, but **Vimo sends frames to Alibaba DashScope** and the default LLM is OpenAI; ImageBind makes it non-commercial (verifier) | Author-reported | Not the private option it looks like |
| 10 | Trained tool-calling VLMs (LongVT, VideoMind, SAGE), VideoExplorer, Vgent, MMCTAgent, 2024 classics, LlamaIndex/LangChain/Haystack/DSPy loaders (`R5:156`, `R5:205-256`) | Grounding tools, planner/grounder splits, or plain pass-through to Gemini or TwelveLabs | — | Mostly CUDA research code | Author-reported; several stale; VideoExplorer's "KDD 2026" venue unverified | Borrow ideas only; the loaders add nothing over calling the provider directly |

### 2.6 Hyperscaler and data-platform services

| # | Name | What it gives an agent | Route | Price | Evidence | Claude fit |
|---|---|---|---|---|---|---|
| 1 | **Gemini on Vertex** ("Gemini Enterprise Agent Platform") (`R6:74`) | Same models as the Gemini API, with US/EU residency endpoints; agentic mode (`v1beta1` only; models: 4 Argon, 3.8/3.7/3.6 Flash, 3.5 Flash-Lite, **not** plain 3.5 Flash) | A | Gemini API rates; non-global endpoints about 10% more; promos are credits back | As Gemini | **First-party remote MCP exists**: `aiplatform.googleapis.com/mcp/generate` with `generate_content` accepting GCS `fileUri` and `videoMetadata` (verifier; agentic mode over MCP unverified). Opus 5.5 is also on Vertex, so one project and jurisdiction is possible |
| 2 | **Azure Content Understanding** (`R6:141`) | Diarized WebVTT transcript, shots, keyframes, per-segment fields and RAG Markdown | B | Extraction $1.00/h; contextualization $0.001 per 1K tokens; new advanced meter $0.003 per 1K from 2026-08-01 (MEASURED, Azure Retail Prices API) | Vendor only; docs admit 1 fps at 512x512 loses rapid motion and small text | Cheapest hyperscaler route to transcript, shots and keyframes; `cu-cli` and MarkItDown now exist |
| 3 | **Amazon Bedrock Data Automation** (`R6:192`) | Shots with SMPTE timecodes, chapters, transcript with speakers, per-frame OCR with boxes, logos | B (+G text boxes) | $3.00/h standard, $5.04/h custom (MEASURED, AWS price feed 2026-10-16) | Vendor only | AWS removed its dedicated MCP on 2026-04-17; use the CLI or generic AWS API MCP |
| 4 | **TwelveLabs on Bedrock** (`R6:237`) | Pegasus 1.2/1.5 and Marengo 3.0 on the AWS invoice | A, B | Pegasus $1.76/h + $7.50/M output; Marengo $2.52/h | Vendor only | One model version behind TwelveLabs direct |
| 5 | **Azure AI Video Indexer**, cloud and Arc (`R6:256`) | The broadest classic insight catalogue; Prompt Content API | B (+G tracked objects) | $3.46 / $6.84 / $11.40 per hour (basic / standard / advanced) | Vendor only | Cloud edition has had no new features for about 7 months, but the **Arc edge edition is active** (live analysis preview, Video Agents Foundry sample, 2026-06); the "investment moved to Content Understanding" line was a guess (verifier) |
| 6 | **Snowflake Cortex** and **BigQuery `AI.GENERATE`** (`C1:133`) | Video Q&A and video embeddings as SQL over warehouse files | A, B | Warehouse credits, unknown | Vendor only | Governed route with no new vendor. Trap: BigQuery silently uses only the first 2 minutes |
| 7 | **Rekognition Video**, **OCI Vision** (`R6:326`, `R6:378`) | Per-feature labels, faces, celebrities, text, frame-accurate shots | B+G | $6.00/h per feature (both) | Vendor only | Specialist signals only. OCI's stream service also detects objects and faces (tracking: faces only); Gemini on OCI may call Vertex outside OCI (verifier) |
| 8 | **Google Video Intelligence API** (`R6:357`) | Legacy annotations | B | Per feature | — | **Deprecated 2026-09-14, shutdown 2027-09-14**; do not build on it |

### 2.7 Build-your-own primitives (what a local pipeline is made of)

| # | Name | What it gives an agent | Where | Evidence | Claude fit |
|---|---|---|---|---|---|
| 1 | **FluidAudio** Parakeet TDT v3, diarization, VAD (`R7:125`) | Word-timed transcript and speaker turns from a local CLI | Local Neural Engine; installed | MEASURED: 20.8% WER vs 24.5% for the best Whisper setting on 7 meetings; 0 hallucinated cues over silence. Diarizer needs a threshold tuned per file | Default audio channel |
| 2 | **Apple Vision** OCR, flow, tracking (`R7:175`) | On-screen text with boxes; optical flow; box tracking | macOS built-in | MEASURED: OCR 1.000 legibility at tiled 1080p, 0.76 at 720p; OCR raised screen questions from 0.17-0.25 to 0.83 | Small Swift CLI emitting JSON |
| 3 | **Apple SoundAnalysis** (`R7:301`) | 300+ sound classes with time ranges | macOS built-in | MEASURED: music ≥0.5 in 14/14 title and 10/10 outro windows, 0/480 dialogue windows; missed a ducked song (`HP:36`) | First audio-event layer |
| 4 | **whisper.cpp** (`R7:142`) | 99-language fallback ASR | Local, MIT | MEASURED traps: loops, filler over silence, invented speaker names | For languages outside Parakeet's 25 |
| 5 | **NeMo-Speech.cpp** + Nemotron 3 Diarization (`R7:153`) | `transcribe --diarize --json`, up to 8 speakers | Local (Metal) | Vendor DER about half of pyannote; MEASURED tie with community-1 on one private recording | Second-opinion diarizer |
| 6 | **PE-A-Frame** (Meta) (`R7:287`) | Free-text sound description in, start and end times out (40 ms) | Local PyTorch, Apache-2.0; MPS untested | Vendor only; card 2025-12 | The candidate for laughter and applause |
| 7 | **OmniShotCut** v1.5 (`R7:228`) | Shots with dissolve, fade and wipe labels | CUDA (unlicensed MLX port) | Vendor only | Fills the dissolve gap (claude-eyes 0/8; PySceneDetect fades 14-26% recall, `R7:191`) |
| 8 | **SAM 3 / 3.1** (`R7:243`) | Noun phrase in, masks and track IDs out | CUDA; hosted by Meta at $0.20 per 1,000 frames | Vendor only | Numbers for counts, positions, entries and exits |
| 9 | **Depth Anything 3**, VGGT, MapAnything (`C1:166`) | Camera pose trajectory, depth, 3D tracks | CUDA-first; DA3 Small/Base Apache-2.0 | Author benchmarks | Deterministic pan/tilt/dolly labels (INFERRED) |
| 10 | Others: PySceneDetect 0.7.2, pyannote 4 (Precision-3 hosted €0.112/h), PaddleOCR 3.7, SigLIP 2, YOLO26 (AGPL) / RF-DETR, CoTracker3, WAFT/SEA-RAFT, mlx-audio, ffmpeg 9 + PyAV 19 + torchcodec 0.17 (`R7:191-414`) | Cuts, diarization, OCR off-Mac, frame search, detection, point tracks, flow, decoding | Mostly local | Mostly vendor | Avoid decord (last release 2021) |

### 2.8 Vertical and specialty

| # | Name | What it gives an agent | Route | Price | Evidence | Claude fit |
|---|---|---|---|---|---|---|
| 1 | **Jam MCP** (`R8:105`) | `getFrames` (grid, exact ms, window), transcript, AI chapters, console, network, user events for bug recordings | C+R | Free (5-min recordings) / Team $14 per creator per month | Vendor only | Remote OAuth MCP; some tools call Gemini |
| 2 | **Replay MCP** (`R8:129`) | Time-travel debugging: variables, call stacks, network, React renders, screenshots at any moment | R | Free to $170/mo; private cloud $1,000+/mo | Vendor case study | No video at all, which is the point for web bugs |
| 3 | **screenpipe** (`R8:154`) | Local searchable memory of screen and audio over MCP; 1 fps video export | B (local) | Free (1 device, limited history); Basic $21/mo; Business $42/seat/mo (verifier; R8 had "unknown") | Vendor only | Stays local, but PostHog analytics is on by default; commercial use needs a licence |
| 4 | **Recall.ai** (`R8:173`) | Raw meeting video, per-participant audio, real-time 360p 2 fps frames | C (frames to your code) | $0.50/h plus $0.15/h transcription | Vendor docs | Only pixel source for live meetings; 360p is too low for small text |
| 5 | **Meeting notetaker MCPs** (Fireflies, Fathom, Granola, Otter) (`R8:301`) | Transcripts, summaries, notes | B (text) | Granola MCP on **every tier** (Basic: 30 days, no transcripts); Fathom now owned by Superhuman (2026-09-14); Otter has an official MCP (Enterprise) (verifier) | Vendor; third-party tool counts | No visuals reach Claude |
| 6 | **GUIDE** benchmark (`R8:268`) | 67.5 h of novice screen recordings | — | Free | Independent (§4) | Tests exactly our frames route |
| 7 | **PostHog** replay MCP and Replay Vision (`R8:286`) | Session search and AI summaries; Vision (closed beta) renders DOM replays to video for Gemini | B / A | Credits | Vendor | Analytics side of UI video |
| 8 | Others: Descript, Loom via Atlassian Rovo, Spot AI, **Verkada Catalyst** (private beta, announced 2026-09-16, read-only, works on still thumbnails per vendor examples), Tavus Raven (live calls only), Magnifi (sports) (`R8:316-380`, `C1:145`) | Transcripts and edit summaries; camera events; live perception | Mixed | Mostly unpublished | Vendor | Narrow fits |

### 2.9 Search, embedding and index infrastructure

| # | Name | What it gives an agent | Where | Price | Evidence | Claude fit |
|---|---|---|---|---|---|---|
| 1 | **Marengo 3.5** (`R9:128`) | One space for video, audio, image, text; segments video itself; embeds audio | Cloud | $0.26 per M video tokens; tokens per minute unpublished | Vendor; one competitor-run number (VideoDB Hit@10 32.87) | No `/search` on 3.5: search your own store. 3.0 and 3.5 vectors are incompatible |
| 2 | **Gemini Embedding 2** (`R9:139`) | Text, image, video, audio, PDF in one space; you chunk | Cloud; GA 2026-04-22 (verifier) | $0.00079 per frame: $0.76-2.84/h | Google's paper; Mixpeek's small run 0.769 (Mixpeek resells it; March, preview model) | Gemini API **ignores audio** and reads at most 32 frames per 120 s chunk; pair with a transcript index. Only a 5-star community MCP |
| 3 | **Qwen3-VL-Embedding** + Reranker (`R9:167`) | Open video and text embeddings with a second-stage reranker | Local, Apache-2.0 | Free | Card plus a competitor's re-measurement (Tencent: 68.5 / 70.6 / 54.7, near Gemini Embedding 2; mixed evaluators). Weights last updated 2026-04 | On a Mac, sentence-transformers on MPS; vLLM/SGLang need a GPU box (then not local). No audio |
| 4 | **Mixedbread** Wholembed v3 (`R9:179`) | Managed multi-vector stores that index audio and video | Cloud | Ingest $2.16 / $4.32 per h; storage $0.72 per h-month | Vendor 66.97 average | mgrep does not document video |
| 5 | **Amazon Nova MME** (`R9:159`) | Segmenting async jobs with audio-video combined | Bedrock | $2.52/h | Competitor-run Hit@10 35.40 | AWS SDK script |
| 6 | **VideoDB**, **Mixpeek** managed indexes (`R9:201`, `R9:214`) | Captions, transcript, OCR, objects, vectors behind hosted MCPs | Cloud | See §2.1 | Vendor | Zero-code, upload required |
| 7 | **WeMM-Embedding**, **PE-AV**, **Voyage multimodal-3.5**, **VideoPrism** (`R9:221-309`) | Newest open embedder (self-reported top MMEB-V2); open audio-visual embeddings; the one Weaviate video module that works; JAX encoders | Mixed | Free or per-pixel | Self-reported or competitor-run | PE-AV is the only open model that embeds audio with video |
| 8 | Stores: **Qdrant**, **LanceDB OSS**, **Pixeltable**, Weaviate, Milvus, Pinecone (`R9:272-301`, `C1:186`) | Vector storage; Pixeltable adds incremental computed columns over a video table | Local or cloud | OSS free | n/a | Qdrant has an MCP. **LanceDB Geneva is proprietary, Enterprise-only and pre-alpha**, and its TwelveLabs example uploads video; LanceDB OSS is the local choice. Pixeltable's MCP needs `PIXELTABLE_HOME` too; its README example sends audio to OpenAI (verifier). Weaviate's TwelveLabs module silently ignores video |
| — | Frame-averaged CLIP (SigLIP 2, X-CLIP, InternVideo2) (`R9:310`) | Frame look-alike search | Local | Free | Independent-ish: NDCG@10 0.30-0.47 vs 0.76-0.77 for API models | Fine for "find a frame like X", wrong for "when does X happen" |

## 3. Price per hour of video (one full pass, input side)

Assumptions (ESTIMATED unless marked): one pass at the route's default sampling, Gemini at low media resolution (about 100 tokens per second with audio), output tokens excluded (a 5K-token answer adds $0.02-0.10), list prices read 2026-10-24 or on the date shown. Method and sources: `R10:297-332`, with verifier corrections.

| Route | $ per video-hour | Basis |
|---|---|---|
| Local transcode (ffmpeg, FluidAudio, Apple Vision) | **$0** plus machine time | No egress |
| Qwen3.8-Omni-Flash | ~$0.03 | $0.15/M, per-video token cap, audio rate assumed (`R2:113`) |
| Seed 2.1 Turbo | ~$0.04 | 80K-token cap × $0.50/M; heavy downscale on long input |
| Claude Opus 5.5 reading 100 frames at 512x288 | **$0.08 per video**, any length | $4/M input; ⌈w/28⌉×⌈h/28⌉ tokens per image (`R10:308`) |
| Amazon Nova 2 Lite | ~$0.08 | 960 frames × 288 tokens × $0.30/M; no audio |
| Gemini 3.5 Flash-Lite | $0.11 low / $0.32 high | $0.30/M (pricing page 2026-10-22) |
| VLM Run (qwen3.8-27b) | ~$0.20 at 0.25 fps | Vendor estimator (DOCUMENTED) |
| Gemini 3.8 Flash | $0.27 low / $0.81 high; **$0.54 / $1.62 from 2027-01-01** | $0.75/M intro, then $1.50 |
| Watch Any Video | ~$0.40 at full use | $8/mo for 20 h |
| Gemini Live 3.8 (streamed) | ~$0.42 | $0.002/min video + $0.005/min audio |
| Claude Opus 5.5 reading 600 frames at 512x288 | $0.50 | Google's LVBench frame count |
| Recall.ai capture | $0.50 + $0.15 transcription | Capture only, no understanding |
| Gemini 4 Argon | $0.72 low now; **$1.44 from 2026-12-01** | $2/M promo, then $4; high resolution exceeds one call |
| SAM 3.1 hosted (Meta) | $0.72 at 1 fps; $21.60 at 30 fps | $0.20 per 1,000 frames |
| Gemini Embedding 2 | $0.76 (32 frames per 120 s) to $2.84 (1 fps) | $0.00079 per frame |
| Azure Content Understanding | ≥$1.00 (Microsoft's own example: $3.33 with GPT-5.2) | MEASURED meter |
| Gemini 3.1 Pro | $1.44 low | — |
| Claude Opus 5.5, 720p every 10 s / 1 fps contact sheets | $1.72 / $2.66 | Cache re-reads cost 5%; cache writes $5-8/M |
| TwelveLabs Pegasus 1.6 direct / 1.5 on Bedrock | $1.75 / $1.76 + $7.50/M output | Overage only on the $99 Pro plan |
| Mixpeek multimodal understanding / video index | $1.75 / $3.00 | "As of August 2026", re-read 2026-10-24 (R10 had "unknown"; R9 and the verifier read the rates) |
| Mixedbread ingest | $2.16 / $4.32 + $0.72 per h-month storage | — |
| Cloudglue | $2.40-3.60 | Credit packs |
| Nova MME / Marengo 3.0 embed | $2.52 / $3.00 (+$0.50 audio) | Bedrock / direct |
| Memories.ai | $0.90 (fps 0.3) to $3.00 (fps 1) | Plus $0.008 per search |
| Reka Vision | $3.00 | 3 h free |
| Bedrock Data Automation | $3.00 standard / $5.04 custom | MEASURED feed |
| Azure Video Indexer | $3.46 / $6.84 / $11.40 | Basic / standard / advanced |
| Rekognition, OCI Vision | $6.00 per feature | Per-minute meters |
| **Not computable** | VideoDB (unpublished), Marengo 3.5, Nova 2 Omni/Pro, Muse, Perceptron, Glimpse | Tokens per second or price unpublished |

Reading (INFERRED): one-pass understanding is cheapest through Gemini Flash-Lite or Claude's own thumbnail route, both within about 2x of each other and 15-30x cheaper than the $1.75-3.60 dedicated services (`R10:406`). Two prices move soon: Argon doubles on 2026-12-01 and Gemini 3.6-3.8 Flash on 2027-01-01 (`R6:51-54`).

## 4. Independent evidence vs vendor claims

**The real signal is a handful of 2026 owner-run or independent evaluations.** Legacy boards stopped adding models in 2024-25, and aggregators mark 0 of their 2026 video rows as verified (`R10:15`).

| Evaluation (date) | Who ran it | What it says for a Claude agent | Independence |
|---|---|---|---|
| **VideoGAIA** (2026-08-12; 271 tasks) | Academic authors | Same path as ours (20 frames plus a tool for 20 more plus web). Seed2.0-Pro 58.3, GPT-5.5 53.1, Gemini-3.1-Pro 50.9, Claude Opus 4.6 48.0, **Opus 4.8 36.9 and 4.7 34.7, last of 20**; ±6 points (`R10:249`) | Independent |
| **Video-MME-v2** (2026-04) | Benchmark owners | Best Gemini-3-Pro 49.4 vs human 90.7; best open Qwen3.5-397B 39.1; frame count moves scores 4.6-8.5 points; no Claude row (`R10:74`) | Owner-run |
| **BVB** (paper 2026-09-14, board updated 2026-10-19) | Third-party lab | Bash plus a frames tool, rebuild the video in Blender. **Opus 5.5 xhigh 72.4 (6th, $1.95 and 13.8 min per video)**; GPT-6 Astra 76.3; Gemini 4 Argon 72.7 at $0.31 (`R5:23`) | Third-party, single lab |
| **Google's Argon table**, LVBench (2026-10) | Google | Argon 91.7 at 1 fps; GPT-6 Astra 87.5 on 800 frames; **Opus 5.5 83.7 on 600 frames**; Fable 5.1 79.7 on 300. The methodology note says "self computed without tools"; "maximum thinking" was not stated for these runs. Human 94.4 comes from the LVBench paper (verifier; primary model card and methodology PDF both read) | Competitor-run |
| **GUIDE** (CVPR 2026) | Google Research | 32 frames, no audio, screen recordings: Claude-4.5-Sonnet best on behavior state 44.6, intent 71.4 and help content 55.0; weak on help need 39.5 vs Gemini-2.5-Pro 69.8; context adds up to about 50 points (`R8:268`) | Independent academic |
| **Video-HolmesV2** (2026-09) | Owners | Gemini-2.5-Pro 73.2 multiple choice vs 35.2 on evidence: require timestamped evidence for every answer | Owner-run |
| **Video-Oasis** (ECCV 2026) | Academic | 55% of benchmark items are solvable without video | Independent audit |
| **REPAIR** (2026-07-01) | Academic | Run-to-run spread 8.05 points exceeds 6 of 7 reported agentic gains; treat gains under about 8 points as noise | Independent audit |
| **Mixpeek embedding benchmark** (2026-03, updated 2026-07) | Mixpeek | 20 videos, 60 queries: API embedders 0.757-0.769 NDCG@10 vs frame-averaged CLIP 0.30-0.47 | Interested third party, small n |
| **Our probe** (2026-10-23) | Us | 23-24/24 full pipeline vs 11/24 transcript-only, one 47-min interview, windowed questions, no human baseline (`HP:15-20`) | MEASURED |

**Opus 5.5 on video, synthesised.** It has two external numbers, not one: Google's competitor-run LVBench 83.7 and BVB's third-party 72.4. This corrects `R10:22`, which missed R5's BVB row. Google's earlier Gemini 3.8 Flash launch also gave Claude Opus 5 75.4 on LVBench (secondary). With enough frames Opus is within about 8 points of Argon on hour-long QA, while older Opus versions ranked last on VideoGAIA's explore-with-tools protocol. One reading is that Claude reads frames well but chooses where to look poorly, which argues for deterministic indexing feeding it (INFERRED, `R10:402`, from Opus 4.7/4.8, not 5.5).

**No independent number at all** (DOCUMENTED absence, `R10:344-360`): TwelveLabs Pegasus 1.5/1.6 and Jockey; Cloudglue/Tinycloud; Memories.ai; VideoDB's Q&A; Reka; Mixpeek's pipeline; VLM Run; Perceptron; Elorian Glimpse; Bedrock Data Automation; Azure Video Indexer and Content Understanding; Gemini agentic mode; Gemini 3.7/3.8 Flash on video; every Claude video skill; every startup's motion or spatial claim.

**Self-reported only, read as upper bounds:** Seed 2.1 TOMATO 79.5; Glimpse TOMATO 93.6; Robotics-ER 2 moment finding 91.3%; Molmo2 tracking; Keye temporal grounding; MiniCPM-V and Qwen3.6 card scores (third-party runs 7-12 points lower); WeMM; Marengo 3.5's composite; Gemini agentic "up to 88% fewer tokens" (the only outside figure is partner Ponder's 3.5x).

**Community failure modes** match our measured traps: wrong timestamps from Gemini on long media, Whisper inventing speech over silence, ffmpeg 9 breaking frame extraction, scene detection "flaky". Practitioners settle on our design: deterministic ASR owns timing, a model owns semantics (`R10:269-293`).

## 5. Where our pipeline stands, and what to adopt

**Position (INFERRED).** `skills/video-understanding` is route C, the only route in which Claude sees pixels. Its index-then-zoom design matches what DVD, CFD, claude-eyes, crv and watch-skill arrived at independently (`R5:17`, `HP:129`). It is the only agent tool found that measures motion numerically (slit-scan, optical flow, easing fits); nothing in R1-R10 ships optical flow as an agent tool (`R5:46`). Commit `11f8feeb2` (2026-10-23) already applied HP §5 rows 1, 2, 3 and 6 (luma-difference cuts, N/2 label fix, ASR guardrails, ≥1080p for text) and parts of rows 4 and 7 (`SK:55-87`, `SK:153-163`). It lags the landscape in five places: on-screen text is a tool, not a pipeline step; speaker attribution and audio events are not standard steps; there is no structured track output; the local VLM it names is the superseded Qwen3-VL (`SK:144`); and there is no packaged MCP or egress-consent switch like watch-skill's.

**The five highest-value adoptions**, ranked by measured gap closed per unit of effort:

| # | Adopt | Measured gap it targets | Products used | Privacy and egress |
|---|---|---|---|---|
| 1 | **Make an on-screen text index a standard step**: Apple Vision OCR with positions at every cut and at 1 fps on screen content, grepped next to the transcript (claude-eyes' "words shown" track) | OCR raised screen questions from 0.17-0.25 to 0.83 in the meeting test; today answers come only from question-driven reads (`HP:145`, row 8); a 720p read keeps 0.76 of tiled-1080p OCR tokens (`HP:143`) | Apple Vision (`R7:175`); PaddleOCR off-Mac | Local |
| 2 | **Add a speaker-attribution step**: FluidAudio diarization with a per-file threshold check, a second pass with Nemotron 3 (NeMo-Speech.cpp) when turn counts disagree, and lip-motion crops at 8-24 fps as the tie-breaker | No speaker labels in ASR; the default threshold put 2,616 of 2,646 s on one speaker; 0.55 was chosen after the fact; the narrator merged into the host (`HP:33`, row 7) | FluidAudio, NeMo-Speech.cpp (`R7:125`, `R7:153`) | Local. pyannote Precision-3 (€0.112/h) is cheap but uploads audio |
| 3 | **Add an audio-event layer**: SoundAnalysis run as a standard probe, plus PE-A-Frame for free-text spans ("laughter", "applause", "music starts") | Laughter could not be grounded and was dropped; the ducked song scored 0/14 after the duck; 3 of 5 wrong details came from audio inference (`HP:36-37`, row 9) | Apple SoundAnalysis (MEASURED here), PE-A-Frame (`R7:287`, untested on MPS) | Local. Gemini or Qwen3-Omni hear audio natively, but Gemini means egress |
| 4 | **Give motion and space a structured tool**: Molmo2-8B on mlx-vlm for points, tracks and counts in a window, verified on 2000 px frames; swap the skill's local VLM from Qwen3-VL to Qwen3.6 (vision) or Qwen3-Omni (vision plus audio) after a 60 s RAM test; OmniShotCut for dissolves; Depth Anything 3 camera trajectory where a CUDA box exists; validate `motion-probe.py` on real camera footage | Qwen3-VL called real motion "not moving" 2 of 2 times and gave an empty generation at 9,732 tokens (`HP:51`, `SK:144`); motion probes validated on one synthetic film only (row 10); dissolves missed by every cut list (`R7:50-53`); benchmark gaps of 24-58 points on 3-D and 37-57 on fine motion (`HP:31`, `HP:35`) | Molmo2, Qwen3.6, Qwen3-Omni, OmniShotCut, DA3 (`R3:107`, `R7:228`, `C1:166`) | Local on the Mac for Molmo2 and Qwen; the CUDA tools mean a cloud GPU unless a box is owned, which is egress |
| 5 | **Harden public-video escalation with a where-to-look router**: Gemini 3.8 Flash agentic (paid key or Vertex, never the free tier) returns candidate timestamps; Claude confirms each on frames (DVD's CONFIRM rule); our ASR owns timing; CFD's Visual-Need Router decides when frames are needed at all | Opus has no audio-visual input (row 11); hour-scale and unprompted watching untested, since every probe question gave its window (`HP:38`); older Opus ranks last when it must choose where to look (VideoGAIA) | Gemini 3.8 Flash / 4 Argon, Vertex MCP (`R2:65`, `R6:74`); DVD and CFD designs (`R5:81`, `R5:147`) | **Public video only.** Pin `WATCH_ENGINE=local` in claude-video so private files never reach Google by accident (`R4:76`) |

Also still open and trivial: HP row 5 (read a shot-census montage and stack two native frames per Read), which is not yet in the skill. **Before claiming parity**, run the missing human baseline, add non-interview genres, and score the pipeline on BVB or VideoGAIA's protocol with REPAIR-style repeated runs (`HP:167`, `R5:114-136`).

**What not to adopt** (each a documented trap or a dead end):
- A video-agent framework as software. DVD, VideoRAG, VTS and the rest are recipes Claude Code can run with local scripts and Read; installing them adds OpenAI, Azure or DashScope egress and CUDA dependencies (`R5:47-54`).
- Event search over keyframe CLIP vectors averaged per clip; it scores less than half the API embedders (`R9:38`).
- Google Video Intelligence API (shutting down 2027-09-14), Overshoot (pivoted), and Cosmos-Reason2 (superseded) for anything new.
- The Gemini free tier, or "key-free" Gemini bridge MCPs, for anything private. The first trains on content; the second breaks Gemini CLI's terms (`R4:35`, `R4:84`).
- mlx-vlm with a model that has no video processor. It silently feeds 16 stills, and the model then answers as if it saw the video (`R3:17`).
- Vidi1.5-9B for boxes. The open weights return time ranges only.
- Any hosted index for private recordings without first reading its data terms; four of the startups above either train on content or forward it (privacy summary below).

**Privacy summary for private recordings (DOCUMENTED terms):** TwelveLabs uses data and outputs to improve its services; VideoDB uses transcription audio to improve its algorithms; Reka's free tier may train; Memories.ai's terms are unreadable; Mixpeek trains no foundation models but forwards content to Google; the Gemini free tier trains while the paid tier does not; Meta's Contributor mode trains; Z.ai routes to a China-HQ vendor; screenpipe stays local but sends analytics by default (`R1:188-193`, `R4:35`, verifier). The corporate "nothing may be uploaded" meeting case leaves only route C or a self-hosted index (`V1:14`).

## 6. Verification log and limits

**Sample.** An adversarial pass re-checked 37 entries, about 20% of the roughly 185 merged entries, against primary sources on 2026-10-24 (vendor docs, pricing pages and APIs, `gh api`, HF and PyPI JSON, papers). **Result: 37 of 37 corrected, 0 refuted.** Every product exists and is active. Every entry had at least one wrong, stale, overstated or unverifiable field. **12 of 37 (32%) carried an error that would change a builder's decision** (classification INFERRED). All corrections are applied in §2-§5.

| Entry | Decision-changing correction |
|---|---|
| TwelveLabs | The benchmark claim was misquoted ("+13.1% on Multimodal Prompting", not "+17% on Video-MME"); overage only on Pro; Marengo 3.5 does no search |
| VLM Run | The gateway does sample frames, at 640x480 at most; per-hour cost is estimable (about $0.20) |
| Mixpeek | The third-party model is Gemini, so content goes to Google; the read-only key claim is unsupported; `mixpeek-mcp-retriever` returns 404 on PyPI |
| Claude frame-route skills | claude-video defaults to Gemini whenever a key resolves; $0.08 is per video, not per hour |
| Gemini 4 Argon | Agentic video is listed in the AI Studio doc (R2 read a stale text copy) |
| Argon evaluation table | Argon is GA on the paid tier, not limited to Fairwind; the primary sources were reachable; "maximum thinking" was overstated |
| LanceDB + Geneva | Geneva is proprietary, Enterprise-only and pre-alpha; its example uploads video to TwelveLabs |
| Gemini on Vertex | A first-party Google MCP exists; plain 3.5 Flash lacks agentic mode |
| Deep Video Discovery | A benchmark figure was mislabelled; repo defaults differ from the paper; the default mode removes the frame tool |
| VideoRAG / Vimo | Frames go to Alibaba DashScope; ImageBind makes it non-commercial |
| Cosmos-Reason2 | Superseded by Cosmos 3 and no longer developed |
| ByteDance Vidi | The open weights do temporal retrieval only, with no boxes |

The other 25 had smaller fixes, in five recurring classes:
- **Egress understated:** VSS remote mode, Pixeltable's README example, screenpipe telemetry, OCI's Gemini calling Vertex.
- **Pricing context wrong or missing:** Nova global vs in-region rates, screenpipe tiers, Granola on all tiers, crv's $9.90 Codex build, Azure's new meter.
- **Capability understated:** Robotics-ER 2 has vendor benchmarks, Chrome DevTools MCP has a screencast, VideoDB has object detection, Otter has an MCP, Muse takes `fps`.
- **Capability or status overstated:** Qwen3-Omni Captioner is audio-only, ADK Live cannot host Claude, the MiniCPM figure came from a non-default setting, VideoExplorer's venue is unverified.
- **Drift:** star and install counts, dates, maturity flags.

**Cross-axis conflicts this synthesis resolved:**
- `R10:22` says Opus 5.5 has one video number; R5:23's BVB row is a second.
- R10:313 says Argon may not be callable; it is GA.
- R2:24-27 says Argon is missing from the AI Studio agentic list; it is listed.
- R10:320 says Mixpeek's per-minute price is unknown; R9 and the verifier read $0.05/min.

**Caveat for the roughly 148 unverified entries.** If the sample is representative, expect at least one wrong field in nearly every unverified entry, and a decision-changing error in about one in three. The most likely errors are understated egress and pricing quoted without plan or region context. **Re-check any entry against its primary source before acting on it** (INFERRED from the 37/37 and 12/37 rates; the sample was spread across axes, not random).

**Limits.**
- No product in this landscape was run on a video by us. Every quality number is someone else's, and our only measurements are the 2026-10-23 probe and earlier local tests.
- Prices are list prices read once. Three promotions end within ten weeks, and several meters (Marengo 3.5, Nova 2, Muse) cannot be turned into per-hour figures.
- OpenRouter's modality tags are third-party metadata; 90 of 469 models accept video, and accepting video says nothing about understanding it (`C1:222-224`).
- Thin axes remain: Chinese closed APIs beyond Qwen and Seed (Baidu ERNIE 5.0), video-platform vendors (Cloudinary, api.video, Bitmovin), media incumbents (Moments Lab, Sieve), and streaming benchmarks (OVO-Bench, StreamingBench) (`C1:205-224`).
- Many open-model and research entries are older than 6 months: Qwen3-Omni, InternVL3.5, the legacy video LLMs, DVD, VideoRAG, M3-Agent, Vidi2.5, PE-A-Frame. They are flagged where listed.

## 8. Follow-up: NVIDIA VSS GTC 2026 talk (2026-10-24)

The operator asked whether NVIDIA's GTC 2026 session "Visual AI Agents for Real-Time Video Understanding" (`youtube.com/watch?v=3yPQHcEZDaI`, the VSS blueprint plus Cosmos Reason) is applicable. Verdict: **partly**, and only as a source of ideas (`agents/V3-applicability-verdict.md`, reviewed in `agents/V4-skeptic.md`).

- **Not usable on our Macs.** Every VSS deployment needs a local NVIDIA GPU. It has no speech-to-text, screen OCR or speaker separation, and its evaluation licence bars production use (DOCUMENTED, `V2`, `V4`).
- **Cosmos Reason does not help.** NVIDIA's own tables put it below its Qwen3-VL-8B base on OCR and hallucination. Community MLX/GGUF builds exist, but there is no reason to prefer it over the base model (DOCUMENTED, `V3`, `V4`).
- **Meeting recordings: nothing new.** Every VSS retrieval pattern already has a built equivalent in the agentsync design (`V3` U2).
- **Where it ranks:** first choice for self-hosted, agent-driven analytics over camera fleets on NVIDIA GPUs (CCTV, warehouse, factory) where video must stay on premises. NVIDIA publishes latency and throughput only, no accuracy numbers.
- **What the talk added beyond the docs:** NVIDIA's coding-agent demo is Claude Code with Opus 4.6; the live demo ran Qwen 3.5, not NVIDIA models (MEASURED from the talk, `V1`). Running our skill on it found a stale-yt-dlp 403 symptom, now in `skills/video-understanding/SKILL.md`.
- **Dropped after review:** VSS's per-claim critic (about 45-50% conviction once the skeptic showed its mechanism fixes none of our 5 measured detail errors), and a test of NVIDIA's hosted Nemotron Omni for audio events (40%).
