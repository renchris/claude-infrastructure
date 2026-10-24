---
name: video-understanding
description: "Understand a video, motion included: two-tier ingestion (ASR and contact sheets to locate, full-resolution reads to extract) plus motion probes (slit-scan, optical flow, easing fits). Use to watch, summarise or critique a video or YouTube link."
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

- **Speech → text** is near-lossless *for meaning* on clean studio audio, and cheap.
  It is not solved for meetings (20.8-31.0% word error rate), names, pause
  lengths or who said what — see the ASR guardrails in the pipeline below.
- **Motion → anything** is where the work is, and where the naive approach fails
  silently.

## The binding constraint: ~2000px

Claude Code downscales any image you Read to at most **2000px on its long edge**
before the model sees it. The model's own limit (2576px, at most 4784 visual tokens)
sits above that and trims only near-square sheets, to about 1930px
(`~/Development/claude-infrastructure/docs/research/cv-design-review-2026-08-26/agents/A9-capture-fidelity.md` §0a).
For an N-column contact sheet each tile arrives at about `2000 / N` px wide:

| Columns | Tile width | Legible |
| --- | --- | --- |
| 1 | 2000px | Everything — 12px UI text, source code |
| 2 | 1000px | Headings, most body text |
| 4 | 500px | Composition and large text only |
| 6+ | ≤333px | Shot type and colour. Text is gone. |

Total visual information = `(image reads) × 2000²`. **You cannot have both full
temporal coverage and full spatial detail.** Every sampling decision is spending
that budget.

## The pipeline

Two tiers. The cheap tier says *where to look*; the expensive tier says *what it
says*. Never run the expensive tier blind.

```bash
# 0-1 · metadata + media  (check yt-dlp is CURRENT — a stale build reports a bogus
#        format list; the real cause is "nsig extraction failed")
#        Another stale-build symptom: HTTP 403 on every media format while the
#        subtitles download fine, so a partial run looks healthy. Measured
#        2026-10-24: 2026.07.04 got 403; the current release fixed it at once:
#        uvx --from 'yt-dlp[default]@latest' yt-dlp <same args>
yt-dlp --dump-json "$URL" > meta.json
yt-dlp -f "137+bestaudio/best[height<=1080]" --merge-output-format mp4 \
       --write-auto-subs --sub-langs "en-orig,en" -o "video.%(ext)s" "$URL"
#     Take at least 1080p for anything with on-screen text: 1920px fits under the
#     2000px Read clamp; a 720p ingest misread "5" as "8" at sheet scale. An x.com
#     video via cc-read-twitter is capped at 720p unless CC_RT_MAX_VIDEO_HEIGHT=1080.

# 2-3 · audio -> transcript (local, ~43s for 8min, no data leaves the machine)
ffmpeg -i video.mp4 -ac 1 -ar 16000 -c:a pcm_s16le audio16k.wav
whisper-cli -m ggml-large-v3-turbo.bin -f audio16k.wav -osrt -oj -of asr
#     ASR guardrails (each measured on a 47-min interview, 2026-10-23):
#     - drop segments past the file's end or over exact-zero audio (whisper
#       invented "Thank you." over digital silence);
#     - take pause lengths from audio energy (silencedetect), never from word
#       times, which erased a measured 1.15 s pause;
#     - seed --prompt with spellings read off the screen (names came out wrong);
#     - when chunking long audio, overlap the chunk boundaries.

# 4 · structural map — where are the hard cuts
ffmpeg -i video.mp4 -vf "select='gt(scene,0.2)',metadata=print:file=scenes.txt" -an -f null -
#     The scene filter is a LOWER BOUND: at 0.3 it missed 168 of ~345 hard cuts on
#     an interview whose wide and close shots share one backdrop. When cut counts
#     or shot spans matter, use per-frame mean luma difference (strong cut >= 20,
#     local peak over +-2 frames so a dissolve counts once):
#     ffmpeg -i video.mp4 -vf scale=96:54,format=gray -f rawvideo - | python3 -c \
#       'import sys,numpy as n;a=n.frombuffer(sys.stdin.buffer.read(),n.uint8).reshape(-1,54,96).astype(int);d=n.abs(n.diff(a,axis=0)).mean((1,2));print(*[i+1 for i in range(len(d)) if d[i]>=20 and d[i]==d[max(0,i-2):i+3].max()])'
#     (frame index of the first frame after each cut; divide by fps for seconds.
#     Measured: 43/43 hand-verified cuts in 3 min of that interview, 0 extras.)

# 5 · coarse sweep — 1 frame / 10s, 4 columns, timestamps burned in
#     (ffmpeg here has NO drawtext/libfreetype; label via ImageMagick with -font)
#     TIMING TRAP: the fps=1/N filter emits frame k at k*N + N/2, so labels taken
#     as k*N are N/2 early (measured: every 20s-sheet label was 10s early). Label
#     with k*N + N/2, or extract each tile with its own input-side -ss.
#     FAST-CUT footage (step 4 finds a cut every ~1s — montages, trailers): a
#     fixed interval skips whole shots, so take ONE frame at the midpoint of each
#     scene interval instead. Measured: a 35s montage had 31 shots; 2s sampling
#     would have missed about half of them.

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
- Hearing. Music onsets, ducking, edit silences and digital silence ARE
  answerable from numbers (ffmpeg `astats`/`silencedetect`, per-0.25 s RMS; in a
  stereo mix with mono dialogue the L-R side channel is a clean music detector).
  Report per-bin values, never only a window mean, which blended a -42 dB and a
  -29 dB phase into one wrong answer. Prosody, laughter and naming a tune are not
  recoverable this way.
- Anything between samples. At 10s sampling a 1s event has ~10% odds of capture.
- Who is speaking. Pitch did not separate the two voices on that interview. Lip-motion crops at
  8-24 fps over the window answered it; local diarization needs its threshold
  tuned (the default put 2,616 of 2,646 s of speech on one speaker).

Full derivation, measurements and traps:
`docs/research/agent-video-understanding-2026-07-26.md`; the 2026-10-23 blind
probe and its dated corrections to this skill:
`docs/research/video-understanding-human-parity-2026-10-23/REPORT.md`.
