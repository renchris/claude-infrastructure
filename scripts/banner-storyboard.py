#!/usr/bin/env python3
"""banner-storyboard.py — ten candidate micro-events, storyboarded so they can be picked by looking.

WHY THIS FILE EXISTS. The banner's beats were being chosen from prose. Prose hides the two things
that actually decide a beat: whether the sprite can perform it at all, and what it costs the loop.
docs/plans/BANNER_NARRATIVE_SPEC.md § "BETTER MICRO-EVENTS" measured the sprite's whole vocabulary —
a body hop (21 CSS px at the 838 px render), an eye shift (10.5 px), an arm rise (a 10.5 x 21 px
sliver, the WEAKEST move despite the largest travel) — and the ranking is invisible in a sentence
and obvious in a frame. So this emits frames.

WHAT IT IS NOT. Not an animation, not a build input, and it does not touch tools/banner/gen.py. It
is a decision surface: ten beats, four to six frames each, every frame drawn from the real geometry
in scripts/clawd-sprite.py rather than from a redrawn approximation. If a pose is not in that
module's quoted pose table, it cannot appear here either — which is the point. THE ASK's blink is
the single exception in the whole page and it is labelled as one, because the honest way to add a
move outside the source vocabulary is to name it, not to smuggle it in.

WHAT IT ASSERTS, so the page cannot lie:
  * cs.verify()          — the sprite parts still reconstruct the extracted 11 x 8 grid.
  * _fits()              — every drawn rect, text and line lies inside its 200 x 150 frame box. The
                           storyboard generator this one generalises shipped a viewBox that did not
                           cover its own content, and clipped art reads as a design choice.
  * frame(creatures=...)  — creatures are a frame PARAMETER, not free geometry, so the >= 2 cells of
                           clear plate between any two of them is checked on every frame rather
                           than eyeballed. Two same-size clawds are refused outright: the binary's
                           own art direction is "one saturated orange subject".
  * _label_fits()        — a label that would overflow its frame fails the build instead of the
                           review.

  scripts/banner-storyboard.py                       # all ten, to a temp dir, prints the path
  scripts/banner-storyboard.py --out /tmp/storyboards --open
  scripts/banner-storyboard.py --only noticing,landing
"""

from __future__ import annotations

import argparse
import html
import importlib.util
import math
import pathlib
import re
import subprocess
import sys
import tempfile
import types
from dataclasses import dataclass, field

# ── the sprite is imported, never redrawn ───────────────────────────────────────────────────────
# Resolved from this file's own directory so the script works from a worktree as well as from the
# checkout it was written in. A hardcoded absolute path is how the reference generator became
# unrunnable anywhere but one machine.


def _load_sprite() -> types.ModuleType:
    path = pathlib.Path(__file__).resolve().parent / "clawd-sprite.py"
    spec = importlib.util.spec_from_file_location("clawd_sprite", path)
    if spec is None or spec.loader is None:  # pragma: no cover - import plumbing
        raise SystemExit(f"banner-storyboard: cannot import {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


cs = _load_sprite()

# ── frame geometry ──────────────────────────────────────────────────────────────────────────────
FW, FH = 200, 150  # one frame box
GAP = 12  # between frames
PAD = 4  # row padding, top and bottom
BASE = 112  # the ground line: every creature's feet land here
BIG, SML = (
    7,
    5,
)  # px per sprite cell: the walker, and the binary's smaller in-session clawd
AX = 30  # the walker's left edge
BX = (
    AX + 11 * BIG + 4 * BIG
)  # the visitor: four BIG cells of clear plate after the walker
GAP_X = AX + 11 * BIG + BIG  # inside the clear band — where a prop is handed ACROSS
PITCH = 13  # the print pitch: one stride of record
LBL_Y = FH - 12
LBL_PX = 6.0  # measured advance width of the 10 px mono label, for the overflow assert
CLEAR_CELLS = 2  # minimum clear plate between two creatures, in cells of the larger one

# ── every paint is a class, so one stylesheet themes ten SVGs ───────────────────────────────────
# The body orange is the one literal: #D77757 is correct in both schemes and is the whole reason
# the composition can only afford one saturated subject.
SVG_CSS = """
.bd{fill:#D77757}
.pl{fill:var(--sb-plate,#11151d)}
.frm{fill:var(--sb-plate,#11151d);stroke:var(--sb-stroke,#242b38)}
.gr{fill:var(--sb-ground,#39404e)}
.mk{fill:var(--sb-accent,#D77757)}
.pp{fill:var(--sb-prop,#f4ead8)}
.pf{fill:var(--sb-fold,#c9b6a0)}
.hk{fill:var(--sb-hat,#4a5462)}
.sp{fill:var(--sb-spark,#ffd9a0)}
.ck{fill:var(--sb-cake,#e0c9a8)}
.ic{fill:var(--sb-icing,#f7f1e6)}
.fl{fill:var(--sb-flame,#ffcf6b)}
.st{fill:var(--sb-star,#f4ead8)}
.sd{fill:var(--sb-stardim,#59626f)}
.sw{fill:var(--sb-sweep,#333e50)}
.hz{fill:var(--sb-hazard,#7b8698)}
.mo{fill:var(--sb-label,#7f8a9a)}
.ln{stroke:var(--sb-line,#57616f);stroke-width:1;fill:none}
.lf{stroke:var(--sb-linedim,#2c333f);stroke-width:1;fill:none}
.fn{font:500 10px ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.03em}
.fnum{fill:var(--sb-accent,#D77757)}
.flab{fill:var(--sb-label,#7f8a9a)}
.frate{fill:var(--sb-dim,#6e7681)}
.ko{stroke:var(--sb-dim,#6e7681);stroke-width:1;stroke-dasharray:3 3;fill:none;opacity:.55}
.day .frm{fill:#fbf5ea;stroke:#ddcfb6}
.day .pl{fill:#fbf5ea}
.day .gr{fill:#b0a08a}
.day .st,.day .sd{fill:#4a4133}
.day .pp{fill:#4a4133}
.day .pf{fill:#7d7160}
.day .sp{fill:#a06a1e}
.day .mo,.day .flab{fill:#6d6353}
.day .frate{fill:#7c7264}
.day .ln{stroke:#8d8271}
.day .ko{stroke:#7c7264}
"""

# The wordmark keep-out, as a STORYBOARD ANNOTATION rather than scene content. The binding rule is
# the operator's: lines and travelling features never touch the TYPE. It is not a ban on the sky's
# upper band — that was a convenience invented in the synthesis, and it is what wrongly narrowed
# the shooting star to a low streak. Drawn so the routing decision is visible instead of asserted.
KEEPOUT = (52.0, 14.0, 90.0, 24.0)

# ── primitives ──────────────────────────────────────────────────────────────────────────────────


def cells(
    pts: list[tuple[float, float]], px: float, ox: float, oy: float, cls: str
) -> str:
    """A run of one-cell squares. Pixel art moves in whole cells or it crawls — see the craft
    brief's dither finding — so every prop in this file is built from these and nothing else."""
    r = "".join(
        f'<rect x="{ox + cx * px:g}" y="{oy + cy * px:g}" width="{px:g}" height="{px:g}"/>'
        for cx, cy in pts
    )
    return f'<g class="{cls}">{r}</g>'


@dataclass(frozen=True)
class Creature:
    """A clawd in a frame. `px` carries the size: BIG is the startup walker, SML is the binary's
    own smaller in-session creature (docs/research/CLAWD_SPRITE_EXTRACTION_2026-07-29.md § "The
    idle poses"), which is why a second creature is derived rather than invented."""

    px: float
    x: float
    pose: str = "default"
    dy: float = 0.0
    blink: bool = False

    @property
    def span(self) -> tuple[float, float]:
        return self.x, self.x + 11 * self.px


def _clawd(c: Creature, ident: str) -> str:
    oy = BASE - 8 * c.px + c.dy
    out = cs.sprite(c.px, c.x, oy, c.pose, idp=ident, plate="__PL__", animatable=False)
    out = out.replace('fill="__PL__"', 'class="pl"')
    if out.count('class="pl"') != len(cs.EYES):
        raise SystemExit(
            "banner-storyboard: the sprite's eye fills did not map to the plate class"
        )
    out = out.replace(f'fill="{cs.BODY}"', 'class="bd"')
    if c.blink:
        # The one move outside the quoted pose table: the eye HOLES painted shut with body orange.
        # THE ASK needs it (a stopped creature with no blink reads as a broken image, not as
        # waiting) and it is flagged on the page as an addition rather than presented as shipped.
        out += cells([(e[0], e[1]) for e in cs.EYES.values()], c.px, c.x, oy, "bd")
    return out


def hat(px: float, x: float, dy: float = 0) -> str:
    """Solid crown plus one brim row wider than it. No mid band — it read as a gap."""
    oy = BASE - 8 * px + dy
    crown = [(cx, cy) for cx in range(3, 8) for cy in (-3, -2)]
    brim = [(cx, -1) for cx in range(2, 9)]
    return cells(crown, px, x, oy, "hk") + cells(brim, px, x, oy, "hk")


def letter(px: float, x: float, y: float) -> str:
    """2 x 2 cells of pale against orange: maximum contrast, and trivially legible at 838 px."""
    return cells(
        [(cx, cy) for cx in range(2) for cy in range(2)], px, x, y, "pp"
    ) + cells([(0, 0), (1, 1)], px, x, y, "pf")


def cake(px: float, x: float, y: float) -> str:
    """The one prop that could fail to read: ~3 x 4 cells against a 3 x 3 letter. Rendered here
    precisely so the decision to keep or cut it is made from a frame."""
    return (
        cells([(cx, cy) for cx in range(3) for cy in (1, 2)], px, x, y, "ck")
        + cells([(cx, 0) for cx in range(3)], px, x, y, "ic")
        + cells([(1, -1)], px, x, y, "fl")
    )


def burst(
    px: float, cx: float, cy: float, r: float, n: int = 8, cls: str = "sp"
) -> str:
    """A dot-shower on integer steps, not a particle spray — the NES/SNES idiom, and the only
    thing that reads as a burst at this size. One group, static children: one animated node."""
    pts = sorted(
        {
            (
                round(math.cos(2 * math.pi * i / n) * r),
                round(math.sin(2 * math.pi * i / n) * r),
            )
            for i in range(n)
        }
    )
    return cells(pts, px, cx, cy, cls)


def print_row(
    mark: tuple[float, ...] = (),
    pitch: float = PITCH,
    y: float = BASE,
    w: float = 5,
    x_from: float = 8,
    x_to: float = FW - 8,
) -> str:
    """The record. A uniform lattice shifted by exactly one period is IDENTICAL to itself, which is
    why THE REFUSAL is unreadable without a marked print — the mark is the only observable."""
    xs: list[float] = []
    x = x_from
    while x <= x_to - w:
        xs.append(x)
        x += pitch
    plain = [v for v in xs if all(abs(v - m) > 0.5 for m in mark)]
    out = (
        '<g class="gr">'
        + "".join(
            f'<rect x="{v:g}" y="{y:g}" width="{w:g}" height="2"/>' for v in plain
        )
        + "</g>"
    )
    if mark:
        out += (
            '<g class="mk">'
            + "".join(
                f'<rect x="{m:g}" y="{y - 1:g}" width="{w:g}" height="3"/>'
                for m in sorted(mark)
            )
            + "</g>"
        )
    return out


LANE_DY = 10  # the second print row's offset: far enough to read, inside the label's clearance


def ramp(x: float, down: bool = True) -> str:
    """The stepped join between two print rows: a fork, in the pixel idiom."""
    step = LANE_DY / 4
    pts = [
        (x + i * 3, BASE + (step * (i + 1) if down else LANE_DY - step * i))
        for i in range(4)
    ]
    r = "".join(f'<rect x="{px:g}" y="{py:g}" width="3" height="2"/>' for px, py in pts)
    return f'<g class="gr">{r}</g>'


def shower(spots: tuple[tuple[float, float], ...], px: float = 5) -> str:
    """Named dot positions, for the fall — a burst ring's lower half is hidden behind the body, so
    the descent has to be authored outside the silhouette or it does not read at all."""
    return "".join(cells([(0, 0)], px, x, y, "sp") for x, y in spots)


def barrier(x: float, top: float = BASE - 40, reach: float = 0) -> str:
    """The post, and — once it is over the path — the bar that drops ACROSS it. The spec's words:
    a post arrives riding the ground, then the bar drops across the path."""
    out = f'<rect x="{x:g}" y="{top:g}" width="3" height="{BASE - top:g}"/>'
    if reach:
        out += f'<rect x="{x + 3 - reach:g}" y="{BASE - 26:g}" width="{reach:g}" height="3"/>'
    return f'<g class="gr">{out}</g>'


def chevrons(rate: int) -> str:
    """The rate vocabulary is {-1,0,1,2,3} and nothing between — so it renders as countable marks.
    Left for the world moving forward, right for a reversal, nothing at all for a stop."""
    if rate == 0:
        return ""
    n, left = min(abs(rate), 3), rate > 0
    r = []
    for i in range(n):
        x = FW - 14 - i * 7
        a, b = (2, 0) if left else (0, 2)
        r += [(x + a, BASE + 7), (x + b, BASE + 9), (x + a, BASE + 11)]
    return (
        '<g class="mo">'
        + "".join(f'<rect x="{px:g}" y="{py:g}" width="2" height="2"/>' for px, py in r)
        + "</g>"
    )


def star(px: float, x: float, y: float, tail: int = 2) -> str:
    """One travelling dash — one geometry, two paints. The tail steps back up the path it came
    down, so the direction of travel is legible from a still frame."""
    t = "".join(
        cells([(0, 0)], px, x + (i + 1) * px * 1.7, y - (i + 1) * px * 1.5, "sd")
        for i in range(tail)
    )
    return t + cells([(0, 0)], px, x, y, "st")


STARS: tuple[tuple[float, float], ...] = ((150, 44), (178, 58), (132, 66), (166, 86))


def constellation(segments: int, fading: bool = False) -> str:
    """Scattered stars, joined. Lines may join stars; a line joining two creatures rebuilds the
    handoff infographic this whole track rejected, so no creature is ever an endpoint."""
    dots = "".join(cells([(0, 0)], 3, x, y, "st") for x, y in STARS)
    if segments <= 0:
        return dots
    pts = " ".join(f"{x + 1.5:g},{y + 1.5:g}" for x, y in STARS[: segments + 1])
    return f'<polyline class="{"lf" if fading else "ln"}" points="{pts}"/>' + dots


def keepout() -> str:
    """The type keep-out, dashed — a STORYBOARD ANNOTATION, not scene content (see KEEPOUT)."""
    x, y, w, h = KEEPOUT
    return f'<rect class="ko" x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="2"/>'


def bird(px: float, x: float, y: float) -> str:
    """The DAY counterpart of the travelling dash. A meteor is night-only, so by day the same
    travelling group carries a three-cell gull instead of a head-and-trail. The animated node and
    its path are IDENTICAL in both schemes — only the static children inside the group differ, so
    there is still one animation to verify and one set of duty numbers, not two."""
    return cells([(0, 0), (1, 1), (2, 0)], px, x, y, "st")


def hazard(x: float, px: float = 5) -> str:
    """The spike pit: a destructive call arriving on the ground.

    Its own class, NOT the ground's. Drawn in the ground colour and packed at three cells' pitch it
    rendered as a thicker section of ground — the threat and the thing it threatens were the same
    visual family, which is the horns failure in another costume. Lighter value than the ground,
    and one clear cell of plate between spikes so they read as points rather than as a serration."""
    spikes = [
        (cx + i * 4, cy)
        for i in range(3)
        for cx, cy in ((1, 0), (0, 1), (1, 1), (2, 1))
    ]
    return cells(spikes, px, x, BASE - 2 * px, "hz")


def shield(x: float, y: float, px: float = 5) -> str:
    """The hook that refuses: a 2 x 5 cell slab dropping in front of the walker. The hazard breaks
    on it and the walker never breaks stride, which is the entire payload."""
    return cells([(cx, cy) for cx in range(2) for cy in range(5)], px, x, y, "hk")


def wall(x: float, h: float = 46) -> str:
    """The quota cliff: the one thing on the ground the walker cannot pass."""
    return (
        f'<g class="hk"><rect x="{x:g}" y="{BASE - h:g}" width="9" height="{h:g}"/>'
        f'<rect x="{x - 3:g}" y="{BASE - h:g}" width="15" height="5"/></g>'
    )


def vrule(x: float, opened: float = 1.0) -> str:
    """The pane split, CHEAP build: a 2 art-px vertical rule that opens and retracts. It implies a
    second surface without authoring one."""
    top = BASE - 74 * opened
    seg = "".join(
        f'<rect x="{x:g}" y="{y:g}" width="2" height="4"/>'
        for y in range(int(top), int(BASE), 7)
    )
    return f'<g class="sw">{seg}</g>'


def split_frame(x: float, phase: float = 0) -> str:
    """The pane split, EXPENSIVE build: a real frame division, so TWO grounds — and the print lock
    then has to hold across the seam. The right-hand ground is drawn at its own phase, because that
    is exactly the thing that has to be proved and cannot be assumed."""
    return (
        print_row(x_to=x - 4)
        + print_row(x_from=x + 6 + phase, w=4)
        + f'<g class="sw"><rect x="{x:g}" y="20" width="2" height="{BASE - 14:g}"/></g>'
    )


# ── the frame box ───────────────────────────────────────────────────────────────────────────────

_RECT = re.compile(
    r'<rect x="([-\d.]+)" y="([-\d.]+)" width="([\d.]+)" height="([\d.]+)"'
)
_POLY = re.compile(r'points="([^"]+)"')


def _fits(inner: str, where: str) -> None:
    """Every drawn thing inside its own 200 x 150 box. The generator this one generalises emitted a
    viewBox that did not cover its content, and a clipped frame reads as intent."""
    bad: list[str] = []
    for m in _RECT.finditer(inner):
        x, y, w, h = (float(g) for g in m.groups())
        if x < 0 or y < 0 or x + w > FW or y + h > FH:
            bad.append(f"rect {x:g},{y:g} {w:g}x{h:g}")
    for m in _POLY.finditer(inner):
        for pt in m.group(1).split():
            x, y = (float(v) for v in pt.split(","))
            if not (0 <= x <= FW and 0 <= y <= FH):
                bad.append(f"point {x:g},{y:g}")
    if bad:
        raise SystemExit(
            f"banner-storyboard: {where} draws outside its frame: {'; '.join(bad)}"
        )


def _label_fits(label: str, where: str) -> None:
    """The label owns its whole line (the rate badge sits on the top edge, not beside it), so the
    only thing that can overflow is the label itself — and it fails the build, not the review."""
    used = (
        10 + (len(label) + 3) * LBL_PX
    )  # x offset, then "N" plus two spaces, then the label
    room = FW - 12
    if used > room:
        raise SystemExit(
            f"banner-storyboard: {where} label {label!r} needs {used:.0f}px, has {room:.0f}px"
        )


def _rate_text(rate: int) -> str:
    return f"rate {'−' if rate < 0 else ''}{abs(rate)}"


def _check_clear(creatures: tuple[Creature, ...], where: str) -> None:
    """>= 2 cells of clear plate between any two creatures, and never two of the same size: the
    source's own art direction is one saturated orange subject."""
    if len(creatures) < 2:
        return
    if len({c.px for c in creatures}) == 1:
        raise SystemExit(
            f"banner-storyboard: {where} puts two same-size clawds on one frame"
        )
    ordered = sorted(creatures, key=lambda c: c.x)
    for a, b in zip(ordered, ordered[1:]):
        need = CLEAR_CELLS * max(a.px, b.px)
        got = b.span[0] - a.span[1]
        if got < need:
            raise SystemExit(
                f"banner-storyboard: {where} clear plate {got:g}px < {need:g}px required"
            )


@dataclass(frozen=True)
class Frame:
    label: str
    rate: int
    creatures: tuple[Creature, ...] = ()
    back: str = ""  # behind the creatures
    front: str = ""  # in front of them
    ground: str | None = None  # None = the default print row
    day: bool = False  # force the DAY plate regardless of the page theme

    def render(self, col: int, key: str) -> str:
        where = f"{key}/{col + 1}"
        _label_fits(self.label, where)
        _check_clear(self.creatures, where)
        body = "".join(
            _clawd(c, f"{key}{col}{i}") for i, c in enumerate(self.creatures)
        )
        g = print_row() if self.ground is None else self.ground
        inner = g + chevrons(self.rate) + self.back + body + self.front
        _fits(inner, where)
        return (
            f'<g class="{"day" if self.day else "night"}" '
            f'transform="translate({col * (FW + GAP)} {PAD})">'
            f'<rect width="{FW}" height="{FH}" rx="5" class="frm"/>'
            f"{inner}"
            f'<text class="fn" x="10" y="{LBL_Y}">'
            f'<tspan class="fnum">{col + 1}</tspan>'
            f'<tspan class="flab">  {html.escape(self.label)}</tspan></text>'
            f'<text class="fn frate" x="{FW - 8}" y="18" text-anchor="end">'
            f"{_rate_text(self.rate)}</text></g>"
        )


@dataclass(frozen=True)
class Variant:
    """A second, shorter strip under a beat's main strip — for a counterpart that has to be SEEN
    rather than described: the day-scheme paint of a night-only beat, or the expensive build of a
    move whose cheap build is what the main strip shows."""

    caption: str
    frames: tuple[Frame, ...]


# ── the ten beats ───────────────────────────────────────────────────────────────────────────────

RX = 96.0  # a beat whose subject is BEHIND the walker frames it right of centre
W_BIG = Creature(BIG, AX)
W_LEFT = Creature(BIG, AX, "look-left")
W_RIGHT = Creature(BIG, AX, "look-right")
V_SML = Creature(SML, BX, "look-left")
R_BIG = Creature(BIG, RX)
R_LEFT = Creature(BIG, RX, "look-left")
R_DROP = Creature(BIG, RX, dy=BIG)  # one cell down: the only "loss" cue the sprite has
FOOT = 99.0  # the lattice print under the walker's leading foot
CAKE_X = 113.0  # mid clear band: 6 px off the walker, 4 px off the visitor


@dataclass(frozen=True)
class Beat:
    key: str
    name: str
    status: str
    reach: str  # stranger-legibility grade, three values only
    cause: str
    behaviour: str
    exit_: str
    mech: str
    cost_tag: str
    cost: str
    note: str
    frames: tuple[Frame, ...] = field(default_factory=tuple)
    variant: Variant | None = None


BEATS: tuple[Beat, ...] = (
    Beat(
        key="summoning",
        name="THE SUMMONING",
        status="spec'd (O1-b) · being built now",
        reach="no code needed",
        cause="The walker needs work done that it will not do itself, so it puts a hat on. The hat "
        "is load-bearing, not decoration: it is what converts an unexplained spawn into a caused "
        "one, and a creature fading in from nothing is exactly the origin-less entrance this spec "
        "spent pages deleting.",
        behaviour="A sparkle bursts in the clear band and the binary's own SMALLER clawd is "
        "standing in it. The walker looks right and hands a pale letter across the gap; the "
        "visitor hands back a cake. Both keep striding the whole time — nobody stops.",
        exit_="The visitor poofs. A self-removal is a stronger goodbye than a wave (and is what a "
        "subagent actually does — its final output IS its return value, then it is gone). The hat "
        "comes off; the cake stays with the walker.",
        mech="An Agent subagent: dispatch a brief, receive the result, the agent ceases to exist. "
        "The alternative reading, O1-a, is `handoff-fire.sh self-close --successor` — there the "
        "SUMMONER leaves and the visitor walks on, and the loop closes by substitution.",
        cost_tag="rate: free · screen-pinned",
        cost="Zero. Both creatures are pinned in screen space and keep striding, so no rate "
        "modulation and nothing authored on the strip. The risk here is never cost, it is LENGTH: "
        "six sub-beats cannot be read in a ~10 s dwell, which is why the wand and the wave are cut.",
        note="Legible with no code at all — hat, errand, gift. The one prop that can fail is the "
        "CAKE: ~3 x 4 cells against the letter's 2 x 2, and frames 5-6 are the render that decides "
        "it — and the render's verdict is already visible here: at this scale the cake reads as a "
        "small pale PARCEL with a candle on it, not as a cake. That may be enough (a gift is the "
        "same beat) but it is not what the sketch asked for, and O1-a needs no cake at all. Note "
        "too that the poof REPLACES the "
        "visitor rather than covering it — a burst drawn over a body that is still there reads as "
        "damage, not as a departure.",
        frames=(
            Frame("walks the record", 1, (W_BIG,)),
            Frame(
                "hat on · sparkle",
                1,
                (W_RIGHT,),
                front=hat(BIG, AX) + burst(4, 128, BASE - 34, 4),
            ),
            Frame("a SMALLER clawd stands", 1, (W_RIGHT, V_SML), front=hat(BIG, AX)),
            Frame(
                "the brief, across the gap",
                1,
                (W_RIGHT, V_SML),
                front=hat(BIG, AX) + letter(6, GAP_X, BASE - 40),
            ),
            Frame(
                "the cake comes back",
                1,
                (Creature(BIG, AX, "look-right", dy=-2 * BIG), V_SML),
                front=hat(BIG, AX, dy=-2 * BIG) + cake(6, CAKE_X, BASE - 46),
            ),
            Frame(
                "it poofs · A keeps it",
                1,
                (W_BIG,),
                front=hat(BIG, AX)
                + cake(6, CAKE_X, BASE - 46)
                + burst(5, BX + 27, BASE - 25, 5),
            ),
        ),
    ),
    Beat(
        key="landing",
        name="THE LANDING",
        status="spec'd (O2)",
        reach="no code needed",
        cause="A commit reaches origin/main and its CONTENT is verified there — the one moment in "
        "the whole pipeline that is unambiguously good news.",
        behaviour="6-10 one-cell dots expand above the walker on whole-cell steps, and the walker "
        "HOPS: the entire 115 x 84 px silhouette displaced by 21 px, the strongest move it has. "
        "Arms-up appears only at the top of the hop, as accent — never alone.",
        exit_="The dots fall and go out; the walker lands back into stride on the next print. No "
        "residue, nothing left on the strip.",
        mech="`ship-land.sh` → `land-lock.sh` holds the CAS push window → `land-verify.sh` "
        "verifies by content, because a commit-count check reads 'landed' for work that was "
        "silently dropped.",
        cost_tag="rate: free · but hops are budgeted",
        cost="Zero rate change and zero strip occupancy while it stays screen-pinned above the "
        "creature. One exception that is NOT free: a hop is a stride_in_place, so "
        "strip_length = 28.8 x (strides_taken - strides_in_place) changes and must stay divisible "
        "by the print pitch. The number of hops is constrained, not chosen.",
        note="The most legible beat in the set to a stranger: a jump plus a burst is celebration in "
        "every visual idiom on earth. The mechanism is invisible and does not need to be read. It "
        "also legalises the deleted 4 s hop — the deletion rule was 'voluntary must map to a "
        "mechanism, or cut', and a hop on a land IS mapped. Frame 4 is also the ladder's own "
        "evidence: raised arms read as two horns at this size, which is the measured failure, "
        "and it is why they may only ever accent a hop.",
        frames=(
            Frame("ambient · the control", 1, (W_BIG,)),
            Frame(
                "dots · whole-cell steps", 1, (W_BIG,), back=burst(5, AX + 38, 30, 3)
            ),
            Frame(
                "body HOP · 21 px",
                1,
                (Creature(BIG, AX, dy=-2 * BIG),),
                back=burst(5, AX + 38, 28, 3),
            ),
            Frame(
                "arms-up as ACCENT only",
                1,
                (Creature(BIG, AX, "arms-up", dy=-2 * BIG),),
                back=burst(6, AX + 38, 26, 3),
            ),
            Frame(
                "dots fall past · in stride",
                1,
                (W_BIG,),
                front=shower(((16, 62), (22, 84), (110, 58), (117, 80))),
            ),
        ),
    ),
    Beat(
        key="noticing",
        name="THE NOTICING",
        status="MANDATORY (operator) · spec'd (O3) · ship first",
        reach="no code needed",
        cause="Nothing in the repo, and that is the honest ground. Tracking a moving thing is "
        "human-universal; this beat is defended on the same basis as THE ASK rather than given a "
        "mechanism-mapping it does not need.",
        behaviour="The gaze LEADS by ~0.5 s — the eye holes shift one cell BEFORE anything is "
        "there — and then a single travelling dash crosses the FULL LENGTH of the sky, entering "
        "high on one side and leaving low on the other. The eyes follow it the whole way, so the "
        "gaze arcs right → centre → left, which is three keyframes of a move the sprite already has.",
        exit_="It leaves at the far edge, low; the eyes return to centre. One-shot, no residue, "
        "nothing to repay.",
        mech="None claimed. The event is the NOTICING, not the star. The routing rule is the "
        "operator's actual one: the travelling feature never touches the TYPE — so it passes BELOW "
        "the wordmark box (or behind the cloud bands). The keep-out is on the type, NOT on the "
        "sky's upper band; a full-width traverse is legal, and the earlier 'nothing above y=340' "
        "was a convenience invented in the synthesis, which is what wrongly narrowed this to a low "
        "streak.",
        cost_tag="rate: free · sky-only",
        cost="Zero, and it is still the cheapest beat available: a pose change is not a world "
        "change, and a sky-only feature has no strip occupancy at all. A full-width traverse costs "
        "no more than a short one — the feature is not on the strip, so its dwell is set by its own "
        "duration rather than by the (1920 + width)/96 transit that binds anything riding the ground.",
        note="Fully legible to a stranger, in both schemes — which is why the DAY counterpart is "
        "storyboarded below rather than described. A meteor is night-only, and a reader gets one "
        "scheme and never sees the other, so by day the same travelling group carries a three-cell "
        "gull. The path, the timing and the gaze choreography are IDENTICAL; only the static "
        "children inside the animated group differ, so there is still one animation to verify. The "
        "gaze-leads ordering is what stops it reading as a stray pixel: by the time it appears the "
        "viewer is already looking where it will be.",
        frames=(
            Frame("ambient · eyes centred", 1, (W_BIG,), back=keepout()),
            Frame("gaze LEADS · sky empty", 1, (W_RIGHT,), back=keepout()),
            Frame(
                "enters high, far right",
                1,
                (W_RIGHT,),
                back=keepout() + star(4, 172, 34),
            ),
            Frame(
                "crosses BELOW the type",
                1,
                (W_RIGHT,),
                back=keepout() + star(4, 124, 44),
            ),
            Frame(
                "exits low, far left", 1, (W_LEFT,), back=keepout() + star(4, 22, 78)
            ),
            Frame("gone · eyes centred", 1, (W_BIG,), back=keepout()),
        ),
        variant=Variant(
            caption="DAY counterpart — same group, same path, same timing; the gull is three "
            "static cells instead of a head and a trail, because a meteor is night-only and a "
            "reader gets one scheme and never sees the other. Rendered on the day plate here "
            "regardless of this page's theme, so the comparison does not need a theme switch.",
            frames=(
                Frame(
                    "day · enters high right",
                    1,
                    (W_RIGHT,),
                    back=keepout() + bird(4, 172, 34),
                    day=True,
                ),
                Frame(
                    "day · below the type",
                    1,
                    (W_RIGHT,),
                    back=keepout() + bird(4, 124, 44),
                    day=True,
                ),
                Frame(
                    "day · exits low left",
                    1,
                    (W_LEFT,),
                    back=keepout() + bird(4, 22, 78),
                    day=True,
                ),
            ),
        ),
    ),
    Beat(
        key="refusal",
        name="THE REFUSAL",
        status="spec'd · cut or de-risk (operator's call)",
        reach="needs the code",
        cause="A turn tried to end while the live git ledger disagreed, and a Stop hook sent it "
        "back. The README already draws this as an arrow BACK.",
        behaviour="A post rides in on the ground. The walker settles — it is trying to end the "
        "turn — the bar drops across the path, and the world scrolls BACK exactly one print pitch, "
        "so the foot lands in a print it already made. A returned turn is redoing a step.",
        exit_="By repayment, not by fading: the rate goes to 2 for exactly as long as it was -1, "
        "and the print lock re-registers. There is no gentle catch-up in the vocabulary.",
        mech="`completion-assert.sh` blocks a false 'done' against the live ledger — the one Stop "
        "hook that refuses rather than advises.",
        cost_tag="rate: −1 then 2 · rides the strip",
        cost="The most expensive beat in the set on both axes. A reversal must be repaid inside "
        "the loop at an INTEGER multiple of nominal, and the post rides the scrolling strip, so it "
        "is on canvas (1920 + width)/96 ≈ 20-26 s regardless of its declared window.",
        note="The most coded beat here: it needs the viewer to have already decoded ground = "
        "progress, and it additionally risks reading as a rendering glitch. Note what frames 1-4 "
        "prove — a uniform lattice shifted by exactly one period is IDENTICAL to itself, so the "
        "reversal is literally unobservable without the marked print. That mark is not a "
        "storyboard convenience, it is a build requirement.",
        frames=(
            Frame(
                "print P under the foot", 1, (W_BIG,), ground=print_row(mark=(FOOT,))
            ),
            Frame(
                "a post rides in",
                1,
                (W_BIG,),
                ground=print_row(mark=(FOOT - PITCH,)),
                back=barrier(172),
            ),
            Frame(
                "bar drops · BACK 1 pitch",
                -1,
                (W_BIG,),
                ground=print_row(mark=(FOOT,)),
                back=barrier(132, reach=25),
            ),
            Frame("the same print, twice", 1, (W_BIG,), ground=print_row(mark=(FOOT,))),
            Frame(
                "repaid at rate 2",
                2,
                (W_BIG,),
                ground=print_row(mark=(FOOT - 2 * PITCH,)),
            ),
        ),
    ),
    Beat(
        key="ask",
        name="THE ASK",
        status="spec'd · survived the audit intact",
        reach="no code needed",
        cause="A decision with no default. The system pages a human only when a human must "
        "actually decide something.",
        behaviour="Everything stops. Rate zero. The gaze parks straight out of the frame at the "
        "viewer — and the eyes BLINK once, because a still creature with no blink reads as a "
        "broken image rather than as waiting.",
        exit_="The answer arrives off-screen; the walker steps off and the stop is repaid at rate "
        "2. The cessation is the event, so the resumption has to be visible too.",
        mech="`cc-decide` class C (waits, no default) · `cc-blockers` · the STOP-ASK rule in the "
        "session-close protocol.",
        cost_tag="rate: 0 for ~6 s, repaid at 2",
        cost="Not free — a full stop is the most expensive thing the rate vocabulary can express, "
        "and it must be repaid at an integer multiple. Worth it: in a loop made entirely of "
        "motion, the only cessation is the most salient thing in it.",
        note="Nobody reads 'class C decision packet'; everybody reads 'it stopped and looked at "
        "me'. ⚠ The blink is the single move on this whole page that is NOT in the sprite's quoted "
        "pose table — it is the eye holes painted shut with body orange. It is an addition, and it "
        "is named as one here rather than smuggled in with the poses that are quoted.",
        frames=(
            Frame("rate 1 · walking", 1, (W_BIG,), ground=print_row(mark=(FOOT,))),
            Frame(
                "stops · gaze still off", 0, (W_LEFT,), ground=print_row(mark=(FOOT,))
            ),
            Frame(
                "gaze parks straight out", 0, (W_BIG,), ground=print_row(mark=(FOOT,))
            ),
            Frame(
                "blink — NOT in the table",
                0,
                (Creature(BIG, AX, blink=True),),
                ground=print_row(mark=(FOOT,)),
            ),
            Frame(
                "steps off · repaid at 2",
                2,
                (W_BIG,),
                ground=print_row(mark=(FOOT - PITCH,)),
            ),
        ),
    ),
    Beat(
        key="overlap",
        name="THE OVERLAP",
        status="spec'd · the designated sacrifice",
        reach="needs the code",
        cause="Succession refuses to retire a predecessor until the successor is verified engaged, "
        "so two sessions are briefly both live. Succession OVERLAPS rather than touches.",
        behaviour="The print pitch HALVES for ~12 prints — two walkers' worth of record on one "
        "strip — and the foot then lands on every SECOND print. The mismatch is the entire tell.",
        exit_="By resolution: the pitch halves back and the foot re-registers with the print under "
        "it.",
        mech="`handoff-fire.sh self-close --successor` — a predecessor may not retire until the "
        "successor's transcript proves it engaged.",
        cost_tag="rate: free · pure strip geometry",
        cost="No rate change at all, but it is authored ON the strip, so 20-26 s of canvas "
        "occupancy, and it is the beat that most constrains the print lock (`strip_length` must "
        "stay divisible by the pitch through the halving and back).",
        note="This row exists to make the operator's CUT legible rather than to argue with it. At "
        "838 px the whole event is ~6 px of dash spacing — no creature move, no prop, no colour. "
        "Put row 06 beside row 02 and the difference in what the eye is being asked to detect is "
        "the argument. THE SUMMONING carries the same meaning visibly.",
        frames=(
            Frame(
                "pitch p · foot registers", 1, (W_BIG,), ground=print_row(mark=(FOOT,))
            ),
            Frame(
                "pitch HALVES to p/2",
                1,
                (W_BIG,),
                ground=print_row(mark=(FOOT,), pitch=PITCH / 2, w=4),
            ),
            Frame(
                "foot lands every 2nd print",
                1,
                (W_BIG,),
                ground=print_row(
                    mark=(FOOT, FOOT - PITCH, FOOT - 2 * PITCH), pitch=PITCH / 2, w=4
                ),
            ),
            Frame(
                "…still ~6 px at 838",
                1,
                (W_BIG,),
                ground=print_row(mark=(FOOT - PITCH / 2,), pitch=PITCH / 2, w=4),
            ),
            Frame(
                "pitch back · re-registers", 1, (W_BIG,), ground=print_row(mark=(FOOT,))
            ),
        ),
    ),
    Beat(
        key="guard",
        name="THE GUARD",
        status="MANDATORY-adjacent · new, from an external session, kept near as-is",
        reach="no code needed",
        cause="A tool call arrives that would do damage — an `rm -rf`, an unsanctioned force-push, "
        "a write in the wrong worktree. The point is not that it fails: it never runs at all.",
        behaviour="A hazard tile rides in on the ground ahead of the walker. A shield drops in "
        "front of it, the hazard breaks on the shield, and the walker NEVER breaks stride — same "
        "rate, same pitch, the foot still landing in its print.",
        exit_="The shards go out and the shield lifts. Nothing is left on the ground and nothing "
        "about the walker changed, which IS the payload: a refused call costs the turn nothing.",
        mech="12 `PreToolUse` hooks and 41 deny rules, plus dangerous-bash patterns, wrong-worktree "
        "and unsanctioned-push refusals. All 69 hook entries exit 0 by default — a deliberate "
        "PreToolUse denial is one of only two things in the system that refuse.",
        cost_tag="rate: free · hazard rides the strip",
        cost="No rate change at all — and here the ABSENCE of a rate change is the content, so the "
        "cheap build is also the correct one. The hazard is authored on the ground, so 20-26 s of "
        "canvas transit; the shield can be screen-pinned if the collision is staged at a fixed x, "
        "which is the version to build.",
        note="The strongest of the new ideas. Shield-stops-hazard reads instantly with no code the "
        "viewer lacks, which is exactly what the audited set was short of, and it is all position "
        "and mass at scene scale, so it clears the legibility ladder without leaning on the arm "
        "rise. Staged WITHOUT the sketch's `DENIED — 41 deny rules` caption; see the page preamble "
        "on why no beat here carries text.",
        frames=(
            Frame("ambient · the control", 1, (W_BIG,), ground=print_row(mark=(FOOT,))),
            Frame(
                "a hazard rides in",
                1,
                (W_BIG,),
                ground=print_row(mark=(FOOT,)),
                back=hazard(140),
            ),
            Frame(
                "the shield drops",
                1,
                (W_BIG,),
                ground=print_row(mark=(FOOT,)),
                back=hazard(126),
                front=shield(112, BASE - 48),
            ),
            Frame(
                "it breaks on the shield",
                1,
                (W_BIG,),
                ground=print_row(mark=(FOOT,)),
                front=shield(112, BASE - 25) + burst(4, 138, BASE - 22, 3, 6),
            ),
            Frame(
                "lifts · stride unbroken", 1, (W_BIG,), ground=print_row(mark=(FOOT,))
            ),
        ),
    ),
    Beat(
        key="wall",
        name="THE WALL",
        status="new · the external HANDOFF, adapted — its CAUSE is what it contributes",
        reach="partly coded",
        cause="The account's five-hour window is spent, and the walker hits something it cannot "
        "pass. This is the one thing O1/THE SUMMONING does not have: there the hat is a licence to "
        "materialise with no reason to use it, and here the summon is FORCED.",
        behaviour="A wall rides in and the walker stops at it — rate zero, gaze locked on it. A "
        "vertical rule opens beyond the wall (the pane split) and the binary's own SMALLER clawd is "
        "standing on the far side. The brief hands across the rule.",
        exit_="The predecessor poofs once the successor is verified engaged, and the wall goes out "
        "with it, because a fresh account has a fresh window. The successor walks on — so the "
        "walker at the end of the loop is not the walker at the start, and the loop closes by "
        "SUBSTITUTION rather than by looping.",
        mech="The five-hour quota cliff → `claude-accounts` routing → `handoff-fire.sh`, which "
        "TYPES the launch into a fresh iTerm2 split through the it2 API with echo-verified "
        "keystrokes (the launchers are zsh functions, so no script can `exec` them) → `self-close "
        "--successor`, which refuses to retire the predecessor until the successor's transcript "
        "proves it engaged.",
        cost_tag="rate: 0 at the wall, repaid at 2",
        cost="The stop is what makes 'cannot pass' legible, and a stop is the most expensive thing "
        "the rate vocabulary can express: 0 through the handover, repaid at 2, exactly as THE ASK "
        "pays. The alternative — the wall rides past and nobody stops — is free, but then the cause "
        "stops being legible and the beat reverts to O1's unmotivated hat. Naming that trade is the "
        "point of this row.",
        note="This is the spec's O1-a, SUBSTITUTION, which it recorded as conceptually the "
        "strongest idea available but would not settle on the operator's behalf. With a wall in "
        "front of it, O1-a now has the thing it lacked: a reason. Two rejections carried forward. "
        "The visitor differs in SIZE, never in palette — the binary does ship "
        "`orange_FOR_SUBAGENTS_ONLY` = rgb(217,119,87), two 255ths from the body orange in one "
        "channel: semantically perfect, visually invisible, so colour cannot carry 'a different "
        "account'. And no captions: the sketch labelled these frames `/handoff` and `PING RECEIVED "
        "FROM PEER`.",
        frames=(
            Frame("a wall rides in", 1, (W_RIGHT,), back=wall(168)),
            Frame("it cannot pass · rate 0", 0, (W_RIGHT,), back=wall(116)),
            Frame("the pane splits", 0, (W_RIGHT,), back=wall(116) + vrule(130, 0.55)),
            Frame(
                "a SMALLER clawd, far side",
                0,
                (W_RIGHT, V_SML),
                back=wall(116) + vrule(130),
            ),
            Frame(
                "the brief across the rule",
                0,
                (W_RIGHT, V_SML),
                back=wall(116) + vrule(130),
                front=letter(6, 126, BASE - 58),
            ),
            Frame(
                "A poofs · B takes over",
                2,
                (Creature(SML, 110),),
                ground=print_row(mark=(FOOT - PITCH,)),
                back=burst(5, AX + 38, BASE - 34, 4),
            ),
        ),
        variant=Variant(
            caption="The ⌘D pane split, both builds — because the image is the most interesting "
            "one in the set and its cost is invisible in prose. The main strip uses the CHEAP "
            "build: a 2 art-px rule that opens and retracts, implying a second surface without "
            "authoring one. The EXPENSIVE build is a real frame division, which means TWO grounds "
            "— and the print lock then has to hold across the seam, `strip_length` divisible by "
            "the pitch on each side independently. That is the only thing anywhere on this page "
            "that would double the world.",
            frames=(
                Frame("cheap · a rule opens", 0, (W_RIGHT,), back=vrule(130)),
                Frame(
                    "expensive · TWO grounds",
                    0,
                    (W_RIGHT, V_SML),
                    ground=split_frame(126, phase=5),
                ),
            ),
        ),
    ),
    Beat(
        key="nothing-lost",
        name="NOTHING IS LOST",
        status="new · from an external session, mechanics changed twice",
        reach="partly coded",
        cause="A pane dies mid-turn — a crash, a reap, a context wall. Something the session was "
        "holding drops.",
        behaviour="A pale token falls out of the walker and lands in the print strip, and the gaze "
        "snaps BACK to it. The walker itself does not change pose: the loss is carried by the thing "
        "that leaves and by the look that follows it, because — see the variant below — the sprite "
        "has no move that reads as stumbling.",
        exit_="The strip gives it back. The token rides the record, then rises out of a print and "
        "overtakes the world to the walker. Nothing new is drawn — the ground already meant 'the "
        "record'.",
        mech="`backup-before-write.sh` stamps a backup before every Write/Edit (nanosecond+PID "
        "names, so it is parallel-agent-safe) · `plan-version-commit.sh` MANIFEST.jsonl · the "
        "self-maintaining FTS5 index. Panes are disposable; their output is not.",
        cost_tag="rate: free · the token rides the strip",
        cost="No rate change: nothing about the walker's stride is touched, so the print lock is "
        "undisturbed. The token is authored on the strip for the leg where the record carries it "
        "(the 20-26 s transit); the return leg overtakes the world and is screen-pinned, so it "
        "costs nothing.",
        note="Two changes from the sketch and one from the brief, all three forced by the sprite "
        "rather than chosen. 'clawd trips' is not available — legs never move. The recovery is NOT "
        "a restore-claw swinging in from a vault: the token falls into the print strip and the "
        "strip carries it back, which needs zero new art and is truer to the mechanism. And the "
        "prescribed body DROP does not read either — the variant below is the render that shows "
        "why, and it is the reason the main strip carries the loss on the token and the gaze "
        "instead. This beat supersedes an earlier draft of mine (THE RECALL) that had the same "
        "return leg with no loss to motivate it.",
        frames=(
            Frame("ambient · rate 1", 1, (R_BIG,)),
            Frame("the token falls out", 1, (R_BIG,), back=letter(5, 84, BASE - 44)),
            Frame(
                "it lands in a print",
                1,
                (R_LEFT,),
                ground=print_row(mark=(60,)),
                back=letter(5, 60, BASE - 13),
            ),
            Frame(
                "the strip carries it back",
                1,
                (R_LEFT,),
                ground=print_row(mark=(34,)),
                back=letter(5, 34, BASE - 13),
            ),
            Frame(
                "it rises and overtakes",
                1,
                (R_LEFT,),
                ground=print_row(mark=(34,)),
                back=letter(5, 56, BASE - 36),
            ),
            Frame(
                "absorbed · nothing lost",
                1,
                (R_BIG,),
                ground=print_row(mark=(34,)),
                back=burst(4, 80, BASE - 30, 3, 6),
            ),
        ),
        variant=Variant(
            caption="The prescribed body DROP, and why it is not used above — this is the render "
            "that decides it. A trip was ruled out because legs never animate, and a body drop was "
            "prescribed instead on the ladder's own logic that position change is the strongest "
            "cue. But the feet are what DEFINE the ground line, so dropping the body puts them "
            "below the print row: it reads as the creature sinking INTO the record, not stumbling "
            "on it. There is no way out inside the vocabulary — no squash pose exists, and the "
            "legs are solid 1 x 2 columns that scripts/clawd-sprite.py explicitly forbids moving, "
            "so a body-only drop is unconstructible. The loss cue therefore has to leave the "
            "creature entirely, which is what the main strip does.",
            frames=(
                Frame("feet ON the line", 1, (R_BIG,)),
                Frame("the DROP · feet below", 1, (R_DROP,)),
            ),
        ),
    ),
    Beat(
        key="index",
        name="THE INDEX",
        status="MANDATORY (operator) · night-only",
        reach="partly coded",
        cause="A session ends and is indexed. The pane is disposable; what it produced is not.",
        behaviour="Stars ALREADY scattered in the sky are joined, star to star, in ORDER — drawn "
        "on by `stroke-dashoffset`, quick but not instant, so the figure assembles rather than "
        "appears. Then it holds briefly. Separate points revealed to be one figure is 'sessions run "
        "each other' stated in the sky, which is why this is the best event idea on the table.",
        exit_="The LINES fade and the stars remain. That is the whole point: the joining was the "
        "event, and what is left behind is the record.",
        mech="The append-only `MANIFEST.jsonl` plus the self-maintaining FTS5 index over every "
        "session (a crash-safe stub at SessionStart, rich metadata at SessionEnd, a 60 s sweep "
        "daemon catching the misses).",
        cost_tag="rate: free · sky-only",
        cost="Zero — sky-only, screen-pinned, one eye shift and no creature displacement. "
        "Structurally the cheapest thing on this page alongside THE NOTICING.",
        note="Three constraints, all binding, all visible above. Lines join STARS to STARS and may "
        "NEVER touch a creature — a line to a creature rebuilds the handoff infographic R1 "
        "rejected, so no creature is ever an endpoint. Lines as well as stars stay outside the type "
        "keep-out (the dashed box). And it is NIGHT-ONLY, so it cannot be the only rare event: by "
        "day the sky's event is row 03's gull, and the day scheme's rare-event budget is otherwise "
        "carried by the beats that are scheme-independent because they are on the ground or "
        "screen-pinned — THE GUARD, THE LANDING, THE REFUSAL, THE ASK, THE WALL. The honest "
        "residue: at 838 px a 1 px line between 3 px stars is the faintest thing here, and the "
        "draw-on is what makes it read at all — a line that is simply present reads as a hairline "
        "artifact.",
        frames=(
            Frame(
                "night · stars scattered",
                1,
                (W_BIG,),
                back=keepout() + constellation(0),
            ),
            Frame(
                "draws on, star to star",
                1,
                (W_RIGHT,),
                back=keepout() + constellation(1),
            ),
            Frame(
                "…in order, not at once",
                1,
                (W_RIGHT,),
                back=keepout() + constellation(2),
            ),
            Frame(
                "one figure · it holds",
                1,
                (W_RIGHT,),
                back=keepout() + constellation(3),
            ),
            Frame(
                "the LINES fade",
                1,
                (W_BIG,),
                back=keepout() + constellation(3, fading=True),
            ),
            Frame("the stars remain", 1, (W_BIG,), back=keepout() + constellation(0)),
        ),
    ),
)

# ── emit ────────────────────────────────────────────────────────────────────────────────────────


def row_svg(beat: Beat) -> str:
    """One row. The viewBox is FH + 2*PAD by construction and every frame is asserted to fit inside
    its own box, so the height cannot fail to cover the content.

    The backdrop rect is `--sb-panel`: inside the index page that is exactly the section's own
    background, so it is invisible there, and it is what makes each `sb-*.svg` presentable when
    opened on its own (a standalone SVG gets no page background from the browser, only the UA's
    grey). The var() fallbacks carry the dark scheme when there is no host stylesheet at all."""
    return strip_svg(beat.frames, beat.key, beat.name)


def strip_svg(frames: tuple[Frame, ...], key: str, label: str) -> str:
    n = len(frames)
    w = n * FW + (n - 1) * GAP
    h = FH + 2 * PAD
    body = "".join(f.render(i, key) for i, f in enumerate(frames))
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
        f'role="img" aria-label="{html.escape(label)} — {n} frames">'
        f"<style>{SVG_CSS}</style>"
        f'<rect width="{w}" height="{h}" fill="var(--sb-panel,#0f131b)"/>'
        f"{body}</svg>"
    )


DARK = {
    "page": "#0b0e14",
    "panel": "#0f131b",
    "plate": "#11151d",
    "stroke": "#242b38",
    "ground": "#39404e",
    "label": "#7f8a9a",
    "dim": "#6e7681",
    "text": "#dbe2ec",
    "text2": "#98a2b1",
    "rule": "#1c2230",
    "accent": "#D77757",
    "accentink": "#e08a68",
    "prop": "#f4ead8",
    "fold": "#c9b6a0",
    "spark": "#ffd9a0",
    "hat": "#4a5462",
    "cake": "#e0c9a8",
    "icing": "#f7f1e6",
    "flame": "#ffcf6b",
    "star": "#f4ead8",
    "stardim": "#59626f",
    "line": "#57616f",
    "linedim": "#2c333f",
    "sweep": "#333e50",
    "hazard": "#7b8698",
}
# The prop inversion is not a theming shortcut, it is this spec's own "one geometry, two paints"
# rule applied to the storyboard: what is warm and bright at night is a dark silhouette by day.
LIGHT = {
    "page": "#f4ead8",
    "panel": "#fdf9f1",
    "plate": "#fbf5ea",
    "stroke": "#ddcfb6",
    "ground": "#b0a08a",
    "label": "#6d6353",
    "dim": "#7c7264",
    "text": "#2a251e",
    "text2": "#5d5548",
    "rule": "#e6d9c2",
    "accent": "#D77757",
    "accentink": "#a8492a",
    "prop": "#4a4133",
    "fold": "#7d7160",
    "spark": "#a06a1e",
    "hat": "#2b3140",
    "cake": "#6b5a42",
    "icing": "#4a4133",
    "flame": "#a06a1e",
    "star": "#5d5548",
    "stardim": "#a89a86",
    "line": "#8d8271",
    "linedim": "#cdc0a9",
    "sweep": "#c6b8a0",
    "hazard": "#8a7461",
}
REACH_ORDER = {"no code needed": 0, "partly coded": 1, "needs the code": 2}


def _vars(theme: dict[str, str]) -> str:
    return "".join(f"--sb-{k}:{v};" for k, v in theme.items())


PAGE_CSS = """
*{box-sizing:border-box}
body{margin:0;background:var(--sb-page);color:var(--sb-text);
  font:15px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace;-webkit-font-smoothing:antialiased}
.wrap{max-width:1360px;margin:0 auto;padding:38px 24px 90px}
h1{font-size:23px;letter-spacing:.01em;margin:0 0 6px}
h1 b{color:var(--sb-accentink);font-weight:600}
.lede{color:var(--sb-text2);max-width:96ch;margin:0 0 4px;font-size:13.5px}
.lede em{color:var(--sb-text);font-style:normal}
.top{display:flex;gap:20px;align-items:flex-start;justify-content:space-between}
button{font:12px ui-monospace,Menlo,monospace;color:var(--sb-text2);background:var(--sb-panel);
  border:1px solid var(--sb-stroke);border-radius:6px;padding:7px 12px;cursor:pointer;white-space:nowrap}
button:hover{color:var(--sb-text);border-color:var(--sb-accent)}
table.glance{border-collapse:collapse;width:100%;margin:26px 0 40px;font-size:12.5px}
table.glance th{text-align:left;color:var(--sb-dim);font-weight:500;padding:6px 10px;
  border-bottom:1px solid var(--sb-stroke);text-transform:lowercase;letter-spacing:.06em}
table.glance td{padding:7px 10px;border-bottom:1px solid var(--sb-rule);vertical-align:top}
table.glance tr:hover td{background:var(--sb-panel)}
table.glance a{color:var(--sb-accentink);text-decoration:none}
table.glance a:hover{text-decoration:underline}
td.num{color:var(--sb-dim)}
section.beat{margin:0 0 46px;padding:22px 22px 18px;background:var(--sb-panel);
  border:1px solid var(--sb-stroke);border-radius:10px}
section.beat>header{display:flex;flex-wrap:wrap;gap:10px;align-items:baseline;margin:0 0 4px}
h2{font-size:16.5px;margin:0;letter-spacing:.04em;color:var(--sb-text)}
h2 span.n{color:var(--sb-accentink);margin-right:10px}
.pill{font-size:11px;padding:3px 8px;border-radius:20px;border:1px solid var(--sb-stroke);
  color:var(--sb-text2);white-space:nowrap}
.pill.cost{border-color:var(--sb-accent);color:var(--sb-accentink)}
.pill.r0{border-color:var(--sb-accent);color:var(--sb-accentink)}
.pill.r1{border-color:var(--sb-stroke)}
.pill.r2{border-color:var(--sb-rule);color:var(--sb-dim)}
.frames{overflow-x:auto;margin:14px 0 16px;padding-bottom:4px}
.frames svg{display:block;max-width:100%;height:auto}
.variant{border-left:2px solid var(--sb-accent);padding:2px 0 2px 16px;margin:0 0 18px}
.vcap{margin:0;font-size:12.5px;color:var(--sb-text2);max-width:104ch}
.variant .frames{margin:10px 0 2px}
.calls{margin:22px 0 4px;font-size:12.5px;color:var(--sb-text2);max-width:104ch}
.calls p{margin:0 0 7px}
.calls b{color:var(--sb-text);font-weight:500}
.calls em{color:var(--sb-text);font-style:normal}
.calls code{color:var(--sb-accentink);font-size:12px}
dl.cbe{display:grid;grid-template-columns:14ch 1fr;gap:5px 16px;margin:0;font-size:13px}
dl.cbe dt{color:var(--sb-dim);text-transform:lowercase;letter-spacing:.05em}
dl.cbe dd{margin:0;color:var(--sb-text2)}
dl.cbe dd.hi{color:var(--sb-text)}
dl.cbe code{color:var(--sb-accentink);font-size:12.5px}
.legend{display:flex;flex-wrap:wrap;gap:18px;font-size:12px;color:var(--sb-dim);
  border-top:1px solid var(--sb-rule);padding-top:14px;margin-top:8px}
.legend b{color:var(--sb-text2);font-weight:500}
footer{color:var(--sb-dim);font-size:12px;border-top:1px solid var(--sb-stroke);
  padding-top:16px;margin-top:34px}
@media (max-width:760px){dl.cbe{grid-template-columns:1fr}dl.cbe dt{margin-top:8px}}
"""

LEDGE = (
    "Ten candidates, four to six frames each, every frame drawn from the extracted 11 x 8 sprite in "
    "<code>scripts/clawd-sprite.py</code> — so nothing on this page is a move the creature cannot "
    "actually make. <em>The whole vocabulary is a body hop (21 px at the 838 px render), an eye "
    "shift (10.5 px), and an arm rise that has the most travel and the worst legibility.</em> Shape "
    "change is illegible at this size; position change is not. Legs never move."
)


def _pill_reach(reach: str) -> str:
    return f'<span class="pill r{REACH_ORDER[reach]}">{html.escape(reach)}</span>'


def _glance(beats: tuple[Beat, ...]) -> str:
    rows = "".join(
        f"<tr><td class='num'>{i + 1:02d}</td>"
        f"<td><a href='#{b.key}'>{html.escape(b.name)}</a></td>"
        f"<td>{html.escape(b.cost_tag)}</td>"
        f"<td>{html.escape(b.reach)}</td>"
        f"<td>{html.escape(b.status)}</td></tr>"
        for i, b in enumerate(beats)
    )
    return (
        "<table class='glance'><thead><tr><th></th><th>beat</th><th>what it costs the loop</th>"
        "<th>reach to a stranger</th><th>standing</th></tr></thead>"
        f"<tbody>{rows}</tbody></table>"
    )


def _section(i: int, b: Beat) -> str:
    fields = (
        ("cause", b.cause, True),
        ("behaviour", b.behaviour, True),
        ("exit", b.exit_, True),
        ("mechanism", b.mech, False),
        ("world-rate", b.cost, False),
        ("legibility", b.note, False),
    )
    dl = "".join(
        f"<dt>{k}</dt><dd class='{'hi' if hi else ''}'>{v}</dd>" for k, v, hi in fields
    )
    var = ""
    if b.variant is not None:
        var = (
            f"<div class='variant'><p class='vcap'>{b.variant.caption}</p>"
            f"<div class='frames'>"
            f"{strip_svg(b.variant.frames, b.key + 'v', b.name + ' variant')}</div></div>"
        )
    return (
        f"<section class='beat' id='{b.key}'><header>"
        f"<h2><span class='n'>{i + 1:02d}</span>{html.escape(b.name)}</h2>"
        f"<span class='pill cost'>{html.escape(b.cost_tag)}</span>"
        f"{_pill_reach(b.reach)}"
        f"<span class='pill'>{html.escape(b.status)}</span></header>"
        f"<div class='frames'>{row_svg(b)}</div>"
        f"{var}<dl class='cbe'>{dl}</dl></section>"
    )


def index_html(beats: tuple[Beat, ...]) -> str:
    light = _vars(LIGHT)
    css = (
        f":root{{{_vars(DARK)}}}"
        f"@media(prefers-color-scheme:light){{:root:not([data-theme=dark]){{{light}}}}}"
        f":root[data-theme=light]{{{light}}}"
        f":root[data-theme=dark]{{{_vars(DARK)}}}"
        f"{PAGE_CSS}"
    )
    return (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>Ten candidate micro-events — banner storyboard</title>"
        f"<style>{css}</style></head><body><div class='wrap'>"
        "<div class='top'><div>"
        "<h1>Ten candidate micro-events — <b>pick by looking</b></h1>"
        f"<p class='lede'>{LEDGE}</p></div>"
        "<button id='t' type='button'>theme</button></div>"
        "<div class='calls'>"
        "<p><b>Three standing calls, so they can be overruled rather than discovered.</b></p>"
        "<p><b>1 &#183; No beat carries text.</b> Every captioned frame in the incoming sketches "
        "(<code>DENIED — 41 deny rules</code>, <code>PING RECEIVED FROM PEER</code>, "
        "<code>5,709 sessions indexed</code>, <code>/handoff</code>) is staged here without its "
        "caption. The spec already ruled on this class when it cut the floating Zzz — "
        "<em>UI iconography, not observation</em> — and a beat that needs a caption has not been "
        "staged. There is a mechanical reason too: an SVG loaded as an <code>&lt;img&gt;</code> "
        "cannot load fonts, so any in-scene text inherits the wordmark's fallback-metrics problem. "
        "A deliberate call, not an omission.</p>"
        "<p><b>2 &#183; The keep-out is on the TYPE, not on the sky's upper band.</b> The dashed box "
        "is a storyboard annotation marking the wordmark; travelling features and constellation "
        "lines route around or below it. A full-length sky traverse is therefore legal — the "
        "earlier &lsquo;nothing above y=340&rsquo; was a convenience invented in the synthesis, and "
        "it is what wrongly narrowed the shooting star to a low streak.</p>"
        "<p><b>3 &#183; idle &#8594; event &#8594; idle is not a new rule.</b> It is the spec's own "
        "&#8805;65%-empty-air requirement, plus per-type duty &#8804;4%, aggregate &#8804;25%, and "
        "no type recurring inside 60 s. Measured v5a fails it at 88.1% aggregate duty, so the "
        "constraint is already the binding one — these ten are candidates to choose FROM, never a "
        "set to ship together.</p></div>"
        "<div class='legend'>"
        "<span><b>rate N</b> top-right of every frame — the world's scroll rate. "
        "The vocabulary is {&#8722;1, 0, 1, 2, 3} and nothing between.</span>"
        "<span><b>&#9666;&#9666;</b> countable chevrons under the ground repeat that rate; "
        "a stop draws none.</span>"
        "<span><b>orange print</b> = one marked print. A uniform lattice shifted by exactly one "
        "period is identical to itself, so the mark is the only observable.</span>"
        "<span><b>dashed box</b> = the type keep-out. Annotation, not scene content.</span>"
        "<span><b>clear plate</b> between two creatures is asserted at &#8805;2 cells on every "
        "frame, not eyeballed.</span></div>"
        f"{_glance(beats)}"
        + "".join(_section(i, b) for i, b in enumerate(beats))
        + "<footer>Generated by <code>scripts/banner-storyboard.py</code>. Geometry from "
        "<code>scripts/clawd-sprite.py</code> (asserted against the extracted grid on every run); "
        "rulings from <code>docs/plans/BANNER_NARRATIVE_SPEC.md</code> &#167; BETTER MICRO-EVENTS. "
        "Rows 01-06 are the spec'd set; 03 and 10 are the operator's mandatory pair; 07-10 are "
        "specified here for the first time, 08-10 adapted from an external session's raw sketches. "
        "<b>Cut to make room, named so they are not lost:</b> THE LANE (a fork in the ground for "
        "worktree isolation) and THE ADVANCE (a deploy sweep whose payload is that nothing changes) "
        "&#8212; both were already the spec's own cut order, ADVANCE first; and THE RECALL, which "
        "NOTHING IS LOST supersedes by giving its return leg a loss to motivate it. Frames are "
        "200 px wide; the beats themselves are judged at the 838 px README column, never at "
        "1:1.</footer>"
        "<script>const r=document.documentElement,b=document.getElementById('t');"
        "b.onclick=()=>{const d=r.dataset.theme||"
        "(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark');"
        "r.dataset.theme=d==='dark'?'light':'dark';};</script>"
        "</div></body></html>"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--out", type=pathlib.Path, help="output directory (default: a temp dir)"
    )
    ap.add_argument(
        "--only", help="comma-separated beat keys to emit (default: all ten)"
    )
    ap.add_argument("--open", action="store_true", help="open the index page when done")
    a = ap.parse_args()

    cs.verify()

    beats = BEATS
    if a.only:
        want = [k.strip() for k in a.only.split(",") if k.strip()]
        known = {b.key for b in BEATS}
        if unknown := [k for k in want if k not in known]:
            raise SystemExit(
                f"banner-storyboard: unknown beat(s) {unknown}; have {sorted(known)}"
            )
        beats = tuple(b for b in BEATS if b.key in want)

    out = a.out or pathlib.Path(tempfile.mkdtemp(prefix="banner-storyboard-"))
    out.mkdir(parents=True, exist_ok=True)
    for b in beats:
        (out / f"sb-{b.key}.svg").write_text(row_svg(b), encoding="utf-8")
    index = out / "index.html"
    index.write_text(index_html(beats), encoding="utf-8")

    frames = sum(len(b.frames) for b in beats)
    print(f"{len(beats)} beats · {frames} frames · {index}")
    if a.open:
        subprocess.run(["open", str(index)], check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
