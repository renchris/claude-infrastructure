"""
text.py -- typography, and real text measurement.

THE PROBLEM THIS SOLVES, because it is the single most common defect in generated decks:
nothing in python-pptx knows how wide a string is. You set a 44pt headline into a 5-inch box
and the library accepts it without complaint. Whether it fits, wraps to four lines, or spills
over the shape below is discovered when a human opens the file -- or, in the failure case this
package exists to prevent, when it is on a screen in front of a room.

PowerPoint's own answer is autofit: shrink the type until it fits. That is the wrong lever for
a designed deck and it is worth being precise about why. Hierarchy on a slide is encoded by
SIZE RATIO -- the headline is dominant because it is roughly twice the support. Autofit changes
one element's size to solve a local overflow, which silently breaks that ratio, and the slide
starts lying about which idea is subordinate to which. Worse, sibling slides shrink by
different amounts, so a deck that was designed with one grammar renders with several. And it
does not even work reliably here: PowerPoint computes the shrink factor at EDIT time inside the
application, so a generated file carries whatever was written into <a:normAutofit> and nothing
recomputes it until a human opens that box.

So the rule this module enforces:

    MEASURE FIRST. IF IT DOES NOT FIT, CUT WORDS -- DO NOT SHRINK TYPE.

Which is also the better editorial outcome. A headline that does not fit at its designated size
is usually a headline carrying two ideas, and the fix a designer would make is the fix the
writing needed anyway.

Measurement uses the real font file via PIL, so it accounts for actual glyph advances and
kerning rather than a characters-times-average-width estimate. The remaining error against
PowerPoint's own layout is small and always conservative in the direction that matters, because
`fits()` applies a safety factor.
"""

from __future__ import annotations

import functools
import os
from dataclasses import dataclass
from typing import Iterable, Sequence

from lxml import etree
from PIL import ImageFont
from pptx.dml.color import RGBColor
from pptx.oxml.ns import qn
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Pt

from . import oxml as X
from .canvas import Box, EMU_PER_POINT

# ---------------------------------------------------------------------------
# Font resolution
# ---------------------------------------------------------------------------

FONT_DIRS = (
    "/System/Library/Fonts/Supplemental",
    "/System/Library/Fonts",
    "/Library/Fonts",
    os.path.expanduser("~/Library/Fonts"),
    "/usr/share/fonts",
    "/usr/local/share/fonts",
)

# Explicit filenames for the faces we actually use. Guessing "Family Bold.ttf" works for the
# Office core fonts on macOS and fails for almost everything else, so anything that matters
# gets named here rather than inferred.
_FONT_FILES = {
    ("arial", False, False): "Arial.ttf",
    ("arial", True, False): "Arial Bold.ttf",
    ("arial", False, True): "Arial Italic.ttf",
    ("arial", True, True): "Arial Bold Italic.ttf",
    ("arial narrow", False, False): "Arial Narrow.ttf",
    ("arial narrow", True, False): "Arial Narrow Bold.ttf",
    ("arial black", False, False): "Arial Black.ttf",
    ("helvetica", False, False): "Helvetica.ttc",
    ("helvetica neue", False, False): "HelveticaNeue.ttc",
    ("verdana", False, False): "Verdana.ttf",
    ("verdana", True, False): "Verdana Bold.ttf",
    ("georgia", False, False): "Georgia.ttf",
    ("tahoma", False, False): "Tahoma.ttf",
    ("times new roman", False, False): "Times New Roman.ttf",
}


class FontNotFound(RuntimeError):
    """Raised rather than silently substituting. A substituted font measures differently."""


@functools.lru_cache(maxsize=256)
def font_path(family: str, bold: bool = False, italic: bool = False) -> str:
    """
    Locate the font file for a family/weight/style on this machine.

    Raises rather than falling back. A silent fallback to a different face would make every
    downstream measurement wrong in a way nothing detects -- the numbers would still look
    plausible, which is worse than an error.
    """
    key = (family.lower().strip(), bold, italic)
    candidates = []
    if key in _FONT_FILES:
        candidates.append(_FONT_FILES[key])
    # Generic guesses, tried after the explicit table.
    stem = family.strip()
    suffix = (
        " Bold Italic"
        if (bold and italic)
        else " Bold"
        if bold
        else " Italic"
        if italic
        else ""
    )
    candidates += [
        f"{stem}{suffix}.ttf",
        f"{stem}{suffix}.otf",
        f"{stem.replace(' ', '')}{suffix.replace(' ', '')}.ttf",
    ]

    for directory in FONT_DIRS:
        for name in candidates:
            candidate = os.path.join(directory, name)
            if os.path.isfile(candidate):
                return candidate

    raise FontNotFound(
        f"no font file for {family!r} (bold={bold}, italic={italic}). "
        f"Searched {list(FONT_DIRS)}. Measurement cannot proceed without the real face; "
        f"either install it or measure against the declared fallback instead."
    )


def font_available(family: str, bold: bool = False, italic: bool = False) -> bool:
    try:
        font_path(family, bold, italic)
        return True
    except FontNotFound:
        return False


@functools.lru_cache(maxsize=512)
def _loaded(family: str, size_pt: float, bold: bool, italic: bool):
    # PIL sizes in pixels; at 72dpi one pixel is one point, so loading at the point size makes
    # every returned advance a point measurement directly.
    return ImageFont.truetype(font_path(family, bold, italic), int(round(size_pt)))


# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------


def text_width_pt(
    text: str,
    family: str,
    size_pt: float,
    bold: bool = False,
    italic: bool = False,
    tracking_pt: float = 0.0,
) -> float:
    """Width of a single line, in points, including kerning and any letter-spacing."""
    if not text:
        return 0.0
    font = _loaded(family, size_pt, bold, italic)
    width = font.getlength(text)
    if tracking_pt:
        width += tracking_pt * len(text)
    return width


def text_width_emu(text: str, family: str, size_pt: float, **kw) -> int:
    return int(round(text_width_pt(text, family, size_pt, **kw) * EMU_PER_POINT))


def wrap(
    text: str,
    max_width_emu: int,
    family: str,
    size_pt: float,
    bold: bool = False,
    italic: bool = False,
    tracking_pt: float = 0.0,
) -> list[str]:
    """
    Greedy word wrap, matching how PowerPoint breaks lines.

    Greedy (fill each line until the next word does not fit) rather than the Knuth-Plass
    optimal algorithm, because greedy is what PowerPoint does -- being cleverer here would
    predict a layout the renderer will not produce.

    Honours explicit newlines, which are line breaks a writer asked for and must be kept.
    """
    max_width_pt = max_width_emu / EMU_PER_POINT
    lines: list[str] = []

    for paragraph in text.split("\n"):
        words = paragraph.split()
        if not words:
            lines.append("")
            continue
        current = words[0]
        for word in words[1:]:
            trial = f"{current} {word}"
            if (
                text_width_pt(trial, family, size_pt, bold, italic, tracking_pt)
                <= max_width_pt
            ):
                current = trial
            else:
                lines.append(current)
                current = word
        lines.append(current)
    return lines


def font_line_height_pt(
    family: str, size_pt: float, bold: bool = False, italic: bool = False
) -> float:
    """
    The natural line height of a face at a size: ascent + descent, in points.

    THIS IS THE CORRECTION THAT MAKES EVERY OTHER MEASUREMENT IN THIS PACKAGE TRUE.

    PowerPoint's proportional line spacing (`line_spacing = 1.08`) multiplies the FONT'S OWN
    line height, not the point size. Those are not the same number and the gap is large:
    Arial's ascent+descent is about 1.13em, so a 34pt line at 1.08 spacing occupies 41pt, not
    the 36.7pt that `size_pt * line_spacing` predicts.

    Under-measuring by 12% per line is invisible on one line and compounds: a two-line headline
    lands 13pt lower than predicted. In the first render of this package that put the accent
    rule -- positioned from the predicted bottom -- straight through the second line of the
    headline on five slides. The arithmetic looked right, the XML was valid, and the only thing
    that revealed it was rendering the deck and looking at it.

    It also means every `fits()` verdict computed the old way was OPTIMISTIC, which is the
    dangerous direction: text reported as fitting that actually overflows.
    """
    ascent, descent = _loaded(family, size_pt, bold, italic).getmetrics()
    natural = ascent + descent
    # PIL loads at an integer pixel size; rescale to the exact requested point size.
    return natural * (size_pt / max(1, int(round(size_pt))))


def line_height_pt(
    family: str,
    size_pt: float,
    line_spacing: float = 1.0,
    bold: bool = False,
    italic: bool = False,
) -> float:
    """One laid-out line, in points, at a given proportional line-spacing multiplier."""
    return font_line_height_pt(family, size_pt, bold, italic) * line_spacing


@dataclass(frozen=True)
class Fit:
    """The result of measuring a string against a region."""

    fits: bool
    lines: list[str]
    width_pt: float  # widest line
    height_pt: float  # total laid-out height
    box_width_pt: float
    box_height_pt: float

    @property
    def line_count(self) -> int:
        return len(self.lines)

    @property
    def overflow_pt(self) -> float:
        """How much taller than the box, in points. Zero or negative means it fits."""
        return self.height_pt - self.box_height_pt

    @property
    def widow(self) -> bool:
        """
        True when the last line is a single short word.

        A one-word last line ("...real
        systems") is a typographic defect that no automated check normally catches and that
        every designer fixes. Reported so a caller can rewrite or force an earlier break.
        """
        return (
            len(self.lines) > 1
            and len(self.lines[-1].split()) == 1
            and len(self.lines[-1]) <= 12
        )

    def describe(self) -> str:
        state = "fits" if self.fits else f"OVERFLOWS by {self.overflow_pt:.1f}pt"
        note = " (widow on last line)" if self.widow else ""
        return f"{state}: {self.line_count} line(s), {self.height_pt:.1f}pt of {self.box_height_pt:.1f}pt{note}"


def fit(
    text: str,
    box: Box,
    family: str,
    size_pt: float,
    *,
    bold: bool = False,
    italic: bool = False,
    tracking_pt: float = 0.0,
    line_spacing: float = 1.15,
    space_before_pt: float = 0.0,
    inset_pt: float = 0.0,
    safety: float = 1.02,
) -> Fit:
    """
    Measure a string against a region and report whether it fits.

    inset_pt  The text frame's own internal margin, subtracted from the usable width. PowerPoint
              DEFAULTS this to 0.1in left/right (7.2pt), and this package now writes 0 --
              see `write()` for why. It stays a parameter so a caller working with a frame it
              did not create can measure that frame honestly.
    safety    A small multiplier on the measured height. Absorbs the residual difference
              between PIL's advances and PowerPoint's own line layout. Always errs toward
              declaring an overflow, which is the safe direction: a false overflow costs an
              edit, a false fit costs a broken slide in front of a room.
    """
    usable_w = box.width - int(round(2 * inset_pt * EMU_PER_POINT))
    if usable_w <= 0:
        raise ValueError(f"box is narrower than its own text insets: {box}")

    lines = wrap(text, usable_w, family, size_pt, bold, italic, tracking_pt)
    widest = max(
        (text_width_pt(ln, family, size_pt, bold, italic, tracking_pt) for ln in lines),
        default=0.0,
    )

    line_h = line_height_pt(family, size_pt, line_spacing, bold, italic)
    height = (
        len(lines) * line_h + max(0, len(text.split("\n")) - 1) * space_before_pt
    ) * safety

    box_h_pt = box.height / EMU_PER_POINT
    box_w_pt = box.width / EMU_PER_POINT

    return Fit(
        fits=height <= box_h_pt and widest <= usable_w / EMU_PER_POINT,
        lines=lines,
        width_pt=widest,
        height_pt=height,
        box_width_pt=box_w_pt,
        box_height_pt=box_h_pt,
    )


def largest_size_that_fits(
    text: str, box: Box, family: str, sizes: Sequence[float], **kw
) -> float | None:
    """
    Pick the largest size from an ALLOWED SET that fits.

    Takes a discrete list rather than searching a continuous range on purpose. Free-floating
    sizes are how a deck ends up with a 37pt headline on one slide and a 39pt on the next --
    each locally optimal, collectively a mess. Constraining to the type scale means sibling
    slides stay siblings.

    Returns None when nothing in the scale fits, which is the signal to CUT WORDS.
    """
    for size in sorted(sizes, reverse=True):
        if fit(text, box, family, size, **kw).fits:
            return size
    return None


# ---------------------------------------------------------------------------
# Writing text
# ---------------------------------------------------------------------------

_ALIGN = {
    "left": PP_ALIGN.LEFT,
    "center": PP_ALIGN.CENTER,
    "right": PP_ALIGN.RIGHT,
    "justify": PP_ALIGN.JUSTIFY,
}
_ANCHOR = {
    "top": MSO_ANCHOR.TOP,
    "middle": MSO_ANCHOR.MIDDLE,
    "bottom": MSO_ANCHOR.BOTTOM,
}


def write(
    shape,
    text: str,
    *,
    family: str | None = None,
    size_pt: float = 18,
    bold: bool = False,
    italic: bool = False,
    color=None,
    alpha: float | None = None,
    align: str = "left",
    anchor: str = "top",
    line_spacing: float = 1.15,
    space_after_pt: float = 0.0,
    tracking_pt: float = 0.0,
    caps: bool = False,
    inset_pt: float | None = 0.0,
) -> None:
    """
    Set styled text into a shape's text frame, replacing anything already there.

    INSET DEFAULTS TO ZERO, and that is a deliberate reversal of PowerPoint's own default.

    PowerPoint gives every text frame a 0.1in (7.2pt) left and right margin, so a box placed at
    the grid's 56.693pt left edge draws its first glyph at 63.9. That is an invisible literal
    offsetting every element on the slide -- exactly the thing canvas.py's module docstring
    forbids ("NO COMPONENT MAY COMPUTE ITS OWN POSITION FROM A LITERAL"), except that nobody
    wrote it and nobody can grep for it. It also silently falsified every coordinate this
    package was built to reproduce: measured KPMG geometry is INK position, and 7.2pt is 0.75%
    of the page.

    With the inset at zero, a box's left edge IS its ink's left edge, all spacing comes from the
    grid, and a headline, its section number and its standfirst align because they were placed
    to align rather than because they happen to share a margin default.

    `color` may be a hex string or a colour ELEMENT from oxml.scheme()/oxml.srgb(). Passing a
    scheme element is strongly preferred -- it keeps the run on the theme, so a template swap
    re-colours it. A hex literal here is the typographic equivalent of hard-coding a colour.

    Multi-line strings split on "\\n" into real paragraphs so that line spacing and space-after
    apply per paragraph, rather than becoming one paragraph with soft breaks.
    """
    tf = shape.text_frame
    tf.word_wrap = True
    tf.clear()

    if inset_pt is not None:
        inset = Pt(inset_pt)
        tf.margin_left = tf.margin_right = inset
        tf.margin_top = tf.margin_bottom = Pt(inset_pt / 2)

    tf.vertical_anchor = _ANCHOR.get(anchor, MSO_ANCHOR.TOP)

    paragraphs = text.split("\n")
    for i, chunk in enumerate(paragraphs):
        para = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        para.alignment = _ALIGN.get(align, PP_ALIGN.LEFT)
        para.line_spacing = line_spacing
        if space_after_pt:
            para.space_after = Pt(space_after_pt)

        run = para.add_run()
        run.text = chunk.upper() if caps else chunk
        run.font.size = Pt(size_pt)
        run.font.bold = bold
        run.font.italic = italic
        if family:
            run.font.name = family

        if color is not None:
            _apply_color(run, color, alpha)
        elif alpha is not None:
            X.set_text_alpha(run, alpha)

        if tracking_pt:
            X.set_tracking(run, tracking_pt)

    # Pin the size. The text was measured; letting PowerPoint decide would undo that.
    X.set_no_autofit(tf)


# The a:rPr sequence, from the point a fill may appear onward. A run's fill must be inserted
# before any of these or the part is invalid.
_RPR_FILL_SUCCESSORS = (
    "a:effectLst",
    "a:effectDag",
    "a:highlight",
    "a:uLnTx",
    "a:uLn",
    "a:uFillTx",
    "a:uFill",
    "a:latin",
    "a:ea",
    "a:cs",
    "a:sym",
    "a:hlinkClick",
    "a:hlinkMouseOver",
    "a:rtl",
    "a:extLst",
)


def _apply_color(run, color, alpha: float | None) -> None:
    """
    Colour a run from either a hex string or a colour element, with optional alpha.

    The element branch exists so callers can pass oxml.scheme("accent1") and keep the run on
    the theme, which is what makes a template swap re-colour the deck. The hex branch goes
    through python-pptx's own API so the emitted XML stays canonical.
    """
    if isinstance(color, etree._Element):
        rPr = run.font._rPr
        for tag in ("a:noFill", "a:solidFill", "a:gradFill", "a:pattFill", "a:grpFill"):
            for found in rPr.findall(qn(tag)):
                rPr.remove(found)
        if alpha is not None:
            etree.SubElement(color, qn("a:alpha")).set(
                "val", str(int(round(alpha * 100000)))
            )
        solid = etree.Element(qn("a:solidFill"))
        solid.append(color)
        X._insert_ordered(rPr, solid, _RPR_FILL_SUCCESSORS)
    else:
        run.font.color.rgb = RGBColor.from_string(str(color).lstrip("#").upper())
        if alpha is not None:
            X.set_text_alpha(run, alpha)


def add_textbox(slide, box: Box, text: str, **kw):
    """Create a textbox at a Box and write into it. The common case, in one call."""
    shape = slide.shapes.add_textbox(*box.as_tuple())
    write(shape, text, **kw)
    return shape
