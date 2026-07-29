#!/usr/bin/env python3
"""banner-collide.py — assert the creature never lands on the wordmark.

R2 makes the title load-bearing: it has to be legible at t=0 and at every t. An always-visible
title that something else is standing on top of satisfies the letter of that and none of its point,
and it is easy to do by accident — the first kit build placed the creature at a hand-picked x and it
covered "ctu" in "infrastructure". A layout that is checked by eye gets checked once, at one
timestamp, on one composition.

So this reads it back out of the rendered PNG rather than trusting the arithmetic that placed it:
the creature is the only saturated-orange thing in frame and the title is the only near-white thing,
so their column ranges are separable without knowing anything about the composition. Overlapping
column ranges are reported as a collision.

Columns, not boxes, because that is the failure that matters: the creature is placed BESIDE the
wordmark, so a horizontal gap is exactly the invariant. A composition that deliberately puts the
creature above or below the title passes `--allow-columns` and is checked on rows instead.

  scripts/banner-collide.py shots/hero-dark-t0.png [more.png ...]
  scripts/banner-collide.py --allow-columns shots/*.png     # stacked layouts
"""

from __future__ import annotations

import argparse
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - environment problem, not a finding
    sys.exit("banner-collide: needs Pillow (python3 -m pip install pillow)")

BODY = (0xD7, 0x77, 0x57)
TOL = 26  # the plate gradient and antialiasing move a pixel a little; a hue this far off is not it


def _near(px: tuple[int, int, int], ref: tuple[int, int, int], tol: int = TOL) -> bool:
    return all(abs(a - b) <= tol for a, b in zip(px, ref))


def _bright(px: tuple[int, int, int]) -> bool:
    """Title ink: near-white and unsaturated. Excludes the orange, which is bright but not grey."""
    r, g, b = px
    return min(px) > 150 and (max(px) - min(px)) < 40


def extents(path: str) -> tuple[dict[str, tuple[int, int]], int, int]:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    found: dict[str, list[int]] = {}
    for name in ("creature_x", "creature_y", "title_x", "title_y"):
        found[name] = []
    for y in range(h):
        for x in range(w):
            p = im.getpixel((x, y))
            if _near(p, BODY):
                found["creature_x"].append(x)
                found["creature_y"].append(y)
            elif _bright(p):
                found["title_x"].append(x)
                found["title_y"].append(y)
    out = {}
    for name, vals in found.items():
        out[name] = (min(vals), max(vals)) if vals else None
    return out, w, h


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pngs", nargs="+")
    ap.add_argument(
        "--allow-columns",
        action="store_true",
        help="the layout stacks the creature above/below the title, so check rows instead",
    )
    a = ap.parse_args()

    axis = "y" if a.allow_columns else "x"
    bad = 0
    for png in a.pngs:
        e, w, h = extents(png)
        c, t = e[f"creature_{axis}"], e[f"title_{axis}"]
        name = png.rsplit("/", 1)[-1]
        if c is None:
            print(f"  {name}: FAIL — no creature found (is the body still {BODY}?)")
            bad += 1
            continue
        if t is None:
            print(
                f"  {name}: FAIL — no title ink found. R2 requires it at EVERY timestamp."
            )
            bad += 1
            continue
        gap = max(c[0], t[0]) - min(c[1], t[1])
        if gap > 0:
            print(
                f"  {name}: ok — creature {axis} {c}, title {axis} {t}, clear by {gap - 1}px"
            )
        else:
            print(f"  {name}: FAIL — creature {axis} {c} overlaps title {axis} {t}")
            bad += 1
    if bad:
        print(
            f"banner-collide: {bad} of {len(a.pngs)} frame(s) collide", file=sys.stderr
        )
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
