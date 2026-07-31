#!/usr/bin/env python3
"""emotes_infra.py — the "What it does" pack: beats that evoke what claude-infrastructure actually does.

THE STEER THIS PACK IS BUILT UNDER, verbatim from the operator: *"representative of our
claude-infrastructure is a BONUS, we just want fun events/emotes over something confusing and
abstract that users won't get that feels forced."* So every candidate here is first a creature doing
a legible thing to a legible piece of world, and only second a reference to a script. Where the two
pulled apart, the picture won. A candidate that could only be built as a gauge, a diagram or an
abstract pulse is reported as FORCED rather than shipped — a viewer who cannot read the beat learns
nothing about the repo either, so accuracy bought with legibility buys nothing at all.

THE FOUR LEGAL GRAMMARS for a relationship, quoted from `docs/research/repo-semantics.md`:
co-location, phase/synchrony, entering or leaving frame, and one creature acting on world furniture.
Illegal, always: a drawn thread, arc, travelling pulse, or arrow. Three of these candidates — THE ONE
GATE, THE FOUR WELLS and THE PROOF — are one drawing decision away from becoming an infographic, and
each is built as creatures-and-terrain for that reason. THE LETTER is the sharpest case: its sender
is never drawn, because the instant an origin creature is visible it is the A-to-B handoff diagram a
prior operator ruling already rejected.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen  # noqa: E402  — the sprite and the palette come from the real banner, never a copy

_HERE = Path(__file__).resolve().parent
_FRAMEWORK = _HERE / "emotes.py"


def _framework():
    """The RUNNING emotes module, found by file identity rather than by name.

    `import emotes` is WRONG here and fails silently, which is the worst way for it to fail.
    `emotes.py` is normally executed as a script, so it lives in `sys.modules` under `__main__`;
    a plain `import emotes` therefore does not find it — it re-executes the file as a SECOND,
    distinct module object with its own empty `EMOTES` list. Every candidate this pack registers
    would land in that copy, `build_all` would iterate the original, and the review page would come
    back with these eight panels simply absent. No error, no traceback, nothing to notice: exactly
    the "a missing panel is indistinguishable from a candidate nobody wrote" failure `load_packs`
    calls the one thing a review surface may never have.

    So: scan the loaded modules for the one whose `__file__` IS `emotes.py`, whatever it is called.
    """
    for m in list(sys.modules.values()):
        f = getattr(m, "__file__", None)
        if not f or not hasattr(m, "emote"):
            continue
        try:
            if Path(f).resolve() == _FRAMEWORK:
                return m
        except OSError:  # a synthetic __file__ that is not a real path
            continue
    import emotes as m  # noqa: PLC0415 — only reachable when emotes.py was never loaded at all

    return m


_fw = _framework()

Emote = _fw.Emote
emote = _fw.emote
egate = _fw.egate
squash = _fw.squash
glyph = _fw.glyph
glyph_pop = _fw.glyph_pop
stop_world = _fw.stop_world
clawd = _fw.clawd
w = _fw.w
wp = _fw.wp
pctx = _fw.pctx
fmt = _fw.fmt

EMOTE_P = _fw.EMOTE_P
G = _fw.E_GROUND  # 330 — the ground rule
SW, SH = _fw.STAGE_W, _fw.STAGE_H  # 760 x 440
SC = _fw.CLAWD_SCALE  # 1.2
CELL = gen.CELL
CAT = "What it does"

# The creature's own extent at the default cx, precomputed because half this pack places furniture
# relative to it and an eyeballed number is exactly what `assert_grounded` exists to forbid.
BODY_L = _fw.CX_DEFAULT
BODY_R = _fw.CX_DEFAULT + gen.SPRITE_W * SC
BODY_T = G - gen.SPRITE_H * SC

# A lit thing must read as LIT in both schemes, which rules out every palette entry: `.eglyph` is
# cream on the dark theme and dark brown on the light one, so a lamp painted with it goes *dark* in
# daylight — the exact opposite of the statement. A fixed warm cream is correct in both, and it is
# far enough off CLAWD's #D77757 not to read as a stray piece of the creature.
LAMP = "#ffd98a"
NIGHT = "#05060c"


# ── local vocabulary ──────────────────────────────────────────────────────────────────────────────
def _rect(x: float, y: float, wd: float, ht: float) -> str:
    return f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(wd)}" height="{fmt(ht)}"/>'


def _steps(name: str, sel: str, rest: float, frames: list[tuple[float, float]]) -> str:
    """A hard-stepped opacity track: (time, opacity), holding each value until the next.

    `steps(1,end)` for the same reason `egate` uses it — an interpolated opacity on a flat pixel
    block is a colour that is not in the palette. Unlike `egate` this carries ARBITRARY levels,
    which is what an ageing stack of copies needs: the ladder of dimness IS the information.

    The rest value is asserted to be where the track ends, because a track that finishes somewhere
    else seams the loop in a way `assert_seamless` cannot see — that gate checks a 100% stop EXISTS,
    not that it agrees with the frame before it.
    """
    if frames and abs(frames[-1][1] - rest) > 1e-9:
        raise SystemExit(
            f"emotes_infra: track '{name}' ends at opacity {frames[-1][1]} but rests at {rest} — "
            f"the loop would visibly snap at the wrap"
        )
    ks = "".join(f"{pctx(t)}%{{opacity:{fmt(o)}}}" for t, o in sorted(frames))
    return (
        f"@keyframes {name}{{0%{{opacity:{fmt(rest)}}}{ks}100%{{opacity:{fmt(rest)}}}}}"
        f"{sel}{{animation:{name} {fmt(EMOTE_P)}s steps(1,end) infinite}}"
    )


def _extra(sfx: str, bob: bool = True) -> str:
    """Everything a SECOND creature needs to be alive rather than inert.

    `gen.clawd_sprite` suffixes every animated and every optional class, so a creature built with
    `sfx="PT"` carries `.legAPT`, `.legsStillPT`, `.armsAlertPT` — and `base_css` names none of
    them. Two independent things go wrong at once and neither reports anything:

      * the OPTIONAL groups are ungated, so they are not hidden, they are ON for the whole loop.
        The visitor renders with its standing legs AND its walking legs, its lids shut over its
        open eyes, and its ears permanently up.
      * the ANIMATED classes are unstyled, so the visitor stands perfectly inert beside a creature
        that is walking.

    Both existing gates pass: `assert_reset_covers_sprite` matches on the class PREFIX, so
    `class="legsStillPT"` is satisfied by the unsuffixed `.legsStill` rule that does not apply to
    it. Only a picture disagrees. This function is the fix, applied per visitor.

    It deliberately does NOT name the unsuffixed groups: `.legsStillPT,` does not contain
    `.legsStill,`, so `assert_css_targets_exist` cannot mistake a visitor's reset for this
    candidate DRIVING a group on the resident.
    """
    css = (
        f".legsStill{sfx},.eShut{sfx},.aShut{sfx},.eyesAsk{sfx},.armsAlert{sfx}{{opacity:0}}"
        f".legA{sfx}{{animation:ewA {fmt(gen.STRIDE)}s steps(1,end) infinite}}"
        f".legB{sfx}{{animation:ewB {fmt(gen.STRIDE)}s steps(1,end) infinite}}"
    )
    if bob:
        css += f".bob{sfx}{{animation:ebob {fmt(gen.STRIDE)}s steps(1,end) infinite}}"
    return css


def _mound(
    x: float, wd: float, ht: float, rows: int = 5, taper: float = 0.72, base: float = G
) -> str:
    """A stepped pile of earth, widest at the bottom, sitting ON the rule.

    Stepped rather than a single rect, and that is the whole difference between terrain and a bar
    chart — `stage_scenery` records the same lesson about the hero clouds ("uniform-width blocks
    read as a bar chart rather than as terrain"). A tapered silhouette cannot be read as a level
    indicator no matter what its height does, which is the ONLY reason THE FOUR WELLS is buildable.

    The taper is steep and the row count high because the first render of THE HEAVY THING YIELDS
    used flat-topped blocks with flat-topped caps and rendered an unmistakable CITY SKYLINE — four
    rows of near-rectangles at the horizon is a downtown, not a range of hills.
    """
    out = []
    rh = ht / rows
    for r in range(rows):
        rw = wd * (1 - taper * (r / rows))
        out.append(_rect(x + (wd - rw) / 2, base - (r + 1) * rh, rw, rh + 1))
    return "".join(out)


def _blades(cx: float, base: float, n: int = 3) -> str:
    """Two or three blades of grass — what makes a pile of earth read as ground rather than as a
    shape. Copied in spirit from `stage_scenery`'s tufts, which cluster for exactly this reason."""
    return "".join(
        _rect(cx + dx, base - dh, 3, dh) for dx, dh in ((-8, 9), (-2, 13), (5, 8))[:n]
    )


# ── 1 · THE COPIES ────────────────────────────────────────────────────────────────────────────────
def _backup() -> Emote:
    """Every write leaves a copy; ten are kept; the oldest ages out.

    The stack recedes to the RIGHT and each slot is a fixed piece of world furniture with a fixed
    age. Nothing moves between slots — the "shift" is six simultaneous opacity steps, which is one
    legible change (the whole ladder ages) rather than six small ones.
    """
    e = Emote(
        key="backup",
        title="THE COPIES",
        category=CAT,
        entry="the stride halts and the creature dips to set one small block down on the ground",
        showcase="behind it, offset ghosts of that block accumulate — each one dimmer than the last",
        exit="it sets another down; every ghost ages one step and the faintest at the back is gone",
        window=(2.8, 8.6),
        cls="BEAT",
        tie="hooks/backup-before-write.sh + scripts/prune-backups.sh — nothing is overwritten, "
        "ten copies are kept, and old ones quietly age out",
    )
    a, b = e.window
    # (x, size, bottom), stacked into the NEAR FOREGROUND rather than along the rule. The first
    # render put them on the horizon at the creature's own depth, where they abutted the ridge
    # silhouettes and read as part of the skyline — small pale cubes sitting in the hills. Down here
    # they are unambiguously objects lying on the ground in front, which is what "set it down" means.
    #
    # The size barely changes and the offset does all the work: an offset copy of THE SAME BLOCK is
    # a ghost, whereas a row of shrinking blocks is a row of different, smaller blocks. Slot 0 is
    # EMPTY through the showcase and is what arrives at the exit, so the newest copy is a new object
    # rather than a re-brightening — a block that blinks reads as a glitch, one that appears reads
    # as an event.
    slots = [
        (500.0, 42.0, 400.0),
        (546.0, 40.0, 393.0),
        (590.0, 38.0, 387.0),
        (630.0, 36.0, 382.0),
        (668.0, 34.0, 378.0),
        (702.0, 32.0, 374.0),
    ]
    show = [0.0, 1.0, 0.58, 0.40, 0.27, 0.17]  # during the showcase
    aged = [
        1.0,
        0.58,
        0.40,
        0.27,
        0.17,
        0.0,
    ]  # after the shift — every rung moves down one
    on_at = [None, 0.10, 0.26, 0.38, 0.49, 0.58]
    off_at = [0.98, 0.95, 0.92, 0.89, 0.86, 0.86]
    shift = 0.74

    def props() -> str:
        return "".join(
            f'<g class="bkS{i}"><g class="eink">{_rect(x, bot - s, s, s)}</g></g>'
            for i, (x, s, bot) in enumerate(slots)
        )

    def css() -> str:
        out = [
            stop_world("bkScr", a, b - 0.5),
            egate("bkStill", ".legsStill", [(a, b - 0.5)]),
            egate("bkWalk", ".legsWalk", [(a, b - 0.5)], on_inside=False),
            # two dips: one per copy set down. The second lands ON the shift, so the cause and the
            # effect share a frame and the ladder's ageing reads as something the creature DID.
            squash(
                "bkDip",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.06), 1.08, 0.90),
                    (w(e, 0.16), 1.0, 1.0),
                    (w(e, 0.68), 1.08, 0.90),
                    (w(e, shift + 0.04), 1.0, 1.0),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            ),
        ]
        for i in range(len(slots)):
            frames: list[tuple[float, float]] = []
            if on_at[i] is not None:
                frames.append((w(e, on_at[i]), show[i]))
            frames.append((w(e, shift), aged[i]))
            frames.append((w(e, off_at[i]), 0.0))
            out.append(_steps(f"bkO{i}", f".bkS{i}", 0.0, frames))
        return "".join(out)

    e.props, e.css = props, css
    return e


# ── 2 · THE ONE GATE ──────────────────────────────────────────────────────────────────────────────
def _gate() -> Emote:
    """Many run at once; exactly one lands at a time.

    The waiting is the picture, so the beat is built entirely out of STILLNESS: two creatures plant
    all four legs and hold while the third keeps striding. Nothing is drawn between them, and the
    notch is one bright cell with two shoulder stones — wide enough and it becomes a turnstile,
    which is the diagram this is one decision away from.
    """
    e = Emote(
        key="gate",
        title="THE ONE GATE",
        category=CAT,
        entry="three of them walking their own lanes, each at its own size, all in step with the world",
        showcase="one bright notch opens in the ground rule and the two flankers stop dead — "
        "four legs planted — while the one at the notch strides on through",
        exit="the notch dims and all three pick the stride back up together",
        window=(3.0, 8.2),
        cls="BEAT",
        tie="scripts/land-lock.sh — one machine-wide mutex: any number may run, exactly one may land",
    )
    a, b = e.window
    hold = (a, b - 0.5)
    nx = BODY_L + gen.SPRITE_W * SC / 2  # under the resident's middle

    def props() -> str:
        return clawd(e, sfx="GL", scale=0.8, x=18) + clawd(
            e, sfx="GR", scale=0.8, x=566
        )

    def front() -> str:
        # In FRONT of the creature, because the resident's own contact shadow is a wide dark ellipse
        # centred on exactly this spot: drawn behind, both the notch and its shoulder stones are
        # simply buried under it. The stones matter — a notch has to be a GAP in something or it is
        # just a lit pixel on the floor — and they are what stops the bright cell reading as a
        # glowing dot rather than as a way through.
        return (
            f'<g class="etuft">{_rect(nx - 36, G - 20, 11, 24)}{_rect(nx + 25, G - 20, 11, 24)}</g>'
            f'<g class="gtN"><rect x="{fmt(nx - 17)}" y="{fmt(G - 7)}" width="34" height="16" '
            f'fill="{LAMP}"/>'
            f'<rect x="{fmt(nx - 25)}" y="{fmt(G - 12)}" width="50" height="26" fill="{LAMP}" '
            f'opacity=".22"/></g>'
        )

    def css() -> str:
        return (
            _extra("GL")
            + _extra("GR")
            + stop_world("gtScr", *hold)
            + egate("gtNo", ".gtN", [hold])
            # the two that WAIT — this is the whole beat. Planted legs alone were not enough to
            # read at this size (walking already shows four legs, just at two heights), so the
            # stop is carried by the SILHOUETTE as well: the ears go up, which is the one
            # whole-body channel measured to survive here.
            + egate("gtSL", ".legsStillGL", [hold])
            + egate("gtWL", ".legsWalkGL", [hold], on_inside=False)
            + egate("gtSR", ".legsStillGR", [hold])
            + egate("gtWR", ".legsWalkGR", [hold], on_inside=False)
            + egate("gtAL", ".armsAlertGL", [hold])
            + egate("gtGL", ".armsGateGL", [hold], on_inside=False)
            + egate("gtAR", ".armsAlertGR", [hold])
            + egate("gtGR", ".armsGateGR", [hold], on_inside=False)
            # ...and the one that GOES: a dip and a hop over the notch, on `.hop`, which the sprite
            # already provides as its own group and which nothing else in this preview animates.
            + f"@keyframes gtHop{{0%,{pctx(a)}%{{transform:translateY(0)}}"
            f"{wp(e, 0.22)}%{{transform:translateY(7px)}}"
            f"{wp(e, 0.36)}%{{transform:translateY(-22px)}}"
            f"{wp(e, 0.50)}%{{transform:translateY(0)}}"
            f"100%{{transform:translateY(0)}}}}"
            f".hop{{animation:gtHop {fmt(EMOTE_P)}s cubic-bezier(.32,.06,.3,1) infinite}}"
        )

    e.props, e.front, e.css = props, front, css
    return e


# ── 3 · THE LIGHT LEFT ON ─────────────────────────────────────────────────────────────────────────
def _nightlight() -> Emote:
    """The machine is deliberately never allowed to sleep.

    A STATE rather than an event, and the only candidate here whose subject is an ABSENCE of change:
    the lamp does nothing at all, and the scene changing around it is what makes that visible. The
    lamp is painted ABOVE the dimming plate for exactly that reason — it is not "brightened during
    the night", it is simply never dimmed, which is the honest depiction of a held assertion.
    """
    e = Emote(
        key="nightlight",
        title="THE LIGHT LEFT ON",
        category=CAT,
        entry="the walk winds down, the world stops, and the whole scene dims toward its darkest",
        showcase="everything goes dark and the creature's eyes shut — except one small lamp, "
        "which never dims at all",
        exit="the light comes back, the stride resumes, and the lamp is exactly as it was",
        window=(2.6, 9.4),
        cls="STATE",
        tie="scripts/caffeinate-floor.sh — a sleep assertion held with no timeout, so the work "
        "carries on while nobody is there",
    )
    a, b = e.window
    doze = (w(e, 0.16), w(e, 0.86))
    lx, lh = 688.0, 34.0  # the lamp post, clear of the creature at 248..512

    def front() -> str:
        return (
            f'<rect class="nlDim" x="0" y="0" width="{SW}" height="{SH}" fill="{NIGHT}"/>'
            # post, halo, head — drawn AFTER the plate, so the dimming cannot reach it
            f'<g class="etuft">{_rect(lx + 5, G - lh, 5, lh)}</g>'
            f'<rect x="{fmt(lx - 6)}" y="{fmt(G - lh - 26)}" width="32" height="32" '
            f'fill="{LAMP}" opacity=".16"/>'
            f'<rect x="{fmt(lx)}" y="{fmt(G - lh - 20)}" width="20" height="20" fill="{LAMP}"/>'
        )

    def css() -> str:
        return (
            stop_world("nlScr", a, b - 0.4)
            + egate("nlStill", ".legsStill", [(a, b - 0.4)])
            + egate("nlWalk", ".legsWalk", [(a, b - 0.4)], on_inside=False)
            # the doze: the ambient 4 s blink is swapped out wholesale for the parked ask-eyes, then
            # their lids are held shut. Gating `.eShut` directly is not available — it already
            # carries the blink, and one animation per element is what makes the freeze exact.
            + egate("nlAsk", ".eyesAsk", [doze])
            + egate("nlLook", ".lookGate", [doze], on_inside=False)
            + egate("nlLid", ".aShut", [doze])
            + egate("nlEye", ".aOpen", [doze], on_inside=False)
            + f"@keyframes nlD{{0%,{pctx(a)}%{{opacity:0}}"
            f"{wp(e, 0.22)}%,{wp(e, 0.80)}%{{opacity:.72}}"
            f"{pctx(b)}%,100%{{opacity:0}}}}"
            f".nlDim{{animation:nlD {fmt(EMOTE_P)}s ease-in-out infinite}}"
        )

    e.front, e.css = front, css
    return e


# ── 4 · THE UNSWITCHED ────────────────────────────────────────────────────────────────────────────
def _staged() -> Emote:
    """Built, staged, and waiting for one human hand.

    The hardest thing in this pack to make visible, because the subject is a thing that is NOT
    running: any depiction of "off" is scenery. The one available move is to make the row large
    enough to read as objects rather than texture, halt the world beside it so the eye has a reason
    to be there, and then give it a single pulse that pointedly stops short of lit.
    """
    e = Emote(
        key="staged",
        title="THE UNSWITCHED",
        category=CAT,
        entry="the stride halts beside a short row of small dark blocks in the near foreground",
        showcase="exactly one of them pulses a single dim frame — never fully lit — and goes dark again",
        exit="the row sits dark, the creature picks its stride back up and walks on past it",
        window=(3.2, 8.0),
        cls="BEAT",
        tie="docs/activation/pending-activation/ — finished, declared, and deliberately not "
        "switched on until the operator says so",
    )
    a, b = e.window
    xs = [140.0, 204.0, 268.0, 332.0, 396.0]
    bw, bh, by = (
        44.0,
        34.0,
        402.0,
    )  # in the near foreground band, well in front of the creature
    hit = 2  # the middle one, directly under the resident

    def props() -> str:
        row = "".join(_rect(x, by - bh, bw, bh) for x in xs)
        # The lamp strips are DARK — one step off the plinth, no more. The first render gave them
        # the ground rule's pale ink and the row read as five things that were already switched ON,
        # which is the precise opposite of what this beat says. Unlit has to look unlit, or the
        # single dim pulse has nothing to be dim against.
        caps = "".join(_rect(x + 8, by - bh - 8, bw - 16, 8) for x in xs)
        return (
            f'<g class="emd1">{row}</g><g class="emd0">{caps}</g>'
            f'<g class="stP"><rect x="{fmt(xs[hit] + 8)}" y="{fmt(by - bh - 8)}" '
            f'width="{fmt(bw - 16)}" height="8" fill="{LAMP}"/></g>'
        )

    def css() -> str:
        return (
            stop_world("stgScr", a, b - 0.5)
            + egate("stgStill", ".legsStill", [(a, b - 0.5)])
            + egate("stgWalk", ".legsWalk", [(a, b - 0.5)], on_inside=False)
            # 0.5, not 1. "Nothing ever fully lights" is the entire content of the beat, so the
            # ceiling is authored rather than eyeballed — and it decays through a second, fainter
            # rung rather than snapping off, so the pulse reads as a thing subsiding rather than as
            # a dropped frame.
            + _steps(
                "stgP",
                ".stP",
                0.0,
                [(w(e, 0.44), 0.5), (w(e, 0.52), 0.2), (w(e, 0.58), 0.0)],
            )
        )

    e.props, e.css = props, css
    return e


# ── 5 · THE HEAVY THING YIELDS ────────────────────────────────────────────────────────────────────
def _standaside() -> Emote:
    """Heavy work self-demotes so it can never slow you down.

    The statement is about two RATES in one frame, so the only thing that may change is the far
    layer's speed — the creature's stride and the ground it walks on are untouched for the whole
    loop, and that is what makes the beat a claim rather than a movement.
    """
    # A tile's worth of travel, spent unevenly: normal drift, a hard acceleration, a long crawl,
    # then normal drift again. The segment distances are made to sum to EXACTLY one tile, which is
    # the only way a variable-rate scroll can loop without a visible jump at the wrap.
    plan = [(0.0, 34.0), (2.6, 110.0), (3.6, 4.0), (8.6, 34.0), (EMOTE_P, 0.0)]
    marks: list[tuple[float, float]] = []
    d = 0.0
    for (t0, v), (t1, _) in zip(plan, plan[1:]):
        marks.append((t0, d))
        d += v * (t1 - t0)
    marks.append((EMOTE_P, d))
    TILE = d

    e = Emote(
        key="standaside",
        title="THE HEAVY THING YIELDS",
        category=CAT,
        entry="the far hills, drifting quietly, suddenly put on speed",
        showcase="they drop to a crawl and stay there — while the creature's stride and the ground "
        "under it never change by a frame",
        exit="the hills quietly pick their normal drift back up",
        window=(2.6, 8.6),
        cls="STATE",
        tie="bin/cc-bats + scripts/qos-census.sh — the heavy job demotes ITSELF to the background "
        "band, so it can never be the reason you are waiting",
    )

    def props() -> str:
        # TWO hills per tile with real sky between them, tapered through five rows. The first render
        # packed four flat-topped blocks with flat-topped caps into the same tile and rendered a
        # CITY SKYLINE — dense, rectangular, and with no gap wide enough to see anything travel
        # through. A speed change is only visible against negative space.
        lumps = "".join(
            _mound(k * TILE + x, wd, ht)
            for k in range(-1, 4)
            for x, wd, ht in ((14, 168, 72), (214, 112, 44))
        )
        return f'<g class="saH"><g class="emd0">{lumps}</g></g>'

    def css() -> str:
        ks = "".join(
            f"{pctx(t)}%{{transform:translateX(-{fmt(dist)}px)}}" for t, dist in marks
        )
        return f"@keyframes saH{{{ks}}}.saH{{animation:saH {fmt(EMOTE_P)}s linear infinite}}"

    e.props, e.css = props, css
    return e


# ── 6 · THE LETTER ────────────────────────────────────────────────────────────────────────────────
def _letter() -> Emote:
    """A message waits in a file until the reader is at a safe boundary.

    THE SENDER IS NEVER DRAWN, and that is a hard constraint rather than a preference: the moment a
    second creature is visible as the origin, this is the A-to-B handoff infographic a prior
    operator ruling rejected. The letter arrives from off-frame, full stop.

    The WAITING is the payload. The creature walks on for four full seconds with the thing sitting
    at its feet, because "it is not an interrupt" is only legible as an interruption that visibly
    does not happen.
    """
    e = Emote(
        key="letter",
        title="THE LETTER",
        category=CAT,
        entry="something drops in from above the frame and lands by the creature's feet",
        showcase="it just sits there — the creature keeps walking, unbothered, for a good four seconds",
        exit="at the creature's own next pause it is taken, gone in a single frame, with a small spark",
        window=(2.2, 9.6),
        cls="BEAT",
        tie="bin/cc-notify + hooks/mailbox-drain.sh — a message is a line in a file that waits for "
        "a safe boundary, never keystrokes on a live input line",
    )
    a, b = e.window
    lx, lw, lh = 526.0, 50.0, 34.0
    lbot = (
        G + 22
    )  # clear of the ridge silhouettes, unambiguously lying on the near ground
    pause = (w(e, 0.76), w(e, 0.94))
    take = w(e, 0.82)
    gx = BODY_L + gen.SPRITE_W * SC / 2
    gy = BODY_T - 46

    def front() -> str:
        y = lbot - lh
        chev = "".join(
            _rect(lx + 6 + 5 * k, y + 6 + 4 * k, 5, 4)
            + _rect(lx + lw - 11 - 5 * k, y + 6 + 4 * k, 5, 4)
            for k in range(3)
        )
        return (
            f'<g class="ltG"><g class="ltF">'
            f'<g class="eglyph">{_rect(lx, y, lw, lh)}</g>'
            f'<g class="efg">{chev}</g>'
            f"</g></g>" + glyph("spark", gx, gy, "ltS")
        )

    def css() -> str:
        return (
            stop_world("ltScr", *pause)
            + egate("ltStill", ".legsStill", [pause])
            + egate("ltWalk", ".legsWalk", [pause], on_inside=False)
            # Two elements, one animation each: the outer group is the hard on/off (taken in a
            # single frame, never dissolved), the inner one is the fall. Folding both into one
            # track would force one timing function on a drop that must ease and a disappearance
            # that must not.
            + egate("ltGo", ".ltG", [(take, EMOTE_P - 0.2)], on_inside=False)
            + f"@keyframes ltF{{0%,{pctx(a)}%{{transform:translateY(-400px)}}"
            f"{wp(e, 0.05)}%{{transform:translateY(0)}}"
            f"{wp(e, 0.08)}%{{transform:translateY(-22px)}}"
            f"{wp(e, 0.12)}%{{transform:translateY(0)}}"
            f"{pctx(take)}%{{transform:translateY(0)}}"
            f"{pctx(take + 0.1)}%,100%{{transform:translateY(-400px)}}}}"
            f".ltF{{animation:ltF {fmt(EMOTE_P)}s cubic-bezier(.5,0,.75,0) infinite}}"
            + glyph_pop("ltSf", ".ltS", take + 0.02, w(e, 0.96))
        )

    e.front, e.css = front, css
    return e


# ── 7 · THE FOUR WELLS ────────────────────────────────────────────────────────────────────────────
def _wells() -> Emote:
    """Four accounts, four budgets, each on its own clock.

    THE RISK NAMED IN ADVANCE: four level indicators is one step from a HUD. So the marks are piles
    of earth with grass on them, stepped and tapered, whose HEIGHT is what changes — a shape that
    tapers cannot be read as a gauge, and grass that sinks with it cannot be read as a bar. Nothing
    is drawn between the drained pile and where the little one goes; it simply walks, and passes
    BEHIND the resident on the way, which is the co-location grammar rather than a path.
    """
    e = Emote(
        key="wells",
        title="THE FOUR WELLS",
        category=CAT,
        entry="four piles of earth along the ground, each a different height, a small one grazing at the second",
        showcase="that pile sinks away to nothing — and the small one just walks off to a fuller one, "
        "passing behind the resident on the way",
        exit="the emptied pile creeps back up from flat, in its own time",
        window=(2.4, 10.0),
        cls="BEAT",
        tie="bin/claude-accounts — four accounts, four budgets, each emptying and refilling on its "
        "own five-hour clock; when one is dry the work simply happens elsewhere",
    )
    # Laid out around the resident's own footprint (248..512) so nothing is hidden behind it at
    # rest, and the grazer's route crosses that footprint on the way. The first render put the piles
    # in `.emd0` at the horizon, where they abutted the ridge silhouettes and simply disappeared
    # into them — terrain the same colour as terrain is not terrain, it is nothing.
    piles = [
        (6.0, 46.0, 34.0),
        (62.0, 68.0, 66.0),  # the one that runs dry
        (540.0, 54.0, 38.0),
        (632.0, 76.0, 58.0),
    ]
    dry = 1
    trek = (w(e, 0.22), w(e, 0.62))
    wx0, wsc = 136.0, 0.5
    wdx = 424.0  # ends among the two full piles on the right

    def props() -> str:
        out = []
        for i, (x, wd, ht) in enumerate(piles):
            grp = (
                f'<g class="etuft">{_mound(x, wd, ht)}</g>'
                f'<g class="eink">{_blades(x + wd / 2, G - ht)}</g>'
            )
            if i == dry:
                # transform-origin pinned to the pile's own footing, so it drains INTO the ground
                # rather than shrinking toward its middle and hovering. The grass rides inside the
                # same group: grass that sinks with the earth is terrain, grass left floating over
                # a shrinking block is a bar chart with a decoration on it.
                out.append(
                    f'<g class="wlD" style="transform-origin:{fmt(x + wd / 2)}px {fmt(G)}px">'
                    f"{grp}</g>"
                )
            else:
                out.append(grp)
        # the grazer, drawn BEHIND the resident so its walk passes behind a solid body — an
        # occluder is the fourth legal grammar, and it costs nothing here
        out.append(f'<g class="wlW">{clawd(e, sfx="WK", scale=wsc, x=wx0)}</g>')
        return "".join(out)

    def css() -> str:
        return (
            _extra("WK") + f"@keyframes wlD{{0%,{wp(e, 0.02)}%{{transform:scaleY(1)}}"
            f"{wp(e, 0.30)}%,{wp(e, 0.58)}%{{transform:scaleY(0)}}"
            f"{wp(e, 0.98)}%,100%{{transform:scaleY(1)}}}}"
            f".wlD{{animation:wlD {fmt(EMOTE_P)}s ease-in-out infinite}}"
            # ...and it WALKS BACK during the air, rather than snapping home at the wrap. A track
            # that ends 424 px from where it starts is a seam the seam-gate cannot see — that one
            # checks a 100% stop EXISTS, not that it agrees with the frame before it — and the
            # return trip is the true thing anyway: the pile refilled, so the work comes back.
             + f"@keyframes wlW{{0%,{pctx(trek[0])}%{{transform:translateX(0)}}"
            f"{pctx(trek[1])}%,{pctx(10.2)}%{{transform:translateX({fmt(wdx)}px)}}"
            f"{pctx(11.9)}%,100%{{transform:translateX(0)}}}}"
            f".wlW{{animation:wlW {fmt(EMOTE_P)}s ease-in-out infinite}}"
        )

    e.props, e.css = props, css
    return e


# ── 8 · THE PROOF ─────────────────────────────────────────────────────────────────────────────────
def _patience() -> Emote:
    """Nothing is cleaned up unless it can be PROVED dead. Idle is not done.

    The beat is a thing that repeatedly does NOT happen, which is the hardest shape to draw, so it
    is built as a rhythm with an obvious slot for the removal: a shadow sweeps, and you expect the
    still creature to be gone behind it. It is not. A second sweeps; still not. The third time it
    is, and the surprise of the first two is what gives the third its meaning.

    It comes BACK by walking in from off-frame — never by fading up — which both closes the loop
    seamlessly and says the true thing: a new one arrives, the old one was not merely hidden.
    """
    e = Emote(
        key="patience",
        title="THE PROOF",
        category=CAT,
        entry="a second, smaller creature at the right edge stops dead mid-stride and plants all four legs",
        showcase="a wide slow shadow sweeps the whole scene and it is NOT taken — it is still there. "
        "A second shadow sweeps; still there",
        exit="only then, in one frame, it is gone — and a new one walks in from off-frame to take the spot",
        window=(2.4, 9.6),
        cls="BEAT",
        tie="bin/cc-reaper — a session is only reaped on positive evidence of death; going quiet is "
        "never evidence, because idle is not done",
    )
    a, b = e.window
    gone, back = 9.4, 10.4
    still = (a, gone)
    px, psc = 592.0, 0.7
    # Narrower and darker than the first pass, which spread a .46 peak over 460 px and rendered a
    # gradient nobody would call a shadow. The surprise this beat depends on — "surely THAT took
    # it" — cannot land if the sweep is not unmistakably an event.
    band = 340.0
    sweeps = ((3.0, 5.2), (5.7, 7.9))

    def props() -> str:
        return f'<g class="ptG"><g class="ptI">{clawd(e, sfx="PT", scale=psc, x=px)}</g></g>'

    def front() -> str:
        return (
            f'<defs><linearGradient id="ptsh" x1="0" y1="0" x2="1" y2="0">'
            f'<stop offset="0" stop-color="{NIGHT}" stop-opacity="0"/>'
            f'<stop offset=".5" stop-color="{NIGHT}" stop-opacity=".68"/>'
            f'<stop offset="1" stop-color="{NIGHT}" stop-opacity="0"/></linearGradient></defs>'
            f'<rect class="ptS" x="{fmt(-band)}" y="0" width="{fmt(band)}" height="{SH}" '
            f'fill="url(#ptsh)"/>'
        )

    def css() -> str:
        run = SW + band
        (s0, s1), (s2, s3) = sweeps
        return (
            _extra("PT")
            + egate("ptSt", ".legsStillPT", [still])
            + egate("ptWk", ".legsWalkPT", [still], on_inside=False)
            # gone in one frame, back by WALKING. The reposition to off-frame right happens inside
            # the hidden window, so nothing teleports in view.
            + egate("ptGo", ".ptG", [(gone, back)], on_inside=False)
            + f"@keyframes ptI{{0%,{pctx(gone + 0.2)}%{{transform:translateX(0);"
            f"animation-timing-function:steps(1,end)}}"
            f"{pctx(gone + 0.3)}%,{pctx(back)}%{{transform:translateX(300px);"
            f"animation-timing-function:ease-out}}"
            f"{pctx(11.7)}%,100%{{transform:translateX(0)}}}}"
            f".ptI{{animation:ptI {fmt(EMOTE_P)}s linear infinite}}"
            # one element, two passes: the return trip is a hard step taken while the band is
            # parked off-frame left, so it is never seen travelling backwards.
             + f"@keyframes ptS{{0%,{pctx(s0)}%{{transform:translateX(0)}}"
            f"{pctx(s1)}%{{transform:translateX({fmt(run)}px);"
            f"animation-timing-function:steps(1,end)}}"
            f"{pctx(s2)}%{{transform:translateX(0);animation-timing-function:linear}}"
            f"{pctx(s3)}%,100%{{transform:translateX({fmt(run)}px)}}}}"
            f".ptS{{animation:ptS {fmt(EMOTE_P)}s linear infinite}}"
        )

    e.props, e.front, e.css = props, front, css
    return e


emote(_backup())
emote(_gate())
emote(_nightlight())
emote(_staged())
emote(_standaside())
emote(_letter())
emote(_wells())
emote(_patience())
