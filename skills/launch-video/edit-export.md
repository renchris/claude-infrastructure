<!-- markdownlint-configure-file { "MD013": false } -->

# Edit and export (Stage 5)

This file decides **what** to do to a take. **How** belongs to the owning skills; load them before building and do not re-derive their mechanics here:
- `~/.claude/skills/hyperframes/SKILL.md`, the mandatory entry for any composition: cuts, zooms, captions, end cards, renders. Its creator-edit table names the domain skills each edit needs. Never its `/product-launch-video` route (`boundary.md` §1).
- `~/.claude/skills/media-use/SKILL.md` for music, SFX, transcription, caption files, cut, reframe and grading.

Work in `posts/<date>-<slug>/work/` (every HyperFrames project for this post lives there) and write exports to `out/`. Never edit `raw/`. Paths below use `P` and `T` from `measure.md`.

**HyperFrames intake** (INFERRED: not yet run end to end). A produced or captioned cut is a fresh HyperFrames creation, so its intent layer runs (`references/intent-interview.md`: must-haves, run-shape questions, the design ask). Give it a formed request written from `script.md` and the export matrix (§6): the route (`/embedded-captions` or `/general-video`, never `/product-launch-video`), destination and aspect, length "from the beats", his caption shape (§3) as the caption identity, and the design ask answered "no design spec: the footage as recorded" (§6.3: demos stay raw). Ask for no pitch round. Put any question HyperFrames still needs to the founder inside Stage 5's single hand-off. Its pre-render approval is the founder's Stage 5 watch of the master, not a separate gate (SKILL.md hard rule 2).

**The edit plan by register** (steps 42-45; his practice from A1, the caption decision INFERRED):

| | Raw screen take | Produced feature demo | Team update, selfie minimum |
| --- | --- | --- | --- |
| Cuts | 0-3 edits: a jump cut over dead time, and at most one short full-screen insert of the result (v1: 1.75 s at 82.87-84.62 s, A1) (§1) | a rough cut planned on the transcript; final pacing is the founder's (§2) | trims only |
| Captions | none on X if the screen carries the meaning on mute; always on Instagram and TikTok | burned-in phrase chunks (§3) | burned in, as for produced |
| Music | none added (v1 none; v2 only the demo's own Spotify playback, §4a) | licensed background music the founder picks (§7) | optional, licensed |
| End | a spoken soft CTA, or none (v2) | a spoken soft CTA, an optional end card (§8) | none needed |

## 1. Raw screen take: trim dead air, keep one take

His raw takes have 0-3 edits, no captions and no added music (§3.3; A1). v1 has one jump cut, removing dead time at 43.03 s (A1). Its other two cuts bracket a 1.75 s full-screen insert of the graded clip, the result reveal (82.87-84.62 s, A1). A take with an insert like that is still a raw take.

```bash
mkdir -p "$P/work" "$P/out"
# preview first: prints how much would be cut, writes nothing
auto-editor "$T" --edit "audio:threshold=-35dB" --margin 0.3s --preview
# then cut, keeping every range where the product is visibly working; never let it open a player
auto-editor "$T" --edit "audio:threshold=-35dB" --margin 0.3s --keep <start>sec,<end>sec --no-open -o "$P/work/trim.mp4"
```

- The flags (`--edit`, `--margin`, `--preview`, `--keep`, `--no-open`) are in `auto-editor --help` for 31.5.0 (MEASURED 2026-10-24). auto-editor opens its output by default, hence `--no-open`.
- The -35 dB threshold is an UNTESTED start. Set it a few dB above the take's measured floor (`measure.md` §1).
- **Silence is not always dead air.** In v1 the 70-72 s wait for Clicky's answer drops the voice to -61 dB and was left in (A1). INFERRED: the viewer waits with him, so it works as a beat. v2's roughly 1.5 s of silence after the ask is one of its measured beats (step 35). Keep product-working ranges with `--keep`, cut only the founder's own dead time, and check the trimmed cut list against the beat card.
- Speeding through a wait (`--set-speed`) misrepresents the product's speed. Prefer a jump cut, and say so on screen if timing is a claim (hard rule 4).
- Trim the head to the first word (an UNTESTED default taken from a step-29 habit, 6 of 6 hits; not a threshold; the report marks a later start "differs", never "fail").

## 2. Produced cut: a rough cut planned on the transcript

1. Lay `measure/asr.srt` against the script's beats (`script.md` §5). Mark keep ranges per beat and the best take of each line.
2. Assemble in HyperFrames: the "cut this footage" row of the hyperframes creator-edit table, `/general-video` + `/hyperframes-core` (`data-start`, `data-duration`, `data-media-start`).
3. Pace by register, as his habits, not targets: produced feature demos ran 13.3-18.5 hard cuts a minute with 2 in the first 10 s; vertical stories about 52 a minute (v6, 52.1; v5's raw 45.5 overcounts archival footage, so its true rate is lower, unmeasured) (§3.3, §4a, A1).
4. Beats over cuts: "I'm not trying to keep your attention, that's actually the wrong way to look at it." [37:36] At each beat ask "am I here? am I still watching?" [38:27].
5. HAND-OFF: final pacing, the music, and when not to cut. Taste is "not delegable" (K1).

**Voice-over form** (`voice: after`, UNTESTED; order in `capture.md` §4): build the silent rough cut from the screen tracks first, send it for the founder's `raw/vo-NN.wav`, then lay the voice in and retime the shots to it. Check the voice alone with `--audio-only`; captions come from the voice file's transcript.

## 3. Captions

**When** (step 42): every Instagram and TikTok version, raw or not; every produced cut; a raw X take stays uncaptioned only if the screen carries the meaning on mute (INFERRED, from X1 §2.11 and step 25). Much feed video plays muted (§7.4).

**Shape** (MEASURED A1, step 42): on 16:9, phrase chunks of 3-6 words, white, bottom-center at about 80% of height; on 9:16, 1-3 words at about 63-69% of height, moved up when screen content sits low (v6). Word-level captions are also in his range (R3 I7, R1 Insert D). His 80% shape comes from presenter-led cuts (step 42). On a screen-led 16:9 take whose action sits in the lower fifth (a terminal, a chat composer), put the captions in a padded strip below the frame (demo-recording "Editing") or above the action, and check one full-size frame per caption position (INFERRED).

**Route** (hyperframes §2 and `references/routes/<route>.md`; run `npx hyperframes skills update <route>` first, per hyperframes §4):
- `/embedded-captions` takes "existing talking-head footage", untouched, and adds a caption layer. Use it for a face-on-camera produced cut or team update.
- A voice-only screen take, or a cut mixing face shots and screen recordings with captions throughout, does not fit that contract; hyperframes says to keep routing rather than force the match, so it goes to `/general-video` with a caption track.
- `/embedded-captions` probes the clip and shortlists 2-3 caption identities. Pre-set his measured shape above as the identity, so the shortlist does not become an extra founder gate.

**Caption files.** For a composition they come from media-use's audio engine (`~/.claude/skills/media-use/references/audio.md`, `audio/references/captions/`). `measure/asr.srt` from whisper-cli is the measuring transcript, and the caption source only for the ffmpeg-full fallback burn-in below.

**Caption chunks from whisper, for the fallback** (UNTESTED settings): a second pass with a character cap and word splits gives short segments:

```bash
whisper-cli -m "<model, as in measure.md §2>" -l en -ml 28 -sow -osrt --prompt "<names>" \
  -f "$P/measure/a16k.wav" -of "$P/work/captions"
```

`-ml` and `-sow` are in `whisper-cli --help` (MEASURED). Proofread every caption against the audio; product names come out wrong unless `--prompt` seeds them.

**Fallback, a plain static SRT burn-in, only when the HyperFrames route fails.** The ffmpeg on PATH (`~/.claude/bin/ffmpeg`) has no `drawtext`, `subtitles` or `ass` filter, but `/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg` lists all three (MEASURED 2026-10-24: `-filters | grep -cwE 'drawtext|subtitles|ass'` returned 0 and 3). demo-recording records the same escape hatch. Nothing needs installing. Re-check before each use:

```bash
/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg -hide_banner -filters | grep -wE 'subtitles|ass|drawtext'
/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg -i "$P/work/trim.mp4" \
  -vf "subtitles=$P/work/captions.srt:force_style='FontName=Helvetica Neue,FontSize=18,Bold=1,PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,BorderStyle=1,Outline=2,Alignment=2,MarginV=40'" \
  -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -c:a copy "$P/work/captioned.mp4"
```

The style values are UNTESTED starting points; check the result against his measured position (about 80% of height on 16:9, a step-42 habit used as the default, UNTESTED) on a full-resolution frame. Remotion's presence is unmeasured, so the skill does not use it (§5).

## 4. Zooms, close zooms and the 9:16 version

- **The opening zoom** (Template A, step 28): onto the small key element at about 2.2 s, held while something moves, then back out at about 7 s: v1's shape (A1); "I purposely zoom in right here" [09:24]. Screen Studio does it while recording; prefer that. On a terminal take, whether its auto-zoom fires on keystrokes rather than clicks is unmeasured: set a manual zoom on the key output line in the recorder, or plan the post zoom below (INFERRED; `script.md` §4 Template A, terminal column). Rebuilding it in post is a custom job each time (K1): the hyperframes "zoom in here" row, `/general-video` + `/hyperframes-core` + `/hyperframes-keyframes`, animating the inner crop wrapper, not the timed clip.
- **One primary platform, then cross-posts** [33:23] (step 45). Whether reframing helps is untested. The 16:9 drawing video went to Instagram letterboxed and did better there by likes (27.4K against 5.1K on X; R4 I-7, I-8), and @heyclicky posted a 122 s vertical update to X (W1 S6).
  - **Letterbox**, the default for a desktop screen take (UNTESTED; his drawing-video precedent): `ffmpeg -i in.mp4 -vf "scale=1080:-2,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black" out.mp4`, with the captions in the band.
  - **Center crop:** media-use `references/operations.md`, "Reframe / crop". It keeps only the middle third of a desktop, so use it only when the action stays there (`capture.md` §1).
  - **A crop that follows the cursor** is a HyperFrames keyframed crop: the same custom job as the zoom.
- **Native 9:16 for Instagram first** ("most of our videos we make for instagram" [33:23]) needs a vertically shot take (Level 2), not a crop. Log `aspect` per post.

## 5. Loudness, then encode, then assert

His edited videos sit 14-16 dB louder than v1's raw take (A1). Normalize every export. The target below comes from neither METHOD nor A1; it is a common feed reference, INFERRED and UNTESTED:

```bash
mkdir -p "$P/out"
# pass 1: measure (audio only; sed keeps the whole JSON, which `tail` would cut: MEASURED 2026-10-24, ffmpeg 9.0.1)
ffmpeg -hide_banner -nostats -i "$P/work/final.mov" -vn -af loudnorm=I=-14:TP=-1:LRA=11:print_format=json -f null - 2>&1 | sed -n '/^{/,/^}/p'
# pass 2: apply with pass 1's measured_* values (linear=true keeps the dynamics)
ffmpeg -i "$P/work/final.mov" \
  -af "loudnorm=I=-14:TP=-1:LRA=11:measured_I=<>:measured_TP=<>:measured_LRA=<>:measured_thresh=<>:offset=<>:linear=true" \
  -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$P/out/x-16x9.mp4"
```

Assert every export: `ffprobe -v error -show_entries stream=codec_name,width,height,avg_frame_rate:format=duration -of default=nw=1 <file>` shows the expected size and frame rate, an audio stream, and the master's duration; then re-run the pass-1 `loudnorm` summary on each export, in the same `-vn … | sed -n '/^{/,/^}/p'` form. These are launch-film §8's assertions minus its film-only checks.

## 6. The export matrix

| File | Aspect, size | Captions | For | Source |
| --- | --- | --- | --- | --- |
| `out/x-16x9.mp4` | 16:9, or a Screen Studio take's native 1.54:1 | raw: only if the meaning is lost on mute | X | X wants 16:9 [33:35]-[33:39]; his X demos are horizontal (A1) |
| `out/yt-16x9.mp4` | 16:9 | yes, or YouTube captions from `captions.srt` | the YouTube library | "a library that will last for decades" [32:16] |
| `out/ig-9x16.mp4` | 9:16, 1080x1920 | yes | Instagram | step 42; P17 |
| `out/tt-9x16.mp4` | 9:16, 1080x1920 | yes | TikTok | step 42 |
| `out/li-16x9.mp4` | as X | as X | LinkedIn cross-post | §3.10 |
| `out/thumb-*.jpg` | 1280x720 candidates | n/a | YouTube | most of his thumbnails show a face (R2 I7); a product frame for a voice-only founder (INFERRED, UNTESTED) |

Export only for the platforms in `setup.md` `platforms` (plus X, the default primary for a developer tool). HyperFrames' `/product-launch-video` maps "X / LinkedIn / Instagram feed" to 1:1; this method keeps X at 16:9. Check each platform's current length and size limits at export time; METHOD does not record them. Length follows the beats: his six measured videos run 45-140 s (A1); his X demos run 100-140 s, 7-23 times X's suggested 6-15 s (X1 §2.4, a search summary), and still hit (step 43, arithmetic).

## 7. Music (§8 q15; the full resolution is in `open-questions.md`)

- **Raw take:** none. None of his raw takes has added background music (A1).
- **Produced cut:** background music only with a documented license, recorded in `licenses.md`. The founder picks "the song" [43:26]-[43:28], so ask first; picking a song does not license it (`open-questions.md` q15). `npx hyperframes media-use resolve --type bgm --intent "<mood>" --project <dir>` returns catalog tracks: record the license terms it reports, and do not use a track whose terms are unstated (INFERRED: the catalog's terms were not checked for this skill).
- **media-use's opportunity pass** offers background music for any piece over about 10 s, SFX on hard cuts, and a TTS voiceover when there is on-screen text with no voice. Decline the music and SFX on a raw take, and decline TTS always: the founder's own voice is the method (hard rule 6; K1).
- **Free first:** a paid or credit-spending media call (a media-use generation, a paid library) is made only after the founder approves it with the cost stated (launch-film §0.10; operator, 2026-10-02). A generated track counts only under q15 item 3, with its provider's terms saved in `licenses.md`.
- **In-app platform audio** is added by the founder at post time inside the app; the export then ships without music, and that license covers only that platform (INFERRED; check each platform's terms).
- **Never an unlicensed song playing inside the demo** (v2's AC/DC from Spotify, A1): mute that span or re-record.
- **Level:** his music-level changes do not reliably mark the story (v3's dip brackets its turn; v4's misses both its turn and its reveal; step 42). Start the music well under the voice and let the founder set it by ear. launch-film §6's "the score never drops out" was set for films and is not imported, but a produced cut's music should not drop to silence mid-piece unless the founder chooses it (a caution from the 10-09 verdict, `boundary.md` §3).

## 8. End cards and titles

Optional, and plain: v3's read "try it for free" then "heyclicky"; v4's "clicky" then "heyclicky" (A1). Put it after the spoken CTA. Never a title card or logo animation at the start: none of his six has one (step 29). A static end card is a HyperFrames `/general-video` static title card. Anything designed (an end card, a thumbnail) avoids the AI-template tells ("mvp ai template slop", the dominant purple gradient; `skills/launch-film/studio-method.md` §3; operator-feedback inferred rules 4-5, an INFERRED carry-over).
