# I0 ingest manifest — 2026-10-24

Lead-run, sequential, before the research workflow. Data lives in `/tmp/farza-2026-10-24/` (not committed: 1.2 GB video).

| Step | Artifact | Result |
| --- | --- | --- |
| Tweet | `tweet.txt`, `thumb.jpg` | `cc-read-twitter https://x.com/ycombinator/status/2113654566776709147 --images`, rc 0, via fxtwitter. 2-post thread, 17 human-authored chapters, 1920x1080 video variant URL, YouTube `v12aSIZIXUs`. 146.8K views / 1K likes / 70 replies on first post when read. |
| Video | `video.mp4` | 1920x1080 h264, 23.976 fps, 2828.373 s (47:08.4), 1,185,216,577 bytes. curl rc 0. |
| Transcript | `transcript.txt` | REUSED from the 2026-10-23 probe (`/tmp/vu-2026-10-23/transcript.txt`, see `../../video-understanding-human-parity-2026-10-23/agents/E0-ingest-manifest.md`): whisper-cli large-v3-turbo, 8 × 360 s chunks, 934 lines, 11,775 words, absolute `[mm:ss]`. Same audio track as the 1080p file (only the video variant differs), so ASR was not re-run. No diarization; chunk boundaries not overlapped. |
| Cuts | `cuts-luma.txt` | Per-frame mean luma difference at 96x54 gray, strong cut ≥ 20, local max over ±2 frames (the `skills/video-understanding/SKILL.md` one-liner). **356 cuts → 357 shots; median shot 5.42 s, min 0.125 s, max 41.1 s; 7.55 cuts/min.** The 2026-10-23 ffmpeg `scene>0.3` pass on the 720p file found 177 — the skill's warning that the scene filter is a lower bound holds here (2.0×). Wall-clock ~34 min (host load average 155-277 during the run). |
| Coarse frames | `coarse/tNNNN.jpg` | 283 frames, one per 10 s at t = 5, 15, … 2825 s, each by its own input-side `-ss` (true timestamps, no fps-filter N/2 offset), 640 px wide. |
| Sheets | `sheets/sheet-01..12.jpg` | 6x4 tiles, label = true timestamp. First labeling pass failed (`magick -font Helvetica` unresolvable); rebuilt with `/System/Library/Fonts/Supplemental/Arial.ttf`. Verified by viewing sheet-03 (08:05-11:55; script insert visible 10:45-11:45). |

Research slots read inserts themselves at full 1920 px with `ffmpeg -ss … -frames:v 1` (the sheets were not ready when the workflow started), so the sheets are for later reviewers.
