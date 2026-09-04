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
  X2 ink-centroid    a mark's rendered ink does not sit where the container it is
                     centred in says it does. ON BY DEFAULT since 2026-09-04
                     (--no-x2 to disable); it shipped provisional and off because
                     trying to validate it found two defects in it, and both are
                     now fixed:
                     (a) it compared ink to the element's OWN box, and
                     getBoundingClientRect returns the POST-transform box, so any
                     translate moved box and ink together and the measured offset
                     was INVARIANT under the very compensation it should verify.
                     It now measures against the CONTAINER's painted shape, whose
                     box no child transform can move.
                     (b) its background was the region's modal colour, so on a
                     round button the square crop's corners -- page background
                     outside the circle -- counted as ink and swamped a 16px
                     glyph. The crop is now MASKED to the container's painted
                     shape, built analytically from the rect and border-radius
                     the DOM already reports and eroded past the antialiased rim,
                     so nothing outside the paint can vote.
                     Measured after the fix on this corpus: 0 findings on the
                     clean control, 1 on the optical-centering variant, naming
                     the glyph. Before the fix it was exactly inverted -- 2 on the
                     control, 0 on the defect.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

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
CENTROID_TOL_PX = 1.0  # ink centroid vs the container's painted centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
BANDS = 6  # samples across a text run; two cannot tell a ramp from a stripe
BAND_SPREAD_MAX = 0.15  # interquartile luminance inside one band before the
# backdrop counts as patterned rather than varying
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
INK_DELTA = 40  # channel-sum distance from the backdrop that counts as ink
# X2 tolerances. A mark is small, painted on a solid fill, and covers a minority
# of it; anything outside these bounds is layout, not a mark, and its centroid
# carries no optical claim.
MASK_INSET_PX = 1.5  # erode past the antialiased rim of the painted shape
X2_MIN_SIDE = 12.0
X2_MAX_SIDE = 96.0
X2_INK_MIN = 0.005
X2_INK_MAX = 0.40
X2_ENABLED = "--no-x2" not in sys.argv  # see the X2 note in the docstring


def rel_lum(rgb) -> float:
    def ch(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = rgb[:3]
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def rel_lum_arr(rgb: np.ndarray) -> np.ndarray:
    """Relative luminance over an array of pixels, for per-band statistics."""
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return lin @ np.array([0.2126, 0.7152, 0.0722])


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


def px(v: str) -> float:
    try:
        return float(str(v).replace("px", "").strip())
    except (ValueError, AttributeError):
        return 0.0


def radius_px(styles: dict, w: float, h: float) -> float:
    """The corner radius in CSS px, resolving a percentage against the box."""
    v = (styles.get("border-radius") or "0px").split()[0].strip()
    if v.endswith("%"):
        try:
            return float(v[:-1]) / 100.0 * min(w, h)
        except ValueError:
            return 0.0
    return px(v)


def shape_mask(h: int, w: int, radius: float, inset: float):
    """Boolean mask of a rounded rectangle, inset by `inset` pixels.

    This is the painted shape the browser actually filled, reconstructed from
    two numbers the DOM already reports exactly -- not guessed from the pixels.
    The inset erodes the antialiased rim, which otherwise reads as a ring of ink
    around every mark and dilutes the very centroid the check is measuring.
    """
    x0 = y0 = inset
    x1, y1 = w - inset, h - inset
    if x1 - x0 < 2 or y1 - y0 < 2:
        return None
    r = max(0.0, min(radius - inset, (x1 - x0) / 2, (y1 - y0) / 2))
    ys = np.arange(h)[:, None] + 0.5
    xs = np.arange(w)[None, :] + 0.5
    inside = (xs >= x0) & (xs <= x1) & (ys >= y0) & (ys <= y1)
    if r > 0:
        # Distance from the inner rect that the corner arcs are struck about.
        qx = np.maximum(np.maximum(x0 + r - xs, xs - (x1 - r)), 0.0)
        qy = np.maximum(np.maximum(y0 + r - ys, ys - (y1 - r)), 0.0)
        inside = inside & ((qx * qx + qy * qy) <= r * r)
    return inside


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

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text, taken separately from the
            # left and right thirds so a backdrop that VARIES across the run cannot
            # hide behind a single average.
            #
            # The text's own ink is excluded first, and the survivors are taken at
            # the MEDIAN rather than the mode. The mode is unsafe here and the
            # corpus proves it: over a smooth gradient no backdrop colour repeats
            # -- each column is its own colour -- so the most common colour in the
            # band is the ANTIALIASED TEXT, and the check silently compares the
            # text against itself. Measured on this corpus before the fix: the
            # left band's modal colour came back rgb(255,255,255) on white text,
            # for a contrast of 1.00:1, and the gradient defect went unreported.
            fgv = np.array(fg[:3], dtype=np.int32)
            w = region.shape[1]
            if w < BANDS * MIN_BOX:
                continue
            edges = np.linspace(0, w, BANDS + 1).astype(int)
            ratios, spreads, ok = [], [], True
            for i in range(BANDS):
                fb = region[:, edges[i] : edges[i + 1]].reshape(-1, 3).astype(np.int32)
                not_ink = np.abs(fb - fgv).sum(axis=1) > INK_DELTA
                # Mostly ink means there is no backdrop to speak of in this band;
                # an honest nothing beats a number drawn from four pixels.
                if not_ink.mean() < 0.2:
                    ok = False
                    break
                back = fb[not_ink]
                ratios.append(contrast(fg[:3], np.median(back, axis=0)))
                lum = rel_lum_arr(back)
                spreads.append(float(np.percentile(lum, 75) - np.percentile(lum, 25)))
            if not ok:
                continue
            swing = max(ratios) - min(ratios)
            if swing <= CONTRAST_DELTA:
                continue

            # A two-number left/right summary is only licensed when the backdrop
            # actually varies MONOTONICALLY across the run. A repeating pattern
            # produces a swing just as large, and reporting its endpoints as
            # "left edge / right edge" invents a story: the value alternates
            # every stripe, so neither endpoint describes what a reader meets.
            # Measured on this corpus: the linear-gradient page's bands have an
            # interquartile luminance spread of ~0.06 and read monotonically; the
            # repeating-stripe page's bands spread ~0.67 and read 1.5, 10.4, 1.6,
            # 9.8 ... -- same swing, different kind of fact.
            patterned = max(spreads) > BAND_SPREAD_MAX
            noise = swing * 0.1
            up = all(b >= a - noise for a, b in zip(ratios, ratios[1:]))
            down = all(b <= a + noise for a, b in zip(ratios, ratios[1:]))
            if patterned or not (up or down):
                rep(
                    "xcheck-backdrop-indeterminate",
                    el["path"],
                    f"contrast under this text swings between {min(ratios):.2f}:1 "
                    f"and {max(ratios):.2f}:1 across {BANDS} samples and does not "
                    f"vary monotonically -- the backdrop is patterned, so neither a "
                    f"single ratio nor a two-number summary describes it. Whether "
                    f"this text is legible is a question about what a reader sees, "
                    f"and it is UNVERIFIED",
                    "high",
                )
                continue
            cl, cr = ratios[0], ratios[-1]
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

    if X2_ENABLED:
        out.extend(check_x2(snap, img, scale))
    return out


def check_x2(snap: dict, img: np.ndarray, scale: float) -> list[dict]:
    """X2 -- a mark's ink does not sit where its CONTAINER centres it.

    Both halves of this are deliberate and both are the fix for a defect that
    shipped in the first version.

    The reference is the CONTAINER, never the mark's own box. `getBoundingClientRect`
    returns the post-transform box, so a `translate` on the mark moves box and ink
    together and any offset measured against that box is invariant under the exact
    compensation the check exists to verify. The container is upstream of the
    child's transform, so its centre is a fixed point the mark can be wrong about.

    The crop is MASKED to the container's painted shape, rebuilt analytically from
    its rect and border-radius. Without it, the square crop of a round button
    includes the page background at the four corners, which differs from the fill
    and therefore counts as ink -- hundreds of pixels of it, against a 16px glyph.
    """
    by_path = {e["path"]: e for e in snap["elements"]}
    kids: dict[str, list[dict]] = {}
    for e in snap["elements"]:
        parent = e["path"].rsplit(" > ", 1)[0] if " > " in e["path"] else None
        if parent in by_path:
            kids.setdefault(parent, []).append(e)

    out = []
    for cont in snap["elements"]:
        r = cont["rect"]
        if not (X2_MIN_SIDE <= r["w"] <= X2_MAX_SIDE):
            continue
        if not (X2_MIN_SIDE <= r["h"] <= X2_MAX_SIDE):
            continue
        # A container only makes a centring claim if it paints a solid ground for
        # the mark to sit on. Without one there is no shape to mask to.
        fill = parse_rgb(cont["styles"].get("background-color", ""))
        if not fill or fill[3] < 0.99:
            continue
        # The mark. The claim being checked is about INK, so a drawn mark (a
        # border triangle, an inline SVG) counts exactly as much as a glyph does;
        # the text test is only here to exclude flowing copy, whose ink is
        # legitimately top-left-heavy and makes no optical claim at all.
        desc = [
            e for e in snap["elements"] if e["path"].startswith(cont["path"] + " > ")
        ]
        text_len = len(cont["text"]) + sum(len(e["text"]) for e in desc)
        if len(desc) > 1 or text_len > 3:
            continue
        mark = desc[0] if desc else cont
        mark_path = mark["path"]
        mark_label = mark["text"] or mark_path.rsplit(" > ", 1)[-1]

        region = crop(img, r, scale)
        if region is None:
            continue
        mask = shape_mask(
            region.shape[0],
            region.shape[1],
            radius_px(cont["styles"], r["w"], r["h"]) * scale,
            MASK_INSET_PX * scale,
        )
        if mask is None or mask.sum() < 32:
            continue

        inside = region[mask].astype(np.int32)
        vals, counts = np.unique(inside, axis=0, return_counts=True)
        ground = vals[counts.argmax()]
        ink = mask & (np.abs(region.astype(np.int32) - ground).sum(axis=2) > INK_DELTA)
        frac = ink.sum() / mask.sum()
        if not (X2_INK_MIN <= frac <= X2_INK_MAX):
            continue

        ys, xs = np.nonzero(ink)
        my, mx = np.nonzero(mask)
        # The reference is the painted shape's own centroid, not the crop's
        # midpoint: a container clipped by the image edge still has an honest
        # centre, and a symmetric shape puts the two in the same place anyway.
        dx = (xs.mean() - mx.mean()) / scale
        dy = (ys.mean() - my.mean()) / scale
        if abs(dx) <= CENTROID_TOL_PX and abs(dy) <= CENTROID_TOL_PX:
            continue
        out.append(
            {
                "rule": "xcheck-optical-centre",
                "target": mark_path,
                "detail": (
                    f"{mark_label!r} is centred by {cont['path'].rsplit(' > ', 1)[-1]}"
                    f", but its rendered ink sits {abs(dx):.1f}px "
                    f"{'left' if dx < 0 else 'right'} and {abs(dy):.1f}px "
                    f"{'up' if dy < 0 else 'down'} of that container's painted "
                    f"centre -- it will read as misaligned however symmetric the "
                    f"box model is"
                ),
                "severity": "medium",
            }
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
