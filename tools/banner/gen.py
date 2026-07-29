#!/usr/bin/env python3
"""Generate the v6 hero banners.

Everything the plan settled is enforced here rather than trusted to hand-typing:

  * P = 240 s master period, and every sub-period is CHECKED to divide it (S1/S2). A period that
    does not divide P is a build error, not a subtle visual bug found later by a frame hash.
  * Phase comes from negative `animation-delay` only — never from a different duration (S2).
  * One animation per element; anything that needs two motions becomes nested groups (S8).
  * The character is grounded by computation — `feet = GROUND - SPRITE_H * scale` (S6).
  * Stars are generated against a hard text keep-out rectangle, so "does not touch the type" is a
    property of the generator rather than of luck (S7).
  * Parallax layers scroll by exactly TILE and their content is duplicated at +TILE, so the wrap
    is seamless by construction.

The art direction lives in the VARIANTS table at the bottom; the machinery above it is shared.

    python3 tools/banner/gen.py --out assets/banner
"""

from __future__ import annotations

import argparse
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

# ── canvas ────────────────────────────────────────────────────────────────────────────────────────
W, H = 1920, 600
TILE = 1920  # parallax wrap distance; content is duplicated at +TILE
GROUND = 506  # the dotted rule: top edge of the ground plane, and clawd's surface (S5)
P = 240  # master period, seconds (S1)

# clawd, quoted from the binary: an 11x8 grid of square pixels (CLAWD_SPRITE_EXTRACTION).
CELL = 20
SPRITE_W, SPRITE_H = 11 * CELL, 8 * CELL  # 220 x 160
CLAWD = "#D77757"  # exact body orange — not #D97757

# The wordmark's exclusion zone. Nothing in the generated scenery may enter it (S7).
KEEPOUT = (372, 82, 1548, 208)  # x0, y0, x1, y1
KEEPOUT_SOFT = 130  # density ramps back up over this distance outside it


# Every rect emitted into a SCROLLING layer is recorded here so `assert_type_clear` can prove the
# wordmark is never overlapped. For a scrolling layer an x-position is no exclusion at all — a cloud
# at x=1000 travels to x=-920 and therefore passes under the type on the way — so the only sound
# invariant is a Y one: scrolling scenery must lie entirely below the keep-out (or entirely above).
_SCROLLING: list[tuple[float, float, str]] = []


def assert_type_clear() -> None:
    """Fail the build if any scrolling scenery can pass through the wordmark's keep-out band."""
    y0, y1 = KEEPOUT[1], KEEPOUT[3]
    bad = [(top, bot, tag) for (top, bot, tag) in _SCROLLING if top < y1 and bot > y0]
    if bad:
        worst = min(bad)
        raise SystemExit(
            f"gen: {len(bad)} scrolling rect(s) cross the wordmark keep-out band "
            f"y={y0}..{y1} — e.g. {worst[2]} spans y={worst[0]:.1f}..{worst[1]:.1f}. "
            f"A scrolling element passes under the type at some phase regardless of its x."
        )


def divides_P(*periods: float) -> None:
    """A sub-period that does not divide P makes the composite loop at the LCM instead (S2)."""
    for p in periods:
        q = P / p
        if abs(q - round(q)) > 1e-9:
            raise SystemExit(
                f"gen: period {p}s does not divide P={P}s (P/p = {q}) — loop would seam"
            )


def fmt(v: float) -> str:
    """Short, stable number formatting — keeps the file small and regeneration byte-identical."""
    if isinstance(v, int) or float(v).is_integer():
        return str(int(v))
    return f"{v:.2f}".rstrip("0").rstrip(".")


def in_keepout(x: float, y: float, pad: float = 0) -> bool:
    x0, y0, x1, y1 = KEEPOUT
    return (x0 - pad) <= x <= (x1 + pad) and (y0 - pad) <= y <= (y1 + pad)


def keepout_distance(x: float, y: float) -> float:
    """Distance from the keep-out rectangle; 0 inside it."""
    x0, y0, x1, y1 = KEEPOUT
    dx = max(x0 - x, 0, x - x1)
    dy = max(y0 - y, 0, y - y1)
    return math.hypot(dx, dy)


# ── palette ───────────────────────────────────────────────────────────────────────────────────────
@dataclass
class Theme:
    """One look. Every field is emitted as a CSS class so the light theme is a media-query override
    of the same geometry — one self-theming file, no <picture> (S3)."""

    sky_top: str
    sky_mid: str
    sky_low: str
    glow: str  # horizon glow colour
    glow_op: float
    ground_top: str
    ground_bot: str
    rule: str
    wm: str  # wordmark
    sub: str  # subtitle
    star: str
    moon: str
    moon_halo: str
    cloud: list[tuple[str, str, str]]  # per layer: (body, top-light, bottom-shade)
    mound: list[str]  # per layer body
    tuft: str
    fg: str
    vignette: float


@dataclass
class Art:
    """An art direction: two themes plus the scene switches that differ between variants."""

    key: str
    title: str
    blurb: str
    dark: Theme
    light: Theme
    subtitle: str = "SESSIONS RUN EACH OTHER"
    clawd_scale: float = 1.0
    clawd_x: float = 700
    cloud_layers: int = 3
    star_count: tuple[int, int, int] = (150, 62, 20)
    moon: tuple[float, float, float] = (1648, 206, 62)  # cx, cy, r
    moon_phase: float = 0.30  # 0 = full, 1 = sliver
    events: tuple[str, ...] = ("shootingstar", "balloon", "birds", "peek")
    second_clawd: bool = False
    # The cheer's period. It has to equal the peer's period when a peer exists, or the two rare
    # beats land at different times and the meeting has nobody answering it.
    cheer_period: float = 120.0
    grain: float = 0.0
    hairline: bool = False


# ── procedural silhouettes ────────────────────────────────────────────────────────────────────────
def lobe_profile(ncols: int, lobes: list[tuple[float, float, float]]) -> list[float]:
    """Height per column as the upper envelope of several circular lobes.

    This is what separates a cumulus from a bar chart: uniform-width blocks read as a city skyline
    (S4), whereas an envelope of overlapping lobes reads as a cloud even when quantised hard.
    """
    out = []
    for i in range(ncols):
        u = (i + 0.5) / ncols
        h = 0.0
        for c, r, amp in lobes:
            d = abs(u - c) / r
            if d < 1.0:
                h = max(h, amp * math.sqrt(1.0 - d * d))
        out.append(h)
    return out


def cumulus(
    x: float,
    base: float,
    width: float,
    height: float,
    cell: int,
    rng: random.Random,
    flat: float = 0.0,
) -> list[tuple[float, float, float, float]]:
    """A stepped cloud/mound as (x, y, w, h) columns, quantised to `cell`.

    `flat` lifts the whole silhouette so wide low mounds keep a solid body instead of tapering to
    nothing at the edges.
    """
    ncols = max(2, int(width // cell))
    nlobes = rng.randint(2, 4)
    lobes = []
    for _ in range(nlobes):
        lobes.append(
            (rng.uniform(0.16, 0.84), rng.uniform(0.28, 0.62), rng.uniform(0.55, 1.0))
        )
    prof = lobe_profile(ncols, lobes)
    peak = max(prof) or 1.0
    cols = []
    for i, p in enumerate(prof):
        h = (p / peak) * (1 - flat) * height + flat * height
        h = max(0.0, round(h / cell) * cell)
        if h <= 0:
            continue
        cols.append((x + i * cell, base - h, cell, h))
    return cols


def pixel_cloud(
    x: float,
    base: float,
    w: float,
    h: float,
    cell: int,
    rng: random.Random,
    bumps: int = 3,
) -> list[tuple[float, float, float, float]]:
    """A pixel cumulus: a flat bottom under a crown of overlapping circular bubbles.

    Three shapes were tried before this one, and each failed in a way worth recording:

      * a coarse lobe envelope collapsed into flat ledges — too few quantisation levels;
      * concentric shrinking tiers gave a centred ziggurat — a temple, not a cloud;
      * a full-width slab with rectangular bumps gave stacked concrete panels, and putting a lit
        row on every rectangle striped them into masonry.

    What works is a per-COLUMN height profile taken as the upper envelope of true circular arcs,
    quantised fine enough (cell small relative to h) to have six or more levels, with a tapered
    minimum height so the bottom stays solid and the ends step down instead of ending in a brick.
    Adjacent equal columns are merged, so the lit edge follows the crown rather than banding it.
    """
    ncols = max(4, int(w // cell))
    bubs = []
    for i in range(max(1, bumps)):
        frac = (i + 0.5) / bumps + rng.uniform(-0.13, 0.13)
        bubs.append((frac, rng.uniform(0.20, 0.38), rng.uniform(0.55, 1.0)))

    prof = []
    for c in range(ncols):
        u = (c + 0.5) / ncols
        best = 0.0
        for fc, rad, amp in bubs:
            d = abs(u - fc) / rad
            if d < 1.0:
                best = max(best, amp * math.sqrt(1.0 - d * d))
        # a solid base that tapers away over the outer tenth, so the ends step down
        taper = min(1.0, min(u, 1.0 - u) / 0.10)
        prof.append(max(best, (2.2 * cell / h) * taper))

    peak = max(prof) or 1.0
    cols = []
    for c, pv in enumerate(prof):
        hh = round((pv / peak) * h / cell) * cell
        if hh <= 0:
            continue
        cols.append((x + c * cell, base - hh, cell, hh))
    return merge_runs(cols)


def swell(
    x: float,
    base: float,
    w: float,
    h: float,
    cell: int,
    rng: random.Random,
    tiers: int = 3,
) -> list[list[float]]:
    """A wide low ground mound as concentric tiers, widest at the bottom.

    Concentric tiers were wrong for clouds — on a tall shape they make a centred ziggurat. On a WIDE
    SHORT shape they are exactly right: each row inset a little from the one below reads as a soft
    swell. Which builder is correct is decided by the aspect ratio, not by taste, so ground scenery
    gets this one and sky gets `pixel_cloud`.

    The failure this replaces: slab+bumps applied to mounds produced narrow tall lumps sitting on a
    flat base — a city skyline, which is the read S4 explicitly rules out.
    """
    tiers = max(1, min(tiers, max(1, int(h // cell))))
    th = max(cell, round((h / tiers) / cell) * cell)
    out = []
    cur_x, cur_w = x, w
    for t in range(tiers):
        out.append([cur_x, base - th * (t + 1), cur_w, th])
        # inset stays a small fraction of the CURRENT width, so the silhouette flattens outward
        left = round(cur_w * rng.uniform(0.14, 0.24) / cell) * cell
        right = round(cur_w * rng.uniform(0.14, 0.24) / cell) * cell
        cur_w = max(cell * 3, cur_w - left - right)
        cur_x += left
    return out


def cloud_body(
    cols: list[tuple[float, float, float, float]], base: float, cell: int, layer: int
) -> str:
    """Body, then a lit edge on each run's own top, then one shaded underside.

    Because the runs are merged the lit edge traces the crown; drawing it per source rectangle is
    what produced horizontal banding and made the clouds read as stone courses.
    """
    if not cols:
        return ""
    s = [rects(cols, f"cb{layer}")]
    _SCROLLING.append((base - cell, base, f"cs{layer}"))
    s.append(
        "".join(
            f'<rect class="ct{layer}" x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" '
            f'height="{fmt(min(cell, h))}"/>'
            for (x, y, w, h) in cols
        )
    )
    x0 = min(c[0] for c in cols)
    x1 = max(c[0] + c[2] for c in cols)
    s.append(
        f'<rect class="cs{layer}" x="{fmt(x0)}" y="{fmt(base - cell)}" '
        f'width="{fmt(x1 - x0)}" height="{fmt(cell)}"/>'
    )
    return "".join(s)


def merge_runs(
    cols: list[tuple[float, float, float, float]],
) -> list[tuple[float, float, float, float]]:
    """Coalesce adjacent equal-height columns into one rect — same picture, far fewer nodes."""
    out: list[list[float]] = []
    for x, y, w, h in cols:
        if (
            out
            and abs(out[-1][1] - y) < 1e-9
            and abs(out[-1][0] + out[-1][2] - x) < 1e-9
        ):
            out[-1][2] += w
        else:
            out.append([x, y, w, h])
    return [(a, b, c, d) for a, b, c, d in out]


# ── emit helpers ──────────────────────────────────────────────────────────────────────────────────
def rects(cols, cls: str) -> str:
    for _x, y, _w, h in cols:
        _SCROLLING.append((y, y + h, cls))
    return "".join(
        f'<rect class="{cls}" x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}"/>'
        for (x, y, w, h) in cols
    )


def tiled(body: str, cls: str, dur: float, delay: float = 0.0) -> str:
    """One scrolling parallax layer. `body` must already contain its own +TILE duplicate."""
    divides_P(dur)
    style = f' style="animation-delay:{fmt(-delay)}s"' if delay else ""
    return f'<g class="{cls}"{style}>{body}</g>'


def duplicate(body_fn) -> str:
    """Render a layer twice, the second copy offset by exactly TILE, so translateX(-TILE) wraps."""
    return body_fn(0) + body_fn(TILE)


# ── sky ───────────────────────────────────────────────────────────────────────────────────────────
def sky_defs(art: Art) -> str:
    d, l = art.dark, art.light
    return (
        # Two gradients, switched by class. A single gradient with themed stop classes is tidier in
        # principle, but stop-color through a media query is the one place SVG-as-image support gets
        # patchy across renderers, so the whole gradient is swapped instead.
        f'<linearGradient id="skyD" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{d.sky_top}"/>'
        f'<stop offset="0.55" stop-color="{d.sky_mid}"/>'
        f'<stop offset="1" stop-color="{d.sky_low}"/></linearGradient>'
        f'<linearGradient id="skyL" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{l.sky_top}"/>'
        f'<stop offset="0.55" stop-color="{l.sky_mid}"/>'
        f'<stop offset="1" stop-color="{l.sky_low}"/></linearGradient>'
        f'<linearGradient id="grdD" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{d.ground_top}"/>'
        f'<stop offset="1" stop-color="{d.ground_bot}"/></linearGradient>'
        f'<linearGradient id="grdL" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{l.ground_top}"/>'
        f'<stop offset="1" stop-color="{l.ground_bot}"/></linearGradient>'
        # Horizon glow: the cheapest depth cue there is. A flat sky reads as paper; a sky that
        # warms toward the horizon reads as air.
        f'<radialGradient id="glowD" cx="{fmt(art.moon[0] / W)}" cy="1" r="0.78">'
        f'<stop offset="0" stop-color="{d.glow}" stop-opacity="{fmt(d.glow_op)}"/>'
        f'<stop offset="1" stop-color="{d.glow}" stop-opacity="0"/></radialGradient>'
        f'<radialGradient id="glowL" cx="{fmt(art.moon[0] / W)}" cy="1" r="0.78">'
        f'<stop offset="0" stop-color="{l.glow}" stop-opacity="{fmt(l.glow_op)}"/>'
        f'<stop offset="1" stop-color="{l.glow}" stop-opacity="0"/></radialGradient>'
        # Vignette, drawn BEFORE the type so it can never darken the wordmark.
        f'<radialGradient id="vig" cx="0.5" cy="0.46" r="0.78">'
        f'<stop offset="0.42" stop-color="#000" stop-opacity="0"/>'
        f'<stop offset="1" stop-color="#000" stop-opacity="1"/></radialGradient>'
        f'<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">'
        f'<stop offset="0.3" stop-color="#fff" stop-opacity="0.5"/>'
        f'<stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>'
    )


def stratified(
    count: int,
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    rng: random.Random,
    ylim: float,
) -> list[tuple[float, float]]:
    """One jittered sample per grid cell, thinned toward the horizon.

    Pure rejection sampling over a density function gives visible clumps and bald patches — v6d had
    a dense knot on the left and an empty right. A jittered grid keeps coverage even while staying
    irregular enough not to read as a lattice, which is what a real sky looks like.
    """
    if count <= 0:
        return []
    # Over-provision the grid. With exactly `count` cells each cell gets a single chance, so every
    # horizon-falloff or keep-out rejection is permanent and the field comes out a third of the
    # requested density (measured: 45 of 165). Shuffling the cells first means taking the first
    # `count` acceptances from a larger grid still gives even coverage.
    cells_wanted = count * 4
    aspect = (x1 - x0) / max(1.0, (y1 - y0))
    ncols = max(1, int(round(math.sqrt(cells_wanted * aspect))))
    nrows = max(1, int(math.ceil(cells_wanted / ncols)))
    cw = (x1 - x0) / ncols
    chh = (y1 - y0) / nrows
    cells = [(c, r) for r in range(nrows) for c in range(ncols)]
    rng.shuffle(cells)
    out = []
    for c, r in cells:
        x = x0 + (c + rng.uniform(0.12, 0.88)) * cw
        y = y0 + (r + rng.uniform(0.12, 0.88)) * chh
        # density falls off toward the horizon: physically true, and it keeps the busiest detail
        # away from the cloud band
        if rng.random() > (1.0 - y / (ylim * 1.22)) ** 1.15:
            continue
        out.append((x, y))
    return out


def starfield(art: Art, rng: random.Random) -> str:
    """Three depth tiers (size + opacity + twinkle rate), a density falloff toward the horizon, and
    a hard keep-out around the type with a soft ramp outside it (S7).

    Drawn as rects, not `*` glyphs: at the displayed scale the mono asterisk renders as a snowflake,
    and a glyph also makes the sky depend on the reader's installed fonts.
    """
    nA, nB, nC = art.star_count
    tiers = [
        # (count, size, opacity, twinkle period, y-limit, class)
        (nA, 2, 0.34, 60.0, 336, "kA"),
        (nB, 3, 0.62, 30.0, 300, "kB"),
        (nC, 4, 0.95, 10.0, 264, "kC"),
    ]
    divides_P(60.0, 30.0, 10.0)
    out = []
    for count, size, op, dur, ylim, kls in tiers:
        placed = 0
        for x, y in stratified(count, 6, W - 6, 8, ylim, rng, ylim):
            if placed >= count:
                break
            if in_keepout(x, y):
                continue
            d = keepout_distance(x, y)
            if d < KEEPOUT_SOFT and rng.random() > (d / KEEPOUT_SOFT) ** 0.9:
                continue
            delay = -(placed % 24) * (dur / 24.0)
            body = f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{size}" height="{size}"/>'
            if kls == "kC":
                # the brightest tier gets a small 4-point sparkle: still pure geometry, so it stays
                # crisp at any zoom and owes nothing to the reader's installed fonts
                arm = size * 1.55
                t = max(1.0, size / 4.2)
                body += (
                    f'<rect x="{fmt(x + size / 2 - t / 2)}" y="{fmt(y - arm)}" '
                    f'width="{fmt(t)}" height="{fmt(arm * 2 + size)}"/>'
                    f'<rect x="{fmt(x - arm)}" y="{fmt(y + size / 2 - t / 2)}" '
                    f'width="{fmt(arm * 2 + size)}" height="{fmt(t)}"/>'
                )
            out.append(
                f'<g class="st {kls}" style="animation-delay:{fmt(delay)}s" '
                f'opacity="{fmt(op)}">{body}</g>'
            )
            placed += 1
    return "".join(out)


def moon(art: Art) -> str:
    """A clean crescent via a mask — no dither, no solid-white cell.

    The checkerboard moon in v5a is the failure this replaces: at the displayed scale an 8 px
    pattern collapses into grey mud and the bitten shape reads as a corrupted sprite rather than
    a moon.
    """
    cx, cy, r = art.moon
    if in_keepout(cx, cy, pad=r):
        raise SystemExit("gen: moon overlaps the wordmark keep-out")
    # bite radius > disc radius keeps the horns closing cleanly; a purely horizontal
    # offset with a slight lift gives the classic tilt without a spur on one horn
    off = r * (0.55 + art.moon_phase * 0.75)
    return (
        f'<mask id="mcut" maskUnits="userSpaceOnUse" x="{fmt(cx - r * 1.4)}" y="{fmt(cy - r * 1.4)}" '
        f'width="{fmt(r * 2.8)}" height="{fmt(r * 2.8)}">'
        f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}" fill="#fff"/>'
        f'<circle cx="{fmt(cx + off)}" cy="{fmt(cy - r * 0.14)}" r="{fmt(r * 1.16)}" fill="#000"/>'
        f"</mask>"
    )


def moon_body(art: Art) -> str:
    cx, cy, r = art.moon
    divides_P(80.0)
    return (
        f'<g class="moonHalo"><circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r * 2.9)}" '
        f'fill="url(#halo)" class="mhalo"/></g>'
        f'<g class="moonLit"><circle class="mdisc" cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}" '
        f'mask="url(#mcut)"/></g>'
    )


def clouds(art: Art, rng: random.Random) -> str:
    """Pixel cumulus in three parallax bands, each with a lit top edge and a shaded underside.

    Proportion is the whole game. The reference clouds in the welcome screen are three rows tall and
    twenty columns wide — roughly 7:1. Built at 2:1 the same generator produces something that reads
    as a rock skyline instead, which is the failure S4 names. So height is CAPPED as a fraction of
    width here rather than being an independent parameter, and the band is kept clear of both the
    type keep-out above and the horizon below.

    Three values (body / lit top / shaded underside) is what gives a stepped silhouette form; a
    single flat fill is why v5a's clouds read as haze.
    """
    speeds = [P, P / 2, P / 3]  # 240 / 120 / 80
    # bottom edge, height, cell, count per tile, tiers. Bottoms stay clear of the type keep-out
    # above (tops must exceed KEEPOUT[3]) and of the horizon below.
    bands = [
        (292, 56, 8, 3, 4),
        (328, 66, 8, 3, 3),
        (362, 76, 10, 2, 3),
    ]
    out = []
    for layer in range(min(art.cloud_layers, 3)):
        base_y, hgt, cs, n, tiers = bands[layer]
        dur = speeds[layer]
        divides_P(dur)

        def body(
            shift: float, layer=layer, base_y=base_y, hgt=hgt, cs=cs, n=n, tiers=tiers
        ) -> str:
            r2 = random.Random(1400 + layer * 7)
            s = []
            gap = TILE / n
            for i in range(n):
                cw = gap * r2.uniform(0.44, 0.62)
                ch = min(hgt * r2.uniform(0.82, 1.0), cw / 5.0)  # stays wider than tall
                cx = shift + i * gap + r2.uniform(0, max(1.0, gap - cw))
                by = base_y + r2.uniform(-12, 12)
                cols = pixel_cloud(cx, by, cw, ch, cs, r2, bumps=tiers)
                s.append(cloud_body(cols, by, cs, layer))
            return "".join(s)

        out.append(tiled(duplicate(body), f"cl{layer}", dur))
    return "".join(out)


def mounds(art: Art, rng: random.Random) -> str:
    """Ground scenery: wide low mounds straddling the horizon, plus the reference's vegetation.

    These must not look like the cloud layer wearing a different colour, so they are flatter (a
    harder aspect cap), quantised coarser, and they carry upright vegetation clumps — which is what
    reads as *ground* rather than as more sky.
    """
    layers = [(P / 2, 74, 3, "md0", 0.0), (P / 4, 46, 3, "md1", 1.0)]  # 120 / 60
    out = []
    for dur, hgt, n, cls, veg in layers:
        divides_P(dur)

        def body(shift: float, hgt=hgt, n=n, cls=cls, veg=veg) -> str:
            r2 = random.Random(hash(cls) % 9999)
            s = []
            gap = TILE / n
            for i in range(n):
                mw = gap * r2.uniform(0.52, 0.78)
                mh = min(
                    hgt * r2.uniform(0.72, 1.0), mw * 0.17
                )  # far flatter than a cloud
                mx = shift + i * gap + r2.uniform(0, max(1.0, gap - mw))
                cols = swell(mx, GROUND, mw, mh, 14, r2, tiers=4)
                s.append(rects([tuple(c) for c in cols], cls))
                if veg and r2.random() < 0.8:
                    # a vegetation clump: a stepped crown over a short stem, from the reference scene
                    vx = mx + mw * r2.uniform(0.2, 0.7)
                    vh = r2.uniform(26, 46)
                    vw = r2.uniform(18, 34)
                    s.append(
                        f'<rect class="{cls}" x="{fmt(vx)}" y="{fmt(GROUND - vh)}" '
                        f'width="{fmt(vw)}" height="{fmt(vh)}"/>'
                        f'<rect class="{cls}" x="{fmt(vx - 5)}" y="{fmt(GROUND - vh * 0.72)}" '
                        f'width="{fmt(vw + 10)}" height="{fmt(vh * 0.34)}"/>'
                    )
            return "".join(s)

        out.append(tiled(duplicate(body), cls + "s", dur))
    return "".join(out)


def ground_detail(art: Art) -> str:
    """The fastest layers, inside the ground band. A visible speed hierarchy is the whole trick of a
    dino-run ground — near things must outrun far things by enough to read.

    Scattered rectangles at random heights read as confetti (the first attempt did). What reads as
    ground is: horizontal dashes lying ON the surface, occasional upright tufts, and a near
    foreground silhouette band with a broken top edge that frames the bottom of the frame.
    """
    out = []
    # dashes + tufts, two speeds
    for dur, n, cls, y0, y1 in [
        (P / 8, 20, "tf0", GROUND + 8, GROUND + 26),  # 30s
        (P / 10, 16, "tf1", GROUND + 30, GROUND + 54),  # 24s
    ]:
        divides_P(dur)

        def body(shift: float, n=n, cls=cls, y0=y0, y1=y1) -> str:
            r2 = random.Random(hash(cls) % 9999)
            s = []
            gap = TILE / n
            for i in range(n):
                x = shift + i * gap + r2.uniform(0, gap * 0.55)
                y = r2.uniform(y0, y1)
                if r2.random() < 0.22:
                    # a tuft: an uneven three-blade clump, never an evenly spaced comb
                    for k in range(3):
                        bh = r2.uniform(5, 12)
                        s.append(
                            f'<rect class="{cls}" x="{fmt(x + k * r2.uniform(3.5, 6))}" '
                            f'y="{fmt(y - bh)}" width="2.5" height="{fmt(bh)}"/>'
                        )
                else:
                    # a long low streak — ground grain, the dino-run read
                    s.append(
                        f'<rect class="{cls}" x="{fmt(x)}" y="{fmt(y)}" '
                        f'width="{fmt(r2.uniform(38, 104))}" height="2.5" '
                        f'opacity="{fmt(r2.uniform(0.35, 0.75))}"/>'
                    )
            return "".join(s)

        out.append(tiled(duplicate(body), cls + "s", dur))

    # the near foreground: one dark band with a stepped top edge, fastest of all
    divides_P(P / 12)

    def fg(shift: float) -> str:
        r2 = random.Random(77)
        s = []
        step = 96
        base = GROUND + 56
        cols = []
        for i in range(TILE // step):
            x = shift + i * step
            top = base + r2.uniform(-9, 9)
            cols.append((x, top, step, H - top))
        s.append(rects(merge_runs(cols), "fgb"))
        return "".join(s)

    out.append(tiled(duplicate(fg), "fgbs", P / 12))
    return "".join(out)


# ── clawd ─────────────────────────────────────────────────────────────────────────────────────────
def clawd_sprite(idsuffix: str = "") -> str:
    """The creature as nested single-animation groups (S8).

    Geometry is the 11x8 grid from the binary: rows 0-5 are the body at columns 1-9, rows 2-3 widen
    to columns 0-10 (the arm stubs), the eyes are holes at column 2 and 8 of row 2, and the legs are
    columns 1/3/7/9 of rows 6-7.

    The pose vocabulary is quoted rather than invented: default / look-left / look-right / arms-up,
    where only the eye band moves between the three looking poses and arms-up is the one whole-body
    pose.
    """
    c = CELL
    sfx = idsuffix
    divides_P(0.5, 2.0, 4.0, 8.0, 12.0, 80.0, 120.0, 240.0)

    eye_l, eye_r = 2 * c, 8 * c  # eye columns
    eye_y = 2 * c

    body = f'<rect x="{c}" y="0" width="{9 * c}" height="{6 * c}" fill="{CLAWD}"/>'
    arms_idle = (
        f'<rect x="0" y="{eye_y}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        f'<rect x="{10 * c}" y="{eye_y}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
    )
    # arms-up: the stubs rise three cells, and a small spark marks the cheer
    arms_up = (
        f'<rect x="0" y="{eye_y - 3 * c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        f'<rect x="{10 * c}" y="{eye_y - 3 * c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        f'<rect x="{fmt(5.2 * c)}" y="{fmt(-2.1 * c)}" width="{fmt(0.6 * c)}" '
        f'height="{fmt(0.6 * c)}" fill="{CLAWD}"/>'
        f'<rect x="{fmt(4.2 * c)}" y="{fmt(-1.5 * c)}" width="{fmt(0.45 * c)}" '
        f'height="{fmt(0.45 * c)}" fill="{CLAWD}" opacity=".7"/>'
        f'<rect x="{fmt(6.4 * c)}" y="{fmt(-1.6 * c)}" width="{fmt(0.45 * c)}" '
        f'height="{fmt(0.45 * c)}" fill="{CLAWD}" opacity=".7"/>'
    )

    eyes_open = (
        f'<rect class="eyeHole" x="{eye_l}" y="{eye_y}" width="{c}" height="{c}"/>'
        f'<rect class="eyeHole" x="{eye_r}" y="{eye_y}" width="{c}" height="{c}"/>'
    )
    # a pixel blink is a hard swap to a thin lid, never a scaleY tween — interpolating a 20 px
    # square through 0.12 produces a soft grey band that is not in the palette
    eyes_shut = (
        f'<rect class="eyeHole" x="{eye_l}" y="{fmt(eye_y + c * 0.62)}" width="{c}" '
        f'height="{fmt(c * 0.24)}"/>'
        f'<rect class="eyeHole" x="{eye_r}" y="{fmt(eye_y + c * 0.62)}" width="{c}" '
        f'height="{fmt(c * 0.24)}"/>'
    )

    legs = lambda cls, cols: (
        f'<g class="{cls}">'
        + "".join(
            f'<rect x="{k * c}" y="{6 * c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
            for k in cols
        )
        + "</g>"
    )

    # sleep: lids drawn over the eye holes in body orange, plus a drifting Z pair
    sleep = (
        f'<g class="rSleep{sfx}">'
        f'<rect x="{eye_l}" y="{eye_y}" width="{c}" height="{c}" fill="{CLAWD}"/>'
        f'<rect x="{eye_r}" y="{eye_y}" width="{c}" height="{c}" fill="{CLAWD}"/>'
        f'<rect x="{fmt(eye_l + 1)}" y="{fmt(eye_y + c * 0.6)}" width="{fmt(c - 2)}" '
        f'height="{fmt(c * 0.22)}" fill="#2b1b14"/>'
        f'<rect x="{fmt(eye_r + 1)}" y="{fmt(eye_y + c * 0.6)}" width="{fmt(c - 2)}" '
        f'height="{fmt(c * 0.22)}" fill="#2b1b14"/>'
        f'<g class="zz1"><rect class="zmk" x="{fmt(11.4 * c)}" y="{fmt(-0.4 * c)}" '
        f'width="{fmt(0.5 * c)}" height="{fmt(0.5 * c)}"/></g>'
        f'<g class="zz2"><rect class="zmk" x="{fmt(12.3 * c)}" y="{fmt(-1.5 * c)}" '
        f'width="{fmt(0.36 * c)}" height="{fmt(0.36 * c)}" opacity=".7"/></g>'
        f"</g>"
    )

    return (
        # turn-around: a rare scaleX flip so he walks against the scroll for a few seconds
        f'<g class="rTurn{sfx}">'
        f'<g class="hop{sfx}">'
        f'<g class="bob{sfx}">'
        f'<g class="armsIdle{sfx}">{arms_idle}</g>'
        f'<g class="rCheer{sfx}">{arms_up}</g>'
        f"{body}"
        f'<g class="look{sfx}">'
        f'<g class="eOpen{sfx}">{eyes_open}</g>'
        f'<g class="eShut{sfx}">{eyes_shut}</g>'
        f"</g>"
        f"{sleep}"
        # legs swap wholesale between walking and standing, so the stride can stop during a doze
        # without any element carrying two animations
        f'<g class="legsWalk{sfx}">{legs("legA" + sfx, (1, 7))}{legs("legB" + sfx, (3, 9))}</g>'
        f'<g class="legsStill{sfx}">{legs("legS" + sfx, (1, 3, 7, 9))}</g>'
        f"</g></g></g>"
    )


def clawd_placed(art: Art, x: float, scale: float, sfx: str = "") -> str:
    """Grounded by computation, never by eye (S6): the sprite's local y runs 0..SPRITE_H to the
    sole, so the group's translate y is exactly GROUND - SPRITE_H*scale."""
    ty = GROUND - SPRITE_H * scale
    sw = SPRITE_W * scale
    shadow = (
        f'<g class="shdw{sfx}">'
        f'<ellipse class="sh" cx="{fmt(x + sw / 2)}" cy="{fmt(GROUND + 3)}" '
        f'rx="{fmt(sw * 0.44)}" ry="{fmt(7 * scale)}"/></g>'
    )
    return (
        shadow + f'<g transform="translate({fmt(x)} {fmt(ty)}) scale({fmt(scale)})" '
        f'shape-rendering="crispEdges">{clawd_sprite(sfx)}</g>'
    )


# ── rare world events ─────────────────────────────────────────────────────────────────────────────
def events(art: Art) -> str:
    out = []
    if "shootingstar" in art.events:
        divides_P(P)
        trail = "".join(
            f'<rect class="ss" x="{fmt(-i * 15)}" y="{fmt(i * 6.4)}" width="{fmt(9 - i * 0.75)}" '
            f'height="{fmt(9 - i * 0.75)}" opacity="{fmt(max(0.06, 0.95 - i * 0.11))}"/>'
            for i in range(9)
        )
        out.append(
            f'<g class="nOnly"><g class="shoot"><g transform="translate(1500 60)">'
            f"{trail}</g></g></g>"
        )
    if "birds" in art.events:
        divides_P(P / 3)
        # three chevrons in loose formation — two rects each, no glyphs
        flock = "".join(
            f'<g transform="translate({fmt(i * 46)} {fmt((i % 2) * 17)})">'
            f'<rect class="brd" x="0" y="0" width="11" height="3"/>'
            f'<rect class="brd" x="11" y="-4" width="11" height="3"/></g>'
            for i in range(3)
        )
        out.append(f'<g class="birds"><g transform="translate(0 268)">{flock}</g></g>')
    if "balloon" in art.events:
        divides_P(P / 2)
        out.append(
            '<g class="balloon"><g transform="translate(0 330)">'
            f'<rect class="bal" x="0" y="0" width="17" height="21"/>'
            f'<rect class="bal" x="3" y="21" width="11" height="5"/>'
            f'<rect class="balStr" x="8" y="26" width="2" height="34"/>'
            f'<rect class="bal" x="4" y="60" width="10" height="7"/></g></g>'
        )
    return "".join(out)


def peek(art: Art) -> str:
    """A visitor rising from behind the ground line, then dropping back. Clipped to the ground so
    it genuinely reads as 'behind' rather than as a sprite sliding over the scene."""
    if "peek" not in art.events:
        return ""
    divides_P(P)
    s = 0.30
    return (
        f'<g clip-path="url(#belowGround)"><g class="peek">'
        f'<g transform="translate(1418 {fmt(GROUND - SPRITE_H * s + 8)}) scale({fmt(s)})" '
        f'shape-rendering="crispEdges">'
        f'<rect x="{CELL}" y="0" width="{9 * CELL}" height="{6 * CELL}" fill="{CLAWD}"/>'
        f'<rect class="eyeHole" x="{2 * CELL}" y="{2 * CELL}" width="{CELL}" height="{CELL}"/>'
        f'<rect class="eyeHole" x="{8 * CELL}" y="{2 * CELL}" width="{CELL}" height="{CELL}"/>'
        f"</g></g></g>"
    )


# ── stylesheet ────────────────────────────────────────────────────────────────────────────────────
def css(art: Art) -> str:
    # every per-variant period goes through the same divisibility gate as the built-in ones
    divides_P(art.cheer_period)
    d, l = art.dark, art.light

    def cloudrules(t: Theme, pfx: str = "") -> str:
        s = ""
        for i, (b, tp, sh) in enumerate(t.cloud):
            s += f"{pfx}.cb{i}{{fill:{b}}}{pfx}.ct{i}{{fill:{tp}}}{pfx}.cs{i}{{fill:{sh}}}"
        for i, m in enumerate(t.mound):
            s += f"{pfx}.md{i}{{fill:{m}}}"
        return s

    base = (
        # ---- themed fills (dark is the base; light is a media-query override) ----
        f".sky{{fill:url(#skyD)}}.grd{{fill:url(#grdD)}}.glw{{fill:url(#glowD)}}"
        f".st{{fill:{d.star}}}.mdisc{{fill:{d.moon}}}"
        f".rl{{stroke:{d.rule}}}.wm{{fill:{d.wm}}}.sub{{fill:{d.sub}}}"
        f".tf0,.tf1{{fill:{d.tuft}}}.fgb{{fill:{d.fg}}}"
        f".ss{{fill:#f2f6ff}}.brd{{fill:{d.mound[0]}}}.bal{{fill:{CLAWD}}}.balStr{{stroke:none;fill:{CLAWD};opacity:.45}}"
        f".eyeHole{{fill:#1b1109}}.sh{{fill:#000;opacity:.46}}.zmk{{fill:{d.star}}}"
        f".vig{{fill:url(#vig);opacity:{fmt(d.vignette)}}}" + cloudrules(d) +
        # ---- parallax: one shared translate, per-layer duration, all dividing P ----
        f"@keyframes sc{{from{{transform:translateX(0)}}to{{transform:translateX(-{TILE}px)}}}}"
        f".cl0{{animation:sc {fmt(P)}s linear infinite}}"
        f".cl1{{animation:sc {fmt(P / 2)}s linear infinite}}"
        f".cl2{{animation:sc {fmt(P / 3)}s linear infinite}}"
        f".md0s{{animation:sc {fmt(P / 2)}s linear infinite}}"
        f".md1s{{animation:sc {fmt(P / 4)}s linear infinite}}"
        f".tf0s{{animation:sc {fmt(P / 8)}s linear infinite}}"
        f".tf1s{{animation:sc {fmt(P / 10)}s linear infinite}}"
        f".fgbs{{animation:sc {fmt(P / 12)}s linear infinite}}"
        # ---- twinkle: three rates so the sky has depth rather than one uniform pulse ----
        f"@keyframes kAf{{0%{{opacity:.34}}50%{{opacity:.92}}100%{{opacity:.34}}}}"
        f"@keyframes kBf{{0%{{opacity:.30}}44%{{opacity:1}}100%{{opacity:.30}}}}"
        f"@keyframes kCf{{0%{{opacity:.55}}30%{{opacity:1}}62%{{opacity:.42}}100%{{opacity:.55}}}}"
        f".kA{{animation:kAf 60s ease-in-out infinite}}"
        f".kB{{animation:kBf 30s ease-in-out infinite}}"
        f".kC{{animation:kCf 10s ease-in-out infinite}}"
        # ---- moon: a slow brightness breath, nothing more ----
        f"@keyframes mnf{{0%{{opacity:.80}}50%{{opacity:1}}100%{{opacity:.80}}}}"
        f".moonLit{{animation:mnf 80s ease-in-out infinite}}"
        f"@keyframes mhf{{0%{{opacity:.18}}50%{{opacity:.34}}100%{{opacity:.18}}}}"
        f".moonHalo{{animation:mhf 80s ease-in-out infinite}}"
        # ---- clawd: constant life ----
        # stride, on steps() so the legs snap between cells instead of sliding
        f"@keyframes wA{{0%,49%{{transform:translateY(0)}}50%,100%{{transform:translateY(-{fmt(CELL * 0.6)}px)}}}}"
        f"@keyframes wB{{0%,49%{{transform:translateY(-{fmt(CELL * 0.6)}px)}}50%,100%{{transform:translateY(0)}}}}"
        f".legA{{animation:wA .5s steps(1,end) infinite}}"
        f".legB{{animation:wB .5s steps(1,end) infinite}}"
        # the body rides the stride — 2 px of weight is what stops him looking like a decal
        f"@keyframes bobf{{0%,49%{{transform:translateY(0)}}50%,100%{{transform:translateY(-2px)}}}}"
        f".bob{{animation:bobf .5s steps(1,end) infinite}}"
        # blink: a hard swap between the two eye groups
        f"@keyframes eof{{0%,90%{{opacity:1}}90.5%,95%{{opacity:0}}95.5%,100%{{opacity:1}}}}"
        f"@keyframes esf{{0%,90%{{opacity:0}}90.5%,95%{{opacity:1}}95.5%,100%{{opacity:0}}}}"
        f".eOpen{{animation:eof 4s steps(1,end) infinite}}"
        f".eShut{{animation:esf 4s steps(1,end) infinite}}"
        # look around — the eye band only, exactly one grid cell each way (the quoted pose table)
        f"@keyframes lkf{{0%,26%{{transform:translateX(0)}}34%,50%{{transform:translateX(-{CELL}px)}}"
        f"58%,74%{{transform:translateX({CELL}px)}}82%,100%{{transform:translateX(0)}}}}"
        f".look{{animation:lkf 8s steps(1,end) infinite}}"
        # ear/arm wiggle
        f"@keyframes arf{{0%,64%{{transform:translateY(0)}}72%{{transform:translateY(-{fmt(CELL * 0.55)}px)}}"
        f"82%,100%{{transform:translateY(0)}}}}"
        f".armsIdle{{animation:arf 2s ease-in-out infinite}}"
        # hop every 12 s, not every 4 — an occasional hop is life, a constant one is a bob
        f"@keyframes hpf{{0%,72%{{transform:translateY(0)}}78%{{transform:translateY(-30px)}}"
        f"84%{{transform:translateY(0)}}88%{{transform:translateY(-9px)}}92%,100%{{transform:translateY(0)}}}}"
        f".hop{{animation:hpf 12s cubic-bezier(.3,.05,.4,1) infinite}}"
        # the shadow squashes on the same 12 s clock — the cue that sells the hop as a jump
        f"@keyframes shf{{0%,72%{{transform:scale(1,1);opacity:.46}}78%{{transform:scale(.66,.5);opacity:.14}}"
        f"84%{{transform:scale(1,1);opacity:.46}}88%{{transform:scale(.88,.8);opacity:.24}}"
        f"92%,100%{{transform:scale(1,1);opacity:.46}}}}"
        f".shdw{{animation:shf 12s cubic-bezier(.3,.05,.4,1) infinite;transform-origin:"
        f"{fmt(art.clawd_x + SPRITE_W * art.clawd_scale / 2)}px {fmt(GROUND + 3)}px}}"
        # ---- rare emotes; every window is a small % of a 240 s loop ----
        f"@keyframes rsf{{0%,63%{{opacity:0}}63.2%,66%{{opacity:1}}66.2%,100%{{opacity:0}}}}"
        f".rSleep{{animation:rsf 240s steps(1,end) infinite}}"
        f"@keyframes lwf{{0%,63%{{opacity:1}}63.2%,66%{{opacity:0}}66.2%,100%{{opacity:1}}}}"
        f".legsWalk{{animation:lwf 240s steps(1,end) infinite}}"
        f"@keyframes lsf{{0%,63%{{opacity:0}}63.2%,66%{{opacity:1}}66.2%,100%{{opacity:0}}}}"
        f".legsStill{{animation:lsf 240s steps(1,end) infinite}}"
        f"@keyframes zzf{{0%,63%{{opacity:0;transform:translate(0,0)}}64%{{opacity:.9}}"
        f"66%{{opacity:0;transform:translate(14px,-30px)}}66.2%,100%{{opacity:0}}}}"
        f".zz1{{animation:zzf 240s ease-out infinite}}"
        f".zz2{{animation:zzf 240s ease-out infinite;animation-delay:-1.2s}}"
        f"@keyframes rcf{{0%,28%{{opacity:0}}28.4%,32%{{opacity:1}}32.4%,100%{{opacity:0}}}}"
        f".rCheer{{animation:rcf {fmt(art.cheer_period)}s steps(1,end) infinite}}"
        f"@keyframes rtf{{0%,86%{{transform:scaleX(1)}}88%,95%{{transform:scaleX(-1)}}97%,100%{{transform:scaleX(1)}}}}"
        f".rTurn{{animation:rtf 80s steps(1,end) infinite;transform-origin:"
        f"{fmt(SPRITE_W / 2)}px {fmt(SPRITE_H / 2)}px}}"
        # ---- rare world events ----
        # the shooting star crosses at 96.5-99% of the loop; clawd's cheer sits at 28-32% so the
        # two rare beats do not collide and the loop always has something coming
        f"@keyframes ssf{{0%,96.3%{{opacity:0;transform:translate(0,0)}}"
        f"96.5%{{opacity:1}}98.9%{{opacity:.85;transform:translate(-700px,300px)}}"
        f"99.1%,100%{{opacity:0;transform:translate(-760px,326px)}}}}"
        f".shoot{{animation:ssf 240s linear infinite}}"
        f"@keyframes brdf{{0%{{opacity:0;transform:translate({W + 180}px,0)}}"
        f"4%{{opacity:.75}}44%{{opacity:.75}}50%,100%{{opacity:0;transform:translate(-260px,-54px)}}}}"
        f".birds{{animation:brdf 80s linear infinite}}"
        f"@keyframes balf{{0%{{opacity:0;transform:translate({W + 120}px,0)}}"
        f"5%{{opacity:.8}}45%{{opacity:.8}}50%,100%{{opacity:0;transform:translate(-180px,-70px)}}}}"
        f".balloon{{animation:balf 120s linear infinite}}"
        f"@keyframes pkf{{0%,40%{{transform:translateY(78px)}}42.5%,48%{{transform:translateY(0)}}"
        f"50.5%,100%{{transform:translateY(78px)}}}}"
        f".peek{{animation:pkf 240s ease-in-out infinite}}"
        # ---- the peer session (v6b) ----
        # It walks in from the right, holds beside the resident for the meeting, then continues
        # left and off. `translate` on the wrapper, stride on the legs, flip on an inner group:
        # three motions, three nested elements, one animation each.
        f"@keyframes prf{{0%,20%{{opacity:0;transform:translateX({W + 240}px)}}"
        f"21%{{opacity:1}}"
        f"27.5%{{transform:translateX({fmt(art.clawd_x + SPRITE_W * art.clawd_scale + 34)}px)}}"
        f"33%{{transform:translateX({fmt(art.clawd_x + SPRITE_W * art.clawd_scale + 34)}px)}}"
        f"41%{{opacity:1;transform:translateX(-320px)}}"
        f"42%,100%{{opacity:0;transform:translateX(-320px)}}}}"
        f".peer{{animation:prf 240s linear infinite}}"
        # it faces the resident while they meet, then turns back to its heading
        f"@keyframes pflf{{0%,27.4%{{transform:scaleX(1)}}27.5%,33%{{transform:scaleX(-1)}}"
        f"33.1%,100%{{transform:scaleX(1)}}}}"
        f".peerFlip{{animation:pflf 240s steps(1,end) infinite;transform-origin:"
        f"{fmt(SPRITE_W / 2)}px {fmt(SPRITE_H / 2)}px}}"
        f"@keyframes pwA{{0%,49%{{transform:translateY(0)}}"
        f"50%,100%{{transform:translateY(-{fmt(CELL * 0.6)}px)}}}}"
        f"@keyframes pwB{{0%,49%{{transform:translateY(-{fmt(CELL * 0.6)}px)}}"
        f"50%,100%{{transform:translateY(0)}}}}"
        f"@keyframes pcf{{0%,28.6%{{opacity:0}}29%,32%{{opacity:1}}32.4%,100%{{opacity:0}}}}"
        f".pCheer{{animation:pcf 240s steps(1,end) infinite}}"
        f".pLegA{{animation:pwA .5s steps(1,end) infinite}}"
        f".pLegB{{animation:pwB .5s steps(1,end) infinite;animation-delay:-.12s}}"
    )

    # A still that is legible on its own, not a frame that happens to be paused. The rare emotes
    # resolve to their hidden state and the visitor stays down.
    reduced = (
        "@media (prefers-reduced-motion:reduce){"
        "*{animation:none!important}"
        ".shoot,.balloon,.birds,.rSleep,.rCheer,.legsStill,.zz1,.zz2,.eShut,.peer,.pCheer{opacity:0}"
        ".legsWalk,.eOpen{opacity:1}"
        # `animation:none` reverts an element to its UN-animated base value, which for the
        # moon halo is full strength — the frozen still showed a blown-out glow that never
        # appears in the animation. Pin the breathing values to their mid-points instead.
        ".moonHalo{opacity:.26}.moonLit{opacity:.9}"
        ".peek{transform:translateY(78px)}"
        "}"
    )

    light = (
        "@media (prefers-color-scheme:light){"
        ".sky{fill:url(#skyL)}.grd{fill:url(#grdL)}.glw{fill:url(#glowL)}"
        f".nOnly{{display:none}}.dOnly{{display:block}}"
        f".mdisc{{fill:{l.moon}}}"
        f".rl{{stroke:{l.rule}}}.wm{{fill:{l.wm}}}.sub{{fill:{l.sub}}}"
        f".tf0,.tf1{{fill:{l.tuft}}}.fgb{{fill:{l.fg}}}"
        f".brd{{fill:{l.mound[0]}}}.sh{{opacity:.20}}"
        f".vig{{opacity:{fmt(l.vignette)}}}" + cloudrules(l) + "}"
    )
    # Day/night switching is done with `display` on a parent group, so no element ever needs both a
    # theme rule and an animation on the same property (which is what S8 forbids).
    daynight = ".dOnly{display:none}.nOnly{display:block}"

    return base + daynight + reduced + light


# ── assembly ──────────────────────────────────────────────────────────────────────────────────────
def build(art: Art) -> str:
    _SCROLLING.clear()
    rng = random.Random(20260729 + sum(ord(ch) for ch in art.key))
    scale = art.clawd_scale

    sun_cx, sun_cy, sun_r = art.moon
    day_sun = (
        f'<g class="dOnly">'
        f'<circle cx="{fmt(sun_cx)}" cy="{fmt(sun_cy)}" r="{fmt(sun_r * 3.1)}" '
        f'fill="url(#halo)" opacity=".5"/>'
        f'<circle class="mdisc" cx="{fmt(sun_cx)}" cy="{fmt(sun_cy)}" r="{fmt(sun_r * 0.92)}" '
        f'opacity=".9"/></g>'
    )

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
        f'role="img" aria-label="claude-infrastructure — the Claude Code creature walking a '
        f'looping landscape under drifting clouds">',
        f"<title>claude-infrastructure</title>",
        f"<desc>{art.title}. {art.blurb} One 240-second loop; the wordmark is legible at every "
        f"instant and nothing passes behind it.</desc>",
        f"<style>{css(art)}</style>",
        "<defs>",
        sky_defs(art),
        moon(art),
        f'<clipPath id="belowGround"><rect x="0" y="0" width="{W}" height="{GROUND}"/></clipPath>',
        "</defs>",
        # sky, then the light that sits in it
        f'<rect class="sky" width="{W}" height="{H}"/>',
        f'<rect class="glw" x="0" y="{fmt(GROUND - 300)}" width="{W}" height="330"/>',
        # stars are night-only; the moon becomes a soft day disc in the light theme
        f'<g class="nOnly">{starfield(art, rng)}</g>',
        f'<g class="nOnly">{moon_body(art)}</g>',
        day_sun,
        # clouds pass in FRONT of the moon, which is what makes the sky feel deep
        clouds(art, rng),
        events(art),
        # ground plane: fill first so the bottom third stops being dead space, then scenery
        f'<rect class="grd" x="0" y="{GROUND}" width="{W}" height="{H - GROUND}"/>',
        mounds(art, rng),
        peek(art),
        ground_detail(art),
        f'<line x1="0" y1="{GROUND}" x2="{W}" y2="{GROUND}" class="rl" stroke-width="3" '
        f'stroke-dasharray="3 9" stroke-linecap="round" opacity=".72"/>',
        clawd_placed(art, art.clawd_x, scale),
    ]

    if art.second_clawd:
        parts.append(second_session(art))

    # vignette BEFORE the type: focuses the frame without ever touching the wordmark
    parts.append(f'<rect class="vig" width="{W}" height="{H}"/>')

    # the type, last — nothing can be over it
    parts.append(
        f'<text x="{W // 2}" y="140" text-anchor="middle" class="wm" '
        f'font-family="ui-monospace,SFMono-Regular,Menlo,monospace" font-size="62" '
        f'letter-spacing="1.5">claude-infrastructure</text>'
    )
    if art.hairline:
        parts.append(
            f'<rect class="sub" x="{W // 2 - 132}" y="163" width="264" height="1" '
            f'opacity=".28"/>'
        )
    parts.append(
        f'<text x="{W // 2}" y="{188 if art.hairline else 182}" text-anchor="middle" class="sub" '
        f'font-family="ui-monospace,SFMono-Regular,Menlo,monospace" font-size="17" '
        f'letter-spacing="7.5">{art.subtitle}</text>'
    )
    parts.append("</svg>")
    assert_type_clear()
    return "".join(parts)


def second_session(art: Art) -> str:
    """The rare beat that makes the subject the WHOLE system rather than one creature: a second
    session walks in from the right, the two meet, both throw their arms up, and the newcomer
    carries on — 'sessions run each other', once per loop.
    """
    divides_P(P)
    s = art.clawd_scale * 0.92
    ty = GROUND - SPRITE_H * s
    return (
        f'<g class="peerWrap"><g class="peer">'
        f'<g transform="translate(0 {fmt(ty)}) scale({fmt(s)})" shape-rendering="crispEdges">'
        f'<g class="peerFlip">'
        f'<rect x="{CELL}" y="0" width="{9 * CELL}" height="{6 * CELL}" fill="{CLAWD}"/>'
        f'<rect x="0" y="{2 * CELL}" width="{CELL}" height="{2 * CELL}" fill="{CLAWD}"/>'
        f'<rect x="{10 * CELL}" y="{2 * CELL}" width="{CELL}" height="{2 * CELL}" fill="{CLAWD}"/>'
        f'<rect class="eyeHole" x="{2 * CELL}" y="{2 * CELL}" width="{CELL}" height="{CELL}"/>'
        f'<rect class="eyeHole" x="{8 * CELL}" y="{2 * CELL}" width="{CELL}" height="{CELL}"/>'
        f'<g class="pLegA"><rect x="{CELL}" y="{6 * CELL}" width="{CELL}" height="{2 * CELL}" '
        f'fill="{CLAWD}"/><rect x="{7 * CELL}" y="{6 * CELL}" width="{CELL}" height="{2 * CELL}" '
        f'fill="{CLAWD}"/></g>'
        f'<g class="pLegB"><rect x="{3 * CELL}" y="{6 * CELL}" width="{CELL}" height="{2 * CELL}" '
        f'fill="{CLAWD}"/><rect x="{9 * CELL}" y="{6 * CELL}" width="{CELL}" height="{2 * CELL}" '
        f'fill="{CLAWD}"/></g>'
        f"</g></g></g></g>"
    )


# ── the art directions ────────────────────────────────────────────────────────────────────────────
NIGHT = Theme(
    sky_top="#05070d",
    sky_mid="#0a1020",
    sky_low="#151d33",
    glow="#3d4a72",
    glow_op=0.40,
    ground_top="#1e2941",
    ground_bot="#111a2d",
    rule="#5d6b80",
    wm="#eef3fa",
    sub="#8794a6",
    star="#cfe0f5",
    moon="#e9e4d3",
    moon_halo="#e9e4d3",
    cloud=[
        ("#131b2d", "#1e2942", "#0e1524"),
        ("#182136", "#26324e", "#111829"),
        ("#1c2740", "#2d3b59", "#141c2f"),
    ],
    mound=["#1e2c48", "#101a2e"],
    tuft="#33415f",
    fg="#070b14",
    vignette=0.42,
)

DAY = Theme(
    sky_top="#bcd8f2",
    sky_mid="#dbe9f8",
    sky_low="#f4f2ec",
    glow="#ffe6c2",
    glow_op=0.62,
    ground_top="#ebe6d8",
    ground_bot="#d7d2c2",
    rule="#9aa3ad",
    wm="#111820",
    sub="#5b6672",
    star="#ffffff",
    moon="#ffd79a",
    moon_halo="#ffd79a",
    cloud=[
        ("#f2f7fd", "#ffffff", "#dae6f2"),
        ("#f7fafe", "#ffffff", "#dfe9f4"),
        ("#fbfdff", "#ffffff", "#e4edf6"),
    ],
    mound=["#c6c8c0", "#adafa2"],
    tuft="#a8a99c",
    fg="#8d8e80",
    vignette=0.10,
)

DUSK = Theme(
    sky_top="#0b1020",
    sky_mid="#232a4a",
    sky_low="#6b4a58",
    glow="#e08a5a",
    glow_op=0.52,
    ground_top="#3a2b35",
    ground_bot="#1d1622",
    rule="#7a6572",
    wm="#fdf3ec",
    sub="#b39a9a",
    star="#ffe9d6",
    moon="#fbe3c4",
    moon_halo="#fbe3c4",
    cloud=[
        ("#282142", "#3f3358", "#1b1730"),
        ("#332947", "#4f3d60", "#231c36"),
        ("#3d2e4c", "#63455f", "#2a2039"),
    ],
    mound=["#33253a", "#191221"],
    tuft="#4d3a49",
    fg="#0c0812",
    vignette=0.44,
)

DAWN = Theme(
    sky_top="#8fc0e8",
    sky_mid="#d9e2f0",
    sky_low="#ffe9cf",
    glow="#ffc27a",
    glow_op=0.72,
    ground_top="#efe2cf",
    ground_bot="#dccbb2",
    rule="#a8968a",
    wm="#1a1410",
    sub="#6d5c50",
    star="#ffffff",
    moon="#ffcf94",
    moon_halo="#ffcf94",
    cloud=[
        ("#f6f0fb", "#ffffff", "#e2dced"),
        ("#fbf2f2", "#ffffff", "#eadfe0"),
        ("#fff6ef", "#ffffff", "#f0e2d4"),
    ],
    mound=["#c8b9a4", "#ae9c85"],
    tuft="#a89684",
    fg="#8e7d6b",
    vignette=0.12,
)

TERM = Theme(
    sky_top="#070a0d",
    sky_mid="#0b1014",
    sky_low="#10171b",
    glow="#2b4a4a",
    glow_op=0.34,
    ground_top="#16211f",
    ground_bot="#0b1211",
    rule="#4e6b66",
    wm="#e6f2ee",
    sub="#7f9c95",
    star="#bfe3d8",
    moon="#dce9e2",
    moon_halo="#dce9e2",
    cloud=[
        ("#101a1c", "#18282a", "#0b1315"),
        ("#142023", "#1f3134", "#0e181a"),
        ("#182629", "#26393c", "#111e20"),
    ],
    mound=["#1a2a24", "#0c1514"],
    tuft="#28413c",
    fg="#050908",
    vignette=0.38,
)

TERM_L = Theme(
    sky_top="#cfe0da",
    sky_mid="#e6efeb",
    sky_low="#f4f7f4",
    glow="#cfe8dc",
    glow_op=0.50,
    ground_top="#e2e8e2",
    ground_bot="#cdd6ce",
    rule="#8fa39c",
    wm="#0d1512",
    sub="#556661",
    star="#ffffff",
    moon="#f0e6c8",
    moon_halo="#f0e6c8",
    cloud=[
        ("#eef5f1", "#ffffff", "#d8e4de"),
        ("#f3f8f5", "#ffffff", "#dde8e2"),
        ("#f8fbf9", "#ffffff", "#e2ece6"),
    ],
    mound=["#c0cac2", "#a9b4ab"],
    tuft="#a3aea7",
    fg="#8b968f",
    vignette=0.10,
)


VARIANTS = [
    Art(
        key="v6a-long-night",
        title="Long Night",
        blurb=(
            "A deep graded sky with a real crescent moon, three bands of lit-edge cumulus and a "
            "ground plane that finally uses the bottom of the frame."
        ),
        dark=NIGHT,
        light=DAY,
        clawd_scale=1.06,
        clawd_x=628,
        star_count=(165, 68, 22),
        moon=(1656, 166, 62),
        moon_phase=0.30,
        events=("shootingstar", "birds", "peek"),
    ),
    Art(
        key="v6b-two-sessions",
        title="Two Sessions",
        blurb=(
            "The same night, but once per loop a second session walks in from the right, the two "
            "meet, both throw their arms up, and the newcomer carries on — the title happening "
            "rather than being described."
        ),
        dark=NIGHT,
        light=DAY,
        clawd_scale=1.0,
        clawd_x=560,
        star_count=(150, 62, 20),
        moon=(1672, 178, 56),
        moon_phase=0.30,
        events=("shootingstar", "birds"),
        second_clawd=True,
        cheer_period=240.0,
        hairline=True,
    ),
    Art(
        key="v6c-dusk-line",
        title="Dusk Line",
        blurb=(
            "Cinematic: a warm horizon burns under a cold upper sky, clouds catch the last light "
            "on their undersides, and the creature walks a rim-lit ridge."
        ),
        dark=DUSK,
        light=DAWN,
        clawd_scale=1.12,
        clawd_x=1096,
        star_count=(120, 44, 14),
        moon=(250, 214, 70),
        moon_phase=0.30,
        events=("shootingstar", "balloon", "birds", "peek"),
    ),
    Art(
        key="v6d-terminal-field",
        title="Terminal Field",
        blurb=(
            "The welcome screen's own language taken seriously — everything on one grid, a cool "
            "phosphor cast, and the quietest motion of the four."
        ),
        dark=TERM,
        light=TERM_L,
        clawd_scale=0.98,
        clawd_x=812,
        star_count=(130, 50, 16),
        moon=(1706, 140, 50),
        moon_phase=0.34,
        events=("birds", "peek"),
        hairline=True,
    ),
]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/banner")
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for art in VARIANTS:
        if args.only and args.only not in art.key:
            continue
        svg = build(art)
        p = out / f"{art.key}.svg"
        p.write_text(svg, encoding="utf-8")
        print(f"{p}  {len(svg):,} B  ({art.title})")


if __name__ == "__main__":
    main()
