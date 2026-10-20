# Gap 4: does the band fix hold at 30-40 per core?

Read-only research, 2026-10-20 05:25-05:55Z. I used natural experiments only. I ran no `launchctl`
command, edited no plist, typed into no pane and signalled no process. The only processes I started
were short read-only probes: `census.py`, `thr.py`, one `lr_recon.observe.observe()` call,
`lr-upgrade.sh --switch-census`, `log show` and `pmset -g log`. My scripts and their raw output are in
`/tmp/gap4/`:

- analysis: `a.py`, `b.py`, `c.py`, `d.py`, `k.py`, `exp.py`
- census sampling: `census-loop.sh` → `census-now.out`, and `hi-census.sh` → `hi-census.out`
- CPU runs: `cpu.sh` → `cpu.out`
- lock and kitty logs: `lock2.log`, `pmset.log`, `kittybp.log`

**Conventions.**
- **Load bins.** Load per core is `loadavg[0] / 10`. Each event is matched to the nearest
  `~/.reso/load.jsonl*` sample within ±90 s.
- **Load data.** There are 131,583 samples from 10-02T05:00Z to 10-20T05:31Z. The one gap over 1 h is
  10-18T21:33Z, lasting 3.1 h (the reboot). Measured with `python3 -I /tmp/gap4/a.py`.
- **Quantiles.** p90 is linear-interpolated.
- **Small samples.** A bin with **n < 5** is marked *too small to conclude*.
- **Caller band.** The handoff-fire `phases` trail is joined to a caller band as follows:
  - `attempt` = `recon:…` → reconciler, PRI 20.
  - `attempt` = `move-…` → move lane, PRI 20. Its only starter is the reset poller, which has no
    ProcessType (`scripts/limit-recover/lr-reset-poller.sh:248-252`).
  - `attempt` null and `firing_sid` set → fired from inside a session, PRI 31. A session's Bash-tool
    child reads PRI 31: `ps -o pri= -p $$` => `31` in this session.
- **Live bands now.**
  - `thr.py 51148` (lr_recon) => `base=20 … max=20`.
  - `thr.py 60282` (classifier-warm, ProcessType Interactive) => `base=31 max=63`.
  - kitty pid 853 main thread => `base=46 max=63`.

## Answer first

1. **Short PRI-31 control-plane steps did not collapse at 30-68 per core.** I compared identical code
   run by both bands (the watcher spawn, heartbeat and kitty pane-proof span, `detach→armed`):
   - PRI 31: median **1 s**, p90 **2.6 s** at ≥ 40/core (n=15); median 3 s, p90 6 s at 30-40/core (n=7).
   - PRI 20: median 4-11 s and p90 8-13 s, already at 10-40/core.

   Across 22 session-fired recycles that started at ≥ 30/core, there were **0** kitty failures:
   17 engaged, 3 held by the load *policy* gate (the pre-`d4260ae3c` bound) and 2 held-busy. Over the same load range, 8 PRI-20
   recycles had 3 kitty `unreachable`, 4 `HELD:load` and 1 engaged. Measured with `/tmp/gap4/b.py` and `c.py`.
2. **CPU-heavy PRI-31 work does stretch at ≥ 30/core.** A fresh Claude Code boot plus first turn
   (`self-retire-peer engage_latency_s`, PRI 31) had these medians and p90s:

   | load bin | median | p90 | n |
   |---|---|---|---|
   | < 10/core | 29 s | 44 s | |
   | 30-40/core | 46 s | 212 s | 23 |
   | ≥ 40/core | 168 s | 250 s | 9 |

   The distribution is bimodal: at ≥ 30/core, 18 of 32 launches still engaged in 25-73 s.
   The current census at 21-25/core shows **6-75 base-31 runnable threads (median 10)** against
   8 P-cores. Measured with `census-loop.sh` (12 samples). So the 31 band is oversubscribed in bursts.
   The history cannot show by-band run queues: `load.jsonl`'s `runnable` field is a plain `ps` count of
   R-state processes.
3. **Kitty failures are mostly not lock-caused in the window I can see (10-13 to 10-20).**
   - The screen was locked **45%** of the 166.8 h.
   - About half of the kitty-touching LR attempts ran while it was locked (59 of 120 recycle attempts).
   - Only **5 of 26** de-duplicated kitty-failure episodes fell inside a lock.
   - Recycles while locked: 32 engaged / 3 held-unreachable. Unlocked: 39 / 5.
   - Kitty's own late-answer marker (`write() to peer socket failed`) appears **once** from 10-12 to now.
     On 10-01 it appeared about 180 times.

   Three in-lock episodes happened at 4.8-19.7/core with kitty accepting a connection but never
   answering (10-17T07:53Z, 20:05Z, 21:01Z). That is the kitty-side signature, which no band fix
   cures. Estimate: **about 12% (3 of 26), at most 19% (5 of 26)** of failure episodes (by episode
   count over the overlay).
4. **The census clamp question is settled by CPU-seconds.** These were measured at PRI 31 with
   `bash /tmp/gap4/cpu.sh`:

   | census | CPU-s | wall at PRI 31 | under `taskpolicy -c utility` |
   |---|---|---|---|
   | reconciler observe census | 1.49-1.55 | 2.1-2.8 s (load 246) | not run |
   | move-batch `--switch-census --sid` (the default shape) | 2.7-2.9 | 6.3-6.5 s (load 176) | 3.25 CPU-s, 20.7 s wall (load 170) |
   | full `--switch-census` (31 rows) | 37.9-39.4 | 85-90 s (load 197-246) | not run |

   The resolution:
   - Unclamp the `--sid` census, as 04 L5 says. It is on the waiting workers' critical path and costs
     3 CPU-s.
   - Keep a utility clamp only on the full-shape census. 07 L1's concern applies to that one.
   - Never clamp the observe census: it carries `kitten @ ls`.
5. **Verdict.**
   - *Interactive alone is enough for the control plane's own short steps at 30-40/core.* The data even
     reaches 68/core (n=15 at ≥ 40/core).
   - *Interactive alone is not enough for "every session, reliably".* Three things limit it:
     - (a) The CPU-heavy PRI-31 tail stretches 3-6x at ≥ 30/core, so every bound sized at low load must
       be re-sized to the ≥ 40/core p90.
     - (b) The `HELD:load` policy gate held PRI-31 recycles at 36-51/core on 10-18, under the bound in
       force then. Since `d4260ae3c` (10-19T23:56Z), `hf_recycle_load_bound` holds *typed* recycles
       above 24/core and exempts staged ones (`handoff-fire.sh:4115-4131`). It still binds at the
       15-40/core operating point. The move worker keeps its own copy (`lr-move-worker.sh:300-349`).
     - (c) The locked-kitty class needs its own fix.
   - **Self-promotion to 37 (04 L2) is not a prerequisite.** No PRI-31 short step degraded enough to
     need it. It is cheap insurance for the actor's own loop, and its children stay at 31.
   - **NSAppSleepDisabled is orthogonal to load, not a prerequisite for the band fix.** It is a
     prerequisite for 24/7 coverage of the about 12-19% of failure episodes that are lock or kitty-side.
     Its efficacy is still unproven, so a kitty-free fallback path is needed alongside it.

## 1. Joining PRI-31 work to load per core

How much of the history is at the operating point (measured with `a.py`, daily bin shares of
`load.jsonl`):
- Before 10-18, 30-40/core and ≥ 40/core together were 0-19% of samples on any day.
- On 10-18 they were 11% + 14%. On 10-19 they were 19% + 10%.

So the high-load evidence comes mostly from 10-10/11 and 10-17 to 10-20.

### 1(a) In-pane lr-fire-resume stages (PRI 31, the pane is a child of kitty)

Source: `~/.reso/limit-recover/*/bundle-*/events.jsonl` (424 files). The stage notes are:
- `relaunch-typed` (`lr-fire-resume.sh:1485`);
- `composer-painted` (`:1615`; the prompt case, which includes boot, ready, typing and paint);
- `READY` (`:1847`; the no-prompt case).

| span | <10/core | 10-20 | 20-30 | 30-40 | ≥40 |
|---|---|---|---|---|---|
| relaunch-typed → READY/composer-painted | n=68, med 5.0 s, p90 7.3 s | n=14, 7.0 / 8.7 s | n=2 *too small* (6.5 / 7.7) | **n=0** | **n=0** |
| gate note → relaunch-typed (bash pre-launch in the pane) | n=78, 1.0 / 2.0 s | n=22, 1.0 / 2.9 s | n=2 *too small* | n=1 (3 s) *too small* | n=1 (7 s) *too small* |
| composer-painted → submitted | n=36, 4.0 / 8.0 s | n=8, 7.0 / 9.2 s | n=1 *too small* | n=0 | n=0 |

Outcomes after `relaunch-typed`:
- 30-40/core: 1 `READY-NOT-SEEN`.
- ≥ 40/core: 1 `READY-NOT-SEEN` (10-18T05:28:34Z, load1 607).

**This source cannot answer the question at ≥ 30/core.** The in-pane stage notes have essentially no
samples there.

### 1(b) Recycles: session-fired (PRI 31) against reconciler and move lane (PRI 20)

Source: `~/.claude/logs/handoffs.jsonl` rows with `phases`/`elapsed_s`. They are grouped into one
recycle by `(target_pane, ts − elapsed_s ± 3 s)`; T0 is set at `scripts/handoff-fire.sh:412`. That
gives 115 recycles:
- 55 session-fired at PRI 31;
- 37 move lane at PRI 20;
- 16 reconciler at PRI 20;
- 7 unknown.

**Confound.** PRI-20 recycles use the *remote* form. Before `gates` it runs the source bind, pin and
transplant-evidence reads (`handoff-fire.sh:16242-16283`). The self form does almost nothing there.
The move worker's kitty probe also retries on a 5/10/20/40 s backoff (`handoff-fire.sh:1554-1562`). So
`start→gates` and `kitty-probe` are **not** like-for-like.

The like-for-like span is **`detach→armed`** (`handoff-fire.sh:19925-19999`). It is the same code for
both forms:
1. spawn the setsid watcher (which re-sources the 20.8k-line script);
2. `await_armed` heartbeat;
3. the watcher's kitty pane proof.

`detach→armed`, measured with `python3 -I /tmp/gap4/c.py`:

| band | <10/core | 10-20 | 20-30 | 30-40 | ≥40 |
|---|---|---|---|---|---|
| session-fired, PRI 31 | n=6, med 1 / p90 1 s | n=13, 1 / 1 s | n=14, 1 / 1.7 s | n=7, **3 / 6 s** | n=15, **1 / 2.6 s** |
| move lane, PRI 20 | n=4 *too small* (4.5 / 8.1) | n=14, 7 / 8.7 s | n=7, 4 / 9.8 s | n=4 *too small* (11 / 12.4) | n=0 |
| reconciler, PRI 20 | n=2 *too small* | n=10, 3 / 12.6 s | n=2 *too small* | n=1 *too small* | n=0 |

The other spans and their caveats:

| span | session-fired, PRI 31 | PRI 20 | caveat |
|---|---|---|---|
| `kitty-probe` | median 0-1 s in every bin; p90 1.4 s at 30-40 (n=7) and 1.0 s at ≥ 40 (n=15) | move lane 2 s median, 9 s at ≥ 40 (n=1) | includes the move lane's retries, so not like-for-like |
| `start→gates` | median 1 s at ≥ 40/core (n=15) | move lane 96 s (n=5) at 30-40 and 84 s (n=1) at ≥ 40 | confounded by the remote pre-pass |
| `self-id→intent` | p90 85-88 s at ≥ 30/core, against 21-40 s below | not compared | includes bg-work and composer waits, so not pure CPU |
| `intent→armed` | p90 75.6 s (30-40) and 80 s (≥ 40), against 22 s at < 10/core | not compared | includes bg-work and composer waits, so not pure CPU |

**Outcomes of recycles that started at ≥ 30/core** (measured with `python3 -I /tmp/gap4/b.py`, which lists
every group with phases and classes):

| band | groups | engaged | kitty `held-unreachable` | policy `HELD:load` | `held-busy` |
|---|---|---|---|---|---|
| session-fired, PRI 31 | 22 (load1 303-679) | **17** | **0** | 3 (at load1 362, 489 and 506) | 2 |
| move lane + reconciler, PRI 20 | 8 (load1 300-448) | 1 | **3** | 4 | 0 |

- The 17 PRI-31 engagements include 3 that ran while the screen was **locked**: 10-18T06:57Z,
  10-19T02:15Z and 02:18Z, at load1 469-592.
- All 7 `HELD:load` rows here predate `d4260ae3c` (10-19T23:56Z), which moved the recycle hold to
  24/core with staged recycles exempt. So they count the old bound, not the current one.
- Start→engaged for PRI 31 at ≥ 40/core: median 172 s, p90 431 s (n=13). Below 10/core it is
  116 / 135 s. This span includes `/exit`, claude boot in the pane and the first turn.

### 1(c) Admission-token age at redeem

Sources: the bundle `gate-admitted` notes (`… token, Ns old`) and `idl.jsonl` rows with
`caller=lr-fire-resume` "redeemed a probe admission Ns old" (only 6 such rows exist).

| minter | bins and values |
|---|---|
| reconciler | 10-20/core: n=5, median 381 s, p90 804 s. 30-40/core: n=1 (458 s) |
| older bundles, minter unknown | < 10/core: n=42, median 55.5 s, p90 116 s. 10-20/core: n=5, 173 / 355 s |

At ≥ 30/core, **n=1, too small to conclude.** The token age spans the minter's transplant and recycle
(PRI 20) plus the relaunch, so it is not a band-pure measure anyway.

### 1(d) classifier-warm (ProcessType Interactive)

The live logs (`~/.claude/logs/research-classifier-warm.{out,err}.log`) record no latency. The only
latency data is commit `f1a62145d`'s run-3 A/B, in
`docs/research/router-classifier-e1h-2026-10-06/e1k-ab-run3.{json,trace.jsonl}`. Its 300 router calls
ran with the workers at PRI 31-37 (commit message).

| load bin | n | median wall | p90 | "careful call silent at 8.5 s" rows |
|---|---|---|---|---|
| 10-20/core | 80 | 5.4 s | 8.6 s | 17 |
| 20-30/core | 23 | 5.0 s | 8.6 s | 4 |
| 30-40/core | 75 | 5.6 s | 8.6 s | 15 |
| ≥ 40/core | 122 | 4.8 s | 8.6 s | 26 |

The silent-call rate is 17-21% in every bin. The curve is flat to 40+/core. But the calls are
network-bound and clipped at the router's 9 s deadline (p90 = 8.6 s everywhere), so they show the
absence of a collapse, not CPU headroom.

### 1(e) Extra source: a fresh session's boot plus first turn (PRI 31)

Source: `handoffs.jsonl` `self-retire-peer` rows, `engage_latency_s`. There are 107 rows from
10-17 to 10-20, all engaged. Measured with `python3 -I /tmp/gap4/d.py`.

| bin | n | median | p90 | max |
|---|---|---|---|---|
| <10/core | 27 | 29 s | 44 s | 204 s |
| 10-20 | 21 | 38 s | 46 s | 77 s |
| 20-30 | 27 | 37 s | 79 s | 208 s |
| 30-40 | 23 | **46 s** | **212 s** | 268 s |
| ≥40 | 9 | **168 s** | **250 s** | 260 s |

This is the heaviest PRI-31 work in the data: node start, hooks and MCP servers, then a model turn.
It is also the clearest load signal in the PRI-31 band. The ≥ 30/core rows are bimodal: 18 of 32 took
25-73 s and 14 took 91-268 s. The first turn's API time is included, so part of the tail may not be
CPU (hypothesis).

## 2. Does the PRI-31 band saturate at 30 per core or more?

**Measured now** (`bash /tmp/gap4/census-loop.sh 12 10` → `/tmp/gap4/census-now.out`; 12 samples,
05:33-05:35Z, load1 208-247, i.e. 21-25/core):

| measure | value |
|---|---|
| base-31 runnable threads | 11, 30, 9, 11, 15, 13, 7, 7, 6, **75**, 7, 9 (median 10) |
| samples with ≥ 8 base-31 runnable (≥ the P-core count) | 8 of 12 |
| base-4 runnable threads | 110-184 |
| base-20 runnable threads | 7-23 |
| base ≥ 37 runnable threads | 0-1 |

- The readable processes are about 1,170-1,250 of about 1,610-1,690, so these counts are lower bounds.
- The burst sample (75 base-31 runnable) showed only 44 at current priority 31. Timeshare decay hides
  the rest from `ps`, as the 04 skeptic found.
- This matches the 04 skeptic's 12-48 at 18-22/core.
- `/tmp/gap4/hi-census.sh` was armed to sample at load1 ≥ 280. Load fell to 75-128 during the run, so
  **no base-priority census exists at ≥ 28/core**. That remains open.

**What the historical data can show:**
- Latency by band and load bin, for the spans in §1. From those, an *indirect* answer:
  - Steps of about 1 CPU-s or less at PRI 31 (`detach→armed`, `kitty-probe`, `start→gates`) show no
    median stretch up to 68/core.
  - Multi-CPU-s PRI-31 work (§1e) stretches 1.2x at 30-40/core and 4.4-5.8x at ≥ 40/core (median, vs
    < 20/core).
  - That pattern is consistent with a 31 band that is busy in bursts and oversubscribed at ≥ 40/core.
    Short wakeups get through, and long CPU runs queue behind the 31-band fleet. This is an inference,
    not a direct reading.

**What it cannot show:**
- Run-queue depth by band. `~/.reso/load.jsonl`'s `runnable` field is `ps -A -o state=` R-count
  (`~/Development/reso-management-app/scripts/load-sampler.sh:60-62`). It has no priority, uses decayed
  state, and counts processes, not threads.
- P-core versus E-core placement.
- Any sample at ≥ 30/core of the reconciler running at 31, because that configuration has never run.

## 3. Kitty failures against screen lock, display sleep and HID idle

**Lock intervals.**
- Lock and unlock times come from `log show … process == "loginwindow"`, using `startScreenLock:] | entered`
  and `lowerShieldWindow` (`/tmp/gap4/lock2.log`). They are closed with `pmset -g log` "Display is
  turned on/off" where the unified log lost a row (`/tmp/gap4/pmset.log`).
- Coverage starts **10-13T06:56Z**; earlier rows have aged out.
- Locks start on display dim with delay 0: `setScreenLockDefaultDelay to: 0`,
  `startScreenLock: entered kLWLockFromDisplayDim`. So *display off* and *locked* coincide here.
- Each lock ends at user activity with `lowerShieldWindow`.
- **The incident window had a lock: 10-20T03:56:04Z → 04:08:40Z.**

**Failure rows.**
- Sources:
  - bundle `HELD` notes (`HELD:unreachable…`, `HELD:pane:resolver-unavailable`);
  - in-pane `READY-NOT-SEEN` "screen reads UNKNOWN" (PRI 31, read through `it2 session read`,
    `lr-fire-resume.sh:1239-1250`);
  - `handoffs.jsonl` `recycle-held-unreachable`;
  - `move/*/*events.jsonl`;
  - `recon/actlogs/*` (file mtime only).
- Rows from the same band within 120 s are counted as one episode.
- 43 episodes since 10-01; **26 inside lock coverage**.
- Measured with `python3 -I /tmp/gap4/k.py` (full table in its output).

| lock state (10-13 onward) | episodes | of which PRI 20 | PRI 31 in-pane | unknown caller |
|---|---|---|---|---|
| locked | 5 | 2 (10-17T07:53Z move, load1 68; 10-18T10:43Z recon actlog mtime, load1 269) | 1 (10-20T04:04:07Z, load1 336) | 2 (10-17T20:05Z load1 197, 21:01Z load1 48) |
| unlocked | 21 | 15 | 3 | 2 (10-20T04:23-04:25Z, poller lr-fleet per `00-lead-observations.md` item 4) |

**Exposure** (measured with `python3 -I /tmp/gap4/exp.py`):
- The screen was locked 74.8 h of 166.8 h (45%).
- `lr-handoff` focus probes: 60 locked / 54 unlocked.
- Recycle attempts: 59 locked / 61 unlocked.
- Recycle outcomes: locked 32 engaged / 3 held-unreachable; unlocked 39 / 5. Seven of the locked
  engagements ran at ≥ 30/core.
- The 9 locked `recycle-dead` rows are relaunch gate or rc 9 refusals: the keystrokes were typed, so
  kitty answered.

**Kitty-side marker.**
- `log show --start 2026-10-12 --predicate 'process == "kitty" AND eventMessage CONTAINS "peer socket failed"'`
  => **one line** (10-20T03:12:14Z).
- A starved kitty that answers late leaves one such line per abandoned client. On 10-01 there were
  about 180 (`docs/research/session-durability-2026-10/C3-socket-robustness.md:107`). Since 10-12 the
  client failures were overwhelmingly requests that kitty never late-answered.
- **HID idle:** failure rows carry `hid_idle_s=unread`, the focus probe itself failing, so HID idle at
  the failure is not recoverable. `pmset` `UserIsActive` assertions exist (2,587 rows), but I did not
  join them; the lock intervals already bound "user away".

**Estimate of what no band fix cures.**
- These episodes show the signature: low load, inside a lock, kitty accepted the connection but never
  answered (`'kitty @ ls' did not answer within 10s (0 queued)`):
  - 10-17T07:53Z, 3 min into a lock, load1 68 (6.8/core);
  - 10-17T20:05Z, load1 197 (19.7/core);
  - 10-17T21:01-21:02Z, load1 48 (4.8/core).
- At 4.8-6.8/core a PRI-20 caller still gets answers in 1-5 s (`07-kitty-control-plane.md:23`), so
  caller starvation does not explain them. **3 of 26 ≈ 12%** (estimated, by episode count).
- Counting every in-lock episode gives an upper bound of **5 of 26 ≈ 19%**.
- The 10-01 PRI-4 case is the measured precedent (`docs/research/recycle-unreachable-2026-10-01.md:12`),
  but it predates the lock coverage.
- **Locking alone does not predict kitty deafness here.** About half of the attempts ran locked, and
  most of them, including PRI-31 recycles at 47-59/core, got answers.
- Kitty's main thread now reads base 46 (unlocked, not frontmost: frontmost is `Dia` per `osascript`).
- `defaults read net.kovidgoyal.kitty NSAppSleepDisabled` => the key does not exist.
- What triggers a PRI-4 kitty (App Nap versus lock) is **unverified**.

The in-pane PRI-31 `screen UNKNOWN` signal is weak. It also occurred unlocked at 10.7 and 12.5/core
(10-20T04:14:48Z, 05:21:07Z), so UNKNOWN has non-kitty causes too (hypothesis: the composer-box parse).

## 4. CPU-seconds of the two census shapes at PRI 31 (the clamp contradiction)

Measured with `bash /tmp/gap4/cpu.sh` (runner band `31`), using `/usr/bin/time -p` and `getrusage`:

| census | load1 | wall | CPU-s (user+sys) |
|---|---|---|---|
| reconciler `observe.observe()` (2× ps, `kitten @ ls` × 1 socket, sessions and transcripts; 39 claude procs, 30 panes, 41 sessions) | 246 | 2.07-2.77 s | **1.49-1.55** (own 1.06-1.10 + children 0.42-0.46) |
| move-batch `lr-upgrade.sh --switch-census --target next --sid <1 sid>` (the default `LR_MOVE_SNAP_SIDS` shape, `lr-move-batch.sh:321-339`) | 176 | 6.25-6.52 s | **2.66-2.89** |
| the same, under `taskpolicy -c utility` (the clamp) | 170 | **20.69 s** | 3.25 |
| full `--switch-census --target next` (31 rows; the shape used with `LR_MOVE_SNAP_SIDS=off`, and the plan-time census, `bin/cc-lr:1019-1021`) | 197-246 | 84.6-89.8 s | **37.9-39.4** |

**How the batch uses its census.**
- It runs a census only while some `<sid>.waiting` exists, every `LR_MOVE_SNAP_S` = 20 s
  (`lr-move-batch.sh:315`).
- A worker leaves the wait only after **two consecutive** snapshots say `move`
  (`lr-move-worker.sh:142-175`).
- So the census wall time sits on the critical path:
  - at PRI 31 a snapshot costs 6.5 s, so the 20 s cadence dominates;
  - clamped, it already costs 20.7 s at 17/core, so the snapshot itself becomes the cadence.

  At 30-40/core the utility tax measured elsewhere is 17-44x (04 R0.1, at 21-22/core). The clamped
  census would then take minutes per snapshot (estimated: 3 CPU-s × 17-44 ≈ 50-130 s).

**What it costs to leave the census at 31.** Estimated by linear interpolation between the 1-row and
31-row runs:
- per-row cost ≈ (38.6 − 2.8) / 30 ≈ 1.2 CPU-s, plus a base of about 1.6 CPU-s;
- with k waiting rows, about (1.6 + 1.2k) CPU-s every 20 s;
- that is 0.14 of a core at k=1 and about 0.6 of a core at k=9, out of 10.

**Resolution of 07 L1 against 04 L5.**
- **Drop the clamp for the `--sid` shape.** It is critical-path and cheap, and the clamp also puts its
  kitty reads (`lru_kls` → `cc_tui_rpc ls`, `lr-upgrade.sh:918-927`) back under the utility band that
  07 F1 shows starving kitty calls.
- **Keep a clamp, or a refusal, for the full shape.** At about 38 CPU-s it is about 4 core-seconds per
  row-free census and is not on any worker's critical path. 07 L1's "heavy census" is this one.
- **Never clamp the reconciler's observe census.** It costs 1.5 CPU-s and its `kitten @ ls` is
  critical-path.
- For scale, lr_recon itself used 1:52 CPU in 72:53 of wall time (2.6% of a core) at PRI 20:
  `ps -o time,etime -p 51148`.

## 5. Conclusion: is `ProcessType Interactive` alone enough at 30-40 per core?

**For the control plane's own work: yes, by the data.**
- The like-for-like A/B (`detach→armed`) has PRI 31 at a 1-3 s median and ≤ 6 s p90 at 30-68/core.
  PRI 20 is at 4-11 s median before load even reaches 30.
- PRI-31 callers had 0 kitty failures across 22 recycles at ≥ 30/core. PRI-20 callers had 3 of 8.
- n is small: 7 recycles at 30-40/core and 15 at ≥ 40/core. But both ≥ 30/core bins point the same way,
  and so do the 10-30/core bins with n=13-14.

**For "every session, reliably": no. Three more things are prerequisites, and one is optional:**
1. **Re-size bounds to the PRI-31 tail at ≥ 40/core.**
   - Fresh boot plus first turn: p90 212-250 s.
   - Recycle `intent→armed`: p90 76-80 s.
   - In-pane `relaunch→ready` is unmeasured at ≥ 30/core.

   Any 120 s placer or 30 s probe bound sized at low load will fire at the operating point, even at 31.
2. **Make every recovery recycle a staged one, or drop the typed-recycle load hold.** On 10-18 the
   hold took 3 of 22 PRI-31 recycles at 36-51/core and 4 of 8 PRI-20 recycles. It now sits at
   24/core, with staged recycles exempt (`handoff-fire.sh:4115-4131`, since `d4260ae3c`). At a
   permanent 15-40/core it still holds every *typed* relaunch above 24. No band change touches it. The
   move worker's copy is at `lr-move-worker.sh:300-349`.
3. **Treat the locked or kitty-side class separately** (about 12-19% of failure episodes, estimated).
   - `NSAppSleepDisabled` is the operator lever. Its effect is still unproven: whether App Nap or lock
     drives kitty to PRI 4 is unverified.
   - It is not a prerequisite *for the band fix*, which helps regardless.
   - It is a prerequisite for 24/7 coverage, because the screen is locked 45% of the time.
   - Because the lever is unproven, recovery also needs a path with fewer kitty reads, such as the
     SIGTERM plus staged-successor recycle (`recycle-exit-signal` / `successor-claimed` rows).
     3 PRI-31 recycles used staging while locked. But they still passed the kitty probe and pane
     proof, so they do not show that the path works with kitty deaf (hypothesis, untested).
4. **Self-promotion to 37 (04 L2) is optional.**
   - Nothing at 31 degraded on short steps up to 68/core.
   - 37 lifts only the actor's own thread; its bash, `ps` and `kitten` children stay at 31 (04 R0.6).
   - Worth doing for the reconciler's loop as cheap insurance.
   - Not a gate for shipping L1.

## Open questions

- **No base-priority census exists at ≥ 30/core.** Arm `/tmp/gap4/hi-census.sh 240 300` on a high-load
  evening; it is read-only.
- **No sample exists of the reconciler or placer at PRI 31.** All 30-40/core reconciler evidence is
  PRI 20. The first Interactive run should log `pri` and per-step wall with load1 on every event, as
  the move-kick already does (`lr-reset-poller.sh:259`).
- **What makes kitty go to PRI 4?** The candidates are lock, occlusion and App Nap. A read-only sampler
  of `thr.py 853` plus the frontmost app every 60 s across the next lock would answer it.
- **In-pane `relaunch-typed→ready` at ≥ 30/core: n=0.** That is the one PRI-31 stage on every recovery
  path that has no high-load measurement.
- **Is the fresh-boot tail CPU or API?** Splitting `engage_latency_s` into process-ready versus
  first-token would tell.
