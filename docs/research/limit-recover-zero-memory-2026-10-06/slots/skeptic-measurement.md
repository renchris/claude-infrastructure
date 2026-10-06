# Skeptic verdict, measurement lens (2026-10-06, about 07:20Z)

**Verdict.** "Memory is not the binding constraint" survives, on receipts stronger than the draft's. Five supporting numbers do not survive as written. "A static width is what binds" is confounded on the move lane and mis-counted on the recover lane.

Source lines are `git show HEAD:<path>`; the working tree was mid-edit (see Missing).

## Binding constraint

- MEASURED, `jq` over `~/.claude/logs/capacity-alarm.jsonl`, 14,375 sampler rows, 2026-09-19 to 10-06: segments at or above 90%: 0 rows (max 72.1%); headroom under 4 GB: 0 rows (min 8.56 GB). At the old 50% ceiling: 211 rows (1.47%) on 3 days. `seg_source` is `est` on every row.
- MEASURED, same file, 06:00:11-06:18:11Z: `compressions` constant at 457,571,867, swap constant at 2,205.75 MB. Nothing was compressed during the batch.
- The draft's proof is thinner. The 8 admits are 2 box readings (5 rows at 06:07:04-08Z, 3 at 06:09:55Z). The 55 `lr-fleet` probes read segments p50 6.72%, max 50.63%, mid-turn 0 on 55 of 55. The "22 probes since 2026-10-05" all fall in 06:03:57-06:21:46Z on 10-06 (17.8 min, about 4% segments); 10-05 has 0 probes, though the sampler read 50% or more on 21 rows.

## Refuted or mis-stated

| Draft claim | What the records give | Receipt |
|---|---|---|
| 38 of 480 `one-*` runs waited on the cap | 17 of 38 RECOVERED rows since 10-01 (45%). The 480 holds 120 dirs from before the cap existed, 103 CWD-GONE parks and 141 FAILED rows (117 one sid, 15 another) | per-dir `grep -q 'at its cap'` joined to `results.tsv` col 6 |
| 13 segments refusals at 48-66% on 2026-10-04 | 12 on 10-04 and 1 on 10-02; the gate's own lines read 54.27-66.09%. A 50% ceiling cannot refuse at 48% (48.19 is the sentinel's figure, q4:103) | `jq` over `idl.jsonl` and 8 archives, 1,005 `lr-*` rows |
| 4 GB headroom floor refused 0 of 2,604 rows | headroom term refused 3 of 2,622 rows, 2026-09-29T07:12-07:16Z, 9.14-9.76 GB against 4 + 6 GB reserve; one caller is `lr-upgrade`. Bare floor: 0 | same pass, all callers |
| memory terms refused 0 of 55 `lr-fleet` probes | current epoch only. Whole ledger: 267 admit, 235 refuse (load 164, active 70, segments 1), 226 of them on 2026-09-19; since 09-21: 9 of 255 | same pass |
| recover lane: cap wait against capacity wait | omits target supply: 47 `parked: no routable target` rows over 12 sessions since 10-01, more than the 38 cap waits. Draft has 0 mentions; q1a:82 and q1d:143 had it | `awk` over `fleet/one-2026100*/results.tsv` |
| slot wait 29% shows the width binding | actuate to actuated ran 105.2-110.0 s in wave 1 (4 wide) and 16.0-16.5 s in wave 2 (3 wide); four bundles stamped 06:08:16Z and four proofs inside 116 ms. A shared 68 s stall is 41% of each 167 s wait | 7 `events.jsonl`, last line of 7 `handoff.log` |

## Re-derived and confirmed

Slot waits 166.8 / 167.3 / 167.2 s; 503.6 of 1,751.3 s (28.8%); mean slot to first proof 169.7 s; 0.455 s; 8 admit, 0 refuse; headroom 30.96-34.94 GB over 17 rows; load1 22.84 to 150.53; hop 89 s (`poller.log:72885`); 6 runs and 9 capacity lines (8 active, 1 segments), equal to the ledger's 9 `lr-fleet` refusals since 09-21. Rank 1: the roll-up loop replayed over the real batch directory under `/bin/bash` 3.2.57 prints `MOVED=7` with leading parens, a syntax error without.

## Convictions to move

- Rank 15, 60 to 45: 2 of 7 boot alarms and load1 119-150 at width 4; stage times differ 6.6x between waves; the 312 s and 270-345 s figures assume independence.
- Rank 16, 55 to 45: the N=20 estimate uses 18 survivor holds; 38 of 359 `--one` rows since 10-01 ended RECOVERED, 160 parked.
- Rank 4, 90 to 85: "0 tests red" has no mutation run behind it.
- Rank 1, 95 to 97: replay above.
- Ranks 2 and 3 hold at 92; rank 2 should cite the sampler.

## Missing

- `kalloc1024_gb` 5.45-5.47 against warn 4 and alarm 6 on every sampler row of the window. No rotation gate reads it; no slot names it.
- Sampler verdict ALARM from 06:09:43Z past 06:22Z while the lane admitted with "load term off". Load1 stayed 111-140 for 5 minutes after the batch closed at 06:14:17Z, so the batch is not shown to be the cause.
- Refused `cc-lr move` calls write nothing (`bin/cc-lr:1279-1286`), so "1 of 1 batch" hides refused attempts. A memory refusal comes after the batch directory exists, so the memory claim is not exposed.
- `git status` showed uncommitted edits to 6 files, then 8 (cc-lr, three move/poller scripts, four bats), covering ranks 1, 7, 8, 10 during this pass.
