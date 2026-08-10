---
status: open
owner: readme-banner
created: 2026-07-29
supersedes: none
---

# README hero banner — an animated Claude mascot for the header

Own track, split out of `README_MEDIA_PIPELINE.md` § Task 3. That doc holds the operator ask and
the constraints already settled by measurement; this one holds the design work, the prototypes,
the comparison, and the recommendation.

> **LANDED 2026-07-30 (`1c54e73c`).** The frozen scope below is met: `v6c-dusk-line` is in the README
> header. What it took first — two lying instruments, a half-applied operator ruling, and three beats
> whose entrances and exits did not exist — is recorded in `BANNER_NARRATIVE_SPEC.md` § v8. Still
> open and named there: the subtitle's 7.42 CSS px and banner height — **both art-direction calls on
> the operator's own page, offered and not taken.** WebKit was the third and is **CLOSED 2026-08-09**:
> it ticks, so all three engines are measured (§ S24).

**Scope (frozen):** design a 1080p60, awwwards-calibre animated Claude-mascot banner for the
README header. Prototype **at least three mediums** (animated SVG · moving ASCII · raster),
compare them side by side on measured evidence, recommend one with the trade-offs named. **Land
the winner into the README header only after the operator has seen the comparison.**

**Explicitly out of scope** (owned by a separate track): the hero recording
`assets/demo/handoff-live.*`, the demo GIFs, and Tasks 1–2 of the media pipeline. This track adds
files under `assets/banner/` and touches `README.md` only at the header, only at the end.

**No Phase 0 / Agent Team.** This is a single-author design task — one composition, iterated
visually against a screenshot harness. Splitting it across teammates would fragment the one thing
that has to stay coherent (the timing). Deliberate, not an omission.

---

## Inherited constraints — settled by measurement, not re-litigated

From `README_MEDIA_PIPELINE.md` § Task 1 and § Task 3:

| Constraint | Consequence for this track |
|---|---|
| GitHub's sanitizer strips `<video>` outright (verified against `gh api /markdown`) | The header can hold an **image** only. `<img src="…svg">` survives and is auto-linked. |
| An animated SVG **does** work in `<img>` on GitHub — declarative CSS/SMIL runs, scripts do not | The SVG medium is viable. No JS anywhere; every prototype must be inert-when-scripted. |
| `<picture>` + `prefers-color-scheme` follows the **reader's OS setting**, not GitHub's theme toggle | A theme-split banner can render light-on-dark for a reader whose OS and GitHub disagree. See § "Why one committed look". |
| The hero recording directly below is already **3.3 MB** | Budget: **well under 1 MB**. A banner that competes with the artifact beneath it has already failed. |

Reference implementation for the CSS-keyframe + `prefers-reduced-motion` pattern:
`assets/diagrams/handoff-choreography.svg`, removed in `a85e87e4`, recovered from git for this
work. Its shape — one shared master timeline on a `.a` class, a `@media (prefers-reduced-motion:
reduce)` block that freezes every element into a legible static composition and swaps an animated
caption for a static one — is reused directly.

---

## The one strong idea

The README's thesis is **sessions run each other**. The mascot should *enact* that thesis, not
decorate it.

> **One Claude starburst divides into two. They exchange a single pulse along a hairline. One of
> them retires — leaving one.**

That is `self-open → two-way → self-close`, the repo's entire loop, told with the mark alone in
under eight seconds, with nothing on screen but two glyphs and a thread.

**Why the starburst is the right mascot here.** Claude's mark is the radiating asterisk, and
Claude Code renders it as a literal terminal glyph (`✻ ✽ ✳`) in its own splash and spinner. It is
simultaneously the brand mark *and* a character — which is what makes the ASCII medium a genuine
contender rather than a gimmick, and lets one design idea be expressed honestly in all three
mediums. That is the point of prototyping across mediums instead of picking one and defending it.

### Restraint rules this banner is held to

These are the bar, and every prototype is scored against them in § Comparison.

1. **It must settle.** A perpetual loop directly above the h1 and the badge row is the classic
   header failure — the eye keeps getting pulled back while the reader is trying to read. The
   narrative plays **once**, then rests. Any residual motion is an ultra-low-amplitude breath on
   the resting mark, slow enough to be felt rather than watched.
2. **The resting state is the deliverable.** The animation is a bonus a reader may scroll past.
   The frame it holds on must be a composition worth having as a static banner. This also covers
   the reader who lands mid-decode, and the `prefers-reduced-motion` reader, with the *same*
   artwork rather than a degraded fallback.
3. **Two objects and a thread.** No particles, no gradients-in-motion, no parallax field.
4. **Type is a whisper.** The h1 and the tagline sit immediately below and say it better. The
   banner carries the mark; any text is micro-type at the edge of legibility-by-design.

### Why one committed look, not a theme split

`<picture>` + `prefers-color-scheme` keys off the **reader's OS**, so a reader on OS-light with
GitHub-dark gets a light plate on a dark page — a visible seam on the very first element of the
README. Committing to a single dark plate: (a) is immune to that mismatch, (b) matches the
terminal recording directly beneath it, which is a dark capture, and (c) reads correctly on
GitHub light, where a dark hero plate is conventional. The trade-off — a dark banner is a
deliberate object on a light page rather than invisible chrome — is accepted, and the light-theme
render is included in the comparison so the operator can judge it rather than take it on trust.

### On "1080p60"

Honored as **1920 px of horizontal resolution at 60 fps**, not a literal 1920×1080 frame: at the
README's 900 px display width a 16:9 banner would stand 506 px tall and swallow the entire fold
above the hero recording. Authored at **1920×600** (16:5), displayed at `width="900"` to match the
existing hero. For the vector prototypes "1080p" is a floor rather than a ceiling — they are
resolution-independent and composite at the browser's own frame rate. For the raster prototype it
is a literal, and measurable, requirement. Aspect is a one-line `viewBox` change if the operator
wants it taller or wider.

---

## Mediums under test

| # | Medium | What it is | The question it has to answer |
|---|---|---|---|
| **A** | Hand-authored animated SVG | Vector starburst, CSS keyframes on one master timeline | Can vector carry the idea with enough craft to make raster unnecessary? |
| **B** | Moving ASCII | The mascot in glyphs, animated as SVG `<text>` — tiny, crisp, selectable | Does the operator's named candidate survive contact with the restraint rules, or does per-cell motion read as noise under the README text? |
| **B2** | Moving ASCII, real terminal | Captured through the existing `vhs` pipeline | Is a genuine terminal capture more honest than a simulated one — and what does it cost in bytes? |
| **C** | Raster (animated WebP + GIF) | A literal 1920-wide 60 fps render, encoded both ways | What does honoring "1080p60" literally actually cost against the sub-1 MB budget? |

## Evaluation rubric

Scored in § Comparison on evidence, not assertion. Bytes are measured; renders are screenshots,
not descriptions.

- **Weight** — bytes on disk, against the well-under-1 MB budget.
- **Fidelity at 900 px and at 2× (Retina)** — the README is read on Retina displays.
- **Frame rate actually delivered.**
- **Behaviour on GitHub light and dark.**
- **`prefers-reduced-motion`** — does a static composition survive, or does it collapse?
- **Reviewability** — can the next session read the diff and know what changed?
- **Regenerability** — is there a build step, and does it drift from its source?
- **Does it settle** — restraint rule 1, the header-specific failure mode.

## Verification method

No SVG rasterizer is installed (`rsvg-convert`, `resvg`, `inkscape` all absent), so verification
runs through headless Chromium (`~/Library/Caches/ms-playwright/chromium-1194`, Chromium 141) via
`scripts/banner-shots.sh`. Two things matter and are both checked:

1. Each prototype is rendered **inside `<img src="…">`** — SVG-as-image mode, which is what GitHub
   actually does and which is stricter than a standalone SVG document (no scripts, no external
   resources).
2. Frames are frozen deterministically by injecting `animation-delay: -Ts; animation-play-state:
   paused` rather than by racing a timer, so the same timestamp screenshots identically every run.

Rendered on the GitHub light and dark page backgrounds at the true 900 px README width.

---

---

## The prototypes as built

| # | File | Bytes | What it is |
|---|---|---|---|
| **A** | `assets/banner/proto-a-vector.svg` | **9,365** | Vector starburst — eleven tapered rays, CSS keyframes |
| **B** | `assets/banner/proto-b-ascii.svg` | 12,322 | ASCII mark on a 45×25 character grid, per-character density flash on each beat |
| **B2** | `assets/banner/proto-b2-ascii-coarse.svg` | 10,260 | The same on a 25×15 grid — glyphs large enough to read *as glyphs* |
| **C** | measured only, not committed | see below | The **same artwork**, rendered out of A to 480 frames at 1920×520 and encoded |

All three share one canvas, one rail, one type block and one 8 s timeline, so the comparison
isolates the medium rather than the idea. Side by side, animating, at the true README column
width: **`assets/banner/comparison.html`** (self-contained — the prototypes are inlined, so it
renders anywhere).

C is deliberately a render *of* A. That isolates the medium's cost: the picture is identical by
construction, so only weight and frame rate differ. The honest caveat is that this also denies
raster its only real advantage — effects vector cannot express (true motion blur, grain,
photographic elements). This design does not want any of them, and the restraint bar argues
against a design that would.

## Comparison — measured 2026-07-29

| Encoding of the same 8 s composition | Frame rate | Bytes | vs the 1 MB budget |
|---|---|---|---|
| **Animated SVG (A)** | browser-native, uncapped | **9,365** | 0.9 % |
| **Animated SVG, ASCII mark (B)** | browser-native, uncapped | 12,322 | 1.2 % |
| Animated WebP, 1920 wide, q72 | 60 fps | 2,229,294 | **2.2× over** |
| Animated WebP, 1920 wide, q50 | 60 fps | 1,716,748 | **1.7× over** |
| Animated WebP, 1920 wide, q72 | 30 fps | 1,189,110 | **1.2× over** |
| Animated WebP, 1920 wide, q72 | 12 fps | 545,728 | fits — but 12 fps, not 60 |
| GIF, 1920 wide, 128 colours | 50 fps † | 45,186,759 | **45× over** |
| GIF, 1920 wide, 128 colours | 12 fps | 14,548,774 | **14× over** |

† **GIF cannot express 60 fps at all.** Frame delays are integer centiseconds, so the available
rates either side are 50 fps (2 cs) and 100 fps (1 cs). Read back from the encoded file: the
Graphic Control Extension carries `delay = 2 cs`. The GIF figures are also flattered by nothing —
this composition has gradients, which a 128-colour palette handles badly; a flat-colour redesign
would compress better, but WebP is the fair raster benchmark and it is over budget on its own.

### What each medium actually proved

**A — vector.** Carries the idea at 0.9 % of the budget and is resolution-independent, so it is
sharper than 1080p on the Retina displays where the README is actually read. It composites at the
browser's own frame rate, which makes "60 fps" a floor rather than a target.

**B — ASCII.** It works, it is only 12 KB, and the per-character density flash is real motion. But
the medium imposes a choice that tuning cannot dissolve: at README width the grid is either
legible **as a mark** (fine grid — but the characters render around 5 px and read as texture, so
you pay ASCII's resolution cost and get none of its identity) or legible **as characters** (coarse
grid — the glyphs resolve, and the mark stops holding together). Both are in the comparison page;
the difference is not a tuning miss, it is the trade-off.

The mark's geometry was constrained by the medium too. Eleven rays — the count that makes the
Claude mark itself — cannot be rendered on a character grid: an odd count leaves the ray at 0°
with nothing opposite it, and horizontally-adjacent glyphs merge into a solid rule rather than
reading as a ray, which stacked glyphs do not do. Eight rays put rays *on* the horizontal, same
problem. Ten rays with a vertical peak was the first configuration that resolved. So the ASCII
mascot is necessarily a *different* mark from the vector one.

ASCII's real home is a terminal at terminal scale — which this README already has, twice, in the
recordings below the banner. Repeating that texture in the header reproduces it at its worst
resolution.

**C — raster.** A literal "1080p60" banner costs **2.23 MB**: 238× prototype A, 2.2× the budget,
and two thirds of the 3.3 MB hero recording it would sit above. Every way of getting under 1 MB
costs the thing that was asked for — drop to 12 fps, or drop the resolution. This is the finding
that settles the medium question rather than a preference about it.

## Recommendation — prototype A, the hand-authored animated SVG

On the rubric, with the trade-offs named:

- **Weight** — 9,365 bytes, 0.9 % of budget, 0.27 % of the hero beneath it. The nearest raster
  that honours 60 fps is 238× larger and does not fit.
- **"1080p60" is only actually deliverable in vector.** Raster must give up either the frame rate
  or the budget; GIF cannot express the frame rate at any weight.
- **Fidelity** — resolution-independent, so it is correct at 2× and at any future column width.
- **Reduced motion** — freezes to a resting frame that is *pixel-identical* to the played-out
  state (RMSE 0 for all three prototypes, against a positive control confirming the emulation
  actually fires: forcing the setting moves the render by 6.4 %). It is the same artwork, not a
  degraded fallback.
- **Reviewability** — a 9 KB text file. The next session reads the diff and knows what changed.
- **Regenerability** — no build step at all, so it cannot drift from a source. B needs a
  generator; C needs a 480-frame export and an encoder.
- **It settles** — nothing loops. The story plays once and holds.

**Trade-offs accepted, not hidden:**

1. **It commits to a dark plate.** On GitHub light it reads as a deliberate dark card rather than
   invisible chrome. This is the deliberate alternative to a `<picture>` theme split, which keys
   off the reader's OS and can put a light plate on a dark page. Judge it with the theme toggle
   in `comparison.html`.
2. **The animation plays once.** A reader who scrolls past inside 8 s sees a still — which is why
   the resting frame, not the motion, is treated as the deliverable.
3. **SVG-as-image means no scripts, ever.** Every future change has to stay expressible in
   declarative CSS. That is a real constraint on whoever edits it next.
4. **The wordmark is live text in a system mono face**, so its exact metrics vary slightly by
   platform. It stays centred, and keeping it as text keeps it selectable and accessible;
   converting it to paths would fix the metrics and cost both.

**If the operator prefers the ASCII mascot anyway**, B is production-ready at 12,322 bytes and is
a one-line swap in the README — the objection to it is aesthetic and resolution-based, not
technical.

## Landing gate — CLOSED REJECTED 2026-07-29. Redesign required.

> **The operator reviewed all three prototypes and rejected them.** The gate did its job — nothing
> reached the README. Do **not** run `banner-apply-header.sh` on A, B or B2: what failed is the
> concept, not the execution and not the medium choice.

### The four rejections — all binding on the redesign

| # | Rejection (operator's words) | What it invalidates |
|---|---|---|
| **R1** | *"the handoff is only one part of our entire claude-infrastructure, so our heading shouldn't be an infographic on that"* | **The core idea.** Starburst-mitosis → pulse → retirement *is* `self-open → two-way → self-close` — one subsystem. A header stands for the WHOLE system. Kills § "The one strong idea" outright. |
| **R2** | *"the animations need to supplement the always showing title, title can't only show at the end"* | **The dramaturgy.** All three are narratives that RESOLVE onto the wordmark — the SVG's own `<desc>` reads "…leaving one mark at rest above the words claude-infrastructure". The title must be legible at **t=0 and every t**; motion supplements it, never delivers it. |
| **R3** | *"Video needs to be a loop"* | **The timeline.** Must loop seamlessly and indefinitely — no one-shot 8 s narrative, no visible restart seam. Periodic/ambient motion is what loops cleanly, which is also what R2 wants. |
| **R4** | *"the Claude Code orange mascot character"* | **The mark.** This means the pixel-art creature Claude Code renders at session start, **not** the radiating asterisk `✻ ✽ ✳`. § "Why the starburst is the right mascot here" is superseded — well-argued, and wrong about what was wanted. |

**Do NOT re-derive these — measured, still binding:**

- § "Inherited constraints" in full: GitHub strips `<video>`, so the header is an image; animated
  SVG runs inside `<img>` (declarative only, no scripts); `<picture>` follows the reader's OS, not
  GitHub's theme toggle.
- § "On 1080p60" — honored as 1920 px wide at 60 fps, authored 1920×600, displayed `width="900"`.
  A literal 16:9 stands 506 px tall and swallows the fold. Vector is resolution-*independent*, so
  1080p is a floor, not a ceiling.
- The § Comparison byte table: every raster encoding of an 8 s composition is **1.2×–45× over** the
  1 MB budget (WebP 1920w@60 = 2,229,294 B; GIF cannot express 60 fps at all — integer-centisecond
  frame delays allow only 50 or 100). **Vector is the only medium that fits.** Do not re-benchmark raster.
- `scripts/banner-shots.sh` — the SVG-as-image screenshot harness + its one-animation-per-element
  lint. Verify every candidate through it; it is the only mode matching GitHub.
- `scripts/banner-apply-header.sh` — the staged one-command header edit. Still the apply path.
- The restraint rules and the `prefers-reduced-motion` obligation.

**The problem restated.** A looping, always-titled header whose motion is *ambient* rather than
*narrative*, carrying the Claude Code creature, standing for the whole of claude-infrastructure —
not one subsystem. The title is the constant; the mascot animates around it.

**Weight was never the constraint.** The rejected prototypes were 9–12 KB against a 1 MB budget —
0.9 %. Do not let byte-thrift shape the redesign; spend on the idea.

<details><summary>Superseded — the original landing gate (kept: it explains why nothing was applied)</summary>

The winner goes into the README header **only after the operator has seen the comparison**. That
gate is unmet by design, so this track has landed everything *except* the README edit:
`assets/banner/`, `scripts/banner-shots.sh`, and this doc. The README body, the hero recording and
the demo GIFs are untouched.

The header edit itself is staged as a single command, not applied — see
`scripts/banner-apply-header.sh`. It `git mv`s the chosen prototype to `assets/banner/hero.svg`,
so after it runs the path captions in `comparison.html` name files that have moved. That is
intended: the page is a point-in-time record of the bake-off, and it still *renders* correctly
because the prototypes are inlined rather than linked.

</details>

## v2 — nine candidates, awaiting the operator's comparison

**Open the page:** `assets/banner/v2/comparison.html`. Nine banners, each shown animating and
frozen. The README header is **untouched**; `banner-apply-header.sh` stays unrun.

The operator's ruling on the redesign was **build all three subjects, and variants of each** — not
pick one. So the subject question was still answered first, it just resolved to "all of them".

### The subjects, and why these three

Drawn on the question the README asks of itself in its third paragraph — *how do you run many at
once, safely, unattended?* Three words, three different claims a header could make:

| | Subject | The claim | Variants |
|---|---|---|---|
| **S1** | The world it lives in — *safely* | `~/.claude` stopped being machine state and became a place that is deployed | `s1a-horizon` · `s1b-close` · `s1c-scene` |
| **S2** | The fleet — *many* | many sessions at once on one machine, unable to collide | `s2a-lanes` · `s2b-depth` · `s2c-row` |
| **S3** | The night shift — *unattended* | it runs while you sleep, and pages you only for a decision | `s3a-starfield` · `s3b-tree` · `s3c-longwatch` |

**In S2, nothing joins the creatures.** A thread between two of them would rebuild the handoff
infographic R1 rejected. Same ground, separate lanes, no contact — the absence *is* the argument.

**Nothing is invented.** The creature is the shipped 11×8 grid in `#D77757`; the motion is its
shipped idle pose table (`default · look-left · look-right · arms-up`); the landscape and the night
sky are the shipped session-start scenes. R3's seamless loop therefore comes from the source
material — an idle cycle loops by nature — rather than from a contrivance.

**No tagline.** "Sessions run each other" is one of five properties, so as banner copy it is an R1
subsystem claim, and the h1 immediately below says it better (restraint rule 4).

### Two harness defects found on the way, both of which made renders LIE

Worth more than the banners, because every future candidate is judged through this harness.

1. **`banner-shots.sh` silently cropped anything taller than ~614 px.** A headless window yields a
   viewport *shorter* than itself (`viewport_h = max(window_h, ~375) − 87` on Chromium 141/macOS),
   so a window sized to the image left the bottom outside it, padded with page background. On
   GitHub dark that padding is the same colour as the plate, so a truncated render looked like a
   banner with generous bottom margin. A 1920×780 sheet lost everything below y=613. The inset is
   now **measured per run** — a hard-coded 87 is one machine's constant, and a number that is wrong
   without looking wrong is this bug's whole failure mode — then asserted and cropped back off.
   RED-proofed by forcing the inset to 0. Note the 640 px asset still passes at inset 0, because its
   request falls under the minimum-window clamp: **short banners were accidentally fine, which is
   why three prototypes (all 520 px) never surfaced it.**
2. **`--lint` now rejects authored `animation-delay`.** The freeze seeks a timestamp by overriding
   delay on `*`, so an authored delay is silently discarded: a fleet staggered by per-element delays
   would **screenshot in lockstep**, a far more convincing lie than an obviously broken frame. Phase
   now lives in the **keyframe percentages** (`hold_cycle` rotates events inside the period), which
   survives the freeze exactly. Same failure class as the two-animation case, same remedy.

### What the checks caught that reviewing by eye did not

- **`s2b` placed three creatures and rendered two** — the far one overlapped both its neighbour and
  the wordmark's last glyph. Only visible once creatures were labelled *individually*: a union
  bounding box cannot see it, and on a fleet it is wrong in both directions (creatures either side
  of the title give a union that spans it, failing a clear layout).
- **`s3c` cleared the title by 14 px at rest and collided by 8 px with its arms up** — a collision
  present for half a second in nineteen. Checking `t=0` only would have shipped it.
- **The night tree sat behind "ture" in `infrastructure`**, reading as smudges on the type.
  `banner-collide` watches the *creature*, so static scenery never tripped it. Scenery now reserves
  against the title box and the **build refuses to emit**. Dim is not harmless: texture behind a
  title degrades exactly the legibility R2 exists to protect.

### Decisions taken by measurement, not taste

- **Legibility floor is 12 px per grid cell.** At 8 px the eyes are specks and the legs merge
  (`assets/banner/clawd-reference.svg` is the ramp). This bounds how many creatures a composition
  can hold.
- **`arms-up` rises 3 cells.** The source's own rise is "one row up" in a two-row creature, which
  does not map. Measured −2/−3/−4 on the 8-row grid: −2 reads as a hat brim, −4 as antennae.
- **Compositions centre themselves on the resting silhouette.** Absolute y values left every variant
  in one band with a third of the plate empty — designed versus merely placed. Reserving the arms-up
  rise inside the band was worse: invisible headroom tilted every frame to hold room for a pose that
  shows for half a second. Arms-up clearance is the render-time check's job instead.
- **Reduced motion freezes the creature as itself.** Proven, not claimed: five variants are
  **pixel-identical** frozen versus at rest; the night three differ only in star pixels, none
  touching the creature. (An earlier sweep put `opacity: .5` on `.eye`/`.arm` along with the stars —
  a degraded fallback wearing the same geometry, which is what "same artwork" forbids.)
- **Frozen stills are near-lossless WebP** — 4.5 KB against 70 KB for PNG. Plain lossy WebP seams
  flat regions and these frames are mostly one flat plate.

### Tooling added

| File | What it is |
|---|---|
| `scripts/clawd-sprite.py` | the creature as vector geometry, **derived** from the literal grid — the parts are declared separately (an animatable arm cannot be a run inside one merged path) and their union is then asserted against the grid, so a one-pixel drift fails the build |
| `scripts/banner-build.py` | composes all nine, plus `kit` (the mechanism proof, kept buildable so the committed artifact is never a file with no generator) |
| `scripts/banner-collide.py` | reads the render back: per-creature boxes versus the title box, and asserts title ink **exists** in every frame |
| `scripts/banner-compare.py` | the comparison page — every candidate **linked** as `<img src="…svg">`, never inlined, so the page cannot flatter its subjects by granting capabilities the README withholds |

### Still open

- **The operator's pick.** Nine candidates, one gate, unchanged: nothing reaches the README until
  the comparison has been seen.
- Composition notes not acted on, being taste rather than defect: `s2a`'s even spacing reads
  slightly mechanical; `s1c` is the busiest of the nine and the least restrained.

## Log

- **2026-07-29 (v2)** — subject validated with the operator BEFORE any SVG was written, which is the
  check whose absence sank v1. Ruling: build all three subjects and variants of each. Nine
  candidates shipped to `assets/banner/v2/`, gate still closed. **Learnings worth keeping beyond
  this track:**
  - **A verification harness can fail in a way that looks like success.** Two separate defects here
    produced renders that were *plausibly wrong* rather than obviously broken: a silent bottom crop
    that read as bottom margin because the padding matched the plate colour, and an
    `animation-delay` override that would have screenshotted a staggered population in lockstep.
    Both are now refused loudly. The general shape: when a tool's failure mode is a *believable*
    artifact, the tool needs an assertion, not a convention.
  - **Union bounding boxes cannot check a population.** Labelling the creatures individually was
    what surfaced three-placed-two-rendered; a union is wrong in both directions once there is more
    than one subject in frame.
  - **Check every timestamp, not `t=0`.** The one collision that mattered appeared for half a second
    in nineteen, on the pose that only fires once per cycle.
  - **A guard only sees what it was pointed at.** The collision check watched the creature, so
    static scenery walked straight behind the title. Extending it to scenery was a two-line
    reservation and caught the defect immediately.
  - **Derive art from its source and assert the derivation.** The sprite's parts are declared
    separately for animation, then their union is checked against the literal grid — pixel art is
    exactly where an off-by-one survives review.
- **2026-07-29** — operator reviewed the three prototypes and **REJECTED all of them**. Four
  binding rejections (R1 whole-system not handoff-infographic · R2 title always visible, motion
  supplements it · R3 must loop · R4 the Claude Code pixel-art creature, not the asterisk mark).
  The landing gate closed REJECTED — it worked exactly as designed: nothing reached the README.
  **Learning worth keeping:** the bake-off compared *mediums* rigorously and never tested the
  *concept* with the operator. Three prototypes of one idea is one idea, measured three ways —
  the cheapest possible check ("is a handoff loop the right subject for a header at all?") was
  never run, and it is the one that failed. Validate the SUBJECT before prototyping the MEDIUM.
- **2026-07-29** — track opened. Constraints inherited; reference SVG recovered from `a85e87e4^`;
  design idea fixed (starburst mitosis → pulse → retirement); tooling surveyed.
- **2026-07-29** — three prototypes built, compared and measured; recommendation = A. Two
  findings worth keeping beyond this track:
  - A frozen reference frame is only exact while every element carries **one** animation. A
    two-animation element had its idle value painted into every narrative frame, and a *control*
    render is what caught it — the frames looked plausible. `scripts/banner-shots.sh --lint` now
    fails on that shape, RED-proofed against a reconstruction of the pre-fix artifact.
  - `xml:space="preserve"` did **not** hold leading spaces for a character grid reached through
    `<use>`; every row left-aligned and the art sheared into a wedge. No-break spaces are not
    whitespace to collapse and carry the same advance in a monospace face, so they pin the grid
    regardless of how a renderer treats `xml:space`.
  - Chromium's `--virtual-time-budget` does **not** drive the animation clock of an SVG loaded as
    an image — every timestamp rendered identically. It was removed rather than left in place as
    a verification mode that cannot fail.

---

## v5 — the landscape line (2026-07-29, session 2). SETTLED FINDINGS — do not re-derive.

The mascot-free detour was MY misread of the operator and is void: **clawd is a hard requirement**
(R4 stands). Everything below is measured on disk with `scripts/banner-shots.sh`.

**S1 · Loop length is effectively free — use it.** An animated SVG is declarative CSS, so a
4-minute loop costs the same bytes as a 32-second one. Master is now **P=240 s** (240 = 2⁴·3·5).
**The only hard rule: every sub-period must divide P exactly**, or the composite never returns to
its start. Valid: 0.5 / 2 / 4 / 8 / 10 / 30 / 60 / 80 / 120. This is what makes **rare items**
possible — an event visible 4 s once per loop is a **1.7 % duty cycle**.

**S2 · One shared master period, phase via negative `animation-delay` — never per-element
durations.** With mixed durations the composite only repeats at their LCM and FAILS a t=0 vs t=P
frame-hash test. Verified both ways: mixed durations → `SEAM ✗`; shared period → byte-identical.

**S3 · `prefers-color-scheme` DOES work inside SVG-as-image.** Measured with an inverted probe
(default white, dark only via the query; rendered black on a dark OS). So **one self-theming file
— no `<picture>`, no second asset.** Caveat unchanged: it follows the reader's **OS**, not GitHub's
toggle, so both looks must be legible rather than assumed to match.

**S4 · The reference is CLOUDS over a flat ground, not hills.** The welcome screen's dithered
blocks float in the sky; clawd stands on a flat dotted rule. Uniform-width bars read as a city
skyline — build stepped mounds, wider than tall.

**S5 · The sky dotted rule has no reason to exist.** In the terminal it is the header divider under
"Welcome to Claude Code v2.1.45" — UI chrome. In a banner whose wordmark sits *inside* the scene it
divides nothing. **Removed.** The ground rule stays: it is the surface clawd stands on.

**S6 · Ground the character by computation.** One `GROUND` constant; feet = `GROUND − 160·scale`.
Verified by pixel-probing a render: lowest clawd pixel at SVG y=505.6 vs ground 506 → **−0.4 px**.

**S7 · Stars need a text keep-out box.** They landed on the wordmark. Keep-out `(430,120)–(1490,262)`
plus a 30 px margin, enforced at generation. Depth via three tiers (size + opacity + twinkle rate
60 s / 30 s / 10 s), not one uniform field.

**S8 · One animation per element — nest groups.** `banner-shots.sh`'s deterministic freeze is exact
only while no element carries a comma-list of animations. Structure clawd as nested single-animation
groups (`rSpin > hop > {ears, look > blink, legA, legB}`).

**S9 · Tamagotchi, not a bob.** Constant life: 0.5 s walk stride · 4 s blink · 8 s look-around ·
4 s hop · 2 s ear-wiggle. Plus **rare emotes**: sleep w/ Zzz (240 s), cheer w/ arms-up (120 s),
turn-around (80 s). And rare world events: shooting star (240 s), a visitor peeking from behind a
rock (240 s), drifting balloon (120 s). Verified alive: 12 frames sampled 0→31 s were 12 distinct
renders, while t=0 vs t=P stayed byte-identical.

**Verification commands (use these, don't invent):**
```bash
scripts/banner-verify.sh assets/banner/<f>.svg     # lint · seam · aliveness · themes · still
scripts/banner-verify.sh --self-test               # proves the gate's own guards can fail
```

> **SUPERSEDED — do not compare PNG file hashes.** The original instruction here was
> `--times 0,240` then "compare the two PNG hashes — MUST be identical". **Chromium's PNG encoder is
> not deterministic in this harness**: the same asset frozen at the same timestamp renders to two
> different FILES (measured 2026-07-29: `ee6b3378…` vs `55fab65e…`). So that comparison has a
> **false-FAILURE mode — it can go red on a pixel-perfect render.** Its PASSES were always sound,
> though: bytes-identical trivially implies pixels-identical, so the check could only ever err red,
> never green (see § S15 for the correction to an earlier over-claim here). `banner-verify.sh`
> decodes to raw RGBA and hashes the PIXELS, which is what the seam claim is actually about —
> corroborated independently by `magick compare -metric AE` reporting 0 differing pixels. The
> missing-file guard noted originally still stands and is now self-tested.

**Still open — the operator's standing ask:** a from-the-ground-up *"Opus 5 design-quality
show-off"* pass. `v5a-long-walk.svg` is the working reference implementation of every constraint
above, not the final artwork. Beauty is the remaining work; the constraints are done.

> **CLOSED by v6 below** (2026-07-29, session 3). The four v6 variants are the show-off pass. S1–S9
> all still stand and are now enforced by the generator rather than by hand-typing.

---

## v6 — the show-off pass (2026-07-29, session 3). AWAITING OPERATOR PICK.

Four art directions on the settled v5 constraint set, generated by `tools/banner/gen.py`. **The
README edit is still not applied** — `banner-apply-header.sh` remains unrun; picking a winner is the
operator's call.

**Review here:** `assets/banner/comparison-v6.html` — one self-contained file, 706 KB, 4 live
animated SVGs + 15 stills all base64-inlined, zero external references (asserted at build time).
Both themes are shown as stills because a live SVG can only ever follow the *viewer's* OS.

| Variant | Character | Bytes |
|---|---|---|
| `v6a-long-night` | Graded night sky, masked crescent, three lit-edge cloud bands. The most straightforwardly pretty. | 77 KB |
| `v6b-two-sessions` | Same night; once per loop a **second session** walks in from the right, both throw their arms up, the newcomer carries on. **The one that answers R1 directly** — the subtitle stops being a caption and becomes what the picture shows. | 73 KB |
| `v6c-dusk-line` | Warm horizon under a cold upper sky, clouds catching last light, low glowing moon. Most atmospheric, least restrained. | 68 KB |
| `v6d-terminal-field` | Cool phosphor cast, hairline under the wordmark, quietest motion. **Most restrained** — likely closest to the operator's stated taste (`feedback-operator-taste-restraint-over-expression`). | 69 KB |

All four: `scripts/banner-verify.sh` **5/5** — lint · `t=0` == `t=240` byte-identical · 12/12 distinct
frames · dark/light both rendered *and different* · reduced-motion still.

### S10 · Three harness checks were reporting success while checking nothing

Fixed before any design work, because the design could not be judged otherwise.

- **`--bg light` never applied `prefers-color-scheme`.** It only paints the page *behind* the image,
  and every banner has a full-bleed background plate that hides the page completely — so `--bg light`
  rendered **byte-identically** to `--bg dark`. **v5a's light theme had therefore never once been
  looked at**, and it is inverted: dark dithered clouds against a white sky. New
  **`--scheme dark|light|none`** drives the media query itself (measured on Chromium 141:
  `preferredColorScheme` `0`=dark, `1`=light, `2`=neither-matches; **unset defaults to dark**). The
  scheme is part of the output filename now, so a light render cannot silently overwrite a dark one.
- **`--lint` false-failed every stepped or eased animation.** It tested the value for any `,`, but
  commas nested in a timing function do not separate animations: `animation: wA .5s steps(1,end)
  infinite` — v5a's own walk cycle — was reported as two animations. Since `steps()` is what stops
  pixel art interpolating into mush, the lint effectively banned the correct idiom. It also let the
  value class run past a closing quote, so an inline `style="animation-delay:-3s"` swallowed
  `font-family="ui-monospace,Menlo,monospace"` and picked up a comma from there. Now counts commas at
  **nesting depth 0** only, and stops the value at `;`, a brace, **or a quote**.
- **`banner-verify.sh`** is the new single acceptance gate. Its guards are the point: the naive seam
  check compares two empty strings when neither render exists and prints PASS. Every hash is asserted
  non-empty before comparison, the frame **count** is asserted alongside distinctness (1 of 12 frames
  would trivially be "all distinct"), and `--self-test` sabotages the inputs to prove each guard fires.

### S11 · Shape builders are chosen by aspect ratio, not by taste

Clouds took four attempts. Each failure is worth keeping because each looks plausible in the code:

| Attempt | What it produced |
|---|---|
| Coarse lobe envelope | Flat architectural **ledges** — a 40 px shape on a 12 px grid has only three levels |
| Concentric shrinking tiers | A centred **ziggurat** |
| Full-width slab + rectangular bumps | Stacked **concrete panels** — worsened by a lit row on *every* rect, which stripes them into masonry courses |
| **Per-column envelope of true circular arcs**, cell small relative to height (6+ levels), runs merged so the lit edge traces the crown | **A cloud** |

**Ground shapes need the opposite builder.** Slab+bumps on a wide low mound gives narrow tall lumps
on a flat base — a **city skyline**, the exact read S4 rules out. Concentric tiers, wrong for clouds,
are right here. Aspect ratio decides which applies: tall → slab+bumps, wide+short → concentric.

### S12 · On a scrolling layer, an x-position is not an exclusion

"Nothing behind the type" cannot be satisfied by placing scenery to the side: a cloud at **any** x
travels the full tile width and passes under the wordmark at some phase. **The only sound invariant
is a Y one**, and `gen.py` now asserts it over every rect emitted into a scrolling layer, failing the
build with a count and an example span. Sabotage-proved (raising a cloud band into the type fails;
clean tree passes). The margin is **+27 px**; it was +1.4 px before this was measured.

Two guards found broken *by* that exercise, both silent:
- the assertion was defined but **never called** — the patch anchor was single-quoted and a formatter
  had already converted it to double quotes, so the edit no-opped;
- the first sabotage run read `$?` **after a pipeline**, reporting the exit status of `tail`.

### S13 · Other measured details

- **The moon's mask bite circle must be LARGER than the disc.** Smaller, and the disc shows all the
  way around it as a thin ring — which presents as a stray sliver beside the crescent.
- **`animation:none` reverts to the UN-animated base value**, not to a mid-animation one. The
  reduced-motion still showed a blown-out moon halo that never appears in the animation; the
  breathing values are pinned at their mid-points inside that media query.
- **A `count` cap must come after every filter.** The star sampler truncated to `count` before the
  caller applied the keep-out, so the keep-out ate the difference: a requested 165 stars rendered
  as 62, with nothing reporting a problem.
- **`declare -A` is a syntax error on macOS bash 3.2**, and under `set -u` a script that reaches it
  dies mid-run rather than reporting a failed check.
- **Stills: WebP q96 @ 620 px** — 17 KB each, RMSE 0.0076 vs lossless, no visible banding in the sky
  gradient at 320% magnification. Took the comparison page 2.3 MB → 706 KB. `near-lossless=40` gives
  RMSE exactly 0 but 64 KB, i.e. no better than plain lossless.

### S14 · The freeze must SEEK phase, not destroy it — `--d` + `--fz`

Main's authored-`animation-delay` lint is correct about the mechanism: the freeze reached a
timestamp by setting `animation-delay` on `*`, which clobbers any authored delay, so a deliberately
staggered population **screenshots in lockstep** — a plausible-looking render that is wrong. But
phase-by-negative-delay is exactly what S2 mandates, so banning it bans the design.

**The seek is now additive.** The asset carries per-element phase in **`--d`**; the freeze supplies
the global seek in **`--fz`**; the delay is `calc(var(--d,0s) + var(--fz,0s))`. Custom properties
inherit into SVG children, so one rule on the root reaches everything, and an asset with no `--d`
is unaffected (fallback `0s`). Proved in SVG-as-image on Chromium 141 with three rects at
`--d` 0/−1/−2s on a 4 s `steps(4)` colour cycle: with `--fz` they stay one step apart and rotate
together; under the old blanket override **all three render the same colour**.

### S15 · Chromium's PNG encoder is NOT deterministic — compare pixels, never file bytes

Found because S14 made SEAM start failing while `magick compare -metric AE` reported **0 differing
pixels**. The same asset frozen at the same timestamp, rendered twice, produces two different
**files** (`ee6b3378…` vs `55fab65e…`). So the long-prescribed "compare the two PNG hashes" check
has a **false-FAILURE mode**: it can go red on a render that is pixel-perfect.

> **CORRECTION — the first draft of this section over-claimed, and the direction of the error is
> worth keeping.** It said "every pass it ever recorded was luck rather than proof". That is wrong.
> The observation was two *different* files with *zero* differing pixels, so bytes-differ does not
> imply pixels-differ — but **bytes-identical trivially implies pixels-identical**, since the same
> bytes decode to the same image. The old check could therefore only ever produce a false **RED**,
> never a false **GREEN**. Every seam PASS it recorded stands as sound proof; only its failures were
> untrustworthy. Hashing decoded pixels is still the right fix — it removes a flaky red — but it
> does not void the green history. (Raised by the lead session, who also could not reproduce the
> divergence in 5 consecutive renders; combined with the one observation here, the nondeterminism is
> **intermittent**, which is harder to debug than a reliable fault and is why the fix earns its
> place.)

`banner-verify.sh` decodes to raw RGBA and hashes the **pixels**. Its decode path is guarded too: a
corrupt-but-non-empty file must not return the md5 of an empty stream, or the emptiness guard
downstream ends up comparing two hashes of nothing — the same false-PASS shape in a new costume.

### S16 · The timeline ANCHORS AT LOAD — the opening seconds are the product

The panel's synthesis rests on this, so it was verified rather than accepted. **Confirmed:** an SVG
loaded as an image starts its CSS timeline when the image begins rendering, so every reader who
scrolls past the README sees **t=0**. A beat placed late in the loop is not rare, it is *unseen*.

Re-runnable: `scripts/banner-timeline-anchor.sh assets/banner/<f>.svg`.

**The first version of this test was wrong, and the failure mode generalises.** It rendered the
unfrozen asset twice, 25 s apart, compared them, found them different, and concluded "not
load-anchored". That is not decisive: a load-anchored timeline *also* yields two different renders,
because the screenshot fires at a slightly variable delay after load and this asset has a 0.5 s
stepped stride — 250 ms of jitter flips the legs. "Differs" cannot separate **jitter** from
**drift**, so the naive test produced a confident refutation on evidence equally consistent with
confirmation.

The decisive form measures *which phase* each render is at, by matching against frozen references:

| render | best match | RMSE |
| --- | --- | --- |
| raw, immediately | **t = 0** | 0.000 % |
| raw, 25 s later | **t = 0** | 0.189 % (jitter, not 25 s of drift) |
| control: frozen t=0 vs t=25 | — | differ, so 25 s of motion *is* detectable |

The 0.000 % is also an independent validation of the freeze itself: the frozen t=0 frame is
pixel-exact against a live render of the unmodified file.

**Rule this produces:** the first beat wants to be at **t≈2.5–4 s**, and anything after ~t=45 s is
decoration. `shoot` at t=228 s was never rare — it was invisible.

### S17 · CSS `@keyframes` DOES animate in Firefox-as-image — the showstopper is refuted

Mozilla bug 1190881 (`SVGDocumentWrapper::IsAnimated` only checks for SMIL, so a CSS-only
`VectorImage` never joins the refresh driver) would make this banner a **static image for every
Firefox reader**, and a Chromium-only harness would never notice. **Measured and refuted:** CSS
`@keyframes` inside an `<img>`-loaded SVG **advances over time in Firefox 144.0.2**. Do not
re-express anything in SMIL.

Re-runnable: `python3 scripts/banner-firefox-probe.py` (Marionette over a socket — no
playwright/puppeteer needed).

**Two obvious forms of this test give WRONG answers**, which is why the script exists:

| test | what it reports | why it is wrong |
| --- | --- | --- |
| one screenshot | "animates" | only proves the t=0 value is COMPOSITED, which Firefox does; says nothing about the clock ticking, which is the whole bug |
| two screenshots, two page loads | "static" | the timeline anchors at LOAD (§ S16), so both land at t≈0 and read identical |
| **two screenshots inside ONE document** | correct | straddles a hard flip; the only form that observes advancement |

Pixel-checked, not byte-checked (§ S15): `css A=srgba(255,0,0,1) B=srgba(0,0,255,1)`. SMIL runs as a
positive control in the same pass — had SMIL also read static, the harness would be broken rather
than the finding confirmed.

**The real hole this exposed is still open:** the whole verification harness is Chromium-only. S1 was
false, but nothing in the gate would have caught it if it had been true. This probe is one engine's
worth of coverage; WebKit is unprobed (playwright ships a build).

**Regenerate:** `python3 tools/banner/gen.py --out assets/banner` then
`python3 tools/banner/compare.py --stills <dir>`. Verify: `scripts/banner-verify.sh <svg>`
(and `scripts/banner-verify.sh --self-test` to check the checker).

**Reproducibility is part of the closing check.** `hash()` on a `str` is salted per process (PEP
456), so `random.Random(hash(cls))` made the generator silently non-reproducible while every
structural check still passed — those test properties of the output, and a differently-seeded ground
satisfies all of them. Seeds come from `seed_of()` (crc32); regenerate and diff against the committed
asset before believing the set is stable.

---

## v7 — the three ratified beats (2026-07-29, session 4). SETTLED — do not re-derive.

`BANNER_NARRATIVE_SPEC.md`'s recommended set is built: THE OVERLAP, THE REFUSAL, THE ASK. All four
variants pass `banner-verify.sh` **6/6**, the print lock re-proves at **0.000000 px over 480 stride
boundaries under the warp**, the generator stays byte-reproducible, and the header is still untouched
— `banner-apply-header.sh` remains unrun.

### S18 · The three beats are ONE mechanism: the world clock

All three speak the same sentence — the ground's scroll rate — so they are not three effects to be
hand-animated. One clock `w(t)` drives every ground-plane layer, and significance comes from a shared
scale rather than from novelty per beat, which is the answer to critique (a).

The warp **cannot** live in a layer's own keyframes: those run on sub-multiples of P, so a hold
written into the 20 s strip would fire twelve times a loop — a beacon of repetition, which is the
defect S16 names. It is a nested outer group instead (`wp96 > fprs > content`): two
single-animation elements per S8, the ambient scroll left byte-for-byte as it was, and the
modulation firing exactly once.

Consequence to know before touching it: **a warped layer needs a third content copy at −TILE.** The
warp offsets the layer beyond its own wrap, and just after a wrap the frame edge would otherwise show
a hard-edged gap of page background — which against a dark plate is very nearly invisible and would
therefore ship. That pad is what took the files 78 KB → 107 KB (10.7 % of the 1 MB budget).
`assert_warp_within_tile` bounds the offset to the one tile the pad buys.

**The sky is deliberately NOT warped.** The clouds keep drifting through THE ASK. The ground's rate is
the gauge the beats speak in, and a session blocked on a human does not stop the world — it stops its
own progress. A frozen sky would also read as the render having died.

### S19 · Two constraints the loop imposes, which the spec did not have

Both were derived, not tuned, and both bind any future edit.

1. **A looping world cannot hold or reverse for free.** Every scrolling layer must travel a whole
   number of its own wrap distances per master period or the loop seams. So a permanent world-time
   deficit would have to be a common multiple of *every* layer's period — and the slowest layer's
   period **is** the master period, so the only free deficit is the entire loop. Every stop and every
   rewind must therefore be **repaid inside the loop, at a rate strictly above nominal.**

   The catch-up is not an artifact to hide; it is forced, so each beat has to *mean* it. Both do: a
   returned turn costs you a step and you make it up, and a session unblocked works through what it
   held.

2. **The rate vocabulary is the integers.** The print lock says the ground advances exactly one
   leg-spacing per stride; under rate `r` it advances `r` leg-spacings, so the foot lands in an
   existing print only when `r` is whole. **There is no gentle catch-up.** A 6 s stop is payable as
   6 s at 2× or 3 s at 3×, and that is the entire menu. Do not soften a rate to taste — it silently
   unlocks the footprint the whole thesis rests on. `assert_print_lock` says so, naming the timestamp
   and the miss distance.

   A corollary worth stating because it looks like a bug: during a repayment stretch the ground
   outruns the stride, so the foot lands on every second (or third) print. That is the cost of the
   integer constraint, it is bounded to 1.5–3 s per loop, and it is visually distinct from THE
   OVERLAP, whose tell is a doubled print *density* at a normal ground rate rather than a fast ground
   at normal density.

### S20 · A beat can be entirely ABSENT while every check reports green

The committed v6b carried a live defect that nothing caught. Its peer keyframes placed interior stops
at **absolute second offsets** (`+14`, `−16`) carried over from a much longer window; on the 9 s peer
those resolved to `-0.83%` and `-1.67%`. **CSS drops a keyframe block with an invalid selector
whole**, so the peer never stopped beside the resident and `pCheer` never fired at all — in the one
candidate built to showcase exactly that beat.

Meanwhile: the file was well-formed, one animation rode each element, `t=0 == t=240`, 12/12 frames
were distinct, both schemes rendered and differed, and the reduced-motion still existed. **6/6 green
over a beat that does not happen.**

Two rules out of it:

- **Interior keyframes are FRACTIONS of the window, never second offsets** (`atf()`). A fraction
  cannot run off the end of a re-timed window; a second offset silently can.
- `assert_keyframe_pcts_sane` reads the **emitted stylesheet** and rejects any selector outside
  0–100 %. Its RED-proof replays the actual committed v6b out of git rather than a hand-written
  approximation, because an approximation of a defect can pass a check vacuously.

### S21 · What the acceptance gate structurally cannot see, and the two probes added for it

`banner-verify.sh` is necessary and not sufficient: **nothing in it can tell a working world clock
from an inert one.** S19 is the proof that green says little about whether a beat happens. So:

| Probe | What it decides |
|---|---|
| `scripts/banner-gate-redproof.py` | Sabotages every build-time gate and requires the **specific** gate to reject it, keyed on the message — not on a non-zero exit, which an unrelated earlier failure can counterfeit. **19/19.** |
| `scripts/banner-world-clock-probe.py` | Cross-correlates the near foreground band between frozen frames and reports how far the ground **actually** moved, against the model. Measured: `0 / −48 / +48 / +96 / 0 / 0 / +288 / +96` px, every one exact. |

Four things about those probes are worth keeping:

- **Prove BOTH halves of an assertion.** Firing on bad input says nothing about whether anything calls
  it. `assert_all_gates_wired` reads `build()`'s own source and refuses any `assert_*` that nothing
  invokes — the exact shape of the S12 defect, where a formatter had already turned the patch anchor's
  quotes around so the wiring edit no-opped and a green build hid it. A hand-maintained list of
  expected calls would be a third copy of the same fact and would rot the same way.
- **The print lock reads the numbers back out of the emitted stylesheet**, not out of the expression
  that generated them. Computing the check from the generator would only prove the function agrees
  with itself. `pctx()` exists for this: `pct()`'s 3 decimals quantise a t=13 s boundary to an 0.08 ms
  error, which is 0.008 px of drift — invisible, and still a lie when the claim is 0.000000 px.
- **A probe that cannot fail is worse than none** (the same reason `--virtual-time-budget` was
  removed). The world-clock probe returns **exit 1** against the pre-change asset recovered from git,
  where it reads a flat nominal 48 px/stride with no modulation anywhere. Read the exit status
  directly — `… | tail` reports *tail's* status, which is the S12 mistake in a new costume.
- **A threshold in the wrong unit is indistinguishable from a subject that cannot pass.** The probe's
  first cut demanded the runner-up beat the winner by 1.0 SAD and reported all eight intervals as FLAT
  PEAK while every measurement was already exact — on near-binary content a correct match scores ~0.0
  and its rivals ~0.7. Prominence is now measured against the correlation surface's own median, which
  has no unit to get wrong.

### S22 · A missing fill does not error, it picks a colour from outside the palette

THE REFUSAL's barrier rendered **solid black** on its first pass because its class had no fill rule
behind it. SVG's initial `fill` is black, so the shape renders confidently in a colour no theme chose
— and it would have been black-on-pale in the light scheme, which is worse. Nothing in the output
pipeline can catch that: well-formed, one animation per element, seam holds, frames differ, both
schemes "render". Only the eye catches it, and only if the crop includes it.

`assert_every_shape_is_themed` now walks the built tree. Two things it had to learn, both of which
made the first version useless rather than merely wrong:

- **`fill` inherits**, so the question is whether the shape *or any ancestor* supplies one. Checking
  each shape's own class alone flagged all ~400 stars, which correctly take their colour from
  `<g class="st sn tw0">`. A guard whose model of the format is wrong produces a wall of false
  positives, and the only cheap response to that is to delete it — so an over-strict guard ends up
  costing exactly what no guard costs, just later.
- **A filter can replace the shape.** The grain rect's chain starts at `feTurbulence` and never
  references `SourceGraphic`, so its own fill cannot reach the screen. It is exempt for that reason,
  checked against the filter's actual primitives. Adding a meaningless fill to quiet a checker would
  have been a lie written into the artifact.

### Verified this session, not recalled

```text
banner-verify.sh          6/6 × 4 variants  (wellformed · lint · seam · alive · themes · still)
banner-verify.sh --self-test                4/4 guards fire
banner-gate-redproof.py                     19/19 gates fire, for the right message
banner-world-clock-probe.py                 4/4 variants exact; exit 1 on the pre-change asset
print lock                                  0.000000 px over 480 stride boundaries, per variant
byte-reproducibility                        identical across two runs
bytes                                       98-107 KB (budget 1 MB)
both schemes                                all three beats read in dark AND light (inspected)
```

### Found and NOT applied — the operator's or spec owner's call

- **The ground's parallax hierarchy is inverted.** By y-band, near-to-far is `fgb` (nearest, 96 px/s),
  `tf1` (middle, **80 px/s**), `tf0` (farther, 96 px/s) — so the middle layer is the slowest of the
  three and the nearest is no faster than the far one, against `ground_detail`'s own stated intent
  that "near things must outrun far things by enough to read". The fix is one line each
  (`tf1s` → `P/16` = 120 px/s, `fgbs` → `P/12` at a shorter tile), and it is **deliberately not in
  this session's commits**: it changes the motion of all four candidates while an operator comparison
  is open, which is the spec owner's call and not a defect fix to slip in beside the beats.
- **The visitor beats (`peek`/`peer`/`rCheer`) are demoted to t≈48-57 s, not deleted.** The panel
  ruled co-presence semantically wrong — a session is never co-present with its peers — but that
  deletes v6b's whole identity, so it is surfaced rather than taken. One line in `RARE_EVENTS`
  reverses the demotion; removing them from `ALWAYS_EMITTED` and `art.events` completes the deletion.
- ~~**WebKit is still unprobed.**~~ **CLOSED 2026-08-09 — it ticks. All three engines are now
  measured.** Chromium always was; Firefox was covered by S17, landed by a sibling session while this
  work was in flight. S17 matters more to these beats than to anything before them: the world clock is
  expressed **entirely in CSS `@keyframes`**, with no SMIL anywhere, so "does a CSS-only VectorImage
  ever join the engine's refresh driver" is the difference between three beats and three static frames
  for that engine's entire readership. Any future beat added here inherits that dependency on all
  three, and `scripts/banner-firefox-probe.py` / `scripts/banner-webkit-probe.py` are what re-check it.
  See § S24 for what the WebKit answer cost to establish.

---

## S24 · The last engine answers yes — WebKit ticks (2026-08-09)

**RESULT: CSS `@keyframes` DOES advance in WebKit-as-image.** Every Safari and every iOS reader gets
the four beats, not a still. That closes the engine question outright: Chromium ✓, Firefox ✓
(S17), WebKit ✓, and the banner needs no SMIL re-expression.

```text
probe  shot A   shot B   uniform   verdict
css    RED      BLUE       100%    ANIMATES — clock ticks
smil   RED      BLUE       100%    ANIMATES — clock ticks     ← positive control
```

Measured on **macOS 15.6.1 (24G90), system WebKit build 20621**. The version is recorded because a
finding about an engine is only true of the build it was measured on — the same reason the published
p95 in `context-econ` had to be re-derived rather than quoted.

**The engine under test is the SYSTEM one, deliberately.** `~/Library/Caches/ms-playwright/webkit-2227`
exists and would have been the easy target, but it is a WebKit built by the Playwright project and no
reader has it. `tools/banner/webkit-probe.swift` binds **`WKWebView`** — the framework this macOS
ships and Safari loads — so the verdict is about the engine readers actually run. `safaridriver` was
the other candidate and was dropped: `--diagnose` hung past a 120 s bound, and enabling it is an
operator step (it needs authentication) for no gain over WKWebView.

**The shape is inherited from the Firefox probe, and it is not negotiable** — same question, so the
fixtures are **imported from `banner-firefox-probe.py`, not retyped**. A second copy of the fixture
would let the two engines' verdicts drift apart while still reading as comparable, which is the
"third copy of the same fact" this repo has already been bitten by (§ S21).

- A single screenshot cannot answer it: compositing the t=0 value proves the animation was *applied*,
  never that the clock *advances*.
- Two page loads cannot answer it: the timeline anchors at load (S16), so both land at t≈0 and a
  static engine produces the same pair as a ticking one.
- So: **one document, two snapshots inside its lifetime**, at 400 ms and 1600 ms, straddling a hard
  step flip at 1000 ms of a 2000 ms period — 400 ms of margin either side, so neither sample sits
  near a boundary where a frame either way would be defensible.

### Why "identical frames" needed three guards, not one

`ANIMATES` is only worth something because the probe was shown returning the other answer.
`--self-test` is **4/4**, each case keyed on its **own reason** rather than on a non-zero exit — an
unrelated earlier failure counterfeits that, the trap `banner-gate-redproof.py` already exists to
avoid:

| case | required | why it exists |
|---|---|---|
| `static-rect` | reads **STATIC**, not ANIMATES | **the one that matters.** Without it, `ANIMATES` is what the probe would say either way, and the live result is unfalsifiable — the recorded reason `--virtual-time-budget` was *deleted* rather than kept as a mode that always agreed |
| `off-palette` | refuses: `off-palette` | a frame uniformly some colour the fixture never authors is not the fixture, so its equality is not evidence |
| `half-drawn` | refuses: `not-uniform` | a half-drawn render compares equal to itself too, and would report STATIC for a healthy engine — a broken instrument whose answer is a *believable finding* rather than an obvious error |
| `absent-page` | harness `verdict != OK` | when the instrument does not run it must say so; a bare exit 0 from a tool that measured nothing reads as a result |

Three further things the build had to get right, each of which would have produced a *plausible*
wrong answer rather than a visible break:

- **Read the histogram, not one pixel.** A single-pixel sample cannot tell a fully painted frame from
  one painted only where the sample landed. The fixture is one flat rect, so ~uniformity is a fact
  worth asserting; both live frames read **100%**.
- **Classify by distance, never equality.** macOS colour-manages, so a round-tripped pixel need not be
  bit-exact. Red and blue stay separated by a vast margin, so nearest-of-palette with a ceiling is
  both tolerant and unambiguous.
- **The snapshot needs a window that is actually drawn.** A `WKWebView` that never reaches the screen
  snapshots blank — and a blank pair compares EQUAL, i.e. reports "static" for a healthy engine. The
  window is ordered front without activating; the uniformity guard is the backstop if it ever fails
  anyway.

**One Swift constraint, already recorded elsewhere in this repo and re-paid here:** the harness must be
**compiled** (`swiftc -O`), never `swift webkit-probe.swift` — the identical note at the head of
`tools/terminal-bench/window-film.swift`. It also cannot be written as top-level code closing over
`guard`-bound values: a class body cannot capture them, so the sample times are threaded through
`init` and held as properties.

### Verified this session, not recalled

```text
banner-webkit-probe.py                4/4 self-test guards fire, each for its own reason
banner-webkit-probe.py                css ANIMATES · smil ANIMATES (control) · 100% uniform
engine                                macOS 15.6.1 (24G90), system WebKit 20621
banner-storyboard.py (rescued)        10 beats · 55 frames, generated clean
```
