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
THE DESIGN ARGUMENT (v4, 2026-08-12). Operator: *"I like the structure of v1 but just make it
better with more concise design system and consistent fonts."* So v4 is v1's TWO-LANE structure —
this repo's lane above, Claude Code's below, a drop from each capability to the release that
shipped it — rebuilt on a closed element vocabulary, one typeface and three sizes. v1's structure
was never the defect; its execution was. The full history of what each version got right and wrong
is at the foot of this docstring, and is the reason v4 can restore a structure that was once
rejected without also restoring what got it rejected.

THE ELEMENT VOCABULARY — SIX TYPES, AND NOTHING ELSE MAY BE ADDED WITHOUT DELETING ONE. This is
what "concise design system" means operationally: a fixed inventory, so the next edit has to argue
against the budget rather than quietly append to it. v1 carried thirteen (two lane styles, ghost
rule, halo, ring, dot, specular, chip, leader, stem, axis-cut, bloom, head-start note).

  1. LANE     a full-width rule in the party's colour.                          2 instances
  2. MARKER   on a lane: a filled disc for this repo, a ring for Claude Code.   4 instances
  3. DROP     a curve from a repo marker to the release that shipped it.        2 instances
  4. CHIP     the lead in days, riding its drop's midpoint.                     2 instances
  5. STACK    name over date at a marker — above its lane on the repo side,
              below on the Claude Code side, so the two never contend.          4 instances
  6. GROUND   the commit ridge, its horizon, and the month scale.               1 instance

TYPE — ONE FAMILY, THREE SIZES. Everything is mono, the hero banner's own face, so there is no
second typeface to be inconsistent with; "consistent fonts" is enforced by there being one. Sizes
are 34 / 22 / 17, each ~1.5x the next, rendering 20.4 / 13.2 / 10.2 at GitHub's 838 px column
(a 0.599 scale). L is chip numerals only. M is the four names — a capability or a release, the
things a reader is meant to come away with. S is everything else: dates, lane names, the kicker,
the ridge caption, the month scale. Nothing else gets a size.
  Why this is the fix and not a preference: v1 had EIGHT sizes between 16 and 26 px, which all land
  inside 9.6–15.6 px after the downscale, plus sans and mono mixed with no rule about which meant
  what. Eight sizes that render four points apart are not a hierarchy, they are noise.

COLOUR — THREE HUES, ONE JOB EACH (prior-art.md §D4: every palette entry must have an identity).
GREEN this repo · BLUE Claude Code · AMBER this repo's own work over time, which is the ridge and
the one warm source against a cool sky (§B8). Nothing is neutral grey; the greys are tinted toward
the sky. v1's fourth hue, orange, existed only to carry the lag — see the note at the foot.

WHAT v4 KEEPS FROM THE LATER VERSIONS, BECAUSE EACH WAS EARNED THE HARD WAY:
  * the ridge (v3) — this repo's commit volume, 7-day trailing, sqrt-scaled, one stepped block per
    day, on the same axis. Both "here first" moments land BEFORE the climb, which is the section's
    own thesis drawn to scale rather than asserted.
  * ours-above / theirs-below (v2) — the rule that makes leader lines unnecessary. Here it is
    structural rather than a convention: each lane's stacks sit on its own outboard side.
  * the single linear axis (v2) — no break, because dropping the self-diminishing content left only
    94 days to span. At 13.5 px/day even the 4-day pair is legible.
  * the dusk material (v3) — depth from colour bands before any shape is drawn (§B1/§B2).

MOTION BUDGET (prior-art.md §B6: ~5 sub-threshold motions on separate layers, exactly one legible).
The legible one is the time cursor crossing left to right once per period, igniting each marker at
its true date. The two drop flows and the four ignitions are individually below threshold. The
ridge is deliberately STATIC: it is the ground.

HARNESS CONTRACT (measured, not stylistic). `scripts/banner-shots.sh --lint` keeps the
deterministic freeze exact, and constrains authoring in two ways this file obeys everywhere:
  * ONE animation per element. Anything needing two motions is split across a wrapper and a child.
  * NO literal `animation-delay`. Phase rides the additive channel `calc(var(--d,0s) + var(--fz,0s))`
    with the per-element offset in `--d`, which is the only spelling the freeze can seek.
Every sub-period divides P, so `banner-verify`'s SEAM check (t=0 == t=P) holds.

WHY EACH FILE CARRIES BOTH PALETTES. The README picks the file through `<picture>` +
`prefers-color-scheme`, GitHub's documented pattern. But an SVG in `<img>` also resolves
`prefers-color-scheme` itself (through the embedding element's used `color-scheme`), so a file with
ONE baked palette is wrong in exactly the case where the two mechanisms disagree. Both files carry
both palettes and differ only in the default. It is also what makes `banner-verify`'s THEMES check
(dark != light) meaningful rather than a check the asset structurally cannot pass.

────────────────────────────────────────────────────────────────────────────────────────────────
THE FOUR VERSIONS, AND WHAT EACH ONE SETTLED (kept so no iteration re-derives a rejected design,
and so v4's restoration of v1's structure is not read as a circle).

v1 — two lanes over 2025-02-24..2026-08-07, a broken axis at this repo's first commit, an orange
     connector running the other way for a lag, and a three-line note apologising for a 13-month
     head start. Operator: *"very unclear, disorganized, AI slop."*
     SETTLED: the STRUCTURE was right and is restored here. What failed was execution — thirteen
     element types, eight type sizes, two typefaces mixed without a rule, four alternating label
     rows joined by leader lines, and the widest, most saturated path on the canvas spent on the
     one negative. Also settled: the axis break was not cosmetic but it still needed a "break"
     label, two gridline densities and a paragraph to be read at all — and it existed only to reach
     content that has since been cut, so it goes with it.
v2 — two isolated tracks on one linear axis, flat plate, hairlines, eight sizes. Fixed v1's
     disorganisation and lost its craft. Operator: *"REGRESSED … just as unreadable with the large
     varying texts and LESS visualization and beautiful complexion."*
     SETTLED: ours-above/theirs-below, and that a chart of four data points cannot carry a
     1400x524 canvas on hairlines alone.
v3 — v2 plus the commit ridge, mass, and the hero's dusk material. Fixed the complexion.
     SETTLED: the ridge, the material, and that the house standard (`assets/banner/v6c-dusk-line.svg`
     plus `docs/research/prior-art.md`) must be READ BEFORE designing against it — it was not, for
     two whole iterations, and rendering it produced the entire brief in two tool calls.
     What v3 still lacked is what v1 had: two lanes make the two-parties claim STRUCTURALLY, where
     v3's isolated bands left the reader to infer it.

THE ORANGE LAG PATH IS GONE AND STAYS GONE — on SCOPE, not on truth. Operator ruling 2026-08-12:
this asset states what ran here FIRST, so a lag does not belong on it whatever its sign. The lag
itself stands; `docs/research/vendor-convergence-2026-08-07.md` §1 measured it and it survived
re-derivation from the CHANGELOG.

THE STATUS-LINE CONTEXT GAUGE IS OFF THIS CHART AND STAYS OFF. A third pair carrying it as a
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
not draw the pair.
"""

from __future__ import annotations

import argparse
import math
import pathlib
import sys
from datetime import date

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "diagrams"
STEM = "convergence-timeline"

# ── canvas ────────────────────────────────────────────────────────────────────────────────────
# 1400 wide against GitHub's measured 838 px README column (scripts/banner-column-width.py) is a
# 0.599 scale — the divisor every type size is chosen against.
W, H = 1400, 636
PAD_L, PAD_R = 64, 1336

# The two lanes, and the band between them that the drops and chips own. Each lane's STACKs sit on
# its OUTBOARD side — repo above, Claude Code below — so the inner band is never contended.
LANE_REPO, LANE_CC = 190, 330
DROP_MID = (LANE_REPO + LANE_CC) / 2  # 260 — where every chip rides, by construction
DY_NAME, DY_DATE = 50, 24  # outboard offsets from a lane to its stack's two rows

HORIZON = 576
TERRAIN_H = 150
CAP_Y = 552
MONTH_Y = 606

# ── chronology ────────────────────────────────────────────────────────────────────────────────
# Claude Code dates are the npm publish time of the exact version string carrying the CHANGELOG
# line; this repo's dates are its own artefact. Never either side's prose about the other.
D0 = date(2026, 5, 10)
D1 = date(2026, 8, 12)  # the ridge's data cutoff, so the ground reaches the right edge
SPAN = (D1 - D0).days  # 94
PPD = (
    PAD_R - PAD_L
) / SPAN  # 13.53 px/day — the 4-day pair is 54 px, legible without a break


def x_of(d: date) -> float:
    return PAD_L + (d - D0).days * PPD


PAIRS = [
    dict(
        key="adv",
        ours=date(2026, 5, 24),
        ours_name="a research team that attacks its own findings",
        theirs=date(2026, 5, 28),
        theirs_name="Dynamic Workflows 2.1.154",
        ours_at="start",  # which end of the STACK its marker sits at — stated, never derived,
        theirs_at="start",  # because the binding neighbour differs per stack
    ),
    dict(
        key="peer",
        ours=date(2026, 7, 10),
        ours_name="two-way session messaging",
        theirs=date(2026, 8, 7),
        theirs_name="Claude Code 2.1.224",
        ours_at="start",
        theirs_at="end",  # 68 px from the margin: this stack runs back to the left
    ),
]
for _p in PAIRS:
    _p["ox"] = x_of(_p["ours"])
    _p["tx"] = x_of(_p["theirs"])
    _p["lead"] = (_p["theirs"] - _p["ours"]).days

# ── GROUND: this repo's own commits, 7-day trailing ───────────────────────────────────────────
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
assert len(COMMITS_7D) == SPAN + 1, (
    f"ridge is {len(COMMITS_7D)} days, axis is {SPAN + 1}"
)


def ridge_y(v: int) -> float:
    """sqrt so the early weeks stay visible under the August peak."""
    return HORIZON - math.sqrt(v) / math.sqrt(RIDGE_PEAK) * TERRAIN_H


# ── palettes — three hues, one job each ───────────────────────────────────────────────────────
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
    rep="#3fb950",
    rep_hi="#7ee787",
    rep_dim="#1f7a33",
    cc="#4b93e6",
    cc_hi="#8cc8ff",
    cc_dim="#2a5c96",
    ridge_a="#d4af37",
    ridge_b="#7a5c22",
    ridge_c="#241a10",
    ridge_edge="#f0cf6a",
    scatter="#c98a4a",
    scatter_o="0.13",
    chip_a="#16241a",
    chip_b="#0f1a13",
    sweep="#bcd6ff",
    sweep_o="0.09",
    halo_o="0.34",
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
    rep="#1a7f37",
    rep_hi="#2da44e",
    rep_dim="#94c9a4",
    cc="#0969da",
    cc_hi="#218bff",
    cc_dim="#9dc4ec",
    ridge_a="#e3b64a",
    ridge_b="#c99a2f",
    ridge_c="#f3e3c4",
    ridge_edge="#b8862a",
    scatter="#e0a55c",
    scatter_o="0.20",
    chip_a="#e9f7ed",
    chip_b="#dcf1e3",
    sweep="#1f4e8c",
    sweep_o="0.05",
    halo_o="0.18",
    core="#ffffff",
)

MONO = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace'
F_L, F_M, F_S = 34, 22, 17  # chip numerals · the four names · everything else
P = 24  # master period, seconds. Every sub-period divides it, so t=0 == t=P.


# ── text width estimate ───────────────────────────────────────────────────────────────────────
# Not a metric — an estimate, used only to fail loudly at build time when a label would overrun its
# slot. The real check is the screenshot; this just stops a known-bad render reaching one.
# EVERYTHING here is mono, so this takes no family argument: v3 shipped a bug where the estimator
# defaulted to sans metrics (0.505/char) for text that rendered mono (0.600), a 19% under-estimate
# that made the overflow guard structurally unable to fire.
def tw(s: str, size: float, tracking: float = 0.0) -> float:
    return len(s) * (size * 0.600 + tracking)


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
.ink{{fill:var(--ink)}} .ink2{{fill:var(--ink2)}} .ink3{{fill:var(--ink3)}}
.c-rep{{fill:var(--rep)}} .c-cc{{fill:var(--cc)}}

.t-l{{font-size:{F_L}px;font-weight:700;fill:var(--rep_hi)}}
.t-lu{{font-size:{F_S}px;font-weight:700;letter-spacing:2.4px;fill:var(--rep)}}
.t-m{{font-size:{F_M}px;font-weight:600;fill:var(--ink)}}
.t-s{{font-size:{F_S}px;fill:var(--ink2)}}
.t-s3{{font-size:{F_S}px;fill:var(--ink3)}}
.t-lane{{font-size:{F_S}px;font-weight:700;letter-spacing:2.4px}}
.t-kick{{font-size:{F_S}px;font-weight:600;letter-spacing:2.6px;fill:var(--ink3)}}

.sky{{fill:url(#sky)}}
.edge{{fill:none;stroke:var(--edge);stroke-width:1.5}}
.edgehi{{fill:none;stroke:var(--edge_hi);stroke-width:1.5;opacity:var(--edge_hi_o)}}
.grid{{stroke:var(--grid);stroke-width:1}}

/* 1. LANE */
.lane{{stroke-width:2.5;stroke-linecap:round}}
.lane-rep{{stroke:url(#laneRep)}} .lane-cc{{stroke:url(#laneCc)}}

/* 3. DROP */
.drop{{fill:none;stroke:var(--rep);stroke-width:3;stroke-linecap:round}}
.drop-hi{{fill:none;stroke:var(--rep_hi);stroke-width:1.2;opacity:.5;stroke-linecap:round}}
.drop-head{{fill:var(--rep)}}
.flow{{fill:none;stroke:var(--rep_hi);stroke-width:3;stroke-linecap:butt;opacity:.55;
       stroke-dasharray:10 74}}
.flow-a{{animation:flow 12s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}
.flow-b{{animation:flow 8s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}

/* 2. MARKER */
.halo{{opacity:var(--halo_o)}}
.halo-rep{{fill:url(#haloRep)}} .halo-cc{{fill:url(#haloCc)}}
.mk-rep{{fill:url(#mkRep)}}
.mk-spec{{fill:#ffffff;opacity:.5}}
.mk-cc{{fill:var(--core);stroke:var(--cc);stroke-width:4}}

/* 4. CHIP */
.chip{{fill:url(#chip);stroke:var(--rep);stroke-width:1.4}}

/* 6. GROUND */
.scatter{{fill:url(#scatter);opacity:var(--scatter_o)}}
.ridge{{fill:url(#ridge)}}
.ridge-edge{{fill:none;stroke:var(--ridge_edge);stroke-width:2;stroke-linejoin:round;opacity:.9}}
.horizon{{stroke:var(--ridge_edge);stroke-width:1.5;opacity:.45}}

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
  10%{{opacity:0;transform:scale(2.2)}}
  100%{{opacity:0;transform:scale(1)}}}}
.ig{{fill:none;stroke-width:2.6;transform-box:fill-box;transform-origin:50% 50%;opacity:0;
     animation:ignite {P}s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}
.ig-rep{{stroke:var(--rep_hi)}} .ig-cc{{stroke:var(--cc_hi)}}

@keyframes flow{{from{{stroke-dashoffset:0}}to{{stroke-dashoffset:-84px}}}}

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
<linearGradient id="laneRep" x1="{PAD_L}" y1="0" x2="{PAD_R}" y2="0" gradientUnits="userSpaceOnUse">
  <stop offset="0" class="g-rep-dim"/><stop offset=".5" class="g-rep"/>
  <stop offset="1" class="g-rep-hi"/></linearGradient>
<linearGradient id="laneCc" x1="{PAD_L}" y1="0" x2="{PAD_R}" y2="0" gradientUnits="userSpaceOnUse">
  <stop offset="0" class="g-cc-dim"/><stop offset=".5" class="g-cc"/>
  <stop offset="1" class="g-cc-hi"/></linearGradient>
<linearGradient id="ridge" x1="0" y1="{HORIZON - TERRAIN_H}" x2="0" y2="{HORIZON}"
    gradientUnits="userSpaceOnUse">
  <stop offset="0" class="g-ridge-a"/><stop offset=".55" class="g-ridge-b"/>
  <stop offset="1" class="g-ridge-c"/></linearGradient>
<linearGradient id="chip" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-chip-a"/><stop offset="1" class="g-chip-b"/></linearGradient>
<linearGradient id="scatter" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-scatter" stop-opacity="0"/>
  <stop offset="1" class="g-scatter" stop-opacity="1"/></linearGradient>
<radialGradient id="mkRep" cx=".38" cy=".32" r=".75">
  <stop offset="0" class="g-rep-hi"/><stop offset="1" class="g-rep"/></radialGradient>
<radialGradient id="haloRep"><stop offset="0" class="g-rep" stop-opacity=".9"/>
  <stop offset="1" class="g-rep" stop-opacity="0"/></radialGradient>
<radialGradient id="haloCc"><stop offset="0" class="g-cc" stop-opacity=".9"/>
  <stop offset="1" class="g-cc" stop-opacity="0"/></radialGradient>
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
.g-chip-a{{stop-color:var(--chip_a)}} .g-chip-b{{stop-color:var(--chip_b)}}
.g-rep{{stop-color:var(--rep)}} .g-rep-hi{{stop-color:var(--rep_hi)}}
.g-rep-dim{{stop-color:var(--rep_dim)}}
.g-cc{{stop-color:var(--cc)}} .g-cc-hi{{stop-color:var(--cc_hi)}}
.g-cc-dim{{stop-color:var(--cc_dim)}}
.g-scatter{{stop-color:var(--scatter)}} .g-sweep{{stop-color:var(--sweep)}}
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


def stack(
    a,
    x: float,
    align: str,
    name: str,
    dt: str,
    hue: str,
    lane_y: float,
    up: bool,
    where: str,
) -> None:
    """ELEMENT 5 — name over date at a marker, on its lane's outboard side.

    `align` is which END of the stack the marker sits at: "start" reads rightwards from it, "end"
    runs back to the left. Stated per stack rather than derived, because the binding neighbour
    differs for each — a formula that got one right got the next one wrong (v1 learned this
    expensively). The stack's width is its NAME's, always the wider of the two rows.
    """
    wid = tw(name, F_M)
    left = (x - 6) if align == "start" else (x + 6 - wid)
    if left < PAD_L or left + wid > PAD_R:
        WARNINGS.append(
            f"  {where}: stack {left:.0f}..{left + wid:.0f} outside {PAD_L}..{PAD_R}"
        )
    ny = lane_y - DY_NAME if up else lane_y + DY_NAME
    dy = lane_y - DY_DATE if up else lane_y + DY_DATE
    a(f'<text class="t-m" x="{left:.1f}" y="{ny:.0f}">{esc(name)}</text>')
    a(f'<text class="t-s c-{hue}" x="{left:.1f}" y="{dy:.0f}">{esc(dt)}</text>')
    return left, left + wid


def build() -> str:
    o: list[str] = []
    a = o.append

    a(f'<rect class="sky" x="0" y="0" width="{W}" height="{H}" rx="16"/>')
    a(
        f'<g class="sweep" style="--d:0s"><rect class="sweepfill" x="-{SWEEP_W}" y="0" '
        f'width="{SWEEP_W}" height="{H}"/></g>'
    )

    starts = month_starts()
    a("<g>")
    for d in starts:
        if d > D0:
            a(
                f'<line class="grid" x1="{x_of(d):.1f}" y1="100" x2="{x_of(d):.1f}" y2="{HORIZON}"/>'
            )
    a("</g>")

    # ── 6. GROUND ─────────────────────────────────────────────────────────────────────────────
    # Scatter first and FULL-BLEED — clipped to the plot it would show two hard vertical edges at
    # full opacity down at the horizon, which reads as a grey box. Atmosphere has no left edge.
    a(
        f'<rect class="scatter" x="0" y="{HORIZON - TERRAIN_H - 40}" width="{W}" '
        f'height="{TERRAIN_H + 40}"/>'
    )
    pts = [f"M {PAD_L} {HORIZON}"]
    for i, v in enumerate(COMMITS_7D):
        x1, x2 = PAD_L + i * PPD, min(PAD_L + (i + 1) * PPD, PAD_R)
        pts.append(f"L {x1:.1f} {ridge_y(v):.1f} L {x2:.1f} {ridge_y(v):.1f}")
    pts.append(f"L {PAD_R} {HORIZON} Z")
    a(f'<path class="ridge" d="{" ".join(pts)}"/>')
    # The lit edge is the PROFILE only; reusing the closed fill path strokes a vertical line up the
    # left margin, where the series is zero and no ridge exists.
    a(f'<path class="ridge-edge" d="{"M" + " ".join(pts[1:-1])[1:]}"/>')
    a(
        f'<line class="horizon" x1="{PAD_L}" y1="{HORIZON}" x2="{PAD_R}" y2="{HORIZON}"/>'
    )
    a("<g>")
    for i, d in enumerate(starts):
        nxt = min(starts[i + 1], D1) if i + 1 < len(starts) else D1
        mid = (x_of(d) + x_of(nxt)) / 2
        lbl = d.strftime("%b") + (" ’26" if i == 0 else "")
        a(
            f'<text class="t-s3" x="{mid:.1f}" y="{MONTH_Y}" text-anchor="middle">{esc(lbl)}</text>'
        )
    a("</g>")
    cap = f"this repo's own commits · 7-day trailing · peak {RIDGE_PEAK:,}/wk"
    a(f'<text class="t-s3" x="{PAD_L}" y="{CAP_Y}">{esc(cap)}</text>')
    # The caption must die inside the flat left end of its own series, or it is text over terrain.
    flat_to = PAD_L + next(i for i, v in enumerate(COMMITS_7D) if v > 12) * PPD
    if PAD_L + tw(cap, F_S) > flat_to:
        WARNINGS.append(f"  ridge caption overruns the flat end at {flat_to:.0f}")

    # ── 1. LANE ───────────────────────────────────────────────────────────────────────────────
    a(
        f'<line class="lane lane-rep" x1="{PAD_L}" y1="{LANE_REPO}" x2="{PAD_R}" y2="{LANE_REPO}"/>'
    )
    a(
        f'<line class="lane lane-cc" x1="{PAD_L}" y1="{LANE_CC}" x2="{PAD_R}" y2="{LANE_CC}"/>'
    )
    a(
        f'<text class="t-lane c-rep" x="{PAD_L}" y="{LANE_REPO - DY_DATE:.0f}">THIS REPO</text>'
    )
    a(
        f'<text class="t-lane c-cc" x="{PAD_L}" y="{LANE_CC + DY_DATE:.0f}">CLAUDE CODE</text>'
    )

    # ── 3. DROP + 4. CHIP ─────────────────────────────────────────────────────────────────────
    for i, p in enumerate(PAIRS):
        ox, tx = p["ox"], p["tx"]
        d = (
            f"M {ox:.1f} {LANE_REPO + 15} C {ox:.1f} {DROP_MID:.0f} "
            f"{tx:.1f} {DROP_MID:.0f} {tx:.1f} {LANE_CC - 17}"
        )
        a(f'<path class="drop" d="{d}"/>')
        a(f'<path class="drop-hi" d="{d}"/>')
        a(f'<path class="flow flow-{"a" if i == 0 else "b"}" d="{d}" style="--d:0s"/>')
        a(
            f'<polygon class="drop-head" points="{tx:.1f},{LANE_CC - 12} '
            f'{tx - 6:.1f},{LANE_CC - 25} {tx + 6:.1f},{LANE_CC - 25}"/>'
        )
        # The cubic's midpoint is exactly ((ox+tx)/2, DROP_MID) for these control points, so the
        # chip rides its own drop by construction rather than by a tuned offset.
        n, unit = str(p["lead"]), "DAYS"
        wn, wu = tw(n, F_L), tw(unit, F_S, 2.4)
        inner = wn + 10 + wu
        cw, ch = inner + 36, 46
        cx = (ox + tx) / 2
        a(
            f'<rect class="chip" x="{cx - cw / 2:.1f}" y="{DROP_MID - ch / 2:.0f}" '
            f'width="{cw:.1f}" height="{ch}" rx="{ch / 2}"/>'
        )
        a(
            f'<text class="t-l" x="{cx - inner / 2:.1f}" y="{DROP_MID + 11:.0f}">{n}</text>'
        )
        a(
            f'<text class="t-lu" x="{cx - inner / 2 + wn + 10:.1f}" '
            f'y="{DROP_MID + 11:.0f}">{unit}</text>'
        )

    # ── 2. MARKER + 5. STACK ──────────────────────────────────────────────────────────────────
    for p in PAIRS:
        for x, hue, lane_y in ((p["ox"], "rep", LANE_REPO), (p["tx"], "cc", LANE_CC)):
            a(f'<g transform="translate({x:.1f},{lane_y})">')
            a(f'<circle class="halo halo-{hue}" r="15"/>')
            if hue == "rep":
                a('<circle class="mk-rep" r="10"/>')
                a('<circle class="mk-spec" cx="-3" cy="-3.6" r="2.4"/>')
                a(f'<circle class="ig ig-rep" r="12.5" style="{phase_for(x)}"/>')
            else:
                a('<circle class="mk-cc" r="8.5"/>')
                a(f'<circle class="ig ig-cc" r="12" style="{phase_for(x)}"/>')
            a("</g>")
        stack(
            a,
            p["ox"],
            p["ours_at"],
            p["ours_name"],
            p["ours"].isoformat(),
            "rep",
            LANE_REPO,
            True,
            f"{p['key']} ours",
        )
        stack(
            a,
            p["tx"],
            p["theirs_at"],
            p["theirs_name"],
            p["theirs"].isoformat(),
            "cc",
            LANE_CC,
            False,
            f"{p['key']} theirs",
        )

    # ── header ────────────────────────────────────────────────────────────────────────────────
    a(f'<text class="t-kick" x="{PAD_L}" y="46">HERE FIRST · TWICE</text>')
    key = (
        "Each drop runs from a capability running here to the release that shipped it."
    )
    a(f'<text class="t-s" x="{PAD_L}" y="82">{esc(key)}</text>')

    a(
        f'<rect class="edge" x=".75" y=".75" width="{W - 1.5}" height="{H - 1.5}" rx="16"/>'
    )
    a(f'<path class="edgehi" d="M 17 1.5 H {W - 17} A 15.5 15.5 0 0 1 {W - 1.5} 17"/>')
    return "\n".join(o)


TITLE = "Twice, this repo shipped it first"

ALT = (
    "A dusk-toned two-lane timeline on one time axis running from May to August 2026. The upper "
    "lane is this repo, in green; the lower lane is Claude Code, in blue; both span the full "
    "width. On each lane a marker sits at its true date — a filled disc on this repo's lane, a "
    "ring on Claude Code's — with the capability or release name above the upper lane and below "
    "the lower one, so the two never overlap. From each of this repo's markers a green curve drops "
    "to the Claude Code release that shipped the same capability, and rides a chip giving the lead "
    "in days. "
    "The first drop: a research team that attacks its own findings, running here on 2026-05-24, to "
    "Dynamic Workflows 2.1.154 on 2026-05-28 — 4 days. The second: two-way session messaging, "
    "running here on 2026-07-10, to Claude Code 2.1.224 on 2026-08-07 — 28 days. "
    "Below both lanes, drawn as an amber stepped ridge rising out of the horizon, is this repo's "
    "own commit volume over the same period — 7-day trailing, peaking at 1,024 commits in a week. "
    "Both drops begin over the flat and first-rising parts of that ridge, before its climb. "
    "A soft column of light crosses the chart from left to right once every 24 seconds, lighting "
    "each of the four markers as it passes, in date order."
)

DESC = (
    "Two lanes on one time axis, May to August 2026 — this repo above in green, Claude Code below "
    "in blue — over an amber ridge of this repo's own commit volume. A green curve drops from each "
    "capability running here to the Claude Code release that shipped it, carrying the lead: 4 days "
    "and 28 days. A light column crosses left to right once every 24 seconds, igniting each marker "
    "in date order."
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
            if (path.read_text() if path.exists() else None) != svg:
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
            "layout warnings (estimates — confirm on the screenshot):", file=sys.stderr
        )
        for w in dict.fromkeys(WARNINGS):
            print(w, file=sys.stderr)

    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
