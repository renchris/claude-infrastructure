#!/usr/bin/env python3
"""hero-film-encode-loop.py: encode the README loop's frames into one animated WebP.

Adapted from agent-context-sync scripts/film-encode-loop.py (round 3, approved 2026-09-24).

    python3 scripts/hero-film-encode-loop.py FRAMES_DIR OUT.webp [--hold nl|q<N>] [--flight q<N>]

FRAMES_DIR holds the loop's frames (f000000.png ...) at the README size, every one at 60 fps since
round two. The meta.json the capture wrote (looked for in FRAMES_DIR and its parent) gives each
frame's time and names the flights, the spans where the camera moves.

Why the frames are not all encoded alike. Animated WebP has no motion compensation, so a frame costs
what its changed pixels cost. While the camera holds still almost nothing changes, and those frames
keep the type crisp. While it flies every pixel changes, so a flight is stored lossy and motion blur
hides the loss. Measured on round two's longest flight at 1676 x 943 and 60 fps: 0.8-1.0 MB a second
lossy, whatever the quality (q20 to q40 moved it 24 %), so a flight's cost is its length.

Identical consecutive frames (a held shot while nothing moves) are stored once, with their durations
summed: a 60 fps hold would otherwise be hundreds of empty frames for the decoder to walk.

Why the frames are assembled here and not by img2webp (round two). libwebp's animation encoder stores
only the rectangle that changed, and a pixel counts as unchanged when it differs from the PREVIOUS
SOURCE frame by less than a quality-derived threshold (about 15 levels at q30). At 60 fps a slow camera
changes the dark floor by less than that each frame, so those regions were never re-sent and the drift
added up: 469 of 1,413 stored frames of round two's first 60 fps encode had solid stale patches, up to
106 levels off (a stepped floor glow, a doubled sign). Round one's 20 fps flights moved enough per frame
to hide it. So this script decides each frame itself, against the DECODED canvas, where error is
bounded:
  - a flight frame is stored whole, lossy (a full 1676 x 943 frame at q30 is 9-15 KB, the same as the
    changed rectangles img2webp was writing, so it costs nothing and cannot drift);
  - the first frame of every hold is stored whole at the hold's quality (near-lossless for the poster),
    so each held shot lands crisp whatever the flight before it left behind;
  - a later hold frame stores only the rectangle where the source has changed by more than DRIFT
    levels since that pixel was last stored. The reference is the SOURCE as it was when stored, not the
    decoded canvas: the codec's own error on a sharp edge is static and can exceed DRIFT at q90, and
    measuring against the canvas re-sent those edges on every frame (39 MB, measured). Slow change
    still adds up against the reference, so it is re-sent once it passes DRIFT. Moving pixels are
    stored at --move quality; once a pixel stored that way has been still for SETTLE frames it is
    re-sent at --hold quality, so type that stands to be read is always stored crisp.
Frames are encoded with cwebp, decoded back to track the canvas, and muxed with webpmux.

Writes FRAMES_DIR/encode.json, the plan (each stored frame's file, time, duration and mode), so
hero-film-verify.py can check each stored frame against its own source, the way it was encoded.
"""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("frames", type=Path)
ap.add_argument("out", type=Path)
ap.add_argument("--hold", default="nl", help="nl (near-lossless 60) or q<N> (lossy at quality N)")
ap.add_argument("--flight", default="q55", help="q<N>: lossy quality of the frames in a flight")
ap.add_argument("--move", default="q75", help="q<N>: lossy quality of what moves inside a hold (refined to --hold once still)")
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


import tempfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

DRIFT = 3  # levels: a held pixel is re-sent once its source has moved more than this since it was stored
SETTLE = 6  # frames: a pixel stored at --move quality is refined to --hold once still this long


def rgb(path):
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"), dtype=np.int16)


plan = []
last = None
for k, (f, t) in enumerate(zip(frames, times)):
    n = flight_of(t)
    # The first frame of each span the page marks nearLossless (the poster holds) is stored
    # near-lossless, whatever --hold says: frame 0, and the poster re-sent whole after the flight home,
    # so the seam decodes the same both times. The rest of such a hold changes only where the ambient
    # commits crawl, and that small region is stored at --hold.
    first_nl = any(abs(t - f0) < 0.5 / meta.get("fps", 60) for f0, f1 in near_lossless)
    mode = a.flight if n is not None else "nl" if first_nl else a.hold
    with Image.open(f) as im:
        digest = hashlib.blake2b(im.convert("RGB").tobytes(), digest_size=16).digest()
    if digest == last and plan and plan[-1]["mode"] == mode:
        plan[-1]["ms"] += ms[k + 1] - ms[k]  # the same picture again: hold the stored frame longer
        continue
    last = digest
    poster = any(f0 - 1e-9 <= t < f1 - 1e-9 for f0, f1 in near_lossless)
    plan.append({"file": f.name, "t": round(t, 4), "ms": ms[k + 1] - ms[k], "mode": mode, "flight": n, "poster": poster})

tmp = Path(tempfile.mkdtemp(prefix="hero-encode-"))


def cwebp(src, dst, mode, crop=None, flight=False):
    args = ["cwebp", "-quiet", "-m", str(a.method), "-metadata", "none"]
    args += ["-lossless", "-near_lossless", "60", "-exact"] if mode == "nl" else ["-q", mode[1:], "-sharp_yuv"]
    if flight:
        # Strongest noise shaping and deblocking: 3-11 % smaller on a flight frame (measured), and the
        # softening they add is hidden by the motion blur.
        args += ["-sns", "100", "-f", "60"]
    if crop:
        x, y, w, h = crop
        args += ["-crop", str(x), str(y), str(w), str(h)]
    subprocess.run([*args, str(src), "-o", str(dst)], check=True)
    return rgb(dst)


# Pass 1, in parallel: every frame stored whole (flights, and the first frame of each hold).
whole = [i for i, p in enumerate(plan) if p["flight"] is not None or i == 0 or plan[i - 1]["flight"] is not None or p["mode"] == "nl"]
with ThreadPoolExecutor(8) as ex:
    decoded = dict(zip(whole, ex.map(lambda i: cwebp(a.frames / plan[i]["file"], tmp / f"{i:05d}.webp", plan[i]["mode"], flight=plan[i]["flight"] is not None), whole)))
# Pass 2, in order: the rest of each hold, as the rectangle that changed, against the decoded canvas.
ref = None  # the source as it was when each pixel was last stored
low = None  # pixels last stored at --move quality
still = None  # frames since each pixel's source last changed
prev = None
kept = None
mux = []
for i, p in enumerate(plan):
    src = rgb(a.frames / p["file"])
    if prev is not None:
        still = np.where(np.abs(src - prev).max(axis=2) > 1, 0, still + 1)
    prev = src
    if i in decoded:
        ref = src
        low = np.zeros(src.shape[:2], bool)
        still = np.zeros(src.shape[:2], np.int32)
        rect = (0, 0, src.shape[1], src.shape[0])
    else:
        changed = np.abs(src - ref).max(axis=2) > DRIFT
        refine = low & (still >= SETTLE)
        if refine.any():
            p["mode"] = a.hold  # the still part comes back crisp; what moves rides along at the same quality
        elif p["mode"] != "nl" and p["flight"] is None and not p.get("poster"):
            # The poster holds keep --hold even for what moves (the crawling commits): the loop point
            # joins a closing-hold frame to frame 0, and a q75 crawl there sharpened at the seam (773 px
            # in the light grade, against ~240 for an ordinary step).
            p["mode"] = a.move
        ys, xs = np.nonzero(changed | refine)
        if len(xs) == 0:
            mux[-1][1] += p["ms"]  # nothing to send: the stored frame before it holds longer
            kept["ms"] += p["ms"]
            p["merged"] = True
            continue
        x0, y0 = int(xs.min()) & ~1, int(ys.min()) & ~1  # WebP stores frame offsets halved
        rect = (x0, y0, int(xs.max()) + 1 - x0, int(ys.max()) + 1 - y0)
        x, y, w, h = rect
        cwebp(a.frames / p["file"], tmp / f"{i:05d}.webp", p["mode"], rect)
        ref = ref.copy()
        ref[y : y + h, x : x + w] = src[y : y + h, x : x + w]
        low[y : y + h, x : x + w] = p["mode"] == a.move
    p["rect"] = list(rect)
    kept = p
    mux.append([tmp / f"{i:05d}.webp", p["ms"], rect])

args = []
for f, d, (x, y, _, _) in mux:
    args += ["-frame", str(f), f"+{d}+{x}+{y}+0-b"]
subprocess.run(["webpmux", *args, "-loop", "0", "-bgcolor", "255,255,255,255", "-o", str(a.out)], check=True, stdout=subprocess.DEVNULL)
plan = [p for p in plan if not p.get("merged")]
(a.frames / "encode.json").write_text(json.dumps({"hold": a.hold, "move": a.move, "flight": a.flight, "drift": DRIFT, "settle": SETTLE, "plan": plan}) + "\n")
n_fl = sum(1 for p in plan if p["flight"] is not None)
print(f"{a.out}: {a.out.stat().st_size} bytes, {len(plan)} stored frames ({n_fl} in flights), {sum(p['ms'] for p in plan)} ms")
