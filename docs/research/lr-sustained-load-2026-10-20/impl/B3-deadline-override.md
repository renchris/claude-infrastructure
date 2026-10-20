# B3 — per-record deadline override: implementation design

Item: B3-deadline-override (REPORT §4 B3, §5 guarantee). Read-only research, 2026-10-20 ~17:30-18:00Z.
Nothing was typed, signalled, loaded or edited outside `/tmp/b3/`.

**Code base.** Line numbers are from this worktree at `28b25a119`. They also hold for `main` (`6fdf87eca`) and the live
checkout: `git diff --quiet 28b25a119 6fdf87eca -- scripts/limit-recover scripts/lib scripts/handoff-fire.sh bin`
=> no difference (measured).

**Labels.** M = measured (command named). E = estimated (method named). H = hypothesis.

---

## 0. Verdict

**BUILD, conviction 62%.**

An agent can implement this end to end in Python inside `lr_recon/`. It needs no new runtime module and no
operator ruling. Activation needs the usual operator reload, because agents may not reload launchd jobs.

What B3 is, in one paragraph:
- Every LIMITED record carries an absolute `deadline_at`. It is set once from `timeline.detected`, kept across
  attempts, hops and restarts, and moved forward only across a system sleep.
- Once a record passes its deadline it is **overdue**. Its first turn then skips the soft admission gates (restore
  budget, token bucket, per-account pacer, the probe and its drip). Its reset wake skips the pacer. A retry after
  rail junk (our own timeout, a deaf kitty, an unreadable read) reuses its still-valid target instead of asking
  `--place` again.
- Two bounds apply instead:
  - a deadline-lane width **D = 6** (overdue actuators alive at once);
  - a **hard stop**, read in-process, that turns the bypass off on positive evidence of a physical limit. The hard
    stop never holds a record beyond today's gates.
- Every hard gate is left byte-for-byte untouched, and so is every actuator precheck. B3 changes *when* and *where*
  an attempt is made, never *whether* the actuator may refuse it.
- An overdue record that is not in a live attempt `W_hard` after its deadline **pages**. This also wires two pages
  that exist in code but never reach anyone (§1.3).

Why conviction is not higher (details in §12):
1. After waves 1-5 the admission gates are already bounded: the token bucket plus the drip give 1 per 30 s per
   cohort. B3's *latency* gain there is minutes, not hours.
   - M, prototype: a 24-member cohort under a standing probe refusal had its last first attempt at +690 s. 3 members
     were past 600 s.
2. The guarantee's other terms, `P_max` (pass length) and `T_att` (attempt wall time), are B2's and the actuators'.
   B3 cannot bound them.
3. The real value is the contract, the pages, and the kept target on retries, none of which has been tried on a live
   cohort yet.
   - M: since the PRI-31 reload at 07:23Z, `recon/events.jsonl` has no new limit cohort. There are 2 `spawn` rows,
     both at 07:23Z.

---

## 1. What exists today (post waves 1-5)

### 1.1 The soft admission gates are age-blind
- `Admission.decide` (`admit.py:264-333`) applies, in order:
  - `restore-r` (`:289-305`);
  - `pace`, a token bucket of 1 per 20 s with burst 6 (`:306-307`, `:170-184`);
  - `pacer`, 3 per target account with a 20 s self-release (`:308-309`, `:193-198`);
  - the probe (`:310`, `:216-238`), then the drip (`:311-326`).
- None of them reads the record's age.
- `_dispatch` asks `decide` every pass (`__main__.py:1269`) and sorts records oldest-first (`:1223-1226`). The answer
  is the same for a record detected 20 min ago as for one detected now.

**M, prototype `/tmp/b3/red.py`** (imports this worktree read-only and writes only under `/tmp/b3`):

| Scenario (today's code) | Result |
|---|---|
| 30 PLANNED limited records on one account, `timeline.detected = now - 1200`, probe admits | **3 spawned** in the pass. 27 × `admit-refused pacer:next` |
| `decide()` alone: 24 overdue members, probe standing on rc 9 (memory soft line), 10 s passes | All 24 admitted. **Last first attempt at +690 s.** 3 members past 600 s (the drip: 1/30 s/cohort) |

### 1.2 A retry re-asks the placer even when its target is still good
- After a TRANSIENT failure the record goes to `BACKOFF` and keeps `target_acct` (`settle.py:308-313`). `plan.movers`
  still offers it to `--place` (`plan.py:255-266`).
- `--place` is bounded at 120 s at our load (`plan.py:358-364`). On rc 124, `keep_waits` keeps it waiting
  (`plan.py:367-375`).
- **M, prototype `/tmp/b3/red2.py`.** An overdue `BACKOFF` record with target `next4` from attempt 1, with `--place`
  returning rc 124, gives `placed=0 substate=BACKOFF`. The event reads `lane=general rc=124 cause=timeout … timeout=120s
  load1=240`.

### 1.3 Three pages are computed and never sent
- `Admission.page_due` is set when the drip opens (`admit.py:322-324`). `grep -n page_due lr_recon/*.py` => only
  `admit.py:24,124,163,324`, so nothing reads it (M). Architecture C6 says the drip "admits one per 30 s **and pages**"
  (`docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md` §C6).
- `classify.apply_failure` returns `BACKOFF_PAGE` at the 6th TRANSIENT and then hourly (`classify.py:190-191`).
  `grep -n BACKOFF_PAGE lr_recon/*.py` => only `classify.py:177,191` (M). The value ends up in an event's detail text
  and pages nobody.
- `Reporter.slo_page` (`report.py:1010-1032`, "10 minutes after the last death…") has no caller: `grep -n slo_page`
  => only its definition (M).

So today a record that retries TRANSIENT failures all night pages nobody. Rule: "Loud into a dead log"
(`.claude/rules/agent-operating-lessons-situational.md:7`).

### 1.4 The bound's other terms, as measured now
- **Pass period at PRI 31** (`recon/band.log` row spacing, one row per pass since 07:23Z, n=3782):
  - p50 10.0 s, p90 13.0 s, p99 19.0 s, max 193 s;
  - 5 gaps over 60 s (M, python over `band.log`).
  - These were quiet passes: only 4 twenty-day-old PARKED-REBOOT idle records were open (M, `/tmp/b3/open.py`).
- **Census abstains still happen at PRI 31.** 4 `abstain` events between 07:40Z and 11:06Z read "ps … timed out at
  30-37s". Each one is "(1 in a row)", and `band.log` read `pri=31` around each (M). Abstain is a hard gate (§3), so it
  stays part of `P_max`.
- **`T_att` at PRI 31: unmeasured.** No cohort has run since the reload (M). At PRI 20, attempts were 7-33 min
  (axis 05 §4).

---

## 2. Lanes and their deadlines (T per lane)

B3 applies only to `kind == "limited"` records. An idle move is a voluntary shed of a session that can still work,
not a queued recovery of a capped one.

| Lane | Clock starts at | `W_soft` (default) | Knob | Why this value |
|---|---|---|---|---|
| **Move**: PRE-MOVE → A/R, both model lanes (`rec.lane` `general` and `fable`) | `timeline.detected` (`census.py:440`), stored as `deadline_at` | **600 s** | `LR_DEADLINE_SOFT_S` | REPORT §5 `W_soft`. The soft gates' designed escapes clear a ≤20-member cohort inside it (drip 1/30 s; E: 20 × 30 s). The deadline only binds when they don't |
| **Owed first turn**: C / C-retry on RELAUNCHED-UNPROMPTED/DRAFTED | the same record's `deadline_at` (unchanged across the move) | inherits | — | Same recovery. C's own 60 s quiet grace is hard and stays (`__main__.py:1236-1242`) |
| **Reset wake**: WAIT_RESET / HELD:team / stay (`_wakes`, `__main__.py:408-455`) | wake due = `wait.eta` (+120 s + jitter 0-60 s unless `detail == "stay"`) | **300 s after due** | `LR_DEADLINE_WAKE_S` | Measured from the reset, never from detection. Otherwise every cohort waiting out a weekly reset would be overdue the instant it resets and lose the jitter spread. 300 s ≫ the pacer's spread (3/acct per 20 s ⇒ 40 wakes per account in 280 s, E) |
| WAIT_RESET with `detail "wait-data"` (a strand that `plan.movers` re-offers, `plan.py:247-254`) | move clock | 600 s | — | It is a mover, not a wake |
| **Idle moves** (`kind idle`, fan-out) | — | **none** | `LR_DEADLINE_IDLE_S` (unset = off) | Voluntary, owes no first turn (`__main__.py:1141-1142`) |
| Poller hook lane (`lr-reset-poller.sh`) | `CC_ADMIT_QUEUED_SINCE` | unchanged: 2700 s | `LR_CAPACITY_QUEUE_MAX_S` | Already a deadline override: it admits and pages past the queue bound (`capacity-admit.sh:1771-1800`). Out of scope for B3 |
| Move lane (`lr-move-worker.sh`, `cc-lr move`) | — | out of scope | — | A bash lane with its own bounded give-ups (axis 01 G17). Not a reconciler record |

`W_hard` (the page) is **900 s** past the deadline for every reconciler lane (`LR_DEADLINE_HARD_S`). The page fires
only while the record is not in a live attempt (§5.8). For the move lane that is detection + 25 min.

---

## 3. Gate census: soft vs hard, and what B3 does to each

Class key:
- **SOFT**: bypassed once the record is overdue.
- **HARD**: never touched.
- **BOUNDED**: already releases by itself; it is a term in the bound and is left as is.
- **LANE**: the deadline lane's own width.

### 3.1 Reconciler gates on the path detection → spawn

| # | Gate | file:line | Class | B3 action |
|---|---|---|---|---|
| 1 | Census abstain (W7a): untrusted census decides nothing | `__main__.py:1676-1683` | HARD (blind census: holders, turns and duplicates unseen) | untouched. A `P_max` term (4 abstains since 07:23Z, §1.4) |
| 2 | `recon.on` / mode `act` | `act.py:452-455`; `__main__.py:1718` | HARD (operator cutover) | untouched |
| 3 | plan-only (zero-human scope D1.9) | `act.py:456-457`; `census.py:345-349`; `__main__.py:225-231` | HARD (operator scope, item A7) | untouched. Now moot: `ls -la ~/.reso/limit-recover/autorecover.on ~/.reso/limit-recover/recon/autorecover.on` => both present (recon one created 12:10 CDT today, M) |
| 4 | PARKED-REBOOT | `act.py:460-461` | HARD (boot-resume owns it) | untouched (and idle, so no deadline) |
| 5 | HEAL disabled | `act.py:462-463` | HARD (operator) | untouched |
| 6 | process-live | `act.py:464-465` | HARD (one actuator per record) | untouched. Counts as lane occupancy |
| 7 | team-live (lead with live members) | `act.py:466-468` | HARD (teammate/lead, D4.4) | untouched |
| 8 | duplicate-risk (R over a holder outside its pane) | `act.py:469-470` | HARD (split-brain, invariant 27) | untouched |
| 9 | backoff | `act.py:471-472`; `classify.py:17-18,169-173`; `settle.py:204,299,304` | BOUNDED (TRANSIENT ≤300 s; WAIT 60 s; HOLD past PRE-MOVE 120 s; R proof 120 s) | untouched (the `B_max` term) |
| 10 | escalated (exact DETERMINISTIC repeat) | `act.py:473-474`; `classify.py:194-197`; rearm `__main__.py:781-806` | HARD (defect stop; pages ESCALATED, `report.py:918-919`) | untouched |
| 11 | wake-guard (30 s after a system wake) | `act.py:475-476` | HARD (stale world after sleep) | untouched |
| 12 | workers-cap (16 live actuators) | `act.py:477-478` | BOUNDED capacity | untouched; dispatch order becomes earliest-deadline-first |
| 13 | C quiet grace 60 s | `__main__.py:1236-1242` | HARD (a second prompt into a turn = double typer) | untouched |
| 14 | one driver per session (claim) | `__main__.py:1248-1268`; `act.py:493-523` | HARD (duplicate driver) | untouched; named in the W_hard page |
| 15 | boot slots (6, shared with the move lane's swap slots) | `__main__.py:1139-1140`; `admit.py:432-440` | LANE | untouched. For A/R it *is* the deadline lane |
| 16 | restore budget R | `admit.py:289-305` | **SOFT** (policy count; already folded into the drip run on 2026-10-13) | bypassed when overdue |
| 17 | token-bucket pace (1/20 s, burst 6) | `admit.py:306-307`, `:170-184` | **SOFT** | bypassed when overdue. A token is still **charged** (the bucket floors at 0, `:183-184`), never required |
| 18 | per-account pacer (3, 20 s release) | `admit.py:308-309`, `:187-203` | **SOFT** (burst protection; "0/40 failures at N≤6", architecture §C6.3) | bypassed when overdue. A slot is still **charged** |
| 19 | probe rc 9 "capacity" (headroom ≥4 GB, segments ≤50%) | `admit.py:231-235`; `capacity-admit.sh:1492,1532` | **SOFT** (capacity-admit itself releases after its budget, `:1833-1838`, or its queue clock, `:1786-1793`) | not run when overdue. Replaced by the **hard stop** (§5.3) |
| 20 | probe-timeout / probe-error | `admit.py:236-238` | **SOFT** (our own bound) | not run when overdue |
| 21 | drip interval (1 per 30 s per cohort after 3 refusals) | `admit.py:311-326` | **SOFT** (the existing escape) | bypassed when overdue. Its page gets wired (§5.8) |
| 22 | wake pacer | `__main__.py:447-449`; `admit.py:205-210` | **SOFT** | bypassed when the wake is overdue (slot charged) |
| 23 | placement non-answer (rc 124/126 → wait-data, keep_waits) | `plan.py:326-331,367-375`; `__main__.py:1011-1019` | **SOFT** (our own timeout) | overdue retry with a valid **kept target** skips `--place` (§5.5). A first placement still needs B2 |
| 24 | WAIT_DATA from `kwork = None` (Invariant 13: missing data is never headroom) | `plan.py:151-163` | SOFT by design invariant | the kept target covers retries. First placement left to B2 |
| 25 | placement answer: target capped, no seat (KMAX), every account capped | `plan.py:413-468`; `bin/claude-accounts --place`; `facts.blocking` `facts.py:334-373` | HARD (a wall, or router policy) | untouched. A kept target is re-checked with `F.blocking` |
| 26 | stay rule (source resets ≤15 min) | `census.py:242-244`; `plan.py:445-451` | BOUNDED policy | untouched; the wake lane's deadline applies |
| 27 | re-offer after a failed wake (900 s) | `plan.py:205,233-243` | BOUNDED | untouched |
| 28 | HOLD-COMPOSER from **busy** (a turn in flight) | `classify.py:146-147`; `settle.py:72` | HARD (in-flight turn) | untouched; never junk |
| 29 | HOLD-COMPOSER from **unreachable / exit-readback / unknown** | `settle.py:73-74`; `classify.py:146`; default `settle.py:117,506` | **SOFT: rail junk** (our read failed; 0 of 18 HOLD-COMPOSER transitions were a composer condition, gap-3 §2.2) | on re-probe, an overdue record keeps its target. The page names the real reason |
| 30 | HOLD-LOAD (recycle typed its relaunch over the 24/core commit bound) | `settle.py:75-78`; `types.py:128-130` | HARD (the F1 typed-relaunch harm, REPORT §3.3; the staged path is exempt, `handoff-fire.sh:13879`) | untouched; pages at 900 s (wave 3) |
| 31 | re-probe cadence 120 s | `settle.py:28,432-444` | BOUNDED | untouched |
| 32 | census holds: TEAMMATE, SPLIT-BRAIN, HOLD:iterm, IMPOSSIBLE, HELD:team, HOLD-FOCUS (only under `LR_MOVE_FOCUSED=off`), HOLD-BGWORK (ship-land, or a source not rejected), HOLD-DRAFT (affirmative draft) | `census.py:184-241` | HARD | untouched: never movers |
| 33 | IN-FLIGHT 600 s with no holder | `__main__.py:876-896` | failure detector | untouched |
| 34 | RECON-DEFECT invariant | `__main__.py:1569-1610` | detector | an overdue defect pages (§5.8). **No forced re-drive** (guessing could double-move) |

### 3.2 Actuator prechecks: run on every attempt; B3 changes nothing they receive

`handoff-fire.sh --probe-recycle-preconditions` (`:13635-13996`) is reached through lr-handoff's precheck
(`lr-handoff.sh:1423-1495`). B3 never alters `act.actuator_env` (`act.py:50-93`) or any argv (`act.py:103-254`). So
each of these verdicts still refuses an overdue attempt exactly as a fresh one:

| Verdict | Line | Hard reason |
|---|---|---|
| `REFUSED:teammate` | `:13823` | teammate |
| `HELD:team` | `:13835-13837` | lead with live members |
| `HELD:busy` / `HELD:mid-turn` | `:3274`, `:3284` via `:13946` | turn in flight |
| `HELD:bg-work:ship-land` / `:other` | `:3293`, `:3300` via `:13946` | ship-land |
| `HELD:focused` / `HELD:draft` (focus gate) | `:13965` | operator at the pane |
| `HELD:draft` | `:13985` | real draft (junk residue is already receipted and passes, `:13968-13980`) |
| `HELD:load` (typed relaunch only) | `:13888` | F1 |
| `HELD:pane:resolver-unavailable`, `HELD:wedged`, `HELD:unreachable`, `HELD:composer-unreadable` | `:13857`, `:13900`, `:13901`, `:13992` | not hard: rail junk, already TRANSIENT since wave 2 (`classify.py:33-35,160-161`) |

The in-place wake keeps `lr_focus_gate` plus `cc_tui_submit`, which refuses an occupied composer (`act.py:226-244`).

**The structural safety argument.** B3 changes only five things:
1. `decide()`'s answer for an overdue record. That answer only mints a first-turn token.
2. Whether an overdue retry re-asks `--place`. It does not when the kept target passes `F.blocking`.
3. Whether `_wakes` honours the pacer for an overdue wake.
4. Dispatch order.
5. Pages.

None of `may_actuate`, `hold_claim`, the census buckets, the actuator env or argv, or any precheck is touched. Test
§7 H8 pins that.

---

## 4. Interplay with the wave-1 token bucket and the drip

- **Order inside `decide`.** The overdue branch is evaluated first:
  1. If the record is overdue, the deadline lane has room, and the hard stop reads clear → `admit:deadline`.
  2. Otherwise the call **falls through to today's path unchanged**: restore-r → pace → pacer → probe → drip.
  - An overdue record is therefore never treated worse than today.
  - A full lane or a memory trip only removes the bypass; it adds no new refusal.
- **Token bucket.** An overdue admission calls `pace_ok(self.wall())` (refill) and then `pace_take()` (floors at 0).
  - Overdue first turns therefore drain the bucket.
  - Non-overdue members queue behind them at 1 per 20 s. That is earliest-deadline-first, which is the intent.
  - The bucket never goes negative, so after an overdue burst the system returns to its designed rate within
    `burst × 20 s` = 120 s.
- **Pacer.** An overdue admission still calls `pacer_take`. A non-overdue member sees that account as busier.
  Overdue first turns per account are bounded by D = 6, inside the measured-safe N ≤ 6 (architecture §C6.3, "0/40
  failures at N≤6").
- **Drip.** An overdue admission never runs the probe, and touches none of `refusals[cohort]`, `over_at` or
  `last_drip_at`.
  - The drip's run therefore keeps meaning "consecutive probe verdicts" for the members still on the normal path.
  - The drip stays the escape for non-overdue members.
  - Its page is wired (§5.8), so the C6 promise "admits one per 30 s and pages" becomes true.
- **Restart.** The deadline lives on the record (`deadline_at`), so a restart neither resets nor re-grants it
  (invariant G6). The bucket and drip state are in memory and are reset by a restart (item A6 iii persists them).
  After a restart an overdue record is admitted at the first dispatch, bounded by D.

---

## 5. The change

### 5.1 Data and format changes

| What | Where | Back-compat |
|---|---|---|
| `Record.deadline_at: Optional[float] = None` | `types.py` (inside `Record`, `:735-797`), in its own commit as the module rule requires (`types.py:3-6`) | `from_dict` defaults missing keys, so old records load with `None`. `ensure_deadline` fills it on the next pass |
| `rec.close` keys: `deadline_admitted_at`, `deadline_hold`, `overdue_at`, `placed_at`, `placed_acct`, `hold_raw` | record JSON | additive |
| events: `overdue`, `kept-target`, `wake-deadline`, `deadline-held` (on reason change, like `admit-refused`), `deadline-shadow`; the `admit:deadline` reason appears in `spawn`/launch rows via `admit_refused` clearing | `recon/events.jsonl` | additive |
| pages: `DEADLINE` (per record), `DRIP` (per cohort) | Reporter sinks | additive |
| switch files: `recon/deadline.off`, `recon/deadline.shadow` | `~/.reso/limit-recover/recon/` | absent = on |

### 5.2 `clock.py` — a sleep moves the deadline (`shift_record`, `:167-180`)

```python
    if rec.deadline_at is not None:      # B3: a deadline, not history (timeline stays put)
        rec.deadline_at += slept
```

### 5.3 `admit.py` — the deadline, the hard stop, the overdue branch

```python
# ── B3: the per-record deadline (REPORT §4 B3, §5) ───────────────────────────────────────────
DEADLINE_SOFT_S = 600.0   # move lane: soft gates bind for 10 min after detection
DEADLINE_WAKE_S = 300.0   # wake lane: from the wake's own due time
DEADLINE_HARD_S = 900.0   # an overdue record not in a live attempt pages this long past its deadline
DEADLINE_WIDTH = 6        # overdue actuators alive at once (BootSlots.START; §C6.3 "0/40 failures at N<=6")
SEG_HARD_PCT = 60.0       # compressor-sentinel pct that disables the bypass (sentinel trips far lower on rate)
THERMAL_HARD = 3          # kOSThermalPressureLevelTrapping; 1 (moderate) is this box's steady state at ~24/core
SENTINEL_FRESH_S = 60.0
WAKE_SUBSTATES = ("WAIT_RESET", "HELD:team")

def deadline_mode(off_file: str, shadow_file: str, env=None) -> str:
    """'off' | 'shadow' | 'on'. A file in recon/ wins (operator, read every pass, no reload)."""
    e = os.environ if env is None else env
    if os.path.exists(off_file) or e.get("LR_DEADLINE") == "off": return "off"
    if os.path.exists(shadow_file) or e.get("LR_DEADLINE") == "shadow": return "shadow"
    return "on"

def ensure_deadline(rec, env=None) -> None:
    """Set once: detected + W_soft. Never reset by an attempt, a hop or a restart (REPORT §5)."""
    if rec.kind == "limited" and rec.deadline_at is None and rec.timeline.detected:
        rec.deadline_at = rec.timeline.detected + _env_float(env, "LR_DEADLINE_SOFT_S", DEADLINE_SOFT_S)

def deadline_of(rec, env=None, wake_after_s: float = 120.0) -> Optional[float]:
    if rec.terminal is not None or rec.kind != "limited":
        return None                      # idle: no deadline unless LR_DEADLINE_IDLE_S (omitted here)
    w = rec.wait
    if rec.phase == "PRE-MOVE" and rec.substate in WAKE_SUBSTATES and not (w and w.detail == "wait-data"):
        if w is None or w.eta is None:
            return None                  # waiting on a reset nobody knows: physics, not a gate
        due = w.eta + (0.0 if w.detail == "stay" else wake_after_s + jitter_s(rec.sid))
        return due + _env_float(env, "LR_DEADLINE_WAKE_S", DEADLINE_WAKE_S)
    if rec.deadline_at is not None:
        return rec.deadline_at
    d = rec.timeline.detected
    return d + _env_float(env, "LR_DEADLINE_SOFT_S", DEADLINE_SOFT_S) if d else None

def overdue(rec, now: float, env=None) -> bool:
    d = deadline_of(rec, env)
    return d is not None and now >= d
```

**The hard stop.** It is read in-process: no fork, no subprocess and no timeout, so it can never become "our timeout
read as a verdict". It is positive-evidence-only.

```python
class HardStop:
    """'' = no positive evidence of a physical limit. Unknown is NOT a stop (operator premise), and
    is named 'unknown', never 'ok' (rule: fail-safe mimics healthy). A trip releases only after two
    clear reads >= 30 s apart with pct <= SEG_HARD_PCT - 10 (rule: release != !trip)."""
    def __init__(self, env=None, sentinel_log=None, sysctl_int=None, thermal=None, wall=None): ...
    def check(self) -> str:
        row = self._sentinel_tail()          # last JSON line of ~/.claude/logs/compressor-sentinel.jsonl
                                             # (CC_SENTINEL_LOG), 4 KB tail read, fresh iff ts age <= 60 s
        lvl = self._sysctl_int("kern.memorystatus_vm_pressure_level")   # ctypes sysctlbyname
        th = self._thermal()                 # ctypes notify_get_state("com.apple.system.thermalpressurelevel")
        why = ""
        if row is not None and int(row.get("strk") or 0) > 0: why = "compressor breach (sentinel strk>0)"
        elif row is not None and float(row.get("pct") or 0) >= self.seg_hard: why = "compressor %.1f%%" % row["pct"]
        elif lvl == 4: why = "memory pressure critical"
        elif th is not None and th >= self.thermal_hard: why = "thermal level %d" % th
        self.state = "unknown" if (row is None and lvl is None) else ("tripped" if why else "ok")
        return self._hysteresis(why, row)
```

Measured feasibility:
- `/usr/bin/python3` 3.9.6, which is the daemon's pinned interpreter (`com.reso.lr-reconciler.plist:23-25,42`), read
  `pressure_level 1` in <0.1 ms and `thermal state 1` in 0.9 ms through ctypes (M, `/tmp/b3/hw.py`).
- Six samples over 30 s at load1 233-239 read pressure 1 and thermal 1 every time (M, `/tmp/b3/hw2.py`). Thermal
  "moderate" is the steady state at ~24/core, which is why the hard line is 3 and not 1 or 2.
- A sentinel row today reads `pct 11.22`, `strk 0` (M, `tail -c 1200 ~/.claude/logs/compressor-sentinel.jsonl`).
  `strk > 0` is the sentinel's own breach verdict (`compressor-sentinel.sh:2083-2091`).

**`decide()`.** New keyword-only arguments, so every existing positional caller and test is unchanged:

```python
    def decide(self, sid, acct, now, active, unredeemed, load1, load5, ncpu, cohort="",
               overdue=False, lane_room=False):
        del load1, load5, ncpu
        if overdue and lane_room:
            hard = self.hard.check()
            if not hard:
                self.pace_ok(self.wall()); self.pace_take()      # charged, never required
                self.pacer_take(sid, acct, now)                    # charged, never refused
                self.last_admit_at = now
                self.last_terms = "deadline (memory %s)" % self.hard.state
                return True, "admit:deadline"                      # probe and drip untouched
            self.deadline_why = "hard:" + hard
        elif overdue:
            self.deadline_why = "deadline-lane"
        ...   # today's body, unchanged: restore-r → pace → pacer → probe → drip
```

The drip page queue: at `:322-324` also `self.drip_pages.append(cohort)`. `page_due` stays, because tests read it.

### 5.4 `classify.py` + `settle.py` — tell rail junk from a real hold

`settle._score` (`:269-320`) labels every held-after-confirm reason by its substate. The raw reason is lost:
`outcome()` returns `"HELD:%s after the confirm"` with the **substate** (`:125-128`). B3 keeps the raw reason.

```python
# settle.py
def _held_raw(text: str) -> str:                    # the (held: <r>) group of the last unconfirm-rc-0 line
    hits = [m for m in _RCY_HELD.finditer(text) if m.group(2) == "0"]
    return hits[-1].group(1).lower() if hits else ""
#   in _score, HOLD branch:      rec.close["hold_raw"] = _held_raw(text) or reason
#   in note_watcher_hold:        rec.close["hold_raw"] = str(row.get("class",""))[len("recycle-held-"):]
#   in note_unconfirm:           rec.close["hold_raw"] = raw read from the same actlog tail
#   in release_holds:            rec.close.pop("hold_raw", None)

# classify.py
JUNK_HOLD_RAW = frozenset(("unreachable", "exit-readback", "unknown", "wedged",
                           "pane:resolver-unavailable", "composer-unreadable"))
def junk_hold(rec) -> bool:
    """A hold our own rail produced (a read that failed), not a fact about the session. Never
    `busy`, `draft`, `bg-work*`, `focused`, `team`, `subagents`, `load`, `menu`."""
    err = rec.last_error
    return bool(err and err.cls == "HOLD" and str(rec.close.get("hold_raw", "")).lower() in JUNK_HOLD_RAW)
```

A misclassification is safe by construction. `junk_hold` only decides whether `--place` is re-asked. The actuator's
precheck runs every attempt and holds a real `busy` again.

### 5.5 `plan.py` — the kept target (placement freshness for overdue retries)

```python
KEEP_TARGET_S = 1800.0

def keeps_target(rec, facts, now, model, overdue, cfg_of) -> bool:
    if not overdue or rec.kind != "limited" or rec.phase != "PRE-MOVE": return False
    if rec.substate not in ("DETECTED", "BACKOFF"): return False          # after re-probe / after TRANSIENT
    t = rec.target_acct
    if not t or t == rec.source_acct or rec.close.get("placed_acct") != t: return False
    if now - float(rec.close.get("placed_at") or 0) > KEEP_TARGET_S: return False   # bounded staleness
    err = rec.last_error
    if err is None or not (err.cls == "TRANSIENT" or classify.junk_hold(rec)): return False  # WAIT ⇒ re-place
    if F.blocking(facts or {}, t, rec.lane, model or "", now) is not None: return False     # HARD: target capped
    return bool(cfg_of(t))
```

In `apply()` (`:434-439`), when `p.acct` is set and `p.reason != "kept:deadline"`, write
`rec.close["placed_at"] = now; rec.close["placed_acct"] = p.acct`. A kept target never refreshes its own age, so it
ages out after `KEEP_TARGET_S` and is re-placed.

Known gap: a kept target skips `--place`'s KMAX seat check. The phantom is re-charged through `--assign-many`
(`__main__.py:1082`). Gap 3 found the seat cap never bound in 1,409 measured sweeps (gap-3 §0 item 2), so this is
accepted as SOFT.

### 5.6 `__main__.py` — wiring

| Function | Change |
|---|---|
| `Ctx.__init__` (`:96-126`) | `self.deadline = "on"`, `self.deadline_used = 0`, `self.admission.hard = HardStop()` |
| `_run_pass` (`:1660-1745`) | after the mode read (`:1664`): `ctx.deadline = admit.deadline_mode(paths.p("deadline.off"), paths.p("deadline.shadow"))` |
| `_derive` (`:744-748`) | for each open record: `admit.ensure_deadline(rec)`. The first time `overdue(rec, now)` holds, set `rec.close["overdue_at"]` and emit event `overdue` (`lane=… age=…s substate=…`) |
| `_wakes` (`:447-449`) | if `pace_wake` refuses and `ctx.deadline == "on"` and `overdue(rec, now)`: `ctx.admission.pacer_take(...)`, emit `wake-deadline`, proceed |
| `_plan` (`:1006-1041`) | per lane, before `plan.place`: partition `keeps_target(...)` movers into `placed[sid] = T.Placement(acct=rec.target_acct, reason="kept:deadline", weight=rec.weight)` with event `kept-target`, and send only the rest to `--place` (skip the call if none remain) |
| `_dispatch` (`:1218-1327`) | (1) sort key becomes `(r.kind != "limited", admit.deadline_of(r) or inf, r.timeline.detected or now)`, i.e. earliest deadline first. (2) `ctx.deadline_used` = open records with `close.deadline_admitted_at` and a live actuator in `snap`, counted **once per pass and incremented per admission** (not pass-scoped: REPORT B7 class). (3) at every `continue` for an overdue record, `_deadline_note(ctx, rec, why, now)` records the blocker in `close.deadline_hold` and emits `deadline-held` on change. (4) on spawn after `admit:deadline`, set `deadline_admitted_at = now`, else pop it |
| `_admit` (`:1160-1171`) | `od = ctx.deadline == "on" and admit.overdue(rec, now)`; `lane_room = od and ctx.deadline_used < width`; pass both to `decide`. On `admit:deadline`, `ctx.deadline_used += 1`. In shadow mode: compute `od`, pass `False`, emit `deadline-shadow` ("would admit; actual: <why>") once per record per attempt |
| `_report` (`:1432-1471`) | in the per-record loop, `rep.deadline_page(cohort, r, overdue=..., live=bool(act.live_procs(r, snap)))`. After the cohorts, drain `ctx.admission.drip_pages` into `rep._once(cid, "drip", "DRIP", text)` |

### 5.7 `report.py`

`deadline_page` fires once per record, then hourly (`REFIRE_S`, `report.py:31`). All of these must hold:
- `kind == "limited"`;
- open, not ENGAGED/MOVED, not escalated (ESCALATED has its own page);
- the current state is **not** in `T.MAX_AGE_S` (`types.py:119-134`). HOLD-DRAFT, HOLD-COMPOSER, WAIT_* and similar
  already page through `max_age_page` (`report.py:985-1008`), so no record pages twice;
- `now ≥ deadline + W_hard`;
- no live actuator.

Text: `"<acct scope>: <who> — overdue since HH:MM (detected HH:MM); soft gates bypassed; blocked by
<close.deadline_hold or last_error> — next: <next_action>"`.

`next_action` (`:153-188`) gains a prefix for overdue records: `"overdue since HH:MM: "`.

### 5.8 What B3 deliberately does not do

- It does not bound the pass (`P_max`) or the attempt (`T_att`). Those are B2 and the actuators.
- It does not place a never-placed record without `--place`. That is B2's cache.
- It does not override any HARD row of §3.1 or any precheck of §3.2.
- It does not force a re-drive of a RECON-DEFECT record. It pages instead.
- It does not touch the poller or the move lane.
- It does not change `HOLD-LOAD` / typed-relaunch semantics. Residual: a precheck `HELD:load` maps to DETERMINISTIC
  (`classify.py:156-166`; `load` is not in `_TERMINAL_TRANSIENT` at `:33-35`), so if staging ever fails under
  permanent load the record escalates and is released as IMPOSSIBLE, with a page. That is a separate decision.

---

## 6. Failure modes under permanent 15-40/core

| # | Failure | Handling |
|---|---|---|
| F1 | Overdue burst onto one account (pacer bypassed) | Bounded by D = 6 alive at once, which is inside the measured-safe N ≤ 6 per account (§C6.3). The pacer slot is still charged. 429/529 telemetry does not exist (axis 05 L8) — H that 6 is safe at 40/core |
| F2 | Long attempts fill the lane (`T_att` 7-33 min at PRI 20) | A full lane falls through to today's gates, never worse. Earliest-deadline-first orders the queue. The DEADLINE page names `deadline-lane` at `W_hard` |
| F3 | Memory genuinely tight while the sentinel is quiet | The bypass also turns off at sentinel `pct ≥ 60` or pressure level 4. Otherwise an overdue first turn is a net-zero restore: the session existed before the cap (§C6.1 premise). The sentinel's own SIGSTOP/kill actuator is unchanged |
| F4 | Sentinel log stale/absent, or sysctl fails | `state = unknown`, **no stop**; the event says `memory unknown` (not `ok`). In-process reads cannot time out |
| F5 | One clear tick inside a memory incident | Hysteresis: two clear reads ≥30 s apart with `pct ≤ 50` before the bypass returns |
| F6 | System sleep | `deadline_at` shifts forward (`shift_record`); the 30 s wake-guard stays hard |
| F7 | Daemon restart (incident: 3 restarts in 70 min) | `deadline_at` is on disk, so G6 holds. The lane count is rebuilt from records and live procs. In-memory bucket/drip reset to burst, which only admits sooner |
| F8 | Census abstain (`ps` 30-37 s at PRI 31, 4× since 07:23Z, §1.4) | Hard: the pass decides nothing. That costs one pass (`P_max`), and each abstain was 1 in a row (M) |
| F9 | `--place` times out for a never-placed overdue record | No kept target exists. It stays WAIT_DATA, which already pages at 120 s (`types.py:120`). Fixed only by B2/B4 (dependency) |
| F10 | The kept target became capped after placement | `F.blocking` (`facts.py:334-373`) re-places it. If the fact lags, the existing TARGET-LIMITED hop handles it (`__main__.py:930-949`) |
| F11 | Claim held by another driver, or by the old daemon after a restart (25.9 min in the incident) | Hard, never overridden. The page names the holder pid. A6 removes the self-refusal |
| F12 | A real `busy` misread as junk | Only `--place` is skipped. The precheck holds it again (`handoff-fire.sh:3274`). Cost: one attempt |
| F13 | Pass-scoped counting (REPORT B7 class): every member in one pass sees the same lane count | `ctx.deadline_used` is incremented per admission. Test H5 pins it |
| F14 | A wall-clock jump | A forward jump makes records overdue early (bounded harm: an earlier bypass). A backward jump delays them. Same as every existing `now`-based clock |
| F15 | Kill switch flipped mid-cohort | Read every pass. Nothing to unwind: `deadline_at` stays on records and only decisions revert |
| F16 | Idle move lane holds the shared swap slots | An overdue A/R gets `boot-slots`. Cross-lane priority is not B3's. Becomes material only with D2 (warning-band shedding) — risk |

---

## 7. Test plan

**Isolation is mandatory.** The new file `lr_recon/tests/test_deadline.py` sets both `LR_STATE_DIR` and `HOME` to a
tempdir in `setUp`, as `test_main.py:84-113` does.
- One existing suite, `test_restore_budget_bound.StandingRefusalIsVisible`, builds its paths with
  `T.Paths.from_env(root=<tmp>)` and then writes `paths.recon_on` and builds `M.Ctx` (`:142-145`). It patches neither
  `LR_STATE_DIR` nor `HOME`.
- `Paths.from_env` resolves `lr_root` to `$HOME/.reso/limit-recover` when `LR_STATE_DIR` is unset (`types.py:238-241`).
- So that suite touches the **live** `recon.on` and the live swap slots when run with a real HOME (§13).
- `test_act.py` and `test_settle.py` also write `recon_on`, but they build `T.Paths(lr_root=<tmp>)` explicitly
  (`test_act.py:27-32`, `test_settle.py:309`), so they are isolated (M, read).

Behavioural [RED] cases use only pre-existing entry points (`_dispatch`, `_plan`, `_wakes`, `_report`, `store`
round-trip, `shift_record`), setting `deadline_at` with `setattr`. They therefore fail on the pre-fix tree for the
behavioural reason, not for an `AttributeError`. UNIT cases exercise new APIs and are not red-proofs. CONTROL cases
are equivalence guards and pass in both arms (rule "Green in both arms", `.claude/rules/…situational.md:62`). Each
CONTROL names the mutation it catches.

| # | Case | Arm today → after | Evidence today |
|---|---|---|---|
| D1 | **[RED]** 30 PLANNED limited on one account, detected now-1200 → spawns = 6, every one `admit:deadline` | 3 → 6 | M `/tmp/b3/red.py`: 3 spawned, 27 × `pacer:next` |
| D2 | CONTROL: the same records detected now → 3 (pacer). Mutation: `overdue()` always True ⇒ red | 3 → 3 | `test_main.py:235-246` |
| D3 | **[RED]** probe standing on rc 9; 10 overdue C records (RELAUNCHED-UNPROMPTED, launcher not admitted) over 4 accounts → 6 in one pass, the probe not called for them | 1 (drip) → 6 | by code: `admit.py:311-326` |
| D4 | **[RED]** `decide` path: an overdue member skips the probe (mock call count 0) | probe called → not called | `admit.py:310` |
| D5 | **[RED]** cohort simulation (decide only, fake wall, 10 s passes, 24 members, rc 9): every member's first admission ≤ its deadline + one pass | last +690 s → ≤ deadline + 10 s | M `/tmp/b3/red.py` |
| H1-H7 | CONTROL, all on overdue records; `act.spawn` mock never called and `close.deadline_hold` names the blocker. Cases: team-live; duplicate-risk; claim held by a live driver (no token minted, pattern of `test_wave_g.OneDriverPerSession`); process-live; plan-only; C inside `C_GRACE_S`; census HOLD-DRAFT / HOLD-BGWORK ship-land / TEAMMATE / SPLIT-BRAIN never in `plan.movers`. Mutation: moving the overdue branch into `may_actuate` or before `hold_claim` ⇒ red | held → held | by code §3.1 |
| H8 | CONTROL: `act.actuator_env` and argv of an overdue record equal those of a fresh one (record ids aside). Mutation: any env flag added for overdue ⇒ red | equal → equal | `act.py:50-93` |
| H9 | UNIT: sentinel row `strk 1` → overdue falls through (probe called, no `admit:deadline`); `pct 61` likewise; pressure 4 likewise; thermal 1 and 2 → not hard; thermal 3 → hard | — | M: thermal 1 at ~24/core |
| H10 | UNIT: sentinel absent and sysctl None → `admit:deadline`, and the event says `memory unknown` | — | rule "Fail-safe mimics healthy", `:8` |
| H11 | UNIT: after a trip, one clear read does not release; two reads ≥30 s apart at `pct ≤ 50` do | — | rule "Release ≠ !trip", `:6` |
| K1 | **[RED]** overdue BACKOFF, `last_error` TRANSIENT, target next4 placed 340 s ago, `--place` rc 124 → PLANNED on next4 plus a `kept-target` event | `placed=0 BACKOFF` → PLANNED | M `/tmp/b3/red2.py` |
| K2 | **[RED]** overdue DETECTED after re-probe, `hold_raw unreachable` → kept | re-placed → kept | by code |
| K3 | CONTROL: `hold_raw busy` → `--place` called, not kept. Mutation: `busy` in the junk set ⇒ red | — | |
| K4 | CONTROL: fact `next4.7d` live → `--place` called, never PLANNED on next4. Mutation: drop `F.blocking` ⇒ red | — | |
| K5 | CONTROL: non-overdue TRANSIENT retry → `--place` called | — | |
| K6 | UNIT: a kept target older than `KEEP_TARGET_S` → re-placed; a kept placement does not refresh `placed_at` | — | |
| W1 | **[RED]** stay record with eta now-400 (wake deadline passed), source pacer full (3 other sids at now) → `_wakes` returns 1, `actions[sid] == "wake"` | 0 → 1 | `__main__.py:447-449` |
| W2 | CONTROL: the same wake inside its 300 s window waits on the pacer | 0 → 0 | `test_main.py:337` pattern |
| C1 | **[RED]** `shift_record(rec, 3600)` moves `deadline_at` by 3600 | unchanged → +3600 | `clock.py:167-180` |
| C2 | **[RED]** `store.save_record` → `load_all` keeps `deadline_at` (restart neutrality G6) | dropped (unknown key) → kept | `types.py:3-6` |
| C3 | UNIT: `deadline_at` survives `settle._score`, `new_attempt` (hop) and `undo_hop`; WAIT_RESET uses the wake clock; idle has none | — | |
| P1 | **[RED]** overdue BACKOFF loop (TRANSIENT ×8), no live actuator, now = deadline+901 → exactly one DEADLINE page naming the last error; +60 s none; +3601 re-fire | none → 1 | M: `BACKOFF_PAGE` has no reader |
| P2 | CONTROL: overdue HOLD-DRAFT pages MAX-AGE only, never DEADLINE. Mutation: drop the `MAX_AGE_S` exclusion ⇒ red | 1 → 1 | |
| P3 | **[RED]** a drip opening emits one DRIP page per cohort | 0 → 1 | M: `page_due` has no reader |
| S1 | CONTROL: `recon/deadline.off` present → D1's scenario spawns 3 (today). Mutation: switch ignored ⇒ red | 3 → 3 | |
| S2 | UNIT: `deadline.shadow` → D1 spawns 3, plus 27 `deadline-shadow` events | — | |

- **Bats wrapper.** `tests/lr-recon-deadline.bats` runs the [RED] and CONTROL cases one per `@test`, labelled like
  `tests/lr-recon-one-driver.bats:20-35`.
- **Proving red on the pre-fix tree** (no stash, scratch tree only, and the unmutated control first: rule "Mutant
  scratch needs a control", `:258`):

```bash
PRE=$(git rev-parse HEAD)          # the commit before the B3 implementation commit
rm -rf /tmp/b3-pre && mkdir -p /tmp/b3-pre && git archive "$PRE" scripts/limit-recover tests | tar -x -C /tmp/b3-pre
cd /tmp/b3-pre/scripts/limit-recover && PYTHONDONTWRITEBYTECODE=1 HOME=/tmp/b3-pre/home LR_STATE_DIR=/tmp/b3-pre/lr \
  python3 -m unittest lr_recon.tests.test_main          # control: must be all OK
cp <worktree>/scripts/limit-recover/lr_recon/tests/test_deadline.py lr_recon/tests/
PYTHONDONTWRITEBYTECODE=1 HOME=/tmp/b3-pre/home LR_STATE_DIR=/tmp/b3-pre/lr \
  python3 -m unittest lr_recon.tests.test_deadline      # every [RED] fails on its assertion; every CONTROL passes
```

- **Suites to stay green.** All of `lr_recon/tests`, plus `tests/lr-recon-*.bats`.
  - M baseline: `test_admit` + `test_restore_budget_bound` ran 28 tests OK in 1.0 s with HOME/TMPDIR under `/tmp/b3`.
- **Under load (B1, not B3).** §5's harness asserts, per member and per load arm, that
  `t_first − deadline ≤ P_max + ceil(k/D)·T_att`, with D = 6. The red arm is today's code at `taskpolicy -c utility`.
  Per-member assertions, not aggregate ones (rule "Aggregate control misses a per-member zero", `:82`).

---

## 8. The guarantee B3 delivers

For every LIMITED record *r* not held by a §3.1/§3.2 HARD gate:

```
t_first(r) ≤ deadline(r) + P_max + ceil(k_r / D) · T_att        deadline(r) = t_detect(r) + 600 s (move lane)
retry(r)   ≤ t_fail + B_max(300 s) + P_max                       (kept target: no --place in between)
page(r)    at deadline(r) + 900 s while not in a live attempt     (hard-held or not, unless a MAX-AGE/ESCALATED page owns it)
```

- None of these terms reads load (G1). B3 adds no load term.
- Only `P_max` and `T_att` can stretch with load, and B3 does not bound them.
- With today's measured quiet-pass `P_max` (max 193 s) and the target `T_att` of 15 min, the 9th member of a
  9-member cohort is first attempted ≤ 10 + 3.2 + 2·15 ≈ 43 min after detection (E, REPORT §5 formula with D = 6).
- With the PRI-20 `T_att` of ~31 min it would be ≈ 75 min. That is why G is claimable only after B2 bounds the attempt
  (axis 05 skeptic L2).

---

## 9. Rollout, kill switch, operator steps

1. **Commit 1:** `types.py` `deadline_at` field, `clock.shift_record`, tests C1/C2. Its own commit (`types.py:4-5`).
2. **Commit 2:** `test_deadline.py` and the bats wrapper. Verify red on the scratch pre-fix tree (§7).
3. **Commit 3:** the implementation (§5.3-5.7). All `lr_recon` suites green. Default **on**.
4. **Deploy.** The runtime needs no new link, because every change is to an already-linked module. The new test file is
   linked by the normal install (`install.sh` lr_recon leg; parity check `scripts/deploy-link-parity.sh:572-577`).
5. **Activation: operator only** (agents may not reload launchd). At a quiet moment, meaning no open limited cohort
   with a live actuator:
   ```bash
   cat ~/.reso/limit-recover/recon/readout.line
   bash ~/.claude/scripts/limit-recover/lr-band-reload.sh                     # dry run
   bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm lr-band   # waits for no lr-recon-act child, reloads, reads band back
   tail -1 ~/.reso/limit-recover/recon/restarts.jsonl                         # the new daemon's start
   ```
   Do not restart mid-cohort to deploy (REPORT A6 i).
6. **Kill switch** (no reload, read every pass):
   ```bash
   touch ~/.reso/limit-recover/recon/deadline.off       # off: today's gates exactly (test S1)
   rm ~/.reso/limit-recover/recon/deadline.off          # back on
   touch ~/.reso/limit-recover/recon/deadline.shadow    # optional: log would-admit, change nothing
   ```
7. **First live cohort: what to read.**
   - `grep -E '"ev": ?"(overdue|kept-target|wake-deadline|deadline-held)"' ~/.reso/limit-recover/recon/events.jsonl`
   - the `spawn` rows that followed an `admit:deadline` admission;
   - load1 and the daemon's band beside each reading (rule "Verify a cure under its load", `:83`).

---

## 10. Estimated size

E, by summing the §5 sketches:

| File | Lines |
|---|---|
| `admit.py` | +140 |
| `__main__.py` | +95 |
| `plan.py` | +45 |
| `report.py` | +45 |
| `settle.py` | +20 |
| `classify.py` | +12 |
| `types.py` | +6 |
| `clock.py` | +2 |
| **Production total** | **≈ 365** |
| `test_deadline.py` | ≈ 430 |
| bats wrapper | ≈ 55 |
| **Total** | **≈ 850** |

---

## 11. Dependencies on other items

| Item | Relation |
|---|---|
| B2-bounded-pass | **Soft dependency.** It bounds `P_max` and `T_att`, without which §8 is not a number. Its placement cache extends "kept target" to first placements (F9). B3 can land first |
| A6-restart-safety | Complementary. A claim-held self-refusal after a restart is HARD for B3 (F11), and A6 removes it. B3 itself is restart-neutral |
| B1-load-harness | Proves §8 under load. B3's unit tests do not need it |
| B4-cheap-place | Complementary: fewer `--place` timeouts for first placements |
| B6-telemetry | Consumes B3's events (`overdue`, `kept-target`, `deadline-held`). No dependency |
| B7-now-audit | B3 adds `now` comparisons. The lane counter is per admission by design (F13). B7 should include them |
| B5-kitty-off-critical-path, B8-kitty-hygiene | Reduce the junk holds B3 routes around. Independent |
| C2-socket-prompt | The C lane. B3's overdue admission applies unchanged to a socket-delivered first turn |
| G2-self-recovery | A self-recovering session holds the claim, so B3 sees HARD claim-held and pages at `W_hard` if it stalls. Compatible |
| A7-limited-cohort-ruling | plan-only stays HARD in B3. Now moot: both markers exist (M) |
| D2-warning-band-shedding | Raises move-lane use of the shared slots (F16) |
| D1-repick-ruling, C1-credential-flip | Independent |

---

## 12. Risks and conviction

- **R1, small payoff after waves 1-5.**
  - The admission gates already release at 1/30 s per cohort (§1.1). B3 matters for cohorts above ~20 members on a
    standing soft refusal, for retries that hit a 120 s `--place` timeout, and for pages.
  - The `P_max`/`T_att` share of delay (REPORT §2.2: 49% band family; attempt wall 12.8%) is outside B3.
- **R2, untested on a real cohort.** There has been no limit cohort since the PRI-31 reload (M). The first one is the
  real test; shadow mode exists for that.
- **R3, burst safety above N = 6 per account is unmeasured** (architecture §C6.3). D = 6 keeps inside the measured range.
- **R4, the kept target bypasses `--place`'s KMAX check** for overdue retries (§5.5). Accepted as SOFT on gap-3's 1,409
  sweeps.
- **R5, memory and thermal hard lines are new thresholds.** `pct 60`, pressure 4 and thermal 3 are positive-evidence
  only and are knobs. No incident history pins them (H).
- **R6, page noise.** A record overdue and between slow attempts pages at detection + 25 min. If PRI-31 `T_att` turns
  out to be ~30 min, raise `LR_DEADLINE_HARD_S`.
- **R7, test-isolation hazard in neighbouring suites** (§7, §13). The new tests must not copy that pattern.

**Conviction 62%:** the mechanism is sound and safe by construction (§3.2), but its measurable latency effect
post-waves is modest and unproven live.

---

## 13. Side finding (reported, not acted on)

During this research, between 17:38Z and 17:56Z, the live `~/.reso/limit-recover/recon.on` mtime moved from 09:46 to
12:55:51 CDT. Measured with `ls -la` and then `stat -f '%Sm' ~/.reso/limit-recover/recon.on`
=> `2026-10-20T12:55:51-0500`.

In the same window, live swap slot `locks/swap-slots/slot-1` was taken by pid 81798, lstart `Tue Oct 20 17:55:15 2026`.
That process is now dead: `ps -p 81798` printed nothing (M).

Both match `test_restore_budget_bound.StandingRefusalIsVisible.setUp`:
- `open(self.paths.recon_on, "w")` at `:144`, with no `LR_STATE_DIR` and no HOME patch;
- `M.Ctx` builds a `BootSlots` on `lr_root/locks/swap-slots` (`__main__.py:101-105`).

The likely cause is that suite run with the real HOME. `test_act.py` and `test_settle.py` set `lr_root` to a tmpdir
and are not implicated.

**It was not this run.** Both of my test runs set `HOME=/tmp/b3/home`. The first failed with `FileNotFoundError:
'/tmp/b3/home/.reso/limit-recover/recon.on'`, and the second wrote its slots to
`/tmp/b3/home/.reso/limit-recover/locks/swap-slots` (M, `ls`).

**Hypothesis:** a concurrent agent ran `lr_recon` tests against the live tree. The effect here was benign:
- `recon.on` was already present and empty;
- a dead-pid slot is reclaimable by `_slot_live`, `admit.py:364-388`.

If `recon.on` had been absent, such a run would have **created the operator's actuation cutover file**.

---

## Appendix: commands run (all read-only, or writing only under /tmp/b3)

| Command | What it established |
|---|---|
| `git log`, `git show --stat` for 07ce89a99…28b25a119, `git diff --quiet 28b25a119 6fdf87eca -- …` | landed waves; line numbers valid on main |
| `sed`/`grep -n` over `lr_recon/{admit,__main__,act,plan,settle,classify,census,types,clock,report,facts}.py`, `handoff-fire.sh:13635-13996`, `lr-handoff.sh:1423-1495`, `capacity-admit.sh:1760-1851` | every file:line above |
| `grep -n page_due\|BACKOFF_PAGE\|slo_page lr_recon/*.py` | the three dead pages |
| `python3 -I /tmp/b3/open.py` (reads `recon/sessions/*.json`) | 4 open records, all idle PARKED-REBOOT from ~20 days ago |
| python over `recon/events.jsonl` (since 1792480997) and `recon/band.log` | 4 abstains at PRI 31; pass period p50 10 / p90 13 / p99 19 / max 193 s |
| python over `recon/events.jsonl` 02:30-06:26Z for the 9 incident sids | decide-refusal delays before first spawns: 7aae55e1 11.6 min, db755a94 25.1 min (own 02:43:16 → spawn 03:08:24) |
| `python3 -I /tmp/b3/red.py`, `/tmp/b3/red2.py` | the D1/D5/K1 red values |
| `python3 -I /tmp/b3/hw.py`, `/tmp/b3/hw2.py`; `/usr/bin/python3 -I /tmp/b3/hw.py` | in-process pressure 1 and thermal 1 at load1 233-239, <1 ms |
| `tail -c 1200 ~/.claude/logs/compressor-sentinel.jsonl` | sentinel row format (`pct`, `strk`) |
| `HOME=/tmp/b3/home TMPDIR=/tmp/b3/tmp PYTHONDONTWRITEBYTECODE=1 python3 -m unittest lr_recon.tests.test_admit lr_recon.tests.test_restore_budget_bound` | baseline 28 OK |
| `ls -la` of `~/.reso/limit-recover/{autorecover.on,recon.on,recon/autorecover.on,locks/swap-slots}` | both zero-human markers present; §13 |

---

## Review — efficacy-under-permanent-load

Adversarial review, 2026-10-20 ~18:20-18:45Z. The question: at 15-40/core with every lane at PRI 31, does B3 bound
recovery time, and does any new wait, bound or gate assume load falls? Read-only. Simulations wrote only under
`/tmp/b3rev/`. Labels as above: M = measured (command named), E = estimated (method named), H = hypothesis.

**Verdict: NEEDS-CHANGES. Efficacy conviction 45%, down from 62%.**

What holds:
- The mechanism is safe. It is never worse than today, because a full lane or a tripped stop only removes the
  bypass (§4).
- It adds no load term.
- Every file:line I checked matches the code at `28b25a119`: `admit.py:264-333`, `:170-210`, `:311-326`;
  `__main__.py:408-455`, `:1132-1171`, `:1218-1327`, `:1660-1745`; `plan.py:211-287`, `:358-375`; `settle.py:60-78`,
  `:269-320`; `classify.py:17-35`, `:146-197`; `clock.py:167-180`; `types.py:119-134`.
- The three dead pages are real. `grep -n "page_due\|BACKOFF_PAGE\|slo_page" lr_recon/*.py` finds only `admit.py:24,124,163,324`,
  `classify.py:177,191` and `report.py:1010` (M).
- The quiet-pass period reproduces. Over `recon/band.log`, n=4120: p50 10 s, p90 13 s, p99 20 s, max 193 s, 5 gaps
  over 60 s, every row `pri=31` (M).

What does not hold is the bound in §8. For moves (A/R), B3's bypass sits *behind* the boot-slot gate, which is the
real limit at load. Several of its new bounds are sized for a quiet box.

### R1. For A/R moves, the bypass changes nothing measurable; boot slots bind first (M, simulation)

- `_admit` takes a boot slot **before** it calls `decide` (`__main__.py:1139-1140`). The slot is held until no
  BOOTING actuator of the record is alive (`:1124-1129`), so for the actuator's whole wall time, not for the boot.
- The slot store is shared with the move lane (`admit.py:353-360`), whose width is `LR_MOVE_SLOTS` default 4
  (`lr-move-worker.sh:57`, `:371`).
- `BootSlots.on_wave` (AIMD) has no caller (`grep -rn on_wave lr_recon/*.py` => only its definition), so the limit
  stays at 6.

`/tmp/b3rev/slots2.py` runs the real `_dispatch` over 10 s passes. It models today's code and a crude B3 (`decide`
admits once `now ≥ detected+600`, lane D=6). It mocks `spawn` so each actuator stays live in `snap` for `T_att`, and
it pre-holds 0 or 4 swap slots as "the move lane". Every row is k=30 limited records, detected at t0, over 3 target
accounts (M):

| T_att | probe | move-lane slots held | today: last first attempt | B3 model: last first attempt |
|---|---|---|---|---|
| 300 s | admits | 0 | 1200 s | **1200 s** |
| 300 s | rc 9 | 0 | 1350 s | **1350 s** |
| 300 s | admits | 4 | 4200 s | **4200 s** |
| 900 s | admits | 0 | 3600 s | **3600 s** |
| 900 s | rc 9 | 4 | 12630 s | **12630 s** |

All 8 A/R scenarios were identical between the two arms, including p50 and the count started by 600 s. The reasons:
- The drip (1 per 30 s) already admits faster than slots turn over (6 per T_att).
- Today's oldest-first sort (`__main__.py:1225`) is already earliest-deadline-first when every deadline is
  detection + 600 s.

D1's "3 → 6" is a single-pass artefact: today reaches 6 one pacer release (20 s) later. Separately, the 900 s / rc 9 /
4-slot row's 12630 s (3.5 h) **violates §8 as written**. With D=6 the formula gives 600 + 10 + 5·900 ≈ 5110 s. It holds
only with an effective width of 2.

The lanes where B3 does move the number are the boot-slot-free ones. `/tmp/b3rev/clane.py` runs C on
RELAUNCHED/UNPROMPTED records with T_att 20 s and the probe standing on rc 9 (M):
- k=30: the last first attempt falls from 870 s to 620 s;
- k=12: no change (330 s in both arms).

This matches the design's own "minutes" caveat (§0 item 1). It is the only latency gain the simulation shows.

### R2. §8's retry bound omits the slot wait

`retry ≤ t_fail + B_max + P_max` ignores `boot-slots` (`__main__.py:1139`) and `workers-cap` (`act.py:477-478`). Both
are refused before or around `decide`, and both are held for T_att by other actuators. Under permanent load the retry
waits up to ⌈q/D_eff⌉·T_att, where q is the queue ahead (E, same model as R1).

### R3. `KEEP_TARGET_S` is a fixed wall from placement and expires inside one load-stretched attempt

- `keeps_target` refuses once `now − placed_at > 1800 s` (§5.5). A kept target never refreshes `placed_at`.
- At PRI 20, attempts were 7-33 min (§1.4, axis 05).
- So the kept target survives at most one long attempt plus its backoff. A failure late in a long attempt (unreachable
  after the transplant, exit-readback) re-asks `--place`. `--place` is bounded at 120 s at ≥15/core
  (`plan.py:358-364`); measured `rc=124 … dur=120.2s` at load1 163-363 before the reload (`events.jsonl` `place` rows,
  M).
- K1 therefore helps only failures that come early in the precheck. This is a bound sized as if attempts stay short.

### R4. The hard stop can pin itself off, and its thermal line sits one step above today's steady state

1. **Thermal (M).** `/usr/bin/python3 -I /tmp/b3rev/therm.py` (the design's own ctypes `notify_get_state` read) gave
   `thermal 2` in **16 of 16** samples over 80 s, at load1 146-157 (14.6-15.7/core), with pressure 1. §5.3 says
   "1 (moderate) is this box's steady state at ~24/core". Today, at the *bottom* of the premise range, the box sits at
   2 (heavy), one level below `THERMAL_HARD = 3`. Thermal 3 at 30-40/core is unmeasured (H). If it holds there, B3 is
   off for as long as load stays high: a load-correlated gate in disguise.
2. **Release needs a fresh sentinel row.** §5.3 / F5 release only after "two clear reads ≥30 s apart with pct ≤ 50".
   The sentinel log is often stale. Over `compressor-sentinel.jsonl.20261020T090406Z.gz` (2026-10-09..20) there were
   293 gaps over 60 s and a maximum gap of 11276 s (M, `python3 -I /tmp/b3rev/sent.py`). A stale row is `unknown`, and
   unknown is not a stop. But if release is coded as "a fresh row with pct ≤ 50", a trip followed by a stale sentinel
   never releases.
3. **Measured cost of the strk/pct rule alone** (E: `/tmp/b3rev/sent2.py` replays §5.3's trip and hysteresis over the
   sentinel rows):
   - the bypass would have been off for 8.5% of the 02:30-06:30Z incident window;
   - about 14% of 2026-10-09..20, with continuous off runs up to ~54 min.
   - It falls back to today's gates, so nothing gets worse. But §8 is silent for that time, and nothing pages that the
     contract is suspended.

### R5. A failed mint re-runs the probe B3 skipped, silently

- `_admit` sets `rec.admit_token = mint_token(...) or ""` (`__main__.py:1167-1170`) and emits no event on `None`.
- `mint_token` is a forked `bash -c 'source capacity-admit.sh; …'` with the same 30 s bound as the probe
  (`admit.py:240-255`, `:68-81`).
- With no token, `actuator_env` sets no `LR_ADMIT_TOKEN_PATH` (`act.py:87-88`). lr-handoff then runs its own
  `lr_capacity_probe_corrected`, which applies the same headroom, segment and active terms, and returns 6
  `PARKED capacity` on a refusal (`lr-handoff.sh:1590-1599`).
- `map_notmoved("capacity…")` maps that to WAIT_CAPACITY (`classify.py:163-164`), which is not a kept-target state.
- So an `admit:deadline` whose mint times out at load re-enters exactly the soft gate the overdue branch bypassed, and
  logs nothing. Frequency at PRI 31 is unmeasured. The idl ledger has one lr-handoff self-probe at 04:16:30Z
  (`~/.claude/autonomy/idl.jsonl`, M), cause unknown (H).

### R6. `P_max` grows with cohort size on the fall-through path, and §8 uses the quiet-pass value

- In `decide` the probe runs **before** the drip check (`admit.py:310-321`). Every "drip" refusal therefore costs one
  serial `bash` fork bounded at 30 s.
- A refusal consumes neither the pace token nor the pacer slot, so every member with pacer room probes on every pass.
- B3 removes this only for overdue records inside lane room. Non-overdue members, a full lane and a tripped stop all
  keep probing per member per pass.
- The probe command carries no sid (`admit.py:224-231`; R is frozen per active period), so the k calls in a pass are
  one question asked k times.
- §1.4's p99 20 s is from quiet passes with no movers. A cohort pass adds ≤120 s of `--place` per lane
  (`__main__.py:1006-1041`) plus ≤30 s per probe and per mint (E, from the bounds).

### R7. Lane occupancy counts adopted watchers, and nothing bounds a lane member's life

- `ctx.deadline_used` counts `act.live_procs` (§5.6). `adopt` runs every pass (`__main__.py:748`) and records any ps
  row carrying `--record-id <rid>`, including `__recycle` watchers (`act.py:360-372`).
- So the lane drains on watcher lifetime. BootSlots instead count only the BOOTING actuator (`__main__.py:1126-1127`).
- No reconciler-side wall cap on an actuator exists. A grep for kill, budget or `T_ATT` in `lr_recon/*.py` finds only
  `os.kill(pid, 0)` at `admit.py:377` (M).
- A hung overdue actuator therefore holds a D slot (and a boot slot) indefinitely, and ⌈k/D⌉·T_att has no T_att.

### R8. Re-offered reset waits come back overdue by hours and jump the queue

- `deadline_of` uses the wake clock only while the substate is WAIT_RESET or HELD:team (§5.3).
- `plan.movers` re-offers a WAIT_RESET to `--place` at `eta + REOFFER_AFTER_S` (900 s) or on a source re-read
  (`plan.py:225-236`). Once placed, the record falls back to `deadline_at = detected + 600`, which may be hours past.
- It is then instantly overdue. The earliest-deadline-first sort ranks it ahead of fresh detections, which inflates
  every fresh record's k_r.
- This contradicts §2's own reason for a wake-lane clock.

### Required changes

1. **Correct §8 to the binding width.** For A/R, use D_eff = min(D, free boot slots), where free = 6 − swap slots held
   by the move lane (≥ 2 with `LR_MOVE_SLOTS` 4).
   - Restate the estimate: 9 members at T_att 15 min ≈ 10 + 3 + 4·15 ≈ 73 min (E). 30 members ≈ 3.5 h (M, R1).
   - Add the slot and workers-cap wait to the retry bound.
   - Either decide cross-lane slot priority for overdue records now (e.g. lr-move-worker yields a slot when an
     overdue reconciler record waits on `boot-slots`), or name B2 and the slot policy as **hard** prerequisites of
     any §8 claim, not soft ones.
2. **Prove the bound where it is set.** Add a multi-pass `_dispatch` test with actuators that stay live (pattern:
   `/tmp/b3rev/slots2.py`) and 0 or 4 move-lane slots held. Assert per member
   `t_first ≤ deadline + P + ⌈k_r/D_eff⌉·T_att`.
   - Cite D1/D5 only as decide-level facts.
   - Re-state the value claim as: C/wake tails under a standing refusal at k ≳ 20, kept-target retries, and pages.
3. **No spawn without the token B3 admitted.** On `admit:deadline`, if `mint_token` returns `None`, do not spawn an
   A/R actuator. Emit `deadline-mint-failed`, keep the pace and pacer charge, and retry next pass. An in-process mint
   would also remove a 30 s fork from the pass.
4. **One probe per pass.** Memoize `probe()` for the pass's `now` (the command is sid-free), so the fall-through paths
   do not make `P_max` ∝ k. Alternatively, make B2's async probe a hard prerequisite.
5. **Age the kept target from the last attempt's end**, or from the newest fact about the target, not from placement.
   Or size `KEEP_TARGET_S` ≥ T_att budget + B_max + P_max, and say which budget.
6. **Make the hard stop unable to pin itself.**
   - (a) A stale or absent sentinel row counts as a clear read for release.
   - (b) A trip lasting longer than `W_hard` while overdue records wait pages "deadline bypass off: <reason> for N min".
   - (c) Log thermal and pressure per pass beside `band.log`, and set `THERMAL_HARD` from readings at ≥30/core. As
     measured, thermal is already 2 at 15/core. Dropping thermal from the stop is an operator call (REPORT §5 lists
     it as hard).
   - (d) State in §8 that while the stop is tripped the bound is today's drip plus slots.
7. **Count lane occupancy only on non-adopted `role == "actuator"` processes**, as BootSlots do. Exclude (and page)
   lane members whose actuator is older than a stated T_att budget, so hung actuators cannot consume D.
8. **Rebase the deadline on leaving a reset wait.** When a record leaves WAIT_RESET/HELD:team for a move, set
   `deadline_at = max(deadline_at, wake_due + W_wake)`, the same treatment as a sleep. Add a test that a re-offered
   weekly-reset record does not sort ahead of a fresh detection.

**Deviation.** My first simulation forked `ps` per slot check (`_slot_live` → `proc_lstart`) and ran far longer than
planned. To stop adding fork load to the production box, I terminated that one process, pid 37140: my own
`python3 -I /tmp/b3rev/slots.py`, started minutes earlier. No other process was signalled. The rerun (`slots2.py`) caches
the lstart in-process and wrote only under `/tmp/b3rev/lr2`.

---

## Review — correctness-and-safety

Adversarial review, 2026-10-20 ~18:10-18:30Z, worktree at `28b25a119`. Read-only. My scripts ran with
`HOME=/tmp/b3rev/home LR_STATE_DIR=/tmp/b3rev/lr*` and wrote only under `/tmp/b3rev` (`verify.py` asserts
`paths.lr_root` starts with `/tmp/b3rev`). Labels as above: M = measured (command named), E = estimated, H = hypothesis.

**Verdict: NEEDS-CHANGES. Adjusted conviction 52% (design: 62%).**

The core safety claim survives: every HARD gate runs before `decide()`, and B3 passes nothing to the actuator. But
the deadline lane, as specified, does not bound what the design says it bounds. Three new code paths can crash-loop
the daemon. The proposed page shape inflates `P_max` and double-pages. And one wording change breaks 5 existing
tests.

### R.1 What I tried to refute and could not (holds)

- **Hard gates precede the bypass.** In `_dispatch`, `act.choose`, then C quiet grace (`__main__.py:1236-1242`),
  then `may_actuate` (`act.py:438-479`), then `hold_claim` (`__main__.py:1248-1268`) all run before `_admit` →
  `decide` (`__main__.py:1269`). `actuator_env` reads no admission state (`act.py:50-93`). So H8's premise holds.
- **Rollback is safe.** `from_dict` ignores unknown keys (`types.py:184-191`) and `to_dict` is `dataclasses.asdict`
  (`types.py:194-195`). So an older daemon loads a record that has `deadline_at`, and C2 is genuinely red today (a
  `setattr` attribute is dropped on save).
- **K2's premise holds.** `reprobe` keeps `target_acct` and the HOLD `last_error`, and it does not call
  `release_holds`, so a `hold_raw` would survive into DETECTED.
  - `settle.py:359-361`, `:432-444`.
  - M, `python3 -I /tmp/b3rev/verify.py` => `after reprobe: substate DETECTED target next4 last_error HOLD`.
- **A source that resets mid-retry is not force-moved onto the kept target.** `settle.cohort_exit` runs in
  `_derive` before `_plan`. It turns a PRE-MOVE member whose source recovered into a stay or NOT_NEEDED
  (`settle.py:1047-1112`, `__main__.py:769-778`).
- **D1 baseline.** M, `verify.py` => `D1 baseline: spawned=3 refusals={'pacer:next': 27} boots.limit=6`.
- **The three dead pages.** `grep -rn "page_due\|BACKOFF_PAGE\|slo_page" scripts bin tests` => only their
  definitions and unit tests read them (M).
- **Sleep shift.** `shift_record` already moves `wait.eta` (`clock.py:167-180`), so the wake-lane deadline shifts
  for free. Only `deadline_at` needs the new line.
- **Line citations.** I spot-checked 40+ of them across `act.py`, `__main__.py`, `admit.py`, `settle.py`,
  `classify.py`, `plan.py`, `types.py`, `report.py`, `handoff-fire.sh` (13 lines), `capacity-admit.sh` (7 lines)
  and the plist. All matched.

### R.2 Findings and required changes

**F-A (HIGH, breaks the design's own safety bound). The lane counts live actuators, but the first-turn actuators
are short-lived.**
- What the actuators do:
  - C and C-retry are `cc_tui_submit` (`act.py:207-210`). The wake is `lr_focus_gate` plus `cc_tui_submit`
    (`act.py:226-244`).
  - `cc_tui_submit` returns rc 0 as soon as the user record lands (`scripts/lib/cc-tui.sh:9`). That is long before
    ENGAGED.
- M, `python3 -I /tmp/b3rev/c_life.py` over `recon/events.jsonl`, spawn→exit:

  | Actuator | n | Lifetime |
  |---|---|---|
  | C | 2 | 24.2-24.5 s |
  | A | 20 | p50 754 s |
  | R | 19 | p50 993 s |

- So a lane slot taken by an overdue C frees by the next pass. §5.6(2) counts "open records with
  `deadline_admitted_at` and a live actuator", which admits **6 overdue first turns per pass**, all of which may go
  to one account.
- E, the design's rule applied with the measured p50 pass of 10 s: up to ~36 first turns/min onto one account.
  Today's pacer allows 3 per 20 s (9/min, `admit.py:187-198`).
- That contradicts §4 ("Overdue first turns per account are bounded by D = 6") and F1. The architecture's
  measured-safe range is "N≤6" first turns (`LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md:213`).
- A/R are additionally bounded by BootSlots, but C, C-retry and wakes are not.
- **Required changes:**
  - Lane occupancy = deadline-admitted first turns that are **submitted and not yet ENGAGED**: open, phase not in
    ENGAGED/MOVED, admitted ≤ a stated bound ago. Do not use live actuator processes.
  - Add a per-target-account cap on deadline admissions (≤6) inside the pacer window.
  - New test D6: 30 overdue C records on one account, with the actuator dead by the next snapshot, over 5 passes.
    Assert ≤6 un-ENGAGED deadline first turns on that account at every pass. Mutation: count `live_procs` ⇒ red.

**F-B (HIGH, strand by crash loop). New in-pass code must never raise.**
- Why any raise is a strand:
  - The daemon loop has no exception guard around `run_pass` (`__main__.py:1827-1849`). Only `_report` catches
    (`__main__.py:1446-1456`).
  - launchd restarts the daemon with `KeepAlive` and `ThrottleInterval 10` (`com.reso.lr-reconciler.plist:45-46`).
  - So a raise in `_derive`, `_wakes`, `_plan` or `_dispatch` repeats on every pass and strands every record, not
    just overdue ones.
- Concrete defects in the sketch:
  1. `ensure_deadline` and `deadline_of` take `env=None` and pass it to `_env_float`. `admit.py` has no
     `_env_float`, and `clock._env_float` does `env.get(...)` (`clock.py:62-65`). That raises AttributeError on
     every pass that has an open limited record.
  2. `HardStop.check` compares `float(row.get("pct") or 0)` but formats the raw `row["pct"]` with `%.1f`. If `pct`
     is a string, that is a TypeError. `int(row.get("strk") or 0)` raises on a non-numeric value.
     - The sentinel builds its row with `printf '%s'` per field (`compressor-sentinel.sh:2115`). An empty variable
       therefore yields invalid JSON.
  3. `keeps_target` does `float(rec.close.get("placed_at") or 0)`, which raises on a non-numeric value.
- **Required changes:**
  - Resolve `env=None` to `os.environ`.
  - Wrap `HardStop.check`, `deadline_of`/`overdue` and `keeps_target` so that any exception gives `unknown` /
    not overdue / not kept, plus one event.
  - Register the thermal notify token once and cancel it at exit, with `argtypes`/`restype` set.
  - Tests: a torn last line, `"pct":` blank, `"pct":"61"`, a stale `ts`, sysctl raising, and `close.placed_at =
    "x"`. Each asserts that `run_pass` completes and that the stop reads `unknown`.

**F-C (MED-HIGH, breaks existing tests). The `next_action` prefix.**
- `next_action(rec)` has no `now` (`report.py:153`). So "overdue since HH:MM: " can only read the wall clock.
- Test records sit at `T0 = 1790000000` (`test_report.py:15`), weeks in the past, so all of them would be overdue.
- M, `python3 -I /tmp/b3rev/prefix_probe.py control` => `run=57 failures=0`. The same with `patched`, which applies
  the design's prefix rule => `failures=5`:
  - `test_a_reboot_parked_record_names_boot_resume`
  - `test_all_thin_wait_says_why`
  - `test_close_residue_names_each_member`
  - `test_held_team_wording_names_the_wake_and_its_page`
  - `test_write_cohort_keeps_cohort_loadable`
- It also makes report text depend on the clock.
- **Required change:** `next_action(rec, now: Optional[float] = None)` with no prefix when `now` is None, passed
  explicitly only by the DEADLINE page. Alternatively, put the overdue note in its own field.

**F-D (MED, inflates `P_max`). DEADLINE pages are per record and synchronous.**
- Each page runs in-pass:
  - cc-notify, bounded at 10 s;
  - then `lr-page.sh`, bounded at 45 s (`report.py:31-37`, `:591-602`, `_emit` `:681-691`).
- Members detected in one pass share `timeline.detected` (`census.py:440`), so they share `deadline + W_hard`. N
  members therefore page in the **same pass**.
- E: worst case N × 55 s added to that pass and every later hourly refire, against the `P_max` target of 3 min
  (REPORT §5).
- **Required changes:**
  - One DEADLINE page per cohort that names its overdue members, coalesced the way `unrecoverable_page` is
    (`report.py:950-983`), and refired hourly per cohort.
  - A test with a sink that sleeps and 20 members crossing `W_hard` in one pass asserts ≤1 sink call.

**F-E (MED, double pages and an hourly page that never stops). Suppressing by *current state* is wrong.**
- **Double pages.** A precheck HOLD-COMPOSER or HOLD-DRAFT goes back to DETECTED at reprobe
  (`settle.py:432-444`) and then to PLANNED. Neither state is in `MAX_AGE_S`.
  - M, `verify.py` => `BACKOFF/DETECTED/PLANNED/WAIT_RESET in MAX_AGE_S: False`.
  - So one record can fire both a MAX-AGE page (keyed on `hold_since`, `settle.py:341-356`) and a DEADLINE page. That
    contradicts "no record pages twice".
- **Pages that never stop.**
  - `census.reboot_park` parks **any** open record planned or detected before boot, limited ones included
    (`census.py:858-862`). PARKED-REBOOT is not in `MAX_AGE_S`, and `may_actuate` refuses it forever
    (`act.py:460-461`). So the design's DEADLINE page would fire hourly for as long as boot-resume owns the record.
    §1.4 found parked records open for ~20 days.
  - A `wake_failed` record has already paged WAKE-FAILED (`report.py:931-932`) and would page DEADLINE hourly too.
- **Required changes:**
  - Suppress DEADLINE when the cohort latch has any `age:<record_id>:*` key or `close.hold_since` is non-empty.
  - Exclude PARKED-REBOOT, `wake_failed`, `plan_only` and `cohort_exit` stays.
  - P2 must use a HOLD that cycles through reprobe → PLANNED, not a static HOLD-DRAFT.

**F-F (MED). The kept target triggers on *any* TRANSIENT, which is wider than "rail junk".**
- The TRANSIENT allowlist includes target-side causes (`classify.py:79-92`):
  - `\b429\b`;
  - `router rc 5`;
  - `no claude process appeared within`.
- `_score` keeps no cause, so these cannot be told apart afterwards.
  - M, `verify.py`: a 429 text => `last_error: TRANSIENT 'TRANSIENT'`, `target kept: next4`.
- With F-A's burst, a 429 from the target retries onto that same target for up to `KEEP_TARGET_S` = 1800 s. That is
  a feedback loop.
- H: today's `--place` often re-picks the same account too, but B3 removes the chance that it does not.
- **Required changes:**
  - Store `close.transient_raw`: the precheck reason, or the name of the pattern that matched.
  - Keep the target only for rail causes: `_TERMINAL_TRANSIENT`, `unreadable*`, kitty/rpc timeout, `resolved to no
    tty`, swallowed enter, and our own kill rc 124/137/143.
  - Test: overdue BACKOFF after a 429 ⇒ `--place` is called. Mutation: keep on any TRANSIENT ⇒ red.

**F-G (MED, a policy gate is skipped without saying so). The kept target skips more than KMAX.**
- `--place` also enforces:
  - the per-pick survival floors `recovery-5h-thin` and `recovery-weekly-thin` (`floors_ok`,
    `bin/claude-accounts:6619-6635`, applied per pick at `:6666`). Decision 3, "always waits", is cited at
    `report.py:82`.
  - `store-holds-sid` (`bin/claude-accounts:6637-6659`).
- §3.1 row 25 classes placement answers, including "router policy", as HARD and "untouched". The §0 claim of "no
  operator ruling" relies on that.
- `F.blocking` sees only death facts (`facts.py:334-373`). It cannot see a target that has gone thin since its
  placement.
- **Required change (either):**
  - bound `KEEP_TARGET_S` by the usage-cache freshness (minutes, not 30 min) and state the decision-3 residual; or
  - re-check the floors for the kept account. Either way, list row 25 as *partly bypassed* and put it to the
    operator.

**F-H (LOW-MED). The kill switch and shadow mode do not cover every override.**
- §5.6 gates only `_admit` and `_wakes` on `ctx.deadline`. `keeps_target` (it takes `overdue` as a parameter) and the
  earliest-deadline-first sort are not stated as gated.
- Yet S1 says "off: today's gates exactly".
- **Required changes:**
  - Pass `overdue = ctx.deadline == "on" and admit.overdue(...)` to `keeps_target`, and gate the sort key.
  - Extend S1/S2 to the K1 and W1 scenarios.

**F-I (LOW). The hysteresis is unspecified for unknown readings and for two of the trip sources.**
- After a trip, if the sentinel goes stale (`row is None`), the release rule ("`pct ≤ 50`") cannot be evaluated.
  The bypass then either sticks off until restart or releases on no evidence. The latter is the "Release ≠ !trip"
  failure (`.claude/rules/agent-operating-lessons-situational.md:6`).
- Pressure-4 and thermal trips have no release rule at all.
- **Required changes:**
  - Write a release rule per source.
  - Tripped-then-unknown holds for a stated bound, then releases to `unknown` with an event.
  - Add test H11b.

**F-J (LOW). The red-proof recipe makes C1/C2 green on the pre-fix tree.**
- §9 puts C1/C2 in Commit 1, together with their fix.
- §7's `PRE` is "the commit before the B3 implementation commit", which is Commit 3, so it already contains Commit 1.
- **Required change:** `PRE` = the parent of Commit 1.

**F-K (LOW). `admit:deadline` is invisible in the logs §9 says to read.**
- The `spawn` event detail is `"%s pid=%d nonce=%s"` (`act.py:340-349`), and the launch row carries no admission
  reason (`__main__.py:1319-1324`).
- **Required change:** emit a `deadline-admit` event with `lane_used`, the stop state and the target account, or add
  the reason to the launch row.

**F-L (LOW). State hygiene.**
- `deadline_why` is sticky across calls; reset it at `decide()` entry.
- `Admission.__init__` must default `self.hard`, because tests build `Admission` directly (`test_admit.py`,
  `test_restore_budget_bound.py`).
- `leave_active()` must clear `drip_pages`.
- `hold_raw` set in `note_watcher_hold`/`note_unconfirm` is dead for `keeps_target`, because `_unconfirmed` clears
  `last_error` (`settle.py:326-331`). Drop it or say so.

### R.3 Out of scope, reported only

- **A pre-existing gap behind §3.2.**
  - `map_notmoved` returns DETERMINISTIC for `bg-work:ship-land`, `bg-work:other` and `mid-turn` (M, `verify.py`).
  - Those are exactly the reasons the precheck emits: `HELD:mid-turn` (`handoff-fire.sh:3284`) and
    `HELD:bg-work:ship-land`/`:other` (`:3293`, `:3300`).
  - The actuator refuses them as hard holds, but the reconciler scores them DETERMINISTIC, which escalates on a repeat.
  - B3 does not make this worse (rearm is time-bounded, `classify.py:22-26`), but it needs its own item.
- **§13's side finding happened again after this design was written.**
  - Live `recon.on` mtime is `Oct 20 13:09:17 2026` CDT (18:09:17Z). Live `locks/swap-slots/slot-1` holds pid
    25138, lstart `Tue Oct 20 18:08:03 2026`, and that pid is dead. M: `stat -f '%Sm'`, `cat slot-1/pid`,
    `ps -p 25138` printed nothing.
  - Neither was this review: my first script is stamped 13:19:20 CDT and used `/tmp` roots.
  - Someone is still running `lr_recon` tests with the real HOME.
- **§1.4 omits a later restart.** The running daemon is pid 5233, started 16:04:56Z (`restarts.jsonl` tail), not
  the 07:23Z one. `band.log` shows it at `pri=31` (M).

