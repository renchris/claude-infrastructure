<!-- markdownlint-configure-file {
  "MD013": false
} -->

# R1: Agent-native video-understanding startups, as of 2026-10-24

Axis: startups and products built to give LLM agents video understanding. For each one: the API shape an agent calls, what the model behind it actually sees, the price (with its date), and traction.

Labels: **MEASURED** = I ran the named command today (2026-10-24). **DOCUMENTED** = a vendor page, README or paper says so; we have not tested it. **INFERRED** = my own reasoning. Every $/video-hour figure is **ESTIMATED**, with the method given. Scratch copies of the fetched pages are in `/tmp/r1-fetch/` and will not survive a reboot; the URL is the citation of record. Nothing was installed, no account was created, and nothing was uploaded.

This file builds on `docs/research/video-understanding-human-parity-2026-10-23/agents/F3-tinycloud-and-agent-video-tools-now.md` (F3) and `~/.claude/research-artifacts/meeting-video-2026-10-06/video-api-alternatives.md` (VAA). Where those already settled a fact, I cite them and repeat nothing.

## 0. The short version

1. **Every product on this axis is a cloud service that takes the whole video file.** Claude ends up with text, JSON, timestamps and URLs. In two cases it can also get boxes or points (VLM Run with SAM 3.1 or ViTPose, and Perceptron `<track>`). No vendor streams frames into Claude as images. Thumbnail or frame URLs come back, and Claude Code then has to fetch them and Read them (DOCUMENTED, per-entry docs below; INFERRED for the Claude Code step).
2. **The "agent" layer is converging on the same three things: a hosted MCP endpoint with OAuth, a Claude Code plugin, and an index→search→read-moment tool chain.** Memories.ai, VideoDB and TwelveLabs Jockey ship all three. Mixpeek, VLM Run and Perceptron ship hosted MCP with a bearer key. Reka ships a local stdio MCP that wraps its cloud API (DOCUMENTED).
3. **Several startups resell frontier or open models under their own brand.** Memories.ai's stateless "Visual Intelligence" API routes video to Gemini (`gemini-3-flash-preview` by default), Nova or Qwen3-VL. Reka's chat API serves `qwen3.8-27b` next to its own `reka-edge-2603`. Overshoot proxies Claude, Gemini, GPT-5.4, Gemma 4, Qwen 3.6 and H-company Holo at list prices. Mixpeek's "multimodal understanding" line is "cost-plus on a third-party model" (DOCUMENTED). Only TwelveLabs (Pegasus/Marengo), Perceptron (Mk1.5), Reka (Edge) and Memories.ai (OmniRetriever/OmniCaptioner, LVMM) claim models of their own.
4. **Only two vendors document spatial or motion output beyond text.** VLM Run's gateway `read_video` returns per-frame tracks from `facebook/sam3.1` and keypoints from ViTPose. Perceptron Mk1.5 returns `<track>` markup with timestamped boxes and points, plus a guide that turns its waypoints into optical-flow tracks. Both are vendor claims with no independent evaluation. TwelveLabs Pegasus 1.6 makes the strongest *text* motion claims (egocentric action labelling, next-action prediction) (DOCUMENTED).
5. **There is no independent benchmark for any of these products.** TwelveLabs' homepage claims Pegasus 1.5 scores "+17%" over Gemini 3.1 Pro on Video-MME (>30 min). OnDeck AI claims "Perception-0" at 81.2% against Gemini 3.1 Pro's 78.5% on an unnamed benchmark. Both are vendor marketing. The independent leaderboards I found (Video-MME-v2, arXiv 2604.05015) do not list Pegasus or any startup model (DOCUMENTED, secondary).
6. **Traction is thin outside TwelveLabs.**
   - TwelveLabs closed a $100M Series B on 2026-07-01 (NEA and NAVER Ventures, with Amazon).
   - Memories.ai has $16M in seed money, and Perceptron $21M.
   - VideoDB has about $1.3M pre-seed and Mixpeek about $650K pre-seed (both directory figures, stale).
   - Cloudglue is a 3-person YC S24 company and joined the Vercel AI Accelerator on 2026-03-20.
   - GitHub signals are tiny except for VideoDB's open-source apps (`call.md` 1,561 stars, `Director` 1,560) and Stream's Vision-Agents framework (8,186) (MEASURED, `gh api repos/...`).
7. **Pivot and staleness flags.**
   - **Overshoot (YC W26) has pivoted.** Its homepage and YC listing now say "We optimize inference stacks for AI teams", although the real-time vision API and its docs are still live (MEASURED, curl of overshoot.ai and the YC page).
   - Tinycloud has shipped nothing since 2026-09-01 (F3; re-MEASURED with `npm view`).
   - VideoDB's `Director` repo was last pushed 2026-01-23, and `videodb-director-mcp` was last published to PyPI on 2025-07-10. Both are older than 6 months (MEASURED).

## 1. Comparison table (ranked by importance to an agent builder)

| # | Product | How Claude Code reaches it | What the model sees | Spatial / motion output | Price (date) | ESTIMATED $/video-hour, one pass | Traction signal | Label |
|---|---|---|---|---|---|---|---|---|
| 1 | **TwelveLabs Models API** (Pegasus 1.6, Marengo 3.5) | Claude Code plugin (MCP + slash commands + skills). It still defaults to Pegasus 1.5, and its last feature commit is 2026-05-14 | Its own video-LLM encoder over visual frames, audio and transcription. 261,120-token context. Up to 2 h per call, 10 GB, 360p-5184×2160 | Text only: timestamped segments, in-segment events, egocentric action labels, next-action prediction | Pegasus input $1.75/video-h, output $7.50/1M. Marengo 3.5 video $0.26/1M tokens (overage page, read 2026-10-24) | **$1.75** + output (rate × 1 h) | $100M Series B 2026-07-01; `twelvelabs-python` 51 stars | DOCUMENTED |
| 2 | **TwelveLabs Jockey** | Hosted MCP `https://mcp.twelvelabs.io/jockey/mcp` (OAuth); claude.ai connector | An agent over a "knowledge store" (spatiotemporal context, typed ontology, embeddings) that Pegasus/Marengo build at ingest | Entity tracking timeline (text, with clip citations) | Free $0 (3 GB), Plus $29/mo (50 GB), Pro $99/mo (200 GB); Jockey $2/1M tokens; storage $0.065/GB-mo (2026-10-15 billing) | Plan-based; not per hour | GA 2026-10-15 | DOCUMENTED |
| 3 | **Memories.ai** Video Datalake (+ Visual Intelligence) | Hosted MCP `https://mcp.memories.ai/mcp` (OAuth); Claude Code / Codex plugin; `memories` CLI | Datalake: frames at `fps` 0.1-30 (default 1.0) → OmniRetriever 3072-d embeddings + OmniCaptioner captions + ASR + speakers + faces. Visual Intelligence: proxies **Gemini / Nova / Qwen** | Face/person library, safety events; nearest-frame JPEG via `get_frame` | Index $0.05/min at fps 1.0; search $0.008; derived read $0.001; storage $0.02/GB-mo; $20/mo starter (pricing page, read 2026-10-24) | **$3.00** at fps 1; vendor says **~$0.90** at fps 0.3 | $16M seed (TechCrunch 2026-03-16); plugin repo 1 star | DOCUMENTED |
| 4 | **VideoDB** | Hosted MCP `https://mcp.videodb.io/mcp` (OAuth, **89 tools**); `npx skills add video-db/skills` / plugin; local `videodb-director-mcp` | `video.understand()` analyzers: `spoken_words`, `vlm` (hosted tiers mini/basic/pro/ultra), `ocr`, `object_detection` (COCO-80 RT-DETR), brand/activity/location. Shot segmentation, frames sampled `uniform` or `interval` per scene | Object labels per frame (COCO), aggregations over `frames.detections.label`; scene descriptions | **Not published**: videodb.io/pricing is a "Talk to us" form (read 2026-10-24); secondary sources say $20 free credits, Pro $20/mo | unknown | ~$1.3M pre-seed (Wellfound, stale); `call.md` 1,561 stars, `Director` 1,560, `skills` 139 | DOCUMENTED |
| 5 | **VLM Run** (Gateway + Orion agent) | Hosted MCP `https://gateway.vlm.run/mcp` (bearer) with `read_video`/`read_image`/`read_audio`/`read_document`; `vlmrun-gw` skill | Clip forwarded **whole** to a native-video model (default `qwen/qwen3.8-27b`; also `gemma-4-26b-a4b-it`, `qwen3.5-0.8b`); `fps`, `max_frames` settable | **Yes**: `facebook/sam3.1` per-frame tracks, `vitpose-plus-large` pose keypoints | Per token: Gemma-4-26B $0.10/$0.30 per 1M; SAM 3.1 ~$1/1K images (gateway pricing doc, read 2026-10-24) | unknown (tokens per hour not published) | `vlmrun-hub` 555 stars, `vlmrun-cookbook` 311 (pushed 2026-10-20) | DOCUMENTED |
| 6 | **Perceptron** Mk1.5 | Hosted MCP `https://api.perceptron.inc/mcp` (bearer) with `question`/`caption`/`ocr`/`detect`; OpenAI-compatible chat | Sampled frames (+ soundtrack if `enable_audio_in_video: true`); **36,864-token context**, so short clips only; audio ≤21.8 min | **Yes**: `<track>` with timestamped point/box; `<clip>` intervals; optical-flow tracking guide | $0.15 in / $1.50 out per 1M (model card, read 2026-10-24) | short-clip model; per hour not meaningful | $21M (TechCrunch 2026-08-26); `isaac` 107 stars | DOCUMENTED |
| 7 | **Cloudglue / Tinycloud** | Tinycloud CLI + 8 skills + Claude Code plugin; `cloudglue-mcp-server` | Server-written text: speech, visual description, scene text, summary; thumbnails | Shots/chapters only | 4 credits/min; packs $15/1000 → $600/60000 (F3, 2026-10-23) | **$2.40-3.60** (F3) | YC S24, team of 3; Vercel AI Accelerator 2026-03-20 (PitchBook); no release since 2026-09-01 | DOCUMENTED + MEASURED |
| 8 | **Reka** Vision API (+ Edge) | Local stdio `uvx reka-mcp` (0.1.10, 2026-05-14) calling the cloud API; OpenAI-compatible chat for short clips | Vision API: transcript, per-chunk captions, embeddings, objects. Chat: `reka-edge-2603` (16k ctx, ≤3 images) or `qwen3.8-27b` (262k) on `video_url` | Objects, "detect prompted objects in a segment" | Index $0.05/min; search $0.005; QA $2/1M output; 3 h free; dev tier auto-deletes after 30 days (pricing doc, read 2026-10-24) | **$3.00** | $110M Series B **2025-07** (stale >6 mo) | DOCUMENTED |
| 9 | **Mixpeek** | Hosted MCP `https://mcp.mixpeek.com/mcp` (48 tools, bearer; scoped ingestion/retrieval/admin servers) | Feature extractors: fleet GPUs for search embeddings, faces, OCR; "multimodal understanding" is cost-plus on a third-party model | Faces, OCR, scenes | Video search $0.05/min, faces $0.10/min, OCR $0.10/min, multimodal understanding $0.0292/min, transcript $0.024/min; Build $25/mo (pricing page "as of August 2026") | **$1.75** understanding; **$3.00** search index; **$6** OCR | ~$650K pre-seed 2023 (stale); `mcp-server` 1 star, last push 2026-04-16 (stale) | DOCUMENTED |
| 10 | **Overshoot** (YC W26) | REST `ovs://streams/...` URLs inside OpenAI-compatible chat; no MCP | Live WebRTC/RTSP/HLS frames, 600 s retained window; `video_url` segment → generated clip at `max_fps` (default 1.0) sent to the chosen VLM, which can be Claude, Gemini, GPT-5.4, Gemma 4, Qwen 3.6 or Holo | Prompted boxes/points via the chosen VLM | List-price passthrough, e.g. Gemma-4-26B $0.06/$0.33 per 1M, Claude Opus 4.6 $5/$25 (`/billing/pricing`, versions dated 2026-06/07) | unknown | **Pivoted to inference optimization**; ~$500K (directory) | MEASURED (endpoints) + DOCUMENTED |
| 11 | **Jina v5-omni** (Elastic) | Elastic Inference Service, or local weights | Embeddings of text/image/video/audio in one 1024-d space aligned with the text model | none | Open weights **CC-BY-NC-4.0**; EIS price not read | n/a | HF: 975,261 downloads, 173 likes; card modified 2026-10-11 | MEASURED (HF API) + DOCUMENTED |
| 12 | **Stream Vision-Agents** (OSS framework) | Python framework; you host it; MCP/tool calling inside the agent | Live WebRTC video to Gemini Live / OpenAI Realtime (e.g. `gemini.Realtime(fps=10)`), with YOLO/Roboflow/Moondream processors running before the LLM | YOLO pose/detections per frame | Apache-2.0; Stream edge pricing not read | n/a | 8,186 stars, pushed 2026-10-24, v0.6.9 2026-08-13 | MEASURED (gh) + DOCUMENTED |
| 13 | **Coactive** | API-first enterprise platform; no MCP found | Model-agnostic tagging/search over image and video | Tags | Not public | unknown | >$44M; last round $30M Series B 2024-05 (stale) | DOCUMENTED (secondary) |
| 14 | **Imaginario AI** | Web app + API (AWS Marketplace); no MCP found | Embeddings over visuals, sounds and speech; "StoryLab agents" assemble rough cuts | Faces, logos, on-screen text | "Flat team pricing" (homepage), no public rate | unknown | ~$1.2M pre-seed (CB Insights, stale) | DOCUMENTED (secondary) |
| 15 | **Vertical YC/seed entrants**: Conntour (W25, $7M seed), OnDeck AI (S25, Perception-0), OpenVector (S26), Nomadic (seed $8.4M, 2026-03-31) | Enterprise apps or APIs for security, industrial and AV fleets; no Claude path found | Proprietary or frontier VLMs over camera feeds | Alerts, counts, event search | Sales-led | unknown | as listed | DOCUMENTED (secondary) |

## 2. Entries in detail

### 2.1 TwelveLabs Models API: Pegasus 1.6 and Marengo 3.5 (DOCUMENTED)

- **API shape.** REST plus SDKs (`twelvelabs` 1.3.6 on PyPI, 2026-10-06, MEASURED `curl pypi.org/pypi/twelvelabs/json`). Analyze (sync and async), segment, search, embed. Available on Amazon Bedrock as well. The Claude Code plugin's slash commands are `/twelvelabs:index-video`, `/twelvelabs:search`, `/twelvelabs:sync-analyze` and `/twelvelabs:async-analyze`. `sync-analyze` defaults to **Pegasus 1.5**, and the plugin's newest feature commit is 2026-05-14, "sync plugin with twelvelabs-mcp 1.0.0" (MEASURED `gh api repos/twelvelabs-io/twelve-labs-claude-code-plugin/commits`). The plugin has not picked up Pegasus 1.6.
- **What the model sees.** Pegasus is "a video encoder, a video tokenizer, and a large language model". It is native video plus audio, not frames sent to someone else's LLM. Video content, audio transcription, prompt, reference images, JSON schema and output all share the 261,120-token context. Inputs are up to 2 h analysed (4 h source with a window), ≤10 GB and 360×360 to 5184×2160. English is fully supported and 12 more languages partially (https://docs.twelvelabs.io/v1.3/docs/concepts/models/pegasus/pegasus-1-6.md; https://docs.twelvelabs.io/v1.3/docs/concepts/multimodal-large-language-models.md). Marengo is said to encode "motion dynamics, temporal relationships", "non-verbal sound recognition, and music interpretation" (same page; vendor claim).
- **Spatial/motion.** Pegasus 1.6 (2026-10-06) adds egocentric video, action labelling, QC of robotics footage, "Trajectory and next-action prediction" and in-segment timestamped events. All of this is text output; no boxes are documented.
- **Pricing** (https://www.twelvelabs.io/overage, read 2026-10-24): Pegasus 1.6 video input $1.75/hour, image $3/1M tokens, output $7.50/1M. Marengo 3.5 video $0.260/1M tokens, audio $0.065/1M, image $0.080/1M, text $0.200/1M, document $0.162/1M. Marengo 3.0 search $4/1,000 queries. Since 2026-10-15 these are overage rates on top of Free/Plus/Pro allowances, and overage is available on Pro only (https://docs.twelvelabs.io/v1.3/agents/get-started/plans-and-billing/plans-allowances-and-overage.md).
- **Privacy, re-verified today.** "We use Customer Data to facilitate the customer's use of the Twelve Labs Services and improve the Twelve Labs Services". This includes outputs such as "generated video captions ... and numeric video and text vector representations" (https://www.twelvelabs.io/privacy-policy, MEASURED by curl + text extract). This still blocks private recordings, as VAA:7 concluded.
- **Evidence.** Vendor claims only: the homepage says Pegasus 1.5 is "+17%" over Gemini 3.1 Pro on Video-MME (>30 min). TwelveLabs' own "Video-to-Text Arena" is vendor-hosted and qualitative. No third-party leaderboard I found lists Pegasus.
- **Traction.** $100M Series B announced 2026-07-01, co-led by NEA and NAVER Ventures, with Amazon participating (https://ecvc.wsgr.com/news/wilson-sonsini-advises-twelvelabs-on-dollar100-million-series-b; https://en.edaily.co.kr/news/eda202607025071/). Cumulative funding is $207-217M (sources differ).

### 2.2 TwelveLabs Jockey (DOCUMENTED)

- **API shape.** Hosted MCP `https://mcp.twelvelabs.io/jockey/mcp` (remote HTTP + OAuth) for Claude, Claude Code and ChatGPT, plus an Agents API (knowledge stores, items, responses, search). Tools cover cross-video search, answers with clip citations, rendered widgets (gallery, timeline, highlight reel) and collection management (https://docs.twelvelabs.io/v1.3/docs/advanced/model-context-protocol.md).
- **What the model sees.** Items are processed into a "knowledge store ... spatiotemporal context, a typed ontology, and embeddings". Jockey reasons over that store, not over raw pixels at query time (INFERRED from the concept description).
- **Recent changes.** Ingest is now configurable (configure-ingestion page). Release notes: 2026-10-22 search by item collection; 2026-10-15 GA and new billing; 2026-10-09 web search inside responses; 2026-10-07/08 location filtering and enriched metadata (https://docs.twelvelabs.io/v1.3/docs/get-started/release-notes.md).
- **Pricing.** Same as F3: Free/Plus $29/Pro $99, Jockey $2/1M tokens (re-read today on the pricing and overage pages).
- **Claude fit.** It is the only zero-code route into claude.ai and Claude Code with corpus-level memory. Every video is uploaded to TwelveLabs and falls under the "improve" clause above.

### 2.3 Memories.ai: Video Datalake, MCP and plugin (DOCUMENTED)

- **API shape.** The Video Datalake is a REST API with 41 endpoints, in preview since 2026-08-03 (https://docs.memories.ai/changelog.md):
  - collections;
  - upload by URL, file or resumable session;
  - a uniform `202 + Operation` async model with HMAC-signed webhooks;
  - moments (`get_moment`, `get_frame`, `get_clip`, captions, transcription, title, summary, speakers, face entities);
  - semantic, keyword, hybrid and image search;
  - a face/person library, safety events, and live streams over SSE.
  
  The hosted MCP `https://mcp.memories.ai/mcp` uses OAuth and is "intent-first", not a 1:1 mirror of the REST API. Its tools are `search_moments`, `get_moment`, `upload_video`, `open_stream`, `create_person` and `wait_for_operation` (https://docs.memories.ai/mcp-server.md). The Claude Code plugin is `claude plugin marketplace add Memories-ai-labs/memories-ai-plugin`, which installs a thin skill pack plus the hosted MCP (https://docs.memories.ai/plugin.md).
- **What the model sees.**
  - **Datalake:** frames sampled at `fps` 0.1-30 (default 1.0). Every collection embeds with **OmniRetriever** (3072-d, multilingual; the only accepted value since 2026-08-18), and captions and summaries come from **OmniCaptioner** (changelog).
  - **Visual Intelligence**, the stateless API, documents three *third-party* video providers. Gemini is the "best default" (`gemini:gemini-3-flash-preview`), Qwen the cheapest (`qwen:qwen3-vl-flash`), and Nova is for tool-style extraction (https://docs.memories.ai/visual-intelligence/video-model-selection.md). Transcription is resold from ElevenLabs Scribe V2 and AssemblyAI Universal-2 (llms.txt index).
  - The public API docs do not name the "Large Visual Memory Model" itself. Whether OmniRetriever/OmniCaptioner *are* LVMM 2.0 is not stated (INFERRED gap).
- **Spatial/motion.** Face recognition and safety detection are per-collection options. Nothing documents tracks or boxes in agent tools. The `fps` lever is the only motion control ("raise it for fast action", FAQ).
- **Pricing** (https://docs.memories.ai/datalake/pricing.md, read 2026-10-24):
  - indexing $0.05 per video minute at fps 1.0, scaling with fps; the vendor's headline is "about $0.90 per hour" at fps 0.3;
  - live stream $0.05/min; search $0.008; moment $0.008; derived reads $0.001; clip $0.005 + $0.01/GB; storage $0.02/GB-month; $20/month starter plan.
  - Stored data is **deleted 30 days after the balance reaches zero**.
- **Traction.** $8M seed in July 2025 plus an $8M extension, $16M in total (TechCrunch 2026-03-16, https://techcrunch.com/2026/03/16/memories-ai-is-building-the-visual-memory-layer-for-wearables-and-robotics/). It has NVIDIA (Cosmos-Reason 2, Metropolis) and Qualcomm on-device partnerships for LVMM 2.0. The founder says commercial focus is "the model and the infrastructure". The `Memories-ai-labs/memories-ai-plugin` repo has 1 star and was last pushed 2026-07-27; `Internet2EgoExo` has 20 stars (MEASURED `gh api`). The privacy page renders client-side and could not be read with curl, so its training terms are **unknown**.

### 2.4 VideoDB (DOCUMENTED; pricing unknown)

- **API shape.** Python SDK `videodb` 0.5.1 (PyPI 2026-07-24, MEASURED). The hosted MCP `https://mcp.videodb.io/mcp` has **89 tools** in toolsets: assets, understand/index/search, editor and timeline, real-time streams, capture (https://docs.videodb.io/pages/mcp/tools.md). There is a Skills pack plus Claude Code plugin (`/plugin marketplace add video-db/skills`; MCP via browser OAuth) and the older local stdio `videodb-director-mcp`. The latter's last PyPI release is 0.1.7 of 2025-07-10, so it is **stale** (MEASURED). The MCP connector says it collects "the arguments of the tool call being run, and nothing else" (https://docs.videodb.io/pages/mcp/auth-and-privacy.md).
- **What the model sees.** `video.understand(analyzers=[...])` runs named analyzers and stores each result as an artifact:
  - `spoken_words` → transcript;
  - `vlm` → scene descriptions, with hosted tiers `mini`/`basic`/`pro`/`ultra` whose underlying vendor is **not named**;
  - `ocr`, `brand_detection`, `activity_recognition` and `location_detection`, which are VLM-backed;
  - `object_detection` (COCO-80, RT-DETR v2).
  
  Default segmentation is `{"type": "shot", "threshold": 30}`. Sampling is `uniform` (N frames per scene) or `interval` (every N s), and frames can be downscaled with `transform.resolution`. VLM prompts can take in other artifacts (`{{inputs.transcript}}`) (https://docs.videodb.io/pages/understand/indexing-pipelines/understanding-artifacts.md). Sandbox Compute runs Qwen3-4B, whisper-large-v3-turbo, OmniVoice and RT-DETR on VideoDB GPUs (https://docs.videodb.io/pages/core-concepts/sandbox-models.md).
- **Spatial/motion.** Per-frame COCO detections are queryable with `group_by: frames.detections.label`. The `interval` sampling guidance is labelled "monitoring motion". There is no tracking.
- **Distinctive.** Real-time desktop capture (screen, mic, system audio) and RTSP **for agents**. The open-source apps on top are `call.md` (meetings, 1,561 stars), `pair-programmer` ("Pair Programmer for Claude Code, Codex and Cursor", 131 stars) and `bloom` ("agentic Loom alternative", 235 stars) (MEASURED `gh api orgs/video-db/repos`). Media is "stored until you delete them, with no automatic expiry". Its privacy policy says audio for transcription is used "to improve our algorithms" (https://videodb.io/legal/privacy, MEASURED curl).
- **Pricing.** Not published. https://videodb.io/pricing serves a contact form (MEASURED 2026-10-24). A secondary listing says $20 of free credits and a $20/month Pro plan; that is unverified.
- **Traction.** About $1.3M pre-seed (Wellfound, undated or stale). It acquired Devzery in 2025-11. It runs 2026 hackathons ("Give Agents Eyes and Ears").

### 2.5 VLM Run: Gateway MCP and the Orion agent (DOCUMENTED)

- **API shape.** The OpenAI-compatible gateway is `https://gateway.vlm.run/v1/openai`. Its hosted MCP `https://gateway.vlm.run/mcp` (Streamable HTTP, bearer or OAuth) exposes `read_document`, `read_image`, `read_audio`, `read_video`, `list_models`, `get_model_info` and `get_completion`. All tools are annotated `readOnlyHint: true`, so "Clients can run these tools without a confirmation prompt" (https://docs.vlm.run/gateway/mcp-tools.md). A `vlmrun-gw` skill exists for coding agents. Orion-2 is a separate agent with a code-execution sandbox (`$0.001/call`) and a per-span cost ledger (https://docs.vlm.run/pricing.md).
- **What the model sees.** `read_video` forwards "the clip ... whole" to a model that ingests video natively; "a model without video support is refused". The default is `qwen/qwen3.8-27b`, with `qwen/qwen3.5-0.8b` and `google/gemma-4-26b-a4b-it` as alternatives. `fps` and `max_frames` are settable. `url` must be http(s), a `data:` URI or base64, "never a local path" (same page).
- **Spatial/motion.** This is the only agent-facing MCP I found that returns **per-frame segmentation tracks** (`facebook/sam3.1`, method `track`, where the prompt names the object) and **pose keypoints** (`usyd-community/vitpose-plus-large`). These are structured records, not prose (DOCUMENTED; untested).
- **Pricing** (https://docs.vlm.run/gateway/pricing.md, read 2026-10-24): per token, e.g. Gemma-4-26B at $0.10/1M input and $0.30/1M output. SAM 3.1 is per image ("$1 / 1K images" as the example). Parakeet ASR is $16.67/1M audio-seconds, about $0.06 per audio hour. Minimum $0.001 per call. Live rates are on `GET /v1/openai/models`. Video tokens per hour are not published, so no $/hour figure is possible.
- **Traction.** `vlmrun-hub` has 555 stars (last push 2025-12-15), `vlmrun-cookbook` 311 (2026-10-20) and `mm` 73 (2026-10-20). `vlmrun` SDK 0.9.2 was released 2026-09-25 (MEASURED `gh api`, PyPI). Funding not found.

### 2.6 Perceptron Mk1.5 (DOCUMENTED)

- **API shape.** OpenAI-compatible chat completions, Multilook (many prompts over one shared context), and a Files API. The hosted MCP is `https://api.perceptron.inc/mcp` with tools `question`, `caption`, `ocr` and `detect`. Each takes one media input, and `modality` has to be set for video or audio (https://docs.perceptron.inc/perceptron-mk1.5/guides/mcp.md). It is also on OpenRouter and AWS Marketplace.
- **What the model sees.** Sampled video frames, grouped temporally and spatially. The soundtrack is included only with `vision_config.enable_audio_in_video: true` and is off by default. Audio costs about 750 tokens/min and is capped at 16,384 tokens (about 21.8 min) per item. The **context window is 36,864 tokens** and output is capped at 8,192, so this is a short-clip model. The docs say so themselves: "Frame sampling can miss brief events; avoid treating a missing observation as proof that an event never occurred" (https://docs.perceptron.inc/perceptron-mk1.5/models/perceptron-mk1.5.md; .../capabilities/video-understanding.md).
- **Spatial/motion.**
  - `<track>` gives timestamped `point_box` observations of an object.
  - `<clip>` gives moment and interval annotations.
  - In-context learning matches a reference image in a video.
  - A "High Fidelity Object Tracking" guide turns model waypoints into dense tracks "with optical flow and appearance" matching.
  
  Mk1.5 shipped 2026-09-25; Isaac 0.1/0.2 were retired from the API the same day (changelog). The open-weight Isaac 0.5 (36B sparse) was released around 2026-08-26 with LeRobot training code.
- **Pricing.** $0.15/1M input, $1.50/1M output, $0.0375/1M cached input (model card, read 2026-10-24).
- **Traction.** $21M from Bessemer, Foundation Capital and S32 (TechCrunch 2026-08-26). Founded 2024-11 by ex-FAIR researchers. `isaac` repo 107 stars (MEASURED `gh api`).
- **Evidence.** Vendor claims only. The 2026-05-12 press release claims parity with "frontier labs at a fraction of the cost".

### 2.7 Cloudglue and Tinycloud (DOCUMENTED + MEASURED)

There is no change since F3. `npm view @cloudglue/tinycloud` still reports 0.3.25, modified 2026-09-01T02:22Z (MEASURED today). The newest changelog entry is 2026-08-29 (MEASURED curl of `docs.cloudglue.dev/changelog.md`). The PyPI `cloudglue` package is 0.7.28 of 2026-08-31 (MEASURED). New traction data: a YC S24 listing with a team of 3, and a PitchBook "Accelerator/Incubator" deal on 2026-03-20 with Vercel's AI Accelerator (https://pitchbook.com/profiles/company/640146-79, secondary). The modality path, price and Claude fit are in F3 §1 and §3 and P3.

### 2.8 Reka: Vision API, reka-mcp and Edge (DOCUMENTED)

- **API shape.** The Vision API has endpoints for videos, video groups, features on demand (`trigger-transcript`, `-captions`, `-embeddings`, `-objects`), search, chat-with-videos, insights (captions, transcript, scenes, objects, segment-video), YouTube automations, clip generation and metadata tagging (https://docs.reka.ai/llms.txt). The MCP is **local stdio** `uvx reka-mcp` with `REKA_VISION_API_KEY` (0.1.10, PyPI 2026-05-14, MEASURED). It is a thin wrapper, and the video still goes to Reka's cloud (https://docs.reka.ai/vision/mcp-server.md).
- **What the model sees.** The chat API takes OpenAI `video_url` parts on `reka-edge-2603` (16k context, at most 3 images) and on a hosted **`qwen3.8-27b`** (262k). `reka-flash-3` is text-only (https://docs.reka.ai/chat/models.md). For control, the docs tell you to run ffmpeg `fps=1` yourself and send the frames as images. Edge open weights run locally on Apple Silicon with 32 GB+ (VAA).
- **Pricing** (https://docs.reka.ai/vision/pricing.md, read 2026-10-24): indexing $0.05 per input minute, search $0.005, QA/tagging $2/1M output tokens, clips $0.04/min (+$0.01 at 1080p), 3 h free. Developer-tier storage is auto-deleted after 30 days.
- **Privacy.** "If you use our Services on a free basis (e.g., ... promotional credits via the API), we may use your interactions ... to train and improve our machine learning models" (https://www.reka.ai/privacy-policy, MEASURED curl). Free-tier testing on private video is therefore training-eligible.
- **Traction.** $110M Series B in **2025-07** (NVIDIA, Snowflake), so the newest funding evidence is more than 6 months old. `reka-sdk-python` was pushed 2026-10-06 and has 18 stars (MEASURED).

### 2.9 Mixpeek (DOCUMENTED)

- **API shape.** Hosted MCP in four scopes: full (48 tools), ingestion, retrieval and admin. Each is `https://mcp.mixpeek.com/.../mcp` with a bearer key, and a retrieval-scoped key makes the agent read-only. There is also a per-retriever generated `search` tool (`mixpeek-mcp-retriever`) (https://mixpeek.com/docs/overview/agents.md). The `mixpeek` SDK 1.3.783 was published 2026-10-23 (MEASURED, PyPI), so it is very active. The open-source `mixpeek/mcp-server` has 1 star and was last pushed 2026-04-16 (stale; MEASURED). Its most-starred repo is `amux` (544), which is not video.
- **What the model sees.** Extractors are either "Fleet rows" on Mixpeek GPUs (video search embeddings, faces, on-screen text) or "External rows" that are "cost-plus on a third-party model" ("multimodal understanding" = transcript + OCR + scene descriptions). The third-party model is not named (https://mixpeek.com/pricing).
- **Pricing** (pricing page, labelled "As of August 2026"): video $0.05/min, audio $0.01/min, faces $0.10/min, OCR $0.10/min, multimodal understanding $0.0292/min of video, transcript add-on $0.024/min, vectors $1.56/1M per month. Build plan $25/month, Scale $250/month, Enterprise from $10,000/month.
- **Privacy.** "We do not train foundation models on your content" (https://mixpeek.com/privacy, MEASURED curl). Self-hosting is offered.
- **Traction.** About $650K pre-seed in 2023 (VCBacked, stale).

### 2.10 Overshoot (YC W26): real-time vision API, now pivoted (MEASURED + DOCUMENTED)

- **API shape.** `POST /streams` returns a LiveKit room and publish token (or the server pulls RTSP/HLS, added 2026-08-05). Chat completions then reference `ovs://streams/<id>?frame_index=-1` (one frame, as `image_url`) or `?start_offset_ms=-5000&max_fps=2` (a segment, as `video_url`, "sent to the selected model as a generated clip"). Frames are kept for 600 s, and leases expire after 5 min. Frames "may be compressed or resized before inference" (https://docs.overshoot.ai/api-reference/stream-media-urls.md, .../limits.md).
- **Models.** `GET https://api.overshoot.ai/v1/models` lists 14 models; 9 are "ready", including `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5`, `gemini-3-flash-preview`, `gemini-3.1-pro-preview`, `gemma-4-26B/31B`, `Qwen3.6-27B-FP8` and `Holo-3.1-35B`. `GET https://api.overshoot.ai/billing/pricing` shows list-price passthrough, e.g. Opus 4.6 at $5/$25 per 1M and Gemma-4-26B at $0.06/$0.33 per 1M, with price versions dated 2026-06-09 to 2026-07-10 (MEASURED: curl of both endpoints, parsed with python).
- **Pivot flag.** overshoot.ai now reads "We optimize inference stacks for AI teams ... You only pay if we meet the performance target". The YC company page reads "We optimize inference stacks for teams". The launch post that claimed "1000+ developers ... <200ms" remains (MEASURED, curl). The latest changelog entry is a ToS update on 2026-09-28. **Treat the vision API as at risk.**

### 2.11 Jina embeddings v5-omni, now part of Elastic (MEASURED + DOCUMENTED)

`jinaai/jina-embeddings-v5-omni-small` (about 1.74B parameters, 1024-d) embeds text, images, video (`.mp4`/`.mov`/`.mkv`/...) and audio into a space aligned with the text-only v5 model. You can index with text and query with any modality without reindexing. Created 2026-04-01 and modified 2026-10-11, with 975,261 downloads and 173 likes (MEASURED `curl huggingface.co/api/models/...`). The license is **CC-BY-NC-4.0**, so commercial use goes through Elastic Inference Service (model card; arXiv 2605.08384). It is a retrieval primitive, not an agent product. It would sit underneath an on-device index (INFERRED).

### 2.12 Stream Vision-Agents (MEASURED + DOCUMENTED)

An open-source Python framework, Apache-2.0 (MEASURED `gh api`). It has 8,186 stars, was pushed 2026-10-24, and its latest release is v0.6.9 of 2026-08-13. It connects WebRTC video to realtime LLMs (Gemini Live, OpenAI Realtime, Nova Sonic, Qwen) and supports Claude through native SDK methods. Pluggable processors run before or after the LLM, for example `gemini.Realtime(fps=10)` with `ultralytics.YOLOPoseProcessor`. TwelveLabs and Moondream integrations exist (README). It is the closest open-source "live video agent" scaffold. Claude has no realtime video, so Claude's role would be tool-calling over processor outputs (INFERRED).

### 2.13 Coactive, Imaginario and the vertical entrants (DOCUMENTED, secondary)

- **Coactive.** API-first enterprise platform ("search, tag, & analyze petabytes of image & video through an API-first platform", homepage). Funding >$44M, with the last round in 2024-05 (stale). No MCP or agent integration was found.
- **Imaginario.** Positions itself as "the application your team works in ... on flat team pricing rather than per minute of video", with "StoryLab agents" for rough cuts and an AWS Marketplace API. Not an agent backend.
- **Conntour** (YC W25, $7M seed 2026-03) does natural-language search and alerts over government camera feeds.
- **OnDeck AI** (YC S25) sells "Perception-0" and claims 81.2% against Gemini 3.1 Pro's 78.5% on an unnamed chart (homepage, vendor claim).
- **OpenVector** (YC S26) offers "Video inference as low as 50ms" and a VLA "camera → computer-use" workflow.
- **Nomadic** ($8.4M seed 2026-03-31, TQ Ventures) structures AV and robotics fleet video with VLMs.

These overlap with the R8 vertical axis. None offers a Claude-side integration (MCP, skill or plugin) that I could find.

## 3. Narrative for this axis

**What an agent builder actually gets.** All the agent-native startups sell the same contract: *upload the video, we index it on our side, your agent calls search/read tools and gets text with timestamps.* They differ in four ways:

1. **Who owns the model.**
   - TwelveLabs and Perceptron train their own video models.
   - Memories.ai, Mixpeek, VLM Run, Overshoot, and partly Reka, broker other people's models. Most often those are Gemini and Qwen, and in Overshoot's case Claude itself.
   - VideoDB does not name the model behind its `vlm` tiers.
2. **How much state they keep.** Persistent "knowledge stores" or lakes (Jockey, Memories, VideoDB, Mixpeek, Reka) versus stateless reads (VLM Run gateway, Perceptron, Overshoot).
3. **Whether anything beyond prose comes back.** Only VLM Run (SAM 3.1 tracks, ViTPose keypoints) and Perceptron (`<track>` boxes and points) return geometry. They are the only products here that touch the "motion and 3-D" gap that F2 measured at 20-60 points.
4. **The Claude integration path.** Hosted OAuth MCP plus a Claude Code plugin is now table stakes (Memories, VideoDB, Jockey). TwelveLabs' own Claude Code plugin lags five months behind its models.

**What this means for our Opus 5.5 agent (INFERRED).** None of these products changes F3's conclusion. Each is a cloud transcode, and each uploads the whole file. For private recordings the blockers are data-use terms:
- TwelveLabs "improve the Services";
- VideoDB "improve our algorithms" for transcription audio;
- Reka free-tier training;
- Memories.ai policy unreadable;
- Mixpeek is the only one that states no foundation-model training.

**The pieces worth borrowing:**
- the index→search→`get_moment(ref)` chain (Memories, Jockey);
- VideoDB's analyzer graph, where a VLM prompt takes in `{{inputs.transcript}}` and `{{inputs.ocr}}` per scene;
- Overshoot's `ovs://...?start_offset_ms=&max_fps=` addressing, which is a clean design for a local frame-server MCP;
- for the motion gap, a VLM Run or Perceptron-style track output. It can be built locally from open SAM 3.x and pose models, without sending video to a startup.

**Cheapest per-hour cloud index on this axis (ESTIMATED: published per-minute rate × 60):** Memories.ai at fps 0.3, about $0.90 (vendor figure), then TwelveLabs Pegasus at $1.75 and Mixpeek multimodal understanding at $1.75. All of them cost more than Gemini direct ($0.11-0.81/h, VAA:4).

## 4. Not found, dead or unverifiable

- **Overshoot real-time vision**: the company has pivoted to inference optimization. The API is still up but at risk (MEASURED).
- **Moonvalley**: a generative-video company. I found no video-understanding API, so "Moonvalley-adjacent" turned up nothing on this axis.
- **TwelveLabs MCP server repo** `twelvelabs-io/twelvelabs-mcp-server`: 404 (MEASURED `gh api`). The plugin references `twelvelabs-mcp 1.0.0` without a public repo under that name.
- **Coactive MCP or agent integration**: none found.
- **Imaginario public API docs or pricing**: not found (secondary sources only).
- **VideoDB public pricing**: not published (contact form, MEASURED).
- **Memories.ai privacy and training terms**: the page is client-rendered and was unreadable by curl.
- **Memories.ai LVMM as a named API model**: not documented in the API docs; only OmniRetriever and OmniCaptioner are named.
- **A 2025-2026 YC company selling a general "video understanding API for LLM agents"**: none found apart from Overshoot (now pivoted). A scan of the yc-oss dataset (6,335 companies; regex over 2025-2026 batches) found only vertical products (Conntour, OnDeck, OpenVector, Aspect, Mosaic/Motion for editing).
- **Independent benchmarks of any startup model here**: none found.

## 5. Gaps

- None of these products was run on a video, so quality and every spatial or motion claim are untested.
- VLM Run and Perceptron publish no video tokens-per-hour figure, so no $/hour figure can be given for them.
- VideoDB's `vlm` tier vendors and Mixpeek's "third-party model" are unnamed.
- Funding figures for VideoDB, Mixpeek, Imaginario and Overshoot come from directories and are stale or unverified.
