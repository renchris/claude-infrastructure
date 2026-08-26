# P2 · DECOMPOSE — one full-page capture → the right set of crops

**Stage owner:** `bin/cv-decompose` (plain CLI, writes JSON + PNG to disk; no MCP — see README §8).
**Upstream:** P1 CAPTURE (raster + capture manifest) and P0 FACTS (`DOMSnapshot.captureSnapshot`
fact-pack + deterministic findings incl. the `INDETERMINATE` set).
**Downstream:** P3 JUDGE (the Opus 5 prompt) and P4 ADJUDICATE (cross-check / FP budget).
**Status:** specification. Nothing here is built yet. Every threshold below carries its derivation.

---

## 1. Contract

### 1.1 Inputs (all required unless marked)

```jsonc
// --capture <dir>  — produced by P1, one directory per (route, breakpoint)
{
  "manifest.json": {
    "url": "http://localhost:3000/dashboard",
    "app": "reso-management-app",
    "viewport": { "w": 1440, "h": 900 },       // CSS px
    "dpr": 2,                                  // == --force-device-scale-factor, pinned both sides
    "scale_mode": "device",                    // R2: without this deviceScaleFactor is DISCARDED
    "playwright": "1.60.0", "channel": "chromium",
    "color_profile": "srgb",
    "stability": { "sha_a": "…", "sha_b": "…", "equal": true },  // capture-twice gate
    "scroll": { "w": 1440, "h": 3488 },        // document CSS px, from Page.getLayoutMetrics().cssContentSize
    "shots": { "fullpage_dpr1": "shots/full@1x.png" }
  },
  "snapshot.json": {                            // bench/capture.py shape, verbatim
    "url": "…", "title": "…",
    "scroll": { "w": 1440, "h": 3488 },
    "elements": [ { "path": "main > div.card:nth-of-type(2)", "tag": "div",
                    "classes": ["card"], "text": "Revenue",
                    "rect": { "x": 24, "y": 1180, "w": 432, "h": 212,
                              "right": 456, "bottom": 1392 },
                    "scroll": { "h": 212, "ch": 212, "w": 432, "cw": 432 },
                    "styles": { "display": "flex", "…": "…" } } ]
  },
  "findings_dom.json": [ { "rule": "contrast", "verdict": "INDETERMINATE",
                           "target": "section.hero > p", "why": "backdrop is a gradient" } ],
  "findings_xcheck.json": [ /* optional; present ⇒ its own hits are duty regions */ ]
}
```

`--out <dir>` · `--budget <n>` (default 12) · `--wave <n>` (default 1) ·
`--saliency none|umsi` (default `none`; `umsi` blocked on licence, §4.3) ·
`--baseline <dir>` (optional prior accepted capture of the same route).

### 1.2 Outputs

```
<out>/
  plan.json          # the crop plan + delivery order + per-crop caption text
  index.png          # ONE whole-page structural image, ≤2000 px long edge  (§6)
  crops/c01.png …    # one PNG per crop, each provably inside the Read ladder
  decompose.log      # every threshold that fired, with its value
```

`plan.json`:

```jsonc
{
  "schema": "cv-decompose/1",
  "page": { "url": "…", "css": { "w": 1440, "h": 3488 }, "dpr": 2 },
  "block_budget": { "cap": 16, "spent": 13, "reserved_for_zoom": 3 },
  "phases": [
    { "phase": "global", "images": ["index.png"], "ask": "…" },   // asked and FROZEN first
    { "phase": "local",  "images": ["crops/c01.png", "…"] }
  ],
  "crops": [
    { "id": "c01", "kind": "duty",                                  // duty | context | seam | zoom
      "css": { "x": 0, "y": 1120, "w": 960, "h": 640 },
      "scale": 2.0, "raster": { "w": 1920, "h": 1280 }, "bytes": 812345,
      "eff": 2.00, "subpixel_verdicts_allowed": true,
      "band": { "index": 3, "role": "main", "of": 6 },
      "page_fraction": [0.321, 0.504],
      "neighbours": { "above": "header/kpi-row", "below": "main/table" },
      "contains": ["main > div.card:nth-of-type(2)", "…"],
      "reason": { "generator": "G1", "finding": "contrast INDETERMINATE on section.hero > p" },
      "caption": "CROP c01 — …",                                   // §6.2, pasted verbatim by P3
      "parent": null, "depth": 0 }
  ],
  "uncovered": [],           // elements ≥24×24 CSS px in NO crop — MUST be empty on success
  "truncated": { "is": false, "remaining": 0 },
  "degraded": []             // e.g. ["saliency:absent → CV surrogate ranking"]
}
```

### 1.3 Failure modes — exact, each with an exit code

| Code | Name | Trigger | Behaviour |
|---|---|---|---|
| 3 | `E_MANIFEST_MISMATCH` | `manifest.dpr` absent, or `≠` the context `deviceScaleFactor`, or `scale_mode≠"device"`, or `stability.equal≠true`, or `manifest.scroll ≠ snapshot.scroll` | **Refuse. Emit nothing.** An unpinned display scale injects 1.5 px of accumulated drift over four paragraphs (A9 §5) and every geometric finding downstream inherits a phantom offset. There is no partial-credit mode. |
| 4 | `E_OVERSIZE` | any rendered PNG has `w>2000 ∨ h>2000 ∨ bytes>3 932 160` | **Hard fail on that crop, do not write it.** Over the cap, Claude Code palette-quantises to 256 colours or JPEGs at q80→q20 *silently* (`tengu_image_resize`, never surfaced). A crop the resizer touched is not the crop we measured. |
| 5 | `E_DUTY_UNCOVERED` | a duty region cannot be contained by any crop inside the envelope (element wider than 2000 CSS px — a horizontally scrolling table) | Emit the crop at reduced `scale`, set `subpixel_verdicts_allowed: false`, and record it in `degraded[]`. Never silently drop. |
| 6 | `E_BUDGET_EXCEEDED` | duty regions alone exceed `--budget` | Emit the top-`budget` by priority, set `truncated:{is:true,remaining:N}`. The caller must fire wave 2 **in a fresh context** (§5.2). |
| 7 | `E_BLANK_DUTY` | a duty crop's ink density < 0.5 % of pixels | Escalate, do not drop: a blank duty region means P1's scroll-priming failed (naive `fullPage` fired 1 of 8 `IntersectionObserver` reveals — A9 §4e). This is a capture bug wearing a decomposition bug's clothes. |
| 0 | success | `uncovered == []` and every crop passed the ladder gate | |

**The gate that makes this stage trustworthy is `uncovered`.** It is a mechanical, checkable
post-condition: for every element in `snapshot.elements` with `rect.w ≥ 24 ∧ rect.h ≥ 24`
(WCAG 2.2 SC 2.5.8 Target Size (Minimum) — below it an element is inline/decorative and its parent
carries the geometry), there must exist a crop whose CSS rect fully contains it. If that set is
non-empty the plan is incomplete and the stage says so in the artifact rather than in prose.

---

## 2. What defines a region worth cropping

**A crop is a unit of judgement, not a unit of layout.** That single reframing settles most of the
design. The page is not being tiled because it is big; it is being cut so that each image asks the
judge exactly one answerable question at a resolution where the answer exists.

Three generators propose regions. They are ordered, they are not peers, and only one of them is
allowed to decide *membership*.

### 2.1 G1 — DUTY regions (obligatory, decide membership)

The reason the vision layer is being called at all. Source, in priority order:

| Priority | Source | Why it is a duty |
|---|---|---|
| 100 | `findings_dom.json[].verdict == "INDETERMINATE"` | The deterministic layer's most valuable output is an abstention. *"contrast-indeterminate: backdrop is a gradient, 4.5:1 is UNVERIFIED"* routes here by construction (README §2 seam). The abstention set **is** the vision layer's job queue. |
| 90 | `findings_xcheck.json[]` hits | Where the DOM's claim and the pixels disagree by more than a stated tolerance. A disagreement needs an eye to say which side is right. |
| 80 | Elements the DOM cannot reason about at all: `background-image` present, `backdrop-filter`, `mix-blend-mode`, `<canvas>`, `<svg>` with ≥1 `<text>`, `filter: blur()` | The styles are correct and the render may still be wrong. No rule reaches these. |
| 70 | Text runs where `blendedBackgroundColors` resolved over a gradient/image chain | Explicitly kept as an abstention rather than adopted as a scalar. Adopting it naively turns an honest INDETERMINATE into a confident false PASS — the measured 10.36:1-reported / 1.22:1-actual swing (README §2). |
| 60 | Interactive elements with no accessible name, and any element that is the *smallest* target on the page | Blind Opus 5 found exactly this class unprompted (unlabelled icon button, smallest hit target). Cheap to route, measured productive. |

A duty region's rect is the union of the finding's target rect and its **nearest ancestor whose
`rect.w ≤ 1000 ∧ rect.h ≤ 1000`** — because a defect in isolation is unjudgeable. *"Is this text
washed out"* needs the surrounding surface in frame; a 200×24 crop of the text alone shows a judge
a grey rectangle and no context to call it wrong against.

### 2.2 G2 — STRUCTURE regions (the MECE cover, decide completeness)

Duty regions are sparse and a page with zero abstentions still needs reviewing — that is where the
three real defects nobody injected came from. So the page is *also* partitioned, exhaustively.

**Bands, cut at whitespace, validated against the DOM.**

1. Compute the horizontal projection profile of the full-page raster: binarise against the modal
   page background, `ink = binary.sum(axis=1)`, one value per raster row. ~2 ms of pure NumPy
   (A5 C4). Valleys with `ink == 0` are candidate cut lines; runs of zero rows are gutters.
2. Reject any candidate `y` that **strictly straddles an element**: `∃ e: e.rect.y < y < e.rect.bottom`
   and `e` is not a full-bleed container (`e.rect.w ≥ 0.98 × page.w`). Cutting through a card is how
   a straddling defect is created rather than merely risked, and the fact-pack makes the check exact.
   *This is the braces; overlap (§4.1) is only the belt.*
3. Prefer cut lines that coincide (±8 CSS px, one Tailwind spacing unit) with the boundary of a DOM
   landmark — `header`, `nav`, `main`, `aside`, `footer`, `section`, `[role]` — and label the band
   with that landmark's role. The label is what makes §6.2's caption meaningful.
4. Cut greedily from `y=0`, taking the **widest admissible gutter within `[0.55·H_max, H_max]`** of
   the running position, where `H_max = 1000` CSS px (the lossless envelope, §3). If no admissible
   gutter exists in that window, cut at `H_max` and record `forced_cut: true` — that band's crop is
   the one place a straddle is possible, so it is where §4.2's seam pass is guaranteed to fire.

Bands are a MECE cover of `[0, scroll.h)`. They are the *substrate* of the crops, not the crops:
a 1440-CSS-wide band is still too wide for the envelope, and §3 splits it.

### 2.3 G3 — ATTENTION (ranking only, never membership)

Ranking decides which bands survive the budget when duty + structure exceeds it. It must never
decide whether a region *can* be seen, because a ranker that removes a region removes it silently.

Default ranker, no model, no licence (A5 §295 composition):

```
priority(band) = 40·ink_density_z + 30·isolation_z + 20·max_local_contrast_z + 10·interactive_count_z
```

where `isolation` is the mean of the distance transform of the inverted binary inside the band
(the widest whitespace channel around its content — emphasis, quantified), and `_z` is a z-score
across that page's bands so the weights are scale-free.

`--saliency umsi` replaces the first three terms with UMSI++ attention mass. It is **the one
specialist worth buying** — CC 0.833 vs the best frontier VLM at 0.408 on the same test set, and the
mechanism (early gaze is pre-semantic) explains the gap rather than merely reporting it. It is
**not the default and must not become one until the licence is resolved** (UEyes repo,
`YueJiang-nj/UEyes-CHI2023`, no licence file). When absent, `degraded[]` records
`"saliency:absent → CV surrogate ranking"` so a downstream reader can see which ordering produced
the plan.

### 2.4 Diff-against-baseline is a MULTIPLIER, never a generator

`--baseline` is used only as `priority × 1.6` for bands whose pixel diff against the prior accepted
capture exceeds `maxDiffPixelRatio 0.002`. It is deliberately **not** allowed to select or deselect
a region.

Reason, measured: the pixel-VRT lane that shipped in this fleet caught **0 of 6** real bugs
prospectively (README §7). Regression-lock is not prospective detection. A decomposition that only
crops what changed inherits that blindness completely on the first-ever review of a route, which is
the review that matters most. The multiplier keeps the one thing diff is genuinely good at —
"spend the scarce budget where something moved" — and discards the thing it is bad at.

The `1.6` is a tie-break weight, not a claim: it is large enough to promote a changed band past one
unchanged band of the same class and too small to promote a changed footer past an unchanged hero.
**UNVERIFIED** as a specific value; the probe is §8.1.

---

## 3. Scale — how a crop lands inside the lossless envelope

The envelope is not the API's. **Claude Code's client clamp binds first: 2000×2000 px and
3 932 160 bytes**, and it degrades through palette-PNG (256 colours) → JPEG q80→q60→q40→q20 →
Lanczos resize, silently. So the design rule is: *choose the scale in the browser; never let the
client resizer choose it.*

`Page.captureScreenshot({ clip: {x, y, width, height, scale} })` — `x/y/width/height` in CSS px,
`scale` the page scale factor at raster time. Rendering at `scale = 1.389` is a **true render at
1.389**, not a Lanczos downsample of a render at 2. Same pixel count, strictly more detail, and
deterministic.

### 3.1 The ladder (deterministic, per crop)

```
w, h  = crop CSS width, height
kind  = "detail" if the crop may carry a sub-perceptual verdict, else "context"

1.  if w ≤ 1000 and h ≤ 1000:            scale = 2.0        # eff 2.00×, lossless
2.  elif kind == "detail":               SPLIT until (1) holds — a detail crop never leaves the envelope
3.  else:                                scale = min(2.0, 2000/w, 2000/h), floored to 3 dp
4.  if scale < 1.0:                      SPLIT the band at its next-widest admissible gutter, recurse
5.  assert ceil(w·scale) ≤ 2000 and ceil(h·scale) ≤ 2000 and bytes ≤ 3 932 160   # else E_OVERSIZE
```

`1000×1000 CSS @2 = 2000×2000 raster` — the exact pass-through condition. `2000/w` is the largest
scale that still passes it. Nothing here is chosen; every number is the clamp read backwards.

**Why the ceiling is 2.0 and not 4.0.** A browser rendering vector text at scale 4 genuinely
produces more detail, and `2000/250 = 8` would permit it on a small crop. It is refused on a design
argument, not a physics one: **the review target is what a human sees at DPR 2.** A defect visible
only at 4× is not a defect any user experiences, and manufacturing one is how a reviewer earns the
~20 % false-positive rate at which it loses credibility regardless of catch rate. Scale is capped at
the human's.

**The consequence for recursion is the interesting one.** Since scale never exceeds 2.0, a child
crop buys *isolation* (fewer competing elements in frame) and, when the parent was a context crop,
*a move from eff 1.39× into eff 2.00×* — it never buys magnification. That is exactly what
terminates the recursion in §5.3.

### 3.2 Worked numbers, the three apps

| Case | CSS crop | scale | raster | tokens `⌈w/28⌉·⌈h/28⌉` | eff |
|---|---|---|---|---|---|
| detail crop, envelope | 960×640 | 2.0 | 1920×1280 | 69·46 = **3 174** | 2.00× |
| full-width band, `reso-management-app` @1440 | 1440×620 | 1.388 | 1999×861 | 72·31 = **2 232** | 1.39× |
| band split into 2 columns (preferred for detail) | 728×620 ×2 | 2.0 | 1456×1240 | 52·45 = 2 340 ea | 2.00× |
| `index.png`, whole page 1440×3488 @1 | 1440×3488 | 0.573 | 826×2000 | 30·72 = **2 160** | 0.57× |
| naive full-page @2 (**rejected**) | 1440×3488 | 2 → clamped | 1152×2000 | 3 024 | **0.80×** |

The last row is the whole argument for this stage in one line: a full-page shot at any DPR delivers
**0.80×**, worse than a plain DPR-1 viewport shot, because height is the binding constraint and no
capture setting fixes it. Two column crops of one band cost 4 680 tokens and deliver 2.00×.

**Full-width vs two columns.** For a 1440 CSS viewport, rule 3 gives 1.388× on a full-width band —
adequate for structure, hierarchy and rhythm, and *not* adequate for a 1 px verdict. So:
`kind = "detail"` (any duty crop, any zoom child, anything whose caption asks about alignment,
hairlines, or colour) is split into ≤1000 CSS-wide columns; `kind = "context"` stays full-width at
1.388× and its caption carries `subpixel_verdicts_allowed: false`, which P3 must render as an
explicit prohibition (§6.2). A crop that cannot support a verdict must say so *in the same image's
caption*, because a judge that is not told will answer anyway.

---

## 4. Overlap — so a straddling defect is not lost

Overlap alone is the wrong instrument, and relying on it is the standard failure. Three mechanisms,
in the order they fire:

### 4.1 Cut placement (primary)

§2.2 step 2 forbids any cut line that strictly straddles a non-full-bleed element. When it holds,
overlap is redundant. It fails only where the page genuinely has no admissible gutter within the
window — a continuous table, a long article — and those cases record `forced_cut: true`.

### 4.2 Overlap band (secondary)

Adjacent crops share `overlap` CSS px, computed per cut rather than fixed:

```
straddlers = { e ∈ elements : e.rect.y < y_cut < e.rect.bottom }
overlap    = clamp( p99(straddlers.rect.h) if straddlers else 0, 64, 160 )
```

- **Floor 64 CSS px.** = 4 × the 16 px base spacing unit, and ≥ the 44 px AAA touch target plus
  2×8 px of padding (60, rounded up to the next 16-multiple). Below 64 the overlap cannot contain a
  single standard control plus its label, which is the smallest thing whose bisection would create a
  finding.
- **Cap 160 CSS px.** At 1440 CSS wide a 160 px overlap costs `72·⌈160·1.388/28⌉ = 72·8 = 576`
  tokens per seam — ~18 % of one context crop. Past that, overlap is cheaper to buy as a seam crop
  (§4.3), which is targeted rather than blanket.
- **`p99` not `max`** so one absurd outlier (a full-height sidebar) does not force every seam to
  160.

### 4.3 Seam crops (guarantee)

After the cover is built, run the `uncovered` post-condition from §1.3. Every element ≥24×24 CSS px
that is in no crop gets a dedicated crop **centred on it**, `kind = "detail"`, expanded to its
nearest ancestor ≤1000×1000. These are counted against the budget at priority 95 — below duty,
above structure — because an element nobody looked at is a worse outcome than a band ranked third
going unseen.

`uncovered` must be empty at exit 0. That is the difference between "we used overlap so it is
probably fine" and a checked property.

---

## 5. How many crops, and what bounds the number

### 5.1 The cliff is per-CONTEXT, not per-request — and that is the binding constraint

The measured fact is *">20 image blocks in one request tightens the per-image cap and **rejects**
oversized images rather than downscaling them."* The consequence most designs get wrong: in a Claude
Code session, **every image the agent has ever `Read` remains in the transcript**, and the transcript
is the next request. So the 20-block cliff accumulates across the whole review, not per tool call.
Two waves of 12 is 24 blocks in one request — over the cliff, and it **fails hard with a 400
mid-review**, after the tokens are spent.

Therefore:

```
BLOCK_CAP        = 16   per judging context
WAVE_1_SPEND     = 13   (1 index + 12 crops)
ZOOM_RESERVE     =  3   (recursion children land in the SAME context — §5.3)
```

- **16, not 20.** Four blocks of headroom against a hard failure. The session may already hold
  images the harness put there (a prior route, a baseline pair, an operator screenshot), and the
  failure is rejection rather than degradation, so the margin has to be real.
- **12 crops.** `12 × ~3 200 = 38 400` image tokens plus the ~2 160-token index plus the ~854-token
  fact-pack ≈ 41 400 tokens of evidence for one route. At a 200 k window that is ~21 %, leaving the
  judge room to reason; at 1 M it is free. Twelve is also roughly the band count of a real page: the
  three apps' primary routes decompose to 5–8 bands at `H_max = 1000` CSS px against document
  heights of ~2 400–5 000 px, so 12 covers the cover with room for duty and seam crops.
- **A page needing >12 duty crops is reported (`E_BUDGET_EXCEEDED`), never truncated silently.**

**Wave 2 runs in a FRESH context.** Not a second request in the same session — a subagent or a new
session that receives `plan.json` and `Read`s only its own wave's crops. This is the only way to
exceed 13 delivered images without touching the cliff, and it is why the plan carries
`truncated.remaining` as data rather than as prose.

### 5.2 Priority and the budget spend

```
duty      priority 100/90/80/70/60   (§2.1)   — always emitted, up to the budget
seam      priority 95                (§4.3)   — a guarantee, ranks with duty
context   priority = G3 score        (§2.3)   — fills the remainder, MECE cover first
```

Fill order: all duty and seam, then context bands in G3 order until the budget is spent. If duty +
seam alone exceed the budget, no context band is emitted and `degraded[]` records
`"cover:incomplete → global judgement rests on index.png alone"` — the operator can then see that
this page's review was defect-driven rather than survey-driven.

### 5.3 Recursion — crop a crop

**Recurse only on a returned signal. Never speculatively.** Speculative recursion is how a
decomposition burns its budget before the judge has said anything, and the measured win
(18.9 % → 48.1 % on ScreenSpot-Pro, no model change) came from *iterative focus refinement* — a
loop, not a pre-plan.

Two triggers:

- **T1 — judge-requested zoom.** P3 returns
  `{"need_zoom":[{"parent":"c07","region_css":[x,y,w,h],"question":"is the divider 1px or 2px?"}]}`
  and P2 is re-invoked with `--zoom plan.json#c07`.
- **T2 — cross-check disagreement inside a crop.** P4's comparator fires on a region → child crop at
  the disagreement's bounds.

Terminate when **any** of these holds:

| | Rule | Number | Reason |
|---|---|---|---|
| **D1** | `depth > 2` | 2 | page → band → element. A third level cannot change `scale` (capped at 2.0, §3.1) and cannot reduce a ≤1000 CSS region further without cutting an element. |
| **D2** | parent already at `eff == 2.00` **and** parent `w ≤ 1000 ∧ h ≤ 1000` | — | The child would deliver the identical pixels with fewer distractors. Answer from the parent; there is nothing to buy. **This is the rule that makes the loop finite**, because §3.1's ceiling means zoom converges rather than diverging. |
| **D3** | context has spent `BLOCK_CAP` | 16 | A 4th zoom child forces a new context; the plan says so rather than failing at the API. |
| **D4** | `IoU(child, any existing crop) ≥ 0.9` | 0.9 | Dedupe. Without it a judge that keeps asking about the same divider oscillates and spends the reserve on identical images. |
| **D5** | `region.w < 24 ∨ region.h < 24` CSS px | 24 | Below the target-size floor the region has no independent geometry; expand to the parent element instead. |

**And one refusal that is not a bound but a policy.** A zoom request whose question is a *number* —
"how many px is this gap", "what is the contrast ratio" — is **refused with the fact-pack answer
instead of a crop**. The grounder supplies identity, the DOM supplies geometry (README §2). Serving
a 3 200-token image to answer a question `getBoundingClientRect()` already answered exactly is the
central waste this pipeline exists to remove, and Opus 5 is measured 0/2 on sub-perceptual precision
anyway — it would answer, and be wrong.

---

## 6. Preserving global judgement — the failure mode, solved explicitly

This is the obvious way this design dies: everything is cropped, so nobody ever looks at the page.
And the capability being destroyed is precisely the one the baseline measured as *excellent* —
2/2 on judgement/gestalt defects, plus three real defects nobody injected. Losing it to win
resolution would be a net loss.

Four mechanisms, all owned by this stage.

### 6.1 The index image is mandatory, and it is FIRST

One whole-page shot, `fullPage:true` at **DPR 1**, downscaled *by us* with an explicit Lanczos pass
to ≤2000 px on the long edge, written as `index.png` and delivered as image block #1. For a
1440×3488 page that is 826×2000, 2 160 tokens, eff 0.57×.

**Its lossiness is not a defect, because of what it is for.** Opus 5 is structurally blind below the
perceptual threshold — so an index image at 0.57× loses nothing it was ever going to use. It carries
section order, vertical rhythm, balance, where the eye lands, whether the page hangs together. Those
are all supra-threshold by construction.

The index's known limits are **stated in its own caption** (§6.2), which converts a silent failure
into a declared one: `MEASURE NOTHING ON THIS IMAGE.`

### 6.2 Captions — every crop carries its frame, and the prohibition it needs

P2 emits the caption text; P3 pastes it verbatim above each image. ~40 tokens against a 3 200-token
image, so the frame is free. Exact strings:

```text
INDEX — whole page, {url}, {W}×{H} CSS px, rendered at 0.57× (downscaled by us, not by the client).
This image is a STRUCTURAL INDEX. Judge only: section order, vertical rhythm, balance, visual
hierarchy, where the eye lands first, whether the page hangs together. MEASURE NOTHING ON THIS
IMAGE — no spacing, no alignment, no colour, no type size. Those numbers are in the fact-pack.
```

```text
CROP {id} — band {i} of {n} ({role}), page rows {y0}–{y1} ({p0:.0%}–{p1:.0%} of the document).
Above this: {role_above}. Below this: {role_below}.
Rendered at {eff}× device pixels per CSS pixel; {W}×{H} CSS px shown.
{subpixel_clause}
{reason_clause}
```

- `subpixel_clause`, when `eff == 2.00`: *"This crop is at full device resolution; 1 px judgements
  are admissible here."*
- `subpixel_clause`, when `eff < 2.00`: *"**This crop is downscaled ({eff}×). Do not assert any
  1–2 px alignment, hairline-width or colour-drift finding from it.** If you suspect one, request a
  zoom naming the region."* — the escape hatch that keeps a refusal from becoming a miss.
- `reason_clause`, for a duty crop: *"You are being shown this because the deterministic layer
  ABSTAINED here: {finding.why}. It could not decide; you can."*

### 6.3 The global question is asked ONCE, before any crop, and its answer is FROZEN

`plan.json.phases` is ordered `global` → `local`, and P3 must honour it. The global verdict is
recorded before the first crop enters the context, and crop findings may **cite** it but never
revise it.

Reason, measured: rubric scoring shows **16–39 % top-1 ranking reversals from reordering alone**,
and pairwise order-invariant consistent accuracy runs ~30–37 % against a 25 % chance baseline. A
judge that has just spent twelve images on hairlines will anchor on hairlines. Freezing the gestalt
answer ahead of the detail pass is the cheapest available defence against an ordering effect this
large, and it costs nothing.

The `global` ask, emitted into `plan.json.phases[0].ask`:

```text
Look at the index image only. In at most six sentences: does this page hang together? Name the
single element your eye lands on first and say whether that is the one that should be. Name any
section whose vertical rhythm breaks the page's own pattern. Do not name any measurement. Do not
look ahead. This answer will not be revised later.
```

### 6.4 Global questions with a NUMBER in the answer never reach the judge at all

"Global" is not the same as "gestalt", and most whole-page questions are arithmetic:

| Whole-page question | Owner | Method |
|---|---|---|
| section-gap consistency, vertical rhythm as *numbers* | P0 FACTS | horizontal projection profile over the full-page raster, gap series, `find_peaks` — ~2 ms |
| column-grid conformance, gutter equality | P0 FACTS | vertical projection profile; *"these four cards have gaps of 16, 16, 16 and 23 px"* is the entire computation |
| palette membership across the page | P0 FACTS | colour histogram vs the token set |
| page-level type-scale conformance | P0 FACTS | `font-size` histogram vs the scale |
| does the page hang together; does the eye land right; is the hierarchy inverted | **P3 JUDGE, on the index** | the 2/2 capability |

So "preserve global judgement" reduces to the genuinely gestalt subset — which one index image
serves completely. **This is the load-bearing move.** The failure mode is only fatal if you believe
the judge has to answer every whole-page question; it does not, and it is worse than a projection
profile at most of them.

---

## 7. The algorithm

```python
BLOCK_CAP, WAVE_SPEND, ZOOM_RESERVE = 16, 13, 3
H_MAX = W_MAX = 1000          # CSS px — the 2000/2 lossless envelope
RASTER_MAX, BYTE_MAX = 2000, 3_932_160
MIN_TARGET = 24               # WCAG 2.2 SC 2.5.8
OVERLAP_FLOOR, OVERLAP_CAP = 64, 160
SCALE_MAX, MAX_DEPTH, DEDUPE_IOU = 2.0, 2, 0.9
INK_MIN = 0.005               # 0.5% — below this a crop is blank

def decompose(cap, out, budget=12, saliency="none", baseline=None):
    m, snap = cap.manifest, cap.snapshot
    assert_manifest(m, snap)                       # exit 3 · E_MANIFEST_MISMATCH

    page  = Rect(0, 0, snap.scroll.w, snap.scroll.h)
    full  = load(m.shots.fullpage_dpr1)            # DPR-1 raster, our own copy
    binar = binarise(full, bg=modal_colour(full))

    # ---- 1. index image (never optional, always block #1) -------------------
    idx_scale = min(1.0, RASTER_MAX / max(page.w, page.h))
    write_png(out/"index.png", lanczos(full, idx_scale))     # ours, not the client's
    gate_ladder(out/"index.png")                   # exit 4 · E_OVERSIZE

    # ---- 2. G2 bands: MECE cover, cut only at admissible gutters ------------
    gutters = zero_runs(binar.sum(axis=1))         # A5 C4 projection profile, ~2ms
    admissible = [g for g in gutters
                  if not any(e.rect.y < g.mid < e.rect.bottom
                             and e.rect.w < 0.98 * page.w for e in snap.elements)]
    bands, y = [], 0
    while y < page.h:
        window = [g for g in admissible if 0.55*H_MAX <= g.mid - y <= H_MAX]
        if window:
            cut, forced = max(window, key=lambda g: g.height).mid, False
        else:
            cut, forced = min(y + H_MAX, page.h), True
        bands.append(Band(y0=y, y1=cut, forced=forced,
                          role=landmark_role_within(snap, y, cut, tol=8)))
        y = cut

    # ---- 3. overlap, per cut, from the straddler distribution ---------------
    for a, b in pairs(bands):
        strad = [e for e in snap.elements if e.rect.y < b.y0 < e.rect.bottom]
        ov = clamp(p99([e.rect.h for e in strad]) if strad else 0,
                   OVERLAP_FLOOR, OVERLAP_CAP)
        a.y1 = min(a.y1 + ov/2, page.h); b.y0 = max(b.y0 - ov/2, 0)

    # ---- 4. G1 duty regions ------------------------------------------------
    duty = []
    for f in cap.findings_dom:
        if f.verdict == "INDETERMINATE":  duty.append(Duty(f, prio=100))
    for f in cap.findings_xcheck or []:   duty.append(Duty(f, prio=90))
    for e in snap.elements:
        if unreasonable_backdrop(e):      duty.append(Duty(e, prio=80))
        if gradient_text_run(e):          duty.append(Duty(e, prio=70))
        if unnamed_interactive(e) or e is smallest_target(snap):
                                          duty.append(Duty(e, prio=60))
    for d in duty:                                  # a defect alone is unjudgeable
        d.rect = nearest_ancestor_within(snap, d.target, W_MAX, H_MAX)

    # ---- 5. G3 ranking — order only, never membership -----------------------
    for b in bands:
        b.prio = (40*z(ink_density(binar, b)) + 30*z(isolation(binar, b))
                  + 20*z(max_local_contrast(full, b)) + 10*z(n_interactive(snap, b)))
        if saliency == "umsi":  b.prio = umsi_mass(full, b)     # licence-gated
        if baseline and diff_ratio(full, baseline, b) > 0.002:  b.prio *= 1.6

    # ---- 6. materialise crops through the scale ladder ----------------------
    crops = []
    for d in sorted(duty, key=lambda d: -d.prio):
        crops += materialise(d.rect, kind="detail", reason=d.reason)
    for b in sorted(bands, key=lambda b: -b.prio):
        crops += materialise(Rect(0, b.y0, page.w, b.y1-b.y0),
                             kind="context", band=b)
        if len(crops) >= budget: break

    # ---- 7. the checked post-condition: nothing ≥24px is unseen -------------
    uncovered = [e for e in snap.elements
                 if e.rect.w >= MIN_TARGET and e.rect.h >= MIN_TARGET
                 and not any(contains(c.css, e.rect) for c in crops)]
    for e in sorted(uncovered, key=lambda e: -area(e))[:budget - len(crops)]:
        crops += materialise(nearest_ancestor_within(snap, e, W_MAX, H_MAX),
                             kind="detail", prio=95, reason="seam")
    uncovered = recompute(uncovered, crops)         # must be [] for exit 0

    crops = crops[:budget]
    for c in crops:
        render(c)                                   # CDP clip+scale, §7.1
        if ink_density_of(c) < INK_MIN:
            if c.kind == "duty": raise Escalate(7)  # E_BLANK_DUTY — capture bug
            crops.remove(c)
        gate_ladder(c.png)                          # exit 4

    return emit(out/"plan.json", page, crops, uncovered,
                truncated=len(duty) > budget, degraded=degradations())

def materialise(rect, kind, **meta):
    """The scale ladder. Returns 1..n crops, all inside the envelope."""
    if rect.w <= W_MAX and rect.h <= H_MAX:
        return [Crop(rect, scale=SCALE_MAX, eff=2.00, **meta)]
    if kind == "detail":                            # never leaves the envelope
        return flatten(materialise(r, kind, **meta) for r in split(rect))
    s = round(min(SCALE_MAX, RASTER_MAX/rect.w, RASTER_MAX/rect.h), 3)
    if s < 1.0:
        return flatten(materialise(r, kind, **meta) for r in split(rect))
    return [Crop(rect, scale=s, eff=s, subpixel=False, **meta)]

def split(rect):
    """Split on the longer axis, at the widest admissible gutter, with overlap."""
    axis = "y" if rect.h >= rect.w else "x"
    cut  = widest_admissible_gutter(rect, axis) or rect.mid(axis)
    ov   = OVERLAP_FLOOR
    return [rect.upto(axis, cut + ov/2), rect.from_(axis, cut - ov/2)]

def zoom(plan, parent_id, region, question):
    """T1/T2 recursion. Every guard is a termination rule from §5.3."""
    p = plan[parent_id]
    if question_is_numeric(question):   return answer_from_factpack(question)   # policy
    if p.depth >= MAX_DEPTH:            return Refuse("D1 depth")
    if p.eff == 2.00 and p.css.w <= W_MAX and p.css.h <= H_MAX:
                                        return Refuse("D2 nothing to buy — answer from " + parent_id)
    if plan.blocks_spent >= BLOCK_CAP:  return Refuse("D3 new context required")
    if region.w < MIN_TARGET or region.h < MIN_TARGET:
                                        region = nearest_ancestor_within(...)   # D5
    child = materialise(region, kind="detail", parent=parent_id, depth=p.depth+1)
    if any(iou(child.css, c.css) >= DEDUPE_IOU for c in plan.crops):
                                        return Refuse("D4 duplicate")
    return child
```

### 7.1 The render call (CDP, verbatim)

```js
// One browser session, reused across all crops of one page, so every crop is the
// same frame the fact-pack describes. Never re-navigate between crops.
await cdp.send('Emulation.setDeviceMetricsOverride',
               { width: 1440, height: 900, deviceScaleFactor: 2, mobile: false });
const png = await cdp.send('Page.captureScreenshot', {
  format: 'png',
  captureBeyondViewport: true,            // reach below the fold without scrolling
  fromSurface: true,
  optimizeForSpeed: false,                // deterministic bytes
  clip: { x, y, width, height, scale }    // CSS px + page scale factor (§3.1)
});
```

Launch flags, inherited from P1 and **asserted**, not set, by P2:
`--force-device-scale-factor=2 --force-color-profile=srgb --hide-scrollbars`.
Playwright equivalent: `page.screenshot({ clip, scale:'device', type:'png',
animations:'disabled', caret:'hide', style:'.js-fixed,[data-fixed]{position:absolute!important}' })`
— **`scale:'device'` is mandatory; without it `deviceScaleFactor` is discarded.**

Use raw Playwright, not the `agent-browser` CLI: as of 0.27.1 it exposes no `--scale css|device`
and no launch-arg passthrough for `--force-device-scale-factor`, so it cannot produce a
scale-pinned capture and every crop from it inherits the phantom-offset risk.

---

## 8. What this stage does NOT do, and who owns it

| Not P2's | Owner | Why it must not be here |
|---|---|---|
| Deciding whether a finding is real | **P3 JUDGE** / **P4 ADJUDICATE** | P2 has no aesthetic model and must not acquire one. It routes; it never rules. |
| Any *number* — spacing, contrast, target size, token conformance, animation timing | **P0 FACTS** | The fact-pack is ~854 tokens, fewer than one screenshot. There is no budget argument for asking a model instead, and the model is measured 0/2 below the perceptual threshold. |
| Capture correctness — scroll priming, `position:fixed` neutralisation, font/stability gating, DPR pinning | **P1 CAPTURE** | P2 **asserts** the manifest and refuses (exit 3). A stage that repairs its input hides its input's bugs. |
| Annotated overlays / boxes drawn on images | **nobody — deliberately not built** | An overlay is a full second image (~3 240 tokens) on top of the clean one; the same findings as JSON coordinates are ~840 tokens, ~4× cheaper. P2 emits coordinates, never ink. |
| False-positive budgeting, order-randomised comparison | **P4 ADJUDICATE** | ~20 % FP is where an AI reviewer loses credibility regardless of catch rate; that budget is measured across a corpus, not within one page. |
| Gating CI on a visual score | **nobody — ratified against** | June 2026 standing ruling: *taste stays human, gates adjudicate correctness/coverage only.* Every artifact here is advisory triage. |
| Ranking by human attention | **blocked** | UMSI++ is the one specialist that wins (CC 0.833 vs 0.408) and its weights carry no licence file. Until resolved, `--saliency none` and `degraded[]` says so. |

---

## 9. Uncertainty, and the one probe that settles each

**U1 — `clip.scale` is a raster scale, not a layout scale. UNVERIFIED.** The whole non-integer
context-crop path (§3.1 rule 3) rests on `Page.captureScreenshot`'s `clip.scale` re-rasterising
without reflowing. If it instead changes the page scale factor in a way layout observes, a 1.388×
band crop is a *different layout* from the 2.0× detail crops of the same region, and cross-crop
geometric comparison becomes invalid.
*Probe:* capture one band at `scale:2` and at `scale:1.388`; extract text baseline y-positions from
both via connected components; assert they agree within 0.5 px after dividing by the scale ratio. A
non-linear disagreement condemns rule 3, and the fallback is already specified — split every band
into ≤1000 CSS-wide columns at 2.0×, at ~2× the token cost.

**U2 — the 2000 px / 3.75 MiB clamp constants perish.** Read from the 2.1.183 bundle; the fleet's
`current` is 2.1.114 and a newer bundle may raise the cap toward the 2576 high-res tier.
*Probe:* `strings <bundle> | grep -o 'maxWidth:[0-9]*'` before each release adoption. **The ladder's
*shape* — pass-through → palette → JPEG → resize — is what generalises; the numbers do not.** Every
constant in §3 is derived from `RASTER_MAX`, so one edit re-derives the stage.

**U3 — the `1.6` baseline-diff multiplier and the `40/30/20/10` ranker weights.** Chosen for shape,
not measured.
*Probe:* run the 13-page corpus with the ranker permuted across 5 weightings and measure whether the
duty-crop set changes at all (it must not — duty is membership, ranking is order) and whether the
context-crop set's rank correlation exceeds 0.8. If ranking is unstable, flatten it to
`ink_density` alone rather than defending a composite nobody validated.

**U4 — 5–8 bands per page for the three apps** is an estimate from document heights, not a count.
*Probe:* run §7 step 2 over the primary route of each app and print `len(bands)`. If any page exceeds
12 bands at `H_MAX = 1000`, the budget is wrong for that app, not the algorithm.

**U5 — the >20-block cliff accumulating per transcript** is inferred from how Claude Code carries
image blocks forward, not observed firing.
*Probe:* `Read` 21 distinct 2000×1250 PNGs in one session and record whether the 22nd request
returns a 400 naming a per-image cap. This is the single highest-value probe in the spec: it decides
whether `BLOCK_CAP` is 16 or whether wave 2 can stay in-context.

---

## 10. Acceptance

The stage is done when, on `bench/corpus` (13 pages, 9 DOM-determined + 2 pixels-only + 1 clean
control):

1. `uncovered == []` on all 13 pages.
2. Every emitted PNG passes `w ≤ 2000 ∧ h ≤ 2000 ∧ bytes ≤ 3 932 160` — checked by the stage, not
   trusted from the resizer.
3. Both pixels-only defects (the 1 px misalignment and the 5/255 colour drift) land inside a crop
   with `eff == 2.00` and `subpixel_verdicts_allowed: true`. P2 cannot make the judge *find* them —
   the measured baseline is 0/2 and this stage does not claim to move it — but a decomposition that
   delivers them at 1.39× has failed on its own terms before the judge is even asked.
4. The clean control yields an index image, a full band cover, **zero** duty crops, and
   `degraded == []`. A decomposition that manufactures work on a clean page is the first step toward
   the ~20 % false-positive rate.
5. Crop count on the corpus dashboard is ≤ 12, and re-running the stage twice on the same capture
   produces byte-identical `plan.json` and byte-identical PNGs.

