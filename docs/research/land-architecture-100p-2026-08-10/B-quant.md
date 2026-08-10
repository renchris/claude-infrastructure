# B-quant — measured congestion picture of the landing pipeline

Measured 2026-08-10 08:15–08:31Z. Log snapshot grew 2,929 → 2,937 rows during the read; every
table states the row count it used. Read-only: no repo or log file was modified.
Log timestamps are UTC (`Z`); box local time is **UTC-7 (PDT)** — verified `date -u` = 08:23:52Z
while `uptime` read `1:26`. Day buckets are **UTC days**, so `2026-08-10` is a partial day
covering 00:00–08:31Z only (= 17:00 Aug-9 → 01:31 Aug-10 PDT).

---

## 0. The brief's premise is wrong about the denominator (schema finding)

`~/.claude/land.log` is **not** 2,914 rows of `{ts,repo,branch,wait_s,hold_s,exit,pid}`.
It is two interleaved record types from two different writers.

```
jq -r 'if has("wait_s") then "LOCK" else "TOOL:"+(.tool//"?") end' ~/.claude/land.log | sort | uniq -c
```

| Record | Writer | n (of 2,937) | Carries wait_s/hold_s? | Semantics |
|---|---|---:|---|---|
| **LOCK** | `scripts/land-lock.sh:74` (`logline`) | 1,466 | yes | one **lock acquisition** (or one wait-timeout) |
| **TOOL** | `scripts/ship-land.sh:476` (`attest_land`) | 1,471 | no | one **ship-land invocation** (the attestation) |

Consequences that govern every number after this:

- **Any percentile over all rows halves its own denominator or mixes units.** `wait_s`/`hold_s`
  exist on 1,466 rows, not 2,937.
- **LOCK rows are not attempts.** One ship-land invocation runs up to `SHIP_LAND_GATE_ROUNDS`
  (default 3, `ship-land.sh:2353`) optimistic rounds, each spawning its own land-lock → up to
  3 LOCK rows + 1 TOOL row per attempt. `pid` differs per round, so `pid` does not identify an attempt.
- **A gate-red never reaches the lock.** The gate runs *unlocked*, before the lock; exit 6 produces
  a TOOL row and **no** LOCK row. The LOCK ledger is structurally blind to the largest loss channel (§7).
- Exit codes on a LOCK row are the *child's* exit under the lock. Per `ship-land.sh:56-58`:
  `0` landed · `42` **INTERNAL** stale-gate CAS miss (retried, not a failure) · `5` rebase conflict ·
  `6` gate red · `7` push non-ff. `75` is land-lock's own EX_TEMPFAIL (`land-lock.sh:134`, wait budget
  exhausted). `130` is land-lock's **default** `CODE=130` (`land-lock.sh:142`) — the process was
  signalled before `"$@"` returned. `127` = command-not-found *under* the lock.

---

## 1. There was a regime change, not a trend: LAND_PIPELINE_V2

`git log origin/main --oneline --since=2026-07-27 --until=2026-07-30 -- scripts/ship-land.sh docs/plans/LAND_PIPELINE_V2.md`

The v2 "inversion" (full suite moved out of the land; land carries only O(diff) work) lands
**2026-07-28**. Every "last 14d vs prior" split in the brief is therefore in practice
**post-V2 vs pre-V2** — the 14-day window opens 2026-07-27. Read the two periods as two different
machines, not as a time series.

---

## 2. (a) wait_s / hold_s percentiles, split by exit code

```
python3 - <<'PY'
import json
from datetime import datetime,timezone,timedelta
L=[json.loads(l) for l in open('/Users/chrisren/.claude/land.log') if l.strip()]
lock=[r for r in L if 'wait_s' in r]
for r in lock: r['t']=datetime.strptime(r['ts'],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
now=max(r['t'] for r in lock); cut=now-timedelta(days=14)
def pct(v,p):
    v=sorted(v); k=(len(v)-1)*p/100; f=int(k); c=min(f+1,len(v)-1); return round(v[f]+(v[c]-v[f])*(k-f),1)
for field in ('wait_s','hold_s'):
    for lab,rs in (("14d",[r for r in lock if r['t']>=cut]),("prior",[r for r in lock if r['t']<cut])):
        for ex in [None]+sorted({r['exit'] for r in rs}):
            s=rs if ex is None else [r for r in rs if r['exit']==ex]
            if not s: continue
            v=[r[field] for r in s]
            print(field,lab,'exit='+str(ex if ex is not None else '*'),len(v),pct(v,50),pct(v,90),pct(v,99),max(v),sum(v))
PY
```

**wait_s (seconds queued for the lock, as land-lock accounts it)** — 1,462-row snapshot

| period | exit | n | p50 | p90 | p99 | max | sum |
|---|---|---:|---:|---:|---:|---:|---:|
| 14d | **all (POISONED)** | 1018 | 0 | 77.0 | 245.8 | 728 | 19,924 |
| 14d | 0 (landed) | 824 | 0 | 23.7 | 84.0 | 165 | 5,262 |
| 14d | 42 (stale-gate) | 168 | **72.5** | **191.9** | **419.3** | **728** | 14,321 |
| 14d | 127 | 18 | 0 | 86.4 | 96.1 | 97 | 332 |
| 14d | 130 | 7 | 0 | 3.6 | 8.5 | 9 | 9 |
| 14d | 7 | 1 | 0 | 0 | 0 | 0 | 0 |
| prior | **all (POISONED)** | 444 | 0 | 1959.2 | 3601.0 | 7386 | 200,545 |
| prior | 0 | 231 | 0 | 219.0 | 1560.3 | 2010 | 19,682 |
| prior | 42 | 133 | 2.0 | 2265.2 | 3934.5 | **7386** | 95,062 |
| prior | **75 (abandoned)** | **19** | 3600 | 3601 | 3601 | 3601 | 68,409 |
| prior | 6 | 34 | 0 | 360.3 | 4808.5 | 5944 | 10,431 |
| prior | 5 | 10 | 0 | 849.8 | 2290.0 | 2450 | 3,485 |
| prior | 127 | 5 | 0 | 1666.2 | 2665.9 | 2777 | 2,777 |
| prior | 130 | 9 | 0 | 296.4 | 423.8 | 438 | 699 |
| prior | 143 | 2 | 0 | 0 | 0 | 0 | 0 |

**hold_s (seconds the lock was held)**

| period | exit | n | p50 | p90 | p99 | max | sum |
|---|---|---:|---:|---:|---:|---:|---:|
| 14d | **all (POISONED)** | 1018 | 61.5 | 119.0 | 199.3 | 282 | 68,017 |
| 14d | **0 (the only meaningful row)** | 824 | **87.0** | **122.7** | **203.1** | **282** | 67,375 |
| 14d | 42 | 168 | 1.0 | 1.0 | 1.3 | 2 | 103 |
| 14d | 127 | 18 | 0 | 0 | 0 | 0 | **0** |
| 14d | 130 | 7 | 99.0 | 139.0 | 160.6 | 163 | 538 |
| prior | all (POISONED) | 444 | 75.0 | 681.7 | 2922.1 | 6771 | 124,746 |
| prior | 0 | 231 | 228.0 | 966.0 | 3110.3 | **6771** | 94,338 |
| prior | 6 | 34 | 543.5 | 2084.6 | 3126.5 | 3239 | 27,404 |
| prior | 42 | 133 | 1.0 | 1.0 | 1.0 | 2 | 79 |

**The poisoning is real and runs in both directions.**
- `hold_s` "all" p50 **61.5** vs exit-0 p50 **87.0**: the 168 stale-gate rows (hold 0–2 s) and 18
  exit-127 rows (hold 0 s) drag the median down **29%**. Never quote an all-rows hold percentile.
- `wait_s` moves the *other* way: exit-0 p90 is 23.7 s but exit-42 p90 is 191.9 s. Averaging them
  gives 77.0 — a number describing no population that exists. §4 shows why they must be split.
- Pre-V2, 19 rows are pure `wait_s=3600, hold_s=0, exit=75` **abandons** contributing 68,409 s
  (19.0 h) of wait and zero work; including them puts the "p99 wait" at exactly the configured
  `LAND_LOCK_WAIT` ceiling — a percentile measuring a config constant, not a queue.
  **Zero exit-75 rows post-V2.**

---

## 3. (a) Per-day attempt counts and distributions

Same loader as §2, bucketed by `r['t'].date()`. `e0/e42/e6/e75/e127` = LOCK-row exit counts.
`hold p50/p90` on **exit-0 rows only**. `lock-min` = sum(hold_s)/60 (all rows). `util` = sum(hold_s)/86400.

| day (UTC) | LOCK rows | e0 | e42 | e6 | e75 | e127 | wait p50 | wait p90 | wait max | rows wait>0 | hold0 p50 | hold0 p90 | hold0 max | lock-min | util |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 07-11 | 4 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 19 | 20 | 20 | 1.0 | – |
| 07-15 | 19 | 18 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 33.5 | 51.3 | 52 | 9.8 | – |
| 07-17 | 10 | 9 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 18 | 84 | 84 | 7.6 | – |
| 07-18 | 7 | 7 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 94 | 113 | 117 | 7.3 | – |
| 07-19 | 96 | 72 | 0 | 10 | 0 | 1 | 0 | 252.0 | 672 | 28 | 308 | 348 | 415 | 396.9 | – |
| 07-20 | 33 | 23 | 0 | 7 | 0 | 0 | 0 | 230.6 | 470 | 5 | 502 | 659 | 731 | 267.9 | – |
| 07-23 | 10 | 6 | 0 | 4 | 0 | 0 | 0 | 113.4 | 486 | 2 | 681 | 820 | 949 | 117.4 | – |
| 07-24 | 6 | 5 | 0 | 1 | 0 | 0 | 29.5 | 741.0 | 1223 | 3 | 1127 | 1162 | 1180 | 102.7 | – |
| 07-25 | 38 | 20 | 15 | 1 | 0 | 1 | 0 | 1524.7 | 2777 | 13 | 48 | 1057 | 6771 | 247.6 | – |
| **07-26** | **183** | 48 | **102** | 9 | **19** | 3 | 0 | **3600.0** | **7386** | **86** | 101 | 2682 | 3260 | **787.8** | – |
| 07-27 | 35 | 18 | 16 | 1 | 0 | 0 | 0 | 2240.8 | 3031 | 9 | 95 | 219 | 1787 | 84.8 | – |
| — LAND_PIPELINE_V2 lands 07-28 — | | | | | | | | | | | | | | | |
| 07-28 | 4 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 82.5 | 104 | 112 | 5.8 | 0.4% |
| 07-29 | 116 | 98 | 16 | 0 | 0 | 0 | 0 | 127.5 | 420 | 42 | 99 | 164 | 204 | 183.1 | 12.4% |
| **07-30** | **220** | **164** | 52 | 0 | 0 | 3 | 0 | 145.6 | **728** | **109** | 108 | 152 | 282 | 317.1 | **21.9%** |
| 07-31 | 110 | 96 | 9 | 0 | 0 | 4 | 0 | 77.6 | 145 | 30 | 107 | 121 | 224 | 173.5 | 11.9% |
| 08-01 | 89 | 76 | 12 | 0 | 0 | 1 | 0 | 66.6 | 203 | 24 | 100 | 121 | 189 | 133.5 | 9.3% |
| 08-02 | 27 | 27 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 37 | 93 | 110 | 21.0 | 1.5% |
| 08-03 | 25 | 25 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 32 | 53 | 152 | 17.1 | 1.2% |
| 08-04 | 11 | 11 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 28 | 38 | 273 | 9.4 | 0.7% |
| 08-05 | 46 | 41 | 5 | 0 | 0 | 0 | 0 | 5.0 | 35 | 5 | 31 | 36 | 49 | 21.8 | 1.5% |
| 08-06 | 54 | 48 | 4 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 32 | 36 | 52 | 26.6 | 1.8% |
| 08-07 | 71 | 60 | 10 | 0 | 0 | 1 | 0 | 0 | 50 | 5 | 49.5 | 66 | 88 | 51.1 | 3.5% |
| 08-08 | 85 | 75 | 8 | 0 | 0 | 2 | 0 | 0 | 49 | 5 | 46 | 54 | 63 | 58.9 | 4.1% |
| 08-09 | 93 | 66 | 21 | 0 | 0 | 3 | 0 | 0 | 45 | 7 | 57 | 81 | 183 | 69.0 | 4.7% |
| 08-10† | 64 | 30 | **31** | 0 | 0 | 2 | 0 | 29.8 | 70 | 11 | 68 | 114 | 254 | 41.2 | 3.4%† |

† partial day (08:19:54Z cutoff for this table). Utilisation uses a full 86,400 s denominator, so
08-10's figure is a **lower bound** by ~3×.

**Headline: the lock is nowhere near saturated.** Peak measured utilisation is **21.9%**
(2026-07-30); the last week runs **1.2–4.7%**. The machine-wide mutex is **not** the binding
constraint on throughput. What *is* congested is the arrival pattern — §4.

---

## 4. (b) Exit-code mix + the mechanism: waiting **causes** the stale-gate miss

`exit 42` is the CAS miss — the locked child finds `origin/main` no longer equals the `GATE_BASE`
it gated against, releases, and the outer loop re-rounds (`ship-land.sh:2364-2366`). Two distinct
producers, and they must be separated:

| day | e42 total | wait_s = 0 (base moved under a **free** lock) | wait_s > 0 (queued, **then** stale) | e42 as % of that day's LOCK rows |
|---|---:|---:|---:|---:|
| 07-25 | 15 | 12 | 3 | 39% |
| 07-26 | 102 | 46 | 56 | 56% |
| 07-27 | 16 | 8 | 8 | 46% |
| 07-29 | 16 | 0 | 16 | 14% |
| 07-30 | 52 | 0 | 52 | 24% |
| 07-31 | 9 | 0 | 9 | 8% |
| 08-01 | 12 | 2 | 10 | 13% |
| 08-05 | 5 | 0 | 5 | 11% |
| 08-06 | 4 | 4 | 0 | 7% |
| 08-07 | 10 | 6 | 4 | 14% |
| 08-08 | 8 | 4 | 4 | 9% |
| 08-09 | 21 | 15 | 6 | 23% |
| **08-10†** | **31** | **21** | **10** | **48%** |

**Conditional probabilities — the load-bearing measurement** (partition LOCK rows on `wait_s>0`,
tabulate P(exit)):

| window | wait_s = 0 | P(e42) | P(e0) | wait_s > 0 | P(e42) | P(e0) |
|---|---:|---:|---:|---:|---:|---:|
| last 14d | n=780 | 7% | 91% | n=238 | **49%** | 49% |
| last 3d | n=270 | 16% | 79% | n=28 | **86%** | 14% |
| pre-V2 | n=298 | 22% | 63% | n=146 | 46% | 29% |

**If you wait for the lock you have a coin-flip chance of having waited for nothing — and over the
last 3 days it is 86%.** The reconstructed tail shows the mechanism cleanly
(queue-start = `ts − hold_s − wait_s`, acquire = `ts − hold_s`):

```
q=07:38:41 acq=07:38:41 rel=07:40:12  w=  0 h= 91 e=  0  m3-fleet-footprint           <- holder pushes
q=07:39:41 acq=07:40:12 rel=07:40:13  w= 31 h=  1 e= 42  crash-rootcause-2026-08-09   <- wakes, CAS fails
q=07:39:44 acq=07:40:15 rel=07:40:15  w= 31 h=  0 e= 42  docs/cloud-post-app-finding  <- wakes, CAS fails
q=07:57:31 acq=07:57:32 rel=07:58:45  w=  1 h= 73 e=  0  goal-default-handoff         <- holder pushes
q=07:57:37 acq=07:58:47 rel=07:58:48  w= 70 h=  1 e= 42  crash-rootcause-2026-08-09   <- wakes, CAS fails
q=08:10:45 acq=08:10:45 rel=08:14:59  w=  0 h=254 e=  0  docs/readme-map-glossary
q=08:14:26 acq=08:14:59 rel=08:15:00  w= 33 h=  1 e= 42  wt-b4f93c9fa73c
q=08:14:35 acq=08:15:02 rel=08:15:02  w= 27 h=  0 e= 42  fix/goal-oob
```

The queue is not a work queue — it is a **staleness generator**. Every waiter that queues *during*
a successful holder's hold is, by construction, gating against the base that holder is about to
move. It acquires at release-time, spends 0–2 s discovering that, and re-rounds. Lock utilisation
stays at 3–5% precisely because the queued work is discarded rather than performed.

The `wait_s = 0, exit = 42` column is a *different* failure: the base moved between the unlocked
gate finishing and the lock being taken, with no queueing at all. That column is the one **rising**
(4 → 6 → 4 → 15 → 21 across 08-06…08-10), so today's degradation is push-*rate* pressure, not lock
contention.

---

## 5. (b) Retry structure

Chains = LOCK rows grouped by `(repo, branch)`, split when the gap exceeds 15 min.

| | chains | landed | single-row first-try | mean e42 re-rounds before a land | never reached exit 0 | landed-chain wall-clock p50 / p90 / p99 / max (s) |
|---|---:|---:|---:|---:|---:|---|
| **last 14d** | 665 | 645 (97%) | 473 (**71%**) | 0.24 | 20 (3%) | **98 / 665 / 2362 / 5536** |
| **last 3d** | 200 | 191 (96%) | 132 (**66%**) | 0.33 | 9 (4%) | **60 / 668 / 2002 / 2390** |
| **pre-V2** | 376 | 211 (**56%**) | 167 (44%) | 0.05 | **165 (44%)** | 346 / 1946 / 3361 / 6772 |

Chain-length distribution, 14d: `{1:485, 2:115, 3:29, 4:11, 5:11, 6:5, 7:3, 8:1}`, max **16**.
Re-round distribution for landed chains, 14d: `{0:557, 1:54, 2:15, 3:11, 4:6, 5:1, 6:1}`.

- **71% of branches land on the first lock acquisition** (14d). 29% are retry chains.
- 34 chains (14d) exceeded the configured 3 rounds and took the guaranteed-progress fallback lane
  (`ship-land.sh:2376`, statics-only re-gate *inside* the lock).
- Dead chains (never exit 0): 20 in 14d, exits `{42:19, 127:8, 130:3}`. Pre-V2 it was 165 (44%),
  including 18 exit-75 abandons and 19 gate-reds. **The V2 rebuild converted a 44% never-lands rate
  into 3%.**
- The p99 landed-chain wall-clock is still **2,362 s (39 min)** over 14 days, max **5,536 s
  (92 min)** — consistent with the operator's 1h08m turn. This is a **lower bound**: it starts at
  the first *lock row's* queue-start and omits the unlocked gate phase (§8.2).

---

## 6. (c) Queue-depth reconstruction

Sweep-line over `wait_s > 0` rows only: `+1` at `ts − hold_s − wait_s`, `−1` at `ts − hold_s`.
An episode is a contiguous period with ≥1 visible waiter; `queue_min` = integral of depth dt.
232 episodes total. Worst by queue-minutes:

| start (UTC) | dur (min) | **peak depth** | queue-min | distinct waiters |
|---|---:|---:|---:|---:|
| **2026-07-26 09:03:57** | 166.8 | **12** | **1105.1** | 27 |
| 2026-07-26 13:56:52 | 223.5 | 8 | 1003.2 | 20 |
| 2026-07-26 23:42:52 | 50.6 | 7 | 268.6 | 8 |
| 2026-07-24 23:22:27 | 88.6 | 4 | 213.4 | 8 |
| 2026-07-26 07:32:56 | 42.1 | 7 | 174.3 | 8 |
| 2026-07-26 13:11:10 | 37.9 | 6 | 168.7 | 6 |
| 2026-07-26 22:30:32 | 26.1 | 6 | 87.3 | 6 |
| 2026-07-30 00:52:17 | 12.2 | 3 | 27.3 | 8 |

Worst in the last 3 days:

| start (UTC) | dur (min) | peak depth | queue-min | waiters |
|---|---:|---:|---:|---:|
| **2026-08-10 08:20:04** | 4.2 | **3** | 9.6 | 3 |
| 2026-08-10 07:57:37 | 1.2 | 1 | 1.2 | 1 |
| 2026-08-10 07:19:21 | 1.1 | 1 | 1.1 | 1 |
| 2026-08-10 07:39:41 | 0.6 | 2 | 1.0 | 2 |
| 2026-08-10 08:14:26 | 0.6 | 2 | 1.0 | 2 |

**Total ledger-visible queue-minutes: all-time 3,684 · last 14d 342 · last 3d 22.**
2026-07-26 alone accounts for **2,807 of the 3,684 (76%)**.

⚠️ These are **visible** queue-minutes and are a **floor**, not the truth — §8.2 measures the gap.

---

## 7. The dominant loss channel is the gate, not the lock

TOOL rows are 1:1 with ship-land invocations, so they are the correct attempt denominator.

```
jq -c 'select(.tool=="ship-land")' ~/.claude/land.log \
 | jq -s 'group_by(.ts[0:10])|map({d:.[0].ts[0:10],n:length,e0:(map(select(.exit==0))|length),e6:(map(select(.exit==6))|length)})'
```

| window | invocations | landed | **gate-red (exit 6)** | esc-park (exit 3) |
|---|---:|---:|---:|---:|
| last 14d | 1130 | 823 (73%) | **305 (27%)** | 2 |
| last 3d | 356 | 217 (61%) | **139 (39%)** | 0 |
| last 1d | 114 | 63 (55%) | **51 (45%)** | 0 |

Per-day gate-red rate: `07-29 12% · 07-30 11% · 07-31 21% · 08-01 34% · 08-05 18% · 08-06 26% ·
08-07 42% · 08-08 32% · 08-09 39% · 08-10 44%`. Pre-V2 it was 69–71%.

**Nearly half of all landing attempts today die at the unlocked gate and never touch the lock.**
That is ~4× the loss the lock queue imposes, and it is invisible in every LOCK-row table.

Gate-red attribution is itself mostly missing. Of 456 exit-6 TOOL rows only **65 carry a non-empty
`red` field**; in the last 14d, **240 of 305 (79%) are unattributed**. (Partly schema growth: only
172 rows have the `red` key at all — `ship-land.sh:209` documents adding it.) Where attributed,
14d: `shellcheck 17 · dead-assertion 11 · shellcheck+dead-assertion 7 · bats-shellcheck 5 ·
hermeticity 5 · shellcheck+hermeticity 5 · smoke:<suite> 7`.

Gate composition, 14d TOOL rows: `gate_scope {fast:1126, scoped:4}` ·
`smoke {none:626, skipped:383, green:48, partial:41, red:28}` · `esc_scan {clean:1128, hit:2}` ·
`verify {ok:823, n/a:307}` · `net {inert:528, none:445, live:153}`. **The smoke is skipped or absent
on 89% of invocations** (load-shed at `CC_GATE_MAX_LOAD`, `ship-land.sh:566`), so the 27–45%
gate-red rate is produced almost entirely by *statics* — shellcheck and the ratchets — not by tests.

---

## 8. (d) COVERAGE — the ledger cannot see the wait, and this is proven, not inferred

### 8.1 The ledger *does* see the lands

```
for d in 1 2 3 7 14 30; do echo "$d $(git -C ~/Development/claude-infrastructure log origin/main --since="$d days ago" --oneline | wc -l)"; done
```

`1d 141 · 2d 277 · 3d 392 · 7d 581 · 14d 1540 · 30d 2209` commits. Commits ≠ lands: one land pushes
a `base..head` range.

| day | commits on origin/main | attested lands (TOOL exit 0) | LOCK exit-0 rows | commits/land |
|---|---:|---:|---:|---:|
| 07-29 | 156 | 98 | 98 | 1.6 |
| 07-30 | 336 | 164 | 164 | 2.0 |
| 07-31 | 221 | 95 | 96 | 2.3 |
| 08-05 | 58 | 41 | 41 | 1.4 |
| 08-06 | 57 | 48 | 48 | 1.2 |
| 08-07 | 102 | 60 | 60 | 1.7 |
| 08-08 | 125 | 75 | 75 | 1.7 |
| 08-09 | 120 | 66 | 66 | 1.8 |
| 08-10† | 68 | 31 | 31 | 2.2 |

- TOOL exit-0 and LOCK exit-0 agree to within ±1/day post-V2. **No systematic land under-count.**
- **882/882** attested `head` shas resolve in the local object store; **200/200** of the most recent
  are ancestors of `origin/main` (`git merge-base --is-ancestor <head> origin/main`).
- Of 392 origin/main commits in the last 3 days, **375 (96%) fall inside some attested `base..head`**;
  17 (4%) unclaimed — most plausibly window-edge (their land row predates the 3-day land window) or
  the 118/999 older exit-0 rows that predate the `head`/`base` schema. **Not verified; UNMEASURED.**

### 8.2 …but it cannot see the WAIT. Two structural blind spots, both measured live.

**Blind spot 1 — a queued waiter writes nothing.** `land-lock.sh:129-138` loops on `try_acquire`
and calls `logline` only at line 133 (wait budget exhausted → exit 75) or from the EXIT trap at
line 146 (after release). **There is no row while queueing.** The brief's hypothesis is confirmed
both by reading the code and by direct observation:

| 08:23:52Z observation (`ps -eo pid,ppid,stat,etime,lstart,command`) | ledger at that instant |
|---|---|
| holder pid 3086 `wt-b4f93c9fa73c`, lock held | last row `08:19:54Z` |
| waiter pid 68954 `wt-bc50117059ac`, queued 3m48s | **no row** |
| waiter pid 63077 `docs/cloud-push-policy-denied`, queued 2m50s | **no row** |
| waiter pid 17004 `research/memory-econ-2026-08-10`, queued 1m55s | **no row** |

All four rows appeared **at once at 08:24:11–08:24:15Z**, after the holder released:
`3086 w=0 h=257 e=0` · `68954 w=248 h=1 e=42` · `63077 w=191 h=1 e=42` · `17004 w=137 h=1 e=42`.
Each waiter's `wait_s` matched its observed process age to within 1 s. The operator's pid **69428
returns zero rows** in the log — exactly the predicted signature of a still-queued waiter.

**Corollary — the log is RIGHT-CENSORED.** At any read instant the in-flight episode is absent, and
the longest episodes are by construction the most likely to be in flight. Every percentile in §2 and
every episode in §6 is biased **low in the tail**. A holder killed with `SIGKILL` writes no row at
all (`trap release EXIT` does not fire on SIGKILL); frequency UNMEASURED.

**Blind spot 2 — the unlocked gate rounds are outside land-lock's clock entirely, and it is larger
than blind spot 1.** `ship-land.sh:2376` is `exec "$LAND_LOCK" -- "$SELF" __locked …`: the fallback
lane **replaces** the ship-land process, so land-lock inherits ship-land's pid *and* its process
start time, while `WAIT_START` (`land-lock.sh:127`) begins only at exec. Two measured instances:

| pid | true process lifetime (ps `lstart` → row `ts`) | ledger attests | **unaccounted** |
|---|---|---|---|
| 3086 | 08:05:49 → 08:24:11 = **1102 s** | `wait_s:0 hold_s:257` = 257 s | **845 s (77%)** |
| 39792 | 08:12:32 → 08:27:32 = **900 s** | `wait_s:0 hold_s:197` = 197 s | **703 s (78%)** |

Both attest **`wait_s: 0` — "no contention"** — for a land that took 15–18 minutes of wall clock.
The missing 77–78% is the three optimistic gate rounds (`SHIP_LAND_GATE_ROUNDS=3`,
`ship-land.sh:2353`), each a full unlocked fetch → rebase → statics → smoke.

Ruled out as causes of the gap, by direct probe rather than assumption:

- *git preamble calls blocking* — `git rev-parse --show-toplevel` 0.053 s, `--git-common-dir`
  0.040 s, `--abbrev-ref HEAD` 0.056 s, measured in the same worktree at load 28. **Refuted.**
- *memory pressure / swap stalling process start* — `memory_pressure` 87% free; `vm_stat` Swapins 0,
  Swapouts 0; `vm.swapusage` 0.00 M used; `shasum` pipeline 0.019 s ×5; `mkdir -p` 0.004 s ×5.
  **Refuted.**
- *Darwin background QoS band* — live land processes measure `pri=31 ni=0` (foreground) for
  session-spawned lands; only `ni=5 / pri=31 SN` on one orphan and `pri=20 ni=19` on /Users/chrisren/.claude/bin/cc-bats children.
  **Refuted for these instances.**

### 8.3 Live process state at 08:30:30Z (read-only `ps`)

```
ps -eo pid,ppid,pri,nice,stat,etime,command | grep -E "land-lock.sh --|ship-land.sh"
```

| pid | ppid | pri/ni | stat | etime | role |
|---|---|---|---|---|---|
| **82031** | **1** | 31/5 | SN | **20:30** | **lock holder**, `wt-bc50117059ac`, fallback lane (empty `GATE_BASE`/`GATE_HEAD` argv), **orphaned** |
| 93230 | 82031 | 31/5 | SN | 02:57 | its locked ship-land child |
| 20799 | 93230 | 26/5 | SN | 00:36 | grandchild ship-land |
| 58559 | 56747 | 31/0 | S | 01:59 | land-lock **waiting** — no ledger row |
| 56747 | 56112 | 31/0 | S | 12:08 | its ship-land, 12 min in |
| 47282 | 47271 | 31/0 | S | 02:10 | ship-land, pre-lock (gate phase) |

`/tmp/land-lock-3cca03ed6835/lock.d`: `pid=82031 branch=wt-bc50117059ac lstart=Mon 10 Aug 01:10:01`,
dir age 177 s. **The current holder has ppid 1** — its owning session died, yet it holds the
machine-wide mutex, and the reap rule deliberately never reaps a live holder (`land-lock.sh:92-94`).
Box state: `load averages: 28.77 43.02 50.11` on `hw.ncpu=10` (**2.9–5.0 per core**); 56 processes
>100 MB RSS totalling **31.4 GB**.

A 20-second sampler (`/tmp/land-live-watch.txt`) recorded `nlandlock` oscillating 1→2 while
`logrows` stayed frozen at 2934 for **3 min 20 s**, then 2937 — a second independent observation of
waiters existing while the ledger reports nothing.

---

## 9. Adversarial pass

| challenge | verdict |
|---|---|
| *"Do your percentiles mix refusal rows with real lands?"* | The all-rows rows in §2 do, and they are labelled **POISONED** and shown only to quantify the distortion: `hold_s` p50 61.5 vs 87.0 exit-0 (−29%). Every operational number in §3–§8 is exit-split. |
| *"Is exit 42 a failure you're counting as one?"* | No. `ship-land.sh:56-58` marks 42 INTERNAL; it is retried and never escapes. It appears here as **wasted wait**, never in a failure rate. Failure rates use TOOL rows (§7). |
| *"Is '14d vs prior' a time trend?"* | **No — it is a rebuild boundary.** LAND_PIPELINE_V2 lands 2026-07-28 and the 14d window opens 07-27. Relabelled post-V2 / pre-V2 (§1). |
| *"Is the queue-depth reconstruction complete?"* | **No, and it cannot be.** It sees only `wait_s>0` rows, i.e. waits that *resolved*. §8.2 measures 77–78% of a land's wall-clock outside land-lock's clock entirely. All §6 figures are floors. |
| *"Is `pid` a stable attempt id?"* | No. Normal rounds get a fresh land-lock child pid; the fallback lane `exec`s and inherits ship-land's pid **and start time** — which is what made the 845 s / 703 s gaps look like a mystery stall until `ship-land.sh:2376` explained them. |
| *"Have you checked whether the ledger misses whole lands, not just waits?"* | Yes — §8.1. It does not: 882/882 heads resolve, 200/200 recent heads are ancestors of origin/main, TOOL and LOCK exit-0 agree ±1/day. The under-coverage is of **time**, not of **events**. |
| *"What did you assume was irrelevant?"* | Initially the TOOL rows — treating the log as one schema. That assumption would have hidden the largest finding (§7): a 45%/day gate-red rate that produces no LOCK row at all. |
| *"UTC vs local day boundaries?"* | Named. Buckets are UTC days; box is UTC-7. 2026-08-10 is a partial UTC day and its utilisation figure is a ~3× lower bound. |

---

## 10. UNMEASURED (named, not imputed)

1. **Time-to-land per session.** No row records ship-land invocation start. §5's chain wall-clock is
   a floor; §8.2's two ps-derived lifetimes are n=2, not a distribution.
2. **How often a holder is SIGKILLed.** The EXIT trap cannot fire; such an episode leaves a stale
   lock dir and zero rows. Not derivable from the log.
3. **Cause of the 79% unattributed gate-reds.** The `red` field is empty on 240/305 recent exit-6 rows.
4. **The 17 unclaimed origin/main commits (last 3d).** Window-edge vs a genuine non-ship-land push
   route — not distinguished.
5. **The lock-key grouping in §3's repo table is heuristic.** The true key is
   `sha1(git --git-common-dir)` (`land-lock.sh:43-51`); the log stores `repo` (the worktree), not the
   key. 1,391/1,462 rows are claude-infrastructure worktrees, so cross-repo contamination is ≤5%, but
   it is not zero and was not resolved per row.
6. **Whether the orphaned holder (pid 82031, ppid 1) is making progress or is wedged.** Observed
   holding for ~3 min at read time with a live child; not followed to completion.

---

## 11. The three numbers that answer the brief

1. **The mutex is not the bottleneck** — peak lock utilisation 21.9% (07-30); last week 1.2–4.7%.
2. **Queueing is nearly pure waste** — P(stale-gate | waited) = **49%** over 14 d and **86%** over
   3 d; queued rounds hold the lock for 0–2 s and discard their work.
3. **The ledger under-reports congestion by ~4×** — two directly measured lands attest `wait_s: 0`
   while spending 845 s and 703 s (77%, 78% of their lifetimes) outside land-lock's clock, and every
   waiter is invisible until it resolves. The biggest loss channel of all — a **45%/day gate-red
   rate** — writes no lock row whatsoever.
