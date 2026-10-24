<!-- markdownlint-configure-file {
  "MD013": { "tables": false, "code_blocks": false }
} -->

# P1: what the claude-infrastructure corpus already established about agent video understanding

Date 2026-10-23. Worker P1. Read-only distillation, plus three `ls`/import checks run this session.

## Labels

- **MEASURED**: a run recorded in the corpus by an earlier session of ours (file:line given), or **MEASURED-now** for a check I ran in this session (command given).
- **DOCUMENTED**: a vendor doc or paper says it, as quoted in the corpus (URL given).
- **INFERRED**: reasoning, by the corpus author or by me (marked "P1" when it is mine).

## Path keys

| Key | Path |
|---|---|
| AVU | `/Users/chrisren/Development/.worktrees/wt-cc-212741-59630/docs/research/agent-video-understanding-2026-07-26.md` (byte-identical to the main-checkout copy, MEASURED-now: `diff -q` printed nothing) |
| SK | `/Users/chrisren/Development/.worktrees/wt-cc-212741-59630/skills/video-understanding/SKILL.md` |
| MFR / MP | `~/Development/claude-infrastructure/tools/motion-film/README.md` / `motion-probe.py` |
| A9, A10, A1 | `~/Development/claude-infrastructure/docs/research/cv-design-review-2026-08-26/agents/A9-capture-fidelity.md`, `A10-motion-interaction.md`, `A1-local-vlms.md` |
| PS | `~/Development/claude-infrastructure/docs/research/cv-design-review-2026-08-26/PIPELINE_SPEC.md` |
| VID | `~/Development/claude-infrastructure/docs/research/sdk-browser-toolsets-2026-10-07/video.md` |
| BLP | `~/Development/claude-infrastructure/docs/research/browser-loop-probe-2026-10-08/REPORT.md` |
| MV/ | `~/.claude/research-artifacts/meeting-video-2026-10-06/`. MU = `model-understanding.md`, EP = `empirical-probe.md`, RRA = `real-recording-audio.md`, RRV = `real-recording-visual.md`, ASR = `v2-asr-bakeoff.md`, DIAR = `v3-local-diarizers.md`, VC = `visual-channel.md`, VXJ / VXK = `value-exp/jup1080-VERDICT.md` / `k8s1080-VERDICT.md` |

Privacy: the MV/ numbers below are numbers and methods only. No person's name or spoken content from any MV/ file is copied here.

## 0. The corpus's one-line position

- The agent has **no native video input and no native audio input**. Every claim about a video is a claim about text and stills derived from it, so the method is a transcoding pipeline (AVU:17-22; SK:14-17). This has not been revised. DOCUMENTED support: Claude vision lists JPEG/PNG/GIF/WebP only, and "Animations are unsupported, and only the first frame is used" (A10:218-221, citing <https://platform.claude.com/docs/en/docs/build-with-claude/vision>). The Claude Code video-input request anthropics/claude-code#32130 was closed as not planned (A10:220-221). A third-party "Claude real-time video API" claim was checked and rejected as unsubstantiated (A10:216-222).
- The first ceiling claim was "near-lossless for speech and on-screen text, structurally lossy for motion and sound" (AVU:24-25). Section 9 lists the corrections later files made to it.
- For speech- and text-dominant video, the self-estimate is **90-95% of an attentive human viewer, and better than one on text density** (AVU:152-155, 379). **INFERRED.** It is a stated estimate, not a measurement. No corpus file measures human-parity comprehension directly. The nearest measured proxy is the MV/ 18-question blind test (section 7).

## 1. Speech

| What was measured | Number | Label / source |
|---|---|---|
| Whisper large-v3-turbo on an 8m15s single-speaker monologue | 43 s; 64 segments, 1,262 words | MEASURED, AVU:38, 98 |
| Agreement with YouTube's independent ASR | 94.9% of tokens. Disagreements were said to be YouTube rolling-caption duplication | MEASURED, AVU:39, 99-102. This is agreement between two machines, not WER against a human reference (INFERRED, P1) |
| WER against human references, 7 meetings (6 AMI, 1 ICSI) | Parakeet TDT v3 mean 20.8% (worst 32.8%); best Whisper setting 24.5% (worst 37.8%); Whisper defaults 31.0% (worst 54.4%) | MEASURED, MV/ASR:8 |
| Whisper repetition loops on meeting audio | defaults loop on 3 of 7 meetings (846, 200 and 200 looped words); `-mc 0` loops on 0 of 7 | MEASURED, MV/ASR:10 |
| Whisper hallucination over silence (2 h 06 m Teams recording, last 35 min digital zero) | `-mc 0` wrote a two-word filler cue 71 times, defaults wrote one 102 times; Parakeet wrote 0 | MEASURED, MV/RRA:10-12 |
| Parakeet silent drop | 10-20 s of audible speech emitted as nothing, 7 stretches in 3 of 7 meetings (0.3-2.4% of reference words); the cause is position-dependent chunk merging | MEASURED, MV/ASR:9 |
| Cross-engine and within-engine disagreement | 8-10% of words cross-engine; 4-6.5% within one engine when the window grid moves | MEASURED, MV/RRA:15 |
| Technical vocabulary | 89-90% of 471 term positions in the on-screen spelling; the product name "Claude Code" right at 1, 1 and 0 of 22 positions (written "cloud code") | MEASURED, MV/RRA:16 |
| Vocabulary prompt fix | a `--prompt` vocabulary line removed the misspelt-product-name errors in the 5-minute slice tested | MEASURED, MV/EP:28, 125 |
| Determinism | whisper.cpp `.txt/.vtt/.json` byte-identical across 2 runs; every engine reproduced its output exactly | MEASURED, MV/EP:26, 214; MV/ASR:13 |
| Speed | 9.6-15.7x realtime under load 40-64 (Whisper); Parakeet 145x realtime | MEASURED, MV/EP:25-27; MV/RRA:11 |

**Stated ceiling.** Lost "irrecoverably": prosody, emphasis, tone, sarcasm, hesitation, emotional register, and who is speaking unless diarisation is run (AVU:104-109; SK:131-133). AVU calls this "the favourable case; the loss was near zero" for a monologue, and says it "would not be" near zero for interviews (AVU:107-109). Whisper also **invents speaker labels**: it prefixed 13 segments with a name carried forward from a spoken introduction, and 2 segments with a name found in no other source (MEASURED, MV/ASR:11).

**Measured comprehension.** Speech-category questions scored 6 of 6 in every condition, transcript-only included, on both recordings (MEASURED, MV/VXJ:8-11; MV/VXK:7).

## 2. On-screen text

| What was measured | Number | Label / source |
|---|---|---|
| Full-resolution targeted frames (2026-07-26 run) | 13 full-res frames recovered a complete source listing and an 11-row technique table, and the reconstruction "was then implemented and it worked" | MEASURED, AVU:88-90, 153-155, 289-291 |
| Native-video VLM text reading (Qwen3-VL-4B-4bit, mlx-vlm 0.6.7) | read **all** on-screen text in a 2.2 s clip correctly | MEASURED, AVU:225-231, 244-246 |
| 60 s launch video, 30 frames at 1 per 2 s, no ASR | every caption and log line transcribed verbatim; text that scrolled between samples was not captured; one frame unreadable from motion blur | MEASURED, VID:5, 20-24, 273 |
| Apple Vision OCR legibility by resolution (45 frames) | 1080p tiled = 1.000 (reference); 1080p untiled 0.877; 720p 0.764-0.768; 360p 0.066 | MEASURED, MV/EP:91-97 |
| Teams 1080p tiling | no gain (2,751 vs 2,719 lines; 26 vs 27 of 31 hand-checked terms) at 1.8-3.4x the time | MEASURED, MV/RRV:18 |
| Small-number failure | untiled 1080p turned a 6-digit ID and a date into wrong digits; 720p dropped 4 of 10 table number cells | MEASURED, MV/EP:99 |
| OCR jitter on an unchanged screen | 34.2% of consecutive unchanged 2 s samples yield at least 1 phantom "new" line | MEASURED, MV/RRV:17 |
| Handwriting from screenshots (claude-haiku-5-5, 3 runs, 27 fields each) | 1 wrong field (a cursive surname) in 2 of 3 runs; 0 in 1 run | MEASURED, BLP:9-12, 71-76 |
| Keyframe compression | WebP q75 keeps 0.924 of OCR tokens at 61 KB; downscaling to 1280 px drops it to 0.79-0.85 | MEASURED, MV/EP:190-202, 208 |

**Stated ceiling: the image clamp.** AVU said images are resampled to about **1568 px** on the long edge, the "single most important number" (AVU:64-67). A9 corrected that to **2000 px**. Claude Code clamps client-side to 2000x2000 and 3.75 MiB before the API sees the image (A9:24-42, constants read from the 2.1.183 binary). The API's high-resolution tier allows 2576 px and 4,784 tokens (DOCUMENTED, A9:46-53, <https://platform.claude.com/docs/en/build-with-claude/vision>). So 2000 px binds (A9:55). SK carries the correction (SK:25-38). A9 says the constant "perishes" and must be re-read per Claude Code version (A9:342).

The legibility table (1 col = 12 px UI text, 4 col = composition only, 6+ col = text gone; AVU:72-79, SK:33-38) is **INFERRED**. It is presented as arithmetic plus observation, and no per-column legibility test is recorded.

More than 20 images in one request means every image must be ≤2000 px or it is **rejected, not downscaled**. Images under 200 px may be hallucinated (DOCUMENTED, A9:57-59).

**Measured comprehension.** Screen-category questions, transcript only: 0.17 and 0.25. With OCR text: 0.83 and 0.83. With OCR text plus keyframes: 1.00 and 1.00 (MEASURED, MV/VXJ:31-34; MV/VXK:20-24; n = 6 per category, one run, one judge).

## 3. Static spatial layout

| What was measured | Number | Label / source |
|---|---|---|
| Composition and palette from 4-column sheets | 50 frames at 4 columns "mapped the structure" (qualitative) | MEASURED (qualitative), AVU:88-90 |
| Sub-perceptual defects judged by the vision model (1 px misalignment, 5/255 colour drift) | 0 of 2 detected | MEASURED, PS:1264-1266, 1403 |
| The same classes read from the DOM layer | 9/9, 0 control false positives | MEASURED, PS:1397 |
| Gestalt judgement (hierarchy, grouping) | 2/2, explicitly n = 2 | MEASURED, PS:1401 |
| Unprompted real defects, blind | 3 per 8 pages, 0 false positives | MEASURED, PS:1260-1261 |
| Published visual-diff benchmark (DiffSpot) | Claude Opus 4.7 38.9%, best of 13 models 47.2%; hard-tier recall under 23% for every model | DOCUMENTED, A1:180-197 |
| Capture artefact that fakes a layout bug | unpinned device scale gives up to 1.5 px baseline drift by the 4th paragraph | MEASURED, A9:94, 273-291 |
| Contact-sheet pixel cost | a 3x3 sheet keeps 31% of per-frame pixels for 3.3x fewer tokens | INFERRED arithmetic from DOCUMENTED patch cost, A10:268-289 |
| Teams layout classification | done deterministically (gutter structure on a 320x180 luma grid); 31.5% of a 2 h recording had no shared content | MEASURED, MV/RRV:14, 64-70 |

**Stated ceiling.** DOCUMENTED: counting is approximate and coordinates are approximate (MV/MU:36, E12). Every geometric finding should be checked against `getBoundingClientRect()`: "a vision model measuring pixels is a sampling instrument" (A9:336). None of these measurements were taken on video frames of physical 3-D scenes. Every spatial measurement in the corpus is on UI, screens or synthetic film (INFERRED, P1, from the inventory of sources above).

## 4. People, faces, identity

| What was measured | Number | Label / source |
|---|---|---|
| Claude naming people from images | will not name people from images | DOCUMENTED, MV/MU:36 (E12), 87 |
| Name label in Zoom camera tiles, read by OCR | readable in 62% of sampled frames (1,014 of 1,627); 73 label changes in 54 min; misspelt variants need fuzzy merging | MEASURED, MV/EP:126 |
| Name label in Teams share layout | readable in 99.8% of share samples; one label highlighted in 85.8%; the highlight is lit in 93.9% of samples with sound vs 5.5% of quiet ones | MEASURED, MV/RRV:20 |
| Diarizer speaker count, 7 reference meetings | right on 6 of 7; mean 81.3% of reference words attributed to the right speaker (worst 72.2%) | MEASURED, MV/ASR:12 |
| Best local diarizer + Teams highlight naming (2 h recording) | 0.4-0.5% of highlighted samples given a wrong name, 1.8-1.9% given no voice; 97-98% agreement with the highlight for 4 systems | MEASURED, MV/DIAR:11-12 |
| One room device carrying several voices | two model families agree on 4 voices (adjusted Rand index 0.908) | MEASURED (agreement) / INFERRED (reading, ~75%), MV/DIAR:13 |
| Diarizer build sensitivity | an older FluidAudio build over-split the presenter into 3 clusters (8 speakers); a newer build found 5 | MEASURED, MV/DIAR:14 |

**Stated ceiling.** Identity comes from the transcript's speaker labels or from name text rendered in the video, "never from faces or voices guessed by a VLM" (INFERRED design rule, MV/MU:87). The corpus measured **no** face recognition, facial expression, gaze or gesture reading (INFERRED, P1: no file in the inventory measures them). "Multi-speaker attribution, unless diarisation is run deliberately" is listed as an open limit (SK:133).

## 5. Motion

**What each probe computes** (MP code read this session):

| Probe | Computation | Answers |
|---|---|---|
| `slice` | For every k-th frame (k = frames / `--width`, default 1500 columns), copies one pixel column at `x = at*W` and one pixel row at `y = at*H` (default `at` 0.5). Stacks them left to right into an X-T and a Y-T image and adds a time ruler with optional named marks (MP:134-182, ruler MP:81-131) | a vertical break is a hard cut, a diagonal streak is movement, a curved streak is easing, a flat region is a hold (MP:181-182) |
| `flow` | Resizes frames to 320 px wide grey and runs Farneback dense optical flow between consecutive sampled frames (`--step` stride). Reports mean flow magnitude plus mean absolute frame difference, marks a CUT when framediff > 22, and counts still frames (flow < 0.05) (MP:188-237) | when motion happens and how much; dead air; cuts |
| `trail` | Per-pixel `np.maximum` across frames in a window, so a long-exposure still (MP:243-257) | one element's trajectory in one image. It traces bright-on-dark subjects only, because it is a max composite (INFERRED, P1, from MP:249) |
| `curve` | Inside a fractional ROI, splits subject from background with an Otsu threshold, rejects a split whose separation is under 25 grey levels, and tracks the **vertical centroid** at native rate. Normalises from the start position to the settled position (median of the last 15%), then fits 8 easing functions by RMSE: verdict "decisive" under 0.05, "plausible" under 0.12; "weighted, not linear" if linear RMSE > 1.6x the best (MP:279-379) | which easing family, as a number |

| What was measured | Number | Label / source |
|---|---|---|
| `curve` on a self-authored film, known ground truth | close mark: outExpo RMSE 0.056 vs linear 0.447 (8x); clipboard: outBack 0.0589 vs outExpo 0.0594 (0.8% margin, "a coin flip") | MEASURED, AVU:204-217; MFR:173-182 |
| `flow` cut location | located the `headline` cut at t = 10.600 s, the exact scene-table value | MEASURED, AVU:209-210 |
| `flow` pacing | 83 of 119 sampled frames in the first 12 s static | MEASURED, AVU:219-221 |
| Native-video VLM on motion (Qwen3-VL-4B-4bit) | a 1.3 s clip at 12 fps (6,226 tokens) of a mark travelling up: "not moving". A 252 px dot travel was called static; direction never answered; the same clip at 9,732 tokens produced an empty generation | MEASURED, AVU:225-242 |
| 1 fps review of the self-authored film | 4 defects visible as stills that were missed in playback | MEASURED, MFR:121-133; AVU:322-325 |
| Fast-cut footage | a 35 s montage had 31 shots; 2 s sampling would have missed about half | MEASURED, SK:65-68 |
| Gemini default sampling | 1 fps, 258 tokens/frame (66 at low resolution); a 200 ms transition lands in 0 or 1 frames | DOCUMENTED, A10:225-238 (<https://ai.google.dev/gemini-api/docs/video-understanding>) |
| Temporal benchmark (TimeBlind) | best of 20+ models 48.2% vs human 98.2% | DOCUMENTED (via search summary), MV/MU:41 |

**Stated ceiling.**

- "Aesthetic judgement of motion": that something is eased "is measurable"; whether it is *good* "is not measurable" (SK:129-130).
- Sampled frames miss anything between samples. At 10 s sampling a 1 s event has about 10% odds of capture (AVU:135-137, INFERRED arithmetic).
- Structural failure classes: dance, sport, choreography, editing rhythm, comic timing, music videos, "anything where the meaning is in *how* something moves or sounds" (AVU:157-168).
- For web UI motion the corpus routes timing to WAAPI/CDP numbers and fences vision to one question, mid-interpolation rendering artefacts (A10:300-339).
- **Validation scope (INFERRED, P1).** The probes were validated on one self-authored synthetic film only. `curve` tracks one vertical scalar, so horizontal, rotational or multi-object motion is not measured by it (MP:287-315). `slice` samples one row and one column (MP:142-155). No probe has been run against real-world camera footage in any corpus file.

## 6. Non-speech audio

| What was measured | Number | Label / source |
|---|---|---|
| Loudness only, 60 s launch video | mean -15.5 dB, max -2.0 dB; whether it was speech or music "NOT STATED" (no ASR model was found at the time) | MEASURED, VID:9-18 |
| Silence map, 2 h recording | silencedetect -40 dB: 46.3% silent; 38.1% of 20 ms frames exact zero | MEASURED, MV/RRA:24-26 |
| Speech share by diarizer | 60.1% of the file | MEASURED, MV/RRA:28 |
| Gemini audio tokenisation | 32 tokens/s | DOCUMENTED, A10:238; MV/MU:34 |

**Stated ceiling.** "Can I perceive sound? **No.** Words survive; everything else about the audio does not" (AVU:381). Music, sound design and silence-as-meaning are lost (AVU:104-106; SK:131). The motion-film tool itself is silent, and its README states that "sound design is roughly half of why a film like this lands" (MFR:232-233). No corpus file measures sound-event classification, music description or emotion from voice (INFERRED, P1). What was measured is energy/silence segmentation and speech/non-speech segmentation only.

## 7. Temporal / causal narrative

| What was measured | Number | Label / source |
|---|---|---|
| Structure map, 8m15s video | 23 hard cuts at `scene > 0.2`; 5 sheets of 50 frames | MEASURED, AVU:40-41 |
| Transcript nominates where to look | a spoken line at 04:31 nominated the 6:35-7:35 range that held the technical document | MEASURED (qualitative), AVU:55-58 |
| ffmpeg `scene` on screen share | `scene > 0.3` kept 28% (demo call) and 65% (slide call) of stable screen words | MEASURED, MV/EP:58, 78 |
| ffmpeg `scene` / PySceneDetect on a synthetic screen clip | 4 of 19 scripted events detected at common thresholds | MEASURED, MV/VC:22 |
| Sampling cadence vs screen-word recall (demo call) | 1 per 10 s caps at 0.821; 1 per 5 s 0.939; 1 per 2 s needed for 97%+; OCR-novelty selector 0.981 with 410 frames | MEASURED, MV/EP:64-71, 81, 84 |
| Cross-modal (speech + screen) questions | transcript only: 0.00 and 0.25. With OCR text: 0.92 and 0.92. With text + frames: 1.00 and 1.00 | MEASURED, MV/VXJ:31-34; MV/VXK:20-24 |
| Wrong-and-confident answers | 0 in every condition. The transcript-only reader declined ("cannot tell") rather than invent | MEASURED, MV/VXJ:15-17; MV/VXK:8 |
| Video-MME-v2 group-consistency | best model 49.4 vs human experts 90.7 | DOCUMENTED (secondary), MV/MU:28 |

**Stated ceiling and design rule.** "Never ask a model to infer order from frames"; order comes from the container's clock and per-line timestamps (INFERRED rule from DOCUMENTED E17/E18, MV/MU:85). The value experiments are n = 18 questions per recording, one reader run per condition and one judge, and 12 of 18 questions were written to need the screen (MV/VXK:10). The reader model is not named in either verdict (MEASURED-now: `rg -i "opus|sonnet|haiku"` over both files found no model name).

## 8. Long-duration memory

| What was measured | Number | Label / source |
|---|---|---|
| Longest video processed end to end | 2 h 06 m 35 s Teams recording; visual pipeline 7.1-7.6 min per recording-hour | MEASURED, MV/RRV:21; MV/RRA:4 |
| Text volume per meeting-hour | speech ~12K tokens; screen text 1.9K (slides) to 39K (live demos), a 20x swing | MEASURED, MV/EP:113-123 |
| Merged speaker turns vs raw cues | 18,846 vs 25,773 tokens (27% smaller) | MEASURED, MV/RRA:20 |
| Keyframes per hour | 38 (slides) to 295 (demos); Teams 13.7/h (slides) to 261-274/h (IDE) | MEASURED, MV/EP:119; MV/RRV:15 |
| Claude image budget | 100 images/request on 200k-context models, 600 otherwise; >20 images forces ≤2000 px per side | DOCUMENTED, A10:239; MV/MU:36 |
| Agentic search over a prebuilt index vs single pass (same base model) | +17 points on LVBench (74.2 vs 57.1) | DOCUMENTED, MV/MU:30 (<https://arxiv.org/html/2505.18079>) |
| Duration decay | GPT-4o 71.4 (8-15 s) to 52.2 (15-60 min); subtitles cut the short-to-long drop from 14.3 to 7.1 points | DOCUMENTED, MV/MU:25-27 |

**Stated ceiling.** No public benchmark measures 30-90 minute screen-share meetings (MV/MU:19). "Understanding was not measured" in the extraction probe (MV/EP:240). That gap is what the later value experiments partly closed, for 44 and 54 minute calls only. The corpus has no measurement of cross-session memory over many videos (INFERRED, P1). The recommended long-video pattern is an offline text index with on-demand frame reads, on the agent's existing grep/Read (INFERRED, MV/MU:76-78).

## 9. Corrections later sections and files made to earlier claims

1. **"I cannot perceive motion" was revised to "a default, not a ceiling"** (AVU:122-126, corrected at AVU:172-197): motion can be transformed into stills or numbers by `motion-probe.py`. **Left unreconciled in the same file:** the summary table still says "Can I perceive motion? **No.**" (AVU:380). The "Honest note" still says native-video models have "a materially higher ceiling on motion" (AVU:276-280, 384). That contradicts the correction's own measured finding that a native-video VLM called a moving mark "not moving" and that Gemini at 1 fps sees less temporal detail than a targeted sweep (AVU:178-186, 225-242). (INFERRED, P1.)
2. **1568 px became 2000 px.** A9:55 corrects AVU:64. The binding limit is Claude Code's client clamp, not the API tier. SK:25-38 adopted it. AVU itself was not edited (AVU:64-90 still say 1568).
3. **The `curve` validation claim was narrowed.** MFR:173-176 says the clipboard "returns `outBack`" as validation. The calibration (AVU:212-217; MFR:178-182) shows a 0.8% margin, so only "weighted, not linear" is supportable.
4. **"Speech → text is near-lossless. Solved. Cheap."** (SK:21; AVU:24, 96-102) was not borne out on multi-party meeting audio. The later measurements are 20.8-31.0% WER vs human references, Whisper loops on 3/7 meetings, filler hallucinated 71-102 times over silence, silent 10-20 s Parakeet drops, invented speaker labels, and a 0-1 of 22 hit rate on one product name (MV/ASR:8-11; MV/RRA:12, 16). The 94.9% figure (AVU:39) was machine-vs-machine agreement on the most favourable case.
5. **ffmpeg scene detection (AVU:40, SK:61) is wrong for screen content.** It recalled 28-65% of screen words at 0.3 (MV/EP:78) and 4/19 events on a synthetic screen clip (MV/VC:22). SK itself added a fast-cut correction (per-scene midpoint frames) for montage footage (SK:65-68).
6. **The single-meeting ASR result "overstated the margin, and hid a Parakeet defect"** (MV/ASR:9).
7. **Within the MV/ corpus the "settled frame is better" argument was dropped for Teams.** The first frame after a change is within 0.42 luma levels of the frame 4 s later (MV/RRV:16).
8. **OCR tiling at 1080p:** it recovered 12% more tokens on a Zoom 1690x1080 recording (MV/EP:94) and gave no gain on Teams 1920x1080 (MV/RRV:18). The two measurements conflict by source, and no rule reconciles them.
9. **The "several people on one device vs one person over-split" question** (MV/RRA:18) was settled toward several people at about 75% (MV/DIAR:13). Diarizer build version was found to matter more than model choice (MV/DIAR:14).
10. **Unprompted-defect rate** corrected from "1 per 13" to "3 per 8 blind pages" (PS:1259-1261).
11. **"No usable Whisper model on this machine"** (VID:14-17, 2026-10-07) was wrong when written. MEASURED-now: `ls ~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/` shows `ggml-large-v3-turbo.bin` (1,624,555,275 bytes, dated Jul 21), and MV/EP:7 had already used it on 2026-10-06. VID searched only `/opt/homebrew/share/whisper-cpp/`.
12. **Ground-truth wording mismatch (INFERRED, P1, unresolved).** AVU:206 gives the close mark's ground truth as "26px" (it matches `translateY(lerp(26, 0, q))`, MEASURED-now: `rg` of `film/film.js:357`). AVU:230 says it "travels 18.6px up". The 18.6 px is probably the measured centroid travel at render scale over the probed window; the file does not say.

## 10. Checks run this session, and scope notes

- MEASURED-now: `whisper-cli`, `fluidaudiocli`, `yt-dlp` and `ffmpeg` are on PATH. `python3 -c "import cv2"` gives 4.13.0. No rendered `reso-film.mp4` exists in `tools/motion-film/`, so the probes were **not** re-run. Rendering would write into another repo's tracked tool directory, which is outside this brief.
- The `rg -il video` sweep matched 79 files (MEASURED-now, `wc -l`). Most are token-efficiency JSON, stream logs and unrelated design notes. Read in full or in the relevant part: A9, A10, A1 (lines 120-200), PS (1255-1405), VID, BLP. The sdk-browser `assessment.md` and `skeptic.md` only reuse VID's numbers.
- Not read (out of this worker's brief, though present in MV/): the `td-tinycloud-*`, `tinycloud-internals.md` and `cloudglue-*` teardown files. No `docs/lessons` file matched "video" (MEASURED-now: `rg -il video docs/lessons` returned nothing).
