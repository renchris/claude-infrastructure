# H: typed relaunch success vs 1-min load per core

Question: is the 8 load/core recycle hold (`hf_recycle_load_gate`, fix 8b, `2bb9817d0`, landed
2026-10-11T19:22:27Z) backed by evidence about the typed relaunch?

Boundaries used:

- `f4b297310` landed 2026-10-09T18:34:17Z (committer date). REPORT.md puts the deploy live at 20:11Z.
- That commit **introduced** the per-attempt telemetry. So no `type-attempt` record can exist from before it.

Buckets are [lo, hi) in load_1m / hw.ncpu (10 cores).

## 1. Attempt level: bucket × verdict (measured; deduped `type-attempt` records)

| load/core | pre-`f4b297310` n | post: submitted | post: echo-unverified | post: other fail | post n | verified-submit rate |
|---|---|---|---|---|---|---|
| 0-4   | 0 | 27 | 0 | 0 | 27 | 27/27 |
| 4-8   | 0 | 6  | 1 | 0 | 7  | 6/7   |
| 8-16  | 0 | 3  | 0 | 0 | 3  | 3/3   |
| 16-32 | 0 | 3  | 0 | 0 | 3  | 3/3   |
| 32-64 | 0 | 0  | 0 | 0 | 0  | —     |
| 64+   | 0 | 0  | 0 | 0 | 0  | —     |
| **all** | **0** | **39** | **1** | **0** | **40** | 39/40 |

Field operator panes only. The rows above 8 are:

| load/core | pane | time |
|---|---|---|
| 9.91 | 169 | 10-10 02:34Z |
| 11.15 | 173 | 03:27Z |
| 12.58 | 172 | 04:23Z |
| 23.63 | 32 | 04:20Z |
| 24.57 and 24.01 | 7 | 02:56Z |

All six are `attempt=1`, `send_rc=0`, with `send_ms` between 0 and 358.

The one failed attempt:

- Pane 7, 2026-10-17T07:57:00Z, at 5.74/core.
- It was the disarm line: `send_ms=12000 read_rc=1 read_bytes=0`.
- Attempt 2 submitted 34 s later, and the relaunch landed.

Records kept out of the table:

| Kind | n | Why |
|---|---|---|
| E2E-live | 2 | Pane 155, scratch window, scenario B. Both submitted, at 2.4/core. |
| E2E-forced | 16 | Pane 157. All echo-unverified at 2.5-3.0/core, from the `HF_WATCHER_IT2` stub (`send_rc=1`, `send_ms` 7-11). |
| bats | 21 | Panes W-PANE, TYPED-PANE and RECY-PANE, on a stub it2. The load was the real machine load, including 4 submitted at 32-52/core, but the transport was fake, so they say nothing about kitty. |

Before `f4b297310`, F1 (pane 44, 2026-10-09 04:56-05:03Z) failed 16 attempts. No telemetry was recorded for them. capacity-alarm reads 42.2-44.5/core across that window (3 samples).

## 2. Per recycle: outcome × max load seen

**A. Recycles backed by telemetry** (measured: max `load_per_core` over the recycle's attempts; post-fix only):

| load/core | recycles | engaged | stranded | with ≥1 failed attempt |
|---|---|---|---|---|
| 0-4   | 15 (+1 E2E) | 15 (+1) | 0 | 0 |
| 4-8   | 4  | 4 | 0 | 1 (pane 7, 10-17) |
| 8-16  | 3  | 3 | 0 | 0 |
| 16-32 | 2  | 2 | 0 | 0 |
| 32+   | 0  | — | — | — |

- Pane 7 on 10-17 typed its relaunch, and claude 79475 came up. The move was then STRANDED by the unrelated commit-tail `/exit`, fixed in `475d66ced`. That counts as a typing success.
- Pane 157 (forced) stranded by design and is excluded.

**B. Typed recycles with no surviving per-attempt detail** (load estimated from `capacity-alarm.jsonl`):

| Era (n) | 0-4 | 4-8 | 8-16 | 16-32 | 32-64 | 64+ |
|---|---|---|---|---|---|---|
| Pre-fix, every relaunch typed (35) | 22/22 | 8/8 | 2/2 | 2/2 | **0/1 (F1)** | — |
| Landed, not yet live: 19:30Z and 19:31Z (2) | 1/1 | 1/1 | — | — | — | — |
| Post-fix, by max load in window (25) | — | 16/16 | 7/7 | 2/2 | — | — |
| Same 25, by min load in window | 1/1 | 22/22 | 2/2 | — | — | — |
| **Held, never typed: `recycle-held-load` (14)** | — | — | 7 | 6 | 1 | — |

Notes on B:

- Pre-fix rows above 8:
  - pane 44 at 9.6/core (10-07);
  - pane 108 at 9.1/core (10-08 18:17Z);
  - pane 113 at 21.5/core (10-08 19:55Z);
  - pane 7 at 25.8/core (10-08 04:47Z).
- The post-fix rows are 11 cc-lr moves on 10-11 and 14 recycles on 10-13. Only two had their whole actuate→result window above 8: pane 212 at 12.6-22.6/core and pane 8 at 8.2-24.5/core.

**Combined typed recycles** (A + B), successes over total:

| load/core | success/total |
|---|---|
| 0-4 | 39/39 |
| 4-8 | 29/29 |
| 8-32 | 18/18 by max load, 11/11 by min load |
| 32-64 | 0/1 |
| 64+ | 0/0 |

## 3. `recycle-held-load` rows by day (UTC)

| Day | rows | load quoted (/core, bound 8) | source |
|---|---|---|---|
| 2026-10-11 | 7 | 9.74, 11.38 ×3, 16.49, 16.61, 16.65 | Count from the trim row at 2026-10-15T14:26:21Z, which dropped `recycle-held-load: 7`. Values from the 7 matching move-lane `handoff.log` lines, 20:29-20:54Z. |
| 2026-10-12 to 10-17 | 0 | — | Every later trim row drops 0, and the live file holds none. |
| 2026-10-18 (10-17 evening CDT) | 7 | 37.49, 28.61, 27.41, 25.67, 13.91, 13.43, 13.14 | `handoffs.jsonl`, 00:59-02:25Z |

- All 14 are resume recycles, held before `/exit`.
- On 10-11 the held sessions (panes 32, 204, 3 and 2) were MOVED by a typed relaunch 19-66 min later, at 4.4-8.3/core.
- On 10-18 two holds (panes 20 and 24) carry `unconfirm rc 2` (stub-present), and both moves ended STRANDED (`move/20261018T*/{e739e5b5,8db0e6f1}.handoff.log`).

## 4. Conclusion

1. Above 8/core every typed relaunch on record succeeded: 6/6 telemetered attempts (5 recycles at 9.9-24.6/core, all first-attempt), and 0 failures in 11-18 typed recycles between 8 and 32/core.
2. The only failure that tracks load is F1: 1 recycle at 42-45/core, before hardening, with no per-attempt record. The 32-64 bucket has n=1, 64+ has n=0, and the one field failed attempt was at 5.74/core.
3. The data does not support 8/core as a measured failure threshold, but it is too thin to set a higher bound. 0 failures in 11 only puts the 8-32 failure rate below about 27% (rule of three, 95%), and nothing hardened exists above 24.6/core.
4. The 8 is ship-land's `CC_GATE_MAX_LOAD_PER_CORE` default (`hf_recycle_load_bound`), not derived from typing data. Since `2bb9817d0` the hold itself prevents new samples above 8, so this record cannot grow without a deliberate probe above 8.

## Sources, method, limits

- **Telemetry records** (n=40 field after dedupe):
  - 23 `handoffs.jsonl` rows. All 23 are also in TMPDIR watcher logs (12 logs, 25 lines).
  - 2 only in the TMPDIR log of pane 14 (10-15). The 10-17 trim dropped them.
  - 15 only in agent transcripts and tool-results that quoted `handoffs.jsonl` before trims. These are 10-09 to 10-13, extracted with `/tmp/lri-h/extract{3,4}.py`.
  - Dedupe key: pane + detail without `line=` + ts within 3 s.
  - Pre-10-15 watcher logs are gone from TMPDIR.
  - `~/.reso/limit-recover/**/watcher.json` holds only pid, pane and armed_at.
  - No rotated `handoffs*.jsonl*` exists.
- **Unrecovered `type-attempt` rows:**
  - 26 rows have no detail: 13 recycles on 10-13, 2 rows each. A count of 2 implies no failed attempt, because each retry adds a row.
  - At least 10 rows of the first 42 are unseen. The only surviving listing printed every third row (`NR%3==1`).
  - The rows for the 10-11 moves are gone. Only their MOVED verdicts survive.
- **No missed failures** (measured):
  - 0 `recycle-dead` in the live file or in any trim drop count.
  - 0 relaunch-failed alarms in `~/.claude/handoff-alarms`.
  - The only recovery packet is pane 157 (forced).
  - The only relaunch-write failures quoted in any transcript are F1 and pane 157.
- **Pre-fix census:**
  - Rows from the 2026-10-09T15:47Z rr-census listing, quoted in transcript `agent-acea324cdc3ce02e6`: 33 engaged and 1 F1. 4 never-typed rows are dropped: pane 37's `recycle-dead` (verdict cc, claude never exited) and 3 held rows.
  - Plus the F1 skeptic's zsh-history census: 22/22 overlapping watchers had both nonce lines. Pid 68695 (17:42Z) is added.
  - zsh history timestamps before 10-15 05:01Z were rewritten, so history alone cannot date entries.
- **Estimated loads** come from the `capacity-alarm.jsonl` (+ `.20261009T015023Z.gz`) 1-min samples:
  - **Section B pre-fix rows** (and the 10-13 rows): the max over the 180 s ending 30 s before the engaged row.
  - **Moves**: the min and max over the move's actuate→result span.
  - **Calibration** against telemetry, n=42 attempts: median |Δ| 0.2/core, p90 1.12, max 2.5. All 42 land in the same bucket.
- **Scope:** read-only. Helper scripts and intermediates are in `/tmp/lri-h/` (`attempts.json`, `census-rows.json`, `movewin.out`).
