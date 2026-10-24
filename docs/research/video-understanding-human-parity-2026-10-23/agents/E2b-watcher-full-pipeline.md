# E2b: blind watcher, full pipeline (2026-10-23)

Role: blind watcher. Inputs were only the files under `/tmp/vu-2026-10-23/` (MANIFEST.md, transcript.txt, cuts.txt, shots/, video.mp4) and the method in `skills/video-understanding/SKILL.md`. I did not open the tweet, x.com, YouTube, any metadata, the web, or any file in `agents/`.

Tags: **MEASURED** means I ran it this session. **DOCUMENTED** means an input file says so (the transcript is whisper output, so it is DOCUMENTED-by-ASR and can be wrong). **INFERRED** means it is my reading of the evidence.

## Budget and method

- **Image reads: 19 of the 60 allowed** (MEASURED, counted below). I spent no read on `sheets/`. The shot census replaced them.
  1-2: shot-census montages `/tmp/vu-e2b/census1.png` and `census2.png`. All 150 census frames at 192 px, labeled with shot number and time.
  3-19: targeted reads `/tmp/vu-e2b/q*.png` and `spec.png`, each named after its question.
- **Full resolution at no extra cost:** two 1280x720 frames stacked vertically (1280x1448) stay under the 2000 px downscale ceiling (SKILL.md:27-38). So one read gives two native-resolution frames. A 2x2 grid gives four frames at about 1000 px each. Helper: `/tmp/vu-e2b/grab.sh`.
- **Non-speech audio is numeric, not listened to.** The scripts are `/tmp/vu-e2b/rms.py` (RMS per 100 ms), `floor.py`, `band.py` (20th-percentile floor per 0.5 s, total and 3-8 kHz) and one spectrogram image (`spec.png`, ffmpeg `showspectrumpic`).
- **Motion:** I tracked the end-card wipe edge per frame at full frame rate (`/tmp/vu-e2b/wipe.py`). I chose this over `motion-probe.py`'s image outputs because it gives numbers and costs no read.

### Method finding: the 0.3-threshold cut list misses most wide-to-single cuts (MEASURED)

`cuts.txt` (threshold 0.3) lists 2 cuts in 02:00-03:00. A rescan at `scene>0.06` (`/tmp/vu-e2b/scan.sh`) found 6. Across each extra candidate (123.04, 134.76, 145.56, 148.40 s), the frame-pair RMSE was 0.221-0.223, against 0.227 at the two listed cuts and 0.097 inside a shot. The cause: the wide shot and the singles share the same red acoustic-foam palette, so the histogram-style scene score sits just under 0.3.

So the 178-shot count in MANIFEST.md is an undercount (INFERRED, size unmeasured). Any question about cut counts needs a low-threshold rescan of its window. I ran one for every window that mattered: 02:00-03:00, 16:40, 19:10, 29:40-30:20, 37:28, 41:26, 46:50.

## Part 1: chapters

Built from transcript topic shifts (DOCUMENTED-by-ASR) and the shot census (MEASURED).

| Start | Chapter |
| --- | --- |
| 00:00 | Cold open: the host to camera, plus clips of the guest's videos |
| 00:36 | Title card: "Startup School / Launch Video Advice" |
| 00:45 | The guest's background: eBay at 13, an online school, YC 2020, Buildspace, Hey Clicky |
| 01:10 | What changed: algorithmic platforms, so you are "constantly launching" |
| 02:55 | Old media is gone; "demos, not launches"; work backwards from the launch |
| 04:35 | The hook is decided before the video is made |
| 05:02 | Show the process, not the ending; you launch to get users, through a repeatable channel |
| 06:01 | Case study: the Clicky launch video (about 3M views, 7,000 downloads, about 100 retained) |
| 07:43 | Writing the post: "tweet poetry" and the "did I stop?" test (fake tweet via Inspect) |
| 09:11 | The first frame and the first 3 seconds: Xcode, the zoom |
| 10:07 | Scripting every video: the script doc, the first 10 seconds, setup at 10-20% |
| 11:56 | The first shot: walkthrough of the screen-aware dictation video |
| 13:59 | Rehearsing lines; the team overrules "this is the worst video" |
| 15:14 | Demo-driven development and the "check this out" feeling |
| 16:11 | Standing out: post, forget it, check a week later |
| 17:42 | Old Zip School launch videos: 23 likes is still a launch |
| 19:36 | The day-one landing-page "launch" (Dec 1, 2020) and the reps analogy |
| 20:36 | The formula: who I am, what's going on, what I'm building, let me show you |
| 22:44 | Studying where you bounce: dissecting Reels |
| 24:04 | Every demo is a mini story; the founder as a character |
| 24:41 | Weekly "everything we built this week" team videos and why they work |
| 26:56 | Joy, being yourself, and why founders won't post a 30-second selfie video |
| 29:09 | B2B buyers are on TikTok and Instagram too: design-agency TikToks found 50 leads |
| 31:01 | Channels compared: Twitter converts worst, YouTube about 20%, Instagram 70% of traffic, /ig link tracking |
| 33:18 | Formats per platform: a 16:9 video for Twitter, watched muted |
| 34:30 | Taste versus volume |
| 35:28 | Spotify voice-control demo: no cuts, but beats |
| 37:53 | Beat structure for short attention spans |
| 38:44 | First hire was a filmmaker; the audience is the moat |
| 40:46 | Gear stack: Screen Studio, iPhone + Edits, Sony FX3/FX30 + DJI mic, audio first, DaVinci |
| 42:59 | Working with a dedicated filmmaker; if you can't afford one, start anyway |
| 44:58 | Writing first, in FreeWrite |
| 45:40 | The 30-day challenge |
| 46:52 | Thanks, sign-off and end credits |

### Summary (150 words)

A Y Combinator interview. YC General Partner Aaron Epstein (the host) talks with Farza Majeed (founder of Hey Clicky, formerly Zip School and Buildspace) about launching through video in 2026. Farza argues that big, polished launch videos are obsolete. On algorithmic feeds a founder should "constantly launch" small, honest demos that show the process.

He screen-shares his own posts and dissects them:
- the Clicky launch video, which got about 3M views but only 7,000 downloads and about 100 daily users, the number he actually cares about
- tweet copy tested by faking it into a real feed
- scripted hooks, the first frame and the first 10 seconds
- old Zip School videos with 23 likes
- weekly team updates
- a no-cut voice-control demo built on "beats"

He compares channels: Twitter converts worst, YouTube converts about 20%, and Instagram brings 70% of traffic. He also describes his gear and his filmmaker collaborator. He closes with a challenge: post one 10-minute phone video every day for 30 days.

### Ten most important claims and advice

1. [02:28] You are no longer making posts; you are constantly launching on algorithmic platforms.
2. [03:11] A simple talk-to-camera video beats a $20,000 produced video on engagement and traffic.
3. [03:55] Work backwards from "what are we launching this week": write the caption and hook while building the feature.
4. [07:14] Ignore views and measure downloads and retention: 3M views gave about 7,000 downloads and about 100 five-day users.
5. [08:49] The "did I stop?" test: paste your copy into a real feed and see whether you would stop on it.
6. [11:04] The first 10 seconds say what it is and why it matters. Setup is 10-20% of a one-minute video.
7. [14:00] Script and rehearse every line, so that it sounds off the cuff.
8. [31:03] Channels differ: Twitter converts worst, YouTube converts about 20% and lasts for decades, Instagram is about 70% of traffic. Track it with links such as /ig.
9. [41:46] Audio quality matters most: "if your audio is bad I'm bouncing." Use a cheap DJI mic.
10. [45:46] Challenge: post one 10-minute phone video every day for 30 days. "In order to not be cringe, you must first be cringe" (44:56).

## Part 2: exam answers

| # | Answer | Conf. | Evidence |
| --- | --- | --- | --- |
| 1 | **The host.** It is the same man captioned "Aaron Epstein, General Partner, Y Combinator", seated left. Solo, he wears a grey-blue long-sleeve crew-neck sweatshirt with no visible collar or undershirt. At the table he wears a dark navy button-up overshirt (flap chest pockets) over a white crew-neck T-shirt. Same wooden table and red foam wall. | 90 | MEASURED: `q1q4.png` (t=1.0, 8.0, 46.0, 49.5) |
| 2 | "Well, shipping, right?": the foreground man with curly dark hair, beard, round thin wire glasses and a black-and-white patterned jacket. "Are we shipping?": a young woman in a cream knit beanie (a hand holds a small DJI mic toward her). "Yeah, we're shipping.": a different bearded man with curly hair, dark thick-rimmed round glasses, and a denim jacket over a white tee, in his own close shot. The clip plays inside a YouTube page titled "shipping a ton and fixing 200+ bugs". | 80 | MEASURED: `q2q5.png` t=14.6; `q2b.png` t=15.9-17.0 (caption and open mouth) |
| 3 | No speech, only a music bed or sound design: sustained tonal notes below about 1.5 kHz in a stepped, rising pattern, plus rhythmic broadband clicks or ticks that grow denser. It runs from about 00:36.7-37.0 to about 00:44.5-44.8 and stops abruptly at the cut to the studio (44.75). Under the first conversation lines there is no music, only dry speech over room tone. The 20th-percentile level floor falls about 15-20 dB (about 33-35 down to 13-20 in band.py units). | 75 | MEASURED: `spec.png` top panel; `band.py 32 18` |
| 4 | Left: "Aaron Epstein / General Partner, Y Combinator", under the host (left, bald-ish, navy overshirt). Right: "Farza Majeed / Founder, Heyclicky", under the guest (right, green cap). On the table: an open MacBook, back of the lid to camera, with a purple wave-logo sticker and a beige sticker. It sits center, slightly toward the guest, as his machine, with a cable trailing off the table front. In front of the host: an orange-red clipboard with white papers and a black pen. | 85 | MEASURED: `q1q4.png` t=46.0; `q6q7.png` t=137 |
| 5 | Left, about 36% of the width: a white X/Twitter post by "Farza @FarzaTV", "hi my name is farza / i just wanted to introduce myself", with an embedded vertical video that plays (captions change: "making stuff on", "learn new things.", a buildspace shot). Right: the guest in close-up. The layout does not change through 66.7, where a cut ends it; only the embedded video advances. | 75 | MEASURED: `q2q5.png` t=52, 59, 66 |
| 6 | **6 hard cuts** (cuts.txt lists only 2; see the method finding). Order: wide two-shot (to 2:03.0), guest single (2:03.0-2:14.8), wide (2:14.8-2:25.6), guest single (2:25.6-2:28.4), wide (2:28.4-2:36.4), host single (2:36.4-2:46.7), wide (2:46.7 to 3:01.5). | 75 | MEASURED: `scan.sh` at 0.08, RMSE check, `q6b.png` |
| 7 | Cap: sage-green baseball cap with a small white embroidered line-art emblem, a frog face (eyes on top, smile), clearer in a later close-up. Eyewear: round, thin metal wire-frame clear glasses. Under the denim button-down (chambray) shirt: a white crew-neck T-shirt. | 70 | MEASURED: `q7q8.png` crop t=262/264; `q21.png` t=2498 shows the frog clearly |
| 8 | **The guest** (same face, beard and round wire glasses), recorded earlier on a laptop webcam. Differences: no cap (dark hair visible, swept), a dark jacket or top, an orange-and-white office background, and a selfie webcam look. The screen is Xcode with a "Clicky" debug console. | 80 | MEASURED: `q7q8.png` t=368/370 |
| 9 | The post is by "Aaron Ng @localghost · 24m" and at first says "Looks like Google is about to drop something?", over a photo of a "Gemini Audio" storefront. The guest right-clicks the text, a context menu opens, he picks Inspect, and Chrome DevTools (Elements panel) opens on the right with the span highlighted. Afterwards the post reads "I built this thing called Clicky. It's an AI teacher that lives as a buddy next to your cursor. It can see your screen, talk to you, and even point at stuff… I've been using it the past few days to learn Davinci Resolve, 10/10." The author name and handle stay "Aaron Ng @localghost". | 85 | MEASURED: `q9.png` t=520-528.5 |
| 10 | Doc insert: **2** boxes, top-left = host, top-right = guest. Video-site insert: **1** box, top-right = guest. | 75 | MEASURED: `q10q11.png` t=645, 810; census tiles #069-#073 |
| 11 | Title: "introducing screen-aware dictation." Likes: **472**. Below: "19K views 2mo ago" (channel heyclicky, 872 subscribers). On the table to the presenter's right (screen-right): a **red insulated water bottle**. | 90 | MEASURED: `q10q11.png` t=810 |
| 12 | **Silence, about 1.2 s** (16:46.0-16:47.2) at -67 to -89 dBFS. That is digital zero, with no room tone, so it is an audio edit, not a natural pause. There is no picture cut there (no scene change above 0.06). The guest holds one hand raised in front of his face, fingers curled in a "C" or pinch shape, then moves it as he resumes "I want to talk about something". | 75 | MEASURED: `rms.py 1002 8`; `scan.sh 1000 12`; `q12q14q20.png` t=1006.0-1007.1 |
| 13 | Title: "Mars Perseverance: Rover Landing". Chips: "Ages: 7-12", "Space", "30 Mins". Teacher label: "Teacher Ashton". First button: "Book Class for **Thu, Feb 25** - 10:…" (the time is cut off by a webcam overlay). | 90 | MEASURED: `q13q16.png` t=1095 |
| 14 | Shot 19:16.82-19:17.70 (0.88 s): **the host**, single, looking screen-right toward the guest with an amused closed-mouth smile. He is **not** speaking; the guest is mid-sentence (ASR 19:13-19:18 is the guest's line). Next shot: the guest in close-up, laughing with eyes nearly shut, one hand (with a ring) raised to the side of his head or cap. | 80 | MEASURED: `scan.sh 1150 15`; `q12q14q20.png` t=1157.25, 1158.0 |
| 15 | The voice belongs to the young man **in the reel** (account "kael_newman"; caption "Two months ago, I created this page to block my long-distance girlfriend and post my weight loss journey"). It is neither person at the table. At about 23:06 the reel is **paused**: a cursor click, a play-triangle icon appears over the video, and the guest starts talking ("first of all this is a random video…"). | 85 | MEASURED: `q15.png` t=1381.5-1386.8 |
| 16 | Handle: **_heyclicky** (display name "heyclicky"). Counts: **48 posts, 35.4K followers, 5 following**. Bio: "your friendly neighborhood cursor". Link: **heyclicky.com/ig** (plus a Threads "_heyclicky" chip). | 92 | MEASURED: `q13q16.png` t=1488 |
| 17 | 29:47-29:56 (shot 29:47.3-29:55.8): **guest**, framed right of center, looking **screen-left**. 30:01-30:13: **host**, framed left of center, looking **screen-right**. This matches the wide shot (host seated left, guest right): each looks across toward the other, with lead room on the gaze side. The 180-degree line is kept. | 80 | MEASURED: `scan.sh 1780 40`; `q17.png` t=1791, 1807, 1798 |
| 18 | Background: AC/DC "Back in Black", played through Spotify in the demo. Just before it, the guest's request ends around 35:51 and there is about 2.5 s of quiet (floor about 20 dB lower) while the assistant works. The assistant then replies "Rock on, it's playing Back in Black now". The track is faint from about 35:53.5 (Spotify's progress reads 0:01 at 35:54.6) and jumps loud at about 35:57-35:59. After the "turn it down" request and the "lowering Spotify to 50" reply (about 36:01-36:04), the music floor drops: the 3-8 kHz floor goes from +2..+15 to about -1..-28. The music continues quietly under the next request. | 70 | MEASURED: `band.py 2148 28`, `floor.py`, `spec.png` middle panel, `q19.png` progress bar |
| 19 | **No.** The line is the assistant's synthetic voice. The man in the bubble (the guest, no cap, patterned jacket, earbud in) smiles broadly with his lips closed and his fingers interlaced under his chin, resting on his clasped hands. The bubble sits upper-left over the Spotify window, not lower-right. | 80 | MEASURED: `q19.png` t=2154.6, 2155.8 |
| 20 | The guest raises a flat palm horizontally to his forehead, like a visor or salute, while saying roughly "keep the story moving" (ASR 37:31-37:36). The edit is a **hard cut on action** at 37:34.75 from the wide shot to his close-up. The gesture continues across the cut, with the hand still at the forehead. No dissolve or zoom. | 75 | MEASURED: `scan.sh 2248 12`; `q12q14q20.png` t=2254.5, 2255.0 |
| 21 | A wristwatch on his **right wrist** (screen-left as he faces camera): round white or cream dial, silver case, brown leather strap. Other hand (left): a plain silver band ring on the ring finger. | 85 | MEASURED: `q21.png` t=2490 |
| 22 | **Yes.** It is the same video-script doc ("When talking to our users, we found many of them want to use agents more!…"), first shown at about **10:38-11:50**. Along its bottom edge is a dark screen-recorder control bar reading: "×", "Recover 2 unfinished recordings", "Display", "Window", "Area", "Device", "No camera", "MacBook Pro…" (mic), "Record system audio", and a settings or gear menu. INFERRED: this is a screen-recording app's bar, possibly Screen Studio (mentioned at 40:53), over the FreeWrite document. | 85 / 50 for the app name | MEASURED: `q22.png` t=2706 vs `q10q11.png` t=645 |
| 23 | After a cut to the wide shot at 46:55.27, both men reach across. Their raised hands meet in a slapping clasp (about 46:56.0), turn into a handshake (46:56.6), and grip and release (46:57.2). Both pull back closed fists (46:57.8), and then the guest flings his hand open (an "explosion" or "boom" gesture) with his tongue out while the host holds a fist or thumb up (46:58.3). Transition: an **orange credits panel wipes in from the right** starting at 46:58.375. The underlying frame does not move; the credits text is motion-blurred in the panel. It covers the frame by about 46:59.25, about 0.9 s, strongly eased out: the edge moves 54 px per frame at first and about 1 px per frame at the end (320 px scale). | 80 | MEASURED: `q23.png` t=2814.8-2819.5; `wipe.py` |
| 24 | The last words are the guest's "Thanks, A…" at about 46:55; the ASR heard "Thanks, Ahmed", which is probably "Aaron" (INFERRED). Then an **outro music sting** runs about 46:55.5-47:03 (tonal stepped pattern and clicks, like the title music), fades out about 47:03-47:04.4, and leaves **exact digital silence** (-120 dB, every sample zero) from 47:04.5 to the end at 47:08.4. **Nothing is said in the final 3 seconds.** The ASR line "[47:07] Thank you." is a whisper hallucination on silence. | 85 | MEASURED: `band.py 2808 20.4` (from 2824.5 on: -120/-120); `spec.png` bottom panel |

## What this run shows about the question "can the agent watch a video like a human?"

- **Spatial and semantic detail is near-human when the reads are targeted** (MEASURED, this run). All on-screen text, counts, handles, clothing, jewelry, framing, eyelines and table objects were recovered with 17 targeted reads. The stacked-frame trick gives native resolution at half the read cost.
- **Structure tools fail silently.** The 0.3 scene threshold undercounted cuts by 3x in a sampled minute (MEASURED). A human counts those cuts effortlessly.
- **Non-speech audio is answerable only by measurement.** Music onset, ducking, edit silences and the end-of-file silence came from level and band statistics, not from hearing. I can say "a music bed with stepped tones" but cannot name an unknown tune unless the screen shows it (here Spotify did). The ASR also hallucinated a "Thank you" on silence (MEASURED). That is a trap: a transcript-only watcher would get Q24 wrong.
- **Motion questions** (the handshake sequence, the wipe direction and easing) need dense frames or a per-frame numeric probe. A 20 s coarse sweep would miss them.
- **Speaker attribution** without diarization relied on burned-in captions and open-mouth frames (Q2, Q14, Q19). That is weaker than human hearing (INFERRED).
