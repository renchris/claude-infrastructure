#!/usr/bin/env python3
"""emote-verify.py — prove each candidate actually DOES something, and that its loop closes.

WHY THIS EXISTS. Every structural gate in `tools/banner/emotes.py` can pass on a candidate that is
visually inert. They check that the CSS is well-formed, that the story has three named acts, that the
sprite's optional groups are consistently drawn and styled — none of which can tell you whether
anything MOVED. Two candidates in the first authored pack passed every one of them and rendered as
five near-identical frames: a limb-level scratch and a stumble whose whole delta was below the size
at which this art is legible. They were caught by a human looking at a contact sheet, which is not a
gate; it is a habit, and habits are exactly what this repo's doctrine says to replace with a
chokepoint.

So this measures the thing that actually matters:

  INERTNESS  at the peak of its showcase, a candidate must differ from its own resting frame at all.
             This catches a panel that renders as a still.

  SEAM       t=0 and t=P must render IDENTICALLY once the intentionally-unsynchronised starfield is
             removed. A loop with a visible restart is not a loop — the same property
             `scripts/banner-verify.sh` asserts for the hero banner.

WHAT THIS CANNOT DO, ESTABLISHED BY MEASUREMENT RATHER THAN ASSUMED. This file was written intending
the first check to be a LEGIBILITY gate — "does the middle act read" — and the calibration run
disproved that outright. Measured movement, against a human verdict from contact sheets:

    curious   1.24%   reads clearly          itch    3.43%   reads as a still
    startle   1.83%   reads clearly          trip    3.61%   reads as a second candidate's pose

The two candidates a reviewer rejected score HIGHER than two he accepted. Whole-frame pixel delta
measures how many pixels moved, and legibility depends on whether the SILHOUETTE changed — a body
nudged sideways repaints a large area while changing shape not at all, and a glyph plus a small
crouch repaints little while being instantly readable. So the floor here is set BELOW every real
candidate and convicts only a panel that is genuinely static. Judging whether a beat reads is still
a human looking at a contact sheet, and this file does not pretend otherwise.

Keeping the measurement in the tool anyway is deliberate: `--calibrate` is how the next person
re-tests that claim instead of inheriting it.

    python3 scripts/emote-verify.py                 # gate every candidate
    python3 scripts/emote-verify.py --calibrate     # print measurements, assert nothing
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "banner"))

import emotes  # noqa: E402

SHOTS = ROOT / "scripts" / "banner-shots.sh"

# Fraction of the frame's pixels that must change between rest and the showcase peak. Set from the
# calibration run at 0.8%, which sits below the LOWEST real candidate measured (1.15%). It is a
# tripwire for a panel that renders as a still, not a quality bar — see the module docstring for the
# measurement that rules out using it as one.
MOVE_FLOOR = 0.008

# The starfield twinkles on periods 7/9/11/13 s, deliberately COPRIME to the 12 s loop so the field
# never repeats and cannot read as a beat. That is correct, and it means t=0 and t=P legitimately
# differ in the sky. Comparing whole frames would therefore report a seam on every candidate — the
# first run of this file did exactly that, a uniform 0.010% across all twelve, which is the tell that
# the instrument was measuring its own design decision rather than a defect. Strip the field and the
# comparison becomes exact for everything that actually belongs to the story.
STAR_OPEN, STAR_CLOSE = '<g class="estar">', "</g>"


def without_stars(svg: Path, dest: Path) -> Path:
    """A copy with the starfield removed, so a seam comparison sees only story elements."""
    t = svg.read_text(encoding="utf-8")
    i = t.find(STAR_OPEN)
    if i != -1:
        j = t.find(STAR_CLOSE, i)
        t = t[:i] + t[j + len(STAR_CLOSE) :]
    dest.write_text(t, encoding="utf-8")
    return dest


def shoot(svg: Path, times: list[float], out: Path) -> list[Path]:
    """Freeze the asset at each timestamp, in the same SVG-as-image mode GitHub renders it in."""
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            str(SHOTS),
            str(svg),
            "--times",
            ",".join(f"{t:g}" for t in times),
            "--scheme",
            "dark",
            "--out",
            str(out),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return sorted(out.glob("*.png"))


def diff_fraction(a: Path, b: Path) -> float:
    """Fraction of pixels that differ between two renders, via ImageMagick's absolute-error count."""
    r = subprocess.run(
        ["magick", "compare", "-metric", "AE", str(a), str(b), "null:"],
        capture_output=True,
        text=True,
    )
    raw = (r.stderr or "0").strip().split()[0]
    n = float(raw.replace(",", ""))
    ident = subprocess.run(
        ["identify", "-format", "%w %h", str(a)], capture_output=True, text=True
    ).stdout.split()
    return n / (int(ident[0]) * int(ident[1]))


def measure(e: emotes.Emote, svg: Path, tmp: Path) -> tuple[float, float]:
    """(movement at the showcase peak, seam difference between t=0 and t=P)."""
    t0, t1 = e.window
    # Rest is sampled BEFORE the story starts rather than at t=0, because t=0 is also where the
    # reduced-motion still lives and several candidates deliberately begin their approach early.
    rest = max(0.35, t0 - 1.2)
    peaks = [t0 + (t1 - t0) * f for f in (0.35, 0.5, 0.65)]
    frames = shoot(svg, [rest, *peaks, 0.0, emotes.EMOTE_P], tmp / e.key)
    by_t = {p.stem.rsplit("-t", 1)[1]: p for p in frames}

    def at(t: float) -> Path:
        return by_t[f"{t:g}".replace(".", "p")]

    move = max(diff_fraction(at(rest), at(p)) for p in peaks)

    starless = without_stars(svg, tmp / f"{e.key}-nostars.svg")
    sf = shoot(starless, [0.0, emotes.EMOTE_P], tmp / f"{e.key}-seam")
    by_s = {p.stem.rsplit("-t", 1)[1]: p for p in sf}
    seam = diff_fraction(by_s["0"], by_s[f"{emotes.EMOTE_P:g}".replace(".", "p")])
    return move, seam


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--calibrate", action="store_true", help="print measurements, assert nothing"
    )
    ap.add_argument("--only", default="", help="comma list of keys")
    args = ap.parse_args()

    emotes.load_packs()
    keys = {k for k in args.only.split(",") if k}
    todo = [e for e in emotes.EMOTES if not keys or e.key in keys]

    with tempfile.TemporaryDirectory(prefix="emote-verify-") as td:
        tmp = Path(td)
        svgs = tmp / "svg"
        emotes.build_all(svgs)

        rows, bad = [], []
        for e in todo:
            move, seam = measure(e, svgs / f"{e.key}.svg", tmp)
            rows.append((e, move, seam))
            if not args.calibrate:
                if move < MOVE_FLOOR:
                    bad.append(
                        f"{e.key}: moves {move * 100:.2f}% of the frame at its showcase peak, under "
                        f"the {MOVE_FLOOR * 100:.2f}% floor — nothing happens at all. (This floor "
                        f"only catches a static panel; a candidate can clear it and still be "
                        f"illegible, which is why beats are also reviewed by eye.)"
                    )
                if seam > 0:
                    bad.append(
                        f"{e.key}: t=0 and t={emotes.EMOTE_P:g}s differ by {seam * 100:.3f}% — the "
                        f"loop has a visible restart. Some track does not return to its 0% value."
                    )

        rows.sort(key=lambda r: r[1])
        width = max(len(e.key) for e, _, _ in rows)
        print(f"\n{'candidate':<{width}}  movement   seam")
        for e, move, seam in rows:
            flag = "  <-- INERT" if move < MOVE_FLOOR else ""
            print(f"{e.key:<{width}}  {move * 100:7.2f}%  {seam * 100:6.3f}%{flag}")

        if bad:
            print("\n" + "\n".join(f"  · {m}" for m in bad))
            return 1
        print(f"\nall {len(rows)} candidates move and loop cleanly")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
