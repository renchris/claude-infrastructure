#!/usr/bin/env python3
"""Cross-check the DOM against the pixels, and report only where they DISAGREE.

Neither substrate alone found the optical-centering defect in this corpus. The
DOM cannot: every box-model number is symmetric, because the flex container really
does centre the glyph. A vision model did not: the offset is ~2px of ink inside a
44px button and reads as correct. The defect lives in neither description -- it
lives in the gap between them.

So this is not a third detector. It is a comparator. Each check takes a claim the
DOM makes about an element, measures the same claim off the rendered pixels, and
fires only when the two answers differ by more than a stated tolerance. That gives
it a property neither layer has: it needs no aesthetic judgement and no learned
model, and its findings are automatically about real rendering rather than about
authored intent.

Three checks, chosen because each maps to a documented way DOM-only review is
unsound:

  X1 zero-ink        an element reports a healthy box and paints nothing.
  X2 ink-centroid    a mark's rendered ink is not centred in the shape that
                     contains it. ON by default since the two defects below were
                     fixed; `--no-x2` turns it off.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

X2, and why it was off
----------------------
It shipped disabled because trying to validate it found two defects, and both
were instances of the failure this whole substrate warns about -- a plausible
number nobody checked. Both are now fixed, and the fixes are the two the
research named:

  (a) MEASURE AGAINST THE CONTAINER. It compared ink to the element's OWN box,
      and getBoundingClientRect returns the POST-transform box, so a `translate`
      moves box and ink together and the measured offset is INVARIANT under the
      very compensation it is supposed to verify. Measured on this corpus: the
      old arm reported 2.2px left / 1.9px up on the clean control AND on the
      variant that deletes the control's compensation -- the same number for the
      right answer and the wrong one, which is a detector with zero information.
      It now measures the mark's ink centroid against the centroid of the
      CONTAINER's painted shape, which is the frame a reader's eye actually uses
      and the one thing the compensating transform moves the ink relative to.

  (b) MASK TO THE PAINTED SHAPE. Its background was the crop's modal colour, so
      on a round button the square crop's corners -- page background outside the
      circle -- counted as ink and swamped a 16px glyph. The mask is now built
      analytically from the container's own rect and border-radius, which is
      geometry the DOM returns exactly and for free. That is the governing rule
      of the whole pipeline applied here: the pixels supply identity, the DOM
      supplies geometry. Nothing outside the painted shape can vote.

The arm still refuses more than it fires, on purpose. It runs only where the
subject is a small self-contained mark inside a small self-contained container,
because that is the only configuration where "centred" is a claim with one
meaning. A paragraph's ink is legitimately top-left-heavy because text flows.

Usage: python3 detect_xcheck.py <corpus-dir> [--no-x2]
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image

from rules import assert_registered

# Tolerances are stated, not tuned. Each is well above sub-pixel rounding and
# well below what a person would call "off", so a finding means a real gap.
INK_MIN_FRAC = (
    0.002  # below this share of non-background pixels, the box paints nothing
)
CENTROID_TOL_PX = 1.0  # ink centroid vs the painted shape's centroid
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
INK_DIST = 40  # channel-sum distance from the backdrop that counts as ink

# X2's admission window. A mark and a container both small enough that "centred"
# is a claim with exactly one meaning, and a mark small enough for its ink
# distribution to be the whole story.
X2_MARK_MAX_PX = 64
X2_CONTAINER_MAX_PX = 96
X2_MARK_MAX_CHARS = 3
SHAPE_INSET_PX = 2.0  # CSS px trimmed off the container's own antialiased edge
# A mark can be a short text run or a small graphic. Icon buttons in real apps
# are overwhelmingly the second, and the arm was blind to all of them.
MARK_TAGS = {"svg", "img", "i", "canvas"}

X2_ENABLED = "--no-x2" not in sys.argv


def rel_lum(rgb) -> float:
    def ch(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = rgb[:3]
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b) -> float:
    l1, l2 = rel_lum(a), rel_lum(b)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def parse_rgb(s: str):
    if not s or "rgb" not in s:
        return None
    nums = s[s.find("(") + 1 : s.find(")")].replace("/", " ").replace(",", " ").split()
    try:
        v = [float(x.rstrip("%")) for x in nums[:4]]
    except ValueError:
        return None
    if len(v) == 3:
        v.append(1.0)
    return tuple(v)


def _opaque(css_colour: str) -> bool:
    """Does this background-color actually paint a shape?"""
    c = parse_rgb(css_colour)
    return bool(c) and c[3] > 0.5


def px(v) -> float:
    try:
        return float(str(v).replace("px", "").strip())
    except (ValueError, AttributeError):
        return 0.0


def shape_mask(h: int, w: int, radius_px: float, inset_px: float = 0.0) -> np.ndarray:
    """The painted shape of a rounded rectangle, as a boolean mask.

    X2 fix (b). Built from the container's own `border-radius` and box, both of
    which the DOM returns exactly -- so the mask is a statement about what the
    browser was asked to paint, not a guess read back out of the pixels. A
    guessed mask would be a second estimate stacked on the estimate it exists to
    correct, and on a round button the corners it has to exclude are the exact
    pixels that broke the old arm.

    `radius_px` and `inset_px` arrive in device pixels, already scaled. The
    radius is clamped to half the shorter side, which is how CSS resolves an
    over-large radius into a pill or a circle.

    `inset_px` shrinks the shape away from its own edge, and it is not a
    nicety. The shape's boundary is antialiased -- a one-pixel ring of blends
    between the container's fill and whatever is behind it -- and every pixel in
    that ring differs from the fill, so an un-inset mask reads the ring as ink.
    Measured on this corpus: the ring is ~84 px against a 16px glyph's ~70, so
    it is the MAJORITY of the ink, it is centred, and it therefore drags every
    centroid toward the middle. It halved the real 2.0px offset to 1.18px and
    left a residual on the control large enough to fire. A border does the same
    thing more loudly. Two device pixels clears both.
    """
    r = max(0.0, min(radius_px, min(h, w) / 2.0))
    e = max(0.0, inset_px)
    ys = np.arange(h)[:, None] + 0.5
    xs = np.arange(w)[None, :] + 0.5
    inside = (xs >= e) & (xs <= w - e) & (ys >= e) & (ys <= h - e)
    rr = max(0.0, r - e)
    if rr < 0.5:
        return inside
    # Distance into each corner's quarter-disc. A pixel is outside the shape only
    # when it is outside the corner arc, which is why both terms are clamped at 0.
    dx = np.maximum(np.maximum((e + rr) - xs, xs - (w - e - rr)), 0.0)
    dy = np.maximum(np.maximum((e + rr) - ys, ys - (h - e - rr)), 0.0)
    return inside & ((dx * dx + dy * dy) <= rr * rr)


def bounds(img: np.ndarray, rect: dict, scale: float):
    """Integer pixel bounds of a CSS rect in this image, clamped to it."""
    h, w = img.shape[:2]
    x0 = max(0, int(round(rect["x"] * scale)))
    y0 = max(0, int(round(rect["y"] * scale)))
    x1 = min(w, int(round(rect["right"] * scale)))
    y1 = min(h, int(round(rect["bottom"] * scale)))
    if x1 - x0 < MIN_BOX or y1 - y0 < MIN_BOX:
        return None
    return x0, y0, x1, y1


def crop(img: np.ndarray, rect: dict, scale: float):
    b = bounds(img, rect, scale)
    return None if b is None else img[b[1] : b[3], b[0] : b[2]]


def check(snap: dict, png: pathlib.Path, census: dict | None = None) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    out = []
    by_path = {e["path"]: e for e in snap["elements"]}

    def parent_of(el):
        p = el["path"].rsplit(" > ", 1)
        return by_path.get(p[0]) if len(p) > 1 else None

    def note(rule, subjects=1):
        if census is not None:
            assert_registered(rule)
            census[rule] = census.get(rule, 0) + subjects

    def rep(rule, target, detail, severity="medium", meta=None):
        assert_registered(rule)
        f = {"rule": rule, "target": target, "detail": detail, "severity": severity}
        if meta:
            f["meta"] = meta
        out.append(f)

    for el in snap["elements"]:
        r = el["rect"]
        if r["w"] < MIN_BOX or r["h"] < MIN_BOX:
            continue
        region = crop(img, r, scale)
        if region is None:
            continue

        # The element's own modal colour is its background; anything else is ink.
        flat = region.reshape(-1, 3)
        vals, counts = np.unique(flat, axis=0, return_counts=True)
        bg = vals[counts.argmax()]
        dist = np.abs(region.astype(np.int32) - bg.astype(np.int32)).sum(axis=2)
        ink = dist > INK_DIST
        frac = float(ink.mean())

        # --- X1: the DOM says there is an element here; the pixels say nothing --
        if el["text"]:
            note("xcheck-zero-ink")
        if el["text"] and frac < INK_MIN_FRAC:
            rep(
                "xcheck-zero-ink",
                el["path"],
                f"box is {r['w']:.0f}x{r['h']:.0f}px and carries text "
                f"{el['text'][:24]!r}, but only {frac * 100:.2f}% of its pixels differ "
                f"from its own background -- it paints nothing a reader can see",
                "high",
            )
            continue

        # --- X2: ink is not centred in the SHAPE that contains it --------------
        # Both halves of the old arm's failure are addressed here: the frame is
        # the container, not the element's own post-transform box (fix a), and
        # the vote is restricted to the container's painted shape (fix b).
        text_mark = el["text"].strip()
        graphic_mark = el["tag"] in MARK_TAGS
        mark = text_mark or (f"<{el['tag']}>" if graphic_mark else "")
        container = parent_of(el)
        admissible = (
            X2_ENABLED
            and (graphic_mark or (text_mark and len(text_mark) <= X2_MARK_MAX_CHARS))
            and r["w"] < X2_MARK_MAX_PX
            and r["h"] < X2_MARK_MAX_PX
            and container is not None
            and container["rect"]["w"] < X2_CONTAINER_MAX_PX
            and container["rect"]["h"] < X2_CONTAINER_MAX_PX
            # There must BE a shape to be off-centre in. A container that paints
            # no background of its own is not a frame a reader can see, and
            # centring a mark inside an invisible box is not a claim about
            # anything. This is also what stops the arm firing twice down a
            # nested chain -- an <svg> wrapping its own <polygon> is transparent,
            # so only the button that actually paints gets to be the container.
            and _opaque(container["styles"].get("background-color", ""))
        )
        if admissible:
            note("xcheck-optical-centre")
            cr = container["rect"]
            cb = bounds(img, cr, scale)
            creg = crop(img, cr, scale)
            if creg is not None:
                ch, cw = creg.shape[:2]
                mask = shape_mask(
                    ch,
                    cw,
                    px(container["styles"]["border-radius"]) * scale,
                    SHAPE_INSET_PX * scale,
                )
                inside = creg[mask]
                # The backdrop is the modal colour INSIDE the shape. Outside it,
                # the page shows through and is not this container's business.
                v, c = np.unique(inside, axis=0, return_counts=True)
                cbg = v[c.argmax()]
                cdist = np.abs(creg.astype(np.int32) - cbg.astype(np.int32)).sum(axis=2)
                cink = (cdist > INK_DIST) & mask
                # The reference point is the container's centre computed from its
                # own CSS rect, not the discrete mask's centroid. For a rounded
                # rectangle -- everything `border-radius` can describe -- the two
                # are the same point, and the analytic one is free of the crop's
                # rounding error. That error is not negligible at this scale: the
                # button's box starts at x=391.33 and the crop starts at 391, so
                # a mask centroid taken off the integer grid is 0.33px out and
                # read the exact 2.00px ground truth as 1.67.
                cx_ref = cr["x"] * scale + (cr["w"] * scale) / 2.0 - cb[0]
                cy_ref = cr["y"] * scale + (cr["h"] * scale) / 2.0 - cb[1]
                if cink.sum() >= 4 and mask.any():
                    # Weight each ink pixel by how far it is from the backdrop,
                    # which for a mark of one colour is proportional to its
                    # antialiasing coverage. A binary mask counts a 10%-covered
                    # edge pixel exactly as much as a solid one, and an edge is
                    # where a triangle has all its asymmetry: measured on this
                    # corpus, binary read the exact 2.00px ground truth as 1.65.
                    wt = np.where(cink, cdist.astype(np.float64), 0.0)
                    tot = wt.sum()
                    ys_i = np.arange(ch)[:, None] + 0.5
                    xs_i = np.arange(cw)[None, :] + 0.5
                    dx = ((wt * xs_i).sum() / tot - cx_ref) / scale
                    dy = ((wt * ys_i).sum() / tot - cy_ref) / scale
                    if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"{mark!r} is geometrically centred in "
                            f"{container['path'].rsplit(' > ', 1)[-1]} by the DOM, but "
                            f"its rendered ink sits {abs(dx):.1f}px "
                            f"{'left' if dx < 0 else 'right'} and {abs(dy):.1f}px "
                            f"{'up' if dy < 0 else 'down'} of that shape's centre -- it "
                            f"will read as off-centre however correct the CSS is",
                            meta={
                                "container": container["path"],
                                "dx_px": round(dx, 2),
                                "dy_px": round(dy, 2),
                                "ink_px": int(cink.sum()),
                            },
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            note("xcheck-contrast-varies")
            # Sample the actual backdrop under the text, separately in the left
            # and right thirds, so a backdrop that VARIES across the run cannot
            # hide behind a single number.
            #
            # Two properties this needs and the first version had neither, which
            # is why it reported nothing on a machine other than the one it was
            # written on:
            #
            #   The text's own ink must not vote. The comment always said "modal
            #   NON-INK colour"; the code took the modal colour of everything.
            #   Over a smooth gradient the backdrop has no repeated value at all,
            #   so the most-repeated colour in the band is the text -- white
            #   glyphs on this corpus -- and it scores 1.00:1 against itself. A
            #   nine-point contrast swing read as no swing at all.
            #
            #   The estimator must be robust, not modal. A gradient band is
            #   thousands of near-unique colours; whichever one happens to repeat
            #   twice wins a mode, and which one that is depends on the font
            #   rasteriser. The median of the surviving pixels is representative
            #   of the band by construction and identical to the mode on a solid
            #   backdrop, so nothing about the solid case changes.
            w = region.shape[1]
            fg_dist = np.abs(region.astype(np.int32) - np.array(fg[:3], dtype=np.int32))
            not_ink = fg_dist.sum(axis=2) > INK_DIST
            bands = {"left": slice(0, w // 3), "right": slice(w - w // 3, w)}
            sampled = {}
            for side, sl in bands.items():
                keep = region[:, sl][not_ink[:, sl]]
                if keep.size == 0:  # the band is all ink; no backdrop to sample
                    sampled = {}
                    break
                sampled[side] = np.median(keep, axis=0)
            if not sampled:
                continue
            cl = contrast(fg[:3], sampled["left"])
            cr = contrast(fg[:3], sampled["right"])
            if abs(cl - cr) > CONTRAST_DELTA:
                lo_side = "left" if cl < cr else "right"
                rep(
                    "xcheck-contrast-varies",
                    el["path"],
                    f"contrast is not one number across this text: {cl:.2f}:1 at the "
                    f"left edge and {cr:.2f}:1 at the right. Any single computed "
                    f"value is a fiction, and the {lo_side} end is the one that "
                    f"fails a reader",
                    "high",
                    meta={"left": round(cl, 2), "right": round(cr, 2)},
                )
    return out


def main(corpus: pathlib.Path) -> None:
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    results = {}
    for f in sorted(snaps.glob("*.json")):
        png = shots / f"{f.stem}.png"
        if not png.exists():
            continue
        results[f.stem] = check(json.loads(f.read_text()), png)
    (corpus / "findings_xcheck.json").write_text(json.dumps(results, indent=1))

    ctrl = results.get("clean", [])
    print(f"CONTROL clean.html -> {len(ctrl)} finding(s){'' if ctrl else '  (quiet)'}")
    for c in ctrl:
        print(f"    [{c['rule']}] {c['target']}: {c['detail'][:100]}")
    print()
    base = {(c["rule"], c["target"]) for c in ctrl}
    for name, fs in sorted(results.items()):
        if name == "clean":
            continue
        novel = [f for f in fs if (f["rule"], f["target"]) not in base]
        if not novel:
            continue
        print(f"{name}")
        for f in novel:
            print(f"    [{f['rule']:24}] {f['detail'][:150]}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(pathlib.Path(args[0] if args else "corpus/out").resolve())
