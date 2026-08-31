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
  X2 ink-centroid    the ink a mark actually paints is not centred in the shape
                     its container actually paints. ON BY DEFAULT since
                     2026-08-31; see "The X2 repair" below for what changed and
                     why the old arm had to ship disabled.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

--------------------------------------------------------------------------------
The X2 repair (2026-08-31)
--------------------------------------------------------------------------------
The arm shipped disabled because validating it found two defects, and both were
the plausible-wrong-number this whole corpus exists to catch:

  (a) it compared ink to the element's OWN box, and getBoundingClientRect
      returns the POST-transform box -- so `transform: translate(2px,2px)`, the
      optical compensation the check exists to verify, moves box and ink
      together and the measured offset is INVARIANT under it. Measured on this
      corpus: clean.html reports 2.1px left on span.glyph and the variant that
      DELETES the compensation reports the same, so the arm scored 2 control
      false positives and 0 discrimination.
  (b) its background was the crop's modal colour, so on a 44px round button the
      square crop's corners -- page background outside the circle -- counted as
      ink and swamped a 16px glyph.

Both are fixed by one construction, and it is the architecture's own rule
(the DOM supplies geometry, the pixels supply what the DOM cannot):

  reference  = the centroid of the CONTAINER's painted shape, rasterised
               analytically from the container's own rect and border-radius.
               Not segmented, not guessed -- a rounded rectangle is exact, and
               the page already told us its four numbers. This fixes (a),
               because the container does not move when the mark inside it is
               translated, and it fixes (b), because everything outside the
               rounded rect is excluded before a single pixel is weighed.
  measurement = the coverage-weighted centroid of the mark's ink INSIDE that
               shape. Coverage is the pixel's projection onto the fg-bg axis,
               so an antialiased glyph edge contributes its true partial mass
               instead of being thresholded to 0 or 1 -- which is what makes a
               2px claim about a 16px glyph honest.

Preconditions, each of which ABSTAINS rather than guessing: the container must
declare that it centres its children, it must resolve to an opaque background,
and the fg-bg axis must be long enough to separate ink from backdrop.

X3 carried defect (b) too, and it was silent. Its docstring said it sampled the
"modal non-ink colour" and the code took the plain modal colour of the band. On
this corpus's gradient page the white caption glyphs OUTVOTE any single gradient
column in the left third, so the sampled left "backdrop" came back #FFFFFF, the
contrast came back 1.00:1 against 1.38:1 on the right, the 1.5-point delta never
fired, and the one arm the spec calls validated MISSED the one defect it exists
to catch. Whether it fires is a function of font rasterisation, which is why it
passed on the authoring Mac and fails on Linux. X3 now excludes ink (plus its
one-pixel antialias halo) before taking the modal backdrop, and abstains for a
band with too little backdrop left to sample.

Usage: python3 detect_xcheck.py <corpus-dir> [--no-x2]
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
CENTROID_TOL_PX = 1.0  # ink centroid vs the container's painted-shape centroid
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# X3 needs to know which pixels are the text so it can refuse to sample them as
# backdrop. L1 distance, because it is the same units the ink threshold above
# already uses and a channel-wise miss is what matters here, not a Euclidean one.
INK_NEAR = 60
# If a band is this close to being all ink, there is not enough backdrop left to
# call a modal colour on. That is an abstention, not a number.
BACKDROP_MIN_FRAC = 0.25
# The fg-bg axis has to be long enough that a coverage projection means anything.
# Below this the mark and its container are near-isoluminant and the centroid is
# noise wearing three decimal places.
MIN_AXIS_L2 = 60.0
X2_ENABLED = "--no-x2" not in sys.argv  # repaired 2026-08-31; see the docstring


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


def px(v) -> float:
    try:
        return float(str(v).replace("px", "").strip())
    except (ValueError, AttributeError):
        return 0.0


def shape_mask(rect: dict, radius: float, x0: int, y0: int, shape, scale: float):
    """Rasterise the container's painted shape from the DOM's own numbers.

    A rounded rectangle is analytic, so there is nothing to segment and nothing
    to hallucinate -- and everything outside it (the page background showing
    through a round button's square crop) is excluded before any pixel is
    weighed. The crop origin is an integer raster row/column while the rect is
    fractional CSS, so the test runs at each raster pixel's CENTRE mapped back
    into CSS: a 0.33px origin bias is a sixth of the tolerance this arm asserts
    against, which is exactly the size of error that makes a 2px claim a lie.
    """
    h, w = shape
    xs = (np.arange(w) + 0.5) / scale + x0 / scale
    ys = (np.arange(h) + 0.5) / scale + y0 / scale
    gx, gy = np.meshgrid(xs, ys)
    left, top = rect["x"], rect["y"]
    right, bottom = rect["right"], rect["bottom"]
    inside = (gx >= left) & (gx <= right) & (gy >= top) & (gy <= bottom)
    r = max(0.0, min(radius, rect["w"] / 2, rect["h"] / 2))
    if r > 0:
        for cx, cy, qx, qy in (
            (left + r, top + r, gx < left + r, gy < top + r),
            (right - r, top + r, gx > right - r, gy < top + r),
            (left + r, bottom - r, gx < left + r, gy > bottom - r),
            (right - r, bottom - r, gx > right - r, gy > bottom - r),
        ):
            corner = qx & qy
            outside = ((gx - cx) ** 2 + (gy - cy) ** 2) > r * r
            inside &= ~(corner & outside)
    return inside


def coverage(region: np.ndarray, fg, bg) -> np.ndarray:
    """Per-pixel ink coverage: the projection onto the fg-bg axis, clipped to 0..1.

    A hard threshold throws away the antialiased edge, and an antialiased edge is
    most of a 16px glyph's boundary. Weighing partial coverage is what lets a
    centroid resolve below the pixel it is measured in.
    """
    axis = np.asarray(fg, dtype=np.float64) - np.asarray(bg, dtype=np.float64)
    denom = float(axis @ axis)
    if denom <= 0:
        return np.zeros(region.shape[:2])
    proj = (
        (region.astype(np.float64) - np.asarray(bg, dtype=np.float64)) @ axis
    ) / denom
    return np.clip(proj, 0.0, 1.0)


def dilate(mask: np.ndarray) -> np.ndarray:
    """One-pixel dilation. Text has an antialias halo and the halo is not backdrop."""
    out = mask.copy()
    out[1:, :] |= mask[:-1, :]
    out[:-1, :] |= mask[1:, :]
    out[:, 1:] |= mask[:, :-1]
    out[:, :-1] |= mask[:, 1:]
    return out


def erode(mask: np.ndarray, n: int = 1) -> np.ndarray:
    """Peel n pixels off the mask's border.

    The container's own edge is antialiased -- a rounded button's rim pixels are
    a blend of its fill and whatever is behind it -- so a rim pixel projects onto
    the fg-bg axis as partial ink even though it is not the mark. Measured on
    this corpus: 23.2 of 104.0 coverage units, 22%, sat on the rim of a 44px
    circle and pulled every offset toward the centre, reporting 1.6px where the
    geometry says exactly 2.0. That is defect (b) re-entering through the edge of
    the very mask that fixed it, so the mask domain is eroded and the analytic
    (un-eroded) shape stays the reference -- eroding a symmetric shape does not
    move its centroid, and the mark is nowhere near the rim.
    """
    for _ in range(n):
        out = mask.copy()
        out[1:, :] &= mask[:-1, :]
        out[:-1, :] &= mask[1:, :]
        out[:, 1:] &= mask[:, :-1]
        out[:, :-1] &= mask[:, 1:]
        mask = out
    return mask


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
    # The origin travels with the region: an analytic mask has to be registered
    # against the same raster grid the pixels came off, not against the rect.
    return img[y0:y1, x0:x1], x0, y0


def optical_centre(el, container, img: np.ndarray, scale: float):
    """X2, repaired. Yields zero or one (rule, target, detail) tuple.

    Every precondition below ABSTAINS -- returns nothing -- rather than falling
    back to a weaker reference. A centroid measured against the wrong frame is
    the failure this arm shipped disabled for; producing no number is strictly
    better than producing that one.
    """
    if container is None:
        return
    # The claim is "the DOM says it centres this and the pixels disagree". If the
    # container never claimed to centre anything, there is no disagreement to report.
    cs = container["styles"]
    centring = "center" in (cs.get("align-items") or "") and "center" in (
        cs.get("justify-content") or ""
    )
    if not centring:
        return
    cbg = parse_rgb(cs.get("background-color", ""))
    if not cbg or cbg[3] < 0.99:
        return  # no opaque backdrop => no fg-bg axis => no coverage weighting
    # A mark's paint colour is `color` when it is typed and `background-color`
    # when it is drawn. Both are DOM facts; picking between them is not a guess.
    fg = parse_rgb(el["styles"].get("color", "")) if el["text"] else None
    if fg is None:
        fg = parse_rgb(el["styles"].get("background-color", ""))
    if not fg or fg[3] < 0.99:
        return
    axis = np.asarray(fg[:3], float) - np.asarray(cbg[:3], float)
    if float(np.sqrt(axis @ axis)) < MIN_AXIS_L2:
        return  # mark and container are near-isoluminant; the centroid is noise

    cr = container["rect"]
    if cr["w"] < MIN_BOX or cr["h"] < MIN_BOX or cr["w"] > 64 or cr["h"] > 64:
        return  # a self-contained mark button, not a layout region
    cropped = crop(img, cr, scale)
    if cropped is None:
        return
    region, x0, y0 = cropped

    # (b) mask to the painted shape: everything outside the rounded rect is page
    # background showing through the square crop, and it is not this element's ink.
    shape = shape_mask(cr, px(cs.get("border-radius")), x0, y0, region.shape[:2], scale)
    if not shape.any():
        return
    domain = erode(shape, max(1, int(round(scale))))
    if not domain.any():
        return
    cov = coverage(region, fg[:3], cbg[:3]) * domain
    total = float(cov.sum())
    if total <= 0:
        return

    ys, xs = np.mgrid[0 : region.shape[0], 0 : region.shape[1]]
    # (a) the reference is the CONTAINER's painted shape, not the mark's own box.
    # The container does not move when the mark inside it is translated, so the
    # optical compensation is finally something the measurement can see.
    ref_x = float((xs * shape).sum() / shape.sum())
    ref_y = float((ys * shape).sum() / shape.sum())
    ink_x = float((xs * cov).sum() / total)
    ink_y = float((ys * cov).sum() / total)
    dx = (ink_x - ref_x) / scale
    dy = (ink_y - ref_y) / scale
    if abs(dx) <= CENTROID_TOL_PX and abs(dy) <= CENTROID_TOL_PX:
        return
    yield (
        "xcheck-optical-centre",
        el["path"],
        f"{container['path'].rsplit(' > ', 1)[-1]} declares it centres its "
        f"children, but this mark's rendered ink sits "
        f"{abs(dx):.1f}px {'left' if dx < 0 else 'right'} and "
        f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'} of the centre of the shape "
        f"that container actually paints -- it will read as misaligned however "
        f"correct the CSS is",
        "medium",
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

    def rep(rule, target, detail, severity="medium"):
        out.append(
            {"rule": rule, "target": target, "detail": detail, "severity": severity}
        )

    for el in snap["elements"]:
        r = el["rect"]
        if r["w"] < MIN_BOX or r["h"] < MIN_BOX:
            continue
        cropped = crop(img, r, scale)
        if cropped is None:
            continue
        region, rx0, ry0 = cropped

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

        # --- X2: the mark's ink is not centred in the shape its container paints
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows. A
        # mark is defined by GEOMETRY plus a paint colour, not by carrying text:
        # an icon is as often drawn (clip-path, border triangle, inline SVG fill)
        # as typed, and gating on `len(text) <= 3` silently exempts every drawn
        # one from the only arm that can see it.
        is_mark_like = (
            X2_ENABLED
            and frac > 0.02
            and r["w"] < 64
            and r["h"] < 64
            and len(el["text"]) <= 3
        )
        if is_mark_like:
            for finding in optical_centre(el, parent_of(el), img, scale):
                rep(*finding)

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text: the modal NON-INK colour,
            # taken separately from the left and right thirds so a backdrop that
            # VARIES across the run cannot hide behind a single average.
            #
            # Excluding the ink is not a refinement, it is the whole check. Take
            # the plain modal colour and the text's own glyphs outvote any single
            # gradient column in a band -- so the "backdrop" comes back as the
            # text colour, contrast comes back 1.00:1, and the arm reports
            # agreement precisely where the disagreement is. Whether that happens
            # is a function of font rasterisation, so it passes on one machine and
            # fails on another with no code change. The halo is dilated in because
            # an antialiased edge is a blend, not backdrop.
            text_px = dilate(
                np.abs(region.astype(np.int32) - np.asarray(fg[:3], np.int32)).sum(
                    axis=2
                )
                <= INK_NEAR
            )
            w = region.shape[1]
            bands = {
                "left": (region[:, : w // 3], ~text_px[:, : w // 3]),
                "right": (region[:, -w // 3 :], ~text_px[:, -w // 3 :]),
            }
            sampled = {}
            for side, (band, keep) in bands.items():
                if keep.mean() < BACKDROP_MIN_FRAC:
                    break  # too little backdrop left to name one; abstain
                v, c = np.unique(band[keep], axis=0, return_counts=True)
                sampled[side] = v[c.argmax()]
            if len(sampled) < 2:
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
