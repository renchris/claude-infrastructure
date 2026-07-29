#!/usr/bin/env python3
"""banner-build.py — compose banner candidates from the clawd sprite geometry.

Takes its creature from scripts/clawd-sprite.py, so a composition can never disagree with the
extracted grid. What it adds is everything the sprite does not know about: the plate, the wordmark,
the ground, and the timeline.

The timeline obeys three rejections at once, and they constrain each other:

  R2  the wordmark is a plain <text> with NO animation of any kind. It is painted at t=0 and never
      touched again, so there is no state of the document in which the title is absent. Motion is
      only ever applied to the creature.
  R3  every animation is `infinite`, and every keyframe list starts and ends on the same value, so
      there is no seam to see. The loop is ambient — the creature idles — rather than a narrative
      that has to restart. Periods are deliberately coprime-ish (13s, 19s), so the COMPOSITE never
      visibly repeats even though each part does.
  lint  one animation per element (scripts/banner-shots.sh --lint). The parts that move are separate
      nodes for exactly this reason; nothing carries a comma-list.

`step-end` is the timing function throughout: this is a pixel grid, so a gaze shift must JUMP one
cell, never slide a fraction of one. Interpolated pixel art is the tell that it was drawn by
something that did not understand it was pixel art.

  scripts/banner-build.py kit > assets/banner/motion-kit.svg
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import sys

_spec = importlib.util.spec_from_file_location(
    "clawd_sprite", pathlib.Path(__file__).with_name("clawd-sprite.py")
)
cs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cs)

PLATE_TOP = "#171e27"
PLATE_BOT = "#0d1117"
BORDER = "#21262d"
RULE = "#30363d"
DIM = "#6e7681"
TITLE = "#e6edf3"

FONT = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace'

WORDMARK = "claude-infrastructure"
TITLE_TRACK = 1.5  # letter-spacing, user units
# Every monospace face in the stack advances 0.6em per cell (SF Mono, Menlo and Consolas all do).
# It is an approximation only in that a substituted face could differ — which is why the layout
# leaves a margin rather than butting the creature against the computed edge.
MONO_ADVANCE = 0.6


def head(w: int, h: int, title: str, desc: str) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}"',
        '     role="img" aria-labelledby="t d">',
        f'<title id="t">{title}</title>',
        f'<desc id="d">{desc}</desc>',
        "<defs>",
        f'  <radialGradient id="plate" cx=".5" cy=".38" r=".72">'
        f'<stop offset="0" stop-color="{PLATE_TOP}"/>'
        f'<stop offset="1" stop-color="{PLATE_BOT}"/></radialGradient>',
        f'  <linearGradient id="rule" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="{w}" y2="0">'
        f'<stop offset="0" stop-color="{RULE}" stop-opacity="0"/>'
        f'<stop offset=".18" stop-color="{RULE}" stop-opacity=".95"/>'
        f'<stop offset=".82" stop-color="{RULE}" stop-opacity=".95"/>'
        f'<stop offset="1" stop-color="{RULE}" stop-opacity="0"/></linearGradient>',
        "</defs>",
    ]


def plate(w: int, h: int) -> list[str]:
    return [
        f'<rect width="{w}" height="{h}" rx="14" fill="url(#plate)"/>',
        f'<rect x=".75" y=".75" width="{w - 1.5}" height="{h - 1.5}" rx="14" fill="none" '
        f'stroke="{BORDER}" stroke-width="1.5"/>',
    ]


def ground(w: int, y: float, dash: str = "3 9") -> str:
    """The hard dotted horizon the shipped scene stands on, faded at both ends."""
    return (
        f'<line x1="0" y1="{y:g}" x2="{w}" y2="{y:g}" stroke="url(#rule)" stroke-width="2" '
        f'stroke-dasharray="{dash}" stroke-linecap="butt"/>'
    )


def timeline(px: float) -> str:
    """The idle cycle. One animation per element; every list returns to its own start value."""
    gaze, arms = px, 3 * px
    return f"""<style>
  .f {{ font-family: {FONT}; }}

  /* The creature idles. Nothing here touches the wordmark — R2 is structural, not a setting:
     the title has no animation to disable, no opacity to reach, and no keyframe that owns it. */
  .eye {{ animation: gaze 13s step-end infinite; }}
  .arm {{ animation: arms 19s step-end infinite; }}

  /* Both eyes share one rule, so a glance is always both eyes together — the shipped pose table
     moves the eye segment as a unit and never one eye alone. Holds `default` most of the cycle;
     the glances are brief, because a header that keeps moving pulls the eye off the page. */
  @keyframes gaze {{
      0%,  28% {{ transform: translateX(0) }}
     28%,  34% {{ transform: translateX(-{gaze:g}px) }}
     34%,  61% {{ transform: translateX(0) }}
     61%,  67% {{ transform: translateX({gaze:g}px) }}
     67%, 100% {{ transform: translateX(0) }}
  }}

  /* One stretch per 19s. 13 and 19 are coprime, so gaze and stretch land together once every
     247s — the composite reads as unrepeating while every part of it loops. */
  @keyframes arms {{
      0%,  86% {{ transform: translateY(0) }}
     86%,  91% {{ transform: translateY(-{arms:g}px) }}
     91%, 100% {{ transform: translateY(0) }}
  }}

  /* Same artwork, held still — the creature sits in `default`, which is where both cycles begin
     and end, so the frozen frame is a frame the animation genuinely passes through rather than a
     separate static fallback that could drift from it. */
  @media (prefers-reduced-motion: reduce) {{
    .eye, .arm {{ animation: none !important; transform: none !important; }}
  }}
</style>"""


def kit(w: int = 1920, h: int = 520) -> str:
    """The mechanism proof, and the skeleton every subject direction shares."""
    px = 22
    title_px = 84
    base = 430.0  # the horizon; the creature stands ON it
    # A monospace advance is a known fraction of the em, so the wordmark's extent is arithmetic
    # rather than a guess — and the creature is placed against that extent instead of by eye. The
    # first attempt put it at a hand-picked x and it landed on top of "ctu" in "infrastructure".
    title_w = (
        len(WORDMARK) * title_px * MONO_ADVANCE + (len(WORDMARK) - 1) * TITLE_TRACK
    )
    cx = (w + title_w) / 2 + 78  # clear of the wordmark's right edge, by a margin

    o = head(
        w,
        h,
        "claude-infrastructure",
        "The words claude-infrastructure set in monospace on a dark plate, above a dotted "
        "horizon line that runs the full width. The orange Claude Code pixel creature stands "
        "on the same line to the right of the words. The title is present the whole time; the "
        "only movement is the creature idling — glancing left, glancing right, and occasionally "
        "stretching both arms above its head — on a loop that repeats indefinitely.",
    )
    o += plate(w, h)
    o.append(timeline(px))
    o.append(ground(w, base))

    # The constant. Painted once, animated never.
    o.append(
        f'<text class="f" x="{w / 2:g}" y="{base - 40:g}" text-anchor="middle" fill="{TITLE}" '
        f'font-size="{title_px}" letter-spacing="{TITLE_TRACK}">{WORDMARK}</text>'
    )
    o.append(
        f'<text class="f" x="{w / 2:g}" y="{base + 50:g}" text-anchor="middle" fill="{DIM}" '
        f'font-size="22" letter-spacing="3.4">SESSIONS RUN EACH OTHER</text>'
    )

    o.append(
        cs.sprite(px, cx, base - cs.H * px, "default", idp="clawd", plate=PLATE_BOT)
    )
    o.append("</svg>")
    return "\n".join(o)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("what", choices=["kit"])
    a = ap.parse_args()
    print({"kit": kit}[a.what]())
    return 0


if __name__ == "__main__":
    sys.exit(main())
