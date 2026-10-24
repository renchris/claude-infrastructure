<!-- markdownlint-configure-file { "MD013": false } -->

# Farza's launch-video method: METHOD draft v1 (2026-10-24)

## 1. About this document

**What this is.** A step-by-step method for frequent, founder-led demo launches. It is distilled from Farza Majeed's YC interview, then checked three ways: against his own launch videos measured frame by frame, against what he has said elsewhere, and against outside evidence. This is the stage-1 research deliverable. Stage 2 turns it into a skill (§8). Slot S0 wrote this draft for review.

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
| launch-film | `skills/launch-film/SKILL.md` | Our cinematic film process, for the boundary in §6 |

**Labels.**

- **QUOTED** means his words, or the host's where marked "(host)", with `[mm:ss]`, at most one sentence. I checked every cited time against the transcript in this run. Capitals are restored and known mishearings fixed (heyclicky, Buildspace, Y Combinator, DaVinci Resolve). "Vikrant" is the ASR spelling, unverified. Speakers are INFERRED from content and shot, since the ASR has no speaker labels.
- **MEASURED** means a slot in this study saw or ran it; the slot is named, for example "(MEASURED, A1)", and its file names the command. In this run I also re-read the on-screen script at full resolution (`/tmp/farza-S0/f-666.jpg`); it matches R2 §3.5 word for word.
- **DOCUMENTED** means a source states it; the URL is in the slot file.
- **INFERRED** means reasoning, including arithmetic.

**Summary of the approach.** Farza treats a launch as a small, frequent, public demo of something new, not a single event. "What are we launching this week?" is the planning question, and the post's caption and hook are drafted before the feature is built. When something works, he notices the moment he would say "check this out" to a teammate and records it. Videos open on the thing itself within two to three seconds, on a first frame the target audience recognizes, and each demo is told as a mini story with a turn. He posts everywhere, walks away, and judges a post by downloads, retention and conversion per channel, never by views. Volume does the rest, because even he cannot predict his hits. His own videos bear out the opening rules: he names the thing by 2.3-3.6 s in five of six, and none has a title card. Production level, though, ranges from one raw take to 52 cuts a minute and did not predict views. The main caveats (§7) are that the examples are survivors from a large existing audience, that a full-time filmmaker made most of them, and that his conversion figures are unshown anecdotes.

## 2. Principles

Evidence grades:
- **Anecdote**: Farza's own account only.
- **Measured (A1)**: visible in his own measured videos.
- **Corroborated (X1)**: outside evidence supports it.
- **Contested**: his own statements, his practice, or outside evidence conflict.

A principle can carry more than one grade.

| # | Principle | Source | Grade | Why that grade |
| --- | --- | --- | --- | --- |
| P1 | Launch constantly. A launch is anything new you show in public, so call it a demo. | [02:31], [03:48], [18:49], [28:56] | Corroborated (X1) | YC's "How to Launch (Again and Again)" (2019) and Buffer's 2025 frequency data agree. Limit: Launch HN and Product Hunt are one-shot channels. |
| P2 | Launch to get users through a channel you can repeat, not for clout. | [05:50]-[05:56] | Corroborated (X1) | Paul Graham (2009): a launch is "a pretext for engaging users". Buildspace's own YC profile calls its 2023 reach "very one-off" (W1 S24). |
| P3 | Work backwards: write the caption and the hook before you build the feature. | [03:59]-[04:32] | Anecdote; partly corroborated (X1) | Same idea as Amazon's Working Backwards, but no outcome data. He has done it since at least 2025 (W1 S7, S14). |
| P4 | Watch for the "check this out" moment; that raw register is how to show up online. | [15:31]-[15:48] | Anecdote; Measured (A1) | "Check this out" appears in v1 at 9.6 s, opens v2, sits at v4's reveal (31 s), and is a line in the on-screen script. |
| P5 | Show the process, not the polished ending. | [05:02], [25:27]-[26:09] | Anecdote; partly corroborated (X1) | Glossier's and Stripe's relaunch cadence supports it. Copying risk is documented (Cory Zue 2022; Clicky has 1,552 forks). |
| P6 | The number-one rule: would I stop, and would I read the first sentence? | [08:50]-[09:10] | Corroborated in direction (X1) | TikTok and Facebook ad data link a key message in the first 3 s to performance. The data is correlational. |
| P7 | Pick the first frame for the target audience. Make the key detail visible and moving within 3 s. | [09:11]-[09:42] | Measured (A1) | v1's frame 0 is Xcode, and it zooms onto the cursor buddy at 2.2 s. |
| P8 | The first 10 s cover what you're doing, why it matters, and "let's get into it". Setup is 10-20% of runtime. | [11:04]-[11:31] | Measured, partly (A1) | The "what" lands by 2.3-3.6 s and the demo starts at 8-10%. The "why" (the turn) often comes at 18-26%. |
| P9 | Script the video, then rehearse until it sounds unscripted. | [10:13] (host), [13:59]-[14:16] | Contested | The Clicky launch itself (3.0M views) was "almost entirely unplanned" [10:00]. He tells first-timers not to script [45:20]. No outside study tests it. |
| P10 | The formula: who I am, what's going on, what I'm working on, let me show you. | [21:51]-[21:56] | Measured, partly (A1) | v6 and the 20.9M Instagram reel follow it. The four launch demos (v1-v4) skip "who I am". |
| P11 | A video converts when the hook is super clear and it is clear why to care right now. Check where you bounce. | [22:34]-[22:48] | Anecdote | No conversion data is tied to it. |
| P12 | A demo is a mini story with beats and a turn. Keep the story moving; don't chase attention. | [24:04] (host), [37:06] (host), [37:31]-[37:36] | Measured (A1); partly corroborated (X1) | Every measured demo has a turn, and the problem is always stated as his own. TikTok (2020) and Wistia (2018) both put story above polish. |
| P13 | Show your face clearly, and talk to the one person who would find it cool. | [12:30]-[12:52] | Measured, partly (A1) | His face is on screen 100% of the time in the raw takes, but only as a bubble. In the edited videos it is 32-62%. |
| P14 | Take a thousand shots. Post what you think is bad; zero views is fine. | [20:25], [16:56], [14:38] | Corroborated for hit rate, contested for skill (X1) | Buffer: posting more grows the tail, but median views stay flat. |
| P15 | Audio quality is the most important thing in any video. | [41:46]-[42:27] | Corroborated (X1) | Newman & Schwarz (2018). Limit: much feed video plays muted. |
| P16 | Every channel converts differently, so measure conversion per channel. | [31:03]-[33:18] | Anecdote; his numbers contested (X1) | "Like 20" percent on YouTube is implausible as a views-to-downloads rate. |
| P17 | Make each video for one primary platform, then cross-post. X wants 16:9. | [33:23]-[33:39] | Measured (A1) | Horizontal X posts reached 0.63-3.83M views and vertical ones 65-73K. Topic is a confound. |
| P18 | Be cringe first: start before you are good. | [28:12]-[28:28], [44:56] | Anecdote | He gives the same advice in his 2026-01 Substack (W1 S11), so it is a stable belief. |
| P19 | Hire a filmmaker early. The founder keeps the script, the song and the vibe. | [39:05]-[39:10], [43:26]-[43:47] | Contested (X1) | Untested. Buildspace had a 2-of-7 film team and is now listed "Inactive" on YC. |

## 3. The procedure

Steps are numbered across the whole section so that §5 can refer to them. Each step names who does it only where it matters. §5 gives the full founder/agent split.

### 3.0 Set up once

1. **Write down your tiers.** These are the defaults, from his practice:
   - a demo whenever something new works, ideally several a week ("demos every single day almost" [16:06]);
   - a team "everything we built" update every two weeks [26:51];
   - a polished launch about once a quarter [15:57];
   - optionally, a one-line teaser with a short clip the day before a release, then a livestream on the day (W1 S5).

   The quarterly tier is where our launch-film skill fits (§6).
2. **Get a real microphone first.** Any external mic will do, and a used cheap DJI is fine. Laptop and AirPods mics "don't count" [41:46]-[42:27].
3. **Install a screen recorder that smooths the cursor and zooms.** He uses Screen Studio [40:53]. §3.12 lists free alternatives.
4. **Set up tracking per channel.** Give each platform its own link path: heyclicky.com/ig is the Instagram bio link [32:47], and heyclicky.com/x is on the @heyclicky X profile (MEASURED, A1). For a desktop app, give mobile visitors a "send it to yourself" button and track its click rate [32:58].
5. **Start a post log.** One row per post:
   - date and platform;
   - register (§3.3);
   - hook line and first frame;
   - length;
   - views, link clicks, signups or downloads;
   - day-5 retention.

   The 30-day challenge's "look back at the one that did 1,000 views" [46:26]-[46:36] assumes such a log (INFERRED).
6. **Name your "post it anyway" person.** This is a partner, teammate or editor who overrules your sense that it is bad:
   - Aaron got him to post the Clicky demo [06:19]-[06:29];
   - Vikrant overruled "the worst video we've ever done" [14:26]-[14:33].

### 3.1 Launch cadence

7. **Every week, ask "what are we launching this week?"** and work backwards from that launch [03:55]-[03:59]. A launch is "we did something new at the company, we talk about it" [18:49]. If more than one person might see it, post it [18:54].
8. **Every day, take 10 minutes.** Ask what you did today that made you smile or was interesting. Talk about it, show it, post it, close the app, and go back to work [28:44]-[28:56].
9. **Every two weeks, record the team update.** Prompt each person with "what are you doing today?" and keep the effort to about 10 minutes [26:30]-[26:36]. It started as accountability: "kind of like stand up right but in front of the world" [26:48]. There is "no hook there's no attention there's no story" [25:12]-[25:18], and you are aiming at existing users ("our users have been loving it" [24:41]). Measured shape (R3 I12):
   - three speakers in about 22 s, each giving one line about one shipped change;
   - a group shot outdoors;
   - B-roll over each line, one big title card, and captions throughout.
10. **Save one-shot channels for the quarterly tier.** YC gives each company one Launch HN, and Product Hunt expects about six months between launches (DOCUMENTED, X1 §2.1). Spend them on substantive releases. His own split is daily demos plus a polished launch "maybe once a quarter" [15:57].

### 3.2 Demo-driven development: build the demo moment first

The host names this "demo-driven development": work backwards from the demo you want at the end [15:14] (host). Farza's version is about the moment, not the artifact.

11. **At feature kickoff, before building, write the caption and the hook.** He asks "what's the copy on the Instagram caption?" [04:08] and "what's the hook if we make this a video?" [04:11]. If it does not "sound good on paper", rethink the feature or its angle [04:28]-[04:32]. Elsewhere he treats this as a build gate:
    - draft many tweets, each angling the idea a different way (W1 S7);
    - "If I can't really explain it in 280 characters, then it's probably too complicated" (W1 S14).
12. **Pick one grounding frame.** This is the single image the video exists to show (W1 S7, an idea he took from Miyazaki). For Clicky it was a small blue cursor popping in and saying hi. It becomes the first-frame design in §3.6.
13. **Build toward the "check this out" moment.** That is the moment you turn to a teammate or co-founder and say it [15:31]-[15:43]. That raw "check this out" is how to present yourself online [15:43]-[15:48]. When it first works, record it, and do not stop to check whether someone did it first [36:25]-[36:31]. Show your own first real use [36:36]-[36:42].
14. **Set a same-day posting deadline.** If the full feature is not working by then, cut to an angle you can demo today (W1 S7, where a feature failed at 5 PM and he posted a smaller angle that evening).

### 3.3 Pick the register

His videos fall into five registers. A1 measured the first three on his own posts. The other two are seen only inside the interview.

| Register | What it looks like (measured) | Examples | Effort | Use it when |
| --- | --- | --- | --- | --- |
| **Raw screen take** | One continuous screen recording with a webcam bubble the whole time. 0-3 edits, no captions, no music. | v1 Clicky launch (3.00M X views), v2 "no hands" (3.83M) (MEASURED, A1) | One take. v1 went up about 13 min after the take ended (A1; the timezone is INFERRED). | A fresh "check this out" moment that is visible on screen. Tool or developer audience. X. |
| **Produced feature demo** | Founder in a real place, product close-ups, full-screen recordings. 13-19 cuts a minute, phrase captions, a music bed, an end card. | v3 drawing (0.63M), v4 dictation (2.95M X; 21K YouTube) (A1) | Every line scripted three days ahead [14:00]-[14:05]. Produced by his filmmaker [42:51]-[42:53]. | A named feature that needs a turn to explain. YouTube library, X, Instagram. |
| **Vertical story** | 9:16, 45-52 cuts a minute, 1-3 word captions, proof screenshots or archival footage, music. | v5 "hi my name is farza" (65K X), v6 "i went viral" (73K X) (A1); the 20.9M Instagram reel (R3 I6) | 4-6 hours for the 20.9M reel [22:14]-[22:19] | Instagram and TikTok. Milestones, origin story, "what's going on". |
| **Team update** | See step 9. | "everything we built this week" (R3 I12) | "10 minutes" [26:30]-[26:36], though the edit is clearly more (R3, INFERRED) | Every two weeks, for existing users. |
| **Niche call-out** | Opens by naming the viewer's role. | Design-agency TikToks, about 4,000 views each and about 50 leads [30:33]-[30:43] | Low | A B2B niche on consumer feeds. |

The minimum version of any register is a selfie: "hi, this is what I'm working on, check this out", then turn the camera to show the screen [22:19]-[22:24]. The challenge version is 30 seconds in selfie mode [27:30]-[27:37].

15. **Choose one register per video.** Default to the raw screen take while the moment is fresh. Note that v1, the Clicky launch itself, was "almost entirely unplanned" [10:00].

### 3.4 Script

16. **Decide how much to script, by experience and register.**
    - First videos: do not worry about writing [45:20].
    - From about the 15th to 30th video: write for 10 minutes about what the video should be, then record [45:22]-[45:29]. Writing first lets you "catch a bad idea" before the camera [45:36].
    - A produced acquisition video: write every line, about three days ahead [14:00]-[14:05].

    Write in a plain, distraction-free editor. He uses FreeWrite, his own free app [45:01]-[45:08]. The order is script first, then visuals [11:56] (host).

**The script he showed** (MEASURED, R2 §3.5 and this run's frame at 666 s). It is for a video he recorded "yesterday" [10:37]. The top line is clipped by the frame (plausibly "Hi,"), and the page is cut off at the bottom. Typos are his.

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

The setup (beats 1-2) is about 75 of the roughly 260 visible words (ESTIMATED by line count, R2).

17. **Mark the setup block.** The opening should say what you're doing and why it matters, then "let's get into it" [11:13]-[11:16]. Keep it to "like 10, 20%" of the runtime [11:27]-[11:31], by analogy to a film's first 20 minutes. He says "both these videos are one minute long" [11:19], but the videos actually shown run 100-140 s (MEASURED, A1). So budget the setup as a share of the real length: 10-28 s for 140 s (arithmetic).
18. **Run his three reading tests.**
    - "If I like reading it, then that means it'll probably sound good if I say it out loud as well." [10:30] He adds "not always".
    - "Would I read this if someone texted this to me?" [10:45]
    - "For me, it's always I'm the audience." [10:54]
19. **Make it sound off the cuff.** This is the part people find surprising, since he "seem[s] like you're just talking off the cuff" [10:19] (host). What he does:
    - **Write for the ear.** The script uses spoken forms ("kinda", "sick", "gotta", "That'd be sick"), short sentences and exclamation marks (MEASURED, the script above).
    - **Frame the problem as your own.** "I'm not saying everyone has this problem where they don't know what to write." [13:36]
    - **Rehearse in your head, away from the desk.** He says each line over and over "in the shower, going to work", asking how to say it, until "I've already visualized it like 10 times" [14:05]-[14:16].
    - **Deliver from memory, loosely.** Reading the script aloud, he says "I want to share a new demo" [11:34], but the page says "I want to show you a demo" (MEASURED). INFERRED: he speaks the lines rather than reading them. He mentions no teleprompter anywhere (K1).
    - **Talk as yourself.** "That's just me being myself, which is like, hey, I want to show you." [13:51]-[13:55]
    - **Record even when the script feels weak.** He called this one "not that strong, but I still recorded the video because you got to be launching" [10:59]-[11:03].

    Outside evidence (X1 §2.5) says audiences grant an authenticity premium to work that seems spontaneous (Rifkin & Du 2023). So the script must stay invisible.

### 3.5 Hook formula and the post-copy rewrite

20. **Write the post copy in his order:** "I built this thing", then what it is ("It's an AI teacher"), then what it does, then why it matters [07:53]-[07:58]. Care about length and the parts of the story ("tweet poetry", [08:04]-[08:11]). The measured X copy (A1) runs 276-280 characters, nearly a full tweet, and three of the four launch posts end with a bare "Demo:".

| Line's job | v1 Clicky launch | v3 drawing | v4 dictation |
| --- | --- | --- | --- |
| 1. Plain claim | "I built this thing called Clicky." | "We built an AI that can draw on your screen." | "Today we're shipping screen-aware dictation." |
| 2. What it is, in one line | "It's an AI teacher that lives as a buddy next to your cursor." | "It's a true personal tutor." | "First, we built a speedy speech-to-text (very fast, ~450ms)." |
| 3. What it does, or the turn | "It can see your screen, talk to you, and even point at stuff, kinda like having a real teacher next to you." | "Using Claude Opus we're able to draw polygons, point with pixel perfect accuracy, and walk users through complex steps directly on their screen." | "But, many products do this!" then "So we went further." |
| 4. Concrete use or proof | "I've been using it the past few days to learn Davinci Resolve, 10/10." | "Here's me learning Pythagorean Theorem + FL Studio." | "In Claude Code, it writes the prompt." |
| 5. Hand-off | (video sits under the text) | "Demo:" | "Demo:" |

The story register uses almost no copy: "hi my name is farza / i just wanted to introduce myself" (54 characters) and "i went viral" (12 characters) (A1). YouTube titles are lower-case sentences ending in a period, such as "introducing screen-aware dictation." and "we built an ai that draws on your screen." (MEASURED, R2 §3.6).

**Hooks by register.** These open both the post and the video.

- **Demo hook.** A greeting, then the thing, then one line describing what is literally on screen. Examples: "Hey, everyone. So this is Clicky." (v1), "Hey, so today we're adding dictation to HeyClicky." (v4), "Alright, check this out, no hands, ready?" (v2) (A1).
- **Story hook.** Recent social proof, plus self-deprecation, plus a credential your niche recognizes. Example: "Last week I went super viral for an idea that I built that I thought was actually kind of terrible, and this week I'm somehow in Y Combinator." [21:26]-[21:31] He says naming YC was "targeting that niche" [21:47], so the credential is a choice of audience.
- **Niche call-out.** Name the viewer's role: "hey are you the founder of a design agency stop right there let me show you something really cool" [30:33] (as transcribed).
- **Curiosity gap.** Open with a time jump that withholds the outcome, like the "two months ago…" reel he found and would reuse "as like a template" [23:11]-[23:26].

He warns against copying his hook as a formula [09:54]. The test is the stop test, not the template.

21. **Run the feed-mockup test.** On X web, find a stranger's post in your real feed. Open Chrome DevTools, inspect the post's text and replace it with your draft. The change is local only; nothing is posted (MEASURED, R2 §3.2: he edited a real post's text span, then scrolled the feed). Then ask "did my eye stop?" [08:50] and whether you would read the first sentence [09:06]. This is his "number one rule, regardless of Twitter, Instagram, YouTube, anything" [08:59].
22. **Rewrite until it passes.** If your eye slid past, or you would not read beyond line one, rewrite the first line and run step 21 again. Expect several angles before one stops you (W1 S7: "drafted hella tweets").
23. **Run the mute test on the video.** Watch it muted at scroll speed and say aloud the few words your brain picks up. His reading of the drawing video was "guy in front of blackboard, AI, draw, screen … Claude Opus, demo, click" [33:54]-[34:07], because "nobody's reading this entire … damn thing" [34:07]-[34:11]. A third-party analysis of Clicky versus his failed Tidbit puts the same test as "can a stranger tell what it does on mute?" (W1 S27).
24. **Put the link in a self-reply, not the post.** In all four launch posts the URL came in a self-reply 4 h 40 min to 7 h 46 min later, phrased like "This is real, and shipped" (MEASURED, A1), with honest notes such as "High chance I run of credits lol" (W1 S2). INFERRED: this keeps the scored post link-free. X's link treatment may have changed in 2025-26 (X1 §2.9), so test it.

### 3.6 The first 10 seconds

25. **Choose the first frame for your audience.** "It's very purposely Xcode", because curious developers come first, not video editors [09:13]-[09:22], even though the use case shown was learning DaVinci Resolve. "Most people, when they're scrolling, see the first three seconds." [09:32]
26. **Lay out the first 10 seconds with the template for your register.** All three templates come from A1's frame-by-frame reads. Across all six videos the first word starts within 0.25 s, with no title card, logo or music intro.

**Template A: raw screen take (16:9, X first).** From v1 and v2.

| Time | Picture | Words | Text on screen |
| --- | --- | --- | --- |
| 0.0-0.3 s | Full desktop in the audience's own tool (Xcode), webcam bubble bottom-right | First word at 0.08 s (v1) or 0.20 s (v2) | none |
| 0.3-2.4 s | Same. One gesture to camera: a peace sign at 0.5 s (v1), open palms on "no hands" at 1.5-2.0 s (v2) | "Hey, everyone. So this is Clicky." (0.08-2.36 s) | none |
| about 2.2 s | Animated zoom onto the small key element (the blue triangle beside the pointer) [09:24] | | none |
| 2.5-7.0 s | Hold the zoom; move the cursor so something visibly moves [09:40] | One line describing what is on screen: "Clicky is this little blue guy that follows your cursor…" | none |
| about 7.0 s | Zoom back out to the full desktop | "…it's basically an AI teacher that can teach you anything." (to 9.41 s) | none |
| 9.6-10.4 s | Full desktop | "So check this out." | none |
| 10.4 s on | The real use case, framed as a personal problem ("a video editing program that I've been procrastinating learning") | | none |

There are 0 hard cuts in the first 10 s of both videos. v2 is demo-first: the spoken command at 2.5 s, Spotify opening at 10.1 s.

**Template B: produced feature demo (16:9, edited).** From v3 and v4.

| Time | Picture | Words | Text on screen |
| --- | --- | --- | --- |
| 0.0-0.5 s | Medium shot of the founder facing camera in a real place (outdoor table with a laptop; a blackboard). In v3 he walks into frame | First word at 0.04 s (v4) or 0.23 s (v3) | Caption from 0.5-1.0 s: 3-6 word chunks, white, bottom-center at about 80% of height |
| 0-3 s | Same | "Hey, so today we're adding dictation to HeyClicky." (to 2.94 s) | "Hey, so today we're adding" |
| 3.5-6.6 s | Cut to a close-up of how it works: fingers on fn + control (v4, 4.04-6.01 s); a hand chalking a triangle and an arrow (v3, 3.50-6.64 s) | The one gesture or capability | "hold fn + control," |
| 6-10 s | Back to the face | The rest of the what: "…whatever text box your cursor is on." | phrase chunks |
| about 8-10 s | | Music bed comes up (v4) | |
| 10-11 s | First full-screen product recording; the demo starts at 8-9% of runtime | | captions continue |

There are 2 cuts in the first 10 s. In v4 the turn comes at 21-30 s and the reveal at 31 s, on a new, darker setup (A1).

**Template C: vertical story (9:16).** From v6. The 20.9M reel's hook (R3 I6) is the variant noted below the table.

| Time | Picture | Words | Text on screen |
| --- | --- | --- | --- |
| 0-1.3 s | Wide: founder under a tree with a laptop | "Today we crossed over 5 million views on this thing we're building called Clicky" (0.12-3.56 s) | 2-3 word captions at about 63% of height from 0.0 s |
| 1.3-2.7 s | Punch in to medium | | |
| 2.7-3.8 s | Seven proof screenshots at about 0.1 s each: the launch post, README, repo, site | | |
| 3.8-6.5 s | Screen recordings of the product working (Logic Pro, DaVinci) | | |
| 7.0-8.9 s | Double exposure: head in hands, plus the product pointer reading "Make a cut here" | "…considering that I thought it was actually a pretty meh idea" | |
| 8.9-9.7 s | Medium face shot | "meh idea." | |

There are 13 hard cuts in the first 10 s, music throughout, and the demo starts at 16.1 s (36%).

The 20.9M reel's hook runs about 7-8 s:
- his face is on camera for 6 of the 8 sampled seconds;
- second 2 cuts to the 2.8M-view X post as proof;
- second 7 holds a YC badge up to the lens;
- word-chunk captions run throughout (MEASURED, R3 I6).

27. **Check the cut against the measured norms (A1):**
    - first word within 0.3 s;
    - product or capability named by about 3.5 s;
    - the key detail visible and moving by 3 s;
    - no title card or logo sting;
    - the demo running by about 10% of runtime;
    - the "why" turn by about 25%;
    - the soft CTA in the last 3-7%.

    These are his habits, not proven thresholds (§7).

### 3.7 The formula for videos that convert

28. **Structure the video as:** "This is who I am, this is what's going on, this is what I'm working on, let me show you." [21:51]-[21:56] (also the cold open, [00:21]-[00:27]). As executed in the 20.9M reel (R3 §3):
    1. **Who and what's going on**, about 7 s: social proof, then self-deprecation, then the niche credential.
    2. **What I'm working on**: the name plus a one-line value proposition, "It's called Clicky, it's a little AI buddy that lives next to your computer cursor and teaches you anything in real time for free" [21:56]-[22:05].
    3. **Let me show you**: one relatable use case set against the status quo ("instead of going to a YouTube video" [22:05]-[22:10]). Then the product visibly does it: the pointer bubble says "this one!" on the color wheel (R3 I7).

    The launch demos (v1-v4) drop "who I am" and start at "what I'm working on" (A1). Use the full formula for story videos and the short form for feature demos; the team update (step 9) skips it.
29. **Check the two properties he says matter.** First, a "super clear hook". Second, "a very clear like why you should care right now while you're on your scroll" [22:34]-[22:40].
30. **Run the bounce test** on your video and on others': "am I bouncing, when am I bouncing?" [22:48]. Cut or rework whatever causes it.
31. **Define "convert" before you claim it.** In the interview, the evidence that a video "converts" is mostly views:
    - the 20.9M reel "is still driving a lot of our traffic" [21:12] and now runs as a Facebook ad [21:22];
    - the YouTube dictation video is "one of our highest converting" with no figure given [12:12].

    The only conversion numbers are in §3.10. Treat "converts" as something you measure through your own tracked links (step 4), not as a property of the formula.

### 3.8 Turning demos into stories

The host frames it: "Everyone wants a story, and so how can a demo just be a mini story?" [24:04] (host; the cold open reuses it at [00:27]). Farza agrees that to a viewer on a feed he is "just a random character" [24:29]-[24:37].

32. **Build the turn.** The measured pattern (A1, pattern 4) is a concession, then a personal problem, then the reveal. v4 has it word for word:
    - concession: "So that's pretty cool, and honestly, many products already do this exact thing today." (21.2 s)
    - personal problem: "But here's the thing, when I'm writing, I often don't really know what I even want to say." (26-30 s)
    - reveal: "So check this out, we're shipping screen-aware dictation." (31 s)

    v3's turn is an escalation instead: "Alright, so that's kind of cute, but what if I wanted to do something a little bit more complicated?" (60 s).
33. **Put beats where cuts would go.** His no-hands demo has "not a single cut" [37:02] but has beats [37:06] (host), and "of course that's all purposeful" [37:18]. The measured beats (A1 v2, R4 §3) run:
    - the hook ("no hands");
    - the ask, then about 1.5 s of silence;
    - the song plays;
    - "it's a little bit loud", and the volume drops;
    - the Stripe dashboard, with a joke ("$140 in a day is not very good");
    - a new beat about every 10-15 s after that.

    The aim is to keep the story moving: "I'm not trying to keep your attention, that's actually the wrong way to look at it." [37:36]
34. **At each beat, ask from the viewer's seat: "am I here? am I still watching?"** [38:27]. Some videos are cut fast on purpose, for "the audience that just has no attention span" [37:53]. The "9 weeks" reel cuts every 0.7-1.3 s (MEASURED, R4 I-14).
35. **Place self-deprecation after a success beat.** Examples are v1's "I'm not sure why I recommended the Sony LUT" aside and v6's "a pretty meh idea" (A1, pattern 5). The host notes the same quality in younger founders' hooks [23:48]-[24:00].
36. **Show what you're doing and why, never your life.** "You'll never catch me making those videos about this is my day as a YC founder." [25:52]-[25:59]
37. **Keep a swipe file.** Watch Reels "not for entertainment, just to kind of study" [22:54]. When a hook works on you, note its device (lighting, caption placement, a "two months ago" curiosity gap) and turn it into a template for your own story [23:05]-[23:26].

### 3.9 Record, edit, post

38. **Record at the level the register needs** [40:52]-[42:32]:
    - Level 1: Screen Studio for on-screen demos;
    - Level 2: phone selfie camera, edited on the phone in Edits;
    - Level 3: Sony FX3 or FX30 with a DJI mic, edited in DaVinci Resolve on the laptop.

    Whatever the level, "show yourself, show your face very clearly", be proud, and "confidently tell the camera what you're working on" [12:30]-[12:44]. Talk to "that like one other person in that world that may think this is cool" [12:48].
39. **Edit to the measured norms (A1, patterns 3 and 8):**
    - Raw takes get no captions and no music; a jump cut may remove dead time.
    - Edited videos get burned-in captions in short phrase chunks: 3-6 words at about 80% of height on 16:9, 1-3 words at 63-69% on 9:16. They are not karaoke-style word-by-word captions.
    - Edited videos get a music bed that dips at the turn or reveal. He brings "the song" himself [43:26]-[43:28].
40. **End with a soft CTA in the last 3-7% of runtime.** Make it an invitation, never "sign up": "I'll put the link below and give it a shot." (v1); "Try to break it." (v3); "This is in production right now." (v4). End cards, where used, say "try it for free" and show the product name (A1, pattern 6).
41. **Make each video for one primary platform, then cross-post** [33:23]. Most of his are made for Instagram (vertical) and posted to X; X-first videos are 16:9 [33:35]-[33:39]. At the start, post the same video everywhere "just to see what happens" [12:26]. A brand-new channel is fine: the YouTube channel was three days old when the dictation video went up [12:07].
42. **Post even if you think it is bad.**
    - He thought the Clicky demo "was not that good" [06:16] and was "so wrong" [06:37].
    - He thought the dictation video was the worst they had made [14:26]; it got 2.95M X views (MEASURED, A1).
    - "I'm constantly forcing myself to put it out." [14:59]

    Have your step-6 person ready.
43. **Post and walk away.** Accept zero views at the moment you post [16:56]. "By the time I hit post, I've already forgotten it." [17:05] Check results "maybe a week later" [17:10].

### 3.10 Measure, and what he found per platform

44. **Measure downloads, then retention, then talk to the retained users.** "I do not care about the traffic at all." [07:05] For the Clicky launch:
    - he asked how many downloaded, "I think 7,000" [07:18];
    - then who retained, about 100 used it "every day for five days straight" [07:27]-[07:30];
    - then "I reached out to those 100 people" [07:34], and their unexpected uses kept him going [07:38]-[07:42].

    That is 0.23% of the 3.0M viewers downloading, and 1.4% of downloaders retained (arithmetic on his figures and A1's view count). A stronger variant from his vlog is a Stripe link right after the demo, with a target of 25 paying customers (W1 S15).
45. **After the first few videos, compare channels on conversion, not views** [32:38]-[33:13]. Use the tagged links from step 4.

| Platform | What he claims | Numbers | Evidence status | What to do |
| --- | --- | --- | --- | --- |
| **X** | Worst conversion over about 10 years [31:05]-[31:13]; people are "doom scrolling" [31:45]-[31:50]; wants 16:9 [33:39]. | Clicky launch: 3,000,762 views (A1) and 7,000 downloads (his figure), so 0.23%. Dictation: 2.95M views (A1), conversion "horrendously low" [31:23]-[31:30]. | Views MEASURED; conversion anecdote. The link penalty documented in 2023 was said in 2026-07 to be gone "for over a year" (X1). | Use X for reach and as a credential. Post 16:9. Re-measure conversion yourself. |
| **YouTube** | Best converting "for most companies" [31:54]-[32:00]; "a library that will last for decades" [32:16]. | Dictation: 21,012 views (A1); "like 20" percent downloaded [31:37]. | 20% is anecdote and CONTESTED: about 4,200 downloads from 21K views is about 90 times the X rate, so probably another denominator (X1). | Upload every feature demo, with a tagged link. |
| **Instagram** | About 70% of all traffic [32:22]; the best audience "by far" [33:13]; most videos are made for it [33:23]. | 20.9M reel; 35.4K _heyclicky followers (on screen, R3). The 16:9 drawing video "performed even better" there [34:17]. | Traffic share anecdote; counts MEASURED on screen. | Make vertical for Instagram first; tagged bio link. |
| **TikTok** | Business buyers are there too [30:14]-[30:23]. | About 50 design-agency leads from videos averaging about 4,000 views [30:38]-[30:48]; Tidbit's product TikToks converted about 0.5% (W1 S9). | Anecdote. Forrester 2026 puts Facebook, Instagram and YouTube above LinkedIn for business buyers (X1). | Niche call-out hooks; count leads, not views. |
| **LinkedIn** | Not discussed by him; the host's "default" route [30:00]. | 75,318 impressions on a cross-posted demo (on screen, R4 I-9). | MEASURED on screen only | Cross-post; unmeasured. |
| **Facebook (paid)** | Runs the 20.9M reel as an ad [21:22]. | none | Anecdote | Turn proven winners into ads. |

46. **Let winners keep working.** YouTube "will keep on performing" [32:12], and algorithms keep serving a strong video [21:12]-[21:17].

### 3.11 The thousand-shots rule, with numbers

47. **Commit to volume, and expect most posts to do little.** "If you don't take a thousand shots, you're not gonna make the five thousandth shot." [20:25] The thousand is a figure of speech. Here is what the numbers show:

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
| 3-5 TikToks a day; about 4M views in 7 days | Tidbit, 2025 (the product still shut down) | DOCUMENTED, his Substack (W1 S8, S9) |
| Median views 459-506 at every frequency from 1 to 11+ posts a week; 90th percentile rises from 3,722 to 14,401 | Buffer's TikTok study: 11.4M posts from 150K+ accounts | DOCUMENTED (X1 §2.7) |

The outside data says volume buys more chances at a hit, while the typical post does not improve. His claim that you also get better [20:15]-[20:25] is plausible but untested (X1).

48. **Review the log every week.** Find the best post of the period, name the device that made it work (hook, first frame, register), and reuse it next [46:26]-[46:36]. Judge by the best post, not the median (X1 §2.7).

### 3.12 The stack

49. **Buy only what the register needs. Audio comes first.** Prices are as of 2026-10-24, from K1.

| Role | His tool | Price | Free or cheap path | Notes |
| --- | --- | --- | --- | --- |
| Screen demo | Screen Studio [40:53]; "I think it costs like 30 bucks" [41:03] | $29 a month, or $9 a month billed yearly; v4.0 (MEASURED, K1) | Cap, OpenScreen, OBS; macOS Cmd-Shift-5 has no auto-zoom (K1) | Its auto-zoom and cursor smoothing make the v1 zoom (INFERRED, A1) |
| Native talking video | Phone selfie camera [41:13]; "iPhone or Android, it's okay" [46:02] | The phone you own | Any phone | "Nothing else required" [41:23]-[41:28] |
| Phone edit | Edits, Instagram's editor [41:17]-[41:23] | Free (DOCUMENTED, K1) | CapCut's free tier | Captions and trims on the phone |
| Cinematic | Sony FX3 or FX30 [41:38] | FX3 $4,299.99 list ($3,998 on Amazon, Oct 6); FX30 about $1,800-2,100 (DOCUMENTED, K1) | Phone rear camera; a used mirrorless body | Level 3 only |
| Audio | DJI mic [41:38]; "find them used online" [42:23] | Mic 3 from $169 (MEASURED, dji.com); Mic Mini kit about $79 (DOCUMENTED) | Any external mic | The one non-negotiable [41:46]-[42:27] |
| Laptop edit | DaVinci Resolve [42:32] | Resolve 21 free; Studio $236, down from $295 until Nov 20 (MEASURED, K1) | Free Resolve | |
| Writing | FreeWrite, his app [45:01]-[45:08] | Free, MIT license, v1.5 (MEASURED, K1) | Any plain editor with a timer | 15-minute default timer |
| Filmmaker | Vikrant (ASR spelling) [42:39]-[43:47] | Not discussed | The founder alone, then a contractor | He brings shot and hook ideas; Farza brings "the script and the song and the vibe" [43:26]-[43:28] |

He calls the filmmaker "maybe the most important part of my stack" [42:37]-[42:39]. If you cannot afford one, "go back to my old Zip School videos" and just start [44:03]-[44:25].

### 3.13 The 30-day launch challenge

For anyone who has never made videos or talked about their work online, but has been building something [45:46]-[45:58]:

50. Every day, spend 10 minutes [46:00].
51. Use your phone, any brand [46:01]-[46:02].
52. Record yourself talking about what you were doing, or what you did that day [46:04]-[46:06].
53. Post it to Instagram or TikTok [46:08]-[46:10]. A new Instagram account is fine, "so your existing followers don't even know" [46:12]-[46:15].
54. Do it "30 days straight, every day, one video" [46:17], [46:40]-[46:41].
55. Find the video that passed about 1,000 views. Ask why, and base the next one on it [46:22]-[46:36]. He offers to like your posts if you send them [46:42]-[46:43].

**Run it as a measured experiment** (X1 §2.14, INFERRED):
- log all 30 posts as in step 5;
- reuse the hooks of the top three in the next ten;
- set expectations from the base rate: Buffer's established accounts have a median of a few hundred views per post, and a brand-new account may start lower.

His promise ("I promise you" [46:20]) is not data.

## 4. Measured reference: his launch videos

All values were MEASURED by A1 on 2026-10-24: lengths and counts with ffprobe and fxtwitter or yt-dlp, cuts with a luma-difference detector, words with whisper. The cut detector counts on-screen app switches as cuts and misses Screen Studio zooms, so v2's "cuts" are windows opening, not edits. It also overcounts low-frame-rate archival footage in v5.

**4a. Format**

| Video | Posted (PT) | X views | Length | Aspect | Hard cuts per min (median shot) | Cuts in first 10 s | Face on screen | Screen on screen | Captions | Music |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| v1 Clicky launch | Apr 6, 2026 | 3,000,762 | 99.9 s | 1.54:1 | 1.8 (27.5 s) | 0 | 100% (bubble) | 100% | none | none |
| v2 "no hands" | May 30, 2026 | 3,826,653 | 104.1 s | 1.54:1 | 2.9 raw, all app switches; 0 edits (11.5 s) | 0 | 100% (bubble) | 100% | none | only the demo's own Spotify |
| v3 drawing | Jun 16, 2026 | 629,293 | 140.4 s | 16:9 | 13.3 (3.4 s) | 2 | 62% (23.6% face only + 38.6% face with laptop) | 35.7% | phrase chunks, about 80% of height | bed, swells at the end |
| v4 dictation | Jul 14, 2026 | 2,945,014 (+21,012 YouTube) | 120.1 s | 16:9 | 18.5 (2.2 s) | 2 | 54% | 41.7% (+2.5% keyboard) | phrase chunks, about 81% | bed from about 8 s |
| v5 "hi my name is farza" | Sep 8, 2026 | 64,892 | 109.5 s | 9:16 | 45.5 raw, overcounts archival (1.1 s) | 3 | 32% (+47.7% archival) | 20.2% | 1-3 words, about 69% | bed |
| v6 "i went viral" (@heyclicky) | Apr 29, 2026 | 73,093 | 44.9 s | 9:16 | 52.1 (0.7 s) | 13 | 49% (incl. 7.2% double exposure) | 50.7% | 2-3 words, about 63%, moves | bed |

**4b. Words**

| Video | Hook (first words, time) | "What it is" lands by | Demo starts | Spoken CTA | Link | Post copy |
| --- | --- | --- | --- | --- | --- | --- |
| v1 | "Hey, everyone. So this is Clicky." (0.08-2.36 s) | 2.4 s | 10.4 s (10%) | "I'll put the link below and give it a shot." (97%) | Self-reply +4 h 42 min | 276 characters |
| v2 | "Alright, check this out, no hands, ready?" (0.20-2.25 s) | 2.3 s | 2.5 s (2%) | none | Self-reply +6 h 54 min | 151 characters, ends "Demo:" |
| v3 | "Hey, so we built a system that can draw directly on your screen…" (0.23-7.80 s) | 3.5 s | 10.9 s (8%) | "Try to break it." (93%), end card "try it for free" | Self-reply +7 h 46 min | 279 characters, ends "Demo:" |
| v4 | "Hey, so today we're adding dictation to HeyClicky." (0.04-2.94 s) | 2.9 s | 11 s (9%); reveal at 31 s (26%) | "This is in production right now." (93%) | Self-reply +5 h 40 min | 280 characters, ends "Demo:" |
| v5 | "I feel like a lot of you guys are new here and I just want to introduce myself" (0.04-2.88 s) | 5.8 s (who he is) | no demo | "Thanks for following" | none | 54 characters, lower-case |
| v6 | "Today we crossed over 5 million views on this thing we're building called Clicky" (0.12-3.56 s) | 3.6 s | 16.1 s (36%) | "go make Clicky do things" | none | 12 characters, lower-case |

**4c. Seen only inside the interview** (partial reads from the YC edit, not full measurements)

| Video | What was measured | Source |
| --- | --- | --- |
| Clicky Instagram reel, "Last week I went super viral…" | 20.9M views on the grid tile; hook about 7-8 s with face for 6 of 8 s; body about 1 cut per second with word-chunk captions; 4-6 hours to make [22:14]-[22:19] | R3 I5-I7 |
| "everything we built this week" team update | Three speakers in about 22 s, title card, captions, B-roll | R3 I12 |
| "It has been 9 weeks" and "Two weeks ago…" reels | Cuts every 0.7-1.3 s; a real usage chart as proof | R4 I-14, I-15 |
| Zip School class launch, Feb 2021 | Screen recording with a selfie bubble, no captions; 23 likes | R3 I2 |

**What the tables say** (INFERRED from A1):
- The opening is the constant: no intro card, and the thing is named within about 3.5 s.
- The two biggest X hits are raw single takes, and v4 was nearly as big while fully produced.
- Horizontal demos reach far more people on X. Vertical stories get higher like rates (1.1-2.5% against 0.36-0.83%) but fewer bookmarks per like (0.21-0.22 against 0.52-0.82).
- The link never goes in the post.

## 5. What an agent can do, and what needs the founder

Step numbers refer to §3. "Agent" means a Claude Code agent with this machine's tools (K1 MEASURED their presence: ffmpeg with `loudnorm`, `astats`, `silencedetect`, `afftdn`; whisper-cli; agent-browser; auto-editor; HyperFrames). The agent never posts. Posting, replies and messages to users are the founder's acts, and our harness forbids an agent sending anything outbound.

| Steps | The agent can do | The founder must do |
| --- | --- | --- |
| 1 Tiers, 10 one-shot channels | Propose a calendar from the roadmap and git log; flag what belongs in the quarterly tier | Choose the tiers and commit to them |
| 2 Microphone | Measure each take's noise floor and loudness; reject a take with bad audio before editing; denoise lightly (K1) | Buy and wear a real mic; re-record bad takes (a laptop-mic recording cannot be repaired into a lav, K1) |
| 3 Recorder | Recommend and configure a recorder; record scripted web flows at a fixed window size (agent-browser) | Record native-app and live demos; agent-driven desktop capture is fragile (K1) |
| 4-5 Tracking, log | Add link paths if the site is in a repo; keep the post log; compute conversion per channel from analytics it can read | Grant analytics access; decide what counts as a conversion |
| 6 "Post it anyway" person | Nothing. An agent saying "post it" is not the human push he describes (INFERRED) | Name the person |
| 7-9 Weekly question, daily prompt, team update | Ask the question on a schedule; draft the "what shipped" list from git log and the changelog (K1) | Say which moment made you smile; appear in the update |
| 11 Caption-first gate | Draft many caption and hook angles; check the 280-character fit; act as a critic | Judge whether it excites you; pick one |
| 12 Grounding frame | Mock up the frame as a still | Choose it |
| 13-14 "Check this out", same-day deadline | Track the deadline; suggest a smaller angle you can demo today | Notice the moment and record it raw |
| 15 Register | Recommend one from the §3.3 table | Choose it |
| 16-18 Script | Interview the founder by voice, transcribe locally, and turn it into a structure; mark the setup block; time it to length; critique against the reading tests | Write the lines in your own voice (K1: an agent-written script is the one most likely to sound read); make the "do I enjoy reading it" call |
| 19 Off the cuff | Make a rehearsal card with beats only | Rehearse until visualized about 10 times; deliver from memory |
| 20-22 Copy and feed mockup | Draft copy variants; build a local, static mock of a feed card | Judge "did my eye stop?" with your own eye (on his real feed, this uses his logged-in session, §8) |
| 23 Mute test | List what the first frames say with no sound | Confirm the read |
| 24 Self-reply | Draft the reply and caveats | Post it |
| 25-27 First 10 seconds | Lint the cut with A1's method: word times, cuts, captions, demo start and turn as shares of runtime | Perform the opening |
| 28-37 Formula and story | Map beats onto the formula; mark the turn and reveal; keep the swipe file | Pacing and taste; the bounce test is a human reaction |
| 38 Record | Record deterministic web flows; trim dead air (auto-editor); add zooms in post (HyperFrames or Remotion); crop to 9:16 | Be on camera; narrate live; shoot Level 3 |
| 39-40 Edit | Rough cut from the transcript; phrase captions (via HyperFrames or Remotion: this machine's ffmpeg has no `drawtext`, `subtitles` or `ass` filter, MEASURED K1); loudness; per-platform exports | Final pacing, music, when not to cut (K1: taste is "not delegable") |
| 41-43 Post | Package files, copy, captions and replies per platform | Press post; walk away |
| 44-46 Measure | Pull numbers; compute conversion per channel; draft messages to retained users (outbound-drafting skill) | Talk to every retained user yourself |
| 47-48 Volume review | Weekly: top post, its device, what to try next | Decide what to make next |
| 50-55 Challenge | Daily reminder, log, captions, day-30 review | Record and post every day |

The agent can take most of the work around the founder: planning, measurement, editing, versions and the log. The founder keeps what the method rests on: noticing the moment, being on camera in their own words, judging whether their own eye stops, and pressing post.

## 6. Boundary with our launch-film skill

**What each one is.**

| | launch-film skill | This method |
| --- | --- | --- |
| Unit | One high-craft film, or a README hero | Many small demo posts |
| Cadence | Per product, or per major release | Daily to weekly, plus a biweekly team update |
| Who is on screen | Nobody real. A human shoot, stock footage and generated video as the base are all ruled out (launch-film §0.11) | The founder's face and voice, and the real product |
| Medium | Code-built 2D (web) or path-traced 3D | Screen recordings, phone selfies, camera footage |
| Approval | One operator yes at each gate: story, look, board, stills, motion, sound, render, README | No gates beyond the founder's own stop and mute tests |
| Time | Days to weeks. One 2026-10 film had a 70.6 h look stage and an 81.4 h final render (launch-film §2, §10) | Minutes to hours. v1 was posted about 13 min after the take (A1) |
| Truth rule | Every on-screen number measured under a written rule (launch-film §1.6) | His practice is mostly honest caveats; this method adopts launch-film's rule |
| Success | The operator's yes, and a hero that lasts | Downloads, retention and conversion per channel |
| Where it lives | README hero (a GitHub attachment video), project `BRIEF.md` and `STATUS.md` | Social channels, the post log, optionally a demos or changelog section |

**When to use which.**
- **Use launch-film** for:
  - a product's first public face on GitHub;
  - a README hero;
  - the quarterly "polished launch" tier [15:57];
  - any time no founder will be on camera, or the piece must stand unchanged for months.
- **Use this method** for:
  - every shipped feature and every "check this out" moment;
  - every social feed;
  - learning which message and channel actually convert.
- **Use neither** for a Launch HN or Product Hunt post. Those are copy, though this method's caption-first gate (step 11) helps write them.

**How they coexist for one product** (INFERRED; nothing in the sources tests this):
1. **Demos first, film later.** The demo cadence finds the message: which hook stopped people, which use case kept users. The film's story gate (launch-film §1) takes its value points and "most impressive true claim" from the post log.
2. **Separate outputs.** The film owns the README hero slot and its project files. No demo replaces the hero URL or writes to the film's `BRIEF.md` or `STATUS.md`. Demos live on the channels and in the post log, and if the README links them, it does so below the hero.
3. **Separate looks.** Demos stay raw and never wear the film's look. The film never cuts in demo footage, since launch-film rules out human footage and wants real UI "translated into the film's material, never pasted in". The film borrows claims from demos, never pictures.
4. **One claims ledger.** A number appears in either only if measured under a written rule. The film carries claims that stay true; fast-moving numbers (views, customers) belong in demos, which date themselves.
5. **One one-line description.** The product's one-line value proposition is the same in the film and in the demos' "what it is" line. Change it in one place, on purpose.
6. **Nobody waits, and approvals do not transfer.** Demos keep running through the film's gates. When the film ships, post it like any demo, with its caption written first (step 11), the feed test (step 21) and a tagged link (step 4). A demo doing well is not a film gate's yes, and a film yes does not approve demo copy.

## 7. Evidence and caveats

### 7.1 Survivorship and an audience built over a decade

- **Only the hits are shown.** The interview shows hits: 3.0M, 2.95M, 3.83M and 20.9M views. He says so himself: "we're looking at the stuff that's working but so much hasn't worked" [35:23]. The "thousands of videos" nobody cared about [09:49] are not shown, and his own measured early baseline is 10-23 likes (R3).
- **He has built distribution for years.** @FarzaTV has 129,259 X followers (MEASURED, W1 via the fxtwitter API). There is also the farzatv YouTube channel (13.6K subscribers, W1) and the Buildspace audience, and he has been posting for "10 plus years" [06:33]. INFERRED: "say hi and post" works partly because he already had reach.
- **Hits are irregular, even for him.** "No one sees 2025" (W1 S19), and the Tidbit launch got 342K views before the product shut down (W1).
- **His own hit prediction is weak.** He says "we kind of know it's a hit before we even start" [04:28] and "I just knew … when I wrote the script" [21:03]. Yet he called the Clicky demo "not that good" [06:16] and the dictation video "the worst video we've ever done" [14:26]. The rule that holds up is "post anyway", not "predict".

### 7.2 "Scrappy" is partly produced

- **His filmmaker made the videos.** "Every video we just looked at, apart from the bad Zip School ones, which were made by me, are made by Vikrant." [42:51]-[42:53] At one point the company had three people making videos and one engineer [39:59]-[40:04].
- **The truly solo examples did little.** In the interview, the only founder-alone videos are the Zip School ones, which got 10-23 likes, and the challenge.
- **There is a tension over v1 and v2.** Both look like unedited Screen Studio takes (A1), which sits oddly beside "made by Vikrant" (INFERRED).
- **Production level did not predict views.** Across four demos, a raw take and a produced cut each reached about 3M on X (A1, n=4). That is a sample-size caveat, not a finding.
- **Who is on camera is not fully established.** A comment on the drawing reel says "Well done Zain" (MEASURED, R4 I-8), and the reels carry several collaborator avatars. A1 did not identify the presenters.

### 7.3 Numbers that are his anecdotes

| Claim | Where | Status |
| --- | --- | --- |
| 7,000 downloads after the Clicky launch | [07:18], [31:13] | His recollection ("I think"); no public source (W1) |
| About 100 retained daily for five days | [07:27]-[07:30] | Anecdote. The window is stated two ways: "four days later" [07:19] and "five days straight" [07:30] |
| About 20% conversion on YouTube | [31:37] | Anecdote; implausible as views to downloads (X1) |
| About 70% of traffic from Instagram | [32:22] | Anecdote, hedged with "I think" |
| About 50 leads from TikToks averaging about 4,000 views | [30:38]-[30:48] | Anecdote; leads, not deals |
| "One of our highest converting videos" | [12:12] | No figure given |
| A selfie video beats a $20,000 produced video | [03:11] | Hypothetical, hedged with "probably" |
| The team update has "almost a million views" on Instagram | [25:22] (host) | Not shown on screen |
| A produced video takes him "like an hour"; the reel took 4-6 hours; the team update takes 10 minutes | [20:50]-[20:55], [22:14]-[22:19], [26:30]-[26:36] | Anecdote; the update's edit is visibly more than 10 minutes (R3) |
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

- **"Old media is gone" [03:08].** YC's 2019 view was that press, Product Hunt and HN launches were "starting to even out", not that press had stopped working. The NYT story in YC's own cold open documents startups spending big on hype videos in 2026, including a reported US$80,000 shoot (R1 Insert A, DOCUMENTED via a reprint).
- **Cheap beats expensive.** In Wistia's 2018 test the $10K ad beat both the $1K and the $100K one, and polish raised perceived expertise but not trust (Johnson et al. 2021). The lesson is story over budget, not cheapest wins.
- **Volume.** Buffer's medians stay flat as frequency rises. Volume buys a fatter tail; skill gains are untested.
- **X conversion.** Link suppression was documented in 2023 and reportedly ended by 2025-26, so his decade of poor X conversion may not hold now.
- **Business buyers.** A TikTok lead is not a deal; 6sense (an interested vendor) reports buying groups of about 11 people and cycles of about 11 months.
- **Showing the process.** Copying is real: Clicky has 1,552 forks, a port appeared within 18 hours (W1 S27), and he moved new work to closed source on 2026-04-27.
- **Audio first.** Corroborated (Newman & Schwarz 2018), but much feed video plays muted (up to 85% of Facebook views in publishers' 2016 reports). Captions and the mute test matter as much.
- **Scripting.** No study compares scripted and unscripted founder videos, and the spontaneity premium (Rifkin & Du 2023) means a visible script costs trust.
- **Hiring a filmmaker first.** Untested. Buildspace, with a 2-of-7 film team [39:55]-[39:59], is listed "Inactive" on YC (MEASURED, X1), though it closed by his choice with over two years of cash (W1 S22).

### 7.5 Tensions inside his own account

| Tension | Resolution for this method |
| --- | --- |
| "This whole video scripted" [14:00] vs the Clicky launch was "almost entirely unplanned" [10:00] | Two registers: a raw same-session take for a fresh moment, a script for produced feature videos (steps 15-16) |
| "Five minutes before dinner" [06:40] vs he had "been sitting on the Clicky demo for a few weeks" (W1 S3) and "tabled it for another two weeks" (W1 S19) | Recording took minutes; deciding to post took weeks. Plan for the hesitation (step 6) |
| Setup is "10, 20%" of "one minute" [11:19]-[11:31] vs videos of 100-140 s whose "why" lands at 18-26% (A1) | The 10-second rule holds for the "what"; the turn can come later (step 17) |
| "There's no hook" for the team update [25:12] vs "my formula is always the same" [21:51] | Updates for existing users skip the formula; acquisition videos use it |
| "The goal … is never to go viral" [30:48] vs examples chosen by view count | Views are how he picks examples to show; conversion is how he judges them |
| "What's really hard to clone is the audience" [40:22] vs "distribution is nothing without like a good product" (W1 S17) | Product first; the audience compounds on top of it |
| In 2025, telling a story about what he was building felt wrong on Reels (W1 S8) vs Instagram as by far the best channel in 2026 [33:13] | INFERRED: the story works once there is a demo a stranger can understand on mute (W1 S27) |
| "I'm good at … writing stories" [19:23] vs 2024: "I am not naturally a guy that can tell great stories" (W1 S12) | The skill came from practice; do not make "be a natural storyteller" a prerequisite |
| "Show your face very clearly" [12:36] vs the face appears only as a bubble in his two biggest hits (A1) | For screen-led demos, a face bubble is enough |

### 7.6 Untested practices

The feed-mockup test, the 10-20% setup ratio, the audio rule's ranking above picture, the gear list and the 30-day challenge appear nowhere outside the interview (W1, from absence in the sources read, which is not proof). The self-reply link timing is a measured habit (A1) whose effect nobody has tested.

## 8. Open questions for turning this into a skill (stage 2)

1. **Who is on camera?** The operator's products are mostly developer tools. Will he be on camera, voice-only, or neither? Voice-only maps to the raw screen take (v1, v2). Neither means this method does not apply, and launch-film covers the alternative.
2. **Scope.** A new skill beside launch-film (working name `demo-launch`) with a shared claims ledger, or a quarterly-tier pointer inside launch-film? Where does the post log live: each product repo, or a private directory?
3. **The outbound line.** The skill stops at a ready-to-post package (files, copy, self-reply, captions). Do messages to retained users go through the outbound-drafting skill?
4. **The feed-mockup test.** Does a static local mock serve, or must it be the founder's real feed? A text swap in his logged-in X session through agent-browser is local-only, but the session is his.
5. **Captions.** This machine's ffmpeg has no `drawtext`, `subtitles` or `ass` filter (K1). Standardize on HyperFrames or Remotion, or install a full ffmpeg build?
6. **A first-10-seconds lint.** Should step 27 become a script? Which of its thresholds are norms, and which are only Farza's habits?
7. **Agent-recorded demos.** Can an agent record a CLI or web take that still reads as "hacking on this right now" rather than a product tour (K1)?
8. **Conversion for an open-source tool.** Stars, installs, issues or sign-ups? What tagged path stands in for `/ig` when the destination is a GitHub repo?
9. **Validate before codifying.** Should stage 2 start with a pre-registered four-week cadence, or the 30-day challenge, before fixing thresholds?
10. **Script authorship.** How much can the agent draft before delivery sounds read? Test it: the founder records one beat from an agent draft and one in his own words.
11. **Formats.** Which of the five registers, plus teaser-then-livestream (W1 S5), belong in version one?
12. **Link timing.** Copy the 4-8 h self-reply habit, or A/B it, given X's link treatment may have changed?
