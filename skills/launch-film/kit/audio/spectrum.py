"""Per-frame spectral features of the voice clips at 60 Hz, for the v3 orb.

For each clip: four band levels (0..1: 80-300, 300-1000, 1000-3000, 3000-8000 Hz), the spectral centroid (0..1 on a
log scale from 150 Hz to 6 kHz) and a spectral-flux onset signal (0..1), each smoothed with the same 20 ms attack /
140 ms release as envelopes.py. Read by composition/scene.js through data/spec.json; the orb is a pure function of t.

    python3 audio/spectrum.py timeline.json composition/data/spec.json
"""

import json
import sys
import wave

import numpy as np

RATE = 60
BANDS = [(80, 300), (300, 1000), (1000, 3000), (3000, 8000)]


def smooth(v: np.ndarray) -> list[float]:
    a, r = 1 - np.exp(-1 / (RATE * 0.02)), 1 - np.exp(-1 / (RATE * 0.14))
    y, s = [], 0.0
    for x in v:
        s += (x - s) * (a if x > s else r)
        y.append(round(float(s), 4))
    return y


def features(path: str) -> dict[str, list[float] | list[list[float]]]:
    w = wave.open(path)
    sr = w.getframerate()
    x = (
        np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
        / 32768.0
    )
    n = int(np.ceil(len(x) / sr * RATE))
    win = int(0.04 * sr)
    hann = np.hanning(win)
    f = np.fft.rfftfreq(win, 1 / sr)
    bands, cents, flux, prev = [], [], [], None
    for i in range(n):
        c = int(i / RATE * sr)
        seg = x[max(0, c - win // 2) : c - win // 2 + win]
        seg = np.pad(seg, (0, win - len(seg)))
        mag = np.abs(np.fft.rfft(seg * hann))
        p = mag**2
        bands.append(
            [10 * np.log10(p[(f >= lo) & (f < hi)].sum() + 1e-12) for lo, hi in BANDS]
        )
        tot = p[(f >= 80) & (f < 8000)].sum()
        cents.append(float((f * p).sum() / tot) if tot > 1e-9 else 0.0)
        flux.append(float(np.maximum(mag - prev, 0).sum()) if prev is not None else 0.0)
        prev = mag
    b = np.array(bands)
    # each band 0..1 over a 36 dB range under its own loudest frame
    b = np.clip((b - (b.max(axis=0) - 36)) / 36, 0, 1)
    cen = np.clip(
        (np.log(np.maximum(cents, 150)) - np.log(150)) / (np.log(6000) - np.log(150)),
        0,
        1,
    )
    fl = np.array(flux)
    fl = np.clip(fl / (np.percentile(fl, 98) + 1e-9), 0, 1)
    return {
        "bands": [smooth(b[:, k]) for k in range(len(BANDS))],
        "centroid": smooth(cen * (b.max(axis=1) > 0.15)),
        "flux": smooth(fl),
    }


if __name__ == "__main__":
    tl = json.load(open(sys.argv[1]))
    out = {
        v["id"]: {"start": v["start"], "rate": RATE, **features(v["file"])}
        for v in tl["voices"]
    }
    json.dump(out, open(sys.argv[2], "w"))
    for k, v in out.items():
        print(
            k,
            len(v["flux"]),
            "frames; band maxima",
            [max(b) for b in v["bands"]],
            "centroid max",
            max(v["centroid"]),
        )
