"""Tone-match stage for the v2 music+effects stem (adapted from brag-output/work/sound/tone.py; only EQ changes).

Measured before (band power as dB of total, B's drop 6-12 s, mean of both channels, vs the mean of the five ende.app
tracks): sub-heavy (+2.0 dB at 40-80 Hz), a thin low-mid (-3.3 dB at 160-320 Hz) and a bright top (+3.3 dB at
2.5-5 kHz, +4.9 dB at 10-20 kHz); 2.50 dB RMS across bands. These four RBJ biquads bring it to 0.94 dB RMS; the stem is
then returned to its original integrated loudness and the silence windows are re-zeroed last, so nothing sounds under
speech.

    python3 tone2.py ../timeline.json music_sfx.wav music_sfx_eq.wav
"""

import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import numpy.typing as npt
from scipy.io import wavfile
from scipy.signal import sosfilt

SR = 48000
Arr = npt.NDArray[np.float64]


def biquad(kind: str, f0: float, gain_db: float, q: float) -> Arr:
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / SR
    cw, sw = np.cos(w), np.sin(w)
    alpha = sw / (2 * q)
    if kind == "peak":
        b = [1 + alpha * a, -2 * cw, 1 - alpha * a]
        d = [1 + alpha / a, -2 * cw, 1 - alpha / a]
    else:
        sa = 2 * np.sqrt(a) * alpha
        if kind == "lowshelf":
            b = [
                a * ((a + 1) - (a - 1) * cw + sa),
                2 * a * ((a - 1) - (a + 1) * cw),
                a * ((a + 1) - (a - 1) * cw - sa),
            ]
            d = [
                (a + 1) + (a - 1) * cw + sa,
                -2 * ((a - 1) + (a + 1) * cw),
                (a + 1) + (a - 1) * cw - sa,
            ]
        else:  # highshelf
            b = [
                a * ((a + 1) + (a - 1) * cw + sa),
                -2 * a * ((a - 1) + (a + 1) * cw),
                a * ((a + 1) + (a - 1) * cw - sa),
            ]
            d = [
                (a + 1) - (a - 1) * cw + sa,
                2 * ((a - 1) - (a + 1) * cw),
                (a + 1) - (a - 1) * cw - sa,
            ]
    return np.array(
        [[b[0] / d[0], b[1] / d[0], b[2] / d[0], 1.0, d[1] / d[0], d[2] / d[0]]]
    )


EQ = [
    ("lowshelf", 90.0, -2.0, 0.7),
    ("peak", 300.0, 2.5, 0.5),
    ("highshelf", 3000.0, -3.0, 0.7),
    ("highshelf", 10000.0, -1.5, 0.7),
]


def lufs(path: Path) -> tuple[float, float]:
    out = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-af",
            "ebur128=peak=true",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
    ).stderr
    i = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", out)[-1])
    tp = float(re.findall(r"Peak:\s+(-?[\d.]+) dBFS", out)[-1])
    return i, tp


def main() -> None:
    tl_path, src, dst = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    tl = json.loads(tl_path.read_text())
    sr, x = wavfile.read(src)
    assert sr == SR
    y: Arr = x.astype(np.float64)
    sos = np.vstack([biquad(*band) for band in EQ])
    y = sosfilt(sos, y, axis=0)
    i_src, _ = lufs(src)
    tmp = dst.with_suffix(".tmp.wav")
    wavfile.write(tmp, SR, y.astype(np.float32))
    i_eq, _ = lufs(tmp)
    y *= 10 ** ((i_src - i_eq) / 20)
    # silence windows last: exactly zero from each window start (30 ms cosine fade into it)
    fade = int(0.03 * SR)
    for a, b in tl["silence_windows"]:
        i0, i1 = round(a * SR), round(b * SR)
        ramp = 0.5 * (1 + np.cos(np.linspace(0, np.pi, fade)))
        y[i0 - fade : i0] *= ramp[:, None]
        y[i0:i1] = 0.0
    y[-1] = 0.0
    wavfile.write(dst, SR, y.astype(np.float32))
    tmp.unlink()
    i_out, tp = lufs(dst)
    print(f"integrated {i_src:.1f} -> {i_out:.1f} LUFS, peak {tp:.1f} dBFS")
    for a, b in tl["silence_windows"]:
        print(
            f"window {a:.2f}-{b:.2f}: max {np.max(np.abs(y[round(a * SR) : round(b * SR)])):.1e}"
        )


if __name__ == "__main__":
    main()
