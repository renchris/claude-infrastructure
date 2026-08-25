# AXIS F — Is the instrument good enough, and what must change?

Measured 2026-08-25 against `~/.claude/logs/account-utilization.jsonl` (12,557 rows, 0 unparseable,
4 accounts, 2026-08-10T05:58Z → 2026-08-25T09:05Z = 15.13 d). Scripts:
`f1_coverage.py`, `f2_schema_k.py`, `f3_tail_burn.py`, `f4_est.py`, `f5_exchange.py`, `f6_ceiling.py`
(same directory). Read-only throughout; no `--fresh` loop was run.

---

## HEADLINE

**The series is good enough — it is the two ESTIMATORS reading it that are broken, and one of them is
broken in a way that makes it a boolean pretending to be a rate.** Separately, the series turns out to
carry the one number nobody thought it had: the **5h : weekly exchange rate, 4.4 ± 0.15 pp of a 5h
window per 1 pp of weekly**, fitted independently on all four accounts (R²-through-origin 0.82–0.94)
against a cross-account null arm at 0.57. That number answers failure mode (2) — *can 9% of a weekly
fit inside one 5h window* — directly: **yes, with 2.5× headroom.**

---

## 1. COVERAGE

**The writer.** `bin/claude-accounts:2478 record_utilization()` — a side-car on the fresh-sweep path
(`bin/claude-accounts:2755`), rate-limited by `UTIL_MIN_INTERVAL_S = 300`, every error swallowed.
Sweeps are driven by **`~/Library/LaunchAgents/com.claude.accounts-keepwarm.plist`**, `StartInterval
180`, `ProcessType Background`, `LowPriorityIO` (currently loaded: `launchctl list` → status 0).

**The cadence is explained exactly, not approximately.** keepwarm ticks at 180 s; the recorder refuses
a write inside 300 s of the last one; so a write lands on every *second* tick. Predicted 360 s,
**measured median 383 s** (p90 467 s), identical to the second across all four accounts.

| account | n | span | median gap | p90 | max | gaps > 2× median | time in them |
|---|---|---|---|---|---|---|---|
| next | 3,139 | 15.13 d | 383 s | 467 s | 12,328 s | 30 | 21.66 h (6.0%) |
| next2 | 3,139 | 15.13 d | 383 s | 467 s | 12,328 s | 30 | 21.66 h (6.0%) |
| next3 | 3,140 | 15.13 d | 383 s | 467 s | 12,328 s | 30 | 21.56 h (5.9%) |
| next4 | 3,139 | 15.13 d | 383 s | 467 s | 12,328 s | 30 | 21.66 h (6.0%) |

**Gaps are fleet-synchronous, never per-account.** 3,140 distinct sweep timestamps; the rows-per-sweep
histogram is `{1: 1, 4: 3139}` — every sweep but the very first wrote all four accounts. So there is no
per-account coverage hole to model: a gap is a gap in the *sweeper*, and it hits all four identically.

**Wall-clock coverage: 95.29%** (each gap credited at min(gap, 600 s)). **17.12 h of the 363.1 h span —
4.71% — is genuinely uncovered.** Top gaps:

```
205.5 min  2026-08-14T23:42Z -> 2026-08-15T03:08Z
163.1 min  2026-08-23T01:44Z -> 2026-08-23T04:27Z
110.5 min  2026-08-14T18:28Z -> 2026-08-14T20:19Z
 85.9 min  2026-08-14T04:18Z -> 2026-08-14T05:44Z
 74.4 min  2026-08-12T23:17Z -> 2026-08-13T00:31Z
```

**Cause — the BOX, not the sweeper. Established with an independent control that could have failed.**
`~/.claude/logs/capacity-alarm.jsonl` is written by a *different* launchd job
(`com.claude.capacity-alarm`) at a *different* cadence (60 s, n = 29,160). If only the utilization
series had holes, the sweeper would be indicted. It does not:

| utilization gap | capacity-alarm gap at the same wall-clock |
|---|---|
| 2026-08-22T20:46:49 → 21:51:57 (65.1 min) | 2026-08-22T20:46:39 → 21:52:23 (65.7 min) |
| 2026-08-14T04:18:50 → 05:44:42 (85.9 min) | 2026-08-14T04:22:39 → 05:45:02 (82.4 min) |
| 2026-08-14T23:42:54 → 15T03:08:21 (205.5 min) | 2026-08-14T23:45:43 → 15T03:06:10 (200.4 min, in two hops) |
| 2026-08-23T01:44:27 → 04:27:32 (163.1 min) | 2026-08-23T01:47:42 → 04:01:31 (133.8 min) |
| 2026-08-25T06:50:04 → 07:39:40 (49.6 min) | 2026-08-25T06:45:16 → 07:32:34 (47.3 min) |

Two unrelated samplers, same holes, minute-for-minute → **machine sleep/reboot**, not a sweep failure.
Consistent with `claude-accounts.log`, which logs a line for every instrument failure and has *none*
clustered on those windows. This matters for the sibling axes: **a gap is missing WALL TIME, not
missing burn** — spend during a real gap still shows up as a step in the next sample's `weekly_pct`,
so nothing is lost from a cumulative reading, only from a *rate* reading. Measured: only **1.6% of all
observed weekly burn** falls inside a gap > 2× median (§5 table).

## 2. RETENTION — lever #7 is SATISFIED and the plan doc is STALE

**Read from the code, not the doc.** `config/store-bounds.manifest:47` and
`scripts/rotate-autonomy-logs.sh:344` list this file in `DEFAULT_TARGETS`. Policy:
`ROTATE_MAX_BYTES` **25 MiB**, `ROTATE_KEEP` **8**, gzip on. Driver:
`com.claude.log-rotation.plist`, hourly. It is **not** truncated, **not** capped at 6 days, and
**never has rotated** — `log-rotation.out.log` reads `rotated=0 skipped=26` on every tick, and there
are zero `account-utilization.jsonl.*` files on disk.

**Arithmetic.** 3,673,047 B over 15.13 d = **237 KiB/day** → 25 MiB reached in **~108 days**
(~2026-12-11), then 8 gzipped generations retained ≈ **2.4 years** of history on disk.

> **`USAGE_TELEMETRY_100P.md:481` — "Raise `account-utilization.jsonl` retention past 6 days" — is
> FALSE as written and should be struck or rewritten.** The "6 days" figure was the *series length on
> 2026-08-16*, not a retention policy; nothing has ever deleted a row. Leaving an open Q1 lever
> pointing at a non-problem is itself the defect (a stale open lever consumes triage attention
> forever).

**The residual, which IS real and is a different problem.** At rotation the *live* file restarts at
zero bytes and the history moves to `account-utilization.jsonl.<UTC>.gz`. Every reader in the repo
(`_util_tail`, `scripts/pool-floor.sh:50`, `scripts/desk-strand-replay.py`) opens the live path only.
So on ~2026-12-11 every burn estimate on the box silently drops to a series of length ~0 and stays
there until the file refills. **Fix is one line in the readers (glob the `.gz` siblings) or a
`ROTATE_MAX_BYTES` override; it is not a retention change.**

## 3. k QUALITY — a fleet-level BLACKOUT, not a per-account blind spot

`k_src` over the whole series (5,013 rows predate the field — see §4):

| k_src | rows | % of fielded (7,544) | % of all (12,557) |
|---|---|---|---|
| `work` | 5,288 | 70.1% | 42.1% |
| `panes` | 1,544 | 20.5% | 12.3% |
| `unmeasured` | 712 | 9.4% | 5.7% |
| absent (pre-2026-08-16) | 5,013 | — | 39.9% |

**The single most decision-relevant fact about `k`: the four accounts NEVER disagree. 0 of 1,886
sweeps have a mixed `k_src`.** That is structural, not luck — `concurrency()` (ps) and
`working_concurrency()` (transcript walk) each return `None` **fleet-wide** on failure
(`bin/claude-accounts:497`, `:552`). So `unmeasured` is never "one account we could not see"; it is
always **all four at once**, which is precisely why `--route` excludes the entire fleet as
`concurrency-unmeasured` → exit 3 → the launcher falls back to a pinned account. That is the
operator's live desk defect, and here is its rate:

```
day        sweeps  ALL-4 unmeasured (-> --route exit 3)   pane-fallback (walk failed)
2026-08-16    125      9 =   7.2%                            10 =   8.0%
2026-08-17    207     17 =   8.2%                            40 =  19.3%
2026-08-18    217      8 =   3.7%                            34 =  15.7%
2026-08-19    219      5 =   2.3%                            35 =  16.0%
2026-08-20    217      5 =   2.3%                            43 =  19.8%
2026-08-21    210     42 =  20.0%                            52 =  24.8%
2026-08-22    208     32 =  15.4%                            43 =  20.7%
2026-08-23    188     45 =  23.9%                            49 =  26.1%
2026-08-24    216      9 =   4.2%                            55 =  25.5%
2026-08-25     80      6 =   7.5%                            26 =  32.5%
TOTAL       1,887    178 =   9.4%                           387 =  20.5%   (last 48 h: 10.5%)
```

**Clustered AND persistent — the distinction the axis brief asked for resolves as "both", and that
changes the fix.** 92 separate runs, longest 15 consecutive sweeps (2026-08-22T02:49→04:44Z). So it is
not one outage to repair, and not a uniform 9.4% either: it is **load-correlated bursts**. The cause is
named in the log and correlates day-for-day:

```
day        ps_fail(TimeoutExpired)  walk_over_budget  429/throttle | ALL-4-unmeasured rows
2026-08-20            19                    95              0      |    20
2026-08-21            75                   183             25      |   168
2026-08-23            79                   171             57      |   180
2026-08-24            26                   120             93      |    36
```

`ps -wwEo command=` timing out at 10 s and the transcript walk blowing its 5.0 s budget are both
**symptoms of a loaded box** — i.e. the instrument fails exactly on the days the fleet is busiest,
which is exactly when routing matters. This is the same shape the code's own comment predicted
(`_kwork_unmeasured`: *"the box is pathologically loaded — i.e. exactly when the concurrency count
matters most"*).

**Task #171 re-verified against today's tree — STILL TRUE, at the low end of its filed band.** Run at
the shipped `KWORK_WINDOW_MIN = 10`:

| | one-level (as shipped) | recursive (truth) | invisible |
|---|---|---|---|
| 5 min | 6 | 13 | **53.8%** |
| **10 min (shipped)** | **8** | **15** | **46.7%** |
| 15 min | 11 | 18 | 38.9% |
| 30 min | 12 | 19 | 36.8% |

Every invisible writer sat at **depth 5**, all of the form
`<slug>/<session-uuid>/subagents/workflows/wf_…/…jsonl` — and on `next` the ratio was **2 visible vs 9
real (78% blind)**. The filed "46–63%" band reproduces. Note the reflexivity: *this research wave's own
subagents are the invisible population*, which is the anti-correlation #171 describes — an account
scores idlest precisely while driving the most agents.

**What fraction of samples can support a per-session estimate at all?** `k_work` is non-null on
5,288/7,544 = **70.1%** of fielded rows and 42.1% of the whole series. And on those rows it
under-counts by ~47%. So the honest answer is: **no per-session (per-burner) estimate is supportable
from this series today.** Any Axis A–E design that wants "%/hour per working session" must abstain
(L2) until #171 lands.

## 4. SCHEMA DRIFT — exactly one change, exactly two key-sets

Every key's first appearance:

| key | first seen | present in |
|---|---|---|
| ts, acct, k, session_pct, weekly_pct, fable_pct, session_reset_at, weekly_reset_at, credits_on, credits_used, auth, stale | 2026-08-10T05:58:34Z | 12,557 / 12,557 |
| **k_work**, **k_src** | **2026-08-16T10:26:05Z** | **7,544 / 12,557 (60.1%)** |

Only **two distinct key-sets** exist in the whole file (12 keys → 14 keys). No field was ever removed,
renamed, or retyped. **Handling rule for any analysis spanning 2026-08-16T10:26Z:** treat absent
`k_src` as a *third* state, `absent`, never as `unmeasured` and never as 0 — the pre-field rows carry a
perfectly good `k` (pane census). Concretely: `src = r.get("k_src") or ("panes" if r.get("k") is not
None else "absent")`.

**Two silent-breakage warnings for sibling axes, both measured:**

- **`k is None` on 776 rows (6.2%)** and `k_work is None` on 2,256 of 7,544 fielded rows (29.9%). A
  `sum(r["k"] for r in rows)` or any `<` comparison raises `TypeError` (it did, in my first run) — or
  worse, `r.get("k", 0)` silently converts a *measurement failure* into *zero concurrency*, which is
  the fail-open direction the code deliberately closed at `bin/claude-accounts:2054`.
- **`session_reset_at` is null on 1,888 rows (15.0%)** and `weekly_reset_at` on 182 (1.4%). This is
  **not** missing data: 1,789 of the 1,790 null-stamp rows that carry a percentage have
  `session_pct == 0`, and all 182 null weekly stamps have `weekly_pct == 0`. The endpoint simply emits
  no reset stamp for a window with zero usage. **A replay must read "null reset stamp" as "window has
  not started", not as "unknown"** — otherwise 15% of rows drop out of any phase-aligned analysis, and
  design law L1 (*report against window PHASE*) is exactly the analysis that needs them.

## 5. STALENESS AND AUTH — the inherited-percentage fear does NOT reproduce

`stale` is written as `bool(stale_quota or error)` (`bin/claude-accounts:2534`).

| field | distribution |
|---|---|
| `stale` | False 11,510 · **True 1,047 (8.3%)** |
| `auth` | ok 11,896 · stale 539 · keychain-error 110 · healed 11 · logged-out 1 |
| `credits_on` | False × 12,557 (never once true) |
| `credits_used` | 0.0 × 12,557 (the field is constant — carries zero information) |

**Do stale rows carry inherited percentages? Yes — and it does not matter, with a control.**

- A stale row repeats **both** percentages of the prior row **91.6%** of the time (959/1,047).
- **Control:** a *fresh* row repeats both **76.1%** of the time (8,756/11,506). At a 383 s cadence with
  1-pp granularity, most consecutive samples genuinely do not move. So the stale excess is +15.5 pp,
  real but modest — stale rows are mostly echoing values that had not changed anyway.

**Could an inherited percentage manufacture a fake rate? Measured: essentially no, three ways.**

1. `_util_tail` (`bin/claude-accounts:1877`) already **drops every `stale` row before any delta is
   taken** — *"a rate needs two MEASUREMENTS, not a measurement and an echo."* Verified in the code
   path, not assumed.
2. The dangerous case is a stale row carrying a **pre-reset** percentage against a **post-reset**
   stamp: the next fresh sample would then show a huge false positive jump. **Measured: 1 occurrence in
   12,553 consecutive pairs.** (A naive minute-keyed test flags 67, but 66 of those are the reset
   stamp's own sub-second jitter straddling `03:59:59.x` ↔ `04:00:00.x` — median jitter 0.294 s, p95
   0.848 s, max 1.858 s, n = 3,137. **Key a window on the reset stamp rounded to the nearest MINUTE or
   coarser, never on string equality** — raw equality reads 2,952 "weekly resets" for `next` where
   there were 6.)
3. Within a single window, with both rows fresh, the series is **monotone**: 0 weekly decreases in
   6,128 in-window pairs, and **1** session decrease in 6,513. There is no rollback to launder.

**Burn accounting — how much real burn the estimators can and cannot see:**

| account | observable weekly pp burned | usable (fresh + contiguous) | lost to `stale` | lost to gaps > 2× |
|---|---|---|---|---|
| next | 120 | 103 (85.8%) | 14 (11.7%) | 3 (2.5%) |
| next2 | 105 | 94 (89.5%) | 8 (7.6%) | 3 (2.9%) |
| next3 | 120 | 112 (93.3%) | 7 (5.8%) | 1 (0.8%) |
| next4 | 102 | 92 (90.2%) | 10 (9.8%) | 0 (0.0%) |
| **fleet** | **447** | **401 (89.7%)** | **8.7%** | **1.6%** |

## 6. THE TWO ESTIMATOR DEFECTS — where the incumbent is WRONG on real data

### 6a. `burn_5h_ph` is a BOOLEAN wearing a rate's clothes

Replayed over all 11,472 eligible adjacent pairs (0.03 ≤ dh ≤ 1.5 h, fresh rows only):

- **77.2% of pairs have `session_pct` delta exactly 0** → the estimator reports **exactly 0.0 %/h**.
  It does not abstain. It asserts zero.
- 2.0% have a negative delta (window rolled) → field absent.
- **94.6% of pairs have |delta| ≤ 2 pp.**
- The **smallest non-zero rate representable at the median 383 s gap is 9.40 %/h.** There is nothing
  between 0 and 9.4. Measured non-zero rates: median 0.00 %/h, p90 9.75 %/h — i.e. the distribution is
  a spike at 0 and a spike at ~9.4, and nothing in between.

**Why this is not academic.** `_su_projected` (`bin/claude-accounts:1865`) reads
`if not isinstance(b,(int,float)) or b <= 0: return su`. So on **77% of decisions the 5h projection is
silently DISARMED**, and on the other 23% it projects at ≥ 9.4 %/h × `PROJ_LOOKAHEAD_H` = 1.0 h, which
is a 9-point shove. Whether the 5h wall-guard fires is decided by **whether one 6-minute sample
happened to tick a single percentage point**. A replay over 11,960 (sweep, account) decisions shows the
field **present 97.1% of the time** — so nothing anywhere says the number is a coin flip.

Applied to the live example: `next3` at 5h 9% would need a rate the instrument cannot express except in
9.4 %/h quanta.

### 6b. `burn_wk_ppd`'s documented 48-hour window is UNREACHABLE — the reader is 4× too small

`apply_burn` selects the *widest* weekly pair inside 48 h requiring span ≥ 6 h. But its only supplier,
`_util_tail`, reads a **fixed 128 KiB byte tail** (`max_bytes=131072`). At the measured 305 B/row ×
4 rows/sweep:

- **Today that tail holds 428 rows = 12.12 HOURS of series.**
- Simulated at every sweep across the 15 days: min 7.96 h, p10 11.61 h, **median 12.20 h**, max 18.81 h.
- **100.0% of sweeps have tail coverage below 48 h.** The clause has never once been satisfiable.
- Replayed: mean actual weekly-pair span available = **12.64 h** (docstring: "up to 48 h").
- The field is present 92.6% of sweeps, abstaining 7.4% — so again it does not fail loudly, it just
  answers a different question than the one documented.

**This is exactly the failure the docstring says it is guarding against, inverted.** The comment
justifies the 48 h pair as *"short spans read desk noise as pace"*; the tail then hands it a ~12 h span.
A 12-hour pair ending at 09:00Z is dominated by the operator's night — which is why the router told the
operator `next3` needed **70 %/day** while calling its recent rate **28 %/day**.

## 7. WHAT THE SERIES *CAN* DERIVE THAT NOBODY HAS USED — the 5h : weekly exchange rate

Both meters count the same spend. Within any interval where **neither** window rolled and both rows are
fresh, `Δsession_pct` and `Δweekly_pct` are both linear in tokens burned, so their ratio is
`weekly_limit / 5h_limit` in percentage points. Fitted per 5h-window run, slope through origin
`Σ(ds·dw)/Σ(dw²)`:

| account | usable runs | Σ weekly pp | Σ 5h pp | **slope (5h pp per weekly pp)** | 1 − SSE/SST |
|---|---|---|---|---|---|
| next | 50 | 97 | 416 | **4.44** | 0.922 |
| next2 | 59 | 88 | 370 | **4.32** | 0.824 |
| next3 | 41 | 103 | 447 | **4.51** | 0.943 |
| next4 | 52 | 86 | 347 | **4.63** | 0.857 |
| **fleet aggregate** | 202 | 374 | 1,580 | **4.22** | — |

**Control (a control that can fail, and did not fire):** the same regression with the 5h deltas from
one account paired against the weekly deltas of a *different* account at the same timestamps gives
slope **0.57** over n = 1,815 pairs — an eighth of the own-account slope. The relationship is
account-internal, not a fleet-wide time-of-day artifact.

**Independent corroboration from a completely different statistic.** If a full 5h window (0 → 100%)
delivers 100/4.4 ≈ **22.7 weekly pp**, then the maximum *sustained* weekly burn is 22.7 pp / 5 h =
**4.5 weekly pp/h**. Measured max sustained 6-hour rates: next 4.83, next2 2.91, next3 6.43, next4 3.56
pp/h — **mean 4.43**. Two unrelated derivations landing on 4.4–4.5 is not a coincidence. (next3's 6.43
exceeds the bound legitimately: a 6 h span straddles a 5h roll and so draws on two windows.)

Empirical burn ceilings, for the sibling axes to plan against:

| window | next | next2 | next3 | next4 |
|---|---|---|---|---|
| max 1 h | 15.42 pp/h | 9.60 | 14.50 | 11.52 |
| max 3 h | 6.46 pp/h | 4.07 | **10.84** | 6.19 |
| max 6 h | 4.83 pp/h | 2.91 | 6.43 | 3.56 |

**Answering the operator's failure mode (2) with numbers, on the live example.** `next3` at weekly 92%
with 3.0 h left must burn 8 pp = **2.67 weekly pp/h**. Converted: 2.67 × 4.4 = **11.7 pp/h of its 5h
window**, from 9%, for 3 h → ends at ~44%, well under `S_CUT = 0.85`. And 2.67 pp/h is **25% of next3's
own demonstrated 3-hour ceiling of 10.84 pp/h**. **The 5h sub-cap is not the binding constraint and
never was on this data; the strand is a demand/dispatch failure, not a capacity one.** That is the
finding the operator asked for and it had been derivable from this series the whole time.

## 8. THE MINIMUM VIABLE FIX LIST — ranked

| # | what is broken | fix | file that writes it | what it buys | verdict |
|---|---|---|---|---|---|
| **F1** | `_util_tail`'s 128 KiB byte tail caps the weekly lookback at ~12 h; `burn_wk_ppd`'s documented 48 h window is unreachable on **100%** of sweeps | raise `max_bytes` to ≥ 600 KiB (48 h × 4 rows × 305 B ≈ 590 KiB), or select by *timestamp* not bytes | `bin/claude-accounts:1877` | the only fix that makes the *existing shipped* weekly rate mean what its docstring says; without it every Axis A–E pace estimate is a ~12 h night-weighted number | **MUST FIX FIRST** |
| **F2** | `burn_5h_ph` reports **exactly 0** on 77.2% of pairs and ≥ 9.40 %/h otherwise — a boolean, with no abstain | widen the pair window (span ≥ 1 h, not one adjacent pair) so the delta clears quantization, and **report null below a minimum resolvable delta** (L2) | `bin/claude-accounts:1908` `apply_burn` | makes the 5h wall-guard and `_su_projected` deterministic instead of sample-lottery | **MUST FIX FIRST** |
| **F3** | `k_work` blind to **46.7%** of live writers (all at depth 5, `subagents/workflows/`); miss is anti-correlated with real load | task **#171** as already specified — walk recursively into a separate `k_agents` field, never folded into `counts[]` | `bin/claude-accounts:599` `working_concurrency` | the only route to any per-burner metric; today no such metric is supportable | **MUST FIX** (blocks per-session estimates only) |
| **F4** | instrument blackout on 9.4% of sweeps (20–24% on loaded days), always fleet-wide → `--route` exit 3 → desk falls back to a pinned account | raise the `ps` timeout above 10 s under Background QoS, and/or let `k_src=unmeasured` **carry forward the last measured k with an age stamp** rather than excluding the whole fleet | `bin/claude-accounts:493` (ps), `:2054` (`_excluded`) | removes the operator's observed desk-abstain; recovers routing on exactly the busy days routing matters | **MUST FIX** (routing, not analysis) |
| **F5** | readers open only the live path; at ~2026-12-11 rotation resets the series to length 0 for every estimator | glob `account-utilization.jsonl*` incl. `.gz` in the three readers, or raise `ROTATE_MAX_BYTES` for this target | `bin/claude-accounts:1877`, `scripts/pool-floor.sh:50`, `scripts/desk-strand-replay.py` | prevents a silent total-blindness event with a known date | **FIX BEFORE DEC** |
| **F6** | `USAGE_TELEMETRY_100P.md:481` lever #7 ("raise retention past 6 days") describes a policy that does not exist — nothing has ever been deleted; 108 d to first rotation, 8 gz generations kept | strike the lever; replace with F5 | `docs/plans/USAGE_TELEMETRY_100P.md` | removes a permanently-open Q1 lever from triage | **DOC CORRECTION** |
| **F7** | `credits_on` (False ×12,557) and `credits_used` (0.0 ×12,557) are constant — pure noise in every row | keep (cheap, and a future non-zero is real signal) | — | nothing | **ALREADY GOOD ENOUGH** |
| **F8** | 15.0% of rows have a null `session_reset_at` | nothing to fix in the data — it means `session_pct == 0`; fix the *readers* to treat null as "window not started" | consumers | keeps 15% of rows inside any phase-aligned (L1) analysis | **ALREADY GOOD ENOUGH (reader rule)** |

**Already good enough, stated plainly so no design over-engineers around it:** wall coverage (95.3%),
gap structure (fleet-synchronous, 1.6% of burn), schema stability (one additive change, two key-sets),
monotonicity (1 decrease in 12,641 in-window fresh pairs), stale contamination of rates (already
filtered at source; 1 cross-reset echo in 12,553 pairs), and the 1-pp resolution of `weekly_pct`
(adequate for weekly pacing — the quantization problem is confined to the 5h meter's short deltas).

## 9. NOT DERIVABLE FROM THIS DATA

- **Absolute token or dollar denominators.** Confirmed: no field carries them and
  `claude-accounts --json` exposes none. Everything here is percentage-space. What would make it
  derivable: OTel export (`USAGE_TELEMETRY_100P` lever #6, still 0 of 5 config dirs) joined to this
  series on timestamp — the token counts are in the transcripts, the percentages are here, and one
  join would fit pp-per-Mtok directly.
- **Per-session / per-burner burn rate.** Blocked by F3 (46.7% of writers invisible) *and* by the
  fleet-synchronous nature of the k blackout. Made derivable by landing #171.
- **What happened during the 17.12 h of gaps, as a rate.** The *cumulative* burn survives; the rate
  does not — and no sweeper change can recover it, because the control above shows the box itself was
  asleep. Only a `caffeinate` policy or a wake-trigger changes this, and that is a machine-policy
  decision, not a telemetry one.
- **Whether a *specific* 5h window would have walled.** The exchange rate (§7) gives the fleet-average
  4.4; per-account slopes span 4.32–4.63 (±3.5%), and per-run ratios on the highest-signal runs (dw ≥ 5)
  have IQRs as wide as (3.80, 5.60). So the rate is good enough for a *plan* and not for a *guarantee*.
  Made tighter by F1+F2 (more usable runs per week) — n = 202 runs over 15 days is the binding limit.
- **Fable's exchange rate.** `fable_pct` is present on every row but was 0 for the entire fleet across
  almost the whole span; there is no co-movement to regress. Would become derivable after a period of
  genuine Fable use — but §0 already REFUTED the Fable arbitrage, so this is not worth engineering for.
