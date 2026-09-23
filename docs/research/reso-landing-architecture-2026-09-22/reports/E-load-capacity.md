# E: machine capacity for the landing-throughput model (load inflation, CPU per land, concurrency)

Box: M1 Max, `hw.ncpu`=10, `hw.perflevel0` Performance 8, `hw.perflevel1` Efficiency 2, 64 GB. The single ps snapshot was taken at 2026-09-23T00:13:29-05:00, loadavg {231.98 237.06 224.74}.
Data: `~/.reso/land.log` has 161 v3 rows (2026-09-14T03:57Z to 2026-09-23T05:20Z; the log is still growing, so re-running the code gives slightly different n). `~/.reso/load.jsonl*` has 73,898 rows (2026-09-14T03:54Z to 2026-09-23T05:10Z). Script sources are on origin/main @ `108be1a7b`.
Evidence labels: **[E]** means measured or fitted from logs. **[T]** means inferred from a model or mechanism.

## Answer first

1. **The main thing that slows verification is other verification suites running concurrently. Load1 matters much less.** [E] Each concurrently running suite adds:
   - **45.1 ± 4.8 s** to a union suite
   - **49.1 ± 5.1 s** to the pre-push full suite
   - **11.5 ± 5.0 s** to tsc

   Adding the concurrency term raises R² from 0.36 to 0.73 (union) and from 0.56 to 0.84 (push). Each unit of ambient load1 costs only 0.18–0.30 s. Among union rounds with load1 < 100, the load1 effect is indistinguishable from zero (0.15 ± 0.17) while the concurrency effect stays at 48 ± 8 s.
2. **Load1 is a poor capacity signal on this box.** [E] At load1 232, three things held:
   - ps showed only **6.2 cores** of decayed %CPU, with 106 processes in state R.
   - 34 of those R-state processes were Chrome helpers at about 0% CPU.
   - Verification (vitest + tsc) was **≥ 40 % of measured CPU**, but a suite's own load1 footprint is only about 7–11. So verification was under about 10% of load1.
3. **CPU per code land is about 730 CPU-s for a clean round** (tsc 30 + union ~340 + pre-push ~340 + misc ~20; range 545–965). [E/T] At the measured **2.4 land-suite runs per landed code land**, a landed code land costs **about 1,650 CPU-s**. [E] If verification had the whole box, the ceiling would be about **42–49 clean rounds/h, or about 19–22 landed code lands/h**. [T]
4. **Capacity knee: about 2 concurrent suites (about 2 lands in their verify window).** [E + T]
   - The 2nd concurrent suite adds about 42 % throughput, the 3rd about 16 %, the 4th about 9 %. Each one adds 45–49 s to every suite already in flight.
   - Kleinrock-power optimum (the concurrency that maximises throughput ÷ latency): n* = T1/c − 1 ≈ **1.5 at load1 50, 2.3–2.7 at load1 250**.
   - cc-sem `reso-land` K=1 already caps the union stage at about **23 rounds/h (about 10 landed code lands/h at today's retry rate)**. That is below the CPU ceiling, so **admission plus retries bind before CPU does.** `general` K=3 lets pre-push suites stack up to 4 concurrent suites in total, which is past the knee.
5. **Inflation does not run away as load rises; timeouts and queues do.** [E]
   - Binned medians grow roughly linearly up to load1 394 (×1.2–1.5 per +100 load1).
   - What fails at the bounds:
     - the `reso-land` wait: sem_wait p90 268 s with 3+ lands in flight, and 3 refusals at the 300 s bound;
     - the default `LAND_PUSH_TIMEOUT=120`, which sits below the pre-push suite's *unloaded* ~117 s (4 terminal push-timeouts, all at exactly 120 s).

---

## (a) load.jsonl schema and load1 by hour of day

**Writer:** `scripts/load-sampler.sh`. launchd starts it via `~/.reso/load-sampler-run.sh`. It appends 1 row every `RESO_LOAD_INTERVAL` = 10 s (`load-sampler.sh:29`). The file rotates on the first write of a new local day, based on its own mtime (`:39-51`), and the newest 14 dated files are kept (`:49`). The sampler only observes; it never signals or throttles.

| field | type | meaning (source) |
|---|---|---|
| `ts` | ISO-8601 UTC string | sample time |
| `loadavg` | [l1, l5, l15] floats | `sysctl -n vm.loadavg` (`:58`) — macOS counts *runnable threads* at every QoS |
| `runnable` | int | processes whose ps state starts with `R` (`:62`) — processes, not threads |
| `top3` | [{`rss_mb`, `cmd`}×3] | top 3 by **RSS** (`:65`) — says nothing about CPU |
| `sem` | {`reso-land`, `reso-verify`, `general`: [{`slot`,`pid`,`label`}]} | cc-sem slot holders, read from `~/.cc-sem/<class>/slot-*` without acquiring (`:75`) |

- **Coverage [E]:** 73,898 rows (5 torn rows skipped). Sample interval p50 10 s, p99 14 s. There are 19 gaps longer than 60 s, 5.3 h in total (longest 72 min).
- **Overall load1 [E]:**

  | p10 | p25 | p50 | p75 | p90 | p95 | p99 | max | mean |
  |---|---|---|---|---|---|---|---|---|
  | 7.2 | 9.4 | 13.4 | 20.5 | 34 | 59 | 156 | 394 | 20.5 |

  corr(load1, runnable) = 0.89.
- **The box is almost never below 10 cores' worth of runnable threads.** Load1 > 10 in 31–100 % of each day's samples.

**By local day (CDT, UTC−5) [E]:**

| day | n | p50 | p90 | max | frac > 50 | frac > 100 | frac > 200 |
|---|---|---|---|---|---|---|---|
| 09-13 (from 22:54) | 385 | 22 | 31 | 69 | .01 | 0 | 0 |
| 09-14 | 8466 | 12 | 22 | 127 | .00 | 0 | 0 |
| 09-15 | 8454 | 16 | 25 | 74 | .00 | 0 | 0 |
| 09-16 | 8408 | 12 | 22 | 394 | .01 | .00 | .00 |
| 09-17 | 8478 | 12 | 24 | 77 | .01 | 0 | 0 |
| 09-18 | 8498 | 8 | 13 | 54 | .00 | 0 | 0 |
| 09-19 | 8035 | 13 | 42 | 166 | .07 | .02 | 0 |
| 09-20 | 6894 | 19 | 75 | 310 | .20 | .05 | .00 |
| 09-21 | 8367 | 13 | 23 | 185 | .01 | .00 | 0 |
| 09-22 | 7870 | 26 | 123 | 364 | .27 | .13 | .04 |
| 09-23 (00:00–00:10) | 43 | 257 | 292 | 315 | 1 | 1 | .93 |

**By local hour of day (CDT), pooled over the 9–10 days [E]:**

| h | n | p10 | p50 | p90 | max | mean | | h | n | p10 | p50 | p90 | max | mean |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 00 | 3211 | 7 | 16 | 32 | 315 | 21 | | 12 | 2930 | 7 | 12 | 32 | 130 | 17 |
| 01 | 3164 | 6 | 13 | 27 | 140 | 16 | | 13 | 2907 | 7 | 12 | 45 | 324 | 23 |
| 02 | 3159 | 7 | 13 | 32 | 212 | 19 | | 14 | 2651 | 10 | 14 | 76 | 315 | 35 |
| 03 | 3163 | 6 | 11 | 26 | 223 | 19 | | 15 | 2948 | 7 | 14 | 31 | 394 | 22 |
| 04 | 3100 | 9 | 14 | 44 | 258 | 28 | | 16 | 3120 | 7 | 13 | 42 | 343 | 23 |
| 05 | 3135 | 8 | 12 | 51 | 113 | 20 | | 17 | 3159 | 8 | 15 | 38 | 97 | 20 |
| 06 | 3125 | 7 | 13 | 38 | 119 | 19 | | 18 | 3057 | 7 | 15 | 33 | 81 | 17 |
| 07 | 3154 | 7 | 11 | 30 | 74 | 15 | | 19 | 3153 | 6 | 16 | 38 | 166 | 20 |
| 08 | 3104 | 8 | 12 | 22 | 55 | 14 | | 20 | 2809 | 9 | 15 | 44 | 122 | 21 |
| 09 | 2933 | 7 | 12 | 24 | 40 | 14 | | 21 | 3038 | 8 | 14 | 34 | 169 | 20 |
| 10 | 3170 | 6 | 10 | 24 | 189 | 18 | | 22 | 3160 | 7 | 13 | 33 | 174 | 19 |
| 11 | 3122 | 8 | 14 | 69 | 364 | 27 | | 23 | 3426 | 9 | 17 | 40 | 272 | 28 |

**What the tables show:**
- **There is no diurnal cycle.** Hourly medians sit between 10 and 17.
- **The tails come from single events,** not from a time of day. Examples of per-day hourly medians: 09-20 04–06h = 151/71/71; 09-22 14h = 229; 09-22 23h = 132; 09-23 00h = 257.
- **The capacity model should treat load as bursty and wave-driven, not diurnal.**
- **Today's 230–290 is the 9-day extreme** (p99 = 156).

---

## (b) Regressions of stage time on load1

**Row selection:**
- **tsc:** rounds with `tsc_skipped==0`.
- **union / full:** `suite_mode` = union or full. The land-time suite runs under `cc-sem reso-land`.
- **push (code):** the round ran a suite AND the pre-push full suite completed. That means `push_rc==0`, or the remote rejected the push after the hook passed (non-fast-forward or cannot-lock).
  - Excluded: 5 hook test failures, 1 audit-ci failure, and 4 timeouts. The timeouts are right-censored at 120 s.
- **Two load regressors:**
  - `load1_entry` is from land.log.
  - `load1_window` is the mean of load.jsonl load1 over the stage's own interval. Intervals are rebuilt from `ts_start` plus the stage durations; unaccounted overhead per attempt is p50 2 s, max 29 s.

### Simple regressions [E]

| stage | x | n | slope s/load (±se) | intercept s | R² | Theil-Sen slope | load at which time doubles (a/b) |
|---|---|---|---|---|---|---|---|
| tsc_s | load1_entry | 127 | **0.225 ± 0.042** | 25.3 | 0.19 | 0.157 | 113 |
| tsc_s | load1_window | 127 | 0.241 ± 0.043 | 24.6 | 0.20 | 0.177 | 102 |
| suite_s (union) | load1_entry | 68 | **0.260 ± 0.043** | 119.4 | 0.35 | 0.287 | 459 |
| suite_s (union) | load1_window | 68 | 0.285 ± 0.046 | 119.6 | 0.36 | 0.325 | 419 |
| suite_s (full, land-time) | load1_entry | 10 | 0.483 ± 0.163 | 119.4 | 0.52 | 0.536 | 247 |
| suite_s (full, land-time) | load1_window | 10 | 0.547 ± 0.127 | 107.1 | 0.70 | 0.620 | 196 |
| **push_s (pre-push full suite)** | load1_entry | 58 | **0.375 ± 0.052** | 131.9 | 0.48 | 0.400 | 352 |
| push_s (pre-push full suite) | load1_window | 58 | 0.463 ± 0.055 | 126.5 | 0.56 | 0.501 | 273 |
| push_s (no-code land, no suite) | load1_entry | 69 | 0.101 ± 0.075 | 5.1 | 0.03 | **0.000** | — (p50 3 s) |

- **Lead's 7-day window (≥ 2026-09-16T04:59Z) [E]:**
  - tsc: 0.210 s/load, intercept 29.1, R² 0.16, n=103
  - union: 0.248, 122.6, 0.34, n=65
  - push (code, `push_rc==0`): 0.416, 124.8, 0.55, n=31

  These match the full-span fits.
- **Per-file normalisation, union [E]:** `suite_s/suite_files` on load1_entry gives R² 0.48. A file-count term helps (0.15–0.28 s per file), but see the concurrency law below.

### The law that actually fits: stage time on window load1 plus concurrent suites [E]

`other_suites` is the mean number of *other* cc-sem holders during the stage (the stage's own slot is subtracted). For tsc, the term is `suites_running`; tsc itself is not admitted.

| stage | intercept | load1_window | concurrent suites | R² | n |
|---|---|---|---|---|---|
| union suite_s | 100.8 ± 4.6 | 0.198 ± 0.032 | **45.1 ± 4.8** | **0.73** | 68 |
| pre-push push_s | 107.8 ± 4.9 | 0.303 ± 0.038 | **49.1 ± 5.1** | **0.84** | 58 |
| tsc_s | 21.5 ± 5.4 | 0.178 ± 0.050 | **11.5 ± 5.0** | 0.23 | 127 |

**Robustness checks [E]:**
- **Union rows split by load:**
  - load1_window < 100: other = 48.4 ± 7.8, load = 0.15 ± 0.17 (n=36)
  - load1_window ≥ 100: other = 42.3 ± 6.6 (n=32)

  So the concurrency cost does not depend on ambient load.
- **Union, raw means at load1 < 60:** suite alone (other < 0.2) averages 101 s (n=14). With ≥ 0.5 other suites it averages 155 s (n=11).
- **Push, split by which lane holds the other suite:** a concurrent union suite (`reso-land`) costs 49.0 ± 6.7 s. Another `general` suite costs 30.5 ± 7.9 s; that lane includes lighter jobs such as design:gate `--workers=1` and ad-hoc runs.
- **Other specifications:** with load1_entry instead of window load, or without the files term, the concurrency coefficient stays at 44–47.

**What this means [T]:**
- **The coefficients fit a processor-sharing model** with about 10 equal cores, where each suite draws about 4 cores. In that model, the cost of one extra 4-core suite is ∂T/∂n = 4·T0/C. Solving for effective capacity C:
  - tsc: 4·21.5/11.5 = 7.5
  - union: 4·100.8/45.1 = 8.9
  - push: 4·107.8/49.1 = 8.8

  So **C ≈ 7.5–9, consistent with 8 P-cores plus 2 E-cores at about 0.3 P-core each (≈ 8.6 P-equivalents).**
- **A unit of ambient load1 costs 0.2–0.3 s, about 20× less than a unit of load1 that comes from a suite** (≈ 45 s per suite ÷ ≈ 7–11 load units per suite). Most ambient runnable threads do not compete with verification on equal terms. The evidence is in §(d).

### Linearity, knee, and the E-core/P-core split [E]

Binned medians by window load1 (n in brackets):

| load1 | 0–15 | 15–25 | 25–40 | 40–70 | 70–120 | 120–180 | 180–400 |
|---|---|---|---|---|---|---|---|
| tsc_s | 27 [6] | 27 [23] | 30 [19] | 35 [14] | 49 [19] | 65 [13] | 54 (mean 80) [24] |
| union suite_s | 98 [2] | 99 [10] | 106 [7] | 142 [11] | 154 [14] | 160 [4] | 179 [19] |
| push_s code | 106 [2] | 129 [5] | 123 [4] | 137 [5] | 174 [6] | 144 [2] | 224 [8] |

- **The curves are linear to mildly concave.** Log-linear fits give ×1.52 (tsc), ×1.22 (union) and ×1.36 (push) per +100 load1. Nothing suggests superlinear runaway up to load1 394.
- **The E-core/P-core split cannot be identified from these instruments.**
  - (i) No log records per-cluster residency; `powermetrics` needs sudo.
  - (ii) The expected knee is where load crosses 8–10, but only 2–6 rounds ran below load1 15, and the sampler's p10 is already 7.2.
  - (iii) The fitted C ≈ 7.5–9 cannot separate 8.6 P-equivalents from 10 equal cores.
- **The only E-core measurement on record** is in `scripts/hooks/pre-push:427-437`. Confining a CPU-bound Node workload to the E-cluster (`taskpolicy -b`) made it **18.5× slower** at ambient load (77,235 ms vs 4,209 ms). **Hypothesis [T]:** the E-cluster is badly oversubscribed, so background-QoS runnable threads queue on the 2 E-cores. That would inflate load1 without competing for P-cores, which fits the small load1 slopes.
- **tsc caveat [E]:** `tsconfig.json` sets `incremental: true`. tsc_s is bimodal: warm runs take 5–10 s and cold runs 40–60 s at the same load (for example, load1 242 gave 16, 30, 59, 100, 111 and 136 s). Load explains only about 20 % of tsc variance, and cache state was not logged.

### Fitting code (as run; stdlib + numpy + scipy)

```python
import json, glob, re, os, datetime as dt, numpy as np
from scipy import stats
H=os.path.expanduser('~/.reso/')
T=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=dt.timezone.utc).timestamp()
S=[]
for f in sorted(glob.glob(H+'load.jsonl.202609*'))+[H+'load.jsonl']:
    for l in open(f):
        try: r=json.loads(l)
        except ValueError: continue
        s=r.get('sem') or {}
        S.append((T(r['ts']),r['loadavg'][0],sum(len(v) for v in s.values())))
S.sort(); A=np.array(S); ts,L1,NS=A[:,0],A[:,1],A[:,2]
def wmean(t0,t1,x):                      # mean over the stage window; nearest sample (<30 s) for short stages
    m=(ts>=t0)&(ts<=t1)
    if m.any(): return x[m].mean()
    i=min(np.searchsorted(ts,(t0+t1)/2),len(ts)-1); return x[i] if abs(ts[i]-(t0+t1)/2)<30 else np.nan
R=[]
for l in open(H+'land.log'):
    if not l.startswith('{"v":3'): continue
    r=json.loads(l); c=T(r['ts_start'])
    for pr in r['per_round']:                # ship-land order: reconcile → tsc → sem wait → suite → push
        w={}
        for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s','push_s'):
            v=pr.get(k) or 0; w[k]=(c,c+v); c+=v
        R.append((r,pr,w))
def rep(name,rows,y,stage,multi=True):
    xe=np.array([r['load1_entry'] for r,pr,w in rows],float)
    xw=np.array([wmean(*w[stage],L1) for r,pr,w in rows])
    o=np.array([max(0,wmean(*w[stage],NS)-(0 if stage=='tsc_s' else 1)) for r,pr,w in rows])
    y=np.array(y,float); ok=~np.isnan(xw)
    for lab,x in (('load1_entry',xe),('load1_window',xw)):
        lr=stats.linregress(x[ok],y[ok]); th=stats.theilslopes(y[ok],x[ok])
        print(name,lab,ok.sum(),lr.slope,lr.stderr,lr.intercept,lr.rvalue**2,th[0],lr.intercept/lr.slope)
    if not multi: return
    X=np.column_stack([np.ones(ok.sum()),xw[ok],o[ok]]); b,*_=np.linalg.lstsq(X,y[ok],rcond=None); e=y[ok]-X@b
    se=np.sqrt(np.diag(e@e/(len(e)-3)*np.linalg.inv(X.T@X))); print(name,'multi',b,se,1-e@e/((y[ok]-y[ok].mean())**2).sum())
tsc=[q for q in R if q[1].get('tsc_skipped')==0 and q[1].get('tsc_s')]; rep('tsc_s',tsc,[q[1]['tsc_s'] for q in tsc],'tsc_s')
for mode in ('union','full'):
    su=[q for q in R if q[1].get('suite_mode')==mode and q[1].get('suite_s')]; rep('suite_s[%s]'%mode,su,[q[1]['suite_s'] for q in su],'suite_s')
done=lambda pr: pr.get('push_rc')==0 or re.search(r'fast-forward|fetch first|cannot lock ref',pr.get('push_tail') or '')
pp=[q for q in R if q[1].get('suite_mode') in ('union','full') and q[1].get('push_s') and done(q[1])]; rep('push_s[code]',pp,[q[1]['push_s'] for q in pp],'push_s')
nc=[q for q in R if q[1].get('suite_mode')=='none' and q[1].get('push_rc')==0]; rep('push_s[no-code]',nc,[q[1]['push_s'] for q in nc],'push_s',multi=False)
```

---

## (c) CPU-seconds per land, by stage

| stage | wall time when alone at low load [E] | parallelism | CPU-s per run | basis |
|---|---|---|---|---|
| reconcile, fetch, git push network, docs gate, content-verify | reconcile p50 ~1–5 s; no-code push p50 3 s | ~1 | **~20** (10–30) | [T] from no-code push and reconcile times |
| tsc (`pnpm typecheck` = `tsc --noEmit`, incremental) | 27 s median / 30 s mean at load1 < 25 (n=29); intercepts 21.5–25 | 1 thread (tsc is single-threaded) | **~30** (warm 6–10, cold 40–60) | [E] wall ≈ CPU for one thread at low contention |
| union suite (`vitest related --run <diff> <159 always-run specs>`, maxWorkers 4, under `cc-sem reso-land`) | 96 s alone at load1 < 25 (n=8); intercept 100.8 | ~3.1–4 cores | **~340** (250–450) | [E/T] wall × cores; the interference fit gives a draw of 4·T0/C ≈ 3.9–4.5 cores |
| pre-push full suite (`pnpm test:unit` = `vitest run`, ~390 files, maxWorkers 4, under `cc-sem general`) | push_s 117 s alone at load1 < 25 (n=5), about 8 s of which is hook, docs gate and network | ~3.1–4 cores | **~340** (260–450) | [E] the verifier's own vitest output (below) |
| **clean code-land round (one pass)** | | | **≈ 730** (545–965) | |
| **per LANDED code land, as measured (7-day window)** | 2.48 tsc runs, 2.39 land-suites and 2.10 pre-push suites per landed code land (31 landed out of 58 code attempts) | | **≈ 1,650** (1,230–2,180) | [E] multipliers; [T] per-run CPU |

**Direct CPU evidence for the full suite [E]:** `~/.reso/verify-logs/*/test-unit.log` holds 10 postland-verify runs (3 forks, 381–391 files). Vitest's `Duration (… setup, import, tests, environment)` are per-file phase times summed across workers, so they measure busy worker-seconds.
- The ratio of busy worker-seconds to wall time is 2.61–2.73 in all 10 runs, i.e. 87–91 % utilisation of 3 forks.
- Least-contended runs:
  - 258 worker-s (98.96 s wall, 09-07)
  - 337 worker-s (125.6 s wall, 09-14 00:34 CDT, load1 18, no other suites)
- More contended runs reach 423–661 worker-s, because the phase times count time spent waiting inside the worker.
- Add the main process (6–11 CPU-s over about 137 s in the snapshot) and about 390 fork/boot costs [T ~20–40 CPU-s]. **That gives about 300–390 CPU-s per full suite.**

**Why the union suite costs about as much as the full suite [E + T]:**
- **Wall times match.** Union alone takes 96–101 s; the full suite alone takes about 108 s.
- **The interference coefficients match.** A concurrent union suite costs the pre-push suite 49 s, which is more than another general-lane suite costs it.
- **Likely cause [T]:** the always-run set is 159 specs, including 42 `scripts/__tests__` that spawn many processes and 28 replicache action tests. That set probably contains most of the suite's heavy files, so running the selected half of the files saves little CPU.

**Isolation cost [E]:** in the snapshot, 10 vitest workers had etime 0–5 s under suite main processes aged 137–138 s. So each test file runs in a **fresh forked process**. `vitest.config.ts` sets no `pool` or `isolate`, so this is Vitest 4's forks+isolate default [T]. Worker CPU therefore dies with the worker, which is why ps cumulative CPU cannot measure suite cost.

**Implied maximum if verification were the only work [T]:**
- Capacity: C = 8.6 P-equivalents (8 P + 2 E × ~0.3) gives 31,000 CPU-s/h; C = 10 gives 36,000.

| basis | lands/h |
|---|---|
| clean rounds | **42–49/h** (range 32–66 over the CPU-s range) |
| landed code lands at today's 2.4× retry multiplier | **19–22/h** |

- **Observed demand is far below this [E].** 31 landed code lands in 7 days (5 per day on average); the peak UTC hour had 5 (09-23T03).
- Suite wall-sum over 7 days: 3.3 h land-time plus 3.4 h pre-push. That is about 21–27 core-hours, **about 1.5 % of the box's week**. The load.jsonl mean of 0.045 suites running gives 0.14–0.18 cores.
- In the 09-22 18:30–20:30Z peak there were 1.38 suites running on average, which is **about 50–64 % of the P-equivalent capacity**.

---

## (d) What the load is made of right now (one read-only ps snapshot)

**Command:** `ps -Aww -o pid=,ppid=,pcpu=,rss=,etime=,time=,state=,args=`, aggregated in Python. This is the brief's column set plus ppid, time, state and args, which were needed to tell vitest, tsc and next apart; they are all `node` by comm. It was one call, with no signals.

**Totals:** 2,183 processes; **Σ%CPU = 621 (6.2 of 10 cores)**; **106 in state R**; 623 `<defunct>` (zombie) processes.

| class | procs | %CPU | share of measured CPU | in R | note |
|---|---|---|---|---|---|
| **vitest workers + main** | 10 + 8 | **231.0** | **37.2 %** | 3 (4 workers in `U`, uninterruptible wait) | 2 suites in flight: ship-land union (label `ship-land:sec-w6-lead`) and a pre-push full suite |
| claude agents | 28 | 146.1 | 23.5 % | 3 | one at 85.5 %, then 25.3 %, 18.2 %; the rest ≤ 7 % |
| fseventsd | 1 | 100.6 | 16.2 % | 1 | 35,846 CPU-s cumulative over 6 d 8 h uptime, so pinned now; driven by file churn [T] |
| node, other (`eslint.js`) | 17 | 26.3 | 4.2 % | 1 | |
| git | 2 | 24.0 | 3.9 % | 2 | |
| **tsc** | 1 | **19.1** | **3.1 %** | 1 | ship-land typecheck |
| shells (zsh/bash/sh) | 214 | 22.5 | 3.6 % | 15 | |
| python | 12 | 12.7 | 2.0 % | 4 | |
| macOS daemons (WindowServer, syspolicyd, spotlight, spindump, 600+ others) | ~627 | 16.6 | 2.7 % | ~23 | |
| desktop tools (Hammerspoon, kitty, Cursor, Karabiner) | ~16 | 13.5 | 2.2 % | 1 | |
| monitors and census (ps, top, find, sleep) | ~30 | 8.1 | 1.3 % | 5 | includes sibling agents' ps snapshots |
| **Google Chrome helpers** | 71 | **0.1** | 0 % | **34** | **runnable but not running: starved** |
| iOS Simulator (`launchd_sim` tree) | 283 | 0.2 | 0 % | 0 | **25.3 GB RSS** |
| next dev / next-server | 1 | 0.0 | 0 | 0 | idle (`SN`); no next build or playwright/chromium was running |

**What the snapshot shows [E unless marked]:**
- **Verification (vitest + tsc) is ≥ 40 % of measured CPU; with land-path git and shells it is about 45 %.** This is a lower bound. `pcpu` is a decaying average, so the per-file forks (etime 0–5 s) are under-counted.
- **Verification is under about 10 % of load1 [E/T].** At a footprint of about 7–11 load1 per suite, two suites plus tsc make about 15–23 of the 232.
  - The footprint comes from load1 changes after cc-sem slot events: releases drop load1 by 7.1 ± 1.5 at +60 s and 6.1 ± 2.5 at +120 s (n=62–99), and R-state processes by 12.5 ± 2.5.
  - Acquire events show no rise, because an acquire coincides with the same land's tsc finishing.
- **Load1 overstates CPU demand.** 34 R-state processes at about 0 % CPU (Chrome helpers), 6.2 cores measured, and slopes 20× smaller than equal-share scheduling predicts all point the same way.
  - Mechanism [T]: macOS counts runnable threads at every QoS in load1, but schedules by QoS and priority. Low-QoS threads can sit runnable indefinitely, especially on the 2 E-cores.
- **Memory is not the driver right now.** One extra read-only `sysctl` returned `vm.memory_pressure: 0`, `kern.memorystatus_level: 73`, swap 1.28 of 2 GB used.
- **Attribution caveat:** walking ancestors for the string `ship-land` also matched it inside agent prompts, which wrongly attributed 5 claude processes (116 %) and an eslint run to the land gate. The class table above does not use that walk. The pre-push attribution (4 workers + main, 93 %) is consistent.
- **Timing caveat:** this snapshot is from the 9-day load extreme. Composition at typical load (p50 13) was not observed.

---

## (e) Capacity: at what concurrency does added verification stop adding throughput?

**Model (fitted in §b) [E]:** T_suite(n) = T1(L) + c·(n−1).
- c ≈ 45–49 s for each other concurrent suite.
- T1(L) is the suite's time when running alone: union 100.8 + 0.20·L, pre-push 107.8 + 0.30·L.
- Suite throughput X(n) = n·3600 / T(n) [T].

**Suite level, T1 = 115 s (load1 ≈ 50), c = 47 s:**

| concurrent suites n | per-suite wall | suites/h | marginal gain |
|---|---|---|---|
| 1 | 115 s | 31.3 | — |
| 2 | 162 s | 44.4 | **+42 %** |
| 3 | 209 s | 51.7 | +16 % |
| 4 (current cap: 1 reso-land + 3 general) | 256 s | 56.3 | +9 % |
| 5 | 303 s | 59.4 | +5 % |
| ∞ (whole box to verification) | — | 76.6 = 3600/c | — |

**Land-round level** (tsc + union + pre-push; R1 = 264 s at load1 50; each other concurrent land costs about 94 s because it is inside a suite 88 % of the time):

| lands in verify | 1 | 2 | 3 | 4 | ∞ |
|---|---|---|---|---|---|
| rounds/h | 13.6 | 20.1 | 23.9 | 26.4 | 38.5 |

**Statement:**
- **The box sustains about 2 concurrent verification suites (about 2 lands inside their verify window) before added verification buys throughput at a worse-than-proportional latency cost.**
  - Kleinrock optimum n* = T1/c − 1 = **1.5** at load1 50. It rises to **2.3–2.7** at load1 250, because ambient load raises T1.
  - That is where 2 suites × 4 workers fill the 8 P-cores [T].
- **Past about 4 concurrent suites, each addition adds under 10 %.**
- **The asymptote of about 77 suites/h (about 38–49 clean rounds/h, about 16–20 landed code lands/h at the 2.4× multiplier) is reachable only by starving the ~28 agent sessions.**
- **Admission binds first.** cc-sem's `reso-land` K=1 serialises the union stage at 3600/T_union. At about one overlapping pre-push suite that is **~23 rounds/h** (18.5/h at load1 250; 32/h if nothing overlaps). At the measured 2.39 land-suite runs per landed code land, that is **≈ 10 landed code lands/h (8–14)**. That is about half the box (23 × 730 CPU-s ≈ 4.7 cores).
- **The operating point is about right; the waste is the problem.** K=1 on `reso-land` is near the knee. `general` K=3 can push total concurrency to 4, past the knee. The larger lever is the **2.4× retry multiplier**: 14 push-rejected, 8 statics-red, 3 push-timeout, 3 unadmitted and 1 cas-exhausted out of 58 code attempts in 7 days. It doubles CPU per landed code land.

---

## cc-sem configuration and queueing (key question 4)

**Configuration on origin/main `scripts/cc-sem.sh` [E]:**

| class | slots | wait bound | env overrides |
|---|---|---|---|
| `reso-land` | **1** (`:88`) | 300 s (`:97`) | `CC_SEM_K_RESO_LAND`, `CC_SEM_WAIT_RESO_LAND` |
| `reso-verify` | **1** (`:89`) | 1800 s (`:98`) | `CC_SEM_K_RESO_VERIFY`, `CC_SEM_WAIT_RESO_VERIFY` |
| `general` | **3** (`:90`) | 900 s | `CC_SEM_K_GENERAL`, `CC_SEM_WAIT_GENERAL` |
| `selftest-*` | 2 (`:91`) | 900 s | `CC_SEM_K_SELFTEST` |

- **Waiting and refusal:** a queued job polls every 1 s (`:272`). If the wait bound runs out, cc-sem refuses with exit 10 (`:268`).
- **Memory floor is inert.** `memory_ok "${floor}" || true` (`:271`) is only evaluated while the job is already queued, and its result is discarded.
- **What each class covers:**
  - `reso-land`: only ship-land's land-time suite (`ship-land.sh:548`).
  - `general`: `test:unit`, `build`, `test:e2e`, `design:gate` (`package.json:126` and neighbours).
  - Not admitted: tsc, reconcile and push.
- **No overrides in this shell's env.**
- **Limits held in practice [E, load.jsonl]:**
  - `reso-land` max holders 1; `general` max 3 (23 samples, ~4 min in 9 days); `reso-verify` never held.
  - Holder labels: `general` is almost all `cc-sem.sh:general` (pre-push and ad-hoc `test:unit`; 2,423 samples), plus `w0-m7:design:gate` (28).

**Queueing is real and is driven by concurrent lands [E]:**

| other land attempts in flight at admission | n | sem_wait p50 | sem_wait p90 |
|---|---|---|---|
| 0 | 33 | 0 | 0 |
| 1 | 19 | 0 | 137 s |
| 2 | 20 | 97 s | 190 s |
| 3+ | 9 | 169 s | 268 s (refusals counted as 300) |

- **By load band** (load1_entry): < 50 → 4/25 rounds waited (p90 43 s); 50–150 → 13/25 (p90 142 s, max 267); ≥ 150 → 14/27 (p50 32, p90 192, max 260).
- **Refusals:** 3 `presubmit-unadmitted` refusals (hit the 300 s bound) at 09-22T19:14Z and 19:16Z (load1 242 and 235) and at 09-23T02:52Z (load1 143).
- **Utilisation:** `reso-land` was held 1.2 % of all samples. Maximum rolling 1-hour utilisation was 0.80 (hour ending 09-23T04:04Z); utilisation exceeded 0.5 in 0.9 % of hour-windows. In the 09-22 18:30–20:30Z peak it was 0.54. **The lane saturates only in bursts, and the waits look like M/D/1 queueing at ρ ≈ 0.5 with clustered arrivals [T].**

---

## Alternatives considered and ruled out

- **Load1 alone as the inflation driver.** Rejected: R² is 0.19–0.56, rising to 0.73–0.84 once concurrent suites are added, and the load term is not significant below load1 100.
- **Equal-share scheduling over load1** (T ∝ L/C). Rejected: it predicts slopes of 2.4 s/load (tsc) and ~12 s/load (suites), 10–40× the observed values.
- **`runnable_entry` as the regressor.** Rejected: worse fit (tsc R² 0.15).
- **Multiplicative (log-linear) model.** R² is no better (tsc 0.16, union 0.37, push 0.69) and the binned curves look linear, so the linear model is kept.
- **ps cumulative `time` to measure suite CPU.** Rejected: per-file forks die within seconds, so their CPU is lost to ps.
- **Measuring each suite's load footprint from acquire events.** Rejected: an acquire coincides with the same land's tsc finishing. Release events were used instead.
- **Attributing processes by walking ps ancestors.** Rejected: it matched `ship-land` inside agent prompts. Class-level shares were reported instead.

## Adversarial pass: what I checked and what is still open

- **Checked: could the concurrency effect just be a busy-period confound?** No. Split by ambient load it is 48 ± 8 s at load < 100 and 42 ± 7 s at load ≥ 100, and the raw means show the same 101 s vs 155 s at load1 < 60.
- **Checked: did the push regression drop pushes rejected by the remote?** Pushes where the hook passed and the remote rejected (18 non-fast-forward, 7 cannot-lock) completed the full suite and are included (n = 58, not 31). Hook failures and timeouts are excluded.
- **Checked: did the window-load fit drop short stages?** Stages with no load sample inside their window use the nearest sample within 30 s. The first pass had dropped them, which biased the tsc intercept upward (28.6 instead of 25.3).
- **Checked: is memory pressure the driver?** Not at snapshot time (pressure 0, level 73).
- **Open: CPU utilisation (idle %) is not recorded anywhere.** The 6.2-core figure is a lower bound. **This instrument gap blocks a direct measurement of CPU saturation.**
- **Open: union-suite CPU has no direct measurement.** Land suites' vitest `Duration` lines are not persisted. The estimate relies on matching wall times and the interference fit.
- **Open: `push_s` mixes several things.** It includes the `general` wait, the suite, hook overhead and the network. No `general` wait is logged per land.
- **Open: tsc cache state is unlogged,** which caps the tsc fit at R² ≈ 0.2.
- **Open: n = 10 for land-time full suites.** Their concurrency term (12.9 ± 25.6) is not identified.
- **Open: nine days of history, dominated by three burst days** (09-20, 09-22, 09-23). The single ps snapshot was taken at the 9-day load extreme.
- **Open: E-core/P-core split** cannot be identified without per-cluster data; see §(b).

## Instrument additions that would close these gaps

These are for the lead to weigh; nothing was changed.

1. Record CPU idle %, or user/sys/idle ticks from `host_processor_info`, in `load.jsonl`.
2. Persist vitest's `Duration (…)` line in the land.log round (as `suite_worker_s`). That is a direct worker-seconds proxy for CPU per suite.
3. Add the pre-push `general` wait (`CC_SEM_WAIT_S`) to the round.
4. Log `tsc_warm` (whether tsbuildinfo existed and how old it was).
