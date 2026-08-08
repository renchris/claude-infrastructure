#!/usr/bin/env python3
"""Generate the self-recycle section banner: clawd, in a BMO costume, changing its own battery.

The subject is `handoff-fire.sh --recycle` — the one operation where a session is its own
successor. The clip it quotes is the seven-second Adventure Time loop of BMO swapping its own
batteries, which is the same act: the machine pulls its own power, goes dark, and comes back up
in place. Nobody hands it a new battery.

WHAT IS ENFORCED HERE rather than trusted to hand-typing:

  * P = 7 s master period — the source clip's length — and every sub-period is CHECKED to divide
    it. The SVG and the rendered video are then the same loop, so the video cannot seam where the
    vector does not.
  * THE LOOP CLOSES BY CONSTRUCTION. Every track declares its keyframes as (t, value) pairs, and
    `Track` refuses to emit unless the value at t=0 is identical to the value at t=P. A banner
    whose last frame differs from its first is a banner with a visible hitch once every loop, and
    that is the defect a 7-second loop cannot hide.
  * NO VISIBLE SNAP. A cycle needs things to return, but a battery swap does not return anything:
    the spent cell ends in the bin and the fresh one ends in the socket. So each travelling cell
    is teleported back to its start — and `assert_snaps_invisible` refuses to emit unless the
    element's own opacity gate reads 0 at the instant it jumps. The reset is not hidden by luck.
  * POWER IS ONE FACT. The face, the mouth, the eyes and the light it throws on the ground are all
    derived from ONE window, POWER_OFF, which is itself derived from the battery's unseat/seat
    beats. A screen that stays lit with no cell in the socket is the whole joke inverted, so it is
    a build error rather than something to notice in review.
  * THE COSTUME IS A COSTUME. clawd is never redrawn as BMO. The shell is a separate object laid
    over the canonical 11x8 sprite: the body's own orange shows above and beside it, the arms and
    feet are bare, and clawd's real eyes are what appear on BMO's screen. `assert_costume_reveals`
    checks the orange margins are still there, because a shell that grew to cover them would
    quietly turn a Halloween costume into a different character.

Art direction is inherited from the v6c hero (`gen.DUSK` / `gen.DAWN`) and the scenery is drawn by
gen.py's own helpers, so the two banners cannot drift apart in palette or texture. gen.py is NOT
edited by this file — see `assert_gen_contract` for how the coupling fails loudly instead.

    python3 tools/banner/recycle.py --out assets/banner
"""

from __future__ import annotations

import argparse
import random
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen  # noqa: E402  — the hero generator, imported for its palette and its scenery

# ── canvas ────────────────────────────────────────────────────────────────────────────────────────
# 4:1. The hero is 1920x600 because it carries a 62 px wordmark; a section banner carries a command
# line, so the frame is shorter and the creature is nearly twice the size — the source clip is a
# medium close-up and the battery has to be legible at the 900 px the README renders it at.
W, H = 1920, 480
GROUND = 372
P = 7.0  # master period, seconds — the length of the clip being quoted

S = 2.0  # sprite scale: 11x8 cells of 20 px -> 440x320
CELL = gen.CELL * S  # 40 px per grid cell on canvas
CX = 430.0  # sprite origin x
CY = GROUND - gen.SPRITE_H * S  # 52 — grounded by computation, never by eye

# The caption's exclusion zone: stars are generated against it, so "no star behind the type" is a
# property of the generator (gen.starfield reads gen.KEEPOUT).
CAPTION_X = 1100.0
KEEPOUT = (1080, 128, 1806, 302)


def gx(col: float) -> float:
    return CX + col * CELL


def gy(row: float) -> float:
    return CY + row * CELL


# ── the beat sheet ────────────────────────────────────────────────────────────────────────────────
# The source clip's shot list, in seconds. Everything downstream is derived from these names, so a
# re-time is one edit here and never a hunt through percentages.
#
#   0.00  seated, screen lit, one slow blink
#   1.05  the right arm reaches behind — the shell's edge wipes it away
#   1.55  nothing but a creature with one arm, working out of sight
#   2.35  the cell has left the socket        <- THE FACE DIES HERE, before you see why
#   2.62  the hand comes back out holding a spent grey cell
#   3.00  it is carried to the crate and dropped in
#   3.40  the left arm dips into the charger; a fresh orange cell rises out
#   4.20  the cell goes in behind him         <- THE FACE COMES BACK HERE
#   4.20  flicker, then an over-bright boot with a scanline down the glass
#   4.85  the hand comes back out empty
#   5.30  a bigger smile and a two-bounce wiggle
#   6.10  back to idle; at 7.00 the frame is identical to 0.00
T_BLINK1 = (0.85, 0.97)
T_REACH_R = 1.05
T_REACH_IN = 1.55  # the hand is behind the shell from here — see BEHIND_R
T_UNSEAT = 2.35
T_OUT_R = 2.62  # back out, holding the spent cell
T_AT_BIN = 3.00
T_DROPPED = 3.30
T_SPENT_OFF = 3.45
T_SPENT_RESET = 3.60
T_ARM_R_HOME = 3.55
T_REACH_L = 3.40
T_AT_CHARGER = 3.68
T_LIFTED = 3.90
T_OUT_L = 4.02  # lifted clear, held in the open
T_SEAT = 4.20
T_FLICKER_END = 4.52
T_BOOT_PEAK = 4.60
T_SCAN_END = 4.60
T_HELD_IN = 4.85  # the hand stays behind him a moment after seating it
T_BLINK2 = (4.90, 5.08)
T_ARM_L_HOME = 5.20
T_SMILE = (5.30, 6.10)
T_NEW_RESET = 6.30

# The single source of the power state. The face is lit if and only if a cell is seated, so both
# ends of this window are beats of the battery's own travel rather than independent numbers.
POWER_OFF = (T_UNSEAT, T_SEAT)


def assert_beats_ordered() -> None:
    """A beat sheet out of order builds fine and reads as nonsense, so check the causal chain."""
    chain = [
        ("blink1", T_BLINK1[0]),
        ("blink1 end", T_BLINK1[1]),
        ("reach right", T_REACH_R),
        ("hand behind", T_REACH_IN),
        ("unseat", T_UNSEAT),
        ("back out with the spent cell", T_OUT_R),
        ("at bin", T_AT_BIN),
        ("dropped", T_DROPPED),
        ("spent hidden", T_SPENT_OFF),
        ("spent reset", T_SPENT_RESET),
        ("at charger", T_AT_CHARGER),
        ("lifted", T_LIFTED),
        ("held in the open", T_OUT_L),
        ("seat", T_SEAT),
        ("flicker end", T_FLICKER_END),
        ("hand back out", T_HELD_IN),
        ("smile", T_SMILE[0]),
        ("smile end", T_SMILE[1]),
        ("new cell reset", T_NEW_RESET),
    ]
    for (an, at), (bn, bt) in zip(chain, chain[1:]):
        if not at <= bt:
            raise SystemExit(
                f"recycle: beat '{an}' ({at}s) must not follow '{bn}' ({bt}s)"
            )
    if chain[-1][1] >= P:
        raise SystemExit(f"recycle: last beat {chain[-1][1]}s must land inside P={P}s")
    # The reach must not begin before the idle blink has finished, or the creature looks startled
    # into action rather than deciding to act.
    if T_REACH_R < T_BLINK1[1]:
        raise SystemExit("recycle: the reach starts inside the idle blink")
    # Both resets must happen while their cell is hidden AND behind a wall; the opacity half of
    # that is checked by assert_snaps_invisible, the ordering half is checked here.
    if not T_SPENT_OFF <= T_SPENT_RESET:
        raise SystemExit("recycle: the spent cell is reset before it is hidden")
    # The fresh cell's reset teleports it back into the charger. That is only invisible while it is
    # behind the shell, i.e. any time after it was seated — but it must also be after the hand has
    # left, or the reset would happen inside a frame the audience is watching a hand in.
    if not T_HELD_IN <= T_NEW_RESET:
        raise SystemExit(
            "recycle: the fresh cell is reset before the hand has come back out — the reset is "
            "only unobservable once the shell is the only thing over it"
        )


def divides_loop(*periods: float) -> None:
    """A sub-period that does not divide P makes the composite loop at the LCM instead.

    For the vector that is a seam once every LCM seconds. For the RENDERED VIDEO it is worse: the
    file is exactly P long, so a 3 s texture inside a 7 s loop restarts mid-file forever.
    """
    for p in periods:
        q = P / p
        if abs(q - round(q)) > 1e-9:
            raise SystemExit(
                f"recycle: period {p}s does not divide P={P}s (P/p = {q}) — the loop would seam"
            )


def fmt(v: float) -> str:
    return gen.fmt(v)


def pct(t: float) -> str:
    """A keyframe stop as a percentage of the master period."""
    return fmt(round(t / P * 100, 4))


# ── the animation tracks ──────────────────────────────────────────────────────────────────────────
@dataclass
class Track:
    """One element's one animation, authored as (time, declarations) waypoints.

    One animation per element is not a style preference: `banner-shots.sh` reaches a timestamp by
    setting `animation-delay` on every element, and an element carrying two animations renders at
    the wrong phase in every verification frame. So anything needing two motions becomes nested
    groups — which is why the cells here are a `*Gate` (opacity, hard steps) wrapping a `*Path`
    (transform, eased): one property each, one animation each, and the two compose.
    """

    cls: str
    name: str
    keys: list[tuple[float, dict[str, str]]]
    ease: str = "linear"
    period: float = P
    gate: str | None = (
        None  # the opacity track that must read 0 wherever this one snaps
    )

    def __post_init__(self) -> None:
        divides_loop(self.period)
        if len(self.keys) < 2:
            raise SystemExit(
                f"recycle[{self.cls}]: a track needs at least two waypoints"
            )
        ts = [t for t, _ in self.keys]
        if ts != sorted(ts):
            raise SystemExit(
                f"recycle[{self.cls}]: waypoints are not in time order: {ts}"
            )
        # Two waypoints at one time is NOT an instant jump — CSS merges keyframes that share a
        # percentage, the later declaration winning, so the pair silently becomes a slow glide from
        # the previous waypoint to the LAST of the two. That mistake shipped a battery drifting
        # across open ground for 2.1 s and a scanline that never moved (see
        # assert_return_travel_is_invisible). There is no legitimate use of it here: an invisible
        # return leg does not need to be instant, it just needs to be invisible.
        pcts = [pct(t) for t in ts]
        dupes = {p for p in pcts if pcts.count(p) > 1}
        if dupes:
            raise SystemExit(
                f"recycle[{self.cls}]: waypoints collide at {sorted(dupes)}% — CSS merges "
                f"same-percentage keyframes, so this reads as a glide, not a jump. Hold the value "
                f"until the gate closes and glide back inside the invisible window instead."
            )
        if ts[0] != 0 or abs(ts[-1] - self.period) > 1e-9:
            raise SystemExit(
                f"recycle[{self.cls}]: waypoints must span 0..{self.period}s exactly, got "
                f"{ts[0]}..{ts[-1]}"
            )
        props = {frozenset(d) for _, d in self.keys}
        if len(props) != 1:
            raise SystemExit(
                f"recycle[{self.cls}]: every waypoint must declare the SAME properties, else the "
                f"missing ones interpolate from the element's base value instead of from the "
                f"previous keyframe — got {[sorted(p) for p in props]}"
            )
        # THE LOOP CONTRACT. Not 'looks continuous' — identical.
        if self.keys[0][1] != self.keys[-1][1]:
            raise SystemExit(
                f"recycle[{self.cls}]: the loop does not close — t=0 is {self.keys[0][1]} but "
                f"t={self.period} is {self.keys[-1][1]}. Every P seconds the banner would jump."
            )

    def moves(self) -> list[tuple[float, float]]:
        """The time spans over which this track's value actually changes."""
        return [
            (ta, tb) for (ta, va), (tb, vb) in zip(self.keys, self.keys[1:]) if va != vb
        ]

    def value_at(self, t: float) -> dict[str, str]:
        """The value a steps(1,end) track holds at t — used to check gates at snap times."""
        held = self.keys[0][1]
        for kt, kv in self.keys:
            if kt <= t + 1e-9:
                held = kv
            else:
                break
        return held

    def css(self) -> str:
        frames = []
        for t, decl in self.keys:
            body = ";".join(f"{k}:{v}" for k, v in decl.items())
            frames.append(f"{pct(t)}%{{{body}}}")
        return (
            f"@keyframes {self.name}{{{''.join(frames)}}}"
            f".{self.cls}{{animation:{self.name} {fmt(self.period)}s {self.ease} infinite}}"
        )


def assert_return_travel_is_invisible(tracks: dict[str, Track]) -> None:
    """A gated track may only CHANGE VALUE while its gate reads zero.

    The swap is not a cycle — the spent cell ends in the crate and the fresh one in the socket — so
    each has to get back to its start before the wrap, travelling a path that is not part of the
    story. That is legitimate exactly while it cannot be seen.

    THIS CHECK REPLACES A WEAKER ONE THAT PASSED OVER A REAL DEFECT, and the reason is worth keeping.
    The first version wrote a teleport as two keyframes at the SAME percentage and then verified the
    gate at that instant. Both halves were wrong. CSS MERGES keyframes that share a percentage — the
    later declaration simply overrides the earlier — so the pair never produced a jump at all; it
    turned the whole preceding segment into a slow glide toward the reset position. And checking the
    gate only AT the snap said nothing about that segment, where the gate was still 1. Rendered
    output: the fresh cell drifting across open ground for 2.1 s of every 7 s loop, the spent cell
    flying back out of the crate, and the boot scanline — whose two same-percentage keys merged into
    a no-op — never moving at all. Three defects, one cause, and every other gate in the file was
    green. So: duplicate percentages are rejected outright (see __post_init__), the return leg is an
    ordinary eased glide, and what is asserted is the INTERVAL, not the instant.
    """
    for tr in tracks.values():
        if tr.gate is None:
            continue
        g = tracks.get(tr.gate)
        if g is None:
            raise SystemExit(
                f"recycle[{tr.cls}]: gate '{tr.gate}' is not a declared track"
            )
        if "steps" not in g.ease:
            raise SystemExit(
                f"recycle[{tr.cls}]: gate '{g.cls}' is eased ({g.ease}), so it holds intermediate "
                f"opacities and 'invisible' cannot be decided from its waypoints. Gates must step."
            )
        # Motion in the MIDDLE of a gated track is the story — a cell being drawn out and carried is
        # exactly what belongs on camera. What must be invisible is only the RETURN LEG: everything
        # after the last waypoint that still differs from the t=0 value, since from there the track
        # is doing nothing but getting home in time for the wrap.
        home = tr.keys[0][1]
        away = [t for t, v in tr.keys if v != home]
        if not away:
            continue
        t_last = max(away)
        probes = [t_last] + [t for t, _ in g.keys if t_last < t <= tr.period]
        for t in probes:
            if g.value_at(t).get("opacity") != "0":
                raise SystemExit(
                    f"recycle[{tr.cls}]: its return leg runs {t_last}s..{fmt(tr.period)}s, but the "
                    f"gate '{g.cls}' still reads opacity:{g.value_at(t).get('opacity')} at t={t}s. "
                    f"The journey home is not part of the story and must not be seen — close the "
                    f"gate no later than {t_last}s."
                )


def assert_power_is_one_fact(tracks: dict[str, Track]) -> None:
    """Everything the battery powers must go dark for EXACTLY the window it is unseated.

    The screen, the eyes, the mouth and the light thrown on the ground are four elements telling
    one story. Authored independently they drift by a beat and the creature keeps smiling with its
    power supply in its hand — which reads as a rendering bug, not as a joke.
    """
    t0, t1 = POWER_OFF
    recover_max = 0.25  # s — how long after the cell seats the light may take to arrive
    for cls in ("screenLit", "eyesOpen", "mouth", "spill"):
        tr = tracks[cls]
        at = {round(t, 6): d["opacity"] for t, d in tr.keys}
        # The two edges must be BEATS of this track, not values it happens to pass through: an
        # eased track without a waypoint on the unseat instant fades out across it instead.
        for edge in (t0, t1):
            if round(edge, 6) not in at:
                raise SystemExit(
                    f"recycle[{cls}]: has no waypoint at t={edge}s. Both edges of the power "
                    f"window must be waypoints of everything the battery powers, or the cut "
                    f"drifts off the swap by however long the neighbouring segment lasts."
                )
        if at[round(t0, 6)] != "0":
            raise SystemExit(
                f"recycle[{cls}]: holds opacity:{at[round(t0, 6)]} at the instant the cell "
                f"leaves the socket. The face is lit if and only if a battery is seated."
            )
        # Dark across the whole interior, whatever the easing: an interior waypoint above zero
        # would interpolate light into a window with no power source.
        inner = [(t, v) for t, v in at.items() if t0 < t < t1 and v != "0"]
        if inner:
            raise SystemExit(
                f"recycle[{cls}]: is lit inside the dark window at {inner}"
            )
        # Lit before the cut, and back promptly after it. A hard-stepped element recovers ON the
        # seat beat; an eased one is allowed to ramp, but only within recover_max.
        before = [v for t, v in at.items() if t < t0]
        if not before or before[-1] == "0":
            raise SystemExit(
                f"recycle[{cls}]: is already dark before the cell is unseated"
            )
        if at[round(t1, 6)] == "0":
            after = [(t, v) for t, v in sorted(at.items()) if t > t1]
            if not after or after[0][1] == "0" or after[0][0] > t1 + recover_max:
                raise SystemExit(
                    f"recycle[{cls}]: does not come back within {recover_max}s of the cell "
                    f"seating — the power cut is wider than the swap"
                )


def assert_one_animation_each(css_text: str) -> None:
    """Fail before `banner-shots.sh --lint` does, and for the same reason it would.

    A top-level comma in an `animation` value means two animations on one element, and the
    harness's freeze collapses their delays — so every verification frame would be quietly wrong.

    Only TOP-LEVEL commas count. `steps(1,end)` and `cubic-bezier(.34,.06,.4,1)` are single
    animations with a comma inside their timing function; a check that tests the raw value for ','
    false-fails every eased or stepped animation, which is nearly all of them. This is the same
    rule as `banner-shots.sh --lint` on purpose — two checks of one property that disagree let the
    build pass what the harness rejects.
    """

    def top_level_commas(value: str) -> int:
        depth = n = 0
        for ch in value:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth = max(0, depth - 1)
            elif ch == "," and depth == 0:
                n += 1
        return n

    bad = [
        m.group(0)
        for m in re.finditer(r"animation:[^;{}\"']+", css_text)
        if top_level_commas(m.group(0))
    ]
    if bad:
        raise SystemExit(
            f"recycle: {len(bad)} element(s) carry two animations: {bad[:3]}"
        )
    for m in re.finditer(r"animation:\s*\S+\s+([\d.]+)s", css_text):
        divides_loop(float(m.group(1)))


# ── the BMO costume ───────────────────────────────────────────────────────────────────────────────
# A Halloween costume, so it is built as an object laid ON the canonical sprite rather than as a
# redraw of it. Everything is in sprite-grid columns/rows, which is what keeps it registered to
# clawd's own geometry: the shell is inset from the body, the screen is wide enough that clawd's
# real eye holes (cols 2-3 and 8-9 of row 3) sit inside it with a margin, and BMO's mouth is
# painted on the glass BETWEEN those eyes. The dots on the screen are clawd's actual eyes; they
# blink on clawd's own clock. That is the whole gag, and it is why the eyes are not moved.
# The shell starts at row 2.2, not at the top of the body, and that number is the whole costume.
# At row 1.5 it left a 20 px orange line above the screen and the result read as a teal robot with
# orange trim: the creature had disappeared into the outfit. Dropping the shell 0.7 of a cell frees
# a 48 px band of clawd's own head above it — enough, at the 900 px the README renders this at, for
# the orange to read as a body wearing a console rather than as a border around one.
SHELL = (1.25, 2.2, 9.75, 7.0)  # col0, row0, col1, row1
SCREEN = (1.6, 2.6, 9.4, 5.0)
BEZEL_PAD = 0.2
STRAP_COLS = (2.15, 8.1)  # the two elastics crossing the bare head — see `costume`
STRAP_W = 0.45

TEAL = "#4bb3a1"  # BMO's body
TEAL_HI = "#79cdbd"  # top bevel
TEAL_LO = "#2f7d6f"  # bezel / outline
TEAL_DK = "#1a534b"  # seams and the shell's own outline
SCREEN_LIT = "#a9e8d6"
SCREEN_BOOT = "#e6fff6"
SCREEN_DEAD = "#22322f"
FACE_INK = "#123330"  # the mouth, and the eye holes while the costume is on
BRASS = "#caa15e"
STRAP = "#2b1b14"  # the same near-black the sprite uses for its own sleeping lids
CELL_LIVE = gen.CLAWD  # a live cell is Claude orange. A spent one is not.
CELL_LIVE_HI = "#eda184"
CELL_SPENT = "#6a6068"
CELL_SPENT_HI = "#8b8290"
# The crates were invisible at #241a26 — the same value as the ground they sit on. These are lifted
# until they read as objects in this light, with a warm rim on the side facing the horizon glow.
BIN_BODY = "#33253a"
BIN_FRONT = "#1b1322"
BIN_EDGE = "#5b4466"
BIN_RIM = "#8a5f52"
LED = "#7dd6a0"

# Every cell element shares one rect and differs only by its transform, so 'seated' is
# translate(0,0) for all three and each loop-close check is a comparison of transforms.
#
# THE COMPARTMENT IS ON THE BACK, AND IS NEVER DRAWN — which is what the source clip does. BMO
# reaches behind itself; the audience never sees the hatch, only a hand going back and a battery
# coming out. That is also the only arrangement that works here, and the reason is arithmetic:
# clawd's arm is a single 80 px stub whose hand is its lower end, so a hand at height y puts the
# arm's top at y-80, and any grab point on the shell's front therefore drags the arm across its own
# screen. Two front-mounted designs were built and both failed on that. A chest hatch put an orange
# bar between the eyes; clipping the arm to the glass's complement removed the bar and left a
# DETACHED orange blob sitting on the door. Moving the hatch into the base cleared the face but the
# assembly — plinth, sliding cover, dark cavity, wide arm — read as clutter at 900 px, and the cover
# once removed sat on top of the buttons.
#
# Reaching behind removes the whole problem: the ARMS ARE DRAWN BEHIND THE SHELL (see `build`'s
# z-order), so an arm moving inboard is progressively occluded by the shell's own edge and simply
# goes away, which is what reaching behind yourself looks like. Nothing can ever cover the face,
# by construction rather than by tuning. The cost is that the mechanism is off-screen, so the CELLS
# carry the story instead — held out in clear air against the sky, with a charger and a crate of
# spent ones either side to say what is happening.
#
# `BAT` is therefore the cell's SEATED position: behind the shell, invisible. translate(0,0) is
# 'in the socket' for all three cells, exactly as before, so the loop-close checks are unchanged.
BAT = (gx(5.75), gy(4.7), 2.2 * CELL, 0.75 * CELL)
# A seam and two screws on the shell's right edge: the only hint that there is a panel at all.
SEAM_COL = 9.45
# Where a cell sits while a hand holds it out, clear of the body on that side. Every hand target is
# derived from these two, so a hand can never drift off the thing it is supposed to be carrying.
SPENT_OUT = (202.0, 48.0)
NEW_OUT = (-306.0, 48.0)

# The two containers: a charger on the left, a crate of spent cells on the right. Their FRONT WALLS
# are the reason this loop needs no fade — a cell parked behind one is occluded, not faded — so the
# parked positions are DERIVED from the containers below rather than typed, and then checked against
# the walls by assert_parked_cells_hidden.
CHARGER = (298.0, 296.0, 112.0, 76.0)  # x, y, w, h
BIN = (898.0, 296.0, 112.0, 76.0)
WALL_TOP = 336.0  # both front walls start here


def park(box: tuple[float, float, float, float]) -> tuple[float, float]:
    """The translate that stands the cell centred on a container's floor, out of sight."""
    bx, by, bw, bh = box
    return (bx + (bw - BAT[2]) / 2 - BAT[0], by + bh - BAT[3] - 2 - BAT[1])


PARK_NEW = park(CHARGER)
PARK_SPENT = park(BIN)
LIFT_NEW = (PARK_NEW[0], PARK_NEW[1] - 48)  # risen clear of the charger's wall
BIN_MOUTH = (PARK_SPENT[0], PARK_SPENT[1] - 26)  # held at the crate's mouth, half in


def assert_costume_reveals() -> None:
    """The body's own orange must still show above and beside the shell.

    This is the single cue that separates 'clawd in a costume' from 'a teal robot': a shell grown
    to the body's edges is a redraw. The floor is MEASURED, not chosen — at 20 px of head the first
    render read as trim on a teal robot, and 48 px is what made the orange read as a body again. The
    threshold sits between the two so the failure that was actually seen cannot come back.
    """
    top_strip = (SHELL[1] - 1.0) * CELL  # body starts at row 1
    side = (SHELL[0] - 1.0) * CELL
    if top_strip < 32 or side < 8:
        raise SystemExit(
            f"recycle: the costume covers clawd — only {top_strip:.0f}px of body shows above the "
            f"shell and {side:.0f}px at the sides. It stops reading as a costume."
        )
    # clawd's real eyes must sit inside the screen with room to spare, or the gag is a cropped eye.
    for col in (2.0, 9.0):
        if not (SCREEN[0] + 0.3 <= col <= SCREEN[2] - 0.3):
            raise SystemExit(
                f"recycle: clawd's eye column {col} is not comfortably inside the screen "
                f"{SCREEN[0]}..{SCREEN[2]} — the eyes ARE the face on the screen"
            )


def assert_parked_cells_hidden() -> None:
    """Each cell, parked, must be fully inside the volume its container's front wall covers."""
    for label, (dx, dy), box in (
        ("fresh cell / charger", PARK_NEW, CHARGER),
        ("spent cell / bin", PARK_SPENT, BIN),
    ):
        x0, y0 = BAT[0] + dx, BAT[1] + dy
        x1, y1 = x0 + BAT[2], y0 + BAT[3]
        bx, _by, bw, _bh = box
        wall = (bx, WALL_TOP, bx + bw, box[1] + box[3])
        if not (x0 >= wall[0] and x1 <= wall[2] and y0 >= wall[1] and y1 <= wall[3]):
            raise SystemExit(
                f"recycle: parked {label} at ({x0:.0f},{y0:.0f})-({x1:.0f},{y1:.0f}) is not "
                f"covered by the front wall {wall} — its reset would be visible"
            )


def assert_arm_poses_are_whole(trs: dict[str, Track]) -> None:
    """Every HELD arm pose must be entirely behind the shell, or entirely clear of it.

    The arms are drawn before the shell, so the shell occludes them — which is what makes reaching
    behind read as reaching behind. A pose landing half in and half out is the failure mode: it
    renders as a severed orange stub poking out from under the console, which is exactly what a
    clipped chest-mounted arm produced.

    Paths BETWEEN poses are deliberately not checked. An arm sliding across the shell's edge,
    progressively occluded, is the motion itself — checking the path would forbid the animation.
    """
    sx0, sy0, sx1, sy1 = body_box()
    for side in ("L", "R"):
        for t, decl in trs[f"arm{side}"].keys:
            m = re.fullmatch(
                r"translate\((-?[\d.]+)px,(-?[\d.]+)px\)", decl["transform"]
            )
            if not m:
                raise SystemExit(f"recycle[arm{side}]: unparseable transform {decl}")
            x0, y0, x1, y1 = arm_rect(side, float(m.group(1)), float(m.group(2)))
            inside = x0 >= sx0 and x1 <= sx1 and y0 >= sy0 and y1 <= sy1
            clear = x1 <= sx0 or x0 >= sx1 or y1 <= sy0 or y0 >= sy1
            if not (inside or clear):
                raise SystemExit(
                    f"recycle[arm{side}]: the pose at t={t}s straddles the shell's edge — arm at "
                    f"({x0:.0f},{y0:.0f})-({x1:.0f},{y1:.0f}) against shell "
                    f"({sx0:.0f},{sy0:.0f})-({sx1:.0f},{sy1:.0f}). It renders as a severed stub: "
                    f"move the hand target fully inside the body (a reach) or fully outside it."
                )


def assert_caption_clear() -> None:
    """The creature, its two containers and the caption must not overlap.

    The hero enforces this against a scrolling world, where only a Y-band exclusion is sound.
    Nothing here scrolls, so the honest check is the literal one: boxes, in canvas space.
    """
    sprite = (gx(0), gy(1), gx(11), GROUND)
    for name, box in (
        ("creature", sprite),
        (
            "charger",
            (CHARGER[0], CHARGER[1], CHARGER[0] + CHARGER[2], CHARGER[1] + CHARGER[3]),
        ),
        ("bin", (BIN[0], BIN[1], BIN[0] + BIN[2], BIN[1] + BIN[3])),
    ):
        if (
            box[0] < KEEPOUT[2]
            and box[2] > KEEPOUT[0]
            and box[1] < KEEPOUT[3]
            and box[3] > KEEPOUT[1]
        ):
            raise SystemExit(
                f"recycle: the {name} overlaps the caption keep-out {KEEPOUT}"
            )


def assert_text_fits(items: list[tuple[str, float, float]]) -> None:
    """Monospace advance is 0.6em in every face of the stack, so the width is computable.

    An overflowing caption is not a soft failure: it is clipped by the viewBox on the right-hand
    side, where the frame edge makes it look deliberate.
    """
    for s, size, track in items:
        wpx = len(s) * size * 0.6 + max(0, len(s) - 1) * track
        if CAPTION_X + wpx > W - 40:
            raise SystemExit(
                f"recycle: caption line {s!r} is {wpx:.0f}px wide and would reach "
                f"{CAPTION_X + wpx:.0f}px, past the {W - 40}px right margin"
            )


# ── the sprite, wearing the costume ───────────────────────────────────────────────────────────────
def r(
    x: float,
    y: float,
    w: float,
    h: float,
    fill: str = "",
    cls: str = "",
    extra: str = "",
) -> str:
    f = f' fill="{fill}"' if fill else ""
    c = f' class="{cls}"' if cls else ""
    return f'<rect{c} x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}"{f}{extra}/>'


def creature_body() -> str:
    """clawd, seated: the canonical sprite with everything dropped one row and the legs shortened.

    The legs keep their four shipped COLUMNS — 1, 3, 7 and 9 — because that spacing is as much of
    the creature's signature as the eyes are. Only their height changes, two cells to one, which is
    what sitting down looks like on this grid. Two wide feet were tried instead and read as orange
    corner brackets on a console: the four-column rhythm was gone, and with it the character.
    """
    o = gen.CLAWD
    return "".join(r(gx(k), gy(7.0), CELL, CELL, o) for k in (1, 3, 7, 9)) + r(
        gx(1), gy(1), 9 * CELL, 6 * CELL, o
    )


def costume() -> str:
    """The shell: a console front strapped over clawd's body."""
    sc0, sr0, sc1, sr1 = SHELL
    x, y, w, h = gx(sc0), gy(sr0), (sc1 - sc0) * CELL, (sr1 - sr0) * CELL
    ec0, er0, ec1, er1 = SCREEN
    sx, sy = gx(ec0), gy(er0)
    sw, sh = (ec1 - ec0) * CELL, (er1 - er0) * CELL
    bp = BEZEL_PAD * CELL

    out = [
        # THE STRAPS, drawn on the bare head BEFORE the shell, so the shell's top edge covers where
        # they end. Two elastics over the head is the cue every kid-in-a-cardboard-box costume has,
        # and it is the difference between 'wearing' and 'being'.
        # They stop 0.35 of a cell BELOW the top of the head. Run to the very edge and they read as
        # two antennae sprouting out of it, which is the first thing the render showed.
        r(gx(STRAP_COLS[0]), gy(1.35), STRAP_W * CELL, (sr0 - 1.35) * CELL, STRAP),
        r(gx(STRAP_COLS[1]), gy(1.35), STRAP_W * CELL, (sr0 - 1.35) * CELL, STRAP),
        # a shadow cast by the shell onto the body it hangs off — the shell sits PROUD of clawd
        r(x, y - 0.1 * CELL, w, 0.1 * CELL, "#8a4a35", extra=' opacity=".55"'),
        # the shell itself: a dark outline all round so it separates from the orange underneath,
        # then a lit top bevel, then a shaded bottom lip
        r(x - 2, y - 2, w + 4, h + 4, TEAL_DK),
        r(x, y, w, h, TEAL),
        r(x, y, w, 0.14 * CELL, TEAL_HI),
        r(x, y + h - 0.12 * CELL, w, 0.12 * CELL, TEAL_LO),
        # bezel, then the dead glass. The lit panel is a separate element on top of it, so the
        # screen going out is one opacity gate rather than a fill animation.
        r(sx - bp, sy - bp, sw + 2 * bp, sh + 2 * bp, TEAL_LO),
        r(sx, sy, sw, sh, SCREEN_DEAD),
        f'<g class="screenLit" opacity="1">{r(sx, sy, sw, sh, SCREEN_LIT)}</g>',
        f'<g class="screenBoot" opacity="0">{r(sx, sy, sw, sh, SCREEN_BOOT)}</g>',
    ]
    # the boot scanline: one bright band crossing the glass once, clipped to it
    band = r(sx, sy - 0.5 * CELL, sw, 0.34 * CELL, "#ffffff", extra=' opacity=".5"')
    out.append(
        f'<g clip-path="url(#glass)"><g class="scanGate" opacity="0">'
        f'<g class="scanPath">{band}</g></g></g>'
    )

    # clawd's own eyes, showing through the glass — the face on the screen IS the creature.
    ey = gy(3.0)
    eyes_open = r(gx(2.0), ey, CELL, CELL, FACE_INK) + r(
        gx(8.0), ey, CELL, CELL, FACE_INK
    )
    lid = ey + CELL * 0.62
    eyes_shut = r(gx(2.0), lid, CELL, CELL * 0.24, FACE_INK) + r(
        gx(8.0), lid, CELL, CELL * 0.24, FACE_INK
    )
    # The eye band glances DOWN at what the hands are doing, then back. The shipped pose table only
    # moves the band left and right, and this is the same move on the other axis — the band as a
    # unit, never one eye — which is what keeps the creature deliberate rather than merely animated.
    out.append(
        f'<g class="look">'
        f'<g class="eyesOpen" opacity="1">{eyes_open}</g>'
        f'<g class="eyesShut" opacity="0">{eyes_shut}</g>'
        f"</g>"
    )

    # BMO's mouth, painted on the glass between the eyes. A pixel smile: a flat bar with its two
    # ends lifted — never a curve, which at this quantisation samples to grey mud. Both smiles share
    # one baseline, so the content beat is a change of WIDTH and of how far the corners lift, which
    # is legible at 900 px in a way that a redrawn curve is not.
    u = CELL * 0.25
    mx, my = gx(5.5), gy(4.5)

    def smile(halfw: float, capup: float) -> str:
        return (
            r(mx - halfw, my, 2 * halfw, u, FACE_INK)
            + r(mx - halfw - u, my - capup, u, capup, FACE_INK)
            + r(mx + halfw, my - capup, u, capup, FACE_INK)
        )

    out.append(f'<g class="mouth" opacity="1">{smile(1.0 * CELL, u)}</g>')
    out.append(f'<g class="mouthBig" opacity="0">{smile(1.6 * CELL, 1.8 * u)}</g>')

    # A PERMANENT sheen on the glass — the one thing on the screen that is not animated. Without it
    # the powered-down face is a flat dark rectangle, which reads as a hole cut in the costume; with
    # it, 'off' still reads as a screen, which is the entire point of the beat.
    out.append(
        f'<g clip-path="url(#glass)">'
        f'<path d="M{fmt(sx)} {fmt(sy + sh)} L{fmt(sx + sw * 0.42)} {fmt(sy)} '
        f'L{fmt(sx + sw * 0.60)} {fmt(sy)} L{fmt(sx + sw * 0.18)} {fmt(sy + sh)} Z" '
        f'fill="#ffffff" opacity=".055"/></g>'
    )

    # the control deck: D-pad left, two buttons and a speaker slot right, the hatch centre
    dpx, dpy = gx(2.6), gy(6.0)
    out += [
        r(dpx - 0.7 * CELL, dpy - 0.25 * CELL, 1.4 * CELL, 0.5 * CELL, TEAL_DK),
        r(dpx - 0.25 * CELL, dpy - 0.7 * CELL, 0.5 * CELL, 1.4 * CELL, TEAL_DK),
        f'<circle cx="{fmt(gx(8.2))}" cy="{fmt(gy(5.75))}" r="13" fill="#d9534f"/>',
        f'<circle cx="{fmt(gx(9.05))}" cy="{fmt(gy(6.45))}" r="13" fill="#4a7fd0"/>',
        r(gx(8.05), gy(6.75), 1.55 * CELL, 0.2 * CELL, BRASS, extra=' opacity=".75"'),
        # the panel seam and its two screws, on the edge the hands disappear behind
        r(
            gx(SEAM_COL),
            gy(2.5),
            0.06 * CELL,
            4.3 * CELL,
            TEAL_DK,
            extra=' opacity=".8"',
        ),
        r(gx(SEAM_COL) - 5, gy(2.75), 4, 4, TEAL_DK),
        r(gx(SEAM_COL) - 5, gy(6.55), 4, 4, TEAL_DK),
    ]
    return "".join(out)


def body_box() -> tuple[float, float, float, float]:
    """The silhouette an arm vanishes behind.

    It is the BODY, not the shell: clawd's own body runs columns 1-10 while the costume is inset to
    1.25-9.75, so the body is the wider of the two and therefore the real occluder. Using the shell
    here would reject poses that are in fact perfectly hidden — behind the strip of orange between
    the shell's edge and the body's.
    """
    return (gx(1), gy(1), gx(10), gy(7))


def battery(live: bool) -> str:
    """One cell, reading as CHARGED or FLAT at a glance — the 🔋 / 🪫 distinction.

    Colour alone did not carry it. The first version differed only in hue, orange for live and grey
    for spent, and the operator's read was right: "they just look like blocks". Hue says WHICH cell,
    never HOW FULL — and at the 900 px this renders at, a 41x14 px block of any colour is a block.

    So the cell states itself twice, in two independent channels:

      * CHARGE SEGMENTS — three bars inside the casing, the way every battery icon ever drawn does
        it: filled and bright when live, hollow dark slots when spent. This is the channel that
        survives being small, because it changes the cell's INTERNAL STRUCTURE rather than its
        colour, and it borrows a convention the reader already knows from a phone status bar.
      * The casing and terminal — still orange or grey, and the live terminal is longer, so the
        silhouettes differ even in a thumbnail where the segments blur.

    The dark outline is not decoration either. A live cell is exactly the same orange as the arm
    carrying it, so without it the hand and the battery merge into one orange blob at the two moments
    the beat depends on being read: lifting the dead one out, and pushing the fresh one home.
    """
    x, y, w, h = BAT
    body, hi = (CELL_LIVE, CELL_LIVE_HI) if live else (CELL_SPENT, CELL_SPENT_HI)
    # The positive terminal: brass and proud of the casing on a live cell, dull and shorter on a dead
    # one, so even the silhouette differs before any colour is read.
    nub_w, nub_h = (11, 0.46 * CELL) if live else (7, 0.32 * CELL)
    out = [
        r(x - 2, y - 2, w + 4, h + 4, "#14101a"),
        r(x, y, w, h, body),
        r(x, y, w, 0.14 * CELL, hi),  # top bevel
        r(x + w, y + (h - nub_h) / 2, nub_w, nub_h, BRASS if live else "#5d5560"),
    ]
    # Three charge segments, inset in the casing — the channel that actually carries the state.
    pad, gap = 0.15 * CELL, 0.08 * CELL
    seg_w = (w - 2 * pad - 2 * gap) / 3
    seg_y, seg_h = y + 0.28 * CELL, h - 0.42 * CELL
    for i in range(3):
        sx = x + pad + i * (seg_w + gap)
        if live:
            out.append(r(sx, seg_y, seg_w, seg_h, "#ffd9c2"))
            out.append(r(sx, seg_y, seg_w, seg_h * 0.36, "#fff5ee"))
        else:
            # hollow slots: a dark cavity with its own lip, so it reads as EMPTY rather than as a
            # darker stripe on a grey block
            out.append(r(sx, seg_y, seg_w, seg_h, "#241f28"))
            out.append(r(sx, seg_y, seg_w, seg_h * 0.22, "#3a333f"))
    return "".join(out)


ARM_COL = {"L": 0.0, "R": 10.0}


def arm_rect(
    side: str, dx: float = 0.0, dy: float = 0.0
) -> tuple[float, float, float, float]:
    """Where an arm's rect lands under a given translate — x0, y0, x1, y1."""
    x, y = gx(ARM_COL[side]) + dx, gy(3.0) + dy
    return (x, y, x + CELL, y + 2 * CELL)


def arms() -> str:
    """Both arm stubs, unchanged from the shipped sprite and left bare — the costume covers neither.

    Drawn BEFORE the shell, so the shell occludes them. That single ordering choice is what lets an
    arm reach behind the creature — it slides inboard, the shell's edge wipes it away, and it comes
    back holding something. It also makes it structurally impossible for an arm to cover the face,
    which two earlier front-mounted designs could not achieve at all. See assert_arm_poses_are_whole.
    """
    return (
        f'<g class="armL">{r(gx(ARM_COL["L"]), gy(3.0), CELL, 2 * CELL, gen.CLAWD)}</g>'
        f'<g class="armR">{r(gx(ARM_COL["R"]), gy(3.0), CELL, 2 * CELL, gen.CLAWD)}</g>'
    )


def reach(side: str, hx: float, hy: float) -> tuple[float, float]:
    """The translate that puts this arm's HAND — the bottom of the stub — at a point.

    The choreography is then written as the points the hands visit — behind the shell, or the end of
    the cell they are carrying — instead of as a column of tuned offsets. Hand-fitted numbers were
    what the first pass had, and every geometry change invalidated all of them silently: the arm
    still moved, it just stopped arriving anywhere.
    """
    bx, by = gx(ARM_COL[side]), gy(3.0)
    return (hx - (bx + CELL / 2), hy - (by + 2 * CELL))


# The points the hands visit, in canvas space. BEHIND_* sit inside the shell's silhouette, so an arm
# sent there is wholly occluded — that IS the reach. HOLD_* are derived from where the cell is being
# held, so hand and cargo cannot drift apart.
BEHIND_R = (gx(7.4), gy(6.0))
BEHIND_L = (gx(3.4), gy(6.0))
HOLD_R = (SPENT_OUT[0] + BAT[0] + 6, SPENT_OUT[1] + BAT[1] + BAT[3] * 0.5)
HOLD_L = (NEW_OUT[0] + BAT[0] + BAT[2] - 6, NEW_OUT[1] + BAT[1] + BAT[3] * 0.5)
# Both crate poses hold the cell by its NEAR end rather than its middle. A hand centred over a cell
# it is the same colour as hides it, and these are the two frames where the audience has to see
# which cell is which — the grey one going in, the orange one coming out.
H_BIN = (BIN[0] + 18, BIN[1] + BIN[3] * 0.26)
H_CHARGER = (CHARGER[0] + 22, CHARGER[1] + CHARGER[3] * 0.63)


def container(box: tuple[float, float, float, float], kind: str) -> tuple[str, str]:
    """A crate, returned as (back, front) so a cell can be drawn between the two halves.

    The front wall is the entire reason the loop can close without a fade: a cell parked behind it
    is not faded out, it is occluded, and occlusion is exact at every scale and in every renderer.
    """
    x, y, w, h = box
    # A lit top lip and a warm rim on the side facing the horizon glow. At the ground's own value
    # both crates were invisible: the first render had them as two dark smudges, and the charger's
    # interior glow read as a stray orange bar because the box around it never resolved.
    back = [
        r(x, y, w, h, BIN_BODY),
        r(x, y, w, 0.1 * CELL, BIN_EDGE),
        r(x, y, 0.07 * CELL, h, BIN_RIM, extra=' opacity=".5"'),
        r(x + w - 0.07 * CELL, y, 0.07 * CELL, h, BIN_RIM, extra=' opacity=".28"'),
        r(x + 5, y + 7, w - 10, h - 12, "#0d0a12"),  # the interior, in both crates
    ]
    if kind == "charger":
        # two brass rails and a low glow, mostly BEHIND the wall — a hint that something is being
        # charged down there, not a light source competing with the screen
        back += [
            r(x + 14, y + 16, 6, h - 26, BRASS, extra=' opacity=".5"'),
            r(x + w - 20, y + 16, 6, h - 26, BRASS, extra=' opacity=".5"'),
            f'<rect x="{fmt(x + 8)}" y="{fmt(y + h * 0.42)}" width="{fmt(w - 16)}" '
            f'height="{fmt(h * 0.5)}" fill="url(#chgGlow)"/>',
        ]
    else:
        # Cells already spent, from the loops before this one — the crate is not empty at t=0, which
        # is what says this has happened before and will again. Three separated bars with their own
        # outlines: two overlapping ones read as a single grey slab, which is what the first render
        # looked like (a bathtub).
        for i, (ox, oy) in enumerate(((9, 2), (17, 20), (11, 38))):
            back += [
                r(x + ox - 2, y + oy - 2, 82, 18, "#14101a"),
                r(x + ox, y + oy, 78, 14, CELL_SPENT if i % 2 == 0 else CELL_SPENT_HI),
                r(x + ox, y + oy, 78, 3, CELL_SPENT_HI, extra=' opacity=".55"'),
            ]
    front = [
        r(x, WALL_TOP, w, y + h - WALL_TOP, BIN_FRONT),
        r(x, WALL_TOP, w, 0.09 * CELL, BIN_EDGE, extra=' opacity=".85"'),
    ]
    if kind == "charger":
        front.append(
            f'<g class="chgLed" opacity=".3">{r(x + w - 18, WALL_TOP + 10, 8, 8, LED)}</g>'
        )
    return "".join(back), "".join(front)


# ── stylesheet ────────────────────────────────────────────────────────────────────────────────────
def tracks() -> dict[str, Track]:
    """Every animation in the file, one per element, all on the 7-second master clock."""
    ease = "cubic-bezier(.34,.06,.4,1)"  # a small mechanism arriving and settling
    step = "steps(1,end)"

    def tf(dx: float, dy: float) -> dict[str, str]:
        return {"transform": f"translate({fmt(dx)}px,{fmt(dy)}px)"}

    def op(v: str) -> dict[str, str]:
        return {"opacity": v}

    t: list[Track] = [
        # ---- the right arm: reaches BEHIND (and vanishes), comes back out holding the spent cell,
        #      carries it to the crate, home. The pose at T_REACH_IN is inside the shell, so between
        #      T_REACH_IN and T_UNSEAT the creature simply has one arm — which is the beat. ----
        Track(
            "armR",
            "arf",
            [
                (0.00, tf(0, 0)),
                (T_REACH_R, tf(0, 0)),
                (T_REACH_IN, tf(*reach("R", *BEHIND_R))),
                (T_UNSEAT, tf(*reach("R", *BEHIND_R))),
                (T_OUT_R, tf(*reach("R", *HOLD_R))),
                (T_AT_BIN, tf(*reach("R", *H_BIN))),
                (T_DROPPED, tf(*reach("R", *H_BIN))),
                (T_ARM_R_HOME, tf(0, 0)),
                (P, tf(0, 0)),
            ],
            ease=ease,
        ),
        # ---- the left arm: into the charger, lift the fresh cell, carry it in, reach BEHIND to seat
        #      it, come back out empty, home ----
        Track(
            "armL",
            "alf",
            [
                (0.00, tf(0, 0)),
                (T_REACH_L, tf(0, 0)),
                (T_AT_CHARGER, tf(*reach("L", *H_CHARGER))),
                (T_LIFTED, tf(*reach("L", H_CHARGER[0], H_CHARGER[1] - 48))),
                (T_OUT_L, tf(*reach("L", *HOLD_L))),
                (T_SEAT, tf(*reach("L", *BEHIND_L))),
                (T_HELD_IN, tf(*reach("L", *BEHIND_L))),
                (T_ARM_L_HOME, tf(0, 0)),
                (P, tf(0, 0)),
            ],
            ease=ease,
        ),
        # ---- the cell that starts seated. It is only ever in the socket, so it needs no path:
        #      it hands over to the fresh cell at T_NEW_RESET, both behind the shell. ----
        Track(
            "cellLive",
            "clf",
            [
                (0.00, op("1")),
                (T_UNSEAT, op("0")),
                (T_NEW_RESET, op("1")),
                (P, op("1")),
            ],
            ease=step,
        ),
        # ---- the spent cell: socket -> bin, then reset while hidden ----
        Track(
            "cellSpentGate",
            "csg",
            [
                (0.00, op("0")),
                (T_UNSEAT, op("1")),
                (T_SPENT_OFF, op("0")),
                (P, op("0")),
            ],
            ease=step,
        ),
        Track(
            "cellSpentPath",
            "csp",
            [
                (0.00, tf(0, 0)),
                (T_UNSEAT, tf(0, 0)),
                (T_OUT_R, tf(*SPENT_OUT)),  # drawn out into the open, in the hand
                (T_AT_BIN, tf(*BIN_MOUTH)),
                (T_DROPPED, tf(*PARK_SPENT)),
                # held in the crate until the gate closes, THEN the long glide back to the socket
                # position — off camera the whole way, which is the only thing that licenses it
                (T_SPENT_OFF, tf(*PARK_SPENT)),
                (P, tf(0, 0)),
            ],
            ease=ease,
            gate="cellSpentGate",
        ),
        # ---- the fresh cell: charger -> behind the shell, then reset once it is out of sight ----
        Track(
            "cellNewGate",
            "cng",
            [
                (0.00, op("0")),
                (T_REACH_L, op("1")),  # switched on while still inside the charger
                (T_NEW_RESET, op("0")),
                (P, op("0")),
            ],
            ease=step,
        ),
        Track(
            "cellNewPath",
            "cnp",
            [
                (0.00, tf(*PARK_NEW)),
                (T_AT_CHARGER, tf(*PARK_NEW)),
                (T_LIFTED, tf(*LIFT_NEW)),
                (T_OUT_L, tf(*NEW_OUT)),  # lifted out, held in clear air
                (T_SEAT, tf(0, 0)),  # carried in behind the shell — seated
                # seated and out of sight until the gate closes, then back to the charger off camera
                (T_NEW_RESET, tf(0, 0)),
                (P, tf(*PARK_NEW)),
            ],
            ease=ease,
            gate="cellNewGate",
        ),
        # ---- the screen. Three hard dropouts on seating, then an over-bright boot. ----
        Track(
            "screenLit",
            "slf",
            [
                (0.00, op("1")),
                (T_UNSEAT, op("0")),
                (T_SEAT, op("1")),
                (4.28, op("0")),
                (4.36, op("1")),
                (4.44, op("0")),
                (T_FLICKER_END, op("1")),
                (P, op("1")),
            ],
            ease=step,
        ),
        Track(
            "screenBoot",
            "sbf",
            [
                (0.00, op("0")),
                (T_FLICKER_END, op("0")),
                (T_BOOT_PEAK, op(".8")),
                (5.05, op("0")),
                (P, op("0")),
            ],
            ease="ease-out",
        ),
        Track(
            "scanGate",
            "sgf",
            [
                (0.00, op("0")),
                (T_SEAT, op("1")),
                (T_SCAN_END, op("0")),
                (P, op("0")),
            ],
            ease=step,
        ),
        Track(
            "scanPath",
            "spf",
            [
                (0.00, tf(0, 0)),
                (T_SEAT, tf(0, 0)),
                # one sweep down the glass on boot, then it rides back up off camera
                (T_SCAN_END, tf(0, (SCREEN[3] - SCREEN[1]) * CELL + 0.5 * CELL)),
                (P, tf(0, 0)),
            ],
            ease="linear",
            gate="scanGate",
        ),
        # ---- the face ----
        Track(
            "eyesOpen",
            "eof",
            [
                (0.00, op("1")),
                (T_BLINK1[0], op("0")),
                (T_BLINK1[1], op("1")),
                (T_UNSEAT, op("0")),
                (T_SEAT, op("1")),
                (T_BLINK2[0], op("0")),
                (T_BLINK2[1], op("1")),
                (P, op("1")),
            ],
            ease=step,
        ),
        Track(
            "eyesShut",
            "esf",
            [
                (0.00, op("0")),
                (T_BLINK1[0], op("1")),
                (T_BLINK1[1], op("0")),
                (T_BLINK2[0], op("1")),
                (T_BLINK2[1], op("0")),
                (P, op("0")),
            ],
            ease=step,
        ),
        Track(
            "look",
            "lkf",
            [
                (0.00, tf(0, 0)),
                (T_REACH_R, tf(0, 0)),
                (T_REACH_IN, tf(14, 0)),
                # back to facing us just BEFORE the power goes, so the last lit frame is a look
                # straight out of the banner. A snap at T_UNSEAT would need gating; this needs none.
                (T_UNSEAT - 0.12, tf(14, 0)),
                (T_UNSEAT, tf(0, 0)),
                (P, tf(0, 0)),
            ],
            ease="ease-in-out",
        ),
        Track(
            "mouth",
            "mof",
            [
                (0.00, op("1")),
                (T_UNSEAT, op("0")),
                (T_SEAT, op("1")),
                (T_SMILE[0], op("0")),
                (T_SMILE[1], op("1")),
                (P, op("1")),
            ],
            ease=step,
        ),
        Track(
            "mouthBig",
            "mbf",
            [
                (0.00, op("0")),
                (T_SMILE[0], op("1")),
                (T_SMILE[1], op("0")),
                (P, op("0")),
            ],
            ease=step,
        ),
        # ---- the light the screen throws on the ground. The scene itself gets darker while the
        #      creature is off, which is the cheapest way to make the power cut felt. ----
        Track(
            "spill",
            "spl",
            [
                (0.00, op(".5")),
                (2.30, op(".5")),
                (T_UNSEAT, op("0")),
                (T_SEAT, op("0")),
                (4.32, op(".72")),
                (4.85, op(".5")),
                (P, op(".5")),
            ],
            ease="ease-out",
        ),
        # ---- the lean, then the two-bounce wiggle of the content beat; a slow idle breath under
        #      both. The LEAN is what stops a vanishing arm reading as a rendering fault: the whole
        #      creature shifts a few px toward whichever hand is working behind it, so the arm goes
        #      away as part of a twist rather than simply ceasing to exist. Same element, same one
        #      animation — lean and bounce are just different stretches of one keyframe list. ----
        Track(
            "wiggle",
            "wgf",
            [
                (0.00, tf(0, 0)),
                (T_REACH_R, tf(0, 0)),
                (T_REACH_IN, tf(5, 0)),  # leaning right, reaching behind on that side
                (T_OUT_R, tf(5, 0)),
                (T_AT_BIN, tf(0, 0)),
                (T_REACH_L, tf(0, 0)),
                (T_AT_CHARGER, tf(-5, 0)),  # and left, for the other hand
                (T_SEAT, tf(-5, 0)),
                (T_HELD_IN, tf(0, 0)),
                (T_SMILE[0], tf(0, 0)),
                (5.45, tf(0, -7)),
                (5.62, tf(0, 0)),
                (5.78, tf(0, -3)),
                (5.95, tf(0, 0)),
                (P, tf(0, 0)),
            ],
            ease=ease,
        ),
        Track(
            "breath",
            "brf",
            [
                (0.00, tf(0, 0)),
                (P / 4, tf(0, -2)),
                (P / 2, tf(0, 0)),
            ],
            ease="ease-in-out",
            period=P / 2,
        ),
        # ---- the charger's own life ----
        Track(
            "chgLed",
            "cgl",
            [
                (0.00, op(".3")),
                (P / 8, op("1")),
                (P / 4, op(".3")),
            ],
            ease="ease-in-out",
            period=P / 4,
        ),
        # ---- the caption's state line: two mutually exclusive readings of the same moment ----
        Track(
            "stLive",
            "stl",
            [
                (0.00, op("1")),
                (T_UNSEAT, op("0")),
                (T_SEAT, op("1")),
                (P, op("1")),
            ],
            ease=step,
        ),
        Track(
            "stDark",
            "std",
            [
                (0.00, op("0")),
                (T_UNSEAT, op("1")),
                (T_SEAT, op("0")),
                (P, op("0")),
            ],
            ease=step,
        ),
        # ---- ambient: the sky's only motion, re-timed onto the 7 s clock. gen.starfield emits
        #      tw0/tw1/tw2 and the moon groups; their periods are OURS, not the hero's. ----
        Track(
            "tw0",
            "twa",
            [
                (0.00, {"opacity": ".45", "transform": "scale(.86)"}),
                (P / 2, {"opacity": "1", "transform": "scale(1.1)"}),
                (P, {"opacity": ".45", "transform": "scale(.86)"}),
            ],
            ease="ease-in-out",
        ),
        Track(
            "tw1",
            "twb",
            [
                (0.00, {"opacity": ".55", "transform": "scale(.92)"}),
                (P * 0.38, {"opacity": "1", "transform": "scale(1.14)"}),
                (P, {"opacity": ".55", "transform": "scale(.92)"}),
            ],
            ease="ease-in-out",
        ),
        Track(
            "tw2",
            "twc",
            [
                (0.00, {"opacity": ".5", "transform": "scale(.9)"}),
                (P / 4, {"opacity": "1", "transform": "scale(1.06)"}),
                (P / 2, {"opacity": ".5", "transform": "scale(.9)"}),
            ],
            ease="ease-in-out",
            period=P / 2,
        ),
        Track(
            "moonLit",
            "mnf",
            [
                (0.00, op(".86")),
                (P / 2, op("1")),
                (P, op(".86")),
            ],
            ease="ease-in-out",
        ),
        Track(
            "moonHalo",
            "mhf",
            [
                (0.00, op(".22")),
                (P / 2, op(".30")),
                (P, op(".22")),
            ],
            ease="ease-in-out",
        ),
    ]
    return {tr.cls: tr for tr in t}


def css(art: gen.Art, trs: dict[str, Track]) -> str:
    d, lt = art.dark, art.light

    def cloudrules(t: gen.Theme, pfx: str = "") -> str:
        s = ""
        for i, m in enumerate(t.mound):
            s += f"{pfx}.md{i}{{fill:{m}}}"
        return s

    base = (
        # themed fills, inherited verbatim from the hero's DUSK/DAWN so the family cannot drift
        f".sky{{fill:url(#skyD)}}.grd{{fill:url(#grdD)}}.glw{{fill:url(#glowD)}}"
        f".st{{fill:{d.star}}}.sc{{fill:{d.star_cool}}}.sw{{fill:{d.star_warm}}}"
        f".sn{{fill:{d.star}}}.mdisc{{fill:{d.moon}}}"
        f".grain{{opacity:{fmt(d.grain)}}}"
        f".rl{{stroke:{d.rule}}}.wm{{fill:{d.wm}}}.sub{{fill:{d.sub}}}"
        f".tf0,.tf1{{fill:{d.tuft}}}.fgb{{fill:{d.fg}}}"
        f".vig{{fill:url(#vig);opacity:{fmt(d.vignette)}}}"
        f".lit{{fill:{SCREEN_LIT}}}" + cloudrules(d)
    )
    base += "".join(tr.css() for tr in trs.values())

    # The additive delay channel, for the same reason the hero has one: `banner-shots.sh` seeks a
    # timestamp by setting animation-delay on every element, which would overwrite an authored
    # delay outright and render a deliberately staggered starfield in lockstep. `animation:`
    # shorthand resets the delay, so the longhand has to follow it.
    base = re.sub(
        r"(animation:[^;{}]*?infinite)",
        r"\1;animation-delay:calc(var(--d,0s) + var(--fz,0s))",
        base,
    )

    # A still that is legible on its own: the creature seated, powered, both arms out, cells out of
    # sight — which is exactly the t=0 frame, and exactly every element's BASE attribute value. So
    # this fallback cannot drift from the animation it replaces; it is not a second drawing.
    reduced = (
        "@media (prefers-reduced-motion:reduce){"
        "*{animation:none!important}"
        ".moonHalo{opacity:.26}.moonLit{opacity:.93}"
        "}"
    )
    light = (
        "@media (prefers-color-scheme:light){"
        ".sky{fill:url(#skyL)}.grd{fill:url(#grdL)}.glw{fill:url(#glowL)}"
        f".grain{{opacity:{fmt(lt.grain)}}}"
        f".nOnly{{display:none}}"
        f".rl{{stroke:{lt.rule}}}.wm{{fill:{lt.wm}}}.sub{{fill:{lt.sub}}}"
        f".tf0,.tf1{{fill:{lt.tuft}}}.fgb{{fill:{lt.fg}}}"
        # The state line borrows the screen's mint so the caption lights up with the face. On a
        # DAWN sky that mint is nearly invisible, so the light theme takes the same hue down to
        # where it holds against a pale background.
        f".lit{{fill:#12695b}}"
        f".vig{{opacity:{fmt(lt.vignette)}}}" + cloudrules(lt) + "}"
    )
    return base + reduced + light


# ── assembly ──────────────────────────────────────────────────────────────────────────────────────
def assert_gen_contract() -> None:
    """Fail loudly if the hero generator moved under us.

    This file borrows gen.py's palette and scenery ON PURPOSE — a copy would drift, and drift
    between two banners in one README is the defect the borrowing prevents. The cost is a coupling,
    so the coupling is asserted rather than assumed: if a successor renames a helper or re-scales
    the sprite, this build stops instead of emitting a banner that no longer matches its sibling.
    """
    want = {"W": 1920, "CELL": 20, "CLAWD": "#D77757", "SPRITE_W": 220, "SPRITE_H": 160}
    for k, v in want.items():
        got = getattr(gen, k, None)
        if got != v:
            raise SystemExit(
                f"recycle: gen.{k} is {got!r}, expected {v!r}. The hero generator changed its "
                f"sprite geometry or palette; re-derive this banner's layout before rebuilding."
            )
    for fn in (
        "sky_defs",
        "starfield",
        "moon",
        "moon_body",
        "mounds",
        "ground_detail",
        "fmt",
    ):
        if not callable(getattr(gen, fn, None)):
            raise SystemExit(
                f"recycle: gen.{fn}() is gone — the scenery this banner reuses moved"
            )
    for th in ("DUSK", "DAWN"):
        if not isinstance(getattr(gen, th, None), gen.Theme):
            raise SystemExit(f"recycle: gen.{th} is no longer a Theme")


def build() -> str:
    assert_gen_contract()
    assert_beats_ordered()
    assert_costume_reveals()
    assert_parked_cells_hidden()
    assert_caption_clear()

    # gen.py's scenery helpers read module globals for the horizon and the type keep-out. Point
    # them at THIS canvas for the duration of the build; nothing is written back to gen.py.
    gen.GROUND, gen.H, gen.KEEPOUT = GROUND, H, KEEPOUT
    gen._SCROLLING.clear()

    art = gen.Art(
        key="recycle-bmo",
        title="BMO Changes Battery",
        blurb="",
        dark=gen.DUSK,
        light=gen.DAWN,
        star_count=(150, 44, 14),
        moon=(238, 100, 50),
        clawd_x=CX,
        clawd_scale=S,
    )
    rng = random.Random(20260729 + sum(ord(c) for c in art.key))
    trs = tracks()
    assert_return_travel_is_invisible(trs)
    assert_arm_poses_are_whole(trs)
    assert_power_is_one_fact(trs)
    style = css(art, trs)
    assert_one_animation_each(style)

    caption = [
        ("SELF-RECYCLE", 28.0, 6.5),
        ("handoff-fire.sh --recycle", 44.0, 1.2),
        ("▸ session live · watcher armed", 30.0, 0.6),
        ("▸ /exit — relaunching in place", 30.0, 0.6),
    ]
    assert_text_fits(caption)

    chg_back, chg_front = container(CHARGER, "charger")
    bin_back, bin_front = container(BIN, "bin")
    sx, sy = gx(SCREEN[0]), gy(SCREEN[1])
    sw, sh = (SCREEN[2] - SCREEN[0]) * CELL, (SCREEN[3] - SCREEN[1]) * CELL
    mono = "ui-monospace,SFMono-Regular,Menlo,monospace"

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
        f'role="img" aria-label="The Claude Code creature, wearing a BMO costume, sits on a dusk '
        f"ridge and changes its own battery: it opens the compartment on its costume, lifts the "
        f"spent orange cell out, its screen face goes dark while nothing is seated, it takes a "
        f"fresh cell from a charger crate, seats it, the screen flickers back to life, and it "
        f"smiles. Beside the caption handoff-fire.sh --recycle, a state line reads session live, "
        f"watcher armed while the screen is lit and slash exit, relaunching in place while it is "
        f'dark.">',
        "<title>self-recycle — a session changes its own battery</title>",
        f"<desc>clawd in a BMO costume, changing its own battery, in one {fmt(P)}-second loop. "
        f"The face is lit if and only if a cell is seated, so the creature is genuinely off for "
        f"{fmt(POWER_OFF[1] - POWER_OFF[0])}s of every loop — which is what "
        f"handoff-fire.sh --recycle does to the pane it runs in. Same palette as the hero "
        f"banner; nothing crosses the caption.</desc>",
        f"<style>{style}</style>",
        "<defs>",
        gen.sky_defs(art),
        gen.moon(art),
        f'<clipPath id="glass"><rect x="{fmt(sx)}" y="{fmt(sy)}" width="{fmt(sw)}" '
        f'height="{fmt(sh)}"/></clipPath>',
        # the light the screen throws forward, and the charger's interior
        f'<radialGradient id="spillG" cx="0.5" cy="0.5" r="0.5">'
        f'<stop offset="0" stop-color="{SCREEN_LIT}" stop-opacity=".55"/>'
        f'<stop offset="1" stop-color="{SCREEN_LIT}" stop-opacity="0"/></radialGradient>',
        f'<radialGradient id="chgGlow" cx="0.5" cy="0.7" r="0.6">'
        f'<stop offset="0" stop-color="{CELL_LIVE}" stop-opacity=".55"/>'
        f'<stop offset="1" stop-color="{CELL_LIVE}" stop-opacity="0"/></radialGradient>',
        "</defs>",
        f'<rect class="sky" width="{W}" height="{H}"/>',
        f'<rect class="glw" x="0" y="{fmt(GROUND - 260)}" width="{W}" height="290"/>',
        f'<rect class="grain" x="0" y="0" width="{W}" height="{GROUND}" filter="url(#grain)"/>',
        f'<g class="nOnly">{gen.starfield(art, rng)}</g>',
        f'<g class="nOnly">{gen.moon_body(art)}</g>',
        gen.mounds(art, rng),
        gen.ground_detail(art),
        f'<line x1="0" y1="{GROUND}" x2="{W}" y2="{GROUND}" class="rl" stroke-width="3" '
        f'stroke-dasharray="3 9" stroke-linecap="round" opacity=".72"/>',
        # ---- Z-ORDER IS THE MECHANISM HERE, not a detail. Four rules fix this order completely:
        #        1. ARMS AND CELLS BEFORE THE BODY. This is what makes reaching behind possible: the
        #           shell occludes them, so a hand sent inboard is wiped away by the shell's own edge
        #           and a cell carried in disappears. It is also why nothing can ever cover the face.
        #        2. A parked cell must be behind its container's front wall — hence back / cell /
        #           front for each crate. That occlusion, not a fade, is what closes the loop.
        #        3. The crates' fronts come after the cells so a cell dropped in is truly hidden.
        #        4. The type is last of all; the vignette is second-to-last, so it darkens the scene
        #           and never the caption.
        #      Move one line and something is occluded that should not be — or worse, isn't.
        chg_back,
        bin_back,
        f'<ellipse class="spill" cx="{fmt(gx(5.5))}" cy="{fmt(GROUND + 2)}" rx="300" ry="46" '
        f'fill="url(#spillG)" opacity=".5"/>',
        '<g class="breath"><g class="wiggle">',
        # the hands and everything in them: BEHIND the creature
        arms(),
        f'<g class="cellLive" opacity="1">{battery(True)}</g>',
        f'<g class="cellNewGate" opacity="0"><g class="cellNewPath">{battery(True)}</g></g>',
        f'<g class="cellSpentGate" opacity="0"><g class="cellSpentPath">{battery(False)}</g></g>',
        # the creature, wearing the console: this is what occludes them
        creature_body(),
        costume(),
        "</g></g>",
        chg_front,
        bin_front,
        f'<rect class="vig" width="{W}" height="{H}"/>',
    ]

    # the caption, last — nothing can be drawn over the type
    k, cmd, live, dark = caption
    parts += [
        f'<text x="{fmt(CAPTION_X)}" y="176" class="sub" font-family="{mono}" '
        f'font-size="{fmt(k[1])}" letter-spacing="{fmt(k[2])}" opacity=".8">{k[0]}</text>',
        f'<text x="{fmt(CAPTION_X)}" y="238" class="wm" font-family="{mono}" '
        f'font-size="{fmt(cmd[1])}" letter-spacing="{fmt(cmd[2])}">{cmd[0]}</text>',
        f'<rect class="sub" x="{fmt(CAPTION_X)}" y="258" width="248" height="1" opacity=".26"/>',
        f'<g class="stLive" opacity="1"><text x="{fmt(CAPTION_X)}" y="294" class="lit" '
        f'font-family="{mono}" font-size="{fmt(live[1])}" letter-spacing="{fmt(live[2])}" '
        f'opacity=".9">{live[0]}</text></g>',
        f'<g class="stDark" opacity="0"><text x="{fmt(CAPTION_X)}" y="294" class="sub" '
        f'font-family="{mono}" font-size="{fmt(dark[1])}" letter-spacing="{fmt(dark[2])}">'
        f"{dark[0]}</text></g>",
        "</svg>",
    ]
    return "".join(parts)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/banner")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    svg = build()
    p = out / "recycle-bmo.svg"
    p.write_text(svg, encoding="utf-8")
    dark = POWER_OFF[1] - POWER_OFF[0]
    print(
        f"{p}  {len(svg):,} B  · loop {fmt(P)}s · dark {fmt(dark)}s "
        f"({dark / P * 100:.0f}% of the loop with the creature genuinely off)"
    )


if __name__ == "__main__":
    main()
