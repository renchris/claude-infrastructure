# F: what loaded the box, 2026-10-17T23:30Z to 2026-10-18T02:10Z, and what the move rail itself cost

## Answer

- **The box was CPU-saturated for the whole window.** It averaged 9.92 of 10 cores busy, and only
  766 idle CPU-s were left out of 96,640 CPU-s used. The 1-minute load was 168 to 531 by 10-minute
  bin, with a peak of 614 (measured: `~/.claude/logs/attrib.jsonl`, `~/.reso/load.jsonl`).
- **The account-move rail's own work was not a material share.** It cost about 1.4-1.8% of box
  CPU over the window, about 9-11 CPU-s per minute out of 600 (estimated, component model below).
  The detached-bash bucket that holds the rail is an upper bound and reads 1.56%, or 9.3 CPU-s/min
  (measured, attrib). The rail peaked at about 4-5% (24-29 CPU-s/min) only in the last 20 minutes,
  01:50-02:10Z. In those same minutes the load was **falling**, from about 530 to 259, because the
  TrueMemory work ended.
- **The load came from teammate and session work, led by TrueMemory tm2.** Teammate tool
  processes ("ghost") took 23.6%, teammate `claude.exe` binaries 7.1% and the TrueMemory lead
  session `ad2417e7` 7.1%. Interactive sessions took 35.7% in total, of which worktree-lane
  sessions were 20.1%. Unattributed short-lived CPU was 13.2%. The rusage run at 01:13-01:24Z
  (`docs/research/load-reinvestigate-2026-10-17/FINDINGS.md`) put TrueMemory at 62-75% of CPU
  once short-lived children are counted.

## 1. Load timeline (10-min bins, UTC)

The load columns come from `~/.reso/load.jsonl`. The CPU columns come from `~/.claude/logs/attrib.jsonl`
(42 rows; each row covers a 2-8 min interval, binned by the row's end timestamp). Each share is a
percentage of host busy CPU. Script: `/tmp/lri-f/timeline.py`.

| bin | load1 avg | load1 max | busy cores | ghost % | TM lead % | claude.exe % | other-501:bash % (rail ⊂) | Dia % | unseen % | rail activity (batch dirs) |
|---|---|---|---|---|---|---|---|---|---|---|
| 23:30 | 168 | 198 | 9.92 | 49.1 | 5.1 | 10.2 | 0.6 | 3.4 | 10.0 | none; 5 plans written at 23:57:45 |
| 23:40 | 442 | 608 | 9.99 | 20.2 | 4.9 | 3.6 | 0.5 | 9.2 | 10.2 | none |
| 23:50 | 456 | 554 | 9.99 | 21.4 | 2.0 | 7.0 | 0.4 | 4.8 | 13.7 | none |
| 00:00 | 503 | 589 | 9.97 | 25.5 | 2.0 | 11.4 | 0.8 | 2.1 | 12.1 | 3 census loops start (235745Z ×3) |
| 00:10 | 337 | 462 | 9.78 | 22.4 | 5.6 | 4.4 | 2.0 | 1.6 | 14.4 | + 2 single-worker actuations |
| 00:20 | 302 | 340 | 9.92 | 19.6 | 2.0 | 13.0 | 2.1 | 5.5 | 14.2 | + 1 actuation |
| 00:30 | 336 | 394 | 9.97 | 22.8 | 3.6 | 10.9 | 1.2 | 6.7 | 14.3 | 3 census loops |
| 00:40 | 304 | 367 | 9.94 | 30.5 | 3.7 | 7.5 | 1.5 | 0.8 | 13.8 | 3 loops enter one census that runs past 02:00 |
| 00:50 | 301 | 392 | 10.00 | 29.1 | 3.9 | 4.6 | 0.7 | 4.4 | 17.3 | same |
| 01:00 | 345 | 439 | 9.93 | 29.7 | 1.1 | 3.4 | 0.9 | 4.2 | 12.4 | waiting workers give up at 01:00:44 |
| 01:10 | 491 | 518 | 9.92 | 35.7 | 1.9 | 2.9 | 1.4 | 5.2 | 12.2 | (research-note rusage run 01:13-01:24) |
| 01:20 | 456 | 508 | 9.97 | 24.1 | 9.1 | 11.2 | 0.8 | 4.8 | 11.6 | none new |
| 01:30 | 483 | 542 | 9.97 | 17.5 | 27.3 | 6.9 | 0.6 | 4.8 | 10.7 | none new |
| 01:40 | 531 | 614 | 9.99 | 17.4 | 28.5 | 4.9 | 0.8 | 4.8 | 13.1 | none new |
| 01:50 | 349 | 568 | 9.96 | 6.5 | 7.6 | 8.5 | 4.6 | 6.4 | 13.4 | 6 batches admitted 01:50-01:54, 17 workers, 4 census loops |
| 02:00 | 259 | 294 | 9.56 | 5.3 | 4.2 | 4.2 | 5.3 | 3.3 | 18.0 | same, plus 2 more batches at 02:12 and 02:14 |

The capacity-alarm cross-check (`~/.claude/logs/capacity-alarm.jsonl`, 42 rows, every verdict
ALARM) gives load_1m 141 (23:31), 559 (23:50), 508 (00:07), 224 (00:18), 506 (01:20), 475 (01:45)
and 246 (02:01). Swap was 7.5-11.9 GB.

## 2. Consumer shares over the window (measured: attrib.jsonl, 23:30:05-02:09:59Z, 9,742 s, accounting "ok" on 42/42 rows)

Busy CPU was 96,640 CPU-s (9.92 cores). Of that, 83,852 CPU-s was attributed and 12,787 CPU-s was
unseen. Scripts: `/tmp/lri-f/attrib_window.py` and `/tmp/lri-f/sess_proj.py`.

| class | CPU-s | % of busy | what it is |
|---|---|---|---|
| **ghost** (tool processes tagged with a session id that has no live session root) | 22,839 | **23.6** | Teammate tool work. Teammate `claude.exe` processes are not session roots: 5 of 5 live teammates have no `sessions/<pid>.json` (checked at 02:30Z), so their tools read as ghost. The tm2 team (10 members, `~/.claude/teams/session-ad2417e7`) dominated per the research note. |
| registered sessions, total | 34,511 | 35.7 | the claude binary itself 9,319 (9.6%) + tools 24,380 (25.2%) + orphans 811 |
|  ↳ sessions in `~/Development/.worktrees/*` (claude-infrastructure lanes and others) | 19,383 | 20.1 | top 647665ed 2,652, a2458487 2,297, a0e6a1fb 2,286, f06b5e9b 2,175 |
|  ↳ TrueMemory lead `ad2417e7` | 6,879 | 7.1 | in-process team lead, tm-upstream-wt |
|  ↳ personal project | 5,552 | 5.7 | 756b68c8 3,199 (the shopping/agent-browser session) |
|  ↳ agent-context-sync | 1,655 | 1.7 | |
| other-501:claude.exe (teammate binaries) | 6,881 | 7.1 | |
| Dia | 4,086 | 4.2 | |
| WindowServer | 2,259 | 2.3 | |
| **other-501:bash** (detached bash with ppid 1, no session tag) | 1,510 | **1.6** | holds the move rail's batch runners, workers, censuses and lr-handoff; it also holds other detached bash (0.3-0.5 cores at 23:00-23:27Z, with no batch live) |
| fseventsd | 788 | 0.8 | |
| postland-verify (the postland bats suite) | 566 | 0.6 | bats runs started from sessions are inside their sessions |
| lead-supervisor | 558 | 0.6 | |
| kitty | 427 | 0.4 | |
| other-501:python3.12 | 370 | 0.4 | |
| lr-reconciler (the reconcile lane, not the move lane) | 364 | 0.4 | |
| rest (everything outside the top 25 buckets in each row) | 3,104 | 3.2 | |
| unseen (processes that exited between ticks into a parent nobody reads) | 12,787 | 13.2 | |

The 343 zombies come from 334 unreaped children of kitty (pid 44163) plus 9 elsewhere. They use
no CPU and do not count toward load (measured: `ps -axo stat`, 02:36Z).

## 3. The rail's cost, by component

### Measured inputs

| input | value | source |
|---|---|---|
| CPU per `--switch-census --from next4 --target next` | **19.1-27.0 CPU-s, mean 23.2 (n=7)**: 25.40, 25.36, 25.35, 27.03, 20.17, 20.16, 19.14 | measured passively. `/tmp/lri-f/rail_mon.py` read the proc_pid_rusage v2 child-CPU of each live batch runner every 3 s from 02:17:21 to 02:29:19Z. The jump when a census child was reaped equals that census's whole tree CPU (`/tmp/lri-f/mon_analyze.py`). The in-flight readings just before each reap agreed to within 0.3 CPU-s. |
| census wall time | 8.6, 8.7, 9.5, 10.4, 5.9, 5.9, 7.1 min at load1 145-208 | measured: census `ps lstart` to the reap sample |
| census wall time at load 300-500 | **≥ 60 min once** (00:42:36 to 02:00:43Z, three batches in lockstep) | measured from files: batch 69993's worker wrote its result at 01:00:44Z, but the WATCH loop did not iterate again until its census returned. Evidence: snap.ts = 02:00:44Z, router.err 02:02:52Z, close 02:02:57Z. `snap.tsv` birth is 00:42:36Z in all three batches (69993/69994/70005). Cause not determined; scheduling priority does not explain the lockstep finish. |
| how many identical censuses run at once | 4 (02:16Z: pids 48933, 48974, 98673, 73622, all `--from next4 --target next`) | measured: `ps` |
| rail scheduling priority | pri 20 for every batch, worker and census (753 other processes run at pri 31) | measured: `ps -o pri` |
| batch runner, total own + child CPU | 27-50 CPU-s per 718 s (0.04-0.09 cores per batch, almost all of it census) | measured: rail_mon |
| worker that is waiting for idle | 1.25-1.31 CPU-s / 718 s = **0.002 cores** | measured: rail_mon (5 workers) |
| worker in slot-wait | 2.53 CPU-s / 123 s = 0.02 cores | measured: rail_mon, pid 17115 |
| worker actuating (lr-handoff tree) | 0.050 / 0.061 / 0.063 cores | measured: rail_mon, pids 15973, 16575, 70197 |
| worker in the prove loop (verdict every 2 s plus its wall) | 2.96 CPU-s / 99 s = **0.03 cores** | measured: rail_mon, pid 15111 (STRANDED path) |
| one `lr_move_verdict` call | **1.0 CPU-s (0.27 user + 0.75 sys), 2.2 s wall** at load1 146 | measured: `/usr/bin/time -l bash /tmp/lri-f/verdict_run.sh 2` (2 calls, 0.53 user + 1.50 sys, 4.39 real). The 0-call baseline was 0.00 / 0.00 / 0.03 s. Sid 246a91b5 was STRANDED, so this is the early-return path. |
| `cc-lr move` caller, polling | 1.92 CPU-s / 718 s = 0.003 cores | measured: rail_mon, pid 22546. Its 23.1 CPU-s of child CPU at the first sample is the plan-time census (bin/cc-lr:1182). |
| census-driving spans (any worker `.waiting`) | 248 batch-minutes in the window | measured: events.jsonl `waiting` to the next stage, unioned per batch (`/tmp/lri-f/batches.py`) |
| actuations | 12; 7,888 s of `actuate`→`actuated` wall, clipped to the window; individual walls 5-1,910 s | measured: events.jsonl |
| prove phases | 2,927 s, clipped | measured: events.jsonl |
| plans (one census each in `cc-lr move`) | 15 batch dirs named in the window | measured: `ls ~/.reso/limit-recover/move` |
| this measurement's own cost | rail_mon 12.1 CPU-s / 721 s | measured: `/usr/bin/time -l` |

### Arithmetic (estimated = measured unit cost × measured span or count)

| component | count × unit | CPU-s in window |
|---|---|---|
| batch census loops | 18-28 censuses × 23.2. Count: the three 235745Z loops ran 2.5-5 censuses each from 00:01 to 00:42 (wall 8-16 min, scaled from the measured 8-10 min by load) plus one long one each, giving 10-18; the four 01:50Z loops ran 69 batch-min / 8.4-9.9 min, giving 8-10 | **420-650** |
| plan-time census (in the calling session's tree) | ≤ 15 × 23 | **≤ 350** |
| actuation (lr-handoff) | 7,888 s × 0.05-0.063 cores | **390-500** |
| prove loops (verdict) | 2,927 s × 0.03 cores | 90 |
| slot-wait | 1,170 s × 0.02 cores | 25 |
| waiting workers | 17,940 worker-s × 0.0018 cores | 32 |
| admission (router, capacity probe, preseed, spawn) | about 13 batches × 1.6-4.8 CPU-s | 20-60 |
| `cc-lr move` callers polling | ≤ 15 × up to 1,500 s × 0.003 cores | ≤ 60 |
| **total** | | **about 1,390-1,770 CPU-s** |

- **Rail vs capacity.** Over 9,742 s that is **8.6-10.9 CPU-s/min against 600 CPU-s/min of
  capacity, or 1.4-1.8%**. It is also 1.4-1.8% of the 96,640 CPU-s actually used.
- **Upper-bound cross-check.** The other-501:bash bucket (1,510 CPU-s, which includes non-rail
  bash) plus the plan censuses (≤ 350) gives ≤ 1,860 CPU-s, which is consistent with the total.
- **By period.** The other-501:bash bucket reads 2.9 CPU-s/min (0.48%) for 23:30-00:00, 8.6
  (1.44%) for 00:00-01:00, 5.5 (0.92%) for 01:00-01:50 and **29.2 (4.98%)** for 01:50-02:10. A
  direct rail measurement at 02:17-02:29Z, with a similar population (5 batch runners, about 14
  workers), gave **24.3 CPU-s/min = 0.405 cores = 4.0%** (batch runners 172 CPU-s, workers 116,
  caller 2.6; measured, rail_mon).
- **Load contribution.** At 02:36Z, rail processes were 4-9 of the 106-190 runnable processes
  (about 5%) while load1 was 208 (measured: 6 `ps` snapshots 3 s apart, `/tmp/lri-f/runq.sh`).
  The rail runs at pri 20, so it queues behind interactive work. Its share of the load average
  is therefore near its CPU share and does not exceed it by much.

### Why the brief's per-unit guesses were off

- **A census costs about 23 CPU-s, not about 7.** The header comment's figure predates the
  current fleet: 46 registry files, about 110 session files, and 11 next4 rows each judged
  through a handoff-fire.sh probe and a kitty composer RPC. Estimated, from reading
  lr-upgrade.sh:636-1112: about 300 jq processes plus 11 transcript globs plus up to about 6
  handoff-fire parses per census.
- **The census does not run every 20 s.** The 20 s is the gap between the end of one census and
  the start of the next. A census runs 6-10 min at load about 150-200 and over 60 min at load
  300-500, so each loop is a single census running back to back. That limits itself to about
  23 CPU-s / (W + 22 s), which comes to 1.4-2.8 CPU-s/min per batch.
- **The prove loop does not reach a verdict every 2 s.** One verdict is 1.0 CPU-s, but a pri-20
  worker under this load got 0.03 cores, which is about one verdict per 30 s.

## 4. Cheapest reductions, with estimated savings

Even all of these together save at most about 1% of the box over this window. They are worth
doing for the rail's own latency and for the peak, but they would not have moved a load of 300-500.

1. **One shared census per (from, to) across batches.**
   - *What happens now:* all four concurrent loops ran the same `--from next4 --target next`
     command.
   - *Change:* a batch takes a mkdir lock on `move/census-<from>-<to>`. It copies the shared
     snapshot when that snapshot is newer than LR_MOVE_SNAP_S, and otherwise runs the census and
     publishes it. `cc-lr move`'s plan step reuses a fresh shared snapshot the same way.
   - *Saving:* (N-1)/N of census-loop CPU, which is about 75% at N=4. That is about 8 CPU-s/min
     (about 1.4% of the box) at the 01:50-02:30Z peak, and 250-450 CPU-s plus up to about 350
     plan-time CPU-s over this window (estimated).
   - *Cost:* lowest of the four, a lock and a file copy in lr-move-batch.sh:247-252.
2. **Judge only the rows somebody is waiting on.**
   - *What happens now:* the census runs the composer RPC and the subagent probe for all 11
     source rows, but a batch needs 1-2 of them. `--sid` already exists for one row.
   - *Change:* a multi-sid selector over the union of waiting sids. It combines with item 1.
   - *Saving:* estimated 50-80% of each census, on the assumption that the per-row probes
     dominate (not profiled).
3. **Longer snap interval under load: a weak lever.**
   - *Why:* census wall time (6-10 min, and over 60 min once) already dwarfs the 20 s gap.
     Raising the gap to 120 s saves only gap/(W+gap), about 20% at W = 8 min.
   - *Better alternatives:* bound the census's wall time, or answer "is it idle" for the waiting
     sids with the at-rest and background-job reads alone. The full census is the only reason a
     wait costs anything.
4. **Cheaper `lr_move_verdict`.**
   - *What it costs now:* 1.0 CPU-s per call, mostly system time (measured).
   - *Code causes:*
     - `lr_session_location` globs `projects/*/<sid>.jsonl` across 4 physical stores of about
       18,200 project dirs each, which is about 73k lookups per call (counted with `ls | wc -l`).
     - `lr_resume_procs` reads the full `ps -axo` table of about 1,700 processes.
     - `lr_registry_live_rows` runs jq over all 46 registry files twice per call, once through
       holders and once through rows.
   - *Change:* resolve the transcript from the plan's cwd slug with one stat, take one ps
     snapshot per call, and read the registry once.
   - *Saving:* estimated 1.0 → about 0.2 CPU-s per call. In this window that saves only about
     70 of 90 CPU-s, because the prove loop is already throttled.
5. **Not in the brief, and larger than the verdict: lr-handoff actuation time.**
   - *Measured:* 12 actuations ran 7,888 s at about 0.055 cores each, about 430 CPU-s in total
     (estimated). Two of them ran 1,558 s and 1,910 s.
   - *Next step:* finding out what those long actuations poll is the next-largest lever after
     item 1.

## Deviations and caveats

- **I did not run the census, which deviates from brief step 2b.** `--switch-census` writes no
  file, but it is not read-only in this brief's sense:
  - per row it makes kitty remote-control calls (`kitty @ get-text` via `cc_tui_composer`, and
    `kitty @ ls` via `lru_kls`, lr-upgrade.sh:605-616 and 887-897), which is the kitten class
    the brief forbids;
  - it launches `handoff-fire.sh --probe-live-subagents`, a 19,771-line script that
    lr-upgrade.sh itself describes as having load-time side effects.

  Instead I measured 7 censuses that were already running, passively, with no writes. That
  method is more exact than `/usr/bin/time` (it reads the whole reaped tree under real load),
  and it ran nothing extra.
- **The verdict was measured as the brief allowed, but only on its early-return path.** It took
  2 runs: a 0-call baseline and 2 calls. The sid was STRANDED, so the P1-P7 path, which adds a
  jq pass over the registry and 3 more `ps`, would cost somewhat more (not measured).
- **The attrib buckets can miss rail CPU.** When a worker exits, its CPU since the last tick
  goes into launchd and reads as unseen, so other-501:bash slightly undercounts the rail on that
  side. On the other side, it also holds non-rail detached bash, so it is a loose upper bound.
- **"Ghost" means teammate tool work for every team, not only TrueMemory.** The w2-* teammates
  are in it too. The TrueMemory share inside ghost comes from the 01:13Z rusage note, not from
  this data.
- **A latency concern for this branch's subject, outside the CPU question.** A worker moves only
  after two consecutive census snapshots say `move`, so at 6-10 min per census an idle session
  waits at least 12-20 min. At the ≥ 60 min census seen at 00:42-02:00Z, the batch close was
  delayed by an hour: worker result 01:00:44Z, close 02:02:57Z.
- **Helper scripts and raw samples** are in `/tmp/lri-f/`: attrib_window.py, timeline.py,
  bash_series.py, batches.py, sess_proj.py, ghost_now.py, rail_mon.py + rail_mon.jsonl,
  mon_analyze.py, verdict_run.sh, runq.sh/.py. Nothing was written under ~/.reso or ~/.claude.
