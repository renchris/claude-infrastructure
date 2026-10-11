# C3 — width and waits (slot report, 2026-10-11T04:05Z, trunk 110ea9a64)

## Answer first

- A rotated session waits mostly in **queues, not in service**. Intake is tied to the poller tick: the request lane and the move kick run once per tick, before the unbounded parked loop. Recover queue wait (request to dispatch, n=26) was p50 175 s, p90 1128 s, max 1471 s. Move queue wait (request to MOVE-BATCH start, n=5) was 2 / 67 / 89 / 221 / **896 s**. Service for a successful session is 85 s p50 (--one RECOVERED) and 120-218 s (move, at load 2/core).
- There are **three concurrency caps that never see each other**: --one width 2, move/reconciler width 4, and a serial upgrade drainer. So the "≤4 overlapping boots" rationale does not hold: up to 7 sessions can boot at once. 2 of 4 completed move batches overlapped a --one run, and 2 of 4 overlapped an upgrade run.
- Load is recorded, in `~/.claude/logs/capacity-alarm.jsonl` (load_1m/load_5m, every 1-2 min) and in the lr-upgrade step events (`load1=`). Move outcomes split by load: 9/9 MOVED at load1 20-53, and 0/13 MOVED at 128-1017. Memory pressure carries no signal: level 1 in 2319 of 2357 samples. The best signal is load5 per core, used to **narrow** the width at slot-acquire time. The proposal makes the bands down-only, so nothing ever runs wider than 4.
- A shared MCP daemon, a SessionStart skip and kqueue are **not** speed levers here: together they are worth at most a few seconds per session against waits of minutes. Lead cost when intake is stuck (live case): 33 API round trips, 4.04 M cache-read tokens, 31 Bash calls, 0 sessions recovered. When the lane is free it is 1 call.

## Where the widths are defined (Q1)

| lane | width | file:line | wait bound |
|---|---|---|---|
| recover `lr-fleet.sh --one` | `LR_ONE_MAX_CONCURRENT` default 2 (mkdir slots in `$STATE/one-slots`) | `scripts/limit-recover/lr-fleet.sh:1496-1500` (cap), `:1502-1503` (take, poll `LR_ONE_SLOT_IVL_S`=10 s) | `LR_ONE_SLOT_WAIT_S` 900 s, `:1503`, `:1835` |
| move worker | `LR_MOVE_SLOTS` default 4, or plan `.slots` | `scripts/limit-recover/lr-move-worker.sh:50`; semaphore `lr-move-lib.sh:180-185` (`locks/swap-slots`, shared with reconciler `lr_recon/__main__.py:89`, `lr_recon/admit.py:255`) | `LR_MOVE_SLOT_WAIT_S` 600 s, poll 2 s, `lr-move-worker.sh:138-141` |
| upgrade drainer | serial (1) by design ("sessions go one at a time") | `scripts/limit-recover/lr-upgrade.sh:15`, loop gap `:3067`, `LRU_GAP_S`=10 at `:92` | none |
| display | `bin/cc-lr:1232-1233` prints both widths | | |

## Per-session wall clock: queue wait vs service (MEASURED)

| lane | queue wait | service | source |
|---|---|---|---|
| recover (poller-drained `requests/<sid>.json`, attempts=1) | n=26 (2026-09-29 to 10-11): p50 175 s, p75 520, p90 1128, max 1471; 4 over 600 s | --one run start to verdict.txt mtime, n=446 runs: RECOVERED n=67 p50 85 s, p90 674, max 2029; FAILED n=172 p50 8 s; parked n=157 p50 8 s | python over `results/*.retired.json` + `requests/*.json` (`ts` to `last_attempt_epoch`); `fleet/one-*/results.tsv` col 6 |
| recover, live case slot wait | 5507881f and 58d3640a: "at its cap (2 live recoveries)", 03:16:01/06 to slot free about 03:18:51 = **165-170 s** | 00b363d4 174 s, 3df4b1b4 172 s, 5507881f 552 s (HELD:unreachable), 58d3640a 1497 s (FAILED) | `fleet/one-20261011T0315*/detached.log:1`, `rank.timing`, verdict mtimes |
| move | request to MOVE-BATCH start: 89, 221, 67, 2, **896 s**; start to admitted: 4, 47, 33, 3, 81 s | per session, slot to result: 120-218 s at load1 20-24 (7/7 MOVED); 719-1233 s at load1 186-1017 (0/8); slot wait 0-195 s (3/7 waited 167 s in the 7-session batch) | `move/*/batch.log`, `poller.log` MOVE-BATCH lines, `move/*/*.events.jsonl` t_ms |
| upgrade (serial) | n=10: 8 at ≤10 s, then 579 s and 1447 s (the latter queued behind a 1359 s fire) | 11-569 s (one 14396 s, parked until idle); fire step 56-190 s at load1 26-36, 153-1359 s at 178-198 | `upgrade-state/*.json` (req id epoch to run dir ts to terminal_ts), `upgrade/*/events.jsonl` |
| poller tick (the intake clock) | since 10-04: 808 ticks, span p50 58 s, p90 217 s; 27 ticks ≥600 s, 12 ≥1200 s, max 5290 s; start gap p50 678 s (600 s requested) | live tick 03:15:46 to 03:41:09 = 1523 s: request lane 03:15:57-03:16:06, census to 03:17:26, CONSOLIDATED 03:21:21, parked loop 1188 s / 31 records = **38 s/record** | `poller.log` TICK start / last line per tick |

---

## C3-1 — Intake runs once per tick, ahead of an unbounded parked loop, so a request filed mid-tick waits out the rest of the tick plus the next interval

- **Symptom:** the move batch filed 03:26:13Z started 03:41:09Z (896 s). The three `cc-lr recover` requests filed 03:24-03:26Z had no run by 03:45Z. `cc-lr rotate --all` gave up at 600 s with "7 still in flight" before the batch had even started.
- **Frequency (MEASURED):** recover queue wait p90 1128 s, max 1471 s (n=26). Move queue wait was ≥221 s in 2 of 5 batches and 896 s once. 27 of 808 ticks since 2026-10-04 lasted ≥600 s, and while such a tick runs, intake is closed.
- **Root cause:** `lrp_move_kick` runs at tick start (`scripts/limit-recover/lr-reset-poller.sh:314`) and again only in the EXIT trap (`:241-246`). The request lane `for _rq in "$REQUESTS"/*.json` runs once (`:1198`), before census, CONSOLIDATED (`:1997`) and the parked loop `for pf in "$PARKED"/*.json` (`:2127`). The parked loop has no time budget: it forks python, reroute and registry probes per record (`:2129-2240`). launchd fires only on `StartInterval` 600 (`~/Library/LaunchAgents/com.reso.lr-reset-poller.plist`, no WatchPaths). A `launchctl kickstart` sent while a tick is running is dropped (`bin/cc-lr:1425-1431` comment), so `cc-lr`'s 15 s re-kick (`bin/cc-lr:1664-1668`) cannot help.
- **Fix:** split intake out of the tick. Add a small launchd job (`com.reso.lr-intake`) with `WatchPaths` = `requests/`, `move/requests/` (ThrottleInterval 10). It runs only the request lane and `lrp_move_kick`, factored into a sourced function file, under its own lock (not the tick's `$LOCKD`). If that is too large, the alternative is a deadline on the parked loop (`LRP_PARKED_BUDGET_S`, default 120): persist a cursor and run `lrp_move_kick` plus the request lane again when the budget expires. Bats: fixture of 31 parked records with a stubbed `reroute_parked` that sleeps 1 s. Start the poller, then drop `move/requests/X.json` 2 s in. Assert `MOVE-BATCH started` appears in `poller.log` within budget+5 s, not at tick end.
- **Size:** M. **Conviction:** 80.
- **Receipt:** `grep -E '^2026-10-11T03:(1[5-9]|[2-5][0-9])' poller.log` gives TICK start 03:15:46, REQUEST lines 03:15:57-03:16:06, CONSOLIDATED 03:21:21, MOVE-BATCH started 03:41:09, next TICK start 03:51:11. `move/20261011T032613Z-*/batch.log` shows "admitted" 03:42:30.

## C3-2 — Three independent caps: the actual boot ceiling is 2+4+1 = 7, not the 4 the width rationale cites

- **Symptom:** the move semaphore's comment says it bounds "more than 4 overlapping TUI boots (the largest overlap in the 49 boots on record)" (`lr-move-lib.sh:168-172`). But --one recoveries and upgrade relaunches boot sessions outside that semaphore.
- **Frequency (MEASURED):** 2 of 4 completed move batches overlapped ≥1 --one run, and 2 of 4 overlapped an upgrade run (python join of `move/*/batch.log` windows against `fleet/one-*` start-to-verdict and `upgrade/*-<ts>` dirs). Batch 20261010T051618Z overlapped both: 5 workers at width 4, plus 1 --one, plus 1 upgrade, and **0/5 moved**. Up to 10 `--one` processes were alive at once (start to verdict, including slot waiters).
- **Root cause:** `lr_swap_slot_acquire` is called only by `scripts/limit-recover/lr-move-worker.sh:138` and the reconciler (`lr_recon/__main__.py:89`). `lr-fleet.sh --one` takes its own `one-slots` (`lr-fleet.sh:1496-1530`). `lr-upgrade.sh --drain` takes no slot (`:3067` gap only). `grep -rn lr_swap_slot_acquire scripts bin` confirms this.
- **Fix:** make `locks/swap-slots` the one boot semaphore. `lr-fleet.sh --one` takes a swap slot around its actuation (from precheck admitted to `lr-handoff` return; keep `one-slots` as the per-lane fairness cap). `lr-upgrade.sh` takes one around fire+relaunch. Bats: pre-create 4 swap slots held by `sleep` pids, run `lr-fleet.sh --one` with stubbed `lr-handoff.sh`, and assert it logs a swap-slot wait and the stub is not invoked until a holder exits. Mirror that for `lr-upgrade.sh --drain`.
- **Size:** M. **Conviction:** 60 (the bypass is certain; that >4 concurrent boots *causes* failures is not proven, because 051618Z also had load1 128-228).
- **Receipt:** `grep -rn "lr_swap_slot_acquire\|one-slots" scripts bin` shows only `lr-move-worker.sh:138`, `lr-fleet.sh:1496/1506/1510`. The overlap python printed `20261010T051618Z overlapping --one runs 1 upgrade runs 1`.

## C3-3 — Width is fixed. Outcomes split by load, and load is already recorded: the width should narrow on load5 per core

- **Symptom:** under high load the width-4 lane does not fail fast. It holds all slots in 900-1000 s actuations that end in HELD/FAILED, while queued workers time out.
- **Frequency (MEASURED, capacity-alarm load joined to batch windows):**

  | batch | load1 during | result |
  |---|---|---|
  | 20261006T060534Z | 20-24 at admit, rising to 150 during the batch | 7/7 MOVED |
  | 20261010T053236Z | 43-53 | 2/2 MOVED (bb1d86c8, c56c729c) |
  | 20261010T051618Z | 128-228 | 0/5 (3 source-ambiguous, bb1d86c8 HELD:pane:resolver-unavailable, c56c729c HELD:composer-unreadable) |
  | 20261010T012444Z | 186-1017 | 0/8 (3 exit-readback after 917-1024 s actuate, 3 slot-wait timeouts, 1 source-ambiguous, 1 busy) |

  The same two sessions were HELD at 160-228 and MOVED 15 min later at 43-53. Upgrade fire took 56-190 s at load1 26-36 and 153-1359 s at 178-198 (n=7, `upgrade/*/events.jsonl` load1). Over 2 days (n=2357), load5 was p50 24, p90 159, p99 596. load5/core was above 3 in 40% of samples, above 10 in 14%, above 20 in 7%. Memory pressure level 1 in 2319/2357.
- **Root cause:** width is a constant: `lr-move-worker.sh:50` (`${LR_MOVE_SLOTS:-4}`) and `lr-fleet.sh:1497-1499` (`${LR_ONE_MAX_CONCURRENT:-2}`). Neither caller reads load, although `lr-upgrade.sh:2019` (`lru_load1`) and `lr_recon/clock.py:160` already do.
- **Fix (values proposed, not applied):** add `lr_effective_width <static>` in `lr-lib.sh` that reads `sysctl -n vm.loadavg` field 2 (load5) divided by `hw.logicalcpu`, with test seam `LR_LOAD5_PER_CORE`. Bands: below 5/core keep the static value; 5-10 gives 2; 10-20 gives 1; above 20 gives 0 (hold: no new grant, and the wait does not count toward the per-worker timeout, see C3-4). Apply it at each acquire attempt in `lr-move-worker.sh:138` and in `lf_one_slot_take` (`lr-fleet.sh:1502`). The bands are down-only, never above the static value, as C18 requires (`scripts/handoff-fire.sh:9320-9326`). Do not use load1: it swung 186 to 994 within 2 min on 2026-10-10 01:31-01:35Z. Do not use memory pressure or the capacity-alarm verdict (never OK: WARN 1255 / ALARM 1102 of 2357). Bats: with seam 25 assert `lr_effective_width 4` gives 0 and the worker logs `slot-wait (load-held)`; with 7 assert 2; with 1.5 assert 4; with the seam unset and sysctl stubbed unreadable, assert the static value is used (fail-open).
- **Size:** M. **Conviction:** 55. Small n (4 batches, 7 fires). The source-ambiguous failures may be a bug that is independent of load. Doctrine at `handoff-fire.sh:9305-9333` turned the load term *off* for the spawn gate, because a resident session adds about 0 load. This proposal gates boots, which do add load: one batch took the box from 20 to 150. That distinction still needs an explicit design note.
- **Receipt:** `jq -r '[.ts,.load_1m,.load_5m,.pressure_level]|@tsv' ~/.claude/logs/capacity-alarm.jsonl` over the windows above, plus the gz archive for 10-06. The move per-session python printed the slotq/actuate/post splits.

## C3-4 — Per-worker slot-wait and unbounded slot holds turn queueing into NOTMOVED and halve the --one lane

- **Symptom:** in batch 20261010T012444Z, 3 of 8 sessions ended `NOTMOVED: slot-wait: no move slot freed in 600s` with nothing touched. All 4 slot holders sat in `actuate` for 351-1024 s. In the live case, 58d3640a held one of only 2 --one slots from about 03:18:51 to 03:41:02 (22 min), the last 936 s after "admitted".
- **Frequency (MEASURED):** 3/31 move session records across 5 batches were slot-wait timeouts, all in the one high-load batch. One --one run held a slot for 1497 s total (live case). RECOVERED p90 is 674 s, max 2029 s.
- **Root cause:** the deadline is per worker and fixed: `lr-move-worker.sh:140` (`LR_MOVE_SLOT_WAIT_S` 600), set at worker spawn. The actuation holding the slot has no wall bound scaled to load: `lr-handoff.sh:1555` runs `lr-transplant.sh` unbounded, and `LR_MOVE_PROVE_S` 300 (`lr-move-worker.sh:175`) starts only after actuate returns. The --one slot is held across the whole run (`lr-fleet.sh:1833` take, released at exit).
- **Fix:** (a) The slot-wait deadline extends while every holder is alive and progressing, judged by the holder's `events.jsonl` mtime advancing; it expires only when holders stall. Pair this with C3-3's hold state. (b) Add an actuation wall bound `LR_ACTUATE_MAX_S`, load-scaled the same way as `hf_load_scaled` (`handoff-fire.sh:3974`), and wrap the transplant call in `lrp_bounded`-style `timeout`. Bats: 4 holders that touch their events file every 1 s, plus a 5th worker with `LR_MOVE_SLOT_WAIT_S=3`. Assert the 5th is still waiting at 5 s, and that it takes a slot when a holder exits.
- **Size:** M. **Conviction:** 60.
- **Receipt:** `move/20261010T012444Z-*/{6defb493,7f70bfc4,e582464c}*.events.jsonl` show result "slot-wait … 600s". The python split shows the holders' actuate at 1024/351/917/918 s. `fleet/one-20261011T031606Z-58d3640a/results.tsv` ends at 2026-10-11T03:41:02Z.

## C3-5 — Service time after admission is not decomposable: no stage events and no load stamp in the --one or move lanes

- **Symptom:** 58d3640a's bundle `events.jsonl` ends at `03:25:26 admitted`, and `transplant.json` is empty. The 936 s until FAILED at 03:41:02 has no stage, no duration and no load. Move events carry `t_ms` but no load. Only lr-upgrade steps carry `dur_s` and `load1`.
- **Frequency (MEASURED):** 1 of 3 lanes records duration+load per step (48 lru-step rows across 34 upgrade runs). The --one lane recorded 0 post-admission stage events in the live case.
- **Root cause:** `lr-handoff.sh:1555` calls `lr-transplant.sh` with no `lrh_state` before or after. `lr-transplant.sh` (rsync at `:904`, `:910`) emits no events. `lr-move-worker.sh` `ev` writes stage+t_ms only. Compare the lru-step format at `lr-upgrade.sh:2019`.
- **Fix:** add `lrh_state transplant start` and `lrh_state transplant end "rc=… dur_s=… load1=…"` around `lr-handoff.sh:1555`. Add `load1=` to `lr-move-worker.sh` `ev`. Bats: stub `lr-transplant.sh` that sleeps 2 s and exits 1; assert the bundle `events.jsonl` has stage `transplant` with `dur_s>=2` and a `load1=` field.
- **Size:** S. **Conviction:** 75.
- **Receipt:** `jq -c '{ts,state,stage}' ~/.reso/limit-recover/58d3640a-*/bundle-20261011T032034Z/events.jsonl` gives 3 rows, the last `admitted` at 03:25:26. `stat` shows `transplant.json` mtime 03:25:26 and empty content.

## C3-6 — Lead-turn cost per recovery: about 1 call when intake is free, 30+ round trips when it is stuck and nothing says why

- **Symptom:** the requesting lead polled and then diagnosed the poller by hand. 14 Bash calls between 03:39:20 and 03:40:58 went on finding pid 91502 stuck in the parked loop. The run ended with `cc-lr move --abort`.
- **Frequency (MEASURED):** live case f1b9b388, 03:20:14 to 03:42:30Z: **33 API round trips**, 31 tool calls, 4,044,513 cache-read, 132,601 cache-create, 20,499 output tokens, max context 148 K, 0 sessions recovered. Nominal case 92928fee: `cc-lr recover 11` then 0 status/poll calls. Prior baseline (`docs/research/lr100p-2026-09-19/PLAN_DRAFT.md:89-90`): 146 tool calls and 24.4 lead-minutes of polls for 5 sessions (about 29 calls per session).
- **Root cause:** the wait loops in `bin/cc-lr:1652-1687` (rotate) and `:1450` (move) count "left" but never say *who* holds the work. They don't distinguish a batch that has not started (request still in `move/requests/`) from one in service, and they never read the tick's age or phase (TICK start line, last poller.log line). `CC_LR_ROTATE_WAIT_S` 600 (`bin/cc-lr:1574`) is shorter than the measured queue wait p90.
- **Fix:** in the rotate/move wait loop, when `move/requests/<batch>.json` still exists or a recover request has no `fleet/one-*` run, print once: `queued: intake is held by poller tick pid P (started N s ago; last phase "<last poller.log line>")`. Return rc 1 early with that line instead of spending the 600 s. Bats: fixture `poller.log` with `TICK start` 1200 s ago and no MOVE-BATCH, plus a move request file. Assert `cc-lr rotate --all` (wait 2 s) prints `queued: intake is held by poller tick`.
- **Size:** S. **Conviction:** 60 (the token saving is estimated: it removes about the 14-call diagnosis).
- **Receipt:** `grep "\[f1b9b388" ~/.claude/logs/bash-commands.log` gives the timeline. jq over `~/.claude-quaternary/projects/*/f1b9b388-*.jsonl` assistant usage, unique message ids, gives api_calls=33 cache_read=4044513.

---

## Ruled out (with the measurement that rules it out)

- **Shared HTTP/SSE MCP daemon instead of per-session stdio.** The only stdio server in every account config is `ms365` (`jq .mcpServers` over `~/.claude.json` and `~/.claude-{next,quaternary,secondary,tertiary}/.claude.json`); `motion`/`motion-plus` are already HTTP, and `~/.claude-next4` has none. MEASURED with `ps`: 36 `ms-365-mcp-server` processes, 860 MB RSS total, about 45 MB fresh, 0.85-1.41 s lifetime CPU each. That is about 1-2 s of CPU per boot (estimated, including the `npm exec` wrapper), against a minimal session boot of about 6.5 s CPU (pid 36584 at 6:42 elapsed) and service of 85-218 s. Memory is not binding (pressure level 1 in 98% of samples). Installed v0.143.0's `--http` mode enforces an OAuth bearer per request (Softeria docs via search), so each config dir would need its own OAuth login. It is feasible but not a recovery-speed lever.
- **SessionStart memo/skip on transplant resume.** The dispatcher already runs its children in parallel (`hooks/session-start-dispatch.sh:53-56`) under a 9 s kill bound (`:41`, `:65`). Prior measurement put the SessionStart span at p50 2.5 s / p95 7.8 s (`docs/research/concurrency-scale-2026-10-04/j-startup-hang.md:37`). The ceiling saving is ≤9 s per boot, against queue waits of 175-1471 s. Skipping also changes what the resumed model sees.
- **kqueue/fswatch instead of polling.** `fswatch`, `watchexec` and `entr` are not installed (`command -v` empty). The polling loops are `lr-move-worker.sh:114/141/194` (5/2/2 s), `lr-move-batch.sh:233` (2 s), `lr-fleet.sh:577/939/1249/1527` (1249 = 5 s engagement wait on the transcript via `lr_engaged_after`, `lr-lib.sh:126`), `lr-fleet.sh:1503` (10 s one-slot), `lr-upgrade.sh:1288/1761/1970/2253/2736/2764`, and `bin/cc-lr:1059/1450/1686/2247/2407`. Granularity adds poll/2 on average (1-5 s), while the measured waits are 64-1024 s of boot/readback. The proof loop judges process state (`ps -E`, registry: `lr-move-lib.sh:16-21`, `:82`), not the transcript. Only `lr-fleet.sh:1249` is a pure transcript wait (python `select.kqueue` would fit, saving about 2.5 s on average).
- **Raising static widths above 4.** No measurement exists above 4 overlapping boots (`lr-move-lib.sh:168-172`), and the 7-session width-4 batch alone moved load1 from 20 to 150.
- **Memory pressure, load1, or the capacity-alarm verdict as the width signal.** Pressure is level 1 in 2319/2357 samples. load1 swings 5x within 2 min. The alarm's per-core thresholds (warn 1.5, alarm 2.5) sit at or below the box's median (2.4/core), so the verdict is never OK.
- **Parallelising the upgrade drainer.** Queue wait was ≤10 s for 8/10 sessions. Serial is a deliberate fix for post-exit admission refusals (`lr-upgrade.sh:12-16`). The 1447 s outlier is a load-stretched fire, so fixing it belongs to C3-3/C3-4.

## Uncertain

- Who owned the three 03:24-03:26Z `cc-lr recover` requests. `recon.on` has been present since 2026-10-10T14:47Z, so `*.cc-lr.json` requests go to the reconciler when it is live (`lr-reset-poller.sh:1205`). The poller paged "reconciler heartbeat is stale" at 03:51:12, so their queue wait may belong to the reconciler, not to tick 91502. The move batch's 896 s is unambiguously the tick's.
- What 58d3640a did for the 936 s after admission. No events exist (C3-5). The rsync `mkstempat … No such file` errors suggest the destination vanished mid-copy, but its duration is unmeasured.
- Load causality. n=4 batches and 7 fires, with mixed failure classes (the repo lesson "aggregate correlation refutes the obvious cause" applies). The same-session HELD-then-MOVED pair is the strongest single comparison.
- Recover queue waits of 1-3 s (3 of 26) mean some requests met an idle poller kicked by `kickstart`. The p50 therefore mixes two populations: kicked-idle and mid-tick.
- Deviation: one scratch file was written outside the delivery path (`/tmp/c3_upg_steps.tsv`, derived from `upgrade/*/events.jsonl`). It was left in place because `rm` is forbidden.
