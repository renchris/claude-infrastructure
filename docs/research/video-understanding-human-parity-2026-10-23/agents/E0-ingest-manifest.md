# E0 ingest manifest: blind two-tier ingestion, 2026-10-23

Method: `skills/video-understanding/SKILL.md` (steps 0-5), run blind. Only input: the twimg MP4 URL in the brief. No tweet, x.com, YouTube, yt-dlp metadata or web page was opened. Host load average was about 85-93 on 10 cores during the run (`uptime` at start). All figures are MEASURED from this run unless marked otherwise.

## Source

| Field | Value |
| --- | --- |
| Path | `/tmp/vu-2026-10-23/video.mp4` (234,206,174 bytes) |
| Duration | 2828.373 s (47:08.4) |
| Video | h264, 1280x720, 24000/1001 fps (23.976), 67,812 frames |
| Audio | AAC, 48 kHz, 2 channels |
| Bitrate | 662 kb/s overall |
| Probe record | `/tmp/vu-2026-10-23/ffprobe.txt` |
| Download wall-clock | 13 s (curl, rc 0) |

## Artifacts

| Step | Artifact | Path | Count / size | Wall-clock | Failures |
| --- | --- | --- | --- | --- | --- |
| 1 | Video + probe | `video.mp4`, `ffprobe.txt` | 1 file, 223 MB | 13 s | none |
| 2a | 16 kHz mono WAV | `audio16k.wav` | 86 MB | 36 s (extract + segment) | none |
| 2b | ASR chunks (360 s each; the last is 308.4 s) | `chunks/chunk-00..07.{wav,srt,json,log}` | 8 chunks | 63, 34, 31, 33, 35, 32, 46, 39 s per chunk (313 s total; whisper's internal totals are 30.5-45.4 s) | none, all rc 0 |
| 2c | Merged transcript | `transcript.txt` | 934 segments, 11,775 words, each line `[mm:ss]` absolute (chunk index x 360 s + the segment's `offsets.from`) | under 1 s | none |
| 3 | Hard-cut list | `cuts.txt` (raw log `scene-raw.log`) | 177 cuts, so 178 shots. Shot length: min 0.042 s, median 8.84 s, max 117.9 s. 12 inter-cut gaps are under 1 s. | 102 s (ran in the background, concurrent with ASR) | none |
| 4 | Coarse sheets | `sheets/sheet-01..12.png` (source frames: `coarse/` raw, `coarse-lab/` labeled) | 141 frames at 1 per 20 s, 12 sheets in 4x3 (sheet-12 is partial: 9 tiles), each sheet 2592x1104 | 71 s extract + 7 s label + 25 s montage | none that matter: `montage` printed "unable to read font" 12 times, once per sheet, for its own title text; the burned-in timestamp labels render correctly (checked by viewing sheet-01) |
| 5 | Shot census | `shots/shot-NNN_tMM-SS_<mid-seconds>.jpg`, index `shots-index.txt` (shot#, start, end, mid) | 150 of 178 shots, all 1280x720 JPEG q2, 12 MB total | 20 s | 0 of 150 extractions failed |
| 6 | This manifest | `MANIFEST.md`; copy at `docs/research/video-understanding-human-parity-2026-10-23/agents/E0-ingest-manifest.md` | 1 | n/a | n/a |

Total measured wall-clock is about 11 min, counting only the timed commands and excluding model and tool lookup.

## Parameters and caveats

- **ASR:** `/opt/homebrew/bin/whisper-cli -m "~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/ggml-large-v3-turbo.bin" -l en -t 8 -osrt -ojf`. The model is not in `~/` dev trees or `/opt/homebrew`. The suggested `fd` search returned nothing and `mdfind` found the model in VoiceInk's app support folder. ASR ran with no diarization, so the transcript has no speaker labels.
- **Chunk-boundary risk:** each split was a hard 360 s cut with no overlap. A word that straddles a boundary (06:00, 12:00, ... 42:00) may be clipped or duplicated. This is INFERRED and was not checked.
- **Cuts:** `select='gt(scene,0.3)',showinfo` with `-fps_mode passthrough`, at native 720p. The brief set the threshold at 0.3; the skill's example uses 0.2 (SKILL.md:61). The 12 gaps under 1 s are probably dissolves or graphics transitions counted twice. This is INFERRED and was not checked.
- **Shot cap:** 178 shots exceeded the cap of 150. The script picked 150 by evenly spaced index, `round(i*(178-1)/149)`, so **28 shots have no census frame**. The script is `/tmp/vu-scripts/shots.py`, and the frame times it chose are in `shots-index.txt`. Each frame was taken at the midpoint (start+end)/2 with an input-side `-ss` seek.
- **Coarse labels:** the label time is `(k-1)*20 s` for frame k from `fps=1/20`. That is ffmpeg's nominal output time; the real decoded frame may sit up to about half a frame interval away. This is INFERRED from the fps filter's default rounding and was not checked. Tiles are 640 px wide in the source, about 500 px once Claude Code downscales the sheet to 2000 px (SKILL.md:33-38). Composition is legible at that size; small on-screen text is not.
- **Helper scripts** are kept outside the data dir: `/tmp/vu-scripts/merge.py` (transcript merge) and `/tmp/vu-scripts/shots.py` (shot selection).
- No content interpretation was done beyond confirming that sheet-01 rendered.
