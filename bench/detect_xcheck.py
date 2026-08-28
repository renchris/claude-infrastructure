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
  X2 ink-centroid    the rendered ink of a small mark does not sit at the centre
                     of the CONTAINER that centres it.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that RESOLVES the DOM's
                     `contrast-indeterminate` abstention, in either direction.

THE ONE IDEA ALL THREE SHARE, and the reason two of them were wrong before
2026-08-28: **the DOM says which colour is paint; the pixels say where it is.**
The previous version took the crop's MODAL colour as the background, which is a
guess made from the pixels alone, and it failed twice in opposite directions:

  X2 (a) compared ink to the element's OWN box, and getBoundingClientRect returns
         the POST-transform box, so a translate moved box and ink together and the
         measured offset was INVARIANT under the very compensation it verified.
     (b) took the crop's modal colour as background, so on a round button the
         square crop's corners -- page background outside the circle, and the same
         white as the glyph -- counted as ink and swamped the mark.
     Both are fixed here: measure against the CONTAINER's box, and mask to the
     painted shape (`paint()` below) so nothing outside the rendered silhouette
     can enter the centroid.

  X3     took the modal colour of a band as the backdrop. On a gradient every
         backdrop pixel is nearly unique while every glyph pixel is exactly the
         text colour, so on a greyscale-antialiasing platform THE TEXT WINS THE
         MODE and the check compares the text against itself: contrast 1.00 on
         both sides, spread 0.00, silence. Measured 2026-08-28 on Linux/Chromium
         141, where the arm the README reports as validated found nothing at all.
         Fixed by excluding declared-foreground pixels from the backdrop
         population and taking a MEDIAN, which a gradient cannot capture.

X3 also no longer measures the element's box. It measures the horizontal extent
of the ink -- where glyphs actually are. On this corpus the caption's box is
1168px wide and its glyphs occupied 298 of them, so the old "left third vs right
third of the box" sampled a region no reader ever looks at. A contrast reported
for a place with no text is precisely the plausible-wrong-number this bench
exists to catch.

Usage: python3 detect_xcheck.py <corpus-dir> [--no-x2]
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image

# The cascade walk is IMPORTED, never re-implemented. A cross-check compares the
# DOM's answer with the pixels', so it must ask the DOM the same question the DOM
# layer asks itself -- a second copy of `backdrop()` here would let the two
# layers drift and turn every disagreement into an artifact of the drift.
from detect_dom import Page as DomPage

# Tolerances are stated, not tuned. Each is well above sub-pixel rounding and
# well below what a person would call "off", so a finding means a real gap.
INK_MIN_FRAC = 0.002  # below this share of in-shape pixels, the box paints nothing
CENTROID_TOL_PX = 1.0  # ink centre vs CONTAINER centre
CONTRAST_DELTA = 1.5  # ratio points between the two ends of a text run
CONTRAST_MIN = 4.5  # the WCAG floor X3 resolves an abstention against
CONTRAST_MIN_LARGE = 3.0
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid

# Channel-sum distances, so each is a third of the per-channel figure it reads as.
FIELD_TOL = 60  # how far a pixel may sit from a DECLARED colour and still be it
INK_TOL = 30  # tighter: the gradient's pale end is 58 from white, and it is
# not ink. Measured on this corpus -- at 90 the caption's ink
# extent read as the whole 1168px box.

# X2 needs a container whose paint it can identify and whose centre means
# something. A mark inside a full-width panel has no optical centre to be off.
X2_MAX_CONTAINER = 96.0
X2_MIN_SHAPE_FRAC = 0.30  # the container must actually be painted, not transparent
X2_MAX_INK_FRAC = 0.60  # ...and the mark must be a mark, not a filled block

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


def hexof(rgb) -> str:
    return "#%02X%02X%02X" % tuple(int(round(c)) for c in rgb[:3])


def near(region: np.ndarray, rgb, tol: int) -> np.ndarray:
    """Pixels within `tol` (summed over channels) of a colour the DOM declared."""
    return (
        np.abs(region.astype(np.int32) - np.asarray(rgb[:3], dtype=np.int32)).sum(
            axis=2
        )
        <= tol
    )


def convex_fill(mask: np.ndarray) -> np.ndarray:
    """Fill a mask to its per-row AND per-column spans.

    For a convex silhouette -- which is what every rounded rect, pill and circle
    is -- the intersection of the two spans is the shape exactly. It is what
    turns "pixels that are the button's blue" into "pixels inside the button",
    and that distinction is the whole of X2 defect (b): the corners of a square
    crop around a round button are page background, they are often the same
    colour as the mark, and they must never be able to enter a centroid.
    """
    rows = np.zeros_like(mask)
    for i in range(mask.shape[0]):
        idx = np.flatnonzero(mask[i])
        if idx.size:
            rows[i, idx[0] : idx[-1] + 1] = True
    cols = np.zeros_like(mask)
    for j in range(mask.shape[1]):
        idx = np.flatnonzero(mask[:, j])
        if idx.size:
            cols[idx[0] : idx[-1] + 1, j] = True
    return rows & cols


def paint(region: np.ndarray, field_rgb, ink_rgb=None):
    """Split a crop into (shape, field, ink) using colours the DOM declared.

    `field_rgb` is the container's own background-color -- the paint. `shape` is
    its convex silhouette, so anything outside the rendered form is excluded
    before any statistic is taken. `ink` is everything inside the shape that is
    not the field; when the foreground colour is also known it is intersected
    with that, which keeps a border or a shadow out of the mark's centroid.
    """
    field = near(region, field_rgb, FIELD_TOL)
    shape = convex_fill(field)
    ink = shape & ~field
    if ink_rgb is not None:
        by_colour = near(region, ink_rgb, FIELD_TOL)
        if (ink & by_colour).sum() >= 4:
            ink = ink & by_colour
    return shape, field, ink


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


class Page(DomPage):
    """The DOM layer's own page model, plus the one lookup only X2 needs."""

    def solid_container(self, el):
        """The nearest ancestor that paints a solid colour, or None.

        X2 measures against a container, and 'container' has to mean something
        checkable: an ancestor whose background-color the DOM states outright, so
        the field is identified rather than guessed from the pixels.
        """
        cur = self.parent_of(el)
        depth = 0
        while cur is not None and depth < 4:
            c = parse_rgb(cur["styles"].get("background-color", ""))
            if c and c[3] > 0.99:
                return cur, c
            cur = self.parent_of(cur)
            depth += 1
        return None, None


def check(snap: dict, png: pathlib.Path) -> tuple[list[dict], dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    pg = Page(snap)
    out: list[dict] = []
    census = {"xcheck-zero-ink": 0, "xcheck-optical-centre": 0, "xcheck-contrast": 0}

    def rep(rule, target, detail, severity="medium", **extra):
        out.append(
            {
                "rule": rule,
                "target": target,
                "detail": detail,
                "severity": severity,
                **extra,
            }
        )

    for el in pg.els:
        r = el["rect"]
        if r["w"] < MIN_BOX or r["h"] < MIN_BOX:
            continue

        fg = parse_rgb(el["styles"].get("color", ""))

        # --- X1: the DOM says there is an element here; the pixels say nothing --
        if el["text"]:
            region = crop(img, r, scale)
            if region is not None:
                container, field_rgb = pg.solid_container(el)
                own = parse_rgb(el["styles"].get("background-color", ""))
                base = own if (own and own[3] > 0.99) else field_rgb
                if base is not None:
                    census["xcheck-zero-ink"] += 1
                    lit = near(region, base, FIELD_TOL)
                    frac = float((~lit).mean())
                    if frac < INK_MIN_FRAC:
                        rep(
                            "xcheck-zero-ink",
                            el["path"],
                            f"box is {r['w']:.0f}x{r['h']:.0f}px and carries text "
                            f"{el['text'][:24]!r}, but only {frac * 100:.2f}% of its "
                            f"pixels differ from the {hexof(base)} it is painted on "
                            f"-- it paints nothing a reader can see",
                            "high",
                        )
                        continue

        # --- X2: ink is not centred in the CONTAINER that centres it ------------
        # Measured against the container's box, never the element's own: a
        # `transform: translate` is exactly how optical compensation is written,
        # and getBoundingClientRect reports the post-transform box, so an
        # own-box measurement is blind to the thing it exists to check.
        container, field_rgb = pg.solid_container(el)
        is_mark = (
            X2_ENABLED
            and container is not None
            and len(el["text"]) <= 3
            and r["w"] < X2_MAX_CONTAINER
            and r["h"] < X2_MAX_CONTAINER
            and container["rect"]["w"] <= X2_MAX_CONTAINER
            and container["rect"]["h"] <= X2_MAX_CONTAINER
        )
        if is_mark:
            creg = crop(img, container["rect"], scale)
            if creg is not None:
                shape, _field, ink = paint(creg, field_rgb, fg)
                shape_frac = float(shape.mean())
                ink_frac = float(ink.sum()) / max(1, int(shape.sum()))
                if (
                    shape_frac >= X2_MIN_SHAPE_FRAC
                    and 0 < ink_frac <= X2_MAX_INK_FRAC
                    and ink.sum() >= 16
                ):
                    census["xcheck-optical-centre"] += 1
                    ys, xs = np.nonzero(ink)
                    dx = xs.mean() / scale - (creg.shape[1] / scale) / 2
                    dy = ys.mean() / scale - (creg.shape[0] / scale) / 2
                    if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                        comp = el["styles"].get("transform", "none")
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"the mark's rendered ink sits {abs(dx):.1f}px "
                            f"{'left' if dx < 0 else 'right'} and {abs(dy):.1f}px "
                            f"{'up' if dy < 0 else 'down'} of the centre of "
                            f"{container['path']}, the {container['rect']['w']:.0f}x"
                            f"{container['rect']['h']:.0f}px container that centres "
                            f"it -- it will read as misaligned however correct the "
                            f"CSS is (its own transform is {comp})",
                            container=container["path"],
                            offset_px={
                                "dx": round(float(dx), 2),
                                "dy": round(float(dy), 2),
                            },
                        )

        # --- X3: what is actually behind the glyphs, over the glyphs' own span --
        if el["text"] and len(el["text"]) > 3 and fg:
            region = crop(img, r, scale)
            if region is None:
                continue
            ink = near(region, fg, INK_TOL)
            cols = np.flatnonzero(ink.any(axis=0))
            if cols.size < 2 * MIN_BOX or ink.sum() < 24:
                continue  # not enough rendered text to say anything about
            census["xcheck-contrast"] += 1
            lo, hi = int(cols[0]), int(cols[-1])
            span = hi - lo + 1
            half = max(1, span // 2)
            ends = {
                "left": (slice(lo, lo + half), ink[:, lo : lo + half]),
                "right": (slice(hi + 1 - half, hi + 1), ink[:, hi + 1 - half : hi + 1]),
            }
            sampled, ratios = {}, {}
            for side, (sl, side_ink) in ends.items():
                band = region[:, sl]
                backdrop = band[~side_ink]
                if backdrop.size < 3 * band.shape[0]:
                    sampled = {}
                    break
                med = np.median(backdrop.reshape(-1, 3), axis=0)
                sampled[side] = med
                ratios[side] = contrast(fg[:3], med)
            if not sampled:
                continue

            size = float(str(el["styles"].get("font-size", "0")).replace("px", "") or 0)
            weight = el["styles"].get("font-weight", "400")
            large = size >= 24 or (
                size >= 18.66 and weight in ("700", "bold", "800", "900")
            )
            need = CONTRAST_MIN_LARGE if large else CONTRAST_MIN
            worst_side = min(ratios, key=lambda s: ratios[s])
            worst = ratios[worst_side]
            spread = abs(ratios["left"] - ratios["right"])
            measured = {
                "left": round(ratios["left"], 2),
                "right": round(ratios["right"], 2),
                "requirement": need,
                "ink_span_px": round(span / scale, 1),
                "box_w_px": round(r["w"], 1),
            }

            # What the CASCADE says about the same text, asked with the DOM
            # layer's own resolver. A comparator has to have both answers.
            cascade_bg, why = pg.backdrop(el)

            if cascade_bg is not None:
                # The DOM has a number. Then this arm's job is DISAGREEMENT, and
                # only that: where both layers say the same thing the DOM layer
                # has already reported it, and a second copy of a finding spends
                # the same credibility as a wrong one.
                computed = contrast(fg[:3], cascade_bg)
                if abs(computed - worst) > CONTRAST_DELTA:
                    rep(
                        "xcheck-contrast-mismatch",
                        el["path"],
                        f"the cascade computes {computed:.2f}:1 against "
                        f"{hexof(cascade_bg)}, but the pixels behind the glyphs "
                        f"give {worst:.2f}:1 at the {worst_side} end. Something "
                        f"between the two -- a blend mode, a filter, a backdrop "
                        f"filter, an overlay -- is repainting this text after the "
                        f"styles were resolved, and {'the render' if worst < computed else 'the cascade'} "
                        f"is the pessimistic one",
                        "high" if worst < need else "medium",
                    )
                continue

            # The DOM abstained. Now this arm is the ONLY layer that can answer,
            # and it answers from a measurement taken at the glyphs themselves --
            # never from a scalar the compositor sampled at one point, which is
            # what would turn an honest INDETERMINATE into a confident false PASS.
            resolved = {
                "rule": "contrast-indeterminate",
                "target": el["path"],
                "verdict": "fail" if worst < need else "pass",
                "because": why,
                "measured": measured,
            }
            if worst < need:
                rep(
                    "xcheck-contrast-real",
                    el["path"],
                    f"sampled behind the glyphs themselves, this text runs "
                    f"{ratios['left']:.2f}:1 at its left end and "
                    f"{ratios['right']:.2f}:1 at its right, against {need}:1 "
                    f"required; the {worst_side} end fails a reader. The cascade "
                    f"could not produce this number at all -- {why}",
                    "high",
                    resolves=resolved,
                )
            elif spread > CONTRAST_DELTA:
                rep(
                    "xcheck-contrast-varies",
                    el["path"],
                    f"contrast is not one number across this text: "
                    f"{ratios['left']:.2f}:1 at the left end and "
                    f"{ratios['right']:.2f}:1 at the right. Both clear {need}:1, so "
                    f"this is a robustness note rather than a failure -- a longer "
                    f"string, or a translation, reaches the pale end",
                    "low",
                    resolves=resolved,
                )
            else:
                # Nothing to report, but the abstention is still answered, and an
                # answered question must not look like an unasked one.
                out.append(
                    {
                        "rule": "xcheck-contrast-ok",
                        "target": el["path"],
                        "detail": (
                            f"resolved: {worst:.2f}:1 at worst over the glyphs' own "
                            f"{span / scale:.0f}px span, against {need}:1 required"
                        ),
                        "severity": "info",
                        "resolves": resolved,
                    }
                )
    return out, census


def run(corpus: pathlib.Path) -> tuple[dict, dict]:
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    results, censuses = {}, {}
    for f in sorted(snaps.glob("*.json")):
        png = shots / f"{f.stem}.png"
        if not png.exists():
            continue
        results[f.stem], censuses[f.stem] = check(json.loads(f.read_text()), png)
    return results, censuses


def main(corpus: pathlib.Path) -> None:
    results, censuses = run(corpus)
    (corpus / "findings_xcheck.json").write_text(json.dumps(results, indent=1))
    (corpus / "census_xcheck.json").write_text(json.dumps(censuses, indent=1))

    def loud(fs):
        return [f for f in fs if f["severity"] != "info"]

    ctrl = loud(results.get("clean", []))
    print(f"CONTROL clean.html -> {len(ctrl)} finding(s){'' if ctrl else '  (quiet)'}")
    for c in ctrl:
        print(f"    [{c['rule']}] {c['target']}: {c['detail'][:100]}")
    print()
    base = {(c["rule"], c["target"]) for c in ctrl}
    for name, fs in sorted(results.items()):
        if name == "clean":
            continue
        novel = [f for f in loud(fs) if (f["rule"], f["target"]) not in base]
        if not novel:
            continue
        print(f"{name}")
        for f in novel:
            print(f"    [{f['rule']:24}] {f['detail'][:150]}")

    n = sum(1 for fs in results.values() for f in fs if f.get("resolves"))
    print(f"\nabstentions resolved by the cross-check: {n}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(pathlib.Path(args[0] if args else "corpus/out").resolve())
