# Account rotation at the 100th percentile: research report (2026-10-24)

Written 2026-10-25 at 00:30 CDT (05:30 UTC) in worktree `wt-cc-225311-6680`. This was research only. Nothing was moved, switched on or reloaded. Bracketed tags such as [R3] point to the receipts in section 9. Every number is labelled **measured** (a command or file produced it) or **estimated** (the method is named).

Terms used throughout:
- **pp**: percentage points of an account's weekly (or 5-hour) quota.
- **Strand**: quota points still unused when an account's week resets.
- **Sink**: an account whose quota is projected to strand.
- **Donor**: an account with a late reset that gives up sessions.
- **Move lane**: `cc-lr move`. It restarts a session in place, in the same pane with the same session id, on another account, without spending a model turn.
- **Reconciler**: the limit-recover reconciler daemon (`com.reso.lr-reconciler`).

---

## 1. Answer first

1. Yes, this has now been researched: 5 evidence slots, 3 competing designs and a judge that checked their file:line claims. The system you want is not built. Nothing in the fleet moves a live session before that session hits a rate-limit error, and the four pre-limit pieces that exist are either switched off or point the wrong way. That is why about 19 sessions are still running on `next` (account 1) while `next4`'s quota expires unused [R2, R16].
2. The 100th-percentile system is a **landing-level rebalancer**. It aims each account's week to finish at 97-99% at its reset and never reach 100% before it. It does this by moving real, actively working, non-team sessions in place onto the account whose quota expires soonest. It is built as a new "rebalance arm" inside the existing late-band shed controller, `scripts/limit-recover/lr-shed.py`.
3. It is driven by events: new usage-feed samples, weekly reset rolls, StopFailure rate-limit markers and each session's own end-of-turn beat. It acts only through the existing in-place move path (`lr-handoff.sh --in-place`, same pane, same session id). After the operator's one-time mode file, no human step is needed.
4. It never launches a session (filler stays vetoed under decision 8f9618059700). It never moves team leads, teammates or mid-turn sessions. It moves at most 4 sessions per tick, one at a time, and a breaker drops it to log-only on the first casualty or overshoot.
5. The bigger prize is next3, not tonight's next4. next4 has about 14 pp expiring in 3.5 h, of which the movable sessions can fill only about 2-3 pp. next3 has about 71-73 pp expiring at 2026-10-27 12:00 UTC (estimated) [R2, R22]. Reaching it needs a 96-hour look-ahead and selection by burn rate, and only the chosen design has both.

---

## 2. Right now (05:27 UTC / 00:27 CDT)

| Account | Live sessions | 5-hour used | Weekly used | Weekly reset |
|---|---|---|---|---|
| next | 19 | 65% (resets 06:30Z) | 5% | 2026-11-01 03:59Z |
| next4 | 13 | 1% (resets 10:10Z) | 83% | **2026-10-25 08:59:59Z (3.5 h)** |
| next3 | 3 | 2% | 18% | **2026-10-27 12:00Z (54.5 h)** |
| next2 | 2 | 1% | 2% | 2026-10-31 11:00Z |

Measured: newest rows of `~/.claude/logs/account-utilization.jsonl`, ts 2026-10-25T05:26:59Z [R2].

**Why the sessions are still on next:** next is not limited. The reconciler acts only after a session's transcript ends in a rate_limit error (`lr_recon/facts.py:12-13`). Idle fan-out is off: `~/.reso/limit-recover/recon/idle-fanout.on` is absent, and even when on it needs an existing limit fact (`census.py:28-31,283`). The shed is off (`~/.reso/limit-recover/shed/` is absent). `cc-lr rotate` moves sessions only off an account at 100% (`bin/cc-lr:526-536`) [R16, R19]. The router already ranks next4 first for recovery placement: `next4 0.008944, next3 0.000255, next2 0.000042`, with next excluded as recovery-5h-thin [R7].

### Should next's sessions move to next4 tonight? Yes, a chosen set of 12. Conviction 70%.

- **Strand without a move (estimated):** next4 is at 83% and has been gaining 0.69-1.03 pp/h [R6]. Over 3.48 h that lands it at about 85.4-86.6%, so **about 13.4-14.6 pp would strand**. Method: linear extrapolation.
- **Re-verified at 05:30:51Z** by the dry run in [R3]:
  - 7 sessions move now: panes 2, 20, 47, 117, 262, 272, 307.
  - 5 wait for their turn to end and then move: panes 217 and 271 mid-turn, 274 background job, 301 subagents in flight, 309 mid-turn.
  - 1 holds: pane 216 now has a live `/goal`.
  - Exit 0. There was no `target-unroutable` line, so the router accepts next4.
- **Left out on purpose:**
  - Cold panes 7 and 67, idle about 12 h: they burn nothing and would only add restarts under load [R4, R5].
  - The lead (pane 263) and teammates (283, 292, 320): these are held by design, because a lead's exit kills its team [R4].
  - Pane 314 (session 30729231): this research session.
- **Expected fill (estimated):** the 13 sessions originally chosen carried 24% of next's last-hour output tokens (57,456 of 237,470) [R5]. 0.24 × next's 3.1-3.8 pp/h [R6] gives 0.74-0.91 pp/h. Over about 3-3.3 effective hours (moves run 4 at a time; waiting rows restart at turn end) that is **about 2-3 pp filled**, so next4 lands near 88-89%. The output-token share leaves out cache writes and subagent transcripts, so the true share may differ in either direction.
- **No overshoot risk (estimated):** even moving every next session would put next4 at about 97-101% [R5]. Moving 24% of the burn cannot reach the wall. next4's 5-hour window has just reset to 1%.
- **Side benefit (estimated):** at 3.1-3.8 pp/h, next itself would reach 100% weekly in about 25-31 h, around 2026-10-26 06:00-12:00Z, if tonight's pace held (linear extrapolation; overnight pace usually drops). Moving about 0.8 pp/h off next pushes that wall out by about a quarter.

**The exact command** (dry-run verified [R3]). Run it from a plain shell or any session. The explicit session ids mean it cannot move the caller.

```
~/.claude/bin/cc-lr move --sids 79076bcf,87a4411d,85c040d1,f27965bc,1bede217,3d1dc252,0e2799a9,2b3becea,15f652bd,502bd860,7396b781,88fc8283,06457213 --to next4 --until-idle 1800
```

Then check progress with `~/.claude/bin/cc-lr move --status <batch>`. To stop workers that have not started, use `cc-lr move --abort <batch>`.

Do not wrap the command in an outer `timeout`. With `--until-idle 1800` the foreground can legitimately wait up to 30 minutes, and an outer kill cannot tell a slow but healthy wait from a hung one. If a bound is needed, use cc-lr's own `--wait S`.

**Risks tonight:**
- **Load and outage:** load averages were 181.84 / 397.56 / 558.20 at 00:29 CDT [R24]. That means 12 exit-and-relaunch cycles, 4 at a time. Each pane is down for 58-129 s (measured on today's 6 moves) [R10].
- **Cache rewrite:** each warm move rewrites the session's prompt cache on its next turn. 273K-479K tokens of cache writes were measured after today's moves [R11]. The cost lands on next4, whose quota is expiring anyway, so ruling 1 accepts it.
- **Race at turn end:** a waiting row restarts the moment its turn ends. A few seconds remain between the last probe and the `/exit` (estimated), in which a task notification or a keystroke could land.
- **Rows flip between holds:** pane 216 changed from movable to goal-live within 90 minutes, and pane 272 flipped the other way earlier [R3, R4]. Rows that turn held are simply not moved.
- **Small record since the fixes:** since 2026-10-19 the move lane is 8 of 8 MOVED on rows that reached the actuator. Before that it had 12 STRANDED and 13 FAILED out of 146 [R10].
- **Slow batch start:** the batch waits for a poller kick (re-kicked every 15 s), because the instant-start job (activation 53) is not loaded [R16].

### After next4 resets at 08:59:59Z (03:59 CDT)

- **Move nothing back.** At 09:00Z next4 starts a fresh week, as fresh as next. Moving sessions back would only mean more restarts under load with no quota gain.
- **The next sink is next3.** It is at 18% with about 54.5 h to its reset and gains 0.16-0.21 pp/h [R2, R22]. That lands it at about 27-29%, so **about 71-73 pp strand** (estimated, linear extrapolation). At 5-10 session-hours per pp (estimated in [R6]), that is about 355-730 session-hours of work otherwise lost.
- **Filling it (estimated):** next3 can take about 1.2 pp/h of added burn and still land at or below 97%. Method: (97 − 18 − 0.21 × 54.5) / 54.5. That is roughly 8-10 next-like working sessions. Its 5-hour window stays safe: 0.55-0.72 pp per session-hour [R6] × 10 ≈ 36% per window.
- **The rebalancer will not exist in time** (estimated from the waves in section 6), so this fill has to be done by hand. That is decision 2 in section 8.

Recipe, all read-only until the last step:
1. Run `cc-lr plan --from next --to next3 --until-idle 1800 --json` and `cc-lr plan --from next4 --to next3 --until-idle 1800 --json`.
2. Keep the rows with a `move` or `wait:*` disposition, warm cache and recent burn. Never take team rows or cold rows.
3. Dry-run with `cc-lr move --sids … --to next3 --until-idle 1800 --dry-run`, then run it without `--dry-run`.
4. Re-check next3's landing every few hours and stop adding sessions once it projects past about 95%.

---

## 3. Measured prize

All figures cover the 30 days from 2026-09-24 to 2026-10-25 unless stated otherwise.

| Lever | Size over 30 days | Size now | Receipts |
|---|---|---|---|
| Moving sessions onto accounts about to strand (sink fill) | 23 of 2,400 account-points stranded over the last 6 resets, about 1% (measured). At 5-10 session-h/pp that is about 115-230 session-h (estimated). | next4: about 13-15 pp by 09:00Z. next3: about 71-73 pp by 10-27 12:00Z (both estimated). **This is the only lever paying out this week.** | R9, R2, R22 |
| Moving sessions before they hit a limit (pre-wall rotation) | 121 quota-wall episodes (100 weekly, 21 five-hour) from 117 sessions, costing 231.3 session-hours. 121 of 121 had headroom on another account. | Low: 7 episodes and 1.1 h in the latest week, none since 10-21. | R8 |
| Faster recovery after a limit (post-wall) | The same 231.3 h pool, so it does not add to pre-wall. 25 episodes waited past the reset and cost 156.8 h. The other 82 moved first: weekly median 8.7 min (p90 165 min), 5-hour median 19.5 min (p90 59 min). | Same low run rate. | R8 |
| ps-blind reconciler passes | 97 'ps degraded' abstains across events.jsonl and events.jsonl.1: 75 failed on the args call, 22 on the tty call. | 15 in a row from 22:43 to 22:56 on 10-24, of which 14 were args timeouts and 1 a tty timeout. | R13 |

Supporting measurements:
- **Supply is the binding constraint.** Accounts sat weekly-capped for 356 account-hours in 30 days [R9]. Tonight's fleet weekly burn is about 4.0-5.0 pp/h against a supply of 2.38 pp/h (4 × 100 pp / 168 h) (estimated from [R6]). So every stranded point is lost work, not spare capacity.
- **Why idle-only moves fill little:** idle sessions burn about nothing. On next, the movable warm idle rows carried at most 5% of last-hour output, the busy movable rows 19%, the team 44% and the research session 32% [R5].
- **The move lane:** across 83 batches, 47 MOVED, 220 NOTMOVED, 13 FAILED and 12 STRANDED. Since 2026-10-19 it is 8 of 8 MOVED [R10]. A busy session can escape `--until-idle` entirely: session 2a707a01 was read 151 times over 3,600 s, mid-turn every time, and ended NOTMOVED [R12]. There are 63 still-busy NOTMOVED rows on record [R10].
- **Reconciler latency:** the median from detection to ENGAGED is 81 min (n=19) [R21].
- **Read-only planners hang under load:** `cc-lr plan` exited 124 at 60 s, and `cc-lr rotate --list` exited 124 at 240 s [R14].
- **A free signal goes unused:** the statusline input in Claude Code 2.1.291 carries `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`, and `statusline.sh:86-104` drops it [R15].
- **Precedent for the ruled approach:** on 10-24 a session moved 6 real sessions onto next by hand, and next then closed at 99% [R20].

---

## 4. The chosen design: a rebalance arm on the late-band shed controller

The judge chose the **economics-first** design. Its scores were value 9, safety 6, rulings 8, implementation risk 4 and verifiability 8. Event-first scored 6/5/9/4/8 and minimal scored 4/7/8/8/8 [R25].

It won because it is the only design that sees next3:
- It looks up to 96 h ahead, using a strand forecast corrected for its own measured bias.
- It picks sessions by priced burn rather than idleness.
- It does not inherit the router's 90% recovery floor (`bin/claude-accounts:4182`, `RECOVERY_W_FLOOR_DEFAULT = 0.10`, which excludes weekly usage of 90% or more). That floor would leave at least 10 pp on every sink.

The grafts from the other two designs cut scope and risk:
- Ship the sink arm first, using the minimal design's origin plumbing and the shed's existing breaker and lock.
- Add event-first's zero-code instant batch start, its turn-end catch on a kernel file watch, and its readout and missed-fill audit.

Everything lives beside the move lane, not inside `lr_recon`. `facts.py:12-13` (usage % is never a limit signal) stays untouched.

Naming: the mode file is `~/.reso/limit-recover/shed/rebal` and the move origin is `rebal`. The word "fill" is avoided on purpose so this is never confused with the vetoed filler launcher `strand-fill-arm.sh`.

### C1. Landing band: `claude-accounts --rebal-band --json` (about 220 LOC)
- **Where:** `bin/claude-accounts`, beside `shed_band_row` (:7113-7177) and `cmd_shed_band` (:7180-7237). It reuses `wk_strand_pp` (:5663-5688), `strand_score` (:5701, `STRAND_SCORE_FLOOR` 4.0 at :5693), `burn_5h_ewma_ph` (:5516) and `_su_projected` (:4805-4830). It is dispatched next to `--strand-score` (:12544).
- **What it returns, one row per account:**
  - weekly used %, hours to reset, and pace low/high;
  - projected landing = used + pace_high × hours;
  - raw strand, and strand minus the forecast's measured bias at that horizon (+15.25 pp at 48 h, +8.45 at 24 h, +5.52 at 12 h, +3.39 at 6 h [R23]);
  - sink capacity in pp/h = (97 − landing) / hours;
  - 5-hour landing.
- **Verdicts:** `sink | donor-7d | donor-5h | neutral | walled | unknown:*`. A sink opens at any horizon up to 96 h once its corrected strand is at least 4 pp.
- **Trigger:** each controller tick. It reads the cache only and never runs a sweep.
- **Safety:** it is a pure function. An `unknown` verdict never opens or closes a window, and no routing constant changes (routing ruling of 2026-09-22).

### C2. Per-session burn meter: new `scripts/limit-recover/lr_burn.py` (about 200 LOC)
- **What:** incrementally tails each live session's main and subagent transcripts, keeping offsets in `shed/burn.json`.
  - Dedupes on `message.id` and takes the maximum output tokens per message (the `bin/cc-quota-price` contract).
  - Drops `*.jsonl.handed-off` transplant copies.
  - Prices tokens with `hooks/lib/idle_gap.py:43-48` (WRITE_PP 0.245, OUT_PP 0.404, READ_PP about 0.006 pp per million tokens).
  - Turns each session's 60-minute priced share into pp/h as that share of its account's measured pace.
  - Output row: `{sid, acct, b_wk, b_5h, last_stop_t, operator_t, ctx}`.
- **Liveness without ps:** `<config>/sessions/<pid>.json` checked with `kill -0` (45 ms measured), plus `kitten @ ls` (73 ms measured) [R13].
- **Safety:** read-only, with a byte cap per transcript per tick. It replaces tonight's output-only share, which left out cache writes and subagents.

### C3. Sink arm in `lr-shed.py` (about 200 LOC; the donor arm is deferred)
- **Where:** a new `select_sink()` beside `select` (:464-481) and a sink block in `_tick` (:818-1088). `step_hysteresis` (:431-461), `open_limited` (:717-739), `run.lock` (:322-355) and `shed/breaker` are reused, so there is no second lock or breaker.
- **Logic:**
  - Sink: the account with the earliest reset that has a sink verdict and capacity.
  - Donor: an account whose weekly reset is at least 24 h after the sink's, and whose own corrected strand stays 0 after the move.
  - Ranking: greedy, by value v = b_wk × min(sink hours left, 96). Rows with v < 1 pp are skipped.
  - Stops when: moved burn reaches 0.8 × capacity, 4 rows have been picked in this tick, the sink's projected weekly landing reaches 97% (using upper-bound burn), or its projected 5-hour usage reaches 80%.
  - Never moves anything back after the reset.
- **Routing:** it does not use `--place --recovery`, whose 90% floor would stop it at exactly the last 10 pp. Instead `cc-lr move`'s own `--rank general` routability check (`bin/cc-lr:905-930`, applied at :1684-1696) stays the arbiter. Whether `--rank general` itself excludes a sink above some weekly level is not verified; check it in shadow.
- **Trigger:** C6 events. In shadow mode it stops at `cc-lr move --dry-run` and logs, as the shed does today (`lr-shed.py` about :977-1035).
- **Holds:**
  - Never moved: team leads and teammates, background-job rows, rows with a goal (`SHED_ENV`, `lr-shed.py:111-115`), drafts, focused panes or panes with an operator prompt in the last 10 min, and dormant rows (b ≈ 0).
  - Mid-turn rows only wait (C5).
  - The arm yields while any limited reconciler record is open.
  - Limits: `--slots 1`, 4 per tick, and a shared 6-hour cooldown per session.
  - `strand_audit` (:655-706) gains an overshoot verdict: a sink that hits its wall with more than 15 min left trips the breaker.

### C4. Move-lane origin `rebal` and re-authorization (about 40 LOC)
- **Where:**
  - `bin/cc-lr:1631`: the allowlist is `''|shed` today; add `rebal`. Plan and intent writes are at :1709-1724.
  - `scripts/limit-recover/lr-move-worker.sh:60` and :117-137: a `rebal_authorized()` copied from `shed_authorized`.
  - `lr-shed.py:519`: `plan.get("origin") != "shed"` becomes a set test, so breaker scans, cooldowns and in-flight accounting cover rebalance batches.
- **Trigger:** every intent read: at the claim, before the actuator, and every 30 s while waiting.
- **Safety:** removing `shed/rebal` revokes queued moves within about 30 s. With origin unset, plans and intents stay byte-identical.

### C5. Catch busy sessions at turn end, by event (about 80 LOC)
- **Where:** the wait loop at `lr-move-worker.sh:211-257`. Each waiting worker runs `bin/cc-kqwait --file ~/.claude/cc-beats/<sid>.json` (the synchronous Stop beat, `hooks/session-beat.sh:91`). On a new stop beat it waits 3 s, so the asyncRewake Stop hooks can start a turn if they are going to. It then takes two single-session census reads (`lr-upgrade.sh:3408 --switch-census --sid`) about 10 s apart and proceeds only on two "move" verdicts.
- **What it replaces:** the 24-second shared-census polling loop that missed 2a707a01 (151 reads) [R12].
- **Safety:**
  - Every existing hold still applies.
  - `hf_bg_work_gate` (`scripts/handoff-fire.sh:3462-3482`) re-probes before `/exit`.
  - If kqwait exits 4 (unavailable), the old path is used.
  - Kill switch: `LR_MOVE_TURNEND=off`.

### C6. Event scheduling (about 60 LOC plus 0-LOC activations)
- **(a) Instant batch start, 0 LOC:** the operator runs `docs/activation/pending-activation/53-lr-move-kick-activate.sh`. It loads the staged `launchd/staged/com.reso.lr-move-kick.plist` (WatchPaths on `move/requests`, ThrottleInterval 2), so batches start in 1-2 s instead of up to 600 s.
- **(b) Controller job:** a new staged `launchd/staged/com.reso.lr-balance.plist` with WatchPaths on `~/.claude/logs/account-utilization.jsonl` (a new sample about every 6.6 min) and `~/.claude/autonomy/stop-failure`, ThrottleInterval 60, running `lr-shed.py --tick`. It comes with a pending-activation script. It must run under `/bin/bash` 3.2, the launchd interpreter.
- **(c) Poller backstop:** `lrp_shed_kick` (`lr-reset-poller.sh:534-555`) should also start the controller when only `shed/rebal` exists. This is **deferred until fix/lr-recon-defects merges**, because that branch edits `lr-reset-poller.sh` [R18].
- **Safety:** single-flight through `run.lock`, so a racing kick does nothing.

### C7. Shed selection-order fix (3 LOC)
- **Where:** `lr-shed.py:480`. `ok.sort(key=lambda r: (r.get("cache") != "cold", -r["idle_s"]))` becomes `(r.get("cache") == "cold", r["idle_s"])`, with the docstring at :465-466 and its test updated.
- **Why:** the 2026-10-21 recheck on packet 76a584cc935b found that cold-first ordering avoids 4-6 of 43 walls instead of the 15 designed [R17].
- **Safety:** the shed stays off until `shed/mode` exists. This only reorders the same eligible set.

### C8. Readout and audits (about 120 LOC)
- **Where:** `lr-shed.py` `log()` (:163), `strand_audit` (:655-706) and `page_once` (:280).
- **What:**
  - A decision row for every tick, including no-ops with their reason.
  - A week-close **missed-fill** audit across every account: a close below 95% with an eligible donor and no rebalance batch pages once, keyed on the cause.
  - A readout line `~/.reso/limit-recover/shed/readout.line` beside `recon/readout.line`, for example `rebal: next3 sink 56pp/54h, 3 queued, 2 waiting(turn-end), 4 team-held`. That line answers "why are sessions still on account 1" without anyone investigating.

### C9. Statusline wire reading, recorded as data only (about 8 LOC)
- **Where:** `statusline.sh:88-104` (inside the existing jq call, so no extra process) and the fallback emit at :292-300.
- **What:** adds `rl5`, `rl5_reset`, `rl7` and `rl7_reset` to the `/tmp/cc-telemetry` rows. This proves the fields arrive at runtime before anything reads them; so far they are documented only in the 2.1.291 binary [R15]. Markers and a ledger come later.
- **Safety:** missing fields render as null inside the existing `try`. Reverting is one line.

**First release, through canary:** about 930 production LOC (estimated by summing the component sizes above) plus tests.

**Deferred to phase 2 (after a clean canary):**
- Donor arm: shed sessions off an account projected to hit 100% before its reset, onto open sinks. About 150 LOC.
- Recycle steering: `handoff-fire.sh:16750-17065` and `bin/claude-accounts:3925-3980`. About 70 LOC.
- Wire markers and a 5-hour band. About 40 LOC.
- A ps-free move-lane census (`lr-upgrade.sh:344`). About 70-180 LOC.
- Optional tty carry-forward in `observe.py:161-205`. About 25 LOC; it removes 22 of 97 recorded abstains but would have saved only 1 of tonight's 15.

---

## 5. Rollout

**Phase 0: land with everything off.** The `shed/rebal` file absent means off, and a bad token means off. C7 lands and the shed itself stays off. C9 writes data that nothing reads yet.

**Phase 1: shadow (the operator writes `shadow` to `~/.reso/limit-recover/shed/rebal`).** Every would-move is logged with a `cc-lr move --dry-run`, and the readout and audits go live.

Acceptance:
- Over at least one sink window (next3, 10-27 12:00Z, is the first), the sink-open decision agrees with the realized strand at least 80% of the time at its horizon.
- 0 picks whose plan disposition is not `move` or `wait:*`.
- 0 would-moves of team, cold, focused or goal rows, or of this session's own row.
- Would-fill is within ±50% of what C2 measures afterward.
- Tick p90 is at most 900 s at load of at least 30 per core, and at least 90% of ticks are not `unknown`.
- `rate_limits` appears in at least 95% of busy-pane telemetry rows (C9).
- Offline replay of 30 days through the lever-eval kernel (commit f4d626ba9) projects a fill of at least 50% of strand.

**Phase 2: canary (`shed/rebal` = `canary`).** At most 1 move per tick, at-rest rows only (turn-end catch off), one sink window.

Acceptance:
- At least 3 moves reach a verdict.
- 0 STRANDED or FAILED (either would trip the breaker).
- No wall on the sink before its reset.
- The sink's final weekly is at least 2 pp above the shadow forecast's baseline.
- Pane outage is at most 130 s per move.
- No operator-surprise page.

**Phase 3: on (`shed/rebal` = `on`, max 4 per tick, `LR_MOVE_TURNEND` on).**

Continuing acceptance, per weekly reset:
- Strand on every account that had movable donor rows trends down.
- Casualties stay at 0.
- The missed-fill counter trends toward 0.

Then the donor arm goes to shadow, and turns on once a replay shows at least 10 of 43 walls avoided.

**Kill switches, narrowest first:**
- `LR_MOVE_TURNEND=off` turns off the turn-end catch only.
- `rm ~/.reso/limit-recover/shed/rebal` revokes queued rebalance intents within about 30 s.
- `shed/breaker` is written automatically on a casualty, strand or overshoot, and forces shadow.
- `LR_REBAL=off`.
- `LR_SHED=off` stops all shed-controller arms.
- Removing `autorecover.on` stops every zero-human move.
- The operator can boot out the `com.reso.lr-balance` job.
- C9 reverts with one line.

---

## 6. Implementation waves

Each wave fits one dispatched session at 500 LOC or less including tests (estimated). The in-flight branch `fix/lr-recon-defects` edits these 8 files: `scripts/limit-recover/lr-fleet.sh`, `lr-reset-poller.sh`, `lr_recon/__main__.py`, `lr_recon/census.py`, `lr_recon/tests/test_bounded_pass.py`, `lr_recon/tests/test_census.py`, `tests/lr-fleet.bats` and `tests/lr-reset-poller-reroute-cap-clear.bats` [R18]. **Waves A-F touch none of them.** Each wave's done-condition must end at what an agent can do; operator acts such as mode files and launchd loads are listed separately, never inside a wave's goal.

| Wave | Content | Files owned (exclusive) | LOC (est.) | Depends on | Done when |
|---|---|---|---|---|---|
| A | C1 landing band | `bin/claude-accounts`; new `tests/claude-accounts-rebal-band.bats` | 220 + 200 tests | none, runs in parallel | `--rebal-band --json` returns tonight's sinks (next4, next3) from the cache; tests pass |
| B | C2 burn meter | new `scripts/limit-recover/lr_burn.py` and its unit tests | 200 + 200 tests | none, parallel | the per-session pp/h shares sum to the account pace within 10% on a replayed hour |
| C | C4 plumbing (worker and cc-lr parts) and C5 turn-end catch | `bin/cc-lr` (origin allowlist :1631 and plan/intent :1709-1724 only); `scripts/limit-recover/lr-move-worker.sh`; new `tests/lr-move-rebal-origin.bats` and `tests/lr-move-turnend.bats`, run under `/bin/bash` 3.2 | 120 + 200 tests | none, parallel | the bats suites pass and print their `1..N` plan line; a revoked `shed/rebal` aborts a queued intent |
| D | C7 order fix and C9 statusline fields | `lr-shed.py` `select()` only plus its test in `tests/lr-shed.bats`; `statusline.sh` | 11 + 60 tests | none, parallel; **merges before E starts** | the shed test asserts warm-first ordering; a telemetry row shows `rl7` with a fixture payload |
| E | C3 sink arm, the `lr-shed.py:519` origin set, C8 readout and audits | `scripts/limit-recover/lr-shed.py`; `tests/lr-shed.bats` | 320 + 180 tests | A, B, C, D merged | a shadow tick on fixture data logs the right sink, donor and picks; overshoot trips the breaker in tests |
| F | C6(b) controller job | new `launchd/staged/com.reso.lr-balance.plist`; new `docs/activation/pending-activation/NN-lr-balance-activate.sh`; a bats test under `/bin/bash` 3.2 | 60 + 60 tests | E merged | the staged job and activation script pass lint and test; nothing is loaded |
| G1 | C6(c) poller backstop and the donor arm (shadow) | `lr-reset-poller.sh:534-555`; `tests/lr-reset-poller-shed-kick.bats`; `lr-shed.py` | about 200 + tests | **fix/lr-recon-defects merged** and canary passed | the poller kicks the controller with only `shed/rebal` present; the donor arm logs in shadow |
| G2 | recycle steering (shadow) | `scripts/handoff-fire.sh` recycle_repick (:16750-17065); `bin/claude-accounts:3925-3980` | about 70 + tests | canary passed; decision 8 ruled | recycle re-pick rows log `basis=strand` in shadow |

Operator acts, outside any wave: activation 53 (any time), loading `com.reso.lr-balance` after F, and writing `shed/rebal` = shadow, then canary, then on.

---

## 7. Rejected alternatives and why

- **Turning on automated filler (`strand-fill-arm.sh` `on`).** The operator vetoed it on 2026-10-24 (decision 8f9618059700). A stranded point is acceptable; busywork is not. It stays log-only.
- **Putting pre-wall logic inside the reconciler**, i.e. treating usage % or wire readings as a limit fact. This breaks `facts.py:12-13`, would touch files pane 318 is editing, and D2 §2 already ruled it out.
- **Event-first as the main design.** It replaces ps with a registry census inside the reconciler and runs "restricted" passes. That loosens the ps-trust gate and collides with `lr_recon/__main__.py` on the in-flight branch. Its gain is also overstated, because the actuator chain still calls ps about 90 times (`handoff-fire.sh` 71, `lr-lib.sh` 14, `lr-handoff.sh` 5) [R25]. Its 6-hour deadline trigger cannot see next3. Its turn-end catch, instant batch start, readout and statusline data were kept.
- **Minimal as the main design.** Its fill arm inherits the 90% recovery floor, which leaves at least 10 pp per sink. Its 12-hour cap hides next3 until its final hours. It relies on the poller's 600-second tick, the weakest fit for ruling 4. Its claim that a tty carry-forward would have saved tonight's 15 blind passes is wrong: 14 of the 15 were args timeouts [R13]. Its selection fix and plumbing pattern were kept.
- **Turning on `lr-shed.py` as it is.** It moves idle sessions off a nearly full account, which is the opposite of filling a sink. It still has the cold-first ordering defect (`lr-shed.py:480`).
- **Moving idle or cold sessions to fill quota.** They burn about nothing (panes 7 and 67 had 0 output tokens in the last hour [R5]), so the move fills nothing and costs a restart under load.
- **Moving team leads and teammates.** They carry 44% of next's burn, but a lead's graceful exit kills its members. `lr-upgrade.sh:398-420` has a team-ordered procedure, which is left out on blast-radius grounds (decision 9).
- **Retuning router constants to favor the soonest-resetting account for new work.** The 2026-09-22 routing ruling says to change no routing constant. The desk lane is already strand-aware for new sessions.
- **Moving sessions back after a reset.** It is pure restart cost with no quota gain.

---

## 8. Open decisions for the operator

1. **Tonight: move the 12 next sessions to next4 with the command in section 2.** Conviction 70%.
   - (a) Run it now. It fills about 2-3 pp of about 14 (estimated).
   - (b) Send the same set to next3 instead. One restart each, and they keep filling next3 for 54 h, but next4's 14 pp all strand.
   - (c) Do nothing. About 14 pp strand.
2. **From 09:00Z: fill next3 by hand before the rebalancer exists** (recipe in section 2). Conviction 75%.
   - (a) 2-3 hand-run batches of working, non-team sessions from next and next4, stopping once next3 projects past about 95%.
   - (b) Wait for the controller. It will not reach canary before 10-27 12:00Z (estimated).
   - (c) Do nothing. About 71-73 pp strand.
3. **Approve building the rebalance arm (waves A-F) in shadow.** Conviction 85%.
   - (a) Build all of A-F.
   - (b) Build A-D only, as data and plumbing, and decide later.
   - (c) Don't build.
4. **Where the sink stops filling.** Conviction 75% for (a).
   - (a) Aim at a 97% landing with the bias-corrected forecast, bypassing the 90% recovery floor.
   - (b) Keep the 90% floor, which is simpler but leaves at least 10 pp per sink.
5. **Run activation 53 (instant batch start) now.** Conviction 80%.
   - (a) Yes. It is 0 LOC, staged and reversible.
   - (b) Wait for wave F.
6. **Take the owed shadow step for the shed (f259e20643bf, packet 76a584cc935b) after wave D lands the ordering fix.** Conviction 70%.
   - (a) Write `shed/mode` = shadow.
   - (b) Leave it off.
7. **At-the-wall idle fan-out (packet c9a05672e692).** Conviction 60% yes, after pane 318's stale reboot-record fix merges.
   - (a) Create `recon/idle-fanout.on` then.
   - (b) Keep it off. It is reactive and the current wall rate is low.
8. **Reconcile the recycle re-pick record (packet 0223cae3d185).** It reads expired-actioned with "shadow first", but no mode is set and the code default is off [R17]. Conviction 65% for (a).
   - (a) Write `~/.claude/state/repick-held` = shadow.
   - (b) Reopen the packet.
9. **Keep team sessions unmovable.** Conviction 75% keep held.
   - (a) Keep them held.
   - (b) Commission a team-ordered move (teammates first, lead last) through `lr-upgrade`.
10. **Close the duplicate strand-fill packets 03b6485e3a00 and 53b5fe93009b** as re-filings of vetoed 8f9618059700. Conviction 90%.

---

## 9. Receipts

- **R1** Brief, `claude-accounts --fresh` at 2026-10-24 23:54 CDT: next 20 live, 5h 60%, weekly 4%. next4 13 live, 5h 19%, weekly 82% (4.1 h). next3 3 live, weekly 18%. next2 2 live, weekly 2%.
- **R2** This run, `tail -n 40 ~/.claude/logs/account-utilization.jsonl`, ts 2026-10-25T05:26:59Z:
  - next k=19, session 65%, weekly 5%, weekly reset 2026-11-01T03:59:59Z, session reset 06:29:59Z.
  - next4 k=13, session 1%, weekly 83%, weekly reset 2026-10-25T08:59:59Z, session reset 10:09:59Z.
  - next3 k=3, session 2%, weekly 18%, weekly reset 2026-10-27T12:00:00Z.
  - next2 k=2, session 1%, weekly 2%, weekly reset 2026-10-31T11:00:00Z.
- **R3** This run, `cc-lr move --sids 79076bcf,…,06457213 --to next4 --until-idle 1800 --dry-run --verbose` (output in `/tmp/rpt6680-dry.txt`, finished 05:30:51Z): `7 to move · 5 waiting · 1 held · 0 on target · DRY RUN`. Pane 216 2b3becea is `hold:goal-live`; panes 217, 271 and 309 are `wait:mid-turn`, 274 `wait:background-job` and 301 `wait:subagents-in-flight`. EXIT=0, and there is no unroutable line.
- **R4** Now slot, `cc-lr move --from next --to next4 --dry-run --verbose` => `9 to move · 1 waiting · 10 held`. 263 is `hold:lead-with-teammate`; 283, 292 and 320 are `hold:teammate`; 314 (30729231) is `wait:self`. Panes 7 and 67 were idle about 43,400 s.
- **R5** Now slot, `python3 -I /tmp/next-act-6680.py` (assistant output tokens in the last hour, main transcripts): total 237,470. The 13 chosen sessions had 57,456 (24%): warm movers 12,231 and busy rows 45,225. Lead 57,774 and teammates 47,178 (44%). Pane 314 75,062 (32%). Panes 7 and 67 had 0.
- **R6** Now slot, `/tmp/burn-6680.py` over account-utilization.jsonl:
  - next weekly 3.08 pp/h (1 h) and 3.77 (3 h); 5-hour 13.4-18.5 pp/h; 0.55-0.72 pp per session-hour of 5-hour usage.
  - next4 weekly 1.03 (1 h) and 0.69 (3 h).
  - Session-hours per pp: 5-10 (estimated from these rates).
- **R7** Now slot, `claude-accounts --rank general --recovery --src next` => `next4 0.008944, next3 0.000255, next2 0.000042`; stderr `general excluded — next=recovery-5h-thin`.
- **R8** Measure slot, `/tmp/rlscan.sh`, `/tmp/walls.py`, `/tmp/ana.py` and `/tmp/ana2.py` over the 4 projects directories, including `*.jsonl.handed-off`:
  - 121 episodes (100 weekly, 21 five-hour), 117 sessions, 231.3 session-hours.
  - 82 moved before reset; 25 waited past reset (156.8 h).
  - `{('wall:seven_day', True): 100, ('wall:five_hour', True): 21}`.
  - By week: 18, 46, 19, 31, 7.
- **R9** Measure slot, `/tmp/util.py` and `/tmp/util2.py` over 44,623 feed rows: 23 real strand points over the last 6 resets (next 21 on 10-17 and 1 on 10-24; next2 1 on 10-24). Weekly-capped hours: next 73.5, next2 159.4, next3 97.9, next4 25.6.
- **R10** Move-mechanics slot, jq over `~/.reso/limit-recover/move/2*/<sid>.json`:
  - 47 MOVED, 220 NOTMOVED, 13 FAILED, 12 STRANDED (63 of the NOTMOVED are still-busy).
  - `/tmp/mm_act.sh` => post-10-19 MOVED 8; pre-10-19 FAILED 13, MOVED 39, NOTMOVED 82, STRANDED 12.
  - Today's result `wall_s` values: 65, 67, 63, 129, 59, 58.
- **R11** Move-mechanics slot, `/tmp/mm_cache.sh`: first turn after a move wrote 344,023, 397,875, 479,138 and 273,235 cache tokens and read 12,826-14,775.
- **R12** Move-mechanics slot, jq of 2a707a01's events (batch 20261024T170212Z-next2-next-67607): `151 snapshot(s) read, first mid-turn` over 3,600 s, ending NOTMOVED.
- **R13** Counts of 'ps degraded':
  - Signals slot, `grep -c 'ps degraded' recon/events.jsonl` => 92.
  - Minimal design, over events.jsonl and events.jsonl.1: 97 (75 args, 22 tty).
  - Judge, reading the last 16 rows: tonight's 15 in a row ran 22:44:42-22:56:03, 14 args and 1 tty.
  - Signals slot: `<config>/sessions` with `kill -0` took 0.045 s; `kitten @ ls` took 0.073 s at load 294.
- **R14** Slots:
  - `timeout 60 cc-lr plan --from next --to next4` => rc 124; `timeout 250` => rc 0.
  - `timeout 240 cc-lr rotate --list --account next --to next4` => rc 124, no output.
- **R15** Signals slot: strings of the Claude Code 2.1.291 binary show `rate_limits` with five_hour and seven_day `used_percentage` and `resets_at`. `statusline.sh:86-104` and :292-300 have no such field.
- **R16** Slots and judge:
  - `ls ~/.reso/limit-recover/shed/` and `ls recon/idle-fanout.on` => No such file.
  - `cat ~/.claude/state/repick-held` => No such file.
  - `launchctl list` shows no `com.reso.lr-move-kick`.
  - This run: `launchd/staged/com.reso.lr-move-kick.plist` and `docs/activation/pending-activation/53-lr-move-kick-activate.sh` exist.
- **R17** Inventory slot, `~/.claude/autonomy/decisions/*.json`: 8f9618059700 vetoed (2026-10-25T04:50:13Z); c9a05672e692 open; 76a584cc935b open (recheck: fix the selection order before on); 0223cae3d185 expired-actioned, but code `REPICK_HELD_DEFAULT = "off"` at `bin/claude-accounts:3929`.
- **R18** This run, `git diff --stat main...fix/lr-recon-defects`: the 8 files listed in section 6 (267 insertions). Head commit e9c761df1.
- **R19** This run, code checks:
  - `lr-shed.py:480` cold-first sort.
  - `lr-shed.py:519` `plan.get("origin") != "shed"`.
  - `bin/cc-lr:1631` origin allowlist `''|shed`.
  - `bin/claude-accounts:4182` `RECOVERY_W_FLOOR_DEFAULT = 0.10  # excludes weekly >= 90`.
  - `bin/cc-lr:905-930` `cl_target_unroutable` uses `--rank general`.
  - `bin/cc-kqwait` and `hooks/session-beat.sh` exist.
  - Judge also verified `facts.py:12-13`, `census.py:28-31,283`, `statusline.sh:86-104`, `observe.py:804-811,1001-1019` and `lr-move-worker.sh:60,117-137`.
- **R20** `~/.claude/autonomy/research/strand-fill-decision-2026-10-24/REPORT.md:40,44-46`: next reached 99% before its reset after 6 sessions were moved onto it. Filler was VETOED, and real work is to be pointed at the account about to reset.
- **R21** Measure slot, python over `~/.reso/limit-recover/recon/sessions/*.json`: detected-to-ENGAGED n=19, median 81.4 min.
- **R22** Judge, account-utilization.jsonl: next3 weekly went from 4% to 18% between 10-21 12:16Z and 10-25 05:20Z (about 0.16 pp/h). The economics design measured 0.21 pp/h over 24 h.
- **R23** Economics design, `timeout 90 claude-accounts --strand-score`: forecast bias of +15.25 pp at 48 h, +8.45 at 24 h, +5.52 at 12 h and +3.39 at 6 h; 82% agreement at 12 h.
- **R24** This run, `uptime` at 00:29 CDT => load averages 181.84 397.56 558.20. The slots measured 294-991 earlier in the night.
- **R25** Judge scores and the ps call-site counts: `grep -c 'ps -'` gives `scripts/handoff-fire.sh` 71, `lr-lib.sh` 14 and `lr-handoff.sh` 5.

**How this report was produced.** Every command was read-only: `date`, `tail` of the usage feed, `git diff --stat`/`git log`, `sed`/`grep` of code, `uptime`, and one `cc-lr move … --dry-run`. The dry run is allowed by the brief. It ran under `timeout 250` rather than 60 because `cc-lr` planners time out at 60 s under this load [R14]. Its only file write was the redirect to `/tmp/rpt6680-dry.txt`. Nothing in the repo, `~/.claude` or the reconciler state was changed. No move, launchctl, kill or keystroke command was run. The earlier slots' `/tmp` helper scripts and their deviations are recorded in their own evidence.