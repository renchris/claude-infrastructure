"""Verify ../brag.mp4 the way v1 was verified (brag-output/brag-plan.md, Build log).

    python3 verify.py timeline.json

1. ffprobe line: 1920x1080, 30 fps, 675 frames, 22.5 s, yuv420p, AAC 48 kHz stereo.
2. Frame 0 is the poster (PSNR against out/poster.png); frame 1 is the render's frame 1 (nothing shifted).
3. Per decoded channel, each clip is found by cross-correlation at its timeline start; least-squares gain ~1.0
   and the residual far below it, so nothing sounds under the speech.
4. Parakeet (ggml parakeet-tdt-0.6b-v3) transcribes each voice region of the decoded MP4 back to the on-screen text.
5. Loudness: integrated LUFS and true peak of the MP4's audio.
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import correlate, resample_poly

SR = 48000
PARAKEET_MODEL = (
    Path.home() / "Development/wcpp191/models/ggml-parakeet-tdt-0.6b-v3-f16.bin"
)


def run(cmd: list[str]) -> str:
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def ffmpeg(*a: str) -> None:
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *a], check=True
    )


def psnr(a: str, b: str) -> str:
    r = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-i",
            a,
            "-i",
            b,
            "-lavfi",
            "psnr",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
    )
    m = re.search(r"average:(\S+)", r.stderr)
    return m.group(1) if m else "?"


def words(s: str) -> list[str]:
    return re.sub(r"[^a-z0-9' ]", " ", s.lower()).split()


def main() -> None:
    tl_path = Path(sys.argv[1]).resolve()
    tl = json.loads(tl_path.read_text())
    work = tl_path.parent
    mp4 = work.parent / "brag.mp4"
    ok = True

    print(
        run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration,size:stream=codec_name,width,height,r_frame_rate,nb_frames,pix_fmt,color_space,sample_rate,channels",
                "-of",
                "compact",
                str(mp4),
            ]
        ).strip()
    )

    with tempfile.TemporaryDirectory() as td:
        t = Path(td)
        # 2 -- the poster is frame 0 and nothing shifted
        ffmpeg(
            "-i",
            str(mp4),
            "-vf",
            "select=eq(n\\,0)",
            "-frames:v",
            "1",
            str(t / "m0.png"),
        )
        ffmpeg(
            "-i",
            str(mp4),
            "-vf",
            "select=eq(n\\,1)",
            "-frames:v",
            "1",
            str(t / "m1.png"),
        )
        ffmpeg(
            "-i",
            str(work / "out/frames.mkv"),
            "-vf",
            "select=eq(n\\,1)",
            "-frames:v",
            "1",
            str(t / "r1.png"),
        )
        print(
            f"frame 0 vs poster PSNR {psnr(str(t / 'm0.png'), str(work / 'out/poster.png'))} dB; "
            f"frame 1 vs render frame 1 PSNR {psnr(str(t / 'm1.png'), str(t / 'r1.png'))} dB"
        )

        # 3 -- the clips in the decoded audio, per channel
        ffmpeg(
            "-i",
            str(mp4),
            "-vn",
            "-ac",
            "2",
            "-ar",
            str(SR),
            "-c:a",
            "pcm_f32le",
            str(t / "a.wav"),
        )
        _, a = wavfile.read(t / "a.wav")
        a = a.astype(np.float64)
        for v in tl["voices"]:
            vsr, clip = wavfile.read(work / v["file"])
            clip = clip.astype(np.float64) / (
                32768.0 if clip.dtype == np.int16 else 1.0
            )
            up = resample_poly(clip, SR // vsr, 1)
            i0 = round(v["start"] * SR)
            lo, hi = i0 - SR // 10, i0 + len(up) + SR // 10
            for ch in (0, 1):
                seg = a[lo:hi, ch]
                xc = correlate(seg, up, mode="valid", method="fft")
                k = int(np.argmax(xc))
                found = (lo + k) / SR
                # gain and residual inside the voice's silence window: the clip's own trailing padding runs past
                # the window into the next riser, where music is allowed, so the whole clip is the wrong span
                wa, wb = next(w for w in tl["silence_windows"] if w[0] <= v["start"] < w[1])
                j0, j1 = round((wa - found) * SR), min(len(up), round((wb - found) * SR))
                y, u = seg[k + j0 : k + j1], up[j0:j1]
                g = float(np.dot(y, u) / np.dot(u, u))
                res = y - g * u
                rdb = 10 * np.log10(np.sum(res**2) / np.sum((g * u) ** 2))
                tail = 20 * np.log10(max(1e-12, float(np.max(np.abs(up[j1:]))))) if j1 < len(up) else float("-inf")
                print(
                    f"{v['id']} ch{ch}: found at {found:.4f} s (timeline {v['start']:.4f}), in window {wa}-{wb}: "
                    f"gain {g:.4f}, residual {rdb:.1f} dB; clip after the window peaks {tail:.1f} dBFS"
                )
                ok &= abs(found - v["start"]) < 0.001 and abs(g - 1) < 0.02

        # 4 -- Parakeet reads each voice region back
        for v in tl["voices"]:
            ffmpeg(
                "-i",
                str(t / "a.wav"),
                "-ss",
                f"{v['start'] - 0.05:.3f}",
                "-t",
                f"{v['length'] + 0.1:.3f}",
                "-af",
                "pan=mono|c0=c0",
                "-ar",
                "16000",
                str(t / f"{v['id']}.wav"),
            )
            out = (
                subprocess.run(
                    [
                        "parakeet-cli",
                        "-np",
                        "-m",
                        str(PARAKEET_MODEL),
                        "-f",
                        str(t / f"{v['id']}.wav"),
                    ],
                    capture_output=True,
                    text=True,
                )
                .stdout.strip()
                .splitlines()
            )
            said = out[-1].strip() if out else ""
            match = words(said) == words(v["text"])
            print(
                f'{v["id"]} Parakeet: "{said}" -> {"EXACT" if match else "MISMATCH"} vs "{v["text"]}"'
            )
            ok &= match

    # 5 -- loudness
    r = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(mp4),
            "-af",
            "ebur128=peak=true",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
    ).stderr
    summary = r[r.rfind("Summary:") :]
    i_lufs = re.search(r"I:\s+(\S+) LUFS", summary)
    tp = re.search(r"Peak:\s+(\S+) dBFS", summary)
    print(
        f"loudness: integrated {i_lufs.group(1) if i_lufs else '?'} LUFS, true peak {tp.group(1) if tp else '?'} dBFS"
    )
    print("VERIFY", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
