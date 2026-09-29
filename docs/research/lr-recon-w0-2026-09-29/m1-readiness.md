# M1: composer painted -> first Enter the TUI accepted (W0, 2026-09-29)
Source: 25 verified bundles (`$HOME/.reso/limit-recover/*/bundle-*/events.jsonl`) plus 31 upgrade dirs (population B, separate). Script `raw/m1-bundle-readiness.py`; exact output `raw/m1-bundle-readiness.txt`. All numbers below are measured by that script.

**Definitions** (they follow `lr_submit_cr` and the submit loop in `scripts/limit-recover/lr-fire-resume.sh`). A run is one `relaunch-typed` segment. `paint` = `composer-painted`. CR1 goes out right after that note, so paint->CR1 = 0 s by construction. A re-send is a `SUBMIT-RECR` row. `accept` = the transcript time (ms) of the user record carrying the run token, taken from the `submitted`/`queued` detail. The accepted CR is the last CR sent at or before `accept`. CR1 counts as swallowed if a RECR or `FAILED:submit` follows it. `ss` = the last SessionStart hook record in the transcript, in s after CR1. Event rows have 1-s resolution, so the times carry up to +1 s of bias.

| sid | rt->paint | RECR | verdict | paint->accept s | accepted CR (sent at s) | CR1 swallowed | ss |
|---|---|---|---|---|---|---|---|
| 3afa727e | 4 | 0 | queued | 0.2 | #1 (0) | no | -1.6 |
| 415a3aac | 5 | 1 | submitted | 32.3 | #2 (32) | yes | 6.3 |
| 46bc0436 | 7 | 1 | submitted | 43.6 | #2 (43) | yes | 1.8 |
| 55120708 | 7 | 1 | submitted | 34.6 | #2 (34) | yes | -1.2 |
| 5714603f | 5 | 0 | queued | 0.1 | #1 (0) | no | -1.2 |
| 60ccb8f4 | 6 | 0 | submitted | 0.2 | #1 (0) | no | -1.6 |
| 64b7c77a | 5 | 0 | queued | 0.7 | #1 (0) | no | -0.6 |
| 7c395da7 | 9 | 0 | submitted | 1.5 | #1 (0) | no | 1.2 |
| 8463599e | 3 | 0 | queued | 0.3 | #1 (0) | no | -0.6 |
| 8ea01453 | 9 | 0 | submitted | 7.4 | #1 (0) | no | 7.2 |
| c769ca76 | 4 | 0 | queued | 0.1 | #1 (0) | no | -1.5 |
| cfb177b2 | 9 | 1 | submitted | 36.7 | #2 (36) | yes | 6.9 |
| fedc17b9 | 5 | 0 | submitted | 24.3 | #1 (0) | no | 4.5 |
| 10 runs, no paint (CR-UNCONFIRMED): 18e3fd78 3d42fa49 4a956c3b 4eecc91f 6fdffc57 798afadf 82542697 a32de00a e44c8e8c x2 | - | 0 | 3 sub, 1 queued, 6 FAILED | 0.2 / 16.0 / 43.7 / 0.1 | #1 in all 4 accepted | 6/10 | |
| 3 runs, no paint and no CR row (emitter before 2026-09-22): 2825e1e5 7c8201f8 b6125384 | - | 0 | 3 FAILED | - | - | - | |

**Painted runs, population A.** paint->submitted: n=8, p50 24.3 s, p90 43.6 s, max 43.6 s. With the queued runs included: n=13, p50 1.5 s, p90 36.7 s. Which CR was accepted: CR1 in 9 of 13 runs (sent at 0 s), CR2 (the first re-send) in 4 of 13, sent at 32, 34, 36 and 43 s. No run needed a third CR. CR1 was swallowed in 4 of 13.
**Population B (upgrade).** 17 dirs have no events.jsonl, and 2 more never reached a CR row. Of 5 painted runs, all 5 had CR1 swallowed. One (7c395da7) was accepted on CR2 at 43 s. Four ended FAILED:submit (3 with the screen reading EMPTY, 1 after a RECR at 32 s). A grep for their run tokens in the transcripts finds none. Of 7 unconfirmed runs, 1 was submitted at 0.9 s.
**Two readings of paint->accept.** fedc17b9 (24 s) and 8ea01453 (7 s) are CR1 acceptances whose record landed late. fedc17b9 was queued behind a running turn. In 8ea01453 the Enter was held until the SessionStart hooks finished (+7.2 s). So the 24.3 s p50 measures when the record lands, not when a CR has to be sent.

**The data are censored.** Every accepted re-send was the only re-send the current code tried: a single look at about 30 poll iterations, which lands 32-43 s after CR1 in wall time. So 32-43 s is an upper bound on readiness, and the data cannot say whether a re-send at 10 or 25 s would also have landed. SessionStart hooks were done by 7.2 s after CR1 in every painted run (p90 6.9 s). In 55120708 they had finished before CR1 and CR1 was still swallowed. So boot latency alone does not explain the swallow.

**Recommendation: `LR_RECR_SCHEDULE=10,45,60`** (s after CR1, wall clock).
- The first two re-sends must cover >=90% of the observed accepted-CR send times. The observed offsets are 0 x9, 32, 34, 36, 43 (A), plus one more 43 in A+B. With the second re-send at 45 s, coverage is 13/13 in A and 14/14 in A+B.
- The default `10,25,40` covers 9/13 (69%). `10,40,55` covers 12/13 in A (92%) but only 12/14 in A+B (86%).
- The re-send at 10 s comes after the latest SessionStart finish (7.2 s) and the latest held-CR1 record (7.4 s). It is the cheap test of early readiness. It still fires only when nothing is in the transcript and the composer reads DRAFT-MINE.
- 60 s is the tail. The schedule must run on elapsed wall time: iteration counts drifted 32-43 s against a nominal 29 s.

## The throwaway drill (lead, same day): uncensoring the re-send times

The bundle recommendation above is SUPERSEDED by this section for the schedule's first entries (the
bundle table is unchanged). Driver `raw/m1-drill.py`, raw output `raw/m1-drill-runs.txt`. 10 kitty
windows the session created, all relaunched at once with `claude --resume <sid>` on CC 2.1.284
(the fleet's binary: 16 of 17 live claude processes at the time), load1 35-62 on 10 cores. Per pane:
wait for the empty composer (a `❯` row between two rule rows), type the draft, wait until the
composer shows it (lr-fire-resume's DRAFT-MINE), send CR 1 at once, then re-send every 2 s while the
draft is still in the composer. Accepted = the marker's user record is in the transcript.

| run | transcripts | draft | relaunch→paint | CR 1 accepted | paint→accepted CR sent | paint→user record |
|---|---|---|---|---|---|---|
| 1 | ~0.4 MB | 30-char plain text | 7.3-10.3 s | 10/10 | p50 0.30 s, max 1.00 s | 2.5-11.1 s |
| 2 | ~1.0 MB (~80k tokens) | 30-char plain text | 13.6-15.7 s | 10/10 | p50 0.05 s, max 0.19 s | 1.6-7.5 s |
| 3 | ~1.0 MB | model-only skill `/keybindings-help` | 8-16 s | void: CC refused the command itself ("can only be invoked by Claude") — the Enter was consumed, not swallowed | — | — |
| 4 | ~1.0 MB | 265-char user-invocable slash command `/lrw0-noop <marker> ingest <path> --record-id … run:<token> …`, the shape of the real `/limit-recover ingest` prompt | 20.3-24.9 s | 10/10 | p50 0.18 s, max 0.62 s | 3.2-6.3 s |

**What it shows.**
- 30 of 30 valid drill panes accepted the first Enter sent ≤ 0.62 s after DRAFT-MINE. No re-send was
  ever needed, so at 2.1.284 the TUI is ready to submit the moment it paints our draft.
- An accepted Enter clears the composer in < 2 s (no pane ever re-read DRAFT-MINE at its 2 s look),
  while the user record reaches the transcript 1.6-11.1 s later (UserPromptSubmit hooks run first).
  So a **transcript-only** submit check misreads a slow write as a swallow; the swallow evidence is
  the draft still in the composer.
- The drill did not reproduce the bundles' 4/13 first-CR swallows. They ran on older binaries,
  typed through expect (`^U`, then the text as one pty write), and cross-account; the drill isolates
  that none of readiness, transcript size, concurrency at load 35-62, or slash-command input causes a
  swallow on 2.1.284.

**Recommendation: `LR_RECR_SCHEDULE=5,15,30,45`**, each re-send gated on the composer still reading
DRAFT-MINE (which is already how the submit loop gates a re-send). A gated re-send costs nothing: an
accepted Enter leaves the composer within 2 s, so DRAFT-MINE at +5 s is proof the first Enter was
lost, and Enter on our own draft can only submit it. 5 s recovers a swallow ~30 s sooner than the
measured 32-43 s re-sends; 45 s still covers the bundles' latest observed acceptance (43 s).
