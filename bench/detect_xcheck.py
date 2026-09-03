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
  X2 ink-centroid    the ink of a small mark does not sit where the DOM centred
                     its box.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

WHERE THE BACKGROUND COMES FROM, because getting this wrong cost all three checks
--------------------------------------------------------------------------------
The first version of every check here derived "background" the same way: take the
crop's MODAL colour and call everything else ink. That is wrong in two directions
and it produced a bug in each check.

A modal colour is undefined on a gradient. A smooth horizontal gradient across a
1168px element is ~1168 distinct colours at 16 occurrences each, while the text
drawn on top is ONE colour repeated thousands of times -- so the mode of a
gradient band is the TEXT, and every downstream number inverts. Measured on this
corpus's own gradient page: X3 sampled `rgb(255,255,255)` as the backdrop of white
text, computed 1.00:1 against 1.38:1 across the run, and stayed silent on the one
defect it was written to catch. The committed macOS run fired only because
platform antialiasing happened to tip the mode the other way. A check that passes
on one machine's font rasteriser and fails on another's was never measuring what
it claimed to.

A modal colour also cannot tell ink from what lies OUTSIDE the painted shape. On
the round glyph button, the square crop's corners are page background -- and the
page background is #FFFFFF, the same colour as the glyph -- so the corners
outweighed a 16px glyph and swamped the centroid.

So neither the mode nor "everything that is not the mode" is used anywhere now.
The DOM already states the foreground colour exactly, for free, with no
estimation: `styles.color` for text, `background-color` for a painted container.
Ink is what matches the declared foreground; the backdrop is the MEDIAN of what
does not. Median is defined on a gradient, mode is not, and both operands come
from a substrate that cannot hallucinate.

WHAT X2 MEASURES, AND THE ONE AXIS IT REFUSES TO JUDGE
------------------------------------------------------
X2 shipped disabled (`--x2`) because validating it found two defects, both fixed
here and both worth keeping on the record:

  (a) It compared ink to the element's OWN box, and getBoundingClientRect returns
      the POST-transform box, so a `translate` moved box and ink together and the
      measured offset was INVARIANT under the very compensation it existed to
      verify. Fixed by measuring against the CONTAINER, which does not carry the
      child's transform. The fix is falsifiable and was falsified: on this corpus
      the horizontal offset now reads +0.16px with the compensation and -1.84px
      with it removed, a 2.0px swing that is exactly the `translate(2px, 2px)`
      the defect variant deletes. The old code read the same number for both.

  (b) Its background was the crop's modal colour, so the corners counted as ink.
      Fixed by masking to the painted shape: the container's own fill colour gives
      the shape minus its holes, a row-wise span fill closes the holes, and the
      mark is what sits inside the filled shape without matching the fill. The
      reference centre is then the centroid of the painted shape itself, so a
      circle inscribed in a square crop is measured against the circle.

X2 returns a verdict on the HORIZONTAL axis only, and this is a statement about
what is knowable rather than a tuned threshold. Horizontally, the inline box is
centred by the container and a glyph's advance is symmetric about it, so residual
ink asymmetry can only come from the glyph's own shape -- which is precisely what
optical centring compensates, and precisely what no DOM API reports. Vertically,
ink sits where the BASELINE puts it, and the browser positions the baseline from
the typeface's ascent and descent; the correct vertical offset is therefore a
property of the font, not of the page, and a single page contains no reference
that could supply it. Measured here: the same glyph reads dy=+3.37px on the clean
control under Liberation Sans, because the corpus's 2px compensation constant was
calibrated against Helvetica's rasterisation of U+25B6 and does not transfer. A
verdict on that axis would have been a false positive on the control on this
machine and a pass on the author's -- so the vertical offset is reported as an
observation carrying no verdict, and the finding says so.

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
# X1's floor is per CHARACTER, not per unit area. Measured across the clean
# control's 31 text runs, ink-per-character spans 4.2 to 80.7 px and is stable
# whatever the box is; the same runs' ink AREA FRACTION spans 0.11% to 29.2%, a
# 265x range that tracks how much padding the box carries and nothing else. The
# area form put a table cell holding a single legible digit -- 0.11% of a
# 192x41px cell -- below a 0.2% floor and reported it as unpainted, twice, on the
# control. One solid pixel per character is four times below the least-inked real
# text on the page, and genuine invisibility reads at or near zero.
INK_MIN_PER_CHAR = 1.0
CENTROID_TOL_PX = 1.0  # ink centre vs painted-shape centre, horizontal only
CONTRAST_DELTA = 1.5  # ratio points between the two ends of one text run
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# Manhattan distance in 8-bit RGB at which a pixel stops counting as "this
# colour". Wide enough to absorb greyscale antialiasing on a glyph edge, narrow
# enough that #FFFFFF and #DBEAFE never collapse together.
COLOR_TOL = 60
# A mark small enough that ink asymmetry inside it reads as a centring error
# rather than as text flow. A paragraph's ink is legitimately top-left-heavy.
GLYPH_MAX_PX = 64
GLYPH_MAX_CHARS = 3


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


def hexof(rgb) -> str:
    return "#%02X%02X%02X" % tuple(int(round(float(c))) for c in rgb[:3])


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


def matches(region: np.ndarray, rgb, tol: int = COLOR_TOL) -> np.ndarray:
    """Pixels within `tol` (Manhattan, 8-bit RGB) of a colour the DOM declared.

    This is the only place a pixel is classified, and it takes its operand from
    the DOM rather than estimating one from the crop. See the module docstring on
    why every estimated background here was wrong.
    """
    ref = np.asarray(rgb[:3], dtype=np.int32)
    return np.abs(region.astype(np.int32) - ref).sum(axis=2) <= tol


def span_fill(mask: np.ndarray) -> np.ndarray:
    """Close a mask's interior holes row-wise: first set pixel to last, per row.

    Exact for the convex shapes X2 applies to -- a disc, a pill, a rounded rect --
    and it is what turns "the button's fill, minus the glyph punched out of it"
    into "the button's painted extent", so the glyph can be recovered as the
    difference of the two.
    """
    out = mask.copy()
    for i, row in enumerate(mask):
        nz = np.nonzero(row)[0]
        if nz.size:
            out[i, nz[0] : nz[-1] + 1] = True
    return out


def backdrop_of(band: np.ndarray, fg) -> np.ndarray | None:
    """The colour BEHIND the text in one band: median of every non-ink pixel.

    Median, not mode: a gradient has no modal colour (see the module docstring),
    and the mode of a gradient band is the text drawn on top of it. Returns None
    when the band is entirely ink, which is the honest answer rather than a
    number.
    """
    keep = ~matches(band, fg)
    if not keep.any():
        return None
    return np.median(band[keep].reshape(-1, 3), axis=0)


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

    by_path = {e["path"]: e for e in snap["elements"]}

    def parent_of(el):
        head = el["path"].rsplit(" > ", 1)
        return by_path.get(head[0]) if len(head) > 1 else None

    for el in snap["elements"]:
        r = el["rect"]
        if r["w"] < MIN_BOX or r["h"] < MIN_BOX:
            continue
        region = crop(img, r, scale)
        if region is None:
            continue
        fg = parse_rgb(el["styles"].get("color", ""))

        # --- X1: the DOM says there is text here; the pixels say nothing -------
        # Asked directly of the declared text colour. The old form asked whether
        # anything differed from the crop's modal colour, which on a gradient
        # made the TEXT the mode and reported 98% ink for an element it could not
        # see at all -- a check that fails open is worse than an absent one.
        if el["text"] and fg:
            n_ink = int(matches(region, fg).sum())
            per_char = n_ink / len(el["text"])
            if per_char < INK_MIN_PER_CHAR:
                rep(
                    "xcheck-zero-ink",
                    el["path"],
                    f"box is {r['w']:.0f}x{r['h']:.0f}px and carries "
                    f"{len(el['text'])} characters {el['text'][:24]!r} in "
                    f"{hexof(fg)}, but only {n_ink} pixels are that colour "
                    f"({per_char:.2f}/char) -- it paints nothing a reader can see",
                    "high",
                )
                continue

        # --- X2: ink is not centred in the shape the DOM centred it in ---------
        # Measured against the CONTAINER and masked to the painted shape; see the
        # module docstring for the two defects that made both necessary, and for
        # why the vertical axis carries an observation rather than a verdict.
        parent = parent_of(el)
        if (
            fg
            and el["text"]
            and len(el["text"]) <= GLYPH_MAX_CHARS
            and r["w"] < GLYPH_MAX_PX
            and r["h"] < GLYPH_MAX_PX
            and parent is not None
        ):
            fill = parse_rgb(parent["styles"].get("background-color", ""))
            shell = crop(img, parent["rect"], scale)
            if fill and fill[3] > 0.99 and shell is not None:
                core = matches(shell, fill)  # the fill, with the mark punched out
                shape = span_fill(core)  # the container's painted extent
                mark = shape & ~core  # the mark, and only inside the shape
                if core.any() and mark.any():
                    sy, sx = np.nonzero(shape)
                    my, mx = np.nonzero(mark)
                    dx = (mx.mean() - sx.mean()) / scale
                    dy = (my.mean() - sy.mean()) / scale
                    if abs(dx) > CENTROID_TOL_PX:
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"the DOM centres this mark in its container, but its "
                            f"rendered ink sits {abs(dx):.1f}px "
                            f"{'left' if dx < 0 else 'right'} of the painted "
                            f"shape's own centre -- it will read as misaligned "
                            f"however correct the CSS is. (Vertically it sits "
                            f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'}; that "
                            f"axis is baseline-governed and carries no verdict)",
                        )

        # --- X3: does contrast even HAVE one value across this run? ------------
        if el["text"] and len(el["text"]) > 3 and fg:
            # Sample the real backdrop separately in the left and right thirds, so
            # a backdrop that VARIES across the run cannot hide behind a single
            # number. Median of the non-ink pixels, because a gradient has no mode.
            w = region.shape[1]
            left = backdrop_of(region[:, : w // 3], fg)
            right = backdrop_of(region[:, -w // 3 :], fg)
            if left is None or right is None:
                continue
            cl, cr = contrast(fg[:3], left), contrast(fg[:3], right)
            if abs(cl - cr) > CONTRAST_DELTA:
                lo_side = "left" if cl < cr else "right"
                rep(
                    "xcheck-contrast-varies",
                    el["path"],
                    f"contrast is not one number across this text: {cl:.2f}:1 at the "
                    f"left edge ({hexof(left)}) and {cr:.2f}:1 at the right "
                    f"({hexof(right)}). Any single computed value is a fiction, and "
                    f"the {lo_side} end is the one that fails a reader",
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
