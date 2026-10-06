# x — hostile review of "remove the memory gate and raise the concurrency caps"

Date 2026-10-06 (about 06:35-07:00Z). Read-only: source, git history, records under `~/.reso/limit-recover/`, `~/.claude/logs/`,
`ps`/`lsof`/`netstat`/`launchctl limit` on kitty. No lr-* tool, cc-lr, cc-limited or claude-accounts was run. No pane touched.
Tags: MEASURED = I ran the command; READ = source, commit or record text; INFERRED = derived. Sibling slots are cited as READ.

## Answer

- No cap and no serial section in the four files names memory as its reason. The only memory terms on the path are the capacity
  probe's headroom and compressor-segment terms; every numeric cap (2, 2, 4, 4 per account per tick, 3 per account per tick, drain
  serial + 10 s) was set for something else. READ (table 1).
- What they protect: (a) the target account (one routing decision at a time, stampede onto one account, first-turn bursts),
  (b) kitty's single control socket and the TUI boot burst, (c) "nothing refuses after /exit" (a pane stranded at a bare shell),
  (d) one actuator per pane and per transcript, (e) runaway fan-out from a launchd tick.
- During the one multi-session batch on record (7 moves, width 4, 06:07-06:14Z) memory headroom stayed 33.1-34.9 GB and segments
  4.1-4.6 %, while load1 went 20.1 -> 150.5 on 10 CPUs and 2 of 7 relaunches (29 %) raised `recycle-boot-indeterminate`.
  MEASURED (`capacity-alarm.jsonl`, watcher logs). Causation of the load rise is confounded (section 6).
- Worst plausible failure at 10 concurrent: kitty's remote-control thread dies (the 2026-10-01 outage), with up to 10 panes past
  `/exit` at a bare shell and no way to type the relaunch; the cure is a kitty restart that ends every session. The fix for that
  outage is not on the live kitty (section 3).
- The missed dimension: a rotation is not reversible. Each hop leaves a tombstone in the store it left, and the recover lane refuses
  any target whose store holds one. 11 of 30 live sessions already have 1-2 accounts they cannot return to; 3 have one fresh
  account left (section 4).

## 1. Every cap and serial section: stated reason, and whether it still holds

| # | Bound (default) | Where | Reason given (non-memory unless marked) | Still true? Evidence |
|---|---|---|---|---|
| 1 | `LR_RECOVER_MAX_CONCURRENT` 2 | `lr-fleet.sh:1340-1365`; commit `c7ed6837e` 2026-09-21; spec `LIMIT_RECOVER_100P.md:365` | Source gives no reason for the number. `LIMIT_RECOVER_FLEET_V2.md:510` (decision 8, ruled 2026-09-30): "Burst protection stays as it is: 2 concurrent recoveries on the live legacy lane, then the 3-per-account first-turn pacer after the reconciler cutover" | Unmeasured, not refuted. 0 of 40 first turns failed at N=2..6 cold starts, one-word `claude -p`, "bounds cold-start bursts, not long turns" (`kmax-decision-8.md:5,42`). N>6 never run. The pacer that was to replace it is not live: `recon.on` absent (MEASURED `ls ~/.reso/limit-recover/`, `recon/ctl/` empty) |
| 2 | `LR_ONE_MAX_CONCURRENT` 2, wait 900 s | `lr-fleet.sh:1368-1384`; commit `7e16ce5f7` 2026-09-29 | The unattended lane "had no cap at all"; the poller could start 4 per account per tick, 16 across four accounts; "until the reconciler's admission is wired (D1.12)" | True as a runaway guard. Binding in 38 runs (q1d, READ). The reconciler admission it waits for is wired in code (`lr_recon/admit.py:87`) but not acting |
| 3 | Admit lock, one rank -> assign -> probe at a time; wait 600 s then steal | `lr-fleet.sh:580-602`, `:969-975` | "every worker picks the same account" and "N probes mint N" (`:582-585`, `:1357-1359`). Wait raised 300 -> 600 s because "the second or third waiter reached the time-based steal while the holder was still alive" (`:599-602`) | True. Also a hidden coupling to cap 1-2: see section 2, failure B |
| 4 | Per-sid run claim | `lr-fleet.sh:91-94`, `:1512-1522`; `lr-move-batch.sh:163` | "the third writer typing into one pane" | True; keep |
| 5 | Poller tick lock, skip not queue | `lr-reset-poller.sh:205-231` | 2026-07-26: "FOUR concurrent `--resume 076a1186`, three spawned within ~90 s, ~1.9 GB and four processes appending to ONE transcript" | True. Memory is named as a symptom; the damage is four writers on one transcript |
| 6 | `RQ_MAX_PER_TICK` 4 per account per tick; `MAX_PER_RUN` 4; `MAX_PER_WT` 1 | `lr-reset-poller.sh:1113`, `:1317-1319`, `:403-410` | "A 30-death cohort otherwise started 30 detached drivers in one tick"; 2026-07-21 sprawl: 14 parked sessions in one worktree all came up | True. With tick interval p50 637 s (q1d, READ), 10 limited sessions on one account need 3 ticks, about 21-32 min, whatever caps 1-2 are set to. INFERRED |
| 7 | `LR_WAKE_PER_ACCT` 3 per account per tick, jitter 0-90 s after reset + 120 s | `lr-reset-poller.sh:1299-1305`; `ARCHITECTURE.md:213` | First-turn pacing per target account, "burst protection; limiter behaviour is unmeasured above N=6" | Unmeasured above 6 |
| 8 | Upgrade/switch drainer: one, serial, `LRU_GAP_S` 10 s | `lr-upgrade.sh:13-16`, `:2395-2397`; `lr-reset-poller.sh:1219-1229`; `bin/cc-lr:733-738` | (i) "capacity-admit refused the relaunch AFTER /exit, stranding 3 panes at a bare shell" so "sessions go one at a time"; (ii) "an upgrade and a switch of the same pane can never interleave, and a --all-idle batch cannot stampede one target account"; (iii) idle is re-judged at execution; (iv) never inside the tick lock | (i) superseded for no-prompt moves (`LR_ADMIT_MODE=swap`, nothing refuses after /exit, `lr-move-worker.sh:20-23`). (ii) half true: per-pane exclusion now has its own locks; the stampede guard has no replacement in the move lane (section 4). The double-drive defect that the serial drain masked is fixed (`lr-upgrade.sh:2380-2392`, F2 2026-10-04) |
| 9 | `LR_MOVE_SLOTS` 4, held from before /exit to first proof | `lr-move-lib.sh:168-179` | "more than 4 concurrent kitty RPC streams, and more than 4 overlapping TUI boots (the largest overlap in the 49 boots on record)"; "default 4 until a canary measures a safe width" | True and still unmeasured above 4. The one batch at 4 tripped the design's own back-off signal (section 2, evidence row) |
| 10 | Move-admit lock; router read once, fail closed; preseed once | `lr-move-batch.sh:7-15` | "the old fail-open path admitted an excluded target at 16:41Z on 2026-10-04"; "15 workers never contend the 2 s .claude.json lock that silently skips the seed" | True; keep |
| 11 | Kernel-safety read: segments < 90 %, headroom > 4 GB | `lr-move-worker.sh:128-135`, `lr-move-batch.sh:151-155` | MEMORY. Active, load and reserve terms are switched off for a move | 0 of 8 refusals in the batch (q1d, READ). Load term off means nothing but row 9 bounds CPU |
| 12 | Active ceiling 8, reserve 1 (recover lane) | `capacity-admit.sh:92-93` | Counts sessions mid-turn plus unredeemed tokens; a turn-concurrency bound | True; it is the most common "capacity" refusal (8 of 9 lines, q1d READ). It becomes the binding term the moment caps 1-2 rise |
| 13 | Reconciler bounds: boot AIMD start 6, +2 / halve, floor 2, cap 12; kitty reads <= 4; pacer 3 per account | `ARCHITECTURE.md:575-590`; `lr_recon/admit.py:255-269` | Boots are "the resource that failed at load 40+ on 2026-09-19" (`LIMIT_RECOVER_100P.md:391`: "relaunch typed but no claude process appeared within 90s on a box at load 40+") | Design only; observe mode |

Reasons the brief asked about that I did not find as a stated reason for any cap: keychain or credential contention, OAuth rate
limits. They exist as hazards in prior research, not as cap rationale: one unbounded `secd` keychain query per boot
(`~/.reso/limit-recover/design-swap-v3/concurrency.md:131-133`, READ); refresh tokens rotate and a rotation revokes the old access
token within 7 s, serialized only by a per-config-dir lock (`design-swap-v3/credential-plane.md:27-33`, READ;
`bin/claude-accounts:24-34`). A relaunch under the target's own config dir joins the target's lock domain, so N boots add no new
refresh race (`credential-plane.md:49-52`, READ). 0 auth failures in `handoffs.jsonl` since 2026-10-04T16:50Z (MEASURED, `jq` +
`grep -c`, n=37 recycle-intent rows).

Focus and keystroke races are guarded per pane (`lr_focus_gate`, composer gate, /exit read-back), not by any cap; kitty marks at
most one pane focused (`LIMIT_RECOVER_FLEET_V2.md:503`). Width does not weaken those gates. INFERRED residual: the pane is a bare
shell for 9-17 s normally and 71-120+ s in the stalls below, and nothing can gate operator keystrokes there; exposure scales with
width times that window.

## 2. What a wider rotation would break

Evidence from the only batch (`move/20261006T060534Z-next3-next2-64630`, n=7, width 4):

| Reading | Value | Source | Tag |
|---|---|---|---|
| headroom during 06:03-06:18Z | 32.8-34.9 GB, flat | `~/.claude/logs/capacity-alarm.jsonl` `headroom_gb` | MEASURED |
| compressor segments | 4.1-4.6 % | same, `seg_pct` | MEASURED |
| load1, 10 CPUs | 17-24 (06:00-06:08) -> 42.9 (06:09:43) -> 119.3 (06:11:48) -> 150.5 (06:12:55) -> 111-140 to 06:19 -> 28 (06:24) | same, `load_1m`; the 61 s sampler skipped to a 125 s gap at 06:09:43 | MEASURED |
| processes in kitty's coalition | 180 -> 334-356 | same, `coal_true_procs` | MEASURED |
| relaunch typed -> launcher's first line, panes 15 and 16 | about 120 s and 71 s; both launchers and both watcher alarms stamped 06:12:38Z | bundle `events.jsonl`, `$TMPDIR/handoff-recycle-{15,16}-*.log` | MEASURED |
| `recycle-boot-indeterminate` alarms | 2 of 7 (29 %), at 3 concurrent | same logs; `~/.claude/handoff-alarms/alarm-20261006T061238Z-*` | MEASURED |
| reconciler's rule for that signal | "halve on any > 45 s or a boot INDETERMINATE" | `ARCHITECTURE.md:581` | READ |
| batch summary and the one mail | `"verdicts":"none"`, "done: no rows", for 7 MOVED | `summary.json`, `batch.log` (bash 3.2 parse error at `lr-move-batch.sh:80-83`; found by q1d) | READ |

By the fleet design's own rule, this record argues for width 2 on the next wave, not 10.

Failure modes at 10 concurrent, worst first:

| | Failure | Mechanism and receipt | Cheap guard |
|---|---|---|---|
| A | kitty control socket dies; up to 10 panes at a bare shell after /exit; restart ends every session | 2026-10-01: socket stuck at 128 queued connections, 59 zombies, about 10 h, 31-32 sessions restarted (`kitty-deadlock-recovery-2026-10-01.md:26,33`, `pane-lifecycle-fixes-2026-10-01.md:21,38`). Root cause: talk thread exits for good on an `accept()` error, EMFILE at about 75 % conviction, reached when the main thread is deaf under load 120+ and abandoned clients pile up as fds (`session-durability-2026-10/C3-socket-robustness.md:11-24`). Live now: kitty 64211 is stock 0.48.2 (0 `still serving` strings, 2 stock `accept() on talk socket failed`; `strings` on the loaded `.so`); soft fd limit 256 (`launchctl limit maxfiles`); no `watcher` line in `kitty.conf`; 35 numeric fds, queue 0 (`lsof`, `netstat`). Load 150 was reached today. No client-side RPC gate exists outside the reconciler (`git grep`). MEASURED | Before each /exit: hold (NOTMOVED, nothing touched) when `hf_kitty_queue_depth` >= 8 or kitty's numeric fds > 150; both readers exist in `scripts/lib/kitty-queue.sh`. Operator step outside this plan: deploy the built talk-thread patch (`35979ed78`) or the fd-limit watcher |
| B | Recover pool >= 7 on a refusing box steals the admit lock from a live holder: two workers routed against one reading | A parked worker holds the lock for `LR_FLEET_CAP_WAIT_S` 120 s (`lr-fleet.sh:547`, `:588`); waiters steal at `LR_ADMIT_LOCK_WAIT_S` 600 s (`:605`, `:623-629`); 600 / 120 = 5 holders, so waiter 7 steals. Cap 2 means at most one waiter. Each recovery adds a first turn, so the active ceiling 8 is reached by the pool itself. INFERRED, not reproduced | Scale the wait to pool x 130 s, or release the lock for the park and requeue |
| C | One target account takes the whole cohort | Move lane: one `--to` per batch, checked only for membership in `--rank general` (`lr-move-batch.sh:128-150`, `bin/cc-lr:1270-1274`). After the batch next2 held k = 11-13 live sessions, next 2, next4 2 (`account-utilization.jsonl` 06:13-06:41Z, MEASURED). `KMAX` was lifted 8 -> 24 on 2026-10-04 (`23ea68c5c`: "Above N=6 concurrent work per account is still unmeasured here; 529 ... are the signal to lower it"), so the router no longer limits stacking. Recover lane: `LF_SOFT_FALLBACK` takes an account excluded for `kmax-concurrency` or `recovery-*-thin` rather than park (`lr-fleet.sh:815-835`). Precedent: 2026-09-10, `/limit-recover` reached about 13 panes inside 8 s; `next` went 23 -> 100 % of its 5 h window in 28 min, next3 +41 pp in 5 min; "cache writes of 250-750k-token contexts, paid once per slot and once per cold resume" (`limit-cascade-2026-09-10.md:3-8,13-17,32-34`) | Per-row targets from the router with a per-account cap per batch; refuse a single `--to` above that cap unless forced |
| D | Registry rows lost at load, so the list command goes blind to moved sessions | `session-register.sh` has a 5 s timeout and "loses rows at load 30-50" (`lr-move-lib.sh:74-77`). 0 of 7 lost today. READ | Already reported as MOVED-UNREGISTERED; the list command should union `--resume` processes, as `lr_move_holders` does (`lr-move-lib.sh:57-59`) |
| E | Poller lock reaper never finishes | `LOCK-REAP rc=124` on 309 of 309 logged runs; 152 files in `locks/`; 70 `CLAIMED-NOT-LIVE` lines in the 06:31Z tick (`poller.log`, MEASURED). Each rotation adds a lock and a `.launch` file | Raise the reaper's bound or batch it; not urgent |

## 3. Is the kitty fix deployed? (the receipt behind failure A)

- `git show 35979ed78`: patch built into `~/ktb-noband` only. `W3-build-plan.md:481`: "Built, not landed." READ.
- Live binary: `/Applications/kitty.app/.../kitty.fast_data_types.so` dated Jul 30, 0 matches for the patch's log string. MEASURED.
- kitty 64211 started 2026-10-06T00:43:28Z, so it has been restarted again since the 10-01 restart (pid 48854). MEASURED `ps`.
- Mitigation that did land: a recycle on an already-deaf kitty is held before recycle-intent (`e66bf5760`); `cc-restore` exists
  (`08c9f3845`). Neither helps panes already past /exit when the thread dies.

## 4. The dimension likely to be missed: rotations are not reversible

- `_lf_target_holds_sid` refuses any target whose store holds `<sid>.jsonl` or `<sid>.jsonl.handed-off` (`lr-fleet.sh:669-681`,
  `:796-799`); incident 2026-09-19/20, `07e30aeb` "died on that refusal three times, deterministically" (`:664-668`). The move
  lane holds such a row as `hold:retired-source` pending `cc-lr repair-markers` (`bin/cc-lr:1099`).
- Live count (MEASURED, python over 5 stores and 30 registry sids): stores touched per session = 1 for 18, 2 for 8, 3 for 3.
  Three of today's seven movers (`7f5deb68`, `1c0f7f90`, `840ca76c`) are live on next2 with full `.handed-off` copies on next4
  and next3; their lock records `chain: [quaternary, tertiary, secondary]`. One fresh account is left for each.
- 117 of 176 FAILED recover rows are one transplant refusal, `lock-mismatch` (q1d, READ): residue from earlier hops is already
  the largest failure class, ahead of every capacity term.
- Consequence: "rotate all to the right accounts" at any width converges on sessions with no legal target. A zero-memory,
  width-N rotation reaches that state sooner. Related, same root: wider rotation concentrates sessions on fewer accounts, so the
  next limit event is a larger cohort than the one just moved (13 on next2 now).

## 5. Alternatives considered

- "The caps are leftover memory throttles": rejected; no comment, commit or ruling says so (table 1).
- "API burst (529) is the real reason for 2": partly. It is the ruling's stated reason, but 0 of 40 at N<=6 and it was never
  measured above; I found 0 such rows in `handoffs.jsonl` since 10-04 (weak instrument: retries are not persisted).
- "Credential or keychain contention": not a stated reason; prior research found no new refresh race for config-dir relaunches.
- "Just widen and let the kernel read protect the box": the kernel read has the load term off and saw nothing at load 150.
- "Use the reconciler's AIMD instead of a static width": supported by the design and by today's record; costs one state file.

## 6. Uncertainties

- The load spike is correlated with the batch, not attributed: pane 11 was recovered with a prompt at 06:10:22Z and the lead
  started this research soon after; 02-03Z had 14 samples at load >= 100 with no move batch (MEASURED hourly table).
- The two multi-pane stalls (68 s x 4 in wave 1 per q1d; 71-120 s x 2 in wave 2) have no identified cause. A stalled kitty main
  loop fits (typed text not executed, watchers silent, simultaneous release) but is not proven.
- kitty RPCs per rotation were not counted (`kitty @` is off limits). The 256-fd arithmetic for failure A is INFERRED.
- Failure B is arithmetic from source, not a reproduction.
- Per-resume quota cost on the target was not measured today; the 09-10 figures are for workflow-heavy Fable sessions.
- Whether a hop back onto a tombstoned store is refused inside `lr-transplant` for the move lane was not traced past the plan hold.
- n=1 move batch. Nothing has run above width 4.
