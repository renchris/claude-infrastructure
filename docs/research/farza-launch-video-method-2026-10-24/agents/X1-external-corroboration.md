# X1: External corroboration and counter-evidence for Farza's launch-video method

Slot: X1-external-corroboration. Written 2026-10-24.
Subject: the YC interview of Farza Majeed by Aaron Epstein ([tweet](https://x.com/ycombinator/status/2113654566776709147), [YouTube v12aSIZIXUs](https://youtu.be/v12aSIZIXUs)). Interview timestamps `[mm:ss]` refer to `/tmp/farza-2026-10-24/transcript.txt` (whisper, absolute times).

Labels used: **MEASURED** means I ran or read it in this run, with the command named. **QUOTED** means his words, with `[mm:ss]`. **DOCUMENTED** means a source states it, with URL and date. **INFERRED** means my own reasoning. If a claim rests only on his own anecdote, I say so.

---

## 0. Measured context (this run)

These facts bear on every verdict below, because they show how much distribution he already had.

| Fact | Value | How measured |
|---|---|---|
| @FarzaTV X followers | **129,258** (following 1,909; joined 2011-07-01) | MEASURED, `curl https://api.fxtwitter.com/FarzaTV`, 2026-10-24 |
| Original Clicky launch post | 2026-04-07 00:38 UTC, **3,000,759 views**, 15,734 likes, 1,171 reposts, 12,647 bookmarks; video **99.84 s**, 1660x1080 | MEASURED, `~/.claude/bin/cc-read-twitter https://x.com/FarzaTV/status/2041314633978659092` plus fxtwitter status API |
| Post saying he will keep working on Clicky | 2026-04-12, 58.9K views. It says "I had been sitting on the Clicky demo for a few weeks" | MEASURED, `cc-read-twitter https://x.com/FarzaTV/status/2043402737828962489` |
| Clicky open-source repo | **7,772 stars, 1,552 forks**, created 2026-04-07 | MEASURED, `gh api repos/farzaa/clicky` |
| Downloads per view, original launch | 7,000 / 3,000,759 = **0.23%** | MEASURED arithmetic on his figure ("I think 7,000 people downloaded it", QUOTED [07:18]) and the measured view count |
| heyclicky YouTube "introducing screen-aware dictation." | **21,000 views**, 121 s. The prior probe E1 saw "19K views 2mo ago" and 872 subscribers on screen | MEASURED, `yt-dlp --flat-playlist @heyclicky/videos`; prior probe E1, Q11 |
| heyclicky YouTube long-form views | 11 videos, from 419 to 21,000 views (agent buddies 6,100; logo 12,000) | MEASURED, same command |
| Buildspace (his previous company) on YC | `ycdc_status: "Inactive"`. Its own profile says "in 2023, we built up massive distribution… but, it was all very one-off" and "12M+ ppl saw our content" | MEASURED, `curl https://www.ycombinator.com/companies/buildspace` |

INFERRED: the Clicky launch went out to a 129K-follower account run by someone with "10 plus years" of posting (QUOTED [06:33]). His own baseline from that period is what a founder with no audience should expect: in 2020, with "maybe 80 followers", his posts got 23 likes (QUOTED [19:55], [18:31]). The method is sound, but the reach he shows off comes from someone who had already built distribution.

---

## 1. His main claims (from the transcript)

1. **Launch constantly.** You are "constantly launching all the time on these algorithmic platforms" (QUOTED [02:31]), and "generally we're launching like demos every single day almost" (QUOTED [16:06]). The team asks what it is launching this week and works backwards from that (QUOTED [03:55]).
2. **Low production beats expensive production.** A "say hi" video "is probably going to perform way better than like a $20,000 produced video" (QUOTED [03:11]).
3. **Show the process, not the result.** For example, the "everything we built this week" videos (QUOTED [24:52]–[25:22]), made "every two weeks" (QUOTED [26:51]).
4. **The hook and the first frame decide everything.** He mocks the post up in a real feed and asks "did I myself stop" (QUOTED [08:51]). "Most people, when they're scrolling, see the first three seconds" (QUOTED [09:32]). Setup should be "like 10, 20%" of a one-minute video (QUOTED [11:29]).
5. **Script every video.** "This whole video scripted" (QUOTED [14:00]), then rehearsed "over and over" (QUOTED [14:05]). He contradicts this for beginners: "if you've never made a video, don't worry about this" (QUOTED [45:20]).
6. **Demo-driven development.** Epstein frames it as working backwards from the demo (QUOTED [15:14]). The "check this out" moment is the thing to post (QUOTED [15:43]).
7. **Take a thousand shots.** "If you don't take a thousand shots you're not gonna make the… five thousandth shot" (QUOTED [20:25]).
8. **Views are not the metric.** "I do not care about the traffic at all" (QUOTED [07:05]). What matters is downloads, then day-4/5 retention: about 100 of 7,000 (QUOTED [07:18]–[07:30]).
9. **Platforms convert differently.** X is "the worst conversion of any channel" (QUOTED [31:07]). YouTube converts at "like 20" percent (QUOTED [31:37]). "70 of our traffic is instagram" (QUOTED [32:22]). He tracks this with a per-channel link-in-bio, "slash ig" (QUOTED [32:47]).
10. **B2B buyers are on consumer feeds.** Targeted TikToks found "like 50 design agency leads" at about 4,000 views each (QUOTED [30:38]–[30:48]).
11. **Audio matters more than picture.** "If your audio is bad i'm bouncing" (QUOTED [41:55]).
12. **The first hire should be a filmmaker.** "Number one a filmmaker and number two an engineer" (QUOTED [39:10]).
13. **Turn a demo into a story with beats, not a cut every few seconds.** "Everyone wants a story" (QUOTED [24:04]). "There's not a single cut in this video" (QUOTED [37:02]).
14. **The 30-day challenge.** Post one 10-minute phone video a day, and "one of those videos will surpass probably 1,000 views" (QUOTED [46:23]).

He also makes caveats that matter for the method:
- His scrappy videos are semi-produced. A produced video takes him "like an hour" (QUOTED [20:55]), and the YC-era video took "four to six hours" (QUOTED [22:14]).
- Every Clicky video "apart from the bad Zip School ones" was made by Vikrant, the filmmaker (QUOTED [42:52]).
- He still does "a polished launch" about "once a quarter" (QUOTED [15:57]).

---

## 2. Verdicts

| # | Claim | Verdict | Evidence beyond his anecdote |
|---|---|---|---|
| 1 | Launch constantly | **CORROBORATED**, with a channel caveat | YC (2019 talk, 2017 blog), PG (2009), Buffer frequency data (2025). Two channels are explicitly one-shot or rate-limited: Launch HN and Product Hunt |
| 2 | Cheap beats expensive | **PARTLY** | Wistia 2018: story beat spend. Johnson et al. 2021: polish raises perceived expertise but not trust |
| 3 | Show the process | **PARTLY** | Glossier/Stripe cadence (YC 2019). Copying risk is documented (Zue 2022), and Clicky has 1,552 forks (measured) |
| 4 | Hook, first seconds | **CORROBORATED** in direction; the specific numbers are ad-industry and correlational | TikTok 2020, Facebook/Nielsen 2016, YouTube Intro metric, MrBeast handbook |
| 5 | Script everything | **PARTLY / UNTESTED** | No direct study. Rifkin & Du 2023: perceived spontaneity earns trust, so the script has to stay invisible |
| 6 | Demo-driven development | **PARTLY**, as a planning discipline | Amazon Working Backwards (Vogels 2006). No outcome data |
| 7 | A thousand shots | **CORROBORATED** as a hit-rate effect, **CONTESTED** as a skill effect | Buffer 2025 heavy tail; Simonton's equal-odds rule |
| 8 | Measure downloads and retention, not views | **CORROBORATED** | PG "pretext for engaging users"; YC "launch to learn" |
| 9 | X worst, YouTube ~20%, Instagram 70% | **UNTESTED** (his data only). X: **PARTLY** (link suppression documented, then reversed). YouTube 20%: **CONTESTED** (implausible as views to downloads) | Musk 2023/2024 and 2026; Wistia 2018 (YouTube best cost per install); Forrester 2026 |
| 10 | B2B buyers are on consumer feeds | **PARTLY** | Forrester 2026: Facebook > Instagram/YouTube > LinkedIn. 6sense 2024 and the 95:5 rule say visibility before the buying cycle matters, but leads are not deals |
| 11 | Audio first | **CORROBORATED** | Newman & Schwarz 2018. Caveat: much feed viewing is muted (Digiday 2016) |
| 12 | Filmmaker as first hire | **UNTESTED / CONTESTED** | a16z New Media shows investors believe it. Buildspace had a 2-of-7 film team and is "Inactive" |
| 13 | Story and beats, not cuts | **PARTLY** | TikTok 2020 "users still value a great story"; Wistia 2018 storytelling. The "attention span" premise is a myth (BBC 2017) |
| 14 | 30-day challenge, 1,000 views | **UNTESTED**; plausible by inference | Buffer median ~500 views, p90 ~7K for 2–5 posts a week, but measured on established business accounts |

### 2.1 Launch constantly: CORROBORATED, with a channel caveat

**For:**
- DOCUMENTED: YC partner Kat Mañalac, "How to Launch (Again and Again)", YC, uploaded 2019-08-15 ([YouTube 3xU050kMbHM](https://www.youtube.com/watch?v=3xU050kMbHM)). MEASURED by downloading the auto-captions with yt-dlp and reading them.
  - She frames launching as something you keep doing: "I want to destroy the idea that launching is just this one moment in time" ([00:00:54] in her talk).
  - She warns that a team spending six months on one launch is likely to be "dead before you get another chance to launch" ([00:00:39]).
  - She cites Glossier relaunching through "every single launch button" about "every six to eight weeks" ([00:16:36]–[00:16:54]).
  - She cites Stripe repeating HN, blog, social and press launches for each product ([00:15:48]).
  - She also says launching on different channels shows "whether you're even talking to the right users" ([00:02:05]). That matches his per-channel tracking.
- DOCUMENTED: YC, "YC's Essential Startup Advice", Geoff Ralston, 2017 ([ycombinator.com](https://www.ycombinator.com/blog/ycs-essential-startup-advice/)): "The first thing we always tell founders is to launch their product right away". MEASURED, curl.
- DOCUMENTED: Paul Graham, "Startups in 13 Sentences", February 2009 ([paulgraham.com](http://paulgraham.com/13sentences.html)): "the main value of whatever you launch with is as a pretext for engaging users." MEASURED, curl.
- DOCUMENTED: Buffer, "How Often Should You Post on TikTok", published 2025-10-08 ([buffer.com](https://buffer.com/resources/how-often-should-you-post-on-tiktok/)). MEASURED, curl and grep.
  - Sample: 11.4M posts from more than 150K accounts, analysed with fixed-effects regressions.
  - Going from 1 post a week to 2–5 gives up to 17% more views per post; 6–10 gives 29%; 11+ gives 34%.
- DOCUMENTED: Buffer's Instagram study ([buffer.com](https://buffer.com/resources/how-often-to-post-on-instagram/)) reports 2M+ posts and faster follower growth at 3–5 posts a week. This is a secondary summary; I did not open the page.

**Against or limits:**
- DOCUMENTED: Some launch channels are explicitly one-shot.
  - Hacker News: "Each YC startup only gets one Launch HN, so it's important to play that card at the right time" ([news.ycombinator.com/yli.html](https://news.ycombinator.com/yli.html), undated, current). The same page says "Don't write in a marketing, sales, or PR style."
  - Product Hunt: the norm is about 6 months between launches unless there is a "significant" update ([PH forum](https://www.producthunt.com/p/producthunt/how-often-should-you-launch-on-product-hunt); search summary, not opened).
- DOCUMENTED: In Sprout Social surveys, over-posting and promotional posts are a top reason people unfollow brands: 2016, n=1,022; 2019, 35% "too many promotional posts", n=1,011 ([MarketingProfs 2019](https://www.marketingprofs.com/charts/2019/41243/why-people-follow-and-unfollow-brands-on-social-media); secondary).
- INFERRED: Frequency helps a demo that shows something new. It hurts when the post is just a promotion.

**What to do:** Split the work into two tracks.
- **Demo track.** Post weekly or more on algorithmic feeds. Each post shows one real new thing.
- **Milestone track.** Spend Launch HN, Product Hunt and press only on substantive releases, a few times a year at most.

Farza runs the same split himself, "once a quarter we'll do a polished launch" (QUOTED [15:57]).

### 2.2 A selfie video beats a $20K produced video: PARTLY

**For:**
- DOCUMENTED: Wistia's "One, Ten, One Hundred" test, by Nottingham & Gagne, 2018-11-15 ([wistia.com](https://wistia.com/blog/does-budget-matter-in-video-advertising)). MEASURED via WebFetch.
  - Three ads for the same product cost $1K, $10K and $100K; $60K of media was spent over 3 weeks.
  - The **$10K** ad won, at $6.66 cost per install on YouTube, about half the others. The $1K and $100K ads were both above $10.
  - Wistia's conclusion: "good storytelling matters far more than production quality."
  - INFERRED: so more budget did not help, but the cheapest ad did not win either.
- DOCUMENTED: Johnson, Bradshaw et al., "Credible Influencers: Sponsored YouTube Personalities and Effects of Warranting Cues", *Journal of Media Psychology*, 2021, a registered report ([UF summary](https://jou.ufl.edu/?p=448942)). Higher production quality raised **perceived expertise** but did **not** change **trust**.

**Against or limits:**
- QUOTED: His own "scrappy" output is made by a full-time filmmaker ([42:52]) and takes 1 to 6 hours ([20:55], [22:14]). The $20K comparison is his anecdote; he gives no A/B test.
- DOCUMENTED: Mañalac (2019) says YC "looked at the stats" of TechCrunch vs Product Hunt vs HN launches, and that they are "starting to even out in terms of their impact and conversion" ([00:08:55]–[00:09:07], [YouTube 3xU050kMbHM](https://www.youtube.com/watch?v=3xU050kMbHM)). YC's data is not public.
- INFERRED: "Old media is gone" (QUOTED [03:08]) goes beyond the evidence; YC's 2019 view was that the channels were converging, not that press had stopped working.

**What to do:**
- Default to phone or screen-recorder quality, and spend the effort on the story and the audio.
- Keep a higher-production piece for the quarterly milestone (the separate "cinematic launch film" process).
- Expect polish to signal competence, not trust.

### 2.3 Show the process, not the polished result: PARTLY

**For:**
- DOCUMENTED: Mañalac 2019 on Glossier's "constant drumbeat" ([00:16:50]).
- QUOTED: His weekly "what we shipped" videos have "almost a million views on instagram" ([25:22]). This is his anecdote.

**Against:**
- DOCUMENTED: Cory Zue, "Farewell, Building in Public", 2022-12-08 ([coryzue.com](https://coryzue.com/writing/building-in-private)). He says both his main products were copied, some down to the interface, pricing and landing page.
- MEASURED: The open-source Clicky has 1,552 forks (`gh api`). Searches surfaced third-party ports and relaunches, for example [github.com/Bitshank-2338/clicky-windows](https://github.com/Bitshank-2338/clicky-windows) and [hunted.space "clicky 2"](https://www.hunted.space/product/clicky-2).
- QUOTED: He takes this on board: "someone can clone my product in like two minutes", and "what's really hard to clone is the audience" ([40:17]–[40:27]). He moved new work to closed source (MEASURED, [Clicky README](https://github.com/farzaa/clicky) dated 2026-04-27).

**What to do:**
- Show the work and the "check this out" moments.
- Do not post metrics, pricing logic or architecture that a clone could use.
- INFERRED: The bet is that audience is the moat. That holds only if the audience turns into retained users (see §2.8).

### 2.4 The hook, the first frame, the first 3–10 seconds: CORROBORATED in direction

**For:**
- DOCUMENTED: TikTok for Business, "9 creative tips…", 2020-10-21 ([ads.tiktok.com](https://ads.tiktok.com/business/en-US/blog/9-creative-tips-to-drive-auction-ad-performance)). MEASURED via WebFetch.
  - "over 63% of all videos with the highest click-through rate (CTR) highlight their key message or product within the first 3 seconds."
  - Vertical TikToks have "an average 25% higher 6-second watch-through rate."
- DOCUMENTED: Facebook and Nielsen, reported by TechCrunch 2016-02-18 ([techcrunch.com](https://techcrunch.com/2016/02/18/facebook-video-metrics)) and in secondary coverage ([Martech](https://martech.org/facebook-releases-new-video-ad-features-including-automated-captions)). 47% of a video campaign's value was delivered in the first 3 seconds and 74% in the first 10 seconds. I did not open the primary study, and the data is about ten years old.
- DOCUMENTED: YouTube Help, "Measure key moments for audience retention" ([support.google.com](https://support.google.com/youtube/answer/9314415?hl=en)). MEASURED via WebFetch.
  - "Intro tells you what percentage of your audience still watched your video after the first 30 seconds."
  - YouTube's advice for a weak intro: change the title and thumbnail, or rework the first 30 seconds.
- DOCUMENTED: The MrBeast Productions onboarding handbook, leaked 2024, authenticity disputed ([Alexander Jarvis copy](https://www.alexanderjarvis.com/memo-how-to-succeed-in-mrbeast-production/); [Gigazine](https://gigazine.net/gsc_news/en/20240917-mrbeast-youtube-production)). It treats the first minute as the point where viewers are most likely to leave, and advises "frontloading".
- DOCUMENTED: X's business video page, undated ([business.x.com](https://business.x.com/en/resources/video)), recommends 6–15 s and captions (search summary).

**Limits:**
- INFERRED: The TikTok and Facebook figures are correlational and about ads.
- INFERRED: YouTube measures the intro at 30 s, not 3 s, so the window depends on the platform: about 3 s on a feed, about 30 s on YouTube.
- DOCUMENTED: The "8-second attention span" figure is a myth. It traces to a 2015 Microsoft Canada report citing "Statistic Brain"; the BBC's *More or Less* (2017) found no source for it ([summary](https://scienceblog.com/t-humans-eight-second-attention-span-goldfish-myth/)).
- Farza's framing avoids that trap: "I'm not trying to keep your attention… I'm always like, all right where is this going" (QUOTED [37:36]).

**What to do:**
- Put "who I am, what this is, why it matters" in the first 10 seconds (his formula, QUOTED [21:51]).
- Make the first frame readable with the sound off.
- Check the hook in a real feed mock-up.
- Use YouTube's Intro and Dips reports to see where viewers drop.

### 2.5 Script every video: PARTLY / UNTESTED

- I found no study comparing scripted and unscripted founder videos on conversion.
- DOCUMENTED: Rifkin & Du, *Journal of Consumer Research*, 2023 (doi 10.1093/jcr/ucac060; [The Conversation, 2023-06-02](https://theconversation.com/the-allure-of-the-ad-lib-new-research-identifies-why-people-prefer-spontaneity-in-entertainment-203487)). People rate performers as more authentic when they act spontaneously, but expect spontaneous work to be lower quality.
- INFERRED: This is consistent with his method: script for quality, then deliver so it reads as spontaneous ("by the time I'm in front of the camera, I've already visualized it like 10 times", QUOTED [14:16]).
- INFERRED: There is a risk. If the audience sees the script, the authenticity premium is lost.
- The evidence for the claim is his anecdote, and he softens it himself: write "for just 10 minutes" once you are on your "15th, 20th, 30th video" (QUOTED [45:22]–[45:28]).

**What to do:**
- Beginners: record unscripted for the first few videos.
- After that: spend 10 minutes writing the hook and beats before recording, and rehearse the opening line out loud. Do not read from a teleprompter.

### 2.6 Demo-driven development: PARTLY (a known discipline; no outcome data)

- DOCUMENTED: Amazon's "Working Backwards", described by Werner Vogels on 2006-11-01 ([allthingsdistributed.com](https://www.allthingsdistributed.com/2006/11/working_backwards.html)): "we start by writing the documents we'll need at launch (the press release and the faq)".
- INFERRED: Writing the caption and hook before building (QUOTED [04:08]–[04:15]) is a lightweight version of this. It forces a clear statement of value early.
- No external evidence links it to better products. Its benefit is the clarity it forces, which is a reasoned argument, not a measured result.

**What to do:** For each feature, write the hook and the one-line caption at kickoff. If neither is interesting, rethink the feature or how you describe it.

### 2.7 Take a thousand shots: CORROBORATED for hit rate, not shown for skill

**For:**
- DOCUMENTED: The same Buffer TikTok study (2025-10-08). MEASURED, curl and grep.

| Posts per week | Median views | 90th-percentile views | p90 / median |
|---|---|---|---|
| 1 | 489 | 3,722 | 7.6x |
| 2–5 | 506 | 6,983 | — |
| 6–10 | 487 | 10,092 | — |
| 11+ | 459 | 14,401 | 31.4x |

  - Buffer's data scientist Julian Winternheimer: "Posting more helps — but mostly because it increases your chances of getting lucky."
- DOCUMENTED: Simonton's equal-odds rule (Simonton, *Psychological Review* 104:66–89, 1997; [summary](https://www.jimdavies.org/summaries/simonton1997.html)). The number of hits rises linearly with total output, and the hit rate per work stays roughly constant. Later studies find some exceptions.

**Against or nuance:**
- INFERRED: The Buffer data shows **flat medians**. Volume buys more chances at a hit; it does not show that the average post gets better. His claim that you "slowly get better" (QUOTED [20:20]) is plausible, but this data does not test it.
- QUOTED: His own Zip School videos never went viral ([19:13]).
- Survivorship: the interview shows his hits. He admits "we're looking at the stuff that's working but so much hasn't worked" ([35:23]).

**What to do:**
- Commit to a cadence of at least 2–5 posts a week.
- Log every post with its hook and its numbers.
- Judge by the tail (best post per month), not the median.
- Do a deliberate review each week, because volume alone may not build skill.

### 2.8 Views are vanity; measure downloads and retention: CORROBORATED

- DOCUMENTED: PG 2009 ("pretext for engaging users"); YC 2017 ("the only way to fully understand customers' problems").
- MEASURED: The Clicky launch converted at 0.23% from views to downloads (7,000 / 3,000,759). About 100 of those were still using it on day 5 (QUOTED [07:30]), roughly 1.4% of downloaders, and he says those 100 users, not the views, are why he kept going (QUOTED [07:24]).
- DOCUMENTED: Buildspace's YC profile shows the counter-lesson. "12M+ ppl saw our content" and "we built up massive distribution… but, it was all very one-off", yet the company is listed as "Inactive" ([ycombinator.com/companies/buildspace](https://www.ycombinator.com/companies/buildspace); MEASURED, curl).
- INFERRED: Distribution did not save the business, so the retention metric is what matters.

**What to do:** For every post, record views → link clicks → signups/downloads → day-1/7 retention. Talk to the retained users.

### 2.9 Platform conversion (X worst, YouTube ~20%, Instagram 70% of traffic): UNTESTED; X partly explained; the YouTube number is doubtful

**On X:**
- DOCUMENTED: Musk said in 2023 that the algorithm optimises time on platform, so links get less attention ([Mediaite](https://www.mediaite.com/news/elon-musk-admits-x-is-throttling-links-effectively-limiting-people-from-reading-news); secondary).
- DOCUMENTED: On 2026-07-29, Musk replied to Paul Graham about link penalties: "We haven't for over a year" ([PPC Land, 2026-07-30](https://ppc.land/x-drops-year-old-link-penalty-musk-tells-zuckerberg-on-platform/); MEASURED via WebFetch). PPC Land's analysis of the open-sourced code found link posts got 94% fewer views, through model behaviour rather than an explicit rule.
- INFERRED: His "10 years" of poor X conversion (QUOTED [31:07]) is consistent with documented link suppression and with in-feed scrolling. The situation may have changed since about mid-2025, so re-measure rather than assume.

**On YouTube's "like 20" percent** (QUOTED [31:37]):
- MEASURED: That video has 21,000 views. 20% of views would be about 4,200 downloads from one video with 872 subscribers.
- INFERRED: That is about 90 times the measured X ratio. It is more likely a different denominator, such as link clicks or tracked visits. Treat it as unverified.
- DOCUMENTED, partial support: Wistia 2018 found YouTube (TrueView for Action) the most efficient channel for installs, and Facebook better for reach ([wistia.com](https://wistia.com/blog/does-budget-matter-in-video-advertising)).

**On Instagram's 70%:**
- His anecdote only.
- DOCUMENTED: Instagram ranks on watch time, likes and sends. Sends matter more for reaching non-followers (Adam Mosseri via [Social Media Today, 2025-01-22](https://www.socialmediatoday.com/news/instagram-shares-algorithm-insights-2025/738034/)). This favours content people share with friends.

**What to do:**
- Treat his platform ranking as a hypothesis, not a fact.
- Give each platform its own short link (his "/ig" approach, QUOTED [32:47]), and compare signups and retention per platform after 4–6 weeks.
- Expect the result to depend on your product: he sells a consumer Mac app.

### 2.10 B2B buyers are on consumer feeds: PARTLY

**For:**
- DOCUMENTED: Forrester, "Social Media Takes Center Stage In B2B Buying — Even In The AI Era", Karen Tran, 2026-01-27 ([forrester.com](https://www.forrester.com/blogs/social-media-takes-center-stage-in-b2b-buying-even-in-the-ai-era/)). MEASURED via WebFetch. Based on more than 17,000 business buyers:
  - "Facebook leads the pack" as a meaningful platform, followed by Instagram and YouTube, then LinkedIn.
  - Millennials and Gen Z are 63% of buyers.
- DOCUMENTED: 6sense 2024 Buyer Experience Report ([BusinessWire, 2024-10-09](https://www.businesswire.com/news/home/20241009142556/en/6sense-Launches-2024-Buyer-Experience-Report-Unveiling-Global-B2B-Buyer-Trends); secondary). Buyers are about 70% through the journey before they contact a seller, and 81% already have a preferred vendor at first contact. 6sense sells ABM software, so it has an interest.
- DOCUMENTED: The 95:5 rule (Dawes, Ehrenberg-Bass, published by LinkedIn's B2B Institute in 2021; [Marketing Week](https://www.marketingweek.com/peter-weinberg-jon-lombardo-95-5-rule)). At any time, most business buyers are not in market, so a steady presence builds memory for later.
- INFERRED: Together these support constant visibility. A buyer has to have seen you before they start the buying cycle.

**Against:**
- DOCUMENTED: 6sense reports buying groups of about 11 people and cycles of about 11.3 months.
- INFERRED: A 4,000-view TikTok makes a lead, not a deal. His "50 design agency leads" (QUOTED [30:43]) come with no figure for leads becoming revenue.

**What to do:**
- For B2B, post call-out videos aimed at a niche ("are you a design agency?").
- Measure leads and pipeline, not views.
- Keep the conventional channels (LinkedIn, communities). He endorses these too: "those are all actually really good you should do those things" (QUOTED [30:14]).

### 2.11 Audio quality matters most: CORROBORATED

- DOCUMENTED: Newman & Schwarz, "Good Sound, Good Research", *Science Communication* 40(2):246–257, 2018, doi 10.1177/1075547018759345 ([ANU repository](https://openresearch-repository.anu.edu.au/items/67350c38-062b-4837-84c9-81419829d59d)). The same content with worse audio led viewers to rate the research and the researcher less favourably.
- DOCUMENTED, limit: Much feed video plays muted. Publishers reported up to 85% silent Facebook views ([Digiday 2016](https://digiday.com/media/silent-world-facebook-video/)); these figures are self-reported.
- QUOTED: His own X test is to "watch it muted" ([33:54]).

**What to do:** Use any external lav or wireless mic (not a laptop or AirPods mic) and burn in captions. The first seconds must work both muted and with sound.

### 2.12 First hire a filmmaker: UNTESTED / CONTESTED

- The evidence is his anecdote.
- DOCUMENTED, for: a16z's New Media pitch, "To win, you must go direct, and to go direct, you must be interesting" ([a16z.com/new-media](https://a16z.com/new-media/), undated, 2026 page). This shows investors believe in in-house creative. It is not outcome evidence.
- DOCUMENTED / QUOTED, against: At Buildspace, "our film team was two people we were only like a seven person team" (QUOTED [39:55]). That company is now YC "Inactive" (MEASURED).
- INFERRED: A strong in-house film function did not by itself produce a durable business.
- He also concedes "a lot of people watching probably can't afford to hire a filmmaker" (QUOTED [44:05]).

**What to do:**
- Pre-PMF: the founder shoots on a phone or screen recorder.
- Hire creative (contract first) once one channel shows tracked conversion and the cadence is limited by production time, not ideas.

### 2.13 Story and beats instead of fast cuts: PARTLY

- DOCUMENTED: TikTok 2020: "TikTok users still value a great story over anything else" ([ads.tiktok.com](https://ads.tiktok.com/business/en-US/blog/9-creative-tips-to-drive-auction-ad-performance)).
- DOCUMENTED: Wistia 2018: storytelling mattered more than production.
- DOCUMENTED: The MrBeast handbook puts "re-engagement" beats at intervals. That is a beat structure, not a cut rate.
- His single-take Clicky voice-control video (QUOTED [37:02]) is one data point.

**What to do:** Plan 3–5 beats (hook, reveal, escalation, payoff). Each beat should raise a question that the next one answers.

### 2.14 The 30-day challenge: UNTESTED

- INFERRED: Buffer's 2–5-posts-a-week cohort has p90 ≈ 6,983 views, so one post in 30 passing 1,000 views is plausible.
- But Buffer's sample is established business accounts connected to Buffer. A brand-new anonymous account, as he suggests ("make a new instagram account", QUOTED [46:13]), may start lower.
- "I promise you" (QUOTED [46:20]) is a promise, not data.

**What to do:** Run it as a measured experiment: 30 posts, a log, and the hook from the top three reused in the next ten.

---

## 3. Cross-cutting counter-evidence

1. **Survivorship.** The interview shows hits: 3M, 2.9M, 3.8M/4.6M and 21M views (QUOTED [07:00], [31:23], [36:50], [21:11]). The "thousands of videos… that nobody has cared about" (QUOTED [09:50]) are not shown. Buffer's flat medians are the base rate.
2. **Pre-built distribution.** He has 129K X followers (MEASURED) and a decade of audience from Buildspace. INFERRED: his "say hi and post" works partly because of that audience.
3. **Distribution is not the business.** Buildspace had "massive distribution" and is "Inactive" (MEASURED). Clicky converted 0.23% of viewers to downloads (MEASURED).
4. **Consumer vs B2B.** His conversion numbers are for a free consumer Mac download. B2B cycles of about 11 months with groups of about 11 people (6sense 2024) mean the per-post metric should be leads or pipeline.
5. **One-shot channels exist.** One Launch HN per YC company; about 6 months between Product Hunt launches.
6. **Audience fatigue.** Over-promotion is a top reason people unfollow brands (Sprout Social 2016/2019).
7. **The Product Hunt base rate.** "of the thousands of startup founders who try their hand at Product Hunt each week, very few see any impact" (Leo Bosuener in [Lenny's Newsletter, 2024-03-05](https://www.lennysnewsletter.com/p/how-to-successfully-launch-on-product)). On HN, average star gains after exposure are skewed by a few viral launches ([arXiv 2511.04453](https://arxiv.org/abs/2511.04453v1), single-author preprint, n=138; search summary). Every launch channel is heavy-tailed.

---

## 4. Founder case study with numbers (besides Clicky)

DOCUMENTED: Dropbox's 2008 demo video is said to have grown the beta waitlist from about 5,000 to 75,000 overnight ([Wikipedia, Timeline of Dropbox](https://en.wikipedia.org/wiki/Timeline_of_Dropbox)). That source is secondary, and Houston's interviews confirm the earlier 2007 HN video, not these figures. It is the classic case of a founder-made screencast driving signups, and it was posted to Digg, the algorithmic feed of its day.

---

## Sources (by date)

- 2006-11-01 Vogels, Working Backwards: https://www.allthingsdistributed.com/2006/11/working_backwards.html
- 2009-02 Paul Graham, Startups in 13 Sentences: http://paulgraham.com/13sentences.html
- 2016-02-18 TechCrunch on Facebook/Nielsen 3 s/10 s value: https://techcrunch.com/2016/02/18/facebook-video-metrics
- 2016-05 Digiday, 85% silent views: https://digiday.com/media/silent-world-facebook-video/
- 2017 YC Essential Startup Advice: https://www.ycombinator.com/blog/ycs-essential-startup-advice/
- 2018 Newman & Schwarz, Science Communication: https://openresearch-repository.anu.edu.au/items/67350c38-062b-4837-84c9-81419829d59d
- 2018-11-15 Wistia, One/Ten/One Hundred: https://wistia.com/blog/does-budget-matter-in-video-advertising
- 2019-08-15 Kat Mañalac, How to Launch (Again and Again): https://www.youtube.com/watch?v=3xU050kMbHM
- 2019 Sprout Social unfollow reasons (via MarketingProfs): https://www.marketingprofs.com/charts/2019/41243/why-people-follow-and-unfollow-brands-on-social-media
- 2020-10-21 TikTok creative tips: https://ads.tiktok.com/business/en-US/blog/9-creative-tips-to-drive-auction-ad-performance
- 2021 Johnson et al., J. Media Psychology (UF summary): https://jou.ufl.edu/?p=448942
- 2021 95:5 rule (Marketing Week): https://www.marketingweek.com/peter-weinberg-jon-lombardo-95-5-rule
- 2022-12-08 Cory Zue, Farewell Building in Public: https://coryzue.com/writing/building-in-private
- 2023-06-02 Rifkin & Du (The Conversation): https://theconversation.com/the-allure-of-the-ad-lib-new-research-identifies-why-people-prefer-spontaneity-in-entertainment-203487
- 2024-03-05 Lenny's Newsletter, Product Hunt: https://www.lennysnewsletter.com/p/how-to-successfully-launch-on-product
- 2024-10-09 6sense Buyer Experience Report: https://www.businesswire.com/news/home/20241009142556/en/6sense-Launches-2024-Buyer-Experience-Report-Unveiling-Global-B2B-Buyer-Trends
- 2025-01-22 Mosseri ranking signals (Social Media Today): https://www.socialmediatoday.com/news/instagram-shares-algorithm-insights-2025/738034/
- 2025-10-08 Buffer TikTok frequency study: https://buffer.com/resources/how-often-should-you-post-on-tiktok/
- 2026-01-27 Forrester B2B social: https://www.forrester.com/blogs/social-media-takes-center-stage-in-b2b-buying-even-in-the-ai-era/
- 2026-07-30 PPC Land, X link penalty: https://ppc.land/x-drops-year-old-link-penalty-musk-tells-zuckerberg-on-platform/
- Undated: YouTube Help key moments https://support.google.com/youtube/answer/9314415 ; Launch HN guide https://news.ycombinator.com/yli.html ; a16z New Media https://a16z.com/new-media/ ; X video resources https://business.x.com/en/resources/video ; YC Buildspace profile https://www.ycombinator.com/companies/buildspace
- Farza posts: https://x.com/FarzaTV/status/2041314633978659092 ; https://x.com/FarzaTV/status/2043402737828962489 ; repo https://github.com/farzaa/clicky
- Prior probe E1: docs/research/video-understanding-human-parity-2026-10-23/agents/E1-exam-key.md (Q11, YouTube metadata)
