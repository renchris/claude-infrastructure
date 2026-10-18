# In-place account moves: why they took hours, and the fixes

Scope (frozen): measure and root-cause why in-place account moves take tens of minutes to hours instead
of seconds, then land fixes that make an idle healthy session's in-place move to a named account complete
in well under a minute even on a loaded box, each fix with a red-then-green bats test; report the
before/after numbers.

Data: session 620db313 (pane 344) asked at 2026-10-17T23:45Z to move every session on next2/next3/next4
to `next`, highest-activity first. By 02:16Z, 0 of 15 movable sessions were proven on `next`, one
(e739e5b5) was down after a transplant, and two had been transplanted and rolled back. Every number
below is measured from the stores named in `raw/`, unless marked *estimated*.

## 1. Answer first

The lane did not fail on one thing. It stacked six independent delays, and on a box at 28-40 load
per core each one multiplied the next:

| # | class | what it cost in this window | root cause | status |
|---|---|---|---|---|
| 1 | **Queue: requests waited for the poller's tick to END** | 17.4 session-hours of 39 session-rows' wait; 27 of 49 batches ever (p50 829 s, p90 4,533 s, max 5,124 s) | the poller looked at `move/requests/` only at its top and in its EXIT trap; launchd drops a kickstart while a tick runs; one tick ran 86 min | **fixed** (mid-tick drain, rank 1) |
| 2 | **Intents expired in the queue, and nothing checked them until the actuator** | 7 rows refused `intent-invalid` / `not-limited`; 10 rows whose intent had expired *before their batch started* still took 8 claims, 8 workers and all 4 slots, and won all 10 claim collisions | intent clock starts when `cc-lr move` is typed (`now + until + 900`), checked only at `lr-handoff.sh:649` | fixes A1/A2 (admission check, act-by from admission) + W1 (worker re-check) |
| 3 | **The actuate stage ran at the wrong CPU band and stood down late** | actuate 194-1,910 s per row (7,989 s total); 1,027 s of 43e6eb4b's 1,477 s was non-kitty work; holds (`HELD:unreachable`, `HELD:load`) fired only after the transplant | every rail process inherits launchd's default clamp (**pri 20**) while the work loading the box ran at pri 31; the kitty probe was one unretried 3 s shot; the load hold sat after the transplant | K1-K4 (retry, honest verdict, fail-fast precheck, no subject nudge) in progress; the band is an operator activation (§6) |
| 4 | **The load hold makes a loaded box unmovable** | 2 of 2 rows that reached `/exit` in the 01:50 pass held `HELD:load` at 28-40/core | handoff-fire's fix 8b holds any relaunch that must be typed above 8/core, and a resume recycle (every in-place move) is always typed | decision (§6.2) |
| 5 | **Self-inflicted contention** | 2 of 5 parallel one-sid batches refused at admission after 599-600 s; 10 claim-held rows; two batches inside the admit section at once | one sid per batch; the admit wait counted loop iterations (90 "s" = 600 s); a lock steal that read the pid twice | A3/A4 (wall-clock wait, rename-and-verify) + `--sids` (one batch, priority order) |
| 6 | **Holds and waits** | 3 background-job waits ran their full 3,600 s; no wait or hold row ever ended MOVED (0 of 84 rows in 17 batches) | the jobs were pollers built to last hours; a census costs 19-27 CPU-s and 6-10 min under load, so a wait row needs 12-20 min just to see two idle snapshots | outside an *idle* session's path; ranked in §6 |

The rail itself was **not** a load source: ~1.5% of box CPU (raw/F). The load was teammate and session
work led by TrueMemory tm2 (62-75% of CPU with short-lived children counted).

## 2. Per-batch timeline (queued → claimed → admitted → actuated → verdict)

Every session-row of the batches requested up to 02:00Z is in `raw/A-timeline.md` (39 rows, all stages
in seconds, read 02:12Z). One line per batch below, re-read at 02:44Z so it also carries the verdicts that
landed since and the batches requested after 02:00Z (UTC; `claimed` = the poller's `MOVE-BATCH started`):

| batch | rows | queued | claimed (queue s) | admitted | first actuate → last verdict | verdicts (read 02:44Z) |
|---|---|---|---|---|---|---|
| `20261017T235745Z-next4-next-69993` | 1 | 23:57:45 | 23:57:54 (9) | 23:59:32 | — → 01:00:35 | NOTMOVED still-busy×1 |
| `20261017T235745Z-next4-next-69995` | 1 | 23:57:45 | 23:57:55 (10) | 00:07:54 **refused** | — → 00:07:55 | NOTMOVED admit-refused×1 |
| `20261017T235745Z-next4-next-69998` | 1 | 23:57:45 | 23:57:56 (11) | 00:07:56 **refused** | — → 00:07:56 | NOTMOVED admit-refused×1 |
| `20261017T235745Z-next4-next-70005` | 1 | 23:57:45 | 23:58:04 (19) | 00:08:08 | — → 01:08:57 | NOTMOVED still-busy×1 |
| `20261017T235746Z-next4-next-69994` | 1 | 23:57:46 | 23:58:12 (26) | 00:05:28 | — → 01:06:15 | NOTMOVED still-busy×1 |
| `20261018T000816Z-next4-next-49288` | 1 | 00:08:16 | 00:17:12 (536) | 00:17:18 | 00:17:36 → 00:53:27 | NOTMOVED HELD:unreachable×1 |
| `20261018T000922Z-next4-next-71757` | 1 | 00:09:22 | 00:17:13 (471) | 00:17:25 | 00:17:36 → 00:53:29 | NOTMOVED HELD:unreachable×1 |
| `20261018T002357Z-next4-next-40187` | 1 | 00:23:57 | 00:24:20 (23) | 00:25:29 | 00:26:57 → 01:14:31 | NOTMOVED not-limited×1 |
| `20261018T002443Z-next4-next-84451` | 1 | 00:24:43 | 01:50:07 (5124) | 01:50:24 | — | RUNNING×1 |
| `20261018T003928Z-next4-next-31080` | 1 | 00:39:28 | 01:50:08 (4240) | 01:52:10 | — → 01:52:13 | NOTMOVED claim-held×1 |
| `20261018T004329Z-next2-next-1739` | 1 | 00:43:29 | 01:50:10 (4001) | 01:52:10 | — → 02:07:41 | NOTMOVED still-busy×1 |
| `20261018T005330Z-next4-next-69593` | 7 | 00:53:30 | 01:50:11 (3401) | 01:50:50 | 01:53:25 → 02:22:03 | NOTMOVED intent-invalid×4, NOTMOVED still-busy×2, NOTMOVED claim-held×1 |
| `20261018T012244Z-next4-next-22836` | 13 | 01:22:44 | 01:50:14 (1650) | 01:52:47 | 01:55:20 → 02:14:36 | NOTMOVED claim-held×7, RUNNING×3, NOTMOVED HELD:load×2, STRANDED×1 |
| `20261018T014908Z-next2-next-23285` | 4 | 01:49:08 | 01:50:16 (68) | 01:53:49 | 01:55:31 → 02:11:58 | NOTMOVED claim-held×1, NOTMOVED slot-wait×1, NOTMOVED HELD:unknown×1, NOTMOVED HELD:draft×1 |
| `20261018T020022Z-next4-next-2123` | 4 | 02:00:22 | 02:11:38 (676) | 02:12:15 | 02:12:59 → 02:28:10 | STRANDED×3, NOTMOVED HELD:load×1 |
| `20261018T021322Z-next4-next-22546` | 2 | 02:13:22 | 02:13:27 (5) | 02:13:47 | 02:15:08 → 02:22:10 | NOTMOVED HELD:load×1, RUNNING×1 |
| `20261018T023337Z-next4-next-4785` | 1 | 02:33:37 | not yet claimed at 02:44Z | — | — | RUNNING×1 |
| `20261018T024022Z-next4-next-8101` | 2 | 02:40:22 | not yet claimed at 02:44Z | — | — | RUNNING×2 |

## 3. Time attributed to each class

Summed over the 39 session-rows (`raw/A-timeline.tsv`; a batch's queue time counts once per row it held):

| stage | rows reaching it | seconds | share | class |
|---|---|---|---|---|
| queue (request → poller start) | 39 | 62,703 | 70% | 1 |
| admit (start → admit.json) | 39 | 5,945 | 7% | 5 |
| idle wait (W2) | 4 finished | 11,620 | 13% | 6 |
| slot wait (W3) | 10 | 565 | 1% | 2/5 (doomed holders held all 4 slots for 107-116 s) |
| actuate (lr-handoff) | 12 | 7,989 | 9% | 3/4 |
| prove (verdict reads) | 11 | 2,826 | 3% | 3 (verdict reads at pri 20: 604-685 s after rc 6, bound 20 s) |

Outcome of the 39 rows when read (02:12Z): 11 still running, 10 claim-held, 4 still-busy, 4
intent-invalid, 2 admit-refused, 2 HELD:unreachable, 2 HELD:load, 1 not-limited (expired intent),
1 slot-wait, 1 HELD:unknown, 1 HELD:draft. **0 MOVED.**

Two more classes the data source added (pane 344, 02:13-02:33Z): a **post-transplant strand**
(e739e5b5, rc 4: transplanted, relaunch never verified, the pane left at a bare zsh; the rescue verb
`lr-fleet --one` then refused to relaunch into its own husk shell) and **false STRANDED verdicts**
(246a91b5 had self-recycled into 4fd71ecf and the verdict does not follow a recycle chain; e3dedc17 was
alive with no registry row). Both are in §6.

## 4. Before and after

Before is measured on the 2026-10-17/18 window and on every move on record. After is what each landed
fix removes, proven by its red-then-green fixture; the live after-number comes from the next real batch
(re-run `/tmp/lri-a/timeline.py`, or read `cc-lr move --status <batch>`). Nothing here was measured by
moving a live session, which this work was not allowed to do.

| stage | before (measured) | after the landed fixes | how it is proven |
|---|---|---|---|
| request → batch started | idle poller p50 3 s; during a tick **p50 829 s, p90 4,533 s, max 5,124 s** (27 of 49 batches) | ≤ `LR_MOVE_DRAIN_POLL_S` (1 s) + the claim, at any tick length | `tests/lr-move-drain.bats` case 1: a request written mid-tick starts while the tick still runs (red before) |
| intent expiry | 7 rows refused late; 10 doomed rows took claims, workers and all 4 slots | an expired intent is refused at admission with no claim; an admitted row's act-by covers its idle wait and slot wait | A1/A2/W1 suites |
| admission | 2 of 5 batches refused after 599-600 s ("90 s"); two batches admitted at once | waits up to 900 wall-clock seconds; one admission for N named sessions | A3/A4 + `--sids` suites |
| actuate, terminal or load hold | 194-1,910 s before `HELD:unreachable` / `HELD:load`, after a transplant | the precheck holds in seconds, before anything is transplanted; a refused-then-answering socket is retried for 120 s | K1-K3 suites |
| actuate, success | 85-110 s, then 64-200 s to proof (all 9 successful moves on record: 175-215 s) | unchanged by this wave — see raw/I and §6 | — |

## 5. Fixes, ranked

Ranked by how much of an idle session's move each removes on a loaded box. "Landed" means content-verified
on origin/main; each row names the suite that was red before the fix and green after.

| rank | fix | removes | where | status |
|---|---|---|---|---|
| 1 | **Mid-tick move drain**: the tick runs a drainer beside its arms that starts a queued batch within 1 s, through the same hard-link claim | class 1 (70% of all stage time; p50 829 s → ~1 s for a request that lands mid-tick) | `scripts/limit-recover/lr-reset-poller.sh` (`lrp_move_drain_start/_stop`) · `tests/lr-move-drain.bats` | lands with this report |
| 2 | **Intent checked at admission; act-by measured from admission** (an `intent/<sid>.admitted` sidecar the validator honours) | class 2: doomed rows never take a claim, a worker or a slot; an admitted row's budget covers its idle and slot waits | `lr-move-batch.sh`, `lr-intent.sh` · `tests/lr-move-admit.bats`, `tests/lr-intent.bats` | built by teammate `admit`, not yet landed |
| 3 | **Fail fast in the precheck** on a deaf terminal or a load the late gate would hold, before anything is transplanted; retry a refused-then-answering socket for 120 s for detached callers; name the probe's real failure | class 3/4: a 10-25 min transplant-then-stand-down becomes a hold in the precheck; tonight's two post-hold strands (`unconfirm rc 2`) cannot happen when nothing was transplanted | `scripts/handoff-fire.sh`, `scripts/lib/kitty-queue.sh`, `lr-handoff.sh` · `tests/handoff-recycle-kitty-precheck.bats`, `tests/handoff-recycle-load-hold.bats` | built by teammate `handoff`, not yet landed |
| 4 | **No "recycle owed" nudge for a driver-run recycle** | the subject re-ran the move's recycle itself and confirmed/unconfirmed the transplant under the driver (a live STRANDED race) | `scripts/handoff-fire.sh` · the pane-close-queue cases | built by teammate `handoff`, not yet landed |
| 5 | **Several named sessions in one batch, in priority order** (`--sid` repeated or `--sids a,b,c`, mixed source accounts) | class 5: one census, one router read, one admission instead of N; the operator's "highest-activity first" survives to the plan | `bin/cc-lr`, `lr-upgrade.sh` · `tests/lr-move-plan.bats` | built by teammate `cclr`, not yet landed |
| 6 | **Admit wait by the wall clock (900 s), steal by rename-and-verify, router reason reset** | class 5: no batch refused for queueing; no double admission | `lr-move-batch.sh` · `tests/lr-move-admit.bats` | built by teammate `admit`, not yet landed |
| 7 | **Worker re-checks its intent while it waits; takes the slot in plan order** | class 2/5: a lapsed intent releases claim and slot at once; priority holds at the slot | `lr-move-worker.sh` · `tests/lr-move-worker.bats` | built by teammate `worker`, not yet landed |

## 6. Not fixed here, and why

These are measured, and each is either an operator call or a next wave; none is hidden as done.

1. **The CPU band (operator activation).** Every process the move lane runs — poller, batch runner,
   worker, lr-handoff, handoff-fire, the recycle watcher — sits at **priority 20**: launchd gives
   `com.reso.lr-reset-poller` (no `ProcessType`) its default light resource limits, and a child cannot
   climb back to 31 (measured here: `taskpolicy -a` from a utility-clamped parent stays at 20). The load
   it competes with ran at 31 (755 processes at 31 against 137 at 20, `ps -o pri`). That is why a
   nominal 5 s wait took 41-50 s and the precheck 163 s. Remedy, not built: a separate
   `com.reso.lr-move-kick` LaunchAgent with `ProcessType Interactive` and `WatchPaths` on
   `move/requests/`, that runs only the kick (the census explicitly clamped back to `utility`). Every
   launchd job here is activated by an operator-run script, so this is the operator's step, and its
   activation script must read the priority back. A positive control with throwaway launchd jobs was
   refused by this session's removal safety check, so the gain at 31 is not measured.
2. **The 8/core load hold (decision).** `raw/H`: the bound is ship-land's `CC_GATE_MAX_LOAD_PER_CORE`
   default, not typing data. The hardened typed relaunch has 0 failures in 11-18 recycles at 8-32/core
   and none measured above 24.6/core (rule of three: the 8-32 failure rate is below ~27%). Options:
   keep 8 (with the precheck fail-fast and a worker that waits for a dip, moves on a loaded box wait but
   never strand); raise to 24 (moves at tonight's 13-24/core loads; the risk is a stranded session, the
   evidence says rare); or build the keystroke-free resume relaunch below, which makes the bound moot.
3. **Keystroke-free resume relaunch (design wave).** Fresh-mode recycles already stage their relaunch
   for the pane's own shell to run; resume recycles (every in-place move) never stage, because the
   watcher's fold, launch-lock and holder rails must run first. A staged successor that waits for a
   go-file the watcher writes after those rails would keep that order and remove the typed step.
4. **A successful move still costs ~3 minutes.** All 9 MOVED rows on record took 175-215 s from
   actuation to proof (85-110 s lr-handoff, 64-200 s relaunch to proof). `raw/I` decomposes it.
5. **Next wave, already specified** (`docs/plans/LR_INPLACE_IMMEDIACY.md` § W2): census filtered by
   session before its per-row forks (the plan-time census ran 3.0-3.4 min under load); the watch census
   limited to waiting rows; the router answer reused from `cc-lr move` (the admit read took 5-323 s); a
   worker that waits for a load dip without a slot; a verdict that reads the transcript by its known
   path instead of globbing ~18,200 directories in each of 4 stores (1.0 CPU-s a call); false STRANDED
   on a missing registry row or a recycle chain; and the rescue verb that will not relaunch into its own
   husk shell (e739e5b5).
6. **Holds outside the idle-session scope** (`raw/E` §4): carry sleep-only background jobs on a healthy
   source (an operator ruling, it narrows `1b97389dd`); key the goal hold on goal activity; do not let
   the requester's own `cc-lr move` become the job that holds its subject.

## 7. Evidence

| file | what it measured |
|---|---|
| `raw/A-timeline.md` / `.tsv` | every session-row's stage timings, every batch in the window |
| `raw/B-poller-latency.md` | queue latency over all 49 batches, tick durations, the 86-min tick's anatomy |
| `raw/C-actuate-kitty.md` | the ~25-min actuates decomposed; the kitty call chain; the owed-recycle race |
| `raw/D-transcript-narrative.md` | session 620db313's own timeline, waits, scripts and conclusions |
| `raw/E-holds.md` | every hold/wait class: where it is assigned, what it protects, a verdict |
| `raw/F-load-rail-cost.md` | what loaded the box; the rail's own CPU (census 19-27 CPU-s); pri 20 |
| `raw/G-claims-ttl-admit.md` | intent expiry, admit contention, claim collisions, with file:line |
| `raw/H-typed-relaunch-vs-load.md` | typed relaunch outcome by load per core (the 8/core bound's evidence) |
| `raw/I-successful-move-profile.md` | where a SUCCESSFUL move's ~3 min goes (still being measured when this report first landed) |
