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
  X2 ink-centroid    the container claims to centre this mark and the rendered ink
                     is not where that claim puts it. Was PROVISIONAL and off by
                     default; both defects that held it back are fixed below.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.


WHAT CHANGED IN X2, AND THE THIRD DEFECT THE FIX EXPOSED
--------------------------------------------------------
The two recorded defects are fixed, and fixing them turned up a third that
changes what the arm is allowed to CLAIM.

(a) *Measure against the container, not the element's own box.* getBoundingClientRect
    returns the POST-transform box, so a translate moved box and ink together and
    the residual was invariant under the very compensation it should verify. The
    reference is now the centre of the PARENT that declares the centring -- which
    carries no transform of its own, and which is the box the DOM's claim is
    actually about. Measured on this corpus: the residual now moves by exactly the
    2.00px the compensation applies (clean -0.33px, variant -2.33px), where before
    the two pages were indistinguishable.

(b) *Mask to the painted shape.* The background was the square crop's modal colour,
    so on a 44px round button the corners -- page background outside the circle --
    counted as ink and swamped a 16px glyph. The footprint is now found by flooding
    inward from the crop border over the border's own colour; everything unreached
    is the painted shape. That alone was not enough: the shape's own ANTIALIASED RIM
    also differs from the fill and is also not ink, and it is a near-symmetric ring
    that halved the measured displacement (2.00px of translate read as 0.96px). The
    shape is eroded before the ink is taken. Ink then falls from 189px to 91px --
    the glyph, and nothing else.

(c) *The third defect: there is no absolute zero on the vertical axis.* With (a) and
    (b) fixed, the CONTROL -- correct by construction -- still reads +2.90px
    vertically, because where a glyph's ink sits inside its line box is a fact about
    the font's baseline and ascent, not about any centring claim. A threshold that
    called that a defect would fire on a clean page, and would do it differently on
    every machine. **X2 measures the horizontal axis only**, and says so.

    Nor does a residual alone separate right from wrong, because a mark that NEEDS
    optical compensation is one whose correct residual is non-zero. So the arm splits
    on what the DOM declared:

      - the child declares NO compensating transform and the ink is off-centre
        -> ASSERT. The DOM claims perfect centring and the pixels disagree; that is
        a cross-check finding in the strict sense.
      - the child DOES declare a transform and a residual survives it
        -> ABSTAIN (`xcheck-optical-centre-indeterminate`). Whether a declared
        compensation is the RIGHT amount is a taste judgement, and taste stays human.
        The abstention is the routable output; a number pretending to be a verdict
        is not.

X3 carried the same masking defect and was silently wrong for it. It sampled each
band's MODAL colour, and over a gradient no colour is modal -- the most common single
value in the left band turned out to be the text's own white ink, giving 1.00:1
against white text and a left/right delta too small to fire. It sampled a real
quantity that was not the backdrop. The backdrop is now the per-channel MEDIAN of the
pixels that are NOT close to the declared foreground colour: exact on a solid backdrop
(clean's hero caption reads 5.49:1, matching the authored blue-100-on-blue-700), and
stable across a gradient (6.01:1 left, 1.90:1 right).

Usage: python3 detect_xcheck.py <corpus-dir>
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image

# Tolerances are stated, not tuned. Each is well above sub-pixel rounding and
# well below what a person would call "off", so a finding means a real gap.
INK_MIN_FRAC = (
    0.002  # below this share of non-background pixels, the box paints nothing
)
# Ink centre vs the CONTAINER centre, horizontal axis. 1.5px sits above the
# control's measured 0.33px residual and below the variant's 2.33px, and above
# the ~1px of drift a different font or device-scale rounding can contribute.
CENTROID_TOL_PX = 1.5
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
INK_TOL = 40  # channel-sum distance from the fill at which a pixel is ink
FG_TOL = 120  # channel-sum distance from the declared colour that is still glyph
SHAPE_ERODE = 1  # px of the painted shape's own antialiased rim to discard
MAX_CENTRE_BOX = 128  # a "mark" a container centres; larger is a layout, not a mark
X2_DISABLED = "--no-x2" in sys.argv  # X2 is validated and on; this is the escape hatch


def flood_outside(region: np.ndarray, tol: int = INK_TOL) -> np.ndarray:
    """Pixels reachable from the crop border over the border's own colour.

    A rectangular crop of a rounded or circular element contains page background
    in its corners, and that background is not the element. Flooding inward from
    the border finds exactly it -- and, unlike a colour test, it will not delete
    a glyph that happens to match the page background, because a glyph in the
    middle of the shape is not reachable from the edge.
    """
    h, w = region.shape[:2]
    ring = np.concatenate([region[0], region[-1], region[:, 0], region[:, -1]])
    v, c = np.unique(ring, axis=0, return_counts=True)
    similar = np.abs(region.astype(np.int32) - v[c.argmax()].astype(np.int32)).sum(2)
    similar = similar <= tol
    out = np.zeros((h, w), bool)
    out[0, :] = out[-1, :] = True
    out[:, 0] = out[:, -1] = True
    out &= similar
    # Bounded flood: a 4-connected front cannot need more steps than the crop's
    # own half-perimeter, and the loop exits as soon as it stops growing.
    for _ in range(h + w):
        grow = out.copy()
        grow[1:, :] |= out[:-1, :]
        grow[:-1, :] |= out[1:, :]
        grow[:, 1:] |= out[:, :-1]
        grow[:, :-1] |= out[:, 1:]
        grow &= similar
        if np.array_equal(grow, out):
            break
        out = grow
    return out


def erode(mask: np.ndarray, n: int = 1) -> np.ndarray:
    """Shrink a mask by n px, 4-connected. Discards the shape's antialiased rim."""
    for _ in range(n):
        e = mask.copy()
        e[1:, :] &= mask[:-1, :]
        e[:-1, :] &= mask[1:, :]
        e[:, 1:] &= mask[:, :-1]
        e[:, :-1] &= mask[:, 1:]
        e[0, :] = e[-1, :] = False
        e[:, 0] = e[:, -1] = False
        mask = e
    return mask


def painted_ink(region: np.ndarray):
    """-> (shape mask, ink mask, fill colour) for a crop of one painted element.

    The shape is what the element actually paints; the fill is that shape's
    dominant colour; the ink is everything inside the shape that is not the fill.
    """
    shape = erode(~flood_outside(region), SHAPE_ERODE)
    if not shape.any():
        return None, None, None
    inside = region[shape]
    v, c = np.unique(inside, axis=0, return_counts=True)
    fill = v[c.argmax()]
    ink = shape & (
        np.abs(region.astype(np.int32) - fill.astype(np.int32)).sum(2) > INK_TOL
    )
    return shape, ink, fill


def backdrop_median(band: np.ndarray, fg) -> np.ndarray | None:
    """The colour behind the text in this band, with the text itself masked out.

    Median rather than mode: over a gradient no colour is modal, and the mode
    degenerates to whichever single value happens to repeat -- which, before this
    was fixed, was the glyph ink. The median of the non-ink pixels is the backdrop
    at the band's midpoint, and on a solid backdrop it is that backdrop exactly.
    """
    keep = np.abs(band.astype(np.int32) - np.asarray(fg[:3], dtype=np.int32)).sum(2)
    px = band[keep > FG_TOL]
    if len(px) < 8:
        return None
    return np.median(px, axis=0)


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


def crop(img: np.ndarray, rect: dict, scale: float):
    x0 = int(round(rect["x"] * scale))
    y0 = int(round(rect["y"] * scale))
    x1 = int(round(rect["right"] * scale))
    y1 = int(round(rect["bottom"] * scale))
    h, w = img.shape[:2]
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(w, x1), min(h, y1)
    if x1 - x0 < MIN_BOX or y1 - y0 < MIN_BOX:
        return None
    return img[y0:y1, x0:x1]


def centres_its_children(styles: dict) -> bool:
    """Does this element's own CSS claim it centres what is inside it?

    X2 only has a claim to cross-check where the DOM made one. A parent that
    never said it centres anything cannot be contradicted by an off-centre glyph.
    """
    disp = styles.get("display", "")
    if "flex" not in disp and "grid" not in disp:
        return False
    return "center" in styles.get("align-items", "") and "center" in styles.get(
        "justify-content", ""
    )


def check(snap: dict, png: pathlib.Path) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    out = []
    by_path = {e["path"]: e for e in snap["elements"]}

    def parent_of(el):
        head = el["path"].rsplit(" > ", 1)
        return by_path.get(head[0]) if len(head) > 1 else None

    def rep(rule, target, detail, severity="medium", **extra):
        out.append(
            {
                "rule": rule,
                "target": target,
                "detail": detail,
                "severity": severity,
                **extra,
            }
        )

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
        ink = dist > 40
        frac = float(ink.mean())

        # --- X1: the DOM says there is an element here; the pixels say nothing --
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

        # --- X2: ink is not where the CONTAINER's centring claim puts it -------
        # Only meaningful for a small self-contained mark whose parent actually
        # declares centring. A paragraph's ink is legitimately top-left-heavy
        # because text flows, and a parent that claims nothing contradicts nothing.
        parent = parent_of(el)
        pr = parent["rect"] if parent else None
        is_mark = (
            not X2_DISABLED
            and parent is not None
            and centres_its_children(parent["styles"])
            # The reference box must not itself be transformed, or it moves with
            # the ink and the residual goes invariant again -- defect (a), one
            # level up.
            and (parent["styles"].get("transform", "none") or "none") == "none"
            and 0 < pr["w"] <= MAX_CENTRE_BOX
            and 0 < pr["h"] <= MAX_CENTRE_BOX
            and len(el["text"]) <= 3
        )
        if is_mark:
            preg = crop(img, pr, scale)
            shape, pink, _fill = painted_ink(preg) if preg is not None else (None,) * 3
            if pink is not None and pink.any():
                ys, xs = np.nonzero(pink)
                # Centre of the container's box in crop coordinates. The rect is
                # fractional and the crop is integer, so carry the offset rather
                # than assuming the crop's own midpoint.
                px0 = max(0, int(round(pr["x"] * scale)))
                cx_box = ((pr["x"] + pr["right"]) / 2) * scale - px0
                dx = (xs.mean() - cx_box) / scale
                # Horizontal only. See defect (c) in the module docstring: the
                # vertical residual is a font-metric fact, not a centring claim.
                if abs(dx) > CENTROID_TOL_PX:
                    side = "left" if dx < 0 else "right"
                    declared = (el["styles"].get("transform", "none") or "none").strip()
                    if declared == "none":
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"{parent['path'].rsplit(' > ', 1)[-1]} centres this mark "
                            f"and declares no optical compensation, but its rendered "
                            f"ink sits {abs(dx):.1f}px {side} of that container's "
                            f"centre -- it will read as misaligned however correct "
                            f"the CSS is",
                            offset_px=round(float(dx), 2),
                        )
                    else:
                        rep(
                            "xcheck-optical-centre-indeterminate",
                            el["path"],
                            f"optical compensation is declared ({declared}) and "
                            f"{abs(dx):.1f}px of ink offset {side} survives it. "
                            f"Whether that residual is the intended compensation or "
                            f"an error is a judgement about this glyph's shape, not "
                            f"a measurement -- UNVERIFIED",
                            offset_px=round(float(dx), 2),
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text, taken separately from the
            # left and right thirds so a backdrop that VARIES across the run cannot
            # hide behind a single average. The text's own ink is masked out first:
            # sampling it instead of the backdrop is what made this arm silently
            # wrong (see the X3 note in the module docstring).
            w = region.shape[1]
            left = backdrop_median(region[:, : w // 3], fg)
            right = backdrop_median(region[:, -w // 3 :], fg)
            if left is None or right is None:
                continue
            cl = contrast(fg[:3], left)
            cr = contrast(fg[:3], right)
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
                )
    return out


def claim_key(f: dict) -> tuple:
    """Identity of a finding, spanning its claim rather than only its location.

    Two findings on the same element are the same finding only if they assert the
    same thing about it. `offset_px` is bucketed so sub-pixel jitter between two
    captures of the same page does not mint a new claim.
    """
    mag = f.get("offset_px")
    return (f["rule"], f["target"], None if mag is None else round(mag))


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

    def asserted(fs):
        return [f for f in fs if not f["rule"].endswith("-indeterminate")]

    ctrl = results.get("clean", [])
    ctrl_a = asserted(ctrl)
    print(
        f"CONTROL clean.html -> {len(ctrl_a)} asserted finding(s)"
        f"{'' if ctrl_a else '  (quiet)'}, "
        f"{len(ctrl) - len(ctrl_a)} abstention(s)"
    )
    for c in ctrl:
        print(f"    [{c['rule']}] {c['target']}: {c['detail'][:100]}")
    print()
    # The key spans the CLAIM, not just its location. Keying on (rule, target)
    # alone let a control finding swallow a real one on the same element -- the
    # `assertion-span-must-equal-its-subject` failure this corpus reproduced
    # live. The magnitude is part of what is being asserted, so it is part of
    # the key.
    base = {claim_key(c) for c in ctrl}
    for name, fs in sorted(results.items()):
        if name == "clean":
            continue
        novel = [f for f in fs if claim_key(f) not in base]
        if not novel:
            continue
        print(f"{name}")
        for f in novel:
            print(f"    [{f['rule']:36}] {f['detail'][:130]}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(pathlib.Path(args[0] if args else "corpus/out").resolve())
