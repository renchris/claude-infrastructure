<!-- markdownlint-configure-file { "MD013": false } -->

# Farza's launch-video method: METHOD, final pass (2026-10-24)

## 1. About this document

**What this is.** A step-by-step method for frequent, founder-led demo launches. It is distilled from Farza Majeed's YC interview, then checked three ways: against his own launch videos measured frame by frame, against what he has said elsewhere, and against outside evidence. This is the stage-1 research deliverable; stage 2 turns it into a skill (§8). Slot S1 wrote this final pass from S0's draft (`agents/S0-method-draft-v1.md`) and C1's skeptic review (`agents/C1-skeptic-review.md`). Where they disagreed, I checked the primary source (§9).

**Sources.** The `agents/` paths are relative to `docs/research/farza-launch-video-method-2026-10-24/`.

| Code | Source | What it contributes |
| --- | --- | --- |
| Interview | YC Startup School "Launch Video Advice": Aaron Epstein (host) with Farza Majeed, posted 2026-10-23. https://x.com/ycombinator/status/2113654566776709147 (YouTube `v12aSIZIXUs`). Transcript `/tmp/farza-2026-10-24/transcript.txt` (whisper, one `[mm:ss]` per line); video `/tmp/farza-2026-10-24/video.mp4`. | Everything QUOTED |
| R1 | `agents/R1-chapters-intro-to-clicky.md` | 00:00-07:43: cold open, launch cadence, the Clicky launch shot by shot |
| R2 | `agents/R2-chapters-hook-to-ddd.md` | 07:43-17:25: hook test, the on-screen script, first 10 seconds, demo-driven development |
| R3 | `agents/R3-chapters-shots-to-show.md` | 17:25-29:11: thousand shots, the formula, stories, process videos |
| R4 | `agents/R4-chapters-customers-to-challenge.md` | 29:11-47:08: channels, conversion, filmmaker, stack, 30-day challenge |
| A1 | `agents/A1-farza-launch-videos-measured.md` | Six of his launch videos measured: cuts, captions, face and screen share, first 10 s, copy |
| W1 | `agents/W1-farza-written-guidance.md` | 27 other sources by Farza (X posts, Substack, vlogs, podcasts) compared with the interview |
| X1 | `agents/X1-external-corroboration.md` | Outside corroboration and counter-evidence for each main claim |
| K1 | `agents/K1-video-stack-agent-era.md` | The stack with prices as of 2026-10-24, and what an agent can do at each step |
| C1 | `agents/C1-skeptic-review.md` | 97 verdicts on the draft; 167 timestamps checked; heyclicky YouTube listed with yt-dlp |
| launch-film, demo-recording | `skills/launch-film/SKILL.md`, `skills/demo-recording/SKILL.md` | Our two sibling video skills, for the boundary in §6 |

**Labels.**

- **QUOTED** means his words, or the host's where marked "(host)", with `[mm:ss]`, at most one sentence. A cited time is the start of the transcript line that holds the words. C1 matched 167 cited phrases: 161 land on the cited line, and 6 fall 2-5 s later in the same sentence. Capitals are restored and known mishearings fixed (heyclicky, Buildspace, Y Combinator, DaVinci Resolve). Speakers are INFERRED from content and shot, since the ASR has no speaker labels. "Vikrant" is the ASR spelling. The same spelling appears on screen in a Clicky UI tile on the _heyclicky grid, "Evening, Vikrant" (R3 I11). That the tile's Vikrant is his filmmaker is INFERRED.
- **MEASURED** means a slot in this study saw or ran it. The slot is named, for example "(MEASURED, A1)", and its file names the command. In this run I re-transcribed one v1 line (§3.8, step 38); scratch files are in `/tmp/farza-S1/`.
- **DOCUMENTED** means a source states it; the URL is in the slot file. "Search summary" means the slot read a search result, not the page.
- **INFERRED** means reasoning, including arithmetic and estimates; the method is named.

**Summary of the approach.** Farza treats a launch as a small, frequent, public demo of something new, not a single event. "What are we launching this week?" is the planning question, and the caption and hook are drafted before the feature is built. When something works, he notices the moment he would say "check this out" to a teammate and records it. In 5 of his 6 measured videos he names the thing by about 3.5 s, and none opens on a title card. Each demo is told as a mini story with a turn. He posts everywhere and walks away from the view counter, though not from the reply thread. He judges channels by downloads, retention and conversion where he can measure them, and he uses views as the early signal and to pick what to repeat. Volume does the rest, because even he cannot predict his hits. Across his four measured X demos, a raw single take and a fully produced cut each reached about 3M views. Four videos cannot show that production level does not matter. The main caveats are in §7:

- the examples are mostly hits, from an audience built over a decade;
- a full-time filmmaker made most of them;
- his conversion figures are unshown anecdotes;
- the measured habits come only from videos that did well.

## 2. Principles

Evidence grades:
- **Anecdote**: Farza's own account only.
- **Measured (A1)**: visible in his own measured videos; n is given where it is small.
- **Corroborated (X1)**: outside evidence supports it.
- **Contested**: his statements, his practice or outside evidence conflict.

A principle can carry more than one grade.

| # | Principle | Source | Grade | Why that grade |
| --- | --- | --- | --- | --- |
| P1 | Launch constantly. A launch is anything new you show in public, so call it a demo. | [02:31], [03:48], [18:49], [28:56] | Corroborated (X1) | YC's "How to Launch (Again and Again)" (2019) and Buffer's 2025 frequency data agree. Limit: Launch HN and Product Hunt are one-shot channels. |
| P2 | Launch to get users through a channel you can repeat, not for clout. | [05:50]-[05:56] | Corroborated (X1) | Paul Graham (2009): a launch is "a pretext for engaging users". Buildspace's YC profile calls its 2023 reach "very one-off" (W1 S24). |
| P3 | Work backwards: write the caption and the hook before you build the feature. | [03:59]-[04:32] | Anecdote; partly corroborated (X1) | Same idea as Amazon's Working Backwards, but no outcome data. He has done it since at least 2025 (W1 S7, S14). |
| P4 | Watch for the "check this out" moment; that raw register is how to show up online. | [15:31]-[15:48] | Anecdote | A1 measures the phrase, not the moment. "Check this out" is his pivot line in raw takes (v1 at 9.6 s; v2's opening) and in scripted ones (v4 at 31 s, written three days ahead [14:00]-[14:05]; the on-screen script). |
| P5 | Show the process, not the polished ending. | [05:02], [25:27]-[26:09] | Anecdote; copying risk documented (X1) | Glossier's "constant drumbeat" (X1 §2.3) is about launch frequency, not process. Copying is documented: Cory Zue (2022), and Clicky's 1,552 forks. |
| P6 | The number-one rule: would I stop, and would I read the first sentence? | [08:50]-[09:10] | Anecdote | This tests the post copy. W1 found the feed-mockup test nowhere outside the interview. |
| P7 | Pick the first frame for the target audience. Make the key detail visible and moving within 3 s. | [09:11]-[09:42] | Measured, n=1 (v1); corroborated in direction (X1) | Only v1 does it: Xcode at frame 0, zoom onto the cursor buddy at 2.2 s. TikTok and Facebook ad data link a key message in the first 3 s of a video to performance (X1 §2.4), but the data is correlational. |
| P8 | The first 10 s cover what you're doing, why it matters, and "let's get into it". Setup is 10-20% of runtime. | [11:04]-[11:31] | Measured, partly (A1) | The "what" lands by 2.3-3.6 s in 5 of 6. The demo starts at 8-10% in v1, v3 and v4, at 2% in v2 and at 36% in v6; v5 has no demo. The problem or turn comes at about 10% (v1), 26% (v4) and 43% (v3). |
| P9 | Script the video, then rehearse until it sounds unscripted. | [10:13] (host), [13:59]-[14:16] | Contested | The Clicky launch (3.0M views) was "almost entirely unplanned" [10:00]. He tells first-timers not to script [45:20]. No outside study tests it. |
| P10 | The formula: who I am, what's going on, what I'm working on, let me show you. | [21:51]-[21:56] | Measured, partly (A1) | No measured video states all four steps. v6 states three (no "who I am"), v5 states only "who I am", and v1-v4 start at "what I'm working on". The 20.9M reel's "who I am" is at most its YC credential (R3 §3). |
| P11 | A video converts when the hook is super clear and it is clear why to care right now. Check where you bounce. | [22:34]-[22:48] | Anecdote | No conversion data is tied to it. |
| P12 | A demo is a mini story with beats and a turn. Keep the story moving; don't chase attention. | [24:04] (host), [37:06] (host), [37:31]-[37:36] | Measured (A1); partly corroborated (X1) | 3 of 4 demos have a turn, and v2 has comic beats instead. The problem is always stated as his own. TikTok (2020) and Wistia (2018) both put story above polish. |
| P13 | Show your face clearly, and talk to the one person who would find it cool. | [12:30]-[12:52] | Measured, partly (A1) | In the raw takes his face is on screen 100% of the time, but only as a bubble. In the edited videos it is 32-62%. |
| P14 | Take a thousand shots. Post what you think is bad; zero views is fine. | [20:25], [16:56], [14:38] | Corroborated for hit rate, contested for skill (X1) | Buffer: posting more grows the tail, but median views stay flat. |
| P15 | Audio quality is the most important thing in any video. | [41:46]-[42:27] | Corroborated (X1); unverified in his own hits | Newman & Schwarz (2018). Limit: much feed video plays muted. A1 did not check which mic v1 and v2 used. v1 is an un-normalized raw take at -32 dBFS. v2's webcam bubble shows white earbuds (R4 §3); if they were the mic, his own rule says they "don't count". |
| P16 | Every channel converts differently, so measure conversion per channel. | [31:03]-[33:18] | Anecdote; his numbers contested (X1) | "Like 20" percent on YouTube is implausible as a views-to-downloads rate. |
| P17 | Make each video for one primary platform, then cross-post. X wants 16:9. | [33:23]-[33:39] | Measured (A1), confounded | On X, horizontal posts reached 0.63-3.83M views and vertical ones 65-73K. But v6 came from @heyclicky (15,584 followers), not @FarzaTV (129,259) (W1 §4). The only same-account vertical post, v5, is n=1 and on another topic. |
| P18 | Be cringe first: start before you are good. | [28:12]-[28:28], [44:56] | Anecdote | He gives the same advice in his 2026-01 Substack (W1 S11), so it is a stable belief. |
| P19 | Hire a filmmaker early. The founder keeps the script, the song and the vibe. | [39:05]-[39:10], [43:26]-[43:47] | Contested (X1) | Untested. Buildspace had a 2-of-7 film team and is listed "Inactive" on YC. It closed by his choice with over two years of cash (W1 S22), so this is weak counter-evidence. |
| P20 | State the product's flaws in public, on camera and in the replies. | A1 v1, v2, v4; W1 S2 | Measured (A1) | Examples: v1's LUT aside (86.8 s); "It's a little bit buggy" in v4's CTA; "High chance I run of credits lol" and "a bit dumb right now" in v1's replies; "I'll fix tomorrow I'm going to sleep lol" under v2. He never states this as a rule. |

## 3. The procedure

Steps are numbered across the whole section so that §5 can refer to them. Each step names who does it only where it matters; §5 gives the full founder/agent split. Steps marked INFERRED are this study's additions, not his advice.

### 3.0 Set up once

1. **Write down your tiers.** These are the defaults, from his practice:
   - a demo whenever something new works, ideally several a week ("demos every single day almost" [16:06]);
   - a team "everything we built" update, every two weeks [26:51] or weekly (the clip is titled "this week" [24:52]; W1 S13 planned "one weekly update");
   - a polished launch about once a quarter, "something I'm really proud of" [15:57]-[16:02], made with his filmmaker (§3.12);
   - optionally, a one-line teaser with a short clip the day before a release, then a livestream on the day (W1 S5).

   His quarterly tier is a produced video with the founder on camera. It is not our launch-film skill, which rules out a human shoot (§6).
2. **Get a real microphone first.** Any external mic will do, and a used cheap DJI is fine. Laptop and AirPods mics "don't count" [41:46]-[42:27].
3. **Install a screen recorder that smooths the cursor and zooms.** He uses Screen Studio [40:53]; §3.12 lists free alternatives.
4. **Tag every post, not only every profile.** His profile links are tagged:
   - heyclicky.com/ig on Instagram [32:47];
   - heyclicky.com/x on the @heyclicky X profile (MEASURED, A1);
   - heyclicky.com/yt on the YouTube channel (R1 Insert C);
   - heyclicky.com/farza in his personal Instagram bio (R3 I10).

   His posts are not tagged. His X self-replies link clicky.so (v1) or heyclicky.com/try (v2-v4) (A1), and the YouTube dictation description links a bare heyclicky.com (R2 §3.7). INFERRED: give each post its own path or UTM. For a desktop app, also give mobile visitors a "send it to yourself" button and track its click rate [32:58].
5. **Instrument the product before you need the numbers** (INFERRED; C1 row 20). Per-post retention needs four things:
   - a signup or download event that carries the link path;
   - a first-use event;
   - a query for users active on each of days 1-5 (his cut, "every day for five days straight" [07:27]-[07:30]);
   - optionally, a "how did you hear about us" question for visitors who arrive without a link.

   R4 I-15 shows the kind of chart this produces: `user_message_sent Unique 1,474` on 28 Apr 2026.
6. **Start a post log.** One row per post:
   - date, platform and account;
   - register (§3.3);
   - hook line and first frame;
   - length;
   - views, link clicks, signups or downloads;
   - day-5 retention.

   The challenge's "look back" at the one that did 1,000 views [46:26]-[46:36] assumes such a log (INFERRED).
7. **Name your "post it anyway" person.** This is a partner, teammate or editor who overrules your sense that it is bad:
   - Aaron got him to post the Clicky demo [06:19]-[06:29];
   - Vikrant overruled "the worst video we've ever done" [14:26]-[14:29];
   - "it's good to have the team also be really like, hey, we made this like, we're going to put it out" [14:33].

### 3.1 Launch cadence

8. **Every week, ask "what are we launching this week?"** and work backwards from that launch [03:55]-[03:59]. A launch is "we did something new at the company, we talk about it" [18:49]. If more than one person might see it, post it [18:54].
9. **Every day, take 10 minutes.** Ask what you did today that made you smile or was interesting. Talk about it, show it, post it, close the app, and go back to work [28:44]-[28:56].
10. **Make the team update in one of two versions.** It started as accountability, "kind of like stand up right but in front of the world" [26:48]. It has "no hook there's no attention there's no story" [25:12]-[25:18], and it is aimed at existing users ("our users have been loving it" [24:41]).
    - **The 10-minute version.** Prompt each person with "what are you doing today?" and keep the effort to about 10 minutes [26:30]-[26:36]. INFERRED: a phone selfie with a handheld mic is enough. The "shipping a ton" clip looks like this, a group selfie at the Transamerica Pyramid with Farza holding a DJI mic (R1 Insert D), though its effort is not stated.
    - **The produced version.** This is what the interview shows (R3 I12): three speakers in about 22 s, each giving one line about one shipped change, a graded group shot outdoors, B-roll from several places over each line, one big title card, and captions throughout. Its edit time is not stated, and it is plainly more than 10 minutes (R3, INFERRED).
    - **Reach.** The host says one has "almost a million views on Instagram" [25:22], which is not shown. The YouTube copies have 1,900 views ("this is everything we shipped.") and 913 ("shipping a ton and fixing 200+ bugs") (MEASURED, C1 yt-dlp). The second showed 787 in the cold open (R1).
11. **Spend one-shot channels only on substantive releases.** YC gives each company one Launch HN (DOCUMENTED, X1 §2.1). Product Hunt reportedly expects about six months between launches (forum post, search summary, X1 §2.1). The split is X1's advice, though it matches his own: daily demos plus a polished launch "maybe once a quarter" [15:57]. A one-shot channel takes whatever finished asset the release has, the produced demo or a launch-film hero (§6). The copy follows the channel's own rules. HN's guide says "Don't write in a marketing, sales, or PR style" (X1 §2.1).

**Time budget** (INFERRED, adding up his own figures):
- daily demos: 10 minutes a day [28:44], [46:00];
- the team update: 10 minutes of capture, edit unstated [26:30];
- a produced feature video: "like an hour" for him [20:50] up to 4-6 hours [22:14];
- a long-form YouTube story: about 8 hours, 3 of them on thumbnails (W1 S10).

A founder alone, doing daily demos plus one produced video a week, is looking at about 2-8 hours a week. Nobody has measured this.

### 3.2 Demo-driven development: build the demo moment first

The host names this "demo-driven development": work backwards from the demo you want at the end [15:14] (host). Farza's version is about the moment, not the artifact.

12. **At feature kickoff, before building, write the caption and the hook.** He asks "what's the copy on the Instagram caption?" [04:08] and "what's the hook if we make this a video?" [04:11]. In the interview, "it just sounds good on paper" is his reason he "kind of know[s] it's a hit" [04:28]-[04:32], and he adds "not that like it needs to ... go viral" [04:15]. The build gate comes from his other writing (W1):
    - he "drafted hella tweets", each angling the idea a different way, before building (S7);
    - "If I can't really explain it in 280 characters, then it's probably too complicated" (S14).

    Use it as a clarity check, not a hit predictor; his own predictions are weak (§7.1). If you cannot state the feature in a caption that excites you, rethink the feature or its angle.
13. **Pick one grounding frame.** This is the single image the video exists to show, an idea he took from Miyazaki (W1 S7). For the October 2025 precursor demo it was "this cute blue cursor popping in from the right side of my Mac's screen, and saying hi" (W1 S7, S31). The grounding frame is not the first frame. v1's first frame is Xcode, chosen for the audience [09:13]-[09:22]. The zoom at 2.2 s brings the blue cursor into view (A1; the link to S7 is INFERRED).
14. **Build toward the "check this out" moment.** That is the moment you turn to a teammate or co-founder and say it [15:31]-[15:43], and that raw "check this out" is how to present yourself online [15:43]-[15:48]. When it first works, record it, and do not stop to check whether someone did it first [36:25]-[36:31]. Show your own first real use [36:36]-[36:42].
15. **Optionally, set a same-day posting deadline.** If the full feature is not working by then, cut to an angle you can demo today. This rests on one 2025 anecdote, where a feature failed at 5 PM and he posted a smaller angle that evening (W1 S7). His biggest hit broke the rule: he "had been sitting on the Clicky demo for a few weeks" (W1 S3) and "tabled it for another two weeks" (W1 S19).

### 3.3 Pick the register

A1 measured the first three registers on his own posts. The others were seen inside the interview, described only, or documented elsewhere.

| Register | What it looks like | Examples | Effort | Use it when |
| --- | --- | --- | --- | --- |
| **Raw screen take** | One continuous screen recording with a webcam bubble the whole time. 0-3 edits, no captions, no music (MEASURED, A1). | v1 Clicky launch (3.00M X views), v2 "no hands" (3.83M) | One take. v1 went up about 13 min after the take ended (A1; the timezone is INFERRED). | A fresh "check this out" moment that is visible on screen. Tool or developer audience. X. |
| **Produced feature demo** | Presenter in a real place, product close-ups, full-screen recordings. 13-19 cuts a minute, phrase captions, a music bed, an end card (A1). | v3 drawing (0.63M), v4 dictation (2.95M X; 21K YouTube) | v4: every line scripted three days ahead [14:00]-[14:05]; v3's scripting is unknown. Made by his filmmaker [42:51]-[42:53]. | A named feature that needs a turn to explain. YouTube library, X, Instagram. His quarterly polished launch is this register at higher effort. |
| **Vertical story** | 9:16, 45-52 cuts a minute (v5's 45.5 overcounts archival footage), 1-3 word captions, proof screenshots or archival footage, music (A1). | v5 "hi my name is farza" (65K X), v6 "i went viral" (73K X, from @heyclicky); the 20.9M Instagram reel (R3 I6) | 4-6 hours for the 20.9M reel [22:14]-[22:19] | Instagram and TikTok. Milestones, origin story, "what's going on". |
| **Fast-cut progress reel** | Vertical, cuts about every 0.7-1.3 s, real proof on screen (a usage chart) (R4 I-14, I-15) | "It has been 9 weeks", "Two weeks ago…" (seen in the interview only) | Not stated | "The audience that just has no attention span" [37:53] |
| **Team update** | See step 10. | "everything we built this week" (R3 I12) | 10 minutes [26:30], or more for the produced version | Weekly or every two weeks, for existing users. |
| **Niche call-out** | Opens by naming the viewer's role (described only; no TikTok was shown, R4 #8). | Design-agency TikToks, about 4,000 views each, about 50 leads [30:33]-[30:48] | Unknown | A B2B niche on consumer feeds (step 52). |
| **Long-form YouTube story** | A scripted, narrated story of making something (W1 S14) | His first YouTube video in a decade (2025-04, about a quarter million views across platforms, W1 S10); "the art of making something from nothing." (7 min 24 s, 53K views, W1 S14) | About 8 h for the first: script 30 min, shoot and edit 5 h, thumbnails 3 h (W1 S10) | A story that outlasts the feed. YouTube. |
| **Teaser, then livestream** | "Something new. See you tomorrow, link below." with a 33-66 s clip, then a stream on launch day (W1 S5) | Apr 22 and May 13 2026 teasers (174K, 102K views) | Not stated | A dated release. |

The minimum version of any register is a selfie: "hi, this is what I'm working on, check this out", then turn the camera to show the screen [22:19]-[22:24]. He adds "I think the effect may not have been as big" [22:28]. His standing advice to anyone starting is a 30-second selfie video [27:30]-[27:37]. The 30-day challenge (§3.13) asks for 10 minutes a day and gives no length.

16. **Choose one register per video.** His default is to make the video for Instagram: "most of our videos we make for instagram" [33:23], and @heyclicky once apologized to X for posting an update there two months after Instagram (W1 S6). Make a raw screen take for X when the moment is fresh, visible on screen and aimed at developers. v1 itself was "almost entirely unplanned" [10:00].

### 3.4 Script

17. **Decide how much to script, by experience and register.**
    - The rule in general: "spend as much time possible before the video writing it" [45:14].
    - First videos: do not worry about writing [45:20].
    - From about the 15th to 30th video: write for 10 minutes about what the video should be, then record [45:22]-[45:29]. Writing first lets you "catch a bad idea" before the camera [45:36].
    - A produced acquisition video: v4 had every line written about three days ahead [14:00]-[14:05]. For his first YouTube video in a decade, the script took 30 minutes (W1 S10).
    - Who writes varies. In the interview Farza brings "the script" [43:26]. On Tidbit's TikToks in 2025, "Hasan just puts the camera in my face, gives me a script" (W1 S8).

    Write in a plain, distraction-free editor. He uses FreeWrite, his own free app [45:01]-[45:08]. The order is script first, then visuals [11:56] (host).

**The script he showed** (MEASURED, R2 §3.5, frame at 666 s). It is for a video he recorded "yesterday" [10:37]. The top line is clipped by the frame (plausibly "Hi,"), and the page is cut off at the bottom. Typos are his. The finished video was never located (§8).

```text
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
```

Its beats (INFERRED from the text):

1. **What**, in one line.
2. **Problem, from users**: why it matters. He selected this block on screen while asking "am I getting across what I'm doing? Why is it important?" [11:04]-[11:16].
3. **Stakes**: "agents can be really magical".
4. **Tension**: "most people never get there".
5. **What-if** with two concrete personas.
6. **Bridge**: "you gotta ask".
7. **Pivot**: "So, check this out."
8. **Stage direction** in angle brackets.
9. **Demo narration.**

The setup (beats 1-2) is about 75 of the roughly 260 visible words (INFERRED, estimated by line count, R2).

18. **Mark the setup block.** The opening should say what you're doing and why it matters, then "let's get into it" [11:13]-[11:16]. Keep it to "like 10, 20%" of the runtime [11:27]-[11:31], by analogy to a film's first 20 minutes. He says "both these videos are one minute long" [11:19]. At that point only v1 (100 s) had been shown; the next video shown, v4, runs 120 s (R2 I8; MEASURED, A1). So budget the setup as a share of the real length: 10-20 s for 100 s, 12-24 s for 120 s, 14-28 s for 140 s (arithmetic).
19. **Run his three reading tests.**
    - "If I like reading it, then that means it'll probably sound good if I say it out loud as well." [10:30] He adds "not always" [10:35].
    - "Would I read this if someone texted this to me?" [10:45]
    - "For me, it's always I'm the audience." [10:54]
20. **Make it sound off the cuff.** This is the surprising part, since he "seem[s] like you're just talking off the cuff" [10:19] (host). What he does:
    - **Write for the ear.** The script uses spoken forms ("kinda", "sick", "gotta", "That'd be sick"), short sentences and exclamation marks (MEASURED, the script above).
    - **Frame the problem as your own.** "I'm not saying everyone has this problem where they don't know what to write." [13:36]
    - **Rehearse in your head, away from the desk.** He says each line over and over "in the shower, going to work", asking how to say it, until "I've already visualized it like 10 times" [14:05]-[14:16].
    - **Treat the page as notes.** Describing this script in conversation, he says "I want to share a new demo" [11:34], while the page says "I want to show you a demo" (MEASURED). That shows he paraphrases his own script. It does not show how he delivered the video, which no slot measured. He mentions no teleprompter anywhere (K1).
    - **Talk as yourself.** "That's just me being myself, which is like, hey, I want to show you." [13:51]-[13:55]
    - **Record even when the script feels weak.** He called this one "not that strong, but I still recorded the video because you got to be launching" [10:59]-[11:03].

    Outside evidence has two halves (X1 §2.5; Rifkin & Du 2023, on entertainment performers). People rate spontaneous performers as more authentic, and they also expect spontaneous work to be of lower quality. INFERRED: script for quality and keep the script from showing.

### 3.5 Hook formula and the post-copy rewrite

21. **Write the X copy in his order:** "I built this thing", then what it is ("It's an AI teacher"), then what it does, then why it matters [07:53]-[07:58]. He cares about length and the parts of the story ("tweet poetry", [08:04]-[08:11]). The measured copy (A1):
    - three of the four launch posts run 276-280 characters;
    - the biggest X hit, v2 (3.83M), runs 151, so do not infer that filling the tweet helps;
    - three of the four end with a bare "Demo:".

| Line's job | v1 Clicky launch (3.00M) | v2 no hands (3.83M) | v3 drawing (0.63M) | v4 dictation (2.95M) |
| --- | --- | --- | --- | --- |
| 1. Plain claim | "I built this thing called Clicky." | "Watch me control my computer with just my voice." | "We built an AI that can draw on your screen." | "Today we're shipping screen-aware dictation." |
| 2. What it is, in one line | "It's an AI teacher that lives as a buddy next to your cursor." | "This is the future of operating systems." | "It's a true personal tutor." | "First, we built a speedy speech-to-text (very fast, ~450ms)." |
| 3. What it does, or the turn | "It can see your screen, talk to you, and even point at stuff, kinda like having a real teacher next to you." | "No hands." | "Using Claude Opus we're able to draw polygons, point with pixel perfect accuracy, and walk users through complex steps directly on their screen." | "But, many products do this!" then "So we went further." |
| 4. Concrete use or proof | "I've been using it the past few days to learn Davinci Resolve, 10/10." | "GPT-Realtime 2.0 is very, very underrated." | "Here's me learning Pythagorean Theorem + FL Studio." | "In Claude Code, it writes the prompt." |
| 5. Hand-off | (video sits under the text) | "Demo:" | "Demo:" | "Demo:" |

The template does not predict views. His Jul 8 "Today we're shipping spatial context." post used v4's structure and got 294K views, against v4's 2.9M six days later (R1 Insert F, on screen). The story register on X uses almost no copy: "hi my name is farza / i just wanted to introduce myself" (54 characters) and "i went viral" (12 characters) (A1).

22. **Write the Instagram caption and the YouTube title as well.** The Instagram caption is his first kickoff question [04:08]. The measured Instagram captions are short, lower-case hooks, not descriptions:
    - "im building a buddy for your computer cursor" (the 20.9M reel, R3 I6);
    - "is my startup trash? let's decide." (the "9 weeks" reel, R1 Insert H);
    - "Put something out, see what happens." (the "two weeks" reel, R4 I-15).

    The heyclicky YouTube titles are mostly lower-case. Three of 11 long-form titles end in a period, such as "introducing screen-aware dictation.", and none of the 8 Shorts titles does (MEASURED, C1 yt-dlp). Most thumbnails show a face (R2 I7, a search page). For a long-form video he spent 3 of about 8 hours on thumbnails (W1 S10).

**Hooks by register.** These open both the post and the video.

- **Demo hook.** A greeting, then the thing, then one line describing what is literally on screen. Examples: "Hey, everyone. So this is Clicky." (v1), "Hey, so today we're adding dictation to HeyClicky." (v4), "Alright, check this out, no hands, ready?" (v2) (A1).
- **Story hook. This needs prior success.** It combines recent social proof, self-deprecation and a credential your niche recognizes. Example: "Last week I went super viral for an idea that I built that I thought was actually kind of terrible, and this week I'm somehow in Y Combinator." [21:26]-[21:31] He says naming YC was "targeting that niche" [21:47]. A newcomer has no viral hit or credential to cite, so this template builds survivorship in.
- **Curiosity gap: the newcomer's version.** Open with a time jump that withholds the outcome, like the "two months ago…" reel he found and would reuse "as like a template" [23:11]-[23:26]. His own "Two weeks ago I was in my apartment…" reel does the same (R4 I-15).
- **Niche call-out.** Name the viewer's role: "hey are you the founder of a design agency stop right there let me show you something really cool" [30:33] (as transcribed).

He warns against copying his hook as a formula [09:54]. The test is the stop test, not the template.

23. **Run the feed-mockup test.** On X web, find a stranger's post in your real feed. Open Chrome DevTools, inspect the post's text and replace it with your draft. The change is local only, and nothing is posted (MEASURED, R2 §3.2: he edited a real post's text span, then scrolled the feed). Then ask "did my eye stop?" [08:50] and whether you would read the first sentence [09:06]. This is his "number one rule, regardless of Twitter, Instagram, YouTube, anything" [08:59].
24. **Rewrite until it passes.** If your eye slid past, or you would not read beyond line one, rewrite the first line and run step 23 again. Expect several angles before one stops you (INFERRED; his "drafted hella tweets" happened before building, W1 S7).
25. **Run the mute test on the video.** Watch it muted at scroll speed and say aloud the few words your brain picks up. His reading of the drawing video was "guy in front of blackboard, AI, draw, screen … Claude Opus, demo, click" [33:54]-[34:07], because "nobody's reading this entire … damn thing" [34:07]-[34:11]. A third-party analysis comparing Clicky with his failed Tidbit puts it as "Distribution only carries what people understand on mute." (W1 S27). Optimizing for one platform did not predict where a video performed. The drawing video he calls "super optimized for twitter" [33:50] was his weakest measured X demo (629K, A1), and it did "even better" on Instagram [34:17].
26. **Put the link in a self-reply, not the post.** This is his habit, though he never states it. In all four launch posts the URL came in a self-reply 4 h 42 min to 7 h 46 min later (MEASURED, A1), phrased like "This is real, and shipped". The replies carry honest notes such as "High chance I run of credits lol" (W1 S2). INFERRED: this keeps the scored post link-free. The evidence on X's link treatment has two halves (X1 §2.9):
    - PPC Land's analysis of X's open-sourced code found that posts with links got 94% fewer views;
    - Musk said on 2026-07-29 that X had not penalized links "for over a year".

    Test it yourself.

### 3.6 The first 10 seconds

27. **Choose the first frame for your audience.** "It's very purposely Xcode", because curious developers come first, not video editors [09:13]-[09:22], even though the use case shown was learning DaVinci Resolve. "Most people, when they're scrolling, see the first three seconds." [09:32] On YouTube the window is longer: its Intro report measures the first 30 s (X1 §2.4).
28. **Lay out the first 10 seconds with the template for your register.** The templates come from A1's frame-by-frame reads, and they describe videos that did well. In all six videos the first word starts within 0.25 s, with no title card, logo or music intro.

**Template A: raw screen take (16:9, X first).** In substance this is n=1: v1. v2 shares only its first 2.5 s, and then the demo starts.

| Time | Picture | Words | Text on screen |
| --- | --- | --- | --- |
| 0.0-0.3 s | Full desktop in the audience's own tool (Xcode), webcam bubble bottom-right | First word at 0.08 s (v1) or 0.20 s (v2) | none |
| 0.3-2.4 s | Same. One gesture to camera: a peace sign at 0.5 s (v1), open palms on "no hands" at 1.5-2.0 s (v2) | "Hey, everyone. So this is Clicky." (0.08-2.36 s) | none |
| about 2.2 s | Animated zoom onto the small key element (the blue triangle beside the pointer) [09:24] | | none |
| 2.5-7.0 s | Hold the zoom; move the cursor so something visibly moves [09:40] | One line describing what is on screen: "Clicky is this little blue guy that follows your cursor…" | none |
| about 7.0 s | Zoom back out to the full desktop | "…it's basically an AI teacher that can teach you anything." (to 9.41 s) | none |
| 9.6-10.4 s | Full desktop | "So check this out." | none |
| 10.4 s on | The real use case, framed as a personal problem ("a video editing program that I've been procrastinating learning") | | none |

Neither video has a hard cut in its first 10 s. v2 is demo-first: the spoken command comes at 2.5 s, and Spotify opens at 10.1 s.

**Template B: produced feature demo (16:9, edited).** From v3 and v4. A1 did not identify the presenters; a comment on the drawing reel reads "Well done Zain" (R4 I-8).

| Time | Picture | Words | Text on screen |
| --- | --- | --- | --- |
| 0.0-0.5 s | Medium shot of the presenter facing camera in a real place (an outdoor table with a laptop; a blackboard). In v3 he walks into frame | First word at 0.04 s (v4) or 0.23 s (v3) | Caption from 0.5-1.0 s: 3-6 word chunks, white, bottom-center at about 80% of height |
| 0-3 s | Same | "Hey, so today we're adding dictation to HeyClicky." (to 2.94 s) | "Hey, so today we're adding" |
| 3.5-6.6 s | Cut to a close-up of how it works: fingers on fn + control (v4, 4.04-6.01 s); a hand chalking a triangle and an arrow (v3, 3.50-6.64 s) | The one gesture or capability | "hold fn + control," |
| 6-10 s | Back to the face | The rest of the what: "…whatever text box your cursor is on." | phrase chunks |
| about 8-10 s | | Music bed comes up (v4) | |
| 10-11 s | First full-screen product recording; the demo starts at 8-9% of runtime | | captions continue |

There are 2 cuts in the first 10 s. In v4 the turn comes at 21-30 s and the reveal at 31 s, on a new, darker setup (A1).

**Template C: vertical story (9:16).** From v6, whose only measured result is 73K views on X from the smaller @heyclicky account. How it performs on Instagram, its target platform, is unknown. The 20.9M reel's hook is a variant, noted below the table.

| Time | Picture | Words | Text on screen |
| --- | --- | --- | --- |
| 0-1.3 s | Wide: founder under a tree with a laptop | "Today we crossed over 5 million views on this thing we're building called Clicky" (0.12-3.56 s) | 2-3 word captions at about 63% of height from 0.0 s |
| 1.3-2.7 s | Punch in to medium | | |
| 2.7-3.8 s | Seven proof screenshots at about 0.1 s each: the launch post, README, repo, site | | |
| 3.8-6.5 s | Screen recordings of the product working (Logic Pro, DaVinci) | | |
| 7.0-8.9 s | Double exposure: head in hands, plus the product pointer reading "Make a cut here" | "…considering that I thought it was actually a pretty meh idea" | |
| 8.9-9.7 s | Medium face shot | "meh idea." | |

There are 13 hard cuts in the first 10 s, music throughout, and the demo starts at 16.1 s (36%).

The 20.9M reel's hook runs about 7-8 s (MEASURED, R3 I6):
- his face is on camera for 6 of the 8 sampled seconds;
- second 2 cuts to the 2.8M-view X post as proof;
- second 7 holds a YC badge up to the lens;
- word-chunk captions run throughout.

29. **Check the cut against his habits, video by video.** These are habits measured on videos that did well, not thresholds (§7.1). Before stage 2 fixes any of them, it should measure lower performers as controls (§8).

| Habit (MEASURED, A1) | v1 | v2 | v3 | v4 | v5 | v6 | Holds in |
| --- | --- | --- | --- | --- | --- | --- | --- |
| First word within 0.3 s | 0.08 s | 0.20 s | 0.23 s | 0.04 s | 0.04 s | 0.12 s | 6 of 6 |
| No title card or logo sting | yes | yes | yes | yes | yes | yes | 6 of 6 |
| Thing named by about 3.6 s | 2.4 s | 2.3 s | 3.5 s | 2.9 s | 5.8 s (who he is) | 3.6 s | 5 of 6 |
| Key detail visible and moving by 3 s | yes (zoom 2.2 s) | no (product acts at 10.1 s) | no (chalk close-up 3.5 s) | no (keys 4.0 s) | no | no (product screen 3.8 s) | 1 of 6; screen-led takes only |
| Demo running by about 10% | 10% | 2% | 8% | 9% | no demo | 36% | 4 of 6 (all 4 X demos) |
| Problem or turn | problem from 10.4 s (10%) | none; comic beats | escalation at 60.3 s (43%) | turn 21-30 s, reveal 31 s (26%) | n/a | "meh idea" at 5-10 s | no common share |
| Spoken product CTA in last 3-7% | 97% | none | 93% | 93% | none ("thanks for following") | closing from 81% | 3 of 6 |
| Hard cuts in first 10 s | 0 | 0 | 2 | 2 | 3 | 13 | by register |

### 3.7 The formula for videos that convert

30. **Structure the video as:** "This is who I am, this is what's going on, this is what I'm working on, let me show you." [21:51]-[21:56] (also the cold open, [00:21]-[00:27]). He says "my formula is always the same" [21:51]. As executed in the 20.9M reel (R3 §3):
    1. **Who and what's going on**, about 7 s: social proof, then self-deprecation, then the niche credential. The "who" is at most the YC badge.
    2. **What I'm working on**: the name plus a one-line value proposition, "It's called Clicky, it's a little AI buddy that lives next to your computer cursor and teaches you anything in real time for free" [21:56]-[22:05].
    3. **Let me show you**: one relatable use case set against the status quo ("instead of going to a YouTube video" [22:05]-[22:10]). Then the product visibly does it: the pointer bubble says "this one!" on the color wheel (R3 I7).

    No measured video states all four steps (P10). INFERRED, the synthesis's split rather than his advice: use the fuller form for story videos, start at "what I'm working on" for feature demos as v1-v4 do, and skip it in the team update (step 10).
31. **Check the two properties he says matter.** First, a "super clear hook". Second, "a very clear like why you should care right now while you're on your scroll" [22:34]-[22:40].
32. **Run the bounce test** on your video and on others': "am I bouncing, when am I bouncing?" [22:48]. Cut or rework whatever causes it. On YouTube, the Intro and Dips reports show where viewers leave (X1 §2.4).
33. **Define "convert" before you claim it.** In the interview, the evidence that a video "converts" is mostly views:
    - the 20.9M reel "is still driving a lot of our traffic" [21:12] and now runs as a Facebook ad [21:22];
    - the YouTube dictation video is "one of our highest converting" with no figure given [12:12].

    The only conversion numbers are in §3.10. Treat "converts" as something you measure through your own tagged links and product events (steps 4-5), not as a property of the formula.

### 3.8 Turning demos into stories

The host frames it: "Everyone wants a story, and so how can a demo just be a mini story?" [24:04] (host; the cold open reuses it at [00:27]). Farza agrees that to a viewer on a feed he is "just a random character" [24:29]-[24:37].

34. **Build the turn.** The measured pattern (A1, pattern 4) is a concession, then a personal problem, then the reveal. v4 has it word for word:
    - concession: "So that's pretty cool, and honestly, many products already do this exact thing today." (21.2 s)
    - personal problem: "But here's the thing, when I'm writing, I often don't really know what I even want to say." (26-30 s)
    - reveal: "So check this out, we're shipping screen-aware dictation." (31 s)

    v3's turn is an escalation instead: "Alright, so that's kind of cute, but what if I wanted to do something a little bit more complicated?" (60 s). v2 has no turn, only comic beats.
35. **Put beats where cuts would go.** His no-hands demo has "not a single cut" [37:02] but has beats [37:06] (host), and "of course that's all purposeful" [37:18]. The measured beats (A1 v2, R4 §3) run:
    - the hook ("no hands");
    - the ask, then about 1.5 s of silence;
    - the song plays;
    - "it's a little bit loud", and the volume drops;
    - the Stripe dashboard, with a joke ("$140 in a day is not very good");
    - a new beat about every 10-15 s after that.

    The aim is to keep the story moving: "I'm not trying to keep your attention, that's actually the wrong way to look at it." [37:36]
36. **At each beat, ask from the viewer's seat: "am I here? am I still watching?"** [38:27]. Some videos are cut fast on purpose, for "the audience that just has no attention span" [37:53]. The "9 weeks" reel cuts about every 0.7-1.3 s (MEASURED, R4 I-14), but that rests on 3 luma cuts in a roughly 10 s excerpt.
37. **Place self-deprecation after a success beat.** Examples: v6's "a pretty meh idea", v4's "It's a little bit buggy" in its CTA (A1, pattern 5), and the reel's "an idea ... I thought was actually kind of terrible" [21:26]. The host notes the same quality in younger founders' hooks [23:48]-[24:00].
38. **Admit the product's mistakes in public (P20).** In v1, Clicky recommends a Sony LUT for Blackmagic RAW footage at 75 s. At 86.8 s he says on camera "I'm not sure why I recommended the Sony LUT for a Blackmagic thing, but ignoring that, that's clicky." C1 guessed "I" was an ASR slip for "it". I re-transcribed 84-93 s three ways in this run: whisper-cli large-v3-turbo, the q5_0 model, and a pass slowed to 0.6×. All three read "I recommended", with the "I" lasting about 0.04 s (MEASURED, `/tmp/farza-S1/`). Either way, the wrong recommendation was the product's, and he left it in and named it. The replies do the same (W1 S2, A1): "High chance I run of credits lol", "a bit dumb right now (only 10 messages of memory)", and under v2, "I'll fix tomorrow I'm going to sleep lol".
39. **Show what you're doing and why, never your life.** "You'll never catch me making those videos about this is my day as a YC founder." [25:52]-[25:59]
40. **Keep a swipe file.** Watch Reels "not for entertainment, just to kind of study" [22:54]. When a hook works on you, note its device (lighting, caption placement, a "two months ago" curiosity gap) and turn it into a template for your own story [23:05]-[23:26].

### 3.9 Record, edit, post

41. **Record at the level the register needs** [40:52]-[42:32]:
    - Level 1: Screen Studio for on-screen demos;
    - Level 2: phone selfie camera, edited on the phone in Edits;
    - Level 3: Sony FX3 or FX30 with a DJI mic, edited in DaVinci Resolve on the laptop.

    Whatever the level, "show yourself, show your face very clearly", be proud, and "confidently tell the camera what you're working on" [12:30]-[12:44]. Talk to "that like one other person in that world that may think this is cool" [12:48].
42. **Edit to his measured habits** (A1, patterns 3 and 8):
    - **Raw takes.** His raw X takes have no captions and no music; a jump cut may remove dead time. Decision (INFERRED, from X1 §2.11 and step 25): caption any version that goes to Instagram or TikTok, raw or not. Leave a raw X take uncaptioned only if the screen carries the meaning on mute.
    - **Edited videos.** Burned-in captions in short chunks, 1-6 words: 3-6 words at about 80% of height on 16:9, and 1-3 words at 63-69% on 9:16. Slots describe the 20.9M reel (R3 I7) and one team update (R1 Insert D) as word-level, so word-level captions are in his range too.
    - **Music.** Edited videos carry a bed; he brings "the song" himself [43:26]-[43:28]. Its level changes do not reliably mark the story. v3's dip (50-68 s) brackets its turn at 60 s, while v4's dip (56-66 s) misses both its turn (21-30 s) and its reveal (31 s). "Music" is INFERRED from the stereo side channel (A1).
43. **Let the length follow the beats.** His measured videos run 45-140 s (A1). X's business page recommends 6-15 s (X1 §2.4, search summary), and his X demos run 100-140 s, 7-23 times that, and still hit (arithmetic). INFERRED: like launch-film §5, treat length as an output of the beats, not a target, and note it in the log (step 6).
44. **End with a soft CTA in the last 3-7% of runtime.** Make it an invitation, never "sign up": "I'll put the link below and give it a shot." (v1); "Try to break it." (v3); "This is in production right now." (v4). v2, his biggest X hit, has no spoken CTA. v3's end card says "try it for free" and then "heyclicky"; v4's says "clicky" and then "heyclicky" (A1).
45. **Make each video for one primary platform, then cross-post** [33:23]. Most of his are made for Instagram (vertical) and posted to X, and X-first videos are 16:9 [33:35]-[33:39]. He does not always reframe:
    - the 16:9 drawing video went to Instagram letterboxed and did better there by likes (27.4K against 5.1K on X; R4 I-7, I-8) [34:17]-[34:30];
    - @heyclicky posted a 122 s vertical update to X (34.5K views, W1 S6).

    Whether reframing helps is untested (INFERRED). The dictation video went "just everywhere just to see what happens" [12:26]. A small channel is fine. He says the YouTube channel was three days old when that video went up [12:07]. Upload dates contradict this: "we are a real company now" went up on 2026-06-28, 16 days before the dictation video on 2026-07-14, and "hi i'm heyclicky" is older still (MEASURED, C1 yt-dlp). The channel had 872 subscribers at the time (R2).
46. **Run three checks before posting** (INFERRED unless cited).
    - **Redaction.** v2 shows a Stripe account ID in the URL bar, live revenue, and "1 dispute has not been answered" (R4 §3). Check every shot for account IDs, keys, emails, customer names and numbers a clone could use (X1 §2.3). demo-recording's contact-sheet gate ("no leaked content") is the model.
    - **Music rights.** In v2, AC/DC's "Back in Black" plays from Spotify on screen (A1), and v3 ends on a song with lyrics. No source discusses licensing. Adopt launch-film's rule: no music without a documented license.
    - **Show it to one person.** "And then, I have to show what I made to at least 1 person." (W1 S7) He adds: "99% of the time I think it's shit, someone else see's something cool." (W1 S7) For Freewrite it was Julian: "That's all I needed to see." (W1 S14)
47. **Post even if you think it is bad.** The reason is volume: posting more buys more chances at a hit while the typical post stays flat (Buffer, X1 §2.7). His two surprise hits are anecdotes, n=2, and nobody knows how many posts he thought bad that stayed bad.
    - He thought the Clicky demo "was not that good" [06:16] and was "so wrong" [06:37].
    - He thought the dictation video was the worst they had made [14:26]; it got 2.95M X views (MEASURED, A1).
    - "I'm constantly forcing myself to put it out." [14:59]
48. **Walk away from the counter.** Accept zero views at the moment you post [16:56]. "By the time I hit post, I've already forgotten it." [17:05] Check the numbers "maybe a week later" [17:10].
49. **Do not walk away from the thread.** His measured behavior after posting (A1, W1):
    - the link self-reply came 4 h 42 min to 7 h 46 min later;
    - v1 got a second reply 10 minutes after the first;
    - under v2 he wrote "I'll fix tomorrow I'm going to sleep lol" and, two days later, "Okay I fixed it";
    - within a week of the Clicky launch he had talked to the retained users (W1 S3).

    Answer questions, ship the small fixes the thread asks for, and say so in the thread.

### 3.10 Measure, and what he found per platform

50. **Measure downloads, then retention, then talk to the retained users.** "I do not care about the traffic at all." [07:05] For the Clicky launch:
    - he asked how many downloaded, "I think 7,000" [07:18];
    - then who retained, about 100 used it "every day for five days straight" [07:27]-[07:30];
    - then "I reached out to those 100 people" [07:34], and their unexpected uses kept him going [07:38]-[07:42].

    That makes 1.4% of downloaders retained (arithmetic). Dividing his 7,000 by the post's 3,000,762 views gives 0.23%, but that is a ratio of two unlike numbers, and it gives the X post the most credit it could get:
    - views count impressions, not people;
    - 7,000 is his recall;
    - the post had no link for 4 h 42 min;
    - he announced the open-source repo the next day (7,772 stars now, W1 S4), so the downloads cannot be attributed to the X post alone.

    A stronger test from his vlog is a Stripe link right after the demo, with a target of 25 paying customers (W1 S15).
51. **Compare channels on conversion, not views, and only once the sample can bear it** [32:38]-[33:13]. Use the per-post tags and product events from steps 4-5. Views are still his early signal: the 30-day challenge picks the next video by which one passed 1,000 views [46:22]-[46:36]. INFERRED decision rule: outcomes are heavy-tailed (X1 §2.7), so compare channels after 4-6 weeks (X1 §2.9) and several posts each, on medians of tracked conversions, never on one post.
52. **Find your niche in your organic users, then call it out.** Design agencies "really loved our product like three of them that found us naturally", so the question became how to get more [29:42]-[29:53]. The answer was call-out TikToks (§3.3) [30:23]-[30:38].
53. **Let winners keep working** [21:12]-[21:22], [32:12]:
    - YouTube "will keep on performing" as a library;
    - turn the winner into a paid ad, as he did with the 20.9M reel on Facebook;
    - build the landing page from demo clips, as heyclicky.com does with .mov windows such as "nohandstricklol.mov" (R1 Insert E);
    - treat open-sourcing as a second launch: he announced the repo the day after the launch post (W1 S4).

    INFERRED caution: over-promotion is a top reason people unfollow brands (Sprout Social, X1 §2.1). Reuse what shows something new, not the same ask.

| Platform | What he claims | Numbers | Evidence status | What to do |
| --- | --- | --- | --- | --- |
| **X** | Worst conversion over about 10 years [31:05]-[31:13]; people are "doom scrolling" [31:45]-[31:50]; wants 16:9 [33:39]. | v1: 3,000,762 views (A1) and 7,000 downloads (his recall); see step 50. v4: 2.95M views, conversion "horrendously low" [31:23]-[31:30]. v3: 629K, his weakest measured X demo. | Views MEASURED; conversion anecdote. Links: suppression documented in 2023; PPC Land's code analysis found 94% fewer views for link posts; Musk said in 2026-07 there had been no penalty "for over a year" (X1 §2.9). | Use X for reach and as a credential: the reel uses the 2.8M screenshot as proof (R3 I6). Post 16:9. Re-measure conversion yourself. |
| **YouTube** | Best converting "for most companies" [31:54]-[32:00]; "a library that will last for decades" [32:16]. | Dictation: 21,012 views (A1); "like 20" percent downloaded [31:37]. | Anecdote, CONTESTED: 20% would be about 4,200 downloads from 21K views, about 90 times the X ratio, so probably another denominator (X1). The description link is a bare heyclicky.com (R2 §3.7), so the 20% cannot come from a tag in that description (INFERRED). | Upload every feature demo with a tagged description link. Spend real time on titles and thumbnails (step 22). Watch the Intro and Dips reports (step 32). |
| **Instagram** | About 70% of all traffic ("I think") [32:22]; the best audience "by far" [33:13]; most videos are made for it [33:23]. | The 20.9M reel (335K likes). Followers: farza954 87.6K, _heyclicky 35.4K (on screen, R3). The drawing video: 27.4K likes, against 5.1K on X (on screen, R4); its "millions of views" [34:25] is not legible. v2's "4.6 million" [36:50] is not tied to a tile on screen. | Traffic share anecdote; counts on screen only. No slot read Instagram directly (it needs a login, W1). | Make vertical for Instagram first. Tag the bio link (/ig, /farza) and each post. |
| **TikTok** | Business buyers are there too [30:14]-[30:23]. | About 50 design-agency leads from videos averaging about 4,000 views [30:38]-[30:48]. For Tidbit: 3-5 TikToks a day, about 4M views in 7 days, about 0.5% conversion on product-specific posts; meme content "juices algo" but converts "much lower" (W1 S8, S9). | Anecdote; no TikTok shown in the interview. Forrester 2026 puts Facebook, Instagram and YouTube above LinkedIn for business buyers (X1). A lead is not a deal (X1 §2.10). | Niche call-out hooks. Count leads and pipeline, not views. Expect memes to grow reach, not signups. |
| **LinkedIn** | Named among the platforms where users are [02:23]; not discussed for conversion. The host's "default" route [30:00]. | On screen: 15,972 followers; the v2 cross-post at 75,318 impressions; a "$10K MRR ... 9-weeks" milestone post at 50,677 (R4 I-9, I-16). | MEASURED on screen only | Cross-post demos and milestones; measure as for any channel. |
| **Reddit** | The 2020 playbook ("find the right subreddit" [02:02]); a place to post the 30-second selfie [27:41]. | none | Named only | Optional cross-post; unmeasured. |
| **Facebook (paid)** | Runs the 20.9M reel as an ad [21:17]-[21:22]. | none | Anecdote | Turn proven winners into ads. |

### 3.11 The thousand-shots rule, with numbers

54. **Commit to volume, and expect most posts to do little.** "If you don't take a thousand shots, you're not gonna make the five thousandth shot." [20:25] The thousand is a figure of speech. The numbers:

| Number | What it is | Label |
| --- | --- | --- |
| "hundreds and thousands of videos … that nobody has cared about" | His estimate of misses [09:49] | QUOTED, anecdote |
| 1,511 | Photos and videos on his X media tab | MEASURED (R3 I1, R4 I-1) |
| "every day almost" | Class videos at Zip School in 2021; none went viral [19:03]-[19:13] | QUOTED |
| 23 likes, 3 replies, 1 repost, 1 bookmark | The Feb 19, 2021 Zip launch post | MEASURED (R3 I2) |
| about 80 followers | His audience in Dec 2020 [19:50] | QUOTED, not shown |
| 10 likes; 17 likes | The Dec 1, 2020 landing-page post; the Nov 7, 2020 selfie | MEASURED (R3 I3, I4) |
| about 10 | Videos before "you get really good at talking about stuff" [22:28] | QUOTED |
| 15th-30th | The video count at which to start writing first [45:22] | QUOTED |
| 1-2% | Share of people he advises who actually post [27:46] | QUOTED, anecdote |
| 1 of 30 passes about 1,000 views | The 30-day challenge promise [46:22]-[46:24] | QUOTED, untested |
| 7 tiles at 13.6K-29.8K; then 29.3K, 160K, 462K, 1.4M, 2.5M, 4.5M, 20.9M | Views on part of his Instagram grid: 1 of 14 counted tiles is above 5M | MEASURED (R3 I5); the share is INFERRED from a partial grid |
| 294K against 2.9M | Two X posts with the same copy template, six days apart | MEASURED on screen (R1 Insert F) |
| 3-5 TikToks a day; about 4M views in 7 days | Tidbit, 2025 (the product still shut down) | DOCUMENTED, his Substack (W1 S8, S9) |
| Median views 459-506 at every frequency from 1 to 11+ posts a week; 90th percentile rises from 3,722 to 14,401 | Buffer's TikTok study: 11.4M posts from 150K+ accounts | DOCUMENTED (X1 §2.7) |

The outside data says volume buys more chances at a hit while the typical post does not improve, which matches Simonton's equal-odds rule (X1 §2.7). His claim that you also get better [20:15]-[20:25] is plausible but untested.

55. **Review the log every week** (X1 §2.7's advice; his own look-back is the challenge's day-30 review [46:26]-[46:36]). Find the best post of the period, name the device that made it work (hook, first frame, register), and reuse it next. Judge by the best post, not the median.

### 3.12 The stack

56. **Buy only what the register needs. Audio comes first.** Prices are as of 2026-10-24, from K1.

| Role | His tool | Price | Free or cheap path | Notes |
| --- | --- | --- | --- | --- |
| Screen demo | Screen Studio [40:53]; "I think it costs like 30 bucks" [41:03] | $29 a month, or $9 a month billed yearly; v4.0 (MEASURED, K1) | Cap, OpenScreen, OBS; macOS Cmd-Shift-5 has no auto-zoom (K1) | Its auto-zoom and cursor smoothing make the v1 zoom (INFERRED, A1) |
| Native talking video | Phone selfie camera [41:13]; "iPhone or Android, it's okay" [46:02] | The phone you own | Any phone | "Nothing else required" [41:23]-[41:28] |
| Phone edit | Edits, Instagram's editor [41:17]-[41:23] | Free (DOCUMENTED, K1) | CapCut's free tier | Captions and trims on the phone |
| Cinematic | Sony FX3 or FX30 [41:38] | FX3 $4,299.99 list ($3,998 on Amazon, Oct 6); FX30 about $1,800-2,100 (DOCUMENTED, K1) | Phone rear camera; a used mirrorless body | Level 3 only |
| Audio | DJI mic [41:38]; "find them used online" [42:23] | dji.com lists the Mic 3 base SKU at $169, marked out of stock, configuration not established (MEASURED, K1); Mic 3 kit about $249-259 and Mic Mini kit about $79 (DOCUMENTED) | Any external mic | The one non-negotiable [41:46]-[42:27] |
| Laptop edit | DaVinci Resolve [42:32] | Resolve 21 free; Studio $236, down from $295 (MEASURED, K1); the sale reportedly runs to Nov 20 (DOCUMENTED, third parties) | Free Resolve | |
| Writing | FreeWrite, his app [45:01]-[45:08] | Free, MIT license, v1.5 (MEASURED, K1) | Any plain editor with a timer | 15-minute default timer |
| Filmmaker | Vikrant [42:39]-[43:47] | Not discussed | The founder alone, then a contractor | He brings shot and hook ideas; Farza brings "the script and the song and the vibe" [43:26]-[43:28] |

He calls the filmmaker "maybe the most important part of my stack" [42:37]-[42:39]. If you cannot afford one, "go back to my old Zip School videos" and just start [44:03]-[44:25].

57. **Hire creative help when production, not ideas, limits the cadence.** X1 §2.12 gives the trigger: one channel shows tracked conversion, and the cadence is limited by production time. Hire on contract first. He has always had a collaborator (W1): Aiden shot and edited his 2025 YouTube video (S10), the Freewrite launch video is credited to @wordisbonz (S30), Hasan wrote and shot the Tidbit TikToks (S8), and Vikrant makes the HeyClicky videos.

### 3.13 The 30-day launch challenge

For anyone who has never made videos or talked about their work online, but has been building something [45:46]-[45:58]:

58. Every day, spend 10 minutes [46:00].
59. Use your phone, any brand [46:01]-[46:02].
60. Record yourself talking about what you were doing, or what you did that day [46:04]-[46:06].
61. Post it to Instagram or TikTok [46:08]-[46:10]. A new Instagram account is fine, "so your existing followers don't even know" [46:12]-[46:15].
62. Do it "30 days straight, every day, one video" [46:17], [46:40]-[46:41].
63. Find the video that passed about 1,000 views. Ask why, and base the next one on it [46:22]-[46:36]. He offers to like your posts if you send them [46:42]-[46:43]. The challenge's success measure is views; conversion comes later (step 51).
64. **If no video passes 1,000 views** (INFERRED; he does not cover this case): the promise is untested (X1 §2.14). Buffer's established accounts have a median of a few hundred views per post, and a new account may start lower. Rank the 30 by views relative to the account's own median, take the top three, change one thing each time (the hook, the first frame or the platform), and run another 30.

**Run it as a measured experiment** (X1 §2.14, INFERRED):
- log all 30 posts as in step 6;
- reuse the hooks of the top three in the next ten;
- set expectations from the base rate above.

His promise ("I promise you" [46:20]) is not data.

## 4. Measured reference: his launch videos

A1 MEASURED all values on 2026-10-24:
- lengths and counts with ffprobe, and fxtwitter or yt-dlp;
- cuts with a luma-difference detector;
- words with whisper.

The cut detector counts on-screen app switches as cuts and misses Screen Studio zooms, so v2's "cuts" are windows opening, not edits. It also overcounts low-frame-rate archival footage in v5. Follower counts are from W1 §4 (fxtwitter).

**4a. Format**

| Video | Account (X followers) | Posted (PT) | X views | Length | Aspect | Hard cuts per min (median shot) | Cuts in first 10 s | Face on screen | Screen on screen | Captions | Music |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| v1 Clicky launch | @FarzaTV (129,259) | Apr 6, 2026 | 3,000,762 | 99.9 s | 1.54:1 | 1.8 (27.5 s) | 0 | 100% (bubble) | 100% | none | none |
| v2 "no hands" | @FarzaTV | May 30, 2026 | 3,826,653 | 104.1 s | 1.54:1 | 2.9 raw, all app switches; 0 edits (11.5 s) | 0 | 100% (bubble) | 100% | none | only the demo's own Spotify |
| v3 drawing | @FarzaTV | Jun 16, 2026 | 629,293 | 140.4 s | 16:9 | 13.3 (3.4 s) | 2 | 62% (23.6% face only + 38.6% face with laptop) | 35.7% | phrase chunks, about 80% of height | bed, swells at the end |
| v4 dictation | @FarzaTV | Jul 14, 2026 | 2,945,014 (+21,012 YouTube) | 120.1 s | 16:9 | 18.5 (2.2 s) | 2 | 54% | 41.7% (+2.5% keyboard) | phrase chunks, about 81% | bed from about 8 s |
| v5 "hi my name is farza" | @FarzaTV | Sep 8, 2026 | 64,892 | 109.5 s | 9:16 | 45.5 raw, overcounts archival (1.1 s) | 3 | 32% (+47.7% archival) | 20.2% | 1-3 words, about 69% | bed |
| v6 "i went viral" | @heyclicky (15,584) | Apr 29, 2026 | 73,093 | 44.9 s | 9:16 | 52.1 (0.7 s) | 13 | 49% (incl. 7.2% double exposure) | 50.7% | 2-3 words, about 63%, moves | bed |

**4b. Words**

| Video | Hook (first words, time) | "What it is" lands by | Demo starts | Spoken CTA | Link | Post copy |
| --- | --- | --- | --- | --- | --- | --- |
| v1 | "Hey, everyone. So this is Clicky." (0.08-2.36 s) | 2.4 s | 10.4 s (10%) | "I'll put the link below and give it a shot." (97%) | Self-reply +4 h 42 min (clicky.so) | 276 characters |
| v2 | "Alright, check this out, no hands, ready?" (0.20-2.25 s) | 2.3 s | 2.5 s (2%) | none | Self-reply +6 h 54 min (/try) | 151 characters, ends "Demo:" |
| v3 | "Hey, so we built a system that can draw directly on your screen…" (0.23-7.80 s) | 3.5 s | 10.9 s (8%) | "Try to break it." (93%), end card "try it for free" | Self-reply +7 h 46 min (/try) | 279 characters, ends "Demo:" |
| v4 | "Hey, so today we're adding dictation to HeyClicky." (0.04-2.94 s) | 2.9 s | 11 s (9%); reveal at 31 s (26%) | "This is in production right now." (93%), end card "clicky" / "heyclicky" | Self-reply +5 h 40 min (/try) | 280 characters, ends "Demo:" |
| v5 | "I feel like a lot of you guys are new here and I just want to introduce myself" (0.04-2.88 s) | 5.8 s (who he is) | no demo | "Thanks for following" | none | 54 characters, lower-case |
| v6 | "Today we crossed over 5 million views on this thing we're building called Clicky" (0.12-3.56 s) | 3.6 s | 16.1 s (36%) | "go make Clicky do things" | none | 12 characters, lower-case |

**4c. Seen only inside the interview** (partial reads from the YC edit, not full measurements)

| Video | What was measured | Source |
| --- | --- | --- |
| Clicky Instagram reel, "Last week I went super viral…" | 20.9M views on the grid tile; 335K likes; hook about 7-8 s with face for 6 of 8 s; body about 1 cut per second with word-chunk captions; 4-6 hours to make [22:14]-[22:19]. A1 could not find the source. | R3 I5-I7 |
| "everything we built this week" team update | Three speakers in about 22 s, title card, captions, B-roll | R3 I12 |
| "It has been 9 weeks" and "Two weeks ago…" reels | Cuts about every 0.7-1.3 s (3 luma cuts in about 10 s); a real usage chart as proof | R4 I-14, I-15 |
| Zip School class launch, Feb 2021 | Screen recording with a selfie bubble, no captions; 23 likes | R3 I2 |

**4d. Controls not yet measured.** These are lower performers that would test whether the habits in step 29 separate hits from misses. Views were MEASURED unless noted.

| Post | Views | Source |
| --- | --- | --- |
| "Here's the new Clicky" (223 s) | 1,192,157 | A1 |
| "Here's our new landing page + look" (16 s) | 344,065 | A1 |
| Tidbit launch, 2025 | 341,900 | W1 S32 |
| "Today we're shipping spatial context." | 294K (on screen) | R1 Insert F |
| "Introducing collaborators" (168 s) | 201,590 | A1 |
| heyclicky "never touch me again" (vertical, 55 s) | 145,280 | A1 |
| The Oct 2025 cursor-buddy precursor (26.7 s) | 453,200 | W1 S31 |

**What the tables say** (INFERRED from A1):
- The opening is the constant: no intro card, and the thing is named within about 3.6 s in 5 of 6.
- The two biggest X hits are raw single takes, and v4 was nearly as big while fully produced. With four demos, this is a sample-size caveat, not a finding.
- On X, horizontal demos reached far more people. The vertical stories had higher like rates (1.1-2.5% against 0.36-0.83%) and fewer bookmarks per like (0.21-0.22 against 0.52-0.82). Two confounds remain: v6 came from an account with an eighth of the followers, and topics differ.
- The link never goes in the post.

## 5. What an agent can do, and what needs the founder

Step numbers refer to §3. "Agent" means a Claude Code agent with this machine's tools. Their presence was MEASURED:
- ffmpeg with `loudnorm`, `astats`, `silencedetect` and `afftdn` (K1);
- whisper-cli (K1);
- agent-browser, whose `record start` writes WebM (C1);
- auto-editor and the HyperFrames skills (K1).

Remotion's presence was not measured. The agent never posts. Posting, replies and messages to users are the founder's acts, and our harness forbids an agent sending anything outbound.

| Steps | The agent can do | The founder must do |
| --- | --- | --- |
| 1, 11 Tiers, one-shot channels | Propose a calendar from the roadmap and git log; flag releases big enough for a one-shot channel | Choose the tiers; decide what counts as substantive |
| 2 Microphone | Measure each take's noise floor and loudness; reject a take with bad audio before editing; denoise lightly (K1) | Buy and wear a real mic; re-record bad takes (a laptop-mic recording cannot be repaired into a lav, K1) |
| 3 Recorder | Recommend and configure a recorder; record scripted web flows at a fixed window size (agent-browser) | Record native-app and live demos; agent-driven desktop capture is fragile (K1) |
| 4-6 Tags, events, log | Generate per-post links; add link paths, product events and the retention query if the site and app are in a repo; keep the log; read public X counts (fxtwitter) and YouTube counts (yt-dlp) | Grant analytics access; export Instagram and TikTok numbers (no reader exists, and Instagram needs a login, W1); decide what counts as a conversion |
| 7 "Post it anyway" person | Nothing. An agent saying "post it" is not the human push he describes (INFERRED) | Name the person |
| 8-10 Weekly question, daily prompt, team update | Ask the question on a schedule; draft the "what shipped" list from git log and the changelog (K1) | Say which moment made you smile; appear in the update |
| 12 Caption-first check | Draft many caption and hook angles; check the 280-character fit; act as a critic | Judge whether it excites you; pick one |
| 13 Grounding frame | Mock up the frame as a still | Choose it |
| 14-15 "Check this out", deadline | Track the deadline; suggest a smaller angle you can demo today | Notice the moment and record it raw |
| 16 Register | Recommend one from the §3.3 table | Choose it |
| 17-19 Script | Interview the founder by voice, transcribe locally, and turn it into a structure; mark the setup block; time it to length; critique against the reading tests | Write or approve the lines. K1 judges an agent-written script the most likely to sound read, but his Tidbit TikToks used a collaborator's script (W1 S8), so test it (§8 Q10) |
| 20 Off the cuff | Make a rehearsal card with beats only | Rehearse until visualized about 10 times; deliver |
| 21-24 Copy, captions, feed mockup | Draft X copy, Instagram captions and YouTube titles; build a local, static mock of a feed card. The mock is a weaker proxy, since the test's value is the real feed around the post (R2 §3.2) | Judge "did my eye stop?" in your own real feed |
| 25 Mute test | List what the first frames say with no sound | Confirm the read |
| 26 Self-reply | Draft the reply and its caveats | Post it |
| 27-29 First 10 seconds | Measure word times, hard cuts, loudness and caption presence, and flag where they differ from the step-29 table | Read the turn, the demo start and the face/screen share; A1 made these calls by eye, corrected cut counts by hand, and re-ran whisper when it compressed timestamps. Perform the opening |
| 30-40 Formula and story | Map beats onto the formula; mark the turn and reveal; keep the swipe file; list known product flaws from the issue tracker for step 38 | Pacing and taste; the bounce test is a human reaction |
| 41 Record | Record deterministic web flows; trim dead air (auto-editor); add zooms in post with HyperFrames (a custom job each time, K1); crop to 9:16 | Be on camera; narrate live; shoot Level 3 |
| 42-45 Edit, length, CTA, platform | Rough cut from the transcript; phrase captions through HyperFrames (this machine's ffmpeg has no `drawtext`, `subtitles` or `ass` filter, MEASURED K1); loudness; per-platform exports | Final pacing, music, when not to cut (K1: taste is "not delegable") |
| 46 Pre-post checks | Contact-sheet every shot for IDs, keys, emails, names and revenue; record each track's license | Decide what may be shown; clear the music; show it to one person |
| 47-49 Post and thread | Package files, copy, captions and replies per platform; draft answers to thread questions | Press post; answer the thread |
| 50-53 Measure, niche, reuse | Compute conversion per channel from tags and product events; draft messages to retained users (outbound-drafting skill); propose ad, landing-page and README reuse | Talk to every retained user yourself; approve reuse |
| 54-55 Volume review | Weekly: top post, its device, what to try next | Decide what to make next |
| 56-57 Stack, hiring | Check prices; flag when production time, not ideas, limits the cadence | Buy; hire |
| 58-64 Challenge | Daily reminder, log, captions, day-30 review | Record and post every day |

The agent can take most of the work around the founder: planning, measurement, editing, versions and the log. The founder keeps what the method rests on. That means noticing the moment, being on camera in their own words, judging whether their own eye stops, talking to users and pressing post.

## 6. Boundary with our launch-film and demo-recording skills

**What each one is.** His quarterly "polished launch" is "something I'm really proud of" [15:57]-[16:02], made with a filmmaker whose job covers "shooting to picking the set to editing" [43:41]-[43:47]. It is the produced register of this method at higher effort. It is not launch-film, which rules out "a human shoot or studio" (launch-film §0.11).

| | launch-film | demo-recording | This method |
| --- | --- | --- | --- |
| Unit | One high-craft film with sound: a README hero or a product's first public face | A silent animated WebP of a screen, terminal or agent flow for a README | Many small demo posts, plus a produced quarterly launch |
| Cadence | Per product, or per major release | Per README change | Daily to weekly, a weekly or biweekly team update, quarterly polish |
| Who is on screen | Nobody real. A human shoot, stock footage with type over it and generated video as the base are ruled out (§0.11) | The product's own screen | The founder's face and voice, and the real product |
| Medium | Code-built 2D (web) or path-traced 3D | Captured window, near-lossless WebP or GIF | Screen recordings, phone selfies, camera footage |
| Approval | One operator yes at story, look (then each element), board, motion, sound (a mix pick) and the final film. The stills check is internal, with no operator question unless the look changed (§4). README is a measured check (§9) | Its own gates: pane parity, contact sheet with no leaked content, streak metric, scratch-branch verify | No gates beyond the founder's own stop and mute tests and step 46 |
| Time | Days to weeks. One 2026-10 film had a 70.6 h look stage and an 81.4 h final render (§2, §10) | Not measured here | Minutes to hours. v1 was posted about 13 min after the take (A1) |
| Truth rule | Every on-screen number measured under a written rule (§1.6) | No leaked content | His practice is mostly honest caveats (P20); this method adopts launch-film's rule |
| Success | The operator's yes, and a hero that lasts | The README renders and animates | Downloads, retention and conversion per channel |
| Where it lives | README hero (a GitHub attachment video), project `BRIEF.md` and `STATUS.md` | README body | Social channels, the post log, optionally a demos or changelog section |

**When to use which.**
- **Use launch-film** for a README hero with sound or a product's first public face on GitHub. Use it when no founder will be on camera, or when the piece must stand unchanged for months.
- **Use demo-recording** for a silent loop of a flow in a README, below the hero.
- **Use this method** for every shipped feature and every "check this out" moment, every social feed, and learning which message and channel convert. His quarterly polished launch also belongs here, in the produced register.
- **One-shot channels** (Launch HN, Product Hunt): one rule, as in step 11. Spend them on substantive releases. Each takes whatever finished asset the release has, the produced demo or a launch-film hero. The copy follows each channel's rules, and the caption-first check (step 12) helps write it.

**How they coexist for one product** (INFERRED; nothing in the sources tests this):
1. **Demos first, film later.** The demo cadence finds the message: which hook stopped people, which use case kept users. The film's story gate (launch-film §1) takes its value points and "most impressive true claim" from the post log.
2. **Separate outputs.** The film owns the README hero slot and its project files. demo-recording owns silent loops below it. Demos live on the channels and in the post log. No demo replaces the hero URL or writes to the film's `BRIEF.md` or `STATUS.md`. A raw screen take may be re-cut into a silent README loop through demo-recording, never into the hero.
3. **Separate looks.** Demos stay raw and never wear the film's look. The film never cuts in demo footage: launch-film rules out human footage and wants real UI "translated into the film's material, never pasted in" (§1.6). The film borrows claims from demos, never pictures.
4. **One claims ledger.** A number appears in either only if measured under a written rule. The film carries claims that stay true; fast-moving numbers (views, customers) belong in demos, which date themselves.
5. **One one-line description.** The product's one-line value proposition is the same in the film and in the demos' "what it is" line. Change it in one place, on purpose.
6. **One music rule.** No music without a documented license, in either (launch-film's "Do NOT" list; step 46).
7. **Nobody waits, and approvals do not transfer.** Demos keep running through the film's gates. When the film ships, post it like any demo: copy in his order (step 21), the feed test (step 23), and a tagged link (step 4). A demo doing well is not a film gate's yes, and a film yes does not approve demo copy.

## 7. Evidence and caveats

### 7.1 Survivorship and an audience built over a decade

- **Mostly hits are shown.** The interview's examples are hits: 3.0M, 2.95M, 3.83M and 20.9M views. It also shows the Zip School misses (10-23 likes) and the 294K spatial-context post. He says so himself: "we're looking at the stuff that's working but so much hasn't worked" [35:23]. The "thousands of videos" nobody cared about [09:49] are not shown. The habits in step 29 come only from hits, and the same copy template gave 2.9M and 294K (§4d).
- **He has built distribution for years** (MEASURED, W1 and R3):
  - @FarzaTV: 129,259 X followers (fxtwitter);
  - @heyclicky: 15,584 X followers;
  - farza954: 87.6K Instagram followers, on screen;
  - _heyclicky: 35.4K Instagram followers, on screen;
  - the farzatv YouTube channel: 13.6K subscribers;
  - the Buildspace audience, and "10 plus years" of posting [06:33].

  INFERRED: "say hi and post" works partly because he already had reach. Instagram is his 70% channel, and his own account there is the larger one.
- **Hits are irregular, even for him.** "No one sees 2025" (W1 S19), and the Tidbit launch got 342K views before the product shut down (W1).
- **His own hit prediction is weak.** He says "we kind of know it's a hit before we even start" [04:28] and "I just knew … when I wrote the script" [21:03]. Yet he called the Clicky demo "not that good" [06:16] and the dictation video "the worst video we've ever done" [14:26]. "Post anyway" holds up because of the volume data (Buffer's fat tail, Simonton; X1 §2.7), not because of his two surprise hits.

### 7.2 "Scrappy" is partly produced

- **His filmmaker made the videos.** "Every video we just looked at, apart from the bad Zip School ones, which were made by me, are made by Vikrant." [42:51]-[42:53] At one point the company had three people making videos and one engineer [39:59]-[40:04]. He has had a video collaborator for as long as his recent record runs: Aiden (W1 S10), @wordisbonz (S30), Hasan (S8), then Vikrant. He has not worked alone at scale.
- **The truly solo examples did little.** In the interview, the only founder-alone videos are the Zip School ones, which got 10-23 likes, and the challenge.
- **v1 and v2 sit oddly beside "made by Vikrant".** Both look like unedited Screen Studio takes (A1, INFERRED).
- **Production level did not predict views, in four videos.** A raw take and a produced cut each reached about 3M on X (A1, n=4). That is a sample-size caveat, not a finding.
- **Who is on camera is not fully established.** A comment on the drawing reel says "Well done Zain" (MEASURED, R4 I-8), and the reels carry several collaborator avatars. A1 did not identify the presenters.

### 7.3 Numbers that are his anecdotes

| Claim | Where | Status |
| --- | --- | --- |
| 7,000 downloads after the Clicky launch | [07:18], [31:13] | His recollection ("I think"); no public source (W1); attribution confounded (step 50) |
| About 100 retained daily for five days | [07:27]-[07:30] | Anecdote. The window is stated two ways: "four days later" [07:19] and "five days straight" [07:30] |
| About 20% conversion on YouTube | [31:37] | Anecdote; implausible as views to downloads (X1) |
| About 70% of traffic from Instagram | [32:22] | Anecdote, hedged with "I think" |
| About 50 leads from TikToks averaging about 4,000 views | [30:38]-[30:48] | Anecdote; leads, not deals |
| Three design agencies "found us naturally" | [29:48] | Anecdote |
| "One of our highest converting videos" | [12:12] | No figure given |
| A new-feature video makes "thousands of people flood my app" | [40:39] | Anecdote, no figure |
| A selfie video beats a $20,000 produced video | [03:11] | Hypothetical, hedged with "probably" |
| The team update has "almost a million views" on Instagram | [25:22] (host) | Not shown; the YouTube copies have 913-1,900 (C1) |
| v2 got "4.6 million" on Instagram | [36:50] | A 4.6M tile is visible, but not tied to this reel on screen (R4 I-13) |
| The drawing video has "millions of views" on Instagram | [34:25] | Not legible; 27.4K likes on screen |
| A produced video takes him "like an hour"; the reel took 4-6 hours; the team update takes 10 minutes | [20:50]-[20:55], [22:14]-[22:19], [26:30]-[26:36] | Anecdote; the update's edit is visibly more than 10 minutes (R3) |
| The YouTube channel was three days old when the dictation video went up | [12:07] | Contradicted by upload dates (C1) |
| 1-2% of people he advises actually post | [27:46] | Anecdote |
| One of 30 videos will pass about 1,000 views | [46:22]-[46:24] | A promise |
| 2,200 customers, about $1M ARR, about 40M views in 30 days | W1 S18 (vlog, 2026-10-20) | His claims, unverified |

**Confirmed by measurement** (A1, read on 2026-10-24):
- launch post: 3,000,762 views ("nearly 3 million" [06:58]);
- dictation on X: 2,945,014 views ("3 million views on Twitter" [12:16], [14:42]);
- dictation on YouTube: 21,012 views ("20,000" [12:16]);
- no-hands demo: 3,826,653 views ("3.8 million" [36:50]).

This settles R2's suspicion that the dictation "3 million" mixed up two videos. The "21 million" Instagram figure shows as 20.9M on screen (R3).

### 7.4 Where outside evidence disagrees or sets limits (X1 unless noted)

- **"Old media is gone" [03:08].** YC's 2019 view was that press, Product Hunt and HN launches were "starting to even out", not that press had stopped working. The NYT story in YC's own cold open describes startups spending big on hype videos in 2026, including an "US$80,000 video shoot" (R1 Insert A; reported in a search summary of a reprint, page not opened).
- **Cheap beats expensive.** In Wistia's 2018 test the $10K ad beat both the $1K and the $100K one. Polish raised perceived expertise but not trust (Johnson et al. 2021). The lesson is story over budget, not that the cheapest wins.
- **Volume.** Buffer's medians stay flat as frequency rises. Volume buys a fatter tail; the skill gain is untested.
- **X conversion.** Link suppression was documented in 2023, and a code analysis found 94% fewer views for link posts. Musk said in 2026-07 that the penalty had been gone for over a year. His decade of poor X conversion may not hold now.
- **Business buyers.** A TikTok lead is not a deal. 6sense, an interested vendor, reports buying groups of about 11 people and cycles of about 11 months.
- **Showing the process.** Copying is real: Clicky has 1,552 forks, a port appeared within 18 hours (W1 S27), and he moved new work to closed source on 2026-04-27. Don't show metrics or architecture a clone could use (X1 §2.3), which v2's live Stripe dashboard did.
- **Audio first.** Corroborated (Newman & Schwarz 2018), but much feed video plays muted (up to 85% of Facebook views in publishers' 2016 reports). Captions and the mute test matter as much.
- **Scripting.** No study compares scripted and unscripted founder videos. Rifkin & Du (2023, entertainment performers) found that spontaneity reads as authentic, and that people expect spontaneous work to be lower quality.
- **Hiring a filmmaker first.** Untested. Buildspace, with a 2-of-7 film team [39:55]-[39:59], is listed "Inactive" on YC (MEASURED, X1). It closed by his choice with over two years of cash (W1 S22).
- **Over-posting.** Too many promotional posts is a top reason people unfollow brands (Sprout Social 2016, 2019).

### 7.5 Tensions inside his own account

| Tension | Resolution for this method |
| --- | --- |
| "This whole video scripted" [14:00] vs the Clicky launch was "almost entirely unplanned" [10:00] | Two registers: a raw same-session take for a fresh moment, a script for produced feature videos (steps 16-17) |
| Script "three days before" [14:00] vs "I wrote the script in 30-minutes" (W1 S10) | Script time varies with the video; step 17 gives the range |
| Farza brings "the script" [43:26] vs "Hasan ... gives me a script" (W1 S8) | Who writes depends on the collaborator; test agent drafts (§8 Q10) |
| "Five minutes before dinner" [06:40] vs "sitting on the Clicky demo for a few weeks" (W1 S3) and "tabled it for another two weeks" (W1 S19) | Recording took minutes; deciding to post took weeks. Plan for the hesitation (step 7) |
| Setup is "10, 20%" of "one minute" [11:19]-[11:31] vs videos of 100-140 s whose problem or turn lands at 10-43% (A1) | The 10-second rule holds for the "what"; the turn varies (step 18) |
| "By the time I hit post, I've already forgotten it" [17:05] vs self-replies 4.7-7.8 h later and fixes announced two days later (A1) | Walk away from the counter, not the thread (steps 48-49) |
| "I don't want to put a ton of attention every day on making videos" [39:22] vs the daily challenge [46:00] | Daily in the early days; delegate later (step 57) |
| "There's not a single cut" on Instagram [37:02] vs the fast-cut reels he shows next [37:53] | Both registers exist; do not read the no-cut claim as a rule |
| "This is super optimized for twitter" [33:50] vs it did "even better" on Instagram [34:17] | Optimizing for a platform did not predict where it performed (step 25) |
| "There's no hook" for the team update [25:12] vs "my formula is always the same" [21:51] | Updates for existing users skip the formula; acquisition videos use it |
| "The goal … is never to go viral" [30:48] vs examples chosen by view count, and a challenge judged by views [46:22] | Views pick examples and next tries; conversion judges channels (step 51) |
| "What's really hard to clone is the audience" [40:22] vs "distribution is nothing without like a good product" (W1 S17) | Product first; the audience compounds on top of it |
| In 2025, telling a story about what he was building felt wrong on Reels (W1 S8) vs Instagram as by far the best channel in 2026 [33:13] | INFERRED: the story works once there is a demo a stranger can understand on mute (W1 S27) |
| "I'm good at … writing stories" [19:23] vs 2024: "I am not naturally a guy that can tell great stories" (W1 S12) | The skill came from practice; do not make "be a natural storyteller" a prerequisite |
| "Show your face very clearly" [12:36] vs the face appears only as a bubble in his two biggest hits (A1) | For screen-led demos, a face bubble is enough |
| "Any mic that's not your MacBook mic or your AirPod mics" [42:24] vs white earbuds in v2's bubble (R4 §3) | Unresolved: which mic recorded v1 and v2 is unknown (P15) |

### 7.6 Untested practices

The following appear nowhere outside the interview (W1; an absence in the sources read is not proof):
- the feed-mockup test;
- the 10-20% setup ratio;
- the audio rule's ranking above picture;
- the gear list;
- the 30-day challenge.

The self-reply link timing is a measured habit (A1) whose effect nobody has tested. The same goes for the one-person gate, the redaction and music checks and the channel decision rule (steps 46, 51), which are this study's additions.

## 8. Open questions for turning this into a skill (stage 2)

1. **Who is on camera?** The operator's products are mostly developer tools. Will he be on camera, voice-only, or neither? Voice-only maps to the raw screen take (v1, v2). Neither means this method does not apply, and launch-film covers the alternative.
2. **Scope.** Is this a new skill beside launch-film and demo-recording (working name `demo-launch`) with a shared claims ledger, or a pointer inside one of them? Where does the post log live: in each product repo, or a private directory?
3. **The outbound line.** The skill stops at a ready-to-post package (files, copy, self-reply, captions). Do messages to retained users go through the outbound-drafting skill?
4. **The feed-mockup test.** Does a static local mock serve, or must it be the founder's real feed? A text swap in his logged-in X session through agent-browser is local-only, but the session is his.
5. **Captions.** This machine's ffmpeg has no `drawtext`, `subtitles` or `ass` filter (K1). Standardize on HyperFrames (Remotion's presence is unmeasured), or install a full ffmpeg build?
6. **A first-10-seconds check.** Which parts of step 29 become a script (word times, cuts, loudness), and which stay human reads (turn, demo start, face share)?
7. **Controls before thresholds.** Before any habit in step 29 becomes a rule, measure the §4d lower performers with A1's method. Do the habits separate the 3M posts from the 145-450K ones?
8. **Unmeasured anchors.** Can the 20.9M reel and the agent-interface video made from the shown script be found and measured? Can the founder export Instagram and TikTok numbers, since no slot read either?
9. **Agent-recorded demos.** Can an agent record a CLI or web take that still reads as "hacking on this right now" rather than a product tour (K1)?
10. **Script authorship.** How much can the agent draft before delivery sounds read? Test it: the founder records one beat from an agent draft and one in his own words.
11. **Conversion for an open-source tool.** Stars, installs, issues or signups? What tagged path stands in for `/ig` when the destination is a GitHub repo?
12. **Validate before codifying.** Should stage 2 start with a pre-registered four-week cadence, or the 30-day challenge, before fixing thresholds? What is the real weekly time cost against the §3.1 estimate?
13. **Formats.** Which of the eight registers in §3.3 belong in version one?
14. **Link timing.** Copy the 4-8 h self-reply habit, or A/B it, given that X's link treatment may have changed?
15. **Music.** Which license sources does the skill accept: platform-licensed in-app audio, a paid library, or original music only?

## 9. Review log

C1 reviewed S0's draft in 97 verdict rows and checked 167 quoted timestamps. Verdict counts, by each row's leading verdict (MEASURED, `python3 -I /tmp/farza-S1/tally.py` on C1):

| Verdict | Rows |
| --- | --- |
| OVERSTATED (3 of them for an overstated label) | 40 |
| SUPPORTED (8 needing no change; 15 still asking for a fix, such as a dropped caveat) | 23 |
| CONTRADICTED | 14 |
| MISATTRIBUTED | 5 |
| UNSUPPORTED | 4 |
| MISQUOTED | 2 |
| MISAPPLIED | 2 |
| ARITHMETIC | 1 |
| Omission, incomplete, or a tension dropped or unresolved | 6 |
| MIS-TIMESTAMPED | 0 (161 of 167 exact; 6 cite the sentence start) |

**Main corrections:**
- **Boundary (§6, steps 1, 11).** The quarterly polished launch is this method's produced register, not launch-film, which bans a human shoot. Launch HN and Product Hunt follow one rule. demo-recording is added. "Stills" is not an operator gate (launch-film §4), which departs from the brief's wording; the skill file wins.
- **Contradicted by his own behavior.** "Never by views" is gone from the summary, and a thread step (49) answers "forgotten by the time I hit post".
- **Survivor habits.** Step 29 reports per video. "Turn by 25%" is dropped, and "key detail moving by 3 s" is limited to screen takes. The 2.9M-against-294K control and unmeasured lower performers (§4d) are added.
- **Confounds and measurement.** The @heyclicky account confound is in P17 and §4a. Posts are tagged and product events added (steps 4-5). The 0.23% is a ratio of unlike numbers.
- **Facts.** Channel age, title periods, 14-28 s, the 30-second selfie, the call-out never shown, the Vikrant tile, the mute-test wording, v2's 151 characters, the end card, the music dip, and the mic and Resolve labels.
- **Grades and attribution.** P4-P8, P10, P12, P15, P17 and P19 are regraded. Steps 12, 13 and 15 are credited to W1, and steps 11, 24, 30 and 55 are marked as X1's or the synthesis's advice. §5's agent claims are narrowed.
- **Added (C1 P2).** Instagram and YouTube copy, the one-person gate, niche discovery, reuse, three registers, length, redaction and music checks, a channel decision rule, a hiring trigger, the no-1,000-views case, a time budget, and Reddit and LinkedIn rows.

**Departures from C1, after checking the primary source:**
- **Row 59.** Three re-transcriptions read "I recommended", not "it". The recommendation was still Clicky's, so the line becomes step 38 and P20.
- **Row 2.** The tile confirms the spelling; that it names the filmmaker is INFERRED.
- **Row 7.** P4 is Anecdote, but the phrase occurs in raw takes as well as scripted ones.
- **Not done.** Measuring lower performers (C1 P0 item 3) is new fieldwork; see §8 Q7.
