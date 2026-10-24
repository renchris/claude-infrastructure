<!-- markdownlint-configure-file { "MD013": false } -->

# C1: skeptic review of S0-method-draft-v1 (2026-10-24)

Slot C1, adversarial reviewer. Target: `agents/S0-method-draft-v1.md` (624 lines, read in full). Checked against `/tmp/farza-2026-10-24/transcript.txt` and R1, R2, R3, R4, A1, W1, X1 and K1, plus `skills/launch-film/SKILL.md`, which the draft cites for its boundary in §6. Scratch files are in `/tmp/farza-C1/`.

**How I checked (MEASURED, this run).**

- **Timestamps.** I took 167 quoted phrases with their cited `[mm:ss]` from the draft (`/tmp/farza-C1/cases.tsv`). I matched each against the transcript with `python3 -I /tmp/farza-C1/check.py` (output: `/tmp/farza-C1/check-out.txt`).
  - 161 land on the cited line, allowing 1 s of slack.
  - 6 sit 2-5 s after the cited time, because the draft cites the start of the sentence: [06:40]→06:43, [09:54]→09:56, [10:37]→10:40, [12:07]→12:12, [12:48]→12:52, [37:18]→37:22.
  - None is wrong. **Timestamp discipline is the draft's strongest feature.**
- **The on-screen script.** I viewed `/tmp/farza-S0/f-666.jpg`. It matches the draft's transcription, typos included.
- **heyclicky YouTube.** I listed the channel read-only with `uvx yt-dlp@latest --flat-playlist` on `@heyclicky/videos` (11 videos) and `@heyclicky/shorts` (8). I also fetched upload dates for `oQHcQYQgQ50`, `km54y7Xd_7g` and `eC9dM0uJMiU`. Output: `/tmp/farza-C1/yt-*.txt`.
- **agent-browser.** `agent-browser --help` lists `record start <path> [url]  Start video recording (WebM)`.
- **launch-film.** I grepped `skills/launch-film/SKILL.md` for each section the draft cites.

Verdicts: SUPPORTED, MIS-TIMESTAMPED, MISQUOTED, OVERSTATED, UNSUPPORTED, CONTRADICTED. I also use MISATTRIBUTED (the right words, credited to the wrong source or context) and ARITHMETIC (a sum is wrong).

---

## 1. Verdict table

### 1.1 Front matter and summary (§1)

| # | Claim (draft §) | Verdict | Evidence | Fix |
| --- | --- | --- | --- | --- |
| 1 | "I checked every cited time against the transcript" (§1 Labels) | SUPPORTED | 161/167 exact; 6 within 2-5 s, citing the sentence start (MEASURED, check.py) | None. State the sentence-start convention once. |
| 2 | "'Vikrant' is the ASR spelling, unverified" (§1; repeated in §3.12) | CONTRADICTED | R3 I11 reads a Clicky UI tile on the _heyclicky grid at 24:52: "Evening, Vikrant. One of your Clickys is working right now" | Say "spelling seen on screen in a product UI tile (R3 I11)". R4 and K1 say "never on screen"; that is wrong. |
| 3 | He "judges a post by downloads, retention and conversion per channel, never by views" (§1 summary) | CONTRADICTED | His own challenge uses views as the learning signal: find the one that passed 1,000 views and base the next one on it [46:22]-[46:36]. Every example he shows was picked by view count (§7.5 row 5 admits this). | Say "judges by conversion where he can measure it; uses views as the early signal and to pick examples". |
| 4 | "Videos open on the thing itself within two to three seconds" (§1) | OVERSTATED | A1: named by 2.3-3.6 s in 5 of 6 videos (v3 3.5 s, v6 3.6 s). v5 at 5.8 s. | Say "by about 3.5 s in 5 of 6". |
| 5 | "Production level ... ranges from one raw take to 52 cuts a minute and did not predict views" (§1) | OVERSTATED | §7.2 calls this "a sample-size caveat, not a finding", across n=4 demos. The 52 cuts a minute is v6: vertical, and posted from a different, smaller account (row 22). | Carry the n=4 caveat into the summary and drop v6 from the comparison. |

### 1.2 Principles table (§2)

| # | Claim (draft §) | Verdict | Evidence | Fix |
| --- | --- | --- | --- | --- |
| 6 | P1, P2, P3, P9, P11, P13, P14, P16, P18: quotes and grades | SUPPORTED | Every timestamp checks out (check.py). The grades match X1 §2 and W1 S7, S11, S14 and S24. | None. |
| 7 | P4 "check this out" graded "Measured (A1)" | OVERSTATED | A1 measures where the *phrase* occurs, not that a raw moment was captured. In v4 it is a line scripted three days ahead [14:00]-[14:05], the opposite of the raw register. | Grade it Anecdote. Say the phrase is his scripted pivot line. |
| 8 | P5 "Glossier's and Stripe's relaunch cadence supports it" | OVERSTATED | X1 §2.3 cites Glossier for launch *frequency* (its "constant drumbeat"). That says nothing about showing process rather than results. | Grade it "Anecdote; copying risk documented". |
| 9 | P6 stop test "Corroborated in direction" by TikTok and Facebook ad data | OVERSTATED | The ad data is about the key message in the first 3 s of a *video* (X1 §2.4). P6 is about whether the first *sentence of the post copy* stops the eye. W1 §3 finds the feed-mock test nowhere outside the interview. | Move that corroboration to P7. Grade P6 Anecdote. |
| 10 | P7 key detail visible and moving within 3 s, graded "Measured (A1)" | OVERSTATED | Only v1 has it (zoom at 2.2 s). v2 has no zoom. v3 and v4 open on a face, with the product close-up at 3.50 s and 4.04 s (A1). | Grade it "Measured, n=1 (v1)". |
| 11 | P8 "demo starts at 8-10%", and "the 'why' (the turn) often comes at 18-26%" | OVERSTATED | Demo at 8-10% holds for v1, v3 and v4 only; v2 starts at 2%, v6 at 36%, v5 has no demo. Turn at 18-26% is v4 alone. v3's turn is at 60.3 s of 140 s, which is 43% (A1). | Report it per video. "Often" rests on n=1. |
| 12 | P10 "v6 and the 20.9M Instagram reel follow" the formula | OVERSTATED | v6 opens "Today we crossed over 5 million views" (A1), with no "who I am". The reel's "who I am" is at most a YC credential (R3 §3). Only v5 states who he is, and v5 is nothing else. | Say "no measured video states all four steps". |
| 13 | P12 "Every measured demo has a turn" | OVERSTATED (minor) | A1 pattern 4 counts v2's jokes ("$140 in a day") as turns. v2 has no problem statement. | Say "3 of 4 demos have a turn; v2 has comic beats". |
| 14 | P15 audio first, "Corroborated (X1)" | SUPPORTED externally, unchecked against his own practice | A1 did not assess which mic v1 and v2 used. v1 is an un-normalised raw take at -32 dBFS mid, 14-16 dB under the edited videos (A1). R4 §3 sees "white earbuds" in v2's webcam bubble. | Add "his two biggest X hits are unverified against his own 'AirPods don't count' rule". |
| 15 | P17 horizontal 0.63-3.83M views on X against vertical 65-73K; "Topic is a confound" | OVERSTATED: a bigger confound is missing | v6 was posted from **@heyclicky** (A1 inventory), which has 15,584 followers, against 129,259 for @FarzaTV (W1 §4, MEASURED fxtwitter). | Add the account confound. The only same-account comparison is v5 against v1-v4, which is n=1 and a different topic. |
| 16 | P19 counter-evidence: Buildspace "is now listed 'Inactive' on YC" | OVERSTATED as counter-evidence | Buildspace closed by his choice, with over 2 years of cash (W1 S22). §7.4 says so; the table omits it. | Carry the §7.4 caveat into the table. |

### 1.3 Procedure, §3.0-§3.2

| # | Claim (draft §) | Verdict | Evidence | Fix |
| --- | --- | --- | --- | --- |
| 17 | Step 1 tiers: daily [16:06], biweekly [26:51], quarterly [15:57], teaser (W1 S5) | SUPPORTED | check.py; W1 S5 | None. |
| 18 | Step 1 "The quarterly tier is where our launch-film skill fits" | CONTRADICTED | His quarterly "polished launch" is "something I'm really proud of ... talked about properly" [15:57]-[16:06], made with his filmmaker, whose job covers shooting and sets [43:41]-[43:47]. launch-film §0 item 11 rules out "a human shoot or studio". | See row 79. |
| 19 | Step 4 per-channel link paths (/ig [32:47], /x on the profile) | SUPPORTED as profile links; CONTRADICTED as his post practice | His X self-replies link `clicky.so` (v1) and `heyclicky.com/try` (v2-v4) (A1). The YouTube dictation description links a bare `https://www.heyclicky.com/` (R2 §3.7, yt-dlp). A `/yt` channel link exists (R1 Insert C) and the draft misses it. | Tag each *post*, not just each profile. Note that his 20% YouTube figure cannot come from a tagged link in that video. |
| 20 | Step 5 post log with per-post "day-5 retention" | UNSUPPORTED as runnable | Per-post retention needs per-post attribution and a product event. R4 I-15 shows the kind of chart needed (`user_message_sent Unique 1,474`). No step sets this up. | Add an instrumentation step: per-post link, signup event, retention query. |
| 21 | Step 6 a "post it anyway" person, from Aaron [06:19]-[06:29] and Vikrant [14:26]-[14:33] | SUPPORTED | Plus [14:33]: "it's good to have the team also be really like, hey ... we're going to put it out" | None. |
| 22 | Step 9 team update: "keep the effort to about 10 minutes", plus a measured shape of B-roll, a title card, captions and a group shot | CONTRADICTED within the step | R3 I12 and contradiction 3: graded footage from several locations is "more produced than 'made in 10 minutes' suggests". | Offer two versions: a 10-minute phone update, and the produced one with its real cost unstated. |
| 23 | Step 9 cadence "every two weeks" [26:51] | SUPPORTED, but tension dropped | The clip is titled "everything we built **this week**" [24:52]. W1 S13 planned "one weekly update". | Note weekly against biweekly. |
| 24 | Team update reach (implied by "almost a million views on Instagram" [25:22], host) | OVERSTATED by omission | The YouTube copies: "this is everything we shipped." 1,900 views and "shipping a ton and fixing 200+ bugs" 913 (MEASURED, yt-dlp this run); 787 on screen in the cold open (R1 Insert C/D). | State the YouTube counts beside the host's unshown Instagram claim. |
| 25 | Step 10 "Product Hunt expects about six months between launches (DOCUMENTED, X1 §2.1)" | OVERSTATED label | X1 §2.1: a forum post, "search summary, not opened". The step is X1's advice, not Farza's. | Relabel it "reported (forum, unopened)" and "X1's advice". |
| 26 | Step 11 "If it does not 'sound good on paper', rethink the feature" [04:28]-[04:32] | MISATTRIBUTED | In the interview, "sounds good on paper" is why "we kind of know it's a hit" [04:28]-[04:32], and he adds "not that ... needs to go viral" [04:15]. The *gate* comes from W1 S7 and S14. It also leans on a prediction that §7.1 calls weak. | Credit the gate to W1. Reconcile it with §7.1: make it a clarity check, not a hit predictor. |
| 27 | Step 12 grounding frame: "For Clicky it was a small blue cursor popping in and saying hi. It becomes the first-frame design in §3.6" | MISATTRIBUTED and CONTRADICTED | W1 S7 describes the Oct 2025 *precursor* demo (S31), not Clicky. v1's first frame is Xcode, chosen for the audience [09:13]-[09:22] (A1). | Say "the precursor's frame". Remove "becomes the first-frame design". |
| 28 | Step 14 same-day posting deadline | OVERSTATED | One 2025 anecdote (W1 S7). The Clicky demo itself sat for weeks (W1 S3; "tabled it for another two weeks", S19). | Present it as an optional forcing device, noting that his biggest hit broke it. |

### 1.4 Procedure, §3.3-§3.5

| # | Claim (draft §) | Verdict | Evidence | Fix |
| --- | --- | --- | --- | --- |
| 29 | §3.3 "The other two [registers] are seen only inside the interview" | CONTRADICTED for the niche call-out | No TikTok is shown: "he did not have the account open ... no insert between 29:11 and 31:13" (R4 #8). | Say "described only, never shown". |
| 30 | Produced feature demo: "Every line scripted three days ahead [14:00]-[14:05]" | OVERSTATED | That quote is about v4 alone. Scripting for v3 is unknown. | Say "v4: every line ..." |
| 31 | Vertical story "45-52 cuts a minute" | OVERSTATED | v5's 45.5 "overcounts archival" (A1). | Add the caveat in the table, not only in §4. |
| 32 | Niche call-out, Effort "Low" | UNSUPPORTED | No effort figure appears anywhere. | Delete it or mark it unknown. |
| 33 | Minimum version selfie [22:19]-[22:24] | SUPPORTED, caveat dropped | He adds "I think the effect may not have been as big" [22:28]. | Add the caveat. |
| 34 | "The challenge version is 30 seconds in selfie mode [27:30]-[27:37]" | MISATTRIBUTED | [27:30] is his standing "how do I start" advice (R3 #61). The challenge [46:00] says "spend 10 minutes" and gives no length. | Separate the two. |
| 35 | Step 15 "Default to the raw screen take" | CONTRADICTED | "most of our videos we make for instagram" [33:23]; W1 S6 "posted this 2-months ago on insta". | Make the default his: vertical for Instagram. Use the raw take for a fresh on-screen moment. |
| 36 | §3.3 "five registers" | Incomplete | W1 S10: long-form YouTube story, about 8 h including 3 h on thumbnails. R4 I-14/I-15: fast-cut progress reels. W1 S4: open-sourcing as a second launch. | Add them, or state that they are excluded. |
| 37 | Step 16 writing ladder [45:20]-[45:36] | SUPPORTED; tension dropped | The same passage opens "spend as much time possible before the video writing it" [45:14]. W1 S10: script in 30 minutes. W1 S8: "Hasan ... gives me a script". | Note the range of time and who writes. |
| 38 | Script transcription and "yesterday" [10:37] | SUPPORTED | Viewed `/tmp/farza-S0/f-666.jpg`; "yesterday" is at 10:40 in the sentence that starts at 10:37. | None. |
| 39 | Step 17 "the videos actually shown run 100-140 s" | OVERSTATED | At [11:19] only v1 (100 s) had been shown. v4 (120 s) is shown at 12:56 and v3 (140 s) at 33:44 (R2 I8, R4 I-6). | Say "v1 is 100 s; the next video shown is 120 s". |
| 40 | Step 17 "10-28 s for 140 s (arithmetic)" | ARITHMETIC | 10-20% of 140 s is 14-28 s. | Fix the figure, or say "10 s (his rule) to 28 s (20%)". |
| 41 | Step 19 "Deliver from memory, loosely", INFERRED from [11:34] against the page | OVERSTATED | [11:34] is him paraphrasing his script in conversation, not delivering the video. That video was never located or measured. | Weaken it to "he paraphrases his own script". Flag the unmeasured video as a gap. |
| 42 | Step 19 Rifkin & Du: an authenticity premium, "so the script must stay invisible" | OVERSTATED | X1 §2.5: the same study finds people "expect spontaneous work to be lower quality", and its subjects are entertainment performers. | Give both halves and the domain. |
| 43 | Step 20 "The measured X copy (A1) runs 276-280 characters" | OVERSTATED (selective) | v2, the biggest X hit at 3.83M, has 151 characters (A1). §4b lists that number. | Say "3 of 4; the top post is 151". Do not imply that filling the tweet helps. |
| 44 | "YouTube titles are lower-case sentences ending in a period" (MEASURED, R2 §3.6) | CONTRADICTED | 3 of 11 long-form titles end in a period, and 0 of 8 Shorts (MEASURED, yt-dlp this run). The example "we built an ai that draws on your screen." is on neither current @heyclicky list. R2's grid came from a *search* page, which can mix channels. | Say "lower-case; some end in a period". Drop or re-source the example. |
| 45 | Story hook: social proof, self-deprecation and a niche credential [21:26]-[21:47] | SUPPORTED as his; OVERSTATED as a general hook | It needs a prior viral hit and a credential (YC), which a newcomer lacks. That is survivorship built into the template. | Mark it "needs prior success"; give the curiosity gap as the newcomer's version. |
| 46 | Step 22 "Expect several angles ... (W1 S7: 'drafted hella tweets')" | MISAPPLIED (minor) | S7's drafting happened before building, not as rewrites after the feed test. | Label it INFERRED. |
| 47 | Step 23: the third-party test as "can a stranger tell what it does on mute?" (W1 S27) | MISQUOTED | That wording is W1's own INFERRED paraphrase. The article's line is "Distribution only carries what people understand on mute." | Quote the article line. |
| 48 | Step 23, using the drawing video as the example of the mute test | Tension dropped | The video he calls "super optimized for twitter" [33:50] was his weakest X demo (629K, A1) and did "even better" on Instagram [34:17] (R4 contradiction 3). | Add: optimising for X did not predict where it performed. |
| 49 | Step 24 self-reply link "4 h 40 min to 7 h 46 min" | SUPPORTED (trivial) | The per-post values are 4h42, 5h40, 6h54 and 7h46 (A1). He never advises this; it is a measured habit. | Write 4 h 42 min. Label it "his habit, never stated". |

### 1.5 Procedure, §3.6-§3.9

| # | Claim (draft §) | Verdict | Evidence | Fix |
| --- | --- | --- | --- | --- |
| 50 | Template A rows (v1 timings, zoom 2.2 s, "So check this out" 9.6 s) | SUPPORTED | A1 v1 | It is in substance n=1. v2 shares only the first 2.5 s. Say so. |
| 51 | Template B "Medium shot of the founder" (v3 and v4) | OVERSTATED | Who presents v3 is unestablished: a comment reads "Well done Zain" (R4 I-8). §7.2 admits this, but the template asserts it. | Say "presenter (identity unverified for v3)". |
| 52 | Template C, the Instagram template, from v6 | OVERSTATED | v6's only measured performance is 73K on X from the small @heyclicky account. Its Instagram performance is unmeasured. | State that the template's performance on its target platform is unknown. |
| 53 | Step 27 norm: "the 'why' turn by about 25%" | CONTRADICTED | v3's turn at 43% (A1). Only v4 meets it. | Drop it, or report per video. |
| 54 | Step 27 norm: "the key detail visible and moving by 3 s" | CONTRADICTED | Fails v3 and v4, which open on a face (A1). | Restrict it to screen-led takes. |
| 55 | Step 27 norms: "demo by about 10%" and "soft CTA in the last 3-7%" | OVERSTATED | Demo: v6 at 36%. CTA: none in v2, the top X hit (A1). | Give per-video pass/fail. |
| 56 | Step 27 norms as a whole | OVERSTATED (survivorship) | Measured only on hits picked for the interview. R1 Insert F: the same copy template gave 2.9M and 294K, "a 10x spread". A1 lists unmeasured posts at 1.19M, 344K, 202K and 145K. W1 lists more: Tidbit 342K and the precursor 453K. | Measure 4-6 lower performers as controls before calling anything a norm. |
| 57 | Step 28 "Use the full formula for story videos and the short form for feature demos" | UNSUPPORTED as his advice | He says "my formula is always the same" [21:51]. The split is the synthesizer's. | Label it INFERRED. |
| 58 | Steps 29-34, 36-37 quotes and beat list | SUPPORTED | check.py; A1 v2; R4 §3 | Step 34's "0.7-1.3 s" rests on 3 luma cuts in a 10 s excerpt (R4 I-14). Say that. |
| 59 | Step 35 self-deprecation: "v1's 'I'm not sure why I recommended the Sony LUT' aside" | OVERSTATED (likely mis-heard) | Clicky, not he, recommended the LUT, at 75 s (A1 v1 structure). "I recommended" is probably ASR for "it recommended". If so, this is an on-camera admission of a product error. | Re-listen at about 86.8 s. If confirmed, make it its own technique: admit the product's mistake. |
| 60 | Step 39 "not karaoke-style word-by-word captions" | OVERSTATED | True for A1's six. R3 I7 calls the 20.9M reel "word-level captions throughout", and R1 Insert D calls the team update's captions "word-by-word". | Say "1-4 word chunks; the reel and team update read as word-level". |
| 61 | Step 39 "a music bed that dips at the turn or reveal" | CONTRADICTED for v4 | v4's dip is at 56-66 s; its turn is at 21-30 s and its reveal at 31 s (A1). "Music" itself is INFERRED from side-channel level. | Say "v3's dip coincides with the turn; v4's does not". |
| 62 | Step 39 raw takes "get no captions" | Unresolved tension | §7.4 and X1 §2.11: as much as 85% of feed video plays muted, so "captions ... matter as much". The mute test is step 23. | Decide it: caption raw takes for Instagram, or say why not. |
| 63 | Step 40 "End cards ... say 'try it for free'" | OVERSTATED | Only v3. v4's end card reads "clicky" then "heyclicky" (A1). | Say "v3's end card". |
| 64 | Step 41 "the YouTube channel was three days old when the dictation video went up [12:07]" | CONTRADICTED | "we are a real company now" (`oQHcQYQgQ50`) was uploaded 2026-06-28, 16 days before the dictation video (`km54y7Xd_7g`, 2026-07-14). "hi i'm heyclicky" is older still in the newest-first list. MEASURED, yt-dlp this run. | Quote him, flag it as contradicted, and keep "a small channel is fine" (872 subscribers). |
| 65 | Step 41 "At the start, post the same video everywhere [12:26]" | MISATTRIBUTED (minor) | [12:26] is about the dictation video, not about the start. | Reword it. |
| 66 | Step 42 post even if you think it is bad, from two surprise hits | OVERSTATED (survivorship) | n=2. We do not know how many posts he thought were bad and that stayed bad. | Rest the step on the volume argument (Buffer tail, X1 §2.7), not the two anecdotes. |
| 67 | Step 43 "By the time I hit post, I've already forgotten it" [17:05], used as a step | CONTRADICTED by A1 | Link self-replies 4 h 42 min to 7 h 46 min later. A second v1 reply 10 min after the first. v2's follow-ups "I'll fix tomorrow I'm going to sleep lol" and, 2 days later, "Okay I fixed it" (A1). He checked retention and talked to users within days (W1 S3). | Say "walk away from the counter, not the thread". Add a step for handling the thread. |

### 1.6 Procedure, §3.10-§3.13

| # | Claim (draft §) | Verdict | Evidence | Fix |
| --- | --- | --- | --- | --- |
| 68 | Step 44 "0.23% of the 3.0M viewers downloading" | OVERSTATED | Views are impressions, not viewers. 7,000 is his recall ("I think"). The post had no link for 4 h 42 min. The repo went public the next day, with 7,772 stars now (W1 S4), so downloads cannot be attributed to the X post. X1 labels this ratio MEASURED arithmetic. | Call it "a ratio of two unlike numbers, upper-bound attribution". |
| 69 | §3.10 X row | SUPPORTED, half the evidence dropped | X1 §2.9: PPC Land's code analysis found posts with links got 94% fewer views. The draft gives only "gone 'for over a year'". | Give both halves. |
| 70 | §3.10 Instagram row: drawing video "performed even better" [34:17] | OVERSTATED | On screen: 27.4K Instagram likes against 5.1K on X (R4 I-8, I-7). "Millions of views" [34:25] is not legible. | Say "by likes on screen; views not shown". |
| 71 | §3.10 / §7.1 audience sizes | Omission | farza954 has 87.6K Instagram followers (R3 I10). Instagram is the 70% channel, yet §7.1 lists only X and YouTube. | Add it. |
| 72 | §3.10 LinkedIn "Not discussed by him" | OVERSTATED (minor) | He names LinkedIn among the platforms where users live [02:23]. | Say "not discussed for conversion". |
| 73 | §3.10 platform list | Omission | Reddit is named at [02:02] and [27:41]. | Add a row or exclude it explicitly. |
| 74 | Step 48 weekly review, cited [46:26]-[46:36] | MISATTRIBUTED | That passage is the day-30 look-back. The weekly cadence is X1 §2.7's advice. | Credit X1. |
| 75 | §3.12 "Mic 3 from $169 (MEASURED, dji.com)" | OVERSTATED | K1: the price was "marked `out_of_stock`. I did not establish which configuration". | Add both caveats. |
| 76 | §3.12 Resolve "until Nov 20" labelled MEASURED | OVERSTATED label | K1: the price is MEASURED, but the end date is DOCUMENTED by third parties. | Split the label. |
| 77 | §3.13 challenge steps 50-55 | SUPPORTED | check.py | Note that its success metric is views, which contradicts row 3. |

### 1.7 Reference, agent split, boundary and caveats (§4-§7)

| # | Claim (draft §) | Verdict | Evidence | Fix |
| --- | --- | --- | --- | --- |
| 78 | §4a and §4b values | SUPPORTED | All six rows checked against A1's cross-video table | Add an "account" column (FarzaTV or heyclicky). "What the tables say" bullet 3 inherits the account confound. |
| 79 | §6 "Use launch-film for ... the quarterly 'polished launch' tier [15:57]" | CONTRADICTED | Same as row 18. His polished launches have the founder on camera and a filmmaker. launch-film §0.11 bans a human shoot. [15:57] says nothing about format. | His quarterly tier is the produced register at higher effort. launch-film is a separate, optional, no-human asset: a README hero or a first public face. |
| 80 | §6 "Use neither for a Launch HN or Product Hunt post. Those are copy" | UNSUPPORTED, and contradicts step 10 | No source says Product Hunt is copy only. Step 10 sends one-shot channels to the quarterly tier, which step 1 maps to launch-film. | Pick one rule and apply it in step 10 and §6. |
| 81 | §6 boundary covers launch-film only | Omission | `skills/demo-recording` (silent README WebP loops; K1 §1.1) is the sibling that overlaps the raw screen take. | Add a third column, or a rule for which skill owns README demo loops. |
| 82 | §6 "Approval: One operator yes at each gate: story, look, board, stills, motion, sound, render, README" | MISQUOTED | launch-film §4: the stills check is "internal ... No operator question unless the look itself changed". | Drop "stills". |
| 83 | §6 timings (70.6 h look, 81.4 h render) and truth rule (§1.6) | SUPPORTED | launch-film §2, §10, §1 item 6 (grep) | None. |
| 84 | §6 rule 6 "post it ... with its caption written first (step 11)" | MISAPPLIED | Step 11 is a gate before building, not a posting step. | Cite step 20 and step 21. |
| 85 | §5 "Record scripted web flows ... (agent-browser)" | SUPPORTED | `agent-browser --help` lists `record start <path> [url]` (WebM), MEASURED this run | None. |
| 86 | §5 steps 4-5 and 44-46: the agent can "compute conversion per channel from analytics it can read" and "Pull numbers" | OVERSTATED | No Instagram or TikTok reader exists. W1 Gaps: "Instagram needs a login". fxtwitter returns public counts, not link clicks. Instagram is the 70% channel. | Say "the agent can only read public X and YouTube counts; Instagram and TikTok need the founder's export". |
| 87 | §5 steps 25-27 "Lint the cut with A1's method" | OVERSTATED | A1 classified face and screen by eye, corrected cut counts by hand (app switches, archival footage) and re-ran whisper after it compressed timestamps (A1 traps). The turn and the demo start were human reads. | Say "measures cuts, word times and loudness; the turn and demo start need a human". |
| 88 | §5 step 38 "add zooms in post (HyperFrames or Remotion)" | OVERSTATED | K1: "a custom job each time". Remotion being installed was not measured. | Add the caveat. |
| 89 | §5 steps 16-18 "Write the lines in your own voice" | CONTRADICTED by his practice | W1 S8: "Hasan just puts the camera in my face, gives me a script". W1 S9: about 4M TikTok views in 7 days. | Make it a test (§8 Q10), not a rule. |
| 90 | §5 steps 20-22 "build a local, static mock of a feed card" | OVERSTATED as a substitute | The test's value is the real surrounding feed (R2 §3.2). | Say "a weaker proxy". |
| 91 | §5 "outbound-drafting skill" | SUPPORTED | `skills/outbound-drafting/SKILL.md` exists | None. |
| 92 | §7.1 "The rule that holds up is 'post anyway', not 'predict'" | OVERSTATED | It rests on the same two surprise hits (row 66). | Ground it in the volume data. |
| 93 | §7.1 "Only the hits are shown" | OVERSTATED (minor) | He also shows the Zip misses (10-23 likes) and the 294K spatial-context post (R1 Insert F). | Say "mostly hits". |
| 94 | §7.2 "His filmmaker made the videos" | SUPPORTED; history dropped | He had a collaborator before Vikrant too: W1 S10 ("all Aiden"), S30 (credited to @wordisbonz), S8 (Hasan). | Add it: he has never worked solo at scale. |
| 95 | §7.3 anecdote table | SUPPORTED; incomplete | Missing: "thousands of people flood my app" [40:39]; 4.6M Instagram views for v2 [36:50] (not tied on screen, R4 I-13); "millions" for the drawing video on Instagram [34:25]; "three [agencies] that found us naturally" [29:48]. | Add them. |
| 96 | §7.4 NYT "US$80,000 shoot (DOCUMENTED via a reprint)" | OVERSTATED label | R1: "search-result summary of The Star's reprint; I did not open the page". | Say "reported in a search summary". |
| 97 | §7.5 tensions | SUPPORTED rows; incomplete | Missing: forgetting after posting against A1's replies (row 67). Not wanting daily video work [39:22] against the daily challenge (R4 #8). "Instagram needs quick edits" against his own fast-cut reels (R4 #6). The X-optimised video doing better on Instagram (row 48). Founder writes the script against W1 S8. A 30-minute script (W1 S10) against three days ahead. | Add them. |

---

## 2. Prioritized fix list

### P0: wrong in a way that would mislead the stage-2 skill

1. **Redraw the launch-film boundary** (rows 18, 79-82, 84).
   - His quarterly polished launch is the produced, founder-on-camera register, not launch-film. launch-film §0.11 bans a human shoot.
   - Make step 10 and §6 agree on Launch HN and Product Hunt.
   - Add `demo-recording` as the third sibling.
   - Drop "stills" from the approval gates.
2. **Fix the two claims that contradict his own measured behaviour** (rows 3, 67).
   - "Never by views" fails against the 30-day challenge.
   - "Forgotten by the time I hit post" fails against self-replies 4.7-7.8 h later and follow-up replies days later (A1).
   - Add a thread-handling step.
3. **Re-scope the step-27 norms and the three templates as survivor habits** (rows 10-11, 50-56).
   - Show pass/fail per video.
   - Delete "turn by 25%"; it fails v3 at 43%.
   - Restrict "key detail moving by 3 s" to screen takes.
   - Restore R1's same-template control (2.9M against 294K).
   - Before stage 2 sets thresholds, have A1 measure 4-6 lower performers: 1.19M, 344K, 294K, 202K, 145K, and Tidbit's 342K.
4. **Add the account confound** (rows 15, 78). v6 came from @heyclicky (15.6K followers), the others from @FarzaTV (129K). Without it, P17 and the horizontal-vs-vertical bullet in §4 do not hold.
5. **Make measurement runnable** (rows 19-20, 68).
   - Tag each post, not just each profile.
   - Say that his own X replies use /try or clicky.so, and his YouTube description link is untagged.
   - Add a product-analytics step: a signup event and a retention query.
   - Relabel 0.23% as a ratio of unlike numbers whose attribution is confounded by the next-day open-source release.
6. **Correct the §5 agent overclaims** (rows 86-90).
   - Instagram and TikTok numbers need the founder's export.
   - A1's method is not an automatic lint.
   - "The founder must write the lines" is contradicted by W1 S8, so make it the §8 Q10 test.
   - The static feed mock is a weaker proxy.
7. **Fix the factual errors.**
   - The YouTube channel's age (row 64, yt-dlp).
   - The title-period claim (row 44).
   - 10-28 s → 14-28 s (row 40).
   - "The challenge is 30 s" (row 34).
   - The niche call-out "seen in the interview" (row 29).
   - "Vikrant unverified" (row 2).
   - The mute-test misquote (row 47).
   - The 276-280 character range that hides v2's 151 (row 43).
   - The end card (row 63).
   - The music dip (row 61).

### P1: evidence grading and attribution

8. **Regrade principles and the summary** (rows 4-5, 7-13, 16):
   - P4, P6: Anecdote.
   - P5: Anecdote; copying risk documented.
   - P7: Measured, n=1.
   - P8, P10: per-video results.
   - P19: carry the "closed by choice" caveat.
   - Put the n=4 caveat in the §1 summary.
9. **Relabel steps that are invented or misattributed** (rows 25-28, 35, 46, 57, 65, 74):
   - Steps 11 and 12 come from W1, and step 12's "becomes the first frame" is wrong.
   - Step 14 is one anecdote, and his biggest hit broke it.
   - Step 15's default contradicts [33:23].
   - Steps 10, 22, 28 and 48 are X1's or the synthesizer's advice, not his.
10. **Audio rule against his own hits** (row 14): mark v1 and v2's mics as unverified, note the earbuds in v2, and note v1's raw -32 dBFS.
11. **Story hook** (row 45): mark it "requires prior success". Use the curiosity gap as the newcomer's version.
12. **Caveats** (rows 92-97): ground "post anyway" in volume data, not the two anecdotes. Complete the anecdote and tension tables.
13. **Minor labels** (rows 31, 33, 39, 41-42, 49, 59, 60, 69-70, 72, 75-76, 96): add the dropped caveats.
    - Rifkin & Du's second half.
    - The "effect may not be as big" caveat.
    - PPC Land's 94%.
    - The dji.com price was out of stock.
    - The NYT story was seen only in a search summary.
    - "I recommended" is probably an ASR slip.

### P2: completeness, meaning what a founder needs to actually run it

14. **Instagram copy** (rows 71, 43). His first kickoff question is the Instagram caption [04:08], yet §3.5 is built entirely on X copy.
    - Add the measured Instagram captions: "is my startup trash? let's decide.", "im building a buddy for your computer cursor" and "Put something out, see what happens." (R1 Insert H, R3 I6, R4 I-15).
    - Add his personal bio link `/farza` (R3 I10).
15. **Steps the readers captured but the draft dropped:**
    - The "show it to one person" gate (W1 S7, S14).
    - Niche discovery from organic users before targeting them [29:42]-[29:53].
    - Thumbnails and titles for YouTube (W1 S10: 3 h) and its Intro and dips report (X1 §2.4: the window is 30 s on YouTube, 3 s on feeds).
    - The landing page built from demo clips (R1 Insert E).
    - A LinkedIn milestone post ("$10K MRR ... 9-weeks", 50,677 impressions; R4 I-16).
    - Open-sourcing as a second launch (W1 S4).
    - "Meme content juices the algorithm but does not convert" (W1 S9).
    - Over-promotion fatigue (X1 §3.6).
    - Do not show metrics a clone could use (X1 §2.3).
16. **Operating details absent from the procedure:**
    - A target length per platform. The measured videos run 45-140 s; X's own guidance is 6-15 s (X1 §2.4); none is given.
    - A rule for reframing when cross-posting vertical to X.
    - A redaction check before posting. v2 shows a Stripe account ID and live revenue (R4 §3).
    - Music rights. v2 plays AC/DC's "Back in Black"; his edited videos carry a "song" with lyrics (A1 v3).
    - A weekly time budget across the whole procedure.
    - A sample-size or decision rule before ranking channels. "After the first few videos" is noise when outcomes are heavy-tailed (X1 §2.7).
    - What to do if 30 days produce no 1,000-view post.
    - When to hire creative help. X1 §2.12 gives a trigger: tracked conversion on one channel, with production as the bottleneck.
17. **Unmeasured anchors to flag as gaps:**
    - The 20.9M reel was never measured from source (A1 could not find it).
    - The agent-interface video made from the shown script was never located.
    - Instagram and TikTok numbers were not read by any slot.
