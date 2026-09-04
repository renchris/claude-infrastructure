#!/usr/bin/env python3
"""Build a ground-truth visual-design-defect corpus.

One realistic dashboard page. Thirteen variants: one clean control plus twelve
variants each carrying exactly ONE injected defect at a known location with a
known magnitude.

The point of the corpus is the `detectable_by` field. Nine defects are fully
determined by the DOM, so a deterministic extractor should find them every
time and any detector that misses one is simply worse than a `getComputedStyle`
call. Three are invisible to the DOM by construction -- the styles are correct
and the rendering is still wrong -- so only something that looks at pixels can
find them. A candidate stack is only worth its complexity if it wins the
second group without losing the first.

Usage:  python3 build_corpus.py [outdir]
Writes: <outdir>/pages/*.html and <outdir>/manifest.json
"""

from __future__ import annotations

import json
import pathlib
import sys
from dataclasses import dataclass, field, asdict

# Pinned so a render is reproducible across machines and runs. Helvetica exists
# on every macOS install; naming it explicitly keeps the fallback chain from
# silently changing the metrics between captures.
FONT = "Helvetica, 'Helvetica Neue', Arial, sans-serif"

TOKENS = {
    "blue600": "#3B82F6",
    "blue700": "#1D4ED8",
    "gray900": "#111827",
    "gray600": "#4B5563",
    "gray400": "#9CA3AF",
    "gray200": "#E5E7EB",
    "gray50": "#F9FAFB",
    "white": "#FFFFFF",
    "radius": "8px",
    "gap": "16px",
    "grid": 8,
}


@dataclass
class Defect:
    """One injected defect plus the ground truth needed to score a detector."""

    id: str
    klass: str
    summary: str
    # CSS appended to the base stylesheet. Exactly one rule-set per defect.
    css: str
    # The element a correct report must point at.
    target: str
    # "dom"    -> fully determined by computed styles / box model
    # "pixels" -> the DOM is correct and the rendering is still wrong
    detectable_by: str
    # Magnitude in the natural unit of the defect, for scoring near-misses.
    magnitude: str
    # Why the DOM cannot see it. Required for pixels-only defects.
    dom_blind_because: str = ""
    # Severity a human designer would assign, for weighting.
    severity: str = "medium"
    html_override: dict[str, str] = field(default_factory=dict)


DEFECTS: list[Defect] = [
    # ---------- DOM-determined: a computed-style read should ace all nine ----
    Defect(
        id="spacing-gap",
        klass="spacing-inconsistency",
        summary="Third KPI card sits 23px from its neighbour; every other gap is 16px.",
        css=".kpi-card:nth-child(3) { margin-left: 23px; }",
        target=".kpi-card:nth-child(3)",
        detectable_by="dom",
        magnitude="7px deviation from a 16px rhythm",
        severity="medium",
    ),
    Defect(
        id="align-1px",
        klass="misalignment",
        summary="The table block is 1px left of the header block it should align with.",
        css=".panel { transform: translateX(-1px); }",
        target=".panel",
        detectable_by="dom",
        magnitude="1px horizontal",
        severity="low",
    ),
    Defect(
        id="radius-drift",
        klass="token-drift",
        summary="Second KPI card uses a 6px corner radius; the token is 8px.",
        css=".kpi-card:nth-child(2) { border-radius: 6px; }",
        target=".kpi-card:nth-child(2)",
        detectable_by="dom",
        magnitude="2px of 8px",
        severity="low",
    ),
    Defect(
        id="type-scale",
        klass="typographic-scale",
        summary="One KPI label is 17px; the scale is 12/14/16/24.",
        css=".kpi-card:nth-child(4) .kpi-label { font-size: 17px; }",
        target=".kpi-card:nth-child(4) .kpi-label",
        detectable_by="dom",
        magnitude="17px, off-scale by 1px",
        severity="medium",
    ),
    Defect(
        id="token-color-drift",
        klass="token-drift",
        summary="Primary button fill is #1D4ED3; the token is #1D4ED8.",
        css=".btn-primary { background: #1D4ED3; }",
        target=".btn-primary",
        detectable_by="dom",
        magnitude="5/255 on the blue channel; below the human just-noticeable difference",
        severity="low",
    ),
    Defect(
        id="grid-offgrid",
        klass="grid-violation",
        summary="Section heading has a 13px top margin; the grid is 8px.",
        css=".section-title { margin-top: 13px; }",
        target=".section-title",
        detectable_by="dom",
        magnitude="13px, 5px off the 8px grid",
        severity="low",
    ),
    Defect(
        id="contrast-plain",
        klass="contrast",
        summary="Helper text is #9CA3AF on white: 2.54:1, below the 4.5:1 floor.",
        css=".helper { color: #9CA3AF; }",
        target=".helper",
        detectable_by="dom",
        magnitude="2.54:1 against a 4.5:1 requirement",
        severity="high",
    ),
    Defect(
        id="overflow-clip",
        klass="overflow",
        summary="A table cell clips its text; the descender row is cut mid-glyph.",
        css=".cell-venue { max-height: 18px; overflow: hidden; display: block; }",
        target=".cell-venue",
        detectable_by="dom",
        magnitude="scrollHeight exceeds clientHeight",
        severity="high",
    ),
    Defect(
        id="touch-target",
        klass="accessibility",
        summary="Secondary button is 30px tall; the minimum touch target is 44px.",
        css=".btn-secondary { padding-top: 6px; padding-bottom: 6px; line-height: 16px; }",
        target=".btn-secondary",
        detectable_by="dom",
        magnitude="30px against a 44px floor",
        severity="high",
    ),
    # ---------- Pixels-only: the DOM is correct and the render is wrong ------
    Defect(
        id="contrast-on-gradient",
        klass="contrast",
        summary=(
            "Hero caption is white over a gradient that runs pale at the caption's "
            "position, so the text washes out in its right half."
        ),
        css=(
            ".hero { background: linear-gradient(100deg,#1E3A8A 0%,#3B82F6 45%,"
            "#DBEAFE 100%); } .hero-caption { color: #FFFFFF; }"
        ),
        target=".hero-caption",
        detectable_by="pixels",
        dom_blind_because=(
            "getComputedStyle returns background-color rgba(0,0,0,0) for the caption and "
            "a background-image string for the ancestor. There is no numeric backdrop "
            "colour to contrast against, so the standard ratio computation has no second "
            "operand and axe-core reports 'incomplete' rather than a violation. The actual "
            "backdrop luminance varies across the element's own width."
        ),
        magnitude="ratio falls from ~8.6:1 at the left edge to ~1.2:1 at the right",
        severity="high",
    ),
    Defect(
        id="contrast-on-pattern",
        klass="contrast",
        summary=(
            "Hero caption is white over a high-frequency stripe pattern, so it is "
            "legible over half the pattern and invisible over the other half."
        ),
        css=(
            ".hero { background: repeating-linear-gradient(45deg,#1E3A8A 0 14px,"
            "#DBEAFE 14px 28px); } .hero-caption { color: #FFFFFF; }"
        ),
        target=".hero-caption",
        detectable_by="pixels",
        dom_blind_because=(
            "Same blindness as the gradient case -- background-image, so no numeric "
            "second operand -- but this one the CROSS-CHECK cannot settle either, and "
            "that is why it is here. The gradient varies monotonically across the run, "
            "so sampling the left and right thirds turns 'unrepresentable' into two "
            "numbers and a verdict. A repeating pattern has IDENTICAL statistics in "
            "every third: the two samples agree, the disagreement arm stays silent, "
            "and the abstention is still the honest answer. This is the residue the "
            "abstention router exists to route -- a legibility question with no number "
            "in its answer, which is the one thing a reader has to look at."
        ),
        magnitude="ratio alternates between ~10:1 and ~1.2:1 every 14px",
        severity="high",
    ),
    Defect(
        id="optical-centering",
        klass="optical-alignment",
        summary=(
            "The play mark loses its optical compensation, so it is geometrically "
            "centred and reads left-heavy -- a triangle's ink mass sits behind its "
            "bounding-box centre."
        ),
        css=".glyph-btn .glyph { transform: none; }",
        target=".glyph-btn .glyph",
        detectable_by="pixels",
        dom_blind_because=(
            "Every box-model number is symmetric: the flex container centres the glyph and "
            "getBoundingClientRect on the glyph is exactly centred within the button. The "
            "asymmetry lives in the distribution of ink inside the mark's own box, which no "
            "DOM API exposes. Detecting it requires computing the centroid of the rendered "
            "pixels and comparing it to the geometric centre -- and against the CONTAINER's "
            "centre, because getBoundingClientRect returns the post-transform box, so the "
            "mark's own box moves with the compensation and cannot witness it."
        ),
        magnitude="ink centroid 2.33px left of the geometric centre",
        severity="medium",
    ),
    Defect(
        id="hierarchy-inversion",
        klass="visual-hierarchy",
        summary=(
            "The destructive secondary action is visually heavier than the primary "
            "action beside it, so the eye lands on the wrong button."
        ),
        css=(
            ".btn-secondary { background: #111827; color: #FFFFFF; font-weight: 700; "
            "border: none; padding: 12px 28px; line-height: 20px; } "
            ".btn-primary { background: #EFF6FF; color: #3B82F6; font-weight: 400; "
            "border: 1px solid #DBEAFE; font-size: 14px; }"
        ),
        target=".actions",
        detectable_by="pixels",
        dom_blind_because=(
            "Both buttons have entirely valid styles; nothing is out of range and no token "
            "is violated. The defect is the RELATION between them and the intent behind it. "
            "A rule could encode 'primary must outweigh secondary', but that requires knowing "
            "which is semantically primary and how to compare visual weight -- a judgement, "
            "not a measurement."
        ),
        magnitude="secondary carries roughly 3x the visual weight of the primary",
        severity="high",
    ),
]

BASE_CSS = f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
html {{ -webkit-font-smoothing: antialiased; }}
body {{
  font-family: {FONT};
  background: {TOKENS["white"]};
  color: {TOKENS["gray900"]};
  width: 1280px;
  padding: 32px;
}}
.hero {{
  background: {TOKENS["blue700"]};
  border-radius: {TOKENS["radius"]};
  padding: 24px;
  margin-bottom: 24px;
}}
.hero-title {{ font-size: 24px; font-weight: 700; color: #FFFFFF; }}
.hero-caption {{ font-size: 14px; color: #DBEAFE; margin-top: 8px; }}

.kpi-row {{ display: flex; gap: {TOKENS["gap"]}; margin-bottom: 24px; }}
.kpi-card {{
  flex: 1;
  background: {TOKENS["gray50"]};
  border: 1px solid {TOKENS["gray200"]};
  border-radius: {TOKENS["radius"]};
  padding: 16px;
}}
.kpi-label {{ font-size: 12px; color: {TOKENS["gray600"]}; text-transform: uppercase;
             letter-spacing: 0.04em; }}
.kpi-value {{ font-size: 24px; font-weight: 700; margin-top: 8px; }}

.section-title {{ font-size: 16px; font-weight: 700; margin-top: 24px; margin-bottom: 8px; }}
.helper {{ font-size: 12px; color: {TOKENS["gray600"]}; margin-bottom: 16px; }}

.panel {{
  border: 1px solid {TOKENS["gray200"]};
  border-radius: {TOKENS["radius"]};
  overflow: hidden;
}}
table {{ width: 100%; border-collapse: collapse; }}
th, td {{ text-align: left; padding: 12px 16px; font-size: 14px; }}
th {{ background: {TOKENS["gray50"]}; color: {TOKENS["gray600"]}; font-size: 12px;
      text-transform: uppercase; letter-spacing: 0.04em; }}
tr + tr td {{ border-top: 1px solid {TOKENS["gray200"]}; }}

.actions {{ display: flex; gap: {TOKENS["gap"]}; align-items: center; margin-top: 24px; }}
/* Button labels are 16px, the same step as .section-title, so the 16px rung of
   the 12/14/16/24 scale is carried by TWO real components. It used to rest on a
   single decorative glyph's font-size, and when that glyph became a drawn shape
   with no text the rung vanished and the scale rule fired on the control. A
   scale step held up by one element that paints no text is not a step. */
.btn-primary {{
  background: {TOKENS["blue700"]}; color: #FFFFFF; font-weight: 600; font-size: 16px;
  border: none; border-radius: 8px; padding: 16px 20px; line-height: 16px; cursor: pointer;
}}
.btn-secondary {{
  background: #FFFFFF; color: {TOKENS["gray600"]}; font-weight: 400; font-size: 16px;
  border: 1px solid {TOKENS["gray200"]}; border-radius: 8px; padding: 15px 20px;
  line-height: 16px; cursor: pointer;
}}
.glyph-btn {{
  width: 44px; height: 44px; border-radius: 22px; background: {TOKENS["blue700"]};
  display: flex; align-items: center; justify-content: center;
}}
.glyph {{
  /* A DRAWN triangle, not a font glyph, and that is load-bearing. The corpus
     promises a render reproducible across machines; a text glyph breaks that
     promise for the one defect whose ground truth is ink GEOMETRY. `Helvetica`
     exists on macOS and nowhere else, and the fallback's U+25B6 sits ~1.7px
     BELOW its line box's centre where Helvetica's sits above it -- so a
     compensation constant measured on one machine cancelled the bias there and
     DOUBLED it here (measured 2026-09-04: ink 3.7px low on the "clean" control
     under DejaVu Sans, i.e. the control was not clean).
     Borders give an exact, font-free shape. Base on the left, apex on the
     right: the ink centroid of a triangle is one third of its width from the
     base, so it sits 14/6 = 2.33px LEFT of the bounding-box centre. That is
     the number the compensation below cancels, and it is arithmetic rather
     than a measurement. */
  display: block; width: 0; height: 0;
  border-top: 8px solid transparent;
  border-bottom: 8px solid transparent;
  border-left: 14px solid #FFFFFF;
  transform: translateX(2.33px);
}}
"""

BODY_HTML = """
<div class="hero">
  <div class="hero-title">Tonight at Ophelia</div>
  <div class="hero-caption">Doors 22:00 &middot; 14 tables held &middot; 3 awaiting deposit</div>
</div>

<div class="kpi-row">
  <div class="kpi-card"><div class="kpi-label">Covers</div><div class="kpi-value">248</div></div>
  <div class="kpi-card"><div class="kpi-label">Spend</div><div class="kpi-value">$61,400</div></div>
  <div class="kpi-card"><div class="kpi-label">Tables</div><div class="kpi-value">32</div></div>
  <div class="kpi-card"><div class="kpi-label">No-shows</div><div class="kpi-value">4</div></div>
</div>

<div class="section-title">Reservations</div>
<div class="helper">Deposits settle at 02:00. Rows in grey are awaiting confirmation.</div>

<div class="panel">
  <table>
    <tr><th>Guest</th><th>Venue</th><th>Party</th><th>Minimum</th></tr>
    <tr><td>A. Nakamura</td><td class="cell-venue">Ophelia Rooftop Terrace</td>
        <td>8</td><td>$4,000</td></tr>
    <tr><td>R. Delgado</td><td class="cell-venue">Ophelia Main Room</td>
        <td>12</td><td>$7,500</td></tr>
    <tr><td>S. Okonkwo</td><td class="cell-venue">Ophelia Mezzanine Booth</td>
        <td>6</td><td>$3,200</td></tr>
  </table>
</div>

<div class="actions">
  <div class="action-group">
    <button class="btn-primary">Confirm all deposits</button>
    <button class="btn-secondary">Release held tables</button>
  </div>
  <div class="glyph-btn"><span class="glyph"></span></div>
</div>
"""

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>{title}</title>
<style>{base}
/* ---- injected defect: {did} ---- */
{extra}
</style></head><body>{body}</body></html>
"""


def build(outdir: pathlib.Path) -> dict:
    pages = outdir / "pages"
    pages.mkdir(parents=True, exist_ok=True)

    (pages / "clean.html").write_text(
        PAGE.format(
            title="clean", base=BASE_CSS, did="none (control)", extra="", body=BODY_HTML
        )
    )

    entries = []
    for d in DEFECTS:
        (pages / f"{d.id}.html").write_text(
            PAGE.format(
                title=d.id, base=BASE_CSS, did=d.id, extra=d.css, body=BODY_HTML
            )
        )
        entries.append(asdict(d))

    manifest = {
        "corpus_version": "1.0",
        "built": "2026-08-26",
        "viewport": {"width": 1280, "height": 900},
        "tokens": TOKENS,
        "control": "clean.html",
        "counts": {
            "total_variants": len(DEFECTS) + 1,
            "dom_detectable": sum(1 for d in DEFECTS if d.detectable_by == "dom"),
            "pixels_only": sum(1 for d in DEFECTS if d.detectable_by == "pixels"),
        },
        "scoring": {
            "true_positive": "names the right defect class AND points at the right target",
            "near_miss": "notices something wrong at the right target, wrong class",
            "false_positive": "reports a defect on the clean control, or on an unmodified "
            "element of a defect page",
            "note": "The control exists so a detector that reports problems everywhere "
            "scores badly. A run with zero findings on clean.html is a "
            "precondition for the rest of the score meaning anything.",
        },
        "defects": entries,
    }
    (outdir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest


if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "out").resolve()
    m = build(out)
    c = m["counts"]
    print(f"corpus -> {out}")
    print(
        f"  {c['total_variants']} pages: 1 control + {c['dom_detectable']} DOM-detectable "
        f"+ {c['pixels_only']} pixels-only"
    )
    for d in m["defects"]:
        print(f"  [{d['detectable_by']:6}] {d['id']:22} {d['magnitude']}")
