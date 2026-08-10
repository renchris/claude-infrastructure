#!/usr/bin/env python3
"""Does a CSS @keyframes animation inside an <img>-loaded SVG ADVANCE OVER TIME in WebKit?

WebKit was the last unprobed engine, and it is the one with the largest unmeasured readership:
every Safari reader and every iOS reader of the README is on it. The banner's world clock is
expressed ENTIRELY in CSS `@keyframes` with no SMIL anywhere, so "does a CSS-only SVG-as-image ever
advance in WebKit" is the difference between four narrative beats and four static frames for that
whole population. Chromium was always covered; Firefox was covered by banner-firefox-probe.py,
against Mozilla bug 1190881 (VectorImage joins the refresh driver only for SMIL) — the same class of
engine-level defect is exactly what this asks WebKit.

THE ENGINE UNDER TEST IS THE SYSTEM ONE. tools/banner/webkit-probe.swift binds WKWebView, i.e. the
WebKit framework this macOS ships and Safari loads — not the Playwright webkit-2227 build sitting in
the cache, which no reader has. The UA string is printed and recorded with the result, because a
finding about an engine is only true of the build it was measured on.

WHY THE SHAPE OF THIS PROBE IS NOT NEGOTIABLE (inherited from the Firefox probe, and it is the same
question, so it uses THE SAME FIXTURES — imported, not retyped, because a second copy of the fixture
would let the two engines' verdicts drift apart while still looking comparable):

  * A single screenshot cannot answer it. Compositing the animation's t=0 value proves the animation
    was APPLIED, never that the clock TICKS.
  * Two page loads cannot answer it. The timeline anchors at load, so both land at t≈0 and a static
    engine produces the same pair as a ticking one.
  * So: ONE document, TWO samples inside its lifetime, straddling a hard colour flip.

THE CONTROLS, because "the frames are identical" has three causes and only one of them is a finding:

  1. SMIL is the positive control. It must animate in <img> on every engine. If SMIL also reads
     static, the HARNESS is broken and nothing may be concluded about CSS. Exit 3.
  2. Each frame must be ~uniformly ONE colour. A blank or half-drawn snapshot also compares equal,
     and would report STATIC for a perfectly healthy engine — the failure mode where a broken
     instrument's answer is a believable finding rather than an obvious error.
  3. That colour must be one of the two the fixture actually authors. A frame that is uniformly some
     third colour is not the fixture, so its equality says nothing. Both are exit 4.

Exit codes: 0 measured (read the printed RESULT) · 2 tooling absent · 3 control failed · 4 render
not trustworthy · 5 the instrument never returned a verdict.
"""

import base64
import importlib.util
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SWIFT_SRC = HERE.parent / "tools" / "banner" / "webkit-probe.swift"
WORK = Path(os.environ.get("BANNER_WK_WORK", "/tmp/banner-wk-probe"))

# Sample times, in ms from load, against the fixtures' 2 s period with its hard step at t=1.0 s.
# 400 ms lets first paint settle; 1600 ms is past the flip with 400 ms of margin on both sides, so
# neither sample sits near the boundary where a frame either side would be defensible.
SHOT_A_MS = 400
SHOT_B_MS = 1600

# The two colours the fixtures author. Classification is nearest-of-these with a distance ceiling,
# not equality: macOS colour-manages, so a pixel that survives the round trip may not be bit-exact,
# while red and blue stay separated by an enormous margin.
PALETTE = {"RED": (255, 0, 0), "BLUE": (0, 0, 255)}
MAX_DIST = 96  # far tighter than the 255*sqrt(3) between the two, far looser than exact
MIN_UNIFORM = 0.90  # the fixture's rect fills the whole viewport


def _fixtures() -> tuple[str, str]:
    """The Firefox probe's own FLIP_CSS / FLIP_SMIL, loaded by path (the module name is hyphenated).

    Shared deliberately. The two probes exist to be READ TOGETHER — "Chromium yes, Firefox yes,
    WebKit ?" is only a sentence if all three were asked the identical question. A retyped fixture
    is a third copy of one fact and would rot the way this repo has already had a fact rot.
    """
    src = HERE / "banner-firefox-probe.py"
    spec = importlib.util.spec_from_file_location("banner_firefox_probe", src)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load fixtures from {src}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.FLIP_CSS, mod.FLIP_SMIL


def _page(svg: str) -> str:
    """The fixture as a data: URI in <img>. That is SVG-as-image by construction — the same mode
    GitHub puts the banner in — and it takes file-origin rules out of the question entirely."""
    b64 = base64.b64encode(svg.encode()).decode()
    return (
        '<!doctype html><meta charset="utf-8">'
        "<style>html,body{margin:0;background:#000}img{width:200px;height:100px;display:block}"
        "</style>"
        f'<img src="data:image/svg+xml;base64,{b64}" width="200" height="100">'
    )


def _dominant(png: Path) -> tuple[str, float, str]:
    """(classified colour, its share of the frame, a human note).

    Reads the HISTOGRAM rather than one pixel. A single-pixel read cannot distinguish a fully
    painted frame from one that happens to be painted only where the sample landed, and this frame
    is one flat rect, so uniformity is a fact worth asserting rather than assuming.
    """
    if not (png.is_file() and png.stat().st_size):
        return ("MISSING", 0.0, f"{png.name} absent or empty")
    r = subprocess.run(
        ["magick", str(png), "-depth", "8", "-format", "%c", "histogram:info:"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return ("UNREADABLE", 0.0, f"magick failed on {png.name}")
    best, total = None, 0
    for line in r.stdout.splitlines():
        m = re.search(r"^\s*(\d+):\s*\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)", line)
        if not m:
            continue
        count = int(m.group(1))
        rgb = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
        total += count
        if best is None or count > best[0]:
            best = (count, rgb)
    if best is None or total == 0:
        return ("UNREADABLE", 0.0, f"no histogram parsed from {png.name}")
    share = best[0] / total
    rgb = best[1]
    name, dist = min(
        (
            (n, sum((a - b) ** 2 for a, b in zip(rgb, v)) ** 0.5)
            for n, v in PALETTE.items()
        ),
        key=lambda t: t[1],
    )
    if dist > MAX_DIST:
        return ("UNRECOGNISED", share, f"rgb{rgb} is not a fixture colour")
    return (name, share, f"rgb{rgb}")


class Unusable(Exception):
    """The pair of frames cannot support ANY comparison, so their equality is not evidence.

    Carries a machine-readable `reason` as well as prose, because --self-test has to require the
    SPECIFIC guard to fire. Keying a red-proof on a non-zero exit lets an unrelated earlier failure
    counterfeit a pass — the discipline banner-gate-redproof.py already enforces for the build gates.
    """

    def __init__(self, reason: str, lines: list[str]) -> None:
        super().__init__(reason)
        self.reason = reason
        self.lines = lines


class HarnessFailed(Exception):
    """The Swift tool never returned verdict=OK — it did not measure, so there is nothing to read."""

    def __init__(self, token: str, lines: list[str]) -> None:
        super().__init__(token)
        self.token = token
        self.lines = lines


def _ensure_tooling() -> Path:
    """Compile the harness, or raise with the reason. Returns the binary's path."""
    for tool in ("magick", "swiftc"):
        if not shutil.which(tool):
            raise RuntimeError(f"{tool} is absent")
    if not SWIFT_SRC.is_file():
        raise RuntimeError(f"harness source missing: {SWIFT_SRC}")
    WORK.mkdir(parents=True, exist_ok=True)
    binary = WORK / "webkit-probe"
    # Compiled, never interpreted — see the 🚨 at the head of webkit-probe.swift.
    build = subprocess.run(
        ["swiftc", "-O", str(SWIFT_SRC), "-o", str(binary)],
        capture_output=True,
        text=True,
    )
    if build.returncode != 0:
        last = (build.stderr.strip().splitlines() or ["(no stderr)"])[-1]
        raise RuntimeError(f"the harness did not compile: {last}")
    return binary


def _sample(binary: Path, name: str, svg: str) -> tuple[str, str, float, str]:
    """Render one fixture twice inside one document. Returns (colourA, colourB, uniformity, ua).

    Raises HarnessFailed if the instrument did not run, Unusable if what it rendered is not the
    fixture. Neither is a finding about the engine, and keeping them as exceptions is what stops
    them being read as one.
    """
    (WORK / f"flip-{name}.html").write_text(_page(svg))
    a, b = WORK / f"wk-{name}-a.png", WORK / f"wk-{name}-b.png"
    for p in (a, b):
        p.unlink(missing_ok=True)  # a stale frame must never be read as this run's
    run = subprocess.run(
        [
            str(binary),
            str(WORK / f"flip-{name}.html"),
            str(SHOT_A_MS),
            str(SHOT_B_MS),
            str(a),
            str(b),
        ],
        capture_output=True,
        text=True,
    )
    token, ua = "", ""
    for line in run.stdout.splitlines():
        if line.startswith("ua="):
            ua = ua or line[3:]
        elif line.startswith("verdict="):
            token = line[8:]
    if token != "OK":
        raise HarnessFailed(
            token or "NONE",
            [
                f"  {name}: the harness returned verdict={token or 'NONE'} (exit {run.returncode})",
                "   " + (run.stderr.strip().splitlines() or ["(no stderr)"])[-1],
            ],
        )
    ca, sa, na = _dominant(a)
    cb, sb, nb = _dominant(b)
    # Recognition BEFORE uniformity, so each cause reports itself: a missing frame scores 0%
    # uniform too, and "not uniform" would be a true sentence about the wrong defect.
    if ca not in PALETTE or cb not in PALETTE:
        raise Unusable(
            "off-palette",
            [
                f"  {name}: sampled {ca} ({na}) and {cb} ({nb}) — not the fixture's own colours,",
                "    so whether they match says nothing about the engine.",
            ],
        )
    if min(sa, sb) < MIN_UNIFORM:
        raise Unusable(
            "not-uniform",
            [
                f"  {name}: frames are not uniform ({sa:.0%} / {sb:.0%}) — the render is not the",
                "    fixture, so nothing it shows can be compared. Not a finding about the engine.",
            ],
        )
    return ca, cb, min(sa, sb), ua


def main() -> int:
    try:
        binary = _ensure_tooling()
    except RuntimeError as exc:
        print(f"  NOT PROVEN — {exc}")
        return 2

    flip_css, flip_smil = _fixtures()

    print(
        f"  Two snapshots inside ONE WKWebView document, at {SHOT_A_MS} ms and {SHOT_B_MS} ms"
    )
    print("  from load, across a hard flip at 1000 ms of a 2000 ms period.\n")

    ua = ""
    rows, verdicts = [], {}
    for probe, svg in (("css", flip_css), ("smil", flip_smil)):
        try:
            ca, cb, uniform, seen_ua = _sample(binary, probe, svg)
        except HarnessFailed as exc:
            print("\n".join(exc.lines))
            return 5
        except Unusable as exc:
            print("\n".join(exc.lines))
            return 4
        ua = ua or seen_ua
        verdicts[probe] = ca != cb
        rows.append((probe, ca, cb, uniform, uniform))

    print(f"  {'probe':6s} {'shot A':14s} {'shot B':14s} {'uniform':9s} verdict")
    for probe, ca, cb, sa, sb in rows:
        state = (
            "ANIMATES — clock ticks" if verdicts[probe] else "STATIC — did not advance"
        )
        print(f"  {probe:6s} {ca:14s} {cb:14s} {min(sa, sb):>7.0%}   {state}")
    if ua:
        print(f"\n  engine: {ua}")

    print()
    if not verdicts.get("smil"):
        print(
            "  CONTROL FAILED — SMIL did not animate either, so the harness is wrong, not the"
        )
        print("  finding. Do not conclude anything about CSS from this run.")
        return 3
    if verdicts.get("css"):
        print(
            "  RESULT: CSS @keyframes DOES advance in WebKit-as-image. The banner is NOT a still"
        )
        print("  image for Safari and iOS readers — all four beats play for them.")
    else:
        print(
            "  RESULT: CSS @keyframes is STATIC in WebKit-as-image while SMIL animates. Every"
        )
        print(
            "  Safari and iOS reader sees ONE frame. The world clock must be re-expressed in"
        )
        print("  SMIL, or those readers get a still.")
    return 0


# ── The red-proof ────────────────────────────────────────────────────────────────────────────────
# A probe that cannot fail is worse than none, which is the recorded reason --virtual-time-budget
# was deleted from this harness rather than left in as a verification mode that always agreed. The
# live run above reports ANIMATES; that sentence is worth nothing until this shows the same code
# reporting STATIC when the thing in front of it does not move, and refusing to report anything at
# all when what it rendered is not the fixture.
#
# Each case is keyed on its OWN reason, never on a non-zero exit — an unrelated earlier failure can
# counterfeit that, which is the trap banner-gate-redproof.py exists to avoid.

STATIC_RED = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" width="200" height="100">'
    '<rect width="200" height="100" fill="#ff0000"/></svg>'
)
OFF_PALETTE = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" width="200" height="100">'
    '<rect width="200" height="100" fill="#00c000"/></svg>'
)
HALVED = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" width="200" height="100">'
    '<rect width="100" height="100" fill="#ff0000"/>'
    '<rect x="100" width="100" height="100" fill="#0000ff"/></svg>'
)


def selftest() -> int:
    try:
        binary = _ensure_tooling()
    except RuntimeError as exc:
        print(f"  NOT PROVEN — {exc}")
        return 2

    # (label, what it must do, how to run it)
    print("  Each guard is required to fire, for its own stated reason.\n")
    print(f"  {'case':14s} {'required':34s} outcome")
    fails = 0

    def report(label: str, required: str, got: str, ok: bool) -> None:
        nonlocal fails
        if not ok:
            fails += 1
        print(f"  {label:14s} {required:34s} {'✓ ' if ok else '✗ '}{got}")

    # 1. THE ONE THAT MATTERS. A fixture that does not move must read STATIC. Without this, the
    #    live run's ANIMATES is unfalsifiable — it is what the probe would say either way.
    try:
        ca, cb, _, _ = _sample(binary, "selftest-static", STATIC_RED)
        moved = ca != cb
        report(
            "static-rect",
            "reads STATIC, not ANIMATES",
            "ANIMATES — the probe cannot report static" if moved else "STATIC",
            not moved,
        )
    except (Unusable, HarnessFailed) as exc:
        report(
            "static-rect",
            "reads STATIC, not ANIMATES",
            f"raised {type(exc).__name__}",
            False,
        )

    # 2. A frame that is uniformly some colour the fixture never authors is not the fixture, so its
    #    equality is not evidence either way.
    try:
        _sample(binary, "selftest-offpalette", OFF_PALETTE)
        report("off-palette", "refuses: off-palette", "returned a comparison", False)
    except Unusable as exc:
        report(
            "off-palette",
            "refuses: off-palette",
            exc.reason,
            exc.reason == "off-palette",
        )
    except HarnessFailed as exc:
        report("off-palette", "refuses: off-palette", f"harness {exc.token}", False)

    # 3. A half-drawn render also compares equal to itself. It must be refused as a render fault,
    #    not read as a static engine — the failure mode where a broken instrument's answer is a
    #    believable finding rather than an obvious error.
    try:
        _sample(binary, "selftest-halved", HALVED)
        report("half-drawn", "refuses: not-uniform", "returned a comparison", False)
    except Unusable as exc:
        report(
            "half-drawn",
            "refuses: not-uniform",
            exc.reason,
            exc.reason == "not-uniform",
        )
    except HarnessFailed as exc:
        report("half-drawn", "refuses: not-uniform", f"harness {exc.token}", False)

    # 4. When the instrument itself does not run, it must say so rather than emit frames. Pointed at
    #    a page that does not exist, the Swift tool owes a verdict token, not a silent exit 0.
    missing = WORK / "flip-selftest-absent.html"
    missing.unlink(missing_ok=True)
    run = subprocess.run(
        [
            str(binary),
            str(missing),
            str(SHOT_A_MS),
            str(SHOT_B_MS),
            str(WORK / "wk-absent-a.png"),
            str(WORK / "wk-absent-b.png"),
        ],
        capture_output=True,
        text=True,
    )
    token = next(
        (ln[8:] for ln in run.stdout.splitlines() if ln.startswith("verdict=")), "NONE"
    )
    report(
        "absent-page",
        "harness verdict != OK",
        f"verdict={token}",
        token not in ("OK", "NONE"),
    )

    print()
    if fails:
        print(
            f"  SELF-TEST FAILED — {fails} guard(s) did not fire. The probe's verdicts are not"
        )
        print(
            "  trustworthy until this is green: it has not shown it can return the other answer."
        )
        return 1
    print(
        "  SELF-TEST 4/4 — the probe can report STATIC, and refuses a render it cannot read."
    )
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--self-test" in sys.argv[1:] else main())
