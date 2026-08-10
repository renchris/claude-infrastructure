---
name: kpmg-deck
description: Build genuinely well-designed PowerPoint decks in code, on a corporate brand system, with a render-and-look verification loop. Use when asked to make a .pptx, a slide deck, a client presentation, a board or steerco pack, a section divider or an exhibit; when a deck must match a corporate brand (KPMG ships configured; any brand works via a JSON file); when converting a document, report or markdown into slides; or when an existing deck needs rebuilding to a professional standard. Also use when asked how to avoid the PowerPoint "[Repaired]" dialog, how to stop generated slides overflowing, or how to make python-pptx output look designed rather than templated. NOT for editing an existing .pptx in place, and NOT for Google Slides or Keynote.
---

# Building a deck that survives the room it is shown in

This skill turns a set of claims into a `.pptx` that looks designed rather than filled in, and
proves it by rendering every slide and looking at it.

**The premise it is built on:** most generated decks fail for reasons that have nothing to do
with taste. Text overflows its box. A rule lands on a headline. Type sits at 2.9:1 on white. The
file opens with a repair dialog. None of those need a designer to prevent — they need
measurement, a grid, and a rendering step. So this skill encodes the judgment as **hard
constraint in code**, and an agent with no design instinct at all can drive it and get a good
result.

What it cannot do is have the idea. The argument, the claims, and which number matters are yours.

---

## Before anything: is the toolchain there

```bash
python3 -c "import pptx, PIL; print('ok')"          # python-pptx + Pillow
ls /Applications/LibreOffice.app >/dev/null && command -v pdftoppm   # the renderer
```

Missing pieces:

```bash
python3 -m pip install --user python-pptx pillow
brew install --cask libreoffice && brew install poppler
```

**If LibreOffice cannot be installed, say so and stop before building.** The render loop is not
a nice-to-have in this workflow — it is the only thing that catches the defects that matter.
Building without it means shipping unverified, and you should tell the user that rather than
quietly skipping the step.

Add the package to the path:

```python
import sys; sys.path.insert(0, "~/.claude/skills/kpmg-deck/assets")  # expand the ~
```

---

## The process

### Phase 1 — Fix the argument before opening the tooling

A deck is a structure of claims. Get it right on one page first; every later phase is cheaper.

1. **One governing statement** the whole deck supports. A sentence, not a topic.
2. **Three to five sections**, each with a statement of what it establishes.
3. **Each slide states one idea**, and its headline IS that idea.

The test, and it is not a matter of taste: **read only the headlines, in order.** They must tell
the whole argument by themselves. If a headline names a category — "Revenue by region", "Next
steps", "Key findings" — it has told the reader the KIND of thought coming rather than the
thought, and it needs rewriting into a claim: "Three regions grew; the fourth carried the loss."

This is also the house style of the brand shipped here. Of 160 current KPMG press-release
headlines, **zero are questions**, 46% carry a finite verb and 35% carry a digit. A KPMG headline
is a claim with a verb, in sentence case.

🚨 **A SLIDE headline is not a press-release headline, and the difference is the one that will
break your layout.** The median-10-words figure above is measured off press releases and is right
for press releases. Measured off thirteen real KPMG *slides*, display headlines run **2–12 words,
median 3**. The constraint is typographic rather than editorial: 48–60 pt type will not hold ten
words, and the archetypes here compute the rest of the page from what the headline leaves behind.
Write a 15-word slide headline and you will not get a wrapped headline — you will get a body box
with negative height, drawn over whatever is beneath it. Aim for 6–9 words and put the nuance in
the standfirst.

### Phase 2 — Choose brand mode

```python
from kpmg_deck import Brand
from kpmg_deck.deck import Deck

deck = Deck(Brand.load("kpmg"), owner="Author Name")          # default: SAFE
deck = Deck(Brand.load("kpmg"), licensed=True,                 # only if genuinely internal
            member_firm="KPMG LLP",
            firm_form="a Delaware limited liability partnership")
```

**Default to safe, and understand why the risk runs backwards from intuition.** The danger is
not being insufficiently on-brand — it is being *too* on-brand. Palette, type scale, grid and
editorial register are style, and style is neither owned nor restricted. The logo, the brand
line, and the corporate copyright statement are the organisation *speaking*. A third party
shipping those has produced a branded artifact that never went through brand review, which is a
rejection trigger in a way that an on-palette deck never is.

Set `licensed=True` only when the deck genuinely is the organisation's own material — in which
case it goes through their normal review like anything else, and `member_firm`/`firm_form` must
be the exact pair for that firm. Never guess them; they vary by member firm and the entity
sentence is a compliance surface.

Print `deck.build_log()` and relay any provenance warning to the user. The bundled KPMG values
are tier-1 public-source extractions, not the official brand kit.

### Phase 3 — Build, using archetypes only

Pick the archetype from the shape of the content. Do not invent layouts.

**`cover()` is superseded and raises.** Its ramp is KPMG Blue → Cobalt, measured off four real
KPMG report covers, and p.46 permits exactly two gradients of which that is not one. Use
`window()` or `window_image()`. Do not repair it by widening `oxml.GRADIENT_ADJACENCY` or passing
`unchecked=True` — that set was narrowed to the book's two ramps deliberately, and the error
message says so, because the previous failure pointed a reader straight at both wrong fixes.

**EVERY PAGE CARRIES THE CLAIM PLUS TWO SUPPORTING ELEMENTS.** That is why `section()` and
`statement()` take their body and their third element as REQUIRED arguments rather than
optional ones. It is not a style preference; it is the defect that made the previous version of
this package produce a generic template with correct hex values. Measured against 95 real KPMG
pages, that deck ran a median of 69 characters a page against their 2,275–2,422, and 28 of its
37 pages sat under 8% ink where roughly 2% of 62 real pages do — and the one real instance is a
back cover. A colour-only fix was built and measured first: cobalt reached 28.6% against KPMG's
own 14.4–16.7 and a third of the pages were still near-empty. **A coloured void is still a void.**

The second and third elements come from a closed list: a chart or small exhibit · a large stat
figure with a one-line gloss · an attributed pull-quote · a two-column contrast · a labelled
diagram · a worked terminal example.

**The system you are building in, in one line:** *a gradient ground, one window, and type.* KPMG's
FY22 brand guidelines (March 2022, 137 pages) replaced the older nine-layout, colour-pair system
outright — there are no layout groups, no page-type taxonomy and no pair matrix. There is one
graphic device, **the window**, on one of **two** permitted gradients. `references/composition.md`
carries the geometry; the four things worth knowing before you pick an archetype are:

- **The window is mostly an image-holder, not a type-holder.** Four styles exist; only style 2 puts
  type inside it, and the book calls that the least characteristic use. Six of the nine slides on
  its own PowerPoint page carry a photograph.
- **Exactly two gradients**, and creating a third is forbidden in the book's own words.
- **Eight palette colours are reserved for data** and are illegal as page furniture however well
  they read. No contrast or palette check can see this; the engine carries it as data.
- **Style 3 refuses the support gradient** behind it, because that overweights the light blues
  against the stated palette proportions.

| The content is… | Use | Hard limits |
|---|---|---|
| The opening, or a claim standing alone | `window(headline, subhead=, support_ground=)` | window style 2. **One window per page** |
| A claim + an image | `window_image(headline, image=, subhead=)` | window style 3. Refuses `support_ground` |
| A full-bleed image page | `image_field(headline, image=, standfirst=, body=, treatment=)` | type colour measured off the treated pixels |
| A working page + an image | `image_split(headline, standfirst, body, image=, treatment=)` | the interior workhorse |
| A section opening | `section(n, title, standfirst, body, aside=)` | **white working page.** `body` required |
| A claim + its argument | `statement(claim, standfirst, body, support=)` | all three required |
| A claim + a colour panel | `split(headline, standfirst, body, panel_build=)` | the workhorse: 29.8% of KPMG's pages |
| Someone else's words | `quote_panel(quote, name, role, support=)` | the house form. A quote IS a change of voice |
| 2–4 ring gauges | `key_findings(headline, [(value, gloss, group)])` | **max 4.** Colour-code by stream, not index |
| A full colour field | `full_field(headline, standfirst=, body=)` | cover · quote · methodology · closing ONLY |
| A claim + a figure | `exhibit(title, build, source=, takeaway=)` | title states the finding; source always |
| 2–5 parallel points | `points_slide(title, [(label, desc), …])` | code cap 5, **fits 3** |
| An ordered sequence | `process(title, [(label, desc), …])` | 2–5 steps |
| 2–4 big numbers | `metrics(title, [(value, label, caption), …])` | **max 4** |
| Two things contrasted | `versus(title, lt, [..], rt, [..])` | max 5 each side |
| The close | `closing(title, [lines])` | full field, KPMG Blue |

**A COLOUR FIELD MARKS A CHANGE OF VOICE, NEVER A CHANGE OF SECTION.** KPMG's section openers
are white working pages; their full-colour fields are reserved for four things — the cover, an
attributed quote, the methodology page, and the closing. This is the single easiest structural
mistake to make with this package, and recolouring does not fix it: the previous version used
colour for section boundaries and nothing else, and a rebuild that changed only the hue left the
category error exactly where it was.

Two more that are invariant, and both were got wrong before they were measured:

- **The interior headline is FLUSH LEFT and two-tone** — line 1 `#00338D`, every remaining line
  `#1E49E2`, always ending cobalt. The rightward staircase is a COVER move and appears on no
  interior page in 95. A headline set entirely in one blue is the clearest tell a deck is off
  the system.
- **A panel carries a FIGURE AND A GLOSS, not a headline.** The house panel is 283.3pt wide,
  which leaves 215pt of measure — nine characters at headline size. Real narrow panels
  (D3 p12, D2 p9) carry a ring or a numeral and a short white gloss, and nothing else.

Pass headlines as STRINGS, never as pre-split lines: `two_tone_headline` searches four sizes and
five line counts and measures the split against the actual column, which no `target_chars` guess
can do at more than one column width.

### How much each archetype actually holds

Measured by building a 35-page deck and reading the exceptions. **Every archetype computes its
content region from what the headline and standfirst leave behind**, so these are not fixed
capacities — they are what you get at a one-to-two-line headline. Write past them and the
component raises with the shortfall in points; it will not shrink type to fit.

| | Holds | And then |
|---|---|---|
| `blocks` | **2 items** comfortably; 3 needs a one-line headline AND a one-line standfirst | the body box goes to a few points and it raises |
| `points_slide` | **3 rows**, each one line of description | 4 rows needs ~298pt and the region is ~263pt |
| `rows` as a `statement` support | **2 rows** | the support region is ~167pt, which is two rows |
| `versus` | 4–5 short items a side, and they may be phrases | — |
| `metrics` / `key_findings` | **max 4** and **2–4** respectively | both raise above it |
| `window` subhead | **one line** | the headline is sized to FILL the window, so the subhead gets the remainder |
| `full_field` | standfirst + ~2 sentences | at a 6–9 word headline |

🚨 **Two traps, both of which cost a rebuild each.**

**The shortfall moves PERVERSELY with headline length in `window()`.** The headline is sized to
fill the window, so a *longer* headline trips the shrink loop and ends up occupying *less* total
height than a short one set at full size. "Shorten the headline" can therefore make the subhead
fit *less* often. The archetype now reserves the subhead first, so this is fixed — but the shape
of the surprise generalises: where a component sizes one element to consume the space, the other
element's failure will not respond the way you expect.

**A near-miss shows up as a line SLICED IN HALF, not as a missing line.** When a text frame
overflows its coloured block, the frame is still valid and `check_overflow` measures the frame —
so the render shows the last line cut by the block's lower edge and every checker reports clean.
If a page looks subtly wrong and verify is green, that is the first thing to look for.

**Imagery comes from `kpmg_deck.imagery`, and the treatment is specified rather than tasteful.**
PowerPoint has no blend modes, so every treatment is composited in Pillow and inserted as a flat
image — which is the only way the brand's rule can be honoured in a `.pptx` at all.

```python
from kpmg_deck import imagery as im

hero = im.load_source("photo.jpg")             # licensed photography drops in here
hero = im.synthetic_field(2200, 1240, seed=11) # or generate it: abstraction is a sanctioned class
deck.image_field("The claim", image=hero, treatment="softlight_multiply")
```

Three approved treatments and no fourth: `neutral` (−50 saturation, +40 lightness, subject masked
out) · `overlay` (the gradient at 65%) · `softlight_multiply` (Soft Light at 100% plus Multiply at
40%). **Neutral is the step BEFORE the overlay, not an alternative to it** — the book prints the
un-neutralised version as its failure case. If the image carries a person, pass `skin_blend` and
blend the untreated figure back at 40–60%, or you will fail the most visible prohibition in the
imagery section.

`synthetic_field` is not a stand-in for photography you could not license. The brand book makes
**abstraction a first-class hero-image category** in its own right, with stated criteria: simple
but graphic, precision and clarity rather than busy or muddy, a clear focal point, and a 3D quality
with "mass and volume — something you could pick up and hold". Every deck that uses it says so in
`build_log()`, so a deck can never silently imply it carries the organisation's own photography.

Figures for `exhibit` come from `kpmg_deck.charts` and `kpmg_deck.components`:

```python
from kpmg_deck.charts import Datum, bar_chart, column_chart, proportion_bar, table

data = [Datum("Cobalt", 121, emphasis=True), Datum("KPMG Blue", 98), Datum("Purple", 19)]
deck.exhibit("Cobalt now carries as much of the document as the master blue",
             lambda s, ctx, box: bar_chart(s, ctx, box, data, unit=" marks"),
             source="Source: KPMG UK Insurance CEO Outlook, January 2026",
             takeaway="A deck built only on the master blue reads as pre-2022.")
```

`emphasis=True` on exactly one datum is what makes an exhibit argue instead of display: that mark
renders in the accent, the rest in a muted tone, so the eye lands where the headline points.

The vocabulary, and what each one is FOR — pick by the argument, never by variety:

| Form | The argument it makes |
|---|---|
| `bar_chart` · `column_chart` | one quantity across categories |
| `proportion_bar` · `stacked_bar` | composition — what a total is made of |
| `unit_grid` | N of M as countable marks. Reads instantly; a bar cannot be counted |
| `waterfall` | a delta explained — what moved a total, and in which direction |
| `matrix_2x2` | two judgments crossed. **The axes must be things a reader can disagree with** |
| `timeline` | an ordered run of dated moments, one of them marked |
| `flow_diagram` | 3–5 stages joined, one route emphasised |
| `annotated_figure` | one number set large, with leaders taking annotations off it |
| `ring_gauge` · `stat_card` | a single figure that needs a gloss |
| `table` · `comparison` | values a reader will want to look up rather than take in |

Two rules that are easy to get wrong. **`matrix_2x2` with every item in one quadrant means the axes
were chosen to produce that answer** — cut the exhibit. And `unit_grid` beats a percentage whenever
the denominator is small and real: "6 of the book's 9 slides" lands where "67%" does not.

Add speaker notes to every content slide: `deck.notes(slide, "…")`. Notes are free and slides
are not — the claim goes on the slide, the argument goes in the notes. That split is what lets a
slide stay at one idea.

### Phase 4 — Verify mechanically

```bash
PYTHONPATH=~/.claude/skills/kpmg-deck/assets python3 -m kpmg_deck.verify deck.pptx kpmg
```

Pass the render directory too, and the DENSITY GATE runs as well:

```bash
bash ~/.claude/skills/kpmg-deck/scripts/render.sh deck.pptx render 110
PYTHONPATH=~/.claude/skills/kpmg-deck/assets python3 -m kpmg_deck.verify deck.pptx kpmg render
```

Checks package integrity (the "[Repaired]" gate), palette conformance, the 14pt type floor
(exempting the nav and footer bands by POSITION, never by size), off-slide geometry, contrast
against each slide's actual ground, **text overflow**, **page rhythm**, **layout diversity**, and
notes coverage. **Zero errors is required.** Warnings are judgment calls — read them, decide,
move on.

Three of those are worth knowing why they exist:

- **`check_overflow`** re-measures every text frame against its own box. It found 23 overflows
  the day it was added, on a deck that passed every other check — because an overflowing text
  frame is valid XML, on the slide, in the palette, above the type floor, and PowerPoint simply
  draws the extra lines over whatever is beneath them.
- **`check_rhythm`** reads the RENDER, not the file, because ink coverage is not in the XML. It
  fails any page under 8% ink. A slide can carry forty shapes and still be empty.
- **`check_siblings` is inverted from what you would expect.** It does not warn about a layout
  used once; it warns about one layout carrying more than 20% of the deck. KPMG runs 21–23
  distinct layouts across 22–23 pages, largest repeat 1–2. The failure mode is monotony, not
  variety.
- **`check_monotony` reads the RENDERS, because `check_siblings` counts the wrong thing.** It
  counts archetype *names*, and `statement`, `split` and `points_slide` are three names that draw
  one picture. A 43-slide reference deck shipped with **six literally indistinguishable pages** and
  every gate green. Near-duplicate pages are now an ERROR; one visual shape carrying more than ~25%
  of the deck is a warning that names the slides.
- **`check_device_mix` is warning-only, and deliberately loose.** It reports the deck's grounds and
  devices against the nine KPMG-authored slides on the brand book's own PowerPoint page. Those nine
  were composed to demonstrate range, so a real engagement deck is legitimately narrower and this
  can never be an error. **Read it for a device at ZERO** — that means part of the system is going
  unused, which is the defect that produced "a generic blue theme" in the first place.

### Phase 5 — Render and LOOK. This phase is not optional.

```bash
bash ~/.claude/skills/kpmg-deck/scripts/render.sh deck.pptx render 110
```

Then **read the PNGs with the Read tool** — a contact sheet first for consistency, then any
slide that looks wrong at full size:

```bash
magick montage render/slide-*.png -tile 2x -geometry 620x349+6+6 -background '#888888' contact.png
```

Look for what no library can measure:

- **Collisions.** Any two elements touching or overlapping.
- **A rule or line landing on text** rather than clearing it.
- **Ragged wrapping** — a one-word last line, a headline breaking mid-phrase.
- **Emphasis on the wrong mark** in an exhibit.
- **Sibling drift** — the same archetype looking different on two slides.
- **Optical imbalance** — a slide that reads bottom-heavy or lopsided.

Fix, rebuild, re-render. Repeat until clean.

**Why this phase is load-bearing, stated plainly:** in this package's own first build, five
slides out of ten had the accent rule struck straight through the headline. Every one passed
every structural check, because valid XML in the wrong position is still valid XML. The root
cause was a 12% under-measurement of line height that no amount of code review had found. It was
visible in about two seconds of looking at a contact sheet. **A green verify means the deck is
not broken. It does not mean the deck is good.**

---

## The rules the code enforces, and why

You do not have to remember these — the package raises if you break them. They are here so the
errors make sense.

**Text is measured before it is written, and never shrunk to fit.** If a headline does not fit,
`headline()` raises. That is a finding, not an obstacle: a headline that overflows is nearly
always carrying two ideas. Shrinking it would break the size ratio that encodes hierarchy, so
the slide would start lying about which idea is subordinate. Cut words instead. Pass
`allow_shrink_to="h3"` only when shrinking is genuinely right, and even then the size comes from
the scale, never a continuous search — so sibling slides stay siblings.

**Colour is chosen by the ground, not by the caller.** Components are told what they sit on and
pick their own legal foreground. This makes the worst mistake in a blue-heavy palette
unreachable: Cobalt on the dark blue ground measures 2.35:1 and is invisible in a lit room, so
the accent inverts to a light tint on dark automatically.

**Nothing sets a literal colour or coordinate.** Colours come from theme references, positions
from the grid. A deck built from `schemeClr` survives a template swap; one built from hex
literals silently stops matching the firm's material the next time the palette moves.

**There is no bullet function.** `points_slide` uses labelled rows separated by hairlines, capped
at five. The cap is the feature: beyond about four items a list stops being retained, and a
six-item list is a grouping that wants a level.

⚠️ **Its code cap and its actual capacity are different numbers, and the smaller one binds.** The
cap of five is editorial. What fits is **three** — the rows share whatever the headline and any
standfirst leave behind, and four rows need about 298pt against a region of about 263pt. Ask for
four and `rows()` raises with both figures rather than drawing them on top of each other. The cap
tells you when a list has stopped being a list; the geometry tells you when it has stopped
fitting, and it speaks first.

**Charts have no gridlines, no axis lines and no legend.** Direct labelling only. A legend makes
the reader bounce between the key and the marks; a label beside its own bar does not.

**Every exhibit carries a source line.** A figure without one is an assertion; with one it is
evidence.

**The refusals are the part you cannot infer from looking at output, and they are why this is a
package rather than a template.** Everything measurable about a brand — palette, type scale, grid —
is recoverable from published material. What is not recoverable is what the system *forbids*, and
each of these raises rather than approximating: a third gradient · any of the eight data-reserved
colours used as a field · the support gradient behind a style-3 window · more than one window on a
page · a headline shrunk to fit. This distinction was learned the expensive way. Four gradient
ramps were once added here from real, correctly-measured KPMG documents, with a confident argument
— and all four were disallowed by the brand book. **Sampling outputs tells you what someone did;
only the rulebook tells you what is allowed.**

---

## Using a different brand

The engine is brand-agnostic. The brand is data.

```bash
cp ~/.claude/skills/kpmg-deck/assets/kpmg_deck/brands/kpmg.json .../brands/acme.json
```

Edit the twelve `theme_colors` slots, the `roles` map, `dataviz` order and the two typefaces,
then `Brand.load("acme")`. Nothing else changes.

Three things to get right, because they are the ones people get wrong:

- **`accent1`–`accent6` are consumed in order by charts.** Put them in the sequence you want a
  multi-series chart to use.
- **Check every role against every ground** before trusting it. Run
  `tokens.contrast_verdict(fg, bg, size)`; the bundled KPMG file documents one deliberate
  deviation from the brand's own palette for exactly this reason — KPMG's muted grey `#989898`
  measures 2.88:1 on white and fails AA at every size, so this package declines to set text in
  it.
- **Only name a typeface the delivery machine has.** PowerPoint substitutes silently, and a
  substituted face re-flows every measured box — on the presenting machine, after every check
  passed on the building one. Most corporate display faces cannot legally be embedded anyway
  (`fsType` restrictions), which is why the Office-safe face is usually the correct choice
  rather than a compromise.

**If an official template `.pptx` exists, prefer it.** Open it with python-pptx, use its layouts,
and let the extracted values be the fallback. Extracted brand data is a good reconstruction, not
the brand kit.

---

## References

Load these only when the question calls for them.

| File | Read it when |
|---|---|
| `references/brand-kit.md` | You need a specific KPMG value, its provenance tier, or the contrast matrix |
| `references/composition.md` | You are designing a new archetype or judging a layout |
| `references/pptx-craft.md` | You hit a python-pptx limit, or a deck triggers "[Repaired]" |
| `references/verification.md` | You are extending the checks, or a LibreOffice render looks wrong |

Module map, if you are extending the package:

```
tokens.py      the type scale, spacing, Brand loading, contrast maths
canvas.py      the grid. Box/Grid. Every position resolves here
text.py        measurement and typography. The line-height model lives here
oxml.py        the safe raw-XML escapes (alpha, gradients, shadow, tracking, tables)
theme.py       rewrites theme1.xml so scheme colours resolve to brand
components.py  the design vocabulary, ground-aware
charts.py      exhibits drawn from primitives
imagery.py     source images, the brand's colour-layer treatments, the neutral-tone pre-step
deck.py        the archetypes. The public API
verify.py      the mechanical gates
```
