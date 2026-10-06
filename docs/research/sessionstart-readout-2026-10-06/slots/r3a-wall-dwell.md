# R3a: how long an account stays at wire 7d `0.99 allowed_warning` before it refuses work

Data window: wire fields first appear 2026-09-19T19:50:07Z. The last row read is 2026-10-06T06:13:51Z. There are no rotated copies: `~/.claude/logs/account-utilization.jsonl` is the only file, 44,586 rows from 2026-08-10, and 2,068 of them carry a wire read. Episodes are therefore measurable only from 09-19.

Sources:
- the utilization jsonl;
- the session-side refusal stores `~/.claude/autonomy/stop-failure/rate_limit__<acct>.jsonl` (224 StopFailure rows, mapped to accounts by `config_dir` through `~/.claude/accounts.json`; 0 rows disagree with their file name);
- `claude-accounts --reset-report`.

Scripts and intermediate data: `/tmp/ssr-research/r3a_episodes2.py <thr>` produces `ep2_0.98.json` and `ep2_0.99.json`. `ep_clean_099.json` holds the 10 clean episodes and `readings_099.json` the per-reading hazard data. Everything below is **measured** by these scripts unless it is labelled *reasoned*.

**How an episode is defined**
- **Start:** the account's first row with `wire_7d_status=allowed_warning` and `wire_7d_util >= thr`.
- **End:** one of three things.
  - The first later row with `wire_7d_status=rejected`. Outcome "rejected".
  - `weekly_pct < 90`, or a new `weekly_reset_at` (rounded to the hour, because the stamp jitters by under a second). Outcome "reset".
  - The end of the data. Outcome "censored".
- **Re-arm:** a new episode can start only after a reset.
- **Session refusal time:** the first StopFailure row on that account whose message contains "weekly limit".

## Answer in one paragraph

Every recorded episode ended in refusal. None reached the weekly reset first: 11/11 at a threshold of >=0.98 and 11/11 at 0.99, including one early episode (#0) with poor instrumentation.

Over the 10 clean episodes, the time from the first 0.99 read to the first session that hit the weekly limit was:
- median **47 min**
- p10 **17.5**, p90 **145** (nearest-rank; n=10, so these are the 1st and 9th order statistics)
- range **17.5 to 174 min**

The live-session count k does **not** predict that time. Spearman(k at entry, dwell) = −0.20 (n=10). The four episodes with k>=11 took 17.5, 22.3, 145 and 174 min. The recent burn rate does predict it: Spearman(trailing-60-min session_pct rate at entry, dwell) = **−0.93** (n=10).

The quantity that stays nearly constant is **how much of the 5-hour meter gets spent after the first 0.99 read before refusal: 3 to 6 points, median 4 (n=10)**. In the incident, 5 points had already been spent at 0.99 when the board said "roughly 5% of one 5-hour window" was left.

The sweep never observes the transition. In 10/10 episodes it falls inside the last ~6-minute sweep gap. A session got refused 0.4 to 16.8 min after the last `allowed_warning` read (median 4.8). The board then kept saying "accepting" for another 0.1 to 7.9 min (median 2.2) until the next sweep read `rejected`.

## Episode table (entry at the first 0.99 read; all times UTC, 2026)

`first weekly refusal` is the first StopFailure "You've hit your weekly limit" row for that account. In every episode its reset time matches the row's `weekly_reset_at`; for example, "resets 7am (America/Chicago)" is 12:00Z for next3. `burn` is the sum of positive steps in `session_pct`, with a fall counted as a 5-hour window roll. It is measured from the first 0.99 read to the first `rejected` row.

| # | acct | first 0.98 | first 0.99 | first wk=100 | last allowed_warning | first weekly refusal (session) | first `rejected` sweep | outcome | dwell 0.99→refusal / →rejected sweep (min) | k entry / max | k_work med / max | sweep spacing med / max (s) | burn evidence: session_pct entry→last warn→rejected; pts spent since 0.99; trailing-60 pts/h at entry |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0* | next | - | 09-19 19:50 | 09-19 19:50 | 09-19 19:50 | 09-19 21:40 | 09-19 22:35 | rejected | ≤110 / 165.2 | 4 / 4 | 0 / 3 | 409 / 616 | 13→13→0; no wire read on 23 of 24 rows; n/a |
| 1 | next3 | 09-22 07:38 | 09-22 07:46 | 09-22 07:52 | 09-22 08:00 | 09-22 08:03:43 | 09-22 08:05 | rejected | 17.5 / 19.3 | 18 / 18 | – / – | 402 / 451 | 83→0→2 (5h roll); 3; 35.2 |
| 2 | next2 | 09-24 20:28 | 09-24 20:52 | 09-24 21:16 | 09-24 22:02 | 09-24 22:18:50 | 09-24 22:26 | rejected | 86.8 / 94.7 | 2 / 3 | 2 / 8 | 403 / **1483** | 6→11→12; 6; 4.13 |
| 3 | next | 09-26 18:39 | 09-26 19:00 | 09-26 19:12 | 09-26 20:21 | 09-26 20:23:54 | 09-26 20:26 | rejected | 83.8 / 86.1 | 7 / 7 | 4 / 6 | 368 / 461 | 4→8→8; 4; 7.25 |
| 4 | next4 | 09-26 20:52 | 09-26 21:29 | 09-26 21:35 | 09-26 22:14 | 09-26 22:19:34 | 09-26 22:19:53 | rejected | 49.9 / 50.2 | 5 / 5 | 5.5 / 8 | 377 / 406 | 15→19→19; 4; 4.21 |
| 5 | next3 | 09-29 02:11 | 09-29 02:17 | 09-29 02:24 | 09-29 03:01 | 09-29 03:02:06 | 09-29 03:07 | rejected | 44.8 / 50.1 | 3 / 3 | 5.5 / 10 | 369 / 413 | 19→24→24; 5; 12.96 |
| 6 | next2 | – (first wire read already 0.99) | 09-30 06:52 | 09-30 06:52 | 09-30 07:05 | 09-30 07:09:49 | 09-30 07:11 | rejected | 17.6 / 19.6 | 6 / 6 | 7 / 7 | 397 / 403 | 78→80→81; 3; 25.51 |
| 7 | next4 | 10-01 17:06 | 10-01 17:33 | 10-01 17:40 | 10-01 19:53 | 10-01 19:59:04 | 10-01 19:59:10 | rejected | 145.1 / 145.3 | 14 / 14 | 1 / 6 | 387 / 481 | 7→2→2 (5h roll); 5; 4.27 |
| 8 | next | 10-01 20:12 | 10-01 20:18 | 10-01 20:18 | 10-01 20:47 | 10-01 20:52:19 | 10-01 20:59 | rejected | 34.2 / 41.0 | 6 / 6 | 6 / 11 | 400 / 528 | 22→25→26; 4; 8.44 |
| 9 | next3 | 10-02 01:22 | 10-02 01:28 | 10-02 01:35 | 10-02 01:43 | 10-02 01:50:24 | 10-02 01:51 | rejected | 22.3 / 23.2 | 18 / 18 | 11 / 15 | 463 / 464 | 31→33→35; 4; 23.11 |
| **10** | **next3 (incident)** | 10-06 01:56:31 | 10-06 03:08:26 | 10-06 03:55:54 | 10-06 06:01:45 | **10-06 06:02:42** (sid e131c8d2) | 10-06 06:08:11 | rejected | **174.3 / 179.7** | 15 / 15 (11 at the last warn) | 1 / 6 | 371 / 547 | 2→7→7; **5**; 3.05 |

\* Episode 0 is excluded from the statistics. It is the very first wire read, and the next 23 sweeps made no wire read, so the dwell can only be bracketed as 0 to 110 min.

Notes on the incident row:
- The first refusal on next3 was at **06:02:42Z** (session `e131c8d2`, 57 s after the 06:01:45 sweep). The plan cites 06:03:04Z, but that is the second refused session, `4ad354fc`. Receipt: `rate_limit__next3.jsonl`, rows 06:02:42 to 06:07:03Z, 4 distinct sessions refused within 30 min.
- At the 06:01:45 row, `session_pct` was 7, against 2 at the first 0.99 read (03:08:26) and 3 when the endpoint first read 100 (03:55:54). That is 5 points spent in the band, and 4 since the endpoint read 100.
- The board's "roughly 5% of one 5-hour window" is `(1 − 0.99)·100 / K_FROZEN`, from `bin/claude-accounts:6745-6750` with K_FROZEN = 0.192 at `:3645`. It is the band's ceiling at **entry**. The same amount had already been spent.

## Summary statistics (n = 10 clean episodes, 4 accounts, 2026-09-22 to 10-06)

| measure | n | median | p10 | p90 | min | max |
|---|---|---|---|---|---|---|
| first 0.99 read → first weekly refusal (session) | 10 | **47.3 min** | 17.5 | 145.1 | 17.5 | 174.3 |
| first 0.99 read → first `rejected` sweep row | 10 | 50.2 | 19.3 | 145.3 | 19.3 | 179.7 |
| first 0.99 read → last `allowed_warning` (lower bound) | 10 | 44.5 | 13.0 | 140.0 | 13.0 | 173.3 |
| first (0.99 and endpoint 100) → refusal | 10 | 40.8 | 10.8 | 126.8 | 10.8 | 138.2 |
| first 0.98 read → refusal | 10 | 69.0 | 17.6 | 172.5 | 17.6 | 246.2 |
| 5-hour-meter points spent, first 0.99 → `rejected` | 10 | **4** | 3 | 5 | 3 | 6 |
| 5-hour-meter points spent, first 0.98 → `rejected` | 10 | 7 | 3 | 8 | 3 | 8 |

- **Outcome counts:** 10/10 rejected, 0 reset first, 0 censored. Including episode 0 and the >=0.98 run, it is 11/11 in both runs. The refusal came long before the scheduled reset; for example, #7 refused about 2.5 days before its 10-04 09:00Z reset.
- **Entry-time uncertainty.** The first 0.99 read lags the true crossing by at most one wire-read gap, about 6 min, in 9/10 episodes (each was preceded by a 0.98 read). In #6 the first wire read was already 0.99, so its crossing is unbounded earlier. *Reasoned:* the true dwell is the measured value plus 0 to ~6 min.
- **Session-refusal time is an upper bound on the server transition.** A StopFailure row fires only when a working session's turn fails. The `allowed_warning` read before it is the lower bound. Both bounds are in the table.

## (b) Dwell against k, k_work and burn rate (Spearman ρ against dwell to the first session refusal)

| predictor | n | ρ | reading |
|---|---|---|---|
| k at entry (pane census) | 10 | **−0.20** | not predictive. With n=10, \|ρ\| needs to exceed ~0.65 for p<0.05. |
| k median over the episode | 10 | −0.31 | not predictive |
| k_work at entry (transcripts written in the last 10 min, `bin/claude-accounts:2800`, `KWORK_WINDOW_MIN=10` at `:2824`) | 8 | −0.83 | predictive; 2 rows are None |
| k_work median over the episode | 9 | −0.97 | predictive, but only known in hindsight |
| trailing-60-min `session_pct` rate at entry (pts/h) | 10 | **−0.93** | predictive and known at entry |
| `session_pct` rate during the episode | 10 | −0.71 | predictive |
| `session_pct` at entry | 10 | −0.95 | stands in for recent burn |

- **Split by k (n=10).** k>=11: 17.5, 22.3, 145.1, 174.3 min (n=4, two clusters). k<11: 17.6, 34.2, 44.8, 49.9, 83.8, 86.8 min (n=6, median 47.3). The long k>=11 episodes are #7 and #10, with 14-15 resident panes but a median k_work of 1. Idle panes do not burn quota.
- **ETA from the trailing burn rate.** Dividing 4 points (the median spent in the band) by the trailing-60 rate gives a time that **under-predicts** the real dwell. The ratio actual/predicted ranged 0.88 to 2.6, median about 2.2 (n=10). The rate during the episode was lower than the trailing rate in 8/10 episodes. *Reasoned, not measured:* routing and operators move load off an account once it is near the wall. Only the minimum of that ratio (0.88) gives a safe floor: "as soon as about 0.9 × 4 / rate".

## Per-reading risk: is a refusal coming before the next sweep? (105 wire readings at 0.99 inside the 10 clean episodes; readings within an episode are not independent)

| condition at the reading | session refusal before the next sweep row |
|---|---|
| all 0.99 `allowed_warning` readings | 10 / 105 (9.5%) |
| endpoint `weekly_pct` = 99 | **0 / 18** |
| endpoint `weekly_pct` = 100 | 10 / 87 (11.5%) |
| >=4 points of the 5-hour meter spent since the first 0.99 read | 6 / 22 (27%) |
| <4 points spent | 4 / 83 (4.8%) |
| k_work >= 5 | 6 / 21 (29%) |
| k_work 0-4 | 2 / 55 (3.6%); 29 readings had k_work None |
| k >= 11 | 4 / 51 (7.8%) |
| k <= 4 | 4 / 35 (11.4%) |

- Every refusal came while the endpoint integer read 100. Wire 0.99 coexisted with endpoint 99 on 18 rows and endpoint 100 on 88. Across all rows, the wire figure was never above the endpoint figure: (0.98, 99)×30, (0.99, 100)×88, (0.99, 99)×18, (0.93, 94)×2, (0.57, 58)×24. *Reasoned:* this fits a server that floors the figure and an endpoint that rounds it (R2's question). If so, 0.99 together with 100 means at most 0.5 pp of the week left, about 2.6 points of one 5-hour window at K_FROZEN, which is half of the "roughly 5%" the board printed.
- A higher k does not raise the per-reading risk (7.8% at k>=11 against 11.4% at k<=4). A higher k_work does.

## (c) Is the sweep spacing too coarse to see the transition?

Yes. The sweep can place the transition only within one gap.

- **Sweep spacing during episodes.** The median per episode is 368-463 s (6.1-7.7 min); the maximum is 1483 s (#2). That is against `StartInterval 180` (cadence is R4's question).
- **Where the transition falls.** In **10/10** episodes it lies inside the last gap, between the final `allowed_warning` read and the first `rejected` read.
  - In 9/10, the first `rejected` row is the next sweep after the last warning (gap 5.1-7.7 min, plus #2's 24.7 min outlier).
  - In #8 there was one sweep with no wire read in between (gap 11.7 min).
- **Refusal after the last `allowed_warning` read:** 0.4, 0.9, 2.8, 3.3, 4.6, 4.9, 5.2, 5.4, 6.8 and 16.8 min. The median is 4.8 (n=10); 9/10 fall within one sweep interval.
- **"Accepting" printed after the first refusal.** The time from the first session refusal to the sweep that read `rejected` was 0.1, 0.3, 0.9, 1.8, 2.0, 2.3, 5.3, 5.5, 6.8 and 7.9 min. The median is 2.2 (n=10).
- **The server reading was never contradicted.** No weekly StopFailure row on an account fell between its first 0.99 read and its last `allowed_warning` read (0/10 episodes). "Accepting work" was true when it was read. What failed was the tense of the sentence and the headroom figure, not the read itself.
- **A finer signal already exists.** The StopFailure rows resolve the transition to the second and cost zero tokens. They led the sweep by a median of 2.2 min (n=10).

## (d) What the board can honestly print for "0.99, accepting work, k live sessions"

**Not supported:** "typically refuses within X min at k>=N". k had no predictive value (ρ = −0.20, n=10). At k>=11 the dwell split into two groups, 17-22 min and 145-174 min (n=4).

**Supported (n=10, 2026-09-22 to 10-06):**

> `next3` ≥99% used — Anthropic's server was still accepting work at 06:01 (N min ago). Every recorded ≥99% episode ended in refusal (10 of 10): 17–174 min after the first ≥99% read, median 47. Since this one began (03:08), 5 points of the 5-hour meter have gone; past refusals came after 3–6.

- The first sentence fixes the tense and age. The second is the base rate, with its sample size. The third is the burn-budget signal (3-6 points, median 4, n=10), which does not depend on k and can be computed from `session_pct` rows that are already logged, at zero tokens.
- *Reasoned:* the producer would have to compute "first ≥99% read" and "points spent since" from the utilization log. The SessionStart hook would still only read a file.
- If one shorter line is required: "≥99%, accepting as of HH:MM; every recorded case refused afterwards (n=10), median 47 min, as soon as 17 min."

## `--reset-report` (read first, then run)

- **Code.** `reset_report()` is at `bin/claude-accounts:2145-2191`; its docstring says "A file read only". It is dispatched at `:7858-7871`, before the get_data anchor ("a file read, no network"). It reads `RESET_LOG_PATH = ~/.claude/logs/quota-reset-detect.jsonl` (`:2012-2027`). The worktree copy is byte-identical to `~/.claude/bin/claude-accounts`, checked with `diff -q`.
- **Run.** `~/.claude/bin/claude-accounts --reset-report --days 90` returned 3 events:
  - next2 7d, 2026-10-03 11:01, lag 1m54s;
  - next 7d, 2026-10-04 04:01, lag 1m22s;
  - next4 5h, 2026-10-04 09:42, lag 2m24s.
  - Summary: `scheduled/usage n=3 median 1m54s max 2m24s`.
- **What it can and cannot answer.** It measures how quickly a reset is detected (from >=99% to <90%; `RESET_HIGH_PCT`/`RESET_LOW_PCT` at `:2006-2007`). It does not measure the 0.99 → `rejected` dwell, and its log starts at 2026-10-03T11:01:53Z, after 9 of the 10 episodes. It corroborates only that no reset ended an episode.
- **One reset it does not hold.** After episode #9, next3 went `weekly_pct` 100 → 0 at 2026-10-02T01:58:01Z, with `weekly_reset_at` still 10-06 12:00Z. That is an unscheduled reset, 7 min after refusal, and it predates the detect log.

## Alternatives considered

- **A k-conditioned time ("within X min at k>=N").** Rejected; see (d).
- **A fixed time ("typically within 47 min").** Weak. It spans a factor of 10 (17-174 min) and on its own would have read as reassurance in the incident, which ran 173 min.
- **An ETA from the trailing burn (4 points / rate).** Well ranked (ρ = −0.93), but it under-predicts by about 2.2× (median). Usable only as a floor: "as soon as …".
- **A burn budget (points spent since first 0.99, against 3-6).** The steadiest quantity in the data and independent of k. It is limited by `session_pct` being an integer (±1 point) and by having only n=10.
- **Using the endpoint reading 100 as an "imminent" sub-state.** Necessary in 10/10 episodes, but it raises the per-reading risk only from 0/18 to 10/87. The existing note already fires on it (`:6745`).

## Blockers and caveats

- **Small sample.** n=10 clean episodes over 4 accounts and 15 days (09-22 to 10-06). The p10/p90 values are single order statistics. No episode predates 09-19, because the wire fields and StopFailure rows begin then.
- **Integer resolution.** Both `session_pct` and the endpoint `weekly_pct` are integers, so each burn figure carries ±1 point.
- **k_work gaps.** k_work is None on 29 of 105 readings, and ρ for k_work rests on n=8-9.
- **Routing (R6, cross-reference only).** `weekly_headroom()` (`:1358-1369`) treats wire 0.99 as 0.01 of headroom, above WEEKLY_FLOOR 0.005, so an account in this state stays routable. Whether new sessions were sent there during these episodes was not measured here.
