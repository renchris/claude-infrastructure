# 10 · Proactive: recover before the wall, not at it

Axis: can sessions leave an account **before** it stops serving turns (pre-emptive switch, standby
reserve, router stops placing), and can recovery be ordered cheapest-first with the expensive
relaunches paced by their own latency? Incident: next3 weekly wall, 2026-10-20 ~02:31Z, 9 sessions.

All reads below are read-only. Every number says whether it is **measured** (with the command or
file) or **estimated** (with the method). Times are UTC unless marked.

---

## 0 · Short answer

1. **The wall was predictable 8+ hours ahead, and this happens about 2.7 times a week.** next3
   crossed 90% at 17:57Z, 95% at 23:51Z and 97% at 01:15Z. The server's own `allowed_warning`
   arrived at 01:54Z, and the server rejected at 02:36:59Z. Since 2026-08-11 there have been
   27 weekly walls, and the median one landed **10.5 h before its own reset**. The router's
   deadline-weighted spending pushes the soonest-reset account into an early wall almost every
   week (§1).
2. **The router already stops new fires early. Recycles slip past it.** The last new fire onto
   next3 was at 17:51:26Z (89%). After that the number of sessions on next3 fell on its own from
   19 to 9. **But 3 of the 9 sessions stuck at the wall were put on next3 by a recycle in its last
   4 hours**: 7aae55e1 (pane 38, at 94%), e80b61f4 (pane 55, at 96%) and ceff45c5 (pane 24, at
   100% on the endpoint and 0.99 on the wire, 14 min before the rejection). `recycle_repick`
   compares raw scores against a 4× threshold. It never consults the dispatch floor's "held for new
   work" verdict (§2).
3. **Moving a session early costs nothing in quota when the session is idle.** For a working
   session the cost is bounded and can be made zero by aiming the wall at the reset (§4). Load does
   not have to fall: the move is already keystroke-free (staged successor plus SIGTERM, and
   lr-handoff's precheck reports "load: not gated"). **The one thing that held every move for load
   is a stale copy of the gate in `lr-move-worker.sh:335-358`.** It cost the idle lane 10 min
   (batch 1, then expired) plus 27.7 min (batch 2) in this incident. Today `cc-lr switch` from a
   healthy session goes through that same gate (§3).
4. **A standby quota reserve was not missing.** next4 (13% weekly, k=2), next (37%) and next2 (62%)
   all had headroom at the wall. What was missing was time (lead) and a decision made in advance
   (placement). The placer call timed out at the wall (`rc=124 dur=120.3s load1=253`) and parked
   sessions in WAIT_DATA for about 30 min. A placement computed during the hours of warning removes
   that call from the critical path (§5).
5. **Ordering:** measured costs run from about 100–160 s (a session's own staged recycle) to about
   19 min (an external idle move) to 7–33 min per attempt (reconciler R relaunch, most attempts
   rc=6). So: idle sessions leave in the warning band, recycles re-pick, limited sessions go last.
   Limited sessions should be paced by a window of moves in flight that adapts to their measured
   completion time, not by a threshold on load (§6).

---

## 1 · Was the wall predictable? Yes, by hours, and it recurs every week

### 1.1 next3 on 2026-10-19/20

Measured from `~/.claude/logs/account-utilization.jsonl`: the first row at or above each
threshold, non-stale rows, next3 only. Python scan over the file; output reproduced.

| threshold | first reached | k_native | lead to rejection (02:36:59Z) |
|---|---|---|---|
| 85% | 10-19 15:28:09 | 18 | 11.1 h |
| 90% | 10-19 17:57:09 | 19 | **8.7 h** |
| 93% | 10-19 20:54:10 | 17 | 5.7 h |
| 95% | 10-19 23:51:24 | 12 | **2.8 h** |
| 97% | 10-20 01:15:30 | 10 | 1.4 h |
| 99% / wire `allowed_warning` (util 0.98) | 10-20 01:54:07 | 10 | 43 min |
| 100% (endpoint) | 10-20 02:17:37 | 9 | 19 min |
| wire `rejected` | 10-20 02:36:59 | 9 | — |

next3's weekly reset was `2026-10-20T12:00Z` (`weekly_reset_at` on the same rows). The account
was capped for about **9.4 h** before its own reset. In the same rows next4 sat at 13% weekly
(k=2), next at 35–40% and next2 at 61–62%. Every other account had room.

### 1.2 A naive time-to-wall forecast, backtested on this window

Estimated: TTW = (100 − weekly_pct) / slope over the trailing 3 h and 6 h of rows, evaluated at
fixed times. Lead and reset figures are corrected to UTC.

| eval at | weekly | TTW 3h-slope → wall | TTW 6h-slope → wall | actual | reset in |
|---|---|---|---|---|---|
| 10-19 18:00 | 90 | 22:52Z | 01:25Z | 02:37Z | 18 h |
| 10-19 20:00 | 92 | 00:34Z | 01:52Z | 02:37Z | 16 h |
| 10-19 22:00 | 93 | 08:07Z | 03:52Z | 02:37Z | 14 h |
| 10-20 00:00 | 95 | 07:17Z | 05:51Z | 02:37Z | 12 h |
| 10-20 01:00 | 96 | 04:45Z | 05:39Z | 02:37Z | 11 h |
| 10-20 02:00 | 99 | 02:33Z | 02:50Z | 02:37Z | 10 h |

From 18:00Z onward, every evaluation said "wall well before the reset". The timing error was
±4 h, as the router's own docstring warns (`bin/claude-accounts:5172-5235`, `wall_projection`
MAE; `:5385-5409`, `wk_strand_pp` as a nowcast with no lead-time claim). So the reliable signal
is the binary verdict "walls before reset", plus the level. The exact minute is not reliable.

### 1.3 Every past weekly wall (27 since 2026-08-11)

Measured with the same file, grouping rows by (acct, `weekly_reset_at` hour) and keeping the
windows that reached 100.

- Reset minus wall: 0.6 / 0.9 / 2.2 / 2.6 / 4.1 / 5.9 / 7.2 / 8.8 / 9.3 / 9.5 / 9.6 / 9.7 / 10.3 /
  **10.5 (median)** / 11.2 / 11.4 / 11.5 / 13.3 / 14.9 / 24.5 / 37.7 / 55.6 / 55.7 / 56.8 / 63.3 /
  76.1 / 106.4 h. 23 of 27 walls came more than 2 h before reset.
- Lead from 90%: min 1.5 h, median 11.3 h. From 95%: min 0.2 h, median 3.0 h. From 97%: min 0.1 h,
  median 1.9 h. The fastest wall (next3 09-22) went 90 → 100 in 1.5 h, so a level trigger alone
  has a floor of about 1.5 h at 90%.
- k_native at the wall, where recorded: 15 (next3 10-13), 13 (next2 10-17), 14 (next4 10-18),
  10 (next3 10-20).
- `claude-accounts --stranded --hours 1008` (read-only history) ⇒ 19 of 23 closed windows reached
  100%. That is about **2.7 walls a week across the fleet**, each with 10–15 sessions resident.
- Wire `allowed_warning` → `rejected` lead over 18 historical transitions: 6–252 min, median about
  49 min (same file, wire status transitions). That is too short to be the only trigger, but it
  is useful as the last-chance signal. Note that the wire is only probed at endpoint ≥ 99
  (`WIRE_NEAR_WALL = 99.0`, `bin/claude-accounts:1803`).

**Conclusion.** The weekly wall is a scheduled, recurring event with hours of warning. Recovering
at the wall is a choice to act at the worst moment. The rest of this note is about not making that
choice.

---

## 2 · What the router already does before the wall, and the hole

### 2.1 New fires: held at 90% (works)

- `DISPATCH_W_FLOOR = 0.10` (`~/.claude/accounts.json` router block; default `bin/claude-accounts:6692`).
  `dispatch_floor_row` (`:6735-6792`) marks an account under 10% headroom as **held for new work**
  unless its quota is forecast to die unused (strand rescue). `_dispatch_partition` (`:6816-6851`)
  then demotes it below every roomy account.
- Measured: `account-assignments.jsonl` holds no next3 assignment after `2026-10-19T17:51:26Z`
  (`src=handoff-fire`, weekly 89%). From 18Z to 04Z the fires went to next, next2 and next4.
- The desk lane left next3 earlier. `route.jsonl` shows `desk -> next2` from 19:10:51Z (DESK_W_FLOOR
  0.15 ramp).
- Measured: next3 `k_native` fell from 19 (17Z) to 9 (02Z) through natural attrition. The floor
  halved the number of sessions exposed to the wall without moving anything.

### 2.2 Recycles: not held (the hole)

Measured from the `~/.claude/logs/handoffs.jsonl` rows with `"account":"next3"`, gate `recycle`:

| recycle intent | pane | next3 weekly | successor sid (first transcript entry) | at the wall? |
|---|---|---|---|---|
| 19:45:35Z | 7 | 92% | — | no |
| 21:39:08Z | 63 | 93% | — | no |
| 22:30:21Z | 38 | 94% | **7aae55e1** (22:37:08) | **yes**, cohort member, pane 853:38 |
| 23:59:59Z | 55 | 96% | **e80b61f4** (00:01:44) | **yes**, cohort member, pane 853:55 |
| 02:22:48Z | 24 | 100% endpoint / 0.99 wire `allowed_warning` | **ceff45c5** (02:24:00) | **yes**, idle-batch member, pane 24 |

Successor identity comes from the first user/assistant entry in each transcript after 20:00Z (scan
of `~/.claude*/projects/*/<sid>.jsonl`) and the pane numbers in the cohort and move-batch files.
**3 of the 9 sessions stuck at the wall were put there by a recycle in the last 4.1 h.** Each of
those recycles had already paid for a full relaunch, so sending it to another account would have
cost nothing extra.

Why the recycle stayed. `recycle_repick` (`scripts/handoff-fire.sh:15962-16130`) re-picks only
when (a) the incumbent is in the exclusion map, or (b) line-1 score ÷ incumbent score ≥
`repick_ratio` (4.0). The dispatch floor's *held* verdict does not appear in the exclusion map, and
`--rank` stdout carries only `name score`.

Estimated by evaluating `score_general = w_rem / (T − 0.5)² × soft` on the logged rows at 22:30Z:

- next3: w_rem 0.06, T ≈ 13.5 h, KF ≈ 0.5 (k=12 vs KMAX 24) ⇒ ≈ 1.8e-4.
- next4: 0.87, ≈ 130 h, KF ≈ 0.92 ⇒ ≈ 4.7e-5.

Either next3 is held and demoted, so line 1 is a roomy account and the ratio is ≈ 0.26 < 4
("stays — does not beat by 4×"), or it is line 1 itself ("stays — the router's own top pick").
Either branch keeps it. The exact branch is **not on disk**: the "stays" line goes only to the
pane's stderr (open question 4). At 02:22, endpoint 100 / wire 0.99 gives `weekly_headroom` 0.01,
which is above `WEEKLY_FLOOR` 0.005, so next3 was not even excluded.

**Moving recycles off is strand-neutral by the floor's own definition.** "Held: on-pace" means the
account's remaining week is consumed by the sessions already on it (`dispatch_floor_row`: spare <
need). A recycle is a new session start, so the held verdict is the right rule for it.

---

## 3 · Shedding early does not need low load, and today one gate makes it need low load

### 3.1 The move is keystroke-free

Measured from `~/.reso/limit-recover/move/20261020T030423Z-next3-next2-15173/ceff45c5-…handoff.log`:

```
lr-handoff: precheck load: not gated (the relaunch is staged in the pane, keystroke-free)
→ successor staged for ttys039 (resume): … when claude exits — no keystrokes
→ exit: SIGTERM to claude pid 77931 (session ceff45c5) — at rest with our successor staged, so nothing is typed
```

`handoff-fire.sh:13831-13837` (Wave S, e2d0cee07, 2026-10-19 23:12Z) states that a staged move is
not held for load. The commit-time hold is skipped for a staged successor too
(`hf_recycle_load_gate`, `:4141-4150`). A self-recycle with a staged successor completed in 100 s
at 02:22–02:24Z, and in 160 s at 00:00–00:02Z (handoffs.jsonl `elapsed_s` 143 and 160, "recycled
in place; a real assistant turn within 0s"). Load then was 12–33/core, measured from
capacity-alarm.jsonl for hours 00Z and 02Z.

### 3.2 But the move lane still waits for load

`scripts/limit-recover/lr-move-worker.sh:299-358` (`load_over` / `load_wait`) holds every worker
while load per core is above 20, with no staged exemption. Its rationale comment (`:299-301`, "handoff-fire
holds every resume recycle, which a move always is") was made false by Wave S. Measured
(batch events.jsonl):

- Batch `…024813Z…` (4 idle sessions): every worker ended `HELD:load — 33–38/core … for 605–613 s;
  nothing touched`.
- Batch `…030423Z…`: load-wait from 03:06:39 to 03:34:19 (**27.7 min**). Meanwhile 3d1d988a and
  3e929a81 **became limited** (`NOTMOVED: became-limited … Recover it: cc-lr recover`). Idle
  sessions turned into expensive limited ones while they waited.

`cc-lr switch` from a healthy session, while the reconciler is live, hands off to this same move
lane (`bin/cc-lr:2109-2135`: "the reconciler is live and has no switch lane — handing this session
to the move lane"). So **today a pre-emptive self-switch at 95% would be held by the same 20/core
gate**.

### 3.3 Load before the wall had troughs, but the design must not count on them

Measured from `~/.claude/logs/capacity-alarm.jsonl`, `load_per_core` by hour:

| hour | median /core | share of samples ≤ 20/core |
|---|---|---|
| 10-19 18Z | 31.2 | 0.00 |
| 20Z | 10.6 | 0.96 |
| 21Z | 6.9 | 1.00 |
| 22Z | 10.0 | 0.94 |
| 23Z | 16.5 | 0.62 |
| 10-20 00Z | 14.1 | 0.79 |
| 01Z | 19.4 | 0.62 |
| **02Z (wall)** | **25.4** | **0.17** |
| 03Z | 23.4 | 0.42 |

The 8 h before the wall offered many windows where even today's gate would pass. The wall hour was
the worst hour in the series. That fits recovery adding its own load: R relaunches, `ps` at
40 s+, `--place` at 120 s. Under the operator's premise the trough is luck, not design. The point
of the lead time is that actions are already ungated once the stale copy is removed (§3.2), and
that hours of slack absorb slow actuation (about 19 min per idle move measured at about 23/core:
actuate 03:35:28 → actuated 03:54:35).

---

## 4 · The quota cost of leaving early, and how to make it zero

- **Idle sessions burn nothing.** Moving one off a wall-bound account strands nothing. 4 of the 9
  sessions at the wall were idle (batch `…024813Z…`). They were not idle for hours: their last
  turns before the wall were 01:35–02:29Z (transcript scan). That is why the shed has to be
  continuous through the band, not a single sweep.
- **Working sessions.** If all 9 had left at 97% (01:15Z), next3 would have stranded about 3 pp.
  Estimated using the operator's own figure of "~$50 a week" per plan (`bin/claude-accounts:3890`
  comment, operator ruling 2026-10-17), that is about $1.5. The fleet cost is lower again, because
  the same work burns on an account that strands anyway this week (next4 at 13% with ~5 days left;
  next4 stranded 26 pp in its 10-04 window per `--stranded`).
- The operator ruled that exhausting the weekly limit is the bottom line (`bin/claude-accounts:3890-3896`;
  `docs/research/routing-policy-ruling-2026-09-22.md` §1). So the design should **aim the wall at
  the reset**, not trade quota for ease:
  - Each pass, per account, compute `TTW = (100 − wp) / max(ewma, flat, 1h-slope)`. The rows
    already carry `burn_wk_ewma_ph`, `burn_wk_flat_ph`, `weekly_reset_h` and `wire.7d_util`
    (`apply_burn`, `bin/claude-accounts:4828`).
  - **Band entry:** wp ≥ 90, or TTW ≤ 6 h, while TTW < `weekly_reset_h − 1 h`.
  - In the band: shed every idle session (quota-free). Shed working sessions at their turn boundary
    only until the remaining burn lands the wall within about 1 h of the reset. Estimated for this
    incident: at 22:00Z next3 had 7 pp and 14 h left, so it needed ≥ 0.5 pp/h against ~1.2 pp/h
    measured. Keeping about 4 of ~10 working sessions and shedding about 6 over 14 h is one move
    every ~2 h.
  - A wall that still lands just before the reset is cheap. The reconciler's WAIT_RESET parks
    limited sessions until a near reset (the 31f4242e0 fix was about a 9 h-away reset, not a
    1 h one), so they resume on the same account with no move.
- This is the missing half of a mechanism that already exists. The strand rescue lifts a thin
  account when quota would die unused (`dispatch_floor_row` → "lifted"). Nothing sheds when the
  account is forecast to wall early. `wk_strand_pp` already clamps that regime and calls it a
  "wall trajectory" (`:5397-5402`), but only for display.

Choosing which sessions stay to burn the last points: keep the ones that are cheapest to recover
at a wall (empty composer, no teammates, no background jobs, autonomous workers). Shed first the
ones that are expensive at a wall (`HOLD-COMPOSER`, team leads, `bg_work`), because those were the
holds in this incident (769b7294: four A attempts ending `rc=6 → HOLD/HOLD-COMPOSER`).

---

## 5 · Standby reserve and pre-placement

- **Quota reserve: not the constraint.** Measured at the wall (`account-utilization.jsonl` 02Z–04Z):
  next4 13% weekly / 0% 5h / k=2, next 37–40%, next2 61–62% with 5h 5–11%. The recovery floors
  (`RECOVERY_W_FLOOR 0.10`, `RECOVERY_S_CEIL 0.60`) were met by 3 accounts. Both idle batches were
  admitted to next2 (`admit.json: target_auth ok`). The deadline-weighted router already leaves the
  latest-reset account (next4) nearly unused as a de facto reserve. Adding a formal quota reserve
  would buy nothing in this incident.
- **Decision reserve: missing.** Measured from `recon/events.jsonl`: 02:36:27
  `place lane=general rc=124 cause=timeout … dur=120.3s timeout=120s load1=253`, and timeouts again
  at 02:53, 03:06, 03:49 and 04:08. The cohort status shows 3d1d988a and 3e929a81 in
  `PRE-MOVE/WAIT_DATA` at age 2118 s. `--place` is cache-only (`get_data(max_wait=0)`,
  `bin/claude-accounts:6512-6513`), but the Python process itself starves at load 250–350 (timeout
  scaling `plan.py:296-302`).
- **Pre-placement:** compute the target while in the band, when there are hours to spare. Store it
  in the record or plan. At the wall, accept it if a cheap file read confirms it: the
  `capped.latest_usage` tail read of account-utilization.jsonl, `lr_recon/capped.py:56-89`, which
  must show the target still under the recovery floors and not capped. Only on a mismatch fall back
  to `--place`.

---

## 6 · Ordering: cheapest first, expensive paced by their own latency

### 6.1 Measured costs per path in this incident

| path | example | wall-clock | outcome |
|---|---|---|---|
| self staged recycle (subject alive, turn boundary) | pane 24 at 02:22:48 → engaged 02:24:32 | **~100 s** (handoffs.jsonl `elapsed_s` 143 incl. intent) | engaged |
| external idle in-place move (move lane, no prompt) | ceff45c5, 9240c6a9 | load-wait 27.7 min, then actuate → actuated **19.0 min**, proof +4 min | MOVED 2/2 that were still idle |
| reconciler R (relaunch + owed turn) | d7eb73d2, 7aae55e1, db755a94, e80b61f4 | spawn → exit **7–33 min** per attempt; 8 R spawns 02:46–04:09 | first rc=0 at 04:10:29 (e80b61f4, its 2nd R); 2 rc=0 by 04:16 |
| reconciler A (prompt into a held composer) | 769b7294 | 15 min, then 4 attempts | each `rc=6 → HOLD/HOLD-COMPOSER` |

Source: `recon/events.jsonl` `spawn`/`exit` rows 02:46–04:19Z, and the batch events files.

### 6.2 Proposed order

1. **Before the wall (band):** recycle re-pick (free), then idle no-prompt moves, then
   working-session sheds at their turn boundary per §4. These run on the move lane with the staged
   successor and no load gate.
2. **At `allowed_warning` (wire):** the last-chance sweep of any session still idle, with
   pre-placed targets.
3. **At the wall:** only sessions that were mid-turn remain. Admit R/A relaunches through a
   **window of moves in flight sized by measured completion time**, in place of load thresholds.
   Start with a window of 2. Grow it by 1 when a relaunch proves engagement under a target latency
   (e.g. 10 min). Halve it on rc=6, a timeout or a rollback. Never let it fall to 0: one admission
   always stays in flight. This is the shape the operator's premise asks for. It needs no load
   reading, reacts to what the box actually delivers, and cannot starve. The reconciler already
   counts in-flight work (`admit-refused … restore-r (active 18 + in flight 4 + 1 vs R 22)`,
   events 03:15:41), so this replaces a threshold rather than adding a subsystem.

---

## 7 · Levers (ranked by value/effort)

See the structured summary for mechanism, risk and evidence per lever:

- L1 recycle re-pick honours the held verdict
- L2 drop the move worker's stale load wait for staged moves
- L3 wall-ahead shed controller (aim the wall at the reset)
- L4 pre-placement
- L5 idle fan-out on band entry (`LR_IDLE_FANOUT` is off by default, `lr_recon/__main__.py:686`, `census.py:281`; the idle batch in this incident was requested by hand from pane 35 at 02:48:13Z, 16 min after the cohort opened)
- L6 latency-paced in-flight window for R/A at the wall

**Rejected:**

- **Retuning `URGENCY_EXP` / `WEEKLY_FLOOR` to spread burn.** Operator rulings 2026-09-22 (change no
  routing constant, 92%) and 2026-10-17 (exhaust the week). The shed controller reaches the same
  outcome without changing which account burns first.
- **A Stop-hook nudge telling sessions to self-switch.** VOLUNTARY_ACCOUNT_SWITCH.md's roster
  explicitly chose "NOT a Stop-hook nudge". An outside shed via the move lane does the same thing
  without spending model turns.

---

## 8 · Open questions

1. How burn per session is distributed (`k_work` against pp/h per account) during the band. Without
   it, the number of working sessions to shed is a proportional estimate.
2. Is a staged move reliable above ~30/core? The two staged moves here ran at about 23/core. None is
   on record at 35+/core.
3. Why did the move lane's actuation take 19 min with load ungated (bundle 03:36:43 → resume-debt
   03:54:18)? The handoff log has no per-phase timestamps.
4. The `recycle_repick` "stays" decision is not written to disk. Only re-picks are. The exact branch
   in §2.2 is estimated from the formula, not read.
5. Does the operator accept a bounded strand (≤ 100 − band%) as a fallback when the shed controller
   cannot land the wall at the reset (burst walls: 1.5 h from 90%)?
6. Could a StopFailure-triggered self-move remove the external driver even at the wall? The hook
   fires in-session at p50 0 s (`docs/plans/LIMIT_DETECT_100P.md:101`), and moves already exit by
   SIGTERM with a staged successor. This is a hypothesis. Nothing here tested it.

---

## Skeptic review

Reviewer: an adversarial skeptic pass, made read-only on 2026-10-20 at about 04:30–04:55Z. Code was
read at worktree HEAD 60c87719f. `git diff --stat 60c87719f main` shows that `handoff-fire.sh`,
`lr-move-worker.sh`, `bin/cc-lr` and `bin/claude-accounts` are unchanged on main (20368fc85).
`lr_recon/admit.py`, `plan.py` and `settle.py` did change, so lr_recon reads below are from main
unless they say otherwise. The ad-hoc scan scripts are `/tmp/skeptic10_scan.py`,
`/tmp/skeptic10_ttw.py` and `/tmp/skeptic10_fp.py`.

### Cross-cutting facts this review found (they bear on several verdicts)

- **X1. The next gate after load is the kitty socket, and it was failing in the same minutes.**
  The R attempts in this cohort fail inside lr-handoff's precheck. The move lane uses the same
  precheck. Measured with `grep 'precheck verdict' recon/actlogs/*`:
  - `d7eb73d2.1.R` ⇒ `HELD:pane:resolver-unavailable` ("no terminal control socket answered at all").
  - `7aae55e1.1.R` and `db755a94.2.R` ⇒ `HELD:composer-unreadable`.
  - `db755a94.1.R` ⇒ "recycle ABORTED: the terminal did not answer the watcher's pane probe".
  - `e80b61f4.1.R` and `7aae55e1.2.R` ⇒ `HELD:unknown` (handoff-fire rc=2).
  - Every `rc=6` in events.jsonl is one of these precheck refusals (`lr-handoff.sh:657-706`,
    "the precheck refused (rc 6)").

  So "load: not gated" does not mean "load-proof". Batch 2's precheck did find kitty answering
  (`kitty_probe: answers … tries=1`, about 03:36Z). The R attempts at 02:46–03:12Z did not.
- **X2. The two WAIT_DATA sessions were held by the zero-human gate, not by `--place`.**
  - Measured in `recon/sessions/{3d1d988a,3e929a81}.json`: `origin: hook`, `plan_only: True`.
  - Measured: `ls ~/.reso/limit-recover/recon/autorecover.on` ⇒ No such file. `zero_human()`
    (`__main__.py:217-223`) therefore returns False, and `census.py:349` makes every hook, census
    and fanout record plan-only.
  - In act mode, `__main__.py:1008-1011` drops any placement that names an account for a plan-only
    record. So the record keeps its old substate.
  - `--place` answered rc=0 at 03:55:55, 03:59:25, 04:11:08, 04:12:27, 04:13:39, 04:15:25,
    04:29:52, 04:32:11 and 04:33:14 (events.jsonl), and both records stayed
    `WAIT_DATA since 03:43:17`.
  - The 04:31:23 cohort plan holds only db755a94 after the 04:29:52 pass with n=3. That fits the
    other two having been placed and then filtered out.
  - `cc-lr status --cohort next3-7d-1792497600` at about 04:52Z ⇒ both still `PRE-MOVE/WAIT_DATA
    age 3012s`, "next: the reconciler retries". That label is misleading. Nothing retries a
    plan-only record until a human re-runs cc-lr (`refire … by=cc-lr` at 04:38:45).
- **X3. Parking at a near reset covers 15 minutes, not 1 hour.** `plan.py:36 EPS_STAY_S = 900`.
  `plan.py:200-210` cites the "operator ruling 2026-10-13: a session on a rejected account moves".
  A limited session whose reset is more than 15 min away is placed and moved if any target has room.
- **X4. An AIMD in-flight window already exists.** `admit.py:304-310` `BootSlots` starts at 6,
  adds 2 after a fast wave, halves on a boot over 45 s, and has a floor of 2. It is wired at
  `__main__.py:97`, since 5a144f2e6 ("…drip, boot aimd", 2026-09-29).
- **X5. The CPU brake already has an anti-starvation floor.** `admit.py:41-42,143-150`: `cpu_ok` is
  true once 20 s have passed since the last admission (`CPU_FLOOR_S = 20.0`, since 2026-09-29).
  Measured over the admit-refused rows after 02:23Z: probe-error 8, cpu 2, restore-r 1.
  7aae55e1 was refused `cpu` at 02:54:18 and spawned at 02:54:50. The brake did not refuse every
  pass in this incident. The binding admission refusal was the 30 s probe bound (main's ed5614054
  renames it `probe-timeout`).

### Key findings

| # | claim (short) | verdict | evidence |
|---|---|---|---|
| F1 | Wall predictable 8+ h ahead; 90% 17:57Z … rejected 02:36:59Z; reset 12:00Z | **CONFIRMED** | Measured with `/tmp/skeptic10_scan.py next3`. Every threshold time matches to the second: 85% 15:28:09, 90% 17:57:09 (k 19), 95% 23:51:24, 97% 01:15:30, 99%/`allowed_warning` 01:54:07, 100% 02:17:37, `rejected` 02:36:59. `weekly_reset_at` is 2026-10-20T12:00Z. The trailing-slope backtest (`/tmp/skeptic10_ttw.py`, least-squares) says "wall before reset" at every evaluation from 18Z on. Its timing error is somewhat larger than ±4 h: at 00:00Z both slopes forecast 07:09–07:29Z against 02:37Z, about 4.5–5 h. |
| F2 | 27 walls since 08-11 (~2.7/week); median 10.5 h before reset; lead from 90% median 11.3 h | **CONFIRMED** (minor drift) | Measured with `/tmp/skeptic10_scan.py walls`, grouping by reset rounded to the hour: n=27, and the reset-minus-wall list is identical to §1.3 (median 10.5). Lead from 90%: median 11.3 h. Lead from 95%: median 2.8 h (doc 3.0). `claude-accounts --stranded --hours 1008` ⇒ 20 of 23 closed windows at 100% (doc 19; next4's 10-04 window walled and then reads 74%). Wire `allowed_warning` → `rejected`: my first-warning method gives 16 valid transitions, range 6–252 min, **median about 72 min** (doc about 49). The conclusion is the same. Context the doc omits: 8 of 27 walls came more than 24 h before reset (24.5–106 h), and 8 of 27 had less than 3 h of lead from 90%. Measured with `/tmp/skeptic10_fp.py`: 26 of 32 closed windows that reached 90% walled, and all 6 that did not were in August. Band precision is high. |
| F3 | Router stops fires at 90%; 3 of 9 stuck sessions were put on next3 by recycles at 22:30 / 23:59 / 02:22 | **CONFIRMED** | `account-assignments.jsonl` has no next3 row after 2026-10-19T17:51:26 (src handoff-fire). `handoffs.jsonl` holds recycle-intent rows on next3 for panes 38 (22:30:21), 55 (23:59:59) and 24 (02:22:48), each ending with `recycle-successor-claimed`/`recycle-engaged` and `cfg …/.claude-tertiary`. Cohort members 7aae55e1 (pane 853:38) and e80b61f4 (853:55) and idle-batch member ceff45c5 (pane 24) match by pane. `k_native` was 19 at 18Z and 9–10 at 01–02Z. |
| F4 | `recycle_repick` keeps a near-wall incumbent: 4× ratio, held is not exclusion; 0.01 > WEEKLY_FLOOR 0.005 | **CONFIRMED** (stronger than "medium") | `handoff-fire.sh:16016-16084`: it stays if line 1 equals cur, or if best/cur < rr. `bin/claude-accounts:6885-6893`: `ranked()` applies `_dispatch_partition`, which moves HELD rows to the bottom without dropping them (`:6816-6851`). **New direct evidence:** the `recycle-repick` row at 2026-10-19T18:36:54Z has `ranked: next 0.000185 > next2 0.000105 > next4 0.000045 > next3 0.000166`. next3 is last despite the second-highest score, so it was held. best/cur ≈ 1.1 < 4, so the branch is "stays — does not beat by 4×". The doc's estimate of 1.8e-4 matches the measured 1.66e-4. At 02:22 the next3 rows read endpoint 100 / wire 0.99 `allowed_warning` (`account-utilization.jsonl` 02:17:37 and 02:26:48). `weekly_headroom` = 0.01 (`:1909-1919`), which is above `WEEKLY_FLOOR` 0.005 (`accounts.json`). |
| F5 | Moves are keystroke-free and ungated downstream; only lr-move-worker's W2c wait held the idle moves; cost 10 + 27.7 min; 2 idle sessions became limited | **CONFIRMED as stated; implication WEAKENED** | `lr-move-worker.sh:299-358` has no staged exemption. `handoff-fire.sh:13823-13837` and `:4141-4150` exempt a staged successor. ceff45c5's handoff.log contains "precheck load: not gated" and "exit: SIGTERM … nothing is typed". Batch 1: four `HELD:load` results at 605–613 s, 33–38/core. Batch 2: load-wait 03:06:18→03:34:19. The limit records were stamped at **03:13:21Z (3e929a81) and 03:19:58Z (3d1d988a)** (`close.death` in recon/sessions), inside that wait. But "the only thing" is true only because the workers never reached the next gate. The R attempts at 02:46–03:12Z failed on the kitty socket (X1). Batch 1 un-gated at about 02:50 would have met the same precheck, so "would have prevented 2 limits" is plausible, not shown. Even ungated, actuation took 19.1 min: actuate 03:35:28, bundle 03:36:43, watcher armed 03:50:26 (log-name epoch), exit-committed +172 s, resume-debt 03:54:18. That is about 15 min before handoff-fire armed at all. |
| F6 | `cc-lr switch` while the reconciler is live goes to the same move lane and its 20/core gate | **CONFIRMED** | `bin/cc-lr:2109-2134`: `lr_recon_live` ⇒ "handing this session to the move lane" ⇒ `LRU_SELF_SID=… cmd_move --until-idle`. `lr-move-worker.sh:355-358` runs `load_wait` for every worker. |
| F7 | Load had troughs (0.96/1.00/0.94 ≤20/core at 20–22Z); the wall hour was the worst | **WEAKENED** ("worst hour" REFUTED) | Measured by bucketing `capacity-alarm.jsonl` `load_per_core` by hour. Shares at 20Z/21Z/22Z: 0.96 / 1.00 / 0.94, confirmed. 02Z: median 24.5, share 0.17. But **18Z: median 31.0, share 0.00, and 12Z: 28.3 / 0.00 were worse than 02Z**. The doc's own §3.3 table shows 18Z at 31.2 / 0.00. Sampling also thins under load: 14–19 samples/h in loaded hours against 35–45 in trough hours, so hourly medians under-weight load. Under the operator premise the troughs are irrelevant either way. |
| F8 | A quota reserve was not binding (next4 13%, next 37%, next2 62%); placement time was missing (`--place` rc=124, about 35 min WAIT_DATA) | **WEAKENED** | The reserve half is confirmed. At 02:36:59: next 36% (5h 5%), next4 13% (k 2), next2 60% (k 15), all inside `RECOVERY_W_FLOOR` 0.10 and `RECOVERY_S_CEIL` 0.60. The timeouts are confirmed at 02:36:27 (load1 253), 02:53:20, 03:06:30, 03:49:05 and 04:08:17, and again at 04:18, 04:20, 04:25 and 04:40. But `--place` also answered rc=0 fourteen times between 02:43 and 04:33. The 2118 s+ WAIT_DATA of 3d1d988a and 3e929a81 is the plan-only drop (X2), not the placer. What `--place` itself provably cost was the first pass for d7eb73d2, 7aae55e1 and db755a94: timeout 02:36:27, answered 02:43:15, about 7 min. After that came probe-error refusals and 7–33 min R attempts. |
| F9 | Costs differ about 10×: self recycle about 100–160 s; idle move about 19 min; R 7–33 min, 2 rc=0 of 8 | **WEAKENED** | Self recycles on next3 (`handoffs.jsonl` intent→engaged): pane 24 104 s, pane 55 144 s, **pane 38 22:30:21→22:37:36 = 435 s**. Pane 38 logged 2× `nudge-held`, `/exit retyped … CR sent`, and a bg-work dialog answered by keystroke. The self path is not keystroke-free: it types `/exit` and dialog answers. R: 8 spawns 02:46–04:09 and rc=0 twice (e80b61f4 04:10:29, 7aae55e1 04:16:49), confirmed. But d7eb73d2's second R (exit "code unknown" 03:54:17) also landed: `stale … live on .claude-next already` at 04:09:59, and the cohort reads ENGAGED. That makes 3 of 8. Spawn→exit includes reconciler observation lag: two exits were logged in the same second, 03:19:19, while `d7eb73d2.1.R.log` last changed at about 03:12Z. The about 10× ordering still holds. |
| F10 | Shedding early costs zero for idle sessions and about 3 pp if all left at 97%; aiming the wall at the reset drives it to about zero | **WEAKENED** | "Idle burns nothing" is contradicted by this incident: 2 of the 4 idle-batch members started turns and hit the wall about 40 min later (F5). Idle now does not mean zero future burn, and an over-shed of idle sessions can strand. "Aim at the reset" keeps burners that still wall up to about 1 h before the reset, plus 4–5 h of forecast error. Under X3 those burners are moved at the wall, not parked. Zero quota cost and zero at-wall moves are a trade-off; the controller cannot get both. The $50/week ruling is verbatim at `bin/claude-accounts:3890-3892`. |

### Levers

| lever | verdict | evidence and the reason it does or does not hold under permanent 15–40/core |
|---|---|---|
| L1 recycle re-pick honours the held verdict | **CONFIRMED** | The mechanism and the hole are proven (F4, including the 18:36:54Z ranking). The existing re-pick already handles moving accounts, so effort S is plausible. Caveats: (a) `--rank` runs under `perl alarm 25` (`handoff-fire.sh:15997`). A timeout is fail-soft "stay" and is not logged. The 18:36:54Z re-pick shows `--rank` answering inside 25 s with 18Z at a median of about 31/core. Nothing is measured at 35–40/core, so coverage at the worst moments is unproven. (b) "Strand-neutral by definition" is approximate. The held verdict's spare includes the predecessor's burn, and the successor continues that burn, so moving it removes burn from the held account. This is bounded by one session's rate (0.42 pp/h p75, `:6695`). (c) The §14 comment (`handoff-fire.sh:15951-15956`) calls pressure-short-of-exclusion a routing-policy judgment. Get an operator ruling. |
| L2 drop W2c load wait for staged moves | **WEAKENED** | The code fact and the stale rationale are confirmed (F5). It is the right change and low-risk, because Wave S already ungates the same path downstream. But "idle sheds proceed at any load" overclaims: (a) the kitty socket reads in the same precheck failed at 02:46–03:12Z (X1); (b) the SIGTERM exit needs at-rest proven (`handoff-fire.sh:4023-4024`), otherwise `/exit` is typed, and `hf_recycle_load_gate` lets a typed `/exit` through whenever a successor is staged (`:4146`), while typing is measured clean only to about 32/core (`:4111-4113`). That is a second unmeasured path at 35–40/core besides the staged-claim one the doc names; (c) about 19 min of actuation per move remains. |
| L3 wall-ahead shed controller | **WEAKENED** | Band entry is sound (26/32 windows at ≥90% walled) and the median lead is ample. Problems: (a) the ledger rows do not carry `burn_wk_ewma_ph`, `burn_wk_flat_ph`, `weekly_reset_h` or `wk_strand_pp`. All are null on every next3 row on 10-19/20 (`/tmp/skeptic10_ttw.py`). They exist only in-process, from `apply_burn` (`bin/claude-accounts:4828`), in the same Python that timed out at 120 s, so the controller must derive them itself. (b) The "shed expensive-at-wall first" set is exactly what the move lane holds at any time: `HELD:team` unconditionally (census.py:9-11, decision 4, cross-account team move is v2), bg_work until the job ends (decision 2), and a pasted draft as `HELD:draft` (`lr-move-worker.sh:292`). These can only be retried across the band, never shed first. (c) The near-reset residual is moved, not parked (X3). (d) Reconciler-originated sheds are plan-only without `recon/autorecover.on` (X2). (e) 8 of 27 walls came 24–106 h before reset, where "aim at the reset" means keeping almost no burners. Shadow first is right. |
| L4 pre-placement in the band | **WEAKENED** | The cheap check is viable: `capped.latest_usage` (`lr_recon/capped.py:59-89`), and the ledger stayed fresh through the incident with 32–36 non-stale rows/h at 00–03Z (measured). But the cited benefit (5 timeouts, about 35 min WAIT_DATA) is mostly misattributed (F8/X2). The proven `--place` cost was about 7 min on the first pass. The same tail read is available at the wall, so the band pre-computation is not what removes `--place`; a placement computed in-process from the tail would. |
| L5 idle fan-out on band entry | **WEAKENED** | Evidence confirmed: the cohort opened at 1792463515.97 = 02:31:55Z, and pane 35 requested the batch at 02:48:13Z, 16.3 min later. Not just a flag flip: (a) fanout-origin records are plan-only unless `recon/autorecover.on` also exists, and it does not (X2, `types.py:33`, `census.py:349`). That is a zero-human actuation decision (D1.9). (b) Eligibility needs an affirmatively empty composer read through kitty each pass (`__main__.py:686-693`, `census.py:296-297`), and that read is the one that failed under load (X1), which yields WORKING, not eligible. (c) It needs a capped fact (`census.py:281`), so band keying needs a new synthetic fact. Effort M is fair. |
| L6 latency-paced in-flight window for R/A | **WEAKENED** (its comparator is REFUTED) | "Cannot starve, unlike the CPU brake in front of the drip" is false: the brake opens after 20 s (X5), and only 2 of 11 refusals were `cpu`. An AIMD window on boots already exists (X4). The measured R failures are kitty-socket prechecks and `HELD:unknown` (X1). "Halve on rc=6" would throttle on a terminal fault that a smaller window does not fix. A 10-min engagement target sits inside the reconciler's own observation lag (F9). What it would genuinely remove is the 30 s probe (8 refusals, 1–8 min each: 03:35:33→03:43:17, 03:51:07→03:53:21). That needs naming as "replace the probe", not "replace the brake". |

### Net

The direction holds: act in the band, ride recycles, and remove the stale move-lane load wait.
Recycle re-pick (L1) is the one lever with no new dependency. Everything that moves sessions
proactively (L2, L3, L5) reaches **the kitty remote-control socket** as its next gate under load (X1).
The reconciler-driven variants (L3, L5) also reach the **zero-human gate** (X2). This note has
measured neither of these under 35–40/core. Both need to be on its open-question list beside the
staged-claim one.
