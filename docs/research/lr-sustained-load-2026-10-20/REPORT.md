# Limit-recover under permanent high load: synthesis report

Incident: on 2026-10-20 the next3 account hit its weekly cap at about 02:31Z with 9 sessions on it. This report combines the ten research axes in `docs/research/lr-sustained-load-2026-10-20/` (`01-…` through `10-…`, each with its skeptic review) and the lead's notes (`00-lead-observations.md`). I also took my own read-only readings of the live system at about 05:09Z. All research was read-only.

**Labels.** *Measured* means read from a named file or command. *Estimated* means derived, with the method named. *Hypothesis* means not verified. When a number comes from an axis file, the axis is named and its own command is the source. Code citations are to the live checkout `/Users/chrisren/Development/claude-infrastructure`, `main` at `58885750c`, unless a line says otherwise.

## 1. The answer

**Recovery does not need lower load. It needs to stop running one scheduling band below the work it competes with, and it needs to stop waiting for conditions that, by the operator's premise, never change.**

1. **The priority band.** The whole limit-recover control plane runs at Darwin scheduling priority 20, the "utility" band. That covers the reconciler, the reset poller, the move lane and every child they start: the capacity probe, the placer, the `ps` census, lr-handoff, handoff-fire, the recycle watcher and the kitty remote-control clients. They run at 20 because their launchd jobs set no `ProcessType`. Every Claude session runs at 31. At load ~200, the same work takes 7-111x longer at 20 than at 31 (measured on five axes), so the rail's 3/10/30/120 s bounds fire. Those firings are then read as facts about kitty, memory or placement. Meanwhile 55-79% of the load average is background threads queued on the 2 efficiency cores, which sessions never compete with.
2. **What to change.**
   - Raise the rail to priority 31 (`ProcessType Interactive`, then read the band back).
   - Delete every wait for load: the move worker's stale 20/core wait, the CPU brake's load term and its pass-scoped clock, and HELD:load as a final verdict.
   - Treat our own timeout firing as "unknown, retry", never as a negative verdict.
   - Fix the logic defects that turned retries into no-ops: the claim re-stamp on restart, plan-only cohort members that nothing drives, a false HELD:busy on a re-attached `/goal` record, and a 19-seat weight on a resumed lead.
3. **Make it a contract.** Every queued recovery is attempted within a bounded time of detection, whatever the load. A deadline that bypasses soft gates enforces it, and a load harness that reproduces the band mix proves it.
4. **Act before the wall.** The weekly wall is forecastable hours ahead (median 10.5 h before reset, about 2.7 walls a week). Keep recycles off an account the router already holds for new work, and shed idle sessions in the warning band, so fewer sessions ever need recovery.
5. **Zero-restart credential flips are not buildable yet.** A credential flip is the one path whose cost does not grow with CPU load, but it is blocked on an operator-run prototype and on refresh-token safety (§4c).

## 2. Where the time went

### 2.1 What actually happened (corrected headline)

- **By 04:16Z, 5 of 9 were working on another account**, which matches the brief:
  - d7eb73d2, engaged 03:53:31;
  - the idle moves ceff45c5 and 9240c6a9, engaged 03:58:17-19;
  - e80b61f4, engaged 04:06:14;
  - 7aae55e1, engaged 04:15:16.

  The last two records read `RELAUNCHED/UNPROMPTED`: their continue prompt was never typed, but their transcripts show real work (axis 02 skeptic, F1 REFUTED the "only 3 of 9" claim).
- **At 05:09Z, 2 h 38 m after the cap, 4 of 9 were still not moved.** Measured: python read of `~/.reso/limit-recover/recon/sessions/<sid>*.json` at 05:09:22Z.

  | session | state at 05:09Z | what holds it |
  |---|---|---|
  | db755a94 | `PRE-MOVE/WAIT_SLOT`, attempt 3, target next4 | `weight 19`, `wait.detail "fact:7d,kmax-concurrency"`, ETA `11:55:01Z` (`date -u -r 1792497301`). It is charged 19 seats (§3.4) |
  | 769b7294 | `PRE-MOVE/PLANNED`, attempt 6 | a false `HELD:busy` on every attempt (§3.4) |
  | 3e929a81 | `PRE-MOVE/PLANNED`, attempt 1 | plan-only hook record until an operator re-fire at 04:38:45 (axis 10 X2) |
  | 3d1d988a | `PRE-MOVE/PLANNED`, attempt 1 | R spawned in the pass starting 05:00:49Z (`events.jsonl` spawn row t=1792472449) |

- **The placer still fails at 05:09Z.** `place … rc=124 cause=timeout dur=120.2s timeout=120s load1=175` at 04:40:51Z, and the same at 04:48:58Z with load1=174 (measured: `tail -n 400 recon/events.jsonl | grep place`).
- **The reconciler is still in band 20.** `ps -M -p 51148` => both threads `20T` at 05:09Z (measured). A single `ps -o pri` sample read 46; that is a transient boost, as axis 03's skeptic warned.
- **A fix for the two unprompted records exists but is not running.** `58885750c` (committed 04:57:05Z) fixes the C actuator's quiet-grace check; C types the owed continue prompt. That check compared a stamp written with the pass's own `now` against that same `now`, so it always read 0. The running daemon started at 04:31:18Z (`restarts.jsonl` last row; `ps` etime 38:12 at 05:09Z), so the fix is not loaded.

### 2.2 Minutes lost, by blocker class

Source: axis 02 §6. Interval edges are measured timestamps. The class assigned to each interval is an estimate. Totals were reproduced by `python3 -I /tmp/f02/agg.py` (axis 02 skeptic, F2). The cut-off is 04:19:00 for the sessions still open. The family grouping and family sums are my arithmetic on axis 02's rows.

| Family | Class | Minutes | Share |
|---|---|---|---|
| **Waits for load to fall** | move-lane HELD:load (lr-move-worker 20/core wait) | 151.6 | 19.1% |
| | CPU brake (one admission per pass) | 30.8 | 3.9% |
| | *family total* | *182.4* | *23.0%* |
| **Control plane starved in band 20** (slow, not refusing) | pass cadence (5-14 min passes, late reap, restart-killed passes) | 149.6 | 18.9% |
| | actuator wall time under load (successful or ongoing attempts) | 101.9 | 12.8% |
| | placer / router timeout | 64.6 | 8.1% |
| | kitty did not answer | 44.5 | 5.6% |
| | capacity probe timeout | 21.4 | 2.7% |
| | composer unreadable | 8.1 | 1.0% |
| | *family total* | *390.1* | *49.2%* |
| **Logic defects** | plan-only hook records / poller tick cadence | 72.4 | 9.1% |
| | false HELD:busy (769b7294) | 64.0 | 8.1% |
| | post-transplant rollback stuck at PRE-MOVE/None (fixed in `20368fc85`) | 46.1 | 5.8% |
| | restart re-stamps claim → actuator refuses its own recycle | 25.9 | 3.3% |
| | *family total* | *208.4* | *26.3%* |
| Operator | operator re-issue of the move batch | 12.4 | 1.6% |
| | **Total** | **793.3 session-minutes** | |

Three caveats on this table:

- The band family is where a priority fix can act. Axis 04's skeptic (F1) independently estimated ~49% for it.
- The skeptic reviews moved two attributions:
  - Most of the "WAIT_DATA ~30 min" in the brief was the plan-only gate, not the placer (axis 10 X2, axis 02 F7).
  - The kitty failures were mostly the client's band, not kitty (axis 07 F1, axis 03 F2).
- Some classes are a mix of families. For example, some HELD:busy minutes are pass cadence. The shares are indicative.

### 2.3 How each attempt ended

Measured in axis 02 §5:
- 18 attempts in all: 12 reconciler spawns, 2 move-lane moves and 4 runs of lr-fleet, the reset poller's per-session runner.
- 3 delivered a working session by 04:19, and 2 more relaunched without their prompt.
- 13 failed: 5 HELD:busy, 3 kitty, 2 restart-claim, 2 router PARKED, 1 composer.
- 3 of the failures came after a transplant and needed an abort.
- Axis 01's skeptic (S2) measured the reconciler lane alone: 9 of 12 attempts were NOTMOVED, which is 75% downstream failure.

**Little's law reading** (axis 05 §4, corrected by its skeptic, F8; estimated):
- The reconciler ran about 2.2 attempts in flight on average.
- It needed about 4 attempts per success.
- One pass took a median of ~8.3 min (range 4.9-13.6 min; axis 02 skeptic F2).

Every detection, placement, admission, reap and retry happens once per pass. So the box's real recovery clock was the pass, not the 3 s gap the code requests (`ACTIVE_FAST_S=3.0`, `__main__.py:57`). That is the "requested rate ≠ delivered rate" lesson (`.claude/rules/agent-operating-lessons-situational.md:34`).

## 3. Root cause

### 3.1 The cross-cutting cause: recovery runs one band below the work

**The band, measured.**
- The reconciler is at base priority 20: `ps -M -p 51148` => `20T` (measured 05:09Z). axis 04 R0.3 read `base 20 / max 20` with `proc_pidinfo`, a hard ceiling.
- Its children are at 20 too:
  - lr-handoff, handoff-fire and caffeinate: axis 01 S1, axis 03 §1;
  - the `kitten @` client: axis 09 R2.
- The reset poller is at 20 (axis 05 F3, axis 09 F3).
- The plists set no `ProcessType`:
  - `grep -n ProcessType scripts/limit-recover/*.plist` => no match (measured);
  - `man launchd.plist`: "If left unspecified, the system will apply light resource limits to the job, throttling its CPU usage and I/O bandwidth."
- A utility-clamped parent cannot produce a priority-31 child (axis 04 R0.4).
- The fix is already staged for the move lane and was never installed. `launchd/staged/com.reso.lr-move-kick.plist:23` carries `ProcessType Interactive`, and `ls ~/Library/LaunchAgents` lists only lr-reconciler, -rig, -watchdog and lr-reset-poller (measured 05:09Z).

**The cost, measured in independent same-moment A/B runs (priority 31 vs `taskpolicy -c utility` = priority 20).**

| Work the rail does | Band 31 | Band 20 | Load1 | Axis |
|---|---|---|---|---|
| `ps -axo …lstart,args` (census read) | 0.24-0.34 s | 8.2-12.7 s | 182-222 | 03 skeptic |
| `cc_capacity_probe` (the admission probe) | 2.6-3.9 s | 54.1-88.4 s | 181-230 | 05 skeptic S0.3 |
| `cc-lr status` | 1.09-1.97 s | 33.2-61.4 s | 214-224 | 04 skeptic R0.1 |
| `kitten @ ls --match id:38` | 0.047-0.084 s | 1.07-4.56 s | 188-234 | 07 skeptic F1 |
| `it2 session list --json` (watcher pane probe, 10 s bound) | 0.44-0.68 s, 4/4 pass | 9.9-24.5 s, 1/4 pass | 188-234 | 07 skeptic F1 |
| kitty connect probe body (3 s bound) | 0.10-0.15 s | 0.36-6.37 s, 3/6 over 3 s | 168-234 | 06 skeptic |
| fixed ~0.45 CPU-s micro-task | 0.87-1.12 s | 30-50 s | 189-232 | 09 skeptic R1 |
| same micro-task, background band (priority 4) | — | >150 s, never finished | 189-232 | 09 skeptic R1 |

**Kitty itself answered.** It answered 20/20 in 0.064-0.165 s at load 196-217 (axis 07 §1 row 8). Its log has one late-answer "Broken pipe" line from 02:00 to 04:35Z, against 6 or more client failures (axis 07 F4).

**Positive control for the cure.** After the same plist change, the research-classifier warm workers went from 34/150 fallbacks at priority 20 to 0/150 in both arms at load 118-471, median 382 (~38/core). Source: commit `f1a62145d`, cited by axis 03's skeptic, F1. A live Interactive job (`com.claude.research-classifier-warm`, pid 60282) runs at base 31 and max 63, and its plain Popen children also run at 31 (axes 04 R0.3 and 06 F1).

**Why "load" misleads.** On Darwin, the load average counts every runnable thread in every band (`osfmk/kern/sched_average.c`, axis 04 §2). By per-thread base priority at load ~200, 73-79% of runnable threads are background-band (axis 09 skeptic R2). They queue on the 2 efficiency cores, and the default band held 11-48 runnable threads on 8 performance cores (axis 04 R0.2, axis 09 R2). So:
- the default band runs at about a 2x stretch (axis 09 R1);
- a priority-20 process gets about 3.9% of one core (axis 06 skeptic spinner);
- the background band gets nothing.

That is why "high load per core has not blocked more sessions" holds while the rail starves. It is also why priority 31 is not the end state: that band is oversubscribed, so expect a residual 1.1-7x (estimated by axis 04's skeptic from wall/cpu ratios).

### 3.2 Gates that assume load falls (wrong under the operator premise)

| Gate (file:line) | What it waits for | Under permanent 15-40/core | Harm behind it | Verdict |
|---|---|---|---|---|
| Move-worker load wait, `lr-move-worker.sh:335-358` | load/core < 20, for `max(600, UNTIL)` s, then a final NOTMOVED `HELD:load` (`:349`) | **Never opens**. Measured: 4/4 rows held 605-613 s; then a 1660 s wait during which 2 idle sessions turned limited (axes 01 F4, 06 F6) | A copy of handoff-fire's typed-relaunch bound. Since Wave S (`e2d0cee07`, which makes a move stage its relaunch so nothing is typed), handoff-fire does not gate a staged move (`handoff-fire.sh:13837` prints "load: not gated"). The worker never got that exemption (`grep -n -i successor lr-move-worker.sh` finds only draft-carry lines) | **Folklore since Wave S** (axes 03, 06, 10) |
| CPU brake, `admit.py:150-157`, gate order `:273-300` | load1/ncpu ≤ max(2.5, L_open), where L_open is the load frozen at the moment recovery went active; or 20 s since the last admission | The 20 s floor is measured against one `now` per pass (`__main__.py:1631`), so it amounts to **one admission per pass**. L_open re-freezes at every restart | None measured. 2.5/core is "uncalibrated: 2.53 fatal once, 5.98 survived" (axis 03 G1) | **Folklore as a harm gate** |
| Drip (the only bounded escape), `admit.py:282-296` | 3 probe refusals, then one per 30 s | Sits **behind** the brake. A `cpu` refusal does not count toward it. Its 30 s clock is also pass-scoped, and the probe still runs (≤30 s) on a drip pass | n/a | Escape exists but is rate-capped at one per pass (axis 01 F3 CONFIRMED) |
| Placer bound, `plan.py:312-318` | `30·load1/(4·ncpu)` s, clamped to 30-120 | Pinned at 120 s from 16/core. It also **shrinks** as load1 falls: it fired at 63-66 s at load1 84-89 while the work did not shrink (axis 06 F4) | None: a timeout is not evidence that any account is full | **Symptom of the band**, sized wrong in both directions |
| Probe runner, `admit.py:67` `timeout=30` | memory terms (headroom ≥4 GB, segments ≤50%) | Fires at 30 s in band 20. Meanwhile memory sat at 21-27 GB headroom and 9-15% segments (axis 03 F6) | **Real** (both 09-16 panics were at compressor segments 100%) | Keep the memory terms; the timeout is the failure |
| Kitty-latency and load HELD verdicts → `map_notmoved` falls through to `("DETERMINISTIC","")` at `classify.py:153` | n/a | A repeat goes ESCALATED, then a 15 min sleep ×4, then IMPOSSIBLE and released (axis 01 F6). Under a standing slow client, that means **giving up** | n/a | Wrong class for kitty latency (axis 01 L6) |
| Mover weight vs account concurrency, `plan.py:153-156` | 1 + subagent transcripts in the last 10 min = **19** seats for db755a94 | Under 24/7 maximum concurrency no account has 19 free seats. Wait ETA 11:55Z, about 7 h (measured, §2.1) | The model assumes a resumed lead restarts its subagents (hypothesis, unverified; `00-lead-observations.md:32-38`) | A capacity wait that, under the premise, never clears |
| Restore budget R vs fleet-wide active count, `admit.py:262-277` | `active + in flight + 1 ≤ R` | Bounded: it counts into the drip run, costing 3 passes once per cohort per daemon lifetime (axis 01 F8) | Policy count, not harm | Low cost; folds into the deadline design |
| BootSlots, `admit.py` `BootSlots` (`on_wave` never called) | a fixed width of 6 | Inert at ~2.2 in flight | "Failed at load 40+" was a 90 s *detection window* at ~4/core: "the window was too short, not the relaunch wrong" (`LIMIT_RECOVER_100P.md:391`, axis 03 F5) | Folklore rationale; a fixed width in practice |

### 3.3 Real harms vs folklore

**Real harms.** Keep a gate for each, and key it on the resource itself, not on load:
- **Memory and the compressor.** Panics happened at segments 100% (axis 03 G2). Read the compressor-sentinel file, not just the pressure level (axis 05 skeptic L3).
- **Kitty 0.48.2 talk-thread death.** A code bug; the patched build is staged but not running (axis 07 F8).
- **Kitty at priority 4 with the screen locked or under App Nap.** It failed 9/9 calls on 10-01 (`recycle-unreachable-2026-10-01.md:11-13`). `NSAppSleepDisabled` is still unset (axis 07 F8).
- **A typed relaunch over a backlogged kitty at 42-45/core.** F1, pane 44, 2026-10-09. This is already exempt when the relaunch is staged.
- **secd background-band starvation of keychain reads.** Mitigated by `CLAUDE_CODE_CERT_STORE=bundled` in all 5 config dirs (axis 03 F9). The placer's own `security find-generic-password` calls still go through secd (axis 03 F7).
- **Kernel-side stalls.** 40-53% of CPU time is system time, from 280-1,410 process creations per second (axis 09 F4). One SIGKILLed `ps` came back after 1,226 s at load 330 (axis 03 F9). It is unknown whether priority 31 escapes this.

**Folklore**, meaning per-core load used as a harm signal. Each threshold, and what its own record says:
- 2.5/core: "uncalibrated".
- 8/core: "ship-land's gate factor, never typing data" (`d4260ae3c`).
- 20/core for staged moves: exempt downstream since Wave S.
- "Boots fail at load 40+": that event was a 90 s detection window at about 4/core.

**Evidence that load itself does not stop recovery:**
- 17 recycles engaged at 32-67/core (axis 03 §4.2).
- 43/43 typed lines submitted up to 31.8/core (axis 05 §1.4).
- Claude Code booted in 7-13 s at incident load; 80 boot samples, max 13 s (axis 05 skeptic F5, axis 06 §4.6).
- The lead's fired fix sessions engaged in 25-46 s at load 333-356 (`00-lead-observations.md:47-48`).
- Caveat: above 24/core only *staged* relaunches have data; a typed relaunch has n=0 above 32/core apart from F1 (axis 03 skeptic F4).

### 3.4 Logic defects that turned retries into no-ops

| Defect | Evidence | Status |
|---|---|---|
| Pass-scoped `now` compared against stamps written from the same `now` | Seen in `cpu_ok` and the drip (`admit.py:150-157`, `:289`, `__main__.py:1631`) and in C's quiet grace (`58885750c` message: "the gap reads 0 on every pass the launcher lives") | C grace fixed but not loaded; brake and drip open |
| A daemon restart re-stamps every open claim to the new pid, so the old daemon's actuator refuses its **own** recycle **after** the transplant | `e80b61f4.1.R.log`, `7aae55e1.2.R.log` "another actuator holds session …'s move claim (pid 47282/38189, lr-reconciler)"; `__main__.py:1739-1744` → `store.py:369-379` (axis 02 F6). All 3 restarts came 10-18 min after an lr_recon fix commit (axis 01 S4; deploy-driven is a hypothesis) | Open |
| Hook-origin records are plan-only while `recon/autorecover.on` is absent, so the reconciler never drives newly limited members of a cohort it is already recovering. The status line says "the reconciler retries" | `census.py:349`, `__main__.py:217-222`, `:1008-1011`; `ls recon/autorecover.on` => No such file (axis 02 F7, axis 10 X2) | Open; needs an operator ruling (zero-human scope) |
| A false HELD:busy | 769b7294's transcript ends with the limit, then an `isMeta` user record ("A session-scoped Stop hook is now active…") timestamped 2026-10-19T15:15:16Z but written after the limit. `hf_transcript_at_rest` (`handoff-fire.sh:2978`) reads it as a user turn (axis 02 skeptic F9; `00-lead-observations.md:14-20`) | Open. A worktree `fix/hf-at-rest-goal-paused` was running `lr-reset-poller.sh --once` at 05:09Z (`ps`), so a fix may be in progress (hypothesis) |
| Our own timeout read as a negative verdict | `kitty_socket_accepting`'s rc 124 is collapsed into "not accepting" at `handoff-fire.sh:2867,2874`, so the retry branch (`:2903`) is skipped, giving HELD:pane:resolver-unavailable. Python start alone in band 20 can exceed the 3 s bound (axis 06 F5 CONFIRMED) | Open |
| 19-seat weight for a resumed lead | db755a94 `weight 19`, `fact:7d,kmax-concurrency`, ETA 11:55Z (measured 05:09Z) | Open; not reviewed by any skeptic |
| Post-transplant rollback stuck at PRE-MOVE/None | fixed `20368fc85`, loaded 04:31Z; re-drive works (axis 02 skeptic L6) | Fixed |
| A placement with no answer parked records at WAIT_RESET until a far reset | fixed `31f4242e0`; cost 0 min here (axis 02 F9) | Fixed |

## 4. The ranked plan

Each lever lists mechanism, expected effect, risk, effort, evidence, the skeptic's verdict, and my conviction. Conviction is my estimate that the lever, as amended by its skeptic, does what it says under 15-40/core. Levers that a skeptic REFUTED are in Appendix A.

### (a) Stop-gaps that can land now

**A1. Run the recovery rail at priority 31.** *Operator activation.*
- **Mechanism.**
  - Add `ProcessType Interactive` to `com.reso.lr-reconciler.plist` and `com.reso.lr-reset-poller.plist`.
  - Install the staged `com.reso.lr-move-kick`.
  - Reload, then read back base priority ≥31 with `ps -M` over several samples (one `ps -o pri` sample can read a transient 46).
  - Add a daemon self-check that logs its base priority every pass and pages if it is below 31.
  - Do not clamp any census that carries kitty reads or feeds a waiting worker back to utility (axis 07 skeptic L1).
- **Expected effect.** The band multiplier goes from 7-111x to about 1-7x (measured A/B; residual estimated). That acts on ~49% of lost minutes: probe timeouts, placer rc=124, ps abstains, resolver-unavailable, pass length.
- **Risk.**
  - The rail's CPU (0.4-2.5% of one core, measured on axes 03 and 06) now competes at 31. A runaway loop would cost a core instead of starving quietly; the watchdog's CPU-evidence kill still applies.
  - It does not fix kitty at priority 4 (see B8).
  - There is a known `Bootstrap failed: 5` re-bootstrap race (axis 04 L1).
- **Effort.** S to change, M to verify under load.
- **Evidence.** §3.1; `f1a62145d`; axis 04 R0.3 Interactive positive control.
- **Skeptic.** CONFIRMED on axes 03 (L1), 04 (L1), 05 (L4, strengthened), 06 (L4), 07 (L1) and 09 (L1). Caveats: unmeasured at 35-40/core, and the default band is oversubscribed.
- **Conviction: 90%.**

**A2. Remove the move worker's wait for load.**
- **Mechanism.**
  - In `lr-move-worker.sh` `load_over` (`:335`), skip the wait when the move will stage a successor (`CC_PANE_SUCCESSOR` on and the successor library loads), mirroring `handoff-fire.sh:13836-13837`.
  - Or delete the wait and let handoff-fire's commit-time hold decide at the one point it guards.
  - Never finish a final `HELD:load` (`:349`).
  - This also unblocks `cc-lr switch` from a healthy session, which hands off to this lane (`bin/cc-lr:2109-2135`, axis 10 F6).
- **Expected effect.** Removes the largest single class: 151.6 min (19.1%). Stops idle sessions from turning limited while they wait (2 of 4 did).
- **Risk.** The worker's next gate is the kitty precheck, so without A1 the likely result is `HELD:pane:resolver-unavailable` in place of `HELD:load` (axis 03 skeptic L2). Ship it with A1. The staged-claim path above 20/core has n=1 in this incident (axis 02 skeptic L4).
- **Effort.** S.
- **Evidence.** `lr-move-worker.sh:335-358` (verified); move batch `20261020T024813Z…` 4/4 HELD:load at 605-613 s; batch `…030423Z…` 1660 s.
- **Skeptic.** CONFIRMED (axis 01 L5, 02 L4, 06 L1); WEAKENED on effect size (03 L2, 10 L2).
- **Conviction: 90%.**

**A3. Treat our own timeout as "unknown, retry", and stop giving up on kitty latency.**
- **Mechanism.**
  - (i) At `handoff-fire.sh:2867,2874`, map rc 124/137 from `kitty_socket_accepting` to a `probe-unknown` that takes the retry branch (`:2903`). Also retry rc 3 when the socket owner's pid is alive (axis 06 skeptic L3).
  - (ii) In `classify.map_notmoved` (`classify.py:125-153`), classify `pane:resolver-unavailable`, `unreachable` and `wedged` as TRANSIENT (backoff capped at 300 s), not DETERMINISTIC → ESCALATED → IMPOSSIBLE.
  - (iii) Keep `HELD:load` out of TRANSIENT. A2 removes its source; a typed-only `HELD:load` retried every 300 s would mint a token each time for nothing (axis 01 skeptic L6).
- **Expected effect.** d7eb73d2's first attempt becomes a retry. The incident logs show exactly that retry working: "the probe's own 3s bound fired … asking again in 5s", then `precheck verdict: OK` (`d7eb73d2.2.R.log:11`, `e80b61f4.1.R.log:9`). No session is released after an hour of slow terminal.
- **Risk.** A truly dead kitty pages hourly instead of terminating. A dead kitty answers rc 3/4 fast, not rc 124.
- **Effort.** S.
- **Evidence.** Verified code lines; axis 06 F5.
- **Skeptic.** 06 L3 CONFIRMED; 01 L6 WEAKENED (split as above).
- **Conviction: 85%.**

**A4. Admission paced in wall-clock time, not per pass.**
- **Mechanism.**
  - Give `cpu_ok` and the drip a separate clock, either `time.time()` at decide or a token bucket (rate 1 per 20 s, burst = BootSlots). Keep the pass `now` as the identity for the restore-r run (`admit.py:273-276`), or that run would count members instead of passes.
  - Delete the brake's load term. Under the premise its input (load1) does not move with the session it gates.
  - Count a `probe-timeout` as no-verdict. On a timeout, read the compressor-sentinel file instead, not just `kern.memorystatus_vm_pressure_level` (axis 05 skeptic L3).
  - Skip the probe when the drip will admit anyway (axis 06 F8).
  - Persist `refusals` and `last_drip_at` across restarts. Do not persist L_open or R.
- **Expected effect.** More than one admission per pass. Estimated small directly: 30.8 + 21.4 min of the 793. It also removes up to k×30 s of serial probe time per pass, which feeds pass length.
- **Risk.** A burst of first turns onto one target account. The per-account pacer (3) and BootSlots (6) still bound it.
- **Effort.** S.
- **Evidence.** `admit.py:150-157,273-300` and `__main__.py:1631` (verified); events 02:54:18/19 `cpu` in the same pass as an admission.
- **Skeptic.** 01 L1 CONFIRMED with caveats, L2 WEAKENED (only with L1); 02 L1 WEAKENED (small payoff); 03 L3 CONFIRMED, L4 CONFIRMED (low impact); 05 L1 WEAKENED, L3 WEAKENED (fallback must be the sentinel); 06 L5 CONFIRMED (keep the per-member count).
- **Conviction: 80%.**

**A5. Fix the false HELD:busy on a re-attached `/goal` record.**
- **Mechanism.** `hf_transcript_at_rest` (`handoff-fire.sh:2978`) must skip `isMeta` user records, and records whose timestamp is earlier than the limit record they follow. That extends the 2026-10-13 rule that a live `/goal` behind the limit error must not hold a session.
- **Expected effect.** 769b7294 moves. 64.0 min so far, and still held at attempt 6 at 05:09Z.
- **Risk.** A real turn misread as meta. The `isMeta` flag is explicit.
- **Effort.** S.
- **Evidence.** axis 02 skeptic F9; `00-lead-observations.md:14-20`.
- **Skeptic.** CONFIRMED as diagnosis (02 F9). The lever itself was not reviewed.
- **Conviction: 85%.**

**A6. Restart safety.**
- **Mechanism.**
  - (i) Do not restart the reconciler mid-cohort to deploy a fix. All 3 incident restarts followed an lr_recon commit by 10-18 min (hypothesis: deploy-driven).
  - (ii) On restart, re-stamp an in-flight claim to the adopted live actuator's pid (an ancestor of handoff-fire), not to the new daemon's pid (axis 02 skeptic L3).
  - (iii) Persist the Admission counters (with A4).
- **Expected effect.** Avoids 2 post-transplant self-refusals (25.9 min) and 2 killed passes per restart.
- **Risk.** Leaving a dead-pid holder lets the poller steal the claim and opens a second-driver window (poller.log 03:20:12 `stolen-dead-holder`). That is why this is option (ii), not "no restamp".
- **Effort.** S-M.
- **Evidence.** §3.4; `restarts.jsonl` at 03:23:17, 03:53:16 and 04:31:18.
- **Skeptic.** 02 L3 WEAKENED (use the adopted-pid variant); 01 L8 CONFIRMED (modest); 05 S3 lists it among the top 3.
- **Conviction: 75%.**

**A7. Let the reconciler drive cohort members that turned limited while queued.** *Operator ruling needed.*
- **Mechanism.**
  - When a move-lane worker finishes `became-limited … cc-lr recover <sid>`, perform that promotion automatically, which sets `origin=cc-lr` (`census.py:349`).
  - Alternatively, let the reconciler drive a hook-origin record whose source account is already in an ACTIVE cohort.
  - Correct the misleading "the reconciler retries" status.
- **Expected effect.** Removes 72.4 min (9.1%), the WAIT_DATA ~30-36 min of 3e929a81 and 3d1d988a.
- **Risk.** Two drivers at once. The poller's 03:20:12 dispatch already produced duplicate bundles 031605Z/031606Z on 769b7294. Changes zero-human scope (D1.9). The global `autorecover.on` exists, so the poller already acts on these sessions without a human.
- **Effort.** S.
- **Evidence.** §3.4.
- **Skeptic.** 02 L5 CONFIRMED (risk restated); 10 L5 WEAKENED (zero-human decision).
- **Conviction: 70%.**

**A8. Charge a resumed lead one seat, not 1 + recent subagents.**
- **Mechanism.** `plan.mover_weight` (`plan.py:153-156`) charges db755a94 19 seats against account concurrency. Charge 1, or cap at the target's free seats and treat the rest as soft.
- **Expected effect.** db755a94 can move now instead of waiting about 7 h for 11:55Z.
- **Risk.** If a resumed lead does relaunch its team, the target account over-commits. Hypothesis: it restarts none on its own (`00-lead-observations.md:36-38`).
- **Effort.** S.
- **Evidence.** db755a94 record at 05:09Z (measured).
- **Skeptic.** Not reviewed by any skeptic. This came from the lead's notes and my reading.
- **Conviction: 65%.**

### (b) Structural changes

**B1. A load harness and the guarantee tests in §5.** This proves A1-A8 and keeps them proven.
- **Effort.** M.
- **Evidence.** The W5 rig, `tests/rig/lr-recon-rig.sh`, already runs the real daemon and real actuators against fake `claude` and throwaway config dirs. It injects no load. It runs the daemon under a detached supervisor whose priority band is the caller's (hypothesis: started from a session, it would run at 31 and hide the bug).
- **Conviction: 80%.**

**B2. A bounded pass, with slow children off the serial path.**
- **Mechanism.**
  - Run one capacity probe per pass, asynchronously, consumed at dispatch.
  - Reap actuators by `waitpid`/SIGCHLD: they are direct children, as a defunct pid 1293 with ppid 51148 showed.
  - Place stale-while-revalidate: use the last answered placement if the capped set is unchanged and it is under 10 min old, and run `--place` in the background. Fall back to a ranking that excludes capped accounts.
  - Add per-phase timings to the heartbeat.
- **Expected effect.** Pass length bounded (target P_max ≤ 3 min, estimated; measured today 4.9-13.6). A retry follows an exit within seconds, not about one pass later. Pass cadence was 149.6 min.
- **Risk.**
  - Concurrency between loops on one record; keep the claim/fence discipline.
  - Do this after A1. Splitting loops inside a band-20 process does not help (axis 02 skeptic L2).
- **Effort.** M.
- **Evidence.** axis 02 §4.1; axes 01 G4/G5, 05 G2/G6, 06 §5.
- **Skeptic.** 01 L4 WEAKENED (effect overstated); 02 L2 WEAKENED (band first); 05 L7 CONFIRMED (with a dependency: measure `--place` after A1); 06 L5 CONFIRMED, L6 CONFIRMED (secondary).
- **Conviction: 70%.**

**B3. A deadline override, applied before the gates.**
- **Mechanism.**
  - Every record has an on-disk `t_detect`.
  - After `W_soft` (10 min, a knob), all soft gates are bypassed: brake, probe, restore budget, load, placement freshness.
  - Only hard predicates hold a record (§5). Each pages after `W_hard`.
  - A deadline lane admits overdue records at a width set by Little's law, capped at BootSlots.
  - A failed attempt keeps its original `t_detect`.
- **Expected effect.** A computable worst-case first-attempt time (§5), independent of load.
- **Risk.** The bound is only credible once B2 and A1 bound P_max and T_att. With today's measured P_max ≈ 14 min and T_att ≈ 31 min the formula gives about 86 min (axis 05 skeptic L2). Most of this incident's delay sat outside `decide()`.
- **Effort.** M.
- **Skeptic.** 05 L2 WEAKENED.
- **Conviction: 65%.**

**B4. Make `--place` cheap.**
- **Mechanism.** `holds()` globs `projects/*/<sid>.jsonl` across ~18,300 directories per account: 65% of `--place` CPU (cProfile), 109,713 `lstat` calls. Run it only on the winning account, or use the slug path as a fast path with the glob confirming the winner. Size `apply_burn`'s 19.3 MB re-parse separately; it needs a new derived file, because burn may not enter the cache.
- **Expected effect.** About −65% of `--place` CPU on the holds part (upper bound). The corpus only grows.
- **Risk.** A stale copy under another slug; that is why the glob confirms the winner.
- **Effort.** S-M.
- **Evidence.** axis 06 §4.2, F3.
- **Skeptic.** 06 L2 CONFIRMED with a correctness caveat; L8 WEAKENED (cache invariant).
- **Conviction: 65%.**

**B5. Take kitty off the pre-commit critical path.**
- **Mechanism.**
  - Stage the successor *before* the watcher's pane probe (today the stage runs after it: `handoff-fire.sh:20089` vs `:19967`). Make the probe advisory when staged and exiting by signal, or retry it before rolling back a transplant.
  - Use `kitten @ ls --match id:N` (49 KB) instead of the `it2 session list` chain (650 KB, 6-10x slower).
  - Pass the census identity (window, root pid and start time) to lr-handoff, verified by `ps`. Exclude zombies: kitty holds 111.
- **Expected effect.** Fewer of the roughly 8-14 kitty round trips per move. Two post-transplant rollbacks (310-410 s each) become retries or proceeds.
- **Risk.** The composer gate cannot rely on HID idle alone, because non-HID composer writers exist (`handoff-fire.sh:13926-13930`). It is unverified whether a draft survives SIGTERM.
- **Effort.** M.
- **Skeptic.** 07 L2 WEAKENED, L3 WEAKENED (needs the reorder), L4 WEAKENED, L5 CONFIRMED.
- **Conviction: 55%.**

**B6. Telemetry, so the next incident is legible.**
- **Mechanism.**
  - Record a runnable-thread histogram by **base** priority, from `proc_pidinfo` `pth_priority`; `ps` shows decayed current priority and undercounts the default band 1.05-6x.
  - Record kitty's priority each minute, and the daemon's own priority each pass.
  - Log `probe_s` and `place_s`.
  - Write the `recycle_repick` "stays" decision to disk.
- **Effort.** S.
- **Skeptic.** 04 L6 WEAKENED (use base priority); 05 rollout step 3 (shadow-only).
- **Conviction: 60%.**

**B7. Audit the pass-scoped `now` class.**
- **Mechanism.** Three instances so far: the brake floor, the drip clock, and C's grace (fixed in `58885750c`). Audit every `now - <stamp>` in lr_recon whose stamp is written from the same pass's `now`. `grep -n -E 'now *- *…(_at|last)'` lists `classify.py:198`, `__main__.py:1204` and `settle.py:253,965`; the settle ones measure "holder seen this pass" and look intentional (hypothesis). Add a test helper that advances the wall clock inside one pass.
- **Effort.** S.
- **Skeptic.** Not reviewed; it is a synthesis observation.
- **Conviction: 60%.**

**B8. Kitty hygiene at a planned kitty restart.** *Operator.*
- **Mechanism.**
  - Set `defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES`.
  - Swap in the staged build that keeps the talk thread alive.
  - Watch kitty's file-descriptor count against a probable 256.
  - Read `ps -o pri= -p <kitty>` back while the screen is locked.
- **Expected effect.** Removes the overnight priority-4 kitty class. A1 cannot fix that class: on 10-01, 9/9 calls failed at 10 s.
- **Risk.** A kitty restart ends all 32 windows, so it needs a planned boot-resume. The key's effect is unproven.
- **Effort.** S to change; the restart is costly.
- **Skeptic.** 07 L6 CONFIRMED (prerequisite for A1 under a 24/7 screen lock); 05 L9 WEAKENED.
- **Conviction: 55%.**

### (c) The zero-restart path (axis 08)

**C1. Do not build a credential flip yet. Run the operator-only prototype first.**
- **What a flip is.** Rewrite a config directory's keychain item, then send one message through Claude Code's own socket. All of that directory's sessions would continue on another account with no `/exit`, no boot, no admission and no kitty.
- **Why it is attractive.**
  - It is the only path whose cost does not scale with CPU.
  - The 2.1.293 binary does adopt a changed item on the next client build (`j7` → `Pl` → `wA`).
  - Capped turns *end* rather than wait, so one socket message starts the new turn.
- **Blockers** (axis 08 skeptic S1-S3):
  - (1) The next and next3 config dirs hold a leftover `.credentials.json`. A keychain-only flip is then invisible until the next token refresh (up to 8 h) or a 401. That covers 17 of 40 live sessions, including the incident account.
  - (2) Refresh tokens rotate, and `invalid_grant` erases the stored credential, so a copied grant strands an account. Design A and claude-swap-style copy-back are rejected for that reason.
  - (3) Design B (an independent grant per directory per account) depends on experiment E1, which is unrun. The repo's own evidence leans against multi-grant (`forced-relogin-rootcause:287-300`).
  - (4) Design C (setup-token) loses Remote Control and gets HTTP 403 at `/api/oauth/usage`, which blinds quota tracking.
- **Prototype amendments.** Test an idle session after the cap plus one socket message, not "break a wait". Include a directory that holds `.credentials.json`. Run T3 for ≥2 weeks; 48 h has P(no incident) ≈ 0.59 (estimated, Poisson).
- **Effort.** L.
- **Skeptic.** 08 L1-L4 WEAKENED.
- **Conviction: 30%** that a safe, unattended flip is reachable.

**C2. Deliver the owed continue prompt over the Claude Code socket instead of typing it.**
- **Mechanism.** `bin/cc-wake` already sends through the session's messaging socket, with no kitty involved. A "moved under you" mode would deliver C's first turn after a relaunch. It needs its own gates past cc-wake's W3 and W3b, which refuse limited sessions until their reset. The incident's wake was refused at W3: `beat=limited`.
- **Expected effect.** Removes kitty from the last step. Hypothesis: it would also have closed the two RELAUNCHED/UNPROMPTED records.
- **Effort.** M.
- **Skeptic.** 08 L5 CONFIRMED on transport (27 `sent`, 0 transport failures).
- **Conviction: 45%.**

### (d) Proactive avoidance (axis 10)

**D1. A recycle's re-pick honours the router's "held for new work" verdict.**
- **Mechanism.** `recycle_repick` (`handoff-fire.sh:15962-16130`) re-picks only on exclusion, or when the best account beats the current one by 4x. The router stopped new fires onto next3 at 89% (17:51Z), but recycles kept sessions there.
- **Expected effect.** 3 of the 9 wall sessions (7aae55e1, e80b61f4, ceff45c5) were put on next3 by a recycle in its last 4.1 h, at 94%, 96% and 100%. Each had already paid for a relaunch, so moving it would have cost nothing.
- **Risk.** It is a routing-policy judgment and needs an operator ruling. `--rank` runs under a 25 s alarm and fails soft to "stay" (unmeasured at 35-40/core).
- **Effort.** S.
- **Evidence.** The 18:36:54Z `recycle-repick` row ranks next3 last despite the second-highest score (axis 10 skeptic F4).
- **Skeptic.** 10 L1 CONFIRMED.
- **Conviction: 80%.**

**D2. Shed load from an account in its warning band, before the wall.**
- **Mechanism.**
  - The band opens when the account reaches ≥90%, or when the time-to-wall estimate is ≤6 h, while the wall still lands before the reset. 26 of 32 windows that reached 90% walled.
  - In the band, continuously move idle sessions out through the move lane (needs A2), with pre-computed targets confirmed by the `capped.latest_usage` tail read.
  - Shed working sessions at their turn boundary only as far as needed to land the wall near the reset.
  - Run it in shadow mode first.
- **Expected effect.** Fewer sessions at the wall: next3 went from 19 to 9 from attrition alone.
- **Risk.**
  - "Idle" is not zero future burn: 2 of the 4 idle sessions here started turns and walled.
  - The ledger rows lack burn fields, so the controller must derive them itself.
  - Reconciler-originated sheds are plan-only without `autorecover.on`.
  - The kitty precheck is the next gate.
  - The operator must rule on how much quota may be stranded.
- **Effort.** M.
- **Skeptic.** 10 L3, L4 and L5 WEAKENED.
- **Conviction: 55%.**

## 5. The guarantee

**Invariant G: attempt latency is bounded whatever the load.**

Take any record *r* that is limited, or requested to move, and is not held by a named hard predicate. Its first actuation attempt starts by

```
t_first(r) ≤ t_detect(r) + W_soft + P_max + ceil(k_r / D) · T_att
```

After any failed attempt, the next one starts within `B_max + P_max`. The terms:

| Term | Meaning | Value |
|---|---|---|
| `t_detect` | detection time | on disk |
| `W_soft` | soft-gate window | 10 min |
| `P_max` | enforced pass bound | target 3 min |
| `T_att` | attempt wall budget | target 15 min |
| `k_r` | overdue, non-held records detected earlier than *r* | count |
| `D` | deadline-lane width | Little's law, ≤ BootSlots |
| `B_max` | backoff cap | 300 s |

None of these terms is a function of load average. Load can stretch `P_max` and `T_att` only up to their enforced bounds. It can never hold a gate shut.

Estimated for this incident, with the targets above and D=6: the 9th session is first attempted ≤ 10 + 3 + 2·15 = 43 min after detection. With today's measured `P_max` ≈ 14 min and `T_att` ≈ 31 min the same formula gives about 86 min (axis 05 skeptic L2). So G can only be claimed once A1 and B2 have bounded those terms.

**Supporting invariants.** Each is mechanically checkable.

| # | Invariant | How it is enforced |
|---|---|---|
| G1 | **No wait on load.** No decision on the recovery rail reads the load average. Telemetry may record it | A lint over `lr_recon/`, `lr-move-*.sh` and the handoff-fire recycle path for `getloadavg`/`vm.loadavg`/`load1` outside telemetry |
| G2 | **Our timeout is never a verdict.** An rc 124/137 from our own bound maps to TRANSIENT/unknown and is retried at a different moment | Unit tests on `classify.map_notmoved` and the kitty resolver |
| G3 | **Pacing is in wall-clock seconds, and persisted.** Pass length ≤ `P_max` | Per-phase heartbeat; a test that runs many decisions within one pass |
| G4 | **Band.** The daemon and every child read base priority ≥31 | A startup and per-pass self-check that pages below 31 |
| G5 | **No giving up for soft reasons.** A recoverable record ends only as ENGAGED on the target, NOT_NEEDED, or a hard hold that has paged | A test |
| G6 | **Restart-neutral.** A daemon restart does not abort an in-flight actuator, reset `t_detect`, or reset pacing | A test |

**Hard predicates**, the only things that may hold a record past `W_soft`. Each pages after `W_hard`:
- a true busy turn (not an `isMeta` record);
- an unsent draft or a pasted block;
- a live claim by another actuator;
- the target account itself capped (then re-place);
- compressor segments over the panic line, or memory pressure critical, read from the compressor-sentinel file;
- thermal critical.

**The test: a load harness built on the W5 rig** (`tests/rig/lr-recon-rig.sh`, B1).

1. **Two arms.**
   - *Red arm:* today's code, with the rig daemon under `taskpolicy -c utility` (priority 20, as in production).
   - *Cure arm:* the candidate code, with the daemon at priority ≥31, read back with `ps -M`.
   - The red arm must fail G. Green in both arms proves only equivalence, not power (rule "Green in both arms", `agent-operating-lessons-situational.md:62`).
2. **A load generator that reproduces the measured band mix,** not just a load number. Run it at three levels: load1/ncpu 15, 25 and 40.
   - 110-170 runnable background-band threads (`taskpolicy -b` spinners);
   - 12-48 runnable default-band threads (spinners at priority 31);
   - 30-38 utility-band threads;
   - a fork storm of 300-1,400 execs per second.
   - These targets are measured on axes 04 (R0.2) and 09 (R2, §1.3).
3. **Record beside every reading** (rule "Verify a cure under its load", `:83`):
   - load1;
   - the runnable census by base priority;
   - the daemon's priority;
   - kitty's priority.
4. **Cohort.** n = 9 and n = 30 rig sessions, with this fault matrix:
   - kitty RC delayed 2-15 s;
   - composer unreadable once;
   - a true busy turn for M minutes;
   - a fake `/goal` isMeta record after the limit;
   - a daemon restart mid-actuation;
   - the placer sleeping past its bound;
   - a heavy lead (weight 19);
   - a member that turns limited while queued in the move lane.
5. **Assertions.**
   - G holds for every non-held member.
   - Every non-held member is ENGAGED by `T_done`.
   - There are zero `HELD:load` verdicts, zero IMPOSSIBLE-for-soft-reason verdicts, and zero self-claim refusals after a restart.
   - Regressing `t_first` on load level gives a slope that stays within the growth of `P_max` and `T_att`.
6. **Limits of the harness.** The rig uses a fake `claude`, so it cannot test real boots or the API. Real boots measured 7-13 s at incident load (axis 05 skeptic F5).

## 6. Open questions, and conviction per recommendation

| Rec. | Conviction | The open question that would move it most |
|---|---|---|
| A1 Run the rail at priority 31 | 90% | Does Interactive put the daemon *and* its `start_new_session=True` Popen children at ≥31 here? How fast are `--place` and the probe at priority 31 at 35-40/core? Is the default band saturated at the 300-375 peak? (axes 04, 06, 07, 09) |
| A2 Remove the move-worker load wait | 90% | Does a staged move succeed at 35-40/core? n=1 above 20/core (e80b61f4 #2, while load1 went 198 → 370) |
| A3 Our timeout = unknown; kitty latency TRANSIENT | 85% | What was the connect rc in `d7eb73d2.1.R.log`? A full-backlog rc 3 would need the rc-3 retry too |
| A5 False HELD:busy on a `/goal` record | 85% | Is the `fix/hf-at-rest-goal-paused` worktree already this fix? |
| A4 Wall-clock admission pacing, no load term | 80% | Why did the active-cpu sampler read "0 sessions mid-turn" at load 250+, with `active-cpu.json` absent? Is the probe's active term effectively off? (axis 01 H2/S5) |
| D1 Re-pick honours the held verdict | 80% | Operator ruling: is pressure short of exclusion grounds to re-pick? (`handoff-fire.sh:15951-15956`) |
| B1 Load harness and guarantee tests | 80% | Can the rig pin the daemon's band without a launchd job (an operator step)? |
| A6 Restart safety | 75% | What restarted the daemon at 03:23, 03:53 and 04:31? It is not on disk; deploy-driven is a hypothesis |
| A7 Drive limited cohort members | 70% | Operator ruling on zero-human scope (D1.9) and on which lane drives |
| B2 Bounded pass, async children | 70% | How does a 7-14 min pass split between ps, `--place`, kitty reads and probes? The heartbeat has no per-phase timings |
| A8 One seat for a resumed lead | 65% | Does a resumed lead restart its subagents on its own? |
| B3 Deadline override | 65% | Do the measured `P_max` and `T_att` fall to their targets after A1 and B2? |
| B4 Cheap `--place` | 65% | Its production share after the capacity and fact checks run first; 65% is an upper bound |
| B6 Telemetry | 60% | — |
| B7 Pass-`now` audit | 60% | Are the `settle.py:253,965` comparisons intended semantics? |
| B5 Kitty off the critical path | 55% | Does Claude Code keep an unsent draft across SIGTERM? What happens in the 244-310 s between "armed" and "exit-committed"? |
| B8 Kitty hygiene | 55% | What is kitty's priority with the screen locked overnight, and does `NSAppSleepDisabled` lift it? |
| D2 Warning-band shedding | 55% | Per-session burn distribution in the band. How much stranded quota will the operator accept? |
| C2 Socket delivery of the owed prompt | 45% | Can a "moved under you" mode pass cc-wake's W3/W3b gates safely? |
| C1 Credential flip | 30% | E1 (two grants of one account coexist), pickup in a directory with `.credentials.json`, T1-T5 (operator-only) |

## 7. Gap round (added by the lead after the critic pass)

A completeness critic raised four gaps, each researched read-only into its own file. The workflow's
revise step could not merge them (this file did not exist yet: the synthesis step's Write was refused
and its text was saved here by the lead), so they are summarized here. Where a gap changes a lever
above, it says so; the gap file is the evidence.

- **Gap 1, the owed prompt after an in-place relaunch** (`gap-1-post-relaunch-prompt-delivery.md`).
  lr-fire-resume has no quiet window: it has a one-shot 8 s deadline from spawn to a painted
  composer. Of 78 prompted relaunches since 10-01, 63 typed on the READY match, 15 ended
  READY-NOT-SEEN and the quiet arm typed none. The cause is boot time, not the screen read (READY
  boots: p50 3.6 s, p90 5.7 s; failures rise from 8% under 10/core to 44% at 10/core or more).
  New top lever for the `RELAUNCHED/UNPROMPTED` class: pass the owed prompt as a positional
  argument on lr-fire-resume's spawn, as `reso-resume-one:927-944` already does; stopgap, re-arm the
  quiet arm up to a 180 s wall bound. Also stop charging fallback C a second first-turn admission.
- **Gap 2, each capped session recovering itself from its own priority-31 tree**
  (`gap-2-decentralized-self-recovery-at-pri31.md`). Feasible, not built: the StopFailure hook
  already holds every input at the death instant, and a setsid'd descendant keeps priority 31.
  Blockers: the SELF recycle form never reaches the kitty-free SIGTERM exit, and the REMOTE form
  refuses a caller carrying the subject's session id. Estimated 2-4 min per session, all in parallel,
  with no reconciler pass, probe or placer. Needs code plus an operator switch file.
- **Gap 3, holds with no bounded release, and seat caps** (`gap-3-non-load-permanent-holds-and-seat-caps.md`).
  KMAX is 24 (since 10-04), not 8; at 24 the cap itself never blocked a measured sweep, but in 56%
  of sweeps the work count was unmeasured on every account. The seat cap fails through the WEIGHT:
  a mover heavier than KMAX can never be placed, and the weight counts subagent files written after
  the death. All 16 HELD:busy holds on limited sessions since 10-01 were false (14 the replayed-goal
  shape). **This corrects A8:** resumed leads do restart fan-out (12 of 18 weighted movers reached 5+
  concurrent subagents within 60 min; db755a94 started a 12-agent workflow 1 s after engaging), so
  "one seat for a resumed lead" is wrong. The levers are instead: bound the weight's window at the
  death (E4.1), clamp the weight below KMAX so no mover is unplaceable (E4.2), exempt a mover's own
  phantom on re-place (E4.3), count a limited session at rest after a quiet window (E1), and fix
  HOLD-COMPOSER bookkeeping (E2).
- **Gap 4, is the priority-31 fix valid at 30-40/core** (`gap-4-band-fix-validated-at-30-40-per-core.md`).
  Like-for-like, short priority-31 control-plane steps stay fast up to 68/core while the priority-20
  lanes are 4-11x slower already at 10-40/core; recycles fired from priority 31 had 0 kitty failures
  in 22 at 30/core or more, against 3 in 8 from priority 20. CPU-heavy work at 31 still slows at
  30/core or more, and no base-priority census exists above 28/core. Supports A1 (ship it without
  waiting for self-promotion to 37) and sizing every bound from the priority-31 p90 at 40/core.

## 8. Implemented (2026-10-20)

Four dispatched waves landed the levers below on `main`, each content-verified with its suites run.
The recovery services were reloaded at priority 31 at 07:23Z (`lr-band-reload.sh`: reconciler and
reset poller read `31T`; `recon/band.log pri=31 ok`).

| Wave | Levers | Landed |
|---|---|---|
| 1 | A1 rail at priority 31 (`ProcessType Interactive` on the reconciler and reset poller, per-pass band check that pages below 31, move census unclamped); A4 admission paced by a wall-clock token bucket (1 per 20 s, burst 6), no load term, drip on the wall clock | `07ce89a99` |
| 2 | A2 the move worker never waits for load nor ends `HELD:load`; A3 our probe timeouts (rc 124/137) and a refused socket with a live owner retry; resolver-unavailable, unreachable, wedged and composer-unreadable are TRANSIENT (backoff ≤300 s) | `9316d9842` |
| 3 | Gap 3: mover weight counted only up to the death and clamped to KMAX−1; a mover's own phantom refunded on re-place; HOLD-COMPOSER/HOLD-LOAD page at 900 s; quiet-window at-rest rule in `lr_recon/transcript.py` (the hf precheck already covered all 16 false HELD:busy runs via `c82a349ce`) | `9fc5964c3` |
| 4 | Gap 1: the owed prompt rides the claude spawn argv (the relay types nothing); the typed path waits up to 180 s for READY; fallback C skips a second first-turn admission for a gate-admitted relaunch | `a8ebaa7c0`, `a24255bf6` |
| 5 | Same root cause outside the rail, found by the rail lead: the backlog dispatcher ran `ProcessType Background` (PRI 4) and had fired 0 sessions since 10-17 because `claude-accounts --rank general` never fit its 20 s bound. Dispatcher plist to Interactive; `cc-wave-plan` retries a rank timeout once at 45 s (PRI-31 samples at load ~225: 2.1-8.1 s), then uses the last good rank within 600 s, only then reports WALL; dispatcher logs its band per pass | `9d6cd03ff` |

Not yet built: B1 (load harness and the guarantee tests of §5), B2-B8, C1-C2, D1-D2, and A7 (needs
an operator ruling). Gap 2 (each capped session recovering itself from its own priority-31 tree)
is the largest remaining lever.

### 8.1 Remaining levers: disposition (lead pane 187, from 2026-10-20 20:30Z)

The remaining levers are executed by `docs/plans/LR_SUSTAINED_LOAD_IMPL.md` (landed `dc13d1a09`, designs
under `impl/`). Each row below ends LANDED (sha on `main`, content-verified, converged, suites green)
or FILED (operator packet `cc-decide` or step `cc-backlog needs`, with its id). A row reading
IN FLIGHT names the wave that will close it. Decision packets were filed at class B, with a deadline
and a default, as the plan specifies.

| Lever | State | Where |
|---|---|---|
| A5 false HELD:busy on a `/goal` record | LANDED | `c82a349ce` (before wave 1) |
| A8 one seat for a resumed lead | LANDED as superseded | replaced by gap 3's weight levers, wave 3 `9fc5964c3` |
| A7 drive cohort members that turned limited while queued | FILED | packet `4ffc4e1e5f1c` (lane order; default: reconciler first, poller after 10 min). Code: W5 LANDED `a294d2bcb` (`fef98e423` + 2 fixups; reconciler first, poller after a bounded wait, move lane lets go; Part A in shadow until ruled), W13 to come |
| D1 re-pick honours the router's held verdict | FILED | packet `0223cae3d185`. Code: W15, lands at mode `off` |
| D2 warning-band shedding | FILED | packets `76a584cc935b` (late-band idle shed, D2b) and `c9a05672e692` (at-the-wall idle fan-out, D2a); step `f259e20643bf` (shadow switch). Code: W13, W16, shadow only |
| B8 kitty hygiene | FILED | steps `d25661ba57f1` (App Nap key), `7e912ef257cb` (fd headroom), `1c94119a286d` (planned kitty restart); packets `74b9bd774c40` (official 0.49.2), `1ef91f32a58c` (in-kitty fd watcher), `1c7000af9e41` (in-process App Nap test). Agent tools LANDED W7 `29fa7e597` (`scripts/kitty-hygiene.sh`, fd-headroom kitten, App Nap reader); router-cache producers at band 31 since the operator ran RK (step `626ed25b243c`, done 2026-10-21) |
| C1 credential flip | FILED | packet `745e0fdc78e6` (wait for the next wall); steps `bd40ec7f3d4f`, `156c1aa935e7` (leftover `.credentials.json` in two config dirs) |
| Gap 2 self-recovery from the session's own priority-31 tree | FILED | packet `4ab193daae88` (scope ruling). Code: W17, behind its measured entry trigger |
| Typed-relaunch load hold (plan closure TR) | FILED | packet `db44ab0ebc55`. Code: W12b part 2 after the ruling |
| Pass-boundary restart request (A6 lever 11) | FILED | packet `5353dd6e8277` |
| B1 harness load and windows | FILED | packets `4eee30ac4de4` (background top-up load), `75bb72581c54` (main-terminal windows) |
| Reconciler reload batches R1-R5, router-cache band RK | FILED | R1-R3 and RK RAN (steps `b8bbc2317870`, `626ed25b243c`, closed done 2026-10-21; reconciler pid 70188 at band 31, heartbeat carries `pass_at`); R4 (after W11+W13) and R5 (after W14) are filed as new steps when their waves land |
| B1 load harness and guarantee tests | IN FLIGHT | hermetic tier LANDED W1 `e6713c4da`..`2d99d8e93` (Tier G simulation, rig, no-load-wait lint; 783 OK, bats 1..36); live tier LANDED W4 `da293caf2` (two concurrent arms, in-path bands, verdict with power; bats 1..58, 34/34 mutants; its pair run owed); rig completion W4b to come |
| A6 restart safety | LANDED | W2 `1eb5548ac` + `45b8bbfa9` (claim re-stamped to the adopted actuator, exit codes survive a restart); 667 unittest OK, bats 1..21; live once operator reload R1 (`b8bbc2317870`) runs; Tier-L guarantee9 pair owed after W4 |
| B4 cheap `--place` | LANDED | client half W3 `c79df708d` (0.15 CPU-s at priority 31, was 3.0-3.3); holds map W10 `52fc6f2b8` (864 unittest OK, 10/10 mutants); live after reload R3; Tier-L pair owed after W4 |
| B6 telemetry | LANDED | W6 `8f4ab29f9` + `748186142` (`recon/telemetry.jsonl`, `cc-lr status --rail`); 743 unittest OK, bats 1..39; live after reload R2; Tier-L cure run owed after W4 |
| B7 pass-scoped `now` audit, and C2-lite (typed delivery retries instead of escalating) | LANDED | W8 `72fc09748` (right clock per decision, no actuator load term, every hold reason mapped); 783 unittest OK, now-audit 1..26, Tier G 1..11, G1 lint 1..9; live after reload R2; Tier-L pair owed after W4 |
| B2 bounded pass (stage 1) | LANDED | W9 `784682330` (pass measured 342.7 s against its 799 s cap, 1426 s with W9 off; 851 unittest OK) + `9700c6213` (bash swap-slot race: 7-11 holders of 6 slots before, 0 in 60 trials after); live after reload R3; stage 2 dropped with a re-open trigger (plan § Dropped) |
| B3 per-record deadline (rescoped) | LANDED | W11 `b54efff86` + `c8c922dc8` + `ed6f47072` (`Record.deadline_at` shifted across a sleep, per-record deadline, the move lane yields boot slots to overdue records); 925 unittest OK, bats 1..46; live after reload R4; Tier-L guarantee9/30 pairs owed |
| B5 kitty off the pre-commit path | IN FLIGHT | W12 LANDED `c85b7063b` (kernel pane identity, one-window probe, in shadow; flip to `on` after 30 agreeing shadow rows); W14 (kitty-free census binding) to come |
| C2 socket transport for the owed prompt | FILED | full transport dropped by the plan (reviewer: "works as specified" ≈ 0%); C2-lite LANDED in W8 `72fc09748`; re-open row `649ebd06939f`, parked not-yet-true until its trigger fires |

Safety precondition wave W0b (test hermeticity, reaper whitelist, hook cwd, and the same cwd
import hijack in `lr-predicate.sh`) LANDED `9f005ae66` + `b24389ff7` before any slot started.

## Appendix A. Refuted claims and levers (dropped)

| Item | Axis | Why it was dropped |
|---|---|---|
| "Only 3 of 9 recovered; the brief's 5 overcounts" | 02 F1 | REFUTED. By the axis's own definition (first engaged turn on the target), e80b61f4 and 7aae55e1 count, and their transcripts show real work by 04:16 |
| "A PRI-31 self-recycle took 133 s vs 7-8.7 min for reconciler (PRI 20) recycles" as band evidence | 07 F6 | REFUTED as stated. A reconciler attempt (pane 38) engaged in 128 s. The numbers were misattributed, and load differed. The band case rests on the controlled A/B (§3.1) |
| Wrapping each `kitten @` call in a Python priority-raising shim (`cc-band-exec`) | 04 L3 | REFUTED for that part. The shim's own interpreter starts in the parent's band (0.08-15 s) and costs more than the 0.05-0.08 s call it wraps |
| "A PRI-31 actor would barely have waited (4-6 runnable at 31)" | 04 §3.1 | REFUTED. `ps` shows decayed priority. By base priority the default band held 12-48 runnable threads in all 8 samples |
| "The wall hour was the worst hour" | 10 F7 | REFUTED. 18Z (median 31.0/core) and 12Z were worse. The premise makes troughs irrelevant anyway |
| "A latency-paced window cannot starve, unlike the CPU brake in front of the drip" (the comparator) | 10 L6 | REFUTED. The brake opens after 20 s, and only 2 of 11 refusals were `cpu`. The useful part ("replace the probe") is in A4 |
| "A placer timeout means no move is dispatched that pass" | 01 F5(a) | REFUTED. The pass that started 02:46:14 still dispatched d7eb73d2, because records already PLANNED are skipped by the placer |
| "The CPU brake refused every pass" (the brief) | 01, 02, 03, 05, 09, 10 | Not what the log shows: 8 probe-error, 2 cpu, 1 restore-r, logged only on a change of reason. The brake capped admissions at one per pass rather than refusing every pass |

## Appendix B. Considered and not recommended

| Item | Axis | Reason |
|---|---|---|
| Credential-flip designs A (copy a grant into another directory's item), D (claude-swap copy-back) and G (apiKeyHelper) | 08 | A and D: the refresh-token rotation race leads to `invalid_grant`, which erases the credential and strands an account. G: OAuth through a helper is unsupported and disables Remote Control |
| A second kitty socket; TIOCSTI tty write; a new kitty process per relaunch | 07 | One `listen_on`, one main thread. XNU refuses TIOCSTI to a non-controlling-tty caller. A new process loses the layout and costs 100-180 MB each. The staged successor is already the kitty-free relaunch |
| Fallback to `kern.memorystatus_vm_pressure_level` alone when the probe times out | 05 L3 | Discards compressor segments, the one memory term with panic history (`capacity-admit.sh:236-252`). Use the compressor-sentinel file instead (A4) |
| A per-account SRE throttle; a cohort-local restore budget | 05 L8 | No 429 telemetry, and no target account failed. R produced one refusal costing 13 s |
| Replacing load1 with a default-band contention threshold | 09 L3, 04 L4 | Under the premise, deleting the load term is simpler and safer than deriving a new threshold. The `ps`-based census mislabels decayed threads |
| Adaptive RFC 6298 bounds everywhere | 06 L7 | With 13-44x run-to-run spread, the result sits near its ceiling. Little gain after A1 and B2. Keep it only for the placer and probe, if at all |
| Demoting the fleet's background work; deploy-live single-flight; async hooks; a longer lead-supervisor sweep; Spotlight and Dia changes | 04 L8, 09 L4-L7 | These reduce load or free CPU for sessions. Under the premise the box refills, so none makes recovery reliable, and some only make the load figure look smaller. Worth doing for CPU (deploy-live duplication and the hook fork storm are real waste), but not as recovery levers |
| Retuning `URGENCY_EXP`/`WEEKLY_FLOOR`; a Stop-hook nudge asking sessions to self-switch | 10 | Operator rulings 2026-09-22 and 2026-10-17; VOLUNTARY_ACCOUNT_SWITCH.md chose "NOT a Stop-hook nudge" |

## Appendix C. Sources and the commands run for this synthesis

**Axis files.** All in `docs/research/lr-sustained-load-2026-10-20/`, each read in full, including its "## Skeptic review" section: `00-lead-observations.md` through `10-proactive.md`.

**Rules read.** `.claude/rules/agent-operating-lessons.md` and `agent-operating-lessons-situational.md`.

**My own read-only checks, about 05:00-05:10Z:**

| Command | What it established |
|---|---|
| `git log --oneline -15 main` | `58885750c` landed after the daemon started |
| `sed`/`grep` of `admit.py`, `__main__.py`, `classify.py`, `settle.py`, `plan.py`, `lr-move-worker.sh`, `handoff-fire.sh` at `58885750c` | Line numbers cited in §3-§4 |
| `grep -n ProcessType scripts/limit-recover/*.plist launchd/staged/com.reso.lr-move-kick.plist` | Only the staged plist sets one |
| `ls ~/Library/LaunchAgents` | No lr-move-kick |
| `ps -M -p 51148` | `20T` |
| `ps -axo pid,ppid,pri,etime,time,command \| grep -E 'lr_recon\|lr-reset-poller'` | The rail's processes and their bands |
| `tail -3 recon/restarts.jsonl` | Restart times |
| `tail -n 400 recon/events.jsonl` (filtered) | Placer timeouts at 04:40:51 and 04:48:58Z |
| python read of `recon/sessions/<sid>*.json` | States at 05:09Z; db755a94 weight 19, ETA 11:55:01Z |
| `sysctl -n vm.loadavg` | 179.91 at 05:09:22Z |
| `sed -n 1,40p tests/rig/lr-recon-rig.sh` | The rig's isolation and supervisor |
| `grep -n -E 'now *- *…' lr_recon/*.py` | The B7 candidate list |

Nothing was typed, signalled, loaded or edited. The synthesis step's Write of this file was refused; the lead saved its returned text here unchanged and added §7.