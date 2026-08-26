# P1 — CAPTURE

**Stage:** acquisition. Everything downstream describes *this frame*; if the frame is wrong, every
later stage is confidently wrong about a picture the browser never drew.

**Substrate:** `agents/A9-capture-fidelity.md` (all fidelity numbers), `agents/A7-deterministic-layer.md`
(CDP extraction costs, FLIP noise floor), `agents/A10-motion-interaction.md` (the WAAPI/rAF freeze
split), `agents/A11-integration.md` (CLI-not-MCP, `clamp_safe`), `bench/capture.py` (the existing
one-pass implementation this supersedes).

**One-sentence thesis.** Capture produces a small number of *archival masters* that no model ever
reads, plus a manifest that tells every later stage exactly which derived images are safe to hand to
`Read` and what each one costs — so the 2000-px client clamp is a computed field, never a surprise.

---

## 0. Contract

### 0.1 Invocation

```
design-capture <url|file> --out <dir>
                [--viewports 1440x900,768x1024,390x844 | --viewports auto]
                [--themes auto|light|dark|light,dark]
                [--dpr 2]
                [--states <name>=<js-file> ...]
                [--reduced-motion-arm]
                [--breakpoint-probe declared|bisect|off]
                [--budget-ms 45000]
```

Re-entrant sub-command, over an existing `--out` dir, minting one lossless crop from a stored master
without relaunching a browser:

```
design-capture crop --out <dir> --cell 1440x900.light --css-rect x,y,w,h [--label hero-cta]
```

### 0.2 Inputs

| Input | Type | Required | Notes |
|---|---|---|---|
| target | URL or `file://` path | yes | A `file://` target skips the HTTP-status assertion; everything else is identical. |
| `--out` | empty or non-existent dir | yes | Refuses a non-empty dir without `--force`. Artifacts are immutable once written. |
| `--viewports` | list, or `auto` | no (default `auto`) | `auto` derives the set from the page's own occupied `@media (width)` branches — §4. |
| `--themes` | `auto` \| explicit | no (default `auto`) | `auto` *measures* whether the page has a second theme rather than assuming — §4.3. |
| `--dpr` | 1 \| 2 \| 3 | no (default `2`) | Written into **both** `--force-device-scale-factor` and the context. Mismatch is exit 20. |
| `--states` | `name=path.js` | no | Each JS file runs after readiness and before capture; each produces its own cell (open menu, error state, empty table). Capture does not invent states. |

### 0.3 Outputs

Every path below is absolute and appears in `manifest.json`. Nothing else is written.

| Artifact | Class | Read by |
|---|---|---|
| `masters/<cell>.doc@Nx.png` | `read_class: "forbidden"` | nothing. Archival raster, crop source. |
| `read/<cell>.index.png` | `degraded` | judge stage, as a table of contents only |
| `read/<cell>.fNN@Nx.png` | `degraded` at 1440 CSS, `lossless` at ≤1000 CSS | judge stage — the default model-facing images |
| `crops/<cell>.<label>@Nx.png` | `lossless` (asserted) | judge stage, on demand, after a region is named |
| `facts/<cell>.domsnapshot.json` | — | deterministic stage (P2) and cross-check stage (P3) |
| `facts/<cell>.layout.json` | — | P2/P3; the CSS-px geometry every finding must be seconded against |
| `manifest.json` | — | **every** later stage; the join key for all of them |
| `env.json`, `spec.json` | — | replay + the "is this diff legal" gate |
| `logs/capture.jsonl` | — | humans, post-mortem |

`stdout` is exactly one line of JSON: `{"ok":true,"manifest":"<abs path>","cells":N,"read_images":M,"warnings":[…]}`.
That single line is the whole structured payload a `Bash` tool result needs to carry (A11 §3.1).

### 0.4 Failure modes — fail closed, always

`manifest.json` is written with `"ok": true` **only** if every assertion in §6.4 passed. A partial
run writes `"ok": false` with `failed_assertions` populated, and the agent contract is: *a manifest
with `ok:false` is not evidence and no later stage may run on it.*

| Exit | Name | Meaning | Recovery |
|---|---|---|---|
| 0 | OK | manifest `ok:true` | — |
| 1 | USAGE | bad args, non-empty `--out` without `--force` | fix the call |
| 10 | NAVIGATION | `goto` threw, timed out, or returned a non-2xx `final_url` status | is the dev server up? `manifest.target.http_status` records what came back |
| 11 | UNSTABLE | three capture attempts never produced two byte-identical rasters (§6.2) | page has un-frozen motion; re-run with `--states` pinning it, or accept and investigate `logs/capture.jsonl` which records the per-attempt shas |
| 12 | OVERSIZE | a `read_class:"lossless"` artifact failed its own `w≤2000 && h≤2000 && bytes≤3932160` assertion | a bug in this stage — lossless artifacts are sized by construction, so this is a hard stop, never a downgrade-and-continue |
| 20 | ENV_DRIFT | `--force-device-scale-factor` ≠ context `deviceScaleFactor`; or a written PNG carries an ICC chunk; or the Playwright/Chromium build differs from `env.json` on a `crop` re-entry | see §6.4 — each of these silently invalidates comparison, so each is fatal rather than a warning |

**Warnings are not failures, but they are structural and they travel.** `coverage.virtualized`,
`coverage.raf_libraries`, `coverage.breakpoints_source: "unavailable"` and
`assertions.fonts_fallback_detected` all leave `ok:true` and all appear in `warnings[]` on stdout —
because each one names a population this stage genuinely could not photograph, and a later stage
that reports "clean" over one of them is emitting a false green (§8).

---

## 1. Geometry: pick the DPR with arithmetic, then stop touching the DPR

### 1.1 The two functions every artifact is scored by

Both are implemented in this stage and both are written into the manifest per image. Neither is a
judgement call.

```python
CLAMP_W = CLAMP_H = 2000        # Claude Code Read tool, read out of the 2.1.183 bundle
CLAMP_BYTES = 3_932_160         # 3.75 MiB — targetRawSize in the same object
PATCH = 28                      # Claude's visual patch edge

def eff(raster_w, raster_h, dpr):
    """Model pixels delivered per CSS pixel, after the Read clamp."""
    s = min(CLAMP_W / raster_w, CLAMP_H / raster_h, 1.0)
    return round(s * dpr, 3)

def visual_tokens(raster_w, raster_h):
    """Cost after the clamp. Patch grid, per the vision docs — NOT bytes/750."""
    s = min(CLAMP_W / raster_w, CLAMP_H / raster_h, 1.0)
    w, h = round(raster_w * s), round(raster_h * s)
    return math.ceil(w / PATCH) * math.ceil(h / PATCH)
```

Sanity: `eff(2880,1800,2) = 1.389`, `eff(2000,1250,2) = 2.0`, `eff(1440,2500,1) = 0.8`,
`visual_tokens(2000,1250) = 72 × 45 = 3240`. These reproduce A9 §0c exactly, which is the point —
the manifest carries the same arithmetic the fidelity study ran, so no later stage re-derives it.

### 1.2 Why DPR is 2, arithmetically

Hold the layout viewport at the real breakpoint (1440 CSS wide, non-negotiable — the review is *of*
that breakpoint) and vary only DPR:

| DPR | raster | clamped to | `eff` | tokens | verdict |
|---|---|---|---|---|---|
| 1 | 1440×900 | — | **1.00** | 1716 | baseline |
| 1.5 | 2160×1350 | 2000×1250 | **1.389** | 3240 | ties DPR 2, at 44% fewer encode pixels |
| **2** | 2880×1800 | 2000×1250 | **1.389** | 3240 | **chosen** |
| 3 | 4320×2700 | 2000×1250 | 1.389 | 3240 | 2.25× the raster cost for identical delivered detail |

DPR 1.5 ties DPR 2 on delivered detail *for the clamped frame* — so the choice is not made here. It
is made by the case where the clamp does **not** fire, because that is the case the whole pipeline is
built around:

| CSS clip | DPR 1.5 raster → `eff` | DPR 2 raster → `eff` |
|---|---|---|
| 1000×625 (the lossless crop unit) | 1500×938 → **1.500** | 2000×1250 → **2.000** |
| 390×844 (phone, whole frame) | 585×1266 → **1.500** | 780×1688 → **2.000** |

**DPR 2 is chosen because it is the largest DPR at which a ≤1000×1000 CSS crop is still lossless
end-to-end, and DPR 3 buys nothing on desktop** (the clamp eats it) **while costing 2.25× the raster.**
The exception the manifest records rather than hides: on viewports narrow enough that DPR 3 stays
under the clamp on *both* axes, DPR 3 does pay — 390×844 @3 is 1170×2532, clamped to 924×2000, `eff`
**2.37**. This stage does not take it. Reason: mixing DPRs across cells makes the phone frames and the
desktop frames non-comparable for any cross-viewport measurement, and 2.00 already exceeds the
threshold at which Opus 5's measured blindness (0/2 on a 1 px misalignment and a 5/255 colour drift)
stops being about resolution. Sub-perceptual precision is P3's job, not more pixels' job.

### 1.3 The one flag that makes the number true

`--force-device-scale-factor=<dpr>` **and** context `deviceScaleFactor: <dpr>` must be equal, and
`screenshot({scale:'device'})` must be set. Each of the three is load-bearing for a different reason:

- Without the **flag**, headless snaps line boxes on whole CSS px while headed Retina snaps on half
  device px — measured 1.5 px of accumulated drift over four paragraphs, with byte-identical font
  metrics. That is a *geometric* corruption, and it is the single defect most likely to make the
  judge assert a real-sounding, falsifiable-sounding, wrong finding (A9 §5).
- Without **`scale:'device'`**, `deviceScaleFactor` is discarded at encode: a 720×400 viewport at DPR
  2 wrote a 720×400 PNG, byte-identical to the DPR-1 capture.
- Without them being **equal**, the compositor rasters at one scale and the emulation reports another,
  and `window.devicePixelRatio` reads `1` in both cases — so the mismatch is *not detectable from
  inside the page*. The only detector is `raster_w / css_w`, computed on the written file. That
  comparison is assertion A4 in §6.4 and it is exit 20, because there is no downstream stage that can
  notice.

---

## 2. Launch: exact flags, exact context, and one deliberate contradiction of A9

```js
const DPR = spec.dpr;                       // 2

const LAUNCH_ARGS = [
  `--force-device-scale-factor=${DPR}`,     // LOAD-BEARING. Closes headless/headed layout drift.
  '--hide-scrollbars',                      // 0 px no-op on macOS; ~15 px correctness fix on Linux/CI
  '--force-color-profile=srgb',             // pin, not a fix — measured inert on macOS today
  '--disable-lcd-text',                     // measured inert on macOS (CoreText grayscale AA)
  '--font-render-hinting=none',             // measured inert on macOS (FreeType-facing)
  '--disable-font-subpixel-positioning',
  '--run-all-compositor-stages-before-draw',
  '--disable-partial-raster',
  '--disable-skia-runtime-opts',            // pins Skia to one code path across CPU feature sets
  '--deterministic-mode',
];

const browser = await chromium.launch({
  channel: 'chromium',   // the real browser, NOT chromium_headless_shell (a different binary)
  headless: true,
  args: LAUNCH_ARGS,
});

const ctx = await browser.newContext({
  viewport: { width: cell.w, height: cell.h },
  deviceScaleFactor: DPR,              // MUST equal --force-device-scale-factor
  colorScheme: cell.theme,             // explicit, never implicit — implicit resolves to 'light'
  reducedMotion: 'no-preference',      // ← see 2.1; this is where we depart from A9
  forcedColors: 'none',
  timezoneId: 'UTC',
  locale: 'en-US',
  bypassCSP: false,                    // an injected style that CSP would block is not the real page
});

const SHOT = {
  scale: 'device',            // without this, deviceScaleFactor is silently discarded at encode
  animations: 'disabled',     // default is 'on'
  caret: 'hide',
  type: 'png',
};
```

Four of these are inert on macOS today (`--force-color-profile`, `--disable-lcd-text`,
`--font-render-hinting`, `--disable-font-subpixel-positioning` — all measured byte-identical with and
without). They stay because this stage's artifacts must be comparable to a future run on a Linux CI
box, and because a flag kept as a *pin* costs nothing while a flag discovered missing after a
Chromium default flip costs a whole corpus.

### 2.1 Departure from A9: `reducedMotion` is `no-preference`, not `reduce`

A9's canonical spec sets `reducedMotion: 'reduce'` and labels it "belt-and-braces with
`animations:'disabled'`". **This stage sets `no-preference` for the default arm, and I am flagging
that as a deliberate contradiction.**

The reason A9 gives is determinism, and A9's own measurement already discharges it without the flag:
three configurations with `animations:'disabled'` + `fonts.ready` + rAF converged on sha
`7b6dad0a1399`, byte-identical, across separate launches. So `reduce` buys no determinism this stage
does not already have.

What it *costs* is real and A9 did not have to pay it, because a hand-authored corpus page has no
`@media (prefers-reduced-motion: reduce)` branch. A shipped marketing page does: it commonly drops a
parallax layer, swaps an autoplaying hero video for a still, or hides an entire animated section.
Reviewing that branch and calling it "the design" reviews a page most users never see, and it *hides*
the motion-design defects the review exists to find. Under `reduce` this stage would produce a clean,
deterministic, byte-stable photograph of the wrong page.

`--reduced-motion-arm` captures the `reduce` branch as an **additional** cell
(`<viewport>.<theme>.reduce`), which is the correct framing: reduced-motion conformance is its own
question — *does the page honour the preference at all* — and it wants both sides, not one.

### 2.2 CDP session, opened once per cell

```js
const cdp = await ctx.newCDPSession(page);
await cdp.send('DOM.enable');
await cdp.send('CSS.enable');
await cdp.send('Animation.enable');
```

The fact-pack comes from **one** `DOMSnapshot.captureSnapshot` call, not from an in-page
`getComputedStyle` loop (32.7 ms vs 881 ms vs 5788 ms for the per-node CDP walk), and it is the only
route to closed shadow roots, pseudo-elements, cross-origin iframe subtrees, paint order, stacking
contexts and the compositor's blended background colour:

```js
const snap = await cdp.send('DOMSnapshot.captureSnapshot', {
  computedStyles: STYLE_PROPS,              // the 41-prop whitelist from bench/capture.py:29-72
  includePaintOrder: true,
  includeDOMRects: true,
  includeBlendedBackgroundColors: true,
  includeTextColorOpacities: true,
});
```

🚨 **Capture writes `blendedBackgroundColors` through verbatim and attaches a poison flag; it never
lets that field stand alone.** The field samples **one** colour per text run. On a gradient it
returned `rgb(30,58,138)` — the leftmost stop, 10.36:1 against white — where the text actually sits
at 1.22:1. A stage that adopts the scalar naively converts an honest `INDETERMINATE` into a confident
false PASS, and a pass routes nowhere while an abstention routes to a stage that can settle it. So
capture emits, per text run:

```json
{ "blended_bg": "rgb(30,58,138)",
  "backdrop_chain_has_varying": true,      // any ancestor with background-image / gradient
  "scalar_representative": false }
```

`scalar_representative: false` is capture's whole contribution to that argument. It is a fact about
the *backdrop chain* — computed from `background-image` on the resolved ancestor chain, which is in
the same snapshot — and it is not a judgement. P2 must abstain wherever it is `false`; P3 resolves
those by sampling the raster. Neither can do that if capture drops the flag.

---

## 3. Readiness ladder — nine steps, in this order, per cell

Each step exists because omitting it was measured to change the output.

```
R0  addInitScript: freeze Date.now / performance.now / Math.random to fixed values,
    and stamp window.__CAPTURE__ = {seed, t0}. Before ANY page script runs.
R1  goto(target, {waitUntil:'load'})           -> record http status + final_url
R2  await page.evaluate(() => document.fonts.ready)
R3  await page.evaluate(() => new Promise(requestAnimationFrame))
R4  SCROLL PRIME: y = 0 .. scrollHeight step floor(innerHeight*0.8), 120 ms settle each
R5  scrollTo(0,0), settle 400 ms
R6  await Promise.all([...document.images].map(i => i.complete ? 0 : i.decode().catch(()=>0)))
R7  COVERAGE PROBES (§3.2) — virtualisation, rAF libraries, silent font fallback, scrollbar px
R8  MOTION FREEZE (§3.3) — WAAPI seek to end + rAF clock freeze
R9  STABILITY GATE (§6.2) — capture twice, require identical sha256; up to 3 attempts
```

**R2 is necessary and not sufficient, and this is the trap.** A capture taken before `load` differed
from every later capture *even though* `document.fonts.status` already read `"loaded"` and
`document.fonts.check("34px 'Playfair Display'")` already returned `true` at that frame.
`fonts.ready` is not a paint gate. R9 is what actually closes it — and R9 subsumes R2 as a *detector*
while R2 remains the cheap way to converge fast.

**R4 exists because naive `fullPage:true` fired 1 of 8 `IntersectionObserver` reveals** — seven
sections photographed at `opacity:0` (47,991 B → 58,960 B once primed). It also covers
`loading="lazy"` images, whose fetch is triggered by proximity to the viewport. The 0.8 step overlap
is so a reveal threshold of `0.25` fires; a full-viewport step can straddle a threshold and skip it.

**R5's 400 ms is a settle for scroll-linked transforms**, not for network. Anything still fetching
after R6 is caught by R9 as instability rather than being waited on with an invented timeout — which
is the right polarity: an unbounded wait hides a slow page, a stability failure names it.

### 3.1 Fixed and sticky — two different problems, two different answers

| | `position: sticky` | `position: fixed` |
|---|---|---|
| Full-page behaviour (Playwright ≥1.60, `captureBeyondViewport`) | rendered **once**, at natural flow position (measured: y=0..56, *not* repeated per screenful) | rendered **once**, anchored to the scroll-0 viewport — so a footer badge lands at y≈560 of a 5120 px image, floating over section 0 |
| In the DOC master | correct as-is | **neutralised**: `style: '*{}'` injection converting `position:fixed` → `absolute`, so it lands in flow |
| In the viewport frames | live, correct | live, correct — the frame *is* the user's view |

The classic "sticky header repeated eight times" artifact does **not** occur on Playwright 1.60,
because `fullPage` no longer scroll-and-stitches. Do not carry that assumption forward from older
tooling, and do not write a de-duplication pass for a problem that no longer exists.

Neutralisation is done by selector-free rule injection so it needs no knowledge of the app's class
names:

```js
const NEUTRALISE_FIXED = `
  *:not(html):not(body) { }
  @supports (position: fixed) {
    [data-capture-fixed] { position: absolute !important; }
  }`;
// applied after tagging, in-page:
await page.evaluate(() => {
  for (const el of document.body.querySelectorAll('*'))
    if (getComputedStyle(el).position === 'fixed') el.setAttribute('data-capture-fixed', '');
});
```

The tag list is written to `facts/<cell>.layout.json` as `fixed_elements[]` with their live
`getBoundingClientRect()`, so a later stage can tell "this element floats over body copy" (a real
defect) from "this element was neutralised for the master" (an artifact of this stage).

### 3.2 Coverage probes — the three silent-false-green detectors

**(a) Virtualised / recycled DOM.** `captureBeyondViewport` renders the whole document in one pass at
the top scroll position, so a `react-window` / TanStack-Virtual table body renders empty below the
fold. reso-management-app is a dashboard and is the likely carrier. Detector, run at R7:

```js
const n0 = document.body.querySelectorAll('*').length;   // at scroll 0, post-prime
// (recorded during R4 at the bottom of the scroll pass)
const nBottom = /* node count sampled at max scroll */;
coverage.virtualized = Math.abs(nBottom - n0) / n0 > 0.05;
```

5% because ordinary lazy-image insertion and a couple of reveal wrappers move the count by ~1-2%;
a recycling list window moves it by 30-90%. On `true`, the DOC master is a composite of states that
never coexisted and every whole-page rhythm claim over it is void — the manifest says so and the
viewport frames (which *are* rendered at a real scroll offset) become the only valid evidence.

**(b) rAF-driven animation libraries.** `document.getAnimations()` returns CSS Animations, CSS
Transitions and Web Animations **only**. GSAP, react-spring, Lenis, and any Motion/Framer animation
off its WAAPI fast path are invisible to it, and `animations:'disabled'` therefore does not stop them.
Probe: `!!(window.gsap || window.Motion || window.__FRAMER_MOTION_DEVTOOLS__ || window.Lenis)`.
On `true`, record `coverage.raf_libraries: [...]` — a clean deterministic pass on a GSAP page is not
evidence of correctness, and this is the field that stops a later stage from claiming it is.

**(c) Silent font fallback.** `font-family` reads correctly while the box renders in the fallback, and
nothing but `CSS.getPlatformFontsForNode` detects it. Run it on ≤24 nodes — one representative per
distinct `(font-family, font-weight, font-size)` triple in the snapshot, which bounds the cost at
~52 ms — and record the resolved family per triple. Assertion A7 fires
`assertions.fonts_fallback_detected` when a resolved family is absent from the declared stack.

### 3.3 Motion freeze needs BOTH levers, and neither alone is complete

| Lever | Controls | Blind to |
|---|---|---|
| `animations:'disabled'` / `Animation.setPlaybackRate(0)` + `seekAnimations` | CSS transitions, CSS animations, Web Animations | rAF-driven JS |
| `page.clock.install()` + `clock.runFor(16)` | `Date`, `setTimeout`, `setInterval`, **`requestAnimationFrame`**, `requestIdleCallback`, `performance` | CSS animations/transitions, the document timeline |

A harness using one has a silent hole. This stage installs the clock at R0 (before any page script),
runs it forward in 16 ms steps through R1–R6 so timers and rAF callbacks that the page *needs* still
fire, then stops stepping at R8 — after which rAF is frozen and `animations:'disabled'` handles the
WAAPI half at screenshot time. Capture produces exactly **one frozen still per cell**; reconstructing
a timing curve across virtual frames is P5's job (motion), not this stage's.

---

## 4. The capture SET — three viewports, measured themes, and why not more

A **cell** is one `(viewport, theme, state)` triple. The set is the list of cells.

### 4.1 Viewports: derived from the page, floored at three

Hardcoding a viewport list restates a perishable fact — which breakpoints a given repo occupies —
inside a spec that has no way to learn it changed. `--viewports auto` reads them instead:

```js
const widths = new Set();
for (const sheet of document.styleSheets) {
  let rules; try { rules = sheet.cssRules; } catch { breakpointsSource = 'unavailable'; continue; }
  for (const r of rules) if (r instanceof CSSMediaRule)
    for (const m of r.conditionText.matchAll(/(?:min|max)-width:\s*([\d.]+)px/g))
      widths.add(+m[1]);
}
```

Each *occupied* branch gets one sample, placed **8 px above the next breakpoint** (so the sample is
unambiguously inside its branch and not on a boundary where `min-width` and `max-width` rules both
apply). The set is then capped and floored:

| | Value | Reason |
|---|---|---|
| **Floor** | 3 | Fewer than three cannot cover the three layout regimes every one of these apps actually ships: multi-column desktop, the single-column reflow, and the touch-target regime. Two viewports always merge two of them. |
| **Ceiling** | 5 | Above five, added viewports sample the *same* branch of most components; the marginal cell is a duplicate photograph at a different width. Tailwind's six default branches are never all occupied by one page — measured intent, and `breakpoints_declared` in the manifest is the receipt. |
| **Default (floor set)** | `1440×900`, `768×1024`, `390×844` | 1440 is the operator's own review width and the modal MacBook logical width. 768 sits exactly at Tailwind's `md`, the boundary where these apps' layouts actually branch. 390 is the iPhone 14/15 logical width **and** it is lossless at DPR 2 (780×1688, under every cap on both axes) — the one viewport where the model gets a true 2.00× whole-frame read. |

`--breakpoint-probe bisect` exists for the `unavailable` case (a CORS-blocked CDN stylesheet makes
`cssRules` throw `SecurityError`): binary-search width in [360, 1600] for layout changes, ~11 reloads.
It is opt-in because it costs 11× a capture and `unavailable` is rare for a self-hosted Next.js build.

### 4.2 States: named by the caller, never invented

Capture photographs the state it is given. `--states menu-open=./states/menu.js` runs the file after
R7 and before R8, producing cell `1440x900.light.menu-open`. This stage does **not** click things to
discover states — a capture stage that explores is a capture stage that photographs a page nobody
asked about and cannot tell you which one it got.

### 4.3 Themes: `auto` MEASURES, it does not assume

Both wrong answers here are expensive. Assuming one theme reviews half a dark-mode app and voids
every contrast finding on the other half. Assuming two doubles the set for the ~half of pages that
have no second theme, and hands the judge two identical images to reconcile.

`--themes auto` runs a three-step probe and records which step answered:

```
T1  capture DOC master at colorScheme:'light'                     -> sha_light
T2  capture DOC master at colorScheme:'dark'                      -> sha_dark
    sha_dark != sha_light  =>  themes_effective = [light, dark], theme_source = "media"
T3  else probe for a class/attribute theme switch:
      html.classList contains 'dark' | 'light'  OR  [data-theme] present on <html>
    if found: addInitScript setting it, re-capture              -> sha_attr
      sha_attr != sha_light => themes_effective=[light,dark], theme_source="attribute"
    else                    => themes_effective=[light],       theme_source="single"
```

T3 exists because `next-themes` (present in `reso-management-app`'s dependencies) writes a **class on
`<html>`**, and only follows `prefers-color-scheme` while `defaultTheme` is `system`. A pinned theme
makes T2 return an identical sha over an app that plainly has two themes — the exact
fail-safe-mimics-healthy shape, where the silent answer and the correct answer look the same. T2's
sha comparison is the discriminator and T3 is the recovery; `theme_source` in the manifest is how a
later stage knows which one it got. If T3 finds an attribute but the re-capture is *still* identical,
that is `theme_probe_inconclusive` in `warnings[]` — a page that carries a theme switch and does not
render one is itself a finding, and it belongs to P2, not here.

### 4.4 Set size, and the ≤20-image ceiling that is NOT capture's constraint

Floor set, single state, both themes = **3 × 2 = 6 cells**. Each cell yields 1 DOC master (never read)
+ 1 index (desktop cell only) + `ceil(scrollHeight / viewportHeight)` viewport frames. A 3000 px page
gives 4 desktop frames, 3 tablet, 8 phone — around **32 Read-safe images** for a single page in two
themes.

That is over the API's 20-image-block ceiling, and over it the per-image cap **tightens and oversized
images are rejected rather than downscaled** — a hard request failure, not a degradation. But the
ceiling is a property of a *request*, not of a *capture*, and putting it here would force capture to
throw away evidence for a batching reason. So capture writes everything and precomputes the grouping:

```json
"read_batches": [
  { "id": "b0", "intent": "desktop-light", "images": ["read/1440x900.light.index.png", "…f00…", "…f03…"],
    "count": 5, "visual_tokens": 15408 }
]
```

**18 images per batch, not 20.** The two spare blocks are reserved for the judge stage's own on-demand
crops and for P4's saliency second-image, both of which arrive *after* batching and would otherwise
push a batch over the cliff. Batch *selection* — which batches to actually send — belongs to the
router; capture only guarantees that no batch it names can fail on size.

---

## 5. Full-page vs viewport: the answer is BOTH, and they answer different questions

The framing "full-page **or** viewport" has no correct answer because the two are not competing
renderings of one thing. They are renderings of two different things, and each is blind where the
other sees.

| | **DOC master** (`fullPage:true`, `captureBeyondViewport`) | **Viewport frames** (`clip` at a real scroll offset) |
|---|---|---|
| Chrome | fixed neutralised to `absolute`, sticky at natural flow position | fixed and sticky **live**, exactly as the user meets them |
| Scroll state | one pass at scroll 0 | one frame per screenful, at the real offset |
| Answers | vertical rhythm across sections · type scale · grid alignment · spacing distribution · section-level hierarchy · token conformance | what the user actually sees · does the sticky header eat the `h1` · is the primary CTA below the fold · does the cookie bar cover the form · per-screen hierarchy |
| Cannot answer | occlusion by fixed chrome, fold position, anything about *a moment of use* | anything spanning more than one screenful |
| Read class | **forbidden** — archival only | the default model-facing image |

**The DOC master is never sent to a model.** At 1440×3000 CSS @2 it is 2880×6000 raster; the Read
ladder would resize it to 1152×2000 for an `eff` of **0.80** — worse than a plain DPR-1 viewport
shot — while also palette-quantising or JPEG-laddering it if it clears 3.75 MiB. It exists for two
other reasons, both of which need the full raster and neither of which needs a model:

1. **It is the crop source.** `design-capture crop --css-rect x,y,w,h` slices any ≤1000×1000 CSS
   window out of it losslessly, with no browser relaunch and no re-render, and therefore no risk that
   the crop and the original describe different frames.
2. **It is the diff subject.** P3's cross-check and any regression comparison run on the master, at
   full raster, where a 1 px border is still 2 device px.

`read/<cell>.index.png` is the master downscaled to a 2000-px long edge and marked `degraded` with
`eff: 0.80` in the manifest. It is a **table of contents** — "there are five sections, the third one
is a pricing grid" — and the manifest's `role: "index"` is what tells the judge stage not to make a
spacing claim on it.

### 5.1 Why frames stay whole at `eff` 1.389 instead of being split for `eff` 2.0

A 1440 CSS frame at DPR 2 is 2880 px wide and clamps to `eff` 1.389. Splitting it into two 720 CSS
half-frames would give 1440×1800 raster each — under the clamp, `eff` **2.000**, a 1.44× detail gain.
This stage does not do that, by default, and the reason is the baseline measurement rather than the
arithmetic:

> Opus 5 blind: judgement/semantic/gestalt defects **2/2**; sub-perceptual precision **0/2**; three
> real defects found that nobody injected; **zero** false positives.

A vertical cut through a 1440 px layout severs exactly the thing the model is measurably good at —
"the secondary action is styled as the primary one" is a claim about two elements that a split can
put in different images — to buy 1.44× more detail in the register where the model scored 0/2 and
where 1.44× does not move a 1 px misalignment or a 5/255 colour drift across the perceptual floor
anyway. **Spending a strength to buy a weakness it cannot use is the trade this stage refuses.**

Lossless detail is bought the other way, and the evidence for that is not marginal: crop-refinement
took ScreenSeekeR's model from 18.9% → 48.1% on ScreenSpot-Pro with **no model change**, a larger
delta than every model upgrade in that study combined. So crops are minted **after** a region has been
named — by P2's `INDETERMINATE` set, by P3's disagreement set, or by the judge asking a second
question about something it already saw — and never speculatively at capture time. A speculative
crop is a guess at what matters, and the whole architecture exists so that nothing guesses.

`--split-frames` exists as an escape hatch for a genuine whole-frame hairline question, and it writes
`role: "half"` with the seam CSS-x recorded, so a finding that lands within 24 px of a seam can be
refused by a later stage rather than believed.

---

## 6. Determinism: making two captures byte-comparable

### 6.1 What "comparable" means, scoped honestly

Byte equality is achievable and required **within one machine + one browser build**. Across machines
it is not achievable and is not the goal — two Chromium builds differed on 7.85% of pixels at max
channel delta **2**, pure LSB dither, zero of it perceptible.

| Comparison scope | Test | Threshold | Why this number |
|---|---|---|---|
| Same machine, same build, same manifest `env` | `sha256` equality | exact | This is what R9 asserts and what A9 measured across three independent launches (`ebaca0f07161` ×3). Anything less exact would hide a real instability. |
| Different machine or build, same `spec` | **NVIDIA FLIP** mean | **≤ 0.020** | Measured noise floor: the two pure-noise variants scored 0.0099 and 0.0130; the weakest *true* regression scored 0.0753. 0.020 sits above the worst noise and 3.8× below the weakest true positive — a **5.8× separation**. pixelmatch at its default inverts here (noise 1,889 vs weakest true positive 1,728, separation 0.91×) and must not be used as the gate. |
| Different capture tool | — | **refuse** | Chromium PNGs carry no colour chunk at all (`icc_profile: None`, verified across 8 captures); `screencapture`/`sips` output is tagged Display P3. A differ that honours tags converts one side and lights up on every saturated region. `env.json` mismatch on `capture_tool` is exit 20. |

### 6.2 The stability gate (R9)

```
for attempt in 0,1,2:
    settle(attempt)               # 0 ms, 250 ms, 1000 ms
    a = raster();  b = raster()
    if sha256(a) == sha256(b): accept a; break
    log {attempt, sha_a, sha_b, differing_px, max_channel_delta}
else: exit 11 UNSTABLE
```

Three attempts, escalating settle. The measured failure this closes — a pre-`load` webfont frame that
`document.fonts.status === "loaded"` had already declared safe — cleared on the first retry; three
gives margin for a slow network font without becoming an unbounded wait. Total added wall clock is
bounded at 1.25 s of settle plus six rasters (~240 ms at the measured 39 ms/raster). The per-attempt
shas and pixel deltas go to `logs/capture.jsonl` **even on success**, because "converged on attempt 2"
is itself information about a page.

### 6.3 What is frozen, and where

| Source of variance | Frozen by | Step |
|---|---|---|
| `Date.now`, `performance.now`, `Math.random` | `addInitScript` before any page script | R0 |
| `setTimeout` / `setInterval` / `requestAnimationFrame` | `page.clock.install()` | R0, frozen at R8 |
| CSS transitions / animations / WAAPI | `animations:'disabled'` | screenshot |
| Caret | `caret:'hide'` | screenshot |
| Timezone, locale | context options | launch |
| Scrollbar gutter | `--hide-scrollbars` + recorded `scrollbar_px` | launch + R7 |
| Host display scale | `--force-device-scale-factor` | launch |
| Encoder path | `scale:'device'`, `type:'png'`, never `jpeg`, never `quality` | screenshot |

### 6.4 The eight assertions — every one is fatal

Written into `manifest.assertions`; any `false` sets `ok:false` and the named exit code.

| | Assertion | Computed as | Exit |
|---|---|---|---|
| A1 | `dpr_flag_matches_context` | launch arg `--force-device-scale-factor` == context `deviceScaleFactor` | 20 |
| A2 | `scale_device_set` | screenshot options literally contain `scale:'device'` | 20 |
| A3 | `raster_matches_dpr` | `raster_w / css_w == dpr` on the written file (**the only detector** — `window.devicePixelRatio` reads 1 either way) | 20 |
| A4 | `no_icc_chunk` | the written PNG carries no `iCCP`/`sRGB`/`cHRM` chunk | 20 |
| A5 | `read_class_lossless_holds` | for every `lossless` artifact: `w≤2000 && h≤2000 && bytes≤3932160` | 12 |
| A6 | `stability_converged` | R9 accepted within 3 attempts | 11 |
| A7 | `fonts_fallback_detected` | *warning*, not fatal — resolved platform font absent from the declared stack | — |
| A8 | `http_ok` | `final_url` status in [200,300) (skipped for `file://`) | 10 |

A5 is stated as an assertion rather than as discipline deliberately: it is A9's R3 remedy, and a
discipline that lives in prose is a discipline the resizer wins.

---

## 7. On-disk layout and the manifest every later stage keys off

### 7.1 Layout

```
<out>/
  manifest.json                                  # the join key for every later stage
  spec.json                                      # frozen input spec; hashed into replay
  env.json                                       # binary/flag/host provenance; hashed into replay
  masters/
    1440x900.light.doc@2x.png                    # read_class: forbidden
    1440x900.dark.doc@2x.png
    390x844.light.doc@2x.png
  read/
    1440x900.light.index.png                     # degraded, eff 0.80 — table of contents
    1440x900.light.f00@2x.png                    # frame, scroll_y_css 0
    1440x900.light.f01@2x.png                    # frame, scroll_y_css 900
    390x844.light.f00@2x.png                     # lossless, eff 2.00
  crops/                                         # EMPTY at capture time; minted on demand
    1440x900.light.hero-cta@2x.png
  facts/
    1440x900.light.domsnapshot.json              # DOMSnapshot.captureSnapshot, verbatim + flags
    1440x900.light.layout.json                   # CSS-px geometry, fixed_elements, fonts, coverage
  logs/
    capture.jsonl
```

Filename grammar: `<w>x<h>.<theme>[.<state>].<role><nn>[@<dpr>x].<ext>`. It sorts correctly, and the
tuple `(viewport, theme, state, role, index)` parsed out of the name is exactly the join key later
stages need — so a stage that has lost the manifest can still attribute a file, and a stage that has
the manifest never has to parse a name.

### 7.2 `manifest.json`

```json
{
  "schema": "design-capture/1",
  "ok": true,
  "capture_id": "c-20260826T140311Z-a1b2c3d4",
  "created_utc": "2026-08-26T14:03:11Z",
  "target": {
    "kind": "url",
    "requested": "http://localhost:3000/dashboard",
    "final_url": "http://localhost:3000/dashboard",
    "http_status": 200,
    "title": "Dashboard — reso"
  },
  "spec": { "dpr": 2, "viewports_mode": "auto", "themes_mode": "auto", "reduced_motion_arm": false },
  "env": {
    "capture_tool": "design-capture/1",
    "playwright": "1.61.1",
    "channel": "chromium",
    "chromium_ua": "…Chrome/148.0.0.0…",
    "launch_args": ["--force-device-scale-factor=2", "--hide-scrollbars", "…"],
    "host_os": "darwin 24.6.0", "host_arch": "arm64", "host_backing_scale": 2,
    "env_sha256": "9f21…"
  },
  "breakpoints_declared": [640, 768, 1024, 1280, 1536],
  "breakpoints_source": "declared",
  "themes_effective": ["light", "dark"],
  "theme_source": "attribute",
  "assertions": {
    "dpr_flag_matches_context": true, "scale_device_set": true, "raster_matches_dpr": true,
    "no_icc_chunk": true, "read_class_lossless_holds": true, "stability_converged": true,
    "http_ok": true, "fonts_fallback_detected": false
  },
  "cells": [
    {
      "id": "1440x900.light",
      "viewport": { "w": 1440, "h": 900 }, "theme": "light", "state": null,
      "scroll_height_css": 3040,
      "scrollbar_px": 0,
      "coverage": {
        "virtualized": false,
        "raf_libraries": [],
        "content_visibility_auto_nodes": 0,
        "cross_origin_iframes": 1
      },
      "fonts_resolved": [
        { "declared": "Inter, ui-sans-serif, system-ui", "weight": "600", "size": "24px",
          "resolved": "Inter", "fallback": false }
      ],
      "fixed_elements": [
        { "path": "header.site-header", "rect_css": [0, 0, 1440, 64], "neutralised_in_master": true }
      ],
      "facts": {
        "domsnapshot": "facts/1440x900.light.domsnapshot.json",
        "layout": "facts/1440x900.light.layout.json",
        "node_count": 2871,
        "text_runs_with_varying_backdrop": 4
      },
      "images": [
        { "path": "masters/1440x900.light.doc@2x.png", "role": "doc-master",
          "css_rect": [0, 0, 1440, 3040], "raster": [2880, 6080], "dpr": 2,
          "bytes": 4113922, "sha256": "7b6d…", "read_class": "forbidden",
          "eff": 0.658, "visual_tokens": 2448, "scroll_y_css": 0, "chrome": "neutralized" },

        { "path": "read/1440x900.light.index.png", "role": "index",
          "css_rect": [0, 0, 1440, 3040], "raster": [947, 2000], "dpr": 0.658,
          "bytes": 612884, "sha256": "c5b3…", "read_class": "degraded",
          "eff": 0.658, "visual_tokens": 2448, "scroll_y_css": 0, "chrome": "neutralized" },

        { "path": "read/1440x900.light.f00@2x.png", "role": "frame",
          "css_rect": [0, 0, 1440, 900], "raster": [2880, 1800], "dpr": 2,
          "bytes": 1204331, "sha256": "9771…", "read_class": "degraded",
          "eff": 1.389, "visual_tokens": 3240, "scroll_y_css": 0, "chrome": "live" }
      ]
    }
  ],
  "read_batches": [
    { "id": "b0", "intent": "desktop-light", "count": 5, "visual_tokens": 15408,
      "images": ["read/1440x900.light.index.png", "read/1440x900.light.f00@2x.png", "…f03…"] }
  ],
  "warnings": [],
  "replay": {
    "argv": ["design-capture", "http://localhost:3000/dashboard", "--out", "…", "--dpr", "2"],
    "spec_sha256": "3ac1…",
    "env_sha256": "9f21…",
    "comparable_with": "same spec_sha256 AND same env_sha256 => byte equality; same spec_sha256 only => FLIP mean <= 0.020"
  }
}
```

**Three fields carry the whole contract with later stages.** `read_class` is a *prohibition*, not a
hint — `forbidden` means the file must never reach `Read`, and putting it in the manifest is what
stops each later stage from having to remember the clamp rule. `eff` is what lets a stage decide
whether a finding is *supportable by this image at all* — a 1 px claim on an `eff: 0.658` index is
inadmissible on its face. `replay.comparable_with` is the rule that makes a diff legal, stated as
data, so a stage comparing two captures does not have to reconstruct §6.1 from prose.

### 7.3 Budget

Per cell, from the measured components: navigation + readiness ~1.5–4 s (page-dependent, dominated by
R4's scroll prime at 120 ms × ceil(H/0.72·vh) steps) · `DOMSnapshot.captureSnapshot` **32.7 ms** ·
`Accessibility.getFullAXTree` **26.7 ms** · `getPlatformFontsForNode` ×24 ≈ **52 ms** · each raster
**~39 ms** · stability gate 2–6 rasters. Six cells land around **20–35 s** wall clock, single browser,
contexts recycled per cell. `--budget-ms` (default 45,000) caps the whole run and exits 11 rather than
truncating the set, because a half-set that looks complete is the failure this stage is built to avoid.

---

## 8. What this stage CANNOT do, and who owns each

| Cannot | Why not | Owner |
|---|---|---|
| Decide **which** crops matter | A speculative crop is a guess at what matters, and it would spend the crop-refinement lever (18.9% → 48.1%) on a random region. Capture exposes `crop` as a re-entrant operation and waits to be told. | P2 (`INDETERMINATE` set) + P3 (disagreement set) + the router |
| Resolve **contrast over a gradient** | It supplies both operands — the blended scalar *and* `scalar_representative:false`, *and* the master raster — but adjudicating them is a comparison between two descriptions, not an acquisition. | P3 cross-check (measured: 4.81:1 left third vs 1.57:1 right third) |
| Say whether the page **looks good** | Standing operator ruling, June 2026: *taste stays human, gates adjudicate correctness/coverage only.* | the human; the VLM stage is advisory triage, never a gate |
| Certify a **colour gamut** | Chromium rasterises to an untagged sRGB-numeric buffer and clips P3 into sRGB before the file exists — `color(display-p3 1 0 0)` and `#ff0000` both encode to `(255,0,0)`. A screenshot cannot testify about gamut and the honest answer is *not determinable from a screenshot; read the computed style.* | P2, from computed styles |
| Reconstruct a **motion timing curve** | It produces exactly one frozen still per cell. Phase sampling needs WAAPI seek for CSS motion and clock-stepping for rAF motion, plus screencast — a different acquisition with a different determinism model. | P5 motion |
| Photograph a **virtualised list's** off-screen rows | `captureBeyondViewport` renders one pass at scroll 0; recycled rows do not exist to be rendered. Detected and flagged (`coverage.virtualized`), never silently absent. | P2, over the viewport frames only |
| See **rAF-library motion** at all | `document.getAnimations()` covers WAAPI only; GSAP/react-spring/Lenis are invisible to it and to `animations:'disabled'`. Detected and flagged (`coverage.raf_libraries`). | P5 motion, via `page.clock` stepping |
| Produce an **annotated overlay** as a standing input | An overlay is a full second image (~3,240 tokens) on top of the clean one; the same findings as JSON coordinates cost ~840 tokens, ~4× cheaper. Overlays are minted on demand for one disputed region, by the stage that has the finding. | the judge stage, on demand |
| Guarantee any **geometric** finding | A vision model measuring pixels is a sampling instrument; `getBoundingClientRect()` is exact and free. Capture's contribution is to write the rects into `facts/*.layout.json` so the seconding is one lookup, not one round trip. | every downstream stage — **no geometric finding ships without a rect from `facts/`** |

---

## 9. UNVERIFIED — and the one probe that settles each

| | Claim in doubt | One probe |
|---|---|---|
| U1 | The Read clamp is **2000×2000 / 3,932,160 B**. Read out of the **2.1.183** bundle; `~/.claude-versions/current` points at 2.1.114, and a newer bundle may raise it toward the 2576-px high-res tier. Every `eff` and every batch size in this spec is downstream of this constant. | `strings ~/.claude-versions/current/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude \| grep -o 'maxWidth:[0-9]*'` — run at capture time and write the result into `env.json`, so the manifest carries the constant it was computed against instead of assuming it. |
| U2 | `page.clock.install()` at R0 does not deadlock `document.fonts.ready` at R2. Frozen virtual time could starve a font-loading path that waits on a timer, turning R2 into a hang. | Install the clock before `goto` on a page with a slow webfont; assert `fonts.ready` resolves within 5 s of **wall** clock while `clock.runFor(16)` steps. If it hangs, move clock install to R7 and accept rAF motion during readiness. |
| U3 | `content-visibility: auto` content renders in the DOC master under `captureBeyondViewport`. If it does not, tall pages using it silently photograph blank below the fold — a second, undetected instance of the virtualisation class. | Fixture page, 6000 px tall, sections at `content-visibility:auto`; capture the master and sample a pixel at y=4000. Non-background ⇒ renders. Add `content_visibility_auto_nodes` to the coverage gate either way. |
| U4 | The **3.75 MiB** byte cap actually fires on a real page. A9 never hit it (playwright.dev full-page @2 = 0.48 MiB), so the palette-quantisation rung of the ladder is read from the binary, not observed. It matters because the frames in §7.2 are ~1.2 MB and a hero-image marketing page could clear it. | Capture `reso-landing-app` `/` at 1440×900 @2 and read `bytes` on the frames. If any frame clears 3,932,160, `read_class` must become `degraded` with the *degradation mode* named, not just `eff`. |
| U5 | `--force-device-scale-factor` behaves the same at values other than 1 and 2, and on non-Retina/Linux hosts. Tested at 1 and 2, one machine, one page, Chromium 148. The mechanism (host backing scale reaching layout snapping) predicts it; that is a prediction. | Re-run the four-paragraph `getBoundingClientRect().top` probe at `--force-device-scale-factor=1.5` and on a Linux CI box; compare to the headed-Retina baseline `[102, 118, 136.5, 157.5]`. |
| U6 | The theme probe's T3 (attribute route) reaches `next-themes` as configured in `reso-management-app`. `next-themes` defaults to `attribute="class"`, but a project can set `attribute="data-theme"` or pin `defaultTheme`, and I read the dependency, not the `ThemeProvider` call site. | `grep -rn 'ThemeProvider' --include='*.tsx' reso-management-app/app` and read the `attribute` / `defaultTheme` props; if pinned, T3's setter must write that exact attribute or `theme_source` will report `single` over a two-theme app. |
| U7 | Chromium PNGs stay **untagged**. A future default flip to tagged output would make every cross-run diff illegal without any error. | Assertion A4 already probes this on every run — this row exists to record that A4 is a *tripwire for a predicted future change*, not a check on a present bug. |

---

## 10. The one-line summary for the stage that reads this

Capture hands you a `manifest.json`. Join on `cells[].id`. Read only what `read_class` permits, weight
every claim by `eff`, second every geometric finding against `facts/<cell>.layout.json`, and treat
`coverage.*` and `scalar_representative:false` as populations you were *not* shown — because a clean
report over one of those is the only failure mode in this pipeline that nobody downstream can catch.
