<!-- markdownlint-configure-file { "MD013": false } -->

# Copy, hooks, and the mute, stop and bounce tests (Stage 6)

The agent drafts; the founder picks, edits and posts. The agent never posts, replies or messages anyone (§5). In every appendix "he" and "his" mean Farza, the method's source; the operator is "the founder". Sources: METHOD §3.2, §3.5, §3.7, §3.8 and §4b.

## 1. The X post (step 21)

His order: "I built this thing", then what it is ("It's an AI teacher"), then what it does, then why it matters [07:53]-[07:58]. He cares about length and the parts of the story, "tweet poetry" [08:04]-[08:11]. His four launch posts (MEASURED, A1):

| Line's job | v1 Clicky launch (3.00M) | v2 no hands (3.83M) | v3 drawing (0.63M) | v4 dictation (2.95M) |
| --- | --- | --- | --- | --- |
| 1. Plain claim | "I built this thing called Clicky." | "Watch me control my computer with just my voice." | "We built an AI that can draw on your screen." | "Today we're shipping screen-aware dictation." |
| 2. What it is | "It's an AI teacher that lives as a buddy next to your cursor." | "This is the future of operating systems." | "It's a true personal tutor." | "First, we built a speedy speech-to-text (very fast, ~450ms)." |
| 3. What it does, or the turn | "It can see your screen, talk to you, and even point at stuff, kinda like having a real teacher next to you." | "No hands." | "Using Claude Opus we're able to draw polygons, point with pixel perfect accuracy, and walk users through complex steps directly on their screen." | "But, many products do this!" then "So we went further." |
| 4. Use or proof | "I've been using it the past few days to learn Davinci Resolve, 10/10." | "GPT-Realtime 2.0 is very, very underrated." | "Here's me learning Pythagorean Theorem + FL Studio." | "In Claude Code, it writes the prompt." |
| 5. Hand-off | (video under the text) | "Demo:" | "Demo:" | "Demo:" |
| Length | 276 | 151 | 279 | 280 |

- **Length is not the lever.** Three of four run 276-280 characters, and the biggest runs 151. Do not pad.
- **The template does not predict views.** His "Today we're shipping spatial context." post used v4's structure and got 294K, against v4's 2.9M six days later (R1 Insert F).
- **Story posts on X use almost no copy:** "hi my name is farza / i just wanted to introduce myself" (54 characters), "i went viral" (12) (A1).
- **No link in the post, by default.** It goes in the self-reply (§2): his habit in all four launch posts, never stated as a rule; test it (step 26). Post 16:9 to X [33:39].

```markdown
## X  (account: <@...>)   register: <raw | produced>   aspect: 16:9
1. <I built this thing called X. | Today we're shipping X. | Watch me <do Y> with just <Z>.>
2. <It's a <category> that <does what>.>
3. <It can <a>, <b>, and even <c>.>   or   <But, many products do this!> <So we went further.>
4. <I've been using it <time: the founder's own> to <real use>, <the founder's verdict>.> | <In <tool>, it <does>.>   # carries "why it matters" [07:58] (INFERRED mapping)
5. Demo:
chars: <n> X-weighted (<= 280; command in script.md §2)     link: none in this post (the default, step 26)
```

## 2. The self-reply that carries the link (step 26)

- **His habit, measured** (A1): in all four launch posts the URL came in a self-reply, 4 h 42 min to 7 h 46 min later, linking clicky.so (v1) or heyclicky.com/try (v2-v4). His texts, verbatim: "This is real, and shipped. Download below + try for free. It's really early, but, really magical. Enjoy." (v2); "P.S: Yes, this is shipped! Give it a try for free." (v3); "This is real + shipped btw. It's free to try." (v4).
- **Honest notes go here too** (P20). v1's reply read "You can give it a try below. https://clicky.so Few notes: 1. Uses Claude + Eleven Labs (very fast!!) 2. Screenshot only taken when you press hotkey. 3. High chance I run of credits lol." (A1); another v1 reply said "a bit dumb right now (only 10 messages of memory)" (W1 S2).
- **Why** (INFERRED): it keeps the scored post link-free. The evidence on X's link treatment has two halves: PPC Land's analysis of X's open-sourced code found 94% fewer views for posts with links; Musk said on 2026-07-29 that X had not penalized links "for over a year" (X1 §2.9). METHOD: "Test it yourself." The default stays link-in-reply; a founder who tries a link in the post logs it (`self_reply_delay_min: in-post`) for the 4-6 week comparison in `open-questions.md` q14 (UNTESTED).
- **Timing** (§8 q14): copy the link-in-reply habit, not the delay. The founder posts the reply when they are back at the thread, and the log records `self_reply_delay_min`. Comparing short and long delays waits for 4-6 weeks with several posts each way (UNTESTED).

```markdown
## X self-reply (the founder posts it, when they choose)
This is real, and shipped. <how to try it, one line>
<honest note, if any>
<this post's tagged link: <domain>/p/<post_id>?utm_source=x>
chars: <n> X-weighted, the URL counted as 23 (<= 280)
```

**No domain, open-source or CLI tool** (INFERRED from §8 q11; `setup-and-log.md` §3). "How to try it" is the install or upgrade command, and the link is the bare repo. Attribution then comes from GitHub's referrer report (sites, not posts; 14 days kept), so read it within 14 days:

```markdown
This is real, and shipped. `<install or upgrade command, e.g. brew upgrade <tool>>`
<honest note, if any>
https://github.com/<owner>/<repo>
```

With a domain, use a counting redirect per post instead (`<domain>/x/<slug>` → the repo).

## 3. Instagram, YouTube, TikTok, LinkedIn, Reddit (step 22)

Draft copy only for the platforms in `setup.md` `platforms`; a platform not on that list gets no copy and no export.

- **Instagram.** The caption is his first kickoff question [04:08]. His measured captions are short lower-case hooks, not descriptions: "im building a buddy for your computer cursor" (the 20.9M reel, R3 I6), "is my startup trash? let's decide." (R1 Insert H), "Put something out, see what happens." (R4 I-15). Captions are burned in on every Instagram version (step 42, INFERRED). Captions there are not clickable, so the tagged link goes in the bio, `/ig` (INFERRED; his bio link heyclicky.com/ig [32:47]).
- **YouTube.** Titles are mostly lower case: 3 of 11 long-form heyclicky titles end in a period ("introducing screen-aware dictation."), and none of the 8 Shorts titles does (MEASURED, C1 yt-dlp). Put a tagged link in the description: his dictation description linked a bare heyclicky.com, so his "like 20" percent cannot come from a tag in that description (INFERRED, §3.10). Most of his thumbnails show a face (R2 I7); for a voice-only founder, use a product frame (INFERRED, UNTESTED). For one long-form video he spent 3 of about 8 hours on thumbnails (W1 S10). YouTube is "a library that will last for decades" [32:16].
- **TikTok.** Burned-in captions; count leads and pipeline, not views. His design-agency call-outs brought about 50 leads from videos averaging about 4,000 views [30:33]-[30:48] (anecdote; a lead is not a deal, X1 §2.10). The call-out hook is not the TikTok default: it needs a niche already found in organic users first (step 52). For Tidbit, meme content "juices algo" but converted "much lower" (W1 S8, S9).
- **LinkedIn.** Cross-post demos and milestones; on screen his v2 cross-post had 75,318 impressions and a "$10K MRR … 9-weeks" post 50,677 (R4 I-9, I-16). Measure it like any channel. METHOD records no LinkedIn copy shape, so this skill reuses the X post (INFERRED, UNTESTED): the same five lines in the same order, full sentences allowed, the video uploaded natively (`out/li-16x9.mp4`), and this post's tagged link (`?utm_source=linkedin`) in the founder's first comment, mirroring the X self-reply habit. Log it as its own row.
- **Reddit.** The 2020 playbook ("find the right subreddit" [02:02]) and a place for the 30-second selfie [27:41]; unmeasured.

## 4. One-shot channels and the teaser

- **Launch HN, Product Hunt** (step 11): only for substantive releases. YC gives each company one Launch HN (DOCUMENTED, X1 §2.1); Product Hunt reportedly expects about six months between launches (forum post, search summary, X1 §2.1). Spending them only on substantive releases is X1's advice; it matches his daily demos plus a polished launch "maybe once a quarter" [15:57] (step 11). Each takes whatever finished asset the release has, the produced demo or a launch-film hero (§6). Write to the channel's own rules, not his X order: HN's guide says "Don't write in a marketing, sales, or PR style" (X1 §2.1). The caption-first check (`script.md` §2) finds the one line.
- **Teaser** (W1 S5): "Something new. See you tomorrow, link below." with a 33-66 s clip the day before a dated release, then a livestream on the day; his Apr 22 and May 13 2026 teasers had 174K and 102K views.

## 5. Hook types (§3.5 "Hooks by register")

These open both the post and the video. He warns against copying his hook as a formula [09:54]; the stop test decides, not the template.

| Hook | Shape | His example | Use when |
| --- | --- | --- | --- |
| Demo hook | A greeting, the thing, one line on what is literally on screen | "Hey, everyone. So this is Clicky." (v1); "Hey, so today we're adding dictation to HeyClicky." (v4); "Alright, check this out, no hands, ready?" (v2) | The default for raw takes and feature demos |
| Curiosity gap | A time jump that withholds the outcome | the "two months ago…" reel he would reuse "as like a template" [23:11]-[23:26]; "Two weeks ago I was in my apartment…" (R4 I-15) | A newcomer's story; no prior hit needed |
| Story hook | Recent social proof, self-deprecation, a credential the niche knows | "Last week I went super viral for an idea that I built that I thought was actually kind of terrible, and this week I'm somehow in Y Combinator." [21:26]-[21:31] | Only with a real prior success; it builds survivorship in |
| Niche call-out | Name the viewer's role | "hey are you the founder of a design agency stop right there let me show you something really cool" [30:33] (as transcribed) | Not offered, not even as a held draft, until `setup.md` or a weekly review records a niche found in organic users (step 52; out of version one, `open-questions.md` q13) |

**The two eligibility words, as METHOD defines them** (§3.5; no follower or star count is given, and the skill sets none):
- **Real prior success** = a recent hit or credential to cite that the niche recognizes, as in his "went super viral … somehow in Y Combinator". It must be a dated entry in `claims.md` (a post's measured views, a funding round, a known user who said so). METHOD sets no star or follower count, so a count such as "400 stars" is the founder's call through the question below, not the agent's.
- **Newcomer** = anyone with no such entry: "A newcomer has no viral hit or credential to cite" (§3.5). The curiosity gap is open to everyone; it is the newcomer's version because it needs no prior hit.
- Unsure whether something counts → ask the founder: "Would a stranger in your niche recognize <it> as a success?" Yes → it may open a story hook, logged in `claims.md`; no → newcomer.

**Every anecdote, time or event in a hook is the founder's own and true** ("Two weeks ago…", "Last week…"). The agent writes it as a `<slot>`, never as a fact, and the founder fills it or the variant is dropped (hard rule 4; P20).

**The variants are the Stage 1 angles** in `candidate.md` (about five, `script.md` §2): there is no second set here. Stage 6 writes the full post for the founder's pick and keeps the others as rewrites for the stop test in §6.

## 6. The stop test: the feed mockup (steps 23-24; the founder's hands)

His "number one rule, regardless of Twitter, Instagram, YouTube, anything" [08:59] (P6, Anecdote: W1 found the feed-mockup test nowhere outside the interview, so it is UNTESTED, §7.6). He edited a real post's text in his own feed, then scrolled (MEASURED, R2 §3.2). Send the founder these steps; the agent never runs them in the founder's session (§8 q4):

1. Open x.com in your own browser, logged in, on the home feed.
2. Scroll until you find a stranger's text post at a normal spot in the feed.
3. Right-click its text, choose Inspect, and double-click the text node in DevTools.
4. Paste the draft's first lines and press Enter. The change is local to your tab; nothing is posted, and a reload undoes it.
5. Close DevTools, scroll up a little, and scroll back down at your normal speed.
6. Answer two questions: "did my eye stop?" [08:50] and "would I read the first sentence?" [09:06]. Reply yes or no to each.

On a no, rewrite line one and run it again (step 24). Expect several angles before one stops you (INFERRED).

**When to run it.** The test reads the post's text. If the post's line one is also the video's spoken first line, run it on that line before Stage 3, so a rewrite can still change what gets recorded: in METHOD's order steps 21-24 come before recording (step 41), though the numbering is not a stated timeline (INFERRED). Run after the take, a rewrite changes only the post, and the post's line one may then differ from the spoken hook; that is allowed, since the two are read in different places (the text above the video, the voice inside it). The test's value is the real feed around the post (§5 rows 21-24). agent-browser's default session is a fresh profile that cannot see the founder's feed. Its CDP mode (`--cdp`, agent-browser "CDP Mode") can attach to a logged-in browser, and that is exactly the drive of the founder's session this rule forbids: never attach `--cdp` to the founder's browser for this test (hard rule 1). So the most the agent can do alone is a static local page with the draft between a few made-up posts, screenshotted: a weaker pre-check, labeled `stop_test: mock` in the log.

## 7. The mute test (step 25)

Watch it muted at scroll speed and say aloud the few words your brain picks up. His read of the drawing video was "guy in front of blackboard, AI, draw, screen … Claude Opus, demo, click" [33:54]-[34:07], because "nobody's reading this entire … damn thing" [34:07]-[34:11]. A third-party analysis comparing Clicky with his failed Tidbit puts it as "Distribution only carries what people understand on mute." (W1 S27; not Farza's words).

- **Planned mute-read words** go in `script.md` in Stage 2: a prediction from the 10-second plan.
- **Measured mute read**, Stage 6: the agent samples the take's first 3 s and first 10 s with no sound and lists what they show (on-screen words, captions, the visible action), beside the planned words.
- The founder confirms the read. A gap between planned and measured decides the `captions on X` row left at "after the mute test".
- If a muted viewer cannot tell what the thing is, change the first frame, the zoom or a caption, not the copy.

Optimizing for one platform did not predict where a video did well: the drawing video he calls "super optimized for twitter" [33:50] was his weakest measured X demo (629K, A1) and did "even better" on Instagram [34:17].

## 8. The bounce test (step 32)

On your video and on others': "am I bouncing, when am I bouncing?" [22:48]. Cut or rework whatever causes it. It is a human reaction (§5 rows 30-40), so it is the founder's. Its first run is during the Stage 5 watch of the master, so the agent can rework the marked spans before export; a bounce found here returns to Stage 5. After posting, YouTube's Intro and Dips reports show where viewers leave (X1 §2.4).

## 9. The swipe file: `swipe.md` (step 40)

Watch Reels "not for entertainment, just to kind of study" [22:54]. When a hook works on the founder, note its device (lighting, caption placement, a "two months ago" curiosity gap) and turn it into a template for your own story [23:05]-[23:26]: the device, never the reference's shots or lines (`boundary.md` §3, the 10-02 "copy cat" row). The agent records one line per hook: the link (read X posts with `read-twitter`), the device, and which register it maps to.

## 10. Thread replies (step 49)

Walk away from the view counter, not from the thread. His measured behavior (A1, W1): the link reply 4 h 42 min to 7 h 46 min later; under v2, "I'll fix tomorrow I'm going to sleep lol", then two days later "Okay I fixed it"; within a week of the launch he had talked to the retained users (W1 S3). On request the agent drafts answers to thread questions and one line per small fix, in his plain register. Each is a message to a third party, so it is drafted through `outbound-drafting`, whose read-the-medium-live rule fits a reply to someone else's words: read the thread as it is now, not from notes. HAND-OFF: the founder pastes the URL of each reply to answer (nothing here can list other people's replies without a login). The agent reads each one live with `curl -s https://api.fxtwitter.com/2/thread/<reply_id>` (no login, and a live read outbound-drafting's hook accepts), never through x.com in the founder's browser, Dia (`cc-dia-act`) or a browser MCP. The founder posts the answers, ships the fixes and says so in the thread. DMs and emails to retained users go the same way, and the founder sends them (§8 q3).
