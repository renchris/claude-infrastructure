"""
theme.py -- rewrite the deck's OOXML theme part so theme colour references resolve to brand.

WHY THIS MODULE EXISTS, stated plainly, because it is the single most important architectural
decision in this package.

You can build a whole deck out of literal hex values. It will look right. It will also be
permanently detached from the firm's template: the next time the brand palette moves, every
literal stays where it was, and the deck silently stops matching the material around it. A
literal is a fact frozen at build time.

The alternative is to reference the THEME -- `<a:schemeClr val="accent1"/>` rather than
`<a:srgbClr val="00338D"/>`. Then the deck says "the first accent colour", the template says
what that is, and a template swap re-skins the whole deck for free.

The catch, and this is measurable rather than theoretical: a deck built from python-pptx's
default template inherits the STOCK OFFICE theme. `scheme("accent1")` resolves to Office's
blue-grey #4472C4 and `accent2` to its orange-red #ED7D31. Rendering a deck that referenced
theme slots showed exactly that -- a blue-grey box with an orange outline sitting on a navy
slide. The references were correct; the theme behind them was somebody else's.

So both halves are required, and neither works alone:
    1. Reference theme slots everywhere (oxml.scheme).
    2. Rewrite the theme part so those slots hold brand values. <- this module

Rewriting theme1.xml wholesale is safe in a way that hand-editing slide XML is not. The theme
is a single self-contained part with a stable schema, no relationships to other parts, and no
ids to keep consistent. It is the one part of a .pptx that can be replaced outright without
risking the repair dialog.
"""

from __future__ import annotations

from typing import Mapping

from lxml import etree
from pptx.opc.constants import RELATIONSHIP_TYPE as RT
from pptx.oxml.ns import qn

# The enforced child order of <a:clrScheme>. Writing these out of sequence is invalid.
CLR_SLOTS = (
    "dk1",
    "lt1",
    "dk2",
    "lt2",
    "accent1",
    "accent2",
    "accent3",
    "accent4",
    "accent5",
    "accent6",
    "hlink",
    "folHlink",
)


def _hex(color: str) -> str:
    h = color.lstrip("#").upper()
    if len(h) != 6 or any(c not in "0123456789ABCDEF" for c in h):
        raise ValueError(f"expected a 6-digit hex colour, got {color!r}")
    return h


def theme_parts(prs):
    """
    Yield every theme part in the package.

    A presentation normally has one theme per slide master. Rewriting only the first one is a
    quiet way to leave half a deck on the stock palette if a template ever ships two masters,
    so callers should apply to all of them.
    """
    seen = set()
    for master in prs.slide_masters:
        try:
            part = master.part.part_related_by(RT.THEME)
        except KeyError:
            continue
        if id(part) not in seen:
            seen.add(id(part))
            yield part


class ThemeDoc:
    """
    Read/modify/write a theme part, parsing once.

    python-pptx does not model the theme part. It has no registered part class, so it loads as
    a generic `Part` carrying raw bytes in `.blob` rather than an lxml tree in `._element`.

    That has a consequence worth stating, because it is a real bug and not a detail: any
    helper that parses `part.blob` on entry and serialises on exit CANNOT be composed. Two
    such helpers run in sequence each parse the ORIGINAL bytes, so the second silently
    discards the first one's edits and the deck ships with, say, brand colours and stock
    fonts. Parse once, mutate the one tree, write once.

    Used as a context manager:

        with ThemeDoc(part) as doc:
            ...mutate doc.root...
        # bytes written back here, exactly once
    """

    def __init__(self, part):
        self._part = part
        self._is_xml_part = hasattr(part, "_element")
        self.root = part._element if self._is_xml_part else etree.fromstring(part.blob)

    def __enter__(self) -> "ThemeDoc":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        if exc_type is None:
            self.flush()
        return False

    def flush(self) -> None:
        if self._is_xml_part:
            return  # mutations already live on the part's own tree
        self._part._blob = etree.tostring(
            self.root, xml_declaration=True, encoding="UTF-8", standalone=True
        )

    @property
    def theme_elements(self):
        el = self.root.find(qn("a:themeElements"))
        if el is None:
            raise ValueError("theme part has no <a:themeElements>")
        return el


def set_color_scheme(prs, colors: Mapping[str, str], scheme_name: str = "Brand") -> int:
    """
    Replace the theme colour scheme.

    colors: a mapping over CLR_SLOTS -> '#RRGGBB'. Every slot must be supplied; a partial
            scheme is invalid and there is no sensible default for a missing accent.

    Slot semantics, which are not obvious from the names and are routinely got wrong:
        dk1 / lt1   the primary TEXT and BACKGROUND pair. In the stock theme these are
                    sysClr window/windowText, which follow the OS. Setting them to explicit
                    srgbClr values is what stops a deck from changing appearance under a
                    high-contrast or dark system theme.
        dk2 / lt2   the secondary text/background pair.
        accent1-6   the six accents, in the order charts consume them. Slot order is
                    therefore also the default categorical data-viz sequence -- put the
                    colours in the order you want a six-series chart to use them.
        hlink       hyperlink; folHlink followed hyperlink.

    Note the bg1/tx1 aliasing: `<a:schemeClr val="bg1"/>` resolves to lt1 and `tx1` to dk1
    via the slide master's <p:clrMap>. That indirection is why a slide can be inverted by
    swapping the colour map rather than by restating every colour.

    Returns the number of theme parts rewritten.
    """
    missing = [s for s in CLR_SLOTS if s not in colors]
    if missing:
        raise ValueError(f"colour scheme is missing required slots: {missing}")

    count = 0
    for part in theme_parts(prs):
        with ThemeDoc(part) as doc:
            _write_color_scheme(doc.theme_elements, colors, scheme_name)
        count += 1

    if count == 0:
        raise RuntimeError("no theme part found; cannot set colour scheme")
    return count


def _write_color_scheme(
    theme_elements, colors: Mapping[str, str], scheme_name: str
) -> None:
    """Mutate one parsed <a:themeElements> in place. Order of CLR_SLOTS is the schema order."""
    clr_scheme = etree.Element(qn("a:clrScheme"))
    clr_scheme.set("name", scheme_name)
    for slot in CLR_SLOTS:
        node = etree.SubElement(clr_scheme, qn(f"a:{slot}"))
        srgb = etree.SubElement(node, qn("a:srgbClr"))
        srgb.set("val", _hex(colors[slot]))

    old = theme_elements.find(qn("a:clrScheme"))
    if old is not None:
        old.addprevious(clr_scheme)
        theme_elements.remove(old)
    else:
        # <a:clrScheme> is the first child of <a:themeElements> in the schema sequence.
        theme_elements.insert(0, clr_scheme)


def set_font_scheme(prs, major: str, minor: str, scheme_name: str = "Brand") -> int:
    """
    Replace the theme font scheme.

    major = headings, minor = body. A run that specifies no typeface inherits minor, which is
    how a deck stays on-brand without every run naming a font. Setting a literal typeface on
    every run is the typographic equivalent of a hard-coded hex.

    The `+mj-lt` / `+mn-lt` indirection is what makes this work: a run whose latin typeface is
    "+mn-lt" means "whatever the theme says body is".
    """
    count = 0
    for part in theme_parts(prs):
        with ThemeDoc(part) as doc:
            _write_font_scheme(doc.theme_elements, major, minor, scheme_name)
        count += 1
    return count


def _write_font_scheme(
    theme_elements, major: str, minor: str, scheme_name: str
) -> None:
    """Mutate one parsed <a:themeElements> in place."""
    font_scheme = etree.Element(qn("a:fontScheme"))
    font_scheme.set("name", scheme_name)
    for tag, typeface in (("a:majorFont", major), ("a:minorFont", minor)):
        fonts = etree.SubElement(font_scheme, qn(tag))
        latin = etree.SubElement(fonts, qn("a:latin"))
        latin.set("typeface", typeface)
        # East-Asian and complex-script slots must be PRESENT (the schema requires all
        # three) but may be empty, which means "fall back to the system default".
        etree.SubElement(fonts, qn("a:ea")).set("typeface", "")
        etree.SubElement(fonts, qn("a:cs")).set("typeface", "")

    old = theme_elements.find(qn("a:fontScheme"))
    if old is not None:
        old.addprevious(font_scheme)
        theme_elements.remove(old)
    else:
        # Sequence is clrScheme, fontScheme, fmtScheme.
        clr = theme_elements.find(qn("a:clrScheme"))
        if clr is not None:
            clr.addnext(font_scheme)
        else:
            theme_elements.insert(0, font_scheme)


def flatten_effect_styles(prs) -> int:
    """
    Empty the theme's effect styles so autoshapes stop inheriting a drop shadow.

    This fixes a defect most generated decks ship with and nobody can locate. Every autoshape
    added by python-pptx carries a <p:style> that points at effectStyleLst entry 3 of the
    theme's format scheme. In the stock Office theme that entry contains an outer shadow. The
    result is a soft grey shadow under every single box on the deck, which nobody wrote, which
    appears in no code, and which is the most reliable visual tell of a generated deck.

    You can clear it per-shape with oxml.clear_effects, and the components in this package do.
    Clearing it at the theme level is the belt-and-braces version: anything added by other
    code, or by a human editing the deck afterwards, also arrives flat.

    The three <a:effectStyle> entries must remain -- the schema requires exactly three and
    <p:style> references them by index -- so they are emptied rather than removed.
    """
    count = 0
    for part in theme_parts(prs):
        with ThemeDoc(part) as doc:
            if _write_flat_effects(doc.theme_elements):
                count += 1
    return count


def _write_flat_effects(theme_elements) -> bool:
    fmt = theme_elements.find(qn("a:fmtScheme"))
    if fmt is None:
        return False
    effect_lst = fmt.find(qn("a:effectStyleLst"))
    if effect_lst is None:
        return False
    for style in effect_lst.findall(qn("a:effectStyle")):
        for child in list(style):
            style.remove(child)
        etree.SubElement(style, qn("a:effectLst"))
    return True


def apply(
    prs,
    colors: Mapping[str, str],
    major: str,
    minor: str,
    scheme_name: str = "Brand",
    flatten_effects: bool = True,
) -> dict:
    """
    Apply a full brand theme in one call. This is what deck.py uses.

    All three mutations happen inside ONE ThemeDoc per part, which is the whole reason this
    function exists rather than callers chaining the three public helpers. Chaining them would
    parse the original bytes three times and keep only the last write -- a deck with correct
    fonts and stock colours, valid XML throughout, and no error anywhere.

    Returns a report so a caller can assert the rewrite happened rather than trust that it did.
    """
    missing = [s for s in CLR_SLOTS if s not in colors]
    if missing:
        raise ValueError(f"colour scheme is missing required slots: {missing}")

    report = {"color_schemes": 0, "font_schemes": 0, "effect_styles_flattened": 0}

    for part in theme_parts(prs):
        with ThemeDoc(part) as doc:
            te = doc.theme_elements
            _write_color_scheme(te, colors, scheme_name)
            report["color_schemes"] += 1
            _write_font_scheme(te, major, minor, scheme_name)
            report["font_schemes"] += 1
            if flatten_effects and _write_flat_effects(te):
                report["effect_styles_flattened"] += 1

    if report["color_schemes"] == 0:
        raise RuntimeError(
            "no theme part found; the deck would ship on the stock Office palette"
        )
    return report


def read_scheme(prs) -> dict:
    """
    Read back the theme colour scheme actually present in the file.

    Used by verify.py. The point of reading rather than remembering is that it catches the
    case where the rewrite silently did not apply -- for instance because a template shipped
    a second master whose theme was never touched.
    """
    out = {}
    for part in theme_parts(prs):
        doc = ThemeDoc(part)  # read-only: no flush
        clr_scheme = doc.theme_elements.find(qn("a:clrScheme"))
        if clr_scheme is None:
            continue
        for slot in CLR_SLOTS:
            node = clr_scheme.find(qn(f"a:{slot}"))
            if node is None:
                continue
            srgb = node.find(qn("a:srgbClr"))
            if srgb is not None:
                out[slot] = "#" + srgb.get("val").upper()
            else:
                sys_clr = node.find(qn("a:sysClr"))
                if sys_clr is not None:
                    out[slot] = "#" + (sys_clr.get("lastClr") or "000000").upper()
        break
    return out
