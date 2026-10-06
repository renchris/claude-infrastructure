# q1c — the serial drainer and the launchd poller: what bounds their throughput

Slot scope: `bin/cc-lr` request writers, `scripts/limit-recover/lr-reset-poller.sh` (the launchd tick),
`lr-upgrade.sh --drain` (the serial drainer), the locks that carry "one actuator per session".
Date 2026-10-06. Tags: MEASURED (I ran the command), READ (source or record), INFERRED.
All line numbers are in the worktree `/Users/chrisren/Development/.worktrees/lr-zero-memory`; the live
scripts are byte-identical (MEASURED: `cmp -s` of lr-reset-poller.sh, lr-upgrade.sh, lr-lib.sh, bin/cc-lr,
scripts/lib/cc-tui.sh, scripts/lib/detach.sh against `/Users/chrisren/Development/claude-infrastructure/`,
which the LaunchAgent's `~/.claude/scripts/limit-recover/lr-reset-poller.sh` symlink resolves into: 6 of 6 SAME).

## 1. Answer

- Nothing in the drainer or the poller is bounded by memory. The drainer is serial because of one
  global `mkdir` lock (`upgrade-drain.lock`), and each item costs wall time waiting on the subject
  (a model turn or a relaunch), not RAM. The poller is bounded by launchd cadence (StartInterval 600 s,
  measured p50 637 s) and by a tick lock.
- The largest fixed cost in this slot is a LOST KICK: a request written while a tick is already in
  flight waits for the next interval tick. Measured 629-820 s for 7 of 7 such switch requests, and 89 s
  for today's move batch (picked up by a tick some other kick started; the next interval tick was 855 s
  after the request).
- The serial drainer is no longer on the rotation path for interactive sessions: since 2026-10-04 the
  driver form of `switch` delegates to the move lane. The drainer has started 0 times since
  2026-10-04T22:50Z. Its residual work is `upgrade`, background-session switches and marker set-asides.
- Memory appears in this slot's records only as an admission refusal inside a drive: 3 of 114 verdict
  rows name it explicitly; 20 further subject-declined rows quote a reply that does not name a cause.

## 2. Q1 — queued to actuated, per request kind

| verb (writer) | file written (tmp + `mv`) | picked up by | actuator | concurrency |
|---|---|---|---|---|
| `cc-lr switch --pane/--sid` legacy or bg-session (bin/cc-lr:964-970) | `requests/cc-lr-switch-<sid>.json`, kind `switch` | tick request loop moves it to `upgrade-queue/` (lr-reset-poller.sh:1219-1236) | `lr-upgrade.sh --drain`, detached by `lrp_upgrade_kick` (:1453-1489) | 1 (global drain lock) |
| `cc-lr upgrade` (bin/cc-lr:2045) | `requests/cc-lr-upgrade-<sid>.json`, kind `upgrade` | same | same drainer | 1 |
| auto-upgrade, every tick (lr-upgrade.sh:2426-2440) | `upgrade-queue/auto-upgrade-<sid>.json` directly | drainer | same drainer | 1; adds nothing while the queue holds work or a drainer runs (:2430-2432) |
| `cc-lr repair-markers` (bin/cc-lr:1893) | `upgrade-queue/` directly, kind `marker-setaside` | drainer | same drainer, no 10 s gap (:2395) | 1 |
| `cc-lr move` (bin/cc-lr:1312-1334) | `move/<batch>/plan.json`, `intent/`, `move/requests/<batch>.json` | `lrp_move_kick`, FIRST work of the tick (lr-reset-poller.sh:262-301); claim is `ln` to `request.claimed.json` | `lr-move-batch.sh <batch>`, detached; one worker per session | parallel (other slot) |
| `cc-lr repair`, hook `stop-failure-marker`, lr-fleet hand-off | `requests/<sid>.json`, kind ""/recovery | tick request loop (:1130-1416) | `lr-fleet.sh --one <sid> --from-daemon --detach` (:1368), or inline `cc_tui_submit` for mode prompt (:1391) | detached, capped 4 dispatches per account per tick (`LR_REQUEST_MAX_PER_TICK`, :1113, :1320) |
| `cc-lr recover/switch` under `recon.on` | `requests/<sid>.cc-lr.json` | reconciler; this loop only when it is not live (:1136-1138) | reconciler | n/a (`recon.on` is absent now, MEASURED `ls`) |

Tick order (READ, lr-reset-poller.sh): overlap lock `poller.lock` (:216-233) -> `TICK start` -> recon
watchdog (:260) -> `lrp_move_kick` (:301) -> request loop (:1130) -> engagement audit (:1439) ->
`lr-upgrade.sh --auto-enqueue`, bounded 60 s (:1495-1502) -> `lrp_upgrade_kick` (:1503) -> resume-debt
sweep, lock reap, census, parked-session resume.

Triggers (READ): launchd `StartInterval` 600, `RunAtLoad` true, no `WatchPaths`/`QueueDirectories`/`KeepAlive`
(com.reso.lr-reset-poller.plist:37-38; installed plist has the same keys, MEASURED `diff`). Every writer
sends one `launchctl kickstart gui/<uid>/com.reso.lr-reset-poller` with no `-k` and no retry
(bin/cc-lr:984, 1339, 1818, 1904, 2058; hooks/stop-failure-marker.sh:290, 549). The script is
single-pass; it has no internal loop (:202).

Drainer loop (READ, lr-upgrade.sh:2347-2415): `mkdir upgrade-drain.lock` (holder pid + lstart) ->
promote every `upgrade-deferred/*.json` back to the queue once (:2363) -> repeat: oldest file by mtime
(`ls -1tr`, re-listed each iteration, so requests queued mid-drain are taken by the running drainer) ->
claim by `mv` into `claimed/` (:2386) -> `sleep $LRU_GAP_S` (10 s) before every item after the first
(:2395) -> `lru_switch_drive` / `lru_drive` / `lru_marker_drive` -> exit when the queue is empty.

## 3. Q2 — is the drainer strictly one at a time, and why

Yes. "ONE AT A TIME, by construction: a lock dir with a holder pid, stolen only from a dead holder"
(lr-upgrade.sh:2346). The poller starts no second one (lr-reset-poller.sh:1460-1463; tests
lr-upgrade.bats C3, C4, C5). MEASURED: 167 `UPGRADE-DRAIN started`, 2 `already running`
(`grep` on poller.log).

Stated reasons (READ):

| reason | where |
|---|---|
| "an upgrade and a switch of the same pane can never interleave, and a --all-idle batch cannot stampede one target account" | lr-upgrade.sh:2396-2397 |
| the drive re-judges idleness at execution time, then waits minutes for the registry flip; that must never run under the tick lock | lr-reset-poller.sh:1222-1229 (defect 1 at :973-979: one request held the tick lock 115-658 s) |
| auto-enqueue must not stack duplicates behind a slow drain | lr-upgrade.sh:2423-2424 |
| acting on a peer pane from inside a session is refused by auto mode, so the actor must be launchd-owned | bin/cc-lr:733-738, 1037-1038 |

None of the four names memory. The plan `VOLUNTARY_ACCOUNT_SWITCH.md:214-232` (DEC-2 resolved) repeats
"the one serial drainer shared with upgrade" without a further reason.

## 4. Q3 — the latency floor before anything happens

Method: `claimed/cc-lr-*.json` `.ts` (write time) joined to `poller.log` `SWITCH-QUEUED`/`UPGRADE-QUEUED`,
`TICK start` and `UPGRADE-DRAIN` lines, and to `switch/<sid8>-<ts>/` and `upgrade/<sid8>-<ts>/` run dirs
(python over the records; n = 30 requests, the latest one per sid).

| stage | measured | n | what sets it |
|---|---|---|---|
| write -> tick start, kick lands on an idle poller | 0-2 s | 23 of 30 | `launchctl kickstart` |
| write -> queued, a tick ALREADY in flight | 629, 649, 663, 669, 807, 814, 820 s | 7 of 30 | the kick is dropped; next StartInterval tick |
| same, move lane, 2026-10-06 batch | 89 s (request 06:05:34Z, tick in flight since 06:05:16Z, `MOVE-BATCH started` 06:07:03Z) | 1 | a later kick from another writer; the next interval tick was 06:19:49Z (855 s) |
| tick start -> request queued, since 2026-10-03 | 0-6 s | 20 | request loop reached at once |
| tick start -> request queued, 2026-09-23 to 2026-10-01 | 13-17 s (6), 60 s (1), 87-89 s (2), 401 s (1) | 10 | INFERRED: the loop works every earlier file in glob order inline before it reaches a `cc-lr-*` file |
| queued -> `UPGRADE-DRAIN` line (started or already running) | 0-2 s (27), 13-27 s (3) | 30 | engagement audit + auto-enqueue census (<= 60 s bound) sit between |
| tick start -> drainer kicked, since 2026-10-01 | p50 19 s, p90 78 s, max 251 s | 122 | same |
| drain start -> first drive reaches its type step | min 2 s, median 22 s, max 332 s | 54 | fence, mutex, census re-judge, capacity probe (upgrade), draft carry |
| no kick at all (auto-enqueue, parked `--until-idle` re-judge) | one tick: p50 637 s, p90 876 s, p99 1987 s, max 6839 s | 1845 intervals | StartInterval 600 + tick run time |

- Lost-kick proof (MEASURED): for all 7 slow requests the previous tick's `TICK start` precedes the
  write and its last log line follows it (e.g. 7b1dea4d written 15:53:06, tick 15:52:21-15:53:10, next
  tick 16:03:33). 8 of 31 recorded requests (26%) hit it. Tick duty cycle since 2026-10-01 is at least
  15.3% (sum of logged tick spans 69,621 s over 455,137 s, 631 ticks), so this is not rare.
- Tick run time (lower bound, last log line minus `TICK start`): p50 28 s, p90 221 s, p99 947 s,
  max 2697 s (n = 1845); since 2026-10-01 p50 36 s, p90 256 s, max 1725 s (n = 631).
- Zero `TICK-SKIP` lines in 1846 ticks (MEASURED `grep -c`): the overlap lock at :218 logged no skip,
  so the drop happens in launchd, which does not start a second instance of a running job (INFERRED
  from the 7 of 7 timing pattern, not tested: I did not kick the live job).
- The interval counts from the previous run's exit (INFERRED): interval p50 637 s = 600 + run p50 36 s,
  p90 876 s against 600 + run p90 256 s. So a dropped kick costs 600 s plus the rest of the in-flight tick.
- "Latch": `requests-latch/` holds the stop-failure hook's latch file per death record
  (`<sid>.<death_uuid>`, 0 bytes; hooks/stop-failure-marker.sh:447), a de-duplicator, not a delay.
  The fire-failure latch (`LR_FIRE_FAIL_MAX` 3,
  `LR_FIRE_LATCH_HOURS` 6, lr-reset-poller.sh:353-354) brakes auto-resume of parked sessions only; no
  cc-lr request passes through it.
- Best case end to end for a kicked switch/upgrade request: about 2 s to the tick, 0-3 s to the queue,
  0-2 s to the drainer, 2-22 s to the first keystroke: roughly 5-30 s. Worst recorded: 820 s before the
  queue is even touched.

## 5. What bounds throughput

| bound | value | evidence |
|---|---|---|
| drainer concurrency | 1 | global lock, lr-upgrade.sh:2350 |
| fixed gap between items | 10 s (`LRU_GAP_S`) | lr-upgrade.sh:88, :2395 |
| legacy switch: start-to-start spacing inside one drain | min 48 s, median 100.5 s, mean 140 s, p90 240 s, max 440 s | MEASURED, n = 32 consecutive pairs of `switch/` run dirs in the same drain |
| of which the drainer's own typing | <= 7 s in 31 of 36, max 71 s (run dir -> `submit.log` mtime) | MEASURED, n = 36 October runs |
| so the rest is the verify loop: waiting for the subject's turn, 5 s poll, ceiling 600 s (`LRU_SWITCH_VERIFY_S`) + draft restore ceiling 300 s | | READ lr-upgrade.sh:1212-1237, :1055 |
| implied serial rate, legacy switch | about 26-36 requests/hour | MEASURED 3600/140, 3600/100.5 |
| 12-request batch 2026-10-04 | "36 m 51 s and moved 0", "median 376K input-equivalent tokens" per subject turn | READ bin/cc-lr:1033-1035; my records: 10 type steps 15:53:01-16:10:29Z, one drainer pid 41027 |
| upgrade drive, run dir -> `upgraded` verdict | min 38 s, median 56 s, max 770 s | MEASURED, n = 11 |
| upgrade worst case by code | retype loop 5 x (30 + 20) s, then engage wait 200 s | READ lr-upgrade.sh:85-87, :2064-2112 |
| `--until-idle` re-judge of a parked switch | once per drain start = once per tick (p50 637 s) | READ :2360-2364; MEASURED 101 "re-judging 1" lines, 9 "budget ended" verdicts |
| recovery request lane | 4 dispatches per account per tick; retry spacing 10 min; 3 attempts; stay-put within 900 s of reset | READ lr-reset-poller.sh:1081-1082, 1112-1113 |
| ...how often that cap bound | 5 of 1846 ticks (`REQUEST-QUEUED`, depths 1-5, all next4) | MEASURED `grep` |

Drainer activity (MEASURED, poller.log): 43 drain starts on 2026-10-03, 75 on 2026-10-04, 0 since
2026-10-04T22:50:28Z; 0 `SWITCH-QUEUED` since then; the one rotation since (2026-10-06, 7 idle moves)
went through `lrp_move_kick`. READ bin/cc-lr:860-874: the driver form of `switch` now calls `cmd_move`
unless `CC_LR_SWITCH_LEGACY=on` or the subject is a background session.

## 6. Q4 — could N requests drain concurrently without breaking "one actuator per session"

What enforces the property (READ):

| mechanism | key | atomic step | holds across | depends on a serial drain? |
|---|---|---|---|---|
| run claim `runs/by-sid/<sid>.active` (`lr_claim_take`, lr-lib.sh:557-700) | sid | `mkdir`; holder = (pid, lstart); dead holder stolen through a rename | the whole upgrade drive (lr-upgrade.sh:1961-1965); shared by cc-lr (:296-309), lr-fleet (:643-649), the poller (:1001-1012), the move lane (lr-move-batch.sh:163) | no |
| same claim in the legacy switch drive | sid | same | RELEASED BEFORE THE SUBMIT (lr-upgrade.sh:1189-1191) so the subject's own `cc-lr switch` can take it | YES: for up to 600 s of verify only seriality keeps a second drainer drive off that pane |
| request claim: `mv` into `claimed/` | request file | rename | one drive per file (lr-upgrade.sh:2380-2392) | no |
| move-batch claim: `ln` to `request.claimed.json` | batch | link | one runner per batch (lr-reset-poller.sh:286-290) | no |
| reconciler fence launch lock | sid | lock dir, exported as `LR_LAUNCH_LOCK` | the whole drive (lr-upgrade.sh:1124-1129, 1948-1952; lr-recon-fence.sh:361-432) | no for separate processes; yes for workers sharing one shell (a global variable) |
| handoff-fire recycle lock `locks/pane-<digest>.recycle` | pane | lock dir | the /exit and relaunch (scripts/handoff-fire.sh:2887-2935) | no |
| global drain lock `upgrade-drain.lock` | none | `mkdir` | the whole queue | it IS the serializer |
| tick lock `poller.lock` | none | `mkdir` | one tick | n/a |
| `lr-lock.py` | sid | none: it classifies and reaps `locks/<sid>.lock`, lr-transplant's custody record (lr-lock.py:1-58) | n/a | it is a TTL policy, not an actuator mutex |

INFERRED answer: yes for `upgrade` and `marker-setaside`, whose safety is carried by keyed locks that hold
for the whole drive (sid claim + pane recycle lock + request rename). Not as written for two cases:

1. Legacy interactive switch: the sid claim is given up before the keystroke, so two drains could act on
   one pane during the verify window. This drive is retired by default; do not parallelize it.
2. Two different sids on one pane: a background session and its `bg-host` row share a pane
   (bin/cc-lr:932-933). The sid claim does not separate them; today seriality does. A concurrent drain
   needs a per-pane lease held for the whole drive.

Other shared state a concurrent drain would touch (READ): up to three request files per sid can sit in the
queue (`cc-lr-switch-`, `cc-lr-upgrade-`, `auto-upgrade-`), so a second worker would report a spurious
"busy" skip; `lru_auto_enqueue` and `lrp_upgrade_kick` read the single lock's pid file; the capacity probe
(`lru_capacity`, lr-upgrade.sh:1857-1873) is asked per drive with no reservation, so N probes can all pass
before any relaunch lands; and the stated stampede reason becomes real: N confirmation turns on one account
at once.

## 7. The memory hypothesis, in this slot

- The drain loop and the poller's kick code contain no memory, swap or headroom term (READ
  lr-upgrade.sh:2347-2415, lr-reset-poller.sh:262-301, 1453-1489).
- `upgrade-drain.log` verdict rows (MEASURED, python tally): 114 rows = 18 SWITCHED, 43 NOTMOVED,
  10 upgraded, 42 skipped, 1 failed. Memory named in 3: one drainer capacity probe
  ("reclaimable 9.14GB < floor 4GB + operator reserve 6GB", 2026-09-29) and two subject-side refusals
  ("compressed memory is at 61% of its limit, and the switch is only allowed under 50%"). One more names
  the active-session ceiling ("Seven sessions are mid-turn ... The ceiling is 8").
- Largest refusal classes: 30 `relaunch-surface-unverified` (surface rc 3), 26 subject-declined,
  9 `--until-idle` budget ended, 6 mutex held. Of the 26 subject-declined: 2 memory gate, 1 session
  ceiling, 3 target unroutable, 20 matched no pattern. Read by eye, none of the 20 names a memory gate
  in its 200-character quote; at least 3 name another cause (target logged out, no account with room,
  the move had in fact happened).

## 8. Proposed changes

| # | change | conviction | risk |
|---|---|---|---|
| 1 | Call `lrp_move_kick` again before each normal exit of the tick (lr-reset-poller.sh:1869 and :2270). The `ln` claim already makes a repeat harmless. Shrinks the lost-kick window for the rotation lane from the rest of the tick (p50 36 s, p90 256 s) to the instants before exit. | 80% | none on safety; a request landing after the tail check still waits one interval, so pair it with change 2 |
| 2 | In `cc-lr move/switch/upgrade` wait loops: if the request file is still unclaimed after about 15 s, send the same bare `kickstart` again (repeat every 15-30 s until claimed). Client-only; bare kickstart is a no-op on a running job. | 80% | does nothing under `--no-wait`/`--wait 0`; adds launchctl calls |
| 3 | Leave the drainer serial. It is off the rotation path (0 starts in the last 31 h) and its per-item cost is the subject's turn, not a resource it could share. | 80% | upgrade waves stay at about 1 per minute |
| 4 | If upgrade volume ever needs it: N drain workers keyed by pane, each holding a pane lease and the sid claim for the whole drive, legacy switch excluded, per-account cap. | 45% | capacity probe has no reservation; kitty RPC under concurrency is untested |
| 5 | Race-free trigger: a `kicks/` token directory under launchd `QueueDirectories`, emptied at tick start. Removes the lost kick for every lane. Needs a plist edit by the operator and the parity lint updated. | 55% | hook-held requests must not live in that directory, or launchd respawns every 10 s |

## 9. Alternatives considered

- Lower `StartInterval`: rejected. A tick already runs p50 36 s / p90 256 s and audits every parked
  session; a 60 s interval would overlap itself and still leave up to 60 s of latency.
- Put `requests/` itself under `QueueDirectories`: rejected. Hook requests stay queued by design until the
  session is seen recovered (lr-reset-poller.sh:1408-1411), so the directory is rarely empty.
- Parallelize the legacy switch drive: rejected. The move lane replaced it and spends 0 model tokens.
- A pre-pass that queues `upgrade|switch` files ahead of hook-request work: gain 0-91 s; low value.

## 10. Uncertainties

- `launchctl kickstart` on a running job being a silent no-op is inferred from 7 of 7 timings; I did
  not exercise the live job or create a scratch LaunchAgent (both outside the brief's rules).
- Tick run times are lower bounds: the log has no `TICK end` line.
- What sent the 06:07:03Z kick that rescued today's move batch is not recorded; a stop-failure hook
  kick is the likely source (a next3 weekly-limit cohort was dying at 06:02-06:07Z).
- `results/*.json` keep only the latest verdict per sid, and `upgrade-drain.log` has no timestamps, so
  per-item verdict latency for switches is derived from run-dir spacing, not from verdict times.
- 20 subject-declined rows carry no cause; some may be memory-gate refusals inside the subject.
- Concurrency safety in section 6 is a code reading. No concurrent drain was run.
