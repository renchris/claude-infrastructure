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
  X2 ink-centroid    PROVISIONAL, OFF BY DEFAULT (--x2 to enable). The two defects
                     the 2026-08-26 wave recorded are FIXED here; a third, which
                     only became visible once they were, is why it is still off.
                     See "The X2 repair" below.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

--- The X2 repair -------------------------------------------------------------

Recorded as known-broken and unfixed on 2026-08-26:

  (a) it compared ink to the element's OWN box, and getBoundingClientRect returns
      the POST-transform box, so a translate moves box and ink together and the
      measured offset was INVARIANT under the very compensation it should verify;
  (b) its background was the crop's modal colour, so on a round button the square
      crop's corners -- page background outside the circle -- counted as ink and
      swamped a 16px glyph.

Both are fixed, and both fixes are checkable against the corpus rather than
asserted. (a) is now measured against the CONTAINER that makes the centring claim,
so `clean` and `optical-centering` -- identical but for `transform: none` --
finally read differently: they used to produce the byte-identical finding.
(b) is now an analytic rounded-rect mask built from the container's own
`border-radius` plus an ink test against the element's DECLARED colour, so ink
falls from ~340 corner-and-rim pixels to the 65 that are actually the glyph.

**The third defect, which the repair exposed.** With the quantity finally correct,
the control does not read zero: the corpus's optical compensation is
`translate(2px, 2px)`, hand-measured on macOS/Helvetica, and on a host that
substitutes Liberation Sans the true compensation is ~3.3px horizontal and ~0
vertical. So the "clean" page carries a real ~2.4px optical error of its own, and
any absolute threshold that separates it from the injected defect is a constant
tuned to one machine's font stack. This is the README's own §1 lesson recurring:
a control is not clean until something disagrees with it. X2 therefore stays off,
and `fp_budget.py` states the cost as a number rather than a suspicion.

Usage: python3 detect_xcheck.py <corpus-dir> [--x2]
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
CENTROID_TOL_PX = 1.0  # ink centre vs the centre of the box that claims to centre it
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# How close a pixel must be to the DECLARED foreground colour, per channel, to
# count as that element's ink. Generous enough to keep antialiased glyph edges,
# tight enough to reject a fill/background blend.
INK_TOL = 40
# Antialiasing paints a ~1px rim along a rounded edge that is neither the fill
# nor the page behind it. Eroding the shape mask by more than that rim drops it
# rather than letting it vote on a centroid.
INK_EDGE_INSET_PX = 1.5
# Below this many backdrop pixels a third is mostly ink, and its "backdrop"
# would be an artefact of the glyph coverage. Abstain instead of reporting one.
MIN_BACKDROP_PX = 24
X2_ENABLED = "--x2" in sys.argv  # provisional; see "The X2 repair" in the docstring

CENTRING_DISPLAYS = ("flex", "inline-flex", "grid", "inline-grid")


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


def rounded_rect_mask(shape, box, radius: float, inset: float = 0.0) -> np.ndarray:
    """Analytic membership in a rounded rect, eroded by `inset`. All in device px.

    `box` is (ox, oy, w, h) relative to the crop origin, so the caller can pass a
    box whose true edges fall between pixel centres without rounding them first.

    The clamped-distance form is used rather than four explicit corner circles
    because the corner centres COLLIDE when radius == w/2 == h/2 -- exactly the
    pill/circle case X2 is about -- and a per-corner formulation then silently
    leaves half the shape unmasked. That is the shape of bug (b) above, one layer
    down, so it is worth not re-introducing while fixing it.
    """
    ox, oy, w, h = box
    w, h = w - 2 * inset, h - 2 * inset
    if w <= 0 or h <= 0:
        return np.zeros(shape, bool)
    r = max(min(radius - inset, w / 2, h / 2), 0.0)
    yy, xx = np.mgrid[0 : shape[0], 0 : shape[1]]
    x = xx + 0.5 - (ox + inset)
    y = yy + 0.5 - (oy + inset)
    inside = (x >= 0) & (x <= w) & (y >= 0) & (y <= h)
    dx = np.maximum(np.maximum(r - x, x - (w - r)), 0.0)
    dy = np.maximum(np.maximum(r - y, y - (h - r)), 0.0)
    return inside & (dx * dx + dy * dy <= r * r)


def ink_of(region: np.ndarray, fg) -> np.ndarray:
    """Pixels that are this element's DECLARED colour, within INK_TOL per channel.

    X2 and X3 both need to know WHERE the known ink is, so they take the colour
    from the DOM rather than inferring it. X1 deliberately does not: it asks
    whether there is any ink at all, and an element whose text colour equals its
    backdrop -- the case X1 exists for -- would come back 100% ink under this test
    and 0% under a backdrop-relative one. Same word, two different questions.
    """
    return np.abs(region - np.asarray(fg[:3], dtype=np.int32)).max(axis=2) <= INK_TOL


def centring_parent(el: dict, by_path: dict):
    """The ancestor box whose computed style CLAIMS to centre this element.

    X2 is a cross-check, so it needs a DOM claim to contradict. `display:flex` with
    both axes centred is that claim, stated in values rather than inferred from
    geometry. No such ancestor means no claim, which means nothing to cross-check
    and an abstention rather than a bare pixel statistic.
    """
    parts = el["path"].rsplit(" > ", 1)
    if len(parts) < 2:
        return None
    p = by_path.get(parts[0])
    if p is None:
        return None
    st = p["styles"]
    if st.get("display", "") not in CENTRING_DISPLAYS:
        return None
    if "center" not in st.get("align-items", ""):
        return None
    if "center" not in st.get("justify-content", ""):
        return None
    return p


def check(snap: dict, png: pathlib.Path) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int32)
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
        fg = parse_rgb(el["styles"].get("color", ""))

        # --- X1: the DOM says there is an element here; the pixels say nothing --
        # Backdrop-relative on purpose -- see ink_of()'s docstring.
        if el["text"]:
            flat = region.reshape(-1, 3)
            vals, counts = np.unique(flat, axis=0, return_counts=True)
            bg = vals[counts.argmax()]
            frac = float((np.abs(region - bg).sum(axis=2) > 40).mean())
            if frac < INK_MIN_FRAC:
                rep(
                    "xcheck-zero-ink",
                    el["path"],
                    f"box is {r['w']:.0f}x{r['h']:.0f}px and carries text "
                    f"{el['text'][:24]!r}, but only {frac * 100:.2f}% of its pixels "
                    f"differ from its own background -- it paints nothing a reader "
                    f"can see",
                    "high",
                )
                continue

        # --- X2: ink is not centred in the box that CLAIMS to centre it ---------
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows.
        container = centring_parent(el, by_path) if X2_ENABLED and fg else None
        if (
            container is not None
            and len(el["text"]) <= 3
            and container["rect"]["w"] < 96
            and container["rect"]["h"] < 96
        ):
            cr = container["rect"]
            # The CONTAINER's box, not the element's -- the element's is
            # post-transform and moves with the ink it is supposed to measure.
            cx0, cy0 = int(np.floor(cr["x"] * scale)), int(np.floor(cr["y"] * scale))
            cx1 = int(np.ceil(cr["right"] * scale))
            cy1 = int(np.ceil(cr["bottom"] * scale))
            creg = img[max(0, cy0) : cy1, max(0, cx0) : cx1]
            if creg.size and creg.shape[0] >= MIN_BOX and creg.shape[1] >= MIN_BOX:
                shape_mask = rounded_rect_mask(
                    creg.shape[:2],
                    (
                        cr["x"] * scale - cx0,
                        cr["y"] * scale - cy0,
                        cr["w"] * scale,
                        cr["h"] * scale,
                    ),
                    px(container["styles"].get("border-radius")) * scale,
                    INK_EDGE_INSET_PX * scale,
                )
                ink = ink_of(creg, fg) & shape_mask
                if ink.sum() >= 4:
                    ys, xs = np.nonzero(ink)
                    cx = (cx0 + xs.mean() + 0.5) / scale - cr["x"]
                    cy = (cy0 + ys.mean() + 0.5) / scale - cr["y"]
                    dx, dy = cx - cr["w"] / 2, cy - cr["h"] / 2
                    if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"{container['path']} centres this mark on both axes, but "
                            f"its {int(ink.sum())} rendered ink pixels sit "
                            f"{abs(dx):.1f}px {'left' if dx < 0 else 'right'} and "
                            f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'} of that "
                            f"container's centre -- it will read as misaligned however "
                            f"correct the CSS is",
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3 and fg:
            # Sample the actual backdrop under the text, separately in the left and
            # right thirds so a backdrop that VARIES across the run cannot hide
            # behind a single average.
            #
            # The backdrop is the MEDIAN of the pixels that are not this element's
            # declared ink. Both halves of that matter and both are repairs:
            # taking the modal colour of the whole band picked the TEXT on a
            # gradient -- the text is one exact colour repeated, while a gradient
            # is a thousand colours appearing a few times each -- so the check
            # scored contrast(white, white) = 1.0 and stayed silent on the one page
            # it was built for. It only ever fired because Helvetica's antialiasing
            # happened to leave fewer exactly-white pixels than the widest gradient
            # band; on Liberation Sans it does not, and the arm went quiet with no
            # error. A detector whose verdict turns on the host's font stack is not
            # measuring the page.
            ink = ink_of(region, fg)
            w = region.shape[1]
            bands = {
                "left": slice(0, max(1, w // 3)),
                "right": slice(-max(1, w // 3), None),
            }
            sampled, thin = {}, False
            for side, sl in bands.items():
                back = region[:, sl][~ink[:, sl]]
                if len(back) < MIN_BACKDROP_PX:
                    thin = True
                    break
                sampled[side] = np.median(back.reshape(-1, 3), axis=0)
            if thin:
                continue
            cl = contrast(fg[:3], sampled["left"])
            cr_ = contrast(fg[:3], sampled["right"])
            if abs(cl - cr_) > CONTRAST_DELTA:
                lo_side = "left" if cl < cr_ else "right"
                rep(
                    "xcheck-contrast-varies",
                    el["path"],
                    f"contrast is not one number across this text: {cl:.2f}:1 at the "
                    f"left edge and {cr_:.2f}:1 at the right. Any single computed "
                    f"value is a fiction, and the {lo_side} end is the one that "
                    f"fails a reader",
                    "high",
                )
    return out


def run(corpus: pathlib.Path) -> dict:
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    results = {}
    for f in sorted(snaps.glob("*.json")):
        png = shots / f"{f.stem}.png"
        if not png.exists():
            continue
        results[f.stem] = check(json.loads(f.read_text()), png)
    return results


def main(corpus: pathlib.Path) -> None:
    results = run(corpus)
    (corpus / "findings_xcheck.json").write_text(json.dumps(results, indent=1))

    ctrl = results.get("clean", [])
    print(f"CONTROL clean.html -> {len(ctrl)} finding(s){'' if ctrl else '  (quiet)'}")
    for c in ctrl:
        print(f"    [{c['rule']}] {c['target']}: {c['detail'][:100]}")
    print()
    # Keyed on the claim, not just its location -- see fp_budget.py.
    base = {(c["rule"], c["target"], c["detail"]) for c in ctrl}
    for name, fs in sorted(results.items()):
        if name == "clean":
            continue
        novel = [f for f in fs if (f["rule"], f["target"], f["detail"]) not in base]
        if not novel:
            continue
        print(f"{name}")
        for f in novel:
            print(f"    [{f['rule']:24}] {f['detail'][:150]}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(pathlib.Path(args[0] if args else "corpus/out").resolve())
