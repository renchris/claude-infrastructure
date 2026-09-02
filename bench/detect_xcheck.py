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
  X2 ink-centroid    the ink inside a container that CLAIMS to centre its content
                     does not sit at the centre of the shape that container
                     actually paints.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

X2 SHIPPED 2026-09-02, after both of the defects it was quarantined for were
reproduced on this corpus and fixed. `--x2` is now a no-op kept so an old
invocation does not break. What it used to do, and what changed:

  (a) It compared ink to the element's OWN box, and getBoundingClientRect returns
      the POST-transform box, so the `translate` that IS the optical compensation
      moved box and ink together and the measurement was invariant under the very
      thing it was meant to verify. Measured: 0/1 on `optical-centering`. The
      subject is now the CONTAINER -- the element whose computed styles claim to
      centre their content -- which does not move when its child is nudged, so
      adding or removing the compensation changes the number.
  (b) Its background was the crop's modal colour, so on a 44px circle the square
      crop's corners -- page background outside the radius -- scored as ink and
      swamped a 16px glyph. Measured: 2 false positives on the clean control, on a
      page where the compensation is present and correct. The reference is now the
      PAINTED SHAPE, masked by comparing against the backdrop sampled in a ring
      just outside the box, and eroded so the shape's own antialiased rim is not
      counted as ink either.

X3 ALSO REPAIRED in the same pass, and this one was a silent false NEGATIVE,
which is the worse kind. Its comment said it sampled "the modal non-ink colour"
and its code sampled the modal colour, full stop. On a gradient the ink wins that
vote outright -- every backdrop column is a slightly different colour while the
glyph pixels are all one colour -- so the left third of the gradient caption
returned #FFFFFF, the text's OWN colour, for 1.00:1 against white text. The check
the entire gradient case rests on reported nothing at all, on the page built to
exercise it. See `_backdrop_of`.

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
CENTROID_TOL_PX = 1.0  # ink centre vs painted-shape centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
INK_TOL = 40  # channel-sum distance at which a pixel stops being background

# --- X2 --------------------------------------------------------------------
# A container big enough to hold a paragraph is not making a centring claim this
# check can falsify: its ink is legitimately top-left-heavy because text flows.
X2_MAX_BOX = 64.0  # CSS px, longest side
X2_SHAPE_TOL = 24  # channel-sum distance from the OUTSIDE colour -> painted
X2_MIN_SHAPE_FRAC = 0.5  # below this the element paints no distinguishable shape
X2_MIN_INK_PX = 12  # device px of ink; fewer has no stable centroid
X2_MAX_INK_FRAC = 0.6  # above this it is a fill, not a mark to be centred
X2_ERODE_CSS_PX = 1.5  # rim eaten before ink is counted, in CSS px
CENTRING_DISPLAYS = {"flex", "inline-flex", "grid", "inline-grid"}


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


def _modal(flat: np.ndarray) -> np.ndarray:
    v, c = np.unique(flat, axis=0, return_counts=True)
    return v[c.argmax()]


def _dist_to(region: np.ndarray, colour) -> np.ndarray:
    """Per-pixel channel-sum distance from one colour. Int32 to avoid int16 wrap."""
    return np.abs(region.astype(np.int32) - np.asarray(colour, dtype=np.int32)).sum(
        axis=2
    )


def _erode(mask: np.ndarray, k: int) -> np.ndarray:
    """Binary erosion by a (2k+1)-square, as k successive 3x3 passes.

    scipy is not a dependency and does not need to be: a 3x3 erosion is nine
    shifted ANDs, and k of them compose to the larger square. This exists so the
    antialiased rim of a painted shape -- which differs from the fill and would
    otherwise be scored as ink -- is eaten before the centroid is taken. On a
    44px circle that rim is ~138 perimeter pixels against a 16px glyph's ~90, so
    without it the rim IS the measurement.
    """
    m = mask
    for _ in range(max(0, k)):
        p = np.pad(m, 1, constant_values=False)
        m = (
            p[:-2, :-2]
            & p[:-2, 1:-1]
            & p[:-2, 2:]
            & p[1:-1, :-2]
            & p[1:-1, 1:-1]
            & p[1:-1, 2:]
            & p[2:, :-2]
            & p[2:, 1:-1]
            & p[2:, 2:]
        )
    return m


def _span_fill(mask: np.ndarray) -> np.ndarray:
    """Close the holes a painted shape's own ink punches in it.

    The shape mask is built by difference from the colour OUTSIDE the box, and
    the commonest mark in UI is white ink on a coloured control sitting on a
    white page: those glyph pixels are at distance ZERO from the outside colour,
    so the glyph punches a hole in the exact shape it sits inside. Measured on
    this corpus: the play button's 485 white pixels all fell outside the mask and
    the check found 0 ink on both the compensated and uncompensated pages -- a
    silent abstention that looked like a pass.

    A pixel is inside if it lies within its row's painted span AND its column's.
    That is the shapes UI actually paints -- rect, rounded rect, pill, circle --
    and the AND cannot leak past the mask's own extent the way a union would on
    a concave shape.
    """
    if not mask.any():
        return mask

    def rows(m: np.ndarray) -> np.ndarray:
        any_ = m.any(1)
        first = np.argmax(m, axis=1)
        last = m.shape[1] - 1 - np.argmax(m[:, ::-1], axis=1)
        idx = np.arange(m.shape[1])[None, :]
        span = (idx >= first[:, None]) & (idx <= last[:, None])
        return span & any_[:, None]

    return rows(mask) & rows(mask.T).T


def _painted_shape(img: np.ndarray, rect: dict, scale: float):
    """Isolate what an element actually PAINTS, and what it paints ON.

    Returns (inner, shape, ink, fill) or None when the element paints nothing
    the page background does not already supply -- in which case there is no
    shape to centre anything in and the check abstains rather than guessing.

    The backdrop operand is sampled from a one-pixel ring just OUTSIDE the box,
    never from inside it. That is the whole repair to defect (b): a square crop
    of a circle contains page background in its corners, and any inside-the-box
    estimator has to decide whether those corners are background or ink. Taking
    the colour from outside removes the decision -- corners match the outside
    colour, so they are masked out by construction.
    """
    pad = max(1, int(round(2 * scale)))
    x0 = int(round(rect["x"] * scale))
    y0 = int(round(rect["y"] * scale))
    x1 = int(round(rect["right"] * scale))
    y1 = int(round(rect["bottom"] * scale))
    h, w = img.shape[:2]
    px0, py0 = max(0, x0 - pad), max(0, y0 - pad)
    px1, py1 = min(w, x1 + pad), min(h, y1 + pad)
    if x1 - x0 < MIN_BOX or y1 - y0 < MIN_BOX:
        return None
    padded = img[py0:py1, px0:px1]
    # The ring is whatever padding survived clipping at the image edge; if a side
    # was clipped away the remaining sides still describe the same backdrop.
    ring = np.concatenate(
        [
            padded[0].reshape(-1, 3),
            padded[-1].reshape(-1, 3),
            padded[:, 0].reshape(-1, 3),
            padded[:, -1].reshape(-1, 3),
        ]
    )
    outside = _modal(ring)

    inner = img[max(0, y0) : min(h, y1), max(0, x0) : min(w, x1)]
    if inner.size == 0:
        return None
    shape = _span_fill(_dist_to(inner, outside) > X2_SHAPE_TOL)
    if shape.mean() < X2_MIN_SHAPE_FRAC:
        return None
    fill = _modal(inner[shape])
    core = _erode(shape, max(1, int(round(X2_ERODE_CSS_PX * scale))))
    ink = core & (_dist_to(inner, fill) > INK_TOL)
    return inner, shape, ink, fill


def _centroid(mask: np.ndarray):
    ys, xs = np.nonzero(mask)
    return float(xs.mean()), float(ys.mean())


def _backdrop_of(band: np.ndarray, fg):
    """The colour BEHIND the text in this band, or None if the band is all ink.

    Drop the pixels that ARE the ink (and its antialiased skirt), then take the
    MEDIAN of what is left. Both halves are load-bearing. Dropping the ink is the
    repair to X3's silent false negative -- the first version voted on every
    pixel and the glyphs won. The median rather than a mode is what makes the
    remainder mean something on a gradient: no backdrop value repeats often
    enough there for a mode to be anything but noise, while the median of a
    monotone ramp is the ramp's value at the middle of the band, which is exactly
    the number this check wants to report for that third of the run.
    """
    flat = band.reshape(-1, 3).astype(np.int32)
    d = np.abs(flat - np.asarray(fg[:3], dtype=np.int32)).sum(axis=1)
    keep = flat[d > INK_TOL]
    if len(keep) < 8:
        return None
    return np.median(keep, axis=0)


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


def check(snap: dict, png: pathlib.Path) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    out = []

    def rep(rule, target, detail, severity="medium"):
        out.append(
            {"rule": rule, "target": target, "detail": detail, "severity": severity}
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

        # --- X2: ink is not centred in the SHAPE the DOM claims to centre ------
        # The subject is the CONTAINER, not the mark: an element whose computed
        # styles assert that its content is centred. That assertion is the claim
        # this check falsifies, and reading it off `display`/`align-items`/
        # `justify-content` is what keeps this a cross-check rather than a
        # detector -- it fires only where the DOM has said something the pixels
        # can contradict. It also fixes defect (a): the container's box does not
        # move when its child is translated, so the compensation is now visible
        # in the measurement instead of cancelling out of it.
        # The opaque-fill requirement is an ABSTENTION, not an oversight. Without
        # a background the DOM itself calls solid there is no painted shape to be
        # the centring reference, only the mark's own bounding box -- which is the
        # degenerate case defect (a) was, measuring the ink against itself. An
        # icon button drawn with a border and a transparent fill is therefore not
        # checked, and saying so is worth more than a number with nothing behind it.
        own_bg = parse_rgb(el["styles"].get("background-color", ""))
        centres = (
            el["styles"].get("display", "") in CENTRING_DISPLAYS
            and "center" in el["styles"].get("align-items", "")
            and "center" in el["styles"].get("justify-content", "")
            and own_bg is not None
            and own_bg[3] > 0.99
        )
        if centres and r["w"] <= X2_MAX_BOX and r["h"] <= X2_MAX_BOX:
            painted = _painted_shape(img, r, scale)
            if painted is not None:
                _, shape, ink2, _fill = painted
                n_ink = int(ink2.sum())
                if (
                    n_ink >= X2_MIN_INK_PX
                    and n_ink <= X2_MAX_INK_FRAC * float(shape.sum())
                    and shape.any()
                ):
                    ix, iy = _centroid(ink2)
                    sx, sy = _centroid(shape)
                    dx, dy = (ix - sx) / scale, (iy - sy) / scale
                    if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"this element's computed styles centre its content, and "
                            f"they do: every box-model number is symmetric. But the "
                            f"ink it paints sits {abs(dx):.1f}px "
                            f"{'left' if dx < 0 else 'right'} and {abs(dy):.1f}px "
                            f"{'up' if dy < 0 else 'down'} of the centre of the shape "
                            f"this element actually paints -- it will read as "
                            f"misaligned however correct the CSS is",
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text, taken separately from the
            # left and right thirds so a backdrop that VARIES across the run cannot
            # hide behind a single average. `_backdrop_of` excludes the ink before
            # it estimates; the version that did not returned the TEXT's colour as
            # its own backdrop and reported 1.00:1.
            w = region.shape[1]
            thirds = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled = {s: _backdrop_of(b, fg) for s, b in thirds.items()}
            if sampled["left"] is None or sampled["right"] is None:
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
