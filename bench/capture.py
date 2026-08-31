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
import platform
import pathlib
import sys
import time

from playwright.sync_api import sync_playwright

# On the authoring Mac the `chromium` channel resolves; in a container the browser
# is pre-placed and the pip playwright's expected revision may not match it. An
# explicit path is the only portable escape, and it stays opt-in so the Mac path
# is untouched.
CHROMIUM_EXECUTABLE = os.environ.get("BENCH_CHROMIUM_EXECUTABLE") or None

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


def capture_env(browser, page, sample: pathlib.Path, vp: dict, dprs: list) -> dict:
    """Record the instrument, so two findings files can never be silently compared.

    Findings are only comparable against the render environment that produced
    them, and the difference does not announce itself: this corpus pinned its
    font stack to `Helvetica, ...` for reproducibility, Helvetica exists only on
    macOS, and everywhere else the stack silently falls back. The corpus's
    optical-alignment ground truth was a constant measured against ONE
    rasteriser, so the same code scored a clean control on one machine and a
    false positive on another with no diff between them. The font is resolved
    through CDP rather than read off `font-family`, because getComputedStyle
    returns the stack that was ASKED for -- the question here is which face
    actually painted, and that is the only version of the question that would
    have caught this.
    """
    env = {
        "platform": platform.platform(),
        "python": platform.python_version(),
        "viewport": vp,
        "device_scale_factors": dprs,
        "force_device_scale_factor": max(dprs),
        "pinned": [
            "--force-color-profile=srgb",
            "--disable-lcd-text",
            "--hide-scrollbars",
            "reduced_motion=reduce",
            "color_scheme=light",
        ],
        "browser_version": browser.version,
        "executable": CHROMIUM_EXECUTABLE or "playwright channel: chromium",
        "resolved_fonts": "unavailable",
    }
    try:
        page.goto(sample.as_uri(), wait_until="load")
        cdp = page.context.new_cdp_session(page)
        cdp.send("DOM.enable")
        cdp.send("CSS.enable")
        root = cdp.send("DOM.getDocument")["root"]["nodeId"]
        node = cdp.send(
            "DOM.querySelector", {"nodeId": root, "selector": ".section-title"}
        )["nodeId"]
        fonts = cdp.send("CSS.getPlatformFontsForNode", {"nodeId": node})
        env["resolved_fonts"] = [
            {"family": f["familyName"], "glyphs": f["glyphCount"]}
            for f in fonts.get("fonts", [])
        ]
        cdp.detach()
    except Exception as exc:  # noqa: BLE001 -- provenance is best-effort, never fatal
        env["resolved_fonts"] = f"unavailable: {type(exc).__name__}: {exc}"
    return env


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

    timings: list = []
    env: dict = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel=None if CHROMIUM_EXECUTABLE else "chromium",
            executable_path=CHROMIUM_EXECUTABLE,
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
                env = capture_env(browser, page, pages[0], vp, dprs)
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

    (corpus / "capture_env.json").write_text(json.dumps(env, indent=1))

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
