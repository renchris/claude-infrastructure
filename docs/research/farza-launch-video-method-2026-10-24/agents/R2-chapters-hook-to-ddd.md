# R2: catalog of interview span 07:43-17:25 (hook, scripting, first 10 seconds, demo-driven development)

Slot: R2-chapters-hook-to-ddd. Source: YC interview, Aaron Epstein (host) with Farza Majeed (guest), posted by @ycombinator on 2026-10-23 (https://x.com/ycombinator/status/2113654566776709147). Chapters covered: Write a Hook That Stops the Scroll (07:43), Why Farza Scripts Every Video (10:30), Designing the First 10 Seconds (12:04), Demo-Driven Development (15:15). I also read about 30 s past each edge (07:10-07:43 and 17:25-17:58).

## Labels and method

- **MEASURED**: I ran the command, or saw the frame, in this run. **QUOTED**: his words, with an interview timestamp `[mm:ss]` from `/tmp/farza-2026-10-24/transcript.txt`. **DOCUMENTED**: an outside source states it (URL given). **INFERRED**: my reasoning.
- **Speaker attribution** comes from the transcript content and from who is in shot. The ASR has no speaker labels, so every attribution is INFERRED unless I mark it otherwise.
- **Insert bounds** are MEASURED with a per-frame mean-luma-difference cut detector at 96x54 (threshold 12, local peak over ±2 frames) on 07:00-18:00. Output: `/tmp/farza-R2-chapters-hook-to-ddd/cuts.txt`, 85 cuts. The shared `cuts-luma.txt` was still empty when I started, and there were no shared sheets.
- **Coarse sweep**: one frame every 5 s across 07:15-17:55, using an input-side `-ss` so the labels are exact. Sheets: `/tmp/farza-R2-chapters-hook-to-ddd/s1.jpg`-`s9.jpg`.
- **Full-res reads**: every insert was read on 1920x1080 frames (`/tmp/farza-R2-chapters-hook-to-ddd/f/`).
- **Captions**: the captions burned into the played YouTube video were read from 4 fps crops of the caption band (`ytcap-0.png`, `ytcap-1.png`, `ytcap-2.jpg`). That filter emits frame k at 776 + k/4 + 0.125 s, and the labels include that offset.
- **YouTube player**: playback timecodes were read from crops of the player (`tcm.jpg`).
- **Outside source**: the YouTube metadata and auto-captions of the played video were fetched read-only with `yt-dlp --skip-download` (video id `km54y7Xd_7g`, https://www.youtube.com/watch?v=km54y7Xd_7g). The files are in `/tmp/farza-R2-chapters-hook-to-ddd/ytdl/`.
- **Prior probe E1** (`docs/research/video-understanding-human-parity-2026-10-23/agents/E1-exam-key.md`) is cited where it agrees or where I corrected it.

---

## 1. Insert map for the span (MEASURED, from cuts.txt plus full-res frames)

| # | Span | What is on screen | Layout |
| --- | --- | --- | --- |
| I0 (boundary) | before 07:43 | none; the talking-head wide and close-ups run 07:05.8-07:43.1 | - |
| I1 | 07:43.08-07:59.52 | X post by Farza @FarzaTV, the Clicky launch (verbatim in section 3.1) | Host PiP top-left, guest PiP top-right, post centred on black |
| I2 | 08:38.06-08:57.03 | X home feed (For you / Following / Build in Public), plus Chrome DevTools. A stranger's post text is swapped for the launch text (section 3.2) | Host PiP top-left, guest PiP top-right |
| I3a | 09:11.63-09:20.31 | Same launch post as I1; he plays its embedded video (section 3.3) | PiPs as I1 |
| - | 09:20.31-09:23.94 | wide two-shot | - |
| I3b | 09:23.94-09:29.90 | Same post; the video is scrubbed to its zoom | PiPs as I1 |
| - | 09:29.90-09:32.19 | wide | - |
| I3c | 09:32.19-09:43.20 | Same post; the video replays 0:00 to 0:04, the zoom on the triangle cursor | PiPs as I1 |
| I4 | 10:37.63-10:54.78 | The script document, no selection | Host PiP top-left, guest PiP top-right, white page |
| I5 | 11:04.70-11:16.13 | Same script; the opening block is selected (highlighted) | same |
| I6 | 11:32.56-11:48.71 | Same script; he selects "When t..." and then the whole opening block again. **Not in prior probe E1.** | same |
| I7 | ~12:07.3-12:17.48 | YouTube search "heyclicky", Videos tab grid (section 3.6) | Host PiP top-left, guest PiP top-right |
| I8 | 12:56.19-13:20.46 | YouTube watch page "introducing screen-aware dictation.", playing 0:02-0:19 (section 3.7) | Guest PiP top-right only (as E1 found) |
| - | 13:20.46-13:25.18 | wide (he comments over the paused video) | - |
| I9 | 13:25.18-13:35.65 | Same watch page, playing about 0:21-0:31 | Guest PiP only |
| - | 13:35.65-13:49.33 | wide | - |
| I10 | 13:49.33-13:54.50 | Same watch page, 0:32-0:37 (the reveal shot) | Guest PiP only |
| - | 13:54.50-17:43.43 | No inserts. Talking heads only: wide, host close-up and guest close-up. The sweep found no screen content between 13:55 and 17:40 | - |
| (boundary) | 17:43.43 onward | X post about Zip School classes (next chapter, outside this span) | - |

---

## 2. Itemized catalog (transcript, in time order)

Type codes: rule, technique, number, example, anecdote, opinion. "Basis" says whether the claim rests on his own experience or on evidence he points to.

### Boundary context (07:10-07:43, end of "The Clicky Launch")

| [mm:ss] | Claim | Quote (one sentence max) | Type | Basis |
| --- | --- | --- | --- | --- |
| 07:10 | He ignores congratulations and view counts. The number he cares about is downloads, then who retained. | "I actually don't care about this number at all." [07:14] | rule | Experience |
| 07:18 | After the launch video, about 7,000 people downloaded Clicky. | "I think 7,000 people downloaded it." [07:18] | number | Anecdote, from his recall ("I think"). No dashboard is shown. |
| 07:19 | He checked retention four days later. About 100 of the 7,000 used it every day for five days straight. | "about 100 people of the 7,000 kept on using it every day for five days straight" [07:27] | number | Anecdote, no evidence on screen |
| 07:34 | He reached out to and talked with each of those 100. Their unexpected uses kept him going. | "I reached out to those 100 people." [07:34] | technique / anecdote | Experience |

### Chapter: Write a Hook That Stops the Scroll (07:43-10:30)

| [mm:ss] | Claim | Quote | Type | Basis |
| --- | --- | --- | --- | --- |
| 07:43 | Much of what he does is now subconscious. The host is asked to help him draw it out. | "things I'm doing just subconsciously at this point" [07:44] | opinion | Experience |
| 07:49 | The headline is casual. Its order is: I built this thing, what it is ("an AI teacher"), what it does, why it matters. This is shown on I1. | "even just the headline, just like, it's just casual." [07:49] | technique | Experience. The on-screen post is the evidence of the form. |
| 07:59 | The structure mirrors how he thinks. He has been writing for 10+ years. | "I've been writing for like a decade plus." [08:01] | anecdote / number | Experience |
| 08:04 | "Tweet poetry": he cares about how long things are and about the separate story parts of the post. | "I care about how long things are." [08:06] | rule | Experience |
| 08:12-08:33 | (Host) His Buildspace marketing emails read as if Farza were writing to you personally, not like typical marketing. | "It felt like Farza was writing to me." [08:25] | anecdote | Host's experience |
| 08:34 | Testing depends on the platform; this demonstration is for Twitter/X. | "it depends on the platform." [08:36] | rule | Experience |
| 08:38 | **Feed-mockup test.** In his real feed, he picks some random person's post and replaces its text with his draft (I2 shows this done through Chrome DevTools), then sees whether his own eye stops on it. | "And I'll literally change this text to my tweets text." [08:42] | technique | Experience. Demonstrated on screen (MEASURED, section 3.2). |
| 08:49 | The test question is whether his own eye stopped. A stop is step one of testing. | "did I myself stop on what this is saying?" [08:52] | rule | Experience |
| 08:59 | **Number one rule, on any platform**: would I stop, would I even read the first sentence? If not, nobody goes further. | "that's kind of my number one rule, regardless of Twitter, Instagram, YouTube, anything." [08:59] | rule | Experience |
| 09:11 | **First frame chosen for the target audience.** The video opens on Xcode on purpose, because curious developers are the first audience, not video editors (even though the use case was learning DaVinci Resolve). | "It's very purposely Xcode." [09:13] | technique | Experience. INFERRED rationale: the first frame signals who the video is for. |
| 09:24 | **Zoom into the small key UI element.** The product's cursor buddy ("this little triangle") is tiny, so he zooms in to show it. | "I purposely zoom in right here to this part to show because the part is so small." [09:24] | technique | Experience. On screen: the video at 0:03-0:04 zooms to the triangle (MEASURED, section 3.3). |
| 09:32 | **Three-second window**: scrollers see the first three seconds, so the opening is "Hey everyone. So this is..." and then the zoom, to provoke "what is that?" | "Most people, when they're scrolling, see the first three seconds." [09:32] | rule / number | Experience. No retention data is shown. |
| 09:40 | **Visible motion**: he moves the cursor around so viewers see something moving on screen. | "you're moving it around so people can see that there's something moving there." [09:40] | technique | Experience (the host phrases it; Farza agrees) |
| 09:43 | He learned this from hundreds or thousands of videos that nobody cared about. | "there's hundreds and thousands of videos I've made that nobody has cared about." [09:49] | anecdote / number | Experience, rough magnitude |
| 09:53 | **Caution against formula**: don't watch this and think you must copy this exact hook. | "I don't want people to watch this video and think, oh I got to make this hook and do this and this." [09:54] | opinion | Experience |
| 09:58 | The Clicky launch video was off the cuff and almost entirely unplanned; instinct built from past lessons. | "This was almost entirely unplanned." [10:00] | anecdote | Experience. **This conflicts with "I script every video"** (section 7). |

### Chapter: Why Farza Scripts Every Video (10:30-12:04)

| [mm:ss] | Claim | Quote | Type | Basis |
| --- | --- | --- | --- | --- |
| 10:11 | (Host) Farza writes a script for all his videos, though he seems off the cuff. The question is how to be prepared without sounding stuffy or read. | "you actually write a script for all of your videos." [10:13] | example | Host's claim. Farza affirms "Totally" [10:28]. |
| 10:30 | **Read-test for scripts**: if he enjoys reading it, it will probably sound good said out loud. He adds "not always, but sometimes". | "If I like reading it, then that means it'll probably sound good if I say it out loud as well." [10:30] | rule | Experience, with his own hedge |
| 10:37 | Shows a real script for a video he recorded "yesterday" (I4, I5, I6; transcribed in section 3.5). | "this is one example of a script I wrote for a video that I did yesterday." [10:37] | example | On screen (MEASURED) |
| 10:42 | **Text-message test**: do I enjoy reading this, and would I read it if someone texted it to me? | "Would I read this if someone texted this to me?" [10:45] | rule | Experience |
| 10:54 | **He is the audience**: would he himself be interested in what the script says? | "For me, it's always I'm the audience." [10:54] | rule | Experience |
| 10:59 | He calls this script "not that strong", but he recorded it anyway because launching cadence beats polish. | "this script is actually not that strong, but I still recorded the video because you got to be launching." [10:59] | rule / anecdote | Experience |
| 11:04 | **First 10 seconds**: is it getting across what I'm doing and why it is important, then "let's get into it"? While he says this, I5 highlights the script's opening block (the "Hi" line through "energy to even know what to ask."). | "you can get across so much in just 10 seconds." [11:11] | rule / number | Experience. MEASURED that the highlight coincides. |
| 11:16 | The first 10 seconds of any video should do this. "Both these videos are one minute long." | "that's what the first 10 seconds of any kind of video should be about" [11:16] | rule / number | Experience. Which two videos "both" means is unclear. On-screen durations I measured are 1:40 and 2:00 (section 7). |
| 11:21 | **Movie analogy**: a 2-hour movie spends about 20 minutes on setup. A 1-minute video also needs setup, but only about 10-20% of it. | "for a video that's one minute long, you need to set up, but it should only be like 10, 20%." [11:27] | rule / number | Analogy, no data |
| 11:31 | He writes the setup down. His example, read aloud loosely: "hi, I want to share a new demo of our new agent interface, when talking to our users, blah blah blah", then into the demo. | "I said, hi, I want to share a new demo of our new agent interface" [11:34] | example | MEASURED: the on-screen text reads "I want to show you a demo of our new agent interface." His spoken version paraphrases it. |
| 11:43 | The script is how he thinks it through before getting in front of the camera. | "this is kind of how I think through it, you know, before I get in front of the camera." [11:45] | technique | Experience |
| 11:48 | **Why script**: the worst state is standing in front of the camera thinking "what am I saying?" with nothing to ground yourself. | "The worst part is when you're in front of the camera and you're like, what am I saying?" [11:48] | rule | Experience |
| 11:56 | (Host) The order is: script first, then the visuals. | "You start with the script and then you move on to some of the visuals." [11:56] | technique | Host's summary, not contradicted |

### Chapter: Designing the First 10 Seconds (12:04-15:15)

| [mm:ss] | Claim | Quote | Type | Basis |
| --- | --- | --- | --- | --- |
| 11:59 | (Host) The first shot is crucial: it is the first thing people see when scrolling. | "It's the first thing people see when they're scrolling." [12:00] | opinion | Host |
| 12:03 | Example: the heyclicky YouTube channel (I7). It was a brand-new channel, and this video was posted three days after the channel was created. | "we literally made it and then posted this video three days later." [12:07] | anecdote / number | Experience. The grid is on screen (section 3.6). |
| 12:12 | It is "one of our highest converting videos", despite 19,000 views. | "this is one of our highest converting videos, despite being 19,000 views." [12:12] | number | Anecdote. No conversion figure is given or shown. The 19K matches the on-screen "19K views" (MEASURED). |
| 12:16 | Same video: about 3M views on Twitter, 20K on YouTube, "some crazy amount" on Instagram. | "I think it did like 3 million views on Twitter, 20,000 on YouTube, and like some crazy amount on Instagram as well." [12:16] | number | Anecdote ("I think"). The only 2.9M on screen is the **April Clicky launch post**, not this video (section 7). |
| 12:26 | **Cross-post everywhere** to see what happens. | "we post it just everywhere just to see what happens." [12:26] | technique | Experience |
| 12:30 | **Founder on camera**: show who is making it. Show your face very clearly and your personality, be proud, and confidently tell the camera what you're working on. | "show yourself, show your face very clearly." [12:36] | rule | Experience |
| 12:44 | **Audience of one**: if you think it's cool, at least one other person will. Talk to that one person. | "I'm talking to that like one other person in that world that may think this is cool." [12:48] | rule | Experience / belief |
| 12:56 | **Opening line**: always start with a very clear "hi, this is what I'm working on". | "I always start with a very clear, hi, this is what I'm working on." [12:56] | rule | Experience. DOCUMENTED: the played video opens "Hey, so today we're adding dictation to Hey Clicky." (auto-captions 0:00-0:02.9) |
| 13:01-13:35 | The played video's audio runs under I8 and I9 (transcribed in section 3.7). | - | example | MEASURED |
| 13:10-13:13 | While the video is paused at 0:13, someone in the room says "great, that's how it works. Can you give me an example?" The line is not in the video's own captions. The guest PiP shows Farza turning toward the host, mouth mostly closed, so the speaker is probably the host. | - | anecdote | INFERRED, low confidence |
| 13:20 | Over the wide shot, the guest voices the viewer's skeptical reaction: "that's pretty cool, but this is like every other [product] I've ever seen". The video's next line pre-empts it with "many products already do this exact thing today". | "There's nothing special about this." [13:22] | technique | INFERRED: he is narrating the objection his script anticipates |
| 13:27 | The turn: "But here's the thing. When I'm writing, I often don't really know what I even want to say." Then the reveal: "So check this out. We're shipping screen-aware dictation." | (played video audio, transcript [13:27]-[13:32]) | example | MEASURED captions; DOCUMENTED auto-captions 0:25.96-0:32.75 |
| 13:35 | **Frame the problem as your own**: he never claims everyone has the problem, only that he does. He builds for himself. | "I'm not saying everyone has this problem where they don't know what to write." [13:36] | rule | Experience |
| 13:47 | The reveal line plays again (I10): "Screen aware dictation. It's pretty cool. I've never seen anything like it before. And I want to show you." | (video audio) | example | MEASURED |
| 13:53 | That is "just me being myself" ("hey, I want to show you"). | "that's just me being myself" [13:53] | opinion | Experience |
| 13:55 | (Host) You come across very natural; was that easy? | - | - | - |
| 13:59 | **Fully scripted**: every line was written about three days before shooting. | "First of all, this whole video scripted." [13:59] | rule / number | Experience |
| 14:05 | **Rehearsal by repetition**: he says each line in his head over and over, in the shower and on the way to work, asking "how should I say that line?" By shoot time he has visualized it about 10 times. | "By the time I'm in front of the camera, I've already visualized it like 10 times." [14:11] | technique / number | Experience |
| 14:16 | Afterwards he told "Vikrant" (ASR spelling, unverified), the person he makes videos with, that it was the worst video they'd made and not worth editing. Vikrant overruled him: he would edit it and they would post it. | "this is the worst video we've ever done. It's not even worth editing it." [14:21] | anecdote | Experience |
| 14:29 | **The team should force shipping**: post regardless of how cringe it feels and let the audience decide. | "It doesn't matter how cringe we think it is." [14:38] | rule | Experience |
| 14:38 | The video did 3M views on Twitter and "people went crazy". He had thought it horrible; he was wrong. | "this video did 3 million views on Twitter and people went crazy over it." [14:38] | number / anecdote | Anecdote, not shown on screen for this video (section 7) |
| 14:47 | Founders (him especially) judge their work bad and withhold it. He constantly forces himself to post; clicking post is not natural for him. | "I'm constantly forcing myself to put it out." [14:59] | opinion / rule | Experience |
| 15:03 | He was surprised anyone cared; he thought it was a simple thing. | "I was like, so surprised that people even cared to begin with" [15:09] | anecdote | Experience |

### Chapter: Demo-Driven Development (15:15-17:25)

| [mm:ss] | Claim | Quote | Type | Basis |
| --- | --- | --- | --- | --- |
| 15:14 | (Host) Demo-driven development: work backwards from the demo you want at the end. The demo proves the thing is ready, lets you test it, and is what you then publish. | "you're almost working backwards from a demo that you want at the end of it." [15:19] | technique | The host frames it as Farza's ("I've heard you talk about this"). Farza does not restate it; he pivots to "check this out". |
| 15:31 | **The "check this out" signal**: the most important thing in every company he has run is noticing the moment you tell a teammate or co-founder "check this out". That moment is what you can talk about online. | "that feeling when you're working with someone often on the team or a co-founder and you're like, check this out" [15:34] | rule | Experience |
| 15:43 | **Raw register**: that raw "check this out" is exactly how to present yourself online. | "That check this out is exactly like that raw check this out is exactly how you should be kind of presenting yourself on the internet." [15:43] | rule | Experience |
| 15:52 | **Cadence tiers**: sometimes fancier; sometimes just a guy in a simple video in the YC office; maybe once a quarter a polished launch for something he is really proud of; generally demos almost every day. | "sometimes maybe once a quarter we'll do a polished launch" [15:57] | rule / number | Experience |
| 16:06 | Daily demo cadence. | "generally we're launching like demos every single day almost." [16:06] | number | Experience |
| 16:11-16:43 | (Host) Everyone can post daily and some spend heavily on produced videos to stand out; you take the opposite approach. How do you stand out? | - | - | - |
| 16:43 | He never thinks about standing out. He wants to talk about something he finds interesting, and someone out there will too. Prior probe E1 measured a 1.15 s silence at 16:46.0-16:47.15 inside this answer. | "I never think about it like that." [16:43] | opinion | Experience |
| 16:50 | **Zero-views test at post time**: if this gets zero attention, he is still happy he posted it. This should be the 2026 mentality for founders. | "if this gets zero attention, zero views, I'm still happy I posted it" [16:56] | rule | Experience |
| 17:05 | **Post and walk away**: by the time he hits post he has forgotten it, and he checks how it did maybe a week later. | "By the time I hit post, I've already forgotten it." [17:05] | rule / number | Experience |
| 17:14-17:25 | (Host) Most people refresh incessantly; you launch and walk away. How did you get there? | - | - | - |

### Boundary after the span (17:25-17:58, start of "You Have to Take a Thousand Shots")

| [mm:ss] | Claim | Quote | Type | Basis |
| --- | --- | --- | --- | --- |
| 17:24 | He got there by putting "so much garbage" out: not bad stuff, but stuff he didn't think was good. | "I put so much garbage out in the world at this point." [17:27] | anecdote | Experience |
| 17:33 | People forget the next day; that is how attention works in 2026. | "people are going to forget the next day." [17:37] | opinion | Experience |
| 17:42 | Introduces a 2021 example, a year after YC, from his time as solo founder at Zip School (an online elementary school). He calls himself not a fantastic editor. The insert starts at 17:43.43. | "I'm not a fantastic editor." [17:54] | example | Next chapter |

---

## 3. On-screen inserts, read at full resolution

### 3.1 I1, 07:43.08-07:59.52, and I3, 09:11.63-09:43.20: the Clicky launch post on X (MEASURED, frames f-467.jpg and f-576.jpg)

- **Author**: "Farza" with two flag emoji (Pakistan and US) and a verified badge, @FarzaTV, "Boost" button.
- **Post text, verbatim** (blank lines between paragraphs):
  > I built this thing called Clicky.
  >
  > It's an AI teacher that lives as a buddy next to your cursor.
  >
  > It can see your screen, talk to you, and even point at stuff, kinda like having a real teacher next to you.
  >
  > I've been using it the past few days to learn Davinci Resolve, 10/10.
- **Metadata**: "5:38 PM · Apr 6, 2026 · **2.9M** Views". Replies **1.3K**, reposts **1.7K**, likes **15K**, bookmarks **12K**. The embedded video runs **1:40** ("0:01 / 1:40").
- **The embedded launch video, shot by shot as seen** (MEASURED from crops in `f/vid-zoom.jpg`):
  - **0:00-0:02**: a full-screen macOS screen recording of Xcode. The file shown is "BuddyDictationManager". The menu bar reads "Mon Apr 6 5:23 PM", and a console prints "Clicky: Starting... / Clicky: Version 1.0 / Permissions - accessibility: true, screen: true, mic: true...". A rounded-square **webcam bubble of Farza's face** (no cap, glasses) sits bottom-right over the screen, so face and screen appear together from frame 1.
  - **About 0:03-0:04**: the frame **zooms in** on the empty console area, where a small **blue triangle cursor** (the Clicky buddy) sits beside the system pointer. The webcam bubble stays bottom-right. Audio per the transcript: "Hey everyone. So this is... [zoom]" [09:34].
  - In the interview he plays and scrubs 0:00 to 0:04 several times (I3a-c) while explaining the first three seconds.
- **Point illustrated**: the casual headline structure (built, what it is, what it does, why it is great: "10/10"); a first frame chosen for the audience (Xcode means developers); the zoom on the tiny UI element in the first 3 s.
- **Correction to E1**: E1's transcription of the swapped post (Q9) shortened line 3 to "...and even point at stuff..." and dropped "kinda like having a real teacher next to you". The full-res read above has the full line.

### 3.2 I2, 08:38.06-08:57.03: the post-text swap (MEASURED, frames f-520.5, f-524.0, f-526.0, f-530.5)

- **Context frame (08:40.5)**:
  - X web, dark mode. Left nav: Home, Explore, Notifications, Chat, SuperGrok, Premium+, Money, History, Creator Studio, Articles, Profile, More. Signed in as "Farza @FarzaTV".
  - Feed tabs: "For you" (selected), "Following", "Build in Public".
  - The post above the target has a video (0:47) with stats 7 replies, 2 reposts, 24 likes, 1.3K views.
- **Version A, the original (08:40.5)**: author **"Aaron Ng" (verified) @localghost · 24m**. Text: **"Looks like Google is about to drop something?"** The image is a storefront with "Gemini Audio" signage.
- **Mechanism (08:44.0)**:
  - Chrome DevTools is docked right: Elements tab, Styles pane, drawer reading "What's new in DevTools 152" / "DevTools for agents".
  - The inspector tooltip on the post text reads `span.css-1jxf684.r-bcqeeo.r-1ttztb7.r-qvutc0.r-poiln3  315.8 × 18.13`. The text is highlighted as the selected node.
  - So the method is: Inspect the post's text span, then edit its text in place. This is a local, visual-only edit; nothing is posted.
- **Version B (08:46.0; E1 measured the change between 08:45.50 and 08:45.75)**: the same author line "Aaron Ng @localghost · 24m" and the same Gemini Audio image now carry the launch text, verbatim:
  > I built this thing called Clicky.
  >
  > It's an AI teacher that lives as a buddy next to your cursor.
  >
  > It can see your screen, talk to you, and even point at stuff, kinda like having a real teacher next to you.
  >
  > I've been using it the past few days to learn Davinci Resolve, 10/10.

  It is identical to the published post in 3.1, with the same paragraph breaks.
- **After the swap (08:47.5 onward)**: DevTools closes, the feed returns to full width, and he scrolls (08:50.5 shows the next post, by "Furqan Rydhan" about "Nebula"). Many small luma cuts at 08:47.5-08:53.2 are scroll motion, not shot changes (INFERRED from the frames).
- **Point illustrated** (QUOTED [08:49]-[09:10]): judge the hook in its real context, surrounded by real feed content, with a real stranger's name and avatar. Ask "did my eye stop?" Stopping on and reading the first sentence is the number one rule on every platform.

### 3.3 I3 (09:11-09:43): the embedded video's first seconds

See the shot-by-shot in 3.1. In the 09:36 frame the player shows "0:00 / 1:40" with Xcode full frame. At 09:33.5-09:43 the video shows the zoomed console with the blue triangle at "0:03 / 1:40" and "0:04 / 1:40" (MEASURED). His own cursor is visible on the interview laptop: a **yellow/orange triangle**, the current Clicky cursor (INFERRED), as distinct from the blue triangle inside the April video.

### 3.4 Script inserts I4 (10:37.63-10:54.78), I5 (11:04.70-11:16.13), I6 (11:32.56-11:48.71)

- **Layout (MEASURED)**: a white document page, black text in a humanist sans (looks like Lato; INFERRED). Host PiP top-left, guest PiP top-right, YC logo bottom-right.
- **Scroll**: there is **no scrolling within any of the three inserts**. A 2 fps difference measurement of the text region over 10:36-11:18 stays at ≤0.4 (out of 255) except where a selection appears. The same 17 lines are always visible.
- **The writing app**: E1 records the guest naming it "FreeWrite" at 45:0x. The reprise at 45:03-45:10 is scrolled one paragraph further down but shows **no lines beyond those below** (MEASURED, f-2706.jpg). It does add a screen-recording toolbar: "Recover 2 unfinished recordings · Display · Window · Area · Device · No camera · MacBook Pro... · Record system audio".
- **Selection states (MEASURED)**:
  - I4: no selection. A text caret blinks at the start of the blank line under the first sentence; the I-beam sits near "never get there."
  - I5: the block from the clipped first line through "energy to even know what to ask." is selected (blue). This is exactly while he says "In the first kind of little bit, am I getting across what I'm doing? Why is it important?" [11:04]-[11:16].
  - I6: at 11:38 only "When t" is selected. At 11:40-11:44 the whole opening block is selected again, while he says "So I write this down... hi, I want to share a new demo..." [11:31]-[11:41].
  - INFERRED: the selected block is what he means by "the first 10 seconds" / setup.

### 3.5 The script on screen: full verbatim transcription (MEASURED, full-res frames f-638.5, f-644.7, f-654, f-665.5, f-675.5, f-698, f-704, f-2706)

Spelling, punctuation and typos are exactly as shown. Blank lines are paragraph gaps on the page.

```
[top line clipped by the frame edge: only the bottoms of 2-3 glyphs visible; plausibly "Hi," (INFERRED from his spoken "hi, I want to share..." [11:34])]

I want to show you a demo of our new agent interface.

When talking to our users, we found many of them want to use agents more! But, didn't know what agents to create. Which kinda makes sense! Most interfaces coming out these days are like a blank chat boxes, and you have to put in a lot of energy to even know what to ask.

If you ask for the right things though, agents can be really magical.

But, most people never get there.

But, what if you were just given the perfect agents for whatever it is you're trying to do ro whatever goals you're trying to accomplish.

What if a filmmaker could magical get a buddy to help him apply for film festivals. What if an app developer could get a buddy to do Ggetoogle Ads for her app autonomously and earn it's first $1.

That'd be sick, and the technology is there but you gotta ask.

So, check this out.

It all starts with a little interview.

<Interview, fashion designer>

As we tell HeyClicky more about ourselves, it gets a better sense of our goals.

After the interview, it'll introduce us to our first 3 agents. Each is persistent, and
[cut off at the bottom edge of the frame in every insert and in the 45:06 reprise]
```

**Structure of the script, beat by beat** (INFERRED from the text):

1. Greeting (clipped) and **what** in one line ("I want to show you a demo of our new agent interface.").
2. **Problem from users**: they want to use agents but don't know what to create, and blank chat boxes demand effort.
3. **Stakes**: agents can be magical if you ask right.
4. **Tension**: "But, most people never get there."
5. **What-if vision** with **two concrete personas** (a filmmaker applying to festivals; an app developer running Google Ads to earn a first $1).
6. **Bridge**: "That'd be sick, and the technology is there but you gotta ask."
7. **Pivot to demo**: "So, check this out." This is the same phrase as his DDD rule [15:43], and the dictation video uses it too.
8. **Demo beats** written as stage directions in angle brackets ("<Interview, fashion designer>").
9. **Demo narration** continues: tell HeyClicky about yourself, then it introduces the first 3 agents.

The "setup" he highlights (beats 1-2) is 2 of 17 visible lines, about 75 of the roughly 260 visible words (estimated by counting lines on the frame). The page is written for the ear: short sentences, "kinda", "sick", "gotta", exclamation marks, and uncorrected typos. That fits "it's just super simple" [10:42] and the read-test [10:30].

### 3.6 I7, ~12:07.3-12:17.48: the heyclicky YouTube channel Videos grid (MEASURED, f-730.jpg)

- **Page**: YouTube search box "heyclicky", tabs Videos / Shorts / Playlists. Titles are all lowercase sentences ending in a period, and every thumbnail carries the white caret logo.

| Title | Length | Views | Age |
| --- | --- | --- | --- |
| our new logo is a keyboard shortcut. | 1:26 | 12K | 3 weeks ago |
| this is everything we shipped. | 0:43 | 1K | 3 weeks ago |
| i finally found an ai i like using. | (behind PiP) | 158K | 4 weeks ago |
| introducing spatial context. | 1:23 | 16K | 1 month ago |
| we built an ai that draws on your screen. | 2:21 | 641K | 2 months ago |
| introducing screen-aware dictation. | 2:01 | 19K | 2 months ago |
| we are a real company now (heyclicky and farzatv) | 0:54 | 1.9K | 2 months ago |
| hi i'm heyclicky | 0:34 | 1.3K | 3 months ago |

- **Thumbnails**: every thumbnail shows a face (Farza and/or team) or a screen with a face, except "hi i'm heyclicky", which shows a lecture hall slide "Lecture 7: Convolutional Neural Networks" with a blue "wanna learn more about this?" chip (MEASURED).
- **Point illustrated**: a new channel, founder face on most thumbnails, a frequent cadence (8 videos over about 3 months; estimated from the "ago" labels).

### 3.7 I8-I10, 12:56.19-13:54.50: "introducing screen-aware dictation." (MEASURED frames f-777, f-783.5, ytp-0.jpg, ytp-1.jpg, caption crops, timecode crops)

- **Watch-page metadata at recording (MEASURED)**:
  - "YouTube Premium" header, search "heyclicky".
  - Title **"introducing screen-aware dictation."**, channel **heyclicky, 872 subscribers**, **472 likes**.
  - **"19K views 2mo ago"**; description line **"Today we're shipping screen-aware dictation."**
  - Player length **2:00**.
- **Current metadata (DOCUMENTED, yt-dlp, https://www.youtube.com/watch?v=km54y7Xd_7g, fetched 2026-10-24)**:
  - Uploaded **2026-07-14**, 120 s, **21,012 views, 489 likes**; channel 1,210 subscribers.
  - Description: "Today we're shipping screen-aware dictation. / First, we built a speedy speech-to-text (very fast, ~450ms). / But, many products do this. / So we went further! Now dictate using your screen as context. In Claude Code, it writes the prompt. In G-Mail, it replies in your voice. / Try it out: https://www.heyclicky.com/".
  - INFERRED: "2mo ago" on 2026-07-14 dates the interview recording to roughly mid-September 2026.
- **Playback as shown (MEASURED timecodes)**:
  - The insert opens **paused at 0:02, muted**. The frame holds "All you gotta do is press and" from 12:56.2 to 13:01.1.
  - Play starts about 13:01. He unmutes about 13:05 (the cursor is on the volume slider, "0:07 / 2:00").
  - Paused at **0:13** from 13:10.6 to about 13:13.5, then resumed: "0:15" at 13:15.
  - It runs to about 0:19 at 13:20.46 (cut to wide), resumes about 0:21-0:31 in I9, and plays 0:32-0:37 in I10.
  - **So the video's first 2 seconds (the greeting) are not shown in the interview.**
- **First 10 seconds of the video** (words: DOCUMENTED auto-captions, word-timed; on-screen captions and shots: MEASURED where shown):

| Video time | Spoken (auto-captions) | Burned caption seen | Shot as seen |
| --- | --- | --- | --- |
| 0:00.0-0:02.9 | "Hey, so today we're adding dictation to Hey Clicky." | not shown in interview | not shown (insert starts paused at 0:02) |
| 0:02.9-0:03.6 | "All you got to do" | "All you gotta do is press and" | Medium shot, **founder facing camera**: outdoors at a wooden table, laptop open toward him, red water bottle right, glasses, dark sweater, wristwatch. Talking with both hands. Shallow depth of field, street and trees behind. |
| 0:03.6-0:05.6 | "is press and hold FN plus control," | "hold fn + control," | **Insert close-up of the keyboard**: two fingers pressing fn + control |
| 0:05.6-0:06.5 | "start talking," | "start talking, and" | keyboard, then back to face |
| 0:06.5-0:09.3 | "and whatever you're saying will stream in as text into" | "whatever you're saying," / "we'll stream in as text into" | face, medium |
| 0:09.3-0:11.1 | "whatever text box your cursor is on." | "whatever text box" / "your cursor is on." | face, medium |
| 0:11.1-0:13.0 | "For example, if I'm on Apple Notes, I can just say," | "For example, if I'm on Apple" / "Notes, I can just say," | Wider shot (different angle, darker); then a **screen recording** (macOS desktop, desert wallpaper, Notes window, yellow Clicky cursor); then keyboard close-up |
| 0:13.9-0:20.0 | "Today I have to ship three things. First, skills, second, memory, and third, this bug that this one user gave about dictation." | same words, in chunks | **Screen recording**: Notes window, the dictated text streaming in, "Dictating" indicator in the menu bar |
| 0:21.4-0:25.3 | "So, that's pretty cool, and honestly, many products already do this exact thing today." | "So that's pretty" / "cool, and honestly," / "many products already do this" / "exact thing today." | Face, medium, at the outdoor table |
| 0:25.96-0:30.6 | "But here's the thing, when I'm writing, I often don't really know what I even want to say." | "But here's the" / "thing, when I'm writing," / "I often don't really know what" / "I even want to say." | face |
| 0:30.6-0:33.5 | "So, check this out. We're shipping screen-aware dictation." | "So check this out, we're" / "shipping" / "screen-aware dictation." | **Cut to a different setup**: darker park, standing, tighter (the reveal shot) |
| 0:33.5-0:37.2 | "It's pretty cool. I've never seen anything like it before, and I want to show you. Let's say I want to write a" | same, chunked | reveal shot |

- **Caption style (MEASURED)**: white sentence-case text, 2-6 words per chunk, centred in the lower third over a soft dark band. Captions change about every 0.5-2 s and sit directly over the founder or the screen.
- **Structure of the video's opening, beat by beat** (INFERRED from the captions):
  1. Greeting plus **what** (0:00-0:03).
  2. **How**, in one gesture: fn + control (0:03-0:11).
  3. **Concrete example** in a real app (0:11-0:20).
  4. **Concede** that it is common (0:21-0:25).
  5. **Turn**, framed as a personal problem: "But here's the thing, when I'm writing..." (0:26-0:30).
  6. **"So, check this out"** plus the real feature (0:31-0:33).
  7. Demo (0:36 onward).
- **Point illustrated** (QUOTED [12:30]-[13:47]): founder face clearly on camera; open with "hi, this is what I'm working on"; frame the problem as your own.

---

## 4. Reconstructed "hook formula" (strictly from what he says)

1. **Write it casual, in his order**: "I built this thing" → what it is ("an AI teacher") → what it does → why it's important [07:49]-[07:58]. The on-screen example adds a personal proof line ("I've been using it the past few days to learn Davinci Resolve, 10/10.").
2. **Mind the length and the parts** ("tweet poetry") [08:04]-[08:11].
3. **Test it in the real feed**: put your text into a stranger's post in your own timeline (DevTools text edit) and check whether your own eye stops [08:38]-[08:58].
4. **Pass gate**: would you stop, and would you read the first sentence? On any platform [08:59]-[09:10].
5. **Pair the text with a first video frame the target audience recognises** (Xcode for developers) [09:11]-[09:22].
6. **Within the first 3 seconds, make the key thing visible**: zoom in on a small UI detail and move it so the eye catches motion [09:24]-[09:42].
7. **Do not treat it as a formula**. The skill came from hundreds or thousands of ignored videos, and this one was improvised [09:43]-[10:00].

## 5. Reconstructed "first 10 seconds template" (strictly from what he says)

- **[0-~2 s] Greeting plus "this is what I'm working on"**, face clearly on camera, confident [12:30]-[13:01]. Example: "Hey, so today we're adding dictation to Hey Clicky." (DOCUMENTED). Script example: "I want to show you a demo of our new agent interface." (MEASURED).
- **[~2-10 s] What you're doing and why it's important**, then "let's get into it" [11:04]-[11:16].
- **Keep the setup to about 10-20% of total length** (movie analogy) [11:21]-[11:31]. For 1:00 that is 6-12 s; for 2:00, 12-24 s (arithmetic).
- **State the problem as your own**, not everyone's [13:35]-[13:47]. Pivot to the demo with "check this out" (script line; dictation video at 0:30.6; DDD rule [15:43]).
- **For the visual opening, see the hook formula**: an audience-specific first frame, a zoom on the key detail, visible motion, all within 3 s [09:11]-[09:42].

---

## (a) Procedure steps implied by this span

1. Before writing anything, notice the moment you say "check this out" to a teammate. That is the thing to post [15:31]-[15:52].
2. Decide the tier: a daily scrappy demo (default) or a once-a-quarter polished launch [15:52]-[16:11].
3. Write the post headline casually, in this order: I built X → what it is → what it does → why it matters [07:49]-[07:59]. Watch length and parts [08:04].
4. Mock the post into your real feed (inspect a stranger's post, replace its text with yours) and ask whether your own eye stops and whether you would read the first sentence [08:38]-[09:10]. Rewrite until it passes.
5. Write a script for the video, every line [10:11], [13:59], about three days before shooting [14:00].
6. Test the script by reading it: do you enjoy it, would you read it if it were texted to you, would you (as the audience) care [10:30]-[10:58].
7. Make the setup (the first ~10 s; 10-20% of length) say what you're doing and why it's important, then "let's get into it" [11:04]-[11:31]. Mark the setup block in the script (as on screen in I5/I6).
8. Frame the problem in first person ("when I'm writing, I often...") and do not generalise to everyone [13:35]-[13:47].
9. Rehearse each line in your head repeatedly (shower, commute) until you have visualised the delivery about 10 times [14:05]-[14:16].
10. On camera, show your face clearly, be yourself, and open with "hi, this is what I'm working on", spoken to the one person who will think it's cool [12:30]-[13:01].
11. Choose a first frame your target audience recognises [09:11]-[09:22]. Zoom in on the small key UI element and keep it moving within the first 3 s [09:24]-[09:42].
12. Record even if the script feels weak, because cadence matters ("you got to be launching") [10:59]-[11:03].
13. Have a teammate or editor who overrules your "this is the worst video" instinct. Edit it and post regardless of cringe; let the audience decide [14:21]-[14:42].
14. Post the same video everywhere (X, YouTube, Instagram) to see what happens [12:26]. A brand-new channel is fine [12:07].
15. At post time, accept zero views as fine, forget the post, and review it about a week later [16:50]-[17:14]. Judge it by downloads and retention, not congratulations or views (boundary [07:10]-[07:30]).
16. Contact the users who retain (he talked to all ~100) [07:34]-[07:42].

## (b) Numbers

| [mm:ss] | Number | Kind |
| --- | --- | --- |
| 07:18 / 07:26 | ~7,000 downloads after the Clicky launch video | Anecdote ("I think"), not shown |
| 07:19 | retention checked 4 days later | Anecdote |
| 07:27-07:30 | ~100 of 7,000 used it daily for 5 days straight (~1.4%; my arithmetic) | Anecdote |
| 07:34 | reached out to all 100 | Anecdote |
| 08:01 | writing for "a decade plus" | Anecdote |
| on screen, I1 | Clicky launch post: 5:38 PM Apr 6, 2026; 2.9M views; 1.3K replies; 1.7K reposts; 15K likes; 12K bookmarks; video 1:40 | MEASURED (screen) |
| on screen, I2 | feed post above: video 0:47; 7 / 2 / 24 / 1.3K. Aaron Ng post: 24m old; later 1 / 5 / 209 | MEASURED (screen), incidental |
| 09:32 | scrollers see the first 3 seconds | Belief, no data |
| 09:49 | "hundreds and thousands of videos" nobody cared about | Anecdote, magnitude |
| 11:11 / 11:16 | 10 seconds to get across what and why | Rule |
| 11:19 | "both these videos are one minute long" | Anecdote. Conflicts with measured lengths (section 7) |
| 11:22-11:26 | movie 1.5-2 h; first 20 min is setup | Analogy |
| 11:29-11:31 | setup should be 10-20% of a 1-minute video | Rule |
| 12:07 | video posted 3 days after the YouTube channel was created | Anecdote |
| 12:12 | 19,000 views, yet "one of our highest converting" | Anecdote; 19K matches the screen |
| 12:16-12:20 | ~3M views on Twitter, 20,000 on YouTube, "crazy amount" on Instagram (same video) | Anecdote; only the YouTube figure is corroborated |
| on screen, I7 | channel grid views: 12K, 1K, 158K, 16K, 641K, 19K, 1.9K, 1.3K; lengths 1:26, 0:43, 1:23, 2:21, 2:01, 0:54, 0:34 | MEASURED (screen) |
| on screen, I8 | 872 subscribers; 472 likes; 19K views; 2mo ago; player 2:00 | MEASURED (screen) |
| 2026-10-24 | 21,012 views; 489 likes; 1,210 subscribers; uploaded 2026-07-14; 120 s | DOCUMENTED (yt-dlp, URL above) |
| video 0:00-0:37 | three things in the dictated example ("ship three things") | content |
| 13:59-14:05 | every line written ~3 days before | Anecdote |
| 14:16 | visualised ~10 times before the shoot | Anecdote |
| 14:38 / 14:42 | "3 million views on Twitter" | Anecdote |
| 15:57 | polished launch ~once a quarter | Anecdote / practice |
| 16:06 | demos "every single day almost" | Anecdote / practice |
| 16:56 | zero attention, zero views is still OK | Rule |
| 17:10 | looks at results ~a week later | Practice |
| 16:46.0-16:47.15 | 1.15 s silence inside his "stand out" answer | MEASURED by prior probe E1 (Q12), not by me |
| script | "first 3 agents"; "first $1" | On-screen script content |

## (c) Contradictions or tensions

1. **Scripted vs unplanned.**
   - "You actually write a script for all of your videos" [10:13] (host, affirmed) and "this whole video scripted" [13:59].
   - But the most successful launch shown, the Clicky post (2.9M views), was "almost entirely unplanned" and "off the cuff" [09:58]-[10:00].
   - Tension: the method says always script, while the headline example was improvised.
2. **"One minute long" vs measured lengths.**
   - He says "both these videos are one minute long" [11:19].
   - The two videos actually shown run **1:40** (Clicky launch, MEASURED) and **2:00/2:01** (dictation, MEASURED and DOCUMENTED). The script video's length is unknown.
3. **The 10-20% setup rule vs his own dictation video.**
   - What and how are delivered by 0:11 (inside 10 s).
   - But the real "why it's important" turn ("But here's the thing") lands at 0:26 and the reveal at 0:31-0:33 of 120 s, about 26-28% (arithmetic on DOCUMENTED caption times).
   - The 10-second rule holds for "what", not for "why".
4. **"3 million views on Twitter" attribution.**
   - He gives ~3M Twitter views for the dictation video twice [12:16], [14:38].
   - The only ~3M figure on screen (2.9M) belongs to the **April 6 Clicky launch post**.
   - I did not verify the dictation video's X numbers. He may be conflating the two (INFERRED, unresolved).
5. **"Highest converting" with no conversion data.** The claim at 12:12 comes with no metric. Elsewhere (boundary [07:14]) he insists on actual numbers over vanity metrics, but here the evidence offered is a view count.
6. **"Number one rule: am I going to stop?" [08:59] vs "I don't want people to... think, oh I got to make this hook" [09:54].** The hook is the gate, yet he warns against hook formulas. These reconcile if the test is a self-check rather than a template (INFERRED).
7. **Walk away after posting [17:05] vs close metric follow-up [07:14]-[07:34].** These reconcile as: ignore attention metrics short-term, but study downloads and retention (4-5 day window) and talk to retained users.
8. **"Show your face very clearly" [12:36] vs the Clicky launch's first frame being an Xcode screen [09:13].** His face there is only a small webcam bubble (MEASURED). Tension resolved by audience choice (developers) (INFERRED).
9. **Script read aloud vs script on screen.** He says "I want to share a new demo" [11:34], while the page says "I want to show you a demo". This suggests he delivers lines loosely rather than verbatim (INFERRED). It fits "sounds off the cuff" [10:19].
10. **Polished vs scrappy.** He does about one polished launch per quarter [15:57] and is otherwise near-daily scrappy. This is not a contradiction, but it shows the method coexists with a polished tier, matching the sibling "cinematic launch film" process.
