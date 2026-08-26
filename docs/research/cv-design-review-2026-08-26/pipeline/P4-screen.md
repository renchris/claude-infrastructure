# P4 — SCREEN

**The deterministic + classical-CV pass that runs before any model call.**

Date: 2026-08-26 · Substrate: `../README.md`, `../agents/A5-cv-primitives.md`,
`../agents/A7-deterministic-layer.md`, `../agents/A13-corpus-audit.md`, and the working code in
`bench/{capture,detect_dom,detect_xcheck}.py`, which this spec generalises and corrects.

SCREEN answers every question that has a number in the answer, and — the load-bearing half —
**declares, per subject, every question it could not answer.** It never guesses, never scores, never
opines. Its most valuable output is an abstention, because an abstention routes to the judge and a
false pass routes nowhere.

---

## 0. CONTRACT

### 0.1 Invocation

A plain CLI writing JSON + PNG to disk. Not an MCP tool: image bytes returned from MCP are charged
against `MAX_MCP_OUTPUT_TOKENS` (default 25,000) and `maxResultSizeChars` explicitly does not apply
to image-returning tools, and a dead stdio server silently vanishes from the tool list — disqualifying
for a layer whose entire job is stopping a model from guessing.

```bash
screen \
  --snapshot   out/<page>.snapshot.json   # P2 CAPTURE artifact (DOMSnapshot-derived)
  --shot       out/<page>@2x.png          # the SAME frame, from the SAME browser pass
  --capture-manifest out/<page>.capture.json
  --tokens     tokens/<app>.resolved.json # resolved design tokens, not the source file
  --profile    reso-management-app        # selects the rule weighting (§6)
  --out        out/<page>.screen.json
  [--cv on|off]            # default on; off ⇒ every X-rule reports INDETERMINATE, never PASS
  [--differential on|off]  # default on; §4.2 probe budget
  [--max-crops 12]         # cap on the crop set handed to P5/P6
  [--gate]                 # exit 1 on any severity=high FAIL; see 0.4
```

### 0.2 Inputs — exact shapes and preconditions

| Input | Must contain | Precondition SCREEN asserts before running any rule |
|---|---|---|
| `--snapshot` | `elements[]` with `path`, `backendNodeId`, `tag`, `role`, `text`, `rect{x,y,w,h,right,bottom}`, `scroll{w,h,cw,ch}`, `styles{…}`, `paintOrder`, `stackingContext`, `blendedBackgroundColor`, `textColorOpacity`, `backgroundChain[]` | non-empty; `frameId` present for every element (iframe elements carry their own) |
| `--shot` | full-page PNG of the frame the snapshot describes | `shot.width / snapshot.scroll.w` resolves to the manifest's `deviceScaleFactor` within 0.01 |
| `--capture-manifest` | `deviceScaleFactor`, `forcedDeviceScaleFactor` (bool), `viewport`, `reducedMotion`, `colorScheme`, `fontsReady` (bool), `colorProfile`, `lcdText` (bool), `capturedAt`, `snapshotSha256`, `shotSha256` | **all six determinism knobs pinned** — see 0.5 |
| `--tokens` | flat map `name → value`, values already resolved through `var()` and theme layers | at least one colour token, else K-family ⇒ INDETERMINATE |

The snapshot and the screenshot **must come from one browser pass**. If `capturedAt` differs by more
than 0 between them, or either sha does not match the file on disk, SCREEN exits 2. There is no
"probably the same frame" mode — a geometric finding argued against a different render is the
phantom-offset defect wearing a diagnosis's clothes.

### 0.3 Outputs

One JSON document (`--out`), plus a `crops/` directory of PNG clips SCREEN wrote for the judge.
Full schema in §5. The header is a **closed census**:

```json
{"census": {"subjects": 1841, "pass": 1732, "fail": 14, "indeterminate": 95, "out_of_scope": 0}}
```

`pass + fail + indeterminate + out_of_scope == subjects`, asserted at exit. This is the field the
March 2026 corpus never had: its "60% of visual checks are fully automated" had 15 items over one
25-item checklist for a page that no longer exists — an unfalsifiable denominator (A13 LB-1). A
coverage claim SCREEN makes is arithmetic over a population it enumerates.

### 0.4 Exit codes — SCREEN fails closed

| Code | Meaning |
|---|---|
| 0 | ran to completion; findings written. **A page full of FAILs still exits 0** unless `--gate`. |
| 1 | `--gate` only: at least one `severity:high` FAIL. Correctness/coverage may gate — that is exactly what the June 2026 ruling permits (*"taste stays human, gates adjudicate correctness/coverage only"*). SCREEN never gates on a judgement. |
| 2 | **precondition failure** — unpinned capture, sha mismatch, snapshot/shot geometry disagreement, missing token file. Nothing was measured; nothing may be inferred. |
| 3 | internal error. |

Exit 2 is the important one. A capture that did not pin `--force-device-scale-factor` does not get a
looser tolerance band; it gets **no geometric verdicts at all** (§3.1).

### 0.5 The six pinned knobs, and why each is a precondition rather than a nicety

`--force-device-scale-factor=<dpr>` · `reduced_motion=reduce` · `color_scheme` fixed ·
`--force-color-profile=srgb` · `--disable-lcd-text` · `await document.fonts.ready`.

Headless and headed Retina disagree on line-box rounding by **~1.5 px accumulated over four
paragraphs with identical font metrics** unless the scale factor is forced. Unpinned, every geometric
finding inherits a phantom offset that reads exactly like a real 1 px bug — and the 1 px bug is a
defect class SCREEN is supposed to own. Subpixel LCD text puts colour fringes on every glyph edge,
which is ink to a NumPy threshold. A non-sRGB profile moves every sampled colour and therefore every
contrast ratio.

---

## 1. The three-valued output, and why the third value is the point

| Verdict | Means | Routes to |
|---|---|---|
| **PASS** | the rule's precondition held, the measurement ran, the value is inside the band | nowhere; counted only |
| **FAIL** | precondition held, measurement ran, value is outside the band | P7 attribution → an edit |
| **INDETERMINATE** | **the rule's precondition did not hold, so no measurement exists** | P5/P6 — with a crop, a question, and the reason no number could be produced |

**INDETERMINATE is not a soft FAIL and not a skip.** It is the statement *"requirement R is
UNVERIFIED for this subject, because P"*, carrying `P` in machine-readable form. Three properties
make it the most important value in the pipeline:

1. **It is the only value that sizes the model spend.** The judge's queue is exactly the
   INDETERMINATE set plus the whole-page questions SCREEN cannot pose. That set is small and
   countable, which is what makes the vision call affordable and its budget defensible.
2. **Its absence is a silent lie.** Measured on this corpus: `blendedBackgroundColors` samples one
   colour per text run, and over a gradient returns an endpoint — reported **10.36:1** where the text
   actually sits at **1.22:1**. Adopting that scalar naively converts an honest INDETERMINATE into a
   confident PASS. The rule gets *better* on solid and layered backdrops at the same moment it goes
   blind on varying ones, so the improvement hides the regression. This is the
   fail-safe-default-mimics-the-healthy-state trap, and only a rule that can refuse to answer escapes it.
3. **It makes new rules admissible.** See the rule-admission test below.

### 1.1 Rule admission test (binding on every rule added later)

A rule may enter SCREEN only if it declares, in code:

- **`subjects(page) → [subject]`** — the enumerable population it judges. No rule may iterate an
  implicit set; the census in §0.3 is computed from these functions.
- **`precondition(subject) → bool | reason`** — the condition under which a number exists at all.
- **at least one reachable INDETERMINATE branch.** A rule with no path to INDETERMINATE is asserting
  it can measure every subject in every page, which is a claim about the world no rule here can
  honestly make. Absent that branch, the rule is rejected at review.
- **one mutant** — a fixture in which exactly this rule's subject is broken and every sibling rule's
  subject is untouched, so a green suite credits *this* rule rather than the file.
- **a clean-control run** — §7.

---

## 2. Rule set — the deterministic family

Every rule below reads only the P2 snapshot and the token file; none touches pixels. Thresholds are
given as `nominal ± band`, and **the band is derived, never chosen** — its arithmetic is in the
Reason column.

### 2.0 How a band is computed

Three physical sources of jitter, and every band is a sum of the ones that apply:

| Source | Magnitude | Applies to |
|---|---|---|
| **J1 device-scale quantisation** | `0.5 / dpr` CSS px — a rendered edge snaps to the device-pixel grid | every geometric rule |
| **J2 fractional layout** | `0.25` CSS px — percentage widths, flex `1fr` division, `em`-derived padding land on non-integers | rules over computed lengths |
| **J3 font-metric drift** | `0.5` CSS px per line box, cumulative — resolved family, hinting, `line-height` rounding | text-extent rules only |

`band = Σ(applicable J)`, computed **from `--capture-manifest` at run time, not hardcoded.** So the
same rule has band 0.75 at dpr 1 (J1 0.5 + J2 0.25) and 0.50 at dpr 2 (J1 0.25 + J2 0.25).

**Why this is a derivation and not a constant.** Our own control flipped from clean to defective when
the display scale changed a box from 44 px to 43 px. The naive repair is a constant tolerance, and a
constant tolerance is wrong in both directions: too tight at dpr 1, needlessly loose at dpr 2, and
silently wrong the day someone captures at dpr 1.5. Deriving it from the manifest means the band
tracks the capture, and an **unpinned** capture yields no band at all — the whole geometric family
reports INDETERMINATE (`capture-not-pinned`) rather than PASS. Loosening a band to survive an
unpinned capture would be trading a known unknown for a confident wrong answer.

### 2.1 G — geometry

| id | Subject population | Measurement | Threshold ± band | Reason for that band | INDETERMINATE when |
|---|---|---|---|---|---|
| **G1** spacing rhythm | every parent with ≥3 laid-out children in one flow direction | `gap[i] = child[i+1].rect.near − child[i].rect.far` along the flow axis; `mode(gaps)` with its share | FAIL if `share(mode) ≥ 0.5` and `abs(gap − mode) > band`, `band = J1+J2` | The rhythm is the page's own dominant convention, so the only jitter is measurement jitter. `share ≥ 0.5` is the existence condition for a convention: below it there is no rhythm to break. | the parent is `display:grid` with `auto-fit`/`minmax` (gap is a *function* of viewport, not a value) · any child carries a non-identity `transform` (bounds are the post-transform AABB — §3.1) · any child has `position:absolute` |
| **G2** grid adherence | every non-zero `margin-*`, `padding-*`, `gap`, `row-gap`, `column-gap` on every element | `v mod U`, where `U` is **discovered**, not assumed: `U = argmax_{u ∈ {4,8}} Σ count(v mod u == 0)`, requiring ≥60% adherence to claim a unit | FAIL if `v mod U ≠ 0` and `v ∉ {1,2}` (hairlines) and `v < 100` | 1 px and 2 px are border/hairline idioms in every system measured, not grid values. `v < 100` excludes section-scale spacing, which is composed rather than stepped. 60% is the floor at which a "system" claim beats chance for U=4 (25% baseline). | no unit clears 60% ⇒ the page has no grid, and `grid-violation` is unaskable |
| **G3** alignment rails | every element's `rect.x` and `rect.right`, rounded to 0.1 | histogram edges; a bin with ≥3 members is a **rail**. FAIL an element whose edge is `0 < |x − rail| ≤ 2.0 + band` — a *near-miss*, not membership | The near-miss window is the detector; a 40 px offset is a different column, not a misalignment. Upper bound 2.0 CSS px is the largest offset the March-corpus 1 px case and the corpus `align-1px` variant both sit inside; band absorbs J1+J2 on both edges. ≥3 members: two boxes sharing an edge is a coincidence at these populations. | the element or any ancestor carries a non-identity `transform` |
| **G4** occlusion / z-order | every ordered pair of text-bearing elements whose `rect`s intersect | intersect area > 0 **and** `paintOrder[later] > paintOrder[earlier]` **and** later is not a declared overlay (`role ∈ {dialog,tooltip,menu,alertdialog}` or `position:fixed` with `z-index ≥ 10`) | FAIL on any surviving pair; overlap area is reported, never thresholded | Raw overlap is noise — measured **4,795** intersecting pairs among the first 600 boxes on one real page. The signal is the conjunction, not the count. There is no tolerance band because the predicate is boolean, not metric. | either element is inside a `<canvas>`/`<svg>` subtree, or `blendedBackgroundColor` is absent for both (nothing was painted to order) |

### 2.2 T — type

| id | Subject | Measurement | Threshold ± band | Reason | INDETERMINATE when |
|---|---|---|---|---|---|
| **T1** type scale | every element with own text | histogram `font-size`; the **scale** is `{s : count(s) ≥ 2}` | FAIL a size used exactly once when a scale exists, reporting the nearest step | Used-once is the discriminator, not distance-from-a-list: a page's real scale is what it repeats. Our corpus's `type-scale` defect is 17 px against a 12/14/16/24 scale — 1 px off, invisible to any perceptual metric, trivially visible to a histogram. No band: `font-size` is an authored value, not a measured one. | `font-size` resolves through `clamp()`/`vw` (the value is viewport-dependent, so "off-scale" is not a property of the page) |
| **T2** leading ratio | every text element | `line-height / font-size` | FAIL if outside `[1.1, 2.0]` **or** if it is the only ratio on the page differing from the page mode by > 0.05 | 1.1 is the tightest ratio at which ascender/descender collision is avoidable at any weight; 2.0 the loosest before a paragraph reads as separate lines. Both are structural, not aesthetic — the aesthetic question is P6's. 0.05 is the smallest ratio delta that survives J3 at 12 px (0.5/12 = 0.042). | `line-height: normal` — the used value is font-metric-derived, so the ratio is a property of the font file, not the design |
| **T3** silent font fallback | every distinct `(font-family, element)` | `CSS.getPlatformFontsForNode` `familyName` vs the first entry of the authored `font-family` | FAIL on mismatch | Nothing else detects this. The computed style is a *request*, not a result: `font-size: 16px; font-family: Inter` tells you nothing about the ink if Inter never loaded, and fallbacks differ in cap-height and x-height at the same `font-size` — which is why `font-size-adjust` exists. | `getPlatformFontsForNode` unavailable (non-CDP capture) — then T3 is INDETERMINATE for the whole page, never PASS |

### 2.3 K — token conformance

The highest-yield family for `reso-management-app`, where a real semantic-token system exists, and
close to the whole job there. Token values must arrive **resolved** — the source file's `var()`
chains and theme layers collapsed by P2 — because a rule diffing against unresolved sources compares
strings, not colours.

| id | Subject | Measurement | Threshold ± band | Reason | INDETERMINATE when |
|---|---|---|---|---|---|
| **K1** colour token | every opaque `color` / `background-color` / `border-*-color` value | set-difference against the token palette; for each miss, `ΔE2000(value, nearest_token)` in Lab | `ΔE < 1.0` ⇒ FAIL `token-drift` ("meant to be the token") · `1.0 ≤ ΔE ≤ 3.0` ⇒ FAIL `token-near-miss` · `ΔE > 3.0` ⇒ FAIL `undeclared-colour` | ΔE2000 < 1.0 is the standard just-noticeable-difference floor — below it, a difference is a rounding or colour-space artifact and the *intent* was the token. 3.0 is where two colours stop being a wobble and become a decision. Our corpus's `token-color-drift` is `#1D4ED3` vs token `#1D4ED8` — **5/255 on one channel**, which Opus 5 missed blind and which lands at ΔE ≈ 0.6 here. Euclidean RGB distance (what `bench/detect_dom.py` currently uses, `dist ≤ 12`) is not perceptual and mis-ranks blues against greens; Lab ΔE2000 is the one place a perceptual colour metric genuinely belongs. | the value carries alpha < 0.99 (the painted colour is a composite, not this value — route to X3) |
| **K2** radius token | every `border-radius > 0` | equality against the token set | FAIL if `min(|r − t|) > 0.5` over tokens `t` | 0.5 px: `border-radius` is authored in integers or `rem`; a half-pixel gap is `rem`-rounding, a 2 px gap is our corpus's `radius-drift` defect. **Exempt** any `r ≥ min(w,h)/2` — a pill or circle is a deliberate shape, not radius drift. | the element is `<svg>`-rendered (radius is a path property, not a box property) |
| **K3** spacing token | every non-zero spacing length | membership in the token spacing ramp | FAIL on non-membership | Distinct from G2: G2 asks "is it on the grid", K3 asks "is it a named step". A 24 px gap on an 8 px grid passes G2 and fails K3 if the ramp is 4/8/16/32. Both are true and they are different findings — this is the `assertion-span-must-equal-its-subject` split. | no spacing ramp in the token file |
| **K4** shadow / elevation | every non-`none` `box-shadow` | exact string match against the elevation set, after normalising colour to `rgb()` and lengths to px | FAIL on non-membership | Shadows are composite values; no partial-credit metric on them is meaningful, so this is set membership or nothing. | no elevation set in the token file |

### 2.4 A — correctness floors (the family permitted to gate)

| id | Subject | Measurement | Threshold ± band | Reason | INDETERMINATE when |
|---|---|---|---|---|---|
| **A1** contrast | every text run with a resolved `blendedBackgroundColor` | WCAG 2.1 ratio, `color` multiplied through `textColorOpacity` first; **APCA Lc emitted alongside as a scalar, never as a gate** | FAIL `< 4.5:1`; `< 3.0:1` for large text (`≥24px`, or `≥18.66px` at weight ≥700). No band — the standard is a bright line | Gating on APCA's `fontLookupAPCA` was measured to flag **66 of 99** text runs on a competently designed page against WCAG 2's 13, with 53 outright disagreements: `#666` on `#fff` at 14 px/400 scores WCAG 5.74 (pass) and Lc 78.8, for which the lookup demands 17.5 px (a "fail"). APCA's lookup is use-case guidance, not a conformance gate; wiring it as one manufactures a ~5× false-positive rate. WCAG 3's visual-contrast method was pulled from the Working Draft in July 2023 and is still "to be determined". | **the resolved backdrop chain contains a gradient or an image** — the single most important abstention in the pipeline. Also: backdrop is semi-transparent over an unresolvable chain; any ancestor carries `mix-blend-mode`, `filter`, or `backdrop-filter`. In every case the subject goes to X3 (§4.3), and only if X3 also abstains does it reach the judge. |
| **A2** target size | every element whose AX `role ∈ {button, link, checkbox, textbox, menuitem, tab, switch, radio, combobox}` | `min(w, h)` of the union of the box and its non-clipped `::before`/`::after` | FAIL if `min(w,h) < 44 − band`; `band = J1 + J2` (0.75 at dpr 1, 0.50 at dpr 2) | **This is the band that exists because our control flipped.** A box authored at exactly 44 px rendered as 43.x under a different display scale and turned a clean control defective. 44 is the WCAG 2.5.5 / iOS floor; the band absorbs one device pixel plus fractional layout and nothing more, so a genuinely 40 px target still fails. Pseudo-element union matters because a common idiom hits 44 with an invisible `::after` expander. | role comes from the AX tree and the AX tree is absent · the element is inside a `<canvas>` |
| **A3** focus-visible | every focusable element | drive `.focus()`, re-snapshot `outline*`, `box-shadow`, `border-color`, diff | FAIL if no property changed | Boolean; nothing to band. Requires state-driving, so it runs only when P2 supplies focus-state snapshots. | focus snapshots absent ⇒ INDETERMINATE for the whole page (never a silent PASS) |

### 2.5 O — containment

| id | Subject | Measurement | Threshold ± band | Reason | INDETERMINATE when |
|---|---|---|---|---|---|
| **O1** overflow / clipping | every element | `scroll.h > client.h + band` or `scroll.w > client.w + band`, cross-referenced with `overflow-*` | FAIL `clipped` when `overflow:hidden`, `FAIL overflowing` when `visible`; `band = 1.0` | 1 px: `scrollHeight` is an integer rounding of a fractional layout height, so a sub-pixel excess is a rounding artifact in every case measured. `hidden` and `visible` are different findings with different fixes and must not share a rule id. | the element is a scroll container by design (`overflow:auto|scroll` **and** a scrollbar is reachable) |
| **O2** truncation | every element with `text-overflow:ellipsis` | as O1, plus whether the clipped remainder is > 0 | report as `severity:low` FAIL with the truncated character count | Truncation is often intentional; the finding is informational and its *acceptability* (mid-word vs grammatical) is a judgement — P6's, not SCREEN's | `-webkit-line-clamp` present (the used line count is font-dependent) |

---

## 3. Two traps that produce confidently wrong numbers

### 3.1 The transform trap — why five rules abstain on `transform`

`DOMSnapshot`'s `bounds` is the **post-transform axis-aligned bounding box** in document space.
Measured: a `rotate(15deg) translateX(40px)` box reports `bounds:[48.8, 53.1, 84, 38.7]` while its
`offsetRect` and `clientRect` came back **empty arrays**. Two consequences SCREEN must encode rather
than discover at review time:

1. **The AABB of a rotated shape is a rectangle that does not exist on screen.** Alignment and gap
   arithmetic over it is arithmetic over a fiction. G1, G3, and X2 therefore declare
   `transform ≠ none` a precondition failure, not a special case.
2. **A `translate` moves box and ink together.** Any check that compares an element's ink to its
   *own* post-transform box is **invariant under the very compensation it is meant to verify**. This
   is not hypothetical: it is defect (a) in the shipped `bench/detect_xcheck.py` X2 arm, found by
   trying to validate it rather than by reading it. §4.2 states the repair.

`offsetRects` / `clientRects` are **sparse** — do not assume the arrays are dense, and do not read a
missing entry as a zero.

### 3.2 The sparsity trap — a miss is not an absence

`blendedBackgroundColors` is populated only for boxes that actually paint text: measured **99 of
2,009** layout entries on one page, **31 of 83** on the corpus control. Indexing by layout index and
treating `-1` as "no background" would mark 95% of a page as transparent. Every consumer indexes by
layout index, skips sentinels, and counts skips into `out_of_scope` — never into `pass`.

---

## 4. Classical-CV cross-checks — measuring the DISAGREEMENT

These are not a third detector. Each takes a claim the DOM makes about an element, measures the same
claim off the rendered pixels, and fires **only where the two answers differ by more than a stated
tolerance**. That gives them a property neither substrate has alone: no aesthetic judgement, no
learned model, and a finding that is automatically about the *render* rather than about authored
intent. A disagreement between two independent instruments is evidence in a way a single reading
never is.

Every operation named below is `cv2` / NumPy / `skimage`, single-core, on the already-captured PNG.

### 4.0 Shared preamble

```python
img   = np.asarray(Image.open(shot).convert("RGB")).astype(np.int16)   # H×W×3, sRGB
scale = img.shape[1] / snap["scroll"]["w"]      # derived from the artifacts, never a flag
assert abs(scale - manifest["deviceScaleFactor"]) < 0.01               # else exit 2
```

Deriving the scale from the artifacts and then asserting it against the manifest is deliberate: it
catches a shot/snapshot pairing error that a trusted flag would launder into a 2× coordinate offset.

### 4.1 X1 — zero-ink, by differential render

**The claim under test:** the DOM says a 200×48 box with text lives at (120, 400).
**The pixel question:** does anything the user can see change if that element does not exist?

The shipped implementation answers this by thresholding against the crop's **modal colour**, and
that is the second of its two known defects: on a round button the square crop's corners — page
background outside the circle — count as ink and swamp a 16 px glyph. Modal-colour background is a
guess about what the element's background *is*. The exact answer is available for one extra
screenshot:

```python
# 1. clip-capture the element's union box (box ∪ its shadow/outline spread), before
cdp("Page.captureScreenshot", clip={"x":ux,"y":uy,"width":uw,"height":uh,"scale":dpr})
# 2. hide ONLY this element, leaving layout untouched
cdp("Runtime.callFunctionOn", functionDeclaration="function(){this.style.visibility='hidden'}",
    objectId=resolve(backendNodeId))
# 3. clip-capture the same rect, after
delta = np.abs(before.astype(np.int32) - after.astype(np.int32)).sum(axis=2)   # H×W
ink_mask = delta > INK_DELTA          # INK_DELTA = 12  (≈3 levels/channel)
ink_frac = ink_mask.mean()
```

`visibility:hidden` and not `display:none`, because `display:none` removes the box from layout and
reflows every sibling — the diff would then be the whole page.

| Threshold | Value | Reason |
|---|---|---|
| `INK_DELTA` | 12 (sum over 3 channels of absolute difference) | 3 levels per channel. sRGB PNG round-trips exactly and LCD text is disabled, so the only sub-threshold source is grayscale anti-aliasing at the very edge of a glyph, which is ≤2 levels on a flat backdrop. Below 12, a change is not a change. |
| `INK_MIN_FRAC` | 0.002 of the union box | A 16 px glyph inside a 44 px round button occupies ≈0.008 of the box at 30% coverage; 0.002 is 4× below the thinnest real mark and above single-pixel PNG noise. |
| probe budget | ≤40 elements/page, ~15–40 ms each | Ranked candidates only (below). A full-page differential sweep is ~2,000 captures and is not the job. |

**What this arm uniquely catches**, and why the conflation is correct rather than sloppy: the delta
is zero for `opacity:0`, for `color` equal to background, for **occlusion by a higher-`z-index`
sibling**, for `overflow:hidden` clipping, for `clip-path` to empty, for a font that never loaded,
and for `content-visibility:hidden`. All seven are the same finding — *the DOM reports a healthy box
and the user sees nothing* — and all seven are invisible to a DOM-only reviewer, which reports a
correct layout on a broken page.

**Candidate ranking** (the probe budget is spent, not sprayed): elements with own text, sorted by
(has an ancestor with `opacity < 1` or `filter` or `mix-blend-mode`) → (G4 flagged an overlap) →
(`color` ΔE2000 < 5 from `blendedBackgroundColor`) → (largest box). Elements not probed are
`out_of_scope`, counted, and named in the census. **Not PASS.**

⚠️ **UNVERIFIED.** The differential-render arm is designed here, not measured — the shipped code uses
modal colour. **One probe settles it:** run both arms over the 13-page corpus and compare on the
round-button page (`optical-centering` variant) where the modal-colour arm is known to be swamped;
the differential arm must report `ink_frac` for the glyph within 20% of the glyph's own coverage, and
both arms must report zero findings on `clean.html`.

### 4.2 X2 — ink centroid vs box centre (both known defects repaired)

**The claim under test:** the DOM centres this glyph in this button.
**The pixel question:** is the ink actually in the middle of what the reader sees as the button?

The shipped arm is provisional and **ships disabled** for two reasons, and both repairs are
structural rather than parametric:

| Defect | Repair |
|---|---|
| **(a)** it compares ink to the element's **own** post-transform box, so a `translate` moves box and ink together and the measured offset is invariant under the compensation it should verify | Measure against the **container's content box**: `parent.rect` inset by the parent's resolved `padding-*` and `border-*-width`. That reference is *pre*-transform with respect to the child, so a child `translate` moves the ink and leaves the reference fixed — which is exactly the quantity optical compensation changes. Additionally require the parent to have no transform of its own, else INDETERMINATE. |
| **(b)** the background is the crop's **modal colour**, so a round button's square corners count as ink and swamp a 16 px glyph | Take the ink mask from **X1's differential render** (§4.1), which is the painted shape by construction — including `border-radius`, `box-shadow`, `::before`/`::after`, and any paint that extends past the border box. Then take the *glyph* mask as the differential of the text node alone, so the button's own fill is excluded from its own centroid. No modal colour anywhere in the computation. |

```python
ys, xs = np.nonzero(glyph_mask)                       # from the text-node differential
cx_ink, cy_ink = xs.mean()/scale, ys.mean()/scale     # CSS px, document space
cx_ref = ref.x + ref.w/2 ; cy_ref = ref.y + ref.h/2   # container content box
dx, dy = (cx_ink + ux) - cx_ref, (cy_ink + uy) - cy_ref
```

| Threshold | Value | Reason |
|---|---|---|
| `CENTROID_TOL` | `1.0 + J1` CSS px (1.5 at dpr 1, 1.25 at dpr 2) | Optical compensation in real design systems is 1–2 px (a triangular play glyph, a round icon's overhang). Below 1.0 the signal is the glyph's own asymmetry — a capital "R" is genuinely left-heavy. Above 2.0 it is a layout bug, not an optical one, and G1/G3 already own it. |
| eligibility | `w<64 ∧ h<64 ∧ len(text)≤3 ∧ ink_frac>0.02` | A paragraph's ink is legitimately top-left-heavy because text flows; centroid is only meaningful for a small self-contained mark. |

⚠️ **UNVERIFIED and shipping OFF (`--x2`) until both repairs are measured.** Shipping it on would
hand the pipeline a confident number with no ground truth behind it — the precise failure this whole
architecture exists to prevent. **One probe settles it:** the corpus's `optical-centering` variant
carries a real delta (the base has compensation, the variant removes it); the repaired arm must fire
on the variant, stay silent on `clean.html`, and — the discriminating case — stay silent on a
synthetic page where the compensation is applied by `transform: translateX(-2px)` instead of by
padding, which the current arm cannot see at all.

### 4.3 X3 — contrast sampled across a run, not at a point

**The claim under test:** `color:#333` on a backdrop the cascade resolves to `#fff` ⇒ 12.6:1.
**The pixel question:** what is actually behind this text, at both ends of it?

This is the arm that already **works** and already **removes a whole class from the model's queue**.
`getComputedStyle` runs before compositing, so `mix-blend-mode`, `filter`, `backdrop-filter` and
ancestor `opacity` all make the computed answer wrong; a gradient makes it unrepresentable. A single
scalar — including CDP's own `blendedBackgroundColor` — reports one end of the run.

```python
w      = region.shape[1]
bands  = {"left": region[:, :w//3], "mid": region[:, w//3:2*w//3], "right": region[:, -w//3:]}
# backdrop per band = modal colour of the NON-ink pixels, using X1's ink mask
bg     = {k: modal(b[~ink_mask_band(k)]) for k, b in bands.items()}
ratios = {k: wcag(fg, v) for k, v in bg.items()}
```

| Threshold | Value | Reason |
|---|---|---|
| `CONTRAST_SPREAD` | 1.5 ratio points between any two bands | Below 1.5, band-to-band variation is JPEG-free PNG sampling noise plus glyph-edge bleed. At 1.5 the two ends are answering different questions. Measured on the corpus gradient page: **4.81:1** in the left third and **1.57:1** in the right — a spread of 3.24. |
| verdict | if `min(ratios) < required` ⇒ **FAIL**, naming the failing end. If spread > 1.5 but all ends pass ⇒ FAIL `contrast-varies` at `severity:low`. If spread ≤ 1.5 and it agrees with A1 within 1.5 ⇒ **PASS** | The one band that fails a reader is the finding; an average over a gradient is a fiction. |
| `X3` vs `A1` disagreement | `|sampled − computed| > 1.5` with a solid computed backdrop ⇒ FAIL `contrast-composited` | This is the D3 case: a blend mode or filter destroyed a ratio the cascade still reports as passing. It is a correctness bug in every DOM-only accessibility audit of a page using modern compositing. |

**This arm is why A1's gradient abstention does not become the model's problem.** Measured: it turns
"unrepresentable" into two numbers and a verdict, with **zero findings on the control**. Contrast over
a gradient leaves the vision queue entirely.

### 4.4 X4 — component-instance drift

**The claim under test:** these six nodes share a class list, so they are six instances of one component.
**The pixel question:** do they render identically?

`cv2.matchTemplate(page, crop_of_instance_0, cv2.TM_CCOEFF_NORMED)` over the sibling set, or — cheaper
and exact for same-size siblings — a direct normalised correlation of the aligned crops.

| Threshold | Value | Reason |
|---|---|---|
| identical | score ≥ 0.995 | Anti-aliasing of a 1 px border at the same nominal geometry costs ≈0.002; below 0.995 something structural differs. |
| drift | 0.95 ≤ score < 0.995 ⇒ FAIL `component-drift` | The corpus's `radius-drift` (6 px vs an 8 px token, on one of four cards) sits here. This arm finds it **without a token file**, which is the whole value for `reso-landing-app`, where the purchased template is the oracle and no token map exists. |
| different | score < 0.95 ⇒ `out_of_scope` — not the same component | |
| INDETERMINATE | siblings differ in `rect.w`/`rect.h` by more than the band, or any contains an `<img>`/`<canvas>` | Different-sized instances are not comparable by correlation; raster content is texture, not design. |

### 4.5 X5 — sub-pixel row registration

`skimage.registration.phase_cross_correlation(row_a, row_b, upsample_factor=100)` registers to 1/100
of a pixel. FAIL when two nominally identical rows differ by `0.25 ≤ |dy| < 1.0` CSS px — the regime a
fractional `em`-derived `line-height` produces, which the DOM reports as identical integers and which
no perceptual metric ranks above anti-aliasing noise. Above 1.0, G3 already owns it. Below 0.25, it is
J1 at dpr 2.

### 4.6 X6 — raster asset sharpness

`cv2.Laplacian(gray_region, cv2.CV_64F).var()`. FAIL `upscaled-asset` when an `<img>`'s variance is
< 0.4× the median variance of the sibling images on the page **and** its `naturalWidth < rect.w × dpr`.
The ratio test rather than an absolute floor: a deliberately soft photograph and an upscaled 1× logo
have the same absolute variance and different neighbours. The `naturalWidth` conjunct is what makes it
a fact rather than a taste — without it, this arm is opining about photography, which is P6's job.

### 4.7 What SCREEN deliberately does NOT run

**No whole-image perceptual metric as a detector.** Measured on a nine-card fixture, one noise class
and seven real regressions: at Playwright's default `threshold:0.2`, three of seven real regressions
produce **literally zero** diff pixels (radius 12→8, colour `#171717→#1a1a1a`, border `#e5→#dd`) and a
fourth (1 px shift, 1,728 px) ranks *below* pure anti-aliasing noise (1,889 px). SSIM inverts on four
of seven; FLIP inverts on five — and FLIP is *right* to, because it answers "would a human notice"
while design review asks "is this wrong". Token drift is invisible-but-wrong by construction, so it
sits in the null space of every metric calibrated to human noticeability. **The DOM answers token
correctness, the pixels answer paint-level correctness, and neither is asked the other's question.**
FLIP's one defensible role is a noise gate on a screenshot *pair* (mean > ~0.02 ⇒ worth a model call;
5.8× separation, the only clean floor measured) — SCREEN reviews one frame, so that belongs to
whichever stage owns baselines.

**No learned detector.** The best learned GUI element detector reaches `F1 = 0.438 at IoU > 0.9`,
which on a 200×48 button still permits ~5 px of boundary error — and every number SCREEN produces is
arithmetic on a box edge, where `getBoundingClientRect` is exact and free. The failure shapes decide
it: classical CV fails by returning an obviously wrong number, a learned model by returning a
plausible one, and the consumer is an agent that will *act*.

---

## 5. Output schema

```jsonc
{
  "schema": "screen/1",
  "page": { "url": "...", "route": "/dashboard", "profile": "reso-management-app" },
  "capture": { "deviceScaleFactor": 2, "forcedDeviceScaleFactor": true,
               "viewport": {"w":1280,"h":900}, "colorScheme": "light",
               "snapshotSha256": "…", "shotSha256": "…", "capturedAt": "…" },
  "bands":   { "J1": 0.25, "J2": 0.25, "J3": 0.5, "note": "derived from capture.deviceScaleFactor" },
  "grid":    { "unit": 8, "adherence": 0.785, "source": "discovered" },
  "census":  { "subjects": 1841, "pass": 1732, "fail": 14, "indeterminate": 95, "out_of_scope": 0,
               "byRule": { "A1": {"pass":68,"fail":2,"indeterminate":13}, "…": {} } },

  "findings": [
    {
      "fp": "b3d1c0…",                       // §5.1
      "rule": "A2", "ruleName": "target-size", "verdict": "FAIL", "severity": "high",
      "subject": { "path": "div.toolbar > button:nth-of-type(3)",
                   "backendNodeId": 8814, "frameId": "…",
                   "rect": {"x":1088,"y":24,"w":30,"h":30,"right":1118,"bottom":54} },
      "measured": { "minEdge": 30.0, "unit": "css-px" },
      "expected": { "floor": 44.0, "band": 0.5 },
      "claim": "min-edge",                    // the discriminator; see §5.1
      "detail": "30x30px against a 44px floor (band 0.5 at dpr 2)",
      "evidence": { "source": "dom", "crop": null }
    },
    {
      "fp": "77af21…",
      "rule": "A1", "ruleName": "contrast", "verdict": "INDETERMINATE", "severity": "high",
      "subject": { "path": "section.hero > p.lede", "backendNodeId": 412, "rect": {…} },
      "reason": { "code": "backdrop-is-gradient",
                  "text": "resolved backdrop chain contains linear-gradient on section.hero; "
                          "requirement 4.5:1 is UNVERIFIED for this text" },
      "routed_to": "X3",                      // resolved downstream, did NOT reach the judge
      "evidence": { "crop": "crops/hero-lede@2x.png", "cropRect": {…} }
    }
  ],

  "judge_queue": [                            // §5.2 — the ONLY thing P5/P6 is asked to look at
    { "question": "Is the primary action the first thing a reader sees on this page?",
      "why_screen_cannot": "visual-hierarchy is not a property of any node",
      "crop": "crops/hero@2x.png", "cropRect": {"x":0,"y":0,"w":1000,"h":760},
      "facts": { "primary_candidates": [ {"path":"…","area":6720,"contrast":6.7,"fontPx":16} ] } }
  ]
}
```

### 5.1 Fingerprint — the span must equal the claim

`fp = blake2s-128(rule_id ‖ subject.path ‖ claim)` where **`claim` is a rule-defined discriminator**,
not the location.

Measured failure this exists to prevent: deduplicating findings by `(rule, target)` **silently
swallowed a real defect** — the colour-token drift on the primary button was suppressed because an
unrelated `token-drift` finding already existed on that same element in the baseline. It scored 0/1
until the key was widened, then 1/1. The key has to span the claim, not just its location: for K1 the
claim is `"color"` or `"background-color"` plus the token drifted from; for A2 it is `"min-edge"`; for
G1 it is the flow axis. **`subject.path` alone is never the key.**

`fp` is stable across runs and across capture DPR (it contains no measured value), so P7 can carry
lifecycle state — `new` / `known` / `regressed` / `fixed` — on it. A reviewer that reprints the same
40 standing findings every run carries zero information.

### 5.2 The judge queue — the only interface to the model layer

SCREEN hands P5/P6 exactly two things: the INDETERMINATE set it could not resolve, and the
whole-page questions it is structurally unable to pose. Each item carries a **crop**, not the page.

| Rule | Value | Reason |
|---|---|---|
| crop size | ≤ **1000 × 1000 CSS px at dpr 2** | Detail comes from clipping, not from raising DPR. A 2500 px-tall full-page shot delivers **0.80× effective detail** — worse than a plain 1× viewport shot at any DPR, because Claude Code's Read tool clamps every ingested image to 2000×2000 px / ~3.75 MiB and degrades through palette-PNG (256 colours), then descending-quality JPEG, then resize. Capturing above the clamp is not fidelity, it is lossy recompression. |
| crop count | `--max-crops`, default **12**, hard cap **19** | Above 20 image blocks in one request the per-image cap tightens and oversized images are **rejected rather than downscaled** — it fails hard, not gracefully. 19 leaves one block for the page overview. |
| ranking when over budget | `severity` → number of subjects sharing the reason code → box area | An abstention affecting 40 text runs is one crop and one question, not 40. |
| format | JSON coordinates alongside the clean crop; **never an annotated overlay as a standing input** | An overlay is a full second image (~3,240 tokens) on top of the clean one; the same findings as JSON coordinates are ~840 tokens, ~4× cheaper. Render an overlay only when a human will look at it. |
| token budget | the whole deterministic fact-pack serialises to ~854 tokens — **fewer than one screenshot** (1,100–1,600) | There is no context-budget argument for withholding facts from the judge. Send the numbers. |

The prompt contract SCREEN's output implies, stated so P6 can inherit it verbatim:

> The numbers below are measured, not estimated. Do not re-derive them and do not comment on spacing
> adherence, contrast ratios, target sizes, grid conformance or palette membership except to
> interpret what is stated. Judge hierarchy, rhythm, grouping, optical alignment, state coverage and
> content fit. Where a value is marked INDETERMINATE, the reason is given; that is the question.

---

## 6. Per-app profiles — three different problems, one harness

The three apps do not share a token source, and the reference oracle differs per app. Measured from
the manifests today (which corrects the brief in two places):

| App | Actual stack (measured 2026-08-26) | Oracle | Rule weighting |
|---|---|---|---|
| **reso-management-app** | Next **16.2.6**, React **19.2.4**, **both** Panda CSS 1.9 + `@park-ui/panda-preset` 0.43.1 **and** Tailwind 4.2.4 | a real semantic-token system in `panda.config.ts` | **K-family is the job.** K1–K4 at `severity:high`; G2 grid discovered from the Panda spacing ramp; X4 low value (tokens already answer it). Two token systems coexist, so the resolved token map must be the union with a `source` field per token, and a value matching neither is `undeclared-colour`. |
| **reso-landing-app** | Next **14.2.11**, React 18, Tailwind **3.4.7**, "radiant" purchased template; `tailwind.config.js` extends only `fontFamily`, `borderRadius.4xl` | **the template is the oracle**; there is no token map to diff against | **K-family mostly INDETERMINATE** (no ramp, no palette) — and it must say so rather than pass. **X4 component drift carries the load**, because it needs no token file: it asks whether the six instances still render alike. G1/G3 unchanged. |
| **reso-web-app** | Next **15.5.24** (not 13), React 18, **Chakra UI 2.4.1** + Emotion, `theme/` with `components.ts` | Chakra theme tokens, extractable but not resolved by Panda's codegen | Between the two. K1/K3 run against the Chakra scale once P2 resolves it; until then they are INDETERMINATE, never PASS. |

A profile may reweight severity and may disable a rule (`out_of_scope`, counted). **A profile may not
loosen a band** — bands are physics, not policy.

---

## 7. The control gate and the false-positive budget

**No rule ships without a run against the clean control**, and a finding on the control is
**adjudicated, never suppressed**. Two outcomes only:

- the rule is overfitted or noisy ⇒ **fix the rule**; its findings elsewhere were worth nothing until
  it is fixed;
- the control is genuinely defective ⇒ **fix the control** and record the fix in the corpus manifest.

That second branch is not theoretical. Our first control run flagged four defects on the
hand-authored baseline; **three were real WCAG failures nobody noticed** — white on blue-600 is
3.68:1, blue-100 on blue-600 is 3.01:1, both under the 4.5:1 floor. A deterministic linter earned its
keep before it ever saw an injected defect. (Repaired by moving to blue-700: 6.70:1 and 5.49:1.)
The corollary is a rule about the instrument: **a corpus needs its own control run before it is
allowed to grade anything**, and ours did not get one until a third detector disagreed with it.

**Budget:** ~20% false positives is where an AI reviewer loses human credibility regardless of catch
rate. The two zero-FP runs on record — deterministic rules 9/9 with 0 FP, cross-check 1/2 with 0 FP —
are the baseline to defend, not a high-water mark to trade against recall. The consumer is an agent
that edits source, so a false positive does not cost attention, it costs a PR that makes the design
worse. Concretely, per release:

| Gate | Value |
|---|---|
| findings on `clean.html` | **0**, no exceptions, no baseline-diff suppression |
| `severity:high` FAIL precision on the seeded corpus | ≥ 0.95 |
| any rule whose FP rate on real pages exceeds 5% | demoted to `severity:low` and barred from `--gate` |
| INDETERMINATE share | reported, never targeted — driving it down is how a false PASS gets manufactured |

---

## 8. What SCREEN cannot do, and who owns it

Stated as a hard boundary, because the failure mode of a measurement layer is scope creep into
judgement, and the failure mode of a judgement layer is arithmetic. Owners below are named by
**role** (CAPTURE · SALIENCY · JUDGE · ATTRIBUTE); if the sibling specs number them differently, the
role is the binding half of the reference.

| Cannot | Why it is structurally out of reach | Owner |
|---|---|---|
| **"Does this page make sense"** — hierarchy, rhythm-as-composition, balance, grouping semantics, whether a page has a focal point | Not a property of any node. 78.5% adherence to a 4 px grid says nothing about whether `24/16/12` *in that sequence* makes a readable card. A perfect scale, badly applied, measures perfectly. | **P6 JUDGE.** Measured: Opus 5 blind found the inverted action hierarchy and text washed out over a gradient 2/2, and found three real defects nobody injected — an orphan legend, an unlabelled icon button, numeric columns left-aligned so digits do not line up. None is a violation; each is a judgement about whether the page makes sense. |
| **Fixation order** — *is the primary CTA seen first* | An ordering claim about a human visual system, not about a raster | **P5 SALIENCY.** UI-trained UMSI++ scores CC 0.833 against the best frontier VLM at 0.408 on the same test set, because early gaze is pre-semantic and a VLM reasons semantically. SCREEN can supply the compositional visual-weight terms (area, ΔE vs backdrop, isolation from the distance transform) but must not call the ranking a verdict. Licence unresolved. |
| **Interiors of `<canvas>` / WebGL / `<video>` / raster / SVG** | One node, one box, no interior. A chart drawn into a canvas contributes a width and a height. | **P6**, via a crop. SCREEN's contribution is to emit the box as INDETERMINATE with `reason.code: "opaque-leaf"` rather than PASS — the census must show the hole. |
| **Absence** — a missing empty state, an absent loading skeleton, no clear primary action | SCREEN enumerates what is present. No measurement over a DOM detects a node that was never authored. | **P6**, and only if the state was captured at all. |
| **Which states exist** — auth, empty/loading/error, breakpoints, theme | A snapshot is one state of one page at one width, and `prefers-reduced-motion:reduce` is set precisely to destroy the time axis for determinism | **P2 CAPTURE / state enumeration.** This is the gap A15 ranks M5: a review of the logged-out homepage at 1440 px reviews the marketing screenshot, not the product. |
| **file:line attribution** | SCREEN emits `backendNodeId` + `frameId` + `path`; mapping those to a React component and a source location is a different lookup | **P7 ATTRIBUTE** — `DOM.getNodeForLocation` plus React fiber debug metadata (what Next.js's own dev-overlay click-to-source uses). SCREEN's obligation is to carry `backendNodeId` on **every** finding so P7 is possible; a finding without it is a report, not an edit. |
| **Cross-engine divergence** | Everything here is Chromium; the DOM is the thing that is identical across engines | Out of scope for v1. Name it, do not approximate it. |
| **Motion quality** — easing, duration, whether it reads sluggish | `getComputedTiming()` returns duration/easing/delay with `auto` resolved, so "this transition is 400 ms and eases wrong" is an assert — but SCREEN captures with motion disabled | A motion stage. Trap to inherit: CDP `Animation.setPlaybackRate(0)` controls WAAPI but not `requestAnimationFrame`, while Playwright's `page.clock` patches rAF but not the document timeline. A harness using one has a silent hole, and a GSAP page reports "0 animations found" as a false green. |

**The one thing SCREEN owns that no other stage can:** everything below the perceptual threshold.
Opus 5 blind scored **0/2** on sub-perceptual precision — it missed a 1 px misalignment and a 5/255
colour drift. The deterministic layer scored **9/9** on the same corpus, including both. That split is
not a weakness to compensate for, it is the architecture: **the judge is forbidden to opine below the
perceptual threshold, and SCREEN is forbidden to opine above it.** A pipeline that lets either cross
the line re-creates the failure the other was hired to prevent.

---

## 9. Performance budget

Measured: `DOMSnapshot.captureSnapshot` **32.7 ms** for the whole tree with 32 style props (against
5,788 ms for the per-node CDP walk and 881 ms for the in-page `getComputedStyle` loop), AX tree
26.7 ms, screenshot 39 ms, the deterministic rules ~80 ms, the NumPy arms 50–150 ms. **Everything
except the differential probes is under 250 ms/page.** The probes are the whole cost: ≤40 × ~15–40 ms
= 0.6–1.6 s *(est.)*, total < 2 s/page. `--differential off` returns SCREEN to ~250 ms at the price
of X1 degrading to the modal-colour approximation and X2 being unavailable — and in that mode X2's
subjects report INDETERMINATE, never PASS.

---

## 10. UNVERIFIED — and the one probe that settles each

| # | Claim | Status | The one probe |
|---|---|---|---|
| U1 | The differential-render ink mask (§4.1) is more accurate than modal colour on non-rectangular elements | **UNVERIFIED** — designed here, not measured | Run both arms over the 13-page corpus; on the round-button page the differential arm must report the glyph's coverage within 20% while the modal arm is swamped, and both must report 0 findings on `clean.html`. |
| U2 | The repaired X2 (container reference + differential mask) detects optical-centering removal | **UNVERIFIED** — ships OFF | Run on the `optical-centering` variant (real delta, base has compensation) plus a synthetic page where compensation is applied by `transform:translateX(-2px)`; the arm must fire on both and stay silent on the control. The transform case is the discriminating one — the current arm is invariant there by construction. |
| U3 | `band = J1 + J2` is the right decomposition; J3 = 0.5 px/line box | **UNVERIFIED magnitudes** — J1 is arithmetic, J2 and J3 are estimates | Capture the corpus at dpr 1, 1.5, 2 and 3 with the scale factor forced, and histogram `|rect.x − round(rect.x)|` and per-line `y` drift. The band should fall out of the measured distribution's 99th percentile, not out of this table. |
| U4 | `INK_DELTA = 12` is above PNG/AA noise and below the thinnest real mark | **UNVERIFIED** | Diff two byte-identical captures of `clean.html`: the max channel delta must be 0. Then diff the control against a variant with `color: rgba(0,0,0,0.02)` text: the delta must exceed 12 on the glyph pixels. |
| U5 | X4's 0.995 identity floor separates AA from structure | **UNVERIFIED** | Correlate two instances of the same card that differ only by a 1 px sub-pixel offset (the known false-positive shape) against two differing by the corpus's 2 px radius drift; the scores must straddle 0.995. |
| U6 | 40 differential probes/page is enough coverage | **UNVERIFIED** | Run unbudgeted on the corpus and count how many X1 findings sit outside the top 40 candidates. If any, the ranking is wrong, not the budget. |
| U7 | Two coexisting token systems in `reso-management-app` (Panda + Tailwind 4) can be resolved into one map without collisions | **UNVERIFIED** | Emit both resolved maps and intersect on value; any colour with two different names, or one name with two values, is a K-family precondition failure and must produce INDETERMINATE rather than an arbitrary pick. |

**Two things this spec deliberately does not do**, because the evidence forbids it: it does not score,
and it does not rank designs. Rubric scoring shows 16–39% top-1 ranking reversals from reordering
alone, and pairwise order-invariant consistent accuracy runs ~30–37% against a 25% chance baseline.
A number SCREEN cannot compute from pixels or from the DOM is a number SCREEN does not emit.




