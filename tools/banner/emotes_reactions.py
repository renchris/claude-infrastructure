#!/usr/bin/env python3
"""emotes_reactions.py — the REACTIONS pack: seven candidate micro-events about the creature itself.

One category per module, per `emotes.load_packs`. Everything in here is the creature's own body and
its own feelings: no props, no second creature, no world event it is responding to. That restriction
is the point of the category rather than an accident of who wrote it — a reaction that needs a prop
to be legible is really a beat about the prop, and it belongs in a different pack.

WHAT THE SPRITE CAN ACTUALLY SAY. Eleven by eight flat cells of one orange, two eye holes for a
face, no mouth, no brows, and a silhouette that is bilaterally symmetric — so a flip is invisible and
a sideways lean carries no direction. Two channels survive at this size, and every candidate below is
built out of them and nothing else:

    POSTURE   a whole-body squash/stretch or displacement, big enough to change the silhouette
    GLYPH     one standardized mark, large enough to read at the README column

Everything finer — a raised eyebrow, a turned head, one lifted foot — was tried on paper and dropped.
THE ITCH is the honest casualty: its brief called for a single back leg lifting off, and the leg
groups are drawn as two interleaved pairs that cannot be split without redrawing the sprite. It
scratches with its whole body instead, and the story says so.

    python3 tools/banner/emotes.py --out /tmp/emotes-react
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

# BIND TO THE FRAMEWORK THAT IS ALREADY RUNNING, never to a fresh copy of it. `emotes.py` is the
# entrypoint as well as the framework, so by the time `load_packs()` imports this file it is already
# loaded under the name `__main__`. A plain `import emotes` therefore builds a SECOND module object
# with its own empty `EMOTES` list, and every candidate registered below lands in a list nobody ever
# renders. Measured rather than feared: a probe pack under that import saw `id(emotes) !=
# id(sys.modules['__main__'])`, two independent registries, and a build that printed its four
# original candidates without a word of complaint.
#
# That is exactly the failure `load_packs` says the review surface may never have — a missing panel
# is indistinguishable from a candidate nobody wrote — and it slips past the FATAL-import rule
# because the import SUCCEEDS. So resolve by identity, not by name.
_main = sys.modules.get("__main__")
if getattr(_main, "__file__", "") == str(_HERE / "emotes.py"):
    fw = _main
else:  # imported as an ordinary library (a test, a REPL) — the plain path
    fw = importlib.import_module("emotes")

gen = fw.gen
Emote = fw.Emote
emote = fw.emote
egate = fw.egate
squash = fw.squash
shift = fw.shift
glyph = fw.glyph
glyph_pop = fw.glyph_pop
stop_world = fw.stop_world
w = fw.w
wp = fw.wp
pctx = fw.pctx
fmt = fw.fmt
EMOTE_P = fw.EMOTE_P
E_GROUND = fw.E_GROUND
CLAWD_SCALE = fw.CLAWD_SCALE

C = (
    gen.CELL
)  # 20 user units per sprite cell — every displacement below is quoted in cells
HEAD_Y = (
    E_GROUND - gen.SPRITE_H * CLAWD_SCALE
)  # 138 — the top of the resting silhouette


def glyph_seat(e: Emote, clearance: float) -> tuple[float, float]:
    """Where a glyph sits above THIS candidate's head, given how far the head rises.

    Computed rather than eyeballed, because the clearance is not a constant: a candidate that
    stretches to scale(_,1.12) lifts its own crown 23 px, and one that hops lifts it 36. A glyph
    seated at a fixed height overlaps the very pose it is commenting on — and the overlap only
    appears at the peak frame, which is the one frame a spot-check is least likely to land on.
    """
    return e.cx + gen.SPRITE_W * CLAWD_SCALE / 2, HEAD_Y - clearance


# ── THE SNEEZE ────────────────────────────────────────────────────────────────────────────────────
def _sneeze() -> Emote:
    """Two rising hitches and a release. The build-up is the whole beat: a sneeze with no inhale is
    just a lurch, and the eye needs the ~500 ms the hitches buy to arrive before the payoff."""
    e = emote(
        Emote(
            key="sneeze",
            title="THE SNEEZE",
            category="Reactions",
            entry="the walk stops and the body swells in two rising hitches, each taller than the last",
            showcase="it goes off — a hard forward squash that shunts the whole body back half a cell",
            exit="it shakes the after-tingle off in three quick wobbles and picks the stride back up",
            window=(2.4, 6.6),
            cls="BEAT",
            tie="a hook firing on something nobody planned for",
        )
    )
    a, b = e.window
    back = b - 0.5  # the world starts moving again slightly before the story ends

    def css() -> str:
        return (
            stop_world("snScr", a, back)
            + egate("snStill", ".legsStill", [(a, back)])
            + egate("snWalk", ".legsWalk", [(a, back)], on_inside=False)
            # The inhale is TWO hitches rather than one long swell, because a single ramp reads as
            # the creature growing. A step-and-hold, twice, reads as breath being taken.
            + squash(
                "snB",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.08), 1.03, 0.97),  # a small dip to load the first hitch
                    (w(e, 0.16), 0.97, 1.07),  # hitch 1
                    (w(e, 0.22), 0.99, 1.04),
                    (w(e, 0.30), 0.94, 1.13),  # hitch 2 — taller, and it holds
                    (w(e, 0.38), 0.95, 1.12),
                    (w(e, 0.42), 1.15, 0.86),  # HA-CHOO
                    (w(e, 0.50), 1.06, 0.95),
                    (w(e, 0.58), 0.96, 1.05),
                    (w(e, 0.68), 1.04, 0.97),
                    (w(e, 0.78), 0.98, 1.02),
                    (w(e, 0.88), 1, 1),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
            # The recoil is AGAINST travel. The ground scrolls left, so the creature is making
            # ground to the right; being shunted back is therefore a move to the LEFT, and that
            # direction is readable even on a symmetric body because the world supplies it.
            + shift(
                "snR",
                ".rTurn",
                [
                    (0, 0, 0),
                    (a, 0, 0),
                    (w(e, 0.30), 3, 0),  # leans in as it loads
                    (w(e, 0.42), -11, 0),  # half a cell back
                    (w(e, 0.52), -8, 0),
                    (w(e, 0.60), -3, 2),  # the shake-off, three quick cycles
                    (w(e, 0.66), -7, -2),
                    (w(e, 0.72), -3, 1),
                    (w(e, 0.78), -6, -1),
                    (w(e, 0.86), -2, 0),
                    (w(e, 0.94), 0, 0),
                    (b, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
        )

    e.css = css
    return e


# ── THE YAWN ──────────────────────────────────────────────────────────────────────────────────────
def _yawn() -> Emote:
    """The only candidate here that uses the eyes, and it can afford to: the squeeze is HELD for a
    full second. A 120 ms eye event at this size is a flicker nobody parses."""
    e = emote(
        Emote(
            key="yawn",
            title="THE YAWN",
            category="Reactions",
            entry="the stride quits and the body sags wide and low, as if it just ran out",
            showcase="a slow deep inflation with both eyes squeezed shut, held for a full second",
            exit="it deflates past its own resting height, settles, and blinks twice",
            window=(2.6, 8.2),
            cls="BEAT",
            tie="the end of a long session — the context is spent and it knows it",
        )
    )
    a, b = e.window
    back = b - 0.6
    shut0, shut1 = (
        w(e, 0.24),
        w(e, 0.62),
    )  # the squeeze — 2.1 s, of which 1.0 s is the held peak
    blink = 0.18

    def css() -> str:
        return (
            stop_world("ywScr", a, back)
            + egate("ywStill", ".legsStill", [(a, back)])
            + egate("ywWalk", ".legsWalk", [(a, back)], on_inside=False)
            + squash(
                "ywB",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.10), 1.05, 0.94),  # the sag
                    (w(e, 0.18), 1.06, 0.93),
                    (w(e, 0.34), 0.93, 1.12),  # the inflation, slow on purpose
                    (w(e, 0.40), 0.92, 1.13),
                    (w(e, 0.58), 0.92, 1.13),  # HELD — .40 to .58 of 5.6 s is 1.0 s
                    (
                        w(e, 0.66),
                        1.09,
                        0.90,
                    ),  # and drops PAST rest, which is what sells the relief
                    (w(e, 0.74), 1.02, 0.97),
                    (w(e, 0.82), 0.99, 1.02),
                    (w(e, 0.90), 1, 1),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
            # THE EYE TRACK, and why it takes four gates rather than one. The ambient blink lives on
            # `.eOpen`/`.eShut`, both of which already carry a 4 s animation, and one animation per
            # element is the rule the deterministic freeze depends on. So the whole ambient pair is
            # gated OFF at `.lookGate` and THE ASK's parked pair (`.eyesAsk`, which carries no
            # ambient animation of its own) is gated on in its place, with this candidate driving its
            # open/shut halves directly. Same nesting the sprite already uses, same reason.
            + egate("ywLook", ".lookGate", [(w(e, 0.14), w(e, 0.92))], on_inside=False)
            + egate("ywAsk", ".eyesAsk", [(w(e, 0.14), w(e, 0.92))])
            + egate(
                "ywShut",
                ".aShut",
                [
                    (shut0, shut1),
                    (
                        w(e, 0.74),
                        w(e, 0.74) + blink,
                    ),  # and two blinks to come back round
                    (w(e, 0.84), w(e, 0.84) + blink),
                ],
            )
            + egate(
                "ywOpen",
                ".aOpen",
                [
                    (shut0, shut1),
                    (w(e, 0.74), w(e, 0.74) + blink),
                    (w(e, 0.84), w(e, 0.84) + blink),
                ],
                on_inside=False,
            )
        )

    e.css = css
    return e


# ── THE ITCH ──────────────────────────────────────────────────────────────────────────────────────
def _itch() -> Emote:
    """A high-frequency judder against a braced posture.

    THE BRIEF ASKED FOR ONE BACK LEG TO LIFT AND IT CANNOT BE DRAWN. `gen.clawd_sprite` emits the
    legs as two interleaved PAIRS (`legA` at columns 1 and 7, `legB` at 3 and 9) for the walk, and
    one four-legged group for standing; there is no single leg to raise, and raising a pair lifts one
    limb on each side, which reads as the body floating rather than as a foot coming up. Redrawing
    the sprite to get it is the one thing this preview is forbidden to do. So the scratch is carried
    entirely by the body — braced low and buzzing — and the story below says that rather than
    claiming a foot the render does not contain.
    """
    e = emote(
        Emote(
            key="itch",
            title="THE ITCH",
            category="Reactions",
            entry="the walk quits and it drops into a braced hunch — a tenth wider, a tenth lower",
            showcase="the whole silhouette pumps in and out four times, a shudder it cannot stop",
            exit="one long stretch up out of the hunch, and it ambles off as if nothing happened",
            window=(3.0, 7.4),
            cls="BEAT",
            tie="",
        )
    )
    a, b = e.window
    back = b - 0.5

    # THE THIRD DRAFT, AND THE FIRST TWO BOTH FAILED THE SAME TEST FOR THE SAME REASON. Draft one
    # scrubbed +-5 units, draft two +-10, and both moved the body WITHOUT CHANGING ITS OUTLINE. A
    # reviewer sampling the loop at even 1 s intervals saw five frames that differed only in where
    # the same shape sat — which on a stopped world is nearly nothing, because there is no relative
    # motion to measure it against. My own contact sheet hid this: I cropped every frame at a FIXED
    # offset, which turns a translation into an apparent displacement of the subject against the
    # crop and makes 12 units look like an event. It is not. The crop was measuring the crop.
    #
    # So the scrub is now carried by the SQUASH, not by the translate: the body's width swings a
    # full 15% each cycle, from 1.15 to 1.00, which is 40 units of outline change on a 264-unit
    # body. That is a silhouette doing something rather than a silhouette being moved. The translate
    # stays, counter-phased and smaller, so the pump reads as scrubbing against something instead of
    # as breathing.
    #
    # And the BRACE is now deep (1.10 x 0.90) and held for most of the window, so that the thing a
    # sample lands on between cycles is still an obviously different posture from the walk. That is
    # the property the first two drafts lacked: they were only legible AT the extremes.
    # NEITHER END OF THE PUMP MAY BE THE RESTING SHAPE, and that is the fourth draft's one idea.
    # Draft three swung 1.15 -> 1.00, a 15% excursion, and still failed at honest size for a reason
    # amplitude does not capture: 1.00 IS the walk's silhouette, so half of every cycle put the
    # creature back into the pose it holds for the other ten seconds of the loop. Sampled at even
    # 0.8 s intervals — how a reviewer actually scans a grid — about half the frames therefore showed
    # a creature standing normally, and a beat legible on alternate frames is not legible.
    #
    # So the cycle now runs between two poses that are both far from rest AND far from each other:
    # squashed wide-and-low, then stretched tall-and-narrow. Each stays inside the +-15% band on its
    # own, but the swing BETWEEN them is 23% of width and 26% of height — the largest outline change
    # in this pack — and no phase of it can be mistaken for the walk.
    pump: list[tuple[float, float, float]] = []
    slide: list[tuple[float, float, float]] = []
    for i in range(4):
        f0 = (
            0.24 + i * 0.10
        )  # 0.44 s a cycle — faster blurs at 332 px, slower reads as rocking
        # EACH EXTREME IS HELD, and that is what makes the beat survive a coarse glance. A pump
        # authored as two instants per cycle spends most of its time in TRANSIT between them, and
        # the midpoint of that transit is approximately the resting shape — so a contact sheet
        # sampled at 0.8 s against a 0.44 s cycle aliases straight onto the crossings and reports a
        # creature standing still. Measured: dense sampling at the extremes showed the shudder
        # plainly while the even-interval strip of the same asset showed almost nothing. Holding
        # each pose for 0.13 s of the 0.44 s cycle puts ~60% of the window on an extreme, and turns
        # a sine into a series of distinct jerks, which is what a shudder is anyway.
        pump.append((w(e, f0), 1.15, 0.86))
        pump.append((w(e, f0 + 0.03), 1.15, 0.86))
        pump.append((w(e, f0 + 0.05), 0.92, 1.12))
        pump.append((w(e, f0 + 0.08), 0.92, 1.12))
        slide.append((w(e, f0), 9, -4))
        slide.append((w(e, f0 + 0.03), 9, -4))
        slide.append((w(e, f0 + 0.05), -7, 3))
        slide.append((w(e, f0 + 0.08), -7, 3))

    def css() -> str:
        return (
            stop_world("itScr", a, back)
            + egate("itStill", ".legsStill", [(a, back)])
            + egate("itWalk", ".legsWalk", [(a, back)], on_inside=False)
            + squash(
                "itB",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.08), 1.06, 0.94),
                    (w(e, 0.18), 1.10, 0.90),  # the hunch, and it is deep on purpose
                ]
                + pump
                + [
                    (w(e, 0.70), 1.09, 0.91),  # back into the hunch
                    (w(e, 0.78), 0.93, 1.12),  # ...and one long stretch up out of it
                    (w(e, 0.86), 1.04, 0.96),
                    (w(e, 0.94), 1, 1),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
            # Counter-phased with the pump, and deliberately smaller than it: wide-and-right, then
            # narrow-and-left. On its own this is the draft that did not read; as the minority
            # partner of a 15% width swing it is what stops the pump reading as breathing.
            + shift(
                "itR",
                ".rTurn",
                [(0, 0, 0), (a, 0, 0), (w(e, 0.20), 0, 0)]
                + slide
                + [(w(e, 0.70), 0, 0), (b, 0, 0), (EMOTE_P, 0, 0)],
                ease="linear",  # a scrub has no easing; ease-out would make every stroke decay
            )
        )

    e.css = css
    return e


# ── THE TRIP ──────────────────────────────────────────────────────────────────────────────────────
def _trip() -> Emote:
    """The catch is the WORLD stopping, not the creature. Arresting the scroll mid-stride is the
    cheapest legible 'something caught' available, and it needs no new art.

    IT DOES NOT RAISE ITS ARMS, AND THAT IS THE WHOLE SECOND DRAFT. The first version flung them up
    on the theory that a flail is what a stumble looks like — and it is, on a creature with arms. On
    THIS one the only arms-up pose in the vocabulary is the CHEER, sparkle cells and all, so the
    stumble's peak frame and THE DELIGHT's peak frame were the same silhouette: wide, stubs up,
    bright dots overhead. On a page whose entire job is comparing candidates side by side, two beats
    that share a signature are not two beats — a reviewer scanning the grid cannot tell which panel
    is which, and the more specific idea (delight) is the one that loses.

    So the pitch carries it alone, and it is built from the two things a stumble actually is:
    the body going somewhere its feet did not, and then stopping hard. The CONTACT SHADOW is what
    proves the first half — it is drawn outside `.rTurn`, in stage coordinates, so it stays where the
    feet were while the body travels a cell and a half past it. Nothing had to be authored for that;
    it falls out of the sprite's own construction, and it is the one cue on this creature that says
    'off balance' without needing a limb to say it with.
    """
    e = emote(
        Emote(
            key="trip",
            title="THE TRIP",
            category="Reactions",
            entry="mid-stride the ground stops dead under it — something caught",
            showcase="the body keeps going without its feet, flattens out past its own shadow, and stops hard",
            exit="it rocks back upright, stands dead still a beat as if checking nobody saw, walks on",
            window=(2.8, 7.0),
            cls="BEAT",
            tie="a gate you did not know was armed",
        )
    )
    a, b = e.window
    back = b - 0.4

    def css() -> str:
        return (
            stop_world("trScr", a, back)
            + egate("trStill", ".legsStill", [(a, back)])
            + egate("trWalk", ".legsWalk", [(a, back)], on_inside=False)
            # A PENDULUM, and that is structural rather than stylistic: the loop has to seam, so any
            # displacement must come back to zero. A stumble that merely translated forward would
            # have to moonwalk home in full view. Rocking back past vertical and settling returns to
            # rest as part of the acting.
            #
            # 30 units is a cell and a half, and it is chosen against the SHADOW rather than by eye:
            # the contact ellipse is 116 units wide, so a 36-unit excursion in stage terms puts a
            # third of the body clear of its own footprint. Under half that and the body still sits
            # inside the shadow, which is a creature leaning, not a creature falling.
            + shift(
                "trR",
                ".rTurn",
                [
                    (0, 0, 0),
                    (a, 0, 0),
                    (w(e, 0.05), 6, 0),  # the feet stop; the body does not
                    (w(e, 0.13), 24, 0),
                    (w(e, 0.20), 30, 0),  # out past the shadow, about to go over
                    (
                        w(e, 0.28),
                        20,
                        0,
                    ),  # THE CATCH — hard, and it is the loudest frame
                    (w(e, 0.34), 8, 0),
                    (w(e, 0.40), -6, 0),  # rocks back past vertical
                    (w(e, 0.46), 2, 0),
                    (w(e, 0.54), 0, 0),
                    (w(e, 0.76), 0, 0),  # ...and stands there. The pause IS the joke.
                    (b, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
            # The flatten is what makes the excursion a PITCH rather than a slide. It is pinned to
            # the feet, so a y of 0.86 brings the crown down 27 units while the soles stay on the
            # rule — the body going over the top of its own legs, which is the shape of a stumble.
            + squash(
                "trB",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.05), 1.06, 0.94),
                    (w(e, 0.13), 1.14, 0.87),
                    (
                        w(e, 0.20),
                        1.15,
                        0.86,
                    ),  # flattest, furthest out — the frame before the catch
                    (w(e, 0.28), 1.11, 0.90),
                    (w(e, 0.34), 0.95, 1.08),  # springs upright out of the catch
                    (w(e, 0.42), 1.05, 0.95),
                    (w(e, 0.50), 0.99, 1.01),
                    (w(e, 0.58), 1, 1),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
            # A short upward jerk ON THE CATCH, riding `.hop` because `.bob` and `.rTurn` are both
            # already spoken for and one animation per element is the rule the whole freeze rests on.
            # It is 7 units and lasts 0.3 s: the snap of arresting yourself, not a jump.
            + shift(
                "trH",
                ".hop",
                [
                    (0, 0, 0),
                    (a, 0, 0),
                    (w(e, 0.26), 0, 0),
                    (w(e, 0.31), 0, -7),
                    (w(e, 0.40), 0, 0),
                    (b, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
        )

    e.css = css
    return e


# ── THE DELIGHT ───────────────────────────────────────────────────────────────────────────────────
def _delight() -> Emote:
    """Two hops with the arms up. The hops ride `.hop` and the squash rides `.bob`, which is the only
    way to have both — an element carrying a comma-list of animations breaks the freeze the whole
    review depends on."""
    e = emote(
        Emote(
            key="delight",
            title="THE DELIGHT",
            category="Reactions",
            entry="it stops and drops into a tiny crouch — the wind-up you can see coming",
            showcase="two hops with both arms up and a spark bursting over its head",
            exit="it lands, the spark lifts away, and it walks on a little lighter",
            window=(3.4, 7.6),
            cls="BEAT",
            tie="a green gate on the first try",
            uses=("rCheer",),
        )
    )
    a, b = e.window
    back = b - 0.4
    # BESIDE THE HEAD, NOT OVER IT, and that is a render finding rather than a preference. The
    # cheer pose carries three small orange sparkle cells of its OWN, up to two cells above the
    # crown; seated overhead the white spark glyph landed in the middle of them and the whole area
    # read as confetti — two marks saying the same thing, neither of them legible. Off the shoulder
    # the glyph has clear sky behind it and the pose's sparkle stays a texture on the pose.
    # 60 units of clearance, not 26: the cheer pose does not just raise the arm stubs, it moves them
    # a full cell OUTBOARD (gen.py: that widening is what stopped them reading as horns), so the
    # silhouette during this showcase is a cell wider on each side than at rest. At 26 the glyph
    # landed on the raised right arm.
    gx = e.cx + gen.SPRITE_W * CLAWD_SCALE + 60
    gy = HEAD_Y - 18

    def front() -> str:
        return glyph("spark", gx, gy, "dlG")

    def css() -> str:
        return (
            stop_world("dlScr", a, back)
            + egate("dlStill", ".legsStill", [(a, back)])
            + egate("dlWalk", ".legsWalk", [(a, back)], on_inside=False)
            # ANTICIPATION, AIRBORNE, LANDING — the three states, in that order, twice. A hop without
            # the crouch that precedes it and the squash that absorbs it reads as the sprite being
            # moved rather than as the sprite jumping.
            + squash(
                "dlB",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.10), 1.08, 0.91),  # the crouch
                    (w(e, 0.18), 1.06, 0.93),
                    (w(e, 0.24), 0.95, 1.08),  # launch
                    (w(e, 0.32), 1.0, 1.0),  # airborne, neutral
                    (w(e, 0.42), 1.10, 0.90),  # land
                    (w(e, 0.48), 0.95, 1.08),  # launch again
                    (w(e, 0.57), 1.0, 1.0),
                    (w(e, 0.66), 1.10, 0.90),
                    (w(e, 0.74), 0.98, 1.03),
                    (w(e, 0.84), 1, 1),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
            + shift(
                "dlH",
                ".hop",
                [
                    (0, 0, 0),
                    (a, 0, 0),
                    (w(e, 0.24), 0, 0),
                    (w(e, 0.30), 0, -26),
                    (w(e, 0.36), 0, -22),
                    (w(e, 0.42), 0, 0),
                    (w(e, 0.48), 0, 0),
                    (
                        w(e, 0.55),
                        0,
                        -30,
                    ),  # the second is the bigger one — delight escalates
                    (w(e, 0.61), 0, -25),
                    (w(e, 0.66), 0, 0),
                    (b, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
                ease="ease-in-out",
            )
            + egate("dlChr", ".rCheer", [(w(e, 0.20), w(e, 0.74))])
            + egate("dlArm", ".armsGate", [(w(e, 0.20), w(e, 0.74))], on_inside=False)
            # the spark lands on the FIRST apex, not on the crouch — the glyph is the payoff, and a
            # payoff that arrives with its own cue has no cue
            + glyph_pop("dlGf", ".dlG", w(e, 0.29), b - 0.25, rise=32)
        )

    e.front, e.css = front, css
    return e


# ── THE FRIGHT ────────────────────────────────────────────────────────────────────────────────────
def _fright() -> Emote:
    """Fast in, slow out. The asymmetry IS the emotion: a recoil that recovers as quickly as it
    arrived reads as a twitch, and only the long climb-down says the creature was frightened."""
    e = emote(
        Emote(
            key="fright",
            title="THE FRIGHT",
            category="Reactions",
            entry="everything stops at once — the stride, the ground, the whole world",
            showcase="it recoils a half-cell, draws up rigid and tall, ears up, and a ! cracks overhead",
            exit="it climbs down over a slow second, the mark lifts away, and the ground rolls again",
            window=(3.2, 8.0),
            cls="BEAT",
            tie="a Stop hook that refuses the false 'done'",
        )
    )
    a, b = e.window
    back = b - 0.5
    # 72 rather than 62: the crown lifts 23 px under the rigid scale(_,1.12) draw-up, and at 62 the
    # bang's foot sat about 6 CSS px off the head — close enough on the contact sheet to read as
    # resting on it rather than as floating above it.
    gx, gy = glyph_seat(e, 72)

    def front() -> str:
        return glyph("bang", gx, gy, "frG")

    def css() -> str:
        return (
            stop_world("frScr", a, back)
            + egate("frStill", ".legsStill", [(a, back)])
            + egate("frWalk", ".legsWalk", [(a, back)], on_inside=False)
            + shift(
                "frR",
                ".rTurn",
                [
                    (0, 0, 0),
                    (a, 0, 0),
                    (w(e, 0.06), -14, -4),  # away, and off the ground a little
                    (w(e, 0.14), -12, 0),
                    (w(e, 0.26), -11, 0),  # frozen there
                    (w(e, 0.42), -10, 0),
                    (w(e, 0.58), -7, 0),  # then edges back in over ~1.3 s
                    (w(e, 0.70), -4, 0),
                    (w(e, 0.86), 0, 0),
                    (b, 0, 0),
                    (EMOTE_P, 0, 0),
                ],
            )
            + squash(
                "frB",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.05), 1.06, 0.93),  # the flinch compresses...
                    (
                        w(e, 0.12),
                        0.93,
                        1.12,
                    ),  # ...then it draws up rigid, which is the held read
                    (w(e, 0.30), 0.94, 1.11),
                    (w(e, 0.50), 0.95, 1.09),
                    (w(e, 0.66), 0.98, 1.04),
                    (w(e, 0.82), 1.01, 0.99),
                    (w(e, 0.92), 1, 1),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
            # The alert ears are a ONE-cell rise in their own columns, deliberately not the cheer:
            # gen.py's own measurement puts -2 at "hat brim" and -4 at "antennae", and this is
            # attention rather than a gesture.
            + egate("frAl", ".armsAlert", [(w(e, 0.04), w(e, 0.76))])
            + egate("frArm", ".armsGate", [(w(e, 0.04), w(e, 0.76))], on_inside=False)
            + glyph_pop("frGf", ".frG", a + 0.42, w(e, 0.80))
        )

    e.front, e.css = front, css
    return e


# ── THE POTTER ────────────────────────────────────────────────────────────────────────────────────
def _potter() -> Emote:
    """The one candidate here that never stops walking, and it is in the set for that reason.

    Six of these seven arrest the world to be seen, which is the cheapest transient in the vocabulary
    and therefore the one most at risk of becoming the only thing the banner ever does. This is the
    control: no stop, no gate, no pose swap — just a second rhythm laid over the stride. The bob runs
    at 0.8 s against the stride's 0.5 s, a 4:5 ratio that drifts through a full phase every 4 s, so
    the two never lock into a single beat and the body reads as bobbing to something of its own.
    """
    e = emote(
        Emote(
            key="potter",
            title="THE POTTER",
            category="Reactions",
            entry="nothing stops — the stride just picks up a bounce it did not have before",
            showcase="the whole body bobs to its own slower rhythm, a note drifting along above it",
            exit="the note lifts away and the bounce decays back into the plain walk",
            window=(4.0, 10.4),
            cls="STATE",
            tie="a session that is simply going well",
        )
    )
    a, b = e.window
    gx, gy = glyph_seat(e, 62)

    # Sixteen half-cycles of 0.4 s across the window, amplitude enveloped in and out over two cycles
    # at each end. Ramped rather than switched: a bounce that arrives at full height on its first
    # beat is an onset, and this candidate's whole claim is that nothing announces itself.
    n = 16
    bob: list[tuple[float, float, float]] = []
    pulse: list[tuple[float, float, float]] = []
    for i in range(n + 1):
        t = a + i * 0.4
        f = i / n
        env = max(0.0, min(1.0, f / 0.25, (1.0 - f) / 0.25))
        if i % 2:  # up
            bob.append((t, 0, -14 * env))
            pulse.append((t, 1 - 0.03 * env, 1 + 0.03 * env))
        else:  # down, and the body compresses as the weight lands
            bob.append((t, 0, 0))
            pulse.append((t, 1 + 0.05 * env, 1 - 0.05 * env))

    def front() -> str:
        return glyph("note", gx, gy, "poG")

    def css() -> str:
        return (
            # `.hop` carries the bob and `.rTurn` the compression, because `.bob` is already spoken
            # for: with `walks=True` it holds the stride's own 2 px bounce, and stacking a second
            # animation on it is the exact thing `--lint` refuses.
            shift(
                "poH",
                ".hop",
                [(0, 0, 0)] + bob + [(EMOTE_P, 0, 0)],
                ease="ease-in-out",
            )
            + squash(
                "poB",
                ".rTurn",
                [(0, 1, 1)] + pulse + [(EMOTE_P, 1, 1)],
            )
            + glyph_pop("poGf", ".poG", a + 0.5, b - 0.5, rise=38)
        )

    e.front, e.css = front, css
    return e


_sneeze()
_yawn()
_itch()
_trip()
_delight()
_fright()
_potter()
