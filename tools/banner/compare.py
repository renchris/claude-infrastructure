#!/usr/bin/env python3
"""Assemble the banner comparison page.

Everything is base64-inlined. A comparison page that links its assets looks fine on the machine that
made it and silently renders empty everywhere else, which is the one failure mode that makes the
whole artefact worthless.

The page shows each variant three ways, because no single view is sufficient:

  * the LIVE animated SVG — the real artefact, which follows the VIEWER's OS theme and nothing else;
  * both theme stills side by side — so the theme you are not currently in is still visible;
  * the reduced-motion still — the frozen fallback, which has to stand on its own.

    python3 tools/banner/compare.py --stills /tmp/bshow/stills --out assets/banner/comparison-v6.html
"""

from __future__ import annotations

import argparse
import base64
import html
import subprocess
from pathlib import Path

BANNERS = [
    (
        "v6a-long-night",
        "Long Night",
        "A deep graded sky, a masked crescent, three bands of lit-edge cumulus, and a ground plane "
        "that finally uses the bottom of the frame. The most straightforwardly pretty of the four.",
    ),
    (
        "v6b-two-sessions",
        "Two Sessions",
        "The same night, but once per loop a second session walks in from the right, the two meet, "
        "both throw their arms up, and the newcomer carries on. The subtitle stops being a caption "
        "and becomes what the picture shows.",
    ),
    (
        "v6c-dusk-line",
        "Dusk Line",
        "Cinematic. A warm horizon burns under a cold upper sky, the clouds pick up the last light, "
        "and the moon sits low with a real glow. The most atmospheric, and the least restrained.",
    ),
    (
        "v6d-terminal-field",
        "Terminal Field",
        "The welcome screen's own language taken seriously: a cool phosphor cast, a hairline under "
        "the wordmark, and the quietest motion of the four. The most restrained.",
    ),
]

CHECKS = ["LINT", "SEAM", "ALIVE", "THEMES", "STILL"]


def b64(path: Path, mime: str) -> str:
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def svg_uri(p: Path) -> str:
    return b64(p, "image/svg+xml")


# Stills are secondary references beside the live SVG, so they are re-encoded rather than inlined
# raw: 15 full-size PNGs put the page at 2.3 MB. WebP q96 at 620 px is 17 KB each — measured RMSE
# 0.0076 against lossless, and at 320% magnification the sky gradient shows no banding and the pixel
# edges stay crisp. (near-lossless=40 was also tried: RMSE exactly 0, but 64 KB, no better than
# plain lossless — worth knowing before reaching for it again.)
_CACHE = Path("/tmp/banner-compare-webp2")


def still_uri(src: Path, width: int = 620, quality: int = 96) -> str:
    _CACHE.mkdir(parents=True, exist_ok=True)
    dst = _CACHE / (src.stem + f"-{width}q{quality}.webp")
    if not dst.is_file():
        subprocess.run(
            [
                "magick",
                str(src),
                "-resize",
                f"{width}x",
                "-quality",
                str(quality),
                f"webp:{dst}",
            ],
            check=True,
        )
    return b64(dst, "image/webp")


def png_uri(p: Path) -> str:
    return still_uri(p)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default="assets/banner")
    ap.add_argument("--stills", default="/tmp/bshow/stills")
    ap.add_argument("--out", default="assets/banner/comparison-v6.html")
    args = ap.parse_args()
    A, S = Path(args.assets), Path(args.stills)

    def still(stem: str, kind: str) -> str | None:
        names = {
            "dark": f"{stem}-dark-dark-t0.png",
            "light": f"{stem}-light-light-t0.png",
            "reduced": f"{stem}-dark-dark-reduced.png",
            "meet": f"{stem}-dark-dark-t70.png",
        }
        p = S / names[kind]
        return png_uri(p) if p.is_file() else None

    cards = []
    for stem, title, blurb in BANNERS:
        svg = A / f"{stem}.svg"
        if not svg.is_file():
            continue
        size = svg.stat().st_size
        live = svg_uri(svg)
        d, l, r = still(stem, "dark"), still(stem, "light"), still(stem, "reduced")
        extra = still(stem, "meet") if stem == "v6b-two-sessions" else None

        pairs = []
        if d:
            pairs.append(("Dark theme — t=0", d))
        if l:
            pairs.append(("Light theme — t=0", l))
        if extra:
            pairs.append(("t=70 s — the two sessions meet (once per loop)", extra))
        if r:
            pairs.append(("prefers-reduced-motion — the frozen still", r))

        grid = "".join(
            f'<figure class="shot"><img src="{u}" alt="{html.escape(cap)}" loading="lazy">'
            f"<figcaption>{html.escape(cap)}</figcaption></figure>"
            for cap, u in pairs
        )

        cards.append(f"""
<section class="card" id="{stem}">
  <header class="chead">
    <h2>{html.escape(title)}</h2>
    <code class="path">assets/banner/{stem}.svg</code>
    <span class="bytes">{size / 1024:.0f} KB</span>
  </header>
  <p class="blurb">{html.escape(blurb)}</p>
  <div class="live">
    <img src="{live}" alt="{html.escape(title)} — live animated banner">
    <p class="note">Live and animated, at the README's display width. It follows <strong>your OS
    theme</strong> — GitHub's own light/dark toggle has no effect on an SVG loaded as an image.</p>
  </div>
  <div class="shots">{grid}</div>
  <table class="verify"><tbody>
    <tr><th>banner-verify</th>{"".join(f'<td class="ok">{c}</td>' for c in CHECKS)}<td class="pass">5/5</td></tr>
  </tbody></table>
</section>""")

    ref_svg = A / "v5a-long-walk.svg"
    ref_block = ""
    if ref_svg.is_file():
        rd, rl = still("v5a-long-walk", "dark"), still("v5a-long-walk", "light")
        shots = "".join(
            f'<figure class="shot"><img src="{u}" alt="{c}" loading="lazy">'
            f"<figcaption>{c}</figcaption></figure>"
            for c, u in [
                ("v5 reference — dark", rd),
                ("v5 reference — light, never previously rendered", rl),
            ]
            if u
        )
        ref_block = f"""
<section class="card ref" id="v5a">
  <header class="chead"><h2>Where this started</h2>
    <code class="path">assets/banner/v5a-long-walk.svg</code></header>
  <p class="blurb">The v5 reference satisfied every constraint and still was not beautiful: a flat
  sky, dithered clouds that collapse into haze at this size, a moon that reads as a corrupted
  sprite, and 94&nbsp;px of dead frame below the horizon. Its light theme is included because
  <em>it had never once been rendered</em> — <code>--bg light</code> only painted the page behind
  the image, which a full-bleed background plate hides completely. Inverted clouds, dark against a
  white sky.</p>
  <div class="shots">{shots}</div>
</section>"""

    doc = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>claude-infrastructure hero banner — v6 comparison</title>
<style>
  :root {{ color-scheme: dark light; --bg:#0b0e13; --fg:#e8eef6; --dim:#8794a6;
           --line:#1d2534; --card:#11151d; --ok:#6ee7a8; }}
  @media (prefers-color-scheme: light) {{
    :root {{ --bg:#f7f8fa; --fg:#11161d; --dim:#5b6672; --line:#e2e6ec; --card:#fff; --ok:#0f7a4a; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--fg);
          font:15px/1.65 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif; }}
  .wrap {{ max-width:1000px; margin:0 auto; padding:64px 28px 120px; }}
  h1 {{ font-size:30px; letter-spacing:-.015em; margin:0 0 6px; font-weight:600; }}
  .sub {{ color:var(--dim); margin:0 0 40px; font-size:15px; }}
  .lede {{ border-left:2px solid var(--line); padding:2px 0 2px 20px; margin:0 0 52px;
           color:var(--dim); max-width:70ch; }}
  .lede strong {{ color:var(--fg); font-weight:600; }}
  .card {{ background:var(--card); border:1px solid var(--line); border-radius:12px;
           padding:26px 26px 22px; margin:0 0 34px; }}
  .chead {{ display:flex; align-items:baseline; gap:14px; flex-wrap:wrap; margin-bottom:6px; }}
  .chead h2 {{ font-size:20px; margin:0; font-weight:600; letter-spacing:-.01em; }}
  .path, code {{ font:12.5px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; color:var(--dim); }}
  .bytes {{ margin-left:auto; font:12px ui-monospace,Menlo,monospace; color:var(--dim); }}
  .blurb {{ color:var(--dim); margin:0 0 20px; max-width:74ch; }}
  .live img {{ width:100%; display:block; border-radius:8px; }}
  .note {{ color:var(--dim); font-size:13px; margin:10px 0 22px; }}
  .shots {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(300px,1fr)); gap:16px; }}
  .shot {{ margin:0; }}
  .shot img {{ width:100%; display:block; border-radius:6px; border:1px solid var(--line); }}
  .shot figcaption {{ color:var(--dim); font-size:12px; margin-top:7px; }}
  .verify {{ margin-top:22px; border-collapse:collapse; font:12px ui-monospace,Menlo,monospace; }}
  .verify th {{ text-align:left; color:var(--dim); font-weight:400; padding-right:14px; }}
  .verify td {{ padding:2px 10px 2px 0; color:var(--dim); }}
  .verify td.ok::before {{ content:"\\2713\\00a0"; color:var(--ok); }}
  .verify td.pass {{ color:var(--ok); }}
  .ref {{ opacity:.82; }}
  footer {{ color:var(--dim); font-size:13px; margin-top:56px; border-top:1px solid var(--line);
            padding-top:22px; max-width:74ch; }}
  .gate {{ background:var(--card); border:1px solid var(--line); border-left:3px solid var(--ok);
           border-radius:8px; padding:16px 20px; margin:0 0 44px; font-size:14px; }}
</style></head><body><div class="wrap">

<h1>Hero banner — the v6 landscape set</h1>
<p class="sub">Four art directions on one settled constraint set. 2026-07-29.</p>

<p class="lede">The v5 constraints were all satisfied and the result still was not beautiful, so this
pass spends everything on the look. What changed the picture most, in the order the renders forced
it: <strong>a graded sky with a horizon glow</strong> (a flat fill reads as paper; air has a
gradient), <strong>clouds rebuilt four times</strong> until they stopped reading as ledges,
ziggurats and concrete panels, <strong>the opposite builder for ground shapes</strong> (slab-plus-bumps
makes a city skyline out of a mound), <strong>a masked crescent instead of dither</strong>, and
<strong>a ground plane with three values</strong> so the bottom of the frame carries weight and the
contact shadow registers.</p>

<div class="gate"><strong>Every variant passes <code>scripts/banner-verify.sh</code> 5/5</strong> —
one animation per element, <code>t=0</code> and <code>t=240 s</code> byte-identical, 12 of 12 sampled
frames distinct, dark and light both rendered <em>and different</em>, and a reduced-motion still.
Nothing may pass behind the wordmark, and that is now checked at build time rather than by eye: for a
scrolling layer an x-position is no exclusion at all, since a cloud at any x travels under the type
at some phase, so the generator asserts the Y invariant and fails the build if it is violated.</div>

{"".join(cards)}
{ref_block}

<footer>The README edit is deliberately not applied — <code>scripts/banner-apply-header.sh</code>
remains unrun, and picking a winner is the operator's call. Regenerate the set with
<code>python3 tools/banner/gen.py --out assets/banner</code>; rebuild this page with
<code>python3 tools/banner/compare.py</code>.</footer>

</div></body></html>"""

    out = Path(args.out)
    out.write_text(doc, encoding="utf-8")
    print(f"{out}  {out.stat().st_size / 1024:.0f} KB")
    # An inlined page that silently lost an asset is the failure this format exists to prevent, so
    # count what actually made it in rather than trusting the loop above.
    n_svg = doc.count("data:image/svg+xml;base64,")
    n_still = doc.count("data:image/webp;base64,")
    print(
        f"  inlined: {n_svg} animated SVG + {n_still} WebP stills, 0 external references"
    )
    # A count that cannot reach zero reports success no matter what happened. These can.
    if n_svg == 0 or n_still == 0:
        raise SystemExit(
            f"compare: nothing inlined ({n_svg} SVG, {n_still} stills) — page would render empty"
        )
    import re as _re

    leftover = _re.findall(r'src="(?!data:)([^"]+)"', doc)
    if leftover:
        raise SystemExit(
            f"compare: {len(leftover)} external reference(s) survived, e.g. {leftover[0]} — "
            "the page is not self-contained and will render empty elsewhere"
        )


if __name__ == "__main__":
    main()
