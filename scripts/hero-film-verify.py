#!/usr/bin/env python3
"""hero-film-verify.py: check the SHIPPED hero loop, decoded from the WebP, not the frames it was made from.

Adapted from agent-context-sync scripts/film-verify.py (round 3, approved 2026-09-24).

    python3 scripts/hero-film-verify.py assets/hero/hero-dark.webp /tmp/cih-film/verify-dark [step] [source-dir]

Writes into the output directory:
  sheet.png       every 0.5 s of the loop as decoded, labelled with its time, 4 per row
  poster-838.png  frame 0 at the README column's width (838 CSS px)
and prints: stored frames, total duration (must be the loop length), and the seam, i.e. how many
pixels of the last frame differ from frame 0 by more than 15 % (0 means the loop point is invisible).
Given the directory of source frames the WebP was encoded from (with the encode.json plan that
scripts/hero-film-encode-loop.py writes there), it also checks every stored frame against its source,
where the 5x5 source neighbourhood is flat: a near-lossless frame must decode within 2/255 (encoder
rounding that survives a cut shows up as a ghost of the last shot), and a lossy one may not
hold a solid patch 24/255 or more away (its quantisation is allowed; a stale region is not).

Frame durations come from webpinfo, because Pillow mis-reports merged durations. Needs python3 with
Pillow and numpy, plus webpinfo (libwebp).
"""

import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

webp, out = Path(sys.argv[1]), Path(sys.argv[2])
step = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
src = Path(sys.argv[4]) if len(sys.argv) > 4 else None
out.mkdir(parents=True, exist_ok=True)

info = subprocess.run(
    ["webpinfo", str(webp)], capture_output=True, text=True, check=True
).stdout
durs = [int(d) for d in re.findall(r"Duration: (\d+)", info)]
starts = np.cumsum([0] + durs[:-1])
total = sum(durs)
print(f"{webp}: {len(durs)} stored frames, {total} ms, {webp.stat().st_size} bytes")

im = Image.open(webp)


def frame_at(ms):
    k = int(np.searchsorted(starts, ms, side="right") - 1)
    im.seek(max(0, k))
    return im.convert("RGB")


first = frame_at(0)
first.resize((838, round(838 * first.height / first.width)), Image.LANCZOS).save(
    out / "poster-838.png"
)
last = frame_at(total - 1)
a = np.asarray(first, dtype=np.int16)
b = np.asarray(last, dtype=np.int16)
seam = int((np.abs(a - b).max(axis=2) > 0.15 * 255).sum())
print(f"seam: {seam} px of the last frame differ from frame 0 by more than 15 %")

if src:
    from PIL import ImageFilter

    # Which source frame each stored frame was encoded from, and how. film-encode-loop.py writes the
    # plan; without one, the frames are taken to be 30 fps, all near-lossless (round 2's encoding).
    plan_path = src / "encode.json"
    plan = json.loads(plan_path.read_text())["plan"] if plan_path.exists() else None
    by_ms = {round(p["t"] * 1000): p for p in plan} if plan else {}

    def source_of(start):
        if plan is None:
            return src / f"f{round(start * 30 / 1000):06d}.png", "nl"
        p = by_ms.get(int(start)) or max((q for ms, q in by_ms.items() if ms <= start), key=lambda q: q["t"])
        return src / p["file"], p["mode"]

    # A near-lossless frame must decode within 2/255 wherever its source is flat: rounding that
    # survives a cut shows up here as a ghost of the last shot. A lossy frame is allowed its
    # quantisation, but not a stale region: no solid patch of flat source pixels may decode 24/255
    # or more away.
    counts = {"nl": [0, 0, (0, "none")], "lossy": [0, 0, (0, "none")]}
    for k, start in enumerate(starts):
        f, mode = source_of(start)
        if not f.exists():
            continue
        kind = "nl" if mode == "nl" else "lossy"
        im.seek(k)
        dec = np.asarray(im.convert("RGB"), dtype=np.int16)
        ref = Image.open(f).convert("RGB")
        grey = ref.convert("L")
        flat = np.asarray(grey.filter(ImageFilter.MaxFilter(5))) == np.asarray(
            grey.filter(ImageFilter.MinFilter(5))
        )
        err = np.abs(dec - np.asarray(ref, dtype=np.int16)).max(axis=2)
        if kind == "nl":
            n = int((err[flat] >= 3).sum())
        else:
            # Lossy ringing beside an edge is thin; a stale region is solid. Count only bad pixels
            # whose whole 3x3 neighbourhood is bad too (an erosion), so a ghost of the last shot
            # still counts and quantisation does not.
            bad = Image.fromarray(((err >= 24) & flat).astype(np.uint8) * 255)
            n = int((np.asarray(bad.filter(ImageFilter.MinFilter(3))) > 0).sum())
        c = counts[kind]
        c[0] += 1
        c[1] += n > 0
        c[2] = max(c[2], (n, f.name))
    for kind, (seen, bad, worst) in counts.items():
        if seen:
            lim = "3/255" if kind == "nl" else "24/255"
            print(
                f"ghost ({kind}): {bad} of {seen} stored frames have flat pixels off their source by >= {lim}"
                f" (worst {worst[0]} px, {worst[1]})"
            )

try:
    font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 22)
except OSError:
    font = ImageFont.load_default()
tiles = []
t = 0.0
while t * 1000 < total:
    f = frame_at(t * 1000).resize(
        (560, round(560 * first.height / first.width)), Image.LANCZOS
    )
    ImageDraw.Draw(f).text((8, 6), f"{t:.1f}", fill=(255, 0, 255), font=font)
    tiles.append(f)
    t += step
cols = 4
w, h = tiles[0].size
sheet = Image.new(
    "RGB", (cols * (w + 4), -(-len(tiles) // cols) * (h + 4)), (136, 136, 136)
)
for n, tile in enumerate(tiles):
    sheet.paste(tile, ((n % cols) * (w + 4), (n // cols) * (h + 4)))
sheet.save(out / "sheet.png")
print(f"wrote {out / 'sheet.png'} ({len(tiles)} frames) and {out / 'poster-838.png'}")
