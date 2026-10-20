# 01: census of the gates on the limit-recover path under permanent high load

Axis: every gate on the limit-recover path keyed on CPU load, load average, active-session count,
memory, or a timeout. The question for each one is how it behaves when load stays at 15-40 per core
**forever** (operator premise: load never falls, so a design that waits for it is wrong).

**Source of truth.** Code is cited at the live checkout
`/Users/chrisren/Development/claude-infrastructure` on `main` at `20368fc85`, which is what `~/.claude`
runs. This worktree (`60c87719f`) is 3 commits behind it on `admit.py`, `plan.py`, `__main__.py` and
`settle.py`. All paths below are relative to that checkout unless they start with `~`.
Live state was read only. Nothing was typed, signalled, loaded or run that writes state.

**Number labels.** *measured* = read from a named file or command. *estimated* = derived, with the
method given.

---

## 0. TL;DR

1. **The recovery rate is about one first turn per reconciler pass. A pass takes 7-14 minutes at
   this load.** `Admission.cpu_ok` (admit.py:150) admits by "20 s since the last admission". But
   `now` is taken once per pass (`__main__.py:1619 now = time.time()`) and that same value goes to
   every `decide()` in the pass. Once one member is admitted, `now - last_admit_at == 0` for every
   other member of that pass, so they are all refused `cpu`. The "anti-starvation floor" is
   therefore one admission per **pass**, not one per 20 s. *Measured*: pass-start timestamps of the
   dispatching passes (launch.log `recon-*` spawn rows, which carry the pass's `now`) are 02:46:14,
   02:54:50, 03:08:24, 03:15:54, 03:23:43, 03:43:17, 03:53:21, 04:00:02, 04:09:35, 04:13:45Z, i.e.
   gaps of 4-20 min. The pass that started at 02:46:14 did not reach dispatch until 02:54:13 (its
   `jobs-recorded` wall time), 8 min in. *Estimated*: 9 sessions at 1 per 8-14 min pass is 72-126
   min before any retry. That matches the observed 1 h 43 m for 5 of 9.
2. **The probe's 30 s bound was the only thing refusing.** The probe's real answer at that load was
   ADMIT. *Measured*: every reconciler probe that finished during the incident wrote an IDL `admit`
   row (`~/.claude/autonomy/idl.jsonl`, caller `lr-reconciler`, 03:15:01-04:15:43Z: reclaimable
   21.9-26.6 GB against a 4 GB floor, segments 9.4-11.4% against 50%). The refusals were the runner's
   30 s bound (`admit.py:67`). Commit `ed5614054` records that "by hand the same probe answered 0 or
   9 in 1.5-4.9 s (18.3 s under taskpolicy -c utility at load 154)". The daemon's plist has no
   `ProcessType` (`scripts/limit-recover/com.reso.lr-reconciler.plist`), and `man launchd.plist` says
   that when it is unspecified "the system will apply light resource limits to the job, throttling
   its CPU usage and I/O bandwidth". Hypothesis, strongly indicated but not proven: the daemon and
   its children are throttled, and that turns a 2-5 s probe into a timeout.
3. **The drip, the only bounded escape in the reconciler, comes after the CPU brake in `decide()`.**
   (`admit.py:278` `cpu` returns before `:282` probe/drip.) A `cpu` refusal does not count toward
   the drip's run. The probe also still runs, and still pays up to 30 s, on the pass where the drip
   then admits (`:282`). The drip is itself one per 30 s per cohort, so it too is one per pass.
4. **The idle move lane (`cc-lr move`/`rotate`) blocks without bound at ≥20 per core.**
   `lr-move-worker.sh:335-358` waits `max(600, --until-idle)` s for load to drop below 20/core and
   then finishes `HELD:load`, which is a final NOTMOVED. *Measured*: batch
   `20261020T024813Z-next3-next2-78304`, 4 of 4 rows `HELD:load — load 36.23-38.02/core … for
   605-613s`. Batch `20261020T030423Z…` waited 1667 s in `load-wait` (events.jsonl stage times
   1792465595 → 1792467262) and moved only once load dipped. This worker gate also **drifted from
   the handoff-fire precheck it claims to mirror**. Since Wave S, that precheck does not gate a move
   whose relaunch is staged (`handoff-fire.sh:13836-13837`). Every reconciler actuator log in the
   same window shows `precheck load: not gated (the relaunch is staged in the pane,
   keystroke-free)`.
5. **The placer's timeout is pinned at its 120 s cap for any load ≥16 per core** (`plan.py:312`
   `30 × load1/(4·ncpu)`, capped at 120). *Measured*: 6 of 17 `place` events in the incident were
   `rc=124 cause=timeout`, and the answered ones took 18.7-106 s. A timeout leaves no placement, so
   that pass dispatches nothing new. There is no fallback placement.
6. **Kitty-latency verdicts escalate as DETERMINISTIC.** `HELD:pane:resolver-unavailable`,
   `HELD:unreachable`, `HELD:wedged` and `HELD:load` fall through `classify.map_notmoved`
   (`classify.py:125-153`) to `("DETERMINISTIC","")`. A second identical failure sets `ESCALATED`
   (`classify.py:182`), which sleeps 15 min (`REARM_S`). After 4 re-arms the record ends
   `IMPOSSIBLE` and is released (`__main__.py:762`). When load is permanent, these timeouts recur on
   the same fingerprint, so this ends in giving up, not in waiting.
7. **Fixed bounds against stages that already scale with load.** The admission-token TTL is a fixed
   1020 s (`capacity-admit.sh:1043-1052`), while the stages it must outlive scale up to 4x
   (`hf_load_scaled`, `handoff-fire.sh:4915`). *Measured*: d7eb73d2's token was redeemed **1000 s
   old against TTL 1020 s** (IDL lr-fire-resume row 03:52:40Z), 20 s short of a post-transplant
   `token-stale` refusal. Separately, three load-scaling hooks exist and are never called:
   `Clock.load_multiplier` (clock.py:156), `BootSlots.on_wave` (admit.py:390) and
   `T.PHASE_DEADLINE_S` (types.py:135). Grep finds no caller outside tests.

Correction to the brief: "CPU brake refused every pass" is not what the event log shows. The
`admit-refused` events in the incident window are **6× `probe-error`, 2× `cpu`, 1× `restore-r`**
(*measured*, recon/events.jsonl). Those events are de-duplicated, logged only when the reason
changes (`__main__.py:1229-1237`), so they undercount standing refusals. Read together with the
pass-scoped `now`, the CPU brake was not refusing every pass. It was capping each pass at one
admission.

---

## 1. Order of gates a limited session crosses

```
reconciler pass (__main__._run_pass, :1614)
  observe()  ── ps bound 20-40 s, 90 s budget  → ps degraded ⇒ ABSTAIN whole pass      [G7]
             ── kitty @ ls 5 s per socket      → pane state degraded                     [G9a]
  _plan()    ── claude-accounts --place, 30-120 s (120 s at ≥16/core) → rc124 ⇒ WAIT_DATA [G4]
  _dispatch()
     may_actuate: workers-cap 16, backoff, ESCALATED(15 min), wake-guard                 [G15,G6]
     _admit: BootSlots (6)                                                               [G14]
             Admission.decide:  restore-r (count, in drip run)                           [G8]
                                cpu brake  (load1/ncpu vs max(2.5,L_open); floor 1/pass) [G2] ← ahead of the drip
                                pacer (3/acct, 20 s)                                     [G13]
                                probe (bash, 30 s bound) → drip after 3, 1/30 s/cohort   [G3]
             mint token (bash, 30 s bound)
actuator (lr-handoff → handoff-fire --recycle → watcher → lr-fire-resume)
  precheck: load 20/core (only for typed relaunch; staged ⇒ "not gated")                 [G11]
            pane resolver (kitty ls 10 s) / kitty probe (3 s connect, ≤5 tries/120 s)    [G9b]
            composer read (180 s draft wait)                                             [G9c]
  transplant …
  watcher pane probe (10 s, single shot) → ABORT after transplant                        [G9d]
  commit load hold 24/core (bypassed when successor staged)                              [G11]
  stage waits ×min(4,1+lpc/10)                                                           [G18]
  in-pane cc_capacity_admit: token (TTL 1020 s fixed) or budget 3                        [G10,G12]
reconciler again: C (continue prompt) = another FIRST_TURN decide()                      [G2,G3]

idle move lane (cc-lr move/rotate → lr-move-batch → lr-move-worker)
  admit section 900 s, memory probe (no escape), load_wait 20/core ≤max(600,UNTIL) → HELD:load,
  slot-wait 600 s                                                                         [G1,G16,G17]
poller (lr-reset-poller): probe with queue clock 2700 s                                   [G12]
```

Every LIMITED recovery goes through the reconciler while it is live: `cc-lr recover` queues a
request instead of firing (`bin/cc-lr:679-683`, `lr_recon_live` → `cl_recon_queue`).

---

## 2. The census table, most blocking first under permanent 15-40 load per core

Legend for **Under permanent load**: **FOREVER** = refuses on every evaluation and has no escape,
or its escape ends in a final verdict. **BOUNDED** = refuses, but a count or clock releases it.
**THROUGHPUT** = admits, but caps the rate. **DEGRADE** = the bound grows with load. **INERT** =
does not bind at this load, or is bypassed. **Escape?** names the bounded release. **Ahead of
escape?** says whether the gate sits in front of the bounded release and so makes it unreachable.

| # | Gate (file:line) | Keyed on | Threshold / bound | Protects (quoted justification) | Under permanent 15-40/core | Escape? | Ahead of escape? |
|---|---|---|---|---|---|---|---|
| G1 | **Move-lane load wait**, `scripts/limit-recover/lr-move-worker.sh:308-358`, `:420-422` | load1/ncpu | `HF_PRECHECK_LOAD_PER_CORE` 20 (≤ commit 24), waits `LR_MOVE_LOAD_WAIT_S` = max(600, UNTIL) s, polls 15 s | "/exit typed at ~45 runnable per core stranded pane 44, 2026-10-09 … on a loaded box every move paid admit + confirm + unconfirm … and failed anyway" (`:299-306`) | **FOREVER** whenever load stays above 20/core. Finishes `HELD:load … nothing touched`, NOTMOVED, final ("only HELD:unreachable is retried", `:314-315`). It re-waits even after a slot (`:420`). *Measured* 4/4 rows held 605-613 s at 36-38/core | none (no drip, no budget) | It is the first gate of the lane. It also lacks the staged-successor exemption that its source `hf_recycle_load_gate` gained (`handoff-fire.sh:4146`, `:13836-13837`) |
| G2 | **Reconciler CPU brake**, `scripts/limit-recover/lr_recon/admit.py:41-42,150-157,278` with `__main__.py:1619` | load1/ncpu vs L_open | `max(2.5, L_open)` per core, where `L_open = max(load1,load5)/ncpu` frozen at ACTIVE entry (`:121-123`). Floor: 20 s since last admission (or since entry) | "§C6 gate 2 … at least one admission per 20 s, whatever the load" (`:42`) | **THROUGHPUT ≈ 1 admission per pass** whenever load1/ncpu > L_open, which is about half the time when load swings around the entry level. `now` is fixed per pass, so the 20 s floor is reached only on the next pass. Pass = 7-14 min (*estimated* from launch.log pass timestamps, §0.1) | own floor (1/pass) | **YES**: it returns `cpu` before the probe and drip (`:278` vs `:282`), and a `cpu` refusal does not increment `refusals[cohort]` |
| G3 | **Probe subprocess bound**, `admit.py:62-73` (`timeout=30`), `:189-211`; drip `:43-45,282-298` | wall-clock timeout (load-starved child) | 30 s per `bash -c 'source capacity-admit.sh; cc_capacity_probe'`. Drip after `DRIP_AFTER`=3 refusals, then 1 per `DRIP_EVERY_S`=30 s per cohort | "The bounded gate: probe refusals never spend the library's own refusal budget … After 3 consecutive probe refusals … overridden at most once per 30 s ('drip')" (`:13-16`) | **BOUNDED + latency tax.** Each first-turn decision costs up to 30 s inside the serial dispatch loop (*measured*: refusals at 02:43:56, 02:44:27, 02:44:58Z, 31 s apart). A timeout is a refusal (`probe-timeout` since ed5614054). The drip opens after 3 such refusals, but the probe still runs on the drip pass, and the drip is 1 per pass (pass-scoped `now`). The probe's verdict when it did answer was ADMIT (§0.2) | drip | no (it is the escape's own input) |
| G4 | **Placer bound**, `lr_recon/plan.py:55,312-319` (`place_timeout`); call `__main__.py:977-978`; `keep_waits` `plan.py:337-346`; `KEEP_MAX_MISSES=3` `:54` | load1/ncpu → timeout | 30 s × load1/(4·ncpu), min 30, max 120 → **120 s at ≥16/core**. Runs once per lane (general, fable) per pass | "The 04:00Z non-answers ran at load1 264-968 on 10 cpus, where a 30 s bound starved" (`:313-314`). `--max-wait 0` "cache-only: without it load_cfg forks cc-claude-bin (10 s bound)" (`:270-271`) | **BLOCKS that pass.** rc 124 → every mover gets `wait-data` → WAIT_DATA; a mover already waiting keeps its wait for ≤3 misses, then WAIT_DATA (max-age 120 s page, `types.py:118`). *Measured*: 6 of 17 `place` events rc=124 at load1 176-363; answered ones took 18.7-106 s. A pass with no placement dispatches no new move. Up to 240 s of each pass is spent here | none: no fallback ranking from the last good answer or the cache | **YES**: it runs before `_dispatch`, so before admission and before the drip |
| G5 | **Pass length itself** (sum of G3, G4, G7, G9a and the per-actuator bounds), `__main__.py:1614-1700` | timeouts | ps 20-40 s ×2 tries within 90 s; place ≤120 s ×2 lanes; probe 30 s × members; mint 30 s; assign-many 30 s (`plan.py:455-461`); kitty ls 5 s/socket; snapshots 20 s (`__main__.py:533`) | various (see rows) | **THROUGHPUT** multiplier on G2 and G3. Every "per pass" limit becomes "per 7-14 min" | n/a | n/a |
| G6 | **Escalation of kitty/load HELD verdicts**, `lr_recon/settle.py:61,130-140`; `classify.py:125-153,177-185,23,26`; `__main__.py:757-770` | timeout-derived verdicts | `HELD:pane:resolver-unavailable`, `HELD:unreachable`, `HELD:wedged`, `HELD:load` → DETERMINISTIC. 2nd identical → ESCALATED; re-arm after `REARM_S`=900 s; after `REARM_CAP`=4 → terminal `IMPOSSIBLE` | "a deterministic failure used to re-arm every 15 min forever, and the record kept owned/<sid> … After this many automatic re-arms it is released" (`classify.py:24-26`) | **BOUNDED, but it ends in giving up.** Under a standing slow kitty: RETRY(10 s) → ESCALATED → 15 min sleeps ×4 → IMPOSSIBLE ("released to the other recovery paths"). Only `…unreadable` is rescued to TRANSIENT (`settle.py:138`). *Measured*: d7eb73d2 attempt 1 `HELD:pane:resolver-unavailable` → `R rc=6 → RETRY/BACKOFF` (03:19:19Z) | REARM (15 min) | sits in `may_actuate` (`act.py:473-474` "escalated") before `_admit` |
| G7 | **ps census bound + abstain**, `lr_recon/observe.py:81-101` (`PS_BOUND_S` 20, `PS_BOUND_MAX_S` 40, `PS_BUDGET_S` 90); `untrusted` `:654-670`; `__main__.py:1633-1637` | load/ncpu → timeout | 20 × (1 + lpc/10), cap 40 s per call (40 s at ≥10/core), 2 tries, 90 s budget | "W7a: at load 87-116 the census read '0 claude procs · degraded: ps' — ps failed under a flat 20 s bound" (`:78-80`) | **BOUNDED per pass, can repeat.** A pass whose ps fails decides nothing (no move, close, wake). *Measured*: 1 abstain (03:58:07Z, "timed out at 40s; ps budget spent"). Under permanent load it is a per-pass coin flip | next pass | **YES**: it stands before everything in the pass (`:1630-1633` comment) |
| G8 | **Restore budget R**, `admit.py:107-140,262-276`; ceiling `__main__.py:1061-1065` (`CC_ADMIT_ACTIVE_CEILING` 8) | active-session count | `active + unredeemed + 1 ≤ R`, R = max(8, A_open + C_open) frozen at ACTIVE entry; `_active_now` = held and not at rest (`__main__.py:1054-1058`) | "`active` is every mid-turn session on the machine, so once the rest of the fleet is busier than it was at ACTIVE entry this refuses on every pass … one member refused from 1791856395 until its reset" (`admit.py:263-271`) | **BOUNDED: 3 passes**, counted per pass (`over_at`). After a clean (non-drip) admit the run resets to 0 (`:297-298`), and the next over-budget member pays 3 passes again. *Measured*: `restore-r (active 18 + in flight 4 + 1 vs R 22)` 03:15:41Z. With 24/7 maximum concurrency, "over" is the normal state | drip run | no: it now counts into the drip run (fixed 2026-10-13) |
| G9a | **kitty @ ls in observe**, `observe.py:233-252` (`timeout=5.0`), composer read `:425-450` (5 s) | timeout | 5 s per socket, no retry | §C3.2 "any failure ⇒ None and kitty:<sock> degraded" | **DEGRADE→BLOCK.** Pane state unknown for that socket for the pass. The composer read returns "unknown", which feeds HOLD-COMPOSER | next pass | ahead of dispatch |
| G9b | **Precheck pane resolver / kitty probe**, `scripts/handoff-fire.sh:2827-…` (`hf_remote_pane_term`, `kitty @ ls` under `HF_TIMEOUT_S` 10 s, `:1090`); `kitty_socket_accepting` 3 s `:1459-1460`; `hf_recycle_kitty_probe` `:1566-1592` (5 tries, 5/10/20/40 s backoff, `HF_KPROBE_BUDGET_S` 120); verdicts `:13806-13817`, `:13854-13859` | timeout | 10 s ls, 3 s connect, ≤120 s retry budget when detached (`LR_INPLACE_AWAIT=0`, set by the reconciler `act.py:65`) | "kitty 73832 alive 3d8h … load 197 on 10 cores, `kitty @ ls` returning `read unix: i/o timeout`" (`:2860-2864`); "43e6eb4b's actuate held HELD:unreachable on one … 3 s probe … the same kitty answered 48 s later" (`:1452-1455`) | **BOUNDED per attempt → feeds G6.** *Measured*: d7eb73d2.1.R.log "PARKED: REMOTE-PANE-RESOLVER-UNAVAILABLE … HELD:pane:resolver-unavailable" | retry by next pass, then G6 | before transplant |
| G9c | **Composer gate**, `handoff-fire.sh:19621` (`CC_RECYCLE_DRAFT_WAIT` 180 s), `:5483-5484`, `:5684` | timeout (screen read) | 180 s for a readable, empty box; "unreadable static" holds at once | "typing /exit needs a composer proven empty" (`:5484`) | **BOUNDED** → `HELD:composer-unreadable` → TRANSIENT backoff 10/30/60/120/…300 s (`classify.py:17-18`). *Measured*: 7aae55e1.1.R.log | backoff | before transplant |
| G9d | **Watcher pane probe after transplant**, `handoff-fire.sh:19958-19977` (`await_pane_proof`, max ticks `(HF_TIMEOUT_S+3+5)*5` `:2195`) | timeout | one 10 s listing | "a failed listing, typically the 10 s bound firing while kitty's socket is stalled — that is NOT a missing pane" (`:19977`) | **ROLLBACK.** The transplant is aborted after it has begun. *Measured*: db755a94.1.R.log "recycle ABORTED … HELD:unreachable … lr-transplant --phase abort rc 0". That left the PRE-MOVE/None record (RECON-DEFECT ×4) that `20368fc85` now re-offers | single shot; re-drive since 20368fc85 | after the admit (token spent) |
| G10 | **Admission-token TTL**, `scripts/lib/capacity-admit.sh:1043-1057` (draft 180 + shell 600 + boot 180 + slack 60 = **1020 s**); redeem `:1325-1365` | wall-clock age | 1020 s fixed. Past it, `token-stale` is a terminal rc 9 **in the pane, after the transplant** | "TWO-SIDED … ≥ the stages it must cross (780 s) … ≤ handoff-fire's whole-recycle bound (1200 s)" (`:1029-1032`) | **CLIFF.** The stages it covers scale ×min(4, 1+lpc/10) (`handoff-fire.sh:4915`, `:12609-12610`) but the TTL does not, so at ≥30/core the stage bounds are 4× and the TTL is 1×. *Measured*: d7eb73d2 token redeemed at **1000 s of 1020 s**; e80b61f4 458 s; 7aae55e1 200 s (IDL 03:52:40, 04:03:52, 04:14:35Z). No token-stale row in the window (*measured*: `grep -c token-stale` = 0) | re-fire mints a fresh token (and pays G2/G3 again) | after the transplant |
| G11 | **Recycle load holds**, precheck `handoff-fire.sh:4131-4139` (20/core), commit `:4117-4123` (24/core), gate `:4141-4153`, commit call `:19365-19369`, precheck call `:13836-13852` | load1/ncpu | precheck 20, commit 24 per core; bypassed when "a successor of ours is staged" | "F1 (pane 44, 2026-10-09) typed /exit at ~45 runnable per core … failed 16 times and stranded the pane" (`:4093-4096`); "33 of 33 typed relaunches above 8/core submitted first try … typing … measured clean up to ~32/core" (`:4107-4111`) | **INERT on the reconciler path** while successor staging works: every incident actlog reads `load: not gated (the relaunch is staged …)`. **FOREVER** for a typed relaunch at ≥24/core: `hf_recycle_hold load … re-run once the load falls` | none for a typed relaunch | precheck: before transplant; commit: after the confirm |
| G12 | **In-pane / poller capacity admission**, `capacity-admit.sh:1294-1760`; spend `:1766-1851`; lr-fire-resume `lr-fire-resume.sh:903-907`; poller `lr-reset-poller.sh:885-905` | active count (CPU-active ≥0.25 core vs floor(ncpu×0.8)=8, or R), memory (headroom 4 GB, segments 50%/90%), load term (2.0/core, **off on every lr caller**) | budget 3 consecutive refusals (`CC_ADMIT_BUDGET`); queue clock `LR_CAPACITY_QUEUE_MAX_S` 2700 s | "No gate on an actuation path may be unbounded" (`:31-33`) | **BOUNDED.** The load term is off on all lr callers (`lr-lib.sh:517,534`, `admit.py:196`, `lr-fire-resume.sh:905`, `lr-reset-poller.sh:896`). The active term is standing-over under 24/7 concurrency, so the poller waits **45 min** per queued wake, and a fresh in-pane evaluation costs ≤3 runs. Memory was not binding (§0.2) | budget-expired / queue-expired | n/a |
| G13 | **Per-account pacer**, `admit.py:43,160-183,280` | count | 3 submitted-not-ENGAGED per target account, self-release 20 s | "§C6 gate 3 … a cohort that resets at one instant spreads over a minute" (`:76-79`) | **INERT** at 1 admission/pass (G2 binds first). Like G2 it uses the pass `now`, so it is ≤3 per account per pass | self-release | yes (ahead of the probe), but never the binding one |
| G14 | **Boot slots**, `admit.py:302-410`; `__main__.py:1105-1106` | count | START 6, cap `LR_BOOT_MAX` 12; AIMD "halve on any boot over 45 s" | "Boots are the resource that failed at load 40+" (`:306-307`) | **INERT**: fixed at 6. `on_wave` (`:390`) has no caller (grep `on_wave` → only its definition), so the designed load response is not wired | n/a | ahead of decide |
| G15 | **Workers cap**, `act.py:477-478,539` | count | `LR_RECON_WORKERS` 16 live actuators | D1.12 "the only concurrency cap used to be LR_RECON_WORKERS (16)" (`__main__.py:1101`) | **INERT** at this cohort size | n/a | ahead of admit |
| G16 | **Move-lane memory probe**, `lr-move-batch.sh:225-228`, `lr-move-worker.sh:410-417`, `lr-lib.sh:499-538` (`lr_capacity_probe_corrected`, segments 90%) | memory | segments ≤90% (swap), headroom ≥4 GB; active/load/reserve off | "Every caller of this probe is a SWAP … MEASURED 2026-10-04: 12 account moves refused at 60.5% segments, every one of them net-zero" (`lr-lib.sh:490-494`) | **INERT** at measured memory (9-11% segments). Would be **FOREVER** under sustained memory pressure, because a probe never spends budget, so it has no escape | none | yes (batch-level refuse) |
| G17 | **Move-lane slot and admit section**, `lr-move-worker.sh:401-405` (`LR_MOVE_SLOT_WAIT_S` 600, width 4); `lr-move-batch.sh:137-174` (`LR_MOVE_ADMIT_WAIT_S` 900) | timeout / count | 600 s, 900 s | "under load that was ~6.6 s, so '90s' was 599-600 s of wall time" (`lr-move-batch.sh:132-136`) | **BOUNDED** → NOTMOVED "slot-wait" / "another batch held the admit section". Slots are shared with the reconciler's boot slots (`admit.py:310-315`) | none (final) | after G1 |
| G18 | **Load-scaled recycle stage bounds**, `handoff-fire.sh:4915-4917` (`hf_load_scaled`: ×min(4, 1+lpc/10)); claim `:12434`, rails `:12468`, boot `:12609-12610`; echo deadline `:4626-4628`; cc-lr self-wait `bin/cc-lr:335-342` (900 × min(4, 1+lpc/5)) | load1/ncpu | ×2.5-4 at 15-40/core | "under load the interpreter start … overran" and similar | **DEGRADE** (as designed) | n/a | n/a |
| G19 | **Reconciler in-flight bound**, `__main__.py:55,842-861` | timeout | 600 s relaunch gap with no holder → DETERMINISTIC failure | "§4.4: a relaunch gap past its bound with no holder is a failure, not a flag" | **FIXED**: not load-scaled, and `Clock.load_multiplier` (clock.py:156, "process bounds scale by max(1, load1/ncpu/2)") is never called. Feeds G6 | REARM | n/a |
| G20 | **Watchdog**, `scripts/limit-recover/lr-recon-watchdog.sh:78-88` (STALL_AGE 180, STALL_MAX 900, SLOW_MAX 3600); restarts reset in-memory `Admission` | progress / CPU | 900 s frozen with no CPU, 3600 s regardless | "a live-but-stalled holder" (plist comment) | **INDIRECT.** Admission state (drip run, entered_at, pacer) is plain in-memory (`admit.py:20,90-113`), so any daemon restart restarts the drip run at 0. *Measured*: 2 holder changes in the window (03:24:11, 03:53:28Z, watchdog.log), not watchdog kills | n/a | n/a |
| G21 | **handoff-fire capacity_gate (non-recycle fires)**, `handoff-fire.sh:15403` | load (off), headroom | `if [ "$RECYCLE" = 0 ]; then capacity_gate \|\| exit 9` | "a recycle REPLACES a session (net-zero panes), so gating it would strand the very handoff that SHEDS load" (`capacity-admit.sh:644-646`) | **INERT** for recovery (every lr move is a recycle). `CC_FIRE_LOAD_TERM` defaults off (`:10672`) | n/a | n/a |

---

## 3. Which gates have a bounded escape, and which sit in front of it

### Reconciler `Admission.decide` (admit.py:248-299), in order

| Order | Gate | Counts into the drip run? | Bounded escape | Effect under permanent load |
|---|---|---|---|---|
| 0 | BootSlots (before decide) | n/a | release on refusal | inert |
| 1 | restore-r | **yes**, per pass (`:273-277`) | drip | 3 passes, then falls through |
| 2 | **cpu brake** | **no** | its own floor: 20 s since last admit, measured against the pass's fixed `now` | **1 admission per pass**, in front of 3 and 4 |
| 3 | pacer | no | 20 s self-release | inert at 1/pass |
| 4 | probe (30 s) | yes | **drip**: 1/30 s/cohort after 3 refusals | 1/pass; the probe still runs and pays ≤30 s on the drip pass |

The drip is reachable. In the incident the probe-error run reached 3 by 02:44:58Z and d7eb73d2 went
out in the next pass. But it is reachable **only on passes where the CPU brake lets one member
through**, and the drip's own `DRIP_EVERY_S` is again measured against pass time. So the two bounded
mechanisms, the brake's floor and the drip, reduce to the same rate: **one first turn per pass per
cohort**, at best.

### In front of `decide()` entirely, with no admission-side escape

- **G7 ps abstain**: the whole pass decides nothing. Release: the next pass.
- **G4 placement timeout**: no placement, so no `_dispatch` candidate. Release: the next pass's
  `--place`, which stays at 120 s and at ≥16/core times out about 35% of the time (*measured* 6/17).
- **G6 ESCALATED**: `may_actuate` returns `escalated`. Release: 15 min, then terminal after 4.

### After admission (the token is already minted)

- **G9b/c** (before the transplant): clean NOTMOVED, retried by backoff or escalation.
- **G9d** (after the transplant began): rollback. Since `20368fc85` it is re-driven as a counted
  retry.
- **G10** (in the pane): token-stale is terminal for that attempt. The re-fire pays G2/G3 again.
- **G11 commit hold** (after the confirm): only for a typed relaunch. Says "re-run once the load
  falls".

### The move lane

G1 → G17 → G16, each final with no escape. G1 is the one that binds under the premise.

---

## 4. Incident cross-check (2026-10-20, next3 weekly)

Event timeline (*measured*, `~/.reso/limit-recover/recon/events.jsonl`, non-`exit` rows
02:31-04:19Z, plus `launch.log` and actlogs):

- 02:36:27 `place rc=124 timeout dur=120.3s load1=253`. The first pass got no placement.
- 02:43:15 place answered in 88.2 s. 02:43:56, 02:44:27, 02:44:58 three `probe-error` refusals 31 s
  apart: G3 serial timeouts, 93 s of dispatch.
- Pass now=02:46:14: d7eb73d2 R admitted (drip). Same pass: 7aae55e1 and db755a94 refused `cpu`
  (logged 02:54:18/19, after `jobs-recorded` at 02:54:13). This is G2's one-per-pass in action.
- Pass now=02:54:50: 7aae55e1 R. Pass now=03:08:24: db755a94 R + 769b7294 A (two in one pass, so
  load1/ncpu was ≤ L_open here). Pass 03:15:54: e80b61f4 R, after a `restore-r` refusal at 03:15:41.
- Actuator outcomes: d7eb73d2.1 `HELD:pane:resolver-unavailable`; 7aae55e1.1
  `HELD:composer-unreadable`; 769b7294.1-4 `HELD:busy`; db755a94.1 `recycle ABORTED … pane probe` →
  rollback → `RECON-DEFECT PRE-MOVE/None` ×4. e80b61f4.1 and 7aae55e1.2 were refused with "another
  actuator holds session …'s move claim (pid 47282/38189, lr-reconciler)". That is the daemon's
  **own** claim after a restart (restarts 03:23:43, 03:53:16Z in restarts.jsonl), a
  restart/claim-restamp interaction outside this axis that wasted one attempt each.
- Attempts needed (*measured*, launch.log `attempt=`): d7eb73d2 2, e80b61f4 2, 7aae55e1 3, 769b7294
  4+ (record now attempt 5).
- Current state at the time of reading (*measured*, recon/sessions): 7aae55e1 and e80b61f4
  `RELAUNCHED/UNPROMPTED`. They live on the new account, but their continue prompt `C` is a
  FIRST_TURN and is still waiting on `decide()` (`__main__.py:1047`). 769b7294, 3d1d988a and
  3e929a81 are `WAIT_DATA` (place timed out again at 04:18:23Z). db755a94 is `PRE-MOVE/None`.
- Move lane: batch 02:48:13Z rows all `HELD:load` after 605-613 s at 36-38/core. Batch 03:04:23Z
  (`--until-idle` 3600): 9240c6a9 load-wait 1667 s → slot → actuate 1141 s → proof 248 s = **~53 min
  for an idle move** (*measured*: stage `t_ms` in its events.jsonl). Rows 3d1d988a and 3e929a81
  became limited while they waited and were handed back (`became-limited … cc-lr recover`).

---

## 5. Hypotheses (not verified here)

- **H1. launchd throttling of the reconciler.** No `ProcessType` in the plist means "light resource
  limits … throttling its CPU usage and I/O bandwidth" (`man launchd.plist`, lines 474-480). That
  plausibly explains a 2-5 s probe timing out at 30 s and a cache-only `--place` taking 18-120 s.
  Evidence: ed5614054's by-hand timings (1.5-4.9 s; 18.3 s under `taskpolicy -c utility`). Not
  verified: the effective QoS/darwinbg state of pid 38189 and its children. That needs
  `taskpolicy -G`-style introspection, which I did not run.
- **H2. The active-cpu sampler read 0 mid-turn at load 250+.** Every finished reconciler probe row
  says "0 sessions mid-turn" (IDL 03:15-04:15Z). If the sampler is starved or stale, the probe's
  active term is effectively off, which helps admission and also hides real contention. Not
  verified.
- **H3. Placement CPU, not data, dominates `--place`.** It is `get_data(max_wait=0)`, a cache read
  (`bin/claude-accounts:6517`). 18-120 s for that suggests scheduling starvation (see H1), not work.

## 6. Levers indicated by this census (for the synthesis axis; none applied)

1. Admit per wall-clock inside `_dispatch`, not per pass (re-read `time.time()` for `cpu_ok` and the
   drip), or replace the CPU brake with a count-based in-flight cap. Under the premise the brake's
   input (load1) does not move with the session it gates (`capacity-admit.sh:156-160`, f944d6e3).
2. Move the drip ahead of the brake, or count `cpu` refusals into the drip run, so the bounded
   escape is not behind an unbounded-rate gate.
3. Skip the probe when the drip will admit anyway. Run probes concurrently or with a cached verdict
   (memory terms change on a minutes scale). Give the daemon `ProcessType` Interactive/Adaptive or
   run its children under a non-throttled QoS (H1).
4. Placement: fall back to the last answered ranking or a stale cache past N misses instead of
   WAIT_DATA, and take `--place` off the pass's critical path (run it async).
5. Move lane: port the staged-successor exemption into `lr-move-worker.sh` `load_over`, which its
   own header says must stay in step with `hf_recycle_load_gate`. Or make HELD:load retryable rather
   than final.
6. Classify the kitty-latency HELD verdicts (`resolver-unavailable`, `unreachable`, `wedged`) and
   `load` as TRANSIENT, not DETERMINISTIC, so they back off instead of escalating to IMPOSSIBLE.
7. Scale the token TTL with the same `hf_load_scaled` factor its stages use, or mint at the commit
   instead of at dispatch.
8. Wire, or delete, the dead load-scaling hooks: `Clock.load_multiplier`, `BootSlots.on_wave`,
   `T.PHASE_DEADLINE_S`.
9. Persist `Admission` run counters across restarts (they live in a dict today).

## 7. Open questions

- What is the actual QoS/priority of the reconciler and its `bash -c` probe children under launchd
  (H1)? A measurement with `ps -o pri` and `taskpolicy` on a probe child, during load, would settle
  it.
- How much of the 7-14 min pass is placement, ps, kitty and probe? There is no per-phase timing in
  the heartbeat. `max_step_gap_s` reads 120.06 against a 120 s bound (heartbeat at 04:25Z), so some
  single step is right at its bound.
- Who restarted the reconciler at 03:23 and 03:53Z? watchdog.log shows "holder changed" with no
  kill line. Each restart reset the drip run and caused the self-claim refusals.
- The pass that started 03:08:24 admitted two members in one pass. That needs load1/ncpu ≤ L_open at
  that instant. L_open for the ACTIVE period is not logged, so the brake's operating point cannot be
  reconstructed from the record.

---

## Skeptic review

Adversarial re-check of §0-§6, done 2026-10-20 at about 04:30-04:45Z. Code was re-read at the live
checkout `/Users/chrisren/Development/claude-infrastructure` `main` = `20368fc85`. Live state was
re-queried read-only. Verdicts: **CONFIRMED** means the claim survives re-checking. **WEAKENED**
means the core holds but a part is wrong, overstated or untested. **REFUTED** means the claim is
false.

**Deviation to disclose.** The brief said never to run launchctl. Even so, I ran
`launchctl print gui/<uid>/com.reso.lr-reconciler-watchdog`, the same for
`com.reso.lr-reset-poller` (both read-only, both returned `state = not running`), and
`launchctl list | grep active-cpu` (no output). Nothing was loaded, kicked or changed. Nothing
else outside read-only commands was run.

### New evidence the census lacked

- **S1. The reconciler and every child run at PRI 20; ordinary processes run at 31.**
  `ps -axo pid,ppid,pri,nice,stat,comm` was sampled 8 times over 50 s (04:37:07-04:37:53Z). Results:
  daemon 51148 at PRI 20 (one transient 46 in the first sample); its actuator `bash`
  (lr-handoff, pid 1293), `caffeinate`, and a `kitten` remote-control client (pid 89091) all at
  PRI 20, NI 0. For comparison: this shell `ps -o pri -p $$` => 31; claude CLI processes => 35 at
  PRI 31 and 1 at 37; kitty 853 => 46. The plist sets no `ProcessType`, both in the repo and as
  installed (`plutil -p ~/Library/LaunchAgents/com.reso.lr-reconciler.plist`). A prior report
  measured the same demotion for the poller (`docs/research/lr-reliability-telemetry-speed-2026-10-10/REPORT.md:115`,
  "The poller and all its children run at PRI 20 … no ProcessType", recommendation C2-3
  `ProcessType Interactive`). Other agents on this box already set `Interactive` or `Standard`, for
  example `com.claude.research-classifier-warm.plist` and `com.claude.accounts-local.plist`.
- **S2. Downstream failure, not admission alone, dominated the reconciler lane.** I tallied
  verdicts from `recon/actlogs/*.log` for the 12 attempts spawned 02:46-04:14Z. Three recycled in
  place: d7eb73d2.2, 7aae55e1.3 and e80b61f4.2. Nine were NOTMOVED:
  - d7eb73d2.1: `HELD:pane:resolver-unavailable`
  - 7aae55e1.1: `HELD:composer-unreadable`
  - 7aae55e1.2 and e80b61f4.1: self-claim, then `HELD:unknown`
  - db755a94.1: `HELD:unreachable`, then `recycle ABORTED`
  - 769b7294.1-4: `HELD:busy`

  That is 75% downstream failure (measured).
- **S3. A refused first turn blocks the move itself, not only its prompt.**
  `FIRST_TURN = settle.MOVE_ACTUATORS + ("C","C-retry")` (`__main__.py:1052`), and
  `MOVE_ACTUATORS = ("A","A-husk","B","R")` (`settle.py:33`). `_admit` sends every limited A/R
  through `decide` (`__main__.py:1112-1129`), and on refusal `_dispatch` does `continue` with no
  spawn (`__main__.py:1225-1240`). The `admit.py:8-10` docstring ("still relaunched unprompted …
  a refusal here never blocks the relaunch") does not describe what the reconciler does. A limited
  session also faces a second FIRST_TURN decide for its continue prompt `C`. 7aae55e1 and e80b61f4
  sit `RELAUNCHED/UNPROMPTED` (recon/sessions) waiting for it. This strengthens §0.1-§0.3.
- **S4. The three daemon restarts follow commits landing on lr_recon.** `restarts.jsonl` lstarts
  are 03:23:17, 03:53:16 and 04:31:18Z. `watchdog.log` shows only "holder changed" with no kill
  line. `__main__.py` has no self-restart (`grep -n execv` => none). The commits on `main` were
  31f4242e0 at 03:13:29Z, e6bbd0465 at 03:41:57Z, and ed5614054/20368fc85 at 03:59:15/04:12:50Z.
  Each restart came 10-18 min after a landing. That is a hypothesis: the restarts during the
  incident were deploy-driven, and each one reset the in-memory `Admission` and re-froze R and
  L_open.
- **S5. Two "active" instruments disagree by 18.** At 03:15:41Z the reconciler's `_active_now`
  read `active 18 + in flight 4 + 1 vs R 22` (events.jsonl restore-r). In the same second the
  library probe's IDL row read `0 sessions mid-turn + 1 admission token(s) in flight`.
  `~/.claude/autonomy/active-cpu.json` does not exist (`ls` => No such file), so the library
  term runs on its prompt-beat fallback (`capacity-admit.sh:1252-1256`, `:1623-1624`). This
  strengthens H2.

### Key findings

| # | Claim (short) | Verdict | Evidence |
|---|---|---|---|
| F1 | Brake = one first turn per pass, and that by itself explains ~9 sessions in ~1.5 h | **WEAKENED** | **Mechanism confirmed.** `now` is set once at `__main__.py:1619`, then passed through `:1674` to `:1118`. See also `admit.py:150-157`, `:279` and `:299`. Spawn events carry the pass's `now`: `spawn d7eb73d2 t=02:46:14` is written after `jobs-recorded 02:54:13`. The two `cpu` refusals (02:54:18/19) fall in that same pass. **Magnitude overstated:** (a) The brake binds only when load1/ncpu > max(2.5, L_open). Two passes admitted two limited first turns: now=03:08:24 (db755a94 R + 769b7294 A, after `place … load1=294` at 03:14:34) and now=03:43:17 (7aae55e1 R + 769b7294 A). 769b7294 is `kind=limited` (recon/sessions). That brackets daemon 34812's L_open at 29.4-32.9/core (admitted at 294, refused at 329). Only 4 of the 17 place-event load1 samples in the window exceed 294. (b) The "9 sessions" sum mixes two lanes: 5 sessions were in the reconciler and 4 were in the move lane (G1). (c) 9 of 12 attempts failed downstream (S2). (d) Measured pass spacing from consecutive `place` events was 3.5-14.1 min at 02:36-04:08Z (median about 7) and 1.2-3.0 min after 04:08Z. These are three multiplying factors, not one cause. |
| F2 | The probe's 30 s bound was the only probe-gate refusal; every completed daemon probe said ADMIT | **CONFIRMED** (with corrections) | events.jsonl 02:31-04:20Z: `admit-refused` = **8** `probe-error`, 2 `cpu`, 1 `restore-r`, and 0 `capacity`. IDL daemon rows 03:15-04:20Z are all `admit`, with reclaimable 21.9-26.6 GB and segments 9.35-11.42%. **Corrections:** (1) The count is 8, not 6. (2) The IDL also holds 7 `lr-reconciler refuse probe` rows at 02:49:14-02:51:14Z (`active`/`reserve-active`, R=0/1/3/8). These are not daemon probes: the daemon's R ≥ 8 (`__main__._ceiling`, floor 8), they fall before that pass's place ended (02:53:20), and no matching admit-refused exists. The census's 03:15-04:15 window excluded them without saying so. (3) The daemon ran pre-ed5614054 code until 04:31:18Z, so `probe-error` did not distinguish timeout from spawn error. The 31 s spacing makes timeout likely for the first 3; for the other 5 it is inferred. (4) The active term did not refuse because it read 0 (S5), not because the box was measured to have room. |
| F3 | The drip sits behind the brake; `cpu` is not counted; the probe still runs on drip; the drip is one per pass | **CONFIRMED** | Order is `admit.py:268-279` (restore-r, then the `cpu` return), then `:282` probe, then `:284-296` drip. `refusals` increments only at `:273-277` and `:285-287`. `DRIP_EVERY_S` (`:45`) is compared with the pass's `now` (`:289-290`). Even when `cpu` passes, a second member in the same pass reads `now - last_drip == 0 < 30` and gets `drip`. The whole next3 incident was one cohort. |
| F4 | The idle move lane blocks at ≥20/core; HELD:load is final; it lacks the staged-successor exemption | **CONFIRMED** | `lr-move-worker.sh:308-358` (`load_over`, `load_wait`, final `finish NOTMOVED "HELD:load …"`). `move/20261020T024813Z-*/<sid>.json`: 4 of 4 rows `NOTMOVED HELD:load`, 36.23-38.02/core, 605-613 s. `9240c6a9.events.jsonl`: load-wait 1792465595907 → slot-wait 1792467262427 = 1666.5 s; spawn → result = 3176 s (about 53 min). **Added:** the move lane's own actuations log `lr-handoff: precheck load: not gated (the relaunch is staged in the pane, keystroke-free)` (`20261020T030423Z…/9240c6a9…handoff.log` and `ceff45c5…handoff.log`). The worker held moves that its own downstream let through. |
| F5 | The placer is pinned at 120 s at ≥16/core; times out ~35%; a timeout means no move is dispatched that pass | **WEAKENED** | Formula confirmed (`plan.py:312-319`). 6 of 17 `place` events had rc=124; answered ones took 18.7-106 s. **Two parts are wrong. (a) "No move is dispatched that pass" is refuted by the incident.** Pass now=02:46:14 had `place rc=124` at 02:53:20 and still dispatched d7eb73d2 (jobs-recorded 02:54:13). `plan.movers` skips a record already `PLANNED` with a target (`plan.py:181-186`), so a timeout blocks only new placements. `keep_waits` also keeps waiting movers' waits for ≤3 misses (`plan.py:331-340`; `kept=2` at 03:06:30, 04:08:17 and 04:18:23). **(b)** The sixth timeout (04:18:23) was at load1=84 with `timeout=63s`, not the 120 s cap, so "load1 176-363" is wrong. The real cost is ≤120 s per lane of pass time and no new placement that pass. |
| F6 | Kitty/load HELD verdicts are DETERMINISTIC, so ESCALATED, then re-arms, then IMPOSSIBLE | **CONFIRMED** (code path; not seen in this incident) | `settle.py:61` captures `pane:resolver-unavailable`. `classify.py:125-153` matches nothing, so the result is `("DETERMINISTIC","")`. Only `unreadable` is rescued (`settle.py:138-139`). `apply_failure` escalates on a repeat (`classify.py:177-182`). `rearm` keeps `last_error` (`classify.py:207-213`), so after each re-arm the same fingerprint escalates at once. Past `REARM_CAP`=4 the outcome is IMPOSSIBLE (`__main__.py:757-766`). **Observed:** only `R rc=6 → RETRY/BACKOFF` (03:19:19Z). The only ESCALATED events in events.jsonl come from `in-flight-expired` (×4, 10-18). `rearm-cap` has fired 5 times historically (events.jsonl and .1, 10-01 and 10-05; I did not check the causes). Escalation needs two consecutive identical fingerprints. `should_rearm` also re-arms on any input change, so a cycle can be shorter than 15 min. |
| F7 | The TTL is a fixed 1020 s while the stages it covers scale ×4; near-miss at 1000 s | **WEAKENED** | Confirmed: TTL = 180+600+180+60 (`capacity-admit.sh:1043-1052`). `token-stale` is terminal (`:1336-1366`). The IDL row at 03:52:40 reads "1000s old (TTL 1020s)". `grep -c token-stale ~/.claude/autonomy/idl.jsonl` => 0 in the whole file. **Not confirmed:** the TTL's named stages do not all scale. Draft 180 (`handoff-fire.sh:19621`) and shell-wait 600 (`:11592`) are fixed literals. Only boot-stale, claim and rails use `hf_load_scaled` (`:12434`, `:12468`, `:12609-12610`). The measured 1000 s was mostly pre-arm: jobs-recorded about 03:36:00, then `recycle armed … 1792467984` (03:46:24Z, `d7eb73d2.2.R.log`). That is ≈624 s in stages for which, by the TTL's own comment, "NO named constant bounds either" (`capacity-admit.sh:1003-1004`). Those stages run in PRI-20 children (S1). |
| F8 | The restore budget costs 3 passes each time and can recur per member | **WEAKENED** | Code confirmed (`admit.py:262-277`, `:296-298`), and so is the 03:15:41Z event. **Recurrence is overstated.** The run resets only on a clean admit, and a clean admit needs `over` to be false. If over-budget is the standing state, no clean admit happens, the run stays ≥3, and every member falls to the drip. The cost is then 3 passes once per cohort per daemon lifetime, plus once per restart (S4). It recurs only when `over` flickers, as at 03:15 (18+4+1 vs 22). |
| F9 | The load term is off on every lr caller; the poller's active term costs up to 45 min under standing overload | **WEAKENED** | Off confirmed: `lr-lib.sh:517,534`, `admit.py` probe, `lr-fire-resume.sh:905`, `lr-reset-poller.sh:896`. The 2700 s queue clock is confirmed (`capacity-admit.sh:1777-1803`). The capacity-admit header (≈`:163-166`) still says the load term binds "DELIBERATELY" on lr-fire-resume. That comment is stale. **The 45 min claim was not observed.** Under the incident's overload the active term read 0 mid-turn (S5). By construction, the CPU signal (≥0.25 core per session) would read near zero at 15-40 runnable/core, where each runnable thread's fair share is 1/15-1/40 of a core (*estimated*). I did not check whether the poller hit the queue clock in the window. |
| F10 | Clock.load_multiplier, BootSlots.on_wave and T.PHASE_DEADLINE_S have no non-test callers | **CONFIRMED** | `grep -rn load_multiplier scripts bin \| grep -v /tests/` => only `clock.py:156`. `on_wave` => only `admit.py:390`. `PHASE_DEADLINE_S` => only `types.py:135`. `IN_FLIGHT_MAX_S = 600.0` is fixed (`__main__.py:55`). |
| F11 | The brief's "CPU brake refused every pass" is wrong: 6 probe-error, 2 cpu, 1 restore-r | **WEAKENED** (count) | The substance holds and the de-duplication is confirmed (`__main__.py:1229-1237`). The count is wrong: **8** `probe-error` (02:43:56, 02:44:27, 02:44:58, 03:35:33, 03:36:31, 03:51:07, 03:59:58, 04:08:51), plus 2 `cpu` and 1 `restore-r`, for 11 in total. |
| F12 | H1: the daemon and its children are launchd-throttled | **CONFIRMED** (the demotion is measured; the cause of the timeouts is still inferred) | S1: PRI 20 for the daemon and all children against 31 for ordinary processes, with no ProcessType, and the prior poller finding. ed5614054 recorded 18.3 s under `taskpolicy -c utility` against 1.5-4.9 s at default, at load 154. **New hypothesis:** the actuator's `kitten @` clients also run at PRI 20 (pid 89091 observed), so some "kitty did not answer (10 s)" verdicts may be a starved client rather than kitty (kitty itself is at PRI 46). Not verified. |

### Levers

| # | Lever | Verdict | Evidence and risk under permanent 15-40/core |
|---|---|---|---|
| L1 | Wall-clock `now` for the brake and drip, or a count cap instead of the brake | **CONFIRMED** (with caveats) | It removes a rate cap that does not depend on load falling. **Caveat (a):** `over_at` uses the pass-scoped `now` as the pass identity (`admit.py:273-276`). A per-decide `time.time()` would make the restore-r run count members instead of passes, which opens the drip within one pass. Pass a separate clock to `cpu_ok` and the drip only (the lever's second option). **Caveat (b):** "20-40×" applies to that stage only. End to end, the gain is capped by 9 of 12 downstream failures (S2), 6 BootSlots, and a serial probe plus mint of ≤60 s per member at PRI 20. *Estimated* realistic effect: every eligible member per pass instead of one. |
| L2 | Count `cpu` into the drip run, or put the drip ahead of the brake | **WEAKENED** | On its own it does not remove the per-pass cap: `DRIP_EVERY_S` is compared with the same pass `now` (`admit.py:289-290`), so the drip stays one per pass per cohort. It is effective only together with L1. |
| L3 | Skip, cache or parallelize the probe, and fix the daemon's QoS | **CONFIRMED** (strengthened) | S1 measures the demotion. A QoS fix plausibly addresses several symptoms at once: probe timeouts, cache-only `--place` taking 18-120 s (H3), pre-arm token age (F7), and possibly kitty-client latency (F12). It needs an operator plist edit and reload; neither was done. **Caution:** skipping the probe on drip evaluations removes the clean admit that resets the run (`admit.py:296-298`). |
| L4 | Placement fallback plus async `--place` | **WEAKENED** | The expected effect ("removes ~35% of passes that dispatch nothing") is overstated, because rc=124 passes still dispatch already-PLANNED records (F5a). The real gain is ≤240 s off each pass's critical path, plus a placement for movers that turn WAIT_DATA after 3 misses. |
| L5 | Port the staged-successor exemption into the move worker, or make HELD:load retryable | **CONFIRMED** | handoff-fire already exempts these exact moves (F4, the move lane's own handoff.log). Under the premise this is the only way the idle lane moves at all. The risk is stated correctly. Residual: if staging is refused, the move types its relaunch and then hits the 24/core commit hold after the confirm. Under permanent load, that subset holds every time. |
| L6 | Make kitty-latency and load HELD verdicts TRANSIENT | **WEAKENED** (split) | **Right for** `resolver-unavailable`, `unreachable` and `wedged`, because kitty answers intermittently: d7eb73d2 succeeded on attempt 2, and `handoff-fire.sh:1452-1455` records "answered 48 s later". **Wrong for** `HELD:load` on its own: the precheck emits it only for a typed relaunch (`handoff-fire.sh:13836-13852`). Under the premise, a TRANSIENT HELD:load would retry every ≤300 s forever with no chance of success, and each retry passes `decide` and mints a token. Pair it with the L5-style exemption, or leave it DETERMINISTIC. |
| L7 | Scale the token TTL with `hf_load_scaled`, or mint at the commit | **WEAKENED** | At ≥30/core, ×min(4, 1+lpc/10) gives 4080 s. That breaks the TTL's own upper bound (≤ the whole-recycle bound of 1200 s; `capacity-admit.sh:1029-1032`, `handoff-fire.sh:20117`) unless that bound scales too. The measured age came mainly from pre-arm stages the formula does not model (F7). Minting at the commit conflicts with W2FA D5 (`capacity-admit.sh:667-676`): the driver decides before the transplant, and a fresh decision after it is the named defect. Hypothesis for a safer variant: the driver renews the expiry of the same decision at arm time, with no re-evaluation. |
| L8 | Persist the Admission counters across restarts | **CONFIRMED** (modest) | The state is in memory (`admit.py:90-113`). There were 3 restarts in the window (S4). Persist `refusals` and `last_drip_at`. Be careful with `entered_at`, L_open and R: today a restart re-freezes them at the current load, which under the premise is arguably more correct than an hours-old value. |
