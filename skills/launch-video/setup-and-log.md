<!-- markdownlint-configure-file { "MD013": false } -->

# Setup, the post log, and measuring (Stages 0 and 9)

Sources: METHOD §3.0, §3.1, §3.10, §3.11, §3.13, §5 and §7.3. "The founder" is the operator whose product it is; "he" and "his" mean Farza.

## 1. The setup message and `setup.md`

**One HAND-OFF message, five questions together** (§8 q1-2). What blocks what: `mode` and `voice` block Stage 1 (they decide the register and route "neither" away); `mic` blocks Stage 3 only, since Stages 1-2 record nothing (INFERRED), so it may stay `open` until then; the rest is asked when its stage needs it.

> Setting up launch videos for <product>. Five quick ones:
> 1. How will you appear: full face on camera, a small face bubble only, voice-only, or neither? (Neither means launch-film or demo-recording instead.)
> 2. If no face: will you talk live while you drive the product, or record the voice afterwards over the screen?
> 3. Which external mic will you use? Laptop and AirPods mics "don't count" in this method.
> 4. Who is your "post it anyway" person, the one who overrules you when you think a take is bad?
> 5. Where do your users come from today, and which accounts will you post from (X, Instagram, YouTube, TikTok, LinkedIn, other)?

**Branches** (§8 q1; §7.5; `open-questions.md` q1):

| Answer | What it opens | Status |
| --- | --- | --- |
| `face` | every version-one register | his practice |
| `bubble` | the raw screen take and screen-led produced demos, with a webcam bubble; not the selfie minimum or vertical story | "a face bubble is enough" for screen-led demos (§7.5); his two biggest X hits show his face only as a bubble (A1) |
| `voice-only` + `voice: live` | the raw screen take, narrated live while the founder drives | UNTESTED: none of his six is voice-only |
| `voice-only` + `voice: after` | the produced demo's voice-over form only (`capture.md` §4); never called a raw take | UNTESTED, and further from his practice: his raw takes are live (step 41; §5 row 41 "narrate live") |
| `neither` | STOP: launch-film or demo-recording | §8 q1 |

Then write `setup.md` from this block. The agent fills what the repo can tell it; a field it cannot fill yet stays `open` and is asked when its stage needs it.

```markdown
# launch-video setup: <product>   (filled <yyyy-mm-dd>)
log-dir: ~/Development/personal/launch-video/<product>/            # §8 q2; private, local only

## Blocking Stage 1
mode: face | bubble | voice-only | neither                         # §8 q1; same enum as post-log `mode`
#   UNTESTED for voice-only: every one of his six measured videos shows his face (100% as a bubble
#   in the raw takes, 32-62% in the edited ones, §4a). Logged per post as `mode`.
#   neither: STOP. Use launch-film (README hero film) or demo-recording (silent README loop).
voice: live | after | n/a                                          # live = raw take; after = voice-over form (capture.md §4)

## Blocking Stage 3 (may be `open` through Stages 1-2)
mic: <model> | open  # any external mic; a used cheap DJI is fine [42:23]; laptop/AirPods "don't count" [41:46]-[42:27]

## Filled when needed (each `open` until then)
post_it_anyway_person: <name> | open                               # step 7; an agent saying "post it" does not count
users_come_from: <X | Instagram | YouTube | GitHub | ...>
platforms: <X @handle | Instagram @handle | YouTube channel | TikTok | LinkedIn | ...>   # Stage 6 drafts copy for these only
one_liner: "<the product's one-line value proposition>" | open   # §6.5; copied read-only from an approved launch film's words if one exists; change it here, on purpose
launch_film_project: <path to the film's BRIEF.md> | none        # read-only (§6.2); its on-screen numbers are cross-checked against claims.md
tiers: demos when something works, target <n>/week | team update weekly|biweekly|off | polished launch ~quarterly   # step 1
screen_recorder: Screen Studio | Cap | OpenScreen | OBS | screencapture | open   # step 3 [40:53]; asked at Stage 2 when the plan has a zoom
conversion: signup | download | install | paid | lead | <other> | open    # step 33; q11 for open source
retained_means: active on each of days 1-5 after first use        # [07:27]-[07:30]
tags: profile <domain>/x /ig /yt /tt; per post <domain>/p/<post_id> or ?utm_source=<platform>&utm_campaign=<post_id> | open
events_wired: signup-with-path | first-use | day1-5 query | none | open   # step 5; built only if the founder asks
music_sources: none | original (rights held) | licensed library | platform in-app | open   # q15
mic_reference: real <path> / laptop <path> | skipped               # optional, UNTESTED (measure.md §1)
first_four_weeks: 30-day challenge | <n> demos a week, fixed before week 1 | open   # q12
```

**How the agent fills it.**
- **Tiers** (step 1). Propose a calendar from the roadmap and `git log`: demos whenever something new works, ideally several a week ("demos every single day almost" [16:06]); a team update every two weeks [26:51] or weekly (the clip is titled "this week" [24:52]); a polished launch about once a quarter [15:57]-[16:02]; optionally a one-line teaser the day before a dated release, then a livestream (W1 S5). The founder picks.
- **Recorder** (step 3). Screen Studio is $29 a month or $9 a month billed yearly (MEASURED, K1); free options are Cap, OpenScreen and OBS; macOS Cmd-Shift-5 has no auto-zoom (§3.12).
- **Buy only what the register needs; audio comes first** (step 56). The gear list and the audio rule's ranking above picture appear nowhere outside the interview (UNTESTED, §7.6). Prices as of 2026-10-24, from K1 via METHOD §3.12 (`/Users/chrisren/Development/claude-infrastructure/docs/research/farza-launch-video-method-2026-10-24/METHOD.md`):

| Role | His tool, price | Free or cheap path |
| --- | --- | --- |
| Screen demo | Screen Studio, $29/month or $9/month yearly (MEASURED) | Cap, OpenScreen, OBS |
| Phone edit | Edits, free | CapCut's free tier |
| Audio (the one non-negotiable [41:46]-[42:27]) | DJI mic, "find them used online" [42:23]; Mic Mini kit about $79, Mic 3 kit about $249-259 (DOCUMENTED) | any external mic |
| Laptop edit | DaVinci Resolve 21, free; Studio $236 (MEASURED) | free Resolve |
| Cinematic (Level 3 only) | FX3 $4,299.99 list, FX30 about $1,800-2,100 (DOCUMENTED) | the phone's rear camera |
| Writing | FreeWrite, free, MIT license | any plain editor with a timer |

- **No external mic yet:** say so plainly. The agent can measure and lightly denoise a take, but it cannot turn a laptop-mic recording into a lav recording (K1). Then ASK: "Wait until you have one (his rule, step 2), or record now on the built-in mic, logged as `mic: laptop` against his rule?" The founder picks; the agent never decides. A `mic: laptop` take still goes through the Stage 4 audio check.

## 2. The product directory

```text
~/Development/personal/launch-video/<product>/
  setup.md        §1
  post-log.md     one row per post per platform (§4)
  claims.md       every number shown or written: value, rule, source, date, lasts (yes: may go in a film | no: dates itself, demos only) (§6.4)
  swipe.md        hooks that worked on the founder (copy.md §9)
  reviews/        <yyyy>-W<nn>.md, one per week (§8)
  posts/<yyyy-mm-dd>-<slug>/    package.md §1
```

It is private and local: `~/Development/personal` is a local-only git repo whose `.gitignore` is an allowlist admitting only `.md` and `.sh` (MEASURED, read 2026-10-24). So every log here is Markdown, and raw video stays untracked. The founder may move `log-dir`; nothing goes in a public repo, because the directory holds unposted copy, metrics and notes on users (INFERRED).

## 3. Tags, events, and conversion for an open-source tool

- **Tag every post, not only every profile** (step 4). His profile links were tagged: heyclicky.com/ig on Instagram [32:47], /x on the @heyclicky profile (A1), /yt on YouTube (R1 Insert C), /farza in his personal bio (R3 I10). His posts were not: the X self-replies linked clicky.so (v1) or heyclicky.com/try (v2-v4) (A1), and the YouTube dictation description a bare heyclicky.com (R2 §3.7). Give each post its own path or UTM (INFERRED). For a desktop app, give mobile visitors a "send it to yourself" button and track its click rate [32:58].
- **Product events** (step 5, INFERRED; C1 row 20): a signup or download event that carries the link path; a first-use event; a query for users active on each of days 1-5; optionally a "how did you hear about us" question. The agent writes the spec. It builds them only if the founder asks, through that repo's own change process, and never in a reso or reso-management-app repo. The founder grants analytics access and decides what counts as a conversion (§5 rows 4-6). Analytics access means a read-only API key the founder puts in the secrets store, or an export the founder saves to `<post>/measure/`; never the founder's logged-in dashboard (hard rule 1).
- **Open-source tool** (§8 q11; INFERRED, UNTESTED). In order of closeness to "downloads, then retention" (step 50):
  1. **Installs**: package-registry download counts (npm, PyPI, Homebrew analytics) or release-asset downloads, `gh api repos/<o>/<r>/releases --jq '.[].assets[]|{name,download_count}'`.
  2. **First use and repeat use**: only from opt-in telemetry the project already runs; never add telemetry for this. Returning issues or PRs from new users are a weak repeat-use signal.
  3. **Stars and issues**: early signals, like views, not conversions.
  4. **The tag**: with a domain, a redirect per platform and post (`<domain>/x/<slug>` to the repo) that counts its hits, since the repo owner sees no UTM data. With no domain, GitHub's referrer report (`gh api repos/<o>/<r>/traffic/popular/referrers`; push access; 14 days kept) gives sites, not posts. Read it within 14 days of each post.

## 4. The post log: `post-log.md`

One row per post per platform, including every post that did nothing. A cross-post gets its own row with the same `post_id`. METHOD's minimum is step 6's columns; the rest let the open questions this skill could not settle be answered from the log later (marked "test").

| Column | Filled by, when | Why |
| --- | --- | --- |
| `post_id`, `date`, `time_local`, `platform`, `account`, `url` | agent, from the URLs the founder pastes back | step 6 |
| `followers_at_post` | agent (X via fxtwitter) or founder | test: reach depends on the account (P17's confound) |
| `register`, `hook_type`, `hook_line`, `first_frame`, `length_s`, `aspect`, `primary_platform` | agent, at packaging | step 6; step 45 (reframing is untested) |
| `mode` (face, bubble, voice-only), `voice` (live, after, n/a) | agent | test, §8 q1 |
| `script_by` (founder, agent-draft, none) | agent | test, §8 q10 |
| `capture_by` (founder, agent) | agent | test, §8 q9 |
| `first_word_s`, `named_by_s`, `cuts_first10` | agent, from `first10-check.py` | test, §8 q7: lets the founder's own hits and misses be compared later |
| `mic`, `gap_db` | agent | P15; lets a "bad audio" line be found later |
| `captions`, `music` (track and license file, or none) | agent | step 42; step 46 |
| `link_path`, `self_reply_delay_min` | agent | step 4; test, §8 q14 |
| `founder_min`, `agent_min` | `agent_min`: from `date +%s` stamps the agent writes into `checklist.md` at each stage's start and end (MEASURED, `date`). `founder_min`: the founder's own figure, labeled an estimate. Never fill either from memory | test, §8 q12: the real weekly cost against §3.1's estimate |
| `stop_test` (real feed, mock), `shown_to` | agent | steps 23, 46 |
| `views_d7`, `likes_d7`, `bookmarks_d7`, `replies_d7` | agent for X and YouTube; founder for Instagram, TikTok and LinkedIn | his early signal [17:10], [46:22] |
| `link_clicks`, `conversions`, `d5_retained`, `leads` | agent from tagged events; founder for leads | steps 50-52 |
| `notes` | anyone | the device that made it work or fail |

Header line, written once:

```markdown
| post_id | date | time_local | platform | account | followers_at_post | url | register | hook_type | hook_line | first_frame | length_s | aspect | primary_platform | mode | voice | script_by | capture_by | first_word_s | named_by_s | cuts_first10 | mic | gap_db | captions | music | link_path | self_reply_delay_min | founder_min | agent_min | stop_test | shown_to | views_d7 | likes_d7 | bookmarks_d7 | replies_d7 | link_clicks | conversions | d5_retained | leads | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
```

About likes and bookmarks: on X his vertical stories had higher like rates (1.1-2.5% against 0.36-0.83%) and fewer bookmarks per like (0.21-0.22 against 0.52-0.82) than his horizontal demos, with two confounds unresolved: v6 came from an account with an eighth of the followers, and the topics differ (§4, "What the tables say"). Log both; read neither as a register effect.

## 5. Reading the numbers, and when

Look "maybe a week later" [17:10]: accept zero views at the moment of posting [16:56], since "By the time I hit post, I've already forgotten it." [17:05]. The agent fills the day-7 columns then, and does not report counts before that unless asked. The thread is different: answers and fixes go out as they come (`copy.md` §10).

```bash
curl -s "https://api.fxtwitter.com/<user>/status/<id>"        # X JSON: views, likes, retweets, replies, bookmarks (A1 used it)
cc-read-twitter "https://x.com/<user>/status/<id>"             # X text and the author's own thread (read-twitter skill)
curl -s "https://api.fxtwitter.com/2/thread/<reply_id>"        # one reply the founder pasted, read live for a draft answer (copy.md §10)
uvx --from 'yt-dlp[default]@latest' yt-dlp --dump-json "<youtube url>" \
  | python3 -I -c 'import json,sys;d=json.load(sys.stdin);print(d["view_count"],d.get("like_count"),d.get("comment_count"))'
```

A current yt-dlp matters: a stale build got HTTP 403 on 2026-10-24 (video-understanding). Instagram and TikTok have no reader here, and Instagram needs a login (W1): HAND-OFF, the founder pastes the counts from each app's insights (§8 q8). These are reads only; nothing is posted.

## 6. Downloads, then retention, then people (step 50)

"I do not care about the traffic at all." [07:05] For the Clicky launch he asked how many downloaded, "I think 7,000" [07:18]; then who retained, about 100 who used it "every day for five days straight" [07:27]-[07:30]; then "I reached out to those 100 people" [07:34], and their unexpected uses kept him going [07:38]-[07:42]. That is 1.4% of downloaders retained (arithmetic on his recall). He gives the window two ways, "four days later" [07:19] and "five days straight" [07:30] (§7.3); days 1-5 is METHOD step 5's cut of an anecdote.

**Never divide downloads by views and call it a conversion rate.** His 7,000 over the post's 3,000,762 views gives 0.23%, a ratio of two unlike numbers that gives the X post the most credit it could get: views count impressions, not people; 7,000 is his recall; the post had no link for 4 h 42 min; and the open-source repo was announced the next day, so the downloads cannot be attributed to the X post alone (step 50).

The agent drafts each message to a retained user through `outbound-drafting`; the founder sends them and holds the conversations (§5 rows 50-53). A stronger test from his vlog is a Stripe link right after the demo, with a target of 25 paying customers (W1 S15).

## 7. Channels: compare on conversion, and only once the sample can bear it (step 51)

Views stay the early signal for what to repeat: the 30-day challenge picks the next video by which one passed 1,000 views [46:22]-[46:36]. Channels are judged on conversion [32:38]-[33:13]. Decision rule (INFERRED, X1 §2.7, §2.9): outcomes are heavy-tailed, so compare after 4-6 weeks and several posts per channel, on medians of tracked conversions, never on one post. His own conversion figures are anecdotes, never benchmarks: 7,000 downloads, "like 20" percent on YouTube, 70% of traffic from Instagram (§7.3).

| Platform | His claim | Evidence status (§3.10) | What to do |
| --- | --- | --- | --- |
| X | Worst conversion over about 10 years [31:05]-[31:13]; "doom scrolling" [31:45]-[31:50]; wants 16:9 [33:39] | Views MEASURED (v1 3,000,762; v4 2.95M with conversion "horrendously low" [31:23]-[31:30]); conversion anecdote. Link treatment disputed: 94% fewer views for link posts in PPC Land's code analysis, against Musk's 2026-07 "for over a year" (X1 §2.9) | Reach and a credential; post 16:9; re-measure conversion yourself |
| YouTube | Best converting "for most companies" [31:54]-[32:00]; "a library that will last for decades" [32:16] | CONTESTED: "like 20" percent [31:37] would be about 4,200 downloads from 21K views, about 90 times the X ratio (X1). The description linked a bare heyclicky.com, so the 20% cannot come from a tag in that description (INFERRED, §3.10) | If YouTube is in `setup.md` `platforms` (ask once at setup whether the founder has or wants a channel): upload every feature demo with a tagged description link; spend real time on titles and thumbnails; read the Intro and Dips reports (step 32). Not on the list: no YouTube copy or export |
| Instagram | About 70% of traffic, "I think" [32:22]; the best audience "by far" [33:13]; most videos made for it [33:23] | Traffic share anecdote; counts on screen only; no slot read Instagram directly (W1) | Vertical first if Instagram is primary; tag the bio link and each post |
| TikTok | Business buyers are there too [30:14]-[30:23]; about 50 design-agency leads from videos averaging about 4,000 views [30:38]-[30:48] | Anecdote; no TikTok shown; a lead is not a deal (X1 §2.10). Tidbit's memes "juices algo" but converted "much lower" (W1 S8, S9) | Niche call-outs once a niche is found (step 52); count leads and pipeline, not views |
| LinkedIn | Named among the platforms [02:23] | MEASURED on screen only (R4 I-9, I-16) | Cross-post demos and milestones; measure like any channel |
| Reddit | The 2020 playbook [02:02]; a place for the 30-second selfie [27:41] | Named only | Optional cross-post; unmeasured |
| Facebook (paid) | Runs the 20.9M reel as an ad [21:17]-[21:22] | Anecdote | Turn a proven winner into an ad; the founder decides and buys |

## 8. The weekly review: `reviews/<yyyy>-W<nn>.md` (step 55)

The agent drafts it; the founder decides what to make next. Judge by the best post, not the median: Buffer's TikTok study of 11.4M posts from 150K+ established accounts found median views flat at 459-506 at every frequency, while the 90th percentile rose from 3,722 to 14,401 (X1 §2.7; other platforms and new accounts are untested). Volume buys a fatter tail; the claim that you also get better [20:15]-[20:25] is untested (§3.11).

```markdown
# Week <nn>, <yyyy>   posts: <n>   founder minutes: <sum>   agent minutes: <sum>   (§3.1 estimate: 2-8 h a week, unmeasured)

## Best post
<post_id> on <platform>   views_d7 <n>   conversions <n>   device that made it work: <hook | first frame | register | platform>
reuse next week as: <one concrete post using that device>

## The rest, by views relative to this account's own median
| post_id | platform | views_d7 | x median | conversions | device |

## One change at a time
tried: <the one thing changed>   result: better | worse | can't tell yet

## Channels   (write "too early" before 4-6 weeks and several posts each; then medians of tracked conversions)

## Retained users to talk to (founder)
<n> users active on days 1-5; drafts through outbound-drafting; the founder sends them   # [07:34]; W1 S3

## Niche signal (step 52)
organic users from one niche that "found us naturally" [29:42]-[29:53]: <who, how many>  -> a call-out hook next?

## Let winners keep working (step 53)
- [ ] best demo on YouTube with a tagged link (it "will keep on performing" [32:12])
- [ ] candidate for a paid ad (founder decides and buys)
- [ ] clips for the landing page (heyclicky.com uses demo .mov windows, R1 Insert E)
- [ ] a silent README loop of a raw take, through demo-recording, never the hero
- [ ] an open-source release as a second launch (W1 S4)
# Reuse what shows something new, not the same ask: over-promotion is a top reason people unfollow (Sprout Social, X1 §2.1).

## Hiring (step 57)
production time, not ideas, limits the cadence?  yes/no      one channel shows tracked conversion?  yes/no
# Suggest contract creative help only when both are yes (X1 §2.12). No time threshold is set; the founder decides.
# Daily in the early days; delegate later (§7.5: [39:22] vs [46:00]). Product first; the audience compounds on top (§7.5: [40:22] vs W1 S17).
```

Even his hits are irregular: the same copy template gave 2.9M and 294K six days apart (§4d), "No one sees 2025" (W1 S19), and he calls his filmmaker "maybe the most important part of my stack" [42:37]-[42:39], with a collaborator behind every recent run of videos (W1; §7.2).

## 9. Time budget (§3.1, INFERRED from his own figures; nobody has measured it)

| Item | His figure | Source |
| --- | --- | --- |
| Daily demo | 10 minutes a day | [28:44], [46:00] |
| Team update | 10 minutes of capture; edit unstated, and the produced one is plainly more (R3, INFERRED) | [26:30] |
| Produced feature video | "like an hour" for him, up to 4-6 hours | [20:50], [22:14] |
| Long-form YouTube story | about 8 h, 3 of them on thumbnails | W1 S10 |
| A founder alone: daily demos plus one produced video a week | about 2-8 hours a week | §3.1 |

Log `founder_min` and `agent_min` per post so that week 4 replaces this estimate with a measurement (§8 q12).

## 10. The 30-day challenge (steps 58-64), for a founder who has never posted

UNTESTED: the challenge appears nowhere outside the interview (X1 §2.14; §7.6). For anyone who has been building something but never talked about it online [45:46]-[45:58]: every day, 10 minutes [46:00], any phone [46:01]-[46:02]; record what you did that day [46:04]-[46:06]; post it to Instagram or TikTok, where a new account is fine, "so your existing followers don't even know" [46:08]-[46:15]; "30 days straight, every day, one video" [46:17]. On day 30, find the one that passed about 1,000 views, ask why, and base the next one on it [46:22]-[46:36]. The agent's part: the daily prompt when the founder opens the skill (a scheduled reminder only if the founder sets one up in their own calendar or reminder app; the agent schedules and sends nothing, §5; hard rule 10), the log row, captions, the day-30 review. His "I promise you" [46:20] is not data (X1 §2.14).

**Be cringe first** (P18, Anecdote): "you got to be cringe for a little while actually to learn how to not be cringe" [28:12]-[28:28]; keep posting after a first video that feels horrible. Expect most early posts to do little: "If you don't take a thousand shots, you're not gonna make the five thousandth shot." [20:25]; about 10 videos before "you get really good at talking about stuff" [22:28] (QUOTED, untested). With no filmmaker, "go back to my old Zip School videos" and just start [44:03]-[44:25].

**Run it as a measured experiment** (§3.13; X1 §2.14, INFERRED): log all 30 posts as in step 6 (`post-log.md`), reuse the hooks of the top three in the next ten, and set expectations from Buffer's base rate below, not from "I promise you" [46:20].

**If none passes 1,000** (step 64, INFERRED; he does not cover it): Buffer's established accounts have a median of a few hundred views a post, and a new account may start lower. Rank the 30 by views relative to the account's own median, take the top three, change one thing each time (the hook, the first frame or the platform), and run another 30.

**Format and logistics.** Selfie videos need a face; a `bubble` or `voice-only` founder runs the challenge as daily raw screen takes, with the bubble or voice only (INFERRED, UNTESTED). Posts go to Instagram or TikTok [46:08]-[46:10] as 9:16 (letterbox a screen take, `edit-export.md` §4); add that account to `setup.md` `platforms` before day 1. No reader exists for either, so the founder pastes each post's views into `post-log.md` by day 30 (§8 q8).
