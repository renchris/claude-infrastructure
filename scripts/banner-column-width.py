#!/usr/bin/env python3
"""banner-column-width.py — measure the README column the banner is actually rendered into.

The whole pixel scale of the banner hangs off one number: how wide is GitHub's markdown column?
`docs/research/prior-art.md` §E3 carried 830 px from a single 2025 blog measurement and flagged it
as un-re-measured. Re-measured here it is **838 px**, and the 8 px matters because §E3's
"415 x 130 art grid at 2x" recommendation rests on 830 / 415 == 2 exactly. 838 = 2 x 419 with 419
prime, so 415 does not divide it and the integer-scale plan does not survive the correction.

Two design rules for this probe, both learned the hard way in this track:

1. MEASURE THE REAL PAGE, never a local reconstruction of GitHub's CSS. A mock column proves what
   you already assumed about it. The URL is fetched live.
2. AGREE ACROSS INDEPENDENT PROBES, because one number that could be wrong is not a measurement.
   Three are taken per viewport — the article's clientWidth minus its padding, a width:100% element
   inserted into the real column, and the measured boxes of images GitHub already renders. They must
   agree; a disagreement means the selector drifted and the answer is not trustworthy.

Driven over CDP rather than via playwright's python package, which is not installed here (the
Chromium binary from the playwright cache is, and that is all this needs).

  scripts/banner-column-width.py
  scripts/banner-column-width.py --url https://github.com/owner/repo --viewports 1920,1280
"""

from __future__ import annotations

import argparse
import asyncio
import glob
import json
import subprocess
import sys
import tempfile
import time
import urllib.request

import websockets

DEFAULT_URL = "https://github.com/renchris/claude-infrastructure"
CHROME_GLOB = (
    "/Users/chrisren/Library/Caches/ms-playwright/chromium-*/chrome-mac/"
    "Chromium.app/Contents/MacOS/Chromium"
)

# Three independent reads of the same quantity, plus the images already on the page.
JS = r"""
(() => {
  const out = {dpr: window.devicePixelRatio, inner: window.innerWidth};
  const art = document.querySelector('article.markdown-body');
  if (!art) { out.err = 'no article.markdown-body — selector drifted'; return out; }
  const cs = getComputedStyle(art);
  out.client_minus_padding = art.clientWidth
      - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
  const probe = document.createElement('div');
  probe.style.width = '100%'; probe.style.height = '1px';
  art.prepend(probe);
  out.probe_100pct = probe.getBoundingClientRect().width;
  probe.remove();
  // Images GitHub renders at full column width are a third, independent witness.
  const w = [...art.querySelectorAll('img')]
      .map(i => Math.round(i.getBoundingClientRect().width));
  out.img_widths = w.slice(0, 12);
  out.img_max = w.length ? Math.max(...w) : null;
  return out;
})()
"""


def _chrome() -> str:
    found = sorted(glob.glob(CHROME_GLOB))
    if not found:
        sys.exit("banner-column-width: no playwright Chromium found")
    return found[-1]


async def _measure(ws_url: str, url: str, viewport: int, settle: float) -> dict:
    async with websockets.connect(ws_url, max_size=40_000_000) as ws:
        counter = [0]

        async def cmd(method: str, params: dict | None = None) -> dict:
            counter[0] += 1
            mid = counter[0]
            await ws.send(
                json.dumps({"id": mid, "method": method, "params": params or {}})
            )
            while True:
                msg = json.loads(await ws.recv())
                if msg.get("id") == mid:
                    return msg

        await cmd(
            "Emulation.setDeviceMetricsOverride",
            {
                "width": viewport,
                "height": 1000,
                "deviceScaleFactor": 2,
                "mobile": False,
            },
        )
        await cmd("Page.enable")
        await cmd("Page.navigate", {"url": url})
        await asyncio.sleep(settle)
        res = await cmd("Runtime.evaluate", {"expression": JS, "returnByValue": True})
        return res["result"]["result"].get("value") or {}


async def run(url: str, viewports: list[int], settle: float) -> int:
    port = 9333
    with tempfile.TemporaryDirectory(prefix="banner-colwidth-") as profile:
        proc = subprocess.Popen(
            [
                _chrome(),
                f"--remote-debugging-port={port}",
                "--headless=new",
                "--no-first-run",
                "--no-default-browser-check",
                "--hide-scrollbars",
                f"--user-data-dir={profile}",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            for _ in range(40):
                try:
                    urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/json/version", timeout=1
                    )
                    break
                except OSError:
                    time.sleep(0.4)
            else:
                print("banner-column-width: Chromium never came up", file=sys.stderr)
                return 1

            bad = 0
            for vp in viewports:
                # /json/new needs PUT on current Chromium; reuse the startup target instead.
                targets = json.load(
                    urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list")
                )
                pages = [t for t in targets if t.get("type") == "page"]
                if not pages:
                    print("banner-column-width: no page target", file=sys.stderr)
                    return 1
                r = await _measure(pages[0]["webSocketDebuggerUrl"], url, vp, settle)

                if "err" in r:
                    print(f"viewport {vp:5d}  FAIL  {r['err']}")
                    bad += 1
                    continue
                a, b, c = r["client_minus_padding"], r["probe_100pct"], r["img_max"]
                agree = a == b and (c is None or c == a)
                verdict = "agree" if agree else "DISAGREE"
                print(
                    f"viewport {vp:5d}  column {a:.0f} px  "
                    f"[clientWidth-padding {a:.0f} · width:100% {b:.0f} · widest img {c}]  {verdict}"
                )
                if not agree:
                    bad += 1
            if bad:
                print(
                    "\nbanner-column-width: probes disagreed — do not trust this number",
                    file=sys.stderr,
                )
            return 1 if bad else 0
        finally:
            proc.terminate()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default=DEFAULT_URL)
    ap.add_argument(
        "--viewports",
        default="1920,1512,1280,1024",
        help="comma-separated viewport widths to measure",
    )
    ap.add_argument(
        "--settle", type=float, default=6.0, help="seconds to let the page settle"
    )
    a = ap.parse_args()
    vps = [int(v) for v in a.viewports.split(",") if v.strip()]
    return asyncio.run(run(a.url, vps, a.settle))


if __name__ == "__main__":
    sys.exit(main())
