#!/usr/bin/env python3
"""Generate the v6 hero banners.

Everything the plan settled is enforced here rather than trusted to hand-typing:

  * P = 240 s master period, and every sub-period is CHECKED to divide it (S1/S2). A period that
    does not divide P is a build error, not a subtle visual bug found later by a frame hash.
  * Phase comes from `--d` (a negative delay through the additive channel), never from a
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
import re
import zlib
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


# ── the stride/scroll lock ─────────────────────────────────────────────────────────────────────
# The creature has been SLIDING. Its legs alternate on a 0.5s stride, but the ground beneath it
# scrolled at a rate with no relationship to that, so each step covered a fractional number of
# cells: measured 1.51 cells against the near tufts, 0.75 against the mounds, 2.26 against the
# foreground. It is worse than one wrong number — there were FOUR different ground-ish rates, so
# there was no single ground speed to be locked to in the first place.
#
# This matters beyond the sliding: a footprint baked into the strip at one stride pitch, so the foot
# lands in an existing print every stride, is impossible until the lock holds. Prerequisite, not
# polish.
#
# The condition is (TILE / STRIP_PERIOD) * STRIDE == k * CELL * scale, with STRIP_PERIOD and STRIDE
# both dividing P. Enumerating the solutions in the usable scale band gives T=20s at scale 1.2 with
# k=2 — one full leg-spacing per stride — which also scales the creature UP, which is what gesture
# legibility wanted anyway.
STRIDE = 0.5  # seconds per step (half the two-step cycle)
STRIP_PERIOD = 20.0  # seconds for the strip to travel one TILE
STRIP_PX_PER_STRIDE = TILE / STRIP_PERIOD * STRIDE  # 48 px


def assert_stride_locked(art: Art) -> None:
    """The ground must advance an exact whole number of sprite cells per stride."""
    cell_px = CELL * art.clawd_scale
    cells = STRIP_PX_PER_STRIDE / cell_px
    if abs(cells - round(cells)) > 1e-9:
        raise SystemExit(
            f"gen[{art.key}]: stride/scroll NOT LOCKED — the strip advances "
            f"{STRIP_PX_PER_STRIDE:.2f}px per {STRIDE}s stride, which is {cells:.3f} sprite cells at "
            f"scale {art.clawd_scale}. The creature slides. Pick a scale where this is a whole "
            f"number (at STRIP_PERIOD={STRIP_PERIOD:g}s: 1.2 gives 2 cells, 1.0 gives 2.4 — not "
            f"whole)."
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


def seed_of(name: str) -> int:
    """A seed that is stable ACROSS PROCESSES.

    `hash()` on a str is salted per interpreter run (PEP 456), so `random.Random(hash(cls))` reseeds
    differently on every invocation and the generator silently stops being reproducible: the file
    still passes every structural check — seam, aliveness, lint — because those test properties of
    the output rather than its identity, so nothing reports a problem. Caught only by regenerating
    and comparing hashes against the committed asset.
    """
    return zlib.crc32(name.encode("utf-8")) & 0xFFFFFFFF


def in_keepout(x: float, y: float, pad: float = 0) -> bool:
    x0, y0, x1, y1 = KEEPOUT
    return (x0 - pad) <= x <= (x1 + pad) and (y0 - pad) <= y <= (y1 + pad)


def keepout_distance(x: float, y: float) -> float:
    """Distance from the keep-out rectangle; 0 inside it."""
    x0, y0, x1, y1 = KEEPOUT
    dx = max(x0 - x, 0, x - x1)
    dy = max(y0 - y, 0, y - y1)
    return math.hypot(dx, dy)


# ── rare events: ONE source of truth for both the keyframes and the disjointness gate ──────────
#
# Every rare event declares its visible window in ABSOLUTE SECONDS on the P=240 s loop, and the CSS
# percentages are derived from that. Previously each window was hand-written as a percentage inside
# its own keyframe string, which is how the shipped defect happened: `rCheer` ran on a 120 s
# sub-period, so it fired TWICE, and its second firing (154.1-158.4 s) sat entirely inside `rSleep`
# (151.7-158.4 s) — the generator had even phase-locked both to end at the same instant. The result
# rendered a sleeping creature, eyes shut and Zzz up, sprouting raised arms.
#
# "Sequence, do not stack" was written down and then regressed anyway, because prose is not
# enforcement. So it is a build-time assertion now: a stacked pair REFUSES TO BUILD.
#
# Every event fires ONCE per loop (period = P). That is also what makes "rare" true — the previous
# set had birds at 40% duty across three passes and a balloon at 40% across two, so two-thirds of
# the loop had something crossing the sky.
EVENT_GAP = 4.0  # seconds of clear air required between any two rare events

# WHAT IS *NOT* A RARE EVENT, and why the distinction is load-bearing.
#
# Only entries in RARE_EVENTS are collision partners. Two animations look like events but are
# TEXTURE, and counting either would make the gate report overlaps that are not defects:
#
#   · the contact shadow (`shdw`) — it is the creature's own ground shadow, so it is present
#     whenever the creature is; treating it as an event would collide it with everything.
#   · the Zzz (`zz1`/`zz2`) — co-occurs with `rSleep` for its full duration BY DESIGN. Sleep and its
#     Zzz are ONE beat expressed by two elements, not two beats that happen to overlap.
#
# The same holds for the constant-life animations (stride, bob, blink, look, ears): they are the
# character being alive, not occurrences. A successor who adds any of these to RARE_EVENTS gets a
# flood of false collisions and would plausibly "fix" it by loosening the gate — which is the
# failure mode this exists to prevent.
RARE_EVENT_NON_MEMBERS = (
    "shdw",
    "zz1",
    "zz2",
    "hop",
    "blink",
    "look",
    "legA",
    "legB",
    "bob",
)


def assert_texture_not_eventised() -> None:
    """Texture must never become a collision partner — see RARE_EVENT_NON_MEMBERS."""
    leaked = [n for n in RARE_EVENT_NON_MEMBERS if n in RARE_EVENTS]
    if leaked:
        raise SystemExit(
            f"gen: {leaked} promoted into RARE_EVENTS. These are texture, not occurrences — the "
            f"shadow is present whenever the creature is, and the Zzz IS the sleep beat rather than "
            f"a second one. Counting them makes the disjointness gate report collisions that are "
            f"not defects."
        )


RARE_EVENTS = {
    #  name        (start_s, end_s)   duration — all now inside the 2.5-10s band
    "peek": (3.0, 9.0),        # 6.0s — a GLANCE, which is what its motion always read as
    "peer": (3.0, 12.0),       # 9.0s — v6b only, in place of peek
    "rCheer": (6.0, 10.0),     # 4.0s — part of the peer's visit in v6b, see COMPOSITE_OF
    "rSleep": (24.0, 32.0),    # 8.0s — posture only now; the Zzz glyph is deleted
}

# Beats that are ONE beat expressed as two, so the gate must not treat them as a collision.
# Precedent: the Zzz was never a second event alongside the sleep. The resident's cheer is CAUSED by
# the visitor's arrival, so it belongs inside the visit — forbidding that overlap would forbid the
# causality the whole redesign exists for.
# The cheer is caused by whichever VISITOR beat that variant carries — `peer` in v6b, `peek`
# elsewhere — so it composites with either. Naming only one parent made the gate correctly
# reject v6a, where the cheer is caused by the peek it was overlapping.
COMPOSITE_OF = {"rCheer": {"peer", "peek"}}

# DELETED, reasons recorded so they are not rediscovered as ideas:
#   balloon — filler with no cause for entering; renders the brand asterisk as a stray object (R4).
#   shoot   — the most tired beat available, AND absent in the day scheme, so it cannot carry
#             anything in both. v6d already shipped without it: evidence the deletion costs nothing.
#   birds   — never in anyone's inventory, never reviewed, 40% duty over three passes, no story.
#   Zzz     — UI iconography. Idleness here is a reaper classification and a closed pane, not sleep.
DELETED_EVENTS = ("balloon", "shoot", "birds")


# ── the duty budget ────────────────────────────────────────────────────────────────────────────
# Ratified thresholds from the panel synthesis. These are bands with derivations, not taste: the
# per-instance ceiling comes from duration <= 1/3 of median dwell, so entry + middle + exit all fit
# in ONE visit with air either side.
BUDGET = {
    "instance_min": 2.5,  # s — shorter than this and a beat cannot be read as caused
    "instance_max": 10.0,  # s
    "per_type_pct": 4.0,  # <= 4% of P, i.e. <= 9.6 s total per event type
    "aggregate_pct": 25.0,  # all rare events summed
    "union_pct": 35.0,  # coverage; equals aggregate while the disjointness gate holds
    "air_pct": 65.0,  # >= this much of the loop with nothing rare on canvas
    "recur_gap": 60.0,  # s — no type may recur inside this
    "first_beat_max": 45.0,  # s — at least one instance must enter before this
}

# The current event SET is deliberately unratified (the panel is still open), so the variants do not
# meet the budget yet. Rather than let the gate pass vacuously or block work that is on hold by
# agreement, each unmet check is WAIVED BY NAME with a reason — and every waived check prints its
# real measured value on every build, so the gap stays visible instead of becoming the new normal.
# Deleting an entry here is what turns each threshold live; that is a one-line change per check.
# Each waived check names the EVENTS it covers, not just the check. A waiver keyed only by check
# name is a blanket: the `instance` waiver below is justified by three beats running LONG, and when
# it was keyed by name alone it also silently absorbed a beat that was too SHORT — the opposite
# defect, suppressed by a reason that did not apply to it. `None` means the check is not per-event
# (aggregate, air, first_beat), so it is waived whole.
# EMPTY BY DESIGN. Every threshold is live: the over-budget beats were thinned or deleted, so there
# is nothing left to waive. An entry here is a suppression that must carry a reason and an owner; an
# empty dict is the state to return to.
BUDGET_WAIVED: dict[str, tuple[set[str] | None, str]] = {}


def _waived(kind: str, event: str | None) -> str | None:
    """The waiver reason if this specific breach is covered, else None."""
    entry = BUDGET_WAIVED.get(kind)
    if entry is None:
        return None
    events, reason = entry
    if events is not None and event not in events:
        return None
    return reason


def assert_duty_budget(art: Art) -> None:
    """Measure every rare event against the ratified budget; fail on any unwaived breach."""
    active = sorted(
        {n for n in RARE_EVENTS if n in art.events}
        | ({"peer"} if art.second_clawd else set())
        | {"rCheer", "rSleep"},
        key=lambda n: RARE_EVENTS[n][0],
    )
    spans = {n: RARE_EVENTS[n][1] - RARE_EVENTS[n][0] for n in active}
    agg = sum(spans.values())
    breaches, waived = [], []

    def check(kind: str, ok: bool, msg: str, event: str | None = None) -> None:
        if ok:
            return
        reason = _waived(kind, event)
        (waived if reason else breaches).append((kind, msg, reason))

    for n, d in spans.items():
        check(
            "instance",
            BUDGET["instance_min"] <= d <= BUDGET["instance_max"],
            f"'{n}' runs {d:.1f}s, outside the {BUDGET['instance_min']}-{BUDGET['instance_max']}s "
            f"per-instance band",
            n,
        )
        check(
            "per_type",
            d / P * 100 <= BUDGET["per_type_pct"],
            f"'{n}' is {d / P * 100:.1f}% duty ({d:.1f}s), over the {BUDGET['per_type_pct']}% "
            f"per-type ceiling ({P * BUDGET['per_type_pct'] / 100:.1f}s)",
            n,
        )
    check(
        "aggregate",
        agg / P * 100 <= BUDGET["aggregate_pct"],
        f"aggregate rare-event duty is {agg / P * 100:.1f}%, over the "
        f"{BUDGET['aggregate_pct']}% ceiling",
    )
    check(
        "air",
        (P - agg) / P * 100 >= BUDGET["air_pct"],
        f"empty air is {(P - agg) / P * 100:.1f}%, under the {BUDGET['air_pct']}% floor",
    )
    if active:
        first = min(RARE_EVENTS[n][0] for n in active)
        check(
            "first_beat",
            first <= BUDGET["first_beat_max"],
            f"first beat enters at t={first:.1f}s, after the {BUDGET['first_beat_max']}s mark — "
            f"and the timeline anchors at LOAD, so a late beat is unseen, not rare",
        )

    if waived:
        print(f"  [{art.key}] budget WAIVED ({len(waived)}), measured anyway:")
        for _kind, msg, reason in waived:
            print(f"      · {msg}")
            print(f"        waiver: {reason}")
    if breaches:
        raise SystemExit(
            f"gen[{art.key}]: duty budget breached:\n"
            + "\n".join(f"  · {m}" for _k, m, _r in breaches)
        )


def ev(name: str) -> tuple[float, float]:
    return RARE_EVENTS[name]


def pct(t: float) -> str:
    """A window edge as a percentage of the master period."""
    return fmt(round(t / P * 100, 3))


def assert_event_names_known(art: Art) -> None:
    """Every event a variant declares must exist in RARE_EVENTS.

    The two vocabularies drifted: the table keyed the shooting star as `shoot` while the variants
    declared `shootingstar`, so the membership test never matched and the event was SILENTLY EXCLUDED
    from both the disjointness gate and the duty budget. A gate that quietly skips an event is worse
    than no gate, because it reports green over the thing it was built to check.
    """
    unknown = [n for n in art.events if n not in RARE_EVENTS]
    if unknown:
        raise SystemExit(
            f"gen[{art.key}]: declares event(s) {unknown} that are not in RARE_EVENTS "
            f"{sorted(RARE_EVENTS)} — they would be silently skipped by every temporal check"
        )


def assert_events_disjoint(art: Art) -> None:
    """Refuse to emit a variant whose rare events overlap in time.

    Only the events this variant actually EMITS are checked — carrying an unused keyframe is
    harmless, and `peek`/`peer` deliberately share a slot because no variant has both.
    """
    active = [n for n in RARE_EVENTS if n in art.events]
    if art.second_clawd:
        active.append("peer")
    if "rCheer" not in active:
        active.append("rCheer")
    if "rSleep" not in active:
        active.append("rSleep")
    active = sorted(set(active), key=lambda n: RARE_EVENTS[n][0])

    for i in range(len(active)):
        for j in range(i + 1, len(active)):
            a, b = active[i], active[j]
            (a0, a1), (b0, b1) = RARE_EVENTS[a], RARE_EVENTS[b]
            if b in COMPOSITE_OF.get(a, ()) or a in COMPOSITE_OF.get(b, ()):
                continue   # one beat in two elements — see COMPOSITE_OF
            if a0 < b1 + EVENT_GAP and b0 < a1 + EVENT_GAP:
                raise SystemExit(
                    f"gen[{art.key}]: rare events '{a}' ({a0:.1f}-{a1:.1f}s) and '{b}' "
                    f"({b0:.1f}-{b1:.1f}s) overlap or sit within the {EVENT_GAP:.0f}s gap on the "
                    f"{P:.0f}s loop. Two unrelated things happening at once cannot read as caused; "
                    f"re-time one of them in RARE_EVENTS."
                )
        # an event must also fit inside the loop, or it wraps and silently becomes two events
        a0, a1 = RARE_EVENTS[active[i]]
        if not (0 <= a0 < a1 <= P):
            raise SystemExit(
                f"gen[{art.key}]: '{active[i]}' window {a0}-{a1}s does not fit in P={P}s"
            )


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
    star_cool: str
    star_warm: str
    grain: float
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
    clawd_scale: float = 1.2
    clawd_x: float = 700
    cloud_layers: int = 3
    star_count: tuple[int, int, int] = (150, 62, 20)
    moon: tuple[float, float, float] = (1648, 206, 62)  # cx, cy, r
    moon_phase: float = 0.30  # 0 = full, 1 = sliver
    events: tuple[str, ...] = ("peek",)
    second_clawd: bool = False
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
    style = f' style="--d:{fmt(-delay)}s"' if delay else ""
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
        f'<stop offset="0.3" stop-color="{d.moon}" stop-opacity="0.38"/>'
        f'<stop offset="1" stop-color="{d.moon}" stop-opacity="0"/></radialGradient>'
        # The wide outer bloom is cooler than the core. Real glow shifts temperature outward; a
        # single-colour radial gradient is the tell of vector art.
        f'<radialGradient id="bloom" cx="0.5" cy="0.5" r="0.5">'
        f'<stop offset="0.12" stop-color="{d.moon}" stop-opacity="0.20"/>'
        f'<stop offset="0.45" stop-color="{d.glow}" stop-opacity="0.09"/>'
        f'<stop offset="1" stop-color="{d.glow}" stop-opacity="0"/></radialGradient>'
        # A small blur on the tight halo so its falloff is OPTICAL rather than a gradient stop.
        # Verified to render in SVG-as-image (Chromium 141): the blurred edge samples to true
        # intermediate values between disc and sky, not to either endpoint.
        f'<filter id="soft" x="-70%" y="-70%" width="240%" height="240%">'
        f'<feGaussianBlur stdDeviation="9"/></filter>'
        # ONE low-opacity grain layer over the sky. This is the single biggest change against the
        # plastic flatness of a large gradient. Measured over a flat patch: stddev 4.75 with the
        # filter vs 1.11 without, so it is genuinely rendering and not a no-op.
        f'<filter id="grain" x="0%" y="0%" width="100%" height="100%">'
        f'<feTurbulence type="fractalNoise" baseFrequency="0.82" numOctaves="2" seed="11" '
        f'result="n"/>'
        f'<feColorMatrix in="n" type="saturate" values="0"/></filter>'
        # A terminator across the lit limb turns a flat crescent into an object.
        f'<linearGradient id="term" x1="0" y1="0" x2="1" y2="0.25">'
        f'<stop offset="0" stop-color="#000" stop-opacity="0.20"/>'
        f'<stop offset="0.45" stop-color="#000" stop-opacity="0"/>'
        f'<stop offset="1" stop-color="#000" stop-opacity="0.10"/></linearGradient>'
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


def poisson(
    count: int,
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    rng: random.Random,
    r_at,
    void_mask,
) -> list[tuple[float, float]]:
    """Blue-noise scatter by dart-throwing against a spatial grid, with a VARIABLE minimum radius.

    Uniform random placement reads as wallpaper and clumps read as spam; a jittered grid (the
    previous approach) fixes the clumping but leaves a faint lattice. Blue noise is the one that
    reads as sky: never two stars piled together, never a row.

    `r_at(y)` returns the minimum separation at that height, so density varies deliberately —
    sparser low, where atmosphere washes stars out. `void_mask(x, y)` returns False for deliberate
    empty regions: unoccupied sky is what makes occupied sky read as composed rather than sprinkled.
    """
    r_min = min(r_at(y0), r_at(y1))
    cell = max(2.0, r_min / math.sqrt(2))
    grid: dict[tuple[int, int], list[tuple[float, float]]] = {}
    pts: list[tuple[float, float]] = []

    def fits(x: float, y: float, r: float) -> bool:
        gx, gy = int(x / cell), int(y / cell)
        span = int(math.ceil(r / cell)) + 1
        for i in range(gx - span, gx + span + 1):
            for j in range(gy - span, gy + span + 1):
                for px, py in grid.get((i, j), ()):
                    if (px - x) ** 2 + (py - y) ** 2 < r * r:
                        return False
        return True

    attempts = 0
    budget = count * 260
    while len(pts) < count and attempts < budget:
        attempts += 1
        x = rng.uniform(x0, x1)
        y = rng.uniform(y0, y1)
        if not void_mask(x, y):
            continue
        r = r_at(y)
        if not fits(x, y, r):
            continue
        pts.append((x, y))
        grid.setdefault((int(x / cell), int(y / cell)), []).append((x, y))
    return pts


# Star colour temperature. All-white stars look cheap; a few degrees of spread either side of
# neutral is the cheapest refinement available in the whole sky.
STAR_TEMPS = [
    ("sc", 0.30),
    ("sn", 0.46),
    ("sw", 0.24),
]  # cool / neutral / warm, with weights


def starfield(art: Art, rng: random.Random) -> str:
    """One blue-noise field with depth expressed by size and brightness, not by three separate
    passes, plus deliberate voids and a hard keep-out around the type (S7).

    Two things here are restraint rather than omission. Most stars do NOT twinkle — a whole sky
    pulsing is a screensaver, and it also competes with the wordmark; only a minority animate, on
    uncorrelated periods. And the 4-point diffraction cross is reserved for the two or three
    brightest: that detail is what makes a field read as photographic, and it stops working the
    moment everything has one.
    """
    total = sum(art.star_count)
    divides_P(60.0, 30.0, 20.0, 12.0)

    # Deliberate voids — a few soft holes in the field, so the sky has empty quarters.
    voids = [
        (rng.uniform(0, W), rng.uniform(10, 300), rng.uniform(90, 210))
        for _ in range(4)
    ]

    def void_mask(x: float, y: float) -> bool:
        for vx, vy, vr in voids:
            d = math.hypot(x - vx, y - vy)
            if d < vr and rng.random() > (d / vr) ** 2.2:
                return False
        return True

    # Minimum separation grows toward the horizon: denser high, sparser low.
    def r_at(y: float) -> float:
        return 15.0 * (1.0 + 2.3 * (max(0.0, y) / 330.0) ** 1.5)

    pts = poisson(total, 8, W - 8, 8, 330, rng, r_at, void_mask)
    pts = [(x, y) for (x, y) in pts if not in_keepout(x, y)]
    pts = [
        (x, y)
        for (x, y) in pts
        if keepout_distance(x, y) >= KEEPOUT_SOFT
        or rng.random() <= (keepout_distance(x, y) / KEEPOUT_SOFT) ** 0.9
    ]

    # Brightness rank drives size, opacity and who gets a cross — one axis, so depth stays coherent.
    ranked = sorted(pts, key=lambda _p: rng.random())
    out = []
    n_cross = 3
    n_twinkle = max(1, int(len(ranked) * 0.22))
    periods = [60.0, 20.0, 12.0]
    for i, (x, y) in enumerate(ranked):
        q = i / max(1, len(ranked) - 1)  # 0 = brightest
        size = 3.6 - 2.0 * q**0.6
        op = 0.95 - 0.62 * q**0.75
        temp = STAR_TEMPS[0][0]
        roll = rng.random()
        acc = 0.0
        for cls, wgt in STAR_TEMPS:
            acc += wgt
            if roll <= acc:
                temp = cls
                break
        body = (
            f'<rect x="{fmt(x - size / 2)}" y="{fmt(y - size / 2)}" '
            f'width="{fmt(size)}" height="{fmt(size)}"/>'
        )
        if i < n_cross:
            # diffraction spikes, on the brightest handful only
            arm = size * 2.6
            t = max(0.8, size / 4.6)
            body += (
                f'<rect x="{fmt(x - t / 2)}" y="{fmt(y - arm)}" '
                f'width="{fmt(t)}" height="{fmt(arm * 2)}"/>'
                f'<rect x="{fmt(x - arm)}" y="{fmt(y - t / 2)}" '
                f'width="{fmt(arm * 2)}" height="{fmt(t)}"/>'
            )
        if i < n_twinkle:
            dur = periods[i % len(periods)]
            delay = -(i * 7.3) % dur
            # opacity AND scale together — a pure opacity blink reads as a rendering glitch
            out.append(
                f'<g class="st {temp} tw{i % 3}" style="--d:{fmt(-delay)}s" '
                f'opacity="{fmt(op)}" transform-origin="{fmt(x)}px {fmt(y)}px">'
                f"{body}</g>"
            )
        else:
            out.append(f'<g class="st {temp}" opacity="{fmt(op)}">{body}</g>')
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
    """Stacked glow, then the disc, then a terminator and a few maria.

    Three passes rather than one radial gradient: a wide cool bloom, a tight warm halo softened by
    an actual blur, and the disc itself. The whole group sits BEFORE the cloud layers, so the glow
    is occluded by the clouds along with the moon — a halo that survives in front of a cloud reads
    as pasted onto the scene.
    """
    cx, cy, r = art.moon
    divides_P(80.0)
    maria = []
    mr = random.Random(4242)
    for fx, fy, fr in ((-0.30, -0.22, 0.30), (0.10, 0.26, 0.22), (-0.06, 0.02, 0.15)):
        maria.append(
            f'<circle cx="{fmt(cx + fx * r)}" cy="{fmt(cy + fy * r)}" r="{fmt(fr * r)}" '
            f'fill="#000" opacity="{fmt(mr.uniform(0.045, 0.085))}"/>'
        )
    return (
        f'<g class="moonHalo">'
        f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r * 3.5)}" fill="url(#bloom)"/>'
        f"</g>"
        f'<g class="moonGlow">'
        f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r * 1.55)}" fill="url(#halo)" '
        f'filter="url(#soft)"/>'
        f"</g>"
        f'<g class="moonLit" mask="url(#mcut)">'
        f'<circle class="mdisc" cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}"/>'
        f"{''.join(maria)}"
        f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}" fill="url(#term)"/>'
        f"</g>"
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
            r2 = random.Random(seed_of(cls))
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
            r2 = random.Random(seed_of(cls))
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
    # arms-up: OUT as well as up. Raising the stubs in the same two columns leaves the silhouette
    # exactly as wide as at rest, so the only change is two nubs appearing above the head — which is
    # why the operator read it as horns rather than as a cheer. Moving them a full cell outboard
    # makes the silhouette itself change shape, which is what a gesture has to do to be nameable.
    # Measured: rest width 218 px on GitHub desktop; this takes the cheer to ~255 px.
    arms_up = (
        f'<rect x="{-c}" y="{eye_y - 3 * c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        f'<rect x="{11 * c}" y="{eye_y - 3 * c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        # the shoulder cells that connect the raised arms to the body, so they read as attached
        f'<rect x="0" y="{eye_y - c}" width="{c}" height="{c}" fill="{CLAWD}"/>'
        f'<rect x="{10 * c}" y="{eye_y - c}" width="{c}" height="{c}" fill="{CLAWD}"/>'
        f'<rect x="{fmt(5.2 * c)}" y="{fmt(-2.1 * c)}" width="{fmt(0.6 * c)}" '
        f'height="{fmt(0.6 * c)}" fill="{CLAWD}"/>'
        f'<rect x="{fmt(3.6 * c)}" y="{fmt(-1.5 * c)}" width="{fmt(0.45 * c)}" '
        f'height="{fmt(0.45 * c)}" fill="{CLAWD}" opacity=".7"/>'
        f'<rect x="{fmt(7.0 * c)}" y="{fmt(-1.6 * c)}" width="{fmt(0.45 * c)}" '
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
                f"</g>"
    )

    return (
        # turn-around: a rare scaleX flip so he walks against the scroll for a few seconds
        f'<g class="rTurn{sfx}">'
        f'<g class="hop{sfx}">'
        f'<g class="bob{sfx}">'
        # The idle side-arms must VANISH during the cheer, or the sprite shows four arms at once —
        # two at the sides and two raised — which is a large part of why the raised pair read as
        # horns rather than as arms. The gate cannot go on `.armsIdle` itself because that element
        # already carries the wiggle and only one animation per element survives the freeze (S8),
        # so it becomes a nested wrapper: gate outside, wiggle inside.
        f'<g class="armsGate{sfx}"><g class="armsIdle{sfx}">{arms_idle}</g></g>'
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
        f".st{{fill:{d.star}}}.sc{{fill:{d.star_cool}}}.sw{{fill:{d.star_warm}}}"
        f".sn{{fill:{d.star}}}.mdisc{{fill:{d.moon}}}"
        f".grain{{opacity:{fmt(d.grain)}}}"
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
        f".tf0s{{animation:sc {fmt(STRIP_PERIOD)}s linear infinite}}"
        f".tf1s{{animation:sc {fmt(P / 10)}s linear infinite}}"
        f".fgbs{{animation:sc {fmt(P / 12)}s linear infinite}}"
        # ---- twinkle: three rates so the sky has depth rather than one uniform pulse ----
        # Twinkle varies opacity AND scale together on eased curves. A pure opacity blink reads as a
        # rendering glitch rather than as atmosphere, and three uncorrelated periods stop the
        # minority that does animate from pulsing as one organism.
        f"@keyframes twA{{0%,100%{{opacity:.42;transform:scale(.86)}}50%{{opacity:1;transform:scale(1.1)}}}}"
        f"@keyframes twB{{0%,100%{{opacity:.55;transform:scale(.92)}}38%{{opacity:1;transform:scale(1.14)}}}}"
        f"@keyframes twC{{0%,100%{{opacity:.5;transform:scale(.9)}}62%{{opacity:1;transform:scale(1.06)}}}}"
        f".tw0{{animation:twA 60s ease-in-out infinite}}"
        f".tw1{{animation:twB 20s ease-in-out infinite}}"
        f".tw2{{animation:twC 12s ease-in-out infinite}}"
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
        # ---- rare emotes and world events ----
        # Every window below is DERIVED from RARE_EVENTS, which the build-time gate also reads, so a
        # stacked pair cannot be emitted. Hand-written percentages are what let the cheer land inside
        # the sleep. Every event runs on the full period, so each fires exactly ONCE per loop.
        + (
            lambda: "".join(
                [
                    # sleep: lids + Zzz on, walking legs swapped for standing ones
                    f"@keyframes rsf{{0%,{pct(ev('rSleep')[0])}%{{opacity:0}}"
                    f"{pct(ev('rSleep')[0] + 0.1)}%,{pct(ev('rSleep')[1])}%{{opacity:1}}"
                    f"{pct(ev('rSleep')[1] + 0.1)}%,100%{{opacity:0}}}}"
                    f".rSleep{{animation:rsf {fmt(P)}s steps(1,end) infinite}}",
                    f"@keyframes lwf{{0%,{pct(ev('rSleep')[0])}%{{opacity:1}}"
                    f"{pct(ev('rSleep')[0] + 0.1)}%,{pct(ev('rSleep')[1])}%{{opacity:0}}"
                    f"{pct(ev('rSleep')[1] + 0.1)}%,100%{{opacity:1}}}}"
                    f".legsWalk{{animation:lwf {fmt(P)}s steps(1,end) infinite}}",
                    f"@keyframes lsf{{0%,{pct(ev('rSleep')[0])}%{{opacity:0}}"
                    f"{pct(ev('rSleep')[0] + 0.1)}%,{pct(ev('rSleep')[1])}%{{opacity:1}}"
                    f"{pct(ev('rSleep')[1] + 0.1)}%,100%{{opacity:0}}}}"
                    f".legsStill{{animation:lsf {fmt(P)}s steps(1,end) infinite}}",
                    # cheer: raised arms ON and — the shipped bug — the IDLE side-arms OFF, or the sprite
                    # shows four arms at once, which is what read as horns with confetti
                    f"@keyframes rcf{{0%,{pct(ev('rCheer')[0])}%{{opacity:0}}"
                    f"{pct(ev('rCheer')[0] + 0.1)}%,{pct(ev('rCheer')[1])}%{{opacity:1}}"
                    f"{pct(ev('rCheer')[1] + 0.1)}%,100%{{opacity:0}}}}"
                    f".rCheer{{animation:rcf {fmt(P)}s steps(1,end) infinite}}",
                    f"@keyframes agf{{0%,{pct(ev('rCheer')[0])}%{{opacity:1}}"
                    f"{pct(ev('rCheer')[0] + 0.1)}%,{pct(ev('rCheer')[1])}%{{opacity:0}}"
                    f"{pct(ev('rCheer')[1] + 0.1)}%,100%{{opacity:1}}}}"
                    f".armsGate{{animation:agf {fmt(P)}s steps(1,end) infinite}}",
                    f"@keyframes pkf{{0%,{pct(ev('peek')[0])}%{{transform:translateY(78px)}}"
                    f"{pct(ev('peek')[0] + 3)}%,{pct(ev('peek')[1] - 3)}%{{transform:translateY(0)}}"
                    f"{pct(ev('peek')[1])}%,100%{{transform:translateY(78px)}}}}"
                    f".peek{{animation:pkf {fmt(P)}s ease-in-out infinite}}",
                    # ---- the peer session (v6b) ----
                    # It arrives from the right, holds beside the resident, and RETURNS THE WAY IT CAME.
                    # It used to exit leftwards THROUGH the resident: same flat #D77757, crispEdges, drawn
                    # above, so its blank body slid over the face and erased the eyes — two same-colour
                    # sprites merging into one connected orange region, which reads as a rendering error, or
                    # worse as one session absorbing another (the handoff infographic R1 rejected, acted out).
                    # A symmetric exit also reads as intent rather than as a despawn.
                    f"@keyframes prf{{0%,{pct(ev('peer')[0])}%{{opacity:0;transform:translateX({W + 240}px)}}"
                    f"{pct(ev('peer')[0] + 1)}%{{opacity:1}}"
                    f"{pct(ev('peer')[0] + 14)}%,{pct(ev('peer')[1] - 14)}%"
                    f"{{transform:translateX({fmt(art.clawd_x + SPRITE_W * art.clawd_scale + 46)}px)}}"
                    f"{pct(ev('peer')[1] - 1)}%{{opacity:1;transform:translateX({W + 240}px)}}"
                    f"{pct(ev('peer')[1])}%,100%{{opacity:0;transform:translateX({W + 240}px)}}}}"
                    f".peer{{animation:prf {fmt(P)}s linear infinite}}",
                    # NOTE: there is deliberately no scaleX flip on the peer. The sprite is bilaterally
                    # symmetric — eyes at 40-60 and 160-180 about centre 110 — so scaleX(-1) maps it onto
                    # itself and the "turn to face" beat was invisible by construction. It existed only in
                    # the code. Direction now reads from travel alone, which is honest.
                    f"@keyframes pcf{{0%,{pct(ev('peer')[0] + 16)}%{{opacity:0}}"
                    f"{pct(ev('peer')[0] + 17)}%,{pct(ev('peer')[1] - 16)}%{{opacity:1}}"
                    f"{pct(ev('peer')[1] - 15)}%,100%{{opacity:0}}}}"
                    f".pCheer{{animation:pcf {fmt(P)}s steps(1,end) infinite}}",
                ]
            )
        )()
        # the peer's stride — the only peer motion not driven by the event table
        + (
            f"@keyframes pwA{{0%,49%{{transform:translateY(0)}}"
            f"50%,100%{{transform:translateY(-{fmt(CELL * 0.6)}px)}}}}"
            f"@keyframes pwB{{0%,49%{{transform:translateY(-{fmt(CELL * 0.6)}px)}}"
            f"50%,100%{{transform:translateY(0)}}}}"
            f".pLegA{{animation:pwA .5s steps(1,end) infinite}}"
            f".pLegB{{animation:pwB .5s steps(1,end) infinite;--d:-.12s}}"
        )
    )

    # Give every animation declaration the ADDITIVE delay channel, so any element may carry its own
    # phase in `--d` while the screenshot harness supplies the global seek in `--fz` and the delay is
    # their sum. The `animation:` shorthand resets animation-delay to 0s, so the longhand must follow
    # it — hence appending rather than prepending.
    #
    # Why not just author the delay directly: `banner-shots.sh`'s freeze reaches a timestamp by
    # setting animation-delay on `*`, which OVERWRITES an authored delay outright. The animation is
    # still right in a browser, but every frozen verification frame renders a deliberately staggered
    # population in lockstep — a plausible-looking render that is wrong, which is worse than an
    # obviously broken one. The harness lints for exactly this. Phase is necessary (many elements, one
    # shared master period, per S2), so the answer is a channel the seek can add to, not less phase.
    base = re.sub(
        r"(animation:[^;{}]*?infinite)",
        r"\1;animation-delay:calc(var(--d,0s) + var(--fz,0s))",
        base,
    )

    # A still that is legible on its own, not a frame that happens to be paused. The rare emotes
    # resolve to their hidden state and the visitor stays down.
    reduced = (
        "@media (prefers-reduced-motion:reduce){"
        "*{animation:none!important}"
        ".rSleep,.rCheer,.legsStill,.eShut,.peer,.pCheer{opacity:0}"
        ".legsWalk,.eOpen,.armsGate{opacity:1}"
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
        f".grain{{opacity:{fmt(l.grain)}}}"
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
    assert_texture_not_eventised()
    assert_event_names_known(art)
    assert_events_disjoint(art)
    assert_stride_locked(art)
    assert_duty_budget(art)
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
        # grain over the sky only — it must not crawl over the ground plane or the type
        f'<rect class="grain" x="0" y="0" width="{W}" height="{GROUND}" filter="url(#grain)"/>',
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
        # There is deliberately NO scaleX flip wrapper here. The sprite is bilaterally symmetric —
        # eyes at 40-60 and 160-180 about centre 110, body 20-200, arm stubs 0-20 and 200-220 — so
        # scaleX(-1) maps it exactly onto itself and the "turns to face the resident" beat was
        # invisible by construction. It existed only in the code. Direction now reads from travel
        # alone, which is honest; leaving an inert wrapper behind would just re-invite the claim.
        f'<g class="peerWrap"><g class="peer">'
        f'<g transform="translate(0 {fmt(ty)}) scale({fmt(s)})" shape-rendering="crispEdges">'
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
        f"</g></g></g>"
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
    star="#dfe8f6",
    star_cool="#c3d6f7",
    star_warm="#fff0dd",
    grain=0.055,
    moon="#f2ead8",
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
    star="#f6f9ff",
    star_cool="#e6efff",
    star_warm="#fff6e6",
    grain=0.030,
    moon="#ffd79a",
    moon_halo="#ffd79a",
    cloud=[
        ("#f4f8fd", "#fdfcfa", "#dae6f2"),
        ("#f8fbfe", "#fefdfb", "#dfe9f4"),
        ("#fcfdff", "#fffefc", "#e4edf6"),
    ],
    mound=["#c6c8c0", "#adafa2"],
    tuft="#a8a99c",
    fg="#8d8e80",
    vignette=0.10,
)

# v6b was `dark=NIGHT, light=DAY` — the SAME two Theme objects as v6a, so it was a re-skin rather
# than a candidate: measured 6.92% pairwise RMSE in light and 7.91% in dark, the tightest pair in
# BOTH schemes. The lead read that as a light-scheme convergence, but the measurement locates it
# elsewhere: v6d has its own light palette and is as distinct in day as in night. What was actually
# wrong is that two of the four candidates were one candidate.
#
# "Two Sessions" is about a meeting, so it gets a quieter, hazier night — moonlight through humidity,
# lower star contrast, warmer air — and an overcast morning rather than a clear midday.
HAZE = Theme(
    sky_top="#0a0d18",
    sky_mid="#141a2c",
    sky_low="#26293c",
    glow="#6b6480",
    glow_op=0.52,
    ground_top="#242a3d",
    ground_bot="#141826",
    rule="#6f7385",
    wm="#f2f0f6",
    sub="#9b98a8",
    star="#e6e2ec",
    star_cool="#cdd4ef",
    star_warm="#ffeeda",
    grain=0.075,
    moon="#f6ecd8",
    moon_halo="#f6ecd8",
    cloud=[
        ("#1a2033", "#2a3048", "#141a2a"),
        ("#1f2639", "#333a52", "#181e2f"),
        ("#252c40", "#3d445c", "#1d2334"),
    ],
    mound=["#232a3e", "#161b29"],
    tuft="#3c4360",
    fg="#0b0e17",
    vignette=0.36,
)

OVERCAST = Theme(
    sky_top="#c4ccd6",
    sky_mid="#d8dee5",
    sky_low="#e9ebec",
    glow="#f0eae0",
    glow_op=0.40,
    ground_top="#dcdcd6",
    ground_bot="#c6c7c0",
    rule="#96999b",
    wm="#171c22",
    sub="#5f666e",
    star="#f8fafc",
    star_cool="#eef2fa",
    star_warm="#fdf8f0",
    grain=0.034,
    moon="#eae4d6",
    moon_halo="#eae4d6",
    cloud=[
        ("#e6eaee", "#f4f6f8", "#d2d8de"),
        ("#ecf0f3", "#f8fafb", "#d9dfe4"),
        ("#f1f4f6", "#fbfcfd", "#dee4e8"),
    ],
    mound=["#c2c4bd", "#adafa8"],
    tuft="#9fa29a",
    fg="#8b8e86",
    vignette=0.14,
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
    star="#f7e6d6",
    star_cool="#d9dcf5",
    star_warm="#ffe2c2",
    grain=0.060,
    moon="#fbe6cc",
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
    star="#fbf7f2",
    star_cool="#e8eeff",
    star_warm="#fff2e0",
    grain=0.032,
    moon="#ffcf94",
    moon_halo="#ffcf94",
    cloud=[
        ("#f7f1fb", "#fefaf6", "#e2dced"),
        ("#fbf3f2", "#fffaf4", "#eadfe0"),
        ("#fff7f0", "#fffbf5", "#f0e2d4"),
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
    star="#d3e8df",
    star_cool="#bcdcea",
    star_warm="#f2ecd8",
    grain=0.050,
    moon="#e6efe6",
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
    star="#f7fbf9",
    star_cool="#e4f0f6",
    star_warm="#fdf5e4",
    grain=0.028,
    moon="#f0e6c8",
    moon_halo="#f0e6c8",
    cloud=[
        ("#eff6f2", "#fdfefb", "#d8e4de"),
        ("#f4f9f6", "#fdfefc", "#dde8e2"),
        ("#f9fbfa", "#fefffd", "#e2ece6"),
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
        clawd_scale=1.2,
        clawd_x=628,
        star_count=(300, 90, 30),
        moon=(1656, 166, 62),
        moon_phase=0.30,
        events=("peek",),
    ),
    Art(
        key="v6b-two-sessions",
        title="Two Sessions",
        blurb=(
            "The same night, but once per loop a second session walks in from the right, the two "
            "meet, both throw their arms up, and the newcomer carries on — the title happening "
            "rather than being described."
        ),
        dark=HAZE,
        light=OVERCAST,
        clawd_scale=1.2,
        clawd_x=560,
        star_count=(280, 84, 28),
        moon=(1672, 178, 56),
        moon_phase=0.30,
        events=(),
        second_clawd=True,
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
        clawd_scale=1.2,
        clawd_x=1096,
        star_count=(220, 62, 20),
        moon=(250, 214, 70),
        moon_phase=0.30,
        events=("peek",),
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
        clawd_scale=1.2,
        clawd_x=812,
        star_count=(240, 70, 22),
        moon=(1706, 140, 50),
        moon_phase=0.34,
        events=("peek",),
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
