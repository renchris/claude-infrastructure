#!/usr/bin/env python3
"""Painted-shape masking: the one primitive the cross-check arms were missing.

Both broken arms in `detect_xcheck.py` failed the same way, and it is worth
stating as one sentence because it will recur: **they took the modal colour of a
rectangular crop and called it the background.** A crop is a rectangle; a painted
element is whatever shape it actually paints. On a round button the corners of
that rectangle are page background, and they outvote a 16 px glyph. On a gradient
the backdrop repeats no colour at all, so the mode is the *text* -- 120 identical
white pixels beat 6,224 unique gradient ones -- and the arm silently measures the
text against itself and reports nothing. Neither failure is loud. Both look like
a clean page.

So the fix for both is one function: separate the pixels the element actually
painted from the pixels that were merely inside its box, using nothing but the
render itself.

`painted_shape` floods inward from the crop's border over everything that matches
the border's own colour, and calls the unreached remainder the painted shape.
That is exactly right for the case it is used on -- a filled mark on a distinct
backdrop -- and it has the property that matters here: a mark's *interior*
detail is never mistaken for outside, because the interior is not connected to
the border. A white glyph on a blue disc on a white page survives; taking "close
to white" as outside would have deleted the glyph.

⚠️ This is the cheap offline approximation of S1b's INK-PROBE, which gets the
same mask by re-rendering the element `visibility:hidden` and differencing
(PIPELINE_SPEC §1.2, deferred as B19b). The differential probe is strictly
better -- it needs no assumption about shape or backdrop at all -- and it needs a
live browser. This one needs a PNG. Where its assumption does not hold it
returns a REASON rather than a mask, and every caller is required to abstain on
that reason rather than fall back to the rectangle. Falling back to the rectangle
is the bug.
"""

from __future__ import annotations

import numpy as np

# Two colours are "the same" within 24 summed over three channels -- 8 levels per
# channel, which is above PNG-level antialiasing chatter and far below any
# deliberate design difference. It is not tuned: 8/255 is under the 5/255 colour
# drift the corpus injects as its SMALLEST detectable defect, so a difference
# this function calls noise is one no rule is allowed to report anyway.
OUTSIDE_TOL = 24
# Ink is anything 40 away from the shape's own fill. Inherited unchanged from the
# arm this replaces, so a mask change cannot be confused with a threshold change.
INK_TOL = 40
# Below this share of a band, there is not enough backdrop left to call anything
# the backdrop, and the honest answer is that the sample failed.
MIN_BG_FRAC = 0.20


def dilate(m: np.ndarray) -> np.ndarray:
    """4-connected one-step growth. No scipy: this whole module is ~10 ms."""
    o = m.copy()
    o[1:, :] |= m[:-1, :]
    o[:-1, :] |= m[1:, :]
    o[:, 1:] |= m[:, :-1]
    o[:, :-1] |= m[:, 1:]
    return o


def erode(m: np.ndarray, k: int = 1) -> np.ndarray:
    """Shrink by k pixels. Used to drop the antialiased rim of a shape, which
    blends fill into backdrop and would otherwise read as ink all the way round
    the edge -- a ring of false ink centred exactly where the real ink is, which
    is the most dangerous possible artefact for a centroid."""
    for _ in range(k):
        p = np.pad(m, 1, constant_values=False)
        m = p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return m


def painted_shape(region: np.ndarray, tol: int = OUTSIDE_TOL):
    """-> (mask, outside_colour, reason). `reason` is "" only when the mask is
    trustworthy; anything else is an abstention the caller must honour.

    The mask is True where the element painted something other than the colour
    its own border pixels carry.
    """
    h, w = region.shape[:2]
    r32 = region.astype(np.int32)
    corners = np.stack([r32[0, 0], r32[0, -1], r32[-1, 0], r32[-1, -1]])
    outside = np.median(corners, axis=0)
    # If the four corners do not agree, the crop's border is not one backdrop --
    # the element overlaps something, or sits on its own gradient. Either way
    # "outside" is not a colour and the flood has no legal seed.
    if np.abs(corners - outside).sum(axis=1).max() > tol:
        return None, outside, "outside-not-uniform"

    like_outside = np.abs(r32 - outside).sum(axis=2) <= tol
    seed = np.zeros((h, w), bool)
    seed[0, :] = seed[-1, :] = True
    seed[:, 0] = seed[:, -1] = True
    reached = seed & like_outside
    # Bounded by the crop's own half-perimeter: a 4-connected flood cannot take
    # more steps than that to cross the region, so this terminates by geometry
    # rather than by hoping the fixpoint arrives.
    for _ in range(h + w):
        nxt = dilate(reached) & like_outside
        if nxt.sum() == reached.sum():
            break
        reached = nxt

    mask = ~reached
    frac = float(mask.mean())
    if frac >= 0.99:
        # Nothing was reachable from the border: the element's fill IS its
        # backdrop's colour, so there is no shape to separate.
        return None, outside, "no-distinct-fill"
    if frac < 0.25:
        # A sliver. Whatever this is, a centroid over it is not a claim about
        # where a mark sits inside its container.
        return None, outside, "shape-too-small"
    return mask, outside, ""


def ink_within(region: np.ndarray, shape: np.ndarray, tol: int = INK_TOL):
    """-> (ink_mask, fill_colour). Ink is what differs from the shape's own fill,
    counted only inside the shape. The fill is the mode taken over the shape, not
    over the crop, which is the entire point of the mask."""
    px = region[shape]
    vals, counts = np.unique(px, axis=0, return_counts=True)
    fill = vals[counts.argmax()]
    ink = shape & (
        np.abs(region.astype(np.int32) - fill.astype(np.int32)).sum(axis=2) > tol
    )
    return ink, fill


def centroid(mask: np.ndarray):
    """-> (cx, cy) in pixel coordinates of the mask's own frame, or None."""
    if not mask.any():
        return None
    ys, xs = np.nonzero(mask)
    return float(xs.mean()), float(ys.mean())


def backdrop_of(band: np.ndarray, fg, tol: int = INK_TOL * 2):
    """-> (rgb, bg_frac) or (None, frac): the colour BEHIND the text in a band.

    Two changes from "take the mode", and each fixes a measured failure:

      1. Pixels close to the known foreground colour are removed first. The
         foreground is a DOM fact, not a guess, and dropping it is what stops the
         text being sampled as its own backdrop.
      2. What remains is summarised by the per-channel MEDIAN, not the mode. A
         gradient has no mode -- every column is a different colour, so the mode
         is whichever colour happens to repeat, which on a text run is the text.
         The median of a gradient band is a real colour from the middle of that
         band, and on a solid backdrop the median IS the solid colour, so this is
         strictly better on both and not merely different.

    Returns None when too little backdrop survives to summarise, which is an
    abstention: a text run that fills its own box leaves nothing to measure.
    """
    fb = band.reshape(-1, 3).astype(np.int32)
    not_ink = np.abs(fb - np.asarray(fg[:3], dtype=np.int32)).sum(axis=1) > tol
    frac = float(not_ink.mean())
    if frac < MIN_BG_FRAC:
        return None, frac
    return np.median(fb[not_ink], axis=0), frac


def band_px(scale: float) -> float:
    """The instrument's own tolerance, in CSS px, derived from the capture rather
    than chosen. PIPELINE_SPEC §1.4: `band = J1(0.5/dpr) + J2(0.25 fractional
    layout) + J3(0.5/line-box)`. A constant tolerance is wrong at both DPRs and
    silently wrong at 1.5 -- and a profile may never loosen this, because a band
    is physics, not policy."""
    return 0.5 / scale + 0.25 + 0.5
