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
import platform
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


FONT_PROBE_JS = """
() => {
  // `getComputedStyle().fontFamily` returns the STACK the author wrote, not the
  // face that rendered -- it reads 'Helvetica, ...' identically on a machine that
  // has Helvetica and one that does not. The only portable way to ask is to
  // measure: render the same string in the candidate and in a family that
  // certainly does not exist, and see whether the widths agree. Equal widths mean
  // the candidate fell back too.
  const probe = (family) => {
    const c = document.createElement('canvas').getContext('2d');
    c.font = `16px ${family}`;
    return c.measureText('Tonight at Ophelia \\u25B6 248 $61,400').width;
  };
  const missing = probe('__no_such_family__');
  const stack = getComputedStyle(document.body).fontFamily;
  const first = stack.split(',')[0].replace(/["']/g, '').trim();
  // NOT "is Helvetica installed". fontconfig aliases unknown families to a
  // substitute, so this came back true on a Linux box with no Helvetica at all:
  // the alias target and the default family are simply two different faces.
  // The honest signal is the WIDTH -- 239.15 px here, and whatever the other
  // machine reports -- because two runs whose widths differ did not render the
  // same page, whatever either of them calls the font.
  return { stack, first, distinct_from_default_fallback: probe(first) !== missing,
           width_px: +probe(first).toFixed(2) };
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
    font_probe = None
    with sync_playwright() as p:
        # The instrument must be nameable. `channel="chromium"` resolves to whatever
        # Playwright installed for its own version, which is right on a dev machine
        # and wrong anywhere the browser was provisioned separately (CI images pin a
        # build number; a version skew fails the launch outright, not the render). An
        # explicit path is the escape hatch, and it is recorded in the run so a
        # geometric finding can always name the binary that produced it.
        exe = os.environ.get("BENCH_CHROMIUM")
        launcher = {"executable_path": exe} if exe else {"channel": "chromium"}
        browser = p.chromium.launch(
            **launcher,
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
            if dpr == dprs[0]:
                page.goto(pages[0].as_uri(), wait_until="load")
                font_probe = page.evaluate(FONT_PROBE_JS)
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
        # Provenance, written once per capture and read by every scorer.
        #
        # 🚨 Every pixel-derived number in this bench is a number about ONE
        # render, and the render is not the same on two machines. Measured
        # 2026-09-04: `findings_dom.json` came back byte-identical to the run
        # committed from an M1 Max -- the DOM layer is machine-independent -- and
        # the X3 contrast numbers moved from 4.81/1.57 to 6.15/1.76 on the same
        # page, because Helvetica does not exist on Linux and the fallback face
        # has different metrics and a different antialiasing rim. The verdict
        # held; the number did not. Without this file the next person to see two
        # different numbers has to re-derive which machine each came from, which
        # is exactly the work this line of JSON deletes.
        (corpus / "run.json").write_text(
            json.dumps(
                {
                    "captured": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                    "platform": f"{platform.system()} {platform.machine()}",
                    "browser": browser.version,
                    "executable": exe or "playwright channel=chromium",
                    "dprs": dprs,
                    "viewport": vp,
                    "pages": [p.stem for p in pages],
                    # The one variable that moved every pixel number between the
                    # two machines this corpus has run on.
                    "font": font_probe,
                },
                indent=1,
            )
        )
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
