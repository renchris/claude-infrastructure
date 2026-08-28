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
  X2 ink-centroid    a mark's rendered ink does not sit where its CONTAINER
                     centres it. Both defects found while validating the first
                     version are fixed here, and both fixes are load-bearing:

                     (a) It used to compare ink to the element's OWN box, and
                     getBoundingClientRect returns the POST-transform box, so a
                     translate moved box and ink together and the offset was
                     INVARIANT under the very compensation it should verify.
                     It now measures against the container's box, which does not
                     move when the child is translated -- so removing an optical
                     compensation actually shows up as a displacement.

                     (b) Its background used to be the crop's modal colour, so on
                     a round button the square crop's corners -- page background
                     outside the circle -- counted as ink and swamped a 16px
                     glyph. The crop is now masked to the container's PAINTED
                     shape, derived from its own border-radius, and both the
                     background estimate and the centroid are taken inside that
                     mask only.

                     Measured on this corpus: quiet on the control, and on the
                     `optical-centering` variant it recovers the removed
                     compensation. `--no-x2` disables it.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

                     The backdrop is the MEDIAN of the band's non-ink pixels, not
                     its modal colour. On a gradient no background colour repeats
                     -- every column is a different value -- so the mode is won by
                     the text's own antialiased core, and the check reported the
                     text colour against itself and fell silent. Measured: on
                     Linux/DejaVu the modal version found 0 findings on the
                     gradient page it was written to catch. A silent miss on the
                     one case a check exists for is the worst failure available to
                     it, and it was invisible because the control stayed quiet.

                     X3 samples BOTH axes. Left/right only passes a vertical
                     gradient with one confident number, and "the check does not
                     look that way" is not a property a reader can see.

                     KNOWN LIMIT, deliberately not closed here. A high-frequency
                     backdrop -- a pattern, a photograph -- varies violently and
                     still averages the same in every band, so X3 finds no
                     disagreement and says nothing. That silence is correct rather
                     than a false pass: X3 only ever CLOSES the DOM's abstention,
                     so an abstention it cannot close survives and routes to the
                     vision layer, which is what `contrast-on-texture` in the
                     corpus exists to demonstrate. A per-pixel luminance-spread
                     rule was written to close it directly and is NOT shipped: it
                     fired on 24 elements of the clean control, because a text
                     run's antialiased glyph edges span the whole luminance range
                     and swamp the backdrop's own spread. Two later variants
                     (backdrop-agreement fraction, per-tile medians) each failed
                     on a different threshold interaction. The measurement that
                     would settle it is a spread taken over BACKDROP pixels only,
                     which needs a glyph mask this check does not have; until then
                     the honest route is the abstention, not a tuned constant.

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
CENTROID_TOL_PX = 1.0  # ink centre vs the CONTAINER's centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# A mark's container. Beyond this it is a layout box, and ink being off-centre
# inside a layout box is text flow, not a missing optical compensation.
MARK_CONTAINER_MAX = 96.0
# Ink share inside the masked container. Below it the mark is noise; above it the
# container is filled rather than carrying a mark, and a centroid says nothing.
MARK_INK_MIN, MARK_INK_MAX = 0.005, 0.50
FG_INK_DIST = 60  # channel-sum distance at which a pixel counts as the text's ink
X2_ENABLED = "--no-x2" not in sys.argv  # see the X2 note in the docstring


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


def rounded_rect_mask(h: int, w: int, radius: float) -> np.ndarray:
    """Boolean mask of the shape a border-radius box actually paints.

    Without this, a round button's square crop carries four corners of PAGE
    background, which differ from the button's fill and therefore count as ink --
    hundreds of pixels of it, against the ~60 of an actual 16px glyph. The
    centroid then measures the crop's corners, not the mark, and reports a real
    number about the wrong subject.
    """
    r = float(min(radius, w / 2.0, h / 2.0))
    mask = np.ones((h, w), dtype=bool)
    if r <= 0.5:
        return mask
    ys = np.arange(h)[:, None] + 0.5
    xs = np.arange(w)[None, :] + 0.5
    for cy, cx in ((r, r), (r, w - r), (h - r, r), (h - r, w - r)):
        corner = (
            ((ys < r) | (ys > h - r))
            & ((xs < r) | (xs > w - r))
            & (((ys - cy) ** 2 + (xs - cx) ** 2) > r * r)
        )
        mask &= ~corner
    return mask


def modal_colour(pixels: np.ndarray):
    """Most common exact colour in an (N,3) array."""
    vals, counts = np.unique(pixels, axis=0, return_counts=True)
    return vals[counts.argmax()]


def px(v) -> float:
    try:
        return float(str(v).replace("px", "").strip())
    except (ValueError, AttributeError, TypeError):
        return 0.0


def translate_of(transform: str) -> tuple[float, float]:
    """The (tx, ty) an element's computed transform applies, in CSS px.

    This is the author's own statement of intent about optical centring, and it is
    the DOM half of X2's comparison. getComputedStyle serialises to a matrix, so
    'translate(2px, 2px)' arrives as 'matrix(1, 0, 0, 1, 2, 2)'.
    """
    t = (transform or "none").strip()
    if t in ("", "none"):
        return 0.0, 0.0
    inner = t[t.find("(") + 1 : t.rfind(")")]
    try:
        v = [float(x) for x in inner.split(",")]
    except ValueError:
        return 0.0, 0.0
    if t.startswith("matrix3d") and len(v) >= 14:
        return v[12], v[13]
    if t.startswith("matrix") and len(v) >= 6:
        return v[4], v[5]
    return 0.0, 0.0


def backdrop_of(band: np.ndarray, fg) -> np.ndarray:
    """The colour BEHIND the text in one band, given what the cascade paints on it.

    The modal colour is wrong here and wrong in the one case the check exists for.
    Across a gradient no background value repeats -- each column is a different
    colour, sixteen pixels of it -- while the glyph's antialiased core is one
    exact value repeated hundreds of times. The mode therefore returns the TEXT
    colour, the contrast comes out 1.0:1 on both sides, the sides agree, and a
    check written to catch a washed-out caption reports nothing.

    So: drop the pixels that are the text, and take the MEDIAN of what is left.
    The median of a gradient band is that band's middle colour, which is the
    honest single operand for it; on a solid backdrop it is the solid colour.
    """
    flat = band.reshape(-1, 3)
    keep = flat[np.abs(flat - np.asarray(fg, dtype=np.int16)).sum(axis=1) > FG_INK_DIST]
    # If the text fills its band there is nothing behind it to sample; fall back
    # to the whole band rather than inventing a backdrop from three pixels.
    if keep.shape[0] < flat.shape[0] // 4:
        keep = flat
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
    by_path = {e["path"]: e for e in snap["elements"]}
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

        # --- X2: ink is not centred in the box the CONTAINER centres -----------
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows.
        #
        # The subject is the CONTAINER, not the element. The element's own box is
        # the post-transform one, so it travels with the ink and cannot witness a
        # translate; the container's box does not move, which is exactly the frame
        # an optical compensation is expressed against.
        is_glyph_like = (
            X2_ENABLED and r["w"] < 64 and r["h"] < 64 and 0 < len(el["text"]) <= 3
        )
        parent = (
            by_path.get(el["path"].rsplit(" > ", 1)[0]) if " > " in el["path"] else None
        )
        if is_glyph_like and parent is not None:
            pr = parent["rect"]
            box = crop(img, pr, scale)
            if (
                box is not None
                and pr["w"] <= MARK_CONTAINER_MAX
                and pr["h"] <= MARK_CONTAINER_MAX
            ):
                radius = px(parent["styles"].get("border-radius")) * scale
                mask = rounded_rect_mask(box.shape[0], box.shape[1], radius)
                inside = box[mask]
                pbg = modal_colour(inside)
                pdist = np.abs(box.astype(np.int32) - pbg.astype(np.int32)).sum(axis=2)
                pink = (pdist > 40) & mask
                pfrac = float(pink.sum()) / float(mask.sum())
                if MARK_INK_MIN < pfrac < MARK_INK_MAX and pink.any():
                    iy, ix = np.nonzero(pink)
                    my, mx = np.nonzero(mask)
                    dx = (ix.mean() - mx.mean()) / scale
                    dy = (iy.mean() - my.mean()) / scale
                    # A glyph's ink centroid is NEVER at its container's centre --
                    # that asymmetry is why optical compensation exists at all, and
                    # its size is a property of the font, not of the design. A bare
                    # threshold on this quantity therefore hardcodes one font's
                    # metrics as a universal constant: measured here, the same
                    # control that is quiet under macOS/Helvetica reports 3.0px
                    # left under DejaVu, so the rule would fire on the clean page
                    # on any machine but the one it was written on.
                    #
                    # The comparison that survives a font change uses the DOM's own
                    # statement of intent. The author's transform says how far they
                    # moved the mark; the pixels say whether that moved the ink
                    # TOWARD the container's centre or away from it. Fire when the
                    # mark is materially off centre AND the compensation did not
                    # help -- which covers both the absent compensation (the
                    # corpus's injected defect) and the wrong-direction one.
                    tx, ty = translate_of(el["styles"].get("transform", ""))
                    ux, uy = dx - tx, dy - ty  # where the ink would sit uncompensated
                    off = abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX
                    helped = abs(dx) < abs(ux) - 0.25 or abs(dy) < abs(uy) - 0.25
                    if off and not helped:
                        how = (
                            "nothing compensates for it"
                            if (tx, ty) == (0.0, 0.0)
                            else f"its transform moves it ({tx:+g}, {ty:+g})px, which "
                            f"does not bring the ink back"
                        )
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"{parent['path'].rsplit(' > ', 1)[-1]} centres this mark "
                            f"exactly, but its rendered ink sits "
                            f"{abs(dx):.1f}px {'left' if dx < 0 else 'right'} and "
                            f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'} of the "
                            f"container's painted centre, and {how} -- it will read "
                            f"as misaligned however correct the CSS is",
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text: the modal non-ink colour,
            # taken separately from the left and right thirds so a backdrop that
            # VARIES across the run cannot hide behind a single average.
            h, w = region.shape[:2]
            # Both axes. Sampling only left/right passes a vertical gradient with
            # a confident single number, and "the check does not look that way" is
            # not a property a reader can see.
            axes = {
                "horizontally": (
                    ("left", region[:, : max(1, w // 3)]),
                    ("right", region[:, -max(1, w // 3) :]),
                ),
                "vertically": (
                    ("top", region[: max(1, h // 3), :]),
                    ("bottom", region[-max(1, h // 3) :, :]),
                ),
            }
            fired = False
            for axis, ((na, ba), (nb, bb)) in axes.items():
                ca = contrast(fg[:3], backdrop_of(ba, fg[:3]))
                cb = contrast(fg[:3], backdrop_of(bb, fg[:3]))
                if abs(ca - cb) > CONTRAST_DELTA:
                    lo = na if ca < cb else nb
                    rep(
                        "xcheck-contrast-varies",
                        el["path"],
                        f"contrast is not one number across this text: it varies "
                        f"{axis}, {ca:.2f}:1 at the {na} and {cb:.2f}:1 at the "
                        f"{nb}. Any single computed value is a fiction, and the "
                        f"{lo} end is the one that fails a reader",
                        "high",
                    )
                    fired = True
            # A backdrop can vary violently and still average the same in every
            # band -- a photograph, a pattern, anything high-frequency. X3 then
            # finds no disagreement and stays silent, and silence here is CORRECT
            # rather than a false pass: the comparator only ever CLOSES the DOM's
            # abstention, so an abstention it cannot close survives and is routed
            # to something that can look. See the X3 note in the docstring for the
            # rule that was tried here instead, and why it is not shipped.
            del fired
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
