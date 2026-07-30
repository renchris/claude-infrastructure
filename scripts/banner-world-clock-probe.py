#!/usr/bin/env python3
"""Measure the ground's ACTUAL displacement out of real renders, against the world clock's model.

Why this exists. `banner-verify.sh` cannot see a beat. It proves the file parses, that one animation
rides each element, that t=0 and t=P match, that twelve frames differ, that both schemes render, and
that a still exists — and the committed v6b passed all six while its peer never stopped beside the
resident and its cheer never fired at all, because CSS had silently dropped two keyframe blocks. So
"6/6 green" is not evidence that THE ASK stops the world or that THE REFUSAL pulls it back. Nothing
in the gate could tell the difference between a world clock that works and one that is inert.

So this measures the thing itself: it cross-correlates the near foreground band between pairs of
frozen frames and reports how far the ground actually moved, in SVG pixels, then compares that with
what the world clock predicts. The band is deliberately the correlation target rather than the
footprints — the prints repeat every 48 px, so a print-based shift is only ever known modulo the
pitch, and "moved one pitch" and "did not move at all" are the same reading. The foreground's top
edge is aperiodic within a tile, so its shift is unambiguous.

The ambient pair at the end is the positive control. Without it a probe that returned zero for
everything would look like proof that the world stops, which is the wrong half of the claim.

    scripts/banner-world-clock-probe.py assets/banner/v6a-long-night.svg

Exit 0 = every measured displacement matches the model within tolerance.
"""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "scripts" / "banner-shots.sh"

# The near foreground band's top edge lives at GROUND+56 +/- 9 = y 553..571, so a window across it
# is part band and part open ground per column: an aperiodic 1-D signal. Kept clear of the tf1 dash
# layer above it (ends y=560 in SVG units) which scrolls at a DIFFERENT rate and would blur the peak.
BAND_Y0, BAND_Y1 = 561, 574
TOL = 2.0  # SVG px — one render's edge quantisation, well under the 48 px stride pitch


def load_gen():
    spec = importlib.util.spec_from_file_location(
        "banner_gen", ROOT / "tools" / "banner" / "gen.py"
    )
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["banner_gen"] = mod
    spec.loader.exec_module(mod)
    return mod


g = load_gen()

# (t0, t1, what it is). Every interval is a whole number of strides, because that is the only place
# the world clock is allowed to change rate.
PAIRS = [
    (4.0, 4.5, "REFUSAL: the creature settles, world holds"),
    (4.5, 5.0, "REFUSAL: the world pulls BACK one print pitch"),
    (5.0, 5.5, "REFUSAL: it re-walks the step it was sent back over"),
    (5.5, 6.0, "REFUSAL: making up the ground it lost"),
    (13.0, 14.0, "ASK: dead stop"),
    (16.0, 17.0, "ASK: still dead, three seconds in"),
    (19.0, 20.0, "ASK: resumes at treble to clear the debt"),
    (30.0, 31.0, "CONTROL: ambient world, nothing declared"),
]


def row_profile(png: Path, width: int) -> list[float]:
    """Column means over the foreground band — a 1-D signature of where the band's top edge sits."""
    h = BAND_Y1 - BAND_Y0
    raw = subprocess.run(
        [
            "magick",
            str(png),
            "-colorspace",
            "Gray",
            "-crop",
            f"{width}x{h}+0+{BAND_Y0}",
            "+repage",
            "-depth",
            "8",
            "gray:-",
        ],
        capture_output=True,
        check=True,
    ).stdout
    if len(raw) != width * h:
        raise SystemExit(
            f"probe: expected {width * h} bytes from {png.name}, got {len(raw)} — the render is not "
            f"the size this probe assumes, so every offset below would be measured against the wrong "
            f"scale"
        )
    return [sum(raw[r * width + c] for r in range(h)) / h for c in range(width)]


def best_shift(
    a: list[float], b: list[float], span: int = 400
) -> tuple[int, float, float]:
    """The leftward shift (a -> b) minimising SAD, that score, and the surface's MEDIAN score.

    Prominence is measured against the surface the peak sits in, never as an absolute margin. The
    first cut of this probe required the runner-up to beat the winner by 1.0 SAD, and reported all
    eight intervals as FLAT PEAK while every one of the eight measurements was in fact exact — on
    near-binary content a correct match scores ~0.0 and its rivals ~0.7, so a fixed absolute margin
    is simply the wrong unit. The threshold was wrong, not the measurement, and a threshold that
    cannot be met is indistinguishable from a subject that cannot pass.
    """
    n = len(a)
    m0, m1 = span, n - span
    cols = list(
        range(m0, m1, 3)
    )  # every third column: 400+ samples, a third of the work
    scores = []
    for s in range(-span, span + 1):
        tot = 0.0
        for c in cols:
            tot += abs(a[c] - b[c - s])
        scores.append((tot / len(cols), s))
    scores.sort()
    median = scores[len(scores) // 2][0]
    return scores[0][1], scores[0][0], median


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("asset")
    ap.add_argument("--width", type=int, default=1920)
    args = ap.parse_args()
    asset = Path(args.asset)
    stem = asset.stem
    # Build THIS variant before reading the encoded clock: `_ENCODED_STRIP` is populated by emitting
    # the stylesheet, and the model must come from the same variant the renders came from.
    art = next((a for a in g.VARIANTS if a.key == stem), None)
    if art is None:
        raise SystemExit(
            f"probe: {stem} is not a variant in gen.py — nothing to compare against"
        )
    g.build(art)

    times = sorted({t for p in PAIRS for t in p[:2]})
    with tempfile.TemporaryDirectory() as td:
        out = Path(td)
        subprocess.run(
            [
                str(SHOTS),
                str(asset),
                "--times",
                ",".join(f"{t:g}" for t in times),
                "--bg",
                "dark",
                "--scheme",
                "dark",
                "--width",
                str(args.width),
                "--scale",
                "1",
                "--out",
                str(out),
            ],
            check=True,
            capture_output=True,
        )
        prof = {}
        for t in times:
            # banner-shots.sh sanitises the dot out of a fractional timestamp: t=4.5 lands in
            # `-t4p5.png`. Reconstructing the name any other way silently finds no file, and a probe
            # that cannot read its own renders reports nothing rather than failing.
            p = out / f"{stem}-dark-dark-t{f'{t:g}'.replace('.', 'p')}.png"
            if not p.exists() or p.stat().st_size == 0:
                raise SystemExit(f"probe: render missing for t={t:g} — {p}")
            prof[t] = row_profile(p, args.width)

    print(f"banner-world-clock-probe: {asset}")
    print(
        f"  band y={BAND_Y0}..{BAND_Y1}, {args.width}px wide, tolerance +/-{TOL:g}px\n"
    )
    print(f"  {'interval':>13}  {'measured':>9}  {'model':>8}  {'rate':>5}  what")
    bad = []
    for t0, t1, label in PAIRS:
        shift, s_best, s_median = best_shift(prof[t0], prof[t1])
        q0 = g._interp(g._ENCODED_STRIP, t0)
        q1 = g._interp(g._ENCODED_STRIP, t1)
        model = g.STRIP_V * (t1 - t0) - (q1 - q0)
        rate = model / (g.STRIP_V * (t1 - t0))
        ok = abs(shift - model) <= TOL
        # A flat correlation surface means the peak carries no information, whatever it says. Judged
        # against the surface's own median, so the test has no hidden unit to get wrong.
        sharp = s_best <= 0.5 * s_median
        flag = (
            ""
            if (ok and sharp)
            else ("  <-- MISMATCH" if not ok else "  <-- FLAT PEAK")
        )
        if not (ok and sharp):
            bad.append((label, shift, model, s_best, s_median))
        print(
            f"  {t0:5.1f}->{t1:5.1f}  {shift:8d}px  {model:7.1f}px  {rate:4.0f}x  {label}{flag}"
        )

    print()
    if bad:
        print(
            f"banner-world-clock-probe: FAIL — {len(bad)} interval(s) do not match the model"
        )
        for label, shift, model, b, s in bad:
            print(
                f"  · {label}: measured {shift}px, model {model:.1f}px (SAD {b:.2f} vs {s:.2f})"
            )
        return 1
    print(
        "banner-world-clock-probe: PASS — the ground stops, reverses one print pitch, and catches "
        "up exactly as the world clock says, measured through a real SVG-as-image render"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
