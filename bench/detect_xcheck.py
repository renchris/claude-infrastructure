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
  X2 ink-centroid    BOTH DOCUMENTED DEFECTS ARE FIXED (2026-09-01); it now
                     measures against the CONTAINER and masks to the PAINTED
                     SHAPE, and it emits an abstention rather than a verdict.
                     Both defects were reproduced live on the corpus before the
                     fix, and the reproduction is the reason to trust the fix:
                     (a) INVARIANCE. It compared ink to the element's OWN box,
                     and getBoundingClientRect returns the POST-transform box, so
                     a translate moved box and ink together. Measured: span.glyph
                     reported ink at (3.91, 9.23) against a box centre of
                     (6.00, 8.00) on clean.html AND on optical-centering.html --
                     identical to two decimal places, with the compensating
                     translate present in one and absent in the other. The
                     measurement was exactly invariant under the thing it existed
                     to verify.
                     (b) SWAMPING. Its background was the crop's modal colour, so
                     on a 44px round button the square crop's corners -- page
                     background outside the r=22px circle -- counted as ink.
                     Measured: ink fraction 0.290, of which the corners are
                     0.215, i.e. the page background outside the shape carried
                     ~74% of the "ink" and the 16px glyph carried the rest.
                     THE FIX. Ink is measured inside an analytic rounded-rect
                     mask built from the container's own rect and border-radius
                     (the DOM supplies geometry, the pixels supply ink -- the
                     governing rule) and its centroid is compared to the MASK's
                     centroid. On the corpus this recovers the injected magnitude
                     exactly: dx +0.50px on clean against -1.50px on
                     optical-centering, a delta of 2.00px against a translate of
                     exactly 2px, and ink fraction inside the mask falls from
                     0.290 to 0.065 -- the glyph alone.
                     WHAT IT MAY ASSERT. Nothing, almost always, and that is the
                     third defect the first two fixes exposed. The offset has no
                     font-independent zero: the same glyph at the same size is
                     3.7px low on this Linux renderer and 1.9px high on the macOS
                     Helvetica the corpus was authored against, so any absolute
                     threshold encodes a font rather than a defect. X2 therefore
                     emits verdict INDETERMINATE carrying the two numbers, which
                     is a routing input, not a finding; it asserts only when the
                     centroid has moved further from the container's centre than
                     the mark's own ink half-extent -- a bound no glyph metric can
                     explain, because at that point the mark no longer straddles
                     the centre at all.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.
                     🚨 Its sampler was renderer-dependent and shipped silent
                     (fixed 2026-09-01). It took the modal colour of each third,
                     which on white-on-gradient hero text is the TEXT'S OWN WHITE
                     -- measured [255,255,255] in the left third of
                     contrast-on-gradient.html, so the arm compared white to
                     white, computed a 0.28 spread against a 1.5 tolerance, and
                     reported nothing. The documented 4.81/1.57 result held only
                     on the renderer it was written against. It now excludes
                     pixels near the declared foreground and takes the MEDIAN of
                     what remains, which is stable under a smooth gradient. This
                     is validated in both directions: on the solid control it
                     recovers rgb(29,78,216) = the authored #1D4ED8 exactly, and
                     on contrast-plain it reproduces the cascade's own 2.54:1 and
                     stays correctly silent because there is no disagreement.

Every finding carries a `verdict`: `asserted` (a claim about the page) or
`indeterminate` (a measured quantity with no verdict attached, which is the
router's queue). The false-positive ship gate counts only `asserted`.

Usage: python3 detect_xcheck.py <corpus-dir>
"""

from __future__ import annotations

import collections
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
CENTROID_TOL_PX = 1.0  # ink centroid vs the container mask's centroid
CONTRAST_DELTA = 1.5  # ratio points between the left and right samples
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
INK_DIST = 40  # channel-sum distance from the surface colour that counts as ink
FG_DIST = 90  # channel-sum distance from the declared colour that is NOT ink
MARK_MAX_CHARS = 3  # a "mark": a glyph or an icon character, not a word
CONTAINER_MAX_PX = 96  # a control-sized affordance, not a layout region
MASK_ERODE_PX = 1.0  # drop the antialiased boundary ring: neither surface nor ink
# X2 stays behind a flag because the ratified build order puts "X2 centroid ON by
# default" on its Cut list. The flag now gates a validated measurement rather
# than an unvalidated one, and what it emits is an abstention -- so turning it on
# adds routing volume, never an assertion.
X2_ENABLED = "--x2" in sys.argv


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


def px(v) -> float:
    try:
        return float(str(v).replace("px", "").strip())
    except (ValueError, AttributeError):
        return 0.0


def shape_mask(rect: dict, radius: float, scale: float) -> np.ndarray:
    """The element's PAINTED shape, as a boolean mask in device pixels.

    Built analytically from the DOM's own rect and border-radius rather than
    guessed from the pixels. That is the governing rule of this whole pipeline in
    one function: the DOM supplies geometry, which it knows exactly and for free,
    and the pixels are asked only what colour is where. A pixel-derived shape
    estimate would reintroduce precisely the guess this check exists to remove.

    Inset by MASK_ERODE_PX because the antialiased boundary ring is a blend of the
    surface and whatever is behind the element -- it is neither, and counting it
    as ink is defect (b) in miniature.
    """
    w = int(round(rect["w"] * scale))
    h = int(round(rect["h"] * scale))
    if w < MIN_BOX or h < MIN_BOX:
        return np.zeros((max(h, 0), max(w, 0)), bool)
    r = min(radius * scale, w / 2.0, h / 2.0)
    yy, xx = np.mgrid[0:h, 0:w]
    cx, cy = xx + 0.5, yy + 0.5
    e = MASK_ERODE_PX
    inside = (cx >= e) & (cx <= w - e) & (cy >= e) & (cy <= h - e)
    if r > 0:
        for ox, oy, sx, sy in (
            (r, r, -1, -1),
            (w - r, r, 1, -1),
            (r, h - r, -1, 1),
            (w - r, h - r, 1, 1),
        ):
            corner = (sx * (cx - ox) > 0) & (sy * (cy - oy) > 0)
            inside &= ~(corner & (np.hypot(cx - ox, cy - oy) > r - e))
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


def check(snap: dict, png: pathlib.Path, stats: dict | None = None) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    out = []
    subject_checks = 0

    def rep(rule, target, detail, severity="medium", verdict="asserted", facts=None):
        out.append(
            {
                "rule": rule,
                "target": target,
                "detail": detail,
                "severity": severity,
                # `asserted` is a claim about the page and counts against the
                # false-positive gate. `indeterminate` is a measured quantity with
                # no verdict attached; it is the abstention router's queue, and an
                # abstention on a clean page is correct behaviour, not a miss.
                "verdict": verdict,
                "layer": "xcheck",
                "facts": facts or {},
            }
        )

    by_path = {e["path"]: e for e in snap["elements"]}
    children = collections.defaultdict(list)
    for e in snap["elements"]:
        parent = e["path"].rsplit(" > ", 1)
        if len(parent) > 1 and parent[0] in by_path:
            children[parent[0]].append(e)

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
        subject_checks += 1
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

        # --- X2: the mark's ink is not centred in its CONTAINER ----------------
        # The subject is the CONTAINER, not the mark. Measuring the mark against
        # its own box is defect (a): getBoundingClientRect is post-transform, so
        # the compensating translate moves box and ink together and the answer
        # cannot change. The container does not move, so it is the only frame in
        # which the compensation is observable at all.
        #
        # Restricted to a container whose single element child is a short mark,
        # because a centroid only means "where the mark sits" when the mark is the
        # only thing painted. A container with two children has a centroid that is
        # a fact about their layout, and this check would be reading it as a fact
        # about optical centring.
        kids = children.get(el["path"], [])
        mark = kids[0] if len(kids) == 1 else None
        is_marked_container = (
            X2_ENABLED
            and mark is not None
            and mark["text"]
            and len(mark["text"]) <= MARK_MAX_CHARS
            and not el["text"]
            and r["w"] <= CONTAINER_MAX_PX
            and r["h"] <= CONTAINER_MAX_PX
        )
        if is_marked_container:
            subject_checks += 1
            mask = shape_mask(r, px(el["styles"].get("border-radius")), scale)
            mreg = img[
                max(0, int(round(r["y"] * scale))) : max(0, int(round(r["y"] * scale)))
                + mask.shape[0],
                max(0, int(round(r["x"] * scale))) : max(0, int(round(r["x"] * scale)))
                + mask.shape[1],
            ]
            if mask.any() and mreg.shape[:2] == mask.shape:
                inside = mreg[mask]
                mv, mc = np.unique(inside, axis=0, return_counts=True)
                surface = mv[mc.argmax()]
                mdist = np.abs(mreg.astype(np.int32) - surface.astype(np.int32)).sum(
                    axis=2
                )
                mink = (mdist > INK_DIST) & mask
                if mink.any():
                    iy, ix = np.nonzero(mink)
                    my, mx = np.nonzero(mask)
                    dx = (ix.mean() - mx.mean()) / scale
                    dy = (iy.mean() - my.mean()) / scale
                    # Font-independent bound. The mark's own half-extent is the
                    # largest offset any glyph metric can account for: past it the
                    # ink no longer straddles the container's centre, which is not
                    # a typographic nicety but a placement error. Inside it, the
                    # honest answer is a number and no verdict -- the same glyph is
                    # 3.7px low on this renderer and 1.9px high on the one the
                    # corpus was authored against.
                    hx = (ix.max() - ix.min() + 1) / (2 * scale)
                    hy = (iy.max() - iy.min() + 1) / (2 * scale)
                    facts = {
                        "offset_x_px": round(dx, 2),
                        "offset_y_px": round(dy, 2),
                        "mark_half_extent_px": [round(hx, 2), round(hy, 2)],
                        "ink_fraction_in_shape": round(
                            float(mink.sum()) / float(mask.sum()), 4
                        ),
                        "container_shape": f"{r['w']:.0f}x{r['h']:.0f}px "
                        f"r={px(el['styles'].get('border-radius')):g}px",
                    }
                    where = (
                        f"{abs(dx):.2f}px {'left' if dx < 0 else 'right'} and "
                        f"{abs(dy):.2f}px {'up' if dy < 0 else 'down'} of the centre "
                        f"of the shape its container paints"
                    )
                    if abs(dx) > hx or abs(dy) > hy:
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"the rendered ink of {mark['text']!r} sits {where}, which "
                            f"is further than the mark's own half-extent "
                            f"({hx:.1f}x{hy:.1f}px) -- it does not straddle the centre "
                            f"at all, so no glyph metric explains this",
                            "medium",
                            verdict="asserted",
                            facts=facts,
                        )
                    elif abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                        rep(
                            "xcheck-optical-centre-indeterminate",
                            el["path"],
                            f"the rendered ink of {mark['text']!r} sits {where}. "
                            f"Whether that reads as centred is a judgement about this "
                            f"glyph at this size, and there is no font-independent "
                            f"zero to compare it against -- UNVERIFIED",
                            "medium",
                            verdict="indeterminate",
                            facts=facts,
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            subject_checks += 1
            # Sample the actual backdrop under the text, separately in the left and
            # right thirds so a backdrop that VARIES across the run cannot hide
            # behind a single average.
            #
            # Exclude pixels near the DECLARED foreground first, then take the
            # median of what remains. The modal colour of a band is the text's own
            # ink whenever the glyphs outnumber any single backdrop shade, which is
            # exactly what happens to white text on a gradient -- and it fails
            # SILENTLY, comparing the foreground against itself for a spread of
            # 0.00. The median of the non-ink pixels is stable under a smooth
            # gradient and degrades to the exact colour on a solid one.
            w = region.shape[1]
            d_fg = np.abs(
                region.astype(np.int32) - np.array(fg[:3], dtype=np.int32)
            ).sum(axis=2)
            not_ink = d_fg > FG_DIST
            bands = {
                "left": (region[:, : w // 3], not_ink[:, : w // 3]),
                "right": (region[:, -(w // 3) :], not_ink[:, -(w // 3) :]),
            }
            sampled = {}
            for side, (band, keep) in bands.items():
                if keep.sum() < 20:
                    sampled = {}
                    break
                sampled[side] = np.median(band[keep], axis=0)
            if not sampled:
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
                    facts={
                        "contrast_left": round(cl, 2),
                        "contrast_right": round(cr, 2),
                        "resolves": "contrast-indeterminate",
                    },
                )
    if stats is not None:
        stats["subject_checks"] = subject_checks
        stats["elements"] = len(snap["elements"])
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
    ctrl_asserted = [c for c in ctrl if c["verdict"] == "asserted"]
    ctrl_abstain = [c for c in ctrl if c["verdict"] != "asserted"]
    print(
        f"CONTROL clean.html -> {len(ctrl_asserted)} asserted"
        f"{'  <-- FALSE POSITIVE, the ship gate is zero' if ctrl_asserted else '  (quiet)'}"
        f", {len(ctrl_abstain)} abstention(s)"
    )
    for c in ctrl:
        print(f"    [{c['verdict']:13}] [{c['rule']}] {c['detail'][:80]}")
    print()
    # The key spans the CLAIM, not just its location. Keying on (rule, target)
    # alone is the dedup bug the README records at 0/1 -> 1/1: X2's whole output
    # is the same rule on the same target with a different number, so a 2-tuple
    # baseline suppresses the defect page using the control's own abstention.
    base = {(c["rule"], c["target"], c["detail"]) for c in ctrl}
    for name, fs in sorted(results.items()):
        if name == "clean":
            continue
        novel = [f for f in fs if (f["rule"], f["target"], f["detail"]) not in base]
        if not novel:
            continue
        print(f"{name}")
        for f in novel:
            print(f"    [{f['verdict']:13}] [{f['rule']:38}] {f['detail'][:110]}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(pathlib.Path(args[0] if args else "corpus/out").resolve())
