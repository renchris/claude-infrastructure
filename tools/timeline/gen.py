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
THE DESIGN ARGUMENT (v2, 2026-08-12 — a ground-up redesign; v1's argument is preserved at the end
of this docstring, because the reasons v1 was replaced are the reasons v2 is shaped as it is).

  0. THE CHART HAS ONE JOB. Two capabilities were running here before the Claude Code release that
     shipped them. The reader needs three things and nothing else: WHICH capability, HOW LONG the
     lead was, and PROOF (two dates and a version number). Everything that is not one of those
     three is deleted — no head-start apology, no axis-break disclosure, no essay block. What is
     NOT on the chart is as deliberate as what is: see leg 5.

  1. ONE TRACK PER CAPABILITY, ONE SHARED TIME AXIS. Each gets a full-width track: a green disc
     where it was running here, a blue ring at the Claude Code release, and the span between them
     drawn to scale with the lead in a pill on it. Green is left of blue on every track, and that
     repetition IS the claim — the reader gets it before reading a word. A faint rule left of the
     green disc ("neither side yet") and right of the blue ring ("both have it") make each row a
     full-width track, which is what ties a label at x=64 to a marker at x=1132.

  2. NO AXIS BREAK, BECAUSE THE APOLOGY IS GONE. v1 spanned 529 days, which forced a broken axis,
     which forced a paragraph explaining the break, which forced a note explaining the 13-month head
     start. Dropping the self-diminishing content collapses the span to 106 days and a single linear
     axis fits with room to spare — the design problem and the message problem had one solution. At
     12 px/day even the 4-day lead is a 48 px bar rather than v1's 26 px unlabellable smudge.

  3. THE LEAD IS THE HERO, AND IT IS A NUMBER AS WELL AS A DISTANCE. 4 days and 28 days differ by
     7x, so the span carries the proportion and the pill carries the magnitude; each row has both,
     and neither has to do the other's job. 4 days reading as "the same week" is not a weakness of
     the chart — two parties inventing the same thing inside one week is the stronger of the two
     facts, and the pill is what stops a short bar reading as a small win.

  4. OURS ABOVE, THEIRS BELOW — one rule that removes every leader-line crossing. Each marker's date
     block sits in its own horizontal band (green above the rail, blue below it) with a short tick
     from the marker into its band. Two blocks can never collide and a tick can never cross a
     neighbour's text, which is what made v1's four alternating label rows unreadable.

  5. A THIRD ROW — THE STATUS-LINE CONTEXT GAUGE — WAS BUILT AND THEN CUT ON EVIDENCE. Recorded so
     it is not re-added: the operator's 2026-01-16 comment on Claude Code issue #12520 is real
     original work (it reverse-engineers `Tw7` against `uSA` out of `cli.js` and shows the status
     line counts INPUT only while the red warning counts INPUT+OUTPUT against the auto-compact
     limit), but it is NOT a "here first" fact. Three dates settle it, all from primary sources:
       * `context_window.{used_percentage,remaining_percentage}` shipped in 2.1.6 — npm publish
         2026-01-13, CHANGELOG "Added `context_window.used_percentage` and
         `context_window.remaining_percentage` fields to status line input". THREE DAYS BEFORE the
         comment, not after it.
       * the fields the comment actually proposes — `conversation_output_tokens`,
         `effective_remaining_percentage` — have NEVER shipped. #12520 is still open and neither
         name appears anywhere in the CHANGELOG.
       * this repo read `used_percentage` on 2026-07-14 (`1b8d671b1`), ~6 months after 2.1.6. That
         commit cites "CC >=2.1.207" for `context_window_size`, but that is an observation about a
         payload, not a release note: `context_window_size` is in no CHANGELOG entry, and 2.1.207
         carries no status-line context change at all.
     So the honest reading of that row is a LAG — which is what v1 drew, and what
     docs/research/vendor-convergence-2026-08-07.md §1 had already measured. It is off this chart
     because the chart is about capabilities that ran here FIRST, not because omitting it flatters
     us. Do not re-add it as a lead without evidence that beats those three dates.

MOTION BUDGET (prior-art.md §B6: ~5 sub-threshold motions on separate layers, exactly one legible).
The legible one is the time cursor — a light column crossing left to right over the four months,
igniting each marker as it passes, in true chronological order across both tracks. It *enacts*
chronology, which is the only justification the survey grants for animating a README asset at all.
The four ignitions are individually below threshold. The rails are deliberately STATIC: a rail that
reveals with the cursor cannot return to its start value by 100% without a visible reset flash, and
the seam check (t=0 == t=P) is not negotiable.

HARNESS CONTRACT (unchanged from v1 — this is measured, not stylistic). `scripts/banner-shots.sh
--lint` is what keeps the deterministic freeze exact, and it constrains authoring in two ways this
file obeys everywhere:
  * ONE animation per element. Anything needing two motions is split across a wrapper and a child.
  * NO literal `animation-delay`. Phase rides the additive channel `calc(var(--d,0s) + var(--fz,0s))`
    with the per-element offset in `--d`, which is the only spelling the freeze can seek.
Every sub-period divides P, so `banner-verify`'s SEAM check (t=0 == t=P) holds.

WHY EACH FILE CARRIES BOTH PALETTES (unchanged from v1). The README picks the file through
`<picture>` + `prefers-color-scheme`, which is GitHub's documented pattern and what every other
diagram here uses. But an SVG in `<img>` also resolves `prefers-color-scheme` itself (through the
embedding element's used `color-scheme`), so a file with ONE baked palette is wrong in exactly the
case where the two mechanisms disagree. So both files carry both palettes and differ only in the
default: -dark.svg defaults dark and overrides to light, -light.svg the reverse. Whichever mechanism
wins, the reader gets the right look — and it is also what makes `banner-verify`'s THEMES check
(dark != light) meaningful rather than a check the asset structurally cannot pass.

────────────────────────────────────────────────────────────────────────────────────────────────
V1'S DESIGN ARGUMENT, AND WHY EACH LEG WAS REPLACED (kept so the next iteration does not re-derive
a rejected design). v1 was a two-lane chronology: a Claude Code lane spanning 2025-02-24..2026-08-07,
a this-repo lane starting at the 2026-03-24 first commit, connectors between paired events, and one
orange connector running the other way for a lag.
  v1.1 "two lanes, not one chain"  → KEPT IN SPIRIT, changed in form. Two parties still, but paired
       per capability instead of pooled into two long lanes: the pairing is the claim, and a lane
       forces the reader to find its own partner for each marker.
  v1.2 "the axis break is semantic" → DROPPED. It was semantic, and it was still a break: it needed
       a "break" label, a two-density gridline, and a three-line note to be read at all. See leg 2.
  v1.3 "the gaps are to scale"      → KEPT, and now the ONLY thing the geometry claims. v1 also
       scaled a 7-month lag across the break, which spent the widest ink on the one negative.
  v1.4 "direction encodes ownership"→ DROPPED WITH ITS SUBJECT, on SCOPE and not on truth. The
       orange upward path carried "7 months late — our gap, not theirs". Operator ruling
       2026-08-12: this asset exists to state what ran here FIRST, so a lag does not belong on it
       whatever its sign. The lag itself STANDS — leg 5 re-derived it from the CHANGELOG and it
       survived. Two intermediate readings were tried while writing v2 and BOTH were wrong, which
       is why leg 5 spells out its sources: (a) that the repo never had the gap, because its first
       commit already read `remaining_percentage` — false, that field arrived in the SAME 2.1.6
       release as the `used_percentage` it then ignored for six months; and (b) that
       `used_percentage` shipped in 2.1.207 on 2026-07-10, four days before this repo adopted it —
       false, that came from reading a commit MESSAGE ("CC >=2.1.207") as a release note. The
       lesson is v1's own, one level up: date a capability from a primary source on BOTH sides, and
       this repo's commit prose is not a primary source for the vendor's side.
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
# 0.599 scale, so the 26 px row title reads at ~15.6 px — a touch above GitHub's own small text.
W, H = 1400, 524

PAD_L, PAD_R = (
    64,
    1336,
)  # plot extent; also the text margins, so everything shares one grid

# Row rhythm. Each track is name / ours-band / rail / theirs-band, and the two bands are what let a
# marker's date block never collide with its neighbour's (design leg 4). The 180 px pitch is set by
# the ONE gap that has to be unambiguous: a blue date block must not read as belonging to the bold
# capability name below it, so below-band → next name is held at 58 px, wider than name → own band.
ROW_Y = (216, 396)  # the rail of each track
DY_NAME = -76  # capability name baseline, relative to the rail
DY_ABOVE = -38  # "running here" band  (green)
DY_BELOW = 46  # "shipped in Claude Code" band (blue)

MONTH_Y = 494  # baseline of the month scale strip
GRID_TOP, GRID_BOT = 104, 472

# ── chronology ────────────────────────────────────────────────────────────────────────────────
# Every date below is verified against a primary source, not against this repo's own prose:
#   Claude Code releases  npm `@anthropic-ai/claude-code` publish times
#   this repo's dates     the commit or the public artefact named in the row
D0 = date(2026, 5, 10)  # axis start — a fortnight before the first event
D1 = date(
    2026, 8, 24
)  # axis end   — far enough past the last that its block has a margin
SPAN = (D1 - D0).days  # 106
PPD = (PAD_R - PAD_L) / SPAN  # 12.0 px/day


def x_of(d: date) -> float:
    """Map a date to an x. One linear act — no break, because nothing needs one (design leg 2)."""
    return PAD_L + (d - D0).days * PPD


# Each track: what it is, when it was running here, and the release that shipped it in Claude Code.
# `ours` is dated from this repo's own artefact, `theirs` from the npm publish time of the exact
# version string that carries the CHANGELOG line — never from either side's prose about the other.
TRACKS = [
    dict(
        key="adv",
        name="a research team that attacks its own findings",
        sub="a share of every wave briefed to refute the rest",
        ours=date(2026, 5, 24),
        ours_text="running here",
        theirs=date(2026, 5, 28),
        theirs_text="Dynamic Workflows 2.1.154 — the same idea",
        # Placement, stated per label rather than derived. The constraint on each block is a
        # DIFFERENT neighbour — a formula that got one right got the next one wrong (v1 learned
        # this the expensive way). "start"/"end" is which END of the block the marker's tick lands
        # on, never a page-margin anchor: a block that floats to the margin leaves its tick pointing
        # into the middle of a sentence, which is what a leader line is for avoiding.
        ours_at="start",  # 1050 px of clear room to the marker's right
        theirs_at="start",
        pill_at="after",  # 48 px of rail cannot hold a pill — it sits just past the blue ring
    ),
    dict(
        key="peer",
        name="two-way session messaging",
        sub="open, brief, question and retire peers from any session",
        ours=date(2026, 7, 10),
        ours_text="running here",
        theirs=date(2026, 8, 7),
        theirs_text="Claude Code 2.1.224 — sessions message each other",
        # The blue ring is in the right sixth, so its block runs back to the left from the marker.
        ours_at="start",
        theirs_at="end",
        pill_at="rail",  # 336 px of rail — the pill rides its midpoint
    ),
]

for _t in TRACKS:
    _t["ox"] = x_of(_t["ours"])
    _t["tx"] = x_of(_t["theirs"])
    _t["lead"] = (_t["theirs"] - _t["ours"]).days

# ── palettes ──────────────────────────────────────────────────────────────────────────────────
DARK = dict(
    plate_a="#111823",
    plate_b="#0a0e15",
    edge="#222b3a",
    edge_hi="#ffffff",
    edge_hi_o="0.05",
    grid="#1e2937",
    ink="#e9eff6",
    ink2="#98a5b5",
    ink3="#6a7686",
    track="#37455a",
    rep="#3fb950",
    rep_hi="#6ee787",
    cc="#4b93e6",
    cc_hi="#8cc8ff",
    pill_a="#16241a",
    pill_b="#0f1a13",
    sweep="#a8d0ff",
    sweep_o="0.09",
    halo_o="0.34",
    core="#0a0e15",
)

LIGHT = dict(
    plate_a="#ffffff",
    plate_b="#f2f6fb",
    edge="#d6dee8",
    edge_hi="#ffffff",
    edge_hi_o="0.85",
    grid="#e4ebf3",
    ink="#0d1319",
    ink2="#54606e",
    ink3="#7d8794",
    track="#c8d3e0",
    rep="#1a7f37",
    rep_hi="#2da44e",
    cc="#0969da",
    cc_hi="#218bff",
    pill_a="#e9f7ed",
    pill_b="#dcf1e3",
    sweep="#1f4e8c",
    sweep_o="0.05",
    halo_o="0.16",
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


# ── type scale ────────────────────────────────────────────────────────────────────────────────
F_DATE = 17.5  # mono, the date in a marker block
F_DETAIL = 19  # sans, the rest of a marker block
F_CODA = 17.5
GAP_DATE = 12  # between the date and its text


def block_w(dt: str, text: str, f_text: float = F_DETAIL) -> float:
    return tw(dt, F_DATE, mono=True) + GAP_DATE + tw(text, f_text)


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
.c-rep{{fill:var(--rep)}} .c-cc{{fill:var(--cc)}} .c-rep-hi{{fill:var(--rep_hi)}}

.t-kicker{{font-size:18px;font-weight:600;letter-spacing:2.4px;fill:var(--ink3)}}
.t-key{{font-size:20px;fill:var(--ink2)}}
.t-legend{{font-size:18px;fill:var(--ink2)}}
.t-name{{font-size:26px;font-weight:600;fill:var(--ink)}}
.t-namesub{{font-size:20px;fill:var(--ink2)}}
.t-date{{font-size:{F_DATE}px;letter-spacing:.4px}}
.t-detail{{font-size:{F_DETAIL}px;fill:var(--ink2)}}
.t-coda{{font-size:{F_CODA}px;fill:var(--ink2)}}
.t-month{{font-size:16px;letter-spacing:.4px;fill:var(--ink3)}}
.t-pill{{font-size:26px;font-weight:700;fill:var(--rep_hi)}}
.t-pill-u{{font-size:15px;font-weight:600;letter-spacing:1.5px;fill:var(--rep)}}

.plate{{fill:url(#plate)}}
.edge{{fill:none;stroke:var(--edge);stroke-width:1.5}}
.edgehi{{fill:none;stroke:var(--edge_hi);stroke-width:1.5;opacity:var(--edge_hi_o)}}
.grid{{stroke:var(--grid);stroke-width:1}}

/* the full-width track: dotted where neither side had it yet, and where both do */
.track{{stroke:var(--track);stroke-width:2;stroke-dasharray:2 9;stroke-linecap:round}}
/* the lead: the one span that means "only this repo had it" */
.rail{{fill:none;stroke:var(--rep);stroke-width:3.5;stroke-linecap:round}}
.rail-hi{{fill:none;stroke:var(--rep_hi);stroke-width:1.2;stroke-linecap:round;opacity:.55}}
.tick-rep{{stroke:var(--rep);stroke-width:1.5;opacity:.5;stroke-linecap:round}}
.tick-cc{{stroke:var(--cc);stroke-width:1.5;opacity:.5;stroke-linecap:round}}

.halo{{opacity:var(--halo_o)}}
.halo-rep{{fill:url(#haloRep)}} .halo-cc{{fill:url(#haloCc)}}
.mk-rep{{fill:var(--rep)}}
.mk-core{{fill:var(--core)}}
.mk-spec{{fill:#ffffff;opacity:.45}}
.mk-ring-cc{{fill:var(--core);stroke:var(--cc);stroke-width:4}}

.pill-bg{{fill:url(#pill);stroke:var(--rep);stroke-width:1.4}}

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
.ig-rep{{stroke:var(--rep_hi)}} .ig-cc{{stroke:var(--cc_hi)}}

@media (prefers-reduced-motion: reduce){{*{{animation:none !important}}}}
"""


# ── defs ──────────────────────────────────────────────────────────────────────────────────────
def defs() -> str:
    # Gradient stops carry their colour through a class so the palette override reaches them; a
    # `stop-color="var(...)"` presentation attribute is not reliably resolved.
    return """<defs>
<linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-plate-a"/><stop offset="1" class="g-plate-b"/></linearGradient>
<linearGradient id="pill" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" class="g-pill-a"/><stop offset="1" class="g-pill-b"/></linearGradient>
<radialGradient id="haloRep"><stop offset="0" class="g-rep" stop-opacity=".85"/>
  <stop offset="1" class="g-rep" stop-opacity="0"/></radialGradient>
<radialGradient id="haloCc"><stop offset="0" class="g-cc" stop-opacity=".85"/>
  <stop offset="1" class="g-cc" stop-opacity="0"/></radialGradient>
<linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" class="g-sweep" stop-opacity="0"/>
  <stop offset=".62" class="g-sweep" stop-opacity=".55"/>
  <stop offset=".88" class="g-sweep" stop-opacity="1"/>
  <stop offset="1" class="g-sweep" stop-opacity="0"/></linearGradient>
</defs>
<style>
.g-plate-a{stop-color:var(--plate_a)} .g-plate-b{stop-color:var(--plate_b)}
.g-pill-a{stop-color:var(--pill_a)} .g-pill-b{stop-color:var(--pill_b)}
.g-rep{stop-color:var(--rep)} .g-cc{stop-color:var(--cc)}
.g-sweep{stop-color:var(--sweep)}
</style>"""


# ── the time cursor ───────────────────────────────────────────────────────────────────────────
SWEEP_W = 300  # the light column's width
SWEEP_TRAVEL = W + SWEEP_W  # starts fully off-canvas left, ends fully off-canvas right
SWEEP_EDGE = SWEEP_W * (1 - 0.88)  # the bright stop sits at 88% across the column
IGNITE_PEAK = 0.02 * P  # the ignite keyframe reaches full opacity at 2%


def phase_for(x: float) -> str:
    """The --d that makes a marker peak exactly as the cursor's bright edge crosses it.

    Derived, not tuned. The column's leading bright edge is at `SWEEP_TRAVEL * t / P - SWEEP_EDGE`,
    so it reaches x at t_fire; the element's own animation clock is `t - delay`, and we want that to
    equal IGNITE_PEAK at t_fire. Subtracting one whole period keeps the value negative, which is
    what the freeze's additive seek expects.

    (The first spelling of this was a bare `-(x + 250) / travel * P`, which ignored both the peak
    offset and the sign convention. It looked plausible and was wrong by ~11 s: every marker lit
    while the light column was somewhere else entirely.)
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


TICK_OVERHANG = (
    6  # how far the block runs past its marker, so the tick lands INSIDE the text
)


def marker_block(
    a,
    x: float,
    align: str,
    dt: str,
    text: str,
    hue: str,
    y: float,
    f_text: float = F_DETAIL,
    cls: str = "t-detail",
    where: str = "",
) -> None:
    """One date block: `2026-07-10  Claude Code 2.1.207`, hung off one end from its own marker.

    `align="start"` puts the block's LEFT edge just left of the marker, so it reads rightwards;
    `align="end"` puts its RIGHT edge just right of the marker, so it reads back to the left. Either
    way the marker's leader tick meets an END of the block rather than the middle of a sentence,
    which is the whole reason the choice is stated per label (see the note in TRACKS).

    The first spelling anchored an `end` block at the page margin (PAD_R) instead of at its marker.
    Every block then lined up beautifully down the right edge — and every tick pointed into the
    middle of a phrase 200 px from the marker it belonged to, which is the one thing a leader line
    exists to prevent. Anchoring on the marker is what makes the tick mean something.
    """
    wid = block_w(dt, text, f_text)
    left = (x - TICK_OVERHANG) if align == "start" else (x + TICK_OVERHANG - wid)
    # Assert against the real neighbour — the canvas edge — rather than a guessed budget.
    if left < PAD_L or left + wid > PAD_R:
        WARNINGS.append(
            f"  {where}: block runs {left:.0f}..{left + wid:.0f}, outside "
            f"{PAD_L}..{PAD_R} — {dt} {text!r}"
        )
    a(f'<text class="t-date mono c-{hue}" x="{left:.1f}" y="{y:.0f}">{esc(dt)}</text>')
    a(
        f'<text class="{cls}" x="{left + tw(dt, F_DATE, mono=True) + GAP_DATE:.1f}" '
        f'y="{y:.0f}">{esc(text)}</text>'
    )


def pill(a, cx: float, cy: float, n: int) -> tuple[float, float]:
    """The lead, as a number. Returns its x extent so callers can keep the rail clear of nothing —
    the pill is opaque, so it simply rides on top."""
    num, unit = str(n), "DAYS"
    wn = tw(num, 26, 700)
    wu = tw(unit, 15, 600, 1.5)
    inner = wn + 8 + wu
    pw, ph = inner + 40, 42
    a(
        f'<rect class="pill-bg" x="{cx - pw / 2:.1f}" y="{cy - ph / 2:.1f}" width="{pw:.1f}" '
        f'height="{ph:.1f}" rx="{ph / 2:.1f}"/>'
    )
    a(f'<text class="t-pill" x="{cx - inner / 2:.1f}" y="{cy + 9:.0f}">{num}</text>')
    a(
        f'<text class="t-pill-u" x="{cx - inner / 2 + wn + 8:.1f}" y="{cy + 9:.0f}">{unit}</text>'
    )
    return cx - pw / 2, cx + pw / 2


def build() -> str:
    o: list[str] = []
    a = o.append

    # ── plate + the time cursor ───────────────────────────────────────────────────────────────
    a(f'<rect class="plate" x="0" y="0" width="{W}" height="{H}" rx="16"/>')
    # Authored fully off-canvas to the left, so the reduced-motion still — and the t=0/t=P seam —
    # show no column at all.
    a(
        f'<g class="sweep" style="--d:0s"><rect class="sweepfill" x="-{SWEEP_W}" y="0" '
        f'width="{SWEEP_W}" height="{H}"/></g>'
    )

    # ── month grid + scale ────────────────────────────────────────────────────────────────────
    starts = month_starts()
    a("<g>")
    for d in starts:
        if d <= D0:
            continue
        a(
            f'<line class="grid" x1="{x_of(d):.1f}" y1="{GRID_TOP}" '
            f'x2="{x_of(d):.1f}" y2="{GRID_BOT}"/>'
        )
    a("</g>")
    a("<g>")
    for i, d in enumerate(starts):
        nxt = starts[i + 1] if i + 1 < len(starts) else D1
        if nxt > D1:
            nxt = D1
        mid = (x_of(d) + x_of(nxt)) / 2
        lbl = d.strftime("%b") + (" ’26" if i == 0 else "")
        a(
            f'<text class="t-month mono" x="{mid:.1f}" y="{MONTH_Y}" text-anchor="middle">'
            f"{esc(lbl)}</text>"
        )
    a("</g>")

    # ── the three tracks ──────────────────────────────────────────────────────────────────────
    for t, ry in zip(TRACKS, ROW_Y):
        ox, tx = t["ox"], t["tx"]

        # name + one-line subtitle, on the shared left margin so the eye reads the names down
        nx = PAD_L
        a(f'<text class="t-name" x="{nx}" y="{ry + DY_NAME}">{esc(t["name"])}</text>')
        wn = tw(t["name"], 26, 600)
        a(
            f'<text class="t-namesub" x="{nx + wn + 18:.0f}" y="{ry + DY_NAME}">'
            f"{esc('· ' + t['sub'])}</text>"
        )
        fits(
            t["name"] + " · " + t["sub"],
            PAD_R - PAD_L - 120,
            22,
            where=f"{t['key']} name",
        )

        # the track: dotted before anyone had it, dotted again once both do
        a(f'<line class="track" x1="{PAD_L}" y1="{ry}" x2="{ox - 15:.1f}" y2="{ry}"/>')
        a(f'<line class="track" x1="{tx + 15:.1f}" y1="{ry}" x2="{PAD_R}" y2="{ry}"/>')

        # the lead itself
        a(f'<line class="rail" x1="{ox:.1f}" y1="{ry}" x2="{tx:.1f}" y2="{ry}"/>')
        a(f'<line class="rail-hi" x1="{ox:.1f}" y1="{ry}" x2="{tx:.1f}" y2="{ry}"/>')

        # ticks from each marker into its own band — ours above, theirs below (design leg 4)
        a(
            f'<line class="tick-rep" x1="{ox:.1f}" y1="{ry - 12}" x2="{ox:.1f}" y2="{ry + DY_ABOVE + 6}"/>'
        )
        a(
            f'<line class="tick-cc" x1="{tx:.1f}" y1="{ry + 12}" x2="{tx:.1f}" y2="{ry + DY_BELOW - 15}"/>'
        )
        # the lead, as a number
        if t["pill_at"] == "rail":
            pill(a, (ox + tx) / 2, ry, t["lead"])
        else:
            wn2 = tw(str(t["lead"]), 26, 700) + 8 + tw("DAYS", 15, 600, 1.5) + 40
            pill(a, tx + 30 + wn2 / 2, ry, t["lead"])

        # markers, drawn over everything on the rail
        for x, hue, kind in ((ox, "rep", "ours"), (tx, "cc", "theirs")):
            a(f'<g transform="translate({x:.1f},{ry})">')
            a(f'<circle class="halo halo-{hue}" r="16"/>')
            if kind == "ours":
                a('<circle class="mk-rep" r="9.5"/>')
                a('<circle class="mk-spec" cx="-3" cy="-3.4" r="2.2"/>')
                a(f'<circle class="ig ig-rep" r="12.5" style="{phase_for(x)}"/>')
            else:
                a('<circle class="mk-ring-cc" r="7.5"/>')
                a(f'<circle class="ig ig-cc" r="12.5" style="{phase_for(x)}"/>')
            a("</g>")

        # the date blocks
        marker_block(
            a,
            ox,
            t["ours_at"],
            t["ours"].isoformat(),
            t["ours_text"],
            "rep",
            ry + DY_ABOVE,
            where=f"{t['key']} ours",
        )
        marker_block(
            a,
            tx,
            t["theirs_at"],
            t["theirs"].isoformat(),
            t["theirs_text"],
            "cc",
            ry + DY_BELOW,
            where=f"{t['key']} theirs",
        )

    # ── header ────────────────────────────────────────────────────────────────────────────────
    a(f'<text class="t-kicker" x="{PAD_L}" y="44">HERE FIRST — TWICE</text>')
    key = (
        "Each bar is how long the capability was running here before the Claude Code release "
        "that shipped it."
    )
    fits(key, PAD_R - PAD_L - 200, 20, where="key line")
    a(f'<text class="t-key" x="{PAD_L}" y="78">{esc(key)}</text>')

    legend = (("rep", "running here"), ("cc", "shipped in Claude Code"))
    span = sum(13 + tw(s, 18) + 34 for _, s in legend) - 34
    lx = PAD_R - span
    for hue, text in legend:
        if hue == "rep":
            a(f'<circle class="mk-rep" cx="{lx:.0f}" cy="38" r="7"/>')
        else:
            a(f'<circle class="mk-ring-cc" cx="{lx:.0f}" cy="38" r="5.5"/>')
        a(f'<text class="t-legend" x="{lx + 13:.0f}" y="44">{esc(text)}</text>')
        lx += 13 + tw(text, 18) + 34

    # ── card edge, drawn last so nothing paints over it ───────────────────────────────────────
    a(
        f'<rect class="edge" x=".75" y=".75" width="{W - 1.5}" height="{H - 1.5}" rx="16"/>'
    )
    a(f'<path class="edgehi" d="M 17 1.5 H {W - 17} A 15.5 15.5 0 0 1 {W - 1.5} 17"/>')

    return "\n".join(o)


TITLE = "Twice, this repo shipped it first"

ALT = (
    "Two horizontal tracks on one time axis running from May to August 2026, one per capability. "
    "Each track carries a filled green disc on the date the capability was running in this repo, "
    "a hollow blue ring on the date of the Claude Code release that shipped it, and a green bar "
    "between them — drawn to scale — labelled with the lead in days. The green disc is left of "
    "the blue ring on both tracks. "
    "The upper track, a research team that attacks its own findings — a share of every wave "
    "briefed to refute the rest: running here on 2026-05-24; Dynamic Workflows 2.1.154, the same "
    "idea, on 2026-05-28, a lead of 4 days. "
    "The lower track, two-way session messaging — open, brief, question and retire peers from any "
    "session: running here on 2026-07-10; Claude Code 2.1.224, in which sessions message each "
    "other, on 2026-08-07, a lead of 28 days. "
    "Each track is dotted before its green disc, where neither side had the capability yet, and "
    "dotted again after its blue ring, where both do. A soft column of light crosses the chart "
    "from left to right once every 24 seconds, lighting each of the four markers as it passes, in "
    "date order."
)

DESC = (
    "Two tracks on one time axis, May to August 2026. On each, a green disc marks the date the "
    "capability was running in this repo and a blue ring the Claude Code release that shipped it; "
    "the bar between them is the lead, drawn to scale and labelled — 4 days and 28 days. A light "
    "column crosses left to right once every 24 seconds, igniting each marker in date order."
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
            print(f"  {w}", file=sys.stderr)

    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
