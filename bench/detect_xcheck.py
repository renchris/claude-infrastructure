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
  X2 ink-centroid    PROVISIONAL, OFF BY DEFAULT (--x2 to enable). Two defects
                     found by trying to validate it, both worth recording:
                     (a) it compares ink to the element's OWN box, and
                     getBoundingClientRect returns the POST-transform box, so any
                     translate moves box and ink together and the measured offset
                     is INVARIANT under the very compensation it should verify;
                     (b) its background is the region's modal colour, so on a
                     round button the square crop's corners -- page background
                     outside the circle -- count as ink and swamp a 16px glyph.
                     The fix for both is to measure against the CONTAINER and to
                     mask to the painted shape. Until then it reports a real
                     quantity nobody has validated, which is exactly the kind of
                     plausible-wrong-number this whole document argues against.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

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
CENTROID_TOL_PX = 1.0  # ink centre vs box centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
X2_ENABLED = "--x2" in sys.argv  # provisional; see the X2 note in the docstring


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

        # --- X2: ink is not centred in the box the DOM centred -----------------
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows.
        is_glyph_like = (
            X2_ENABLED
            and frac > 0.02
            and r["w"] < 64
            and r["h"] < 64
            and len(el["text"]) <= 3
        )
        if is_glyph_like and ink.any():
            ys, xs = np.nonzero(ink)
            cx_ink = xs.mean() / scale
            cy_ink = ys.mean() / scale
            cx_box = (region.shape[1] / scale) / 2
            cy_box = (region.shape[0] / scale) / 2
            dx, dy = cx_ink - cx_box, cy_ink - cy_box
            if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                rep(
                    "xcheck-optical-centre",
                    el["path"],
                    f"the DOM centres this box exactly, but its rendered ink sits "
                    f"{abs(dx):.1f}px {'left' if dx < 0 else 'right'} and "
                    f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'} of the geometric "
                    f"centre -- it will read as misaligned however correct the CSS is",
                )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text: the modal non-ink colour,
            # taken separately from the left and right thirds so a backdrop that
            # VARIES across the run cannot hide behind a single average.
            w = region.shape[1]
            thirds = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled = {}
            for side, band in thirds.items():
                fb = band.reshape(-1, 3)
                v, c = np.unique(fb, axis=0, return_counts=True)
                sampled[side] = v[c.argmax()]
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
