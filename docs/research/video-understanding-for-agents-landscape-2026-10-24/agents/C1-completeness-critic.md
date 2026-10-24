# C1: Completeness critic for the video-understanding-for-agents landscape (2026-10-24)

Role: find important offerings that R1-R10 missed, and name the axes that are thin. Method: web search plus primary
sources (vendor docs fetched as Markdown with curl, the OpenRouter `/api/v1/models` catalogue, the Hugging Face
model API, `gh api` repo metadata, npm and PyPI registry JSON). I checked candidate names against R1-R10, F1-F3 and the
2026-10-23 corpus with grep, and kept only items that have no entry there. Several were named in passing, for example
in R2's §3 long-tail paragraph, but never got a full entry. Nothing was installed, uploaded or signed up for.

Labels: **MEASURED** = fact retrieved today with curl, the HF/GitHub/npm API or a grep of a fetched doc (never our
own inference run). **DOCUMENTED** = stated in a primary doc or card I read. **INFERRED** = my judgement.

## Comparison table (ranked by importance to an agent builder)

| # | Name | Category | Path into the model | Deploy / licence | Price (date) | Claude Code fit | Newest evidence | Label |
|---|---|---|---|---|---|---|---|---|
| 1 | Elorian Glimpse | agent-native startup / frontier API | Native video (mp4 file part, `video_fps` option); the model re-watches short intervals at denser sampling; no audio | Cloud, proprietary (post-trained on an open base) | $0.60 / $3.00 per M tokens (OpenRouter, 2026-10-24) | OpenRouter, Vercel AI Gateway or Together API via a skill script; egress | Launched 2026-10-15/17 | MEASURED (catalogue) / vendor claims |
| 2 | Z.ai Vision MCP Server (`@z_ai/mcp-server`) | agent integration | Local MCP that uploads the clip (≤8 MB, MP4/MOV/M4V) to GLM-5.3-Flash | npx local stdio, Z.ai cloud model | GLM Coding Plan from $18/month (docs 2026-10-24) | `claude mcp add` one-liner documented for Claude Code | v0.1.5, 2026-08-27; 47,418 downloads in the 30 days to 2026-10-22 | MEASURED |
| 3 | LiveKit Agents / Pipecat / Google ADK Live | agent framework (realtime) | WebRTC camera or screen frames: about 1 fps at 1024 px (LiveKit) or 768 px (ADK) into Gemini Live or OpenAI Realtime, or frames as image blocks into any LLM including Claude | OSS (Apache-2.0 / BSD-2 / Apache-2.0); self-host or vendor cloud | Framework free; model tokens extra | Claude works only in the pipeline mode (STT, Claude with image frames, TTS) | All pushed 2026-10-24; 14,912 / 16,763 / 21,984 stars | MEASURED |
| 4 | Meta Muse Spark Open (816B-A42B) | open-weight VLM | Text, image, video and audio in; text out | Weights gated, Muse Model License; at least 700 GB for NVFP4 | OpenRouter $1.25 / $4.25 per M (2026-10-24) | API only in practice; server-class | HF modified 2026-10-15 | MEASURED (HF, OpenRouter) + secondary |
| 5 | Xiaomi MiMo-V2.6 Pro / Flash | open-weight VLM (omni) | Native text, image, video and audio (681M ViT, 308M audio tokenizer) | MIT weights (Pro-RL 1.02T-A42B, Flash-RL 309B-A15B); Xiaomi API | Pro $0.435 / $0.87, Flash $0.14 / $0.28 per M (OpenRouter, 2026-10-24) | API via skill; weights server-class | HF 2026-10-09 | MEASURED |
| 6 | H2-2026 open MoE models with video input: Kimi K3.1 Pro, Step-5 Preview, MiniMax-M3.1-Flash, Ling-3.0-flash-VL | open-weight VLM | Native video input (`video_url`); Ling uses VideoRoPE for event localisation | Mixed: StepFun Model License 1.0, minimax-community, MIT (Ling); K3.1 weights unverified | $2/$10, $1/$2.7, $0.15/$0.6, $0.06/$0.18 per M (OpenRouter, 2026-10-24) | API via skill | 2026-09-04 to 2026-10-23 | MEASURED (catalogue, cards) |
| 7 | Ming-flash-omni 2.0 (Ant inclusionAI) and LongCat-Flash-Omni (Meituan) | open-weight VLM (omni, streaming) | Native video and audio in, speech out; streaming video conversation | MIT; 100B-A6B and 560B-A27B | Self-host; unknown | Local server behind an MCP; Ming is the more feasible on a large Mac (INFERRED) | Ming HF 2026-09-29; LongCat HF 2025-11-11 (STALE) | MEASURED (HF) |
| 8 | Snowflake Cortex AI and BigQuery `AI.GENERATE` | hyperscaler / data warehouse | SQL over staged video: `AI_COMPLETE` with Gemini 3.5 Flash (preview), `AI_MULTI_EMBED` with Marengo 3.0 (GA, ≤6 GB); BigQuery passes ObjectRef video to Gemini (first 2 minutes only) | Cloud; data stays inside the warehouse account | Unknown (warehouse credits) | Snowflake or BigQuery CLI or MCP from Claude; results come back as SQL rows | Snowflake notes 2026-05-28 and 2026-08-10 | DOCUMENTED |
| 9 | Tavus Raven-1 / Raven-2 perception | vertical (conversational video) | Live camera, screen and audio fused into text observations; perception tools fire on visual or audio cues | Cloud, inside Tavus CVI/PAL | Unknown | Works only inside a Tavus conversation; no standalone file API | Raven-1 GA 2026-02; docs current 2026-10 | DOCUMENTED |
| 10 | Mux `@mux/ai` + `@mux/mcp` + Mux Robots | agent integration / video platform | Storyboard frames plus transcript sent to OpenAI, Anthropic (Claude) or Gemini; workflows for summaries, chapters, moderation, burned-in captions | OSS TS library (licence NOASSERTION) + Mux cloud | Mux usage plus model tokens; unknown | Official Mux MCP; `@mux/ai` can use Claude as the vision model; video must be in Mux | `@mux/ai` 0.54.0 on 2026-10-23; `@mux/mcp` 15.6.1 on 2026-10-05 | MEASURED |
| 11 | Feed-forward 3D and camera pose: Depth Anything 3, VGGT, MapAnything | primitive library | Frames → camera extrinsics/intrinsics, depth, point maps, 3D tracks; DA3-Streaming for long video | Local GPU; DA3 Small/Base Apache-2.0 (Giant/Large CC-BY-NC); VGGT-1B-Commercial custom; MapAnything code Apache, weights CC-BY-NC | Free | Local CLI (`da3 video …`) wrapped as a skill returning a pose trajectory as JSON (INFERRED) | DA3 pushed 2026-07-27; VGGT 2026-05-19; MapAnything 2026-08-07 | MEASURED |
| 12 | ByteDance Vidi2 / Vidi2.5 | open-weight VLM (spatio-temporal grounding) | Query → time ranges plus per-frame boxes (STG); temporal retrieval | Vidi1.5-9B and Vidi-7B weights CC-BY-NC-4.0; Vidi2/2.5 web demo only | Free (non-commercial) | Local 9B behind a tool; non-commercial | Vidi2.5 2026-01-20 (older than 6 months) | MEASURED (HF, repo) |
| 13 | Pixeltable (+ developer MCP + Claude plugin) | search / embedding infra | Declarative tables: video column → frame/audio extraction → transcript, LLM and embedding computed columns, incremental | Apache-2.0, local | Free; model calls extra | `claude mcp add pixeltable … uvx mcp-server-pixeltable-developer` documented; Claude plugin | v0.7.20 2026-10-22; 1,643 stars | MEASURED |
| 14 | M3-Agent (ByteDance Seed, ICLR 2026) | agent framework | Online video and audio stream → entity-centric multimodal memory graph → RL-trained multi-turn retrieval | Apache-2.0 code and weights; GPU | Free | Pattern to borrow; not a tool | Repo pushed 2026-02-12 (STALE) | MEASURED (repo) |

## Entries

### 1. Elorian Glimpse (Elorian, Palo Alto) — the one new agent-native video model of the last month
- **What it gives an agent:** a hosted "visual thinking" model that reasons over images and video directly. Per Vercel's
  changelog (2026-10-16) it can return to visual evidence mid-reasoning: "zooming into a detail, revisiting a short
  interval of video". Together's page says it is trained end to end to use multimodal tools (code, image transforms,
  watching video) and to coordinate subagents.
- **Modality path:** native video input. Vercel's example sends an `mp4` file part with provider option `video_fps: 1`.
  No published duration, size or fps caps. No audio input listed (OpenRouter `input_modalities` = text, image, video,
  MEASURED 2026-10-24).
- **Price:** $0.60 / $3.00 per M input/output tokens, cache read $0.06 (OpenRouter API, MEASURED 2026-10-24). Context
  262,144 tokens.
- **Spatial and motion claims:** "follows objects in motion and across changing viewpoints", "connects an action to
  its physical consequences". Self-reported at maximum thinking effort (Together page): TOMATO 93.60, Video-MME-v2 with
  subtitles 56.68, E.T. Bench 63.55, ERQA 83.75, DREAM-1K 76.04. For context, R2's best self-reported TOMATO was Seed
  2.1 at 79.5, and R10's owner-run Video-MME-v2 best was Gemini-3-Pro at 49.4. The settings differ, so the comparison
  is not like for like. Vendor claims only.
- **Company:** a reported $55M from Striker, Menlo and Altimeter, with NVIDIA and Jeff Dean among backers. CEO Andrew
  Dai is ex-Google Brain/DeepMind (secondary press: vktr, 36kr). An April 2026 article called its capabilities "on
  paper only".
- **Claude fit:** a skill that posts the clip to OpenRouter, Vercel or Together and returns text. Full egress; data
  terms were not checked.
- **Why it matters:** it is the first startup model (not a wrapper) whose pitch is the motion and physical-consequence
  gap our probe measured, and it is priced below Gemini 3.8 Flash on output. It should be on the shortlist for a paired
  test against Gemini on our motion items.

### 2. Z.ai Vision MCP Server (`@z_ai/mcp-server`) — the most-downloaded video MCP built for Claude Code that the survey missed
- Zhipu's official local MCP for GLM Coding Plan users. Tools include `video_analysis` ("Inspect videos (local/remote
  ≤8 MB; MP4/MOV/M4V) to describe scenes, moments, and entities"), plus `extract_text_from_screenshot`, `ui_diff_check`,
  `diagnose_error_screenshot` and others. The docs give a `claude mcp add -s user zai-mcp-server … npx -y
  "@z_ai/mcp-server"` line and note that Claude Code is the one client where pasted images still route to the MCP.
  The model behind it is GLM-5.3-Flash (≥0.1.2).
- npm: latest 0.1.5 (2026-08-27), first published 2025-09-07, **47,418 downloads in the 30 days to 2026-10-22**
  (MEASURED, npm downloads API). That is far more than the watch skills R4 counted (220-1,700 installs).
- Price: the coding plan starts at $18/month, with Lite, Pro and Max quotas (docs.z.ai, fetched 2026-10-24).
- Caveats: the 8 MB cap means short clips only; the clip is uploaded to Z.ai (China-HQ vendor); no published video eval
  for GLM-5.3-Flash (R3 found no video claims on its card). MiniMax's equivalent coding-plan MCP has `understand_image`
  only, with no video (PyPI 0.0.5, MEASURED).

### 3. Realtime WebRTC agent frameworks: LiveKit Agents, Pipecat, Google ADK Live toolkit
R1 covered only Stream Vision-Agents (8,186 stars). The three larger frameworks were absent:
- **LiveKit Agents** (14,912 stars, `livekit-agents@1.8.9` released 2026-10-24, Apache-2.0, MEASURED). Live video input
  works only with Gemini Live or OpenAI Realtime. By default it samples **1 frame/s while the user speaks and 1 every
  3 s otherwise, resized to 1024×1024 JPEG**. A trap: "Enabling `video_input` with an audio-only realtime model
  silently ignores the video frames — no error is raised". The pipeline mode injects the latest frame as
  `ImageContent` per turn, which works with any vision LLM, including Claude. The docs themselves warn that frame-fed
  LLMs do worse on motion (DOCUMENTED).
- **Pipecat** (Daily; 16,763 stars, v1.14.0 released 2026-10-24, BSD-2, MEASURED). A frame-pipeline framework with
  Gemini Live vision and screenshare, a Moondream vision service and a Tavus transport.
- **Google ADK** (adk-python, 21,984 stars, MEASURED). The Live toolkit sends video as individual JPEG blobs through
  `send_realtime`, recommended at **~1 fps max and 768×768**. The docs say plainly that "At ~1 FPS the model can see
  what the user is pointing a camera at … but not anything motion-dependent" (DOCUMENTED).
- **Fit:** these are for live calls, screen-share copilots and camera agents, not for files. Claude can only be the
  brain in the cascaded pipeline, seeing about 1 still per turn.

### 4. Meta Muse Spark Open (816B MoE, 42B active)
- HF `meta-models/Muse-Spark-Open-816B-A42B`: created 2026-09-15, modified 2026-10-15, gated (manual), `license:other`,
  5,196 downloads and 679 likes (MEASURED, HF API). OpenRouter `meta/muse-spark-open`: created 2026-10-15, inputs text,
  image, video, file and **audio**, 1,048,576 context, $1.25 / $4.25 per M (MEASURED).
- From secondary coverage, since the card is gated: weights under the Muse Model License (permits fine-tuning and
  redistribution with conditions; one report cites a $20M commercial threshold); NVFP4 needs at least 700 GB of
  accelerator memory, BF16 2 TB; Meta claims it runs on two M5 Ultra Mac Studios with MLX. Meta demoed frame-by-frame
  review of footage in DaVinci Resolve. Benchmarks are Meta's own.
- **Gap note:** R2 deferred this model to R3 ("belongs to the open-weight axis"), but R3 covers only Muse Glimmer-30B,
  which processes video as frames and has no audio. So the largest US open-weight model with video plus audio has no
  entry in the survey.

### 5. Xiaomi MiMo-V2.6 Pro / Flash
- Released 2026-09-21. HF `XiaomiMiMo/MiMo-V2.6-Pro-RL` and `-Flash-RL`, **MIT**, about 96K and 92K downloads
  (MEASURED). The card lists Modalities: Text, Image, Video, Audio; a 681M MiMo ViT; a 308M AudioTokenizer plus a 127M
  audio patch encoder; 1M context; Pro is 1.02T-A42B. OpenRouter lists Flash at 309B-A15B (MEASURED).
- OpenRouter: Pro $0.435 / $0.87, Flash $0.14 / $0.28 per M, both with audio input (MEASURED 2026-10-24). These are
  among the cheapest omni APIs listed.
- The card publishes **no video benchmark** (grep: only "MiMo VisualCoding" under Visual Agent). R3 covered only V2.5
  and the V2.6 9B distill, and R2 listed V2.6 in its unchecked long tail.

### 6. The H2-2026 wave of open MoE models with video input
All MEASURED from the OpenRouter catalogue and HF cards on 2026-10-24. None has a published video benchmark on its
card.
- **Moonshot Kimi K3.1 Pro**: OpenRouter created 2026-10-23, text, image and video in, 1M context, $2 / $10 per M. The
  description says "flagship open-weight". No `moonshotai/Kimi-K3.1-Pro` HF repo was found (HF API error), so weights
  are unverified. Secondary sources on 2026-10-21 still called K3.1 a rumour.
- **StepFun Step-5 Preview**: 600B-A27B, 1M context, "accepts text, images, and video"; StepFun Model License 1.0; HF
  2026-09-20 / 2026-10-15; $1 / $2.70.
- **MiniMax-M3.1-Flash**: about 428B-A23B, text, image and video in, 1M context, `minimax-community` licence, HF
  2026-10-17; $0.15 / $0.60.
- **inclusionAI Ling-3.0-flash-VL**: 124B-A5.5B, MIT, 256K context. It uses VideoRoPE "supporting tasks such as event
  localization, long-video question answering, and video clip editing" and takes OpenAI-style `video_url`. HF
  2026-09-04; $0.06 / $0.18. At 5.5B active it is the most laptop-plausible of the set (INFERRED; not tested).
- Also confirmed to exist but outside this wave: DeepSeek-V4-Flash-Vision-Exp (2026-08, MIT) is **image-only**; GLM-5V-Turbo
  (2026-04-01, video in, $1.20 / $4) appears in R10's VideoGAIA row but has no entry.

### 7. Open omni models with streaming video plus audio: Ming-flash-omni 2.0 and LongCat-Flash-Omni
- **Ming-flash-omni 2.0** (Ant Group inclusionAI): Ling-2.0 MoE, 100B total and 6B active, MIT. Inputs are image, text,
  video and audio; outputs are image, text and audio. The card demos "Streaming Video Conversation". HF created
  2026-02-10, modified 2026-09-29, 6,048 downloads (MEASURED). The vendor claims it beats Gemini 2.5 Pro on some
  benchmarks (secondary).
- **LongCat-Flash-Omni** (Meituan): 560B-A27B, MIT, any-to-any, 128K context, real-time audio-visual interaction. HF
  last modified 2025-11-11 and repo pushed 2026-05-09, so it is **stale by more than 6 months** on weights (MEASURED).
- These widen R3's short list of open models that hear the audio track, which held only Qwen3-Omni, Nemotron Omni,
  MiniCPM-o, Gemma 4 and MiMo. No independent video eval exists for either.

### 8. Data-warehouse SQL video functions: Snowflake Cortex AI and BigQuery `AI.GENERATE`
- **Snowflake:** 2026-05-28, "AI_COMPLETE now supports Gemini 3.5 Flash for multimodal video and audio analysis …
  without moving data outside of Snowflake". 2026-08-10, `AI_MULTI_EMBED` is GA "for semantic video search with support
  for large video files up to 6 GB using the TwelveLabs Marengo Embed 3.0 model". `AI_TRANSCRIBE` handles the audio of
  a video. The multimodal doc says "Audio and video processing using AI_COMPLETE is in public preview" (DOCUMENTED, .md
  docs fetched 2026-10-24).
- **BigQuery:** `AI.GENERATE` accepts ObjectRef video to Gemini, but "the maximum supported length is two minutes. If
  the video is longer than two minutes, AI.GENERATE only returns results based on the first two minutes", and the
  input can hold "at most one video object" (DOCUMENTED, reference page). That is a silent-truncation trap.
- **Why it matters:** for an enterprise whose video already sits in a warehouse, this is the governed route with no new
  vendor. R6 covered Vertex, Azure, AWS and OCI but not the warehouse layer. Pricing is in warehouse credits (unknown).

### 9. Tavus Raven-1 / Raven-2 (conversational perception)
- Raven-1 went GA in 2026-02 (press release). It fuses camera and audio (tone, expression, gaze) into natural-language
  observations for the conversational LLM. Docs (fetched 2026-10-24): `visual_awareness_queries`,
  `audio_awareness_queries`, perception tools with `origin: "vision" | "audio"` that fire on cues, and
  `perception_analysis_queries` for a post-call report. Screen awareness and proactive callouts need **Raven-2**.
- No standalone file API: the perception layer exists only inside a Tavus PAL conversation. Latency claims (sub-100 ms
  audio perception, under 600 ms pipeline) come from the vendor press release. Pricing unknown.
- It belongs on the realtime axis as the only product that turns live video into *event-triggered tool calls*. That
  design is worth copying in a local frame-server MCP (INFERRED).

### 10. Mux: `@mux/ai`, `@mux/mcp` and Mux Robots
- `@mux/ai` (npm 0.54.0, 2026-10-23; repo `muxinc/ai`, 70 stars, pushed 2026-10-23, MEASURED) is a TypeScript workflow
  library. It sends frames and transcripts of Mux-hosted assets to OpenAI, **Anthropic**, Google, Baseten or any
  OpenAI-compatible endpoint. Workflows include `getSummaryAndTags`, chapters, moderation, `hasBurnedInCaptions`,
  embeddings, translation and dubbing. The README states the defaults are `gpt-5.6-luna`, `claude-sonnet-4-5` and
  `gemini-3-flash-preview`, and that evals for quality, latency and cost are published on each push to main.
  Mux Robots is the hosted version. `@mux/mcp` is the official Mux API MCP (15.6.1, 2026-10-05, MEASURED).
- It is one of the few packaged pipelines that uses **Claude as the vision model over frames** with published evals.
  The cost: the video must live in Mux. Video-platform vendors as a class (Mux, Cloudinary, api.video, Bitmovin's Stream
  Lab MCP) were absent from the survey.

### 11. Feed-forward 3D and camera pose from video: Depth Anything 3, VGGT, MapAnything
- **Depth Anything 3** (ByteDance Seed): 6,563 stars, pushed 2026-07-27. It does camera pose estimation (extrinsics
  and intrinsics) and depth from any number of views, and has a `da3 video` CLI. **DA3-Streaming** (2025-12) handles
  "ultra-long video sequence inference with less than 12GB GPU memory". DA3-Small and Base are Apache-2.0;
  Large and Giant are CC-BY-NC-4.0 (MEASURED, README and HF).
- **VGGT** (Meta, CVPR 2025 best paper): 14,554 stars, pushed 2026-05-19. It infers cameras, depth, point maps and 3D
  point tracks. Only VGGT-1B-Commercial is under a commercial-use licence (gated).
- **MapAnything** (Meta): code Apache-2.0, weights CC-BY-NC-4.0, pushed 2026-08-07.
- **Why it matters:** none of R1-R10 lists a geometry primitive. A per-frame camera trajectory gives
  pan/tilt/zoom/dolly labels and the camera's spatial layout deterministically. That is the motion signal crv Pro sells
  as closed labels, and that optical flow gives only in 2D (INFERRED). They are CUDA-first; MPS is untested.

### 12. ByteDance Vidi2 / Vidi2.5 (spatio-temporal grounding)
- arXiv 2511.19529: Vidi2 (2025-11-25) and Vidi2.5 (2026-01-20). Given a text query it returns time ranges plus
  bounding boxes inside them. The paper claims it "substantially outperforms" Gemini 3 Pro Preview and GPT-5 on its
  own VUE-TR-V2 and VUE-STG benchmarks. It releases the VUE-STG, VUE-TR-V2 and VUE-PLOT benchmarks.
- Open weights are only the older **Vidi1.5-9B** and Vidi-7B, both **CC-BY-NC-4.0** (HF, MEASURED). Vidi2/2.5 are
  demo-only (vidi.byteintl.com). Repo: 660 stars, pushed 2026-08-03. The newest model evidence is older than 6 months.
- It complements Molmo2 (R3) as the second open grounding specialist, but its benchmark is the vendor's own.

### 13. Pixeltable
- An Apache-2.0 "multimodal database, orchestration, and serving" library: 1,643 stars, v0.7.20 on 2026-10-22
  (MEASURED). A `pxt.Video` column with computed columns (`extract_audio`, transcription, LLM summary, embedding index)
  updates incrementally on insert. The maintained `mcp-server-pixeltable-developer` (pushed 2026-10-22) documents
  `claude mcp add pixeltable … uvx mcp-server-pixeltable-developer` and ships a Claude plugin. The older
  `mcp-server-pixeltable` is archived.
- It is the closest open, local equivalent of VideoDB's "per-scene analyzer graph" design that R1 recommended
  borrowing (INFERRED). R10 mentioned Pixeltable only as the author of a vendor listicle.

### 14. M3-Agent (ByteDance Seed, ICLR 2026)
- It processes video and audio streams online into episodic and semantic memory held as an **entity-centric multimodal
  graph** (faces and voices tracked across modalities), then RL-trained (DAPO) multi-turn retrieval answers questions.
  It ships M3-Bench (robot and web video). The authors report +6.7, +7.7 and +5.3 points over a Gemini-1.5-Pro/GPT-4o
  prompting agent on M3-Bench-robot, M3-Bench-web and Video-MME-long (author-reported).
- Repo: 1,464 stars, Apache-2.0, last push 2026-02-12, so it is **STALE** (MEASURED). Weights:
  `ByteDance-Seed/M3-Agent-Control` (Apache-2.0).
- It is missing from R5's framework list. It is the strongest published design for *multi-day, person-centric* footage
  that also uses audio, which EGAgent's SQLite graph does not.

## Thin axes
1. **Realtime and live video.** Before this pass the survey had one OSS framework (Stream Vision-Agents), Gemini Live
   and a pivoted Overshoot. The large frameworks (LiveKit, Pipecat, ADK) and conversational perception (Tavus) were
   missing. All converge on about 1 fps at 768-1024 px, so live agents are blind to motion by design (DOCUMENTED in the
   LiveKit and ADK docs). Streaming VLM research (StreamingVLM, LiveCC) is stale: last push 2025-10, MEASURED. No
   streaming benchmark (OVO-Bench, StreamingBench) has an entry.
2. **3D, spatial geometry and camera motion.** No geometry primitive was surveyed (entry 11). VSI-Bench is the only
   spatial item.
3. **Chinese closed APIs other than Qwen and Seed.** Baidu ERNIE 5.0 (natively omni, video in, Qianfan API, launched
   2026-01-22; weights closed per DataLearner/AI Wiki, secondary only) and Tencent Hunyuan HY4 (announced in training
   2026-08-12, not released) have no coverage. Kimi K3.1 Pro, Step-5, MiniMax M3.1 and MiMo-V2.6 have no deep checks.
4. **Data warehouse and video-platform layers** (entries 8 and 10). Cloudinary, api.video and Bitmovin were not
   checked in depth.
5. **Media and enterprise video-AI incumbents.** Moments Lab (MXT-2, public API, $24M, Discovery Agent preview at
   IBC2025; no 2026 or MCP evidence found), Sieve (seed, about $4.1M, hiring 2026-04, no 2026 docs found), Archetype AI
   Newton (physical-AI agents 2026-06, no public API docs) and Ragie (audio and video RAG, 2025-05, older than
   6 months) were absent. None looked strong enough for a full entry.
6. **Evidence.** None of the 14 entries above has an independent video evaluation. The OpenRouter catalogue now lists
   **90 of 469 models with video input** (MEASURED 2026-10-24), and almost none publish video benchmarks on their
   cards. Accepting video says nothing about how well a model understands it.

## Sources
- OpenRouter catalogue: https://openrouter.ai/api/v1/models (MEASURED 2026-10-24)
- Elorian: https://www.together.ai/models/elorian-glimpse ; https://vercel.com/changelog/elorian-ai-glimpse-now-available-on-ai-gateway ; https://www.vktr.com/ai-platforms/year-old-elorian-launches-glimpse-to-compete-with-frontier-ai-models/
- Z.ai: https://docs.z.ai/devpack/mcp/vision-mcp-server.md ; https://docs.z.ai/devpack/overview.md ; https://www.npmjs.com/package/@z_ai/mcp-server
- LiveKit: https://docs.livekit.io/agents/multimodality/vision/video.md ; https://github.com/livekit/agents
- Pipecat: https://docs.pipecat.ai/pipecat/features/gemini-live ; https://github.com/pipecat-ai/pipecat
- ADK: https://adk.dev/live/audio-video/ ; https://github.com/google/adk-python
- Muse Spark Open: https://huggingface.co/meta-models/Muse-Spark-Open-816B-A42B ; https://itdaily.com/news/innovation/meta-muse-spark-open-weigh/ ; https://thenewstack.io/meta-muse-spark-open/
- MiMo-V2.6: https://huggingface.co/XiaomiMiMo/MiMo-V2.6-Pro-RL ; https://huggingface.co/XiaomiMiMo/MiMo-V2.6-Flash-RL
- Wave: https://huggingface.co/stepfun-ai/Step-5-Preview ; https://huggingface.co/MiniMaxAI/MiniMax-M3.1-Flash ; https://huggingface.co/inclusionAI/Ling-3.0-flash-VL ; https://openrouter.ai/moonshotai/kimi-k3.1-pro
- Omni: https://huggingface.co/inclusionAI/Ming-flash-omni-2.0 ; https://huggingface.co/meituan-longcat/LongCat-Flash-Omni
- Snowflake: https://docs.snowflake.com/en/release-notes/2026/other/2026-05-28-gemini-3-5-flash-multimodal-video-audio ; https://docs.snowflake.com/en/release-notes/2026/other/2026-08-10-ai-multi-embed-large-video-files-ga ; https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-multimodal
- BigQuery: https://cloud.google.com/bigquery/docs/reference/standard-sql/bigqueryml-syntax-ai-generate
- Tavus: https://docs.tavus.io/sections/conversational-video-interface/pal/perception ; https://www.streetinsider.com/Press+Releases/Tavus+Introduces+Raven-1%2C+Bringing+Multimodal+Perception+to+Real-Time+Conversational+AI/26004150.html
- Mux: https://github.com/muxinc/ai ; https://www.npmjs.com/package/@mux/mcp
- Geometry: https://github.com/ByteDance-Seed/Depth-Anything-3 ; https://github.com/facebookresearch/vggt ; https://github.com/facebookresearch/map-anything
- Vidi: https://github.com/bytedance/vidi ; https://arxiv.org/abs/2511.19529
- Pixeltable: https://github.com/pixeltable/pixeltable ; https://github.com/pixeltable/mcp-server-pixeltable-developer
- M3-Agent: https://github.com/ByteDance-Seed/m3-agent ; https://arxiv.org/abs/2508.09736
- Not-entries: https://github.com/landing-ai/vision-agent (deprecated) ; https://github.com/mit-han-lab/streaming-vlm ; https://github.com/showlab/livecc ; https://huggingface.co/unsloth/DeepSeek-V4-Flash-Vision-Exp
