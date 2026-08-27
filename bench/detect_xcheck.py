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
  X2 ink-centroid    the mark inside a container that CLAIMS to centre it does not
                     sit at that container's centre. Validated 2026-08-27 and ON by
                     default (`--no-x2` to disable); it shipped provisional and off
                     because trying to validate it found two defects, and both are
                     now fixed:
                     (a) it compared ink to the element's OWN box, and
                     getBoundingClientRect returns the POST-transform box, so any
                     translate moved box and ink together and the measured offset
                     was INVARIANT under the very compensation it should verify.
                     FIXED: the reference frame is now the CONTAINER's box, which no
                     transform on the child can move.
                     (b) its background was the region's modal colour, so on a
                     round button the square crop's corners -- page background
                     outside the circle -- counted as ink and swamped a 16px glyph.
                     FIXED: pixels are classified against two colours the DOM
                     already knows -- the container's own background-color and the
                     backdrop resolved behind it -- and the crop is masked to the
                     painted shape by a per-row fill, so the corners are excluded
                     before a centroid is taken.
                     Where either operand is not a solid colour the check ABSTAINS
                     (`xcheck-centre-indeterminate`) rather than guessing one.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.
                     Its backdrop sample carried defect (b) too, and silently: it
                     took the MODAL colour of each band, ink included. On a smooth
                     gradient no backdrop colour has a plurality but every
                     antialiased glyph pixel shares one exact value, so the INK won
                     the mode and the check compared the text to itself -- 1.00:1
                     against 1.38:1, delta 0.38, below tolerance, silent. Measured
                     on this corpus 2026-08-27, where it had reported the gradient
                     correctly on a Mac: the rule was passing for a reason that had
                     nothing to do with the page. FIXED the same way -- exclude
                     pixels near the known foreground colour, then take the MEDIAN
                     of what remains, which is a backdrop sample by construction
                     instead of by luck.

Usage: python3 detect_xcheck.py <corpus-dir>
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image

# The backdrop resolver is IMPORTED rather than reimplemented. Two ancestor-walks
# that disagree about what colour sits behind an element would put the two
# detectors in different worlds while both looked correct, which is the exact
# failure this bench keeps finding in other people's tooling.
from detect_dom import Page as DomPage, hexof, px

# Tolerances are stated, not tuned. Each is well above sub-pixel rounding and
# well below what a person would call "off", so a finding means a real gap.
INK_MIN_FRAC = (
    0.002  # below this share of non-background pixels, the box paints nothing
)
CENTROID_TOL_PX = 1.0  # ink centre vs the CONTAINER's centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# Channel-sum distances (0..765). SHAPE_TOL says "this pixel is not the backdrop";
# INK_TOL says "this pixel is not the container's fill". Both sit far above 8-bit
# rounding and sRGB conversion noise and far below any colour pair a designer
# would call the same.
SHAPE_TOL = 24
INK_TOL = 40
FG_TOL = 60  # a pixel this close to the text colour is ink, not backdrop
AA_PX = 2  # width of the antialiased ring a rounded edge paints, in CSS px
MIN_INK_PX = 24  # below this there is no centroid worth the name
X2_ENABLED = "--no-x2" not in sys.argv  # validated 2026-08-27; see the docstring
CENTRING = {"flex", "inline-flex", "grid", "inline-grid"}


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


def dist_to(region: np.ndarray, rgb) -> np.ndarray:
    """Per-pixel channel-sum distance to one colour. 0..765, integer, exact."""
    ref = np.asarray(rgb[:3], dtype=np.int32)
    return np.abs(region.astype(np.int32) - ref).sum(axis=2)


def painted_shape(region: np.ndarray, outside) -> np.ndarray:
    """Mask of the pixels belonging to the element's painted shape.

    A square crop of a round button contains page background in its corners. Those
    corners are not the element, and counting them as ink is what made the old X2
    report a 44px button's geometry as a 16px glyph's offset.

    Anything that differs from the resolved backdrop is painted; then each row is
    filled between its first and last painted pixel. The fill is what makes this
    correct rather than merely close: a white glyph on a blue disc on a white page
    is IDENTICAL to the outside colour, so a colour test alone would punch the
    glyph back out of the mask -- the very pixels the check exists to weigh. Row
    fill recovers any interior for a shape that is convex per row, which covers
    every border-radius rectangle, circle and pill. It would over-claim on a
    C-shape, and nothing in this bench is one.
    """
    painted = dist_to(region, outside) > SHAPE_TOL
    h, w = painted.shape
    any_row = painted.any(axis=1)
    first = np.where(any_row, painted.argmax(axis=1), w)
    last = np.where(any_row, w - 1 - painted[:, ::-1].argmax(axis=1), -1)
    cols = np.arange(w)[None, :]
    return (cols >= first[:, None]) & (cols <= last[:, None])


def erode(mask: np.ndarray, k: int) -> np.ndarray:
    """Shrink a mask by k pixels on every side (4-connected, k passes).

    This is not a refinement, it is the difference between measuring a mark and
    measuring the container it sits in. A border-radius edge is antialiased, so a
    ring of blend pixels around the shape is neither the fill nor the backdrop and
    lands in "ink" under any colour test. Measured on this corpus: a 44px round
    button contributed ~400 ring pixels against ~120 for the glyph inside it, so
    the centroid described the disc and moved 0.3px when the glyph moved 2px --
    the same swamping as the old modal-colour version, one layer further in, and
    it would have read as a working check. Eroding past the edge also drops any
    border, which is chrome rather than the centred mark.
    """
    m = mask
    for _ in range(max(0, k)):
        m = (
            m
            & np.roll(m, 1, 0)
            & np.roll(m, -1, 0)
            & np.roll(m, 1, 1)
            & np.roll(m, -1, 1)
        )
        m[0, :] = m[-1, :] = False
        m[:, 0] = m[:, -1] = False
    return m


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


def centre_check(pg: DomPage, img: np.ndarray, scale: float, el: dict) -> list[dict]:
    """X2 -- does the mark sit where its container says it does?

    The question is asked about the CONTAINER, and that is the whole fix for
    defect (a). `getBoundingClientRect` returns the post-transform box, so a
    `translate` on the mark carries its own box along with its ink and the offset
    between them never changes. The container's box does not move, so an offset
    measured against it is exactly the quantity a designer means by "off centre",
    and it responds to the compensation the way the compensation intends.

    The check is only asked where the DOM makes the claim -- a flex or grid
    container centring on both axes, holding exactly one child. That keeps it from
    fishing: a finding here is always a contradiction of something the stylesheet
    asserts, never an opinion about where a mark ought to sit. Sole-child rather
    than short-text is what makes it useful outside this corpus, where an icon
    button holds an `<svg>` and carries no text at all.
    """
    parent = pg.parent_of(el)
    if parent is None:
        return []
    ps = parent["styles"]
    claims_centre = (
        ps.get("display", "").strip() in CENTRING
        and "center" in ps.get("align-items", "")
        and "center" in ps.get("justify-content", "")
    )
    if not claims_centre or len(pg.children_of(parent)) != 1:
        return []
    pr = parent["rect"]
    if pr["w"] < MIN_BOX or pr["h"] < MIN_BOX or pr["w"] > 160 or pr["h"] > 160:
        return []

    # Both operands come from the DOM, never from the image. Guessing either one
    # from the pixels is what the modal-colour version did, and it is why a round
    # button's corners could outvote its glyph.
    fill = parse_rgb(ps.get("background-color", ""))
    # The backdrop BEHIND the container, so the walk starts above it. `backdrop`
    # answers "what colour is under this text", which includes the element's own
    # background -- ask it about the container and it returns the container's own
    # fill, `outside` becomes `fill`, and every pixel that is not the fill counts
    # as painted: the white page corners and the white glyph alike, with the
    # corners winning on area. Measured here before the fix.
    above = pg.parent_of(parent)
    outside, why = pg.backdrop(above) if above else ((255, 255, 255, 1.0), "ok")
    if fill is None or fill[3] < 0.99 or outside is None:
        return [
            {
                "rule": "xcheck-centre-indeterminate",
                "target": el["path"],
                "detail": (
                    f"{parent['path']} claims to centre this mark, but the centroid "
                    f"cannot be measured: "
                    + (
                        f"{why}"
                        if outside is None
                        else "the container's own background is not a solid colour"
                    )
                    + ". Whether the mark reads as centred is UNVERIFIED"
                ),
                "severity": "medium",
            }
        ]

    region = crop(img, pr, scale)
    if region is None:
        return []
    border = max(
        px(ps.get(f"border-{s}-width", "")) for s in ("top", "right", "bottom", "left")
    )
    shape = erode(painted_shape(region, outside), int(round((border + AA_PX) * scale)))
    # Ink is what the container is NOT: its fill masked to its own painted shape.
    weight = np.where(shape, dist_to(region, fill), 0)
    weight = np.where(weight > INK_TOL, weight, 0).astype(np.float64)
    total = weight.sum()
    if total <= 0 or (weight > 0).sum() < MIN_INK_PX:
        return [
            {
                "rule": "xcheck-centre-indeterminate",
                "target": el["path"],
                "detail": (
                    f"{parent['path']} claims to centre this mark, but inside its "
                    f"painted shape fewer than {MIN_INK_PX} pixels differ from the "
                    f"container's own fill -- there is no ink to take a centroid of. "
                    f"Whether the mark reads as centred is UNVERIFIED"
                ),
                "severity": "medium",
            }
        ]

    # Intensity-weighted, so an antialiased edge contributes in proportion to how
    # much of it was painted. A binary threshold quantises the centroid to whole
    # pixels and would put the tolerance below its own resolution.
    #
    # Both centres are then resolved in PAGE coordinates. The crop origin is an
    # integer and the container's box is fractional, so comparing a crop-relative
    # centroid against `w/2` charges the rounding of the origin to the mark. It is
    # up to half a pixel against a one-pixel tolerance, it moves with the page's
    # layout rather than with the element, and it showed up here as the same glyph
    # reading 0.5px up on one page and 1.4px down on another.
    ys, xs = np.nonzero(weight)
    w = weight[ys, xs]
    x0 = max(0, int(round(pr["x"] * scale)))
    y0 = max(0, int(round(pr["y"] * scale)))
    cx = (x0 + float(((xs + 0.5) * w).sum() / total)) / scale
    cy = (y0 + float(((ys + 0.5) * w).sum() / total)) / scale
    dx = cx - (pr["x"] + pr["w"] / 2)
    dy = cy - (pr["y"] + pr["h"] / 2)
    if abs(dx) <= CENTROID_TOL_PX and abs(dy) <= CENTROID_TOL_PX:
        return []
    return [
        {
            "rule": "xcheck-optical-centre",
            "target": el["path"],
            "detail": (
                f"{parent['path']} centres this mark on both axes, but its rendered "
                f"ink sits {abs(dx):.1f}px {'left' if dx < 0 else 'right'} and "
                f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'} of that container's "
                f"centre -- it will read as misaligned however correct the CSS is"
            ),
            "severity": "medium",
        }
    ]


def check(snap: dict, png: pathlib.Path) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    pg = DomPage(snap)
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

        # --- X2: the ink is not centred in the container that centres it -------
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows.
        if X2_ENABLED and len(el["text"]) <= 3 and r["w"] < 64 and r["h"] < 64:
            out.extend(centre_check(pg, img, scale, el))

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text, separately in the left and
            # right thirds so a backdrop that VARIES across the run cannot hide
            # behind a single average.
            #
            # Exclude the ink FIRST, by the one colour we know exactly -- the
            # cascade's `color`. Taking a modal colour over the whole band, as this
            # did until 2026-08-27, samples whatever value happens to repeat most,
            # and on a smooth gradient that is the text: every backdrop pixel is
            # unique, every antialiased glyph pixel is the same. The rule then
            # compared the text to itself and read 1.00:1 -- a pass, silently, on
            # the one page it was written for.
            #
            # Then take the MEDIAN of what remains rather than the mode. A gradient
            # has no modal colour to find; its median is the middle of the band,
            # which is a fair statement of the backdrop over that third.
            w = region.shape[1]
            thirds = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled = {}
            for side, band in thirds.items():
                fb = band.reshape(-1, 3)
                backdrop = fb[dist_to(band, fg).reshape(-1) > FG_TOL]
                if len(backdrop) < max(16, 0.2 * len(fb)):
                    sampled = None  # mostly ink: no backdrop to sample honestly
                    break
                sampled[side] = np.median(backdrop, axis=0)
            if sampled is None:
                rep(
                    "xcheck-contrast-unsampleable",
                    el["path"],
                    f"the rendered backdrop behind this text cannot be sampled: fewer "
                    f"than a fifth of the pixels in its box differ from its own "
                    f"{hexof(fg)} text colour. The ratio here is UNVERIFIED",
                )
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
