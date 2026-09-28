#!/usr/bin/env python3
"""picture_gate.py: the design gates of skills/launch-film/studio-method.md § 4, measured, never self-scored. Generic:
it needs no hook in the page (`design_gate.py` beside it is the variant for pages that report their own layout).

Encoding gates passed a film the operator called "very broken" (2026-09-28). These gates read the picture instead:
  geometry  `node render.mjs geom --page <page>` → <geom>/geom.jsonl: every visible text run per frame, as the page
            itself lays it out (box, on-screen glyph px, opacity, role, texture, skewed plane), plus a screenshot every
            few frames with every glyph made transparent, so a stroke inside a text box is visible as pixels
  pixels    the decoded film (the final MP4, or a preview render before it): static share and subject coverage
  review    <review>/manifest.json from review.py: a sheet covering 100 % of the duration and a strip per state change

  python3 picture_gate.py --geom out/geom --video ../brag.mp4 [--review review] [--lockup 36.6] [--label v3]
Prints one line per gate and `DESIGN PASS` or `DESIGN FAIL (n)`; exit 1 on fail. Thresholds are the method's starting
values; the ones used are printed so a calibration is on the record."""

import argparse, json, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image

A = argparse.ArgumentParser()
A.add_argument("--geom")
A.add_argument("--video")
A.add_argument("--review")
A.add_argument("--label", default="")
A.add_argument(
    "--lockup",
    type=float,
    default=None,
    help="the lockup starts here (s); exempt from coverage/static",
)
A.add_argument("--min-px", type=float, default=22.0)
A.add_argument("--head-px", type=float, default=84.0)
A.add_argument("--static-max", type=float, default=0.40)
A.add_argument("--hold-max", type=float, default=1.2)
A.add_argument("--cover-min", type=float, default=0.15)
A.add_argument("--ink-min", type=float, default=0.02)
A.add_argument("--run-max", type=float, default=0.3)
A.add_argument("--frozen", type=float, default=0.001, help="MAD/255 at 160x90 under which nothing moved; 0.001 = no pixel changed (the rejected v2's holds measure exactly this)")
o = A.parse_args()
fails = []


def gate(ok, name, detail):
    print(f"{'ok  ' if ok else 'FAIL'} {name}: {detail}")
    if not ok:
        fails.append(name)


def spans(ts, step):
    """Group sorted times into runs of consecutive samples; returns [(t0, t1)]."""
    out = []
    for t in ts:
        if out and t - out[-1][1] <= step * 1.5:
            out[-1][1] = t
        else:
            out.append([t, t])
    return [(a, b) for a, b in out]


def fmt(runs, k=4):
    return ", ".join(f"{a:.2f}–{b:.2f}s" for a, b in runs[:k]) + (
        " …" if len(runs) > k else ""
    )


# ---------------------------------------------------------------- geometry gates
if o.geom:
    G = Path(o.geom)
    info = json.loads((G / "info.json").read_text())
    fps = info["fps"]
    frames = [
        json.loads(l) for l in (G / "geom.jsonl").read_text().splitlines() if l.strip()
    ]
    anyrole = any(x.get("role") for f in frames for x in f["texts"])
    small, heads, overl, transit, skewed, strokes = [], [], [], [], [], []
    worst_small, worst_head = [], []
    prev = {}
    for f in frames:
        t = f["t"]
        read = [x for x in f["texts"] if x["op"] >= 0.5 and not x["texture"]]
        # minimum type: nothing meant to be read under min-px; a headline under head-px. A page that marks no
        # roles gets its largest text on each frame treated as that frame's headline.
        for x in read:
            if x["px"] < o.min_px - 0.05:
                small.append(t)
                worst_small.append((x["px"], x["s"], t))
        hs = (
            [x for x in read if x.get("role") == "headline"]
            if anyrole
            else ([max(read, key=lambda x: x["px"])] if read else [])
        )
        for x in hs:
            if x["px"] < o.head_px - 0.05:
                heads.append(t)
                worst_head.append((x["px"], x["s"], t))
        # text over text: two different runs whose boxes intersect (0 px tolerance)
        vis = [x for x in f["texts"] if x["op"] >= 0.3]
        hit = False
        for i in range(len(vis)):
            for j in range(i + 1, len(vis)):
                if vis[i]["id"] == vis[j]["id"]:
                    continue
                for a in vis[i]["rects"]:
                    for b in vis[j]["rects"]:
                        if (
                            min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]) > 0.5
                            and min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]) > 0.5
                        ):
                            hit = True
                            worst = (vis[i]["s"], vis[j]["s"], t)
        if hit:
            overl.append(t)
            overl_ex = worst
        # text in transit: a readable run that moves continuously between consecutive frames (more than 1 px, less
        # than a line jump), or any readable run on a skewed / rotated / 3D plane
        cur = {}
        for x in read:
            r = x["rects"][0]
            cur[x["id"]] = (r[0], r[1], r[3], x["px"])
            if x["skew"]:
                skewed.append(t)
            p = prev.get(x["id"])
            if p:
                d = max(abs(r[0] - p[0]), abs(r[1] - p[1]), abs(r[3] - p[2]))
                if 1.0 < d < 0.8 * x["px"] or abs(x["px"] - p[3]) > 0.3:
                    transit.append(t)
                    transit_ex = (x["s"], round(d, 1), t)
        prev = cur
        # a stroke or shape inside a readable text box, read from the glyph-less screenshot
        if f.get("shot"):
            img = np.asarray(Image.open(G / f["shot"]).convert("RGB")).astype(np.int16)
            for x in read:
                for r in x["rects"]:
                    x0, y0 = int(np.ceil(r[0] + 1)), int(np.ceil(r[1] + 1))
                    x1, y1 = int(r[0] + r[2] - 1), int(r[1] + r[3] - 1)
                    x0, y0 = max(x0, 0), max(y0, 0)
                    x1, y1 = min(x1, img.shape[1]), min(y1, img.shape[0])
                    if x1 - x0 < 3 or y1 - y0 < 3:
                        continue
                    box = img[y0:y1, x0:x1].reshape(-1, 3)
                    q = box // 8
                    keys, cnt = np.unique(
                        q[:, 0] * 1024 + q[:, 1] * 32 + q[:, 2], return_counts=True
                    )
                    k = keys[cnt.argmax()]
                    ref = np.array([k // 1024, (k // 32) % 32, k % 32]) * 8 + 4
                    dev = int((np.abs(box - ref).max(1) > 40).sum())
                    if dev > max(20, 0.002 * len(box)):
                        strokes.append(t)
                        stroke_ex = (x["s"], dev, t)
    step = 1 / fps
    gate(
        not small,
        f"minimum type ≥ {o.min_px:g} px",
        "every readable run"
        if not small
        else f"{len(set(small))} frames, e.g. {sorted(set(worst_small))[:3]}",
    )
    gate(
        not heads,
        f"headline ≥ {o.head_px:g} px",
        ("roles marked" if anyrole else "no roles marked: largest text per frame")
        + (
            ""
            if not heads
            else f"; {len(set(heads))} frames under, e.g. {sorted(set(worst_head))[:2]}"
        ),
    )
    gate(
        not overl,
        "text vs text (0 px)",
        "no two runs touch"
        if not overl
        else f"{len(overl)} frames ({fmt(spans(overl, step))}), e.g. {overl_ex}",
    )
    shots = sum(1 for f in frames if f.get("shot"))
    gate(
        not strokes,
        "text vs line (0 px)",
        f"{shots} glyph-less frames checked"
        if not strokes
        else f"{len(set(strokes))} of {shots} checked frames ({fmt(spans(sorted(set(strokes)), step * info['shots']))}), e.g. {stroke_ex}",
    )
    gate(
        not transit and not skewed,
        "text in transit / skewed plane",
        "readable text never moves or skews"
        if not (transit or skewed)
        else f"{len(set(transit))} moving frames ({fmt(spans(sorted(set(transit)), step))}){', e.g. ' + str(transit_ex) if transit else ''}; {len(set(skewed))} skewed",
    )

# ---------------------------------------------------------------- pixel gates (decoded film)
if o.video:
    pr = json.loads(
        subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_entries",
                "stream=r_frame_rate:format=duration",
                "-of",
                "json",
                o.video,
            ],
            capture_output=True,
            text=True,
        ).stdout
    )
    num, den = pr["streams"][0]["r_frame_rate"].split("/")
    fps = float(num) / float(den)
    dur = float(pr["format"]["duration"])

    def frames_of(w, h):
        p = subprocess.Popen(
            [
                "ffmpeg",
                "-v",
                "error",
                "-i",
                o.video,
                "-vf",
                f"scale={w}:{h}:flags=area,format=gray",
                "-f",
                "rawvideo",
                "-",
            ],
            stdout=subprocess.PIPE,
        )
        while True:
            b = p.stdout.read(w * h)
            if len(b) < w * h:
                break
            yield np.frombuffer(b, np.uint8).reshape(h, w)

    lock = o.lockup if o.lockup is not None else dur
    # static share, measured the way the method's numbers were (160×90 greyscale, MAD < 0.5/255 vs the previous frame)
    stat, frozen, prevf, n = [], [], None, 0
    for i, fr in enumerate(frames_of(160, 90)):
        t = i / fps
        n += 1
        if prevf is not None and t < lock:
            mad = np.abs(fr.astype(np.int16) - prevf).mean()
            if mad < 0.5:
                stat.append(t)
            if mad < o.frozen:
                frozen.append(t)
        prevf = fr.astype(np.int16)
    mid = max(1, sum(1 for i in range(n) if 0 < i / fps < lock))
    share = len(stat) / mid
    # The reel metric stays on the record and gates only when --static-max is set below 1. Calibration (2026-09-28):
    # the operator rejected a film built to the reels' motion as "just fast moving and not actually good design or
    # informational", and the Opus 5.5 launch film holds still for ~53 % of its frames, so a reel threshold cannot
    # be this film class's bar. What made v2 read as slides is the dead hold, a stretch where nothing at all moves;
    # that is what gates. Measure it on a lossless render: encoder noise is motion to this metric.
    gate(
        share <= o.static_max,
        f"static share, reel metric (≤ {o.static_max:.0%})",
        f"{share:.1%} of {mid} frames before the lockup",
    )
    runs = [r for r in spans(frozen, 1 / fps) if r[1] - r[0] + 1 / fps > o.hold_max]
    gate(
        not runs,
        f"no dead hold > {o.hold_max:g} s outside the lockup (MAD < {o.frozen:g}/255)",
        f"{len(frozen) / mid:.1%} of frames frozen, every run within bound"
        if not runs
        else f"{len(runs)} dead holds: {fmt(runs)}",
    )
    # subject coverage: 16×9 cells of the 480×270 frame; a cell is occupied when ≥ 10 % of it differs from the
    # frame's ground (its modal grey) by > 24; ink = the differing fraction of the whole frame
    bad = []
    for i, fr in enumerate(frames_of(480, 270)):
        t = i / fps
        if t >= lock:
            continue
        hist = np.bincount((fr // 4).ravel(), minlength=64)
        g = hist.argmax() * 4 + 2
        ink = np.abs(fr.astype(np.int16) - g) > 24
        cells = ink.reshape(9, 30, 16, 30).mean((1, 3)) >= 0.10
        if cells.mean() < o.cover_min or ink.mean() < o.ink_min:
            bad.append(t)
    runs = [r for r in spans(bad, 1 / fps) if r[1] - r[0] + 1 / fps > o.run_max]
    gate(
        not runs,
        f"subject ≥ {o.cover_min:.0%} of cells, ink ≥ {o.ink_min:.0%}",
        f"{len(bad)} thin frames, none in a run > {o.run_max:g} s"
        if not runs
        else f"{len(runs)} subjectless runs > {o.run_max:g} s: {fmt(runs)}",
    )

# ---------------------------------------------------------------- review coverage
if o.review:
    m = Path(o.review) / "manifest.json"
    if not m.exists():
        gate(False, "review coverage", f"{m} missing")
    else:
        r = json.loads(m.read_text())
        gate(
            r["tiles"] * r["interval"] >= r["duration"] - 1e-6,
            "review sheet covers 100 %",
            f"{r['tiles']} tiles × {r['interval']} s vs {r['duration']} s",
        )
        missing = [
            c for c in r["changes"] if not any(abs(s - c) < 1e-3 for s in r["strips"])
        ]
        gate(
            not missing,
            "a strip per state change",
            f"{len(r['strips'])} strips"
            if not missing
            else f"no strip at {missing[:5]}",
        )

print(
    f"{o.label + ': ' if o.label else ''}{'DESIGN PASS' if not fails else f'DESIGN FAIL ({len(fails)})'}"
)
sys.exit(1 if fails else 0)
