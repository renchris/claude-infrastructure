# D1 skeptic review: codebase retrieval on wide sweeps (2026-10-08)

Reviewed: `/tmp/haiku55-decisions/D1-retrieval-wide.md`, its 100 rows, and the harness under
`/tmp/haiku55-decisions/d1/`. No new model calls were made. Every number below is measured by a
python3 recompute over `D1-retrieval-wide.rows.jsonl` unless it names another source or is marked
estimated.

## Verdict

The action survives; the conviction and three sentences of the write-up do not.

- **Keep medium as the configured rung, low as slack.** I agree, but as a tie broken by cost of
  error, not as a measured preference. This run gives zero evidence that medium beats low.
- **My conviction: 80%**, below the worker's 88% and not above the 85% the decision carried in.
  A measurement that removes the stated reason for medium cannot raise conviction in medium.
- **"Low did not collapse on sweeps of this size" holds** (0 recall failures in 20 runs, 21 with
  the pilot).
- **"Never high" holds only for sweeps of this shape.** The vendor chart the write-up leans on to
  keep medium says the opposite about high for truly wide search (see finding 2).

## Recomputed headline numbers

| Claim in the write-up | Write-up | Recomputed | Match |
|---|---|---|---|
| Rows, served model = requested | 100, none dropped | 100 of 100; also 100 of 100 in `d1/raw/*.json` `modelUsage` keys | yes |
| 5.5 @low exact sets, true files found | 20 of 20, 482/482 | 20 of 20, 482/482 | yes |
| 5.5 @medium exact sets | 20 of 20, 482/482 | 20 of 20, 482/482 | yes |
| 5.5 @high exact sets, mean precision | 17 of 20, 0.987 | 17 of 20, 0.987 | yes |
| Haiku 4.5 recall, exact, errored | 0.868, 10 of 20, 2 | 0.868, 10 of 20, 2 | yes |
| Opus 5.5 @low exact sets | 20 of 20 | 20 of 20 | yes |
| Median output tokens low / medium / high / Opus low | 2126 / 2536 / 3976 / 802 | 2125.5 / 2535.5 / 3976 / 802 | yes |
| Median turns, median wall (s), low / medium / high | 4, 5, 6; 10, 12, 18 | 4, 5, 6; 10.4, 12.1, 18.0 | yes |
| Sign test, output tokens, low vs medium (n = 10 questions) | 8 to 2, p = 0.11 | 8 to 2, exact two-sided p = 0.109 | yes |
| Sign test, output tokens, medium vs high | 10 to 0, p = 0.002 | 10 to 0, p = 0.002 | yes |
| Sign test, recall, low vs medium | 0/0/10, p = 1.00 | 0/0/10; no discordant pair, so the test carries no information | yes |
| 5.5 vs Haiku 4.5 on F1 | 6/0/4, p = 0.03 | 6/0/4, p = 0.031 | yes |
| Upper bound on low's miss rate from 0 of 20 | 14% (26% at n = 10) | 13.9% (25.9%) | yes |

Stored recall, precision, exact and tp agree with my own rescoring on 100 of 100 rows. Answers,
served model, output tokens and turns in the rows agree with the raw CLI JSON on 100 of 100.

## The checks asked for

1. **Ground truth fixed by a program before the models ran: yes.** `shasum -a 256` of `truth.json`,
   `questions.tsv` and `truth.py` equals `truth.sha256` (stamped 05:03:11Z). `stat` shows the first
   model output at 05:03:38Z (the pilot) and the first scored run at 05:04:19Z. Rerunning
   `truth.py` on the models' working corpus reproduces all 10 frozen sets. Independent grep
   one-liners reproduce 10 of 10 sets (the worker's 8, its `w01.grep`, and my own grep for w04).
   The corpus is byte-identical to `git archive 3b3af122d bin scripts hooks lib` (796 of 796 files)
   and the working directory held nothing else. No judgment enters scoring. The one judgment sits
   in question w01's wording (finding 1).
2. **Identical tools, prompts and inputs: yes.** `cell.sh` builds one prompt per question; only
   `--model` and `--effort` vary. Haiku 4.5 gets no `--effort` because it takes none. Same binary,
   account, working directory, tool list. Order was shuffled (arms mixed in every quarter of
   `jobs.txt`). Not checkable: which tool calls each run made, because the raw JSON holds only the
   final result.
3. **Served model read on every row, substitutions dropped: yes.** `score.py` drops any row whose
   `modelUsage` keys differ from the requested id; 0 of 100 did.
4. **Is n large enough?** For "low does not collapse": yes. 0 failures in 20 runs has probability
   0.0008 if the per-run failure rate were 30%, and 0.028 if only the 10 questions are independent.
   For "low is as good as medium": no test applies, because there are zero discordant pairs. Ruling
   out a 5% failure rate needs about 59 failure-free independent runs (estimated, 0.95^59 = 0.048).
   For "low is cheaper": no, 8 to 2 is p = 0.109; an exact Wilcoxon signed-rank on the same 10
   differences gives p = 0.131.
5. **Ceiling effect: yes, and it decides the review.** Low, medium and Opus 5.5 @low all scored
   recall 1.000 on all 10 questions. The low versus medium comparison has no room to show anything.
   Only Haiku 4.5 separated, and for a reason unrelated to effort (two runs overflowed its 200K
   window after 22 turns of reading files).
6. **Does the recommendation follow from the numbers?** No. The numbers say tie on quality and a
   small unproven edge to low on cost. "Keep medium" comes from the prior plus the vendor chart.
   The write-up says so openly, which is to its credit, but then raises conviction from 85% to 88%.
7. **Cheaper explanation.** Each question resolves to one to three Grep calls whose output is the
   answer, and no true set exceeds 40 paths, so nothing is truncated. Copying a short tool result
   needs no reasoning. Low and medium also barely differ in behavior here (finding 3), so there was
   little for the effort setting to act on.

## Findings that change the write-up

1. **A low-effort run with a wrong file was left out.** The pilot (`d1/pilot.jsonl`, raw file
   `claude-haiku-5-5_low.w01_src_jev.pilot.61460.json`) is Haiku 5.5 @low on w01, served
   `claude-haiku-5-5`, run after the question and truth were frozen and with the same `cell.sh`
   (`stat`: `cell.sh` created 05:03:27Z and never modified; pilot output 05:03:38Z). It returned 9
   files for a true set of 8, adding `hooks/anti-deference-nudge.sh`, the same file high added in
   both of its w01 runs. So across all runs made under identical conditions, low is 20 of 21 exact,
   not 20 of 20, and "high was the only Haiku 5.5 rung to return a wrong file" is false. Recall is
   unaffected (the pilot found 8 of 8). Leaving a pilot out is normal; not reporting that it
   contradicts a headline sentence is not. The precision argument against high is now one stray
   file on w05 (1 of 20 runs), plus a wording trap on w01 that low also fell into.
2. **The vendor chart is read selectively.** The fleet's own notes
   (`docs/research/haiku55-upgrade-2026-10-07/notes/card-p111-129.facts.json`, fact c111-90) record
   Haiku 5.5 on the vendor's wide-search benchmark as low 3.5%, medium 12.9%, high 37.3%. That
   chart does not single out low. Medium is also near the floor, and the big step is medium to
   high (+24.4 points). If that chart is the reason to avoid low, it is an equal reason to distrust
   medium and to prefer high for truly wide search, which contradicts "do not use high." The
   benchmark is also web research over tens to hundreds of entities at up to dollars per task,
   against a repo sweep costing a median $0.002 to $0.004 per run here, so its transfer to this
   role is weak in either direction.
3. **The positive control does not cover the contrast that matters.** "Effort reached the model"
   is shown for high (higher than medium on 10 of 10 questions for both output and thinking tokens,
   p = 0.002). For low versus medium it is not: output tokens 8 to 2 (p = 0.109), thinking tokens
   8 to 2 (p = 0.109, read from `modelUsage.thinkingTokens` in the raw files), and the median
   thinking tokens run the wrong way (low 986, medium 880). The write-up cannot use the same 8 to 2
   both as proof that effort took hold and as a saving it calls unproven.
4. **The saving is smaller than quoted.** 16% is the gap between medians. On total output tokens
   low is 10.7% below medium (47,886 vs 53,609 over 20 runs each), and on the CLI's reported cost
   10% below (mean $0.00246 vs $0.00272; sign test 6 to 4, p = 0.75). Two reps of the same question
   in the same arm differ by a median 21% (low) and 29% (medium), which is larger than the gap.
5. **"57% more on every one of the 10 questions" overstates.** High's median is 57% above medium's.
   High was higher on all 10 questions, by amounts from 0.5% (w02) to 226% (w01).

## Recommendation after review

Keep `haiku55_retrieval` at medium with low as the slack rung, and keep high off for greppable
sweeps of this size. Record the reason as: low and medium tie on two measured task classes (narrow
lookups, and sweeps up to 40 files), low's saving is about 11% of a cheap token stream and not
established, and a missed file in a retrieval answer is silent, so the tie goes to the rung that
costs slightly more. Remove "low collapses on wide sweeps" as a reason. Do not cite the vendor
chart as support for medium, and do not write "never high" without the size limit.

Conviction 80%. It would move above 90% only with a sweep hard enough to leave the ceiling.

## Not settled by this measurement

- Whether medium is better than low at anything. Both sat at the ceiling on every question.
- Whether low is cheaper than medium (p = 0.109 at n = 10 questions).
- Sweeps with more than 40 true files, truncated Grep output, or a per-file judgment after the
  search. This is where the rungs could separate, and where high might be needed.
- Whether medium itself holds up on genuinely wide search. The vendor's number for it is 12.9%.
- Loosely worded sweeps, and real Explore spawns under a lead with a long brief.
- Per-question failure rates under about 26% for low or medium (2 reps, 10 questions).
- The plan-quota ratios (0.38 and 0.32 of Opus 5.5 @low). They rest on the 0.12 weight from the
  earlier upgrade study, which these rows cannot check.
