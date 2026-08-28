#!/usr/bin/env python3
"""Capture the corpus: a screenshot plus a full layout/style snapshot per page.

Two artifacts come out of one browser pass, and keeping them in one pass is the
point -- the snapshot describes exactly the frame that was photographed, so a
pixel finding and a DOM finding can be argued against each other without any
"maybe the page moved" escape hatch.

Screenshots are taken at both deviceScaleFactor 1 and 2 so the capture-fidelity
question (does a 2x capture actually buy a vision model anything, or does the
model's own downscaling throw it away) can be measured rather than assumed.

Usage: python3 capture.py <corpus-dir> [--dpr 1,2]
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import time

from playwright.sync_api import sync_playwright

# Everything a general design rule could need, and nothing else. Pulling all of
# getComputedStyle would be ~340 properties per element and would bury the
# signal in shorthand duplicates.
STYLE_PROPS = [
    "display",
    "position",
    "visibility",
    "opacity",
    "overflow",
    "overflow-x",
    "overflow-y",
    "font-family",
    "font-size",
    "font-weight",
    "font-style",
    "line-height",
    "letter-spacing",
    "text-transform",
    "text-overflow",
    "white-space",
    "color",
    "background-color",
    "background-image",
    "border-radius",
    "border-top-width",
    "border-right-width",
    "border-bottom-width",
    "border-left-width",
    "border-top-color",
    "margin-top",
    "margin-right",
    "margin-bottom",
    "margin-left",
    "padding-top",
    "padding-right",
    "padding-bottom",
    "padding-left",
    "gap",
    "column-gap",
    "row-gap",
    "flex-direction",
    "align-items",
    "justify-content",
    "z-index",
    "box-shadow",
    "transform",
]

EXTRACT_JS = """
(props) => {
  // A stable, human-readable path so a finding can name an element the way a
  // person would. nth-of-type keeps it unique without leaking generated ids.
  const pathOf = (el) => {
    const parts = [];
    while (el && el.nodeType === 1 && el.tagName !== 'BODY') {
      let seg = el.tagName.toLowerCase();
      if (el.classList.length) seg += '.' + [...el.classList].join('.');
      const sibs = el.parentElement
        ? [...el.parentElement.children].filter(c => c.tagName === el.tagName)
        : [];
      if (sibs.length > 1) seg += `:nth-of-type(${sibs.indexOf(el) + 1})`;
      parts.unshift(seg);
      el = el.parentElement;
    }
    return parts.join(' > ');
  };

  const out = [];
  for (const el of document.body.querySelectorAll('*')) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue;
    const cs = getComputedStyle(el);
    const styles = {};
    for (const p of props) styles[p] = cs.getPropertyValue(p);

    // Direct text only: a wrapper's textContent includes every descendant and
    // would make every ancestor look like a text node.
    const ownText = [...el.childNodes]
      .filter(n => n.nodeType === 3).map(n => n.textContent.trim())
      .join(' ').trim();

    out.push({
      path: pathOf(el),
      tag: el.tagName.toLowerCase(),
      classes: [...el.classList],
      text: ownText.slice(0, 120),
      rect: { x: +r.x.toFixed(2), y: +r.y.toFixed(2),
              w: +r.width.toFixed(2), h: +r.height.toFixed(2),
              right: +r.right.toFixed(2), bottom: +r.bottom.toFixed(2) },
      // The overflow signal: a clipped element reports more content than it shows.
      scroll: { h: el.scrollHeight, ch: el.clientHeight,
                w: el.scrollWidth, cw: el.clientWidth },
      styles,
    });
  }
  return {
    url: location.href,
    title: document.title,
    scroll: { w: document.documentElement.scrollWidth,
              h: document.documentElement.scrollHeight },
    elements: out,
  };
}
"""


def capture(corpus: pathlib.Path, dprs: list[int]) -> None:
    manifest = json.loads((corpus / "manifest.json").read_text())
    vp = manifest["viewport"]
    pages = sorted((corpus / "pages").glob("*.html"))
    if not pages:
        sys.exit(f"no pages under {corpus / 'pages'}")

    shots = corpus / "shots"
    snaps = corpus / "snapshots"
    shots.mkdir(exist_ok=True)
    snaps.mkdir(exist_ok=True)

    timings = []
    with sync_playwright() as p:
        # A pinned browser binary wins over the channel when one is supplied. The
        # bench otherwise only runs where Playwright's own download matches its
        # Python package, which is not true of a CI image that ships one Chromium
        # for every version of the client. Set BENCH_CHROMIUM to that binary.
        exe = os.environ.get("BENCH_CHROMIUM")
        launch_kw = {"executable_path": exe} if exe else {"channel": "chromium"}
        browser = p.chromium.launch(
            **launch_kw,
            args=[
                "--force-color-profile=srgb",
                "--disable-lcd-text",
                "--hide-scrollbars",
                # Pins the host display scale so headless matches headed. Without it
                # the two disagree on line-box rounding -- measured at ~1.5px drift
                # accumulated over four paragraphs, with identical font metrics --
                # and every geometric finding inherits a phantom offset that reads
                # like a real 1px bug.
                f"--force-device-scale-factor={max(dprs):g}",
            ],
        )
        for dpr in dprs:
            ctx = browser.new_context(
                viewport={"width": vp["width"], "height": vp["height"]},
                device_scale_factor=dpr,
                color_scheme="light",
                reduced_motion="reduce",
            )
            page = ctx.new_page()
            for html in pages:
                t0 = time.perf_counter()
                page.goto(html.as_uri(), wait_until="load")
                page.evaluate("document.fonts.ready")
                suffix = "" if dpr == 1 else f"@{dpr:g}x"
                page.screenshot(
                    path=str(shots / f"{html.stem}{suffix}.png"), full_page=True
                )
                # The snapshot is DPR-independent (CSS pixels), so take it once.
                if dpr == dprs[0]:
                    snap = page.evaluate(EXTRACT_JS, STYLE_PROPS)
                    snap["source"] = html.name
                    (snaps / f"{html.stem}.json").write_text(json.dumps(snap, indent=1))
                timings.append(
                    (html.stem, dpr, round((time.perf_counter() - t0) * 1000))
                )
            ctx.close()
        browser.close()

    per_dpr = {}
    for _, dpr, ms in timings:
        per_dpr.setdefault(dpr, []).append(ms)
    print(f"captured {len(pages)} pages at dpr {dprs}")
    for dpr, ms in sorted(per_dpr.items()):
        print(f"  dpr {dpr}: mean {sum(ms) // len(ms)} ms/page")
    for f in sorted(shots.glob("*.png"))[:3]:
        print(f"  sample {f.name}: {f.stat().st_size // 1024} KB")
    n_el = len(json.loads((snaps / "clean.json").read_text())["elements"])
    print(
        f"  snapshot: {n_el} elements/page, "
        f"{(snaps / 'clean.json').stat().st_size // 1024} KB"
    )


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument(
        "--dpr", default="1,1.5"
    )  # 1.5 keeps 1280px wide under the 2000px clamp
    a = ap.parse_args()
    capture(a.corpus.resolve(), [float(x) for x in a.dpr.split(",")])
