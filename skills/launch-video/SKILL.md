---
name: launch-video
description: "Founder-led demo videos for X, Instagram, YouTube or TikTok (Farza's method): plan, script, record, edit, package, log what converts; the founder posts. A repo's launch video or README hero: launch-film. Silent README loop: demo-recording."
---

<!-- markdownlint-configure-file { "MD013": false } -->

# Launch video: frequent founder-led demos

Turn "we shipped something new" into a small, honest, public demo, often (P1 [02:31], [03:48]). The agent drives all it can
(candidates from the git log, caption angles, a beat card, stage prep, inserts, measurement, edits, copy, a ready-to-post
folder) and stops at named hand-offs. "The founder" is the operator whose product it is; "Farza" is the method's source.

**Source.** `docs/research/farza-launch-video-method-2026-10-24/METHOD.md` (METHOD) is the only source for the method: Farza
Majeed's 47-minute YC interview, checked against six of his launch videos measured frame by frame. `§n` is a METHOD section,
"step n" its procedure (§3), "Pn" a principle (§2), `[mm:ss]` an interview timestamp; A1, K1, W1, X1, R1-R4 are its evidence
files. Labels: **QUOTED**, **MEASURED** (the command is named), **INFERRED** (reasoning), **UNTESTED** (never a threshold).

**Four caveats bound every default** (§1, §7):
- Mostly hits, from an audience built over a decade (@FarzaTV 129,259 X followers, farza954 87.6K on Instagram, "10 plus
  years" of posting [06:33]): "say hi and post" works partly because he had reach (INFERRED, §7.1).
- A full-time filmmaker made most of his videos [42:51]-[42:53]; the solo Zip School videos got 10-23 likes (§7.2). The
  agent covers only post-production (K1), so a founder working alone is the UNTESTED case.
- A raw take and a produced cut each reached about 3M views on X: n=4, a sample-size caveat, not a finding (§4, §7.2).
- His first-10-second habits come only from videos that did well: reference columns, never passing scores (step 29, §8 q7).
  His conversion figures are anecdotes, never benchmarks (§7.3). The feed-mockup stop test, the 10-20% setup share, audio
  ranked above picture, the gear list and the 30-day challenge appear nowhere outside the interview (UNTESTED, §7.6).

## Which skill: triage before anything else

**Use launch-video for every shipped feature or "check this out" moment that goes to a social feed in the founder's own voice
(and face, if they are on camera), including the quarterly produced launch; use launch-film for a README hero film with sound
or a product's first public face on GitHub, with no founder seen or heard; use demo-recording for a silent animated WebP loop
in a README, below the hero.** (§6; how the three coexist, and each launch-film verdict row by row: `boundary.md`.)

- "Launch video" is ambiguous: the operator has used it for a launch-film hero (launch-film §10; operator-feedback 09-24).
  README or a GitHub page as the destination, hero, first public face, no founder seen or heard, or "stand unchanged for
  months" (§6) → launch-film, and so does "Create our launch video with <repo URL>" naming no feed, voice or face, with no
  question (launch-film §10). The founder's voice or face on a social feed, voice-only included (§8 q1), or a YouTube library
  demo → here. Unclear → ask: "Is this for a social feed in your own voice, or the README hero with no founder seen or heard?"
- Founder neither on camera nor heard → not this skill: launch-film for a hero film, demo-recording for a silent loop (§8 q1).
- A finished launch film going to social feeds → Stages 6-9 only, on the approved master as delivered, with no Stage 3-5
  work on it (`boundary.md` §2 rule 7). A film yes does not approve its copy (§6.7).
- Launch HN and Product Hunt: one-shot channels, substantive releases only, any finished asset (step 11; X1's advice).
- HyperFrames' `/product-launch-video` route triggers on "launch video for X" but builds a site promo from captured brand
  assets and defaults X feeds to 1:1. Never route a founder demo there; X exports stay 16:9 (step 45 [33:35]-[33:39]).
- **Resume:** if the product directory's `setup.md` exists (default `~/Development/personal/launch-video/<product>/`), read it, `post-log.md` and the newest
  `posts/*/checklist.md`, skip Stage 0, and resume at the first unmet exit check. An item marked `open` is asked when needed.

## Who does what

The agent takes planning, drafting, measuring, editing, versions, packaging and the log. The founder keeps what the method
rests on: noticing the moment, their own voice and face, whether their own eye stops, users, and pressing post (§5).

| Founder act (a HAND-OFF) | Why the agent cannot do it | Stage |
| --- | --- | --- |
| Say face, face bubble, voice-only or neither; live voice or voice after; name the external mic | §8 q1; §7.5; laptop and AirPods mics "don't count" [41:46]-[42:27] | 0 |
| Name the "post it anyway" person | An agent saying "post it" is not that human push (§5 row 7, INFERRED) | 0 |
| Notice the "check this out" moment and say which one | Only the founder knows what made them smile [15:31]-[15:48], [28:44] | 1 |
| Pick the hook; write or rewrite every spoken line; rehearse | "For me, it's always I'm the audience." [10:54]; scripting is Contested (P9); [14:05]-[14:16] | 1-2 |
| Record the take on the real mic, live; be on camera for face shots | K1: an agent cannot "Supply the voiceover", nor repair a laptop-mic take into a lav; voice-only forms are UNTESTED | 3 |
| Final pacing, music, when not to cut; the bounce test | Taste is "not delegable" (K1); the bounce test is a human reaction (§5 rows 30-40) | 5 |
| The stop test in their own real feed; confirm the mute read | The test's value is the real feed around the post (§5 rows 21-25) | 6 |
| Decide what may be shown; clear the music; show it to one person | Step 46; W1 S7 | 7 |
| Post, self-reply, answer the thread, talk to retained users | Outbound acts are the founder's (§5 rows 47-53; harness rule) | 8-9 |

**How a hand-off runs.** Two kinds, both said in this session's reply only, never by mail, chat, iMessage or a notifier. An
answer: ask, end the turn, and write the reply word for word into its named field (`setup.md`, `candidate.md`,
`checklist.md`, `post-log.md`). A file (a take goes in `<log-dir>/posts/<date>-<slug>/raw/`): name the absolute path, then
poll it with run_in_background in slices of at most 270 s, at most 6 slices (about 27 min; UNTESTED default). If nothing
lands, say once "Tell me when it is in <path>" and end the turn; Resume picks it up. Never perform the founder's act.

## Hard rules (every run)

1. **Nothing outbound.** Never post, reply, DM or email, or drive any logged-in session of the founder's: social, product,
   analytics, Dia (`cc-dia-act`), a browser MCP, or agent-browser `--cdp` or auto-connect. Messages to anyone go through
   `outbound-drafting` as drafts the founder sends (§5; §8 q3).
2. **No approval gates beyond the method's own:** the founder's stop and mute tests and the step-46 checks (§6 table,
   "Approval"). The audio check, the frame check on agent inserts and the founder's watch of the master (§5 rows 42-45;
   launch-film rule 8) are quality checks and hand-offs, not approvals: never ask a yes/no or "(yes / what to change)", and
   never import launch-film's per-gate operator yes (story, look, board, motion, sound, final). Approvals do not transfer (§6.7).
3. **Demos never enter the film.** No demo footage, look or music in a launch-film hero; never replace the README hero URL or
   write a film's `BRIEF.md` or `STATUS.md`. A raw take becomes a silent README loop only through demo-recording (§6.2-6.3).
   Keep each post's HyperFrames project in its own `work/` (INFERRED: HyperFrames' intent layer writes its own `BRIEF.md`).
4. **One truth rule, launch-film §1.6's:** every number on screen or in copy is measured under a written rule, dated and
   logged in `claims.md` (§6.4); every mechanic shown is real; the stakes are true; names on screen belong to this product: no
   other project's name, goal or plan, the founder's or anyone's (the 2026-10-01 verdict named "TrueMemory 2.0", a third-party
   project, "another project not ours"), and no customer or user names (step 46; §5 row 46). The audience's own tool may be the
   stage if no other project's content shows (INFERRED, step 27). An anecdote, time or event is the founder's own: a `<slot>`.
5. **No music without a documented license** (step 46; launch-film Do NOT), including audio an app plays inside the demo (v2
   played AC/DC from Spotify, A1). Free first: a paid or credit-spending media call only after the founder approves it with the
   cost stated (launch-film §0.10; operator, 2026-10-02); a generated track counts only under q15 item 3, its terms saved.
6. **The founder's own voice, the real product.** No TTS or generated voice for the founder's words, and no stock or generated
   footage standing in for the founder or the product (K1; INFERRED as a rule). Decline media-use's offered TTS voiceover
   always, and its background music and SFX on a raw take (his carry no added music, A1).
7. **Survivor habits are reference columns:** report where a take differs from step 29, never fail it on that. Label every
   number MEASURED (command named) or INFERRED (method named); an untested default says UNTESTED.
8. **Length is an output of the beats,** never a target or a choice (INFERRED in step 43, after launch-film §5). Report it.
9. **Product repos are read-only** (`git log`, `git show`, `gh pr list`). Tags, events or a post package go in only when the
   founder asks, through that repo's own change process (its worktree and land flow), never over a launch-film project.
10. **The skill schedules nothing:** no launchd, cron, reminders or messages. The weekly question, the daily challenge prompt
    and the day-7 read run when the founder calls the skill; Resume finds the open row.

## Stage 0. Set up once per product (templates: `setup-and-log.md` §1-3)

1. **One message, five questions** (§8 q1-2; text and branches in `setup-and-log.md` §1): face, bubble, voice-only or
   neither; live voice or voice afterwards; the external mic; the "post it anyway" person (step 7); where users come from
   and which accounts post. Neither → route. Voice-only is UNTESTED (none of his six is). `mode` blocks Stage 1; an
   unknown mic blocks Stage 3 only, so Stages 1-2 may run with `mic: open` (INFERRED: they record nothing).
2. **Create the product directory**, default `~/Development/personal/launch-video/<product>/` (private, local, `.md` and `.sh`
   only), or the directory the founder names: `setup.md`, `post-log.md`, `claims.md`, `swipe.md`, `posts/`; a dry run uses
   the caller's scratch `log-dir`.
3. **Mark the rest `open`** and fill each when its stage needs it: tiers (step 1), the conversion definition (step 33; q11 for
   an open-source tool), the tag scheme (step 4), product events (step 5, built only if the founder asks), music sources
   (q15), the one-liner and any launch-film project (§6.4-6.5), an optional mic reference (UNTESTED), the first four weeks (q12).

**Exit check:** `setup.md` holds `mode` and `voice`; `mic` is filled or `open` (filled before Stage 3); the rest is filled or `open`.

## Stage 1. What are we launching this week?

Ask it when the founder opens the skill each week (hard rule 10) and work backwards [03:55]-[03:59]. A launch is "we did
something new at the company, we talk about it" [18:49]; if more than one person might see it, post it [18:54]. Daily: what
did you do today that made you smile [28:44]-[28:56]? Show the process, not the polished ending (P5 [05:02], [25:27]-[26:09];
Anecdote): an inside look at what you did today. Copying risk: `measure.md` §5. Detail: `script.md` §1-2.

1. **Mine the repo** read-only (git log, merged PRs, changelog, closed bugs) into the week's `posts/<yyyy>-W<nn>-candidates.md`.
2. **Caption first** (step 12 [04:08]-[04:11]; W1 S7, S14): several angles per top candidate, each at most 280 X-weighted
   characters (`script.md` §2; about five is a working default, INFERRED). A clarity check, not a hit predictor (§7.1): if no
   angle states it plainly in a caption that excites the founder, tell the founder to rethink the feature or its angle. The
   angles ARE the hook variants: each is a caption plus a spoken first line, with its hook type (`copy.md` §5), in the picked
   candidate's `posts/<date>-<slug>/candidate.md`. Stage 6 expands the pick into full copy; it writes no second set.
3. **Grounding frame** (step 13): the single image the video exists to show; not the first frame. Flag any release big
   enough for a one-shot channel (step 11).
4. **HAND-OFF:** "Which one made you smile, and is it working on screen right now?" If it is, write only Stage 2's beat card
   (a few minutes, INFERRED estimate; v1 was "almost entirely unplanned" [10:00]) and record it raw, without checking whether
   someone did it first [36:25]-[36:31]; show your own first real use [36:36]-[36:42]. A same-day deadline is optional (step 15).

**Exit check:** `posts/<date>-<slug>/candidate.md` holds the angles, the one the founder says excites them, and the frame.

## Stage 2. Register, script or beat card, first 10 seconds (`script.md` §3-7)

1. **One register per video** (step 16; version-one set: `open-questions.md` q13): raw screen take (a fresh moment on screen,
   developer audience, X first); produced feature demo (a named feature that needs a turn; its voice-over form is UNTESTED);
   team update (what shipped, for existing users, no hook [25:12]-[25:18]); selfie minimum (his 30-second starter advice
   [27:30]-[27:37]; the 30-day challenge uses a similar talking format, §3.13). He makes most for Instagram [33:23]; for a
   developer tool, start from the raw take for X (INFERRED). **Tie-break** (INFERRED, `script.md` §3): working and posting
   today → raw take, even for a named feature; produced for the quarterly launch, voice after, or a turn one take cannot carry.
2. **Script depth** (step 17; P9 Contested): "spend as much time possible before the video writing it" [45:14]; first videos,
   don't worry [45:20]; from about the 15th, write 10 minutes, then record [45:22]-[45:29]; produced: every line (v4 [14:00]).
3. **The agent drafts structure; the founder owns the words** (§8 q10; `script.md` §5): from a 10-minute voice interview for a
   produced script, from `candidate.md` for a raw beat card; two spoken-form options per line; `script_by: agent-draft` until
   the founder rewrites. The setup block is what and why it matters, then "let's get into it" [11:13]-[11:16] (beats 1-2 of
   his shown script, §3.4), measured as the demo start, as P8 does, against his "like 10, 20%" (step 18 [11:27]-[11:31]).
   The founder runs his reading tests as self-checks, never a block (step 19; "not that strong" [10:59]-[11:03]), and
   rehearses away from the desk until visualized about 10 times [14:05]-[14:16]; the agent's card holds beats only (§5 row 20).
4. **First 10 seconds** (steps 27-28): the first frame chosen for the audience ("very purposely Xcode" [09:13]-[09:22]), the
   first word at once, no title card, the thing named early, something visibly moving [09:40]. Templates: `script.md` §4 (his
   staging and lines are for reference; write your own). A zoom in the plan fills `screen_recorder` now (step 3).
5. **The story** (steps 30-38): the turn (concession, personal problem, reveal); beats in a no-cut take (v2's about every
   10-15 s, gaps 10-23 s; n=1, not a target; A1); self-deprecation after a success; known flaws admitted on camera (P20); a
   "super clear hook" and why to care "right now while you're on your scroll" [22:34]-[22:40].

**Exit check:** `script.md` holds the setup block (start-end s and its share of the estimated length), the turn (or "no
turn: comic beats", as in v2), the CTA (or "no CTA", as in v2), the 10-second plan with its planned mute-read words, the shot
list (`capture.md` §7), and `script_by` (founder, agent-draft or none). A raw beat card (Template 2) carries all of these.

## Stage 3. Capture

Detail: `capture.md`. The agent prepares the stage; the founder performs on it.

1. **Prepare:** Do Not Disturb (HAND-OFF), a demo account with invented data, no keys, customer names or revenue on any screen
   (step 46; v2 showed a Stripe account ID, R4 §3), other projects' windows hidden by the founder (HAND-OFF; the agent closes
   nothing), the window sized and the capture rectangle chosen per demo-recording's "Setup" and "The capture itself" (`-R`,
   never `-l`). CLI, infra, login and third-party-app rows: `capture.md` §1-2. Host facts live in demo-recording; re-measure there.
2. **Agent-recorded inserts** (`capture.md` §2-3): agent-browser in a named session closed on every path, then the frame
   check (a draft run MEASURED 10 fps, 3-8 frames for 3.5-6 s flows); fallback `screencapture -v -R` after a screen hand-off.
3. **The founder's take** (HAND-OFF): the founder's live session and live narration, since an agent-driven run "reads as a
   product tour, not as a founder working" (K1; §8 q9). Give, in this session, the level (step 41 [40:52]-[42:32]), mic,
   recorder, beat card and absolute `raw/` path; masters stay untouched. A voice recorded after is `capture.md` §4's order.

**Exit check:** a take in `raw/`, with the mic that recorded it in `measure/reads.md`.

## Stage 4. Measure the take (reject before editing)

Detail: `measure.md`. Tool: `python3 -I ~/.claude/skills/launch-video/first10-check.py` (before install:
`<repo>/skills/launch-video/first10-check.py`). It rewrites `report.md` on every run; hand-written lines go in `measure/reads.md`.

1. **Audio check first** (P15, step 2): `--audio-only` reports loudness, true peak, speech, floor, gap and clipping, with the
   clipped bins' times. Clipping in speech → re-record. No floor or gap bar: METHOD gives no number for "bad", and v1, a
   3.0M-view hit, reads a 24.9 or 15.3 dB gap by method (`measure.md` §1). Compare with the founder's mic reference
   (UNTESTED), or ask which mic recorded it. Raw voice only, never a mix. His mic rule [42:17]-[42:27] is not a measured cause (P15).
2. **Then the full report in the background** (`--name`, `--prompt`, `--sheets`; slow under load, `measure.md` §6). Read it
   against step 29 as reference only. Human reads stay human (§8 q6): the turn, the demo start, face and screen share, "key
   detail moving by 3 s", and real edits as opposed to app switches.
3. **Leak check** (step 46): read every `redact-NN.jpg` (1 frame a second), then at full size every frame showing a URL bar,
   dashboard, terminal, inbox, settings page or customer list, and every shot under 1 s the report lists (first and last
   included); a 1 fps sample can step over a flash. A failed audio or leak check goes back as a HAND-OFF with timestamps.

**Exit check:** `measure/report.md` (tool) and `measure/reads.md` (keep-or-re-record call, leak findings, human reads).

## Stage 5. Edit and export

Detail: `edit-export.md`. This stage decides what to do; `hyperframes` and `media-use` own how.

1. **Raw take:** `auto-editor --preview`, then trim with `--no-open`, keeping product-working ranges with `--keep`. v1's
   70-72 s wait for Clicky's answer (-61 dB, A1) was left in; reading it as a beat, not dead air, is INFERRED. No added music.
2. **Produced cut:** a rough cut planned on the transcript, a HyperFrames composition in `work/` from a formed request
   (`edit-export.md`, "HyperFrames intake"), licensed background music only; a voice recorded afterwards is laid over here.
3. **Captions** on every Instagram and TikTok version and every produced cut, in his measured shape (3-6 words near 80% of
   height on 16:9, 1-3 words near 63-69% on 9:16; step 42; below the frame when a screen take's action sits low); an X raw take
   stays uncaptioned only if the screen carries the meaning on mute (INFERRED). HyperFrames routes, media-use caption files,
   and the ffmpeg-full fallback (PATH ffmpeg lacks `drawtext`, `subtitles`, `ass`; MEASURED): `edit-export.md` §3.
4. **End** on a soft spoken CTA, an invitation, never "sign up" (step 44). His sat in the last 3-7% in 3 of 6 videos, and v2,
   his biggest X hit, had none (step 29: a habit, not a position to hit).
5. **Export** (`mkdir -p out`): one primary platform, then cross-posts (step 45 [33:23]); X 16:9; 9:16 by letterbox (UNTESTED)
   or a center crop; -14 LUFS, -1 dBTP (a feed target, INFERRED, not METHOD); assert every file with `ffprobe`.
6. **HAND-OFF:** `open` the master. The founder watches it end to end (launch-film operator-feedback rule 8), sets final
   pacing, the music and when not to cut, and runs the bounce test, "am I bouncing, when am I bouncing?" [22:48] (step 32),
   marking the times; the agent cuts or reworks those spans before export.

**Exit check:** every export in `out/` passes the ffprobe assertions, and the founder has watched the master.

## Stage 6. Copy, the mute test and the stop test (`copy.md`)

1. **X post in his order** (step 21 [07:53]-[07:58]): "I built this thing", what it is, what it does, why it matters; in his
   four posts that becomes plain claim, what it is, what it does or the turn, use or proof, often "Demo:" (A1). Do not pad:
   v2, his biggest X hit, ran 151 characters. The template does not predict views (294K and 2.9M, §3.5).
2. **Self-reply** with the tagged link and an honest note. The link is not in the post: his habit in all four launch posts,
   never stated as a rule, with split evidence on X's link treatment; test it (step 26). The log records the reply's delay
   (q14). Then copy for the other platforms in `setup.md` `platforms` only (step 22; variants in `copy.md` §2-3).
3. **Hook type** (picked in Stage 1; definitions in `copy.md` §5): demo hook by default; curiosity gap for a newcomer; story
   hook only with a real prior success; no niche call-out until a niche in organic users is recorded (step 52; q13).
4. **Mute test** (step 25): the agent lists the measured mute read of the take beside `script.md`'s planned words; the
   founder confirms the read.
5. **Stop test** (steps 23-24), HAND-OFF: his "number one rule, regardless of Twitter, Instagram, YouTube, anything" [08:59]
   (P6, Anecdote). The founder swaps the draft into a stranger's post in their own feed with DevTools (`copy.md` §6) and
   asks "did my eye stop?" [08:50]; rewrite line one until it does. A static mock is a weaker, labeled fallback (q4). To test
   a line that will be spoken, run it before Stage 3. The bounce test [22:48] is the founder's too; a bounce here returns to Stage 5.

**Exit check:** the founder's eye stopped on one draft in their real feed (or a labeled mock); `copy.md` is complete.

## Stage 7. Pre-post checks

Step 46 plus this skill's rules, in `checklist.md` (`package.md` §2): redaction with the sheet paths; every track in
`licenses.md`, or "no music"; every number in `claims.md`, cross-checked against `launch_film_project`; every mechanic real;
no other project on screen; the HAND-OFF "I have to show what I made to at least 1 person" (W1 S7). Post even if it feels
bad: volume buys chances at a hit [20:25] while the typical post stays flat (Buffer, X1 §2.7); his two surprises are n=2.

**Exit check:** every row filled; every "no" fixed, or, for founder-decided rows only, waived in the founder's own words. The
Music and Truth rows are never waived (`package.md` §2).

## Stage 8. Package and hand off

`package.md` §1, §3: one folder per post (exports, `copy.md`, `captions.srt`, `licenses.md`, `checklist.md`, the report, a
log row). `open` it. The message, said in this session, lists the files and the order: primary platform, cross-posts, the
self-reply; then walk away from the counter [17:05], not from the thread (step 49). No gate question.

**Exit check:** `post-log.md` has each post URL; post and self-reply times come from fxtwitter's `created_at` once the founder
pastes each URL (MEASURED, `curl -s https://api.fxtwitter.com/<user>/status/<id>`). A missing self-reply URL stays `open`.

## Stage 9. After posting (`setup-and-log.md` §4-8)

1. **Thread** (HAND-OFF): the founder pastes each reply's URL; the agent reads it live with `curl -s https://api.fxtwitter.com/2/thread/<reply_id>`
   (never x.com in the founder's browser, Dia or a browser MCP) and drafts through `outbound-drafting` (`copy.md` §10).
2. **Day 7, not before unless asked** ("maybe a week later" [17:10]): X by fxtwitter, YouTube by `yt-dlp`; the founder pastes
   Instagram, TikTok and LinkedIn numbers (no reader exists; §8 q8; LinkedIn INFERRED, as §5 names only the first two).
3. **Downloads, then retention, then people** (step 50; "I do not care about the traffic at all" [07:05]): tagged signups or
   downloads, users active on each of days 1-5 [07:27]-[07:30], then messages drafted through `outbound-drafting`. Never
   divide downloads by views and call it a conversion rate.
4. **Weekly review** (step 55): the best post, its device, what to reuse; channels compared only after 4-6 weeks on medians
   of tracked conversions (step 51, INFERRED). Hiring only when production time limits cadence and a channel converts (step 57).

**Exit check:** the post's day-7 row is complete.

## Fast path: a raw take, same session

The beat card, the take, Stage 4's audio check and leak sheets (`--no-asr --sheets`), a dead-air trim, the X post and
self-reply, Stages 7-8; no ASR, captions, music or crops unless Instagram or TikTok is wanted. v1 went up about 13 min after
the take (A1; timezone INFERRED), but deciding to post took weeks (W1 S3; §7.5). Agent time here is unmeasured; log it.

## Neighbor skills and appendices

Route by name. `hyperframes`: every composition, caption, zoom and render (never `/product-launch-video`). `media-use`: music,
SFX, transcription, caption files, cut and reframe (no TTS for the founder). `video-understanding`: measuring a reference
video. `agent-browser`: web inserts. `demo-recording`: window sizing, `-R` capture, terminal takes, host facts, capture
hygiene, silent loops. `launch-film`: the README hero. `read-twitter`: swipe-file posts. `outbound-drafting`: any message.

Appendices: [boundary.md](boundary.md) (the three skills; each launch-film verdict) · [setup-and-log.md](setup-and-log.md)
(setup, tags, post log, platforms, review, 30-day challenge) · [script.md](script.md) (candidates, registers, templates) ·
[copy.md](copy.md) (copy, hooks, the tests) · [capture.md](capture.md) (stage, takes, shot list) · [measure.md](measure.md) ·
[edit-export.md](edit-export.md) · [package.md](package.md) · [open-questions.md](open-questions.md) (METHOD §8 resolved) ·
[coverage.md](coverage.md) (steps 1-64, P1-P20) · [first10-check.py](first10-check.py).

## Do NOT

- Treat step-29 habits, the 1,000-view promise or his conversion figures as thresholds or facts (§7.1, §7.3).
- Put words in the founder's mouth: an agent-written line they did not rewrite is the most likely to sound read (K1).
- Show a life instead of the work: "You'll never catch me making those videos about this is my day as a YC founder." [25:52]
- Judge a channel by views, or by one post (step 51); use a story hook with no real success to cite (§3.5).
- Close or move a window or pane the agent did not open, or clear the founder's shell history (`capture.md` §1); restage
  his frames or post his lines word for word (the templates carry structure, `boundary.md` §3, 10-02).

**Sources:** `docs/research/farza-launch-video-method-2026-10-24/METHOD.md` (§1-§8) and its `agents/` evidence files;
`skills/launch-film/SKILL.md` and `operator-feedback.md`; the neighbor skills above.
