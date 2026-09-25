#!/usr/bin/env python3
"""hero-film-encode-loop.py: encode the README loop's frames into one animated WebP.

Adapted from agent-context-sync scripts/film-encode-loop.py (round 3, approved 2026-09-24).

    python3 scripts/hero-film-encode-loop.py FRAMES_DIR OUT.webp [--hold nl|q<N>] [--flight q<N>]

FRAMES_DIR holds the loop's frames (f000000.png ...) at the README size. The meta.json the capture
wrote (looked for in FRAMES_DIR and its parent) gives each frame's time and names the flights, the
spans where the camera moves; hero-film-capture.mjs --flight-fps samples those at 20 fps instead of 30.

Why the frames are not all encoded alike. Animated WebP has no motion compensation, so a frame costs
what its changed pixels cost. While the camera holds still almost nothing changes, and those frames
keep the type crisp. While it flies every pixel changes, so a flight is stored lossy, at 20 fps, and
motion blur hides both. Measured on round 3's flights at 1676 x 943: about 7 MB a second
near-lossless against about 1 MB a second lossy.

Writes FRAMES_DIR/encode.json, the plan (each stored frame's file, time, duration and mode), so
hero-film-verify.py can check each stored frame against its own source, the way it was encoded.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("frames", type=Path)
ap.add_argument("out", type=Path)
ap.add_argument("--hold", default="nl", help="nl (near-lossless 60) or q<N> (lossy at quality N)")
ap.add_argument("--flight", default="q55", help="q<N>: lossy quality of the frames in a flight")
ap.add_argument("--method", type=int, default=6)
a = ap.parse_args()

meta_path = next((p for p in (a.frames / "meta.json", a.frames.parent / "meta.json") if p.exists()), None)
if not meta_path:
    sys.exit(f"no meta.json in {a.frames} or its parent")
meta = json.loads(meta_path.read_text())
frames = sorted(a.frames.glob("f*.png"))
times = meta.get("times") or [k / meta.get("fps", 30) for k in range(len(frames))]
if len(times) != len(frames):
    sys.exit(f"{len(frames)} frames but meta.json lists {len(times)} times")
ms = [round(t * 1000) for t in times] + [round(meta["duration"] * 1000)]
flights = meta.get("flights", [])
near_lossless = meta.get("nearLossless", [])


def flight_of(t):
    return next((n for n, (f0, f1) in enumerate(flights) if f0 - 1e-9 <= t < f1 - 1e-9), None)


plan = []
for k, (f, t) in enumerate(zip(frames, times)):
    n = flight_of(t)
    # The spans the page marks nearLossless (the poster holds) are, whatever --hold says.
    mode = a.flight if n is not None else "nl" if any(f0 - 1e-9 <= t < f1 - 1e-9 for f0, f1 in near_lossless) else a.hold
    plan.append({"file": f.name, "t": round(t, 4), "ms": ms[k + 1] - ms[k], "mode": mode, "flight": n})

args = ["-loop", "0", "-near_lossless", "60", "-min_size"]
for p in plan:
    args += ["-d", str(p["ms"])]
    args += ["-lossless"] if p["mode"] == "nl" else ["-lossy", "-q", p["mode"][1:]]
    args += ["-m", str(a.method), str(a.frames / p["file"])]
subprocess.run(["img2webp", *args, "-o", str(a.out)], check=True, stdout=subprocess.DEVNULL)
(a.frames / "encode.json").write_text(json.dumps({"hold": a.hold, "flight": a.flight, "plan": plan}) + "\n")
n_fl = sum(1 for p in plan if p["flight"] is not None)
print(f"{a.out}: {a.out.stat().st_size} bytes, {len(plan)} stored frames ({n_fl} in flights), {sum(p['ms'] for p in plan)} ms")
