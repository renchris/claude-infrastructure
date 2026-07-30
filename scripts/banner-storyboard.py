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
.mo{fill:var(--sb-label,#7f8a9a)}
.ln{stroke:var(--sb-line,#57616f);stroke-width:1;fill:none}
.lf{stroke:var(--sb-linedim,#2c333f);stroke-width:1;fill:none}
.fn{font:500 10px ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.03em}
.fnum{fill:var(--sb-accent,#D77757)}
.flab{fill:var(--sb-label,#7f8a9a)}
.frate{fill:var(--sb-dim,#6e7681)}
"""

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


def sweep(x: float) -> str:
    """The deploy sweep: one dim column, and its whole payload is that nothing it passes changes."""
    return f'<g class="sw"><rect x="{x:g}" y="34" width="2" height="{BASE - 34}"/></g>'


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
            f'<g transform="translate({col * (FW + GAP)} {PAD})">'
            f'<rect width="{FW}" height="{FH}" rx="5" class="frm"/>'
            f"{inner}"
            f'<text class="fn" x="10" y="{LBL_Y}">'
            f'<tspan class="fnum">{col + 1}</tspan>'
            f'<tspan class="flab">  {html.escape(self.label)}</tspan></text>'
            f'<text class="fn frate" x="{FW - 8}" y="18" text-anchor="end">'
            f"{_rate_text(self.rate)}</text></g>"
        )


# ── the ten beats ───────────────────────────────────────────────────────────────────────────────

RX = 96.0  # THE RECALL frames what is BEHIND, so its walker sits right of centre
W_BIG = Creature(BIG, AX)
W_LEFT = Creature(BIG, AX, "look-left")
W_RIGHT = Creature(BIG, AX, "look-right")
V_SML = Creature(SML, BX, "look-left")
R_BIG = Creature(BIG, RX)
R_LEFT = Creature(BIG, RX, "look-left")
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
        status="spec'd (O3) · ship first",
        reach="no code needed",
        cause="Nothing in the repo, and that is the honest ground. Tracking a moving thing is "
        "human-universal; this beat is defended on the same basis as THE ASK rather than given a "
        "mechanism-mapping it does not need.",
        behaviour="The gaze LEADS by ~0.5 s: the eye holes shift one cell before anything is "
        "there. Then a single travelling dash descends through the LOW sky toward the horizon, and "
        "the eyes track it down.",
        exit_="The dash goes out at the horizon; the eyes return to centre. One-shot, no residue, "
        "nothing to repay.",
        mech="None claimed. The event is the NOTICING, not the star — which is also why the star "
        "never crosses the top of the frame: nothing is ever authored above y=340, so the wordmark "
        "keep-out holds by construction rather than by a check.",
        cost_tag="rate: free · sky-only",
        cost="Zero, and it is the cheapest beat available anywhere in the set: a pose change is "
        "not a world change, and a sky-only feature has no strip occupancy at all.",
        note="The only beat fully legible to a stranger in BOTH schemes — one geometry, two paints "
        "(warm head plus tail at night, dark silhouette by day), so the timing and the gaze "
        "choreography are identical and there is one animation to verify instead of two. The "
        "gaze-leads ordering is what stops the dash reading as a stray pixel: by the time it "
        "appears the viewer is already looking where it will be.",
        frames=(
            Frame("ambient · eyes centred", 1, (W_BIG,)),
            Frame("gaze LEADS · sky empty", 1, (W_RIGHT,)),
            Frame("the dash appears", 1, (W_RIGHT,), back=star(4, 176, 42)),
            Frame("eyes track it down", 1, (W_RIGHT,), back=star(4, 148, 66)),
            Frame("out at the horizon", 1, (W_BIG,), back=star(4, 122, 96, tail=1)),
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
        key="lane",
        name="THE LANE",
        status="new · specified here (was named, never spec'd)",
        reach="partly coded",
        cause="A second writer starts. Two writers cannot share one git index — a bare commit in "
        "one session sweeps the other's staged files — so isolation is the precondition, not a "
        "convenience.",
        behaviour="The ground FORKS. A second print row peels off below the first and runs "
        "parallel for ~2 s at the same pitch. The walker stays on its own row and never crosses, "
        "and NOTHING walks the other lane.",
        exit_="The two rows converge back into one, at the same pitch and phase. That convergence "
        "is the land, and the payload is that the record is single again.",
        mech="A worktree per writer (`claude -w`, handed out warm in ~3 s) funnelling into exactly "
        "one machine-wide `land-lock.sh` around the CAS push window.",
        cost_tag="rate: free · widest strip footprint",
        cost="No rate change, but a fork has to be authored ON the strip, so 20-26 s of canvas and "
        "the largest footprint of anything here. The spec's cut order puts it second for exactly "
        "this reason — most infographic-prone, widest footprint.",
        note="A fork and a merge is legible with no code. What is NOT legible is that the other "
        "lane is a PEER SESSION: an empty lane reads as a road, not as a colleague. That is the "
        "honest price of refusing to put a second creature there — which the spec does refuse, "
        "because two same-size clawds break the source's own one-saturated-subject rule and a line "
        "joining them rebuilds the rejected handoff infographic.",
        frames=(
            Frame("one row · one writer", 1, (W_BIG,)),
            Frame(
                "the ground FORKS",
                1,
                (W_BIG,),
                ground=print_row()
                + ramp(112)
                + print_row(y=BASE + LANE_DY, x_from=126),
            ),
            Frame(
                "parallel · nobody there",
                1,
                (W_BIG,),
                ground=print_row() + print_row(y=BASE + LANE_DY),
            ),
            Frame(
                "they converge",
                1,
                (W_BIG,),
                ground=print_row()
                + print_row(y=BASE + LANE_DY, x_to=92)
                + ramp(96, down=False),
            ),
            Frame(
                "one row again · the land", 1, (W_BIG,), ground=print_row(mark=(FOOT,))
            ),
        ),
    ),
    Beat(
        key="advance",
        name="THE ADVANCE",
        status="new · specified here · first in the cut order",
        reach="needs the code",
        cause="The background verifier stamps green on the full corpus and the deploy autopilot "
        "advances the live layer on a launchd tick.",
        behaviour="One dim column crosses the frame in the world's own direction. It passes "
        "THROUGH the walker's column without touching it, and everything it passes is exactly as "
        "it was afterwards. The payload IS that nothing changes.",
        exit_="It leaves at the far edge. The eyes flick to it and back. Nothing is left behind at "
        "all.",
        mech="`postland-verify.sh` (fresh cell, host suites partitioned out) green stamp → "
        "`deploy-live.sh` on a launchd tick → the live `~/.claude`. The live layer only ever "
        "advances to a green stamp; fail-closed.",
        cost_tag="rate: free · screen-pinned overlay",
        cost="Zero — an overlay, pinned, nothing authored on the strip. The second-cheapest beat "
        "here and also the emptiest, which is why the spec ranks it FIRST in the cut order: "
        "weakest exit, ~1 px of payload.",
        note="Honestly poor. 'A sweep passed and nothing changed' is a joke that needs its own "
        "punchline explained, and a stranger reads a scanline artifact or a render bug. It is on "
        "this page so the ruling is visible, not because it should ship. The one thing it has: it "
        "is the only beat whose subject is the deploy axis, which is where this repo's most "
        "expensive incidents live (landed ≠ deployed).",
        frames=(
            Frame("ambient · the control", 1, (W_BIG,)),
            Frame("the sweep enters", 1, (W_BIG,), back=sweep(178)),
            Frame("it crosses · eyes flick", 1, (W_RIGHT,), back=sweep(72)),
            Frame("nothing changed", 1, (W_BIG,), back=sweep(24)),
            Frame("gone · no residue", 1, (W_BIG,)),
        ),
    ),
    Beat(
        key="recall",
        name="THE RECALL",
        status="new · fills the one gap in the set",
        reach="partly coded",
        cause="Something a previous session wrote is needed again — a file version restored, a "
        "plan revision recovered, a full-text hit in the archive of every conversation.",
        behaviour="The gaze goes BACKWARD first, one cell, toward the prints already made. Then a "
        "pale letter rises OUT of an old print behind the walker, drifts forward faster than the "
        "world, and is absorbed at the body: the record handing something back.",
        exit_="Absorbed, not faded — it reaches the walker and is gone into it. The print it came "
        "out of stays exactly as it was, because nothing was consumed.",
        mech="`backup-before-write.sh` + `restore-file` (every file version) · "
        "`plan-version-commit.sh` MANIFEST.jsonl (every plan revision) · the SQLite FTS5 index "
        "behind `claude-search` (every conversation, 5,709 of them).",
        cost_tag="rate: free · pinned, moves faster than the world",
        cost="Zero. The letter is pinned in screen space just behind the walker and overtakes the "
        "world, so nothing is authored on the strip and nothing needs repaying. It is the "
        "cheapest of the four new beats.",
        note="Partly coded: it needs prints = the record, which the strip teaches passively over "
        "the whole loop. But 'something came back out of the ground it had already walked' reads "
        "as memory to most viewers, and the BACKWARD gaze is what makes it read as retrieval "
        "rather than as litter. Why it is worth a slot: README §4 ('nothing a session did dies "
        "with it') is currently carried only as a permanent STATE — no beat plays it.",
        frames=(
            # This is the one beat whose subject is BEHIND the walker, so it is the one row framed
            # with the walker right of centre. Left of AX there are only 22 px of visible ground —
            # the letter and the marked print both landed under the body and read as nothing.
            Frame("ambient · prints behind", 1, (R_BIG,), ground=print_row(mark=(47,))),
            Frame("gaze goes BACK", 1, (R_LEFT,), ground=print_row(mark=(47,))),
            Frame(
                "rises out of an old print",
                1,
                (R_LEFT,),
                ground=print_row(mark=(47,)),
                back=letter(6, 47, BASE - 22),
            ),
            Frame(
                "it overtakes the world",
                1,
                (R_LEFT,),
                ground=print_row(mark=(47,)),
                back=letter(6, 70, BASE - 40),
            ),
            Frame(
                "absorbed · print unchanged",
                1,
                (R_BIG,),
                ground=print_row(mark=(47,)),
                back=burst(4, 84, BASE - 32, 3, 6),
            ),
        ),
    ),
    Beat(
        key="index",
        name="THE INDEX",
        status="new · beautiful, and night-only",
        reach="partly coded",
        cause="A session ends and is indexed. The pane is disposable; what it produced is not.",
        behaviour="Three or four stars ALREADY scattered in the low sky are joined by one thin "
        "line, drawn one segment at a time in the world's direction. It joins stars only, never a "
        "creature.",
        exit_="The line fades and the stars stay. That is the whole point: the joining was the "
        "event, the record is what remains.",
        mech="The append-only `MANIFEST.jsonl` plus the self-maintaining FTS5 index (a crash-safe "
        "stub at SessionStart, rich metadata at SessionEnd, a 60 s sweep daemon catching misses).",
        cost_tag="rate: free · sky-only",
        cost="Zero — sky-only, pinned, one eye shift and no creature displacement. Structurally "
        "the cheapest of the four new beats alongside THE RECALL.",
        note="NIGHT-ONLY, and on this page's own standard that is close to disqualifying: half the "
        "viewers never see it, and the shooting star was deleted partly for exactly that. It also "
        "sits one step from the rejected infographic — the rule that saves it is that lines may "
        "join STARS and may never have a creature as an endpoint. Ranking: the most beautiful of "
        "the four new beats and the least shippable. It re-enters if the day scheme ever gets a "
        "counterpart geometry.",
        frames=(
            Frame("night · stars scattered", 1, (W_BIG,), back=constellation(0)),
            Frame("gaze over · one segment", 1, (W_RIGHT,), back=constellation(1)),
            Frame("the line completes", 1, (W_RIGHT,), back=constellation(3)),
            Frame("the line fades", 1, (W_BIG,), back=constellation(3, fading=True)),
            Frame("the stars remain", 1, (W_BIG,), back=constellation(0)),
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
    n = len(beat.frames)
    w = n * FW + (n - 1) * GAP
    h = FH + 2 * PAD
    body = "".join(f.render(i, beat.key) for i, f in enumerate(beat.frames))
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
        f'role="img" aria-label="{html.escape(beat.name)} — {n} frames">'
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
    return (
        f"<section class='beat' id='{b.key}'><header>"
        f"<h2><span class='n'>{i + 1:02d}</span>{html.escape(b.name)}</h2>"
        f"<span class='pill cost'>{html.escape(b.cost_tag)}</span>"
        f"{_pill_reach(b.reach)}"
        f"<span class='pill'>{html.escape(b.status)}</span></header>"
        f"<div class='frames'>{row_svg(b)}</div>"
        f"<dl class='cbe'>{dl}</dl></section>"
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
        "<div class='legend'>"
        "<span><b>rate N</b> top-right of every frame — the world's scroll rate. "
        "The vocabulary is {&#8722;1, 0, 1, 2, 3} and nothing between.</span>"
        "<span><b>&#9666;&#9666;</b> countable chevrons under the ground repeat that rate; "
        "a stop draws none.</span>"
        "<span><b>orange print</b> = one marked print. A uniform lattice shifted by exactly one "
        "period is identical to itself, so the mark is the only observable.</span>"
        "<span><b>clear plate</b> between two creatures is asserted at &#8805;2 cells on every "
        "frame, not eyeballed.</span></div>"
        f"{_glance(beats)}"
        + "".join(_section(i, b) for i, b in enumerate(beats))
        + "<footer>Generated by <code>scripts/banner-storyboard.py</code>. Geometry from "
        "<code>scripts/clawd-sprite.py</code> (asserted against the extracted grid on every run); "
        "rulings from <code>docs/plans/BANNER_NARRATIVE_SPEC.md</code> &#167; BETTER MICRO-EVENTS. "
        "Rows 07-10 are new and are specified here for the first time. Frames are 200 px wide; the "
        "beats themselves are judged at the 838 px README column, never at 1:1.</footer>"
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
