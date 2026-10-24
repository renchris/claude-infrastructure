<!-- markdownlint-configure-file { "MD013": false } -->

# Candidates, registers, the first 10 seconds and the script (Stages 1 and 2)

The agent drafts, counts, times and critiques; the founder picks, rewrites in their own words and performs. "He" and "his" mean Farza. K1: an agent is "good as an editor and sparring partner; weak as a ghostwriter for a founder-on-camera register". Sources: METHOD §3.2-§3.8 and A1's frame-by-frame reads. Every timing below comes from his videos that did well: it shows what his hits did, not what makes a hit (§7.1).

## 1. Candidates from the repo (Stage 1)

Read-only, in the product repo:

```bash
git log --since="<date of last post>" --no-merges --date=short --pretty='%h %ad %s'
git log --since="<date>" --no-merges --stat --pretty='%n%h %s' -- <user-facing dirs>
gh pr list --state merged --search "merged:>=<date>" --json number,title,mergedAt --limit 50
```

Also read the changelog, release notes, and closed issues labeled bug (they feed step 38's flaws). Write the week's table to `posts/<yyyy>-W<nn>-candidates.md` (one file a week, at the `posts/` root). When the founder picks a row, create `posts/<yyyy-mm-dd>-<slug>/candidate.md` with that row, its angles (§2) and the grounding frame; the weekly file only lists, and `candidate.md` feeds Stages 2 and 6.

| Change (in the user's words) | Commits or PR | User-visible? | Works on screen today? | Grounding frame (step 13) | Big enough for a one-shot channel? (step 11) |
| --- | --- | --- | --- | --- | --- |

- Drop refactors, chores and internal tooling, unless the audience is developers and the change is the product (INFERRED: a launch is "something new" [18:49] that a user can see).
- "If more than one person might see it, post it" [18:54]: small is fine.
- A team update (step 10) is this table read aloud by the people who built each row: "what are you doing today?" [26:30]-[26:36].

## 2. The caption-first check (step 12)

He asks "what's the copy on the Instagram caption?" [04:08] and "what's the hook if we make this a video?" [04:11] before building; he "drafted hella tweets", each angling the idea a different way (W1 S7); and "If I can't really explain it in 280 characters, then it's probably too complicated" (W1 S14).

- **Angles:** for each top candidate, about five angles (a working default, INFERRED), each a post-sized caption plus a spoken first line and its hook type (`copy.md` §5). Vary the claim, the user, the problem and the proof. These angles are the post's hook variants; there is no second set later. Stage 6 turns the founder's pick into the full X post and keeps the rest for stop-test re-runs. Write them in `candidate.md`:

```markdown
## Angle <n>   hook type: demo | curiosity gap | story      # niche call-out: not offered (copy.md §5)
caption (<= 280, X weighted count <n>): <text>
spoken first line: "<line>"        # an anecdote, time or event is a <slot> only the founder fills
critique: <why a stranger would stop or scroll past>
```

- **Count** with X's weighting, not plain `len()`: X counts any URL as 23 characters and most characters outside Latin and common punctuation (CJK, emoji) as 2 (X's published counting rules, not from METHOD; an approximation, since an emoji sequence can over-count). At most 280 on a standard account, and the self-reply too (`copy.md` §2):

```bash
python3 -I -c 'import re,sys;t=re.sub(r"https?://\S+","x"*23,sys.argv[1]);print(sum(1 if (o<=4351 or 8192<=o<=8205 or 8208<=o<=8223 or 8242<=o<=8247) else 2 for o in map(ord,t)))' "<draft>"
```
- **Critique:** one line per angle on why a stranger would stop or scroll past.
- **A clarity check, never a hit predictor.** He called the Clicky demo "not that good" [06:16] and the dictation video "the worst video we've ever done" [14:26]; they got 3.0M and 2.95M X views (§7.1, A1). If no angle states the change plainly in a caption that excites the founder, tell the founder to rethink the feature or its angle (step 12).

## 3. Registers in version one (step 16, §3.3; scope in `open-questions.md` q13)

| Register | Looks like (A1) | Needs | His examples | Effort | Template |
| --- | --- | --- | --- | --- | --- |
| **Raw screen take** | One continuous screen recording; 0-3 edits, no captions, no music; a webcam bubble the whole time in his | The founder on mic, live; bubble optional; voice-only UNTESTED | v1 (3.00M X views), v2 (3.83M) | One take | A, §5 Template 2 |
| **Produced feature demo** | Presenter in a real place, close-ups, full-screen recordings; 13-19 cuts a minute, phrase captions, background music, an end card | The founder on camera, or a voice-over form (UNTESTED: none of his is voice-only) | v3 (0.63M), v4 (2.95M X, 21K YouTube) | "like an hour" [20:50] to 4-6 h [22:14]; his filmmaker made them [42:51]-[42:53] | B, §5 Template 1 |
| **Team update** | What shipped, one line per person, for existing users; "no hook there's no attention there's no story" [25:12]-[25:18] | Each speaker on camera; voice-only: a narrated "what shipped" screen walk (INFERRED, UNTESTED) | "everything we built this week" (R3 I12) | About 10 minutes of capture [26:30]-[26:36] | §5 Template 4 |
| **Selfie minimum** | "hi, this is what I'm working on, check this out", then turn the camera to the screen [22:19]-[22:24] | A face | his standing advice to beginners: a 30-second selfie video [27:30]-[27:37] | Not stated (§3.3); the 30-day challenge asks 10 minutes a day [46:00] and gives no length | §5 Template 5 |
| **Vertical story** (conditional) | 9:16, 45-52 cuts a minute (v6 52.1; v5's 45.5 overcounts archival footage, so its true rate is lower, §3.3, §4a), 1-3 word captions, proof shots, music | The founder on camera, and a real milestone to cite; a story works once there is a demo a stranger understands on mute (INFERRED, §7.5; W1 S8, S27) | v6 (73K X from @heyclicky), the 20.9M reel | 4-6 h for the reel [22:14]-[22:19] | C, §5 Template 3 |

He adds of the selfie minimum, "I think the effect may not have been as big" [22:28]. His quarterly polished launch is the produced register at higher effort (§6). Choose one register per video; Farza makes most of his for Instagram [33:23], and a raw take for X when the moment is fresh, on screen and for developers (step 16).

**When a change fits both the raw take and the produced demo** (a new named feature that also works on screen today), decide in this order (INFERRED from step 16 and §3.3's "Use it when" column; not his stated rule):
1. It works on screen today and the founder will post today → **raw take**, even for a named feature. v1 named Clicky and still went out raw.
2. The founder records the voice afterwards (`setup.md` `voice: after`) → **produced demo, voice-over form** (UNTESTED); a raw take needs live narration.
3. The point needs a turn (a concession, then why this is different, as in v4) that one live take cannot carry → **produced demo**.
4. The quarterly polished launch → **produced demo** at higher effort (§6).

A voice-only founder leans raw (§8 q1: voice-only maps to the raw screen take).

## 4. The first 10 seconds (steps 27-29)

"Most people, when they're scrolling, see the first three seconds." [09:32] On YouTube the window is longer: its Intro report measures the first 30 s (X1 §2.4). In all six of his measured videos the first word starts within 0.25 s, with no title card, logo or music intro; in five of six the thing is named by about 3.6 s (A1). These are habits from hits, not thresholds.

**Plan sheet** (fill before capture; check against the take in `measure.md` §4):

| Item | Plan | Source |
| --- | --- | --- |
| First frame: the audience's own tool or world. If the product spans two tools, open on the one where the new thing happens (INFERRED tie-break) | | "It's very purposely Xcode" [09:13]-[09:22] |
| First spoken line: greeting, then the thing | | demo hook, §3.5 |
| Thing named by; the names passed to `first10-check.py --name` (product and feature) | | 5 of 6 by about 3.6 s |
| The detail that moves early (screen-led takes); the zoom target | | P7 (n=1), [09:24], [09:40] |
| Recorder, if the plan has a zoom (`setup.md` `screen_recorder`) | | step 3; Screen Studio zooms while recording, else a HyperFrames zoom in post (`edit-export.md` §4) |
| "So check this out." or another pivot | | P4 |
| Why care right now, in one line, and where it lands (below) | | step 31 [22:34]-[22:40] |
| Planned mute-read words (a prediction; Stage 6 measures the take) | | step 25 |
| Captions on X: yes, no, or after the mute test | | step 42 (INFERRED rule) |

**Where the why-care line goes.** His rule: the opening says what you're doing and why it matters, then "let's get into it" [11:13]-[11:16]. In practice the why often lands after 10 s (A1; v4's turn at 21-30 s). INFERRED: in v1 the why plausibly rides on the "what it is" line ("…it's basically an AI teacher that can teach you anything", to 9.41 s), and the real use from 10.4 s is framed as his own problem ("a video editing program that I've been procrastinating learning") (A1; §3.6). So put it in the "what it is" line, or make it the first real-use line after the pivot. In a produced script it is beat 2 (the problem, as your own).

**For a feature of a product people already know**, name the feature, or use v4's form, "Hey, so today we're adding <feature> to <product>." (0.04-2.94 s, A1). Pass both names to `--name` (`measure.md` §4).

**Template A: raw screen take** (16:9, X first). In substance n=1, v1; v2 shares only its first 2.5 s, then goes straight to the demo (§3.6). For a developer tool, open on the audience's own editor or terminal. v1 filmed the full desktop; this skill films the sized window's capture rectangle instead (`capture.md` §1: it keeps notifications and other projects out and the type larger; INFERRED trade-off), so "frame" below means that rectangle. The Picture and Words cells are his, for reference: write your own lines and never restage his frames (`boundary.md` §3, the 10-02 "copy cat" row).

| Time | Picture | Words | Voice-only form (INFERRED, UNTESTED) | Terminal or CLI form (INFERRED, UNTESTED) |
| --- | --- | --- | --- | --- |
| 0.0-0.3 s | The capture rectangle in the audience's own tool; webcam bubble bottom-right (face or bubble mode) | First word at 0.08 s (v1) or 0.20 s (v2) | No bubble | The terminal, the command already typed or typing |
| 0.3-2.4 s | Same; one gesture to camera (v1's peace sign at 0.5 s) | "Hey, everyone. So this is Clicky." (0.08-2.36 s) | No gesture; one small cursor move instead | Press Enter: output starting to stream is the movement |
| about 2.2 s | Animated zoom onto the small key element [09:24] | | Same | Zoom onto the one output line that matters. Whether a recorder's auto-zoom fires on keystrokes is unmeasured, so set a manual zoom in the recorder or plan a HyperFrames keyframe zoom (`edit-export.md` §4) |
| 2.5-7.0 s | Hold the zoom; move the cursor so something visibly moves [09:40] | One line describing what is literally on screen | Same | Hold while the key line fills in |
| about 7.0 s | Zoom back out to the frame | "…it's basically an AI teacher that can teach you anything." (to 9.41 s) | Same | Same |
| 9.6-10.4 s | The frame | "So check this out." | Same | Same |
| 10.4 s on | The real use, framed as a personal problem | | Same | Same; if the result lands in a second tool (a chat app, a browser), switch to it here inside the one take, as v2 opens Spotify at 10.1 s (A1) |

Neither v1 nor v2 has a hard cut in its first 10 s. A terminal take must also read on a phone: `capture.md` §3.

**Template B: produced feature demo** (16:9, edited), from v3 and v4. A1 did not identify the presenters (§7.2). The staging (the outdoor table, the blackboard, the chalking hand) and the lines are his, for reference: write your own.

| Time | Picture | Words | On-screen text | Voice-only form (INFERRED, UNTESTED) |
| --- | --- | --- | --- | --- |
| 0.0-0.5 s | Medium shot of the presenter facing camera in a real place (an outdoor table with a laptop; a blackboard) | First word at 0.04 s (v4) or 0.23 s (v3) | Captions from 0.5-1.0 s: 3-6 word chunks, white, bottom-center at about 80% of height | The product's most legible screen, never a title card |
| 0-3 s | Same | "Hey, so today we're adding dictation to HeyClicky." (to 2.94 s) | "Hey, so today we're adding" | Same words over the screen |
| 3.5-6.6 s | Close-up of the one gesture: fingers on fn + control (v4, 4.04-6.01 s); a hand chalking (v3) | The one capability | "hold fn + control," | Hands on the keyboard, or the product in close-up |
| 6-10 s | Back to the face | The rest of the "what" | phrase chunks | Back to the screen |
| about 8-10 s | | Background music comes up (v4) | | Same |
| 10-11 s | First full-screen product recording; the demo starts at 8-9% of runtime | | captions continue | Same |

Two cuts in the first 10 s. In v4 the turn comes at 21-30 s and the reveal at 31 s, on a new, darker setup (A1).

**Template C: vertical story** (9:16), reference only, from v6 (73K X views from the smaller account; its Instagram result is unknown): a wide shot under a tree with "Today we crossed over 5 million views on this thing we're building called Clicky" (0.12-3.56 s) and 2-3 word captions at about 63% of height; seven proof screenshots at about 0.1 s each; screen recordings; a double exposure on "a pretty meh idea". Thirteen hard cuts in the first 10 s, music throughout, the demo at 36% (§3.6). The 20.9M reel's hook runs about 7-8 s with his face for 6 of 8 sampled seconds, a cut to the 2.8M-view X post as proof, and a YC badge at second 7 (R3 I6).

## 5. Script templates (step 17)

**How much to script:**

| Where the founder is | What to write | Source |
| --- | --- | --- |
| The general rule | "spend as much time possible before the video writing it" | [45:14] |
| First videos | Nothing; "if you've never made a video, don't worry about this" | [45:20] |
| About the 15th-30th video | Write for 10 minutes about what it should be, then record; writing first lets you "catch a bad idea" | [45:22]-[45:29], [45:36] |
| Produced feature demo | Every line, ahead; v4 was written about three days before; his first YouTube video in a decade took a 30-minute script | [14:00]-[14:05]; W1 S10 |
| Raw take of a fresh moment | A beat card at most (INFERRED from v1 being "almost entirely unplanned") | [10:00] |

P9 is Contested: the Clicky launch was unplanned, he tells first-timers not to script, and no outside study tests it (§2). Write in a plain editor with no distractions; he uses FreeWrite, his own free MIT-licensed app [45:01]-[45:08] (K1). Script first, then visuals [11:56] (host).

**Who writes** (§8 q10, a test). For a produced script, the agent interviews the founder by voice for about 10 minutes, transcribes it locally (`measure.md` §2), and fits it to the template. For a raw beat card there is no interview: the agent drafts from `candidate.md` (the picked angle and caption). Either way the agent writes two spoken-form options for each spoken line (line 1, line 2, the pivot, the CTA in Template 2; every line in Template 1), marks `script_by: agent-draft`, and the founder writes or rewrites every spoken line, after which it reads `script_by: founder`. The rewrite is the founder owning the words, not a gate (SKILL.md hard rule 2): a founder who records the draft as is leaves `agent-draft` in the log, which is what q10's test needs. K1 judges an agent-written script the most likely to sound read, but his Tidbit TikToks used a collaborator's script ("Hasan just puts the camera in my face, gives me a script", W1 S8). Log `script_by`. The "what it is" line is the product's one-line value proposition, `setup.md` `one_liner`: keep it identical to any launch film's (§6.5). Change it only in `setup.md`, and on purpose. If a change would make it differ from an approved launch film's words, raise it with the founder as a launch-film change (its §1 story is frozen on yes); never write it into the film.

**Template 1: produced feature demo.** Beat order INFERRED (§3.4) from the script he showed (text MEASURED, R2 §3.5; its finished video was never located, §8 q8), plus v4's measured turn (A1). The example lines are his, for reference: the founder writes their own.

```markdown
# Script: <feature>   <date>   register: produced feature demo   primary platform: <Instagram | X | YouTube>
estimated length: <s> (from the beats; reported, never a target, hard rule 8)   setup share: <setup s / length>   # [11:27]-[11:31]
script_by: agent-draft | founder
## Setup block (beats 1-2: what you're doing and why it matters [11:04]-[11:16]; his "like 10, 20%" applies to this, a reference, not a passing score)
1. What, in one line:   "Hey, so today we're <shipping | adding> <thing>."         # v4, first word at 0.04 s
2. Problem:             "When I <do X>, I <hit Y>." Then "let's get into it" [11:13]-[11:16], in your words.
   # his shown script states it from users ("When talking to our users, we found..."); his advice [13:36] and his
   # measured videos (P12, A1) state it as his own. Default here: as your own.
## Lead-in (beats 3-7; METHOD sets no share for these, and the shown script's finished video was never located, §3.4)
3. Stakes:              <what is possible when it works>
4. Tension:             <why most people never get there>
5. What-if, two personas: "What if a <role> could <outcome>? What if a <role> could <outcome>?"
6. Bridge:              <one line from the what-if to this product>
7. Pivot:               "So, check this out."
## Demo
<stage direction in angle brackets, e.g. <screen: the editor, hold fn + control>>
<narration: what is literally on screen, said plainly>
## Turn (concession -> personal problem -> reveal; A1 pattern 4, step 34)
## Beats after the reveal (ask "am I here? am I still watching?" at each [38:27])
## One honest flaw, after a success beat (P20; steps 37-38)
## CTA (an invitation, never "sign up"; step 44; his 3 of 6 sat in the last 3-7%, a habit, not a target; "none" is allowed, as in v2)
end card (optional): <"try it for free", then the name>                             # v3, v4
## Planned mute-read words (a prediction; Stage 6 measures the take)                # step 25
## Shot list (capture.md §7)
```

| Estimated length | His 10-20% share (arithmetic, step 18; a reference, not a budget to hit; the ratio appears nowhere outside the interview, UNTESTED, §7.6) |
| --- | --- |
| 60 s | 6-12 s |
| 100 s | 10-20 s |
| 120 s | 12-24 s |
| 140 s | 14-28 s |

His setup rule was said of "one minute" videos [11:19] while his demos ran 100-140 s (A1), so read it as a share of the length. Before capture the length is an estimate from the beats; Stage 4 re-reads the share on the take as the demo start over the take's length, as P8 measures it (v1, v3, v4: 8-10%). In the shown script the setup (beats 1-2) was about 75 of roughly 260 visible words (INFERRED, R2). The "what" lands in the first seconds whatever the length; the turn varied from 10% to 43%, so it has no target (§7.5).

**Template 2: raw screen take beat card** (not a script; recorded live, one take):

```markdown
# Beat card: <moment>   <date>   register: raw screen take   primary platform: X (16:9)
mode / voice: <face | bubble | voice-only> / live           script_by: agent-draft | founder
first frame:  <the audience's own tool; the capture rectangle>            # [09:13]-[09:22]
zoom target:  <the small key element; zoom early (v1 at about 2.2 s; n=1, 1 of 6 by 3 s; not a target), hold, move it>  # [09:24], [09:40]
recorder:     <setup.md screen_recorder; manual zoom or HyperFrames post zoom if it cannot auto-zoom>
# option a) lines are his, for reference only; never post his lines word for word (boundary.md §3)
line 1:       a) "Hey, everyone. So this is <thing>."  b) <option>         # v1, 0.08-2.36 s; feature: "today we're adding <f> to <p>" (v4)
line 2:       a) <one sentence on what is on screen>  b) <option>         # may carry the why-care line (§4)
pivot:        a) "So check this out."  b) <option>                        # v1 at 9.6 s
setup block:  <0.0 s to the end of the why line / demo start> (<share>% of an estimated <n> s)   # what + why, then "let's get into it" (step 18); in v1 this is also the pivot; estimate, not target
real use:     <your own first real use, framed as your problem>            # [36:36]-[36:42]; v1 at 10.4 s
beats:        <ask -> it works -> the result>  (v2's beats came about every 10-15 s, gaps 10-23 s; n=1, not a target)
turn:         <concession -> personal problem -> reveal> | no turn: comic beats   # step 34; v2 has none
flaw:         <name any mistake it makes on camera and keep going>         # v1 at 86.8 s
CTA:          a) "I'll put the link below and give it a shot."  b) <option> | none (v2)   # v1 at 97%
planned mute-read words: <the few words a muted scroller would pick up>   # step 25; Stage 6 measures the take
captions on X: yes | no | after the mute test
```

Each beat stays a one-line note, not a sentence to read (§5 row 20). The shot list (`capture.md` §7) goes under the card in `script.md`.

**Template 3: the formula, for a story or milestone video** (step 30): "This is who I am, this is what's going on, this is what I'm working on, let me show you." [21:51]-[21:56] No measured video states all four (P10). INFERRED split: the full form for story videos, start at "what I'm working on" for feature demos as v1-v4 do, skip it for the team update. The story hook needs a real prior success; a newcomer opens with a curiosity gap instead (`copy.md` §5). As carried out once, in the 20.9M reel (step 30; R3 §3; n=1):
1. **Who and what's going on**, about 7 s: social proof, then self-deprecation, then the niche credential; the "who" is at most a credential.
2. **What I'm working on:** the name plus a one-line value proposition, "It's called Clicky, it's a little AI buddy that lives next to your computer cursor..." [21:56]-[22:05].
3. **Let me show you:** one relatable use case set against the status quo ("instead of going to a YouTube video" [22:05]-[22:10]), then the product visibly does it (R3 I7).

**Template 4: team update, 10-minute version** (step 10): "kind of like stand up right but in front of the world" [26:48]. Prompt each person with "what are you doing today?" [26:30]-[26:36]; one line each about one shipped change; the agent drafts the "what shipped" list from `git log` (§5 rows 8-10). A phone selfie with a handheld mic is enough (INFERRED). The produced version he showed (three speakers in about 22 s, cutaway shots, a title card, captions; R3 I12) is plainly more than 10 minutes (R3, INFERRED; its edit time is not stated) and is not templated here.

**Template 5: the minimum.** "hi, this is what I'm working on, check this out", then turn the camera to the screen [22:19]-[22:24]. No script.

## 6. Checks on any script (steps 19-20)

**His three reading tests.** The founder ticks them, since two are first-person ("I'm the audience"); the agent may pre-check sentence length and spoken forms and note where a line fails (§5 rows 17-19: the agent can "critique against the reading tests"). Run all three. A line that fails is a candidate for rewriting, not a block: he recorded a script he called "not that strong" [10:59]-[11:03], so the founder may record anyway (SKILL.md hard rule 2):
- [ ] "If I like reading it, then that means it'll probably sound good if I say it out loud as well." [10:30] ("not always" [10:35])
- [ ] "Would I read this if someone texted this to me?" [10:45]
- [ ] "For me, it's always I'm the audience." [10:54]

**Make it sound off the cuff:**
- [ ] Written for the ear: spoken forms ("kinda", "gotta", "That'd be sick"), short sentences (MEASURED, his script).
- [ ] The problem is the founder's own: "I'm not saying everyone has this problem where they don't know what to write." [13:36]
- [ ] Rehearsed away from the desk, "in the shower, going to work", until "I've already visualized it like 10 times" [14:05]-[14:16].
- [ ] The page is notes: he paraphrases his own script ("I want to share a new demo" [11:34] against the page's "I want to show you a demo"). This shows he paraphrases his own script in conversation; it does not show how he delivered the video, which no slot measured (§3.4). He mentions no teleprompter (K1).
- [ ] Talk as yourself: "That's just me being myself, which is like, hey, I want to show you." [13:51]-[13:55]
- [ ] Recorded even if it feels weak: "not that strong, but I still recorded the video because you got to be launching" [10:59]-[11:03].

Outside evidence has two halves (Rifkin & Du 2023, entertainment performers; X1 §2.5): people rate spontaneous performers as more authentic, and they also expect spontaneous work to be of lower quality. INFERRED: script for quality, and keep the script from showing.

**Rehearsal card:** the beat list, one line each, no full sentences (§5 row 20).

**Voice-only founder** (INFERRED, UNTESTED): the first sentence still names the thing early; the first frame is the product or the audience's tool, never a title card; the voice carries everything a face would, so the mic rule matters more, not less (P15); log `mode: voice-only` and `voice: live | after`. A voice recorded afterwards is the produced demo's voice-over form, never a raw take (`capture.md` §4).

## 7. Story moves (steps 30-40)

- **The turn** (A1 pattern 4, step 34): a concession, a personal problem, the reveal. v4: "So that's pretty cool, and honestly, many products already do this exact thing today." (21.2 s), then "But here's the thing, when I'm writing, I often don't really know what I even want to say." (26-30 s), then "So check this out, we're shipping screen-aware dictation." (31 s). v3 escalates instead: "Alright, so that's kind of cute, but what if I wanted to do something a little bit more complicated?" (60 s). v2 has no turn, only comic beats.
- **Beats where cuts would go** (step 35): v2 has "not a single cut" [37:02] but has beats [37:06] (host), "of course that's all purposeful" [37:18]: the hook, the ask and about 1.5 s of silence, the song, "it's a little bit loud", the Stripe joke, then a new beat about every 10-15 s (A1's beat times give gaps of 10-23 s; n=1). "I'm not trying to keep your attention, that's actually the wrong way to look at it." [37:36]
- **From the viewer's seat** (step 36): at each beat, "am I here? am I still watching?" [38:27].
- **Self-deprecation after a success beat** (step 37): "a pretty meh idea" (v6), "It's a little bit buggy" in v4's CTA.
- **Admit the product's mistakes** (step 38, P20): v1 left Clicky's wrong LUT recommendation in and named it at 86.8 s; his replies did the same ("High chance I run of credits lol", W1 S2). Pull known flaws from the issue tracker into the card.
- **Storytelling is learned, not a prerequisite** (§7.5): "I'm good at … writing stories" [19:23] against 2024's "I am not naturally a guy that can tell great stories" (W1 S12).
- **Two properties** (step 31): a "super clear hook", and "a very clear like why you should care right now while you're on your scroll" [22:34]-[22:40].
- **Show the work, never a life** (step 39): "You'll never catch me making those videos about this is my day as a YC founder." [25:52]-[25:59]
- **Define "convert" before claiming it** (step 33): the formula has no conversion data tied to it (P11); measure through tagged links and events (`setup-and-log.md` §6).
