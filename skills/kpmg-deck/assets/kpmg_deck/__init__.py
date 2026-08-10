"""
kpmg_deck -- a brand-driven PowerPoint engine.

The brand is DATA (brands/*.json); everything else is brand-independent craft. Point it at a
different brand file and the same engine produces that brand's deck.

Typical use:

    from kpmg_deck import Deck, Brand
    deck = Deck(Brand.load("kpmg"))
    deck.cover("Set up a clean workspace", "KPMG Lakehouse | September 2026")
    deck.save("out.pptx")
"""

from .tokens import Brand, SCALE, SPACE, contrast_ratio, contrast_verdict
from .canvas import Box, Grid, GRID, inches, points

__all__ = ["Brand", "SCALE", "SPACE", "contrast_ratio", "contrast_verdict",
           "Box", "Grid", "GRID", "inches", "points"]
