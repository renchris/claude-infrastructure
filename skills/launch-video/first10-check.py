#!/usr/bin/env python3
"""launch-video: measure a take or a cut. Audio gate, first 10 seconds, hard cuts, leak sheets.

Run with -I so nothing in the video's folder is imported:

  python3 -I ~/.claude/skills/launch-video/first10-check.py VIDEO --out DIR
          [--audio-only] [--name NAME ...] [--prompt "spellings on screen"]
          [--model PATH] [--asr-json PATH] [--no-asr] [--sheets] [--reuse]

Modes:
  --audio-only   the fast audio gate for a raw take: loudness, true peak, speech level,
                 noise floor (digital-zero bins excluded), their gap, clipped samples.
                 Decodes no video and runs no ASR. Writes DIR/audio-gate.md.
  (default)      everything: probe, cuts, audio, loudness, ASR, the first-10 s sheet.
                 Writes DIR/report.md first, then the images.
  --sheets       also 1 frame/s sheets: faces-NN.jpg (face/screen read) and
                 redact-NN.jpg (leak read, 2 columns so small text stays legible).
  --asr-json     reuse an existing whisper-cli -ojf file instead of transcribing.
  --no-asr       skip speech entirely.
  --reuse        reuse cuts.json and asr.json already in DIR.

What it measures (each report row names its method):
  length, size, fps            ffprobe
  first word, name said by     whisper-cli -ojf token times
  last speech vs length        whisper-cli -ojf (A1's compression trap)
  hard cuts, brief shots       luma difference at fps=30, 96x54 gray, >= 20, local max +-2 frames
  loudness, true peak, LRA     ffmpeg loudnorm print_format=json
  speech, floor, gap, clipping numpy over ffmpeg s16le at 48 kHz, 0.25 s bins
  stereo music or not          side channel RMS against mid

What it leaves to a person (listed unticked in the report): key detail moving by 3 s,
demo start, the turn, face and screen share, the mute, stop and bounce tests.

The comparison column is Farza's range on six videos that did well (METHOD §3.6 step 29,
A1). Those are survivor habits, never thresholds: a difference is marked "differs", never
"fail". It deletes nothing, posts nothing and sends nothing.
"""

import argparse
import json
import os
import re
import subprocess
import sys

import numpy as np

DEFAULT_MODEL = os.path.expanduser(
    "~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/ggml-large-v3-turbo.bin"
)  # found with `mdfind -name ggml-large-v3-turbo.bin` on 2026-10-24; override with --model or WHISPER_MODEL
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
READ_CLAMP = 2000  # Claude Code downscales any image read to 2000 px on its long edge (video-understanding)
CUT_FPS = 30  # resample before diffing so cut times are right on variable-frame-rate screen recordings


def log(msg):
    sys.stderr.write(f"first10-check: {msg}\n")
    sys.stderr.flush()


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def probe(path):
    r = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type,width,height,avg_frame_rate,r_frame_rate:format=duration",
            "-of",
            "json",
            path,
        ],
        text=True,
        check=True,
    )
    d = json.loads(r.stdout)
    out = {"dur": float(d["format"]["duration"]), "video": False, "audio": False}
    for s in d.get("streams", []):
        if s.get("codec_type") == "audio":
            out["audio"] = True
        if s.get("codec_type") == "video" and not out["video"]:
            rate = s.get("avg_frame_rate", "0/0")
            if rate in ("0/0", "0/1"):
                rate = s.get("r_frame_rate", "0/1")
            num, den = rate.split("/")
            out.update(
                video=True,
                w=int(s["width"]),
                h=int(s["height"]),
                fps=float(num) / float(den) if float(den) else 0.0,
            )
    return out


def cuts(path, dur):
    raw = run(
        [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-i",
            path,
            "-vf",
            f"fps={CUT_FPS},scale=96:54,format=gray",
            "-f",
            "rawvideo",
            "-",
        ]
    ).stdout
    a = np.frombuffer(raw, np.uint8).reshape(-1, 54, 96).astype(np.int16)
    d = np.abs(np.diff(a, axis=0)).mean((1, 2))

    def peaks(lo, hi):
        return [
            (i + 1) / CUT_FPS
            for i in range(len(d))
            if lo <= d[i] < hi and d[i] == d[max(0, i - 2) : i + 3].max()
        ]

    hard = peaks(20, 1e9)
    bounds = [0.0] + hard + [dur]
    brief = [  # every shot, the first (0 s to the first cut) and the last (to the end) included
        (round(bounds[i], 2), round(bounds[i + 1] - bounds[i], 2))
        for i in range(len(bounds) - 1)
        if bounds[i + 1] - bounds[i] < 1.0
    ]
    return {"hard": hard, "soft": peaks(10, 20), "brief": brief}


def audio(path):
    raw = run(
        [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-i",
            path,
            "-vn",
            "-ac",
            "2",
            "-ar",
            "48000",
            "-f",
            "s16le",
            "-",
        ]
    ).stdout
    if not raw:
        return None
    i16 = np.frombuffer(raw, np.int16).reshape(-1, 2)
    full = (np.abs(i16.astype(np.int32)) >= 32767).any(axis=1)
    clipped = int(full.sum())
    a = i16.astype(np.float32) / 32768
    mid, side = (a[:, 0] + a[:, 1]) / 2, (a[:, 0] - a[:, 1]) / 2

    def db(x):
        return float(
            20 * np.log10(np.sqrt(np.mean(np.square(x, dtype=np.float64))) + 1e-9)
        )

    k = 12000  # 0.25 s at 48 kHz
    nb = len(mid) // k
    if nb == 0:
        return None
    rms = 20 * np.log10(
        np.sqrt(np.square(mid[: nb * k].reshape(nb, k), dtype=np.float64).mean(1))
        + 1e-9
    )
    live = rms[rms > -150]  # exact digital zero is an edit gap, not room noise
    res = {
        "mid": db(mid),
        "side": db(side),
        "bins": nb,
        "zero_bins": int(nb - len(live)),
        "clipped": clipped,
        # start times of the 0.25 s bins holding a full-scale sample, so each can be checked against the words
        "clip_s": (
            np.flatnonzero(full[: nb * k].reshape(nb, k).any(axis=1)) * 0.25
        ).tolist(),
    }
    if len(live):
        res["speech"] = float(np.percentile(live, 90))
        res["floor"] = float(np.percentile(live, 10))
    return res


def loudness(path):
    r = run(
        [
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-i",
            path,
            "-vn",
            "-sn",
            "-dn",
            "-af",
            "loudnorm=print_format=json",
            "-f",
            "null",
            "-",
        ],
        text=True,
    )
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    if not m:
        return None
    j = json.loads(m.group(0))
    return {
        k: j[k]
        for k in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset")
    }


def asr(path, out, model, prompt, reuse, asr_json):
    base = os.path.join(out, "asr")
    src = asr_json
    if not src:
        src = base + ".json"
        if not (reuse and os.path.exists(src)):
            if not os.path.exists(model):
                log(
                    f"no whisper model at {model}; locate one with "
                    "`mdfind -name ggml-large-v3-turbo.bin` and pass --model; skipping ASR"
                )
                return None
            wav = os.path.join(out, "a16k.wav")
            run(
                [
                    "ffmpeg",
                    "-nostdin",
                    "-v",
                    "error",
                    "-y",
                    "-i",
                    path,
                    "-ac",
                    "1",
                    "-ar",
                    "16000",
                    "-c:a",
                    "pcm_s16le",
                    wav,
                ],
                check=True,
            )
            cmd = ["whisper-cli", "-m", model, "-f", wav, "-ojf", "-osrt", "-of", base]
            if prompt:
                cmd += ["--prompt", prompt]
            r = run(cmd, text=True)
            if r.returncode != 0 or not os.path.exists(src):
                sys.stderr.write(r.stderr[-2000:])
                return None
    toks = []
    for seg in json.load(open(src))["transcription"]:
        for t in seg.get("tokens", []):
            if t["text"].startswith("[_") or not t["text"].strip():
                continue
            toks.append(
                (t["offsets"]["from"] / 1000, t["offsets"]["to"] / 1000, t["text"])
            )
    return toks


def named_by(toks, names):
    """Earliest end time of the token that completes any of `names`; None if none is heard."""
    text, owner = "", []
    for i, (_, _, s) in enumerate(toks):
        text += s
        owner += [i] * len(s)
    best = None
    for nm in names:
        m = re.search(re.escape(nm.lower()), text.lower())
        if m:
            t = toks[owner[m.end() - 1]][1]
            if best is None or t < best[0]:
                best = (t, nm)
    return best


def layout(kind, portrait):
    """Columns and rows per sheet, chosen so a sheet never exceeds the 2000 px read clamp."""
    table = {
        "first10": ((4, 5), (10, 2)),
        "faces": ((4, 6), (8, 2)),
        "redact": ((2, 3), (3, 1)),
    }
    return table[kind][1 if portrait else 0]


def montage(pngs, cols, rows, dest, aspect):
    """Tile cells sized to the frame's aspect so the whole sheet stays within the read clamp."""
    cw, ch = (READ_CLAMP - 8 * cols) / cols, (READ_CLAMP - 8 * rows) / rows
    s = min(cw / aspect, ch)
    bw, bh = int(s * aspect), int(s)
    font = ["-font", FONT] if os.path.exists(FONT) else []
    run(
        [
            "magick",
            "montage",
            *font,
            *pngs,
            "-tile",
            f"{cols}x{rows}",
            "-geometry",
            f"{bw}x{bh}>+4+4",
            "-background",
            "gray20",
            dest,
        ],
        check=True,
    )
    r = run(["magick", "identify", "-format", "%w %h", dest], text=True, check=True)
    w, h = (int(x) for x in r.stdout.split())
    if max(w, h) > READ_CLAMP:
        log(f"WARNING {dest} is {w}x{h}, over the {READ_CLAMP} px read clamp")
    return dest


def label(png, text):
    font = ["-font", FONT] if os.path.exists(FONT) else []
    run(
        [
            "magick",
            png,
            *font,
            "-pointsize",
            "28",
            "-fill",
            "yellow",
            "-undercolor",
            "black",
            "-gravity",
            "northwest",
            "-annotate",
            "+4+4",
            text,
            png,
        ],
        check=True,
    )


def scale_long(edge):
    return f"scale='if(gte(iw,ih),{edge},-2)':'if(gte(iw,ih),-2,{edge})'"


def first10_sheet(path, out, p):
    d = os.path.join(out, "f10")
    os.makedirs(d, exist_ok=True)
    pngs = []
    for k in range(20):
        t = k * 0.5
        if t + 0.05 >= p["dur"]:
            break
        png = os.path.join(
            d, f"t{t:05.1f}.png"
        )  # zero-padded so t10.0 sorts after t02.0
        run(
            [
                "ffmpeg",
                "-nostdin",
                "-v",
                "error",
                "-y",
                "-ss",
                f"{t + 0.05:.2f}",
                "-i",
                path,
                "-frames:v",
                "1",
                "-vf",
                scale_long(640),
                png,
            ],
            check=True,
        )
        label(png, f"{t:.1f}s")
        pngs.append(png)
    cols, rows = layout("first10", p["h"] > p["w"])
    return [
        montage(pngs, cols, rows, os.path.join(out, "first10.jpg"), p["w"] / p["h"])
    ]


def fps1_frames(path, out):
    """One labeled frame a second. The fps=1 filter emits frame k at k + 0.5 s (video-understanding)."""
    d = os.path.join(out, "fps1")
    os.makedirs(d, exist_ok=True)
    run(
        [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-y",
            "-i",
            path,
            "-vf",
            f"fps=1,{scale_long(1000)}",
            os.path.join(d, "f%04d.png"),
        ],
        check=True,
    )
    frames = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".png"))
    for i, f in enumerate(frames):
        label(f, f"{i + 0.5:.1f}s")
    return frames


def sheets(frames, out, kind, aspect):
    cols, rows = layout(kind, aspect < 1)
    per, dests = cols * rows, []
    for s in range(0, len(frames), per):
        dests.append(
            montage(
                frames[s : s + per],
                cols,
                rows,
                os.path.join(out, f"{kind}-{s // per + 1:02d}.jpg"),
                aspect,
            )
        )
    return dests


def audio_rows(au, ld):
    rows = []
    if au:
        if au["side"] < -150:
            bed = "exact dual-mono, no stereo background music"
        elif au["side"] - au["mid"] > -25:
            bed = "stereo content (background music or stereo ambience): the floor below reads the music, not the room"
        else:
            bed = "little stereo content"
        rows.append(
            f"| Mid level, whole file | {au['mid']:.1f} dBFS | v1 raw take -32.1; his edited cuts 14-16 dB louder (A1) | numpy RMS, 48 kHz |"
        )
        if "speech" in au:
            rows.append(
                f"| Speech level (90th pct of 0.25 s bins) | {au['speech']:.1f} dBFS | v1 by this tool: -28.4 (measure.md §1) | same; {au['zero_bins']} digital-zero bins excluded |"
            )
            rows.append(
                f"| Noise floor (10th pct of live bins) | {au['floor']:.1f} dBFS | v1 by this tool: -53.4 | same |"
            )
            rows.append(
                f"| Speech minus floor | {au['speech'] - au['floor']:.1f} dB | v1 by this tool: 24.9. No passing score: compare only with the founder's own mic reference, measured by this same tool | same |"
            )
        cs = au.get("clip_s", [])
        where = (
            f"; bins at {' '.join(f'{t:.2f}' for t in cs[:20])} s{' …' if len(cs) > 20 else ''}"
            if cs
            else ""
        )
        rows.append(
            f"| Samples at full scale (clipping) | {au['clipped']}{where} | 0 expected; check each bin against the words: clipping in speech means re-record | int16 == full scale (decoding clamps overs to full scale, INFERRED) |"
        )
        rows.append(
            f"| Side channel | {au['side']:.1f} dBFS: {bed} | raw takes none; edited cuts carry background music | numpy RMS |"
        )
    else:
        rows.append(
            "| Audio | no audio stream | every take needs the founder's voice | ffprobe |"
        )
    if ld:
        rows.append(
            f"| Integrated loudness, true peak, LRA | {ld['input_i']} LUFS, {ld['input_tp']} dBTP, LRA {ld['input_lra']} | not a habit; normalize at export (edit-export.md §5) | ffmpeg loudnorm |"
        )
    return rows


def report(a, p, cu, au, ld, toks):
    dur = p["dur"]
    if toks:  # drop text past the file's end, which whisper invents (video-understanding ASR guardrails)
        toks = [t for t in toks if t[0] < dur] or None
    L = [
        f"# first-10-seconds check: {os.path.basename(a.video)}",
        "",
        'Every value is MEASURED by first10-check.py; each row names its method. "His range" is '
        "Farza's six measured videos (METHOD §3.6 step 29, A1): survivor habits, not thresholds. "
        'A difference is marked "differs", never "fail".',
        "",
        "| Item | This cut | His range | Method |",
        "| --- | --- | --- | --- |",
        f"| Length | {dur:.1f} s | 44.9-140.4 s (§4a); length follows the beats | ffprobe |",
    ]
    if p["video"]:
        L.append(
            f"| Frame | {p['w']}x{p['h']}, {p['w'] / p['h']:.2f}:1, {p['fps']:.2f} fps | 16:9 or 1.54:1 on X; 9:16 on Instagram/TikTok | ffprobe |"
        )
    if toks:
        fw = next((t for t in toks if re.search(r"[A-Za-z0-9]", t[2])), None)
        if fw:
            L.append(
                f"| First word starts | {fw[0]:.2f} s{'  differs' if fw[0] > 0.3 else ''} | 0.04-0.23 s, 6 of 6 | whisper-cli -ojf |"
            )
        if a.name:
            nb = named_by(toks, a.name)
            shown = (
                f"not heard ({', '.join(a.name)})"
                if nb is None
                else f"{nb[0]:.2f} s ('{nb[1]}'){'  differs' if nb[0] > 3.6 else ''}"
            )
            L.append(
                f"| Name said by | {shown} | 2.3-3.6 s in 5 of 6; read it to the second, since token times move about 0.6 s between whisper runs | whisper-cli -ojf |"
            )
        first10 = "".join(s for t0, _, s in toks if t0 < 10).strip()
        L.append(
            f'| Words in 0-10 s | {first10[:300]} | what + why + "let\'s get into it" [11:13]-[11:16] | whisper-cli -ojf |'
        )
        cta = "".join(s for t0, _, s in toks if t0 >= 0.93 * dur).strip()
        L.append(
            f"| Words in last 7% ({0.93 * dur:.1f} s on) | {cta[:200] or '(none)'} | soft spoken CTA at 93-97% in 3 of 6 | whisper-cli -ojf |"
        )
        last = toks[-1][1]
        flag = (
            "  CHECK: speech ends early; whisper may have compressed times (A1 trap): re-run from an offset"
            if last < 0.6 * dur
            else ""
        )
        L.append(
            f"| Last speech ends | {last:.1f} s of {dur:.1f} s{flag} | close to the end | whisper-cli -ojf |"
        )
    else:
        L.append("| Words | (ASR skipped or failed) | | |")
    if cu:
        hard = cu["hard"]
        L.append(
            f"| Hard cuts in first 10 s | {sum(1 for t in hard if t < 10)} | raw take 0, produced 2, vertical story 3-13 (by register) | luma diff >= 20 at fps=30 |"
        )
        L.append(
            f"| Hard cuts, whole cut | {len(hard)} ({len(hard) / dur * 60:.1f}/min) | raw 1.8 (v1) to 2.9 (v2, all app switches, 0 edits); produced 13.3-18.5; story 52.1 (v6; v5's 45.5 overcounts archival) (§4a) | same |"
        )
        L.append(
            f"| Cut times (s) | {' '.join(f'{t:.2f}' for t in hard[:60])} | | same |"
        )
        L.append(
            f"| Shots under 1 s (start, length) | {' '.join(f'{s}+{n}' for s, n in cu['brief'][:40]) or 'none'} | read each at full size: a flash of another window hides here | same |"
        )
        L.append(
            f"| Soft changes (diff 10-20): zooms, app switches | {len(cu['soft'])} | | luma diff 10-20 |"
        )
    L += audio_rows(au, ld)
    L += [
        "",
        "Caveats (A1): on a screen take the luma detector counts app windows opening as cuts and "
        "misses Screen Studio zooms, so count real edits by eye on the sheets. It overcounts "
        "low-frame-rate archival footage.",
        "",
        "## Human reads (agent proposes, founder confirms)",
        "",
    ]
    for item in [
        "No title card, logo animation or music intro at frame 0 (6 of 6)",
        "First frame is the audience's own tool or world [09:13]-[09:22]",
        "Screen-led take: key detail visible and moving by about 3 s (1 of 6 did it: v1)",
        "Demo running by about 10% of length (4 of 6; all 4 X demos)",
        "Problem or turn present, and where (no common share across his videos)",
        "Closing words are a soft CTA, or none (v2, his biggest X hit, had none)",
        "Face share: bubble for screen takes, face shots in produced cuts (32-100% in his); n/a if voice-only",
        "Mute test: the few words a muted scroller picks up [33:54]-[34:07]",
        "Stop test in the founder's own feed [08:50]; bounce test [22:48]",
    ]:
        L.append(f"- [ ] {item}")
    L += ["", "## Images", ""]
    return L


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("video")
    ap.add_argument(
        "--out", help="output directory (default /tmp/launch-video-check/<stem>)"
    )
    ap.add_argument(
        "--name",
        nargs="*",
        default=[],
        help="every name the founder might say for the thing",
    )
    ap.add_argument(
        "--prompt", help="spellings to seed whisper with (names read off the screen)"
    )
    ap.add_argument("--model", default=os.environ.get("WHISPER_MODEL", DEFAULT_MODEL))
    ap.add_argument("--asr-json", help="reuse an existing whisper-cli -ojf file")
    ap.add_argument("--audio-only", action="store_true", help="fast audio gate only")
    ap.add_argument("--no-asr", action="store_true")
    ap.add_argument(
        "--sheets", action="store_true", help="also write 1 fps faces and redact sheets"
    )
    ap.add_argument(
        "--reuse", action="store_true", help="reuse cuts.json and asr.json in --out"
    )
    a = ap.parse_args()

    out = a.out or os.path.join(
        "/tmp/launch-video-check", os.path.splitext(os.path.basename(a.video))[0]
    )
    os.makedirs(out, exist_ok=True)
    p = probe(a.video)

    if a.audio_only:
        log(f"probed {p['dur']:.1f} s; audio gate only")
        L = [
            f"# audio gate: {os.path.basename(a.video)}",
            "",
            "MEASURED by first10-check.py --audio-only. METHOD gives no noise-floor number for "
            '"bad", so there is no passing score here: compare with the founder\'s own mic reference, '
            "and re-record on any clipping in speech (measure.md §1).",
            "",
            "| Item | This take | Reference | Method |",
            "| --- | --- | --- | --- |",
            f"| Length | {p['dur']:.1f} s | | ffprobe |",
        ]
        L += audio_rows(audio(a.video), loudness(a.video))
        rp = os.path.join(out, "audio-gate.md")
        open(rp, "w").write("\n".join(L) + "\n")
        print(rp)
        return

    cu = None
    if p["video"]:
        cpath = os.path.join(out, "cuts.json")
        if a.reuse and os.path.exists(cpath):
            cu = json.load(open(cpath))
        else:
            log(f"probed {p['dur']:.1f} s; measuring cuts at fps={CUT_FPS}")
            cu = cuts(a.video, p["dur"])
            json.dump(cu, open(cpath, "w"))
    log("measuring audio")
    au, ld = audio(a.video), loudness(a.video)
    toks = None
    if not a.no_asr:
        log("reading transcript" if a.asr_json else "transcribing (slow under load)")
        toks = asr(a.video, out, a.model, a.prompt, a.reuse, a.asr_json)

    L = report(a, p, cu, au, ld, toks)
    rp = os.path.join(out, "report.md")
    open(rp, "w").write("\n".join(L) + "\n")
    log(f"report written: {rp}; making images")

    if p["video"]:
        aspect = p["w"] / p["h"]
        frames = []

        def fps1():
            frames[:] = fps1_frames(a.video, out)
            return sheets(frames, out, "faces", aspect)

        jobs = [("first 10 s", lambda: first10_sheet(a.video, out, p))]
        if a.sheets:
            jobs += [
                ("faces", fps1),
                ("redact", lambda: sheets(frames, out, "redact", aspect)),
            ]
        for name, job in jobs:
            try:
                for dest in job():
                    L.append(f"- {name}: `{dest}`")
            except (subprocess.CalledProcessError, OSError) as e:
                L.append(
                    f"- {name}: FAILED ({e.__class__.__name__}); the measurements above stand"
                )
            open(rp, "w").write("\n".join(L) + "\n")
    print(rp)


if __name__ == "__main__":
    main()
