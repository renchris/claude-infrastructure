#!/usr/bin/env python3
"""banner-beat-ink.py — prove every rare event actually puts INK on the canvas.

WHY THIS EXISTS, and it is not a hypothetical. Every gate in `tools/banner/gen.py` is STRUCTURAL:
the markup parses, each element carries exactly one animation, every sub-period divides P, the loop
seams shut at t=0 == t=P, no scenery enters the wordmark's keep-out. A beat can pass all of them and
render nothing at all — and one did. THE SHOOTING STAR's persistent train was authored as a stroked
horizontal `<path>` filled from an objectBoundingBox gradient; a perfectly horizontal path has a
bounding box of zero height, and SVG declines to paint an element whose box is degenerate in either
axis. Contribution over the whole frame: zero pixels. Every gate green.

`banner-verify`'s ALIVE check is the closest thing that already existed and it cannot see this. It
samples 0..31s of a 240s loop and asks only that the frames DIFFER FROM EACH OTHER, which the
creature's own two-frame stride satisfies by itself. A banner with every rare event painted in
invisible ink passes ALIVE 12/12.

THE METHOD, and the two ways it can lie to you — both of which it did before it worked:

  1. SUPPRESSION MUST OUTRANK AN ANIMATION. The obvious control is to inject `opacity:0` for the
     beat's selector and diff against the unmodified render. It reports zero difference for EVERY
     beat, because a running CSS animation outranks a normal author declaration in the cascade, so
     the control changes nothing and every beat reads as invisible. Only `display:none!important`
     actually removes the element — `!important` author declarations sit above the animation origin.
  2. THE CONTROL NEEDS A POSITIVE CONTROL. A suppression that silently fails and a beat that
     genuinely draws nothing produce the identical measurement — zero. So the suite is only
     trustworthy because at least one probe comes back NON-zero: a run in which every probe measured
     zero is reported as a BROKEN HARNESS rather than as a wall of failures, since that is the far
     likelier reading and the opposite conclusion would send a reader to rewrite working art.

Frames are frozen deterministically by `banner-shots.sh`, so a probe screenshots identically every
run and a failure is reproducible rather than a race.

    scripts/banner-beat-ink.py assets/banner/v6a-long-night.svg
    scripts/banner-beat-ink.py assets/banner/v6*.svg --min-px 40
"""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "tools" / "banner" / "gen.py"
SHOTS = ROOT / "scripts" / "banner-shots.sh"
WIDTH = (
    838  # the real README column — a beat must be visible at SHIPPING size, not at 1920
)


def load_gen():
    spec = importlib.util.spec_from_file_location("banner_gen", GEN)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    # Registered BEFORE exec: @dataclass resolves its own class's module out of sys.modules.
    sys.modules["banner_gen"] = mod
    spec.loader.exec_module(mod)
    return mod


def shoot(svg: Path, t: float, out: Path) -> Path:
    subprocess.run(
        [
            str(SHOTS),
            str(svg),
            "--times",
            f"{t:g}",
            "--bg",
            "dark",
            "--width",
            str(WIDTH),
            "--out",
            str(out),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    pngs = sorted(out.glob("*.png"))
    if len(pngs) != 1:
        raise SystemExit(f"banner-beat-ink: expected 1 frame in {out}, got {len(pngs)}")
    return pngs[0]


def delta(a: Path, b: Path) -> tuple[int, int]:
    """(max level difference, count of pixels differing by more than 1) between two renders."""
    from PIL import (
        Image,
    )  # imported late: the module is only needed when a probe actually runs
    import numpy as np

    x = np.asarray(Image.open(a).convert("L")).astype(int)
    y = np.asarray(Image.open(b).convert("L")).astype(int)
    if x.shape != y.shape:
        raise SystemExit(f"banner-beat-ink: frame sizes differ, {x.shape} vs {y.shape}")
    d = abs(x - y)
    return int(d.max()), int((d > 1).sum())


def variant_for(g, asset: Path):
    """Match an asset back to the Art that produced it — the beat set is per-variant."""
    for art in g.VARIANTS:
        if asset.stem == art.key:
            return art
    raise SystemExit(
        f"banner-beat-ink: {asset.name} does not match any variant key "
        f"({', '.join(a.key for a in g.VARIANTS)}). The probe set is per-variant, so an "
        f"unmatched asset would be checked against the wrong beats."
    )


def probe(
    svg_text: str, selector: str, t: float, tmp: Path, tag: str
) -> tuple[int, int]:
    whole = tmp / f"{tag}-whole"
    without = tmp / f"{tag}-without"
    a = tmp / f"{tag}-a.svg"
    b = tmp / f"{tag}-b.svg"
    a.write_text(svg_text)
    # display:none, not opacity:0 — see the module docstring. And !important, because the beat's own
    # keyframes are an animation and an animation outranks a normal declaration.
    b.write_text(
        svg_text.replace("</style>", f"{selector}{{display:none!important}}</style>", 1)
    )
    return delta(shoot(a, t, whole), shoot(b, t, without))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("assets", nargs="+")
    ap.add_argument(
        "--min-px",
        type=int,
        default=25,
        help="pixels that must differ for a beat to count as visible AT 838px (default 25)",
    )
    args = ap.parse_args()
    g = load_gen()

    failures: list[str] = []
    uncovered: list[str] = []
    results: list[tuple[str, str, float, str, int, int]] = []

    for raw in args.assets:
        asset = Path(raw).resolve()
        art = variant_for(g, asset)
        text = asset.read_text()
        if "</style>" not in text:
            raise SystemExit(
                f"banner-beat-ink: {asset.name} has no <style> to inject into"
            )
        active = g.active_events(art)
        print(
            f"banner-beat-ink: {asset.name} — {len(active)} emitted beat(s) at {WIDTH}px"
        )
        for beat in active:
            probes = g.BEAT_INK.get(beat)
            if not probes:
                # NAMED, never skipped in silence: an unprobed beat is exactly as unverified as a
                # failing one, and a summary that omits it reads as coverage it does not have.
                uncovered.append(f"{art.key}/{beat}")
                print(f"  ? {beat:9s} NO PROBE DECLARED — add one to BEAT_INK")
                continue
            w0, _w1 = g.RARE_EVENTS[beat]
            with tempfile.TemporaryDirectory() as td:
                for i, (off, selector) in enumerate(probes):
                    t = w0 + off
                    mx, px = probe(text, selector, t, Path(td), f"{beat}{i}")
                    results.append((art.key, beat, t, selector, mx, px))
                    ok = px >= args.min_px
                    mark = "✓" if ok else "✗"
                    print(
                        f"  {mark} {beat:9s} t={t:7.2f}s  {selector:<28s} "
                        f"max {mx:3d}  px {px:6d}"
                    )
                    if not ok:
                        failures.append(
                            f"{art.key}/{beat} at t={t:.2f}s: suppressing {selector} changed "
                            f"{px} pixels (max delta {mx}), under the {args.min_px}px floor — "
                            f"this beat is invisible at the README's real width"
                        )

    print()
    # THE POSITIVE CONTROL ON THE WHOLE RUN. A broken suppression and a genuinely blank banner both
    # measure zero everywhere, so an all-zero run is reported as a broken harness. Convicting the
    # art on evidence that equally convicts the instrument is how a good asset gets rewritten.
    if results and all(px == 0 for *_rest, px in results):
        print(
            "banner-beat-ink: BROKEN HARNESS — every probe measured exactly zero. That is far more "
            "likely to be the suppression failing to apply than every beat being blank. Check that "
            "'</style>' is still the injection anchor and that the rule is display:none!important."
        )
        return 2
    if uncovered:
        print(
            f"banner-beat-ink: {len(uncovered)} beat(s) have NO PROBE: {', '.join(uncovered)}"
        )
    if failures:
        print(
            f"banner-beat-ink: FAIL — {len(failures)} beat(s) put no ink on the canvas"
        )
        for f in failures:
            print(f"  · {f}")
        return 1
    print(
        f"banner-beat-ink: PASS — {len(results)} probe(s), every emitted beat is visibly "
        f"present at {WIDTH}px"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
