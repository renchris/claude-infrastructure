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
  X2 ink-centroid    a mark's rendered ink is not centred in the shape its
                     container paints. Both defects that kept this arm disabled
                     are now fixed, and the fixes are the whole arm:
                     (a) it referenced the element's OWN box, and
                     getBoundingClientRect returns the POST-transform box, so a
                     translate moved box and ink together and the measurement was
                     INVARIANT under the very compensation it should verify. It
                     now references the CONTAINER's painted shape, which no
                     transform on the mark can move.
                     (b) its background was the crop's modal colour, so on a
                     round button the square crop's corners -- page background
                     outside the circle -- counted as ink and swamped a 16px
                     glyph. Ink is now taken only inside the container's painted
                     shape, eroded to drop the antialiased rim, and weighted by
                     how far each pixel has travelled from the container's own
                     background toward the mark's own colour. Both operands come
                     from the DOM; the pixels supply only where the ink landed.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

                     🚨 This arm was silently dead when the abstention router was
                     built against it, and it is the arm README.md credits with
                     removing contrast-over-a-gradient from the vision queue. It
                     sampled the backdrop as each band's MODAL colour, and on a
                     smooth gradient no backdrop colour repeats -- so the mode was
                     the text's own antialiased white (120 px against the busiest
                     gradient colour's 70). It compared white to white, got
                     1.00:1 vs 1.38:1, and reported nothing. The backdrop is now
                     the per-band MEDIAN over pixels that are NOT the known
                     foreground colour: the mode assumes a flat backdrop, which is
                     precisely the assumption this check exists to break.

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
# The vertical axis gets its own, wider tolerance because it is the only one that
# moves with capture DPR. Text baselines snap to whole DEVICE pixels, so the same
# glyph lands at a different fraction of a CSS pixel at 1x and 1.5x: measured on
# this corpus, dx agreed to 0.04 px across the two captures while dy moved 0.89 px.
# A single tolerance would either fire on the capture config or miss a real 1.5 px
# vertical offset, so the axes are stated separately rather than averaged.
CENTROID_TOL_PX_Y = 1.5
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# X2's subject and container are both small painted marks -- an icon button and
# its glyph. Above this, "the shape the mark sits in" stops being a shape and
# becomes the page, and a centroid over it means nothing.
MARK_MAX_PX = 96
SHAPE_TOL = 60  # sum|dRGB| within which a pixel counts as the container's fill
RIM_ERODE_PX = 2  # drop the antialiased edge of the container's own shape
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


def erode(mask: np.ndarray, r: int) -> np.ndarray:
    """Shrink a mask by r px. Nine-line disc erosion, no SciPy dependency."""
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            out &= np.roll(np.roll(mask, dy, 0), dx, 1)
    return out


def fill_holes(mask: np.ndarray) -> np.ndarray:
    """Close a painted outline into a solid region.

    The glyph punches a hole in the container's fill, so the fill alone is a ring
    and its centroid is only accidentally the shape's centre. Spanning each row
    and each column between their outermost set pixels and intersecting the two
    closes any convex shape -- a rect, a pill, a circle -- which is every shape a
    border-radius can produce.
    """
    rows = np.zeros_like(mask)
    cols = np.zeros_like(mask)
    for i, row in enumerate(mask):
        nz = np.nonzero(row)[0]
        if len(nz):
            rows[i, nz[0] : nz[-1] + 1] = True
    for j in range(mask.shape[1]):
        nz = np.nonzero(mask[:, j])[0]
        if len(nz):
            cols[nz[0] : nz[-1] + 1, j] = True
    return rows & cols


def ink_weight(region: np.ndarray, bg, fg) -> np.ndarray:
    """Per-pixel ink mass along the container-background -> mark-colour axis.

    Both endpoints are read from the DOM, so this asks the pixels only one
    question: how far along that axis did this pixel land. A hard threshold would
    make the centroid jump with the antialiasing, and the whole claim is about
    fractions of a pixel -- so the partial coverage of an edge pixel is carried as
    partial mass. Anything off the axis (a third colour bleeding in) is dropped
    rather than projected onto it.
    """
    axis = np.asarray(fg, dtype=float) - np.asarray(bg, dtype=float)
    denom = float(axis @ axis)
    if denom < 1.0:  # mark and container share a colour; nothing to measure
        return np.zeros(region.shape[:2])
    t = ((region - bg) @ axis) / denom
    off_axis = np.linalg.norm(region - (bg + t[..., None] * axis), axis=2)
    return np.clip(t, 0.0, 1.0) * (off_axis < 30)


def centroid(weight: np.ndarray):
    mass = float(weight.sum())
    if mass <= 0:
        return None
    ys, xs = np.mgrid[0 : weight.shape[0], 0 : weight.shape[1]]
    return float((xs * weight).sum() / mass), float((ys * weight).sum() / mass), mass


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
    by_path = {e["path"]: e for e in snap["elements"]}

    def rep(rule, target, detail, severity="medium"):
        out.append(
            {"rule": rule, "target": target, "detail": detail, "severity": severity}
        )

    def mark_container(el):
        """The nearest ancestor that PAINTS a shape this mark sits inside.

        Referencing the mark's own box is the defect that kept X2 disabled --
        getBoundingClientRect is post-transform, so the box follows the ink and
        the offset is invariant under the compensation being verified. An
        ancestor carrying its own opaque fill is not moved by a transform on the
        mark, which is what makes it a reference at all.
        """
        path = el["path"]
        while " > " in path:
            path = path.rsplit(" > ", 1)[0]
            anc = by_path.get(path)
            if anc is None:
                continue
            bg = parse_rgb(anc["styles"].get("background-color", ""))
            if not bg or bg[3] < 0.99:
                continue
            r = anc["rect"]
            if r["w"] > MARK_MAX_PX or r["h"] > MARK_MAX_PX:
                return None  # a page-sized ancestor is not a shape
            return anc, bg[:3]
        return None

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

        # --- X2: the mark's ink is not centred in the shape its container paints
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows.
        is_glyph_like = (
            X2_ENABLED
            and r["w"] < MARK_MAX_PX
            and r["h"] < MARK_MAX_PX
            and 1 <= len(el["text"]) <= 3
        )
        held = mark_container(el) if is_glyph_like else None
        if held:
            anc, cbg = held
            shell = crop(img, anc["rect"], scale)
            fg = parse_rgb(el["styles"].get("color", ""))
            if shell is not None and fg:
                painted = fill_holes(np.abs(shell - np.asarray(cbg)).sum(2) < SHAPE_TOL)
                core = erode(painted, max(1, round(RIM_ERODE_PX * scale)))
                shape_c = centroid(painted.astype(float))
                ink_c = centroid(ink_weight(shell, cbg, fg[:3]) * core)
                # Under ~20 px of ink mass the centroid is one antialiased edge
                # away from meaningless, and the arm abstains rather than guess.
                if shape_c and ink_c and ink_c[2] >= 20 * scale * scale:
                    dx = (ink_c[0] - shape_c[0]) / scale
                    dy = (ink_c[1] - shape_c[1]) / scale
                    if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX_Y:
                        parts = []
                        if abs(dx) > CENTROID_TOL_PX:
                            parts.append(f"{abs(dx):.1f}px {'left' if dx < 0 else 'right'}")
                        if abs(dy) > CENTROID_TOL_PX_Y:
                            parts.append(f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'}")
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"every box-model number here is symmetric, but the ink "
                            f"this mark actually paints sits {' and '.join(parts)} of "
                            f"the centre of the shape {anc['path'].rsplit(' > ', 1)[-1]} "
                            f"paints around it -- it will read as misaligned however "
                            f"correct the CSS is",
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text, separately in the left
            # and right thirds so a backdrop that VARIES across the run cannot
            # hide behind a single average.
            #
            # The MEDIAN over pixels that are not the known foreground colour --
            # never the mode. A mode assumes some backdrop colour repeats, which
            # is exactly false on the gradient this check exists for: measured
            # here, the busiest gradient colour appeared 70 times against the
            # text's own antialiased white at 120, so the mode returned the ink
            # and the check compared white to white and reported nothing.
            w = region.shape[1]
            bands = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled = {}
            for side, band in bands.items():
                backdrop = band[np.abs(band - np.asarray(fg[:3])).sum(2) > 90]
                if len(backdrop) < 20:
                    break  # the run is nearly all ink; no backdrop to sample
                sampled[side] = np.median(backdrop, axis=0)
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


def main(corpus: pathlib.Path, suffix: str = "", out_name: str = "") -> None:
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    results = {}
    for f in sorted(snaps.glob("*.json")):
        png = shots / f"{f.stem}{suffix}.png"
        if not png.exists():
            continue
        results[f.stem] = check(json.loads(f.read_text()), png)
    if not results:
        sys.exit(f"no captures matching shots/*{suffix}.png under {shots}")
    (corpus / (out_name or f"findings_xcheck{suffix}.json")).write_text(
        json.dumps(results, indent=1)
    )

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
    # A pixel check that only ever ran at one capture scale has not been tested,
    # it has been demonstrated. --shot-suffix reruns the identical rules against
    # the other capture of the same frame; X2's per-axis tolerances exist because
    # that comparison found dy moving with DPR and dx not.
    suffix = next(
        (a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--shot-suffix=")), ""
    )
    main(pathlib.Path(args[0] if args else "corpus/out").resolve(), suffix)
