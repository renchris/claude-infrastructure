"""
Every archetype, once. The reference for what the package can express.

Run it after any change to deck.py: it is the cheapest check that the public API still
composes, and it is what caught `section()` and `statement()` silently changing shape.
"""
import sys; sys.path.insert(0,"/Users/chrisren/.claude/skills/kpmg-deck/assets")
from kpmg_deck import Brand
from kpmg_deck import components as C
from kpmg_deck.deck import Deck
from kpmg_deck.charts import Datum, bar_chart, ring_gauge

SECTIONS = ["Workspace", "Systems", "Session", "Plan", "Sign-off", "Scale"]

d = Deck(Brand.load("kpmg"), owner="Chris Ren",
         doc_title="Designing decks that survive the room",
         sections=SECTIONS,
         standing_line="Reference deck  ·  kpmg-deck skill")
for line in d.build_log(): print(" ", line)

# `window()`, not `cover()`: cover() is superseded and raises -- its KPMG Blue -> Cobalt ramp
# is not one of the two gradients FY22 permits. This is the type-holding window, style 2.
d.window("Decks that survive the room",
         subhead="A reference deck for the kpmg-deck skill")

# A section opener is a WHITE working page: number, rule, two-tone headline, cobalt
# standfirst, and the section's real argument beside it. `body` is required, because a
# section opener with nothing to say is the near-empty page this package exists to prevent.
d.section(1, "Set up a clean workspace",
          "An agent that cannot find your files will confidently invent them.",
          "A folder is not a filing convenience. It is the entire world the agent can see, "
          "and anything outside it does not exist.\n\n"
          "Point at what you already have rather than copying it in. A copy drifts the moment "
          "you make it; a pointer cannot.",
          aside=lambda s, ctx, box: ring_gauge(
              s, ctx, box, 0.62, label="62%", diameter_pt=96))

# A claim, its argument, and one supporting element. All three are required arguments.
d.statement("You do not need to be a software engineer to be an excellent AI engineer.",
            "The load-bearing skill is saying clearly what you want.",
            "Executive communication and the ability to elicit the real requirement are what "
            "the work turns on. The software falls out of research and planning done well.",
            eyebrow="The claim",
            support=lambda s, ctx, box: C.contrast_pair(
                s, ctx, box,
                "The engineer", "One rung. The technical half is already held.",
                "Everyone else", "Two rungs, same top level.",
                emphasis="right"))

# The workhorse: white content plus one full-bleed cobalt panel, 29.8% of KPMG's pages.
d.split("Colour marks a change of voice, never a change of section",
        "Section openers are white working pages.",
        "KPMG's full-colour fields are reserved for four things: the cover, an attributed "
        "quote, the methodology page, and the closing. Using one for a section boundary is a "
        "category error that survives every recolouring.",
        panel_build=lambda s, ctx, box: C.body(
            s, ctx, box,
            "24 of 24 measured full-height panels are Cobalt #1E49E2.\n\nNone is #00338D. "
            "Filling a panel with the master blue is a characteristic near-miss: correct "
            "palette, wrong role.",
            role="lead", color=ctx.brand.color("on_dark"), strict=False))

# An attributed pull-quote IS a change of voice, so it earns a colour field.
d.quote_panel("The danger is not being insufficiently on-brand. It is being too on-brand.",
              "Brand governance research", "Axis A6",
              headline="Why unlicensed decks omit the marks",
              support=lambda s, ctx, box: C.body(
                  s, ctx, box,
                  "An unlicensed third party shipping a deck with the marks on it has produced "
                  "a branded artifact that never went through brand review -- which is a "
                  "rejection trigger in a way that a merely on-palette deck never is.",
                  strict=False))

# The ring page. Always page 4 in all four measured CEO decks.
d.key_findings("Three of the four measured tells are architectural, not chromatic",
               [("69", "characters a page, median, against KPMG's 2,275-2,422", "density"),
                ("28", "of 37 pages under 8% ink, against ~2% of 62 real pages", "density"),
                ("9", "distinct layouts across 37 slides, against 21-23 in 22-23 pages",
                 "rhythm")],
               standfirst="Colour was never the defect.")

d.exhibit("Cobalt now carries as much of a KPMG document as the master blue",
          lambda s,c,b: bar_chart(s,c,b,[
              Datum("Cobalt", 121, emphasis=True),
              Datum("KPMG Blue", 98),
              Datum("Pacific blue", 24),
              Datum("Purple", 19),
              Datum("Pink", 1)],
              unit=" marks", label_width_in=2.0),
          source="Source: colour operators read from KPMG UK Insurance CEO Outlook, January 2026",
          takeaway="A deck built only on the master blue reads as a pre-2022 deck.")

d.points_slide("Three things separate a designed deck from a filled-in template", [
    ("The grid never moves", "Same margins, same headline position, every slide. Consistency is most of what reads as designed."),
    ("One idea per slide", "If it needs a bullet list, it is two slides or it is speaker notes."),
    ("The title states the finding", "Not 'Revenue by region' but 'Three regions grew; the fourth carried the loss'."),
])

d.process("How the deck gets built", [
    ("Measure", "Every string is measured against its box before it is written."),
    ("Compose", "Archetypes place content on the grid. Callers never set coordinates."),
    ("Render", "Every slide becomes a PNG."),
    ("Look", "The agent reads the images and finds what no library can measure."),
])

d.metrics("What the extraction established", [
    ("8", "brand colours recovered from KPMG's own stylesheet", "Every value tier-1 sourced"),
    ("0", "of those values appear on colour-aggregator sites", "All still serve the pre-2022 palette"),
    ("15", "KPMG artifacts measured directly", "Geometry, type scale and footer read from real files"),
])

d.versus("Two grounds, two legal foreground sets, and a caller who names neither",
         "On white",
         ["Body copy is KPMG Blue #00338D, not grey -- 19,680 characters measured in one report",
          "Headlines KPMG Blue; a headline set entirely in one blue is the tell",
          "Cobalt accent at 6.76:1, and it is the fill for every panel on the page",
          "Rules #B2B2B2; #E5E5E5 is the chart track and only that"],
         "On dark blue",
         ["Body copy white -- 10,997 characters of it measured on reversed panels",
          "Headlines white, closing in the pale tint rather than in cobalt",
          "Accent INVERTS to #ACEAFF: cobalt on the dark ground is 2.35:1 and illegal",
          "The quiet tone is the tint, never a grey: #B2B2B2 on cobalt is 3.19:1"])

# A full colour field: short headline, large indented standfirst, small body.
d.full_field("Type is the graphic",
             standfirst="A large two-tone headline, a hairline rule, a cobalt standfirst, and "
                        "60% of the page left white. No ornament at all.",
             body="This is how 90 of 95 photograph-free KPMG pages are carried. The devices "
                  "that carry the rest, in order of frequency: the full-bleed cobalt panel, "
                  "the number as the graphic, the oversized Pacific quote mark, and ring "
                  "gauges.")

d.closing("Built with the kpmg-deck skill", [
    "Every colour from the theme. Every position from the grid.",
    "Every string measured. Every slide rendered and looked at.",
])

d.save("showcase.pptx")
print(f"\nsaved {d.slide_count} slides")
