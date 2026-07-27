---
name: video-understanding
description: Ingest and genuinely understand a video — including MOTION, which frame sampling structurally cannot see. Use when asked to watch/analyse/summarise a video or a YouTube link, to critique motion design or an animation's easing/timing, to extract on-screen text or code from a screen recording, or to reverse-engineer how a piece of motion graphics was made. Covers the adaptive two-tier ingestion pipeline (local ASR + coarse contact sheets to LOCATE, full-resolution targeted reads to EXTRACT), the ~1568px downscale budget that governs every sampling decision, and the motion-probe transforms (slit-scan, optical flow, motion trails, easing-curve fitting) that make motion measurable. NOT for GENERATING motion graphics — that is tools/motion-film.
---

<!-- markdownlint-configure-file {
  "MD013": { "tables": false, "code_blocks": false }
} -->

# Understanding video

## The one thing to internalise

You have **no native video input and no native audio input**. Every claim you make
about a video is a claim about text and stills derived from it. So this is a
transcoding problem, and the whole craft is choosing a transcode that loses as
little of the thing you were asked about as possible.

Two channels behave completely differently:

- **Speech → text** is near-lossless. Solved. Cheap.
- **Motion → anything** is where the work is, and where the naive approach fails
  silently.

## The binding constraint: ~1568px

Any image you read is resampled to roughly **1568px on its long edge**. For an
N-column contact sheet each tile arrives at about `1568 / N` px wide:

| Columns | Tile width | Legible |
| --- | --- | --- |
| 1 | 1568px | Everything — 12px UI text, source code |
| 2 | 784px | Headings, most body text |
| 4 | 392px | Composition and large text only |
| 6+ | ≤261px | Shot type and colour. Text is gone. |

Total visual information = `(image reads) × 1568²`. **You cannot have both full
temporal coverage and full spatial detail.** Every sampling decision is spending
that budget.

## The pipeline

Two tiers. The cheap tier says *where to look*; the expensive tier says *what it
says*. Never run the expensive tier blind.

```bash
# 0-1 · metadata + media  (check yt-dlp is CURRENT — a stale build reports a bogus
#        format list; the real cause is "nsig extraction failed")
yt-dlp --dump-json "$URL" > meta.json
yt-dlp -f "137+bestaudio/best[height<=1080]" --merge-output-format mp4 \
       --write-auto-subs --sub-langs "en-orig,en" -o "video.%(ext)s" "$URL"

# 2-3 · audio -> transcript (local, ~43s for 8min, no data leaves the machine)
ffmpeg -i video.mp4 -ac 1 -ar 16000 -c:a pcm_s16le audio16k.wav
whisper-cli -m ggml-large-v3-turbo.bin -f audio16k.wav -osrt -oj -of asr

# 4 · structural map — where are the hard cuts
ffmpeg -i video.mp4 -vf "select='gt(scene,0.2)',metadata=print:file=scenes.txt" -an -f null -

# 5 · coarse sweep — 1 frame / 10s, 4 columns, timestamps burned in
#     (ffmpeg here has NO drawtext/libfreetype; label via ImageMagick with -font)

# 6 · targeted full-res reads at the instants the transcript nominated
ffmpeg -ss $T -i video.mp4 -frames:v 1 -q:v 2 hires.png
```

The transcript nominates the timestamps worth paying full resolution for. On an
8m15s video, 63 image reads beat what ~200 uniform mid-res frames would have
given — and recovered a complete source-code listing.

## Motion: use `tools/motion-film/motion-probe.py`, not a bigger model

**Frame sampling is the universal substrate, including for "native video"
models.** Gemini samples at 1 fps by default. Nothing in that pipeline measures
displacement between frames. Measured on this repo's own fixture film:

| Question | Qwen3-VL-4B (native `--video`) | `motion-probe.py curve` |
| --- | --- | --- |
| How does the mark move? | *"There is no visible motion… **not moving**"* | `outExpo`, RMSE 0.056, 8x better than linear |
| Dot travelling 252px | *"a small dot or indicator on the line"* (static) | — |

The VLM read **every on-screen text string correctly**. That is the job to give
it. It is blind to motion.

```bash
python3 tools/motion-film/motion-probe.py slice VIDEO.mp4 --out st.png \
        --marks "sceneA@0,sceneB@3.6"        # slit-scan + time axis
python3 tools/motion-film/motion-probe.py flow  VIDEO.mp4 --from 0 --to 12 --step 6
python3 tools/motion-film/motion-probe.py trail VIDEO.mp4 --from 10.6 --to 12
python3 tools/motion-film/motion-probe.py curve VIDEO.mp4 --from 32.2 --to 33.45 \
        --roi 0.28,0.30,0.72,0.72
```

- **`slice`** — one pixel-column per frame. Time becomes the x axis, so motion
  becomes geometry: vertical break = hard cut, diagonal streak = movement,
  **curvature of the streak = the easing**, staircase = a stagger. Always pass
  `--marks`; without a time axis it is decorative, not diagnostic.
- **`flow`** — per-frame optical-flow magnitude. Locates cuts to the frame and
  exposes dead air (it flagged 83/119 static frames in a film that felt fine).
- **`curve`** — tracks an element at full rate and fits easing functions.

**Calibrate before trusting `curve`:** it *decisively* separates weighted easing
from linear (~8x RMSE gap). It ranks *within* the weighted family only weakly —
outBack beat outExpo by 0.0589 vs 0.0594 on one element, a coin flip. Claim "this
is properly eased." Do not claim "this is specifically outBack" from one element.

## Choosing tooling

1. **`motion-probe.py` transforms** — the only thing that answers motion
   questions. Free, local, no model involved.
2. **Whisper large-v3-turbo locally** — the audio channel.
3. **Gemini native video** — semantic breadth over long unfamiliar footage. Not
   motion. Costs money, sends the content off-machine.
4. **Local VLM** (`mlx-vlm` + Qwen3-VL, native `--video`/`--fps`) — excellent at
   pulling every on-screen string out of a video; private. Tune the frame budget:
   the same clip produced an empty generation at 9,732 tokens and worked at 3,547.
5. **PySceneDetect** over raw ffmpeg scene detection.
6. **OCR** (Apple Vision natively) for exhaustive text with positions.

## Honest limits that remain

- Aesthetic judgement of motion. You can measure that something is eased and how;
  whether it is *good* is not measurable.
- Sound beyond words — prosody, music, sound design, silence-as-meaning.
- Anything between samples. At 10s sampling a 1s event has ~10% odds of capture.
- Multi-speaker attribution, unless diarisation is run deliberately.

Full derivation, measurements and traps:
`docs/research/agent-video-understanding-2026-07-26.md`.
