# R1: chapters intro to The Clicky Launch (00:00-07:43), deep read

Slot R1. Span: 00:00-07:43, read with margins to 08:20. Chapters covered: intro (00:00), Launch Constantly (01:44), Start Shipping Demos (03:38), Show the Process (05:02), The Clicky Launch (06:07).

Source: the YC interview of Farza Majeed by Aaron Epstein, posted 2026-10-23 at https://x.com/ycombinator/status/2113654566776709147 (YouTube v12aSIZIXUs).

## Labels and method

- **MEASURED** means I ran it or saw it this run.
- **QUOTED** means his words, with the interview time in [mm:ss].
- **DOCUMENTED** means a source states it, with a URL.
- **INFERRED** means my reasoning.
- **prior probe E1** is `docs/research/video-understanding-human-parity-2026-10-23/agents/E1-exam-key.md`.

How the evidence was gathered (all MEASURED):

- **Transcript.** I read `/tmp/farza-2026-10-24/transcript.txt` lines 1-188 (00:00-08:20).
  - The shared `cuts-luma.txt` was empty and no shared sheets existed when I started. `ingest-status.txt` was absent.
- **Hard cuts.** I recomputed cuts for 0-518 s with the SKILL.md luma-diff rule (96x54 gray, diff >= 20, local peak over +-2 frames, 23.976 fps).
  - Output: `/tmp/farza-R1/cuts.txt` (0-123 s) and `/tmp/farza-R1/cuts2-raw.txt` (118-518 s, times offset by +118 s).
- **Insert finder.** The source has a keyframe every 3.003 s (measured, `ffprobe -skip_frame nokey`). I extracted every keyframe from 0-520 s (170 frames) and labelled each with its exact pts time.
  - Sheets: `/tmp/farza-R1/sheet-grp-a[a-f].jpg`.
  - Every non-talking-head moment in the span was found this way, then read at full 1920x1080 (`/tmp/farza-R1/f/`, `/tmp/farza-R1/cl/`).
- **Machine load.** The machine was heavily loaded the whole run (load average 262 on 10 cores, `uptime`). Frame extraction was slow, so I sampled inserts at the midpoint of each shot rather than at fixed fps.
- **Audio and words for the Clicky clip.**
  - Mid/side levels per 0.5 s for 06:00-06:22 (numpy on `ffmpeg -ac 2`).
  - Word-level whisper (`whisper-cli`, large-v3-turbo q5_0, `-ml 1 -sow`) on 06:02-06:18 (`/tmp/farza-R1/a362.wav`).
  - Webcam-bubble lip crops at 2 fps: `/tmp/farza-R1/m-lip.jpg`.
- **ASR spellings corrected from the screen.** "Hey Clicky" is **heyclicky** (site, YouTube, lower-third "Founder, Heyclicky"). The handle is **@FarzaTV** on X and **farza954** on Instagram. "Buildspace" appears as "buildspace" in the 01:05 clip.

---

## 1. Shot map of the span (MEASURED cuts, luma-diff)

| Span | What is on screen |
| --- | --- |
| 00:00.00-00:02.42 | Aaron solo to camera, grey sweatshirt (cold open, shot separately: prior probe E1 Q1) |
| 00:02.42-00:04.50 | NYT headline card |
| 00:04.50-00:06.46 | 3x3 grid of high-production startup launch videos |
| 00:06.46-00:07.51 | Second 3x3 grid variant |
| 00:07.51-00:08.63 | Aaron solo |
| 00:08.63-00:10.22 | Wide two-shot inset in a white/peach frame |
| 00:10.22-00:12.85 | heyclicky YouTube channel page |
| 00:12.85-00:17.10 | YouTube watch page "shipping a ton and fixing 200+ bugs" (sub-cuts 14.35, 15.35, 15.72, 16.47) |
| 00:17.10-00:18.60 | heyclicky.com homepage |
| 00:18.60-00:19.60 | X post, Jul 14 (screen-aware dictation) |
| 00:19.60-00:20.60 | X post, Apr 6 (Clicky launch) |
| 00:20.60-00:21.86 | X post, Jul 8 (spatial context) |
| 00:21.86-00:27.94 | Farza close-up (lines lifted from 21:51) |
| 00:27.94-00:31.41 | Wide two-shot (line lifted from 24:04) |
| 00:31.41-00:33.87 | Instagram profile grid with host and guest picture-in-picture boxes |
| 00:33.87-00:36.04 | Instagram reel "is my startup trash? let's decide." |
| 00:36.04-00:36.70 | Same reel, rocket frame |
| 00:36.70-00:44.79 | Title cards, "Startup School / Launch Video Advice" |
| 00:44.79-00:47.01 | Wide two-shot with lower-thirds |
| 00:47.01-00:51.01 | Aaron close-up |
| 00:51.01-01:06.69 | Split-screen: "hi my name is farza" post (left) and Farza close-up (right) |
| 01:06.69-01:09.86 | heyclicky.com homepage again |
| 01:09.86-06:03.79 | Talking heads only, no inserts (keyframe sheets checked every 3 s) |
| 06:03.79-06:07.21 | Clicky launch post on X, with host and guest boxes |
| 06:07.21-06:15.88 | Full-screen punch-in of the launch clip itself |
| 06:15.88 | Back to Farza close-up |
| 06:41.49-06:47.12 | Launch post again (clip on its DaVinci Resolve segment) |
| 07:43.10-07:59.53 | Launch post again (clip paused; headline highlighted) |
| 07:59.53 onward | Talking heads |

Cut times inside the talking-head stretch 01:09-06:03, for completeness: 01:22.50, 01:27.09, 01:31.42, 01:49.23, 01:58.62, 02:03.04, 02:14.77, 02:25.57, 02:28.41, 02:36.41, 02:46.72, 03:01.48, 03:06.36, 03:47.44, 03:55.41, 03:59.33, 04:05.79, 04:15.09, 04:33.70, 04:35.53, 04:58.76, 05:02.56, 05:17.45, 05:27.71, 05:34.17. After the span: 07:05.77, 07:19.78, 07:32.58, 08:03.74, 08:12.33. All are wide or close-up switches.

---

## 2. Catalog of claims, techniques, numbers, examples and anecdotes

Columns: **T** is the start time. **Type** is rule / technique / number / example / anecdote / opinion. **Basis** is "experience" (Farza's own experience, no outside evidence given), "external" (he or YC points to an outside source) or "on-screen" (backed by a visible post or count).

### Intro and cold open (00:00-01:44)

| # | T | Claim in plain words | Quote | Type | Basis |
| --- | --- | --- | --- | --- | --- |
| 1 | 00:00 | YC's framing, voiced by Aaron: founders wrongly think launching means spending heavily on a slick video and hoping it hits. | "These days, too many founders think launching is all about spending a ton of time and money to produce a slick video and hoping it hits." [00:00] | opinion (host) | external: YC cuts to a NYT headline (Insert A) |
| 2 | 00:07 | Farza has a different approach to launching and going viral. | "my guest today, Farza Majeed, has a totally different approach to launching and going viral." [00:07] | opinion (host) | — |
| 3 | 00:12 | A weekly "everything we shipped" video, recorded outdoors in a group selfie, is shown as an example of the format. The line is from the heyclicky clip itself. | "All right, this is everything we ship this week." [00:12] | example | on-screen: YouTube "shipping a ton and fixing 200+ bugs", 787 views (Insert C/D) |
| 4 | 00:17 | His posts regularly get millions of views. | "his posts regularly get millions of views." [00:17] | number (host claim) | on-screen: 2.9M, 2.9M, 294K on X; 2.5M, 4.5M, 1.4M, 20.9M on Instagram (Inserts F, H) |
| 5 | 00:21 | His formula is fixed: who I am, what's going on, what I'm working on, let me show you. The cold open lifts this from 21:51. | "This is who I am." [00:23] | technique (formula) | experience |
| 6 | 00:27 | A demo should be a mini story, because everyone wants a story. Lifted from 24:04. | "Everyone wants a story, and so how can a demo just be a mini story?" [00:27] | rule | experience |
| 7 | 00:31 | The promise of the episode: a playbook for videos that convert, not just get views. | "how to create videos that actually convert." [00:31] | opinion (host) | — |
| 8 | 00:51 | Bio: first company at 13 selling on eBay. Ten years later he moved into software and built an online school for kids, which went through YC in 2020 with Aaron. | "I started my first company when I was 13, selling stuff on eBay." [00:51] | anecdote | experience. The split-screen shows his "hi my name is farza" post (Insert I) |
| 9 | 01:01 | That became Buildspace, "one of the largest schools for people who wanted to work on their own ideas". Now he runs heyclicky, "a new interface for AI". | "now working on Hey Clicky, a new interface for AI." [01:01] | example | heyclicky.com is shown 01:06.7-01:09.9 (Insert J) |
| 10 | 01:10 | Aaron: video has been a core distribution strategy at Buildspace and heyclicky. | — | opinion (host) | — |
| 11 | 01:27 | He simply loves making online videos. Now the story in front of him is his company's story. | "the story that's in front of me is actually my company's story." [01:31] | opinion | experience |
| 12 | 01:39 | In 2026, making videos is good for business. | "making videos in 2026 is really good for business, too." [01:39] | opinion | experience |

### Launch Constantly (01:44-03:38)

| # | T | Claim in plain words | Quote | Type | Basis |
| --- | --- | --- | --- | --- | --- |
| 13 | 01:45 | Aaron: Farza has made and published videos for over a decade. | "you've been making videos for over a decade" [01:45] | number (host) | — |
| 14 | 02:02 | The 2020-era launch playbook was Hacker News, Product Hunt and Reddit ("find the right subreddit"), each a one-off launch post. | "back then, you know, we had to do stuff like post to Hacker News, post to Product Hunt, go to Reddit" [02:02] | example | experience |
| 15 | 02:14 | Users of every product, whether drones, AI or a dating app, now live on many new channels. | "It doesn't matter what you're working on." [02:19] | opinion | experience |
| 16 | 02:23 | Those channels are mostly algorithmic: X, LinkedIn, Twitter (sic, said alongside X) and YouTube. | "Your users are on many new platforms, mostly algorithmic platforms like X, LinkedIn, Twitter, YouTube." [02:23] | opinion | experience |
| 17 | 02:28 | The biggest change: you no longer make one launch post; you launch constantly on algorithmic platforms. | "You're actually just constantly launching all the time on these algorithmic platforms." [02:31] | rule | experience |
| 18 | 02:36 | Aaron: YC batch founders over-invest time, energy and money in one big, coordinated, fancy launch video and hope it is the moment. | — | opinion (host) | experience (host, YC batches) |
| 19 | 02:55 | The old approach made sense: you had one shot (a TechCrunch article, New York Times press), so you needed a polished asset to go with it. | "you got to do like a fancy thing and make it a big deal because you got one shot." [02:58] | opinion | experience |
| 20 | 03:08 | Old media is "kind of just gone". | "now all of the old media is kind of just gone." [03:08] | opinion | experience; no data given |
| 21 | 03:11 | A selfie video of him saying hi and describing the product will likely beat a $20,000 produced video placed with the NYT, on engagement and traffic. | "a video where I put I say hi and I talk about my product is probably going to perform way better than like a $20,000 produced video" [03:11] | number + opinion | experience. Hedged with "probably"; no comparison data given |
| 22 | 03:26 | You don't need old media. A phone and a laptop are enough. | "if you have a phone and a laptop, you're so much more powerful." [03:28] | rule (kit) | experience |
| 23 | 03:31 | Call them launches, but they are mini launches happening all the time. | "These are mini launches all the time." [03:38] | rule | experience |

### Start Shipping Demos (03:38-05:02)

| # | T | Claim in plain words | Quote | Type | Basis |
| --- | --- | --- | --- | --- | --- |
| 24 | 03:41 | A launch is not a rocket launch; do not treat each one as a big event. | "It's not like we're launching a rocket." [03:45] | opinion | experience |
| 25 | 03:48 | Call them demos, not launches, and ship demos constantly. The more demos a company puts out, the better. | "I rather call these demos instead of launches." [03:48] | rule | experience |
| 26 | 03:55 | Weekly cadence question inside the company: what are we launching this week? | "At my company, I'm always like, well, what are we launching this week?" [03:55] | rule (cadence) | experience |
| 27 | 03:59 | Work backwards from the launch of whatever is being built. | "we work backwards always from the launch of whatever we're working on." [03:59] | technique | experience |
| 28 | 04:04 | At feature-planning time, besides the feature and how it feels, ask: what is the Instagram caption copy, and what is the hook if this becomes a video? | "But then I ask, well, what's the copy on the Instagram caption?" [04:08] | technique | experience |
| 29 | 04:15 | It need not go viral, but the team should discuss how to communicate it. | "And not that like it needs to have a good, needs to go viral, but we should talk about it." [04:15] | rule | experience |
| 30 | 04:19 | How you communicate is as important as what you build, so communication belongs in every part of the process. | "how we communicate to other people is just as important as what we're building." [04:19] | rule | experience |
| 31 | 04:24 | A hit video is not made by magic after the build; "we kind of know it's a hit" before building, because it "sounds good on paper". | "It's always like we kind of know it's a hit before we even start like working on it" [04:28] | opinion / technique | experience. Tension with #42 and with 14:26 (section 6) |
| 32 | 04:35 | Aaron: his videos look effortless and off the cuff, but the hook is worked out before the video is made. | "you're trying to figure out the hook before you even do the video." [04:46] | technique (host summary) | — |

### Show the Process (05:02-06:07)

| # | T | Claim in plain words | Quote | Type | Basis |
| --- | --- | --- | --- | --- | --- |
| 33 | 05:02 | Philosophy: show the process of what you are doing, not the finished end state. | "how can we just show like almost like the process of what I'm doing versus show the ending of what I'm doing." [05:02] | rule | experience |
| 34 | 05:15 | Anti-pattern: the "founder raised X, here is my product, fancy DSLR, wonderfully edited, nice office" video. He sees many daily. | "I saw like five today for sure." [05:29] | example (foil) + number | experience |
| 35 | 05:31 | Those polished videos have a purpose, but making them the default aspiration is "really annoying". He deliberately does the opposite. | "And those have a purpose." [05:31] | opinion | experience |
| 36 | 05:43 | A polished launch is a one-time thing; what you want is a channel. | "Because again, that's a one-time thing." [05:43] | rule | experience |
| 37 | 05:44 | Why launch at all? To get users, not clout or looking smart. The exchange is probably Farza asking and Aaron answering "to get users" (INFERRED speaker split; the ASR has no labels). | "We're not launching to like get a bunch of clout on the internet and make people think that we're smart." [05:50] | rule (goal) | experience |
| 38 | 05:56 | The goal of launching is a repeatable channel you can keep finding users from. | "that means having a channel that we can keep on repeating and find users from." [05:56] | rule | experience |

### The Clicky Launch (06:01-07:43, margin to 08:20)

| # | T | Claim in plain words | Quote | Type | Basis |
| --- | --- | --- | --- | --- | --- |
| 39 | 06:05 | The "perfect example" is the X post that launched heyclicky. | "This is like the launch of Hey Clicky." [06:05] | example | on-screen: @FarzaTV, 5:38 PM · Apr 6, 2026, 2.9M views (Insert K) |
| 40 | 06:07 | The launch clip opens with a one-sentence definition: Clicky is a little blue guy that follows your cursor as you use your computer, an AI teacher that can teach you anything. This is the clip's own audio (section 3). | "Clicky is this little blue guy that follows your cursor as you use your computer." [06:09] (re-transcribed; the batch ASR has "on his user computer") | example (hook wording) | on-screen and audio, MEASURED |
| 41 | 06:16 | He thought the demo was "not that good". Aaron, in YC office hours, said to post it, and asked again later before Farza agreed. | "Honestly, I thought the demo was not that good." [06:16] | anecdote | experience; an outside push from the partner |
| 42 | 06:31 | Even after 10+ years of doing this, he still feels "it's not good enough". That instinct was "so wrong". | "I've been doing this for years, like 10 plus years." [06:31] | anecdote / rule (post anyway) | experience |
| 43 | 06:40 | He recorded it in the office five minutes before dinner and posted it. After dinner it was "doing numbers". | "I record this video in the office five minutes before dinner and I post it." [06:40] | anecdote | on-screen corroboration: clip clock 5:23-5:24 PM, post 5:38 PM (Insert K/L) |
| 44 | 06:47 | It was a random side project he open-sourced because he thought nobody would care. Six months later it is his company. | "It was just a random side project that I then even just open source" [06:49] | anecdote | experience. "Six months": Apr 6 to about Oct is consistent (INFERRED) |
| 45 | 06:58 | Aaron: "nearly 3 million views". | "this was nearly 3 million views." [06:58] | number | on-screen: "2.9M Views" (MEASURED) |
| 46 | 07:05 | He does not care about views or congratulations. He asks "what are the actual numbers?", meaning downloads. | "I do not care about the traffic at all." [07:05] | rule (metric) | experience |
| 47 | 07:17 | About 7,000 people downloaded after that video. | "after this video, I think 7,000 people downloaded it." [07:18] | number | experience (his recollection, "I think") |
| 48 | 07:19 | He then checked retention: about 100 of the 7,000 used it every day for five days straight. He says "four days later" and then "five days straight" (section 6). | "about 100 people of the 7,000 kept on using it every day for five days straight." [07:27] | number + technique (retention cut) | experience |
| 49 | 07:22 | He continued the product because of retained users, not virality. | "it's not because it went viral." [07:24] | rule | experience |
| 50 | 07:34 | He reached out to all ~100 retained users and talked to each one. They used it for things he never imagined, and the users inspired him to continue. | "I reached out to those 100 people." [07:34] | technique | experience |
| 51 | 07:43 | (Margin, next chapter.) Many choices are subconscious by now. The headline is just casual: "I built this thing. It's an AI teacher. What does it do? Why is it important?" | "even just the headline, just like, it's just casual." [07:49] | technique (headline) | on-screen: the cursor highlights "I built this thing called Clicky." at about 07:51 (Insert M) |
| 52 | 08:01 | (Margin.) He has written for a decade-plus. "Tweet poetry": he cares about length and about the parts of the story. Aaron recalls Buildspace marketing emails written the same way. | "I care about how long things are." [08:06] | technique (copy) | experience |

---

## 3. The Clicky launch clip, shot by shot (06:03.79-07:59.53)

### 3a. The post as shown (MEASURED, full-res `/tmp/farza-R1/cl/c-366.jpg`)

- **Layout.** Black background. Post centred. Aaron's camera box top-left, Farza's top-right (both live table cameras). YC "Y" bug bottom-right.
- **Header.** "Farza" with Pakistani and US flag emoji and a verified badge, "@FarzaTV". A white **"Boost"** button, a Grok-style icon and "...".
  - INFERRED: the Boost button appears for the post's own author, so he is showing it logged in as himself.
- **Post text, verbatim, four paragraphs:**
  1. "I built this thing called Clicky."
  2. "It's an AI teacher that lives as a buddy next to your cursor."
  3. "It can see your screen, talk to you, and even point at stuff, kinda like having a real teacher next to you."
  4. "I've been using it the past few days to learn Davinci Resolve, 10/10."
  - About 52 words (estimated, hand count).
  - Structure (INFERRED): casual first-person claim, then a one-line metaphor of what it is, then a three-part capability list plus an analogy, then personal proof with a rating. There is no "Demo:" label; the video sits directly under the text.
- **Metadata.** "5:38 PM · Apr 6, 2026 · **2.9M** Views".
  - Counts: 1.3K replies, 1.7K reposts, 15K likes (heart filled pink), 12K bookmarks. "Relevant", "View activity".
- **Embedded video.** Landscape screen recording. The remaining-time badge read "1:38" at 06:06 and "1:36" in the 00:19.6-00:20.6 cold-open view.
  - The player later shows **"0:01 / 1:40"** and "0:02 / 1:40" (07:43-07:59), so the launch video is **1:40 long** (MEASURED).

### 3b. The clip itself

| Time | On screen (MEASURED) | Audio |
| --- | --- | --- |
| 06:03.79-06:07.21 | Post view as in 3a; the embedded video is playing. Farza's live camera box shows him gesturing as he introduces it. | Farza live: "This is like the launch of Hey Clicky." [06:05] |
| 06:07.21-06:08.4 | YC editor's full-screen punch-in on the embedded video (the post chrome is gone). Xcode, project "learning-buddy", file `BuddyDictationManager` (`final class BuddyDictationManager: NSObject, ObservableObject`). The console reads "Clicky: Starting... / Clicky: Version 1.0 / Permissions - accessibility: true, screen: true, mic: true, screenContent: false / Clicky start - accessibility: ...". A left pane reads 'No Results for "press start" in Project'. The macOS menu bar reads **"Mon Apr 6 5:23 PM"**. | Clip audio (see attribution below) |
| 06:08.5-06:13 | The edit zooms in on the cursor area. The line `var isMicrophoneButtonSessionBusy: Bool {` sits at the top. The black macOS arrow cursor has a **small blue triangle (the Clicky "buddy") trailing beside it**, and the two move together across the empty editor (06:09-06:12). The webcam bubble stays bottom-right. | "So this is Clicky. Clicky is this little blue guy that follows your cursor as you use your computer." |
| 06:13-06:15.88 | The zoom pulls back to the whole Xcode window with the dock; the bubble stays bottom-right. | "And it's basically an AI teacher that can teach you anything." (ends at about 06:16.0) |
| 06:15.88 | Cut to Farza close-up at the table. | Farza live: "Honestly, I thought the demo was not that good." [06:16] |

**Framing of the launch clip (MEASURED from the frames above and Insert L):**

- A single continuous macOS screen recording with a **rounded-square webcam bubble bottom-right**. Farza in the bubble has no cap: glasses, beard, dark top, an orange wall and a white room behind him (prior probe E1 Q8 identifies him).
- Face and screen share the frame for the whole sampled clip. There is no separate face-only shot.
- **No burned-in captions or text overlays** appear in any frame I sampled (06:04-06:15, 06:41-06:47, 07:43-07:59).
- **The hook is spoken, not written:** product name, then a visual description of the on-screen thing, then the one-line value proposition.
- **Bubble speaking.** The mouth forms different shapes at 06:09.0, 06:10.0, 06:11.0, 06:12.0 and 06:12.5 (MEASURED, `/tmp/farza-R1/m-lip.jpg`).

**Who is speaking 06:07.4-06:16.0 (INFERRED, high):** the launch clip's own audio, not Farza live at the table. Three independent measurements agree:

1. Whisper word-level output on 06:02-06:18 put **speaker-turn markers at 06:07.44 and 06:16.08**, exactly bracketing these words.
2. The **mid level drops** from -13 to -18 dB (studio dialogue, 06:04-06:08) to **-21 to -28 dB during 06:08.5-06:15.5**, then returns to -14 to -17 dB from 06:16. The audio is mono throughout (side mostly at digital zero).
3. The bubble face is visibly articulating.

The batch transcript's "[06:10] that follows your cursor on his user computer" is an ASR error. The word-level pass reads "follows your cursor as you use your computer".

### 3c. Second showing, 06:41.49-06:47.12 (MEASURED, `c-403.0.jpg`, `x-dvr.jpg`)

- **Layout.** Same post layout and boxes. The embedded video is now in **DaVinci Resolve 20**: project "test_grade", "Timeline 1", timecode 00:00:16:08, clips "The-Greenhouse-...", "C0006.MP4", "Timeline 1". The viewer shows a man touching a plant in a greenhouse.
- **Clock.** The menu bar reads **"Mon Apr 6 5:24PM"**.
- **Remaining time.** The badge reads "1:03" at 06:43.0 and "1:00" at 06:45.5, so this is roughly 0:37-0:40 into the 1:40 clip. The bubble is still bottom-right.
- **Audio.** Farza live, about recording "five minutes before dinner" and "after dinner, it's just doing numbers" [06:40-06:47].
- **Point illustrated.** The use case named in the copy ("learn Davinci Resolve") is demonstrated live in the same single take, which moved from Xcode to Resolve. INFERRED from the clock going 5:23 to 5:24 within one continuous recording.

### 3d. Third showing, 07:43.10-07:59.53 (MEASURED, `/tmp/farza-R1/m-reshow.jpg`)

- **Player.** Same post. The video is paused at "0:01 / 1:40", then "0:02 / 1:40", with a "Play" tooltip, so someone is scrubbing or clicking it.
- **Cursor.** It moves through the post text. At about **07:51 the line "I built this thing called Clicky." is selected/highlighted**. The cursor then moves to "buddy" (07:54) and to "It can see your screen" (07:57).
  - A small yellow triangle pointer trails the mouse cursor in this screen recording, as it does in the 00:31-00:36 Instagram recording. INFERRED, low: the interview laptop itself runs Clicky.
- **Audio.** Farza: "even just the headline, just like, it's just casual. I built this thing. It's an AI teacher. What does it do? Why is it important?" [07:49-07:59].
- **Point illustrated.** The copy is a sequence of short answers: what it is, what it does, why it matters.

### 3e. Recording-to-post timing (MEASURED inputs, INFERRED conclusion)

| Clip time | In-clip clock |
| --- | --- |
| About 0:02 | 5:23 PM |
| About 0:37-0:40 | 5:24 PM |

The post timestamp is 5:38 PM, Apr 6, 2026. So posting came about **15 minutes after recording**, which is consistent with "recorded five minutes before dinner and posted" [06:40]. It implies minimal or no editing: one take, about 1:40, posted the same evening.

---

## 4. Every other on-screen insert in the span (MEASURED, full-res frames in `/tmp/farza-R1/f/`)

**Insert A, 00:02.42-00:04.50: newspaper card.**
- Pink gradient card in a serif italic headline: "Go Ask Alice Why Tech Start-Ups Are Spending Big on **Hype Videos**". "Hype Videos" is highlighted in orange. "The New York Times" wordmark below.
- Illustrates the foil: expensive hype videos.
- DOCUMENTED (search-result summary of The Star's reprint; I did not open the page): the piece leads with an AI startup, Daydream, staging an "US$80,000 video shoot" to announce a US$15M round. https://www.thestar.com.my/tech/tech-news/2026/05/31/go-ask-alice-why-tech-startups-are-spending-big-on-hype-videos/

**Inserts B1/B2, 00:04.50-00:07.51: two 3x3 grids of high-production launch videos (the foil).** Readable tiles:
- "Personalized Brain Games" pill over an "ato" fabric speaker device on a shelf; the variant shows an older man gardening.
- A red silhouette dancing in a forest with yellow neon words "AEO", "AI SE…", "LMO" (variant: "GEO", "AEO", "LMO").
- "PIKA AI SELVES" with an ID card "ALEX P." and caption "AI Selves." with a "Pika" watermark.
- A man in a corduroy jacket in a brick loft (interview-style).
- "SERIES [letter illegible] **$50M** Led by MENLO VENTURES".
- "Cluely" over a dark restaurant scene.
- A woman beside a dark humanoid robot (a "1X"-style logo, top-left).
- An overhead dinner table with a skillet.
- A kiosk "Doo-Dah Cafe" under a storm with the subtitle "Because in today's world, technology has".
- An eye macro and a kitchen scene with the same subtitle.

The voice-over is Aaron's "slick video and hoping it hits" line. Point: the expensive cinematic launch film that Farza's method opposes.

**Insert C, 00:10.22-00:12.85: YouTube channel "heyclicky".**
- "@heyclicky · 1.14K subscribers · 21 videos", "your friendly neighbourhood cursor ...more", link "heyclicky.com/yt", Subscribe.
- Tabs Videos / Shorts / Playlists; Latest selected.
- First-row videos:
  - "shipping a ton and fixing 200+ bugs" (0:56, 787 views, 2w ago)
  - "introducing agent buddies" (2:25, 5.8K, 3w ago, overlay chip "meet my buddies ^^")
  - "this song is not AI-generated" (2:22, 1.1K, 3w ago)
- Second-row thumbnail chip: "aww ty ^^".
- The banner shows a macOS cursor with a blue triangle.
- Point: a cadence of frequent, casual company videos with modest view counts.

**Insert D, 00:12.85-00:17.10: YouTube watch page "shipping a ton and fixing 200+ bugs".**
- heyclicky, 1.14K subscribers, 25 likes.
- Clip: a low-angle group selfie at the Transamerica Pyramid. Farza (checked jacket) holds a DJI wireless mic.
- Big lowercase caption "everything" (00:12.85-00:14.35), then "Well, shipping, right?" / "Are we shipping?" / "Yeah, we're shipping." over quick close-ups of different people (prior probe E1 Q2).
- The audio "All right, this is everything we ship this week." [00:12] is the clip's.
- Point: a weekly "what we shipped" team video with word-by-word captions and a phone-selfie look.

**Insert E, 00:17.10-00:18.60 and again 01:06.69-01:09.86: heyclicky.com homepage.**
- Nav "heyclicky features pricing trust changelog careers". The menu bar shows "5:26 PM" and "get heyclicky".
- Centre: "heyclicky / an ai buddy that lives on your mac", buttons "download for mac" and "windows waitlist", small text "100% free. sonoma 14.2 or higher".
- Floating desktop-style windows labelled it-draws-too-omg.mov, heyclicky-draw.mov, usecase.mov (caption 'Could you play "Can You'), nohandstricklol.mov and daddyshome.mov.
- Main video hello.mov ("play video"): two men in a convenience-store aisle.
- Also "HELLO my name is heyclicky" stickers, kaomoji, a Nokia phone and a trash can.
- Point: the site itself is built from demo clips (.mov files) in the same casual register.

**Insert F, 00:18.60-00:21.86: three @FarzaTV X posts in one-second flashes.**

| Span | Post | Text and video | Counts |
| --- | --- | --- | --- |
| 00:18.60-00:19.60 | "Jul 14" | "Today we're shipping screen-aware dictation. / First, we built a speedy speech-to-text (very fast, ~450ms). / But, many products do this! / So we went further. Now dictate using your screen as context. In Claude Code, it writes the prompt. In G-Mail, it replies in your voice. / Demo:" Video: outdoor talking head with a red water bottle, caption "dictation to HeyClicky." | 552 replies, 776 reposts, 10K likes, **2.9M** views |
| 00:19.60-00:20.60 | "Apr 6" | The Clicky launch post (3a), video badge 1:36 | 1.3K, 1.7K, 15K, **2.9M** |
| 00:20.60-00:21.86 | "Jul 8" | "Today we're shipping spatial context. / This lets you draw directly on your screen + pass it as context to the model. / AI can easily analyze screenshots. But, it has no idea where exactly you want it to look. Now you can just show it. / It's very intuitive. / Demo:" Video: Farza drawing UI boxes on glass, caption "hotkey and use your cursor", badge 1:11 | 181, 193, 2.8K, **294K** |

- Point: a repeated copy template and frequent feature launches.
- INFERRED: the same template produced a 10x spread in views (2.9M versus 294K).

**Insert G, 00:31.41-00:33.87: Instagram profile grid (owner view, with view counts).**
- Host and guest camera boxes sit top-left and top-right. The left rail shows the Instagram icons with a "5" badge.
- Tiles:
  - "We made our first beat," (2.5M)
  - a code/terminal screen recording (4.5M)
  - "heyclicky.com" over Farza sitting on a bench (1.4M)
  - "Last week I went" (20.9M)
  - the top row is cut off: 462K, 160K, 29.3K
  - lower row: a Windows-XP-style sky with "hi, i'm clicky!" chat bubble beside the cursor, people climbing stairs, a dark scene, a red theatre
- "Messages" pill.
- Voice-over (Aaron): "videos that actually convert" [00:31].
- Point: Instagram is the bigger view surface.
- Which account: INFERRED, the reel opened next is farza954's. The prior probe E1 Q16 found "_heyclicky" at 24:45, a different account.

**Insert H, 00:33.87-00:36.70: Instagram reel by "farza954 ✓, Original audio".**
- Caption "is my startup trash? let's decide.", "Edited · 12w".
- On-video text: "It has been 9 weeks" (Farza on a gym ball against a Windows-XP-style green hill), then "and launched" over a rocket launch (36.04-36.70).
- Bubbles over the video: "am I trash? 😭" and "gymball video" with avatars, one of them the heyclicky logo.
- Comments, verbatim:
  - aadillpickle "my fav"
  - nadimu.nasser "you're so cool man"
  - elibethmarch "Every time I use it I feel like we're in future I saw in cartoons when I was a kid!!! Fireeeee 🔥🔥🔥🔥" (5 likes)
  - qroonjha "Your video editor deserves a Pakwan dinner 🙌" (59 likes, View replies (2))
  - mosaad_m7 "Bro, we're using the product because your content is just that good! 🔥"
- "View insights", "Boost reel", "Liked by samin100 and **3,364 others**", "July 1".
- Point: a progress/story-format update ("it has been 9 weeks"), and social proof that content drives product use.

**Insert I, 00:51.01-01:06.69: split-screen.**
- Left third: a white panel with an @FarzaTV post, "hi my name is farza / i just wanted to introduce myself", over a vertical video with word-chunk captions.
- Caption at each sampled time:

| Time | Caption | Picture |
| --- | --- | --- |
| 52.0 | "making stuff on" | a teen in glasses at a webcam and laptop |
| 53.2 | "back in 2008" | — |
| 55.5 | "I was 24" | a hackathon room, top banner "K.O" |
| 57.0 | "I wanted to start" | same "K.O" room, a MacBook |
| 59.0 | "learn new things." | an adult with kids at a laptop |
| 60.5 | "And so I started" | an educational graphic "COMPOUND EYES / SIMPLE EYES" on a dragonfly, a woman in an inset circle |
| 62.0 | "for people" | a large hall full of people at laptops |
| 63.5 | "their own ideas." | same hall |
| 65.5-66.4 | "It's where so" | a hand-drawn/3D street with "buildspace" signage |

- Right two-thirds: Farza close-up telling the same bio live. The post's video is muted under his voice (INFERRED from the transcript, which carries only his live words).
- Sub-cuts inside the panel: prior probe E1 Q5.
- Point: the bio told through a founder self-introduction post. The format is "hi, my name is X, I just wanted to introduce myself" plus a life montage with captions.

**Lower-thirds, 00:44.79-00:47.01** (MEASURED, `f-46.0.jpg`): "Aaron Epstein / General Partner, Y Combinator" and "Farza Majeed / Founder, Heyclicky".

**Title cards, 00:36.70-00:44.79** (MEASURED, `/tmp/farza-R1/m-titles.jpg`): an outlined "Learn", then a bold "Startup", then "Startup School" (School in orange), then an orange bar "Startup School", then a white box "Launch Video Advice" on orange, then a black-square transition. Music: prior probe E1 Q3.

**Laptop on the table, whole span:** the back of Farza's MacBook carries a purple sticker with the heyclicky zig-zag/caret logo (MEASURED, `f-9.4.jpg`). INFERRED: product branding in frame.

---

## 5. Procedure steps implied by this span (imperative, each anchored)

1. Treat every shipped feature as a launch. Plan for weekly mini-launches ("demos"), not one big launch film [02:31], [03:38], [03:48].
2. Each week ask the team "what are we launching this week?" and work backwards from that launch [03:55], [03:59].
3. At feature-planning time, before building, draft the caption copy and the video hook. Kill or rethink the feature if it does not "sound good on paper" [04:08], [04:11], [04:28].
4. Make communication a standing part of the build process, not a post-build marketing step [04:19], [04:22].
5. Show the process, not the polished end state. Avoid the "raised $X, DSLR, nice office, heavily edited" template [05:02], [05:15].
6. Optimise for a repeatable channel that yields users, not clout. Judge every launch by whether it feeds that channel [05:44], [05:56].
7. Keep the kit to a phone and a laptop. For a software demo, record one continuous screen recording with a webcam bubble, face and screen together. The Clicky launch was one take of about 1:40 [03:28]; 3b/3c (MEASURED).
8. Open the video by naming the product and describing what is literally on screen, then give the one-line value proposition: "So this is Clicky. Clicky is this little blue guy that follows your cursor as you use your computer. And it's basically an AI teacher that can teach you anything." [06:07]
9. Demonstrate one concrete real use in the same take; the Clicky clip goes from Xcode to learning DaVinci Resolve [06:41-06:47] (MEASURED).
10. Write the post copy as short casual lines:
    1. a first-person claim ("I built this thing called X.")
    2. what it is, as a metaphor
    3. what it does, as a three-part list plus an analogy
    4. personal proof with a rating
    5. the video

    Care about length and story parts ("tweet poetry") [07:49], [08:06]; Insert K text.
11. Post it even when you think it is not good enough. Use an outside push (a partner, a teammate) to override the instinct. Record and post the same session; the Clicky launch went out about 15 minutes after recording [06:16], [06:31], [06:40]; 3e.
12. Ignore views. Within days, measure downloads, then the cohort still using it daily (his cut: every day for five days) [07:05], [07:17], [07:27].
13. Personally contact every retained user, learn the unexpected uses, and let them steer what you build next [07:34], [07:38].
14. Reuse one copy template for subsequent feature launches: "Today we're shipping X. / [what it does] / [why others fall short] / So we went further... / Demo:" Insert F (Jul 8, Jul 14 posts; MEASURED). This one is INFERRED from the visible posts, not said in this span.
15. Keep a running "what we shipped this week" team video on YouTube, captioned word by word and shot as a phone selfie [00:12]; Insert D.

---

## 6. Numbers (every number in the span)

| T | Number | Context | Kind |
| --- | --- | --- | --- |
| 00:17 | "millions of views" | his posts regularly | host claim; on-screen counts support it (2.9M, 2.9M, 20.9M, 4.5M, 2.5M, 1.4M; MEASURED) |
| 00:51 | 13 | age at his first company (eBay) | anecdote |
| 00:54 | "ten years later" | moved to software | anecdote |
| 00:54 / 01:58 | 2020 | his YC batch, with Aaron as partner | anecdote |
| 01:39 | 2026 | "making videos in 2026 is really good for business" | opinion |
| 01:45 | "over a decade" | making videos (host) | anecdote |
| 03:11 | $20,000 | cost of a "produced video" his selfie video would beat | anecdote / hypothetical, no data |
| 05:29 | "like five" | polished founder launch videos he saw that day | anecdote |
| 06:33 | "10 plus years" | how long he has done this | anecdote |
| 06:40 | "five minutes before dinner" | when the launch was recorded | anecdote; on-screen clock 5:23-5:24 PM, post at 5:38 PM (MEASURED) |
| 06:54 | "six months later" | side project to company | anecdote; post dated Apr 6, 2026 (MEASURED) |
| 06:58 | "nearly 3 million views" | Clicky launch post | on-screen 2.9M (MEASURED) |
| 07:18 | 7,000 | downloads after the launch video | his recollection ("I think"), not shown on screen |
| 07:19 | "four days later" | retention check point | his recollection |
| 07:27 | about 100 of 7,000 | users active every day for five days straight | his recollection. 100/7,000 = 1.4% (arithmetic) |
| 07:27 | five days | the retention window | his recollection |
| 07:34 | 100 | users he personally contacted | anecdote |
| 08:01 | "a decade plus" | years writing | anecdote |
| derived | 0.24% | 7,000 downloads / 2.9M views (arithmetic). He says "less than one percent" at 31:19 | derived |
| on-screen | 1:40 | length of the Clicky launch video (X player "0:01 / 1:40") | MEASURED |
| on-screen | 1.3K / 1.7K / 15K / 12K / 2.9M | replies / reposts / likes / bookmarks / views on the Apr 6 launch post | MEASURED |
| on-screen | 552 / 776 / 10K / 2.9M | Jul 14 screen-aware dictation post | MEASURED |
| on-screen | ~450ms | dictation speed claimed in the Jul 14 copy | MEASURED (text) |
| on-screen | 181 / 193 / 2.8K / 294K | Jul 8 spatial context post | MEASURED |
| on-screen | 1.14K subs, 21 videos | heyclicky YouTube | MEASURED |
| on-screen | 787 views, 25 likes, 0:56 | "shipping a ton and fixing 200+ bugs" | MEASURED |
| on-screen | 5.8K (2:25), 1.1K (2:22) | "introducing agent buddies", "this song is not AI-generated" | MEASURED |
| on-screen | 2.5M, 4.5M, 1.4M, 20.9M, 462K, 160K, 29.3K | Instagram grid tile views | MEASURED |
| on-screen | 3,365 likes (samin100 + 3,364), July 1, "9 weeks", 59 likes on the top comment | farza954 reel | MEASURED |
| on-screen | "$50M", Series [illegible], Menlo Ventures | foil grid tile | MEASURED |
| external | US$80,000 shoot, US$15M round | NYT "hype videos" story via The Star reprint | DOCUMENTED (search summary; page not opened) |

---

## 7. Contradictions or tensions with other parts of the interview

1. **"We know it's a hit before we start" [04:28] versus his own bad predictions.** He thought the Clicky demo "was not that good" and had to be talked into posting it [06:16-06:31]. At 14:26 he called another video "the worst video we've ever done", and it then did 3M views on Twitter. At 16:56 he says he is happy even with zero views. His hit-prediction is weak by his own account; the robust rule is "post anyway".
2. **"I record this video ... five minutes before dinner" [06:40] versus "this whole video scripted. Every line ... I wrote like three days before" [14:00] and the chapter "Why Farza Scripts Every Video" (10:30).**
   - The launch clip was recorded and posted within about 15 minutes (MEASURED clocks).
   - Either the Clicky launch was unscripted, or "scripted" can mean rehearsed lines delivered in a quick take.
   - The method document should keep both registers: same-session raw demos, and scripted premeditated videos.
3. **"I do not care about the traffic at all" [07:05] versus how YC and he present it.** The cold open is built on view counts, and the tweet says "his posts regularly get millions of views". At 31:07-31:37 he says Twitter is his worst-converting channel: the original Clicky video got 7,000 downloads on 3M views ("less than one percent"; 0.24% by arithmetic), while a 20K-view YouTube video converted at about "20" (percent). This agrees with [07:05], but it means the flagship example of this span came from his worst channel.
4. **Retention window stated two ways.** "who's like retained four days later" [07:19] versus "kept on using it every day for five days straight" [07:27]. Treat the cohort definition as approximate.
5. **"You don't need old media / a phone and a laptop" [03:26] and the anti-polish stance [05:15] versus his first hire.** He hired a filmmaker first (39:05-39:55) and does a polished launch "maybe once a quarter" (15:57). The heyclicky YouTube and Instagram inserts in this span (graded selfie footage, word-by-word captions, the "Your video editor deserves a Pakwan dinner" comment) show edited production. The Farza register is scrappy-first, not production-free.
6. **"Old media is gone" [03:08] with no evidence.** The NYT story YC cuts to (Insert A) documents startups spending big on hype videos in 2026 (DOCUMENTED, The Star reprint), so the practice is alive. His claim is about effectiveness ("way better ... engagement and traffic" [03:11]), which he asserts but does not measure.
7. **Platform lists.** At [02:23] he names "X, LinkedIn, Twitter, YouTube" (X and Twitter both; a slip). He does not mention Instagram, yet Instagram dominates the view counts shown in the cold open (20.9M, 4.5M). At 31:03 onward he says each channel converts differently.
8. **Bio detail, minor.** "Ten years later" after age 13 [00:54] puts the software start at about 23, while his intro video caption says "I was 24" (00:55.5). Not material to the method.

---

## 8. Files produced (scratch, MEASURED evidence)

- Cuts: `/tmp/farza-R1/cuts.txt`, `/tmp/farza-R1/cuts2-raw.txt` (second file is offset by +118 s).
- Keyframe sheets with exact time labels: `/tmp/farza-R1/sheet-grp-aa.jpg` to `-af.jpg`.
- Full-res frames: `/tmp/farza-R1/f/f-<sec>.jpg`, `/tmp/farza-R1/cl/c-<sec>.jpg`.
- Montages: `/tmp/farza-R1/m-open1.jpg`, `m-open2.jpg`, `m-titles.jpg`, `m-split.jpg`, `m-clicky.jpg`, `m-reshow.jpg`, `m-lip.jpg`, `m-misc.jpg`.
- Crops: `x-clock.jpg` (menu-bar clock), `x-dvr.jpg` (DaVinci segment), `x-50m.jpg`.
- Audio clip for the word-level ASR: `/tmp/farza-R1/a362.wav`.
