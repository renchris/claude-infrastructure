<!-- markdownlint-configure-file { "MD013": false } -->

# The post folder, the pre-post checklist and the hand-off (Stages 7 and 8)

The agent stops here: it writes the folder, opens it, and lists the founder's acts. It never posts, replies or messages anyone (§5; §8 q3), and it asks no gate question: the method has no gates beyond the founder's stop and mute tests and the step-46 checks (§6 table, "Approval"). Section numbers point to METHOD; "he" and "his" mean Farza.

## 1. The post folder

Everything for one post lives in `<log-dir>/posts/<yyyy-mm-dd>-<slug>/`:

| File | Holds | Made | Gated by | Owner |
| --- | --- | --- | --- | --- |
| `candidate.md` | the row from the week's `posts/<yyyy>-W<nn>-candidates.md`, the caption angles (they are the hook variants, `script.md` §2) and the one the founder picked, the grounding frame | Stage 1, before building | the clarity check: a caption that excites the founder (step 12) | agent drafts; founder picks |
| `script.md` | the script or beat card, setup block, turn, CTA, the 10-second plan, planned mute-read words, the shot list (`capture.md` §7), `script_by` | Stage 2 | none; the founder runs the three reading tests (step 19) as self-checks (hard rule 2) | founder's words; agent's structure |
| `raw/` | untouched takes (`capture.md` §6) | Stage 3 | the frame check for agent inserts (a quality check, not an approval) | founder records; agent inserts |
| `measure/` | `audio-gate.md`, `report.md` (both rewritten by the tool on every run), `reads.md` (hand-written: mic, keep call, leak findings, human reads; the tool never writes it), `asr.json`, `asr.srt`, `cuts.json`, `first10.jpg`, `faces-NN.jpg`, `redact-NN.jpg`, `hires-*.png` | Stage 4 | clipping and leaks; habits are reference only | agent measures; founder decides |
| `work/` | trims, caption files, this post's HyperFrames project | Stage 5 | none | agent |
| `out/` | `x-16x9.mp4`, `yt-16x9.mp4`, `ig-9x16.mp4`, `tt-9x16.mp4`, `li-16x9.mp4`, `thumb-*.jpg` | Stage 5 | ffprobe assertions; then the founder's watch of the master (a hand-off, not an approval) | agent; founder sets pacing and music |
| `copy.md` | every platform's text, ready to paste (§3) | Stage 6 | the founder's stop test (step 23) | agent drafts; founder edits |
| `captions.srt` | proofread captions | Stage 5 | proofread against the audio | agent |
| `licenses.md` | every track and asset with its license, or "no music" | Stage 5 | step 46 | agent records; founder clears |
| `checklist.md` | §2 | Stage 7 | every row filled or waived | agent evidence; founder decides |
| `log-row.md` | the pre-filled post-log row (`setup-and-log.md` §4) | Stage 8 | none | agent |

Only the `.md` files are tracked by `~/Development/personal`'s allowlist; media stays local (`setup-and-log.md` §2).

## 2. `checklist.md` (step 46 plus this skill's rules)

The three step-46 checks are this study's additions, not Farza's advice (INFERRED unless cited); the redaction check is modeled on demo-recording's "no leaked content" gate.

```markdown
# Pre-post: <slug>   <date>

## Leaks (step 46; measure.md §5)
- [ ] read every redact-NN.jpg (1 frame a second) and, at full size, every frame with a URL bar, dashboard, terminal, inbox,
      settings page or customer list, and every shot under 1 s the report lists. The sheets are a 1 fps SAMPLE: a flash
      shorter than a second can fall between samples (demo-recording "Capture hygiene")
- [ ] no account or workspace IDs, API keys, tokens, .env contents, or secrets in a terminal, editor or shell history   # v2: a Stripe account ID (R4 §3)
- [ ] no email addresses, phone numbers, or customer or user names
- [ ] no live revenue, dashboards or support counts the founder has not chosen to show       # v2: "1 dispute has not been answered"
- [ ] no metrics or architecture a clone could use (X1 §2.3)
- [ ] no notification banners, other people's messages, or another project's name, goal or plan, the founder's or anyone's (hard rule 4)
- [ ] no cloud account IDs, ARNs, bucket or host names unless the founder chose to show them (CLI and infra tools, capture.md §1)
- [ ] no Claude Code composer ghost text (demo-recording)
- [ ] FOUNDER: decided what may be shown

## Music (step 46; launch-film Do NOT)
- [ ] every track listed in licenses.md with its source and license, or "no music"
- [ ] the source is on setup.md's accepted list (open-questions.md q15)
- [ ] no unlicensed music playing from an app on screen                                  # v2's AC/DC (A1)
- [ ] FOUNDER: cleared the music

## Truth (§6.4; launch-film §1.6)
- [ ] every number on screen or in the copy is in claims.md with its rule and date
- [ ] every anecdote, time or event in a hook was filled by the founder, not left as an agent guess (hard rule 4)
- [ ] every mechanic shown really happens in the product as shown: no mock-up, staged result or sped-up wait presented as real (launch-film §1.6; hard rule 6). Not waivable
- [ ] if it is not shipped yet, the post and self-reply say so, and "This is real, and shipped" is dropped
- [ ] the problem and stakes are true and the founder's own (launch-film §1.6 "stakes are true"; [13:36])
- [ ] the "what it is" line matches `setup.md` `one_liner` everywhere (§6.5)

## The checks that make it land
- [ ] first-10-seconds report read; differences from his habits noted, not "fixed" by rule (measure.md §4)
- [ ] mute test: FOUNDER confirmed the read (copy.md §7)
- [ ] stop test: FOUNDER's eye stopped in their real feed, or a labeled mock (copy.md §6)
- [ ] captions burned in on every Instagram and TikTok version (edit-export.md §3)
- [ ] audio: FOUNDER's keep call recorded in measure/reads.md
- [ ] FOUNDER watched the master end to end, with the bounce test (copy.md §8)

## Links and tags (step 4)
- [ ] no link in the X post (the default), or logged as a link-in-post test; the tagged link is in the self-reply
- [ ] each platform's link carries this post's tag; the YouTube description link is tagged (if YouTube is in `platforms`); with no domain, the bare repo link and a referrer-report read date (copy.md §2)
- [ ] X post and self-reply each at most 280 by the X-weighted count (script.md §2)

## One person (W1 S7)
- [ ] FOUNDER showed it to at least one person: "And then, I have to show what I made to at least 1 person."
      who: ____   what they said: ____

## Boundary (§6.2-6.3)
- [ ] nothing here replaces a README hero URL or writes a launch film's BRIEF.md or STATUS.md
- [ ] no demo footage, look or music is going into a launch-film hero
```

Every "no" is fixed before the hand-off. Only the rows the founder decides (what may be shown, the one-person row, a stop test run as a mock) may be waived, in the founder's own words. The Music and Truth rows are hard rules 4-5, shared with launch-film (METHOD §6.4, §6.6): a "no" there is fixed by removing the track or the claim, never waived.

**"I think it's bad"** (step 47). If every box is ticked and the founder still thinks it is bad, post it anyway; the "post it anyway" person in `setup.md` exists for this moment, and the agent is not that person (§5 row 7). He thought the Clicky demo "was not that good" [06:16] and was "so wrong" [06:37]; he thought the dictation video the worst they had made [14:26]; they got 3.0M and 2.95M X views (A1). Those are two anecdotes, n=2, and nobody knows how many he thought bad that stayed bad. The real reason is volume: posting more buys more chances at a hit while the typical post stays flat (Buffer, X1 §2.7). "I'm constantly forcing myself to put it out." [14:59] "99% of the time I think it's shit, someone else see's something cool." (W1 S7)

## 3. `copy.md` and the hand-off message

```markdown
# <slug>: copy (<date>)
## X post (<n> characters; link NOT in the post)
## X self-reply (the founder posts it when they choose; log the delay)
## Only the platforms in setup.md `platforms`, each as its own section:
##   Instagram caption (lower-case, short; link in the bio /ig)
##   YouTube title / description (tagged link in the description) / thumbnail candidates
##   LinkedIn (the X post's five lines; tagged link in the first comment; copy.md §3) / TikTok
## Mute read: planned (from script.md) / measured (first 3 s / first 10 s)
## Likely thread questions, with short honest draft answers (the founder uses them or not)
```

After `open "$P"` (launch-film operator-feedback rule 8: the operator judges by watching the delivered file), say in this session (never by mail, chat or a notifier):

> <slug> is ready: `out/x-16x9.mp4` (<s> s), `out/ig-9x16.mp4`, `out/yt-16x9.mp4`; copy in `copy.md`. Checked: audio, leaks, licenses, claims. Yours, in order: post on <primary platform>, then the cross-posts, then the self-reply with the link when you are back at the thread. Then walk away from the counter, not the thread. Paste each post URL here when it is up, and ask me for the day-7 read on or after <date + 7 days>.

The message lists acts; it does not ask "(yes / what to change)" (hard rule 2), and it schedules nothing (hard rule 10). After the founder posts, the agent writes the log row from the URLs they paste back. Post and self-reply times come from fxtwitter's `created_at` for each pasted URL (MEASURED: `curl -s https://api.fxtwitter.com/<user>/status/<id>`), never from memory; a missing self-reply URL stays `open` and is asked for at the day-7 read.
