"""Loudness envelopes of the voice clips at 60 Hz, 0..1, for the video's sound-arc graphic."""
import json
import sys
import wave

import numpy as np

RATE = 60


def envelope(path: str) -> list[float]:
    w = wave.open(path)
    sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
    n = int(np.ceil(len(x) / sr * RATE))
    half = int(0.0125 * sr)
    out = []
    for i in range(n):
        c = int(i / RATE * sr)
        seg = x[max(0, c - half): c + half]
        rms = float(np.sqrt(np.mean(seg**2))) if len(seg) else 0.0
        db = 20 * np.log10(rms + 1e-9)
        out.append(min(1.0, max(0.0, (db + 48) / 36)))
    # attack 20 ms, release 140 ms
    a, r = 1 - np.exp(-1 / (RATE * 0.02)), 1 - np.exp(-1 / (RATE * 0.14))
    y, s = [], 0.0
    for v in out:
        s += (v - s) * (a if v > s else r)
        y.append(round(s, 4))
    return y


if __name__ == "__main__":
    tl = json.load(open(sys.argv[1]))
    data = {v["id"]: {"start": v["start"], "rate": RATE, "env": envelope(v["file"])} for v in tl["voices"]}
    json.dump(data, open(sys.argv[2], "w"))
    for k, v in data.items():
        print(k, len(v["env"]), "frames, max", max(v["env"]))
