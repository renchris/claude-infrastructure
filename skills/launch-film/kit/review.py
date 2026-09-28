#!/usr/bin/env python3
"""review.py: the three-zoom review of studio-method.md § 5, made from a rendered film.

  python3 review.py <video> <cues.json> <outdir>
    sheet-N.png   every 1.0 s of the film, 6×4 tiles at 480 px, so the sheets cover 100 % of the duration
    strip-<t>.png every frame from 0.3 s before to 0.5 s after each state change in the cue export (section, land,
                  state, live, chime, name), 12×4 tiles at 240 px
    manifest.json {duration, interval, tiles, changes, strips}, which picture_gate.py --review checks
The strips are for reading, not for scoring: the gate only proves they exist for every change."""

import json, subprocess, sys
from pathlib import Path

video, cues, out = (
    sys.argv[1],
    json.loads(Path(sys.argv[2]).read_text()),
    Path(sys.argv[3]),
)
out.mkdir(parents=True, exist_ok=True)
dur, fps = float(cues["duration"]), float(cues["fps"])
ff = lambda *a: subprocess.run(
    ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *a], check=True
)
interval, per = 1.0, 24
tiles = int(round(dur / interval))
for k in range(0, tiles, per):
    n = min(per, tiles - k)
    ff(
        "-ss",
        f"{k * interval}",
        "-t",
        f"{n * interval}",
        "-i",
        video,
        "-vf",
        f"fps=1/{interval},scale=480:-1,tile=6x4:padding=4:color=0x333333",
        "-frames:v",
        "1",
        str(out / f"sheet-{k // per + 1}.png"),
    )
kinds = {"section", "land", "state", "live", "chime", "name"}
changes = sorted(
    {round(c["t"], 3) for c in cues["cues"] if c["kind"] in kinds and 0 < c["t"] < dur}
)
strips = []
for t in changes:
    a = max(0.0, t - 0.3)
    ff(
        "-ss",
        f"{a:.4f}",
        "-t",
        "0.8",
        "-i",
        video,
        "-vf",
        "scale=240:-1,tile=12x4:padding=2:color=0x333333",
        "-frames:v",
        "1",
        str(out / f"strip-{t:06.3f}.png"),
    )
    strips.append(t)
(out / "manifest.json").write_text(
    json.dumps(
        {
            "duration": dur,
            "interval": interval,
            "tiles": tiles,
            "changes": changes,
            "strips": strips,
        }
    )
)
print(out, f"{-(-tiles // per)} sheets", f"{len(strips)} strips")
