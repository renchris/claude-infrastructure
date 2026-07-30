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


# ── the world clock ────────────────────────────────────────────────────────────────────────────
# The three ratified beats all speak ONE sentence: the ground's scroll rate. Nominal = working,
# zero = blocked on a human (THE ASK), negative = a turn was returned (THE REFUSAL). So the rate is
# not a per-beat effect to be hand-animated three times; it is a single shared quantity, modelled
# here as one world clock w(t) that every ground-plane layer reads. Significance then comes from a
# shared scale rather than from novelty per beat, which is the whole answer to "volume dilutes
# significance".
#
# TWO RESULTS FELL OUT OF THE LOOP THAT THE SPEC DID NOT HAVE, and both bind whoever edits next:
#
# 1. A LOOPING WORLD CANNOT HOLD OR REVERSE FOR FREE. Every scrolling layer must travel a whole
#    number of its own wrap distances per master period or the loop seams. So a permanent deficit of
#    world-time would have to be a common multiple of EVERY layer's period — and the slowest layer's
#    period IS the master period, so the only free deficit is the entire loop. Therefore every stop
#    and every rewind must be REPAID inside the loop, at a rate strictly above nominal. The catch-up
#    is not an artifact to be hidden; it is forced, so each beat has to MEAN it. Both do: a returned
#    turn costs you a step and you make it up, and a session unblocked works through what it held.
#
# 2. THE RATE VOCABULARY IS THE INTEGERS. The print lock says the ground advances exactly one
#    leg-spacing per stride; under rate r it advances r leg-spacings, so the foot lands in an
#    existing print only when r is a whole number. There is no gentle catch-up — the world can stop,
#    reverse, walk, double or treble and nothing in between exists. A 6 s stop is payable as 6 s at
#    2x or 3 s at 3x, and that is the entire menu. Do not "tune" a rate to soften it; it will
#    silently break the footprint lock the whole thesis rests on, and assert_print_lock will say so.
STRIP_V = TILE / STRIP_PERIOD  # 96 px/s — the rate the print lock is defined against

# The hop's clock, declared ONCE here because both the CSS keyframes and
# assert_hop_clear_of_stopped_world read it. A second copy in the checker would let the animation and
# the assertion drift apart, and the assertion would then pass on a file it no longer describes.
HOP_PERIOD = 12.0
HOP_FROM_PCT, HOP_TO_PCT = 72.0, 92.0  # airborne between these points of the cycle
HOP_RISE = HOP_PERIOD * HOP_FROM_PCT / 100
HOP_FALL = HOP_PERIOD * HOP_TO_PCT / 100

# Rate modulations, in STRIDES from the owning beat's declared window start:
#     (offset_strides, n_strides, rate)
WORLD_MOD: dict[str, tuple[tuple[int, int, int], ...]] = {
    # THE REFUSAL — `completion-assert.sh` refuses a false "done", and the README's own diagram
    # draws it as an arrow BACK. The bar drops across the path, the creature settles (it is trying
    # to end the turn, so the world stops with it), the world pulls back exactly one print pitch,
    # the creature steps forward into the print it has already made, and then it makes up the ground
    # it lost. The foot is over the SAME print at +2, +3 and +5 strides, and over the print behind
    # it at +4: a returned turn is redoing a step.
    "rRefuse": ((2, 1, 0), (3, 1, -1), (4, 1, 1), (5, 3, 2)),
    # THE ASK — the system pages a human only when one must decide, and then it waits with no
    # default. Nothing arrives; everything stops. 12 strides of dead world (6 s — in a loop made of
    # motion the only cessation is the most salient thing in it), then 6 strides at treble to clear
    # the debt. 6+3 was chosen over 4+4 because the cessation is the payload and the catch-up is the
    # cost: maximise the payload, minimise the cost's DURATION.
    "rAsk": ((0, 12, 0), (12, 6, 3)),
}


def world_segments() -> list[tuple[float, float, int]]:
    """Absolute (t0, t1, rate) covering the whole loop; rate 1 wherever nothing is declared."""
    declared: list[tuple[float, float, int]] = []
    for beat, mods in WORLD_MOD.items():
        base = RARE_EVENTS[beat][0]
        for off, n, r in mods:
            declared.append((base + off * STRIDE, base + (off + n) * STRIDE, r))
    declared.sort()
    out: list[tuple[float, float, int]] = []
    t = 0.0
    for t0, t1, r in declared:
        if t0 < t:
            raise SystemExit(
                f"gen: world modulations overlap at t={t0}s (previous segment ends {t}s) — two "
                f"rates for one instant is not a rate"
            )
        if t0 > t:
            out.append((t, t0, 1))
        out.append((t0, t1, r))
        t = t1
    if t < P:
        out.append((t, P, 1))
    return out


def world_breaks() -> list[tuple[float, float]]:
    """(t, q) at every segment boundary, where q = strip pixels the world is BEHIND nominal.

    q is piecewise LINEAR between these points because the rate is piecewise constant, so a `linear`
    CSS animation through exactly these keyframes reproduces it without approximation.
    """
    q = 0.0
    out = [(0.0, 0.0)]
    for t0, t1, r in world_segments():
        q += STRIP_V * (1 - r) * (t1 - t0)
        out.append((t1, q))
    return out


def pctx(t: float) -> str:
    """A keyframe offset at enough precision that the POSITION it encodes is exact.

    `pct()`'s 3 decimals are fine for an opacity gate but they quantise a boundary at t=13s to
    5.417%, an 0.08 ms error — which on a 96 px/s strip is 0.008 px of drift. That is invisible and
    it is still a lie, because the claim being made is 0.000000 px. Nine decimals puts the encoded
    error below 1e-6 px, and `assert_print_lock` reads the numbers back out of these strings rather
    than trusting this function.
    """
    return f"{t / P * 100:.9f}".rstrip("0").rstrip(".") or "0"


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
    #  name        (start_s, end_s)   duration — all inside the 2.5-10s band
    # Ordered so the beats land inside the window a reader actually sees. The timeline anchors at
    # LOAD (S16), so placement is not taste: a beat at t=200s is not rare, it is unseen.
    #
    # THE SUMMONING now LEADS, and that cost the other two their slots. A reader arrives at t=0 and
    # stays 5-15s, once — so the prime window is a single resource and it goes to the beat that says
    # the most. THE REFUSAL and THE ASK were re-timed, not weakened: both keep their full span, their
    # full world-clock modulation and their order relative to each other. Nothing here is a
    # loosened assertion — `assert_events_disjoint` and `assert_one_strip_feature` both name
    # re-timing in RARE_EVENTS as THE fix, and this is that fix.
    #
    # Every number below is forced, none is preference:
    #   · 9.6s, not the 10.0s `instance_max` — BUDGET's per_type_pct of 4.0% caps ONE beat at
    #     4% of 240s. A 3.0-13.0 window is 10.0s and breaches it; BUDGET_WAIVED is empty by design.
    #   · the 4.0s gaps are exactly EVENT_GAP; tightening any of them fails the disjointness gate.
    #   · rAsk could not start later than 26.0s: its 6s stop would then reach into the hop's airborne
    #     span (32.64-35.04s on the 12s hop clock) and `assert_hop_clear_of_stopped_world` refuses a
    #     creature jumping while the world is frozen. It clears that by 0.64s.
    "rSummon": (
        3.4,
        13.0,
    ),  # 9.6s — THE SUMMONING: a subagent is called, works, and removes itself
    "rRefuse": (17.0, 22.0),  # 5.0s — THE REFUSAL: the world pulls back one print pitch
    # THE ASK: 6s of dead world, then 3s at treble to clear the debt.
    "rAsk": (26.0, 35.0),  # 9.0s
    # THE OVERLAP: the print pitch halves; the foot lands on every 2nd print. Placed here and not
    # earlier because it and THE REFUSAL are the only two beats that put an OBJECT on the scrolling
    # strip, and a strip object is on canvas for ~20s however brief its beat is. Their on-canvas
    # windows must not overlap, so the spacing is set by geometry, not by the 4s event gap.
    "rOverlap": (36.0, 44.25),  # 8.25s
    # The visitor beats are DEMOTED, not deleted. The panel ruled co-presence semantically wrong —
    # a session is never co-present with its peers, they live in other panes — but deleting v6b's
    # identity is the spec owner's call, not this session's. So they keep their machinery and move
    # past the ~45s line where S16 says a beat is decoration. One line reverts either decision.
    "peek": (48.5, 54.5),  # 6.0s — a GLANCE, which is what its motion always read as
    "peer": (48.5, 57.5),  # 9.0s — v6b only, in place of peek
    "rCheer": (50.5, 54.5),  # 4.0s — part of the visitor's visit, see COMPOSITE_OF
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
#   rSleep  — SUPERSEDED BY THE ASK, not merely cut. Both beats are a cessation; the sleep's is
#             uncaused and the ask's is `cc-decide` class C waiting on a human with no default.
#             Shipping both puts two stops 15 s apart, and the ambient one makes the distinctive one
#             read as a repeat of itself. Its posture machinery (the legsWalk/legsStill swap) is
#             exactly what THE ASK needs and is reused rather than duplicated.
DELETED_EVENTS = ("balloon", "shoot", "birds", "rSleep")


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


# Beats every variant emits regardless of `art.events` — the ratified ones.
# ONE list, read by BOTH the duty budget and the disjointness gate. They used to carry a copy each,
# which is a silent-divergence trap: a beat added to one list only is either unbudgeted or
# uncollided, and in both cases the build stays green over the thing the gate exists to check.
#
# WITHDRAWN by the operator on the artifact. Both keep their machinery AND their RARE_EVENTS entry,
# so re-adding the one name here restores the whole beat — that is the point of routing every
# emitter through `emits()` rather than letting each decide for itself:
#   rOverlap — correct and INVISIBLE. Its entire signal is a print pitch that halves, ~9 px of ink
#              at the 838 px README column, under the one thing in frame anybody looks at. The
#              legibility audit had already named it the designated sacrifice; the artifact agreed.
#   rCheer   — belongs to the visitor's visit, and the visitor beats are on hold. On its own it is
#              an unprompted celebration with nothing present to celebrate.
ALWAYS_EMITTED = ("rSummon", "rRefuse", "rAsk")


def active_events(art: Art) -> list[str]:
    """Every rare event this variant actually emits, earliest first."""
    active = {n for n in RARE_EVENTS if n in art.events} | set(ALWAYS_EMITTED)
    if art.second_clawd:
        active.add("peer")
    return sorted(active, key=lambda n: RARE_EVENTS[n][0])


def emits(art: Art, name: str) -> bool:
    """Does this variant emit `name`? The ONE question every emitter and every geometry gate asks.

    Membership in ALWAYS_EMITTED / `art.events` used to decide only what the temporal gates MEASURED,
    while `build` emitted the overlap run and the cheer's raised arms unconditionally. Withdrawing a
    beat from the list would then have removed it from the budget and the disjointness gate and left
    it on screen — a beat nothing measures, which is the exact inversion of the drift
    `assert_event_names_known` exists to catch. So emission reads the same list the gates do.
    """
    return name in active_events(art)


def assert_duty_budget(art: Art) -> None:
    """Measure every rare event against the ratified budget; fail on any unwaived breach."""
    active = active_events(art)
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


def at(name: str, secs: float) -> str:
    """A percentage `secs` into a beat's declared window."""
    return pct(ev(name)[0] + secs)


def atf(name: str, frac: float) -> str:
    """A percentage at a FRACTION of the way through a beat's window.

    The only safe way to place an interior keyframe. Absolute-second offsets do not survive a beat
    being re-timed to a shorter window: they run off the end, land on a negative percentage, and CSS
    drops the whole keyframe block silently. Fractions cannot, by construction.
    """
    w0, w1 = ev(name)
    return pct(w0 + frac * (w1 - w0))


GATE_EDGE = 0.1  # s — the hard swap between a gate's two states


def gate(
    name: str, sel: str, windows: list[tuple[float, float]], on_inside: bool = True
) -> str:
    """An opacity gate: visible inside `windows`, hidden outside (or inverted).

    One animation, one element, `steps(1,end)` so the swap is hard — a pixel-art sprite must never be
    caught half-faded, and an interpolated opacity is not in the palette.
    """
    a, b = ("0", "1") if on_inside else ("1", "0")
    frames = [f"0%{{opacity:{a}}}"]
    for w0, w1 in sorted(windows):
        if w1 + GATE_EDGE > P:
            raise SystemExit(
                f"gen: gate '{name}' window ends at {w1}s, too close to P={P}s for its "
                f"{GATE_EDGE}s swap edge — the gate would never return to its resting state and the "
                f"loop would seam"
            )
        frames.append(f"{pct(w0)}%{{opacity:{a}}}{pct(w0 + GATE_EDGE)}%{{opacity:{b}}}")
        frames.append(f"{pct(w1)}%{{opacity:{b}}}{pct(w1 + GATE_EDGE)}%{{opacity:{a}}}")
    frames.append(f"100%{{opacity:{a}}}")
    return (
        f"@keyframes {name}{{{''.join(frames)}}}"
        f"{sel}{{animation:{name} {fmt(P)}s steps(1,end) infinite}}"
    )


def stopped_spans() -> list[tuple[float, float]]:
    """Contiguous spans where the world is not moving forward — rate zero or negative.

    Derived from the world clock rather than written down beside it, so the creature's stride and the
    ground it stands on cannot disagree about when the world stopped.
    """
    out: list[list[float]] = []
    for t0, t1, r in world_segments():
        if r > 0:
            continue
        if out and abs(out[-1][1] - t0) < 1e-9:
            out[-1][1] = t1
        else:
            out.append([t0, t1])
    return [(a, b) for a, b in out]


def ask_stop() -> tuple[float, float]:
    """THE ASK's dead-world span — the only one the stare and the ears belong to."""
    w0 = RARE_EVENTS["rAsk"][0]
    zero = [m for m in WORLD_MOD["rAsk"] if m[2] == 0]
    if len(zero) != 1:
        raise SystemExit(
            f"gen: THE ASK declares {len(zero)} rate-zero spans; the stare, the ears and the "
            f"standing legs are all gated on exactly one. Merge them or gate each explicitly."
        )
    off, n, _r = zero[0]
    return (w0 + off * STRIDE, w0 + (off + n) * STRIDE)


ASK_BLINK = 0.12  # s — one blink, long enough to register at 838px and too short to read as a shut
# Fractions of the dead-world span at which the creature blinks. Deliberately NOT on the 0.5s stride
# grid and not evenly spaced: the world clock has stopped, so anything ticking in step with it is
# just a second stopped thing. Three is the count — one reads as a dropped frame, four starts to
# read as a nervous tic in a beat whose subject is stillness.
ASK_BLINK_AT = (0.19, 0.53, 0.86)


def ask_blinks() -> list[tuple[float, float]]:
    """THE ASK's blinks: the one thing still alive through six seconds of dead world.

    The cessation IS the beat, so it is NOT shortened — but a frame with nothing moving in it is
    indistinguishable from a stalled image, and a reader who arrives inside the beat has no earlier
    frame to compare it against. It read as broken ("feels buggy being halted"). A blink answers
    exactly that and nothing else, because it is on the CREATURE: zero world-rate change, so there is
    no debt to repay, no strip feature to space, and `assert_print_lock` never sees it.

    Derived from `ask_stop()` rather than written down beside it, so re-timing the stop moves the
    blinks with it instead of leaving them over a world that has started moving again.
    """
    t0, t1 = ask_stop()
    span = t1 - t0
    out = [(t0 + f * span, t0 + f * span + ASK_BLINK) for f in ASK_BLINK_AT]
    if out[0][0] < t0 or out[-1][1] + GATE_EDGE > t1:
        raise SystemExit(
            f"gen: an ASK blink falls outside its own dead-world span ({t0:.2f}-{t1:.2f}s): "
            f"{[(f'{a:.2f}', f'{b:.2f}') for a, b in out]}. A blink after the world restarts makes "
            f"the stop look like it ended early. Move ASK_BLINK_AT's fractions inboard."
        )
    return out


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
    active = active_events(art)

    for i in range(len(active)):
        for j in range(i + 1, len(active)):
            a, b = active[i], active[j]
            (a0, a1), (b0, b1) = RARE_EVENTS[a], RARE_EVENTS[b]
            if b in COMPOSITE_OF.get(a, ()) or a in COMPOSITE_OF.get(b, ()):
                continue  # one beat in two elements — see COMPOSITE_OF
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


# ── gates on the world clock ───────────────────────────────────────────────────────────────────
def assert_world_rates_integral() -> None:
    """Result 2 above, enforced: a fractional rate silently unlocks the footprint."""
    bad = [(b, r) for b, mods in WORLD_MOD.items() for _o, _n, r in mods if int(r) != r]
    if bad:
        raise SystemExit(
            f"gen: fractional world rate(s) {bad}. The ground must advance a WHOLE number of "
            f"leg-spacings per stride or the foot stops landing in a print — there is no gentle "
            f"catch-up. Legal rates are the integers: 0 stops, -1 reverses, 2 and 3 repay."
        )


def assert_world_balanced() -> None:
    """Every stop and rewind must be repaid INSIDE the loop, and inside its own beat.

    Result 1 above: a permanent deficit would have to be a common multiple of every layer's period,
    and the slowest layer's period is P itself. If q does not return to 0 the loop seams — and the
    seam check would catch that, but only after a full Chromium render, and it could not say why.
    """
    q = 0.0
    for beat, mods in WORLD_MOD.items():
        for _off, n, r in mods:
            q += STRIP_V * (1 - r) * n * STRIDE
        if abs(q) > 1e-9:
            raise SystemExit(
                f"gen: world clock for '{beat}' ends {q:+.1f}px behind nominal. A stop or rewind is "
                f"debt: it must be repaid by a rate above nominal within the same beat, or the loop "
                f"seams. Add strides at rate 2 or 3 (each rate-2 stride repays "
                f"{STRIP_V * STRIDE:.0f}px, each rate-3 stride {2 * STRIP_V * STRIDE:.0f}px)."
            )
    if abs(world_breaks()[-1][1]) > 1e-9:
        raise SystemExit(
            f"gen: world clock ends {world_breaks()[-1][1]:+.1f}px off at t=P"
        )


def assert_world_inside_windows() -> None:
    """A rate modulation must lie inside its beat's DECLARED window.

    Otherwise the duty budget and the disjointness gate are both measuring a window that is not
    when the world is actually perturbed — the gate reports on a fiction, which is worse than no
    gate because it reports green over exactly the thing it exists to check.
    """
    for beat, mods in WORLD_MOD.items():
        w0, w1 = RARE_EVENTS[beat]
        lo = w0 + min(o for o, _n, _r in mods) * STRIDE
        hi = w0 + max(o + n for o, n, _r in mods) * STRIDE
        if lo < w0 - 1e-9 or hi > w1 + 1e-9:
            raise SystemExit(
                f"gen: '{beat}' modulates the world over {lo:.2f}-{hi:.2f}s but declares "
                f"{w0:.2f}-{w1:.2f}s in RARE_EVENTS. Widen the declared window: every temporal gate "
                f"reads the declaration, so an un-declared perturbation is an unbudgeted event."
            )


def assert_warp_within_tile() -> None:
    """The warp shifts a scrolling layer beyond its own wrap, so each carries a -TILE pad copy.

    That pad buys exactly one tile of headroom. A deeper stop would slide the layer past it and
    open a hard-edged GAP of page background at the frame edge — which on a dark plate is very
    nearly invisible, so it would ship.
    """
    qmax = max(abs(q) for _t, q in world_breaks())
    if qmax > TILE:
        raise SystemExit(
            f"gen: the world falls {qmax:.0f}px behind nominal, past the {TILE}px pad copy every "
            f"warped layer carries — the frame edge would show a gap. Shorten the stop, or emit a "
            f"second pad copy in `duplicate`."
        )


def assert_warp_matches_scroll(art: Art, sheet: str) -> None:
    """A layer's warp must be sized for the speed the STYLESHEET actually scrolls it at.

    Every parallax layer's period is written twice: `tiled()` takes it as `dur` and sizes the warp
    wrapper from `TILE / dur`, and the stylesheet writes it again as the `sc` animation duration.
    Nothing compared them, and they disagreed in the shipped artifact for `tf0` — declared `P/8`
    (30 s, so its wrapper was `wp64`) while `.tf0s` scrolled at `STRIP_PERIOD` (20 s, 96 px/s).

    `warp_css` scales each layer's world-modulation offset by its REGISTERED rate, so the mismatch
    means the modulation under-compensates by exactly the ratio between the two: through THE ASK's
    dead world `tf0` kept moving at 96-64 = 32 px/s while `tf1` and `fgb` froze byte-exact, and
    through THE REFUSAL's rewind it travelled two-thirds of everyone else. Measured, not inferred —
    two frames inside the stop differed over 17.3% of that band's pixels against 0.0% for its
    neighbours.

    Nothing else could have caught it. `divides_P` passes (both 20 and 30 divide 240), the print lock
    is anchored to `.fprs` and never looks at `tf0`, `warp_css` only requires that SOME layer sits at
    the strip rate, and every render is self-consistent. The defect lives exactly in the gap between
    two copies of one number, which is why the check has to read the EMITTED stylesheet rather than
    recompute the period — recomputing it would only prove this function agrees with itself.
    """
    for cls, dur in sorted(_LAYER_PERIOD.items()):
        m = re.search(rf"\.{re.escape(cls)}\{{animation:sc ([0-9.]+)s", sheet)
        if not m:
            raise SystemExit(
                f"gen[{art.key}]: layer '{cls}' is tiled with a {dur:g}s period but the stylesheet "
                f"never scrolls it — a tiled layer with no `sc` rule is painted and then frozen, "
                f"which reads as a stuck decal rather than as ground."
            )
        css_dur = float(m.group(1))
        if abs(css_dur - dur) > 1e-6:
            raise SystemExit(
                f"gen[{art.key}]: layer '{cls}' SCROLL/WARP MISMATCH — the stylesheet scrolls it at "
                f"{css_dur:g}s ({TILE / css_dur:.0f}px/s) but it registered a {dur:g}s period "
                f"({TILE / dur:.0f}px/s) with its warp wrapper. The world modulation is scaled by "
                f"the registered rate, so a stopped world would leave this layer creeping at "
                f"{abs(TILE / css_dur - TILE / dur):.0f}px/s while every correctly-warped layer "
                f"freezes. Write ONE period to both sites."
            )


def assert_print_lock(art: Art, encoded: list[tuple[float, float]]) -> None:
    """The thesis, re-proved UNDER the warp: the foot lands in an existing print every stride.

    `encoded` is the (t, q) polyline recovered from the percentages actually written into the
    stylesheet — not from `world_breaks()`. That distinction is the whole point: computing the check
    from the same expression that generated the CSS would only prove this function agrees with
    itself, and would stay green through any rounding introduced between here and the file. The
    lesson is on the record twice in this repo: a control has to replay the real artifact.

    The condition is exact, not approximate. Foot at canvas x_f; the strip coordinate under it is
    x_f + q(t) + STRIP_V*t; a print sits at every multiple of the pitch measured from x_f. So the
    foot is in a print iff (q(t) + STRIP_V*t) is a whole number of pitches, and that must hold at
    EVERY stride boundary in the loop.
    """
    pitch = STRIP_PX_PER_STRIDE
    worst = (0.0, 0.0)
    n = int(round(P / STRIDE))
    for m in range(n):
        t = m * STRIDE
        q = _interp(encoded, t)
        off = (q + STRIP_V * t) % pitch
        off = min(off, pitch - off)  # distance to the NEAREST print, either side
        if off > worst[1]:
            worst = (t, off)
    if worst[1] > 1e-6:
        raise SystemExit(
            f"gen[{art.key}]: FOOTPRINT LOCK BROKEN — at t={worst[0]:.2f}s the foot lands "
            f"{worst[1]:.6f}px from the nearest print (pitch {pitch:g}px). The record is the thesis; "
            f"a foot that misses it makes the ground decorative. Every world rate must be an integer "
            f"and every segment a whole number of {STRIDE:g}s strides."
        )
    print(f"  [{art.key}] print lock: 0.000000px over {n} stride boundaries")


def _interp(poly: list[tuple[float, float]], t: float) -> float:
    """Linear interpolation over a (t, value) polyline — the same reading a CSS `linear` run makes."""
    for (t0, v0), (t1, v1) in zip(poly, poly[1:]):
        if t0 - 1e-9 <= t <= t1 + 1e-9:
            if t1 - t0 < 1e-12:
                return v1
            return v0 + (v1 - v0) * (t - t0) / (t1 - t0)
    return poly[-1][1]


def assert_all_gates_wired() -> None:
    """Every `assert_*` in this module must actually be CALLED from `build`.

    This is the other half of "define an assertion and prove it fires", and it is the half that has
    already failed twice on this branch. S12 records one: an assertion was written, reviewed and
    committed, and never ran, because the patch anchor was single-quoted and a formatter had already
    converted it to double quotes, so the wiring edit no-opped in silence. A build stayed green over
    a check that did not exist. Proving a guard CAN fail says nothing about whether anything asks it.

    Reading `build`'s own source is deliberate: a hand-maintained list of expected calls is a third
    copy of the same fact and would rot exactly like the other two.
    """
    import inspect

    body = inspect.getsource(build)
    mine = [
        n
        for n, o in sorted(globals().items())
        if n.startswith("assert_") and callable(o) and n != "assert_all_gates_wired"
    ]
    orphans = [n for n in mine if f"{n}(" not in body]
    if orphans:
        raise SystemExit(
            f"gen: {len(orphans)} assertion(s) are DEFINED BUT NEVER CALLED from build(): "
            f"{orphans}. An unwired gate is worse than no gate — it reads as coverage in review and "
            f"the build goes green over the thing it was written to catch."
        )


def assert_keyframe_pcts_sane(art: Art, sheet: str) -> None:
    """Every keyframe selector in the emitted stylesheet must be a percentage in [0, 100].

    This is the guard for a defect that was live in the committed v6b and that nothing caught. Its
    interior keyframes were placed at absolute second offsets (`+14`, `-16`) carried over from a much
    longer window; on the 9 s peer they resolved to -0.83% and -1.67%. CSS drops a keyframe block
    with an invalid selector WHOLE, so the peer never stopped beside the resident and its cheer never
    appeared at all — and the file was well-formed, the lint passed, the seam passed, twelve frames
    were distinct, both themes rendered. A beat can be entirely absent from a candidate while every
    check reports green, which is why this reads the stylesheet rather than the intent behind it.
    """
    bad = []
    for block in re.finditer(
        r"@keyframes\s+([\w-]+)\s*\{(.*?)\}\s*(?=@|\.|$)", sheet, re.S
    ):
        name, body = block.group(1), block.group(2)
        for sel in re.finditer(r"(?:^|\})\s*([^{}]+?)\s*\{", "}" + body):
            for token in sel.group(1).split(","):
                token = token.strip()
                if not token or token in ("from", "to"):
                    continue
                if not token.endswith("%"):
                    bad.append((name, token, "not a percentage"))
                    continue
                try:
                    v = float(token[:-1])
                except ValueError:
                    bad.append((name, token, "unparseable"))
                    continue
                if v < 0 or v > 100:
                    bad.append((name, token, "outside 0-100%"))
    if bad:
        raise SystemExit(
            f"gen[{art.key}]: invalid keyframe selector(s) — CSS drops the whole block SILENTLY, so "
            f"the beat simply does not happen:\n"
            + "\n".join(f"  · @keyframes {n}: '{t}' ({why})" for n, t, why in bad)
            + "\nPlace interior keyframes with atf() — a fraction of the window, never a second "
            "offset that can run off its end."
        )


def assert_every_shape_is_themed(art: Art, sheet: str, body: str, defs: str) -> None:
    """Every painted shape must get its colour from the palette, not from the SVG default.

    THE REFUSAL's barrier shipped its first render in solid black because it carried a class with no
    fill rule behind it. That is not a loud failure: SVG's initial `fill` is black, so the shape
    renders confidently in a colour no theme chose, and on the light scheme it would have been black
    on pale. Nothing in the output pipeline can catch it — the file is well-formed, one animation per
    element, the seam holds, twelve frames differ, both schemes "render". Only the eye catches it, and
    only if the crop happens to include it.
    """
    # `fill` INHERITS in SVG, so the question is whether the shape OR ANY ANCESTOR supplies one. A
    # first cut of this check looked at each shape's own class alone and flagged all ~400 stars, which
    # legitimately take their colour from `<g class="st sn tw0">`. Worth recording: a guard whose
    # model of the format is wrong produces a wall of false positives, and the only cheap response to
    # that is to delete it — so an over-strict guard ends up costing exactly what no guard costs.
    import xml.etree.ElementTree as ET

    def filter_generates_its_own_paint(el) -> bool:
        """True when a filter REPLACES the shape rather than modifying it.

        The grain rect is the case: its filter starts at `feTurbulence` and never references
        SourceGraphic, so the output is entirely synthesised and the rect's own fill cannot reach the
        screen. Adding a fill to satisfy a checker would be a lie written to keep a checker quiet.
        A filter that DOES consume SourceGraphic is not exempt — there the fill is still the input.
        """
        ref = re.match(r"url\(#([\w-]+)\)", el.get("filter") or "")
        if not ref:
            return False
        block = re.search(
            rf'<filter id="{re.escape(ref.group(1))}".*?</filter>', defs, re.S
        )
        if not block:
            return False
        chain = block.group(0)
        return (
            "SourceGraphic" not in chain
            and re.search(r"<fe(?:Turbulence|Flood|Image)\b", chain) is not None
        )

    def supplies_paint(el) -> bool:
        if el.get("fill") or el.get("stroke"):
            return True
        if filter_generates_its_own_paint(el):
            return True
        for cls in (el.get("class") or "").split():
            for rule in re.findall(rf"\.{re.escape(cls)}\b[^{{}}]*{{([^}}]*)}}", sheet):
                if re.search(r"(?:fill|stroke)\s*:", rule):
                    return True
        return False

    ns = "{http://www.w3.org/2000/svg}"
    shapes = {f"{ns}{t}" for t in ("rect", "circle", "ellipse", "path", "polygon")}
    root = ET.fromstring(f"<svg xmlns='http://www.w3.org/2000/svg'>{body}</svg>")
    missing = set()

    def walk(el, inherited: bool) -> None:
        here = inherited or supplies_paint(el)
        if el.tag in shapes and not here:
            missing.add(el.get("class") or f"<no class> at x={el.get('x')}")
        for kid in el:
            walk(kid, here)

    for kid in root:
        walk(kid, False)
    if missing:
        raise SystemExit(
            f"gen[{art.key}]: painted shape(s) with no fill in the stylesheet: {sorted(missing)}. "
            f"SVG's initial fill is BLACK, so these render in a colour no theme picked — visible as "
            f"a hard graphic element on the dark plate and worse on the light one. Give each a rule "
            f"in both schemes, or an inline fill= at the call site."
        )


def overlap_x0(art: Art) -> float:
    """Strip x of THE OVERLAP run's first print. ONE definition, read by the emitter AND the gate."""
    return foot_r(art) + STRIP_V * RARE_EVENTS["rOverlap"][0]


def refusal_x0(art: Art) -> float:
    """Strip x of THE REFUSAL barrier's left end. ONE definition, ditto."""
    return foot_r(art) + BAR_CLEAR + STRIP_V * (RARE_EVENTS["rRefuse"][0] + BAR_AT)


def strip_features(art: Art) -> list[tuple[str, float, float]]:
    """(beat, strip_x0, strip_x1) for every EVENT-OWNED object riding the scrolling ground.

    Only beats this variant actually EMITS. A withdrawn beat puts nothing on the strip, so reserving
    twenty seconds of canvas for it would make the gate report on a fiction — the same defect as a
    gate that skips a live event, reached from the other side.
    """
    pitch = STRIP_PX_PER_STRIDE
    ox, px = overlap_x0(art), refusal_x0(art)
    feats = [
        ("rOverlap", ox - 9, ox + (OVERLAP_PRINTS - 1) * pitch + 9),
        ("rRefuse", px, px + BAR_LEN),
    ]
    return [f for f in feats if emits(art, f[0])]


def assert_one_strip_feature(art: Art) -> None:
    """At most one event-owned feature on canvas at a time.

    The temporal gate is not enough for these two, and that is the whole reason this exists. A beat
    riding the strip is on canvas for (1920 + its width) / 96 ≈ 20-26 s no matter how short its beat
    is, so two beats a comfortable 4 s apart in the event table can still put two objects on screen
    together for twenty seconds — which is precisely the "volume dilutes significance" failure the
    redesign was ordered to fix, arriving through a gate that reports green.

    Swept over the real world clock, not over t, because THE ASK stops the ground: a stop compresses
    the wall-clock gap between two strip features without changing either's declared window.
    """
    feats = strip_features(art)
    step = 0.05
    n = int(round(P / step))
    for i in range(n + 1):
        t = min(i * step, P)
        travelled = STRIP_V * t - _interp(_ENCODED_STRIP, t)
        on = []
        for name, x0, x1 in feats:
            for copy in (0.0, GROUND_TRAVEL):
                a, b = x0 + copy - travelled, x1 + copy - travelled
                if b > 0 and a < W:
                    on.append(name)
        if len(set(on)) > 1:
            raise SystemExit(
                f"gen[{art.key}]: at t={t:.2f}s both {sorted(set(on))} are on canvas. A strip-borne "
                f"beat is visible for ~{(W + BAR_LEN) / STRIP_V:.0f}s regardless of how brief its "
                f"beat is, so their spacing is set by geometry and not by the {EVENT_GAP:g}s event "
                f"gap. Move one beat later in RARE_EVENTS."
            )


def assert_overlap_ink_is_ambient(art: Art) -> None:
    """THE OVERLAP must lay down prints indistinguishable from the ambient ones.

    Its whole claim is a DENSER RECORD — one stretch of ground carrying two walkers' worth. The
    moment its prints differ in colour, size or opacity they stop being record and become a new
    object crossing the frame, and then its declared 8.25 s window is measuring the wrong thing
    entirely: an object is on canvas for 20 s+, and the duty budget was told 8.25.
    """
    x = 500.0
    if print_ink(x) != print_ink(
        x
    ):  # pragma: no cover - stability of the spelling itself
        raise SystemExit("gen: print_ink is not deterministic")
    ambient = print_ink(x)
    if 'class="fpr"' not in ambient:
        raise SystemExit(
            f"gen[{art.key}]: prints no longer carry the ambient `fpr` class, so the overlap run "
            f"cannot be ink-identical to the record it is meant to thicken"
        )
    body = "".join(
        print_ink(overlap_x0(art) + k * STRIP_PX_PER_STRIDE)
        for k in range(OVERLAP_PRINTS)
    )
    shape = re.sub(r'x="[-\d.]+"', 'x="_"', ambient)
    for chunk in re.findall(r"<rect[^>]*/>", body):
        if re.sub(r'x="[-\d.]+"', 'x="_"', chunk + "") not in shape:
            raise SystemExit(
                f"gen[{art.key}]: an overlap print differs from an ambient print other than in x:\n"
                f"  overlap: {chunk}\n  ambient: {ambient}\n"
                f"Both must come from print_ink(), or the beat is an object, not a record."
            )


def assert_hop_clear_of_stopped_world(art: Art) -> None:
    """Texture must not contradict the beat it lands in.

    The hop is involuntary life on a 12 s clock and is deliberately NOT a rare event. But a hop
    inside a dead-stopped world is a creature jumping while the world is frozen — the exact
    non-sequitur this redesign exists to remove, and it would arrive purely from re-timing a beat,
    with every existing gate still green.
    """
    stops = [(t0, t1) for t0, t1, r in world_segments() if r <= 0]
    k = 0
    while k * HOP_PERIOD < P:
        h0, h1 = k * HOP_PERIOD + HOP_RISE, k * HOP_PERIOD + HOP_FALL
        for s0, s1 in stops:
            if h0 < s1 and s0 < h1:
                raise SystemExit(
                    f"gen[{art.key}]: the hop fires {h0:.2f}-{h1:.2f}s, inside a stopped/reversed "
                    f"world ({s0:.2f}-{s1:.2f}s) — a creature jumping while the world is frozen. "
                    f"Move the beat off the {HOP_PERIOD:g}s hop clock."
                )
        k += 1


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


def seal_runs(
    cols: list[tuple[float, float, float, float]], bleed: float = 0.75
) -> list[tuple[float, float, float, float]]:
    """Overlap each run into its right-hand neighbour so no ANTI-ALIASED SEAM can open between them.

    The defect this closes, reported by the operator against the clouds: a hairline of background
    showing through the middle of a cloud, crawling as the layer scrolls, and flashing bright wherever
    the moon passed behind it.

    Two abutting shapes do NOT composite to full coverage. Each cloud run sits at a FRACTIONAL x (the
    per-cloud random offset, e.g. -1633.31), so the shared edge falls inside a device pixel; the
    renderer draws run A with partial alpha `a` there, then run B with partial alpha `b` OVER it, and
    the result is `a + b(1-a)`, which is strictly less than 1 whenever both are. The uncovered
    remainder is the sky — one pixel wide, exactly as reported. It crawls because the scroll transform
    changes the sub-pixel phase every frame, and it is brightest over the moon because that is what is
    behind it.

    Widening each run into the next removes the shared edge entirely: the seam pixel is now interior
    to a shape rather than a boundary between two. `bleed` is under one art pixel, so at every display
    scale the overlap is smaller than a rendered pixel and cannot show as a step; the runs are the
    SAME fill, so an overlap is invisible by construction where a gap is not.

    NOT fixed by `shape-rendering="crispEdges"`. That trades anti-aliasing for rounding, and two runs
    whose shared fractional edge rounds in opposite directions open a HARD one-pixel gap instead of a
    soft one — the same defect with sharper edges. Geometry that cannot seam beats a rendering hint
    that relocates the seam.

    The last run is left alone: there is no neighbour to bleed into, and extending it would grow the
    cloud's silhouette.
    """
    out = []
    for i, (x, y, w, h) in enumerate(cols):
        if i + 1 < len(cols) and abs((x + w) - cols[i + 1][0]) < 1e-9:
            w += bleed
        out.append((x, y, w, h))
    return out


def merge_runs(
    cols: list[tuple[float, float, float, float]],
) -> list[tuple[float, float, float, float]]:
    """Coalesce adjacent equal-height columns into one rect — same picture, far fewer nodes.

    Then SEAL what remains. Coalescing removes the joins between equal-height columns but leaves one
    at every change of height, and this function is the chokepoint every skyline in the file passes
    through — clouds, their lit crowns, the near foreground band. Sealing here fixes all of them at
    once; sealing at the call sites would fix whichever ones a future author remembered.
    """
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
    return seal_runs([(a, b, c, d) for a, b, c, d in out])


# ── emit helpers ──────────────────────────────────────────────────────────────────────────────────
def rects(cols, cls: str) -> str:
    for _x, y, _w, h in cols:
        _SCROLLING.append((y, y + h, cls))
    return "".join(
        f'<rect class="{cls}" x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}"/>'
        for (x, y, w, h) in cols
    )


# Every distinct layer speed that gets a warp wrapper, collected during the build so exactly the
# animations that are used are emitted. Keyed by px/s.
_WARPED: set[float] = set()

# The period each tiled layer DECLARED, keyed by its scroll class. Recorded because a layer's period
# is written twice — once here, where it sizes the warp wrapper, and once in the stylesheet, where it
# drives the actual scroll — and nothing used to compare them. `tf0` shipped for months declaring
# P/8 (30 s) to its warp while the stylesheet scrolled it at STRIP_PERIOD (20 s), so its world
# modulation was scaled for 64 px/s against a layer moving 96. See assert_warp_matches_scroll.
_LAYER_PERIOD: dict[str, float] = {}


def warp_class(v: float) -> str:
    """The wrapper class for a layer travelling at `v` px/s."""
    _WARPED.add(v)
    return "wp" + fmt(round(v, 4)).replace(".", "_")


def tiled(
    body: str, cls: str, dur: float, delay: float = 0.0, warp: bool = True
) -> str:
    """One scrolling parallax layer, wrapped in its world-clock warp.

    The warp CANNOT live in this layer's own keyframes. Its period is a sub-multiple of P, so a hold
    written into it would fire once per sub-period — twelve times a loop for the strip — which is a
    beacon of repetition rather than a rare beat. Nesting it as an outer group instead gives two
    single-animation elements (S8), leaves the ambient scroll byte-for-byte what it already was, and
    makes the modulation exactly once per loop.
    """
    divides_P(dur)
    _LAYER_PERIOD[cls] = dur
    style = f' style="--d:{fmt(-delay)}s"' if delay else ""
    inner = f'<g class="{cls}"{style}>{body}</g>'
    if not warp:
        return inner
    return f'<g class="{warp_class(TILE / dur)}">{inner}</g>'


def duplicate(body_fn, pad: bool = True) -> str:
    """Render a layer at -TILE, 0 and +TILE so translateX wraps seamlessly under the warp.

    Two copies is enough for an unwarped layer, whose translate stays inside [0, -TILE]. The warp
    adds a positive offset on top of that, so just after a wrap the layer needs content to the LEFT
    of its own origin or the frame edge shows a hard-edged gap of page background — which against a
    dark plate is very nearly invisible and would therefore ship. `assert_warp_within_tile` bounds
    the offset to the one tile this pad buys.
    """
    return (body_fn(-TILE) if pad else "") + body_fn(0) + body_fn(TILE)


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


def footprints(art: Art) -> str:
    """The record the walker leaves — prints baked into the strip at exactly one stride pitch.

    This is the thesis as a STATE rather than an event. The prints are already there, evenly spaced
    at the distance the ground travels in one stride, so the foot lands in an existing print every
    stride BY CONSTRUCTION. The record is continuous and the walker is not: you cannot tell where
    one session's prints end and the next's begin, which is `sessions run each other` rendered as
    the ground instead of as a diagram joining two creatures.

    It only works because the stride is locked (see assert_stride_locked). The grid is anchored to a
    foot's x modulo the pitch, and TILE / pitch is a whole number, so the alignment survives the tile
    wrap as well as every stride. The sprite's legs are themselves 2 and 4 cells apart — multiples of
    the pitch — so one grid puts a print under all four feet at once rather than under one.
    """
    pitch = STRIP_PX_PER_STRIDE
    n = TILE / pitch
    if abs(n - round(n)) > 1e-9:
        raise SystemExit(
            f"gen[{art.key}]: TILE {TILE} is not a whole number of {pitch}px print "
            f"pitches ({n:.3f}) — the grid would jump at the tile wrap"
        )
    offset = foot_l(art) % pitch

    def body(shift: float) -> str:
        out = []
        for k in range(int(round(n))):
            out.append(print_ink(shift + offset + k * pitch))
        return "".join(out)

    return tiled(duplicate(body), "fprs", STRIP_PERIOD)


def print_ink(x: float) -> str:
    """One footprint, centred on x. The SINGLE spelling of a print's ink.

    THE OVERLAP calls this too, and that is load-bearing rather than tidy: the extra prints it lays
    down must be indistinguishable from ambient ones. If the overlap run ever gets its own colour or
    size it stops being a denser RECORD and becomes a new object crossing the frame — a feature with
    a 20 s on-canvas life instead of an 8 s beat, and a different thing entirely from what the duty
    budget was told it was measuring. `assert_overlap_ink_is_ambient` refuses that.
    """
    return (
        f'<rect class="fpr" x="{fmt(x - 9)}" y="{fmt(GROUND + 5)}" width="8" height="4"/>'
        f'<rect class="fpr" x="{fmt(x + 1)}" y="{fmt(GROUND + 5)}" width="8" height="4"/>'
    )


def foot_l(art: Art) -> float:
    """Canvas x of the leftmost leg's outer edge — the print grid's anchor."""
    return art.clawd_x + CELL * art.clawd_scale


def foot_r(art: Art) -> float:
    """Canvas x of the rightmost leg's outer edge. The legs span 4 pitches, so a beat that has to be
    read AT THE FOOT has to clear all four of them, not one."""
    return art.clawd_x + 10 * CELL * art.clawd_scale


# ── the three ratified beats ───────────────────────────────────────────────────────────────────
# A world-borne object travels STRIP_V*P over the loop, so a single copy is visible for one pass
# only — which means it is on canvas at t=0 and gone at t=P, and the SEAM check fails. Emitting the
# same object again one full loop-travel downstream makes t=0 and t=P present identically BY
# CONSTRUCTION rather than by the accident of both being off-canvas.
GROUND_TRAVEL = STRIP_V * P  # 23040 px — one loop of world travel at the strip rate
OVERLAP_PRINTS = 12  # the successor's own record: "two walkers' worth", ~12 prints
BAR_LEN, BAR_W, POST_W, POST_H = 116.0, 7.0, 7.0, 66.0
BAR_CLEAR = 36.0  # how far ahead of the leading foot the bar comes down
BAR_DROP = (
    30.0  # how far it falls — far enough to cross the leg band, which is 48px tall
)
# Seconds after the REFUSAL's window opens at which the bar is fully down. It must coincide with the
# first stalled stride, or the world stops before anything has asked it to.
BAR_AT = WORLD_MOD["rRefuse"][0][0] * STRIDE
# ...and when it lifts: the instant the world has finished re-walking the step it was sent back over,
# which is the end of the rate-1 segment in the middle of the beat. Both derived, so re-timing the
# modulation moves the barrier with it instead of leaving it hanging over a world already moving on.
BAR_UP_AT = (WORLD_MOD["rRefuse"][2][0] + WORLD_MOD["rRefuse"][2][1]) * STRIDE


_ENCODED_STRIP: list[tuple[float, float]] = []


def warp_css() -> str:
    """One @keyframes per warped layer speed, driving every ground layer off ONE world clock.

    Each layer's offset is scaled by its own speed, so the parallax stays coherent: a stopped world
    stops the near tufts and the far mounds in the same proportion they normally move. The sky is
    NOT warped — the clouds keep drifting through THE ASK. That is a decision, not an omission: the
    ground's rate is the gauge the beats speak in, and a session blocked on a human does not stop the
    world, it stops its own progress. A frozen sky would also say the render had died.

    Side effect: records the strip-speed polyline exactly as encoded, for `assert_print_lock`.
    """
    breaks = world_breaks()
    out = []
    for v in sorted(_WARPED):
        cls = warp_class(v)
        frames = []
        for t, q in breaks:
            frames.append((pctx(t), fmt(round(q * v / STRIP_V, 4))))
        out.append(
            f"@keyframes {cls}f{{"
            + "".join(f"{p}%{{transform:translateX({x}px)}}" for p, x in frames)
            + f"}}.{cls}{{animation:{cls}f {fmt(P)}s linear infinite}}"
        )
        if abs(v - STRIP_V) < 1e-9:
            # read back out of the emitted TEXT — see assert_print_lock's docstring
            _ENCODED_STRIP[:] = [(float(p) / 100 * P, float(x)) for p, x in frames]
    if not _ENCODED_STRIP:
        raise SystemExit(
            "gen: no layer scrolls at the strip rate, so the print lock has nothing to be measured "
            "against — the footprint grid is anchored to that rate by construction"
        )
    return "".join(out)


def world_borne(body_fn, cls: str, extra: str = "") -> str:
    """One object that travels with the ground, warped by the world clock like every ground layer."""
    inner = f'<g class="{cls}"{extra}>{body_fn(0)}{body_fn(GROUND_TRAVEL)}</g>'
    return f'<g class="{warp_class(STRIP_V)}">{inner}</g>'


def overlap_run(art: Art) -> str:
    """THE OVERLAP — `handoff-fire.sh self-close --successor` refuses to retire a predecessor until
    the successor is VERIFIED ENGAGED, so succession overlaps rather than touches.

    For twelve prints the pitch halves: two walkers' worth of record on one stretch of ground. The
    foot still lands every 48 px, so it lands on every SECOND print, and that mismatch is the tell —
    there is more record here than one walker can account for. It exits by resolution: the run ends,
    the pitch halves back, the foot re-registers.

    Nothing fades in. The denser stretch arrives from the right as ground, because that is what it
    is: the record was written before this stretch reached us. An opacity gate would have popped the
    extra prints into existence across the whole frame at once, which is the despawn-in-reverse the
    spec rules out.

    WITHDRAWN — see ALWAYS_EMITTED. The half-pitch check below runs whether or not the beat is
    emitted, deliberately: a withdrawn beat whose geometry stops being checked rots silently, and
    restoring one name must restore a beat that provably sits on the print grid.
    """
    pitch = STRIP_PX_PER_STRIDE
    # The left edge meets the rightmost foot exactly at the declared window start.
    x0 = overlap_x0(art)
    half = (x0 - foot_l(art)) % pitch
    if abs(half - pitch / 2) > 1e-9:
        raise SystemExit(
            f"gen[{art.key}]: the overlap run sits {half:.3f}px off the ambient print grid, not the "
            f"{pitch / 2:g}px half-pitch it must sit at. At any other offset the foot does not land "
            f"on every second print — it lands between prints, which reads as a broken grid rather "
            f"than as two records. Keep the window start a whole number of {STRIDE:g}s strides."
        )
    if not emits(art, "rOverlap"):
        return ""

    def body(shift: float) -> str:
        return "".join(print_ink(shift + x0 + k * pitch) for k in range(OVERLAP_PRINTS))

    return world_borne(body, "ovl")


def refusal_gate(art: Art) -> str:
    """THE REFUSAL — `completion-assert.sh` refuses a false "done".

    A post arrives with the ground. When it draws level with the creature's path the bar comes down
    across it; the creature settles, trying to end its turn; the world pulls back exactly one print
    pitch so the creature is returned to the print it already made; it steps that step again; the bar
    lifts and it makes up the ground it lost.

    The post is deliberately still on canvas through THE ASK that follows, and that is not leftover
    scenery. A stopped strip of UNIFORM ground texture is ambiguous — nothing in it says whether it
    is moving. One distinct object standing dead still is unambiguous, so the post is what makes the
    next beat's cessation legible at all. It never does anything during it; it just holds.
    """
    x0 = refusal_x0(art)
    top = GROUND - POST_H

    def body(shift: float) -> str:
        px = shift + x0 + BAR_LEN - POST_W
        _SCROLLING.append((top, GROUND, "rfPost"))
        _SCROLLING.append((top + 4, top + 4 + BAR_W + BAR_DROP, "rfBar"))
        return (
            f'<rect class="rfp" x="{fmt(px)}" y="{fmt(top)}" width="{fmt(POST_W)}" '
            f'height="{fmt(POST_H)}"/>'
            # The bar is ALWAYS present, retracted at the post's head, and drops into the path. So
            # nothing spawns and nothing despawns: the exit is the same mechanism as the entrance,
            # played backwards, which is what reads as intent rather than as a fade.
            f'<g class="rfBar">'
            f'<rect class="rfp" x="{fmt(shift + x0)}" y="{fmt(top + 4)}" width="{fmt(BAR_LEN)}" '
            f'height="{fmt(BAR_W)}"/></g>'
        )

    return world_borne(body, "rfPost")


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
    divides_P(P / 16)

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

    out.append(tiled(duplicate(fg), "fgbs", P / 16))
    return "".join(out)


# ── clawd ─────────────────────────────────────────────────────────────────────────────────────────
def clawd_sprite(idsuffix: str = "", cheer: bool = True, summon: bool = False) -> str:
    """The creature as nested single-animation groups (S8).

    Geometry is the 11x8 grid from the binary: rows 0-5 are the body at columns 1-9, rows 2-3 widen
    to columns 0-10 (the arm stubs), the eyes are holes at column 2 and 8 of row 2, and the legs are
    columns 1/3/7/9 of rows 6-7.

    The pose vocabulary is quoted rather than invented: default / look-left / look-right / arms-up,
    where only the eye band moves between the three looking poses and arms-up is the one whole-body
    pose.

    `cheer=False` omits the arms-up group entirely rather than leaving it for a gate to hide. An
    ungated group is not hidden — the raised arms would simply be ON for the whole loop — so the
    element and its gate have to appear and disappear together.

    `summon=True` adds THE SUMMONING's two ON-BODY props: the hat, and the cake once it is in hand.
    Both live INSIDE this group rather than beside it, and that is forced rather than tidy — `.hop`
    lifts the creature 30px every 12s and the beat's window contains an airborne span, so a
    screen-pinned prop "in hand" would hang in the air for 2.4s while the hand left it behind. In here
    they ride the bob and the hop for free, with no second animation on any element.
    """
    c = CELL
    sfx = idsuffix
    divides_P(STRIDE, 2.0, 4.0, 8.0, HOP_PERIOD, 80.0, 120.0, 240.0)

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
    cheer_group = f'<g class="rCheer{sfx}">{arms_up}</g>' if cheer else ""

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

    # THE ASK's posture. The sleep this replaces shut the eyes; an ask does the opposite — it is
    # waiting on a human and looking straight at where the answer has to come from. So the ask needs
    # the eye band PARKED rather than PANNING: the 8 s look cycle is swapped out wholesale for a
    # centred pair, exactly as the legs are.
    #
    # It does NOT stay perfectly still, and that is a correction. A dead-still stare was the read the
    # beat wanted, and six seconds of it instead read as a stalled render — "feels buggy being
    # halted" — because nothing on screen distinguishes a stopped world from a stopped image. The gaze
    # still does not move; the eyes BLINK three times (see `ask_blinks`). The reason the ambient 4 s
    # blink could not simply be gated through still stands — it would have to be re-based onto the
    # master period, thirty repetitions, to keep six seconds out of the middle — so this pair carries
    # its own once-per-loop blink instead: gate outside on `.eyesAsk`, blink inside, the same nesting
    # as armsGate/armsIdle for the same one-animation-per-element reason.
    eyes_ask = (
        f'<g class="eyesAsk{sfx}">'
        f'<g class="aOpen{sfx}">{eyes_open}</g>'
        f'<g class="aShut{sfx}">{eyes_shut}</g>'
        f"</g>"
    )
    # ears up: the stubs rise ONE cell in their own columns. Deliberately not the cheer's three cells
    # out-and-up — the measurement on this grid puts -2 at "hat brim" and -4 at "antennae", and this
    # beat is alertness, not a gesture. It reads as attention because everything else has stopped.
    arms_alert = (
        f'<g class="armsAlert{sfx}">'
        f'<rect x="0" y="{eye_y - c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        f'<rect x="{10 * c}" y="{eye_y - c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        f"</g>"
    )

    # THE SUMMONING's hat: a solid crown one cell above the head and a brim one row WIDER sitting on
    # the head's own top row. No mid-band — a band across a 5-cell crown at this size is one pixel row
    # of a third colour and reads as noise, not as a hatband. The crown clears the body's top edge by
    # exactly one cell, which `assert_summon_clear_plate` bounds: unbounded, a crown grows into the
    # sky this beat is not allowed to author in.
    hat = (
        (
            f'<g class="smHat{sfx}">'
            f'<rect x="{3 * c}" y="{-c}" width="{5 * c}" height="{c}"/>'
            f'<rect x="{2 * c}" y="0" width="{7 * c}" height="{c}"/>'
            f"</g>"
        )
        if summon
        else ""
    )
    # ...and the cake ONCE IT IS IN HAND, as a second copy that takes over from the travelling one at
    # the same position in the same instant. Two representations of one object is the only way it can
    # both cross open plate and then ride A's hop — and they cannot disagree, because the travelling
    # copy is authored AT this position and animated backwards from B.
    #
    # Drawn BEFORE the body, which is the exit: its last four steps slide it 8 cells left, entirely
    # inside the body rect, and it switches off there. Occluded, not popped.
    held = f'<g class="smHeld{sfx}">{_cake(11 * c, c, c)}</g>' if summon else ""

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
        f"{cheer_group}"
        f"{arms_alert}"
        f"{held}"
        f"{body}"
        # The look cycle needs an opacity gate for THE ASK, and it already carries the 8 s pan, so it
        # takes a wrapper: gate outside, pan inside. Same shape as armsGate/armsIdle, same reason.
        f'<g class="lookGate{sfx}"><g class="look{sfx}">'
        f'<g class="eOpen{sfx}">{eyes_open}</g>'
        f'<g class="eShut{sfx}">{eyes_shut}</g>'
        f"</g></g>"
        f"{eyes_ask}"
        # legs swap wholesale between walking and standing, so the stride can stop during a doze
        # without any element carrying two animations
        f'<g class="legsWalk{sfx}">{legs("legA" + sfx, (1, 7))}{legs("legB" + sfx, (3, 9))}</g>'
        f'<g class="legsStill{sfx}">{legs("legS" + sfx, (1, 3, 7, 9))}</g>'
        # the hat LAST: it must sit over the head, not behind it, or the brim disappears into the body
        # and the crown alone is the two-nubs-above-the-head shape already measured to read as horns
        f"{hat}"
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
        f'shape-rendering="crispEdges">'
        f"{clawd_sprite(sfx, emits(art, 'rCheer'), emits(art, 'rSummon'))}</g>"
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


# ── THE SUMMONING ─────────────────────────────────────────────────────────────────────────────────
# The resident dons a hat; a burst opens in the clear plate beside it and a SECOND, SMALLER clawd is
# standing there; the resident hands it a letter; it hands back a cake; it removes itself in a second
# burst and the resident walks on with the cake. `Task`/`Agent` in four moves: dispatch, work,
# result, self-removal. The letter is the brief and the cake is the finished work.
#
# WHY THIS PUTS TWO CREATURES ON SCREEN when v6b's peer was rejected for exactly that. The peer WALKED
# IN from off-frame, which claims sessions are co-present in one world — they are not, they live in
# other panes. This one is CALLED INTO EXISTENCE and REMOVES ITSELF inside one 9.6s window, which is
# precisely what a subagent is. The distinction is the whole beat; a peer that merely arrived would
# be the rejected idea with new props.
#
# B IS DERIVED, NOT INVENTED. docs/research/CLAWD_SPRITE_EXTRACTION_2026-07-29.md § "The idle poses"
# records a second, SMALLER clawd shipping alongside the pose table, so a smaller orange mass is the
# binary's own vocabulary rather than this session's idea — and it preserves the source's rule of ONE
# saturated orange subject, which two same-size clawds break by construction.
SUMMON_B_SCALE = 0.8  # asserted SMALLER than A's; B does not walk, so the stride lock does not own it
SUMMON_GAP_CELLS = (
    6  # clear plate between the two bodies, measured in A's OWN grid cells
)
SUMMON_CLEAR_MIN = (
    2  # the floor: below this the two flat-orange masses read as one shape
)
SUMMON_Y_FLOOR = (
    340.0  # no NEW ink in the clear plate above this; the sky stays ambient
)

# The choreography, as FRACTIONS of the declared window — never absolute seconds. `atf`'s docstring is
# the reason and it is not hypothetical: v6b's interior keyframes were seconds carried over from a
# longer window, resolved to negative percentages, and CSS dropped the whole block SILENTLY, so the
# beat was simply absent from the candidate built to show it off.
#
# THE ORDER IS FORCED BY TWO FACTS, not by taste:
#  1. The ambient hop is airborne 8.64-11.04s on its 12s clock, i.e. inside this window, and it cannot
#     be moved — every other period that divides P either lands a jump inside a stopped world (the
#     assertion refuses it) or makes the hop so rare it stops reading as life. So NOTHING may be in
#     hand across it: both hand-offs complete by 8.6s, and the hop falls in the span where A is just
#     walking on with the cake, which is where a hop belongs anyway.
#  2. The loop must seam, so every prop must be gone by f=1. The cake leaves by sliding BEHIND A's own
#     body and switching off while fully occluded, and the letter the same way behind B — the exit is
#     the entrance played backwards, which this file already requires of the barrier and the peer.
#     The hat is the ONE plain swap: no pose in the vocabulary can lift it (arms translate on y only),
#     and sliding it down through A's face to hide it would be worse than a swap.
SM_HAT_ON, SM_HAT_OFF = 0.0625, 0.9375
SM_SPARK = (
    0.0625,
    0.198,
)  # the summoning burst; B switches on inside it, so nothing pops
SM_B_ON, SM_B_OFF = 0.125, 0.604
SM_MAIL = (
    0.229,
    0.375,
)  # 4 steps across the gap, then 2 more INTO B: taken, not vanished
SM_MAIL_OFF = 0.396
SM_BUP = (
    0.406,
    0.49,
)  # B's arms-up — the one whole-body pose in the table — as it hands the cake
SM_CAKE = (0.4375, 0.5215)
SM_HELD_ON = (
    0.542  # the travelling cake switches off in the same instant, at the same position
)
SM_POOF = (0.5625, 0.667)
SM_OCCLUDE = (0.8125, 0.917)  # after the hop lands at 11.04s, never during it
SM_HELD_OFF = 0.9375


def summon_cell(art: Art) -> float:
    """A's grid cell in canvas px — the ONE grid every prop is drawn and moved on.

    Props are sized and stepped in whole multiples of this. A prop that moves a fractional pixel per
    frame crawls: its edges shimmer at the render scale the README actually uses, which is the
    difference between pixel art and a scaled bitmap.
    """
    return CELL * art.clawd_scale


def summon_bx(art: Art) -> float:
    """B's left edge. ONE definition, read by every emitter AND by the clear-plate gate."""
    return (
        art.clawd_x + SPRITE_W * art.clawd_scale + SUMMON_GAP_CELLS * summon_cell(art)
    )


def sm_at(f: float) -> float:
    """A fraction of THE SUMMONING's declared window, in absolute seconds.

    The only way any part of this beat is allowed to name a time. `at()` takes seconds and `atf()`
    returns a percentage string; the gates want seconds, so this is the seconds-valued sibling of
    `atf` and it reads the window from RARE_EVENTS exactly as they do.
    """
    w0, w1 = ev("rSummon")
    return w0 + f * (w1 - w0)


def summon_steps(art: Art) -> dict[str, float]:
    """Every prop offset this beat uses, in canvas px, derived from the grid rather than measured.

    Returned as one dict so `assert_summon_on_grid` can check the same numbers the emitters use — a
    second copy is how the stride lock got four different ground speeds.
    """
    u = summon_cell(art)
    return {
        "u": u,
        "mail_dx": u,  # one cell per step across the gap
        "mail_dy": u / 2,  # and half a cell down: A's hand band is one cell above B's
        "mail_swallow": u * 1.5,  # the two steps that carry it inside B's silhouette
        "cake_dx": -3 * u / 4,  # 4 steps back over 3 cells
        "cake_dy": -14.0,  # 4 steps up over the 56px between B's hands and A's
        "held_dx": -2 * CELL,  # LOCAL px inside A's sprite: 2 cells per step, 4 steps
    }


def assert_summon_on_grid(art: Art) -> None:
    """Every prop step must be a WHOLE number of canvas pixels.

    Not a style rule. These props are 3-cell rects with hard edges on a 240s loop; a step of 23.5px
    puts every edge on a half pixel for half the beat, and at the 838px README column that is a
    visible crawl on the one object the beat asks the reader to follow. Asserted rather than trusted
    because the offsets are derived from `art.clawd_scale`, so a future variant with a different
    scale would break them silently.
    """
    bad = [
        (k, v)
        for k, v in summon_steps(art).items()
        if abs(v - round(v)) > 1e-9 and k != "u"
    ]
    if bad:
        raise SystemExit(
            f"gen[{art.key}]: THE SUMMONING's prop step(s) {bad} are not whole canvas pixels at "
            f"clawd_scale={art.clawd_scale}. A prop moving a fractional pixel per step crawls at the "
            f"render scale the README uses. Pick step counts that divide the travel exactly."
        )


def assert_summon_clear_plate(art: Art) -> None:
    """B must never touch A, must be SMALLER than A, and must fit inside the frame.

    v6b shipped a peer interpenetrating the resident for 7.2s in the same flat #D77757, and it read
    as a render error rather than as two sessions: two same-colour bodies that meet become ONE
    connected orange region, and the eyes of the one behind are simply erased. So the gap is asserted
    in A's own cells — the grid the reader's eye measures against — and the size difference with it,
    because two equal orange masses break the source's one-subject rule even when they never touch.
    """
    u = summon_cell(art)
    if SUMMON_B_SCALE >= art.clawd_scale:
        raise SystemExit(
            f"gen[{art.key}]: B's scale {SUMMON_B_SCALE} is not smaller than A's "
            f"{art.clawd_scale}. B is the binary's SMALLER in-session clawd; two same-size creatures "
            f"give the frame two equal orange subjects, which the source art does not do."
        )
    a_right = art.clawd_x + SPRITE_W * art.clawd_scale
    b_left = summon_bx(art)
    clear = (b_left - a_right) / u
    if clear < SUMMON_CLEAR_MIN:
        raise SystemExit(
            f"gen[{art.key}]: only {clear:.2f} cells of clear plate between A and B, under the "
            f"{SUMMON_CLEAR_MIN}-cell floor. Props hand ACROSS the gap; a gap this narrow makes the "
            f"two flat-orange masses read as one shape."
        )
    b_right = b_left + SPRITE_W * SUMMON_B_SCALE
    if b_right > W:
        raise SystemExit(
            f"gen[{art.key}]: B's right edge is at x={b_right:.0f}, past the {W}px frame — it would "
            f"be cropped, and a half-summoned creature reads as a clipping bug. Reduce "
            f"SUMMON_GAP_CELLS or move clawd_x left."
        )
    b_top = GROUND - SPRITE_H * SUMMON_B_SCALE
    if b_top < SUMMON_Y_FLOOR:
        raise SystemExit(
            f"gen[{art.key}]: B's head reaches y={b_top:.0f}, above the y={SUMMON_Y_FLOOR:.0f} floor "
            f"this beat may author in. The sky is ambient; only the resident's own silhouette goes up "
            f"there. Reduce SUMMON_B_SCALE."
        )
    # The hat is the one exemption, and it is BOUNDED rather than waived: it may clear the body's own
    # top edge by exactly one cell and no more. A's silhouette already reaches y=314, above the
    # floor, so a floor cannot apply to on-creature ink — but an unbounded exemption would let the
    # crown grow into the sky, which is the thing the floor exists to prevent.
    a_top = GROUND - SPRITE_H * art.clawd_scale
    hat_top = a_top - CELL * art.clawd_scale
    if hat_top < a_top - u - 1e-9:
        raise SystemExit(
            f"gen[{art.key}]: the hat's crown reaches y={hat_top:.0f}, more than one cell above the "
            f"body's own top edge y={a_top:.0f}"
        )


def _cake(x: float, y: float, u: float) -> str:
    """3 wide x 2 tall, an icing row, one candle pixel. The riskiest prop, so it is built to be
    SELF-contrasting rather than to contrast with the plate: dark body under a pale icing row under an
    amber candle. That way it reads on the navy ground and on the pale one without a theme override,
    which a single-tone silhouette of this size could not do.
    """
    return (
        f'<rect class="smCkC" x="{fmt(x + u)}" y="{fmt(y)}" width="{fmt(u)}" height="{fmt(u)}"/>'
        f'<rect class="smCkI" x="{fmt(x)}" y="{fmt(y + u)}" width="{fmt(3 * u)}" '
        f'height="{fmt(u)}"/>'
        f'<rect class="smCkB" x="{fmt(x)}" y="{fmt(y + 2 * u)}" width="{fmt(3 * u)}" '
        f'height="{fmt(2 * u)}"/>'
    )


def _burst(cx: float, cy: float, cls: str) -> str:
    """Five dots as ONE group with STATIC children.

    The dots never animate individually — one transform on the group is the entire effect. That is
    not tidiness: an SVG loaded as an `<img>` can never pause off-screen, so every element here is
    painting for as long as the page is open, and five dots animated singly would be five times the
    cost of the same picture.
    """
    r = 5.0
    dots = "".join(
        f'<rect class="smSpk" x="{fmt(cx + dx - r)}" y="{fmt(cy + dy - r)}" '
        f'width="{fmt(2 * r)}" height="{fmt(2 * r)}"/>'
        for dx, dy in ((0, -34), (30, -13), (19, 27), (-19, 27), (-30, -13))
    )
    return f'<g class="{cls}">{dots}</g>'


def summon_burst_centre(art: Art) -> tuple[float, float]:
    """Both bursts fire at B's own centre — ONE definition, also read by the CSS transform-origin."""
    return (
        summon_bx(art) + SPRITE_W * SUMMON_B_SCALE / 2,
        GROUND - SPRITE_H * SUMMON_B_SCALE / 2,
    )


def summon_props(art: Art) -> str:
    """The bursts and the two travelling props, drawn UNDER both creatures.

    Under, not over, and that is the whole exit mechanism: the letter's last two steps carry it inside
    B's silhouette and the travelling cake hands off to a copy inside A's, so each prop switches off
    while fully occluded instead of popping out of existence in open plate. A prop drawn OVER a body
    would also be the v6b failure in miniature — an object crossing a face erases it.
    """
    if not emits(art, "rSummon"):
        return ""
    st = summon_steps(art)
    u = st["u"]
    cx, cy = summon_burst_centre(art)
    a_right = art.clawd_x + SPRITE_W * art.clawd_scale
    a_top = GROUND - SPRITE_H * art.clawd_scale
    hand_y = (
        a_top + 2 * u
    )  # A's arm band: the letter leaves from the hand, not from the body
    # The letter: a pale face inside a dark edge. The brief's pale #f4ead8 alone is invisible on the
    # light scheme's pale plate, so the READ comes from the edge and the pale is the fill inside it —
    # one shape that works in both schemes rather than two theme overrides of the same rect.
    letter = (
        f'<g class="smMail">'
        f'<rect class="smMailE" x="{fmt(a_right)}" y="{fmt(hand_y)}" width="{fmt(2 * u)}" '
        f'height="{fmt(2 * u)}"/>'
        f'<rect class="smMailF" x="{fmt(a_right + u / 4)}" y="{fmt(hand_y + u / 4)}" '
        f'width="{fmt(1.5 * u)}" height="{fmt(1.5 * u)}"/>'
        f'<rect class="smMailE" x="{fmt(a_right + u / 2)}" y="{fmt(hand_y + 0.85 * u)}" '
        f'width="{fmt(u)}" height="{fmt(u / 4)}"/>'
        f"</g>"
    )
    # The travelling cake is drawn at its DESTINATION and animated backwards from B, so its final
    # position is identical to the held copy's by construction rather than by two numbers agreeing.
    cake = f'<g class="smCake">{_cake(a_right, a_top + u, u)}</g>'
    return letter + cake


def summon_bursts(art: Art) -> str:
    """Both bursts, drawn OVER B — the one thing in this beat that is not under a body.

    Measured, not assumed: with the burst under B its dots sit at radius 34-68px from B's own centre,
    i.e. inside a 176x128 body, so B occluded its own summoning for all but 0.37s of a 1.3s burst. The
    first render showed a creature simply appearing next to a hat. A burst is light rather than an
    object, so in front is also where it belongs: at its bright stage it covers B's arrival, which is
    exactly what a materialisation has to do — nothing may be seen switching on.
    """
    if not emits(art, "rSummon"):
        return ""
    cx, cy = summon_burst_centre(art)
    return _burst(cx, cy, "smSpark") + _burst(cx, cy, "smPoof")


def summon_peer(art: Art) -> str:
    """B — the smaller in-session clawd, SCREEN-PINNED, summoned and self-removed.

    Screen-pinned, never on the scrolling strip, and that is a hard constraint rather than a choice: a
    strip-borne object is on canvas for (W + its width) / 96 ≈ 20-26s however brief its beat is, so B
    would still be standing there through THE REFUSAL and THE ASK. Screen-pinning also costs the
    world clock nothing — no rate change, so no debt to repay and no print-lock exposure.

    B does not walk, does not bob and does not blink, and none of that is an omission. A summoned
    subagent is not a session walking a world; it is called, it works, it is gone. Its one motion is
    the arms-up pose from the quoted table, at the instant it hands the work back.
    """
    if not emits(art, "rSummon"):
        return ""
    s = SUMMON_B_SCALE
    c = CELL
    x = summon_bx(art)
    ty = GROUND - SPRITE_H * s
    sw = SPRITE_W * s
    # look-left, straight out of the pose table: the eye band shifts ONE cell and nothing else moves.
    # B stands to A's right, so look-left is B looking AT A — which is the only reason to pick a pose
    # over the default at all.
    eyes = "".join(
        f'<rect class="eyeHole" x="{k * c}" y="{2 * c}" width="{c}" height="{c}"/>'
        for k in (1, 7)
    )
    legs = "".join(
        f'<rect x="{k * c}" y="{6 * c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        for k in (1, 3, 7, 9)
    )
    arms_idle = (
        f'<rect x="0" y="{2 * c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        f'<rect x="{10 * c}" y="{2 * c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
    )
    # arms-up is the table's ONE whole-body pose and it translates on y only: 2c - 3c = -1c. No
    # horizontal component exists in the vocabulary, which is also why there is no wave anywhere here.
    arms_up = (
        f'<rect x="0" y="{-c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
        f'<rect x="{10 * c}" y="{-c}" width="{c}" height="{2 * c}" fill="{CLAWD}"/>'
    )
    return (
        f'<g class="smPeer">'
        # a contact shadow, static: without one a grounded creature reads as pasted on
        f'<ellipse class="sh" cx="{fmt(x + sw / 2)}" cy="{fmt(GROUND + 3)}" '
        f'rx="{fmt(sw * 0.44)}" ry="{fmt(7 * s)}"/>'
        f'<g transform="translate({fmt(x)} {fmt(ty)}) scale({fmt(s)})" '
        f'shape-rendering="crispEdges">'
        # arms before the body, as on A, so the body covers the shoulder joint
        f'<g class="smBArm">{arms_idle}</g>'
        f'<g class="smBUp">{arms_up}</g>'
        f'<rect x="{c}" y="0" width="{9 * c}" height="{6 * c}" fill="{CLAWD}"/>'
        f"{eyes}{legs}"
        f"</g></g>"
    )


def summon_burst_css(
    name: str, cls: str, win: tuple[float, float], cx: float, cy: float
) -> str:
    """One burst: ONE animation on ONE group, opacity and transform in the SAME keyframe block.

    Two declarations would be two animations on one element, which `banner-shots.sh --lint` rejects —
    and rightly: the freeze overrides delay on `*`, so the second one starts immediately and paints
    its value into frames it does not belong in. `steps(1,end)` because a burst on a pixel-art plate
    is four discrete stages, not a tween; an interpolated scale puts the dots on fractional pixels for
    the whole of it.
    """
    f0, f1 = win
    span = f1 - f0
    frames = [f"0%,{atf('rSummon', f0)}%{{opacity:0;transform:scale(.25)}}"]
    # The first VISIBLE stage lands at 3% of the burst, not 18%: at 18% the burst began a quarter of a
    # second after the hat appeared, so the hat popped on with nothing to cover it. A burst has to be
    # already bright at its own window start or it is not covering anything.
    for k, op, sc in (
        (0.03, 1.0, 0.5),
        (0.28, 1.0, 1.1),
        (0.55, 1.0, 1.6),
        (0.8, 0.5, 2.0),
    ):
        frames.append(
            f"{atf('rSummon', f0 + k * span)}%"
            f"{{opacity:{fmt(op)};transform:scale({fmt(sc)})}}"
        )
    frames.append(f"{atf('rSummon', f1)}%,100%{{opacity:0;transform:scale(.25)}}")
    return (
        f"@keyframes {name}{{{''.join(frames)}}}"
        f".{cls}{{animation:{name} {fmt(P)}s steps(1,end) infinite;"
        f"transform-origin:{fmt(cx)}px {fmt(cy)}px}}"
    )


def summon_travel_css(
    name: str, cls: str, marks: list[tuple[float, float, float, int]]
) -> str:
    """A prop crossing the gap in WHOLE-PIXEL steps: (fraction, dx, dy, opacity) per authored stop.

    `steps(1,end)` holds each stop and then jumps, so the prop is only ever at an authored position —
    which is what makes "integer art-pixel steps" true of what actually renders rather than of the
    intent. Opacity travels in the same block for the same one-animation-per-element reason as the
    bursts, and it is what lets a prop switch off while occluded instead of fading.
    """
    frames = ["0%{opacity:0}"]
    for f, dx, dy, op in marks:
        frames.append(
            f"{atf('rSummon', f)}%{{opacity:{op};"
            f"transform:translate({fmt(dx)}px,{fmt(dy)}px)}}"
        )
    frames.append("100%{opacity:0}")
    return (
        f"@keyframes {name}{{{''.join(frames)}}}"
        f".{cls}{{animation:{name} {fmt(P)}s steps(1,end) infinite}}"
    )


def summon_css(art: Art) -> str:
    """Every rule THE SUMMONING needs. Nine animations, nine elements, no element with two."""
    st = summon_steps(art)
    cx, cy = summon_burst_centre(art)
    dx, dy, sw = st["mail_dx"], st["mail_dy"], st["mail_swallow"]
    m0, m1 = SM_MAIL
    # six stops: four across the open gap, then two that carry the letter inside B's silhouette. The
    # last two are the exit — B takes it, rather than it evaporating in mid-plate.
    mail_marks = [
        (
            m0 + k * (m1 - m0) / 6,
            k * dx if k <= 4 else 4 * dx + (k - 4) * sw,
            min(k, 4) * dy,
            1,
        )
        for k in range(7)
    ]
    mail_marks.append((SM_MAIL_OFF, mail_marks[-1][1], mail_marks[-1][2], 0))
    c0, c1 = SM_CAKE
    cake_marks = [
        (c0 + k * (c1 - c0) / 4, (4 - k) * -st["cake_dx"], (4 - k) * -st["cake_dy"], 1)
        for k in range(5)
    ]
    cake_marks.append((SM_HELD_ON, 0.0, 0.0, 0))
    o0, o1 = SM_OCCLUDE
    held_marks = [(SM_HELD_ON, 0.0, 0.0, 1), (o0, 0.0, 0.0, 1)]
    held_marks += [
        (o0 + k * (o1 - o0) / 4, k * st["held_dx"], 0.0, 1) for k in range(1, 5)
    ]
    held_marks.append((SM_HELD_OFF, 4 * st["held_dx"], 0.0, 0))
    return "".join(
        [
            gate("smh", ".smHat", [(sm_at(SM_HAT_ON), sm_at(SM_HAT_OFF))]),
            gate("smb", ".smPeer", [(sm_at(SM_B_ON), sm_at(SM_B_OFF))]),
            # B's idle arms off while the raised pair is up, or B shows four arms — the same defect
            # that made A's cheer read as horns, and it is no less wrong on a smaller body.
            gate(
                "smba",
                ".smBArm",
                [(sm_at(SM_BUP[0]), sm_at(SM_BUP[1]))],
                on_inside=False,
            ),
            gate("smbu", ".smBUp", [(sm_at(SM_BUP[0]), sm_at(SM_BUP[1]))]),
            summon_burst_css("smsf", "smSpark", SM_SPARK, cx, cy),
            summon_burst_css("smpf", "smPoof", SM_POOF, cx, cy),
            summon_travel_css("smmf", "smMail", mail_marks),
            summon_travel_css("smcf", "smCake", cake_marks),
            summon_travel_css("smhf", "smHeld", held_marks),
        ]
    )


# ── stylesheet ────────────────────────────────────────────────────────────────────────────────────
def css(art: Art) -> str:
    d, l = art.dark, art.light
    cheering = emits(art, "rCheer")

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
        f".tf0,.tf1{{fill:{d.tuft}}}.fgb{{fill:{d.fg}}}.fpr{{fill:{d.fg};opacity:.55}}"
        # THE REFUSAL's barrier takes the GROUND RULE's own colour. It had no fill rule at all on
        # first render and therefore fell back to the SVG default of solid black, which against a
        # #1e2941 ground read as a hard graphic bracket pasted over the scene — and would have been
        # black-on-pale in the light scheme, where it is worse. Nothing here may be un-themed: a
        # missing fill does not error, it picks a colour from outside the palette.
        f".rfp{{fill:{d.rule};opacity:.9}}"
        f".ss{{fill:#f2f6ff}}.brd{{fill:{d.mound[0]}}}.bal{{fill:{CLAWD}}}.balStr{{stroke:none;fill:{CLAWD};opacity:.45}}"
        f".eyeHole{{fill:#1b1109}}.sh{{fill:#000;opacity:.46}}.zmk{{fill:{d.star}}}"
        # THE SUMMONING's palette. Which of these need a light-scheme override is decided by WHAT
        # THEY SIT ON, not by preference — the creature's #D77757 is a constant, so ink that lands on
        # the body is scheme-independent, and ink that lands on the sky or the ground plate is not.
        #   · the hat crosses the SKY, so it takes the rule colour — the one tone this file already
        #     trusts to read against both skies. A near-black crown vanishes into the night sky.
        #   · the envelope's EDGE lands on the ground plate and takes the foreground colour, which is
        #     the darkest tone in each scheme. Its pale face needs no override because the edge is
        #     what carries the read: pale-on-pale would be invisible in the light scheme alone.
        #   · the cake is SELF-contrasting (dark body / pale icing / amber candle), so it needs no
        #     override at all — which is the whole reason the brief specified an icing row.
        #   · the sparkle dots land on the ground plate, so they invert with it.
        f".smHat{{fill:{d.rule}}}"
        f".smMailE{{fill:{d.fg}}}.smMailF{{fill:#f4ead8}}"
        f".smCkB{{fill:#7a4a2e}}.smCkI{{fill:#f4ead8}}.smCkC{{fill:#e8b04b}}"
        f".smSpk{{fill:{d.star}}}"
        f".vig{{fill:url(#vig);opacity:{fmt(d.vignette)}}}" + cloudrules(d) +
        # ---- parallax: one shared translate, per-layer duration, all dividing P ----
        f"@keyframes sc{{from{{transform:translateX(0)}}to{{transform:translateX(-{TILE}px)}}}}"
        f".cl0{{animation:sc {fmt(P)}s linear infinite}}"
        f".cl1{{animation:sc {fmt(P / 2)}s linear infinite}}"
        f".cl2{{animation:sc {fmt(P / 3)}s linear infinite}}"
        f".md0s{{animation:sc {fmt(P / 2)}s linear infinite}}"
        f".md1s{{animation:sc {fmt(P / 4)}s linear infinite}}"
        f".tf0s{{animation:sc {fmt(P / 8)}s linear infinite}}"
        f".fprs{{animation:sc {fmt(STRIP_PERIOD)}s linear infinite}}"
        f".tf1s{{animation:sc {fmt(P / 10)}s linear infinite}}"
        f".fgbs{{animation:sc {fmt(P / 16)}s linear infinite}}"
        # a world-borne single object travels the whole loop's worth of ground in one pass
        f"@keyframes gsc{{from{{transform:translateX(0)}}"
        f"to{{transform:translateX(-{fmt(GROUND_TRAVEL)}px)}}}}"
        f".ovl,.rfPost{{animation:gsc {fmt(P)}s linear infinite}}" + warp_css() +
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
        # A hop every 12 s, not every 4 — an occasional hop is life, a constant one is a bob. The
        # period and the airborne window come from the HOP_* constants because
        # assert_hop_clear_of_stopped_world reads them: a hardcoded 12s here and a 12.0 there are two
        # copies of one fact, and the assertion would go on passing against a file it no longer
        # describes the moment either moved.
        f"@keyframes hpf{{0%,{fmt(HOP_FROM_PCT)}%{{transform:translateY(0)}}"
        f"{fmt(HOP_FROM_PCT + 6)}%{{transform:translateY(-30px)}}"
        f"{fmt(HOP_FROM_PCT + 12)}%{{transform:translateY(0)}}"
        f"{fmt(HOP_FROM_PCT + 16)}%{{transform:translateY(-9px)}}"
        f"{fmt(HOP_TO_PCT)}%,100%{{transform:translateY(0)}}}}"
        f".hop{{animation:hpf {fmt(HOP_PERIOD)}s cubic-bezier(.3,.05,.4,1) infinite}}"
        # the shadow squashes on the same clock — the cue that sells the hop as a jump
        f"@keyframes shf{{0%,{fmt(HOP_FROM_PCT)}%{{transform:scale(1,1);opacity:.46}}"
        f"{fmt(HOP_FROM_PCT + 6)}%{{transform:scale(.66,.5);opacity:.14}}"
        f"{fmt(HOP_FROM_PCT + 12)}%{{transform:scale(1,1);opacity:.46}}"
        f"{fmt(HOP_FROM_PCT + 16)}%{{transform:scale(.88,.8);opacity:.24}}"
        f"{fmt(HOP_TO_PCT)}%,100%{{transform:scale(1,1);opacity:.46}}}}"
        f".shdw{{animation:shf {fmt(HOP_PERIOD)}s cubic-bezier(.3,.05,.4,1) infinite;"
        f"transform-origin:"
        f"{fmt(art.clawd_x + SPRITE_W * art.clawd_scale / 2)}px {fmt(GROUND + 3)}px}}"
        # ---- rare emotes and world events ----
        # Every window below is DERIVED from RARE_EVENTS, which the build-time gate also reads, so a
        # stacked pair cannot be emitted. Hand-written percentages are what let the cheer land inside
        # the sleep. Every event runs on the full period, so each fires exactly ONCE per loop.
        + "".join(
            [
                # ---- THE ASK and THE REFUSAL: the creature's side of a stopped world ----
                # The stall windows are DERIVED from the world clock, never written twice. If they
                # were authored separately the legs could keep striding through a dead world — the
                # sliding defect the stride lock exists to kill — with every gate still green.
                gate("lwf", ".legsWalk", stopped_spans(), on_inside=False),
                gate("lsf", ".legsStill", stopped_spans()),
                # The stare and the ears belong to THE ASK only. A refusal is a settle, not a stare:
                # the creature is trying to end its turn, not waiting on anybody.
                gate("lgf", ".lookGate", [ask_stop()], on_inside=False),
                gate("eaf", ".eyesAsk", [ask_stop()]),
                gate("aaf", ".armsAlert", [ask_stop()]),
                # ...and the stare BLINKS, three times, inside the gate that shows it. This is the
                # ONLY thing moving through the dead world, which is the whole job: it separates a
                # stopped world from a stopped renderer. It costs no world rate, so nothing is owed
                # back and the print lock is untouched.
                gate("abo", ".aOpen", ask_blinks(), on_inside=False),
                gate("abc", ".aShut", ask_blinks()),
                # The idle side-arms must be OFF while the ask's alert pair is up, or the sprite
                # shows four arms at once — two at the sides and two raised — which is most of why a
                # raised pair reads as horns. The gate cannot go on `.armsIdle` itself because that
                # element already carries the wiggle and only one animation per element survives the
                # freeze (S8), so it is a nested wrapper: gate outside, wiggle inside.
                gate(
                    "agf",
                    ".armsGate",
                    [ev("rCheer"), ask_stop()] if cheering else [ask_stop()],
                    on_inside=False,
                ),
                # the barrier: retracted at the post's head, down across the path, retracted again.
                f"@keyframes rbf{{0%,{at('rRefuse', 0)}%{{transform:translateY(0)}}"
                f"{at('rRefuse', BAR_AT)}%,{at('rRefuse', BAR_UP_AT)}%"
                f"{{transform:translateY({fmt(BAR_DROP)}px)}}"
                f"{at('rRefuse', BAR_UP_AT + 0.4)}%,100%{{transform:translateY(0)}}}}"
                f".rfBar{{animation:rbf {fmt(P)}s ease-in-out infinite}}",
                # ---- the visitor beats ----
                # Offsets are FRACTIONS of the declared window, never absolute seconds. They used to
                # be seconds — `+14`, `-16` — carried over from a much longer window, so on a 9 s
                # peer they resolved to NEGATIVE percentages. A keyframe block with an invalid
                # selector is dropped whole, so v6b shipped with a peer that never stopped beside the
                # resident and a cheer that never fired at all: no error, no blank frame, just a beat
                # silently absent from the candidate built to showcase it.
                f"@keyframes pkf{{0%,{atf('peek', 0)}%{{transform:translateY(78px)}}"
                f"{atf('peek', 0.45)}%,{atf('peek', 0.55)}%{{transform:translateY(0)}}"
                f"{atf('peek', 1)}%,100%{{transform:translateY(78px)}}}}"
                f".peek{{animation:pkf {fmt(P)}s ease-in-out infinite}}",
                # It arrives from the right, holds beside the resident, and RETURNS THE WAY IT CAME.
                # It used to exit leftwards THROUGH the resident: same flat #D77757, crispEdges,
                # drawn above, so its blank body slid over the face and erased the eyes — two
                # same-colour sprites merging into one connected orange region, which reads as a
                # rendering error, or worse as one session absorbing another (the handoff
                # infographic R1 rejected, acted out). A symmetric exit reads as intent, not despawn.
                f"@keyframes prf{{0%,{atf('peer', 0)}%"
                f"{{opacity:0;transform:translateX({W + 240}px)}}"
                f"{atf('peer', 0.06)}%{{opacity:1}}"
                f"{atf('peer', 0.24)}%,{atf('peer', 0.76)}%"
                f"{{transform:translateX({fmt(art.clawd_x + SPRITE_W * art.clawd_scale + 46)}px)}}"
                f"{atf('peer', 0.96)}%{{opacity:1;transform:translateX({W + 240}px)}}"
                f"{atf('peer', 1)}%,100%{{opacity:0;transform:translateX({W + 240}px)}}}}"
                f".peer{{animation:prf {fmt(P)}s linear infinite}}",
                # NOTE: there is deliberately no scaleX flip on the peer. The sprite is bilaterally
                # symmetric — eyes at 40-60 and 160-180 about centre 110 — so scaleX(-1) maps it onto
                # itself and the "turn to face" beat was invisible by construction. It existed only in
                # the code. Direction now reads from travel alone, which is honest.
                f"@keyframes pcf{{0%,{atf('peer', 0.34)}%{{opacity:0}}"
                f"{atf('peer', 0.36)}%,{atf('peer', 0.66)}%{{opacity:1}}"
                f"{atf('peer', 0.68)}%,100%{{opacity:0}}}}"
                f".pCheer{{animation:pcf {fmt(P)}s steps(1,end) infinite}}",
            ]
            # The cheer's gate and the cheer's element appear and disappear together — an element
            # with no gate is not hidden, it is permanently ON, and a gate with no element is a
            # keyframe block nothing reads. Withdrawing the beat has to drop BOTH halves.
            + ([gate("rcf", ".rCheer", [ev("rCheer")])] if cheering else [])
            # ---- THE SUMMONING ----
            # Same rule as the cheer: element and gate ship together or not at all. Every window in
            # here is a FRACTION of the declared rSummon window, so re-timing the beat moves the whole
            # choreography with it and no offset can run off the end into a negative percentage.
            + ([summon_css(art)] if emits(art, "rSummon") else [])
        )
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
        ".rCheer,.legsStill,.eShut,.aShut,.peer,.pCheer,.eyesAsk,.armsAlert{opacity:0}"
        ".legsWalk,.eOpen,.aOpen,.armsGate,.lookGate{opacity:1}"
        # THE SUMMONING resolves to BEFORE it happened, not to the middle of it. `animation:none`
        # reverts each element to its un-animated base, which for every one of these is opacity 1 —
        # so the frozen still would otherwise show the hat on, both cakes at once, the letter in
        # mid-air and two bursts at rest scale. The one thing a still must never be is a frame that
        # could not occur.
        ".smHat,.smPeer,.smBUp,.smSpark,.smPoof,.smMail,.smCake,.smHeld{opacity:0}"
        ".smBArm{opacity:1}"
        # The barrier rests RETRACTED. `animation:none` already leaves it there (translateY(0) is its
        # un-animated base), but the still is the deliverable, so it is pinned rather than inferred —
        # the same reasoning as the moon halo below, which was blown out for exactly that assumption.
        ".rfBar{transform:translateY(0)}"
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
        f".tf0,.tf1{{fill:{l.tuft}}}.fgb{{fill:{l.fg}}}.fpr{{fill:{l.fg};opacity:.40}}"
        f".rfp{{fill:{l.rule};opacity:.9}}"
        f".brd{{fill:{l.mound[0]}}}.sh{{opacity:.20}}"
        f".smHat{{fill:{l.rule}}}.smMailE{{fill:{l.fg}}}.smSpk{{fill:{l.fg}}}"
        f".vig{{opacity:{fmt(l.vignette)}}}" + cloudrules(l) + "}"
    )
    # Day/night switching is done with `display` on a parent group, so no element ever needs both a
    # theme rule and an animation on the same property (which is what S8 forbids).
    daynight = ".dOnly{display:none}.nOnly{display:block}"

    return base + daynight + reduced + light


# ── assembly ──────────────────────────────────────────────────────────────────────────────────────
def build(art: Art) -> str:
    _SCROLLING.clear()
    _WARPED.clear()
    _LAYER_PERIOD.clear()
    _ENCODED_STRIP.clear()
    assert_all_gates_wired()
    assert_texture_not_eventised()
    assert_event_names_known(art)
    assert_events_disjoint(art)
    assert_stride_locked(art)
    assert_duty_budget(art)
    assert_world_rates_integral()
    assert_world_inside_windows()
    assert_world_balanced()
    assert_warp_within_tile()
    assert_hop_clear_of_stopped_world(art)
    assert_summon_on_grid(art)
    assert_summon_clear_plate(art)
    rng = random.Random(20260729 + sum(ord(ch) for ch in art.key))
    scale = art.clawd_scale

    defs = (
        sky_defs(art)
        + moon(art)
        + f'<clipPath id="belowGround"><rect x="0" y="0" width="{W}" height="{GROUND}"/></clipPath>'
    )

    sun_cx, sun_cy, sun_r = art.moon
    day_sun = (
        f'<g class="dOnly">'
        f'<circle cx="{fmt(sun_cx)}" cy="{fmt(sun_cy)}" r="{fmt(sun_r * 3.1)}" '
        f'fill="url(#halo)" opacity=".5"/>'
        f'<circle class="mdisc" cx="{fmt(sun_cx)}" cy="{fmt(sun_cy)}" r="{fmt(sun_r * 0.92)}" '
        f'opacity=".9"/></g>'
    )

    # The SCENE is composed before the stylesheet, because emitting a scrolling layer is what
    # registers its speed for a warp animation. Generating the CSS first would have produced a
    # stylesheet with no warp rules at all — every gate still green, the beats simply absent.
    scene = [
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
        footprints(art),
        # THE OVERLAP rides at the footprints' own z, because it IS footprints — see print_ink
        overlap_run(art),
        peek(art),
        ground_detail(art),
        # THE REFUSAL's barrier stands on the ground, so it goes over the ground texture and under
        # the creature
        refusal_gate(art),
        f'<line x1="0" y1="{GROUND}" x2="{W}" y2="{GROUND}" class="rl" stroke-width="3" '
        f'stroke-dasharray="3 9" stroke-linecap="round" opacity=".72"/>',
        # THE SUMMONING, in paint order: bursts and travelling props UNDER both creatures, so each
        # prop's exit is an OCCLUSION rather than a pop — the letter's last steps carry it inside B,
        # the cake hands off to a copy inside A. Over a body, either one would erase a face, which is
        # v6b's rejected peer in miniature.
        summon_props(art),
        summon_peer(art),
        summon_bursts(art),
        clawd_placed(art, art.clawd_x, scale),
    ]

    if art.second_clawd:
        scene.append(second_session(art))

    # vignette BEFORE the type: focuses the frame without ever touching the wordmark
    scene.append(f'<rect class="vig" width="{W}" height="{H}"/>')

    # the type, last — nothing can be over it
    scene.append(
        f'<text x="{W // 2}" y="140" text-anchor="middle" class="wm" '
        f'font-family="ui-monospace,SFMono-Regular,Menlo,monospace" font-size="62" '
        f'letter-spacing="1.5">claude-infrastructure</text>'
    )
    if art.hairline:
        scene.append(
            f'<rect class="sub" x="{W // 2 - 132}" y="163" width="264" height="1" '
            f'opacity=".28"/>'
        )
    scene.append(
        f'<text x="{W // 2}" y="{188 if art.hairline else 182}" text-anchor="middle" class="sub" '
        f'font-family="ui-monospace,SFMono-Regular,Menlo,monospace" font-size="17" '
        f'letter-spacing="7.5">{art.subtitle}</text>'
    )
    assert_type_clear()

    # Now the stylesheet, which needs every warped layer to have been registered above.
    sheet = css(art)
    assert_keyframe_pcts_sane(art, sheet)
    assert_warp_matches_scroll(art, sheet)
    assert_every_shape_is_themed(art, sheet, "".join(scene), defs)
    assert_print_lock(art, _ENCODED_STRIP)
    assert_one_strip_feature(art)
    assert_overlap_ink_is_ambient(art)

    return "".join(
        [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" '
            f'height="{H}" role="img" aria-label="claude-infrastructure — the Claude Code creature '
            f'walking a looping landscape under drifting clouds">',
            "<title>claude-infrastructure</title>",
            f"<desc>{art.title}. {art.blurb} One 240-second loop; the wordmark is legible at every "
            f"instant and nothing passes behind it.</desc>",
            f"<style>{sheet}</style>",
            f"<defs>{defs}</defs>",
            *scene,
            "</svg>",
        ]
    )


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
        # The visitor is HELD, not deleted — operator ruling on the artifact, "silly"
        # (BANNER_NARRATIVE_SPEC.md § OPERATOR RULINGS). Only half of that ruling had been applied:
        # the beat was demoted to t=48.5 and left EMITTING, so the shipped pick still carried a beat
        # its owner had withdrawn. A demotion is not a withdrawal — past t=45s a beat is unseen by
        # most readers, which hides it from review without removing it from the file.
        # The machinery stays whole (RARE_EVENTS, the emitters, the collision partner entry); putting
        # "peek" back in this tuple is the entire restoration.
        events=(),
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
