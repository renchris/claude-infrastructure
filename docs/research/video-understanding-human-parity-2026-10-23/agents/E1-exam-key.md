# E1 exam key: 24 watching questions with grounded answers (2026-10-23)

Role: Examiner. Blind: the only inputs were the files under `/tmp/vu-2026-10-23/` (video, transcript, cuts, sheets, shot census). No tweet, x.com, YouTube page, yt-dlp metadata or web search was used. The names below come from on-screen text in the video itself (lower-thirds at 00:45, credits at 46:58) and from `transcript.txt`.

The question-only file is `/tmp/vu-2026-10-23/exam-questions.md`. It lists the 24 questions in time order with no axis labels. This key gives the axis for each.

Labels: **MEASURED** means this examiner ran it (frame read, ffmpeg or numpy measurement, whisper run). **DOCUMENTED** means a tool or doc states it. **INFERRED** means reasoned from measured evidence. Evidence frames are under `/tmp/vu-e1/f/`, scripts under `/tmp/vu-e1/`.

## Count per axis

| Axis | Questions | Count | Ungroundable? |
| --- | --- | --- | --- |
| A Spatial layout | 4, 5, 10, 17 | 4 | no |
| B People / appearance / identity | 1, 7, 8, 21 | 4 | no (Q8 rests on an inference chain, rated high) |
| C Audio-visual fusion | 2, 14, 15, 19 | 4 | no |
| D Inserted visual content | 11, 13, 16, 22 | 4 | no |
| E Motion / temporal | 6, 9, 20, 23 | 4 | no |
| F Paralinguistic / non-speech | 3, 12, 18, 24 | 4 | partly: **laughter** could not be grounded (see Dropped) |

Time spread: 5 questions in 00:00-01:07, 4 in 01:07-10:00, 5 in 10:00-20:00, 3 in 20:00-30:00, 4 in 30:00-40:00, 4 in 40:00-47:08.

## How ground truth was established (method, all MEASURED)

- **Frames:** each answer was checked on full-resolution 1280x720 frames from an input-side `ffmpeg -ss T -frames:v 1` (`/tmp/vu-e1/fr.sh`). Motion and AV questions also used labelled strips at 4-24 fps (`/tmp/vu-e1/strip.py`).
- **Strip timing bug, found and fixed:** a strip built with ffmpeg's `fps=F` filter emits frame n at about **label + 0.5/F**. At 0.2 fps the tile labelled 46:40 matched t=2802.5 s (mean abs diff 0.44, versus 2.7 or more for its neighbours). The script now starts decoding at S-0.5/F. Every time quoted below comes from an exact `-ss` frame or from a corrected strip.
- **The same bug affects the E0 coarse sheets:** sheet tile *k* shows about **label + 10 s**. The tile labelled 00:40 matches t=50 s (mean abs diff 1.34; at t=40 it is 175.65). E0's manifest called this "INFERRED, up to half an interval". It is exactly half an interval, so every sheet label is 10 s early. Downstream agents reading the sheets should add 10 s.
- **Cuts:** I recomputed shot boundaries from the mean absolute luma difference between frames at 96x54 over all 67,812 frames (`/tmp/vu-e1/cutdiff.py`, `/tmp/vu-e1/cuts2.py`, output `/tmp/vu-e1/cuts-robust.txt`). That gives 432 candidate spikes, **342 of them strong (diff of 20 or more)**. All 177 E0 cuts are recovered, and **168 strong cuts are missing from E0's `cuts.txt`**, mostly wide-to-guest-close-up cuts. I spot-checked 12 of the new cuts as frame pairs and all were real hard cuts (`/tmp/vu-e1/f/newcuts-a.jpg`). E0 "shot 31" (02:46.7-03:59.3) and "shot 158" (37:22-38:03) each contain hidden cuts.
- **Audio:** stereo 48 kHz was split into mid (L+R) and side (L-R) in dB per window (`/tmp/vu-e1/audio.py`). Dialogue in this mix is mono (side about -110 to -240 dB) and the music beds are stereo, so the side channel is a clean music detector here. Tonality and beat strength came from STFT peaks and onset autocorrelation (`/tmp/vu-e1/tonal.py`). Word timings came from `whisper-cli` large-v3-turbo with `-ml 1 -sow` on short clips (`/tmp/vu-e1/asr/`).

---

## Key

### Q1 [B] 00:00.0-00:02.4 and 00:07.5-00:08.6: cold-open outfit
- **Answer:** The man is the **host**: same face and receding light hair as the left-seated interviewer captioned "Aaron Epstein" at 00:45. In the cold open he wears a **charcoal/slate-grey crew-neck sweatshirt** with a small V-stitch at the collar. He sits alone, centred, at a round wooden table in front of the red pyramid-foam wall, gesturing with both hands. At the table conversation (from 00:45) he wears a **dark charcoal/navy button-up overshirt with two flap chest pockets, open over a white crew-neck T-shirt**. So the outfits differ: the cold open was shot separately.
- **Evidence:** `f/full-1.0.jpg`, `f/full-7.9.jpg` (sweatshirt); `f/full-1880.jpg` (31:20 table outfit); `f/open-0-12.jpg`. The two solo shots are 0.000-2.419 and 7.508-8.634: the E0 cuts at 2.419 and 7.508, plus the robust cut at 8.634 where the inset two-shot begins (`/tmp/vu-e1/cuts-robust.txt`). MEASURED.
- **Confidence:** high. Same person: INFERRED from face and hairline, plus `transcript.txt:2` ("my guest today") being spoken in this shot.

### Q2 [C] 00:14.3-00:17.1: captioned YouTube clip, who says what
- **Answer:**
  - "Well, shipping, right?" is said by the man in **round thin wire glasses with a beard and a grey/white checked jacket, holding a small DJI mic**, in close-up from 00:14.35 to 00:15.35.
  - "Are we shipping?" is said by the **young woman in a cream knit beanie**, who points, mouth open, from 00:15.72 to 00:16.47.
  - "Yeah, we're shipping." is said by a **different bearded man in thick dark tortoiseshell glasses and a denim jacket**, in close-up from 00:16.48 to 00:17.10.
  - The page is a YouTube watch page titled "shipping a ton and fixing 200+ bugs" (heyclicky, 1.14K subscribers, 25 likes).
- **Evidence:** `f/shipping.jpg` (6 fps), `f/full-13.5.jpg`, `f/full-16.0.jpg`, `f/full-16.6.jpg`. Robust cuts at 14.348, 15.349, 15.724 and 16.475 (`cuts-robust.txt`). Caption text matches `transcript.txt:4-6`. MEASURED.
- **Confidence:** high. Each caption sits over a shot of that person, and the speaker's mouth is open.

### Q3 [F] 00:36.5-00:49.0: music under the title cards
- **Answer:**
  - During the title graphics ("Learn" then "Startup" then "Startup School" then "Launch Video Advice", 00:36.7-00:44.4) a **loud, bass-heavy, rhythmic music track** plays and no one speaks.
  - It cuts down sharply at about **00:44.75**, as the wide two-shot appears. A faint tail fades under the first lines and is essentially gone by about **00:49**.
  - The cold-open speech before it (00:26-00:35) also had a quieter music bed underneath.
  - From 00:47 onward the dialogue is near-mono with no music.
- **Measurements (MEASURED):**
  - Mid/side over 36.5-44.5 s: **-16.1 / -30.7 dB**.
  - 75-97% of energy is below 250 Hz in each second from 36 to 44 s.
  - Onset autocorrelation strength **0.749** at a 0.372 s lag (about 161 or 81 bpm), versus **0.067** for dialogue at 50-58.5 s.
  - Side level falls from -32.8 dB (44.50 s) to -39.9 (44.75) to -44.7 (45.0), then to -58.5 (47.5), -71.3 (49.0) and -78.3 (49.25).
  - Cold-open speech 26-35 s: side **-45.6 dB**; dialogue 50-60 s: side **-113.6 dB**.
  - ASR left this span empty (`transcript.txt:15-16`, a gap from 00:31 to 00:45).
- **Confidence:** high. The label "music" is INFERRED from stereo spread, bass-heavy energy and strong beat periodicity. I did not listen to it.

### Q4 [A] 00:45.3-00:47.0: name captions and seating
- **Answer:**
  - **Left caption: "Aaron Epstein / General Partner, Y Combinator"**, under the man on the **left** (no cap; dark overshirt over a white tee).
  - **Right caption: "Farza Majeed / Founder, Heyclicky"**, under the man on the **right** (green cap, glasses, denim shirt).
  - On the table: an **open MacBook seen from behind** (the back of its lid faces the camera), slightly right of centre and nearer the guest. Its lid has a purple app-icon sticker at the top-left and a beige bear-shaped sticker at the bottom-left, and a cable runs off to the right. In front of the host lie **white papers on a red clipboard** with a black pen beside them.
  - The captions wipe outward from thin white vertical bars that appear at about 44.92, and are fully legible by about 45.5.
- **Evidence:** `f/wide-45.jpg` (4 fps), `f/trans-44.jpg` (12 fps), `f/mouth-45.jpg`, `f/full-1880.jpg` (table objects at full res). MEASURED.
- **Confidence:** high.

### Q5 [A] 00:51.0-01:06.7: split-screen layout
- **Answer:** The **left third or so is a white panel** showing a post from the account "Farza @FarzaTV" ("hi my name is farza / i just wanted to introduce myself") with a vertical phone-style video playing inside it, captioned for example "I really loved". The video's content changes across the window: old photos, an office, a crowd. The **right two-thirds is a close-up of the guest** (green cap), talking and gesturing. The layout holds for the whole window; only the clip inside the phone frame changes (sub-cuts at 51.30, 54.30, 57.89, 60.89, 64.27). It ends at 01:06.7 with a cut to the heyclicky website.
- **Evidence:** `f/full-58.0.jpg`, `f/split-51.jpg` (1 fps; label offset +0.5 s, so content is at least that wide), `cuts-robust.txt`. MEASURED.
- **Confidence:** high.

### Q6 [E] 02:00.0-03:00.0: cut count and framings
- **Answer:** **6 hard cuts**:
  - 02:03.04: wide to guest close-up
  - 02:14.76: back to wide
  - 02:25.56: guest close-up
  - 02:28.40: wide
  - 02:36.41: host close-up
  - 02:46.71: wide, which runs past 03:00 to 03:01.47

  The resulting sequence is wide (from 01:58.6), guest, wide, guest, wide, host, wide.
- **Evidence:** `cuts-robust.txt` (diffs 32.9-38.9); `f/min2.jpg` (1 fps strip, 01:58-03:02, each framing visible); `f/newcuts-a.jpg` (before/after pairs). E0 `cuts.txt` lists only **2** of these 6 (156.406, 166.708). MEASURED.
- **Confidence:** high.

### Q7 [B] 04:15.1-04:33.7: cap emblem, glasses, undershirt
- **Answer:** An **olive/sage-green baseball cap with a small white embroidered outline of a cartoon frog's head** (two bulging eyes and a wide mouth) on the front. **Round, thin metal wire-rim glasses.** A **white crew-neck T-shirt** under a **medium-blue denim button-down shirt** with white buttons and button-down collar points.
- **Evidence:** `f/x-255.jpg`, `f/x-260.jpg`, `f/caplogo.jpg` (3x zoom of the emblem), `f/b4.jpg`. Shot bounds 255.088 and 273.690 come from `cuts-robust.txt`. MEASURED.
- **Confidence:** high for the cap colour, glasses and shirts; high for "frog head" (the outline clearly shows two bulging eyes over a wide grin).

### Q8 [B] 06:04-06:15: who is in the code editor's webcam bubble
- **Answer:** **The guest**, shown **without his cap**: dark, tousled hair visible, the same round thin wire glasses, a beard, and a dark T-shirt. The screen recording is Xcode ("BuddyDictationManager"), with the macOS menu bar reading "Mon Apr 6 5:23 PM". The same uncapped man reappears in the webcam bubbles at 35:43-35:57 and 36:01, there in a checked shirt with white earbuds.
- **Evidence:** `f/full-368.0.jpg`; `f/identity.jpg` (side by side: bubble at 06:08, bubble at 36:01, guest close-up at 04:15). Supporting context:
  - The post at 00:20 from @FarzaTV embeds this same Xcode video (`f/open-12-24.jpg`).
  - The 00:58 panel shows the @FarzaTV account (`f/full-58.0.jpg`).
  - The lower-third at 00:45 names the right-seated man Farza Majeed.
  - `transcript.txt:108,128` ("This is like the launch of Hey Clicky"; "I record this video in the office").
- **Confidence:** high, but **INFERRED**: the face and glasses match and the on-screen context chain agrees. It was not checked against any outside source.

### Q9 [E] 08:40-08:48: the post that gets its text swapped
- **Answer:**
  - At first the post under a different account (shown as "Aaron Ng @localghost · 24m") reads **"Looks like Google is about to drop something?"**, above a photo of a storefront with "Gemini Audio" signage.
  - A **browser developer-tools panel** (Elements / Styles, "What's new in DevTools 152") opens on the right by about 08:44, and the post's text element is highlighted (08:44.0-08:44.5).
  - Between **08:45.50 and 08:45.75** the post's text changes to the guest's launch text: "I built this thing called Clicky. It's an AI teacher that lives as a buddy next to your cursor. It can see your screen, talk to you, and even point at stuff... I've been using it the past few days to learn Davinci Resolve, 10/10."
  - The **author name and avatar stay unchanged**.
  - At about 08:47.75 the view changes and devtools is no longer shown; by 08:50 he has scrolled to other posts.
- **Evidence:** `f/tw-grid.jpg` (full res at 08:40.5, 08:44.5, 08:47.0, 08:50.5); `f/tw-swap.jpg` (4 fps text crop); `transcript.txt:205` ("I'll literally change this text"). MEASURED.
- **Confidence:** high.

### Q10 [A] 10:38-10:54 and 13:03-13:35: picture-in-picture boxes
- **Answer:** At 10:38-10:54 there are **two boxes**, at the **top-left (host)** and **top-right (guest)**, either side of a white script document that begins "I want to show you a demo of our new agent interface." The same host-left, guest-right arrangement appears at 18:15 and 36:01. At 13:03-13:35 there is **only one box, top-right, with the guest**. The top-left there is the YouTube "Premium" header.
- **Evidence:** `f/pip-check.jpg` (10:38.5, 10:53.5, 13:03, 13:20); `f/script-doc.jpg`; `f/full-1095.jpg` (18:15); `f/full-2161.jpg` (36:01); `f/yt-1330v.jpg`. Document insert bounds 637.64-654.78 come from `cuts-robust.txt`. MEASURED.
- **Confidence:** high.

### Q11 [D] 13:25-13:35: YouTube watch-page details
- **Answer:** Title **"introducing screen-aware dictation."**; channel heyclicky (872 subscribers); **472 likes**; **"19K views 2mo ago"**; description line "Today we're shipping screen-aware dictation." In the playing video the presenter (glasses, dark sweater) sits at an outdoor table with a laptop, and a **red water bottle** stands to his right. The burned-in caption at 13:30 is "But here's the".
- **Evidence:** `f/yt-1330v.jpg`, `f/yt-1330-meta.jpg` (2x zoom of the metadata). MEASURED. The like count, the "2mo ago" and the bottle are not spoken anywhere. "872 subscribers" and "20k views" are spoken later (`transcript.txt:644`, 32:05), so a transcript reader could recover those two.
- **Confidence:** high.

### Q12 [F] 16:44-16:48: the pause
- **Answer:** **Near-total silence for about 1.15 s** (16:46.0-16:47.15) after "I always just think about like," and before "I want to talk about something." There is no music or room sound: the level drops below -80 dB. During it, in the wide shot, the guest holds **one hand raised beside his face in a loose C-shape**, mouth slightly open, looking off toward screen-left (a thinking gesture). He drops the hand as he resumes at 16:47.25.
- **Measurements (MEASURED):** mid level -21.6 dB over 16:44-16:46, then **-75.7 dB mean over 16:46.0-16:47.15**, with 0.1 s bins falling to -88.7 dB, then back to -15 to -25 dB from 16:47.2. Whisper's word-level timestamps **compress this pause away**: "like" at 1005.88-1006.15 runs straight into "i'm i i want" at 1006.15-1006.72 (`/tmp/vu-e1/asr/p16.csv`). The segment-level transcript only hints at it (`transcript.txt:458-459`).
- **Evidence:** `f/pause-1646.jpg` (4 fps), `f/pause-crop.jpg` (full res at 16:46.4). There is no cut between 1003.38 and 1012.8 (`cuts-robust.txt`).
- **Confidence:** high for the silence and its duration, and for the hand at his face. Calling it a "thinking pause" rather than an edit gap is INFERRED: the floor below -80 dB is unusually clean and could be gated or edited.

### Q13 [D] 18:13.5-18:16.5: class-listing card
- **Answer:** **"Mars Perseverance: Rover Landing"** (with a rocket emoji). Chips: **"Ages: 7-12", "Space", "30 Mins"**. Teacher label: **"Teacher Ashton"**, with a small avatar. First booking button: **"Book Class for Thu, Feb 25 - 10:..."**, with its time cut off by a webcam overlay. The next buttons are Thu, Feb 25 - 7:... and Fri, Feb 26 - 12:..., then "Show 3 more times". A selfie-video overlay of a man in glasses and a denim jacket covers the right end of the buttons, and the PiP boxes are host top-left and guest top-right.
- **Evidence:** `f/full-1095.jpg`. MEASURED. "Ages 7 to 12" is spoken (`transcript.txt:480`); "30 Mins", "Space" and "Teacher Ashton" are not.
- **Confidence:** high.

### Q14 [C] 19:16.8-19:17.7: reaction shot
- **Answer:** The **host** is on screen, in a single close-up from **19:16.82 to 19:17.70**. He is **not speaking**: the voice is the guest's, continuing "...happened, but the fact is". The host wears a **closed-lip amused smile**, looking screen-right. The next shot, from 19:17.70, is the **guest grinning broadly with his left hand (with ring) raised beside his head**, a self-deprecating "never happened" moment.
- **Evidence:** `f/react-1917.jpg` (10 fps crops); `f/laugh-19.jpg` (1 fps context); word timings from `/tmp/vu-e1/asr/r19.csv`: "which" 1155.70-1156.05, "never" 1156.05-1156.36, "happened" 1156.36-1156.90, "but" 1156.90-1157.18, "the" 1157.18-1157.46, "fact" 1157.46-1157.83. Robust cuts at 1156.822 and 1157.698. `transcript.txt:492`. MEASURED.
- **Confidence:** high.

### Q15 [C] 23:00-23:06.5: whose voice in the vertical video
- **Answer:** The voice is the **young man in the vertical Instagram reel**: dark-lit face, moustache, in a dark room. It is **neither person at the table**. The reel's caption reads exactly "Two months ago, I created this page to block my long-distance girlfriend and post my weight loss journey", which matches the spoken words. The reel man's lips keep forming different shapes from 23:01 to 23:04, while the guest's PiP (top-right) shows him watching with lips closed. At about **23:06 the reel is paused**: a play icon appears over it with the mouse cursor below. The guest then resumes ("first of all this is a random video..."). Reel counts: 7,752 likes, 108 comments, 45 reposts.
- **Evidence:** `f/reel-23.jpg` (1 fps), `f/reel-cmp.jpg` (full res at 23:02 vs 23:06.5), `f/reel-mouths-reel.jpg` and `f/reel-mouths-pip.jpg` (4 fps mouth crops); `transcript.txt:537`. The whole span is mono audio (side -114 to -180 dB), so no stereo cue exists here. MEASURED.
- **Confidence:** high.

### Q16 [D] 24:45.5-24:50.8: profile page
- **Answer:** Handle **"_heyclicky"** (display name heyclicky). **48 posts, 35.4K followers, 5 following.** Bio **"your friendly neighborhood cursor"**. Link **"heyclicky.com/ig"** plus a Threads handle "_heyclicky". The avatar is a white zig-zag/caret mark on a blue sky background.
- **Evidence:** `f/full-1487.jpg`, `f/ig-zoom2.jpg` (2.5x zoom), `f/ig-find.jpg` (1 fps; profile on screen 24:45-24:51; 24:44 briefly shows a different profile). MEASURED. **Note:** the downscaled coarse sheet read as "8 following". Only the full-res zoom shows **5**. The "/ig" link is spoken later (`transcript.txt:652`, 32:47); the counts and bio are not spoken.
- **Confidence:** high.

### Q17 [A] 29:47-29:56 then 30:01-30:13: eyelines in singles
- **Answer:**
  - **29:47.3-29:55.75: guest single.** He is placed **right of centre** with open space on the left and looks **screen-left**.
  - **30:01.0-30:13.3: host single.** He is placed **left of centre** with space on the right and looks **screen-right**.
  - This matches the wide shot (host seated left, guest seated right, facing each other): their eyelines meet across the cut. The same pattern holds at 02:03-02:14 (guest looks left) and 02:36-02:46 (host looks right).
- **Evidence:** `f/eyeline-30.jpg` (0.5 fps, corrected), `f/min2.jpg`; robust cuts at 1787.33, 1795.75, 1801.01, 1813.31. MEASURED.
- **Confidence:** high.

### Q18 [F] 35:50-36:13: music in the Spotify demo
- **Answer:**
  - Just before the music, **about 1.5 s of near-silence** (35:51.0-35:52.5), a beat while the demo waits.
  - Then **loud stereo rock music** (the Spotify page shows AC/DC "Back In Black") enters at about **35:52.75** and plays under the voices.
  - At about **36:04.25**, right after the assistant says "lowering Spotify to 50%" (36:02.64-36:04.88), the music **drops by about 16 dB** and stays lower.
- **Measurements (MEASURED):**
  - Mid/side: speech before the music (35:43-35:50.8) **-20.5 / -75.4 dB**.
  - Gap (35:51.0-35:52.5) **mid -47.7 dB, side digital silence**.
  - Loud music (35:53-36:04) **side -32.0 dB**; after the drop (36:04.5-36:13) **side -48.4 dB**, a **16.4 dB** fall.
  - 0.25 s bins: side -28.6 dB at 36:04.00, then -47.4 at 36:04.25 and -70.4 at 36:04.50.
- **Evidence:** `audio.py` output in session; word timings from `/tmp/vu-e1/asr/spot.csv`; `f/full-2161.jpg` (Spotify page).
- **Confidence:** high for timing and level. "Rock music" is INFERRED from the Spotify page on screen and the stereo bass-heavy bed; I did not listen to it.

### Q19 [C] 35:54.2-35:56.2: "Rock on, it's playing Back in Black now"
- **Answer:** **No.** The man in the bubble (the guest without his cap: checked shirt, round glasses, white earbuds) holds **one fixed wide, toothy grin with his hands clasped under his chin**, and his mouth does not form words. The line is the **assistant's synthesised reply** to his spoken command. By contrast, at 35:49.4-35:50.4 (his own "maybe a back in black... I love that song") his lips visibly form changing shapes. Related moments in the same bubble:
  - At about **35:44.0-35:44.5**, as he says "no hands", he **raises both open palms** to the camera.
  - At about **35:57.6-35:57.9**, as "it's a little bit loud" is heard, he **reaches up to his ear/earbud**.
- **Evidence:** `f/bubble-mouth24.jpg` (24 fps crops, 35:54.20-35:55.16: same grin in every frame); `f/bubble-mouth24-speak.jpg` (24 fps, 35:49.40-35:50.36: articulating); `f/bubble-mouth.jpg` (8 fps, 35:53.5-35:58); `f/spot-a.jpg` (2 fps). Words come from `/tmp/vu-e1/asr/spot.csv`: "Rock" 2154.16, "on" 2154.20-2155.03, "...now" 2156.06-2156.24. MEASURED. Attributing the line to the assistant is INFERRED from his spoken request ("Hey clicky can you please open up Spotify and play AC/DC", `transcript.txt:686`) and the content of the reply.
- **Tried and failed:** an autocorrelation F0 comparison did **not** separate the voices. Medians were 148-239 Hz across utterances, overlapping, and the music confounds it. So this answer rests on the visual evidence, not on pitch.
- **Confidence:** high (visual).

### Q20 [E] 37:33-37:36: visor gesture and match cut
- **Answer:** At about **37:33.1**, in the wide shot, the guest raises a **flat hand to his brow like a visor**, as if peering into the distance. He holds it as he starts "I'm always just trying to keep the story moving" (`transcript.txt:706`). The edit **cuts at 37:34.75 from the wide to his close-up mid-gesture**, hand still at his brow: a match on action. This cut is **missing from E0's `cuts.txt`** (E0 treats 37:22.0-38:03.2 as one shot). Before it, from 37:22.7 to 37:33, the **host** is the speaker in the wide shot, gesturing open-palmed toward the guest ("then you play the song, then you lower the music..."), while the guest listens with his hands on the table.
- **Evidence:** `f/salute.jpg` (8 fps, 37:33.0-37:34.9); `f/react-full.jpg` (1 fps; labels +0.5 s); `f/c3-faces.jpg`; robust cut at 2254.753 (diff 32.9). MEASURED.
- **Confidence:** high for the gesture and the cut. Which hand is raised (it appears to be his right, with a dark band on that wrist) is medium, so the question does not ask it.

### Q21 [B] 41:28-41:42: wrist and jewelry
- **Answer:** An **analogue wristwatch with a white dial and a brown leather strap** on his **right wrist** (screen-left while he faces the camera). A **thin silver ring** on his **left hand**, on what appears to be the ring finger. The same ring shows on his raised left hand at 19:17.7 and 42:02.
- **Evidence:** `f/acc-2490.jpg`, `f/acc-zoom.jpg` (zoom: both hands palms-down at chest, watch on the screen-left wrist, ring on the screen-right hand); `f/acc-2522.jpg`. Close-up bounds 2487.69-2502.75 come from `cuts-robust.txt`. MEASURED.
- **Confidence:** high for the watch and ring. "Right wrist" is INFERRED from his facing the camera with an unmirrored picture. Ring finger: medium.

### Q22 [D] 45:03-45:10: the document seen again
- **Answer:** **Yes.** It is the same script shown at **10:38-10:54** (and again 11:04.7-11:16.1). Here it is scrolled to start at "When talking to our users, we found many of them want to use agents more! But, didn't know what agents to create..." and includes "If you ask for the right things though, agents can be really magical." and "<Interview, fashion designer>". Along the bottom is a **dark floating screen-recording control bar** with an X button, **"Recover 2 unfinished recordings"**, four capture-mode icons (display / window / area / device), **"No camera"**, **"MacBook Pro..."** (a mic icon), **"Record system audio"**, and a settings icon. The PiP boxes are again host top-left and guest top-right. The guest names the writing app "FreeWrite" at that moment (`transcript.txt:850`).
- **Evidence:** `f/fw.jpg`, `f/fw-zoom.jpg`, `f/fw-tb.jpg` (toolbar zoom), `f/fw-4505.jpg` (1 fps), and `f/script-doc.jpg` for comparison. Insert bounds 2702.70-2710.25. MEASURED. **Note:** at sheet resolution the button read as "Recover 2 unlimited recordings". The full-res zoom reads **"unfinished"**.
- **Confidence:** high.

### Q23 [E] 46:55.3-46:58.7: the closing handshake
- **Answer:** The host reaches across the table, and they do a **multi-step handshake**:
  - **clasp** at about 46:56.0, hands raised (a cut to a tighter wide angle at 46:56.19)
  - a conventional **shake** at about 46:56.5-46:57.5
  - a **fist bump** at about 46:57.7-46:58.0
  - both open their fists into spread hands (an **"explosion"**) at about 46:58.2-46:58.4

  Then an **orange panel wipes in from the right** (from about 46:58.4) and covers the frame by about 46:58.7, revealing the credits card: Host Aaron Epstein; Producer Ryan Loughlin; Guest Farza Majeed; Editor Amanda Deisler; Camera Matt Kang, Chris Hall.
- **Evidence:** `f/handshake.jpg` (6 fps), `f/endcard.jpg`, `f/full-2822.jpg` (credits at full res); robust cuts at 2815.271, 2816.188 and 2818.399. MEASURED. No transcript line mentions it (`transcript.txt:930-934`).
- **Confidence:** high.

### Q24 [F] 46:47-47:08.4: ending audio, and the ASR's "Thank you."
- **Answer:**
  - Outro **music fades in under the last lines** from about 46:47.
  - It plays **at full level from about 46:56 to 47:02**, over the handshake and credits.
  - It **fades out over 47:03-47:04**.
  - From **47:05 to the end (47:08.37) there is digital silence**.
  - **Nothing is said in the last 3 seconds.** The transcript's final line "[47:07] Thank you." (`transcript.txt:934`) is an **ASR hallucination**: its source segment spans 05:07.98-05:37.96 in chunk-07, which is absolute 47:07.98-47:37.96, running past the end of the file and over measured silence (`/tmp/vu-2026-10-23/chunks/chunk-07.srt`, segment 175).
- **Measurements (MEASURED):**
  - Side level by second: -132 dB (46:46), -103 (46:47), -82 (46:48), -58.5 (46:50), -46 (46:53), **-28 dB (46:56-47:01)**, -32 (47:02), -44 (47:03), -65 (47:04), **-180 dB in both channels from 47:05**.
  - Window means: fade (46:47-46:55) mid/side -24.2 / -51.5 dB; loud (46:56-47:02) -14.3 / -28.1; final (47:05-47:08.3) mid and side at digital zero.
  - Beat-periodic, bass-heavy energy (90-95% below 250 Hz) during the loud part.
- **Confidence:** high.

---

## Dropped or replaced during grounding

- **Laughter (F):** dropped. Untranscribed loud bursts (06:23.2-06:24.3, -16.6 dB; also 02:11.5, 07:56.1, 11:40.2) are voiced, but too short or ambiguous to call laughter without listening. Whisper prompted with "(laughs) [laughter]" emitted no laughter tags on 19:10-19:28, 06:18-06:28 or 46:35-46:50. A pause question replaced it (Q12).
- **Speaker identity by pitch (C):** dropped as a method (see Q19).
- **20:01-20:08 sound under an old selfie video:** mono, tonal (a 411.8 Hz peak with 55.7 dB prominence), untranscribed, source unclear. Dropped.
- **Wardrobe at "04:20 wide" (B):** the first plan assumed a wide shot there. The frame showed a guest close-up, because E0 missed the 04:15.09 cut, so the question became Q7 (cap emblem).

## Reserve questions (verified, not in the exam)

All MEASURED, with frames in `/tmp/vu-e1/f/`:
- **00:02.4-00:04.5:** a New York Times headline card on pink: "Go Ask Alice Why Tech Start-Ups Are Spending Big on Hype Videos", with "Hype Videos" highlighted orange (`open-0-12.jpg`).
- **00:36.7-00:44.4:** title cards "Learn", then "Startup", then "Startup School" (orange), then "Launch Video Advice". At 44.42-44.83 the text vanishes, a black square grows inside the white box, and an orange square frame opens to reveal the wide two-shot (`trans-44.jpg`).
- **45:35 vs 46:43-46:50:** the laptop is open and upright with no phone on the table at 45:35. A black phone lies to the right of the laptop by 45:48. The guest holds the phone up at about 46:07.5 ("take your phone out", `transcript.txt:890`). By 46:43.5 the laptop is shut and lying flat (`late-table.jpg`, `laptop-cmp.jpg`).
- **06:08:** the macOS menu bar reads "Mon Apr 6 5:23 PM" (`full-368.0.jpg`).

## What this means for "watching like a human" (INFERRED)

- About half of the cuts are invisible to the E0 cut list (168 of about 345 strong cuts missed). Any agent that keys "who is on screen" off that list will mislabel spans, as in Q20.
- The coarse sheets are labelled 10 s early. That is a systematic error a human watching does not make.
- Three answers depend on reading text or counts that only appear at full resolution: Q16 ("5 following", which looked like "8"), Q22 ("unfinished", which looked like "unlimited") and Q11's like count. Sheet-level viewing alone gets them wrong.
- Two answers depend on audio facts the transcript hides or invents: the 1.15 s pause in Q12, which whisper's word timestamps erase, and the hallucinated final "Thank you." in Q24.
- Four answers depend on lip-motion versus voice alignment: Q2, Q14, Q15 and Q19. Each was groundable only with 8-24 fps face crops.
