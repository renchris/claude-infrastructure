#!/usr/bin/env python3
"""Recreate the BMO battery-swap clip as clawd, frame by frame, and encode the loop.

    python3 tools/banner/clawdify.py --ref ~/Development/.banner-ref --out assets/demo

WHY THIS AND NOT A VECTOR BANNER. Three attempts to hand-draw the scene missed on silhouette, and a
fourth — tracing the frames into flat vector and swapping six poses — was faithful per pose but a
SLIDESHOW: `banner-verify`'s ALIVE check measured 3 distinct images across a 3-second window, which is
exactly what it is there to catch. The source is 178 frames of continuous cel animation. Six vector
poses cannot represent that, and 178 of them would be megabytes.

The insight that makes this easy: turning BMO into clawd is a RECOLOUR, and a recolour is a per-pixel
operation. So every frame of the real clip gets it, motion and all, and the result is the clip's own
timing rather than an approximation of it.

HOW THE RECOLOUR PICKS ITS PIXELS. Not by snapping to a palette — that was tried and it shattered the
antialiased fringe into speckle, because a fringe pixel between teal and ink lands nearest to some
unrelated dark entry. This works in HSV and selects by HUE BAND, which the fringe shares with the body
it fringes, so the fringe is recoloured smoothly along with it and no speckle can appear. The bands are
far enough apart to be safe:

    body teal   ~178-190 deg   -> becomes clawd orange     (#1A5657, #22696A, #16494B and fringes)
    ground blue ~194-205 deg   -> untouched
    screen mint ~160-170 deg   -> untouched, so BMO's lit face stays its own colour

Value is preserved, so the source's three shading steps survive the shift for free — the box still
reads as a box, lit exactly as the original was.
"""

from __future__ import annotations

import argparse
import colorsys
import pathlib
import shutil
import subprocess
import tempfile

import numpy as np
from PIL import Image

# The hue window that is BMO's body, in degrees, plus the saturation floor that keeps the near-grey
# outline out of it. Measured off the frames: body #1A5657 is hue 181, #22696A is 181, #16494B is 184;
# the ground #023A50 is 199 and the lit screen #4A9C89 is 166.
BODY_HUE = (172.0, 191.0)
BODY_SAT_MIN = 0.18
CLAWD_HUE = 17.0  # #D77757
CLAWD_SAT = (
    0.60  # the source's teal is more saturated than clawd; hold it near clawd's own
)

# The broadcast overlays, inpainted by smearing the row just above each.
OVERLAYS = ((926, 54, 1192, 140), (1046, 564, 1200, 680))


def clawdify(im: Image.Image) -> Image.Image:
    """Shift BMO's body hue to clawd's, keeping value so the shading survives."""
    a = np.asarray(im, dtype=np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = a.max(2), a.min(2)
    d = mx - mn
    # hue, in degrees, computed inline — colorsys is per-pixel and this is 900k of them per frame
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rm, gm, bm = (mx == r) & nz, (mx == g) & nz, (mx == b) & nz
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = ((b - r)[gm] / d[gm]) + 2
    h[bm] = ((r - g)[bm] / d[bm]) + 4
    h *= 60.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)

    sel = (h >= BODY_HUE[0]) & (h <= BODY_HUE[1]) & (s >= BODY_SAT_MIN)
    if not sel.any():
        return im
    out = a.copy()
    # rebuild only the selected pixels, at clawd's hue and saturation, with their own value kept
    v = mx[sel]
    hh = np.full(v.shape, CLAWD_HUE / 360.0, dtype=np.float32)
    ss = np.full(v.shape, CLAWD_SAT, dtype=np.float32)
    conv = np.array(
        [
            colorsys.hsv_to_rgb(float(x), float(y), float(z))
            for x, y, z in zip(hh, ss, v)
        ],
        dtype=np.float32,
    )
    out[sel] = conv
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGB")


def inpaint_overlays(im: Image.Image) -> Image.Image:
    for x0, y0, x1, y1 in OVERLAYS:
        row = im.crop((x0, y0 - 2, x1, y0 - 1)).resize(
            (x1 - x0, y1 - y0), Image.NEAREST
        )
        im.paste(row, (x0, y0))
    return im


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--ref", default=str(pathlib.Path.home() / "Development/.banner-ref")
    )
    ap.add_argument("--out", default="assets/demo")
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--width", type=int, default=960)
    args = ap.parse_args()

    ref = pathlib.Path(args.ref)
    frames = sorted((ref / "hi").glob("h*.png"))
    if not frames:
        raise SystemExit(
            f"clawdify: no frames under {ref}/hi — extract them first:\n"
            f"  ffmpeg -i {ref}/bmo.webm -vf fps={args.fps} {ref}/hi/h%03d.png"
        )
    for tool in ("ffmpeg", "img2webp"):
        if not shutil.which(tool):
            raise SystemExit(f"clawdify: {tool} is not on PATH")

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        made = []
        for i, f in enumerate(frames):
            im = clawdify(inpaint_overlays(Image.open(f).convert("RGB")))
            w = args.width
            im = im.resize((w, round(w * im.height / im.width)), Image.LANCZOS)
            dst = work / f"c{i:04d}.png"
            im.save(dst)
            made.append(dst)
        if not made:
            raise SystemExit("clawdify: produced no frames")

        mp4 = out / "recycle-bmo.mp4"
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-loglevel",
                "error",
                "-framerate",
                str(args.fps),
                "-i",
                str(work / "c%04d.png"),
                "-vf",
                "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-crf",
                "20",
                "-movflags",
                "+faststart",
                "-an",
                str(mp4),
            ],
            check=True,
        )
        # Animated WebP for the README's inline slot: GitHub strips <video> but serves an animated
        # WebP byte-identical through camo. NEAR-LOSSLESS, not lossy — see the demo-recording skill:
        # ordinary lossy WebP encodes each frame as a partial update rectangle and re-quantizes flat
        # regions differently inside it, leaving a visible seam at its edge. This clip is almost
        # entirely flat night ground, i.e. the worst case for that artifact.
        webp = out / "recycle-bmo.webp"
        subprocess.run(
            [
                "img2webp",
                "-loop",
                "0",
                "-d",
                str(round(1000 / args.fps)),
                "-near_lossless",
                "40",
                "-m",
                "6",
                *[str(m) for m in made],
                "-o",
                str(webp),
            ],
            check=True,
        )

    for p in (mp4, webp):
        if not p.exists() or p.stat().st_size == 0:
            raise SystemExit(f"clawdify: {p} was not produced")
    dur = len(made) / args.fps
    print(f"{len(made)} frames @ {args.fps} fps · {dur:.2f}s loop")
    for p in (mp4, webp):
        print(f"   {p}  {p.stat().st_size / 1024:,.0f} KB")


if __name__ == "__main__":
    main()
