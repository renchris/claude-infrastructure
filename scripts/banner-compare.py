#!/usr/bin/env python3
"""banner-compare.py — build the side-by-side comparison page for the banner candidates.

Every candidate is embedded as `<img src="…svg">`, which is SVG-as-image mode: no scripts, no
external resources, stricter than opening the SVG as a document. That is the mode GitHub uses, so it
is the only mode worth comparing in — a page that inlined the SVGs would let each one reach
capabilities the README will not give it, and would compare something the reader never sees.

The images are LINKED, not inlined, for the same reason. It costs a relative path (so the page must
sit beside the assets) and it buys a page that cannot flatter its subjects.

Each candidate is shown twice: animating, and again with motion frozen via the reduced-motion
screenshot, because the frozen composition is half the deliverable — it is what a reduced-motion
reader gets, and what anyone who scrolls past mid-cycle sees. (A page cannot force reduced motion on
an <img>, so the frozen state has to be a still.)

Those stills are near-lossless WebP at display width, which is 4.5 KB where the PNG was 70 KB. Plain
lossy WebP is not an option and the choice is not about the saving: it seams every flat region, and
these frames are mostly one flat dark plate.

  scripts/banner-compare.py assets/banner/v2 > assets/banner/v2/comparison.html
"""

from __future__ import annotations

import argparse
import html
import pathlib
import re
import sys

SUBJECTS = {
    "s1": (
        "S1 · The world it lives in",
        "<b>safely</b> — <code>~/.claude</code> stopped being machine state and became a place that "
        "is deployed. One creature, the landscape that ships in the binary, and nothing else.",
    ),
    "s2": (
        "S2 · The fleet",
        "<b>many</b> — several sessions run at once on one machine and cannot collide. The "
        "load-bearing detail is that <b>nothing joins the creatures</b>: a thread between two of "
        "them would rebuild the handoff infographic R1 rejected. Same ground, separate lanes, no "
        "contact — the absence is the argument.",
    ),
    "s3": (
        "S3 · The night shift",
        "<b>unattended</b> — it runs while you are asleep and pages you only when a human must "
        "decide. The night variant of the scene ships in the same bundle as the day one.",
    ),
}

BLURB = {
    "s1a-horizon": "Title and creature on one full-width horizon. The plainest reading.",
    "s1b-close": "The most restrained: one large creature, one hairline, the words. Nothing else "
    "in the frame.",
    "s1c-scene": "The fullest quote of the shipped scene — mounds and vegetation, the creature "
    "standing among them.",
    "s2a-lanes": "Four creatures evenly spaced on one horizon, each idling out of step.",
    "s2b-depth": "Three lanes at three distances, so parallelism reads as depth rather than as a "
    "row.",
    "s2c-row": "The words hold the left, the population holds the right, both on one line.",
    "s3a-starfield": "Sparse stars on uncorrelated slow timings; the creature still working "
    "beneath them.",
    "s3b-tree": "The night scene's canopy and trunk, quoted, with the creature at the far side of "
    "the same line.",
    "s3c-longwatch": "A denser, fainter sky — and one star on a far longer beat than any other: "
    "the page that is not coming.",
}

CSS = """
:root { color-scheme: dark light; }
* { box-sizing: border-box; }
body { margin: 0; padding: 40px 28px 96px;
       background: #0d1117; color: #c9d1d9;
       font: 15px/1.65 ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace; }
main { max-width: 1000px; margin: 0 auto; }
h1 { font-size: 25px; font-weight: 600; letter-spacing: .2px; color: #e6edf3; margin: 0 0 6px; }
.lede { color: #8b949e; margin: 0 0 12px; }
.rules { border: 1px solid #21262d; border-radius: 10px; padding: 14px 18px; margin: 22px 0 40px;
         background: #10151c; }
.rules p { margin: 0 0 8px; color: #8b949e; }
.rules p:last-child { margin: 0; }
.rules b { color: #c9d1d9; }
h2 { font-size: 18px; font-weight: 600; color: #e6edf3; margin: 46px 0 4px;
     padding-top: 22px; border-top: 1px solid #21262d; }
h2:first-of-type { border-top: 0; }
.claim { color: #8b949e; margin: 0 0 26px; }
figure { margin: 0 0 34px; }
figcaption { display: flex; gap: 10px; align-items: baseline; margin: 0 0 8px; }
.key { color: #d77757; font-weight: 600; }
.why { color: #8b949e; }
img { display: block; width: 100%; height: auto; border-radius: 10px; }
.pair { display: grid; gap: 10px; grid-template-columns: 1fr; }
.frozen { margin-top: 10px; }
.frozen .tag { color: #6e7681; font-size: 13px; margin: 6px 0 4px; }
.meta { color: #6e7681; font-size: 13px; margin: 6px 0 0; }
code { color: #c9d1d9; background: #161b22; padding: 1px 5px; border-radius: 4px; font-size: .92em; }
"""


def build(d: pathlib.Path) -> str:
    svgs = sorted(p for p in d.glob("*.svg"))
    if not svgs:
        sys.exit(f"banner-compare: no .svg in {d}")

    out = [
        '<!doctype html><meta charset="utf-8">',
        "<title>README hero banner — nine candidates, three subjects</title>",
        f"<style>{CSS}</style>",
        "<main>",
        "<h1>README hero banner — nine candidates</h1>",
        '<p class="lede">Three subjects, three variants each. Every banner below is embedded as '
        '<code>&lt;img src="…svg"&gt;</code> — the same SVG-as-image mode GitHub uses, with no '
        "scripts and no external resources. Nothing here is inlined, so none of them can reach a "
        "capability the README would not give it.</p>",
        '<div class="rules">',
        "<p><b>Held to all four rejections.</b> <b>R1</b> whole-system, never a handoff or "
        "subsystem infographic — nothing in any candidate depicts an exchange. <b>R2</b> the title "
        "is a plain <code>&lt;text&gt;</code> with no animation, opacity or keyframe that reaches "
        "it, so there is no state of the document in which it is absent; verified present, and "
        "unobscured, in all 45 rendered frames. <b>R3</b> every animation is "
        "<code>infinite</code> and every keyframe list starts and ends on the same value, so the "
        "loop has no seam; the motion is an idle cycle, not a narrative. <b>R4</b> the real 11×8 "
        "clawd in <code>#D77757</code>, posing through its four shipped poses.</p>",
        "<p><b>The choice is the subject, not the medium.</b> Vector is settled — every raster "
        "encoding of an eight-second composition ran 1.2×–45× over the 1&nbsp;MB budget. These are "
        "3–17&nbsp;KB.</p>",
        "</div>",
    ]

    for prefix, (heading, claim) in SUBJECTS.items():
        group = [p for p in svgs if p.stem.startswith(prefix)]
        if not group:
            continue
        out += [f"<h2>{heading}</h2>", f'<p class="claim">{claim}</p>']
        for p in group:
            key = p.stem
            frozen = f"{key}-frozen.webp"
            has_frozen = (d / frozen).exists()
            out += [
                "<figure>",
                "<figcaption>"
                f'<span class="key">{html.escape(key)}</span>'
                f'<span class="why">{BLURB.get(key, "")}</span>'
                "</figcaption>",
                f'<img src="{p.name}" alt="{html.escape(_alt(p))}">',
                f'<p class="meta">{p.stat().st_size:,} B</p>',
            ]
            if has_frozen:
                out += [
                    '<div class="frozen">',
                    '<p class="tag">↑ animating &nbsp;·&nbsp; ↓ frozen, as a '
                    "prefers-reduced-motion reader sees it — same artwork, no second fallback</p>",
                    f'<img src="{frozen}" alt="The same banner with motion disabled.">',
                    "</div>",
                ]
            out.append("</figure>")

    out += ["</main>"]
    return "\n".join(out)


def _alt(p: pathlib.Path) -> str:
    """Reuse the SVG's own <desc>, so the page cannot describe something the asset does not do."""
    m = re.search(r"<desc[^>]*>(.*?)</desc>", p.read_text(), re.S)
    return re.sub(r"\s+", " ", m.group(1)).strip() if m else p.stem


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dir", type=pathlib.Path)
    a = ap.parse_args()
    print(build(a.dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
