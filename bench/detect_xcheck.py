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
  X2 ink-centroid    the ink inside a container that CLAIMS to centre its child
                     is not centred in it. Validated and ON by default as of
                     2026-09-03; `--no-x2` disables it.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

--------------------------------------------------------------------------------
X2, and why it was provisional until now
--------------------------------------------------------------------------------
The first version of X2 shipped disabled because trying to validate it found two
defects in it, and both were the plausible-wrong-number this whole wave argues
against:

  (a) it compared ink to the element's OWN box, and getBoundingClientRect returns
      the POST-transform box, so a `translate` moves box and ink together and the
      measured offset is INVARIANT under the very compensation it should verify;
  (b) its background was the crop's modal colour, so on a round button the square
      crop's corners -- page background outside the circle -- counted as ink and
      swamped a 16px glyph.

Both fixes are now in, and they are the two halves of one idea: **the DOM supplies
the geometry, the pixels supply only the ink distribution.**

  (a) MEASURE AGAINST THE CONTAINER. The subject is no longer the element's own
      box but its parent's, and the candidate gate is the parent's own CLAIM --
      `align-items:center` AND `justify-content:center`. That makes the check a
      real cross-check rather than a measurement: the DOM asserts "this child is
      centred here", and X2 asks the pixels whether they agree. The parent is not
      the transformed node, so the invariance is gone: a translate on the child
      moves ink relative to the container box and the offset moves with it.
  (b) MASK TO THE PAINTED SHAPE. The mask is built analytically from the
      container's own border-radius rather than guessed from colour, so a circle's
      corners are excluded because the DOM says they are not painted. Inside that
      shape a pixel is ink when it is nearer the child's computed `color` than the
      container's computed `background-color` -- a nearest-of-two split with no
      threshold to tune, which lands antialiased edge pixels fairly on both sides.

The colour test alone could not have fixed (b) here: the glyph is #FFFFFF and the
page behind the button is also #FFFFFF, so the corners are indistinguishable from
ink BY COLOUR and separable only BY SHAPE. That is the whole reason the fix is
geometric.

Proof the fix is real, measured on this corpus (identical container, the ONLY
difference between the two pages being `transform: translate(2px,2px)` vs `none`):

    arm                              clean.html        optical-centering.html
    OLD (own box, modal bg)          dx -1.59 dy +1.73  dx -1.59 dy +1.73   <- identical
    NEW (container, shape-masked)    dx -2.87 dy -0.26  dx -4.34 dy -1.74   <- moves

The old arm returns the SAME NUMBER on both pages, to two decimals. It was not
merely imprecise, it was blind by construction, and it would have gone on
reporting that number with total confidence. The new arm moves by ~1.47px in both
axes -- not the full 2px of the translate, because Chromium promotes the
transformed glyph to its own paint layer and its antialiasing is not a pure
translate of the untransformed one (the ink pixel count is identical at 106 in
both, so the shape is preserved and only its edge weighting shifts).

--------------------------------------------------------------------------------
Why X2 ABSTAINS instead of calling a defect
--------------------------------------------------------------------------------
X2 emits `xcheck-optical-indeterminate`, not a defect claim, and it fires on the
clean control -- deliberately, and it is not a false positive.

The reason is in the numbers above: on the clean control the compensated glyph
still sits 2.87px left of the container's centre. That compensation was authored
and measured on macOS/Helvetica (2.2px left, 1.9px up -- see build_corpus.py); on
this host the same U+25B6 comes from a fallback face with a different ink
asymmetry, so the same 2px translate does not null it out. The RESIDUAL IS A
PROPERTY OF THE FONT, and no substrate in this pipeline exposes a glyph's
intrinsic optical centre.

So "is 2.87px correct compensation or a defect?" is not answerable by arithmetic,
and any absolute threshold that separated 2.87 from 4.34 would be a constant tuned
to this corpus on this host -- the overfitting the control exists to prevent, and
the plausible-wrong-number this document argues against, reintroduced one layer up.
P5-route already classes `optical-alignment` as an unscreenable question. X2's
honest product is therefore the MEASUREMENT plus an explicit UNVERIFIED, which
`route.py` turns into a cropped question. The false-positive budget counts defect
claims; abstentions are counted separately, because their cost is a model call
rather than a lost reader's trust.

Usage: python3 detect_xcheck.py <corpus-dir> [--no-x2]
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image

from verdict import is_abstention

# Every rule this module can emit -- see the note on detect_dom.RULES.
RULES = (
    "xcheck-zero-ink",
    "xcheck-optical-indeterminate",
    "xcheck-contrast-varies",
)

# Tolerances are stated, not tuned. Each is well above sub-pixel rounding and
# well below what a person would call "off", so a finding means a real gap.
INK_MIN_FRAC = (
    0.002  # below this share of non-background pixels, the box paints nothing
)
CENTROID_TOL_PX = 1.0  # ink centre vs CONTAINER centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# X3 reads the backdrop as the MEDIAN of a band. A band that is mostly the text's
# own ink has no backdrop to report, so the check abstains rather than reporting
# the text colour back to itself. INK_NEAR_FG is used ONLY to detect that
# domination -- never to filter pixels out of the median (see the note at X3).
# 48 is an abs-sum over three channels, i.e. ~16/255 each: inside "the same
# colour", outside any two distinct tokens.
INK_NEAR_FG = 48
BACKDROP_MIN_SURVIVORS = 0.20
# CSS px shaved off the container's painted shape before any pixel is classified,
# so the antialiased boundary ring can never be mistaken for ink. 2px covers
# Chromium's ~1px AA with margin; it is scaled by the capture's device scale.
EDGE_ERODE_PX = 2.0


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


def px(v: str) -> float:
    try:
        return float(str(v).replace("px", "").strip())
    except (ValueError, AttributeError):
        return 0.0


def shape_mask(h: int, w: int, radius_raster: float, erode: float = 0.0) -> np.ndarray:
    """Boolean mask of a rounded rectangle's painted INTERIOR, in raster pixels.

    Built from the container's own `border-radius`, not inferred from colour. On a
    round button the four square corners are page background, not container and
    not ink; on this corpus they are the same #FFFFFF as the glyph itself, so no
    colour test can exclude them and only the geometry can. This is fix (b).

    `erode` insets the shape, and it is not an optional refinement -- without it
    this mask is wrong in a way that is easy to miss. A painted circle has a ~1px
    ANTIALIASED RING where blue blends to white, and the outer half of that ring is
    nearer white than blue, so a nearest-of-two split calls it ink. It is only a
    handful of pixels, but they sit at the maximum distance from the centre, so
    their lever arm on a centroid is enormous: measured on this corpus, ~10 stray
    ring pixels moved dy by 5.5px on a 44px button while the glyph's own 96 pixels
    stayed put, and the ink bounding box read 0-36px for a glyph 16px tall. The
    number stayed perfectly plausible the whole time.
    """
    e = int(round(erode))
    if e > 0:
        inner = shape_mask(h - 2 * e, w - 2 * e, max(0.0, radius_raster - erode))
        m = np.zeros((h, w), bool)
        m[e : h - e, e : w - e] = inner
        return m
    m = np.ones((h, w), bool)
    r = int(round(radius_raster))
    if r <= 0:
        return m
    r = min(r, h // 2, w // 2)
    if r <= 0:
        return m
    # Distance from the corner arc's centre, measured at pixel centres.
    yy, xx = np.ogrid[:r, :r]
    outside = ((yy - (r - 0.5)) ** 2 + (xx - (r - 0.5)) ** 2) > (r * r)
    m[:r, :r] &= ~outside
    m[:r, w - r :] &= ~outside[:, ::-1]
    m[h - r :, :r] &= ~outside[::-1, :]
    m[h - r :, w - r :] &= ~outside[::-1, ::-1]
    return m


def nearer_to(region: np.ndarray, a, b) -> np.ndarray:
    """Pixels nearer colour `a` than colour `b`. A nearest-of-two split.

    No threshold to tune, and antialiased edge pixels fall on whichever side they
    are actually closer to, which keeps a centroid unbiased instead of eroding one
    edge of the glyph.
    """
    r = region.astype(np.int32)
    da = np.abs(r - np.asarray(a[:3], np.int32)).sum(axis=2)
    db = np.abs(r - np.asarray(b[:3], np.int32)).sum(axis=2)
    return da < db


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


def check(snap: dict, png: pathlib.Path, x2_enabled: bool = True) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    by_path = {e["path"]: e for e in snap["elements"]}

    def parent_of(el):
        head = el["path"].rsplit(" > ", 1)
        return by_path.get(head[0]) if len(head) > 1 else None

    out = []

    def rep(rule, target, detail, severity="medium", measure=None):
        f = {"rule": rule, "target": target, "detail": detail, "severity": severity}
        # `detail` is prose for a human and carries its numbers already rounded, so
        # comparing two runs by their detail strings compares presentation, not
        # measurement. `measure` is the same quantities as data, which is what lets
        # the router ask "did this MOVE?" with a tolerance instead of a string diff.
        if measure:
            f["measure"] = {k: round(float(v), 3) for k, v in measure.items()}
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

        # --- X2: ink is not centred in the CONTAINER that claims to centre it ---
        # The candidate gate is the PARENT's own claim, which is what makes this a
        # cross-check rather than a measurement: the DOM asserts "I centre this
        # child", and X2 asks the pixels whether they agree. Only meaningful for a
        # small self-contained mark -- a paragraph's ink is legitimately
        # top-left-heavy because text flows.
        container = parent_of(el)
        claims_centre = container is not None and (
            container["styles"].get("align-items", "").strip() == "center"
            and container["styles"].get("justify-content", "").strip() == "center"
        )
        if (
            x2_enabled
            and claims_centre
            and r["w"] < 64
            and r["h"] < 64
            and len(el["text"]) <= 3
            and el["text"]
        ):
            cr = container["rect"]
            # (a) The subject is the CONTAINER's box. getBoundingClientRect returns
            # the POST-transform box, so measuring the child against its own box is
            # invariant under the translate that does the optical compensation --
            # the container is the only frame in which that translate is visible.
            creg = crop(img, cr, scale)
            fg = parse_rgb(el["styles"].get("color", ""))
            bgc = parse_rgb(container["styles"].get("background-color", ""))
            if creg is not None and fg and bgc and bgc[3] > 0.99:
                # (b) Mask to the painted shape before looking at any colour.
                shape = shape_mask(
                    creg.shape[0],
                    creg.shape[1],
                    px(container["styles"].get("border-radius")) * scale,
                    erode=EDGE_ERODE_PX * scale,
                )
                gink = shape & nearer_to(creg, fg, bgc)
                # A mark that paints almost nothing, or almost everything, has no
                # meaningful centroid -- abstain rather than report a number.
                gfrac = float(gink.sum()) / max(1, int(shape.sum()))
                if 0.01 < gfrac < 0.60:
                    ys, xs = np.nonzero(gink)
                    dx = (xs.mean() - (creg.shape[1] - 1) / 2) / scale
                    dy = (ys.mean() - (creg.shape[0] - 1) / 2) / scale
                    if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                        rep(
                            "xcheck-optical-indeterminate",
                            el["path"],
                            f"{container['path']} centres this child exactly by the "
                            f"box model, but the child's rendered ink sits "
                            f"{abs(dx):.1f}px {'left' if dx < 0 else 'right'} and "
                            f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'} of the "
                            f"container's centre. Whether that offset is deliberate "
                            f"optical compensation or a defect is UNVERIFIED -- it "
                            f"depends on the glyph's own ink asymmetry, which no "
                            f"substrate here exposes",
                            measure={"dx": dx, "dy": dy},
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text, separately in the left and
            # right thirds, so a backdrop that VARIES across the run cannot hide
            # behind a single average.
            #
            # NOT the modal colour, which is what this check used until 2026-09-03
            # and which is unsound for exactly the case the check exists for. Under
            # a GRADIENT every column is a different colour, so no backdrop colour
            # repeats, while the text's own solid fill repeats hundreds of times --
            # so the mode of the band IS THE TEXT, and the check compares the text
            # to itself and reports ~1:1 at both ends. It then finds no delta and
            # stays silent. Measured on this corpus: the gradient page went from a
            # 4.81 vs 1.57 finding to reporting nothing at all, purely because the
            # host's fallback font (Liberation Sans, no Helvetica on Linux) painted
            # enough extra white pixels to win the mode. A check whose verdict turns
            # on a font substitution is not measuring what it claims to.
            #
            # So: take the MEDIAN of the band. The median of a gradient band is its
            # middle column -- a real, present backdrop colour -- and a minority of
            # ink does not move it. Note what is deliberately NOT done: the ink is
            # not filtered out first. Filtering by "close to the text colour" would
            # discard the backdrop precisely where it is closest to the text, i.e.
            # exactly where contrast is worst, and the check would go quiet on its
            # own worst case -- the fail-safe-mimics-the-healthy-state trap again.
            # Ink dominance is handled by ABSTAINING instead, below.
            w = region.shape[1]
            thirds = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled = {}
            for side, band in thirds.items():
                flatb = band.reshape(-1, 3)
                near_fg = (
                    np.abs(flatb.astype(np.int32) - np.asarray(fg[:3], np.int32)).sum(
                        axis=1
                    )
                    < INK_NEAR_FG
                )
                if 1.0 - float(near_fg.mean()) < BACKDROP_MIN_SURVIVORS:
                    sampled = None  # text-dominated band: no backdrop to report
                    break
                sampled[side] = np.median(flatb, axis=0)
            if sampled is None:
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


def run(corpus: pathlib.Path, x2_enabled: bool = True) -> dict[str, list[dict]]:
    """Cross-check every captured page. Importable so the router and the
    false-positive budget run the same code path the CLI does."""
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    results = {}
    for f in sorted(snaps.glob("*.json")):
        png = shots / f"{f.stem}.png"
        if not png.exists():
            continue
        results[f.stem] = check(json.loads(f.read_text()), png, x2_enabled)
    return results


def main(corpus: pathlib.Path, x2_enabled: bool = True) -> None:
    results = run(corpus, x2_enabled)
    (corpus / "findings_xcheck.json").write_text(json.dumps(results, indent=1))

    ctrl = results.get("clean", [])
    # An abstention on the control is NOT a false positive -- it is the layer
    # saying it cannot answer, which is the whole point of the seam. Only a defect
    # CLAIM on a page with no defect costs a reader's trust, so the two are counted
    # apart here rather than summed into one alarming number.
    ctrl_fp = [c for c in ctrl if not is_abstention(c)]
    ctrl_abs = [c for c in ctrl if is_abstention(c)]
    print(
        f"CONTROL clean.html -> {len(ctrl_fp)} false positive(s)"
        f"{'  (quiet)' if not ctrl_fp else '  <-- rules are noisy'}"
        f" · {len(ctrl_abs)} abstention(s)"
    )
    for c in ctrl:
        kind = "ABSTAIN" if is_abstention(c) else "CLAIM"
        print(f"    [{kind}][{c['rule']}] {c['target']}: {c['detail'][:80]}")
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
    main(
        pathlib.Path(args[0] if args else "corpus/out").resolve(),
        x2_enabled="--no-x2" not in sys.argv,
    )
