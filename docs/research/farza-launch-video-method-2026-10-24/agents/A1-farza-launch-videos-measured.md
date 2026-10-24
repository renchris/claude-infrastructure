# A1: Farza's launch videos, measured (2026-10-24)

<!-- markdownlint-configure-file { "MD013": false } -->

Slot A1. I watched six of Farza's launch/demo videos frame by frame and measured them. I did not work from memory. All engagement counts were **read on 2026-10-24** (about 13:30 local) from `api.fxtwitter.com` (X) and `yt-dlp` (YouTube). Scratch files, frames and montages are in `/tmp/farza-A1-farza-launch-videos-measured/`.

Labels: **MEASURED** means I ran or read it in this run, and the command is named. **QUOTED** means his words, with [mm:ss] from `/tmp/farza-2026-10-24/transcript.txt` or a URL. **DOCUMENTED** means a source states it. **INFERRED** means my reasoning. "Prior probe E1" is `docs/research/video-understanding-human-parity-2026-10-23/agents/E1-exam-key.md`.

## How each number was made (MEASURED, all runs this session)

| Measure | Command / method |
| --- | --- |
| Post text, date, counts | `cc-read-twitter <url>` and `curl api.fxtwitter.com/<user>/status/<id>` (fields likes/retweets/replies/views/bookmarks/quotes). Timelines came from `api.fxtwitter.com/2/profile/<user>/statuses` paged by cursor (`timeline.py`). |
| Media | The 1080p variant URL that `cc-read-twitter` printed, fetched with `curl -L`. The YouTube copy came via `uvx yt-dlp@latest -f 137+bestaudio`. |
| Length, resolution, fps | `ffprobe -show_entries stream=width,height,r_frame_rate,duration` |
| Hard cuts | The SKILL.md luma one-liner: 96x54 gray, mean abs diff >= 20, local max over +-2 frames (`cuts.py`). I also report a variant that de-duplicates cuts closer than 0.3 s. |
| First 10 s | 20 frames at 0.05 + 0.5k s (input-side `-ss`), montaged and read (`first10.sh`). |
| Face/screen ratio | 1 frame/s (`fps=1`, so the tile labelled k is the frame at about k+0.5 s), montaged and classified by eye (`sheet1fps.sh`). v6 is fast-cut, so for it I took one frame at each shot's midpoint and weighted by shot length, as SKILL.md prescribes. |
| ASR | `whisper-cli` large-v3-turbo `-osrt -ojf`, seeded with on-screen spellings. Word times come from the `-ojf` tokens. |
| Music | Per-2 s RMS of mid (L+R)/2 and side (L-R)/2 in dBFS (`audio.py`). A side channel near -180 dB means exact dual-mono. A side channel of about -35 to -50 dB under mono speech indicates a stereo bed (music or stereo ambience). |

## Inventory

| # | Video | URL | Posted (UTC / PT) | Length (ffprobe) | Frame | Views | Likes | Reposts | Quotes | Bookmarks | Replies |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| v1 | Clicky launch | https://x.com/FarzaTV/status/2041314633978659092 | 2026-04-07 00:38 / Apr 6 17:38 PDT | 99.85 s | 1660x1080, horizontal (1.54:1), 60 fps | 3,000,762 | 15,733 | 1,171 | 583 | 12,647 | 1,302 |
| v2 | "No hands" GPT-Realtime demo | https://x.com/FarzaTV/status/2060865350036750847 | 2026-05-30 23:26 / 16:26 PDT | 104.07 s | 1660x1080, horizontal, 60 fps | 3,826,653 | 14,116 | 829 | 674 | 8,299 | 927 |
| v3 | "We built an AI that can draw on your screen" | https://x.com/FarzaTV/status/2066983088035656086 | 2026-06-16 20:35 / 13:35 PDT | 140.37 s | 1920x1080 (source 3840x2160 per fxtwitter), 29.97 fps | 629,293 | 5,211 | 318 | 141 | 2,725 | 405 |
| v4 | Screen-aware dictation (X) | https://x.com/FarzaTV/status/2077130366230639022 | 2026-07-14 20:37 / 13:37 PDT | 120.05 s | 1920x1080 (source 3840x2160), 29.97 fps | 2,945,014 | 10,692 | 469 | 307 | 8,748 | 552 |
| v4-YT | "introducing screen-aware dictation." (heyclicky YouTube) | https://www.youtube.com/watch?v=km54y7Xd_7g | upload_date 20260714 | 120 s (yt-dlp), 120.07 s (ffprobe) | 3840x2160 max | 21,012 | 489 | n/a | n/a | n/a | 58 comments |
| v5 | "hi my name is farza / i just wanted to introduce myself" | https://x.com/FarzaTV/status/2097407173274075223 | 2026-09-08 19:30 / 12:30 PDT | 109.48 s | 1080x1920, **vertical** (source 2160x3840), 23.976 fps | 64,892 | 1,624 | 47 | 13 | 342 | 92 |
| v6 | "i went viral" (@heyclicky) | https://x.com/heyclicky/status/2049703156779733318 | 2026-04-30 04:11 / Apr 29 21:11 PDT | 44.94 s | 1080x1920, **vertical**, 29.97 fps | 73,093 | 797 | 12 | 11 | 172 | 42 |

All values are MEASURED (fxtwitter JSON / yt-dlp `--dump-json`, read 2026-10-24). The interview's lower-third in the prior probe E1 showed the launch post at "1.7K" reposts. X's UI number appears to be retweets plus quotes: 1,171 + 583 = 1,754. That is INFERRED.

**v4 and v4-YT are the same cut.** MEASURED: mean abs luma difference between the X and YouTube frames at 30 s was 2.8 and at 75 s was 1.6, far below the cut threshold of 20. The YouTube description repeats the X post copy almost word for word (yt-dlp `description`). He quotes the pair himself: "this video, I think it did like 3 million views on Twitter, 20,000 on YouTube" [12:16]. MEASURED: 2.95M on X and 21.0K on YouTube.

### Post copy, verbatim (MEASURED, fxtwitter `text`)

- **v1:** "I built this thing called Clicky. / It's an AI teacher that lives as a buddy next to your cursor. / It can see your screen, talk to you, and even point at stuff, kinda like having a real teacher next to you. / I've been using it the past few days to learn Davinci Resolve, 10/10." (276 chars, 54 words). Self-reply 1 came 4 h 42 m later: "You can give it a try below. https://clicky.so Few notes: 1. Uses Claude + Eleven Labs (very fast!!) 2. Screenshot only taken when you press hotkey. 3. High chance I run of credits lol." Self-reply 2 followed 10 min after that: "Also, this will work on anything. ..."
- **v2:** "Watch me control my computer with just my voice. This is the future of operating systems. / No hands. / GPT-Realtime 2.0 is very, very underrated. / Demo:" (151 chars). Self-reply came 6 h 54 m later: "This is real, and shipped. Download below + try for free. It's really early, but, really magical. Enjoy. P.S: Follow the journey @heyclicky http://heyclicky.com/try". Further replies were "Note 1: ... experimental ... Note 2: It only plays AC/DC on Spotify right now. I'll fix tomorrow I'm going to sleep lol." and, 2 days later, "Okay I fixed it ... No more only AC/DC lol."
- **v3:** "We built an AI that can draw on your screen. / It's a true personal tutor. / Using Claude Opus we're able to draw polygons, point with pixel perfect accuracy, and walk users through complex steps directly on their screen. / Here's me learning Pythagorean Theorem + FL Studio. / Demo:" (279 chars). Self-reply came 7 h 46 m later: "P.S: Yes, this is shipped! Give it a try for free. https://www.heyclicky.com/try".
- **v4:** "Today we're shipping screen-aware dictation. / First, we built a speedy speech-to-text (very fast, ~450ms). / But, many products do this! / So we went further. Now dictate using your screen as context. In Claude Code, it writes the prompt. In G-Mail, it replies in your voice. / Demo:" (280 chars). Self-reply came 5 h 40 m later: "This is real + shipped btw. It's free to try. FN + CNTRL for simple dictation (fast). CNTRL + Option for screen-aware (slow). Enjoy: https://www.heyclicky.com/try".
- **v5:** "hi my name is farza / i just wanted to introduce myself" (54 chars, all lowercase, no link, no reply).
- **v6:** "i went viral" (12 chars, lowercase, no link).

## Per-video measurements

### v1: Clicky launch (Apr 6/7 2026, 3.0M views)

- **Hook, first words (MEASURED, whisper tokens):** "Hey, everyone. So this is Clicky." (0.08-2.36 s), then "Clicky is this little blue guy that follows your cursor ... it's basically an AI teacher that can teach you anything." (2.62-9.41 s) and "So check this out." (9.61-10.36 s).
- **First on-screen text:** none added. The frame is UI only: Xcode, `BuddyDictationManager` and `isMicrophoneButtonSessionBusy` code, and the menu bar.
- **First 10 s, shot by shot (MEASURED, `f10-v1-launch-montage.jpg`).** There is one continuous screen recording with a rounded-square webcam bubble bottom-right, and no hard cut.
  - 0.0-2.2 s: full macOS desktop with Xcode, plus the bubble. He has his hand on his chin at 0.0 and makes a peace sign at 0.5.
  - About 2.2 s: an animated zoom-in onto the blue triangle cursor-buddy, beside the mouse pointer.
  - 2.5-7.0 s: held zoom. The pointer and the buddy move around an empty panel.
  - About 7.0 s: zoom out (motion-blurred frame).
  - 7.5-10 s: full desktop again.
  - INFERRED: the zoom and the bubble are Screen Studio auto-zoom. He names Screen Studio for his on-computer demos [40:53], and he says "I purposely zoom in right here" [09:24].
- **Cuts (MEASURED):** 3 hard cuts, 1.8/min, median shot 27.5 s, 0 in the first 10 s. The cut at 43.03 s is a jump cut from the Edit page to the Color page (dead time removed). The cuts at 82.87-84.62 s bracket a 1.75 s full-screen insert of the graded clip, the "result" reveal. The Xcode-to-DaVinci switch at about 10.5 s and the zooms register only as soft diffs (10-20) at 11.17, 22.15 and 69.15 s.
- **Captions:** none.
- **Music:** none. MEASURED: the side channel is -180 dB for the whole file, so it is exact dual-mono. During the 70-72 s wait for Clicky's answer the mid level falls to -61 dB, so no bed runs under the pause. Whole-file mid is -32.1 dBFS, 14-16 dB quieter than v3-v6. INFERRED: a raw, un-normalised take.
- **Face vs screen (MEASURED, 1 fps, n=100):** screen+face PiP 100%.
- **Structure (MEASURED, whisper + 1 fps sheet):**
  - 0-10 s: what it is (Xcode).
  - 10.4 s: "Let's go to DaVinci". The problem is personal: "a video editing program that I've been procrastinating learning ... I don't want to watch a one hour YouTube video".
  - 22 s: he drags in a clip.
  - About 27 s: first ask, "How can I make it look more cinematic?" Clicky points (about 40 s).
  - 48 s: LUT question. 67 s: "Which one should I pick?" 75 s: Clicky recommends a LUT.
  - 82.9-84.6 s: full-screen graded result (reveal).
  - 86.8 s: self-deprecating aside, "I'm not sure why I recommended the Sony LUT for a Blackmagic thing, but ignoring that, that's clicky."
  - 92.7 s: generalisation, "It can teach you anything in any program".
  - **CTA at 96.6-99.5 s (last 3%):** "I'll put the link below and give it a shot. Learn something. Learn by doing." The link itself is in a self-reply 4 h 42 m later.
- **Production time (MEASURED + INFERRED):** the macOS menu-bar clock in the recording reads "Mon Apr 6 5:24 PM" at 42.9 s and "5:25 PM" at 98.5 s. Prior probe E1 recorded "5:23 PM" on the opening Xcode screen. The post went out at 17:38 PDT. If the Mac clock is Pacific (INFERRED), the 100 s take was posted about 13 minutes after it ended.

### v2: "No hands" (May 30 2026, 3.83M views)

- **Hook, first words (MEASURED):** "Alright, check this out, no hands, ready?" (0.20-2.25 s), then "Hey, Clicky, can you please open up Spotify and play AC/DC for me?" (2.54-6.62 s).
- **First on-screen text:** none added (UI only: Xcode with realtime logs, redwood wallpaper).
- **First 10 s (MEASURED):** one continuous shot of the full desktop with the webcam bubble mid-left. He raises both open hands to the camera at 1.5-2.0 s on "no hands", then talks with his hands lowered. At 10.08 s the Spotify window opens.
- **Cuts (MEASURED):** 5 luma breaks (2.9/min raw; 4 after de-duplication), 0 in the first 10 s. All 5 coincide with app windows opening on screen: Spotify at 10.08/10.13 s, the browser and Stripe at 30.17/31.02 s, Reminders at 91.13 s. INFERRED: these are state changes inside one take, not edits. The webcam bubble runs continuously in the 1 fps sheet. This matches his claim "there's not a single cut in this video" [37:02].
- **Captions:** none.
- **Music:** MEASURED. Side is -82 to -102 dB in 0-8 s (no bed). From about 10 s, when "Back in Black" starts playing from Spotify on screen, side rises to -50 dB and then -37 dB (16-20 s). After "could you turn it down ... 50%" (about 16-23 s) it drops to about -55 dB and stays there to the end. INFERRED: the only music is diegetic, the demo's own Spotify playback. The host describes the same beat: "then you lower the music so that you can continue to talk over it" [37:22].
- **Face vs screen (MEASURED, n=104):** screen+face PiP 100%.
- **Structure (MEASURED):**
  - 0-2 s: hook ("no hands").
  - 2.5-23 s: Spotify play, then volume down.
  - 24-37 s: Stripe dashboard. Humour: "Oh man, $140 in a day is not very good."
  - 37-60 s: Google Ads integration, then a background agent to "double this revenue number".
  - 60-74 s: calendar ("an event at Y Combinator ... Who's speaking?" "Paul Graham and Jessica Livingston").
  - 74-91 s: Saturday reminder, then Reminders opens.
  - 92-104 s: "Twitter's actually watching you right now ... say hi", Clicky: "Hi Twitter", then "Bye guys".
  - **No CTA in the video.** The CTA and link come in a self-reply 6 h 54 m later.

### v3: "We built an AI that can draw on your screen" (Jun 16 2026, 629K views)

- **Hook, first words (MEASURED):** "Hey, so we built a system that can draw directly on your screen, it can draw polygons, arrows, curved lines, and a lot more." (0.23-7.80 s), then "It can teach you literally anything, no matter what app you're in." (8.16-10.62 s).
- **First on-screen text:** the burned caption "so we built a system that can draw", from about 1.0 s.
- **First 10 s (MEASURED):**
  - 0-3.50 s: medium face shot in front of a blackboard with a chalk drawing of a screen. He walks into frame from the left (0.0-1.0 s).
  - 3.50-6.64 s: over-the-shoulder close shot of his hand chalking a triangle, an arrow and a curve. Caption: "It can draw polygons, arrows, curved".
  - 6.64-10 s: medium face shot. Captions: "lines, and a lot more." and "It can teach you literally anything no".
- **Cuts (MEASURED):** 31, 13.3/min, median shot 3.42 s, max 16.4 s, 2 in the first 10 s. There are also 29 soft transitions (10-20) concentrated at 58-86 s.
- **Captions:** yes. Burned-in phrase chunks of about 3-6 words, small white sans, bottom-centre at about 80% of frame height, running to the end ("Bye." at 136 s).
- **Music:** yes (INFERRED from MEASURED side). Side is -50 dB at 0-8 s, -38 dB from about 10 s, dips to about -56 dB at 50-68 s, is about -46 dB at 70-106 s and back to -38 dB at 108-135 s. At 136-140 s mid swells to -8 dB and side to -24 dB under the end card, where whisper transcribes sung lyrics.
- **Face vs screen (MEASURED, n=140):** face only 23.6% (33), full-screen recording 35.7% (50), face plus laptop screen in the same camera shot 38.6% (54), end cards 2.1% (3).
- **Structure (MEASURED):**
  - 0-10.6 s: what it is.
  - 10.9-60 s: demo 1. Pythagorean theorem drawn over a Khan Academy video; payoff at 53-57 s, "just like that, it drew directly on a YouTube video".
  - 60.3 s: escalation turn, "Alright, so that's kind of cute, but what if I wanted to do something a little bit more complicated?" A personal problem follows: "40 minutes long ... going back and forth between the video, program".
  - 79-114 s: demo 2, FL Studio first beat.
  - 114-126 s: payoff, "We made our first beat literally in like 10 seconds".
  - 126.4 s: thesis, "a brand new interface for you to actually talk to your computer".
  - **CTA at 130.2-135.6 s:** "Check it out. It's live. It works in literally any program. Try it out. Try to break it. I dare you. And enjoy."
  - End cards "try it for free" (137 s) and "heyclicky" (138-139 s).
- **This is the "drawing video" he dissects as Twitter-optimised** [33:39-34:17]. INFERRED from his description "we built a system that can draw directly on your screen it can draw polygons, arrows" [33:44] matching v3's first sentence word for word.

### v4: Screen-aware dictation (Jul 14 2026, 2.95M X + 21.0K YouTube)

- **Hook, first words (MEASURED):** "Hey, so today we're adding dictation to HeyClicky." (0.04-2.94 s), then "All you gotta do is press and hold Fn plus control, start talking, and whatever you're saying will stream in as text into whatever text box your cursor is on." (2.97-10.64 s).
- **First on-screen text:** the caption "Hey, so today we're adding", from 0.5 s.
- **First 10 s (MEASURED):**
  - 0-4.04 s: medium face shot at an outdoor table, laptop in front, red bottle at right (golden-hour light).
  - 4.04-6.01 s: product close-up of two fingers pressing fn+control on the MacBook keyboard. Caption: "hold fn + control,".
  - 6.01-10 s: back to the face shot. Captions: "whatever you're saying," and "we'll stream in as text into".
- **Cuts (MEASURED):** 37 (18.5/min; 36 de-duplicated), median shot 2.2 s, max 10.2 s, 2 in the first 10 s.
- **Captions:** yes. Same style as v3: 3-6 word phrase chunks, white, bottom-centre at about 81% of height, overlaid on the full-screen recordings too.
- **Music:** yes (INFERRED from MEASURED side). Side is -53 to -56 dB at 0-8 s, then about -38 dB from 8-10 s. It dips to -47/-55 dB at 56-66 s and returns to about -30/-40 dB to the end.
- **Face vs screen (MEASURED, n=120):** face 54.2% (65), full-screen recording 41.7% (50), keyboard close-up 2.5% (3), end card 1.7% (2). No PiP.
- **Structure (MEASURED):**
  - 0-11 s: what (basic dictation, the keys).
  - 11-21 s: Apple Notes demo.
  - **21.2-30 s, the turn he describes in the interview:** "So that's pretty cool, and honestly, many products already do this exact thing today. But here's the thing, when I'm writing, I often don't really know what I even want to say."
  - About 31-36 s: **reveal**, "So check this out, we're shipping screen-aware dictation. It's pretty cool, I've never seen anything like it before". From about 31 s the light is visibly bluer and darker than at 0-30 s.
  - 36-66 s: Gmail reply demo and why it is magical.
  - 67-80 s: Claude Code terminal ("I'm non-technical").
  - 80-99 s: skills, then the YC skill writing a Google Slides opener.
  - 99-111 s: user use-cases (social proof).
  - **CTA at 111.9-118 s:** "So that's it. This is in production right now. It's a little bit buggy, but we're making it better every single day. Let us know what you think, and enjoy."
  - End card "clicky" then "heyclicky" (118-120 s).
- He says the whole thing was scripted: "this whole video scripted. Every line that I'm saying, I wrote like three days before" [14:00-14:05].

### v5: "hi my name is farza" (Sep 8 2026, 64.9K views)

- **Hook, first words (MEASURED):** "I feel like a lot of you guys are new here and I just want to introduce myself" (0.04-2.88 s), then "my name is Farza and I am 30 years old" (2.88-5.78 s).
- **First on-screen text:** the caption "I feel" at 0.0 s.
- **First 10 s (MEASURED):**
  - 0-5.96 s: vertical handheld face shot outdoors (denim shirt, clip-on transmitter visible on the chest at 1.0-3.0 s). At 0.0 s he is leaning into frame.
  - 5.96-6.97 s: archival 16:9 clip letterboxed in black, of a teenage Farza at a computer in a blue room. Caption: "so I started".
  - 6.97-8.22 s: archival clip of friends wrestling. Captions: "making stuff on", "the internet", "back in 2008".
  - 8.22-10 s: archival vlog of a teen in a green beanie. Captions: "back in 2008", "when I was 13,". A "FarzaTV" title overlay appears at about 9.5 s.
- **Cuts (MEASURED):** raw 83 (45.5/min), median shot 1.08 s; 74 after de-duplication; 3 in the first 10 s. **Caveat (MEASURED):** the 0.17 s-spaced cluster at 54.18-55.35 s is a low-frame-rate archival handheld clip panning, not edits (frames in `k5-sheet.jpg`). The true edit count is therefore lower than raw, by an unmeasured amount.
- **Captions:** yes. 1-3 word chunks, small bold white, at about 69% of height over the face shot and directly under the letterboxed archival clips.
- **Music:** yes (INFERRED from MEASURED side). Side holds -34 to -43 dB for the whole runtime and falls to -56 dB at 106 s.
- **Face vs screen (MEASURED, n=109):** present-day face 32.1% (35), screen (web pages, tweets, Xcode, app, comments, Stripe) 20.2% (22), archival photos and b-roll 47.7% (52).
- **Structure (MEASURED from captions + second whisper pass):** a chronological origin story keyed to his age at each step:
  - 0-6 s: hello and age 30.
  - 6-15 s: 2008, age 13, YouTube.
  - About 15 s: "$100,000 a year by the time I was 15".
  - About 16-22 s: 2011, Xbox 360 discs.
  - About 24-33 s: 2014, age 18, learns to code; mood.gg reaches "almost three million people".
  - About 42-52 s: 2016, deep learning, a self-driving model.
  - About 53-67 s: 2019, Zip School, YC, 150,000 students.
  - About 68-87 s: 2021, Buildspace, "$10 million from A16Z".
  - About 88-97 s: "Now I'm 30 ... HeyClicky ... a simpler interface for AI models".
  - About 98-103 s: "millions of people check out our product online and we just recently passed a thousand customers", over a Stripe chart.
  - **Closing at about 104-107 s:** "So yeah, that's me. Thanks for following and I'm just gonna get back to work". He walks off at 108 s. **No product CTA and no link.**
- **ASR trap (MEASURED):** the first whisper pass compressed this file's timestamps, ending all speech at 49.5 s of a 109.5 s video under the constant music bed. Re-transcribing from 45 s recovered the speech running to about 109 s. Word times in the first 10 s matched the burned captions, so the hook timings above stand.

### v6: "i went viral" (@heyclicky, Apr 30 2026, 73.1K views)

- **Hook, first words (MEASURED):** "Today we crossed over 5 million views on this thing we're building called Clicky" (0.12-3.56 s), then "Which is crazy and mind-blowing considering that I thought it was actually a pretty meh idea" (5.08-9.68 s). At 3.6-5.0 s whisper heard "Here's Interstellar Vibes". INFERRED: this is in-demo audio over the Logic Pro screen, where the Clicky pointer label reads "Interstellar vibes".
- **First on-screen text:** the caption "Today we crossed", at 0.0 s.
- **First 10 s (MEASURED, montage + midpoint sheet):**
  - 0-1.27 s: wide shot, sitting under a tree with a laptop. Captions: "Today we crossed", "over 5 million".
  - 1.27-2.67 s: punch-ins to medium. Caption: "views on this".
  - 2.67-3.80 s: 7 screenshots at about 0.1 s each: the launch tweet, the GitHub README "Hi, this is Clicky", the "You can give ... clicky.so" reply, the farzaa/clicky repo, and clicky.so "Hi, I'm Clicky". Caption: "called".
  - 3.80-about 6.5 s: screen recordings of the Logic Pro organ library with the Clicky pointer "Interstellar vibes", then the DaVinci Color page. Captions: "Which is crazy" and "and mind-blowing".
  - About 7.0-8.88 s: double exposure of him holding his head, overlaid with a Clicky pointer reading "Make a cut here". Captions: "considering that", "I thought it was", "actually a pretty".
  - 8.88-9.71 s: medium face shot. Caption: "meh idea."
- **Cuts (MEASURED):** 39 (52.1/min; 32 de-duplicated), median shot 0.73 s, max 7.7 s (the closing shot), **13 in the first 10 s** (9 de-duplicated). The detector also logged 19 soft transitions, including whip moves.
- **Captions:** yes. 2-3 word chunks, larger white sans with shadow, at about 63% of height. They move to about 21% (top) when the screen recording's content sits low (5.0-5.5 s).
- **Music:** yes (INFERRED from MEASURED side). Side holds -34 to -49 dB throughout.
- **Face vs screen (MEASURED, duration-weighted over 40 shot midpoints):** face 41.7%, screen 50.7%, face plus screen double exposure 7.2%, transition 0.4%.
- **Structure (MEASURED):**
  - 0-3.6 s: what's going on (5M views).
  - 5-13.4 s: story ("pretty meh idea ... so many people checked it out, gave a lot of feedback, and inspired me").
  - 13.4-16.1 s: "So, we've been building, and I want to show you some new stuff".
  - 16.1-36.5 s: three background-agent demos (clean the Downloads folder; build a retro Mac app that controls Spotify; text "my friend Nilesh that he's handsome"). Each lands on a terse "On it" / "Done" / "And it's done" beat.
  - **Closing at 36.5-44.9 s:** "So, that's it, enjoy, go make Clicky do things. I'm gonna chill under this tree for now though". **No link.**

## Cross-video table (all MEASURED except where marked)

| | v1 launch | v2 no-hands | v3 draw | v4 dictation | v5 hi-my-name | v6 went-viral |
| --- | --- | --- | --- | --- | --- | --- |
| Length | 99.9 s | 104.1 s | 140.4 s | 120.1 s | 109.5 s | 44.9 s |
| Aspect | 1.54:1 horiz | 1.54:1 horiz | 16:9 | 16:9 | 9:16 | 9:16 |
| Views (X) | 3.00M | 3.83M | 0.63M | 2.95M | 0.065M | 0.073M |
| Likes / views | 0.52% | 0.37% | 0.83% | 0.36% | 2.50% | 1.09% |
| Bookmarks / likes | 0.80 | 0.59 | 0.52 | 0.82 | 0.21 | 0.22 |
| Post copy length | 276 ch | 151 ch | 279 ch | 280 ch | 54 ch | 12 ch |
| First words land "what it is" by | 2.4 s ("this is Clicky") | 2.3 s ("no hands") | 3.5 s | 2.9 s | 5.8 s (who he is) | 3.6 s |
| First-10 s framing | screen+PiP, zoom at 2.2 s | screen+PiP | face then hands then face | face then keyboard then face | face then archival | face, screenshots, screen, overlay |
| Hard cuts / min (raw) | 1.8 | 2.9 (app switches) | 13.3 | 18.5 | 45.5 (overcounts archival) | 52.1 |
| Median shot | 27.5 s | 11.5 s | 3.4 s | 2.2 s | 1.1 s | 0.7 s |
| Cuts in first 10 s | 0 | 0 | 2 | 2 | 3 | 13 |
| Burned captions | no | no | phrase, bottom 80% | phrase, bottom 81% | 1-3 words, 69% | 2-3 words, 63%, moves |
| Music bed | none (dual-mono) | diegetic only (Spotify) | yes, swells at end | yes | yes | yes |
| Face visible (face + both) | 100% (PiP) | 100% (PiP) | 62% | 54% | 32% (+ archival) | 49% |
| Demo starts at | 10.4 s (10%) | 2.5 s (2%) | 10.9 s (8%) | 11 s (9%); reveal 31 s (26%) | no demo | 16.1 s (36%) |
| Spoken CTA | "link below ... give it a shot" at 97% | none | "Try it out. Try to break it. I dare you." at 93% | "in production ... let us know what you think" at 93% | "Thanks for following" | "go make Clicky do things" |
| Link in post | no (reply +4h42m) | no (reply +6h54m) | no (reply +7h46m) | no (reply +5h40m) | none | none |
| End card | none | none | "try it for free" / "heyclicky" | "clicky" / "heyclicky" | none (walk-off) | none |

## Patterns that hold across them

1. **The first sentence names the thing; nothing comes before it.** In all six, the first spoken sentence starts within 0.25 s, with no title card, logo sting or music intro. In five of six (all except v5, the introduce-myself video), the product or capability is named by 2.3-3.6 s. The openers are near-formulaic: "Hey, everyone. So this is Clicky" / "Hey, so we built a system that..." / "Hey, so today we're adding..." (MEASURED).
2. **Two registers, matched to aspect ratio and reach.** (MEASURED, with INFERRED interpretation.)
   - The four horizontal X demos (v1-v4) reached 0.63-3.83M views, with bookmarks/likes of 0.52-0.82. INFERRED: people save them as tools.
   - The two vertical, lowercase, personal-story posts (v5, v6) reached about 65-73K views on X, with high like rates (1.1-2.5%) and low bookmarks (0.21-0.22). The vertical ones are cut 2.5-4x faster (median shot 0.7-1.1 s vs 2.2-27.5 s).
3. **Raw and edited are both used, for the same register.** The two biggest X hits are effectively raw Screen Studio takes: v1 has 3 cuts and v2 has none, with no captions, no music and a webcam bubble the whole time. v4, nearly as big, is fully produced: 37 cuts, captions, a music bed, a keyboard insert and an outdoor set. Production level did not predict X views in this sample of four; this is a sample-size caveat, not a finding.
4. **Every demo has a turn.**
   - v1: the personal problem "I don't want to watch a one hour YouTube video", then a reveal insert at 83 s.
   - v3: "that's kind of cute, but what if..." at 60 s.
   - v4: "many products already do this ... But here's the thing" at 21-30 s, then the reveal at 31 s.
   - v2's turns are jokes: "$140 in a day is not very good", "Twitter's actually watching you".
   - The problem is always stated as his own ("I've been procrastinating learning", "When I'm writing, I often don't really know..."), which matches his own reading of v4 [13:36-13:42].
5. **Self-deprecation is placed after a success beat.** Examples: v1's "not sure why I recommended the Sony LUT ... but ignoring that" (86.8 s), v4's "It's a little bit buggy" in the CTA, v6's "a pretty meh idea" (MEASURED).
6. **Soft CTAs at the very end, links never in the post.** Spoken CTAs fall in the last 3-7% of runtime and are invitations ("give it a shot", "try to break it, I dare you", "let us know what you think"), never "sign up". In all four launch posts the URL comes in a self-reply posted 4 h 40 m to 7 h 46 m after the post, and in v2 and v3 it is phrased "This is real, and shipped" / "Yes, this is shipped!" (MEASURED from timestamps). INFERRED: this keeps the link off the scored post and lets the self-reply answer "is this real?" once the thread is busy. The channel-specific tracking link he describes (`/ig` [32:47]) also exists for X: the @heyclicky profile website is `heyclicky.com/x` (MEASURED, fxtwitter profile).
7. **Post copy fills a tweet and ends with "Demo:".** v1, v3 and v4 are 276-280 characters. v2, v3 and v4 end with the bare line "Demo:". The pattern is: a one-line claim, a one-line what-it-does, one concrete use ("learn Davinci Resolve", "Pythagorean Theorem + FL Studio", "In Claude Code ... In G-Mail ..."), then "Demo:" (MEASURED).
8. **Captions only on edited videos.** Burned captions appear in all four produced videos (v3-v6) as short phrase chunks, not karaoke word-by-word. They sit at about 80% height on 16:9 and about 63-69% on 9:16. The raw takes (v1, v2) have none (MEASURED).

## Where his practice differs from, or confirms, what he says in the interview

| He says (QUOTED) | Measured practice | Verdict |
| --- | --- | --- |
| The first 10 s should cover "What you're doing, why it's important, let's get into it" [11:13-11:17]; setup should be "like 10, 20%" [11:31] | v1, v3 and v4 state what by about 3 s and reach the demo at 8-10% of runtime. v2 starts the demo at 2%. v4 states the "why" (the turn) only at 21-30 s, which is 18-25% of runtime. v6's demo starts at 36% because the first third is story. | Mostly matches. The "why" often comes after the 10 s window. |
| "Most people, when they're scrolling, see the first three seconds" [09:32]; launch first frame "very purposely Xcode" [09:13]; "I purposely zoom in" [09:24] | v1 frame 0 is Xcode. The zoom starts at about 2.2 s and holds to 7.0 s. v2 also opens on Xcode. | Matches (MEASURED). |
| Launch was "almost entirely unplanned" [10:00], yet "you actually write a script for all of your videos" [10:13] | v1 shows one continuous take recorded in about 2-3 clock minutes (menu bar 5:23-5:25 PM, E1 plus this run), posted about 13 min later (INFERRED timezone). v4 is fully scripted [14:00]. | Both are true. The biggest launch was the unscripted one. |
| "Every video we just looked at, apart from the bad Zip School ones ... are made by Vikrant" [42:51-42:53] | v1 and v2 look like unedited Screen Studio exports at 60 fps, each with at most a jump cut and one insert. | Partly in tension (INFERRED). The editor's hand is visible in v3-v6, not in the two biggest raw takes. |
| "there's not a single cut in this video ... but there are beats" [37:02-37:06] (v2) | 5 luma breaks, all app windows opening, continuous webcam bubble. The beats arrive roughly every 10-15 s (Spotify 2.5 s, volume 14 s, Stripe 24 s, Ads 37 s, calendar 60 s, reminder 74 s, sign-off 92 s). | Matches. |
| "twitter generally doesn't like vertical videos it's like 16.9" [33:35-33:39] | X horizontal posts reached 0.63-3.83M views; X vertical posts 65-73K. | Matches on X (MEASURED views; causation INFERRED, since topics differ). |
| "show yourself, show your face very clearly" [12:36]; "I always start with a very clear, hi, this is what I'm working on" [12:56] | Face is visible 100% of the time only in the PiP raw takes; 32-62% in the edited ones. "Hey/Hi" opens v1, v3 and v4; v2 opens "Alright". | Mostly matches. The face is a bubble, not full-frame, in the two biggest hits. |
| Formula: "this is who I am, this is what's going on, this is what I'm working on, let me show you" [21:51-21:56] | v6 follows it exactly (what's going on: 5M views, then building, then show). v5 is only the "who I am" step, stretched to 109 s. v1-v4 skip "who I am" entirely. | Applies to the story/update register, not the launch demos. |
| "the most important thing in any video ... is audio quality" [41:46-41:55]; AirPods/MacBook mics "don't count" [42:27] | v1's raw take sits at -32 dBFS mid (14-16 dB under the edited ones) with no stereo content. A clip-on transmitter is visible on his chest in v5 (1.0-3.0 s). I did not assess which mic v1/v2 used. | Not testable from these files beyond loudness. |
| "I'm really good at the music" [43:39]; music lowered to talk over [37:22] | Music beds run in all four edited videos, with level changes at the turn or reveal (v3 dip at 50-68 s; v4 bed enters at about 8-10 s and dips at 56-66 s) and a swell under the end card (v3). | Consistent (side-channel MEASURED; "music" INFERRED). |
| Interview numbers: launch "nearly 3 million views" [06:58]; dictation "3 million views on Twitter, 20,000 on YouTube" [12:16]; no-hands "3.8 million views on twitter" [36:50] | 3,000,762; 2,945,014 and 21,012; 3,826,653 | All confirmed (MEASURED 2026-10-24). |

## Videos I could not measure, or chose not to

- **The YC-batch video, "last week I went super viral ... this week I'm somehow in Y Combinator", 21M Instagram views per [21:07].** It is not on the fxtwitter-visible FarzaTV or heyclicky X timelines (FarzaTV pages reached back to Apr 14 2026; heyclicky only to Jul 4 2026). I checked the heyclicky YouTube video "we are a real company now" (oQHcQYQgQ50) via auto-subs: it is a weekly "everything we're shipping" update, not that video. Instagram was not tried. The interview copy is on screen at about 21:26-22:14 of the YC video.
- **The weekly "this is everything we shipped" process videos** [24:52-26:56], e.g. YouTube 93-Zd5L0RMQ "this is everything we shipped." (1.9K views per yt-dlp) and ffi-bsnU4VQ "shipping a ton and fixing 200+ bugs" (913 views). Not measured, for scope.
- **Other high-view X posts not measured, for the 4-6 budget** (views MEASURED from the timeline):
  - "Here's the new Clicky" (2048203459976188261, 1,192,157 views, 223 s)
  - "Here's our new landing page + look" (2078645479899078911, 344,065 views, 16 s)
  - "Introducing collaborators" (2103581812069179417, 201,590 views, 168 s)
  - heyclicky "never touch me again" (2061650962004218327, 145,280 views, vertical 55 s)
- Nitter (`nitter.net`) served a challenge page, `xcancel.com` returned HTTP 451, and the syndication timeline returned 20 bytes. The fxtwitter profile endpoint worked once called without `?count=`.

## Measurement traps found in this run (for the method doc)

- **Luma cuts on screen recordings count app switches, and miss Screen Studio zooms.** v2's 5 "cuts" are windows opening. v1's zooms register only as soft diffs. Count edits by eye on the 1 fps sheet for screen-led videos.
- **Luma cuts overcount archival low-fps footage.** In v5, a handheld clip produced 7 "cuts" in 1.2 s.
- **whisper-cli compressed the timestamps of a speech-over-music file.** v5's speech appeared to end at 49.5 s of 109.5 s. Check that the last segment end is close to the duration. Re-run from an offset if it is not.
- **fps=1 sampling is useless on v6** (median shot 0.73 s). Use per-shot midpoints there.
