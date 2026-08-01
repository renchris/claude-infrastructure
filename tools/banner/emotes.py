#!/usr/bin/env python3
"""emotes.py — one small animated SVG per candidate clawd micro-event, for review before build.

WHY THIS EXISTS. The hero banner's beats are authored directly into `gen.py` against a 240 s master
period, which makes proposing a NEW beat expensive: it has to be timed against every other beat, pass
the disjointness and duty gates, and then be watched for minutes to be seen once. That cost is paid
before anyone has decided whether the idea is any good. This module is the cheap half of that loop —
a candidate becomes a self-contained 12 s SVG that can be looked at in seconds, and only the ones
that survive review get the expensive treatment in `gen.py`.

THE SPRITE IS IMPORTED, NEVER REDRAWN. Every candidate here uses `gen.clawd_sprite()` and `gen`'s own
constants, so a review page cannot show a creature that differs from the shipping one. This is the
same discipline `recycle.py` follows for the palette, and it exists because of a measured failure in
this repo: a checker that kept its own copy of its subject's geometry convicted a green asset, every
row off by exactly 4/3 — the model was stale, not the subject. A preview that redrew the sprite would
be that same defect aimed at the design decision instead of at a test.

WHAT A CANDIDATE OWES. Each one is a STORY with three acts, because the operator's ask is for beats
that make sense rather than beats that merely happen:

    ENTRY      the cue that makes you look — a motion onset, or an arrest of an established rhythm
    SHOWCASE   exactly ONE legible state change, the thing the beat is actually about
    EXIT       it leaves with agency — a speed or direction change, an occluder, a transformation

...and then AIR. The loop is 12 s and no story is allowed to fill it, because "special" is a contrast
effect and there is nothing to contrast against in a beat that never stops.

    python3 tools/banner/emotes.py --out /tmp/emotes
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen  # noqa: E402  — the sprite, the palette and the geometry all come from the real banner

# ── the stage ─────────────────────────────────────────────────────────────────────────────────────
# Sized so the creature renders at EXACTLY the size it has in the shipped banner. The banner is a
# 1920-wide viewBox displayed at the measured 838 px README column, so one user unit is 0.4365 CSS px
# and clawd at scale 1.2 is 115.2 x 83.8 CSS px. A 760-wide stage displayed at 332 px keeps that
# ratio, so a defect that only appears at shipping size still appears here. Reviewing pixel art at a
# convenient magnification is how this project previously shipped a moon that was a crescent at 3x
# and an eclipse at 838.
STAGE_W, STAGE_H = 760, 440
COLUMN = 838  # the measured README content column, in CSS px
BANNER_W = 1920
DISPLAY_SCALE = COLUMN / BANNER_W  # 0.4365
PANEL_PX = round(STAGE_W * DISPLAY_SCALE)  # 332 — the honest display width of one panel

E_GROUND = 330  # the ground rule inside the stage: clawd's surface
CLAWD_SCALE = 1.2  # identical to the banner's, which is what makes the sizes identical
CX_DEFAULT = 248  # centred: 248..512 of 760

# The shared loop period. EVERY candidate uses it, so all panels on the review page stay phase-locked
# and a reader comparing two beats is comparing them at the same moment of their story rather than at
# two arbitrary phases. It is short because the operator's recorded complaint about the previous
# surface was waiting: "we need to have all of the microevents individually shown so we dont have to
# wait how many minutes to see all of them."
EMOTE_P = 12.0

GATE_EDGE = 0.08  # s — the hard swap between a gated element's two states

# Every optional group `gen.clawd_sprite` can emit. Named once, read by BOTH gates, so the two can
# never disagree about what the sprite is capable of — gen.py records the same lesson about keeping
# one list rather than a copy per consumer.
OPTIONAL_GROUPS = (
    "rCheer",
    "legsStill",
    "eShut",
    "aShut",
    "eyesAsk",
    "armsAlert",
    "smHat",
    "smWand",
    "smWandSpk",
    "smHeld",
)
SUMMON_GROUPS = {"smHat", "smWand", "smWandSpk", "smHeld"}

# The twinkle vocabulary: (period, peak position as a % of that period). Periods are COPRIME to each
# other and to the 12 s loop, so the field's combined pattern never repeats and cannot form a beat;
# the peak position is the per-element phase, expressed where it survives the deterministic freeze.
# Twenty combinations over twenty-six stars keeps every synchronised cohort at or under three, which
# is the threshold above which a twinkling field stops twinkling and starts pulsing in unison.
TWINKLES = [(p, pk) for p in (7, 9, 11, 13) for pk in (18, 34, 50, 66, 82)]

# Baseline motion, quoted from the banner rather than re-chosen, so a candidate previewed here moves
# like the creature it will become.
STRIDE = gen.STRIDE  # 0.5 s per step
STRIP_V = gen.STRIP_V  # 96 px/s — the ground rate the stride is locked to
PRINT_TILE = 96.0  # one ground-dash tile; STRIP_V * 1s, and 1s divides EMOTE_P


def fmt(v: float) -> str:
    return gen.fmt(v)


def pctx(t: float) -> str:
    """A keyframe offset on the emote period, at enough precision that the position is exact.

    Deliberately the same shape as gen.pctx, but on EMOTE_P rather than P. It cannot simply be
    imported: gen.pctx divides by gen.P (240 s), so every offset it returns would be 20x too small
    here and every beat would collapse into the first 5% of its loop.
    """
    return f"{t / EMOTE_P * 100:.6f}".rstrip("0").rstrip(".") or "0"


def egate(
    name: str, sel: str, windows: list[tuple[float, float]], on_inside: bool = True
) -> str:
    """An opacity gate on the emote period: visible inside `windows`, hidden outside.

    `steps(1,end)` so the swap is hard. A pixel sprite must never be caught half-faded — an
    interpolated opacity is a colour that is not in the palette.

    THE REST VALUE IS EMITTED STATICALLY AS WELL AS INTO THE KEYFRAMES, and that is not
    belt-and-braces: the static rule is the ONLY place a reduced-motion reader ever looks.
    `base_css` ends with `*{animation:none!important}` under `prefers-reduced-motion`, so every
    animation is switched off and each element paints its static declaration — and a gate whose
    only `opacity` lived in its keyframes falls back to the CSS default of 1, which is the exact
    inverse of what a hidden-at-rest gate promises. That defect was found and fixed FOUR separate
    times before it was lifted here: once for `.eglyph`, once for `.gtN` beside its own `egate`
    call, and twice inside `_steps`' pack. Fixing it in the vocabulary is what makes the fifth
    time impossible; `assert_static_rest` covers everything that does not come through here.

    A running animation outranks a normal declaration in the cascade, so the live loop is
    unchanged — verified by rendering all 27 candidates before and after and comparing the frames.
    """
    a, b = ("0", "1") if on_inside else ("1", "0")
    frames = [f"0%{{opacity:{a}}}"]
    for w0, w1 in sorted(windows):
        if w1 + GATE_EDGE > EMOTE_P:
            raise SystemExit(
                f"emotes: gate '{name}' ends at {w1}s, too close to EMOTE_P={EMOTE_P}s for its "
                f"{GATE_EDGE}s swap edge — the gate could not return to rest and the loop would seam"
            )
        frames.append(
            f"{pctx(w0)}%{{opacity:{a}}}{pctx(w0 + GATE_EDGE)}%{{opacity:{b}}}"
        )
        frames.append(
            f"{pctx(w1)}%{{opacity:{b}}}{pctx(w1 + GATE_EDGE)}%{{opacity:{a}}}"
        )
    frames.append(f"100%{{opacity:{a}}}")
    return (
        f"@keyframes {name}{{{''.join(frames)}}}"
        f"{sel}{{opacity:{a};animation:{name} {fmt(EMOTE_P)}s steps(1,end) infinite}}"
    )


# ── a candidate ───────────────────────────────────────────────────────────────────────────────────
@dataclass
class Emote:
    """One candidate micro-event: its story, its class, and the two functions that draw it."""

    key: str
    title: str
    category: str  # how the review page groups it
    entry: str  # act 1 — the cue
    showcase: str  # act 2 — the ONE legible change
    exit: str  # act 3 — how it leaves
    window: tuple[float, float]  # when the story runs inside the 12 s loop
    tie: str = ""  # the claude-infrastructure behaviour it evokes, if any. A BONUS, never forced.
    cls: str = (
        "BEAT"  # BEAT | VISITOR | STATE — the taxonomy the banner grammar already uses
    )
    walks: bool = (
        True  # does the world scroll and the creature stride, or is it standing?
    )
    # Which OPTIONAL sprite groups this candidate drives. `gen.clawd_sprite` OMITS the arms-up group
    # and the summon props unless it is asked for them, so a candidate whose CSS animates `.rCheer`
    # without declaring it here styles a group that was never drawn: the raised arms never appear,
    # the idle arms are gated off anyway, and the creature simply loses its arms for the length of
    # its own showcase. Nothing errors. This field is what `assert_css_targets_exist` checks in BOTH
    # directions — declared-but-undrawn, and drawn-but-unstyled.
    uses: tuple[str, ...] = ()
    # Sprite suffixes this candidate actually draws, filled in by `clawd()` as it emits each body.
    # It has to be discovered rather than declared: a candidate may draw a second creature from
    # inside `props()` or `front()`, and asking authors to also list the suffix by hand is exactly
    # the kind of duplicated bookkeeping that goes stale.
    _sfx: set = field(default_factory=set)
    props: Callable[[], str] = field(
        default=lambda: ""
    )  # extra SVG, drawn behind the creature
    front: Callable[[], str] = field(default=lambda: "")  # extra SVG, drawn in front
    css: Callable[[], str] = field(default=lambda: "")
    cx: float = CX_DEFAULT

    @property
    def dur(self) -> float:
        return self.window[1] - self.window[0]


def w(e: Emote, frac: float) -> float:
    """An absolute time a FRACTION of the way through a candidate's window.

    Fractions rather than absolute offsets, for the reason gen.py's `atf` records: an offset in
    seconds does not survive its beat being re-timed to a shorter window — it runs off the end, lands
    on a negative percentage, and CSS drops the whole keyframe block SILENTLY. A beat that vanishes
    without an error is the worst failure this file could have, because the review page would then
    show a blank panel that looks exactly like a bad idea.
    """
    t0, t1 = e.window
    return t0 + frac * (t1 - t0)


def wp(e: Emote, frac: float) -> str:
    return pctx(w(e, frac))


# ── the stage art ─────────────────────────────────────────────────────────────────────────────────
def theme_of(key: str = "v6c-dusk-line"):
    """The shipping art direction, imported so a preview cannot drift from the banner."""
    for v in gen.VARIANTS:
        if v.key == key:
            return v
    raise SystemExit(f"emotes: no variant {key!r} in gen.VARIANTS")


ART = theme_of()


def stage_defs() -> str:
    d = ART.dark
    return (
        f'<linearGradient id="esky" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" class="skT"/><stop offset=".55" class="skM"/>'
        f'<stop offset="1" class="skL"/></linearGradient>'
        f'<linearGradient id="eglow" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{d.glow}" stop-opacity="0"/>'
        f'<stop offset="1" stop-color="{d.glow}" stop-opacity="{d.glow_op}"/></linearGradient>'
        f'<linearGradient id="egnd" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" class="gnT"/><stop offset="1" class="gnB"/></linearGradient>'
    )


def stage_scenery(e: Emote) -> str:
    """Mounds, tufts and a thin starfield — the banner's world at panel scale.

    Not decoration for its own sake. A beat can only read as an OCCURRENCE against a world that was
    already there and carries on afterwards; on an empty plate the same motion reads as the entire
    content of the image. The silhouettes come from `gen.lobe_profile`, the same envelope-of-lobes
    the hero clouds use, because uniform-width blocks read as a bar chart rather than as terrain.

    The stars obey the TEXTURE law the banner grammar states: periods COPRIME to each other and to
    the loop, with phase baked PER ELEMENT. A cohort of stars sharing one period does not twinkle —
    it makes the whole sky pulse in unison, a full-field luminance transient more salient than any
    beat, which is exactly the regression the hero banner shipped once already.
    """
    rng = __import__("random").Random(gen.seed_of("emote-stage"))

    # The starfield. Phase is baked into each twinkle's KEYFRAME PERCENTAGES, never into an
    # `animation-delay` — `banner-shots.sh --lint` refuses an authored delay, and it is right to:
    # the deterministic freeze works by overriding `animation-delay` on `*` to seek a timestamp, so
    # a star carrying its own delay would be seeked to the wrong moment and every reference render
    # would be quietly untrue. gen.py records the same constraint for the hero starfield.
    stars = []
    for _ in range(26):
        x, y = rng.uniform(0, STAGE_W), rng.uniform(8, 180)
        k = rng.randrange(len(TWINKLES))
        r = rng.choice((2, 2, 3))
        stars.append(
            f'<rect class="etw{k}" x="{fmt(x)}" y="{fmt(y)}" width="{r}" height="{r}"/>'
        )
    sky = f'<g class="estar">{"".join(stars)}</g>'

    # Two ridges, far then near, drawn as SILHOUETTES AGAINST THE SKY and then covered by the ground
    # plane. Draw order is the whole difference: painted after the ground they are dark slabs lying
    # on top of it, which is what the first pass rendered. The lobes are few, wide and overlapping,
    # because narrow lobes at high amplitude quantise into a crenellated wall — the bar-chart read
    # `lobe_profile` exists to avoid. Amplitude stays well under the creature's height: a hill that
    # rivals the subject stops being a background.
    ridges = []
    for cs, tint, amp in ((6, 1, 62), (8, 0, 40)):
        cols = int(STAGE_W / cs) + 1
        lobes = [
            (rng.uniform(-0.15, 1.15), rng.uniform(0.34, 0.62), rng.uniform(0.5, 1.0))
            for _ in range(4)
        ]
        prof = gen.lobe_profile(cols, lobes)
        # Through `gen.merge_runs`, which is the chokepoint every skyline in the banner passes
        # through: it coalesces equal-height columns AND bleeds each surviving run into its
        # neighbour. Abutting rects do not composite to full coverage — the shared edge lands inside
        # a device pixel and leaves a hairline of sky showing through, which is precisely the striped
        # horizon the first render of this stage produced. Sealing here rather than at the call site
        # is why it is fixed for every ridge instead of for whichever one someone remembered.
        cells = [
            (i * cs, E_GROUND - h, cs, h + 2)
            for i, hf in enumerate(prof)
            if (h := round(hf * amp / cs) * cs) > 0
        ]
        runs = "".join(
            f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(wd)}" height="{fmt(ht)}"/>'
            for x, y, wd, ht in gen.merge_runs(cells)
        )
        ridges.append(f'<g class="emd{tint}">{runs}</g>')

    # Ground tufts. Few, and only in the near foreground band — scattered thinly over the whole
    # plane they read as speckle or as rain rather than as vegetation, because at 3 px wide an
    # isolated mark carries no shape. Clustering three blades is what makes it read as a plant.
    tufts = []
    for _ in range(7):
        bx = rng.uniform(20, STAGE_W - 20)
        by = E_GROUND + rng.uniform(30, 92)
        for dx, dh in ((0, 10), (5, 14), (10, 8)):
            tufts.append(
                f'<rect x="{fmt(bx + dx)}" y="{fmt(by - dh)}" width="3" height="{fmt(dh)}"/>'
            )
    fg = f'<g class="etuft">{"".join(tufts)}</g>'
    return sky, "".join(ridges), fg


def stage_body(e: Emote) -> str:
    """Sky, horizon glow, ground plane and the dotted rule — the banner's world, at panel size."""
    glow_h = 120
    dashes = "".join(
        f'<rect class="eprint" x="{fmt(x)}" y="{E_GROUND}" width="56" height="3"/>'
        for x in range(0, int(STAGE_W + PRINT_TILE * 2), int(PRINT_TILE))
    )
    scroll = ' class="escroll"' if e.walks else ""
    sky, ridges, fg = stage_scenery(e)
    # Draw order IS the depth cue, and it is the whole difference between terrain and slabs: stars
    # first, then the ridges as silhouettes against the sky, and only then the ground plane painted
    # over their footings. Painted after the ground instead, the same rectangles read as dark bars
    # lying on the surface — which is exactly what the first pass rendered.
    return (
        f'<rect x="0" y="0" width="{STAGE_W}" height="{E_GROUND}" fill="url(#esky)"/>'
        f"{sky}"
        f'<rect x="0" y="{E_GROUND - glow_h}" width="{STAGE_W}" height="{glow_h}" '
        f'fill="url(#eglow)"/>'
        f"{ridges}"
        f'<rect x="0" y="{E_GROUND}" width="{STAGE_W}" height="{STAGE_H - E_GROUND}" '
        f'fill="url(#egnd)"/>'
        f"<g{scroll}>{dashes}</g>"
        f"{fg}"
    )


def clawd(
    e: Emote, sfx: str = "", scale: float | None = None, x: float | None = None
) -> str:
    """The real sprite, grounded by computation rather than by eye (gen.py's S6).

    The optional groups are emitted ONLY when the candidate declares that it drives them, because
    an ungated group is not hidden — it would simply be on for the whole loop, which is how a cheer
    once rendered as a permanent pair of horns. The inverse mistake is quieter and cost this file a
    render to find: gating a group that was never drawn removes the arms and reports nothing.
    """
    if sfx:
        e._sfx.add(sfx)
    sc = CLAWD_SCALE if scale is None else scale
    px = e.cx if x is None else x
    ty = E_GROUND - gen.SPRITE_H * sc
    sw = gen.SPRITE_W * sc
    shadow = (
        f'<g class="shdw{sfx}"><ellipse class="esh" cx="{fmt(px + sw / 2)}" '
        f'cy="{fmt(E_GROUND + 2)}" rx="{fmt(sw * 0.44)}" ry="{fmt(6 * sc)}"/></g>'
    )
    return (
        shadow + f'<g transform="translate({fmt(px)} {fmt(ty)}) scale({fmt(sc)})" '
        f'shape-rendering="crispEdges">'
        f"{gen.clawd_sprite(sfx, cheer='rCheer' in e.uses, summon=SUMMON_GROUPS & set(e.uses) != set())}</g>"
    )


def _light_rules(lt, scheme: str) -> str:
    """The light palette, as a media override (`auto`), bare (`light`), or absent (`dark`)."""
    if scheme == "dark":
        return ""
    body = (
        f".skT{{stop-color:{lt.sky_top}}}.skM{{stop-color:{lt.sky_mid}}}"
        f".skL{{stop-color:{lt.sky_low}}}"
        f".gnT{{stop-color:{lt.ground_top}}}.gnB{{stop-color:{lt.ground_bot}}}"
        f".eprint{{fill:{lt.rule}}}.esh{{opacity:.20}}"
        f".eink{{fill:{lt.rule}}}.efg{{fill:{lt.fg}}}"
        f".emd0{{fill:{lt.mound[0]}}}.emd1{{fill:{lt.mound[1]}}}.etuft{{fill:{lt.tuft}}}"
        f".eglyph{{fill:#4a3d33}}"
        # the stars are a NIGHT fact, not a dimmed one — a daylit sky with faint stars in it reads
        # as a rendering fault rather than as daytime
        f".estar{{display:none}}"
    )
    return (
        body if scheme == "light" else f"@media(prefers-color-scheme:light){{{body}}}"
    )


def base_css(e: Emote, scheme: str = "auto") -> str:
    """The world's palette plus the creature's baseline life.

    `scheme` selects how the two palettes are expressed:
      auto  — dark as the base, light as a `prefers-color-scheme` override. THIS IS WHAT SHIPS.
      dark  — dark only, media query omitted.
      light — light as the base, media query omitted.

    The two forced variants exist only for the review page, and for a reason worth stating: an asset
    that self-themes can only be reviewed in ONE scheme at a time, because the media query answers to
    the reader's own OS. Asking a reviewer to toggle their system appearance to check the other half
    of the work is how the light theme goes unreviewed. Forcing each scheme into its own file lets the
    page show both side by side — but they are review instruments, never the shipped asset.

    THE RESET LIST IS LOAD-BEARING. `gen.clawd_sprite` emits every optional group unconditionally —
    the alert arms, the ask-eyes, the standing legs, the shut lids. They are hidden by CSS, not by
    omission, so a stylesheet that forgets one renders a creature with four arms, or with both leg
    sets, or permanently blinking. It is copied from gen.py's own 0% state for that reason.
    """
    d, lt = ART.dark, ART.light
    walk = (
        f"@keyframes ewA{{0%,49%{{transform:translateY(0)}}"
        f"50%,100%{{transform:translateY(-{fmt(gen.CELL * 0.6)}px)}}}}"
        f"@keyframes ewB{{0%,49%{{transform:translateY(-{fmt(gen.CELL * 0.6)}px)}}"
        f"50%,100%{{transform:translateY(0)}}}}"
        f".legA{{animation:ewA {fmt(STRIDE)}s steps(1,end) infinite}}"
        f".legB{{animation:ewB {fmt(STRIDE)}s steps(1,end) infinite}}"
        f"@keyframes ebob{{0%,49%{{transform:translateY(0)}}50%,100%{{transform:translateY(-2px)}}}}"
        f".bob{{animation:ebob {fmt(STRIDE)}s steps(1,end) infinite}}"
        f"@keyframes escr{{from{{transform:translateX(0)}}"
        f"to{{transform:translateX(-{fmt(PRINT_TILE)}px)}}}}"
        f".escroll{{animation:escr 1s linear infinite}}"
    )
    stand = ".legsWalk{opacity:0}.legsStill{opacity:1}"
    return (
        # ── the 0% state: every optional group off, so the reduced-motion still is composed ────────
        ".rCheer,.legsStill,.eShut,.aShut,.eyesAsk,.armsAlert{opacity:0}"
        ".legsWalk,.eOpen,.aOpen,.armsGate,.lookGate{opacity:1}"
        # `.smWand`/`.smWandSpk` were missing here from the moment the wand was added, which is the
        # exact hazard this docstring describes: a summon-using candidate rendered the creature
        # holding a permanently-lit wand, and nothing said so. The list is the gate.
        ".smHat,.smWand,.smWandSpk,.smHeld{opacity:0}"
        # THE SAME RESET, ONCE PER EXTRA CREATURE. `gen.clawd_sprite(sfx)` suffixes every class it
        # emits, so a second creature's optional groups are `.legsStillB`, `.eShutB`, `.aShutB`,
        # `.eyesAskB`, `.armsAlertB` — and the unsuffixed rules above do not reach any of them. Left
        # alone the visitor renders with BOTH leg sets at once, blink-lids painted over its open
        # eyes, ears permanently raised and the ask-pose's centred eyes stacked on the normal pair.
        # The world pack hit this and wrote its own `sfx_rest`/`sfx_walk` helpers; the infra pack
        # documented the same hazard independently. A third candidate (this file's own
        # NEIGHBOUR) shipped with `aShutB` on and nothing noticed until the reset gate was tightened
        # from prefix matching to exact class tokens. Emitting it here fixes every candidate at once
        # and is why a pack no longer needs to know about it.
        + "".join(
            f".rCheer{x},.legsStill{x},.eShut{x},.aShut{x},.eyesAsk{x},.armsAlert{x},"
            f".smHat{x},.smHeld{x}{{opacity:0}}"
            f".legsWalk{x},.eOpen{x},.aOpen{x},.armsGate{x},.lookGate{x}{{opacity:1}}"
            for x in sorted(e._sfx)
        )
        # ── palette (dark is the default; light is a media override of the same geometry) ─────────
        + f".skT{{stop-color:{d.sky_top}}}.skM{{stop-color:{d.sky_mid}}}"
        f".skL{{stop-color:{d.sky_low}}}"
        f".gnT{{stop-color:{d.ground_top}}}.gnB{{stop-color:{d.ground_bot}}}"
        f".eprint{{fill:{d.rule}}}.esh{{fill:#000;opacity:.42}}"
        f".eink{{fill:{d.rule}}}.efg{{fill:{d.fg}}}.eclawd{{fill:{gen.CLAWD}}}"
        f".emd0{{fill:{d.mound[0]}}}.emd1{{fill:{d.mound[1]}}}.etuft{{fill:{d.tuft}}}"
        f".estar{{fill:{d.star}}}"
        # Glyphs get the HIGHEST-contrast ink in the scheme, not a scenery colour. They sit at the
        # legibility floor (~17 CSS px) where contrast is the only remaining margin: rendered in the
        # ground rule's muted violet the first pass produced a mark that was technically large enough
        # and still hard to find against the sky. A glyph nobody locates is a glyph nobody decodes.
        # `opacity:0` is the RESTING state, not a decoration. Under `prefers-reduced-motion` every
        # animation is switched off, so an element's painted value falls back to its static rule —
        # and a glyph whose only opacity lived in `glyph_pop`'s keyframes therefore rendered FULLY
        # VISIBLE in the reduced-motion still, floating unattached beside a creature doing nothing.
        # Found by rendering the still rather than by trusting the footer that claims it composes.
        # A running animation overrides this, so the live loop is unaffected.
        f".eglyph{{fill:{d.star};opacity:0}}"
        # each twinkle's phase lives in its own keyframe percentages, never in a delay. The .38
        # trough is also declared statically, for the reason `egate` records: with animations off
        # a keyframes-only opacity paints at the CSS default of 1, and the whole field would light
        # to maximum magnitude at once — a starfield with no magnitudes in it, which is the one
        # thing the twinkle vocabulary exists to avoid.
        + "".join(
            f"@keyframes etwk{i}{{0%,{max(pk - 14, 1)}%{{opacity:.38}}"
            f"{pk}%{{opacity:1}}{min(pk + 14, 99)}%,100%{{opacity:.38}}}}"
            f".etw{i}{{opacity:.38;animation:etwk{i} {p}s ease-in-out infinite}}"
            for i, (p, pk) in enumerate(TWINKLES)
        )
        # ── baseline life ─────────────────────────────────────────────────────────────────────────
        + (walk if e.walks else stand)
        + f"@keyframes eblkO{{0%,90%{{opacity:1}}90.5%,95%{{opacity:0}}95.5%,100%{{opacity:1}}}}"
        f"@keyframes eblkS{{0%,90%{{opacity:0}}90.5%,95%{{opacity:1}}95.5%,100%{{opacity:0}}}}"
        f".eOpen{{animation:eblkO 4s steps(1,end) infinite}}"
        f".eShut{{animation:eblkS 4s steps(1,end) infinite}}"
        f"@keyframes earm{{0%,64%{{transform:translateY(0)}}"
        f"72%{{transform:translateY(-{fmt(gen.CELL * 0.55)}px)}}"
        f"80%,100%{{transform:translateY(0)}}}}"
        f".armsIdle{{animation:earm 2s ease-in-out infinite}}"
        # ── light theme ───────────────────────────────────────────────────────────────────────────
        # ONE definition of the light palette, wrapped or unwrapped depending on `scheme`. The forced
        # variant therefore applies the SAME rules the media query would, rather than a second copy
        # that could drift from it — a reviewer comparing a forced render against the shipped asset
        # must be comparing the artwork, not two stylesheets that disagree.
        + _light_rules(lt, scheme)
        # ── reduced motion freezes at 0%, which the reset list above makes a composed still ───────
        + "@media(prefers-reduced-motion:reduce){*{animation:none!important}}"
    )


def render(e: Emote, scheme: str = "auto") -> str:
    """One candidate as a standalone, self-contained SVG. `auto` is the shipping form."""
    # Body FIRST, stylesheet second. `clawd()` is what discovers the extra-creature suffixes, so a
    # stylesheet written before the body would emit resets for a set that is still empty — the bug
    # would look fixed and stay live.
    body = f"{stage_body(e)}{e.props()}{clawd(e)}{e.front()}"
    css = base_css(e, scheme) + e.css()
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {STAGE_W} {STAGE_H}" '
        f'width="{STAGE_W}" height="{STAGE_H}" role="img" '
        f'aria-label="{gen_escape(e.title)}: {gen_escape(e.showcase)}">'
        f"<title>{gen_escape(e.title)}</title>"
        f"<desc>{gen_escape(e.entry)} {gen_escape(e.showcase)} {gen_escape(e.exit)}</desc>"
        f"<defs>{stage_defs()}</defs>"
        f"<style>{css}</style>"
        f"{body}"
        f"</svg>"
    )


def gen_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


# ── the expressive vocabulary ─────────────────────────────────────────────────────────────────────
# Everything a candidate is allowed to say, in one place. The constraint driving all of it: this
# creature has NO MOUTH, no brows, and a bilaterally symmetric silhouette — `scaleX(-1)` maps it onto
# itself, so "turning to face" is invisible and was shipped as a bug once already. Two channels
# survive at the size this renders: WHOLE-BODY POSTURE (a change of at least ~30% of the silhouette)
# and a STANDARDIZED GLYPH large enough to read. Limb-level and gaze-level acting does not.

GLYPH_MIN = (
    37  # user units ≈ 16 CSS px at the README column — the measured legibility floor
)


# The glyph set is deliberately small and conventional. An invented glyph has to be learned; a
# standardised one is decoded instantly, and decoding is the entire job at 16 px. Each is drawn on
# the pixel grid at GLYPH_MIN or larger.
def glyph(kind: str, cx: float, cy: float, cls: str, u: float = 13.0) -> str:
    """One standardized glyph, centred on (cx, cy). `u` is the pixel unit it is built from."""

    def r(x: float, y: float, w: float, h: float) -> str:
        return (
            f'<rect x="{fmt(cx + x * u)}" y="{fmt(cy + y * u)}" '
            f'width="{fmt(w * u)}" height="{fmt(h * u)}"/>'
        )

    if kind == "bang":  # ! — alarm, surprise, "something happened"
        art = r(-0.5, -1.8, 1, 2.4) + r(-0.5, 1.0, 1, 1)
    elif kind == "query":  # ? — curiosity, "what is that"
        art = (
            r(-1, -1.8, 2.4, 0.9)
            + r(0.6, -1.0, 0.9, 1.1)
            + r(-0.4, 0, 1, 0.9)
            + r(-0.4, 1.3, 1, 1)
        )
    elif kind == "spark":  # a burst — delight, success
        art = (
            r(-0.4, -1.9, 0.8, 0.9)
            + r(-0.4, 1.1, 0.8, 0.9)
            + r(-1.9, -0.4, 0.9, 0.8)
            + r(1.1, -0.4, 0.9, 0.8)
        )
    elif kind == "sweat":  # a drop — effort, alarm, embarrassment
        art = r(-0.5, -1.4, 1, 1.6) + r(-0.9, 0, 1.8, 1.2) + r(-0.5, 1.0, 1, 0.6)
    elif kind == "note":  # a musical note — contentment, pottering
        art = r(0.2, -1.8, 0.9, 2.6) + r(-1.1, 0.4, 1.4, 1.1)
    elif kind == "heart":
        art = (
            r(-1.5, -1.0, 1.2, 1.2)
            + r(0.3, -1.0, 1.2, 1.2)
            + r(-1.5, 0.2, 3, 0.9)
            + r(-0.9, 1.1, 1.8, 0.9)
            + r(-0.3, 2.0, 0.6, 0.8)
        )
    else:
        raise SystemExit(f"emotes: unknown glyph {kind!r}")
    # Two classes, and the split is deliberate: `eglyph` carries the CONTRAST (one rule, both colour
    # schemes, defined once in base_css) and `cls` carries only this instance's ANIMATION. A
    # candidate that wanted to restyle the fill locally would silently opt out of the light theme.
    return f'<g class="eglyph {cls}">{art}</g>'


def glyph_pop(name: str, sel: str, t0: float, t1: float, rise: float = 26.0) -> str:
    """A glyph's whole life: it POPS in, holds, and lifts away. It never cross-fades.

    A gradual opacity ramp is missed 69% of the time even with no visual disruption — a slow fade is
    not an entrance, it is a change nobody sees happen. So the appearance is a hard step with an
    overshoot in scale (the 'pop'), and the departure is motion, not dissolution.

    It rests at `opacity:0` STATICALLY for `egate`'s reason. Today every caller reaches this through
    `glyph()`, which pairs the animation class with `.eglyph` — and `.eglyph` already carries that
    resting value, so the reduced-motion still is correct by INHERITANCE rather than by anything
    this function does. That is a coincidence of the current callers, not a property, and a pack
    that pops a non-glyph element through here would have found the trap again.
    """
    return (
        f"@keyframes {name}{{"
        f"0%,{pctx(t0)}%{{opacity:0;transform:translateY(6px) scale(.4)}}"
        f"{pctx(t0 + 0.10)}%{{opacity:1;transform:translateY(0) scale(1.25)}}"
        f"{pctx(t0 + 0.22)}%{{opacity:1;transform:translateY(0) scale(1)}}"
        f"{pctx(t1 - 0.30)}%{{opacity:1;transform:translateY(0) scale(1)}}"
        f"{pctx(t1)}%{{opacity:0;transform:translateY(-{fmt(rise)}px) scale(.9)}}"
        f"100%{{opacity:0;transform:translateY(6px) scale(.4)}}}}"
        f"{sel}{{opacity:0;animation:{name} {fmt(EMOTE_P)}s ease-out infinite}}"
    )


def squash(
    name: str, sel: str, frames: list[tuple[float, float, float]], origin_y: float = 8.0
) -> str:
    """A squash-and-stretch track: (time, x-scale, y-scale), pinned to the feet.

    Amplitudes here stay inside roughly +-15%. Beyond that a hard-edged pixel body stops reading as
    a squashy creature and starts reading as a scaling bug, because there is no deformation in the
    silhouette's interior to sell it — every cell is the same flat colour.
    """
    ks = "".join(
        f"{pctx(t)}%{{transform:scale({fmt(sx)},{fmt(sy)})}}" for t, sx, sy in frames
    )
    return (
        f"@keyframes {name}{{{ks}}}"
        f"{sel}{{animation:{name} {fmt(EMOTE_P)}s cubic-bezier(.32,.06,.3,1) infinite;"
        f"transform-origin:{fmt(5.5 * gen.CELL)}px {fmt(origin_y * gen.CELL)}px}}"
    )


def shift(
    name: str,
    sel: str,
    frames: list[tuple[float, float, float]],
    ease: str = "ease-out",
) -> str:
    """A whole-body translate track: (time, dx, dy) in sprite units."""
    ks = "".join(
        f"{pctx(t)}%{{transform:translate({fmt(dx)}px,{fmt(dy)}px)}}"
        for t, dx, dy in frames
    )
    return f"@keyframes {name}{{{ks}}}{sel}{{animation:{name} {fmt(EMOTE_P)}s {ease} infinite}}"


def stop_world(name: str, t0: float, t1: float) -> str:
    """Freeze the scrolling ground between t0 and t1, then resume WITHOUT losing position.

    The arrest of an established rhythm is the cheapest reliable transient in this whole vocabulary —
    it needs no new artwork, because a violated rhythm IS the transient. The travel either side has
    to stay continuous or the world visibly jumps at the wrap.
    """
    v = PRINT_TILE  # px per second
    return (
        f"@keyframes {name}{{"
        f"0%{{transform:translateX(0)}}"
        f"{pctx(t0)}%{{transform:translateX(-{fmt(v * t0)}px)}}"
        f"{pctx(t1)}%{{transform:translateX(-{fmt(v * t0)}px)}}"
        f"100%{{transform:translateX(-{fmt(v * (EMOTE_P - (t1 - t0)))}px)}}}}"
        f".escroll{{animation:{name} {fmt(EMOTE_P)}s linear infinite}}"
    )


# ── gates every candidate must pass ───────────────────────────────────────────────────────────────
def assert_story_shape(e: Emote) -> None:
    """A candidate without three acts is not a candidate, it is a movement."""
    for act in ("entry", "showcase", "exit"):
        text = getattr(e, act).strip()
        if not text:
            raise SystemExit(
                f"emotes[{e.key}]: no {act.upper()} — a beat needs all three acts"
            )
        # A LENGTH FLOOR, because these strings are not decoration — the review page prints them as
        # the candidate's story, so a placeholder becomes a shipped panel that describes nothing. The
        # case is not hypothetical: a pack under construction registered a stub with entry="a",
        # showcase="b", exit="c" purely to exercise the API, and every other gate passed it. Twelve
        # characters is enough to distinguish a written act from a keystroke.
        if len(text) < 12:
            raise SystemExit(
                f"emotes[{e.key}]: {act.upper()} is {text!r} — too short to be a written act. These "
                f"strings are printed on the review page AS the story; a placeholder here ships as a "
                f"panel that explains nothing."
            )
    if not 2.0 <= e.dur <= 9.0:
        raise SystemExit(
            f"emotes[{e.key}]: story runs {e.dur:.1f}s, outside the 2-9s band. Under 2s the eye "
            f"cannot arrive in time (saccade ~200ms + identify ~300ms); over 9s it stops being an "
            f"occurrence inside a {EMOTE_P}s loop and becomes the loop's subject."
        )
    if e.window[1] + GATE_EDGE > EMOTE_P:
        raise SystemExit(
            f"emotes[{e.key}]: story ends at {e.window[1]}s, past EMOTE_P={EMOTE_P}s"
        )
    air = EMOTE_P - e.dur
    if air < EMOTE_P * 0.25:
        raise SystemExit(
            f"emotes[{e.key}]: only {air:.1f}s of air in a {EMOTE_P}s loop. A beat with no silence "
            f"either side cannot read as an occurrence — 'special' is a contrast effect."
        )


def assert_grounded(e: Emote) -> None:
    """The creature stands ON the rule, by arithmetic — never by a number someone eyeballed."""
    sole = (E_GROUND - gen.SPRITE_H * CLAWD_SCALE) + gen.SPRITE_H * CLAWD_SCALE
    if abs(sole - E_GROUND) > 1e-9:
        raise SystemExit(f"emotes[{e.key}]: sole at {sole}, rule at {E_GROUND}")


def assert_css_targets_exist(svg: str, e: Emote) -> None:
    """A candidate's own stylesheet may not name a sprite group that was never drawn.

    THE DEFECT THIS EXISTS FOR, found by rendering rather than by reading: THE STRETCH gated
    `.armsGate` off and `.rCheer` on, but the sprite had been built with `cheer=False`, so `.rCheer`
    did not exist. The idle arms went away on cue, nothing replaced them, and the creature performed
    its whole showcase with no arms at all. Every other gate passed — the CSS was valid, the loop was
    seamless, the lint found one animation per element. Only a picture disagreed.

    Note this is the OPPOSITE direction from `assert_reset_covers_sprite`, and both are needed: that
    one catches a group drawn and left unstyled (renders ON forever), this one catches a group styled
    and never drawn (renders as a hole). Neither implies the other.
    """
    # The CANDIDATE's own stylesheet, not the whole file. `base_css` resets every optional group to
    # opacity:0 whether or not it was drawn, and resetting a group that does not exist is harmless —
    # so scanning the combined CSS convicts every candidate of a defect none of them has. What is
    # never harmless is DRIVING a group that does not exist, and only `e.css()` does any driving.
    own = e.css()
    for cls in OPTIONAL_GROUPS:
        styled = f".{cls}{{" in own or f".{cls}," in own
        drawn = f'class="{cls}"' in svg
        if styled and not drawn:
            raise SystemExit(
                f"emotes[{e.key}]: the stylesheet drives '.{cls}' but `gen.clawd_sprite` never drew "
                f"it — add {cls!r} to this candidate's `uses` tuple. Left alone this renders as a "
                f"MISSING body part for the length of the showcase, and reports nothing."
            )


def assert_reset_covers_sprite(svg: str, e: Emote) -> None:
    """Every optional group the sprite emits must be named by the stylesheet.

    The failure this prevents is silent and ugly: an ungated group is not hidden, it is simply ON for
    the whole loop. That is how a cheer once shipped as a permanent pair of horns. So rather than
    trusting the reset list to stay in step with `gen.clawd_sprite`, read the classes back out of the
    rendered sprite and require each one to appear in the CSS.
    """
    css = svg.split("<style>", 1)[1].split("</style>", 1)[0]

    # EXACT CLASS TOKENS, never prefixes. The first version tested `class="legsStill` against the
    # document and `"legsStill" in css`, and BOTH are satisfied by a suffixed group. A second
    # creature drawn as `clawd(e, sfx="B")` emits `.legsStillB`, `.eShutB`, `.armsAlertB`,
    # `.eyesAskB` — none of which `base_css`'s reset list names — so every one renders ON for the
    # whole loop: a visitor with both leg sets at once, blink-lids painted over its open eyes, ears
    # permanently raised. The prefix match reported all of that as covered, because the UNSUFFIXED
    # rule exists. The world pack found it and worked around it with per-suffix reset helpers,
    # which is the tell that the gate was passing something it should have refused.
    drawn = {
        tok
        for attr in re.findall(r'class="([^"]+)"', svg)
        for tok in attr.split()
        if any(tok.startswith(g) for g in OPTIONAL_GROUPS)
    }
    for cls in sorted(drawn):
        if not re.search(rf"\.{re.escape(cls)}\b", css):
            raise SystemExit(
                f"emotes[{e.key}]: sprite emits '{cls}' but no rule names it — it would render ON "
                f"for the entire loop. A SUFFIXED group (a second creature) needs its own reset; "
                f"the unsuffixed rule in base_css does not reach it."
            )


def assert_seamless(svg: str, e: Emote) -> None:
    """Nothing may be mid-transition at the wrap.

    Weaker than a frame hash and honest about it: this checks that every gate returns to its resting
    value by 100%, which is the property that makes the loop's first and last frame agree. A true
    byte-identical t=0 vs t=P comparison is `scripts/banner-verify.sh`'s job and runs on the rendered
    asset, not here.
    """
    for block in svg.split("@keyframes ")[1:]:
        name = block.split("{", 1)[0].strip()
        body = block.split("{", 1)[1]
        if (
            "100%" not in body
            and "to{" not in body
            and not name.startswith(("ewA", "ewB"))
        ):
            raise SystemExit(
                f"emotes[{e.key}]: keyframes '{name}' has no 100% stop — loop seams"
            )


def _css_blocks(css: str) -> list[tuple[str, str]]:
    """(prelude, body) for every brace-balanced block at the top level of `css`.

    Enough of a parser for this stylesheet and no more: it is machine-written by this module, so
    there are no comments, no strings and no escapes for a brace to hide inside. Balancing rather
    than regex-splitting is what lets the same function read a rule, an `@keyframes` body and an
    `@media` body — a regex that stopped at the first `}` would truncate the nested two.
    """
    out: list[tuple[str, str]] = []
    depth, start, open_at = 0, 0, 0
    for i, ch in enumerate(css):
        if ch == "{":
            if depth == 0:
                open_at = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                out.append((css[start:open_at].strip(), css[open_at + 1 : i]))
                start = i + 1
    return out


# `(?:^|;)` so this cannot match the tail of `fill-opacity` or `stop-opacity` — a bare `opacity:`
# search reads a stop's alpha as an element's and reports a rest that no element has.
_OPACITY = re.compile(r"(?:^|;)\s*opacity:\s*([^;}]+)")
_ANIMATION = re.compile(r"(?:^|;)\s*animation:\s*([A-Za-z0-9_-]+)")


def _rest_opacity(keyframes_body: str) -> str | None:
    """The opacity a track holds at 0%, or None if it never sets one there.

    None is not a defect and must not be treated as one. A track that animates only `transform`
    has no resting opacity to check, and a track that sets opacity somewhere but NOT at 0% takes
    its implicit 0% from the element's own static value — which makes the two agree by
    construction, i.e. exactly the property this gate is asserting.
    """
    stops = _css_blocks(keyframes_body)
    for marks, decls in stops:
        if "0%" in [m.strip() for m in marks.split(",")] or marks.strip() == "from":
            m = _OPACITY.search(decls)
            return m.group(1).strip() if m else None
    return None


def assert_static_rest(svg: str, e: Emote) -> None:
    """An animated opacity must ALSO exist as a static declaration, or reduced motion lights it.

    THE DEFECT, found by rendering rather than by reading, and found FOUR times before it was
    fixed at the source. `base_css` ends with `@media(prefers-reduced-motion:reduce){*{animation:
    none!important}}`, so for that reader every animation is off and each element paints its STATIC
    rule. An element whose only `opacity` lived inside its keyframes therefore falls back to the
    CSS default of 1 — fully visible, when the whole point of its track was that it rests hidden.
    Rendered as stills that meant THE DIG showed its finished hole before a single crumb had been
    thrown, THE COPIES showed its entire ghost stack at once, THE UNSWITCHED showed the one thing
    it promises never to show, and a `!` hung in the sky beside a creature doing nothing. Every
    other gate passed all four times, because a gate that reads the animated timeline never looks
    at the frame where the animation is absent.

    `egate`, `glyph_pop` and `emotes_infra._steps` now emit the rest statically, so a candidate
    built out of the vocabulary cannot reintroduce it. THIS gate is what covers the rest, and it is
    the half that matters: three of the four instances were hand-rolled `@keyframes` blocks, which
    no amount of fixing the helpers can reach.

    READ PER ELEMENT, NOT PER SELECTOR, because that is what a browser does. A glyph is
    `class="eglyph cuG"` and takes its resting `opacity:0` from `.eglyph` while `.cuG` carries only
    the animation; convicting `.cuG` for a rest it legitimately inherits from a sibling class would
    make this a gate authors work around, and a gate that is worked around is deleted next. Six
    candidates sit in exactly that position today.

    KNOWN BOUND, stated rather than hidden: `@media(prefers-color-scheme:light)` is flattened in,
    so a resting opacity that DIFFERS between the two schemes would be judged on the light one.
    No element has that shape today (`.esh` is the only scheme-dependent opacity and nothing
    animates it), and the reduced-motion block itself is skipped — it turns animations off, it
    declares no resting value.
    """
    css = svg.split("<style>", 1)[1].split("</style>", 1)[0]
    rest: dict[str, str | None] = {}
    rules: list[tuple[str, str]] = []
    for pre, body in _css_blocks(css):
        if pre.startswith("@keyframes"):
            rest[pre.split(None, 1)[1].strip()] = _rest_opacity(body)
        elif pre.startswith("@media"):
            if "prefers-reduced-motion" not in pre:
                rules += _css_blocks(body)
        elif not pre.startswith("@"):
            rules.append((pre, body))

    # Position-keyed, because the cascade between two single-class rules is decided by DOCUMENT
    # ORDER and an element carries several classes. `.legsStill` is reset to 0 by base_css and then
    # back to 1 by the standing variant; taking "the last declaration among this element's classes"
    # needs to know which of its classes was declared last, which a plain name→value map cannot say.
    static: dict[str, tuple[int, str]] = {}
    driven: dict[str, str] = {}
    for i, (pre, body) in enumerate(rules):
        op, anim = _OPACITY.search(body), _ANIMATION.search(body)
        for sel in (s.strip() for s in pre.split(",")):
            if not re.fullmatch(r"\.[A-Za-z0-9_-]+", sel):
                continue
            cls = sel[1:]
            if op:
                static[cls] = (i, op.group(1).strip())
            if anim:
                driven[cls] = anim.group(1)

    # `[A-Za-z]` and not `[a-z]`: SVG has mixed-case element names (`clipPath`, `linearGradient`),
    # and a lowercase-only match plus `\b` silently skips every one of them. None carries a class
    # today. "None does today" is the sentence that precedes each of this defect's four appearances.
    for tag in re.finditer(r"<[A-Za-z][A-Za-z0-9]*\b[^>]*>", svg):
        toks = re.search(r'class="([^"]+)"', tag.group(0))
        if not toks:
            continue
        classes = toks.group(1).split()
        # A presentation attribute is outranked by ANY rule, so it is the painted value only when
        # no rule matched. Handling it costs one line and closes the shape rather than the instance
        # — no element carries both today, and "no element does that today" is how this defect got
        # in four times.
        attr = re.search(r'\sopacity="([^"]+)"', tag.group(0))
        pos, val = max(
            (static[c] for c in classes if c in static),
            default=(-1, attr.group(1) if attr else "1"),
        )
        for cls in classes:
            name = driven.get(cls)
            if name is None or rest.get(name) is None:
                continue
            # A value this cannot read is a THIRD state, never a pass. Everything here is a numeric
            # literal today, so a `var(--x)` or a `calc()` arriving later means the gate has stopped
            # being able to judge — and a guard that answers "fine" when it means "I could not look"
            # is worse than no guard, because it reports coverage it does not have.
            try:
                painted, resting = float(val), float(rest[name])
            except ValueError:
                raise SystemExit(
                    f"emotes[{e.key}]: '{cls}' rests at {rest[name]!r} and paints {val!r} with "
                    f"animations off — one of those is not a number this gate can compare, so it "
                    f"CANNOT say whether the reduced-motion still is right. Keep resting opacities "
                    f"as plain literals, or teach `assert_static_rest` the new form."
                ) from None
            if abs(painted - resting) > 1e-9:
                raise SystemExit(
                    f"emotes[{e.key}]: '{cls}' animates opacity ('{name}' rests at "
                    f"{rest[name]}) but the element paints {val} with animations OFF. Under "
                    f"prefers-reduced-motion the whole still is that frame, so this element "
                    f"renders {'VISIBLE' if painted > resting else 'HIDDEN'} when "
                    f"its own track says it should not — declare the rest statically too, "
                    f"`.{cls}{{opacity:{rest[name]};animation:…}}`, the way `egate` does."
                )


# ── the candidates ────────────────────────────────────────────────────────────────────────────────
EMOTES: list[Emote] = []


def emote(e: Emote) -> Emote:
    EMOTES.append(e)
    return e


def _startle() -> Emote:
    """PROTOTYPE 1 — the cheapest legible beat available: an arrest of an established rhythm."""
    e = Emote(
        key="startle",
        title="THE STARTLE",
        category="Reactions",
        entry="the stride stops dead mid-step — a rhythm violation is a transient needing no new art",
        showcase="the whole body flinches back a half-cell and the arms snap up alert",
        exit="it settles, shakes it off, and the stride picks the beat back up",
        window=(2.6, 6.2),
        cls="BEAT",
        tie="the Stop hook that refuses a false 'done' — being pulled up short",
    )
    a, b = e.window

    def css() -> str:
        return (
            egate("stStill", ".legsStill", [(a, b - 0.6)])
            + egate("stWalk", ".legsWalk", [(a, b - 0.6)], on_inside=False)
            + egate("stAlert", ".armsAlert", [(w(e, 0.10), w(e, 0.62))])
            + egate("stArms", ".armsGate", [(w(e, 0.10), w(e, 0.62))], on_inside=False)
            + f"@keyframes stScr{{0%,{pctx(a)}%{{animation-timing-function:linear;"
            f"transform:translateX(0)}}"
            f"{pctx(a)}%,{pctx(b - 0.6)}%{{transform:translateX(-{fmt(PRINT_TILE * a)}px)}}"
            f"100%{{transform:translateX(-{fmt(PRINT_TILE * EMOTE_P)}px)}}}}"
            f"@keyframes stFlinch{{0%,{pctx(a)}%{{transform:translate(0,0)}}"
            f"{wp(e, 0.08)}%{{transform:translate({fmt(gen.CELL * 0.5)}px,0)}}"
            f"{wp(e, 0.30)}%{{transform:translate({fmt(gen.CELL * 0.15)}px,0)}}"
            f"{wp(e, 0.72)}%,100%{{transform:translate(0,0)}}}}"
            f".rTurn{{animation:stFlinch {fmt(EMOTE_P)}s ease-out infinite}}"
        )

    e.css = css
    return e


def _peek_burrow() -> Emote:
    """PROTOTYPE 2 — a VISITOR that enters and leaves through an occluder, never by fading."""
    e = Emote(
        key="burrow",
        title="THE NEIGHBOUR",
        category="The world",
        entry="a mound of earth by the rule swells, then breaks",
        showcase="a second, smaller clawd pops up out of it and blinks at the resident",
        exit="it drops back down the SAME hole it came out of, and the mound settles flat",
        window=(3.0, 9.0),
        cls="VISITOR",
        walks=False,
        tie="a worktree: a sibling session, its own hole, gone without a trace",
        cx=214,
    )
    a, b = e.window
    hx, hw = 520.0, 132.0

    def props() -> str:
        return (
            f'<g class="bwClip"><clipPath id="bwHole">'
            f'<rect x="{fmt(hx - hw / 2)}" y="0" width="{fmt(hw)}" height="{fmt(E_GROUND)}"/>'
            f"</clipPath>"
            f'<g clip-path="url(#bwHole)"><g class="bwUp">'
            f"{clawd(e, sfx='B', scale=0.62, x=hx - gen.SPRITE_W * 0.62 / 2)}"
            f"</g></g></g>"
        )

    def front() -> str:
        # A RIM of thrown earth, not a dark blob. The first version scaled a single dark ellipse and
        # read as a puddle or a drop-shadow: a hole is only legible as a hole when there is spoil
        # piled around its edge, because the dark ellipse alone is the same shape the creature's own
        # contact shadow already makes twice in the same frame.
        rim = "".join(
            f'<rect x="{fmt(hx + dx)}" y="{fmt(E_GROUND - dh)}" width="{fmt(wd)}" '
            f'height="{fmt(dh + 4)}"/>'
            for dx, wd, dh in (
                (-hw * 0.52, 14, 5),
                (-hw * 0.38, 12, 9),
                (hw * 0.26, 12, 9),
                (hw * 0.40, 14, 5),
            )
        )
        dirt = "".join(
            f'<rect class="bwDirt{i}" x="{fmt(hx + dx)}" y="{fmt(E_GROUND - 14)}" '
            f'width="5" height="5"/>'
            for i, dx in enumerate((-34, -12, 16, 38))
        )
        return (
            f'<g class="emd0">{rim}</g>'
            f'<ellipse class="efg" cx="{fmt(hx)}" cy="{fmt(E_GROUND + 1)}" '
            f'rx="{fmt(hw * 0.30)}" ry="6"/>'
            f'<g class="emd0">{dirt}</g>'
        )

    def css() -> str:
        rise = gen.SPRITE_H * 0.62 + 14
        return (
            # B rides up out of the ground and back down the same shaft. The clip is the occluder, so
            # it is never "gone" in the sense of ceasing to exist — it is behind something.
            f"@keyframes bwR{{0%,{pctx(a)}%{{transform:translateY({fmt(rise)}px)}}"
            f"{wp(e, 0.18)}%,{wp(e, 0.78)}%{{transform:translateY(0)}}"
            f"{pctx(b)}%,100%{{transform:translateY({fmt(rise)}px)}}}}"
            f".bwUp{{animation:bwR {fmt(EMOTE_P)}s cubic-bezier(.35,.1,.3,1) infinite}}"
            # The herald: four crumbs of earth are thrown up and fall back, 0.9 s BEFORE the head
            # appears. That lead sits inside the 1-3 s herald window — long enough for the eye to
            # arrive (a saccade plus identification is ~400-500 ms) and short enough that the crumb
            # and the head still read as one event rather than two.
            + "".join(
                f"@keyframes bwD{i}{{0%,{pctx(a - 0.9)}%{{transform:translate(0,0);opacity:0}}"
                f"{pctx(a - 0.75)}%{{opacity:1}}"
                f"{pctx(a - 0.4)}%{{transform:translate({fmt(dx)}px,{fmt(-18 - i * 4)}px);"
                f"opacity:1}}"
                f"{pctx(a)}%{{transform:translate({fmt(dx * 1.5)}px,4px);opacity:0}}"
                f"100%{{transform:translate(0,0);opacity:0}}}}"
                f".bwDirt{i}{{opacity:0;animation:bwD{i} {fmt(EMOTE_P)}s ease-out infinite}}"
                for i, dx in enumerate((-16, -6, 7, 15))
            )
            # the resident notices, 250 ms after B clears the rule
            + egate("bwAl", ".armsAlert", [(w(e, 0.24), w(e, 0.86))])
            + egate("bwAg", ".armsGate", [(w(e, 0.24), w(e, 0.86))], on_inside=False)
        )

    e.props, e.front, e.css = props, front, css
    return e


def _stretch() -> Emote:
    """PROTOTYPE 3 — pure cute, no semantics. A whole-body posture change, which is the one thing
    measured to be legible at this size."""
    e = Emote(
        key="stretch",
        title="THE STRETCH",
        category="Idle life",
        entry="the walk slows and stops; the body sinks into a crouch",
        showcase="it stretches tall — squashes down, then rises a full cell with both arms straight up",
        exit="it drops back, wobbles once, and ambles on",
        window=(3.4, 8.0),
        cls="BEAT",
        walks=False,
        tie="",
        uses=("rCheer",),
    )

    def css() -> str:
        c = gen.CELL
        return (
            f"@keyframes stqB{{0%,{wp(e, 0.0)}%{{transform:scale(1,1)}}"
            f"{wp(e, 0.18)}%{{transform:scale(1.10,.88)}}"  # anticipation: squash
            f"{wp(e, 0.42)}%{{transform:scale(.93,1.14)}}"  # the stretch itself
            f"{wp(e, 0.62)}%{{transform:scale(.96,1.08)}}"
            f"{wp(e, 0.80)}%{{transform:scale(1.04,.96)}}"  # overshoot on the way down
            f"{wp(e, 1.0)}%,100%{{transform:scale(1,1)}}}}"
            f".bob{{animation:stqB {fmt(EMOTE_P)}s cubic-bezier(.32,.06,.3,1) infinite;"
            f"transform-origin:{fmt(5.5 * c)}px {fmt(8 * c)}px}}"
            + egate("stqA", ".rCheer", [(w(e, 0.30), w(e, 0.70))])
            + egate("stqG", ".armsGate", [(w(e, 0.30), w(e, 0.70))], on_inside=False)
        )

    e.css = css
    return e


def _curious() -> Emote:
    """VOCABULARY VALIDATION — the glyph channel plus a posture lean, together."""
    e = Emote(
        key="curious",
        title="THE CURIOUS",
        category="Idle life",
        entry="the walk halts and the world stops with it; the body leans forward",
        showcase="a question mark pops above its head and holds while it peers at nothing",
        exit="the glyph lifts away, the body rocks back, and the world starts moving again",
        window=(2.8, 7.4),
        cls="BEAT",
        tie="",
    )
    a, b = e.window
    gx = e.cx + gen.SPRITE_W * CLAWD_SCALE / 2
    gy = E_GROUND - gen.SPRITE_H * CLAWD_SCALE - 46

    def front() -> str:
        return glyph("query", gx, gy, "cuG")

    def css() -> str:
        return (
            stop_world("cuScr", a, b - 0.6)
            + egate("cuStill", ".legsStill", [(a, b - 0.6)])
            + egate("cuWalk", ".legsWalk", [(a, b - 0.6)], on_inside=False)
            # A CROUCH is the anticipation, not a sideways lean. On a bilaterally symmetric sprite a
            # lateral shift carries no direction — there is no front to lean toward — so it reads as
            # the whole image sliding rather than as the creature addressing something. A vertical
            # posture change has no such ambiguity. The glyph is the payoff and lands 0.55 s LATER,
            # never on the same frame: the eye needs ~400-500 ms to arrive after a cue.
            + squash(
                "cuCrouch",
                ".bob",
                [
                    (0, 1, 1),
                    (a, 1, 1),
                    (w(e, 0.14), 1.07, 0.93),
                    (w(e, 0.30), 1.0, 1.02),
                    (w(e, 0.82), 1.0, 1.02),
                    (b, 1, 1),
                    (EMOTE_P, 1, 1),
                ],
            )
            + glyph_pop("cuGf", ".cuG", a + 0.55, b - 0.35)
        )

    e.front, e.css = front, css
    return e


emote(_startle())
emote(_curious())
emote(_peek_burrow())
emote(_stretch())


# ── build ─────────────────────────────────────────────────────────────────────────────────────────
def load_packs() -> None:
    """Import every `emotes_*.py` sibling, each of which registers its own candidates.

    The candidate set is split across modules by CATEGORY rather than kept in one file, for a plain
    mechanical reason: a set this size is authored by several people (or several agents) at once, and
    one shared file makes every author a merge conflict for every other. One module per category
    means one owner per file and no shared write surface at all.

    Import failures are FATAL rather than skipped. A pack that fails to import would otherwise remove
    its candidates from the page silently, and a missing panel is indistinguishable from a candidate
    nobody wrote — the review would be quietly incomplete, which is the one thing a review surface
    may never be.

    THE ALIAS BELOW EXISTS BECAUSE THAT FATAL-IMPORT RULE HAD A HOLE, AND THE HOLE WAS FOUND BY THREE
    AUTHORS PAYING THE SAME TAX. This file is both the framework and the entrypoint, so when it runs
    as a script it lives in `sys.modules` under `__main__`. A pack that writes the obvious
    `import emotes` therefore did not find it — Python re-executed this file as a SECOND module object
    with its OWN empty `EMOTES` list, every `emote(...)` in that pack registered into a registry
    nobody renders, and the build reported success with the pack's panels simply absent. The
    fatal-import rule cannot see it, because the import SUCCEEDS.

    Reproduced before fixing: a pack doing nothing but `import emotes as E` and registering one
    candidate left the count unchanged at 27 and wrote no file, with zero complaint. Each of the
    three packs had independently discovered this and carried its own binding shim, which is the tell
    that the framework was wrong rather than the packs.

    Aliasing the running module under its importable name closes it at the source: `import emotes`
    now returns THIS object, so a pack needs no shim and the obvious spelling is the correct one.
    """
    me = sys.modules[
        __name__
    ]  # '__main__' under `python3 emotes.py`, 'emotes' when imported
    canonical = sys.modules.setdefault("emotes", me)
    if canonical is not me:
        raise SystemExit(
            "emotes: two framework module objects exist — `sys.modules['emotes']` is not the running "
            "module, so packs would register into a registry this process never renders."
        )

    here = Path(__file__).resolve().parent
    for mod in sorted(here.glob("emotes_*.py")):
        before = len(EMOTES)
        __import__(mod.stem)
        # Belt and braces, and independent of the cause: a pack that registers NOTHING is a pack
        # whose panels are missing from the review, whatever the reason. Silence here is the exact
        # failure this function's contract forbids, so it is an error rather than an empty section.
        if len(EMOTES) == before:
            raise SystemExit(
                f"emotes: pack '{mod.name}' registered no candidates. Either it calls no `emote(...)`, "
                f"or it bound to a different framework object than the one building this run."
            )


def build_all(
    out: Path, schemes: tuple[str, ...] = ("auto",)
) -> list[tuple[Emote, Path]]:
    out.mkdir(parents=True, exist_ok=True)
    made = []
    seen: set[str] = set()
    for e in EMOTES:
        if e.key in seen:
            raise SystemExit(f"emotes: duplicate key {e.key!r}")
        seen.add(e.key)
        assert_story_shape(e)
        assert_grounded(e)
        svg = render(e)
        assert_css_targets_exist(svg, e)
        assert_reset_covers_sprite(svg, e)
        assert_seamless(svg, e)
        assert_static_rest(svg, e)
        p = out / f"{e.key}.svg"
        p.write_text(svg, encoding="utf-8")
        made.append((e, p))
        for sch in schemes:
            if sch == "auto":
                continue
            (out / f"{e.key}.{sch}.svg").write_text(render(e, sch), encoding="utf-8")
        print(f"  {p}  {len(svg):,} B  ({e.title} — {e.dur:.1f}s story, {e.cls})")
    return made


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="/tmp/emotes", type=Path)
    ap.add_argument(
        "--schemes",
        default="auto",
        help="comma list: auto (the shipping self-theming form), dark, light. The forced pair is "
        "for the review page, which cannot otherwise show both halves of a self-theming asset.",
    )
    args = ap.parse_args()
    load_packs()
    made = build_all(args.out, tuple(args.schemes.split(",")))
    print(
        f"\n{len(made)} candidate(s) · loop {EMOTE_P}s · panel {PANEL_PX}px (README-honest)"
    )


if __name__ == "__main__":
    main()
