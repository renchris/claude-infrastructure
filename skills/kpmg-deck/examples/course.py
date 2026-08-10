"""
Build the KPMG Lakehouse course deck.

THE ARGUMENT IS IN content.py; THIS FILE IS THE SEQUENCE. That split matters because the two
are governed by different rules. The claims are delivered material and are asserted verbatim
against claims.json below -- if anyone edits one, this build fails rather than shipping a deck
that quietly disagrees with the course. The sequence is a design decision and is measured
against KPMG's own, read off the per-deck background strings:

    D1  A C D D D C D C D C D C D C D D D C C B B D D
    D2  A C D D D C D C D D C D C B D D D
    D3  A D D D C C D C D D D C D C C C D B B D D D
    D4  A D D D D D C D C D B D D C C D B D B B B D

    A cover   B full-bleed colour   C split (white + one panel)   D dense white

Five rules read straight off those strings, and this deck obeys all five:

  1. COLOUR BY PAGE 2. Every one of D1-D4 has a split or full-bleed page at position 2. Ours
     is the day-shape exhibit, which is why `split()` grew a `body_build` argument.
  2. NEVER MORE THAN TWO CONSECUTIVE WHITE PAGES in the first two thirds. The corpus maximum
     run is five and it occurs once, in the run-up to a methodology page.
  3. ALTERNATE THE PANEL SIDE. Handled by `split()` itself.
  4. CLOSE ON A CRESCENDO, THEN DROP TO WHITE. D1 ends C C B B D D; D4 ends B D B B B D.
  5. A COLOUR FIELD MEANS A CHANGE OF VOICE, NEVER A CHANGE OF SECTION. So the six section
     openers are white working pages and the full fields are reserved for the four claims that
     are genuinely someone changing register, plus the closing.

    python3 course.py && \\
      PYTHONPATH=~/.claude/skills/kpmg-deck/assets python3 -m kpmg_deck.verify course.pptx kpmg && \\
      bash ~/.claude/skills/kpmg-deck/scripts/render.sh course.pptx render 110

A green verify means NOT BROKEN. It never means good. Put the render beside
docs/research/KPMG-SYSTEM-2026-08-08/kpmg-pages/ and look at both.
"""

import json
import os
import sys

sys.path.insert(0, "/Users/chrisren/.claude/skills/kpmg-deck/assets")

from content import CLAIMS, INTERACTIVE, NAV, SECTIONS, SHORT  # noqa: E402

from kpmg_deck import Brand  # noqa: E402
from kpmg_deck import components as C  # noqa: E402
from kpmg_deck.canvas import Box, points  # noqa: E402
from kpmg_deck.charts import Datum, bar_chart, ring_gauge  # noqa: E402
from kpmg_deck.deck import Deck  # noqa: E402
from kpmg_deck import text as T  # noqa: E402
from kpmg_deck.tokens import SCALE, SPACE, tracking_pt  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# The claims are delivered material. Assert, do not trust.
# ---------------------------------------------------------------------------

DELIVERED = json.load(open(os.path.join(HERE, "claims.json")))
_ours = {}
for c in CLAIMS:
    _ours.setdefault(str(c["section"]), []).append(c["claim"])
if _ours != DELIVERED:
    for k in sorted(set(_ours) | set(DELIVERED)):
        a, b = _ours.get(k, []), DELIVERED.get(k, [])
        for missing in [x for x in b if x not in a]:
            print(f"  section {k}: DROPPED  {missing!r}")
        for extra in [x for x in a if x not in b]:
            print(f"  section {k}: ALTERED  {extra!r}")
    raise SystemExit(
        "content.py has diverged from claims.json. The 22 claims are delivered material, "
        "verbatim from COURSE.md, and are not editable here -- fix content.py, or change "
        "the course first and claims.json with it."
    )


# ---------------------------------------------------------------------------
# The supporting elements, as builders
# ---------------------------------------------------------------------------
#
# Each returns a `(slide, ctx, box)` builder. They exist as a closed set for the same reason
# the archetypes do: a page's third element should come from a vocabulary, not from whatever
# the author felt like drawing on that page.


def element_builder(kind, payload):
    if kind == "contrast":
        left_label, left_body, right_label, right_body, emphasis = payload
        return lambda s, ctx, box: C.contrast_pair(
            s,
            ctx,
            box,
            left_label,
            left_body,
            right_label,
            right_body,
            emphasis=emphasis,
        )

    if kind == "code":
        lines, caption = payload
        return lambda s, ctx, box: C.code_block(s, ctx, box, lines, caption=caption)

    if kind == "stat":
        value, label, caption = payload
        return lambda s, ctx, box: C.stat(s, ctx, box, value, label, caption=caption)

    if kind == "rings":

        def build(s, ctx, box):
            n = len(payload)
            row_h = box.height // n
            for i, (value_label, gloss, _group) in enumerate(payload):
                d = min(points(88), row_h - points(SPACE["sm"]))
                top = box.top + i * row_h
                ring_gauge(
                    s,
                    ctx,
                    Box(box.left, top, d, d),
                    1.0,
                    color=ctx.brand.dataviz[i % 3],
                    label=value_label,
                    diameter_pt=d / 12700,
                )
                C.body(
                    s,
                    ctx,
                    Box(
                        box.left + d + points(SPACE["md"]),
                        top,
                        box.width - d - points(SPACE["md"]),
                        row_h,
                    ),
                    gloss,
                    role="small",
                    strict=False,
                )

        return build

    raise ValueError(f"no element builder for {kind!r}")


def panel_builder(lead, items):
    """
    The panel's own content: a bold white lead line, then two or three label/body pairs.

    NO HEADLINE. That was the first version of this and it could not be built: a 34pt headline
    in the house panel's 215pt of measure fits nine characters, so `two_tone_headline` raised
    rather than shipping a headline broken across five lines. Going and looking at what a real
    narrow panel carries settled it -- D3 p12 and D2 p9 both put a FIGURE and a GLOSS in there,
    at body size, and neither carries a headline at all. The panel is an aside, not a second
    page competing with the first.

    THE WHOLE PANEL IS SIZED AS ONE BLOCK, and it took three attempts to get there. Equal cells
    drew each item over the next. Measured cells stopped that and then ran the last item off
    the bottom of the slide, at a NEGATIVE height the geometry gate caught. The reason both
    failed is the same: an item cannot decide its own size, because whether it fits depends on
    what the other two took. So the sizes are chosen once, for the panel, from a ladder --
    measure the whole stack, step the pair down, measure again.

    White for the label, pale blue for the body beneath it. Both are legal on Cobalt; the body
    ink #00338D is not, at 2.35:1, which is why nothing here reaches for `ctx.ink`.
    """

    def build(s, ctx, box):
        gap = points(SPACE["md"])
        hair = points(SPACE["hair"])

        def measure(lead_role, item_role):
            """Total height of the stack at these two roles, and the per-block heights."""
            probe = Box(box.left, box.top, box.width, points(600))
            lh = points(
                T.fit(
                    lead,
                    probe,
                    ctx.brand.font_minor,
                    SCALE[lead_role],
                    line_spacing=1.22,
                ).height_pt
            )
            blocks = []
            for label, text in items:
                a = points(
                    T.fit(
                        label,
                        probe,
                        ctx.brand.font_minor,
                        SCALE[item_role],
                        line_spacing=1.22,
                    ).height_pt
                )
                b = points(
                    T.fit(
                        text,
                        probe,
                        ctx.brand.font_minor,
                        SCALE[item_role],
                        line_spacing=1.22,
                    ).height_pt
                )
                blocks.append((a, b))
            total = (
                lh + points(SPACE["lg"]) + sum(a + hair + b + gap for a, b in blocks)
            )
            return total, lh, blocks

        # The ladder. `lead` is always at least one step above the items, so the panel keeps a
        # hierarchy even at the bottom rung -- a panel whose lead is the same size as its items
        # has three equal voices and no opening.
        ladder = [
            ("lead", "small"),
            ("body", "small"),
            ("body", "caption"),
            ("small", "caption"),
            ("small", "footnote"),
        ]
        lead_role, item_role = ladder[-1]
        total, lead_h, blocks = measure(*ladder[-1])
        for cand in ladder:
            t, lh, bl = measure(*cand)
            if t <= box.height:
                lead_role, item_role, total, lead_h, blocks = (
                    cand[0],
                    cand[1],
                    t,
                    lh,
                    bl,
                )
                break

        y = box.top
        C.body(
            s,
            ctx,
            Box(box.left, y, box.width, lead_h),
            lead,
            role=lead_role,
            color=ctx.brand.color("on_dark"),
            strict=False,
        )
        y += lead_h + points(SPACE["lg"])

        for (label, text), (label_h, text_h) in zip(items, blocks):
            C.body(
                s,
                ctx,
                Box(box.left, y, box.width, label_h),
                label,
                role=item_role,
                color=ctx.brand.color("on_dark"),
                strict=False,
            )
            C.body(
                s,
                ctx,
                Box(box.left, y + label_h + hair, box.width, max(text_h, points(12))),
                text,
                role=item_role,
                color=ctx.brand.color("on_dark_accent"),
                strict=False,
            )
            y += label_h + hair + text_h + gap

    return build


def panel_figure(value, gloss, *, ring=False):
    """
    A panel carrying one large figure and a white gloss. The measured form -- D3 p12, D2 p9.

    `ring` draws it as a ring gauge rather than a numeral, which is what D3 p12 does. Either
    way the figure is the panel's whole content and the gloss explains it; there is no third
    thing, because at 215pt of measure there is no room for one and KPMG does not put one there.
    """

    def build(s, ctx, box):
        if ring:
            d = min(points(150), box.width)
            ring_gauge(
                s,
                ctx,
                Box(box.left, box.top + points(40), d, d),
                1.0,
                color=ctx.brand.color("accent_bright"),
                label=value,
                diameter_pt=d / 12700,
            )
            top = box.top + points(40) + d + points(SPACE["lg"])
        else:
            size = SCALE["hero"]
            T.add_textbox(
                s,
                Box(box.left, box.top + points(40), box.width, points(size * 1.3)),
                value,
                family=ctx.brand.font_major,
                size_pt=size,
                bold=True,
                color=ctx.brand.color("on_dark"),
                tracking_pt=tracking_pt("hero", size),
                line_spacing=1.0,
                anchor="top",
            )
            top = box.top + points(40) + points(size * 1.2) + points(SPACE["md"])

        C.body(
            s,
            ctx,
            Box(box.left, top, box.width, box.bottom - top),
            gloss,
            role="small",
            color=ctx.brand.color("on_dark"),
            strict=False,
        )

    return build


def interactive_panel(n):
    headline, gloss = INTERACTIVE[n]
    return panel_builder(
        headline,
        [
            ("Open it", f"build/section-{n}/interactive.html, in a browser."),
            ("Play it", gloss),
            ("Not optional", "A scheduled part of the hour. A screenshot is not it."),
        ],
    )


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

d = Deck(
    Brand.load("kpmg"),
    owner="Chris Ren",
    doc_title="How to become an AI engineer",
    sections=NAV,
    standing_line="KPMG Lakehouse, September 2026  ·  course material by Chris Ren",
)

# 1 -- the cover: a gradient ground carrying THE WINDOW, with the title set inside it.
# FY22 pp.46/72. This is window style 2 (window as type-holding shape), and it is the one
# composition on the brand book's own PowerPoint page (p.113) that carries display type.
#
# THE COMMENT THAT USED TO SIT HERE ARGUED FOR A SYSTEM THIS LINE DOES NOT USE, which is worth
# recording rather than quietly deleting. It chose "Group 3" -- the 2015 book's no-photograph
# layout family -- citing p.101's mechanical rule, "if you do not want to use a photo, use
# group 3." That reasoning was sound about the wrong book. FY22 (March 2022) has no layout
# groups at all; it replaces them with the window on one of two permitted gradients. The code
# was corrected when the FY22 book was obtained; the comment was not, so for one commit the
# file's own explanation pointed the next author back at the superseded system.
#
# d.cover() is still here and still correct for its own genre -- the measured report cover from
# the CEO-Outlook family, gradient field, hard-edged window at 1:sqrt2, staircase title. It is
# a faithful reproduction of a real KPMG cover, and it is also what the operator saw and called
# a generic blue theme, because that family is monochrome and a course deck is not a report.
d.window(
    "How to become an AI engineer",
    subhead="KPMG Lakehouse  ·  One day, six hours  ·  September 2026",
)
d.notes(
    d.prs.slides[0],
    "One day, six hours, split 3 / lunch / 3. 140 attendees, associate to partner, on their "
    "own laptops and their own real work.",
)

# 2 -- colour by page 2, and it is the deck's one real exhibit.
s = d.split(
    "Two sections overrun their block; section 2 has room to give",
    "302 content-minutes against six printed 50-minute blocks.",
    body_build=lambda sl, ctx, box: bar_chart(
        sl,
        ctx,
        box,
        [
            Datum(f"{n}. {SHORT[n]}", SECTIONS[n][1], emphasis=(SECTIONS[n][1] > 50))
            for n in sorted(SECTIONS)
        ],
        unit=" min",
        label_width_in=2.4,
        max_value=70,
        bar_height_pt=16,
    ),
    panel_build=panel_builder(
        "Whoever runs the room chooses",
        [
            ("Section 2 is genuinely short", "28 minutes against a printed 50."),
            ("Sections 4 and 5 genuinely overrun", "61 and 62 against the same 50."),
            ("Say it openly", "The course states this and offers three ways out."),
        ],
    ),
    side="right",
)
d.notes(
    s,
    "Sections, in order: "
    + "; ".join(f"{n}. {SECTIONS[n][0]}" for n in sorted(SECTIONS))
    + ". 302 content-minutes against six printed 50-minute blocks (300). Section 2 is "
    "genuinely short; 4 and 5 genuinely overrun. The course states this openly and offers "
    "three ways out. Do not silently fix it.",
)

# 3..36 -- six sections, each: white opener, its claims, then the visualization page.
for n in sorted(SECTIONS):
    title, minutes, statement, argument = SECTIONS[n]

    # The divider, before the opener. This is the book's own sequence, not an invention: p.100
    # is a Group 3 divider reading "Layout" and p.101 is the content page that follows it. All
    # eight of the book's dividers are 10/90, which is why none of them is a G3-B.
    #
    # No pair is named. `section_index` drives palette.rotate(), which walks every legal pair so
    # consecutive dividers share no colour -- bb p.112: "try to use as many combinations as you
    # can over a period of time." Naming pairs here would put the deck's colour decisions in the
    # content file, where the next author would copy the first one six times.
    d.notes(
        d.window(
            title, numeral=f"{n:02d}", support_ground=(n % 2 == 0), section_index=n - 1
        ),
        f"Section {n} divider. One statement, one colour pair, nothing else -- the argument is "
        f"on the page after this one.",
    )

    sl = d.section(
        n,
        title,
        statement,
        argument,
        aside=lambda s_, ctx, box, m=minutes: C.stat(
            s_,
            ctx,
            box,
            f"{m} min",
            "of content in this hour",
            caption="Against a printed 50-minute block.",
        ),
    )
    d.notes(
        sl,
        f"Section {n}. {minutes} content-minutes against a printed 50-minute block. "
        f"The section's own claim is the standfirst; the argument beside it is what the "
        f"companion opens with.",
    )

    for claim in [c for c in CLAIMS if c["section"] == n]:
        kind = claim["kind"]
        element = claim.get("element")

        # A CONTRAST ELEMENT IS ALREADY TWO BLOCKS, so it becomes two coloured ones. This is a
        # presentation change and nothing else -- the claim, the standfirst, the body and both
        # sides of the contrast are the delivered words, unaltered, and claims.json still
        # asserts them above. What changes is that the two halves now sit INSIDE colour instead
        # of beside each other on white, which is what KPMG's own deck does with the same shape
        # (sources/kpmg2026/in-ux-2023/p-07.png: three stacked colour blocks carrying the body).
        if kind == "white" and element and element[0] == "contrast":
            left_label, left_body, right_label, right_body, _emphasis = element[1]
            sl = d.blocks(
                claim["claim"],
                claim["stand"],
                [(left_label, left_body), (right_label, right_body)],
                eyebrow=claim["eyebrow"],
                section_index=n - 1,
            )
        elif kind == "white":
            sl = d.statement(
                claim["claim"],
                claim["stand"],
                claim["body"],
                eyebrow=claim["eyebrow"],
                support=element_builder(*element) if element else None,
                section_index=n - 1,
            )
        elif kind == "split":
            heading, items = element[1]
            sl = d.split(
                claim["claim"],
                claim["stand"],
                claim["body"],
                panel_build=panel_builder(heading, items),
                eyebrow=claim["eyebrow"],
                section_index=n - 1,
            )
        elif kind in ("field", "field-navy"):
            # 6 Cobalt : 4 KPMG Blue across the measured full-bleed pages, and the navy ones
            # are the formal pages -- "The journey ahead", "About the authors", a closing.
            sl = d.full_field(
                claim["claim"],
                standfirst=claim["stand"],
                body=claim["body"],
                color=d.brand.color("canvas_brand") if kind == "field-navy" else None,
                section_index=n - 1,
            )
        else:
            raise ValueError(f"unknown page kind {kind!r}")

        d.notes(
            sl,
            f"Section {n} -- delivered claim, verbatim from COURSE.md. The supporting "
            f"argument is in the section companion.",
        )

    # THE SIX HAND-OFF PAGES USED TO BE ONE PAGE PRINTED SIX TIMES. Same archetype, same
    # standfirst, same body, and a headline differing by a single digit -- "Open the section N
    # visualization and play it". Every gate passed it: the palette was right, nothing
    # overflowed, and `check_siblings` counts archetype NAMES, so six `split` pages inside a
    # deck that also used `split` legitimately never crossed its ceiling. `check_monotony`
    # reads the renders instead and named them immediately, at a grayscale RMS of 3.2 and 4.4
    # against 9.0 for the closest genuinely distinct pair in the same deck.
    #
    # The fix is not a reworded headline. Six pages that say the same thing in the same shape
    # are one page; what makes them six is that each visualization asks a DIFFERENT question,
    # so each page now states its own and takes the archetype that argues it. No figures are
    # invented here -- every number these produce is computed live in the browser, and a slide
    # that quoted one would be claiming what it cannot verify.
    headline, gloss = INTERACTIVE[n]
    if n == 1:
        sl = d.split(
            headline,
            gloss,
            "Weigh the folder yourself. The container is the cost, not the words in it.",
            panel_build=interactive_panel(n),
            section_index=n - 1,
        )
    elif n == 2:
        sl = d.versus(
            headline,
            "Any two of these",
            [
                "Private data and untrusted content",
                "Untrusted content and an outward channel",
                "Private data and an outward channel",
            ],
            "All three at once",
            [
                "The one combination to refuse",
                "Build it in the browser and watch it close",
            ],
        )
    elif n == 3:
        sl = d.blocks(
            headline,
            gloss,
            [
                (
                    "One run rides the window down",
                    "Same artifact, and it pays for it twice.",
                ),
                (
                    "The other checkpoints and clears",
                    "Same artifact, at a different cost.",
                ),
            ],
            section_index=n - 1,
        )
    elif n == 4:
        sl = d.points_slide(
            headline,
            [
                (
                    "Change one word",
                    "A single black-box word in the prompt, and nothing else on the page.",
                ),
                (
                    "Read both artifacts",
                    "Side by side, then say out loud which one you actually asked for.",
                ),
                (
                    "The word was doing work",
                    "It was carrying a decision you had not noticed you were delegating, and "
                    "a screenshot of the result cannot ask you to make it.",
                ),
            ],
        )
    elif n == 5:
        # `process` rather than `statement(support=interactive_panel(...))`: that panel builder
        # writes white type and is only legible inside the coloured panel `split` gives it, so
        # as a support element on a white working page it asserts white-on-white and refuses.
        # The refusal is right, and `process` is the better page anyway -- four runs of the
        # same job IS an ordered sequence, which is the one thing this archetype is for.
        sl = d.process(
            headline,
            [
                (
                    "Run 1",
                    "Every step reasoned from the top, because nothing has been written down "
                    "yet and the agent is deriving the whole shape of the job each time.",
                ),
                (
                    "Run 2",
                    "The file starts to carry some of it. The steps you had to correct last "
                    "time are the ones that stop needing correction.",
                ),
                (
                    "Run 3",
                    "Fewer questions, because fewer are left to ask. What remains is the part "
                    "that genuinely varies between runs.",
                ),
                (
                    "Run 4",
                    "What is left over is the skill. Nobody authored it -- it is the residue "
                    "of doing the same work four times and keeping what held.",
                ),
            ],
        )
    else:
        sl = d.full_field(
            headline,
            body="Collapse the chain one link at a time and meet the new ceiling on the "
            "other side. The loss between ten people is where the technical debt came from.",
            standfirst=gloss,
        )
    d.notes(
        sl,
        f"Open build/section-{n}/interactive.html in a browser. Scheduled part of the hour, "
        f"not optional. Do not substitute a screenshot.",
    )

# 37 -- the closing. Full field in KPMG Blue, which is the formal one of the two.
sl = d.closing(
    "The load-bearing skill is saying clearly what you want",
    [
        "Research, then plan, then implement — with the agent, in plain English.",
        "The software is what falls out of research and planning done well.",
    ],
)
d.notes(
    sl,
    "Close on the entry requirement, not on the tooling. Two jumps against one; the line "
    "between technical and non-technical stops existing.",
)

# Save beside this script rather than into the caller's cwd. Running it from the repo root
# used to drop an untracked course.pptx there, which is neither where `.gitignore` expects the
# build output nor where SKILL.md's render and verify commands look for it.
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "course.pptx")
d.save(OUT)
for line in d.build_log():
    print("  " + line)
print(f"saved {d.slide_count} slides -> {OUT}")
