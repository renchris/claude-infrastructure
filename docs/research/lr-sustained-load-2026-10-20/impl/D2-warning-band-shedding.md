# D2: move idle sessions off an account before its weekly wall (decision packet and implementation design)

Item D2-warning-band-shedding, from `REPORT.md` §1 item 4, §4(d) D2 and §6. Written 2026-10-20
between about 18:00Z and 18:40Z. It is read-only, against `28b25a119` (this worktree's HEAD).
`main` has since moved to `6fdf87eca`, but none of those commits touch the files cited here
(`git diff --stat 28b25a119 main`). Load at writing: `sysctl -n vm.loadavg` =>
`{ 264.96 229.30 215.98 }` at 17:59Z and `{ 245.78 210.31 181.87 }` at 18:38Z, on 10 cores, so
about 22-26 per core.

**Labels.** *Measured* means read from a named file or produced by a named command. *Estimated*
means derived, and the method is named. *Hypothesis* means not verified. The scripts that produced
every measured number are in `/tmp/d2/` (Appendix A). They read only `~/.claude/logs/`,
`~/.reso/limit-recover/` and the transcript stores, and they wrote only under `/tmp/d2/`.

**Verdict: OPERATOR.** An agent can build the design end to end (§6). But the design moves
*healthy* sessions unattended, which reverses a written rule
(`bin/cc-lr:1801`: "An account with headroom keeps its idle sessions: moving a healthy session is a
surprise"). It also spends quota, and the operator has ruled that using up each weekly limit is the
bottom line (`bin/claude-accounts:3890-3892`). Both are the operator's call.

**Recommendation.** Build D2 as a **late-band idle shed**, shadow mode first. "Idle" means at rest
for ≥30 min, empty composer, not focused, no goal, team or background job. The band opens at
weekly ≥97%, or when the fast pace puts the wall ≤2 h away. Shedding happens only while the slow
pace still walls the account ≥2 h before its reset. Pair it with D2a: an at-the-wall idle fan-out
switch file, a 20-line change. **Do not** shed working sessions, and do not shed from 90%.

**Conviction: 60%** that the recommended configuration avoids roughly a fifth to a third of
at-wall limited sessions for ≤0.2 pp of stranded quota per wall, under permanent 15-40/core load.
The main doubt is the move lane's own casualty record (§3.4), which has not been measured since the
priority-31 waves.

---

## 0. Summary

1. **Walls are predictable, but only the late band is safe to act on.** Since 2026-08-29, every
   account that reached 90% walled: 25 of 25 windows. Over all 41 closed windows, 27 walled.
   - From 90% to the wall: median 11.3 h.
   - From 97%: median 1.9 h.
   - The wall lands a median 10.5 h before the reset. About 2.7 walls a week.

   All measured, M1.
2. **Idle is not zero future burn.** Of the band's weekly points, a median 18% (max 52%) came from
   sessions that had been at rest ≥30 min when the band opened. Across 7 recent walls, 23 such
   sessions resumed and burned in the band (measured from transcripts, attribution estimated, M4).
   So shedding from 90% strands quota.
3. **The frontier (replay of 7 walls, 10-08 to 10-20, 43 sessions that hit the limit; estimated,
   M5).**
   - Shedding idle sessions from 90% with no guard avoids 24 of 43 limited sessions, but strands
     15.6-21.8 pp across the 7 walls.
   - The late band with the strand guard avoids 15 of 43 (8 of 43 if the move takes 45 min instead
     of 20), and strands ≤1.5 pp in total, about 0.2 pp a wall.
   - A trigger at 99% avoids 11 of 43 and strands 0 pp.
4. **At-the-wall idle fan-out is the comparator, and it depends on latency.** Measured from the
   first death, which is when the reconciler gets its account fact:
   - it avoids 17 of 43 if the idle move lands within 20 min;
   - 6 of 43 within 60 min;
   - 3 of 43 within 120 min.

   In the incident, the idle batch took more than 60 min. D2 acts hours earlier and does not
   depend on that latency. The two together avoid 16-21 of 43 (M6).
5. **The actuator is the risk.** The move lane has driven 285 session rows since 2026-10-06. Of the
   66 that actuated, 41 ended `MOVED`, 13 `FAILED` and 12 `STRANDED` (measured, M8). A proactive
   shed that strands a healthy session is worse than doing nothing. So the design runs shadow
   first and has a casualty breaker that drops itself to shadow.

## 1. The question

> When an account is about to hit its weekly limit, may the rail move that account's **idle,
> healthy** sessions to another account **before** the wall, unattended, so that fewer sessions
> ever hit the limit and need a recovery? If so, how early, and how much stranded quota is
> acceptable?

**In scope:**
- Weekly (`7d`) walls.
- Sessions at rest with an empty composer, no live `/goal`, no team, no background job, and not
  the focused pane.
- The move lane as the actuator (`cc-lr move`, `lr-move-batch.sh`, `lr-move-worker.sh`). It
  restarts a session in its own pane on another account with no model turn.

**Out of scope, with reasons:**
- **Working sessions.** Their move is the R relaunch with an owed prompt, which is the recovery
  itself done earlier. It carries the largest strand risk (§4 option F). D1 already moves
  recycling sessions off a held account at no cost.
- **5-hour walls.** They reset within 5 h; the existing stay rule and `IDLE_MIN_LEFT_S` cover them
  (`lr_recon/census.py:27`).
- **Retuning the router's spend policy.** Operator rulings 2026-09-22 and 2026-10-17
  (`REPORT.md` Appendix B).

## 2. How the code decides today

| Path | What it does with an account nearing its weekly wall | Code |
|---|---|---|
| New fires | **Held** below 10% weekly headroom unless forecast to strand (`on-pace`, `claimed`, …), so demoted below every open account | `bin/claude-accounts:6770-6827` (`dispatch_floor_row`), `:6851-6882` (`_dispatch_partition`) |
| Recovery placement | **Excluded** below `RECOVERY_W_FLOOR` 0.10 | `bin/claude-accounts:3942` (`recovery_floors`), `accounts.json` router `RECOVERY_W_FLOOR 0.1` |
| Recycles | Stay unless excluded or beaten 4x (D1's subject) | `scripts/handoff-fire.sh` `recycle_repick` |
| Idle sessions, before the wall | **Nothing.** `cc-lr rotate` moves idle sessions only off an account at **100%** (`cl_acct_cap`: `w >= 100`), and states the rule: "An account with headroom keeps its idle sessions: moving a healthy session is a surprise" | `bin/cc-lr:517-531`, `:1801` |
| Idle sessions, at the wall | The reconciler's idle fan-out exists end to end (`IDLE-ELIGIBLE` → fanout record → `lr-handoff --in-place --voluntary --no-prompt`) but is **off**: `LR_IDLE_FANOUT` defaults to `off` and the plist sets no environment | `lr_recon/census.py:8-9,271-299` (`:281`), `__main__.py:710`, `act.py:78-84,126-127`; `plutil -p scripts/limit-recover/com.reso.lr-reconciler.plist` => no `EnvironmentVariables` |
| The zero-human gates | Global `autorecover.on` (the poller's hook lane and reroute) and `recon/autorecover.on` (reconciler, D1.9) | `lr-reset-poller.sh:2464`; `__main__.py:225-231`. Both exist now: `stat` => global since 2026-09-29, `recon/` since **2026-10-20T17:10:32Z** (A7's file records this as the operator's touch) |
| Pace estimators | EWMA, flat 24 h/12 h, strand nowcast, all computed in-process by `apply_burn`. **The ledger rows carry none of them** (axis 10 skeptic L3a) | `bin/claude-accounts:4842-4968,5319-5434` |

The idle fan-out's account fact comes from a death (hook or census) or from a wire `rejected` read.
The fact file never records a quota forecast, by charter: "Never a limit signal here, by design:
the usage endpoint integer >= 100" (`lr_recon/facts.py:1-12`). So the reconciler cannot act
before the wall without breaking its own fact model. This is why the shed below lives beside the
move lane, not in the reconciler.

## 3. Measurements

### 3.1 How predictable the walls are

| # | Finding | How |
|---|---|---|
| M1 | **41 closed weekly windows** (2026-08-10 to 10-20). 33 reached ≥90%, 27 walled (100%), and every wall had passed 90%. **Since 08-29: 25 of 25 that reached 90% walled.** 2.70 walls a week over 10.0 weeks. Lead times before the wall: from 90%: min 1.5, p25 4.5, **median 11.3**, p75 20.1, max 71.3 h. From 95%: median 3.0 h. From 97%: min 0.1, p10 0.3, p25 0.9, **median 1.9** h. Wall to reset: p10 2.6, p25 8.8, **median 10.5**, p75 37.7, max 106.4 h. Sessions at the wall (`k_native`, else `k`): median 8, max 23 (n=24) | Measured: `python3 -I /tmp/d2/windows.py` over `~/.claude/logs/account-utilization.jsonl` (56,634 rows), windows keyed by (account, reset hour) |
| M2 | **Band-entry rules, backtested with the router's own pace estimators** (ports of `burn_wk_ewma_ph`/`burn_wk_flat_ph`, fed only the rows that existed at each moment). The proposed **late** rule is: (≥97% or wall ≤2 h at the fast pace) and the slow pace walls ≥2 h before the reset. It fired in **26 windows, 25 walled (precision 0.96)**. Lead to the wall: p10 0.3, p25 0.9, median 2.2 h. It missed 2 walls, the near-reset ones (next 10-11 walled 0.9 h before its reset, next4 10-11 0.6 h); the guard skips those by design. The one false entry was next3 08-18 (max 98). For comparison, ≥90% alone: precision 0.82, 0 missed. The axis-10 combination (≥90 or wall ≤6 h): precision 0.87, 1 missed. The open/closed state flips up to 7 times per window without hysteresis | Measured: same script, `rules` block |
| M2b | **Live now (18:24Z).** next2 is at weekly 83%, flat-24 h pace 1.56 pp/h, reset in 88.6 h, so its wall is forecast in about 10.9 h (≈ 10-21 05Z), about 3 days before its reset. next is at 61%, 1.36 pp/h, wall in about 28.6 h. A shadow rollout would see two bands within a day and a half | Measured: python read of the ledger's newest rows, 24 h endpoint delta (estimate of the forecast) |

### 3.2 Per-session burn inside the band

The ledger has per-account levels only. Per-session burn is **estimated** as follows:

- **Calls.** Every assistant API call written since 10-07 was extracted from the four config dirs'
  transcripts (2,105 files, 3.8 GB, 113,215 unique message ids). Subagent files are charged to
  their parent.
- **Account.** Each call is attributed to the account that served it. Transplants clone a
  transcript, and an APFS clone keeps its birthtime, so 6,905 message ids sit in more than one
  dir. A call belongs to the `.handed-off` copy with the smallest mtime at or after its timestamp,
  otherwise to the live copy.
- **Points.** Each account's weekly points over the band are apportioned by cost-weighted tokens:
  input 1, 5-minute cache write 1.25, 1-hour cache write 2, cache read 0.1, output 5.
- **Calibration.** It is noisy. Over account-days the points per million weighted tokens run from
  p25 0.11-0.19 to p75 0.22-0.38 by account, so per-session shares are good to roughly a factor of
  2.

Commands: `python3 -I /tmp/d2/files.py`, `parse.py`, `burn2.py`.

| # | Finding |
|---|---|
| M3 | **7 walls analysed** (every wall whose 90% crossing fell after 10-07: next2 10-10, next 10-11, next4 10-11, next3 10-13, next2 10-17, next4 10-18, next3 10-20). Bands lasted 2.2-46.0 h (90% to endpoint 100) and 7-26 sessions made calls in each. **Per session, pp per band-hour (burners only, n=129): p10 0.008, p25 0.021, median 0.056, p75 0.19, p90 0.30, max 1.33.** **Per active hour: median 0.14, p75 0.26, p90 0.40, max 1.72.** For comparison, the router's 2,845-session-hour figure is p75 0.39, p90 0.61 pp/h (`bin/claude-accounts:6730-6731`). **The top 3 sessions burned 31-55% of each band's points**, so burn is concentrated |
| M4 | **Idle now, burning later.** At band entry, 12-152 sessions per wall had been at rest ≥30 min. The count includes sessions that had already exited: residency is not on disk, so this is "had a main-thread call in the prior 24 h". In every wall 2-5 of them resumed and burned in the band, 23 sessions in all. **Their share of the band's points was median 0.18, p75 0.37, max 0.52**. This confirms axis 10 skeptic F10 with a population: "idle" now predicts little about the next hours |

### 3.3 What shedding would have avoided and stranded (M5)

**Simulation** (estimated; `burn2.py`):
- **Clock.** It walks each band in 10-minute steps.
- **Shed rule.** A session is shed once it has been at rest for ≥Q minutes: its last main-thread
  call ended the turn, and nothing ran since. The move completes L minutes later unless the session
  makes a call first; in that case it is retried at its next rest.
- **Strand guard M.** A shed starts only while the counterfactual trailing-6 h pace of the kept
  sessions still walls the account ≥M h before its reset. Optionally it also waits until the
  counterfactual level is ≥LV.
- **Counterfactual level.** It omits a shed session's calls after its shed time.
- **Strand, high bound.** The level the account would reach by its reset if only the kept sessions'
  *observed* later calls are added. These come from any account, since a recovered session keeps
  its id. It is high because a session stuck at the wall made no calls.
- **Strand, low bound.** Each kept session that burned in the last 2 h before the wall is assumed
  to go on at that rate until the reset.
- **Avoided.** A session that hit the limit on that account between the wall and the reset, and had
  been shed before its first limit record.

Totals over the 7 walls, 43 limited sessions:

| Policy (Q at rest, M guard, LV level) | Avoided (L=20 min) | Avoided (L=45 min) | Strand high / low, pp, 7 walls |
|---|---|---|---|
| Shed from 90%, Q30, no guard | **24** | 9 | **21.76 / 15.62** |
| Shed from 90%, Q30, guard 2 h | 16 | 8 | 10.85 / 7.45 |
| Q60, guard 2 h | 8 | 8 | 3.40 / 2.15 |
| LV 93, Q30, guard 2 h | 16 | 8 | 7.33 / 4.11 |
| LV 95, Q30, guard 2 h | 16 | 8 | 4.80 / 2.78 |
| **LV 97, Q30, guard 2 h (recommended)** | **15** | **8** | **1.50 / 0.97** |
| LV 97, Q15, guard 2 h | 19 | 9 | 3.90 / 2.18 |
| LV 97, Q30, no guard | 19 | 9 | 2.07 / 0.97 |
| LV 99, Q30, guard 2 h | 11 | 3 | 0.00 / 0.00 |

Per wall, the recommended row looks like this:

| Wall | Avoided / limited | Strand high / low (pp) | Note |
|---|---|---|---|
| next2 10-10 | 3/7 | 0.89 / 0.00 | |
| next 10-11 | 0/7 | 0 / 0 | guard: walled 0.9 h before reset |
| next4 10-11 | 0/0 | 0 / 0 | |
| next3 10-13 | 3/5 | 0 / 0 | |
| next2 10-17 | 6/7 | 0.61 / 0.97 | |
| next4 10-18 | 0/10 | 0 / 0 | guard: walled 2.2 h before reset |
| next3 10-20 | 3/7 | 0 / 0 | **the incident:** 3d1d988a shed at 23:37Z and 3e929a81 at 00:27Z (both became limited at 03:19 and 03:13Z, matching `REPORT.md` §2.1 and axis 10 F5); d7eb73d2 at 22:57Z |

**Why the strand numbers are bounds and not a point.** Three things are not modelled:

- The router's strand rescue lifts an account once the forecast says ≥4 pp would die
  (`dispatch_floor_row`, `DISPATCH_STRAND_PP 4.0`), and that brings new fires in.
- D1's recycles would also leave the account.
- Unobserved sessions that were idle and alive add no burn and change nothing.

What converts strand into work: at the measured p50 of 0.14 pp per active session-hour, 1 pp is
about 7 active session-hours (estimated).

### 3.4 The actuator's record

| # | Finding | How |
|---|---|---|
| M8 | **Move lane since 2026-10-06: 79 batches, 285 session rows.** Outcomes: 41 `MOVED`, 219 `NOTMOVED`, 13 `FAILED`, 12 `STRANDED`. Of the 66 that actuated, 62% moved. The casualties cluster: on 10-10/11, 11 `FAILED source-ambiguous`; on 10-18, 11 `STRANDED` ("no live process holds the session"). On 10-20, 2 of 2 moved. `MOVED` wall time: p50 386 s, p90 1,347 s, max 3,712 s. Main `NOTMOVED` reasons: `HELD` 72, `still-busy` 62, `REFUSED` 17, aborted while waiting 16, batch refused 15, slot-wait 14, claim-held 13, became-limited 3 | Measured: `jq` over `~/.reso/limit-recover/move/2026*/<sid>.json` into `/tmp/d2/move_verdicts.tsv` |
| M9 | **No move-lane batch has run since the priority-31 reload** (newest is `20261020T030423Z`). Its latency and casualty rate at priority 31, at 15-40/core, are **unmeasured** | Measured: `ls -t ~/.reso/limit-recover/move/` |
| M10 | **The reset poller now ticks every 10.7 min (p50; max 12.4)** after the 07:23Z reload, against p50 12.9 and p90 42.9 min before it | Measured: `TICK start` gaps in `~/.reso/limit-recover/poller.log` on 10-20, split at 07:30Z |

### 3.5 At-the-wall idle fan-out (the comparator)

| # | Finding |
|---|---|
| M6 | Of the 43 limited sessions, **36 had ended their turn before the endpoint read 100**: they were at rest at the wall and started a new turn after it. The reconciler's fan-out can act only once a fact exists, that is from the first death. Measured from that moment, a fan-out that lands the idle move within **20 / 60 / 120 min avoids 17 / 6 / 3** of 43 (estimated, `burn2.py` P1). **D2 (recommended row) plus fan-out: 21 of 43 at 20 min, 16 at 60 min.** One session, 3e929a81, hit the limit at 3 consecutive walls (next2 10-17, next4 10-18, next3 10-20): recovery placement keeps sending sessions to the next account due to wall, by design |

## 4. Options

| Option | What it does | Measured or estimated consequence |
|---|---|---|
| **A. Status quo** | Idle sessions sit until they start a turn after the wall, then go through recovery | 43 limited sessions over 7 walls; about 6 per wall (M5/M6) |
| **B. D2a only: at-the-wall idle fan-out**, switched by a file the reconciler reads each pass | The existing reconciler idle path, keyed on the death fact | 6-17 of 43 avoided depending on latency. 0 pp strand by construction (the account has walled). Under the premise's load, latency is the weak point: the incident's idle batch took more than 60 min |
| **C. D2b only: late-band idle shed (recommended thresholds)** | A shed controller kicked by the poller; the move lane moves at-rest sessions while the band is open and the guard holds | 8-15 of 43 avoided (L=45/20 min). ≤1.5 pp stranded over 7 walls, ≤0.2 pp per wall. Acts hours ahead, so at-wall latency does not matter |
| **D. B + C (recommended)** | Both | 16-21 of 43 avoided; strand as C |
| E. Shed from 90%, no guard | Axis 10's band | 24 of 43 at L=20, but 15.6-21.8 pp stranded over 7 walls, about 2.2-3.1 pp per wall. It conflicts with the 2026-10-17 ruling. **Rejected** |
| F. Also shed working sessions at turn boundaries to aim the wall at the reset | Move the top burners (the top 3 hold 31-55% of the band, M3) | It needs the R relaunch with owed prompt, which is the recovery itself, done early. Goal-driven sessions rarely rest; the move lane holds a live `/goal` (`bin/cc-lr:1172`, `:1210-1226`). Largest strand risk. D1 moves recycling sessions for free. **Not recommended** |
| G. LV 99 instead of 97 | A stricter trigger | 3-11 of 43 avoided, 0 pp stranded. Fragile to latency: 3 at L=45 |

## 5. Recommendation and the questions for the operator

Adopt **D**:
- the late-band shed at LV 97, Q 30 min, guard 2 h, at most 4 per account per tick, focused panes
  excluded, cold cache first;
- plus the at-wall fan-out switch;
- shadow mode first, with a casualty breaker and a strand audit that both drop the shed to shadow.

**Questions** (each has a default the code ships with):

1. **May the rail move a healthy, idle session to another account, unattended, before its account
   walls?**
   - This reverses `bin/cc-lr:1801` for the late band only.
   - The move is in place: same pane, same session id, no model turn. The operator sees the pane
     restart.
   - Default: no. The code ships `off`.
2. **What strand is acceptable?**
   - LV 97: ≤0.2 pp per wall (high bound), 15 of 43 avoided at L=20.
   - LV 99: 0 pp, 11 of 43.
   - The strand audit pages when an account with sheds closes its week below 99%.
3. **Turn on the at-the-wall idle fan-out (D2a)?**
   - Zero strand; 6-17 of 43.
   - Uses `recon/autorecover.on`, which exists.
   - Needs one reconciler restart to load the code; see A6 about restarting mid-cohort.
4. **Confirm working sessions stay out of scope** (option F).
5. **Shadow length:** at least two banded walls (likely next2 ≈ 10-21 05Z and next ≈ 10-21 23Z,
   M2b), then decide `on`.

Exact operator commands are in §9.

## 6. Implementation design

### 6.1 Files and functions

| File | Function or site | Change |
|---|---|---|
| `bin/claude-accounts` | After `DISPATCH_CLAIM_TTL_MIN_DEFAULT` (`:6731-6732`): new `SHED_*_DEFAULT`, `shed_knob(R, key)`, `shed_band_row(r, R)` | The band verdict, **pure**, over the `apply_burn` stamps (§6.2) |
| `bin/claude-accounts` | `ROUTER_OPTIONAL_RANGES` (`:437-457`) | `SHED_LV_OPEN (50, 100)`, `SHED_TTW_OPEN_H (0, 48)`, `SHED_GUARD_H (0, 48)`. The lower bound on LV is the typo guard (0.97 typed for 97) |
| `bin/claude-accounts` | New `cmd_shed_band(args, cfg)` beside `cmd_place` (`:6504`); dispatch in `main()` right after `--place` (`:11190-11191`) | `--shed-band --json`, cache-only (`get_data(max_wait=0)`, as `:6532`), so it can never sweep |
| `scripts/limit-recover/lr-shed.py` (new, stdlib, `/usr/bin/python3` 3.9-safe) | `main`, `tick`, `step_hysteresis`, `select`, `breaker_scan`, `strand_audit`, `report` | The controller (§6.3) |
| `scripts/limit-recover/lr-reset-poller.sh` | New `lrp_shed_kick()` after `lrp_evidence_gc_kick` (`:352-378`), called once per tick | A detached start, live layer only, single-flight; **not** under `taskpolicy` (§6.4) |
| `bin/cc-lr` | Globals `:1576-1578`; `cmd_move` plan write (`:1686-1690`) and intent write (`:1693-1701`) | Environment seams `CC_LR_MOVE_QUEUED_OUT`, `CC_LR_MOVE_ORIGIN`, `CC_LR_MOVE_HOLD_FOCUSED`; plan fields `origin`, `hold_focused`; intent field `origin` (§6.5) |
| `scripts/limit-recover/lr-move-worker.sh` | Plan reads (`:53-57`); `lr-handoff` invocation (`:429-438`) | `hold_focused: true` ⇒ `LR_MOVE_FOCUSED=off` for this actuation (`lr-lib.sh:1403-1420` then holds a focused pane as `HELD:focused`) |
| `scripts/limit-recover/lr_recon/__main__.py` | `:325` (`census.bucket` call) and `:710` (`_read_composer`) | D2a: the effective fan-out switch is `LR_IDLE_FANOUT=on` **or** `recon/idle-fanout.on` (§6.6) |
| `scripts/limit-recover/lr_recon/types.py` | `Paths` (beside `recon_autorecover_on`, `:333-340`) | `idle_fanout_on` path property |
| `tests/claude-accounts-shed-band.bats` (new), `tests/lr-shed.bats` (new), `tests/lr-shed-kick.bats` (new), `tests/cc-lr-move-origin.bats` (new), `scripts/limit-recover/lr_recon/tests/test_idle_fanout_switch.py` (new), `tests/fixtures/shed/` (new) | | §8 |
| `docs/plans/LIMIT_RECOVER_FLEET_V2.md` | Kill-switch list (`:136-152`) | Add `shed/mode`, `shed/breaker`, `recon/idle-fanout.on`, `LR_SHED`, `CC_ROUTE_SHED`. Record the ruling |
| `accounts.json` | router block | Optional `SHED_*` keys and a `_shed` note recording the ruling; the code defaults carry it |

### 6.2 Router: the band verdict (`bin/claude-accounts`)

```python
# after DISPATCH_CLAIM_TTL_MIN_DEFAULT (:6732)
# ── D2 (ruling <packet>, 2026-10-2x): the LATE warning band — idle sessions leave before the wall ──
# Replay of 7 walls (10-08..10-20, 43 limited sessions; docs/research/lr-sustained-load-2026-10-20/
# impl/D2-warning-band-shedding.md §3.3): LV 97 + guard 2 h avoided 15 at <=1.5 pp stranded in
# total; LV 90 without a guard avoided 24 and stranded 15.6-21.8 pp. Idle is not zero future burn:
# sessions at rest >= 30 min at 90% burned a median 18% of the band.
SHED_LV_OPEN_DEFAULT = 97.0      # weekly used % at which the band opens
SHED_TTW_OPEN_H_DEFAULT = 2.0    # ...or hours to the wall at the FAST pace
SHED_GUARD_H_DEFAULT = 2.0       # the SLOW pace must still wall this long before the reset

_SHED_KEYS = {"SHED_LV_OPEN": ("CC_ROUTE_SHED_LV_OPEN", SHED_LV_OPEN_DEFAULT),
              "SHED_TTW_OPEN_H": ("CC_ROUTE_SHED_TTW_OPEN_H", SHED_TTW_OPEN_H_DEFAULT),
              "SHED_GUARD_H": ("CC_ROUTE_SHED_GUARD_H", SHED_GUARD_H_DEFAULT)}


def shed_knob(R, key):
    env, default = _SHED_KEYS[key]
    return _dispatch_knob(env, R, key, default)      # env > SSOT > default, range-clamped


def shed_band_row(r, R):
    """D2 -> (token, facts). PURE: reads apply_burn's stamps, no I/O.
       off              CC_ROUTE_SHED=off
       out              used < SHED_LV_OPEN and the fast-pace wall is > SHED_TTW_OPEN_H away
       band             in the late band, and the SLOW pace still walls >= SHED_GUARD_H before
                        the reset: idle sessions (who add nothing to the measured pace) may leave
       band-guard       in the late band, but the slow pace lands the wall inside SHED_GUARD_H of
                        the reset, or never: shedding could strand, so nothing is shed
       hold-credits     extra usage is on: an overshoot is overage, not a wall
       unknown:<why>    level-stale | no-reset | pace-unknown | pace-stale. The controller
                        neither opens nor closes a band on it (our blindness is not a verdict)
    Every comparison is `not x >= y`, so a NaN reaching one is never 'band'."""
    if not _term_on("CC_ROUTE_SHED"):
        return "off", {}
    if r.get("stale_quota") or r.get("error"):
        return "unknown:level-stale", {}
    if r.get("credits_on"):
        return "hold-credits", {}
    used, wrh = weekly_used_frac(r), r.get("weekly_reset_h")
    if not _is_num(used) or not _is_num(wrh) or not (0 < wrh <= WEEK_H):
        return "unknown:no-reset", {}
    ewma, flat = r.get("burn_wk_ewma_ph"), r.get("burn_wk_flat_ph")
    if not _is_num(ewma):
        return "unknown:pace-unknown", {}
    if not _is_num(flat):
        return "unknown:pace-stale", {}          # flat is None when the ledger is > 1 h old
    left = max(0.0, 100.0 * (1.0 - used))
    hi, lo = max(ewma, flat), min(ewma, flat)
    ttw_hi = left / hi if hi > 0 else math.inf
    ttw_lo = left / lo if lo > 0 else math.inf
    facts = {"used_pct": round(100.0 * used, 2), "left_pp": round(left, 2), "reset_h": round(wrh, 2),
             "pace_hi": round(hi, 4), "pace_lo": round(lo, 4),
             "ttw_hi_h": None if ttw_hi == math.inf else round(ttw_hi, 2),
             "ttw_lo_h": None if ttw_lo == math.inf else round(ttw_lo, 2)}
    lv, tt, gh = (shed_knob(R, k) for k in ("SHED_LV_OPEN", "SHED_TTW_OPEN_H", "SHED_GUARD_H"))
    if not (100.0 * used >= lv or ttw_hi <= tt):
        return "out", facts
    if not ttw_lo <= wrh - gh:
        return "band-guard", facts
    return "band", facts


def cmd_shed_band(args, cfg):
    """--shed-band --json: the D2 verdict per account, and the recovery-lane targets that are not
    themselves in the band. CACHE-ONLY (max_wait 0), dispatched before the get_data anchor like
    --place, so it never sweeps. exit 0 answered · 3 WAIT_DATA (no servable cache)."""
    try:
        rows, wj, _c, _p = get_data(cfg, max_wait=0, max_age=cfg.get("cache_grace_s", 600))
    except CacheOnlyUnavailable:
        print(json.dumps({"v": 1, "wait_data": True}))
        return PLACE_EXIT_WAIT_DATA
    mark_self(rows, cfg); refresh_login_countdown(rows)
    apply_assignments(rows, cfg); apply_burn(rows, cfg)
    R, win = cfg["router"], win_from_json(wj)
    accts = []
    for r in rows:
        if r.get("acct") in (None, "none"):
            continue
        tok, f = shed_band_row(r, R)
        accts.append(dict(f, acct=r["acct"], verdict=tok))
    banded = {a["acct"] for a in accts if a["verdict"] in ("band", "band-guard")}
    out, reasons = _ranked(rows, cfg, win, "general", recovery=True)
    print(json.dumps({"v": 1, "ts": time.time(), "accounts": accts,
                      "targets": [r["acct"] for _s, r in out if r["acct"] not in banded],
                      "excluded": reasons,
                      "knobs": {k: shed_knob(R, k) for k in _SHED_KEYS}}, sort_keys=True))
    return 0

# main(), right after `if "--place" in args: sys.exit(cmd_place(args, cfg))` (:11190-11191):
#     if "--shed-band" in args:
#         sys.exit(cmd_shed_band(args, cfg))
```

Why the guard uses the **slow** pace: shedding removes sessions that add nothing to the *current*
pace. The question it must answer is whether the sessions still working alone exhaust the account
before its reset. The slower of the two estimators is the conservative answer. Why the trip uses
the **fast** pace: it is an early warning, and a false trip costs nothing while the guard holds.

### 6.3 The controller: `scripts/limit-recover/lr-shed.py`

**Paths and files** (all under `LR_STATE_DIR`, default `~/.reso/limit-recover`):
- `shed/mode`: written by the operator. Its first token is `off`, `shadow` or `on`; an absent file
  means off.
- `shed/breaker`: written by the controller.
- `shed/state.json`: written atomically (tmp, fsync, rename).
- `shed/decisions.jsonl`: one row ≤1 KB per decision, appended with a single `write()` and
  rotated at 4 MB to `.1`.
- `shed/run.pid`: the single-flight lock.
- `paged-once/`: shared with `lr-page-once.sh`.

**Seams:** `LR_SHED_CA_BIN`, `LR_SHED_CCLR_BIN`, `LR_SHED_PAGE_BIN`, `CC_UTIL_LOG`, `LR_SHED_NOW`
(tests).

```python
Q_S = env_int("LR_SHED_IDLE_S", 1800)          # at rest at least this long (the move lane's idle_s)
MAX_PER_TICK = env_int("LR_SHED_MAX", 4)       # per source account per tick
COOLDOWN_S = env_int("LR_SHED_COOLDOWN_S", 21600)   # a sid shed once is not re-shed for 6 h
TRIP_CONFIRM_S, RELEASE_CONFIRM_S = 300, 1200  # two looks >= 5 min apart open; >= 20 min apart close
BAND_TO, PLAN_TO, MOVE_TO = 60, 240, 300       # per-arm bounds
TICK_BUDGET_S = 900                            # > BAND_TO + PLAN_TO + MOVE_TO (one account), so the
                                               # first banded account can always finish (lesson:
                                               # inner bound must stay under the pass bound)

def effective_mode():
    if os.environ.get("LR_SHED", "on") == "off": return "off", "env"
    m = first_token(read(SHED/"mode")) or "off"
    if m not in ("off", "shadow", "on"): return "off", "bad-mode-file"
    if m == "on" and exists(SHED/"breaker"):        return "shadow", "breaker"
    if m == "on" and not exists(STATE/"autorecover.on"): return "shadow", "zero-human"   # D1.9
    return m, ""

def run(argv, timeout, env=None):
    # start_new_session=True; on timeout kill the GROUP, return (124, out, err)
    # 124/137 are OUR bound firing: "unknown, retry next tick" — never a verdict (REPORT §5 G2)

def tick(now):
    if not take_lock(): return 0                    # a live pid holds it; stale pid reaped
    mode, why = effective_mode()
    if mode == "off": return 0
    t0 = now
    rc, out, _ = run([CA, "--shed-band", "--json"], BAND_TO)
    band = parse(out) if rc == 0 else None
    if band is None or band.get("wait_data"):
        log(ev="band", verdict="unknown", cause=f"rc={rc}", mode=mode); return 0
    st = load_state()
    breaker_scan(st, now)                           # may write shed/breaker (and page once)
    strand_audit(st, now)                           # windows whose reset passed
    mode, why = effective_mode()                    # the breaker may have just tripped
    for a in band["accounts"]:
        w = window(st, a, now)                      # key: acct + reset rounded to the minute
        step_hysteresis(w, a["verdict"], now)       # pure
        log(ev="band", acct=a["acct"], verdict=a["verdict"], open=w["open"], **brief(a), mode=mode, why=why)
        if not (w["open"] and a["verdict"] == "band"):
            continue                                # the guard is re-read EVERY tick
        if time.time() - t0 > TICK_BUDGET_S - (PLAN_TO + MOVE_TO):
            log(ev="budget", acct=a["acct"]); break
        tgt = [t for t in band["targets"] if t != a["acct"]]
        if not tgt: log(ev="no-target", acct=a["acct"]); continue
        if inflight(st, a["acct"]): log(ev="in-flight", acct=a["acct"]); continue
        rc, out, _ = run([CCLR, "plan", "--from", a["acct"], "--to", tgt[0], "--json"], PLAN_TO)
        rows = (parse(out) or {}).get("rows") if rc == 0 else None
        if rows is None: log(ev="census", acct=a["acct"], verdict="unknown", cause=f"rc={rc}"); continue
        picks = select(rows, st, now)               # pure
        log(ev="pick", acct=a["acct"], target=tgt[0], cands=len(rows), picks=[p["sid"][:8] for p in picks], mode=mode)
        if mode != "on" or not picks:
            continue                                # SHADOW ends here: would-shed is on disk
        qf = mktemp()
        rc, out, err = run([CCLR, "move", "--from", a["acct"], "--sids", ",".join(p["sid"] for p in picks),
                            "--to", tgt[0], "--wait", "0"], MOVE_TO,
                           env={"CC_LR_MOVE_ORIGIN": "shed", "CC_LR_MOVE_HOLD_FOCUSED": "1",
                                "CC_LR_MOVE_QUEUED_OUT": qf})
        batch = read(qf).strip()
        if batch:
            w["sheds"] += len(picks)
            st["batches"].append({"batch": batch, "acct": a["acct"], "to": tgt[0], "ts": now,
                                  "sids": [p["sid"] for p in picks], "settled": False})
            for p in picks: st["cooldown"][p["sid"]] = now
        log(ev="move", acct=a["acct"], batch=batch or None, rc=rc, err=err[-200:])
    save_state(st)
    return 0

def step_hysteresis(w, v, now):                     # Release is NOT !trip (rules: release-predicate)
    if v.startswith("unknown") or v == "off":
        w["unknown_n"] += 1; return                 # our blindness neither opens nor closes
    if not w["open"]:
        if v == "band":
            w["trip_at"] = w["trip_at"] or now
            if now - w["trip_at"] >= TRIP_CONFIRM_S: w.update(open=True, opened_at=now)
        else:
            w["trip_at"] = None
    else:
        if v in ("band-guard", "out", "hold-credits"):
            w["fail_at"] = w["fail_at"] or now
            if now - w["fail_at"] >= RELEASE_CONFIRM_S: w.update(open=False, closed_at=now, closed_by=v)
        else:
            w["fail_at"] = None

def select(rows, st, now):
    ok = [r for r in rows
          if r.get("act") == "move" and r.get("disposition") == "move"      # never a draft carry
          and isinstance(r.get("idle_s"), int) and r["idle_s"] >= Q_S
          and now - st["cooldown"].get(r["sid"], 0) >= COOLDOWN_S]
    ok.sort(key=lambda r: (r.get("cache") != "cold", -r["idle_s"]))   # cold cache first: free to move
    return ok[:MAX_PER_TICK]

def breaker_scan(st, now):
    for b in st["batches"]:
        if b["settled"]: continue
        verdicts = read_verdicts(STATE/"move"/b["batch"])      # <sid>.json, skipping plan/admit/summary/watcher
        bad = [(s, v) for s, v in verdicts.items() if v in ("STRANDED", "FAILED")]
        if bad:
            write_atomic(SHED/"breaker", json.dumps({"batch": b["batch"], "casualties": bad, "ts": now}))
            page_once(f"shed-casualty-{b['batch']}", "D2 shed casualty",
                      f"shed batch {b['batch']}: {bad[0][0][:8]} {bad[0][1]}; shed is now shadow-only. "
                      f"Read: cc-lr move --status {b['batch']}. Clear: rm {SHED}/breaker")
        if summary_settled(STATE/"move"/b["batch"]): b["settled"] = True

def strand_audit(st, now):
    for key, w in st["windows"].items():
        if w["audited"] or w["reset_at"] > now - 600: continue
        final = last_ledger_level(w["acct"], before=w["reset_at"])     # tail read, CC_UTIL_LOG seam
        w.update(audited=True, final_pct=final)
        if w["sheds"] > 0 and final is not None and final < 99:
            log(ev="strand-audit", acct=w["acct"], final=final, sheds=w["sheds"])
            if os.environ.get("LR_SHED_STRAND_BREAKER", "on") != "off":
                write_atomic(SHED/"breaker", json.dumps({"strand": key, "final": final, "ts": now}))
            page_once(f"shed-strand-{key}", "D2 shed strand",
                      f"{w['acct']} closed its week at {final}% after {w['sheds']} shed move(s); "
                      f"up to {100 - final} pp may have stranded. Shed is now shadow-only. Clear: rm {SHED}/breaker")
    prune(st, now)                                   # windows > 7 d past reset, settled batches > 7 d

# CLI: lr-shed.py --tick | --report [--json] | --status
```

`--report` prints one line per window: account, reset, `opened_at`, sheds, the shed batches'
verdict counts, the final level and the closing token. This is the shadow-review surface for §9
step 2.

### 6.4 The poller kick (`scripts/limit-recover/lr-reset-poller.sh`)

The kick is the `lrp_evidence_gc_kick` pattern (`:352-378`), minus `taskpolicy`. The shed's
`cc-lr plan` census must run at priority 31: band 20 is 7-111x slower at this load (`REPORT.md`
§3.1).

```bash
# ── D2: THE LATE-BAND SHED (ruling <packet>) ─────────────────────────────────────────────────────
# Started DETACHED (it must not lengthen the tick, and a census can take minutes), ONLY by the live
# layer (the evidence-GC lesson: test ticks started 133 copies), one at a time, at most every
# LR_SHED_EVERY_MIN. NOT under taskpolicy: the shed's census and kitty reads must inherit this job's
# Interactive band (priority 31). Nothing at all happens while shed/mode is absent.
lrp_shed_kick() {
  local m="$STATE/shed/mode" stamp="$STATE/shed/kick.stamp" pidf="$STATE/shed/run.pid" py="$LR/lr-shed.py"
  local live det="" d pid
  [[ "${LR_SHED:-on}" != off && -f "$m" ]] || return 0
  [[ ! -e "$stamp" ]] || [[ -n "$(find "$stamp" -mmin +"${LR_SHED_EVERY_MIN:-9}" 2>/dev/null)" ]] || return 0
  live="$(/usr/bin/readlink -f "$HOME/.claude/scripts/limit-recover/lr-shed.py" 2>/dev/null)"
  if [[ -z "$live" || "$(/usr/bin/readlink -f "$py" 2>/dev/null)" != "$live" ]]; then
    log "SHED-SKIP $py is not the deployed layer's lr-shed.py; only the live poller starts the shed"; return 0
  fi
  pid="$(cat "$pidf" 2>/dev/null)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then log "SHED-SKIP the previous run (pid $pid) is still going"; return 0; fi
  if [[ $DRY -eq 1 ]]; then log "DRY   shed would start: python3 $py --tick"; return 0; fi
  for d in "$LR/../lib/detach.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/detach.sh" "$HOME/.claude/scripts/lib/detach.sh"; do
    [[ -f "$d" ]] && { det="$d"; break; }
  done
  [[ -n "$det" ]] || { log "SHED-SKIP scripts/lib/detach.sh unreachable"; return 0; }
  mkdir -p "$STATE/shed" 2>/dev/null; : > "$stamp" 2>/dev/null || true
  # shellcheck disable=SC1090  # runtime-resolved sibling
  pid="$( . "$det" && detach "$STATE/shed/shed.log" /usr/bin/env LR_STATE_DIR="$STATE" /usr/bin/python3 "$py" --tick 2>/dev/null )" || pid=""
  if [[ "$pid" =~ ^[0-9]+$ ]]; then printf '%s\n' "$pid" > "$pidf" 2>/dev/null; log "SHED-KICK started pid $pid"
  else log "SHED-KICK could not be started (retried next tick)"; fi
  return 0
}
lrp_shed_kick
```

`lr-shed.py` also takes `run.pid` itself, comparing pid and `lstart` (`lr-claim-lstart` rule), so
a detached start racing a manual `--tick` cannot double-run. The poller's own cadence is 10.7 min
p50 (M10). Each band has 0.9-2.2 h of lead at p25-median (M2), so 5-12 ticks see the band before
the wall.

### 6.5 Move-lane seams (`bin/cc-lr`, `lr-move-worker.sh`)

```bash
# bin/cc-lr:1576-1578 — today these are plain globals reset at load, so no caller can pass them
CL_MOVE_EXCL=""
CL_MOVE_QUEUED_OUT="${CC_LR_MOVE_QUEUED_OUT:-}"   # a file path: a real run writes its batch id there
CL_MOVE_NO_STATUS_ROW="${CC_LR_MOVE_QUEUED_OUT:+1}"
CL_MOVE_ORIGIN="${CC_LR_MOVE_ORIGIN:-}"           # "shed" for the D2 controller; empty = an operator
CL_MOVE_HOLD_FOCUSED="${CC_LR_MOVE_HOLD_FOCUSED:-}"

# cmd_move plan.json (:1686-1690): + origin and hold_focused, only when set (byte-identical otherwise)
   ... + (if $origin != "" then {origin:$origin} else {} end)
       + (if $hf == "1" then {hold_focused:true} else {} end)
# intent (:1693-1701): + (if $origin != "" then {origin:$origin} else {} end)

# lr-move-worker.sh, after :57
HOLD_FOCUSED="$(jq -r '.hold_focused // false' "$PLAN" 2>/dev/null)"
# :429-438, in the env list of the lr-handoff call
      ${HOLD_FOCUSED:+$( [ "$HOLD_FOCUSED" = true ] && printf 'LR_MOVE_FOCUSED=off' )} \
```

The worker change needs care with bash 3.2's `$( )` parsing (the 3.2 lesson). The safe form
assigns `FOCUS_ENV=()` beforehand and expands `"${FOCUS_ENV[@]}"` in the `env` list. A
`HELD:focused` result is `NOTMOVED`, and the next tick re-plans it.

**Why not a new move verb:** `cmd_move` stays the one writer of `plan.json` and intent files. The
batch runner keeps its strict router read at admit, which also confirms the target. The worker
keeps its at-rest re-check, the claims, the abort, and `LR_MOVE_LANE=off`.

### 6.6 D2a: the at-wall idle fan-out switch (`lr_recon`)

```python
# types.py, Paths, beside recon_autorecover_on (:333-340)
    @property
    def idle_fanout_on(self) -> str:
        """recon/idle-fanout.on: the operator's switch for idle fan-out (D2 ruling). A FILE, read
        every pass, so turning it on or off needs no plist edit and no restart."""
        return self.p("idle-fanout.on")

# __main__.py
def fanout_env(paths: T.Paths) -> Mapping[str, str]:
    if os.path.exists(paths.idle_fanout_on) and os.environ.get("LR_IDLE_FANOUT", "") != "off":
        return dict(os.environ, LR_IDLE_FANOUT="on")
    return os.environ
# :325   b = census.bucket(s, snap, facts, now, env=fanout_env(paths))   (computed once per pass)
# :710   use the same mapping instead of os.environ in _read_composer
```

An explicit `LR_IDLE_FANOUT=off` in the environment still wins, so it stays the hard kill. The
zero-human gate is unchanged: fan-out records act only with `recon/autorecover.on`
(`census.py:345-349`, `__main__.py:225-231`), which exists.

### 6.7 Data and format changes

| Item | Change | Compatibility |
|---|---|---|
| `claude-accounts --shed-band --json` | New: `{v:1, ts, accounts:[{acct, verdict, used_pct, left_pp, reset_h, pace_hi, pace_lo, ttw_hi_h, ttw_lo_h}], targets:[…], excluded:{…}, knobs:{…}}`, or `{v:1, wait_data:true}` with exit 3 | New flag; nothing else changes |
| `accounts.json` router | Optional `SHED_LV_OPEN`, `SHED_TTW_OPEN_H`, `SHED_GUARD_H` | Range-checked only when present (`_validate_router`) |
| `move/<batch>/plan.json` | Optional `origin`, `hold_focused` | Absent ⇒ byte-identical to today |
| `move/<batch>/intent/<sid>.json` | Optional `origin` | `lr-intent.sh` checks owner, mode, path, binding and expiry, not extra keys (hypothesis to verify in the test) |
| `~/.reso/limit-recover/shed/` | New dir: `mode` (operator), `breaker`, `state.json`, `decisions.jsonl`(+`.1`), `run.pid`, `kick.stamp`, `shed.log` | New |
| `~/.reso/limit-recover/recon/idle-fanout.on` | New operator switch file (D2a) | Absent ⇒ today's behaviour |

`state.json` shape: `{v:1, windows:{"<acct>:<reset_min>": {acct, reset_at, open, trip_at, fail_at,
opened_at, closed_at, closed_by, sheds, unknown_n, audited, final_pct}}, batches:[{batch, acct, to,
ts, sids, settled}], cooldown:{sid: ts}}`.

## 7. Failure modes under permanent 15-40/core load

| Failure | What happens | Handling |
|---|---|---|
| `--shed-band` slow or stuck (Python start, ledger tail, cache) | A priority-31 `--rank` from the cache took 2.1-8.1 s at about 22/core (wave 5, `9d6cd03ff`); estimated ~15 s at 40/core | Bound 60 s. rc 124 ⇒ an `unknown` row, **no** open, close or move; retried next tick. Never "out" |
| No servable cache (exit 3) | The keepwarm sweep is stalled | `unknown`, retry. The controller never forces a sweep |
| Ledger over 1 h old | `burn_wk_flat_ph` is `None` (`:5373-5396`) | `unknown:pace-stale`; the band state is held, not changed |
| `cc-lr plan` census slow (kitty and composer reads, a jq per row) | 3.0-3.4 min under load before the prefilter, at priority 20 (`lr-upgrade.sh:1058-1063` comment) | Bound 240 s, with the tick budget (900 s) above the per-account arms. Timeout ⇒ `unknown` for that account, retried next tick |
| A composer read fails (kitty slow, or at priority 4 with the screen locked: B8) | The census says `composer-unknown` ⇒ `act=hold` | Not selected. The shed only ever under-acts on blindness |
| The session starts a turn between plan and actuation | The worker re-checks at rest; with `until_idle 0` it ends `NOTMOVED`/`still-busy` | Cooldown is set only on a queued batch; the next tick may pick it again once it rests ≥30 min |
| Focused pane | `hold_focused` ⇒ `LR_MOVE_FOCUSED=off` ⇒ `HELD:focused` at the pre-exit gate (`lr-lib.sh:1403-1420`) | `NOTMOVED`, retried next tick |
| Router refuses the target at admit | The batch is refused (`lr-move-batch.sh`, strict) | All rows `NOTMOVED`; next tick re-reads targets |
| Shed target walls soon itself | The band's `targets` exclude every `band`/`band-guard` account; recovery floors exclude <10% headroom | 3e929a81's three walls in four days (M6) are the pattern this avoids |
| Two drivers on one session (reconciler fan-out or R, poller, move lane) | Per-session claims by (pid, lstart): the batch takes one claim per row (`lr-move-batch.sh` header), and the reconciler's `may_actuate`/`hold_claim` refuses a live foreign claim (`act.py:438-526`) | A regression test pins it (§8 T5) |
| Move casualty (`STRANDED`/`FAILED`) | M8: 25 of 66 actuated rows since 10-06 | `breaker_scan` writes `shed/breaker` ⇒ shadow; pages once. The operator clears it after review |
| Strand (the account closes its week below 99% after sheds) | Simulated ≤0.2 pp per wall | `strand_audit` pages once and trips the breaker (default on). The guard is re-read every tick, so the band stops shedding the moment the slow pace no longer walls ≥2 h early |
| Controller crash mid-tick | `run.pid` dead | The next kick reaps it (pid and lstart). State writes are atomic, so a crash loses at most one tick's log rows |
| Poller not ticking | No kicks | The reconciler backup watchdog and its pages are unchanged; the shed has hours of slack and is optional work |
| Clock or reset key jitter | A window key flips | The key uses the minute-rounded reset (`_reset_key`'s rule, `bin/claude-accounts:4587-4600`); unknown keys only add a window |
| Daemon restart (A6) | Unaffected: the shed has no daemon. D2a needs one reconciler restart to load its code | Schedule it outside a cohort (A6 i) |
| Load figure | Never read. No decision reads `load1` or `vm.loadavg` | Invariant G1 holds (`REPORT.md` §5). A test greps `lr-shed.py` for `getloadavg`, `vm.loadavg` and `load1` |

## 8. Test plan

Every suite runs under `/bin/bash` 3.2 and `/usr/bin/python3` 3.9, the deployment interpreters.
Every new suite asserts its plan line `1..N` (rules: "Gate refusal ≠ gate result").

**T1 `tests/claude-accounts-shed-band.bats`** loads the module like `account-recovery-lane.bats`
`$LOAD` and seals `CC_UTIL_LOG` to a fixture.

- **[RED] incident replay.** The fixture `tests/fixtures/shed/next3-20261019.jsonl` holds the
  ledger slice 10-19T08Z to 10-20T03Z (next3 only, about 400 rows). With `time.time` pinned:
  - at 18:00Z ⇒ `out`;
  - at 01:20Z (97%) ⇒ `band`, `guard` ok;
  - `--shed-band --json` lists next3 absent from `targets`.

  On trunk the flag does not exist and `shed_band_row` is absent: red.
- **Guard.** The next 10-11 slice at 02:30Z (wall 0.9 h before the 04:00Z reset) ⇒ `band-guard`.
  **Mutant m1:** the guard reads `pace_hi` ⇒ `band`; the test must die.
- **Boundary.** Exactly 97.0 ⇒ `band`. **Mutant m2** (`>` for `>=`) dies.
- **NaN or None pace** ⇒ `unknown:*`, never `band`. **Mutant m3** (`min()` dropping NaN) dies.
- Ledger 61 min old ⇒ `unknown:pace-stale`. `credits_on` ⇒ `hold-credits`. `stale_quota` ⇒
  `unknown:level-stale`.
- `CC_ROUTE_SHED=off` ⇒ every verdict `off`, and `--rank` output stays byte-identical (the strand
  rescue's kill-switch style).
- **Cache-only.** With the cache file absent: exit 3, `{"wait_data":true}`, and no sweep. A
  `get_data` spy asserts `max_wait=0`.
- Range: `SHED_LV_OPEN 0.97` in the SSOT is refused by `_validate_router`.

**T2 `tests/lr-shed.bats`** drives `lr-shed.py --tick` with fake `claude-accounts` and `cc-lr`
stubs that record argv and env.

- **[RED] the incident's two late idles.**
  - Setup: band `band` for next3, targets `[next2, next4]`, mode `on`, `autorecover.on` present.
  - Plan rows: 3d1d988a (`idle_s` 2820, `move`/`move`); 769b7294 (`idle_s` 300); a draft row
    (`act=move`, `disposition=draft`); a `hold:mid-turn` row.
  - Expected: exactly one `cc-lr move --from next3 --sids 3d1d988a… --to next2 --wait 0` with
    `CC_LR_MOVE_ORIGIN=shed` and `CC_LR_MOVE_HOLD_FOCUSED=1`; a batch recorded; cooldown set.
  - On trunk: no controller, so red.
- **Mutants.**
  - m4 drops the idle filter, so 769b7294 is picked: the test must die.
  - m5 selects `disposition=draft`: dies.
  - m6 moves in `shadow`: dies.
  - m7 ignores `autorecover.on`: dies.
  - m8 treats a `--shed-band` timeout as `out` (closing an open band): dies, by the T2 hysteresis
    case.
- **Shadow.** `decisions.jsonl` gets a `pick` row with the would-shed sids; the `cc-lr move` stub
  is never called.
- **Zero-human.** Mode `on` without `autorecover.on` ⇒ behaves as shadow, `why=zero-human`.
- **Hysteresis.**
  - One `band` look does not open; two looks ≥300 s apart do.
  - One `band-guard` does not close; two looks ≥1200 s apart do.
  - An `unknown` between them changes nothing.
  - Per-tick: an open window whose current verdict is `band-guard` sheds nothing.
- **Timeout = unknown.** The `claude-accounts` stub sleeps past `BAND_TO` (seam
  `LR_SHED_BAND_TO=2`): exit 0, one `unknown` row, no state change, no move.
- **In flight.** A batch without `summary.json` for the source means no second batch.
- **Breaker.**
  - A shed batch whose `<sid>.json` says `STRANDED` writes `shed/breaker`.
  - The next tick in mode `on` behaves as shadow.
  - The page stub is called once across 3 ticks.
- **Strand audit.** A fixture ledger closes the window at 96 with `sheds=2`: one page, an audit
  row, and the breaker. At 100: nothing.
- **Lock.** A live `run.pid` (this test's own `sleep` child) makes a second `--tick` a no-op; a
  dead pid is reaped.
- **G1 lint.** `grep -nE 'getloadavg|vm\.loadavg|load1' lr-shed.py` finds nothing.

**T3 `tests/lr-shed-kick.bats`** (the `tests/lr-evidence-gc.bats` poller cases are the model):

- [RED] a non-live copy never starts the shed;
- mode file absent ⇒ no start and no log line;
- a live `run.pid` ⇒ skip;
- `--dry-run` ⇒ the DRY line only;
- the live layer's tick starts ONE detached process that outlives the tick, with no `taskpolicy`
  in its argv;
- the stamp throttles to `LR_SHED_EVERY_MIN`.

**T4 `tests/cc-lr-move-origin.bats`:**

- `CC_LR_MOVE_ORIGIN=shed` and `CC_LR_MOVE_HOLD_FOCUSED=1` produce `origin` and `hold_focused` in
  `plan.json` and `origin` in each intent;
- unset, `plan.json` is byte-identical to trunk's for the same rows;
- `CC_LR_MOVE_QUEUED_OUT` receives the batch id;
- the worker passes `LR_MOVE_FOCUSED=off` to a stub `lr-handoff` when `hold_focused` is true, and
  not otherwise;
- `lr-intent.sh` accepts an intent carrying `origin` (this pins the §6.7 hypothesis).

**T5 `lr_recon/tests/test_idle_fanout_switch.py`:**

- [RED] with `recon/idle-fanout.on` present and `LR_IDLE_FANOUT` unset, an at-rest,
  empty-composer, unfocused session under an uncontradicted 7d fact buckets `IDLE-ELIGIBLE`; on
  trunk it is `WORKING "no idle fan-out"`;
- `LR_IDLE_FANOUT=off` beats the file;
- the composer read happens only when the switch is on (a count of `observe.composer_state`
  calls);
- a record with a live move-lane claim is refused by `may_actuate`, which is the two-driver
  regression.

**T6 under load (needs B1).** Run one `lr-shed.py --tick` against the rig, with the B1 band mix
at 25 and 40 per core. Record beside each reading load1, the runnable census by base priority,
the shed's own `ps -M` priority, and kitty's priority (rule "Verify a cure under its load").
Assert:

- the tick completes within `TICK_BUDGET_S`;
- its processes read base priority ≥31;
- a forced census timeout yields an `unknown` row and no move.

The red arm runs the same tick under `taskpolicy -c utility` and must breach the budget. Policy
itself, meaning burn and strand, is not testable in the rig: B1 has no burn model
(`B1-load-harness.md:709`).

**T7 replay evaluator, before `on`:** `/tmp/d2/burn2.py` re-run over the shadow period's
transcripts. Shadow's `pick` rows are then compared with the sessions that actually hit the limit,
which gives a measured "would have avoided / would have stranded" in place of §3.3's simulation.

## 9. Rollout, kill switches and operator steps

| Step | Who | Exact command | Exit criterion |
|---|---|---|---|
| 0 | Agent | Land via `/ship`; converge per the repo's standing rule | Suites T1-T5 green; `shed/mode` absent, so behaviour is byte-identical (`--shed-band` is a new flag only; the kick returns before anything when the file is absent) |
| 1 | Operator | `mkdir -p ~/.reso/limit-recover/shed && printf 'shadow\n' > ~/.reso/limit-recover/shed/mode` | `python3 ~/.claude/scripts/limit-recover/lr-shed.py --report` shows `band` rows for next2 and next at their next walls (M2b) |
| 2 | Agent | `python3 ~/.claude/scripts/limit-recover/lr-shed.py --report --json` plus the T7 replay over the shadow period | Shadow picks that later went limited ≥1 per wall; replayed strand ≤0.5 pp per wall; 0 picks that were focused or had drafts |
| 3 | Operator (ruling Q1/Q2) | `printf 'on\n' > ~/.reso/limit-recover/shed/mode` | First on-mode wall: 0 casualties; `--report` final level ≥99 |
| 3a | Operator (ruling Q3) | `touch ~/.reso/limit-recover/recon/idle-fanout.on`, after the D2a code is loaded by one reconciler restart outside a cohort (A6) | Fan-out records appear (`events.jsonl` `rebucket` to `IDLE-ELIGIBLE`) only on accounts with a death fact |

**Kill switches, all on the safe side:**

| Switch | Effect |
|---|---|
| `rm -f ~/.reso/limit-recover/shed/mode` | Everything off at the next tick (the kick returns before starting Python) |
| `printf 'shadow\n' > ~/.reso/limit-recover/shed/mode` | Logs only |
| `~/.reso/limit-recover/shed/breaker` | Written by the controller on a casualty or strand. While present, mode `on` acts as shadow. Clear with `rm -f ~/.reso/limit-recover/shed/breaker` |
| `CC_ROUTE_SHED=off` | Every verdict `off` |
| `LR_SHED=off` | Kick and controller do nothing (environment; the file is the primary switch) |
| `LR_MOVE_LANE=off` | The whole move lane refuses |
| In-flight batches | Stopped with `cc-lr move --abort <batch>`; ids are in `shed/state.json` and in `decisions.jsonl` `move` rows |
| D2a | `rm -f ~/.reso/limit-recover/recon/idle-fanout.on` |

## 10. Estimated size

Estimated by function count against similar landed code: the dispatch floor and strand rescue
(`aa98726b1`), and `lrp_evidence_gc_kick` (`:352-378`).

| Part | LOC |
|---|---|
| `bin/claude-accounts` (`shed_band_row`, `cmd_shed_band`, knobs, ranges, dispatch, docstrings) | ~150 |
| `scripts/limit-recover/lr-shed.py` | ~380 |
| `lr-reset-poller.sh` `lrp_shed_kick` | ~35 |
| `bin/cc-lr` seams and fields | ~15 |
| `lr-move-worker.sh` | ~6 |
| D2a (`types.py`, `__main__.py`) | ~20 |
| Docs (`LIMIT_RECOVER_FLEET_V2.md`, `accounts.json` note) | ~40 |
| Tests T1-T5 and fixtures | ~850 |
| **Total** | **~1,500** (≈650 code, ≈850 tests) |

## 11. Dependencies on other items

| Item | Relation |
|---|---|
| A2, A3, A1 (landed) | **Hard, met.** No load wait in the move worker (`9316d9842`); our timeouts retry; the rail and poller at priority 31, which the shed inherits |
| A7-limited-cohort-ruling | **Met for D2a.** `recon/autorecover.on` exists since 17:10:32Z. D2b gates on the global `autorecover.on` (exists) plus its own `shed/mode` |
| B1-load-harness | **Soft, before `on`.** T6 needs it to show the tick bounded and at priority ≥31 at 25-40/core. It cannot test the policy (no burn model) |
| D1-repick-ruling | **Complementary; shared risk.** D1 moves recycles off held accounts, D2 moves idle sessions off banded ones; both remove burn from the walling account. The strand audit judges the account's final level, so it covers both. Ship D1 first or together; D2's guard reads the measured pace, which already reflects D1 |
| A6-restart-safety | Soft, D2a only: loading D2a needs one reconciler restart, which should be outside a cohort |
| B8-kitty-hygiene, B5-kitty-off-critical-path | Soft. A priority-4 kitty with the screen locked makes composer reads fail, so the shed abstains (fails safe, does less). B5's `kitten @ ls` path would make the census cheaper |
| B6-telemetry | Independent. `shed/decisions.jsonl` is its own log and can feed B6's readout |
| G2-self-recovery, C1-credential-flip, C2-socket-prompt | Each lowers the cost of a limited session, and so D2's value. C1, if it ever ships, makes per-session moves moot |
| B2, B3, B4, B7 | None. D2 adds no record to the recovery queue and reads no pass clock |

## 12. Risks and open questions

1. **The actuator's casualty rate after the waves is unmeasured** (M8, M9). This is the largest
   risk. Shadow plus the breaker contain it, but the first `on` wall is still a live trial.
2. **Attribution noise.** Calibration spread is about 2-3x per account-day, and the attribution
   of transplanted calls is a heuristic. The frontier's ordering (LV 90 ≫ 95 > 97 > 99 in
   strand) holds in every window; the absolute pp are ±2x (estimated).
3. **Residency is not on disk.** The simulation's shed counts include exited sessions; the real
   move count per wall is bounded by `k` (median 8, max 23, M1). The cap of 4 per tick and the
   6 h cooldown bound the rail load in any case.
4. **"Idle ≥30 min" from `idle_s`** is transcript-mtime age (`bin/cc-lr:1294-1300`). A hook write
   resets it, so the shed under-acts, which is the safe direction.
5. **Warm-cache cost.** A session idle 30-60 min still has its 1 h prompt cache. Moving it costs
   one context re-write on the target. Estimated about 0.05-0.3 pp of the target's week per warm
   move (200-400k context × 1.25-2.0 weight × 0.15-0.5 pp per M weighted tokens). The selection
   orders cold first.
6. **Surprise.** The operator sees idle panes restart on another account. Ruling Q1 is exactly
   this. `VOLUNTARY_ACCOUNT_SWITCH.md` §8a made the account visible on the pane, which helps.
7. **Interaction with the strand rescue.** If sheds pushed the forecast strand to ≥4 pp, the
   router would lift the account and send new fires back. The 2 h guard and the 97% trigger keep
   the remaining points under 3 pp, so a lift cannot be triggered by sheds alone (estimated).

## Appendix A. Commands run

All read-only, or writing only under `/tmp/d2/`.

| Command | What it established |
|---|---|
| `python3 -I /tmp/d2/windows.py` | M1, M2: 41 windows, wall leads, the rule backtests including `late` |
| `python3 -I /tmp/d2/files.py` | 2,105 transcript files with mtime ≥ 10-07 across 4 config dirs (`.jsonl` and `.jsonl.handed-off*`, main and subagent) |
| `python3 -I /tmp/d2/parse.py` | `/tmp/d2/msgs.tsv` (121,836 occurrences, 113,215 ids) and `stops.tsv` (stop reasons), with byte-offset bisection to 10-07 |
| `P1LAG=20\|60 SIML=20\|45 python3 -I /tmp/d2/burn2.py` | M3-M6: calibration, per-session burn, the shed frontier, at-wall fan-out, per-session detail. Outputs `/tmp/d2/sim_lag20.txt`, `sim_lag60.txt`, `sim_L45.txt` |
| `jq` over `~/.reso/limit-recover/move/2026*/<sid>.json` | M8 (`/tmp/d2/move_verdicts.tsv`) |
| `grep TICK ~/.reso/limit-recover/poller.log` (python gap stats) | M10 |
| python read of the newest ledger rows | M2b |
| `stat -f '%Sm' ~/.reso/limit-recover/{,recon/}autorecover.on` | Zero-human files present (global 2026-09-29, recon 2026-10-20 12:10:32-0500) |
| `plutil -p` of the reconciler and poller plists | No `LR_IDLE_FANOUT`; poller `StartInterval 600`, `ProcessType Interactive` |
| `sed`/`grep` of `bin/claude-accounts`, `bin/cc-lr`, `lr-reset-poller.sh`, `lr-move-*.sh`, `lr-lib.sh`, `lr_recon/{census,__main__,act,facts,types}.py` at `28b25a119` | Every `file:line` cited |

## Appendix B. Deviations from the brief

- Two scratch writes used a shell heredoc instead of the Write tool:
  - `cat > /tmp/d2/probe_shape.py <<EOF`;
  - one `python3 - <<EOF` no-op.

  Both were under `/tmp` only. Every other script was written with the Write/Edit tools. Nothing
  outside `/tmp/d2/` and this file was written.
- No code was edited; nothing was typed into a pane, signalled, loaded or reloaded.

## Review — correctness-and-safety

Adversarial review, 2026-10-20, against `28b25a119` (this worktree's HEAD). It is read-only: the
only writes were this section and two throwaway interpreter runs that wrote nothing. The lens asks
whether the design could strand a session, move one twice, lose a draft, split-brain, break an
invariant or break an existing test. The repo rules were read first (`.claude/rules/*.md`). The
lessons that apply are "Deployment interpreter ≠ yours", "Inner bound starves the tail",
"Release ≠ !trip", "Hardcoded pid is no constant", "Detached bash is reaped at 10 min" and
"Green in both arms".

**Verdict: NEEDS-CHANGES.** The architecture is sound:
- a controller outside the reconciler, because the fact model forbids forecasts (`lr_recon/facts.py:1-12`);
- shadow mode first;
- the move lane as actuator, with its per-session claims (`lr-move-batch.sh:13`), the reconciler
  fence (`lr-move-worker.sh:123-128`) and the operator-intent validator.

But the sketch as written has these defects:
- three that defeat the controller outright (D1, D2, D5);
- one that breaks every move-lane worker, operator moves included (D6);
- several that let the shed act outside its stated scope or past its own kill switches (D7-D10).

The OPERATOR verdict on policy (Q1-Q5) stands. Nothing below changes it.

### What checks out (spot-verified)

All of these were verified with `sed -n`/`grep -n` at `28b25a119`:
- the rule text `bin/cc-lr:1801` and the ruling `bin/claude-accounts:3890-3892`;
- `cl_acct_cap` `w >= 100` (`bin/cc-lr:517-531`) and `recovery_floors` (`:3942`);
- `dispatch_floor_row` (`:6770`), `_dispatch_partition` (`:6851`), the knob block (`:6720-6732`) and `ROUTER_OPTIONAL_RANGES` (`:437-457`);
- `cmd_place` cache-only (`:6531-6532`), the `--place` dispatch (`:11190-11191`) and `apply_burn` (`:4842`, flat pace `:5373-5396`);
- `_reset_key` (`:4587-4600`);
- the move-lane globals (`bin/cc-lr:1576-1578`) and the `plan.json`/intent writes (`:1685-1701`);
- the worker's plan reads (`lr-move-worker.sh:53-57`) and the handoff env list (`:429-438`);
- the focus gate (`lr-lib.sh:1403-1420`);
- `census.py:8-9,27,271-299`, `__main__.py:225-231,325,710`, `types.py:333-340` and `act.py:78-84,126-127`;
- the evidence-GC kick (`lr-reset-poller.sh:352-378`) and the `autorecover.on` gate (`:2464`).

`ls -t ~/.reso/limit-recover/move/ | head -1` => `20261020T030423Z-next3-next2-15173`, which
confirms M9. `ls ~/.reso/limit-recover/recon/idle-fanout.on` => no such file, and `shed/` is
absent, so nothing in this design is live.

### Defects (each with evidence and the required change)

**D1. The controller locks itself out (the run.pid has two writers).**
- *Evidence.* `detach` prints the pid of `/usr/bin/env`, which execs python, so it is the
  controller's own pid (`scripts/lib/detach.sh:27-34`). §6.4 writes that pid to `shed/run.pid`
  right after `detach` returns, which is before a loaded python reaches its `take_lock`. §6.3
  `take_lock` then reads its own live pid and returns ("a live pid holds it").
- *Consequence.* Every tick is a no-op.
- *Second problem.* The kick's own check is `kill -0` alone. This box "wraps the whole 99999-pid
  space in ~41 min" (`bin/cc-reaper:621-623`), so a recycled pid held by a long-lived process makes
  the kick skip for as long as that process lives.
- **Change:**
  - give the lock one writer: the controller, with O_EXCL plus `(pid, lstart)`;
  - the kick either writes a different file or does not check the pid at all, and lets python
    refuse a second run;
  - any liveness read compares `lstart`, as the poller's own lock does (`lr-reset-poller.sh:274-289`).

**D2. "Settled" and "in flight" are keyed on the wrong file, so the breaker misses late casualties.**
- *Evidence.* `summary.json` is written while members are still RUNNING, and a late verdict
  rewrites it later (`lr-move-batch.sh:19-21`, `lr-move-lib.sh:369-377`). The marker that means
  settled is `summary.settled/` (`lr-move-batch.sh:88-90`).
- *Measured.* `grep running move/2026*/batch.log` =>
  `20261018T002357Z-next4-next-40187: running: RUNNING=1 … each worker writes its own, and this summary is rewritten`.
  A loop over the move directory found 75 batches with `summary.json` and 45 with `summary.settled`.
- *Consequence.* §6.3 marks a batch settled at `summary.json` and stops scanning it. The slowest
  member, which is where STRANDED is listed first, is never read by `breaker_scan`. `inflight()` on
  `summary.json` also allows a second shed batch on the same source while workers still run.
- **Change:**
  - settled means `summary.settled/` exists;
  - in flight means a plan with `origin: shed` and no `summary.settled/`;
  - run `breaker_scan` before the `--shed-band` read, so that a failing band read does not also
    blind the breaker (§6.3 returns early at `band is None`).

**D3. Shed batches are known only through `CC_LR_MOVE_QUEUED_OUT`.**
- *Evidence.* `cmd_move` writes the request (`bin/cc-lr` cmd_move, `requests/$batch.json`) one
  statement before the `QUEUED_OUT` write (`:1707-1708`). A `MOVE_TO` kill in between leaves a
  batch that runs but is never recorded in `state.json`. Nothing then sets a cooldown or in-flight
  state for it, nothing scans it for casualties, and the next tick can re-pick the same sids. The
  claims still serialize the drivers.
- **Change:**
  - discover shed batches from disk, using `plan.json` `origin == "shed"`, which the design already
    adds;
  - treat a plan with no request, no `request.claimed.json` and no `admit.json` after two intent
    lifetimes as dead.

**D4. The "NaN is never band" claim is false for the code as written.**
- *Evidence.* `_is_num` accepts NaN (`bin/claude-accounts:5369-5370`). `max(0.0, nan)` returns 0.0.
- *Measured.* `/usr/bin/python3 -I -c` over the §6.2 arithmetic gives:
  - `used=nan -> band`;
  - `flat=nan: hi,lo= 1.0 1.0`, so `min()` silently drops the NaN, which is mutant m3 already in
    the trunk sketch.
- *Source.* `weekly_used_frac` passes wire `7d_util` through unclamped (`:1898-1906`), and
  `json.loads` accepts `NaN`.
- *Consequence.* T1's NaN case would fail against the sketch.
- **Change:**
  - `math.isfinite` on `used`, `wrh`, `ewma` and `flat`;
  - `lo <= 0` gives `band-guard`;
  - keep T1's NaN rows, and add `used=NaN`.

**D5. The window key cannot be computed stably, so the band may never open.**
- *Evidence.* `--shed-band` emits only `reset_h`, rounded to 0.01 h (§6.7). On a cached row,
  `weekly_reset_h` is the countdown taken at the sweep, "as stale as the cache"
  (`bin/claude-accounts:9041-9044`, `:8373-8377`), and the cache may be up to `cache_grace_s` 600 s
  old.
- *Consequence.* `now + reset_h` drifts by minutes from tick to tick. So "acct + reset rounded to
  the minute" creates a new window on most ticks, `trip_at` never ages 300 s, and `sheds` and the
  strand audit fragment across keys.
- **Change:**
  - emit `weekly_reset_at` and `_reset_key(weekly_reset_at)` per account, and key the windows on that;
  - compute the guard's `wrh` with `_until(r, "weekly_reset_at", "weekly_reset_h")`.

**D6. The "safe form" for the worker breaks every move-lane worker under bash 3.2.**
- *Evidence.* The worker is `#!/bin/bash` with `set -uo pipefail` (`lr-move-worker.sh:1,32`), and
  the batch starts it with `/bin/bash` (`lr-move-batch.sh:284`).
- *Measured.* `/bin/bash -c 'set -u; A=(); env "${A[@]}" true'` => `/bin/bash: A[@]: unbound variable`
  (bash 3.2.57). The guarded form `${A[@]+"${A[@]}"}` => ok.
- *Consequence.* §6.5's `"${FOCUS_ENV[@]}"` aborts every worker whose array is empty, which is
  every non-shed row, operator moves and `rotate` included. The abort lands just before
  `lr-handoff`, so it has a claim and a slot and no verdict.
- **Change:**
  - use `${FOCUS_ENV[@]+"${FOCUS_ENV[@]}"}`;
  - T4 must run the worker to the handoff line under `/bin/bash` with `hold_focused` absent, as the
    red arm for this.

**D7. Nothing stops the shed at the wall, and there it leaves its own scope.**
- *Evidence.* At used ≥ 100%, `left = 0`, so `ttw_hi = ttw_lo = 0`. The trip holds, and the guard
  `0 <= wrh - 2` holds while the reset is more than 2 h away. The band therefore stays `band` from
  the wall to the reset (median 10.5 h, max 106 h; M1).
- *What changes once the source is dead.* A rejected 7d or 5h fact makes `lr_source_dead` true
  (`lr-lib.sh:1143-1160`). Then `cl_move_rows`:
  - turns `background-job` into `move` (`bin/cc-lr:1312-1313`);
  - drops the `/goal` hold (`:1384-1387`).

  So the shed would move sessions with running jobs, which the recycle ends, and goal-driven
  sessions. §1 excludes both. A 5h fact can do this before the weekly wall.
- *Overlap.* After the wall, the shed also drives the same population as D2a's fan-out and the
  reconciler, at the moment recovery load peaks.
- **Change:**
  - add a verdict `walled` (used ≥ 1.0, or any rejected 7d/5h fact for the account) that sheds
    nothing; the at-wall population belongs to D2a and the reconciler, one driver per phase;
  - pass `LR_DEAD_SOURCE_RELEASE=off` and `CC_LR_MOVE_GOAL_HOLD=always` in the environment of the
    shed's `cc-lr plan` and `cc-lr move`.

**D8. The shed can carry a draft; "never a draft carry" does not hold.**
- *Evidence.* `cmd_move` re-runs the census at move time (`bin/cc-lr` cmd_move, `cl_move_rows`
  call). A composer that gained text since the shed's `plan` becomes `disposition=draft act=move`
  (`:1320-1328`). The worker then carries it, in the poller's environment (`lr-move-worker.sh:298`).
- *Why the draft is not lost.* The carry retypes it unsent. A `move` row whose box fills after the
  census is held by the recycle's composer gate (`handoff-fire.sh:5239-5245`).
- *Why it still matters.* Clear-and-retype in a pane someone just typed into is outside the shed's
  scope. It also has more ways to fail.
- **Change:** pass `LR_MOVE_CARRY_DRAFT=off` to the shed's `cc-lr move`. Its census then gives
  `hold:draft` and the row is not driven. T2 pins it.

**D9. `hold_focused` does not hold a pane whose focus is unknown.**
- *Evidence.* `lr_focus_gate` proceeds on `unknown` (`lr-lib.sh:1407`: `[ "$LR_FOCUS_STATE" = yes ] || return 0`).
  It is unknown whenever the kitty `ls` fails or times out (`:1363-1387`), which is exactly the slow
  kitty under load of B8.
- **Change:** for shed rows, focus `unknown` must hold too (for example a plan-driven
  `LR_MOVE_FOCUS_UNKNOWN=hold` in the worker's environment). Add a T4 row for it.

**D10. The operator-intent latch is minted by automation, and the kill switches do not reach queued moves.**
- *What the latch is.* `--operator-intent` is "A HEALTHY PANE MOVED BY ITS OPERATOR, NOT BY ITSELF"
  (`lr-handoff.sh:633-636`). `lr_intent_check` ignores extra keys (`lr-intent.sh:29-72`), so an
  `origin: shed` intent is indistinguishable from a typed one.
- *Consequence.* After `rm shed/mode`, after the breaker trips or after `autorecover.on` is
  removed, queued shed batches still actuate until their intents expire. That is
  `until_idle + 900` s, extended at admission (`lr-intent.sh:73-90`).
- **Change:**
  - `lr_intent_check`, or the worker's `intent_ok`, re-authorizes `origin == "shed"` at actuation:
    `shed/mode` reads `on`, there is no `shed/breaker`, and `autorecover.on` exists;
  - a breaker trip writes `abort` into every unsettled shed batch (`cc-lr move --abort`,
    `bin/cc-lr` cmd_move `--abort`);
  - Q1 should name this latch explicitly.

**D11. The cooldown contradicts §7.**
- *Evidence.* §6.3 sets a 6 h cooldown for every pick at queue time. §7 says a still-busy row, a
  focused row and a router-refused row are "retried next tick". With a 6 h cooldown and band leads
  of 0.9-2.2 h (M2), they are never retried within the band.
- *A separate correction.* "still-busy" is the wrong mechanism for a `move` row. Only `wait:*` rows
  are re-checked in W2 (`lr-move-worker.sh:143-178`). A `move` row that starts a turn is refused by
  handoff-fire's at-rest check, HELD:busy (`handoff-fire.sh:2754`, `:3193`).
- **Change:**
  - set the cooldown on MOVED only;
  - clear it for a non-casualty NOTMOVED read by `breaker_scan`;
  - correct the §7 rows.

**D12. Knob typos fail toward shedding.**
- *Evidence.* `_dispatch_knob` clamps an environment value to its range (`bin/claude-accounts:6742-6747`;
  `clamp` is `max(lo, min(hi, x))`, `:3562-3563`).
- *Consequence.* `CC_ROUTE_SHED_LV_OPEN=0.97` becomes 50: a band from 50%, worse than the rejected
  option E. The SSOT ranges themselves admit LV 50 and TTW 48 h.
- **Change:**
  - an out-of-range environment value for a SHED knob falls back to the default;
  - tighten the ranges, for example LV [95, 100], TTW [0, 6], GUARD [1, 24];
  - T1 pins `0.97` in the environment to the default.

**D13. The replay that sizes the policy is not the rule the code implements.**
- *What the simulation does.* `/tmp/d2/burn2.py:286-311`:
  - trips on the counterfactual level ≥ LV only;
  - guards on a counterfactual trailing-6 h pace of the kept sessions, which excludes shed sessions'
    later calls;
  - has no hysteresis.
- *What §6.2 does.* It trips on level ≥ 97 **or** fast-pace TTW ≤ 2 h, so it can open below 97%.
  It guards on `min(EWMA, flat)` over the whole account's ledger, which still counts the shed
  sessions' earlier burn. §6.3 adds the confirm delay of two looks ~10 min apart.
- *Consequence.* "15/43 avoided, ≤1.5 pp stranded" is therefore unvalidated for the specified rule.
  The direction of the strand error is plausibly upward (estimated, by reading both: a
  whole-account pace overstates the burn of the kept sessions).
- **Change:** re-run the replay with a port of `shed_band_row` and `step_hysteresis` before
  quoting the frontier. Use a realistic L: confirm + census + poller pickup + MOVED p50 386 s,
  which is estimated at 30-45 min, closer to the 8/43 row.

**D14. Bounds sized without a load measurement (liveness, which silently defeats the safety story).**
- *Evidence.* `cc-lr move` re-runs the census and then a non-cache `--rank general`
  (`cl_target_unroutable`, `bin/cc-lr:899-920`). Its own comment prices that read at "5-323 s".
- *Consequence.* `MOVE_TO = 300` can expire routinely at 15-40 per core. Every expiry is "unknown,
  retry", so the shed can be a permanent no-op that looks healthy. T6 asserts only that the tick
  ends within budget.
- **Change:**
  - T6 must also assert that a batch is queued in the `on` arm at 25 and 40 per core;
  - size `PLAN_TO` and `MOVE_TO` from that measurement, keeping the max per-arm bound below the pass
    bound;
  - measure the budget with `time.monotonic()`, not with the `LR_SHED_NOW`-seamed `now`. That seam
    trips the budget at once in tests.

**D15. The actuator is unqualified, and shadow mode cannot qualify it.**
- *Evidence.* M8: 25 of 66 actuated rows were casualties, and M9: nothing has run since the
  priority-31 waves.
- *Consequence.* Shadow writes picks only and never actuates, so §9 step 2 has no evidence about
  STRANDED.
- **Change:** add a gate before step 3: a measured post-wave casualty rate, for example ≥ 20
  actuated move-lane rows, attended or in the B1 rig, with 0 STRANDED.

**D16. D2a.**
- *T5 tests the wrong function.* `may_actuate` has no claim check (`act.py:438-479`). The claim is
  `hold_claim`, called from `__main__.py:1248-1250`, so T5 must drive that path.
- *Boot slots.* Idle records take boot slots (`__main__.py:1139-1140`). The pool is AIMD with
  floor 2 and halves on any boot over 45 s (`admit.py:334-341`), so at load it sits near 2. The act
  loop orders limited records first (`__main__.py:1223-1226`), but a slot held by an idle boot still
  delays a limited relaunch by up to one boot.
- *Composer reads.* Each idle composer read is bounded at 5 s (`observe.py:426-452`), with up to 23
  sessions at a wall (M1).
- **Change:**
  - reserve at least one boot slot for limited records;
  - cap idle composer reads per pass;
  - measure the pass with D2a on under B1 load before step 3a.

**D17. Minor items.**
- *Targets.* All picks go to `tgt[0]`, which piles them onto one account.
  - Use `claude-accounts --place` with `kind: idle` movers (`:6504-6519`), which accounts capacity
    and phantoms, or spread the picks across targets.
  - Hypothesis, not verified: a general-lane target may not serve a Fable-model session.
- *Requester identity.* Scrub `CLAUDE_CODE_SESSION_ID`, `KITTY_WINDOW_ID`, `CC_PANE_ID` and
  `ITERM_SESSION_ID` from the shed's children. Otherwise a manual `--tick` binds batch mail and
  `self` handling to the invoking pane (`bin/cc-lr:316-327`, `lr-move-lib.sh:361-366`).
- *Stale citation.* `bin/cc-lr:1172` ("Drafts are held, never carried") is stale. Drafts have been
  carried since 2026-10-18 (`:1320-1328`).
- *Equivalence guard.* T1's "`--rank` byte-identical" is green in both arms. Name its mutant or
  drop it.

### Residual risk after the changes

- Move-lane casualties on healthy sessions (D15) remain the dominant risk. The breaker contains
  them only after the first one, and up to 4 rows per source batch are in flight at once.
- Burn attribution is ±2x (§12.2).

These leave the policy call where §5 put it, with the operator.

## Review — efficacy-under-permanent-load

Adversarial review, 2026-10-20 18:55-19:30Z, read-only, against `28b25a119`. Load during the review:
`sysctl -n vm.loadavg` => `{ 318.84 262.74 223.79 }` at 19:00:51Z, which is 31.9 per core on 10
cores, so the readings below were taken under the premise's load. The repo rules were read first.
The ones that apply are "Inner bound starves the tail", "Verify a cure under its load", "Green in both
arms", "Empty vs no-surface" and "Detached bash is reaped at 10 min". The only writes were two
scripts and their output under `/tmp/d2rev/`, and this section.

The lens: does D2 hold at 15-40 per core with every lane at priority 31? Does any new wait, bound or
gate assume that load falls? Does D2 weaken the §5 guarantee for the recoveries it does not prevent?
Where the correctness-and-safety review above already covers a point, it is cited by its number
(D1-D17) and not repeated.

**Verdict: NEEDS-CHANGES.**

What holds:
- No decision in the controller reads the load average (G1).
- Each external arm has a wall-clock bound below the tick budget: 60 + 240 + 300 < 900.
- Our own timeout yields `unknown` and neither opens nor closes a band (G2).
- The kick is not under `taskpolicy`, so the controller inherits the poller's band. The poller
  plist reads `ProcessType Interactive`, and `recon/band.log` reads `pri=31 floor=31 ok`.
- The move lane's relaunch is staged, so `handoff-fire` does not load-gate it.
  `ls ~/.claude/lib/pane-successor.sh` shows it is present, and it defines `cc_pane_successor_stage`
  (`lr-move-worker.sh:300-332`).

What does not hold:
- D2 takes boot slots from the recovery cohort it is meant to shrink, at the moment that cohort
  forms (E1).
- Two of its gates have no bounded release (E3, E4).
- Its first-shed latency carries a confirmation delay the replay never paid (E2).
- Its shadow mode cannot tell "blind" from "nothing to do" (E7).

### E1. The shed shares the reconciler's boot slots, so D2 lengthens the guarantee's queue term (blocker)

- *Evidence: one store.*
  - The reconciler's `BootSlots` takes `slot-1..slot-6` under `<lr_root>/locks/swap-slots`
    (`admit.py:353-358`, `__main__.py:101-105`).
  - The move lane takes `slot-1..slot-W` in the same directory (`lr-move-lib.sh:236-260`), with
    `W = plan.slots` or `LR_MOVE_SLOTS`, default 4 (`lr-move-worker.sh:57`).
  - `grep -rn on_wave scripts bin tests` finds only `admit.py:422` and `test_admit.py`, so the AIMD
    resize is not wired and the reconciler's width is a constant `D = 6`. This corrects D16 above,
    which says the pool "sits near 2". B1 found the same (`B1-load-harness.md:793`).
- *Measured: how long a move row holds a slot.* From `slot` to the first proof read,
  `python3 -I /tmp/d2rev/slot_hold.py` over `move/*/*.events.jsonl` gives p50 410 s, p90 1,443 s
  and max 3,787 s (n = 148 actuated rows, all before priority 31).
- *Measured: this contention has already happened.* `grep boot-slots recon/events.jsonl*` returns
  7 `admit-refused boot-slots` rows on 2026-10-18:
  - 4 at 07:02:39Z;
  - 2 at 07:27:17Z;
  - 1 at 07:33:33Z.

  Each fell while move batches held slots. Batch `064955Z` held them from 06:55:04 to 07:15:44Z,
  `070336Z` from 07:12:03 to 07:36:58Z and `072521Z` from 07:25:53 to 07:36:06Z (`jq` over those
  batches' events).
- *Consequence for G (estimated, using the §5 formula with its targets T_att = 15 min and k = 8,
  the median wall cohort, M1).*
  - With the full width, `ceil(8/6)·15` = 30 min.
  - While a 4-row shed batch holds slots 1-4, the reconciler has 2 left: `ceil(8/2)·15` = 60 min.
- *When it bites.* Mostly at the source's own wall:
  - a batch queued in the last ≤2 h is still in flight then, because MOVED takes p50 386 s and
    p90 1,347 s (M8);
  - the band also stays `band` after the wall (D7).

  It also bites at any other account's wall.
- *Contradiction.* B3 recorded exactly this risk ("Idle move lane holds the shared swap slots …
  Becomes material only with D2", `B3-deadline-override.md:458`). §11's "B2, B3, B4, B7: None" is
  therefore wrong.
- *Why it matters.* D2 is net-positive for G only if it yields. It removes an estimated 1-2 limited
  sessions per wall (8-15 of 43 over 7 walls). That saves at most one `T_att` step, which is less
  than the step it can add.
- **Change:**
  - shed batches pass `cc-lr move --slots 1`, which caps the shed at one shared slot;
  - the controller logs `yield:recovery` and queues nothing while any reconciler record of kind
    `limited` is open and not terminal. Read this from `recon/sessions/`. It is a queue gate, not a
    load gate, and §5 bounds how long that queue lasts;
  - correct §11 for B2 and B3;
  - add a B1 test: a k = 9 limited cohort plus a concurrent 4-row shed batch. Assert that `t_first`
    for every member is within the no-shed arm's bound. The red arm is today's `--slots 4` with no
    yield.

### E2. The confirmation delay on the monotone level arm costs one poller period of a short lead (major)

- *Evidence.* `step_hysteresis` opens only after two `band` looks at least 300 s apart. The kick
  runs once per poller tick.
- *Measured.* `TICK start` gaps since 07:30Z: n = 64, p50 10.7 min, p90 10.9, max 13.8 (M10 said
  max 12.4). Opening therefore costs about one tick, 10.7 min, after the first look.
- *Why it buys nothing on that arm.* The weekly level cannot fall inside a window, so `used ≥ LV` is
  monotone. M2's "flips up to 7 times" comes from the pace terms: the TTW trip and the guard.
- *What it costs.* At the p25 lead of 0.9 h from 97% (M2), the delay spends about 20% of the lead
  before the first move is even queued.
- *Mismatch with the replay.* The replay has no confirmation at all (`/tmp/d2/burn2.py:291-321`).
  This adds to D13.
- **Change:**
  - open on the first look when `used_pct ≥ LV`;
  - keep the two-look confirmation only for a TTW-only trip;
  - optional: while a window is open, the controller stays alive and re-ticks every 3-5 min within
    its budget. It is Python, so cc-reaper's 600 s bash reap does not apply.

### E3. The one-batch-in-flight gate has no bounded release (major)

- *Evidence.*
  - `inflight(st, acct)` holds the source while its batch has no settle marker (D2 corrects which
    marker).
  - A batch runner that dies never writes `summary.settled/`. Neither does one whose host reboots,
    or whose pid is reaped.
  - The batch's own WATCH deadline is `UNTIL + LR_MOVE_SLOT_WAIT_S (600) + LR_MOVE_PROVE_S (300) +
    300` = 1,200 s for the shed's `until_idle` of 0 (`lr-move-batch.sh:299`).
- *Consequence.* After one lost runner, that account is never shed again. This is the "gate that
  never opens" class the premise forbids.
- **Change:**
  - a shed batch is in flight only while it is younger than its WATCH deadline plus a margin, about
    1,500 s, and its runner (pid and lstart, read from `batch.log` or a recorded pid) is alive;
  - past that, it becomes `settled:unknown`, which releases the source and is logged;
  - add a T2 case: a batch dir with no runner and no marker, older than 1,500 s, allows the next
    batch.

### E4. A session that turns limited while it waits for a slot keeps the shed's claim for up to 600 s (major)

- *Evidence.*
  - The W3 loop `until slot_try` (`lr-move-worker.sh:376-381`) re-checks the abort file and the
    intent, never the limit.
  - `limited_now` runs before the loop (`:202`) and after the slot (`:384`).
  - While the claim is live, the reconciler's `hold_claim` refuses the record. "A live claim by
    another actuator" is a §5 hard predicate, which pages only after `W_hard`.
- *Why D2 makes it common.* D2 is the lane whose rows sit on an account minutes from its wall.
  Under E1's contention its rows also wait longer in slot-wait.
- *Consequence.* A recovery can be delayed by up to `LR_MOVE_SLOT_WAIT_S` (600 s), which is a whole
  `W_soft`.
- **Change:**
  - re-check `limited_now` in the slot-wait loop at the intent re-check cadence
    (`LR_MOVE_INTENT_RECHECK_S`, 30 s), at least for `origin: shed` rows;
  - add a T4 case: a row whose transcript gains a limit record during slot-wait ends
    `became-limited` within one re-check.

### E5. Transient failures are made final (concurs with D11, with the measured share)

- *Measured.* Load-correlated NOTMOVED reasons in M8's table, from `awk` over
  `/tmp/d2/move_verdicts.tsv`:

  | Reason | Rows |
  |---|---|
  | HELD:unreachable | 8 |
  | HELD:no-shell | 7 |
  | resolver-unavailable | 6 |
  | composer-unreadable | 5 |
  | exit-readback | 4 |
  | batch refused target-unverified | 13 |
  | slot-wait | 14 |
  | claim-held | 13 |

- *Consequence.* With a 6 h cooldown at queue time and band leads of 0.9-2.2 h, each of these ends
  that session's eligibility for the band. That makes a transient a negative verdict, against G2.
- *Estimate of the effect* (only a scaling: M8's actuated success of 62% before the waves, applied
  to the replay's range). With D11 unfixed, roughly 0.6 × (8-15) ≈ 5-9 of 43 avoided, not 8-15.
- **Change:** as D11. Also add a T2 case: a batch that settles NOTMOVED `HELD:unreachable` leaves the
  sid re-pickable on the next tick.

### E6. T6 cannot go red as written, so it has no power (major)

- *Why the red arm cannot breach.* Every arm is bounded (60/240/300 s), and the budget check stops a
  second account after 360 s. So a tick at priority 20 still ends within about 900 s; its arms just
  return `unknown`.
- *Consequence.* "Red arm under `taskpolicy -c utility` must breach the budget" will be green in
  both arms (rule "Green in both arms").
- **Change:**
  - the cure arm, at 25 and 40 per core, must produce `pick` rows and, in mode `on`, a queued batch,
    with each arm's wall time under half its bound;
  - the red arm must produce `unknown` rows for the census or move arm;
  - record each arm's wall time in `decisions.jsonl`;
  - measure the budget on `time.monotonic()`, not the seamed `now` (D14 found this too).

### E7. Shadow mode cannot qualify the actuation front, and cannot tell blind from empty (major)

- *Two blind spots.*
  - The `pick` row logs `cands` and the picks, nothing more. If kitty is at priority 4 with the
    screen locked (B8), every row reads `hold:composer-unknown`. A disposition comes from
    `lru_unreadable_disp` (`lr-upgrade.sh:632-640`, `:1106`). The shadow log then reads "0 picks",
    the same as "no idle session" (rule "Empty vs no-surface").
  - Shadow never runs `cc-lr move`, which repeats the census and a strict `--rank general` that can
    sweep (`bin/cc-lr:899-936`).
- *Measured strict-read duration.* `ts − router_ranked_epoch` in `plan.json` is 1-38 s over the 12
  batches that recorded it (10-18 15:32Z to 10-20 03:04Z). That is acceptable. The census time is
  recorded nowhere.
- **Change:**
  - every `pick` row carries a disposition histogram (`move`, `hold:*`, `composer-unknown`,
    `draft`, …);
  - every `unknown` row carries the cache age and the ledger age;
  - in shadow, time a bounded `cc-lr move --from A --sids … --to T --dry-run` per banded account per
    tick. It runs the census and the strict router read (`bin/cc-lr:1659-1663`) and then returns
    before any write (`:1664-1672`). Log its wall time and router verdict;
  - §9 step 3 requires that dry-run's p90 to be under half of `MOVE_TO` at the shadow walls' load.

### E8. The shed's inputs are produced one band below the work (moderate)

- *Measured: the producer's band.* The verdict's cache and ledger come from
  `com.claude.accounts-keepwarm`, whose plist sets `ProcessType Standard`. `man launchd.plist` says
  "Standard jobs are equivalent to no ProcessType being set". `ps -M` on the running sweep (pid
  35923, 19:08:58Z) => `20T`.
- *Measured: sweep times.* The last 150 `keepwarm:` lines give `took_ms` p50 20,490, p90 72,100 and
  max 141,784, under a 240 s alarm.
- *Measured: ledger cadence.* `python3 -I /tmp/d2rev/ledger_gaps.py`:
  - since 07:23Z: gaps p50 460 s, p90 564 s, max 651 s, with the newest row older than 600 s for 0.3%
    of the time;
  - since 10-18: p99 637 s, and one gap of 11,657 s (10-18T21:27Z to 10-19T00:41Z), during which
    the shed would have been blind.
- *Consequence.* It fails safe today, but the margin to `cache_grace_s` 600 is thin at 32 per core.
  The strand audit's `last_ledger_level(before=reset_at)` would read a stale level across such a gap
  and trip the breaker falsely.
- **Change:**
  - name keepwarm's band as a dependency;
  - give `--shed-band` its own `max_age` (≈1,200 s; the level moves ≤ 1-2 pp/h);
  - the strand audit requires a ledger sample within 30 min before the reset, otherwise `unknown`,
    which pages nothing and trips no breaker;
  - shadow reports the share of ticks that were blind.

### E9. D2a adds kitty reads to every reconciler pass for hours (concurs with D16, with the cadence)

- *Evidence.*
  - `_read_composer` reads the composer of every at-rest session in a `claude` pane under a
    fact-covered account on every pass when fan-out is on (`__main__.py:710-719`). The bound is 5 s
    per read (`observe.py:431`).
  - The read happens before `_idle` rejects focused or occupied panes, so those panes are re-read on
    every pass until the reset.
- *Measured.* The pass cadence is p50 6 s and p90 7 s (gaps in the last 200 `recon/band.log` lines).
  A wall leaves its fact up for a median 10.5 h (M1).
- *Consequence.* The reads add directly to the pass duration, which enters the guarantee as `P_max`.
- **Change:**
  - a per-session composer verdict TTL of ≥60 s;
  - a per-pass cap on idle reads, as D16 says;
  - at most one boot slot for idle records while any `limited` record is open;
  - list B2 as a dependency of D2a.

### E10. Minor

- §6.4 cites the 3.0-3.4 min census time as the basis for `PLAN_TO`. That figure is for a `--sid`
  census, which gets the prefilter. A `--from` census still pays three `jq` reads per live row before
  the `from` test (`lr-upgrade.sh:1058-1077`). Measure it (E7).
- The "2.1-8.1 s at priority 31" figure is in `REPORT.md` §8 (wave 5), not in the message of
  `9d6cd03ff`.
- The `census.bucket` call is at `__main__.py:326`, not `:325`.
- The G1 lint should also assert that the deployed environment stages the relaunch. The only load
  hold left on the actuation path is `handoff-fire`'s typed-relaunch precheck, which applies when
  the successor library is missing (`lr-move-worker.sh:313-332`).

### Adjusted conviction

**45%**, down from 60%: as written, D2 avoids a fifth to a third of at-wall limited sessions at no
cost to the guarantee's bound. With E1-E5 and D11/D13 fixed, I would put it at about 55%. The
remaining doubts are:
- the move lane's casualty rate at priority 31 (M9, D15);
- kitty's band at night (B8), which blinds both D2 and the census.

### Commands run (all read-only; writes only under `/tmp/d2rev/`)

| Command | Established |
|---|---|
| `sysctl -n vm.loadavg` | 31.9 per core during the review |
| `plutil -p` of the keepwarm, poller and reconciler plists; `man launchd.plist` | keepwarm `ProcessType Standard`; poller and reconciler `Interactive`; Standard means unspecified |
| `ps -M -p 35923` (a live keepwarm sweep) | `20T` |
| `tail -150 ~/.claude/logs/accounts-keepwarm.out.log` | sweep `took_ms` distribution |
| `python3 -I /tmp/d2rev/ledger_gaps.py` | ledger sweep cadence and staleness (E8) |
| `python3 -I /tmp/d2rev/slot_hold.py` | move-lane slot hold times (E1) |
| `grep boot-slots recon/events.jsonl*`, then `jq` over move batch events from 06:55 to 07:40Z on 10-18 | slot contention between the lanes (E1) |
| `jq` over `move/*/plan.json` (`ts − router_ranked_epoch`) | strict router read 1-38 s (E7) |
| `awk` over `/tmp/d2/move_verdicts.tsv` | transient NOTMOVED counts (E5) |
| `grep 'TICK start' poller.log`, gap stats | poller cadence (E2) |
| `tail -200 recon/band.log`, gap stats | reconciler pass cadence (E9) |
| `grep -rn on_wave scripts bin tests` | BootSlots width is a constant 6 (E1) |
| `sed -n`/`grep -n` of `admit.py`, `__main__.py`, `census.py`, `observe.py`, `lr-move-{lib,batch,worker}.sh`, `lr-upgrade.sh`, `bin/cc-lr`, `bin/claude-accounts`, `lr-reset-poller.sh`, `scripts/lib/detach.sh`, `lr-page-once.sh` | every `file:line` cited above |
