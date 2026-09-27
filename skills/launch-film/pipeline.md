# Launch-film pipeline harvest (natural-text-to-voice-extension, v1 → v3)

Root: `~/Development/natural-text-to-voice-extension/`. v1 = `brag-output/`, v2 = `brag-output-2026-09-26-123925/`,
v3 = `brag-output-2026-09-26-151455/` (final). All paths below are under `<vN>/work/` unless stated.

## 0. What "brag" is

- **latent-spaces/brag** (MIT, https://github.com/latent-spaces/brag) is a Claude Code skill/plugin that turns a project
  or URL into a short launch video + share copy. `/brag` (classic) builds on HeyGen Hyperframes with bundled music
  (ende.app "happy beats" mp3s + cue JSON) and UI SFX (.ogg). **`/brag-slim`** (from plugin 0.4.0) is the Opus 5.5
  route: one 101-line `SKILL.md`, no bundled assets, "build it with whatever works on this machine".
- **Not installed** anywhere under `~/.claude*`/plugins/skills/commands or `~/.agents`. It was fetched to
  `/tmp/brag/c893c5ed…` (symlink `/tmp/brag/current`; second copy `/tmp/brag-src-0926/`) and followed **by path**.
  Both are in /tmp and perishable.
- v1 `brag-plan.md:3`: "Made with `/brag-slim` (latent-spaces/brag `c893c5e`, 2026-09-24)". brag contributed **only the
  procedure and creative laws**; every script in `work/` is ours. brag-slim rules the pipeline enforces:
  - `SKILL.md:20`: write to `brag-output/` (timestamped if it exists), keep all intermediates in `work/`.
  - `SKILL.md:93`: "make every frame a pure function of time and wait for fonts and images to load".
  - `SKILL.md:95`: check stills from every scene *and* mid-transition before the full render (→ `sheet.sh`).
  - `SKILL.md:99`: bake the poster in as frame 0 by *replacing* frame 0 (→ `finish.sh` overlay `enable='eq(n,0)'`).
  - `SKILL.md:63,68`: 15–25 s; readable text held ~0.3 s/word once whole.
- The one external dependency on brag's assets: `sound/soundtrack2.py:61` `REFERENCE_GLOB =
  "/tmp/brag-src-0926/skills/brag/assets/music/*.mp3"`, used only to report band balance against brag's bundled
  tracks (`tone2.py` then EQs toward them). Missing /tmp copy → that report section is lost, not the render.
- Separately, the **claude-infrastructure** film (candidate 4) was also made with `/brag-slim`, on the unlanded branch
  `hero-brag` (worktree `~/Development/.worktrees/hero-brag`, commits 34684c59d..d9c8fbe53, not on origin/main). It has
  its own, different toolchain: `scripts/hero-brag-{capture.mjs,render.sh,pacing.py,score.py,review.py}`, capture via
  `window.__seek(t)`, **6 parallel CDP workers**, 3840×2160 @ 60 fps, JPEG q97, CRF 14, AAC at −16 LUFS, plus a
  pacing gate. Worth reconciling with this kit rather than forking a third.

## 1. v1 → v2 → v3: what was added when

| File | v1 | v2 | v3 |
|---|---|---|---|
| `render.mjs` | 94 lines | +CDP 90 s timeout, `--sub N` motion blur, URL relative to its own folder (101 lines) | = v2 (byte-identical) |
| `join.sh` | — | **new** (resume after renderer loss) | = v2 |
| `finish.sh` | CRF 14 | CRF 22 + `-tune grain` | = v2 |
| `verify.py` | — (verified by hand) | **new**, scripted gate | = v2 |
| `mix.py`, `sheet.sh`, `audio/envelopes.py`, `audio/word_times.py` | v1 | = v1 | = v1 |
| `timeline.json` | v1 (22.3 s, D major ~100 BPM) | rewritten (22.5 s, D minor 120 BPM) | = v2 |
| `sound/` | `soundtrack.py` (58 KB) + `tone.py` | `soundtrack2.py` (82 KB, 2251 lines) + `tone2.py` | = v2; `music_sfx_eq.wav` and `out/mix.wav` byte-identical to v2 |
| `audio/spectrum.py` → `composition/data/spec.json` | — | — | **new** |
| `composition/orb.js` (WebGL2) | — | — | **new** |
| `gltest/` (orb{,2,3}.html, index.html, render-{gl,orb,orb2,orb3}.mjs) | — | — | **new** (prototype harnesses) |
| `composition/scene.js` | 608 lines | 712 | 690 (rewritten look; same camera/popup/timing) |
| `research/` (ElevenLabs/ChatGPT orb sources, tweets) | — | — | **new**, design refs only |

So the **reusable toolchain was finished at v2**; v3 changed only the picture (scene.js, orb.js, spectrum.py).

## 2. Per script

### `render.mjs` — frame renderer (Node ≥ 22 for global `WebSocket`)
- **CLI** (`render.mjs:1-3`, flags parsed `:18-23`):
  - `node render.mjs stills [--dpr 1] t1 t2 …` → `stills/t-<t.toFixed(2)>.png` (1920×1080; DPR>1 is Lanczos-downscaled)
  - `node render.mjs video [--dpr 2] [--sub 1] [--from s] [--to s] [--out out/frames.mkv]`
  - env `CHROME` overrides the browser binary.
- **In**: `composition/index.html`. **Out**: `out/frames.mkv` = FFV1 level 3, `-g 1` (all-intra), `gbrp` lossless RGB,
  1920×1080. Prints `frame n/N elapsed` every 30 frames to stderr, final `<out> <N> frames <s> s` to stdout.
- **How**: an in-process static HTTP server whose root is the **repo** (`REPO = HERE/../..`, `:14`; traversal guard
  `:29`; `Cache-Control: no-store`), so the composition can `fetch('/assets/…')` real product files. Spawns
  chrome-headless-shell with a throwaway profile and `--force-color-profile=srgb --run-all-compositor-stages-before-draw
  --disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows
  --font-render-hinting=none --hide-scrollbars` (`:37-41`). Raw CDP over WebSocket, no Puppeteer.
- **Invariants**:
  - **Page contract**: page sets `window.__ready === true` (polled 100 ms, 30 s cap, `:64`), exposes `__info()` →
    `{duration, fps, …}` (frame count = `round(duration*fps)`, `:82`) and async `__render(t)`. Frame n is captured at
    t = n/fps, always via `__render` → `Page.captureScreenshot` png (`:67`). No wall clock is ever used.
  - **CDP timeout 90 s per call** (`:54-58`) — added after v2's renderer died at frame 498 and the render hung forever.
  - **Supersampling**: `--dpr 2` renders 3840×2160, ffmpeg `scale=1920:1080:flags=lanczos+accurate_rnd+full_chroma_int`.
  - **Motion blur** `--sub N` (`:83-90`): N subframes at `t = (n + ((k+0.5)/N − 0.5)·0.5)/fps` (180° shutter), averaged
    by `tmix=frames=N` then `select` every Nth. Cost scales ×N.
  - **YUV once**: RGB kept lossless until `finish.sh`.
  - Pipe backpressure honoured (`drain`, `:91`).
- **Product coupling**: CHROME default path is Playwright's `chromium_headless_shell-1243/…mac-arm64` (`:15`); viewport
  1920×1080 hard-coded (`:62`, `:77`, `:86`) — vertical/square/4K need edits; MIME table (`:25`) lacks
  `.woff2 .jpg .webp .avif .mp4 .gif` (served as octet-stream); page path `composition/index.html` (`:63`).
  `gltest/render-orb.mjs` is this same file with only `HERE` (`:13`) and the URL (`:63`) changed — i.e. the harness is
  already page-agnostic apart from those two lines.

### `join.sh <N>` — resume a crashed render
- Cuts `out/frames-a.mkv` to frames 0..N−1 (`-c copy`, legal because FFV1 is all-intra), concats `out/frames-b.mkv`
  (rendered with `--from N/fps --out out/frames-b.mkv`), prints seam PSNR (A's frame N vs B's frame 0 — must match
  since frames are pure functions of t), prints frame count via `ffprobe -count_frames` (`join.sh:9-15`).
- **Caveat**: does not assert the count or seam; the "675" in its comment is v2's number. Expects the first render
  renamed to `frames-a.mkv`. Used once: `join.sh 498` (v2 plan `brag-plan-v2.md:108-113`).

### `sheet.sh <out.png> t1 t2 …` — review contact sheet
- Calls `render.mjs stills` then ImageMagick `magick montage` 3 across at 640×360 with labels (`sheet.sh:4-6`).
  Needs `magick`. Errors to `/tmp/brag-sheet.err`. Generic.

### `mix.py timeline.json <stem.wav> out/mix.wav` — final audio
- **In**: 48 kHz stereo stem (music+sfx), each `timeline.voices[].file` (24 kHz mono int16). **Out**: `out/mix.wav`
  float32 48 kHz stereo, exactly `duration·48000` samples (stem length must be within 1 sample, `mix.py:41`).
- **Invariants**: stem **exactly 0.0** inside every `silence_windows` entry (`:48-52`) and inside each clip's
  `speech_on..speech_off` (`:65`); clip upsampled 2:1 by `resample_poly` (unity gain), mono copied bit-exactly to both
  channels, **no gain, nothing on the sum** (`:58-62`, `:70`); voice region of the mix `array_equal` to the clip
  (`:77`); peak < 0 dBFS (`:73`).
- **Coupling**: entirely voice-product-specific (24 kHz assert `:57`, 2:1 ratio). For a film with no product audio the
  mix *is* the stem; for a narrated film, keep it but generalise the resample ratio.

### `finish.sh <poster-seconds>` — poster + final encode
- **Out**: `out/poster.png` (exactly frame round(T·30) of the lossless render), `../brag.jpg` (`-q:v 2`), `../brag.mp4`.
- **Invariants** (`finish.sh:12-25`): poster **overlaid on frame 0 only** (`overlay=…:enable='eq(n,0)'`), so frame count
  and A/V sync are unchanged; one RGB→YUV conversion with explicit `out_color_matrix=bt709:out_range=tv` (v1's first
  pass used swscale's BT.601 default and was discarded, v1 plan build log); tags `bt709` primaries/trc/colorspace, tv
  range; libx264 `-preset slow -crf 22 -tune grain -profile:v high -level 4.2 -g 60 -keyint_min 30 -bf 2`; AAC 256k
  48 kHz stereo; `+faststart`; `-shortest`. Ends with an ffprobe line.
- **Coupling**: `FPS=30` hard-coded (`:8`); needs `out/mix.wav` (drop `-i out/mix.wav`/`-map 2:a` for a silent film);
  CRF 22 + tune grain is tuned to v2/v3's film grain — a grain-free film should go back toward CRF 14–18; level 4.2 is
  1080p30-only (4K60 needs 5.1/5.2).

### `verify.py timeline.json` — delivery gate (reads `../brag.mp4`)
Checks (`verify.py:3-10`):
1. ffprobe line (printed, **not asserted** — the docstring's "675 frames, 22.5 s" is not enforced).
2. Frame 0 vs `out/poster.png` PSNR, frame 1 vs render frame 1 PSNR (printed, not asserted; "nothing shifted").
3. Per decoded channel, each clip found by FFT cross-correlation within ±0.1 s of its start; least-squares gain and
   residual measured **inside its silence window only** (`:151-158`; the clip's trailing padding runs into the next
   riser). **Asserted**: `|found − start| < 1 ms` and `|gain − 1| < 0.02` (`:164`).
4. Parakeet TDT 0.6B v3 (`parakeet-cli -np -m ~/Development/wcpp191/models/ggml-parakeet-tdt-0.6b-v3-f16.bin`,
   `:25-27`, `:183-190`) transcribes each voice span (16 kHz mono, one channel) — **asserted** word-for-word equal to
   `voices[].text` after lower-casing/punctuation strip (`:62-63`, `:198`).
5. `ebur128=peak=true` integrated LUFS + true peak (printed, **not asserted**).
Exit 0 + `VERIFY PASS` only if 3 and 4 hold.
- **Coupling**: 3 and 4 are voice-product-only; Parakeet model path is machine-local. Gotcha recorded in v1's plan:
  measure a single channel, not `-ac 1` (ffmpeg's dual-mono downmix reads +3 dB).
- For another repo: keep 1, 2, 5 and **turn them into assertions** (frame count = round(duration·fps), duration,
  1920×1080, yuv420p/bt709, PSNR(frame0, poster) > ~40 dB, PSNR(frame1, render1) > ~40 dB, LUFS in band, TP ≤ −1 dBTP).

### `audio/envelopes.py timeline.json composition/data/env.json`
- Per voice clip: 25 ms RMS window → dB mapped `(db+48)/36` clamped 0..1, sampled at 60 Hz, one-pole smoothing
  attack 20 ms / release 140 ms (`envelopes.py:16-29`). Out: `{id: {start, rate: 60, env: [...]}}`. Assumes int16.
  Reads `v["file"]` relative to cwd (run from `work/`).

### `audio/spectrum.py timeline.json composition/data/spec.json` (v3)
- Per clip at 60 Hz, 40 ms Hann FFT: 4 band levels (80–300, 300–1k, 1k–3k, 3k–8k Hz) each normalised 0..1 over 36 dB
  under its own max; log spectral centroid 150 Hz–6 kHz (gated by band level > 0.15); spectral flux normalised to its
  98th percentile; all smoothed 20/140 ms (`spectrum.py:16-68`). Generic audio-reactive data: point it at any WAV
  (e.g. the music stem) for a non-voice film.

### `audio/word_times.py <helper-Resources-dir> '<clips json>'`
- Kokoro-only: imports the helper's `tts_worker`, reruns the duration predictor, asserts direct sample count == helper
  clip's, writes `word-times.json`. Opens `<id>.wav` next to itself, so ids must be file stems. **Drop for other repos.**

### `sound/soundtrack2.py ../timeline.json` (+ `tone2.py ../timeline.json music_sfx.wav music_sfx_eq.wav`)
- Header `soundtrack2.py:2-18`: numpy/scipy-only synthesis of one music+SFX stem; **every time comes from
  timeline.json on each run** so the score follows picture edits. Writes next to itself `music_sfx.wav`,
  `stems/{music,sfx}.wav`, `preview_mix.wav` (with voices placed), `report.json`; 48 kHz stereo float32, exactly
  `duration` s. Exit 1 on any violation.
- Constants `:43-60`: limiter ceiling −2.0 dBTP (limit −1.5), momentary max −14 LUFS, tails ≤ −60 dBFS (target −66)
  50 ms before each silence window then 30 ms raised-cosine to zero, ≥2 ms attack / ≥15 ms release on every event,
  swing 0.55, short-term targets tease −21 / drop −17 / build −19.5 LUFS, SFX 8–14 dB under music; the **silence gate
  runs last**, after the limiter.
- Timeline schema it consumes: `duration, bpm, silence_windows, voices, music_sections[] (role inferred from keys:
  final_hit|fade_to_zero_by → finale; riser_from|accents|build_from → drop; else tease — `:1232-1237`), sfx[] {t,
  until?, type}`; SFX types implemented: whoosh, selection_sweep, menu_open, click, riser, swish, slider_glide, chime
  (`:676-773`; unknown types render as a click with a warning).
- **Coupling**: key/chords hard-coded D minor (Dm–B♭–F–C, `FINALE_CHORDS :153`; `tl["key"]` is not read); BPM is read;
  reference band-balance glob in /tmp (`:61`). `tone2.py` EQ values are measured corrections for *this* stem — re-measure
  per film. `sound/BRIEF.md` is the teammate brief (hard constraints section reusable verbatim).

### `timeline.json` — single source of timing
Read by scene.js (`scene.js:51`), soundtrack2.py, mix.py, verify.py. Fields: `fps 30, width 1920, height 1080,
duration 22.5, key, bpm 120, voices[] {id,file,voice,label,speed,text,start,length,speech_on,speech_off},
silence_windows [[3.15,5.44],[14.55,18.07]], music_sections[], sfx[], events{name: seconds}`. Design rule
(`:2`): a beat = 0.5 s = 15 frames; picture events sit on the grid.

### `composition/` — the film as a web page
- `index.html` (32 lines): fixed 1920×1080 `#stage` with layered DOM, one WebGL canvas (`#orb-gl`), a 960×540 grain
  canvas, `scene.js` as an ES module.
- **scene.js structure** (skim): top-level `await` loads `../timeline.json`, `data/env.json`, `data/spec.json`
  (`:51`), the real product files over the repo-root server (`assets/media/src/article.html :120`,
  `chrome-extension/src/popup/{popup.html,popup.css}` + `shared/variables.css` into shadow roots `:161`), then
  `await document.fonts.ready` + explicit `f.load()` on every face (`:351-352`) and measures geometry once.
  Helpers: `prog/seg/EASE/bezier/spring/logerp` (`:15-46`) — every value is a closed-form function of t; audio
  features are interpolated from the 60 Hz tables (`envAt`, `specAt`, `:54-84`), and "phase" uses the envelope's
  **precomputed running integral** (`ENV_CUM`, `:61-71`) so it is continuous in t without per-frame accumulation.
  `renderAt(t)` calls scene renderers in dependency order (atmosphere → window/camera/anchors → orb → pillars → outro,
  `:678-684`); `window.__render = async t => { renderAt(t); await raf(); await raf(); }` (`:686`); `__info()` also
  reports font availability, WebGL2 and measured weights (`:687`); `renderAt(0); window.__ready = true`.
- **Determinism devices**: CSS kills all transitions/animations (`style.css:167`) plus the slider thumb pseudo-elements
  (`:168`, the `popup.css:293` transition the `*` rule missed — found by the two-order check); grain = xorshift seeded
  by `round(t·240)` (`scene.js:341`).
- **orb.js (WebGL2)** (`orb.js:1-4`, `:110-143`): one viewport-size canvas at backing scale DPR;
  `preserveDrawingBuffer:true, antialias:false, premultipliedAlpha:true`; each `draw(s)` clears the whole canvas, then
  `gl.scissor` to the orb's bbox (centre ± 2.2 r) and draws one full-screen triangle; `gl.finish()` so the screenshot
  sees it; all inputs are uniforms (t, phase, audio bands, flux…), no state kept between frames; alpha dithered ±0.5/255
  against banding (v3 plan `brag-plan.md:140`).
- **Coupling**: the whole of scene.js is product choreography (article, popup, menus, voice list); only the skeleton
  (load → fonts → measure → `renderAt(t)` → `__render/__info/__ready`) and the style.css kill rule transfer.

### `gltest/render-orb.mjs`
- `render.mjs` with two lines changed (`HERE` one level up; URL `gltest/orb.html?r=260&scale=2`). Used for isolated
  shader prototyping: `node gltest/render-orb.mjs stills --dpr 2 <t…>`. Established WebGL2 works in
  chrome-headless-shell 1243 via ANGLE (SwiftShader; later GPU-backed on this machine) — `brag-plan.md:36-38,145`.

## 3. Purity check (no script — ad hoc, worth scripting)
Render a set of t in forward and reverse order and diff PNGs. v1: 17 frames, 12 identical, 5 within 4/255 (RMS <
0.08 %, compositor AA) after fixing 3 real sequential-state glitches (v1 plan build log "Purity"). v3: 12 frames
byte-identical across all scenes after the slider-thumb fix (`brag-plan.md:148-149`). Leftover stills in
`/tmp/brag-purity-a/`.

## 4. Minimal reusable kit (for e.g. a CLI/infra repo with no audio product)

Copy from v3 `work/`:
1. `render.mjs` — change: page path (`:63`) if not `composition/index.html`; `REPO` root (`:14`) to wherever the real
   assets live; add `.woff2/.jpg/.webp` to MIME table; parametrise 1920×1080 (`:62,:77,:86`) if not landscape 1080p;
   `CHROME` default path if the Playwright build differs. Keep the 90 s CDP timeout.
2. `join.sh`, `sheet.sh` — as-is (fix the 675 comment; optionally assert count).
3. `finish.sh` — change: `FPS`; audio input = the stem directly (or a silent film: drop audio mapping); CRF 14–18 unless
   the look has grain (then 22 + `-tune grain`); x264 level for resolution/fps.
4. `timeline.json` — keep schema (`duration, fps, bpm, events, music_sections, sfx, silence_windows=[]`, `voices=[]`).
5. `composition/index.html` + a new `scene.js` keeping the skeleton and the page contract (`__ready`, `__info()
   {duration,fps}`, async `__render(t)` with 2 rAFs), and `style.css`'s transition/animation kill rule. Fetch real repo
   artefacts (README, logs, terminal output, config) through the repo-root server instead of re-typing them.
6. `sound/soundtrack2.py` (+ `tone2.py`, `BRIEF.md` constraints) — change: chords/key (hard-coded D minor), SFX types
   for the new film's events, reference glob (or drop band-balance), section roles via timeline keys.
7. `verify.py` — delete checks 3–4 (voice/Parakeet); assert 1, 2, 5 (see §2).
8. Optional: `audio/spectrum.py` / `envelopes.py` on the music stem for audio-reactive visuals; `orb.js` as the
   deterministic-WebGL pattern (scissor + clear + finish + uniforms-only).
Drop: `mix.py` (unless there is narration/product audio), `audio/word_times.py`, `gltest/*` except as a prototype
harness pattern, `research/`.

Run order: timeline.json → `soundtrack2.py ../timeline.json` ∥ composition → `sheet.sh` review (every scene + mid-
transition) → two-order purity check → `render.mjs video --dpr 2 [--sub 4]` (background; watch the node pid or the log's
final "frames" line, not `pgrep -f`) → [`mix.py`] → `finish.sh <poster s>` → `verify.py`.

## 5. Measured numbers

| Metric | Value | Source |
|---|---|---|
| Render v3, `--dpr 2 --sub 4` | 675 frames in 1148.8 s ≈ **1.70 s/frame** (0.43 s/subframe), no stall | `v3/work/out/render.log` last line; `brag-plan.md:150-151` |
| Render v2, `--dpr 2 --sub 4` | ~2.4 s/frame (frames 0–480 in 1170 s); renderer lost after frame 498, hung; part B 177 frames in 495.6 s | `v2/work/out/render.log`, `render-b.log`; `brag-plan-v2.md:108-113` |
| Render v1, `--dpr 2`, no sub | ~3 min for 669 frames (≈0.27 s/frame, as quoted) | `brag-plan-v2.md:78` ("≈4× v1's 3 min") |
| Orb stills (GPU-backed) | 15 stills in ~8 s; SwiftShader budget had been ~1 s/frame, ~3 s/subframe full-frame | `brag-plan.md:73,118,145` |
| Lossless FFV1 intermediate | v1 253 MB, v2 601 MB, v3 299 MB | `ls -la */work/out/frames.mkv` |
| Final MP4 | v1 10.06 MB (CRF 14, 669 fr, 22.3 s); v2 12.7 MB (CRF 22 tune grain); v3 7.3 MB (CRF 22 tune grain) | `ls -la */brag.mp4`; `finish.sh:16-17` |
| CRF sweep (v2 grain) | CRF 14 → 74 MB; 20/23/26 → 21/8/4 MB, SSIM flat 0.977; CRF 23 crisp, no banding | `finish.sh:16-17`, `brag-plan-v2.md:118-120` |
| Duration / frames | v2 & v3: 22.500 s, 675 frames, 30 fps, 1920×1080 yuv420p bt709, AAC 48 kHz stereo | `v2/work/out/verify.txt`; `brag-plan.md:152` |
| Frame-0 poster PSNR | v2 43.0 dB (frame 1 vs render 44.6 dB); v1 39 / 44 dB | `verify.txt`; v1 plan build log |
| Clip placement | 3.1500 / 14.5500 s exact; gain 0.9994 / 0.9993; residual −48.8 / −47.5 dB | `verify.txt`; `brag-plan.md:153` |
| Parakeet | EXACT on both lines (v2, v3) | same |
| Loudness | final −18.0 LUFS integrated, TP −2.3 dBFS (v2, v3); v1 −19.6 LUFS, peak −3.0 | `verify.txt`; v1 plan |
| Stem | −17.9 LUFS, TP −2.4 dBTP after tone2; band gap to refs 2.50 → 0.94 dB RMS; 0.0 in both silence windows | `brag-plan-v2.md:100-107`; `sound/report.json` |
| Voice clips | 24 kHz mono 16-bit, −21 LUFS (helper-normalised) | v1 `brag-plan.md` "Voice clips" |

## 6. Failure lessons baked into the kit
- Chrome renderer can vanish mid-render (v2, frame 498, ~2,000 4K screenshots) → CDP 90 s timeout + `--from` + `join.sh`.
- `pgrep -f 'render.mjs video'` matches the watcher's own command line → watch the pid or the log (`brag-plan.md:156`).
- swscale defaults to BT.601 → explicit `out_color_matrix=bt709` (v1).
- Grain × low CRF explodes size (74 MB) → CRF 22 + `-tune grain`.
- CSS transitions leak state between frames, including vendor pseudo-elements the `*` rule misses → kill rule + two-order check.
- Measure loudness/gain per channel, not `-ac 1` (+3 dB dual-mono artefact).
- Screen capture stalls with the display off (project MEMORY: keep `caffeinate -d` running during renders).
