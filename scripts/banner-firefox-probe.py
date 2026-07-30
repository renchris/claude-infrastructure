#!/usr/bin/env python3
"""Does a CSS @keyframes animation inside an <img>-loaded SVG ADVANCE OVER TIME in Firefox?

Mozilla bug 1190881 says no: SVGDocumentWrapper::IsAnimated only checks for SMIL, so a CSS-only
VectorImage is never added to the refresh driver. If that still holds, our banner is a STATIC IMAGE
for every Firefox reader and a Chromium-only harness would never notice.

A single screenshot cannot answer this. Compositing the animation's t=0 value (which Firefox does —
measured separately) only proves the animation is APPLIED, not that the clock TICKS. And two separate
page loads cannot answer it either, because the timeline anchors at load, so both land at t≈0.

So: drive one document with Marionette (Firefox's own automation protocol), and screenshot TWICE
within its lifetime, straddling a hard colour flip. Different => the clock ticks. Identical => static.
SMIL runs as the positive control: it MUST animate in <img> on every engine, so if SMIL also reads
static the harness is broken rather than the finding confirmed.
"""

import base64
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

FF = (
    "/Users/chrisren/Library/Caches/ms-playwright/firefox-1497/"
    "firefox/Nightly.app/Contents/MacOS/firefox"
)
PORT = 2829
# Probe fixtures are generated into a scratch dir; nothing here reads the real assets, because the
# question is about the ENGINE, not about our art.
WORK = Path(os.environ.get("BANNER_FF_WORK", "/tmp/banner-ff-probe"))


def _centre(png: Path) -> str:
    """The centre pixel, or a distinct sentinel per failure so a bad read can never read as equal."""
    if not (png.is_file() and png.stat().st_size):
        return f"MISSING:{png.name}"
    r = subprocess.run(["magick", str(png), "-format", "%[pixel:p{100,50}]", "info:"],
                       capture_output=True, text=True)
    out = r.stdout.strip()
    return out if out else f"UNREADABLE:{png.name}"


class Marionette:
    def __init__(self, port: int) -> None:
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=30)
        self.msgid = 0
        self._recv()  # server handshake

    def _recv(self) -> dict:
        length = b""
        while not length.endswith(b":"):
            c = self.sock.recv(1)
            if not c:
                raise RuntimeError("marionette closed the connection")
            length += c
        n = int(length[:-1])
        buf = b""
        while len(buf) < n:
            buf += self.sock.recv(n - len(buf))
        return json.loads(buf)

    def cmd(self, name: str, params: dict | None = None):
        self.msgid += 1
        payload = json.dumps([0, self.msgid, name, params or {}]).encode()
        self.sock.sendall(f"{len(payload)}:".encode() + payload)
        msg = self._recv()
        if msg[2] is not None:
            raise RuntimeError(f"{name} failed: {msg[2]}")
        return msg[3]


FLIP_CSS = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" width="200" height="100"><style>
@keyframes flip{0%,49.999%{fill:#ff0000}50%,100%{fill:#0000ff}}
.c{animation:flip 2s steps(1,end) infinite}
</style><rect class="c" width="200" height="100" fill="#ff0000"/></svg>"""

FLIP_SMIL = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" width="200" height="100">
<rect width="200" height="100" fill="#ff0000">
<animate attributeName="fill" values="#ff0000;#0000ff" keyTimes="0;0.5" dur="2s" repeatCount="indefinite" calcMode="discrete"/>
</rect></svg>"""

PAGE = ('<!doctype html><meta charset="utf-8">'
        '<style>html,body{margin:0}img{width:200px;display:block}</style>'
        '<img src="file://%s" width="200">')


def write_fixtures() -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    for name, svg in (("css", FLIP_CSS), ("smil", FLIP_SMIL)):
        sp = WORK / f"flip-{name}.svg"
        sp.write_text(svg)
        (WORK / f"flip-{name}.html").write_text(PAGE % sp)


def main() -> int:
    write_fixtures()
    profile = WORK / "mprof"
    profile.mkdir(parents=True, exist_ok=True)
    (profile / "user.js").write_text(
        'user_pref("marionette.port", %d);\n'
        'user_pref("browser.shell.checkDefaultBrowser", false);\n' % PORT
    )

    proc = subprocess.Popen(
        [FF, "--headless", "--marionette", "--profile", str(profile), "about:blank"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        client = None
        for _ in range(60):  # marionette needs a moment to bind
            try:
                client = Marionette(PORT)
                break
            except OSError:
                time.sleep(0.5)
        if client is None:
            print("  NOT PROVEN — marionette never accepted a connection")
            return 2
        client.cmd("WebDriver:NewSession", {"capabilities": {}})

        print(
            "  Two screenshots inside ONE document, 1.2s apart, across a 2s hard flip.\n"
        )
        print(f"  {'probe':6s} {'shot A':22s} {'shot B':22s} verdict")
        results = {}
        for probe in ("css", "smil"):
            client.cmd(
                "WebDriver:Navigate", {"url": f"file://{WORK}/flip-{probe}.html"}
            )
            time.sleep(0.4)  # let first paint settle
            a = client.cmd("WebDriver:TakeScreenshot", {"full": False})["value"]
            time.sleep(1.2)  # crosses the flip at t=1.0s
            b = client.cmd("WebDriver:TakeScreenshot", {"full": False})["value"]
            for tag, data in (("a", a), ("b", b)):
                (WORK / f"mar-{probe}-{tag}.png").write_bytes(base64.b64decode(data))
            # Compare PIXELS, never the base64. Two encodings of an identical image can differ
            # byte-for-byte (this repo has already been bitten by a non-deterministic PNG encoder),
            # so a bytes-differ verdict would report ANIMATES on a static image.
            same = _centre(WORK / f"mar-{probe}-a.png") == _centre(WORK / f"mar-{probe}-b.png")
            results[probe] = not same
            print(
                f"  {probe:6s} {'sampled':22s} {'sampled':22s} "
                f"{'STATIC — did not advance' if same else 'ANIMATES — clock ticks'}"
            )

        print()
        if not results.get("smil"):
            print(
                "  CONTROL FAILED — SMIL did not animate either, so the harness is wrong,"
            )
            print(
                "  not the finding. Do not conclude anything about CSS from this run."
            )
            return 3
        if results.get("css"):
            print(
                "  RESULT: CSS @keyframes DOES advance in Firefox-as-image. Bug 1190881 does not"
            )
            print("  bite this build — the banner is NOT static for Firefox readers.")
        else:
            print(
                "  RESULT: CSS @keyframes is STATIC in Firefox-as-image while SMIL animates."
            )
            print(
                "  Bug 1190881 HOLDS. Every CSS animation in the banner must be re-expressed"
            )
            print("  in SMIL, or Firefox readers get a still image.")
        return 0
    finally:
        proc.terminate()


if __name__ == "__main__":
    sys.exit(main())
