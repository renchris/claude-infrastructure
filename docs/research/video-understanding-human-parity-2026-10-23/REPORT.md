<!-- markdownlint-configure-file {
  "MD013": false
} -->

# Can the Opus 5.5 agent understand a video the way a human watching it does? (2026-10-23)

Scope (frozen): answer the operator's question "Can we fully semantically and spatially understand a video just like a human watching a video through, as the Opus 5.5 agent?", using our prior research (including how Tinycloud works) plus a fresh blind experiment on the video in https://x.com/ycombinator/status/2113654566776709147.

Labels: **MEASURED** = we ran it (this session or a cited earlier session). **DOCUMENTED** = a vendor page, paper or file says it. **INFERRED** = reasoning from the first two. Paths are relative to this directory unless absolute. Scratch files under `/tmp/` will not survive a reboot.

Privacy: numbers taken from `~/.claude/research-artifacts/meeting-video-2026-10-06/` are numbers and methods only.

## Answer

**No, not fully, and the gap is on specific axes.** Opus 5.5 has no video input and no audio input in either the API or Claude Code. It "watches" only through stills and a transcript that tools make for it (DOCUMENTED + MEASURED, `agents/F1-opus55-native-modalities.md:7`, `:62`). With our tool pipeline on one 47-minute YC talking-head interview, it scored **23-24 of 24** on time-windowed lookup questions about layout, clothing, on-screen text, cuts, gestures and non-speech audio. Reading the transcript alone scored **11 of 24** (MEASURED run, judge-graded, `agents/E3-judgement.md:11`, `:145`). That is strong evidence that **the agent can read whatever is in a frame or in a level measurement once it is told where to look**. It is not evidence of human parity, for three reasons:
- no human watched the video for comparison;
- every question handed the agent its time window;
- the test is one video in one genre.

Published benchmarks still put frontier models 20-60 points below humans on fine motion, 3-D spatial configuration, joint audio-visual reasoning and hour-scale memory (DOCUMENTED, `agents/F2-sota-vs-human-benchmarks.md:11-12`, `:169`). Tinycloud does not close those gaps. It turns video into server-written text, and the agent never sees a frame (DOCUMENTED-SRC, `agents/P3-tinycloud-cloudglue-how-it-works.md:48`, `:149-153`).

## Parity table

"Pipeline" = Opus 5.5 in Claude Code plus our `skills/video-understanding` method: whisper ASR, cut list, contact sheets, full-resolution targeted frames, numeric audio probes.

| Axis | Opus 5.5 alone | Opus 5.5 + pipeline (this run) | Against a human | Evidence |
|---|---|---|---|---|
| What is said (speech semantics) | Blind to audio | Transcript carries the content. Chapter boundaries: 0.88 recall at ±30 s, against 0.72 for an evenly spaced grid and 0.52 for random placement | **About parity on clean studio speech.** Multi-party meeting ASR is worse: 20.8-31.0% word error rate | MEASURED `agents/E3-judgement.md:38-40`, `/tmp/vu-review/baseline.py`; `agents/P1-claude-infra-video-corpus.md:42` |
| On-screen text and inserted content | Reads a still well (2000 px per Read in Claude Code) | 4/4 on handles, counts, titles and dates. Full resolution was needed: at sheet resolution "5" read as "8" and "unfinished" as "unlimited" | **At or above a casual viewer**, once the frame is found | MEASURED `agents/E3-judgement.md:139`; `agents/E1-exam-key.md:101`; `agents/F1-opus55-native-modalities.md:55` |
| Static 2-D layout (who sits where, framing, eyelines) | Per frame | 4/4 | Matches the human on these 4 questions. Not tested beyond 2-D screen layout | MEASURED `agents/E3-judgement.md:136` |
| 3-D spatial reasoning (direction, route, cross-view) | n/a | Not tested | **Large gap:** 24-58 points on VSI-Bench and MMSI-Video for frontier models | DOCUMENTED `agents/F2-sota-vs-human-benchmarks.md:39-42` |
| People and appearance | Will not name people from images | 4/4 on clothing, cap emblem, watch and ring. Identity came from captions, never from faces | Matches on these 4 questions | MEASURED `agents/E3-judgement.md:137`; DOCUMENTED `agents/P1-claude-infra-video-corpus.md:98` |
| Who is speaking | Blind | Burned-in captions plus open-mouth frames, 4/4. Local diarization (`fluidaudiocli`, threshold 0.55) separated host, guest and the synthetic assistant voice in 5 of 6 probe windows, but merged the reel narrator into the host. At the default threshold it put 2,616 of 2,646 s of speech on one speaker | **Weaker than hearing**: it needs tuning, and the 0.55 threshold was picked after the default failed | MEASURED `agents/E3-judgement.md:138`; `/tmp/r-uc-probe/diar-s55.json`, `/tmp/r-uc-scripts/diar_report.py` |
| Cuts and edit structure | n/a | The default cut list missed 168 of about 345 strong cuts. Sheet labels were 10 s early. Both were caught only by a rescan | **Worse unless rescanned.** A human counts cuts without effort | MEASURED `agents/E1-exam-key.md:26-27`; `agents/E2b-watcher-full-pipeline.md:18-20` |
| Motion and gesture (sub-second) | Never sees motion | 4/4 with dense frame strips and a per-frame wipe tracker. A 20 s sweep would miss them | Matches when the window is known. **Large gap** on benchmarks (TOMATO 57, VLM4D 37 points) | MEASURED `agents/E3-judgement.md:140`, `agents/E2b-watcher-full-pipeline.md:124`; DOCUMENTED `agents/F2-sota-vs-human-benchmarks.md:56`, `:43` |
| Non-speech audio (music, silence, ducking) | Blind | 4/4 from level and band statistics, not hearing. macOS SoundAnalysis scored music ≥0.5 in 14/14 title windows and 10/10 outro windows, against 0/480 dialogue windows. It missed the ducked song (0/14 after the duck) | **Partial.** Onsets and levels are measurable. A tune cannot be named unless the screen shows it | MEASURED `agents/E3-judgement.md:141`; `/tmp/r-uc-probe/sa.csv`, `/tmp/r-uc-scripts/sa_report.py`; `agents/E2b-watcher-full-pipeline.md:123` |
| Paralinguistics (laughter, tone, prosody, sarcasm) | Blind | Laughter was dropped from the exam as ungroundable. The classifier found 3 laughter hits ≥0.5 (one, at 18:21, matches visible grins) and scored ≤0.13 at all 4 of the key's candidate points | **Not at parity. Untested** beyond this | MEASURED `agents/E1-exam-key.md:84`; `/tmp/r-uc-probe/sa.csv`; INFERRED |
| Hour-scale memory and whole-video watching | Context holds about 385 frames of 2000x1000 per 1M tokens | Not tested. Every question gave its window | **Gap**: 18-48 points on LVBench and HourVideo | INFERRED `agents/F1-opus55-native-modalities.md:84`; DOCUMENTED `agents/F2-sota-vs-human-benchmarks.md:89-91` |
| Social and mental-state inference | n/a | Not tested | **19-27 point gap**, except goal inference | DOCUMENTED `agents/F2-sota-vs-human-benchmarks.md:103-108` |

## 1. What Opus 5.5 can take in

- **Inputs:** text, images (JPEG/PNG/GIF/WebP; only the first frame of a GIF is used) and documents (PDF, plain text). There is no audio or video content block, and none appears in the 142 KB Messages API reference (DOCUMENTED, `agents/F1-opus55-native-modalities.md:15-18`; https://platform.claude.com/docs/en/build-with-claude/vision).
- **Claude Code clamps every image Read to 2000 px per side.** We tested this: a 4000x2000 PNG arrived as 2000x1000 (MEASURED, `agents/F1-opus55-native-modalities.md:55-56`). The API's own ceiling is 2,576 px and 4,784 tokens, and a request with more than 20 images is limited to 2000 px per side anyway (DOCUMENTED, `:32`, `:29`).
- **No video input in Claude Code.** Its binary has flags for images and PDF only, and Read refuses `.mp4`/`.mov`/`.mp3` (MEASURED, `:62`). The changelog through 2.1.310 adds no video input (MEASURED, `agents/F3-tinycloud-and-agent-video-tools-now.md:48`). Claude Code's video-input request #32130 was closed as not planned (DOCUMENTED, `agents/P1-claude-infra-video-corpus.md:32`).
- **Native video elsewhere:**
  - **Gemini** takes video with interleaved audio. It samples 1 fps by default; `fps` can be set in static mode, and agentic mode adjusts the frame rate adaptively. The live video page (updated 2026-10-13) lists Gemini 4 Argon, 3.8 Flash, 3.6 Flash and 3.5 Flash Lite for agentic video; its `.md.txt` copy leaves Argon out (DOCUMENTED, https://ai.google.dev/gemini-api/docs/video-understanding, fetched to `/tmp/vu-apply/dl/gem.html` and `gem.md.txt`).
  - **Qwen3-VL** is open-weights video at 2 fps with no audio (DOCUMENTED, `agents/F1-opus55-native-modalities.md:71`).
  - **Qwen3-Omni-30B-A3B-Instruct** is open-weights (Apache-2.0) and takes audio and video. MLX builds at 4-8 bit exist. We have not tested it (DOCUMENTED, https://huggingface.co/Qwen/Qwen3-Omni-30B-A3B-Instruct, `mlx-community/Qwen3-Omni-30B-A3B-Instruct-4bit`).
  - **OpenAI:** "All latest OpenAI models support text and image input". No video input (DOCUMENTED, https://developers.openai.com/api/docs/models, fetched today).
- **Even native video does not watch motion like a human.** Gemini warns that 1 fps sampling loses fast action (DOCUMENTED, `agents/F1-opus55-native-modalities.md:69`). A local Qwen3-VL called real motion "not moving" on 2 of 2 probes (MEASURED earlier, `agents/P1-claude-infra-video-corpus.md:124`).

## 2. The experiment (E0-E3)

**Subject.** The YC interview attached to the tweet: 47:08, a two-person studio conversation with screen-share inserts (MEASURED, `agents/E0-ingest-manifest.md:10-11`; `agents/F3-tinycloud-and-agent-video-tools-now.md:127-130`). We ingested the **1280x720** variant. The tweet also offers 1920x1080 and 3840x2160 MP4s (MEASURED, `api.fxtwitter.com`, `/tmp/vu-apply/dl/fx.json`). Because Claude Code clamps at 2000 px, the 1080p file would have given about 1.5x more linear detail per Read at no extra clamp. The spatial results here describe that ingest choice, not a model ceiling (INFERRED).

**Design.**
- **Ingest (E0).** Done blind, about 11 min of measured wall-clock: whisper large-v3-turbo, a cut list at threshold 0.3, 12 contact sheets, and a 150-frame shot census (MEASURED, `agents/E0-ingest-manifest.md:19-30`).
- **Exam key (E1).** An agent examiner using the **same toolchain** wrote 24 time-windowed questions on six axes and grounded each one on full-resolution frames and audio measurements (MEASURED, `agents/E1-exam-key.md:3-28`).
  - Some questions describe the event in advance, for example "a small webcam bubble in its lower right" or a quoted line (DOCUMENTED, `/tmp/vu-2026-10-23/exam-questions.md:19`, `:27`, `:31`, `:41`).
  - Laughter was dropped as ungroundable (`agents/E1-exam-key.md:84`).
- **Watchers (E2a, E2b).** Two blind watchers answered:
  - **E2a** had the transcript only.
  - **E2b** had the full pipeline and used 19 image reads, one targeted read per question (MEASURED, `agents/E2b-watcher-full-pipeline.md:9-12`).
- **Judge (E3).** Graded against the key and audited 6 items where watchers and key disagreed (`agents/E3-judgement.md:184`).

**Results** (grades are the judge's calls, summed by `/tmp/vu-e3/calib.py`, which hard-codes them (`calib.py:2-8`); the sums are arithmetic):

| | Transcript only (E2a) | Full pipeline (E2b) |
|---|---|---|
| Score, judge's grading | 11.0 / 24 | 24 / 24 |
| Score, original key and strict grading of the Q3 "no music" sub-claim | 10.5 / 24 (INFERRED) | 23.0 / 24 (INFERRED) |
| Sub-part credit (judge's grading) | 13.3 | 23.4 |
| Details wrong at confidence 70-80 | 1 | 5 (Q3, Q12, Q18, Q19, Q23) |
| Confidently wrong whole answers | 0 | 0 |

Source: `agents/E3-judgement.md:11-17`, `:107`, `:122`, `:145-146`, `:171-177`.

The two judge calls that move E2b between 23 and 24:
- **Q3.** E2b's "no music" under the first lines is contradicted by measurement (`agents/E3-judgement.md:205`), yet it was given ½ (`:107`).
- **Q18.** The item was re-keyed after the judge read E2b's answer. The re-key rests on a re-measurement that reproduced the key's own numbers and found its window average blended a quiet phase with a loud one (MEASURED, `:191-194`, `:219-229`).

**Per axis (judge's grading)** (`agents/E3-judgement.md:136-141`):

| Axis | E2a | E2b |
|---|---|---|
| Spatial layout | 3 | 4 |
| People | 1 | 4 |
| Audio-visual fusion | 3 | 4 |
| Inserted content | 1 | 4 |
| Motion | 1 | 4 |
| Non-speech | 2 | 4 |

**Chapters.** Against the publisher's chapter list (authorship not checked; it came from the task brief, `agents/E3-judgement.md:3`), both watchers recall 15 of 17 boundaries within ±30 s.
- At ±30 s, 0.88 beats a 34-point evenly spaced grid (0.72 mean) and random placement (0.52, p≈0.0004) (MEASURED, `python3 -I /tmp/vu-review/baseline.py`).
- The ±60 s figures (0.94 and 1.00) **are uninformative**: the content-blind grid scores 1.00 at every phase (MEASURED, same script).

**Key quality.** Of the 6 audited items, 4 had key errors: 1 substantive (Q18) and 3 minor (`agents/E3-judgement.md:270-275`). The error rate in the 18 unaudited items is unknown. Errors the key shares with E2b, through the same tools, would not have surfaced (INFERRED).

**Method failures found, all silent** (MEASURED; short cites like `E1:27` mean `agents/E1-exam-key.md` line 27):

- **Cut list.** The `scene>0.3` list missed **168 of about 345 strong cuts**, mostly cuts between the wide shot and the singles, which share one red-foam palette (E1:27, E1:237; E2b:16-18). E2b had to rescan every window it relied on at a threshold near 0.06 (E2b:20). One question (Q20) falls inside a span the cut list called one shot (E1:180).
- **Sheet labels.** With ffmpeg's `fps=1/20` filter, frame *k* shows label + 10 s, so every sheet label was 10 s early (E1:25-26). E0 had flagged this only as "up to half an interval" (E0:38).
- **ASR.** The transcript ends with a hallucinated "Thank you." placed past the end of the file over digital silence (E1:211). Word timestamps erased a measured 1.15 s pause (E1:126). Names came out wrong, including the host's first name and "Buildspace" (E2a:13-16). There are no speaker labels (E0:34), and the 360 s chunk boundaries were left unchecked (E0:35).

**What the experiment does not show** (INFERRED):
- No human watcher was tested, so "parity" here means agreement with a model-written, judge-corrected key.
- Only one video, in the talking-head genre.
- No 3-D, object-tracking, unprompted whole-video or heard-audio test. Non-speech audio came from level measurement, not from hearing.

## 3. What earlier research had already established

- **Self-estimate.** The 2026-07-26 study put speech- and text-heavy video at "90-95% of an attentive human". That was a stated estimate, not a measurement (INFERRED there, `agents/P1-claude-infra-video-corpus.md:34`).
- **Meeting blind test (2 public Zoom calls, 36 questions).**
  - Transcript only scored 0.50 and 0.39. Adding OCR'd screen text raised both to 0.92, and keyframes to 1.00. The image gain could not be told apart from zero (p = 0.50 and 0.25).
  - None of the 108 answers was confidently wrong.
  - No human baseline was run (MEASURED earlier, `agents/P2-meeting-video-measurements.md:56-66`, `:102-104`).
- **Corrections since then:**
  - "speech is solved" did not hold for meetings (20.8-31.0% word error rate, Whisper loops, filler hallucinated over silence) (`agents/P1-claude-infra-video-corpus.md:183`).
  - The 1568 px figure is now 2000 px (`:181`).
  - The motion probes (slit-scan, optical flow, easing fit) turn motion into numbers, but have been validated only on one synthetic film (`:136`).

## 4. How Tinycloud works and why it does not change the answer

- **Architecture.** Cloudglue is a hosted service that turns a video into time-aligned **text** tracks (speech, visual description, scene text, audio description) per 20 s segment. Tinycloud is its CLI and agent harness. The agent reads JSON and never sees frames or audio (DOCUMENTED-SRC, `agents/P3-tinycloud-cloudglue-how-it-works.md:42`, `:48`, `:79`). Results over 6,000 characters are cut to a one-line summary with no pointer (`:98`).
- **Gaps it leaves open.** Speech and on-screen words are closed well enough for retrieval. Spatial layout, motion and continuity, identity over time, paralinguistic audio and charts are **not closed** (INFERRED from teardown, `:149-153`). We have no measured quality figure on our own recordings (`:34`).
- **Status.** Still 0.3.25 (2026-09-01), with no release in 52 days (MEASURED, `agents/F3-tinycloud-and-agent-video-tools-now.md:29-31`). The October ruling stands: borrow the design and run it on-device (`:38-39`).
- **Other tools.** Every agent tool found either feeds Claude stills plus text or relays a cloud model's text (`agents/F3-tinycloud-and-agent-video-tools-now.md:89-91`).
  - claude-eyes and video-understanding-skill (October 2026) converged on our index-then-zoom design, and neither does optical flow (`:98-104`).
  - Egress trap: `claude-video`'s `--engine auto` uploads to Gemini whenever a `GEMINI_API_KEY` resolves (`:92-97`).

## 5. What would close the remaining gaps, by expected gain per unit of effort

Each row targets a gap measured in this probe or in earlier runs. Short cites: `E0`-`E3`, `F1`-`F3`, `P1`-`P3` are files in `agents/`; `SK` is `skills/video-understanding/SKILL.md`; `AVU` is `docs/research/agent-video-understanding-2026-07-26.md`. "In SK?" says whether `skills/video-understanding/SKILL.md` already carries it. The `/tmp` scripts cited below do not survive a reboot.

| # | Change | Measured gap it targets | Expected gain (I) | Effort | In SK? |
| --- | --- | --- | --- | --- | --- |
| 1 | Replace the scene-filter cut list with a frame-difference detector: mean absolute luma difference at 96x54 on every frame, "strong" at 20 or more. Treat any scene-filter list as a lower bound | 168 of about 345 strong cuts missed (E1:27, E1:237); 2 of 6 cuts in a sampled minute (E2b:18); Q20's span (E1:180) | Correct shot spans and cut counts without rescanning each window | Trivial (`/tmp/vu-e1/cutdiff.py`) | **New.** SK:60-61 uses `scene>0.2`, which was untested here; SK:124 recommends PySceneDetect |
| 2 | Label contact-sheet tiles by true frame time: use `-ss` per frame, or add half an interval to `fps=1/N` labels | Every sheet label 10 s early (E1:25-26) | Removes a systematic timing error | Trivial | **New** |
| 3 | ASR guardrails, four parts (listed below the table) | A hallucinated final line (E1:211); a 1.15 s pause erased (E1:126); name errors (E2a:13-16); unchecked splits (E0:35); a vocabulary prompt fixed product-name errors in an earlier test (P1:48) | Removes traps that cost the transcript-only watcher on Q12 and Q24 | Small | **New.** SK:21 calls speech "Solved" |
| 4 | Make a numeric audio probe a standard step: mid/side RMS per 0.25 s, low-band energy share, exact-zero fraction, one spectrogram. Report per-bin values, never only window means | The non-speech axis went from 2/4 to 4/4 (E3:141). But 3 of E2b's 5 wrong details were audio inferences (E3:173-175), and the key's one real error was a window mean (E3:219) | High on the structure of non-speech audio | Small (`/tmp/vu-e3/av.py`, `/tmp/vu-e2b/band.py`) | **New.** SK:131 lists sound as a limit and has no probe |
| 5 | Read a shot-census montage instead of coarse sheets, and stack two native frames per read | 150 frames in 2 reads; 19 reads in all; 0 spent on sheets (E2b:9-12) | Halves the read cost per native-resolution frame | Trivial | **New.** SK:33-42 implies stacking but does not say it |
| 6 | Fetch the highest-resolution variant for text-heavy video | Used 720p while a 4K variant existed (E0:11, F3:128). Sheet-level reads misread two answers (E1:147, E1:191). 720p keeps about 0.76 of the OCR tokens of a tiled 1080p read (P2:205) | Text reliability | Trivial | **Partly.** SK:53 caps downloads at 1080p |
| 7 | A who-is-speaking step: diarization plus lip-motion crops at 8-24 fps | No speaker labels (E0:34). The fusion axis needed face crops (E1:241). Pitch did not separate the voices (E1:176). Diarization gives 81.3% of words to the right speaker on AMI (P2:147) | Low on this video, where fusion was already 4/4; high on multi-party video | Medium | **Partly.** SK:133 names diarization as a limit, not as a step |
| 8 | An index of on-screen text with positions, grepped alongside the transcript | Here the answers came from question-driven reads. In earlier tests OCR text raised screen questions from 0.17-0.25 to 0.83 (P2:63-65) | Recall of on-screen text nobody asked about yet, which is how a human remembers | Medium | **Yes**, as a tool (SK:125), not as a pipeline step |
| 9 | Local audio-event tagging (laughter, applause, music) | Laughter could not be grounded at all (E1:222) | Unknown; an untested proposal | Medium | **New** |
| 10 | Validate `motion-probe.py` on real camera footage | Validated on one synthetic film only (P1:136). This exam's motion questions were discrete events (E3:140) | Unknown until tested | Medium | **Yes** (SK:78-112) |
| 11 | For public video only, escalate 3-D spatial and audio-visual questions to Gemini 3.8 Flash or 4 Argon | Opus has no audio-visual input (F1:7); Gemini is the only native audio-visual path (F1:9) | Moderate, but still 28-58 points below humans (F2:12). Costs $0.11-1.44 per hour (P2:296, F3:59); the video leaves the machine | Small | **Yes** (SK:119-120) |

Row 3's four guardrails:

- drop any segment that runs past the end of the file or sits over exact-zero audio;
- take pause lengths from audio energy, not from ASR word times;
- seed `--prompt` with spellings read from the screen;
- overlap chunk boundaries.

**Ranking logic (INFERRED).** Rows 1-6 cost minutes and fix errors measured on this video. Rows 7-10 widen coverage to footage this video did not stress, such as multi-party audio and fine motion. Row 11 buys modality, not parity.

**What no row closes.** Three things remain:

- hearing (prosody, laughter as a human perceives it, recognising a tune nothing on screen names);
- continuous perception of motion;
- passive one-pass memory.

These need native audio and video input, which Opus 5.5 lacks (F1:7). The benchmarks also say that native input alone does not reach human level yet (F2:169, INFERRED).

**Evidence still missing.** We need a human baseline on the same 24 questions, run both one-pass and with the questions in hand, plus more videos, including the "do not trust me here" classes such as dance, sport and music video (AVU:157-164). Today's n of 24 on one interview cannot settle parity outside talk-plus-screen video.

## 6. Corrections (dated 2026-10-23)

Each entry is a correction to AVU (`docs/research/agent-video-understanding-2026-07-26.md`) or SK (`skills/video-understanding/SKILL.md`).

1. **SK:21 and AVU:24, AVU:96-102: "Speech → text is near-lossless. Solved. Cheap."**
   - Correct for *meaning* on clean studio audio: the transcript alone recovered 15 of 17 chapter boundaries within ±30 s, against 0.72 for a content-blind grid (E3:38, `/tmp/vu-review/baseline.py`, MEASURED).
   - Wrong as stated. On this video ASR invented a final line over silence, erased a 1.15 s pause, misrendered names and gave no speaker labels (E1:126, E1:211; E2a:13-16; E0:34, MEASURED). On meeting audio, word error rates are 20.8-31.0% against human references (P2:126-128, MEASURED).
   - AVU's 94.9% figure compares two machines with each other, not a machine with a human reference (P1:41).
2. **SK:60-61 and AVU:40: ffmpeg `scene` as "where are the hard cuts".**
   - At 0.3 it missed about half the strong cuts on same-palette interview footage (E1:27, E1:237, MEASURED). The skill's 0.2 setting was not tested.
   - Treat a scene-filter list as a lower bound; earlier findings on screen content point the same way (P1:184).
3. **New trap, not in SK:63-64.** Tiles built with `fps=1/N` show label + N/2. AVU:350's per-frame `-ss` method is exact (E1:25-26, MEASURED).
4. **SK:131 and AVU:104-106, AVU:381: "Can I perceive sound? No. Words survive; everything else about the audio does not."**
   - Partly wrong. Music presence, onset, ducking, edit silences and digital silence were all answered from numeric probes: the non-speech axis scored 4/4 (E3:141, MEASURED). The narrower claim stands: we cannot *hear*.
   - Three of the five wrong details came from audio inference, and laughter could not be grounded (E3:173-175; E1:222, MEASURED).
5. **SK:133: "Multi-speaker attribution, unless diarisation is run deliberately."**
   - Too narrow. Who is speaking on screen was answered 4/4 with lip-motion crops at 8-24 fps and no diarization (E1:241; E3:138, MEASURED).
   - Pitch comparison failed to separate the voices (E1:176, MEASURED).
6. **AVU:380: "Can I perceive motion? No."**
   - This line still contradicts the same file's correction at AVU:172 (P1:180).
   - Current reading: discrete motion and edit events are answerable from dense frame strips and per-frame tracking (motion axis 4/4, E3:140, MEASURED). Continuous kinematics on real footage is unvalidated (P1:136).
7. **AVU:276-280 and AVU:384: native-video models have "a materially higher ceiling on motion and audio".**
   - The motion half is not supported. Gemini samples at 1 fps by default and its own docs warn about fast action (F1:68-69, DOCUMENTED). The best models trail humans by 30-57 points on fine-motion benchmarks (F2:65, DOCUMENTED).
   - The audio half stands, because Gemini hears and Opus does not. Audio-visual fusion is still 20-35 points below humans (F2:81, DOCUMENTED).
8. **AVU:64, AVU:74 and AVU:382: the "1568px" clamp.** Superseded. Claude Code reads at 2000 px (F1:55, MEASURED) and the API allows 2576 px (F1:32, DOCUMENTED). SK:25-38 already carries this, but AVU was never edited (P1:181).
9. **AVU:180: Gemini fps "via `videoMetadata`".** The current docs put `fps` in a `processing` object and add an agentic mode (F1:78, DOCUMENTED).
10. **AVU:152-155 and AVU:379: "90-95% of an attentive viewer" for speech- and text-dominant video.**
    - This now has a first data point on a talk-plus-screen interview: 23-24 of 24 headline answers (judge-graded) and 19/24 with every detail right, on 24 time-windowed questions our own tools could ground (E3:11).
    - It is agreement with a model-written key, not a human comparison. Restate the estimate as "with the question and its time window in hand, headline answers match the key; about 80% of details do; no human baseline yet".
11. **SK:53: `best[height<=1080]`.** For text-heavy video, take the highest variant available. This run used 720p while a 4K variant existed, and two answers needed zooms beyond sheet resolution (F3:128; E1:147, E1:191, MEASURED).

## 7. Limits of this report

- **Small sample.** n = 24 questions, one video, one run per watcher and one judge. A one-question swing moves an axis score by 25 points (E3:142, INFERRED).
- **Selection.** Questions were kept only if our own toolchain could ground them, and laughter was dropped (E1:222). So the exam cannot detect gaps our tools share (E3:286-287).
- **Open book.** Both watchers had the questions while working (E2a:3; E2b:3), much as VSI-Bench's humans had unlimited time to re-watch (F2:39). The exam measures "can the pipeline answer about any moment", not "what one passive viewing retains" (INFERRED).
- **No human sat this exam.** Every human figure is a published benchmark baseline, and those come from small samples (F2:175-182).
- **Load.** Wall-clock figures were taken at load average 85-93 on 10 cores (E0:3), so they are upper bounds.
- **Model labels.** The earlier blind-reader experiments never recorded the reader model (P2:54). This probe's watchers were Opus 5.5 subagents (INFERRED from the workflow that spawned them; not recorded in E2a or E2b).

## Reproduce

These paths do not survive a reboot:

- **Ingest:** `/tmp/vu-2026-10-23/` (video, transcript, cuts, sheets, shots, `exam-questions.md`).
- **Examiner:** `/tmp/vu-e1/`, including `cutdiff.py`, `cuts-robust.txt` and the evidence frames in `f/`.
- **Watcher E2b:** `/tmp/vu-e2b/`, including `band.py`, `wipe.py` and the 19 read files.
- **Judge:** `/tmp/vu-e3/`, including `chapters.py`, `calib.py`, `av.py` and `win.py`. Run its Python with `python3 -I` (E3:290-296).

## Review log

Two adversarial reviews (OVERCLAIM, UNDERCLAIM) were run before this file existed; both reviewed the agent files it would cite. Each defect was verified against those files or re-run, then applied when this report was written.

| # | Defect | Disposition |
|---|---|---|
| O1 | "24/24 means parity on groundable questions" (E3:287) | **Fixed.** No human watcher was tested, and the key was written by an agent on the same toolchain (E1:3-7). The report says agreement with a model-written key, not parity. |
| O2 | "near-human … MEASURED" (E2b:121) | **Fixed.** No human was measured. "Near-human" is not used; only the recovered details are reported as MEASURED. |
| O3 | Chapter recall 0.94 at ±60 s presented as signal | **Fixed.** Re-ran `/tmp/vu-review/baseline.py`: the grid scores 1.00 at ±60 s. The report uses ±30 s (0.88 against 0.72 grid, 0.52 random). |
| O4 | "answers every headline question" | **Fixed.** Questions are windowed and some pre-describe the event (exam lines 19, 27, 31, 41, read). Q3 got ½ despite a contradicted claim (E3:107, 205). The score is reported as 23-24. Added the strict E2a figure, 10.5, which the reviewer omitted. |
| O5 | Scores labelled MEASURED | **Fixed.** `calib.py:2-8` hard-codes the grades. They are labelled as the judge's grading, summed by script. |
| O6 | "1-in-24 key-error floor" | **Fixed.** 4 of 6 audited items had key errors, the audit was selected by disagreement (E3:184), and the other 18 are unknown. |
| O7 | Scope unstated | **Fixed.** The report states n=1 talking-head video, 2-D only, and audio from level measurement rather than hearing. |
| O8 | "human-authored chapter list" | **Fixed.** Now "publisher's chapter list, authorship not checked". |
| U1 | F3:109-110 says Argon is missing from the agentic list | **Fixed.** Curl of the live page (updated 2026-10-13) lists Argon; only the `.md.txt` copy omits it. |
| U2 | "Gemini samples at 1 fps" understates it | **Fixed.** 1 fps is the default; `fps` is settable in static mode, and agentic mode adjusts the frame rate (verified in the fetched page). |
| U3 | Qwen3-Omni was missed | **Fixed.** The HF page shows `license_name: apache-2.0`, audio-visual input, and mlx-community 4-8 bit builds. Marked untested. |
| U4 | "audio only through ASR" understates it | **Fixed, with a narrower claim than proposed.** Music detection reproduces (14/14, 10/10, 0/480). The ducked song scored 0/14 after the duck, and laughter is weak (3 hits, 0 at the key's 4 points). So the report says "partial; laughter unreliable", not "recovers … some laughter". The 22 s runtime and the visual laughter check come from the reviewer and were not re-run. |
| U5 | Pitch could not separate voices, but diarization can | **Fixed, with caveats.** `diar_report.py` reproduces the result: 5 of 6 windows separated at 0.55, the narrator merged with the host, the default threshold collapsed to one speaker, and the threshold was chosen post hoc. |
| U6 | Ingest used 720p while 1080p and 2160p exist | **Fixed.** Confirmed via fxtwitter (5 MP4 variants up to 3840x2160). Added the 2000 px clamp context. |
| U7 | "OpenAI docs not reached" (F3:66, 137) | **Fixed.** The page was fetched today and says "text and image input". F1:70 had already cited it. |

No defect was rejected.
