# W1: what Farza says elsewhere about launching, demos, video and distribution (2026-10-24)

Slot: W1-farza-written-guidance. The baseline is the YC interview with Aaron Epstein (posted 2026-10-23, https://x.com/ycombinator/status/2113654566776709147). Its transcript is `/tmp/farza-2026-10-24/transcript.txt`, cited as `[mm:ss]`. This file covers what Farza Majeed (@FarzaTV) has said in other places, compares each source with the interview, and lists the track-record facts that bear on his credibility.

**Labels.** MEASURED means I fetched or ran it during this run (the tool is named). QUOTED means his own words, at most one sentence, with a URL or `[mm:ss]`. DOCUMENTED means a source states it, with its URL. INFERRED means my own reasoning. Every quote below is at most one sentence. YouTube timestamps are written `@mm:ss` and come from the auto-captions I downloaded (MEASURED: `yt-dlp --write-auto-subs`, en-orig). Auto-captions can mishear words.

**How the sources were read (MEASURED).**
- X posts: `~/.claude/bin/cc-read-twitter`, which uses the fxtwitter source. Engagement counts are as of 2026-10-24.
- Follower counts: `curl https://api.fxtwitter.com/<handle>`.
- Recent timeline: `api.fxtwitter.com/2/profile/<handle>/statuses`. It returned only the latest 22 posts, because pagination did not work.
- Substack: `farza.substack.com/api/v1/archive` and `/api/v1/posts/<slug>`.
- Web pages: `curl` with a Chrome user agent.
- YouTube: `uvx yt-dlp` for metadata and auto-captions.
- GitHub: `api.github.com`.

Scratch files are in `/tmp/farza-W1-farza-written-guidance/`.

---

## 1. Source index (27 distinct sources)

Verdict compares each source with the YC interview: AGREES, EXTENDS (adds something the interview lacks), DISAGREES, or TENSION (partly conflicts or has a different emphasis).

| # | Source | Date | Type | Verdict |
|---|---|---|---|---|
| S1 | X: Farza quote-tweeting the YC video | 2026-10-24 | own post | AGREES (his own TLDR) |
| S2 | X: original Clicky launch thread | 2026-04-07 | own post | AGREES; it is the artefact the interview analyses |
| S3 | X: "I'm gonna keep hacking on Clicky!" | 2026-04-12 | own post | AGREES, with a timing nuance |
| S4 | X: open-sourcing Clicky + GitHub README | 2026-04-08 | own post / repo | EXTENDS |
| S5 | X: teaser pattern "See you tomorrow, link below." + livestreams | 2026-04-22, 2026-05-13, 2026-10-22 | own posts | EXTENDS |
| S6 | X @heyclicky: "sorry twitter. posted this 2-months ago on insta." | 2026-09-01 | company post | AGREES (Instagram first) |
| S7 | Substack: "went to buy a bag of fresh air…" (cursor-buddy origin) | 2025-10-27 | own essay | AGREES + EXTENDS (**deep dive 1**) |
| S8 | Substack: "making tiktoks with the lads…" (Tidbit week) | 2025-08-18 | own essay | TENSION / DISAGREES on Reels (**deep dive 3**) |
| S9 | Substack: "went to the club with my raspberry pi…" (TikTok numbers) | 2025-08-31 | own essay | EXTENDS |
| S10 | Substack: "just wiped my counter top…" (first YouTube video in a decade) | 2025-04-10 | own essay | EXTENDS (time budget) |
| S11 | Substack: "theres a snowstorm in nyc…" (fear of posting) | 2026-01-25 | own essay | AGREES |
| S12 | Substack: "me and the beatles just ate some waffles…" (no vision, update people) | 2024-05-16 | own essay | TENSION (storytelling self-image) |
| S13 | Substack: "me and skrillex…" (joining YC again) | 2026-04-02 | own essay | AGREES |
| S14 | YouTube (farzatv): "the art of making something from nothing." | 2025-05-10 | own video | AGREES + EXTENDS (write the tweet first) |
| S15 | YouTube (farzatv): "im coming up with new ideas…" | 2026-04-06 | own vlog | AGREES + EXTENDS (Stripe-link test) |
| S16 | YouTube (farzatv): "im having fun building products again" | 2026-05-11 | own vlog | AGREES (process videos) |
| S17 | YouTube (farzatv): "my company hit 600 customers today" | 2026-07-15 | own vlog | TENSION (distribution vs product) |
| S18 | YouTube (farzatv): "i don't recommend being a solo founder" | 2026-10-20 | own vlog | track record |
| S19 | Podcast: Omar Waseem, "How to start over after shutting down a $100M Company" | 2026-08-26 | interview | AGREES + EXTENDS (**deep dive 2**) |
| S20 | Podcast: Omar Waseem EP33, "Buildspace: The $100M Startup Building Hogwarts IRL" | 2023-09-29 | interview | EXTENDS (narrative control) |
| S21 | TBPN interview (auto transcript via tbpndigest) | 2026-06-10 | interview | EXTENDS (video as sales on top of a business) |
| S22 | Buildspace shutdown tweet + letter | 2024-08-23 | own letter | track record |
| S23 | farza.com home page | read 2026-10-24 | own site | track record |
| S24 | Buildspace program pages (/nw (s5), /school, /sf1) + YC company page | 2023-2024 | Buildspace material | AGREES (weekly build-and-launch cadence) |
| S25 | Buildspace DMW lecture "video 101" + "good videos aren't just about hooks" (**not Farza speaking**) | 2024-02-29, 2024-03-14 | Buildspace material | AGREES (template-copying, music first) |
| S26 | YC company page for HeyClicky (Launch YC post) | 2026 | company text | AGREES |
| S27 | Neatprompts analysis, "HeyClicky got 15 million views for arguing against itself" (third party) | 2026-09-12 | secondary analysis | EXTENDS / counter-reading |

Other track-record posts (S28-S33) are listed in §4.

---

## 2. Source by source

### S1. X: Farza on the YC video, 2026-10-24
https://x.com/FarzaTV/status/2113815562329727203

- QUOTED: "This is a game of consistency, not one time viral hits."
- QUOTED: "TLDR: Record a shitty demo, and just start showing your work."
- MEASURED (cc-read-twitter): 783 likes and 53.9K views at read time.
- Verdict: **AGREES**. This is his own one-line summary of the interview. It matches "show your work every day" `[29:00]` and the 30-day challenge `[46:00]`.

### S2. X: the original Clicky launch, 2026-04-07
https://x.com/FarzaTV/status/2041314633978659092

- MEASURED (cc-read-twitter): a 3-post thread. Post 1 carries a 99.84 s video at 1660x1080. Post 1 has 15.7K likes, 1.3K replies and **3M views**.
- QUOTED (post 1): "I built this thing called Clicky." The next line is "It's an AI teacher that lives as a buddy next to your cursor."
- Reply 2 (MEASURED) gives the link plus three plain notes: which models it uses, that a screenshot is taken only on the hotkey, and "High chance I run of credits lol." Reply 3 lists extra use cases and admits it is "a bit dumb right now (only 10 messages of memory)".
- Verdict: **AGREES**.
  - The interview walks through this exact headline as "just casual, I built this thing, it's an AI teacher" `[07:51]-[07:56]`.
  - His "nearly 3 million views" `[06:58]` matches the measured 3M.
  - The 7,000 downloads and ~100 users retained for five days `[07:17]-[07:30]` cannot be verified from any public source I found.
- INFERRED: the replies follow a pattern that the interview does not spell out. The link goes in a reply rather than the main post, and caveats are stated honestly.

### S3. X: "I'm gonna keep hacking on Clicky!", 2026-04-12
https://x.com/FarzaTV/status/2043402737828962489

- QUOTED: "What's funny is I had been sitting on the Clicky demo for a few weeks."
- QUOTED: "Instead of hunting for the perfect idea, I rather ship and turn whatever I'm building into the perfect idea!"
- QUOTED: "What changed my mind was talking to all the users this week, I feel like there's so much more here than what meets the eye."
- MEASURED: 1.3K likes and 58.9K views. Reply 2 sends people to an email list at farza.com/clickyyy and says "Probably wont spam Twitter much about Clicky."
- Verdict: **AGREES**, with a nuance.
  - In the interview he records the video "five minutes before dinner" `[06:40]`. This post says the *demo* sat for weeks before that, and S19 says the same (two weeks shelved).
  - Retention calls with users as the reason to continue `[07:34]-[07:42]` match.
  - INFERRED: the quick video took weeks of hesitation before it. The method document should not present "record 5 minutes before dinner" as the whole story.

### S4. X: open-sourcing Clicky, 2026-04-08, and the GitHub README
https://x.com/FarzaTV/status/2041691382008705321 · https://github.com/farzaa/clicky

- QUOTED: "All I ask is one thing: Build something cool, show me, and share your learnings with everyone ❤️."
- MEASURED (raw README): an "Update: April 27, 2026" says the old code stays MIT-licensed and new work goes private. The README links the original tweet "that kinda blew up for a demo".
- MEASURED (api.github.com): 7,772 stars and 1,552 forks; the repo was created 2026-04-07T05:12Z.
- Verdict: **EXTENDS**.
  - The interview mentions open-sourcing only in passing: "I then even just open source[d] because I thought no one would even care" `[06:51]`.
  - INFERRED: open-sourcing the day after the launch post works as a second launch. Neatprompts (S27) credits community ports as unpaid marketing.

### S5. X: the teaser pattern and launch livestreams
- 2026-04-22 https://x.com/FarzaTV/status/2047026688970850385
  - QUOTED: "Something new."
  - QUOTED: "See you tomorrow, link below."
  - MEASURED: a 33 s video; the reply announces a livestream at 12PT; 173.5K views.
- 2026-05-13 https://x.com/FarzaTV/status/2054397864009408889
  - QUOTED: "Bringing back the computer we fell in love with."
  - MEASURED: a 66 s video; the reply announces a stream at 12PM PT; 101.8K views.
- 2025-07-23 (Tidbit) https://x.com/FarzaTV/status/1948098268883243457
  - QUOTED: "see you tmmro ❤️"
  - The reply says "we'll be going live on youtube".
- 2026-10-22 @heyclicky: "something new. see you tomorrow." The next day (2026-10-23): "we shipped something new." plus an X broadcast link.
  - MEASURED via the fxtwitter timeline: 12,761 and 27,448 views.
- Verdict: **EXTENDS**.
  - The interview does not mention a teaser-then-livestream cycle. It mentions only the weekly or biweekly "everything we built this week" videos `[24:52]`, `[26:56]`.
  - INFERRED: a fourth format exists alongside daily demos, the weekly update and the quarterly polished launch `[15:57]`. That format is a one-line teaser with a short video the day before, then a live stream on launch day.

### S6. X @heyclicky: Instagram first, 2026-09-01
https://x.com/heyclicky/status/2094638206113485124

- QUOTED: "sorry twitter. posted this 2-months ago on insta. won't ever leave you behind again."
- The post is the "june 2026 investor update" as a 122 s vertical video (1080x1920).
- MEASURED: 34.5K views.
- Verdict: **AGREES**.
  - Instagram is where they post first and where traffic comes from: "70% of our traffic is instagram" `[32:22]`, and "most of our videos we make for instagram" `[33:23]`.
  - Twitter is the afterthought because it converts worst `[31:07]`.

### S7. Substack, 2025-10-27: how the cursor-buddy idea was found and posted (**deep dive 1**)
https://farza.substack.com/p/went-to-buy-a-bag-of-fresh-air-at

This is his most detailed written account of the demo-first loop. It describes the October 2025 "ai cursor that lives on my screen as a buddy" demo (S31), which came before Clicky.

The daily rule:
- QUOTED: "Almost everyday I will make something."
- The examples are writing a content script, building a demo, or recording a video.
- QUOTED: "And then, I have to show what I made to at least 1 person."
- QUOTED: "99% of the time I think it's shit, someone else see's something cool."

The grounding image:
- When an idea strikes, usually while listening to music, he pictures a single image of a product flow or "a marketing video".
- QUOTED: "That “image” becomes my life raft I hold on to as I work on the idea."
- He says he took this from the Miyazaki documentary, where Miyazaki will not start a film until he has one frame he feels good about.
- His frame for the cursor idea was "this cute blue cursor popping in from the right side of my Mac's screen, and saying hi", with the song he had been listening to as background music.

Drafting tweets before building:
- QUOTED: "So, before I built anything further I drafted hella tweets."
- Each draft angles the idea a different way.
- QUOTED: "If it doesn't sound exciting in a tweet, then it probably won't be exciting in general."
- QUOTED: "I'm purely writing these to get my self excited and clear about the idea."

A self-imposed posting deadline:
- The feature he wanted (the cursor clicking things for you) was not working by 5PM, and "I promised myself I'd post something today".
- So he switched to an angle he could ship that day (a buddy that recommends things) and posted it.

Verdict:
- **AGREES** with working backwards from the caption and hook before building `[04:08]-[04:32]`, and with "not that it needs to go viral" `[04:15]`.
- **EXTENDS** the interview with three steps it lacks:
  - (a) the "show one person" gate before posting;
  - (b) the single grounding frame, a pre-visualised first shot that connects to the first-frame design at `[09:12]`-`[09:27]` and `[11:59]`;
  - (c) a same-day posting deadline that forces him to cut scope down to whatever angle can be demoed.
- INFERRED: Clicky's look, "this little blue guy that follows your cursor" `[06:09]`, comes directly from this October 2025 grounding image. S19 adds that the Clicky code came from an earlier "Learning Buddy" app.

### S8. Substack, 2025-08-18: the Tidbit TikTok pivot (**deep dive 3**)
https://farza.substack.com/p/making-tiktoks-with-the-lads-and

Messaging pivots instead of product pivots:
- After a simple tweet comparing Tidbit to Slack he got "almost 100+ DMs". He then dropped the "ditch Slack" story for "work better with AI".
- QUOTED: "Early days, I think it's about nailing messaging."
- QUOTED: "It was as simple as changing a few words on our landing page and in the DMs I sent people."

Leading with an emotion the audience already has:
- QUOTED: "No one gives a shit about Tidbit. But, everyone knows how they feel when they think of Slack."

Reels against TikTok:
- QUOTED: "I really dislike when people says shorts are the same across platform."
- QUOTED: "With IG Reels me + Hasan felt like we were trying way to hard to tell a story that wasn't there yet."
- QUOTED: "Also, something felt so wrong about doing the same old “tell a story about what I'm building” over a Reel thing."
- He thought it naive to expect a new storytelling style in 4 weeks, "At minimum would take 3-4 months".

Volume and roles:
- "We're doing 3-4 TikToks a day."
- QUOTED: "Hasan just puts the camera in my face, gives me a script, and I am literally just a bot for him hahaha."

B2B buyers on TikTok:
- They "started getting our first B2B customers — agencies, consulting firms, and founders from there (yes, they are all on TikTok)".

Verdict:
- **AGREES**:
  - "every channel is different" `[31:47]`;
  - B2B buyers are on TikTok, and he found ~50 design-agency leads there from videos averaging ~4,000 views `[30:28]-[30:48]`.
- **DISAGREES / TENSION**:
  - In 2025 he called "tell a story about what I'm building" on Reels a format that felt wrong. In the 2026 interview, Instagram is by far Clicky's best channel `[33:13]`, and "show what you're doing" is the core advice `[24:41]-[26:14]`.
  - Who writes the script differs. In the interview Farza brings "the script and the song and the vibe" `[43:26]`. On TikTok in 2025 the content person wrote the scripts.
  - INFERRED resolution: the Reels format works once there is a visible story to tell, meaning a demo you can see on mute. Tidbit's chat-interface value did not show on camera; S27 makes the same argument. Who leads depends on the platform's culture and the collaborator's strength.

### S9. Substack, 2025-08-31: TikTok numbers for Tidbit
https://farza.substack.com/p/went-to-the-club-with-my-raspberry

- QUOTED: "Almost ~4,000,000 views in just the last 7-days."
- The content person made "nearly 3-5 TikToks a day. Some pop. Some flop."
- QUOTED: "When we make super Tidbit specific content the conv is about 0.5% (view TikTok profile -> go to link -> make account)."
- QUOTED: "When it's more meme/trend content, much lower. But, juices algo."
- Verdict: **EXTENDS**.
  - It adds a measured conversion figure: about 0.5% for product-specific TikToks.
  - Meme content is described as feeding the algorithm rather than converting.
  - It sits beside the interview's channel ranking: YouTube converts ~20% `[31:37]`, Twitter less than 1% `[31:19]`, Instagram brings 70% of traffic `[32:22]`.
  - INFERRED: track conversion per channel with a tagged link (/ig `[32:47]`), and expect meme content to grow reach, not signups.

### S10. Substack, 2025-04-10: the first YouTube video in a decade
https://farza.substack.com/p/just-wiped-my-counter-top-with-orange

- His stated budget:
  - QUOTED: "I wrote the script in 30-minutes."
  - Shoot and edit took "5-hours the next day at 7AM (all Aiden, ty king)".
  - "Spent 3-hours on thumbnails".
  - QUOTED: "All together, ~8-hours."
- Result: "around a quarter million views across platform".
- QUOTED: "My goal is by EOY to make YT my main platform I post on."
- Verdict: **EXTENDS**.
  - It gives a concrete time budget for a long-form YouTube piece. Thumbnails take as long as half the shoot and edit, and the interview never mentions thumbnails.
  - It is consistent with "a produced video for me will take like an hour" `[20:50]` and "this took us like four to six hours" `[22:18]`.
  - It agrees with his view of YouTube as "a library that will last for decades" `[32:16]`.
  - **TENSION**: here the script took 30 minutes. In the interview the screen-dictation script was written "like three days before" and rehearsed "in the shower" `[14:03]-[14:11]`.

### S11. Substack, 2026-01-25: the fear of posting
https://farza.substack.com/p/theres-a-snowstorm-in-nyc-and-im

- He tells a would-be creator to record "a 15s video about this slice of life scene" and post it to Reels on the spot. She refuses out of fear of judgement.
- QUOTED: "You'll tell yourself hundreds of stories of why its a bad idea instead of just doing it."
- His coaching line, QUOTED: "Why do you believe something must be good to post it?"
- He says Nights & Weekends S5 had "over 120,000 people". DOCUMENTED as his claim.
- Verdict: **AGREES** closely with:
  - "take out your iphone… selfie mode and talk about what you're doing for 30 seconds" `[27:30]`;
  - "1-2% … will actually do it" `[27:46]`;
  - "you got to be cringe for a little while" `[28:17]`.
- It is the same advice in a different setting, which suggests it is a stable belief rather than a talking point for the interview (INFERRED).

### S12. Substack, 2024-05-16: no vision, keep updating people
https://farza.substack.com/p/me-and-the-beatles-just-ate-some

- QUOTED: "I had a long history of consistently saying I would do something, then doing it, and then updating people on results (whether I failed or succeeded)."
- QUOTED: "I am not naturally a guy that can tell great stories, or speak in a really persuasive way."
- Verdict:
  - **AGREES** with the public, recurring update (the weekly "everything we built" videos, `[26:43]` "stand up… in front of the world").
  - **TENSION**: in the interview he calls himself "good at making videos in general and writing stories" `[19:23]` and "really good at writing" `[43:37]`.
  - INFERRED: the 2024 line is about persuasive pitching of a vision, not narrative video. Even so, the method document should not lean on "be a natural storyteller". His own account is that the skill came from practice.

### S13. Substack, 2026-04-02: joining YC again
https://farza.substack.com/p/me-and-skrillex-at-the-club-crying

- QUOTED: "You'll probably see me launching a lot of random stuff over the next few weeks especially."
- He plans "one weekly update on YouTube", which he says is more fun than Substack.
- He says many founders in the batch credit Buildspace for getting them into YC (DOCUMENTED as his claim).
- Verdict: **AGREES** with "launch constantly" `[02:31]`.
- Timing (MEASURED): this was 5 days before the Clicky post (S2).

### S14. YouTube (farzatv), 2025-05-10: "the art of making something from nothing."
https://www.youtube.com/watch?v=izji0xYKbtM

- MEASURED (yt-dlp): 7 min 24 s, 53K views.
- This is a scripted, narrated story of making Freewrite.
- Write the tweet before building anything:
  - QUOTED @03:23: "The first thing I did was I wrote a tweet introducing the product that I hadn't even created yet."
  - QUOTED @03:29: "If I can't really explain it in 280 characters, then it's probably too complicated."
- Show one person: he showed it to Julian, and QUOTED @04:06 "That's all I needed to see."
- He called it "the shittiest, dumbest product I ever made", and then it "got two million views" @04:09-04:39.
- Earlier reach for comparison: his previous "I'm back" video did "25,000 on YouTube, 400,000 on Twitter" @00:33.
- Verdict:
  - **AGREES** with working backwards from the copy `[04:08]` and with "I thought it was horrible… I was wrong" `[14:21]-[14:51]`.
  - **EXTENDS** with a specific test: the idea must fit in 280 characters before any build.
  - The video is itself an example of "turning demos into stories" `[24:04]`: a self-deprecating arc, the blank page, the build, the embarrassment, the surprise.

### S15. YouTube (farzatv), 2026-04-06: "im coming up with new ideas…"
https://www.youtube.com/watch?v=xnv40fO7nw0

- He posted a personal-Wikipedia demo on a Saturday: "literally like 1.1 million views" @12:13.
- He then put "a Stripe link on Twitter", and if he gets "the 25 customers that I'm looking for" he will keep going @12:28.
- QUOTED @16:35: "And 1 million views on Twitter doesn't mean [__] to me."
- Verdict:
  - **AGREES** with "I do not care about the traffic at all" `[07:05]`.
  - **EXTENDS** with a paid-intent test: a Stripe link with a customer-count threshold right after the demo. That is stronger than the download and retention test he describes for Clicky `[07:17]`.

### S16. YouTube (farzatv), 2026-05-11: "im having fun building products again"
https://www.youtube.com/watch?v=vl2P_eRDukA

- QUOTED @10:14: "We're just making videos about us and our process."
- The same passage says "we're not trying to make videos that are popping off talking about our product", and the team works "with the intention of building towards release about the end of the week" @10:44.
- Verdict: **AGREES** with the weekly process videos: "there's no hook there's no attention there's no story" `[25:17]`, and "most companies just never show their process" `[26:09]`.

### S17. YouTube (farzatv), 2026-07-15: "my company hit 600 customers today"
https://www.youtube.com/watch?v=Wwjj-zaJhSE

- QUOTED @03:37-03:52: "It actually really annoys me when people say that distribution is like the most important thing … in 2026."
- QUOTED @06:28: "distribution is nothing without like a good product."
- He grants that his following helps "to an extent" @05:11.
- Verdict: **TENSION**.
  - The interview frames audience as the moat: "someone can clone my product in like two minutes… what's really hard to clone is the audience" `[40:17]-[40:27]`.
  - This vlog says distribution alone is worthless.
  - INFERRED: the two fit together as "product first, then audience as the compounding advantage". The method document should state that demo videos amplify a product people can see working; they do not replace one. S27 makes the same point with Tidbit.

### S18. YouTube (farzatv), 2026-10-20: "i don't recommend being a solo founder"
https://www.youtube.com/watch?v=WdHrHBILq98

- QUOTED @00:16-00:31: "we went from like 1,000 customers to now we're at like 2,200 customers."
- He continues @00:31: "we're almost at a million dollars ARR now", and "I think we got like 40 million views in the last 40 days, 30 days".
- DOCUMENTED as his own claim. These figures are not independently verified.
- Verdict: track record only (see §4).

### S19. Omar Waseem podcast, 2026-08-26 (**deep dive 2**)
https://www.youtube.com/watch?v=Z98ZuXR7kDM

MEASURED (yt-dlp): 68 min, 24.5K views, posted on Omar Waseem's channel. The host says it was recorded about a month before release @56:21, so roughly June to July 2026 (INFERRED from that remark).

The Clicky origin, which matches the interview:
- He built "Learning Buddy" and did not post it, calling it "a stupid idea" @54:19.
- While learning DaVinci to shoot his own weekly YouTube vlogs, he kept screenshotting into Claude @54:34-55:20. That gave him the idea of a buddy that could see the screen when you press a button.
- He "tabled it for another two weeks" until his YC partner Aaron asked about it @55:35.
- QUOTED @55:50: "I don't care how dog the idea is."
- He finishes the thought: "I will happily just post it cuz I have no care about my own reputation". It "took a while to get to" @56:05.

Detachment from the audience:
- QUOTED @63:08-63:24: "when I put something out I'm like zero people care about this."
- He says he gained that detachment "over the last 10 years".

Why he likes demo-shaped work:
- QUOTED @40:34: "working on something where I can like put it out aggressively hopefully um, like where people can see it quickly."
- He contrasts this with a car company that "takes four years of not showing anybody anything" @40:51.

Hits are irregular:
- People think "every idea I'm making hits", but "no one sees 2025" @60:45.
- He expects a pattern like "boom boom boom boom and then no one cares" @61:00.

On Buildspace:
- Asked why he did not sell, QUOTED @05:57: "I just thought the thing was worthless."
- He adds that in hindsight he "may have done certain moves differently like financial moves" @06:28.
- He took six months off and "did nothing" @12:08.
- When he came back, "it took 6 months just to get like even just base level confidence again to think that anybody would even care" @27:18.

Money:
- An Accel partner he had worked for at 22 offered $3M @59:44. He reached "$4 million" before demo day @60:30 and "landed at the $12 million number", which he notes matches Buildspace's lifetime total @61:34. DOCUMENTED as his claim.

Verdict:
- **AGREES** on several points:
  - Aaron pushing him to post `[06:19]-[06:29]`;
  - "if this gets zero attention… I'm still happy I posted it" `[16:56]`;
  - "By the time I hit post, I've already forgotten it" `[17:08]`;
  - "you just put so much garbage out there" `[17:24]`.
- **EXTENDS** on three points:
  - (a) the hesitation lasted weeks, not minutes;
  - (b) his detachment is a learned stance that took a decade, so the method document should coach a newcomer toward it rather than assume it;
  - (c) he prefers work that can be shown quickly, which explains why "demo-driven development" `[15:14]` suits him.

### S20. Omar Waseem EP33, 2023-09-29: Buildspace era
https://www.youtube.com/watch?v=oLif8JcsaZw

- MEASURED: 75 min, 13.8K views.
- On controlling the story instead of giving it to press:
  - QUOTED @56:26: "our main job is to like maintain the story like we are the writers of the book."
  - The host raises his past refusal of magazine and business articles because "you don't have control over that story" @55:55-56:10.
- On why make anything: "you get to push the work in front of an audience of people every week every day and um that's all it really is like the work gets better" @73:06-73:22.
- Verdict: **EXTENDS**.
  - It gives an early reason for founder-owned channels: control of the narrative, not only reach.
  - That matches the interview's dismissal of old media: "all of the old media is kind of just gone" `[03:08]`.
  - It matches the "character" framing `[24:33]`.

### S21. TBPN interview, 2026-06-10 (auto transcript)
https://www.tbpndigest.com/story/2026-06-10/hey-clicky-founder-farza-majeed-built-a-voice-controlled-ai-desktop-agent-in-8-weeks-now-using-claude-4-by-default/transcript

- The page says its transcript "is auto-generated and may contain errors" (DOCUMENTED).
- Asked whether his "media talent" competes with the startup, he answered:
  - QUOTED: "I am painfully familiar with how bad of a business like making videos is, and making movies is, and making music is."
  - QUOTED: "I know more than anybody the power of getting in front of a billion people every single month."
  - He adds the condition "When there's a good engine underneath, a good business engine".
- He tells the Clicky origin the same way: "I thought it was really a really bad idea… One of my friends just had to post it."
- Verdict: **EXTENDS**.
  - Video is a sales channel on top of a working business, not the business itself.
  - This agrees with "We're launching to get users" `[05:49]` and with S17.

### S22. Buildspace shutdown tweet and letter, 2024-08-23
https://x.com/FarzaTV/status/1827030900456169849 · https://buildspace.so/letter

- MEASURED (cc-read-twitter): 5.9K likes, 1.2K replies, 2.5M views.
- QUOTED (tweet): "It's not because of investor pressure, runway, internal drama, monetization, or any of those reasons."

What the letter says (MEASURED, curl of buildspace.so/letter, dated "aug 23, 2024"):
- There are "over 2+ years in the bank".
- Sponsorships could bring "$3-5m arr" to keep the lights on.
- The company "is the strongest it's ever been".
- The real reason, QUOTED: "at this point i'm out of ideas to try that i can really put my all behind to take us further."
- He started feeling this "in september 2023… shortly after s4 ended" and took a year to decide.
- In the last 12 months they had "launched a new ai product to 100,000 users, ran our biggest season ever, expanded our content to millions of hits".
- He also recalls "the laughs we had while making our videos".

Later reflection (S28, Substack 2025-12-18, https://farza.substack.com/p/ate-a-lactose-free-cake-for-my-bday):
- QUOTED: "Closing a company I loved (buildspace) due to my own personal flaws sucked."
- He notes it "was very public, millions saw it".

Verdict: track record (see §4).
- INFERRED relevance: he is open about failure in public, which fits the "show the process" stance `[05:02]`. It also means his advice comes from someone whose biggest company ended by his own choice, not through product-market failure.

### S23. farza.com, read 2026-10-24
https://farza.com

- Self-description, QUOTED: "i'm just a guy that loves creating things for others."
- His self-reported record (DOCUMENTED as self-claims):
  - an eBay business at 13 that grew to "$100K in revenue per year";
  - Buildspace, which "scaled nights & weekends online to over 100,000 students", raised from a16z and YC, built a physical SF campus, "grew content to millions", and built an AI social product (Sage);
  - zipschool, grown to "150,000 kiddos";
  - Visor, an Overwatch coaching model, which "got really big… then, blizzard banned us";
  - League of Legends tools with "1m+ users".
- QUOTED: "some stuff above worked out. most of it didn't."
- Verdict: track record. It **AGREES** with the interview's "hundreds and thousands of videos I've made that nobody has cared about" `[09:49]` framing of a long tail of misses.

### S24. Buildspace program material, 2023-2024
- https://buildspace.so/nw (the s5 URL redirects here; MEASURED by curl)
- https://buildspace.so/school
- https://buildspace.so/sf1
- https://www.ycombinator.com/companies/buildspace

Nights & Weekends structure (DOCUMENTED, /nw):
- QUOTED: "every week, we have 1 lecture, 1 talk and 1 weekly update."
- The six weeks are "week 1 idea · week 2 version one · week 3 feedback · week 4 iterate + feedback · week 5 users + growth · week 6 demo day + final 32".
- The goal is to "turn it into something that people give a shit about".
- QUOTED disclaimer: "this is not a bootcamp."

The SF school (DOCUMENTED, /school, signed by Farza):
- QUOTED: "every week you'll build, you'll launch, you'll learn, and you'll iterate."

The YC company page (DOCUMENTED, Buildspace's own text):
- "12M+ ppl saw our content across Instagram and Twitter" in 2023;
- "more than 30,000 people joined nights & weekends";
- QUOTED self-critique: "in 2023, we built up massive distribution… but, it was all very one-off."

Verdict:
- **AGREES**. The weekly build-launch-iterate cycle with a public weekly update and a demo day is the interview's "what are we launching this week" `[03:55]`, institutionalised years earlier.
- The "one-off" self-critique **AGREES** with "you want a channel… that we can keep on repeating" `[05:56]`.
- Not established: written demo-day *rules*, such as length or format. None appear on the pages I could reach.

### S25. Buildspace DMW lectures, 2024 (**not Farza's voice**)
- "video 101: how to make good videos.", 2024-02-29, https://www.youtube.com/watch?v=FxyD8fH3Vcs
- "good videos aren't just about hooks or impressions.", 2024-03-14, https://www.youtube.com/watch?v=0LF1VllQKLo

Who is speaking (MEASURED, auto-captions):
- The lecturer is a Buildspace staff filmmaker who calls Farza "my CEO farza" @28:28 (FxyD8fH3Vcs). He is not named in the captions.
- The DMW course was taught mainly by other staff: the class-0 speaker introduces himself as Buildspace's designer (https://www.youtube.com/watch?v=jPTIeD7DtKQ @00:15).

What the video lecture teaches:
- Make something "you would want to watch first", and "don't focus on chasing numbers right now" (0LF1VllQKLo @03:41, @04:28).
- QUOTED (0LF1VllQKLo @04:45): "good videos ain't just about good hooks, content, and a CTA."
- When the account was "dying", he says "I actually stole the [__] script from this video from another person" and mimicked its structure (FxyD8fH3Vcs @14:54-15:56).
- Music first: "we worked backwards… choosing the right music was just like help guide you" (@25:32). Farza is cited as someone who edits to the beat (@28:28).

Verdict: **AGREES** as house style, not as Farza's words.
- It matches studying Reels and using one as a template `[22:54]-[23:26]`.
- It matches "I'm the audience" `[10:54]`.
- It matches Farza bringing "the song" `[43:28]`, and the "beat system" `[38:44]`.

### S26. YC company page for HeyClicky (Launch YC text)
https://www.ycombinator.com/companies/clicky

- DOCUMENTED: Spring 2026 batch; primary partner Aaron Epstein.
- QUOTED (launch post): "We've gone super viral on Instagram and are getting insane pull."
- The launch post lists concrete user types: kids making games, founders researching competitors, doctors, and content creators learning After Effects and DaVinci.
- Verdict: **AGREES** with Instagram as the lead channel `[33:13]` and with leading with specific, surprising use cases `[07:38]-[07:40]`.

### S27. Neatprompts, 2026-09-12 (third-party analysis)
https://www.neatprompts.com/p/heyclicky-15m-views-arguing-against-itself

- DOCUMENTED claims:
  - Clicky content passed "15 million" views across Instagram, X and LinkedIn;
  - #6 Product of the Day on Product Hunt;
  - a non-technical user posted a Windows port within 18 hours.
- Its counter-reading: Tidbit "had exactly the same audience" and flopped. The article's view is that the difference was "whether a stranger could tell what the product did by watching someone use it".
- QUOTED (the article's own line): "Distribution only carries what people understand on mute."
- It also documents the repeated teaser formula (S5) and his self-critical metrics video.
- Verdict: **EXTENDS**, and it is a useful control on Farza's own story. INFERRED: the method document should include a mute test ("can a stranger tell what it does with the sound off?"). That test extends his "watch it muted and imagine I'm scrolling" check for Twitter `[33:50]-[34:01]`.

---

## 3. Interview claims compared with what he says elsewhere

| Interview claim | Elsewhere | Verdict |
|---|---|---|
| Launch constantly; call them demos `[02:31]`, `[03:48]` | S1 "game of consistency"; S13 "launching a lot of random stuff"; S24 weekly launch cadence since 2023 | AGREES, and stable over years |
| Work backwards from caption and hook before building `[04:08]-[04:32]` | S7 "drafted hella tweets" before building; S14 tweet written before the product existed, 280-char test | AGREES; elsewhere it is a **build-gate**, not just packaging |
| He thought the demo was bad, Aaron pushed, he posted fast `[06:16]-[06:45]` | S3 "sitting on the Clicky demo for a few weeks"; S19 "tabled it for another two weeks" | AGREES, with a **timing nuance**: weeks of hesitation came first |
| Views don't matter; downloads and retention do `[07:05]-[07:32]` | S15 "1 million views… doesn't mean [__]" plus a Stripe link for 25 customers; S9 0.5% TikTok conversion | AGREES + EXTENDS (paid-intent test) |
| Script every video; rehearse; three days ahead `[14:03]-[14:16]` | S10 script in 30 minutes, ~8 h total; S8 the content person wrote the TikTok scripts | TENSION on how long scripting takes and who writes |
| Show the process, not the polished ending `[05:02]`, `[25:46]` | S16 "videos about us and our process"; S12 "updating people on results" | AGREES |
| Instagram is the best channel; Twitter converts worst `[31:07]`, `[32:22]` | S6 "posted this 2-months ago on insta"; S26 "super viral on Instagram"; **S8 (2025) Reels felt wrong for Tidbit** | AGREES for Clicky; DISAGREES for the 2025 Tidbit period |
| Every channel is different `[31:47]` | S8 "shorts are the same across platform" is a view he dislikes | AGREES |
| Audience is the moat `[40:22]` | S17 "distribution is nothing without like a good product"; S21 needs "a good business engine underneath"; S24 "very one-off" | TENSION; resolved as product first, audience compounds |
| He is good at stories `[19:23]` | S12 "I am not naturally a guy that can tell great stories" | TENSION (2024 self-image versus 2026) |
| Zero-views mindset `[16:56]` | S19 "zero people care about this", a stance "gained over the last 10 years" | AGREES; and it is **learned** |
| Be cringe first; record 30 s on a phone `[27:30]-[28:23]` | S11 the 15 s Reel dare, "Why do you believe something must be good to post it?" | AGREES |
| Study and copy a format `[22:54]-[23:26]` | S25 Buildspace lecture "stole the script… mimic" | AGREES (house style) |
| A filmmaker as the first hire `[39:05]` | S10 shoot and edit by a teammate; S8/S9 "trusting Hasan… actor bots for him"; S16 Vikrant making process videos | AGREES; he has always had a video collaborator |

Not found anywhere outside the interview: the "did my eye stop" mock-tweet test `[08:42]-[09:08]`, the 10-20% setup ratio `[11:29]`, the audio-quality rule `[41:50]`, the specific gear list `[40:53]-[42:36]`, and the formal 30-day challenge `[45:58]`. These look specific to the interview (INFERRED from absence in the sources read, which is not proof).

---

## 4. Track record bearing on credibility

| Fact | Value | Label / source |
|---|---|---|
| @FarzaTV followers | 129,259 (joined 2011-07-01; 21,662 posts) | MEASURED `api.fxtwitter.com/FarzaTV`, 2026-10-24 |
| @heyclicky followers (X) | 15,584 (joined 2026-02-24) | MEASURED `api.fxtwitter.com/heyclicky` |
| @_buildspace followers (X) | 111,441 | MEASURED `api.fxtwitter.com/_buildspace` |
| farzatv YouTube subscribers | 13.6K | MEASURED `yt-dlp` channel_follower_count on 2RxDQwPmvtA |
| heyclicky YouTube subscribers | 1,210 (the interview screen showed 872) | MEASURED yt-dlp on km54y7Xd_7g; 872 per prior probe E1 |
| _heyclicky Instagram | 35.4K followers, 48 posts, link heyclicky.com/ig (on screen in the interview) | prior probe E1 (frame read); not re-measured |
| Clicky launch post | 3M views, 15.7K likes, 1.3K replies | MEASURED cc-read-twitter (S2) |
| Screen-aware dictation YouTube | 21,012 views, 489 likes (uploaded 2026-07-14) | MEASURED yt-dlp km54y7Xd_7g |
| Clicky GitHub | 7,772 stars, 1,552 forks | MEASURED api.github.com |
| S29: basketball shot-counter demo, 2025-05-30 https://x.com/FarzaTV/status/1928484483076087922 | 2.9M views, 11.6K likes | MEASURED cc-read-twitter |
| S30: Freewrite launch, 2025-04-11 https://x.com/FarzaTV/status/1910789505722036357 | 2.2M views, 10.6K likes; the video is credited to @wordisbonz | MEASURED cc-read-twitter |
| S31: AI cursor buddy, the Clicky precursor, 2025-10-10 https://x.com/FarzaTV/status/1976456495132025030 | 453.2K views, 3.5K likes, 26.7 s video | MEASURED cc-read-twitter |
| S32: Tidbit launch, 2025-06-26 https://x.com/FarzaTV/status/1938240417956565219 | 341.9K views, 2K likes; shut down ~3 months later | MEASURED; shutdown in Substack 2025-09-20 https://farza.substack.com/p/tony-hawk-and-me-ate-pizza-on-a-skateboard |
| HeyClicky landing page reveal, 2026-07-19 https://x.com/FarzaTV/status/2078645479899078911 | 344K views, 2.6K likes | MEASURED fxtwitter timeline |
| Buildspace shutdown post | 2.5M views, 5.9K likes | MEASURED (S22) |
| Buildspace $10M raise thread, 2022-11-11 https://x.com/FarzaTV/status/1591131253410918400 | 2.5K likes; it claims "profitable + have 125,000+ users" | MEASURED (likes); DOCUMENTED (claims) |
| S33: S4 recap video, 2023-10-30 https://x.com/FarzaTV/status/1719091708775059754 · S5 announcement, 2024-04-19 https://x.com/FarzaTV/status/1781405384420548786 · Sage launch, 2024-06-15 https://x.com/FarzaTV/status/1802077019402064342 | 203.4K / 265.9K / 336.2K views | MEASURED cc-read-twitter |
| Buildspace 2023 reach | "12M+ ppl saw our content"; 30,000+ joined N&W; 1,000 at IRL events | DOCUMENTED, YC company page (S24) |
| Buildspace shutdown reason | personal: "out of ideas", passion gone; not runway (2+ years of cash), investors, monetization ($3-5M ARR possible) or drama | DOCUMENTED, letter (S22) |
| Total raised across zipschool + Buildspace; HeyClicky raise | "$12 million" each | DOCUMENTED as his claim (S19 @61:34; S12 "I've raised $12M") |
| HeyClicky scale | "1000 paying customers" (2026-08-27 post https://x.com/FarzaTV/status/2093034526142525815); "2,200 customers", "almost… a million dollars ARR", "40 million views in the last… 30 days" (2026-10-20) | DOCUMENTED as his claims (S18); not independently verified |
| Third-party tally | Clicky content >15M views across platforms; #6 Product of the Day on Product Hunt | DOCUMENTED, Neatprompts (S27) |

INFERRED reading of the record:
- He has a large, long-built personal audience: 129K on X, a YouTube channel from 2010, and Buildspace's audience.
- Several of his demos reached 2-3M views on X. Others, such as Tidbit, reached 300-450K and the product still did not survive.
- His advice is therefore best read as what works for a founder with a big existing audience and a full-time filmmaker. Two points of his own support transferring it anyway: the 2020 Zip School posts with ~80 followers and 23 likes `[18:31]`, `[19:50]`, and his claim that a new account will reach 1,000 views within 30 days `[46:22]`.

---

## 5. Method implications (INFERRED; for the synthesis)

1. **Add a pre-build pitch gate.** Before building, write the post (tweet or caption) for the demo. If it does not excite you, or does not fit in about 280 characters, rethink the angle (S7, S14).
2. **Add a "show one person" gate** before posting (S7, S14). It replaces "is it good enough?" with "did one person smile?".
3. **Pick one grounding frame** before scripting: the single image the video exists to show (S7). It feeds the first-frame design `[09:12]`.
4. **Set a same-day post deadline** and cut scope to whatever angle demos today (S7).
5. **Use a mute test** next to the stop test: can a stranger tell what it does with the sound off (S27, `[33:50]`)?
6. **Measure intent, not views.** Use a tagged link per channel (`/ig` `[32:47]`). Where possible, add a paid-intent check with a threshold (S15). Expect meme content to grow reach, not signups (S9).
7. **Keep five formats:**
   - daily demo;
   - weekly or biweekly "everything we built" process video `[24:52]`, `[26:56]`;
   - teaser then livestream drop (S5);
   - quarterly polished launch `[15:57]`;
   - long-form YouTube story at about 8 h including thumbnails (S10).
8. **Plan for the hesitation.** Even he sat on Clicky for weeks (S3, S19). The detachment took him a decade, so the method document needs a forcing function: a partner, a deadline, or the 30-day challenge.

---

## Gaps

- **Lenny's Podcast**: I found no Farza episode. Searches for Lenny's, My First Million and Colin & Samir returned nothing with him. I cannot rule one out.
- **Instagram and TikTok**: not read (no reader tool; Instagram needs a login). The 35.4K _heyclicky follower count comes from prior probe E1, not this run. I found no follower count for Farza's personal Instagram.
- **X search**: the fxtwitter timeline endpoint returned only the latest 22 posts (pagination failed), and X itself cannot be searched read-only. Older X threads with launch advice may exist that I did not find. I did not find the X posts for screen-aware dictation (the interview says 2.9M views `[31:23]`), the "this week I'm somehow in YC" video (21M on Instagram `[21:11]`), or the GPT-realtime Spotify demo (3.8M `[36:50]`).
- **Buildspace demo-day rules**: none published on the reachable pages; only the six-week outline (S24).
- **Interview numbers I could not verify**: 7,000 Clicky downloads, ~100 users retained, 20% YouTube conversion, 70% Instagram traffic share, and 50 design-agency leads. No public source confirms them.
- **The TBPN transcript is auto-generated**, and the YouTube captions are auto-captions. Quotes from them may contain transcription errors. I did not re-transcribe them with whisper.
- **Not fetched**:
  - "The Path EP2" (https://www.youtube.com/watch?v=fOUJgXlS6Jk): yt-dlp reported "This video is unavailable".
  - Inventing the Future #31 (2023-01-30).
  - The Gemini XPRIZE live session "How to Take Software to Market in 2026" (Luma, 2026-07-07): only its description was found, no recording.
  - The Urdu AI video (CyfNCxEx91E): captions hit HTTP 429.
- **DMW lecturers are not named**: the S25 lecturers are identified only by their role in the captions, so S25 is house style, not Farza's words.
