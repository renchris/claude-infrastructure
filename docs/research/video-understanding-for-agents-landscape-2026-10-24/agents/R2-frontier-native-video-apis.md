# R2: Frontier closed models that take video natively through an API (as of 2026-10-24)

Axis: closed frontier models you can hand a video file or URL and get text back. This covers Google Gemini (3.x, 4 Argon,
Live, Robotics-ER), OpenAI, Amazon Nova, Meta (Muse; Llama is superseded), xAI Grok, Mistral, ByteDance Seed, Alibaba Qwen
(VL and Omni), and two native-video specialists (Perceptron, Meta SAM 3.1) that turned up along the way.

Labels: **MEASURED** means I ran the named command this session. **DOCUMENTED** means a vendor page, model card or
third-party page says it; vendor claims are marked "vendor". **INFERRED** means my own reasoning. All dollar figures
per video-hour are **ESTIMATED** by arithmetic (`python3 -I -c ...`, this session) from the documented token rates and
list prices, and each one names its inputs. Nothing was installed, no account was created, nothing was uploaded.
Scratch copies of fetched pages are in `/tmp/r2-fetch/`, which will not survive a reboot; the URL is the citation of record.

## 0. What this extends (vs F1/F3 of 2026-10-23)

Our agent, Opus 5.5 in Claude Code, has no video or audio input. Gemini is the cheapest cloud route, and its agentic
mode was already known (F1 §3, F3 §3). New in this pass:

1. **Google's Argon eval puts a number on Opus 5.5 working from frames.** On LVBench (hour-long video, no tools,
   Google's own run) the scores are: Gemini 4 Argon **91.7** at 1 fps, GPT-6 Astra **87.5** on 800 frames, Claude
   **Opus 5.5 83.7 on 600 frames**, and Claude Fable 5.1 79.7 on 300 frames. The frame counts were chosen "due to API
   limitations". Human is 94.4 (F2). Source: the Argon model card PDF p.5 and the evals-methodology PDF (MEASURED
   retrieval with `pdftotext` and `pdftoppm`; DOCUMENTED, vendor-run). F3 said "No video benchmark published" for Argon.
   That is now wrong: the benchmark sits in the model card's table image, not in the blog post.
2. **The docs disagree on whether Argon has agentic video.** The AI Studio video doc, updated 2026-10-13, lists agentic
   mode for 3.8 Flash, 3.6 Flash and 3.5 Flash-Lite only (MEASURED: `curl …/video-understanding.md.txt`, lines
   617 and 625). The Vertex doc (2026-10-22) and the Argon model page both list Argon. On Vertex it needs `v1beta1` and
   `media_processing="AGENTIC"`.
3. **Meta is now a native video+audio vendor.** Muse Spark 1.1-1.3 and Muse Wonder (2026-10-12) take mp4 and read the
   embedded audio, through OpenAI-compatible Responses and Chat endpoints. Meta also exposes hosted SAM 3.1 video
   tracking at $0.20 per 1,000 frames. Llama is no longer Meta's frontier line.
4. **Qwen's and Seed's hosted APIs cap tokens per video**, so a long video is silently downscaled hard. Qwen VL models
   allow at most about 32K tokens per video (about 65K on qwen3-vl-plus). Seed allows 80K by default, which falls to
   64 tokens per frame at the 1,280-frame cap. Both are INFERRED from the vendors' own token calculators. That makes
   them very cheap and very low-resolution on hour-long input.
5. **OpenAI, xAI and Mistral still have no video input** (DOCUMENTED, primary docs). OpenAI's realtime models do take
   *image* input, so a frame-push loop is possible.

## 1. Comparison table (ranked by importance to an agent builder)

| # | Model / API | Native video in? | Audio track used? | Default sampling / control | Max per request | Price basis (date) | Est. $ per video-hour (input only) | Spatial/motion claim | Label |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Gemini 3.8 Flash** (`gemini-3.8-flash`, 2026-09-02) | Yes: file, Files API, GCS, public YouTube URL | Yes, interleaved, 32 tok/s | 1 fps static; `processing.fps`, `start/end_offset`; `media_resolution`; **agentic** mode | 1M ctx: about 3 h at low res, 1 h at high; 10 videos (2.5+); Files API 20 GB paid | $0.75/M in until 2026-12-31, then $1.50 (pricing page 2026-10-22) | **$0.27** low / $0.81 high; $0.54 / $1.62 from 2027-01-01 | Docs warn 1 fps "may miss details in videos with rapid motion" | DOCUMENTED |
| 2 | **Gemini 4 Argon** (`gemini-4-argon`, GA 2026-10-13) | Yes (same API) | Yes | Same; agentic per model page and Vertex | 1,048,576 ctx; 65K out | $2/M in until 2026-11-30, then $4; paid only | **$0.72** low / $2.16 high; $1.44 / $4.32 from 2026-12-01 | LVBench 91.7 (vendor-run); ERQA 87 (spatial, image) | DOCUMENTED (vendor) |
| 3 | **Gemini 3.5 Flash-Lite** / 2.5 Flash-Lite | Yes | Yes | Same; 3.5 FL has agentic | 1M ctx | 3.5 FL $0.30/M all modalities; 2.5 FL $0.10 video + $0.30 audio | **$0.11** low (3.5 FL); **$0.06** low (2.5 FL, released 2025-07, >6 mo old) | none beyond the above | DOCUMENTED |
| 4 | **Qwen3.8-Omni-Flash** (Alibaba Model Studio, 2026-09-18/20) | Yes: video file or image list | **Yes**: "supports audio in the video", billed separately | 2 fps; "stable" up to 15 fps; at most 2,048 frames | 2 h / 2 GB per video; 1M ctx | $0.15/M in (Intl), $0.113 (CN) (2026-10-22) | **about $0.03** (ESTIMATED: video ≤90K tok cap + audio at an *assumed* 25 tok/s) | Vendor: agentic +4.4 OmniVideoBench, +6.3 Video-MME-v2 vs static | DOCUMENTED (vendor) |
| 5 | **Seed 2.1 Pro / Turbo** (ByteDance, BytePlus ModelArk / Volcengine) | Yes: Files API (512 MB, 2 GB with TOS), URL or base64 ≤50 MB | "Some models" read audio in video | 1 fps default, 0.2-5; 16-1,280 frames; 64-384 tok/frame; **80K tok/video cap**; timestamp text before each frame | 256K ctx | Turbo $0.50/M (OpenRouter, 2026-08); Pro price only from an aggregator | **about $0.04** (Turbo, 80K-token cap) | Vendor: TOMATO 79.5, VideoMME 89.2, "temporal changes, actions, physical motion" | DOCUMENTED (vendor) |
| 6 | **Meta Muse Spark 1.3 / Muse Wonder** (Meta Model API; Wonder 2026-10-12, preview) | Yes: mp4 via Files API (1 GiB) or `input_video` URL (50 MB inline) | **Yes**, embedded audio transcribed (1.3 audio "may be degraded": use 1.2) | Not documented | 1,048,576 ctx | Spark $1.25/M in (Contributor mode $0.10, trains on data); Wonder $4/M | Not computable (no tokens-per-second doc) | Model card: "Visual and spatial reasoning, especially 3D tasks, remains a known limitation" | DOCUMENTED |
| 7 | **Qwen VL-capable API models** (qwen3.8-max/flash, 3.7/3.6/3.5, qwen3-vl-plus) | Yes | **No**: "does not support understanding the audio track" | 2 fps (0.1-10); `max_frames`; at most 2,000 frames | 2 h (3.5-3.8); 1 h (qwen3-vl-plus); 64 videos per request | qwen3.8-flash $0.15/M; qwen3.8-max $2/M (Intl) | **$0.005-0.07** (ESTIMATED: ≤32K tok/video cap) at about 33K px/frame for 1 h | "For scenes with fast motion, set a higher fps" | DOCUMENTED + INFERRED |
| 8 | **Gemini Live API** (3.8 Live / 3.1 Flash Live) | Streamed JPEG frames, ≤1 fps | Yes, 16 kHz PCM | ≤1 fps | A/V session **2 min** without compression; 10-min connection; resumption 2 h | $0.002/min video + $0.005/min audio in | **$0.42/h** of streamed A/V input | Real-time, but ≤1 fps | DOCUMENTED |
| 9 | **Amazon Nova 2 Lite** (Bedrock, GA; release 2025-12) | Yes: S3 (1 GB) or 25 MB inline | **No**: "Audio tracks in videos are not processed" | 1 fps ≤16 min, then 960 frames total; frames squashed to 672×672 | 1M ctx; 1 video | $0.30/M (AWS price JSON, 2026-10-16) | **$0.08** (960 × 288 tok) | Vendor admits "limited spatial reasoning"; <16 min for "high motion" | DOCUMENTED; MEASURED price |
| 10 | **Amazon Nova 2 Omni / Nova 2 Pro** (Preview since 2025-12) | Yes | Omni: speech in; whether video-embedded audio is used is unconfirmed | Not documented for Nova 2 | 1M ctx | Omni $0.30 video / $1.00 audio; Pro $1.25 (2026-10-16) | Not computable | none found | DOCUMENTED; MEASURED price; **>6 mo in preview** |
| 11 | **Gemini Robotics-ER 2** (+ Streaming Preview, 2026-07) | Yes (+ Live streaming) | Yes | Not documented | 131K ctx | $1.00/M until 2026-12-31, then $2 | not computed | Points, boxes, trajectories, **object tracking in video, moment finding, task progress** (no benchmarks) | DOCUMENTED (vendor) |
| 12 | **Perceptron Mk1.5** (startup, 2026-09-25) | Yes: URL, file, or pre-selected `video_frames` with `timestamp_ms` | Opt-in `enable_audio_in_video`; 750 tok/min; ≤21.8 min audio | Not documented | **36,864 ctx** (short clips only) | $0.15/M in, $1.50 out (OpenRouter) | not meaningful at this context size | **Tracks, clips (time intervals), points/boxes/polygons**; a dense-tracking guide combines optical flow | DOCUMENTED (vendor) |
| 13 | **Meta SAM 3.1** (hosted on Meta Model API) | Yes: segmentation, not QA | n/a | Per frame | ≥50 frames billed per request | $0.20 per 1,000 frames (2026-10) | **$0.72/h at 1 fps**, $21.60/h at 30 fps | Text-prompted boxes and masks **tracked across frames** | DOCUMENTED |
| 14 | **OpenAI GPT-6 Astra / Sol / Luna; GPT-Realtime-2** | **No** video input. Realtime-2 takes `input_image` | Realtime audio only | n/a: send frames (≤1,500 images, 512 MB per request) | 1.05M ctx | Astra $10/M in; Realtime-2 image $5/M | Not computable (no patch-to-token formula on the pricing page) | none | DOCUMENTED |
| 15 | **xAI Grok 4.7** (2026-09-21) | **No** (image only; video = Imagine *generation*) | STT $0.10/h batch (separate) | n/a | 500K | $2/$6 | n/a | none | DOCUMENTED (absence) |
| 16 | **Mistral Large 4** (public preview 2026-10-06) | **No** (text and image) | Voxtral is audio-only (separate) | n/a | 1.05M | $1.36/$4.18 | n/a | none | DOCUMENTED |

Reference point for the table: Opus 5.5 reading frames itself costs about **$3.01/h** at 1 fps and 512×288
(752,400 tokens at $4/M), or about **$17.22/h** at 1280×720 (1,196 tok/frame). It also needs at least 6 requests per
hour because of the 600-image cap (ESTIMATED; tokens from `ceil(w/28)·ceil(h/28)`, F1 §1a).

## 2. Entries in detail

### 2.1 Google Gemini API: Gemini 3.8 Flash, static + agentic video (the workhorse)
- **Input path.** The video goes in as a file part through the Files API (20 GB paid, 2 GB free), Cloud Storage
  registration (2 GB), inline data (<100 MB per the summary table; another section says 20 MB, so the doc contradicts
  itself) or a **public YouTube URL**. YouTube is in preview and free of charge; the free tier is capped at 8 h/day;
  private and unlisted videos are refused. Up to 10 videos per request (2.5+).
- **Static mode** (default for every model): 1 fps. Frames cost 66 tokens at low and 258 at high resolution in this
  doc. Vertex says Gemini 3 models use 70 tokens at LOW/MEDIUM/default and 280 at HIGH. Audio is 1 Kbps mono at
  32 tok/s, with MM:SS timestamps every second. The total is about 100 tok/s at the default low resolution and about
  300 at high. `processing: {type: static, fps, start_offset, end_offset}` applies to static mode only.
- **Agentic mode** (`"processing": "agentic"`, Interactions API): the model "dynamically navigates the video
  timeline", reads the transcript first, and loads segments and audio on demand. Vendor claim: "up to 88% more
  token-efficient and ~7% higher quality on long-form". It can be slower and costlier on clips under 5 min. Steps
  appear as `processing_call` and `processing_result`. `background=True` is recommended.
- **Price per hour** (ESTIMATED: 360K tok/h low, 1.08M high): $0.27 low and $0.81 high now; doubles 2027-01-01.
  Applying the 88% claim to a long video at low res gives about $0.03/h before thinking and output tokens (INFERRED).
- **Data use:** paid tier is not used for training; free tier is (F3 §3, DOCUMENTED).
- **Claude fit:** no Claude-native path. A skill or CLI shells out to the `google-genai` SDK with a `GEMINI_API_KEY`
  and returns text or JSON. Existing community wrappers: claude-video `--engine gemini`, claude-video-vision (F3).
  **Egress:** the whole file goes to Google. YouTube URLs avoid both download and upload.
- **Evidence:** Video-MME-v2 (independent benchmark authors, Apr 2026) gives Gemini-3-Flash 42.5 Non-Lin / 61.1 acc
  with subtitles; humans score 90.7. Nobody has published an independent score for 3.8 Flash. Qwen's blog (a
  competitor's run) gives 3.8 Flash static/agentic: OmniVideoBench 65.2/70.1, Video-MME-v2 71.0/72.7,
  LVOmniBench 70.7/70.7.
- URLs: https://ai.google.dev/gemini-api/docs/video-understanding ; https://ai.google.dev/gemini-api/docs/pricing ;
  https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/video-understanding

### 2.2 Gemini 4 Argon (quality tier)
- `gemini-4-argon` went GA on 2026-10-13 (blog). Inputs: text, image, video, audio, PDF. 1,048,576 context, 65,536
  output by default. Paid only. Model page updated 2026-10-14. Knowledge cutoff March 2026 (model card).
- **Price:** $2/$10 per M until 2026-11-30, then $4/$20. Batch is half. ESTIMATED **$0.72/h** low and $2.16 high now;
  $1.44 and $4.32 from December.
- **Evidence (vendor-run):** LVBench 91.7 vs GPT-6 Astra 87.5 (800 frames), Opus 5.5 83.7 (600 frames), Fable 5.1
  79.7 (300 frames), "self computed without tools… 1FPS for Gemini". Chartography 71.6. ERQA 87% (blog). An
  aggregator reports Artificial Analysis's general index has Argon 5 points *behind* Opus 5.5, which is not a video
  measure. **The 8-point LVBench gap between Argon (native) and Opus 5.5 (frames only) is the most decision-relevant
  vendor number found** (INFERRED): a frames-plus-transcript Claude pipeline is not hopeless on long-video QA. But this
  was Google's run of a competitor, with its own frame choice.
- URLs: https://ai.google.dev/gemini-api/docs/models/gemini-4-argon ;
  https://storage.googleapis.com/deepmind-media/Model-Cards/Gemini-4-Argon-Model-Card.pdf ;
  https://deepmind.google/models/evals-methodology/gemini-4-argon/ ;
  https://blog.google/innovation-and-ai/models-and-research/gemini-models/introducing-gemini-4-argon/

### 2.3 Gemini Flash-Lite tier (cheapest native audio+video)
- 3.5 Flash-Lite charges $0.30/M for all modalities and supports agentic mode: about **$0.11/h** low.
- 2.5 Flash-Lite charges $0.10/M video and $0.30/M audio: about **$0.06/h** low (66 tok/frame plus 32 tok/s audio).
  It was released 2025-07, so its evidence is **more than 6 months old**.
- Use: a bulk first pass ("index this hour"), then escalate to Flash or Argon on the flagged segments (INFERRED).

### 2.4 Qwen3.8-Omni-Flash (Alibaba Model Studio): the closest non-Google analogue to Gemini
- Text, image, audio and video in; text out; 1M context. Video file "supports audio in the video", with visual and
  audio billed separately. Limits: 2 h and 2 GB (URL), base64 <10 MB. Calculator constants: 2 fps default, 640×32×32
  max px per frame, at most 2,048 frames, total ≤180,224×32×32 px, so at most about 90K video tokens per video
  (INFERRED from the doc's code). The doc says the model is "stable" with input sampled at up to 15 fps.
- **Agentic mode:** vendor blog (2026-09-20). The model "independently decides what to watch and listen to", working
  coarse to fine. Static vs agent (agent run in the Qwen Code harness): OmniVideoBench 63.4→67.8, Video-MME-v2
  65.0→71.3, LVOmniBench 63.3→73.6. Tokens per query fell 145,736→79,117. Vendor claim: video price per hour down
  more than 93% vs 3.5-Omni-Plus. No API parameter for agentic mode is documented (it was run through Qwen Code).
- **Price:** $0.15/M in and $0.47/M out (Intl, pricing page 2026-10-22; OpenRouter agrees). ESTIMATED about $0.03/h,
  but the audio tokens per second are **not documented**. I assumed 25 tok/s.
- **Claude fit:** an OpenAI-compatible endpoint (`DASHSCOPE_BASE_URL`) makes this a 20-line skill. Egress goes to
  Alibaba Cloud: Singapore, US (Virginia), Frankfurt and other regions are available. I did not verify the
  data-training terms.
- URLs: https://www.alibabacloud.com/help/en/model-studio/qwen-omni ;
  https://www.alibabacloud.com/blog/qwen3-8-omni-flash-omni-senses--agentic-delivery-_603580 ;
  https://www.alibabacloud.com/help/en/model-studio/model-pricing

### 2.5 Qwen VL-capable API models (no audio)
- Doc updated 2026-10-11. qwen3.5 to 3.8 handle up to 2 h; qwen3-vl-plus 1 h; open Qwen3-VL 20 min. Up to 64 videos and
  2,048 images per request. `fps` defaults to 2.0 (range 0.1-10) plus `max_frames` (DashScope SDK only). Local file
  ≤100 MB. "The model does not support understanding the audio track of video files."
- **Hidden downscale (INFERRED from the doc's calculator):** tokens = frames/2 × (h/32) × (w/32), and total pixels per
  video ≤65,536×32×32 (≤131,072×32×32 on qwen3-vl-plus). The ceiling is therefore about **32K tokens per video**
  (about 65K on plus). At the 2,000-frame cap that leaves about 33.5K px per frame, roughly 244×137, for an hour of
  footage. That is cheap (ESTIMATED $0.005/h on qwen3.8-flash, $0.07/h on qwen3.8-max) but near-useless for on-screen
  text in long video. Pass an image list at controlled resolution instead.
- URL: https://www.alibabacloud.com/help/en/model-studio/vision ; https://www.alibabacloud.com/help/en/model-studio/vision-model/

### 2.6 ByteDance Seed 2.1 Pro / Turbo (BytePlus ModelArk; Volcengine in China)
- **Mechanism (DOCUMENTED, BytePlus video-understanding doc updated 2026-10-23):** fps-based sampling, then the
  sequence is assembled as "timestamp + image". `fps` defaults to 1 (min 0.2, max 5). Frames: 16-1,280. Tokens per
  frame 64-384 (`min_frame_tokens`/`max_frame_tokens`, 42×42 px per token). `max_video_tokens` defaults to 81,920. Over
  1,280 frames, frames are spread evenly at 64 tokens each (about 112,896 px, roughly 448×252). Input: Files API
  (512 MB, or 2 GB with a TOS bucket; needs `preprocess_configs.video.model`), URL or base64 ≤50 MB. "Some models"
  read embedded audio. The doc states it "will not retain user data… for model training". Example model ID:
  `dola-seed-2-1-turbo-260628`.
- **Vendor benchmarks** (seed.bytedance.com/seed2_1): Seed2.1 Pro / Turbo vs Gemini 3.5 Flash / 3.1 Pro: VideoMME
  89.2/89 vs 87.2/86.7; **TOMATO (motion) 79.5**/56.8 vs 71.9/60.4; Minerva 70.7; OVOBench (streaming) 80.7;
  ERQA 72.0. This is the strongest *motion* claim among general frontier models, and it is self-reported (F2 flagged
  the same).
- **Independent:** Video-MME-v2 has Doubao-Seed-2.0-Pro at 43.3 Non-Lin / 60.5, between Gemini-3-Pro (49.4) and
  Gemini-3-Flash (42.5).
- **Price:** Turbo $0.50/$2.50 per M (OpenRouter, listed 2026-08-12). The Pro price ($0.89/$4.45) comes only from an
  aggregator, unverified. ESTIMATED about $0.04/h on Turbo, because of the 80K-token cap.
- URLs: https://docs.byteplus.com/en/docs/ModelArk/1895586 ; https://seed.bytedance.com/en/seed2_1

### 2.7 Meta Muse Spark 1.3 / Muse Wonder (Meta Model API): Meta's frontier line, replacing Llama
- Hosted at `https://api.meta.ai/v1`, OpenAI-compatible Responses and Chat Completions, and a Messages protocol.
  Video: mp4 only, uploaded with the Files API (≤1 GiB, `purpose=user_data`) or passed as `input_video.video_url`
  (public or base64, 50 MB inline). "Muse Spark reads a video's visual sequence and any embedded audio together." Audio
  on 1.3 "is currently not fully supported… may be degraded"; use 1.2. **No fps, duration or token-per-second figures
  are documented.**
- Muse Wonder (`muse-wonder-1.0`, model card release date 2026-10-12, preview): text, image, video, audio and PDF in;
  1M context; $4/$20 per M. Muse Spark: $1.25/$4.25. **Contributor mode** costs $0.10/$0.20, and Meta trains on that
  data. Standard mode does not train on it.
- Model card: no video benchmark published, and it states "Visual and spatial reasoning, especially 3D tasks, remains a
  known limitation."
- Muse Spark Open (816B MoE, 42B active, open weights, video+audio) belongs to the open-weight axis (R3).
- URLs: https://dev.meta.ai/docs/video-understanding.md ; https://dev.meta.ai/docs/models.md ;
  https://dev.meta.ai/docs/pricing-rate-limits.md ; https://research.meta.ai/static/muse-wonder-model-card

### 2.8 Gemini Live API (real-time streaming)
- Input is JPEG frames at **≤1 fps** plus 16 kHz PCM audio. Without context compression, an audio+video session ends
  after **2 minutes** (audio-only: 15). Connections last about 10 min; resumption tokens are valid for 2 h;
  `contextWindowCompression` uses a sliding window. Prices: 3.8 Live charges $0.002/min image/video and $0.005/min
  audio input, so about $0.42/h of input.
- Fit: live screen-share or camera agents, not after-the-fact video files. Claude Code has no streaming-media surface,
  so this only fits as a side process that writes text events (INFERRED).
- URLs: https://ai.google.dev/gemini-api/docs/live ; https://ai.google.dev/gemini-api/docs/live-session

### 2.9 Amazon Nova 2 Lite (Bedrock), GA
- MP4, MOV, MKV, WebM, FLV, MPEG, MPG, WMV, 3GP. One video per request: 25 MB inline or 1 GB via S3. Every frame is
  **resized with distortion to 672×672**. 1 fps up to 16 min, then 960 frames total. The doc's own table contradicts
  that rule (45 min = 2,700 frames). About 288 tokens per frame. **No audio.** Vendor caveats: "limited spatial
  reasoning", small text, and <16 min for high-motion content.
- **Price:** $0.30/M in, $2.50/M out. MEASURED from the AWS metered-pricing JSON
  (`b0.p.awsstatic.com/.../bedrock.json`, published 2026-10-16). ESTIMATED **$0.08/h** at the 960-frame cap.
- Fit: Bedrock is attractive if the data must stay in an AWS account (Bedrock does not train on inputs: F3/October,
  not re-checked). Audio needs a separate ASR.
- URL: https://docs.aws.amazon.com/nova/latest/nova2-userguide/using-multimodal-models.md

### 2.10 Amazon Nova 2 Omni / Nova 2 Pro (Preview)
- Both were announced in preview at re:Invent (2025-12) and are **still Preview** on the AWS pricing page (2026-10-16).
  Neither appears in the Nova 2 user guide's model table, which lists only Lite, Sonic and Embeddings. Omni accepts
  text, image, video and speech; whether it uses the *audio track inside a video* is not documented. Prices:
  Omni $0.30/M text, image and video, $1.00/M audio, $2.50 out; Pro $1.25/M in, $10 out (MEASURED, AWS price JSON).
  The newest evidence of the launch is more than 6 months old.

### 2.11 Gemini Robotics-ER 2 / ER 2 Streaming (Preview, 2026-07)
- Text, image, video and audio in; text out (JSON points `[y,x]` 0-1000, boxes, trajectories). The vendor claims
  object tracking in video, moment finding in continuous feeds, and task-progress and success detection. The
  streaming variant runs on the Live API. 131K context. $1/$5 per M until 2026-12-31, then $2/$10. No benchmarks on
  the page.
- Why it matters: it is the only Google model whose documented output is spatial and temporal *structure* rather than
  prose. That is useful for "where/when did X move" questions that the general models blur (INFERRED).
- URL: https://ai.google.dev/gemini-api/docs/robotics-overview

### 2.12 Perceptron Mk1.5 (startup; native video model with grounded outputs)
- Released 2026-09-25 (changelog), when Isaac 0.1 and 0.2 were retired. Video by URL or file; frames only by default.
  Set `vision_config.enable_audio_in_video: true` for sound (about 750 encoder tok/min, ≤16,384 = about 21.8 min).
  Accepts **pre-selected `video_frames` with `timestamp_ms`**, which fits a Claude pipeline that already picks
  keyframes. Outputs: `<clip … t="1.0 seconds 4.5 seconds">`, points, boxes, polygons and **tracks**. A "High Fidelity
  Object Tracking" guide combines model waypoints with optical flow. The doc warns: "Frame sampling can miss brief
  events; avoid treating a missing observation as proof that an event never occurred."
- Context is only 36,864 tokens, so it suits clips, not hours. $0.15/$1.50 per M (OpenRouter).
- URLs: https://docs.perceptron.inc/perceptron-mk1.5/capabilities/video-understanding.md ;
  https://docs.perceptron.inc/perceptron-mk1.5/changelog.md

### 2.13 Meta SAM 3.1 (hosted segmentation and tracking)
- `sam-3.1` on Meta Model API takes a noun phrase (or boxes and points) plus an image or video and returns every match
  as boxes and masks, "follows each match across frames". Billing: $0.20 per 1,000 video frames, at least 50 frames
  per request. ESTIMATED $0.72/h at 1 fps.
- This is a measurement primitive, not QA, and it is the motion-tracking complement the frontier QA models lack
  (INFERRED). The open SAM weights are covered under R7.
- URL: https://dev.meta.ai/docs/media-segmentation.md

### 2.14 OpenAI: no native video (GPT-6 Astra, Sol, Luna; GPT-Realtime-2)
- Models page: "All latest OpenAI models support text and image input". No model lists video. Vision guide: ≤1,500
  images and 512 MB per request; `detail` low, high or original; Astra at `high` takes up to 2,500 patches. The
  Realtime guide says "`gpt-realtime-2` and `gpt-realtime` also support image input" (`input_image`). Realtime image
  tokens cost $5/M. Astra is $10/M in.
- Google's LVBench run fed Astra 800 frames "due to API limitations". OpenAI's video route is the same frames
  transcode Claude uses. GPT-Live 1 ($0.05/min) is voice; no API video found.
- URLs: https://developers.openai.com/api/docs/models ; https://developers.openai.com/api/docs/guides/images-vision ;
  https://developers.openai.com/api/docs/guides/realtime-conversations ; https://developers.openai.com/api/docs/pricing

### 2.15 xAI Grok 4.7: no video input
- docs.x.ai models page: flagship `grok-4.7`, 500K context, $2/$6. The doc menu has "Image Understanding" only. Video
  appears only as **Imagine** generation (from $0.02/s). STT costs $0.10/h batch and $0.20/h streaming: a cheap ASR leg
  for a transcode pipeline (DOCUMENTED). OpenRouter lists every Grok 4.x model as text, image and file input.
  Third-party claims of "native video input on Grok 4.3" are unverified and contradicted by both sources.
- URL: https://docs.x.ai/docs/models

### 2.16 Mistral Large 4: no video input
- docs.mistral.ai: public preview, released 2026-10-06, input text and image, $1.36/M in and $4.18/M out. Voxtral
  handles audio only. One Eden AI tag claims "Video input", contradicted by Mistral's own page.
- URL: https://docs.mistral.ai/models/mistral-large-4-0.md

## 3. Long tail: other APIs that accept video, surfaced but not deep-checked
From the OpenRouter catalogue (`curl https://openrouter.ai/api/v1/models`, MEASURED 2026-10-24: 469 models, 90 with
`video` in `input_modalities`): Moonshot **Kimi K3.1 Pro** (2026-10-23, $2/M, open weights), Xiaomi **MiMo-V2.6
Pro/Flash** (2026-09-21, video+audio, $0.435/$0.14 per M), Zhipu **GLM-5.3 Flash/FlashX**, StepFun **Step-5
Preview**, MiniMax **M3.1 Flash**, NVIDIA **Nemotron 3.5 Super VL** (a free tier exists), Elorian **Glimpse**
(2026-10-17, "visual reasoning in the physical world"). These are mostly open-weight (R3's axis). OpenRouter's
modality tags are third-party metadata, and I did not verify each against the vendor's docs.

## 4. Takeaways for this axis
1. **Gemini is still the only frontier vendor with first-class video+audio, URL/YouTube input, fps control and a
   documented agentic navigator.** 3.8 Flash at about $0.27/h (low res) is the default perception sub-tool; Argon is
   the escalation at about $0.72/h until 2026-11-30, then twice that.
2. **Fast followers have arrived, but their docs are thinner.** Qwen3.8-Omni-Flash (video+audio plus agentic, about
   $0.03/h ESTIMATED), Seed 2.1 (best self-reported motion score, 1-5 fps, timestamp-interleaved) and Meta Muse (video
   with embedded audio, no sampling docs) all take video natively. None publishes independent evidence beyond
   Video-MME-v2's Seed-2.0 row.
3. **Hosted APIs silently cap tokens per video.** Qwen VL allows about 32K, Seed 80K, Nova 960 frames at 672×672.
   Gemini's 1M context lets 1 h fit at high res. For on-screen text or fine motion, send pre-selected frames at known
   resolution (Qwen image list, Perceptron `video_frames`) or use Gemini with `media_resolution` high (INFERRED).
4. **Motion and spatial evidence is all vendor-reported.** Seed TOMATO 79.5, Argon ERQA 87, Robotics-ER tracking,
   Perceptron tracks. Every general model samples at 1-2 fps by default, and three vendors (Google, Amazon, Perceptron)
   warn in their own docs that fast or brief events get missed. Structured-output models (Robotics-ER 2, Perceptron,
   SAM 3.1) are the only route that returns *where and when* as data.
5. **For Claude Code the integration pattern is the same everywhere:** a skill or CLI uploads the file (or passes a
   URL) to a third-party cloud and relays text. OpenAI, xAI and Mistral offer nothing beyond what Claude already
   does. Google's LVBench table (Opus 5.5 at 83.7 on 600 frames vs Argon at 91.7, vendor-run) suggests a native model
   buys about 8 points on hour-long QA. Paying for it means video egress.

## 5. Not found, dead or unverified
- **Meta Llama 4/5 video:** no Llama-branded video API found. Meta's frontier and API line is Muse (Spark, Wonder);
  "Muse Video" is generation and unreleased per a catalogue page.
- **OpenAI video input:** absent from all primary docs. The "GPT-5 60 s clips" claim (F1) remains unverified, and the
  LiveKit "Realtime video" pattern is frame-pushing.
- **xAI "Grok 4.3 native video input":** third-party only, contradicted by docs.x.ai and OpenRouter.
- **Seed 2.1 Pro official BytePlus price:** not found (the pricing page is JS-rendered); only an aggregator figure.
- **Qwen-Omni audio tokens per second; Meta Muse fps and duration limits; Nova 2 Omni use of video audio:** not
  documented.
- **Independent (non-vendor) video benchmark for Gemini 4 Argon, 3.8 Flash, Qwen3.8-Omni, Seed 2.1 or Muse:** none
  found.

## Sources (primary unless noted)
- Google: https://ai.google.dev/gemini-api/docs/video-understanding (raw `.md.txt` MEASURED grep) ·
  https://ai.google.dev/gemini-api/docs/pricing · https://ai.google.dev/gemini-api/docs/models/gemini-4-argon ·
  https://storage.googleapis.com/deepmind-media/Model-Cards/Gemini-4-Argon-Model-Card.pdf ·
  https://deepmind.google/models/evals-methodology/gemini-4-argon/ ·
  https://blog.google/innovation-and-ai/models-and-research/gemini-models/introducing-gemini-4-argon/ ·
  https://ai.google.dev/gemini-api/docs/live · https://ai.google.dev/gemini-api/docs/live-session ·
  https://ai.google.dev/gemini-api/docs/robotics-overview ·
  https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/video-understanding
- OpenAI: https://developers.openai.com/api/docs/models · …/guides/images-vision · …/guides/realtime-conversations ·
  …/pricing
- AWS: https://docs.aws.amazon.com/nova/latest/nova2-userguide/using-multimodal-models.md ·
  https://docs.aws.amazon.com/nova/latest/nova2-userguide/what-is-nova-2.md · https://aws.amazon.com/nova/pricing/ +
  `https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/bedrock/USD/current/bedrock.json` (MEASURED)
- Meta: https://dev.meta.ai/docs/video-understanding.md · https://dev.meta.ai/docs/models.md ·
  https://dev.meta.ai/docs/pricing-rate-limits.md · https://dev.meta.ai/docs/file-handling.md ·
  https://dev.meta.ai/docs/media-segmentation.md · https://research.meta.ai/static/muse-wonder-model-card
- Alibaba: https://www.alibabacloud.com/help/en/model-studio/vision · …/vision-model/ · …/qwen-omni · …/model-pricing ·
  https://www.alibabacloud.com/blog/qwen3-8-omni-flash-omni-senses--agentic-delivery-_603580
- ByteDance: https://docs.byteplus.com/en/docs/ModelArk/1895586 · https://seed.bytedance.com/en/seed2_1
- xAI: https://docs.x.ai/docs/models · Mistral: https://docs.mistral.ai/models/mistral-large-4-0.md
- Perceptron: https://docs.perceptron.inc/perceptron-mk1.5/capabilities/video-understanding.md ·
  https://docs.perceptron.inc/perceptron-mk1.5/changelog.md
- Independent: https://video-mme-v2.netlify.app/ (arXiv 2604.05015) · OpenRouter catalogue
  https://openrouter.ai/api/v1/models (third-party metadata)
