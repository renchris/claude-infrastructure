#!/usr/bin/env python3
"""gen.py — the README convergence timeline, emitted as two GitHub-safe animated SVGs.

    python3 tools/timeline/gen.py           # writes assets/diagrams/convergence-timeline-{dark,light}.svg
    python3 tools/timeline/gen.py --check   # exit 1 if either file on disk differs from a fresh render

WHY THIS IS HAND-BUILT AND NOT MERMAID. `beautiful-mermaid` 1.1.3 renders flowchart / stateDiagram /
xychart only. There is no timeline primitive, no control over node geometry, no gradients, no motion —
so a chronology can only come out as a chain of boxes, which is what the two landed iterations were
(`6c4c86d7`, `7691cd44`) and why both were rejected on design. The mermaid source stays as the
interactive fallback; this is the shipped picture.

THE DESIGN ARGUMENT, because it is the reason this beats the chain it replaces:

  1. TWO LANES, NOT ONE CHAIN. The section's claim is about *two parties inventing the same thing
     independently*. A single chain throws that away — it can only say "then, then, then". Two lanes
     with time on the x-axis say it structurally: the distance between a repo marker and its Claude
     Code twin IS the lead, drawn to scale.
  2. THE AXIS BREAK IS SEMANTIC, NOT COSMETIC. A linear axis over 529 days puts every interesting
     event in the right 15% (four of them inside 152 px) — unlabellable. So the axis breaks exactly
     once, at 2026-03-24, this repo's first commit. Left of the break is Claude Code alone; right of
     it is both lanes. The break is the repo's birth, so the compression is the story rather than a
     concession to it. The month gridlines are drawn at both scales and their density change is the
     honest disclosure — 27 px/month on the left, 194 px/month on the right.
  3. THE GAPS ARE TO SCALE WITHIN THE ACT. 4 days = 26 px, 28 days = 179 px, and the 7-month lag we
     owe runs 845 px across the break. The reader sees 7x and 33x without reading a number.
  4. DIRECTION ENCODES OWNERSHIP. Both leads run repo lane -> Claude Code lane, downward. The one
     gap that is ours runs the other way, upward, in orange, from a 2025-12 Claude Code release to
     the 2026-07 commit where we finally read it.

MOTION BUDGET (prior-art.md §B6: ~5 sub-threshold motions on separate layers, exactly one legible).
The legible one is the sweep — a light column crossing left to right over the master period, igniting
each marker as it passes. It *enacts* chronology, which is the only justification the survey grants
for animating a README asset at all ("the animation earns its place by explaining, not decorating").
The other four — two lane flows, the orange march, the bloom — are individually below threshold.

HARNESS CONTRACT. `scripts/banner-shots.sh --lint` is what keeps the deterministic freeze exact, and
it constrains authoring in two ways this file obeys everywhere:
  * ONE animation per element. Anything needing two motions is split across a wrapper and a child.
  * NO literal `animation-delay`. Phase rides the additive channel `calc(var(--d,0s) + var(--fz,0s))`
    with the per-element offset in `--d`, which is the only spelling the freeze can seek.
Every sub-period divides P so `banner-verify`'s SEAM check (t=0 == t=P) holds.

WHY EACH FILE CARRIES BOTH PALETTES. The README picks the file through `<picture>` +
`prefers-color-scheme`, which is GitHub's documented pattern and what every other diagram here uses.
But an SVG in `<img>` also resolves `prefers-color-scheme` itself (through the embedding element's
used `color-scheme`), so a file with ONE baked palette is wrong in exactly the case where the two
mechanisms disagree. So both files carry both palettes and differ only in the default: -dark.svg
defaults dark and overrides to light, -light.svg the reverse. Whichever mechanism wins, the reader
gets the right look — and it is also what makes `banner-verify`'s THEMES check (dark != light)
meaningful rather than a check the asset structurally cannot pass.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
from datetime import date

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "diagrams"
STEM = "convergence-timeline"

# ── canvas ────────────────────────────────────────────────────────────────────────────────────
# 1400 wide against GitHub's measured 838 px README column (scripts/banner-column-width.py) is a
# 0.599 scale, so the 26 px title reads at ~15.6 px — a touch above GitHub's own small text. Width
# is spent on the axis; every label fits on one row per stagger without abbreviation.
W, H = 1400, 640

PAD_L, PAD_R = 70, 1330  # plot extent
BREAK_A, BREAK_B = 420, 462  # the axis break band; ACT II starts at its right edge

LANE_TOP = 264  # this repo
LANE_BOT = 426  # Claude Code

# Label rows. NEAR is the row adjacent to its lane, FAR the outer one; events alternate between them
# so a leader line never crosses a neighbour's text.
ROW_U_FAR, ROW_U_NEAR = 74, 156  # above LANE_TOP
ROW_L_NEAR, ROW_L_FAR = 442, 524  # below LANE_BOT
BLOCK_H = 76

MONTH_Y = 612  # baseline of the month scale strip

# ── chronology (settled; docs/plans/README_TIMELINE_AND_IDLE_RECYCLE.md § Track A) ────────────
D_START = date(2025, 2, 24)  # Claude Code 0.2.6 — first npm publish
D_BREAK = date(2026, 3, 24)  # this repo's first commit (aa391e46)
D_END = date(2026, 8, 7)  # Claude Code 2.1.224

ACT1_DAYS = (D_BREAK - D_START).days  # 393
ACT2_DAYS = (D_END - D_BREAK).days  # 136
ACT1_PPD = (BREAK_A - PAD_L) / ACT1_DAYS
ACT2_PPD = (PAD_R - BREAK_B) / ACT2_DAYS


def x_of(d: date) -> float:
    """Map a date to an x. Linear within each act; the single break is at this repo's first commit."""
    if d <= D_BREAK:
        return PAD_L + (d - D_START).days * ACT1_PPD
    return BREAK_B + (d - D_BREAK).days * ACT2_PPD


# ── palettes ──────────────────────────────────────────────────────────────────────────────────
DARK = dict(
    plate_a="#111823",
    plate_b="#0a0e15",
    edge="#222b3a",
    edge_hi="#ffffff",
    edge_hi_o="0.05",
    grid="#1d2736",
    grid_o="1",
    ink="#e9eff6",
    ink2="#98a5b5",
    ink3="#6a7686",
    rep="#3fb950",
    rep_hi="#6ee787",
    rep_dim="#1c4527",
    cc="#4b93e6",
    cc_hi="#8cc8ff",
    cc_dim="#173453",
    gap="#e0813c",
    gap_hi="#f7b17a",
    gap_dim="#48280f",
    chip_a="#16241a",
    chip_b="#0f1a13",
    bloom_a="#2ea043",
    bloom_b="#1f6feb",
    bloom_o="0.16",
    sweep="#a8d0ff",
    sweep_o="0.10",
    halo_o="0.40",
    glow_o="0.24",
    core="#0a0e15",
)

LIGHT = dict(
    plate_a="#ffffff",
    plate_b="#f2f6fb",
    edge="#d6dee8",
    edge_hi="#ffffff",
    edge_hi_o="0.85",
    grid="#e7edf4",
    grid_o="1",
    ink="#0d1319",
    ink2="#54606e",
    ink3="#7d8794",
    rep="#1a7f37",
    rep_hi="#2da44e",
    rep_dim="#63b87a",
    cc="#0969da",
    cc_hi="#218bff",
    cc_dim="#7fb6ee",
    gap="#bc4c00",
    gap_hi="#e16f24",
    gap_dim="#f6cfa8",
    chip_a="#e9f7ed",
    chip_b="#dcf1e3",
    bloom_a="#2da44e",
    bloom_b="#0969da",
    bloom_o="0.07",
    sweep="#1f4e8c",
    sweep_o="0.055",
    halo_o="0.20",
    glow_o="0.16",
    core="#ffffff",
)

SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif'
MONO = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace'

P = 24  # master period, seconds. Every sub-period below divides it, so t=0 == t=P.


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


def fits(
    s: str,
    budget: float,
    size: float,
    weight: int = 400,
    tracking: float = 0.0,
    mono: bool = False,
    where: str = "",
) -> str:
    got = tw(s, size, weight, tracking, mono)
    if got > budget:
        WARNINGS.append(f"  {where}: {got:.0f}px > {budget:.0f}px budget — {s!r}")
    return s


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ── events ────────────────────────────────────────────────────────────────────────────────────
# lane: "repo" (upper) | "cc" (lower).  kind drives the marker glyph and colour.
#   win    — the capability was running here first (repo lane)
#   caught — the Claude Code release that arrived after it (cc lane)
#   base   — context, neither a lead nor a lag
#   late   — the one we were behind on (repo lane, orange)
# `tx` is the text anchor x and `budget` the width the block may occupy before it hits its
# neighbour's text or a leader line dropping through its row. Both are explicit rather than derived,
# because the constraint on each block is a DIFFERENT neighbour — a formula that got one right got
# the next one wrong. `fits()` asserts the copy against the budget at build time.
EVENTS = [
    dict(
        key="cc026",
        lane="cc",
        kind="base",
        d=date(2025, 2, 24),
        title="Claude Code 0.2.6",
        sub="first npm publish",
        row="far",
        align="start",
        tx=83,
        budget=790,
    ),
    dict(
        key="cc2070",
        lane="cc",
        kind="base",
        d=date(2025, 12, 15),
        title="Claude Code 2.0.70",
        sub="status-line context fields exist",
        row="near",
        align="start",
        tx=345,
        budget=520,
    ),
    dict(
        key="first",
        lane="repo",
        kind="base",
        d=date(2026, 3, 24),
        title="this repo's first commit",
        sub="aa391e46",
        row="far",
        align="start",
        tx=475,
        budget=375,
    ),
    dict(
        key="advers",
        lane="repo",
        kind="win",
        d=date(2026, 5, 24),
        title="adversarial research team",
        sub="briefed to attack its own findings",
        row="near",
        align="end",
        tx=838,
        budget=368,
    ),
    dict(
        key="dynwf",
        lane="cc",
        kind="caught",
        d=date(2026, 5, 28),
        title="Dynamic Workflows 2.1.154",
        sub="the same idea, independently",
        row="far",
        align="start",
        tx=890,
        budget=430,
    ),
    dict(
        key="peer",
        lane="repo",
        kind="win",
        d=date(2026, 7, 10),
        title="peer session messaging",
        sub="open, brief and retire peers",
        row="far",
        align="end",
        tx=PAD_R,
        budget=468,
    ),
    # No label block: this one is named on the orange path, where the seven months it belongs to are.
    dict(
        key="lateread",
        lane="repo",
        kind="late",
        d=date(2026, 7, 14),
        title=None,
        sub=None,
        row=None,
        align=None,
        tx=0,
        budget=0,
    ),
    dict(
        key="cc2224",
        lane="cc",
        kind="caught",
        d=date(2026, 8, 7),
        title="Claude Code 2.1.224",
        sub="sessions message each other",
        row="near",
        align="end",
        tx=PAD_R - 13,
        budget=430,
    ),
]
EV = {e["key"]: e for e in EVENTS}
for _e in EVENTS:
    _e["x"] = x_of(_e["d"])
    _e["y"] = LANE_TOP if _e["lane"] == "repo" else LANE_BOT
# 2026-07-14 is 4 days after 2026-07-10 — 25 px at this scale, which is the truth and also a
# collision. Drop it off the lane onto a short stem rather than move it along the axis: an
# annotation hanging below the lane stays honest about WHEN, and stops being a smudge on the win.
EV["lateread"]["y"] = LANE_TOP + 30

# The two leads and the one lag, as (from, to) event keys.
LEADS = [("advers", "dynwf"), ("peer", "cc2224")]
LAG = ("cc2070", "lateread")


def days(a: str, b: str) -> int:
    return (EV[b]["d"] - EV[a]["d"]).days


# ── stylesheet ────────────────────────────────────────────────────────────────────────────────
def palette_vars(p: dict) -> str:
    return "".join(f"--{k}:{v};" for k, v in p.items())


def stylesheet(default: dict, override: dict, override_scheme: str) -> str:
    return f"""
:root{{{palette_vars(default)}}}
@media (prefers-color-scheme: {override_scheme}){{:root{{{palette_vars(override)}}}}}

text{{font-family:{SANS};dominant-baseline:auto}}
.mono{{font-family:{MONO}}}
.ink{{fill:var(--ink)}} .ink2{{fill:var(--ink2)}} .ink3{{fill:var(--ink3)}}
.t-date{{font-size:19px;letter-spacing:.6px;fill:var(--ink3)}}
.t-title{{font-size:26px;font-weight:600;fill:var(--ink)}}
.t-sub{{font-size:20px;fill:var(--ink2)}}
.t-kicker{{font-size:18px;font-weight:600;letter-spacing:2.4px;fill:var(--ink3)}}
.t-lane{{font-size:17px;font-weight:700;letter-spacing:2.6px}}
.t-month{{font-size:16px;letter-spacing:.4px;fill:var(--ink3)}}
.t-legend{{font-size:18px;fill:var(--ink2)}}
.t-chip{{font-size:25px;font-weight:700}}
.t-chip-s{{font-size:16px;font-weight:600;letter-spacing:1.6px}}
.t-gap{{font-size:21px}}
.t-gap-s{{font-size:19px}}
.t-note{{font-size:20px;fill:var(--ink3)}}
.c-rep{{fill:var(--rep)}} .c-cc{{fill:var(--cc)}} .c-gap{{fill:var(--gap)}}
.c-rep-hi{{fill:var(--rep_hi)}} .c-gap-hi{{fill:var(--gap_hi)}}

.plate{{fill:url(#plate)}}
.edge{{fill:none;stroke:var(--edge);stroke-width:1.5}}
.edgehi{{fill:none;stroke:var(--edge_hi);stroke-width:1.5;opacity:var(--edge_hi_o)}}
.grid{{stroke:var(--grid);stroke-width:1;opacity:var(--grid_o)}}
.gridq{{stroke:var(--grid);stroke-width:1.5;opacity:var(--grid_o)}}
.breakcut{{stroke:var(--edge);stroke-width:2;stroke-linecap:round;opacity:.9}}

.lane-glow{{fill:none;stroke-width:11;stroke-linecap:round;opacity:var(--glow_o)}}
.lane-core{{fill:none;stroke-width:3;stroke-linecap:round}}
.lane-rep-glow{{stroke:var(--rep)}} .lane-rep-core{{stroke:url(#laneRep)}}
.lane-cc-glow{{stroke:var(--cc)}}   .lane-cc-core{{stroke:url(#laneCc)}}
.lane-dash{{fill:none;stroke-width:3;stroke-linecap:butt;opacity:.85}}
.lane-dash-rep{{stroke:var(--rep_hi)}} .lane-dash-cc{{stroke:var(--cc_hi)}}
.lane-cap{{stroke-width:3;stroke-linecap:round}}
.ghost{{stroke:var(--rep);stroke-width:2;stroke-dasharray:2 12;stroke-linecap:round;opacity:.3}}

.case{{fill:none;stroke:url(#plateStroke);stroke-width:9;stroke-linecap:round}}
.lead{{fill:none;stroke:var(--rep);stroke-width:3.2;stroke-linecap:round}}
.lead-hi{{fill:none;stroke:var(--rep_hi);stroke-width:1.2;stroke-linecap:round;opacity:.75}}
.lag{{fill:none;stroke:var(--gap);stroke-width:2.6;stroke-linecap:round;
      stroke-dasharray:11 9;opacity:.95}}
.lag-soft{{fill:none;stroke:var(--gap);stroke-width:10;stroke-linecap:round;opacity:var(--glow_o)}}
.arrow-rep{{fill:var(--rep)}} .arrow-gap{{fill:var(--gap)}}

.halo{{opacity:var(--halo_o)}}
.halo-rep{{fill:url(#haloRep)}} .halo-cc{{fill:url(#haloCc)}} .halo-gap{{fill:url(#haloGap)}}
.mk-core{{fill:var(--core)}}
.mk-rep{{fill:var(--rep)}} .mk-cc{{fill:var(--cc)}}
.mk-ring-rep{{fill:none;stroke:var(--rep);stroke-width:3}}
.mk-ring-cc{{fill:none;stroke:var(--cc);stroke-width:3}}
.mk-ring-gap{{fill:none;stroke:var(--gap);stroke-width:2.6;stroke-dasharray:3.4 3.2}}
.mk-dot{{fill:var(--core)}}
.mk-spec{{fill:#ffffff;opacity:.5}}
.stem{{stroke:var(--gap);stroke-width:2;opacity:.8;stroke-linecap:round}}
.leader{{stroke-width:1.4;opacity:.55;stroke-linecap:round}}
.leader-rep{{stroke:var(--rep)}} .leader-cc{{stroke:var(--cc)}}

.chip-bg{{fill:url(#chip);stroke:var(--rep);stroke-width:1.4}}
.chip-glow{{fill:var(--rep);opacity:var(--glow_o)}}

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
  10%{{opacity:0;transform:scale(3.1)}}
  100%{{opacity:0;transform:scale(1)}}}}
.ig{{fill:none;stroke-width:2.4;transform-box:fill-box;transform-origin:50% 50%;opacity:0;
     animation:ignite {P}s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}
.ig-rep{{stroke:var(--rep_hi)}} .ig-cc{{stroke:var(--cc_hi)}} .ig-gap{{stroke:var(--gap_hi)}}

@keyframes flow{{from{{stroke-dashoffset:0}}to{{stroke-dashoffset:-96px}}}}
.flow-a{{stroke-dasharray:14 82;animation:flow 12s linear infinite;
         animation-delay:calc(var(--d,0s) + var(--fz,0s))}}
.flow-b{{stroke-dasharray:14 82;animation:flow 8s linear infinite;
         animation-delay:calc(var(--d,0s) + var(--fz,0s))}}

@keyframes march{{from{{stroke-dashoffset:0}}to{{stroke-dashoffset:-120px}}}}
.lag{{animation:march {P}s linear infinite;animation-delay:calc(var(--d,0s) + var(--fz,0s))}}

@keyframes breathe{{0%{{opacity:var(--bloom_o)}}50%{{opacity:calc(var(--bloom_o) * 1.85)}}
                    100%{{opacity:var(--bloom_o)}}}}
.bloom{{fill:url(#bloom);animation:breathe {P}s ease-in-out infinite;
        animation-delay:calc(var(--d,0s) + var(--fz,0s))}}
.bloom-still{{fill:url(#bloom2);opacity:calc(var(--bloom_o) * 0.8)}}

@media (prefers-reduced-motion: reduce){{*{{animation:none !important}}}}
"""


# ── defs ──────────────────────────────────────────────────────────────────────────────────────
def defs(p_default: dict) -> str:
    # Gradient stops carry their colour through a class so the palette override reaches them; a
    # `stop-color="var(...)"` presentation attribute is not reliably resolved.
    return f"""<defs>
<linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-plate-a"/><stop offset="1" class="g-plate-b"/></linearGradient>
<linearGradient id="plateStroke" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-plate-a"/><stop offset="1" class="g-plate-b"/></linearGradient>
<linearGradient id="chip" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-chip-a"/><stop offset="1" class="g-chip-b"/></linearGradient>
<linearGradient id="laneRep" x1="{BREAK_B}" y1="0" x2="{PAD_R}" y2="0" gradientUnits="userSpaceOnUse">
  <stop offset="0" class="g-rep-dim"/><stop offset=".45" class="g-rep"/>
  <stop offset="1" class="g-rep-hi"/></linearGradient>
<linearGradient id="laneCc" x1="{PAD_L}" y1="0" x2="{PAD_R}" y2="0" gradientUnits="userSpaceOnUse">
  <stop offset="0" class="g-cc-dim"/><stop offset=".5" class="g-cc"/>
  <stop offset="1" class="g-cc-hi"/></linearGradient>
<radialGradient id="haloRep"><stop offset="0" class="g-rep" stop-opacity=".85"/>
  <stop offset="1" class="g-rep" stop-opacity="0"/></radialGradient>
<radialGradient id="haloCc"><stop offset="0" class="g-cc" stop-opacity=".85"/>
  <stop offset="1" class="g-cc" stop-opacity="0"/></radialGradient>
<radialGradient id="haloGap"><stop offset="0" class="g-gap" stop-opacity=".85"/>
  <stop offset="1" class="g-gap" stop-opacity="0"/></radialGradient>
<radialGradient id="bloom" cx=".5" cy=".5" r=".5">
  <stop offset="0" class="g-bloom-a" stop-opacity=".9"/>
  <stop offset=".55" class="g-bloom-a" stop-opacity=".3"/>
  <stop offset="1" class="g-bloom-a" stop-opacity="0"/></radialGradient>
<radialGradient id="bloom2" cx=".5" cy=".5" r=".5">
  <stop offset="0" class="g-bloom-b" stop-opacity=".8"/>
  <stop offset=".55" class="g-bloom-b" stop-opacity=".26"/>
  <stop offset="1" class="g-bloom-b" stop-opacity="0"/></radialGradient>
<linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" class="g-sweep" stop-opacity="0"/>
  <stop offset=".62" class="g-sweep" stop-opacity=".55"/>
  <stop offset=".88" class="g-sweep" stop-opacity="1"/>
  <stop offset="1" class="g-sweep" stop-opacity="0"/></linearGradient>
</defs>
<style>
.g-plate-a{{stop-color:var(--plate_a)}} .g-plate-b{{stop-color:var(--plate_b)}}
.g-chip-a{{stop-color:var(--chip_a)}} .g-chip-b{{stop-color:var(--chip_b)}}
.g-rep{{stop-color:var(--rep)}} .g-rep-hi{{stop-color:var(--rep_hi)}}
.g-rep-dim{{stop-color:var(--rep_dim)}}
.g-cc{{stop-color:var(--cc)}} .g-cc-hi{{stop-color:var(--cc_hi)}} .g-cc-dim{{stop-color:var(--cc_dim)}}
.g-gap{{stop-color:var(--gap)}}
.g-bloom-a{{stop-color:var(--bloom_a)}} .g-bloom-b{{stop-color:var(--bloom_b)}}
.g-sweep{{stop-color:var(--sweep)}}
</style>"""


# ── drawing ───────────────────────────────────────────────────────────────────────────────────
SWEEP_W = 340  # the light column's width
SWEEP_TRAVEL = (
    W + SWEEP_W
)  # it starts fully off-canvas left and ends fully off-canvas right
SWEEP_EDGE = SWEEP_W * (1 - 0.88)  # the bright stop sits at 88% across the column
IGNITE_PEAK = 0.02 * P  # the ignite keyframe reaches full opacity at 2%


def phase_for(x: float) -> str:
    """The --d that makes a marker peak exactly as the sweep's bright edge crosses it.

    Derived, not tuned. The column's leading bright edge is at `SWEEP_TRAVEL * t / P - SWEEP_EDGE`,
    so it reaches x at t_fire; the element's own animation clock is `t - delay`, and we want that to
    equal IGNITE_PEAK at t_fire. Subtracting one whole period keeps the value negative, which is
    what the freeze's additive seek expects.

    (The first spelling of this was a bare `-(x + 250) / travel * P`, which ignored both the peak
    offset and the sign convention. It looked plausible and was wrong by ~11 s: every marker lit
    while the sweep was somewhere else entirely, and the t=6 reference frame showed a marker at
    2026-07-10 mid-flash with the light column still off at the far left.)
    """
    t_fire = (x + SWEEP_EDGE) * P / SWEEP_TRAVEL
    return f"--d:{t_fire - IGNITE_PEAK - P:.3f}s"


def month_ticks() -> list[tuple[date, bool]]:
    out = []
    y, m = D_START.year, D_START.month + 1
    while True:
        if m > 12:
            y, m = y + 1, 1
        d = date(y, m, 1)
        if d > D_END:
            break
        # A label every 3rd month in the compressed act, every month in the expanded one — and
        # never inside the break band, where it would collide with its neighbour across the cut.
        labelled = (d > D_BREAK) or (d.month % 3 == 0)
        if BREAK_A - 46 < x_of(d) < BREAK_B + 30:
            labelled = False
        out.append((d, labelled))
        m += 1
    return out


def build() -> str:
    o: list[str] = []
    a = o.append

    # ── plate, bloom, sweep ───────────────────────────────────────────────────────────────────
    a(f'<rect class="plate" x="0" y="0" width="{W}" height="{H}" rx="16"/>')
    # Two blooms, warm-ish green under the right where the leads are and cool blue under the left
    # where Claude Code ran alone. Only one breathes; a second animated one would be legible, and
    # the motion budget already has its one legible member.
    a('<ellipse class="bloom-still" cx="300" cy="470" rx="620" ry="330"/>')
    a('<ellipse class="bloom" cx="1060" cy="300" rx="700" ry="390" style="--d:0s"/>')
    # The sweep band is authored fully off-canvas to the left, so the reduced-motion still — and the
    # t=0/t=P seam — show no column at all.
    a(
        f'<g class="sweep" style="--d:0s"><rect class="sweepfill" x="-340" y="0" '
        f'width="340" height="{H}"/></g>'
    )

    # ── month grid ────────────────────────────────────────────────────────────────────────────
    a("<g>")
    for d, labelled in month_ticks():
        x = x_of(d)
        cls = "gridq" if labelled else "grid"
        a(
            f'<line class="{cls}" x1="{x:.1f}" y1="58" x2="{x:.1f}" y2="{MONTH_Y - 22:.0f}"/>'
        )
    a("</g>")

    # month scale strip
    a("<g>")
    first_labelled = True
    for d, labelled in month_ticks():
        if not labelled:
            continue
        x = x_of(d)
        lbl = d.strftime("%b")
        if d.month == 1 or first_labelled:
            lbl += f" ’{d.strftime('%y')}"
        first_labelled = False
        a(
            f'<text class="t-month mono" x="{x:.1f}" y="{MONTH_Y}" text-anchor="middle">'
            f"{esc(lbl)}</text>"
        )
    a("</g>")

    # ── axis break ────────────────────────────────────────────────────────────────────────────
    # No masking band across the gap. It was there to hide gridlines inside the break, but no month
    # boundary falls in that 70 px anyway — so on GitHub light it was a bright white stripe down the
    # chart doing nothing at all. The cut marks on the lane and the gridline density carry it.
    for cx in (BREAK_A + 12, BREAK_A + 26):
        a(
            f'<line class="breakcut" x1="{cx - 9}" y1="{LANE_BOT + 13}" '
            f'x2="{cx + 9}" y2="{LANE_BOT - 13}"/>'
        )
    a(
        f'<text class="t-month" x="{(BREAK_A + BREAK_B) / 2:.0f}" y="{MONTH_Y}" '
        f'text-anchor="middle">break</text>'
    )

    # ── lanes ─────────────────────────────────────────────────────────────────────────────────
    # Claude Code runs the whole width; this repo's lane BEGINS at the break, because that is when
    # it began. The empty upper-left is the 13-month head start, stated by absence.
    for x1, x2, y, key, flow in (
        (BREAK_B, PAD_R, LANE_TOP, "rep", "flow-a"),
        (PAD_L, BREAK_A - 4, LANE_BOT, "cc", "flow-b"),
        (BREAK_B + 4, PAD_R, LANE_BOT, "cc", "flow-b"),
    ):
        a(
            f'<line class="lane-glow lane-{key}-glow" x1="{x1}" y1="{y}" x2="{x2}" y2="{y}"/>'
        )
        a(
            f'<line class="lane-core lane-{key}-core" x1="{x1}" y1="{y}" x2="{x2}" y2="{y}"/>'
        )
        a(
            f'<line class="lane-dash lane-dash-{key} {flow}" x1="{x1}" y1="{y}" x2="{x2}" y2="{y}" '
            f'style="--d:0s"/>'
        )

    # A ghost of the repo lane over the 13 months it did not exist. Absence alone left the top-left
    # quarter of the canvas reading as blank space rather than as a stated fact; a fine dotted rule
    # at the same y says "this lane is not here yet" instead of saying nothing.
    a(
        f'<line class="ghost" x1="{PAD_L}" y1="{LANE_TOP}" x2="{BREAK_A - 10}" y2="{LANE_TOP}"/>'
    )

    # Lane identity, both sitting just above their own lane's left end — consistently placed, and
    # out of the middle band, which the leads and the lag need all of.
    a(
        f'<text class="t-lane c-rep" x="{BREAK_B + 16}" y="{LANE_TOP - 12}">THIS REPO</text>'
    )
    a(f'<text class="t-lane c-cc" x="{PAD_L}" y="{LANE_BOT - 18}">CLAUDE CODE</text>')

    # The head-start note lives in the space the repo lane does not yet occupy — the absence is the
    # point, so the note explains it rather than filling it. It also carries the axis disclosure,
    # because the break and the head start are the same fact.
    for i, line in enumerate(
        (
            "Claude Code ran 13 months",
            "before this repo existed.",
            "The axis breaks there, 7×.",
        )
    ):
        a(f'<text class="t-note" x="{PAD_L}" y="{170 + i * 26}">{esc(line)}</text>')
        fits(line, 320, 20, where="head-start note")

    # ── the lag we owe (drawn first: it is context for the two leads, not a peer of them) ─────
    # It runs LOW and flat for most of its length, hugging the Claude Code lane it belongs to, and
    # only climbs at the very end. That keeps the middle band clear for the two leads — and it draws
    # the shape of the fact: seven months spent down there before this repo caught up.
    lag_a, lag_b = EV[LAG[0]], EV[LAG[1]]
    x0, y0 = lag_a["x"], LANE_BOT - 10
    flat = LANE_BOT - 14
    x1, y1 = lag_b["x"], lag_b["y"] + 20
    lag_d = (
        f"M {x0:.1f} {y0:.1f} C {x0 + 220:.1f} {flat:.1f} {x1 - 430:.1f} {flat:.1f} "
        f"{x1 - 128:.1f} {flat:.1f} C {x1 - 52:.1f} {flat:.1f} {x1:.1f} {y1 + 62:.1f} "
        f"{x1:.1f} {y1:.1f}"
    )
    # No soft under-stroke: at width 10 it read as a brown smear behind the dashes rather than a
    # glow, and worst exactly where the path climbs past the 28-day chip.
    a(f'<path class="lag" d="{lag_d}" style="--d:0s"/>')
    a(
        f'<polygon class="arrow-gap" points="{x1:.1f},{y1 - 10:.1f} {x1 - 6.5:.1f},{y1 + 4:.1f} '
        f'{x1 + 6.5:.1f},{y1 + 4:.1f}"/>'
    )

    # Sits above the flat run, inside the widest empty region on the canvas. Right edge is bounded
    # by where the first lead's connector descends (x ~845).
    lag_lines = (
        ("7 months late", " — our gap, not theirs."),
        (None, "the status-line context fields existed from"),
        (None, "2025-12-15. This repo read them on 2026-07-14."),
    )
    for i, (bold, rest) in enumerate(lag_lines):
        # Sits directly ON TOP of the flat run rather than floating in the middle of the band —
        # at y≈292 the block read as unattached to the orange path it describes.
        y = 344 + i * 24
        if bold:
            a(
                f'<text class="t-gap" x="352" y="{y}">'
                f'<tspan class="c-gap-hi" font-weight="700">{bold}</tspan>'
                f'<tspan class="ink2">{esc(rest)}</tspan></text>'
            )
        else:
            a(f'<text class="t-gap-s ink2" x="352" y="{y}">{esc(rest)}</text>')
        fits((bold or "") + rest, 465, 21 if bold else 19, where=f"lag L{i + 1}")

    # ── the two leads ─────────────────────────────────────────────────────────────────────────
    for src, dst in LEADS:
        s, t = EV[src], EV[dst]
        sx, tx = s["x"], t["x"]
        d = (
            f"M {sx:.1f} {LANE_TOP + 11} C {sx:.1f} {LANE_TOP + 74:.0f} "
            f"{tx:.1f} {LANE_BOT - 78:.0f} {tx:.1f} {LANE_BOT - 13}"
        )
        a(
            f'<path class="case" d="{d}"/>'
        )  # casing: the lead reads above the lag where they cross
        a(f'<path class="lead" d="{d}"/>')
        a(f'<path class="lead-hi" d="{d}"/>')
        a(
            f'<polygon class="arrow-rep" points="{tx:.1f},{LANE_BOT - 3:.1f} '
            f'{tx - 6.5:.1f},{LANE_BOT - 17:.1f} {tx + 6.5:.1f},{LANE_BOT - 17:.1f}"/>'
        )

        # The chip rides low on its own connector, clear of the lag text above it. It is deliberately
        # NOT sized by the day count — the proportion is already carried, to scale, by how far apart
        # the two markers are; a chip that also scaled would double-count it.
        n = days(src, dst)
        label = f"{n} days"
        cx, cy = 908 if n < 10 else 1252, 368
        cw = max(146, tw(label, 25, 700) + 44)
        ch = 60
        a(
            f'<rect class="chip-glow" x="{cx - cw / 2 - 3:.1f}" y="{cy - ch / 2 - 3:.1f}" '
            f'width="{cw + 6:.1f}" height="{ch + 6:.1f}" rx="{(ch + 6) / 2:.1f}"/>'
        )
        a(
            f'<rect class="chip-bg" x="{cx - cw / 2:.1f}" y="{cy - ch / 2:.1f}" width="{cw:.1f}" '
            f'height="{ch:.1f}" rx="{ch / 2:.1f}"/>'
        )
        a(
            f'<text class="t-chip c-rep-hi" x="{cx:.1f}" y="{cy - 2:.0f}" text-anchor="middle">'
            f"{label}</text>"
        )
        a(
            f'<text class="t-chip-s c-rep" x="{cx:.1f}" y="{cy + 20:.0f}" text-anchor="middle">'
            f"LATER</text>"
        )

    # ── markers ───────────────────────────────────────────────────────────────────────────────
    for e in EVENTS:
        x, y, kind, lane = e["x"], e["y"], e["kind"], e["lane"]
        hue = "gap" if kind == "late" else ("rep" if lane == "repo" else "cc")
        if (
            kind == "late"
        ):  # the stem is what keeps the off-lane marker attached to its true date
            a(
                f'<line class="stem" x1="{x:.1f}" y1="{LANE_TOP}" x2="{x:.1f}" y2="{y - 8}"/>'
            )
        a(f'<g transform="translate({x:.1f},{y})">')
        # Halo radius is tight. At r=26 the 2026-07-10 and 2026-07-14 markers — 4 days and 25 px
        # apart, which is the truth — merged into one blob.
        a(
            f'<circle class="halo halo-{hue}" r="{18 if kind in ("win", "caught") else 11}"/>'
        )
        if kind == "late":
            a('<circle class="mk-dot" r="7"/>')
            a('<circle class="mk-ring-gap" r="7"/>')
            a('<circle class="ig ig-gap" r="8.5" style="' + phase_for(x) + '"/>')
        elif kind == "base":
            a(f'<circle class="mk-dot" r="7.5"/>')
            a(f'<circle class="mk-ring-{hue}" r="7.5"/>')
            a(f'<circle class="ig ig-{hue}" r="10" style="{phase_for(x)}"/>')
        else:  # win / caught — the paired events, drawn solid and one step larger
            a(f'<circle class="mk-{hue}" r="10.5"/>')
            a(f'<circle class="mk-dot" r="4"/>')
            a(f'<circle class="mk-spec" cx="-3" cy="-3.4" r="2.1"/>')
            a(f'<circle class="ig ig-{hue}" r="13" style="{phase_for(x)}"/>')
        a("</g>")

    # ── event labels ──────────────────────────────────────────────────────────────────────────
    for e in EVENTS:
        if not e["title"]:
            continue
        x, lane, row, align = e["x"], e["lane"], e["row"], e["align"]
        if lane == "repo":
            top = ROW_U_FAR if row == "far" else ROW_U_NEAR
            leader_y1, leader_y2 = top + BLOCK_H + 4, LANE_TOP - 14
        else:
            top = ROW_L_NEAR if row == "near" else ROW_L_FAR
            leader_y1, leader_y2 = LANE_BOT + 14, top - 6
        hue = "rep" if lane == "repo" else "cc"
        a(
            f'<line class="leader leader-{hue}" x1="{x:.1f}" y1="{leader_y1:.0f}" '
            f'x2="{x:.1f}" y2="{leader_y2:.0f}"/>'
        )

        anchor = "start" if align == "start" else "end"
        tx, budget = e["tx"], e["budget"]
        fits(e["title"], budget, 26, 600, where=f"{e['key']} title")
        fits(e["sub"], budget, 20, where=f"{e['key']} sub")
        a(
            f'<text class="t-date mono" x="{tx:.1f}" y="{top + 18}" text-anchor="{anchor}">'
            f"{e['d'].isoformat()}</text>"
        )
        a(
            f'<text class="t-title" x="{tx:.1f}" y="{top + 48}" text-anchor="{anchor}">'
            f"{esc(e['title'])}</text>"
        )
        a(
            f'<text class="t-sub" x="{tx:.1f}" y="{top + 72}" text-anchor="{anchor}">'
            f"{esc(e['sub'])}</text>"
        )

    # ── header ────────────────────────────────────────────────────────────────────────────────
    a(
        f'<text class="t-kicker" x="{PAD_L}" y="42">SAME WALL, SAME ANSWER, WEEKS APART</text>'
    )
    legend = (
        ("dot", "rep", "this repo"),
        ("dot", "cc", "Claude Code"),
        ("ring", "gap", "our gap"),
    )
    span = sum(15 + tw(t, 18) + 40 for _, _, t in legend) - 40
    lx = PAD_R - span
    for glyph, colour, text in legend:
        if glyph == "dot":
            a(f'<circle class="mk-{colour}" cx="{lx:.0f}" cy="35" r="7"/>')
            a(f'<circle class="mk-dot" cx="{lx:.0f}" cy="35" r="2.6"/>')
        else:
            a(f'<circle class="mk-dot" cx="{lx:.0f}" cy="35" r="6.5"/>')
            a(f'<circle class="mk-ring-gap" cx="{lx:.0f}" cy="35" r="6.5"/>')
        a(f'<text class="t-legend" x="{lx + 15:.0f}" y="41">{text}</text>')
        lx += 15 + tw(text, 18) + 40

    # ── card edge, drawn last so nothing paints over it ───────────────────────────────────────
    a(
        f'<rect class="edge" x=".75" y=".75" width="{W - 1.5}" height="{H - 1.5}" rx="16"/>'
    )
    a(f'<path class="edgehi" d="M 17 1.5 H {W - 17} A 15.5 15.5 0 0 1 {W - 1.5} 17"/>')

    return "\n".join(o)


TITLE = "Twice, this repo shipped it first"

ALT = (
    "A two-lane timeline, time running left to right, comparing when a capability was running in "
    "this repo against when it shipped in Claude Code. The lower lane is Claude Code and spans the "
    "whole chart; the upper lane is this repo and does not begin until 2026-03-24, because that is "
    "this repo's first commit — Claude Code had already run for 13 months. The axis breaks once, at "
    "that first commit: everything left of the break is compressed, everything right of it is drawn "
    "at about seven times the scale, and the month gridlines show both densities. "
    "On the Claude Code lane: 2025-02-24, Claude Code 0.2.6, the first npm publish; 2025-12-15, "
    "Claude Code 2.0.70, in which the status-line context fields first exist; 2026-05-28, Dynamic "
    "Workflows 2.1.154; and 2026-08-07, Claude Code 2.1.224, in which sessions can message each "
    "other. On this repo's lane: 2026-03-24, the first commit; 2026-05-24, an adversarial-role "
    "research team, a share of every wave briefed to attack the rest; 2026-07-10, peer session "
    "messaging; and 2026-07-14, the day this repo finally read the status-line fields. "
    "Two green arrows run downward from this repo's lane to Claude Code's, each labelled with the "
    "lead and drawn to scale: 4 days from the adversarial research team on 2026-05-24 to Dynamic "
    "Workflows on 2026-05-28, and 28 days from peer session messaging on 2026-07-10 to Claude Code "
    "2.1.224 on 2026-08-07. One orange arrow runs the other way, upward from Claude Code 2.0.70 on "
    "2025-12-15 across the axis break to 2026-07-14 — seven months in which the status-line fields "
    "existed and this repo did not read them. That one is this repo's gap, not Claude Code's."
)

DESC = (
    "Two lanes on one time axis. Claude Code's lane spans the chart; this repo's lane begins at the "
    "axis break, which is its first commit. Distance between paired markers is the lead, to scale: "
    "4 days and 28 days downward from this repo to Claude Code, 7 months upward the other way for "
    "the one gap this repo owes. A light sweep crosses left to right once every 24 seconds, igniting "
    "each event as it passes."
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
        f"{defs(default)}\n"
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
