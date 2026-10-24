# P3. How Tinycloud and Cloudglue work, and what they close of human-parity video understanding

Date 2026-10-23. Worker P3. Desk synthesis of our 2026-10-06 teardown; nothing was re-run against either product today, nothing uploaded, no account used.

## 0. Sources, labels, privacy

Teardown files (all under `~/.claude/research-artifacts/meeting-video-2026-10-06/`), cited by short name and line:

| Short | File |
|---|---|
| TI | `tinycloud-internals.md` |
| AC | `td-tinycloud-agent-core.md` |
| MR | `td-tinycloud-media-rendering.md` |
| SR | `td-tinycloud-skills-recipes.md` |
| VV | `td-tinycloud-video-verbs.md` |
| CM | `cloudglue-method.md` |
| CA | `cloudglue-api.md` |
| DP | `td-cloudglue-describe-pipeline.md` |
| ES | `td-cloudglue-extract-segmentation.md` |
| SC | `td-cloudglue-search-chat.md` |
| PM | `td-published-method.md` |
| WN | `td-adv-what-not-to-copy.md` |
| CV | `td-adv-claim-verifier.md` |
| SPEC | `~/Development/agent-context-sync/docs/design/meeting-video-spec.md` |

Labels, as the brief asks:

- **MEASURED**: we ran a command and got the number (teardown greps, `curl -sI`, `shasum`, the `rg` fixture, the spec's blind-reader experiments).
- **DOCUMENTED**: the vendor or its papers say so. Sub-label **DOCUMENTED-SRC**: we read the vendor's shipped code (Tinycloud 0.3.25 carve) or OpenAPI spec statically. This is stronger than prose but the behaviour was **not executed** (AC:3, VV:3, CV:3).
- **INFERRED**: reasoning by the teardown or by me; the basis is named.

Privacy: no person's name or spoken content from the private recording is used here. Names that appear in the vendor's public sample are left out too; only counts and methods are kept.

Caveat on everything below: the teardown was text-only. No Cloudglue output on any of our recordings was ever produced, so we have **no measured quality figure** for Cloudglue on meetings (CA:305; DP:348; CM:108).

---

## 1. Architecture

### 1.1 The split in one line

Cloudglue is a hosted service that turns a video into time-aligned **text** tracks per segment. Tinycloud is Cloudglue's CLI and agent harness: a thin request builder over six endpoints (`/files`, `/describe`, `/extract`, `/deepSearch`, `/responses`, `/find-moments`). It does no video understanding on the client (DOCUMENTED-SRC, VV:17; TI:28, 40).

### 1.2 What model sees what

| Actor | Input it receives | Label, cite |
|---|---|---|
| Tinycloud's agent model (`tinycloud:advanced` or `general-medium`, hosted alias, model not named; 1M-token window declared, `reasoning: false`, 32K output) | Text only: one summary string per operation, plus the operation's JSON only if it serialises to 6,000 characters or less. It never sees frames or audio. `read` is `readFileSync(..., "utf-8")`; images reach it only by clipboard paste, and only on the latest user turn | DOCUMENTED-SRC, AC:17-20, 139-147, 208-212; TI:109, 129-135; confirmed CV:8-9 |
| The user's own agent (Claude Code, Codex and others, through the 8 shipped skills) | The JSON envelope Tinycloud prints on stdout. Same text-only channel | DOCUMENTED-SRC, TI:131, 156-157 |
| Server-side description models (undisclosed) | The uploaded file. Speech: one whole-file pass. Visual, scene text, segment title and summary: one stateless pass per segment | INFERRED from schema and sample, DP:30, 174-221 |
| `ask` | Server model `nimbus-002-preview` over the stored descriptions, through the Responses API | DOCUMENTED-SRC, AC:225; VV:181-187 |
| `moments` (Find Moments) | The stored **text** description, not pixels ("reads the file's media description") | DOCUMENTED, VV:203; ES:25 |

Third-party models: the docs name only Gemini, for audio description. The trust-centre list of sub-processors includes Deepgram for transcription, plus Google Cloud, Azure and Groq for inference. The CTO's research prototypes used Gemini 1.5 Flash, GPT-4o/4.1, AssemblyAI, SigLIP and OpenAI embeddings (DOCUMENTED, CM:22; CA:169-171).

### 1.3 Frame rate and resolution

- **Client.** Tinycloud uploads the whole container as it is, read fully into memory. It does not trim, transcode or sample frames first (DOCUMENTED-SRC, TI:85; confirmed CV:10). Its only local frame tools are `clip thumbs` and the agent's `ffmpeg thumbnails`, at a fixed `fps=1/10` by default. They write to disk, put no timestamp in the file name, and their output is never shown to the model (DOCUMENTED-SRC, MR:125-136; AC:101). It has no local scene detection (MEASURED by grep for `select=`, `gt(scene` and others: 0 hits, MR:260).
- **Server.** No describe parameter sets frame rate, frames per window or model (DOCUMENTED, DP:62). Timestamps in the vendor sample are whole seconds, and the 0-20 s visual entry narrates view changes in order. That points to a time-ordered frame sequence of about 1 fps per 20 s window (INFERRED, DP:161). Gemini also samples at 1 fps (DP:161, 250).
- **Upload guidance.** At most 1080p, H.264 and AAC (DOCUMENTED, CA:46). Limits: 2 h and 2 GB, with "best under 250 MB" local uploads in the docs, against "~3 GB, 2 s-3 h" in Tinycloud's glossary. The two disagree and neither was tested (DOCUMENTED, CA:29; CV:16).
- **Images the server exposes.** One thumbnail per segment. A sampled one was 1080x608 WebP at 44.6 KB, served unsigned from CloudFront with a one-year cache (MEASURED by `curl -sI`, MR:21). Optional 0-8 keyframes per segment and uniform frame extraction at 0.1-30 fps exist. All are CDN URLs (DOCUMENTED, CA:61-62, 282). Tinycloud uses uniform frame extraction only inside face detection (DOCUMENTED-SRC, MR:139).

### 1.4 Audio

- The whole file goes up. Tinycloud has no audio-only path (DOCUMENTED-SRC, TI:85).
- **Speech** runs as one pass over the whole file. It yields sentence units with float-second times on the file timeline and integer speaker ids. Word times are returned only on request (`include_word_timestamps`), which Tinycloud never sends (DOCUMENTED, DP:122; DOCUMENTED-SRC, VV:140). The float32 artefacts and the paragraph-and-sentence structure match Deepgram (INFERRED, DP:31, 223-228).
- **Speaker names.** The API documents a closed set: names come only from `participants` (at most 50), otherwise `Speaker N` (DOCUMENTED, CA:27; DP:230-235). Tinycloud **never sends** `participants`, so its meeting recipe's speaker names are model inference from the transcript (DOCUMENTED-SRC, CV:14, 24; VV:31).
- **Audio description** (non-speech sound, music) is said to use Gemini. It is off by default, and the docs contain no populated example (DOCUMENTED, CM:22; MEASURED by grep, three hits, all `[]`, DP:125). The blog's prosody and facial "overlays" do not appear in the API schema (DOCUMENTED, CM:68).
- **Tinycloud captions** are 5-word cues whose times are linearly interpolated across the utterance. `--word-level` is accepted and changes nothing (DOCUMENTED-SRC, MR:87-93).

### 1.5 How segments, descriptions and indexes are built

1. **Segmentation** (DOCUMENTED, DP:66-80; ES:114-152):
   - `uniform`: the default, 20 s windows.
   - `shot-detector`: `adaptive` or `content`, threshold 27.0, minimum 0.6 s, maximum 300 s, gap fill. Its defaults equal PySceneDetect's (INFERRED, DP:33; ES:27; CV:26).
   - `narrative`: chapters via `transcript`, `balanced` or `comprehensive` (a VLM).
   - `manual`.
2. **Fan-out per segment.** Each segment gets its own stored describe record with its own status. The file-level JSON concatenates them without dedup, so an utterance that straddles a 20 s boundary appears twice (DOCUMENTED-SRC spec plus sample, DP:29, 202-208).
3. **Tracks.** Parallel arrays `speech[]`, `visual_scene_description[]`, `scene_text[]` and `audio_description[]`, each entry `{text, start_time, end_time}`. "Fusion" is co-location on a shared timeline, not a joint model (DOCUMENTED, CM:21; PM:225-227).
4. **Scene text** keeps its own time ranges (down to 1 s) and does not follow the 20 s grid. That suggests change-aware OCR (INFERRED from sample timings, CV:12, 25). It is most likely a VLM pass rather than a classical OCR engine, at medium confidence (INFERRED, DP:32, 237-246). It carries no boxes, no layout and no reading order, and is not deduplicated across windows (DOCUMENTED sample, DP:162-166; CA:154).
5. **Reduce.** The file title and summary are built "from the descriptions generated" (DOCUMENTED, DP:209).
6. **Rendering happens on read.** One stored job serves JSON, markdown "Video Document", SRT, VTT, diarized markdown and plain text, plus time and track filters (DOCUMENTED, DP:34, 82-92).
7. **Index.** A collection, or `use_in_default_index`, adds one search document per segment (speech, visual text, scene text) and one per file (the summary). Indexing is a second, free stage (DOCUMENTED, SC:50-60). `general_content` is most likely a dense embedding of the fused segment **text**, not of frames (INFERRED, SC:150). Hybrid modalities are merged by rank (INFERRED, SC:152).
8. **Client cache.** The directory is `sha256({src, op, prompt, seg, mod, model, start, end, options})`. It holds raw `describe.json`, `describe.md`, `speech.vtt` and a `watch.json` projection. That projection inlines speech per segment but **drops** `scene_text` and visual text (DOCUMENTED-SRC, VV:261-277; AC:156).

### 1.6 How an agent queries it

| Shape | Mechanism | Label, cite |
|---|---|---|
| `search` (local, free) | Lowercase substring `indexOf` over cached `watch.json`. On a video only speech and segment titles are reachable: `--field text` and `--field entities` can never match, and `--field visual` falls back to the title | DOCUMENTED-SRC, AC:156; VV:325-326; SC:341-342 |
| `probe` | `/deepSearch`: a planner writes several searches, each with its own modalities, scope and filter; a synthesis model writes a reason per hit and a summary | DOCUMENTED, VV:174; INFERRED algorithm, SC:256-262 |
| `ask` | `/responses` with `nimbus-002-preview`. A citation is a **segment** `(file, segment, start, end)` with all of that segment's text. It carries no quote offset | DOCUMENTED-SRC, VV:181-187; SC:26, 208-219 |
| `extract` | A schema fill at video level or per segment. It carries no evidence fields, and segment level fills every segment, including with `N/A` filler | DOCUMENTED, ES:23, 32 |
| `moments` | A rubric sweep with free-range spans, `reason`, `anchors`, `speakers` and `absence` findings. It reads the text description | DOCUMENTED, ES:26, 159-188 |
| `query` | Read-only SQL over extracted entities (inferred to be DuckDB) | DOCUMENTED, SC:240 |
| MCP server | `describe_video` pages markdown in 5-minute windows; searches return 20 raw hits | DOCUMENTED-SRC, SC:295, 312 |

The context gate: above 6,000 characters the model gets only the summary line. There is no path, no size and no truncation marker (DOCUMENTED-SRC, AC:139-157; CV:9). A one-hour `watch` is about 180 segment objects, and the gate is crossed at about 2-3 minutes of talk (estimated from object sizes, AC:161). A long `ask` is cut to its first 200 characters with no citations (DOCUMENTED-SRC, AC:162).

---

## 2. What they claim about "understanding", against what the teardown verified

| Claim | Source | What the teardown found | Label, cite |
|---|---|---|---|
| "State-of-the-art video understanding ... we orchestrate and manage model upgrades" | Landing page | No Cloudglue-trained model, model card or benchmark entry. Read literally, the claim is about orchestrating third-party models | DOCUMENTED quote; absence noted, CM:8, 99 |
| Beats peers | Implied | No head-to-head against any commercial peer exists, from anyone | DOCUMENTED absence, CM:9 |
| "2 hours of video in 3 minutes" | Landing page | No test published, and the figure has changed over time ("50 minutes" earlier). Stateless per-segment fan-out makes it arithmetically possible: about 360 parallel calls for 2 h | DOCUMENTED, CM:42; INFERRED, DP:251 |
| "+83 %", multimodal 96.7 against ASR-only 53.3 | Vendor article and KDD workshop paper | 15 queries, 5 per class, authors' own annotators, ASR-only baseline. One query moves a class by 20 points | DOCUMENTED, CM:43; PM:151-160 |
| "Consistently outperform single-modality ... across 1.8M clips" | Blog | The cited paper (arXiv v1) shows a **tie** with speech alone (HIT@1 0.741 against 0.741). The supporting result is ModaRoute: fused text R@5 75.9, speech-only 46.2, per-modality late fusion 38.7, with some queries written from the fused text itself | DOCUMENTED, PM:54-67, 117-135; CM:45-47 |
| Speaker names "never invented" | Docs | Holds only when `participants` is passed, and Tinycloud never passes it | DOCUMENTED; DOCUMENTED-SRC, CV:14, 24 |
| Find Moments is "exhaustive" | Changelog | No recall figure published | DOCUMENTED, ES:188 |
| "Context is additive; deeper passes pull out more detail" | System prompt | Every deeper pass is a metered verb behind the 6,000-character gate; a changed steering prompt re-bills | DOCUMENTED-SRC, WN:13; AC:51-53 |
| Local search covers speech, visual, text and entities | Skill reference | For a video only speech works (see 1.6) | DOCUMENTED-SRC, AC:156; SR:21 |
| "Highlights" recipe | Recipe name | It cuts **every** shot and ranks nothing | DOCUMENTED-SRC, MR:61; ES:31 |
| Meeting minutes demo | Landing page | No recipe or template exists. It is a free-form agent run plus a third-party docx skill | DOCUMENTED-SRC, TI:19; MR:236 |

Defects in the vendor's own material:

- **OCR spelling.** In the published sample, one presenter's name is read three different ways across scene-text entries, and the speech track and a segment summary spell another name differently. No cross-frame voting is done (DOCUMENTED sample, DP:166, 168; CA:33).
- **Visual prose.** Six consecutive windows re-describe the same static speaker, and details drift between them (DOCUMENTED sample, DP:167; CM:62).
- **Duplicates.** An utterance on a boundary is listed twice (DP:29), and a contact slide is emitted twice across adjacent windows (DP:164).
- **Charts.** The vendor's own paper calls "charts, diagrams, or handwriting" an open challenge (DOCUMENTED, CM:66; PM:162).
- **Determinism.** Output is not deterministic ("a one-time index doesn't make it deterministic"), and model versions are neither pinned nor exposed (DOCUMENTED, CM:30; DP:267).
- **Inert surface.** Fifteen declared Tinycloud surfaces are inert or contradicted in 0.3.25 (MEASURED as a row count of VV:319-339; DOCUMENTED-SRC per row).
- **Synthetic fill.** When extraction is thin, the sales-coaching renderer fills constant scores of 60 and canned insight text, and the page does not say so (DOCUMENTED-SRC, MR:232; SR:126).
- **Grounding rules.** The agent's system prompt has no citation, attribution or uncertainty rule (MEASURED by grep, 0 hits for uncertain, confiden, hallucin, guess, AC:64-72).

What *is* demonstrated, by vendor-run tests that no one has replicated:

- A time-aligned text projection beats frame embeddings for retrieval (HIT@1 0.74 against 0.48-0.55) (PM:54-67).
- Co-located text from all modalities is the best design the CTO has measured (PM:132, 230).
- The CTO's own engineering post reports that 70 % of distinct on-screen terms in 566 conference talks were never spoken (DOCUMENTED self-report, method unpublished, PM:202).

---

## 3. Which mechanisms close which human-parity gap

The reference is a human who watches the whole video continuously: sees every frame, hears tone, tracks objects and people, remembers across the hour. Neither product gives the agent continuous pixels or audio. Every gap is closed, where it is closed, by **converting** the video into text, and "understanding" sits with server models we cannot inspect (INFERRED from 1.2).

| Gap | Mechanisms that close it, partly | What stays open | Label, cite |
|---|---|---|---|
| **Semantic**: what was said and shown means | Whole-file ASR in sentence units. Scene text (VLM-like) catches on-screen terms speech misses. A per-segment VLM description. Co-location under one time heading is the best-scoring retrieval layout (R@5 75.9 against 46.2). Schema extract and rubric moments structure the meaning | Charts and diagrams are an admitted open problem. Segment summaries see only their own 20 s (one is titled just "Video Conference Call"). The meeting recipe defaults to speech-only, so a slide's content never enters the describe. Spellings are unstable across tracks | DOCUMENTED, DP:30-32, 168; PM:230; CM:66; TI:86, 98; CV:7 |
| **Spatial**: where things are on screen, layout, what is pointed at | Face boxes per sampled frame (normalised `{top, left, width, height}`). Up to 8 keyframes per segment exist as URLs. The CTO's separate project (Overcast, not the product) adds labelled contact sheets | Scene text has no boxes, layout, table structure or reading order. Faces have no track and no link to a speaker. Nothing models cursor, highlight, selection or spatial relations. Tinycloud's agent cannot open an image, so even the keyframes do not reach it | DOCUMENTED, SC:274-279; CA:154, 61; DP:162; PM:211; DOCUMENTED-SRC, AC:208-212 |
| **Motion and temporal dynamics** | The VLM sees an ordered frame sequence of about 1 fps inside each window and narrates view changes. The PySceneDetect-style shot detector cuts on HSV change. Moments snap edges (`sentence`, `tight`, `loose`). Overcast's bisect and presence-window skills (not product) find when a state changes | Descriptions are stateless across windows, with no memory of the previous segment. Nothing tracks objects or people. Events shorter than about 1 s fall between samples. Shot detection degenerates to 300 s windows on screen shares, and nothing detects a slide change | INFERRED, DP:161, 251; DOCUMENTED, CM:25; ES:28; MR:62; PM:212 |
| **Audio**: speech, speakers, non-speech, tone | Diarized ASR. Closed-set naming via `participants` at the API. Word times on request. Audio description via Gemini | Tinycloud passes neither `participants` nor word times, and its captions interpolate. Audio description is off by default with no published example. Prosody, emotion and laughter are not in the schema. Silent footage makes the `transcript` chapter strategy error out rather than degrade | DOCUMENTED-SRC, CV:14; VV:140; MR:87-93; DOCUMENTED, DP:125; CM:68; CV:18 |
| **Long-horizon recall** | Describe once, cache, search: keyword, then semantic, then re-analysis. Every segment carries its own times. Collections with a frozen config. Deep Search planner. Moments: exhaustive pass, read-time shaping, `absence` findings. SQL for counts. MCP 5-minute paging. Client cache keyed by content and options | The 6,000-character gate drops long results with no pointer. An entity has no identity across segments or videos, and analytics group on exact strings. Recall is only as good as the 20 s text written about each window. The 2 h cap needs splitting. Local search cannot see on-screen text | DOCUMENTED, CM:17; ES:26, 30, 182-184; SC:295; CA:29; DOCUMENTED-SRC, AC:153; VV:325 |

Net, INFERRED from the rows above:

- **Closed well enough for retrieval:** speech semantics, and on-screen *words* (as text, unstably spelled).
- **Partly closed:** coarse temporal order within a window; finding moments over the hour.
- **Not closed:** spatial layout, motion and continuity, object and person identity over time, paralinguistic audio, charts.

The vendor's own evidence says the *representation* (labelled, time-aligned text) is the transferable idea. It says nothing that Cloudglue executes it better than an alternative (CM:10, 101).

---

## 4. What our spec adopted and dropped

### 4.1 Rows citing `td-tinycloud-*` (SPEC section 14 and section 8)

| Mechanism | Teardown source | Spec disposition | Spec reason, cite |
|---|---|---|---|
| Retrieval-shape table in the skill ("which move fits which question") | SR:309 (from VV and TI:114-122, 191) | **Adopted**: the cheapest-first look-up order of section 8: curated page, then index, then grep both channels, then one window, then at most 3 keyframes | SPEC:910, 1244, 879-895 |
| Snapping a cited span to speech-turn edges (the local form of `boundary_policy: sentence`) | MR:329 (also ES:276) | **Dropped**: a citation is one time and one quote; lint rule 4 names the line within 10 s | SPEC:1234; SPEC:110 |
| Redactor for URL signatures and `key=value` secrets (from Tinycloud's session scrubber) | AC:330 | **Dropped**: the evidence prints what was read; a credential stubs the whole recording | SPEC:1237 |
| "No access" rather than "no recordings" on EACCES (macOS privacy honesty) | AC:337 | **In the repo already** | SPEC:1238 |
| Dry run that reports minutes per pending recording (what Tinycloud's `plan` promises and does not deliver) | SR:304 | **Dropped**: a dry run starts no helper, so it cannot know a duration | SPEC:1240 |
| Two cache axes (identity and enrichment) in every result | VV:396 | **Dropped**: one action key is one axis | SPEC:1241 |
| Write guard for a half-synced `.mp4` (stat before and after hashing) | VV:397 | **In the repo already** (S0 rule 9) | SPEC:1242 |

### 4.2 Other teardown rows in the same table (Cloudglue and adversarial)

| Mechanism | Source | Disposition | Cite |
|---|---|---|---|
| Absences seeded from the invite's agenda (Find Moments `absence` findings) | ES:268 | Adopted, as a curator rule | SPEC:1232, 690 |
| People-and-terms registry across meetings | ES:275 | Dropped: a cross-meeting ledger is a non-goal | SPEC:1233 |
| Spelling-variant clusters | SC:457 | Dropped for this build; the "On-screen terms never spoken" block is the adopted part | SPEC:1235 |
| Glossary that boosts ASR and corrects tokens (Cloudglue `prompt`) | DP:368 | Dropped: the screen is the spelling authority | SPEC:1236 |
| "Emit every state once; never pre-trim" | WN:46 | Departed from on purpose in four counted places (under 4 s, the 840-read bound, 5,400 ticks) | SPEC:1245 |

### 4.3 Adopted or rejected in substance without a `td-` row

INFERRED: each match below is my reading of the spec against the teardown, not a citation the spec makes.

- **Rejected: the cloud engine as a whole.** No upload, no cloud result, no network call (SPEC:100). Tinycloud's first cloud call uploads the whole file and its local path (TI:141-142).
- **Rejected: model prose in evidence.** No captions, summaries or chapters in the evidence package (SPEC:101). This answers Cloudglue's VLM scene prose and segment summaries (WN:8; DP:372).
- **Rejected: fixed 20 s scenes** (SPEC:107; WN:7). Replaced by gated screen states (SPEC:39).
- **Rejected: any index.** No vector or full-text index (SPEC:105), the opposite of Cloudglue's search, Deep Search and collections. Grep covers the lexical modalities (MEASURED, rg fixture, SC:382).
- **Rejected: names from a face or voiceprint** (SPEC:103, 660). Cloudglue itself documents no face-to-speaker link (CA:64).
- **Adopted: a speech line printed once,** in the state where it starts (SPEC:335, 341). This fixes the duplicated boundary utterance (DP:29; VV:351; PM:215).
- **Adopted: always search both channels.** The modality router's 42.9 % on screen-text intent is cited as the reason (SPEC:884, 908; PM:127).
- **Adopted and tightened: closed-set naming** with a recorded basis and a one-person check (SPEC:648-657). This is the API rule Tinycloud fails to use (CV:33).
- **Adopted: a content-addressed cache key** over bytes, converter version and options (SPEC:601). This matches Tinycloud's key design (VV:261-277). The spec also pins engine versions, which Cloudglue does not.
- **Adopted: interval-joined, self-locating lines.** Every line carries a time and a channel tag (SPEC:876, 883-884). This fixes Tinycloud's projection dropping scene text (AC:328-329).
- **Conditional: contact sheets**, only if readers open more than 3 images per question (SPEC:597; from PM:211).
- **Stated openly: the residual human-parity gap.** The spec's "Not detected" list names who actually spoke beyond `VOICE` lines; camera, faces, gestures and cursor; highlighting; charts; anything under 4 s; video played in a share; laughter and tone (SPEC:1213-1224). This is the same spatial, motion and paralinguistic territory left open in section 3.
- **Measured value of the adopted text channel.** On-screen text raised blind-reader correctness from 0.50 and 0.39 (transcript) to 0.92 and 0.92 on two Zoom recordings. Keyframe images added 1.5 of 18 points, not distinguishable from zero (MEASURED by our project, per SPEC:38-40). No Teams recording or Cloudglue output was in that test.

---

## 5. Concerns and deviations

1. No claim about Cloudglue output quality on our recordings is MEASURED. Every quality observation rests on one truncated vendor sample of unknown date (DP:36, 348).
2. Server internals are reconstructions, as marked: 1 fps, Deepgram, VLM scene text, PySceneDetect, fused-text embedding, Deep Search planner.
3. The Tinycloud line numbers are for one carve of 0.3.25 darwin-arm64 and shift in any other build (AC:322; VV:389). The product released about every 3 days (estimated, 26 releases in 82 days, TI:18), so the 0.3.25 read may be stale by 2026-10-23.
4. Deviation from the brief: I added section 4.2 (non-Tinycloud teardown rows) and section 4.3 (substantive matches without a `td-` row, marked INFERRED). Question 4 asks which mechanisms the spec adopted or dropped, and the cited rows alone leave out the largest decisions (no cloud, no index, no model prose).
5. `.claude/rules/` of this repo were not read: the brief concerns external artefacts and a sibling repo's spec.
