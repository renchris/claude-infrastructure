# P3 — EXTRACT: the deterministic fact-pack

**Stage owner:** the `design-perceive` CLI, `extract` phase.
**One-line job:** turn one loaded page into ~854 tokens of facts the judge must never re-derive, and
into a set of **honest abstentions** that are the vision stage's job queue.

---

## 1. CONTRACT

### 1.1 Inputs

| | Input | Source | Required |
|---|---|---|---|
| I1 | A **live CDP session** on a page that has finished layout | P2-CAPTURE hands over the same `CDPSession` that took the screenshot | yes |
| I2 | `Page.getLayoutMetrics()` result | taken by P2 in the same pass | yes |
| I3 | Viewport, DPR, and the raster dimensions of the PNG P2 wrote | P2's return value | yes |
| I4 | Token file for this app (`{name: "#hex"}`) | repo, resolved per target app (§9) | optional — absent ⇒ `palette.tokenDiff: null`, never a guess |
| I5 | Optional `clip` rect in CSS px, when this is a **crop pass** | P4-CROP | optional |

🚨 **I1 is a hard coupling and it is deliberate.** EXTRACT must run against *the same frame that was
photographed*, in the same browser pass, before any navigation, scroll, hover or resize. A snapshot
taken in a second pass permits the escape hatch "maybe the page moved", and every disagreement
between a DOM finding and a pixel finding then becomes unarguable. If P2 hands over a closed session,
EXTRACT exits `4` (§1.3) rather than re-navigating.

### 1.2 Outputs

Two files and one stdout object. No image is produced by this stage.

| | Artifact | Shape | Size *(measured, nextjs.org, 2,009 layout nodes)* |
|---|---|---|---|
| O1 | `<out>/<slug>.facts.json` | the §6 schema — **this is what the judge reads** | 3,073 B ≈ **854 tokens** |
| O2 | `<out>/<slug>.layout.json` | the raw reduced node table, one row per *retained* node (§5) | ~40–90 KB; **never handed to a model** |
| O3 | stdout | `{"ok":true,"schema":"design-perceive/1","facts":"<path>","layout":"<path>","extractMs":53,"abstentions":N}` | — |

O2 exists so a follow-up automation (P4-CROP choosing where to zoom, P6-VERIFY re-arguing a disputed
finding) can look up a node without re-running the browser. It is on disk precisely so it is *not* in
context. **The one rule that governs the split: if a fact is per-node it lives in O2; if it is
per-page it lives in O1.** A judge that needs one node's numbers is being asked a localisation
question, which is P4's job, not P3's.

### 1.3 Failure modes — exact exit codes, and what each one means downstream

| Exit | Condition | Downstream obligation |
|---|---|---|
| `0` | facts written; `abstentions` may be > 0 | normal |
| `2` | `captureSnapshot` returned `documents[0].layout.nodeIndex.length === 0` | the page never laid out — **P2's problem**; do not emit a clean fact-pack |
| `3` | token file given but unparseable | run again without `--tokens`; `palette.tokenDiff` becomes `null`, and the judge is told the check did not run |
| `4` | CDP session closed / detached before extract | re-run the whole P2+P3 pass; **never** re-navigate inside P3 |
| `5` | `documents.length > 1` and `--frames=strict` | cross-origin iframe present; the caller must decide whether frame facts merge or stay separate (§4.4) |

🚨 **There is no exit code for "no defects found", because EXTRACT does not adjudicate.** It emits
facts and abstentions. A run over a flawless page still returns `0` with a full fact-pack. Any code
path that lets a *thin* fact-pack read as a *clean* page reproduces `fail-safe-default-mimics-the-healthy-state`,
which is the single most expensive failure available to this pipeline.

---

## 2. What this stage CANNOT do, and who owns it

Stated first, because a spec that lists capabilities before limits invites the caller to assume the
gaps are filled.

| Not ownable here | Why structurally | Owning stage |
|---|---|---|
| Any contrast number over a gradient, image, `mix-blend-mode`, or backdrop-filter | no scalar can represent a backdrop that *varies across* the element sitting on it | **P5-XCHECK** (samples left/right thirds) — routed by our `INDETERMINATE` |
| `<canvas>` / WebGL / `<video>` interiors | contributes exactly one node with a width and a height | **P6-JUDGE** (pixels) |
| Raster and SVG image content — crop, brand fit, baked-in text | `background-image:url(...)` is a string | **P6-JUDGE** |
| Whether a measured number is *good* | 78.5 % on a 4 px grid says nothing about whether `24/16/12` in that sequence reads well | **P6-JUDGE** |
| Optical alignment (round icon overhang, hanging punctuation) | the measured edges are *identical* and it still looks wrong | **P6-JUDGE**, informed by P5's ink centroid |
| Absence — a missing empty state, no clear primary action | no measurement over a DOM detects a node that was never authored | **P6-JUDGE** |
| Silent font fallback | `font-family` is a *request*; only `CSS.getPlatformFontsForNode` returns the *result* | **P3, but per-node only** — see §8.3, it is a crop-time call |
| Hover / active / disabled / error states | require driving state; each is a separate capture | **P2-CAPTURE**, one pass per state |

---

## 3. The extraction call, exactly

### 3.1 Determinism preamble — runs in P2, asserted in P3

EXTRACT refuses to run unless P2 set all five. It re-reads them and puts them in `meta.determinism`,
so a geometric finding can never be argued from an unpinned capture.

```js
// Chromium launch flags (P2)
'--force-device-scale-factor=2'   // headless vs headed disagree on line-box rounding:
                                  // ~1.5px drift over four paragraphs, identical font metrics.
                                  // Unpinned, EVERY geometric finding inherits a phantom offset
                                  // that reads exactly like a real 1px bug.
'--force-color-profile=srgb'      // the screenshot is an untagged sRGB-numeric buffer either way;
                                  // pinning it stops the host display profile entering the numbers.
'--disable-lcd-text'              // subpixel AA makes glyph edges colour-fringed, which poisons
                                  // P5's ink/backdrop separation.
'--hide-scrollbars'               // a 15px scrollbar shifts every right edge in the alignment histogram.
```

```js
await cdp.send('Emulation.setEmulatedMedia', {
  features: [{ name: 'prefers-reduced-motion', value: 'reduce' }]   // freeze transitions
});
await page.evaluate(() => document.fonts.ready);                    // metrics before geometry
```

### 3.2 The one call

```js
const snap = await cdp.send('DOMSnapshot.captureSnapshot', {
  computedStyles: STYLE_WHITELIST,        // §3.3 — 39 entries
  includePaintOrder: true,                // → layout.paintOrders
  includeDOMRects: true,                  // → layout.{offsetRects,clientRects,scrollRects}
  includeBlendedBackgroundColors: true,   // → layout.blendedBackgroundColors  (the compositor's answer)
  includeTextColorOpacities: true         // → layout.textColorOpacities
});
```

*(measured)* **32.7 ms** for 2,871 nodes × 32 style properties. The alternatives: **881.5 ms** for the
in-page `getComputedStyle` loop (29×) and **5,788 ms** extrapolated for the per-node
`CSS.getComputedStyleForNode` walk (177×). The four `include*` flags each cost **+0 ms** — they are
data the layout already holds. **There is no version of this stage that does not set all four.**

Three capabilities have no in-page equivalent and decide the call: **closed shadow roots** appear with
`shadowRootType:"closed"` (decisive for web-component design systems — `document.querySelectorAll('*')`
cannot reach them at all), **pseudo-elements** appear as first-class nodes carrying `pseudoType` with
their own bounds, and **cross-origin iframes** return as extra `documents[]` entries. The in-page route
is the blind one; that inverts the usual "CDP is a nice-to-have" framing.

**Below the fold is already included.** *(measured)* max layout Y = 3,488 px against a 700 px viewport.
`captureSnapshot` is a document-wide layout dump, not a viewport dump. **Scroll-and-stitch is a pixel
problem only** — never scroll to complete the geometry, because scrolling can fire IntersectionObserver
reveals and you will have snapshotted a different page than the one photographed.

### 3.3 `STYLE_WHITELIST` — 39 properties, and why each earns its place

The cost is `nodes × props`, so this list is the stage's only real size knob. Pulling all of
`getComputedStyle` is ~340 properties per element and buries the signal in shorthand duplicates.

```js
const STYLE_WHITELIST = [
  // — geometry qualifiers: decide whether a box is REAL before it enters any histogram
  'display','position','visibility','opacity','transform',
  // — box: the spacing histogram (B1) and the shape language (B4)
  'margin-top','margin-right','margin-bottom','margin-left',
  'padding-top','padding-right','padding-bottom','padding-left',
  'gap','border-radius',
  // — overflow: the clipping detector (B7) needs BOTH axes; the shorthand is ambiguous
  'overflow-x','overflow-y','text-overflow','white-space',
  // — type (B2)
  'font-family','font-size','font-weight','line-height','letter-spacing','text-transform',
  // — colour (B3, B6)
  'color','background-color','background-image',
  // — stroke + elevation (B4)
  'border-top-width','border-top-color','box-shadow',
  // — stacking (B8)
  'z-index',
  // — ABSTENTION GUARD (§8). These five earn their place by preventing a FALSE PASS, not by
  //   producing a finding. Without them the contrast rule cannot tell a solid backdrop from a
  //   composited one, and it fails in the silent direction.
  'mix-blend-mode','backdrop-filter','filter','background-clip','-webkit-text-fill-color'
];
```

**39 entries: 34 that produce findings, 5 that prevent false passes.** The measured 32-property run
did not carry the guard five; every number in this doc that came from it is unaffected, because the
guard properties are read per *text run* (99 of 2,009 nodes) and contribute nothing to the histograms.

Four deliberate **omissions**, each with the reason it is safe:

- **`border-{right,bottom,left}-{width,color}`** — dropped. Asymmetric borders are rare enough that the
  4× cost is not worth it; the *presence* of a border is what B4 needs. If a repo turns out to use
  one-sided rules as a divider idiom, this is a one-line re-add. **UNVERIFIED for `reso-landing-app`**
  (purchased template) — one probe settles it: histogram `border-left-width` over one page and see
  whether any non-zero value exists that `border-top-width` does not already report.
- **`flex-direction` / `align-items` / `justify-content`** — dropped from the whitelist and **not
  replaced**. They describe *intent*; `bounds` describes *result*. Every alignment question this
  pipeline asks is answered by the edge histogram over `bounds`, which is true even when the flex
  properties lie (a `justify-content:center` inside an over-constrained parent).
- **`font-style`** — dropped; carried by `font-family` in practice and never load-bearing for a defect.
- **`outline*`** — dropped from the *page* pass. Focus-visible coverage requires driving `.focus()`
  per element and re-reading, which is a state pass (P2), not a snapshot field.

**Cost of the list as written:** 39 props. *(measured, at 32 props)* 707 KB raw, **246 B/node**. Adding
back the twelve omitted properties is ~+35 % raw bytes for zero measured findings — that is the trade
this list encodes.

---

## 4. The accessibility tree is a SEPARATE substrate, not a convenience

```js
const ax = await cdp.send('Accessibility.getFullAXTree');   // measured: 26.7 ms, 790 nodes
```

### 4.1 Why separate, stated as a rule

`captureSnapshot` answers **"where is this box and what does it look like"**. The AX tree answers
**"what is this thing, and what is it called"**. They are different questions with different failure
modes, and merging them into one table is how a pipeline starts believing that a valid a11y tree
implies a correct render. It does not: *a perfectly valid accessibility tree coexists with text
overlap, occlusion, and a button whose label is `undefined`.* Keeping them separate makes the
substrate of every finding nameable, which is what lets a disputed finding be re-argued against its
own source instead of re-litigated from scratch.

### 4.2 The join

`AXNode.backendDOMNodeId` → the snapshot's `documents[0].nodes.backendNodeId` → `layout.nodeIndex`
→ `layout.bounds`. This is the pipeline's governing rule made concrete: **the grounder supplies
identity, the DOM supplies geometry.** A model-produced bounding box is a ~68-mAP estimate of
something `bounds` returns exactly, for free, with no hallucination risk. **The judge is forbidden
from computing any distance from a box a model drew** — that rule is enforceable only because this
join exists.

`Accessibility.getFullAXTree` — not Playwright's `accessibility.snapshot()`, which filters to
"interesting nodes" and therefore silently changes the *denominator* of the touch-target census.

### 4.3 What the AX tree is used for, exhaustively

| | Use | Mechanism |
|---|---|---|
| AX1 | **Touch-target census** | `role ∈ {button,link,checkbox,textbox,menuitem,tab,switch,radio,combobox}` → join → `min(w,h)`. *(measured)* 36 of 72 interactive elements under 24 px on nextjs.org. |
| AX2 | **Unlabelled interactive elements** | `role` interactive **and** computed `name.value` empty ⇒ named in the fact-pack. This is one of the three defects blind Opus 5 found that no rule was looking for; it is trivially deterministic, so it moves out of the judge's queue. |
| AX3 | **Heading order** | `role:"heading"` + `level` in document order; a level skip (h1→h3) is a fact, and whether the *visual* hierarchy matches it is P6's question. |
| AX4 | **Element naming for every finding's `target`** | so a finding reads `the "Docs" nav link` rather than `main > nav > ul > li:nth-of-type(3) > a`. |
| AX5 | **`ignored:true` + non-zero bounds** | a visible box the AT cannot see. Emitted as a count, not a list. |

**Not used for:** anything perceptual, and anything about ordering-as-designed. AX3 gives the
*declared* hierarchy; whether the page *reads* in that order is the inverted-action-hierarchy class
that blind Opus 5 already catches 2/2.

### 4.4 Frames

`documents[]` beyond index 0 are iframes (cross-origin included; *(measured)* an `https://example.com/`
frame yielded 20 nodes). Default `--frames=merge`: frame nodes are extracted with their bounds
translated into top-document space and tagged `frame:<n>` in O2, but **frame nodes are excluded from
the B1/B2/B3 histograms**, because a third-party embed's spacing scale is not this app's and would
corrupt `onGridPct`. `--frames=strict` exits `5` instead, for callers who want to decide explicitly.

---

## 5. Paint order and stacking contexts

Both are the same call, `+0 ms`, and both are the *only* route to their data — nothing in the DOM API
exposes them, and the alternative is re-implementing CSS 2.1 Appendix E.

**`layout.paintOrders[i]`** — an integer per layout node. Used for exactly one thing: **ordering
rect-intersection pairs so "which is on top" is a fact, not an inference.**

🚨 **Raw overlap count is noise and must never be emitted.** *(measured)* **4,795 intersecting pairs
among the first 600 boxes** on a correctly built page. Boxes nest; that is what layout is. The signal
is the filtered predicate:

```
OCCLUSION(a, b) :=
     rectIntersect(bounds[a], bounds[b]) with IoU_of_smaller > 0.5
 AND both a and b have non-empty layout.text
 AND paintOrders[b] > paintOrders[a]
 AND b is NOT a declared overlay
       (b or an ancestor of b has position ∈ {fixed, absolute} AND an explicit z-index)
```

`IoU_of_smaller > 0.5` — half the smaller box covered. Below that, a text box clipping a neighbour's
margin box is ordinary. Above it, one text run is genuinely sitting on another. **UNVERIFIED: 0.5 is
reasoned, not measured.** One probe settles it: run the predicate at 0.3/0.5/0.7 across the 13-page
corpus and pick the value with zero hits on the control.

**`layout.stackingContexts`** (a `RareBooleanData` index list) — *(measured)* **1,274** on nextjs.org.
That count is not a finding either; a Tailwind page mints stacking contexts constantly. It is emitted
as `zorder.stackingContexts` only as a *denominator*, alongside the one derived fact that is
actionable: **a `position:sticky` element whose nearest ancestor stacking context is not its scroll
container** — which is the mechanism by which sticky headers silently stop sticking, and which is
invisible in both the computed styles and the screenshot of a page that happens to be scrolled to top.

---

## 6. THE REDUCTION — 707 KB → 854 tokens

This is the hard part of the stage. Our bench produced **73 KB of JSON for 46 elements**; nextjs.org
produces **707 KB for 2,009**. The output is **3,073 bytes**. That is a 230× reduction, and doing it
by "pick the interesting bits" is how a reducer silently deletes the finding.

### 6.1 The rule that decides — one sentence

> **A node is named only when it is an OUTLIER AGAINST THE PAGE'S OWN DOMINANT CONVENTION, or when it
> carries an abstention. Everything else becomes a distribution, and a distribution is emitted as its
> HEAD (which establishes the convention) plus its VIOLATORS (which break it). The middle is dropped.**

Two properties follow, and both are load-bearing:

1. **The comparison is internal, so a clean page produces a clean-shaped pack with zero named nodes.**
   Every threshold below is relative to the page's own mode. This is why the deterministic layer
   scores **0 false positives on the control** — a rule that fires on the control is overfitted, and
   its findings elsewhere are worth nothing.
2. **The tail of a design-system distribution IS the defect.** In a page built from tokens, a value
   used four times among two thousand is not a convention, it is a leak. So the reducer does not drop
   the tail to save bytes — it *promotes* it. Dropping the tail would be the one reduction that
   deletes exactly the signal.

### 6.2 The three tiers, and the filter that assigns them

**TIER A — DROPPED before anything counts it.** A node never reaches a histogram if any holds:

| Filter | Threshold | Why this number |
|---|---|---|
| zero-area | `w === 0 && h === 0` | not painted; contributes a phantom edge to the alignment histogram |
| invisible | `display:none` ∨ `visibility:hidden` ∨ `opacity < 0.01` | 0.01 not 0: `opacity:0.005` is an intentional invisible; `opacity:0` boxes are used as measurement shims |
| off-canvas | `bounds.x + w < 0` ∨ `bounds.y + h < 0` ∨ `bounds.x > cssContentSize.width` | the `left:-9999px` visually-hidden idiom would otherwise dominate `alignment.leftEdges` |
| non-app frame | `documents[n>0]` | a third-party embed's spacing scale is not this app's (§4.4) |
| script/style/meta | `nodeName ∈ {SCRIPT,STYLE,LINK,META,HEAD,TITLE}` | zero geometry, non-zero count |

*(measured, our corpus)* Tier A removes ~35–40 % of raw layout entries on a Tailwind page, entirely
from wrapper `<div>`s with no own paint.

**TIER B — AGGREGATED.** The survivor contributes one increment to each applicable histogram and is
then forgotten. This is where the 230× comes from: 1,200 surviving nodes × 34 properties collapse to
~9 distributions of ≤10 entries each.

**TIER C — NAMED.** The node is enumerated with an identifier the judge and a follow-up automation can
both use. Promotion is by exactly one of the six rules in §6.3; there is no editorial "this looks
interesting" path.

### 6.3 The six promotion rules — with per-axis thresholds and their reasons

🚨 **Rarity indicts an IDENTITY; off-scale indicts a MAGNITUDE.** A single frequency threshold across
all axes is the obvious design and it is wrong: on the measured page a 0.5 %-rarity rule flags
`font-family: Inter` (4 nodes against GeistSans's 1,978) — correct, that is a real token leak no human
finds by eye — but the same rule flags `font-size: 72px` (the hero, 5 nodes), which is not a defect at
all. A display size legitimately appears once; a font family never legitimately appears four times.

| | Axis | Promotion rule | Threshold + reason | Cap |
|---|---|---|---|---|
| **P1** | `font-family`, `color`, `background-color` (identities) | **rarity** — `count ≤ ceil(0.005 × axisTotal)` | 0.5 %: *(measured)* on nextjs.org this flags `Inter` (4/2,008) and nothing else, leaving `Geist Mono` (14) and `Georgia` (12) as legitimate conventions. A design system's leaks are 1–2 orders below its tokens, never within one. | 12 |
| **P2** | spacing (`margin/padding/gap`) | **off-grid** — `v % gridBase !== 0` | `gridBase` = the largest of `{8,4,2}` whose adherence ≥ **70 %**. *(measured)* nextjs.org is 78.5 % on 4 and 49.6 % on 8 ⇒ base 4. Below 70 % no grid is named at all (`gridBase:null`) — asserting a grid a page does not have tells the judge something false. | 12 |
| **P3** | `font-size`, `border-radius` (magnitudes) | **off-scale** — value not within 2 % of any member of the dominant ratio series fitted to the top-5 sizes by count | 2 %: below the rounding noise of `rem`-based scales at 16 px root; a `1.25` scale from 16 px yields 20/25/31.25 and a 31 px authored value must not read as a violation. | 8 |
| **P4** | alignment edges | **near-miss** — a box whose left (or right) edge is **1–3 px** from a bin holding ≥ 3 boxes, but not in it | lower bound **1 px**: below it is device-scale rounding — *(measured)* a control authored at exactly 44 px reads 44.0 pinned and 43.x unpinned. Upper bound **3 px**: beyond that it is a deliberately different column, not a mistake. **This near-miss test is the detector; the histogram is only its denominator.** | 10 |
| **P5** | contrast | **WCAG 2.1 fail** (`< 4.5:1`, or `< 3.0:1` for ≥ 24 px / ≥ 18.66 px bold) **or abstention** | 4.5/3.0 are the standard's own numbers and are the only *binary* gate here. **APCA `Lc` rides along as a continuous scalar and gates nothing** — *(measured)* wiring `fontLookupAPCA` as pass/fail flagged **66 of 99** runs against WCAG's 13, with 53 outright disagreements. It is a use-case guidance table, not a conformance gate; as a gate it manufactures a ~5× false-positive rate on a competently designed site. | 8 + all abstentions |
| **P6** | touch targets | `min(w,h) < 44 − 0.75` | 44 px is the WCAG 2.5.5 AAA figure. The **0.75 px band** exists because rendered geometry is fractional: without it a control authored at exactly 44 px flips to a defect when the capture config changes. | 8 |

**Cap semantics — and the one thing that is never capped.** Each cap truncates by *severity, then
magnitude*, and sets `"truncated": {"<axis>": <n_omitted>}` so the judge knows it is seeing a sample.
**`abstentions` is uncapped and is never truncated**, because an abstention that gets dropped for
budget silently becomes a pass, and a pass routes nowhere.

### 6.4 The token budget, made auditable

| Block | Tokens | What it costs if dropped |
|---|---|---|
| `meta` + `determinism` | ~60 | every geometric finding becomes unarguable |
| `spacing` | ~90 | judge re-derives the grid by eye, badly |
| `type` | ~120 | the family leak is invisible |
| `palette` | ~130 | token conformance moves to the judge, which is the one thing it must never do |
| `shape` | ~80 | radius/shadow drift |
| `alignment` | ~70 | the near-miss list — the sub-perceptual class Opus 5 scores 0/2 on |
| `contrast` | ~110 | ditto |
| `targets` | ~70 | the smallest-hit-target finding |
| `clipping` + `zorder` + `ax` | ~80 | overflow and occlusion |
| `abstentions` | ~40 | **the vision stage loses its job queue** |
| **total** | **~850** | vs a 1440×900 PNG at **1,100–1,600** |

🚨 **Hard ceiling: 1,100 tokens.** The *entire* justification for handing the judge this pack is that
it costs less than the image it accompanies. A pack that outgrows its own screenshot has lost its
argument. On breach the reducer truncates **histograms first** (compressible — the head still
establishes the convention), then **capped violator lists**, and **never abstentions**. It emits
`"overBudget": true` rather than silently exceeding, because the alternative is a stage that quietly
inverts its own cost claim.

---

## 7. O1 — the exact schema, filled

Values are the real `nextjs.org` extraction *(measured)* except `contrast.abstentions[0]`, which is the
real gradient page from our 13-page corpus, spliced in because nextjs.org has no gradient text and the
abstention path must be shown filled rather than empty.

```jsonc
{
  "schema": "design-perceive/1", "stage": "extract",

  "meta": {
    "url": "https://nextjs.org/", "slug": "home",
    "viewport": {"w":1440,"h":900}, "dpr": 2, "raster": [2000,1250],
    "cssContentSize": {"w":1440,"h":3488},
    "capturedAt": "2026-08-26T07:20:20.223Z", "extractMs": 53,
    "layoutNodes": 2009, "retained": 1237, "frames": 1,
    "determinism": { "forcedDeviceScaleFactor": 2, "reducedMotion": true,
                     "fontsReady": true, "colorProfile": "srgb", "lcdText": false },
    "budget": { "tokens": 854, "ceiling": 1100, "overBudget": false },
    "truncated": {}
  },

  // B1 — every margin/padding/gap > 0, histogrammed. gridBase is INFERRED, not assumed.
  "spacing": { "distinct": 26, "gridBase": 4, "gridBaseConfidence": 0.785,
               "histogram": {"4":128,"8":116,"24":94,"16":72,"12":71,"10":49,"6":38,"32":34,"3":12,"1.2":24},
               "offGrid": [1.2,2,3,6,10,14,18,19,21,25] },

  // B2 — sizes/weights are MAGNITUDES (off-scale rule P3); families are IDENTITIES (rarity rule P1).
  "type": { "sizes": {"16":1618,"14":197,"20":73,"13":60,"24":31,"32":7,"11":6,"72":5,"12":4,"18":4,"40":3},
            "weights": {"400":1868,"600":97,"500":43},
            "lineHeights": {"26.4px":1619,"20px":84,"23.1px":59,"21.45px":40},
            "families": {"GeistSans":1978,"Geist Mono":14,"Georgia":12,"Inter":4},
            "familyLeaks": [{"value":"Inter","count":4,"share":0.002,
                             "nodes":["footer > div > p:nth-of-type(2)"]}],
            "offScaleSizes": [] },

  // B3 — the whole check is a set-difference against the token file. Near-misses get ΔE2000.
  "palette": { "distinctTotal": 33,
               "textColors": {"rgb(23, 23, 23)":1615,"rgb(102, 102, 102)":166,"rgb(255, 255, 255)":85,"rgb(17, 17, 17)":35},
               "backgrounds": {"rgb(255, 255, 255)":200,"rgb(50, 145, 255)":180,"rgba(0, 0, 0, 0.6)":16},
               "tokenDiff": { "tokenFile": "src/styles/tokens.css", "matched": 29, "unmatched": 4,
                              "drift": [{"observed":"rgb(26,26,26)","nearestToken":"neutral-900",
                                         "tokenValue":"rgb(23,23,23)","deltaE2000":1.03,
                                         "verdict":"sub-threshold-drift","count":3}] } },

  // B4
  "shape": { "radii": {"0px":1343,"9999px":477,"2px":79,"100px":22,"12px":21,"6px":17,"4px":10},
             "offScaleRadii": [],
             "shadows": {"rgba(0,0,0,0.03) 0px 0px 0px 1px, rgba(0,0,0,0.06) 0px 12px 24px 0px":11} },

  // B5 — the histogram is the DENOMINATOR; nearMisses is the detector.
  "alignment": { "sharedLeftEdges_ge3": 142,
                 "leftEdges": {"120":27,"145":28,"221":24,"550":22},
                 "rightEdges": {"218":26,"230":25,"1320":23},
                 "nearMisses": [{"axis":"left","edge":121,"bin":120,"deltaPx":1.0,"binMembers":27,
                                 "node":"main > section:nth-of-type(3) > div.card:nth-of-type(2)",
                                 "name":"Deploy card"}] },

  // B6 — operands come from blendedBackgroundColors, MULTIPLIED THROUGH textColorOpacities.
  "contrast": { "measured": 99, "indeterminate": 1, "wcagFailures": 13,
                "apcaLcRange": [-107.6, 106.4],
                "worst": [{"fg":"rgb(0,114,245)","bg":"rgb(255,255,255)","px":16,"weight":400,
                           "wcag":4.44,"required":4.5,"apcaLc":69.9,"pass":false,
                           "node":"main > nav > a:nth-of-type(2)","name":"Learn"}],
                "abstentions": [
                  {"reason":"backdrop-varies","backdropKind":"linear-gradient",
                   "declaredOn":"section.hero",
                   "node":"section.hero > h1","name":"Ship faster",
                   "fg":"rgb(255,255,255)","blendedReported":"rgb(30,58,138)",
                   "blendedWouldGive":10.36,
                   "claim":"cannot compute a ratio: the backdrop is a gradient, so no single colour is the operand. WCAG 4.5:1 is UNVERIFIED for this text.",
                   "routeTo":"P5-XCHECK","bbox_css":[0,148,1440,72]}
                ] },

  // B9 — role from the AX tree, box from the snapshot. Never the other way round.
  "targets": { "total": 72, "under44": 61, "under24": 36,
               "smallest": [{"role":"link","name":"Docs","w":33,"h":20,
                             "node":"header > nav > a:nth-of-type(1)"}],
               "unlabelled": [{"role":"button","name":"","w":24,"h":24,
                               "node":"header > button.icon"}] },

  // Emitted only when non-empty.
  "clipping": [{"node":"header > nav > a:nth-of-type(3)","name":"Showcase",
                "scroll":[76,23],"client":[66,23],"overflowX":"hidden","verdict":"silently-truncated"}],
  "zorder":   {"stackingContexts":1274,"explicitZIndex":{"2":17,"3":17,"1":10,"1000":4},
               "occlusions":[], "stickyOutsideScrollParent":[]},
  "ax":       {"nodes":790,"headingOrder":[1,2,2,3,2,3,3],"headingSkips":[],"ignoredVisible":4},

  "cannotAnswer": ["canvas:1","background-image:6","svg:41","video:0"]
}
```

**`cannotAnswer` is not a diagnostic; it is a contract clause.** It counts the nodes whose *interiors*
are structurally unreachable from here — one `<canvas>` contributing a width and a height, six
`background-image` URLs that are strings, forty-one SVG subtrees whose stroke-weight coherence is
unmeasurable. The judge is told, in its own input, exactly where the deterministic layer has nothing
to say, so that silence in this pack is never readable as absence of defect.

---

## 8. THE ABSTENTION RULE — how `blendedBackgroundColors` is prevented from becoming a false pass

### 8.1 The trap, measured

`includeBlendedBackgroundColors` returns the **compositor's own** answer to "what is actually behind
this text", resolved through arbitrary nesting, opacity and `mix-blend-mode`. Every JS contrast
checker approximates this by walking ancestors and gets it wrong on overlap. It is strictly better
than what it replaces — *and adopting it naively makes this pipeline worse.*

It samples **one colour per text run**. On our gradient page it returned `rgb(30, 58, 138)` — the
gradient's **leftmost stop**:

| Sample point | Contrast vs white | Verdict |
|---|---|---|
| left stop `#1E3A8A` — **what CDP reported** | **10.36:1** | PASS |
| mid `#3B82F6` | 3.68:1 | FAIL |
| right `#DBEAFE` — **where the text actually sits** | **1.22:1** | FAIL |

A nine-point swing across a single text run, and the scalar reports the passing end. **The failure is
not that the number is wrong. It is that adopting it converts an honest `INDETERMINATE` into a
confident PASS, and an abstention routes to a stage that can answer while a pass routes nowhere.**
This is `fail-safe-default-mimics-the-healthy-state` exactly: the rule gets *better* on solid and
layered backdrops at the same moment it goes blind on varying ones, so the improvement hides the
regression.

### 8.2 The rule — colour from the compositor, KIND from the cascade

The ancestor walk is precisely what `blendedBackgroundColors` replaces, and this rule re-adds it — for
a different question. **The walk never computes the colour** (it is worse at that). It classifies the
backdrop's *kind*, and the two readings must agree before a number is emitted.

```
BACKDROP(t) for a text-carrying layout node t:

  1. blended := layout.blendedBackgroundColors[t]
     if blended is absent or -1:                       -> INDETERMINATE("no-blended-sample")
        // NOT a failure. (measured) only 99 of 2,009 entries are populated -- boxes that
        // actually paint text. Sparsity is by design; reading it as an error is the T2 trap.

  2. Walk t and its ancestors, max depth 12, stopping at the first opaque background-color.
     Return INDETERMINATE on the FIRST of these seen anywhere on that chain:
        background-image      != 'none'   -> "backdrop-varies"        (gradient OR url())
        mix-blend-mode        != 'normal' -> "backdrop-composited"
        backdrop-filter       != 'none'   -> "backdrop-filtered"
        filter                != 'none'   -> "backdrop-filtered"
        background-color alpha in (0, 0.99]  -> "backdrop-semi-transparent"
     Also on t itself:
        background-clip: text  OR  -webkit-text-fill-color: transparent
                                          -> "foreground-varies"  (gradient TEXT: no single fg either)

  3. If the walk reached the document canvas with no opaque stop -> SOLID(rgb(255,255,255)).
  4. Otherwise                                                    -> SOLID(blended).
     // The COLOUR is the compositor's, never the walk's. The walk only earned the right to use it.

  5. Multiply the foreground through layout.textColorOpacities[t] BEFORE any ratio.
     (opacity:.6 text passes contrast on paper and fails on screen.)
```

**Depth cap 12** — a chain deeper than twelve backgroundless ancestors is a wrapper stack, not a
design decision; the cap bounds the walk without changing any measured verdict.
**Alpha cut 0.99, not 1.0** — `rgba(255,255,255,0.995)` from a fade animation is opaque in every
practical sense, and treating it as semi-transparent would abstain on half a page mid-transition.

### 8.3 What an abstention IS, downstream

An abstention is a **routed work item**, not a null. Every one carries `routeTo`, the bbox that P4-CROP
needs, and `blendedWouldGive` — *the number this stage refused to publish* — so P5 can state the
disagreement rather than re-derive it from nothing.

| `reason` | `routeTo` | What that stage does |
|---|---|---|
| `backdrop-varies` | **P5-XCHECK** | samples the rendered backdrop in the left and right thirds of the run: *(measured)* **4.81:1 left, 1.57:1 right** — turns "unrepresentable" into two numbers and a verdict, with **no VLM call and zero findings on the control** |
| `foreground-varies` | **P5-XCHECK** | same sampling, ink side |
| `backdrop-composited` / `backdrop-filtered` | **P5-XCHECK** | pixel sampling is the only operand that exists |
| `backdrop-semi-transparent` | **P5-XCHECK** | ditto |
| `no-blended-sample` | **P3, per-crop** | re-extract at crop scope (§9); if still absent, escalate to P5 |

🚨 **`backdrop-varies` covers `url()` as well as gradients, and that is deliberate.** A raster backdrop
is *more* variable than a gradient, not less, and the same scalar-cannot-represent-it argument applies
with more force. Splitting them would create a class where a single sampled colour looks defensible.

### 8.4 The invariant a test must pin

> For every text node, **exactly one** of `contrast.worst[]`, `contrast.passes` (a count) and
> `contrast.abstentions[]` claims it. `measured + indeterminate === textRuns`.

Assert it on every run and fail the extract on breach. Without this, the reducer's caps (§6.3) can
drop a text node out of both lists, and a node claimed by neither reads as a pass.

---

## 9. Per-page vs per-crop — what is re-extracted

P4-CROP clips to **≤ 1000×1000 CSS px @ DPR 2** (= ≤ 2000×2000 raster), because that is the only
desktop configuration that is lossless end to end through Claude Code's 2000 px / 3.75 MiB clamp. A
2500 px-tall full-page shot delivers **0.80× effective detail — worse than a plain 1× viewport shot at
any DPR.** Crop-refinement is also the largest single measured lever in this whole pipeline:
ScreenSeekeR took a model **18.9 % → 48.1 %** on ScreenSpot-Pro with no model change.

**The governing rule: geometry is captured once; anything whose operand is a PIXEL is per-crop.**

| | Quantity | Once per page | Per crop | Why |
|---|---|---|---|---|
| R1 | `captureSnapshot` itself | ✅ | ❌ | CSS px are DPR- and clip-independent, and the document-wide dump already includes below-the-fold *(measured max layout Y 3,488 px vs a 700 px viewport)*. **Re-snapshotting per crop is pure cost and adds a real risk** — a scroll or resize between crops fires IntersectionObserver reveals and you would be describing a different page than the one photographed. |
| R2 | AX tree | ✅ | ❌ | identity does not change with the viewport |
| R3 | B1/B2/B3/B4 histograms | ✅ | ❌ | a crop's spacing distribution is a biased sample of the page's; recomputing per crop would invent a different "convention" in every crop and make the off-grid rule meaningless |
| R4 | `bbox_raster` for every named node | ❌ | ✅ | `bbox_raster = (bbox_css − clipOrigin) × dpr`. Pure arithmetic from R1, **no browser call.** The model reasons in the coordinate space of the image it was shown; two fields are cheaper than one wrong conversion. |
| R5 | Alignment near-misses | ✅ | ✅ (re-*filtered*) | bins are computed page-wide (R3), but the crop's pack lists only near-misses whose bbox intersects the clip — otherwise the judge is handed coordinates outside its own image |
| R6 | `CSS.getPlatformFontsForNode` | ❌ | ✅ | **2.17 ms/node** — unaffordable page-wide, and nothing else detects **silent font fallback** (the computed `font-family` is a *request*, the resolved font is the *result*). Run it on the ≤ 20 text nodes inside the crop. |
| R7 | `CSS.getMatchedStylesForNode` + `getLayersForNode` | ❌ | ✅ | answers *which authored rule set the off-token value* — the fix location, not the symptom. Per-node cost; only ever run on a node already named by §6.3. This is what makes a finding **actionable by an agent that edits source**, which is our actual consumer. |
| R8 | Focus-visible | ❌ | ❌ | needs `.focus()` + re-read — a state pass, owned by **P2** |

**Crop packs are ≤ 300 tokens** and carry `"scope":"crop"`, `"clip":[x,y,w,h]`, the R4/R5/R6/R7
results, and a back-pointer `"pagePack":"<path>"`. They **never repeat the page histograms** — the
judge already has them, and repeating them per crop is how a 854-token pack becomes a 4,000-token one
across six crops and loses its cost argument.

---

## 10. Token-source resolution, per app — and where the pack must admit it has no answer

`palette.tokenDiff` is the highest-value field this stage produces for one of the three apps and is
**meaningless for another**. Emitting the same shape for both is how a check becomes theatre.

| App | Token source *(verified on disk today)* | `tokenDiff` behaviour |
|---|---|---|
| **reso-management-app** (Next 16 / React 19 / Tailwind 4) | **Panda CSS** `styled-system/tokens/index.mjs` **plus** a 1,221-line `src/app/globals.css` whose `:root` carries hand-authored semantic vars (`--mc-header-content-gap: 1.5rem`) | **full diff, and it is the primary output.** Design-system conformance is this app's entire review question. Read the Panda token object *and* the `:root` custom properties; a value matching neither is drift. |
| **reso-landing-app** (Next 14, purchased template) | `tailwind.config.js` extends **only** `fontFamily.sans` and `borderRadius.4xl` — i.e. the palette is stock Tailwind, not a curated set | **`tokenDiff: null`, explicitly.** Diffing against the full default Tailwind palette would match nearly everything and report a conformance the app has never claimed. Emit `"tokenDiff": null, "reason": "no curated token set"` — the pack must say the check did not run. |
| **reso-web-app** (Next 13) | no Tailwind config, no token module found at depth 3 | **`tokenDiff: null`.** `palette.distinctTotal` alone is the finding here: a high distinct count against a low histogram head *is* the absence of a system, and that is a fact the judge can act on. |

🚨 **A `null` here is a first-class value, not an error.** The alternative — quietly diffing against
whatever file happened to exist — produces a confident conformance number for an app that has no
conformance target. Same shape of defect as §8.

---

## 11. Three traps that produce wrong numbers, and the guard for each

| | Trap | Measurement | Guard in this stage |
|---|---|---|---|
| **T1** | `bounds` is **post-transform document space**, and `offsetRects`/`clientRects`/`scrollRects` are **not always populated** | a `rotate(15deg) translateX(40px)` box reports `bounds:[48.8,53.1,84,38.7]` (the transformed AABB) while `offsetRect` and `clientRect` came back `[]` | Alignment (B5) and occlusion (§5) read **`bounds` only**. Clipping (B7) reads the DOM-rect arrays and **skips any node whose arrays are empty**, counting the skip into `clipping.unmeasurable` rather than treating an empty array as "no overflow". |
| **T2** | `blendedBackgroundColors` is **sparse by design** | **99 populated of 2,009** layout entries — only boxes that actually paint text | Index by layout index, skip `-1`, and route sparsity to `INDETERMINATE("no-blended-sample")` (§8.2 step 1). **Never read sparsity as failure and never read it as pass.** |
| **T3** | CSS rule-usage tracking must be **armed before navigation** | calling `CSS.startRuleUsageTracking` after load returned **591 rules tracked, 591 used, 0 % unused** — an artifact, not a result | Dead-CSS is **out of scope for P3 v1**. If added: enable `DOM` + `CSS`, start tracking, *then* `Page.navigate` — which makes it a P2 concern, not a P3 one, because P3 never navigates. |

---

## 12. UNVERIFIED — and the one probe that settles each

| | Claim | Why it is not yet knowable | The one probe |
|---|---|---|---|
| U1 | `IoU_of_smaller > 0.5` is the right occlusion threshold | reasoned from "half the smaller box covered", never measured | Run the §5 predicate at 0.3 / 0.5 / 0.7 across the 13-page corpus; take the largest value with **zero** hits on the clean control. |
| U2 | `gridBase` adherence floor of 70 % separates real grids from fictional ones | one data point *(nextjs.org: 78.5 % on 4, 49.6 % on 8)* | Histogram `onGridPct` at bases 2/4/8 across all three reso apps plus the corpus; a bimodal split confirms the floor, a smear refutes it. |
| U3 | The 0.5 % rarity rule generalises off nextjs.org | it flags exactly `Inter` there, which is the right answer — but n=1 | Run P1 over `reso-management-app`, where the Panda token file gives independent ground truth for which families/colours are sanctioned. Precision/recall against that file is a real number. |
| U4 | Dropping `border-{right,bottom,left}-*` is safe | reasoned; a one-sided-rule divider idiom would refute it | Histogram `border-left-width` on one page of each app; a non-zero value that `border-top-width` does not already report means re-add. |
| U5 | The pack stays under 1,100 tokens on a dense app | measured on nextjs.org (854). `reso-management-app` has more distinct semantic vars and may have a longer palette tail | Run extract on the management app's busiest route and read `meta.budget.tokens`. If it breaches, the fix is the §6.4 truncation order, already specified. |
| U6 | Opus 5 is in the high-resolution image tier | the docs say "Claude 4.7 and later"; Opus 5 is later, so the inference is safe but not stated | Send one 2000×1250 PNG with `transformations:{"oversized_image":"error"}` and read whether it errors at 1568 or passes at 2576. **If it fails, the ≤1000×1000 CSS px crop rule (§9) becomes *more* right, not less.** |

---

## 13. Where this stage sits against the standing ruling

The June 2026 ruling binds: **taste stays human; gates adjudicate correctness and coverage only.**

**EXTRACT is the one stage in this pipeline whose output MAY block CI**, and that is not an exception
to the ruling — it is the ruling applied. Everything here is arithmetic: a WCAG ratio, a target
dimension, a token set-difference, an overflow inequality. None of it is taste. *(measured)* the
deterministic layer scores **9/9 on DOM-determined defects at ~80 ms/page with 0 false positives on the
control**, which is what a gate needs to be.

Two clauses keep it inside the ruling:

1. **Only `contrast.worst[]` (WCAG 2.1 binary), `targets` and `clipping` are gateable.** `spacing`,
   `type`, `palette`, `shape` and `alignment` are *advisory context for the judge* — an off-grid value
   is a fact, not a violation, and gating on `onGridPct` would be gating on taste wearing a number's
   clothes. `apcaLc` gates nothing, ever (§6.3 P5).
2. **An abstention never gates.** It routes. A stage that blocked CI on "I could not compute this"
   would convert every gradient hero into a build failure.

The judge's output — hierarchy, rhythm, grouping, optical alignment, content fit — remains **advisory
triage** and re-adopting it as a blocking gate contradicts a ratified decision. This pack is what makes
that division affordable: it hands the judge the numbers so the prompt can say *"the numbers are given;
do not re-derive them, and do not comment on spacing adherence, contrast ratios, target sizes or
palette membership except to interpret what is stated."* That is an 854-token investment that removes
an entire class of failure, and it is cheaper than the screenshot it rides beside.
