#!/usr/bin/env python3
"""
motion-probe.py — make motion legible to something that can only see stills.

A language model reading a video is always reading sampled frames; even the
"native video" APIs sample (Gemini defaults to 1fps). Sampling harder does not
fix this, because motion does not live in any single frame — it lives *between*
frames. The fix is to transform the temporal dimension into a spatial one, so
that a still image carries the motion, and to measure animation curves as
numbers instead of eyeballing them.

Four probes, each answering a question frames alone cannot:

  slice   Spatiotemporal (slit-scan) image. One column of pixels per frame,
          stacked left to right. The whole film's timing becomes visible
          geometry: hard cuts are vertical discontinuities, a moving object is
          a diagonal streak, and the CURVATURE of that streak is the easing.

  flow    Dense optical-flow magnitude per frame -> a time series. Answers
          "when does motion happen, and how much", and exposes stutter,
          dropped frames and dead air.

  trail   Temporal max-composite over a window: a long-exposure photograph.
          Shows an element's whole trajectory in one still.

  curve   Tracks a scalar property (vertical centroid / brightness / spread)
          of a region across frames at full rate, prints it as numbers, and
          FITS it against standard easing functions. This is the one that
          turns "does this animation feel right" into a measurement.

Requires: opencv-python, numpy. matplotlib optional (PNG plots).

  python3 motion-probe.py slice  FILM.mp4 --out st.png
  python3 motion-probe.py flow   FILM.mp4 --out flow.png
  python3 motion-probe.py trail  FILM.mp4 --from 10.6 --to 12.0 --out trail.png
  python3 motion-probe.py curve  FILM.mp4 --from 10.6 --to 12.0 --roi 0.25,0.35,0.75,0.62
"""

from __future__ import annotations

import argparse
import sys

import cv2
import numpy as np

# --------------------------------------------------------------------- io ---


def open_video(path: str) -> tuple[cv2.VideoCapture, float, int, int, int]:
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        sys.exit(f"cannot open {path}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    return cap, fps, n, w, h


def frames_in_range(path: str, t0: float, t1: float | None, step: int = 1):
    """Yield (index, seconds, BGR frame) for a time range, at native rate."""
    cap, fps, n, _, _ = open_video(path)
    start = int(round(t0 * fps))
    end = n if t1 is None else min(n, int(round(t1 * fps)))
    cap.set(cv2.CAP_PROP_POS_FRAMES, start)
    i = start
    while i < end:
        ok, frame = cap.read()
        if not ok:
            break
        if (i - start) % step == 0:
            yield i, i / fps, frame
        i += 1
    cap.release()


# ------------------------------------------------------------ probe: slice ---


def _add_time_ruler(img: np.ndarray, t0: float, t1: float, marks: str | None):
    """Bolt a second-by-second time axis (and optional named marks) onto a slice."""
    h, w = img.shape[:2]
    bar = 74
    out = np.full((h + bar, w, 3), 18, np.uint8)
    out[bar:] = img

    span = max(t1 - t0, 1e-6)
    px = lambda t: int(round((t - t0) / span * (w - 1)))  # noqa: E731

    # tick every second, labelled every 5
    t = float(np.ceil(t0))
    while t <= t1:
        x = px(t)
        major = abs(t % 5) < 1e-6
        cv2.line(out, (x, bar - (16 if major else 8)), (x, bar), (90, 90, 90), 1)
        if major:
            cv2.putText(
                out,
                f"{int(t)}s",
                (x + 4, bar - 22),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.62,
                (210, 210, 210),
                2,
                cv2.LINE_AA,
            )
        t += 1.0

    # named marks: "label@seconds,label@seconds" — drawn as full-height guides
    if marks:
        for spec in marks.split(","):
            if "@" not in spec:
                continue
            label, _, tv = spec.partition("@")
            try:
                x = px(float(tv))
            except ValueError:
                continue
            cv2.line(out, (x, bar), (x, h + bar), (0, 200, 255), 1, cv2.LINE_AA)
            cv2.putText(
                out,
                label,
                (x + 5, 26),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.66,
                (0, 200, 255),
                2,
                cv2.LINE_AA,
            )
    return out


def probe_slice(args) -> None:
    """Spatiotemporal slice: time becomes the x axis, so motion becomes shape."""
    cap, fps, n, w, h = open_video(args.video)
    t1 = args.to if args.to is not None else n / fps
    start, end = int(args.frm * fps), min(n, int(t1 * fps))
    count = end - start
    step = max(1, count // args.width)

    col_x = int(w * args.at)  # which column of the frame to sample (for X-T)
    row_y = int(h * args.at)  # which row (for Y-T)
    xt, yt = [], []

    cap.set(cv2.CAP_PROP_POS_FRAMES, start)
    i = start
    while i < end:
        ok, frame = cap.read()
        if not ok:
            break
        if (i - start) % step == 0:
            yt.append(frame[row_y, :, :].copy())  # a horizontal line over time
            xt.append(frame[:, col_x, :].copy())  # a vertical line over time
        i += 1
    cap.release()

    if not xt:
        sys.exit("no frames sampled")

    # rows = the sampled line, cols = time
    xt_img = np.stack(xt, axis=1)
    yt_img = np.stack(yt, axis=1)
    # stack both views with a divider
    div = np.full((8, xt_img.shape[1], 3), 40, np.uint8)
    out = np.vstack([xt_img, div, yt_img])

    # A slit-scan with no time axis is close to unreadable — every feature's
    # meaning depends on WHEN it is, and the x axis is the only place that lives.
    # The ruler is not decoration.
    if not args.no_ruler:
        out = _add_time_ruler(out, args.frm, t1, args.marks)

    cv2.imwrite(args.out, out)
    print(
        f"{args.out}  {out.shape[1]}x{out.shape[0]}  "
        f"{count} frames -> {len(xt)} columns ({args.frm:.2f}s..{t1:.2f}s)"
    )
    print("  TOP    = vertical slice through x=%.2fW, time ->" % args.at)
    print("  BOTTOM = horizontal slice through y=%.2fH, time ->" % args.at)
    print("  read it as: vertical break = hard cut · diagonal streak = movement")
    print("              curved streak = eased movement · flat = static hold")


# ------------------------------------------------------------- probe: flow ---


def probe_flow(args) -> None:
    """Dense optical flow magnitude per frame -> when and how much motion."""
    cap, fps, n, w, h = open_video(args.video)
    t1 = args.to if args.to is not None else n / fps
    start, end = int(args.frm * fps), min(n, int(t1 * fps))
    step = max(1, args.step)

    small = (320, int(320 * h / w))
    cap.set(cv2.CAP_PROP_POS_FRAMES, start)
    prev = None
    series: list[tuple[float, float, float]] = []
    i = start
    while i < end:
        ok, frame = cap.read()
        if not ok:
            break
        if (i - start) % step == 0:
            g = cv2.cvtColor(cv2.resize(frame, small), cv2.COLOR_BGR2GRAY)
            if prev is not None:
                fl = cv2.calcOpticalFlowFarneback(
                    prev, g, None, 0.5, 3, 15, 3, 5, 1.2, 0
                )
                mag = np.linalg.norm(fl, axis=2)
                # absolute frame difference catches cuts, which flow under-reports
                diff = float(np.mean(cv2.absdiff(prev, g)))
                series.append((i / fps, float(mag.mean()), diff))
            prev = g
        i += 1
    cap.release()

    if not series:
        sys.exit("no flow computed")

    print(
        f"optical flow · {len(series)} samples · {args.frm:.2f}s..{t1:.2f}s "
        f"(every {step} frame(s) = {step / fps * 1000:.0f}ms)"
    )
    print(f"{'t(s)':>8} {'flow':>8} {'framediff':>10}  {'':<32}")
    peak = max(s[1] for s in series) or 1.0
    for t, m, d in series:
        bar = "#" * int(round(m / peak * 32))
        cut = "  <- CUT" if d > 22 else ""
        print(f"{t:8.3f} {m:8.3f} {d:10.2f}  {bar:<32}{cut}")

    mags = [s[1] for s in series]
    print(
        f"\n  mean {np.mean(mags):.3f} · peak {np.max(mags):.3f} "
        f"at t={series[int(np.argmax(mags))][0]:.2f}s · "
        f"still frames (<0.05) {sum(1 for m in mags if m < 0.05)}/{len(mags)}"
    )


# ------------------------------------------------------------ probe: trail ---


def probe_trail(args) -> None:
    """Temporal max-composite — a long-exposure still showing the trajectory."""
    acc = None
    count = 0
    for _, _, frame in frames_in_range(args.video, args.frm, args.to, args.step):
        f = frame.astype(np.float32)
        acc = f if acc is None else np.maximum(acc, f)
        count += 1
    if acc is None:
        sys.exit("no frames in range")
    cv2.imwrite(args.out, acc.astype(np.uint8))
    print(
        f"{args.out}  max-composite of {count} frames "
        f"({args.frm:.2f}s..{args.to:.2f}s) — bright pixels trace the path"
    )


# ------------------------------------------------------------ probe: curve ---

EASINGS = {
    "linear": lambda x: x,
    "outExpo": lambda x: np.where(x >= 1, 1.0, 1 - np.power(2.0, -10 * x)),
    # outBack overshoots past 1 and springs back — including it forces the fit to
    # DISCRIMINATE rather than just confirm, since its tail is the opposite shape
    # to outExpo's. Constants match film.js.
    "outBack": lambda x: 1 + 2.2 * np.power(x - 1, 3) + 1.2 * np.power(x - 1, 2),
    "outQuad": lambda x: 1 - (1 - x) ** 2,
    "outCubic": lambda x: 1 - (1 - x) ** 3,
    "outQuart": lambda x: 1 - (1 - x) ** 4,
    "inOutCubic": lambda x: np.where(
        x < 0.5, 4 * x**3, 1 - np.power(-2 * x + 2, 3) / 2
    ),
    "inQuad": lambda x: x**2,
}


def probe_curve(args) -> None:
    """
    Extract a scalar animation signal at FULL frame rate and fit easing curves.

    This is the probe that answers questions frame-sampling structurally cannot:
    not "what is on screen" but "how did it get there" — is the motion linear
    (reads cheap) or weighted (reads expensive), and by how much.
    """
    x0, y0, x1, y1 = (float(v) for v in args.roi.split(","))
    ts, cy, energy = [], [], []

    for _, t, frame in frames_in_range(args.video, args.frm, args.to, 1):
        h, w = frame.shape[:2]
        roi = frame[int(y0 * h) : int(y1 * h), int(x0 * w) : int(x1 * w)]
        g8 = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        # Isolate the subject from the background wash with Otsu rather than a
        # mean+kσ rule. A fixed sigma multiple silently fails whenever the
        # subject fills a large fraction of the ROI: the subject's own pixels
        # drag the mean and σ up until the threshold exceeds the subject's own
        # brightness, and the probe reports "no subject found" on a frame where
        # the subject dominates. Otsu picks the split from the histogram, so it
        # is invariant to how much of the ROI the subject occupies.
        thr, mask_u8 = cv2.threshold(g8, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        mask = mask_u8 > 0
        # Otsu always returns a split, even on a subject-free gradient. Require a
        # real bimodal separation before believing there is something to track.
        if mask.any() and (~mask).any():
            sep = float(g8[mask].mean()) - float(g8[~mask].mean())
            if sep < 25.0:
                mask = np.zeros_like(mask)
        ts.append(t)
        energy.append(float(mask.sum()))
        if mask.sum() > 12:
            ys = np.nonzero(mask)[0]
            cy.append(float(ys.mean()))
        else:
            cy.append(np.nan)

    ts_a = np.array(ts)
    cy_a = np.array(cy)
    en_a = np.array(energy)
    if np.all(np.isnan(cy_a)):
        sys.exit("no subject found in ROI — widen --roi or change the window")

    # forward-fill NaNs so the fit sees a continuous signal
    idx = np.where(~np.isnan(cy_a))[0]
    cy_a = np.interp(np.arange(len(cy_a)), idx, cy_a[idx])

    rel = ts_a - ts_a[0]
    dur = rel[-1] if rel[-1] > 0 else 1.0

    print(
        f"tracked {len(ts)} frames at native rate "
        f"({args.frm:.2f}s..{ts_a[-1]:.2f}s, {1 / np.mean(np.diff(ts_a)):.0f}fps)"
    )
    print(f"roi = {args.roi}\n")
    print(f"{'t(s)':>7} {'rel':>6} {'centroid_y':>11} {'norm':>7} {'lit_px':>8}")
    span = cy_a.max() - cy_a.min()
    for i in range(0, len(ts_a), max(1, len(ts_a) // 26)):
        norm = (cy_a[i] - cy_a.min()) / span if span > 1e-6 else 0.0
        print(
            f"{ts_a[i]:7.3f} {rel[i]:6.3f} {cy_a[i]:11.2f} {norm:7.3f} "
            f"{int(en_a[i]):8d}"
        )

    # normalise: motion goes from start value to settled value
    settle = float(np.median(cy_a[int(len(cy_a) * 0.85) :]))
    start = float(cy_a[0])
    if abs(settle - start) < 1.0:
        print("\n  signal is flat — no vertical travel in this window")
        return
    observed = (cy_a - start) / (settle - start)

    print(f"\n  travel: {start:.1f}px -> {settle:.1f}px over {dur:.3f}s")
    print(f"\n  {'easing':<12} {'RMSE':>8}   fit")
    scored = []
    xs = np.clip(rel / dur, 0, 1)
    for name, fn in EASINGS.items():
        pred = np.asarray(fn(xs), dtype=np.float64)
        rmse = float(np.sqrt(np.mean((pred - observed) ** 2)))
        scored.append((rmse, name))
    scored.sort()
    for rmse, name in scored:
        bar = "#" * max(0, int(round((0.35 - min(rmse, 0.35)) / 0.35 * 26)))
        mark = "  <== best" if (rmse, name) == scored[0] else ""
        print(f"  {name:<12} {rmse:8.4f}   {bar:<26}{mark}")

    best_rmse, best = scored[0]
    verdict = (
        "decisive"
        if best_rmse < 0.05
        else "plausible"
        if best_rmse < 0.12
        else "weak — treat as inconclusive"
    )
    print(f"\n  best fit: {best} (RMSE {best_rmse:.4f}) — {verdict}")
    lin = dict((n, r) for r, n in scored)["linear"]
    print(
        f"  linear RMSE {lin:.4f} — "
        f"{'motion IS weighted, not linear' if lin > best_rmse * 1.6 else 'cannot rule out linear'}"
    )


# -------------------------------------------------------------------- cli ---


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("probe", choices=["slice", "flow", "trail", "curve"])
    ap.add_argument("video")
    ap.add_argument("--from", dest="frm", type=float, default=0.0)
    ap.add_argument("--to", dest="to", type=float, default=None)
    ap.add_argument("--out", default="probe.png")
    ap.add_argument("--step", type=int, default=1, help="frame stride")
    ap.add_argument("--width", type=int, default=1500, help="slice: target columns")
    ap.add_argument("--at", type=float, default=0.5, help="slice: fractional row/col")
    ap.add_argument("--no-ruler", action="store_true", help="slice: omit the time axis")
    ap.add_argument(
        "--marks",
        default=None,
        help="slice: guides, e.g. 'open@0,door@3.6,chapter@8.4'",
    )
    ap.add_argument(
        "--roi",
        default="0.2,0.3,0.8,0.7",
        help="curve: x0,y0,x1,y1 as fractions of the frame",
    )
    args = ap.parse_args()
    {
        "slice": probe_slice,
        "flow": probe_flow,
        "trail": probe_trail,
        "curve": probe_curve,
    }[args.probe](args)


if __name__ == "__main__":
    main()
