#!/usr/bin/env python3
"""
proof.py -- the deck that argues for its own construction.

WHAT THIS IS FOR. The engine had been producing decks that were correct on every measurable
axis and still read, to the person who commissioned them, as "a generic blue theme". Correct
hexes, correct type scale, zero gate failures, and the wrong system. This deck is the evidence
that the diagnosis was right and the fix is real, so it is built to be judged beside KPMG's own
pages rather than beside our rules.

THE GOVERNING STATEMENT, which every page supports:

    KPMG's FY22 system is a gradient ground, one window, and type -- and a deck that misses the
    window is a blue theme no matter how correct its hex values are.

READ ONLY THE HEADLINES, IN ORDER. They carry the whole argument without the slides. That is
the test this file is written against, and it is the reason the headline strings here are
claims with verbs rather than the topic labels a specimen sheet would use.

PROVENANCE. Every rule cited is from *KPMG Brand guidelines, March 2022*, 137 pages, read in
full. Page numbers are the book's own. Where a number was measured off the book's artwork
rather than stated in its words, the slide says "measured" -- that distinction is the one this
project has been burned by most often and it is not decorative.

Run:  PYTHONPATH=assets python3 examples/proof.py
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "assets"))

from kpmg_deck import Brand  # noqa: E402
from kpmg_deck import charts as ch  # noqa: E402
from kpmg_deck import components as c  # noqa: E402
from kpmg_deck import imagery as im  # noqa: E402
from kpmg_deck.charts import Datum  # noqa: E402
from kpmg_deck.deck import Deck  # noqa: E402

# ---------------------------------------------------------------------------
# The running order, as section names for the nav strip.
# ---------------------------------------------------------------------------

NAV = ["The system", "Logo", "Colour", "The window", "Imagery", "Voice"]

d = Deck(
    Brand.load("kpmg"),
    owner="Chris Ren",
    doc_title="Built on the brand book, not on a blue theme",
    sections=NAV,
    standing_line="Derived from KPMG Brand guidelines, March 2022  ·  137 pages, read in full",
)


# ---------------------------------------------------------------------------
# 1 -- the cover. Gradient ground, the window holding the title. FY22 pp.46/72.
# ---------------------------------------------------------------------------

sl = d.window(
    "Built on the brand book",
    subhead="KPMG's FY22 system, in code",
)
d.notes(
    sl,
    "This cover is window style 2 -- the window as type-holding shape. It is the one "
    "composition on the brand book's own PowerPoint page (p.113) that carries display type, "
    "and the book is explicit that it is the least characteristic of the four styles. Saying "
    "so on the first slide is the point: the deck knows which move it is making.",
)

# ---------------------------------------------------------------------------
# 2 -- what the book actually replaced.
# ---------------------------------------------------------------------------

sl = d.blocks(
    "Nine layouts became one device",
    "And we had built the nine.",
    [
        (
            "What we had built",
            "Nine layout groups and a forty-two cell colour-pair matrix.",
        ),
        (
            "What March 2022 says",
            "No groups, no matrix. One device: the window, on two gradients.",
        ),
    ],
    eyebrow="THE CORRECTION",
)
d.notes(
    sl,
    "The nine-layout system was not sloppy work -- it was derived from measurement of real "
    "KPMG documents. That is precisely why it is worth naming: a method that produces a "
    "confident, internally consistent, well-evidenced answer to the wrong question will not "
    "announce itself. The only thing that caught it was obtaining the actual specification.",
)

# ---------------------------------------------------------------------------
# The supersession, on a time axis. Two brand books eleven years apart, and the two corrections
# we made in between on evidence that was real and not authoritative.
# ---------------------------------------------------------------------------

sl = d.exhibit(
    "Eleven years, two systems, and one of them is current",
    lambda s, ctx, box: c.timeline(
        s,
        ctx,
        box,
        [
            c.Moment(
                "2015", "The brand book we rebuilt on", "Nine layouts, a 42-pair matrix"
            ),
            c.Moment(
                "Mar 2022", "The book that replaced it", "One window, two gradients"
            ),
            c.Moment("Aug 2026", "We obtain it, in full", "137 pages", emphasis=True),
        ],
    ),
    source="Both books held in full; the 2022 edition obtained 2026-08-09",
    takeaway="Everything built before that date was a faithful reading of a superseded rule.",
    eyebrow="THE CORRECTION",
)
d.notes(
    sl,
    "The dates matter because the failure was not carelessness. The 2015 system was "
    "reconstructed from real KPMG documents and reproduced faithfully; it was simply no longer "
    "the rule. There is no amount of care applied to the wrong source that reaches the right "
    "answer, which is why obtaining the specification outranked every further measurement.",
)

# ---------------------------------------------------------------------------
# SECTION 02 -- THE LOGO. Nineteen pages of the book, and the reason this deck does not
# reproduce the mark is itself one of the rules.
# ---------------------------------------------------------------------------

sl = d.window(
    "The mark is the organisation speaking",
    subhead="Everything else on these pages is only style.",
    support_ground=True,
)
d.notes(
    sl,
    "The distinction the whole logo section turns on, and the one that decides whether a third "
    "party may ship a thing at all. Style can be matched by anyone; the mark cannot be used by "
    "anyone. Put as a window page because it is an assertion rather than an explanation.",
)

# NOT another annotated_figure. The window-geometry page later in the deck is already a giant
# "1x" with three leaders off it, and two pages built from the same figure at the same size read
# as one page at contact-sheet size -- which is exactly what the monotony check said when both
# were in. The rule here is the same unit; the page should not be the same picture.
sl = d.blocks(
    "The clear space is the whole logo again",
    "The same unit the window is measured in.",
    [
        (
            "Clear space",
            "The logo's own height and width on every side; half that where constrained.",
        ),
        (
            "Support copy",
            "No larger than a quarter of the logo height, wherever it sits.",
        ),
    ],
    eyebrow="THE LOGO",
)
d.notes(
    sl,
    "pp.35-36. The book relaxes this rule explicitly in one place -- 'the clear space rule is "
    "not rigid in every circumstance' -- and says a background image does not infringe it. "
    "Both are worth knowing before treating the measurement as absolute. That the logo and the "
    "window are denominated in the same unit is what makes the two devices sit together on a "
    "page rather than merely near each other.",
)

sl = d.quote_panel(
    "Don't lock the logo up with other text — a name, a function, a service, a paragraph.",
    "KPMG Brand guidelines, March 2022",
    "Section 02, page 39",
    headline="Six things you may not do to the mark",
    support=lambda s, ctx, box: c.rows(
        s,
        ctx,
        box,
        [
            ("Never reversed", "Nor rotated, distorted or recoloured."),
            ("Never rearranged", "No KP over MG. No letters without boxes."),
        ],
    ),
)
d.notes(
    sl,
    "A quote is a change of voice, which is what earns it the panel: this page is the book "
    "speaking rather than us summarising it. The stated exception to recolouring is 'logo as "
    "hero'. Three of the six are shown because a page of prohibitions read from the back of a "
    "room is a page nobody retains.",
)

sl = d.versus(
    "The logo and the footer never appear together",
    "Cover and statement pages",
    [
        "Logo, top left",
        "No footer",
        "No page number",
        "No classification",
    ],
    "Content pages",
    [
        "No logo",
        "Footer with the copyright line",
        "Page number, right aligned",
        "Classification beside it",
    ],
)
d.notes(
    sl,
    "Measured off the nine slides on p.113: the two states are mutually exclusive and never "
    "both. This deck follows it -- the window pages carry no footer and every working page "
    "carries no logo. It is the cheapest rule in the book to obey and among the most visible "
    "when broken.",
)

sl = d.statement(
    "This deck carries no logo, deliberately",
    "The risk runs the opposite way to intuition.",
    "Palette, type scale and grid are style, and style is not owned. The logo and the "
    "copyright line are the organisation speaking.",
    support=lambda s, ctx, box: c.rows(
        s,
        ctx,
        box,
        [
            (
                "Safe mode, the default",
                "Style only. No mark, no copyright line.",
            ),
            (
                "Licensed mode",
                "Their own material, reviewed as normal.",
            ),
        ],
    ),
    eyebrow="THE LOGO",
)
d.notes(
    sl,
    "The engine defaults to safe mode and prints the reason in its build log. Licensed mode "
    "needs the exact member-firm name and entity form, which vary by firm and are a compliance "
    "surface -- never guessed.",
)

# ---------------------------------------------------------------------------
# 3 -- the window's geometry, which is stated and therefore checkable.
# ---------------------------------------------------------------------------

sl = d.exhibit(
    "Every distance in the window is measured in logo heights",
    lambda s, ctx, box: c.annotated_figure(
        s,
        ctx,
        box,
        "1x",
        [
            (
                0.16,
                "Layout margin, and the minimum clearance from the window to any edge",
            ),
            (0.50, "Window-to-logo gap is 2x, or 1x where the layout is tight"),
            (0.84, "Type inset is 0.75x on every edge the type touches"),
        ],
        label="logo height",
    ),
    source="KPMG Brand guidelines, March 2022, pp.72-89 [stated]",
    takeaway="The book never gives the logo's height, so all four rules stay undefined "
    "until you supply it. Ours is 36.0 pt.",
    eyebrow="THE WINDOW",
)
d.notes(
    sl,
    "This is the sharpest example in the book of a specification that is complete in form and "
    "unusable in fact. Four rules, all stated in the same unit, and the unit itself is never "
    "given a value in that section. We measured 36.0 pt against four current KPMG covers, "
    "which came out at 6.7 percent of slide height, against 6.2 to 6.5 percent measured "
    "independently off the book's own window examples.",
)

# ---------------------------------------------------------------------------
# 4 -- the four styles, and which one we had been living in.
# ---------------------------------------------------------------------------

sl = d.exhibit(
    "Only one window style holds type",
    lambda s, ctx, box: ch.table(
        s,
        ctx,
        box,
        ["Style", "What sits in the window", "Where the headline goes"],
        [
            ["1", "People and objects, in front of it", "On the ground"],
            ["2", "The headline itself", "Inside the window"],
            ["3", "An image", "On the ground"],
            ["4", "The action, highlighted", "On the ground"],
        ],
        emphasis_row=1,
    ),
    source="KPMG Brand guidelines, March 2022, pp.74-89 [stated]",
    takeaway="Style 2 is the one every deck reaches for and the one the book calls least "
    "characteristic.",
    eyebrow="THE WINDOW",
)
d.notes(
    sl,
    "The book's own words, p.74: 'don't overemphasize the type relationship with the window; "
    "first and foremost the window should interact with objects and people.' Every deck this "
    "engine had produced used style 2 and nothing else, which is how a correct device still "
    "produced a wrong-looking page.",
)

# ---------------------------------------------------------------------------
# Style 1's geometry, which is the most specific thing the window section states.
# ---------------------------------------------------------------------------

sl = d.metrics(
    "A subject may cover the window, within a band",
    [
        ("40-80%", "of the window the subject may cover", "Style 1, stated as a range"),
        ("2", "sides it may cross, at most", "Never one side in its entirety"),
        ("1", "window on a page, ever", "Never in multiples, never decorative"),
    ],
    source="KPMG Brand guidelines, March 2022, pp.78, 96 [stated]",
)
d.notes(
    sl,
    "Styles 1 and 4 both need a masked subject -- a person or an object cut out of its "
    "background -- so neither is built here: we hold no photography of people and generating "
    "one would be inventing a subject rather than treating one. The geometry is stated, so the "
    "constraint can be asserted the day a licensed image arrives.",
)

# ---------------------------------------------------------------------------
# 5 -- the count that explains the whole complaint.
# ---------------------------------------------------------------------------

sl = d.exhibit(
    "Six of the book's nine slides carry a photograph",
    lambda s, ctx, box: ch.unit_grid(
        s,
        ctx,
        box,
        6,
        9,
        columns=3,
        caption="Slides carrying a photograph, on the brand book's own PowerPoint page",
    ),
    source="KPMG Brand guidelines, March 2022, p.113 [measured, the nine slides printed there]",
    takeaway="A deck with no imagery is not a restrained version of this system. It is a "
    "different system.",
    eyebrow="IMAGERY",
)
d.notes(
    sl,
    "Read this beside the previous slide. Five of the nine carry a window, six carry a "
    "photograph, and the overlap is where the system actually lives -- the window is mostly a "
    "way of holding or framing an image, not a way of holding type. Treat the nine as an "
    "envelope rather than a target: they are exemplars composed to demonstrate range.",
)

# ---------------------------------------------------------------------------
# A window page, standing alone. THIS IS A CHANGE OF VOICE, NOT A SECTION MARKER, which is the
# distinction the package enforces everywhere else: full-colour fields belong to the cover, an
# attributed quote, the methodology page and the closing. A single claim carrying a whole page
# is the same move as a quote -- the deck stops explaining and asserts -- so it earns the field.
# ---------------------------------------------------------------------------

sl = d.window(
    "Colour was never the defect",
    subhead="Every hex value was already right when the deck was rejected.",
    support_ground=True,
)
d.notes(
    sl,
    "Worth saying out loud because it is the counter-intuitive part. A colour-only fix was "
    "built and measured first: cobalt reached 28.6 percent of the deck against KPMG's own 14.4 "
    "to 16.7, and a third of the pages were still near-empty. A coloured void is still a void.",
)

# ---------------------------------------------------------------------------
# Colour proportion. The one part of the palette that is specified as a QUANTITY.
# ---------------------------------------------------------------------------

sl = d.exhibit(
    "Two blues carry two thirds of the system",
    lambda s, ctx, box: ch.proportion_bar(
        s,
        ctx,
        box,
        [
            Datum("KPMG Blue", 33),
            Datum("Cobalt", 33),
            Datum("White", 9),
            Datum("Light Blue", 8),
            Datum("Pacific", 8),
            Datum("Dark Blue", 3, emphasis=True),
            Datum("Purple", 3, emphasis=True),
            Datum("Pink", 3, emphasis=True),
        ],
    ),
    source="KPMG Brand guidelines, March 2022, p.44 [measured off the printed bar; the one "
    "stated number agrees]",
    takeaway="The three marked are capped in the book's own words: no more than 2-3% of "
    "colour use at a time.",
    eyebrow="COLOUR",
)
d.notes(
    sl,
    "This is the rule that makes the style-3 prohibition make sense. Putting the Pacific/Light "
    "Blue support gradient behind a style-3 window is not banned because it is ugly -- it is "
    "banned because those two together would carry a page, and the palette allots them 16% "
    "between them. A proportion stated for the system is a constraint on every page in it.",
)

# ---------------------------------------------------------------------------
# 6 -- colour, and the refusal that matters most.
# ---------------------------------------------------------------------------

# THIS PAGE IS ITS OWN EVIDENCE. Both sanctioned gradients are on it and nothing else is: the
# support ramp as the ground, the primary in the window. Stating the rule on a white page would
# have been the weaker version of the same slide.
sl = d.window(
    "Two gradients, and a third is forbidden",
    subhead="Support on the ground, primary in the window. That is both of them.",
    support_ground=True,
)
d.notes(
    sl,
    "The four sampled ramps are worth remembering. They were real observations of real KPMG "
    "output, added to a guard built specifically to prevent generalising from member-firm "
    "material -- so the error was committed a second time inside the thing meant to stop it. "
    "A brand book is not a record of observations; it is the rule the observations follow.",
)

# ---------------------------------------------------------------------------
# 7 -- the trap no contrast checker can see.
# ---------------------------------------------------------------------------

sl = d.statement(
    "Eight colours are reserved for data",
    "On-palette, high-contrast, perfectly legible, and still forbidden as page furniture.",
    "Nothing about a colour's measured contrast tells you which side of that line it sits on, "
    "so the rule cannot be derived and has to be carried as data.",
    support=lambda s, ctx, box: c.rows(
        s,
        ctx,
        box,
        [
            (
                "Reserved for data",
                "#76D2FF · #510DBC · #B497FF · #AB0D82 · "
                "#FFA3DA · #098E7E · #00C0AE · #63EBDA",
            ),
            (
                "Never a field",
                "The book's own heading: don't use secondary colors for type.",
            ),
        ],
    ),
    eyebrow="COLOUR",
)
d.notes(
    sl,
    "This is the cleanest example in the whole system of a rule that is invisible to "
    "verification. Every automated check this package runs -- palette conformance, contrast, "
    "type floor -- passes a slide with a #B497FF field. Only the book says no.",
)

# ---------------------------------------------------------------------------
# 8 -- the ground, and the colour that was never a field. A coloured page.
# ---------------------------------------------------------------------------

sl = d.full_field(
    "The solid ground is KPMG Blue. Cobalt was never a flat field",
    body="Cobalt appears on the book's own slides only as a gradient endpoint and a chart ring. "
    "Filling a panel with it is a characteristic near-miss: correct palette, wrong role.",
    standfirst="Measured, both solid-ground slides on p.113.",
)
d.notes(
    sl,
    "A colour field marks a change of voice, never a change of section. The book's full-colour "
    "fields are the cover, an attributed quote, the methodology page and the closing. Using "
    "one for a section boundary is a category error that a palette change cannot fix.",
)

# ---------------------------------------------------------------------------
# 9-12 -- imagery. The four pages that carry the actual answer to "still just a blue theme",
# because the device the engine was missing is mostly a way of holding an IMAGE.
#
# The source images are generated by `kpmg_deck.imagery.synthetic_field` rather than licensed.
# That is not a workaround: p.104 makes abstraction a first-class KPMG hero-image category in
# its own right -- "an evolution of our textured imagery" -- alongside photography, with its own
# stated criteria. `imagery.load_source()` takes a real photograph in the same slot with no
# other change, which is the path if licensed material is ever held.
# ---------------------------------------------------------------------------

HERO = im.synthetic_field(2200, 1240, seed=11, kind="ribbon")

sl = d.image_field(
    "The colour layer is what makes an image KPMG's",
    image=HERO,
    standfirst="Purple/Cobalt over the image, and the treatment is specified rather than "
    "tasteful.",
    body="The book gives the blending recipes and says which layouts each belongs to.",
    treatment="softlight_multiply",
)
d.notes(
    sl,
    "Soft Light at 100 percent plus Multiply at 40 percent of the same gradient, which is the "
    "second of the book's two stated recipes (pp.91-93). The first is Overlay at 65 percent. "
    "PowerPoint has no blend modes at all, so both are composited in Pillow and inserted as a "
    "flat image -- which is the only way this rule can be honoured in a .pptx.",
)


def _recipes(s, ctx, box):
    """The same source image under each approved treatment, untreated first, left to right."""
    gap = c.points(9)
    cell_w = (box.width - gap * 3) // 4
    cell_h = int(cell_w * 0.72)
    plate = im.crop_to_fill(HERO, 640, 460)
    shots = [
        plate,
        im.treat(plate, mode="overlay", depth="light"),
        im.treat(plate, mode="overlay", depth="moderate"),
        im.treat(plate, mode="overlay", depth="moderate_deep"),
    ]
    for i, img in enumerate(shots):
        s.shapes.add_picture(
            im.to_png_bytes(img),
            box.left + i * (cell_w + gap),
            box.top,
            width=cell_w,
            height=cell_h,
        )
    c.body(
        s,
        ctx,
        c.Box(box.left, box.top + cell_h + c.points(10), box.width, c.points(36)),
        "Source  ·  Light  ·  Moderate  ·  Moderate-deep",
    )


sl = d.exhibit(
    "The overlay runs a ramp, not a single setting",
    _recipes,
    source="KPMG Brand guidelines, March 2022, p.92 [stated; the step sizes are ours]",
    takeaway="Depth is chosen by what the layout needs the image to do. The fourth step, "
    "opaque, is a composition rather than a treatment -- and the engine says so.",
    eyebrow="IMAGERY",
)
d.notes(
    sl,
    "p.91 gives the sequence: start from an image of overall neutral tone, mask the subject out "
    "of the colour edit, apply Hue/Saturation at -50 saturation and +40 lightness to strip the "
    "blue cast, and only then lay the gradient over it. The masked subject is what keeps the "
    "pop of colour that stops the result going flat.",
)

sl = d.window_image(
    "Style 3 puts the image inside the window",
    image=im.synthetic_field(1400, 1000, seed=29, kind="ribbon"),
    subhead="Purple/Cobalt behind it. The support gradient is forbidden here.",
)
d.notes(
    sl,
    "p.82 names three permitted grounds for this style -- the Purple/Cobalt gradient, KPMG Blue "
    "solid, Cobalt solid -- and rules out the Pacific/Light Blue support gradient explicitly, "
    "because it overemphasises the light blues against the palette proportions on p.44. The "
    "engine raises if you ask for it, which is the only reason that rule survives contact with "
    "a caller in a hurry.",
)

sl = d.image_split(
    "An interior page carries an image too",
    "This is the shape most of a real deck is made of, and the one the engine could not build.",
    "Six of the nine slides on the book's own PowerPoint page carry a photograph, and only one "
    "of them is a cover. Treating imagery as a cover-only device is what produced a deck that "
    "was correct on every measurable axis and still read as a template.",
    image=im.synthetic_field(1500, 1500, seed=47, kind="structure"),
    treatment="overlay",
)
d.notes(
    sl,
    "Overlay at 65 percent here rather than the deeper recipe: this image sits beside body copy "
    "rather than under type, so it does not need to lose its detail. Choosing the lighter step "
    "for a working page is exactly the judgment the four-step ramp exists to make available.",
)

# ---------------------------------------------------------------------------
# Skin tone. The book's most visible prohibition, and the only one that is pure arithmetic.
# ---------------------------------------------------------------------------

sl = d.process(
    "A person is blended back over the colour",
    [
        ("Adjust", "Standard tones need adjusting for hero use."),
        ("Overlay", "Purple and pink, consistent with the hero approach."),
        ("Mask", "The figure is cut from its background, crop unchanged."),
        ("Blend back", "The figure returns over it at 40-60% on Normal."),
    ],
)
d.notes(
    sl,
    "p.103, five steps, of which four are shown. Step 4 is the failure case the book prints "
    "deliberately: the masked figure at 100% opacity, where foreground and background 'appear "
    "too disparate in color'. The engine implements this as arithmetic rather than judgment -- "
    "0.6 x figure plus 0.4 x colour-adjusted, verified to within 2/255 per channel against the "
    "book's own final panel -- and refuses a skin_blend outside the stated band, or one given "
    "without a mask, because a skin rescue with no idea where the skin is would silently do "
    "nothing.",
)

# ---------------------------------------------------------------------------
# SECTION 01 -- VOICE. Twenty-one pages, and the section that constrains a teaching deck most.
# ---------------------------------------------------------------------------

sl = d.window_image(
    "An insight is not an instruction",
    image=im.synthetic_field(1400, 1000, seed=61, kind="ribbon"),
    subhead="Twenty-one pages of the book are about what you may say.",
)
d.notes(
    sl,
    "Opening the voice section on a style-3 window rather than a white page, because the "
    "sections of this deck are otherwise indistinguishable at contact-sheet size and the "
    "monotony check said so before a reader had to.",
)

sl = d.points_slide(
    "Three principles, each a pair of bounds",
    [
        (
            "Smart",
            "Because we connect information directly to insight, rather than reporting it.",
        ),
        (
            "Clear",
            "Because we express ideas transparently, elegantly and accessibly to all.",
        ),
        (
            "Confident",
            "Bold not brazen. Assertive not aggressive. Expert not arrogant.",
        ),
    ],
    eyebrow="VOICE",
)
d.notes(
    sl,
    "Each principle is structured identically on its page: a 'because' clause, a 'this means "
    "that we' line, three 'X but not Y' pairs under 'we sound', and three bolded instructions. "
    "The pairs are the usable part -- they bound the register from both sides, which a single "
    "adjective cannot.",
)

sl = d.versus(
    "The checklist an insight has to clear",
    "Write this",
    [
        "Intuitive — the reader recognises it",
        "Data-driven — a number carries it",
        "Specific — it names the case",
        "Actionable — it sparks a move",
    ],
    "Not this",
    [
        "Obvious — they already knew",
        "Data-centric — the number IS it",
        "Inaccessible — only experts follow",
        "Instructional — 'companies should'",
    ],
)
d.notes(
    sl,
    "p.11, four pairs, each printed with a worked do and don't. The book's own don't example "
    "for the last pair opens 'Companies should invest in...' -- a directive statement about "
    "what to do.",
)

sl = d.full_field(
    "The book rejects the instructional register",
    body="It is what a course deck produces by default. The fix is not softer wording: state "
    "what is true and let the action follow.",
    standfirst="'Actionable but not instructional' is the fourth pair on the checklist.",
    color=d.brand.color("canvas_brand"),
)
d.notes(
    sl,
    "This is the one finding in the voice section that changes what a KPMG-branded teaching "
    "deck may say, as opposed to how it looks, and it is the reason it is a full field here: "
    "a colour field marks a change of voice, and this page IS the change of voice.",
)

# ---------------------------------------------------------------------------
# SECTION 07 -- BRAND IN ACTION. Fifteen pages showing the system applied, and the one place
# the book stops specifying and starts demonstrating.
# ---------------------------------------------------------------------------

sl = d.image_split(
    "The same system, at four sizes",
    "A publication cover, a social post, a slide and a page all take the same three parts.",
    "The book's applications section is where the pieces stop being rules and start being "
    "compositions: a gradient ground, one window, and type. What changes between a poster and "
    "a slide is the window's proportion and how much type it holds -- not the system.",
    image=im.synthetic_field(1500, 1500, seed=73, kind="ribbon"),
    treatment="overlay",
)
d.notes(
    sl,
    "pp.110-124. The publication cover on p.112 is the clearest single example in the book of "
    "the abstraction class from p.104 doing real work -- a flowing three-dimensional form in "
    "the primary gradient, held in a light-blue window, with the headline inside it.",
)

sl = d.image_field(
    "Nothing here is a template",
    image=im.treat(
        im.synthetic_field(2200, 1240, seed=97, kind="ribbon"),
        mode="overlay",
        depth="light",
    ),
    standfirst="Three parts, recombined. That is the whole system.",
    body="A gradient ground. One window. Type. Every page in the book, and every page in this "
    "deck, is those three in a different arrangement.",
    treatment="softlight_multiply",
)
d.notes(
    sl,
    "Treated twice deliberately -- once light on the way in, then the full recipe in the "
    "archetype -- which is what the deeper end of the p.92 ramp looks like when the type has to "
    "sit over the middle of the frame rather than at its edge.",
)

# ---------------------------------------------------------------------------
# 13 -- typography.
# ---------------------------------------------------------------------------

sl = d.metrics(
    "The type scale, as the book states it",
    [
        ("48-60", "Headline, KPMG Bold", "pt, desktop"),
        ("24-30", "Subheadline, KPMG Bold", "pt"),
        ("14-20", "Lead paragraph, Arial", "pt"),
        ("8-12", "Body, Arial", "pt"),
    ],
    source="KPMG Brand guidelines, March 2022, p.63 [stated]. Leading, tracking, measure and "
    "ragging appear nowhere in 137 pages -- ours are inferred.",
)
d.notes(
    sl,
    "Setting display type in Arial is a workaround forced by not holding the licensed face, "
    "not compliance. The honest form of that sentence matters: citing the book's Office "
    "guidance as permission for an Arial headline would be quoting a rule that says the "
    "opposite of what it is being used for.",
)

# ---------------------------------------------------------------------------
# The second window page, opening the verification argument.
# ---------------------------------------------------------------------------

sl = d.window(
    "A brand is a set of refusals",
    subhead="And the refusals are the part that cannot be inferred from looking at output.",
)
d.notes(
    sl,
    "This is the whole finding in one line. Everything measurable about KPMG's system -- the "
    "palette, the type scale, the grid -- was recoverable from published material. What was "
    "not recoverable was what the system forbids: the third gradient, the eight data colours "
    "as fields, the support gradient behind a style-3 window. Only the rulebook carries those.",
)

# ---------------------------------------------------------------------------
# 14 -- accessibility, and the record that had to be corrected.
# ---------------------------------------------------------------------------

sl = d.exhibit(
    "KPMG prints three of its own pairs as failures",
    lambda s, ctx, box: ch.table(
        s,
        ctx,
        box,
        ["Pair, as the book prints it", "Ratio", "Normal text"],
        [
            ["White on Gray 3", "2.88:1", "Fail"],
            ["White on Gray 4", "2.12:1", "Fail"],
            ["KPMG Blue on Cobalt", "1.67:1", "Fail"],
            ["KPMG Blue on White", "11.3:1", "Pass"],
            ["White on the gradient", "7:1 / 6.76:1", "Pass"],
        ],
        emphasis_row=0,
    ),
    source="KPMG Brand guidelines, March 2022, pp.128-131 [stated]",
    takeaway="What we logged as a deviation from KPMG was mostly compliance with it.",
    eyebrow="THE GATES",
    ground=c.Ground.DARK,
)
d.notes(
    sl,
    "This package's brand file used to record that no published KPMG accessibility standard "
    "could be found in public material. Pages 126 to 136 are an accessibility appendix with "
    "per-colour WCAG tables, so that note was false. Note also that the gradient is scored as "
    "a RANGE across its ramp, which is the right way to score a gradient and is what this "
    "engine now does.",
)

# ---------------------------------------------------------------------------
# 15 -- the statement the whole verification section turns on. A coloured page.
# ---------------------------------------------------------------------------

sl = d.full_field(
    "A green checker means the deck is not broken. It does not mean the deck is good",
    body="In this package's first build, five slides in ten had the accent rule struck through "
    "the headline. Every one passed every structural check, because valid XML in the wrong "
    "position is still valid XML.",
    standfirst="Which is why rendering every slide and looking at it is a required phase.",
    color=d.brand.color("canvas_brand"),
)
d.notes(
    sl,
    "The general form of this: a check can only fail what it was built to measure, and the "
    "defects that survive to the room are the ones nobody thought to measure. Rendering is the "
    "only step that catches an unknown class.",
)

# ---------------------------------------------------------------------------
# 16 -- the gate that was counting the wrong thing.
# ---------------------------------------------------------------------------

sl = d.key_findings(
    "Six identical slides passed every gate",
    [
        ("43", "slides in the reference deck", "deck"),
        ("6", "of them rendered indistinguishable", "dup"),
        ("0", "errors reported by the old gates", "gate"),
    ],
    standfirst="The old check counted archetype names. Three different names render as the "
    "same picture, so it read green.",
)
d.notes(
    sl,
    "The replacement reads the renders rather than the file: near-duplicate pages are an error "
    "with no defensible reading, and a single visual shape carrying more than a quarter of the "
    "deck is a warning that names the slides. Ink coverage and layout shape are not in the "
    "XML, which is why both of these checks have to open the PNGs.",
)

# ---------------------------------------------------------------------------
# 17 -- the deck measured against the book it claims to follow.
# ---------------------------------------------------------------------------

sl = d.exhibit(
    "This deck sits inside the book's own envelope",
    lambda s, ctx, box: ch.stacked_bar(
        s,
        ctx,
        box,
        [
            (
                "The book, p.113",
                [
                    Datum("White", 4),
                    Datum("Colour", 3),
                    Datum("Photo", 2, emphasis=True),
                ],
            ),
            (
                "This deck",
                [
                    Datum("White", 9),
                    Datum("Colour", 5),
                    Datum("Photo", 4, emphasis=True),
                ],
            ),
        ],
    ),
    source="KPMG Brand guidelines, March 2022, p.113 [measured] against this file's output",
    takeaway="An envelope, not a target. The nine are exemplars built to show range.",
    eyebrow="THE GATES",
)
d.notes(
    sl,
    "Saying 'inside the envelope' rather than 'matches' is the honest form. A checker that "
    "reported a real deck as wrong for not matching a demonstration reel would be worse than "
    "no checker, which is why the device-mix check is warning-only and says what it is "
    "comparing against.",
)

# ---------------------------------------------------------------------------
# 18 -- the close.
# ---------------------------------------------------------------------------

sl = d.closing(
    "The system is a gradient ground, one window, and type",
    [
        "Not a palette. The palette was the part we already had right.",
        "Everything above is enforced in code, and the engine raises rather than approximates.",
    ],
)
d.notes(
    sl,
    "Close on the system rather than on the tooling. The engine is the means; the finding is "
    "that a brand is a set of refusals, and that the refusals are the part that cannot be "
    "inferred from looking at output.",
)

# ---------------------------------------------------------------------------

# Save beside this script rather than into the caller's cwd, so the render and verify commands
# in SKILL.md resolve the same path whichever directory the build was launched from.
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "proof.pptx")
d.save(OUT)
for line in d.build_log():
    print("  " + line)
print(f"saved {d.slide_count} slides -> {OUT}")
