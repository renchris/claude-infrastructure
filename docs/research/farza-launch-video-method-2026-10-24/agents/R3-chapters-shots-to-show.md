# R3: deep read of 17:25-29:11 ("Thousand Shots", "Formula", "Demos Into Stories", "Show What You're Building")

Slot R3, 2026-10-24. Source: the YC interview of Farza Majeed by Aaron Epstein (https://x.com/ycombinator/status/2113654566776709147; YouTube v12aSIZIXUs).

## How this was read (method, all MEASURED this run)

- **Transcript.** I read `/tmp/farza-2026-10-24/transcript.txt` from 16:50 to 29:36, which is 30 s or more either side of the span. I also grepped the whole file for cross-references (hour, script, every day, hook, formula, million, percent, iphone, cringe, filmmaker, 30 days).
- **No precomputed inserts.** `cuts-luma.txt` was empty (0 lines) and `sheets/` and `ingest-status.txt` did not exist when I ran. So I located inserts myself.
- **Coarse sweep.** One 384px frame every 3 s from 1015 to 1780 s (`/tmp/farza-R3/sw/`), extracted with an input-side `-ss`, so each label is the true time.
- **1 fps passes** (frame k is at start + k s; the fps-label trap is corrected):
  - 17:39-18:25, 19:29-20:15 and 21:00-21:15 at 320px (`/tmp/farza-R3/b/`)
  - the Clicky reel, 21:24-22:21, centre crop (`/tmp/farza-R3/reel1/`)
  - 22:58-25:42 at 960px (`/tmp/farza-R3/p2/`)
  - 24:41-25:16 at 1920px and 2 fps (`/tmp/farza-R3/p3/`)
- **Full-res reads.** 1920x1080 stills at every insert (`/tmp/farza-R3/f/`). Small counts were read from crops zoomed 3x.
- **Precision.** Insert boundaries are given to ±1 s where the 1 fps passes covered them. Elsewhere they are ±3 s (the 3 s sweep).
- **Prior probe.** Prior probe E1 (`docs/research/video-understanding-human-parity-2026-10-23/agents/E1-exam-key.md`) worked from a 1280x720 copy. Its timestamps for the class card (18:13.5-18:16.5), the reel (23:00-23:06.5) and the profile (24:45.5-24:50.8) agree with mine.
- **Machine load.** The machine was heavily loaded (`uptime` load average 282, MEASURED), so each ffmpeg seek took about 8 s. No command hung.

**Name corrections from on-screen text (MEASURED):**
- ASR "Zip School" is **Zip** / **zipschool.com**, read off the posts at 17:47 and 19:38.
- ASR "Bill Space" is **Buildspace**, from the @_buildspace handle on the profiles.
- ASR "in why" (21:31) is **Y Combinator**, read off the reel caption "Y Combinator?!!".
- ASR "Davinci results" is **DaVinci Resolve**.
- ASR "doesn't have 21 million views" (21:07) means "it has": the reel tile reads **20.9M** views.

Labels: **MEASURED** means I saw or ran it this run. **QUOTED** means his words, with [mm:ss]. **DOCUMENTED** means a source states it. **INFERRED** means my reasoning. "F" is Farza and "A" is Aaron Epstein. Speaker attribution comes from content and from who is on camera; the ASR has no speaker labels.

---

## 1. Itemized catalog (time order)

Columns: time · claim · quote (one sentence or less) · type · basis. Basis is **exp** (Farza's own experience, nothing external cited) or **ext** (an external number or evidence shown or cited).

### Lead-in (16:50-17:25), just before the chapter

| # | [mm:ss] | Claim | Quote | Type | Basis |
|---|---|---|---|---|---|
| 1 | 16:50 | Post with the mindset that zero views is still a win: the value is in having shipped something out. | "if this gets zero attention, zero views, I'm still happy I posted it" [16:56] | rule (mindset) | exp |
| 2 | 17:05 | Post and forget. Do not watch the metrics live; check results about a week later. | "By the time I hit post, I've already forgotten it." [17:05] | rule / technique | exp |
| 3 | 17:14 | A (host) contrasts this with most people, who refresh to see who liked the post. F agrees: launch and walk away. | "But you launch and you walk away." [17:21] | opinion (A) | exp |

### Chapter: You Have to Take a Thousand Shots (17:25)

| # | [mm:ss] | Claim | Quote | Type | Basis |
|---|---|---|---|---|---|
| 4 | 17:24 | How he got there: volume. He has put out a great deal of work he did not think was good. | "I put so much garbage out in the world at this point." [17:27] | anecdote | exp |
| 5 | 17:33 | Attention is short-lived, so any single post is low-stakes. | "people are going to forget the next day" [17:37] | opinion | exp |
| 6 | 17:42 | Worked example: a 2021 launch, "a year after YC". He was a solo founder at Zip, then Buildspace, and is "solo founder now" (as transcribed). | "I'm not a fantastic editor." [17:54] | example | exp |
| 7 | 17:44-18:20 | **On screen: the Zip launch post and video** (insert I1, I2 below). He plays his own 2021 launch video. Its spoken opening is "hey there Zip schoolers, Farza from Zip School here again to show off four new classes that we just added yesterday" [18:04]. | (see I2) | example (on screen) | MEASURED |
| 8 | 18:19 | He judges his own old video harshly. | "I'm already checked out watching this video" [18:19] | opinion | exp |
| 9 | 18:23 | A asks what mistakes it makes. F refuses to critique: the point is that he posted it. | "it's about the fact that i posted it" [18:27] | rule | exp |
| 10 | 18:31 | Result: 23 likes, more than zero views, one comment, a bookmark. The screen shows 3 replies, 1 repost, 23 likes, 1 bookmark (I2). | "it got 23 likes which by the way is more than zero" [18:31] | number / anecdote | ext (on-screen counts, MEASURED) |
| 11 | 18:43 | **Definition of a launch:** anything new at the company, talked about publicly. | "we did something new at the company we talk about it to the into the world" [18:49] | rule (definition) | exp |
| 12 | 18:54 | Threshold: if there is a chance of more than one view, talk about it. | "if there's a chance that we get more than one view we should talk about it" [18:54] | rule | exp |
| 13 | 18:59 | This was an everyday thing: new classes dropped "every day almost", so he made a video for them. | "this is like an everyday thing in my company" [18:59] | anecdote / cadence | exp |
| 14 | 19:08 | He hoped one class would go viral, and admits none did. | "which never happened" [19:13] | anecdote | exp |
| 15 | 19:13 | **Outcome of volume: skill at talking about products.** Products are hard to talk about without sounding "shilly" or fooling yourself. | "over time i got so much better at just knowing like how should i talk about products" [19:18] | rule / opinion | exp |
| 16 | 19:23 | He distinguishes "good at making videos and writing stories" from "talking about products is hard". | "talking about products is hard" [19:28] | opinion | exp |
| 17 | 19:32 | **Second example:** his first day at the company, 1 Dec 2020, he shipped a landing page and posted it with no copy, just a link and "some weird video I made in Canva". He counts that as a launch. On screen (I3): the post text is only "zipschool.com", over a 5 s card reading "Live science classes kids love 🚀". | "there's no copy there's just a link" [19:37] | example | MEASURED (on screen) |
| 18 | 19:50 | Audience at the time: he had "maybe 80 followers", so no one was watching. | "i had like maybe 80 followers or something" [19:50] | number / anecdote | exp (not shown) |
| 19 | 19:55 | **Third example:** a 7 Nov 2020 selfie video (on screen, I4) about "the next four years", a non-product personal post. It illustrates "I've been posting these for years". | "i've just been posting these for just years" [20:09] | example | MEASURED (on screen) |
| 20 | 20:15 | **The thousand-shots rule**, a basketball analogy: keep shooting and you get closer. You are smart and will improve, but only with volume. | "if you don't take a thousand shots you're not gonna make the ... five thousandth shot" [20:25] | rule (core) | exp |
| 21 | 20:30 | A paraphrases: put it out, don't worry, get the reps. A also notes "the five years since then". | "you need to get the reps" [20:30] | rule (A's paraphrase) | exp |

### Chapter: Farza's Formula for Videos That Convert (20:48)

| # | [mm:ss] | Claim | Quote | Type | Basis |
|---|---|---|---|---|---|
| 22 | 20:46 | Disclaimer: his videos look produced only because production comes naturally to him. A produced video takes him about an hour. | "to make a produced video for me will take like an hour" [20:50] | number / opinion | exp |
| 23 | 20:59 | **Production is optional:** an iPhone video can do really well. | "you don't have to produce your videos it could just be an iphone video" [20:59] | rule | exp |
| 24 | 21:03 | He predicted this video would hit while writing the script. Note the script-first workflow. | "even when i ... wrote the script that it was going to go big" [21:03] | anecdote / technique | exp |
| 25 | 21:07 | The Clicky reel has about 21M Instagram views. The screen shows **20.9M** on the reel tile (I5). | "21 million views on instagram" [21:07] | number | ext (on-screen 20.9M, MEASURED) |
| 26 | 21:11 | **Long tail:** the one video still drives a lot of traffic, because algorithms keep serving content to people who want it. | "this one video is still driving a lot of our traffic" [21:11] | number-free claim / opinion | exp (no traffic data shown) |
| 27 | 21:17 | **Reuse the winner as a paid ad:** he now runs it as a Facebook ad. | "i've made this video an ad now so i'm running facebook ads now on a video" [21:17] | technique | exp |
| 28 | 21:26-21:35 | **On screen: the Clicky launch reel's hook**, played (I6). Shot by shot in §2. | "last week i went super viral for an idea that i built that i thought was actually kind of terrible and this week i'm somehow in [Y Combinator]" [21:26] | example | MEASURED |
| 29 | 21:36 | **Hook deconstruction:** (1) "last week I went super viral" signals social proof and recency; (2) for "something I built that I thought was kind of ridiculous/bad" (self-deprecation), the viewer reaction is "cool, that's interesting"; (3) "now he's in this thing called Y Combinator", where the viewer thinks "oh I've heard of Y Combinator". | "so just that hook" [21:36] | technique | exp |
| 30 | 21:47 | **Niche targeting inside the hook:** naming YC deliberately aims at the people who know and care about YC. | "so i was kind of targeting that niche" [21:47] | technique | exp |
| 31 | 21:51 | **THE FORMULA** (stated): who I am, then what is going on, then what I'm working on, then "let me show you". It is also teased in the cold open at 00:21. | "it's my formula is always the same" [21:51] | rule (core) | exp |
| 32 | 21:56-22:14 | **On screen: the reel's body** (I7). Name the product and give a one-line value proposition, then one concrete use case, shown with the product doing it: "It's called Clicky, it's a little AI buddy that lives next to your computer cursor and teaches you anything in real time for free; let's say I'm learning how to color grade in DaVinci Resolve…" | "let me show you what i'm building" [21:56] | example / technique | MEASURED |
| 33 | 22:14 | This one took **4-6 hours** to make, "because we've just done this". | "this took us like four to six hours to make" [22:14] | number | exp |
| 34 | 22:19 | **Minimum viable version:** "hi, this is what I'm working on, check this out", then turn the camera to show the computer screen. The effect might be smaller, but it still works. | "then i turn the camera to literally show my computer" [22:24] | technique | exp |
| 35 | 22:28 | **Reps target:** make about 10 of those, then you get really good at talking about stuff. | "you just start and you make like 10 of those then you get really good at talking about stuff" [22:28] | number / rule | exp |
| 36 | 22:34 | **The two properties that matter:** a super clear hook, and a very clear reason why you should care *right now while you're on your scroll*. | "super clear hook a very clear like why you should ... care right now while you're on your scroll" [22:34] | rule (core) | exp |
| 37 | 22:44 | **The bounce test:** on any video, his or anyone's, ask "am I bouncing, and when am I bouncing?" | "i ask myself am i bouncing when am i bouncing" [22:44] | technique | exp |
| 38 | 22:48 | **Study practice:** he watches a lot of Instagram Reels "not for entertainment, just to kind of study". | "i watch a lot of content not for entertainment just to kind of study" [22:54] | technique | exp |

### Chapter: Turning Demos Into Stories (23:01)

| # | [mm:ss] | Claim | Quote | Type | Basis |
|---|---|---|---|---|---|
| 39 | 23:00-23:22 | **On screen: a random reel** (kael_newman, I8). Its caption is "Two months ago, I created this page to block my long-distance girlfriend and post my weight loss journey". He stumbled on it live. | "this is a random video we just stumbled upon" [23:05] | example | MEASURED |
| 40 | 23:09 | **What to steal from it:** dark background, light on the face, a caption at the bottom, and an opening ("two months ago") that creates a curiosity gap. | "you kind of want to know two months ago what" [23:16] | technique (observed craft) | exp + on-screen |
| 41 | 23:16 | **Swipe-file technique:** mentally note the pattern and turn it into a template for your own video, e.g. "two months ago I was working on something and I didn't really know what it was", then tell the story. | "maybe we can make a video that uses this as like a template" [23:21] | technique | exp |
| 42 | 23:30 | He keeps doing this: he scrolls more reels on screen (I9) and reads hooks aloud: "this song just hit two million streams", "welcome back to features we should have released six months ago". | "i'll just keep doing this" [23:30] | technique | MEASURED (on screen) |
| 43 | 23:43 | The albo_app "features we should have released 6 months ago" reel shows what startups should be doing. | "this is cool this is what startups should be doing" [23:43] | opinion | exp |
| 44 | 23:48 | A: he sees this mostly from younger founders. Hooks share a **self-deprecating** quality (F's "a thing I thought was terrible"; albo's "should have launched six months ago"; "broke up with my ex-girlfriend"). | "there's almost something um like self-deprecating about it" [23:48] | opinion (A) | exp |
| 45 | 24:04 | A: **everyone wants a story**; a demo, or what you say, can be a mini story. | "how can a demo just be a mini story" [24:04] | rule (A) | exp |
| 46 | 24:08 | A: it is "the character Farza", a character the audience can identify with and root for. | "a character that the audience can identify with and uh ultimately root for" [24:13] | opinion (A) | exp |
| 47 | 24:24 | F: he is not playing a character, but to a viewer on a TikTok or Twitter feed he *is* a random character. | "like i'm a character to the people" [24:29] | opinion | exp |

### Chapter: Show What You're Actually Building (24:53)

| # | [mm:ss] | Claim | Quote | Type | Basis |
|---|---|---|---|---|---|
| 48 | 24:41-24:52 | **On screen:** F navigates his Instagram (farza954 profile, then the _heyclicky profile; I10, I11) to find the team update video. | "something we've been doing that our users have been loving" [24:41] | example | MEASURED |
| 49 | 24:48 | Users love these. Most don't go viral, though "some of them have been going viral". | "it's not going viral but our users have been loving it" [24:41-24:48] | opinion | exp |
| 50 | 24:52-25:16 | **On screen: the "everything we built this week" team update** (I12). Shot by shot in §2. | "this is everything we built this week" [24:52] | example | MEASURED |
| 51 | 25:12 | **Format rule:** no hook, no attention device, no story, just "a group of people telling you what we're doing". | "there's no hook there's no attention there's no story" [25:12] | rule / technique | exp |
| 52 | 25:22 | A: this one almost has a million views on Instagram. The count was **not** visible on screen in this span (see Gaps). | "this almost has a million views on instagram" [25:22] | number | exp (unverified) |
| 53 | 25:27 | **Why it works (his "most important thing"):** what a company does day to day is far from what people imagine. An inside look at the process gets them excited and interested. | "to just give them an inside look of what's actually going on in your process is so cool" [25:40] | rule (core) | exp |
| 54 | 25:46 | **Anti-pattern:** no "life as a founder" content. "My day as a YC founder" is never; show *what* you're doing and *why*. | "you'll never catch me making those videos about ... this is my day as a yc founder" [25:52] | rule (negative) | exp |
| 55 | 26:09 | Most companies never show process. Big companies show the keynote (Zuckerberg on stage with Meta glasses). Early adopters want to see "what is [a] random group of four guys and girls ... making this AI product and how are they doing it". | "most companies just never show their process" [26:09] | opinion | exp |
| 56 | 26:30 | **Production budget for the update format:** about 10 minutes; prompt each person with "what are you doing today". | "we make these videos in 10 minutes" [26:30] | number / technique | exp |
| 57 | 26:43 | **Origin:** they started making them for accountability, "like stand up, but in front of the world". | "it's kind of like stand up right but in front of the world" [26:48] | anecdote / technique | exp |
| 58 | 26:51 | **Cadence:** now every two weeks. | "now we do these every two weeks" [26:51] | number (cadence) | exp |
| 59 | 26:56 | A: the joy shows through the music choice, people clapping and supporting each other, positive vibes. | "people see that in your personality and ... in the music that you choose" [27:00] | opinion (A) | exp |
| 60 | 27:15 | F: you cannot fake it; "you just have to be yourself". | "this is where you just have to be yourself" [27:21] | rule | exp |
| 61 | 27:25 | **His standing advice to anyone starting:** take out your iPhone, record in selfie mode, talk about what you're doing for 30 seconds, and post to Instagram, TikTok, Reddit, YouTube "or wherever". | "take out your iphone click record go go go ... selfie mode and talk about what you're doing for 30 seconds" [27:30] | technique (core) | exp |
| 62 | 27:41 | **Take-up rate:** about 1-2% of people he tells actually do it. | "maybe one percent two percent of the time people will actually do it" [27:46] | number | exp (anecdotal estimate) |
| 63 | 27:50 | **Why people don't:** nerves ("what am I gonna say, how am I gonna look, what if people think it's stupid") and the audience-mismatch fear ("my high school friend follows me, he doesn't care"). Most of the nerves are voiced by A when F asks him. | "what if people think it's stupid" [28:03] | anecdote / psychology | exp |
| 64 | 28:12 | **The cringe rule:** you have to be cringe for a while to learn how not to be. | "you got to be cringe for a little while actually to learn how to not be cringe" [28:17] | rule (core) | exp |
| 65 | 28:23 | People call their first video horrible and refuse to post it. The important part is to keep doing it. | "the important part is to continue doing it" [28:28] | rule | exp |
| 66 | 28:32 | **Daily prompt:** you spend 8 hours a day on your laptop. Spend 10 minutes to ask "what did I do today that made me smile, or was interesting?", talk about it, show it, click post, close it, back to work. | "what's something i did today that made me smile or was interesting" [28:44] | technique (core) | exp |
| 67 | 28:56 | **2026 redefinition of launching:** launching means showing your work. Launching on TechCrunch or the NYT was also showing your work; now you can do it every day and build an audience from it. | "that's what it means to be launching i think in 2026 just to show your work" [28:56] | rule (definition) | exp |
| 68 | 29:09 | (Bridge into the next chapter) A: founders who sell to businesses or procurement think TikTok and Instagram aren't for them. F: everybody is on these platforms, including real people at companies who could be customers. | "there's all kinds of people ... using these platforms that are real humans that happen to work at companies" [29:27] | opinion | exp |

---

## 2. On-screen inserts in the span: verbatim and shot by shot (all MEASURED)

The layout for every insert except I6/I7 (partly) and I12 is the same: black field, host webcam PiP top-left, guest PiP top-right, YC logo bottom-right, content centred. There were no inserts at all from 17:25 to 17:44, 18:21 to 19:34, 20:11 to 21:05, 21:12 to 21:27, 21:36 to 21:59, 22:16 to 22:59, 23:23 to 23:31, 23:47 to 24:41, or 25:17 to 29:40. Those spans are two-shots and singles at the table, verified on the 3 s sweep and the 1 fps passes.

### I1 · 17:44-17:52 · X profile media tab scrolled to the Zip post (illustrates #6)
- Header "Farza 🇵🇰🇺🇸 ✓ · 1,511 photos & videos".
- First at 17:44 the previous post: a video (0:00 / 0:35) of a child in a red "MIGHTY TOUGH" truck sweater, with 1 reply and 16 likes, and below it the Feb 18, 2021 post "Cool little thing I'm doing to update users about new features we add."
- Then the target post, "Farza @FarzaTV · Feb 19, 2021". The hover tooltip reads "10:57 AM · Feb [19,] 2021".

### I2 · 18:01-18:20 · the Zip launch post opened, then its video full-height (illustrates #7-#10)
- **18:01-18:05: post detail.** "New classes on Zip available to book today!" then:
  - 🚀 Mars Perseverance: Rover Landing
  - 🌱 Plant Mystery: The Venus Fly Trap, Pitcher Plant, and Corpse Flower
  - 🐝 Insect Science: The Magic Behind Bees
  - 🎢 Engineer Training: Building an Awesome Rollercoaster w/ Physics
- **Metadata.** "10:57 AM · Feb 19, 2021". **3 replies, 1 repost, 23 likes, 1 bookmark.**
- **Video player.** Remaining-time counter 1:19 at 18:01 and 1:16 at 17:47, so the video runs at least 1:19.
- **Sidebar.** Farza's X bio: "hi. i make things. hacking on @heyclicky. prev founder @_buildspace."
- **18:06-18:20: the launch video itself, enlarged.** A **screen recording of the class page with a selfie-cam bubble bottom-right** (the younger Farza: dark glasses, denim jacket, no cap). There are no burned-in captions.
- **Page content:**
  - A Mars landing image, then "🚀 Mars Perseverance: Rover Landing".
  - Description: "Join this incredible journey and come face to face with NASA's latest mission: The Mars Perseverance Rover! From helicopter drones attached to the belly of the Rover, to drills that will collect Martian samples from the surface of Mars - this is an adventure not to be missed!"
  - Chips: "Ages: 7-12", "Space", "30 Mins", "Teacher Ashton".
  - Buttons: "Book Class for Thu, Feb 25 - 10:…", "Book Class for Thu, Feb 25 - 7:…", "Book Class for Fri, Feb 26 - 12:…", "Show 3 more times". (Prior probe E1 Q13 agrees.)
- **Format (INFERRED from what is seen):** face in a small bubble, product page as the main picture, narration straight to camera ("hey there Zip schoolers…"). No hook beyond the greeting.

### I3 · 19:35-19:56 · the first-day landing-page post (illustrates #17)
- "Farza @FarzaTV · Dec 1, 2020". The **entire post text is "zipschool.com"**.
- The attached video is **5 s long** (player "0:03 / 0:05" at 19:59). A pink-to-magenta header card reads "**Live science classes kids love 🚀**" over footage of a dog in an astronaut suit floating in a space-station interior.
- **2 replies, 10 likes.** The post above it has 1 reply and 12 likes (purple graphic, content not identified).

### I4 · 19:57-20:10 · 7 Nov 2020 selfie (illustrates #19)
- "Farza @FarzaTV · Nov 7, 2020". A vertical selfie video, **0:10** long. It is a handheld close-up of Farza in glasses and a dark zip top. There is no caption text in the post. **17 likes.** The audio is "what is this, nice, four years … I'm pretty excited for the next four years for the USA, for Zip School, for the world" [19:55-19:59].
- Below it: "Sep 18, 2020 · I suck at Melee but did this thing the other day on Marth I thought was kinda cool :)." with a Melee gameplay clip (timer "05:52.37").

### I5 · 21:05-21:11 · Farza's Instagram grid, with view counts (illustrates #25)
- **21:05** (lower part of the grid): tile view counts **29.8K, 22.5K, 27.6K, 22K, 19.3K, 13.6K, 17.9K**. One tile starts "Once upon a time, There was a boy named Az…".
- **21:08** (higher in the grid): tiles **462K, 160K, 29.3K** (top row cut off). Then a row of **2.5M** ("We made our first beat,"), **4.5M** (a code/terminal screen), **1.4M** ("heyclicky.com", Farza seated outdoors) and **20.9M** ("Last week I went", the Clicky launch reel). Below them sit tiles with no visible count ("hi, i'm clicky!" on a sky background, people climbing stairs, a dark interior, a red theatre).
- **What it shows (INFERRED):** this is the "thousand shots" hit distribution on one account. Many posts sit in the 13.6K-29.8K range, and one sits at 20.9M. He did not narrate the distribution; he was scrolling to the 20.9M tile.

### I6 · 21:28-21:35 · the Clicky launch reel, hook (shown on Instagram, account farza954)
- **Reel UI (21:30):** ♥ **335K**, comments **55.8K**, reposts **2,681**. Caption "**im building a buddy for your computer cursor**". A red Instagram activity badge to the left reads "100 comments · 18 likes · 100 follows · 2".
- **Shot by shot** (1 fps; burned-in captions are white, centred, a few words at a time):

| t | Picture | Burned caption |
|---|---|---|
| 21:28 | Farza (dark cap, glasses, dark fleece) at a round table by a bright window, typing on a laptop, red headphones on the table. Medium shot, warm natural light, a cinematic look. | "Last week I went" |
| 21:29 | Cut to a light-mode screenshot of his X post: "I built this thing called Clicky. / It's an AI teacher that lives as a buddy next to your cursor. / It can see your screen, talk to you, and even point at stuff… having a real teacher next to you. / I've been using it the past few days to learn Davinci Resol[ve]…", with an embedded 0:54 DaVinci video. Footer "5:38 PM · Apr 6, 2026 · **2.8M Views**", 1.7K reposts, 15K likes. | "super viral for" |
| 21:30 | Back to Farza at the table, talking to the camera. | "an idea that I" |
| 21:31 | Same shot. | "built that I" |
| 21:32 | Same shot; he looks up, deadpan. | "terrible." |
| 21:33 | Same shot; he looks off to the side. | "And this week I'm" |
| 21:34 | Farza holds up a YC badge or card toward the camera, mouth open in mock surprise. | "Y Combinator?!!" |
| 21:35 | Extreme close-up of the badge: a red square with a white "Y". | "Y Combinator?!!" |

- Then a cut back to the studio wide (21:36) while F unpacks the hook.
- **The hook as spoken** [21:26]: "Last week I went super viral for an idea that I built that I thought was actually kind of terrible, and this week I'm somehow in Y Combinator."
- **Timing (MEASURED):** about 7-8 s, with the face on camera in 6 of the 8 seconds sampled. The proof cut (the viral post at 2.8M views) lands in second 2.

### I7 · 22:00-22:15 · the Clicky launch reel, body (same reel resumed)

| t | Picture | Burned caption |
|---|---|---|
| 22:00 | Wide of the bright room, Farza small at the table on the right. | "what I'm" / "building." |
| 22:01 | Press-article screenshot, partly cropped: headline "…eacher 'Clicky' with Q…", a pill-shaped "…ibe" button, and the body line "help you learn software and…". | (none legible) |
| 22:02-22:04 | Desert dunes under a hazy sun, with a blue Clicky cursor-triangle drifting across. | "It's a little AI" / "buddy that lives" / "computer cursor," |
| 22:05 | Collage of YouTube-style results, the word "anything" large. | "anything" |
| 22:06 | Close-up of search results: "REAL-TIME", "Real-Time – Inte…", "IG…org", with a cursor. | (illustrates "in real time") |
| 22:07-22:09 | Screen capture of DaVinci Resolve (media pool and colour wheels). | "learning how to" / "DaVinci Resolve." |
| 22:10 | YouTube results page of DaVinci Resolve tutorials. | "to a [YouTube video]" |
| 22:11 | Close-up of hands on a MacBook keyboard and trackpad. | "I just gotta ask" |
| 22:12 | DaVinci timeline with audio waveform. | "out loud and" |
| 22:13 | Same timeline. | "literally tell me" |
| 22:14 | DaVinci "Primaries - Color Wheels" panel. | "exactly how to" |
| 22:15 | Same panel; Clicky's blue pointer with the speech bubble "**this one!**" points at the Lift wheel ("DaVinci Resolve Studio 20" label). | "at it for me." |

- Then a cut back to the wide (22:16).
- **Voice-over** [21:59-22:14]: "It's called Clicky, it's a little AI buddy that lives next to your computer cursor and teaches you anything in real time for free; let's say I'm learning how to color grade in DaVinci Resolve, instead of going to a YouTube video I just gotta ask out loud and Clicky will literally tell me exactly how to get there and even point at it for me."
- **Pattern (MEASURED):** the face appears only at the start; the body is screen and B-roll, about one cut per second, with word-level captions throughout.
- **Revisit:** the same reel is on screen again at 24:42-24:43, paused on the "at it for me." frame with "this one!", before he navigates to the profiles.

### I8 · 23:00-23:22 · random reel: kael_newman (the "Turning Demos Into Stories" example)
- Instagram Reels feed. Account "**kael_newman** ✓ · Follow".
- Burned caption: "**Two months ago, I created this page to block my long-distance girlfriend and post my weight loss journey**". White bold text, lower-middle.
- Post caption: "2 days until I fly to show my long distance girlfriend my weight loss transformation. Gonna be interesting……".
- Counts: ♥ **7,752**, comments **108**, reposts **45**.
- **Framing:** a single static selfie close-up of a young man with a moustache, lit from the front against a near-black room. Paused at about 23:06 (prior probe E1 Q15), but it stays on screen while F comments until 23:22.
- **Why he shows it** [23:05-23:30]: it was a random find. Note the dark background with light on the face, and the caption opening "two months ago" that makes you want to know "two months ago what". Save the pattern as a template ("two months ago I was working on something…").

### I9 · 23:32-23:46 · scrolling the Reels feed for more hooks

| t | Account | On screen | Counts |
|---|---|---|---|
| 23:33 | hyuletx | Black-on-white caption box "trying to record a song in a tehran appartment" (sic), over a young man at a microphone with a guitar. | ♥ 3,145 · 122 · 36 |
| 23:35-23:36 | lyrah | Top title "how i got 2M streams without a label"; a Spotify row "Run Out · 2,444,448"; subtitle "Okay, so this song just hit 2 million streams,". Post caption "i realize i'm pulling back the curtain here 😅 but sharing for any indie artist who puts too much pressure on their videos …". **F reads this hook aloud** [23:30]. | ♥ 2,861 · 160 · 45 |
| 23:37 | mey_laneflow | "POV : 19 yo on a client call / I clearly don't know how to take a compliment 🥲"; subtitle "you and it's better when". Post caption "Is 19 a good age to start a business or not? 🤔 #fypシ #sales #startup". | ♥ count hidden ("Likes") · 30 · 14 |
| 23:38-23:39 | meshparade (audio: brakence) | A 3D yellow smiley on black. Caption "i'm bugging! #brakence #hyperpop #blender3d #3danimation #edit". | ♥ 3,990 · 62 · 374 |
| 23:41-23:46 | albo_app ✓ (audio: karosaves) | Two founders sitting on the floor, one holding a lav mic. Text "welcome back to….. **FEATU[RES]** we should have / **released 6 months ago** (but we're only releasing them now)". Post caption "GUYSSS we have been releasing so much good stuff - so time to give you a MAJOR update!!! … pls let us know how…". **F reads it aloud and says this is what startups should be doing** [23:36-23:43]. | ♥ 66 · 8 |

- The spoken line "you wanted to know where I've been" [23:36] is reel audio during the scroll. Which reel it came from could not be pinned (INFERRED: mey_laneflow or meshparade).

### I10 · 24:44 · Instagram profile farza954 (prior probe E1's "different profile")
- "**farza954** ✓ / farza 🇵🇰🇺🇸".
- **31 posts · 87.6K followers · 309 following** (read from a 3x zoom).
- Bio: "working on @_heyclicky, prev founder at @_buildspace". Link "heyclicky.com/farza and 2 more". Threads: farza954.
- Highlights: canceled, ty, trending, ai+frnds, handsome, urinals, eggs.

### I11 · 24:45-24:52 · Instagram profile _heyclicky (special item)
- "**_heyclicky** / heyclicky".
- **48 posts · 35.4K followers · 5 following.** Read on a 3x zoom of the 1920px frame at 24:47: it is "**5**", **not "8"**, which confirms prior probe E1 Q16.
- Bio: "your friendly neighborhood cursor". Link "**heyclicky.com/ig**". Threads "_heyclicky". "Followed by nokhezz_, samin100 + 82 more". The viewer is "Following".
- Pinned tiles: "hi, i'm clicky!" (sky with a blue cursor), "[every]thing we" (the update video), a team selfie (hover reads **♥ 12.2K · 153 comments**), and "me what to take off your p[late]" / "i'm on gpt-6 now ^_^".
- **24:52 grid scroll:** a tile hovered at **♥ 1,457 · 39**, another at "♥ 528 · 39". The status-bar URL is "instagram.com/_heyclicky/reel/DdezcgWSDS_/". Other tiles include "I recently made this short film but" and a Clicky UI tile reading "Evening, Vikrant. One of your Clickys is working right now".

### I12 · 24:54-25:16 · "everything we built this week" (team update, 16:9, played full-frame with both PiPs)

| t | Picture | Burned caption (small, white, bottom) |
|---|---|---|
| 24:54 | Farza front-centre, outdoors (tan chore jacket, yellow cap), holding a small wireless mic to his mouth. Five teammates sit and stand behind on a low wall with red-flowered shrubs. Shallow depth of field, teal-and-warm grade. | "This is everything we built this week." |
| 24:55-24:56 | Same shot with a large white title over it. | "**everything we built**" (title) |
| 24:57-24:59 | Cut: a teammate (black polo, glasses) leans into the lens with the mic; the group watches, smiling. | "So, Clicky had some problems" / "about like integration and" |
| 25:00 | Same; someone behind holds up the yellow cap. | "orchestration of the agents." |
| 25:01 | B-roll: hands holding a phone (team photo), desk and laptop. | (none) |
| 25:02 | B-roll: phone close-up with the Clicky chat UI. | "Now, Clicky has a new brain and you will" |
| 25:03 | B-roll: blurred desk detail. | "feel way more smooth to spawn the agents," |
| 25:04 | Monitor showing the team crowding a selfie camera and waving. | (same line) |
| 25:05 | Wider office view of that monitor. | "to control them, to pause them." |
| 25:06-25:07 | Handheld office shot, people laughing. | "to control them, to pause them." / "And you're gonna see a lot of" |
| 25:08-25:09 | Back to the outdoor group, black-polo teammate. | "And you're gonna see a lot of" / "improvements overall." |
| 25:10-25:11 | A third teammate (white tee, glasses, beard) close to the camera with the mic, the group behind. | "A lot of people complaining about like," |
| 25:12-25:13 | Office: two people drawing on a large dark board or wall. | "Clicky keeps following them." |
| 25:14-25:15 | Office: a teammate in a red tee at a desk with a big monitor, gesturing to someone off-frame. | "So, I made a fix for them. Stay tuned." |

- Cut to the studio wide at 25:16.
- **Pattern (MEASURED):** three speakers in about 22 s, each giving one line about one shipped change. The group shot is the anchor, B-roll covers each sentence, there is one big title card, and captions run throughout. **INFERRED:** even this "no hook" format opens on a title-card line ("This is everything we built this week") and uses graded multi-location B-roll, so it is more produced than "made in 10 minutes" suggests; see §5.

---

## 3. The formula, reconstructed as stated

**Stated** (QUOTED [21:51]): "my formula is always the same: this is who I am, this is what's going on, this is what I'm working on, let me show you". The cold open teases the same lines [00:21-00:23].

**As executed in the Clicky reel** (MEASURED from I6/I7, mapped by me, so INFERRED where noted):

1. **Who I am + what's going on (the hook, about 7 s).** One sentence that packs three things:
   - recent social proof: "last week I went super viral", cut to the 2.8M-view post;
   - self-deprecation: "for an idea that I thought was terrible";
   - a niche-targeted credential: "this week I'm in Y Combinator?!!", with the badge shown.

   Per F [21:36-21:51], each beat triggers a viewer reaction ("cool, that's interesting", "oh I've heard of YC"). The niche is chosen on purpose.
2. **What I'm working on.** "Let me show you what I'm building. It's called Clicky." That is the name plus a one-line value proposition: "a little AI buddy that lives next to your computer cursor and teaches you anything in real time for free".
3. **Let me show you.** One concrete, relatable use case, "let's say I'm learning how to color grade in DaVinci Resolve". The contrast is the status quo ("instead of going to a YouTube video"). The payoff is the product visibly doing it: the pointer bubble "this one!" on the Lift wheel.
4. **Acceptance test** [22:34]: a "super clear hook" plus a "very clear why you should care right now while you're on your scroll". The edit is checked against "am I bouncing, when am I bouncing" [22:44].
5. **Scripted.** He wrote it and knew while writing that it would go big [21:03]. This links to the 10:30 chapter: every line is scripted and rehearsed [14:00-14:16].

**The "convert" in the chapter title** is supported in this span only by:
- 20.9M views (on screen);
- "still driving a lot of our traffic" [21:11] (no data shown);
- reuse as a Facebook ad [21:17].

No conversion figure is given in this span. The interview's only conversion numbers come later: 7,000 downloads on 3M X views (under 1%), and about 20% from a 20K-view YouTube video [31:13-31:42], outside this slot.

## 4. The "thousand shots" volume rule, with every number

- **Rule** [20:25]: "if you don't take a thousand shots you're not gonna make the … five thousandth shot". The 1,000 is a figure of speech, not a count he reports.
- **His evidence is cadence and duration, not a hit rate:**
  - at Zip he made a video for new classes that dropped "every day almost" [18:59-19:03];
  - "I've just been posting these for just years" [20:09];
  - Aaron says "five years since then" [20:36].
- **Early outcomes:**
  - 23 likes on the Feb 2021 launch (on screen: 23 likes, 3 replies, 1 repost, 1 bookmark);
  - about 80 followers in Dec 2020 (spoken, not shown);
  - the Dec 2020 landing-page post had 10 likes and the Nov 2020 selfie had 17 likes (on screen);
  - none of the class videos went viral [19:13].
- **Skill threshold:** "make like 10 of those, then you get really good at talking about stuff" [22:28].
- **Visible hit distribution** on his Instagram grid (MEASURED, I5):
  - seven tiles at 13.6K-29.8K;
  - 29.3K, 160K, 462K, 1.4M, 2.5M, 4.5M;
  - one at 20.9M.

  That is about 1 of 14 counted tiles above 5M, and 4 of 14 at or above 1.4M. This is INFERRED from a partial grid, not a full census.
- **Take-up of his advice:** 1-2% of people he tells actually post [27:46].
- **Daily cost:** 10 minutes out of an 8-hour laptop day [28:32-28:44]; a 30-second selfie [27:30].
- **Recurring team format:** every two weeks, about 10 minutes to make [26:30-26:51].
- **Later in the interview** (outside the slot, for context only): the 30-day challenge, one video a day for 30 days, says one video will "probably" pass 1,000 views [46:17-46:41].

---

## (a) Procedure steps implied by this span

1. Treat every new thing the company does as a launch, however small. If more than zero people might see it, post about it. [18:43-18:59]
2. Post on a near-daily cadence, attached to what actually shipped that day. Do not save it up for "big" launches. [18:59-19:03, 28:56-29:09]
3. Before posting, accept a zero-view outcome. After posting, close the app; review results about a week later, not live. [16:56-17:10]
4. Expect early posts to be weak (23 likes, 10 likes, 80 followers) and keep shooting. Plan for about 10 videos before you are good at talking about the product. [18:31, 19:50, 22:28]
5. If you have nothing produced, make the minimum version: selfie mode, about 30 s, "hi, this is what I'm working on, check this out", then turn the camera to the screen. [22:19-22:28, 27:25-27:37]
6. Use the daily prompt: take 10 minutes to ask "what did I do today that made me smile or was interesting?" Talk about it, show it, post, return to work. [28:32-28:56]
7. Script the video. Write the lines ahead (this links to the 10:30 chapter), and judge at script stage whether it can go big. [21:03]
8. Structure it with the formula: who I am, then what's going on (hook), then what I'm working on (name plus a one-line value proposition), then "let me show you" (one concrete use case with the product visibly doing it). [21:51-22:14]
9. Build the hook from recent social proof, plus self-deprecation, plus a named credential or niche marker that your target audience recognizes. Show proof on screen (the viral post, the YC badge). [21:26-21:51]
10. Check the cut against two tests: is the hook super clear, and is it clear why the viewer should care right now, mid-scroll? [22:34]
11. Run the bounce test on your video and on others': "am I bouncing, when am I bouncing?" Cut what causes the bounce. [22:44]
12. Keep a swipe file: watch Reels to study, not for entertainment. When a hook works on you, note the device (curiosity-gap opening such as "two months ago…", lighting, caption placement) and adapt it as a template for your own story. [22:48-23:30]
13. Frame the demo as a mini story, with the founder as a character viewers can root for. Self-deprecation helps. [23:48-24:33]
14. Add a recurring process format: a short team update, "everything we built this week". Each person states one change, with no hook or story required. Prompt with "what are you doing today?" Keep it to about 10 minutes of effort, every two weeks; it doubles as public accountability, like a stand-up. [24:52-26:51]
15. Show process: what you are doing and why. Do not make "day in the life of a founder" content. [25:27-26:09]
16. Let the team's real energy (music choice, clapping, support) show; do not fake it. [26:56-27:25]
17. Post the same video across Instagram, TikTok, Reddit and YouTube "or wherever". [27:37-27:41]
18. When a video wins, keep it working: it keeps getting served organically, and you can repurpose it as a paid ad (he runs the winner as a Facebook ad). [21:11-21:22]
19. Push through the cringe phase deliberately: post the first videos you think are horrible, and continue. [28:12-28:28]

## (b) Numbers (every number said or shown in the span)

| [mm:ss] | Number | What | Kind |
|---|---|---|---|
| 16:56 | 0 | "zero attention, zero views" is still OK | rule framing |
| 17:10 | ~1 week | when he checks how a post did | anecdote |
| 17:42 | 2021; "a year after YC" | date of the Zip example | anecdote; on screen Feb 19, 2021 (MEASURED) |
| 18:04 | 4 | new classes in the launch | spoken; on screen 4 listed (MEASURED) |
| 18:14 | 7-12 | class ages | spoken; on screen "Ages: 7-12", plus "30 Mins" (MEASURED) |
| 18:31 | 23 | likes on the Zip launch | spoken; on screen 23 likes, 3 replies, 1 repost, 1 bookmark (MEASURED) |
| 18:37 | 1 | comment ("one comment from a guy"), 1 bookmark | spoken (screen shows 3 replies) |
| 18:54 | "23 views" (sic), "more than one view" | threshold rule | spoken (he says views; the screen count is likes) |
| 19:03 | "every day almost" | class-drop cadence at Zip | anecdote |
| 19:37 | December 1st 2020 | first day at the company, landing-page launch | spoken; on screen Dec 1, 2020 (MEASURED) |
| 19:38 / 19:59 | 0:05 | length of the Canva video | MEASURED (player) |
| 19:38 | 2 replies, 10 likes | Dec 1 2020 post | MEASURED |
| 19:50 | ~80 | followers at the time | anecdote (not shown) |
| 19:55 | 4 years | "next four years" (Nov 7 2020 selfie) | spoken; video 0:10, 17 likes (MEASURED) |
| 20:25 | 1,000 / 5,000th | thousand shots | metaphor |
| 20:36 | 5 years | since 2021 (Aaron) | spoken |
| 20:50 | ~1 hour | a produced video, for him | anecdote |
| 21:05-21:08 | 29.8K, 22.5K, 27.6K, 22K, 19.3K, 13.6K, 17.9K, 462K, 160K, 29.3K, 2.5M, 4.5M, 1.4M, 20.9M | Instagram reel view counts on his grid | MEASURED (on screen) |
| 21:07 | 21 million | Instagram views of the Clicky reel | spoken; on screen 20.9M (MEASURED) |
| 21:29 | 2.8M views; 1.7K reposts; 15K likes; 5:38 PM Apr 6, 2026; 0:54 | the X launch post inside the reel | MEASURED |
| 21:30 | 335K likes; 55.8K comments; 2,681 reposts | Instagram stats of the Clicky reel | MEASURED |
| 21:30 | 100 / 18 / 100 / 2 | Instagram activity badge (comments / likes / follows / other) | MEASURED; meaning of the last figure not established |
| 22:14 | 4-6 hours | time to make the Clicky reel | anecdote |
| 22:28 | ~10 | videos needed to get good | anecdote / rule of thumb |
| 23:00 | 7,752 / 108 / 45 | kael_newman reel likes, comments, reposts | MEASURED |
| 23:16 | "two months ago" | the caption device | spoken |
| 23:33-23:46 | 3,145/122/36; 2,861/160/45 with "2,444,448" streams; 30/14; 3,990/62/374; 66/8 | other reels in the scroll | MEASURED |
| 23:30 | 2 million streams | the lyrah hook | spoken, read off the screen |
| 23:36 | 6 months | the albo_app hook | spoken, read off the screen |
| 24:44 | 31 posts, 87.6K followers, 309 following | farza954 | MEASURED |
| 24:47 | 48 posts, 35.4K followers, **5** following; "+ 82 more" | _heyclicky | MEASURED (3x zoom) |
| 24:51-24:52 | 12.2K/153; 1,457/39; 528/39 | hover like and comment counts on _heyclicky tiles | MEASURED |
| 25:22 | ~1 million ("almost") | Instagram views of the weekly update | spoken by Aaron; not shown |
| 26:25 | 4 | "random group of four guys and girls" | spoken (6 people visible in I12, MEASURED) |
| 26:30 | 10 minutes | time to make a team update | anecdote |
| 26:51 | every 2 weeks | update cadence | anecdote |
| 27:30 | 30 seconds | recommended selfie length | rule |
| 27:46 | 1-2% | share of advised people who actually post | anecdotal estimate |
| 28:32 | 8 hours | founder's daily laptop time | rhetorical |
| 28:44 | 10 minutes | daily reflect-and-post time | rule |

## (c) Contradictions or tensions with the rest of the interview

1. **"You don't have to produce" vs his own examples.** He says an iPhone video can do well [20:59] and gives the 30-second-selfie advice [27:30]. But every example in this span that performed is produced: the 20.9M reel (4-6 hours, cinematic, word-level captions, about 1 cut/s) and the graded multi-location team update. His first hire was a filmmaker [39:05-39:55]. The lo-fi examples he shows (the Zip launch, the Canva post) got 10-23 likes. **INFERRED:** "lo-fi is fine to start" and "what went viral was produced" are both true, and a method should not imply lo-fi reaches the same ceiling.
2. **"No hook, no story" vs "formula always the same" and "script every video".** The team update is explicitly hook-less [25:12], yet the Clicky reel is cited as a model *because* of its hook [21:36], and at 14:00 he says every line of another video was scripted three days ahead. **INFERRED:** there are two registers. Acquisition videos follow the formula and are scripted. Recurring process updates are loose and target existing users ("our users have been loving it" [24:41]).
3. **"We make these in 10 minutes" [26:30] vs what is on screen.** The update shows graded footage, multiple locations, B-roll, a title card and burned captions (MEASURED, I12). Ten minutes is plausible for each person's capture, but not for the edit. INFERRED; the edit time is not stated.
4. **Zero-views mindset vs prediction and study.** He says he does not care about views and forgets posts [16:56-17:10], yet he "knew" the Clicky script would go big [21:03], studies reels for hooks [22:54], and the 30-day challenge asks you to analyse the video that got 1,000 views [46:29]. Not a true contradiction: the post-time detachment is emotional, and the review is deferred and deliberate.
5. **Twitter as the proof shot vs Twitter as the worst channel.** The Clicky reel's hook uses the 2.8M-view X post as social proof (MEASURED, I6). Later he calls Twitter his worst-converting channel (7,000 downloads on 3M views, under 1%) [31:07-31:19]. A viral X post can be valuable as a credential inside a video on another platform even when it converts poorly itself (INFERRED).
6. **"Convert" in the chapter title vs evidence.** This span shows views (20.9M) and asserts traffic and ad reuse, but gives no conversion data. Conversion figures appear only at 31:13-31:42.
7. **"Against founder-life content" vs a character-driven persona.** He refuses "my day as a YC founder" videos [25:52]. Yet A frames his success as "the character Farza" [24:13], and the hook is about *him* (went viral, got into YC). His line is "what I'm doing and why", not "my life" [26:05]. The hook does personal narrative in service of the product.
8. **Counts said vs counts shown:**
   - "21 million" said vs **20.9M** shown;
   - "one comment" said vs **3 replies** shown;
   - "23 views" said at 18:54 vs **23 likes** shown;
   - elsewhere he says "nearly 3 million views" [06:58] and "3 million views" [31:13] for the original Clicky X video, while the screenshot inside the reel shows **2.8M**.

   All are rounding-level, but a method document should quote the screen, not the speech.
9. **"Solo founder now" [17:51]** vs the team of about 6 shown in I12, and "random group of four guys and girls" [26:25]. Most likely ASR or meaning drift ("solo founder" at earlier companies). Not resolvable from the audio transcript alone.
