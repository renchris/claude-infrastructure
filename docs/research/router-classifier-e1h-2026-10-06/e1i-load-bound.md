# Would a load-bounded re-read of row 15 pass? (receipt for decision 416e61ae1569, 2026-10-07)

Timing data only: no sealed set, no label and no correctness was read for this note.

## Timeouts track machine load
`~/.claude/autonomy/research/router-heldout/reading-v4-2026-10-07.trace.jsonl` records the 594 answered items
of the E1i read (label, path, load, wall time); the timed-out items are absent from it, so they are inferred from
gaps between consecutive answered items longer than the next item's wall time by 8.8 s or more (80 of the ~105
inferred), each assigned the mean load of its two neighbours.

| 1-min load | answered items | inferred timeouts | share |
|---|---|---|---|
| 0-40 | 88 | 0 | 0.0% |
| 40-60 | 274 | 8 | 2.8% |
| 60-100 | 156 | 54 | 25.7% |
| over 100 | 75 | 18 | 19.4% |

Corroboration: E1h's cold tuning run (median load 18) gave union(`sonnet-off`, `haiku-on`) 0 fallbacks in 1,078
calls (`result.txt`); E1i's warm latency check put all 8 of its fallbacks at load 83-145. Answered items at load
0-40 had a median wall time of 5.6 s and a maximum of 8.68 s across the whole read.

## Low-load windows exist
`~/.claude/autonomy/idl.jsonl`, 432 samples 2026-10-06 05:36 to 2026-10-07 22:17 CDT, about one every 5.5 min:
79% of samples at load 40 or under; the longest unbroken runs were 689 min (from 10-07 01:37, two minutes after
the E1i read ended), 450 min (10-06 05:36) and 192 min (10-06 15:43). A read takes about 75 min.

## What it implies
With the read held to load 40 or under, timeouts go to about 0, so the measured E1i misses that were timeouts
(all 25 recall misses; 19 of 30 `other` misses) would not recur: `other` near 0.96, recall bounded by labels,
which were right on every answered relay-gold item. Remaining risks are not load: a fresh `other` and
regex-matched sample, and regex-missed as a disclosed third read of v3's 25 counted items.

## CORRECTED (2026-10-08): the timeout table above undercounts, and the timeouts come in bursts
Found by the refuting critic of workflow `wf_7fd65e4a-17f` and re-run by the lead. The trace's `t` is each
classify call's START (`scripts/research-kit/router.py`, `t0` in the `classify` verb), so a gap holds the
PREVIOUS item's wall time, not the next one's; the table above subtracted the wrong item's. Re-inferred
(gap minus the previous item's wall time over 8.5 s, rounded to 9 s per timeout): 106 timeouts (the record
says about 105), in 31 gaps; the largest runs are 19, 15, 8, 8, 6, 5 and 5 items in a row.

| 1-min load | answered items | inferred timeouts |
|---|---|---|
| 0-40 | 88 | 1 |
| 40-60 | 274 | 12 |
| 60-100 | 156 | 72 |
| over 100 | 75 | 21 |

So timeouts still track load, but not cleanly: they arrive as stall bursts in which both classifier calls
miss together, and one run of 5 came at load 56. A load bound alone is not a sure cure; the next step is
to trace each fallback and fix the warm daemon's stalls on tuning data (decision research:
`docs/research/reask-haiku55-decision-2026-10-08/REPORT.md`). The low-load-window section stands.
