# Axis 01 — Session-AGE memory growth, and the corrected memory wall

Measured 2026-08-09 23:13–23:30 PDT on the live M1 Max 64 GiB box (`hw.memsize 68719476736`,
`hw.model MacBookPro18,2`, macOS 15.6.1). Every number below is a live read taken this session
unless marked `[D]` (repo doc) or `[I]` (inference). Instrument = `vmmap -summary <pid>` *Physical
footprint*, cross-checked against `top -l1 -stats pid,mem` (agreed to <1 MB on 4/4 processes:
98361 read 273.7 M vs 274 M). `ps` RSS is NOT used for any conclusion — it read 916 MB against a
273.7 MB footprint on the same pid, a 3.3× shared-library double-count.

Scope: the DYNAMIC curve only — growth over session lifetime, equilibrium under real recycle
cadence, and the denominator arithmetic that follows. The at-rest compressor question is a sibling
axis and is not answered here (one dynamic fact bearing on it is recorded in §3).

---

## 0 · Verdict

> **Session AGE does not break the 150-resident budget. The budget breaks anyway — on the CONSTANT
> and on a BURST term that the age hypothesis was hiding.**
>
> 1. **Age slope is bounded at ≤9.5 MB/h (95% upper), and the fleet's equilibrium resident age is
>    3.69 h** ⇒ the age term contributes **≤35 MB/session, ~13%** of a session's footprint. It cannot
>    move a 150-session budget. §1–§2.
> 2. **The per-session constant is wrong by 1.47×.** `CONCURRENCY_PROGRAM.md §S6.2` budgets
>    **232 MB**; measured in-situ marginal is **340 MB/session** (paired within-box differential,
>    n=1,194 transitions). ⇒ **150 × 340 MB = 51.0 GB against 44.0 GB usable — over by 7.0 GB.
>    Binds at N=132**, and at **N=103** in today's actual desktop state. §4–§5.
> 3. **A burst term nobody budgeted.** 54 distinct `claude.exe` processes exceeded 4 GB in 11 days,
>    max **40.96 GB**, ramping at **916–7,909 MB/min**. Rate **0.0204 per session-hour** ⇒ at 150
>    resident, **3.1 events/hour**, each able to consume the entire remaining headroom. §6.

---

## 1 · Footprint vs age — the measured table

All nine live Claude sessions, identified by **argv[0] command position** (`awk '$7 ~ /\/claude$/'`
over `ps -axo pid=,lstart=,command=`), never by substring. All nine are
`/Users/chrisren/.claude-220/node_modules/.bin/claude`; the running image reports as `claude.exe` —
a **Bun**-compiled binary (a 182.5 MB `__BUN` region), not Node.

| pid | launched | age (h) | ps RSS (MB) | **phys_footprint (MB)** | peak (MB) | note |
|---|---|---|---|---|---|---|
| 56864 | 04:25:46 | **18.92** | 844 | **373.0** → 400 → 406 | 425.6 | wave lead — Fable, `--resume`, 17 descendants, actively driving a 13-subagent wave |
| 43530 | 13:41:39 | 9.62 | 842 | 250.1 | 320.2 | **EXITED** mid-measurement (natural churn) |
| 98361 | 16:45:36 | 6.59 | 916 | **273.7** (both sweeps, Δ=0.0) | 293.3 | |
| 19485 | 22:01:24 | 1.33 | 748 | **222.0** | 239.9 | sibling axis `m3-fleet-footprint` |
| 49853 | 22:14:07 | 1.11 | 760 | **243.9** | 301.1 | sibling axis `m6-account-facts` |
| 58413 | 22:48:41 | 0.54 | 801 | **251.2** | 283.6 | |
| 99699 | 22:53:08 | 0.46 | 891 | **279.3** | **402.6** | 0.46 h old, peaked at 402.6 MB |
| 4371 | 22:56:36 | 0.41 | 719 | **234.9** | 248.7 | |
| 1083 | 23:11:57 | 0.15 | 676 | **250.1** | **307.0** | 9 min old, peaked at 307.0 MB |

**mean 266.0 MB · median 250.6 MB · n=8** (43530 exited before its second read).

### 1.1 The fit — and the honest problem with it

| model | slope | se | t | R² | 95% CI |
|---|---|---|---|---|---|
| OLS all n=8 | **+6.67 MB/h** | 1.16 | 5.76 | 0.847 | 3.8 … 9.5 |
| OLS dropping the wave lead, n=7 | **+3.61 MB/h** | 3.64 | 0.99 | 0.165 | −5.7 … 13.0 |

**The entire slope is one point.** 56864 (18.92 h) is the only observation above 6.6 h and is also
the only session running a research wave. Three independent measurements say its elevation is
WORKLOAD, not age:

- **It moved 260.0 → 355 → 373.0 → 400 → 406 MB inside 8 minutes** of my own sampling
  (`vmmap` 23:13:52 → `top` 23:16 → `vmmap` 23:20:58 → `top` 23:26 → 23:30). That is
  **+1,095 MB/h instantaneous** — 164× the fitted "age" slope. An age process cannot do that.
- **Its peak moved 361.3 → 425.6 MB in those same 7 minutes.** The high-water mark was set *now*,
  not hours ago.
- **The other seven sessions are flat.** Longitudinal sampler (0.2 Hz × 50 s, `top -l1 -stats
  pid,mem`, 10 samples/pid): 19485 `222 222 222 222 222 222 222 222 222 222`; 98361 `274 ×10`;
  49853 `243 ×10`; 4371 `231…232`; 58413 `250…251`; 1083 `245…246`; 99699 `311…312`. Only 56864
  moved (`360 355 353 354 359 368 357 357 355 352` — oscillating, **no trend**).

**Both readings are reported because I cannot decide between them with n=1 at high age.** It does
not matter: §2 shows the budget is insensitive to the difference.

### 1.2 The `[D]` "216 MB fresh → 548 MB at 26 h" reading is a workload excursion, not a curve

`session-capacity-ceiling-2026-08-09.md §2.4` reports *"216 MB fresh, median 232, mean 283, **max 548
at 26 h**"*. The 548 is the **max of 19**, and the co-occurrence with 26 h is not evidence of a curve:

- Measured today, a **0.46 h-old** session peaked at **402.6 MB** and a **0.15 h-old** session at
  **307.0 MB** — both inside the same band, at ~1/60th the age.
- Taking the doc's own implied slope (548−216)/26 = **12.8 MB/h** as a prediction: an 18.92 h
  session should read **458 MB**. It reads **373 MB** — 85 MB under, and that reading is already
  inflated by the wave-lead workload.

---

## 2 · Equilibrium under the ACTUAL recycle cadence

Session lifetimes, `st_birthtime → st_mtime` over 913 transcript `.jsonl` files written in the last
14 days across `~/.claude`, `~/.claude-tertiary`, `~/.claude-220`:

| p10 | p25 | **p50** | p75 | p90 | p95 | p99 | max | mean |
|---|---|---|---|---|---|---|---|---|
| 0.01 h | 0.16 h | **0.62 h** | 2.19 h | 6.41 h | 11.58 h | 39.00 h | 311.6 h | 3.19 h |

| band | 0–0.5 h | 0.5–1 | 1–2 | 2–4 | 4–8 | 8–16 | 16–24 | 24–48 | >48 |
|---|---|---|---|---|---|---|---|---|---|
| share | **45.3%** | 14.2% | 12.6% | 12.4% | 7.1% | 5.3% | 1.4% | 0.5% | 1.1% |

**92.9% of sessions never reach 8 h. 3.0% exceed 16 h.** The fleet recycles on context-fill exactly
as § Context Stewardship prescribes, and the cadence keeps sessions young.

**Equilibrium mean RESIDENT age — three estimates, and why the small one is right:**

| estimate | value | status |
|---|---|---|
| length-biased `E[L²]/(2E[L])` over all transcripts | 34.56 h | **rejected** |
| same, with the 10 files >48 h (1.1%) truncated | 4.97 h | plausible |
| **direct: mean age of the 8 live processes** | **3.69 h** (median 0.83 h) | **used** |

The 34.56 h figure is an artifact and must not be quoted: **a `--resume` appends to the SAME
transcript file with a FRESH process**, so transcript span over-states process age without bound
(two of the nine live sessions carry `--resume`; the 311.6 h file is a conversation, not a process).
Memory is held by the process. The direct measurement (3.69 h) and the transcript p50 (0.62 h vs
live median 0.83 h) agree, which is the cross-check.

**Equilibrium footprint** = 241.4 + 6.67 × 3.69 = **266 MB** — identical to the directly measured
mean of **266.0 MB**. At the *upper* 95% slope bound (9.5 MB/h) the age term is **35 MB**; at the
lead-excluded slope it is **13 MB**.

> ⇒ **Age contributes 13–35 MB of a ~266 MB session. Even at the pessimistic bound this is 13%, and
> it is smaller than the 108 MB spread the SAME-AGE sessions already show (222.0 → 373.0 MB).**

---

## 3 · What actually grows — vmmap region attribution

Dirty-size per region class, `vmmap -summary`, MB. Physical footprint ≈ TOTAL DIRTY (98361: 273.7
dirty vs 273.7 footprint, exact).

| pid | age h | **foot** | **IOAccelerator** | JS JIT | JS Gigacage | MALLOC (all zones) | Stack | other |
|---|---|---|---|---|---|---|---|---|
| 56864 | 18.88 | 377.1 | **311.1 (82%)** | 30.3 | 7.3 | 22.1 | 2.9 | 3.4 |
| 98361 | 6.55 | 273.7 | **178.0 (65%)** | 30.0 | 6.6 | 52.5 | 2.4 | 4.2 |
| 19485 | 1.29 | 222.0 | **163.1 (73%)** | 25.4 | 6.6 | 20.5 | 2.9 | 3.5 |
| 49853 | 1.08 | 243.2 | **181.9 (75%)** | 26.3 | 6.7 | 22.0 | 2.9 | 3.4 |
| 58413 | 0.50 | 250.3 | **190.8 (76%)** | 27.1 | 6.7 | 19.5 | 2.9 | 3.3 |
| 99699 | 0.42 | 314.2 | **193.5 (62%)** | 24.4 | 6.7 | **83.1** | 3.0 | 3.5 |
| 4371 | 0.37 | 234.6 | **174.4 (74%)** | 25.2 | 6.6 | 22.1 | 2.8 | 3.5 |
| 1083 | 0.11 | 247.2 | **200.3 (81%)** | 19.5 | 6.7 | 14.6 | 2.8 | 3.3 |

**The dominant term is `IOAccelerator` — 62–82% of every session's footprint — not the JS heap.**

- It is genuine **GPU-aperture memory**: five `128.0M` slabs at `0x4ef1b000000…`, `SM=PRV`,
  `rw-/rwx`, plus a `384.0M` reserved tail. `IOAccelerator.framework` is mapped, alongside
  CoreGraphics / CoreImage / CoreVideo / AppKit — Bun's JavaScriptCore drags the graphics stack into
  a process that only draws a TUI.
- **The JS heap is small and age-flat**: JS JIT 19.5–30.3 MB, Gigacage 6.6–7.3 MB across a 170×
  age range. `MALLOC` is 14.6–83.1 MB and tracks activity, not age (the 83.1 MB is the 0.42 h
  session).
- **IOAccelerator is NOT wired** — this was the alarming hypothesis and it is refuted in §4.2.
  It is ordinary pageable/compressible dirty memory. *(Whether the compressor handles it cheaply is
  the sibling at-rest axis; not answered here.)*
- Age-flat across the clean range: **200.3 MB at 0.11 h vs 178.0 MB at 6.55 h.**

---

## 4 · The true denominator

### 4.1 Non-Claude baseline — measured, named

Full-box census, `top -l1 -stats pid,mem,command`, 898 processes, **22.58 GB total phys_footprint**:

| command | n | MB | in the 150-budget's "browsers CLOSED" world? |
|---|---|---|---|
| Browser (Dia + Chrome helpers) | 33 | **4,459** | removed |
| node (Next dev servers in worktrees) | 14 | **4,319** | work artifact, removable |
| **claude.exe** | **8** | **2,129** | this is the numerator |
| WindowServer | 1 | 1,642 | stays |
| Cursor | 18 | 1,601 | stays |
| kitty | 1 | 1,527 | stays (shared by every pane) |
| Google (Chrome) | 8 | 589 | removed |
| Dia (main) | 1 | 371 | removed |
| mds_stores / mediaanalysisd / esbuild / Creative | 5 | 723 | stays |
| bash (62) + zsh (20) — hooks, watchdogs, wrappers | 82 | 249 | scales with sessions |
| remainder (~740 procs) | — | ~3,000 | stays |

Non-Claude today = **20.45 GB**. Browsers closed = **15.03 GB**. Browsers closed *and* dev servers
stopped = **10.7 GB** — which is where §S6.2's *"≈10 GB, browsers CLOSED"* `[D]` comes from. That
assumption is defensible **only** in that doubly-idealised state.

### 4.2 Wired — measured, and it does NOT scale with sessions

11,438 samples over 11 days (`~/.claude/logs/capacity-alarm.jsonl`, 60 s cadence,
2026-07-30 → 2026-08-10): `wired_gb` min 2.33 · **p50 6.30** · mean 6.20 · p95 8.51 · max 12.17.

The cross-sectional regression is a **trap** and I fell into it before catching it:

| instrument | wired slope | verdict |
|---|---|---|
| cross-sectional OLS, all 11 days | +98 ± 4 MB/session (R²=0.15) | **confounded** |
| cross-sectional OLS, last 3 days | +173 ± 6 MB/session (R²=0.49) | **confounded** |
| **paired adjacent-sample differential** (n=1,194 transitions ≤180 s apart) | **−0.9 MB/session** | **used** |

The cross-section says session memory is wired; the paired within-box differential says it is not.
The differential wins — it holds the box constant and only lets the session count move. Session
count and wired memory both rise through the working day (browsers, GPU compositing), which is the
whole confound. **Verified symmetrically:** ΔS=+1 → mean ΔWIRED **+24.7 MB**, ΔS=−1 → **+1.8 MB**,
median **+0.0 MB** in both directions.

> ⇒ **The 27 GB-of-wired-GPU-memory catastrophe is NOT real.** Wired is a fixed ~6.3 GB term.

### 4.3 The per-session constant — 340 MB, not 232 MB

Same paired differential, on `active_gb`:

| ΔS | n | mean ΔACTIVE | median | implied MB/session |
|---|---|---|---|---|
| −3 | 36 | −1,681.9 MB | −1,070.1 | 560 |
| −2 | 72 | −653.9 | −445.4 | 327 |
| −1 | 476 | −365.2 | −250.9 | 365 |
| **0** | **9,866** | **+14.1** | **+10.2** | — (box drift, all causes) |
| +1 | 488 | +293.0 | +358.4 | 293 |
| +2 | 105 | +722.4 | +696.3 | 361 |
| +3 | 45 | +543.2 | +911.4 | 181 |
| **through-origin pooled slope** | 1,194 | — | — | **340.5 MB/session** |

Consistent in **both directions** and at every |ΔS| — 293–365 MB. The gap to the 269 MB mean
`claude.exe` self-footprint is the **satellite cost**: the pane's shell, `lead-crash-watchdog.sh`
(1:1 with sessions, `SessionStart`), `cc-await-ping`, and transient tool forks. Direct subtree walk
corroborates: descendant overhead over `claude.exe` self is +2.5 to +93 MB for ordinary sessions.

*Caveat, named:* a subtree walk that includes the **ancestor** chain double-counts `kitty`
(1,527 MB shared by every pane) — it inflates to a nonsense 1,660 MB/session. Not used. The paired
differential is immune to this because kitty is already resident when session N+1 arrives.

---

## 5 · Corrected budget arithmetic — binds-at-N

`usable = 64 GiB − wired − non-Claude process footprint − file-cache floor (3 GB)`

| box state | non-Claude | wired | **usable** | N@232 `[D]` | N@269 (self) | **N@340 (marginal)** | 150 × 340 = 51.0 GB |
|---|---|---|---|---|---|---|---|
| browsers closed, no dev servers | 10.7 | 6.3 | **44.0 GB** | 194 | 167 | **132** | **OVER by 7.0 GB** |
| browsers closed, dev servers up | 15.0 | 6.3 | **39.7 GB** | 175 | 151 | **119** | OVER by 11.3 GB |
| **today's actual state** | 20.45 | 6.3 | **34.2 GB** | 151 | 130 | **103** | OVER by 16.8 GB |
| optimistic (wired p25, minimal desktop) | 10.7 | 4.7 | **46.6 GB** | 205 | 177 | **140** | OVER by 4.4 GB |

§S6.2 `[D]` reads `150 × 232 MB ≈ 35 GB` … `remaining for bursts ≈ 19 GB`. Corrected:

```
150 × 340 MB              = 51.0 GB      (was 35 GB — the constant, not the age, is the error)
macOS + render + baseline = 17.0 GB      (wired 6.3 + non-Claude 10.7, browsers CLOSED)
                            -------
                            68.0 GB      against 64 GiB physical
remaining for bursts      = NEGATIVE 4.0 GB   (was "≈19 GB")
```

> **Binds at N = 132** in the idealised state; **N = 103** as the box actually sits tonight. Neither
> number leaves any burst headroom, and §S6.2's own conclusion — *"at 150 resident there is no room
> for even ONE unbounded cold compile"* — is right for the wrong reason and understates it by 23 GB.

**The shipping alarm carries a third, differently-wrong constant.** `capacity-alarm.sh:1065`
`PER_MB="${CC_CAP_PER_SESSION_MB:-636}"` — an RSS-derived figure, emitted in every one of the 11,438
rows as `per_session_mb_est: 636` / `est_room_sessions: 57`. Its own header (`:1040-1055`) labels it
a deliberate **upper bound** so `est_room_sessions` reads as a floor, and it is never used in the
verdict — so this is a documentation hazard, not a live gating defect. Three constants are now in
circulation (232 `[D]`, 636 shipped, 340 measured) and none of the three agrees with another.

---

## 6 · The term the age hypothesis was hiding — runaway bursts

`top_procs` in the capacity log records the box's top-3 processes by footprint every 60 s. The
visibility floor is low (3rd-place p10 = 447 MB, min 273 MB), so for events above ~2 GB this is
close to a **full census**, not a sample.

- **54 distinct `claude.exe` processes exceeded 4 GB** in 11 days; 135 samples >2 GB; 120 >4 GB.
- **All-time max: 40,960 MB (40.0 GiB), pid 80508, 2026-08-02T20:06:34Z, 21 sessions live.**
  Corroborated by the independent `max_proc_gb: 40.0` field and by `swap_used_mb` going
  `0 → 424.62 → 2581.06` across the same four samples, with the verdict escalating `WARN → ALARM`.
  Not a parsing artifact.
- **Ramp rates are 916–7,909 MB/min**, median visible span **1.1 minutes**:

| pid | samples | span (min) | min MB | max MB | **MB/min** |
|---|---|---|---|---|---|
| 80508 | 10 | 12.4 | 2,827 | **40,960** | 3,063 |
| 99795 | 9 | 13.0 | 3,501 | 32,768 | 2,254 |
| 85373 | 5 | 5.8 | 6,371 | 29,696 | 4,033 |
| 15594 | 2 | 1.2 | 8,810 | 18,432 | **7,909** |
| 21926 | 3 | 2.2 | 4,539 | 18,432 | 6,315 |

**This settles the age question from the other side.** Growth in this binary is burst-shaped and
minutes-scale — 4-to-5 orders of magnitude faster than any age slope. Eleven days of 60-second
sampling contain **no slow-accumulation signature at all**.

**Rate, and what it does at 150:** 2,641 observed session-hours (Σ sessions / 60) ⇒
**0.0204 events per session-hour = 1 per 49 session-hours.**

| resident sessions | events/hour | mean gap |
|---|---|---|
| 14 (today's mean) | 0.29 | 3.5 h |
| 46 (all-time max observed) | 0.94 | 64 min |
| **150 (design point)** | **3.06** | **20 min** |

Onsets occur at a median of **20 live sessions** against a fleet median of 13 — the rate is if
anything *super*-linear in session count, so 3.06/h is a floor. Against §5's negative burst headroom
this is the binding failure mode, and it already bites: **46.2% of all samples have swap in use**
(p90 2,120 MB, p99 8,590 MB, max **30,268 MB**).

---

## 7 · Adversarial self-pass

| challenge | resolution |
|---|---|
| *"You dropped your only high-age point because it disagreed."* | Both fits are reported (§1.1). The point is retained in every table. It is flagged because three independent measurements — an 8-minute +146 MB swing, a peak that moved *during* measurement, and 17 live descendants — identify its workload, and because §6 shows minutes-scale bursts are this binary's actual growth mode. **The conclusion does not need the drop:** even the significant +6.67 MB/h slope yields only +25 MB at the measured 3.69 h equilibrium age. |
| *"n=8 cannot see 26 h+; onset may be later."* | True and named. Bounded instead: transcript p99 = 39 h, only 3.0% of sessions exceed 16 h and 1.1% exceed 48 h. An age effect confined beyond 20 h reaches ≤3% of the fleet. The 11-day `top_procs` census independently finds no slow-ramp process of any age. |
| *"`top`/`vmmap` MEM might over-count a Bun process with 3.9 GB of reserved Gigacage."* | Reserved VM is excluded — `vmmap` prints `TOTAL, minus reserved VM space` separately, and footprint tracks TOTAL **DIRTY** (273.7 = 273.7 on 98361). The 40 GB excursion is corroborated by concurrent swap growth and an independent `max_proc_gb` field. |
| *"Wired scales with sessions ⇒ 27 GB wired at 150."* | **I asserted this and then refuted my own claim** (§4.2). Cross-sectional slope (+98…+173 MB/session) is confounded; the paired differential reads −0.9 MB/session. Session memory is pageable. |
| *"Transcript spans give the age distribution."* | They do not — `--resume` reuses the file with a fresh process, so the length-biased estimate inflates to 34.56 h against a directly measured 3.69 h (§2). Quoting the 34.56 would have manufactured an age effect out of an instrument defect. |
| *"340 MB/session includes a startup burst, so it over-states residency."* | Partly — but it is symmetric on **departure** (ΔS=−1 → −365 MB), which a pure startup burst cannot be. Reported as the marginal in-situ cost, with the 269 MB self-footprint given alongside so the budget can be read either way (N=132 vs N=167). |
| *"Two sibling measurement sessions are in your sample."* | Yes: 19485 (`m3-fleet-footprint`) and 49853 (`m6-account-facts`) — the two *lowest* footprints in the sample (222.0, 243.9). They do not inflate anything. Nothing was started, stopped, or configured; sampling was 0.2 Hz for 50 s plus two `vmmap` sweeps. |

## 8 · Uncertainties, named

1. **n=1 above 6.6 h.** The 6.67 vs 3.61 MB/h fork is unresolved by measurement. Both bounds are
   budget-immaterial; a clean resolution needs a session parked idle for 24 h.
2. **What triggers the 4–40 GB bursts is unknown** — this axis established their existence, rate,
   and shape only. Naming the trigger is the highest-value follow-on and is not answerable from
   `top_procs` (top-3 only, no argv, no cwd).
3. **The paired 340 MB/session assumes session arrivals are otherwise independent of box state.**
   Symmetric departure evidence supports it; a controlled N-up/N-down sweep would confirm it.
4. **`file-cache floor = 3 GB` in §5 is a judgement, not a measurement** — the only unmeasured input
   to the denominator. At 0 GB, N@340 rises 132 → 141; at 6 GB it falls to 123. The verdict is
   unchanged across that whole range.
5. **Whether IOAccelerator dirty pages compress cheaply is the sibling at-rest axis.** If they
   compress poorly, every N in §5 is optimistic; §4.2 establishes only that they are not wired.
