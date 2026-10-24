# F1: What Claude Opus 5.5 can take in (as of 2026-10-23), compared with Gemini, GPT and Qwen-VL

Labels: **MEASURED** means we ran it this session. **DOCUMENTED** means a vendor doc or the bundled claude-api skill says it. **INFERRED** means a reading of minified code or a deduction.

## Verdict

Claude Opus 5.5 has **no native video input and no native audio input**, either through the Claude API or through Claude Code. The inputs it accepts are text, images (JPEG/PNG/GIF/WebP; for GIF, only the first frame is used), and documents (PDF and plain text). To "watch" a video, Opus 5.5 has to work from stills taken from the video plus a transcript of its audio. Those stills and that transcript are produced by tools such as ffmpeg and Whisper, either in Claude Code or in the API's code-execution container.

Among the main vendors, only Gemini takes video natively, interleaved with audio, and it still samples at 1 fps by default. Qwen3-VL (open weights) takes video natively, defaults to 2 fps, and does not process audio. GPT-6 Astra (OpenAI's current flagship) has no video input.

## 1. Claude API: input modalities for `claude-opus-5-5`

| Claim | Label | Source |
|---|---|---|
| "All current models support text and image input, text output, multilingual capabilities, vision, and tool use." The page never mentions audio or video input. | DOCUMENTED | https://platform.claude.com/docs/en/about-claude/models/overview (Compare models para) |
| The user `content` block types are `text`, `image`, `document`, `search_result`, `thinking`, `redacted_thinking`, `tool_use`, `tool_result`, the server-tool result blocks, and `container_upload`. There is **no audio or video block** and no `audio/*` or `video/*` media type. | DOCUMENTED (the fetch read the first 100K of 142K characters) | https://platform.claude.com/docs/en/api/messages/create |
| Image media types: `image/jpeg`, `image/png`, `image/gif`, `image/webp`. "Animations are unsupported, and only the first frame is used." | DOCUMENTED | https://platform.claude.com/docs/en/build-with-claude/vision (Supported formats) |
| Document media types: `application/pdf` and `text/plain`. | DOCUMENTED | messages/create (as above) |
| Opus 5.5 specs: 1M context, 128K max output, adaptive thinking that is always on, default effort `medium`. | DOCUMENTED | models/overview table |

**Quoting the docs on video and audio:** the Vision page and the models overview say nothing at all about video or audio input. The only statement of input modalities is "text and image input". The one place the claude-api skill mentions video is to recommend an agent workaround: "For complex inputs - dense charts, filings, tables nested in PDFs, video - run it as an agent with a container that holds the raw images/videos and basic image-processing libraries (PIL, OpenCV) preinstalled" (claude-api skill `shared/model-migration.md:1840`, DOCUMENTED). That guidance is written for Fable 5.1. The Opus 5.5 version is the same advice without the word video (`shared/model-migration.md:2057`).

### 1a. Image limits (API)

| Limit | Value | Label | Source |
|---|---|---|---|
| Images per request | 600 (models with 1M context, which includes Opus 5.5); 100 for 200K-context models; 20 per message on claude.ai | DOCUMENTED | vision page, Request limits |
| Maximum input dimensions | 8000x8000 px | DOCUMENTED | as above |
| Requests with more than 20 images | A stricter per-image dimension limit applies. Images over it get `invalid_request_error` ("many-image requests"). To stay safe, keep each side at or under 2000 px, or send 20 or fewer image/document blocks. Images inside `tool_result` and images resent from earlier turns count toward the 20. | DOCUMENTED | as above |
| Per-image size | 10 MB base64 (Claude API and Google Cloud); 5 MB on Bedrock | DOCUMENTED | as above |
| Request size | 32 MB on standard endpoints | DOCUMENTED | as above |
| Native resolution for Opus 5.5 | "High-resolution" tier (Claude 4.7 and later): **2,576 px long edge, 4,784 visual tokens maximum**. Larger images are downscaled with aspect ratio kept. | DOCUMENTED | vision page, Resolution and token cost table |
| Token formula | `ceil(w/28) x ceil(h/28)` visual tokens (28x28 patches) | DOCUMENTED | as above |
| Example costs | 1920x1080 is 2,691 tokens unresized; 3840x2160 is downscaled to 2576x1449, 4,784 tokens. At $4/MTok a 4K frame costs about $19.14 per thousand. | DOCUMENTED (we recomputed 1920x1080 = 2,691: MEASURED arithmetic) | as above |

**What this means for video (INFERRED):** at 600 frames per request, 1080p frames (2,691 tokens each) come to about 1.6M tokens, which is over the 1M context window. Any request with more than 20 frames also has to keep each side at or under 2000 px. The practical ceiling for one request is therefore a few hundred mid-resolution frames. A 1-hour video sampled at 1 fps (3,600 frames) cannot go into a single request.

### 1b. PDF (API)

| Limit | Value | Label | Source |
|---|---|---|---|
| Pages per request | 600 (100 when the request's context window is under 1M) | DOCUMENTED | https://platform.claude.com/docs/en/build-with-claude/pdf-support (Check PDF requirements) |
| Request size | 32 MB | DOCUMENTED | as above |
| Processing | "each page is converted into an image" plus extracted text, at 1,500-3,000 text tokens per page plus image tokens | DOCUMENTED | as above (Estimate your costs) |

### 1c. Audio

No audio content block exists (messages/create, DOCUMENTED). The Claude API offers no speech-to-text endpoint. Transcription has to happen outside the model, with Whisper or another ASR, before the text is sent (INFERRED from the absence of any such endpoint). The skill does mention audio and video *outputs* produced inside the code-execution sandbox, which carry C2PA credentials (`shared/model-migration.md:1690`). Those are files the sandbox creates, not media the model perceives.

## 2. Claude Code: what happens to the images it Reads

| Claim | Label | Source |
|---|---|---|
| The Read tool returns PNG/JPEG/GIF/WebP "as visual content… Claude Code resizes and recompresses large images to fit the model's image size limits… Claude may see a downscaled version". It refuses image files over 128 MB. | DOCUMENTED | https://code.claude.com/docs/en/tools-reference (Read tool behavior) |
| **A 4000x2000 PNG Read in this session arrived as 2000x1000.** The harness annotation said: "original 4000x2000, displayed at 2000x1000". Test file: `/tmp/f1-imgtest/probe-4000x2000.png`, made with `magick -size 4000x2000 gradient:red-blue`. | **MEASURED** (Claude Code 2.1.293, model claude-opus-5-5) | this session |
| Claude Code's model registry sets `claude-opus-5-5` to `image_limits:{maxWidth:2000,maxHeight:2000}`. The default object is `{maxWidth:2000,maxHeight:2000,maxBase64Size:5242880,targetRawSize:3932160}`, i.e. 2000 px per side and 5 MiB base64. A feature gate (`tengu_crimson_vector`, first-party only) can raise the base64 cap to 10 MiB. | MEASURED (`strings` on `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, v2.1.293; the same values are in v2.1.291 at `/opt/homebrew/...`) | binary strings: `var h0={maxWidth:2000,...}`, function `Uc()` |
| So Claude Code **gives up resolution compared with the API**. A 2000x1000 image costs 72x36 = **2,592 visual tokens**. The API's own Opus 5.5 ceiling is 2576x1288 = 4,232 tokens for the same 2:1 frame. The 2000 px cap matches the API's many-image limit, so long, image-heavy sessions never hit that 400 error. | MEASURED (arithmetic) / INFERRED (rationale) | above, plus the vision page many-image rule |
| A second, snake_case model-selector config in the same binary lists Opus 5.5 at `max_width:2576, max_image_tokens:4784`. The Read path did not use it in our test (2000 px observed). | MEASURED (strings) / INFERRED (which path uses it) | binary strings |
| **Limit on images per conversation:** before each API call Claude Code keeps at most `min(600 or 100, mediaItemLimit)` media items. 600 applies to 1M-context models, 100 to others. When the count goes over, it strips the oldest down to the limit minus 20 and puts a placeholder where each one was. A separate byte cap, `tengu_media_byte_cap`, defaults to 75 MiB, or 24 MiB on some providers, and also strips the oldest media. | INFERRED from minified code (`yon(Ze,Math.min(w?Cbs:kbs,…),e_o,Lfr(),xbs)` with `Cbs=600,kbs=100,e_o=20,Tbs=78643200,Rbs=k3e-8388608`) | binary strings, v2.1.293 |
| Error text in the binary: "An image in the conversation exceeds the dimension limit for many-image requests (2000px). Run /compact to remove old images from context, or start a new session." | MEASURED (strings) | binary |
| PDFs: read whole up to 10 pages. Beyond that, the `pages` parameter is required, at most 20 pages per read, rendered with `pdftoppm`. The binary also carries "PDF too large (max 100 pages, 20MB)" (`Ebs=100`, `RPt=20971520`). | DOCUMENTED (tools-reference) + MEASURED (strings `xPt=10`, `IJ=20`) | as cited |
| Capability flags in the binary are only `mm_images` and `mm_pdf`. There is **no `mm_video` or `mm_audio`**. Read classifies `.mp4/.mov/.mkv/.mp3/.m4a` as binary extensions it refuses. | MEASURED (strings) | binary |

## 3. Comparison: native video elsewhere

| Model / vendor | Native video? | Sampling | Audio | Max length / count | Label + source |
|---|---|---|---|---|---|
| **Gemini** (docs name Gemini 2.5, 3, 3.5 Flash Lite, 3.6 Flash, 3.8 Flash, "Gemini 4 Argon") | Yes: mp4, mpeg, mov, avi, flv, mpg, webm, wmv, 3gpp; public YouTube URLs | **1 fps by default** (static mode). `fps` and clipping (`start_offset`/`end_offset`) are set in a `processing` object. Frames cost 258 tokens, or 66 at low media resolution. Timestamps every second (MM:SS). | Yes, interleaved: 1 Kbps mono at 32 tokens/s. That is about 300 tokens per second of video at high resolution, about 100 at low. | 1M context: about 3 h at low resolution, 1 h at high. Up to 10 videos per request (2.5+). Files API up to 20 GB paid / 2 GB free. | DOCUMENTED https://ai.google.dev/gemini-api/docs/video-understanding |
| Gemini **agentic mode** (`"processing": "agentic"`) | Yes. "dynamically navigates the video timeline, loading only the content it needs": transcript first, then segments and audio on demand, adapting frame rate and resolution | On demand | On demand | Claims up to 88% fewer tokens on long video. Models: Gemini 4 Argon, 3.8 Flash, 3.6 Flash, 3.5 Flash Lite. The docs warn "fast action sequences might lose detail due to the 1 FPS sampling rate". | DOCUMENTED (same page). Press coverage of the 2026-09-02 rollout: https://androidauthority.com/gemini-agentic-video-understanding-3705876 |
| **OpenAI GPT-6 Astra** (flagship, per developers.openai.com) | **No.** "All latest OpenAI models support text and image input". No model lists video input, and the vision guide never mentions video. | n/a (convert to frames as images; up to 1,500 images per request, 512 MB payload) | Audio only through the realtime / transcribe models (GPT-Realtime-2.1, GPT-Live 1, GPT-Transcribe) | n/a | DOCUMENTED https://developers.openai.com/api/docs/models ; https://developers.openai.com/api/docs/guides/images-vision . One May 2026 blog post claims 60 s video clips for GPT-5. No OpenAI doc backs it, so it is treated as unverified. |
| **Qwen3-VL** (open weights: 2B/4B/8B/32B dense, 30B-A3B and 235B-A22B MoE) | Yes | **fps=2 by default**, or `num_frames`. Each video gets 256-16,384 visual tokens (32x spatial, 2x temporal compression). Text-timestamp alignment and Interleaved-MRoPE. | **No**: the VL page never mentions audio. Audio needs the Omni line. | Native 256K context, 1M with YaRN. The page claims "hours-long video with full recall and second-level indexing". | DOCUMENTED https://github.com/QwenLM/Qwen3-VL |
| Qwen3.5-Omni (hosted, Alibaba Model Studio) | Yes, with audio | not confirmed | Yes | About 1 h / 2 GB per video (hosted listing). Qwen3.5-3.7 VL: 2 h / 2 GB. | DOCUMENTED, but only from search snippets: https://www.alibabacloud.com/help/en/model-studio/vision-model/ (not fetched directly; low confidence) |
| Qwen3-VL-4B-4bit run locally (mlx-vlm 0.6.7) | Yes | 4-12 fps tested | No | Read on-screen text correctly. **Called real motion "not moving"** on 2 of 2 motion probes. | **MEASURED** previously: `docs/research/agent-video-understanding-2026-07-26.md:223-242` |

## 4. Corrections to our own prior research

- `agent-video-understanding-2026-07-26.md:74` says a single frame is read at "1568px". That is stale. The API ceiling for Opus 5.5 is 2576 px (DOCUMENTED, vision page), and Claude Code caps Reads at 2000 px (MEASURED above).
- The same doc at `:179-180` says Gemini fps is set "via `videoMetadata`". The current Gemini doc puts `fps` in a `processing` object (static mode only) and adds an agentic mode (DOCUMENTED). That doc's "1 fps by default, 258 tokens/frame" figure still holds.
- That doc's `:17` claim ("no native video input and no native audio input") **still holds for Opus 5.5** as of 2026-10-23 (DOCUMENTED + MEASURED above).

## 5. What this means for the "watch like a human" question (INFERRED)

1. Opus 5.5 never sees continuous motion or hears audio. Whatever it perceives depends on how the video is sampled and transcribed. In Claude Code each frame is capped at 2000 px, and a conversation holds at most about 600 media items before the oldest are stripped.
2. Spatial detail per frame is strong at 2000-2576 px, with a crop/zoom loop recommended (`model-migration.md:2057`, `:2209`). Temporal understanding is limited by the frame budget: 600 frames per request, a 1M-token context, and 2,592 tokens per 2000x1000 frame comes to about 385 frames per 1M tokens.
3. Gemini is the only frontier option with native video and audio, but it also samples at 1 fps, and its own docs warn about losing fast action. On the motion axis, no vendor's native path "watches like a human". Motion has to be measured with tools such as optical flow or slit-scan, as the prior doc found (`agent-video-understanding-2026-07-26.md:172-221`).
