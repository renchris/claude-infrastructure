# Lead observations during the 2026-10-20 next3 recovery

Measured by the session that drove the recovery, 02:36Z-04:40Z. Each item names its evidence.

## Defects found and fixed during the run

| # | Defect | Effect | Fix |
|---|---|---|---|
| 1 | `plan.apply()` turned a `wait-data` placement (placer timeout, eta unknown) into `WAIT_RESET` with the source's reset as ETA, however far; `movers()` skips `WAIT_RESET` until that ETA | panes 48 and 55 parked until next3's weekly reset, 9 h out | `31f4242e0` |
| 2 | a post-transplant rollback (`lr-handoff` NOTMOVED after `HELD:unreachable`) left the record `PRE-MOVE` with substate None; nothing re-drove it, `RECON-DEFECT` every pass | pane 41 stranded | `20368fc85` |

## Defects found, not yet fixed

3. **A re-attached `/goal` record behind the limit error reads as a turn in flight.** Pane 48
   (769b7294): the transcript's last records are the limit error at 02:40:06Z, then a `user` record
   carrying the session-scoped Stop-hook goal text with an older timestamp (2026-10-19T15:15Z).
   `lr-handoff` precheck: `bg_work: unknown (limited, but a turn is in flight after the limit)` →
   `HELD:busy`; the reconciler shows `HOLD-COMPOSER`, attempt 6. The limit-recover skill says a live
   `/goal` behind the limit error must not hold a session (rule of 2026-10-13, panes 297 and 113);
   this shape (goal re-attachment as a `user` record) is not covered.
4. **Two actors, neither owning.** Panes 20 and 30 (3e929a81, 3d1d988a) went LIMITED at 03:13Z and
   03:19Z while queued in an idle-move batch. The reconciler holds records for them in
   `PRE-MOVE/WAIT_DATA` (since 03:43Z) yet never placed them after the placer recovered at 04:29Z;
   the reset poller's fence said `verdict=act reason=not-owned` and dispatched `lr-fleet --one` at
   04:10Z, which failed `HELD:unreachable` (kitty socket) and left `runs/by-sid/<sid>.active`
   mutexes whose holder pids (37815, 23199) are dead. Its verdict went nowhere: `cc-notify ...
   role 'desk' is not set` → "the verdict is on disk only".
5. **The kitty control socket is a single point of failure for every lane.** `HELD:unreachable` /
   `HELD:pane:resolver-unavailable` / `composer: unreadable` appear in the reconciler R lane
   (panes 32, 38, 41), the poller lane (20, 30) and the idle-move lane.

6. **A heavy fan-out lead cannot be placed anywhere.** Pane 41 (db755a94) at 04:56Z: placement
   `{"acct":null,"reason":"fact:7d,kmax-concurrency","eta_s":25661,"weight":19}`. Its mover weight
   is `1 + subagent transcripts written in the 10 min before death` (`plan.mover_weight`), so one
   session asks for 19 seats against each account's active-concurrency cap and no account has 19
   free. It sits `WAIT_SLOT` (re-offered every pass, ETA 11:57Z) until seats free. The weight models
   the subagents a resumed lead would restart; a resumed session restarts none of them on its own,
   so the charge may be far above what the move actually costs.
   CORRECTED (2026-10-20): the last sentence is wrong. Resumed leads do restart fan-out: 12 of 18
   weighted movers reached 5+ concurrent subagents within 60 min, and db755a94 started a 12-agent
   workflow 1 s after it engaged (`gap-3-non-load-permanent-holds-and-seat-caps.md`). The defect is
   that the weight is unbounded (it counts files written after the death and can exceed KMAX), not
   that it exists.

## Gate timeline (from events.jsonl and actlogs)

- 02:36Z-03:23Z: admission refused (`probe-error` = 30 s probe timeout, then `cpu` brake). The drip
  admission (1 per 30 s after 3 refusals) sits behind the CPU brake, so it never opened.
- 03:00Z: all 4 idle moves `HELD:load — load 38.02/core stayed above the 20/core recycle bound for 605s`.
- placer `rc=124 cause=timeout` (120 s) from ~02:46Z until 04:29Z; first answer `dur=84.2s` at load 182,
  later answers 14-18 s.
- Load average over the run: 105-375 on 10 cores. The fired fix sessions engaged in 25-46 s at load
  333-356, so a fresh Claude Code session DOES boot and work at that load.
