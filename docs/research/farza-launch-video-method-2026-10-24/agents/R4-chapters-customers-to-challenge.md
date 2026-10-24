# R4: chapters "Finding Customers on Social Media" to "The 30-Day Launch Challenge" (29:11-47:08)

Slot R4, deep reader. Source: YC interview, Aaron Epstein with Farza Majeed, posted by @ycombinator 2026-10-23 (https://x.com/ycombinator/status/2113654566776709147; YouTube v12aSIZIXUs). Span read: 28:44-47:08, which includes about 30 s before the first chapter boundary.

## How this was produced

All of the following was MEASURED this run.

- **Transcript.** I read `/tmp/farza-2026-10-24/transcript.txt` from [28:44] to the end.
- **Coarse sweep.** I pulled one frame every 5 s from 1720 s to 2825 s, each with its own input-side `-ss`, so the labels are exact. That is 222 frames at 480 px, montaged 4 across (`/tmp/farza-R4/c/`, `/tmp/farza-R4/m*.jpg`). The shared sheets and `cuts-luma.txt` were not ready: there was no `ingest-status.txt`, and `cuts-luma.txt` was 0 bytes.
- **Cut list.** I computed it myself with the skill's luma-difference one-liner (strong cut >= 20, local peak over +-2 frames) over 1700-2830 s. It found 130 cuts (`/tmp/farza-R4/cuts.txt`). Spot agreement with prior probe E1: FreeWrite insert 2702.71-2710.26 here vs 2702.70-2710.25 in E1; handshake cut 2815.28 vs 2815.271.
- **Full-resolution reads.** Every insert was read at 1920x1080 (`/tmp/farza-R4/f/`). Insert spans below run from cut to cut.

Speaker attribution is INFERRED from content and from the shot on screen, because the ASR has no speaker labels. "Aaron" is the host and "Farza" the guest. Spellings follow on-screen text where it exists. Where only the ASR has a spelling (for example "Vikrant"), it is flagged.

**Labels.** MEASURED means seen or read this run. QUOTED means his words, with a timestamp. DOCUMENTED means a source states it. INFERRED means my reasoning. EXPERIENCE means Farza's own account, with no external evidence cited. ON-SCREEN means an artefact shown in the edit that corroborates a spoken number.

---

## 1. Itemised catalogue (time order)

### 1a. Boundary run-in (28:44-29:11, end of "Show What You're Actually Building")

| # | [mm:ss] | Claim | Quote (at most one sentence) | Type | Basis |
|---|---|---|---|---|---|
| 1 | 28:44 | Daily prompt: ask what you did today that made you smile or was interesting, talk about it, show it, post it, close the app and go back to work. | "ask yourself what's something i did today that made me smile or was interesting" [28:44] | technique | EXPERIENCE |
| 2 | 28:56 | In 2026, "launching" just means showing your work. A TechCrunch or NYT launch was also showing your work; now you can do it every day and build an audience from it. | "that's what it means to be launching i think in 2026 just to show your work" [28:56] | opinion / rule | EXPERIENCE |

### 1b. Finding Customers on Social Media (29:11-31:02)

| # | [mm:ss] | Claim | Quote | Type | Basis |
|---|---|---|---|---|---|
| 3 | 29:09 | (Aaron) The common objection: "I sell to businesses or procurement, not Gen Z, so TikTok and Instagram aren't my channel." His reading of Farza's view: real people who work at companies are on these platforms. | "a lot of people think well i'm not targeting gen z" [29:09] | opinion (host) | n/a |
| 4 | 29:36 | (Farza) A large majority of the world, billions of people, browse these platforms. | "a large majority of the world is browsing through these platforms" [29:36-29:42] | opinion | EXPERIENCE, no source given |
| 5 | 29:42 | Example: design agencies loved Clicky. Three found it organically, so the question became how to get more of them. | "we found that design agencies really loved our product like three of them that found us naturally" [29:42-29:48] | example | EXPERIENCE |
| 6 | 29:53 | Farza turns the question to Aaron ("founder mode"). Aaron gives the default: search LinkedIn for people listing a design agency as employer, go to their communities, specialised design websites. | "probably the default for a lot of people is like go look on linkedin" [30:00] | anecdote (host) | n/a |
| 7 | 30:14 | (Farza) Do those things too, but also ask whether design-agency founders are on TikTok, Instagram and YouTube. The answer is probably yes. | "you should do those things but at the same time do you think a design agency founders on tiktok or instagram or youtube" [30:14-30:19] | rule | EXPERIENCE |
| 8 | 30:23 | Technique: TikToks that open by calling out the exact niche, then show something. He did not have the account open, so no TikTok is shown on screen (MEASURED: no insert between 29:11 and 31:13). | "hey are you the founder of a design agency stop right there let me show you something really cool" [30:33] | technique (niche call-out hook) | EXPERIENCE |
| 9 | 30:38 | Result: about 50 design-agency leads from TikTok alone. | "that's how we found like 50 design agency leads" [30:38] | number / example | EXPERIENCE (anecdote, no data shown) |
| 10 | 30:43 | The videos did not go viral: about 4,000 views each on average, but targeted views. | "they each on average had like 4 000 views but it's probably 4 000 targeted" [30:43-30:48] | number | EXPERIENCE |
| 11 | 30:48 | The goal is never to go viral. It is to talk about what you're working on in front of an audience that actually cares. ASR reads "the goal of michael"; the intended word is probably "mine" (INFERRED). | "the goal of michael is never to go viral" [30:48] (ASR) | rule | EXPERIENCE |

### 1c. Which Platforms Actually Convert? (31:02-39:01)

| # | [mm:ss] | Claim | Quote | Type | Basis |
|---|---|---|---|---|---|
| 12 | 31:03 | Every channel is different. | "every channel is different" [31:03] | rule | EXPERIENCE |
| 13 | 31:05 | Twitter/X has been his worst-converting channel historically, after about 10 years of posting there. | "twitter is our worst ... the worst conversion of any channel" [31:05-31:13] | opinion / number | EXPERIENCE |
| 14 | 31:13 | The original Clicky video got 7,000 downloads on 3 million views, which he calls "less than one percent" (7,000 / 3,000,000 = 0.23%, INFERRED arithmetic). | "the original clicky video got 7 000 downloads on 3 million views" [31:13] | number | 3M is ON-SCREEN as 2.9M (insert I-1). The 7,000 downloads is EXPERIENCE: no analytics shown. |
| 15 | 31:23 | The screen-aware dictation video got 2.9M views on Twitter, but conversion to accounts was "horrendously low". | "2.9 million views on twitter but the conversion rate onto those people actually making accounts was horrendously low" [31:23-31:30] | number | 2.9M is ON-SCREEN (I-2). The conversion rate is not given as a number. |
| 16 | 31:30 | The same video on YouTube: 20,000 views, but about 20% of viewers downloaded the app. ASR "like 20" is read as 20 percent from context ("the chances ... was 20"). | "this youtube video has 20 000 views but do you know what the conversion rate on this video is it's like 20" [31:30-31:37] | number | 19K views is ON-SCREEN (I-3). The 20% conversion is EXPERIENCE, no analytics shown. |
| 17 | 31:45 | Why: on Twitter he is "just scrolling through random stuff", which is low intent. He found YouTube surprising. | "i'm on twitter i'm just like doom scrolling basically" [31:45-31:50] | opinion | EXPERIENCE |
| 18 | 31:54 | YouTube is, "for most companies", the best channel for conversion. | "historically actually youtube is for most companies the best performing channel in terms of conversion" [31:54-32:00] | opinion | Presented as general knowledge, no source cited |
| 19 | 32:00 | His YouTube numbers are small (872 subscribers, 20K views, "I'm not Mr Beast") but produce "a very real number of signups". | "872 subscribers 20k views like i'm not mr beast" [32:05] | number | ON-SCREEN (I-4: 872 subscribers, 19K views) |
| 20 | 32:12 | YouTube keeps performing: it is a library that lasts decades. Twitter gives you one moment. | "this youtube is a library that will last for decades twitter you got your moment once and you're gone" [32:16] | rule / opinion | EXPERIENCE |
| 21 | 32:22 | Instagram matters most: about 70% of Clicky's traffic. | "all of our traffic i think 70 of our traffic is instagram" [32:22] | number | EXPERIENCE (hedged "I think"), no analytics shown |
| 22 | 32:28 | Look down the funnel at how many actually converted, not at virality. | "down the funnel how many people actually converted it's worth checking out" [32:32-32:38] | rule | EXPERIENCE |
| 23 | 32:38 | Sequence: make your first couple of videos, then add per-channel tracking. | "make the first couple of videos but then start to ask themselves" [32:43] | technique | EXPERIENCE |
| 24 | 32:47 | Per-channel tracking link: the Instagram link in bio is heyclicky.com/ig, so he can measure the conversion of everyone who hits /ig. | "our link in bio is slash ig why because then i can track" [32:47] | technique | ON-SCREEN (I-5: "heyclicky.com/ig") |
| 25 | 32:53 | Mobile hand-off: visitors who land on their phone get a button to email the download to themselves. He tracks that click rate as its own conversion. Clicky is a desktop app, which INFERRED explains why this matters. | "we have a little button that lets them send it to them uh themselves over email how many of them click that" [32:58-33:02] | technique | EXPERIENCE |
| 26 | 33:02 | Posting on every channel shows you both where you get views and which channel holds the audience you want. For Clicky that is Instagram "by far ... not even close". | "for us it is by far instagram um and it's it's not even close" [33:13-33:18] | rule / opinion | EXPERIENCE |
| 27 | 33:18 | (Aaron) "Same content for every channel?" (Farza) Videos are made for one platform and cross-posted. Most are made for Instagram and posted to Twitter; some are made for Twitter and posted to Instagram. | "most of our videos we make for instagram but then we post to twitter" [33:23] | technique | EXPERIENCE |
| 28 | 33:35 | The difference: Twitter "generally doesn't like vertical videos", so it gets 16:9. | "twitter generally doesn't like vertical videos it's like 16.9" [33:35-33:39] | rule | EXPERIENCE |
| 29 | 33:39 | Example: the drawing video ("a system that can draw directly on your screen ... polygons, arrows") is "super optimized for twitter". | "this is super optimized for twitter" [33:50] | example | ON-SCREEN (I-6, I-7) |
| 30 | 33:50 | Muted-scroll test: watch your own post muted, as if scrolling, and say aloud the few words your brain picks up ("guy in front of blackboard, AI, draw, screen ... Claude Opus, demo, click"). Nobody reads the whole post text. | "let's just watch it muted and imagine i'm scrolling my feed" [33:50] | technique | EXPERIENCE (performed live on screen, I-7) |
| 31 | 34:07 | Nobody reads the whole post. | "nobody's reading this entire this entire damn thing" [34:07] | opinion | EXPERIENCE |
| 32 | 34:11 | Surprise: the exact same Twitter-optimised 16:9 video did better on Instagram, with "millions of views", even though letterboxed on a phone "it looks even worse". | "we posted the exact same thing to uh my instagram and it performed even better" [34:17] | example / number | IG reel shows 27.4K likes (I-8). "Millions of views" is not legible on screen. |
| 33 | 34:34 | (Aaron) Farza has a very high bar and also puts out a lot. He has taste, and a short attention span that he uses as a filter. | "you just naturally have a very uh short attention span" [34:55] | opinion (host) | n/a |
| 34 | 35:06 | (Farza) Either he has good taste or he just puts out so much that some videos hit. He thinks it is more the latter: volume plus iteration. | "either i have good taste or i just put out so much stuff and some of them just hit" [35:06] | opinion | EXPERIENCE |
| 35 | 35:23 | Survivorship caveat: "we're looking at the stuff that's working". Much hasn't worked, e.g. the old Zip School videos. | "so much hasn't worked right like my old zip school videos like nobody cared" [35:23] | anecdote | EXPERIENCE |
| 36 | 35:28 | Example of a "super simple video, basically just a quick story": he found that GPT Realtime could generate shell commands and control the computer in real time, and filmed it. | "i found out that with gpt real time you could generate shell commands and control your computer in real time" [35:32] | example | ON-SCREEN (I-10, I-11) |
| 37 | 35:43 | The Spotify/Stripe "no hands" demo is played. Shot list in section 3 (I-11). | "check this out no hands" [35:43] | example | MEASURED |
| 38 | 36:17 | Origin: "one little moment in the day" when he realised the model could do this. He didn't check whether anyone had done it first and just made the video; it turned out to be novel. | "i didn't check if anybody did it before i was just like i'm gonna make a video" [36:25-36:31] | technique (record the moment of discovery) | EXPERIENCE |
| 39 | 36:36 | The demo shows his own first real use case (play a song, lower the volume). | "that's exactly the first use case that i had as a user myself" [36:36-36:42] | technique / rule | EXPERIENCE |
| 40 | 36:42 | Build and film for the version of yourself who is watching: if you think it's cool, others will too. | "if i think that's cool i think someone else would too" [36:46] | rule | EXPERIENCE |
| 41 | 36:50 | The same video: 3.8M views on Twitter, 4.6M on Instagram. | "3.8 million views on twitter really good but again then instagram 4.6 million" [36:50] | number | X 3.8M is ON-SCREEN (I-12). The IG 4.6M is not clearly tied to this reel on screen (I-13). |
| 42 | 36:57 | Myth: Instagram needs "a lot of quick edits". This video has "not a single cut". Speaker probably Farza (INFERRED). | "there's not a single cut in this video" [37:02] | opinion / rule | MEASURED consistent: the playback I-11 is one continuous screen recording with a webcam bubble. The only luma cuts inside it (35:52.54, 36:14.89, 36:15.73) are screen-content changes, not edits (INFERRED from frames). |
| 43 | 37:06 | (Aaron) No cuts, but there are beats. Hook "hey, no hands", then the song plays, then the music is lowered so he can keep talking, then the Stripe dashboard ("I wonder how much money they made"). | "there's no cuts in the video but there are beats in the video" [37:06] | technique (beat analysis, host) | MEASURED: the beats match the shot list (section 3) |
| 44 | 37:18 | (Farza) The beats are deliberate. | "oh of course that's all purposeful" [37:18-37:22] | rule | EXPERIENCE |
| 45 | 37:31 | Keep the story moving; do not try to "keep attention". The viewer should feel "where is this going, come on, keep going", like someone telling a story you want to reach the end of. | "i'm always just trying to keep the story moving yeah i'm not trying to keep your attention that's actually the wrong way to look at it" [37:31-37:39] | rule | EXPERIENCE |
| 46 | 37:53 | Some videos are made on purpose for the no-attention-span audience. Example: the "It has been 9 weeks" reel, played on screen (I-14). | "some of my videos are purposely made to just kind of like appeal to like the audience that just has no attention span" [37:53] | technique | ON-SCREEN |
| 47 | 38:10 | Second beat example: the "two weeks ago I was in my apartment" reel, played (I-15). | "two weeks later i built this thing that's now being used by thousands of people every single day" [38:16-38:20] | example | ON-SCREEN (analytics chart in reel) |
| 48 | 38:24 | Viewer checkpoints: he imagines the viewer asking at each beat "am I here? am I still watching?" He makes a chopping hand gesture (MEASURED, frame 2306 s). | "i literally think about it like like like this ... am i here yeah am i still watching" [38:24-38:27] | technique | EXPERIENCE |
| 49 | 38:30 | Beat sense becomes obvious with repetition. A 19-year-old at the office "has this built into his head"; most people who make many videos develop a "beat system". | "most people who work on videos a lot have this little beat system in their head" [38:44] | opinion / anecdote | EXPERIENCE |

### 1d. Why Farza's First Hire Was a Filmmaker (39:01-40:49)

| # | [mm:ss] | Claim | Quote | Type | Basis |
|---|---|---|---|---|---|
| 50 | 38:48 | (Aaron) Farza invests a large share of a small early team in making videos regularly. | "a large portion of it is actually built to help you create and produce and get these videos out the door on a regular basis" [38:54] | opinion (host) | n/a |
| 51 | 38:59 | (Farza) He is "okay at videos"; others are much better. | "i'm okay at videos there are people out there who who are way better at me" [39:00-39:05] | opinion | EXPERIENCE |
| 52 | 39:05 | Before starting the company he knew the first two hires: number one a filmmaker, number two an engineer, "or whatever order they can come in". | "it's going to be number one a filmmaker and number two an engineer" [39:10] | rule | EXPERIENCE |
| 53 | 39:22 | Reason 1: he does not want to spend a lot of attention every day on making videos, and no founder does. In the early days you have to, though. | "i don't want to put a ton of attention every day on making videos" [39:22] | rule | EXPERIENCE |
| 54 | 39:31 | Early Clicky: he forced himself to make videos and "stuff" every day. | "i'm forcing myself to just make videos and make stuff every day" [39:35] | anecdote | EXPERIENCE |
| 55 | 39:40 | Reason 2: the filmmaker's full-time job is to observe what the team is doing, help it launch, and make it look good and "come off properly". | "this would be really great if someone's full-time job at my company was to kind of observe what we were doing and help us launch" [39:40] | rule (role definition) | EXPERIENCE |
| 56 | 39:55 | Previous company (Buildspace, per the tweet): the film team was 2 people out of a 7-person team. | "our film team was two people we were only like a seven person team" [39:55-39:59] | number | EXPERIENCE |
| 57 | 39:59 | At Clicky, at one point: 3 people making videos and 1 engineer. | "we had three people making videos and one engineer" [40:03] | number | EXPERIENCE |
| 58 | 40:04 | Thesis: code is now easy to produce, but talking coherently about your work in front of an audience is harder than ever. | "it's harder than ever to actually talk about what you are doing in a coherent way in front of an audience" [40:10] | opinion | EXPERIENCE |
| 59 | 40:17 | The product can be cloned "in like two minutes"; the audience, community and energy cannot. | "what's really hard to clone is the audience and the community" [40:22] | opinion | EXPERIENCE |
| 60 | 40:27 | Hypothetical: an audience of 100,000 people in your niche (enterprise AI, photography, ...) would be useful. | "if you had an audience around your company i'll say a hundred thousand people" [40:27-40:30] | number (hypothetical) | n/a |
| 61 | 40:39 | Today a new-feature video makes "thousands of people flood my app". | "i can make a video now about a new feature and like thousands of people flood my app" [40:39] | number / anecdote | EXPERIENCE |

### 1e. The Video Stack (40:49-45:41)

Every tool, piece of gear, app and setting he names or shows. Prices are only as he states them; another slot researches prices.

| # | [mm:ss] | Tool / item | What he says it is for | Quote | Basis |
|---|---|---|---|---|---|
| 62 | 40:52 | **Screen Studio** (desktop screen recorder) | Level 1, demos on the computer ("what I'm hacking on that day"). Records the screen and local audio, "makes your cursor look good". "Made by some indie hacker." | "i always use this thing called screen studio" [40:53] | EXPERIENCE. A recorder toolbar is on screen 41:00.22-41:06.93 (I-17). |
| 63 | 41:03 | Screen Studio price | "I think it costs like 30 bucks." | "i think it costs like 30 bucks" [41:03] | EXPERIENCE (hedged) |
| 64 | 41:07 | **iPhone selfie camera** | Level 2, videos that include him "in a more native way": "literally just a selfie camera", record himself talking, then post. | "i'll just pull my iphone literally just a selfie camera and just record myself talking" [41:13] | EXPERIENCE |
| 65 | 41:17 | **Edits** (Instagram's video-editing app, on the phone) | He edits on the phone "a good amount". | "instagram's editing too it's called edits" [41:22] | EXPERIENCE |
| 66 | 41:28 | Level 2 needs nothing else | "That's the iPhone, nothing else required." | "so that's the iphone uh nothing else required" [41:26] | EXPERIENCE |
| 67 | 41:28 | **Sony FX3 and Sony FX30** | Level 3, "more thought through, cinematic". ASR is garbled: "sony fx3 and sony fx30 or sony fx3 the cheaper one". He presumably means the FX30 is the cheaper one (INFERRED). | "that's where i use my sony fx3 and sony fx30" [41:38] | EXPERIENCE |
| 68 | 41:38 | **DJI mic** (wireless lav) | Paired with the Sony bodies. A DJI-style mic is also seen in the cold-open YouTube clip (prior probe E1, Q2). | "along with a dji mic" [41:38] | EXPERIENCE |
| 69 | 41:46 | **Rule: audio quality is the most important thing in any video**, whether it is "a shitty loom", a small video or the iPhone. | "if your audio is bad i'm bouncing" [41:55] | rule | EXPERIENCE |
| 70 | 42:00 | Corollary: he will watch a 720p demo from "a weird room in a basement" if the audio is crisp and the work is interesting. Picture quality and looks don't matter. | "I've watched some demos that are like 720p" [42:00] | anecdote / rule | EXPERIENCE |
| 71 | 42:17 | Buy "one of those super cheap DJI mics", used online is fine, or any mic that is not the MacBook mic or AirPods mic ("those don't count"). | "any mic that's not your MacBook mic or your AirPod mics, those don't count" [42:24-42:27] | rule | EXPERIENCE |
| 72 | 42:32 | **DaVinci** (DaVinci Resolve) | Editing on the laptop. The 2.9M-view Clicky launch post also mentions learning "Davinci Resolve" (I-1). | "for editing on my actual laptop, I use DaVinci" [42:32] | EXPERIENCE + ON-SCREEN mention |
| 73 | 42:37 | **Vikrant** (filmmaker; spelling from ASR only, not shown on screen) | "Maybe the most important part of my stack." He made all the HeyClicky videos. | "Vikrant has made all the HeyClicky videos." [42:41] | EXPERIENCE |
| 74 | 42:51 | Every video shown in the interview was made by Vikrant, except the "bad Zip School ones" Farza made himself. | "Every video we just looked at, apart from the bad Zip School ones, which were made by me, are made by Vikrant." [42:51-42:53] | anecdote | EXPERIENCE. This matters for the method: see Contradictions. |
| 75 | 42:55 | Having someone talented at filmmaking, storytelling and writing next to you is "the biggest bonus a founder could have today". | "having a person that is actually talented at filmmaking, storytelling, writing next to you is like the biggest bonus" [42:55-43:01] | opinion | EXPERIENCE |
| 76 | 43:05 | Workflow with Vikrant: brainstorm per feature ("we made this feature, how should we make the video, where should we do it"). Vikrant brings shot ideas and hook ideas. | "Vikrant is actually the main guy that's like, hmm, I had this shot idea." [43:17-43:19] | technique | EXPERIENCE |
| 77 | 43:26 | Division of labour: Farza usually brings the script, the song and the vibe. | "often I'm the guy that's bringing the script and the song and the vibe" [43:26-43:28] | technique | EXPERIENCE |
| 78 | 43:31 | Find which parts of video-making you're good at. For him: writing and music. Vikrant does "literally everything else": shooting, picking the set, editing, motion graphics. | "for me, I find I'm really good at writing and I'm really good at the music" [43:37-43:39] | rule / anecdote | EXPERIENCE |
| 79 | 43:51 | That frees the founder for growth, hiring and product. | "I can go back to focusing on growth, hiring, making the product." [43:53] | rule | EXPERIENCE |
| 80 | 44:03 | If you can't afford a filmmaker (solo, or with a co-founder): look at his old Zip School videos and "old shitty videos", and just start. | "go back to my old Zip School videos" [44:11] | rule | EXPERIENCE |
| 81 | 44:20 | The most important thing about launch videos is to start. Doing it every day makes it natural, and hopefully you can later hire someone better than you. | "you got to start" [44:25] | rule | EXPERIENCE |
| 82 | 44:35 | Parallel: he is no longer the core engineer either. The same goes for filmmaking and design: hire people better than you. Early on, the founder does everything (taxes, design, filmmaking). | "I'm not the core engineer." [44:38] | anecdote / rule | EXPERIENCE |
| 83 | 44:51 | "You can't be a little baby about it": take out the camera and post cringe. | "in order to not be cringe, you must first be cringe" [44:56] | rule | EXPERIENCE |
| 84 | 44:59 | **FreeWrite** (freewrite.io) | All of his writing. Free to download, "my app", "I built it actually just for this purpose", "free, open source". | "for all of my writing, I always use this thing called FreeWrite" [44:59-45:01] | EXPERIENCE; ON-SCREEN (I-18). |
| 85 | 45:10 | Writing is very important: spend as much time as possible writing before you record. | "spend as much time possible before the video writing it" [45:14] | rule | EXPERIENCE |
| 86 | 45:20 | Gate on experience: on your first video, don't worry about writing. By the 15th, 20th or 30th video, write for 10 minutes about what it should be, then record. | "Try writing for just 10 minutes about what it should be and then record it." [45:27-45:29] | rule / number | EXPERIENCE |
| 87 | 45:31 | The more you think it through beforehand, the better it gets: you "catch a bad idea" before the camera. | "you can catch a bad idea before it gets here" [45:36] | rule | EXPERIENCE |

### 1f. The 30-Day Launch Challenge (45:41-47:08)

The rules as he states them, in his order:

| # | [mm:ss] | Rule | Quote |
|---|---|---|---|
| 88 | 45:46 | Who it's for: you have never really made videos or talked about your work online, but you have been hacking, tinkering or working on something. | "if you've never really made videos or if you have never really talked about your work online, but you've been hacking" [45:48-45:55] |
| 89 | 45:58 | "Super simple." Every day, spend 10 minutes. | "Every day, just spend 10 minutes" [46:00] |
| 90 | 46:01 | Device: your phone, iPhone or Android, either is fine. In the wide shot he holds a black phone up at about 46:07 (prior probe E1 reserve; coarse frame c-2765 MEASURED). | "take your phone out, iPhone or Android, it's okay" [46:01-46:02] |
| 91 | 46:04 | Content: record yourself talking about what you were doing, or what you did that day. | "just record yourself, talking about what you were doing, what you did that day" [46:04-46:06] |
| 92 | 46:08 | Post it to your social media of choice: Instagram or TikTok. | "post it to your social media of choice, Instagram, TikTok" [46:08-46:10] |
| 93 | 46:12 | Optional: make a new Instagram account so your existing followers don't know. | "Make a new Instagram account so your existing followers don't even know." [46:12-46:15] |
| 94 | 46:15 | Do it for 30 days straight. | "do that for 30 days straight" [46:17] |
| 95 | 46:20 | His promise: within the 30 days, one video will "probably" pass 1,000 views. | "within those 30 days, one of those videos will surpass probably 1,000 views" [46:22-46:24] (EXPERIENCE, no data) |
| 96 | 46:26 | Then look back, ask why that one did 1,000 views, base the next video on it, and keep improving. | "you can make the next one based off the one that got 1,000 views" [46:33-46:36] |
| 97 | 46:39 | Restated: 30 days straight, every day, one video. | "30 days straight, every day, one video." [46:40-46:41] |
| 98 | 46:42 | Send it to him and he will like it. | "Send it to me. I'll be one of your likes" [46:42-46:43] |
| 99 | 46:47 | (Both) It has never been easier to get the message out. | "it's never been easier to do this" [46:47] |
| 100 | 46:52 | (Aaron) Thanks Farza. The ASR's "Thanks, Ahmed" [46:55] is probably "Thanks, Aaron" (INFERRED, ASR error). The final "[47:07] Thank you." is an ASR hallucination over silence (prior probe E1, Q24). | n/a |

---

## 2. On-screen inserts in the span (all MEASURED at 1920x1080)

The layout is constant for every screen insert from 31:13 on: host webcam picture-in-picture top-left, guest top-right, YC "Y" bug bottom-right (MEASURED). The only exception is the 33:44-33:49 full-frame video, which also carries the PiPs. There are no inserts from 28:44 to 31:13.59: wide shots and singles only.

| ID | Span (cut to cut) | What is on screen (verbatim where legible) | Point illustrated |
|---|---|---|---|
| **I-1** | 31:13.59-31:19.93 | X profile timeline, header "Farza 🇵🇰🇺🇸 ✓, 1,511 photos & videos". Post text: "I built this thing called Clicky. It's an AI teacher that lives as a buddy next to your cursor. It can see your screen, talk to you, and even point at stuff, kinda like having a real teacher next to you. I've been using it the past few days to learn Davinci Resolve, 10/10." Embedded video 0:00/1:40: Xcode ("BuddyDictationManager") with a webcam bubble bottom-right. Counts **1.3K replies, 1.7K reposts, 15K likes, 2.9M views**. The post date is scrolled out of view. Below it: "@FarzaTV · Apr 4 This is Farzapedia. I had an LLM take 2,500 entries from my diary, Apple Notes, and some iMessage convos to create a personal Wikipedia for me..." | "The original Clicky video got 7,000 downloads on 3 million views" (Twitter = worst conversion). The on-screen figure is 2.9M. |
| (wide) | 31:19.93-31:24.14 | Two-shot | n/a |
| **I-2** | 31:24.14-31:34.94 | Same X timeline scrolled. The post above shows 219 / 118 / 2.5K / 342K. Then "@FarzaTV · Jul 14 Today we're shipping screen-aware dictation. First, we built a speedy speech-to-text (very fast, ~450ms). But, many products do this! So we went further. Now dictate using your screen as context. In Claude Code, it writes the prompt. In G-Mail, it replies in your voice. Demo:". The video plays: at 31:26, presenter at an outdoor café table with a red water bottle, burned caption "Hey, so today we're adding", 0:01/2:00; by 31:30, a keyboard close-up of fingers on fn+control, caption "hold fn + control,", 1:55 remaining. Counts **552 replies, 777 reposts, 10K likes, 2.9M views**. Next post: "@FarzaTV · Jul 8 Today we're shipping spatial context. This lets you draw directly on your screen + pass it as context to the model. AI can easily analyze screenshots. But, it has no idea where exactly you..." | "Screen-aware dictation, 2.9 million views on Twitter, conversion horrendously low." Shows an announcement-post format: one-line "Today we're shipping X", then a problem/"we went further" paragraph, then "Demo:". |
| **I-3** | 31:34.94-31:41.49 | YouTube watch page, search box "heyclicky". Video "introducing screen-aware dictation." paused at 0:40/2:00, burned caption **"I can just say, "HeyClicky,"**. Presenter outdoors in a dark sweatshirt, gesturing. Channel **heyclicky, 872 subscribers**, Subscribe button, **472 likes**, description "**19K views 2mo ago** Today we're shipping screen-aware dictation. First, we built a speedy speech-to-text (very fast, ~450ms) ...more". | "This YouTube video has 20,000 views, conversion about 20%." |
| (wide/singles) | 31:41.49-32:03.60 | n/a | n/a |
| **I-4** | 32:03.60-32:07.64 | The same YouTube page scrolled. Adds **"69 Comments"**; cursor on "872 subscribers". | "872 subscribers, 20K views, I'm not MrBeast." |
| **I-5** | 32:46.06-32:50.90 | 32:46.06-32:47.93: incidental Instagram browsing. First an unrelated IG ad (getsuperscaleai, "You don't need 10 AI apps to run your Shopify ads..."), then a different account's reels grid (52.7K, 17.2K, 21.5K, 20.1K, 14.5K, 19.3K views). From 32:47.93: **Instagram profile "_heyclicky"**, name "heyclicky", **48 posts, 35.4K followers, 5 following**, bio "your friendly neighborhood cursor", link **"heyclicky.com/ig"**, Threads "_heyclicky", "Followed by nokhezz_, samin100 + 82 more". Reels tab: thumbnails "on and tell me what to tak[e]" / "I'm on g...", "I recently made this short film but", "and we'll get you", a dim room with a TV. Status-bar URL "instagram.com/_heyclicky/followers/mutualOnly". Cursor hovers the link. | "Our link in bio is slash ig." The flashed ad and other grid are navigation residue left in by the editor (INFERRED). |
| (singles/wide) | 32:50.90-33:44.24 | Includes a Farza close-up 33:42.16-33:44.24 | n/a |
| **I-6** | 33:44.24-33:49.62 | Full-frame 16:9 playback of the drawing video. A man at a chalkboard in a dark zip fleece with a lav mic; a chalk browser-window wireframe. Burned captions "so we built a system that can draw" (33:45) and "It can draw polygons, arrows, curved" (33:48), with a close-up of his hand drawing a triangle and arrow in chalk. | "We built a system that can draw directly on your screen ... polygons, arrows". |
| (wide) | 33:49.62-33:54.71 | n/a | n/a |
| **I-7** | 33:54.71-34:06.39 | X timeline, full desktop layout (left nav with "SuperGrok, Premium+, Money, History, Creator Studio, Articles, Profile"; "You might like" and "What's happening" on the right). Post above: 181 / 193 / 2.8K / 293K. **"@FarzaTV · Jun 16 We built an AI that can draw on your screen. It's a true personal tutor. Using Claude Opus we're able to draw polygons, point with pixel perfect accuracy, and walk users through complex steps directly on their screen. Here's me learning Pythagorean Theorem + FL Studio. Demo:"** Video 0:06/2:20, caption "It can draw polygons, arrows, curved". Counts **404 replies, 457 reposts, 5.1K likes, 589K views**. Below: "@FarzaTV · May 30 Watch me control my computer with just my voice. This is the future of operating systems. No hands. GPT-Realtime 2.0 is very, very underrated. Demo:". | "Optimized for Twitter": the muted-scroll test. He reads out "guy in front of blackboard, AI draw screen ... Claude Opus demo click" [33:54-34:07]. |
| (wide) | 34:06.39-34:28.83 | n/a | n/a |
| **I-8** | 34:28.83-34:33.83 | Instagram reel modal, **farza954 ✓ "Original audio"**, caption "Built an AI that can draw and..." 14w. The same drawing video, letterboxed 16:9 inside the vertical frame, caption "we built a system that can draw", collaborator avatars (farza954, heyclicky logo, a third account). Comments: jecastillof 🔥🔥🔥; farinadil "Love it! Give me more deets, I'll start sharing that with my students too. Well done Zain" (20 likes); rajyagurup "That's impressive!"; farhajmayan "Let's gooooo". **"Liked by samin100 and 27.4K others", June 16.** "View insights" and "Boost reel" buttons (owner view). 34:31.08-34:33.21 is a white loading flash. At 34:33.5 the reel shows small in a narrow phone-width layout. Grid tiles at the left edge: "We made our first beat, 2.5M", **"4.6M"**, 61.9K, 29.8K, 22.5K. | "We posted the exact same thing to my Instagram and it performed even better ... on their phone it looks even worse, it looks like this" [34:17-34:30]. |
| (singles) | 34:33.83-35:29.97 | n/a | n/a |
| **I-9** | 35:29.97-35:30.43 (0.46 s flash) | LinkedIn feed, own profile. "Farza Majeed / DREAMING :)", **Followers 15,972**. Post above: 4,213 reactions / 235 comments / 130 reposts, **231,666 impressions**. Then "Farza Majeed · You · 3mo **Watch me control my computer with just my voice. This is the future of operating systems....** more", Spotify "Back In Black" demo thumbnail, **1,635 reactions, 122 comments, 46 reposts, 75,318 impressions**, "View analytics". Then "4mo · Edited I rented out a 250-seat theatre in SF to screen one of the best movies ever:... more". | Not spoken. Shows the same demo cross-posted to LinkedIn. INFERRED: an edit flash (navigation residue). |
| **I-10** | 35:30.43-35:34.89 | X timeline, the "May 30 Watch me control my computer with just my voice ... No hands. GPT-Realtime 2.0 is very, very underrated. Demo:" post. Video 0:00/1:44, Xcode + desktop with a webcam bubble. Counts **929 replies, 1.5K reposts, 14K likes, 3.8M views**. Next post: "May 16 Been working on a new UX for agents. It will understand your workflow as you use your computer and proactively nudge you when it can be helpful. I feel like agents are these super powerful beings trapped in terminals and chat interfaces. Now, just use your voice. Demo:" | "This was a super simple video, basically just a quick story." |
| (wide) | 35:34.89-35:42.57 | n/a | n/a |
| **I-11** | 35:42.57-36:21.90 | The no-hands demo plays, with interview PiPs overlaid. Shot list in section 3. | Beats without cuts; first-use-case demo. |
| (wide/singles) | 36:21.90-36:50.34 | n/a | n/a |
| **I-12** | 36:50.34-36:54.76 | The same X post as I-10, now playing at 0:12/1:44 (Spotify "Back In Black" visible). Cursor hovers **"3.8M"** with tooltip "View". Status-bar URL "x.com/FarzaTV/status/2060865350036750847/analytics". | "3.8 million views on Twitter." |
| **I-13** | 36:54.76-36:57.48 | Instagram reels grid of **farza954** (URL "instagram.com/farza954/reel/DZA9qazSplT/"). Views per tile: **123K** ("...und the area that"), **463K** (man lying on a couch with a phone), **160K** ("It's an AI that"), **29.3K** ("UGC fo[r]"), **2.5M** ("We made our first beat,"), hovered tile (code-screen thumbnail, the voice-control demo; INFERRED) **44.9K likes, 770 comments** + "Boost reel", **1.4M** ("heyclicky.com", man on a bench in a fleece), **20.9M** ("Last week I went", man in a cap at a café table with a laptop). | "Instagram 4.6 million." The hover replaces the view count with likes and comments, so 4.6M is not legible on this tile. A 4.6M tile appears in I-8. |
| (singles/wide) | 36:57.48-38:03.21 | Includes the 37:33 visor gesture and the 37:34.75 match cut (prior probe E1 Q20) | n/a |
| **I-14** | 38:03.21-38:12.97 | IG reel modal, **farza954 "is my startup trash? let's decide."** Edited · 12w. Shot by shot: (a) 38:03-38:05 a man in a cream sweater sitting on a silver gym ball in front of a green screen, burned caption **"It has been 9 weeks"**, stickers "am I trash? 😭" and "gymball video", collaborator avatars; (b) 38:06.5 the same man keyed onto a spinning world map, caption "world."; (c) 38:08 the man tiny on a design-app canvas with a red arrow drawn to a box, caption "can draw directly"; (d) 38:10.17 back to the farza954 grid. Comments: aadillpickle "my fav"; nadimu.nasser "you're so cool man"; elibethmarch "Every time I use it I feel like we're in future I saw in cartoons when I was a kid!!! Fireeee"; qroonjha "Your video editor deserves a Pakwan dinner 🙌" (59 likes); mosaad_m7 "Bro, we're using the product because your content is just that good! 🔥". **Liked by samin100 and 3,364 others, July 1.** Audio: "it has been nine weeks since i built and launched my idea it's an ai that can draw directly on your screen and guide you through any" [37:59-38:05]. | Quick, high-beat video for the no-attention-span audience. Cuts land about every 0.7-1.3 s: luma cuts at 38:05.54, 38:06.21, 38:06.96. |
| (wide) | 38:12.97-38:17.22 | Farza typing on the laptop | n/a |
| **I-15** | 38:17.22-38:25.98 | IG reel, **farza954, caption "Put something out, see what happens."**, **31.3K likes, 306 comments, 264 reposts**, notification pill "100 comments, 20 likes, 100 follows, 2". Shots: (a) 38:17-38:21 the man on a bench with a laptop outdoors, caption **"Two weeks later,"**; (b) 38:19-38:21 the man in a fleece with a patch, laptop on lap, in front of a chalkboard full of math, caption "to figure out a"; (c) 38:23.3 a product-analytics screen-capture, line chart, tooltip **"Tuesday, 28 Apr 2026 (UTC) user_message_sent Unique 1,474"**, caption "thousands of". Audio: "two weeks ago i was in my apartment trying to figure out a cool idea to work on two weeks later i built this thing that's now being used by thousands of people every single day and the crazy part is" [38:16-38:24]. | Beats ("am I here? am I still watching?"). A real usage chart is used as proof B-roll for "thousands of people". |
| (wide/singles) | 38:25.98-41:00.22 | No inserts across the whole filmmaker chapter | n/a |
| **I-16/17** | 41:00.22-41:06.93 | LinkedIn own feed (Farza Majeed / DREAMING :) / Followers 15,972). A post with 611 / 30 / 7, **27,441 impressions**. Then "2mo **We hit $10K MRR on heyclicky yesterday. It's been 9-weeks since I started working on it....** more", video thumbnail of two men in a convenience store, caption "just to learn why people use", **1,106 reactions, 53 comments, 7 reposts, 50,677 impressions**. Bottom: a floating dark **screen-recorder control bar**: ⓧ, "Recover 2 unfinished recordings", capture modes "Display / Window / Area / Device", "No camera", mic "MacBook Pro...", "Record system audio", settings gear. Static: the cursor only moves. | Shown while he names Screen Studio [40:53-41:03]. The bar is INFERRED to be Screen Studio's recording toolbar, from timing; its UI is not named on screen. The LinkedIn content is incidental but carries numbers. |
| (singles/wide) | 41:06.93-45:02.71 | No inserts across the gear, audio, Vikrant and "be cringe" sections | n/a |
| **I-18** | 45:02.71-45:10.26 | Full-screen plain-text editor (FreeWrite, named at 44:59-45:01). White page, serif-free text, no chrome visible: "When talking to our users, we found many of them want to use agents more! But, didn't know what agents to create. Which kinda makes sense! Most interfaces coming out these days are like a blank chat boxes, and you have to put in a lot of energy to even know what to ask. / If you ask for the right things though, agents can be really magical. / But, most people never get there. / But, what if you were just given the perfect agents for whatever it is you're trying to do ro whatever goals you're trying to accomplish. / What if a filmmaker could magical get a buddy to help him apply for film festivals. What if an app developer could get a buddy to do Ggetoogle Ads for her app autonomously and earn it's first $1. / That'd be sick, and the technology is there but you gotta ask. / So, check this out. / It all starts with a little interview. / <Interview, fashion designer>". The same recorder bar as I-17 is at the bottom. | The writing tool. Script anatomy (INFERRED): user insight, then the problem, then the payoff, then "what if" examples for specific personas, then the "check this out" turn, then a bracketed shot direction "<Interview, fashion designer>". Typos left in (it is a draft). Prior probe E1 Q22: the same document appears at 10:38-10:54 and 11:04.7-11:16.1. |
| (wide/singles) | 45:10.26-46:58.41 | The challenge is told in wide and singles. Phone held up about 46:07. Laptop closed by about 46:43 (E1). | n/a |
| **End card** | 46:58.41-47:08.37 | Orange gradient panel wipes in from the right (E1 Q23). Monospace credits, MEASURED full-res crop: **Host: Aaron Epstein · Producer: Ryan Loughlin · Guest: Farza Majeed · Editor: Amanda Deisler · Camera: Matt Kang, Chris Hall**. YC "Y" bug bottom-right. No URL, CTA or subscribe card. Music bed out by 47:05, then digital silence (E1 Q24). | Credits |

---

## 3. The Spotify/Stripe "no hands" demo (I-11), shot by shot as seen

The source is the "May 30 / Watch me control my computer with just my voice" post (I-10, I-12; X length 1:44). The interview shows about 39 s of it, 35:42.57-36:21.90.

- **Frame.** 16:9 macOS desktop screen recording. A redwood-forest wallpaper, an Xcode window (class "ClickyChimeWarmer", log lines "[Realtime] ...", "[notch] voiceState ..."), desktop folders "lol-snake-game", "Misc", "LUTS".
- **Face.** A rounded-square webcam bubble, lower-left. The man is uncapped, in round wire glasses, a black-and-white checked shirt and white earbuds, against a brick wall (MEASURED). That he is Farza is prior probe E1's INFERRED identification. The face is always on screen, and the screen is always the subject.

| Time | Beat (what happens) | Audio (transcript) |
|---|---|---|
| 35:42.6-35:44 | **Hook.** Bubble over Xcode logs. He looks into the camera and raises both open palms (E1 Q19). | "check this out no hands ready" [35:43] |
| 35:44-35:51 | He speaks the command to Clicky. | "hey clicky can you please open up spotify and play acdc for me maybe uh back in black i love that song" [35:43-35:49] |
| 35:51.0-35:52.5 | About 1.5 s of near-silence while the agent works (E1 Q18: mid -47.7 dB). | n/a |
| 35:52.54 | **Payoff 1.** Spotify album page "Back In Black", AC/DC, 1980, 10 songs, 42 min 2 sec. Track rows with play counts ("Back In Black" 2,180,128,432). Playback starts. He grins, hands clasped under his chin (E1 Q19). Loud music enters at about 35:52.75 (E1). | Clicky: "rock on it's playing back in black now" [35:49-35:57] |
| 35:57-36:04 | **Complication.** He winces and puts his hands to his ears (MEASURED, frame 2162 s). | "it's a little bit loud could you turn it down in spotify ... it's so loud" [35:57-36:00] |
| 36:04 | **Payoff 2.** Clicky lowers the volume. The music drops about 16 dB (E1 Q18). He can now talk over it. | Clicky: "got it lowering spotify to 50 so it's less intense" [36:00]; Farza: "okay thank you" |
| 36:05-36:11 | **Escalation.** Next command. The video's speaker breaks in: "so now I'm gonna keep going and this is actually a fun one". | "hey clicky can you open up my ... stripe dashboard for me in my browser let's see if we made any money today" [36:05-36:11] |
| 36:14.89 | Browser opens, blue loading screen. Tabs "(13) X Pro", "chat". He covers his mouth, laughing. | Clicky: "opening your stripe dashboard now" [36:11] |
| 36:15.73 | Stripe dashboard loading, URL "...e.com/acct_1QwEz3GX8p5NiGDv/dashboard". | n/a |
| about 36:18-36:21 | **Reveal.** Stripe "Today": **Gross volume $140.00 (7:02 PM), Yesterday $240.00, USD balance $416.26, Payouts $226.26 Expected Jun 1**, "1 dispute has not been answered". Overview, last 4 weeks: Payments Succeeded $5,851.00, Uncaptured $60.00, Refunded $1,817.00; Gross volume **$7,868.00 +555.67%** vs $1,200.00 previous period. He grins. | "oh man 140 in a day is not ..." [36:17] (the interview cuts away mid-line) |
| 36:21.90 | The interview cuts back to the wide shot. | n/a |

**Structure** (Aaron's reading [37:06-37:31], matching the frames): hook ("no hands") → ask → wait → payoff (song) → complication (too loud) → payoff (volume down, so he can talk over it) → escalation (Stripe) → reveal (real revenue). The demo has no edit cuts: every visual change is the screen itself changing (INFERRED from the frames at each luma cut). Captions: none are burned into this demo, unlike the vertical reels (MEASURED: frames 2143, 2148, 2154, 2162, 2167, 2175, 2178, 2181 s).

---

## 4. Platforms named in the span, and what he says converts

| Platform | Who names it, when | What is claimed | Numbers | Evidence type |
|---|---|---|---|---|
| **Twitter / X** | Farza 31:05, 31:23, 33:35, 36:50 | Worst conversion of any channel, historically, over about 10 years. A "moment once and you're gone". Doom-scroll context. Wants 16:9. | Clicky launch 7,000 downloads on 3M views (on screen 2.9M). Dictation 2.9M views, "horrendously low" account conversion. Drawing video 589K views (on screen only). Voice demo 3.8M views. | Views ON-SCREEN; conversion EXPERIENCE |
| **YouTube** | Farza 30:19, 31:30-32:16 | Best conversion "for most companies". A library that lasts decades and keeps performing. | 20K views (on screen 19K), about 20% downloaded the app, 872 subscribers, 472 likes, 69 comments | Views and subs ON-SCREEN; 20% EXPERIENCE |
| **Instagram** | Farza 30:19, 32:22-33:18, 34:17, 36:50; challenge 46:10-46:13 | About 70% of all traffic. Best channel for the audience he wants, "by far, not even close". Most videos are made for IG. A Twitter-optimised 16:9 video still did better there. | 70% of traffic; drawing reel 27.4K likes (on screen); voice demo 4.6M views (spoken); grid 123K-20.9M views (on screen); _heyclicky 35.4K followers (on screen); "9 weeks" reel 3,364+ likes; "two weeks" reel 31.3K likes | Traffic share EXPERIENCE; counts ON-SCREEN |
| **TikTok** | Farza 30:19-30:48; challenge 46:10 | Niche call-out hooks found design-agency leads. | About 50 leads; about 4,000 views per video | EXPERIENCE; no TikTok shown |
| **LinkedIn** | Aaron 30:04 (the "default" founder channel); shown in I-9 and I-16 | Farza says nothing about LinkedIn conversion in this span. | On screen only: 15,972 followers; posts at 231,666, 75,318, 50,677 and 27,441 impressions | ON-SCREEN only |
| **Threads** | On screen only (I-5: "_heyclicky") | n/a | n/a | ON-SCREEN |
| **Communities / specialised design websites** | Aaron 30:09 | Farza: "those are all actually really good, you should do those things" [30:14] | n/a | opinion |

**Conversion instrumentation he describes** (EXPERIENCE): a per-channel path in the bio link (heyclicky.com/ig); landing-page download conversion per path; a "send it to yourself by email" button for mobile visitors, with its click rate tracked.

---

## 5. Procedure steps implied by this span

Numbered, imperative, each with the source timestamp.

1. Every day, ask what you did today that made you smile or was interesting. Talk about it, show it, post it, go back to work [28:44-28:56].
2. Do not rule out consumer platforms for a B2B product. Ask whether your buyer (e.g. design-agency founders) scrolls TikTok, Instagram or YouTube, and run that alongside LinkedIn and community outreach [30:14-30:23].
3. For a niche, open with a call-out hook that names the viewer's role ("Hey, are you the founder of a design agency? Stop right there, let me show you something really cool") [30:33-30:38].
4. Judge niche videos by targeted views and leads, not virality. About 4,000 targeted views can be enough [30:43-30:54].
5. Post to every channel at first, then compare channels on conversion, not views [31:03, 33:02-33:13].
6. After the first couple of videos, give each channel its own tracked link-in-bio path (e.g. /ig) and measure path → download [32:43-32:53].
7. If the product is desktop-only, add a "send the link to yourself" button for mobile visitors and track its click rate [32:53-33:02].
8. Treat YouTube as a long-lived library. Upload the demo there even with a tiny channel, because it keeps converting [32:12-32:16].
9. Make each video for one primary platform (usually vertical for Instagram) and cross-post. Make 16:9 versions when Twitter is the primary [33:23-33:39].
10. Before posting, watch the video muted at scroll speed and list the few words your brain registers. If they don't add up to the pitch, change the first frames or the text [33:50-34:11].
11. Record the moment you first get something working, and show your own first real use case. Don't wait to check whether someone did it first [35:32, 36:17-36:42].
12. Structure a one-take demo as beats: hook, ask, payoff, complication, payoff, escalation, reveal. Keep the story moving rather than "holding attention" [37:06-37:43].
13. At each beat, ask "am I still watching?" from the viewer's seat [38:24-38:27].
14. Make some videos deliberately high-beat for the no-attention-span audience (fast captions, cuts about every second) [37:53-38:20].
15. Get decent audio before anything else: a cheap (used) DJI mic or any mic other than the laptop or AirPods [41:46-42:31].
16. Pick the capture level by intent: (a) screen demo, Screen Studio; (b) "native" talking video, iPhone selfie camera, edit in Edits; (c) cinematic, Sony FX3/FX30 + DJI mic. Edit on the laptop in DaVinci [40:52-42:32].
17. Once you've made 15-30 videos, write for 10 minutes before each recording (he uses FreeWrite) to catch bad ideas before the camera [44:59-45:36].
18. Find which parts of video-making you're best at (his: script, song, vibe). When you can, hire a filmmaker for the rest, and brainstorm each feature video together [43:05-43:47].
19. If you can't hire yet, start anyway and accept cringe [44:03-44:58].
20. Run the 30-day challenge: 10 minutes a day, phone selfie talking about what you did, post to IG or TikTok (a fresh IG account if you like), 30 days straight, then copy whatever passed about 1,000 views [45:58-46:41].

---

## 6. Numbers (every number said in the span)

"Spoken" means Farza or Aaron said it. Whether it is an anecdote or something measured on screen is stated per row.

| [mm:ss] | Number | Context | Status |
|---|---|---|---|
| 29:42 | "billions" | People browsing these platforms | Spoken, no source |
| 29:48 | 3 | Design agencies that found Clicky naturally | Anecdote |
| 30:38 | about 50 | Design-agency leads from TikTok | Anecdote |
| 30:43 | about 4,000 | Average views per targeted TikTok | Anecdote |
| 31:07 | about 10 years | Time making stuff on Twitter | Anecdote |
| 31:13 | 7,000 downloads / 3 million views | Original Clicky video on Twitter | 3M ON-SCREEN as 2.9M (I-1); 7,000 anecdote |
| 31:19 | "less than one percent" | His conversion math (0.23% by arithmetic, INFERRED) | Anecdote + arithmetic |
| 31:23 | 2.9 million | Dictation video views on Twitter | ON-SCREEN 2.9M (I-2) |
| 31:30 | 20,000 | Dictation video views on YouTube | ON-SCREEN 19K (I-3) |
| 31:37 | about 20 (%) | YouTube view → download conversion | Anecdote, no analytics shown |
| 32:05 | 872 subscribers | heyclicky YouTube channel | ON-SCREEN (I-3, I-4) |
| 32:05 | 20k views | Same | ON-SCREEN 19K |
| 32:16 | "decades" | YouTube library lifespan | Opinion |
| 32:22 | about 70 (%) | Share of traffic from Instagram ("I think") | Anecdote |
| 33:39 | 16:9 | Twitter aspect ratio | Rule |
| 34:25 | "millions of views" | Drawing video on Instagram | Anecdote; ON-SCREEN only 27.4K likes |
| 36:17 | 140 | Dollars in a day (Stripe, in the demo) | ON-SCREEN $140.00 |
| 36:00 | 50 (%) | Spotify volume set by Clicky (in the demo) | In-demo audio |
| 36:50 | 3.8 million | Voice demo views on Twitter | ON-SCREEN 3.8M (I-12) |
| 36:50 | 4.6 million | Voice demo views on Instagram | Spoken; "4.6M" tile visible in I-8, not tied to this reel |
| 37:02 | 0 ("not a single cut") | Cuts in the voice demo | Consistent with frames (INFERRED) |
| 37:59 | 9 weeks | "It has been 9 weeks since I built and launched" (reel audio) | ON-SCREEN caption |
| 38:16 | 2 weeks | "two weeks later" (reel audio) | ON-SCREEN caption |
| 38:20 | "thousands of people every single day" | Reel claim | ON-SCREEN chart: 1,474 unique user_message_sent on 28 Apr 2026 |
| 38:38 | 19 | Age of the beat-sense staffer | Anecdote |
| 39:10 | 2 | First two hires (filmmaker, then engineer) | Anecdote |
| 39:55 | 2 of 7 | Film team vs whole team at the last company | Anecdote |
| 40:03 | 3 and 1 | Video people vs engineers at Clicky at one point | Anecdote |
| 40:17 | "two minutes" | Time to clone his product | Hyperbole |
| 40:30 | 100,000 | Hypothetical niche audience | Hypothetical |
| 40:43 | "thousands of people" | Flood the app after a feature video | Anecdote |
| 41:03 | about 30 bucks | Screen Studio price | Spoken, hedged |
| 42:00 | 720p | Low-res demo he'd still watch with crisp audio | Anecdote |
| 45:22 | 15th, 20th, 30th | Video count at which to start writing first | Rule |
| 45:27 | 10 minutes | Pre-record writing time | Rule |
| 46:00 | 10 minutes | Daily challenge time | Rule |
| 46:17 / 46:40 | 30 days | Challenge length | Rule |
| 46:24 | about 1,000 views | Promised outlier within 30 days | Promise, no data |
| 46:41 | 1 | Video per day | Rule |

**On-screen-only numbers** (MEASURED, never spoken):

- X profile: 1,511 photos & videos.
- Launch post: 1.3K replies / 1.7K reposts / 15K likes. Dictation post: 552 / 777 / 10K. Drawing post: 404 / 457 / 5.1K / 589K views. Voice post: 929 / 1.5K / 14K.
- YouTube: 472 likes, 69 comments, "2mo ago"; video length 2:00.
- _heyclicky: 48 posts / 35.4K followers / 5 following.
- farza954 reels: 123K, 463K, 160K, 29.3K, 2.5M, 1.4M, 20.9M views; 44.9K likes / 770 comments on the hovered tile.
- Drawing reel: 27.4K likes, June 16. "9 weeks" reel: 3,364+ likes, July 1. "Two weeks" reel: 31.3K likes / 306 comments / 264 reposts.
- LinkedIn: 15,972 followers; posts at 231,666 / 75,318 / 50,677 / 27,441 impressions.
- Stripe: $140 today, $240 yesterday, $7,868 over 4 weeks (+555.67%).

---

## 7. Contradictions or tensions noticed

1. **"Founder-led, scrappy" vs "made by a filmmaker."** The challenge and the "start cringe" advice describe a solo phone register [44:11-46:41]. But Farza says every video shown in the interview, except the old Zip School ones, was made by Vikrant [42:51]. At one point Clicky had 3 video people to 1 engineer [40:03]. What the method document reproduces from these examples is a founder-on-camera, filmmaker-produced register. Only the challenge and Zip School are truly solo. Earlier he also says a produced video "will take like an hour" for him [20:50-20:55], which sits oddly beside a full-time filmmaker making all of them.
2. **Scripting: always or later?** Earlier he says "this whole video scripted, every line" written three days before [14:00-14:05] (chapter "Why Farza Scripts Every Video", 10:30). Here he says first-timers should not worry about writing, and should write 10 minutes once on their 15th-30th video [45:20-45:29]. That is reconcilable as staged advice, but the method document should state the stage explicitly.
3. **Twitter is the "worst" channel, yet the hero examples are Twitter numbers.** He calls Twitter the worst converter [31:05], yet leads with 3M, 2.9M and 3.8M Twitter view counts, and calls the drawing video "super optimized for Twitter" [33:50]. That same video did better on Instagram [34:17], so "optimise for Twitter" did not predict where it performed.
4. **"Never go viral" vs viral-count framing.** "The goal is never to go viral" [30:48] and "I'm not trying to go viral" [32:28], but the examples are chosen by view count (millions). The IG grid shows outliers up to 20.9M. He acknowledges survivorship himself ("we're looking at the stuff that's working" [35:23]).
5. **Conversion numbers are unshown.** The 7,000 downloads, the about-20% YouTube conversion and the about-70% Instagram traffic share are all spoken without an analytics screen, while view counts are shown on screen every time. Arithmetic (INFERRED): 20% of about 19K is about 3,800 downloads from YouTube, vs 7,000 from 2.9-3M Twitter views. So the low-view YouTube video yielded roughly half the downloads of the viral tweet. That supports his point, but rests entirely on his rates.
6. **"Instagram needs quick edits" vs both examples.** The voice demo has no cuts and does 4.6M on IG [37:02]. Yet the next examples he shows ([37:53-38:26], "9 weeks" and "two weeks") are fast-cut, caption-heavy reels made for the no-attention-span audience. His position is "both registers exist". The method should not read the no-cut claim as a general rule.
7. **Who is on camera.** The Clicky videos shown feature an uncapped man in round glasses whom prior probe E1 INFERRED to be Farza. But an on-screen comment on the drawing reel says "Well done Zain" (I-8, MEASURED). The reels carry three collaborator avatars, and the reels grid shows visibly different presenters (e.g. the "heyclicky.com" and "Last week I went" tiles). Whether every "founder-led" video stars Farza is not established here.
8. **Daily effort.** "I don't want to put a ton of attention every day on making videos ... nobody wants to do that" [39:22-39:26] vs the challenge "every day, 10 minutes" [46:00] and "I'm forcing myself to just make videos ... every day" [39:35]. His resolution: daily in the early days, delegate later.
9. **Name spellings.** "Vikrant" appears only in ASR [14:21, 42:39-43:41] and never on screen. The credits name the YC crew, not Clicky's. Treat the spelling as unverified.
