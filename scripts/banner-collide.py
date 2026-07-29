#!/usr/bin/env python3
"""banner-collide.py — assert the creature never lands on the wordmark.

R2 makes the title load-bearing: it has to be legible at t=0 and at every t. An always-visible
title that something else is standing on top of satisfies the letter of that and none of its point,
and it is easy to do by accident — the first kit build placed the creature at a hand-picked x and it
covered "ctu" in "infrastructure". A layout that is checked by eye gets checked once, at one
timestamp, on one composition.

So this reads it back out of the rendered PNG rather than trusting the arithmetic that placed it:
the creature is the only saturated-orange thing in frame and the title is the only near-white thing,
so their extents are separable without knowing anything about the composition.

The invariant is that the two boxes do not INTERSECT, which holds as soon as either axis is clear —
so a creature beside the title and a creature above it both pass, and neither needs to declare which
it is. Checking one named axis would fail every stacked layout for the crime of being stacked.

It also asserts the title is present at all: a frame with no title ink is an R2 violation whatever
the geometry says, and that is worth catching at every timestamp rather than at t=0 only.

  scripts/banner-collide.py shots/*.png
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


MIN_BLOB = 400  # px; below this it is antialiasing on a hairline, not a creature


def scan(
    path: str,
) -> tuple[list[tuple[int, int, int, int]], tuple[int, int, int, int] | None]:
    """Return one box per CREATURE, plus one box for the whole title.

    Creatures are labelled individually rather than taken as a single union. A union is not merely
    imprecise here, it is wrong in both directions: a fleet with creatures either side of the title
    has a union spanning the title on both axes, so a perfectly clear layout reports a collision.
    The title stays a union because it genuinely is one run of text.
    """
    im = Image.open(path).convert("RGB")
    w, h = im.size
    # One flat bytes buffer, walked once. Per-pixel im.getpixel() over 45 frames of 1800x487 is
    # ~39M calls and takes minutes; this is the same arithmetic without the call overhead.
    buf = im.tobytes()

    mask = bytearray(w * h)
    tx0, ty0, tx1, ty1 = w, h, -1, -1
    br, bg, bb = BODY
    for i in range(0, len(buf), 3):
        r, g, b = buf[i], buf[i + 1], buf[i + 2]
        if abs(r - br) <= TOL and abs(g - bg) <= TOL and abs(b - bb) <= TOL:
            mask[i // 3] = 1
        else:
            lo = r if r < g else g
            lo = lo if lo < b else b
            if lo > 150:
                hi = r if r > g else g
                hi = hi if hi > b else b
                if hi - lo < 40:
                    p = i // 3
                    y, x = divmod(p, w)
                    if x < tx0:
                        tx0 = x
                    if x > tx1:
                        tx1 = x
                    if y < ty0:
                        ty0 = y
                    if y > ty1:
                        ty1 = y

    blobs = []
    for start in range(w * h):
        if mask[start] != 1:
            continue
        stack, x0, y0, x1, y1, area = [start], w, h, -1, -1, 0
        mask[start] = 2
        while stack:
            i = stack.pop()
            cy, cx = divmod(i, w)
            area += 1
            x0, x1 = min(x0, cx), max(x1, cx)
            y0, y1 = min(y0, cy), max(y1, cy)
            for j, ok in (
                (i - 1, cx > 0),
                (i + 1, cx < w - 1),
                (i - w, cy > 0),
                (i + w, cy < h - 1),
            ):
                if ok and mask[j] == 1:
                    mask[j] = 2
                    stack.append(j)
        if area >= MIN_BLOB:
            blobs.append((x0, y0, x1, y1))

    title = (tx0, ty0, tx1, ty1) if tx1 >= 0 else None
    return blobs, title


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pngs", nargs="+")
    a = ap.parse_args()

    bad = 0
    for png in a.pngs:
        blobs, title = scan(png)
        name = png.rsplit("/", 1)[-1]
        if not blobs:
            print(f"  {name}: FAIL — no creature found (is the body still {BODY}?)")
            bad += 1
            continue
        if title is None:
            print(
                f"  {name}: FAIL — no title ink found. R2 requires it at EVERY timestamp."
            )
            bad += 1
            continue

        tx0, ty0, tx1, ty1 = title
        worst, worst_box = None, None
        for x0, y0, x1, y1 in blobs:
            # Clear on EITHER axis means the boxes do not intersect. Take each creature's better
            # axis, then the whole frame is only as good as its worst creature.
            gap = max(
                max(x0, tx0) - min(x1, tx1) - 1,
                max(y0, ty0) - min(y1, ty1) - 1,
            )
            if worst is None or gap < worst:
                worst, worst_box = gap, (x0, y0, x1, y1)

        if worst >= 0:
            print(
                f"  {name}: ok — {len(blobs)} creature(s), tightest clearance {worst}px"
            )
        else:
            print(
                f"  {name}: FAIL — creature {worst_box} overlaps the title {title} "
                f"by {-worst}px ({len(blobs)} creature(s) in frame)"
            )
            bad += 1
    if bad:
        print(
            f"banner-collide: {bad} of {len(a.pngs)} frame(s) collide", file=sys.stderr
        )
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
