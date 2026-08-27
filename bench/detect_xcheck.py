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
  X2 ink-centroid    the ink inside a small mark does not sit where the DOM
                     centred it. Both defects the 2026-08-26 review found in this
                     arm are fixed -- see the X2 block below for what was wrong,
                     what the repair measures instead, and why the arm STILL
                     ships behind --x2.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.

Usage: python3 detect_xcheck.py <corpus-dir> [--x2]
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
CENTROID_TOL_PX = 1.0  # ink centre vs the painted container's centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
MARK_MAX = 64  # a "mark" is an icon/glyph container, not a layout box
INK_MIN_MASS = 8.0  # CSS px^2 of ink; below this a centroid is noise


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


def modal(pixels: np.ndarray):
    """Most common colour in an (N,3) array, or None when there is nothing to count.

    Packed to one int per pixel first. `np.unique(..., axis=0)` on an (N,3) array
    lexsorts three columns and is ~50x slower here; on a full-page element at
    dpr 1.5 that is millions of rows, and it took the whole cross-check from
    seconds to a minute per corpus once the arms moved to the higher-DPR capture.
    """
    if len(pixels) == 0:
        return None
    p = pixels.astype(np.int32)
    packed = (p[:, 0] << 16) | (p[:, 1] << 8) | p[:, 2]
    v, c = np.unique(packed, return_counts=True)
    top = int(v[c.argmax()])
    return np.array([(top >> 16) & 255, (top >> 8) & 255, top & 255], dtype=np.int16)


def painted_shape(region: np.ndarray, tol: int = 40) -> np.ndarray | None:
    """The mask of what this box actually PAINTS, as opposed to what it occupies.

    The outside colour is taken from the crop's corners and then flood-filled
    inward FROM THE BORDER. The flood is what makes this geometric rather than
    chromatic, and that distinction is load-bearing: a plain colour test deletes
    every ink pixel that happens to match the page background -- a white glyph on
    a blue button on a white page -- and it deletes them from the SHAPE as well,
    so the reference centre moves with the ink it was supposed to be measured
    against. Measured on this corpus, that alone attenuated a known 2.0px offset
    to 0.6px. Interior pixels are unreachable from the border, so they survive.
    """
    h, w = region.shape[:2]
    corners = np.concatenate(
        [
            region[:2, :2].reshape(-1, 3),
            region[:2, -2:].reshape(-1, 3),
            region[-2:, :2].reshape(-1, 3),
            region[-2:, -2:].reshape(-1, 3),
        ]
    )
    out = modal(corners)
    if out is None:
        return None
    near = np.abs(region - out).sum(axis=2) <= tol
    seen = np.zeros((h, w), bool)
    q = collections.deque()
    border = [(y, x) for y in range(h) for x in (0, w - 1)]
    border += [(y, x) for x in range(w) for y in (0, h - 1)]
    for y, x in border:
        if near[y, x] and not seen[y, x]:
            seen[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return ~seen


def erode(mask: np.ndarray, k: int) -> np.ndarray:
    """Pull the mask in by k pixels, to drop the shape's own antialiased rim.

    The rim differs from the fill exactly the way ink does, it is stationary, and
    on a 44px circle it outweighs a 16px glyph -- so leaving it in dilutes the
    measurement toward zero rather than biasing it in a nameable direction.
    """
    e = mask
    for _ in range(k):
        p = np.pad(e, 1, constant_values=False)
        e = e & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return e


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


def check(
    snap: dict, png: pathlib.Path, x2: bool = False, census: dict | None = None
) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    by_path = {e["path"]: e for e in snap["elements"]}
    out = []
    # Subject-checks, per arm: the denominator a false-positive budget has to be
    # stated over. A rate per RUN says nothing -- one page here carries 47
    # subjects and one real route carries 1,841.
    checked = collections.Counter()

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
        bg = modal(region.reshape(-1, 3))
        dist = np.abs(region.astype(np.int32) - bg.astype(np.int32)).sum(axis=2)
        ink = dist > 40
        frac = float(ink.mean())

        # --- X1: the DOM says there is an element here; the pixels say nothing --
        if el["text"]:
            checked["xcheck-zero-ink"] += 1
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

        # --- X2: ink is not centred in the shape that contains it --------------
        #
        # REPAIRED 2026-08-27. The 2026-08-26 review shipped this arm disabled
        # because validating it found two defects, and both are now closed:
        #
        #   (a) it measured the glyph's ink against the GLYPH's own box, and
        #       getBoundingClientRect returns the POST-transform box -- so the
        #       optical compensation moved box and ink together and the number
        #       was invariant under the very thing it existed to verify. Measured
        #       on this corpus: `span.glyph` reported 2.1px left on all thirteen
        #       pages, compensated and uncompensated alike. It now measures
        #       against the CONTAINER, whose box a child transform cannot move.
        #   (b) its background was the crop's modal colour, so on a round button
        #       the square crop's corners -- page background outside the circle --
        #       counted as ink and swamped a 16px glyph. It now measures inside
        #       `painted_shape`, and against that shape's own centroid rather than
        #       the box centre, which is also the right reference for a mark that
        #       is not rectangular.
        #
        # With both closed the arm resolves the injected defect exactly: the
        # measured offset moves by 2.00px in each axis between the compensated
        # and uncompensated renders, which is the corpus's translate(2px, 2px) to
        # the hundredth. It stays behind --x2 anyway, for a reason that is now a
        # measurement rather than a doubt: the corpus's compensation constant was
        # authored against macOS Helvetica metrics, so on a different font stack
        # the CONTROL is genuinely off-centre and this arm correctly says so --
        # a true finding that is still a control false positive under the ship
        # gate. `fp_budget.py` is what reports that, per platform.
        parent = by_path.get(el["path"].rsplit(" > ", 1)[0]) if x2 else None
        is_mark = (
            parent is not None
            # A mark carries a glyph or two. Empty text is not a mark, it is a
            # layout box, and its ink belongs to whatever it wraps.
            and 1 <= len(el["text"]) <= 3
            and MIN_BOX <= parent["rect"]["w"] <= MARK_MAX
            and MIN_BOX <= parent["rect"]["h"] <= MARK_MAX
        )
        if is_mark:
            checked["xcheck-optical-centre"] += 1
            box = crop(img, parent["rect"], scale)
            shape = painted_shape(box) if box is not None else None
            if shape is not None and shape.sum() > 0.25 * shape.size:
                fill = modal(box[shape].reshape(-1, 3))
                core = erode(shape, max(1, int(round(scale))))
                weight = (
                    np.clip(np.abs(box - fill).sum(axis=2), 0, 255).astype(float) * core
                )
                mass = weight.sum() / 255.0 / (scale**2)
                if mass >= INK_MIN_MASS:
                    yy, xx = np.mgrid[0 : box.shape[0], 0 : box.shape[1]]
                    sy, sx = np.nonzero(shape)
                    dx = ((xx * weight).sum() / weight.sum() - sx.mean()) / scale
                    dy = ((yy * weight).sum() / weight.sum() - sy.mean()) / scale
                    if abs(dx) > CENTROID_TOL_PX or abs(dy) > CENTROID_TOL_PX:
                        rep(
                            "xcheck-optical-centre",
                            el["path"],
                            f"the DOM centres this mark exactly, but its rendered ink "
                            f"sits {abs(dx):.1f}px {'left' if dx < 0 else 'right'} and "
                            f"{abs(dy):.1f}px {'up' if dy < 0 else 'down'} of the "
                            f"painted centre of {parent['path'].rsplit(' > ', 1)[-1]} "
                            f"-- it will read as misaligned however correct the CSS is",
                        )

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            checked["xcheck-contrast-varies"] += 1
            # Sample the actual backdrop under the text: the modal NON-INK colour,
            # taken separately from the left and right thirds so a backdrop that
            # VARIES across the run cannot hide behind a single average.
            #
            # Excluding the ink is what makes "non-ink" true rather than merely
            # intended, and it is not a refinement: on a smooth gradient no
            # backdrop colour repeats, so the plain mode of the band is the TEXT
            # colour -- the one colour with many identical pixels. The check then
            # computes the text against itself, returns ~1:1 on both sides, and
            # goes silent on the only defect it exists to catch. That is what it
            # did on a Linux render of this corpus while passing on macOS, which
            # is the worst available failure shape: a silent pass that looks like
            # a clean page and varies by machine.
            w = region.shape[1]
            thirds = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled = {}
            for side, band in thirds.items():
                fb = band.reshape(-1, 3)
                backdrop = fb[
                    np.abs(fb - np.asarray(fg[:3], np.int16)).sum(axis=1) > 60
                ]
                if len(backdrop) < 10:  # all ink: no backdrop to sample
                    sampled = {}
                    break
                sampled[side] = modal(backdrop)
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
                )
    if census is not None:
        census.update(checked)
    return out


def best_shot(shots: pathlib.Path, stem: str) -> pathlib.Path | None:
    """The highest-DPR capture of this page. Every arm here is sub-pixel, and the
    device-pixel grid is the noise floor: at DPR 1 the glyph centroid moved 0.8px
    between pages that do not touch the glyph, and at 1.5 it moved 0.00px."""
    cands = sorted(
        (p for p in shots.glob(f"{stem}*.png") if p.stem.split("@")[0] == stem),
        key=lambda p: p.stat().st_size,
    )
    return cands[-1] if cands else None


def main(corpus: pathlib.Path, x2: bool = False) -> None:
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    results = {}
    for f in sorted(snaps.glob("*.json")):
        png = best_shot(shots, f.stem)
        if png is None:
            continue
        results[f.stem] = check(json.loads(f.read_text()), png, x2=x2)
    (corpus / "findings_xcheck.json").write_text(json.dumps(results, indent=1))

    ctrl = results.get("clean", [])
    print(f"CONTROL clean.html -> {len(ctrl)} finding(s){'' if ctrl else '  (quiet)'}")
    for c in ctrl:
        print(f"    [{c['rule']}] {c['target']}: {c['detail'][:100]}")
    print()
    # The baseline key spans the CLAIM, not just its location. Keyed on
    # (rule, target) alone, a control finding hides a variant's finding on the
    # same element even when the two say different things -- which is the
    # assertion-span-must-equal-its-subject bug the corpus already caught once,
    # in detect_dom's dedup, where it cost a real defect (0/1 until fixed).
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
    # See the X2 block in `check` for why the centroid arm is opt-in.
    main(
        pathlib.Path(args[0] if args else "corpus/out").resolve(), x2="--x2" in sys.argv
    )
