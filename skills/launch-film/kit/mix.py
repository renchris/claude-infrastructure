"""Final mix: the music+effects stem plus the two helper clips, placed per timeline.json.

The clips are the helper's WAVs as returned: upsampled 24 -> 48 kHz with a unity-gain polyphase filter, mono copied
to both channels exactly, no gain, no processing. Nothing is applied to the sum, so every voice sample in the mix is
the clip's own. Checks: the stem is exactly 0 inside each silence window, the voice region of the mix equals the
upsampled clip bit for bit, and the sum never clips.

    python3 mix.py timeline.json sound/music_sfx.wav out/mix.wav
"""

import json
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly

SR = 48000


def read_float(path: Path) -> tuple[int, np.ndarray]:
    sr, x = wavfile.read(path)
    if x.dtype == np.int16:
        y = x.astype(np.float64) / 32768.0
    elif x.dtype == np.int32:
        y = x.astype(np.float64) / 2147483648.0
    else:
        y = x.astype(np.float64)
    return sr, y


def main() -> None:
    tl_path, stem_path, out_path = (Path(a) for a in sys.argv[1:4])
    tl = json.loads(tl_path.read_text())
    work = tl_path.parent
    n = round(tl["duration"] * SR)

    sr, stem = read_float(stem_path)
    assert sr == SR and stem.ndim == 2 and stem.shape[1] == 2, (sr, stem.shape)
    assert abs(stem.shape[0] - n) <= 1, (stem.shape[0], n)
    stem = (
        stem[:n]
        if stem.shape[0] >= n
        else np.pad(stem, ((0, n - stem.shape[0]), (0, 0)))
    )

    for a, b in tl["silence_windows"]:
        seg = stem[round(a * SR) : round(b * SR)]
        peak = float(np.max(np.abs(seg))) if seg.size else 0.0
        print(f"stem in silence window {a:.2f}-{b:.2f}: peak {peak:.3e}")
        assert peak == 0.0, "music or effects under speech"

    voice = np.zeros((n, 2))
    for v in tl["voices"]:
        vsr, clip = read_float(work / v["file"])
        assert vsr == 24000 and clip.ndim == 1
        up = resample_poly(clip, 2, 1)
        i0 = round(v["start"] * SR)
        i1 = min(n, i0 + len(up))
        voice[i0:i1, 0] = up[: i1 - i0]
        voice[i0:i1, 1] = up[: i1 - i0]
        # the stem must be silent wherever the clip has speech
        on, off = round(v["speech_on"] * SR), round(v["speech_off"] * SR)
        assert float(np.max(np.abs(stem[on:off]))) == 0.0
        print(
            f"{v['id']}: {len(clip)} samples @24k -> {len(up)} @48k at {v['start']:.3f}s, clip peak {20 * np.log10(np.max(np.abs(clip))):.2f} dBFS, upsampled peak {20 * np.log10(np.max(np.abs(up))):.2f} dBFS"
        )

    mix = stem + voice
    peak = float(np.max(np.abs(mix)))
    print(f"mix peak {20 * np.log10(peak):.2f} dBFS")
    assert peak < 1.0
    for v in tl["voices"]:
        i0 = round(v["start"] * SR)
        on, off = round(v["speech_on"] * SR), round(v["speech_off"] * SR)
        assert np.array_equal(mix[on:off], voice[on:off]), "voice region altered"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    wavfile.write(out_path, SR, mix.astype(np.float32))
    print("wrote", out_path, mix.shape)


if __name__ == "__main__":
    main()
