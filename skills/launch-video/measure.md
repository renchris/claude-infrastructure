<!-- markdownlint-configure-file { "MD013": false } -->

# Measure a take (Stage 4)

Measure every take before editing it. A take goes back for bad audio or a leak, never for differing from Farza's habits, which are survivor habits (step 29, §7.1). The general method for watching a video (two tiers, the 2000 px read limit, ASR guardrails, the luma-diff cut list) belongs to `skills/video-understanding/SKILL.md`; this file gives the one tool this skill ships, how to read it, and the deltas A1 found on his videos.

```bash
P=~/Development/personal/launch-video/<product>/posts/<date>-<slug>
T="$P/raw/take-01.mov"
LV(){ python3 -I ~/.claude/skills/launch-video/first10-check.py "$@"; }   # before install: python3 -I <repo>/skills/launch-video/first10-check.py
LV "$T" --audio-only --out "$P/measure"                                        # 1. the audio check, fast
LV "$T" --out "$P/measure" --name "<Product>" "<feature>" --prompt "<names on screen>" --sheets   # 2. the full report; pass both names for a feature of a known product
```

Run the second command with `run_in_background` and poll for `report.md`; the report is written before any image, so an image failure never loses the numbers. `--reuse` keeps `cuts.json` and `asr.json` from an earlier run in the same `--out`; `--asr-json <file>` reads an existing whisper `-ojf` transcript; `--no-asr` skips speech.

## 1. The audio check (P15, step 2; a quality check, not an approval)

"the most important thing in any video … is audio quality" [41:46]-[41:55]; "if your audio is bad i'm bouncing" [41:55]. `--audio-only` decodes no video (both ffmpeg passes run with `-vn`) and runs no ASR. It reports, from the raw take:

- integrated loudness, true peak and loudness range (ffmpeg `loudnorm`);
- speech level (90th percentile of 0.25 s bins of the mid channel) and noise floor (10th percentile), with bins at exact digital zero excluded, since a trimmed edit gap is not room noise;
- their gap;
- samples at full scale, the clipping count, with the start times of up to 20 clipped 0.25 s bins;
- the side channel: dual-mono, or stereo content such as background music.

**How to read it.**
- **Clipping in speech** → re-record; it cannot be repaired. The report lists the clipped bins' times, so check each against the words: clipping in an app sound or a click is not clipping in speech.
- **No passing score for the floor or the gap.** METHOD gives no noise-floor number for "bad", so the skill sets none. The number also depends on the method. MEASURED on 2026-10-24 on A1's copy of his v1 raw take, a 3.0M-view hit: this tool (0.25 s bins, 48 kHz) reads speech -28.4 dBFS, floor -53.4 dBFS, gap 24.9 dB; a draft's script with 0.5 s bins of a 16 kHz mono mix read speech -28.9, floor -44.2, gap 15.3 dB on the same file. A fixed bar would come from one survivor and one method.
- **Compare like with like.** If the founder recorded a mic reference in Stage 0 (20 s of speech on the real mic and 20 s on the laptop mic, both measured with `--audio-only`), a take that sits closer to the laptop reference goes back: "this sounds like the laptop mic; re-record with the external mic" (UNTESTED). Without a reference, ask which mic recorded it and let the founder listen with the numbers in hand. Log `mic` and `gap_db` per post so the weekly review can find a bar later.
- **The raw voice, never a mix.** MEASURED on A1's copy of v4, a produced cut: floor -27.4 dBFS and gap 12.6 dB, because its background music fills the pauses; the side channel (-36.5 dBFS) flags the music. A floor under music reads the music, not the room.
- **Loudness level does not gate.** v1 went out un-normalized at -28.67 LUFS (MEASURED, this tool) and about -32 dBFS mid, 14-16 dB under his edited cuts (A1). That is a caveat to P15, not advice: normalize at export (`edit-export.md` §5).
- **Denoise lightly only**, with `afftdn` (present, §5; K1). `arnndn` is compiled in but needs an RNNoise model (`arnndn=m=<file>.rnnn`); none is on this machine (MEASURED 2026-10-24: `ffmpeg … -af arnndn -f null -` printed "Error initializing filters", and `mdfind -name .rnnn` found 0 files), so skip it unless the founder supplies one. Repair is "good enough for a rescue", not a substitute; a laptop-mic recording cannot be made to sound like a lav (K1).

His mic rule [42:17]-[42:27] is his rule, not a measured cause of his hits: which mic recorded v1 and v2 is unknown, and v2's bubble shows white earbuds (P15; R4 §3).

## 2. Words (whisper-cli)

The full run converts the take to 16 kHz mono and runs `whisper-cli -m <model> -ojf -osrt --prompt "<spellings>"`. The model defaults to `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/ggml-large-v3-turbo.bin` (found with `mdfind -name ggml-large-v3-turbo.bin` on 2026-10-24); override with `--model` or `WHISPER_MODEL`. If no model is found the tool says so and skips speech. Follow video-understanding's ASR guardrails (seed `--prompt` with names read off the screen; take pause lengths from `silencedetect`, never word times; drop text over digital silence). Two deltas from A1:

- **Compressed times under music.** Whisper put v5's speech into the first 49.5 s of 109.5 s (A1). The report flags speech that ends before 60% of the length; re-run from an offset.
- **Token times drift.** A draft's whisper pass put "Clicky" at 2.95 s where A1's transcript of the same file has 2.36 s: read "name said by" to the second, not the tenth.

`asr.srt` is the measuring transcript. Caption files for a composition come from media-use's audio engine (`edit-export.md` §3); `asr.srt` is the caption source only for the ffmpeg-full fallback burn-in.

## 3. Hard cuts

The luma-difference detector from video-understanding (96x54 gray, mean absolute difference of at least 20, local peak over ±2 frames), with the input resampled to `fps=30` first, so cut times stay right on variable-frame-rate screen recordings. It also lists soft changes (difference 10-20) and every shot shorter than 1 s, the first shot (0 s to the first cut) and the last (the last cut to the end) included.

Deltas from A1: on a screen recording it counts app windows opening as cuts and misses Screen Studio zooms (v2's 5 "cuts" are windows opening), and it overcounts low-frame-rate archival footage (v5: 7 "cuts" in 1.2 s). Count real edits by eye on the sheets.

## 4. The first-10-seconds report (§8 q6)

| Measured by the tool | Stays a human read (the agent proposes, the founder confirms) |
| --- | --- |
| Length, size, fps; first-word time; when any of the `--name` names is first said; the words in 0-10 s and in the last 7%; speech that ends early | No title card or logo at frame 0; captions by 1 s; whether the closing words are a CTA |
| Hard cuts in the first 10 s and in total, per minute, cut times, shots under 1 s, soft changes | Key detail visible and moving by 3 s; when the demo starts (% of runtime); when the turn lands |
| Loudness, speech, floor, gap, clipping (with bin times), stereo background music | Face and screen share (the `faces-NN.jpg` sheets help); whether the audio sounds good |
| | The mute, stop and bounce tests |

A1 made the right-hand calls by eye, corrected cut counts by hand, and re-ran whisper when it compressed timestamps (§5 rows 27-29). The report marks a difference from his range "differs", never "fail", and blocks nothing (§8 q7). Its images: `first10.jpg` (20 frames at 0.05 + 0.5k s, A1's method) and, with `--sheets`, `faces-NN.jpg` and `redact-NN.jpg` at 1 frame a second. Every sheet is sized to stay within the 2000 px read clamp, and each tile is labeled k + 0.5 s, because the `fps=1` filter emits frame k at k + 0.5 s (video-understanding).

## 5. The leak check (step 46)

Read every `redact-NN.jpg` (2 columns of 1 frame a second on a 16:9 take, so headings and most body text stay legible; 3 columns on a vertical take). Then read at full size, with `ffmpeg -ss <t> -i "$T" -frames:v 1 "$P/measure/hires-<t>.png"`, every frame that shows a URL bar, dashboard, terminal, inbox, settings page or customer list, and every shot under 1 s the report lists. The sheet samples one frame a second; demo-recording's "Capture hygiene" warns that a `fps=1/4` sheet "can step straight over a two-second leak", and a 1 fps sheet can still step over a shorter flash. For exhaustive on-screen text, OCR is the stronger tool (video-understanding, "Choosing tooling").

Look for:
- account or workspace IDs, keys, tokens, `.env` contents, emails, phone numbers;
- customer or user names, live revenue, support counts, and any metric or architecture "a clone could use" (X1 §2.3; v2's Stripe dashboard showed an account ID, live revenue and "1 dispute has not been answered", R4 §3; Clicky had 1,552 forks and a port within 18 hours, W1 S27);
- another project's name, goal or plan, the founder's or anyone's (hard rule 4), and cloud account IDs, ARNs, bucket or host names on a CLI or infra take (`capture.md` §1);
- notification banners, other people's messages, and Claude Code composer ghost text (demo-recording);
- the menu-bar clock and date: harmless, but A1 timed v1's posting from it.

List each finding with its time. The founder decides what may be shown; then blur it in HyperFrames, cut it, or re-record.

## 6. Timings and the dogfood (MEASURED 2026-10-24, load average about 280-320 by `uptime`)

Run on A1's own copies of his videos in `/tmp/farza-A1-farza-launch-videos-measured/` (`bash /tmp/lv-final-dogfood/run.sh`):

| Run | Wall clock | Matches A1? |
| --- | --- | --- |
| `--audio-only` on v1 (99.9 s), after the `-vn` fix | 79.5 s (`/usr/bin/time -p`, load 132-169; 206 s before the fix at load 280-320) | mid -32.0 dBFS against A1's -32.1; dual-mono side -180 dB; -28.67 LUFS, -9.10 dBTP; 0 clipped samples |
| `--audio-only` on v4 (120.1 s), after the `-vn` fix | 158.9 s (`/usr/bin/time -p`, load 164-169; 157 s before); user CPU 4.75 s, so wall clock here is load, not work | side -36.5 dBFS flagged as stereo background music; -15.38 LUFS |
| full on v1 with `--asr-json` (A1's transcript) and `--sheets` | about 6.5 min to `report.md` and `first10.jpg` (cuts alone 146 s); 973 s with the 100 labeled 1 fps frames and their sheets | first word 0.08 s; "Clicky" by 2.36 s (A1: 2.4); 3 hard cuts, 1.8 a minute, 0 in the first 10 s, at 43.03, 82.87 and 84.63 s (A1: 84.62); 3 soft changes (A1: 3); the last 7% holds "I'll put the link below and give it a shot."; the redact sheets kept the menu-bar clock "Mon Apr 6 5:24 PM" and Resolve's panel labels legible |
| full on v4 with `--asr-json`, no sheets | 266 s | 37 hard cuts, 18.5 a minute (A1: 37, 18.5), 2 in the first 10 s at 4.03 and 6.00 s (A1: 4.04, 6.01); first word 0.04 s; floor -27.4 dBFS under the music; three shots under 1 s listed (13.13, 84.07, 84.93 s), unchanged when recomputed from `cuts.json` with the first and last shots included (MEASURED 2026-10-24; v1 still 0, v6 still 25) |
| full on v6 (9:16, 45.0 s) with `--asr-json` and `--sheets` | 362 s | first word 0.12 s; "Clicky" by 3.60 s (A1: 3.6); 13 hard cuts in the first 10 s, 52.0 a minute (A1: 13, 52.1); vertical sheets came out 1998x1178 (redact, 3 columns) and 2000x876 (faces), all within the clamp |

Whisper itself adds more: two drafts' dogfoods measured about 15 minutes for a full measuring run on v1 without whisper and over 20 minutes with it, at load 250-317. On an idle machine all of this should be far faster (INFERRED, not measured). The fast path therefore runs `--audio-only`, then `--no-asr --sheets`.

## 7. `measure/reads.md`: what the founder and agent add

first10-check.py rewrites `report.md` (and `audio-gate.md`) in full on every run, so nothing hand-written goes there. The tool writes the measured table and the unticked human reads; write these, by hand, in `measure/reads.md`, which the tool never touches:

```markdown
- mic that recorded it: <model>   (founder)        reference: real <gap> / laptop <gap> | none
- audio call: keep | re-record   (founder, with the numbers in hand)
- leak check: sheets <paths>; full-size reads <n>; findings: none | <t, what, fixed how>
- human reads: title card <y/n>; demo starts at <s>, so setup share <s / length> (P8's measure) against the plan's estimate; pivot at <s>; turn at <s>; face share <%> | bubble | voice-only; CTA <y/n>
- differs from his habits (reference only, step 29): <list>
```

## 8. His habits on six videos that did well (step 29, MEASURED A1)

Report differences from these; never fail a take on them.

| Habit | v1 | v2 | v3 | v4 | v5 | v6 | Holds in |
| --- | --- | --- | --- | --- | --- | --- | --- |
| First word within 0.3 s | 0.08 s | 0.20 s | 0.23 s | 0.04 s | 0.04 s | 0.12 s | 6 of 6 |
| No title card or logo animation | yes | yes | yes | yes | yes | yes | 6 of 6 |
| Thing named by about 3.6 s | 2.4 s | 2.3 s | 3.5 s | 2.9 s | 5.8 s (who he is) | 3.6 s | 5 of 6 |
| Key detail visible and moving by 3 s | yes (zoom 2.2 s) | no | no | no | no | no | 1 of 6; screen-led takes only |
| Demo running by about 10% | 10% | 2% | 8% | 9% | no demo | 36% | 4 of 6 (all 4 X demos) |
| Problem or turn | from 10.4 s (10%) | none; comic beats | 60.3 s (43%) | 21-30 s, reveal 31 s (26%) | n/a | 5-10 s | no common share |
| Spoken product CTA in last 3-7% | 97% | none | 93% | 93% | none | from 81% | 3 of 6 |
| Hard cuts in first 10 s | 0 | 0 | 2 | 2 | 3 | 13 | by register |

The first line comes closest to a rule: it holds in 6 of 6 and serves his point that scrollers see the first three seconds [09:32]. It is still a measured habit, not a tested rule. Why none of these can be a threshold: they come only from videos that did well (§7.1), and his "thousands of videos" nobody cared about [09:49] were never measured. Before any habit becomes a check, A1's method has to be run on the §4d lower performers (1.19M, 453K, 344K, 342K, 294K, 202K and 145K views) to see whether it separates them from the 3M posts (§8 q7). That fieldwork is not done (§9, "Not done"). Meanwhile the post log collects `first_word_s`, `named_by_s` and `cuts_first10` for every post, hits and misses alike, so the founder's own data can answer it later.
