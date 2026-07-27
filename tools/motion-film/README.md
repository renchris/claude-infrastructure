<!-- markdownlint-configure-file {
  "MD013": { "tables": false, "code_blocks": false }
} -->

# motion-film

Render a broadcast-looking motion-design film from HTML, CSS and JavaScript —
no video editor, no motion-design software, no footage, no font files, no
dependencies beyond Node 22 and ffmpeg.

```bash
cd tools/motion-film
./render.sh review    # 1fps pass -> review/sheet_*.jpg  ← look at these FIRST
./render.sh film      # 60fps pass -> reso-film.mp4
```

The current film is a ~35s reso launch piece: `film/film.js` holds the whole
edit, `film/film.css` holds the look, `film/index.html` holds the elements.

---

## The idea

**It is not a video. It is a web page being photographed.**

There is no video editor anywhere in this. What exists is an ordinary HTML
page — divs, text, CSS — plus a function that says *"given the time 12.4
seconds, here is exactly what every element on screen should look like."* A
headless browser then opens that page ~2,100 times in a row, saying "show me
0.000s… now 0.016s… now 0.033s…", screenshots each time, and ffmpeg staples
the screenshots into an MP4.

That is the whole trick. Everything below is detail.

The property that makes it work is that the page is a **pure function of time**.
`render(3.7)` puts the page at 3.7 seconds; call it again and you get a
pixel-identical result. Nothing is remembered between calls. That is what makes
scrubbing, replaying and frame capture all work for free.

It also means the render has **no real-time budget to miss**. Frames are *posed*
and then photographed, not recorded. A frame that takes 400ms to paint is still
frame 900 of 2,124. The output is therefore perfectly smooth no matter how
expensive the blur and filter work gets — there are no dropped frames, because
there is no clock to drop them against.

---

## The five rules that keep it working

**1 · One clock, and nothing else.**
No `animation`, no `transition`, no `@keyframes`, no `requestAnimationFrame`.
CSS animations run on their own private schedule, and you cannot ask them "what
do you look like at exactly 12.4s?" — which is the only question the capture loop
asks, 2,124 times, perfectly. Everything that changes over time is written by
`render(t)`.

**2 · A scene is just a time range.**

```js
const SC = { open: [0.00, 3.60], door: [3.60, 8.40], chapter: [8.40, 10.60], … }
```

The master `render(t)` shows whichever scenes are live and hands each one
`t - start` — its own local clock. So a scene body says "the count starts
ticking 1.3s in", never "at 16.1s of film time". Dragging a scene from 22s to
26s is editing one number, and nothing inside it breaks.

**3 · Two helpers do 90% of the work.**

```js
const p = (t, a, b) => clamp01((t - a) / (b - a))            // how far along am I
const e = (t, a, b, fn = ease.outExpo) => fn(p(t, a, b))     // …with weight
```

`e()` always returns 0→1. Map that onto anything visual — opacity, `translateY`,
`blur` — and you have a reveal. Stagger it by multiplying a start time by an
index:

```js
words.forEach((w, i) => reveal(w, e(u, 0.05 + i * 0.085, 0.05 + i * 0.085 + 0.85)))
```

A stagger is just a start time multiplied by an index. The same four lines
produce the headline reveal, the rows arriving, the tables filling and the pills
popping in.

**4 · The "camera" is a `<div>`.**
There is no camera. A push-in is a wrapper div being scaled with its
`transform-origin` parked on the thing you are pushing into. A 3D tilt is
`perspective` on the parent and `rotateX()` on the child. A mouse cursor is an
inline SVG arrow that `translate()`s from A to B on an ease, and the "click" is
the target scaling to 0.86 for 100ms. Your brain does the rest.

**5 · Review grids of stills, not video.**
See below. This is the rule people skip, and it is the one that matters most.

---

## Why it reads as expensive

Nothing here is technically advanced. The polish comes from five cheap habits:

1. **Weighted easing everywhere.** `outExpo`, never linear. Constant speed looks
   like a PowerPoint slide; real things accelerate and settle. Feed `0.25` into
   `outExpo` and get `0.82` out — the element does most of its travel
   immediately, then eases into place. This single substitution is most of the
   difference between "student project" and "agency made it".
2. **Hard cuts, not crossfades.** Crossfades read as amateur.
3. **Motion-blur substitute.** Animate `filter: blur()` from ~9px to 0 alongside
   the movement. Cheap, and it is why type reveals feel filmic.
4. **One accent colour, used sparingly.** Here: reso gold `#D4AF37` on charcoal,
   with red reserved for the problem and green for the resolution.
5. **A background that never stops moving.** Four blurred circles drifting on
   slow sine waves under every scene. It is why nine hard cuts feel like one
   continuous film rather than a slide deck.

---

## Review at 1fps, not 60

`./render.sh review` renders the film at **one frame per second** (35 frames,
~6 seconds of work) and tiles it into contact sheets.

Do not watch the film to review it. Motion is persuasive and it hides defects;
stills expose them. Every defect found while building this one was visible
instantly as a still image and invisible in playback:

| Defect | What the still showed |
| --- | --- |
| Blank frame at every scene boundary | Opacity fading in from zero over the same duration as the slide. Fixed by ramping opacity ~6x faster, so it reads as a hard cut. |
| `THEDOOR` | `splitWords()` emits the gaps between words as their own spans, and an inline-block span collapses whitespace. Needed `white-space: pre`. |
| Muddy brown background | Gold blobs too large and too opaque over near-black. Smaller, softer, plus a vignette. |
| Empty box for half a second | The floor-plan tables were staggered along with the room. The room should exist from frame one; only the *fill* should stagger. |

Only once the sheets are clean is it worth paying 60x the render cost.

---

## Files

| File | Role |
| --- | --- |
| `film/index.html` | Every element the film will ever need, present from load |
| `film/film.css` | Static appearance only — **no animation, no transition, ever** |
| `film/film.js` | The scene table, the easing helpers, and `render(t)` |
| `capture.mjs` | Headless Chrome over CDP: seek, screenshot, repeat |
| `contact-sheet.mjs` | Tiles a 1fps pass into review grids |
| `render.sh` | The pipeline in the order you should run it |
| `motion-probe.py` | Reads motion back OUT of a rendered film (see below) |

## motion-probe.py — measuring the motion, not eyeballing it

Contact sheets show you *what* is on screen; they cannot show you *how* it
moved, because motion lives between frames. These four probes move the temporal
axis into something inspectable:

```bash
python3 motion-probe.py slice reso-film.mp4 --out st.png          # slit-scan
python3 motion-probe.py flow  reso-film.mp4 --from 0 --to 12 --step 6
python3 motion-probe.py trail reso-film.mp4 --from 10.6 --to 12 --out trail.png
python3 motion-probe.py curve reso-film.mp4 --from 32.2 --to 33.45 \
        --roi 0.28,0.30,0.72,0.72
```

- **`slice`** stacks one pixel-column per frame. The film's whole timing becomes
  geometry: vertical breaks are hard cuts, diagonal streaks are movement, and
  the **curvature of a streak is the easing**. The staggered check-in rows show
  up as a literal staircase.
- **`flow`** prints per-frame optical-flow magnitude. It located this film's
  `headline` cut at t=10.600s — the exact value in `SC` — from pixels alone, and
  flagged that 83 of 119 sampled frames in the first 12s are static (a fair
  pacing critique).
- **`curve`** tracks an element at full frame rate and fits easing functions.
  Validated against known ground truth: the closing mark returns `outExpo`
  (written as `outExpo`), the clipboard returns `outBack` (written as
  `outBack`).

**Calibration, so this is not over-trusted:** `curve` *decisively* separates
weighted easing from linear (~8x RMSE gap). It separates curves *within* the
weighted family only weakly — outBack beat outExpo on the clipboard by 0.0589 vs
0.0594, which is a coin flip. Trust "this is properly eased"; do not trust "this
is specifically outBack" from one element.

Requires `opencv-python` and `numpy` (not repo dependencies — `pip install` them
into a scratch venv; nothing here is imported by the app).

`capture.mjs` has **zero dependencies**: Node 22+ ships a global `WebSocket` and
`fetch`, and the Chrome DevTools Protocol is just JSON over a socket. The loop is
the whole of it:

```js
for (let f = 0; f < total; f++) {
  const t = f / fps
  await evaluate(cdp, `window.__seek(${t})`)          // be this instant
  const { data } = await cdp.send('Page.captureScreenshot')  // photograph it
  writeFileSync(`f${f}.jpg`, Buffer.from(data, 'base64'))
}
```

The page must expose exactly two things:

```js
window.__duration   // number, seconds
window.__seek(t)    // put the page at t
```

Anything satisfying that contract can be captured by this pipeline — the film in
`film/` is one example, not a constraint.

---

## Authoring

Open `film/index.html` in a browser directly. There is a scrub bar at the
bottom; drag it, or use ← / → to step one frame at a time (shift for 10). That
is the fastest way to see how a beat is built. The bar is removed during capture
(`html.capturing`), so it can never appear in a frame.

To change the edit, edit `SC` in `film.js`. To change a beat, edit that scene's
function — it only ever sees its own local clock, so it cannot break the rest.

To re-time everything 20% faster, divide the stagger constants. `0.045 → 0.036`
is one character; the After Effects equivalent is re-dragging 54 keyframes by
hand.

---

## What this does not do

Worth being clear-eyed about, because "professional level" does a lot of lifting:

- **No sound.** Sound design is roughly half of why a film like this lands. This
  is silent.
- **No footage or photography.** Everything is drawn with divs, CSS and inline
  SVG.
- **No custom type, no logo design, no brand identity.** A system font and the
  existing reso palette.
- **Transitions are cuts and fades only.** No morphs, no match cuts, no real
  camera moves.
- **It does not decide what the thing should look like.** Choosing the palette,
  the mood and the rhythm is the part that takes a week. This pipeline makes
  *executing* a look cheap; it does not make *having* one cheap.

That last point is the honest limit. The technique collapses the cost of
production, not the cost of taste.

---

## Provenance

The technique was reverse-engineered from a demonstration published 2026-07-25
(`youtube.com/watch?v=oX43sxhvlWI`), in which the same approach — HTML/CSS
timeline, headless-Chrome frame capture, ffmpeg encode — produced a 38-second
film in a single pass. This implementation is independent, uses reso's own
palette and subject matter, and is structured for reuse rather than as a one-off.
