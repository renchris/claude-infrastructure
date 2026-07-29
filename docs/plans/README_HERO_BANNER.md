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

## Landing gate — OPEN, awaiting the operator

The winner goes into the README header **only after the operator has seen the comparison**. That
gate is unmet by design, so this track has landed everything *except* the README edit:
`assets/banner/`, `scripts/banner-shots.sh`, and this doc. The README body, the hero recording and
the demo GIFs are untouched.

The header edit itself is staged as a single command, not applied — see
`scripts/banner-apply-header.sh`. It `git mv`s the chosen prototype to `assets/banner/hero.svg`,
so after it runs the path captions in `comparison.html` name files that have moved. That is
intended: the page is a point-in-time record of the bake-off, and it still *renders* correctly
because the prototypes are inlined rather than linked.

## Log

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
