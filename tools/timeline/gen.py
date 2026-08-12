#!/usr/bin/env python3
"""gen.py — the README convergence timeline, emitted as two GitHub-safe animated SVGs.

    python3 tools/timeline/gen.py           # writes assets/diagrams/convergence-timeline-{dark,light}.svg
    python3 tools/timeline/gen.py --check   # exit 1 if either file on disk differs from a fresh render
    python3 tools/timeline/gen.py --alt     # print the README alt text

WHY THIS IS HAND-BUILT AND NOT MERMAID. `beautiful-mermaid` 1.1.3 renders flowchart / stateDiagram /
xychart only. There is no timeline primitive, no control over node geometry, no gradients, no motion —
so a chronology can only come out as a chain of boxes, which is what the two landed iterations were
(`6c4c86d7`, `7691cd44`) and why both were rejected on design. The mermaid source stays as the
interactive fallback; this is the shipped picture.

────────────────────────────────────────────────────────────────────────────────────────────────
THE DESIGN ARGUMENT (v3, 2026-08-12). v1 and v2 are preserved at the foot of this docstring,
because each was rejected for a *different* reason and the pair of reasons is what shapes v3.

  0. THE BRIEF, AS THE OPERATOR STATED IT. v2's verdict: *"just as unreadable with the large varying
     texts and LESS visualization and beautiful complexion."* Three separable defects, and v3 is
     organised as their three fixes:
       * TYPE — v2 carried EIGHT sizes between 16 and 26 px. At GitHub's 838 px column that is a
         0.599 scale, so all eight land inside 9.6–15.6 px: eight sizes, no hierarchy, and the bold
         26 px row names left as the only thing with weight. v3 has THREE sizes, 36 / 24 / 18, which
         render 21.6 / 14.4 / 10.8 — separated by 1.5× at each step, so hierarchy survives the
         downscale. Everything is mono except the two capability names, which is the hero banner's
         own type system (a mono wordmark, one sans-free line of tracked caps).
       * VISUALIZATION — v2 drew four dots, two 3.5 px hairlines and two pills on a 1400×524 plate.
         Measured as ink, it was a paragraph of prose with rules under it. v3 adds a real second
         data layer (leg 2) and gives the leads MASS (leg 3).
       * COMPLEXION — v2's plate was a near-flat #111823→#0a0e15 wash. The hero (`v6c-dusk-line.svg`,
         the standard this asset is measured against) gets its look from prior-art.md §B1/§B2/§B8:
         depth built from COLOUR BANDS before any shape is drawn, atmospheric perspective per plane,
         and one warm source against a cool surround. v3 is built that way — see leg 4.

  1. WHAT THE CHART CLAIMS IS UNCHANGED FROM v2, AND SO IS ITS SKELETON. Two capabilities were
     running here before the Claude Code release that shipped them; one linear time axis; green is
     left of blue on both tracks and that repetition is the claim. v2's ONE genuinely good rule
     survives intact: ours-above / theirs-below, each date block hung off its own marker so a leader
     tick always meets an END of it. Do not re-derive that.

  2. THE COMMIT RIDGE IS THE SECOND DATA LAYER, AND IT ARGUES THE SECTION'S OWN POINT. The lower
     third is this repo's commit volume on the SAME time axis — 7-day trailing, sqrt-scaled,
     stepped one block per day. It is not decoration and it is not filler: both "here first" moments
     land BEFORE the explosion (2026-05-24 sits on flat ground during the zero-commit May the README
     already calls "the plateau between two"; 2026-07-10 sits on the first rise), and the ridge then
     climbs to a 1,024-commit week. The section's thesis is that these were invented on the way up,
     not announced from a roadmap, and the ridge is that thesis drawn to scale.
     WHY SQRT AND WHY TRAILING: raw daily counts over this window are median 0, max 322 — a picket
     fence with three spikes and no readable shape. A 7-day trailing sum makes it a growth curve;
     sqrt keeps the early activity visible instead of crushing it to a flat line under the August
     peak. Both transforms are named in the caption, because a shape drawn from a transformed series
     with no stated scale is a picture pretending to be a measurement.

  3. MASS, NOT HAIRLINES. The lead is a 26 px rounded BAND with a green ramp along its length and a
     soft glow, capped by its two markers — not v2's 3.5 px rule. A quantity you are meant to feel
     needs area; a 3.5 px line reads as a leader line, which is exactly how v2's read.
     THE NUMBER IS NOT ON THE BAND. It sits at the left margin, at 36 px, leading the capability
     name on one baseline. That is what finally makes the two lead placements consistent: v1 and v2
     both had to special-case the 4-day pair, because 4 days is 54 px and no pill fits inside it.
     Moving the number into the row header means the geometry never varies with the datum — and it
     buys a column the eye reads straight down: 4, then 28.

  4. THE MATERIAL IS THE HERO'S, VERBATIM AS METHOD. Sky is a four-stop vertical ramp, cool indigo
     at the top warming toward the horizon; the ridge is the warm source (amber, the repo's own
     badge gold) against that cool surround; the ridge carries a lit top edge and darkens toward its
     base. Per §D4 every palette entry has an identity — three hues, one job each: GREEN a capability
     running here, BLUE the Claude Code release, AMBER this repo's own work over time. Nothing is
     neutral grey; the greys are tinted toward the sky.

MOTION BUDGET (prior-art.md §B6: ~5 sub-threshold motions on separate layers, exactly one legible).
The legible one is the time cursor — a light column crossing left to right over the three months,
igniting each marker as it passes, in true chronological order. The two band flows and the four
ignitions are individually below threshold. The ridge is deliberately STATIC: it is the ground.

HARNESS CONTRACT (unchanged, measured, not stylistic). `scripts/banner-shots.sh --lint` keeps the
deterministic freeze exact, and constrains authoring in two ways this file obeys everywhere:
  * ONE animation per element. Anything needing two motions is split across a wrapper and a child.
  * NO literal `animation-delay`. Phase rides the additive channel `calc(var(--d,0s) + var(--fz,0s))`
    with the per-element offset in `--d`, which is the only spelling the freeze can seek.
Every sub-period divides P, so `banner-verify`'s SEAM check (t=0 == t=P) holds.

WHY EACH FILE CARRIES BOTH PALETTES. The README picks the file through `<picture>` +
`prefers-color-scheme`, GitHub's documented pattern. But an SVG in `<img>` also resolves
`prefers-color-scheme` itself (through the embedding element's used `color-scheme`), so a file with
ONE baked palette is wrong in exactly the case where the two mechanisms disagree. Both files carry
both palettes and differ only in the default: -dark.svg defaults dark and overrides to light,
-light.svg the reverse. It is also what makes `banner-verify`'s THEMES check (dark != light)
meaningful rather than a check the asset structurally cannot pass.

────────────────────────────────────────────────────────────────────────────────────────────────
v1 AND v2, AND WHY EACH WAS REPLACED (kept so no iteration re-derives a rejected design).

v1 — a two-lane chronology, 2025-02-24..2026-08-07, with a broken axis at this repo's first commit
and an orange connector running the other way for a lag. Operator: *"very unclear, disorganized, AI
slop."*
  v1.1 "two lanes, not one chain"  → KEPT IN SPIRIT. Two parties still, but paired per capability
       rather than pooled into two long lanes; a lane makes the reader find its own partner for
       each marker.
  v1.2 "the axis break is semantic" → DROPPED. It was semantic and it was still a break: it needed a
       "break" label, two gridline densities and a three-line note to be read at all.
  v1.3 "the gaps are to scale"      → KEPT. Still the only thing the x geometry claims.
  v1.4 "direction encodes ownership"→ DROPPED WITH ITS SUBJECT, on SCOPE not on truth. The orange
       path carried "7 months late — our gap, not theirs". Operator ruling 2026-08-12: this asset
       states what ran here FIRST, so a lag does not belong on it whatever its sign. The lag itself
       STANDS — see the status-line note below.

v2 — two tracks on one linear axis, flat plate, hairlines, eight type sizes. Fixed v1's structure
and lost its craft: correct and inert. Its ours-above/theirs-below rule is the one thing v3 keeps
unchanged (leg 1).

THE STATUS-LINE CONTEXT GAUGE IS OFF THIS CHART, AND STAYS OFF. A third track carrying it as a
175-day lead was built during v2 and cut on evidence. Three dates, all primary:
  * `context_window.{used_percentage,remaining_percentage}` shipped in 2.1.6 — npm 2026-01-13,
    CHANGELOG "Added `context_window.used_percentage` and `context_window.remaining_percentage`
    fields to status line input". THREE DAYS BEFORE the 2026-01-16 comment on issue #12520.
  * the fields that comment proposes — `conversation_output_tokens`,
    `effective_remaining_percentage` — have NEVER shipped. #12520 is still open and neither name
    appears anywhere in the CHANGELOG.
  * this repo read `used_percentage` on 2026-07-14 (`1b8d671b1`), ~6 months after 2.1.6. That commit
    cites "CC >=2.1.207" for `context_window_size`, but that is an observation about a payload, not
    a release note: `context_window_size` is in no CHANGELOG entry and 2.1.207 carries no
    status-line context change at all.
Both wrong intermediate readings came from dating the VENDOR's side off this repo's own prose — a
`statusline.sh` header comment, then a commit message. Date both sides from a primary source or do
not draw the row.
"""

from __future__ import annotations

import argparse
import math
import pathlib
import sys
from datetime import date, timedelta

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "diagrams"
STEM = "convergence-timeline"

# ── canvas ────────────────────────────────────────────────────────────────────────────────────
# 1400 wide against GitHub's measured 838 px README column (scripts/banner-column-width.py) is a
# 0.599 scale — the divisor every type size below is chosen against (design leg 0).
W, H = 1400, 636

PAD_L, PAD_R = (
    64,
    1336,
)  # plot extent; also the text margins, so everything shares one grid

# Row rhythm. Header (number + name) sits at the left margin on its own line; the band and its two
# date blocks sit at their true x on the axis. Ours-above / theirs-below is v2's one kept rule.
ROW_HEAD = (160, 336)  # baseline of "<lead> DAYS  <capability name>"
BAND_Y = (240, 416)  # centre-line of the lead band
DY_ABOVE = -34  # green date block, relative to the band
DY_BELOW = 34  # blue date block
BAND_H = 26

HORIZON = 576  # the ridge's baseline — also the time axis
TERRAIN_H = 110  # peak height of the ridge above the horizon
CAP_Y = 552  # ridge caption, in the empty sky over the flat left end
MONTH_Y = 606

# ── chronology ────────────────────────────────────────────────────────────────────────────────
# Claude Code dates are the npm publish time of the exact version string carrying the CHANGELOG
# line; this repo's dates are its own artefact. Never either side's prose about the other.
D0 = date(2026, 5, 10)  # axis start — a fortnight before the first event
D1 = date(
    2026, 8, 12
)  # axis end   — the ridge's data cutoff, so the terrain reaches the edge
SPAN = (D1 - D0).days  # 94
PPD = (
    PAD_R - PAD_L
) / SPAN  # 13.53 px/day — 4 days is 54 px, a bar rather than a smudge


def x_of(d: date) -> float:
    return PAD_L + (d - D0).days * PPD


TRACKS = [
    dict(
        key="adv",
        name="a research team that attacks its own findings",
        ours=date(2026, 5, 24),
        ours_text="running here",
        theirs=date(2026, 5, 28),
        theirs_text="Dynamic Workflows 2.1.154 — the same idea",
        # Which END of the block the marker's tick lands on. Stated per label, never derived: the
        # constraint on each block is a different neighbour, and a formula that got one right got
        # the next one wrong (v1 learned this expensively). "start" reads rightwards from the
        # marker, "end" runs back to the left — the choice is simply which side has the room.
        ours_at="start",
        theirs_at="start",
    ),
    dict(
        key="peer",
        name="two-way session messaging",
        ours=date(2026, 7, 10),
        ours_text="running here",
        theirs=date(2026, 8, 7),
        theirs_text="Claude Code 2.1.224 — sessions message each other",
        ours_at="start",
        theirs_at="end",  # the blue ring is 68 px from the margin; its block runs back left
    ),
]
for _t in TRACKS:
    _t["ox"] = x_of(_t["ours"])
    _t["tx"] = x_of(_t["theirs"])
    _t["lead"] = (_t["theirs"] - _t["ours"]).days

# ── the ridge: this repo's own commits, 7-day trailing ────────────────────────────────────────
# Regenerate with, from the repo root:
#   git log origin/main --since=2026-04-01 --until=2026-08-13 --format=%ad --date=format:%Y-%m-%d
# then per-day counts, 7-day trailing sum, sliced D0..D1 inclusive. Baked as a literal so `--check`
# is deterministic — a series read live would make every render differ from the one on disk.
# Measured 2026-08-12: 2,648 commits over the window, peak day 322, peak trailing week 1,024.
COMMITS_7D = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    7,
    9,
    9,
    10,
    12,
    12,
    12,
    9,
    8,
    9,
    8,
    6,
    6,
    6,
    2,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    2,
    6,
    24,
    24,
    23,
    23,
    23,
    22,
    18,
    12,
    36,
    36,
    39,
    111,
    131,
    140,
    149,
    223,
    276,
    321,
    282,
    268,
    286,
    311,
    375,
    429,
    384,
    395,
    711,
    851,
    1024,
    960,
    903,
    935,
    910,
    660,
    545,
    465,
    501,
    574,
    735,
    890,
    836,
]
RIDGE_PEAK = max(COMMITS_7D)
RIDGE_TOTAL = 2648
assert len(COMMITS_7D) == SPAN + 1, (
    f"ridge series is {len(COMMITS_7D)}, axis is {SPAN + 1} days"
)


def ridge_y(v: int) -> float:
    """sqrt so the early weeks stay visible under the August peak (design leg 2)."""
    return HORIZON - math.sqrt(v) / math.sqrt(RIDGE_PEAK) * TERRAIN_H


# ── palettes ──────────────────────────────────────────────────────────────────────────────────
# Three hues, one job each (§D4 — every entry must have an identity):
#   rep   GREEN  a capability running here        cc  BLUE   the Claude Code release
#   ridge AMBER  this repo's own work over time (the warm source against the cool sky, §B8)
DARK = dict(
    sky_a="#05080f",
    sky_b="#0d1424",
    sky_c="#1d1e3a",
    sky_d="#3a2740",
    edge="#242c3e",
    edge_hi="#ffffff",
    edge_hi_o="0.05",
    grid="#1a2133",
    ink="#eef3f9",
    ink2="#9aa8bb",
    ink3="#6c7889",
    track="#2c3547",
    rep="#3fb950",
    rep_hi="#7ee787",
    rep_dim="#1b6b2c",
    cc="#4b93e6",
    cc_hi="#8cc8ff",
    ridge_a="#d4af37",
    ridge_b="#7a5c22",
    ridge_c="#241a10",
    ridge_edge="#f0cf6a",
    scatter="#c98a4a",
    scatter_o="0.13",
    sweep="#bcd6ff",
    sweep_o="0.09",
    halo_o="0.36",
    glow_o="0.20",
    core="#0b1020",
)

LIGHT = dict(
    sky_a="#ffffff",
    sky_b="#f2f6fd",
    sky_c="#e9eefb",
    sky_d="#fbeedd",
    edge="#d8e0ea",
    edge_hi="#ffffff",
    edge_hi_o="0.85",
    grid="#e6ecf4",
    ink="#0c1218",
    ink2="#53606f",
    ink3="#7c8794",
    track="#ccd6e2",
    rep="#1a7f37",
    rep_hi="#2da44e",
    rep_dim="#8fc9a2",
    cc="#0969da",
    cc_hi="#218bff",
    ridge_a="#e3b64a",
    ridge_b="#c99a2f",
    ridge_c="#f3e3c4",
    ridge_edge="#b8862a",
    scatter="#e0a55c",
    scatter_o="0.20",
    sweep="#1f4e8c",
    sweep_o="0.05",
    halo_o="0.18",
    glow_o="0.14",
    core="#ffffff",
)

SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif'
MONO = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace'

# THREE sizes, 1.5x apart, so hierarchy survives the 0.599 downscale (design leg 0).
F_L, F_M, F_S = 36, 24, 18

P = 24  # master period, seconds. Every sub-period divides it, so t=0 == t=P.


# ── text width estimate ───────────────────────────────────────────────────────────────────────
# Not a metric — an estimate, used only to fail loudly at build time when a label would overrun its
# slot. The real check is the screenshot; this just stops a known-bad render reaching one.
def tw(
    s: str, size: float, weight: int = 400, tracking: float = 0.0, mono: bool = False
) -> float:
    if mono:
        per = 0.600
    elif weight >= 700:
        per = 0.565
    elif weight >= 600:
        per = 0.545
    else:
        per = 0.505
    return len(s) * (size * per + tracking)


WARNINGS: list[str] = []


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ── stylesheet ────────────────────────────────────────────────────────────────────────────────
def palette_vars(p: dict) -> str:
    return "".join(f"--{k}:{v};" for k, v in p.items())


def stylesheet(default: dict, override: dict, override_scheme: str) -> str:
    return f"""
:root{{{palette_vars(default)}}}
@media (prefers-color-scheme: {override_scheme}){{:root{{{palette_vars(override)}}}}}

text{{font-family:{MONO};dominant-baseline:auto}}
.sans{{font-family:{SANS}}}
.ink{{fill:var(--ink)}} .ink2{{fill:var(--ink2)}} .ink3{{fill:var(--ink3)}}
.c-rep{{fill:var(--rep)}} .c-cc{{fill:var(--cc)}}

.t-lead{{font-size:{F_L}px;font-weight:700;fill:var(--rep_hi)}}
.t-unit{{font-size:{F_S}px;font-weight:600;letter-spacing:1.8px;fill:var(--rep)}}
.t-name{{font-size:{F_M}px;font-weight:600;fill:var(--ink)}}
.t-s{{font-size:{F_S}px;fill:var(--ink2)}}
.t-s3{{font-size:{F_S}px;fill:var(--ink3)}}
.t-kick{{font-size:{F_S}px;font-weight:600;letter-spacing:2.6px;fill:var(--ink3)}}

.sky{{fill:url(#sky)}}
.edge{{fill:none;stroke:var(--edge);stroke-width:1.5}}
.edgehi{{fill:none;stroke:var(--edge_hi);stroke-width:1.5;opacity:var(--edge_hi_o)}}
.grid{{stroke:var(--grid);stroke-width:1}}
.horizon{{stroke:var(--ridge_edge);stroke-width:1.5;opacity:.45}}
.scatter{{fill:url(#scatter);opacity:var(--scatter_o)}}

/* the ridge — this repo's own commits, the warm source against the cool sky */
.ridge{{fill:url(#ridge)}}
.ridge-edge{{fill:none;stroke:var(--ridge_edge);stroke-width:2;stroke-linejoin:round;opacity:.9}}

/* the track, and the lead drawn as MASS */
.track{{stroke:var(--track);stroke-width:2;stroke-dasharray:2 10;stroke-linecap:round}}
.band-glow{{fill:var(--rep);opacity:var(--glow_o)}}
.band{{fill:url(#band)}}
.band-edge{{fill:none;stroke:var(--rep_hi);stroke-width:1.2;opacity:.5}}
.tick-rep{{stroke:var(--rep);stroke-width:1.5;opacity:.5;stroke-linecap:round}}
.tick-cc{{stroke:var(--cc);stroke-width:1.5;opacity:.5;stroke-linecap:round}}

.halo{{opacity:var(--halo_o)}}
.halo-rep{{fill:url(#haloRep)}} .halo-cc{{fill:url(#haloCc)}}
.mk-rep{{fill:url(#mkRep)}}
.mk-spec{{fill:#ffffff;opacity:.5}}
.mk-cc{{fill:var(--core);stroke:var(--cc);stroke-width:4.5}}

/* ── motion ─────────────────────────────────────────────────────────────────────────────────
   One animation per element, and no literal delay value anywhere — phase rides --d through the
   additive calc channel the freeze can seek (banner-shots --lint enforces both). Every period
   divides {P}s, so t=0 and t=P render identically. NB the lint reads this stylesheet as text, so
   a prose mention of that property followed by a colon reads to it as a declaration. */

@keyframes sweepx{{from{{transform:translateX(0px)}}to{{transform:translateX({SWEEP_TRAVEL}px)}}}}
.sweep{{animation:sweepx {P}s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}
.sweepfill{{fill:url(#sweep);opacity:var(--sweep_o)}}

@keyframes ignite{{
  0%{{opacity:0;transform:scale(1)}}
  2%{{opacity:.9;transform:scale(1)}}
  10%{{opacity:0;transform:scale(2.15)}}
  100%{{opacity:0;transform:scale(1)}}}}
.ig{{fill:none;stroke-width:2.6;transform-box:fill-box;transform-origin:50% 50%;opacity:0;
     animation:ignite {P}s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}
.ig-rep{{stroke:var(--rep_hi)}} .ig-cc{{stroke:var(--cc_hi)}}

@keyframes flow{{from{{stroke-dashoffset:0}}to{{stroke-dashoffset:-104px}}}}
.flow{{fill:none;stroke:var(--rep_hi);stroke-width:{BAND_H - 10};stroke-linecap:butt;opacity:.13;
       stroke-dasharray:16 88}}
.flow-a{{animation:flow 12s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}
.flow-b{{animation:flow 8s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}

@media (prefers-reduced-motion: reduce){{*{{animation:none !important}}}}
"""


# ── defs ──────────────────────────────────────────────────────────────────────────────────────
def defs() -> str:
    # Gradient stops carry their colour through a class so the palette override reaches them; a
    # `stop-color="var(...)"` presentation attribute is not reliably resolved.
    return f"""<defs>
<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-sky-a"/><stop offset=".42" class="g-sky-b"/>
  <stop offset=".76" class="g-sky-c"/><stop offset="1" class="g-sky-d"/></linearGradient>
<linearGradient id="ridge" x1="0" y1="{HORIZON - TERRAIN_H}" x2="0" y2="{HORIZON}"
    gradientUnits="userSpaceOnUse">
  <stop offset="0" class="g-ridge-a"/><stop offset=".55" class="g-ridge-b"/>
  <stop offset="1" class="g-ridge-c"/></linearGradient>
<linearGradient id="band" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" class="g-rep-hi"/><stop offset=".55" class="g-rep"/>
  <stop offset="1" class="g-rep-dim"/></linearGradient>
<radialGradient id="mkRep" cx=".38" cy=".32" r=".75">
  <stop offset="0" class="g-rep-hi"/><stop offset="1" class="g-rep"/></radialGradient>
<radialGradient id="haloRep"><stop offset="0" class="g-rep" stop-opacity=".9"/>
  <stop offset="1" class="g-rep" stop-opacity="0"/></radialGradient>
<radialGradient id="haloCc"><stop offset="0" class="g-cc" stop-opacity=".9"/>
  <stop offset="1" class="g-cc" stop-opacity="0"/></radialGradient>
<linearGradient id="scatter" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-scatter" stop-opacity="0"/>
  <stop offset="1" class="g-scatter" stop-opacity="1"/></linearGradient>
<linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" class="g-sweep" stop-opacity="0"/>
  <stop offset=".62" class="g-sweep" stop-opacity=".55"/>
  <stop offset=".88" class="g-sweep" stop-opacity="1"/>
  <stop offset="1" class="g-sweep" stop-opacity="0"/></linearGradient>
</defs>
<style>
.g-sky-a{{stop-color:var(--sky_a)}} .g-sky-b{{stop-color:var(--sky_b)}}
.g-sky-c{{stop-color:var(--sky_c)}} .g-sky-d{{stop-color:var(--sky_d)}}
.g-ridge-a{{stop-color:var(--ridge_a)}} .g-ridge-b{{stop-color:var(--ridge_b)}}
.g-ridge-c{{stop-color:var(--ridge_c)}}
.g-rep{{stop-color:var(--rep)}} .g-rep-hi{{stop-color:var(--rep_hi)}}
.g-rep-dim{{stop-color:var(--rep_dim)}}
.g-cc{{stop-color:var(--cc)}} .g-sweep{{stop-color:var(--sweep)}}
.g-scatter{{stop-color:var(--scatter)}}
</style>"""


# ── the time cursor ───────────────────────────────────────────────────────────────────────────
SWEEP_W = 300
SWEEP_TRAVEL = W + SWEEP_W
SWEEP_EDGE = SWEEP_W * (1 - 0.88)
IGNITE_PEAK = 0.02 * P


def phase_for(x: float) -> str:
    """The --d that makes a marker peak exactly as the cursor's bright edge crosses it.

    Derived, not tuned. The column's leading bright edge is at `SWEEP_TRAVEL * t / P - SWEEP_EDGE`,
    so it reaches x at t_fire; the element's own clock is `t - delay`, and we want that to equal
    IGNITE_PEAK at t_fire. Subtracting one whole period keeps the value negative, which is what the
    freeze's additive seek expects. (The first spelling ignored both the peak offset and the sign
    convention; it looked plausible and was wrong by ~11 s.)
    """
    t_fire = (x + SWEEP_EDGE) * P / SWEEP_TRAVEL
    return f"--d:{t_fire - IGNITE_PEAK - P:.3f}s"


# ── drawing ───────────────────────────────────────────────────────────────────────────────────
def month_starts() -> list[date]:
    out, y, m = [], D0.year, D0.month
    while True:
        d = date(y, m, 1)
        if d > D1:
            break
        out.append(d)
        m += 1
        if m > 12:
            y, m = y + 1, 1
    return out


def date_block(
    a, x: float, align: str, dt: str, text: str, hue: str, y: float, where: str
) -> None:
    """`2026-08-07  Claude Code 2.1.224 — …`, hung off ONE end from its own marker so the leader
    tick meets an end of the block rather than the middle of a sentence (v2's kept rule)."""
    wd = tw(dt, F_S, mono=True)
    wid = wd + 12 + tw(text, F_S, mono=True)
    left = (x - 6) if align == "start" else (x + 6 - wid)
    if left < PAD_L or left + wid > PAD_R:
        WARNINGS.append(
            f"  {where}: block {left:.0f}..{left + wid:.0f} outside {PAD_L}..{PAD_R}"
        )
    a(f'<text class="t-s c-{hue}" x="{left:.1f}" y="{y:.0f}">{esc(dt)}</text>')
    a(f'<text class="t-s" x="{left + wd + 12:.1f}" y="{y:.0f}">{esc(text)}</text>')


def build() -> str:
    o: list[str] = []
    a = o.append

    # ── sky ───────────────────────────────────────────────────────────────────────────────────
    a(f'<rect class="sky" x="0" y="0" width="{W}" height="{H}" rx="16"/>')
    a(
        f'<g class="sweep" style="--d:0s"><rect class="sweepfill" x="-{SWEEP_W}" y="0" '
        f'width="{SWEEP_W}" height="{H}"/></g>'
    )

    # ── month grid ────────────────────────────────────────────────────────────────────────────
    starts = month_starts()
    a("<g>")
    for d in starts:
        if d <= D0:
            continue
        a(
            f'<line class="grid" x1="{x_of(d):.1f}" y1="96" x2="{x_of(d):.1f}" y2="{HORIZON}"/>'
        )
    a("</g>")

    # ── the ridge: one stepped block per day, closed to the horizon ───────────────────────────
    # Scatter first, so the ridge silhouettes against its own light rather than sitting on flat sky.
    # FULL-BLEED, not PAD_L..PAD_R: a scatter clipped to the plot has two hard vertical edges at
    # full opacity down at the horizon, which reads as a grey box behind the ridge. Atmosphere has
    # no left edge.
    a(
        f'<rect class="scatter" x="0" y="{HORIZON - TERRAIN_H - 40}" '
        f'width="{W}" height="{TERRAIN_H + 40}"/>'
    )
    pts = [f"M {PAD_L} {HORIZON}"]
    for i, v in enumerate(COMMITS_7D):
        x1 = PAD_L + i * PPD
        x2 = min(PAD_L + (i + 1) * PPD, PAD_R)
        y = ridge_y(v)
        pts.append(f"L {x1:.1f} {y:.1f} L {x2:.1f} {y:.1f}")
    pts.append(f"L {PAD_R} {HORIZON} Z")
    a(f'<path class="ridge" d="{" ".join(pts)}"/>')
    # The lit top edge is the PROFILE only. Reusing the closed fill path would stroke a vertical
    # line up the left margin, where the series is zero and no ridge exists.
    a(f'<path class="ridge-edge" d="{"M" + " ".join(pts[1:-1])[1:]}"/>')
    a(
        f'<line class="horizon" x1="{PAD_L}" y1="{HORIZON}" x2="{PAD_R}" y2="{HORIZON}"/>'
    )

    # month scale, under the horizon
    a("<g>")
    for i, d in enumerate(starts):
        nxt = starts[i + 1] if i + 1 < len(starts) else D1
        mid = (x_of(d) + x_of(min(nxt, D1))) / 2
        lbl = d.strftime("%b") + (" ’26" if i == 0 else "")
        a(
            f'<text class="t-s3" x="{mid:.1f}" y="{MONTH_Y}" text-anchor="middle">{esc(lbl)}</text>'
        )
    a("</g>")

    # ── the two tracks ────────────────────────────────────────────────────────────────────────
    for i, (t, hy, by) in enumerate(zip(TRACKS, ROW_HEAD, BAND_Y)):
        ox, tx = t["ox"], t["tx"]

        # row header: the lead as the hero numeral, leading the name on one baseline
        lead = str(t["lead"])
        a(f'<text class="t-lead" x="{PAD_L}" y="{hy}">{lead}</text>')
        cx = PAD_L + tw(lead, F_L, 700, mono=True) + 10
        a(f'<text class="t-unit" x="{cx:.1f}" y="{hy}">DAYS</text>')
        nx = cx + tw("DAYS", F_S, 600, 1.8) + 24
        a(f'<text class="t-name sans" x="{nx:.1f}" y="{hy}">{esc(t["name"])}</text>')
        if nx + tw(t["name"], F_M, 600) > PAD_R:
            WARNINGS.append(f"  {t['key']} header overruns {PAD_R}")

        # full-width track, so a header at x=64 stays tied to a band at x=889
        a(f'<line class="track" x1="{PAD_L}" y1="{by}" x2="{ox - 16:.1f}" y2="{by}"/>')
        a(f'<line class="track" x1="{tx + 16:.1f}" y1="{by}" x2="{PAD_R}" y2="{by}"/>')

        # the lead, with MASS
        bx, bw, r = ox, tx - ox, BAND_H / 2
        a(
            f'<rect class="band-glow" x="{bx - 4:.1f}" y="{by - r - 4:.1f}" width="{bw + 8:.1f}" '
            f'height="{BAND_H + 8}" rx="{r + 4:.1f}"/>'
        )
        a(
            f'<rect class="band" x="{bx:.1f}" y="{by - r:.1f}" width="{bw:.1f}" '
            f'height="{BAND_H}" rx="{r:.1f}"/>'
        )
        a(
            f'<line class="flow flow-{"a" if i == 0 else "b"}" x1="{bx:.1f}" y1="{by}" '
            f'x2="{tx:.1f}" y2="{by}" style="--d:0s"/>'
        )
        a(
            f'<rect class="band-edge" x="{bx:.1f}" y="{by - r:.1f}" width="{bw:.1f}" '
            f'height="{BAND_H}" rx="{r:.1f}"/>'
        )

        # leader ticks into each block's own band
        a(
            f'<line class="tick-rep" x1="{ox:.1f}" y1="{by - 16}" x2="{ox:.1f}" y2="{by + DY_ABOVE + 6}"/>'
        )
        a(
            f'<line class="tick-cc" x1="{tx:.1f}" y1="{by + 16}" x2="{tx:.1f}" y2="{by + DY_BELOW - 14}"/>'
        )

        # markers, capping the band
        a(f'<g transform="translate({ox:.1f},{by})">')
        a('<circle class="halo halo-rep" r="15"/>')
        a('<circle class="mk-rep" r="10.5"/>')
        a('<circle class="mk-spec" cx="-3.2" cy="-3.8" r="2.5"/>')
        a(f'<circle class="ig ig-rep" r="13" style="{phase_for(ox)}"/>')
        a("</g>")
        a(f'<g transform="translate({tx:.1f},{by})">')
        a('<circle class="halo halo-cc" r="14"/>')
        a('<circle class="mk-cc" r="9"/>')
        a(f'<circle class="ig ig-cc" r="12.5" style="{phase_for(tx)}"/>')
        a("</g>")

        date_block(
            a,
            ox,
            t["ours_at"],
            t["ours"].isoformat(),
            t["ours_text"],
            "rep",
            by + DY_ABOVE,
            f"{t['key']} ours",
        )
        date_block(
            a,
            tx,
            t["theirs_at"],
            t["theirs"].isoformat(),
            t["theirs_text"],
            "cc",
            by + DY_BELOW,
            f"{t['key']} theirs",
        )

    # ── header + ridge caption ────────────────────────────────────────────────────────────────
    a(f'<text class="t-kick" x="{PAD_L}" y="46">HERE FIRST · TWICE</text>')
    key = "Bar = the days it was running here before the Claude Code release that shipped it."
    a(f'<text class="t-s" x="{PAD_L}" y="82">{esc(key)}</text>')

    cap = f"this repo's own commits · 7-day trailing · peak {RIDGE_PEAK:,}/wk"
    a(f'<text class="t-s3" x="{PAD_L}" y="{CAP_Y}">{esc(cap)}</text>')
    # The caption must die inside the flat left end of its own series, or it is text over terrain.
    _cap_end = PAD_L + tw(cap, F_S, mono=True)
    _flat_to = PAD_L + next(i for i, v in enumerate(COMMITS_7D) if v > 12) * PPD
    if _cap_end > _flat_to:
        WARNINGS.append(
            f"  ridge caption ends {_cap_end:.0f}, ridge leaves the floor at {_flat_to:.0f}"
        )

    legend = (("rep", "running here"), ("cc", "shipped in Claude Code"))
    span = sum(15 + tw(s, F_S, mono=True) + 34 for _, s in legend) - 34
    lx = PAD_R - span
    for hue, text in legend:
        if hue == "rep":
            a(f'<circle class="mk-rep" cx="{lx:.0f}" cy="40" r="8"/>')
        else:
            a(f'<circle class="mk-cc" cx="{lx:.0f}" cy="40" r="6"/>')
        a(f'<text class="t-s" x="{lx + 15:.0f}" y="46">{esc(text)}</text>')
        lx += 15 + tw(text, F_S, mono=True) + 34

    # ── card edge, drawn last so nothing paints over it ───────────────────────────────────────
    a(
        f'<rect class="edge" x=".75" y=".75" width="{W - 1.5}" height="{H - 1.5}" rx="16"/>'
    )
    a(f'<path class="edgehi" d="M 17 1.5 H {W - 17} A 15.5 15.5 0 0 1 {W - 1.5} 17"/>')

    return "\n".join(o)


TITLE = "Twice, this repo shipped it first"

ALT = (
    "A dusk-toned chart on one time axis running from May to August 2026. Along the bottom, drawn "
    "as an amber stepped ridge rising out of the horizon, is this repo's own commit volume over "
    "the same period — 7-day trailing, 2,648 commits in the window, peaking at 1,024 in a week. "
    "Above it, two tracks cross the full width, one per capability. Each track begins with its "
    "lead as a large numeral at the left margin, followed by the capability name; out on the axis "
    "a thick green bar runs from a filled green disc, on the date the capability was running in "
    "this repo, to a hollow blue ring, on the date of the Claude Code release that shipped it. "
    "The green disc is left of the blue ring on both tracks. "
    "The first track, 4 days — a research team that attacks its own findings: running here on "
    "2026-05-24; Dynamic Workflows 2.1.154, the same idea, on 2026-05-28. Its bar sits over the "
    "flat left end of the ridge, where this repo committed nothing at all that month. "
    "The second track, 28 days — two-way session messaging: running here on 2026-07-10; Claude "
    "Code 2.1.224, in which sessions message each other, on 2026-08-07. Its bar sits over the "
    "ridge's first rise, before the climb to the August peak. "
    "A soft column of light crosses the chart from left to right once every 24 seconds, lighting "
    "each of the four markers as it passes, in date order."
)

DESC = (
    "Two tracks on one time axis, May to August 2026, over an amber ridge of this repo's own "
    "commit volume. On each track a green disc marks the date the capability was running here and "
    "a blue ring the Claude Code release that shipped it; the bar between them is the lead, drawn "
    "to scale, with its length in days as a large numeral at the left margin — 4 days and 28 days. "
    "Both leads fall before the ridge's climb. A light column crosses left to right once every 24 "
    "seconds, igniting each marker in date order."
)


def render(variant: str) -> str:
    default, override, scheme = (
        (DARK, LIGHT, "light") if variant == "dark" else (LIGHT, DARK, "dark")
    )
    body = build()
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}"\n'
        f'     role="img" aria-labelledby="ttl dsc">\n'
        f'<title id="ttl">{esc(TITLE)}</title>\n'
        f'<desc id="dsc">{esc(DESC)}</desc>\n'
        f"{defs()}\n"
        f"<style>{stylesheet(default, override, scheme)}</style>\n"
        f"{body}\n"
        f"</svg>\n"
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if a file on disk differs from a fresh render",
    )
    ap.add_argument(
        "--alt", action="store_true", help="print the README alt text and exit"
    )
    args = ap.parse_args()

    if args.alt:
        print(ALT)
        return 0

    stale = 0
    for variant in ("dark", "light"):
        svg = render(variant)
        path = OUT_DIR / f"{STEM}-{variant}.svg"
        if args.check:
            cur = path.read_text() if path.exists() else None
            if cur != svg:
                print(
                    f"STALE: {path.relative_to(ROOT)} — run `python3 tools/timeline/gen.py`",
                    file=sys.stderr,
                )
                stale += 1
        else:
            path.write_text(svg)
            print(f"wrote {path.relative_to(ROOT)} ({len(svg) / 1024:.1f} KB)")

    if WARNINGS:
        print(
            "text-fit warnings (estimates — confirm on the screenshot):",
            file=sys.stderr,
        )
        for w in dict.fromkeys(WARNINGS):
            print(w, file=sys.stderr)

    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
