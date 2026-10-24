# E3 judgement: two blind watchers vs the exam key and the publisher's chapters (2026-10-23)

Role: judge. Inputs read: `agents/E1-exam-key.md` (KEY), `agents/E2a-watcher-transcript-only.md` (E2a), `agents/E2b-watcher-full-pipeline.md` (E2b), the question file `/tmp/vu-2026-10-23/exam-questions.md` (EXAM; question *n* is at line 3+2n), the transcript `/tmp/vu-2026-10-23/transcript.txt` (T), and the video `/tmp/vu-2026-10-23/video.mp4` for re-measurement. The human-authored chapter list came from the task brief (the video's publisher); per their own condition statements, neither watcher saw it (E2a:3, E2b:3).

Labels: **MEASURED** = I ran it this session (scripts and frames in `/tmp/vu-e3/`). **DOCUMENTED** = a file I read states it. **INFERRED** = my reasoning from measured or documented evidence.

## Verdict

| | E2a, transcript only | E2b, full pipeline |
|---|---|---|
| Exam score (24 questions, key as corrected below) | **11.0 / 24 (46%)** | **24 / 24 (100%)**; 19/24 with every detail right |
| Sub-part credit (threshold-free check) | 13.3 / 24 (0.55) | 23.4 / 24 (0.98) |
| Chapter recall at ±30 s / ±60 s (17 non-trivial boundaries) | 0.88 / 0.94 | 0.88 / 1.00 |
| Chapter-title topical match (17 titled chapters) | 14.0 / 17 (0.82) | 16.0 / 17 (0.94) |
| Mean confidence vs score | 31.8% vs 45.8% (underconfident by 14 points) | 80.9% vs 100% headline; 80.9% vs 79.2% all-detail |
| Confident-wrong (conf ≥70, graded 0) | 0 | 0 |
| Wrong sub-claims at conf ≥70 | 1 (Q18) | 5 (Q3, Q12, Q18, Q19, Q23), all minor |

All MEASURED from the grading below (`/tmp/vu-e3/calib.py`, `/tmp/vu-e3/chapters.py`).

The key had **1 substantive error and 3 minor ones** (section 3). The substantive one (Q18) would have marked E2b's correct answer as confident-wrong.

---

## 1. Chapter recovery vs the publisher's chapter list

### Method (MEASURED, `/tmp/vu-e3/chapters.py`)

- GT: the 18 chapter starts in the brief. 00:00 is trivially hit by everyone, so headline numbers exclude it (17 boundaries). Results with it included are also given.
- Predicted: E2a's 35-row table (E2a:26-60), E2b's 34-row table (E2b:28-61). E2a also offered a 14-row "a YouTube editor would merge these" list (E2a:62), scored separately.
- **Recall:** a GT boundary is hit if a predicted boundary is within the tolerance. **Precision:** a predicted boundary is correct if a GT boundary is within the tolerance. Both are reported two ways: any-match, and an optimal one-to-one, order-preserving match.
- **Granularity ceiling:** both watchers emit about 2x the GT count. With one-to-one matching, precision therefore cannot exceed 17/33 = 0.52 (E2b) or 17/34 = 0.50 (E2a), excluding 00:00. Read precision against that ceiling, not against 1.0.

### Results

| Excluding 00:00 | Recall ±30 s | Recall ±60 s | Precision ±30 s (1:1) | Precision ±60 s (1:1) | Median abs Δ of ±30 s hits |
|---|---|---|---|---|---|
| E2a (34 boundaries) | 15/17 = **0.88** | 16/17 = **0.94** | 15/34 = 0.44 | 16/34 = 0.47 | 12 s |
| E2a merged list (13) | 10/17 = 0.59 | 12/17 = 0.71 (1:1: 11/17) | 10/13 = 0.77 | 11/13 = 0.85 | n/a |
| E2b (33 boundaries) | 15/17 = **0.88** | 17/17 = **1.00** | 15/33 = 0.45 | 17/33 = **0.52**, the ceiling | 6 s |

Including 00:00: E2a 16/18 and 17/18; E2b 16/18 and 18/18. Any-match precision at ±60 s is 0.68 for E2a and 0.67 for E2b (MEASURED, script output).

### Alignment table and topical match

Title rule:
- Compare the GT title with the watcher's chapter matched to that boundary within ±60 s. If none is matched, compare with the watcher's chapter in force at the GT start.
- **1** = same headline topic.
- **0.5** = the GT topic appears only as a secondary clause, or in an adjacent watcher chapter inside the GT span.
- **0** = a different topic.
- Each judgement was checked against the transcript at the GT start (T:30-49, T:88-89, T:105-109, T:164-170, T:298-313, T:394-396, T:465-469, T:534-551, T:558-560).

| GT start | GT title | E2a boundary (Δ s) | E2a title (E2a line) | E2a topic | E2b boundary (Δ s) | E2b title (E2b line) | E2b topic |
|---|---|---|---|---|---|---|---|
| 00:00 | (intro) | 00:00 (0) | Cold open (26) | n/a | 00:00 (0) | Cold open (28) | n/a |
| 01:44 | Launch Constantly | 01:10 (-34)† | Video as core strategy; what changed since 2020 (28) | 0.5 | 01:10 (-34)† | What changed: ... "constantly launching" (31) | 1 |
| 03:38 | Start Shipping Demos | 04:02 (+24) | Work backwards from the launch (30) | 0.5 | 02:55 (-43)† | Old media gone; "demos, not launches" (32) | 1 |
| 05:02 | Show the Process | 04:35 (-27) | Breakdown: the Hey Clicky launch video (31) | 0 | 05:02 (0) | Show the process, not the ending (34) | 1 |
| 06:07 | The Clicky Launch | none ≤60 (nearest 04:35, -92) | in force: Breakdown: the Hey Clicky launch video (31) | 1 | 06:01 (-6) | Case study: the Clicky launch video (35) | 1 |
| 07:43 | Write a Hook That Stops the Scroll | 08:01 (+18) | Writing like "tweet poetry" (32) | 1 | 07:43 (0) | Writing the post; "did I stop?" test (36) | 1 |
| 10:30 | Why Farza Scripts Every Video | 10:07 (-23) | Scripting every video (35) | 1 | 10:07 (-23) | Scripting every video (38) | 1 |
| 12:04 | Designing the First 10 Seconds | 11:59 (-5) | The first shot: show your face (36) | 1 | 11:56 (-8) | The first shot (39) | 1 |
| 15:15 | Demo-Driven Development | 15:14 (-1) | Demo-driven development (38) | 1 | 15:14 (-1) | Demo-driven development (41) | 1 |
| 17:25 | You Have to Take a Thousand Shots | 17:42 (+17) | Old Zip School videos (40); reps at 20:09 (41) | 0.5 | 17:42 (+17) | Old Zip School videos (43); reps at 19:36 (44) | 0.5 |
| 20:48 | Farza's Formula for Videos That Convert | 20:46 (-2) | ... and the formula (42) | 1 | 20:36 (-12) | The formula (45) | 1 |
| 23:01 | Turning Demos Into Stories | 22:44 (-17) | "Am I bouncing?": Reels as templates (43); story at 24:00 (44) | 0.5 | 22:44 (-17) | Studying where you bounce (46); story at 24:04 (47) | 0.5 |
| 24:53 | Show What You're Actually Building | 24:41 (-12) | Weekly "everything we built this week" (45) | 1 | 24:41 (-12) | Weekly "everything we built" videos (48) | 1 |
| 29:11 | Finding Customers on Social Media | 29:09 (-2) | B2B buyers are on TikTok too (47) | 1 | 29:09 (-2) | B2B buyers on TikTok and Instagram (50) | 1 |
| 31:02 | Which Platforms Actually Convert? | 31:03 (+1) | Channel conversion (48) | 1 | 31:01 (-1) | Channels compared (51) | 1 |
| 39:01 | Why Farza's First Hire Was a Filmmaker | 38:46 (-15) | Why the first hire was a filmmaker (54) | 1 | 38:44 (-17) | First hire was a filmmaker (56) | 1 |
| 40:49 | The Video Stack | 40:48 (-1) | Gear (55) | 1 | 40:46 (-3) | Gear stack (57) | 1 |
| 45:41 | The 30-Day Launch Challenge | 45:41 (0) | The 30-day challenge (59) | 1 | 45:40 (-1) | The 30-day challenge (60) | 1 |
| | | | | **14.0/17** | | | **16.0/17** |

† = outside ±30 s but inside ±60 s.

Observations:
- **The transcript carries the chapter structure** (INFERRED from the table). Transcript-only E2a recovers 16 of 17 boundaries within ±60 s.
  - The visual pipeline's one extra hit is 06:07, where E2b cut at 06:01, the moment the screen share starts (T:106 "I'll show you one example here").
  - The other E2a-only weakness is 05:02, a transcript topic shift ("show the process", T:88-89) that E2a did not split out. That is a judgement difference, not a modality one.
- **Both watchers miss in the same direction** (INFERRED, 4 cases). They cut at the host's question; the publisher cuts at the follow-up or the guest's answer.
  - 01:10 vs 01:44 (T:22, T:30)
  - 10:07 vs 10:30 (T:298-306)
  - 38:44/38:46 vs 39:01 (T:721-725)
  - 22:44 vs 23:01 (T:534-537)
- **E2a's merged list** has the best precision (0.77-0.85) and contains 01:44 exactly, but it drops 5-7 GT boundaries.
- **Shared extra boundaries:** both watchers split 31:02-39:01 at 35:28, the Spotify demo, which the publisher keeps inside "Which Platforms Actually Convert?". Both also have a 46:47/46:52 sign-off chapter. These count against precision but are defensible splits.

---

## 2. Exam grading

### Rubric

- Each question is split into the sub-parts its wording asks for (EXAM line 3+2n). Each sub-part is scored 1, ½ or 0. A hedge "A or B" where only one option is right scores ½.
- Fraction *f* = mean of the sub-parts. Grade **1** if *f* ≥ 0.8, **0.5** if 0.4 ≤ *f* < 0.8, **0** if *f* < 0.4.
- Grading uses the key as corrected in section 3.
- **Confident-wrong** = grade 0 at confidence ≥70. Separately listed: any specific sub-claim at confidence ≥70 that a measurement contradicts.
- Where a watcher gave several confidences for one question, the mean is used for calibration.

### Per-question grades

| Q | Axis | Key (KEY lines) | E2a answer → sub-parts | E2a grade (conf) | E2b answer → sub-parts | E2b grade (conf) |
|---|---|---|---|---|---|---|
| 1 | B | Host; charcoal crew-neck sweatshirt vs dark two-pocket overshirt over white tee (34-37) | host ✓; "dark jacket or sweater" ½; "more casual shirt at the table" ½ (E2a:87) | **0.5** (85 role / 5 clothes) | all ✓ (E2b:94) | **1** (90) |
| 2 | C | Wire-glasses bearded man / cream-beanie woman / tortoiseshell-glasses denim man (39-46) | no appearance; role guesses ✗ (E2a:89) | **0** (15) | all three ✓ (E2b:95) | **1** (80) |
| 3 | F | Loud bass-heavy music; drops at 44.75; faint tail under first lines to about 00:49 (48-61) | music ✓; stops about 00:45 ✓; "no music bed" under first lines ½ (E2a:91) | **1** (35) | stepped tones and clicks ✓; stops 44.75 ✓; "no music" ½ (E2b:96) | **1** (75) |
| 4 | A | "Aaron Epstein / General Partner, YC" left; "Farza Majeed / Founder, Heyclicky" right; MacBook nearer guest; red clipboard before host (63-70) | "Group Partner" ½; right ✓; sides ✓; objects ½ ("mics or water" ✗, no clipboard); in front of whom ½ (E2a:93) | **0.5** (55/30/15) | all ✓ (E2b:97) | **1** (85) |
| 5 | A | Left: white @FarzaTV post with embedded vertical video; right: guest; layout holds (72-75) | "B-roll or graphics" ½; guest ✓; "layout changes" ✗ (E2a:95) | **0.5** (15) | all ✓, about 36% width (E2b:98) | **1** (75) |
| 6 | E | 6 cuts: W-G-W-G-W-H-W (77-88) | "about 4", wrong order (E2a:97) | **0** (10) | 6 cuts, same order, times within 0.05 s (E2b:99) | **1** (75) |
| 7 | B | Sage cap with white frog-head outline; thin round wire glasses; white tee under denim (90-93) | "small logo" ✗; "clear-frame" ✗; white tee ✓ (E2a:99) | **0** (5) | all ✓ (E2b:100) | **1** (70) |
| 8 | B | Guest, uncapped, dark tousled hair (95-102) | guest ✓; "no cap or no glasses" ½ (E2a:101) | **0.5** (65/15) | guest, no cap ✓ (E2b:101) | **1** (80) |
| 9 | E | "Looks like Google is about to drop something?" → devtools → Clicky launch text; author unchanged (104-112) | initial text not given ✗; devtools ✓; Clicky text ✓; author ✓ (E2a:103) | **0.5** (55) | all ✓, plus right-click → Inspect (E2b:102) | **1** (85) |
| 10 | A | 2 boxes, host top-left, guest top-right; then 1 box, guest top-right (114-117) | counts ✓; who ✓; "in the corners" ½ (E2a:105) | **1** (10) | all ✓ (E2b:103) | **1** (75) |
| 11 | D | "introducing screen-aware dictation."; 472 likes; 19K views 2mo ago; red bottle (119-122) | title ½; likes ✗; views ✓ / age ✗ ½; "mic or plant" ✗ (E2a:107) | **0** (≤40) | all ✓ (E2b:104) | **1** (90) |
| 12 | F | About 1.15 s near-silence; hand raised beside face in a C (124-128) | "3-4 s gap ... filler or laugh" ½; length ✗; "raised or circling" ½ (E2a:109) | **0** (45/5) | silence about 1.2 s ✓; C-shaped hand ✓; *"digital zero, so an edit" wrong* (E2b:105) | **1** (75) |
| 13 | D | "Mars Perseverance: Rover Landing"; Ages 7-12 / Space / 30 Mins; Teacher Ashton; Thu, Feb 25 (130-133) | title ✓; chips ½; "Teacher: Farza" ✗; "Thu, Feb 18" ½ (E2a:111) | **0.5** (70/50/5) | all ✓ (E2b:106) | **1** (90) |
| 14 | C | Host, not speaking, closed-lip smile; next: guest grinning, hand up (135-138) | host ✓; not speaking ✓; smiling ✓; "guest or wide" ½ (E2a:113) | **1** (35) | all ✓ (E2b:107) | **1** (80) |
| 15 | C | Reel narrator, neither man; reel paused at 23:06 (140-143) | all ✓ (E2a:115) | **1** (80/30) | all ✓ (E2b:108) | **1** (85) |
| 16 | D | _heyclicky; 48 / 35.4K / 5; "your friendly neighborhood cursor"; heyclicky.com/ig (145-148) | handle ½; counts ✗✗✗; bio ✗; link ✓ (E2a:117) | **0** (≤25) | all ✓, including "5 following" (E2b:109) | **1** (92) |
| 17 | A | Guest right-of-centre looking screen-left; host left-of-centre looking screen-right (150-156) | all ✓: people from who speaks, sides from the 180° rule (E2a:119) | **1** (75/35) | all ✓ (E2b:110) | **1** (80) |
| 18 | F | *Corrected:* 1.5 s silence; music enters quiet at 35:52.75; steps up about 13 dB at about 35:58.75; drops about 19 dB at 36:04.25 (158-169, audit A2) | AC/DC ✓; *"starts right after the assistant's confirmation ... loud at first" ✗*; before ½; drop ✓ (E2a:121) | **0.5** (70) | ✓; faint from 35:53.5 then loud at 35:57-59 ✓; "2.5 s of quiet" ½; drop ✓ (E2b:111) | **1** (70) |
| 19 | C | No; grin with teeth (closed once), hands clasped under chin (171-177, audit A3) | No ✓; smiling ✓; "hands raised or away from keyboard" ½ (E2a:123) | **1** (80/25) | No ✓; *"lips closed"* ½; interlaced fingers ✓ (E2b:112) | **1** (80) |
| 20 | E | Flat-hand visor at the brow; cut on action at 37:34.75 (179-182) | "rolling keep-going" ✗; hard cut on the gesture ✓ (E2a:125) | **0.5** (10) | all ✓ (E2b:113) | **1** (75) |
| 21 | B | White-dial watch, brown strap, right wrist; silver ring, left hand (184-187) | "smartwatch, left wrist" ✗✗; ring on right hand ½ (E2a:127) | **0** (5) | all ✓ (E2b:114) | **1** (85) |
| 22 | D | Yes, from 10:38; screen-recorder bar with "Recover 2 unfinished recordings" etc. (189-192, audit A5) | yes ✓; 10:38-10:54 ✓; "FreeWrite toolbar" ✗; invented labels ✗ (E2a:129) | **0.5** (50/30) | all ✓ (E2b:115) | **1** (85) |
| 23 | E | Clasp, shake, fist bump, both hands open; orange wipe from the right (194-203, audit A6) | "shake (or fist-bump)" ½; "fade or dissolve" ✗ (E2a:131) | **0** (25) | clasp/shake/fists/explosion ¾ (*misses bump contact and host's open hand*); wipe ✓ (E2b:116) | **1** (80) |
| 24 | F | Music to 47:02, fade 47:03-04, digital silence from 47:05; nothing said; "Thank you." hallucinated (205-216) | music ½ ("to the end" ✗); nothing said ✓ (E2a:133) | **0.5** (55/50) | all ✓ (E2b:117) | **1** (85) |

Italic = a detail contradicted by measurement (section 3).

### Score per axis

| Axis (questions) | E2a | E2b |
|---|---|---|
| A Spatial layout (4, 5, 10, 17) | 3.0 / 4 | 4 / 4 |
| B People / appearance (1, 7, 8, 21) | 1.0 / 4 | 4 / 4 |
| C Audio-visual fusion (2, 14, 15, 19) | 3.0 / 4 | 4 / 4 |
| D Inserted visual content (11, 13, 16, 22) | 1.0 / 4 | 4 / 4 |
| E Motion / temporal (6, 9, 20, 23) | 1.0 / 4 | 4 / 4 |
| F Paralinguistic / non-speech (3, 12, 18, 24) | 2.0 / 4 | 4 / 4 |
| **Total** | **11.0 / 24 = 0.458** | **24 / 24 = 1.000** |

MEASURED (`/tmp/vu-e3/calib.py`).
- **Under the unaudited key:** E2b scores 23.5 (Q18 = 0.5) and E2a is unchanged at 11.0.
- **Threshold-free check:** sub-part credit is E2a 13.3 (0.55) and E2b 23.4 (0.98). The ranking and the size of the gap do not depend on the 0.8/0.4 thresholds.

E2a's 11 points split two ways:
- **The 6 questions E2a itself flagged as answerable from words** (E2a:85): 4.0/6.
- **The other 18:** 7.0/18. It gained points on Q3, Q10, Q14 and Q17 from film-grammar priors (reaction shots, the 180° rule) and from transcript gaps. Each of those was stated at confidence ≤55 (INFERRED from E2a:91, 105, 113, 119).

### Calibration

| | E2a | E2b |
|---|---|---|
| Mean confidence | 0.318 | 0.809 |
| Mean score | 0.458 | 1.000 headline; 0.792 with every detail right |
| Gap (confidence minus score) | -0.140 (underconfident) | -0.191 headline; +0.017 all-detail |
| Brier (fractional outcome) | 0.120 | 0.040 headline; 0.149 all-detail |

E2a by confidence bin:
- **Below 30:** n=11, confidence 0.14, score 0.18. Calibrated.
- **30-59:** n=12, confidence 0.45, score 0.71. Underconfident.
- **60 and above:** n=1, Q18 at 70, scored 0.5.

E2b's confidences (70-92) match the probability that *every* detail of an answer is right (79%), not the probability that its headline is right (100%). MEASURED (`/tmp/vu-e3/calib.py`).

### Confident-wrong

- **Question level (graded 0 at confidence ≥70): none for either watcher.** E2a's zeros were all stated at confidence ≤25 (E2a:89, 97, 99, 107, 109, 117, 127, 131).
- **Sub-claims at confidence ≥70 contradicted by measurement:**
  - **E2a, Q18 (70):** the music "starts right after the assistant's spoken confirmation ... loud at first" (E2a:121). In fact it enters at 35:52.75-35:53.0, before "Rock on" (2154.16 s, KEY:175), and quietly (audit A2).
  - **E2b, Q3 (75):** "no music, only dry speech over room tone" under the first lines (E2b:96). A bass tail persists (audit A1).
  - **E2b, Q12 (75):** "digital zero ... so it is an audio edit" (E2b:105). There are no zero samples (audit A4).
  - **E2b, Q18 (70):** "about 2.5 s of quiet" (E2b:111). Measured: 1.5 s of silence, then about 1 s of faint music (audit A2).
  - **E2b, Q19 (80):** "lips closed" (E2b:112). Teeth show in 3 of 4 sampled frames (audit A3).
  - **E2b, Q23 (80):** the host "holds a fist or thumb up", and no fist-bump contact is reported (E2b:116). Knuckles touch at 46:58.00 and the host's hand is open at 46:58.40 (audit A6).
- **Under the unaudited key**, E2b's Q18 "jumps loud at about 35:57-35:59" would have been scored confident-wrong. The re-measure shows it is right.

---

## 3. Audit of the key

**Trigger:** questions where both watchers disagree with the key, which are Q3 and Q18. I also checked four E2b-only conflicts (Q12, Q19, Q22, Q23), because each decides a ≥70-confidence claim.

**Tools:**
- `/tmp/vu-e3/av.py`: per-bin mid = (L+R)/2 and side = (L-R)/2 RMS in dBFS, exact-zero sample fraction, and share of energy below 250 Hz.
- `/tmp/vu-e3/win.py`: window means.
- Native-resolution `ffmpeg -ss` frames in `/tmp/vu-e3/f/`.

**My script reproduces the key's numbers exactly** (MEASURED):
- Q3: side -39.9 dB at 44.75 s, -71.3 at 49.00, -78.3 at 49.25.
- Q12: -75.7 dB mean over 1006.0-1007.15.
- Q18: -47.7 / -32.0 / -48.4.

Each error below is therefore one of window choice or interpretation, not of arithmetic.

### A1 · Q3: is there music under the first lines? Key is RIGHT (both watchers say no music)

- **The tail:** in speech gaps the mid level is -31.5 dB at 45.50 s and -36.7 dB at 46.25 s, with 96% and 95% of the energy below 250 Hz.
- **Comparison with room tone:** pauses in later dialogue (50-62 s) bottom out at -48.9 to -54.5 dB, with 0-1% below 250 Hz. So the first-line gaps sit 15-20 dB above room tone.
- **The decay:** side falls -39.9 (44.75) → -50.1 (45.50) → -58.5 (47.25) → -71.3 (49.00) → -97.7 (50.00), and is exactly zero from 50.25 s.
- MEASURED (`av.py 43.5 7 0.25`; `av.py 50 12 0.25`).

**Ruling:** a fading bass tail does sit under 00:45-00:49, as the key says (KEY:51). Both watchers missed it. Both got the main event, the abrupt drop at 44.75 s, so this costs ½ of one sub-part and neither grade changes.

### A2 · Q18: when does the music start, and how loud? Key PARTLY WRONG (both watchers disagree, in different ways)

| Window (s) | Mid dB | Side dB | Reading |
|---|---|---|---|
| 2151.00-2152.50 (35:51.0-35:52.5) | -47.7 | exactly 0 | silence, 1.5 s. **Key right** (KEY:160) |
| 2153.00-2158.50 (35:53.0-35:58.5) | -19.2 | **-42.1** | music has entered (side -52.2 at 35:52.75, -39.7 at 35:53.0) but is **quiet** |
| 2158.75-2164.00 (35:58.75-36:04.0) | -16.7 | **-29.0** | **about 13 dB step up at about 35:58.75** |
| 2164.50-2173.00 (36:04.5-36:13) | -18.2 | -48.4 | after the drop: 19.4 dB below the loud phase |
| 2168.50-2170.25 (36:08.5-36:10.25) | -20.4 | -137.8 | music **absent for about 1.75 s**, then back at -44 to -55 |

MEASURED (`win.py`; 0.25 s bins from `av.py 2149 24 0.25`).

- **The key's error:** it says "loud stereo rock music ... enters at about 35:52.75" and quotes one window mean, "-32.0 dB" over 35:53-36:04 (KEY:161, 166). That -32.0 is the energy blend of a -42 dB phase and a -29 dB phase. The timing is right; "loud" at entry is wrong.
- **The drop:** about 19 dB from the loud phase, not the 16.4 dB the key computed from its blended mean.
- **Omission:** the key does not mention the 36:08.5-36:10.25 dropout.
- **Cross-check from the frames:** the Spotify progress bar reads 0:01 at 35:54.6 and 0:02 at 35:55.6 (`f/q19-stack.png`, MEASURED), which puts the song start at about 35:52.6-35:53.6. That fits the measured entry.
- **Why it is quiet first (INFERRED, not listened to):** the soft first 6 s fits the song's hi-hat count-in before the riff.

**Ruling:**
- E2b's "faint from about 35:53.5, jumps loud at about 35:57-35:59" (E2b:111) is right on the shape.
- E2a's "starts right after the confirmation, loud at first" (E2a:121) is wrong on both order and level.

**Effect:** E2b Q18 moves from 0.5 to 1. E2a is unchanged.

### A3 · Q19: the expression in the bubble. Key mostly right, but the grin is not "fixed"

2x crops at 35:54.3, 35:54.9 and 35:55.9 show an open grin with teeth; at 35:55.4 the lips are closed. Hands are clasped under the chin in all four (`f/q19-mouth.png`, MEASURED).
- The key's "fixed ... same grin in every frame" (KEY:172, 175) holds only for the 35:54.20-35:55.16 span it sampled.
- E2b's "lips closed" (E2b:112) is wrong for most of the window.

### A4 · Q12: is the pause digital zero? Key RIGHT

0.1 s bins over 1006.0-1007.1 (MEASURED, `av.py 1005.8 1.6 0.1`):
- Mid falls smoothly and monotonically from -66.9 to -88.7 dB.
- The exact-zero sample fraction is 0.000.
- Side is exactly 0, so the dialogue is mono.

So this is not digital zero. A smooth 1 s decay looks like a noise-gate release, not a splice (INFERRED). E2b's measured range (-67 to -89 dBFS, E2b:105) matches mine; its inference "digital zero, so an audio edit" does not. The key's hedge, "could be gated or edited" (KEY:128), is the better-calibrated statement.

### A5 · Q22: earlier appearances of the document. Key RIGHT but INCOMPLETE

- **Cut list:** `/tmp/vu-e1/cuts-robust.txt` shows white-insert toggles at 637.637/654.779, 664.706/676.134 and **692.567/708.708**, each with a luma difference of 161-176 (MEASURED, read).
- **Frame:** at 700.0 s (11:40) the same script is on screen, scrolled to "I want to show you a demo of our new agent interface." (`f/q22-doc.png`, MEASURED).
- **So:** the key's 10:38-10:54 and 11:04.7-11:16.1 (KEY:190) omit a third appearance at 11:32.6-11:48.7. E2b's "about 10:38-11:50" (E2b:115) is the correct envelope.

### A6 · Q23: handshake and wipe. Key RIGHT on the gesture, about 0.45 s early on the wipe

Frames (`f/q23-grid.png`, `f/q23-wipe.png`, MEASURED):

| Time | What the frame shows |
|---|---|
| 46:57.55 | hands clasped |
| 46:57.80 | closed fists, apart |
| **46:58.00** | **knuckles touching: a fist bump** |
| 46:58.25 | guest's hand spread, tongue out; host's hand opening |
| 46:58.40 | both hands open; wipe about 46% across |
| 46:58.70 | about 87% covered |
| 46:59.00 | about 2% uncovered |
| 46:59.15 | fully covered |

- The key's sequence is right (KEY:196-199); its "covers the frame by about 46:58.7" (KEY:201) is early.
- E2b's per-frame "covers by about 46:59.25" (E2b:116) is closer, but E2b missed the bump contact and the host's open hand.

### Key error list

1. **Q18, substantive:** "loud" music at entry. It is in fact quiet entry, then a +13 dB step at about 35:58.75. The drop is understated (16.4 vs about 19 dB), and the 1.75 s dropout at 36:08.5 is omitted.
2. **Q19, minor:** the "fixed" toothy grin varies; lips are closed at 35:55.4.
3. **Q22, minor omission:** the third appearance at 11:32.6-11:48.7 is missing.
4. **Q23, minor:** the wipe completes at about 46:59.15, not 46:58.7.

Confirmed when challenged: Q3 (the tail), Q12 (not digital zero), Q23 (the gesture sequence) and Q24 (E2a's "music to the end" is wrong; the last 3.3 s are exact zeros, `win.py` q24_tail zero_frac 1.000).

---

## 4. What this says about "watching like a human" (INFERRED)

- **With targeted reads, the full pipeline answers every headline question an examiner could ground.** E2b got 24/24. Its residual errors are fine level or timing claims and single-frame expressions: 5 details at confidence 70-80.
- **The transcript alone is half an exam.** E2a got 11/24. It is strongest on voice ownership (C, 3/4) and on layout guessable from film grammar (A, 3/4), and weakest on appearance, on-screen text and motion (B/D/E, 1/4 each).
- **Chapters need only the transcript:** recall 0.94 at ±60 s without vision.
- **The examiner shares the toolchain's blind spot.** The key's one substantive error came from a window-averaged audio level, the same kind of mistake the watchers make. A single-key exam built with these tools therefore carries about a 1-in-24 key-error floor.
- **The exam is selection-conditioned.** Questions were kept only if groundable with these tools; laughter was dropped as ungroundable (KEY:222). So 24/24 means parity on groundable questions. It is not evidence of parity on what a human hears directly (laughter, tune identity, prosody), which this exam did not test.
- **E2b's independence from the key looks real.** It got details right that the key lacks: the reel account name (E2b:108), the Spotify progress 0:01 at 35:54.6 (E2b:111, confirmed in my frame), and "tongue out" (E2b:116, confirmed). Its errors also differ from the key's (A2, A3).

## Reproduce

- `/tmp/vu-e3/chapters.py`: boundary recall and precision.
- `/tmp/vu-e3/calib.py`: scores, axes and calibration.
- `/tmp/vu-e3/av.py VIDEO START DUR BIN` and `/tmp/vu-e3/win.py VIDEO label:a:b ...`: audio.
- `/tmp/vu-e3/f/`: frames (`q19-stack.png`, `q19-mouth.png`, `q23-grid.png`, `q23-wipe.png`, `q22-doc.png`).
- Run the Python with `python3 -I`.
