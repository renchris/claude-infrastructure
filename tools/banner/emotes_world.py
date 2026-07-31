#!/usr/bin/env python3
"""emotes_world.py — the WORLD pack: eight candidates about the creature and everything that is not it.

One category per module, per `emotes.load_packs`. The reactions pack owns the creature's own body;
this one owns the opposite half — a prop it can act on, a piece of ground it can change, and other
clawds arriving and leaving. Nothing in here is a feeling.

TWO LAWS SHAPE EVERY CANDIDATE BELOW, and both are prohibitions rather than preferences.

NO CONNECTOR MAY EVER BE DRAWN BETWEEN TWO CREATURES. No thread, no arc, no travelling pulse, no
arrow. A prior operator ruling rejected the banner reading as a handoff diagram, and a drawn link
rebuilds exactly that infographic out of two sprites and a line. So relationship here is carried by
four legal channels only: CO-LOCATION (they are in the same frame), SYNCHRONY (they act on the same
frame), SUCCESSION (one leaves, one arrives, the state persists), and INDIRECTION (both act on the
same piece of world). THE GREETING, THE FOLLOWER and THE HANDOVER are each built on exactly one of
those and would be trivial — and illegal — with a line.

A VISITOR LEAVES BY MOTION OR BY AN OCCLUDER, NEVER BY AN OPACITY FADE. A fade is the observer
losing information; it is not the object doing anything. `_peek_burrow` in the framework records the
same rule and the same remedy. The occluders used below are the frame edges (THE GREETING, THE
HANDOVER, THE MOTE), the ground line via a clip path (THE FOLLOWER), a mound drawn in front (THE
SHY), and one creature's own body (THE HANDOVER's block).

WHAT A SECOND CREATURE COSTS, measured rather than assumed. `gen.clawd_sprite` names its groups
GLOBALLY — `.bob`, `.legA`, `.legsStill` — and a suffix produces `.bobB`, `.legAB`, `.legsStillB`.
Two consequences, and the framework's own gates catch NEITHER of them, because
`assert_reset_covers_sprite` matches `class="legsStill` as a PREFIX and is satisfied by the
unsuffixed rule in `base_css`:

    1. UNDRIVEN — nothing in `base_css` animates a suffixed class, so a second creature stands
       perfectly inert while the resident walks.
    2. UNRESET — and worse, `base_css`'s 0% reset list does not name them either, so `.legsStillB`,
       `.eShutB`, `.armsAlertB` and `.eyesAskB` are all ON for the whole loop: a visitor with both
       leg sets at once, blink-lids painted over its open eyes, ears permanently raised, and the
       ask-pose's centred eyes stacked on top of the normal pair.

`sfx_rest()` below exists for (2) and `sfx_walk()` for (1), and every candidate here that draws a
second creature calls both. This was found by rendering, not by reading.

    python3 tools/banner/emotes.py --out /tmp/emotes-world
"""

from __future__ import annotations

# The framework aliases itself into `sys.modules['emotes']` before importing any pack, so this binds
# to the RUNNING module object and its live `EMOTES` registry. That guarantee is load-bearing rather
# than incidental: `emotes.py` is the entrypoint as well as the framework, so before the alias
# existed a plain `import emotes` built a SECOND module object with its own empty registry and every
# candidate below registered into a list nobody rendered. Measured here before a line of art was
# written — a one-candidate probe pack built cleanly and printed eleven candidates, none of them the
# probe — and `emotes.load_packs` now asserts the two objects are identical.
import emotes as fw

gen = fw.gen
Emote = fw.Emote
emote = fw.emote
egate = fw.egate
squash = fw.squash
shift = fw.shift
stop_world = fw.stop_world
clawd = fw.clawd
w = fw.w
wp = fw.wp
pctx = fw.pctx
fmt = fw.fmt
EMOTE_P = fw.EMOTE_P
E_GROUND = fw.E_GROUND
STAGE_W = fw.STAGE_W
CLAWD_SCALE = fw.CLAWD_SCALE
PRINT_TILE = fw.PRINT_TILE
STRIDE = fw.STRIDE

C = gen.CELL  # 20 user units per sprite cell
HEAD_Y = (
    E_GROUND - gen.SPRITE_H * CLAWD_SCALE
)  # 138 — the top of the resting silhouette


# ── shared machinery ──────────────────────────────────────────────────────────────────────────────
# A NOTE ON `shift`, paid for once already. Its frames are `(time, dx, dy)` — X BEFORE Y — and every
# vertical move in this pack was first authored as `(t, -26, 0)`, which is a sideways slide. Five
# candidates shipped a horizontal hop, a horizontal spring, a horizontal step-over, a horizontal
# set-down dip and a horizontal "synchronised bounce" that moved neither creature up by a pixel. The
# tell was not in the code, which reads perfectly: it was a measured 2 px of crown travel across the
# bounce frames, and that 2 px turned out to be the ambient `.bob`. Measure the axis you meant.
def world_locked(name: str, sel: str, t0: float, t1: float) -> str:
    """Give any prop the ground plane's own travel: left at STRIP_V, frozen between t0 and t1.

    Identical arithmetic to `stop_world`, which is the point — a stone that scrolls at anything other
    than the dashed rule's rate is not lying on the ground, it is sliding across it. `stop_world`
    hardcodes the `.escroll` selector because it IS the world; this takes a selector so one prop can
    ride the same clock.

    The consequence worth stating out loud: a prop is DISPLACED by -PRINT_TILE*t0 for the whole
    frozen span, so the position it appears to have during the story is NOT the x in its markup.
    Every caller below computes its authored x from where it wants the prop to be at t0.
    """
    v = PRINT_TILE
    return (
        f"@keyframes {name}{{"
        f"0%{{transform:translateX(0)}}"
        f"{pctx(t0)}%{{transform:translateX(-{fmt(v * t0)}px)}}"
        f"{pctx(t1)}%{{transform:translateX(-{fmt(v * t0)}px)}}"
        f"100%{{transform:translateX(-{fmt(v * (EMOTE_P - (t1 - t0)))}px)}}}}"
        f"{sel}{{animation:{name} {fmt(EMOTE_P)}s linear infinite}}"
    )


def sfx_rest(sfx: str, walking: bool, cheer: bool = False) -> str:
    """The 0% reset list, for a SUFFIXED sprite. Static rules, no animation, no exceptions.

    `base_css`'s reset covers `.legsStill`, `.eShut`, `.eyesAsk`, `.armsAlert` and the rest — every
    one of them UNSUFFIXED. A second creature's copies are therefore ungated, and an ungated group is
    not hidden, it is ON. Four visible defects at once, none of which any gate in `emotes.py` can
    see: `assert_reset_covers_sprite` tests `class="legsStill` as a PREFIX, and the unsuffixed rule
    in `base_css` already satisfies it.
    """
    off = [f".eShut{sfx}", f".aShut{sfx}", f".eyesAsk{sfx}", f".armsAlert{sfx}"]
    on = [f".eOpen{sfx}", f".aOpen{sfx}", f".armsGate{sfx}", f".lookGate{sfx}"]
    if (
        cheer
    ):  # only drawn when the candidate declares rCheer — and then for BOTH creatures
        off.append(f".rCheer{sfx}")
    (on if walking else off).append(f".legsWalk{sfx}")
    (off if walking else on).append(f".legsStill{sfx}")
    return f"{','.join(off)}{{opacity:0}}{','.join(on)}{{opacity:1}}"


def sfx_walk(sfx: str) -> str:
    """Bind a suffixed sprite's legs and bob to the SHARED stride keyframes from `base_css`.

    Reusing `ewA`/`ewB`/`ebob` rather than minting a private copy is what keeps a second creature in
    phase with the resident for free — and phase is not cosmetic here. THE HANDOVER's loop closes on
    the successor standing in the resident's place with the resident's exact leg phase, and that only
    holds because both are ticking off one clock. Valid only on a `walks=True` candidate: `base_css`
    emits these keyframes only then, and a rule naming a keyframes block that does not exist animates
    nothing at all.
    """
    return (
        f".legA{sfx}{{animation:ewA {fmt(STRIDE)}s steps(1,end) infinite}}"
        f".legB{sfx}{{animation:ewB {fmt(STRIDE)}s steps(1,end) infinite}}"
        f".bob{sfx}{{animation:ebob {fmt(STRIDE)}s steps(1,end) infinite}}"
    )


def converging_stride(
    name: str, sel: str, amp: float, t0: float, t1: float, invert: bool = False
) -> str:
    """A square-wave leg track whose PHASE slides from antiphase into the resident's, across t0..t1.

    This is THE FOLLOWER's entire showcase, and it cannot be done with `animation-delay`: the
    deterministic freeze in `banner-shots.sh` overrides `animation-delay` on `*` to seek a timestamp,
    so an authored delay is both refused by `--lint` and silently wrong in every reference render.
    The phase therefore has to live in the keyframe percentages, which means writing all twenty-four
    strides out and shrinking the offset on each one.

    It lands EXACTLY in phase, on purpose: the final stride's toggles fall on 11.5 s and 11.75 s,
    which is where the resident's 0.5 s `ewA` puts its own, so the wrap is silent.
    """
    hi = 0.0 if invert else -amp
    lo = -amp if invert else 0.0
    frames = [f"0%{{transform:translateY({fmt(lo)}px)}}"]
    k = 0
    while k * STRIDE < EMOTE_P:
        base = k * STRIDE
        f = 0.0 if base <= t0 else 1.0 if base >= t1 else (base - t0) / (t1 - t0)
        p = (STRIDE / 2) * (
            1 - f
        )  # a half-step out at the start, dead in phase at the end
        for t, v in ((base + p, lo), (base + STRIDE / 2 + p, hi)):
            if 0 < t < EMOTE_P:
                frames.append(f"{pctx(t)}%{{transform:translateY({fmt(v)}px)}}")
        k += 1
    frames.append(f"100%{{transform:translateY({fmt(lo)}px)}}")
    return (
        f"@keyframes {name}{{{''.join(frames)}}}"
        f"{sel}{{animation:{name} {fmt(EMOTE_P)}s steps(1,end) infinite}}"
    )


def dome(cx: float, half_w: float, height: float, cell: float = 8.0) -> str:
    """A low mound sitting on the ground rule, quantised to `cell` and sealed by `gen.merge_runs`.

    Quantised because the stage's own ridges are, and a smooth curve beside them reads as a different
    material. Sealed because abutting rects do not composite to full coverage — the shared edge lands
    inside a device pixel and leaves a hairline of whatever is behind showing through, which is the
    striped horizon `stage_scenery` records fixing once already.
    """
    cols = max(int(half_w * 2 / cell), 2)
    cells = []
    for i in range(cols):
        f = (i + 0.5) / cols * 2 - 1  # -1..1 across the dome
        h = round(height * max(0.0, 1 - f * f) ** 0.55 / cell) * cell
        if h > 0:
            cells.append((cx - half_w + i * cell, E_GROUND - h, cell, h + 6))
    return "".join(
        f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(wd)}" height="{fmt(ht)}"/>'
        for x, y, wd, ht in gen.merge_runs(cells)
    )


def below_ground_clip(cid: str, body: str) -> str:
    """Everything in `body`, cut off at the ground rule — the framework's own occluder, widened.

    `_peek_burrow` uses a narrow version of this for its shaft. Widened it becomes a HORIZON: a
    visitor translated down past its own height is gone, and gone by occlusion rather than by fade.
    Deliberately far wider than the stage so that only the Y edge does any work.
    """
    return (
        f'<clipPath id="{cid}">'
        f'<rect x="-500" y="-500" width="{fmt(STAGE_W + 1000)}" height="{fmt(E_GROUND + 500)}"/>'
        f"</clipPath>"
        f'<g clip-path="url(#{cid})">{body}</g>'
    )


# ── THE PEBBLE ────────────────────────────────────────────────────────────────────────────────────
def _pebble() -> Emote:
    """A prop that was already in the world, acted on once, and then left behind.

    The stone is WORLD-LOCKED rather than pinned to the stage, and that buys the third act for
    nothing: once the ground moves again the stone drifts back past the creature and off the left
    edge, and 'it ambles after it' is that drift read in the frame's own convention. It also means
    the stone enters and leaves off-frame, so nothing ever pops.
    """
    e = emote(
        Emote(
            key="pebble",
            title="THE PEBBLE",
            category="The world",
            entry="a small stone comes up the ground with the world, and the stride stops beside it",
            showcase="the body shunts forward once and the stone rolls a short way, slowing to a stop",
            exit="the walk picks up, the ground moves again, and the stone drifts back past its feet",
            window=(3.2, 7.6),
            cls="BEAT",
            tie="",
            # Off-centre on purpose, and the offset is solved rather than chosen. A world-locked
            # prop has to be off-frame at BOTH ends of the loop or it pops at the wrap, and those
            # are two inequalities pulling opposite ways: the stone's authored x must clear the
            # right edge at 0 %, and that same x plus the roll minus a loop's worth of travel must
            # clear the left edge at 100 %. The first draft satisfied only the second, and the stone
            # blinked into existence at the right edge once every twelve seconds — invisible in any
            # single frame, which is why the arithmetic caught it and the contact sheet did not.
            # Solved together they fix cx, the rest position and the 2.0 s stop simultaneously.
            cx=210.0,
        )
    )
    a, b = e.window
    back = (
        b - 2.4
    )  # the world restarts well before the story ends — the amble IS the third act
    # Authored so the stone is at the toe at `a`. The world track has already carried it
    # -PRINT_TILE*a by then, so the markup x is that displacement added back on.
    rest_x = 462.0  # 12 px clear of the front foot, which ends at 450
    roll = 130.0  # …to 592; authored at 769, so off BOTH edges at 0 % and at 100 %
    art_x = rest_x + PRINT_TILE * a

    def props() -> str:
        # Three rects rather than one: a lone square at this size is a dropped pixel, and the stepped
        # corner is the only thing that says 'stone' rather than 'block'.
        stone = (
            f'<rect x="{fmt(art_x + 5)}" y="{fmt(E_GROUND - 16)}" width="12" height="5"/>'
            f'<rect x="{fmt(art_x)}" y="{fmt(E_GROUND - 11)}" width="22" height="6"/>'
            f'<rect x="{fmt(art_x + 3)}" y="{fmt(E_GROUND - 5)}" width="16" height="5"/>'
        )
        return f'<g class="pbW"><g class="pbRoll"><g class="efg">{stone}</g></g></g>'

    def css() -> str:
        return (
            stop_world("pbScr", a, back)
            + world_locked("pbW", ".pbW", a, back)
            + egate("pbStill", ".legsStill", [(a, back)])
            + egate("pbWalk", ".legsWalk", [(a, back)], on_inside=False)
            # The roll leaves on the SAME frame the body shunts, and `ease-out` between those two
            # keyframes IS the deceleration. Something that coasts at one speed and then stops is a
            # slide; a thing that is struck once decelerates.
            + f"@keyframes pbR{{0%,{wp(e, 0.16)}%{{transform:translateX(0)}}"
            f"{wp(e, 0.43)}%{{transform:translateX({fmt(roll)}px)}}"
            f"100%{{transform:translateX({fmt(roll)}px)}}}}"
            f".pbRoll{{animation:pbR {fmt(EMOTE_P)}s ease-out infinite}}"
            # The nudge has to be whole-body: the legs are drawn as two interleaved PAIRS that cannot
            # be split without redrawing the sprite, so there is no single foot to swing. A forward
            # shunt against a stopped world is the largest unambiguous 'it pushed that' available —
            # and forward is legible because the ground, not the silhouette, supplies the direction.
            + shift(
                "pbSh",
                ".rTurn",
                [
                    (0, 0, 0),
                    (a, 0, 0),
                    (w(e, 0.10), -7, 0),  # loads back a third of a cell first
                    (w(e, 0.16), 16, 0),  # …and drives forward on the contact frame
                    (w(e, 0.30), 9, 0),
                    (w(e, 0.55), 0, 0),
                    (b, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
            + squash(
                "pbB",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.10), 1.06, 0.94),
                    (w(e, 0.16), 0.97, 1.05),
                    (w(e, 0.30), 1.02, 0.98),
                    (w(e, 0.48), 1, 1),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
        )

    e.props, e.css = props, css
    return e


# ── THE SNIFF ─────────────────────────────────────────────────────────────────────────────────────
def _sniff() -> Emote:
    """One held pose. The whole candidate is the HOLD — 2.3 s of being interested in one spot.

    THE YAWN's lesson applied at the other end of the body: a posture change that lasts 120 ms is a
    flicker nobody parses, and the same change held past comfort becomes an act of attention. Nothing
    else in the frame moves during it, because the world is stopped for the duration.
    """
    e = emote(
        Emote(
            key="sniff",
            title="THE SNIFF",
            category="The world",
            entry="a scuffed patch of earth arrives with the ground and the stride stops over it",
            showcase="the body presses down onto the rule and leans in, and holds there examining it",
            exit="it springs back up off the ground in one small hop and the walk resumes",
            window=(3.0, 7.2),
            cls="BEAT",
            tie="",
            # Right of centre so the scuff can be authored off the right edge and still sit under
            # the body when the creature reaches it — the same both-ends-off-frame constraint THE
            # PEBBLE solves, with the same consequence for where the creature has to stand.
            cx=300.0,
        )
    )
    a, b = e.window
    back = b - 1.2
    mark_x = (
        474.0 + PRINT_TILE * a
    )  # 762 — off the right edge at 0 %, under the body at `a`

    def props() -> str:
        marks = "".join(
            f'<rect x="{fmt(mark_x + dx)}" y="{fmt(E_GROUND - dh)}" '
            f'width="{fmt(wd)}" height="{fmt(dh + 3)}"/>'
            for dx, wd, dh in (
                (0, 14, 4),
                (18, 9, 8),
                (31, 17, 5),
                (52, 11, 8),
                (67, 14, 4),
            )
        )
        return f'<g class="snW"><g class="efg">{marks}</g></g>'

    def css() -> str:
        return (
            stop_world("snfScr", a, back)
            + world_locked("snW", ".snW", a, back)
            + egate("snfStill", ".legsStill", [(a, back)])
            + egate("snfWalk", ".legsWalk", [(a, back)], on_inside=False)
            # Down, and only down: the squash origin is pinned at the feet, so scaling y to .85 drops
            # the crown 29 px while the soles stay welded to the rule. A translate would take the
            # legs through the ground plane instead, which reads as sinking rather than as stooping.
            + squash(
                "snfB",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.07), 0.98, 1.03),  # a small rise to load the drop
                    (w(e, 0.17), 1.13, 0.85),  # DOWN — and it stays there
                    (w(e, 0.72), 1.12, 0.86),
                    (w(e, 0.78), 1.05, 0.96),
                    (w(e, 0.84), 0.95, 1.06),  # the spring
                    (w(e, 0.93), 1.03, 0.98),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
            # The lean is forward — with travel — and the ground supplies that direction even though
            # the silhouette cannot. Held for the same 2.3 s as the crouch, so the two read as one
            # committed pose rather than as two events that happen to overlap.
            + shift(
                "snfLean",
                ".rTurn",
                [
                    (0, 0, 0),
                    (a, 0, 0),
                    (w(e, 0.17), 13, 0),
                    (w(e, 0.72), 13, 0),
                    (w(e, 0.84), -3, 0),
                    (w(e, 0.95), 0, 0),
                    (b, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
            # The hop goes on `.hop`, which nothing in the framework touches. The squash cannot do it:
            # its origin is at the feet, so it can only ever make the body shorter, never airborne.
            + shift(
                "snfHop",
                ".hop",
                [
                    (0, 0, 0),
                    (w(e, 0.80), 0, 0),
                    (w(e, 0.86), 0, -26),
                    (w(e, 0.91), 0, -20),
                    (w(e, 0.96), 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
        )

    e.props, e.css = props, css
    return e


# ── THE DIG ───────────────────────────────────────────────────────────────────────────────────────
def _dig() -> Emote:
    """The only candidate here that CHANGES the world and leaves the change behind.

    That persistence is the idea: five strokes on their own are a wobble, and it is the hole
    surviving them — and then travelling off with the ground, still open — that makes this an event
    rather than a movement. The hole is nested gate-outside / world-track-inside for the usual
    reason: one animation per element, and it needs both an existence and a travel.
    """
    e = emote(
        Emote(
            key="dig",
            title="THE DIG",
            category="The world",
            entry="the walk quits and the body drops into a crouch over one spot",
            showcase="five fast strokes, each throwing a crumb of earth up and back behind it",
            exit="a hole is left open in the ground; it steps clear and the world carries it away",
            window=(2.8, 7.2),
            cls="BEAT",
            tie="a worktree torn down — the ground it worked on is still there afterwards",
        )
    )
    a, b = e.window
    back = b - 1.0
    dug = w(e, 0.41)  # the hole exists from the third stroke on
    # Centred between the two leg pairs, so it is digging UNDER itself rather than at something out
    # in front. The authored x carries the frozen world displacement, as ever.
    dig_cx = 380.0  # where the digging APPEARS to happen, on the frozen stage
    hole_cx = (
        dig_cx + PRINT_TILE * a
    )  # …and where the hole is AUTHORED, inside the world group
    strokes = [w(e, 0.14 + i * 0.055) for i in range(5)]

    def props() -> str:
        rim = "".join(
            f'<rect x="{fmt(hole_cx + dx)}" y="{fmt(E_GROUND - dh)}" '
            f'width="{fmt(wd)}" height="{fmt(dh + 4)}"/>'
            for dx, wd, dh in ((-48, 13, 5), (-35, 11, 9), (24, 11, 9), (36, 13, 5))
        )
        hole = (
            f'<g class="eink">{rim}</g>'
            f'<ellipse class="efg" cx="{fmt(hole_cx)}" cy="{fmt(E_GROUND + 1)}" rx="40" ry="8"/>'
        )
        return f'<g class="dgHole"><g class="dgW">{hole}</g></g>'

    def front() -> str:
        # The crumbs are NOT world-locked — each lives 0.4 s inside a frozen world, so a travel
        # track would be four decimal places of nothing — and they are therefore authored at
        # `dig_cx`, the SCREEN position, while the hole is authored at `hole_cx`, which carries the
        # world group's -PRINT_TILE*a displacement. Using one number for both put the spray 269 px
        # to the right of its own hole. The arithmetic is correct only for whichever of the two
        # groups the value was computed for, and the render is the only thing that says which.
        #
        # They are also drawn in FRONT rather than with the rest of the props, which is the second
        # thing the render corrected. Behind, the entire arc lands inside the body's own 272..488 by
        # 138..282 rectangle and is occluded by the creature doing the throwing — the spray survived
        # as two specks in the gap between the legs. Earth passing in front of an animal digging
        # under itself is what actually happens, and this is the only plane where it survives.
        crumbs = "".join(
            f'<rect class="dgC{i}" x="{fmt(dig_cx - 8 - i * 5)}" y="{fmt(E_GROUND - 12)}" '
            f'width="16" height="16"/>'
            for i in range(5)
        )
        return f'<g class="eink">{crumbs}</g>'

    def css() -> str:
        # Five strokes on `.bob`: down-up, down-up, 0.24 s a pair. Fast enough to read as scrabbling
        # rather than as five separate crouches, which is what a 0.5 s pair looked like.
        #
        # The squash ALONE did not read. At the +-15 % the framework allows, five 12 % pulses on a
        # flat-coloured body are a shimmer, and the first contact sheet showed the stroke frames as
        # indistinguishable from rest. So the strokes are doubled onto `.rTurn` as a horizontal ROCK
        # — a real displacement of the whole silhouette, back on the drive and forward on the
        # recovery, which is what a digging animal actually does and what the eye actually catches.
        # It cannot be a vertical pump: `.hop` moves the feet too, and 14 px down puts the soles
        # through the ground plane.
        pump: list[tuple[float, float, float]] = [
            (0, 1, 1),
            (a, 1, 1),
            (w(e, 0.09), 1.07, 0.92),
        ]
        for t in strokes:
            pump += [(t, 1.11, 0.88), (t + 0.12, 1.01, 0.99)]
        pump += [
            (w(e, 0.50), 1.05, 0.94),
            (w(e, 0.62), 0.97, 1.04),  # stands back up off the hole
            (w(e, 0.72), 1.02, 0.98),
            (w(e, 0.82), 1, 1),
            (b, 1, 1),
            (EMOTE_P, 1, 1),
        ]
        rock: list[tuple[float, float, float]] = [(0, 0, 0), (a, 0, 0)]
        for t in strokes:
            rock += [(t, -21, 0), (t + 0.12, 7, 0)]
        rock += [(w(e, 0.52), 0, 0), (b, 0, 0), (EMOTE_P, 0, 0)]
        return (
            stop_world("dgScr", a, back)
            + world_locked("dgW", ".dgW", a, back)
            + egate("dgStill", ".legsStill", [(a, back)])
            + egate("dgWalk", ".legsWalk", [(a, back)], on_inside=False)
            # The hole APPEARS hard, mid-showcase, and is gated off only once the world has carried
            # it clear of the frame — at 11.4 s it is 176 px past the left edge, so the swap has
            # nothing on screen to swap.
            + egate("dgG", ".dgHole", [(dug, 11.4)])
            + squash("dgB", ".bob", pump)
            + shift("dgRk", ".rTurn", rock)
            # Earth goes up and BACK — against travel — because that is the side the creature is not
            # working toward, and it is the only lateral direction this frame can distinguish.
            + "".join(
                f"@keyframes dgCk{i}{{0%,{pctx(t)}%{{transform:translate(0,0);opacity:0}}"
                f"{pctx(t + 0.03)}%{{opacity:1}}"
                f"{pctx(t + 0.17)}%{{transform:translate({fmt(-22 - i * 8)}px,"
                f"{fmt(-46 - (i % 3) * 15)}px);opacity:1}}"
                f"{pctx(t + 0.40)}%{{transform:translate({fmt(-42 - i * 12)}px,8px);opacity:0}}"
                f"100%{{transform:translate(0,0);opacity:0}}}}"
                f".dgC{i}{{opacity:0;animation:dgCk{i} {fmt(EMOTE_P)}s ease-out infinite}}"
                for i, t in enumerate(strokes)
            )
            # The step clear: one hop over its own hole, just before the world restarts.
            + shift(
                "dgStep",
                ".hop",
                [
                    (0, 0, 0),
                    (w(e, 0.62), 0, 0),
                    (w(e, 0.70), 0, -22),
                    (w(e, 0.78), 0, -14),
                    (w(e, 0.86), 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
        )

    e.props, e.front, e.css = props, front, css
    return e


# ── THE MOTE ──────────────────────────────────────────────────────────────────────────────────────
def _mote() -> Emote:
    """A beat that ends in FAILURE, which is the only reason it is interesting.

    A catch is a shape the eye has already seen; a miss leaves a residue — the thing carries on
    existing and then leaves under its own power. The mote enters off the right edge and exits
    through the top, so it never fades at either end, and the gap at the apex is authored at 43 px
    so the miss reads at the README column instead of looking like a bad hit-test.
    """
    e = emote(
        Emote(
            key="mote",
            title="THE MOTE",
            category="The world",
            entry="a single point of light drifts in off the right edge at head height",
            showcase="the ears go up, it crouches, and it jumps for the mote — and misses it",
            exit="the mote climbs away, accelerating, and leaves through the top of the frame",
            window=(2.4, 7.2),
            cls="VISITOR",
            tie="",
        )
    )
    a, b = e.window
    back = b - 0.8
    mx, my = 786.0, 148.0  # authored off the right edge, level with the eye band

    def front() -> str:
        # In front, and in the GLYPH ink rather than the star ink: `.estar` is `display:none` under
        # the light scheme — correct for a night sky, fatal for the object a beat is about.
        return (
            f'<g class="eglyph moDot">'
            f'<rect x="{fmt(mx)}" y="{fmt(my)}" width="10" height="10"/>'
            f'<rect x="{fmt(mx - 6)}" y="{fmt(my + 3)}" width="4" height="4"/>'
            f'<rect x="{fmt(mx + 12)}" y="{fmt(my + 3)}" width="4" height="4"/>'
            f'<rect x="{fmt(mx + 3)}" y="{fmt(my - 6)}" width="4" height="4"/>'
            f"</g>"
        )

    def css() -> str:
        return (
            stop_world("moScr", a + 0.8, back)
            + egate("moStill", ".legsStill", [(a + 0.8, back)])
            + egate("moWalk", ".legsWalk", [(a + 0.8, back)], on_inside=False)
            # Ears up from the moment it registers the mote until after the landing. This is the
            # 'tracking' channel: the eye band cannot pan far enough to read at this size, and a
            # bilaterally symmetric body has no facing to turn toward anything.
            + egate("moAl", ".armsAlert", [(w(e, 0.26), w(e, 0.86))])
            + egate("moAg", ".armsGate", [(w(e, 0.26), w(e, 0.86))], on_inside=False)
            # `linear`, with the acceleration authored into the SPACING of the last four keyframes —
            # 50 px, then 80, then 130 in roughly equal time. An ease-in would have applied to the
            # drift as well and turned the entrance into a swoop.
            #
            # The path also CLIMBS as it comes in. Held level with the eye band — which is what 'at
            # head height' first meant — the hover lands at y=148 inside the body's own 138..282
            # band, and a white dot on flat orange reads as a speck ON the creature rather than as
            # something in the air near it. It arrives over open sky to the right, rises as it
            # crosses, and hovers 38 px clear of the crown, where the silhouette can be jumped at.
            # `.eglyph` carries `opacity:0` as its RESTING state — the framework added it so a glyph
            # whose only opacity lived in `glyph_pop`'s keyframes would not render FULLY VISIBLE in
            # the reduced-motion still. Borrowing the class for its ink alone and driving only
            # `transform` therefore paints nothing at all, in every frame, which is precisely what
            # the first render of this candidate showed. So opacity belongs in THESE keyframes and
            # not in a static override: the 0→1 ramp runs entirely off the right edge and the 1→0
            # ramp entirely above the top edge, so the live loop never sees an edge of either — and
            # the reduced-motion still falls back to a plain walking creature, with no mote left
            # hanging unattached in the sky.
            + f"@keyframes moK{{0%{{transform:translate(0,0);opacity:0}}"
            f"{pctx(a)}%{{transform:translate(0,0);opacity:1}}"
            f"{wp(e, 0.22)}%{{transform:translate(-172px,6px)}}"  # clear sky, right of the body
            f"{wp(e, 0.34)}%{{transform:translate(-300px,-18px)}}"  # drifting left and climbing
            f"{wp(e, 0.44)}%{{transform:translate(-356px,-48px)}}"  # hovering ABOVE the crown
            f"{wp(e, 0.50)}%{{transform:translate(-350px,-38px)}}"
            f"{wp(e, 0.55)}%{{transform:translate(-357px,-52px)}}"
            f"{wp(e, 0.59)}%{{transform:translate(-360px,-78px)}}"  # it starts up on the launch
            f"{wp(e, 0.63)}%{{transform:translate(-364px,-110px)}}"  # apex: 52 px clear of the crown
            f"{wp(e, 0.72)}%{{transform:translate(-370px,-160px)}}"
            f"{wp(e, 0.84)}%{{transform:translate(-377px,-240px)}}"
            f"{pctx(b)}%{{transform:translate(-383px,-342px);opacity:1}}"
            f"100%{{transform:translate(-392px,-640px);opacity:0}}}}"
            f".moDot{{animation:moK {fmt(EMOTE_P)}s linear infinite}}"
            # The jump. Apex at w=.62, where the mote is at y=54 — the crown reaches 97, so the gap
            # is 43 px and the miss is unmistakable rather than arguable.
            + shift(
                "moHop",
                ".hop",
                [
                    (0, 0, 0),
                    (w(e, 0.52), 0, 0),
                    (w(e, 0.56), 0, -17),
                    (w(e, 0.60), 0, -30),
                    (w(e, 0.63), 0, -34),
                    (w(e, 0.66), 0, -29),
                    (w(e, 0.70), 0, -11),
                    (w(e, 0.73), 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
            + squash(
                "moB",
                ".bob",
                [
                    (0, 1, 1),
                    (w(e, 0.30), 1, 1),
                    (w(e, 0.46), 1.09, 0.90),  # the crouch that loads the jump
                    (w(e, 0.52), 0.94, 1.10),  # extension off the ground
                    (w(e, 0.66), 0.97, 1.04),
                    (w(e, 0.73), 1.10, 0.89),  # the landing
                    (w(e, 0.80), 0.98, 1.03),
                    (w(e, 0.90), 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
        )

    e.front, e.css = front, css
    return e


# ── THE GREETING ──────────────────────────────────────────────────────────────────────────────────
def _greeting() -> Emote:
    """SYNCHRONY, and nothing else. Two creatures bounce on the same frame, twice.

    This is the candidate the no-connector law bites hardest, and the answer is that a line was never
    needed: simultaneity is a relationship the eye reads directly, and it is one of the few channels
    that survives at 332 px where a 2 px thread does not.

    The 84 px gap is load-bearing too. Two same-coloured sprites that touch merge into one connected
    orange region and read as a rendering fault, so they are never allowed within a body-width of
    each other — which is also why the visitor leaves the way it came instead of 'carrying on left'
    as the brief first had it. Continuing left would drive it straight THROUGH the resident. A change
    of direction and a brisker pace carry the departure instead.
    """
    e = emote(
        Emote(
            key="greeting",
            title="THE GREETING",
            category="The world",
            entry="a second clawd walks in off the right edge and pulls up a polite distance away",
            showcase="both of them bounce on the same frame, twice — nothing else in the world moves",
            exit="the visitor heads back out the right edge, faster than it came; the resident walks on",
            window=(2.6, 8.6),
            cls="VISITOR",
            tie="two sessions passing on the same trunk",
            # The resident stands left of centre so that BOTH creatures fit. The visitor is 220 px
            # wide and needs a body-width of clear sky beside it; parking it at the default cx put
            # its right half off the stage for the whole meeting, and every gate passed — a sprite
            # half out of frame is still a legal sprite.
            cx=120.0,
        )
    )
    a, b = e.window
    meet0, meet1 = 5.0, 7.2  # the stopped span: arrival to departure
    b_x = 800.0  # authored off the right edge
    b_travel = (
        -330.0
    )  # …to 470, which is 86 px clear of the resident's 384 and 70 px inside
    #                     the right edge — the whole visitor is on stage for the whole meeting

    def props() -> str:
        return f'<g class="grB">{clawd(e, sfx="B", scale=1.0, x=b_x)}</g>'

    def css() -> str:
        # ONE keyframe shape for both bounces, so 'the same frame' is true by construction rather
        # than by two hand-kept lists of numbers. The amplitudes differ because the scales do: -22
        # inside scale(1.2) and -26 inside scale(1.0) are both 26 px on stage.
        def bounce(name: str, sel: str, amp: float) -> str:
            return shift(
                name,
                sel,
                [
                    (0, 0, 0),
                    (5.25, 0, 0),
                    (5.45, 0, -amp),
                    (5.70, 0, 0),
                    (5.95, 0, -amp),
                    (6.20, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )

        return (
            sfx_rest("B", walking=True)
            + sfx_walk("B")
            + stop_world("grScr", meet0, meet1)
            + egate("grStill", ".legsStill", [(meet0, meet1)])
            + egate("grWalk", ".legsWalk", [(meet0, meet1)], on_inside=False)
            + egate("grStillB", ".legsStillB", [(meet0, meet1)])
            + egate("grWalkB", ".legsWalkB", [(meet0, meet1)], on_inside=False)
            # Ears up on both, over the same span, for the same reason as the bounce: a shared state
            # is a relationship, and it costs no ink between them.
            + egate("grAl", ".armsAlert", [(5.1, 7.0)])
            + egate("grAg", ".armsGate", [(5.1, 7.0)], on_inside=False)
            + egate("grAlB", ".armsAlertB", [(5.1, 7.0)])
            + egate("grAgB", ".armsGateB", [(5.1, 7.0)], on_inside=False)
            # In at 85 px/s, out at 146. Both ends of the track sit at x=800, off the right edge, so
            # the loop closes with the visitor genuinely absent rather than merely hidden.
            + shift(
                "grIn",
                ".grB",
                [
                    (0, 0, 0),
                    (a, 0, 0),
                    (meet0, b_travel, 0),
                    (meet1, b_travel, 0),
                    (b, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
                ease="linear",
            )
            + bounce("grBo", ".hop", 22)
            + bounce("grBoB", ".hopB", 26)
        )

    e.props, e.css = props, css
    return e


# ── THE FOLLOWER ──────────────────────────────────────────────────────────────────────────────────
def _follower() -> Emote:
    """A relationship expressed as a CONVERGENCE, over four seconds, with no ink spent on it.

    The small one arrives out of step and the beat is its legs sliding into the resident's rhythm,
    half a stride less wrong each time. That is this pack's strongest argument against a drawn
    connector: the link here is a property of the TIMING, so a line would be a redundant second
    statement of something the motion already makes — and the ruling that rejected the infographic
    reading applies to a redundant line exactly as hard as to a load-bearing one.

    It leaves under the horizon, clipped, because a fade would end the beat by having the observer
    lose track of it rather than by having it go anywhere.
    """
    e = emote(
        Emote(
            key="follower",
            title="THE FOLLOWER",
            category="The world",
            entry="a much smaller clawd trots in off the left edge, its legs out of step with the resident's",
            showcase="stride by stride it pulls into phase, until the two are stepping together",
            exit="it drifts back and drops away under the ground line; the resident never noticed",
            window=(1.8, 9.0),
            cls="VISITOR",
            tie="a small helper session falling into step behind the lead",
        )
    )
    b_x = -170.0  # authored off the left edge
    b_travel = (
        250.0  # …to 80, which leaves 58 px of sky to the resident's 248. Measured, not
    )
    #                   eyeballed: two same-coloured sprites that touch merge into one orange
    #                   region and read as a rendering fault, so the loop was swept at 0.6 s
    #                   and the tightest gap in the sample is the number quoted here.
    sync0, sync1 = 3.6, 7.4

    def props() -> str:
        return below_ground_clip(
            "foClip",
            f'<g class="foX"><g class="foY">{clawd(e, sfx="B", scale=0.5, x=b_x)}</g></g>',
        )

    def css() -> str:
        return (
            sfx_rest("B", walking=True)
            # NOT `sfx_walk` — the whole showcase is that these legs are NOT on the shared clock
            # until they are. `converging_stride` writes the phase into the percentages, because the
            # freeze in `banner-shots.sh` overrides `animation-delay` and `--lint` refuses one.
            + converging_stride("foLA", ".legAB", C * 0.6, sync0, sync1)
            + converging_stride("foLB", ".legBB", C * 0.6, sync0, sync1, invert=True)
            + converging_stride("foBo", ".bobB", 2.0, sync0, sync1)
            # In from the left, then a drift BACK as it peels off — the direction change is the cue
            # that the exit has begun, 0.6 s before the drop makes it obvious.
            + shift(
                "foInX",
                ".foX",
                [
                    (0, 0, 0),
                    (1.8, 0, 0),
                    (sync0, b_travel, 0),
                    (8.4, b_travel, 0),
                    (9.0, b_travel - 38, 0),
                    (
                        11.4,
                        0,
                        0,
                    ),  # …the rest of the way home while it is under the ground
                    (EMOTE_P, 0, 0),
                ],
                ease="linear",
            )
            # The drop, and the reset. The Y snap back to 0 is authored across the last 0.1 s — a
            # tenth of a second at x=-170, an entire sprite-width off the left edge, so the one frame
            # it could possibly occupy is not on screen. Any slower and it would rise back up through
            # the ground line in full view.
            + f"@keyframes foYk{{0%,{pctx(8.4)}%{{transform:translateY(0)}}"
            f"{pctx(9.0)}%{{transform:translateY(96px)}}"
            f"{pctx(11.9)}%{{transform:translateY(96px)}}"
            f"100%{{transform:translateY(0)}}}}"
            f".foY{{animation:foYk {fmt(EMOTE_P)}s ease-in infinite}}"
        )

    e.props, e.css = props, css
    return e


# ── THE HANDOVER ──────────────────────────────────────────────────────────────────────────────────
def _handover() -> Emote:
    """SUCCESSION: one leaves, one arrives, and the work that was set down is picked up and carried.

    HOW THE LOOP CLOSES, which is the whole engineering problem here. A succession ends in a CHANGED
    state and a 12 s loop may not — so both creatures are the same sprite at the same scale, and the
    successor's track ends at exactly the resident's starting position with exactly the resident's
    leg phase (both run off `base_css`'s shared `ewA`/`ewB` clock, so that part is free). At 100 %
    the frame therefore holds one creature at x=248 mid-stride with the block tucked behind its body
    — which is the frame at 0 %. Neither track returns to its own starting value and neither needs
    to: it is the COMPOSITE that has to match, and it does.

    The block is never seen to appear or to vanish. It starts occluded behind the resident's body,
    slides out and down onto the rule, sits there in the open while the frame is empty of creatures,
    and is lifted back up behind the successor's body. A body is the occluder at both ends.
    """
    e = emote(
        Emote(
            key="handover",
            title="THE HANDOVER",
            category="The world",
            entry="the resident dips and sets a small block down on the ground ahead of itself",
            showcase="it walks off the left edge; the block sits alone; a second clawd arrives from the right",
            exit="the newcomer lifts the block, carries it to the resident's place, and takes up the stride",
            window=(2.6, 9.8),
            cls="VISITOR",
            tie="a handoff — the successor picks up exactly what was put down, and the work continues",
        )
    )
    b_x = 800.0  # the successor, authored off the right edge
    lift_x, home_x = 470.0, 248.0  # where it stops to lift, and the place it inherits
    blk_x, blk_y = (
        440.0,
        250.0,
    )  # authored INSIDE the resident's body — never seen there
    set_dx, set_dy = (
        170.0,
        58.0,
    )  # …to (610, 308): on the rule, between the successor's leg pairs
    carry_dx = (
        lift_x - home_x
    )  # 222 — the block's offset for as long as it is being carried

    def props() -> str:
        block = (
            f'<g class="hoBlk"><g class="efg">'
            f'<rect x="{fmt(blk_x)}" y="{fmt(blk_y)}" width="22" height="22"/>'
            f'<rect x="{fmt(blk_x + 3)}" y="{fmt(blk_y - 3)}" width="16" height="3"/>'
            f"</g></g>"
        )
        return (
            block + f'<g class="hoB">{clawd(e, sfx="B", scale=CLAWD_SCALE, x=b_x)}</g>'
        )

    def css() -> str:
        return (
            sfx_rest("B", walking=True)
            + sfx_walk("B")
            # The resident's exit. `.rTurn` carries the sprite and `.shdw` carries its contact
            # shadow, off ONE keyframes block shared by the two elements — a shadow left standing at
            # x=248 while the body walks away is the fastest way to break a departure.
            + shift(
                "hoOut",
                ".rTurn,.shdw",
                [
                    (0, 0, 0),
                    (3.6, 0, 0),
                    (5.8, -540, 0),  # 292 px past the left edge, wholly out of frame
                    (EMOTE_P, -540, 0),
                ],
                ease="linear",
            )
            # …and its dip as it puts the block down.
            + shift(
                "hoDip",
                ".hop",
                [
                    (0, 0, 0),
                    (2.6, 0, 0),
                    (3.0, 0, 13),
                    (3.5, 0, 13),
                    (3.9, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
            # The successor: in at 137 px/s, a pause to lift, then home. Its final value is the
            # resident's starting position — see the docstring; that is what makes the wrap silent.
            + shift(
                "hoIn",
                ".hoB",
                [
                    (0, 0, 0),
                    (5.0, 0, 0),
                    (7.4, lift_x - b_x, 0),
                    (8.4, lift_x - b_x, 0),
                    (9.8, home_x - b_x, 0),
                    (EMOTE_P, home_x - b_x, 0),
                ],
                ease="linear",
            )
            + shift(
                "hoDipB",
                ".hopB",
                [
                    (0, 0, 0),
                    (7.5, 0, 0),
                    (7.8, 0, 13),
                    (8.1, 0, 13),
                    (8.4, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
            # The block. Out from behind the resident and down onto the rule; a long sit; up behind
            # the successor; then it rides home. The 8.4→9.8 leg is the exact negative of the
            # successor's, so for that span it is welded to the body carrying it.
            + shift(
                "hoBk",
                ".hoBlk",
                [
                    (0, 0, 0),
                    (2.8, 0, 0),
                    (3.5, set_dx, set_dy),
                    (7.9, set_dx, set_dy),
                    (8.3, carry_dx, 0),
                    (8.4, carry_dx, 0),
                    (9.8, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
                ease="linear",
            )
        )

    e.props, e.css = props, css
    return e


# ── THE SHY ───────────────────────────────────────────────────────────────────────────────────────
def _shy() -> Emote:
    """A creature that is only ever a pair of eyes, and an exit that is pure occlusion.

    The mound is drawn in FRONT of it and is the whole apparatus: the watcher is a complete sprite
    the entire time, parked with its crown below the crest, and 'a pair of eyes rises' is that sprite
    coming up 56 px. It never fades, is never gated and never changes size — it goes behind something
    and comes back out from behind the same thing, which is the only disappearance the framework
    allows.

    The clip at the ground line is the second half of that. Sunk far enough to hide, its legs would
    otherwise be drawn ON TOP of the ground plane below the rule, because props paint after it.
    """
    e = emote(
        Emote(
            key="shy",
            title="THE SHY",
            category="The world",
            entry="a pair of eyes rises over the crest of a mound and stops there, watching",
            showcase="it holds, then eases up a little further — most of a head now, still watching",
            exit="the resident's ears go up and it stops dead; the eyes drop behind the same mound",
            window=(3.0, 8.4),
            cls="VISITOR",
            tie="",
        )
    )
    seen = 7.4  # the frame the resident registers it, and the frame it goes
    mnd_cx, mnd_hw, mnd_h = 610.0, 96.0, 72.0
    # Computed, not eyeballed: the eye band is 20..30 local units down a 0.5-scaled sprite whose top
    # sits at E_GROUND-80, so it rests at y 270..280 and the crest is at 258. HIDDEN needs the crown
    # below the crest, not the eyes.
    hidden, peek1, peek2 = 30.0, -26.0, -42.0

    def props() -> str:
        return below_ground_clip(
            "shClip", f'<g class="shPeek">{clawd(e, sfx="B", scale=0.5, x=555.0)}</g>'
        )

    def front() -> str:
        return f'<g class="emd0">{dome(mnd_cx, mnd_hw, mnd_h)}</g>'

    def css() -> str:
        return (
            sfx_rest("B", walking=False)
            + stop_world("shScr", seen, 8.4)
            + egate("shStill", ".legsStill", [(seen, 8.4)])
            + egate("shWalk", ".legsWalk", [(seen, 8.4)], on_inside=False)
            # The resident's half of the beat is one state change on one frame — and it is the CAUSE
            # of the exit, so the two are authored at the same instant on purpose. Turning its head
            # would have been the natural cue and is not available: `scaleX(-1)` on a bilaterally
            # symmetric sprite maps it onto itself.
            + egate("shAl", ".armsAlert", [(seen, 8.4)])
            + egate("shAg", ".armsGate", [(seen, 8.4)], on_inside=False)
            # Up slowly in two stages, down in a quarter of a second. The asymmetry is the character:
            # rising is a decision, dropping is a reflex.
            + f"@keyframes shPk{{0%,{pctx(3.0)}%{{transform:translateY({fmt(hidden)}px)}}"
            f"{pctx(3.7)}%{{transform:translateY({fmt(peek1)}px)}}"
            f"{pctx(6.0)}%{{transform:translateY({fmt(peek1)}px)}}"
            f"{pctx(6.5)}%{{transform:translateY({fmt(peek2)}px)}}"
            f"{pctx(seen)}%{{transform:translateY({fmt(peek2)}px)}}"
            f"{pctx(seen + 0.25)}%{{transform:translateY({fmt(hidden)}px)}}"
            f"100%{{transform:translateY({fmt(hidden)}px)}}}}"
            f".shPeek{{animation:shPk {fmt(EMOTE_P)}s cubic-bezier(.35,.1,.3,1) infinite}}"
        )

    e.props, e.front, e.css = props, front, css
    return e


_pebble()
_sniff()
_dig()
_mote()
_greeting()
_follower()
_handover()
_shy()
