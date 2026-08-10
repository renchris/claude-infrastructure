"""
canvas.py -- the grid. Every position on every slide resolves through this module.

The reason a grid is the first thing built, ahead of any component, is that consistency of
alignment is most of what a viewer reads as "designed". Not colour, not typeface, not the
cleverness of any single slide: the fact that the left edge of the headline is in the SAME
PLACE on slide 4 and slide 31, and that every element on a slide lands on a shared set of
lines. A deck of individually pretty slides with drifting margins reads as amateur, and a
deck of plain slides on a rigid grid reads as professional. That asymmetry is the whole
argument for putting geometry in code rather than in each caller's arithmetic.

The practical rule this enforces: NO COMPONENT MAY COMPUTE ITS OWN POSITION FROM A LITERAL.
Callers ask the grid for a region and place things in it. A literal Inches(2.37) somewhere in
a slide builder is how the drift starts, and it is invisible in code review because 2.37 looks
as reasonable as 2.40.

Units: OOXML measures in EMU (English Metric Units), 914400 per inch, 12700 per point. Integer
throughout -- EMU is deliberately an integer unit chosen to divide evenly by both inches and
centimetres, and rounding at every call site is how off-by-one alignment creeps in.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

EMU_PER_INCH = 914400
EMU_PER_POINT = 12700


def inches(value: float) -> int:
    return int(round(value * EMU_PER_INCH))


def points(value: float) -> int:
    return int(round(value * EMU_PER_POINT))


def emu_to_inches(value: int) -> float:
    return value / EMU_PER_INCH


@dataclass(frozen=True)
class Box:
    """
    A rectangle in EMU. Immutable, because a component that mutates the region it was handed
    is how two components end up silently overlapping.

    Every derived method returns a NEW Box, so regions compose without aliasing.
    """

    left: int
    top: int
    width: int
    height: int

    @property
    def right(self) -> int:
        return self.left + self.width

    @property
    def bottom(self) -> int:
        return self.top + self.height

    @property
    def center_x(self) -> int:
        return self.left + self.width // 2

    @property
    def center_y(self) -> int:
        return self.top + self.height // 2

    def inset(self, dx: int = 0, dy: int | None = None) -> "Box":
        dy = dx if dy is None else dy
        return Box(
            self.left + dx, self.top + dy, self.width - 2 * dx, self.height - 2 * dy
        )

    def offset(self, dx: int = 0, dy: int = 0) -> "Box":
        return Box(self.left + dx, self.top + dy, self.width, self.height)

    def resize(self, width: int | None = None, height: int | None = None) -> "Box":
        return Box(
            self.left,
            self.top,
            self.width if width is None else width,
            self.height if height is None else height,
        )

    def top_slice(self, height: int) -> "Box":
        return Box(self.left, self.top, self.width, height)

    def bottom_slice(self, height: int) -> "Box":
        return Box(self.left, self.bottom - height, self.width, height)

    def split_h(self, at: float, gap: int = 0) -> tuple["Box", "Box"]:
        """Split into left/right at a fraction of the width, with an optional gutter."""
        lw = int(self.width * at) - gap // 2
        rl = self.left + int(self.width * at) + gap // 2
        return (
            Box(self.left, self.top, lw, self.height),
            Box(rl, self.top, self.right - rl, self.height),
        )

    def split_v(self, at: float, gap: int = 0) -> tuple["Box", "Box"]:
        """Split into top/bottom at a fraction of the height, with an optional gutter."""
        th = int(self.height * at) - gap // 2
        bt = self.top + int(self.height * at) + gap // 2
        return (
            Box(self.left, self.top, self.width, th),
            Box(self.left, bt, self.width, self.bottom - bt),
        )

    def row(self, count: int, index: int, gap: int = 0) -> "Box":
        """One cell of an even horizontal division. Used for metric rows and card strips."""
        if not 0 <= index < count:
            raise IndexError(f"index {index} out of range for {count} cells")
        cell_w = (self.width - gap * (count - 1)) // count
        return Box(self.left + index * (cell_w + gap), self.top, cell_w, self.height)

    def column(self, count: int, index: int, gap: int = 0) -> "Box":
        """One cell of an even vertical division."""
        if not 0 <= index < count:
            raise IndexError(f"index {index} out of range for {count} cells")
        cell_h = (self.height - gap * (count - 1)) // count
        return Box(self.left, self.top + index * (cell_h + gap), self.width, cell_h)

    def as_tuple(self) -> tuple[int, int, int, int]:
        """(left, top, width, height) -- the argument order every python-pptx add_* takes."""
        return (self.left, self.top, self.width, self.height)


# ---------------------------------------------------------------------------
# The body measure limit -- brand book p.99, adopted outright
# ---------------------------------------------------------------------------
#
# p.99, verbatim, printed as one of four what-not-to-dos: "Do not set body copy over more than
# four columns of the six-column grid, as this will affect legibility."
#
# EXPRESSED AS A FRACTION OF CONTENT WIDTH, NEVER AS A COLUMN COUNT, and that is the whole
# point of these two names. "Four columns" is only meaningful once you have said which grid,
# and this package has two of them (see Grid's docstring). A fraction holds on both, survives
# a change of column count, and applies just as well inside a panel or a Group 3 field -- none
# of which have columns at all.
#
# The nominal reading is 4/6 = 0.6667. The number the geometry actually produces is smaller,
# because the four columns absorb THREE gutters while the six absorb five: on the default grid
# col6(0,4) is 557.79pt of an 846.61pt content width = 0.6589. The exact value is what
# `Grid.body_measure_fraction` returns and what the archetypes clamp to; 4/6 below is kept as
# the stated rule so the arithmetic can be checked against the book rather than against us.
#
# WHY IT IS ADOPTED WITHOUT THE HESITATION THE SIX-COLUMN GRID GETS: this one does not depend
# on the grid being real. At 140-person room distance a full-bleed measure is unreadable
# whoever's page it is on -- KPMG's 10.5pt body over 846pt would run ~160 characters a line,
# and ours at 20pt still runs ~80, which is past where the eye reliably finds the next line.
BOOK_COLUMNS = 6
BODY_MEASURE_COLUMNS = 4
BODY_MEASURE_FRACTION = BODY_MEASURE_COLUMNS / BOOK_COLUMNS  # 0.6667, nominal


@dataclass(frozen=True)
class Grid:
    """
    The slide's coordinate system.

    Defaults are for 16:9 at 13.333 x 7.5in (12192000 x 6858000 EMU), which is the modern
    PowerPoint widescreen default and what any deck built after roughly 2013 uses. The older
    16:9 was 10 x 5.63in; a deck built at one size and opened in a template of the other gets
    every element rescaled, so this is worth asserting rather than assuming.

    Layout constants. EVERY ONE IS A MEASUREMENT off 95 rendered pages of five current KPMG
    reports authored at 960.094 x 540pt -- which is PowerPoint's 16:9 slide to within 0.0098%,
    smaller than a rendered pixel at 150dpi, so every measured x-value is used unscaled.

      margin_x 56.693pt  20mm EXACTLY, and 884 text spans sit on it. This REPLACED an earlier
                        "78.5pt, measured" figure that appears as a text edge nowhere in 95
                        pages -- the number near it is the COVER margin, 72.0, which is a
                        different measurement doing a different job (see cover_margin).
      margin_top 85.04  30mm. The measured cap-top of the page headline, sigma 0.7pt over
                        eight headlines in three decks. Not an optical guess.
      margin_bottom     48.19pt, putting the content bottom line at 491.81 -- where panel
                        bottoms land to the hundredth of a point -- and leaving the 513.7-529.1
                        footer band clear beneath it.
      columns 12        KEPT at 12, and this is the reconciliation that makes the geometry
                        cheap rather than a rewrite. With margin_x 56.693 and gutter 19.843 a
                        12-column grid has a 52.36pt column, so a span of FOUR reproduces
                        KPMG's measured 3-column module to a worst residual of 0.20pt:
                        col(0,4) = 56.69/268.98 against a measured 56.69/269.01. Six- and
                        twelve-column models were tested against the corpus and refuted --
                        doubling the candidate origins buys 23 more lines out of 3,653.
      book_columns 6    THE OTHER GRID, AND IT IS A SEPARATE ACCESSOR RATHER THAN A REPLACEMENT.
                        See the note below; `col6()` reads it, `col()` never does.

    TWO GRIDS LIVE HERE, AND THE CONFLICT IS REAL. IT IS RECORDED RATHER THAN RESOLVED.

    KPMG's brand book states one grid and one only, p.96 in its own words: "We use a simple
    six-column grid system for all our marketing communications... These six columns are
    separated by five gutters on each page." p.99 prints "do not use grids that are not based
    over six columns" as an explicit what-not-to-do. That is the only column count KPMG ever
    wrote down, and twelve appears in no KPMG document we hold -- it is a web convention.

    Against that, `columns = 12` above is not a preference either. It is what 95 rendered pages
    of five current KPMG reports measure to: a 4-span lands on the corpus's own three-column
    module to 0.20pt, and six- and twelve-column ORIGIN models were both tested against those
    3,653 measured text edges and refuted as explanations of where the edges are. So one number
    is authored and the other is observed, and they disagree.

    HOW THAT SPLITS, AND IT SPLITS BY GENRE, NOT BY SENIORITY OF SOURCE:

      col()   -- 12 columns -- governs REPORT-STYLE INTERIOR PAGES: the dense white content
                 page, the exhibit, the section opener with two columns of argument beside the
                 headline. It is measured from exactly that genre and it reproduces it.
      col6()  -- 6 columns -- governs BRAND-BOOK LAYOUTS: the Group 3 two-colour pages (G3-A
                 10/90 and G3-B 40/60, bb pp.112-114), covers, dividers. Those pages are
                 specified in the book and appear nowhere in the measured report corpus, so
                 there is no measurement that could contradict the book about them.

    The six-column rule is the WEAKEST of the six brand-book rules this package adopts, and
    saying so is part of adopting it: `S1-brandbook.md` could not resolve any current KPMG page
    onto a six-column module, so six is authored-but-unconfirmed in 2026 practice. It is
    adopted because it is the only count KPMG ever published, not because current practice
    confirms it -- and it is adopted as a SECOND accessor precisely so that adopting it cannot
    silently re-cut the pages the 12-column measurement earned.

    The four-of-six body limit (p.99) is adopted OUTRIGHT and independently of all of that --
    see BODY_MEASURE_FRACTION below. It needs no grid to be true.
      gutter 19.843pt   7mm exactly. The system's invariant: 184.24 x 2 + 19.84 = 388.32,
                        exactly, on D1 p5.
      baseline 0.10in   Retained as a convenience ONLY. KPMG runs no baseline grid -- the
                        residue test is flat at pitch 13.0 / 14.4 / 15.6 -- so nothing should
                        be forced onto it.
    """

    slide_w: int = 12192000
    slide_h: int = 6858000
    margin_x: int = points(56.693)
    margin_top: int = points(85.04)
    margin_bottom: int = points(48.19)
    columns: int = 12
    book_columns: int = BOOK_COLUMNS
    gutter: int = points(19.843)
    baseline: int = inches(0.10)

    # The cover is the one page that does NOT use the body margin. Logo, staircase and tagline
    # all sit on 72.0pt (1 inch) across four measured covers.
    cover_margin: int = points(72.0)

    # Derived, computed once in __post_init__ since the dataclass is frozen.
    _col_w: int = field(init=False, default=0, repr=False)
    _book_col_w: int = field(init=False, default=0, repr=False)

    def __post_init__(self) -> None:
        for count, attr in (
            (self.columns, "_col_w"),
            (self.book_columns, "_book_col_w"),
        ):
            total_gutter = self.gutter * (count - 1)
            usable = self.slide_w - 2 * self.margin_x - total_gutter
            if usable <= 0:
                raise ValueError("margins and gutters exceed the slide width")
            object.__setattr__(self, attr, usable // count)

    # -- regions ------------------------------------------------------------

    @property
    def full(self) -> Box:
        """The whole slide, edge to edge. For full-bleed colour blocks and imagery only."""
        return Box(0, 0, self.slide_w, self.slide_h)

    @property
    def content(self) -> Box:
        """The safe area. Everything that is read lives inside this."""
        return Box(
            self.margin_x,
            self.margin_top,
            self.slide_w - 2 * self.margin_x,
            self.slide_h - self.margin_top - self.margin_bottom,
        )

    @property
    def footer(self) -> Box:
        """The band below the content area, holding page number and any mandated furniture."""
        return Box(
            self.margin_x,
            self.slide_h - self.margin_bottom,
            self.slide_w - 2 * self.margin_x,
            self.margin_bottom,
        )

    # The two running-chrome bands. Properties rather than fields because a Box default cannot
    # reference slide_w, which is itself a field. Measured y-extents, edge to edge horizontally
    # because the nav strip runs the full width and the footer ranges right to x=903.40.
    @property
    def nav_band(self) -> Box:
        """The top section-navigation band: y 12.4 -> 36.0pt. On 100% of non-cover pages."""
        return Box(0, points(12.4), self.slide_w, points(23.6))

    @property
    def footer_band(self) -> Box:
        """The document footer band: y 513.7 -> 529.1pt. On 100% of non-cover pages."""
        return Box(0, points(513.7), self.slide_w, points(15.4))

    def col(
        self,
        start: int,
        span: int = 1,
        *,
        top: int | None = None,
        height: int | None = None,
    ) -> Box:
        """
        A column-aligned region.

        `start` is zero-based. `span` counts columns, and the gutters BETWEEN spanned columns
        are absorbed into the region -- which is the behaviour you want, and the thing that is
        easy to get wrong by hand: a 6-column span is six column widths plus five gutters, not
        six of each.
        """
        if start < 0 or span < 1 or start + span > self.columns:
            raise ValueError(
                f"columns {start}..{start + span - 1} fall outside a {self.columns}-column grid"
            )
        left = self.margin_x + start * (self._col_w + self.gutter)
        width = span * self._col_w + (span - 1) * self.gutter
        c = self.content
        return Box(
            left,
            c.top if top is None else top,
            width,
            c.height if height is None else height,
        )

    def col6(
        self,
        start: int,
        span: int = 1,
        *,
        top: int | None = None,
        height: int | None = None,
    ) -> Box:
        """
        A column-aligned region on THE BRAND BOOK'S SIX-COLUMN GRID (bb p.96).

        Identical arithmetic to `col()`, over six columns and five gutters instead of twelve
        and eleven, on the same margins. Same zero-based `start`, same gutter-absorbing `span`.

        USE THIS FOR PAGES THE BOOK SPECIFIES AND THE REPORT CORPUS DOES NOT CONTAIN: the
        Group 3 two-colour layouts, covers, dividers. Use `col()` for report-style interior
        pages, which is where the 12-column measurement came from and what it reproduces.
        Grid's docstring carries the full argument for why both exist; the short version is
        that one grid is authored by KPMG and the other is measured off KPMG, they disagree,
        and neither is entitled to overwrite the other's genre.

        On the default grid the six columns are 124.57pt with 19.843pt gutters, so col6(0,4)
        is 557.79pt -- which is the body measure limit p.99 states, and `max_body_width()`
        returns the same number without needing this method at all.
        """
        if start < 0 or span < 1 or start + span > self.book_columns:
            raise ValueError(
                f"columns {start}..{start + span - 1} fall outside a "
                f"{self.book_columns}-column grid. This is the BOOK grid; for the measured "
                f"{self.columns}-column report grid use col()."
            )
        left = self.margin_x + start * (self._book_col_w + self.gutter)
        width = span * self._book_col_w + (span - 1) * self.gutter
        c = self.content
        return Box(
            left,
            c.top if top is None else top,
            width,
            c.height if height is None else height,
        )

    @property
    def body_measure_fraction(self) -> float:
        """
        The widest a run of body copy may be, as a fraction of the region it sits in.

        Four of six columns, gutters counted honestly: 3 gutters inside the four against 5
        inside the six, which is 0.6589 on the default grid rather than the nominal 0.6667.
        See BODY_MEASURE_FRACTION at the top of this module for the rule and the reasoning.
        """
        four = (
            BODY_MEASURE_COLUMNS * self._book_col_w
            + (BODY_MEASURE_COLUMNS - 1) * self.gutter
        )
        six = (
            self.book_columns * self._book_col_w + (self.book_columns - 1) * self.gutter
        )
        return four / six

    def max_body_width(self, width: int | None = None) -> int:
        """
        Clamp a width to the body measure limit. Pass the region you were about to set prose in.

        `width=None` means the full content width, so `max_body_width()` is the page-level cap:
        557.79pt on the default grid, which is col6(0,4) exactly.

        Called with an argument this is a min(), not a scale -- a 200pt panel column stays
        200pt. The limit only ever bites where a caller was about to set prose across most of
        a page, which is precisely the case p.99 draws a red line through.
        """
        base = self.content.width if width is None else width
        cap = int(self.content.width * self.body_measure_fraction)
        return min(base, cap)

    def lines(self, count: float, *, from_top: bool = True) -> int:
        """A vertical distance in baseline units, for snapping stacked blocks."""
        return int(round(count * self.baseline))

    def snap(self, value: int) -> int:
        """Round an EMU value to the nearest baseline multiple."""
        return int(round(value / self.baseline)) * self.baseline

    # -- checks -------------------------------------------------------------

    def contains(self, box: Box, *, safe: bool = True) -> bool:
        """
        Is this region inside the slide (safe=False) or inside the safe content area
        (safe=True)? verify.py uses this to catch content that has drifted off-slide, which
        is invisible in code and obvious in a render.
        """
        bounds = self.content if safe else self.full
        return (
            box.left >= bounds.left
            and box.top >= bounds.top
            and box.right <= bounds.right
            and box.bottom <= bounds.bottom
        )


# The default grid. Import this rather than constructing one, so every module shares a
# coordinate system by default; construct a custom Grid only for a genuinely different
# slide size.
GRID = Grid()


def rule_of_thirds(grid: Grid = GRID) -> tuple[int, int]:
    """
    The two horizontal lines at 1/3 and 2/3 of slide height.

    Useful for a specific decision the archetypes make repeatedly: where a single dominant
    statement sits vertically. Optical centre -- slightly ABOVE true centre -- is where the eye
    expects a headline to be, and true vertical centring on a 16:9 slide reads as fractionally
    low. The upper third line is the reliable anchor.
    """
    return (grid.slide_h // 3, 2 * grid.slide_h // 3)


Align = Literal["left", "center", "right"]


def place(
    box: Box,
    width: int,
    height: int,
    *,
    h: Align = "left",
    v: Literal["top", "middle", "bottom"] = "top",
) -> Box:
    """Position a fixed-size element within a region. Returns the placed Box."""
    if h == "left":
        left = box.left
    elif h == "center":
        left = box.left + (box.width - width) // 2
    else:
        left = box.right - width

    if v == "top":
        top = box.top
    elif v == "middle":
        top = box.top + (box.height - height) // 2
    else:
        top = box.bottom - height

    return Box(left, top, width, height)
