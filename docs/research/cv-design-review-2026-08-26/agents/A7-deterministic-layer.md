# A7 — The Deterministic Measurement Layer

**Date:** 2026-08-26 · **Axis:** everything computable exactly from the browser and from image pairs, so no model is ever asked to guess a number it could be told.

**Method:** every number marked *(measured)* was produced on this machine — Playwright 1.61.1 / Chromium, macOS 15.6 (Darwin 24.6.0), Node 22.21.1, viewport 1440×900 @ dpr 1, target `https://nextjs.org/`. Probe scripts were transient; all numbers are reproduced inline so nothing here depends on them surviving.

---

## 0. The headline, before the tables

Three findings reorder the brief's own framing.

1. **`DOMSnapshot.captureSnapshot` is the whole ballgame.** One CDP call returns post-layout geometry + whitelisted computed styles + paint order + stacking contexts + blended background colours for the *entire* tree, including closed shadow roots and cross-origin iframes. *(measured)* **32.7 ms** for 2,871 nodes × 32 style properties, against **5,788 ms** extrapolated for the equivalent per-node `CSS.getComputedStyleForNode` walk and **881.5 ms** for the in-page `getComputedStyle` loop most tools actually use. That is **177×** and **29×** respectively.

2. **The full deterministic fact-pack costs less than the screenshot it accompanies.** *(measured)* The complete extraction schema in §3 serialises to **3,073 bytes ≈ 854 tokens**; a 1440×900 PNG is ~1,100–1,600 tokens. Capture-to-JSON end-to-end: **53 ms**. There is no context-budget argument for withholding facts from the model.

3. **No perceptual image metric ranks a real design regression above anti-aliasing noise — and this is not a metric-selection problem.** *(measured, §2)* Perceptual metrics answer *"would a human notice?"*. Design review asks *"is this wrong?"*. Token drift is **invisible-but-wrong**, so it lives exactly in the null space of every metric tested. The correct architecture is not a better differ; it is: **DOM answers token correctness, image differ answers paint-level correctness, and neither is asked the other's question.**

---

## 1. Capability table — exact sources

Cost measured per-page on the 2,009-layout-node `nextjs.org` unless noted.

| # | Measurement | Exact source | Design defect caught | Cost *(measured)* |
|---|---|---|---|---|
| C1 | Geometry + computed styles, whole tree | [`DOMSnapshot.captureSnapshot`](https://chromedevtools.github.io/devtools-protocol/tot/DOMSnapshot/#method-captureSnapshot) → `documents[].layout.{nodeIndex,styles,bounds,text}` | everything in the B-series below | **32.7 ms**, 707 KB raw, 246 B/node |
| C2 | Paint order | same call, `includePaintOrder:true` → `layout.paintOrders` | z-order inversion; element behind its own overlay | +0 ms; 2,009 entries |
| C3 | Stacking contexts | same → `layout.stackingContexts` (`RareBooleanData`) | accidental stacking context breaking `position:sticky` / `z-index` | +0 ms; **1,274** found |
| C4 | Blended background colour behind text | same, `includeBlendedBackgroundColors:true` → `layout.blendedBackgroundColors` | contrast against the *actual composited backdrop*, not the nearest ancestor's `background-color` | +0 ms; **99** text runs resolved |
| C5 | Text colour opacity | same, `includeTextColorOpacities:true` → `layout.textColorOpacities` | `opacity:.6` text that passes contrast on paper and fails on screen | +0 ms |
| C6 | offset / client / scroll rects | same, `includeDOMRects:true` | overflow + clipping (B7) | +0 ms |
| C7 | Per-node computed style | [`CSS.getComputedStyleForNode`](https://chromedevtools.github.io/devtools-protocol/tot/CSS/#method-getComputedStyleForNode) | — | **2.17 ms/node.** Use only on a handful of nodes after C1 localises them. |
| C8 | Authored rules + cascade + `@media`/`@supports`/`@layer` origin | [`CSS.getMatchedStylesForNode`](https://chromedevtools.github.io/devtools-protocol/tot/CSS/#method-getMatchedStylesForNode) | *which rule* set the off-token value — the fix location, not just the symptom | per-node; only route to authored-vs-computed |
| C9 | Cascade layers for a node | [`CSS.getLayersForNode`](https://chromedevtools.github.io/devtools-protocol/tot/CSS/#method-getLayersForNode) | a design-system layer losing to an app layer | per-node |
| C10 | Rule usage / dead CSS | [`CSS.startRuleUsageTracking`](https://chromedevtools.github.io/devtools-protocol/tot/CSS/#method-startRuleUsageTracking) + `stopRuleUsageTracking` | dead token definitions; utility-class bloat | see trap **T3** |
| C11 | Background colours behind text (single node) | [`CSS.getBackgroundColors`](https://chromedevtools.github.io/devtools-protocol/tot/CSS/#method-getBackgroundColors) | same as C4, per-node | superseded by C4 for page-wide work |
| C12 | Font files actually resolved | [`CSS.getPlatformFontsForNode`](https://chromedevtools.github.io/devtools-protocol/tot/CSS/#method-getPlatformFontsForNode) | **silent font fallback** — `font-family` reads correctly while the box renders in the fallback | per-node; nothing else detects this |
| C13 | Accessibility tree | [`Accessibility.getFullAXTree`](https://chromedevtools.github.io/devtools-protocol/tot/Accessibility/#method-getFullAXTree) | role + name for every interactive element → touch-target census (B9) | **26.7 ms**, 790 nodes |
| C14 | Viewport + content size | [`Page.getLayoutMetrics`](https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-getLayoutMetrics) → `cssLayoutViewport`, `cssVisualViewport`, `cssContentSize` | horizontal-scroll bugs; measurement denominators. Use the `css*` fields — the unprefixed ones are **deprecated** and device-pixel. | <5 ms |
| C15 | Screenshot | [`Page.captureScreenshot`](https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-captureScreenshot) (`captureBeyondViewport`, `clip`, `optimizeForSpeed`) | the image the model judges | **39 ms**, 71 KB |
| C16 | Element highlight overlay | [`Overlay.highlightNode`](https://chromedevtools.github.io/devtools-protocol/tot/Overlay/#method-highlightNode) · `setShowGridOverlays` · `setShowFlexOverlays` | **annotation, not measurement** — paints margin/padding/grid tracks onto the screenshot so the model sees *where* a cited number lives | one call per node |

### What CDP gives that Playwright's high-level API does not

Playwright exposes `boundingBox()` (one node, one round trip), `evaluate()` (in-page — blind to closed shadow DOM and pseudo-elements), and `accessibility.snapshot()` (filtered "interesting nodes" only). Reach CDP with `await page.context().newCDPSession(page)`; no extra dependency.

Five capabilities with **no** high-level equivalent:

- **Closed shadow roots.** *(measured)* An `attachShadow({mode:'closed'})` subtree's text and styles appear in `captureSnapshot` with `shadowRootType:"closed"`. `document.querySelectorAll('*')` cannot reach it at all. Decisive for web-component design systems.
- **Pseudo-elements.** *(measured)* `::before` / `::after` appear as first-class nodes carrying `pseudoType`, with their own `bounds` and computed styles. In-page JS cannot enumerate them; `getComputedStyle(el,'::before')` requires you to already know the element.
- **Cross-origin iframes.** *(measured)* Returned as additional entries in `documents[]` — an `https://example.com/` frame yielded 20 nodes. Same-origin JS cannot cross that boundary.
- **Paint order and stacking contexts as data.** Not exposed anywhere in the DOM API; the only alternative is re-implementing CSS 2.1 Appendix E.
- **Blended background colour.** The compositor's own answer to "what is actually behind this text", through arbitrary nesting, gradients, opacity and `mix-blend-mode`. Every JS contrast checker approximates this by walking ancestors, and gets it wrong on overlap.

**Below-the-fold is included.** *(measured)* Max layout Y = **3,488 px** against a 700 px viewport. `captureSnapshot` is a document-wide layout dump, not a viewport dump — no scroll-and-stitch needed for geometry (only for pixels).

---

## 2. Perceptual diff — and why the honest answer is "mostly don't"

### 2a. The experiment

Nine-card grid, 1200×820, `deviceScaleFactor:1`, deterministic fixture, fonts awaited. One **noise** class (sub-pixel text translation — the canonical false positive, visually identical) and seven **real regression** classes. Every cell measured.

| Variant | raw diff px | pm t=0.1 | **pm t=0.2 (PW default)** | SSIM (mssim) | **FLIP mean** | max ΔE2000 |
|---|---|---|---|---|---|---|
| `A_identical` (control) | 0 | 0 | 0 | 1.000000 | 0 | 0 |
| **`N_aa_0.3px` (noise)** | 41,195 | 7,360 | **1,889** | 0.996243 | **0.009907** | 49.95 |
| **`N_aa_0.25px_all` (noise)** | 68,201 | 6,145 | **800** | 0.994576 | **0.012978** | 32.81 |
| `R_padding 16→14` | 288,838 | 76,425 | 73,033 | 0.604905 | 0.143856 | 88.88 |
| `R_gap 24→20` | 114,216 | 37,724 | 34,285 | 0.764647 | 0.075301 | 88.88 |
| `R_weight 600→500` | 8,096 | 3,334 | 2,674 | 0.990680 | 0.004469 | 88.88 |
| `R_shift 1px` | 5,823 | 2,070 | **1,728** ⚠ | 0.997138 ⚠ | 0.004737 ⚠ | 88.88 |
| `R_radius 12→8` | 2,448 | **0** ⛔ | **0** ⛔ | 0.999162 ⚠ | 0.000331 ⚠ | 5.18 |
| `R_color #171717→#1a1a1a` | 29,814 | **0** ⛔ | **0** ⛔ | 0.999981 ⚠ | 0.001865 ⚠ | 1.03 |
| `R_bordercolor #e5→#dd` | 9,843 | **0** ⛔ | **0** ⛔ | 0.998234 ⚠ | 0.002332 ⚠ | 1.78 |

⛔ = real change, **literally zero** diff pixels. ⚠ = real change scored *less different than pure noise* (rank inversion).

### 2b. What that table says

- **At Playwright's default `threshold: 0.2`, three of seven real regressions are invisible and a fourth ranks below noise.** `odiff` at `threshold:0.1, antialiasing:true` independently returns `{"match": true}` for the radius regression *(measured)* — so this is a property of threshold-on-colour-delta differs generally, not a pixelmatch bug.
- **Why:** the threshold is a *global colour-delta* gate. A geometric change rendered where two near-identical colours meet (a card corner: `#fff` on `#fafafa`) produces a delta below any usable threshold. Design tokens live disproportionately in exactly those low-contrast regions — borders, surfaces, radii, hairlines.
- **SSIM inverts on four of seven.** It ranks the AA noise (0.9962) as *more different* than the real radius (0.9992), colour (0.99998), border (0.9982) and 1px-shift (0.9971) regressions. SSIM is not the fix.
- **FLIP inverts on five of seven — and FLIP is *right* to.** A human genuinely would not notice `border-radius: 12px → 8px` or `#171717 → #1a1a1a` in a flash test. FLIP answers its own question correctly. The mistake is asking it ours.

### 2c. The one thing FLIP is best at, and it is the thing you actually need

FLIP is the only metric tested with a **clean, interpretable noise floor**:

- both noise variants: mean **0.0099** and **0.0130**
- the two regressions a human *would* notice: **0.0753** and **0.1439**
- separation: **≈ 5.8×** between worst noise and weakest true positive.

Compare pixelmatch at its default: noise 1,889 vs weakest true positive 1,728 — separation **0.91×**, i.e. inverted. FLIP is therefore the right **gate**, not the right **detector**: it answers *"is this screenshot pair worth spending a vision model on?"* with a threshold that means something.

### 2d. Verdict table

| Metric | Repo / package | Use it for | Do **not** use it for | Cost *(measured, 1200×820)* |
|---|---|---|---|---|
| **NVIDIA FLIP** (LDR) | [NVlabs/flip](https://github.com/NVlabs/flip) · `pip install flip-evaluator` · v1.7 · BSD-3 | **default noise gate.** `mean > ~0.02` ⇒ escalate to the vision model. Its error map is also the best third image to hand the model. | catching token drift; anything readable from the DOM | **422 ms** |
| **odiff** | [dmtrKovalenko/odiff](https://github.com/dmtrKovalenko/odiff) · `odiff-bin` v4.5.0 · MIT · SIMD | fast pre-filter on large full-page shots; `ignoreRegions` for known-dynamic areas | a correctness gate — returns `match:true` on real regressions | **47 ms** (28 ms on the noise pair) |
| **pixelmatch** | [mapbox/pixelmatch](https://github.com/mapbox/pixelmatch) · v7.2.0 · ISC | localising *where* a FLIP-flagged diff is (`diffMask`); `windowSize` is genuinely useful against dithering | same as odiff | **81 ms** (9 ms with `includeAA:true`) |
| **SSIM** | `ssim.js` v3.5.0 | layout-scale breakage only, where it does move decisively (padding 0.60, gap 0.76) | fine-grained anything; it inverts | ~200 ms |
| **CIEDE2000** | `culori` `differenceCiede2000()` · `colorjs.io` | **per-colour-pair, on values read from the DOM** — "is `#171717` vs `#1a1a1a` a different colour or a rounding artifact?" ΔE 1.03 answers exactly that | whole-image scanning — `max` saturates at 88.88 on any pair containing a text edge and becomes information-free | µs per pair |
| **LPIPS / DISTS** | [dingkeyan93/DISTS](https://github.com/dingkeyan93/DISTS) · MIT | **not recommended here.** Both are texture-invariant *by design* — DISTS is explicitly "robust to texture variance and mild geometric transformations", precisely the sensitivity a UI reviewer needs. Torch dependency, GPU-shaped cost. | UI regression | — |

### 2e. A verified correction to a load-bearing assumption

**Playwright 1.61.1 does not use current pixelmatch.** Direct inspection of the shipped bundle (`playwright-core/lib/coreBundle.js`) shows a vendored `packages/utils/third_party/pixelmatch.js` containing

```js
const maxDelta = 35215 * options.threshold * options.threshold;
```

plus the coefficient `0.5053` — the **YIQ** formula (Kotsarenko & Ramos 2010) from pixelmatch v5. Upstream pixelmatch **7.2.0 has since moved to OKLab / HyAB**. So Playwright's documented "perceived color difference" is 2010-vintage YIQ, and `threshold: 0.2` means *YIQ delta² > 35215 × 0.04 = 1,408.6*. `includeAA` is left at its default `false` (i.e. AA detection **is** active) and is not overridable through `toHaveScreenshot`. Anyone reasoning from "Playwright uses pixelmatch" is reasoning about a different algorithm than the one running.

---

## 3. The extraction schema

What the capture step hands the judging model alongside the screenshot. *(measured)* **3,073 bytes ≈ 854 tokens**, produced in **53 ms** including the AX tree. Values below are the real `nextjs.org` output, not illustrations.

```jsonc
{
  "meta": { "url": "...", "viewport": {"w":1440,"h":900}, "dpr": 1,
            "capturedAt": "2026-08-26T07:20:20.223Z", "captureMs": 53, "layoutNodes": 2009 },

  // B1 SPACING SCALE ADHERENCE — every margin/padding/gap, histogrammed
  "spacing": { "distinct": 26, "gridBase": 4, "onGridPct": 78.5,
               "histogram": {"4":128,"8":116,"24":94,"16":72,"12":71,"10":49,"6":38,"32":34,"3":12,"1.2":24},
               "offGrid": [1.2,2,3,6,10,14,18,19,21,25] },

  // B2 TYPOGRAPHIC SCALE
  "type": { "sizes": {"16":1618,"14":197,"20":73,"13":60,"24":31,"32":7,"11":6,"72":5,"12":4,"18":4,"40":3},
            "weights": {"400":1868,"600":97,"500":43},
            "lineHeights": {"26.4px":1619,"20px":84,"23.1px":59,"21.45px":40},
            "families": {"GeistSans":1978,"Geist Mono":14,"Georgia":12,"Inter":4} },

  // B3 PALETTE ACTUALLY USED — diff this against your token file; that is the whole check
  "palette": { "distinctTotal": 33,
               "textColors": {"rgb(23, 23, 23)":1615,"rgb(102, 102, 102)":166,"rgb(255, 255, 255)":85,"rgb(17, 17, 17)":35},
               "backgrounds": {"rgb(255, 255, 255)":200,"rgb(50, 145, 255)":180,"rgba(0, 0, 0, 0.6)":16} },

  // B4 SHAPE LANGUAGE
  "shape": { "radii": {"0px":1343,"9999px":477,"2px":79,"100px":22,"12px":21,"6px":17,"4px":10},
             "shadows": { "rgba(0, 0, 0, 0.03) 0px 0px 0px 1px, ... 0px 12px 24px 0px": 11 } },

  // B5 ALIGNMENT EDGES — a left edge shared by >=3 boxes is an intentional column
  "alignment": { "leftEdges": {"120":27,"145":28,"221":24,"550":22},
                 "rightEdges": {"218":26,"230":25,"1320":23},
                 "sharedLeftEdges_ge3": 142 },

  // B6 CONTRAST — both algorithms, per text run, from the BLENDED backdrop
  "contrast": { "measured": 99, "wcagFailures": 13, "apcaLcRange": [-107.6, 106.4],
                "worst": [{"fg":"rgb(0, 114, 245)","bg":"rgb(255, 255, 255)","px":16,"w":400,
                           "wcag":4.44,"apcaLc":69.9,"wcagPass":false}] },

  // B9 TOUCH TARGETS — role from AX tree, box from snapshot
  "targets": { "total": 72, "under24": 36, "under44": 61,
               "smallest": [{"role":"link","name":"Docs","w":33,"h":20}] },

  // B7/B8/B10 — emitted only when non-empty
  "clipping": [ {"node":"A","scroll":[76,23],"client":[66,23],"overflowX":"visible"} ],
  "zorder":   { "stackingContexts": 1274, "explicitZIndex": {"2":17,"3":17,"1":10,"1000":4} },
  "focus":    { "focusable": 72, "noVisibleRing": 6,
                "samples": [{"tag":"A","cls":"outline-none m-0 p-0 border-0"}] }
}
```

### How each field is computed, exactly and cheaply

| | Measurement | Computation |
|---|---|---|
| **B1** | spacing-scale adherence | From `layout.styles`, collect every `margin-*` / `padding-*` / `*gap` > 0. `onGridPct = Σcount(v % base == 0) / Σcount`. *(measured)* 78.5 % on a 4 px base, 49.6 % on 8 px, from **26** distinct values — so `nextjs.org` is a 4 px system, and the model should be *told* that, not asked to infer it. `offGrid` names the violators. **Pure JS over the snapshot: 36.7 ms** *(measured)*. |
| **B2** | typographic scale | Histogram `font-size`; ratios between consecutive sizes expose whether a modular scale exists. *(measured)* 11 sizes, 3 weights, **4 families** — the 4th (`Inter`, 4 nodes, alongside `GeistSans` at 1,978) is a token leak no human finds by eye. |
| **B3** | palette vs tokens | Histogram `color` + `background-color` (drop `rgba(0,0,0,0)`). Set-difference against the token file. For near-misses run **CIEDE2000** per unmatched pair: ΔE < ~1 ⇒ rounding/colour-space artifact · ΔE 1–3 ⇒ real but sub-threshold drift · ΔE > 3 ⇒ a different colour. This is the one place a perceptual colour metric belongs. |
| **B5** | alignment edges | Round `bounds[i].x` and `x+width`; histogram. Bins with ≥3 members are intended columns; a box within 1–3 px of a populated bin but *not in it* is a **misalignment** — that near-miss test is the actual detector, not the histogram. *(measured)* **142** shared left edges. |
| **B6** | contrast | `blendedBackgroundColors[i]` + `styles[i].color` + `font-size` / `font-weight` → WCAG 2.1 via `colorjs.io` `contrastWCAG21`, APCA Lc via `apca-w3` v0.1.9 `APCAcontrast(sRGBtoY(fg), sRGBtoY(bg))`. Multiply through `textColorOpacities[i]` first. |
| **B7** | overflow / clipping | `scrollRects[i].width > clientRects[i].width + 1` (or height) ⇒ content exceeds its box. Cross-reference `overflow-x` / `overflow-y`: `hidden` ⇒ **silently truncated**; `visible` ⇒ overflowing. *(measured)* **31** such subtrees, including two nav links whose text is 76 px in a 66 px box. |
| **B8** | z-order / overlap | Rect-intersect over `bounds`, ordered by `paintOrders`. *(measured)* 4,795 intersecting pairs among the first 600 boxes — so **raw overlap count is noise**. The signal is *intersecting pairs where both boxes carry text and the later-painted one is not a declared overlay*. `stackingContexts` (1,274) locates accidental contexts. |
| **B9** | touch targets | AX `role ∈ {button,link,checkbox,textbox,menuitem,tab,switch,radio,combobox}` → `backendDOMNodeId` → snapshot `bounds`. *(measured)* **36 of 72** interactive elements under 24 px in their smaller dimension. |
| **B10** | focus-visible coverage | Requires driving state: per focusable, snapshot `outline*` + `box-shadow` + `border-color`, call `.focus()`, re-read, diff. *(measured)* **6 of 72** produce no visual change — all four sampled carry the literal class `outline-none`. |
| **B11** | silent font fallback | `CSS.getPlatformFontsForNode` on a sample; compare `familyName` against the first entry of the authored `font-family`. Nothing else detects this — the computed style is a *request*, not a result. |

### Three traps that will produce wrong numbers

- **T1 — `bounds` is post-transform document space; `offsetRects` / `clientRects` are not always populated.** *(measured)* A `rotate(15deg) translateX(40px)` box reports `bounds:[48.8,53.1,84,38.7]` (the transformed AABB) while `offsetRect` / `clientRect` came back `[]`. Use `bounds` for alignment and overlap; never assume the DOM-rect arrays are dense.
- **T2 — `blendedBackgroundColors` is sparse by design.** *(measured)* **99** populated of 2,009 layout entries — only boxes that actually paint text get one. Index by layout index and skip `-1`; do not read sparsity as failure.
- **T3 — CSS coverage must be armed before navigation.** *(measured)* Calling `CSS.startRuleUsageTracking` after load returned **591 rules tracked, 591 used, 0 % unused** — an artifact, not a result. Enable `DOM` + `CSS`, start tracking, *then* `Page.navigate`.

**Determinism knobs to set before any capture:** `Emulation.setEmulatedMedia` (`prefers-reduced-motion: reduce`; plus `forced-colors` / `prefers-color-scheme` for theme passes), `animations:'disabled'` + `caret:'hide'` on the Playwright side, a fixed `deviceScaleFactor`, and `await document.fonts.ready`.

---

## 4. What to take rather than build

| Project | Take | Reason |
|---|---|---|
| **axe-core** ([dequelabs/axe-core](https://github.com/dequelabs/axe-core), 4.11.x, MPL-2.0) | **Take wholesale.** `color-contrast`, `target-size`, `focus-order-semantics`, `aria-*`. | Its `color-contrast` rule already handles transparency, opacity and pseudo-element backgrounds — years of edge cases you would otherwise re-derive. 4.11.1 explicitly fixed a case where the contrast rule could **skip testing a page**; pin ≥ 4.11.1. **APCA is not in axe-core** — [StackExchange/apca-check](https://github.com/StackExchange/apca-check) supplies APCA bronze/silver rules in the same harness if you want it. |
| **Lighthouse** | **Take selectively.** `tap-targets` (48×48 with a 25 % overlap rule) and `unsized-images` are worth reading as *specifications*. | Lighthouse **13 removed the `font-size` audit**, and its scoring is a performance product, not a design product. Take the audit logic, not the runner. |
| **Playwright `toHaveScreenshot`** | **Take the harness, replace the comparator.** | Excellent capture determinism (`animations:'disabled'`, `caret:'hide'`, `mask`, `maskColor`, `stylePath`, `scale:'css'`, `clip`, `fullPage`). But §2e: the comparator is vendored 2010-era YIQ pixelmatch, and §2b shows the default threshold misses real regressions. Use `maxDiffPixelRatio` as a coarse tripwire and put FLIP downstream. |
| **odiff / pixelmatch** | Take as **libraries**, in the §2d roles only. | Both small, MIT/ISC, no lock-in. |
| **NVIDIA FLIP** | **Take — this is the recommendation.** | BSD-3, `pip install flip-evaluator`, 422 ms. The only metric with a defensible noise floor. |
| **BackstopJS / reg-suit** | **Take neither.** | Both are baseline-management + reporting shells around a pixel differ. You already have baseline management (git) and a better judge (the model). Their differ is the part §2 disqualifies. |
| **Aalto Interface Metrics** ([aalto-ui/aim](https://github.com/aalto-ui/aim), MIT, Python) | **Take 3–4 metric modules as source; not the service.** | Verified roster read from the repo: `m1` PNG size · `m2` JPEG size · `m3` distinct RGB · `m4` contour density · `m5` figure-ground contrast · `m6` contour congestion · `m7` subband entropy · `m8` feature congestion (Rosenholtz) · `m9` **UMSI saliency (Xception NN)** · `m10` WAVE · `m11` static clusters · `m12` dynamic clusters · `m13` luminance std · `m14` LAB avg/std · `m15` colourfulness (Hasler-Süsstrunk) · `m16` HSV avg/std · `m17` distinct H/S/V · `m18` **NIMA (DenseNet-121)** · `m19` distinct RGB per cluster · `m20` colour harmony · `m21` **grid quality** · `m22` **white space** · `m23` colour blindness · `m24`/`m25` segmentation · `m30` MDEAM. **Take `m21` grid quality, `m22` white space, `m8` feature congestion, `m15` colourfulness** — exactly the "code supplies facts" quantities the DOM cannot express. **Do not take `m9`, `m18`, `m30`** — they are neural nets, i.e. a second, weaker vision model competing with the one you already have. Deployed as a Tornado web service; vendor the metric modules, not the service. |
| **APCA** (`apca-w3` v0.1.9, [Myndex/apca-w3](https://github.com/Myndex/apca-w3)) | **Take `APCAcontrast` as a scalar. Do NOT take `fontLookupAPCA` as a gate.** | See §5, challenge 2 — a measured correction. |

**Status check on APCA / WCAG 3, since the brief asks:** visual contrast was **pulled from the WCAG 3 Working Draft in July 2023**, and as of April 2026 the draft states the contrast method is **yet to be determined**. WCAG 3 is not expected to reach Recommendation before 2028. BridgePCA exists as a WCAG-2-backwards-compatible bridge. So: **WCAG 2.1 is the binary compliance floor; APCA Lc is a readability scalar, not a standard.** Report both; gate on neither alone.

---

## 5. Adversarial self-pass

Three challenges run with real probes rather than assumptions. Two overturned things this document was about to assert.

**Challenge 1 — "DOMSnapshot must be blind to shadow DOM, pseudo-elements and cross-origin frames; the schema collapses on a web-component app."** *(refuted, measured)* All three are captured, including **closed** shadow roots. The in-page `getComputedStyle` route — what most tooling uses, and what I would otherwise have recommended as the portable fallback — is the blind one. This inverts the usual "CDP is a nice-to-have" framing: for component-library review, CDP is the only route that sees the components.

**Challenge 2 — "just use APCA, it is the better algorithm."** *(refuted, measured)* Naively gating on `fontLookupAPCA(Lc)` — treating the returned minimum font size per weight as pass/fail — flagged **66 of 99** text runs on `nextjs.org` as failures, against WCAG 2's 13, with **53 outright disagreements** between the two. Example: `#666` on `#fff` at 14 px / 400 scores WCAG **5.74 (pass)** and Lc **78.8**, for which the lookup demands **17.5 px** — a "fail". APCA's lookup is a *use-case guidance table*, not a conformance gate; wiring it as one manufactures a ~5× false-positive rate on a competently designed site. **Emit `apcaLc` as a continuous scalar and let the model weigh it; gate only on WCAG 2.1.**

**Challenge 3 — "pick the best perceptual metric."** *(reframed, measured)* §2 is the answer: the premise is wrong. No metric ranks token drift above AA noise, because token drift is *below human noticeability by construction* while perceptual metrics are calibrated to human noticeability. The resolution is architectural, not a better metric.

### The defects this layer provably CANNOT catch — the vision model's job description

Everything above is a fact. Everything below is taste, semantics, or content, and no amount of CDP or image differencing reaches it. This is the most useful output of this brief.

**Class 1 — Rendered but not declared (a hard blind spot, not a hard problem).**
- **`<canvas>` / WebGL / `<video>` interiors.** *(measured)* A chart drawn into a canvas contributes exactly one node with a width and a height. Its axes, labels, colours, overlaps and legibility are invisible to every measurement in §1.
- **Raster image content.** `background-image: url(hero.png)` is a string. Whether the hero is on-brand, well-cropped, has its subject in the safe area, or has text baked in that fails contrast — unreachable.
- **SVG interiors** — icon-set consistency, stroke-weight coherence across an icon row.
- **Text rendered as an image.**

**Class 2 — Correct numbers, wrong design.** Every one of these passes every check above.
- **Rhythm and proportion.** 78.5 % on a 4 px grid says nothing about whether `24 / 16 / 12` *in that sequence* produces a readable card. A perfect scale, badly applied, measures perfectly.
- **Visual hierarchy.** Which element should be seen first, and whether it is. Sizes and weights are enumerable; the *ordering intent* is not.
- **Balance, tension, density.** Whether a layout feels crowded or empty. AIM `m22` yields a white-space scalar; it does not yield "this hero is empty in a way that reads as unfinished".
- **Alignment that is technically shared but visually wrong.** Optical alignment — a round icon needs 1–2 px overhang to *look* aligned; hanging punctuation; optical centring of a triangle in a play button. The measured edges will be identical and it will look off.
- **Grouping and proximity semantics.** That two controls sit 8 px apart is a fact; that they are unrelated and *should* be 24 px apart is a judgment about meaning.

**Class 3 — Meaning, tone, content correctness.**
- Copy quality, tone, terminology consistency; truncation that is grammatical vs. mid-word.
- Whether an icon means what its label says.
- **Brand fit.** Whether `rgb(50,145,255)` is *the* blue is a token lookup (deterministic); whether that blue belongs on this product is not.
- Locale / RTL sanity, and whether German copy breaks the layout at a width you did not capture.

**Class 4 — State and time.** A snapshot is one state of one page at one width.
- **Hover / active / disabled / loading / error / empty states** exist only if something drives them. B10 shows focus is drivable — but each state is a separate capture, and *which* states matter is a judgment.
- **Animation and transition quality** — easing, duration, whether motion reads as responsive or sluggish. `prefers-reduced-motion` is set precisely to *destroy* this signal for determinism.
- **Scroll-dependent design** — sticky-header behaviour, parallax, scroll-triggered reveals, whether the fold cuts a section so it reads as the end of the page.
- **Responsive breakpoint judgment** — geometry is measurable at each width; whether the *chosen* breakpoints are right is not.
- **Cross-browser / platform rendering divergence** — everything here is Chromium.

**Class 5 — Absence.** The deterministic layer enumerates what is present. It cannot flag a missing empty-state, an absent loading skeleton, a page with no clear primary action, or an unhandled error path. **No measurement over a DOM detects a node that was never authored.**

**The division of labour this implies:** hand the model the screenshot, the FLIP error map when diffing, and the §3 fact-pack — and have the prompt say, in effect: *"the numbers are given; do not re-derive them, and do not comment on spacing adherence, contrast ratios, target sizes or palette membership except to interpret what is stated. Judge hierarchy, rhythm, grouping, optical alignment, state coverage, and content fit."* That is an 854-token investment that removes the entire class of failure the March 2026 corpus conceded.

---

## 6. Blockers and uncertainties

- **The §2 fixture is one synthetic page with seven mutation classes.** The rank inversions are unambiguous and mechanistically explained, but the *magnitudes* (5.8× FLIP separation, the 0.02 gate) are calibrated on that fixture. Re-derive the FLIP threshold on your own corpus before hard-coding it.
- **The AA-noise proxy is a sub-pixel transform, not genuine cross-platform font rendering.** It is the right *shape* of noise (AA-only, geometry-preserving), but real CI noise — different GPU, different font-hinting stack — may be larger. That direction makes the case *stronger*, not weaker.
- **FLIP at 422 ms is the slowest stage**, ~8× the entire CDP capture. Use odiff (47 ms) as a cheap "any pixels at all?" pre-filter and run FLIP only on non-empty diffs.
- **`nextjs.org` is a single, well-built target.** The 78.5 % grid adherence and the 4-font-family leak are real, but calibrate `onGridPct` expectations on your own corpus — no cross-site distribution was gathered.
- **Not investigated, deliberately:** `DOM.getBoxModel` was skipped once `DOMSnapshot.bounds` proved to carry post-transform geometry for the whole tree — `getBoxModel` is per-node and strictly dominated for a page census. If you need the *separate* content/padding/border/margin quads for one node, it is the right call.
