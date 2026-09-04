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
  X2 ink-centroid    the rendered ink of a small mark is not centred in the
                     CONTAINER that centres it. Both defects found when this arm
                     was first validated are now fixed, and both are recorded
                     because each is a shape of error that will recur:
                     (a) it compared ink to the element's OWN box, and
                     getBoundingClientRect returns the POST-transform box, so any
                     translate moved box and ink together and the measured offset
                     was INVARIANT under the very compensation it should verify.
                     FIXED: the offset is measured against the container's box,
                     which no transform on the child moves.
                     (b) its background was the crop's modal colour, so on a
                     round button the square crop's corners -- page background
                     outside the circle -- counted as ink and swamped a 16px
                     glyph. FIXED: `inkmask.painted_shape` floods in from the
                     border and measures only inside the shape that was painted.
                     What the fixes did NOT buy is the vertical axis: a text
                     glyph's ink sits where its font's baseline puts it, so a
                     vertical offset from the container's centre is a font fact
                     and not a defect. That axis ABSTAINS, by name, rather than
                     reporting the true-but-meaningless number -- measured on the
                     control, it is +3.23px and would have been this arm's first
                     false positive.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.
                     🚨 Its first implementation sampled the modal colour of each
                     band, and on the one page it exists for that mode is the
                     TEXT: a gradient repeats no colour, so 120 identical white
                     glyph pixels outvoted 6,224 unique backdrop ones and the arm
                     measured white against white, found no variation, and
                     reported nothing. It read as a clean page. Fixed by
                     `inkmask.backdrop_of` (drop the known foreground, take the
                     median). Recorded because a detector that fails by falling
                     SILENT is the failure mode this whole substrate is built to
                     refuse, and it shipped here anyway.

Every finding carries a three-valued `verdict` (PIPELINE_SPEC §1.4): FAIL when
the measurement ran and landed outside its band, INDETERMINATE when a
precondition did not hold so no measurement exists. An INDETERMINATE carries
`routeTo`, and that field is the routing layer's entire input -- see `route.py`.

Usage: python3 detect_xcheck.py <corpus-dir> [--no-x2]
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image

import inkmask

# Tolerances are stated, not tuned. Each is well above sub-pixel rounding and
# well below what a person would call "off", so a finding means a real gap.
INK_MIN_FRAC = (
    0.002  # below this share of non-background pixels, the box paints nothing
)
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# X2's subject population: a small mark inside a small container. Both bounds are
# statements about what "optically centred" even means -- it is a claim about a
# mark in a frame, and neither a paragraph nor a page section is one.
X2_MARK_MAX = 64.0
X2_CONTAINER_MAX = 96.0
# X2 ships ON. It earned that by clearing the gate every rule must clear: zero
# findings on the control, and the injected defect caught at its stated magnitude
# (measured 2026-09-04: control 0.00px, optical-centering -2.00px against a
# derived band of 1.25px). `--no-x2` is for bisecting a run, not for policy.
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
    band = inkmask.band_px(scale)
    by_path = {e["path"]: e for e in snap["elements"]}
    out = []

    def parent_of(el):
        head = el["path"].rsplit(" > ", 1)
        return by_path.get(head[0]) if len(head) > 1 else None

    def rep(rule, target, detail, severity="medium", verdict="FAIL", route_to=None):
        f = {
            "rule": rule,
            "target": target,
            "detail": detail,
            "severity": severity,
            "verdict": verdict,
        }
        if route_to:
            f["routeTo"] = route_to
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

        # --- X2: ink is not centred in the CONTAINER that centres it -----------
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows.
        parent = parent_of(el)
        is_mark = (
            X2_ENABLED
            and len(el["text"]) <= 3
            and r["w"] < X2_MARK_MAX
            and r["h"] < X2_MARK_MAX
            and parent is not None
            and parent["rect"]["w"] < X2_CONTAINER_MAX
            and parent["rect"]["h"] < X2_CONTAINER_MAX
        )
        if is_mark:
            # Measured against the CONTAINER. The child's own box is post-
            # transform, so ink and box move together and the offset this arm
            # exists to find is invariant inside it. The container does not move.
            frame = crop(img, parent["rect"], scale)
            shape, _, why = (
                inkmask.painted_shape(frame)
                if frame is not None
                else (None, None, "container-too-small")
            )
            if shape is None:
                rep(
                    "xcheck-optical-centre",
                    el["path"],
                    f"cannot separate this mark's ink from its container: {why}. "
                    f"Optical centring is UNVERIFIED here",
                    "low",
                    verdict="INDETERMINATE",
                    route_to="optical-alignment",
                )
            else:
                # The shape's antialiased rim blends fill into backdrop and would
                # otherwise read as a ring of false ink centred exactly where the
                # real ink is. Erode ceil(scale)+1 device px: one for the rim,
                # which is one device pixel wide by construction of the
                # rasteriser, and one for the stair-step residue a discrete
                # erosion leaves on a curve. Measured convergence, both DPRs:
                # k=1 still carries rim (control reads +0.45px), k=2/3/4 are
                # identical to the hundredth of a pixel. A depth past convergence
                # costs nothing but ink pixels; a depth short of it biases every
                # centroid towards the shape's own centre, which is the direction
                # that HIDES this defect.
                core = inkmask.erode(shape, int(np.ceil(scale)) + 1)
                mark_ink, _ = inkmask.ink_within(frame, core)
                c = inkmask.centroid(mark_ink)
                if c is None:
                    rep(
                        "xcheck-optical-centre",
                        el["path"],
                        "the container paints a shape but no mark inside it; "
                        "nothing to centre",
                        "low",
                        verdict="INDETERMINATE",
                        route_to="optical-alignment",
                    )
                else:
                    dx = (c[0] - frame.shape[1] / 2) / scale
                    dy = (c[1] - frame.shape[0] / 2) / scale
                    if abs(dx) > band:
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"the container centres this mark exactly, but its rendered "
                            f"ink mass sits {abs(dx):.2f}px "
                            f"{'left' if dx < 0 else 'right'} of the container's centre "
                            f"(band {band:.2f}px) -- it will read as misaligned however "
                            f"correct the CSS is",
                        )
                    # The vertical axis is NOT symmetric with the horizontal one.
                    # A glyph's ink sits where its font's ascent and descent put
                    # it inside the line box, so a vertical offset is a property
                    # of the typeface, not of the layout. Measured on the control
                    # with this font: +3.23px, which is real, correct, and not a
                    # defect. Reporting it would have been this arm's first false
                    # positive; the honest output is that the axis is unmeasured.
                    if el["text"] and abs(dy) > band:
                        rep(
                            "xcheck-optical-centre-v",
                            el["path"],
                            f"vertical ink offset is {dy:+.2f}px, but this mark is a "
                            f"text glyph and its vertical ink position is set by the "
                            f"font's baseline metrics, which no artifact here carries. "
                            f"Vertical centring is UNVERIFIED",
                            "low",
                            verdict="INDETERMINATE",
                            route_to="optical-alignment",
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text, separately in the left
            # and right thirds so a backdrop that VARIES across the run cannot
            # hide behind a single average. `backdrop_of` drops the known
            # foreground first and takes the median of what is left -- the mode
            # of a band on a gradient is the text, which is how this arm came to
            # be silently dead. See the X3 note in the docstring.
            w = region.shape[1]
            thirds = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled, frac_ok = {}, True
            for side, strip in thirds.items():
                col, bg_frac = inkmask.backdrop_of(strip, fg)
                if col is None:
                    rep(
                        "xcheck-contrast-varies",
                        el["path"],
                        f"only {bg_frac * 100:.0f}% of this text's {side} third is "
                        f"backdrop; too little to sample a colour behind it. The "
                        f"rendered contrast is UNVERIFIED",
                        "medium",
                        verdict="INDETERMINATE",
                        route_to="readability",
                    )
                    frac_ok = False
                    break
                sampled[side] = col
            if not frac_ok:
                continue
            cl = contrast(fg[:3], sampled["left"])
            cr = contrast(fg[:3], sampled["right"])
            if abs(cl - cr) > CONTRAST_DELTA:
                lo_side = "left" if cl < cr else "right"
                rep(
                    "xcheck-contrast-varies",
                    el["path"],
                    f"contrast is not one number across this text: {cl:.2f}:1 across "
                    f"its left third and {cr:.2f}:1 across its right. Any single "
                    f"computed value is a fiction, and the {lo_side} end is the one "
                    f"that fails a reader",
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

    # A FAIL on the control and an INDETERMINATE on the control are different
    # events and must never be summed. The first says a rule invents defects and
    # is disqualifying; the second says a rule knows what it cannot see, which is
    # the property this whole layer is built for. Printing one number for both is
    # how an honest abstention gets mistaken for noise and deleted.
    ctrl = results.get("clean", [])
    fails = [c for c in ctrl if c.get("verdict", "FAIL") == "FAIL"]
    absts = [c for c in ctrl if c.get("verdict") == "INDETERMINATE"]
    print(
        f"CONTROL clean.html -> {len(fails)} FAIL"
        f"{'  <-- false positive, this arm does not ship' if fails else '  (quiet)'}"
        f" · {len(absts)} abstention(s) -> the vision queue"
    )
    for c in ctrl:
        print(f"    [{c.get('verdict', 'FAIL')[:4]} {c['rule']}] {c['detail'][:88]}")
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
