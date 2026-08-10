"""
tokens.py -- the design tokens, and the one place a literal value is allowed to exist.

TWO IDEAS GOVERN THIS FILE.

1. NO LITERAL ANYWHERE ELSE.
   Every colour, size, weight and spacing used by any component resolves through a token.
   Not because indirection is virtuous, but because a literal is un-auditable: you cannot
   grep a deck for "places that used a slightly-off grey", and a slide with #6B7386 next to
   forty slides with #7C8598 looks like a rendering artifact rather than a bug. Tokens make
   the palette a closed set, and `verify.py` can then assert the deck used only colours the
   brand actually has.

2. THE BRAND IS DATA; THE ENGINE IS CODE.
   The palette, typefaces and legal furniture live in a `Brand` object loaded from JSON --
   not baked into these modules. Everything else here (the type scale, the spacing rhythm,
   the composition rules) is brand-independent craft that applies to any corporate deck.

   That split is deliberate and load-bearing. It means this package is a general
   brand-deck engine that KPMG's values are passed INTO, so pointing it at a different
   brand is a data change rather than a fork. It also means the KPMG values can be corrected
   -- when the brand moves, or when a better source than the public web is available -- by
   editing one JSON file, with no risk of missing an occurrence buried in a component.

   The corollary matters for anyone using this: values in `brands/kpmg.json` are extracted
   from PUBLIC sources and carry a provenance tier each. They are not a substitute for the
   official brand portal. Where an official template exists, load ITS theme instead and let
   the extracted values serve only as the fallback. `Brand.provenance_warning()` says so at
   build time rather than leaving it to be assumed.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Any, Mapping

# ---------------------------------------------------------------------------
# The type scale
# ---------------------------------------------------------------------------
#
# A modular scale at roughly 1.25 (the major third), anchored on 18pt body.
#
# Why a fixed scale rather than free sizes: hierarchy is read as RATIO, not as absolute size.
# When every slide draws from the same eleven values, a viewer learns the deck's grammar once
# -- this size means "claim", that size means "support" -- and every later slide is legible
# without re-learning. Free-floating sizes produce a 37pt headline on one slide and 39pt on
# the next, each locally defensible, collectively noise.
#
# The floor is 14pt and it is a hard floor, not a preference. Below that, text is unreadable
# past the middle of a large room, and the standard consulting habit of dropping to 10pt to
# fit more on is precisely the move that turns a slide into a document.

SCALE = {
    "micro": 11,  # legal furniture, copyright, document classification ONLY -- never content
    "footnote": 14,  # source lines, footnotes. The floor for anything a reader must read.
    "caption": 16,  # labels under figures, axis labels, table cells
    "small": 18,  # secondary body
    "body": 20,  # the default for support text on a slide
    "lead": 24,  # emphasised support, deck lede
    "h3": 28,  # sub-headings inside a slide
    "h2": 34,  # slide headline, the common case
    "h1": 44,  # slide headline when it is the only thing on the slide
    "display": 60,  # section dividers, statement slides
    "hero": 88,  # cover title
    "mega": 150,  # a single statistic used as the whole slide
}

MIN_READABLE_PT = 14
MIN_HEADLINE_PT = 28


# ---------------------------------------------------------------------------
# Spacing
# ---------------------------------------------------------------------------
#
# An 8pt-derived rhythm expressed in points. Components space by NAME, never by number, so
# that vertical relationships stay proportional if the scale is ever retuned.

SPACE = {
    "hair": 4,
    "xs": 8,
    "sm": 12,
    "md": 20,
    "lg": 32,
    "xl": 48,
    "xxl": 72,
}


# ---------------------------------------------------------------------------
# Type treatment
# ---------------------------------------------------------------------------
#
# Tracking (letter-spacing) as a fraction of the point size. These are not decorative.
# Type drawn for body copy carries sidebearings tuned for 10-12pt; scaled to 60pt those gaps
# read as holes, so display type needs negative tracking. Small caps and short label text need
# positive tracking or the letterforms crowd. Applying no tracking at either end is one of the
# clearest differences between set type and typed text.

TRACKING = {
    "hero": -0.022,
    "display": -0.018,
    "h1": -0.014,
    "h2": -0.010,
    "h3": -0.006,
    "body": 0.0,
    "eyebrow": 0.10,  # small caps labels
    "footnote": 0.0,
}

# Leading. NOT a multiple of the point size -- a multiple of THE FONT'S OWN LINE HEIGHT.
#
# This distinction is the whole reason these numbers changed, and it is invisible until it is
# measured. PowerPoint's proportional line spacing multiplies the font's line height, which for
# Arial Bold is 1.13em (measured: 50.0pt at 44, 68.0 at 60, 99.0 at 88) -- not the point size.
# So the previous `hero: 0.84`, documented as "73.9pt leading on 88pt type", actually produced
# 99.0 x 0.84 = 83.2pt. Every display value was running ~15% looser than its own comment said.
#
# The visual target is pitch relative to CAP HEIGHT, because that is what the eye reads. KPMG
# runs pitch/cap = 1.30 on page headlines (66.0 / (75 x 0.678)) and 1.195 on covers. Arial
# Bold's cap height is 0.716em. The values below hit those two targets:
#
#   role       value   -> pitch/size   pitch/cap    KPMG measured
#   hero       0.76       0.859        1.20         1.195 (cover)
#   display    0.82       0.927        1.29         1.30  (page headline)
#   h1         0.82       0.927        1.29         1.30
#   h2         0.90       1.017        1.42         --
#
# The prior values measured pitch/cap 1.73 on our own section divider against KPMG's 1.32 --
# a headline block half again as tall as theirs for the same words, which is most of why our
# dividers read as captions on a field rather than as type used as the graphic.
#
# Body runs the opposite way, because prose is read rather than scanned. KPMG's own body is
# 10.5/13 = 1.238 x SIZE; 1.22 x 1.13 = 1.379 x size is the room-legible compromise at 20pt.

LINE_SPACING = {
    "hero": 0.76,
    "display": 0.82,
    "h1": 0.82,
    "h2": 0.90,
    "h3": 1.15,
    "body": 1.22,
    "footnote": 1.25,
}


def tracking_pt(role: str, size_pt: float) -> float:
    """Tracking for a role, in points, given the size it is set at."""
    return TRACKING.get(role, 0.0) * size_pt


# ---------------------------------------------------------------------------
# Brand
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Brand:
    """
    A brand's data. Loaded from JSON; never hardcoded in a component.

    `theme_colors` maps the twelve OOXML theme slots. It is what theme.apply() writes, and
    therefore what every `schemeClr` reference in the deck resolves to.

    `roles` is the semantic layer the components actually speak: 'ink', 'canvas', 'accent',
    'muted', 'rule'. A component asks for the role; the brand decides the value. This is the
    indirection that lets one component render correctly on a light slide and a dark one.
    """

    name: str
    theme_colors: Mapping[str, str]
    roles: Mapping[str, str]
    dataviz: list[str]
    font_major: str
    font_minor: str
    # Colours the brand reserves for charts and infographics and forbids as page furniture.
    # Empty for a brand that draws no such line. See kpmg.json's _chart_only_note.
    chart_only: list[str] = field(default_factory=list)
    font_preferred_major: str | None = None
    font_fallbacks: list[str] = field(default_factory=list)
    legal: Mapping[str, str] = field(default_factory=dict)
    provenance: Mapping[str, Any] = field(default_factory=dict)
    notes: str = ""

    # -- access -------------------------------------------------------------

    def color(self, role: str) -> str:
        """Resolve a semantic role to a hex value. Raises on an unknown role."""
        if role in self.roles:
            return self.roles[role]
        if role in self.theme_colors:
            return self.theme_colors[role]
        raise KeyError(
            f"unknown colour role {role!r} for brand {self.name!r}. "
            f"Known roles: {sorted(self.roles)}; theme slots: {sorted(self.theme_colors)}"
        )

    def series(self, index: int) -> str:
        """The nth data-visualisation colour, cycling. Order is the brand's chart order."""
        if not self.dataviz:
            raise ValueError(
                f"brand {self.name!r} declares no data-visualisation palette"
            )
        return self.dataviz[index % len(self.dataviz)]

    def provenance_warning(self) -> str | None:
        """
        The honest statement about where these values came from.

        Returns a warning string when any part of the brand data is below primary-source
        confidence, and None when the brand was loaded from an official template. Callers
        print this at build time. A deck built on inferred brand values is a perfectly
        reasonable thing to produce; one that does not KNOW it was is not.
        """
        tier = self.provenance.get("overall_tier")
        if tier in (None, "T1"):
            return None
        contested = self.provenance.get("contested") or []
        msg = (
            f"Brand '{self.name}' was built from tier-{tier} public sources, not an official "
            f"template. Colours and typefaces are best-effort."
        )
        if contested:
            msg += " Contested values: " + "; ".join(str(c) for c in contested) + "."
        official = self.provenance.get("official_source")
        if official:
            msg += f" Authoritative source: {official}"
        return msg

    # -- loading ------------------------------------------------------------

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> "Brand":
        required = ("name", "theme_colors", "roles", "font_major", "font_minor")
        missing = [k for k in required if k not in data]
        if missing:
            raise ValueError(f"brand data is missing required keys: {missing}")

        from .theme import CLR_SLOTS

        missing_slots = [s for s in CLR_SLOTS if s not in data["theme_colors"]]
        if missing_slots:
            raise ValueError(
                f"brand {data['name']!r} is missing theme slots {missing_slots}. "
                f"All twelve are required or the theme rewrite is invalid."
            )

        return cls(
            name=data["name"],
            theme_colors=dict(data["theme_colors"]),
            roles=dict(data["roles"]),
            dataviz=list(data.get("dataviz", [])),
            chart_only=list(data.get("chart_only", [])),
            font_major=data["font_major"],
            font_minor=data["font_minor"],
            font_preferred_major=data.get("font_preferred_major"),
            font_fallbacks=list(data.get("font_fallbacks", [])),
            legal=dict(data.get("legal", {})),
            provenance=dict(data.get("provenance", {})),
            notes=data.get("notes", ""),
        )

    @classmethod
    def load(cls, name_or_path: str) -> "Brand":
        """
        Load a brand by name (from the bundled brands/ directory) or from an explicit path.

            Brand.load("kpmg")
            Brand.load("/path/to/our-brand.json")
        """
        if os.path.isfile(name_or_path):
            path = name_or_path
        else:
            path = os.path.join(
                os.path.dirname(__file__), "brands", f"{name_or_path}.json"
            )
            if not os.path.isfile(path):
                available = _available_brands()
                raise FileNotFoundError(
                    f"no brand {name_or_path!r}. Available: {available}. "
                    f"Or pass an absolute path to a brand JSON file."
                )
        with open(path, "r", encoding="utf-8") as fh:
            return cls.from_dict(json.load(fh))


def _available_brands() -> list[str]:
    directory = os.path.join(os.path.dirname(__file__), "brands")
    if not os.path.isdir(directory):
        return []
    return sorted(f[:-5] for f in os.listdir(directory) if f.endswith(".json"))


# ---------------------------------------------------------------------------
# Contrast -- a mechanical gate, not a judgement call
# ---------------------------------------------------------------------------


def _srgb_to_linear(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def relative_luminance(hex_color: str) -> float:
    """WCAG 2.x relative luminance."""
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return (
        0.2126 * _srgb_to_linear(r)
        + 0.7152 * _srgb_to_linear(g)
        + 0.0722 * _srgb_to_linear(b)
    )


def contrast_ratio(fg: str, bg: str) -> float:
    """WCAG contrast ratio between two colours, 1.0 to 21.0."""
    l1, l2 = relative_luminance(fg), relative_luminance(bg)
    lighter, darker = max(l1, l2), min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def contrast_verdict(
    fg: str, bg: str, size_pt: float, bold: bool = False
) -> tuple[str, float]:
    """
    Judge a text/background pairing against WCAG AA.

    "Large text" in WCAG means >=18pt, or >=14pt bold, and gets the relaxed 3.0:1 threshold
    instead of 4.5:1. Nearly all slide type is large by that definition, which is why passing
    on a slide is easier than on a web page -- and why a FAIL here is genuinely serious rather
    than pedantic.

    A caveat the standard does not cover, and it matters more than the standard here: a
    conference projector in a lit room loses a great deal of contrast against a laptop screen.
    Mid-tone on mid-tone that measures 3.2:1 and passes will not be readable from the back of
    a 140-person room. Treat 3.0 as the legal floor and 4.5 as the practical one for anything
    the audience actually has to read.
    """
    ratio = contrast_ratio(fg, bg)
    is_large = size_pt >= 18 or (size_pt >= 14 and bold)
    threshold = 3.0 if is_large else 4.5
    if ratio >= 7.0:
        return ("PASS-AAA", ratio)
    if ratio >= threshold:
        return ("PASS-AA-LARGE" if is_large and ratio < 4.5 else "PASS-AA", ratio)
    return ("FAIL", ratio)
