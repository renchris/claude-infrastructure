# E2a: blind watcher, transcript only

Condition: the only inputs read were `/tmp/vu-2026-10-23/transcript.txt` (934 lines, 63,163 bytes) and `/tmp/vu-2026-10-23/exam-questions.md`. I opened no image, frame, sheet, video, audio, manifest, cut list or web page, and nothing else in `agents/`.

Evidence labels:
- **MEASURED**: read directly from the transcript artifact (cited as `T:<line>`, where line N is the line in transcript.txt).
- **INFERRED**: deduced from the words, or general prior knowledge applied to them.
- **GUESS**: words do not support an answer. This is a prior-based guess, scored low.

No claim here is DOCUMENTED, because no vendor or paper source was consulted.

ASR defects noticed (MEASURED from the text, corrections INFERRED):
- "Bill Space" T:475 should be Buildspace (T:21).
- "Ahmed" T:933 is almost certainly "Aaron": the host is addressed as "Aaron" at T:97 and T:497, and as "aaron epstein" at T:595.
- "davinci results" T:526 should be DaVinci Resolve.
- "the goal of michael" T:629 should be "the goal of mine".
- "16.9" T:662 should be 16:9.
- The final "[47:07] Thank you." T:934 comes 12 s after the previous line and looks like Whisper's known silence/music hallucination.

Timestamps: the transcript has segment starts at 1-second resolution, and segments can run on (T:395, T:416). Chapter starts are therefore accurate to about ±2 s.

## Part 1: Chapters

| Start | Title | Evidence |
|---|---|---|
| 00:00 | Cold open: launching without the slick video | T:1-15 |
| 00:45 | Farza's background: eBay at 13, Zip School, Buildspace, Hey Clicky | T:16-21 |
| 01:10 | Video as core strategy, and what changed since 2020 | T:22-42 |
| 02:36 | The big coordinated launch vs constant mini-launches ("demos") | T:43-69 |
| 04:02 | Work backwards from the launch: caption and hook first | T:70-83 |
| 04:35 | Breakdown: the Hey Clicky launch video (3M views, 7,000 downloads, ~100 retained) | T:84-174 |
| 08:01 | Writing like "tweet poetry"; personal-sounding emails | T:175-197 |
| 08:34 | The "did I stop?" test: mock your post into a real feed | T:198-228 |
| 09:11 | The first frame and first 3 seconds (Xcode, zoom-in) | T:229-285 |
| 10:07 | Scripting every video so it sounds unscripted | T:286-393 |
| 11:59 | The first shot: show your face. Screen-aware dictation video | T:394-421 |
| 13:55 | Rehearsing lines, and the team overruling "worst video ever" | T:421-438 |
| 15:14 | Demo-driven development and the "check this out" feeling | T:439-451 |
| 16:11 | Standing out: post it and forget it | T:452-472 |
| 17:42 | The old Zip School videos (23 likes) and the first landing page | T:473-501 |
| 20:09 | Reps: the basketball analogy | T:502-508 |
| 20:46 | Produced vs iPhone; the 21M-view video and the formula | T:509-533 |
| 22:44 | "Am I bouncing?": studying other people's Reels as templates | T:534-548 |
| 24:00 | Every demo as a mini story; the founder as a character | T:549-557 |
| 24:41 | Weekly "everything we built this week" team updates | T:558-583 |
| 26:56 | Joy, being yourself, and why only 1-2% actually record | T:583-609 |
| 29:09 | B2B buyers are on TikTok too: the design-agency TikToks | T:610-631 |
| 31:03 | Channel conversion: Twitter worst, YouTube ~20%, Instagram ~70% of traffic | T:631-650 |
| 32:47 | Tracking with a /ig link in bio | T:651-658 |
| 33:18 | Platform-specific cuts: 16:9 for Twitter, the drawing video | T:658-671 |
| 34:30 | Taste vs volume | T:671-683 |
| 35:28 | Breakdown: the no-hands GPT-realtime / Spotify / Stripe demo (no cuts, but beats) | T:683-710 |
| 37:50 | Beats for short-attention viewers | T:711-721 |
| 38:46 | Why the first hire was a filmmaker | T:721-745 |
| 40:48 | Gear: Screen Studio, iPhone + Edits, Sony FX3/FX30 + DJI mic. Audio is #1 | T:746-776 |
| 42:37 | Working with Vikrant, the filmmaker | T:777-815 |
| 44:03 | Can't afford a filmmaker? Start anyway; "be cringe first" | T:816-848 |
| 44:59 | Writing first, with FreeWrite (freewrite.io) | T:849-876 |
| 45:41 | The 30-day challenge | T:877-924 |
| 46:47 | Wrap and thanks | T:924-934 |

A YouTube editor would probably merge these into about 12 chapters: 00:00, 00:45, 01:44, 04:35, 10:07, 11:59, 16:11, 17:42, 22:44, 29:09, 35:28, 38:46, 40:48 and 45:41.

### 150-word summary

YC's Aaron Epstein interviews Farza Majeed, founder of Hey Clicky (previously Buildspace and Zip School), about launching through video in 2026 (T:2, T:17, T:595). Farza argues the expensive, coordinated launch video is obsolete. Algorithmic feeds reward founders who "launch" small demos constantly, and a selfie video can outperform a $20,000 production (T:40-58, T:52). He walks through his own videos: the off-the-cuff Clicky launch (about 3M views, 7,000 downloads, about 100 daily users), the scripted screen-aware dictation video, the no-cuts Spotify demo, and early Zip School clips that got 23 likes. From these he draws his method: test whether you would stop scrolling, nail the first 10 seconds, write and rehearse a script, show your face, tell a mini story with beats, and measure conversion per channel rather than views. Instagram drives about 70% of traffic. Hire a filmmaker early, prioritize audio, write in FreeWrite, and post one video a day for 30 days.

### 10 most important claims and advice

1. **[02:28]** You're not making posts anymore; you are constantly launching on algorithmic platforms (X, LinkedIn, YouTube). T:40-42. MEASURED.
2. **[03:11]** A simple "hi, here's my product" video now likely beats a $20,000 produced video on engagement and traffic. T:52. MEASURED.
3. **[04:08]** Work backwards from the launch: decide the caption and hook before building the feature. T:69-76. MEASURED.
4. **[07:05]** Ignore views and track downloads and retention. The Clicky launch got about 3M views, about 7,000 downloads, and about 100 people who used it daily for 5 days. T:138, T:142-155. MEASURED.
5. **[08:47]** Paste your draft text into a real feed and ask "would I stop on this?" T:205-222. MEASURED.
6. **[11:11]** Use the first 10 seconds (10-20% of a one-minute video) to say what you're doing and why it matters. T:342-363. MEASURED.
7. **[21:55]** The formula: "this is who I am, this is what's going on, this is what I'm working on, let me show you." T:523-524. MEASURED.
8. **[31:07]** Conversion differs by channel. Twitter is the worst (7,000 downloads on 3M views), a 20k-view YouTube video converted about 20%, and Instagram is about 70% of traffic. T:633-647. MEASURED.
9. **[41:46]** Audio quality is the most important thing in any video. Buy a cheap DJI mic, not a MacBook or AirPods mic. T:756-773. MEASURED.
10. **[45:46]** The challenge: record and post one 10-minute-effort video a day for 30 days. One will probably pass 1,000 views; learn from it. T:881-920. MEASURED.

Runner-up: hire a filmmaker as one of the first two hires (T:725-727).

## Part 2: Exam

Calibration note (INFERRED): of 24 questions, only Q9, Q15, Q18, Q19, Q22 (partly) and Q24 (partly) can be answered from words. The rest ask about appearance, layout, cuts or on-screen text, which a transcript does not carry.

**Q1.** **Host.** The lines at 00:00 and 00:07 are interviewer narration: "my guest today, Farza Majeed" (T:1-2). Clothing cannot be read from words. GUESS: a dark jacket or sweater for the standalone open, versus a more casual shirt at the table. Confidence: host 85, clothing 5. Evidence: T:1-2, T:7. MEASURED (role) / GUESS (clothing).

**Q2.** All three lines (T:4-6) come from an inserted clip. INFERRED: it is the Hey Clicky team's weekly "everything we built this week" video (T:3 "this is everything we ship this week" matches T:560). So the speakers are likely Farza and two teammates, not the host. GUESS: "Well, shipping, right?" is a teammate, "Are we shipping?" is another teammate, and "Yeah, we're shipping." is Farza. Appearance cannot be read from words. Confidence 15. Evidence: T:3-6, T:560-583.

**Q3.** The transcript has no speech from 00:31 to 00:45 (T:15 to T:16). INFERRED: the graphics play under music, presumably a theme or stinger, which stops at or just before "Farza, thanks for being here" at 00:45. GUESS: the first lines of the conversation are dry, room-tone dialogue with no music bed. Confidence 35. Evidence: the T:15/T:16 gap.

**Q4.** GUESS from context: one caption reads "Aaron Epstein, Group Partner, Y Combinator" (the name is from T:595; the title is a prior) and the other reads "Farza Majeed, Founder, Hey Clicky" (T:2, T:17). Guess on placement: host caption left under the host, guest caption right under the guest. Table objects: a laptop in front of the guest, because he drives screen demos ("I'll show you", T:106, T:396), and possibly mics or water. Confidence: names 55, sides 30, objects 15.

**Q5.** The guest is speaking about his background (T:19-21). GUESS: the left part holds B-roll or graphics illustrating eBay, Buildspace and Hey Clicky, the right part holds the guest, and the layout changes as each company is named. Confidence 15.

**Q6.** Not answerable from words. In 02:00-03:00 the guest speaks from 02:02 to 02:28, the host from 02:36 to 02:53, then the guest again (T:35-52). GUESS: about 4 cuts, in the order guest single, wide, host single, guest single, wide. Confidence 10.

**Q7.** Not answerable from words; the guest is speaking at T:73-77. GUESS: a cap with a small logo, clear-frame glasses, a white tee under an open overshirt. Confidence 5.

**Q8.** INFERRED: the insert is the Hey Clicky launch video, recorded in the YC office "five minutes before dinner" (T:107-129). The bubble is probably **the guest, Farza**, in that earlier recording. GUESS on the difference: different clothes, no cap or no glasses, filmed in an office rather than the studio. Confidence: identity 65, difference 15.

**Q9.** INFERRED from the narration "I'll just go to some random person's tweet here. Maybe like this one. And I'll literally change this text to my tweet's text" (T:201-206). The storefront post first shows **a stranger's original tweet text**. **Browser developer tools (Inspect Element)** open. Afterwards the post shows **Farza's own tweet text** (the Clicky launch copy, roughly "I built this thing… an AI teacher", T:170-171). The **author name does not change**, because only the text is swapped (T:205). Confidence: overall 55; devtools panel 50; author unchanged 60.

**Q10.** Not answerable from words. 10:38-10:54 is his script document (T:312-315). GUESS: two live-camera boxes, host and guest, in the corners. GUESS for 13:03-13:35 (YouTube page, T:396-399): one box, the guest's. Confidence 10.

**Q11.** INFERRED: this is the screen-aware dictation video (T:419) on a new YouTube channel posted three days after it was created (T:397-398). The view count is about 19,000 (T:399, "despite being 19,000 views"); T:400 and T:637 say "20,000". GUESS: title "Screen aware dictation" or similar; likes several hundred; age "N months ago" (unknown). The table object cannot be read from words; GUESS a mic or a plant. Confidence: views 40, title 25, likes and age 5, object 3.

**Q12.** T:458 ends "I always just think about like," at 16:43 and the next segment starts at 16:47 (T:459). MEASURED: a 3-4 s gap with no transcribed words. INFERRED: a thinking pause, possibly with a filler or a laugh the ASR dropped, lasting about 3 s. The hand is unknown; GUESS a raised or circling hand, as when thinking. Confidence: pause and length 45, hand 5.

**Q13.** INFERRED: a Zip School class card. The title is "Mars Perseverance Rover Landing" (T:479-480), and "ages 7 to 12" should be one chip (T:480). GUESS on the other chips: "Science" and "Space" or "Live". Teacher label: unknown, GUESS "Teacher: Farza". Booking day and date: the Perseverance landing (prior knowledge: Thu 2021-02-18) puts a session around then; GUESS "Thu, Feb 18". Confidence: title 70, age chip 50, rest 5.

**Q14.** The guest is speaking at T:491-492 ("…go super viral which never happened"). INFERRED: a sub-second single is likely a **reaction cut to the host**, who is not speaking, smiling or laughing at "which never happened". GUESS: the next shot returns to the guest or the wide. Confidence 35.

**Q15.** INFERRED: the voice is **the creator of a random Instagram Reel**, a stranger ("this is a random video we just stumbled upon", T:538). It is neither person at the table. GUESS for 23:06: the Reel is paused or stopped as the guest starts commenting, "first of all…" (T:537-538). Confidence: voice 80, 23:06 event 30.

**Q16.** INFERRED context: the account behind the weekly update videos (T:558-566), likely Hey Clicky's Instagram. GUESS: handle "@heyclicky"; bio along the lines of "an AI buddy that lives next to your cursor" (T:525); link "heyclicky.com/ig" (link-in-bio is "slash ig", T:652). Counts are unknown. Confidence: handle 25, link 25, bio 10, counts 2.

**Q17.** MEASURED: in 29:47-29:56 the **guest** speaks (T:616-619: design agencies, "what would you do… Aaron"), and from 30:00 the **host** answers ("oh i don't know probably the default…", T:619-622). So the first close-up is the guest and the second is the host. Sides and gaze are GUESSES assuming the 180° rule, with host on the left and guest on the right in the wide: guest framed screen-right looking screen-left, host framed screen-left looking screen-right, each looking toward where the other sits in the wide. Confidence: people 75, sides and gaze 35.

**Q18.** MEASURED: the request "can you please open up spotify and play acdc… back in black" (T:686-687), then "rock on it's playing back in black now" at about 35:54 (T:687), "it's a little bit loud" (T:688), "it's so loud / got it lowering spotify to 50" at about 36:00 (T:689). INFERRED: the background sound is AC/DC's "Back in Black". It starts right after the assistant's spoken confirmation, just after he asks for it, and it is loud at first. After about 36:04 the volume drops (Spotify set to 50%) so speech sits over it ("lower the music so you can continue to talk over it", T:705). Confidence 70.

**Q19.** **No.** "Rock on, it's playing Back in Black now" is **Clicky's AI voice** answering him (T:687; GPT-realtime agent, T:684). The man is not saying it. Posture GUESS: hands raised or away from the keyboard, since it is billed as "no hands" (T:686, T:702); smiling or nodding to the music. Confidence: speaker 80, posture 25.

**Q20.** Not answerable from words. At 37:33-37:36 the host is on "somebody goes I wonder how much money they made" and the guest answers "i'm always just trying to keep the story moving" (T:705-707). GUESS: the guest gestures with his hand (a forward or rolling "keep going" motion), and the edit is a hard cut from the wide to his close-up on the gesture. Confidence 10.

**Q21.** Not answerable from words; the guest is on gear at T:752-756. GUESS: a smartwatch on the left wrist and a ring on a right-hand finger. Confidence 5.

**Q22.** INFERRED: at 45:01-45:10 he says "for all of my writing I always use this thing called FreeWrite… freewrite.io… It's my app" (T:850-853), so the white document is FreeWrite. It **probably appeared earlier at about 10:38-10:54**, as "a script I wrote for a video that I did yesterday" (T:312-315). FreeWrite is his writing tool, so the script likely lives in it. The bottom bar is FreeWrite's toolbar. From prior knowledge of the open-source app (INFERRED, not from the transcript), its labels are: font size, "Lato", "Arial", "System", "Serif", "Random", a timer (e.g. "15:00"), "Chat", "Fullscreen" and "New Entry". Confidence: same-document 50, bar labels 30.

**Q23.** MEASURED: "Farza, thank you so much for being here" (T:930-931), then "Thanks, Ahmed" (sic, Aaron) at 46:55 (T:933). INFERRED and GUESSED steps: they turn toward each other, reach across the table and shake hands (or fist-bump), then let go. GUESS: the picture fades or dissolves to a YC end card. Confidence 25.

**Q24.** MEASURED: the last real line, "Thanks, Ahmed/Aaron", is at 46:55 (T:933). The transcript then shows "[47:07] Thank you." (T:934), which falls inside the final 3 s (47:05.4-47:08.4). INFERRED: the 12 s gap fits outro music, and a lone "Thank you." on a music tail is the classic Whisper hallucination. My answer: **outro music from about 46:56 to the end, and probably nothing is actually said in the final 3 s**. The words-only evidence is ambiguous on this point: the transcript does literally show speech there. Confidence: music 55, nothing said 50.

## What this condition shows (INFERRED)

- A transcript alone supports chapters, summary and claims at a level close to a human's. Every Part 1 item above cites a line.
- The transcript fails on spatial and visual questions: about 14 of 24 exam items are guesses at 15% confidence or less.
- It also fails on who-said-what inside inserts (Q2) and on non-speech audio (Q3, Q12, Q24), where it can only flag gaps.
- One transcript artifact, the T:934 "Thank you.", is a trap for words-only reasoning.
