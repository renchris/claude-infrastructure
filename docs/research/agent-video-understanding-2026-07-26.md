<!-- markdownlint-configure-file {
  "MD013": { "tables": false, "code_blocks": false }
} -->

# How an agent actually ingests video — capability, method, and the honest ceiling

**Date:** 2026-07-26
**Context:** Established empirically by ingesting `youtube.com/watch?v=oX43sxhvlWI`
(8m15s, 1080p30) end-to-end, then measuring what survived the process.
**Status:** Reference. The pipeline is reproducible; the ceiling claims are
measured, not assumed.

---

## The one-line answer

I have **no native video input and no native audio input**. Every claim I make
about a video is a claim about *text and still images derived from it*. The
100th-percentile method is therefore not a way of watching — it is a
**transcoding pipeline** that converts a video into the two modalities I do
genuinely process, chosen so that as little meaning as possible is lost in the
conversion.

That conversion is near-lossless for **speech and on-screen text**, and
structurally lossy for **motion and sound**. Everything below quantifies that.

---

## The pipeline that was actually run

Every step below was executed on this machine; none of it is hypothetical.

| # | Step | Tool | Cost | Output |
| --- | --- | --- | --- | --- |
| 0 | Metadata, description, chapters, caption inventory | `yt-dlp --dump-json` | ~3s | title, duration, 157 caption tracks, full description |
| 1 | Media fetch (1080p + audio, muxed) | `yt-dlp -f 137+bestaudio` | ~8s | 42 MB mp4 |
| 2 | Audio extraction | `ffmpeg -ac 1 -ar 16000` | <1s | 16 kHz mono WAV |
| 3 | **ASR** | `whisper-cli` + `ggml-large-v3-turbo` | **43s** | 64 timestamped segments, 1,262 words |
| 4 | Cross-check ASR | YouTube `en-orig` auto-captions vs (3) | ~1s | **94.9% token agreement** |
| 5 | Structural map | `ffmpeg select='gt(scene,0.2)'` | ~32s | 23 hard cuts with timestamps |
| 6 | Coarse visual sweep | `ffmpeg` 1 frame/10s → ImageMagick `montage` 4×3 | ~20s | 5 labelled contact sheets, 50 frames |
| 7 | Targeted detail reads | `ffmpeg -ss T` at native 1920×1080 | ~1s each | full-res frames at chosen instants |

Total wall-clock: **under three minutes** for an 8-minute video, entirely local,
no third-party inference, no data leaving the machine.

### The load-bearing design decision

Steps 3 and 6 are cheap and tell you **where to look**. Step 7 is expensive per
unit and tells you **what it says**. Running 7 blindly across the whole video is
wasteful; running only 3 and 6 misses the substance. The pipeline is adaptive by
construction: *the transcript and the coarse sheets nominate the timestamps that
earn a full-resolution read.*

In this video that mattered enormously. The transcript said, at 04:31, "I asked
it how it did that" — which nominated the 6:35–7:35 range. Full-resolution reads
of that range recovered a complete technical document, including working source
code, that no amount of additional transcript would have contained.

---

## The hard constraint nobody mentions: image downscale

Any image I read is resampled to roughly **1568px on its long edge**. This is the
single most important number in visual video analysis, because it converts
directly into a **coverage-versus-detail trade-off** that cannot be escaped by
being clever.

For a contact sheet of *N* columns, each tile arrives at me about `1568 / N`
pixels wide:

| Columns | Effective tile width | What is legible |
| --- | --- | --- |
| 1 (single frame) | 1568px | Everything, including 12px UI text and source code |
| 2 | 784px | Headings, most body text, UI structure |
| 3 | 522px | Headings, layout, colour, composition |
| 4 | 392px | Composition and large text only |
| 6 | 261px | Shot type and colour only — text is gone |
| 10+ | <160px | Scene-change detection by eye; nothing more |

So the total visual information available to me is bounded by
`(number of image reads) × (1568² pixels)`. There is no configuration where I
get both full temporal coverage and full spatial detail. **Deciding how to spend
that budget is the entire craft of visual video analysis**, and it is why the
adaptive two-tier approach (coarse sweep → targeted full-res) dominates any fixed
sampling rate.

In this run: 50 coarse frames at 4 columns mapped the structure, then 13
full-resolution frames extracted the substance. 63 image reads covered an 8-minute
video better than 200 uniform mid-resolution frames would have.

---

## What survives the transcoding, and what does not

### Channel 1 — audio → text: near-complete, for speech

Whisper `large-v3-turbo` transcribed 8m15s in 43s. Cross-checked against
YouTube's entirely independent ASR: **94.9% of tokens agreed**. Inspecting the
disagreements, essentially all were YouTube's rolling-caption duplication
artefacts rather than substantive word differences. The spoken content is
recovered at effectively full fidelity.

**Irrecoverably lost in this channel:** prosody, emphasis, tone, sarcasm,
hesitation, emotional register, music, sound design, the meaning of silence, and
— for multi-speaker content — who is speaking, unless diarisation is run
separately. This video is a single-speaker monologue, which is the favourable
case; the loss was near zero. It would not be for an interview, a podcast, or
anything where delivery carries meaning.

> This matters more than it sounds. A separate finding in this project
> ([`feedback-transcript-speaker-attribution-discipline`]) traced a three-day
> failure to speaker misattribution in a supplied transcript. Text-from-audio
> silently discards the speaker axis; if the content is multi-party, that axis
> must be reconstructed deliberately, not assumed.

### Channel 2 — video → stills: structurally lossy, and the real ceiling

I sampled 50 frames out of 14,850 for the structural pass — **0.34% of the
frames**. Even with targeted reads, total coverage was well under 1%.

**I cannot perceive motion.** I see poses. Never movement. Velocity, easing,
timing, rhythm, frame-to-frame continuity, whether an animation "feels stiff" —
all of it is inaccessible to me directly. I can *infer* motion from a sampled
sequence, or read it off the source code that generated it, but I never observe
it.

The irony here is worth stating plainly, because it bounds this entire exercise:
**the video is about motion design, and motion quality is precisely the thing I
cannot judge.** I can tell you the film's structure, its palette, its scene
count, its copy, and its exact implementation technique. I cannot tell you
whether it actually looks good in motion. On that question I am relying on the
narrator's assessment, not my own perception.

**Also lost:** anything occurring between samples. At 10-second sampling, a
one-second event has roughly a 10% chance of being caught. Rapid cuts, brief
overlays, flash frames, and micro-interactions are invisible unless scene
detection happens to flag them.

---

## Where this method is strong, and where it fails

**Near-best case (this video scored here):**

- Speech-dominant, single speaker → ASR recovers the narrative
- Static or slow on-screen text → full-res frames recover it perfectly, and I
  read *every word* of a scrolling document that a human viewer would skim past
- Screen recordings, tutorials, conference talks, code walkthroughs, demos
- Low cut rate → few samples suffice to map structure

For this class I would estimate I reach **90–95% of what an attentive human
viewer extracts, and exceed them on text density**. That is a genuine claim: I
recovered the complete source-code listing and an eleven-row technique table from
this video. A human watching at normal speed would not have retained those.

**Structural failure cases — do not trust me here:**

- Dance, sport, physical performance, choreography
- Motion-design *critique* (as opposed to motion-design *description*)
- Editing rhythm, pacing, comic timing
- Music videos, ASMR, sound-design-led work
- Anything where the meaning is in *how* something moves or sounds
- Long-form where a fleeting moment carries the point

For these I am not "worse than a human viewer" by a margin — I am doing a
different and much weaker thing: reading a sparse description assembled from
samples.

---

## Correction: "I cannot perceive motion" is a default, not a ceiling

The section above states motion is inaccessible. That is true of *frame sampling*
— it is **not** true of what an agent can be equipped with, and treating it as a
ceiling was the wrong framing. Two facts change the picture.

**1 · Frame sampling is the universal substrate, including for "native video"
models.** Gemini's video path samples at **1 fps by default** (258 tokens/frame,
`fps` configurable via `videoMetadata`). It is not perceiving continuous motion
either; it is sampling, then interleaving audio. So "get a video-native model" is
not the answer to motion — at 1 fps it sees *less* temporal detail than a
targeted local sweep, and it is strictly worse than the option below for
questions about *how* something moves. Its genuine advantages are semantic
coverage, audio interleaving, and zero engineering.

**2 · Motion can be made legible in a still.** Motion does not live in any
frame — it lives *between* frames. So the high-leverage move is to transform the
temporal axis into a spatial one, or into numbers. `tools/motion-film/
motion-probe.py` implements four such probes (opencv + numpy, local, free):

| Probe | Turns motion into | Answers |
| --- | --- | --- |
| `slice` | A spatiotemporal (slit-scan) image — one pixel-column per frame | Cut structure, holds, and **easing as literal curvature** of a streak |
| `flow` | Dense optical-flow magnitude per frame, as a table | *When* motion happens and how much; stutter; dead air |
| `trail` | Temporal max-composite (long exposure) | An element's whole trajectory in one still |
| `curve` | A tracked scalar at full frame rate, fitted against easing functions | **Which easing function**, measured, not eyeballed |

### Validated against ground truth

The probes were checked against a film whose source I wrote, so the correct
answer was known in advance:

| Element | Ground truth in `film.js` | `curve` verdict | linear RMSE |
| --- | --- | --- | --- |
| Closing `reso` mark | `outExpo`, 26px | **outExpo** (RMSE 0.056) | 0.447 (8x worse) |
| Door clipboard | `outBack`, 40px | **outBack** (RMSE 0.0589) | 0.436 |

And `flow` located the `headline` cut at **t=10.600s** — the exact value in the
scene table — from pixels alone.

**Calibrate the claim honestly, though.** The probe **decisively** separates
weighted from linear easing (≈8x RMSE separation). It ranks *within* the weighted
family only **weakly**: outBack beat outExpo on the clipboard by 0.0589 vs
0.0594, a 0.8% margin that is effectively a coin flip. So: "this motion is
properly eased, not linear" is a supportable measured claim. "This is
specifically outBack" is not, on a single element.

`flow` also surfaced something not visible by watching: 83 of 119 sampled frames
in the first 12s register as static. That is a real pacing critique of the film,
found by measurement.

### Measured: a native-video VLM is strong on semantics and blind to motion

`mlx-vlm` 0.6.7 + `Qwen3-VL-4B-Instruct-4bit` (2.9 GB, native `--video`/`--fps`
input) was installed and tested on the same film, on an M1 Max. Two probes:

| Clip | Ground truth | Qwen3-VL answer |
| --- | --- | --- |
| Close mark, 1.3s @12fps (6,226 tok) | `reso` travels 18.6px up on `outExpo` | *"There is no visible motion... It is a static image... **not moving**"* |
| Sync scene, 2.2s @4fps (3,547 tok) | Gold dot travels 252px L→R; counter runs 0→289 | Read **all** text correctly (`289 ms`, the caption, DOOR/FLOOR boxes) but called the dot *"a small dot or indicator on the line"* — static — and treated the counter as a fixed value. Never answered the direction question. |

So on a task where a 200-line opencv script returned *"outExpo, RMSE 0.056,
8x better than linear"*, the video-native model returned *"not moving."*

Two caveats, stated so the finding is not over-read: this is the **4B 4-bit**
tier (the smallest), and a larger model or Gemini would very likely do better.
At 12fps the same clip also produced an **empty generation** at 9,732 tokens —
frame budget needs tuning per clip. But the direction of the result is
consistent across both tests and matches the structural argument: these models
sample frames and reason semantically over them; nothing in that pipeline
measures displacement between frames.

Where the VLM *was* genuinely excellent: reading every piece of on-screen text
out of the video without a separate OCR pass, and describing composition. That
is the job to give it.

### So what should actually be installed

Ranked by capability gained per unit of effort:

1. **`motion-probe.py`-style transforms** (opencv + numpy + ffmpeg). Free,
   local, and the *only* option that answers precise motion questions. Nothing
   else on this list can tell you an easing curve.
2. **Whisper large-v3-turbo locally** for the audio channel — already covered.
3. **A native-video API (Gemini) for semantic breadth** on long or unfamiliar
   footage: "what happens, roughly, across 40 minutes". Do not use it for motion
   quality. Costs money and sends the content to a third party.
4. **A local video VLM via MLX** (`mlx-vlm` + Qwen3-VL, which added
   timestamp-grounded temporal localisation) on Apple Silicon. Private and free
   after download; on an M1 Max/64GB this is comfortable. Best for semantic
   description when the content cannot leave the machine.
5. **PySceneDetect** over raw ffmpeg scene detection — content-aware and adaptive
   detectors, better shot boundaries.
6. **OCR** (Apple Vision framework natively, or PaddleOCR) when the goal is
   exhaustive on-screen text with positions and timestamps.

The unintuitive part is the ranking. The instinct is to reach for the biggest
model; but for *motion*, a 200-line opencv script beats every VLM on this list,
because it measures the thing directly instead of describing a sample of it.

---

## Honest note on the ceiling being harness-specific

The ceiling described here is **the ceiling of this toolchain**, not of the state
of the art. Models with native video ingestion (Gemini's ~1fps native video path
being the clearest current example) genuinely take video and audio as first-class
input, and have a materially higher ceiling on motion and audio content than the
transcode-and-sample method above.

What this local pipeline has instead: it runs entirely on this machine, sends
nothing to a third party, costs nothing per run, and — for the speech-plus-text
class of video, which is most work-relevant video — closes most of the gap. That
was the right trade here. It would be the wrong trade for analysing a dance
performance.

I did not use a native-video model for this task and therefore cannot claim to
have exhausted the state of the art. I can claim that the method above extracted
enough to reconstruct the video's complete technical content, verifiably, because
the reconstruction was then implemented and it worked.

---

## Convergent validation (the part that was genuinely surprising)

Before reading the video's contents, I chose contact sheets as the review
instrument because the image-downscale arithmetic above forces that choice.

The video, at 06:40, independently prescribes the same thing — as the method for
analysing motion design:

> *"What does each second look like? → `fps=1, tile=5x5` built a contact sheet:
> 25 frames laid out in a grid as one image. That contact sheet is the whole
> analysis. One glance and you can see all 35 scenes, the pacing, the palette,
> which moves repeat. Any time you want to study a piece of motion design, do
> this."*

And at 07:00, as the method for *reviewing* it:

> *"I never watched the film to review it. I rendered it at 1 frame per second
> (39 frames, 1.6 seconds of work) and tiled it into two contact sheets. Four
> defects were visible instantly as still images… **Look at grids of stills, not
> video** — motion hides problems, stills expose them."*

Two independent parties arriving at the same instrument is reasonable evidence
that it is the right one. It also generalises past agents: the reason it works is
not that a model reads images — it is that **a grid of stills makes the whole
temporal structure simultaneously comparable**, which motion, being sequential,
never does.

This was then confirmed a third time, adversarially: rendering the reso film in
`tools/motion-film/` at 1fps exposed four real defects (blank opening frame,
`THEDOOR` word-spacing collapse, muddy background, half-second empty box at a
cut) that were invisible during playback. See that README for the table.

---

## Reproducing this

The steps are ordinary shell. Requirements: `yt-dlp` (recent — the 2025 build
failed with `nsig extraction failed` and had to be replaced), `ffmpeg`,
ImageMagick, and a local Whisper build with `ggml-large-v3-turbo`.

```bash
# 0-1 · metadata and media
yt-dlp --dump-json "$URL" > meta.json
yt-dlp -f "137+bestaudio/best[height<=1080]" --merge-output-format mp4 \
       --write-auto-subs --sub-langs "en-orig,en" -o "video.%(ext)s" "$URL"

# 2-3 · audio -> transcript
ffmpeg -i video.mp4 -ac 1 -ar 16000 -c:a pcm_s16le audio16k.wav
whisper-cli -m ggml-large-v3-turbo.bin -f audio16k.wav -osrt -oj -of asr

# 5 · structural map: where are the hard cuts
ffmpeg -i video.mp4 -vf "select='gt(scene,0.2)',metadata=print:file=scenes.txt" -an -f null -

# 6 · coarse sweep: 1 frame / 10s, 4 columns, timestamps burned in
#     (this ffmpeg build lacks drawtext/libfreetype, so ImageMagick labels)
ffmpeg -ss $T -i video.mp4 -frames:v 1 -vf scale=620:-1 f.jpg
magick f.jpg -font Arial -pointsize 34 -fill yellow -undercolor '#000c' \
      -gravity NorthWest -annotate +10+10 " ${T}s " f.jpg
montage -font Arial f_*.jpg -tile 4x3 -geometry +3+3 -background '#111' sheet.jpg

# 7 · targeted full-resolution reads at instants the transcript nominated
ffmpeg -ss $T -i video.mp4 -frames:v 1 -q:v 2 hires.png
```

Two traps worth recording:

- **`yt-dlp` staleness is silent-ish.** A 16-month-old build reported "Requested
  format is not available" and listed only storyboards. The real cause was
  `nsig extraction failed`. Always check the version before believing a format
  list.
- **A venv Python has no CA bundle on macOS.** `yt-dlp` then dies with
  `CERTIFICATE_VERIFY_FAILED`. Fix: `pip install certifi` and export
  `SSL_CERT_FILE` to `certifi.where()`.
- **This `ffmpeg` build has no `drawtext`** (compiled without libfreetype). Frame
  labelling has to go through ImageMagick, which needs an explicit `-font` path
   or it fails with an `unable to read font` error naming an empty path.

---

## Summary judgement

| Question | Honest answer |
| --- | --- |
| Can I ingest video? | Not natively. I transcode it to text + stills, both of which I do process genuinely. |
| Can I *understand* it? | For speech- and text-dominant video, yes — to 90–95% of an attentive viewer, and beyond them on text density. |
| Can I perceive motion? | **No.** I see poses, never movement. Inference from samples only. |
| Can I perceive sound? | **No.** Words survive; everything else about the audio does not. |
| What is the binding constraint? | The ~1568px image downscale, which forces a coverage-vs-detail budget. |
| What is the right method? | Adaptive two-tier: cheap ASR + coarse contact sheets to locate, full-resolution targeted reads to extract. |
| Is this the state of the art? | No — native-video models have a higher ceiling on motion and audio. This is the best *local, private, zero-cost* method, and it is sufficient for most work-relevant video. |
| Did it work here? | Verifiably. The extracted technique was implemented in `tools/motion-film/` and produces the described output. |
