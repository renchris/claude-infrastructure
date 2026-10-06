# E1h slot: population accrual. When could a fully fresh certification set exist?

Written 2026-10-06 by a worker agent. Counts only: no candidate prompt was printed or read. The analysis
used only the `stratum` and `source` fields (source timestamp, plus the session-id prefix for session counts).

## What was run

- Measured: `python3 scripts/research-kit/heldout-candidates.py --history "$HOME/.claude*/history.jsonl"
  --days 400 --cap 10000000 --cap-for {regex-matched,regex-missed,pushback,other}=10000000
  --out /tmp/e1h-research/cands.jsonl` (worktree HEAD `ff3e87fb7`; the brief's `git pull` was NOT run, because
  this worker may not mutate git). Output: 7,433 transcripts, 4 history files; **other 25,457, pushback 49,
  regex-matched 681, regex-missed 617** (E1g phase 4: 25,434 · 49 · 681 · 612 a day earlier).
- Each row is placed in 7-day bins counted back from now (2026-10-06T06:07Z). The bin is set by the source
  timestamp: ISO for transcripts, epoch ms for `history:` rows. All 26,804 rows parsed.
- Afterwards `/tmp/e1h-research/cands.jsonl` was deleted. A cands.jsonl from an earlier run (01:03 local)
  already existed and was overwritten by this run's `--out`.

## Weekly counts (measured, from the bucketing script over cands.jsonl)

Week 0 = the 7 days ending 2026-10-06T06:07Z. Each cell is total (transcript t / history h).

| wk | starts | pushback | regex-missed | regex-matched | other |
|---|---|---|---|---|---|
| 0 | 09-29 | 0 | 89 (89t/0h) | 29 (26t/3h) | 934 |
| 1 | 09-22 | 0 | 96 (96t/0h) | 31 (30t/1h) | 2636 |
| 2 | 09-15 | 0 | 91 (90t/1h) | 23 (23t/0h) | 354 |
| 3 | 09-08 | 1 (1t) | 109 (109t/0h) | 14 (12t/2h) | 617 |
| 4 | 09-01 | 2 (1t/1h) | 62 (60t/2h) | 10 | 482 |
| 5 | 08-25 | 4 (3t/1h) | 51 (47t/4h) | 21 | 1113 |
| 6 | 08-18 | 3 (0t/3h) | 35 (34t/1h) | 35 | 763 |
| 7 | 08-11 | 2 (h) | 5 (2t/3h) | 3 | 1099 |
| 8 | 08-04 | 5 (h) | 4 (h) | 14 | 811 |
| 9 | 07-28 | 2 (h) | 10 (h) | 10 | 1008 |
| 10 | 07-21 | 1 (h) | 4 (h) | 7 | 551 |
| 11 | 07-14 | 3 (h) | 22 (h) | 46 | 1066 |

| window | pushback | regex-missed | regex-matched | other |
|---|---|---|---|---|
| last 4 weeks | 1 = **0.25/wk** | 385 = **96.3/wk** | 97 = **24.3/wk** | 4,541 = 1,135/wk |
| last 12 weeks | 23 = **1.92/wk** | 578 = **48.2/wk** | 243 = **20.3/wk** | 11,434 = 953/wk |
| whole store (~52 wk) | 49 = 0.94/wk | — | — | — |

Monthly pushback (measured): 2025-10..2026-07: 1,1,1,6,5,1,0,3,6,6; **2026-08: 16; 2026-09: 3; 2026-10 so far: 0**.
The last pushback-stratum prompt is dated 2026-09-14T02:35Z.

Poisson 95% intervals on the pushback rate (estimated, exact Poisson): 1 in 4 wk gives 0.01–1.39/wk;
23 in 12 wk gives 1.22–2.88/wk; 49 in 52 wk gives 0.70–1.25/wk.

Cross-check (measured): since `tuning-v2.jsonl` was created (2026-10-05T00:59Z) there are 12 regex-missed,
4 regex-matched and 86 other. E1g recorded 8 · 5 · 67 at the v3 mine a few hours later, so the two agree.
Since the v3 mine (2026-10-06T03:08Z) there are 3 regex-missed, 0 regex-matched, 0 pushback and 19 other.

Session spread (measured, transcript rows, distinct session-id prefixes per week): regex-missed weeks 0–3 come
from 44, 54, 46 and 55 sessions, with no session above 14 rows. They span four config dirs and the main repo,
worktrees and the personal project. So the regex-missed stream is broad, not one burst.

## Yield per sealed prompt (from RESEARCH_PROGRAM_BUILD.md E1c, E1g)

- pushback agreed: v2 7/37 = 0.19; v2+v3 11/46 = 0.24. Counted (agreed AND the agreed label is a relay
  label): v2 5/37, v3 2/9, pooled 7/46 = 0.15.
- regex-missed counted (relay-gold): v3 25/326 = 0.077; v2 34/228 = 0.149; pooled 59/554 = 0.106.
- regex-matched counted: v3 47/144 = 0.33; v2 24/64 = 0.375.

## Weeks to accrue a fully fresh set (estimated: needed raw prompts ÷ weekly rate; the binomial gives the raw count)

"Mean" = target ÷ yield. "P≥0.9" = the smallest n with P(Binomial(n, yield) ≥ target) ≥ 0.9.

| stratum, target | raw needed (mean / P≥0.9) | at last-4-wk rate | at last-12-wk rate | at whole-store rate |
|---|---|---|---|---|
| pushback, ≥5 agreed (p 0.19) | 26 / 41 | 104 / 164 wk | 14 / 21 wk | 28 / 44 wk |
| pushback, ≥5 agreed (p 0.24 pooled) | 21 / 32 | 84 / 128 wk | 11 / 17 wk | 22 / 34 wk |
| pushback, ≥5 counted (p 0.15) | 33 / 51 | 132 / 204 wk | 17 / 27 wk | 35 / 54 wk |
| regex-missed, ≥25 counted (v3 yield 0.077) | 326 / 408 | **3.4 / 4.2 wk** | 6.8 / 8.5 wk | — |
| regex-missed, ≥25 counted (pooled 0.106) | 235 / 293 | 2.4 / 3.0 wk | 4.9 / 6.1 wk | — |
| regex-matched, ≥25 counted (0.33) | 77 / 93 | 3.2 / 3.8 wk | 3.8 / 4.6 wk | — |

Read in calendar terms from 2026-10-06 (estimated):
- **regex-missed and regex-matched**: fresh sets of 25 counted could exist in about **4–9 weeks** (early November
  to early December 2026).
- **pushback is the binding stratum.** At the 12-week rate it is about **17–27 weeks** (February–April 2027). At
  the whole-store rate it is about **34–54 weeks** (mid-2027 to late 2027). At the last-4-week rate it is **2–4
  years**. The last 4 weeks hold 1 pushback prompt; the stream has been almost dry since mid-September.
- **other**: about 1,000/week, so it is never the constraint (v3's 273 sealed, giving 148 agreed, is under one
  week).

## Caveats that change the reading

1. **The regex-missed rate depends on which store a prompt sits in.** In the last 7 weeks, 92% of rows are from
   transcripts (wk0–3: 384 of 385). Transcripts carry the "first prompt after a done-claim" channel, which
   history cannot. Before 2026-08-11 only history covers the weeks, and those read 4–22/week. The jump at
   week 6–7 is the store boundary, not a change in the operator. New prompts will have transcripts, so the
   last-4-week rate is the relevant one, but:
2. **Transcripts are kept about 60 days.** An after-claim regex-missed prompt whose transcript is purged comes
   back from history as `other` (or not at all). A fresh regex-missed set must be mined within about 8 weeks
   of its earliest prompt. The 3–9 week accrual fits inside that, but there is no room to wait for pushback
   and collect regex-missed along the way. Pushback is 44/49 from history (about a year deep), so retention
   does not limit it.
3. **Pushback repeats are not new.** The miner dedups on the first 200 characters, so a re-typed "are you
   sure?" is not a new candidate, and an exact repeat of a v1/v2/v3 prompt is excluded anyway. Short
   stereotyped challenges therefore accrue only as new wordings. This may be why the rate fell after the
   August peak (16). Whether the live re-ask hook changed the operator's phrasing is not knowable from counts.
4. **The yields come from small sets.** The pushback agreement rate rests on 46 prompts (11 agreed). The
   regex-missed yield halved from v2 (0.149) to v3 (0.077). The week estimates move by about 1.5–2× with that
   choice.
5. **Not checked:** whether a recent row is already in v1/v2/v3. That would need the sealed sets, which this
   worker may not read. Every row dated after 2026-10-06T03:08Z is fresh by construction (3 regex-missed, 19
   other so far). The rates above are store accrual rates, and new prompts are assumed fresh, as the brief says.
6. Whether transcript "user" prompts in worktree sessions are all typed by the operator, rather than injected
   by automation, cannot be told without reading prompts or transcript bodies, which was not done. The 44–55
   distinct sessions per week argue against one automated source.
