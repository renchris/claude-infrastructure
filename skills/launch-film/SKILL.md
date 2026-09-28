---
name: launch-film
description: "Make, re-work or audit a repo's launch film (a 15-60 s product film with sound, or a README hero loop) to the operator's accepted bar: startup-modern, studio-grade restraint, no purple-gradient 'AI slop', every string and sound real, rendered frame-by-frame from a web page and gated by a verify script. Use when asked for a launch video, brag film or hero film, when re-styling one that reads as 'classroom', 'template' or 'AI slop', or when carrying the Natural TTS film's quality to another repo (e.g. claude-infrastructure). Owns the taste, truth rules and gates; hyperframes, demo-recording and visual-direction own their own mechanics."
---

# Launch film

Worked example: the Natural TTS launch film, v3, accepted with *"Great. Add to our README.md"* and then
*"position launch film as the first hero/header asset"* (2026-09-27). Film: `natural-text-to-voice-extension`
README, first media under the badges (commit `0d3c429`). Everything reusable from it is in `kit/` beside this
file, because the originals live in git-excluded `brag-output-*/work/` folders and brag-slim's own text was only
ever in `/tmp`.

Evidence files beside this skill (read them before changing a rule here):
`operator-feedback.md` (every operator word on the film, verbatim, dated) and `pipeline.md` (each script: CLI,
invariants, coupling, measured numbers).

## 1. The bar, in the operator's words

Two lineages, one taste. Each verdict names what it rejected; the rule is the rejection, not the agent's reading of it.

| When | Verdict on | Operator's words | What it rejected |
|---|---|---|---|
| 2026-09-24 | agent-context-sync animated-SVG hero | "This needs to be more of a hero launch video rather than a secondary supplementary infographic" | a correct, captioned diagram as the hero |
| 2026-09-24 | its canvas film | "the scene is very abstract … there is no 3d transpilation transitions from scene to scene" | metaphor fields; hard cuts |
| 2026-09-25 | claude-infrastructure 20 fps loop | "make the film more smooth (ie. 60fps) … I don't feel oriented nor I can read anything in time" | low frame rate; fast flights; short holds |
| 2026-09-26 | Natural TTS v1 (light indigo, Iowan serif, soft) | "This is good. It's very "2000s classroom friendly" vibes. Can we make it more startup modern? … the same energy as … an Apple launch product" | the look and pace, **not** the story (kept through v3) |
| 2026-09-26 | (mid-build) | "compete with the design and brand guidelines of ElevenLabs / SuperWhisper/WhisprFlow / Awwwards / Anthropic" · "showcase the ability of you the world class motion designer Opus 5.5" | generic "good design" |
| 2026-09-26 | Natural TTS v2 (black stage, iridescent orb, glows, gradient text, mono index labels, shockwave) | "from "mvp ai template slop" to "world-class design studio" … well-design the orb … like ElevenLabs and ChatGPT Voice … EVEN BETTER … less "purple gradient" prominent vibes whicih is the "AI slop" theme default" | showing off through template tropes |
| 2026-09-27 | Natural TTS v3 (warm paper stage, one cobalt-ink orb, near-black type) | "Great. Add to our README.md" | — accepted |

Read together:
1. **Content survives, looks get re-rolled.** Keep a working story and truth rules; change look, pace and sound.
2. **Startup-modern means flagship-launch energy with studio restraint.** Craft shows in the object, the motion and
   the type — never in auras, glows or gradients. v2 showed off *and* was rejected; v3 held back *and* was accepted.
3. **Benchmark against named brands and beat them** (ElevenLabs, ChatGPT Voice, Anthropic, Awwwards, Apple
   keynotes). Study the operator's references as data (measured colours, frame grabs), never from memory.
4. **Concrete, continuous, legible:** real things with real names, one world with eased camera flights, 60 fps on
   anything that moves, every line held ≥ 1.0 s + 0.3 s/word.
5. **Frame 0 is the answer; an accepted film becomes the page's first hero asset.**

Honest limit: the operator never ruled on single elements of v3 (the paper stage, the ink orb, the music). The
design system in §2 is the agent's, accepted as a whole. Treat it as the proven default, not as law.

## 2. The look that passed (Natural TTS v3)

**The AI-slop tells — remove every one before the operator sees a frame:** purple/indigo/violet/pink auras or
gradients as the dominant field; iridescent or gradient-filled text; glow blooms; vignettes; light streaks;
shockwave rings; glossy specular "ornament" spheres; mono uppercase labels with `01 / 03` index numbers; heavy grain
used as a look (≤ 0.02, and only to dither).

**The system that replaced them:**
- **Colour comes from the product, not a template.** Pull the palette from the repo (brand README, CSS variables,
  icon). One accent. Keep product truth: the real icon and the real UI keep their real colours even when they are a
  gradient (v3 kept the indigo icon tile).
- **Colour lives in one object.** ~90 % of every frame is warm neutrals and near-black type; one saturated object
  takes the rest (ElevenLabs measured: page `#FDFCFC`, panels `#F5F3F1`, one colour field per section).
- **Warm light stage, never template-black:** stage `#EFEDE8`, page `#FBFAF7`, so white UI reads as objects.
  Focus without darkness: fade the rest toward paper (~15 %) instead of dimming to black.
- **Type:** near-black `#141414` SF Pro Display 400–500, tracking ≈ −0.035 em, large; one serif italic supporting
  line; captions SF Pro Text 20–22 px, muted `#8A857D`, sentence case.
- **One signature object, made of the product's own story** (v3: "the ink of the text becomes a living voice" —
  cobalt ink blooming in a milk-white sphere on paper). It must differ from every reference, not average them.
  Prototype it alone (`kit/example/orb.js`; a `gltest/`-style page rendered by a copy of `render.mjs`), keep a
  reject log with the reason for each rejection, and drive it with real data (the product's audio spectrum via
  `kit/audio/spectrum.py`) — data changes speed and bloom, never the pattern's scale.
- **Motion:** eased camera choreography, 4-subframe motion blur, transitions made of the object itself (ink wash)
  rather than colour takeovers or hard cuts.

## 3. Truth rules (every film)

1. Every legible string and every product sound is real: copy from the README, store listing and UI; product audio
   used exactly as the product returned it — no gain, no cuts inside a clip.
2. For a product that speaks or plays sound: music and effects are **digital silence** under it.
3. No invented UI or features; measured latencies are shown as measured.
4. Graphics that are not the product (an orb, a chip) sit off the product's UI and are driven by real data.
5. Captions and share copy state only verified facts (version, machine, voices, speeds).

## 4. Procedure

1. **Intake** (brag-slim's questions, `kit/brag-slim/SKILL.md`): what it is, who it's for, what sets it apart, the
   most impressive true claim, the visual hook, the real UI to show, share caption. Write the angle in one sentence.
   Output folder `brag-output[-<timestamp>]/` with `work/` beside the plan; git-exclude it
   (`.git/info/exclude`: `/brag-output*/`), never commit renders.
2. **References.** One read-only research subagent per reference (the operator's links, plus the named brands);
   each writes `research/<slot>/notes.md` + `contact.png` with measured values. Read the sheets, not the pages.
3. **Look-frame to the operator early** — one still of the hero moment, before the full build. Critics passed films
   the operator rejected on sight twice (abstract; unreadable pace).
4. **`timeline.json` is the single source of timing** (`kit/timeline.json`): fps, size, duration, bpm, product clips
   with `speech_on/off`, `silence_windows`, music sections, sfx. Picture events sit on the beat grid.
5. **Composition = a web page that is a pure function of t** (contract, from `kit/example/scene.js`): top-level
   await loads the timeline, data and REAL product files through the render server (its root is the repo); fonts
   loaded explicitly; `renderAt(t)` computes everything closed-form (use running integrals, never accumulate);
   `window.__render = async t => { renderAt(t); await raf(); await raf(); }`, `__info()`, `__ready`. Kill every CSS
   transition/animation, in every shadow root that hosts real product CSS (`kit/example/scene.js`, grep
   `transition: none !important`), including vendor pseudo-elements the `*` rule misses (a slider thumb leaked).
6. **Stills review before any full render:** `./sheet.sh out.png t1 t2 …` over every scene AND mid-transition
   frames. Check against §1 and the §2 tell list, frame by frame.
7. **Purity check:** render the same t set in forward and reverse order, diff the PNGs; byte-identical (or ≤ 4/255
   compositor AA) or find the leaking state.
8. **Render in the background:** `caffeinate -d` running (display-off stalls capture), then
   `node render.mjs video --dpr 2 --sub 4`. Watch the render's own pid or the log's final `frames` line, never
   `pgrep -f 'render.mjs video'` (it matches the watcher). On a lost renderer: `--from <s> --out out/frames-b.mkv`,
   then `./join.sh <n>`.
9. **Score:** synthesize it (`kit/sound/soundtrack2.py ../timeline.json`, numpy/scipy; brief constraints in
   `kit/sound/BRIEF.md`). Bundled stock tracks without a documented licence are out. Band-check against a reference and
   EQ (`tone2.py`) with values re-measured per film. A teammate may own the score; it gets reaped after reporting, so
   read its files rather than waiting for its message.
10. **Mix** (only with product audio): `python3 mix.py timeline.json sound/music_sfx_eq.wav out/mix.wav`.
11. **Finish:** `./finish.sh <poster seconds>` — poster replaces frame 0 only; one BT.709 conversion; CRF 22 +
    `-tune grain` for grained looks (CRF 14 on grain cost 74 MB), 14–18 for grain-free.
12. **Verify:** `python3 verify.py timeline.json` must print `VERIFY PASS`. For a film with no product audio, cut the
    clip and Parakeet checks and **assert** what it only prints today: frame count = round(duration·fps), size,
    yuv420p/bt709, PSNR(frame 0, poster) and PSNR(frame 1, render 1) > ~40 dB, LUFS in band, true peak ≤ −1 dBTP.
13. **Deliver so the operator can watch it:** `open brag.mp4` and SendUserFile the mp4 + jpg + share copy. The
    operator judges by watching the MP4, not by reading the plan.
14. **README, once accepted:** first hero asset, directly under the title and badges. GitHub strips `<video>`: upload
    the MP4 (≤ 10 MB) to a closed issue titled `README media: <name>` with `gh issue create --attach`, put the bare
    `github.com/user-attachments/assets/<uuid>` URL on its own line under a `<!-- <name> -->` marker, caption with
    verified facts only, and check `gh api markdown -f mode=gfm -f context=<owner/repo> -F text=@README.md` renders a
    `<video>` for that uuid. (Recipe: natural-text-to-voice-extension `scripts/release/embed-hero-video.sh`.) For a
    silent looping hero, use demo-recording's animated-WebP rules instead.

## 5. The kit (`kit/`)

| File | Use | Change for a new film |
|---|---|---|
| `render.mjs` | CDP frame renderer, 90 s call timeout, `--dpr`, `--sub` motion blur, `--from/--to` | lives at `<repo>/brag-output*/work/` (it serves `../..` as root); page path; 1920×1080 is hard-coded; add `.woff2/.webp/.jpg` MIME types; `CHROME` path |
| `join.sh`, `sheet.sh` | resume a crashed render; review sheets | none (join does not assert the count) |
| `finish.sh` | poster as frame 0, BT.709 encode | `FPS`; drop the audio input for a silent film; CRF by grain; x264 level for 4K/60 |
| `verify.py` | delivery gate | see step 12 |
| `mix.py`, `audio/envelopes.py`, `audio/spectrum.py` | product-audio mix; audio-reactive data | mix is voice-specific (24 kHz, 2:1); spectrum works on any WAV, e.g. the score |
| `sound/soundtrack2.py`, `tone2.py`, `BRIEF.md` | synthesized score, EQ, brief | key/chords hard-coded (D minor); SFX types; reference glob points at `/tmp` |
| `example/` | v3's `scene.js` (page contract, closed-form helpers, the transition kill rule), `orb.js` (deterministic WebGL: clear, scissor to bbox, uniforms only, `gl.finish()`), `style.css`, `index.html`, the v3 plan | pattern only; the choreography is product-specific |
| `brag-slim/` | latent-spaces/brag 0.4.0 `/brag-slim` (MIT, licence beside it) | the procedure this pipeline follows |

Measured on an M1 Max: v3 rendered 675 frames at `--dpr 2 --sub 4` in 19 min (≈1.7 s/frame); final 7.3 MB.

## 6. Carrying it to another repo (e.g. claude-infrastructure)

- **Reconcile before building.** claude-infrastructure already has `tools/hero-film/` (a 3D three.js world,
  48 s 4K60 film + 36 s WebP loop, pacing gate `npm run hero:pacing`) and an unlanded `hero-brag` branch with a third
  toolchain (`scripts/hero-brag-*`). Extend one of them; do not fork another.
- **Audit the existing film against §1-§2 frame by frame**, from a contact sheet of the real MP4
  (`ffmpeg -i film.mp4 -vf "fps=2/3,scale=640:-1" f%02d.png`, then montage). Mark every §2 tell (dark template
  stage, glowing lines, bloom, gradient fields) and every place colour is not the product's.
- **Where the lineages seem to disagree, the operator decides from a look-frame.** Both are compatible: 3D camera
  flights, 60 fps, concreteness and reading time (infra) sit inside restraint, product-sourced colour and one
  signature object (Natural TTS). What the operator has not ruled on is a dark stage with a glow-lit world outside a
  voice product. Show one re-graded still next to the current one and let them pick.
- **Find the repo's signature object in its own story** (the Natural TTS orb was the text's ink becoming voice).
  For an infra repo that is a real thing on screen (a terminal pane, a commit landing, a file turning live), never
  an abstract orb pasted in.
- **Real strings only:** terminal output and file names from real runs, as that repo's hero-film honesty rule says.
- **Carry the METHOD, never the look.** On 2026-09-27 the operator rejected a claude-infrastructure build that had
  Natural TTS's paper stage, one accent and Iowan italic: *"we overfit to the exact output style and not the
  methodology of design and composition … We should have different inspiration from our claude harness infrastructure
  that helps self manages 15+ concurrent sessions"*. The method is: research the product's OWN domain, then design one
  signature object from its story that beats those references. For an agent-fleet repo that research wave was ten
  read-only slots, each writing `notes.md` + `contact.png`: Claude brand films, parallel-agent products, infra launches,
  real-world fleet control (ATC, rail tokens, Apollo), Apple's software craft, studio motion, terminal staging,
  autonomy and the human decision, plus a hostile critic of the look-frame and a red team of the object. They
  converged on what no agent product shows: time, work crossing one lock one at a time, and a film that ends on the
  one decision left. The object that came out of it was **the day sheet**: one real day of the repo drawn as a train
  timetable from `land.log`, with each land a thread through the lock. Every mark on it was a real record.
- **Prototype the object alone through the film's own renderer** (`render.mjs --page proto/index.html --stills-dir
  proto/stills`), keep a reject log with the reason per rejection, and only then build the film on it. Its purity
  check caught three leaks the eye did not: a composited label layer (`will-change: transform`) whose text phase kept
  the history of earlier frames, a canvas context carrying drawing state between redraws, and a font the page never
  awaited before its first draw.

## Do NOT

- Do not answer "startup modern" with a black stage, purple/violet gradients, glows and gradient text: that exact
  answer was v2, and it drew "mvp ai template slop".
- Do not change the story when the note is about the look ("This is good" kept v1's storyboard alive to v3).
- Do not imitate a reference's object (ElevenLabs' tangerine velvet, ChatGPT's white clouds in blue); beat it with
  one that comes from your product.
- Do not use stock or bundled music without a documented licence; do not put anything under product speech.
- Do not recolour real product UI or the real icon to fit the palette.
- Do not full-render before a stills sheet and the purity check; do not render without `caffeinate -d`.
- Do not treat your own "APPROVED" as the operator's: every v1-v3 still review was the agent's; only watching the
  MP4 produced a verdict.
- Do not cite `file:line` into the kit or the source repos in new notes; cite a grep (line numbers rot).
