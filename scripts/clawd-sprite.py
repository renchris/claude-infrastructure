#!/usr/bin/env python3
"""clawd-sprite.py — the Claude Code creature as vector geometry, derived rather than redrawn.

The creature ("clawd") ships as literal data inside the Claude Code binary. Its authoritative
geometry — an 11 x 8 grid of SQUARE pixels — and its exact body orange #D77757 are read out in
docs/research/CLAWD_SPRITE_EXTRACTION_2026-07-29.md. This module turns that grid into SVG.

Two properties make it worth being a generator instead of hand-typed coordinates:

1. FIDELITY IS ASSERTED, NOT ASSUMED. The drawable parts are declared explicitly (they have to be
   — an animatable arm cannot be a run inside one merged path), and then their union is checked
   against the literal grid below. A part that drifts by one pixel fails the build. Hand-typed
   rects have no such check, and pixel art is exactly where an off-by-one is invisible in review.

2. THE POSES ARE DELTAS, NOT COPIES. Four poses ship in the binary's pose table; here each is a
   translation of two elements, so every pose renders the same body and cannot diverge from it.

Emits geometry only. It knows nothing about banners, timelines or plates — the composition owns
those. Elements are emitted one-animation-ready: the eyes and the arms are separate nodes, so a
pose is a transform on a node rather than a second animation on a shared one (which is what
scripts/banner-shots.sh --lint refuses).

  scripts/clawd-sprite.py --pose default --px 24      # one sprite, SVG fragment on stdout
  scripts/clawd-sprite.py --sheet > out.svg           # the verification sheet: 4 poses + a scale ramp
"""

from __future__ import annotations

import argparse
import sys

# ── the authoritative grid ──────────────────────────────────────────────────────────────────
# Transcribed from CLAWD_SPRITE_EXTRACTION_2026-07-29.md § "the true resolution is 11 x 8".
#   #  = body (clawd_body #D77757)
#   .  = eye — clawd_background shows through the upper half of the `▄` half-block
#   ' ' = empty
GRID = [
    " ######### ",
    " ######### ",
    "##.#####.##",
    "###########",
    " ######### ",
    " ######### ",
    " # #   # # ",
    " # #   # # ",
]

W, H = 11, 8
BODY = "#D77757"  # exact; NOT #d97757, and NOT the orange_FOR_SUBAGENTS_ONLY swatch beside it

# ── the drawable parts ──────────────────────────────────────────────────────────────────────
# (x, y, w, h) in grid units. Split by what has to move independently, not by what draws fewest
# rects: the arms rise for `arms-up` and the eyes shift for the looking poses, so each is a node.
TORSO = (1, 0, 9, 6)
LEGS = [(1, 6, 1, 2), (3, 6, 1, 2), (7, 6, 1, 2), (9, 6, 1, 2)]
ARMS = {"l": (0, 2, 1, 2), "r": (10, 2, 1, 2)}
EYES = {"l": (2, 2, 1, 1), "r": (8, 2, 1, 1)}

# ── the poses ───────────────────────────────────────────────────────────────────────────────
# The pose table in the binary belongs to the SMALLER in-session clawd, whose eyes are quadrant
# notches inside a two-row body. The vocabulary is quoted; mapping it onto the 11 x 8 startup
# creature is a translation, and this is the whole of the translation rule:
#
#   look-left / look-right  the source moves the dark notch to the cell's upper-LEFT (`▟███▟`) or
#                           upper-RIGHT (`▙███▙`) corner, both eyes together, body unmoved. Here
#                           the eye is a single pixel, so it shifts one pixel, both together.
#   arms-up                 the source's one whole-body pose raises the outer stubs onto the row
#                           ABOVE the body, where nothing was before. Here that means the arms must
#                           CLEAR the crown: measured against dy -2/-3/-4, a 2-cell rise leaves them
#                           flush with the top row and reads as a hat brim rather than raised arms,
#                           and a 4-cell rise reads as antennae. -3 clears the crown by one cell,
#                           which is the smallest rise that reads, so it is the one used.
#
# The feet row also shifts in the source (`Tdf`), but as quadrant marks inside one cell — the
# startup creature's legs are solid 1x2 columns with no sub-cell to move within, so they stay put.
# Inventing a leg shift would be the one part of this file that is not quoted from anything.
POSES = {
    "default": {"eye_dx": 0, "arm_dy": 0},
    "look-left": {"eye_dx": -1, "arm_dy": 0},
    "look-right": {"eye_dx": 1, "arm_dy": 0},
    "arms-up": {"eye_dx": 0, "arm_dy": -3},
}


def _cells(rect: tuple[int, int, int, int]) -> set[tuple[int, int]]:
    x, y, w, h = rect
    return {(x + dx, y + dy) for dx in range(w) for dy in range(h)}


def verify() -> None:
    """The parts must reconstruct the grid exactly. Loudly, or not at all."""
    literal_body = {
        (x, y) for y, row in enumerate(GRID) for x, ch in enumerate(row) if ch == "#"
    }
    literal_eyes = {
        (x, y) for y, row in enumerate(GRID) for x, ch in enumerate(row) if ch == "."
    }

    parts = _cells(TORSO) | {c for leg in LEGS for c in _cells(leg)}
    for arm in ARMS.values():
        parts |= _cells(arm)
    drawn = parts - {c for eye in EYES.values() for c in _cells(eye)}

    if (
        drawn != literal_body
        or {c for e in EYES.values() for c in _cells(e)} != literal_eyes
    ):
        missing = sorted(literal_body - drawn)
        extra = sorted(drawn - literal_body)
        raise SystemExit(
            f"clawd-sprite: parts do not reconstruct the grid.\n"
            f"  missing from parts: {missing}\n  drawn but not in grid: {extra}"
        )
    if any(len(row) != W for row in GRID) or len(GRID) != H:
        raise SystemExit(f"clawd-sprite: grid is not {W}x{H}")


def _r(rect: tuple[int, int, int, int], px: float, ox: float, oy: float) -> str:
    x, y, w, h = rect
    return f'<rect x="{ox + x * px:g}" y="{oy + y * px:g}" width="{w * px:g}" height="{h * px:g}"/>'


def sprite(
    px: float,
    ox: float = 0,
    oy: float = 0,
    pose: str = "default",
    idp: str = "clawd",
    plate: str = "#0d1117",
    animatable: bool = True,
) -> str:
    """One creature. `animatable` gives the movable parts ids so a composition can drive them."""
    p = POSES[pose]
    eye_dx, arm_dy = p["eye_dx"] * px, p["arm_dy"] * px

    body = [_r(TORSO, px, ox, oy)] + [_r(leg, px, ox, oy) for leg in LEGS]
    out = [
        f'<g id="{idp}" shape-rendering="crispEdges">',
        f'  <g fill="{BODY}">{"".join(body)}</g>',
    ]
    for side, arm in ARMS.items():
        ident = f' id="{idp}-arm{side.upper()}"' if animatable else ""
        shift = f' transform="translate(0 {arm_dy:g})"' if arm_dy else ""
        out.append(f'  <g{ident} fill="{BODY}"{shift}>{_r(arm, px, ox, oy)}</g>')
    for side, eye in EYES.items():
        ident = f' id="{idp}-eye{side.upper()}"' if animatable else ""
        shift = f' transform="translate({eye_dx:g} 0)"' if eye_dx else ""
        out.append(f'  <g{ident} fill="{plate}"{shift}>{_r(eye, px, ox, oy)}</g>')
    out.append("</g>")
    return "\n".join(out)


def sheet() -> str:
    """Verification sheet: every pose, and a scale ramp that answers 'how small can it get'.

    Static by construction — a reference render with no animation is one --lint can never
    disagree with, and the geometry is what is under test here, not the timing.
    """
    w, h = 1920, 780
    o = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}"',
        '     role="img" aria-labelledby="t d">',
        '<title id="t">clawd sprite — geometry verification sheet</title>',
        '<desc id="d">The Claude Code pixel creature drawn from its extracted 11 by 8 grid, in its '
        "four shipped poses along the top, and in a scale ramp along the bottom from 8 to 32 "
        "pixels per grid cell, to find the size below which the eyes and legs stop reading.</desc>",
        '<style>.f{font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,monospace}'
        ".cap{fill:#6e7681;font-size:15px;letter-spacing:.08em}</style>",
        f'<rect width="{w}" height="{h}" rx="14" fill="#0d1117"/>',
        f'<rect x=".75" y=".75" width="{w - 1.5}" height="{h - 1.5}" rx="14" fill="none" '
        'stroke="#21262d" stroke-width="1.5"/>',
    ]

    px, top = 20, 90
    span, gap = W * px, 120
    total = 4 * span + 3 * gap
    x0 = (w - total) / 2
    for i, pose in enumerate(POSES):
        x = x0 + i * (span + gap)
        o.append(sprite(px, x, top, pose, idp=f"p{i}", animatable=False))
        o.append(
            f'<text class="f cap" x="{x + span / 2:g}" y="{top + H * px + 40}" '
            f'text-anchor="middle">{pose}</text>'
        )

    ramp = [8, 12, 16, 24, 32]
    baseline = 620
    total = sum(W * s for s in ramp) + 110 * (len(ramp) - 1)
    x = (w - total) / 2
    for s in ramp:
        o.append(
            sprite(s, x, baseline - H * s, "default", idp=f"s{s}", animatable=False)
        )
        o.append(
            f'<text class="f cap" x="{x + W * s / 2:g}" y="{baseline + 34}" '
            f'text-anchor="middle">{s}px</text>'
        )
        x += W * s + 110
    o.append(
        f'<text class="f cap" x="{w / 2:g}" y="{baseline + 76}" text-anchor="middle" '
        'opacity=".75">grid 11 x 8 &#183; body #D77757 &#183; eye = plate showing through'
        "</text>"
    )
    o.append("</svg>")
    return "\n".join(o)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pose", choices=list(POSES), default="default")
    ap.add_argument("--px", type=float, default=24)
    ap.add_argument(
        "--sheet", action="store_true", help="emit the verification sheet SVG"
    )
    a = ap.parse_args()

    verify()
    print(sheet() if a.sheet else sprite(a.px, pose=a.pose))
    return 0


if __name__ == "__main__":
    sys.exit(main())
