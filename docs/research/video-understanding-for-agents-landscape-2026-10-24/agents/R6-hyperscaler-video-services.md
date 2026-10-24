# R6: Hyperscaler video-AI services an agent can call (as of 2026-10-24)

Axis: Azure AI Content Understanding (video), Azure AI Video Indexer, AWS Bedrock Data Automation (video), Amazon Nova 2 and TwelveLabs on Bedrock, Amazon Rekognition Video, Google Cloud Video Intelligence API, Gemini on Google's Vertex AI (now "Gemini Enterprise Agent Platform"), Oracle OCI Vision, and IBM.

Agent context: Claude Opus 5.5 in Claude Code has no video or audio input; Claude Code clamps images to 2000 px (prior F1). Every service below runs on the hyperscaler's side and returns text or JSON, with some optionally returning keyframes. Claude then reasons over that text and those few images.

## How the numbers were obtained

- **Prices: MEASURED from the vendors' own machine-readable price feeds, not from marketing pages.**
  - Azure: Retail Prices API (`curl https://prices.azure.com/api/retail/prices?...productName eq 'Azure Content Understanding'` / `'Azure Video Indexer'`), queried 2026-10-24.
  - AWS: the metered-unit JSON that backs the pricing pages (`curl https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/{bedrock,bedrockfoundationmodels,rekognition}/USD/current/*.json`). The hashed price keys were resolved against the `priceOf!` tokens in the HTML of aws.amazon.com/bedrock/pricing. Feed publication dates: Bedrock 2026-10-16, Bedrock foundation models 2026-10-12, Rekognition 2026-09-11.
  - Oracle: `curl https://apexapps.oracle.com/pls/apex/cetools/api/v1/products/?currencyCode=USD`.
  - Google: the rendered pricing pages (`curl` of cloud.google.com/products/video-intelligence/pricing and the Agent Platform pricing page), fetched 2026-10-24.
- **Capabilities and limits: DOCUMENTED** from vendor docs fetched 2026-10-24. Page dates are noted where shown.
- **Cost per hour of video: ESTIMATED.** The method is plain arithmetic on the measured per-unit prices, with the assumptions stated in each row.
- **Independent accuracy evidence:** I found **no** independent head-to-head evaluation of Content Understanding, BDA, Video Indexer or Rekognition on any public benchmark. A WebSearch on 2026-10-24 returned only vendor material. The only third-party numbers on this axis are Gemini's video-benchmark scores, already collected in prior F2.

## Narrative

1. **The legacy "per-feature" video APIs are being retired. The replacement is "LLM over sampled frames plus transcript".**
   - Google: Video Intelligence API deprecated on **2026-09-14**, with shutdown on **2027-09-14**. Google recommends migrating to Gemini.
   - AWS: Rekognition Streaming Video closed to new customers on **2026-04-30**. People Pathing ended on **2025-10-31**.
   - Microsoft: Azure Video Indexer is not deprecated, but its last release-notes entry is March 2026 (GPT-5 support for summarization). Microsoft's active video investment is Content Understanding: GA API 2025-11-01, preview 2026-06-01, and docs updated October 2026.
   - An agent builder starting today should treat Rekognition Video, Google Video Intelligence and Video Indexer as **specialist signal sources**: frame-accurate shots, face and celebrity IDs, bounding-box tracking, clapperboards. None of them is the primary understanding layer.

2. **Three hyperscaler products now package video as an "agent-ready" text artefact, and they are cheap.**
   - **Azure Content Understanding `prebuilt-video`**, content extraction only: a diarized WebVTT transcript, shot boundaries and keyframes for **$1.00 per video-hour** (MEASURED meter). The `prebuilt-videoSearch` RAG analyzer adds per-segment natural-language descriptions. Microsoft's own illustrative cost is **$3.33/h** with GPT-5.2.
   - **AWS BDA video standard output**: shots with SMPTE timecodes and frame indexes, chapters with summaries, transcript, per-frame OCR with bounding boxes, logos, moderation and IAB categories. The price is **$0.050/min = $3.00/h**; custom blueprints cost **$0.084/min = $5.04/h** (MEASURED, feed of 2026-10-16).
   - **Gemini on Vertex** goes further, with native video and audio in one model. It has a new `media_processing="AGENTIC"` mode, in which the model navigates the video itself (zooming to timestamps, reading small text) instead of tokenizing every frame. By token arithmetic, Gemini is the cheapest per hour, but it is a model, not an indexer.

3. **Every hyperscaler service samples about 1 fps at low resolution.** That is the same ceiling our probe hit:
   - Content Understanding: about 1 fps, frames resized to **512 x 512**, and "small text or distant objects can be lost".
   - Nova 2 Lite: 1 fps up to 16 min, then **960 frames total**, resized with distortion to **672 x 672**, and **no audio**.
   - Gemini: 1 fps by default, adjustable through `videoMetadata.fps`. It defaults to **70 tokens per frame** on Gemini 3+ models, or 280 at HIGH.
   - BDA: does not publish its sampling rate. It accepts 1-60 fps input up to 7680 px.
   - For screen-text-heavy video (slides, code, UIs), prior findings said to keep 1080p and read it ourselves. None of these services lifts that ceiling. They cut the transcript-and-structure cost, not the OCR-fidelity problem. (INFERRED from the documented limits plus our prior measurement that downscaling to 1280 px loses 5-16 points of OCR.) Exceptions: BDA's and Rekognition's per-frame OCR return word-level boxes, but neither documents the sampling density.

4. **Agent plumbing is thin at all three clouds. There is no first-party MCP server for video understanding.**
   - AWS **removed** its `aws-bedrock-data-automation-mcp-server` from awslabs/mcp on **2026-04-17**; the commit message reads "-> boto3 API" (MEASURED via the GitHub API).
   - Microsoft's `Azure-Samples/azure-content-understanding-mcp-server` has 4 stars, was last pushed 2025-05-12 (stale), and the official `microsoft/mcp` repo has no Content Understanding or Video Indexer tool (tree search MEASURED). The only Video Indexer MCP I found is community-built and stale (benbakhar/videoindexer-mcp, 4 stars, 2025-04-20).
   - I found no first-party Google MCP for Gemini video understanding (GitHub search, 2026-10-24).
   - The practical route from Claude Code is therefore a **CLI or SDK call wrapped in a skill**. Examples: `aws bedrock-data-automation-runtime invoke-data-automation-async`, or the generic `aws-api-mcp-server`, last commit 2026-09-30; `az rest`/`curl` against the Content Understanding REST API, or the `azure-ai-contentunderstanding` Python SDK, 1.1.0 GA with 1.2.0b3 on 2026-08-11; and `google-genai` against Vertex. Each writes JSON or Markdown to disk for Claude to Read.

5. **Data residency is the hyperscalers' real differentiator against the startups.**
   - Content Understanding stores data at rest in the chosen region (16 regions carry the video meter) and lets you pick the processing location. The LLM leg follows your Foundry deployment type.
   - BDA keeps processing within a geography (US, EU, APAC) unless you opt into `global.data-automation-v1`. Note that BDA *requires* cross-region inference, so requests can leave the source region within the geography.
   - Gemini's Global endpoint "may be processed in any Google Cloud location". US and EU jurisdictional multi-region endpoints keep ML processing in that geography, and non-global endpoints cost about 10 % more.
   - Video Indexer has an **Azure Arc** edition that runs on-premises on Kubernetes. It is the only hyperscaler video indexer here that can run without the video leaving the site.
   - If the operator runs Opus 5.5 through Bedrock, Vertex or Foundry, the whole pipeline can stay inside one cloud account and geography (INFERRED from the documented residency controls).

6. **Pricing is moving underneath builders.**
   - Gemini 3.6/3.7/3.8 Flash introductory pricing of $0.75/$3.75 per 1M tokens ends **2026-12-31** and doubles to $1.50/$7.50.
   - Gemini 4 Argon promotional pricing of $2/$10 ends **2026-11-30** and becomes $4/$20.
   - Content Understanding's GPT-4.1-family analyzers face that model family's retirement in October 2026. Microsoft recommends gpt-5.2. (DOCUMENTED, via a secondary search summary of Microsoft's migration page.)

## Comparison table

Costs per video-hour are USD, list price, US region. "Est." marks arithmetic on measured unit prices.

| # | Service | What comes back | Sampling / limits | $/video-hour | Residency | Claude Code route | Status |
|---|---|---|---|---|---|---|---|
| 1 | Gemini on Vertex / Agent Platform (Gemini 3.x Flash, Gemini 4 Argon) | Free-form or JSON answers, timestamps (MM:SS or MM:SS.sss), chapters; agentic navigation mode | 1 fps default, custom fps, clipping; 70 tok/frame (HIGH 280); about 45 min with audio / 1 h without per video; up to 10 videos per prompt | Est. $0.11 (3.5 Flash-Lite) to $0.28 (3.8 Flash intro) to $1.47 (Gemini 4 Argon post-promo) for input, assuming about 367K tok/h | Global, or US/EU jurisdictional endpoints | `google-genai` script as a skill; or Claude on Vertex in the same project | Active; docs updated 2026-10-22 |
| 2 | Azure AI Content Understanding (video) | WebVTT transcript with diarization, shots (`cameraShotTimesMs`), keyframes, segment descriptions, custom fields, custom segmentation, face grouping add-on | about 1 fps, 512x512; 4 GB / 2 h by URL, 200 MB / 30 min inline; input up to 1080p | $1.00 extraction-only (MEASURED); $1 extraction + $1 contextualization + LLM tokens; MS example $3.33 | Data at rest in region; 16 regions with the video meter | REST/SDK script; stale sample MCP | GA 2025-11-01; preview 2026-06-01 |
| 3 | AWS Bedrock Data Automation (video) | Shots (SMPTE, frame index), chapters with summaries, full summary, transcript, per-frame OCR with boxes, logos, moderation, IAB; custom blueprints | up to 240 min, 10 GB, 224-7680 px, 1-60 fps input | $3.00 standard / $5.04 custom (MEASURED) | Geography-scoped CRIS (US/EU/APAC); global opt-in | AWS CLI/boto3 script; generic aws-api-mcp-server | Active; BDA MCP removed 2026-04-17 |
| 4 | TwelveLabs Pegasus 1.5 / Marengo 3.0 on Bedrock | Video-LLM text (Pegasus); video+audio embeddings (Marengo) | per TwelveLabs limits (see prior F3) | Pegasus $1.76 input + $7.50/1M out; Marengo 3.0 $2.52 video (+$0.50 audio) (MEASURED) | Bedrock region / CRIS; Marengo 3.0 in 3 regions | Bedrock InvokeModel script | Pegasus 1.6 (2026-10-06) not on Bedrock yet |
| 5 | Azure AI Video Indexer | Shots, scenes, keyframes, editorial shot types, OCR, faces, celebrities (gated), labels, tracked objects, observed people with boxes, clothing, slates, transcript, translation, 16-speaker diarization, audio effects, topics, LLM summary, "Prompt Content" LLM-ready text | 2 GB upload / 30 GB URL; 6 h | Basic $3.46, Standard $6.84, Advanced $11.40 for video+audio (MEASURED) | 45 regions on the price meter; **Arc edge edition** | REST script; Prompt Content API → text | Maintained, slowing (last note 2026-03) |
| 6 | Amazon Nova 2 Lite / Pro / Omni (Preview) | Model answers over frames | Lite: 1 fps up to 16 min, then 960 frames total; 672x672; **no audio**; 1 GB via S3 | Est. Lite about $0.08 input (276K tok × $0.30/1M) | Bedrock region / CRIS | Bedrock Converse script | Lite GA; Pro and Omni preview |
| 7 | Amazon Rekognition Video (stored) | Labels with boxes, faces, face search, celebrities, moderation, text, segments (shots + technical cues) | 10 GB, 6 h, H.264 MP4/MOV, 20 concurrent jobs | $6.00 per feature; $3.00 for segment detection (MEASURED) | Regional | AWS CLI script | Streaming closed to new customers 2026-04-30 |
| 8 | Google Cloud Video Intelligence API | Labels, shots, explicit content, speech, object tracking, text, logos, faces, persons, celebrities | per-feature | $3-9 per feature (first 1,000 min/month free) | Regional | gcloud/REST | **Deprecated 2026-09-14; shutdown 2027-09-14** |
| 9 | Oracle OCI Vision stored video (+ OCI GenAI Gemini 2.5) | Labels, objects, text, faces with timestamps and boxes | 20 GB, 10 h | $6.00 after 1,000 free min; streaming $9.00 (MEASURED) | OCI region | OCI CLI script | GA 2024-12; little 2026 activity |

## Entries (ranked by importance to an agent builder)

### 1. Gemini video understanding on Vertex AI / "Gemini Enterprise Agent Platform" (Google Cloud)

**What it gives an agent**

- A second model that actually watches the video (frames plus audio) and answers in text or JSON with timestamps.
- Clipping (`videoMetadata` start and end offsets) and custom fps.
- The new **agentic video understanding** mode (`media_processing="AGENTIC"`), in which the model "dynamically navigate[s] video content instead of having to process every frame statically". Google pitches it for "long-form video Q&A", "fine-grained visual inspection: zoom into specific timestamps ... reading small on-screen text", "multi-video comparison" and "video-powered agents" with context preserved across turns through opaque `step_list` steps.
- Agentic mode is listed for Gemini 4 Argon and Gemini 3.5–3.8 Flash and Flash-Lite.

**Modality path**

- Native video+audio into the model.
- File API sampling: 1 fps, audio at 1 Kbps mono, timestamps every second.
- Gemini 3+ default is 70 tokens per frame (MEDIUM and LOW are both 70; HIGH is 280). Pre-3 models used 258 per frame, or 66 at low.
- Per video: about 45 min with audio, or about 1 h without; up to 10 videos per prompt.
- Sources: GCS URI, YouTube URL or inline base64.

**Deployment:** cloud only. Endpoints are Global or jurisdictional (US/EU multi-region); "submitted to a global endpoint may be processed in any Google Cloud location".

**Pricing** (Agent Platform pricing page, fetched 2026-10-24; input price per 1M tokens covers text, image, video and audio):

| Model | Input / output per 1M | Note |
|---|---|---|
| Gemini 3.8 / 3.7 / 3.6 Flash | $0.75 / $3.75 | Introductory, through 2026-12-31; $1.50 / $7.50 from 2027-01-01 |
| Gemini 3.5 Flash-Lite | $0.30 / $2.50 | |
| Gemini 3.5 Flash | $1.50 / $9.00 | |
| Gemini 3.1 Pro Preview | $2 / $12 | |
| Gemini 4 Argon | $2 / $10 promo through 2026-11-30, then $4 / $20 | |

Non-global endpoints cost about 10 % more.

**Cost per video-hour (ESTIMATED)**

- 3600 frames × 70 tokens = 252K, plus about 115K audio tokens (assuming the 32 tokens/s documented for earlier Gemini models; not re-verified for 3.x/4), giving about 367K input tokens per hour.
- Input cost per hour by model:
  - 3.5 Flash-Lite: about $0.11
  - 3.8 Flash (introductory): about $0.28
  - Gemini 4 Argon after the promotion: about $1.47
- Output is extra. Agentic mode claims fewer tokens.

**Claude fit**

- Wrap `google-genai` (Vertex mode) in a skill script that uploads to GCS, calls the model with a schema, and writes JSON for Claude to Read.
- If Opus 5.5 itself runs on Vertex, the video never leaves the GCP project.
- The video does egress to Google; Claude receives only text.
- Community Claude Code plugins that use the consumer Gemini API exist (e.g., jordanrendric/claude-video-vision, MEASURED pushed 2026-10-14; covered on another axis). None targets Vertex specifically.

**Maturity**

- The docs page was "Last updated 2026-10-22 UTC".
- Vertex AI docs now redirect to `docs.cloud.google.com/gemini-enterprise-agent-platform/...` (MEASURED via the curl effective URL). Treat the product rename as DOCUMENTED.
- Gemini 3.7 Flash model card: August 2026.

**Evidence**

- Vendor: the Gemini 3.7 Flash model card reports LVBench 85.4 %.
- Third-party (prior F2): Gemini-3-Pro Video-MME-v2 level-2 temporal 50.0 vs human 91.1; LVBench 76.2 (Qwen3.5 card); VLM4D 62.0 for Gemini-2.5-Pro vs human 98.8.
- No independent evaluation of agentic mode found.

**Spatial and motion**

- Google advises raising fps for "fast-action understanding or high-speed motion tracking", and warns that "fast action sequences might lose detail due to the 1 FPS sampling rate".
- Sub-second timestamps (MM:SS.sss) apply only above 1 fps.
- Independent benchmarks show large temporal and spatial gaps to humans (F2).

URLs: https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/capabilities/video-understanding , https://cloud.google.com/gemini-enterprise-agent-platform/generative-ai/pricing , https://docs.cloud.google.com/gemini-enterprise-agent-platform/resources/data-residency , https://deepmind.google/models/model-cards/gemini-3-7-flash/

### 2. Azure AI Content Understanding: video analyzers (Microsoft Foundry Tools)

**What it gives an agent:** "RAG-ready" Markdown plus JSON, in two stages.

- **Content extraction:**
  - WebVTT transcript with diarization and multilingual per-phrase locale.
  - Keyframes.
  - Shot detection (`cameraShotTimesMs`).
  - Sentence-level timestamps when `returnDetails: true`.
- **Field extraction:** a generative model fills a `fieldSchema` per segment (types: generate or classify). Custom segmentation from a natural-language `contentCategories` prompt; for example, "segment a news broadcast into stories".
- Add-ons: face grouping, plus face transaction and storage meters.
- The 2026-06-01-preview adds an "agentic" workflow at the advanced contextualization rate. It is described for analyzers generally; I did not verify that it applies to video.

**Modality path:** server-side text index.

- About 1 fps; frames resized to 512 x 512 for the model ("Rapid motions or single-frame events might be missed"; "Small text or distant objects can be lost").
- Only speech is transcribed: music and sound effects are ignored.
- Input 320x240 to 1920x1080. Up to 4 GB / 2 h by URL, or 200 MB / 30 min inline.
- Throughput: 4 video-hours per minute per resource.
- The LLM is your own Foundry deployment: GPT-4o through gpt-6.1-sol are listed. **No Claude models are listed** as Content Understanding generative models.

**Pricing** (MEASURED, Azure Retail Prices API, westus, 2026-10-24):

| Meter | Price |
|---|---|
| Video Content Extraction | $1.00/hour (effective 2025-12-01) |
| Std Contextualization | $0.001/1K tokens (1M tokens per video-hour, so $1/h) |
| Add-On Face Grouping (video) | $2.00/hour |
| Legacy "Video Field Extraction" | $9.90/hour (2024-12 preview meter, still listed) |

- LLM tokens are billed on the Foundry deployment.
- Microsoft's worked example: 1 h of video on `prebuilt-videoSearch` with GPT-5.2 costs **$3.33** (pricing-explainer, dated 2026-10-07).

**Deployment and residency:** cloud only, in 12 documented regions; the video meter is priced in 16. "All data at rest is stored in the selected region", and you can "specify the processing location".

**Claude fit**

- A REST or Python SDK call (`azure-ai-contentunderstanding` 1.1.0 GA; 1.2.0b3 on 2026-08-11, MEASURED via PyPI) wrapped in a skill.
- The keyframes in the output can be fed to Claude's Read as images. That makes the cheapest hyperscaler path to "transcript + shot list + keyframes" $1/h, extraction only (INFERRED).
- Keyframe resolution is not documented. The 512 px limit applies to frames sent to the model.
- Microsoft's sample MCP server is stale: 4 stars, last pushed 2025-05-12.
- The video egresses to Azure.

**Maturity:** GA API 2025-11-01; preview 2026-06-01. Docs updated 2026-10-19 to 2026-10-21. Older preview APIs were retired by 2026-07-15.

**Evidence:** vendor claims only; no independent evaluation found.

**Spatial and motion:** the vendor claims "segment-based multi-frame analysis" to "identify actions, events". No bounding boxes or tracking for video objects are documented. There is no independent evidence.

URLs: https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/video/overview , https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/service-limits , https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/pricing-explainer , https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/language-region-support , https://azure.microsoft.com/en-us/pricing/details/content-understanding/

### 3. Amazon Bedrock Data Automation (BDA): video modality (AWS)

**What it gives an agent:** standard output JSON containing:

- Metadata: fps, codec, duration, dimensions.
- `shots[]`: SMPTE timecodes, millisecond and frame indexes, confidence, chapter links.
- `chapters[]`: shot indices plus a generated summary.
- A full-video summary that tries to name speakers from audio or slide text.
- A transcript with speaker identification.
- Per-frame `text_words` with bounding boxes and polygons.
- Logo detection with boxes (off by default).
- 7-category content moderation, and IAB taxonomy (24 L1 / 85 L2).

Custom output uses blueprints (natural-language field definitions; one video blueprint per project). A Data Automation Library adds custom vocabulary for audio and video. Knowledge Bases integration covers RAG.

**Modality path:** server-side extraction plus LLM summaries.

- Up to **240 min**, 10 GB, MP4/MOV/AVI/MKV/WEBM (H.264/H.265/VP8/VP9/AV1/ProRes), 224-7680 px, input 1-60 fps.
- Only one audio track; subtitle files are not used.
- The internal sampling rate is not documented.

**Pricing** (MEASURED, AWS metered-unit feed published 2026-10-16; identical in all 13 listed regions):

| Output | Per minute | Per hour |
|---|---|---|
| Video standard output | $0.050 | $3.00 |
| Video custom output | $0.084 | $5.04 |
| Audio standard / custom | $0.006 / $0.009 | |

**Deployment and residency:** cloud only. BDA *requires* cross-region inference. Geographic profiles (`us.`, `eu.`, ...) keep requests in the geography; `global.data-automation-v1` is opt-in. "Requests and output results may move outside of your primary Region."

**Claude fit**

- `aws bedrock-data-automation-runtime invoke-data-automation-async`, then poll, then read the S3 JSON. Wrap this in a skill, or use the generic awslabs `aws-api-mcp-server` (last commit 2026-09-30, MEASURED).
- The dedicated `aws-bedrock-data-automation-mcp-server` was **removed 2026-04-17** (deprecated in favour of the boto3 API; MEASURED from the commit).
- If Opus 5.5 runs on Bedrock, the stack is single-cloud.

**Maturity:** GA March 2025. The 2026 doc set includes Library and custom vocabulary pages. 9.8K-star awslabs/mcp has dropped it.

**Evidence:** vendor claims only ("industry-leading accuracy", with no numbers).

**Spatial and motion:** frame-accurate shot boundaries; OCR and logo bounding boxes with timestamps. No object tracking or action recognition is claimed. There is no independent evidence.

URLs: https://docs.aws.amazon.com/bedrock/latest/userguide/bda-ouput-video.html , https://docs.aws.amazon.com/bedrock/latest/userguide/bda-limits.html , https://docs.aws.amazon.com/bedrock/latest/userguide/bda-cris.html , https://docs.aws.amazon.com/bedrock/latest/userguide/bda-library.html , https://aws.amazon.com/bedrock/pricing/ , https://github.com/awslabs/mcp

### 4. TwelveLabs Pegasus and Marengo served through Amazon Bedrock

**What it gives an agent:** the TwelveLabs video-LLM (Pegasus) and multimodal video embeddings (Marengo), billed on the AWS invoice under Bedrock IAM and VPC controls. This entry extends prior F3, which covered the TwelveLabs-direct API and plugin.

**Pricing** (MEASURED, Bedrock foundation-models feed published 2026-10-12):

| Model | Video input | Other |
|---|---|---|
| Pegasus 1.2 and 1.5 | $0.00049/s ($1.764/h) | $7.50 per 1M output tokens |
| Marengo Embed 3.0 | $0.0007/s video ($2.52/h) | $0.00014/s audio ($0.50/h); only us-east-1, eu-west-1 and ap-northeast-2 |

**Notable:** the Bedrock pricing page lists Pegasus 1.2 and 1.5, but **not Pegasus 1.6**, which TwelveLabs launched 2026-10-06 (MEASURED from the page HTML).

**Claude fit:** Bedrock InvokeModel script. The video stays in AWS.

**Evidence:** vendor claims only. TwelveLabs' motion claims are in F3.

URLs: https://aws.amazon.com/bedrock/pricing/ (TwelveLabs section)

### 5. Azure AI Video Indexer (Microsoft)

**What it gives an agent:** the broadest classic insight catalogue of any service here.

- **Video models:**
  - Shots, scenes, keyframes, black frames, rolling credits.
  - Editorial shot type: wide, close-up and so on.
  - OCR and textual logos.
  - Face detection and grouping; celebrity and account face ID (Limited Access).
  - Labels.
  - **Object detection with tracking**: re-recognised when an object returns to frame.
  - **Observed people with bounding boxes**, plus matched faces and clothing.
  - Slates and clapperboards.
- **Audio models:**
  - Transcription in 50+ languages, translation and captions.
  - Diarization up to 16 speakers.
  - Audio effects: siren, laughter, gunshot and so on (advanced preset).
  - Emotions from text.
- **Cross-modal:** topics, entities, keywords and sentiment.
- **LLM layer:**
  - Textual video summarization through your Azure OpenAI deployment, including GPT-5 to 5.2 (March 2026).
  - The **Prompt Content API**, which turns insights into "prompt-ready" text in Summarized or Full style for "Q&A, RAG and search". That is the closest thing to an agent hand-off.

**Limits:** 2 GB upload or 30 GB by URL; 6 h (12 h for basic audio).

**Pricing** (MEASURED, Azure Retail Prices API, eastus, 2026-10-24; most regions, with Switzerland, Norway and Gov higher):

| Preset | Video per min | Audio per min | Combined per hour |
|---|---|---|---|
| Basic | $0.045 | $0.0126 | about $3.46 |
| Standard | $0.09 | $0.024 | $6.84 |
| Advanced | $0.15 | $0.04 | $11.40 |

These match prior P2. The trial account includes 2,400 free minutes.

**Deployment:** cloud, or **Azure Arc-enabled edge** on any Kubernetes. The Arc edition offers basic presets (transcription, translation, captioning, keyframes, object detection, scenes and shots, summarization with Phi-3.5), live-stream custom detections from natural language, and is suited to "strict data residency". The price meter exists in 45 Azure regions.

**Claude fit:** REST script, `Prompt Content` → text file → Claude. The only MCP is community and stale (benbakhar/videoindexer-mcp, 4 stars, 2025-04-20). The video egresses to Azure unless you use Arc.

**Maturity:** the last release-notes entry is **March 2026**; before that, May 2025. The pace has slowed sharply since 2024. The overview page was updated 2026-09-11. Flagged: there have been no new features for more than 6 months.

**Evidence:** vendor claims only.

**Spatial and motion:** the vendor claims object tracking across frames and observed-people bounding boxes with timestamps. There is no independent evidence.

URLs: https://learn.microsoft.com/en-us/azure/azure-video-indexer/video-indexer-overview , https://learn.microsoft.com/en-us/azure/azure-video-indexer/release-notes , https://learn.microsoft.com/en-us/azure/azure-video-indexer/avi-support-matrix

### 6. Amazon Nova 2 (Lite GA; Pro and Omni preview) on Bedrock

**What it gives an agent:** Amazon's own model reading video frames, answering questions and summarizing, through the Bedrock Converse API.

**Modality path:**

- Visual frames only: "No audio support ... Audio tracks in videos are not processed" (Nova 2 Lite doc).
- 1 fps up to 16 min, then a fixed 960 frames; every frame is resized with distortion to **672 x 672**.
- About 288 tokens per frame (276,480 tokens for 960 frames).
- 25 MB inline, or 1 GB from S3.
- AWS recommends under 1 h for low motion and under 16 min for high motion.
- Nova 2 Omni (Preview) is priced with separate video and audio input meters. I did not verify that it fuses a video's audio track.

**Pricing** (MEASURED, Bedrock feed, us-east-1): Nova 2 Lite $0.30 in / $2.50 out per 1M; Nova 2 Omni video input $0.30/1M and audio $1.00/1M; Nova 2 Pro video input $1.25/1M.

**Cost estimate:** about $0.08 of input per video-hour on Lite (ESTIMATED: 276K tokens × $0.30).

**Claude fit:** a cheap pre-pass inside AWS. It does not replace the transcript, because it has no audio.

**Evidence:** vendor claims only. The docs themselves warn of "limited spatial reasoning" and that "people identification" is not supported.

URLs: https://docs.aws.amazon.com/nova/latest/nova2-userguide/using-multimodal-models.md , https://aws.amazon.com/bedrock/pricing/

### 7. Amazon Rekognition Video (stored video)

**What it gives an agent:** asynchronous S3 jobs returning timestamped JSON:

- Labels with bounding boxes.
- Faces, face search against collections, celebrity recognition.
- Content moderation and text detection.
- **Segment detection**: frame-accurate shots plus technical cues such as black frames, color bars and end credits.

**Limits:** 10 GB, 6 h, H.264 MP4/MOV, 20 concurrent jobs.

**Pricing** (MEASURED, Rekognition feed published 2026-09-11, us-east-1):

| Feature | Per minute | Per hour |
|---|---|---|
| Label, Face, Person tracking, Celebrity, Moderation, Face search (each) | $0.10 | $6.00 |
| Shot or technical-cue detection | $0.05 | $3.00 |
| Streaming | $0.12 | |

**Status:**

- Streaming Video and Bulk Image Analysis closed to new customers on **2026-04-30**.
- People Pathing (`StartPersonTracking`) ended **2025-10-31**.
- Stored-video APIs are unaffected.

**Claude fit:** an AWS CLI job script. Useful when an agent needs *who* (face or celebrity ID) or *exact cut frames*. It provides no semantic understanding.

**Evidence:** vendor only.

URLs: https://docs.aws.amazon.com/rekognition/latest/dg/rekognition-availability-changes.html , https://docs.aws.amazon.com/rekognition/latest/dg/limits.html , https://aws.amazon.com/rekognition/pricing/

### 8. Google Cloud Video Intelligence API: DEPRECATED

**Status:** "Starting on September 14, 2026, Video Intelligence API is officially deprecated ... You can continue using Video Intelligence API until September 14, 2027, when it will be shut down. We recommend migrating to Gemini" (release-notes banner, fetched 2026-10-24).

**Outputs:** labels, shots, explicit content, speech transcription, object tracking with boxes, text, logos, faces, person detection, celebrities. Emotion labels already return UNKNOWN.

**Pricing** (stored video, page fetched 2026-10-24): first 1,000 min/month free per feature, then:

| Feature | Per minute |
|---|---|
| Label, explicit content, face, person, celebrity (each) | $0.10 |
| Shots | $0.05 |
| Speech | $0.048 |
| Object tracking, text, logo (each) | $0.15 |

Two lower volume-discount columns exist. Streaming costs $0.12–0.17.

**Claude fit:** do not build on it.

URLs: https://docs.cloud.google.com/video-intelligence/docs/release-notes , https://cloud.google.com/products/video-intelligence/pricing

### 9. Oracle OCI Vision: stored video analysis (plus Gemini on OCI Generative AI)

**What it gives an agent:** labels, objects, text and faces, each with detection times and bounding boxes. Stored video analysis has been GA since December 2024. A separate Stream Video Analysis service handles RTSP, with face tracking only.

**Limits:** MOV/MP4/MKV/WEBM, up to 20 GB and 10 h.

**Pricing** (MEASURED, Oracle price-list API, 2026-10-24):

| Item | Price |
|---|---|
| Stored video, first 1,000 processed minutes | Free |
| Stored video, after 1,000 minutes | $0.10/min ($6/h) |
| Stream video | $0.15/min |
| Gemini 2.5 Flash on OCI Generative AI (text, image, video input) | $0.30/1M |
| Gemini 2.5 Pro on OCI Generative AI | $1.25/1M |

**Claude fit:** relevant only for OCI-resident customers; the CLI is the route.

**Evidence and maturity:** vendor only. I found no 2026 feature news (newest blog post: GA, 2024-12). Flagged as older than 6 months.

URLs: https://www.oracle.com/artificial-intelligence/vision/pricing/ , https://docs.oracle.com/en-us/iaas/Content/vision/using/limits.htm , https://blogs.oracle.com/ai-and-datascience/oci-vision-stored-video-analysis-ga

## Not found or dead

- **IBM watsonx / Granite Vision:** I found no video input. Granite Vision 3.2 and the Granite 4.0 3B Vision LoRA are image and document models (search, 2026-10-24). IBM has no hyperscaler video-understanding service on this axis.
- **Google Cloud Video Intelligence API:** deprecated 2026-09-14, shutting down 2027-09-14.
- **Amazon Rekognition Streaming Video:** closed to new customers 2026-04-30. **Rekognition People Pathing:** ended 2025-10-31.
- **awslabs `aws-bedrock-data-automation-mcp-server`:** removed 2026-04-17.
- **Azure-Samples `azure-content-understanding-mcp-server`:** stale; last push 2025-05-12, 4 stars.

## Concerns and limits of this pass

- I did not sign up for any service, upload video or run any analyzer. All capability statements are vendor documentation.
- The Azure "Video Field Extraction $9.90/h" meter is still in the price API. I believe it is the legacy preview meter, since the pricing explainer now bills field extraction through Foundry tokens, but I could not confirm which applies to a 2025-11-01-GA analyzer.
- Gemini audio tokens per second for 3.x/4 models were not re-verified, so the per-hour Gemini estimates carry that assumption.
- Content Understanding keyframe output resolution is undocumented. Test it before relying on keyframes for OCR.
