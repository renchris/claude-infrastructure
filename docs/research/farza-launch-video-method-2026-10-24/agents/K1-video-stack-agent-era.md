# K1: Farza's video stack (40:49-45:41), with prices and agent-era equivalents

Slot K1-video-stack-agent-era. Run date 2026-10-24.

Source: YC interview, Aaron Epstein with Farza Majeed. Posted by @ycombinator ([x.com/ycombinator/status/2113654566776709147](https://x.com/ycombinator/status/2113654566776709147)); YouTube `v12aSIZIXUs`. All `[mm:ss]` times are absolute times in `/tmp/farza-2026-10-24/transcript.txt` (whisper large-v3-turbo). The ASR is lower-case and unpunctuated before 41:58.

Labels:
- **MEASURED**: I ran, read or saw it in this run.
- **QUOTED**: his words, with `[mm:ss]`.
- **DOCUMENTED**: a source states it; the URL is given.
- **INFERRED**: my own reasoning.

## 0. What the segment is, and what it shows on screen

- **MEASURED, cuts.** I ran the luma-diff one-liner from `skills/video-understanding/SKILL.md` over 40:40-45:45. It found 24 hard cuts: 40:41.08, 40:46.51, 40:49.22, 40:52.14, 41:00.23, 41:06.94, 41:27.71, 41:42.77, 41:57.45, 42:32.40, 42:56.26, 43:04.81, 43:10.48, 43:34.22, 43:51.78, 44:03.29, 44:12.63, 44:35.74, 44:50.71, 44:59.80, 45:02.72, 45:10.27, 45:39.59 and 45:41.30. I also swept 99 frames at a 3 s interval from 40:48 to 45:42, and checked the 1.7 s shot from 45:39.6 to 45:41.3 on its own.
- **MEASURED, inserts.** Only two shots in the segment are not the studio interview angles (wide two-shot, guest close-up, host close-up). Both are screen recordings of his Mac.
  1. **41:00.23-41:06.94**, under "records your screen records your local audio makes your cursor look good" [40:58].
     - It shows his LinkedIn profile feed: "Farza Majeed · DREAMING :)", 15,972 followers. One post reads "We hit $10K MRR on heyclicky yesterday. It's been 9-weeks since I started working on it…", with 1,106 reactions and 50,677 impressions.
     - The post's video shows him in a convenience store, holding a small black device with a green light to his mouth. It has a burned-in white caption, "just to learn why people use".
     - The cursor is a system arrow with a separate orange triangular "buddy" pointer beside it.
     - A dark floating recorder bar runs along the bottom: "Recover 2 unfinished recordings", Display / Window / Area / Device, "No camera", "MacBook Pro…" (mic), "Record system audio".
     - Frames: `/tmp/farza-K1-video-stack-agent-era/f-2463.jpg`, `crop-2463-post.jpg`, `crop-2463-cursor.jpg`.
  2. **45:02.72-45:10.27**, under "I always use this thing called FreeWrite" [45:01].
     - It shows a plain, chrome-less writing document: "When talking to our users, we found many of them want to use agents more!… If you ask for the right things though, agents can be really magical.… <Interview, fashion designer>". The same recorder bar is along the bottom.
     - Frame: `/tmp/farza-K1-video-stack-agent-era/f-2706.jpg`.
     - Prior probe E1 (Q22) found the same document and the same toolbar, and identified it as the script shown at 10:38-10:54. The insert bounds match: E1 has 2702.70-2710.25, I have 2702.72-2710.27.
- **No gear is shown on screen.** No camera, DJI mic, DaVinci or Edits appears anywhere in 40:49-45:41 (MEASURED, frame sweep above). Prior probe E1 records the host holding "a small DJI mic" at 00:14 (E1 line 41). That is outside this segment.
- **INFERRED, the recorder bar is Screen Studio's.**
  - Screen Studio's own site describes iPhone/iPad capture you "pick … in the recording bar" (MEASURED, curl of [screen.studio](https://screen.studio/) on 2026-10-24). The bar has a "Device" mode, and he names Screen Studio as his demo recorder at 40:53.
  - I did not see the app's name in either frame.
- **INFERRED, the document app is FreeWrite.**
  - FreeWrite's default font is `Lato-Regular` (MEASURED: `ContentView.swift` line 90 in [github.com/farzaa/freewrite](https://github.com/farzaa/freewrite)). The document text at 45:06 looks like Lato.
  - The insert is cut to the line where he names FreeWrite.
  - The app's name is not visible on screen.

## 1. Every tool, gear item and step he names, in his order

He describes it as levels of production, from cheapest to most produced, plus three things that cut across all levels: audio, a filmmaker partner, and writing.

### 1.1 Level 1: screen demo, with Screen Studio

- **What he says (QUOTED):**
  - "for demos on my computer which is just like what i'm hacking on that day i always use this thing called screen studio" [40:48-40:53]
  - "i think it's like made by some indie hacker" [40:58]
  - "records your screen records your local audio makes your cursor look good and i think it costs like 30 bucks" [40:58-41:03]
  - "that's like one level" [41:03]
- **Why:** daily hacking demos. The selling points are screen, local audio and a good-looking cursor.
- **Current version and price (MEASURED, curl of [screen.studio](https://screen.studio/) on 2026-10-24):**
  - The banner reads "Screen Studio 4.0 released".
  - Two plans: **$29/mo monthly**, or **$9/mo billed yearly**, which the site calls "Save 69%".
  - Both include "Export up to 4K at 60 fps, Shareable links, Cloud transcript". The site recommends "macOS 13.1 or later".
  - DOCUMENTED (third party, [trainn.co](https://trainn.co/blog/screen-studio-pricing/)): yearly works out to $108/yr. A former one-time licence of about $229 is no longer sold to new buyers. The maker is Adam Pietrasiak ([trainn.co](https://trainn.co/blog/what-is-screen-studio/)).
  - INFERRED: his "like 30 bucks" matches today's monthly price. It is no longer a one-off purchase.
- **Cheaper or free alternatives (DOCUMENTED, [alternativeto.net](https://alternativeto.net/software/screen-story), [openalternative.co](https://openalternative.co/alternatives/screen-studio)):**
  - Cap: AGPLv3, freemium; AI transcripts are paid.
  - OpenScreen: MIT, with manual zoom and motion blur.
  - OBS Studio: free, but no automatic zoom.
  - INFERRED: macOS's built-in Cmd-Shift-5 recorder costs nothing, but has no cursor smoothing or auto-zoom.
- **Agent-era equivalent:**
  - **Can do (MEASURED tool availability on this machine):** `ffmpeg` 9.0.1, `agent-browser`, `auto-editor` and the `hyperframes*` skills are installed.
    - An agent can script a browser flow and record it, at a fixed window size, with no stray notifications.
    - It can trim dead air (`auto-editor`, `silencedetect`), add zooms and a cursor highlight in post (HyperFrames or Remotion compositions), and make a 9:16 crop.
    - The repo's `skills/demo-recording` already covers capture, then contact-sheet review, then encode, for silent README loops.
  - **Cannot (INFERRED):**
    - Choose *which* moment of today's hacking is the interesting one.
    - Produce the spontaneous "I'm hacking on this right now" feel. A scripted, agent-driven run reads as a product tour, not as a founder working.
    - Supply the voiceover. His Level 1 records *his* local audio while he demos.
  - **Maturity (INFERRED):**
    - Recording a deterministic web flow is mature.
    - Recording a native desktop app driven by an agent is fragile: permissions, focus and timing.
    - Auto-zoom in post is solved inside Screen Studio. An agent rebuilding it in HyperFrames is a custom job each time.

### 1.2 Level 2: iPhone selfie, edited on the phone in Edits

- **What he says (QUOTED):**
  - "videos that more include me in a more kind of like uh kind of native way and for that i'll just pull my iphone literally just a selfie camera and just record myself talking" [41:07-41:17]
  - "on my phone uh it's uh instagram's editing too it's called edits" [41:17-41:23]
  - "so that's the iphone uh nothing else required" [41:23-41:28]
  - In the 30-day challenge: "iPhone or Android, it's okay." [46:02]
- **Why:** this is "native" content for the feed; it is fast, and he edits on the phone.
- **Current version and price:**
  - Edits is **free**. Mosseri has said some AI features may be paid later ([planoly.com](https://planoly.com/blog/instagrams-edits-app-review), [techradar.com](https://www.techradar.com/computing/instagram/i-cant-wait-to-try-edits-instagrams-answer-to-capcut-and-its-out-now-as-a-free-download), DOCUMENTED).
  - Third-party feature lists name a teleprompter, auto-captions, 4K export, a 10-minute cap and an Instagram login requirement ([planoly.com](https://planoly.com/blog/instagrams-edits-app-review)). A Jan-Feb 2026 roundup adds caption animations and volume ducking ([metricool.com](https://metricool.com/video-editing-apps-for-instagram/)).
  - **I could not verify the current Edits version number.**
  - iPhone: I did not look up prices. He says the phone you already own is enough [46:02].
- **Cheaper or free alternatives (INFERRED):** Edits is already free. CapCut has a free tier; the phone's own Photos trim also works. Any Android phone will do, by his own words [46:02].
- **Agent-era equivalent:**
  - **Can do:**
    - Take the raw selfie file off the phone, then transcribe it locally. MEASURED: `whisper-cli` large-v3-turbo ran on a 25 s clip in this run.
    - Cut the ums and silences, normalise loudness (`loudnorm` is present, MEASURED), add burned-in captions, and export 9:16 and 1:1.
    - Draft the post copy.
    - Captions caveat (MEASURED): this machine's ffmpeg has **no `drawtext`, `subtitles` or `ass` filter**, so burned-in captions have to go through HyperFrames/Remotion or ImageMagick overlays, not a plain ffmpeg filter.
  - **Cannot (INFERRED):**
    - Be the face. The whole register is the founder talking to his own phone.
    - Post. Outbound posting is the founder's act, and this harness forbids it in any case.
  - **Maturity (INFERRED):** transcript-driven rough cuts and auto-captions are mature commodity features. Edits and CapCut do them in-app. An agent adds value mainly when the same take has to be versioned for several platforms.

### 1.3 Level 3: "cinematic", with Sony FX3 / FX30 and a DJI mic

- **What he says (QUOTED):**
  - "you feel like you want to do something a little bit more kind of like thought through cinematic uh and that's where i use my sony fx3 and sony fx30 or sony fx3 the cheaper one along with a dji mic" [41:28-41:38]
- **ASR check (MEASURED):** I re-ran whisper on 41:25-41:50 with a spelling prompt. It returned the same words: "Sony FX3 and Sony FX30 or Sony FX3, the cheaper one".
  - INFERRED: he almost certainly meant "or the FX30, the cheaper one". The FX30 is the APS-C, cheaper sibling (prices below).
  - INFERRED: he does not say which DJI model, and the transcript does not tell us which camera he uses for what.
- **Current price, Sony FX3 (DOCUMENTED, [ymcinema.com, 2026-10-06](https://ymcinema.com/2026/10/06/sony-fx3-3998-lowest-price-2026/)):**
  - List price **$4,299.99**. Amazon had it at **$3,998** during Prime Big Deal Days (Oct 6-7).
  - The article names the current unit "Sony FX3A".
- **Current price, Sony FX30 (DOCUMENTED):**
  - Glazer's lists the body at **$2,099.99**, or $2,499.99 with the XLR handle ([glazerscamera.com](https://www.glazerscamera.com/collections/sony-cinema-fx30-fx3); the page is undated).
  - A price tracker logs 2026 Amazon dips to about $1,798 ([pricehistory.app](https://pricehistory.app/p/sony-cinema-line-fx30-super-35-camera-iuTl2pw8)).
- **Not verified:** Sony's own store pages returned about 470 bytes to curl (MEASURED), so no first-party price for either camera.
- **Current price, DJI Mic:**
  - MEASURED: curl of [dji.com/mic-3](https://www.dji.com/mic-3) returned page JSON with `"price":"USD $169"` for "DJI Mic 3" (base SKU), marked `out_of_stock`. I did not establish which configuration that price is.
  - DOCUMENTED: the Mic 3 kit (2 TX + 1 RX + charging case) sold for about $249-259 against a $329 reference ([slickdeals.net](https://slickdeals.net/f/19343196-249-dji-mic-3-2-tx-1-rx-charging-case-wireless-microphone-at-amazon)).
  - DOCUMENTED: the Mic Mini kit was about $79 on Amazon in April 2026 (search result summary of deal listings, [slickdeals.net](https://slickdeals.net/f/19211041-dji-mic-mini-transmitter-infinity-black-ultralight-wireless-lavalier-microphone-for-dji-action-5-pro-osmo-pocket-3-2-colors-25-free-shipping-w-prime-or-on-35)).
- **Cheaper alternatives:**
  - QUOTED, his own advice: "invest in one of those super cheap DJI mics, find them used online" [42:17-42:23].
  - INFERRED: for the camera, the phone's rear camera, or a used mirrorless body, is the cheap path. He himself puts the phone first.
- **Agent-era equivalent:**
  - **Can do (INFERRED):**
    - Write a shot list and gear checklist from the script.
    - Check settings consistency across clips (`ffprobe`: frame rate, resolution, colour profile).
    - Sync the DJI audio to camera audio by waveform cross-correlation, and apply a starting LUT or grade.
    - Assemble a first cut against the script. MEASURED from Blackmagic's 21.x page: DaVinci's IntelliScript "compares the script text to the original transcribed audio and creates a cut" ([blackmagicdesign.com whatsnew](https://www.blackmagicdesign.com/products/davinciresolve/whatsnew)).
  - **Cannot (INFERRED):** operate a camera, light a room, pick a location, or direct a performance. Text-to-video models can make b-roll and establishing shots. They cannot make the real founder in a real place with the real product, which is the point of this register.
  - **Maturity (INFERRED):** generated b-roll is usable for abstract cutaways. It is a credibility risk if viewers can read it as the product or the founder.

### 1.4 Cross-cutting rule: audio quality comes first

- **What he says (QUOTED):**
  - "the most important thing in any video you make it doesn't matter if it's a shitty loom or a shitty like little video or your iphone is audio quality" [41:46-41:55]
  - "if your audio is bad i'm bouncing" [41:55]
  - "I've watched some demos that are like 720p … but his audio is crisp." [42:00-42:06]
  - "any mic that's not your MacBook mic or your AirPod mics, those don't count." [42:24-42:27]
  - This is the only absolute rule in the segment. Picture quality is explicitly negotiable: "I don't care about the rest of it." [42:11]
- **Tools and prices:**
  - The DJI mic (above).
  - Software rescue tools, DOCUMENTED: Adobe Podcast Enhance Speech has a free tier (1 hour/day, 30-minute files, audio only); Premium is about $9.99/mo ([feisworld.com](https://www.feisworld.com/blog/adobe-podcast-enhance-speech-v2), written by an Adobe ambassador).
  - Descript's Studio Sound is metered by AI credits ([sonix.ai](https://sonix.ai/resources/descript-review-pricing/amp/), a competitor's write-up).
- **Agent-era equivalent:**
  - **Can do:**
    - Measure the audio rather than guess. Per-0.25 s RMS, noise floor in the gaps (`silencedetect`, `astats`) and integrated loudness (`loudnorm`) are all present (MEASURED).
    - Gate a take: "noise floor too high, re-record with the lav", before any editing starts.
    - Denoise lightly: `afftdn` and `arnndn` are present in this ffmpeg (MEASURED).
  - **Cannot (INFERRED):**
    - Make a MacBook-mic recording sound like a lav. Room reverb and distance are baked in, and enhancement tools trade them for artefacts.
    - The fix is upstream, a ~$80-170 mic, which only the founder can wear.
  - **Maturity (INFERRED):** measuring is mature; repairing is "good enough for a rescue", not a substitute.

### 1.5 Editing on the laptop: DaVinci Resolve

- **What he says (QUOTED):** "And then for editing on my actual laptop, I use DaVinci." [42:32]
  - Elsewhere in the interview, he demos Clicky teaching him DaVinci: "let's say i'm learning how to color grade in davinci results" [22:05].
  - Prior probe E1 (08:45.5) read his launch post: "I've been using it the past few days to learn Davinci Resolve, 10/10."
- **Current version and price (MEASURED, curl of [blackmagicdesign.com/products/davinciresolve](https://www.blackmagicdesign.com/products/davinciresolve) and [/whatsnew](https://www.blackmagicdesign.com/products/davinciresolve/whatsnew) on 2026-10-24):**
  - The pages show "DaVinci Resolve 21" and "What's New in 21.1".
  - Resolve itself is **free**. **Studio: "Was $295 Now $236".**
  - DOCUMENTED: the 20% sale runs to 20 November ([ymcinema.com via search](https://ymcinema.com/?p=29266); [redsharknews.com](https://www.redsharknews.com/davinci-resolve-studio-21-sale-20-percent-off?hs_amp=true)).
  - MEASURED from the whatsnew page:
    - 21.x lists IntelliSearch ("find specific objects or key words in dialog").
    - IntelliScript with plain-text and Final Draft scripts.
    - Vertical and square timelines with Smart Reframe.
    - Direct upload to social accounts.
- **Cheaper alternative (INFERRED):** the free Resolve. He does not say whether he uses Studio.
- **Agent-era equivalent:**
  - **Can do (INFERRED from the tools listed):**
    - Produce a full first cut outside an NLE: transcript, then paper edit against the script, then ffmpeg concat; HyperFrames for titles and motion graphics.
    - Or hand Resolve a plain-text script for IntelliScript.
    - Write the captions file and the per-platform exports.
  - **Not verified this run:** whether Resolve's scripting API can be driven headlessly on the free edition.
  - **Cannot (INFERRED):** the edit decisions that make his videos work. These are the hook in the first seconds, when to drop the music, and holding a no-cut take (his point at 37:02, outside this segment). An agent can propose these, and a human has to judge them.
  - **Maturity (INFERRED):**
    - Assembly and rough cut: usable now.
    - Colour: preset level.
    - Pacing and taste: not delegable.

### 1.6 The filmmaker partner (Vikrant)

The spelling is ASR's; it is not seen on screen, and a web search did not resolve it.

- **What he says (QUOTED):**
  - "maybe the most important part of my stack, he's not here right now, but Vikrant." [42:37-42:39]
  - "Vikrant has made all the HeyClicky videos." [42:41]
  - "Every video we just looked at, apart from the bad Zip School ones, which were made by me, are made by Vikrant." [42:51-42:53]
  - "having a person that is actually talented at filmmaking, storytelling, writing next to you is like the biggest bonus a founder could have today." [42:55-43:01]
- **The workflow (QUOTED):**
  - "we just brainstorm" [43:09].
  - Vikrant brings shot and hook ideas [43:17-43:24].
  - Farza brings "the script and the song and the vibe that I'm going for" [43:26-43:28], because "I'm really good at writing and I'm really good at the music" [43:37-43:39].
  - Vikrant does "everything else, from shooting to picking the set to editing after to … all the little motion graphics" [43:41-43:47].
  - Why: "I don't want to spend all my time making videos" [43:58].
- **For founders who cannot hire (QUOTED):**
  - "go back to my old Zip School videos" [44:11].
  - "You got to take out your camera and start posting some cringe stuff." [44:53-44:54]
  - "in order to not be cringe, you must first be cringe." [44:56-44:57]
  - He frames this as a sequence: do it all yourself first, hire later [44:30-44:47].
- **Price:** not discussed. I did not research filmmaker rates.
- **Agent-era equivalent:** this is the role an agent most plausibly *partly* fills for a solo founder.
  - **Can do (INFERRED):**
    - The brainstorm partner: hook variants, shot ideas, a shot list.
    - The post-production half of Vikrant's job: rough cut, captions, motion-graphic titles in HyperFrames/Remotion, and versions per platform.
    - Licensing check (DOCUMENTED): HyperFrames is Apache-2.0 ([github.com/heygen-com/hyperframes](https://github.com/heygen-com/hyperframes)). Remotion is free for individuals and companies of up to 3 people ([remotion.dev](https://www.remotion.dev/docs/license)).
  - **Cannot (INFERRED):**
    - Shooting, picking the set, and directing the founder on the day.
    - The "no, bro, be quiet … we're going to post it" push from a human collaborator who has seen the take [14:29].
    - His split also says the founder owns script, music and vibe. So even a perfect agent would not take over those.
  - **Maturity (INFERRED):**
    - Brainstorm and post-production assistant: usable now.
    - Camera operator or set designer: no.
    - Motion graphics from HTML/React compositions: usable with iteration. Taste review stays human; the repo's `launch-film` skill exists because agent-made films drew operator rejections.

### 1.7 Writing before recording: FreeWrite (his own app)

- **What he says (QUOTED):**
  - "for all of my writing, I always use this thing called FreeWrite." [44:59-45:01]
  - "It's free to download, freewrite.io." [45:04]
  - "I built it actually just for this purpose." [45:06]
  - "Yeah, free, open source." [45:08]
- **The step (QUOTED):**
  - "spend as much time possible before the video writing it." [45:14-45:15]
  - "Try writing for just 10 minutes about what it should be and then record it." [45:27-45:29]
  - "you can catch a bad idea before it gets here." [45:36-45:38]
  - He exempts first-timers: "if you've never made a video, don't worry about this" [45:20-45:21]. Writing is advice for the 15th-30th video [45:22].
  - Earlier in the interview, on the depth of scripting: "this whole video scripted. Every line that I'm saying, I wrote like three days before." [14:00-14:05] He then rehearses lines in his head [14:05-14:16]. He does not name a teleprompter anywhere I read.
- **Current version and price (MEASURED, `gh api repos/farzaa/freewrite` and freewrite.io via curl on 2026-10-24):**
  - MIT licence, 1,374 stars, last push 2026-04-11.
  - Latest release **v1.5** ("freewrite [1yr]", 2026-04-10): "Video logging transcriptions with Apple Dictation".
  - The site says "it's a mac app i made for myself … all in native swift. open-source. all local. free." It also links a Windows version.
  - The source has a 15-minute default timer (`timeRemaining: Int = 900`), an optional backspace lock, and buttons that send the entry to ChatGPT or Claude with a canned prompt (MEASURED, `ContentView.swift` lines 92, 129 and 202-216).
- **Cheaper alternative:** none needed; it is free. Any plain-text editor with a timer works (INFERRED).
- **Agent-era equivalent:**
  - **Can do (INFERRED):**
    - Interview the founder by voice for 10 minutes and transcribe it locally (whisper, MEASURED working). This turns spoken thinking into a draft, which matches FreeWrite v1.5's own move to video logs with transcripts.
    - Offer hook variants, flag a weak first ten seconds, and time the script to a target length.
    - Pull the "what I shipped today" facts from git logs.
  - **Cannot (INFERRED):**
    - Write in his voice well enough that it survives being said on camera. He names writing as the part he is "really good at" [43:37].
    - Do his rehearsal-until-natural step. A script the founder did not write is the one most likely to sound read.
  - **Maturity (INFERRED):** good as an editor and sparring partner; weak as a ghostwriter for a founder-on-camera register.

### 1.8 Adjacent: the 30-day challenge (45:41 onward, read to 46:22)

- **What he says (QUOTED):** "Every day, just spend 10 minutes, take your phone out" [46:00-46:01].
  - Post to "Instagram, TikTok" [46:10].
  - "Make a new Instagram account so your existing followers don't even know." [46:12-46:15]
  - "do that for 30 days straight" [46:17].
- **INFERRED:** this is the stack collapsed to its floor. It is Level 2 with no editing, and the only hard requirement is the daily habit. An agent's honest role here is reminder, logger and caption helper. The founder records and posts.

## 2. Things on screen that bear on the stack but that he does not name

- **Burned-in captions (MEASURED, 41:03 frame):** the post clip carries white, centred, sentence-fragment captions ("just to learn why people use"). He does not name a captioning tool in this segment.
  - INFERRED: these could come from Edits, DaVinci or the editor's own workflow; this run cannot tell which.
- **Handheld mic (INFERRED from the 41:03 frame):** in the post clip he holds a small black device with a green light to his mouth, like a reporter's mic. That is consistent with a DJI Mic transmitter used handheld, but the brand is not legible.
- **The Clicky cursor (MEASURED, 41:03 frame):** an orange triangle sits beside the system cursor in his own screen recording. INFERRED: this is the Clicky "buddy next to your cursor" [22:00], recorded live. The product is visible even in his tool demo.

## 3. Summary table

The "price" column has prices as of 2026-10-24. Sources are in §1.

| Step | His tool | Price | Agent can do | Needs founder |
| --- | --- | --- | --- | --- |
| Screen demo of today's hacking | Screen Studio [40:53] | $29/mo, or $9/mo billed yearly; v4.0 (MEASURED, screen.studio) | Scripted browser capture, trim dead air, zoom/cursor emphasis in post, 9:16 crop | Choosing the moment; live narration; the "hacking right now" feel |
| Native talking-head | iPhone selfie camera [41:13]; "iPhone or Android" [46:02] | Phone you own (price not researched) | Ingest, transcribe, cut ums, captions, multi-format export | Being on camera, every time |
| Phone edit | Instagram Edits [41:17-41:23] | Free; version not verified (DOCUMENTED, planoly/techradar) | Same rough cut and captions on desktop; post copy drafts | Final look; posting (outbound is his) |
| Cinematic shoot | Sony FX3 / FX30 [41:38] | FX3 $4,299.99 list, $3,998 Amazon Oct 6 (ymcinema); FX30 about $1,800-2,100 (Glazer's, pricehistory) | Shot list, settings check, audio sync, first grade, b-roll generation for cutaways | Camera, light, location, performance, real product footage |
| Audio capture | DJI mic, "find them used" [41:38, 42:19] | Mic 3 from USD $169 (dji.com JSON); kit about $249-259; Mic Mini kit about $79 | Measure noise floor and loudness, gate bad takes, light denoise, loudnorm | Wearing a real mic; re-recording a bad take |
| Laptop edit | DaVinci [42:32] | Resolve 21.x free; Studio $236 (was $295) to Nov 20 (MEASURED, blackmagicdesign.com) | Transcript paper edit, script-matched assembly, titles and motion graphics (HyperFrames/Remotion), exports | Hook timing, music drops, when not to cut: taste |
| Filmmaker partner | Vikrant (ASR spelling) [42:39-43:47] | Not discussed | Brainstorm hooks and shots; post-production half of the role | Shooting, set, directing, the human "post it anyway" push; script, song and vibe stay with him [43:26] |
| Writing first | FreeWrite, his app [45:01-45:08] | Free, MIT, v1.5 (MEASURED, gh api) | Voice-interview to draft, hook variants, length timing, facts from git | Writing in his own voice; rehearsing until it sounds unscripted [14:05] |
| Daily habit | Phone, 10 min/day, 30 days [46:00-46:17] | Free | Reminders, logging, captions | Recording and posting, daily |
