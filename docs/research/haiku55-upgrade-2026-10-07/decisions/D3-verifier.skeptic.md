# D3 verifier measurement: skeptic review (2026-10-08)

Reviewed: `/tmp/haiku55-decisions/D3-verifier.md` and `/tmp/haiku55-decisions/D3-verifier.rows.jsonl`.
No model calls were made for this review.

## Verdict

I could not overturn the main line. The mechanics are clean and every headline number recomputes.
What does not hold up is how much the result is asked to carry: the stated risk bound is too tight,
the quota saving is not measured, the rung was picked on cost, and the test is too easy to say
anything about verifying beyond a one-line lookup.

**My recommendation:** keep verifier and judge slots on Opus 5.5 and leave D3 where it is. Allow
Haiku 5.5 only on the exact class measured (one line-cited claim against one inlined file, no
tools), and only in a week when quota is actually binding. Do not count this run as support for
Opus over Haiku, and do not widen Haiku's use until a harder set breaks the ceiling.

**Conviction: 78%.** About 85% on keeping Opus as the default, about 70% on the narrow Haiku
allowance being safe (both are my estimates, not measured).

## What I recomputed

Measured with `python3 /tmp/haiku55-decisions/d3-skeptic/recompute.py` and `extra.py`, written for
this review and independent of the worker's `score.py`. First row per cell, 80 scored calls.

| Claim in the write-up | My number | Match |
|---|---|---|
| Accuracy 119/120, 120/120, 120/120, 120/120 (Haiku medium, Haiku high, Opus medium, Opus high) | same, n=120 verdicts per arm | yes |
| False accepts 0/60 in every arm | same | yes |
| False rejects 1/60 Haiku medium, 0/60 elsewhere | same; the miss is `land-speed-census.py` C2, rep 2 | yes |
| Total output tokens 7,809 / 11,300 / 3,816 / 3,751 | same, n=20 calls per arm | yes |
| Median output tokens 431.5 / 503 / 150 / 150 | same | yes |
| Median wall 5.0 / 5.4 / 5.1 / 5.55 s; API about 2.4 / 2.5 / 2.2 / 2.3 s | 5.0 / 5.4 / 5.1 / 5.55; 2.39 / 2.51 / 2.18 / 2.28 | yes |
| Wilson 95% upper bound 6.0% on 0/60 | 6.02% | yes, as arithmetic |
| Sign tests: at most one discordant pair, p = 1.0, all six | same, n=120 claim-reps per pair; 0 discordant on the 60 false claims | yes |
| 81 calls, all served the requested model, none errored | 81 of 81 `served` equals the requested model; 0 failed; 0 `is_error`; `stop_reason` end_turn on 81; `num_turns` 1 on 81 | yes |
| One duplicate cell, identical verdicts | rows 0 and 25, Haiku medium `norm-share.py` rep 1, identical | yes |
| Key and corpus hashes | `shasum -a 256` matches `key.sha256` and all 10 lines of `corpus.sha256`; all 10 files equal `git show c3ed0a381:<path>` | yes |
| 14 failed launches, rows kept in `launch-failures.jsonl` | the file holds 9 rows (`wc -l`) | no, bookkeeping only |

## The checks asked for

**Was ground truth fixed by a program before the models ran?** Timing, yes. `key.json` was created
at 23:59:13 local on Oct 7 (matches `key.frozen-at`), the first failed launch wrote at 00:00:05, and
the rows file was created at 00:00:42 (measured, `stat` birth times). Content, mostly. The program
proves that the cited line contains one code string and lacks another. It does not prove the English
sentence is false. I read all 60 claims against their cited lines. The 30 true claims are true. Of
the 30 false claims, 26 are false on any reading. Four are logical weakenings that the code actually
entails if read strictly, and are "refuted" only by the convention that a claim must describe the
code's condition exactly:

- `scratchpad-reaper.sh` C1: "both is_live and is_recent succeed" where the code is `||`.
- `heldout-rate.py` C2: "every wanted id and the attempt is the second" where the code is `or`.
- `cc-wait` C5: "refused unless deadline is greater than or equal to 0" where the code is `-gt 0`.
- `branch-reaper.sh` C4: "at most the first 20 targets" where the code prints 10.

Every arm refuted all four in both reps (8 of 8 each, measured), so no score changes. Dropping them
leaves 0/52 per arm on 26 distinct false claims.

**Identical tools, prompts and inputs?** Yes for what the harness sent: one prompt builder, same
flags, `--tools ""`, one turn on every row, arms interleaved inside each file so no time-of-day
confound. One caveat outside the worker's control: the CLI adds a constant 580 to 588 more input
tokens for Haiku than for Opus on every file (measured, `cache_create`, 10 files, medium, rep 1).
A constant gap across files of different sizes is a different system block, not a tokenizer effect.

**Served model read on every row, substituted rows dropped?** Yes. 81 of 81 rows carry `served`
from `modelUsage` and all match. Nothing needed dropping.

**Is n large enough? Sign test.** The exact sign test is the wrong tool here and the write-up's
p = 1.0 means only that it has no power: with zero or one discordant pair it cannot reject anything.
The claim is "no difference," so what matters is the bound, and the bound is overstated. The 60
false-claim verdicts are 30 distinct claims run twice, and the two reps agreed on 239 of 240
arm-claim pairs (measured). Reps are near copies, so the honest n is 30. Zero misses in 30 gives an
exact 95% upper bound of 11.6% (Wilson 11.4%), not 6.0%. If Haiku's true false-accept rate were 5%,
this test would still show zero misses 21.5% of the time on 30 claims; at 2%, 54.5% of the time
(computed, binomial).

**Ceiling effect?** Yes, and it is the whole story. No arm scored below 119 of 120, so the test
has never shown it can catch a weak verifier. There is no arm that failed, no weaker model, and no
claims-only run to show the items cannot be guessed.

**Does the recommendation follow from the numbers?** Half of it. "Keep Opus as the default" is the
prior plus the absence of a measured gain from switching; nothing in these rows favors Opus.
"Admit Haiku on the narrow class" does follow from the numbers, as "not shown worse." "At medium"
does not follow from accuracy; it is a cost tie-break.

**Cheaper explanation.** Each item is settled by reading one cited line and comparing one literal.
The key's own builder does it with substring checks. Opus answered with no reasoning tokens at all
(exactly 150 output tokens, the bare JSON) in 31 of 40 calls and still scored 240 of 240 (measured).
The task is a lookup, and any competent reader passes it.

## Where the write-up overstates

1. **"0 of 60" and the 6.0% bound.** See above: 30 distinct false claims, bound about 11.6%.
2. **The quota saving.** The 0.25x figure multiplies the record's 0.12x per output token by the 2.05x
   token ratio. The record measured 0.12x where cache writes ran at about 0.4x output. Here cache
   writes are 21.3x output for Haiku medium and 40.6x for Opus medium, and output is 4.2% and 2.3%
   of all tokens per call (measured, n=20 calls each). The estimate is carried into a regime it was
   not calibrated for. The saving for this workload is not measured. The CLI's own dollar figure
   gives a ratio of 0.028 (measured, `cost_usd` sums), but that is list price, not plan quota.
3. **The rung.** High costs 175 more output tokens per call than medium, which is 1.9% more total
   tokens per call (measured). The "45% more" in the write-up is true of output alone. On the other
   side, Haiku medium answered with no reasoning tokens in 4 of 20 calls, Haiku high in 0 of 20
   (Fisher two-sided p = 0.106), and the one miss was in one of those four calls (151 output tokens;
   Fisher p = 0.2). Neither difference is established. Those four calls still caught 12 of 12 false
   claims. The data do not pick a rung.
4. **"Cited the right line, 120/120."** The claim text hands the model the line number. This column
   measures copying.
5. **Launch failures.** 14 stated, 9 rows on file. All were after the key was frozen, so nothing is
   contaminated. Whether they reached a model cannot be checked: stderr was discarded.

## Not settled

- Whether Haiku 5.5 falls behind on harder checks: no line cite, two lines read together, files over
  1,000 lines, several files, a verifier that reads the source with tools. This run is silent.
- Any false-accept rate under about 11.6%, for either model. Zero misses on 72 distinct false claims
  would bound it under 5%; under 1% takes 368 (computed, exact binomial).
- Judges. Not measured. The vendor evidence D3 rests on (grader self-preference, unscorable ratings,
  use of leaked answers) is about grading and visible answers, not about open-book line checks, so
  this run neither tests nor weakens it.
- The rung, and the size of any quota saving.
- Realistic wrong claims. These are single-token edits written by one Opus 5.5 session, and the key
  follows that session's reading convention.

## How this review was done

Read-only except for this file and three scratch scripts under
`/tmp/haiku55-decisions/d3-skeptic/` (`recompute.py`, `audit_key.py`, `extra.py`), which the brief
did not name. They are kept so the numbers above can be rerun. Git use was `git show` only.
