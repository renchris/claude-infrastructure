# Sonnet 5.5 synthesis probe: tally (2026-09-28)

Arms: SM = Sonnet 5.5 @medium, SH = Sonnet 5.5 @high, SX = Sonnet 5.5 @xhigh, OX = Opus 5.5 @xhigh. Judges per brief: J0 and J1 are Opus 5.5 (session), J2 is Opus 5. There are 18 judge rows (6 briefs x 3 judges). Every figure below was measured: `/tmp/s55tally/table.py` computed it from the de-blinded judge rows and `arms/index.jsonl`. Key sizes are the distinct item IDs in `opus55-synth-reprobe-2026-09-22/corpus/keys/<brief>.md`, counted with grep.

## 1. Per-brief pairwise verdicts (strict majority, at least 2 of 3 judges)

Cells show the majority result, then the calls of J0/J1/J2. `split` means no outcome got 2 votes.

| Brief | SM v SH | SM v SX | SM v OX | SH v SX | SH v OX | SX v OX |
|---|---|---|---|---|---|---|
| T1-custody | **SH** (SH/SH/SH) | **SX** (SX/SX/SX) | **OX** (OX/OX/OX) | **tie** (tie/tie/tie) | **tie** (OX/tie/tie) | **tie** (OX/tie/tie) |
| T2-recycle-goal | **SM** (SM/SM/SM) | **SX** (SX/SX/SX) | **OX** (OX/OX/OX) | **SX** (SX/SX/SX) | **OX** (OX/OX/OX) | **OX** (tie/OX/OX) |
| T3-frontier-budget | **tie** (tie/SH/tie) | **SX** (SX/SX/SX) | **OX** (OX/OX/OX) | **SX** (SX/SX/SX) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |
| T4-stop-arms | **SH** (SH/tie/SH) | **SX** (SX/SX/SX) | **OX** (OX/OX/OX) | **tie** (tie/tie/SX) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |
| T5-deploy-live-exec | **SH** (SH/SH/SH) | **SX** (SX/SX/SX) | **OX** (OX/OX/OX) | **SH** (SH/SH/SH) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |
| T6-choose | **tie** (tie/tie/SH) | **SM** (SM/SM/SM) | **OX** (OX/OX/OX) | **SH** (SH/SH/SH) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |

Majority tally across the 6 briefs (wins for the first arm - wins for the second arm - tie or split):

| Pair | first-arm wins | second-arm wins | tie/split |
|---|---|---|---|
| SM v SH | SM 1 | SH 3 | 2 |
| SM v SX | SM 1 | SX 5 | 0 |
| SM v OX | SM 0 | OX 6 | 0 |
| SH v SX | SH 2 | SX 2 | 2 |
| SH v OX | SH 0 | OX 5 | 1 |
| SX v OX | SX 0 | OX 5 | 1 |

## 2. Majority key recall (an item counts when at least 2 of 3 judges credited it in `hit_ids`)

| Brief | key n | SM | SH | SX | OX |
|---|---|---|---|---|---|
| T1-custody | 21 | 19/21 | 21/21 | 20/21 | 20/21 |
| T2-recycle-goal | 25 | 22/25 | 22/25 | 25/25 | 25/25 |
| T3-frontier-budget | 32 | 29/32 | 28/32 | 29/32 | 30/32 |
| T4-stop-arms | 20 | 19/20 | 20/20 | 20/20 | 20/20 |
| T5-deploy-live-exec | 17 | 13/17 | 16/17 | 15/17 | 17/17 |
| T6-choose | 15 | 15/15 | 15/15 | 14/15 | 15/15 |
| **Total** | 130 | **117/130 (90.0%)** | **122/130 (93.8%)** | **123/130 (94.6%)** | **127/130 (97.7%)** |

## 3. Mean score, wrong claims, bad-citation rate by judge model

Bad-citation rate is the summed `bad` over the summed `cites` checked. The Opus 5.5 columns pool 12 rows (J0 and J1); the Opus 5 columns cover 6 rows (J2).

| Arm | mean score (Opus 5.5 judges) | mean score (Opus 5 judge) | wrong claims (Opus 5.5 / Opus 5) | bad cites (Opus 5.5) | bad cites (Opus 5) | mean score (all 18) |
|---|---|---|---|---|---|---|
| SM | 6.58 | 6.33 | 49 / 34 | 42/390 (10.8%) | 23/157 (14.6%) | 6.50 |
| SH | 7.42 | 7.17 | 36 / 23 | 32/434 (7.4%) | 12/156 (7.7%) | 7.33 |
| SX | 7.50 | 7.33 | 28 / 24 | 20/449 (4.5%) | 11/178 (6.2%) | 7.44 |
| OX | 9.00 | 8.83 | 17 / 7 | 6/517 (1.2%) | 4/195 (2.1%) | 8.94 |

Own-family check: the score gap OX minus each Sonnet arm, as seen by each judge family:

| Gap | Opus 5.5 judges | Opus 5 judge |
|---|---|---|
| OX - SM | +2.42 | +2.50 |
| OX - SH | +1.58 | +1.67 |
| OX - SX | +1.50 | +1.50 |

## 4. Output tokens and turns per arm (from arms/index.jsonl, summed over 6 cells)

| Arm | cells | output tokens (total) | mean per brief | turns (total) | mean turns | cache_create (total) | denials | cost USD (total) | wall s (total) |
|---|---|---|---|---|---|---|---|---|---|
| SM | 6 | 61,078 | 10,180 | 95 | 15.8 | 237,859 | 7 | 1.86 | 441 |
| SH | 6 | 89,683 | 14,947 | 134 | 22.3 | 325,690 | 6 | 2.69 | 645 |
| SX | 6 | 192,787 | 32,131 | 157 | 26.2 | 410,652 | 12 | 4.25 | 1384 |
| OX | 6 | 206,423 | 34,404 | 151 | 25.2 | 423,161 | 14 | 8.60 | 1930 |

Per-cell detail:

| Brief | SM out/turns | SH out/turns | SX out/turns | OX out/turns |
|---|---|---|---|---|
| T1-custody | 11,152/18 | 21,127/24 | 44,158/27 | 41,986/27 |
| T2-recycle-goal | 10,986/21 | 12,026/24 | 28,517/28 | 40,753/27 |
| T3-frontier-budget | 10,117/14 | 14,059/18 | 35,327/26 | 37,850/24 |
| T4-stop-arms | 13,048/11 | 19,414/21 | 39,643/21 | 37,030/24 |
| T5-deploy-live-exec | 8,314/12 | 14,700/25 | 26,772/28 | 29,442/26 |
| T6-choose | 7,461/19 | 8,357/22 | 18,370/27 | 19,362/23 |

## 5. Exact two-sided sign tests on per-brief majority wins (ties and splits dropped)

| Comparison | wins-losses (ties) | n | p (two-sided) |
|---|---|---|---|
| SX vs OX | SX 0 - OX 5 (1) | 5 | 0.0625 |
| SH vs OX | SH 0 - OX 5 (1) | 5 | 0.0625 |
| SM vs OX | SM 0 - OX 6 (0) | 6 | 0.0312 |
| SH vs SX | SH 2 - SX 2 (2) | 4 | 1.0000 |

There are only 6 briefs, so the smallest p a 6-0 sweep can reach is 0.0312. A 5-0 result with one tie gives p = 0.0625.


## 6. Verdict

1. No. Sonnet 5.5 cannot take the Workflow bulk-synthesis-worker slot from Opus 5.5 @xhigh at any effort level. OX won or tied every per-brief majority against all three Sonnet arms (SX 0-5-1, SH 0-5-1, SM 0-6-0). Across 54 individual judge calls it lost none (49 OX wins, 5 ties; measured).
2. The gap is accuracy, not coverage. Majority key recall is close (OX 97.7%, SX 94.6%, SH 93.8%, SM 90.0%). Bad-citation rates are much further apart: OX 1.2-2.1%, SX 4.5-6.2%, SH 7.4-7.7%, SM 10.8-14.6%. So are mean scores: OX 8.94 against at most 7.44 for Sonnet. The Sonnet arms dropped exactly the items that need depth (T5 N4/M1, T3 K19, T2 K17/M6/M7 at medium and high).
3. Own-family bias does not explain the result. The Opus 5 judge gives the same OX-over-Sonnet score gaps as the Opus 5.5 judges (+1.50 vs +1.50 for SX, +1.67 vs +1.58 for SH, +2.50 vs +2.42 for SM).
4. The case for Sonnet would be cost, and it is weak. SX costs about half as much ($4.25 vs $8.60) but uses almost the same output tokens (192,787 vs 206,423) and turns (157 vs 151). High effort does not clearly beat xhigh (SH v SX 2-2-2, p = 1.0). Medium is cheapest ($1.86) but has the most errors.
5. Conviction that OX should keep the slot: 85%. Every call points one way, but the sign tests stop at p = 0.0625 / 0.0625 / 0.0312 because there are only 6 briefs. A cheaper Sonnet pass whose output an Opus reviewer then checks remains untested.
