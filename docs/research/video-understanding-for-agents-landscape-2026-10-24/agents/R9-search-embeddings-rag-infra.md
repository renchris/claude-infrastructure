# R9: Video search, embedding and RAG infrastructure (as of 2026-10-24)

Axis: the retrieval layer of a video agent. That means embedding models that put video segments and text queries in one vector space, managed indexers that turn video into searchable records, vector databases with video pipelines, and the benchmarks that rank them.

Our agent is Claude Opus 5.5 in Claude Code. It cannot take video or audio input, and Claude Code clamps images to 2000 px. So an embedding index never gives it "understanding". It gives it **where to look**: a ranked list of (video, start, end) hits. The agent then pulls frames and transcript for those windows with the local pipeline that `skills/video-understanding/SKILL.md` already documents. Prior work (REPORT.md, F1-F3) did not cover this axis. F3 mentions Marengo 3.5 only as Pegasus's search companion, so this file starts from zero.

Method: WebSearch, plus WebFetch or curl of primary docs, pricing pages, the AWS price map, HF model cards, the GitHub and HF APIs, and two arXiv PDFs read with `pdftotext`. I did not create any account, upload any video or install anything. Labels:

- **MEASURED**: a number I fetched myself. The command or API is named.
- **DOCUMENTED**: a vendor or paper statement, cited.
- **INFERRED**: my arithmetic or judgement. The method is named.

Unless marked "independent", every quality number in this file is the vendor's own claim.

## 1. Narrative

**The quality tier is narrow, and it is all API.** Five public result sets exist:

- Google's own paper (arXiv 2605.27295, 2026-05-26). Google ran the competitors through their APIs.
- Mixedbread's eval page (testing dated March 2026).
- Tencent's WeMM report (arXiv 2608.24053, 2026-08). Tencent re-tabulated Gemini Embedding 2, Nova and Voyage and measured Qwen3-VL-Embedding.
- TwelveLabs' Marengo 3.5 post.
- The only independent run: Mixpeek's 20-video, 60-query benchmark (2026-03-12). Mixpeek is commercially interested and resells Gemini Embedding 2.

Read together, they rank text-to-video retrieval roughly as follows:

1. **Top band**: Gemini Embedding 2, Marengo, Mixedbread Wholembed v3, and the open Qwen3-VL-Embedding-8B and WeMM-Embedding.
2. **Next**: Amazon Nova MME.
3. **Below that**: Voyage multimodal-3.5 and Google's legacy multimodalembedding@001.
4. **Bottom**: frame-averaged CLIP-family models.

The weakest results are on instructional and long-procedure video. YouCook2 NDCG@10 is 31-35 for Nova, Voyage and @001, against 52.5 for Gemini Embedding 2, 54.7 for Qwen3-VL-8B and 64-66 for Mixedbread and WeMM-9B (DOCUMENTED, the tables cited in section 3).

**Open-weight models caught up in 2026.** On Tencent's re-tabulation, Qwen3-VL-Embedding-8B (Apache-2.0, released 2026-01-08) matches or beats Gemini Embedding 2 on all three text-to-video sets: 68.5 / 70.6 / 54.7 against 68.8 / 68.0 / 52.5. WeMM-Embedding-9B (2026-08-25, Apache-2.0 per its model card) claims 78.4 / 74.1 / 66.3 (DOCUMENTED, WeMM Table 3). Nobody has replicated these numbers, so treat them as vendor and paper claims.

This changes the agent-builder calculus. A **fully local** video index is now credible: no egress, a Qwen3-VL-Embedding-2B or 8B encoder on 1 fps and 64-frame clips, LanceDB or Qdrant as the store, and the Qwen3-VL-Reranker as stage two. The cost is GPU time. Running it on our Mac is unmeasured.

**"Video is not a bag of frames" is the one independent result an agent builder should act on.** In Mixpeek's run, SigLIP 2 averaged over 8 frames scored NDCG@10 0.325, and InternVideo2-6B scored 0.302. The API models scored 0.757-0.769 (DOCUMENTED; the third party is small-n and partly rate-limited). A do-it-yourself CLIP-over-keyframes index is therefore a poor event-search tool. It is fine for "find the frame that looks like X". It is not fine for "find when X happens".

**How each one segments video matters more than embedding dims.**

| Product | Segmentation |
|---|---|
| Marengo 3.5 | Segments itself: dynamic, scene-change splits with a 2 s minimum by default, or fixed length. Returns one clip vector per segment plus an optional whole-asset vector. |
| Nova MME | Segments itself: async jobs cut 1-30 s segments. |
| Gemini Embedding 2 | Does **not** segment. You must cut 120 s chunks yourself. On the Gemini API it reads at most **32 frames per chunk** (1 fps only up to 32 s) and **ignores the audio track**. The Vertex variant documents up to 120 frames and optional audio extraction (about 81 s at 1 fps). |
| multimodalembedding@001 | Analyzes 2 min per call at an `intervalSec` of 4 s or more. Ignores audio. |
| Voyage | Takes whole videos up to 20 MB and 32k tokens. You chunk. |
| Mixpeek and VideoDB | Wrap all of this in ffmpeg time, scene or silence cuts, plus captioning. |

For an agent the consequence is concrete. A Gemini Embedding 2 index over a 47-min interview, cut into 120 s chunks, sees about 0.27 fps (INFERRED: 32 frames / 120 s). It has no audio either. Spoken content must come from a separate transcript index. That is exactly the hybrid Mixpeek and VideoDB build.

**Audio is the main differentiator.** These embed the audio track natively:

- Marengo 3.5: one encoder for speech, music and non-speech sound.
- Nova MME: `AUDIO_VIDEO_COMBINED` mode.
- Meta PE-AV.
- Jina v5 omni (optional audio segment).
- Mixedbread (as claimed).

These do not:

- Gemini Embedding 2 video on the Gemini API.
- multimodalembedding@001.
- Qwen3-VL-Embedding.
- WeMM.
- Voyage (not documented).

For talking-head and meeting video, the 2026-10-23 probe found that transcript and OCR carry most of the signal. A transcript text index plus a visual embedding index (hybrid) is the right shape whichever vendor you pick (INFERRED, from REPORT.md section 3).

**Price per video-hour has converged near $2-3 for hosted APIs.** The exceptions are Voyage's per-pixel meter, which is cheaper at low resolution, and Marengo 3.5's per-token meter. TwelveLabs does not publish tokens per minute, so the Marengo 3.5 cost cannot be computed ahead of time. See the table in section 2.

**Agent wiring exists, but mostly for managed indexers, not for raw embedding APIs.** Hosted MCP servers:

- VideoDB: `claude mcp add --transport http videodb https://mcp.videodb.io/mcp`, plus a local Director MCP.
- Mixpeek: five scoped MCP servers at `mcp.mixpeek.com`, plus a Claude Code skill.
- TwelveLabs: the Claude Code plugin and the Jockey connector (F3).

Qdrant has `mcp-server-qdrant`, and LanceDB ships a Claude Code plugin marketplace. Gemini Embedding 2, Nova MME, Voyage and Qwen3-VL-Embedding are reachable only through a script or CLI the agent writes. That is cheap to build in Claude Code.

**Traps found today** (DOCUMENTED, primary docs):

1. Weaviate's `multi2vec-twelvelabs` module is **text and images only**. A `videoFields` entry is stored and silently ignored.
2. Weaviate's `gemini-embedding-2` path lists text, image, PDF and audio, with **no video**. Video in `multi2vec-google` works only with `multimodalembedding@001`.
3. Pinecone's model docs still list `Marengo-retrieval-2.6`, but TwelveLabs sunset Marengo 2.7 on 2026-03-30.
4. The `/search` endpoint on Marengo 3.5 does not exist. You must search 3.5 vectors in your own database, or keep an index on Marengo 3.0.
5. Marengo 3.0 and 3.5 vectors are incompatible, so switching means a full re-embed.
6. The Gemini free tier lets Google use your content to improve its products. The paid tier does not.

## 2. Comparison table

Prices are on-demand and in USD, with the date each was fetched. "/hr" means per hour of source video.

| # | Name | Kind | Segmentation | Audio in video vector | Dims | Price per video-hour | Quality evidence | Agent wiring |
|---|---|---|---|---|---|---|---|---|
| 1 | TwelveLabs Marengo 3.5 | API embedding | dynamic (scene change, min 2 s default) or fixed; clip + asset scopes; sync <=30 s | yes (unified encoder) | 128/256/512 (MRL) | $0.260/1M video tokens; tokens/min **unpublished** -> unknown. Marengo 3.0: $2.50/hr (overage page, 2026-10-24) | vendor: 67.38 composite vs GE2 62.35, Nova 50.34 | REST/SDK; Claude Code plugin and Jockey (F3); Qdrant docs updated for 3.5 |
| 2 | Google Gemini Embedding 2 | API embedding | none; <=120 s per request; Gemini API <=32 frames, 1 fps only <=32 s | **no** (Gemini API); optional on Vertex (about 81 s) | 128-3072, default 3072 | $0.00079/frame ($12/1M tok); 1 fps -> **$2.84/hr**; 32 frames per 120 s -> **$0.76/hr**; batch half (pricing page updated 2026-10-22) | Google paper: Vatex 68.8, MSR-VTT 68.0, YouCook2 52.5 NDCG@10; independent-ish Mixpeek NDCG@10 0.769 | script only; Weaviate integration lacks video |
| 3 | Amazon Nova Multimodal Embeddings | API embedding | async, 1-30 s segments | yes (combined or separate) | 3072/1024/384/256 | $0.0007/s = **$2.52/hr**; batch $0.00056/s = $2.02/hr (AWS price map published 2026-10-16) | Google paper: 60.3 / 67.0 / 34.7; TwelveLabs composite 50.34 | Bedrock SDK; us-east-1 |
| 4 | Qwen3-VL-Embedding 2B/8B + Reranker | open weights, Apache-2.0 | you chunk; fps 1.0, max_frames 64 default | no | 2B <=2048, 8B <=4096 (min 64, MRL) | GPU only | card: MMEB-V2 video 66.1, V-Ret 57.0, M-Ret 53.2; WeMM table: Vatex 68.5 / MSR-VTT 70.6 / YouCook2 54.7 | local; vLLM, sentence-transformers, SGLang |
| 5 | Mixedbread Wholembed v3 (Search stores) | managed multi-vector store | undisclosed | claimed | late-interaction, multi-vector | 24,000 tokens/min; Fast $1.50/M -> **$2.16/hr**; HQ $3/M -> $4.32/hr; storage $0.50/M/mo -> $0.72/hr-month; $4/1k semantic queries (fetched 2026-10-24) | vendor: MSR-VTT 64.4, DiDeMo 72.3, YouCook2 64.22; Mixpeek NDCG@10 0.757 (37 of 60 queries) | API; `mgrep` CLI for coding agents (video not documented) |
| 6 | VideoDB | managed indexer (VLM captions + transcript -> text and vector index) | time or shot; 1-5 frames per scene into a VLM | via transcript | n/a (server-side) | not public (pricing URL redirects to contact, 2026-10-24) | none | hosted MCP `mcp.videodb.io/mcp`; local Director MCP; skills |
| 7 | Mixpeek | managed indexer | ffmpeg time/scene/silence -> GE2 or Vertex vectors + Whisper + E5 + Gemini captions | via transcript; CLAP add-on | 3072 (GE2) or 1408 | $0.05/min base = **$3.00/hr**; +$0.10/min faces; +$0.10/min OCR (public rate card API, 2026-10-24) | its own benchmark only | 5 hosted MCP servers; Claude Code skill |
| 8 | Voyage multimodal-3.5 | API embedding | you chunk; <=20 MB per video, 32k tokens (1120 px = 1 token) | not documented | 256/512/1024/2048 | $0.60/B pixels; 1 fps at 640x360 about **$0.50/hr**, at 720p about $1.99/hr (INFERRED) | Google paper: 55.2 / 63.0 / 31.4; Mixedbread: 54.72 avg | API; Weaviate module supports video |
| 9 | Tencent WeMM-Embedding 2B/4B/9B | open weights | you chunk | no | 4096 | GPU only | paper: MMEB-V2 video 74.3 (9B); Vatex 78.4, MSR-VTT 74.1, YouCook2 66.3 | local (transformers) |
| 10 | Meta Perception Encoder: PE-Core, PE-AV | open weights, Apache-2.0 | 16-frame or all-frame variants | **yes**: PE-AV joint audio-video-text | per card | GPU only | repo: PE-AV-L avg retrieval 51.6 | local |
| 11 | Jina v5 omni small/nano | open weights CC-BY-NC-4.0; Jina API; Elastic | frames + optional audio segment | optional | small 1024, nano 768 (MRL to 32) | API price not found | **vendor admits the gap**: MMEB video retrieval 27.82 vs 58.73 for the best open baseline | Elastic Inference Service |
| 12 | Vertex multimodalembedding@001 | legacy API | intervalSec >=4 (default 16); 2 min per call | no | 128/256/512/1408 | not re-fetched today | Google paper 54.9 / 57.9 / 34.9; Mixedbread avg 48.47 | Weaviate video works only with this model |
| 13 | NVIDIA VSS 3.3 + Cosmos-Embed1 | self-hosted blueprint | streaming RTVI-Embed | no | SigLIP2 attributes 1152 | GPUs (2-4 GPUs for the search profile) | no metrics; known false positives listed | MCP-based agent; agentskills.io skills |
| 14 | Qdrant | vector DB, Apache-2.0 | n/a | n/a | any; multivector and MUVERA | OSS free / cloud | n/a | `mcp-server-qdrant`; Marengo 3.5 guide |
| 15 | LanceDB (+ Geneva) | multimodal lakehouse, Apache-2.0 | Geneva chunker UDTF (you write ffmpeg clipper) | n/a | any | OSS free / Enterprise | n/a | Claude Code plugin marketplace |
| 16 | Weaviate | vector DB with vectorizer modules | `video_interval_seconds` (Google @001) | n/a | per model | OSS / cloud | n/a | **trap**: TwelveLabs module ignores video |
| 17 | Milvus / Pinecone | vector DBs | tutorials only | n/a | any | OSS / cloud | n/a | Pinecone lists dead Marengo 2.6 |
| 18 | Google VideoPrism (-LvT) | open weights, Apache-2.0, JAX | 16 frames (B) / 8 frames (L) at 288 px | no | global + 16x16 spatial tokens | GPU only | paper-era (2024-25) | local JAX; no PyTorch yet |
| 19 | Frame-CLIP baselines (SigLIP 2, X-CLIP, InternVideo2, LanguageBind) | open primitives | uniform frames | no | 512-1152 | GPU only | Mixpeek independent: X-CLIP 0.470, SigLIP 2 0.325, InternVideo2 0.302 NDCG@10 | local |
| 20 | Benchmarks: MMEB-V2/V3 video, Mixpeek bench | benchmark | n/a | n/a | n/a | n/a | see section 3 | n/a |

How the derived prices were worked out (INFERRED):

- GE2 at 1 fps: 3600 frames x $0.00079.
- GE2 at 32 frames per 120 s: 30 chunks x 32 x $0.00079.
- Nova: $0.0007 x 3600.
- Mixedbread: 60 min x 24,000 tokens x rate.
- Mixpeek: $0.05 x 60.
- Voyage: 3600 frames x pixels per frame x $0.60/1e9. Voyage's SDK frame-sampling rate is not documented, so the cost could differ.

## 3. Entries in detail (ranked by importance to an agent builder)

### 1. TwelveLabs Marengo 3.5 (embedding API)

- **What it is.** A video-native embedding model with one space for video, audio, image, text and PDF. Introduced 2026-08-31. Selectable 128/256/512 dims added 2026-09-30. There is no duration cap; Marengo 3.0 capped at 4 h. It returns a per-dimension uncertainty vector. "Time-based metadata fusion" folds your own time-aligned text into segment vectors. Composed queries mix text with images, video or audio.
- **Segmentation (DOCUMENTED, API reference).** `temporal.dynamic` follows scene changes, with a default `min_duration_sec: 2`. `fixed` uses `duration_sec`. The default scope is `["clip","asset"]`. Asset scope is advised only for videos up to 10-30 s. Sync calls take up to 30 s of media.
- **Search caveat.** The `/search` endpoint does not support 3.5. You query the vectors in your own database. The 3.0 and 3.5 vector spaces are incompatible.
- **Price (DOCUMENTED, twelvelabs.io/overage, fetched 2026-10-24).** Embed Video $0.260/1M tokens. Audio $0.065/1M. Image $0.080/1M. Text $0.200/1M. Document $0.162/1M. Marengo 3.0 costs $2.50/hr for video and $0.50/hr for audio. Index search costs $4 per 1,000 queries. Tokens per video-minute are not published, so a cost estimate needs a test call.
- **Plans.** New plans from 2026-10-15: Free, Plus $29, Pro $99. Existing customers move on 2027-01-04.
- **Evidence.** Vendor only. Mean 70.57 on five text-to-video sets (+6.29 over 3.0). Eight-group composite 67.38 at 512 d, against GE2 62.35 at 3072 and Nova 50.34 at 3072. 256 d keeps 98.3% of the score and 128 d keeps 94.6%. Independent evidence exists only for Marengo 2.7 (Mixpeek): NDCG@10 0.760 on 34 of 60 queries, 18 s latency.
- **Fit.** It is the only hosted model in this set that **segments for you and embeds audio natively**. Cloud egress of the video applies.
- URLs: https://docs.twelvelabs.io/v1.3/docs/concepts/models/marengo/marengo-3-5.md, https://docs.twelvelabs.io/v1.3/api-reference/create-embeddings-v2/create-async-embedding-task.md, https://www.twelvelabs.io/overage, https://www.twelvelabs.io/blog/marengo-3.5, https://docs.twelvelabs.io/v1.3/docs/get-started/release-notes.md

### 2. Google Gemini Embedding 2

- **Model.** `gemini-embedding-2` is stable. The preview launched 2026-03-10, and the model page says "April 2026" for the latest update. It embeds text, image, video, audio and PDF in one space. Default 3072 dims, flexible 128-3072, MRL.
- **Video limits (DOCUMENTED, Gemini API embeddings page, updated 2026-10-09).** Up to 120 s. "Maximum of 32 frames per video". 1 fps when 32 s or shorter, otherwise uniform sampling. "Audio tracks are not processed in video files". 8,192-token cap, with silent truncation above it. For longer videos the docs say to chunk into overlapping segments.
- **Vertex variant (Vertex docs, updated 2026-10-22).** "1 video per request, up to 120 frames", where duration = 120 / FPS. Audio extraction from video is off by default, and with it on the cap is about 81 s at 1 fps. The two surfaces document different frame budgets. Check which endpoint you call.
- **Price (DOCUMENTED, Gemini API pricing page updated 2026-10-22).** Video $12/1M tokens, which is $0.00079 per frame. Batch is $0.000395 per frame. Audio is $0.00016 per second. The free tier is free of charge, but its content is used to improve Google products.
- **Evidence.**
  - Google paper, with competitors run via their APIs. Text-to-video NDCG@10 for Gemini, Nova, Voyage and @001:

    | Dataset | Gemini | Nova | Voyage | @001 |
    |---|---|---|---|---|
    | Vatex | 68.8 | 60.3 | 55.2 | 54.9 |
    | MSR-VTT | 68.0 | 67.0 | 63.0 | 57.9 |
    | YouCook2 | 52.5 | 34.7 | 31.4 | 34.9 |

    Video was embedded at 1 FPS up to 32 frames.
  - Mixpeek (independent of Google): NDCG@10 0.769, 2.46 s latency. It was fooled once on hard negatives (NDCG@1 0.800).
- **Fit.** The best price-to-quality ratio for the visual track. It is a plain API, so the agent writes a chunk-and-embed script. No MCP exists.
- URLs: https://ai.google.dev/gemini-api/docs/embeddings, https://ai.google.dev/gemini-api/docs/pricing, https://docs.cloud.google.com/vertex-ai/generative-ai/docs/embeddings/get-multimodal-embeddings, https://arxiv.org/abs/2605.27295

### 3. Amazon Nova Multimodal Embeddings

- **Model.** `amazon.nova-2-multimodal-embeddings-v1:0`, GA 2025-10-28. The newest primary evidence is the launch, so it is **older than 6 months**. No 2026 model update was found. Context is 8K tokens, which is 30 s of video plus 30 s of audio per sync call. Async `SEGMENTED_EMBEDDING` jobs take `durationSeconds` per segment (1-30 s, per secondary sources; the docs example uses 15). Modes are `AUDIO_VIDEO_COMBINED` or separate audio and video. Dims 3072/1024/384/256 (MRL). Region us-east-1.
- **Price (MEASURED: AWS price map JSON, `b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/bedrock/USD/current/bedrock.json`, published 2026-10-16, us-east-1).** Video $0.0007/s on-demand and $0.00056/s batch. Audio $0.00014/s. Image $0.00006. Text $0.135/1M tokens.
- **Evidence.** Google's paper: 60.3 / 67.0 / 34.7. TwelveLabs composite: 50.34. No independent run.
- **Fit.** The natural pick if the corpus is already in S3 under AWS governance.
- URLs: https://docs.aws.amazon.com/nova/latest/userguide/nova-embeddings.md, https://aws.amazon.com/nova/pricing/, https://aws.amazon.com/about-aws/whats-new/2025/10/amazon-nova-multimodal-embeddings

### 4. Qwen3-VL-Embedding and Qwen3-VL-Reranker (open, Apache-2.0)

- **Model.** 2B and 8B. Released 2026-01-08 (HF createdAt 2026-01-07; paper arXiv 2601.04720). Inputs are text, images, screenshots and video. Dims run 64 up to 2048 (2B) or 4096 (8B), with 32K context.
- **Video defaults (DOCUMENTED, GitHub README).** `fps=1.0`, `max_frames=64`, `total_pixels=7,864,320`. No audio.
- **Adoption (MEASURED: HF API, 2026-10-24).** 8B: 1,278,583 downloads in the last month. 2B: 756,965. GitHub: 1,409 stars, last push 2026-06-23 (GitHub API).
- **Evidence.**
  - Model card: MMEB-V2 video overall 66.1, V-Ret 57.0, M-Ret 53.2.
  - WeMM's leaderboard table gives different numbers: 67.1, 58.7, 56.1.
  - WeMM Table 3: Vatex 68.5, MSR-VTT 70.6, YouCook2 54.7. That is on par with or above Gemini Embedding 2.
- **Fit.** The strongest local option. The reranker gives a second stage. Nothing leaves the machine. Running it on our Mac is unmeasured.
- URLs: https://huggingface.co/Qwen/Qwen3-VL-Embedding-8B, https://github.com/QwenLM/Qwen3-VL-Embedding

### 5. Mixedbread Wholembed v3 and Search stores

- **Product.** A multi-vector (late-interaction) model, released 2026-03-12. It is the default and only model for new Mixedbread stores, and indexes audio and video directly. How it segments is undisclosed.
- **Price (DOCUMENTED, mixedbread.com/pricing, fetched 2026-10-24).**
  - Metering: 1 video-minute counts as 24,000 content tokens.
  - Ingest: Fast $1.50/M tokens, High Quality $3/M.
  - Storage: $0.50/M tokens per month.
  - Queries: $4 per 1k semantic queries, $7.50 with rerank.
  - Plans: Starter has $5 of one-time credit; Scale costs $20 a month.
- **Evidence.** Vendor eval page (testing March 2026), NDCG@10:

  | Model | Average | MSR-VTT | DiDeMo | YouCook2 |
  |---|---|---|---|---|
  | Mixedbread | 66.97 | 64.4 | 72.3 | 64.22 |
  | GE2 | 62.74 | 67.6 | 68.11 | 52.5 |
  | Voyage | 54.72 | 63.3 | 66.82 | 34.04 |
  | @001 | 48.47 | 58.32 | 50.98 | 36.12 |

  Mixpeek's independent run: NDCG@10 0.757 on 37 of 60 queries, and best-in-class hard-negative scores (NDCG@1 1.000).
- **Fit.** `mgrep` is an agent-facing CLI (Apache-2.0, 4,423 stars, last push 2026-04-25, MEASURED GitHub API). Its documentation covers code, text, PDF and images. **Video through mgrep is not documented.** The upload is to cloud.
- URLs: https://mixedbread.com/blog/wholembed-v3, https://www.mixedbread.com/evals/video-retrieval, https://www.mixedbread.com/pricing

### 6. VideoDB (managed indexer)

- **Product.** A new "Understand -> Index -> Retrieve" API. SDK v0.5.0 shipped 2026-07-22 and the last push was 2026-10-07 (MEASURED GitHub API).
  - Analyzers: `spoken_words`, `vlm` scene captions, `object_detection` (labels, counts, boxes), `ocr` and `brand_detection` all produce timestamped artifacts.
  - `video.index()` turns chosen fields into semantic, filter or aggregate indexes.
  - Retrieval: `search`, `semantic_search`, `query`, `aggregate`. Results come back as playable stream URLs.
  - Segmentation: time-based or shot-based, with 1-5 frames per scene into the VLM.
  - RTStreams (live RTSP) are VLM-only, time-segmented.
- **Retrieval model.** Retrieval runs over **text artifacts** (captions and transcripts), not native video vectors.
- **Price.** Not public. `videodb.io/pricing` redirects to `/contact` (MEASURED, curl, 2026-10-24).
- **Fit.** The best-wired option for Claude: `claude mcp add --transport http videodb https://mcp.videodb.io/mcp`, plus the local `videodb-director-mcp`. The connector collects only tool-call arguments. Uploaded videos stay until you delete them.
- URLs: https://docs.videodb.io/pages/core-concepts/indexes-and-search.md, https://docs.videodb.io/pages/understand/quality-and-evaluation/latency-and-cost.md, https://docs.videodb.io/pages/mcp/connect.md, https://docs.videodb.io/pages/mcp/auth-and-privacy.md

### 7. Mixpeek (managed indexer)

- **Pipeline.** The "multimodal extractor" chunks with ffmpeg (time, scene or silence). Per segment it runs Whisper, E5-Large transcript vectors (1024 d), Gemini captions and OCR, and a multimodal vector. v1 uses Vertex @001 (1408 d). v2 uses Gemini Embedding 2 (3072 d, configurable to 1536 or 768). A "moment group" retrieval stage merges adjacent hits. Add-ons: faces (SCRFD and ArcFace), CLAP audio fingerprint, scrolling-text OCR.
- **Price (MEASURED: `curl https://api.mixpeek.com/v1/billing/pricing`, public, 2026-10-24).** Video base $0.05/min. Faces +$0.10/min. On-screen OCR +$0.10/min. Audio fingerprint +$0.01/min. Plans: Build $25/mo with a $10 pool; Scale $250/mo with a $100 pool. Storage $0.33/GB-month.
- **Fit.** Five scoped hosted MCP servers. The full server is `https://mcp.mixpeek.com/mcp` with 66 tools; read-only OAuth is `/app/mcp`. There is also a Claude Code skill. Mixpeek also authored the only independent embedding benchmark (entry 20).
- URLs: https://docs.mixpeek.com/docs/processing/extractors/multimodal.md, https://docs.mixpeek.com/docs/platform/billing.md, https://docs.mixpeek.com/docs/agent-integrations/mcp.md

### 8. Voyage multimodal-3.5 (MongoDB)

- **Model.** Released 2026-01-15, so its newest evidence is **older than 6 months**. Interleaved text, image and video in one backbone. Dims 256/512/1024 (default)/2048, with int8 and binary quantization options. Videos up to 20 MB and 32k tokens, where 1120 video pixels count as one token.
- **Price (DOCUMENTED, docs.voyageai.com/docs/pricing, fetched 2026-10-24).** $0.12/1M text tokens and $0.60/B pixels. Each video frame is priced as an image. The first 200M tokens and 150B pixels are free.
- **Evidence.** Google paper: 55.2 / 63.0 / 31.4. Mixedbread: 54.72 average. On both, it trails the top band.
- **Fit.** The only provider whose Weaviate module wires video (`video_fields`).
- URLs: https://docs.voyageai.com/docs/multimodal-embeddings, https://docs.voyageai.com/docs/pricing, https://docs.weaviate.io/weaviate/model-providers/voyageai/embeddings-multimodal

### 9. Tencent WeMM-Embedding (open)

- **Model.** 2B, 4B and 9B, built on Qwen3.5. HF createdAt 2026-08-25. Card license is "other", named apache-2.0. Output is 4096 d. No audio.
- **Evidence (self-reported).** MMEB-V2 video overall 74.3 for 9B (V-Ret 67.4, M-Ret 58.5). Vatex / MSR-VTT / YouCook2: 78.4 / 74.1 / 66.3. The same table lists closed leaderboard entries such as Octen-VL-Large at 76.0 video overall and Seed-1.6-Embedding at 67.7.
- **Adoption (MEASURED: HF API).** 2B: 15,832 downloads in the last month.
- **Fit.** The newest open state of the art claim. Not replicated by anyone else.
- URLs: https://arxiv.org/pdf/2608.24053, https://huggingface.co/tencent/WeMM-Embedding-9B

### 10. Meta Perception Encoder: PE-Core and PE-AV (open, Apache-2.0)

- **Releases.** PE-Core (2025-04) is a CLIP model for image and video retrieval. PE-AV and PE-A-Frame (2025-12-16) embed audio, video, audio+video and text jointly. PE-AV ships in 16-frame and all-frame variants. It is the encoder behind SAM Audio.
- **Evidence (repo table).** PE-AV-L all-frames averages 51.6 retrieval. VGGSound V->A 48.3, Valor T->V 35.1. PE-A-Frame gives frame-level audio event localization (AUROC).
- **Adoption (MEASURED).** HF pe-av-large: 22,825 downloads in the last month. Repo: 2,398 stars, last push 2026-04-13.
- **Freshness.** The newest release is **more than 6 months old**.
- **Fit.** The only open joint audio-visual embedding found. Useful for "find the moment the glass breaks".
- URLs: https://github.com/facebookresearch/perception_models, https://huggingface.co/facebook/pe-av-large

### 11. Jina embeddings v5 omni (small and nano)

- **Release.** 2026-05-12 (Elastic press release 2026-05-11). Frozen text backbone, with SigLIP2 and Whisper-large-v3 encoders joined by projectors. Small is 1024 d with 32k context. Nano is 768 d with 8k context. Video is fed as frames, optionally preceded by an audio segment.
- **License.** CC-BY-NC-4.0 for the weights. Commercial use goes through Elastic.
- **Price.** API price not found.
- **Evidence.** The vendor discloses the gap: MMEB video retrieval 27.82 against 58.73 for the best open baseline, and video overall 41.20 against LCO-7B at 47.41. The vendor says "temporal reasoning benefits more from end-to-end training".
- **Fit.** Choose it only if you are already on Elastic, for the text-compatible index.
- URLs: https://jina.ai/news/jina-embeddings-v5-omni-multimodal-embeddings-for-text-image-audio-and-video, https://ir.elastic.co/News--Events/news/news-details/2026/Elastic-Introduces-Jina-v5-Omni-Family-Two-Models-to-Power-Text-Image-Video-and-Audio-Search/default.aspx

### 12. Vertex multimodalembedding@001 (legacy)

- **Specs.** 1408 d by default (128/256/512 also available). `intervalSec` of at least 4: Plus is 4-8 s, Standard 8-15 s, and Essential 15 s or more (the default is 16). Only 2 min of content is analyzed per call. "Doesn't consider audio content". No deprecation notice as of 2026-10-22.
- **Evidence.** Bottom of every table: 54.9 / 57.9 / 34.9 in Google's paper, 48.47 average on Mixedbread's page.
- **Fit.** Still what Weaviate's Google module uses for video.
- URLs: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/embeddings/get-multimodal-embeddings

### 13. NVIDIA VSS blueprint v3.3 and Cosmos-Embed1

- **Blueprint.** The video-search workflow is labelled "alpha". It uses RTVI-Embed, based on Cosmos-Embed1 (default `Cosmos-Embed1-448p-anomaly-detection`), and SigLIP2 attribute vectors (1152 d). Elasticsearch is the store, fed through Kafka. The search profile needs 2-4 GPUs; L40S needs 4.
- **Agent wiring.** An MCP-based agent, plus agentskills.io skills in the repo.
- **Activity (MEASURED: GitHub API).** 1,941 stars, last push 2026-10-24.
- **Model.** Cosmos-Embed1: HF license "other". The 224p variant had 111,254 downloads in the last month.
- **Evidence.** No metrics. The docs list known false positives.
- **Fit.** For CCTV and live streams, not for a laptop.
- URLs: https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization, https://docs.nvidia.com/vss/latest/agent-workflow-search.html, https://huggingface.co/nvidia/Cosmos-Embed1-448p

### 14. Qdrant

- **Activity (MEASURED: GitHub API).** 35,220 stars, last push 2026-10-23.
- **Video support.** The docs now carry a Marengo 3.5 integration (512/256/128 d, cosine), plus Marengo 3.0 via Bedrock. It supports multivectors, late interaction and MUVERA, which suits Wholembed-style or per-frame vectors. A three-part video anomaly tutorial uses TwelveLabs and NVIDIA VSS.
- **Fit.** `mcp-server-qdrant` gives the agent a local MCP store.
- URLs: https://qdrant.tech/documentation/embeddings/twelvelabs/index.md, https://qdrant.tech/llms.txt

### 15. LanceDB and Geneva

- **Activity (MEASURED: GitHub API).** 11,756 stars, last push 2026-10-24.
- **Video support.** Blob columns store video bytes next to vectors. Geneva "chunkers" (scalar UDTFs) expand one video row into N clip rows with incremental refresh; the docs example uses 10 s fixed clips. There is a TwelveLabs Geneva tutorial.
- **Fit.** A Claude Code plugin: `/plugin marketplace add lancedb/lancedb-agent-plugins`. It is the embedded, serverless choice for a local index.
- URLs: https://docs.lancedb.com/geneva/udfs/scalar-udtfs.md, https://docs.lancedb.com/build-with-ai-agents.md, https://www.lancedb.com/blog/geneva-twelvelabs

### 16. Weaviate

- **Activity (MEASURED).** 16,908 stars, last push 2026-10-23.
- **Video support.**
  - `multi2vec-google`: `video_fields` and `video_interval_seconds` work only with `multimodalembedding@001`. The `gemini-embedding-2` path lists text, image, PDF and audio, with no video.
  - `multi2vec-twelvelabs` (added v1.38.9): **text and images only**. `videoFields` is stored but nothing reads it.
  - `multi2vec-voyageai`: supports video.
- URLs: https://docs.weaviate.io/weaviate/model-providers/google/embeddings-multimodal, https://docs.weaviate.io/weaviate/model-providers/twelvelabs/embeddings-multimodal

### 17. Milvus and Pinecone

- **Milvus** (46,463 stars, last push 2026-10-23, MEASURED). Has TwelveLabs video-search and video-similarity tutorials.
- **Pinecone.** Its model index still lists `Marengo-retrieval-2.6`, which is dead: Marengo 2.7 was sunset on 2026-03-30. Its video example uses Vertex.
- **Both** are plain vector stores here. Neither has a video-specific pipeline.
- URLs: https://milvus.io/docs/video_search_with_twelvelabs_and_milvus.md, https://docs.pinecone.io/models/marengo-retrieval-2-6.md

### 18. Google DeepMind VideoPrism and VideoPrism-LvT (open, Apache-2.0)

- **Model.** Video encoders (B and L) released 2025-06. Video-text encoders (LvT-B 248M, LvT-L 580M) released 2025-07-16. Inputs are (frames, 288, 288, 3), trained at 16 frames (B) and 8 frames (L). Outputs include **16x16 spatial tokens per frame** for spatiotemporal use, plus global embeddings in LvT.
- **Status.** JAX only; PyTorch is on the to-do list. Recent commits are maintenance only (2026-10-20, MEASURED GitHub API).
- **Freshness.** The newest model is **more than 6 months old**.
- **Fit.** The open encoder whose spatial token grid is documented for localization research.
- URLs: https://github.com/google-deepmind/videoprism, https://huggingface.co/google/videoprism-lvt-large-f8r288

### 19. Frame-CLIP baselines: SigLIP 2, X-CLIP, InternVideo2, LanguageBind

- **SigLIP 2** (2025-02, Apache, 711,756 downloads in the last month). Strong for frame and keyframe lookup.
- **Mixpeek's independent run** found frame-averaged video search weak: X-CLIP-B 0.470, SigLIP 2 SO400M 0.325, InternVideo2-6B 0.302 NDCG@10.
- **InternVideo.** The family moved on to InternVideo-Next (2025-12) and InternVideo3 (2026-06, an 8B instruct MLLM and video agent, **not** an embedding model).
- **LanguageBind.** The repo was last pushed 2024-03-25 and the HF video model last modified 2024-02. It is stale.
- URLs: https://mixpeek.com/blog/video-embedding-benchmark-2026, https://github.com/OpenGVLab/InternVideo, https://github.com/PKU-YuanGroup/LanguageBind

### 20. Benchmarks for this layer

- **MMEB-V2 video split.** 18 tasks: classification, QA, retrieval (5) and moment retrieval (3), scored by Hit@1. It is the leaderboard most embedding papers cite. MMEB-V3 adds audio and agent-retrieval tasks. Scores differ by source, for example the Qwen3-VL card against WeMM's leaderboard table, so compare only within one table.
- **Text-to-video NDCG@10 on Vatex, MSR-VTT, YouCook2 and DiDeMo.** The common external comparison.
- **Mixpeek benchmark** (2026-03-12, updated 2026-07-11). 20 Pexels CC0 clips of 10 s or less and 60 graded queries. Code is open. It is the only cross-vendor run made by someone other than the vendors; Mixpeek still sells a pipeline built on one of the models it tested. The promised re-run with Marengo 3.0 and Nova was not found.
- URLs: https://huggingface.co/datasets/TIGER-Lab/MMEB_Raw_Video/blob/main/README.md, https://mixpeek.com/blog/video-embedding-benchmark-2026

## 4. Takeaways for our agent (INFERRED unless cited)

1. **What an index buys an agent with no video input.** Embeddings and indexes buy *where*, not *what*. Use them only when the corpus is too long or too many videos to sheet-scan. Our 47-min single-video probe did not need one. A 100-hour library would.
2. **Best hosted visual track per dollar: Gemini Embedding 2.** About $0.76-$2.84/hr. Chunk it yourself, and pair it with a transcript index, because it has no audio on the Gemini API.
3. **Best hosted option that segments for you and embeds audio: Marengo 3.5.** Run a test call first, because tokens per minute are unpublished.
4. **Best fully local stack.** Qwen3-VL-Embedding plus its reranker over 1 fps clips, in LanceDB or Qdrant, with PE-AV added for non-speech sound. Apache-2.0, no egress. Throughput on the Mac is unmeasured and should be measured before adoption.
5. **Zero-code option for Claude Code: VideoDB's hosted MCP.** Then Mixpeek's MCP. Both upload the video, and VideoDB's retrieval is over VLM captions, not video vectors.
6. **Do not build event search on averaged keyframe CLIP vectors.** The one independent benchmark puts it at less than half the API models' NDCG@10.
7. **Check integrations against the primary docs.** Weaviate's TwelveLabs module ignores video. Weaviate's Gemini Embedding 2 path has no video. Pinecone lists a dead Marengo.

## 5. Not found, dead or unverifiable

- **Marengo 2.7.** Sunset 2026-03-30 (TwelveLabs release notes). Pinecone's `Marengo-retrieval-2.6` page is therefore stale.
- **Weaviate.** Video through `multi2vec-twelvelabs` is not supported (`videoFields` is ignored). Video through Weaviate's `gemini-embedding-2` path is not listed.
- **Cohere Embed v5** (2026-09-30). Video input not found; the aggregators list only text and images.
- **TwelveLabs Marengo 3.5 tokens per video-minute.** Not published.
- **VideoDB public pricing.** Not found; the pricing URL redirects to contact.
- **Seed-1.6-Embedding (`doubao-embedding-vision`) video price.** Not found. It appears on MMEB-V2 at video overall 67.7.
- **Jina v5 omni API price, and its frame or fps settings.** Not found.
- **Mixpeek's promised re-run** with Marengo 3.0 and 3.5 and Nova. Not found.
- **Independent replication** of the Qwen3-VL-Embedding or WeMM video numbers. Not found.
- **LanguageBind.** Stale: last push 2024-03-25.
- **HKUDS/VideoRAG** (3,422 stars, last push 2026-03-18, license NOASSERTION, MEASURED GitHub API). A research RAG library, not evaluated here.
