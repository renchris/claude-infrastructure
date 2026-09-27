#!/usr/bin/env python3
"""Music and effects stem v2 for the Natural TTS launch video: modern electronic pop, launch-keynote energy.

Every time comes from the timeline on each run, so the picture can move and the score follows it:

    python3 soundtrack2.py ../timeline.json

Writes next to this script: music_sfx.wav, stems/music.wav, stems/sfx.wav, preview_mix.wav and report.json, all
48 kHz stereo float32 and exactly `duration` seconds long. D minor, A4 = 440 Hz, the timeline's tempo; chords
Dm - Bb - F - C, one per bar, and an F major final hit.

Flow: an event score (punchy kick, clap, swung hats, a saturated gliding sub, sidechained supersaws, a pluck motif,
impacts, risers, reverse swells) is mixed into groups with room, hall and ping-pong sends. Each segment (the tease,
the drops, the build) is gain-solved to its short-term loudness target through the master; every section's tail
is shaped to sit below -60 dBFS 50 ms before its silence window; the master is glue compression (2:1), gentle
saturation and a true-peak look-ahead limiter; the silence gate runs last, so the stem is digital silence inside
every silence window.
"""

from __future__ import annotations

import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import zlib
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import numpy.typing as npt
from scipy import signal  # type: ignore[import-untyped]
from scipy.io import wavfile  # type: ignore[import-untyped]

Arr = npt.NDArray[np.float64]

FS = 48_000
PEAK_CEILING_DBTP = (
    -2.0
)  # the limiter's ceiling on 4x-oversampled peaks, under the -1.5 dBTP limit
TRUE_PEAK_LIMIT_DBTP = -1.5
MOMENTARY_MAX_LUFS = -14.0
TAIL_LIMIT_DBFS = -60.0  # the brief's limit, 50 ms before a window
TAIL_TARGET_DBFS = -66.0  # what the tail shaping aims for (margin under the limit)
CHECK_S = 0.050
FADE_S = 0.030
MIN_ATTACK_S = 0.002  # every event starts with at least this raised-cosine attack
MIN_RELEASE_S = 0.015  # and ends with at least this release, on an exact zero
SWING = 0.55  # the off 16th lands at 55 % of its 8th
TARGET_LUFS: dict[str, float] = {
    "tease": -21.0,
    "drop": -17.0,
    "build": -19.5,
}  # short-term 3 s, centred
SFX_UNDER_RANGE_DB = (-14.0, -8.0)  # effects against the music around them
REFERENCE_GLOB = "/tmp/brag-src-0926/skills/brag/assets/music/*.mp3"
BANDS_HZ: tuple[tuple[float, float], ...] = (
    (40.0, 80.0), (80.0, 160.0), (160.0, 320.0), (320.0, 640.0), (640.0, 1280.0),
    (1280.0, 2560.0), (2560.0, 5120.0), (5120.0, 10240.0), (10240.0, 20000.0),
)  # fmt: skip

# Mix levels (dB) of each group; every segment is then gain-solved to its loudness target as a whole.
GROUP_DB: dict[str, float] = {
    "kick": -5.0,
    "heart": -9.0,
    "sub": -12.0,
    "clap": -2.0,
    "snare": -9.0,
    "hat": -11.0,
    "tick": -24.0,
    "chords": -12.0,
    "stab": -10.0,
    "pluck": -14.0,
    "pad": -16.0,
    "bell": -16.0,
    "impact": -9.0,
    "crack": -18.0,
    "swell": -14.0,
    "riser": -20.0,
}

# Sidechain: ducked-event kind -> (kick source, depth dB, hold s, release s).
DUCKS: dict[str, tuple[str, float, float, float]] = {
    "chords": ("main", 6.0, 0.010, 0.150),
    "sub": ("main", 14.0, 0.008, 0.110),
    "pad": ("heart", 4.0, 0.010, 0.200),
}

# Effects: how far each type sits under the music around it (momentary max vs the segment's short-term loudness),
# and its room and hall sends.
SFX_UNDER_DB: dict[str, float] = {
    "whoosh": -10.0,
    "selection_sweep": -12.0,
    "menu_open": -12.0,
    "click": -11.0,
    "riser": -9.5,
    "swish": -11.0,
    "slider_glide": -12.0,
    "chime": -10.0,
}
SFX_ROOM: dict[str, float] = {
    "whoosh": 0.10,
    "selection_sweep": 0.20,
    "menu_open": 0.20,
    "click": 0.15,
    "riser": 0.10,
    "swish": 0.15,
    "slider_glide": 0.15,
    "chime": 0.10,
}
SFX_HALL: dict[str, float] = {
    "whoosh": 0.15,
    "selection_sweep": 0.15,
    "menu_open": 0.10,
    "click": 0.0,
    "riser": 0.20,
    "swish": 0.10,
    "slider_glide": 0.10,
    "chime": 0.35,
}

NOTE_OFFSETS: dict[str, int] = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# Harmony (D minor): i - VI - III - VII, one chord per bar; the finale goes VI - VII into an F major final hit.
CYCLE = ("Dm", "Bb", "F", "C")
VOICING: dict[str, tuple[str, ...]] = {
    "Dm": ("D3", "A3", "D4", "F4", "A4", "D5"),
    "Bb": ("Bb2", "F3", "Bb3", "D4", "F4", "Bb4"),
    "F": ("F3", "A3", "C4", "F4", "A4", "C5"),
    "C": ("C3", "G3", "C4", "E4", "G4", "C5"),
}
STAB_NOTES: dict[str, tuple[str, ...]] = {
    "Dm": ("A3", "D4", "F4", "A4", "D5", "F5"),
    "Bb": ("F3", "Bb3", "D4", "F4", "Bb4", "D5"),
    "F": ("A3", "C4", "F4", "A4", "C5", "F5"),
    "C": ("G3", "C4", "E4", "G4", "C5", "E5"),
}
ROOT: dict[str, str] = {"Dm": "D2", "Bb": "Bb1", "F": "F1", "C": "C2"}
# The pluck motif: four rising chord tones in 16ths to a C6 that every chord shares, and an answer on the 7th 16th.
MOTIF_STEPS = (0, 1, 2, 3, 6)
MOTIF_VEL = (0.80, 0.68, 0.78, 1.0, 0.82)
MOTIF: dict[str, tuple[str, ...]] = {
    "Dm": ("D5", "F5", "A5", "C6", "A5"),
    "Bb": ("D5", "F5", "Bb5", "C6", "Bb5"),
    "F": ("C5", "F5", "A5", "C6", "A5"),
    "C": ("C5", "E5", "G5", "C6", "G5"),
}
FINALE_CHORDS = ("Bb", "C")
FINALE_MOTIF: dict[str, tuple[str, ...]] = {
    "Bb": ("D5", "F5", "Bb5", "C6", "D6"),
    "C": (
        "C5",
        "E5",
        "G5",
        "C6",
        "E6",
    ),  # the E6 leads into the F6 bell of the final hit
}
FINAL_PAD = ("F3", "C4", "F4", "A4", "C5")
BELLS = ("F6", "A6", "C7")

SAW_SPREAD = (
    -1.0,
    -0.62,
    -0.31,
    0.0,
    0.29,
    0.60,
    1.0,
)  # 7 voices, JP-8000-like spacing
SAW_PAN = (-0.9, 0.55, -0.4, 0.0, 0.4, -0.55, 0.9)
PAD_SPREAD = (-1.0, -0.5, 0.0, 0.5, 1.0)
PAD_PAN = (-0.7, 0.35, 0.0, -0.35, 0.7)
HAT_OSC_HZ = (
    205.3,
    304.4,
    369.6,
    522.7,
    540.0,
    800.0,
)  # the TR-808's six metallic oscillators
BELL_PARTIALS = (
    (1.0, 1.0, 1.0),
    (2.0, 0.5, 0.6),
    (2.76, 0.32, 0.45),
    (4.07, 0.16, 0.3),
    (5.43, 0.1, 0.22),
    (6.8, 0.05, 0.15),
)  # fmt: skip  (ratio, amplitude, decay factor)
SUB_DRIVE, SUB_BIAS = (
    2.5,
    0.25,
)  # asymmetric tanh: 2nd harmonic about -14 dB, 3rd -16 dB, 4th -21 dB

# K-weighting (ITU-R BS.1770-4) at 48 kHz.
K1_B = (1.53512485958697, -2.69169618940638, 1.19839281085285)
K1_A = (1.0, -1.69065929318241, 0.73248077421585)
K2_B = (1.0, -2.0, 1.0)
K2_A = (1.0, -1.99004745483398, 0.99007225036621)


# ---------------------------------------------------------------------------------------------
# Small helpers


def note(name: str) -> int:
    """MIDI number of a note name such as 'F#4' or 'Bb1' (C4 = 60, A4 = 69)."""
    m = re.fullmatch(r"([A-G])([#b]?)(\d)", name)
    if m is None:
        raise ValueError(f"bad note name: {name!r}")
    shift = {"": 0, "#": 1, "b": -1}[m.group(2)]
    return 12 * (int(m.group(3)) + 1) + NOTE_OFFSETS[m.group(1)] + shift


def hz(m: float) -> float:
    """Equal-tempered frequency, A4 = 440 Hz."""
    return 440.0 * math.pow(2.0, (m - 69.0) / 12.0)


def nhz(name: str) -> float:
    return hz(note(name))


def db(x: float) -> float:
    return float(10.0 ** (x / 20.0))


def rng_for(key: str) -> np.random.Generator:
    """A generator seeded from a stable name, so moving one event never changes another's noise."""
    return np.random.default_rng(zlib.crc32(key.encode("utf-8")))


def noise(n: int, key: str) -> Arr:
    out: Arr = rng_for(key).standard_normal(n)
    return out


def rise(n: int) -> Arr:
    """Raised-cosine ramp 0 -> 1 over n samples; the first sample is exactly 0."""
    k = np.arange(n, dtype=np.float64)
    out: Arr = 0.5 - 0.5 * np.cos(np.pi * k / max(n, 1))
    return out


def fall(n: int) -> Arr:
    """Raised-cosine ramp 1 -> 0 over n samples; the last sample is exactly 0."""
    k = np.arange(1, n + 1, dtype=np.float64)
    out: Arr = 0.5 + 0.5 * np.cos(np.pi * k / max(n, 1))
    return out


def shape_ends(
    x: Arr, attack: float = MIN_ATTACK_S, release: float = MIN_RELEASE_S
) -> Arr:
    """Raised-cosine attack and release on the last axis (never shorter than 2 ms / 15 ms); ends on an exact 0."""
    y = x.copy()
    n = y.shape[-1]
    na = min(n, max(1, int(round(max(attack, MIN_ATTACK_S) * FS))))
    nr = min(n, max(1, int(round(max(release, MIN_RELEASE_S) * FS))))
    y[..., :na] *= rise(na)
    y[..., n - nr :] *= fall(nr)
    return y


def decay_env(n: int, tau: float) -> Arr:
    out: Arr = np.exp(-np.arange(n) / (tau * FS))
    return out


def peak_norm(x: Arr) -> Arr:
    out: Arr = x / max(1e-12, float(np.max(np.abs(x))))
    return out


def humanize(rng: np.random.Generator, vel: float, spread: float = 0.05) -> float:
    return float(np.clip(vel * (1.0 + spread * rng.standard_normal()), 0.05, 1.0))


def lowpass1(x: Arr, fc: float) -> Arr:
    a = 1.0 - math.exp(-2.0 * math.pi * fc / FS)
    out: Arr = signal.lfilter([a], [1.0, a - 1.0], x, axis=-1)
    return out


def butter_sos(order: int, fc: float | tuple[float, float], kind: str) -> Arr:
    out: Arr = signal.butter(order, fc, btype=kind, fs=FS, output="sos")
    return out


def sosf(sos: Arr, x: Arr) -> Arr:
    out: Arr = signal.sosfilt(sos, x, axis=-1)
    return out


def rbj(fc: float, q: float, kind: str) -> tuple[Arr, Arr]:
    """RBJ-cookbook biquad: 'lp' low-pass, 'hp' high-pass or 'bp' band-pass (0 dB peak)."""
    fc = min(max(fc, 20.0), 0.45 * FS)
    w0 = 2.0 * math.pi * fc / FS
    alpha = math.sin(w0) / (2.0 * q)
    c = math.cos(w0)
    if kind == "lp":
        b = [(1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0]
    elif kind == "hp":
        b = [(1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0]
    else:
        b = [alpha, 0.0, -alpha]
    a = [1.0 + alpha, -2.0 * c, 1.0 - alpha]
    return np.array(b) / a[0], np.array(a) / a[0]


def tv_biquad(x: Arr, fc: Arr, q: float, kind: str, block: int = 64) -> Arr:
    """A biquad whose cut-off/centre follows fc, updated every `block` samples."""
    y = np.empty_like(x)
    zi = np.zeros(2)
    for i in range(0, len(x), block):
        j = min(i + block, len(x))
        b, a = rbj(float(fc[(i + j) // 2]), q, kind)
        seg, zi = signal.lfilter(b, a, x[i:j], zi=zi)
        y[i:j] = seg
    return y


def lp4(x: Arr, fc: Arr) -> Arr:
    """4th-order low-pass (two biquads with Butterworth Qs) following fc; (n,) or (2, n)."""
    if x.ndim == 2:
        return np.vstack([lp4(x[c], fc) for c in range(x.shape[0])])
    return tv_biquad(tv_biquad(x, fc, 0.5412, "lp"), fc, 1.3066, "lp")


def stereo(x: Arr, pan: float) -> Arr:
    """Constant-power pan for mono; balance for stereo."""
    if x.ndim == 2:
        if pan == 0.0:
            return x
        return np.vstack((min(1.0, 1.0 - pan) * x[0], min(1.0, 1.0 + pan) * x[1]))
    th = (min(max(pan, -1.0), 1.0) + 1.0) * math.pi / 4.0
    return np.vstack((math.cos(th) * x, math.sin(th) * x))


def pan_sweep(x: Arr, p0: float, p1: float) -> Arr:
    th = (np.linspace(p0, p1, len(x)) + 1.0) * math.pi / 4.0
    return np.vstack((np.cos(th) * x, np.sin(th) * x))


def place(buf: Arr, t: float, x: Arr, gain: float) -> None:
    i0 = int(round(t * FS))
    a = max(0, i0)
    b = min(buf.shape[1], i0 + x.shape[1])
    if b > a:
        buf[:, a:b] += gain * x[:, a - i0 : b - i0]


def glide_phase(f: Arr) -> Arr:
    out: Arr = 2.0 * math.pi * (np.cumsum(f) - f[0]) / FS
    return out


def saw(f: float, n: int, phase0: float) -> Arr:
    """Band-limited (PolyBLEP) sawtooth."""
    dt = f / FS
    ph = (phase0 + dt * np.arange(n)) % 1.0
    y: Arr = 2.0 * ph - 1.0
    lo = ph < dt
    u = ph[lo] / dt
    y[lo] -= 2.0 * u - u * u - 1.0
    hi = ph > 1.0 - dt
    u = (ph[hi] - 1.0) / dt
    y[hi] -= u * u + 2.0 * u + 1.0
    return y


def square(f: float, n: int, phase0: float) -> Arr:
    """Band-limited square (+-1): two PolyBLEP saws half a cycle apart."""
    out: Arr = saw(f, n, phase0) - saw(f, n, (phase0 + 0.5) % 1.0)
    return out


def band_sweep(n: int, fc: Arr, q: float, key: str) -> Arr:
    """Noise through a band-pass whose centre follows fc, held at one level along the sweep (unit RMS)."""
    y: Arr = tv_biquad(noise(n, key), fc, q, "bp") * np.sqrt(float(np.mean(fc)) / fc)
    return y / max(1e-12, float(np.sqrt(np.mean(y * y))))


def swell_env(n: int, peak_at: float, floor: float, up: float = 2.0, down: float = 1.6, onset: float = 0.004,
              release: float = 0.025) -> Arr:  # fmt: skip
    """Quick onset to `floor`, a rise to 1 at `peak_at` (fraction), then a fall to an exact zero."""
    u = np.arange(n) / n
    rising = floor + (1.0 - floor) * np.clip(u / peak_at, 0.0, 1.0) ** up
    falling = np.clip((1.0 - u) / (1.0 - peak_at), 0.0, 1.0) ** down
    env: Arr = np.where(u < peak_at, rising, falling)
    return shape_ends(env, onset, release)


# ---------------------------------------------------------------------------------------------
# Instruments (mono arrays are (n,), stereo (2, n); every one starts and ends through shape_ends)


def kick(vel: float, key: str, lp: float = 0.0) -> Arr:
    """Punchy kick: a sine swept 160 -> 48 Hz (tau 35 ms), the body about 20 dB down by 280 ms, a 4 ms click and
    tanh drive. lp > 0 muffles it (the heartbeat)."""
    n = int(0.40 * FS)
    t = np.arange(n) / FS
    f = 48.0 + 112.0 * np.exp(-t / 0.035)
    amp = np.minimum(1.0, 1.3 * np.exp(-t / 0.085))
    body = np.tanh(2.4 * np.sin(glide_phase(f)) * amp) / math.tanh(2.4)
    nc = int(0.004 * FS)
    click = peak_norm(
        sosf(butter_sos(2, (1800.0, 9000.0), "bandpass"), noise(nc, key)) * fall(nc)
    )
    y: Arr = body.copy()
    y[:nc] += 0.4 * click
    if lp > 0.0:
        y = peak_norm(sosf(butter_sos(2, lp, "lowpass"), y))
    return vel * shape_ends(y, 0.002, 0.03)


def sat_sine(ph: Arr) -> Arr:
    """sin(ph) through an asymmetric tanh, DC-free and peak-normalised: the 2nd, 3rd and 4th harmonics carry the
    sub on a phone speaker."""
    th = np.linspace(0.0, 2.0 * math.pi, 4096, endpoint=False)
    ref = np.tanh(SUB_DRIVE * (np.sin(th) + SUB_BIAS))
    dc = float(np.mean(ref))
    pk = float(np.max(np.abs(ref - dc)))
    out: Arr = (np.tanh(SUB_DRIVE * (np.sin(ph) + SUB_BIAS)) - dc) / pk
    return out


def sub_note(freq: float, length: float, tau: float, punch: float = 0.3) -> Arr:
    """One 808-style note: a short pitch drop at the attack for punch, then an exponential decay."""
    n = int(length * FS)
    t = np.arange(n) / FS
    f = freq * (1.0 + punch * np.exp(-t / 0.015))
    return shape_ends(sat_sine(glide_phase(f)) * np.exp(-t / tau), 0.004, 0.04)


def sub_line(
    freqs: Sequence[float],
    bounds: Sequence[float],
    glide: float = 0.020,
    release: float = 0.05,
) -> Arr:
    """A sustained sub: freqs[i] from bounds[i] to bounds[i + 1] (s), gliding into each new note over `glide`."""
    n = int(round((bounds[-1] - bounds[0] + release) * FS))
    f = np.empty(n)
    ng = max(1, int(round(glide * FS)))
    for i, fr in enumerate(freqs):
        i0 = int(round((bounds[i] - bounds[0]) * FS))
        i1 = n if i == len(freqs) - 1 else int(round((bounds[i + 1] - bounds[0]) * FS))
        f[i0:i1] = fr
        if i > 0:
            m = min(ng, i1 - i0)
            u = np.arange(1, m + 1) / ng
            f[i0 : i0 + m] = freqs[i - 1] * (fr / freqs[i - 1]) ** (
                u * u * (3.0 - 2.0 * u)
            )
    return shape_ends(sat_sine(glide_phase(f)), 0.006, release)


def snare(vel: float, key: str, tone: float = 190.0) -> Arr:
    """Snare: a pitched body (tone, dropping from +35 %) and 1.5-9 kHz noise, tanh-glued."""
    n = int(0.26 * FS)
    t = np.arange(n) / FS
    f = tone * (1.0 + 0.35 * np.exp(-t / 0.015))
    body = np.sin(glide_phase(f)) * np.exp(-t / 0.045)
    nz = peak_norm(
        sosf(butter_sos(2, (1500.0, 9000.0), "bandpass"), noise(n, key))
        * np.exp(-t / 0.075)
    )
    y = np.tanh(1.6 * (0.55 * body + 0.8 * nz)) / math.tanh(1.6)
    return vel * shape_ends(peak_norm(y), 0.002, 0.03)


def clap(vel: float, key: str) -> Arr:
    """Clap: three 1-4 kHz noise bursts 10 ms apart and a 140 ms tail; decorrelated noise per side."""
    n = int(0.22 * FS)
    t = np.arange(n) / FS
    env = np.zeros(n)
    na = int(0.002 * FS)
    for j, off in enumerate((0.0, 0.010, 0.020)):
        i0 = int(off * FS)
        tt = t[: n - i0]
        burst = (
            np.exp(-tt / 0.0045)
            if j < 2
            else 0.75 * np.exp(-tt / 0.0045) + 0.55 * np.exp(-tt / 0.045)
        )
        burst[:na] *= rise(na)
        env[i0:] += burst
    out = np.vstack(
        [
            sosf(butter_sos(2, (1000.0, 4000.0), "bandpass"), noise(n, f"{key}.{c}"))
            for c in range(2)
        ]
    )
    return vel * shape_ends(peak_norm(out * env), 0.002, 0.03)


def hat(vel: float, key: str, length: float, tau: float) -> Arr:
    """Hi-hat: noise plus the 808's six square oscillators (scaled up), high-passed at 7 kHz."""
    n = int(length * FS)
    rng = rng_for(key)
    metal = np.zeros(n)
    for f in HAT_OSC_HZ:
        metal += square(4.3 * f, n, float(rng.uniform()))
    x = 0.6 * noise(n, key) + 0.4 * metal / math.sqrt(len(HAT_OSC_HZ))
    x = sosf(butter_sos(4, 7000.0, "highpass"), x) * decay_env(n, tau)
    return vel * shape_ends(peak_norm(x), 0.002, 0.015)


def tick(vel: float, key: str) -> Arr:
    """A dry 16th tick (4.5-11 kHz noise, 6 ms decay)."""
    n = int(0.04 * FS)
    x = sosf(butter_sos(2, (4500.0, 11000.0), "bandpass"), noise(n, key)) * decay_env(
        n, 0.006
    )
    return vel * shape_ends(peak_norm(x), 0.002, 0.015)


def supersaw(freqs: Sequence[float], dur: float, key: str, fc: Arr | float, detune: float = 15.0,
             spread: Sequence[float] = SAW_SPREAD, pans: Sequence[float] = SAW_PAN, attack: float = 0.004,
             release: float = 0.04, hp: float = 110.0) -> Arr:  # fmt: skip
    """Stereo supersaw chord: PolyBLEP saws per note spread +-detune cents and across the stereo field, a 4th-order
    low-pass at fc (constant or per sample) and a high-pass that leaves the low end to the sub."""
    n = int(round(dur * FS))
    rng = rng_for(key)
    acc = np.zeros((2, n))
    for f0 in freqs:
        for sp, pan in zip(spread, pans):
            s = saw(f0 * 2.0 ** (detune * sp / 1200.0), n, float(rng.uniform()))
            th = (pan + 1.0) * math.pi / 4.0
            acc[0] += math.cos(th) * s
            acc[1] += math.sin(th) * s
    acc /= math.sqrt(len(freqs) * len(spread))
    if isinstance(fc, float):
        acc = sosf(butter_sos(4, fc, "lowpass"), acc)
    else:
        acc = lp4(acc, fc)
    if hp > 0.0:
        acc = sosf(butter_sos(2, hp, "highpass"), acc)
    return shape_ends(acc, attack, release)


def chord_hz(chord: str, table: dict[str, tuple[str, ...]]) -> list[float]:
    return [nhz(x) for x in table[chord]]


def stab(chord: str, key: str, decay: float, gate: float, bright: float = 1.0) -> Arr:
    """A short bright supersaw chord: the filter snaps open to ~8 kHz and closes over ~150 ms."""
    dur = gate + 0.05
    n = int(round(dur * FS))
    t = np.arange(n) / FS
    fc = 1200.0 + 7000.0 * bright * np.exp(-t / 0.15)
    x: Arr = supersaw(
        chord_hz(chord, STAB_NOTES), dur, key, fc, attack=0.002, release=0.05
    ) * decay_env(n, decay)
    return x


def pluck(name: str, vel: float, key: str, length: float = 0.5) -> Arr:
    """Bright pluck: saw plus square, +-7 cents across the channels, a filter envelope with a 120 ms decay."""
    f0 = nhz(name)
    n = int(length * FS)
    t = np.arange(n) / FS
    rng = rng_for(key)
    fc = 700.0 + (3000.0 + 6000.0 * vel) * np.exp(-t / 0.12)
    out = np.zeros((2, n))
    for c, cents in enumerate((-7.0, 7.0)):
        f = f0 * 2.0 ** (cents / 1200.0)
        p = float(rng.uniform())
        out[c] = tv_biquad(
            0.6 * saw(f, n, p) + 0.4 * square(f, n, (p + 0.25) % 1.0), fc, 1.4, "lp"
        )
    return vel * shape_ends(peak_norm(out * decay_env(n, 0.22)), 0.002, 0.03)


def bell(name: str, vel: float, decay: float, key: str) -> Arr:
    """Additive bell: six partials (1, 2, 2.76, 4.07, 5.43, 6.8), the upper ones dying first."""
    f = nhz(name)
    n = int(min(6.0, 5.0 * decay) * FS)
    t = np.arange(n) / FS
    rng = rng_for(key)
    y = np.zeros(n)
    norm = 0.0
    for ratio, amp, dk in BELL_PARTIALS:
        if ratio * f > 15000.0:
            continue
        ph = float(rng.uniform(0.0, 2.0 * math.pi))
        y += (
            amp * np.sin(2.0 * math.pi * ratio * f * t + ph) * np.exp(-t / (decay * dk))
        )
        norm += amp
    return vel * shape_ends(y / norm, 0.002, 0.04)


def impact(key: str, length: float = 1.3, tau: float = 0.38) -> Arr:
    """Impact: a tanh-driven sine boom 70 -> 30 Hz over 700 ms plus a 350 ms noise burst whose low-pass falls."""
    n = int(length * FS)
    t = np.arange(n) / FS
    f = 70.0 * (30.0 / 70.0) ** np.clip(t / 0.7, 0.0, 1.0)
    boom = np.tanh(1.8 * np.sin(glide_phase(f)) * np.exp(-t / tau)) / math.tanh(1.8)
    nb = int(0.35 * FS)
    tb = np.arange(nb) / FS
    fc = 300.0 * (7000.0 / 300.0) ** np.exp(-tb / 0.07)
    out = np.zeros((2, n))
    for c in range(2):
        burst = tv_biquad(noise(nb, f"{key}.{c}"), fc, 0.707, "lp") * np.exp(-tb / 0.07)
        out[c, :nb] += 0.55 * peak_norm(shape_ends(burst, 0.002, 0.08))
        out[c] += boom
    return shape_ends(peak_norm(out), 0.002, 0.1)


def crack(key: str) -> Arr:
    """Noise crack: 1-10 kHz, 25 ms decay, stereo."""
    n = int(0.16 * FS)
    out = np.vstack(
        [
            sosf(butter_sos(2, (1000.0, 10000.0), "bandpass"), noise(n, f"{key}.{c}"))
            for c in range(2)
        ]
    )
    return shape_ends(peak_norm(out * decay_env(n, 0.025)), 0.002, 0.03)


def noise_riser(d: float, key: str, f0: float, f1: float, tone: tuple[float, float] | None, floor_db: float,
                q: float = 1.2) -> Arr:  # fmt: skip
    """Riser: noise band-pass sweeping f0 -> f1 (plus an optional rising sine), an exponential swell from floor_db
    that ends exactly d seconds after it starts."""
    n = int(round(d * FS))
    u = np.arange(n) / n
    fc = f0 * (f1 / f0) ** (u**1.4)
    out = np.vstack([band_sweep(n, fc, q, f"{key}.{c}") for c in range(2)])
    if tone is not None:
        out += 0.35 * np.sin(glide_phase(tone[0] * (tone[1] / tone[0]) ** (u**1.2)))
    env = 10.0 ** (floor_db * (1.0 - u) ** 1.3 / 20.0)
    return shape_ends(out * env, 0.004, 0.02)


def reverse_swell(freqs: Sequence[float], d: float, key: str, ir: Arr) -> Arr:
    """A reverse swell ending exactly d seconds after it starts: the hall's response to a bright chord and the chord
    itself, reversed, plus a reversed cymbal."""
    nd = int(round(d * FS))
    src = supersaw(freqs, 0.3, f"{key}.src", 6000.0, release=0.05)
    ns = src.shape[1]
    k0 = int(0.02 * FS)  # skip the hall's pre-delay
    wet = np.zeros((2, nd))
    for c in range(2):
        full = signal.fftconvolve(src[c], ir[c])[k0 : k0 + nd]
        wet[c, : len(full)] = full
    dry = np.zeros((2, nd))
    m = min(ns, nd)
    dry[:, nd - m :] = (src * decay_env(ns, 0.1))[:, :m][:, ::-1]
    t = np.arange(nd) / FS
    cym = np.vstack(
        [
            sosf(butter_sos(2, 5000.0, "highpass"), noise(nd, f"{key}.cym.{c}"))
            for c in range(2)
        ]
    )
    x = (
        peak_norm(wet[:, ::-1])
        + 0.45 * peak_norm(dry)
        + 0.3 * peak_norm(cym * np.exp(-(d - t) / 0.12))
    )
    return shape_ends(peak_norm(x), 0.01, 0.015)


# ---------------------------------------------------------------------------------------------
# Effects (each returns stereo, starting exactly at its `t`)


def sfx_whoosh(d: float, key: str) -> Arr:
    """Rising out of the dark: band-passed air 160 Hz -> 2.4 kHz -> 700 Hz over a rumble rising 40 -> 95 Hz."""
    n = int(round(d * FS))
    u = np.arange(n) / n
    peak = 0.6
    lo, top, out = math.log(160.0), math.log(2400.0), math.log(700.0)
    lf = np.where(
        u < peak,
        lo + (top - lo) * u / peak,
        top + (out - top) * (u - peak) / (1.0 - peak),
    )
    air = band_sweep(n, np.exp(lf), 0.9, key)
    rumble = np.sin(glide_phase(40.0 * (95.0 / 40.0) ** np.minimum(u / peak, 1.0)))
    x = (air + 0.5 * rumble) * swell_env(n, peak, 0.3, 1.8, 1.6, 0.004, 0.05)
    return pan_sweep(x, -0.5, 0.4)


def sfx_selection_sweep(d: float, key: str) -> Arr:
    n = int(round(d * FS))
    u = np.arange(n) / n
    air = band_sweep(n, 2400.0 * (7000.0 / 2400.0) ** u, 1.4, key)
    d6, a6 = nhz("D6"), nhz("A6")
    glide = np.sin(glide_phase(d6 * (a6 / d6) ** u))
    x = (air + 0.35 * glide) * swell_env(n, 0.7, 0.45, 1.2, 1.4, 0.004, 0.05)
    return pan_sweep(x, -0.3, 0.3)


def sfx_menu_open(key: str) -> Arr:
    n = int(0.5 * FS)
    t = np.arange(n) / FS
    f = nhz("A5")
    y = (
        np.sin(2.0 * math.pi * f * t) * np.exp(-t / 0.18)
        + 0.30 * np.sin(4.0 * math.pi * f * t) * np.exp(-t / 0.07)
        + 0.10 * np.sin(6.0 * math.pi * f * t) * np.exp(-t / 0.04)
    )
    pick = peak_norm(lowpass1(noise(n, key), 4000.0) * np.exp(-t / 0.003))
    return stereo(shape_ends(y + 0.08 * pick, 0.002, 0.02), 0.12)


def sfx_click(key: str) -> Arr:
    """A crisp UI click: a 2-7 kHz noise tick, a 2.8 kHz ring and a short 1.3 kHz body."""
    n = int(0.09 * FS)
    t = np.arange(n) / FS
    tk = peak_norm(
        sosf(butter_sos(2, (2000.0, 7000.0), "bandpass"), noise(n, key))
        * np.exp(-t / 0.0025)
    )
    ring = np.sin(2.0 * math.pi * 2800.0 * t) * np.exp(-t / 0.006)
    body = np.sin(2.0 * math.pi * 1300.0 * t) * np.exp(-t / 0.014)
    return stereo(shape_ends(0.5 * tk + 0.3 * ring + 0.4 * body, 0.002, 0.02), 0.0)


def sfx_riser(d: float, key: str) -> Arr:
    """Noise band-pass 300 Hz -> 8 kHz plus a sine rising D4 -> D6, swelling to exactly its `until`."""
    return noise_riser(d, key, 300.0, 8000.0, (nhz("D4"), nhz("D6")), -14.0)


def sfx_swish(d: float, key: str, direction: float) -> Arr:
    n = int(round(d * FS))
    u = np.arange(n) / n
    peak = 0.7
    lo, top, out = math.log(900.0), math.log(5200.0), math.log(2500.0)
    lf = np.where(
        u < peak,
        lo + (top - lo) * u / peak,
        top + (out - top) * (u - peak) / (1.0 - peak),
    )
    x = band_sweep(n, np.exp(lf), 1.1, key) * swell_env(
        n, peak, 0.3, 1.6, 1.4, 0.004, 0.02
    )
    return pan_sweep(x, -0.6 * direction, 0.6 * direction)


def sfx_slider(d: float, key: str) -> Arr:
    """Speed 1.0x -> 1.2x is almost exactly a minor third: a glide E5 -> G5 (both tones of the C chord under it)."""
    n = int(round(d * FS))
    u = np.arange(n) / n
    s = u * u * (3.0 - 2.0 * u)
    e5, g5 = nhz("E5"), nhz("G5")
    ph = glide_phase(e5 * (g5 / e5) ** s)
    air = band_sweep(n, 3000.0 * (5000.0 / 3000.0) ** s, 2.0, key)
    y = (np.sin(ph) + 0.15 * np.sin(2.0 * ph) + 0.12 * air) * (0.8 + 0.2 * s)
    return pan_sweep(shape_ends(y, 0.01, 0.04), -0.15, 0.15)


def sfx_chime(key: str) -> Arr:
    """The icon's three sound arcs: a bright F major bell triad, F6 A6 C7, 45 ms apart, left to right."""
    n = int(1.6 * FS)
    out = np.zeros((2, n))
    for j, (name, pan) in enumerate((("F6", -0.35), ("A6", 0.0), ("C7", 0.35))):
        i0 = int(round(0.045 * j * FS))
        b = bell(name, 1.0 - 0.1 * j, 0.45, f"{key}.{j}")[: n - i0]
        out[:, i0 : i0 + len(b)] += stereo(b, pan)
    return shape_ends(out, 0.002, 0.05)


def render_effect(entry: dict[str, Any], idx: int) -> Arr:
    typ = str(entry["type"])
    t = float(entry["t"])
    d = float(entry["until"]) - t if "until" in entry else 0.0
    key = f"sfx.{idx}.{typ}"
    if typ == "whoosh":
        return sfx_whoosh(max(d, 0.25), key)
    if typ == "selection_sweep":
        return sfx_selection_sweep(max(d, 0.2), key)
    if typ == "menu_open":
        return sfx_menu_open(key)
    if typ == "riser":
        return sfx_riser(max(d, 0.15), key)
    if typ == "swish":
        return sfx_swish(max(d, 0.15), key, 1.0 if idx % 2 else -1.0)
    if typ == "slider_glide":
        return sfx_slider(max(d, 0.1), key)
    if typ == "chime":
        return sfx_chime(key)
    return sfx_click(
        key
    )  # 'click', and a click for any unknown type (flagged in the report)


# ---------------------------------------------------------------------------------------------
# Score


@dataclass(frozen=True)
class Event:
    group: str
    t: float
    x: Arr
    gain_db: float
    pan: float
    room: float
    hall: float
    delay: float
    duck: str


@dataclass
class Score:
    events: list[Event] = field(default_factory=list)
    kicks: dict[str, list[float]] = field(default_factory=dict)
    marks: dict[str, list[float]] = field(default_factory=dict)

    def add(self, group: str, t: float, x: Arr, gain_db: float = 0.0, pan: float = 0.0, room: float = 0.0,
            hall: float = 0.0, delay: float = 0.0, duck: str = "") -> None:  # fmt: skip
        self.events.append(
            Event(group, t, x, GROUP_DB[group] + gain_db, pan, room, hall, delay, duck)
        )

    def kick_at(self, source: str, t: float) -> None:
        self.kicks.setdefault(source, []).append(t)

    def mark(self, kind: str, t: float) -> None:
        self.marks.setdefault(kind, []).append(t)


@dataclass(frozen=True)
class Grid:
    t0: float
    beat: float
    tempo: float
    unit: str  # the grid the section's last hit lands on: beat, 8th, 16th or none


def fit_grid(t0: float, hit: float, bpm: float, nudge: float = 3.0) -> Grid:
    """The tempo within +-nudge BPM that puts `hit` on a beat, else an 8th, else a 16th."""
    span = hit - t0
    for unit, name in ((1.0, "beat"), (0.5, "8th"), (0.25, "16th")):
        best: tuple[float, float] | None = None
        k = 1
        while True:
            tempo = 60.0 * k * unit / span
            if tempo > bpm + nudge + 1e-9:
                break
            if abs(tempo - bpm) <= nudge + 1e-9 and (
                best is None or abs(tempo - bpm) < abs(best[0] - bpm)
            ):
                best = (tempo, k * unit)
            k += 1
        if best is not None:
            return Grid(t0, 60.0 / best[0], best[0], name)
    return Grid(t0, 60.0 / bpm, bpm, "none")


def bar_bounds(t0: float, t1: float, bar: float) -> list[float]:
    out = [t0]
    while out[-1] + bar < t1 - 1e-6:
        out.append(t0 + len(out) * bar)
    out.append(t1)
    return out


def duck_curve(n: int, times: Sequence[float], depth_db: float, hold: float, release: float,
               attack: float = 0.003) -> Arr:  # fmt: skip
    """Sidechain gain: a raised-cosine dip of depth_db at each kick, held, then an S-curve back to 1 over release."""
    d = 1.0 - db(-depth_db)
    nr = int(release * FS)
    u = np.arange(nr) / nr
    shape = np.concatenate(
        (
            d * rise(int(attack * FS)),
            np.full(int(hold * FS), d),
            d * (1.0 - u * u * (3.0 - 2.0 * u)),
        )
    )
    g = np.ones(n)
    for tk in times:
        i0 = int(round(tk * FS))
        i1 = min(n, i0 + len(shape))
        if i1 > i0 >= 0:
            g[i0:i1] = np.minimum(g[i0:i1], 1.0 - shape[: i1 - i0])
    return g


def mixdown(sc: Score, n: int) -> tuple[dict[str, Arr], dict[str, Arr]]:
    """Every event into its group, sidechained where it asks to be, with its room, hall and delay sends."""
    ducks = {
        kind: duck_curve(n, sc.kicks.get(src, []), depth, hold, rel)
        for kind, (src, depth, hold, rel) in DUCKS.items()
    }
    groups: dict[str, Arr] = {}
    sends = {bus: np.zeros((2, n)) for bus in ("room", "hall", "delay")}
    for ev in sc.events:
        st = stereo(ev.x, ev.pan) * db(ev.gain_db)
        i0 = int(round(ev.t * FS))
        a, b = max(0, i0), min(n, i0 + st.shape[1])
        if b <= a:
            continue
        seg = st[:, a - i0 : b - i0]
        if ev.duck:
            seg = seg * ducks[ev.duck][a:b]
        if ev.group not in groups:
            groups[ev.group] = np.zeros((2, n))
        groups[ev.group][:, a:b] += seg
        for bus, amount in (("room", ev.room), ("hall", ev.hall), ("delay", ev.delay)):
            if amount > 0.0:
                sends[bus][:, a:b] += amount * seg
    return groups, sends


# ---------------------------------------------------------------------------------------------
# Arrangement


def groove(
    sc: Score, t0: float, t1: float, g: Grid, key: str, rng: np.random.Generator
) -> None:
    """Kick on every beat, clap over a snare body on 2 and 4, swung 16th hats with an open hat on each off-beat."""
    q = g.beat
    s16 = q / 4.0
    swing = (SWING - 0.5) * 2.0 * s16
    k = 0
    while t0 + k * q < t1 - 1e-6:
        t = t0 + k * q
        sc.add("kick", t, kick(1.0 if k % 4 == 0 else 0.94, f"{key}.kick.{k}"))
        sc.kick_at("main", t)
        if k % 2 == 1:
            sc.add(
                "clap", t, clap(humanize(rng, 0.95, 0.03), f"{key}.clap.{k}"), room=0.35
            )
            sc.add("snare", t, snare(0.8, f"{key}.snare.{k}"), gain_db=-4.0, room=0.2)
        k += 1
    j = 0
    while t0 + j * s16 < t1 - 1e-6:
        pos = j % 4
        t = t0 + j * s16 + (swing if pos % 2 else 0.0)
        if pos == 2:
            choke = (
                t0 + (j + 1) * s16 + swing - t + MIN_RELEASE_S
            )  # the next closed hat chokes it
            open_hat = hat(
                humanize(rng, 0.75, 0.05), f"{key}.open.{j}", min(0.175, choke), 0.055
            )
            sc.add("hat", t, open_hat, pan=-0.18, room=0.1)
        else:
            vel = (0.9, 0.5, 0.0, 0.62)[pos]
            sc.add(
                "hat",
                t,
                hat(humanize(rng, vel, 0.08), f"{key}.hat.{j}", 0.05, 0.011),
                pan=0.2,
                room=0.06,
            )
        j += 1


def motif(
    sc: Score, t: float, notes: Sequence[str], g: Grid, key: str, delay: float = 0.3
) -> None:
    """The pluck motif from t, swung like the hats, into the ping-pong delay."""
    s16 = g.beat / 4.0
    swing = (SWING - 0.5) * 2.0 * s16
    for i, (step, name, vel) in enumerate(zip(MOTIF_STEPS, notes, MOTIF_VEL)):
        ti = t + step * s16 + (swing if step % 2 else 0.0)
        pan = -0.15 if i % 2 else 0.15
        sc.add(
            "pluck",
            ti,
            pluck(name, vel, f"{key}.{i}"),
            pan=pan,
            room=0.08,
            hall=0.12,
            delay=delay,
        )


def stab_hit(sc: Score, t: float, chord: str, key: str) -> None:
    """A hard, short hit that must die fast: kick, sub, bright supersaw stab, noise crack, a small room."""
    sc.add("kick", t, kick(1.0, f"{key}.kick"))
    sc.kick_at("main", t)
    sc.add("sub", t, sub_note(nhz(ROOT[chord]), 0.5, 0.11))
    sc.add("stab", t, stab(chord, f"{key}.stab", 0.13, 0.4), room=0.22, hall=0.04)
    sc.add("crack", t, crack(f"{key}.crack"), room=0.3)
    sc.mark("hit", t)


def build(
    sc: Score,
    tb: float,
    hit: float,
    g: Grid,
    chord: str,
    key: str,
    rng: np.random.Generator,
) -> None:
    """The run-up to a hit: the chord's low-pass opens 350 Hz -> 7 kHz, an 8th then 16th snare roll, rising noise."""
    span = hit - tb
    q = g.beat
    n = int(round((span + 0.02) * FS))
    u = np.clip(np.arange(n) / FS / span, 0.0, 1.0)
    fc = 350.0 * (7000.0 / 350.0) ** (u**1.5)
    ch = supersaw(
        chord_hz(chord, VOICING), span + 0.02, f"{key}.chords", fc, release=0.02
    )
    sc.add("chords", tb, ch * 10.0 ** (-6.0 * (1.0 - u) / 20.0), room=0.1, hall=0.1)
    half = tb + q * max(1, round(span / (2.0 * q)))
    times: list[float] = []
    k = 0
    while tb + k * q / 2.0 < half - 1e-6:
        times.append(tb + k * q / 2.0)
        k += 1
    k = 0
    while half + k * q / 4.0 < hit - 1e-6:
        times.append(half + k * q / 4.0)
        k += 1
    for i, t in enumerate(times):
        v = (t - tb) / span
        roll = snare(
            humanize(rng, 0.3 + 0.7 * v**1.2, 0.04),
            f"{key}.roll.{i}",
            tone=180.0 + 70.0 * v,
        )
        sc.add("snare", t, roll, gain_db=-6.0, pan=0.1 if i % 2 else -0.1, room=0.25)
    sc.add(
        "riser",
        tb,
        noise_riser(span, f"{key}.noise", 400.0, 9000.0, None, -28.0),
        hall=0.08,
    )


def arrange_tease(sc: Score, sec: dict[str, Any], g: Grid) -> None:
    """Dark and tense: a filtered heartbeat kick and sub pulse, a Dm pad and a noise riser swelling, 16th ticks
    creeping in from the middle, then one hard stab on the click."""
    sid = str(sec["id"])
    t0, hit = float(sec["downbeat"]), float(sec["last_hit"])
    span = hit - t0
    q = g.beat
    s16 = q / 4.0
    rng = rng_for(f"{sid}.human")
    k = 0
    while t0 + k * q < hit - 1e-6:
        t = t0 + k * q
        u = (t - t0) / span
        sc.add("heart", t, kick(0.8 + 0.2 * u, f"{sid}.lub.{k}", lp=180.0))
        sc.add("heart", t + s16, kick(0.5 + 0.15 * u, f"{sid}.dub.{k}", lp=140.0))
        sc.kick_at("heart", t)
        sc.add(
            "sub",
            t,
            sub_note(nhz(ROOT[CYCLE[0]]), 0.45, 0.16, punch=0.15),
            gain_db=-4.0 + 4.0 * u,
        )
        k += 1
    n = int(round((span + 0.03) * FS))
    u_pad = np.clip(np.arange(n) / FS / span, 0.0, 1.0)
    pad = supersaw([nhz(x) for x in ("D3", "F3", "A3", "D4")], span + 0.03, f"{sid}.pad",
                   250.0 * (2400.0 / 250.0) ** (u_pad**1.5), detune=10.0, spread=PAD_SPREAD, pans=PAD_PAN,
                   attack=0.3, release=0.03, hp=80.0)  # fmt: skip
    sc.add(
        "pad",
        t0,
        pad * 10.0 ** (-30.0 * (1.0 - u_pad) ** 1.6 / 20.0),
        duck="pad",
        hall=0.25,
    )
    tr = t0 + 0.1 * span
    riser = noise_riser(
        hit - tr, f"{sid}.riser", 300.0, 8000.0, (nhz("D3"), nhz("D6")), -34.0
    )
    sc.add("riser", tr, riser, hall=0.15)
    tm = t0 + 0.5 * span
    j = 0
    while tm + j * s16 < hit - 1e-6:
        t = tm + j * s16
        v = (t - tm) / (hit - tm)
        sc.add("tick", t, tick(humanize(rng, 0.3 + 0.7 * v**1.4, 0.05), f"{sid}.tick.{j}"),
               pan=0.3 if j % 2 else -0.3, room=0.12)  # fmt: skip
        j += 1
    stab_hit(sc, hit, CYCLE[0], f"{sid}.hit")


def arrange_drop(sc: Score, sec: dict[str, Any], g: Grid, ir_hall: Arr) -> None:
    """A reverse swell into the drop, impact plus the full groove, a stab and the motif on each accent, the build,
    and one hit on the tonic that dies fast."""
    sid = str(sec["id"])
    t0 = float(sec["downbeat"])
    rs = float(sec.get("riser_from", t0))
    hit = float(sec["last_hit"])
    tb = float(sec.get("build_from", hit))
    accents = [float(a) for a in sec.get("accents", [])]
    bar = 4.0 * g.beat
    rng = rng_for(f"{sid}.human")

    def chord_at(t: float) -> str:
        return CYCLE[int(math.floor((t - t0) / bar + 1e-6)) % len(CYCLE)]

    if t0 - rs > 0.05:
        sc.add(
            "swell",
            rs,
            reverse_swell(
                chord_hz(chord_at(t0), STAB_NOTES), t0 - rs, f"{sid}.swell", ir_hall
            ),
        )
    sc.add("impact", t0, impact(f"{sid}.impact"), hall=0.3)
    sc.mark("drop", t0)
    groove(sc, t0, tb, g, sid, rng)
    bounds = bar_bounds(t0, tb, bar)
    names = [chord_at(b) for b in bounds[:-1]]
    sc.add("sub", t0, sub_line([nhz(ROOT[c]) for c in names], bounds), duck="sub")
    for i, c in enumerate(names):
        chords = supersaw(
            chord_hz(c, VOICING),
            bounds[i + 1] - bounds[i] + 0.04,
            f"{sid}.chords.{i}",
            3800.0,
        )
        sc.add("chords", bounds[i], chords, duck="chords", room=0.1, hall=0.12)
    for j, ta in enumerate(accents):
        c = chord_at(ta)
        sc.add("stab", ta, stab(c, f"{sid}.stab.{j}", 0.24, 0.6), room=0.15, hall=0.15)
        motif(sc, ta, MOTIF[c], g, f"{sid}.motif.{j}")
        sc.mark("accent", ta)
    if hit - tb > 0.2:
        build(sc, tb, hit, g, chord_at(tb), f"{sid}.build", rng)
    stab_hit(sc, hit, CYCLE[0], f"{sid}.hit")


def arrange_finale(sc: Score, sec: dict[str, Any], g: Grid, ir_hall: Arr) -> None:
    """The second drop, brightest (Bb then C, the chords opened up with an octave layer), then an F major final hit
    with bells, and only the pad and the hall left to fade."""
    sid = str(sec["id"])
    t0 = float(sec["downbeat"])
    rs = float(sec.get("riser_from", t0))
    tf = float(sec["final_hit"])
    end = float(sec["fade_to_zero_by"])
    q = g.beat
    rng = rng_for(f"{sid}.human")
    bounds = [t0, t0 + q * max(1, round((tf - t0) / (2.0 * q))), tf]
    if t0 - rs > 0.05:
        swell = reverse_swell(
            chord_hz(FINALE_CHORDS[0], STAB_NOTES), t0 - rs, f"{sid}.swell", ir_hall
        )
        sc.add("swell", rs, swell)
    sc.add("impact", t0, impact(f"{sid}.impact"), hall=0.3)
    sc.mark("drop", t0)
    groove(sc, t0, tf, g, sid, rng)
    sc.add(
        "sub", t0, sub_line([nhz(ROOT[c]) for c in FINALE_CHORDS], bounds), duck="sub"
    )
    for i, c in enumerate(FINALE_CHORDS):
        dur = bounds[i + 1] - bounds[i] + 0.04
        sc.add("chords", bounds[i], supersaw(chord_hz(c, VOICING), dur, f"{sid}.chords.{i}", 6000.0), duck="chords",
               room=0.1, hall=0.15)  # fmt: skip
        octave = supersaw(
            [2.0 * f for f in chord_hz(c, VOICING)[-3:]],
            dur,
            f"{sid}.octave.{i}",
            7000.0,
        )
        sc.add(
            "chords",
            bounds[i],
            octave,
            gain_db=-7.0,
            duck="chords",
            room=0.1,
            hall=0.15,
        )
        sc.add(
            "stab",
            bounds[i],
            stab(c, f"{sid}.stab.{i}", 0.26, 0.6, bright=1.2),
            room=0.15,
            hall=0.18,
        )
        motif(sc, bounds[i], FINALE_MOTIF[c], g, f"{sid}.motif.{i}")
    sc.add("kick", tf, kick(1.0, f"{sid}.final.kick"))
    sc.kick_at("main", tf)
    sc.add("impact", tf, impact(f"{sid}.final.impact", length=1.6, tau=0.45), hall=0.4)
    sc.add(
        "stab",
        tf,
        stab("F", f"{sid}.final.stab", 0.45, 1.4, bright=1.1),
        room=0.1,
        hall=0.35,
    )
    for i, name in enumerate(BELLS):
        sc.add("bell", tf + 0.012 * i, bell(name, 0.9 - 0.1 * i, 1.1, f"{sid}.bell.{i}"), pan=(-0.3, 0.0, 0.3)[i],
               hall=0.4)  # fmt: skip
    n = int(round((end - tf) * FS))
    u = np.arange(n) / max(1, n - 1)
    pad = supersaw([nhz(x) for x in FINAL_PAD], end - tf, f"{sid}.pad", 3200.0 * (900.0 / 3200.0) ** u, detune=10.0,
                   spread=PAD_SPREAD, pans=PAD_PAN, attack=0.03, release=0.05)  # fmt: skip
    sc.add("pad", tf, pad, hall=0.35)
    sc.add("sub", tf, sub_note(nhz(ROOT["F"]), end - tf, 0.55, punch=0.2))
    sc.mark("final", tf)


# ---------------------------------------------------------------------------------------------
# Sections, segments, envelopes, reverb


@dataclass(frozen=True)
class Section:
    sid: str
    role: str  # tease, drop or finale
    start: float  # first sound: riser_from or downbeat, or an earlier effect in the same gap
    hit: float  # the last hit
    end: float  # silent_by / fade_to_zero_by, or an earlier silence window start
    fade_from: float  # where the tail shaping begins
    power: float  # the tail's curve (1 = straight in dB)


@dataclass(frozen=True)
class Segment:
    key: str
    kind: str  # tease, drop or build
    t0: float
    t1: float
    mid: float  # centre of the 3 s loudness window
    target: float


def role_of(s: dict[str, Any]) -> str:
    if "final_hit" in s or "fade_to_zero_by" in s:
        return "finale"
    if "riser_from" in s or "accents" in s or "build_from" in s:
        return "drop"
    return "tease"


def sections_from(tl: dict[str, Any]) -> list[Section]:
    duration = float(tl["duration"])
    windows = [(float(a), float(b)) for a, b in tl["silence_windows"]]
    fx_times = [float(s["t"]) for s in tl["sfx"]]
    out: list[Section] = []
    for s in tl["music_sections"]:
        start = float(s.get("riser_from", s["downbeat"]))
        hit = float(s["final_hit"] if "final_hit" in s else s["last_hit"])
        end = min(
            duration,
            float(s["fade_to_zero_by"] if "fade_to_zero_by" in s else s["silent_by"]),
        )
        for ws, _ in windows:
            if start < ws < end:
                end = ws
        gap_start = max([we for _, we in windows if we <= start], default=0.0)
        start = min([start, *[t for t in fx_times if gap_start <= t < start]])
        role = role_of(s)
        if role == "finale":
            fade_from, power = min(hit + 0.3, end - CHECK_S - 0.3), 1.0
        else:
            fade_from, power = (
                min(hit + max(0.1, 0.3 * (end - hit)), end - CHECK_S - 0.1),
                1.5,
            )
        out.append(Section(str(s["id"]), role, start, hit, end, fade_from, power))
    return out


def segments_from(tl: dict[str, Any], secs: list[Section]) -> list[Segment]:
    by_id = {str(s["id"]): s for s in tl["music_sections"]}
    out: list[Segment] = []
    for sec in secs:
        s = by_id[sec.sid]
        if sec.role == "tease":
            out.append(
                Segment(
                    sec.sid,
                    "tease",
                    sec.start,
                    sec.end,
                    0.5 * (sec.start + sec.end),
                    TARGET_LUFS["tease"],
                )
            )
            continue
        t0 = float(s["downbeat"])
        if "build_from" in s:
            tb = float(s["build_from"])
            out.append(
                Segment(
                    f"{sec.sid}:drop",
                    "drop",
                    sec.start,
                    tb,
                    0.5 * (t0 + tb),
                    TARGET_LUFS["drop"],
                )
            )
            out.append(
                Segment(
                    f"{sec.sid}:build",
                    "build",
                    tb,
                    sec.end,
                    0.5 * (tb + sec.hit),
                    TARGET_LUFS["build"],
                )
            )
        else:
            out.append(
                Segment(
                    f"{sec.sid}:drop",
                    "drop",
                    sec.start,
                    sec.end,
                    0.5 * (t0 + sec.hit),
                    TARGET_LUFS["drop"],
                )
            )
    return out


def segment_for(t: float, segs: list[Segment]) -> Segment:
    for s in segs:
        if s.t0 - 1e-9 <= t < s.t1:
            return s
    later = [s for s in segs if s.t0 >= t]
    return later[0] if later else segs[-1]


def automation(
    n: int, segs: list[Segment], gains: dict[str, float], ramp: float = 0.04
) -> Arr:
    """Each segment's gain; where two segments meet, a raised-cosine ramp that ends at the boundary."""
    g = np.ones(n)
    for s in segs:
        g[max(0, int(round(s.t0 * FS))) : min(n, int(round(s.t1 * FS)))] = db(
            gains[s.key]
        )
    nr = int(ramp * FS)
    for s0, s1 in zip(segs, segs[1:]):
        if abs(s0.t1 - s1.t0) < 1e-6:
            b = int(round(s1.t0 * FS))
            g0, g1 = db(gains[s0.key]), db(gains[s1.key])
            g[b - nr : b] = g0 + (g1 - g0) * rise(nr)
    return g


def ending_envelope(n: int, secs: list[Section], depths: Sequence[float]) -> Arr:
    """1 through each section; from fade_from a decay reaching -depth dB at end - 50 ms; a 30 ms raised cosine to
    an exact zero at end; 0 between sections."""
    env = np.zeros(n)
    nf = int(round(FADE_S * FS))
    for s, depth in zip(secs, depths):
        i0 = max(0, int(round(s.start * FS)))
        i1 = min(n, int(round(s.end * FS)))
        t = np.arange(i0, i1) / FS
        u = np.clip((t - s.fade_from) / ((s.end - CHECK_S) - s.fade_from), 0.0, None)
        level = np.where(
            u <= 1.0, -depth * u**s.power, -depth - s.power * depth * (u - 1.0)
        )
        seg = 10.0 ** (level / 20.0)
        k = min(nf, len(seg))
        seg[len(seg) - k :] *= fall(k)
        env[i0:i1] = seg
    return env


def silence_gate(n: int, windows: list[tuple[float, float]], final_end: float) -> Arr:
    """Exact zeros inside every window (inclusive), after a 30 ms raised cosine that ends at its start."""
    g = np.ones(n)
    nf = int(round(FADE_S * FS))
    for ws, we in [*windows, (final_end, n / FS)]:
        a = min(n - 1, int(round(ws * FS)))
        b = min(n, int(round(we * FS)) + 1)
        lo = max(0, a - nf)
        g[lo:a] *= fall(a - lo)
        g[a:b] = 0.0
    return g


def reverb_ir(key: str, length: float, predelay: float, rt_scale: float) -> Arr:
    """Synthetic stereo space: decorrelated noise, highs dying first; rt_scale 1 is an RT60 of about 1.8 s."""
    n = int(length * FS)
    t = np.arange(n) / FS
    bands: tuple[tuple[str, float, float, float], ...] = (
        ("lowpass", 250.0, 0.0, 1.6),
        ("bandpass", 250.0, 1000.0, 1.8),
        ("bandpass", 1000.0, 3000.0, 1.7),
        ("bandpass", 3000.0, 7000.0, 1.2),
        ("highpass", 7000.0, 0.0, 0.7),
    )
    ir = np.zeros((2, n))
    nd = int(predelay * FS)
    for c in range(2):
        src = noise(n, f"{key}.{c}")
        acc = np.zeros(n)
        for kind, f1, f2, rt60 in bands:
            sos = butter_sos(4, (f1, f2) if kind == "bandpass" else f1, kind)
            acc += sosf(sos, src) * np.exp(-6.9078 * t / (rt60 * rt_scale))
        acc = shape_ends(acc, 0.004, 0.05)
        acc = sosf(
            butter_sos(2, 9000.0, "lowpass"),
            sosf(butter_sos(2, 160.0, "highpass"), acc),
        )
        ir[c, nd:] = acc[: n - nd]
    # Unity power gain over 300 Hz - 3 kHz: a send of s puts the space about 20 log10(s) dB under the dry sound.
    spec = np.abs(np.fft.rfft(ir, axis=-1)) ** 2
    f = np.fft.rfftfreq(n, 1.0 / FS)
    out: Arr = ir / math.sqrt(float(np.mean(spec[:, (f >= 300.0) & (f <= 3000.0)])))
    return out


def convolve(send: Arr, ir: Arr) -> Arr:
    n = send.shape[1]
    if not np.any(send):
        return np.zeros_like(send)
    left = signal.fftconvolve(0.7 * send[0] + 0.3 * send[1], ir[0])[:n]
    right = signal.fftconvolve(0.3 * send[0] + 0.7 * send[1], ir[1])[:n]
    return np.vstack((left, right))


def pingpong(
    send: Arr, delay_s: float, feedback: float = 0.38, repeats: int = 4
) -> Arr:
    """Dotted-8th ping-pong echo: right first, each repeat darker."""
    n = send.shape[1]
    d = int(round(delay_s * FS))
    x = sosf(butter_sos(2, (350.0, 6000.0), "bandpass"), 0.5 * (send[0] + send[1]))
    out = np.zeros((2, n))
    for k in range(1, repeats + 1):
        if k * d >= n:
            break
        x = lowpass1(x, 5000.0)
        out[k % 2, k * d :] += feedback ** (k - 1) * x[: n - k * d]
    return out


# ---------------------------------------------------------------------------------------------
# Loudness and measurement


def cum_power(x: Arr) -> Arr:
    """Cumulative K-weighted power, summed over channels (BS.1770, G = 1 for L and R)."""
    y = signal.lfilter(K2_B, K2_A, signal.lfilter(K1_B, K1_A, x, axis=-1), axis=-1)
    p = np.sum(y * y, axis=0)
    out: Arr = np.concatenate(([0.0], np.cumsum(p)))
    return out


def loud(c: Arr, t0: float, t1: float) -> float:
    a = max(0, int(round(t0 * FS)))
    b = min(len(c) - 1, int(round(t1 * FS)))
    if b <= a:
        return -120.0
    ms = (c[b] - c[a]) / (b - a)
    return -0.691 + 10.0 * math.log10(ms) if ms > 1e-14 else -120.0


def momentary(
    c: Arr, t0: float, t1: float, win: float = 0.4, hop: float = 0.01
) -> tuple[float, float]:
    """(max momentary loudness, time of its window end) over windows ending in [t0 + win, t1]."""
    w = int(win * FS)
    ends = np.arange(
        max(w, int(round((t0 + win) * FS))),
        min(len(c) - 1, int(round(t1 * FS))) + 1,
        int(hop * FS),
    )
    if len(ends) == 0:
        return -120.0, t0
    ms = (c[ends] - c[ends - w]) / w
    i = int(np.argmax(ms))
    return (
        -0.691 + 10.0 * math.log10(float(ms[i])) if ms[i] > 1e-14 else -120.0
    ), float(ends[i] / FS)


def integrated(c: Arr) -> float:
    """BS.1770-4 gated integrated loudness (a self-check against ffmpeg)."""
    blk, hop = int(0.4 * FS), int(0.1 * FS)
    starts = np.arange(0, len(c) - 1 - blk + 1, hop)
    ms = (c[starts + blk] - c[starts]) / blk
    lk = -0.691 + 10.0 * np.log10(np.maximum(ms, 1e-20))
    g1 = ms[lk > -70.0]
    if len(g1) == 0:
        return -120.0
    rel = -0.691 + 10.0 * math.log10(float(np.mean(g1))) - 10.0
    g2 = ms[(lk > -70.0) & (lk > rel)]
    return -0.691 + 10.0 * math.log10(float(np.mean(g2)))


def true_peak_dbfs(x: Arr) -> float:
    pk = float(np.max(np.abs(signal.resample_poly(x, 4, 1, axis=-1))))
    return 20.0 * math.log10(pk) if pk > 0.0 else -200.0


def rms_dbfs(x: Arr, t0: float, t1: float) -> float:
    """Plain RMS (20 log10 rms; a full-scale sine reads -3 dBFS) over both channels."""
    a = max(0, int(round(t0 * FS)))
    b = min(x.shape[1], int(round(t1 * FS)))
    if b <= a:
        return -200.0
    ms = float(np.mean(x[:, a:b] ** 2))
    return 10.0 * math.log10(ms) if ms > 1e-20 else -200.0


def rms_envelope(x: Arr, win: float = 0.002) -> Arr:
    p = np.mean(x * x, axis=0) if x.ndim == 2 else x * x
    w = max(1, int(win * FS))
    out: Arr = np.sqrt(np.convolve(p, np.ones(w) / w, mode="same"))
    return out


def onset_ms(
    x: Arr, t_from: float, target: float, search: float = 0.35, rel_db: float = -20.0
) -> float:
    """First time the 2 ms RMS envelope comes within rel_db of the event's peak, minus target (ms)."""
    a = max(0, int(round(t_from * FS)))
    b = min(x.shape[-1], a + int(search * FS))
    env = rms_envelope(x[..., a:b])
    pk = float(np.max(env))
    if pk <= 0.0:
        return float("nan")
    i = int(np.argmax(env >= pk * db(rel_db)))
    return ((a + i) / FS - target) * 1000.0


def end_ms(x: Arr, until: float, rel_db: float = -30.0) -> float:
    """Last time the 2 ms RMS envelope is within rel_db of its peak, minus `until` (x starts at 0), in ms."""
    env = rms_envelope(x)
    idx = np.nonzero(env >= float(np.max(env)) * db(rel_db))[0]
    return (float(idx[-1]) / FS - until) * 1000.0


def flux_onset_ms(x: Arr, target: float, span: float = 0.06) -> float:
    """Time of the steepest 5 ms-frame energy rise above 300 Hz within +-span of target, minus target (ms). The
    high-pass keeps the sub's phase ripple (+-3 dB in 5 ms frames) from posing as an onset."""
    frame, hop = int(0.005 * FS), int(0.001 * FS)
    a = max(0, int(round((target - span - 0.01) * FS)))
    b = min(x.shape[1], int(round((target + span + 0.01) * FS)))
    a0 = max(0, a - int(0.05 * FS))
    p = np.mean(sosf(butter_sos(2, 300.0, "highpass"), x[:, a0:b])[:, a - a0 :] ** 2, axis=0)
    c = np.concatenate(([0.0], np.cumsum(p)))
    starts = np.arange(frame, len(p) - frame, hop)
    now = (c[starts + frame] - c[starts]) / frame
    before = (c[starts] - c[starts - frame]) / frame
    rise_db = 10.0 * np.log10((now + 1e-20) / (before + 1e-20))
    i = int(np.argmax(rise_db))
    return (float(a + starts[i]) / FS - target) * 1000.0


def band_balance(x: Arr) -> list[float]:
    """Welch PSD of a mono signal; each band's power in dB of the 40 Hz - 20 kHz total."""
    f, p = signal.welch(x, fs=FS, nperseg=8192)
    total = float(np.sum(p[(f >= 40.0) & (f < 20000.0)]))
    return [
        10.0 * math.log10(float(np.sum(p[(f >= lo) & (f < hi)])) / total)
        for lo, hi in BANDS_HZ
    ]


def reference_bands() -> tuple[list[str], list[list[float]]]:
    """Band balance of 10-40 s of each reference track, decoded to 48 kHz mono with ffmpeg."""
    exe = shutil.which("ffmpeg")
    paths = sorted(Path(REFERENCE_GLOB).parent.glob(Path(REFERENCE_GLOB).name))
    names: list[str] = []
    rows: list[list[float]] = []
    if exe is None:
        return names, rows
    for p in paths:
        cmd = [exe, "-hide_banner", "-loglevel", "error", "-ss", "10", "-t", "30", "-i", str(p), "-ac", "1", "-ar",
               str(FS), "-f", "f32le", "-"]  # fmt: skip
        raw = subprocess.run(cmd, capture_output=True, check=False).stdout
        x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
        if len(x) > FS:
            names.append(p.name)
            rows.append(band_balance(x))
    return names, rows


def harmonics_db(x: Arr, f0: float, count: int = 4) -> list[float]:
    """Level of harmonics 2..count against the fundamental (dB), from a Hann-windowed spectrum."""
    mono = np.mean(x, axis=0) if x.ndim == 2 else x
    spec = np.abs(np.fft.rfft(mono * np.hanning(len(mono))))
    f = np.fft.rfftfreq(len(mono), 1.0 / FS)

    def level(fk: float) -> float:
        return float(np.max(spec[(f > fk - 3.0) & (f < fk + 3.0)]))

    h1 = level(f0)
    return [20.0 * math.log10(level(k * f0) / h1) for k in range(2, count + 1)]


# ---------------------------------------------------------------------------------------------
# Master


def compressor_gain(x: Arr, thr_db: float = -18.0, ratio: float = 2.0, knee: float = 6.0, attack: float = 0.025,
                    release: float = 0.2, rms: float = 0.030, hop: int = 16) -> Arr:  # fmt: skip
    """Stereo-linked 2:1 soft-knee glue compressor on a 30 ms RMS detector; returns the gain curve."""
    p = np.mean(x * x, axis=0)
    c = np.concatenate(([0.0], np.cumsum(p)))
    idx = np.arange(0, len(p), hop)
    lo = np.maximum(0, idx + 1 - int(rms * FS))
    level = 10.0 * np.log10(np.maximum((c[idx + 1] - c[lo]) / (idx + 1 - lo), 1e-20))
    over = level - thr_db
    slope = 1.0 - 1.0 / ratio
    gr = np.where(over <= -knee / 2.0, 0.0,
                  np.where(over >= knee / 2.0, slope * over, slope * (over + knee / 2.0) ** 2 / (2.0 * knee)))  # fmt: skip
    a_att, a_rel = math.exp(-hop / (attack * FS)), math.exp(-hop / (release * FS))
    smooth = np.empty_like(gr)
    s = 0.0
    for i, v in enumerate(gr.tolist()):
        coef = a_att if v > s else a_rel
        s = coef * s + (1.0 - coef) * v
        smooth[i] = s
    out: Arr = 10.0 ** (-np.interp(np.arange(len(p)), idx, smooth) / 20.0)
    return out


def saturate(x: Arr, drive: float = 0.9) -> Arr:
    """Gentle tanh saturation at 2x oversampling: unity for small signals, about -0.6 dB at -6 dBFS."""
    up = signal.resample_poly(x, 2, 1, axis=-1)
    out: Arr = signal.resample_poly(np.tanh(drive * up) / drive, 1, 2, axis=-1)[
        :, : x.shape[1]
    ]
    return out


def window_min(x: Arr, w: int) -> Arr:
    """out[i] = min(x[i : i + w]), x continued with its last value (a sparse table, O(n log w))."""
    n = len(x)
    cur = np.concatenate((x, np.full(w, x[-1])))
    span = 1
    while span * 2 <= w:
        cur = np.minimum(cur[:-span], cur[span:])
        span *= 2
    out: Arr = np.minimum(cur[:n], cur[w - span : w - span + n])
    return out


def limiter_gain(
    x: Arr, ceiling_dbtp: float, look: float = 0.002, release: float = 0.06
) -> Arr:
    """Look-ahead true-peak limiter gain: the need per sample from 4x-oversampled peaks, a forward minimum over the
    look-ahead, a box-filtered attack that lands exactly on the peak, and an exponential release in dB."""
    n = x.shape[1]
    up = signal.resample_poly(x, 4, 1, axis=-1)
    pk = np.max(np.abs(up[:, : 4 * n]), axis=0).reshape(n, 4).max(axis=1)
    pk = np.maximum(pk, np.max(np.abs(x), axis=0))
    need = np.minimum(1.0, db(ceiling_dbtp) / np.maximum(pk, 1e-12))
    w = max(1, int(round(look * FS)))
    h = window_min(need, w + 1)
    c = np.concatenate(([0.0], np.cumsum(np.concatenate((np.ones(w), h)))))
    s = (c[w + 1 :] - c[:n]) / (w + 1)
    gr = -20.0 * np.log10(np.minimum(s, 1.0))
    k = np.arange(n) / (release * FS)
    held = np.exp(np.maximum.accumulate(np.log(gr + 1e-9) + k) - k) - 1e-9
    out: Arr = 10.0 ** (-np.maximum(held, gr) / 20.0)
    return out


@dataclass
class Master:
    out: Arr  # after the limiter, before the gate
    comp: Arr  # compressor gain
    lim: Arr  # limiter gain
    music: Arr  # the music through the same filters and gains (no saturation)
    sfx: Arr  # the effects likewise


def run_master(music: Arr, sfx: Arr) -> Master:
    """High-pass 25 Hz, low-pass 19 kHz, 2:1 glue compression, gentle saturation, true-peak limiter."""
    hp, lp = butter_sos(2, 25.0, "highpass"), butter_sos(2, 19000.0, "lowpass")
    m = sosf(lp, sosf(hp, music))
    f = sosf(lp, sosf(hp, sfx))
    cg = compressor_gain(m + f)
    y = saturate((m + f) * cg)
    ceiling = PEAK_CEILING_DBTP
    lg = limiter_gain(y, ceiling)
    for _ in range(4):
        over = true_peak_dbfs(y * lg) - PEAK_CEILING_DBTP
        if over <= 0.0:
            break
        ceiling -= over + 0.02
        lg = limiter_gain(y, ceiling)
    return Master(y * lg, cg, lg, m * cg * lg, f * cg * lg)


# ---------------------------------------------------------------------------------------------
# Effects placement


@dataclass
class Fx:
    typ: str
    t: float
    until: float
    wet: Arr  # the effect with its own room and hall, at unit gain, starting at t
    own_db: float  # momentary max of `wet`
    seg: Segment
    under: float  # target level under the segment's music (dB)
    gain_db: float
    onset_ms: float
    end_ms: float | None
    known: bool


def prepare_fx(
    entries: list[dict[str, Any]], segs: list[Segment], ir_room: Arr, ir_hall: Arr
) -> list[Fx]:
    out: list[Fx] = []
    for i, entry in enumerate(entries):
        typ, t = str(entry["type"]), float(entry["t"])
        x = render_effect(entry, i)
        padded = np.zeros((2, x.shape[1] + ir_hall.shape[1]))
        padded[:, : x.shape[1]] = x
        wet = padded.copy()
        if SFX_ROOM.get(typ, 0.15) > 0.0:
            wet += SFX_ROOM.get(typ, 0.15) * convolve(padded, ir_room)
        if SFX_HALL.get(typ, 0.1) > 0.0:
            wet += SFX_HALL.get(typ, 0.1) * convolve(padded, ir_hall)
        own = momentary(cum_power(wet), 0.0, wet.shape[1] / FS)[0]
        seg = segment_for(t, segs)
        under = SFX_UNDER_DB.get(typ, -12.0)
        until = float(entry["until"]) if "until" in entry else t + x.shape[1] / FS
        onset = (
            onset_ms(x, 0.0, 0.0, search=x.shape[1] / FS)
            + (round(t * FS) / FS - t) * 1000.0
        )
        ends = end_ms(x, until - t) if "until" in entry else None
        out.append(
            Fx(
                typ,
                t,
                until,
                wet,
                own,
                seg,
                under,
                seg.target + under - own,
                onset,
                ends,
                typ in SFX_UNDER_DB,
            )
        )
    return out


def fx_sum(n: int, fxs: list[Fx]) -> Arr:
    buf = np.zeros((2, n))
    for fx in fxs:
        place(buf, fx.t, fx.wet, db(fx.gain_db))
    return buf


# ---------------------------------------------------------------------------------------------
# I/O


def ffmpeg_ebur128(path: Path) -> dict[str, float] | None:
    exe = shutil.which("ffmpeg")
    if exe is None:
        return None
    cmd = [
        exe,
        "-hide_banner",
        "-nostats",
        "-i",
        str(path),
        "-af",
        "ebur128=peak=true",
        "-f",
        "null",
        "-",
    ]
    text = subprocess.run(cmd, capture_output=True, text=True, check=False).stderr
    summary = text[text.rfind("Summary:") :]
    found = {
        "integrated_lufs": re.search(r"I:\s+(-?[\d.]+|-inf) LUFS", summary),
        "lra_lu": re.search(r"LRA:\s+(-?[\d.]+) LU", summary),
        "true_peak_dbtp": re.search(
            r"True peak:\s+Peak:\s+(-?[\d.]+|-inf) dBFS", summary
        ),
    }
    return {k: float(m.group(1)) for k, m in found.items() if m is not None}


def lint(script: Path) -> dict[str, str]:
    cache = Path(tempfile.gettempdir()) / "soundtrack2-mypy-cache"
    commands = {
        "ruff": [sys.executable, "-m", "ruff", "check", "--no-cache", str(script)],
        "mypy": [
            sys.executable,
            "-m",
            "mypy",
            "--strict",
            "--cache-dir",
            str(cache),
            str(script),
        ],
    }
    result: dict[str, str] = {}
    for name, cmd in commands.items():
        try:
            r = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                cwd=script.parent,
                timeout=600,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            result[name] = f"not run: {exc}"
            continue
        out = (r.stdout + r.stderr).strip()
        if "No module named" in out:
            result[name] = "not run: not installed for this Python"
        else:
            result[name] = "clean" if r.returncode == 0 else out[-1500:]
    return result


def write_wav(path: Path, x: Arr) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wavfile.write(str(path), FS, np.ascontiguousarray(x.T.astype(np.float32)))


def wav_info(path: Path) -> dict[str, Any]:
    rate, data = wavfile.read(str(path))
    return {
        "samples": int(data.shape[0]),
        "seconds": round(int(data.shape[0]) / int(rate), 6),
        "rate": int(rate),
        "channels": int(data.shape[1]) if data.ndim == 2 else 1,
        "dtype": str(data.dtype),
    }


def load_voice(path: Path) -> Arr:
    """A helper clip as returned: int16 or float, mono, upsampled to 48 kHz with a unity-gain polyphase filter."""
    rate, data = wavfile.read(str(path))
    x = np.asarray(data, dtype=np.float64)
    if data.dtype == np.int16:
        x /= 32768.0
    elif data.dtype == np.int32:
        x /= 2147483648.0
    if x.ndim == 2:
        x = x.mean(axis=1)
    if int(rate) != FS:
        g = math.gcd(int(rate), FS)
        x = np.asarray(
            signal.resample_poly(x, FS // g, int(rate) // g), dtype=np.float64
        )
    return x


def r2(x: float) -> float:
    return round(float(x), 2)


# ---------------------------------------------------------------------------------------------
# Main


def render(timeline_path: Path, out_dir: Path) -> dict[str, Any]:
    tl: dict[str, Any] = json.loads(timeline_path.read_text())
    work_dir = timeline_path.parent
    duration = float(tl["duration"])
    n = int(round(duration * FS))
    bpm = float(tl["bpm"])
    windows = [(float(a), float(b)) for a, b in tl["silence_windows"]]
    secs = sections_from(tl)
    segs = segments_from(tl, secs)
    by_id = {str(s["id"]): s for s in tl["music_sections"]}
    ir_room = reverb_ir("room", 1.2, 0.008, 0.35)
    ir_hall = reverb_ir("hall", 3.0, 0.022, 1.15)

    # 1. Score: every section on its own bar grid, starting at its downbeat.
    sc = Score()
    grids: dict[str, Grid] = {}
    for sec in secs:
        s = by_id[sec.sid]
        g = fit_grid(float(s["downbeat"]), sec.hit, bpm)
        grids[sec.sid] = g
        if sec.role == "tease":
            arrange_tease(sc, s, g)
        elif sec.role == "drop":
            arrange_drop(sc, s, g, ir_hall)
        else:
            arrange_finale(sc, s, g, ir_hall)

    # 2. Mixdown and the shared spaces. Each send closes along its section's tail, reaching -60 dB 50 ms before
    #    the window, so nothing still feeds a room when the voice comes in.
    groups, sends = mixdown(sc, n)
    send_env = ending_envelope(n, secs, [60.0] * len(secs))
    wet = {
        "room": convolve(sends["room"] * send_env, ir_room),
        "hall": convolve(sends["hall"] * send_env, ir_hall),
        "delay": pingpong(sends["delay"] * send_env, 0.75 * 60.0 / bpm),
    }
    music_raw = np.sum(list(groups.values()), axis=0) + np.sum(
        list(wet.values()), axis=0
    )

    # 3. Effects, each set to its level under the music around it.
    fxs = prepare_fx(list(tl["sfx"]), segs, ir_room, ir_hall)

    # 4. Solve: segment gains to their loudness targets through the master, effect gains to their levels under the
    #    music, tail depths until every tail is below the target 50 ms before its window.
    c_raw = cum_power(music_raw)
    gains = {s.key: s.target - loud(c_raw, s.mid - 1.5, s.mid + 1.5) for s in segs}
    slopes = {s.key: 0.8 for s in segs}
    last: dict[str, tuple[float, float]] = {}
    depths = [40.0] * len(secs)
    iterations = 0
    for iterations in range(1, 16):
        env = ending_envelope(n, secs, depths)
        ms = run_master(
            music_raw * automation(n, segs, gains) * env, fx_sum(n, fxs) * env
        )
        c_out = cum_power(ms.out)
        c_music = cum_power(ms.music)
        errs = {s.key: s.target - loud(c_out, s.mid - 1.5, s.mid + 1.5) for s in segs}
        tails = [
            rms_dbfs(ms.out, s.end - CHECK_S - 0.02, s.end - CHECK_S) for s in secs
        ]
        chain = ms.comp * ms.lim * env
        fx_err: list[float] = []
        for fx in fxs:
            a, b = (
                int(round(fx.t * FS)),
                max(
                    int(round(fx.t * FS)) + 1,
                    int(round(min(fx.until, fx.t + 0.3) * FS)),
                ),
            )
            level = (
                fx.own_db
                + fx.gain_db
                + 20.0 * math.log10(max(1e-9, float(np.mean(chain[a:b]))))
            )
            fx_err.append(
                fx.under - (level - loud(c_music, fx.seg.mid - 1.5, fx.seg.mid + 1.5))
            )
        if (
            all(abs(e) <= 0.1 for e in errs.values())
            and all(tl_ <= TAIL_TARGET_DBFS for tl_ in tails)
            and all(abs(e) <= 0.3 for e in fx_err)
        ):
            break
        for s in segs:
            measured = s.target - errs[s.key]
            if s.key in last and abs(gains[s.key] - last[s.key][0]) > 0.05:
                slopes[s.key] = float(
                    np.clip(
                        (measured - last[s.key][1]) / (gains[s.key] - last[s.key][0]),
                        0.3,
                        1.5,
                    )
                )
            last[s.key] = (gains[s.key], measured)
            gains[s.key] += float(np.clip(errs[s.key] / slopes[s.key], -6.0, 6.0))
        depths = [
            d + (tl_ - TAIL_TARGET_DBFS + 2.0 if tl_ > TAIL_TARGET_DBFS else 0.0)
            for d, tl_ in zip(depths, tails)
        ]
        for fx, e in zip(fxs, fx_err):
            fx.gain_db += e

    gate = silence_gate(n, windows, secs[-1].end)
    out = ms.out * gate
    music_st, sfx_st = ms.music * gate, ms.sfx * gate
    write_wav(out_dir / "music_sfx.wav", out)
    write_wav(out_dir / "stems" / "music.wav", music_st)
    write_wav(out_dir / "stems" / "sfx.wav", sfx_st)

    # 5. Preview: the voices on top, mono to both channels unchanged (upsampled to 48 kHz only), no gain.
    preview = out.copy()
    for v in tl["voices"]:
        voice = load_voice(work_dir / str(v["file"]))
        place(preview, float(v["start"]), np.vstack((voice, voice)), 1.0)
    write_wav(out_dir / "preview_mix.wav", preview)

    # 6. Verify.
    c_out = cum_power(out)
    c_music = cum_power(music_st)
    mom, mom_t = momentary(c_out, 0.0, duration)
    residual = out - music_st - sfx_st
    report: dict[str, Any] = {
        "timeline": str(timeline_path),
        "files": {
            name: wav_info(out_dir / name)
            for name in (
                "music_sfx.wav",
                "stems/music.wav",
                "stems/sfx.wav",
                "preview_mix.wav",
            )
        },
        "expected_samples": n,
        "ffmpeg_ebur128": {
            "music_sfx": ffmpeg_ebur128(out_dir / "music_sfx.wav"),
            "preview_mix": ffmpeg_ebur128(out_dir / "preview_mix.wav"),
        },
        "self_check": {
            "integrated_lufs": r2(integrated(c_out)),
            "true_peak_4x_dbfs": r2(true_peak_dbfs(out)),
            "sample_peak_dbfs": r2(20.0 * math.log10(float(np.max(np.abs(out))))),
            "dc_offset": [float(f"{float(np.mean(out[ch])):.3g}") for ch in range(2)],
            "momentary_max_lufs": r2(mom),
            "momentary_max_at": r2(mom_t),
            "preview_integrated_lufs": r2(integrated(cum_power(preview))),
            "preview_sample_peak_dbfs": r2(
                20.0 * math.log10(float(np.max(np.abs(preview))))
            ),
            "max_glue_compression_db": r2(-20.0 * math.log10(float(np.min(ms.comp)))),
            "max_limiting_db": r2(-20.0 * math.log10(float(np.min(ms.lim)))),
            "stems_sum_vs_master_residual_db": r2(
                rms_dbfs(residual, 0.0, duration) - rms_dbfs(out, 0.0, duration)
            ),
            "solve_iterations": iterations,
        },
        "segments": [],
        "silence_windows": [],
        "sections": [],
        "onsets": {"drops": [], "accents": [], "hits": [], "sfx": []},
        "band_balance": {},
        "sub_harmonics_db": {},
        "group_balance_lu": {},
        "lint": lint(Path(__file__).resolve()),
    }
    for s in segs:
        report["segments"].append({
            "segment": s.key,
            "kind": s.kind,
            "short_term_window": [r2(s.mid - 1.5), r2(s.mid + 1.5)],
            "target_lufs": s.target,
            "short_term_lufs_mix": r2(loud(c_out, s.mid - 1.5, s.mid + 1.5)),
            "short_term_lufs_music": r2(loud(c_music, s.mid - 1.5, s.mid + 1.5)),
            "gain_db": r2(gains[s.key]),
            "glue_gr_mean_db": r2(-20.0 * math.log10(float(np.mean(ms.comp[int(round((s.mid - 1.5) * FS)) : int(round((s.mid + 1.5) * FS))])))),
            "glue_gr_max_db": r2(-20.0 * math.log10(float(np.min(ms.comp[int(round((s.mid - 1.5) * FS)) : int(round((s.mid + 1.5) * FS))])))),
        })  # fmt: skip
    ends = [(ws, we, "silence_window") for ws, we in windows] + [
        (secs[-1].end, duration, "final_fade")
    ]
    for ws, we, kind in ends:
        a, b = int(round(ws * FS)), min(n, int(round(we * FS)) + 1)
        report["silence_windows"].append({
            "kind": kind,
            "window": [ws, we],
            "max_abs_inside": float(np.max(np.abs(out[:, a:b]))) if b > a else 0.0,
            "rms_50ms_before_dbfs": r2(rms_dbfs(out, ws - CHECK_S, ws)),
            "natural_decay_at_minus50ms_dbfs": r2(rms_dbfs(ms.out, ws - CHECK_S - 0.02, ws - CHECK_S)),
        })  # fmt: skip
    for sec, depth in zip(secs, depths):
        g = grids[sec.sid]
        mm, mm_t = momentary(c_out, sec.start, sec.end)
        report["sections"].append({
            "id": sec.sid,
            "role": sec.role,
            "span": [sec.start, sec.end],
            "tempo_bpm": r2(g.tempo),
            "last_hit_on": g.unit,
            "momentary_max_lufs": r2(mm),
            "momentary_max_at": r2(mm_t),
            "tail_depth_db": r2(depth),
            "tail_shaping_from": r2(sec.fade_from),
        })  # fmt: skip
    for t in sc.marks.get("drop", []):
        placed = [
            ev
            for ev in sc.events
            if ev.group in ("impact", "kick") and abs(ev.t - t) < 1e-9
        ]
        report["onsets"]["drops"].append({
            "target": t,
            "placement_samples": [int(round(ev.t * FS)) - int(round(t * FS)) for ev in placed],
            "downbeat_sample": int(round(t * FS)),
            "impact_layer_onset_ms": r2(onset_ms(groups["impact"], t - 0.02, t, 0.2)),
            "music_stem_energy_rise_ms": r2(flux_onset_ms(music_st, t)),
        })  # fmt: skip
    for kind, group in (("accents", "stab"), ("hits", "stab")):
        for t in sc.marks.get("accent" if kind == "accents" else "hit", []):
            report["onsets"][kind].append({
                "target": t,
                "stab_layer_onset_ms": r2(onset_ms(groups[group], t - 0.02, t, 0.2)),
                "music_stem_energy_rise_ms": r2(flux_onset_ms(music_st, t)),
            })  # fmt: skip
    for fx in fxs:
        a = int(round(fx.t * FS))
        b = max(a + 1, int(round(min(fx.until, fx.t + 0.3) * FS)))
        level = (
            fx.own_db
            + fx.gain_db
            + 20.0
            * math.log10(max(1e-9, float(np.mean((ms.comp * ms.lim * env)[a:b]))))
        )
        report["onsets"]["sfx"].append({
            "type": fx.typ,
            "t": fx.t,
            "onset_offset_ms": r2(fx.onset_ms),
            "end_offset_ms": None if fx.end_ms is None else r2(fx.end_ms),
            "momentary_max_lufs": r2(level),
            "under_music_db": r2(level - loud(c_music, fx.seg.mid - 1.5, fx.seg.mid + 1.5)),
            "segment": fx.seg.key,
            "known_type": fx.known,
        })  # fmt: skip

    # Band balance of the first drop (downbeat to build) against the reference tracks.
    drop_sec = next((by_id[s.sid] for s in secs if s.role == "drop"), None)
    if drop_sec is not None:
        d0 = float(drop_sec["downbeat"])
        d1 = float(drop_sec.get("build_from", drop_sec["last_hit"]))
        mono = np.mean(out[:, int(round(d0 * FS)) : int(round(d1 * FS))], axis=0)
        mine = band_balance(mono)
        names, rows = reference_bands()
        ref = [float(v) for v in np.mean(rows, axis=0)] if rows else []
        report["band_balance"] = {
            "window": [d0, d1],
            "bands_hz": [[lo, hi] for lo, hi in BANDS_HZ],
            "stem_db": [r2(v) for v in mine],
            "reference_mean_db": [r2(v) for v in ref],
            "difference_db": [r2(a - b) for a, b in zip(mine, ref)],
            "rms_gap_db": r2(
                math.sqrt(float(np.mean([(a - b) ** 2 for a, b in zip(mine, ref)])))
            )
            if ref
            else None,
            "reference_tracks": names,
        }
        bar = 4.0 * grids[str(drop_sec["id"])].beat
        sub = groups["sub"][
            :, int(round((d0 + 0.25) * FS)) : int(round((d0 + bar - 0.25) * FS))
        ]
        h = harmonics_db(sub, nhz(ROOT[CYCLE[0]]))
        report["sub_harmonics_db"] = {
            "note": ROOT[CYCLE[0]],
            "h2": r2(h[0]),
            "h3": r2(h[1]),
            "h4": r2(h[2]),
        }
        total = loud(c_raw, 0.5 * (d0 + d1) - 1.5, 0.5 * (d0 + d1) + 1.5)
        report["group_balance_lu"] = {
            name: r2(
                loud(cum_power(x), 0.5 * (d0 + d1) - 1.5, 0.5 * (d0 + d1) + 1.5) - total
            )
            for name, x in sorted(groups.items())
        }
        for bus, x in wet.items():
            report["group_balance_lu"][f"{bus}_return"] = r2(
                loud(cum_power(x), 0.5 * (d0 + d1) - 1.5, 0.5 * (d0 + d1) + 1.5) - total
            )

    violations: list[str] = []
    if n != report["files"]["music_sfx.wav"]["samples"]:
        violations.append("wrong length")
    for w in report["silence_windows"]:
        if w["max_abs_inside"] != 0.0:
            violations.append(f"non-zero inside {w['window']}")
        if (
            w["rms_50ms_before_dbfs"] > TAIL_LIMIT_DBFS
            or w["natural_decay_at_minus50ms_dbfs"] > TAIL_LIMIT_DBFS
        ):
            violations.append(f"tail too loud before {w['window']}")
    tp = (report["ffmpeg_ebur128"]["music_sfx"] or {}).get(
        "true_peak_dbtp", report["self_check"]["true_peak_4x_dbfs"]
    )
    if tp > TRUE_PEAK_LIMIT_DBTP:
        violations.append(f"true peak {tp} dBTP")
    if report["self_check"]["momentary_max_lufs"] > MOMENTARY_MAX_LUFS:
        violations.append(
            f"momentary max {report['self_check']['momentary_max_lufs']} LUFS"
        )
    for sg in report["segments"]:
        if abs(sg["short_term_lufs_mix"] - sg["target_lufs"]) > 1.0:
            violations.append(
                f"{sg['segment']} short-term {sg['short_term_lufs_mix']} LUFS"
            )
    for d_ in report["onsets"]["drops"]:
        if (
            any(p != 0 for p in d_["placement_samples"])
            or abs(d_["impact_layer_onset_ms"]) > 5.0
        ):
            violations.append(f"drop {d_['target']} off its downbeat")
    for a_ in report["onsets"]["accents"]:
        if abs(a_["stab_layer_onset_ms"]) > 5.0:
            violations.append(
                f"accent {a_['target']} onset {a_['stab_layer_onset_ms']} ms"
            )
    for fx_ in report["onsets"]["sfx"]:
        if abs(fx_["onset_offset_ms"]) > 5.0:
            violations.append(
                f"{fx_['type']} at {fx_['t']} onset {fx_['onset_offset_ms']} ms"
            )
        if (
            fx_["type"] == "riser"
            and fx_["end_offset_ms"] is not None
            and abs(fx_["end_offset_ms"]) > 5.0
        ):
            violations.append(
                f"riser at {fx_['t']} ends {fx_['end_offset_ms']} ms off its drop"
            )
        if not SFX_UNDER_RANGE_DB[0] <= fx_["under_music_db"] <= SFX_UNDER_RANGE_DB[1]:
            violations.append(
                f"{fx_['type']} at {fx_['t']} is {fx_['under_music_db']} dB vs music"
            )
        if not fx_["known_type"]:
            violations.append(
                f"unknown effect type {fx_['type']} at {fx_['t']} (rendered as a click)"
            )
    for name, verdict in report["lint"].items():
        if verdict != "clean":
            violations.append(f"{name} not clean")
    report["violations"] = violations
    (out_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: python3 soundtrack2.py ../timeline.json", file=sys.stderr)
        return 2
    out_dir = Path(__file__).resolve().parent
    report = render(Path(argv[1]).resolve(), out_dir)
    ff = report["ffmpeg_ebur128"]["music_sfx"] or {}
    print(
        f"music_sfx: I {ff.get('integrated_lufs')} LUFS, LRA {ff.get('lra_lu')} LU, TP {ff.get('true_peak_dbtp')} dBTP"
    )
    for s in report["segments"]:
        print(
            f"{s['segment']}: short-term {s['short_term_lufs_mix']} LUFS (target {s['target_lufs']})"
        )
    for w in report["silence_windows"]:
        print(
            f"{w['kind']} {w['window']}: max|x| {w['max_abs_inside']}, 50 ms before {w['rms_50ms_before_dbfs']} dBFS"
        )
    bb = report["band_balance"]
    print(
        f"band balance vs references: RMS gap {bb.get('rms_gap_db')} dB, diff {bb.get('difference_db')}"
    )
    print(f"lint: {report['lint']}")
    print("violations:", report["violations"] or "none")
    return 1 if report["violations"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
