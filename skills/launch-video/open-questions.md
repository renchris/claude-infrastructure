<!-- markdownlint-configure-file { "MD013": false } -->

# METHOD §8: how this skill resolves each open question

Each of the 15 questions in METHOD §8 gets either a **DEFAULT** (what the skill does, why, and the source) or an **ASK** (the founder question the skill puts, and where), or both. A default nobody has tested is marked **UNTESTED**: it is a starting point to log against, never a threshold. METHOD §8 q7 is the reason: the step-29 habits are survivor habits.

| # | Question (short) | Resolution | Kind | Logged as |
| --- | --- | --- | --- | --- |
| 1 | Who is on camera? | Ask at Stage 0 (face, bubble, voice-only, neither; live voice or after); neither routes away; voice-only is UNTESTED | ASK | `mode`, `voice` |
| 2 | Scope; where the log lives | A separate skill; a private, local product directory | DEFAULT | |
| 3 | The outbound line | Stop at the folder; every message drafted through outbound-drafting | DEFAULT | |
| 4 | The feed-mockup test | The founder, in their own real feed; a mock only as a labeled fallback | DEFAULT + ASK | `stop_test` |
| 5 | Captions | HyperFrames; ffmpeg-full only as a measured fallback | DEFAULT | `captions` |
| 6 | What the first-10-second check scripts | `first10-check.py` measures; people read the rest | DEFAULT | `first_word_s`, `named_by_s`, `cuts_first10` |
| 7 | Controls before thresholds | Reference columns only; no thresholds in this version | DEFAULT (UNTESTED by design) | same three columns |
| 8 | Unmeasured anchors; Instagram and TikTok numbers | Not needed; the founder pastes platform numbers at day 7 | DEFAULT + ASK | `views_d7` and the rest |
| 9 | Agent-recorded demos | The founder records the raw take; agent inserts pass a frame check | DEFAULT, UNTESTED | `capture_by` |
| 10 | Script authorship | The agent structures, the founder writes the lines; one A/B | DEFAULT + ASK, UNTESTED | `script_by` |
| 11 | Conversion for an open-source tool | Installs first, stars as reach; a redirect as the tag | ASK, with an UNTESTED default | `conversions` |
| 12 | Validate before codifying | A pre-registered first four weeks, or the 30-day challenge | ASK, with an UNTESTED default | `founder_min`, `agent_min` |
| 13 | Registers in version one | Three of §3.3's eight in, plus the selfie minimum; one conditional; four out | DEFAULT | `register` |
| 14 | Link timing | The link in a self-reply; the founder times it | DEFAULT + ASK, UNTESTED | `self_reply_delay_min` |
| 15 | Music licenses | No music on raw takes; documented licenses only | DEFAULT + ASK | `music` |

## 1. Who is on camera?

**ASK** in the Stage 0 setup message (`setup-and-log.md` §1, which holds the branch table), then branch:
- **Full face on camera:** every version-one register.
- **Face bubble only:** every screen-led register, with a webcam bubble. METHOD's own resolution: "For screen-led demos, a face bubble is enough" (§7.5), and his two biggest X hits show his face only as a bubble (A1). Not the selfie minimum or the vertical story.
- **Voice-only, narrated live:** the raw screen take leads; v1 and v2 are screen-led, with his face only as a bubble. The team update runs as a narrated screen walk.
- **Voice-only, voice recorded afterwards:** the produced demo's voice-over form only, never a raw take, since his raw takes are narrated live (step 41; §5 row 41). Order of work: `capture.md` §4 (INFERRED).
- **Voice-only, either way:** **UNTESTED:** none of his six measured videos is voice-only (A1), P13 says "show yourself, show your face very clearly" [12:30]-[12:44], and METHOD's resolution that "a face bubble is enough" for screen-led demos (§7.5) does not cover no face at all. The selfie minimum and the vertical story need a face. Logged as `mode` on every row, so the weekly review can see whether it matters. The operator's products are mostly developer tools, the audience the raw take served (§3.3).
- **Neither:** this method does not apply. Route to launch-film for a hero film or demo-recording for a silent loop.

## 2. Scope, and where the post log lives

**DEFAULT.** `launch-video` is its own skill beside launch-film and demo-recording, not a pointer inside either: the unit, cadence, person on screen and success measure all differ (§6 table). METHOD's working name `demo-launch` became `launch-video`. The log lives in `~/Development/personal/launch-video/<product>/`: private, local only, outside every product repo, because it holds unposted copy, metrics and notes on users (INFERRED). That repo's allowlist admits only `.md` and `.sh`, so the log is Markdown. **One claims rule, one ledger per product** (§6.4): before adding a number to `claims.md`, read the product's launch-film project (`setup.md` `launch_film_project`; its board and script, read-only) for the same quantity. If the film shows it, copy the film's value, rule and date into `claims.md` with the film as the source. If the take measures something different, show both to the founder and post neither until it is settled. Never write into the film's files: no demo writes the film's files (§6.2). launch-film's story gate may read the post log for value points and "the most impressive true claim" (§6.1), but launch-film's SKILL.md does not point at this ledger, so a film session reads it only if pointed to (INFERRED); Stage 0 records `launch_film_project` and Stage 7 cross-checks. The founder may move `log-dir`.

## 3. The outbound line

**DEFAULT.** The skill stops at a ready-to-post folder: files, copy, the self-reply, captions and the checklist. The founder posts, replies and answers the thread. Messages to retained users, collaborators or anyone else (DMs, emails, replies to someone's words) are drafted through `outbound-drafting`, whose read-the-medium-live rule fits a reply in a thread, and the founder sends them. Reason: posting and messaging are the founder's acts, and the harness forbids an agent sending anything outbound (§5).

## 4. The feed-mockup test

**DEFAULT.** The founder runs it in their own real feed with DevTools, following `copy.md` §6. The agent writes the draft and the steps, and never drives the founder's logged-in X session: the text swap is local, but the session is the founder's, and one wrong click in a logged-in feed is a public act. agent-browser's default session is a fresh profile that cannot see the founder's feed. Its CDP mode (`--cdp`, agent-browser "CDP Mode") can attach to a logged-in browser, and that is exactly the drive of the founder's session this rule forbids: never attach `--cdp` to the founder's browser for this test (hard rule 1).

**ASK** only if the founder cannot run it: "Can I use a static mock instead? It is a weaker proxy." The test's value is the real feed around the post (R2 §3.2; §5 rows 21-24). Logged as `stop_test: real | mock`.

## 5. Captions: HyperFrames, or a full ffmpeg build?

**DEFAULT: HyperFrames** for every burned-in caption, as the mandatory entry for any composition. `/embedded-captions` for talking-head footage; `/general-video` for a voice-only screen take or a mixed cut (`edit-export.md` §3). MEASURED 2026-10-24: the ffmpeg on PATH (`~/.claude/bin/ffmpeg`) has no `drawtext`, `subtitles` or `ass`, as K1 found, but `/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg` is already installed and lists all three; demo-recording records the same escape hatch. So nothing is installed, and ffmpeg-full is a fallback for a plain static SRT burn-in only when the HyperFrames route fails, re-checked before each use. Remotion's presence is unmeasured (§5), so the skill does not use it.

## 6. Which first-10-second checks become a script

**DEFAULT.** The split follows what A1 had to do by eye (§5 rows 27-29):

| Check | How |
| --- | --- |
| Length, size, fps; first-word time; name-said time; words in 0-10 s and the last 7%; early-ending speech | `first10-check.py` (whisper-cli `-ojf` tokens) |
| Hard cuts in the first 10 s and in total; shots under 1 s; soft changes | `first10-check.py` (luma difference at fps=30) |
| Loudness, speech, floor, gap, clipping, stereo background music | `first10-check.py --audio-only` |
| Title card at frame 0; captions by 1 s; key detail moving by 3 s; the demo start; the turn; a CTA; face and screen share; real edits as opposed to app switches | a person (the agent proposes from the sheets; the founder confirms) |
| The mute, stop and bounce tests | the founder |

MEASURED 2026-10-24 on A1's copy of v1 with A1's transcript: the tool reproduced A1's first word (0.08 s), name time (2.36 s against A1's 2.4), hard cuts (3, at 43.03, 82.87 and 84.63 s against A1's 84.62), cuts per minute (1.8) and whole-file mid level (-32.0 against -32.1 dBFS) (`measure.md` §6).

## 7. Controls before thresholds

**DEFAULT: no step-29 habit is a gate in this version.** The report prints his range beside each measurement and marks a difference "differs", never "fail" (`measure.md` §8). Promoting any habit to a check first needs A1's method run, through video-understanding, on the §4d lower performers (1,192,157; 453,200; 344,065; 341,900; 294K; 201,590 and 145,280 views), to see whether it separates the 3M posts from the 145-450K ones. That fieldwork is not done (§9, "Not done"), and this skill does not claim it. The post log collects `first_word_s`, `named_by_s` and `cuts_first10` for every post so the founder's own hits and misses can answer it later.

## 8. Unmeasured anchors, and Instagram and TikTok numbers

**DEFAULT.** The skill depends on neither the 20.9M reel (A1 could not find its source) nor the agent-interface video made from the shown script (never located, §3.4); both are cited only as METHOD does, as partial reads from inside the interview (§4c).

**ASK** at each day-7 read: "Can you paste the Instagram, TikTok and LinkedIn insights for this post?" No reader exists here, and Instagram needs a login (W1); LinkedIn is INFERRED, as §5 names only the first two. The agent reads X (fxtwitter) and YouTube (yt-dlp) itself.

## 9. Agent-recorded demos

**DEFAULT, UNTESTED.** The raw "check this out" take is the founder's live session; the agent prepares the stage. The agent records deterministic web flows (agent-browser, a named session, closed on every path) and terminal flows (demo-recording) in a demo account, as inserts in a produced cut or the screen track under a voice-over. Every agent recording passes the frame check (`capture.md` §2), because a draft run MEASURED agent-browser WebM at 10 fps with 3-8 frames for 3.5-6 s flows, under load. Reason: K1 judges a scripted agent-driven run to read "as a product tour, not as a founder working", and agent-driven desktop capture is fragile. The operator's launch-film verdicts against "very "tutorial"" walkthroughs point the same way, though they were about films.

**Test:** if the founder wants to try an agent-recorded take narrated live, log `capture_by: agent` and compare in the weekly review.

## 10. Script authorship

**DEFAULT.** The agent drafts beats, timings and two line options per spoken line: from a 10-minute voice interview for a produced script, from `candidate.md` for a raw beat card (no interview). It marks `script_by: agent-draft`; the founder writes or rewrites every spoken line and runs the reading tests as self-checks, never a block; the rehearsal card holds beats only (`script.md` §5-6). K1 judges an agent-written script the most likely to sound read, but his Tidbit TikToks used a collaborator's script (W1 S8), so this is a question to test, not a ban.

**ASK** once, on the first produced demo: "Record one beat from my draft and the same beat in your own words; then your 'post it anyway' person, or anyone who saw neither script, picks the one that sounds less read without knowing which is which; you note your own pick separately." Log both picks, and which take was the agent's, in `setup.md`; `script_by` per post (UNTESTED; n=1 per founder).

## 11. Conversion for an open-source tool

**ASK** in `setup.md` which conversion counts, with this **DEFAULT, UNTESTED**, in order of closeness to "downloads, then retention" (step 50):
1. **Installs**: registry downloads or release-asset download counts.
2. **First and repeat use**: only from opt-in telemetry the project already has; never add telemetry for this.
3. **Stars and issues**: reach, like views, not conversion.
4. **The tag that stands in for `/ig`**: with a domain, a redirect per platform and post (`<domain>/x/<slug>` → the repo) that counts its hits. With no domain, GitHub's referrer report (`gh api repos/<o>/<r>/traffic/popular/referrers`; push access; 14 days kept), read within 14 days of each post.

Commands: `setup-and-log.md` §3.

## 12. Validate before codifying

**ASK** before week 1, written into `setup.md`: a founder who has never posted runs the 30-day challenge (`setup-and-log.md` §10); everyone else runs a pre-registered first four weeks (INFERRED split; both options UNTESTED; X1 §2.14 for the challenge): the cadence (for example, three raw demos and one produced demo a week; an illustration only, INFERRED, not from METHOD), the signal that picks the next video (views, per step 51), and the conversion measure. The four-week window follows X1 §2.9's 4-6 weeks. Nothing becomes a threshold before then. Every row logs `founder_min` and `agent_min`, and the week-4 review sets the real weekly time against §3.1's 2-8 hour estimate.

Expect most early posts to do little: "If you don't take a thousand shots, you're not gonna make the five thousandth shot." [20:25]; about 10 videos before "you get really good at talking about stuff" [22:28] (QUOTED, untested). With no filmmaker, "go back to my old Zip School videos" and just start [44:03]-[44:25].

## 13. Which registers belong in version one

**DEFAULT** (`script.md` §3):
- **In:** the raw screen take (his two biggest X hits, v1 and v2); the produced feature demo, with an UNTESTED voice-over form (v3, v4); the 10-minute team update; and the selfie minimum (not one of §3.3's eight: METHOD calls it "the minimum version of any register" [22:19]-[22:24]), close to the 30-day challenge's format (§3.3 keeps them separate).
- **Conditional:** the vertical story, only if the founder is on camera and has a real milestone to cite, since the story hook "needs prior success" (§3.5).
- **Out of version one,** each for a reason: the niche call-out needs a niche found in organic users first (step 52); the fast-cut progress reel rests on 3 luma cuts in about 10 s (step 36); the long-form YouTube story is about 8 hours of work (W1 S10); the teaser-then-livestream is a copy line and a clip from an existing take, kept in `copy.md` §4 without a template of its own.

Of these, A1 measured the raw take, the produced demo and the vertical story on his own posts; the team update was seen only inside the interview (R3 I12). Revisit after four weeks of the log.

## 14. Link timing

**DEFAULT.** The link goes in a self-reply, not the post: his habit in all four launch posts (A1, step 26), never stated as a rule; METHOD says "Test it yourself". A founder who tries a link in the post logs `self_reply_delay_min: in-post`, so the same 4-6 week comparison below covers it. The delay is not copied: his 4 h 42 min to 7 h 46 min is a measured habit with no tested effect, and X's link treatment is disputed (94% fewer views for link posts in PPC Land's code analysis, against Musk on 2026-07-29 saying there had been no penalty "for over a year"; X1 §2.9).

**ASK** in the hand-off: "Post the reply when you are back at the thread." The log records `self_reply_delay_min`. After 4-6 weeks with several posts each way, the weekly review may compare short and long delays on median tracked clicks: a loose A/B, labeled as one. UNTESTED.

## 15. Which music sources count

**ASK** at setup (`music_sources` in `setup.md`), with this **DEFAULT**, in order:
1. **No music.** The default for a raw take: none of his raw takes has added music (A1).
2. **Original music the founder or a collaborator made and holds the rights to** (INFERRED; METHOD §8 q15's "original music only" option). Record it in `licenses.md` as "original, by <who>, <date>, rights held"; that line is its documented license.
3. **A track with a written license that covers the platform**, its license text or receipt saved in the post folder and named in `licenses.md`. A media-use `resolve --type bgm` result, or a generated track, counts only with its license or provider terms recorded; unstated terms count as unlicensed (INFERRED).
4. **Platform in-app audio**, added by the founder inside the platform's own app at post time, on that platform only and never baked into a cross-posted master (INFERRED from how platform licensing usually works; check each platform's terms).

Who picks: the founder picks the song, whatever its source ("the script and the song and the vibe" [43:26]-[43:28], P19). Picking a song does not license it: a founder-picked commercial track still needs item 3 or 4. Free first: a paid or credit-spending source (a paid library, a media-use generation) only after the founder approves it with the cost stated (launch-film §0.10; operator, 2026-10-02).

Never: an unlicensed song playing inside the demo (v2's AC/DC, A1), a ripped commercial song, or a track with no terms. The rule is launch-film's Do NOT, "Use music without a documented licence", adopted in step 46.
