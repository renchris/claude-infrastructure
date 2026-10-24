# R8: vertical and specialty video understanding for agents, as of 2026-10-24

Axis: screen-recording / UI video, meeting video, sports and broadcast, security and surveillance video LLMs,
robotics and world-model video understanding, and video-editing agents. Products are included only if they give an
agent or API caller some *understanding* of video. Products that only generate video, or that offer understanding only
inside their own UI, are listed under "Excluded".

Labels: **MEASURED** means I ran the named command today. **DOCUMENTED** means a vendor page, README, model card or
paper says it; we have not tested it. **INFERRED** means my own reasoning. Every price is as fetched on 2026-10-24
unless the page carries its own date. Nothing was installed, no account was created, and no video was uploaded.

GitHub numbers are MEASURED with `curl -sL https://api.github.com/repos/<owner>/<repo>` (fields
`stargazers_count`, `pushed_at`, `license.spdx_id`) and `.../releases?per_page=3`, run on 2026-10-24.

Baseline this extends (not repeated here): Opus 5.5 has no video or audio input, so every route is either a transcode
into text plus stills, or a remote model that returns text. TwelveLabs, Cloudglue/Tinycloud, Gemini and the generic
video APIs are covered in `../../video-understanding-human-parity-2026-10-23/agents/F3-tinycloud-and-agent-video-tools-now.md`.

## Narrative

**1. For UI and bug video, the best vertical tools avoid video altogether, or hand Claude the frames directly.**
Two products fit a Claude Code agent well today.

- **Jam's MCP** has a `getFrames` tool that returns timestamped image frames: an overview grid of 6-16 frames, frames
  at exact milliseconds, or N frames across a window. It sits next to `getConsoleLogs`, `getNetworkRequests`,
  `getUserEvents`, a WebVTT transcript and AI chapters. That is the "frames plus transcript" transcode our baseline
  uses, done by the vendor and already aligned with the app telemetry.
- **Replay MCP** records the browser runtime deterministically rather than as pixels. The agent inspects variables,
  call stacks, network calls, React renders and screenshots at any point in time. For a web bug that beats watching
  video (INFERRED), because the thing a human watcher misses (state) is in the recording.

PostHog's MCP covers the analytics-replay side. It returns metadata and summaries. Its closed-beta Replay Vision renders
a DOM session to a sped-up video, sends it to Gemini, and returns structured observations.

**2. The one independent screen-recording benchmark found favours Claude with sampled frames.**
GUIDE (CVPR 2026, arXiv 2603.25864) tested 8 models zero-shot on 67.5 h of novice screen recordings, 32 uniformly
sampled frames per segment, no audio. Claude-4.5-Sonnet was best on behavior-state detection (44.61%) and on intent
prediction (71.39%). Gemini-2.5-Pro led help-need detection without context (69.82%). Absolute scores are low. Adding
user context lifts help prediction by up to about 50 points. Lesson: for UI video, telemetry and context (Jam/Replay)
matter more than the choice of model.

**3. Meeting video: the notetaker MCPs give transcripts only. Recall.ai is the only API that hands an agent pixels.**

- Fireflies, Fathom, Granola, Otter and Loom (through Atlassian Rovo MCP) give Claude transcripts, summaries and action
  items. None documents a frame or video tool.
- Recall.ai's bot API returns mixed video and per-participant video (separate files are a beta behind a feature flag).
  It can also stream real-time base64 PNG frames per participant and per screenshare over a websocket, at 360p and
  2 fps. An agent can sample those frames into Claude.
- Recall's own MCP is for operating the account (bots, recordings, logs, docs), not for understanding.
- Price: $0.50 per recording hour, plus $0.15 per hour for transcription (post dated 2026-03-10, updated 2026-09-14).

**4. Robotics and world-model understanding now has two serious agent-callable options.**

- **Gemini Robotics-ER 2** (2026-07-30) is a hosted API. Its documented features include video moment finding (Google
  reports 91.3% and a 0.96 s mean absolute error), progress classification (57.4%), object tracking in video, pointing,
  boxes and trajectories. Paid price: $1.00 per 1M input tokens and $5.00 per 1M output tokens until 2026-12-31, then
  doubling. A free tier exists. It is the strongest documented *temporal and motion* claim reachable from an agent.
  All figures are Google's own.
- **NVIDIA Cosmos 3 Reasoner** (2026-05-31; OpenMDW-1.1) is the open, local counterpart. It takes video at 4 fps, has
  a 256K context, and outputs text with 2D/3D points and boxes. It replaced Cosmos Reason 2 on build.nvidia.com.
- Meta's V-JEPA 2.1 (2026-03-16, MIT) is an encoder and world model with no text interface. It is a primitive for
  motion features, not something Claude can query.

**5. Security video has agent hooks, but most are thin or gated.**

- NVIDIA's open VSS 3.x blueprint is the real self-hostable "agentic video search" stack. It ships an MCP server
  (VA-MCP over Elasticsearch incidents) and agentskills.io skills. Its default VLM is Cosmos3 Nano Reasoner. The repo
  was pushed on 2026-10-24 (MEASURED).
- Spot AI claims an open API, webhooks and a "live Model Context Protocol endpoint". Only a community `spot-ai-mcp`
  is verifiable, and it exposes event counts, not VLM answers.
- Verkada's Catalyst MCP (October 2026) is a private beta with no published tools.
- Ambient.ai Pulsar, Coram, Lumana and Conntour have natural-language search inside their own products, with no
  developer API found.

**6. Sports and editing are weak for agents.**

- Magnifi has a partner-only REST API that returns detected key moments. WSC Sports has no public API.
- Descript is the only editing agent with a public API and an MCP (Underlord behind one agentic endpoint). What it
  returns is transcripts and edit summaries. Its own blog says visual editing is handed back to the UI.
- Runway, Captions/Mirage and OpusClip are generation or clipping APIs, not understanding.

## Comparison table (ranked by importance to a Claude Code agent builder)

| # | Name | Vertical | What reaches Claude | Video into model? | Deployment | Price (date) | Label |
|---|---|---|---|---|---|---|---|
| 1 | Jam MCP | UI / bug repro | Timestamped frames as images, WebVTT transcript, AI chapters, console, network, user events | Frames to Claude (6-16 grid, or exact ms) | Cloud (some tools use Gemini) | Free $0 (30 Jams, 5-min cap, MCP included); Team $14/creator/mo yearly (2026-10-24) | DOCUMENTED |
| 2 | Replay MCP | UI / web bug | Time-travel runtime: variables, stacks, network, React renders, screenshots | No video; deterministic runtime recording | Cloud; private cloud and on-prem tiers | Free tier; plan cards $0 / $17 / $170/mo, but the page's FAQ contradicts the card prices (2026-10-24) | DOCUMENTED |
| 3 | screenpipe | Screen memory | OCR and accessibility text, audio transcripts, input events, optional base64 frames, `export-video` | Frames on request; text index | Local by default; analytics on by default | Source-available commercial licence; price not checked | DOCUMENTED; GitHub MEASURED |
| 4 | Recall.ai | Meeting video | Mixed and per-participant video files; real-time PNG frames (2 fps, 360p) or H.264, per webcam and screenshare | Raw pixels to your code, which samples them into Claude | Cloud | $0.50/rec-h, +$0.15/h transcription, storage $0.05/media-h per 30 days after 7 days free (2026-03-10, updated 2026-09-14) | DOCUMENTED |
| 5 | Gemini Robotics-ER 2 | Robotics / physical | Moment finding, progress, tracking, points, boxes, trajectories; streaming variant | Native video and audio (Gemini) | Cloud API | $1.00/M in, $5.00/M out until 2026-12-31, then $2/$10; free tier (2026-10-24) | DOCUMENTED (vendor numbers) |
| 6 | NVIDIA Cosmos 3 Reasoner (Nano 16B) | Robotics / physical | Text reasoning plus 2D/3D points and boxes from video | Native video at 4 fps, 256K context; no audio on the Reasoner | Local (vLLM, H100/H200 class) plus build.nvidia.com trial | Open weights, OpenMDW-1.1; hosted is a trial | DOCUMENTED |
| 7 | NVIDIA VSS 3.x blueprint | Security / smart spaces / warehouse | MCP (VA-MCP: incidents, sensors, FOV, speeds, analyze), search, Q&A, summarization, clip retrieval, agent skills | VLM on chunked video; dense captions | Self-hosted GPU; Launchable | Apache-2.0 repo; NIM self-host needs an NVAIE licence | DOCUMENTED; GitHub MEASURED |
| 8 | GUIDE benchmark | UI video eval | Independent scores for 8 models on screen recordings | 32 uniform frames, no audio | Dataset at guide-bench.github.io | n/a | DOCUMENTED (independent) |
| 9 | PostHog session-replay MCP and Replay Vision | Product analytics | Recording search and metadata, session summaries; Vision observations (key moment, typed answer) | Vision renders DOM replay to video and sends it to Gemini | Cloud | Vision: cost set per scanner model; marketing page says 2,500 credits/mo free (undated) | DOCUMENTED |
| 10 | Notetaker MCPs (Fireflies, Fathom, Granola, Otter) | Meetings | Transcripts, summaries, notes; no video | No | Cloud | Granola MCP on Business, about $14-19/user/mo (third-party, 2026-08); others vary | DOCUMENTED |
| 11 | Loom via Atlassian Rovo MCP v2 | Async screen video | Video metadata, transcripts, AI meeting action items; comments and upload | No | Cloud; uses Rovo credits | Rovo credits (rate not found) | DOCUMENTED |
| 12 | Descript API and MCP | Editing agent | Underlord agentic endpoint, transcript export (txt/md/html/rtf/srt), edit summaries | Server-side; visual understanding not exposed | Cloud | Included with paid plans; draws media minutes and AI credits | DOCUMENTED |
| 13 | Spot AI | Security / operations | Open API (cameras, zones, counting/idle/presence events, LPR); claimed MCP endpoint | No VLM answers exposed in the verifiable API | Cloud plus edge IVR | Per location via channel partners (llms.txt, October 2026) | DOCUMENTED (vendor) / unverified MCP |
| 14 | Verkada Catalyst MCP | Security | Command org to Claude, ChatGPT and Gemini; tools unpublished | Unknown | Cloud | Private beta (October 2026) | DOCUMENTED (thin) |
| 15 | Meta V-JEPA 2.1 | World model / encoder | Dense spatio-temporal features; action-conditioned planning (2-AC) | Native video into an encoder; no text out | Local, MIT | Free | DOCUMENTED; GitHub MEASURED |
| 16 | Magnifi (VideoVerse / Minute Media) | Sports / broadcast | Partner REST API: key-moment clips, highlights, HMAC webhooks | Server-side | Cloud | Partner pricing | DOCUMENTED (stale) |

## Entries in detail

### 1. Jam MCP (Jam, Inc.): screen-recording bug reports for coding agents
- **Gives an agent**: 30 MCP tools. The ones for reading recordings are `getDetails`, `getConsoleLogs`,
  `getNetworkRequests`, `getUserEvents`, `getMetadata`, `getScreenshots`, `getVideoTranscript` (WebVTT, needs the
  microphone on), `getVideoChapters` (AI titled segments) and `getFrames`.
- **`getFrames` modes**:
  - overview grid: one labelled image of 6-16 evenly spaced frames, with a timestamp in each cell;
  - `at` in ms: frames at exact moments;
  - `fromMs`/`toMs`/`count`: N frames across a window.

  Each frame is preceded by a `t=<ms>` text anchor. Size is small, medium or large. It works only on videos hosted on
  Cloudflare Stream, and the video tools do not work on Instant Replay Jams.
- **Modality path**: frames reach Claude as images, alongside the transcript and telemetry. It is the same transcode
  our baseline uses, but the vendor runs it and aligns it to console and network events.
- **Claude fit**: remote HTTP MCP with OAuth, `claude mcp add jam --transport http https://mcp.jam.dev/mcp`; there is
  also a claude.ai connector. **Egress**: Jam says "Some MCP tools use Google's Gemini", so recording data goes to Google
  for those tools. Jam opts out of training and de-identifies data. The MCP mirrors existing Jam permissions.
- **Pricing (2026-10-24)**: Free $0 (30 Jams, 5 Recording Links, 5-min recordings, "Debug Jams via MCP"). Team
  $14/creator/mo billed yearly (15-min recordings, 200 AI summaries). Enterprise custom.
- **Spatial/motion**: no claims. The agent sees stills at chosen times, so motion is only what sampling catches
  (INFERRED).
- **Maturity**: an earlier third-party listing called it "BETA". The current docs list 30 tools and carry no date.
- **Evidence**: vendor claims only.
- URLs: https://jam.dev/docs/debug-a-jam/mcp , https://jam.dev/mcp , https://jam.dev/pricing

### 2. Replay MCP (Replay.io): time-travel debugging of a recorded browser session
- **Gives an agent**: tools in these groups:
  - source and console (browse and search code with execution annotations, console output, screenshots "at any
    moment");
  - inspection (variables, evaluate expressions, call stacks, virtual breakpoints and logpoints);
  - errors (uncaught exceptions, React crash unmounts);
  - network and localStorage;
  - React (component tree, render causes, wasted renders);
  - Playwright test steps;
  - performance profiling.
- **Modality path**: other. The recording is deterministic (DOM and JS runtime), not pixels, plus screenshots. The
  Chrome extension, the Replay Browser CLI, or `@replayio/playwright` in CI create it.
- **Claude fit**: `claude mcp add replay --transport http https://dispatch.replay.io/nut/mcp --header "Authorization: <key>"`.
  The key is needed only for team recordings. Optional skills: `npx skills add https://github.com/replayio/skills`.
  **Egress**: recordings live on Replay's cloud unless you buy the private cloud or on-prem tier.
- **Pricing (2026-10-24)**: the pricing page cards show Free $0 (25 credits), Starter $17/mo, Pro $170/mo, Private
  Cloud $1,000+/mo and On-Prem $5,000+/mo. The page's FAQ says Starter is $20 and Pro is $200. The page does not mention
  MCP, so it is unclear whether these plans cover the MCP product.
- **Spatial/motion**: not applicable. State replaces pixels.
- **Maturity**: the docs once called it "experimental". The `replayio/skills` repo was last pushed 2026-04-29
  (MEASURED), which is about 6 months old: **flag**.
- **Evidence**: vendor case study only (the "found a React bug faster than Dan Abramov" blog).
- URLs: https://docs.replay.io/basics/replay-mcp/overview , https://www.replay.io/pricing ,
  https://blog.replay.io/replay-time-travelogue:-how-replay-mcp-helped-find-a-react-bug-faster-than-dan-abramov-did

### 3. screenpipe (screenpipe, YC S26): local screen and audio memory over MCP
- **Gives an agent**: two MCP tools.
  - `search-content` returns OCR text, accessibility text, audio transcripts and input events. It filters by time, app,
    window and speaker. `include_frames=true` attaches base64 screenshots.
  - `export-video` takes a time range and an fps (default 1.0).
- **Modality path**: a server-side *local* text index (accessibility tree first, OCR as fallback, local transcription),
  with optional frames as images.
- **Claude fit**: `claude mcp add screenpipe -- npx -y screenpipe-mcp@latest` (stdio). **Privacy**: local by default.
  But PostHog analytics and Sentry crash reports are on by default. Cloud transcription, cloud AI and sync send data
  off the device, so turn analytics off in Settings > Privacy.
- **Licence**: source-available "Screenpipe Commercial License". Personal non-commercial use is free; commercial use
  needs a licence. The GitHub API reports `NOASSERTION`.
- **Maturity (MEASURED)**: repo `screenpipe/screenpipe` (renamed from `mediar-ai/screenpipe`), 22,048 stars, pushed
  2026-10-24, latest release `app-v2.7.116` on 2026-10-21. Very active.
- **Footprint (third-party listing)**: 5-10% CPU, 0.5-3 GB RAM, about 20 GB per month.
- **Spatial/motion**: none claimed.
- **Evidence**: vendor claims only.
- URLs: https://github.com/screenpipe/screenpipe , https://docs.screenpipe.com/mcp-server

### 4. Recall.ai: meeting-bot and desktop-recording API that returns raw meeting video
- **Gives an agent**: the agent's own code receives the media; there is no understanding layer.
  - Bots join Zoom, Meet, Teams and GoTo (Webex has no separate video).
  - Outputs: mixed video, separate audio per participant, and (beta, behind a workspace flag) participant-separated
    video-only files.
  - Real time over a websocket: `video_separate_png` gives base64 PNG frames at **360p, 2 fps** for each webcam and
    each screenshare. `video_separate_h264` gives typically 240-1280 px at 10-30 fps for screenshare.
  - Concurrent streams: 16 on Zoom and Meet, 9 on Teams.
- **Modality path**: raw frames and audio to your code. The agent samples the frames into Claude and sends the audio to
  ASR. 2 fps screenshare PNGs fit Claude's image route directly (INFERRED). At 360p, small on-screen text will be lost;
  our earlier finding was that legible text needs 1080p or more.
- **Claude fit**: the official Recall MCP (regional `https://<region>.recall.ai/mcp`, page updated 2026-10-18) has
  about 50 tools for bots, recordings, logs, calendars, webhooks and docs. It is read-only unless write scopes are
  granted. It is for *operating* Recall, not understanding the content. **Egress**: media goes to Recall's cloud.
- **Pricing**: $0.50 per recording hour pay-as-you-go, with no platform fee. The Desktop Recording SDK costs the same.
  Built-in transcription is $0.15/h. Storage is free for 7 days, then $0.05 per media-hour per 30 days. The Calendar
  API is free. (Blog dated 2026-03-10, updated 2026-09-14.)
- **Maturity**: Sacra estimates $31M ARR in January 2026, up 211% year on year (third-party estimate).
- **Spatial/motion**: none. It is capture infrastructure.
- **Evidence**: vendor documentation.
- URLs: https://recall.ai/blog/new-recall-ai-pricing-for-2026 ,
  https://docs.recall.ai/docs/how-to-get-separate-videos-per-participant-realtime ,
  https://docs.recall.ai/docs/participant-separated-video , https://docs.recall.ai/docs/mcp

### 5. Gemini Robotics-ER 2 (Google DeepMind): embodied-reasoning model with video moment finding
- **Gives an agent**:
  - spatial reasoning: points, boxes, object tracking across video, trajectory planning;
  - video understanding: moment finding, progress classification, success and failure detection on raw video streams;
  - instrument reading (10 instrument types);
  - task orchestration through function calling.

  `gemini-robotics-er-2-streaming-preview` uses the Live API for continuous audio and video.
- **Modality path**: native video and audio into the model. Input limit is 131,072 tokens, output limit 65,536. It
  "builds on Gemini 3.5 Flash".
- **Claude fit**: call it as a tool from Claude Code (CLI or MCP wrapper around the Gemini API). Claude orchestrates and
  ER 2 watches. **Egress**: video goes to Google.
- **Pricing (2026-10-24)**: paid $1.00/M input (text, image, video, audio) and $5.00/M output until 2026-12-31, then
  $2.00/$10.00 from 2027-01-01. A free tier exists. ER 1.6 was deprecated on 2026-08-31.
- **Spatial/motion claims**: moment finding 91.3% with 0.96 s mean absolute error, progress classification 57.4%,
  "4x the execution speed". These are Google's numbers; no independent replication found. It is still the strongest
  documented temporal and motion claim available to an agent.
- **Maturity**: preview, announced 2026-07-30, available in AI Studio and the Gemini API.
- URLs: https://ai.google.dev/gemini-api/docs/robotics-overview , https://ai.google.dev/gemini-api/docs/pricing ,
  https://blog.google/innovation-and-ai/models-and-research/google-deepmind/gemini-robotics-er-2/

### 6. NVIDIA Cosmos 3 Reasoner (Cosmos3-Nano 16B, Super 65B, Edge 4B): open physical-AI video reasoner, replacing Cosmos Reason 2
- **Gives an agent**: text answers with chain of thought, 2D/3D point localisation and boxes. It covers physical
  reasoning, task planning, action forecasting and embodied reasoning.
- **Architecture**: Cosmos 3 is an "omnimodal" mixture-of-transformers. On Nano, an 8B autoregressive Reasoner sits
  beside an 8B diffusion Generator. Audio belongs to the generation side.
- **Modality path**: native video into the model, mp4 at a recommended 4 fps, 256K context. The Reasoner takes text,
  image or video; no audio input is documented.
- **Deployment**: local through `vllm-cosmos3` (vLLM 0.21 with CUDA 13). Tested on H100 and GB200; the vLLM-Omni example
  recommends H200. Weights are BF16. build.nvidia.com hosts "Cosmos3-Reasoner" NIM 1.7.0 as a trial (2026-05-31).
- **Licence**: OpenMDW-1.1, commercial use allowed.
- **Claude fit**: run it as a local tool (OpenAI-compatible vLLM endpoint behind an MCP or CLI) that Claude calls with a
  clip and a question. **Privacy**: fully local is possible, but it needs a datacentre-class GPU (INFERRED from the
  test hardware).
- **Maturity**:
  - Released 2026-05-31; paper arXiv 2606.02800 (v4, 2026-06-23).
  - Hugging Face card text dated Sep 16: Nano about 124k, Edge about 106k, Super about 64k (assumed to be downloads).
  - `nvidia/cosmos` has 12,124 stars, pushed 2026-10-21 (MEASURED).
  - Predecessor Cosmos Reason 2 (2B/8B/32B on Qwen3-VL, NVIDIA Open Model License, 8B card updated 2026-03-10, 83k
    downloads last month): `nvidia-cosmos/cosmos-reason2` has 457 stars, pushed 2026-06-07 (MEASURED).
- **Evidence**: vendor benchmarks only.
  - Reason2-8B vs its Qwen3-VL-8B base: Self-Driving 67.85 vs 46.38, Smart Spaces 69.96 vs 42.66, BlinkSpatial
    84.62 vs 87.41 (here the base wins).
  - The Cosmos 3 paper, run by NVIDIA, puts Reason2-32B above Gemini 3.1 Pro on VideoPhy2 (43.3 vs 28.7) and below it on
    MMBench and RealWorldQA.
  - An aggregator lists Reason2-32B first on Physical AI Bench at 70.8 (2026-05-06). Not verified at the source.
- URLs: https://huggingface.co/nvidia/Cosmos3-Nano , https://arxiv.org/abs/2606.02800 ,
  https://build.nvidia.com/nvidia/cosmos-reason2-8b/modelcard , https://huggingface.co/nvidia/Cosmos-Reason2-8B

### 7. NVIDIA Metropolis VSS 3.x blueprint: self-hosted agentic video search and summarisation (security, smart city, warehouse)
- **Gives an agent**:
  - natural-language search over video, long-video summarisation (dense captions, chunked and aggregated), visual Q&A,
    alert verification, snapshot and clip retrieval;
  - Video Analytics MCP with tools `get_incident`, `get_incidents`, `get_sensor_ids`, `get_places`,
    `get_fov_histogram`, `get_average_speeds` and `analyze` (Elasticsearch-backed, at `http://localhost:9901/mcp`);
  - agentskills.io-compatible `skills/` for deploying and operating it, plus OpenClaw and Hermes harnesses.
- **Modality path**: VLM over chunked video (Cosmos3 Nano Reasoner) plus embeddings. The LLM is Nemotron 3.5 Lightning
  30B-A3B. Audio is not mentioned.
- **Deployment**: self-hosted on GPUs. Docker Compose on Ubuntu 24.04 needs driver 595.58.03 and Docker 28.3.3 up to
  (not including) 29.5.0. The Launchable example uses 2x RTX PRO 6000. Self-hosting the NIMs needs an NVIDIA AI
  Enterprise developer licence. NVIDIA's docs say to deploy it on a trusted, isolated network.
- **Claude fit**: Claude Code can drive the shipped skills and connect to VA-MCP. Video stays on your hardware.
- **Maturity**: VSS 3 announced at GTC on 2026-03-17 and GA in June 2026; docs at 3.3.0. Repo has 1,941 stars, pushed
  2026-10-24, Apache-2.0 (MEASURED).
- **Spatial/motion**: "agentic search for detecting actions and temporal events", FOV histograms, average speeds
  (DOCUMENTED; the speeds come from the CV pipeline, not the VLM, INFERRED).
- **Evidence**: vendor claims only.
- URLs: https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization ,
  https://docs.nvidia.com/vss/3.2.0/video-analytics-mcp.html ,
  https://forums.developer.nvidia.com/t/nvidia-vision-ai-at-nvidia-gtc-san-jose-2026-announcements/363762

### 8. GUIDE benchmark (Google Research, CVPR 2026): independent evidence for screen-recording understanding
- **What it is**: 67.5 h of screen recordings from 120 novice demonstrations across 10 apps (including PowerPoint and
  Photoshop). Tasks: behavior state, intent, help need, help content. 32 uniformly sampled frames per segment, no
  audio, zero-shot.
- **Results (Table 2, accuracy %)**:
  - Claude-4.5-Sonnet: behavior 44.61, intent 71.39, help need 39.49, help content 55.00.
  - Gemini-2.5-Pro: 42.44 / 67.80 / 69.82 / 52.74.
  - GPT-4o: 36.32 / 61.19 / 49.69 / 45.95.
  - Qwen3-VL-8B: 37.97 / 62.70 / 52.83 / 46.06.
  - InternVideo2.5-8B: 21.57 / 43.79 / 34.36 / 23.67.
  - With behavior and intent context, help need reaches 87.91 for GPT-4o and 59.43 for Claude-4.5-Sonnet; help content
    reaches 82.79 for Claude.
  - No human baseline.
- **Why it matters**: it is the only independent test found of the exact route Claude uses (sampled frames). Claude does
  well on reading state and intent from frames and is weak on help need. Context from telemetry beats model choice.
- URLs: https://arxiv.org/abs/2603.25864 , https://guide-bench.github.io ,
  https://research.google/pubs/guide-a-benchmark-for-user-context-understanding-and-assistance-in-gui-workflow-videos/

### 9. PostHog session-replay MCP and Replay Vision
- **Gives an agent**: the MCP searches recordings by events, person properties, rage and dead clicks, and time. It
  reads recording metadata (duration, interaction and console counts, person summary), lists and fetches session
  summaries, manages playlists, and can delete recordings (permanently). Replay Vision (closed beta) lets you define
  "scanners" that run over recordings and produce observations: a typed answer, a key moment, and a "worth watching"
  judgement. These are queryable as `$recording_observed` events. PostHog marketing says an agent can create and run a
  scanner through the MCP.
- **Modality path**: Vision renders the DOM replay to a sped-up video with idle periods trimmed and sends it, with
  nearby events and failed or slow requests, to an unnamed Gemini model. The MCP returns text.
- **Claude fit**: PostHog MCP works in Claude Code. **Egress**: session data goes to PostHog and then Google.
- **Pricing**: cost per observation is set by the scanner's model. A marketing page says 2,500 credits a month are free
  (500 standard observations); undated.
- **Evidence**: vendor claims only.
- URLs: https://posthog.com/docs/session-replay/surfaces/mcp , https://posthog.com/docs/replay-vision

### 10. Meeting-notetaker MCPs: Fireflies, Fathom, Granola, Otter (transcript only)
- **Fireflies**: official `https://api.fireflies.ai/mcp`, tools `get_user`, `get_transcript`, `get_transcripts`. Needs a
  paid Claude plan. The help page says "last updated 11 months ago" (**flag: older than 6 months**). Listed in the
  Claude directory since August 2025.
- **Fathom**: official `https://api.fathom.ai/mcp`. A third-party review (August 2026) counted 9 read-only tools on all
  tiers including free; search covers titles and summaries, and full transcripts are fetched by ID.
- **Granola**: official `https://mcp.granola.ai/mcp`, launched 2026-02-04. Basic plan gets 30 days of notes and no
  transcripts; paid plans get full history and transcripts. On Enterprise it is off by default.
- **Otter**: an MCP and Claude connector exist per a competitor (Sonix); the tool list was not verified.
- **Modality path**: server-side ASR and summary text. None exposes video or frames. Meeting *visuals* (slides, screen
  share) are not available to Claude through these.
- **Egress**: meeting content goes to Anthropic under the connector terms.
- URLs: https://guide.fireflies.ai/articles/8272956938-learn-about-the-fireflies-mcp-server-model-context-protocol ,
  https://developers.fathom.ai/mcp-docs , https://www.granola.ai/blog/granola-mcp

### 11. Loom tools in the Atlassian Rovo MCP server (v2)
- **Gives an agent**: read (`read_loom`) covers video lists, metadata, transcripts and AI meeting action items. Write
  (`write_loom`) covers timestamped comments, reactions, sharing, folders, permissions, and upload and publish.
- **Modality path**: a text transcript, plus whatever AI summaries Loom produces. No frames are documented.
- **Claude fit**: remote MCP at `https://mcp.atlassian.com/v2/mcp` (directory-sourced), OAuth. Calls use Rovo credits.
  The Loom workspace must be linked to an Atlassian Cloud site. v1 users migrate automatically on 2027-03-01.
- **Maturity**: per a directory, part of the Rovo MCP v2 preview announced on 2026-08-11. Docs now call v2 released.
- URLs: https://support.atlassian.com/loom/docs/loom-mcp-tools/

### 12. Descript API (beta) and Descript MCP: Underlord editing agent behind one endpoint
- **Gives an agent**:
  - import from a URL or a file, with automatic transcription;
  - Underlord edits from a natural-language goal (captions, filler-word removal, Studio Sound, scenes, highlight
    reels);
  - transcript export (txt, md, html, rtf, srt; DOCX only through the API);
  - publish to a signed URL, job tracking, and a readable summary of what changed.
- **Modality path**: Underlord understands the media server-side. Only transcripts and edit summaries come back.
  Descript's own blog says chat interfaces cannot show video and the MCP hands visual editing back to the UI.
- **Claude fit**: listed in the Claude connector directory. In Claude Code it is added as a custom MCP URL, with OAuth
  scoped to one Drive. **Egress**: media goes to Descript.
- **Pricing**: no extra charge for paying users; imports use media minutes and edits use AI credits (HTTP 402 when they
  run out). Rates not fetched.
- **Maturity**: API in beta. The design post was updated 2026-06-23.
- **Evidence**: vendor claims only.
- URLs: https://help.descript.com/api-and-mcp/api , https://help.descript.com/api-and-mcp/mcp ,
  https://www.descript.com/blog/article/dont-ship-your-api-as-an-mcp

### 13. Spot AI: camera-agnostic video AI agents with an open API
- **Gives an agent**: per the community `spot-ai-mcp` (PyPI; not affiliated with Spot AI): `list_cameras`, `get_zones`,
  `get_intelligence` (counting, idle and presence events for people, vehicles and forklifts), `get_lpr_report`,
  `get_live_stream_urls`, and `spot_api_get` for any `/v1/` or `/v2/` path. Base URL `dev-api.spot.ai`, bearer key.
  Spot AI's compare page (updated 2026-07-22) says it "exposes open APIs, webhooks, and a live Model Context Protocol
  endpoint". No official MCP documentation was found.
- **Modality path**: server-side CV events. Iris (natural-language "what did the cameras see") is not documented as
  callable through the API.
- **Pricing**: per location, through channel partners.
- **Maturity**: about $93M raised (tracker); claims more than 1,000 customers.
- **Evidence**: vendor claims only.
- URLs: https://www.spot.ai/compare/spot-ai-vs-axis-communications , https://pypi.org/project/spot-ai-mcp ,
  https://www.spot.ai/llms.txt

### 14. Verkada Catalyst MCP
- **Status**: announced in the October 2026 product updates (rollout 2026-10-08). It connects a Command org to Claude,
  ChatGPT and Gemini for "custom workflows, reports, and integrations". **Private beta**; no tools published, and no
  statement that it exposes video search.
- URL: https://www.verkada.com/updates/october-2026-product-updates/

### 15. Meta V-JEPA 2 / 2.1 / 2-AC: self-supervised video world model (primitive)
- **Gives an agent**: nothing it can query in text. These are encoders (V-JEPA 2.1: ViT-B to ViT-G at 384 px) and probes
  (SSv2, Diving48, EPIC-KITCHENS). V-JEPA 2-AC is an action-conditioned planner for robot arms. Useful as a motion and
  dense-feature backbone behind a custom tool.
- **Reported results (2.1 paper, arXiv 2603.14482)**: Ego4D short-term anticipation 7.71 mAP, EPIC-KITCHENS action
  anticipation 40.8 R@5, SSv2 77.7, and a 20-point gain in real-robot grasp success over 2-AC. Paper results; not
  independently replicated.
- **Maturity (MEASURED)**: 4,808 stars, MIT, last push 2026-03-23, about 7 months ago: **flag**.
- URLs: https://github.com/facebookresearch/vjepa2 , https://arxiv.org/abs/2603.14482

### 16. Magnifi (VideoVerse, acquired by Minute Media in 2025): sports key-moment detection API
- **Gives an agent**: a partner REST API for stream ingestion (HLS, RTMP, SRT, MP4), key-moment clips and highlights,
  match-video export, roster and schedule management, and HMAC-signed webhooks. Detection uses visual, audio and text
  cues.
- **Access**: partner documentation only.
- **Freshness**: the newest primary evidence is 2025 (acquisition, September 2025): **flag, older than 6 months**.
- URLs: https://apis.io/providers/videoverse/ , https://magnifi.ai/partners

## Excluded, or not exposed to agents

- **Ambient.ai Pulsar**: an edge VLM for physical security. The vendor claims it beats GPT-5 and Gemini 2.5 Pro "at 50x
  efficiency", with no method given. There is no developer API; there is a public playground at playground.ambient.ai.
  The newest primary source is 2025-11-19, older than 6 months.
- **WSC Sports**: no public API found. Enterprise highlight automation only.
- **Runway (Aleph 2.0, hosted MCP from May 2026, Dev MCP from 2026-09-02)**: generation and editing only; no
  understanding output.
- **Captions / Mirage API**: captioning and generation, not understanding.
- **OpusClip API**: early access as of May 2026; clipping.
- **Coram, Lumana, Conntour, Eagle Eye Smart Video Search**: natural-language video search inside their own products;
  no agent API or MCP found. Eagle Eye's feature dates from 2022.
- **Google Genie / RT-series**: not searched in depth this pass. Genie is a world *generator* and RT is research. No
  understanding API is known (INFERRED, unverified).
- **OpenAI Codex "Record and Replay"**: observes desktop activity for OpenAI's own agent; not usable from Claude.

## Concerns and deviations

- Several tool lists come from vendor docs fetched through a summarising fetcher. Exact tool names should be checked
  against a live `tools/list` before building.
- I did not verify Otter's MCP tools, Fathom's tool count, the Spot AI official MCP, or any Rovo credit rates.
- Replay's pricing page may describe a different Replay product line: its credits model and its "design partner" home
  page do not mention MCP.
