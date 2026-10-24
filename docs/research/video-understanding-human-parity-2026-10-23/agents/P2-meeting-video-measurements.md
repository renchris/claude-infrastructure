# P2: what the October 2026 meeting-video research measured

Date: 2026-10-23. This agent ran nothing new. Every number below comes from the cited artifact. The tags say where the artifact's author got it:

- **MEASURED**: the research ran it on this Mac. The command or script is named in the cited line.
- **DOCUMENTED**: a vendor, a paper or a model card states it. The cited artifact quotes the URL, and this agent did not re-fetch it.
- **INFERRED**: reasoning, either the artifact's or this agent's (marked "this agent").

Base path for every short citation: `~/.claude/research-artifacts/meeting-video-2026-10-06/` (abbreviated `R/`). Short names:

| Short | File |
|---|---|
| mu | `R/model-understanding.md` |
| vc | `R/visual-channel.md` |
| ep | `R/empirical-probe.md` |
| vaa | `R/video-api-alternatives.md` |
| rv | `R/real-recording-visual.md` |
| ra | `R/real-recording-audio.md` |
| asr | `R/v2-asr-bakeoff.md` |
| v3s | `R/v3-synthesis.md` |
| v3a | `R/v3-sota-attribution.md` |
| vk | `R/value-exp/k8s1080-VERDICT.md` |
| vj | `R/value-exp/jup1080-VERDICT.md` |
| spec | `R/v2-spec.md` |
| cmp | `R/v2-review-completeness.md` |
| red | `R/adv-red-team.md` |
| d1-d5 | `R/decisions-v3/d1-voiceprints.md` ... `d5-public-excerpts.md` |

Privacy. The private Teams recording appears here only as counts and methods (rv, ra, v3s, d1-d5), with no names, terms or spoken content. The two value-experiment recordings are public Zoom calls. Their participants are not named here either.

---

## 1. The blind value experiment: what was tested, n, scoring, result

### 1.1 Design

- **Two public Zoom community calls, not Teams** (MEASURED, ep:11-16).
  - `k8s1080`: 54 min, a slide deck with discussion on camera. 1920x1080, 25 fps.
  - `jup1080`: 44 min. Talking heads, then six live browser, notebook and terminal demos. 1690x1080.
- **Three blind readers, each in a fresh session with only its own inputs** (DOCUMENTED in the research's own spec, spec:822; vk:12):
  - **A**: the Whisper transcript only. It has no speaker names and no slide text (vk:12).
  - **B**: the "evidence package" text, which is timed speech fused with OCR'd screen text. k8s: `00-index.md` plus 11 window files. jup: 10 files (vk:51, vj:73).
  - **C**: B plus at most 25 keyframe JPEGs, opened on demand.
- **18 questions per recording, 36 in total, 108 answers over both recordings** (spec:820, :837).
  - 6 SPEECH (answer only in speech), 6 SCREEN (answer only on screen), 6 CROSS (needs both).
  - At least one gold answer per recording is "not said" or "not shown" (spec:820).
  - **One run per condition and one judge** (vk:104-108). In jup the judge was "not blind to condition" (vj:143-144).
- **Correctness scoring** (spec:822; vk:114; vj:24-26):
  - 1, 0.5 or 0. A half point means one asked-for part right, the rest honestly declined, nothing wrong.
  - "Cannot tell" scores 0, unless gold is "not said" or "not shown".
  - Wrong-and-confident answers are counted separately.
- **Citation scoring**: the cited time is within 30 s of the gold time, and every quoted fragment is a substring of that reader's sources. The checks were Python scripts plus `grep -F` (MEASURED, vk:24; vj:43-47).
- **How gold was checked.** The judge opened 13 (k8s) and 12 (jup) full-size frames and read the whole transcript (MEASURED, vk:95; vj:128). C and gold read the same pixels, and one keyframe C used was gold's own frame. So agreement between C and gold is partly "the same kind of reader agreeing with itself" (INFERRED by the author, vj:151-152).
- **The reader model is not recorded in any file read** (INFERRED, this agent: no model name in vk, vj, spec:815-845 or SESSION-STATE). It cannot be said that the readers were Opus-class.

### 1.2 Results

Correctness, judged against gold (vk:18-22; vj:28-33):

| Recording | A transcript | B evidence text | C text + keyframes |
|---|---|---|---|
| k8s (slides), all 18 | 0.50 (9.0) | 0.92 (16.5) | 1.00 (18) |
| k8s SPEECH / SCREEN / CROSS | 1.00 / 0.25 / 0.25 | 1.00 / 0.83 / 0.92 | 1.00 / 1.00 / 1.00 |
| jup (demos), all 18 | 0.39 (7) | 0.92 (16.5) | 1.00 (18) |
| jup SPEECH / SCREEN / CROSS | 1.00 / 0.17 / 0.00 | 1.00 / 0.83 / 0.92 | 1.00 / 1.00 / 1.00 |

- **Wrong and confident: 0 of 108 answers in every condition** (judged, vk:38-44; vj:59-63; spec:837).
  - Reader A never got a screen question wrong. It declined with "cannot tell": 7 times on k8s and 11 times on jup (vk:8; vj:15-17).
  - Every answer marked "high" confidence on k8s was right (MEASURED, vk:44).
- **Significance** (MEASURED, exact sign test):
  - A vs B: p = 0.002 (k8s, 10 questions differ) and p = 0.001 (jup, 11 of 11).
  - B vs C: p = 0.50 and 0.25 (vk:107; vj:148-150).
  - So **the gain from images "is not distinguishable from zero at this size"** (vk:107). The jup author adds that the questions are not independent, which "flatters" both p values (vj:149-150).
- **The images' whole contribution** (judged): k8s +1.5 points from 2 questions (camera on/off, slide count and number; vk:9). jup +1.5 points from 3 half-points (vj:12-14).
  - In jup, 2 of those 3 were text that OCR had read and the package build then dropped. Only one needed pixels: a one-character output line (MEASURED, vj:13-14, :114-116).
  - In k8s, one third of the image gain was likewise OCR text the build dropped (vk:9, :86).
- **What A was missing**: speaker names, slide text and UI state. It was not short of ASR accuracy. Even perfect ASR would lack surnames shown only on screen (judged, vk:83-85).
  - Screen text also corrected three ASR errors in jup, none of which cost A a point (MEASURED, vj:104-106).

### 1.3 Reading cost (tokens = chars/4, ESTIMATED by the authors)

| Recording | A | B | C | Images opened |
|---|---|---|---|---|
| k8s, 54 min | 11,512 | 17,676 | 39,204 | 8 of 25 allowed, 46 available (vk:50-52) |
| jup, 44 min | 10,074 | 48,216 (4.8x A) | 69,627 (6.9x A) | 9 of 109, cap 25 (vj:72-74) |

- Image tokens are 2,691 per 1920x1080 frame (k8s) and 2,379 per 1690x1080 frame (jup) (vk:54; vj:79).
- Marginal yield (ESTIMATED):
  - A to B: 1.22 points per 1K tokens on k8s and 2.5 points per 10K tokens on jup.
  - B to C: 0.07 points per 1K tokens and 0.7 points per 10K tokens (vk:56; vj:80-81).

### 1.4 Limits the research itself recorded

- **The question mix is built in.** 12 (k8s) and 11 (jup) of 18 questions were written to need the screen. The "All" means describe this question set, not how often real questions need the screen (vk:10, :106; vj:145-147).
- **No question tested a chart, diagram or screenshot.** The slides opened were text only (vk:109). The image-only wins were "low-stakes facts" (vk:109).
- **Baseline A was weaker than what a tenant already has.** A Teams VTT with name tags plus the synced deck would answer 5 of the k8s screen gains. The jup gain (terminal and UI text) survives that baseline (cmp:23; spec:842).
- **The red team's bar was not run** (red:17; spec:842). That bar: 10 real recordings, with a reader given transcript, chat and deck, where frames carry a decision or a number the reader misses in 3 or more of the 10.
- **No Teams-recording fixture exists** (spec:824).

### 1.5 What it implies about "understanding like a human" (INFERRED, this agent unless cited)

- **It measured question answering, not human parity.** It shows retrieval and grounding of facts in two technical screen-share calls: who, what was on the slide, what the terminal printed, what was said.
  - No human reader was scored, so there is no human baseline to compare 1.00 against.
  - Nothing tested motion, gesture, tone, sarcasm, order of events, charts or diagrams.
- **Within that scope, the result is strong.** Speech questions were at ceiling in every condition, so a transcript already carries what was said. On-screen text turns "cannot tell" into correct answers (+7.5 and +9.5 points). The agent never bluffed.
- **Pixels added little because OCR text already carried most of the screen.** The few things only pixels gave were non-text state: a selected-thumbnail border, camera on or off (vk:88-89).
- **External benchmarks the research cited point the same way for harder skills** (DOCUMENTED, secondary extraction):
  - Video-MME-v2: best model 49.4 against human experts 90.7 under group-consistency scoring (mu:28).
  - TimeBlind (temporal): best model 48.2 against human 98.2 (mu:41).
  - The research's reading of these: native video "understands an hour" for gist but not for consistent detail (mu:55).
- **The pipeline does not watch continuously.** It samples every 2 s and keeps the frames that change.
  - A sub-2 s autocomplete popup was missed by both frame selectors (MEASURED, rv:174).
  - Anything between keyframes is unreachable without a frame-at-time helper (INFERRED, mu:79).
- **Net:** "fully like a human" is not supported. "Near-ceiling on spoken content and on-screen text for screen-share meetings, never confidently wrong" is supported at n = 36 questions on 2 recordings.

---

## 2. Speaker attribution and diarization

### 2.1 ASR accuracy (word error rate)

Measured on 7 meetings with human references: 6 AMI and 1 ICSI (MEASURED, asr:8, :44-55):

| Engine | Mean WER | Worst WER |
|---|---|---|
| Parakeet TDT v3 (FluidAudio) | 20.8 % | 32.8 % |
| Whisper large-v3-turbo, `-mc 0` | 24.5 % | 37.8 % |
| Whisper large-v3-turbo, defaults | 31.0 % | 54.4 % |

Failure modes (MEASURED):

- **Parakeet silently drops 10-20 s stretches.** 7 holes in 3 of 7 meetings, losing 0.3-2.4 % of the reference words (asr:9, :125).
- **Whisper defaults loop.** Loops of 200-846 words on 3 of 7 meetings (asr:10, :95-103).
- **Whisper invents speaker-name prefixes.** One name was carried over 13 segments. Another, under `--vad -mc 0`, appears in no transcript and nowhere on screen (asr:11, :168, :178).
- **Whisper invents text over digital silence.** On the private Teams file, `-mc 0` wrote 71 tail cues and defaults wrote 102. Parakeet wrote 0 (ra:10-12, :36-38).
- **The engines disagree with each other and with themselves.**
  - Parakeet vs Whisper: 8-10 % of words on the Teams file (ra:15).
  - Each engine against itself when the file boundary moves: 4-6.5 % (ra:15, :62-68).
- **Product and project names.** On the Teams file, 89-90 % of 471 spoken technical-term positions came out right or with a spacing variant (ra:16, :87-93). One two-word product name was rendered correctly in only 1, 1 and 0 of 22 positions (ra:16). On-screen text was the only correct source for that spelling (ra:148; asr:227).

### 2.2 Diarization: who spoke when

**Reference meetings** (MEASURED, FluidAudio offline community-1, threshold 0.6; asr:12, :251-261):

- Speaker count right on 6 of 7 meetings. TS3003a found 2 of 4.
- DER 31.8 % mean and 42.0 % worst, with a harsh scorer (collar 0, overlap scored).
- **Share of reference words given to the right speaker: mean 81.3 %, worst 72.2 %.** On overlap-heavy meetings, roughly one word in four would carry the wrong speaker tag or none (asr:266).
- Forcing the true speaker count made it worse: words right fell to 63.6 % (asr:265).

**The private Teams recording** (MEASURED, ra:17-18, :154-173):

- 5 clusters. The presenter is one stable cluster with 81.9 % of talk time.
- The other 4 clusters all sit behind one on-screen account label. It is unresolved whether that is several people or one person over-split. Centroid cosine suggests at least two voices (ra:171).
- No ground truth exists for this recording.

### 2.3 On-screen speaker cue (Teams)

MEASURED on the private recording:

- **Name labels are readable** in 99.8 % of share samples. 97.0 % of reads are exactly one canonical string (rv:20, :260-262).
- **The speaking highlight is a filled label pill, not a ring** (rv:266). Exactly one label is lit in 85.8 % of share samples, but in 0 % of single-camera samples. Over the whole recording, 61.6 % of samples carry a lit label (rv:268).
- **The highlight follows audio energy.** A label is lit in 93.9 % of samples with sound and 5.5 % of quiet samples (rv:269). This was checked against energy, not against each speaker (rv:272).

### 2.4 Binding voices to names: the v3 "stream rule"

MEASURED on the private recording (v3s:14-19, :57-64):

- **What it names.** 1 of 5 voices is named: 39 of 98 turns, 81.8 % of talk. The 4 voices on the shared account print as "voice N, on shared audio of <label>".
- **Contradictions.** After the turn veto, 0 named turns are contradicted by the highlight. 26 of 1,806 named samples (1.44 %) show the other account lit, which is an upper bound that includes cross-talk.
- **The older majority-label rule would be wrong.** It would put the shared account owner's name on 55 of 98 turns (v3s:19, :62).
- **Whether the names match real people is unmeasured.** There was no listen and no Teams VTT (v3s:18, :71, :96).
  - The research says agreement with the highlight must never be presented as name accuracy (v3s:131, A-R7).
  - Five random lines per voice would catch a merged second person who holds 10 % of a voice's talk only 41 % of the time (ESTIMATED, binomial, d4:21, :130).

### 2.5 Published state of the art (DOCUMENTED, v3a)

- **Best open diarizer: Nemotron 3** (2026-09-23). AMI-SDM 11.14 % and DIHARD III 12.73 % DER under NVIDIA's own protocol, capped at 8 speakers (v3a:9, :44-51).
  - Locally on the same recording it ties community-1 once samples are counted as events (p = 0.12). It leaves 12 named turns without a lit sample of their own; community-1 leaves 0 (MEASURED, v3s:21-22, :60).
- **pyannote community-1** (no collar): AMI-SDM 19.9 %, DIHARD III 20.2 % (v3a:12, :29-33).
- **Research on reading the highlighted Zoom tile by OCR**: 98.5 % of utterances correctly attributed (v3a:110). The research weakened this because that study has one person per tile (v3s:118).
- **An LLM naming speakers from self-introductions**: 74 % last-name exact match (v3a:111). The skeptic's reading is 58.3 % exact full-name match (v3s:51, :118).
- **No product publishes a name-attribution accuracy.** Accurate names come from the platform (separate streams or the active-speaker signal), not from voice (INFERRED, v3a:115-118).
- **Voiceprint owner matching on public AMI audio** (MEASURED): 129 of 135 trials named the owner's cluster, and 0 of 135 named a wrong cluster (d1:23, :118-119). It was not adopted for colleagues, on legal and value grounds (d1:9-18).
- **Claude will not name people from images** (DOCUMENTED, mu:36, :87). So faces cannot be a naming route for the reading agent.

---

## 3. OCR of screen content (Apple Vision `VNRecognizeTextRequest`, accurate level)

### 3.1 Synthetic floor

MEASURED on random words and digits with language correction off (vc:63-75):

| Text height | Proportional font (SF) | Monospace (Menlo) |
|---|---|---|
| 14 px | 0.998 | 1.000 |
| 12 px | 0.978-0.989 | 1.000 |
| 8 px | 0.73-0.79 (fails) | 0.946-0.950 |
| 6-7 px | 0.51-0.70 | 0.79-0.96 |

- 2x upscaling is not a fix (vc:75).

### 3.2 Zoom calls (MEASURED, ep:89-101)

- **Resolution.** Against a tiled 1080p read, 720p recovers 0.764-0.768 of the tokens and 360p only 0.066 ("unreadable"). Untiled 1080p recovers 0.877.
- **Small table digits fail first.** One table frame showed digit errors untiled that tiling fixed (ep:99).
- **Detectors.** The ffmpeg `scene` filter at 0.3 caught only 28 % (demo call) and 65 % (slide call) of the screen text (ep:58, :78). OCR text novelty kept 410 frames at 98.1 % word recall (ep:71, :84).

### 3.3 Real Teams recording (MEASURED, rv)

- **Confidence.** Slides: mean 0.979, p50 line box 26 px. Desktop (editor, terminal): mean 0.821, p50 16.7 px (rv:205-208).
- **Hand check.** 27 of 31 eye-checked on-screen terms exact untiled, 26 of 31 tiled. Tiling at 1024 px gives no net gain for 1.8-3.4x the time (rv:18, :213-214).
- **Error types**:
  - one-character swaps in identifiers;
  - punctuation swaps;
  - icons read as letters;
  - invented text from a half-clipped line at confidence 0.5 (rv:216-225).
- **Jitter.** On an unchanged desktop screen, 34.2 % of consecutive samples produce at least one "new" line (rv:17, :151).
- **Frame selection.** Selectors limited to the content column keep 215 and 225 frames at word recall 0.960 and 0.963. That is 13.7 frames per hour on slides and 261-274 per hour on IDE and terminal (rv:15).
- **Non-text visuals.** A bar-chart slide had 13 OCR lines, so neither the "under 5 lines" nor the "under 2 % coverage" rule flags it for an image read (rv:328).
- **Grading caveat.** Recall is graded by the same OCR engine that produces the output, so text Vision cannot read is invisible to these numbers (ep:236; rv:371).

---

## 4. Image-count and resolution limits

### 4.1 Claude, the reading agent

DOCUMENTED as fetched by the research on 2026-10-06 from platform.claude.com vision docs, mu:36. Not re-verified here.

- **No video input. Images only.**
- **Tokens = ceil(w/28) x ceil(h/28).**
- **Two tiers:**
  - High-resolution tier (Claude 4.7 and later): long edge up to 2,576 px, at most 4,784 tokens per image.
  - Standard tier: 1,568 px and 1,568 tokens.
- **A 1920x1080 frame costs 2,691 tokens on the high-res tier, or 1,560 on standard.**
- **Up to 600 images per request** (100 on 200k-context models).
- **More than 20 images in one request forces every image to 2,000 px per side or less**, or the request is rejected. History and tool results count toward the 20.
- **Other caps:** 32 MB per request, 10 MB per image.
- **Stated limits:** it does not name people; counting is approximate; coordinates are approximate; it may hallucinate on images that are low quality or under 200 px.
- **Budget arithmetic** (INFERRED, mu:60-63): 40 distinct 1080p screens cost about 108K tokens on the high-res tier. A 3x3 contact sheet costs about 300 tokens per thumbnail, "enough to locate a screen, not to read it".
- **Not verified:** whether Copilot CLI's Read downsizes images or caps their count (mu:130).

### 4.2 Other services (DOCUMENTED)

- **Gemini**: 1 fps by default, 66 tokens per frame at low resolution and 258 at high (mu:34; vaa:11, :63).
  - About 360K tokens (low) or 1.08M tokens (high) per hour (mu:59; vaa:64).
  - Up to 3 h per prompt at low resolution, or 1 h at high (vaa:37).
- **Azure Content Understanding**: frames at about 1 fps, resized to 512 px square; "small text ... can be lost" (vaa:11).
- **Best model on MME-VideoOCR**: 73.7 % (vaa:11, secondary).

### 4.3 What the probe agents did (MEASURED)

- Blind readers opened 8 and 9 keyframes against a cap of 25 (vk:52; vj:74).
- Keyframes at native 1080p as JPEG q70 cost 245 KB each, 26.2 MB per recording-hour (rv:19, :235).
- Downscaling to 1280 px loses 5-16 points of OCR text (rv:19, :241-246). Downscaling costs more legibility than compression does (ep:208).

---

## 5. Cost per hour of video

### 5.1 Local compute (M1 Max under heavy load, so wall times are upper bounds)

| Stage | Cost | Tag | Source |
|---|---|---|---|
| Picture pipeline, OCR-novelty path | 7.1 min per recording-hour (15.0 min for 2.11 h) | MEASURED | rv:21, :285 |
| Picture pipeline, cell-diff path | 7.6 min per recording-hour (15.9 min for 2.11 h) | MEASURED | rv:21, :292 |
| Picture pipeline, gated path | about 2.2 min per recording-hour | ESTIMATED | rv:293 |
| Audio decode + Parakeet + diarizer | 135-162 s for the 2 h 06 m file | MEASURED | ra:14, :223 |
| Parakeet / diarizer per recording-hour | 24.8 s / 31.4 s | MEASURED | ra:260 |
| Whisper `-mc 0` | 342 s for the 2 h 06 m file | MEASURED | ra:14, :37 |
| End to end on the Zoom probe | about 7-12 min per meeting-hour | ESTIMATED | ep:50 |

### 5.2 Reading tokens

| Item | Tokens | Tag | Source |
|---|---|---|---|
| Transcript of the Teams file, as merged speaker turns | 18,846 for about 91 min of speech | MEASURED (chars/4) | ra:197 |
| Same transcript, as raw Whisper cues | 25,773 | MEASURED (chars/4) | ra:200 |
| Evidence package, k8s, 54 min (B / C) | 17.7K / 39.2K | ESTIMATED | vk:50-52 |
| Evidence package, jup, 44 min (B / C) | 48.2K / 69.6K | ESTIMATED | vj:72-74 |
| Screen text, slide meeting vs demo meeting | 1.9K vs 39K per hour, a 20x swing | MEASURED | ep:123 |
| Screen text on Teams | 0.77K-25.8K per hour of new lines | MEASURED | rv:357 |

### 5.3 Disk

- Keyframes as JPEG q70: 26.2 MB per recording-hour and 37.6 MB per share-hour (MEASURED, rv:19).
- The source video itself is about 467 MB per hour (MEASURED, rv:40).

### 5.4 Cloud prices per video-hour

ESTIMATED by the research from DOCUMENTED unit prices (vaa:6). Quality on meeting video was never measured (vaa:10, :100).

| Service | Price per video-hour | Source |
|---|---|---|
| Gemini (by model and resolution) | $0.11-0.81 | vaa:13, :37 |
| Twelve Labs Pegasus | $1.75 | vaa:27 |
| Cloudglue describe | $2.40-3.60 | vaa:26 |
| Memories.ai, Reka, Mixpeek | $3.00 each | vaa:29-31 |
| Azure Content Understanding (illustrative) | $3.33 | vaa:50 |
| Azure Video Indexer, standard | $6.84 | vaa:49 |
| Azure Video Indexer, advanced | $11.40 | vaa:49 |

- **Teams/Stream transcript: $0, and it carries real names** (DOCUMENTED, vaa:12, :47). It names accounts, not people, on shared devices and in rooms (DOCUMENTED, d4:17-19; v3a:17).
- **A published research-agent comparison**: Deep Video Discovery (agentic search over an index) cost $0.213 per question at about 0.15M tokens. It beat the same base model's single pass by 17 points on LVBench (DOCUMENTED, mu:30).

---

## 6. Gaps that bound every number above

- **Recordings.** One private Teams recording (2 h 06 m, presenter-heavy) and two public Zoom calls. All English, all technical (ep:237; rv:369; ra:269).
- **Machine.** Every timing was taken at load 21-144 (ep:5; rv:3; ra:5).
- **No ground truth for the Teams recording:**
  - no reference transcript, so cross-engine disagreement is not an error rate (ra:269);
  - no speaker roster or listen, so person-level naming is unmeasured (v3s:96).
- **Meeting types not covered.** Video playing inside the share, whiteboard or camera on paper, and gallery-only meetings "silently yield nothing useful" under the spec as written (cmp:5, :25-28).
- **Codecs.** VP9 and AV1 files did not decode through AVFoundation on the M1 Max until VideoToolbox's supplemental decoders were registered. After that, 25 of 27 excerpts decode (MEASURED, v3s:32, :158; d3:13, :25-26).
