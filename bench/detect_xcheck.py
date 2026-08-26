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
  X2 ink-centroid    ON BY DEFAULT since 2026-08-26 (--no-x2 to disable). It
                     shipped disabled because trying to validate it found two
                     defects; both are now fixed, and the fix is what earned the
                     arm its default:
                     (a) it compared ink to the element's OWN box, and
                     getBoundingClientRect returns the POST-transform box, so any
                     translate moved box and ink together and the measured offset
                     was INVARIANT under the very compensation it should verify.
                     It now measures against the CONTAINER's painted shape, which
                     no transform on the mark can move.
                     (b) its background was the region's modal colour, so on a
                     round button the square crop's corners -- page background
                     outside the circle -- counted as ink and swamped a 16px
                     glyph. It now masks to the painted shape, recovered from the
                     container's OWN background colour by a per-row/per-column
                     span fill, and the page background outside the disc is
                     excluded by construction.
                     Measured on this corpus after the fix: 0 findings on the
                     control (was 2), 1 on optical-centering (was 2, i.e. the arm
                     had zero discrimination -- it said the same thing about every
                     page including the clean one).
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.
                     Its backdrop estimator was the third defect of the same
                     family, and it was invisible on the machine it was written
                     on. It took the MODAL colour of each third -- but under a
                     gradient no backdrop colour repeats, while the text ink is
                     one exact constant, so the mode can BE the foreground. It
                     then contrasts the text against itself, gets 1.00:1 at both
                     ends, and reports nothing. Measured: on macOS/Helvetica the
                     backdrop won the mode and the arm fired; on Linux/DejaVu the
                     ink won and the same arm went silent on the same page. A
                     detector whose verdict turns on a font fallback is not
                     validated. It now excludes ink first and takes the MEDIAN of
                     what is left, which is the statistic a varying backdrop
                     actually has.
                     Its VERDICT was wrong in the other direction: it asserted
                     "the <side> end is the one that fails a reader" whenever the
                     two ends differed by more than the tolerance, without ever
                     comparing either to the requirement. A backdrop running 9:1
                     to 5:1 varies by more than the tolerance and passes at both
                     ends. It now names the requirement and says which of the two
                     answers it is giving -- a failure, or a spread with nothing
                     to fix. Both still settle the abstention, because both are
                     the two real numbers the abstention said could not exist.

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
CENTROID_TOL_PX = 1.0  # ink centre vs the painted shape's centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# Channel-sum distance under which a pixel counts as "that colour". 40 is the
# same threshold X1 uses for ink; it sits above JPEG-free antialiasing noise and
# below any two colours a designer would call different.
COLOUR_NEAR = 40
# WCAG AA, so that X3 can say whether a spread actually FAILS rather than merely
# existing. Same numbers as detect_dom.py, deliberately duplicated: a comparator
# that imported its requirement from the detector it is checking would agree with
# it by construction.
CONTRAST_MIN = 4.5
CONTRAST_MIN_LARGE = 3.0
X2_ENABLED = "--no-x2" not in sys.argv  # see the X2 note in the docstring


def px(v: str) -> float:
    try:
        return float(str(v).replace("px", "").strip())
    except (ValueError, AttributeError):
        return 0.0


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


def near(region: np.ndarray, rgb, tol: int = COLOUR_NEAR) -> np.ndarray:
    """Boolean mask of pixels within `tol` channel-sum distance of `rgb`."""
    return (
        np.abs(region.astype(np.int32) - np.asarray(rgb[:3], dtype=np.int32)).sum(
            axis=2
        )
        <= tol
    )


def span_fill(mask: np.ndarray) -> np.ndarray:
    """Fill the holes in a convex mask, without a morphology dependency.

    The painted shape we need is the container's background -- a disc, a pill, a
    rounded rect -- with the glyph punched out of it. Taking the intersection of
    each row's and each column's occupied span closes that hole exactly for a
    convex shape, and a mark small enough for this arm to look at is convex. It
    is deliberately NOT a flood fill: a flood fill from the border would leak
    through any antialiased seam, and this cannot.
    """
    rows = np.zeros_like(mask)
    cols = np.zeros_like(mask)
    idx_x = np.arange(mask.shape[1])
    idx_y = np.arange(mask.shape[0])
    for y in np.nonzero(mask.any(axis=1))[0]:
        xs = idx_x[mask[y]]
        rows[y, xs.min() : xs.max() + 1] = True
    for x in np.nonzero(mask.any(axis=0))[0]:
        ys = idx_y[mask[:, x]]
        cols[ys.min() : ys.max() + 1, x] = True
    return rows & cols


def check(snap: dict, png: pathlib.Path) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    by_path = {e["path"]: e for e in snap["elements"]}
    out = []

    def container_of(el):
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

        # --- X2: ink is not centred in the shape the DOM centred it in ---------
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows.
        #
        # Both operands come from the CONTAINER, never from the mark's own box.
        # That is the whole fix for defect (a): getBoundingClientRect returns the
        # post-transform box, so a `translate` on the mark moves box and ink
        # together and any offset measured inside that box is invariant under the
        # compensation it is supposed to verify. The container's painted shape is
        # the one frame the mark's transform cannot move.
        # A mark, not a paragraph: small, and carrying at most a glyph's worth of
        # text. Zero text is admitted because an icon drawn by CSS or SVG is the
        # same subject and paints the same way -- the old text-length floor was a
        # proxy for "is this a glyph" that excluded every non-font icon.
        is_glyph_like = (
            X2_ENABLED and r["w"] < 64 and r["h"] < 64 and len(el["text"]) <= 3
        )
        cont = container_of(el) if is_glyph_like else None
        if cont is not None and cont["rect"]["w"] < 96 and cont["rect"]["h"] < 96:
            fg = parse_rgb(el["styles"].get("color", ""))
            cbg = parse_rgb(cont["styles"].get("background-color", ""))
            shell = crop(img, cont["rect"], scale)
            # No opaque container fill means no painted shape to mask to, and
            # guessing one is how this arm produced its first wrong number. Say
            # nothing rather than measure against the crop's corners.
            if shell is not None and fg and cbg and cbg[3] > 0.99:
                bgmask = near(shell, cbg)
                if bgmask.mean() >= 0.05:
                    shape = span_fill(bgmask)
                    # Ink is what sits INSIDE the painted shape and is not the
                    # fill. Defect (b) was that page background outside the disc
                    # counted as ink -- and on a white glyph over a white page it
                    # is not merely noise, it is the same colour. Nothing outside
                    # `shape` can be counted now, whatever colour it is.
                    ink_m = shape & ~bgmask & near(shell, fg, COLOUR_NEAR * 2)
                    if ink_m.sum() >= 8:
                        ys, xs = np.nonzero(ink_m)
                        sy, sx = np.nonzero(shape)
                        dx = (xs.mean() - sx.mean()) / scale
                        dy = (ys.mean() - sy.mean()) / scale
                        if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                            rep(
                                "xcheck-optical-centre",
                                el["path"],
                                f"the DOM centres this mark exactly inside "
                                f"{cont['path'].rsplit(' > ', 1)[-1]}, but its rendered "
                                f"ink sits {abs(dx):.1f}px "
                                f"{'left' if dx < 0 else 'right'} and {abs(dy):.1f}px "
                                f"{'up' if dy < 0 else 'down'} of that shape's own "
                                f"centre -- it will read as misaligned however correct "
                                f"the CSS is",
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
            # Exclude the text's own ink FIRST, then take the median of what is
            # left. The mode cannot do this job: under a gradient no backdrop
            # colour repeats, while antialiased text is one exact constant, so
            # the most frequent colour in the band can be the foreground itself
            # -- which contrasts against itself at 1.00:1 and makes the arm
            # silent on precisely the page it exists for. Measured: that is what
            # it did here under DejaVu, and not under Helvetica. The median is
            # the statistic a varying backdrop actually has.
            w = region.shape[1]
            thirds = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled = {}
            for side, band in thirds.items():
                keep = ~near(band, fg, COLOUR_NEAR * 2)
                # Too little backdrop left to describe: abstain rather than
                # report a ratio computed off five pixels.
                if keep.mean() < 0.2:
                    sampled = {}
                    break
                sampled[side] = np.median(band[keep].reshape(-1, 3), axis=0)
            if not sampled:
                continue
            cl = contrast(fg[:3], sampled["left"])
            cr = contrast(fg[:3], sampled["right"])
            if abs(cl - cr) > CONTRAST_DELTA:
                # Spread is not failure, and this arm used to say it was: it
                # asserted "the <side> end is the one that fails a reader"
                # whenever the two ends differed, without ever comparing either
                # to the requirement. A backdrop running 9:1 to 5:1 varies by
                # more than the tolerance and passes at both ends. Saying it
                # fails is a false positive with a real number attached to it,
                # which is the most persuasive kind.
                size = px(el["styles"].get("font-size", ""))
                weight = el["styles"].get("font-weight", "400")
                large = size >= 24 or (
                    size >= 18.66 and weight in ("700", "bold", "800", "900")
                )
                need = CONTRAST_MIN_LARGE if large else CONTRAST_MIN
                lo_side = "left" if cl < cr else "right"
                lo = min(cl, cr)
                if lo < need:
                    rep(
                        "xcheck-contrast-varies",
                        el["path"],
                        f"contrast is not one number across this text: {cl:.2f}:1 at "
                        f"the left edge and {cr:.2f}:1 at the right. Any single "
                        f"computed value is a fiction, and the {lo_side} end fails "
                        f"the {need}:1 requirement at {lo:.2f}:1",
                        "high",
                    )
                else:
                    rep(
                        "xcheck-contrast-varies",
                        el["path"],
                        f"contrast is not one number across this text: {cl:.2f}:1 at "
                        f"the left edge and {cr:.2f}:1 at the right. No single "
                        f"computed value describes it, but both ends clear the "
                        f"{need}:1 requirement -- the abstention is answered and "
                        f"there is nothing here to fix",
                        "low",
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
