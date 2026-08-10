# Composition — the rules the code enforces, and the numbers behind them

Read this when designing a new archetype or judging a layout. The full research is in
`lakehouse-lecture/docs/research/KPMG-BRAND-2026-08-08/B2-composition.md`, and — governing, since
2026-08-09 — `docs/research/KPMG-SYSTEM-2026-08-08/BUILD-SPEC-FY22.md` with its eight `FY22-*`
section files.

Rules below are marked **[stated]** (the FY22 book's own words, with a page) or **[measured]**
(pixel measurement of the book's artwork). The two are not interchangeable: measurement tells you
what KPMG did on one page, a statement tells you what KPMG permits. Anything unmarked is this
package's own construction and should be read as ours.

## The one rule behind all the others

**The KPMG page system is a gradient ground, one window, and type. It is not a layout grid.**

FY22 has **no layout groups, no page-type taxonomy and no colour-pair matrix.** All of that was the
2015 book, and the 2015 book is dead. What replaced it is a single graphic device — the window —
used with restraint, on one of two gradients, with type set left and in sentence case. Roughly
25 pages of the book (pp.70–96) specify that one device; nothing specifies a column grid.

> **This is the correction that mattered most, and it explains a symptom nobody could name.** An
> earlier build of this deck was composed on a nine-layout system with a 30-pair colour-adjacency
> matrix, both reconstructed from the 2015 book plus 95 rendered report pages. The output kept
> reading as *a blue theme* rather than as KPMG, no matter how correct the colour was — because the
> colour was never the thing carrying the identity. The window was, and we did not have it. Nine
> layouts became **no layouts**; thirty colour pairs became **two gradients**.
>
> Keep the reasoning, not just the conclusion: we had eleven years of inference and 95 pages of
> sampled output standing in for one page of specification. Sampling outputs tells you what someone
> did; only the rulebook tells you what is allowed. (`S7-fy22-brandbook.md`.)

## The grid

13.333 × 7.5in. Margins 1.09in left/right (measured off real KPMG decks), 0.66in top,
0.80in bottom holding the footer band. **12 columns**, 0.167in gutter, 0.10in baseline.

Twelve columns because it divides by 2, 3, 4 and 6 — halves, thirds, quarters and sixths all land
on real column lines. An 8-column grid cannot express thirds; a 10 cannot express quarters.

The top margin is tighter than the sides deliberately. A region with equal top and side margins
reads as bottom-heavy; the correction is the same one a book's page margins make. For the same
reason, a dominant statement sits on the **optical upper third**, not the true centre.

**Nothing computes its own position.** Callers ask `Grid` for a `Box`. A literal `Inches(2.37)`
in a slide builder is how drift starts, and it is invisible in review because 2.37 looks as
reasonable as 2.40.

> **This grid is OURS, and the section above should not be read as KPMG's.** Every argument in it
> holds — the twelve columns really do divide by 2, 3, 4 and 6, and a caller really should never
> compute its own position. But **KPMG specifies no grid at all**, and the margins here are
> measured off shipped member-firm decks rather than stated anywhere.
>
> What KPMG specifies instead is a **unit**: the height of the KPMG logo. Layout margin is 1 logo
> height, type inset 0.75, headline cap height ~2, window-to-logo gap 2 — all of it in § The window
> below. On the book's own slides that puts the left margin at **x 0.023–0.055** of slide width
> (22–53 pt at 960 pt) against our 78.5 pt. Ours is wider, deliberately, for a 140-person room.
> **Hold the grid; know that it is a construction, and that a KPMG reviewer's ruler is the logo.**

## The window — the device the whole system rests on

> *"Our window allows us to highlight the insight/opportunity by guiding the viewer's focus to the
> action… It is not intended to be used decoratively or manipulated to create alternate shapes."*
> [stated, p.72]

**What it is.** One box, **derived from the KPMG logo's four boxes**, with **square corners**. It is
either **7:10 vertical** or **10:7 horizontal** [stated, p.72] — *"never adjust the window
proportions"* is the one thing p.81 calls inflexible. A 16:9 slide takes either; the book's own
slides use both.

**Never more than one at a time** [stated, p.74, p.95 #1, p.96 #10]. Not two, not a repeated motif,
not a grid of them. **Never decorative** — it always holds or frames the content, and p.96 #9
separately bans decorative detail behind it.

**Corner radius = 0. No stroke, no shadow, no bevel.** The book never states a number, but it is
established by prohibition — the source shape is the logo's square-cornered box, p.72 forbids
manipulation into alternate shapes, p.95 forbids modifying the shape or proportions, and every
window across all 27 pages of the section is a plain rectangle [measured].

### Geometry — denominated in logo heights, and undefined until you supply one

Every measurement in the window section is expressed in **multiples of the KPMG logo's height**,
not as a page percentage [stated, pp.72–89]:

```
layout margin, and minimum window-to-edge clearance   1x logo height        p.81 C
window-to-logo gap                                    2x (1x when tight)    p.81 D, p.89
type inset, every edge the type touches               0.75x                 p.81 B
headline cap height                                   ~2x  ("a guide")      p.81 A
minimum window height, 16:9 slide   30% of layout height (horizontal window) / 40% (vertical)   p.88
placement                           to the RIGHT of the logo, or BELOW it — those two only      p.79
alignment    beside the logo: top-align to the logo · below the logo: left-align to it          p.81 E
```

🚨 **The logo's own height is not given in that section — which leaves every rule above undefined
until a value is supplied.** This is the load-bearing gap in the source, and it is easy to read
straight past: the section reads as fully specified because every number is present, and none of
them resolves. Section 05 never states the logo size; the authority is the logo section earlier in
the book.

**Ours: 36.0 pt on a 540 pt slide = 6.7%** — measured on four current KPMG covers, against
**6.2–6.5%** measured independently off the book's own window examples (15 px on a 231 px slide,
p.79; 16.3 px on a 262 px layout, p.81). The two agree closely enough to use, and 36.0 pt is the
number this package holds. Change it and every window measurement moves with it, which is the point.

**Measured practice on the book's own 16:9 slides — six examples, remarkably tight:**

| Page | Style | Aspect | Height ÷ slide height |
|---|---|---|---|
| 73 | 2, vertical | 0.710 | 80% |
| 74 | 2, horizontal | 1.411 | 79% |
| 79 | 2, horizontal | 1.419 | 77.5% |
| 79 | 2, vertical | 0.709 | 78.8% |
| 82 | 3, vertical | 0.711 | 79% |
| 87 | 4, vertical | 0.702 | 78% |

**On 16:9 the window's controlling dimension is its HEIGHT, at 78–80% of slide height** [measured],
hung from the logo line about 1 logo height in, leaving a deeper bottom margin (≈15% of slide
height). **It is not vertically centred** — that is the single most likely mistake, because centring
is what a layout engine does by default. A horizontal window at 79% height comes out at ≈63% of
slide width; a vertical one at ≈32%.

Note how far the stated *minimum* sits below observed practice: 30% is the floor, 79% is the house.
A window at 35% is legal and will not look like KPMG.

### The four styles, and only one puts type inside

| | **1** — behind people & objects | **2** — type holding shape | **3** — image holding shape | **4** — highlighting action |
|---|---|---|---|---|
| **For** | content *"in support of… giving them prominence"*; humanity or technology | *"moments when we need to elevate message-driven communications"* | *"establish a direct relationship between messaging and image"* | *"spotlights the action taking place within the layout"* |
| **What is inside** | nothing — the window sits *behind* a silhouetted person or object | **the headline and sub-copy** | a photograph or abstract hero image, filling it entirely | the un-overlaid (neutral) region of a full-bleed image |
| **The window's fill** | people: primary gradient as a light transparency · objects: opaque gradient | opaque | the image | the image, unoverlaid or lightly so |
| **The ground** | people: Gray 5 `#E5E5E5`, or primary gradient in light transparency over white · objects: opaque primary gradient | the paired half of the p.80 combination | **only three — see below** | the same photograph under a primary-gradient transparency |
| **Where the headline goes** | **outside**, on the ground, left, beside the window | **inside**, upper-left (lower-left when needed), always left-aligned | **outside**, on the ground, left; may extend over the window at discretion | **outside**, on the ground, left |
| **Type colour** | KPMG Blue on Gray 5; white on a gradient ground | white if the window is dark, KPMG Blue if light | **white**, on all three sanctioned grounds | white |
| **Its own constraint** | person/object covers **40–80%** of the window, on **≤2 sides**, never one side entirely (p.78) | the eight-combination colour list on p.80 | breakout element **≤ ½** the window's height or width (p.86) | **primary gradient only**, and only ever as a transparency |

**Three of the four styles put the headline on the ground, outside the window.** Only style 2 puts
type inside, and the book calls that the least characteristic use in as many words:

> *"Don't overemphasize the type relationship with the window; first and foremost, the window should
> interact with objects and people."* [stated, p.96 #13]

A deck built entirely from style 2 is technically compliant and is leaning on the one style the book
warns about. It is also the style a slide generator will reach for first, because a rectangle
holding text is the easiest thing to build.

### Style 3's hard colour prohibition

**The opaque background behind a style-3 window may be one of exactly three things** [stated, p.82]:
**primary Purple/Cobalt gradient**, **KPMG Blue solid**, or **Cobalt Blue solid**.

**The support gradient (Pacific → Light Blue) is forbidden there**, and the book gives its reason:
it *"overemphasizes the light blue brand colors, a departure from our color palette."* That is the
p.44 proportion rule enforced at the level of a single composition — Pacific and Light Blue are
allotted 8% each, and a full-bleed support-gradient ground spends the whole budget on one slide.

The general rule underneath it, in force across the section: **a Pacific/Light Blue window is never
allowed to float on white or on an unstated ground.** It requires a deliberate dark ground, and the
primary gradient is the reference case (p.77 puts a support-gradient window on an opaque
primary-gradient ground — the two-gradient pairing that is the book's page shape).

**Gradients run the same direction in ground and window** — 0°, left to right, both. The book never
counter-rotates them [measured, consistent with p.46].

## Furniture — two mutually exclusive states

[measured, the nine PowerPoint slides on p.113]

| | Logo | Footer |
|---|---|---|
| **Cover / statement slides** | **top-left**, x 0.033–0.040, y 0.076–0.086, width 0.066–0.069 | **none** — no copyright, no classification, no page number |
| **Content slides** | **none** at top-left; it appears in the footer band instead | band at **y 0.918–0.955**: logo · 2-line copyright paragraph (to x ≈ 0.52) · right-aligned `Document Classification: … | N`, the number in bold |

**Never both.** A cover with a page number, or a chart slide with a top-left logo, is off-system —
and it is the kind of error that reads as *wrong* long before a viewer can say why.

**One left margin governs everything.** Logo, headline, body and footer all start on it, and nothing
on any of the nine slides begins left of **x 0.023** (x 0.024–0.055 across the set).

## The page mix — an envelope, not a target

[measured, the nine slides on p.113]

| | |
|---|---|
| White ground | 4 / 9 |
| Coloured ground (flat or gradient) | 3 / 9 |
| Photographic ground | 2 / 9 |
| Carries a window | 5 / 9 |
| Carries a photograph anywhere | 6 / 9 |
| Carries the footer (content slides) | 6 / 9 |
| Carries the top-left logo instead (cover/statement) | 3 / 9 |
| Ink coverage, low to high | 8.7% – 77.1% |

**Read this as an envelope, not a target, and the reason is in what these nine slides are for.**
They are brand-book exemplars, composed to demonstrate the system's range on a single page — so
they are deliberately more varied than any real document. A 40-slide engagement deck built to hit
44% white and 22% photographic would be following a sampling artefact. What the figures do establish
is the **outer bounds**: a deck where every slide is white is under-using the system, and one where
every slide carries a window is over-using it.

The ink-coverage span is the most useful number here. **8.7% to 77.1% on nine consecutive slides**
is the rhythm — near-empty pages next to saturated ones — and it is achievable without any device
this package lacks.

## The type scale

Eleven values, roughly a 1.25 ratio, anchored on 20pt body:

`micro 11 · footnote 14 · caption 16 · small 18 · body 20 · lead 24 · h3 28 · h2 34 · h1 44 ·
display 60 · hero 88 · mega 150`

Hierarchy is read as **ratio**, not absolute size. A fixed scale means a viewer learns the deck's
grammar once — this size means "claim", that size means "support" — and every later slide is
legible without relearning. Free sizes produce a 37pt headline on one slide and 39pt on the next:
each locally defensible, collectively noise.

**14pt is a hard floor.** Below it, text is unreadable past the middle of a large room. The
standard consulting habit of dropping to 10pt to fit more on is exactly the move that turns a
slide into a document.

> **How this scale sits against the book's stated one.** FY22 p.63 specifies four desktop levels:
> headline **48–60 pt**, subheadline **24–30**, lead paragraph **14–20**, body **8–12** [stated].
> Two deliberate departures, both upward and both for the room rather than the desk:
>
> - **Our 14 pt floor sits above KPMG's 8–12 pt body.** Their number is document density; ours is a
>   140-person room. Keep the floor.
> - **`hero 88` and `mega 150` exceed the stated 48–60 pt headline range.** The book's own slides
>   go there too — the p.113 cover measures ≈80 pt and the closing statement ≈74–96 pt [measured] —
>   so the stated range describes ordinary headlines, not covers. `mega 150` has no support in the
>   book at any size; treat it as ours and use it rarely.
>
> One editorial constraint travels with the type size and is not really editorial: **real slide
> headlines in the book run 2–12 words, median 3** [measured, 13 exemplars]. At 48–60 pt that is
> arithmetic, not taste — ten words will not fit. `brand-kit.md` § Voice has the rest.

## Leading and tracking, which is where set type differs from typed text

**Display type needs NEGATIVE leading and NEGATIVE tracking.** Measured off a real KPMG cover:
88pt type with 73.9pt leading, a ratio of **0.84**. Type drawn for body copy carries sidebearings
tuned for 10–12pt; scaled to 60pt those gaps read as holes. Body runs the opposite way — 1.35
leading, because prose is read rather than scanned.

Tracking as a fraction of size: hero −0.022, display −0.018, h1 −0.014, h2 −0.010, body 0,
**eyebrow +0.10**. ~~Small tracked caps are legitimate for a two-or-three word label that is
scanned;~~ caps at a readable size destroy word-shape and measurably slow reading.

> **The eyebrow's small caps are prohibited, and this was easy to miss.** *"The KPMG style is
> sentence case for all copy; we do not use ALL CAPS or Title Case"* [stated three times — pp.61,
> 63, 69], with p.69 phrasing it as *"Don't use ALL CAPS or Title Case for headlines. All text
> should be in sentence case."* **All copy**, not just headlines. The typographic argument for a
> tracked micro-label is sound in general and does not survive this rule.
>
> Keep the +0.10 tracking value — an eyebrow set in **sentence case** still needs it, because a
> two-word label at 11 pt is scanned rather than read. What goes is the capitalisation, not the
> device. And note where the rule lives: in the **typography** section, not the voice section, which
> is why a search of the voice pages misses it entirely.
>
> The whole of leading, tracking, measure and ragging is **absent from the book** [stated as absent
> — nothing is specified anywhere]. Everything else in this section is therefore ours and stays
> ours; only the capitalisation was ever KPMG's to rule on.

## The line-height model — the correction that makes measurement true

PowerPoint's proportional line spacing multiplies the **font's own line height**
(ascent + descent), not the point size. Arial's is ~1.13em. So 34pt at 1.08 spacing occupies
**41pt, not 36.7pt**.

Under-measuring by 12% is invisible on one line and compounds. In this package's first build it
put the accent rule straight through the headline on five slides out of ten — all of which passed
every structural check, because valid XML in the wrong position is still valid XML.

**Always position the next element from the MEASURED bottom of the text above it**
(`Placed.bottom`), never from the height of the box you allocated.

## Rules the components enforce

- **One idea per slide.** If it needs a bullet list it is two slides, or it is speaker notes.
- **Max 5 items in a list, max 4 metrics, max 5 steps.** Working memory holds about four. A
  seven-item list is not retained; it is a document read aloud.
- **Never centre body text** — and now, never centre *anything*. ~~Centring is legitimate for a
  single short line and essentially nothing else.~~ *"All type within our communications should be
  set left-aligned"* (p.63); *"Don't center type and do not right-align type. Type should always be
  left-aligned"* (p.69) [stated]. **A centred title slide violates the book**, and that exemption
  for a single short line is exactly where a cover headline would have slipped through. The reason
  this file gave still holds — a ragged left edge gives the eye no consistent return point — it is
  simply no longer a judgment call.
- **Hairlines, not boxes.** 0.75pt rules separate without enclosing. A 1pt+ mid-grey rule reads
  as a border and starts boxing things in.
- **Callouts get a 4pt left bar, not a filled box.** A filled callout competes with the exhibit
  it comments on.
- ~~**A gradient between two hues is decoration; between two lightness steps of one hue it is a
  surface.** The middle of a two-hue ramp turns muddy under projection.~~

  > **Superseded, and it is the most direct contradiction the FY22 book produced.** KPMG's two
  > sanctioned gradients are **both two-hue**: Purple `#7213EA` → Cobalt `#1E49E2`, and Pacific
  > `#00B8F5` → Light Blue `#ACEAFF` [stated, p.46]. They are not decoration — they are the
  > **ground**, the surface the whole page system sits on. And the single-hue lightness ramp this
  > rule recommended instead is not a sanctioned gradient at all: *"do not create new gradients."*
  >
  > So the rule inverted the actual system. Both stops, midpoint, angle and the flipping rule are in
  > `brand-kit.md` § The two gradients; use those two and no others.
  >
  > **The projection caution underneath it was real and is worth keeping as a caution.** A two-hue
  > ramp's midpoint does lose separation on a projector — Purple→Cobalt passes through a muddy
  > violet at 50%. The response is not to substitute a different gradient but to **avoid setting
  > type over the midpoint**, which the book independently requires: gradients are for backgrounds,
  > never for typography, and never behind graphs [p.53 rule 3].
- **Shadows encode elevation only.** The stock Office theme puts a shadow on every autoshape —
  the most reliable tell of a generated deck. `theme.flatten_effect_styles` removes it.

## The consulting exhibit

**Action title.** The headline states the finding, not the subject. "Revenue by region" labels
the chart; "Three regions grew; the fourth carried the loss" tells the reader what to look for
before they look. Highest-leverage rule available and it costs only the discipline of writing a
sentence.

**Ghosting.** Exactly one datum carries emphasis — accent colour, the rest muted. An exhibit
where everything is equally coloured has no argument, only data.

**Direct labelling, no legend.** A legend makes the reader bounce between key and mark.

**No gridlines, no axis lines, no tick marks.** A light track behind each bar does the job an
axis would — showing the maximum — without a line.

**A source line on every exhibit.** A figure without one is an assertion; with one it is
evidence.

**Never a pie chart.** Judging relative angle is among the least accurate perceptual tasks;
judging length on a common baseline is among the most. A single stacked bar signals "these sum to
a whole" just as clearly. Use `proportion_bar`.

## Projection reality

A conference projector in a lit room loses substantial contrast against a laptop screen. Mid-tone
on mid-tone that measures 3.2:1 and passes WCAG will not read from the back of a 140-person room.
Treat 3.0 as the legal floor and **4.5 as the practical one**.
