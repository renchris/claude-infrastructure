# B7: audit of the pass-scoped `now` in lr_recon. Implementation design

Item B7 of `REPORT.md` §4(b). Read-only research, 2026-10-20 ~17:40-18:20Z. Code cited at worktree
HEAD `28b25a119`. `git diff --stat 28b25a119 6fdf87eca -- scripts/limit-recover/` is empty, so the
lines are the same on `main`. **Measured** means a named command was run, and **estimated** means
the method is named. **Hypothesis** means not verified.

**Verdict: BUILD.** Conviction 80%. An agent can implement, test and land this end to end. The only
operator step comes after landing: reload the reconciler at a quiet point so the new code loads,
the same step every lr_recon wave has needed (§9).

---

## 0. Summary

- **What `now` is.** `_run_pass` takes `now = time.time()` once (`__main__.py:1665`). That value is
  the census instant: `observe.observe(now=now)` makes it `snap.wall` (`observe.py:476-479`). It is
  then threaded through every stage of the pass. Stages run in this order: facts, census, derive,
  plan (`--place` takes up to 120 s per lane), dispatch (each admission probe takes up to 30 s),
  report and save.
- **How stale `now` gets.** Each daemon spawn's `events.jsonl` row carries `t = now`, the pass
  start. Measured: `python3 -I /tmp/b7audit/spawn_lag.py events.jsonl.1 events.jsonl` gives 53
  spawn rows. Each spawn's `t` is earlier than rows the same file wrote before it, by p50 ≥173 s,
  p90 ≥699 s and max ≥1,633 s. Those are lower bounds on the in-pass offset at dispatch, and all
  are from before A1 (priority 20).
- **Where things stand since A1.** End-of-pass cadence from `recon/band.log` (07:23Z-17:42Z):
  p50 10 s, p90 13 s, p99 19 s, max 193 s. That window is mostly idle: 0 `place` events and 2
  spawns after 07:23Z. Load1 was 265.6 at 17:42Z, 26.6 per core (`sysctl -n vm.loadavg`). No
  post-A1 cohort exists to show the in-pass offset under load (open question, §12).
- **The audit.** I enumerated every `now` comparison and stamp in the 22 non-test modules (§3).
  Most of them are **intended**: they compare a census-stamped value with the census instant.
  Five defect classes remain:
  - **D1, quiet windows anchored on the wrong census, and read before this census's stamp.** C's
    60 s grace (`__main__.py:1237`), `rolled_back` (`settle.py:259`) and `holder_gone`
    (`settle.py:1011`) measure quiet time from the last census that *saw* the activity. That is an
    upper bound on when the activity stopped, so one long pass reads as that much quiet. The two
    settle checks also run before `_derive` stamps this census's sighting (`:763` and `:813`
    against `:855-856`). They are the REPORT's "settle.py:253,965" and "__main__.py:1204". The
    REPORT's hypothesis that they are intentional is half right: comparing census with census is
    intended, but the anchor and the ordering are defects.
  - **D2, our own actions stamped at pass start.** These are `act.spawn`'s `intent.at`, the
    record's `updated_at` and the spawn event `t` (`act.py:320,321,337,345`), plus the launch.log
    row (`__main__.py:1323`). The effect is on forensics and telemetry, not behaviour.
  - **D3, the per-account pacer is still pass-scoped.** The pace and the drip moved to the wall
    clock in wave 1. The pacer's slots (`admit.py:187-198`, used at `:207-209` and `:308,330-332`)
    did not, so they never free inside a pass. That caps first turns at 3 per account per pass.
  - **D4, `updated_at` used as an age anchor.** `save_records` rewrites `updated_at` to `now` every
    pass (`store.py:165`). The IN-FLIGHT fallback (`__main__.py:881`, `:1585`) therefore measures
    one pass gap and never expires a record with no confirm stamp. The same pattern is latent in
    three report fallbacks (`report.py:196,224,996`).
  - **D3b (the C2 mixed-clock gap) is not a defect.** `act.may_actuate`'s `now < next_eligible_at`
    (`act.py:471`) must stay on the census instant. `next_eligible_at` also carries evidence waits
    (R_PROOF_S, `settle.py:203-204`), and reading the wall clock there would re-fire R on a census
    taken before its own proof window.
- **Fix.** Use two clocks with stated roles: the census instant `now` for observations, and
  `t_dec = max(now, wall())` for actions and rate gates. Add a first-unseen quiet anchor that is
  stamped before any reader, and a stable IN-FLIGHT anchor. A per-pass file kill switch
  (`recon/pass-clock`) is included.
- **Prototype, measured, all in `/tmp` copies of the tree.**
  - Base arm (HEAD plus the new controls): 758 tests ran and exactly the 7 new controls failed.
  - Fixed arm: 758 OK. Fixed arm with the kill switch: 772 OK.
  - Pre-existing suite: 628 tests OK in both arms.
  - Two mutants were each killed by their own control.
  - Measured diff: +95/−29 production lines across 5 files.

---

## 1. The clock model the fix enforces

`now` is the **census instant**. The census, the facts and the evidence were read at about that
moment, and every stamp written from them describes it. The pass then continues for minutes, and
decisions taken late in it act at a later wall time. The rules below are to be written into
`clock.py`'s module docstring:

| # | Rule | Clock |
|---|---|---|
| R1 | An **observation** (what a census saw) is stamped with `now`, and census-stamped values are compared with `now` | census |
| R2 | An **action** we take (spawn, admission, pacer slot, launch.log row) is stamped at the action | `t_dec = max(now, wall())` |
| R3 | A **rate gate** ("no more than one per N s") reads the decision time against the action stamps | `t_dec` |
| R4 | An **evidence wait** ("act only on a census taken ≥ N s after X") compares the census instant, never the wall. A later wall reading cannot make an older census newer | census |
| R5 | A **quiet window** ("X has been absent ≥ N s") is measured from the **first census that did not see X**, which is a lower bound. The last census that saw X is an upper bound and must not anchor it. A census's own sighting is stamped before any reader in the same pass | first-unseen census → `t_dec` |
| R6 | `updated_at` is rewritten every pass, so it is never an age anchor | n/a |
| R7 | A stamp used as **pass identity** stays `now` (`busy_at` at `_invariant`, `Admission.over_at`) | census |

`max(now, wall())` cannot be earlier than the census instant. That property makes tests that drive
`now` forward by hand keep today's semantics. In production `wall() ≥ now` always holds.

---

## 2. Measurements

| Reading | Command | Result |
|---|---|---|
| In-pass offset at spawn (pre-A1) | `python3 -I /tmp/b7audit/spawn_lag.py ~/.reso/limit-recover/recon/events.jsonl.1 ~/.reso/limit-recover/recon/events.jsonl`: for each `spawn` row, the max `t` of the 200 rows before it minus its own `t` | n=53. Lower bound p50 173.2 s, p90 699.2 s, max 1,632.8 s (2026-10-18 11:46:38Z, sid 5759497b B). Incident rows: d7eb73d2 R ≥736 s, 7aae55e1 R ≥699 s, 769b7294 A ≥529 s |
| Spawns since the PRI-31 reload | same script, rows after 1792480000 | 2 (07:23:17Z, e80b61f4 C and 3e929a81 C). No cohort since, so no post-A1 offset under load |
| Pass cadence since A1 | `python3 -I /tmp/b7audit/gaps.py ~/.reso/limit-recover/recon/band.log`: gaps between consecutive end-of-pass rows of one pid (`_band(ctx, time.time())`, `__main__.py:1837`) | n=3,745 (07:23:28Z-17:42:01Z). p50 10.0 s, p90 13.0 s, p99 19.0 s, max 193.0 s (07:36:50Z) |
| Load at the reading | `sysctl -n vm.loadavg` at 17:42:13Z | 265.62 / 251.04 / 206.33, i.e. 26.6/core on 10 cores |
| Live IN-FLIGHT records without a confirm | `python3 -I /tmp/b7audit/scan.py` over `recon/sessions/*.json` | 138 records, 4 open (all PARKED-REBOOT), 0 IN-FLIGHT with `timeline.confirmed` null |

The scratch scripts live in `/tmp/b7audit/` and are not part of the design. Each is a few lines of
`json`/`statistics` over the named file.

---

## 3. Every `now` site in lr_recon, classified

Method: `grep -n -E '\bnow\b' scripts/limit-recover/lr_recon/*.py` gives 437 lines. Removing
signatures, docstrings and pure pass-throughs leaves 316 lines (`/tmp/b7audit/now_lines.txt`). Each
comparison and stamp was then read in context.

Classes:
- **D**: defect, fixed by B7.
- **I-obs**: intended. Census instant against a census stamp, or against a slow external stamp
  such as a reset hours away.
- **I-ev**: intended evidence wait (R4). Must stay on `now`.
- **I-id**: intended pass identity (R7).
- **I-keep**: wrong clock in a direction that is safer. Kept deliberately.
- **N**: not pass-scoped. It reads its own fresh clock or runs outside the pass.
- **M**: minor or display. Fixed only where the change is free.

### 3.1 `__main__.py` (the pass)

| Line | Expression | Class | Note |
|---|---|---|---|
| 1665 | `now = time.time()` | definition | becomes `snap.wall` (`:1667-1673`) |
| 193 → facts.py:179 | `observed_at=now` | I-obs | a fact observed by this census |
| 218 → facts.py:273,290 | `resets_at + 60 < now` | I-obs | resets are hours away |
| 265 → census.py:861,884 | park `since=now` | I-obs | |
| 300, 340 → census.py:511-514, 547-549 | `detected/terminal.at = now` | I-obs | |
| 309, 325 → census.py:126,243,287 | `resets + GRACE < now`, `resets - now < STAY_S`, `resets_at - now < IDLE_MIN_LEFT_S` | I-obs | error ≤ observe time against 15 min to hours |
| 360 → settle.py:342-356 | `_hold` `since=now`, `eta=now+REPROBE_S` | I-obs | re-probe is paced by censuses |
| 372 → census.py:440-441,460 | `timeline.detected = now`, `updated_at = now` | I-obs | `detected` is B3's `t_detect`. `updated_at` is never an anchor after D4 |
| 428, 438 | `now < w.eta + WAKE_AFTER_S + jitter`, `resets_at > now` | I-obs | reset + 120 s |
| **447 → admit.py:205-210** | `pace_wake` pacer slot at `now` | **D3** | wakes share the pacer |
| 476 → census.py:705 | `now - ts < quiet_s` (tombstone ts, 600 s) | I-obs | understates age, so it errs conservative |
| 520, 553 | provenance stamp, band log | N | called with `time.time()` (`:1836-1837`) |
| 644 | focus ledger `t: now` | I-obs | a row about this census |
| 753 → settle.py:903,915-926 | `ok <= (detected or now)`, close stamps | I-obs | |
| **763 → settle.py:1011** | `now - busy_at < HOLDER_GONE_QUIET_S` | **D1** | last-seen anchor, and read before `:856` stamps this census (REPORT's "settle.py:965") |
| 764, 770 → settle.py:1043, 1103-1112, capped.py:108-154 | terminal stamps, `reset + GRACE < now` | I-obs | |
| 784 → classify.py:211 | `now - last_error.at >= REARM_S` | I-obs | census to census, 900 s (REPORT's "classify.py:198") |
| 798, 913, 1525 → classify.py:226 | `next_eligible_at = now` | I-obs | eligible at once |
| 809 → settle.py:171, 201-204, 287-311, classify.py:186-198 | backoff and wait stamps from `now`, `replaced_at = now`, `next_eligible_at = now + R_PROOF_S` | I-ev | the exit is observed by this pass's reap. R_PROOF_S is an evidence wait ("one window per R", `settle.py:203`) |
| 813 → settle.py:254 | `(next_eligible_at or 0) > now` | I-ev | |
| **813 → settle.py:259** | `now - busy_at < HOLDER_GONE_QUIET_S` | **D1** | same two defects (REPORT's "settle.py:253") |
| 818-833 → settle.py:440,497,553,846-850,1122 | `now >= wait.eta`, `now - replaced_at < R_PROOF_S`, stamps | I-obs / I-ev | |
| 853 | `timeline.submitted or now` | I-obs | token seen by this census |
| 855-856 | `busy_at = now` | stamp | moved earlier by D1. Must stay `now` (R7, `:1596`) |
| 862 → settle.py:822 | `now - target_sample.at >= LAUNCHER_CHAIN_MAX_S` | I-obs | `target_sample.at = snap.wall` (`evidence.py:300`) |
| 859-866 | `typer_at = now` | stamp | D1 adds the first-unseen anchor |
| **881** | `now - (confirmed or updated_at or now) >= IN_FLIGHT_MAX_S` | **D4** | `updated_at` is the previous pass start, so the age is one pass gap |
| 889, 952-958 | failure stamps, `sentinel_until = now + 300`, `now >= sentinel_until` | I-obs | |
| 1001 → plan.py:237,241,253,269 | `eta <= now`, `now >= eta + REOFFER_AFTER_S`, `eta - now >= EPS_STAY_S` | I-obs | |
| 1004 → plan.py:137-162, working.py:88,128,151,171,188,222 | kwork at the census instant ("records after `now` are ignored", `working.py:15`) | I-obs | |
| 1040 → plan.py:384-386 | `_fresh(stamp, now, 120)` against the stamp mtime | I-obs | understates age (conservative) |
| 1046 → plan.py:431,438,458 | stay `eta=now`, `planned=now`, `since=now` | I-obs | |
| 1046 → plan.py:440 | `eta = now + p.eta_s` | M | backdated by the placer's own run (≤120 s per lane). It only feeds `max_age_deadline` (eta + 600) and the readout, because `movers()` re-places a WAIT_SLOT every pass whatever its eta (`plan.py:255-267`). Not fixed |
| 1053 → plan.py:568 | plan `at` | display | |
| 1078 → store.py:403,362,575-576 | claim orphan age `now - dir mtime`, holder `ts`, `intent.at` | **I-keep** | pass `now` understates the dir's age, so the 10 s orphan grace (`store.py:308-310`) is effectively 10 s plus the in-pass offset. Moving it to wall would shrink the grace for a slow bash taker under load |
| 1119 → admit.py:147 | `entered_at` | record only | |
| 1161 → admit.py:302-303 | `over_at[cohort] != now` | **I-id** | the restore-budget run counts passes (`admit.py:15-16, 298-299`) |
| 1161 → admit.py:306, 318-325 | pace and drip | N | `self.wall()` since wave 1 (`19e405543`) |
| **1161 → admit.py:308, 330-332** | `pacer_ok/pacer_take(…, now)`, `last_admit_at = now` | **D3** | |
| 1192 | carried-jobs file name `int(now)` | M | cosmetic |
| 1225 | sort key `detected or now` | I | |
| **1236-1237** | `now - typer_at < C_GRACE_S` | **D1** | last-seen anchor (REPORT's "__main__.py:1204"). The busy-vs-typer half was fixed in `58885750c` |
| 1244 → act.py:471 | `now < next_eligible_at` | **I-ev** | must stay on `now` (R4). `next_eligible_at` carries R_PROOF_S |
| 1250 → act.py:522 → store.py:403 | claim orphan age | I-keep | as at 1078 |
| 1284 | `admit_refused_at = now` | M | shown as "since HH:MM" (`report.py:182`). Moved to `t_dec` because it is free |
| **1304-1311 → act.py:320,321,337,345** | `intent.at`, `updated_at`, spawn event `t` = `now` | **D2** | |
| **1323** | launch.log `spawn` row `t` = `now` | **D2** | the double-typer audit keeps a record's rows whatever their `t` (`report.py:310-314`) |
| 1354 | `next_eligible_at = time.time() + WAIT_RETRY_S` | N | wall, compared next pass with the census instant: conservative |
| 1405, 1443-1468 | cohort `opened_at`, readout and cohort status | display | |
| **1585** | `_invariant`: `now - (confirmed or updated_at or 0) < IN_FLIGHT_MAX_S` | **D4** | |
| 1596 | `_invariant`: `now - busy_at < ACTIVE_FAST_S` | **I-id** | "this pass's derive saw…" (`:1597-1599`). Requires `busy_at == now` |
| 1728 → store.py:156-172 | `save_records` `updated_at = now`, refresh `0 <= t - last < 60` | I | pass to pass |
| 1795-1800 | restart window | N | `time.time()` |

### 3.2 Other modules

| Site | Class | Note |
|---|---|---|
| admit.py:187-198 `_expire/pacer_ok/pacer_take(now)` | **D3** (root) | the caller's clock. Callers listed above |
| admit.py:373 `BootSlots._slot_live` | N | `time.time()` |
| act.py:427 `reap_actlogs` | N, dead | `grep -rn reap_actlogs scripts bin tests` finds only its `def` |
| report.py:196, 224, 996 `since = w.since if w else rec.updated_at` | **D4b**, latent | today the only PRE-MOVE substate set without a wait is HOLD-MENU (`__main__.py:870-871`), whose max age is `None` ("at once"), so no numeric max age is reachable. Fixed so it cannot become a never-firing page |
| report.py:621-623 `Reporter.now = time.time` (latches and pages `:650-1021`) | N | `max_age_due` with a fresh wall against census stamps pages early by at most the in-pass offset. Acceptable |
| report.py:246-261 `cohort_status` age | display | `wait.since or detected or updated_at` |
| evidence.py:235, 285, 300 | I-obs | `snap.wall` on both sides |
| transcript.py:462, 503 | N | `observe_transcript` is called without `now` (`transcript.py:537`), so it reads `time.time()` at the read (`:512`) |
| capped.py:64-82 `now - at > USAGE_MAX_AGE_S (900)` | I-obs | lenient by seconds against a 900 s bound |
| facts.py, census.py, working.py, plan.py (other) | I-obs | above |
| store.py:130, 197, 436, 501, 681-698 | N / stamp | `time.time()` defaults |
| clock.py:118-154 (`tick`, `wake_guard_ok`), heartbeat | N | own clocks |
| fence.py:213 | N | a CLI predicate, not in the pass |
| drain.py:141-186, band.py | N | one-shot CLI, and a log line |

The REPORT's three named instances are settled. The brake floor and the drip (`admit.py`) were fixed
in wave 1, and C's busy-vs-typer half was fixed in `58885750c`. B7's remaining defects are D1-D4.

---

## 4. The defects in detail

### D1. Quiet windows: the anchor, and the ordering (medium)

- **Mechanism, anchor.** `typer_at` and `busy_at` are the time of the last census that saw the
  activity live. The check `now - stamp >= 60` therefore tests the time since that sighting, which
  is an upper bound on how long the activity has really been quiet. With censuses `P` seconds apart
  and `P ≥ 60`, a single census that does not see the activity satisfies the window. The activity
  may have stopped one second before that census.
- **Mechanism, ordering.** `holder_gone` (`:763`) and `rolled_back` (`:813`) run before
  `rec.close["busy_at"] = now` (`:855-856`) in the same loop iteration. They read the previous
  pass's stamp, so a launcher or watcher that this very census sees is invisible to them:
  - for `holder_gone`, whenever the record was never busy before (`busy_at` absent);
  - for `rolled_back`, once the last sighting is 60 s or more old.
- **Harm under the premise.**
  - **C.** C types a second copy of the owed prompt while the launcher's user record may still be
    landing. Records land 1.6-11 s after Enter, with re-sends up to 45 s (`__main__.py:1238-1241`).
    This needs a typed launcher path ending UNVERIFIED or INDETERMINATE, plus a pass gap of 60 s or
    more.
  - **rolled_back.** It scores a counted retry while a watcher or launcher of the move is live.
  - **holder_gone.** It closes `NOT_NEEDED (dead-before-claim)` while another lane's launcher is
    booting the session (launcher live, no holder yet).
  - **Frequency: estimated low.** Since `a8ebaa7c0` the normal path passes the prompt on argv.
    Post-A1 pass gaps of 60 s or more are expected only during cohorts (hypothesis, §12).
- **Evidence.** Controls C4, C5 and C6 (§8) are red against HEAD (measured).
- **Fix (R5).**
  - Stamp each census's view of the activity once, at the top of the per-record loop, before
    any reader.
  - Keep two stamps per activity: `<key>_at`, the last census that saw it (unchanged meaning), and
    `<key>_quiet_at`, the first census that did not (`None` while it is seen).
  - A quiet window is `t - <key>_quiet_at`. `t` is `t_dec` for C, decided in `_dispatch`, and `now`
    for the two settle checks, decided in `_derive` a moment after the census.
  - For C, using `t_dec` lets C go out in the same pass once 60 s of wall time have passed since
    the first census that did not see the typer. Control E1 is the liveness guard for this.

### D2. Our actions stamped at pass start (low; forensics)

- **What is wrong.** Spawn rows, `intent.at` and the launch.log row all carry the pass start. The
  REPORT itself had to read a spawn row as "the pass starting 05:00:49Z" (§2.1 row 3d1d988a).
  Measured backdating is p50 ≥173 s pre-A1 (§2).
- **Fix (R2).** In `act.spawn`, `t = max(now, time.time())`. In `_dispatch`, the launch.log row
  uses `max(now, ctx.wall())`.

### D3. The pacer is pass-scoped (low-medium)

- **What is wrong.**
  - Inside one pass a slot taken at `now` never reaches its 20 s release (`now - at = 0`), so
    first turns are capped at 3 per target account per pass.
  - Across passes the slot frees early: it is stamped up to the in-pass offset before the real
    submit.
  - This is the same class wave 1 removed from the pace and the drip (REPORT G3, "pacing is in
    wall-clock seconds").
- **Fix (R2/R3).** `t_dec = max(now, self.wall())` for `pacer_ok`, `pacer_take` and
  `last_admit_at` in `decide`, and in `pace_wake`.
- **Bounds that remain.** The token bucket (1 per 20 s, burst 6), BootSlots (6) and the 3-per-20 s
  per-account bound itself, now measured in real seconds.

### D4. `updated_at` as an age anchor (low; latent, can strand)

- **What is wrong.**
  - IN-FLIGHT is entered either by `settle_exit` (A rc 0, `settle.py:198`) or by `mark_in_flight`
    (`settle.py:581`).
  - With no readable tombstone, `timeline.confirmed` stays `None`, and the age is
    `now - updated_at`, which is one pass gap.
  - At a 5 s cadence it never reaches 600 s. `_invariant` skips the record for the same reason, so
    it sits IN-FLIGHT silently, breaking REPORT G5.
  - It fires only when one single pass gap is 600 s or more.
- **Evidence.** Control C7 is red against HEAD: no expiry in 995 s of 5 s passes (measured). Zero
  live instances today (§2).
- **Fix (R6).**
  - Add `close["in_flight_at"]`. `setdefault` it to `now` while the record is PRE-MOVE/IN-FLIGHT,
    and pop it otherwise.
  - The age is `confirmed or in_flight_at`.
  - `report.py:196, 224, 996` fall back to `timeline.detected` before `updated_at`.

---

## 5. The change (files, functions, diff sketch)

All of this was prototyped and measured in `/tmp/b7ks.4gR4aC`, with the full diff at
`/tmp/b7audit/fix_ks.diff`: +95/−29 lines across 5 files (`diff -ru` base vs fixed, `-x tests`).

**`scripts/limit-recover/lr_recon/__main__.py`**

- `Ctx` (`:93-126`) gains the following.
  ```python
  pass_clock = "wall"   # B7 kill switch, re-read every pass
  def wall(self) -> float:
      """The instant a decision or an action is taken (``now`` is the census instant).
      Under the kill switch it reads -inf, so every max(now, wall) is the pass ``now`` again."""
      return time.time() if self.pass_clock != "pass" else float("-inf")
  ```
  Also add a module-level `read_pass_clock(paths)`: `recon/pass-clock` reading `pass` gives `"pass"`,
  anything else gives `"wall"`.
- `_run_pass` (`:1664-1665`), before `now = time.time()`:
  `ctx.pass_clock = read_pass_clock(paths)` and
  `ctx.admission.pacer_on_wall = ctx.pass_clock != "pass"`.
- `_derive`:
  - Right after `act.adopt(rec, snap)` (`:748`), stamp this census's busy sighting (R5 ordering):
    ```python
    settle.note_seen(rec, "busy",
        bool(act.live_procs(rec, snap))
        or evidence._argv_live(snap, rec.sid, "handoff-fire", "__recycle")
        or evidence._argv_live(snap, rec.sid, "lr-fire-resume"),
        now, first_unseen=ctx.pass_clock != "pass")
    ```
    These are the predicates evidence.build uses (`evidence.py:206,208`). Delete the old stamp at
    `:855-856`.
  - Replace `:859-866` with `settle.note_seen(rec, "typer", <same predicate as today>, now,
    first_unseen=…)` followed by `rec.close.setdefault("typer_at", 0.0)`.
  - Before the IN-FLIGHT check (`:876`):
    ```python
    if rec.phase == "PRE-MOVE" and rec.substate == "IN-FLIGHT":
        rec.close.setdefault("in_flight_at", now)
    else:
        rec.close.pop("in_flight_at", None)
    ```
    Then replace `rec.updated_at or now` with `rec.close["in_flight_at"]` at `:881`.
- `_dispatch` (`:1218-1327`):
  - Add `t_dec = max(now, ctx.wall())` after `step()`.
  - The C grace becomes `if which == "C" and settle.quiet_for(rec, "typer", t_dec) < C_GRACE_S:
    continue`.
  - `admit_refused_at = t_dec`.
  - The launch.log row uses `max(now, ctx.wall())`.
  - **Unchanged on purpose:** `act.may_actuate(…, now, …)` (R4) and `act.hold_claim(…, now)`
    (I-keep).
- `_invariant` (`:1585`): `(now or time.time()) - (r.timeline.confirmed or r.close.get("in_flight_at")
  or (now or time.time())) < IN_FLIGHT_MAX_S`. `:1596` is unchanged (R7).

**`settle.py`.** Add the following before `HOLDER_GONE_QUIET_S` (`:986`).

```python
def note_seen(rec, key, seen, now, first_unseen=True):
    at, quiet = key + "_at", key + "_quiet_at"
    if seen:
        rec.close[at] = now; rec.close[quiet] = None
    elif quiet not in rec.close:                 # an older daemon's record: keep its old reading
        rec.close[quiet] = float(rec.close.get(at) or 0.0)
    elif rec.close[quiet] is None:               # seen by the previous census, not by this one
        rec.close[quiet] = now if first_unseen else float(rec.close.get(at) or 0.0)

def quiet_for(rec, key, t):                      # -1.0: this pass's census saw it
    quiet = key + "_quiet_at"
    if quiet not in rec.close:                   # never stamped (unit tests): old last-seen gap
        last = rec.close.get(key + "_at")
        if last is None and key == "typer":
            last = rec.close.get("busy_at")      # the C grace's reading before 58885750c
        return t - float(last or 0.0)
    q = rec.close[quiet]
    return -1.0 if q is None else t - float(q)
```

`rolled_back` (`:259`) and `holder_gone` (`:1011`) then use `quiet_for(rec, "busy", now) <
HOLDER_GONE_QUIET_S`.

Migration subtlety (measured): a key that is absent is seeded from the old last-seen value. My first
draft seeded it with `now`. That reddened `test_rollback.test_a_stranded_rollback_is_re_driven…`,
whose record carries a 30-min-old `busy_at`, because the new code then made it wait 60 s more and
paged RECON-DEFECT. Seeding from `<key>_at` keeps the first pass after the upgrade identical to
today. The `busy_at` fallback for `typer` must apply only in `quiet_for`, never in the seeding,
because the new top-of-loop busy stamp would contaminate a fresh record. A second draft did that
and reddened three `test_unprompted_c` tests (measured).

**`admit.py`.**
- `Admission.__init__`: `self.pacer_on_wall = True`.
- `decide` (`:308, 330-332`): `t_dec = max(now, self.wall()) if self.pacer_on_wall else now`, then
  `pacer_ok(acct, t_dec, sid)`, `pacer_take(sid, acct, t_dec)` and `last_admit_at = t_dec`.
- `pace_wake` (`:205-210`): the same `t`.
- `over_at` (`:302-303`) is unchanged (R7).
- Update the module docstring (`:13-16`): the pacer now reads the wall as well.

**`act.py`.** In `spawn` (`:306-351`), `t = max(now, time.time())` is used for `intent.at`, both
`save_record` calls and the event `t`. Read `time.time` at call time, not as a default argument, so
a test that patches it is honoured.

**`report.py`.** At `:196, 224, 996`: `since = w.since if w else (rec.timeline.detected or
rec.updated_at)`.

**`clock.py`.** Add the R1-R7 table to the module docstring. No code change.

---

## 6. Data and format changes

| Where | Change | Compatibility |
|---|---|---|
| `recon/sessions/<sid>.json` `close` | new keys `busy_quiet_at`, `typer_quiet_at` (float, or JSON null for "seen by the last census") and `in_flight_at` (float) | older code ignores unknown `close` keys (`Dict[str, Any]`). Save and load round-trip, null included, measured: `note_seen` → `store.save_record` → `store.load_all` gives `{'typer_quiet_at': None, 'busy_quiet_at': 0.0, 'in_flight_at': 90.0}` |
| `recon/events.jsonl` `spawn` rows | `t` is the spawn's own wall time, no longer the pass start | readers are human and forensic only (`grep -rn '"spawn"' lr_recon bin/cc-lr` finds no program reader) |
| `recon/launch.log` spawn rows | field 1 is the spawn's wall time | `report._typers` keeps a record's rows whatever their time (`report.py:310-314`) |
| `recon/pass-clock` (new, optional) | contains `pass` to turn B7's decision-time readings off, read every pass | absent means `wall` |

There is no schema version bump. Rolling back the code (`git revert`) leaves harmless extra keys on
disk.

---

## 7. Failure modes under permanent 15-40/core

| Failure | Handling |
|---|---|
| Passes run minutes long. Every census is older at decision time | That is the premise B7 is built for. Census-to-census checks stay on `now` (R1, R4). Actions and rate gates read `t_dec`. Quiet windows have a true lower bound (R5) |
| **D1 costs latency.** A quiet window can now need one more pass when the first census not seeing X is the current one and the decision is in `_derive` | Bounded by one pass. This is within the REPORT §5 G term `B_max + P_max`. For C (decided in `_dispatch`) there is no added pass when the in-pass offset is ≥ 60 s, because `t_dec` has advanced. Control E1 guards this, and a mutant is killed (§8) |
| The pacer admits more than 3 first turns per account inside one long pass | Intended: 3 per 20 s of real time. Still bounded by the token bucket (burst 6, 1 per 20 s) and BootSlots (6) |
| A wall-clock step backwards (NTP) | `max(now, wall())` never reads earlier than the census |
| A lid or system sleep between census and dispatch: `t_dec` jumps, and C's grace could count sleep time | C is not in `act.IRREVERSIBLE` (`act.py:32`), so the wake guard does not cover it. But `Caffeinate` holds idle and system sleep while any record is moving, including RELAUNCHED (`__main__.py:58, 1840-1845`). And the claim is re-read at decision time (`hold_claim` before every claimed actuator, C included), so a driver started after the census is caught there. Residual: a lid close on battery, which does not apply to a desktop. Not changed |
| A daemon restart mid-cohort | The new keys persist in `rec.close`. After a restart the first unseen census anchors a fresh `quiet_at = now`, which costs one more 60 s at most. That errs safe and is restart-neutral (REPORT G6) |
| An unplanned restart loads the new code mid-cohort (deploy-driven restarts, REPORT §3.4) | State-compatible. The first pass seeds absent keys from the old last-seen values, so behaviour equals today's until the next sighting |
| The IN-FLIGHT expiry now fires for unconfirmed records | It takes the existing path for confirmed records: DETERMINISTIC, then ESCALATED, a re-arm after 15 min, then IMPOSSIBLE and a page after `REARM_CAP` (`test_main.py:1066-1082`). This replaces silent stranding |
| The claim's orphan grace | Kept on `now` on purpose (I-keep). Separately, a 10 s grace (`LR_CLAIM_ORPHAN_GRACE_S`, `store.py:308-310`) for a bash taker's mkdir-to-stamp under load is unmeasured. That belongs to A6, not B7 |
| The kill switch file is unreadable | It reads as `wall`, the default. No crash path: `OSError` is caught |

No B7 change reads the load average or adds a wait. A timeout is still only "unknown, retry".

---

## 8. Test plan

### 8.1 Measured in /tmp (no repo writes)

| Arm | Command (from `<arm>/scripts/limit-recover`, `TMPDIR=/tmp/b7audit/tmpdir PYTHONDONTWRITEBYTECODE=1`) | Result |
|---|---|---|
| HEAD, unmodified (`git archive HEAD scripts tests bin launchd hooks lib`) | `python3 -m unittest discover -s lr_recon/tests -t .` | **Ran 628, OK** |
| HEAD plus the 7 controls and E1 | same | **Ran 758, FAILED (failures=7)**: exactly C1-C7 |
| fixed (D1-D4) plus controls | same | **Ran 758, OK** |
| fixed, claims kept on `now`, kill switch, plus E4 | same | **Ran 772, OK** |
| mutant M1: the C grace reads `now`, not `t_dec` | `python3 -m unittest lr_recon.tests.test_b7_proto2 lr_recon.tests.test_b7_proto` | **E1 FAILS** (killed) |
| mutant M2: the quiet anchor reverts to last-seen (`quiet = at`) | same | **C4 FAILS** (killed) |

The prototype tests subclassed existing TestCases for speed, so the inherited tests re-ran. That
accounts for 758 against 628 + 8. The final tests must not do this (§8.3).

### 8.2 The controls (red before, green after, all measured)

- **C1** `test_admit.Pacer.test_a_slot_frees_on_wall_time_inside_one_pass`.
  - Setup: 3 admissions to `acct1` at wall 100, the same pass `now`, then wall advanced 21 s.
  - Expect: the 4th is admitted.
  - Before: `(False, 'pacer:acct1')`.
- **C2** `test_long_pass.LongDispatch.test_a_long_dispatch_stamps_spawns_at_their_own_time`.
  - Setup: 4 PLANNED limited records, one target account, and a probe stub that advances the wall
    30 s per call.
  - Expect:
    - each `spawn` row has `t ≥` the wall at its spawn. Before, the rows read 1800000000.0 for
      spawns at +30, +60 and +90 s;
    - all 4 dispatched. Before, 3, with the 4th `pacer:next`.
- **C3** `test_long_pass.WholeLongPass.test_a_whole_long_pass_stamps_its_spawn_at_the_spawn`. This
  is **the test that runs a long pass.**
  - Setup: `run_pass` in act mode on a `cc-lr` request, with `time.time` patched by the `LongPass`
    helper. The placer stub advances 120 s and the probe stub 30 s.
  - Expect: the pass really was long (≥150 s at spawn), and the spawn row `t ≥` the wall at spawn.
  - Before: `1800000000.0 not ≥ 1800000150.0`.
- **C4** `test_unprompted_c…test_C_waits_60s_after_the_first_census_that_did_not_see_the_typer`.
  - Setup: pass 1 with the typer live (no verdict). Pass 2 is a census 300 s later in which the
    launcher has written `UNVERIFIED:submit`.
  - Expect: no C in pass 2 at a decision 1 s after the census.
  - Before: `['C']`.
- **C5** `test_rollback…test_a_launcher_seen_by_this_census_holds_the_rollback_retry`.
  - Setup: the db755a94 rolled-back shape with `busy_at` 1,800 s old, and a live
    `lr-fire-resume … <sid>` in this census.
  - Expect: no `rolled-back` event and `attempt` still 1.
  - Before: the event fired.
- **C6** `test_holder_gone…test_a_launcher_booting_the_sid_in_this_census_keeps_the_record_open`.
  - Setup: a never-began record, no holder, another lane's launcher live.
  - Expect: still open.
  - Before: `NOT_NEEDED dead-before-claim`.
- **C7** `test_main…test_in_flight_without_a_confirm_stamp_still_expires`.
  - Setup: PRE-MOVE/IN-FLIGHT with `confirmed=None`, passes every 5 s, and `save_records`
    restamping `updated_at`.
  - Expect: the failure fires by 610 s.
  - Before: nothing within 995 s.

### 8.3 Equivalence guards (green in both arms; each names the mutant it kills)

- **E1** `test_C_goes_out_in_the_same_pass_once_60s_of_wall_passed` (measured green in both arms).
  It kills M1, an over-conservative fix that reads `now`.
- **E2** `test_dispatch_hands_may_actuate_the_census_instant` (designed, not prototyped).
  - Mock `act.may_actuate` and run `_dispatch` while the wall advances.
  - Assert it was called with `now`.
  - It kills a well-meant "fix" that passes `t_dec`, which would re-fire R on a census taken
    before its R_PROOF_S window (`settle.py:203-204`).
- **E3** `test_claims_keep_the_census_instant` (designed). Assert `hold_claim` received `now`. It
  kills a mutant that shrinks the orphan grace.
- **E4** `test_pass_clock_pass_restores_the_last_seen_grace` (measured green in the kill-switch
  arm). With `recon/pass-clock` = `pass`, C4's scenario sends C in pass 2, as today. This proves the
  switch.
- The existing 628 tests stay green. They pin the pre-existing semantics: the C chain bound
  (`test_unprompted_c`), the 3-per-account pacer at a fixed wall (`test_main…30_record_cohort`),
  `_invariant`'s pass identity (`test_main:1036-1051`), and rollback re-drive (`test_rollback`).

### 8.4 Where the tests go

- `lr_recon/tests/longpass.py` (new): the `LongPass` clock. It is a callable with `.advance(s)`,
  patched over `time.time` for the duration of a pass, and slow stubs advance it. B1 can reuse it.
- Place each control in its home suite, not a subclass:
  - C1 in `test_admit.py`;
  - C4, E1 and E4 in `test_unprompted_c.py` (same class);
  - C5 in `test_rollback.py`;
  - C6 in `test_holder_gone.py`;
  - C7, E2 and E3 in `test_main.py`;
  - C2 and C3 in a new `test_long_pass.py`.
- The land gate does not run the lr_recon Python suite wholesale (`grep -rn 'python3 -m unittest'
  scripts/*.sh scripts/lib/*.sh` finds nothing; only bats wrappers run named cases). So add
  `tests/lr-recon-pass-clock.bats` following `tests/lr-recon-one-driver.bats`: one `@test` per
  control, marked `[RED]` or `CONTROL`. Also run the whole suite by hand before landing (rule
  "Landed ≠ tested"): `cd scripts/limit-recover && python3 -m unittest discover -s lr_recon/tests
  -t .` and assert `Ran N` plus `OK`.
- Optional, S: a census guard that counts `now`-comparison sites per module and fails when the
  count changes, with a message pointing at §3 so a reviewer classifies the new site. It is
  text-based and brittle, so only worth it if B3 and B2 add many sites.

---

## 9. Rollout, kill switch, operator steps

1. **Agent: build and land.** Build in a worktree, then commit on its own branch. Run the full
   lr_recon suite and the new bats. Land through the project-local `/ship`. Converge with
   `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (`.claude/CLAUDE.md` standing
   authorizations).
2. **Operator: load the code into the running reconciler at a quiet point.** Agents may not reload
   launchd jobs (`lr-band-reload.sh:4-5`), and REPORT A6 (i) says do not restart mid-cohort.
   - Check that nothing is open: `cat ~/.reso/limit-recover/recon/readout.line`. Empty means no
     open record.
   - Dry run: `bash ~/.claude/scripts/limit-recover/lr-band-reload.sh`
   - Reload: `bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm lr-band`. It waits
     for no `lr-recon-act` child, reloads the reconciler and the poller, and reads the band back.
   - Alternative: leave it to the next natural restart. B7 is state-compatible (§6, §7).
3. **Read-back** (read-only, after the first reconciler spawn following the reload):
   ```
   tail -1 ~/.reso/limit-recover/recon/band.log      # new pid, pri=31 … ok
   python3 -I -c 'import json,sys; R=sys.argv[1]; T=json.loads(open(R+"/restarts.jsonl").readlines()[-1])["t"]; r=[json.loads(l) for l in open(R+"/events.jsonl") if l.strip()]; s=[(max([x["t"] for x in r[max(0,i-200):i]] or [e["t"]])-e["t"]) for i,e in enumerate(r) if e.get("ev")=="spawn" and e["t"]>=T]; print("since restart t=%d: %d spawn rows, worst backdating %.1fs" % (T, len(s), max(s or [0.0])))' ~/.reso/limit-recover/recon
   ```
   Expect a worst backdating of about 0 s, against a p50 of 173 s before. Run today it prints
   `since restart t=1792512296: 0 spawn rows, worst backdating 0.0s` (measured). Record load1 and
   the daemon's band next to the reading (rule "Verify a cure under its load").
4. **Kill switch, no restart, read every pass.**
   - Engage: `printf 'pass\n' > ~/.reso/limit-recover/recon/pass-clock`
   - Release: `rm ~/.reso/limit-recover/recon/pass-clock`
   - What it reverts: `t_dec` back to `now`, the pacer back to `now`, and quiet windows back to
     last-seen.
   - What it keeps: the stamp-before-reader ordering, the spawn and launch.log stamps, and the
     IN-FLIGHT anchor. These are pure defect fixes with no behavioural upside to reverting.
   - Full rollback: `git revert` plus the reload in step 2.

---

## 10. Estimated size

Production: +95/−29 lines, measured as the prototype diff over 5 files:
- `__main__.py` +46/−15
- `settle.py` +31/−2
- `admit.py` +10/−5
- `act.py` +5/−4
- `report.py` +3/−3

Tests: about 300 lines. That is estimated from the 395-line prototypes less the duplicated fixtures,
plus the bats wrapper (about 40 lines). **Total about 430 LOC. Effort S.**

---

## 11. Dependencies on the other items

- **Hard prerequisites: none.** B7 is self-contained and lands on current `main`.
- **B3-deadline-override (soft; B3 should follow B7).** B3's "W_soft since `t_detect`" is a rate or
  time bound, so it must compare `t_dec` (R3) against `timeline.detected`, which is census-stamped
  (R1). Its deadline lane must not move `may_actuate`'s evidence waits to wall time (R4, E2).
- **B2-bounded-pass (independent; land B7 first).**
  - B2 shrinks the in-pass offset, which shrinks every D's magnitude.
  - B2's async probe and stale-while-revalidate placement widen the gap between census and decision,
    so R1-R5 matter more after it.
  - Both edit `_run_pass` and `_dispatch`: a merge-conflict risk, not a logical one.
- **A6-restart-safety (soft).**
  - If A6 persists the Admission counters, the pacer slots must be wall-stamped first (D3). Stamps at
    pass `now` are meaningless across a restart.
  - B7's quiet and IN-FLIGHT anchors already persist in `rec.close` (G6).
  - A6 should also size the claim orphan grace (§7).
- **B1-load-harness (soft; reuse).** B1 can reuse `lr_recon/tests/longpass.py`, and it needs D2's
  true spawn times to measure `t_first`.
- **B6-telemetry (soft).** B6 can log `t_dec − now` per spawn, which is the in-pass offset §2 had to
  infer. D2 makes the events legible.
- **C2-socket-prompt.** If C becomes socket-delivered, its grace still needs R5. Reuse `quiet_for`.
- **No interaction:** B4, B5, B8, C1, D1, D2, A7, G2.

---

## 12. Risks, open questions, what I did not verify

- **Size of the in-pass offset after A1, under a cohort: unmeasured.** No cohort has run since
  07:23Z: 0 `place` events and 2 spawns. If post-A1 passes stay under about 20 s even in cohorts,
  D1 and D3 rarely bind, and B7 is mostly D2 and D4 correctness (value lower, risk unchanged).
- **D1-C frequency: hypothesis.** It needs a typed launcher path ending UNVERIFIED or INDETERMINATE.
  I did not count how often lr-fire-resume still types since `a8ebaa7c0`, nor how often it ends
  unverified.
- **D4 reachability: the edge path was not observed live.** 0 instances among 138 records. The
  silent-forever behaviour is shown by C7, not by a production record.
- **E2 and E3 were designed, not run.**
- **Scope.** The audit covers `lr_recon` only. The bash lanes (`lr-move-worker.sh`,
  `handoff-fire.sh`, `lr-reset-poller.sh`) read `date +%s` at each use, so they are not pass-scoped
  in this sense, but they were not audited (out of B7's brief).
- **`ctx.actions` persists across passes.** A record that `continue`s in `_derive` before `:868`
  keeps the previous pass's action. This is not a clock defect, but it interacts with the C grace.
  Noted, not designed here.

---

## 13. Conviction

**80%** that this design, as written, lands green and does what it says under 15-40/core:
- every defect has a control that is red at HEAD and green with the fix;
- two mutants are killed;
- the pre-existing 628 tests are untouched;
- the format is backward compatible.

The 20% residual:
- the unmeasured post-A1 offset, which sets the value rather than the correctness;
- the designed-but-unrun E2 and E3;
- the possibility that a reviewer prefers to leave D4's anchorless IN-FLIGHT stranded rather than
  escalate it.

On the REPORT's own question, "Are the `settle.py:253,965` comparisons intended semantics?": the
census-to-census comparison is intended, but the last-seen anchor and the read-before-stamp ordering
are defects (C5 and C6 red, measured).

---

### Deviations from the brief

- **Heredocs.** Before I noticed the brief's ban on heredoc writes, I used shell heredocs to write
  scratch scripts under `/tmp/b7audit/`. All later scratch files were written with the Write tool.
- **Scratch locations.** Prototypes and test runs ran only in `/tmp` copies: `git archive HEAD | tar
  -x` into `/tmp/b7*`, with `TMPDIR=/tmp/b7audit/tmpdir` and `PYTHONDONTWRITEBYTECODE=1`.
- **Repository.** Nothing in the repository was edited except this file. No process was signalled,
  no launchd job touched, and no pane typed into.

---

## Review — correctness-and-safety

Adversarial review, 2026-10-20, worktree HEAD `28b25a119`. The reviewer re-ran the prototype and
probed it in fresh `/tmp` copies only: `/tmp/b7rev.o0jawl`, `/tmp/b7rev2.RQi0aX` and
`/tmp/b7revhead.O4yvF4` (a `git archive HEAD` copy). Each run used `TMPDIR=<copy>/tmpdir
PYTHONDONTWRITEBYTECODE=1`. Nothing in the repository was edited except this section.

**Verdict: NEEDS-CHANGES.** The two-clock model, the IN-FLIGHT anchor, the pacer on wall time and
the spawn stamps are sound. But D1's fix for C uses the wrong clock, and that reopens the
double-prompt hazard the grace exists to stop. E1 pins that hazard as wanted behaviour. A
read-before-stamp defect of the same R5 class was missed. And the new busy anchor turns a rare
rolled-back strand into a permanent, silent one. Conviction for the design as written: **50%**. With
changes 1-4: about 80%.

### What checks out (verified, not just re-cited)

- **The prototype result reproduces.** Measured: `python3 -m unittest discover -s lr_recon/tests -t
  .` in a copy of `/tmp/b7ks.4gR4aC` => `Ran 772 tests in 42.530s / OK`.
- **The line cites hold at HEAD**, and main has no lr_recon diff (`git diff --stat 28b25a119
  6fdf87eca -- scripts/limit-recover/` => empty):
  - `__main__.py:856` (busy_at), `:864-866` (typer_at), `:881` and `:1585` (updated_at as an age),
    `:1236-1237` (the C grace), `:1596` (busy_at as pass identity), `:1665` (`now`);
  - `settle.py:259` and `:1011`; `admit.py:187-198`, `:302-303` and `:330-332`;
  - `act.py:471` (R4) and `store.py:403` with `:308-310` (I-keep);
  - `evidence.py:206,208`; `act.py:482-489` (C is in `CLAIMED_ACTUATORS`).
- **The top-of-loop busy predicate equals today's.** `_role_live` (`evidence.py:96-97`) only looks at
  `rec.procs`, so it is a subset of `act.live_procs` (`act.py:355-357`).
- **R4 for `may_actuate`, and I-keep for the orphan grace, are correct.**
- **D2 has no program readers.** No reader of `intent.at` exists (`grep -rn 'intent\.at'
  lr_recon/*.py`, writers only), and `report._typers` keeps a record's rows whatever their `t`
  (`report.py:310-314`).
- **D4 is real.** `save_records` sets `rec.updated_at = t` on every record every pass
  (`store.py:165`).
- **Minor cite error.** `reap_actlogs` is at `act.py:418`, not `:427` (`grep -n 'def reap_actlogs'`).

### Finding 1 (blocking): C's grace is an evidence wait, so `t_dec` there re-opens the double prompt

- **What the grace is for.** C's grace exists because the launcher's user record "lands 1.6-11 s
  after the Enter … with re-sends up to 45 s" (`__main__.py:1238-1241`). C's go-ahead rests on
  evidence read in `_derive`: row 7's `UNPROMPTED` comes from `ev.submitted` and the target
  transcript read (`phase.py:116-121`, `evidence.py:223,234`).
- **Nothing re-reads that evidence before typing.** Between `act.choose` and `act.spawn`,
  `_dispatch` reads no transcript (`__main__.py:1218-1327`). `cc_tui_submit` gates only on an empty
  composer (`cc-tui.sh:593-607`), and C mints a fresh token (`__main__.py:1381`).
- **So this is R4, by the design's own definition:** "act only on a census taken ≥ N s after X".
  The design instead measures it to `t_dec` (§4 D1, §5 `_dispatch`, §7 "no added pass … because
  `t_dec` has advanced").
- **The failure.** The census that first misses the typer is at T, and the record lands at T+11. A
  dispatch at T+61 then types a second prompt on census-T evidence. The design's own E1 asserts
  exactly this ("C goes out in the same pass once 60 s of wall passed"). It is green at HEAD only
  because HEAD has the D1 last-seen defect.
- **Measured.** `test_b7_review_hazard` is E1's scenario with the token record written after
  `_derive` and before a `_dispatch` at census+61.
  - In the design's arm: `AssertionError: Lists differ: ['C'] != []` at the same-pass assertion.
  - With `quiet_for(rec, "typer", now)`: the same-pass assertion holds.
  - The full suite with only that one token changed: `Ran 772 … FAILED (failures=1)`, and the one
    failure is E1. M1 is therefore the safe variant, and E1 is the test that has to change.
- **Cost of the fix.** At most one more pass, inside REPORT §5's `P_max` term, which the design
  already accepts for the two settle checks. The §7 sleep-between-census-and-dispatch row goes away
  too.

### Finding 2 (blocking): a missed R5 defect. `timeline.submitted` is read before this census stamps it

- **The ordering.** `evidence.build` sets `submitted = rec.timeline.submitted is not None`
  (`evidence.py:223`) from the previous pass. It then finds this census's token (`_target_reads`,
  `:234`), and row 7 derives `UNPROMPTED`/C from the stale flag (`phase.py:117`). `_derive` only
  stamps `timeline.submitted` afterwards (`__main__.py:851-854`). §3.1 lists `:853` as I-obs and
  misses the ordering.
- **When it bites.** A launcher's record that lands after the first-unseen census is first seen by a
  census at least 60 s later, which is exactly the long-pass regime. That census still says
  `UNPROMPTED`, the grace has elapsed, and C types a second prompt. This happens even with
  Finding 1 fixed.
- **Measured.** With the census-instant grace alone, the hazard test's second assertion (census+70,
  token visible) fails with `['C'] != []`.
  - The fix: after `_target_reads(rec, ev)`, add `if ev.token_record_offset is not None and
    ev.token_is_this_attempt: ev.submitted = True`. That is the same predicate `_derive` stamps
    with.
  - With both fixes, the hazard test passes and the whole suite gives `Ran 786 … FAILED
    (failures=1)`, the one failure being E1 (`/tmp/b7rev.o0jawl`).

### Finding 3 (required): the new busy anchor makes a rolled-back strand permanent and silent

- **The predicate is too broad.** The busy predicate counts any live `lr-fire-resume … <sid>`. That
  relay lives as long as its claude (`__main__.py:884-885`, and `lr-fire-resume.sh:2273` execs a
  shell only after claude exits).
  - Measured: `ps -axo pid=,etime=,args=` shows 6 bash `lr-fire-resume.sh` relays alive for 13:23 to
    14:51 h, for sids e80b61f4, 3e929a81, ceff45c5, 3d1d988a, 9240c6a9 and d7eb73d2.
  - A rolled-back move keeps its source alive (`settle.py:226-235`). If that source was itself
    relaunched by lr-fire-resume, busy is seen on every census.
- **What follows.** `quiet_for` is -1 forever, so `rolled_back` never fires. `_invariant` also skips
  the record, because `busy_at == now` is under `ACTIVE_FAST_S` (`__main__.py:1594-1599`).
- **Measured.** `test_b7_review_relay` runs 90 passes at a 10 s cadence with the source-account relay
  (`next3` = `source_acct`) alive:
  - HEAD, with a busy_at seen last pass: `fired_at_pass=None defects=0`. This is pre-existing at
    normal cadence.
  - HEAD, with a stale busy_at: fires at pass 0.
  - The design: `fired_at_pass=None defects=0` in both shapes.
- **Why it is B7's to fix.** B7 removes the only escape, the long-gap reading. C5's relay is on
  `next4` (the target, `test_rollback.py:69`), so narrowing the predicate keeps C5 green.

### Finding 4 (required): the typer stamp can freeze at "seen"

- **Where it can freeze.** The typer `note_seen` stays after `evidence.derive` (§5). The early
  `continue`s skip it: engaged, not-needed, cohort-exit-resume, PARKED-REBOOT and rearm-cap
  (`__main__.py:752-790`).
- **Why that matters now.** Under a first-unseen anchor, a skipped census leaves `typer_quiet_at =
  None`, which reads as "seen", and it never ages. Today's last-seen anchor ages through skips.
- **Today's exposure is one pass.** A cohort-exit-resume record reaches `_dispatch` with a C wake
  (`settle.py:1101-1110`, `act.py:572-573`) in the same pass it skipped the stamp. That is bounded
  to one pass by `close["cohort_exit"]`.
- **The risk.** It is fragile by construction: any future early `continue` that leaves a record open
  could hold C or a wake for good.

### Not blocking, state them in the design

- **IN-FLIGHT expiry may fire while the watcher is still working.** `IN_FLIGHT_MAX_S` is 600 s, but
  the watcher's `--await` caps at 1,200 s (`__main__.py:59`). D4 now applies the 600 s expiry to
  unconfirmed IN-FLIGHT records too, so one can fail DETERMINISTIC while its watcher is still
  awaiting. That is the same as the confirmed path today.
- **The pacer docstring contradicts the new semantics.** `admit.py:7` says "at most 3
  submitted-not-ENGAGED per account". D3 makes it 3 per 20 s of wall time. Under load, ENGAGED takes
  minutes, so a long pass can hold more than 3 unengaged first turns per account. These stay bounded
  by the bucket and BootSlots. Reword `:7` as well as `:13-16`.
- **The report fallback anchor is coarse.** `timeline.detected` (D4b) measures "since detection",
  not "since entering this state". Any future numeric max-age state without a wait would page an old
  record at once.
- **E2 and E3 were never run.** Run them before landing.

### Required changes

1. C's grace reads the census instant, `settle.quiet_for(rec, "typer", now)`.
   - Delete E1 as an equivalence guard. Replace it with E1′: no C in the pass whose census first
     missed the typer, however late the dispatch; C goes at the first census at least 60 s later.
   - Move C4's decision to census+61 s so it kills the `t_dec` variant.
   - Add `test_b7_review_hazard` as a control.
   - Rewrite R5, §4 D1 "For C, using `t_dec`…", and the two §7 rows.
2. Fix the `timeline.submitted` ordering in `evidence.build` (Finding 2). List it in §3 as a D1
   sibling, with its control.
3. Narrow the busy predicate `rolled_back` reads so the source session's own relay does not count:
   exclude an `lr-fire-resume` whose account argument is `rec.source_acct` or `source_cfg`, or
   which is an ancestor of the source holder.
   - Keep C5 green.
   - Add a liveness control: rolled-back shape, source relay live, re-driven within one pass +
     60 s.
   - If this is ruled out of B7's scope, file it as its own item before B7 lands, and say in §12
     that B7 makes it unconditional.
4. Stamp the typer observation for every open record on every census, before any `continue`, or add
   a test that every path reaching `_dispatch` with C or a wake has stamped this census.
5. Run E2 and E3. Fix the `act.py:418` cite. Update the `admit.py:7` docstring. Note the
   IN_FLIGHT_MAX_S versus watcher `--await` gap in §7.

---

## Review — efficacy-under-permanent-load

Adversarial review, 2026-10-20 ~18:40-19:10Z, worktree HEAD `28b25a119`. The question: at 15-40 per
core, with every lane at PRI 31, does B7 bound recovery time, and does any new wait, bound or gate
assume that load falls? **Verdict: NEEDS-CHANGES.** My conviction is **45%** that the design as
written does what it claims under the premise (the author's figure is 80%).

D2 (spawn stamps) and D3 (a wall-clock pacer) are sound and help under the premise. Three of the
D1/D4 changes are not:
- one has no effect when passes are long;
- one turns a long-pass re-drive into a strand that emits no event at all;
- one widens a path where our own timeout becomes a verdict.

All three are measured below. All probes ran in my own `/tmp/b7eff/` copies:
- `base` is a copy of `/tmp/b7base.cZ1ZXt`, which matches HEAD apart from the proto tests (`diff -rq`);
- `fixed` is a copy of the author's `/tmp/b7ks.4gR4aC`;
- `m1` is a copy of `/tmp/b7mut.4uS4WA`.

Every run used `TMPDIR=/tmp/b7eff/tmpdir PYTHONDONTWRITEBYTECODE=1`.

### Verified

Every file:line in §0, §3.1 and §4 that I spot-checked matches HEAD (`sed -n <l>p` on 28 sites:
`__main__.py:1665,1237,855-856,763,813,881,1585,1596,1323`, `act.py:320,321,337,345,471`,
`admit.py:187,308,330,332`, `settle.py:203-204,259,1011`, `store.py:165,403`,
`report.py:196,224,996`). The design's predicate for the busy stamp it moves to the top of the loop
is equivalent to today's. `act.live_procs` (`act.py:355-357`) already covers `_role_live`
(`evidence.py:96-97`), so the moved stamp sees the same things.

### Finding 1: C's same-pass release (E1) is the D1 race, unchanged (high)

- **The claim.** The design defines C's grace as `t_dec - typer_quiet_at`, where `t_dec` is the wall
  clock. It says that in long passes there is "no added pass" for C (§7), and its control E1
  enforces that.
- **Why that is not a quiet window.**
  - The fact that C is owed (`UNPROMPTED`) comes from the census, read at `now`
    (`__main__.py:868`, `ctx.actions`).
  - The C actuator types through `cc_tui_submit` (`act.py:207-210`). That function only checks that
    the composer is empty (`cc-tui.sh:593-627`). It does not re-read the transcript.
  - So C typed at `t_dec ≥ q + 60` acts on evidence from census `q`, which is the first census
    that no longer saw the typer. That evidence is at most a few seconds younger than the typer
    itself.
  - This is R4 (an evidence wait), not R5. A later wall reading cannot make census `q` newer: that
    is the design's own rule (§1, R4).
- **Measured.** `python3 -m unittest lr_recon.tests.test_b7_eff2` ran C4's shape with the decision
  at census +61 s. In that shape the launcher writes `UNVERIFIED:submit` before census 2, and its
  record lands at t+305.

  | Arm | Pass 2 (census t+300, decision t+361) | Pass 3 (census t+600) |
  |---|---|---|
  | base (HEAD) | `['C']` | ENGAGED |
  | fixed (the design) | `['C']`, the second prompt | ENGAGED |
  | m1 (grace on census `now`) | `[]` | ENGAGED if the record landed, `['C']` if it never did |

- **What it means.** In the premise's regime the fixed arm behaves exactly like HEAD. The in-pass
  offset was p50 ≥173 s before A1 (§2), and after A1 it is unmeasured. So D1-C has no effect
  whenever dispatch reaches the record ≥60 s after the census. M1 is the correct design, and its
  cost is bounded: one more pass. E1 kills the correct variant.

### Finding 2: moving the busy stamp strands a rolled-back move whose source has a long-lived relay, and it emits no event (high)

- **Mechanism.**
  - `live_launcher` matches **any** `lr-fire-resume` process whose argv holds the sid
    (`evidence.py:208-209`).
  - That relay is the session's pty relay for the session's whole life. See `58885750c` ("it lives
    as long as the session") and `lr-fire-resume.sh:1179-1196`. It execs a shell only after
    claude exits (`:2273`).
  - So for any source pane rooted by an earlier `lr-fire-resume`, "busy" is seen in **every**
    census. B7 then holds `busy_quiet_at = None` and `quiet_for = -1`, so `rolled_back` never fires.
  - `_invariant` skips the record because `busy_at == now` (`__main__.py:1594-1600`).
  - `report._state` is `None` for PRE-MOVE/None (`report.py:106-110`), so no max-age page fires
    and the readout counts the record as "moving" (`:124`).
  - Today the stamp is written after the reader (`:813` against `:855`). One pass gap of 60 s or
    more therefore re-drives the record.
- **Measured.** `python3 -m unittest lr_recon.tests.test_b7_eff.RelayStrand` ran the db755a94
  rolled-back shape plus a live `lr-fire-resume … <sid>` row in every census.

  | Arm | 120 s pass gap (the premise) | 10 s pass gap |
  |---|---|---|
  | base (HEAD) | rolled-back on pass 1: attempt 2, BACKOFF, re-driven | never in 1,800 s, 0 defects (already a strand today) |
  | fixed | never in 17 passes (1,920 s): 0 defects, **0 events of any kind**, attempt 1 | never |
  | fixed with `recon/pass-clock`=`pass` | never: the kill switch does not undo it | not run |

  The result is the same with an A actlog instead of R (`test_b7_eff_a`).
- **Prevalence.** `ps -axo pid,etime,args | grep -c "^ *[0-9]* *[0-9:-]* /bin/bash
  [^ ]*lr-fire-resume.sh"` gave **6** live relay-rooted panes at 18:46Z, aged 13-15 h (measured;
  load1 196.4, 19.6/core).
  - Their argv0 is `bash`, so `root_shape` reads `shell` (`observe.py:312-314`,
    `observe_rows.py:28`) and their move is A.
  - The rollback cause in db755a94 was HELD:unreachable, a kitty-socket stall. That cause is
    **load-correlated (hypothesis)**.
- **Control C5 asserts this strand.** Its relay row
  `/bin/bash lr-fire-resume.sh next4 /p <sid> --prompt x` is the long-lived relay shape (pid 24868,
  the e80b61f4 relay, still alive at 14 h 42 m).

### Finding 3: D4 widens a path where our own timeout becomes a verdict, and it fires while the move's watcher is still inside its own bound (medium-high)

- **Mechanism.**
  - The expiry reads only `not ev.holders and not rec.escalated` (`__main__.py:876-883`).
  - It classifies the record DETERMINISTIC. The same fingerprint on the next pass then becomes
    ESCALATED (`classify.py:194-197`), because `in_flight_at` is never re-anchored and the check
    does not read `next_eligible_at`.
  - After `REARM_CAP`=4 re-arms the record becomes IMPOSSIBLE.
  - The watcher's `--await` bound is 180+600+180+180+60 = **1,200 s** (`handoff-fire.sh:20159`;
    `IN_FLIGHT_MAX_S` at `__main__.py:59` says so). That bound includes
    `HF_RECYCLE_SHELL_WAIT_S` 600 s for `/exit` to reach a shell, which is load-stretched.
  - A fixed 600 s that then becomes a verdict assumes the relaunch gap fits inside it. That
    contradicts REPORT §5 G2 ("our timeout is never a verdict") and G5.
- **Measured.** `python3 -m unittest lr_recon.tests.test_b7_eff3` ran IN-FLIGHT with no confirm,
  `ev.live_watcher=True`, 5 s passes for 1,195 s.
  - base: no expiry, the silent strand D4 targets.
  - fixed: `in-flight-expired … → RETRY`, then `→ ESCALATED` on the next pass. `last_error` is
    DETERMINISTIC at +610 s, with the watcher live throughout.
- **Effect.** ESCALATED blocks `may_actuate` (`act.py:473`) and with it the B/R rescue (rows
  10-11) for up to 15 min per re-arm.

### Finding 4: the §7 latency statements are not the G terms (low-medium)

- **Settle quiet windows.** D1 for `rolled_back` and `holder_gone` adds one census:
  - the worst case re-drive is about 60 s + 2·P + B after the lane goes quiet;
  - that is not "within B_max + P_max";
  - P is load-dependent until B2 lands (REPORT §5: measured P_max ≈ 14 min).
- **C after Finding 1's fix.** C's bound becomes ≤ 60 s + 2·P after the typer's last sighting.
- **`may_actuate` on `now`.** Keeping it on `now` (E2) makes the retry term B + 2·P, not
  B_max + P_max. That is correct for R_PROOF_S, but the bound should be stated as such.
- **Inconsistency.** "No B7 change … adds a wait" (§7, last line) contradicts §7's own D1 row.

### Finding 5 (minor): the pacer slot is stamped before the probe

- `t_dec` is read before `self.probe` (up to 30 s), then used for `pacer_take` and `last_admit_at`.
- A slot is therefore stamped up to 30 s before its admission. With probes ≥20 s the slot is
  already expired at the next `decide`.
- This is harmless for throughput, because the probe serialises admissions. But G3's "3 per 20 s of
  real time" is not literally what the code enforces. The drip already re-reads the wall after the
  probe (`admit.py:318-322`).

### What holds under the premise

- **D3** removes a real per-pass cap of 3 first turns per account. Inside a long pass that cap
  bound below the token bucket's 1 per 20 s (C1 and C2, author-measured).
- **D2** is pure forensics.
- None of B7's changes reads the load average.
- The `may_actuate` and claim-grace keeps (E2, E3) are right.
- The cost of `note_seen` is two extra `_argv_live` scans per open record. That is negligible at
  1,746 procs and 4 open records (`ps -axo pid= | wc -l`, and a scan of `recon/sessions`).

### Required changes

1. **C's grace is an evidence wait (R4), not a quiet window.**
   - Use `settle.quiet_for(rec, "typer", now) < C_GRACE_S` on the census instant, which is M1.
   - Delete E1 and replace it with its negation: in `test_b7_eff2`'s shape, no C in the pass whose
     census first missed the typer even at decision +61 s, then ENGAGED or C on the next census.
   - Update §1, §3.1 row 1236-1237 and §7.
   - Alternative: re-read this attempt's target transcript for the token at `t_dec`, immediately
     before spawning C.
2. **"Busy" must mean a lane of this move, not any relay of the sid.**
   - Count an `lr-fire-resume` row only if it started after the move began. Its `lstart` must be
     later than `timeline.planned` or the move spawn's `intent.at`. Otherwise require that its
     launcher has not settled (`settle.launcher_settled`).
   - Apply the same predicate to `_invariant`'s `ACTIVE_FAST_S` skip, so that a record held only by
     a relay is re-driven or paged, never left silent.
   - Rebuild C5 with a launcher started after the move.
   - Add `test_b7_eff`'s strand as a control: at 120 s and at 10 s pass gaps, `rolled-back` within
     60 s + 2 passes, and never zero events.
3. **D4 must not add a timeout-to-verdict path.**
   - Do not expire while this attempt's watcher or launcher is live (`ev.live_watcher`,
     `act.live_procs`), or raise the bound to at least the watcher's 1,200 s.
   - Re-anchor `in_flight_at` after firing, and classify TRANSIENT (G2).
   - Or limit B7's D4 to `_invariant` (silent becomes paged) and leave the DETERMINISTIC ladder to a
     separate ruling.
   - Add `test_b7_eff3` as a control: watcher live for 1,195 s gives no DETERMINISTIC.
4. **Kill switch.** Either `pass` also restores the old busy-stamp position, or §9 states that the
   switch does not undo the rollback behaviour (measured: still stranded with the switch engaged).
5. **Restate §7's bounds** with the real worst cases from Finding 4, and say that B7's added census
   is load-dependent until B2 enforces P_max. Remove the "adds no wait" line.
6. **(minor) Re-read the wall after the probe** for `pacer_take` and `last_admit_at`, as the drip
   does. Extend C1 so the probe advances the wall.

### Deviations

- Scratch tests are in `/tmp/b7eff/` (written with Write, plus `cp`/`sed` into the /tmp copies).
  Nothing else in the repository was touched.
- `ps` and `sysctl` were read-only.
