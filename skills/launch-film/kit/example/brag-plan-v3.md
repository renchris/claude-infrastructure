# /brag plan — Natural TTS launch film, v3 ("studio")

Re-design of v2 (`brag-output-2026-09-26-123925/`, delivered, kept; its plan is copied here as `brag-plan-v2.md`).
Same product, same truth rules, same two voice lines and timeline; new orb, palette, type and layout.

Scope (frozen, v3): take the launch film from "MVP AI template slop" to world-class design-studio quality, as a new
run in this folder: a new voice orb better than ElevenLabs' and ChatGPT Voice's, no purple-gradient look, studio-grade
type/layout/motion; re-render, re-mix, re-verify to v2's bar (ffprobe 22.5 s / 675 frames / 1920×1080, clips placed
exactly with gain ≈ 1 and nothing under speech, Parakeet transcripts exact), deliver brag.mp4 + brag.jpg + share copy.

## Phase 0 — orchestration

| Wave | Locus | Why |
|---|---|---|
| R: reference research (3 X posts; ElevenLabs site + Orb source; ChatGPT Voice + AI SDK Persona) | research subagents | read-only, parallel; each writes `research/<slot>/notes.md` + `contact.png` so the lead reads one sheet per slot |
| D: design direction + orb shader + restyle of `work/composition/` | **L** — lead | one visual judgment made against stills frame by frame, on files the lead already knows (v2's scene.js) |
| B: render, mix, finish, verify, deliver | **L** | scripted (`render.mjs`, `mix.py`, `finish.sh`, `verify.py`); the lead only watches |

Lead context: ~37% of 1M at the start of v3 (session transplanted from `next` to `next2` at the weekly limit, 20:40Z).
Succession point: after wave D's stills are approved and written into this file, before the full render, if the fill
passes ~60%.

## Operator direction, verbatim (2026-09-26 ~15:10 CDT)

> Can we push the design quality from "mvp ai template slop" to "world-class design studio"
> Also can we well-design the orb? We need something world-class like what ElevenLabs and ChatGPT Voice has but EVEN
> BETTER
> Also we need less "purple gradient" prominent vibes whicih is the "AI slop" theme default.

References: https://elevenlabs.io/ · https://chatgpt.com/features/voice/ ·
https://elements.ai-sdk.dev/components/persona · x.com/dan__marek/status/2013219980838412664 ·
x.com/zzzzshawn/status/2080235762751361160 · x.com/insporadesign/status/2097733377650499861

## Established so far

- **WebGL2 renders in the headless pipeline** (`work/gltest/`): chrome-headless-shell 1243 gives WebGL2 through ANGLE on
  SwiftShader (CPU; deterministic), float colour buffers available. A shader orb is feasible; it must be cheap enough
  for 4 subframes × 675 frames at 2× DPR (render the orb canvas only over its own bounding box).
- **Voice-driven data**: `work/audio/spectrum.py` → `composition/data/spec.json`: per clip at 60 Hz, four band levels
  (80–300, 300–1k, 1k–3k, 3k–8k Hz), log spectral centroid and spectral flux, smoothed like the envelope. The orb can
  answer the actual voice, not a generic pulse.
- **The product's own palette** (the colour source instead of a template gradient): neutrals `#FAFAFA` bg,
  `#202124` text, `#5F6368` secondary; the article's paper `#FBFAF7`; ONE accent, the popup's `#3D4ED7` (icon tile
  `#5B6CF3 → #3441C6`). v2's indigo/violet/pink auras, iridescent text and glow blooms are what read as "AI slop".
- **v2 defects this run must not repeat**: the render hang (Chrome renderer lost at frame 499; `render.mjs` now times out
  CDP calls, `join.sh` joins resumed parts); CRF 14 bloats grain to 74 MB (`finish.sh` uses CRF 22 + tune grain).

## Orb prototype log (`work/gltest/orb.html`, rendered by `gltest/render-orb.mjs stills --dpr 2 <t…>`)

- Concept under test: the orb is a drop of ink (the text) that fills with light when it speaks (the voice), sitting on
  a warm paper stage with a contact shadow and its light cast onto the page. Cost: ~1 s per frame for a 2288² canvas on
  SwiftShader, so affordable.
- v0: royal-blue body, 4-octave fbm, ±3.5 % silhouette wobble, white halo. Rejected: reads as a lapis marble with
  cracked-ice light and a lumpy potato outline; the halo reads as a cheap glow.
- v1: 3-octave fbm at lower frequency, ±1 % wobble, shadow and light spill on the paper below. Silent state (dark ink
  ball on paper) is elegant; speaking state reads as a marbled blue glass marble / lava lamp and drifts toward lavender.
  Next pass waits for the references (ElevenLabs Orb shader, ChatGPT orb frames, the three X posts).

- v2 (`gltest/orb2.html`, pearl/chrome after the X references): physical thin film landed on magenta (the banned
  purple); crumpled-foil normals; then a plain chrome ball bearing. Rejected: chrome is the wrong material — the two
  world-class references (ElevenLabs site orb, ChatGPT) are SOFT: velvety volumes, no hard specular, grain, one hue.
- **v3 — APPROVED (`gltest/orb3.html`, 2026-09-26 ~16:30 CDT): cobalt ink blooming in a milk-white sphere on paper.**
  Story: the ink of the text becomes a living voice. Distinct from ElevenLabs (tangerine velvet) and ChatGPT (white
  clouds in blue): blue ink in white milk. Stills: silence = a small ink seed with one tendril; the voice's attack =
  ink blooms; full speech = a deep cobalt cloud with fine filament tendrils at its edge; the tail = it settles.
  Structure (keep): milk body lit by one soft window (lambert 0.86→0.995 grey-white) · ink = 3 front-to-back slices,
  fisheye lens `q*(1.18-0.30z)`, a Gaussian cloud around a slowly drifting core, spread `0.26+0.30E+0.10low`, shaped by
  2-octave domain-warped fbm (warp `0.32+0.22mid`), tendrils = ridged noise `pow(1-|snoise(pw*1.6)|,10)` gated to the
  cloud's edge and softer with depth · colours `uDeep #0A3FB0` (core) → `uAccent2 #5E9BE8` (thin) · glass shell: a
  small rounded softbox reflection upper-left (strength 0.32), clear rim, fresnel of the paper · a soft contact shadow
  and a faint cobalt tint of transmitted light on the paper · grain 0.022. Voice drives only speed (phase = 0.5t +
  3·env; production should use the envelope's running integral as in v2's `envIntAt`), bloom radius and puffs on
  spectral flux; never the pattern's scale (the @zzzzshawn notes' rule). Cost ≈1 s/frame at 2× for a 520 px orb.
  Known defect: 8-bit banding in the shadow falloff where alpha → 0 (grain is multiplied by alpha) — dither alpha
  and colour by ±0.5/255 in integration.

## v3 design system (decided 2026-09-26 from the research; apply to every scene)

- **Stage**: warm light, never dark. Stage `#EFEDE8` (so the white Chrome window and the milk orb read as objects),
  page as the article's own `#FBFAF7`. ElevenLabs measured `#FDFCFC` page / `#F5F3F1` panels.
- **Colour lives in one object**: the orb's cobalt ink. Plus the product's own UI blue inside the real popup and the
  real icon tile — nothing else. No auras, no vignette, no glow blooms, no iridescent or gradient text, no streaks, no
  shockwave ring (all v2 "AI slop" tells). Grain ≤ 0.02 and only for dithering.
- **Type**: near-black `#141414` SF Pro Display at weight 400–500 (ElevenLabs' display is weight 300), tracking about
  −0.035 em, large; the article's Iowan Old Style italic for the one supporting line, `#5A5650`; small captions in SF
  Pro Text 20–22 px muted `#8A857D`, sentence case. Drop the mono uppercase labels and the `01 / 03` index numbers.
- **Focus without darkness**: where v2 dimmed the page to black around the spoken sentence, v3 fades the rest of the
  page toward paper (the sentence stays full ink; the rest ~15 %), like v1's reading spotlight.
- **Motion**: keep v2's camera choreography, easing and 4-subframe motion blur; transitions become an ink wash (the
  orb's cloud expands to fill the frame, then clears to paper) instead of the v2 colour takeover.

## Scene-by-scene restyle (targets in `work/composition/scene.js` / `style.css`)

1. Opening 0–2 s: page fades in from paper (not black); the sentence lit by the sweep = the rest of the page at paper
   opacity, the sentence full ink; pull-back to the Chrome window over the `#EFEDE8` stage with a soft realistic
   window shadow; push through selection and menu (unchanged). `renderWindow` hook branch, `setSpot` → a paper-fade.
2. Heart 2–5.5: rest of the page fades to paper after the click; the orb is born at 2.6 to the right of the line and
   speaks; its caption "Kokoro · Heart (US)" in muted SF Pro Text under it (was mono uppercase).
3. Takeover 5.5–6: the orb grows and its ink blooms across the frame (ink wash), clearing to the paper stage for
   the titles. Titles 6–12: "Natural." / "Private." / "Fast." near-black with the per-character masked reveal; the
   Iowan italic sub-line; one muted caption. Natural: the voice-picker drum restyled in near-black/grey on paper,
   landing on Heart, clear of the orb. Private: the one-hop diagram in ink hairlines, black nodes, "Your Mac" caption,
   the pulse a small cobalt dot; the orb small at the Apple GPU node. Fast: "20×" counting up in near-black (no
   gradient), and — replacing the streaks — two hairline bars: speech length vs the time to make it (1/20), labelled
   from the README ("about 20 times faster than it plays").
4. Popup 12–18.5: unchanged choreography (window flies in, popup opens from the icon, Emma, 1.2×, Speak); after the
   click the page fades to paper except the sentence and the popup; the orb comes out of the toolbar icon and speaks
   with Emma, caption "Kokoro · Emma (UK)".
5. Outro 18.5–22.5: the orb condenses into the real icon (it keeps its indigo tile: product truth); "Natural TTS"
   near-black; the Iowan italic line; "Free and open source" muted; the repo URL in a `#F5F3F1` pill with near-black
   text; the icon's small pulse on the 20.5 hit; no ring.

## Orb integration notes

- Replace the DOM `.orb` with ONE WebGL2 canvas the size of the viewport (backing scale = DPR), positioned in the
  orb's z-slot (above the window and the titles' drum, below the pointer). Per frame pass the orb centre and radius
  in pixels as uniforms and `gl.scissor` to the orb's bbox (radius × 2.2) so only those pixels run; clear the rest.
  During the 5.5–6 takeover the bbox is the whole frame (~3 s/subframe on SwiftShader for ~15 frames: acceptable).
- Features per frame from `data/env.json` (envelope + its running integral for phase) and `data/spec.json` (bands,
  centroid, flux) for v1/v2; silence = the seed state. Everything stays a pure function of t (check by rendering a
  handful of frames in two orders, as v2 did).
- `render.mjs` already times out CDP calls; `join.sh` resumes a crashed render; `finish.sh` encodes at CRF 22 + tune
  grain; `verify.py` checks everything v2 checked.

## Status

- Wave R: first attempt killed by the weekly limit on `next` (all three NULL); re-run on `next2` 20:42Z with the
  verbatim briefs + a seed line naming the files the dead attempt had already saved. Tweets and ElevenLabs: COMPLETE
  (`research/tweets/`, `research/elevenlabs/`: notes.md + contact.png each). ChatGPT/Persona: see its folder.
- Wave D, orb: DONE (v3 approved above). Lead context reached 52 % at the orb decision, so the restyle + render +
  verify + deliver continues in a fresh-context successor of this pane (recycle), reading this file as its DoD.
  Successor order: (1) integrate `gltest/orb3.html` as the WebGL orb in `work/composition/`; (2) restyle per the design
  system and the scene list; (3) review sheets of every scene and mid-transition frame (`./sheet.sh`), purity check in
  two orders; (4) `node render.mjs video --dpr 2 --sub 4` in the background, watched with a stall check (render.mjs
  times out CDP calls; resume with `--from` + `join.sh`); (5) `python3 mix.py timeline.json
  sound/music_sfx_eq.wav out/mix.wav` (v2's tone-matched stem, copied); (6) `./finish.sh <poster s>`; (7)
  `python3 verify.py timeline.json` must print VERIFY PASS; (8) share-copy.txt, SendUserFile mp4 + jpg.
- Successor (session dac9bf63, 2026-09-26 ~17:00 CDT), steps (1)–(3) DONE:
  - Orb = `composition/orb.js` (orb3's shader, rebased to viewport px, scissored to c ± 2.2r). Shadow and tint are
    premultiplied black/cobalt, so one orb sits on page or stage unchanged; alpha dithered ±0.5/255 (the banding
    fix). New uniforms: `uWash` (ink wash: spread +2.4 and higher contrast, `mix(0.85,0.42)+mix(0.9,1.45)·shape`, so
    milk channels survive instead of flat cobalt — the first cut read as a blue plastic ball), `uShell`, `uRest`
    (chapters: spread +0.30 — at +0.16 the resting orb read as a blank white ball), `uAlpha`, `uShadow`. Wisps
    0.55 → 0.46. Phase = 0.5t + 2.2·(running envelope integral) + 3·wash surge.
  - Rendering is GPU-backed here (15 stills in ~8 s), far faster than the 1 s/frame SwiftShader budget above.
  - Fast: the sub stays v2's "About 20× faster than it plays."; bars "Speech, as it plays" / "Time to make it",
    drawn at one speed so the second stops at 1/20 (FAST_BAR 700 → 35 px). Orb beside the 20× at (1752, 360) r 76.
  - Purity: two-order check byte-identical on 12 frames across all scenes, after one fix — `popup.css:293` gives the
    slider thumb a box-shadow transition the `*` override missed (v2 carried it too; max diff 24 at the thumb).
- Steps (4)–(8) DONE, 2026-09-26 16:42 CDT. Render: 675 frames in 1149 s (19 min, no stall; ~1.7 s/frame at
  `--dpr 2 --sub 4`). Mix: stem exactly 0 in both silence windows. `./finish.sh 7.5` (poster = "Natural." with the
  orb and the drum on Heart, v2's moment) → `brag.mp4` 7.3 MB (v2 12.7 MB), `brag.jpg`. `verify.py`: 22.5 s / 675
  frames / 1920×1080; clips at 3.1500 and 14.5500 s, gain 0.9994 / 0.9993, residual −48.8 / −47.5 dB; Parakeet EXACT
  on both lines; −18.0 LUFS, true peak −2.3 dBFS; VERIFY PASS. `share-copy.txt` = v2's (same product, same claims).
  Delivered (SendUserFile: mp4, jpg, share copy).
  - Watch lesson: a stall monitor that tests `pgrep -f 'render.mjs video'` matches its own command line and never sees
    the exit; watch the render's own pid or its log's final "frames" line instead.
