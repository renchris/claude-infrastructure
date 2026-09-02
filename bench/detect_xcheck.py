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
  X2 ink-centroid    the container centres the child's BOX and the child's own
                     INK still sits off that centre. Validated 2026-09-02 and now
                     on by default (--no-x2 to disable). It shipped provisional
                     and disabled because validating it found two defects, and
                     both are now fixed:
                     (a) it compared ink to the element's OWN box, and
                     getBoundingClientRect returns the POST-transform box, so any
                     translate moved box and ink together and the measured offset
                     was INVARIANT under the very compensation it should verify.
                     FIXED: the reference frame is the CONTAINER -- specifically
                     the parent whose computed style makes a centring claim --
                     and the container's box does not move when the child does.
                     (b) its background was the crop's modal colour, so on a round
                     button the square crop's corners -- page background outside
                     the circle -- counted as ink and swamped a 16px glyph.
                     Measured on this corpus: 499 px of "ink" for an 80 px glyph,
                     85% of it corner. FIXED: the crop is masked to the painted
                     shape, found by flood-filling the OUTSIDE colour inward from
                     the crop border (the glyph cannot be reached that way even
                     when it is the same colour as the page behind the button,
                     which here it is), then eroded by the antialiasing width.
                     Masked ink mass falls to 76 px and the clean/defect centroid
                     separation becomes the injected 2.00 px exactly.
  X3 contrast-real   the colour sampled behind the text disagrees with the colour
                     computed from the cascade. getComputedStyle runs BEFORE
                     compositing, so mix-blend-mode, filter and backdrop-filter
                     all make the computed answer wrong; a gradient makes it
                     unrepresentable. This is the check that catches what the
                     scalar blended-backdrop cannot.
                     Its band-sampling step carried a latent FALSE NEGATIVE, found
                     by re-running the corpus on a second font stack: the modal
                     colour of a band includes the text's OWN ink, so wherever the
                     type is dense enough to win the mode the "backdrop" sampled
                     is the foreground and the ratio collapses to 1.00:1 on BOTH
                     sides -- a varying backdrop reported as uniform. Measured
                     here: 1.00:1 left vs 1.38:1 right on the gradient page, under
                     the 1.5-point trigger, so the defect the arm exists to catch
                     went unreported. FIXED: ink is excluded before the mode is
                     taken, using the foreground colour the DOM already knows.

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
CENTROID_TOL_PX = 1.0  # ink centre vs the CONTAINER's centre
CONTRAST_DELTA = 1.5  # ratio points between sampled and computed contrast
MIN_BOX = 8  # ignore hairlines; a 1px rule has no meaningful centroid
# A pixel this far off the background-to-foreground line is neither, so it belongs
# to some third thing (a border, an icon, another element) and is not this mark's
# ink. Well above 8-bit rounding and JPEG-free PNG noise, well below any real hue.
OFF_LINE_TOL = 12.0
# A pixel nearer the foreground than this is text ink, and text ink is never a
# sample of the backdrop behind it. Used by X3.
INK_NEAR_FG = 40.0
X2_ENABLED = "--no-x2" not in sys.argv  # validated 2026-09-02; see the docstring
# Centring claims we can read off computed styles. text-align is deliberately not
# here: capture.py does not collect it, and inventing the claim would make the
# comparator fire where the DOM never promised anything.
CENTRED_MAIN = {"center", "safe center"}


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


def _grow(mask: np.ndarray) -> np.ndarray:
    """4-connected dilation by one pixel. Four shifts beat importing scipy."""
    o = mask.copy()
    o[1:, :] |= mask[:-1, :]
    o[:-1, :] |= mask[1:, :]
    o[:, 1:] |= mask[:, :-1]
    o[:, :-1] |= mask[:, 1:]
    return o


def _erode(mask: np.ndarray, rounds: int) -> np.ndarray:
    """4-connected erosion, with the crop border treated as outside."""
    for _ in range(rounds):
        e = mask.copy()
        e[1:, :] &= mask[:-1, :]
        e[:-1, :] &= mask[1:, :]
        e[:, 1:] &= mask[:, :-1]
        e[:, :-1] &= mask[:, 1:]
        e[0, :] = e[-1, :] = False
        e[:, 0] = e[:, -1] = False
        mask = e
    return mask


def painted_shape(region: np.ndarray, bg: np.ndarray, scale: float) -> np.ndarray:
    """The pixels the container itself paints, as a boolean mask over the crop.

    A crop is a rectangle; a painted element need not be. On a `border-radius: 22px`
    button the crop's four corners are PAGE background, and counting them as ink is
    what made this arm unshippable.

    The corners cannot be excluded by colour alone: here the page behind the button
    is white and the glyph inside it is also white, so any nearest-colour rule that
    removes the corners removes the mark as well. They CAN be excluded by
    connectivity -- the corners touch the crop's border and the glyph does not --
    so the outside region is a flood fill inward from the border over pixels that
    look more like the surroundings than like the container's own fill. The result
    is eroded by the antialiasing width, because a rounded edge is a ramp between
    the two colours and every pixel on that ramp would otherwise read as ink.
    """
    # The surrounding colour, read from the corners and only where it actually
    # differs from the fill. A square element has no such pixels, and then the
    # painted shape is simply the whole crop.
    k = max(2, int(round(2 * scale)))
    corners = np.concatenate(
        [
            region[:k, :k].reshape(-1, 3),
            region[:k, -k:].reshape(-1, 3),
            region[-k:, :k].reshape(-1, 3),
            region[-k:, -k:].reshape(-1, 3),
        ]
    )
    far = corners[np.linalg.norm(corners - bg, axis=1) > 24.0]
    if len(far) < k * k:
        return np.ones(region.shape[:2], dtype=bool)
    vals, counts = np.unique(far, axis=0, return_counts=True)
    outside = vals[counts.argmax()].astype(np.float64)

    cand = np.linalg.norm(region - outside, axis=2) < np.linalg.norm(
        region - bg, axis=2
    )
    reach = np.zeros(cand.shape, dtype=bool)
    reach[0, :] = cand[0, :]
    reach[-1, :] = cand[-1, :]
    reach[:, 0] = cand[:, 0]
    reach[:, -1] = cand[:, -1]
    while True:
        nxt = _grow(reach) & cand
        if np.array_equal(nxt, reach):
            break
        reach = nxt
    return _erode(~reach, int(round(scale)) + 1)


def ink_coverage(region: np.ndarray, bg: np.ndarray, fg: np.ndarray) -> np.ndarray:
    """Per-pixel alpha of `fg` composited over `bg` — the mark's own coverage.

    Antialiased type is a partial blend, so a binary threshold throws away most of
    a small glyph's mass and biases the centroid toward whichever stroke happens to
    be densest. The least-squares alpha along the bg->fg line recovers the coverage
    the rasteriser actually wrote, and the distance OFF that line rejects pixels
    belonging to something else entirely.
    """
    d = fg - bg
    denom = float(d @ d)
    if denom < 1.0:  # foreground and background are the same colour; no signal
        return np.zeros(region.shape[:2])
    alpha = np.clip(((region - bg) @ d) / denom, 0.0, 1.0)
    residual = np.linalg.norm(region - (bg + alpha[..., None] * d), axis=2)
    return np.where(residual <= OFF_LINE_TOL, alpha, 0.0)


def centring_claim(parent: dict) -> tuple[bool, bool]:
    """(centres horizontally, centres vertically) per the parent's computed style.

    X2 is a comparator, so it may only fire where the DOM has actually PROMISED
    something. A flex row that centres on its cross axis has made a claim about
    vertical placement and none about horizontal, and a rule that ignores the
    difference is not cross-checking, it is guessing.
    """
    st = parent["styles"]
    disp = st.get("display", "")
    if "flex" not in disp and "grid" not in disp:
        return False, False
    align = st.get("align-items", "").strip() in CENTRED_MAIN
    justify = st.get("justify-content", "").strip() in CENTRED_MAIN
    if "grid" in disp:
        return justify, align
    column = "column" in st.get("flex-direction", "")
    return (align, justify) if column else (justify, align)


def x2_optical_centre(el, parent, img, scale) -> list[dict]:
    """Compare a mark's rendered ink centroid to the CENTRE OF ITS CONTAINER.

    The container is the reference frame precisely because it does not move when
    the child does. Measuring against the child's own box made this arm blind to
    the transform it was written to verify.

    Vertical placement of TEXT ink is not gated, only reported. Inside a line box
    the glyph's vertical position is decided by the font's ascent, descent and
    baseline, not by anything the page author wrote, so a threshold on it is a
    threshold on the font: measured on this corpus the same markup renders the ink
    3.8 px low under the Linux fallback face and ~0 px low under macOS Helvetica.
    A mark with no text has no such excuse and is judged on both axes.
    """
    hor, vert = centring_claim(parent)
    if not hor and not vert:
        return []
    bg_c = parse_rgb(parent["styles"].get("background-color", ""))
    fg_c = parse_rgb(el["styles"].get("color", ""))
    if not bg_c or bg_c[3] < 0.99 or not fg_c or fg_c[3] < 0.99:
        return []  # no opaque pair to separate ink from fill; say nothing

    region = crop(img, parent["rect"], scale)
    if region is None:
        return []
    region = region.astype(np.float64)
    bg = np.array(bg_c[:3], dtype=np.float64)
    fg = np.array(fg_c[:3], dtype=np.float64)
    alpha = ink_coverage(region, bg, fg) * painted_shape(region, bg, scale)
    mass = float(alpha.sum())
    if mass < 8.0 * scale * scale:  # too little ink to have a centroid worth stating
        return []

    ys, xs = np.nonzero(alpha > 0.02)
    w = alpha[ys, xs]
    dx = ((xs * w).sum() / w.sum() - (region.shape[1] - 1) / 2) / scale
    dy = ((ys * w).sum() / w.sum() - (region.shape[0] - 1) / 2) / scale
    gate_v = vert and not el["text"]
    off = (hor and abs(dx) > CENTROID_TOL_PX) or (gate_v and abs(dy) > CENTROID_TOL_PX)
    if not off:
        return []
    axis = f"{abs(dx):.1f}px {'left' if dx < 0 else 'right'}"
    if gate_v:
        axis += f" and {abs(dy):.1f}px {'up' if dy < 0 else 'down'}"
    return [
        {
            "rule": "xcheck-optical-centre",
            "target": el["path"],
            "detail": (
                f"{parent['path']} centres this mark's box exactly, but its rendered "
                f"ink sits {axis} of that container's centre "
                f"(vertical offset {dy:+.1f}px, not gated: font metrics own it). "
                f"It will read as misaligned however correct the CSS is"
            ),
            "severity": "medium",
        }
    ]


def check(snap: dict, png: pathlib.Path) -> list[dict]:
    img = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    # The snapshot is in CSS px; the shot may be at a device scale. Derive the
    # factor from the artifacts themselves rather than trusting a flag.
    scale = img.shape[1] / snap["scroll"]["w"]
    out = []
    by_path = {e["path"]: e for e in snap["elements"]}
    # A mark is a LEAF: an element that paints itself rather than arranging others.
    # A wrapper's "ink" is its children's, and its centroid says nothing about it.
    has_kids = {p.rsplit(" > ", 1)[0] for p in by_path if " > " in p}

    def parent_of(el):
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

        # --- X2: ink is not centred in the box the DOM centred -----------------
        # Only meaningful where the element is a small, self-contained mark. A
        # paragraph's ink is legitimately top-left-heavy because text flows.
        is_glyph_like = (
            X2_ENABLED
            and r["w"] < 64
            and r["h"] < 64
            and len(el["text"]) <= 3
            and el["path"] not in has_kids
        )
        parent = parent_of(el) if is_glyph_like else None
        if parent is not None:
            out.extend(x2_optical_centre(el, parent, img, scale))

        # --- X3: sampled backdrop vs the one the cascade computed --------------
        if el["text"] and len(el["text"]) > 3:
            fg = parse_rgb(el["styles"].get("color", ""))
            if not fg:
                continue
            # Sample the actual backdrop under the text: the modal non-ink colour,
            # taken separately from the left and right thirds so a backdrop that
            # VARIES across the run cannot hide behind a single average.
            #
            # The text's own ink is excluded FIRST. Without that step the mode is
            # the foreground wherever the type is dense, both sides report the
            # foreground's contrast against itself -- 1.00:1 -- and a backdrop that
            # varies by nine ratio points is reported as uniform. That is a false
            # NEGATIVE produced by a rule that looks like it is working, and it
            # only appeared when the corpus was re-rendered on a second font stack.
            w = region.shape[1]
            thirds = {"left": region[:, : w // 3], "right": region[:, -w // 3 :]}
            sampled = {}
            for side, band in thirds.items():
                fb = band.reshape(-1, 3)
                backdrop = fb[
                    np.abs(fb - np.array(fg[:3], dtype=np.int16)).sum(axis=1)
                    > INK_NEAR_FG
                ]
                if len(backdrop) < 16:
                    break  # the band is all ink; no backdrop to sample
                v, c = np.unique(backdrop, axis=0, return_counts=True)
                sampled[side] = v[c.argmax()]
            if len(sampled) < 2:
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


def run(corpus: pathlib.Path, suffix: str = "") -> dict:
    """Grade the whole corpus at one capture scale. `suffix` selects the shot."""
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    results = {}
    for f in sorted(snaps.glob("*.json")):
        png = shots / f"{f.stem}{suffix}.png"
        if not png.exists():
            continue
        results[f.stem] = check(json.loads(f.read_text()), png)
    return results


def main(corpus: pathlib.Path, suffix: str = "") -> None:
    results = run(corpus, suffix)
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
    # A comparator that is quiet at one capture scale and noisy at another has not
    # been measured, so the shot is selectable rather than assumed.
    sfx = next(
        (a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--shot=")), ""
    )
    main(pathlib.Path(args[0] if args else "corpus/out").resolve(), sfx)
