#!/usr/bin/env python3
"""banner-build.py — compose banner candidates from the clawd sprite geometry.

Takes its creature from scripts/clawd-sprite.py, so a composition can never disagree with the
extracted grid. What it adds is everything the sprite does not know about: the plate, the wordmark,
the ground, the sky, and the timeline.

THREE SUBJECTS, three variants each. The subjects are three different answers to the question the
README asks of itself — *how do you run many at once, safely, unattended?* — so they make different
claims rather than being three styles of one idea:

    S1  the world it lives in   (safely)     one creature, the shipped landscape
    S2  the fleet               (many)       several creatures, separate lanes, nothing joining them
    S3  the night shift         (unattended) the shipped NIGHT scene, one creature working under it

Every variant obeys the same four rejections, and they constrain each other:

  R1  whole-system. Nothing depicts a handoff: no threads, no exchanges, no arrows. In S2 the
      ABSENCE of anything joining the creatures is the claim — parallel work that cannot collide.
  R2  the wordmark is a plain <text> with NO animation, opacity or keyframe that reaches it. There is
      no state of the document in which the title is missing; motion only ever touches the creature.
  R3  every animation is `infinite` and every keyframe list starts and ends on the same value, so
      there is no seam. The loop is ambient — an idle cycle quoted from the binary's own pose table
      — rather than a narrative needing a restart.
  R4  the creature is the real 11x8 clawd in #D77757, posing through its real four poses.

Two hard-won rules are baked in:

  * `step-end` throughout. This is a pixel grid: a gaze must JUMP one cell. Sliding a fraction of a
    cell is the tell that whatever drew it did not know it was pixel art.
  * PHASE LIVES IN THE KEYFRAME PERCENTAGES, never in `animation-delay`. banner-shots.sh seeks a
    timestamp by overriding delay on `*`, so authored delays are discarded and a staggered fleet
    would screenshot in lockstep. `hold_cycle` rotates the events inside the period instead, which
    survives the freeze exactly. `--lint` now fails on the delay form.

  scripts/banner-build.py <name> > out.svg        # one variant
  scripts/banner-build.py --all <dir>             # every variant, named by key
  scripts/banner-build.py --list
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import random
import sys

_spec = importlib.util.spec_from_file_location(
    "clawd_sprite", pathlib.Path(__file__).with_name("clawd-sprite.py")
)
cs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cs)

W, H = (
    1920,
    520,
)  # displayed at width=900 -> 244px tall: a header that does not swallow the fold

PLATE_TOP, PLATE_BOT = "#171e27", "#0d1117"
NIGHT_TOP, NIGHT_BOT = "#0f1420", "#080b11"
BORDER, RULE, DIM, TITLE = "#21262d", "#30363d", "#6e7681", "#e6edf3"
HILL, VEG, STAR = "#1e2632", "#2b3542", "#9aa4ae"
# The first pass had these barely off the plate. Quiet is the brief; invisible is a different
# thing, and a tree nobody can see is not restraint, it is noise at the bottom of the frame.

FONT = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace'
WORDMARK = "claude-infrastructure"
TRACK = 1.5
MONO_ADVANCE = 0.6  # every face in the stack advances 0.6em per cell
CAP_HEIGHT = (
    0.72  # cap height as a fraction of the em, for the ink box above the baseline
)

GAZE_S, ARMS_S = 13, 19  # coprime: the composite lands identically once every 247s

# The idle cycle as hold-points: (fraction of the period, value held from there to the next).
# Default dominates both cycles — a header that keeps moving pulls the eye off the page it sits on.
GAZE_HOLDS = [(0.00, 0), (0.28, -1), (0.34, 0), (0.61, 1), (0.67, 0)]
ARMS_HOLDS = [(0.00, 0), (0.86, -3), (0.91, 0)]


def title_width(size: float) -> float:
    return len(WORDMARK) * size * MONO_ADVANCE + (len(WORDMARK) - 1) * TRACK


def hold_cycle(holds: list[tuple[float, int]], phase: float) -> list[tuple[float, int]]:
    """Rotate a hold-point cycle by `phase` and emit ascending keyframe percentages.

    0% and 100% are pinned to the value in force across the wrap, so the loop closes on itself and
    there is nothing to see at the seam. With `step-end` each entry holds until the next.
    """
    rot = sorted(((f + phase) % 1.0, v) for f, v in holds)
    wrap = rot[-1][1]
    out = [(0.0, wrap)] + [(f * 100, v) for f, v in rot if f > 0.0] + [(100.0, wrap)]
    return out


def _kf(
    name: str, holds: list[tuple[float, int]], phase: float, unit: float, axis: str
) -> str:
    body = " ".join(
        f"{p:.4g}%{{transform:translate{axis}({v * unit:g}px)}}"
        for p, v in hold_cycle(holds, phase)
    )
    return f"  @keyframes {name} {{ {body} }}"


class Scene:
    """Accumulates elements plus the per-element keyframes their phases need."""

    def __init__(self, night: bool = False) -> None:
        self.body: list[str] = []
        self.kf: list[str] = []
        self.rules: list[str] = []
        self.night = night
        self.rng = random.Random(20260729)
        # The content's vertical extent, accumulated as it is placed. Composing to absolute y values
        # left every variant clustered in one band with a third of the plate empty below it — the
        # difference between a composition that was designed and one that was merely placed. Each
        # variant now says where things sit RELATIVE to each other and the scene centres itself, so
        # a later nudge to one element cannot silently unbalance the whole frame.
        self.ymin: float = float("inf")
        self.ymax: float = float("-inf")
        self.scenery: list[tuple[str, float, float, float, float]] = []
        self.title_box: tuple[float, float, float, float] | None = None

    def _span(self, top: float, bottom: float) -> None:
        self.ymin = min(self.ymin, top)
        self.ymax = max(self.ymax, bottom)

    def _reserve(self, kind: str, x0: float, y0: float, x1: float, y1: float) -> None:
        """Record scenery so render() can refuse anything sitting behind the wordmark.

        banner-collide checks the CREATURE against the title, because that is the element that moves.
        Scenery is static, so it never tripped that check — and the night tree duly ended up directly
        behind 'ture' in infrastructure, reading as smudges on the type. Dim is not the same as
        harmless: texture behind a title degrades exactly the legibility R2 exists to protect.
        """
        self.scenery.append((kind, x0, y0, x1, y1))

    # ── chrome ────────────────────────────────────────────────────────────────────────────────
    def plate(self) -> None:
        """Records the palette. The plate itself is full-bleed, so render() draws it OUTSIDE the
        centring group — a background that moved with the content would defeat the point."""
        self.grad = (NIGHT_TOP, NIGHT_BOT) if self.night else (PLATE_TOP, PLATE_BOT)

    def ground(
        self, y: float, x1: float = 0, x2: float = W, dash: str = "3 9", op: float = 1.0
    ) -> None:
        self._span(y, y)
        self.body.append(
            f'<line x1="{x1:g}" y1="{y:g}" x2="{x2:g}" y2="{y:g}" stroke="url(#rule)" '
            f'stroke-width="2" stroke-dasharray="{dash}" opacity="{op:g}"/>'
        )

    def wordmark(self, size: float, x: float, y: float, anchor: str = "middle") -> None:
        """The constant. Painted once, animated never — R2 is structural here, not a setting."""
        # No glyph in "claude-infrastructure" has a descender, so the baseline IS the ink bottom.
        self._span(y - size * CAP_HEIGHT, y)
        tw = title_width(size)
        x0 = x if anchor == "start" else x - tw / 2
        self.title_box = (x0, y - size * CAP_HEIGHT, x0 + tw, y)
        self.body.append(
            f'<text class="f" x="{x:g}" y="{y:g}" text-anchor="{anchor}" fill="{TITLE}" '
            f'font-size="{size:g}" letter-spacing="{TRACK}">{WORDMARK}</text>'
        )

    # ── landscape, quoted from the shipped scene ──────────────────────────────────────────────
    def hills(
        self, base: float, spans: list[tuple[float, float, int]], cell: int = 14
    ) -> None:
        """Soft mounds standing in for the scene's `░` rows: dim monochrome texture, never a fill
        that reads as a panel. Built on a coarse cell so they stay pixel-native beside the creature.
        """
        out = []
        for x0, x1, rows in spans:
            cols = int((x1 - x0) // cell)
            for c in range(cols):
                t = c / max(1, cols - 1)
                hgt = int(round(rows * (1 - abs(2 * t - 1)) ** 0.7))
                if hgt <= 0:
                    continue
                out.append(
                    f'<rect x="{x0 + c * cell:g}" y="{base - hgt * cell:g}" width="{cell}" '
                    f'height="{hgt * cell}"/>'
                )
        top = base - max(r for _, _, r in spans) * cell
        self._span(top, base)
        self._reserve("hills", min(s[0] for s in spans), top, max(s[1] for s in spans), base)
        self.body.append(f'<g fill="{HILL}">{"".join(out)}</g>')

    def veg(self, base: float, xs: list[float], cell: int = 9) -> None:
        """The scene's `▒` vegetation — a few cells, not a field."""
        out = []
        for x in xs:
            for dx, dy in ((0, 0), (1, 0), (0, 1), (2, 1), (1, 2)):
                out.append(
                    f'<rect x="{x + dx * cell:g}" y="{base - (dy + 1) * cell:g}" '
                    f'width="{cell}" height="{cell}"/>'
                )
        self._span(base - 3 * cell, base)
        self._reserve("veg", min(xs), base - 3 * cell, max(xs) + 3 * cell, base)
        self.body.append(f'<g fill="{VEG}">{"".join(out)}</g>')

    def tree(self, base: float, x: float, cell: int = 11) -> None:
        """The night variant's `░▓▓███▓▓░` canopy over a `███▓░` trunk."""
        canopy = ["  ▓▓▓  ", " ▓███▓ ", "▓█████▓", " ▓███▓ "]
        out = []
        for r, row in enumerate(canopy):
            for c, ch in enumerate(row):
                if ch != " ":
                    out.append(
                        f'<rect x="{x + c * cell:g}" y="{base - (len(canopy) + 3 - r) * cell:g}" '
                        f'width="{cell}" height="{cell}"/>'
                    )
        for r in range(3):
            out.append(
                f'<rect x="{x + 3 * cell:g}" y="{base - (3 - r) * cell:g}" '
                f'width="{cell}" height="{cell}"/>'
            )
        top = base - (len(canopy) + 3) * cell
        self._span(top, base)
        self._reserve("tree", x, top, x + 7 * cell, base)
        self.body.append(f'<g fill="{VEG}">{"".join(out)}</g>')

    def stars(self, n: int, y0: float, y1: float, slow: bool = False) -> None:
        """A sparse sky. Each star is one element with one animation whose phase is baked into its
        keyframes, so the twinkle is uncorrelated AND every frozen frame is honest.
        """
        self._span(y0, y1)
        for i in range(n):
            x = self.rng.uniform(40, W - 40)
            y = self.rng.uniform(y0, y1)
            s = self.rng.choice((2, 2, 3))
            per = self.rng.choice((7, 9, 11, 13))
            lo, hi = 0.14, self.rng.uniform(0.4, 0.72)
            ph = self.rng.random()
            name = f"tw{i}"
            holds = [(0.0, 0), (0.5, 1), (0.62, 0)]
            rot = hold_cycle(holds, ph)
            body = " ".join(f"{p:.4g}%{{opacity:{hi if v else lo:g}}}" for p, v in rot)
            self.kf.append(f"  @keyframes {name} {{ {body} }}")
            self.rules.append(
                f"  #{name} {{ animation: {name} {per}s step-end infinite; }}"
            )
            self.body.append(
                f'<rect id="{name}" x="{x:.1f}" y="{y:.1f}" width="{s}" height="{s}" '
                f'fill="{STAR}" opacity="{lo}"/>'
            )
        if slow:
            # One mark on a much longer beat than everything around it: the page that is not coming.
            body = " ".join(
                f"{p:.4g}%{{opacity:{0.85 if v else 0.1:g}}}"
                for p, v in hold_cycle([(0.0, 0), (0.93, 1), (0.99, 0)], 0.0)
            )
            self.kf.append(f"  @keyframes twslow {{ {body} }}")
            self.rules.append("  #twslow { animation: twslow 47s step-end infinite; }")
            self.body.append(
                f'<rect id="twslow" x="{W - 168}" y="{y0 + 16:g}" width="3" height="3" '
                f'fill="{STAR}" opacity=".1"/>'
            )

    # ── the creatures ─────────────────────────────────────────────────────────────────────────
    def clawd(
        self,
        px: float,
        x: float,
        base: float,
        phase: float = 0.0,
        idp: str | None = None,
    ) -> None:
        """One creature standing on `base`, idling with its own phase inside the shared periods."""
        idp = idp or f"c{len([r for r in self.rules if 'gaze' in r])}"
        plate = NIGHT_BOT if self.night else PLATE_BOT
        # Balance on the RESTING silhouette. Reserving the arms-up rise here instead put invisible
        # headroom inside the centred band, which tilted every frame to keep room for a pose that
        # shows for half a second in nineteen. Arms-up clearance is banner-collide's job, and it
        # checks real renders at the arms-up timestamp rather than a reservation.
        self._span(base - cs.H * px, base)
        self.body.append(
            cs.sprite(px, x, base - cs.H * px, "default", idp=idp, plate=plate)
        )
        self.kf.append(_kf(f"gaze_{idp}", GAZE_HOLDS, phase, px, "X"))
        self.kf.append(_kf(f"arms_{idp}", ARMS_HOLDS, phase * 0.7, px, "Y"))
        self.rules += [
            f"  #{idp} .eye {{ animation: gaze_{idp} {GAZE_S}s step-end infinite; }}",
            f"  #{idp} .arm {{ animation: arms_{idp} {ARMS_S}s step-end infinite; }}",
        ]

    # ── assembly ──────────────────────────────────────────────────────────────────────────────
    def render(self, title: str, desc: str) -> str:
        top, bot = self.grad
        # Centre the accumulated content band in the plate. The plate and its border are drawn
        # outside this group, being full-bleed.
        if self.title_box is not None:
            tx0, ty0, tx1, ty1 = self.title_box
            for kind, x0, y0, x1, y1 in self.scenery:
                if x0 < tx1 and x1 > tx0 and y0 < ty1 and y1 > ty0:
                    raise SystemExit(
                        f"banner-build: {kind} at ({x0:g},{y0:g})-({x1:g},{y1:g}) sits behind the "
                        f"wordmark ({tx0:g},{ty0:g})-({tx1:g},{ty1:g}). Texture behind the title "
                        f"degrades the legibility R2 protects — move it clear."
                    )
        dy = (H - (self.ymax - self.ymin)) / 2 - self.ymin
        return "\n".join(
            [
                f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" '
                f'height="{H}" role="img" aria-labelledby="t d">',
                f'<title id="t">{title}</title>',
                f'<desc id="d">{desc}</desc>',
                "<defs>",
                f'  <radialGradient id="plate" cx=".5" cy=".38" r=".72">'
                f'<stop offset="0" stop-color="{top}"/>'
                f'<stop offset="1" stop-color="{bot}"/></radialGradient>',
                f'  <linearGradient id="rule" gradientUnits="userSpaceOnUse" x1="0" y1="0" '
                f'x2="{W}" y2="0">'
                f'<stop offset="0" stop-color="{RULE}" stop-opacity="0"/>'
                f'<stop offset=".16" stop-color="{RULE}" stop-opacity=".95"/>'
                f'<stop offset=".84" stop-color="{RULE}" stop-opacity=".95"/>'
                f'<stop offset="1" stop-color="{RULE}" stop-opacity="0"/></linearGradient>',
                "</defs>",
                "<style>",
                f"  .f {{ font-family: {FONT}; }}",
                *self.rules,
                *self.kf,
                "  /* Same artwork, held still. Every cycle begins AND ends on `default`, so the",
                "     frozen frame is one the animation genuinely passes through rather than a",
                "     separate static fallback free to drift from it. */",
                "  @media (prefers-reduced-motion: reduce) {",
                "    /* The creature must freeze as ITSELF. An earlier version swept opacity onto",
                "       .eye and .arm along with the stars, which washed out the arms and let orange",
                "       bleed through the eyes — a degraded fallback wearing the same geometry, which",
                "       is precisely what 'same artwork' rules out. */",
                "    .eye, .arm { animation: none !important; transform: none !important; }",
                "    /* Stars hold mid-twinkle rather than at their dimmest, so the sky still reads. */",
                "    [id^=tw] { animation: none !important; opacity: .45 !important; }",
                "  }",
                "</style>",
                f'<rect width="{W}" height="{H}" rx="14" fill="url(#plate)"/>',
                f'<rect x=".75" y=".75" width="{W - 1.5}" height="{H - 1.5}" rx="14" fill="none" '
                f'stroke="{BORDER}" stroke-width="1.5"/>',
                f'<g transform="translate(0 {dy:.4g})">',
                *self.body,
                "</g>",
                "</svg>",
            ]
        )


# ── the variants ──────────────────────────────────────────────────────────────────────────────
# Each returns a finished SVG. They differ in composition and density only — the medium question is
# settled (vector), so re-testing it would be re-running the check that already passed.

D_COMMON = (
    "The words claude-infrastructure set in monospace on a dark plate. The title is present the "
    "whole time and never moves; the only motion is the orange Claude Code pixel creature idling "
    "— glancing left, glancing right and occasionally stretching both arms above its head — on a "
    "loop that repeats indefinitely with no restart. "
)


def s1a() -> str:
    """Horizon: the title on a full-width ground line, one creature standing beside it."""
    s = Scene()
    s.plate()
    base, px, size = 372.0, 22, 84
    s.ground(base)
    s.wordmark(size, W / 2, base - 40)
    s.clawd(px, (W + title_width(size)) / 2 + 78, base)
    return s.render(
        "claude-infrastructure",
        D_COMMON
        + "It stands on the same dotted horizon the words sit on, which runs the full "
        "width of the plate. Nothing else is in the frame.",
    )


def s1b() -> str:
    """Close: the most restrained reading — one large creature, the line, the words. Nothing else."""
    s = Scene()
    s.plate()
    base, px, size = 400.0, 32, 76
    s.ground(base, 120, W - 120)
    s.clawd(px, 208, base)
    s.wordmark(size, 208 + 11 * px + 96, base - 34, anchor="start")
    return s.render(
        "claude-infrastructure",
        D_COMMON
        + "The creature is large and stands at the left on a dotted line; the words sit "
        "to its right on the same line. There is nothing else in the frame.",
    )


def s1c() -> str:
    """Scene: the shipped landscape quoted more fully — mounds, vegetation, a creature in it."""
    s = Scene()
    s.plate()
    base, px, size = 396.0, 20, 72
    s.hills(base, [(-80, 620, 7), (1240, 2040, 9)], cell=10)
    s.veg(base, [792, 1108, 1246])
    s.ground(base)
    s.clawd(px, 520, base)
    s.wordmark(size, W / 2, 176)
    return s.render(
        "claude-infrastructure",
        D_COMMON
        + "The words sit above a landscape: dim mounds at both edges, a few clumps of "
        "vegetation, and the creature standing among them on the dotted ground line.",
    )


def s2a() -> str:
    """Four lanes: one horizon, four creatures, nothing between them. The gap IS the claim."""
    s = Scene()
    s.plate()
    base, px, size = 404.0, 16, 78
    s.ground(base)
    for i, x in enumerate((214, 656, 1098, 1540)):
        s.clawd(px, x, base, phase=i * 0.25, idp=f"c{i}")
    s.wordmark(size, W / 2, 214)
    return s.render(
        "claude-infrastructure — four sessions, one machine, no collisions",
        D_COMMON
        + "Four identical creatures stand evenly spaced along one dotted horizon beneath "
        "the words, each idling out of step with the others. Nothing joins them: there are no "
        "lines, threads or exchanges between them — they simply share the ground in separate lanes.",
    )


def s2b() -> str:
    """Depth lanes: three separate hairlines at three distances — parallelism read as depth."""
    s = Scene()
    s.plate()
    # The title rides high and every lane sits below it, with room for the arms-up rise (3 cells)
    # to stay clear. The first attempt shared the title's band, so the far creature clipped the
    # last glyph AND overlapped the near one — banner-collide saw two creatures where three stand.
    size = 64
    s.wordmark(size, W / 2, 112)
    for i, (px, x, base, op) in enumerate(
        ((11, 300, 268.0, 0.5), (17, 860, 344.0, 0.75), (25, 1408, 438.0, 1.0))
    ):
        s.ground(base, 90, W - 90, op=op)
        s.clawd(px, x, base, phase=0.13 + i * 0.31, idp=f"c{i}")
    return s.render(
        "claude-infrastructure — parallel lanes",
        D_COMMON
        + "Three creatures of different sizes stand on three separate dotted lines at "
        "different heights, reading as three distances. Each idles on its own timing. No line "
        "connects one lane to another.",
    )


def s2c() -> str:
    """Row beside the title: the words hold the left, the population holds the right."""
    s = Scene()
    s.plate()
    base, px, size = 384.0, 16, 62
    s.ground(base, 96, W - 96)
    s.wordmark(size, 150, base - 30, anchor="start")
    for i in range(4):
        s.clawd(px, 1020 + i * 200, base, phase=0.07 + i * 0.25, idp=f"c{i}")
    return s.render(
        "claude-infrastructure — a population, not a diagram",
        D_COMMON
        + "The words sit at the left on a dotted line. Four identical creatures stand in "
        "a row to the right on the same line, each idling out of step. Nothing connects them.",
    )


def s3a() -> str:
    """Starfield: the shipped night variant, one creature working under it."""
    s = Scene(night=True)
    s.plate()
    base, px, size = 392.0, 22, 82
    s.stars(34, 46, 268)
    s.ground(base)
    s.wordmark(size, W / 2, base - 44)
    s.clawd(px, (W + title_width(size)) / 2 + 82, base)
    return s.render(
        "claude-infrastructure — the night shift",
        D_COMMON
        + "The plate is a night sky: sparse faint stars, each brightening and dimming on "
        "its own slow timing, none in step with another. The creature stands on the dotted horizon "
        "beside the words, still working.",
    )


def s3b() -> str:
    """Night tree: the canopy and trunk that ship in the same bundle, creature beside it."""
    s = Scene(night=True)
    s.plate()
    base, px, size = 400.0, 21, 66
    s.stars(26, 44, 240)
    s.clawd(px, 372, base)
    s.veg(base, [630])
    s.wordmark(size, 720, base - 36, anchor="start")
    s.tree(base, 1660)
    s.ground(base)
    return s.render(
        "claude-infrastructure — the night shift",
        D_COMMON
        + "Under a sparse field of faint twinkling stars, the creature stands at the left "
        "of a dotted horizon with the words to its right, and a small dim tree stands at the far "
        "right of the same line.",
    )


def s3c() -> str:
    """Long watch: a denser, fainter sky, and one mark on a far slower beat than the rest."""
    s = Scene(night=True)
    s.plate()
    # Stacked, so the clearance has to survive the arms-up rise: at px 24 the earlier layout cleared
    # the title by 14px at rest and collided by 8px the moment the arms went up — a collision only
    # one timestamp in nineteen seconds shows, which is why the check runs at every frame and not
    # just t=0.
    base, px, size = 434.0, 20, 74
    s.stars(52, 40, 240, slow=True)
    s.ground(base)
    s.wordmark(size, W / 2, 172)
    s.clawd(px, W / 2 - 11 * px / 2, base)
    return s.render(
        "claude-infrastructure — the long watch",
        D_COMMON
        + "A dense field of very faint stars twinkles on uncorrelated slow timings, with "
        "one star at the right on a far longer beat than any other. The creature stands centred on "
        "the dotted horizon below the words.",
    )


def kit() -> str:
    """The mechanism proof (assets/banner/motion-kit.svg) — kept regenerable, not a candidate.

    It is the smallest composition that demonstrates R2, R3 and the one-animation-per-element lint
    holding at once, which is what it was built to settle. It is deliberately NOT in the comparison
    set: it is bottom-weighted and right-heavy, being a proof rather than a design.
    """
    s = Scene()
    s.plate()
    base, px, size = 430.0, 22, 84
    s.ground(base)
    s.wordmark(size, W / 2, base - 40)
    s.body.append(
        f'<text class="f" x="{W / 2:g}" y="{base + 50:g}" text-anchor="middle" fill="{DIM}" '
        f'font-size="22" letter-spacing="3.4">SESSIONS RUN EACH OTHER</text>'
    )
    s.clawd(px, (W + title_width(size)) / 2 + 78, base)
    return s.render(
        "claude-infrastructure",
        D_COMMON + "The creature stands on the same dotted horizon the words sit on.",
    )


VARIANTS = {
    "s1a-horizon": s1a,
    "s1b-close": s1b,
    "s1c-scene": s1c,
    "s2a-lanes": s2a,
    "s2b-depth": s2b,
    "s2c-row": s2c,
    "s3a-starfield": s3a,
    "s3b-tree": s3b,
    "s3c-longwatch": s3c,
}
# The mechanism proof, kept buildable so the committed artifact never becomes a file with no
# generator. Excluded from --all, because it is a proof and not a candidate.
EXTRA = {"kit": kit}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("name", nargs="?", choices=list(VARIANTS) + list(EXTRA))
    ap.add_argument(
        "--all", metavar="DIR", help="write every variant into DIR as <key>.svg"
    )
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()

    if a.list:
        for k in VARIANTS:
            print(k)
        return 0
    if a.all:
        d = pathlib.Path(a.all)
        d.mkdir(parents=True, exist_ok=True)
        for k, fn in VARIANTS.items():
            p = d / f"{k}.svg"
            p.write_text(fn() + "\n")
            print(f"{p}  {p.stat().st_size} B")
        return 0
    if not a.name:
        ap.error("give a variant name, --all DIR, or --list")
    print({**VARIANTS, **EXTRA}[a.name]())
    return 0


if __name__ == "__main__":
    sys.exit(main())
