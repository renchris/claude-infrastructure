# A. OSS/dev-tool README hero banners

## What the good ones actually do

**The reference class splits cleanly into three, and only one of them reads as craft.**

| Class | Examples | What it signals |
|---|---|---|
| **Bespoke static art + a functional motion asset below it** | [catppuccin](https://github.com/catppuccin/catppuccin) (custom circular cat mark, `<picture>` theme-aware, palette-matched badges), [terrastruct/d2](https://github.com/terrastruct/d2) (static `banner.png` hero, then an `cli.mp4` showing the tool *working*), Charm's repos (hand-illustrated header + a [VHS](https://github.com/charmbracelet/vhs)-recorded terminal clip) | Craft. The hero is *identity*; the motion is *evidence*. |
| **Bespoke animated hero, hand-coded** | [Scalar's contributor planes](https://blog.scalar.com/p/how-we-created-an-animated-responsive) — SVG + `foreignObject` + `@keyframes`, planes drifting L→R "at slightly different offset speeds", contributor names cycling | Craft *intent*, broken execution (see §E1 — it does not animate in Firefox). |
| **Generator output** | [readme-typing-svg](https://github.com/DenverCoder1/readme-typing-svg) 9.1k★/1.6k forks · [Platane/snk](https://github.com/Platane/snk) 6.0k★/2.3k forks · [capsule-render](https://github.com/kyechan99/capsule-render) 1.8k★/729 forks, 15 header styles incl. "wave", 5 animations incl. `blinking`/`twinkling` | Gimmick. Instantly recognisable as *not made for this repo*. |

**Motion budget in the admired set: near zero in the hero, high in the demo.** d2, Charm, catppuccin, awesome-readme's own cited exemplars — the hero is a still. Where animation exists it is *below* the hero and it is a screen recording of the product. [awesome-readme](https://github.com/matiassingers/awesome-readme)'s praise language is telling: "Hero animation followed by the project logo" (gui-cs/Terminal.Gui), "explanatory motion gifs" (Clean-Coder-AI) — the animation earns its place by *explaining*, not decorating.

**Narrative events: essentially absent, and deliberately so.** The only widely-seen narrative-event README animation is snk (snake eats your contribution graph), and it is now the canonical profile-README cliché. Scalar's planes are the closest thing to an authored ambient scene in a serious dev-tool README, and they carry no discrete event — the planes just drift. Nobody in this class ships a "something happens" beat. §C explains why that is correct, not timid.

**One genuine design principle from the Scalar team, worth keeping:** *"When so many READMEs are the same, one that plays with the limits of it as a form really stands out."* The differentiator they name is **form-play**, not motion.

## Failure cases, and why they read cheap

From the [HN thread on CSS in GitHub READMEs](https://news.ycombinator.com/item?id=25349068) — the sharpest available critical sample:

- **"Developer MySpace."** The named failure is *category confusion*: decoration on an artifact whose job is orientation. One commenter: spend the time "making your code better, sorting, fixing and clear your issues."
- **Markdown source becomes line-noise.** READMEs are read as plain text (in editors, `cat`, `glow`, vendored copies). A 40-line HTML hero block at the top makes the raw file unreadable.
- **Mobile breakage and screen-reader failure** when SVG carries content without semantics.
- **Animations lag slow machines**; CPU cost for zero information.
- **It pushes the actual content below the fold.** This is the strongest structural criticism and it generalises directly ([hero-image critique](https://webdesignerdepot.com/stop-using-hero-images-theyre-killing-your-ux/)): a decorative hero that "pushes the primary call to action below the fold... creates unnecessary friction." At GitHub's 830px README width (§E3), a 1920×600 banner renders 830×259; add H1 + badge row and the first sentence of prose sits ~400px down.

**The tell that separates cheap from crafted, stated plainly:** a generator-produced hero is *recognisable across repos*. Typing-SVG, the wave capsule, the snake — a reader has seen them 50 times. Bespoke pixel art has no such prior. That alone buys most of the quality gap, before any craft.

**Praise the same thread grants:** for GUI/visual tools, screenshots and animation "communicate project value faster than text alone," especially for newcomers. So the licence exists — it is conditional on the media *carrying information*.

---

# B. Ambient looping pixel-art scenes as an art form

## The recurring craft moves that make these read expensive

**1. Depth is built from *colour bands*, not from objects.** Slynyrd's [Pixelblog 62 — Landscape Backgrounds](https://www.slynyrd.com/blog/2026/5/27/pixelblog-62-landscape-backgrounds) (May 2026) starts every scene by "creating solid horizontal bars of colour to define the horizon line," then subdividing. Depth is *primarily conveyed by colour choice*, before a single shape is drawn. Amateur work builds depth by drawing more stuff further away.

**2. Atmospheric perspective as a hard rule per plane:**
- Nearest plane = most saturated, strongest light/shadow contrast
- Each receding plane: saturation ↓, lightness ↑ (daylight), hue shifts *toward the sky colour*
- The valley scene: warmest hue nearest → shifts "more towards blue" at distance
- **Detail scales with the plane too**: near vegetation = "single pixel wide, short, vertical streaks"; mid = "one, or two pixel tall clusters at the most"; far = no individual blades at all
- Total palette across three full environments: **15 colours maximum**

**3. Palette discipline: ramps with mandatory hue-shift.** [Pixelblog 1](https://www.slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes): **9 swatches per ramp, +20° hue shift per step** as brightness rises. Slynyrd's stated reason is that heavy hue-shift "creates harmony between ramps." This is the single most reliable amateur/professional discriminator: a ramp that only changes value looks like a Photoshop brightness slider; a ramp that rotates hue looks painted.

**4. Parallax: pixel-perfect movement, or don't move.** [Pixelblog 23 — Parallax Scrolling](https://www.slynyrd.com/blog/2019/11/12/pixelblog-23-parallax-scrolling) gives the only hard numbers anywhere in this survey:
- Canvas width chosen for **divisor richness** — 96px, because it divides by 1,2,3,4,6,8,12,16,24,32,48
- Frame count = canvas width (96 frames)
- Background layer moves **1 px/frame**; each nearer layer takes the next faster *divisor* rate
- **Never slower than 1px/frame** — sub-pixel rates jitter. To go slower, repeat the image twice and halve the rate instead.
- **Nested loops must divide the master loop**: a 4-frame car cycle inside a 96-frame master is legal; a 5-frame one is not.
- "Balanced layers **without dominant points of interest** help hide the loop."

That last clause is the whole art form in one sentence, and it is the direct enemy of a micro-event (§C).

**5. Layer count: 4 is the working default, and more is not better.** The common structure is Foreground / Midground / Background / Static ([GameMaker on parallax](https://gamemaker.io/en/blog/creating-depth-and-immersion-parallax)), with the explicit caution that "there is a certain charm to having less layers, and the more layers you make the closer to 3D the visuals will feel" — i.e. layer count is a *style* dial, not a quality dial. Too little variation → flat; too much → chaotic. For a 3.2:1 banner strip with a walking creature, 4–5 is the band: sky (static) / stars+moon (static or near-static) / far silhouette / mid silhouette / ground+creature.

**6. How many things move at once: fewer than you think, and hierarchically.** Two independent lines converge:
- Animation's **secondary-action** principle: if a secondary motion "conflicts with, becomes more interesting, or dominates in any way, it is either the wrong choice or is staged improperly" ([Animation Mentor](https://www.animationmentor.com/blog/secondary-action-the-12-basic-principles-of-animation/)).
- [Smashing's ambient-animation principles](https://www.smashingmagazine.com/2025/09/ambient-animations-web-design-principles-implementation/) (Sept 2025): *"If someone's eyes are drawn to a raised eyebrow, it's probably too much, so dial back the animation until it feels like something you'd only catch if you're really looking."* Also: durations **3–6s**, `ease-in-out`, and — importantly — **"A single animation might be boring. Five subtle animations, each on separate layers, can feel rich and alive"** with varied rhythm/tone/timing.

So the answer is not "one thing moves." It is **~5 motions, each individually sub-threshold, on separate layers, at non-commensurate periods** — with exactly **one** motion allowed to be legible (here: the creature's walk).

**7. Where the eye rests.** In the lofi-loop canon the eye rests on the *character*, and the character is the least-animated element — [Sundstedt's Lofi Girl loops](https://sundstedt.se/blog/portfolio/lofi-girl-animated-music-video-loops/) are built by rigging characters and objects for "subtle animation" over painted-in occluded background, with lighting and particles added as "subtle details," on **multi-plane** 2.5D depth. The design goal is stated as visually interesting *"without distracting from the music."* Translate: your hero's job is not to be looked at; it is to be *glanced past* and remembered.

**8. Warmth is a lighting decision, not a hue decision.** The cozy-aesthetic literature consistently attributes the feeling to **soft, low-contrast, warm-source lighting** against muted/pastel surrounds, not to warm colours per se. In a night scene this means: the moon is cool, but one warm point-source (a lit window, a lantern, the wordmark itself) is what makes it cozy rather than bleak.

**9. Limited animation is the genre, not a compromise.** Lofi/ambient loops are explicitly built on limited-animation reuse. A representative shipped ambient asset: a [pixel campfire](https://srobinson111.itch.io/pixel-campfire) at **7 frames, 46-colour palette**, including smoke *and* flame. Seven frames is a complete ambient element.

---

# C. Micro-event cliché census

## The finding that outranks the ranking

**A discrete event is what makes a loop legible as a loop.** From ambient-loop craft: *"don't include unique sounds that repeat — any distinct event like a bird chirp, dog bark, or thunderclap will become a beacon of repetition"* ([Looping Drones](https://humlibrary.com/blogs/news/looping-drones-crafting-game-ambience-that-won-t-annoy)); ambient loops want **15–30s**, and 30s is roughly where a viewer's attention has drifted enough to mask the splice. Slynyrd's parallax rule says the same thing from the art side: **"balanced layers without dominant points of interest help hide the loop."**

Applied to a README hero, this produces a fork, and the second branch is the good one:

- **Looping event** → the reader who lingers 40s watches the shooting star fire twice and the illusion dies. The reader who leaves in 6s never sees it at all. Worst of both.
- **One-shot event** → fire it **once**, at ~2–4s after load, never repeating. Every reader gets exactly one event, at the moment they are still looking; nobody ever sees it repeat; the loop stays seamless because the looping layers contain no dominant point of interest. This is directly expressible in SMIL (`begin="2.5s" repeatCount="1"`) and *not* expressible with any generator tool. **This is the highest-leverage single decision in the artefact.**

**Corollary — the strongest available "event" is not an object at all: it is the light/dark theme itself.** The banner already must self-theme. Make the light variant a *day* scene and the dark variant a *night* scene, same composition, same creature, same walk. Each reader sees one world; the "event" is delivered by their own environment; and readers who switch themes get a genuine reveal. No stock asset can supply that, and it costs zero motion budget.

## Ranked: freshest → most tired

Ranking metric is empirical, not taste: a beat is **tired** in proportion to (i) its availability as a free/stock drop-in asset marketed for this exact use, (ii) its presence in beginner tutorials, (iii) its presence in the top README generators.

### Tier 1 — fresh (no stock-asset market; reads as observed-from-life)

| # | Beat | Why it's fresh | Emotional beat it delivers |
|---|---|---|---|
| 1 | **Cloud occults the moon; the whole ground layer steps down one palette rung, then recovers** | It's a *lighting* event, not an *object* event. No new sprite enters. Trivially cheap if the palette is built as Slynyrd 9-step ramps. Essentially unseen in pixel loops. | The world breathing. Same beat as a shooting star (a moment of change) with none of its Disney baggage. |
| 2 | **Earthshine — the crescent's dark limb faintly visible** ("the old Moon in the new Moon's arms", [APOD 2002-04-19](https://apod.nasa.gov/apod/ap020419.html)) | Real, constantly visible near new moon, and near-absent from pixel art because artists draw a crescent as a lit shape on *nothing*. Not an event — a permanent detail. | "Someone who has actually looked at the sky made this." |
| 3 | **A satellite pass — steady, non-blinking, no trail, crossing slowly** | The precise anti-shooting-star. ISS crosses horizon-to-horizon in **3–6 min at mag −4**, "a very bright, steady, non-blinking light... no flashing lights and no sound." The *absence* of a trail is the signal. | Quiet awe, modern rather than fairytale. |
| 4 | **Heat lightning below the horizon — a far cloud lights from inside, one or two frames, no bolt** | Weather happening *elsewhere*. Almost never depicted without a visible bolt. | The world is bigger than the frame. |
| 5 | **Aircraft anti-collision strobe** — one red flash ~1/s on a slow dot | ~4 pixels total. Unmistakably modern and real; distinguishable from a satellite precisely *because* it blinks. | Late-night, someone else is awake. |
| 6 | **Wind as a propagating wave** — gust hits near grass, mid trees ~0.4s later, far trees later still | Motion with *causality* instead of motion with *objects*. Slynyrd devotes a whole entry to it ([Pixelblog 33 — Wind Effects](https://www.slynyrd.com/blog/2021/7/16/pixelblog-33-wind-effects)) and almost nobody stages the delay. | Physical presence of air. |
| 7 | **Delayed secondary reaction** — creature passes a puddle; the reflection ripples one beat *after* | Secondary action done properly (the delay is the craft). Cheap: one 3-frame ripple. | The creature is *in* the world, not composited onto it. |
| 8 | **A distant window light goes out** | Narrative in one 2×2 pixel cluster, no motion path, no new sprite. | Someone went to bed. Time is passing. |
| 9 | **The creature stops, looks off-frame, resumes** | Anticipation with no payoff. Authored restraint; nearly unseen. | Interiority. |
| 10 | **Breath vapour — one puff every N steps** | Establishes temperature *and* life in ~6 pixels. | Cold night, warm animal. |
| 11 | **Footprints that persist then fade behind the creature** | Makes the loop's own history visible; hides the seam by giving the eye a trailing gradient rather than a hard reset. | Journey. |
| 12 | **A moth orbiting the lit letter of the wordmark** | Ties the ambient beat to the *brand mark* — the one move no stock asset can ever supply. | The scene and the logo are one object, not a logo pasted on a scene. |
| 13 | **Starfield rotating a few art-pixels over the master loop** | Diurnal motion is real and essentially never animated. Sub-threshold by construction. | Sublime, unnoticed. |

### Tier 2 — worn but survivable at low dosage

14. Fireflies — heavy in cozy-asset packs; survivable at **2–3**, fatal at 30
15. Chimney/campfire smoke — free 7-frame packs exist; fine as *ambient*, not as *event*
16. Rain / rain-on-glass — the lofi-visual signature; instant genre-tag
17. Falling leaves / petals — drifting-object move #2
18. Lighthouse beam — strong shape, but it's a metronome and metronomes expose loops
19. Distant train with lit windows — good, but it's a *big* dominant point of interest
20. Bird flock in V — reads as clip-art at small scale
21. Cat tail flick / ear twitch — fine as idle *ambient*; not an event

### Tier 3 — tired

22. **Blinking eyes** — not an event, an idle. Harmless but earns nothing.
23. **Creature waves at the viewer** — breaks the fourth wall and converts an observed scene into a mascot ad; also collides directly with the 👋 waving-hand emoji that opens roughly every profile README.
24. **Floating Zzz** — this is *UI iconography*, not observation. It is the sleep-state icon from a thousand games.
25. **Drifting hot-air balloon** — the default "add interest to an empty sky" move; reads as filler because it *is* filler.
26. **Shooting star** — the most tired beat available. Hundreds of stock listings on single vendors ([165 on Dreamstime alone](https://www.dreamstime.com/illustration/falling-pixel-star.html), 640+ video assets on iStock), taught in every beginner night-sky tutorial, and available as a [free itch.io drop-in](https://pixel-salvaje.itch.io/free-falling-star-animation) explicitly marketed as: make them "pop up randomly in night backgrounds." When a beat ships as a free asset *pitched at your exact use case*, it cannot signal craft.
27. **Typing/glitch wordmark** — readme-typing-svg, 9.1k★
28. **Snake/creature consuming the contribution graph** — snk, 6.0k★ / 2.3k forks
29. **Wave/gradient capsule header** — capsule-render, 1.8k★, and its animation menu is literally `blink`, `blinking`, `twinkling`

---

# D. Craft technique for the specific elements

## D1. Night-sky starfield

**The rule that does most of the work — desaturate almost everything.** Human colour vision fails on faint point sources (**small-field tritanopia**): "only the brightest stars are able to activate your cones, which is why fainter ones appear white — that is, colorless" ([BBC Sky at Night](https://www.skyatnightmagazine.com/space-science/star-colours)). So:

- **Give hue to 3–6 stars in the entire field, no more.** Everything else is near-white / blue-grey / one step off the sky colour. A field of vividly multi-coloured stars is the #1 amateur tell and it is *factually wrong*, not just gaudy.
- The 3–6 coloured ones follow real temperature order: blue-white (hottest) → white → yellow → orange → red. Pick warm ones for contrast against a cool sky.
- **Brightness tiers, not one tier**: a starfield needs at least 3 magnitudes — a handful at full palette-white, a middle band one ramp step down, and a majority two steps down (barely above sky). Uniform brightness is the second amateur tell.
- **Placement: clustered-random, never grid, never even.** The canonical guidance is to "place big stars next to little stars and with varying spaces," avoiding "an even or uniform placement... consistent, regular pattern or... equal distances." Practically: generate randomly, then hand-fix — delete anything that forms a line, a triangle, or an obvious constellation you didn't intend, and **carve a deliberate void** where you want the eye to rest (behind the wordmark, above the creature).
- **Twinkle: animate a minority, at incommensurate periods.** Twinkle is atmospheric scintillation and it's strongest *near the horizon*, weakest at zenith — so twinkle the low stars, leave the high ones steady. Never twinkle all of them, never on a common period (that reads as a pulse). Practically: 3–5 groups on periods like 2.3s / 3.1s / 4.7s / 5.9s (mutually prime-ish), each just ±1 ramp step, most stars never twinkling at all.
- **Diffraction spikes: only on the single brightest star, and only if you have ≥3px to spend.** Spikes are a *telescope/camera* artifact, not a naked-eye one. On a small pixel star a 4-point spike is 5 pixels and reads as a sparkle emoji. Default: no spikes anywhere.
- **AVOID**: pure `#FFFFFF` for everything (blows out against a dark sky and destroys the magnitude hierarchy — use the palette's second-lightest); 1px stars at a scale where 1px will land on a fractional device pixel (§E3) and shimmer; equal spacing; a star visible *through* a cloud.

## D2. Crescent moon with believable glow

**The geometry, which is where amateurs die.** A crescent is bounded by **a half-circle and a half-ellipse** — the lit limb is a circular arc, the terminator is an *elliptical* arc whose major axis is a diameter of that circle ([Crescent](https://handwiki.org/wiki/Crescent), [Terminator (solar)](https://en.wikipedia.org/wiki/Terminator_(solar))). Drawing both arcs as circles of different radii — the "two overlapping circles" method every tutorial teaches — produces the *logo* moon, not the *sky* moon.

Two further constraints, both mocked in [xkcd 1738 "Moon Shapes"](https://www.explainxkcd.com/wiki/index.php/1738:_Moon_Shapes):
- **The horns must point away from the sun**, and at night the sun is below the horizon → **a night crescent's horns point downward-ish toward the horizon, never straight up.** "Horns up at night" is explicitly flagged *Not possible at night*.
- **The line joining the two horns must be a diameter** of the moon's disc. Wide crescents whose horn-line is a chord rather than a diameter are physically impossible.

**Earthshine** — see §C item 2. One ramp step above sky, filling the unlit disc, bounded by the same circle. Costs nothing, and it is the single detail that most separates "drawn a moon" from "looked at the moon."

**Glow, done as pixel art rather than as a blur.** Bloom in the shader sense (identify bright pixels → Gaussian blur → additive composite) is the *wrong* mental model here: a smooth radial alpha gradient behind a pixel moon reads as a Photoshop layer sitting on top of pixel art, and it will band. The pixel-art construction is:
- **2–4 concentric bands** stepping down your sky ramp (not a continuous gradient), each band 1 ramp step, radii growing non-linearly (tight, then looser) to fake inverse-square falloff.
- **Hue-shift the glow toward the moon's own hue** and *desaturate* outward — the glow is the sky lit by the moon, so it must resolve into the sky colour, not into grey.
- **Dither only the outermost band's boundary** — the transition into pure sky. Interior band boundaries stay hard.
- The glow is **not concentric on a crescent** — it centres on the *lit* portion, so it sits offset toward the horns' outer edge. Centring the glow on the disc is a tell.
- **AVOID**: glow radius > ~2.5× the moon's radius (reads as fog); a glow band that is a different hue family from the sky; any glow at all on a *full* moon in a scene that also has stars (a full moon washes stars out — pick one).

## D3. Dithered clouds

**Where dithering belongs, and the discipline that stops it looking cheap** ([Pixel Parmesan](https://pixelparmesan.com/blog/dithering-for-pixel-artists), [Divoom](https://divoom.com/blogs/setup-ideas/pixel-art-dithering-when-to-use-and-stop)):

- **Dither exists to fill a gap in the palette, not to shade.** "If your palette already includes the mid-tone you need, just use it. Dithering exists to fill gaps, not to replace available colours. Reach for the palette first, the dither second."
- **Transitional dithering** (softening one colour into the next) is the cloud use-case; **fill dithering** (creating a whole new perceived colour) is the sky-gradient use-case.
- **Contrast determines step count**: "the greater the contrast between the two colours you are blending, the more dithering steps you will need (and in turn the greater the resolution required)." A 2-step dither between two adjacent ramp rungs is invisible and wasted; a 2-step dither across a 4-rung jump looks like static.
- **Reuse a small set of patterns and vary the intermediate colours** — do not cycle through every pattern in your head. Consistency of pattern is what reads as a *material*.
- **Zoom to 1:1 before judging.** "Dithering that looks beautiful at 800% zoom... falls apart at real viewing distance. If the dithered area looks like TV static or random noise instead of a smooth gradient, you've over-dithered." For this artefact, judge at the **actual rendered size** (§E3), not at 1:1 of the art grid.
- **Clouds specifically**: Slynyrd builds cloud bodies from overlapping arched highlight shapes over a base silhouette made with varied-diameter pencil strokes, and warns that clouds "can take a lot of dithering, but you can lose the nice shapes you worked hard on." So: **dither the interior transition, keep the silhouette hard.** The silhouette is the design; the dither is the material.
- **The animation trap, and it is the decisive one here:** "a dither pattern that looks great on a static sprite can shimmer and crawl once the sprite animates. **If a region moves, keep it flat or hand-place the dither so it stays stable.**" Drifting clouds in a parallax layer are moving regions. Therefore: **clouds that move must translate their dither with them as a rigid group** (never regenerate the pattern per frame), and must translate in **whole art-pixel steps** (Slynyrd's pixel-perfect rule) or the pattern will crawl.
- **AVOID**: 50% checkerboard across a whole cloud (the single loudest amateur signature); dithering the cloud's outer edge against the sky *and* the interior (pick the interior); dither on any element smaller than ~8px.

## D4. The general amateur/professional tells (apply to every element above)

From [Derek Yu's canonical list](https://www.derekyu.com/makegames/pixelart2.html) and the Pedro Medeiros/Pixel Parmesan corpus:

- **Too many similar colours** — "when colours are too similar, pixels begin to blend together and get lost." Each palette entry must have an identity. 15 colours for a whole landscape is the professional benchmark (§B).
- **Naive colouring** — pure "as they should be" colours (blue sky, grey rock) without reflected light. In a night scene: nothing is neutral grey; everything takes a moonlight tint.
- **Pillow shading** — shading inward from the outline as if the viewer is the light source. "Almost never occurs naturally... makes the object look blurry and indistinct." Fatal on the creature.
- **Banding** — parallel same-length runs of adjacent ramp colours; "only draws the eye by reinforcing the theoretical grid."
- **The Chunky Pixels Rule** — avoid single-pixel-thickness elements. Doubly binding here, because 1px features are exactly what dies under non-integer downscale (§E3).
- **Over-anti-aliasing** — "the most common mistake is when the anti-alias is overdone causing a blurry effect. Avoid this by using fewer colour halftones, fewer steps, and do not use anti-alias on 45° lines or straight lines."

---

# E. Adversarial pass — what this survey nearly missed

These are hard constraints discovered by asking "what would falsify the plan," and several change the build.

### E1. CSS `@keyframes` inside an `<img>`-referenced SVG **does not animate in Firefox**. Use SMIL.

[Mozilla bug 1190881](https://bugzilla.mozilla.org/show_bug.cgi?id=1190881) — "SVG CSS animation not working through img tag." Root cause named in the bug: `SVGDocumentWrapper::IsAnimated` only checks for SMIL animations, not CSS animations, so the `VectorImage` is never added to the refresh driver. Meanwhile **SMIL (`<animate>`, `<animateTransform>`, `<animateMotion>`, `<set>`) animates in `<img>` across every modern engine** — and Chrome *suspended* its SMIL deprecation precisely because "animations inside img-tag SVGs have no CSS or Web Animations equivalent."

**Consequence: the Scalar case study's technique (`foreignObject` + `@keyframes`) is a static image for every Firefox reader**, and `foreignObject` inside SVG-as-image is separately unreliable in Safari (it silently fails to render without explicit `width`/`height`; see [mdn/content#1319](https://github.com/mdn/content/issues/1319)). The most-cited prior art in this space is technically broken. Build in **SMIL only**, and never route pixel art through `foreignObject`.

Supporting constraint: GitHub's CSP on raw SVG includes `style-src 'unsafe-inline'`, which is what allows SMIL to run in Firefox at all ([bug 1683972](https://bugzilla.mozilla.org/show_bug.cgi?id=1683972) — Firefox blocks SMIL under a bare `default-src 'none'`; GitHub's header is the documented workaround). Do not self-host the SVG behind a stricter CSP.

### E2. No external fonts. The wordmark must be geometry.

MDN, [SVG as an image](https://developer.mozilla.org/en-US/docs/Web/SVG/Guides/SVG_as_an_image): scripts disabled, `:visited` disabled, **"external resources cannot be loaded, though they can be used if inlined through `data:` URLs"** — and "fonts shouldn't be loaded" either. A `<text>` element with a webfont will fall back to whatever the renderer picks, silently, per-platform. Draw the wordmark as pixel geometry (which the brief wants anyway) or as outlined paths. Never `<text>` + `font-family`.

### E3. 1920×600 is ~2.3× oversampled for GitHub, and the scale factor is non-integer — the pixel-art killer.

Measured rendering widths ([wh0, May 2025](https://wh0.github.io/2025/05/18/banner-width.html)):

| Surface | Max rendered width |
|---|---|
| **GitHub repo README** | **830px** |
| GitHub markdown file view | 1012px |
| VS Code extension view | 882px |
| VS Code Marketplace | 710.55px |
| Glitch project page | 965px |

All scale **down**, and narrower viewports scale further. A 1920-wide asset in an 830px column is a **0.432× downscale**; pixel art scaled by a non-integer factor gets "geometric distortion, commonly referred to as shimmering or pixel wobble" — at a fractional factor "some pixels are 1×1, while others are 2×2, 2×1, and 1×2" ([integer scaling](https://tanalin.com/en/articles/integer-scaling/)).

**Recommendation:** choose the art grid so that the *rendered* scale is an integer at the dominant surface. `830 / 415 = 2`. So design on a **415×130 art grid presented in a 830×260 viewBox at 2×** — or accept 830 native at 1×. Never design at a grid where 830/grid is fractional (480 → 1.729× → mush). Because the column narrows on smaller viewports you cannot guarantee integer scale everywhere, which is exactly why the **Chunky Pixels Rule** (§D4) is load-bearing: with no feature thinner than 2 art-pixels, fractional rounding stays invisible.

Related: `image-rendering: pixelated` is **not** a reliable rescue — the SVG attribute form works only in Firefox/Inkscape, the CSS form was Chrome-first, and the recommended belt-and-braces is `<image image-rendering="optimizeSpeed" style="image-rendering:pixelated">` with pre-upscaling as the actual fix ([Siipola](https://zpl.fi/pixelated-images-in-svg/)). Note it applies only to raster `<image>`, never to vector rects/paths.

### E4. Movement must be in whole art-pixels, stepped — not interpolated.

Slynyrd's parallax rule ("pixel perfect movement... only moves in increments of pixel units", never slower than 1px/frame) has a direct SMIL expression: **`calcMode="discrete"` with explicit `keyTimes`** for both the walk-cycle frame swap and the parallax translation. Default `calcMode="linear"` will place the creature and the cloud layers on fractional coordinates every frame — which is precisely the mechanism that makes dither patterns "shimmer and crawl" (§D3) and 1px stars flicker. Master loop length should be chosen for divisor richness so every nested cycle (walk = 6 or 8 frames, twinkle groups, cloud drift) divides it exactly.

### E5. Reduced motion: GitHub's own control does **not** cover you, and you cannot use JS.

GitHub ships an accessibility setting — Settings → Accessibility → Motion → **"Autoplay animated images": Sync with system / Enabled / Disabled**, which renders a play/pause button on animated images ([changelog, 2022-05-19](https://github.blog/changelog/2022-05-19-option-to-prevent-animated-images-from-playing-automatically/)). **That control governs GIF/APNG/WebP. An animated SVG is not an "animated image" to it** — so a reader who has explicitly asked GitHub to stop animations will still get your banner moving, with no pause button. Separately, WCAG 2.2.2 (Pause, Stop, Hide) applies to any auto-starting motion lasting >5s presented alongside other content.

The only lever available inside an `<img>`-referenced SVG (no JS, no `matchMedia`) is a **CSS media query that disables the SMIL elements**:

```css
@media (prefers-reduced-motion: reduce) {
  animate, animateTransform, animateMotion, set { display: none; }
}
```

`display:none` on an animation element disables it, and the media query itself *does* evaluate in image context (Firefox's bug is the refresh driver for CSS animations, not media-query evaluation). **This forces a real design constraint: the base attribute values must compose a good static frame** — creature mid-stride in a readable pose, moon and glow at rest, wordmark fully legible. Design the still first; the motion is a layer on top of a complete picture.

### E6. Theme-switching is fragile and does *not* track the GitHub theme setting.

`<picture>` + `prefers-color-scheme` is the officially supported mechanism ([GitHub blog](https://github.blog/developer-skills/github/how-to-make-your-images-in-markdown-on-github-adjust-for-dark-mode-and-light-mode/)), but:

- **It reads the OS/browser setting, not the GitHub appearance setting.** A user on GitHub-dark with OS-light gets the *light* banner on a dark page. Documented in [community discussion #16910](https://github.com/orgs/community/discussions/16910), including a specific inversion bug with Night theme + "Light default". The [driesvints investigation](https://driesvints.com/blog/investigating-dark-mode-for-svgs-in-github-readmes) proves the alternative is impossible: SVGs referenced through `<img>` cannot see the parent DOM's `data-color-mode`.
- **`<source srcset>` is not path-rewritten** — you must hardcode absolute repo URLs, which sends the variants through **camo** and its aggressive cache (`curl -X PURGE https://camo.githubusercontent.com/<id>`; several GitHub Actions exist purely to bust it). *Version the filename (`hero-night-v3.svg`) rather than relying on purge.* By contrast a plain relative `<img src>` is rewritten to `/{owner}/{repo}/raw/{ref}/{path}` and **camo is not in the path at all** — bytes served SHA256-identical (verified end-to-end in this repo's own `demo-recording` skill, `~/.claude/skills/demo-recording/SKILL.md`).
- **The GitHub iOS app does not support `<picture>` with relative links** — unresolved for years.

**Robustness recommendation:** put the day/night switch *inside a single SVG* via `@media (prefers-color-scheme: dark)` on fills, and reference it with a plain relative `<img>`. One file, no camo, no srcset rewriting, no iOS-app breakage — and it degrades to whichever variant is the CSS default rather than to nothing. It still can't see GitHub's own theme toggle; nothing can.

### E7. Size and cost.

An unoptimised pixel-art SVG expressed as one `<rect>` per pixel is a DOM bomb — "an unoptimised SVG illustration can easily be 500 KB with 10,000+ path nodes," and node count costs main-thread parse time, not just bytes. Mitigations: run SVGO with `mergePaths` (merges adjacent same-style paths), emit **one `<path>` per palette colour** using `M…h…v…z` runs rather than per-pixel rects, and keep the art grid small (§E3's 415×130 = 53,950 cells worst-case, but a 15-colour scene with large flat regions collapses to a few thousand path commands). Also: `interfaces.rauno.me` rule — *"Looping animations should pause when not visible on the screen"* — **you cannot honour this in an `<img>` SVG** (no IntersectionObserver, no JS). Your banner animates forever, off-screen, on every open README tab. That is a real argument for keeping the total animating-element count in the low tens, animating *groups* rather than individual stars, and avoiding SVG filters (`feGaussianBlur`, drop-shadow) entirely — Smashing flags blur/shadow as the ambient-animation performance trap even in normal DOM.

### E8. Portability beyond github.com.

The banner will also be rendered by npm, PyPI (`readme_renderer` sanitises HTML; `twine check` is the required local verification), crates.io, pkg.go.dev, the GitHub mobile apps, and plain-text readers. `<picture>` and raw HTML are the first things stripped. Design so the **`<img>` fallback alone is a complete, correct hero**, and keep the repo's `# Title` H1 present beneath it — deleting the H1 because "the wordmark is in the banner" destroys the anchor target, the screen-reader landmark, and every non-HTML rendering.

---

## Blockers / uncertainties

- **GitHub Primer canvas hex values not verified this session.** Whether the night sky's darkest rung should *match* GitHub's dark canvas (bleed, no visible edge) or deliberately differ (contained rectangle) is a real design fork; verify current `--color-canvas-default` tokens before committing.
- **Exact 830px figure is from a single 2025 measurement** ([wh0](https://wh0.github.io/2025/05/18/banner-width.html)), consistent with the widely-documented 980–1012px markdown body but not independently re-measured. Re-measure in a browser before locking the art grid — this number determines the whole pixel scale.
- **`display:none` on SMIL elements under `prefers-reduced-motion`**: spec-supported and reported as working ("technically disables animations"), but I found no source testing it *specifically inside an `<img>`-referenced SVG on GitHub*. Verify empirically on a scratch branch before relying on it as the accessibility story.
- **Critical discourse on README animation is thin** — one strong HN thread, no substantial Reddit/design-community sample surfaced. The §A failure-case analysis rests on that thread plus general hero-image UX literature; treat "developer sentiment" claims as directionally sound rather than statistically grounded.
- **No named example found of a bespoke pixel-art animated hero in a serious dev-tool README.** Multiple search angles returned only generators, GIF-collection repos, and profile-README templates. This is either a genuine gap in the field — which is the opportunity — or a search-visibility failure. I lean toward genuine gap: the technique constraints in §E1–E5 are obscure enough that few would get through them.