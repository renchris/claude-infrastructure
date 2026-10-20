# 04 — Darwin priority: making recovery immune to sustained load (axis 04-darwin-priority)

Date: 2026-10-19 local (incident 2026-10-20 02:31Z). Host: Apple M1 Max, 10 cores = 8 P + 2 E
(`sysctl -n hw.ncpu hw.perflevel0.logicalcpu hw.perflevel1.logicalcpu` => `10 8 2`), macOS 15.7.9
(`sw_vers -productVersion`), scheduler `edge` (`sysctl kern.sched` => `kern.sched: edge`).
Everything below was read-only on the system. The only processes I created were my own short-lived
probe processes under `/tmp/qos-probe-04/` (bench.py, pri.py, spawn.py, role.py, execq.py, rolexec.py).
Each one changed only its own priority, then exited (`ps ... | grep qos-probe-04` => empty afterwards).

## 0. Bottom line

1. **What blocked recovery was its priority band, not the load.** Every process the reconciler runs
   is at **PRI 20**. The fleet it competes with is at **PRI 31**. At load 186, the same `cc-lr status`
   took **0.95-1.98 s at PRI 31 and 36.8-88.0 s under a utility clamp (PRI 20)**. That is 37-44x slower
   for the same ~0.3 s of CPU (measured, §3.3). The admission probe's 30 s bound and the placer's
   120 s bound sit inside that tax.
2. **Load average is a bad measure of what a recovery actor competes with.** XNU's load average
   counts *every runnable thread of every QoS bucket* (§2). Measured live at load 124-129, **55-74% of
   runnable threads are at PRI 4**: background QoS, confined to the 2 E-cores, and unable to compete
   for P-cores. Only 4-10 runnable threads were at PRI 31 (§3.1). Starving background work *raises*
   the load average and never competes with a P-core actor.
3. **An unprivileged process can lift itself above the whole Claude fleet. No root and no hardware are
   needed.** Every `claude` session is a child of kitty. Kitty's children are capped at PRI 31,
   because XNU squashes the UI and user-initiated QoS of an app-type task with no role down to LEGACY.
   I measured that a process can call `task_policy_set(self, TASK_CATEGORY_POLICY,
   TASK_FOREGROUND_APPLICATION)` with no privilege. Its main thread then reads **PRI 46/47**. Adding
   `QOS_CLASS_USER_INITIATED` reads **PRI 37**. At load 182-234 the 37 and 47 bands showed
   **wall/cpu 1.00-1.07 and p99 wake overshoot 0.66-2.35 ms**. PRI 31 showed 1.11-7.05 and 4.5-49 ms,
   and the utility clamp 20.8-153 and 162-908 ms (§3.2). The role survives `exec` (§3.4).
4. **The one hard blocker is launchd's default clamp.** A job with no `ProcessType`
   (com.reso.lr-reconciler, com.reso.lr-reset-poller, the watchdog, the rig) runs its whole tree at
   PRI 20. Nothing inside that tree can climb out. Measured: a fresh process type, the foreground role
   and a QoS raise all read PRI 20 under a utility clamp (§3.4). So `ProcessType Interactive` is the
   operator's gate. Once it is in place, the self-promotion levers work without further privilege.
5. **Demoting fleet background work buys little and costs a lot.** 514 processes already sit at PRI 4.
   Background QoS never finishes at saturation: my bench under `-c background` did not finish in
   120 s, against 0.2-0.3 s at 31. And each demoted runnable thread still counts in the load average.
   Lifting the few actuators (§5 L1-L3) is the lever. Demoting the many is not.

## 1. Repo knowledge read first

- Memory `darwin-qos-band-mechanics.md` (2 days old; re-verified here where it mattered):
  - `nice` alone does not move PRI, and only `taskpolicy -c` does.
  - The band is a one-way ratchet back to 31.
  - A LaunchAgent with no `ProcessType` runs at PRI 20.
  - `com.reso.lr-reset-poller` puts the whole move lane at 20: "a 5 s wait took 41-50 s, a precheck 163 s".
  - Background QoS never finishes at load 400-600.
- `docs/research/lr-inplace-immediacy-2026-10-18/REPORT.md:153-166` (§6 item 1) found the same PRI-20
  lane and staged `com.reso.lr-move-kick` with `ProcessType Interactive`
  (`launchd/staged/com.reso.lr-move-kick.plist`). It also records "What is not measured is this lane's
  latency at 31". This file measures it (§3.3).
- `scripts/limit-recover/lr-reset-poller.sh:249-258` documents the PRI-20 cause. Its own plist has no
  `ProcessType`.
- `scripts/limit-recover/lr-move-batch.sh:335-339` deliberately clamps the switch census to `utility`
  (19-27 CPU-s). At load ~186 that band costs 30-150x (§3.2).
- `scripts/limit-recover/lr_recon/admit.py:60-73` (`default_runner`, 30 s bound) records in its own
  docstring: "six 'probe-error' refusals at load ~259 were the 30 s bound firing on a demoted child".
- `scripts/limit-recover/lr_recon/admit.py:150-157` (`cpu_ok`): the gate is `load1 / ncpu`. §2 shows
  this ratio counts E-core-confined background threads.
- The reconciler plist source, `scripts/limit-recover/com.reso.lr-reconciler.plist`, has no
  `ProcessType`. The same holds for `com.reso.lr-reconciler-rig.plist`,
  `com.reso.lr-reconciler-watchdog.plist`, `com.reso.lr-reset-poller.plist` and
  `launchd/com.claude.boot-resume.plist` (grep for `ProcessType` => no matches in any of them).

## 2. What XNU's load average counts (web + source)

- `osfmk/kern/sched_average.c`, `compute_averages`:
  `nthreads = os_atomic_load(&sched_run_buckets[TH_BUCKET_RUN], relaxed) - 1; ... sched_nrun = nthreads;`
  The load average (`avenrun`) is the exponential average of `sched_nrun`.
  Source: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/kern/sched_average.c
- `osfmk/kern/sched.h`, `sched_bucket_t`: `TH_BUCKET_FIXPRI, TH_BUCKET_SHARE_FG, TH_BUCKET_SHARE_IN,
  TH_BUCKET_SHARE_DF, TH_BUCKET_SHARE_UT, TH_BUCKET_SHARE_BG, TH_BUCKET_RUN /* All runnable threads */`.
  Constants: `BASEPRI_FOREGROUND 47`, `BASEPRI_USER_INITIATED 37`, `BASEPRI_DEFAULT 31`,
  `BASEPRI_UTILITY 20`, `MAXPRI_THROTTLE 4`.
  Source: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/kern/sched.h
- **Consequence:** load is a count of runnable *threads* in every QoS bucket, including a background
  thread that can only run on the 2 E-cores. `load1/ncpu` divides that count by 10 cores, 2 of which
  are the only cores the background threads can use. Background threads cannot use P-cores even when
  P-cores are idle (eclecticlight, measured by its author, not Apple docs:
  https://eclecticlight.co/2025/05/09/what-is-quality-of-service-and-how-does-it-matter/ ,
  https://eclecticlight.co/2026/02/17/in-the-background-putting-threads-to-work/ ). A starved
  background thread stays runnable, so **demoting work to background raises the load average** while
  it stops competing with P-core work.

### Clutch/Edge scheduler semantics that matter (Apple's doc)

Source: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/doc/scheduler/sched_clutch_edge.md

- Threads are scheduled in a three-level hierarchy: root bucket per QoS band, then thread group, then thread.
- Root buckets are chosen earliest-deadline-first. Worst-case execution latency (WCEL) per bucket:
  FG 0, IN 37.5 ms, DF 75 ms, UT 150 ms, BG 250 ms. Warp: FG 8 ms, IN 4 ms, DF 2 ms, UT 1 ms, BG 0.
- A lower bucket gets a starvation window, so 31 cannot fully starve 20. But each band waits behind
  every band above it, up to its WCEL per selection.
- Within a root bucket, thread groups compete by `maxpri + interactivity_score`. Groups that mostly
  sleep get preferred over CPU-bound ones.
- **Implication:** a 37 (IN) or 47 (FG) actor is in a different root bucket from the fleet's 31 (DF).
  It wins the EDF selection by design whatever the number of DF threads. That matches the measured
  wall/cpu ≈ 1.0 (§3.2). The 20 (UT) lane waits behind every DF thread, which matches the measured
  20-150x.

### QoS ceilings: why the fleet is capped at 31 and an actor can go above it

Source: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/kern/task_policy.c
(WebFetch excerpts).

- For app apptypes (`TASK_APPTYPE_APP_DEFAULT`/`APP_NONUI`), the ceiling is set by role.
  `case TASK_UNSPECIFIED: /* Apps that don't have an application role get USER_INTERACTIVE and
  USER_INITIATED squashed to LEGACY */ next.tep_qos_ceiling = THREAD_QOS_LEGACY;`
- For daemons: `/* Daemons and dext get USER_INTERACTIVE squashed to USER_INITIATED */
  next.tep_qos_ceiling = THREAD_QOS_USER_INITIATED;`.
- Primordial main-thread QoS: APP_DEFAULT gets USER_INTERACTIVE. DAEMON_INTERACTIVE, STANDARD and
  ADAPTIVE get LEGACY. DAEMON_BACKGROUND gets BACKGROUND. The task's clamp then applies via MIN.
- `proc_set_task_spawnpolicy` sets the apptype from the spawn attribute with no privilege check.
  `task_policy_set` requires privilege only for the CONTROL and GRAPHICS roles.

## 3. Measurements

### 3.1 Who is runnable at "load 125" (live census)

`ps -axo pri= | sort -n | uniq -c` (load 124-128) =>
`117 @0, 514 @4, 132 @20, 681 @31, 44 @37, 42 @46, 14 @47, ... 1 @79`.

Runnable threads by PRI (`ps -M -A -o pid=,state=,pri=`, fields NF-1/NF), three samples at
`vm.loadavg` 124-129:

| sample | runnable threads | PRI 4 | PRI 20 | PRI 31 | other |
|---|---|---|---|---|---|
| 1 | 91 | 67 (74%) | 16 | 5 | 3 |
| 2 | 82 | 60 (73%) | 15 | 6 | 1 |
| 3 | 68 | 37 (54%) | 19 | 4 | 8 |

The PRI-4 runnable owners included `mds_stores`, `duetexpertd`, `gh`, `jq`, `find`,
`idl-abstain-alarm.sh`, `cc-reaper sweep`, `agentsync sync`, `claude-accounts --login-status`
(at `pri4 nice10`), Dia renderer and others. These are already demoted background work.
**At this moment the PRI-31 band had 4-6 runnable threads on 8 P-cores. A PRI-31 actor would barely
have waited, and a PRI-20 actor queued behind ~16 peers plus everything at 31.** I did not capture the
band mix during the 300-375 peaks; `~/.reso/load.jsonl` records process-level `runnable` only
(`reso-management-app/scripts/load-sampler.sh:62`). This is an open question.

Live process bands of the actors (`ps -axo pid,ppid,pri,nice,...`):

| process | PRI | why |
|---|---|---|
| `python -m lr_recon` (pid 38189, com.reso.lr-reconciler) | **20** | launchd "daemon (3)" spawn type, no ProcessType (`launchctl print gui/501/com.reso.lr-reconciler` => `spawn type = daemon (3)`) |
| its child `claude-accounts` (45395) | 20 | inherited clamp |
| `lr-fleet.sh --one … --from-daemon` (23199) | 20 | inherited |
| `handoff-fire.sh --recycle --transplanted-source` (14601, 23381) | 20 | inherited |
| `lr-reset-poller.sh` (1938) | 20 | launchd default |
| `lr-fire-resume.sh` / `expect` in a pane (24868, 29897) | 31 | kitty child |
| every `claude` session (e.g. 35226, 39922, 87772) | 31 | kitty child, app-type with no role, so capped at LEGACY |
| kitty main thread (853) | 46 (`ps -M -p 853`, row 1) | foreground app UI thread; other kitty threads 31 |
| WindowServer (633) | 79 | |
| `com.claude.research-classifier-warm` (60282) | 31 | `spawn type = interactive (4)`, the precedent for ProcessType Interactive |

### 3.2 Band benchmark: one fixed workload at each band, under live load

Probe `/tmp/qos-probe-04/bench.py`. It sets the band on its own process and then measures:
- 200 × `sleep(5 ms)`, reporting the overshoot percentiles;
- a fixed 3 M-iteration CPU loop, reporting wall/cpu, where 1.0 means it got a core the whole time.

Command: `/usr/bin/python3 -I bench.py <mode>`, optionally under `taskpolicy -c utility|background`.

| band (how) | own PRI | load1 | wake p50 / p99 / max ms | CPU loop wall/cpu |
|---|---|---|---|---|
| default, pane-born (none) | 31 (decays to 22 under contention) | 125-234 | 1.27-1.33 / 4.46-49.28 / 4.96-62.5 | 1.11-7.05 (6 runs) |
| `in` QoS, pane-born (request squashed) | 31, decays to 19-21 | 222-230 | 1.34-1.51 / 11.0-26.9 | 1.19-2.37 |
| **FG role + `in` QoS** (`task_policy_set` + `pthread_set_qos_class_self_np`) | **37** | 184-188 | 1.27 / **1.49-2.35** / 2.35 | **1.03-1.07** (3 runs) |
| **FG role** (UI main thread) | **47** | 182-234 | 0.64 / **0.66-0.73** / 0.76 | **1.00** (5 runs) |
| `utility` QoS self-set | 20 | 134 | 20.1 / 210 / 213 | 20.8 |
| `taskpolicy -c utility` (emulates the launchd-default lane) | 20 | 164-221 | 19.6-21.8 / 162-684 / 183-909 | **31-153** (3 runs) |
| `taskpolicy -c background` | 4 | ~183 | did not finish | **>400x: rc 124 at a 120 s bound** (2 runs) |

Source: the bench.py output lines in this session. The load moved between 122 and 234 during the
runs, and the load1 column gives the value at each run.

### 3.3 The real lane workload: `cc-lr status` at 31 vs utility clamp

`/usr/bin/time -p timeout … ~/.claude/bin/cc-lr status` (permitted read-only verb):

| run | PRI 31 real (user) | utility-clamped PRI 20 real (user) | load1 |
|---|---|---|---|
| 1 | 0.95 s (0.26) | 36.81 s (0.27) | 186-190 |
| 2 | 1.98 s (0.29) | 87.99 s (0.36) | 163-186 |

Both bands burned the same CPU. Only the wait differed. This is the latency at 31 that the 10-18
REPORT left unmeasured.

**Kitty remote control from each band.** `kitten @ --to unix:/tmp/kitty-853 ls` returns 645 KB of
JSON. It took 0.05-0.06 s at PRI 31 and 0.41-0.83 s under a utility clamp, at load 184-188 (3 runs
each). So at load ~186 **kitty itself answered at once** (its main thread is at 46). The client band
alone costs 8-14x.

Placer durations from `~/.reso/limit-recover/recon/events.jsonl` (`ev=place`):
- n=237, 16 timeouts (rc 124);
- rc 0 median 3.8 s, Pearson(load1, dur) = 0.74;
- runs at load ~100 took 75.7 s, and timeouts happened at load1 84-89 (bounds 63-66 s).

This PRI-20 lane is load-sensitive. §3.2-3.3 show the sensitivity comes from the band.

### 3.4 What can and cannot be lifted (positive controls)

Probes: `pri.py` reads its own main-thread PRI, `spawn.py` calls `posix_spawn` with
`posix_spawnattr_setprocesstype_np`, `role.py` calls `task_policy_set`, `execq.py`/`rolexec.py` test
`exec`.

| construction | result (own PRI / plain child PRI) |
|---|---|
| pane-born, request `ui` or `in` QoS | 31 / 31 (squashed: app type, no role) |
| pane-born, `task_policy_set(FOREGROUND)` | **46** / 31 |
| … + `ui` QoS | **47** / 31 |
| … + `in` QoS | **37** / 31 |
| `task_policy_set(USER_INIT_APPLICATION=9)` | kr=4 (refused), 30 |
| `posix_spawn` as DAEMON_INTERACTIVE, then `in` QoS | **37** (daemon ceiling = IN) |
| DAEMON_STANDARD (no launchd clamp), then `in` | 37 |
| DAEMON_INTERACTIVE, then FG role + `ui` | 37 (daemon ceiling holds) |
| DAEMON_INTERACTIVE → spawns APP_DEFAULT child → FG role + `ui` | **47** |
| DAEMON_ADAPTIVE / DAEMON_BACKGROUND | did not finish in 60 s (DARWIN_BG) |
| `posix_spawnattr_set_qos_class_np(in)` | rc 22 (EINVAL); it only clamps downward |
| raise QoS to `in`, then `exec /bin/sh` | after exec 30-31 (thread QoS is reset by exec) |
| **FG role, then `exec /bin/sh`** | **after exec 47**, its `$(…)` child 31 (task role survives exec; not inherited by children) |
| **under `taskpolicy -c utility`**: FG role + `ui`; DAEMON_INTERACTIVE spawn + `in` | **20 / 20** (the clamp is inherited through every route) |
| under `taskpolicy -c background`: DAEMON_INTERACTIVE spawn | did not finish in 90 s |

Conclusions:
- (a) Raising priority is the process's own act: no root, no entitlement. It is blocked only by a
  clamp in its ancestry. A no-`ProcessType` launchd job is such a clamp: it reads PRI 20, and the
  memory's `taskpolicy -a` stays 20.
- (b) `ProcessType Interactive` gives the tree DAEMON_INTERACTIVE with no clamp, so 31 by default.
  Python actors can then lift themselves to 37, or to 47 through one APP_DEFAULT spawn hop.
- (c) Bash cannot call these APIs. A tiny role shim (set FG role, then exec the script) lifts the
  script's own process to 47. Its child commands (jq, ps, kitten, python) stay at 31.
- (d) Which `taskpolicy` flags exist (`man taskpolicy`): `-c utility|background|maintenance` (clamp,
  downward only), `-b/-B` (DARWIN_BG on/off), `-t`/`-l` (throughput/latency tier), `-a`
  (application resource policies). None of them raise above 31.
- (e) `launchd.plist(5)` (`man launchd.plist`, ProcessType): "If left unspecified, the system will
  apply light resource limits to the job, throttling its CPU usage and I/O bandwidth … Interactive
  jobs run with the same resource limitations as apps, that is to say, none."

## 4. Mapping to the incident blockers

| blocker (2026-10-20) | Darwin-band reading | evidence |
|---|---|---|
| admission probe "probe-error" (30 s bound) | bash `cc_capacity_probe` child of a PRI-20 daemon. The admit.py docstring already says "the 30 s bound firing on a demoted child" | admit.py:60-73; §3.3 shows a 37-44x tax at 20 |
| CPU brake `cpu_ok(load1, ncpu)` refused every pass | gates on a thread count that is mostly PRI-4, E-core-confined work (§3.1). It measures nothing the actor competes with at 31/37/47 | sched_average.c; §3.1 |
| drip behind the brake | a gate-order bug (axis 01). With the actor at 37/47 the brake has no physical basis | §3.2 |
| placer rc=124 at 120 s → WAIT_DATA ~30 min | `claude-accounts --place` (Python) at PRI 20. Median 3.8 s when unloaded | events.jsonl stats §3.3 |
| idle lane `HELD:load` (38/core > 20/core) | a load-average policy bound. Wake p99 at 37/47 stays ≤ 2.4 ms at load 182-234 | §3.2 |
| kitty RC 10 s non-answer, composer unreadable, rollback after transplant | at load ~186 kitty answered `@ ls` in 0.05 s at PRI 31 vs 0.41-0.83 s from PRI 20. The incident callers were PRI-20 lane processes. **Hypothesis:** the client band plus 645 KB `ls` payloads at load 300+, not kitty itself. Second hypothesis (unverified): kitty is App-Nap eligible (`defaults read net.kovidgoyal.kitty NSAppSleepDisabled` => "does not exist"; `pmset -g assertions` shows no kitty activity assertion) | §3.3 |

## 5. Levers (ranked by value per effort)

**L1 — `ProcessType Interactive` for the reconciler tree (operator activation).**
- Change: add `ProcessType Interactive` to `scripts/limit-recover/com.reso.lr-reconciler.plist`, and
  load the already-staged `com.reso.lr-move-kick` (or give `lr-reset-poller` the same key). The
  operator then re-bootstraps.
- Mechanism: the launchd utility-class clamp is removed, so lane PRI goes from 20 to 31. The lane then
  ties with the fleet instead of queuing behind it.
- Expected effect: measured on the same workload, `cc-lr status` 37-88 s becomes 1-2 s at load 186,
  and kitty-RC client time 0.4-0.8 s becomes 0.05 s. The probe and placer bounds stop firing for band
  reasons.
- Prerequisite for L2-L3 (the clamp blocks them, §3.4).
- Risk: the reconciler's own bulk work (ps censuses) now competes at 31. Keep the explicit
  `taskpolicy -c utility` clamps only on bounded, non-critical bulk.
- Read back `ps -o pri` ≥ 31 after load, as `53-lr-move-kick-activate.sh` does.
- The memory notes a `Bootstrap failed: 5` re-bootstrap race.

**L2 — Self-promotion of the Python actors to 37 (FG role + USER_INITIATED).**
- Change: one helper, e.g. `lr_recon/qos.py`, using ctypes:
  `task_policy_set(mach_task_self_, 1, &1, 1)`, then
  `pthread_set_qos_class_self_np(0x19, 0)`. Call it at start in the reconciler, `claude-accounts`
  (under an env opt-in that only the LR lane sets) and `lr-lock.py`. Log the read-back PRI and degrade
  open if it reads < 37.
- Mechanism: the actor moves into the IN root bucket (WCEL 37.5 ms), which EDF picks ahead of the DF
  fleet.
- Expected effect: wall/cpu 1.03-1.07 and p99 wake ≤ 2.4 ms at load 184-188 (measured), against
  1.4-7 at 31.
- Why 37 and not 47: 47 would outrank kitty's main thread (46) if an actor ever busy-loops. 37 sits
  above the fleet and below kitty and WindowServer.
- Note: under launchd Interactive the role is ignored for the ceiling (daemon ceiling 37), so the
  same call yields 37 there with no spawn hop. Measured: "DAEMON_INTERACTIVE, then FG role + ui" read 37.
- Risk: undocumented use of a role on a non-GUI process, which a future macOS or RunningBoard could
  override. It was measured only for seconds-long processes, so the long-lived reconciler should
  re-read its band every pass.

**L3 — Role shim for the bash critical path and the kitty client.**
- Change: add `bin/cc-band-exec`, a Python wrapper that sets the FG role (and, in a launchd-Interactive
  tree, first spawns itself as APP_DEFAULT), then `os.execv`s the target. Wrap `lr-handoff.sh`,
  `handoff-fire.sh --recycle`'s watcher, `lr-fire-resume.sh`, `cc_capacity_probe` and the
  `kitten @` calls in cc-tui.sh.
- Mechanism: the role survives exec, measured at 47 after exec, so the script's own interpreter runs
  in the FG bucket.
- Expected effect: the bash process's own waits, polls and parsing stop queuing. Its child commands
  stay at 31, which is parity, and that is fine when the 31 band holds 4-10 runnable threads (§3.1).
- Risk: a shim that crashes before exec must fall through to a plain exec (fail-open).
- The two-hop daemon→APP_DEFAULT→role→exec chain is measured only in pieces (nest test 47; rolexec 47).
  It needs one end-to-end positive control.
- Do not apply it to long CPU-heavy loops.

**L4 — Replace load-average gates with a band-scoped latency canary.**
- Change: `cpu_ok` (admit.py:150-157), the idle lane's 20/core `HELD:load`, and the 8/core recycle
  bound should gate on what the actor will experience. Run 200 × 5 ms sleeps (1 s) at the actor's own
  band and refuse only if p99 > N ms. Or count runnable threads at PRI ≥ the actor's band
  (`ps -M -A -o pid=,state=,pri=`), which is cheaper.
- Mechanism: the measured quantity is what the actor competes with, not E-core background backlog.
- Expected effect: with L1-L2 in place the canary reads ≈ 1-2 ms at load 180-234 (measured), so the
  gate opens at always-high load. The brake survives only for real P-core saturation.
- Risk: a canary run at the wrong band lies. It must run in the same process and band as the actor.
  It is cross-cut with axis 05 (signal replacement).

**L5 — Never put critical-path work in utility/background, and size bounds to the band.**
- Measured tax: utility 20-153x at load 134-221, background > 400x (§3.2).
- Change: drop `LR_MOVE_CENSUS_CLAMP` utility for the census (lr-move-batch.sh:335-339). Its 19-27
  CPU-s at 31 is trivial on 8 P-cores, against 10-60 min at the measured utility tax.
- Change: any detached LR work that must complete uses ≥ 31, never `-b` (the memory's evidence-gc leak).
- Risk: slightly more P-core contention for sessions while a census runs.

**L6 — Record the band mix with every load sample.**
- Change: add a per-PRI runnable-thread histogram to `load.jsonl` (gl.reso.load-sampler, a reso-repo
  script), or to a LR-owned sampler.
- Mechanism: the next incident can then show whether the 31 band (the actor's competition) was
  saturated at load 300-375. That figure is not knowable from current data.
- Risk: the `ps -M -A` cost is about 5,700 thread rows per sample, so sample at ~60 s.

**L7 — Shrink kitty RC payloads and check App Nap.**
- Change: use `@ ls --match …` or a narrower query instead of the 645 KB full `ls` in the resolver.
- App Nap: the operator can verify in Activity Monitor (App Nap column) whether kitty naps when its
  windows are occluded or the screen is locked. If it does, `defaults write net.kovidgoyal.kitty
  NSAppSleepDisabled -bool YES` is an operator setting. That write is not done here, and whether
  current macOS honours the key is disputed (https://eclecticlight.co/2017/11/15/undead-apps-and-opting-out-of-app-nap/).
- Risk: low. The App Nap part is a hypothesis.

**L8 (not recommended as a primary lever) — demote fleet background work.**
- 514 processes are already at PRI 4.
- Demoting more hooks or pollers to background makes them never finish at saturation (memory
  2026-10-12) and adds to the load average (§2).
- Hooks run synchronously on each session's turn, so demoting them slows every session.
- Utility is acceptable only for detached, bounded, non-critical pollers.
- With L1-L2 the actors no longer depend on what the fleet is doing.

## 6. What this does not fix

- The pane-side phases run in the session's own process tree, which is a kitty child at 31: the
  source's `/exit` and SessionEnd hooks, and the relaunched `claude` boot. They tie with the fleet.
- Lifting the target `claude` with the role shim would make that session permanently FG-band for its
  whole life. A process can set only its own role, so nothing could lower it later. That is not
  recommended.
- If the 31 band itself saturates at incident peaks (unknown, see L6), these phases slow down.
  Moving more of each phase out of the pane is the remedy (axis 08, zero-restart).
- Reconciler logic bugs (WAIT_RESET, the rollback orphan) are untouched by priority.

## 7. Evidence index (commands run)

- `ps -axo pid,ppid,pri,nice,stat,etime,time,comm,args | grep …`: actor bands (§3.1)
- `ps -M -p 853`, `ps -M -p 60282`: kitty main 46, other threads 31. Interactive daemon 31.
- `ps -M -A -o pid=,state=,pri=` + awk: runnable-thread census by PRI (§3.1)
- `launchctl print gui/501/<label> | grep 'spawn type'` (read-only print):
  - reconciler, reset-poller, boot-resume, watchdog, capacity-alarm: `daemon (3)`
  - classifier-warm: `interactive (4)`
  - dispatcher: `background (5)`
  - lr-move-kick: not loaded (empty output)
- `plutil -p ~/Library/LaunchAgents/com.reso.lr-reconciler.plist`: no ProcessType
- `/usr/bin/python3 -I /tmp/qos-probe-04/{bench,pri,spawn,role,execq,rolexec}.py …`: §3.2, §3.4
- `/usr/bin/time -p … cc-lr status` and `… taskpolicy -c utility cc-lr status`: §3.3
- `/usr/bin/time -p … kitten @ --to unix:/tmp/kitty-853 ls`: §3.3
- `events.jsonl` `ev=place` statistics (python): §3.3
- `sysctl kern.sched`, `sysctl -n vm.loadavg`, `man taskpolicy`, `man launchd.plist`,
  `pmset -g assertions`, `defaults read net.kovidgoyal.kitty NSAppSleepDisabled`

## Skeptic review

Reviewer: adversarial skeptic for axis 04. Run 2026-10-20 about 04:52-05:20Z, at load1 182-224 the
whole time (`sysctl -n vm.loadavg`). Read-only throughout: I typed into no pane, signalled no process
and ran no `launchctl` command. That means I could not re-run `launchctl print`, and the `spawn type` reading is
replaced below by a kernel max-priority reading. The only processes I started were short probes that
changed their own priority and exited. They are in `/tmp/skeptic-04/` (`census.py`, `thr.py`,
`persist.py`, `place.py`, `run1.sh`, `census-loop.sh`). I also re-ran the author's probes in
`/tmp/qos-probe-04/` unchanged. The XNU sources I fetched are in `/tmp/skeptic-04-dl/`.

### R0. New measurements this review rests on

- **R0.1 `cc-lr status` band A/B.** Measured with `bash /tmp/skeptic-04/run1.sh` (interleaved, load 214-224,
  output in `/tmp/skeptic-04/run1.out`).
  - At PRI 31: **1.38, 1.97 and 1.09 s**.
  - Under `taskpolicy -c utility`: **61.41, 33.20 and 42.06 s**.
  - User CPU: 0.27-0.28 s at 31 and 0.31-0.34 s at 20.
  - Per-pair ratio: **17-44x**.
- **R0.2 Census by base priority versus current priority.** `/usr/bin/python3 -I /tmp/skeptic-04/census.py`
  reads `proc_pidinfo(PROC_PIDTHREADINFO)` for every thread of every same-user process:
  - `pth_priority` is the base priority and `pth_curpri` the current one;
  - a thread counts as runnable when `run_state == 1`;
  - about 1,170-1,200 of about 1,600 processes were readable, so root-owned daemons are missing and the counts are lower bounds.

  Measured, 8 samples (`census.py` once, then `census-loop.sh`):

  | load1 | runnable | base 4 | base 20 | **base 31** | shown as 31 by current pri (what `ps` sees) | base ≥ 37 |
  |---|---|---|---|---|---|---|
  | 219 | 178 | 133 (75%) | 28 | **17** | 6 | 0 |
  | 213 | 128 | 58 (45%) | 22 | **48** | 38 | 0 |
  | 202 | 137 | 94 (69%) | 28 | **12** | 4 | 2 |
  | 194 | 106 | 69 (65%) | 23 | **14** | 7 | 0 |
  | 187 | 133 | 99 (74%) | 12 | **22** | 21 | 0 |
  | 182 | 171 | 141 (82%) | 18 | **12** | 2 | 0 |
  | 196 | 212 | 167 (79%) | 28 | **13** | 6 | 4 |
  | 193 | 151 | 108 (72%) | 19 | **17** | 16 | 6 |

  In the first sample, 11 of the 17 base-31 runnable threads showed a current priority of 23-30, or 0.
  In sample 2, 36 of the 48 base-31 runnable threads were `claude.exe`.
- **R0.3 Kernel band of the actors.** `/usr/bin/python3 -I /tmp/skeptic-04/thr.py <pid>` reads base, current and max priority:

  | process | base | max |
  |---|---|---|
  | `python -m lr_recon` (pid 51148, restarted since the doc's pid 38189) | 20 | **20** |
  | `lr-reset-poller.sh` (65409) | 20 | **20** |
  | `taskpolicy -c utility /bin/sleep` | 20 | **20** |
  | `com.claude.research-classifier-warm` (60282, launchd `ProcessType Interactive`) | 31 | **63** |
  | `claude.exe` (16567) | 31 | 63 |
  | kitty 853 main thread (it read 46 in the doc) | **47** | 63 |

  A max of 20 is a hard ceiling. It is identical to a utility clamp and stands in for the `spawn type = daemon (3)` reading I could not re-run.
- **R0.4 Replications of §3.4** (load ~215):
  - `role.py 1 none` read **47T**; the doc says 46.
  - `role.py 1 in` read **37T**, and its child 31.
  - `rolexec.py` read `after-exec pri= 47 child= 31`.
  - Under `taskpolicy -c utility`, `role.py 1 ui` read **20T**, and its child 20.
  - `spawn.py daemon_interactive none in` read 37; with `role:ui`, 37; `nest:role:ui`, **47**.
  - Under utility, the same spawn read **20**.
- **R0.5 `bench.py`** (load 214-219, 2 rounds):

  | band | wake p99 | wall/cpu | note |
  |---|---|---|---|
  | none (31) | 5.40-12.10 ms | 1.15-1.46 | own main thread read **0T and 6T** after its 0.2 s CPU loop: timeshare decay to the floor |
  | role-in (37) | 2.03-2.51 ms | 1.04-1.06 | |
  | role-fg (47) | 0.65-0.66 ms | 1.00 | |
- **R0.6 Role persistence.** `/usr/bin/python3 -I /tmp/skeptic-04/persist.py 240 in`: FG role plus IN QoS held
  **base 37 / max 63 on all 17 reads over 240 s** at load 182-224. Its plain child read base 31.
- **R0.7 Placer statistics.** `/usr/bin/python3 -I /tmp/skeptic-04/place.py ~/.reso/limit-recover/recon/events.jsonl`:
  - n=240, rc 0 = 223, rc 124 = 17;
  - rc-0 median 3.9 s; Pearson(load1, dur) 0.77.
  - rc-0 median by load1:

    | load1 | n | median |
    |---|---|---|
    | < 50 | 134 | 2.8 s |
    | 50-100 | 45 | 4.0 s |
    | 100-200 | 29 | 17.8 s |
    | ≥ 200 | 15 | 44.8 s |
- **R0.8 Background never finishes, seen live.** pid 32123 was another session's probe:
  `taskpolicy -b bash -c '… cc_capacity_probe lr-reconciler first-turn'`. `ps -o pid,pri,time,etime` =>
  `32123 4 0:00.07 01:12:55`, which is 0.07 CPU-s in 73 minutes at PRI 4. It was gone by the end of the review.

### R1. Key findings

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| F1 | Recovery was slowed by its band, not the load; actors at PRI 20, fleet at 31 | **WEAKENED** | *Band facts confirmed:* R0.3 shows lr_recon and the reset poller at base 20 with **max 20**, and sessions at base 31/max 63. *Causal claim overstated.* Axis 02's minute ledger (`02-timeline-forensics.md:375-390`) puts about 49% of the 793 lost session-minutes (estimated, by summing its classes that run inside the PRI-20 tree: pass cadence 18.9, actuator wall 12.8, placer 8.1, kitty unreachable 5.6, probe 2.7, composer 1.0) where a band change can act. The other ~51% are load-average policy gates or logic defects that no band change touches: move `HELD:load` 19.1% (a redundant copy of a typing bound; see L4), CPU brake 3.9%, plan-only hook records 9.1%, false `HELD:busy` 8.1%, PRE-MOVE bug 5.8%, restart claim re-stamp 3.3%, operator re-issue 1.6%. Example: incident batch `move/20261020T030423Z-…-15173/9240c6a9….events.jsonl` sat at `load-wait` from 03:06:35 to 03:34:22Z (**27.8 min**, a policy gate), then took 19.0 min `actuate`→`actuated`, which is band-sensitive. And "not the load" is a false split, because the PRI-20 tax itself grows with load (R0.7: rc-0 placer median 2.8 s at load1 < 50, 44.8 s at ≥ 200). |
| F2 | Same lane work is 37-44x slower at PRI 20 for the same CPU | **CONFIRMED** (range widened) | R0.1 reproduces it at load 214-224: 1.09-1.97 s against 33.2-61.4 s, the same ~0.3 user-CPU-s, **17-44x**. The author's saved outputs `/tmp/qos-probe-04/s31.*`, `s20.*`, `t31.*`, `t20.*` match the cited numbers. Axis 03 found the same independently (`03-harm-evidence.md:15-20`): `ps -axo` 0.22-0.37 s against 16.5-25.6 s, and `python3 -I -c 'import json,os'` 0.20-0.30 s against 11.4-15.3 s. |
| F3 | Load average counts every runnable thread; most are E-core background; load1/ncpu is not the P-core actor's competition | **WEAKENED** | *Source confirmed:* `sched_average.c:288,306` (`nthreads = …sched_run_buckets[TH_BUCKET_RUN] - 1; … sched_nrun = nthreads`) and `sched.h:231` (`TH_BUCKET_RUN, /* All runnable threads */`). *Majority-background confirmed:* R0.2 has base-4 at 45-82% of runnable threads. *The supporting census is wrong where it matters.* "Only 4-6 at PRI 31" came from `ps`, which prints the **current, decayed** priority. A base-31 thread that has just used CPU reads 23-30, or as low as 0 (R0.5: bench's own 31 thread read 0T and 6T). By base priority, the DF band held **12-48 runnable threads in all 8 samples**. That is always above the 8 P-cores, and 1.05-6x what `ps` showed. So §3.1's "a PRI-31 actor would barely have waited" is refuted. The 31 band is oversubscribed at load ~200, which is why the bench's 31 runs show wall/cpu 1.11-7.05 rather than ~1.0. |
| F4 | An unprivileged process can lift itself above the fleet (FG role ⇒ 46/47; + IN ⇒ 37) | **CONFIRMED** | R0.4 replicated it: 47, 37 and 20 under a clamp. Source: `task_policy.c:360-381`. `TASK_FOREGROUND/BACKGROUND/DEFAULT_APPLICATION` are set with no privilege check, and only embedded forbids setting your own role (`#if !defined(XNU_TARGET_OS_OSX)`). Lines 879-883: "Apps that don't have an application role get USER_INTERACTIVE and USER_INITIATED squashed to LEGACY". Line 887-888 gives the daemon ceiling USER_INITIATED. Correction: role FG without QoS read 47 here, not 46. |
| F5 | 37/47 latency barely moves with load; 31 degrades; utility collapses | **CONFIRMED** (at ≤ 224 only) | R0.5 at load 214-219: 47 has p99 0.65 ms and wall/cpu 1.00; 37 has 2.0-2.5 ms and 1.04-1.06; 31 has 5.4-12.1 ms and 1.15-1.46. Utility is 17-44x (R0.1). This is consistent with R0.2: the ≥ 37 bands held 0-6 runnable threads. Not measured at 300-375, by either the author or me. |
| F6 | An inherited utility clamp blocks every route up; ProcessType Interactive is the required operator step | **CONFIRMED** (one caveat) | R0.4: role plus `ui`, and a DAEMON_INTERACTIVE spawn plus `in`, both read 20 under a utility clamp. R0.3: launchd's default job has max 20, while the `ProcessType Interactive` job (research-classifier-warm) has base 31 and max 63. That is the positive control for L1. Caveat: "cannot be escaped from inside the lane" is too strong. Work the lane gets run by kitty is unclamped, and §3.1's own table puts `lr-fire-resume.sh`/`expect` in a pane at 31. That route still couples recovery to kitty RC, which takes 1-30 s from PRI 20 (`07-kitty-control-plane.md:21-24`), so the plist key remains the clean route. |
| F7 | A task role survives exec; a thread QoS raise does not; children stay at 31 | **CONFIRMED** | R0.4 `rolexec.py` read `after-exec pri= 47 child= 31`. Source: `task_policy.c:2195-2206` `proc_inherit_task_role()` ("Inherit task role across exec"). |
| F8 | Kitty answers at once at load ~186; incident RC timeouts were PRI-20 callers; App Nap unverified | **CONFIRMED** (two corrections) | Corroborated by axis 07. Kitty answered 20/20 in 0.064-0.165 s at load 196-217, and kitty's own log has **one** broken-pipe line from 02:00 to 04:35Z against ≥ 6 client failures (`07-kitty-control-plane.md:28-45`). *Correction 1:* the 645 KB payload part is unsupported, since full `ls` takes 0.05 s at 31. *Correction 2:* App Nap is not merely unverified. A measured precedent exists: kitty's main process was at **PRI 4 with the screen locked**, and 9/9 RC queries failed at exactly 10 s at load 120-133 (`docs/research/recycle-unreachable-2026-10-01.md:12`). A non-frontmost kitty was also at PRI 4 (`docs/research/session-durability-2026-10/C3-socket-robustness.md:300-302`). Kitty's main thread read 46 for the author and base 47 for me. `sched.h:160-161` defines 47 as `BASEPRI_FOREGROUND` and 46 as `BASEPRI_BACKGROUND`, the non-focal app band. So kitty's band follows focus and lock state, and it was not observed during 02:31-04:14Z. |
| F9 | Placer is load-sensitive in its PRI-20 band; it timed out even at load1 84-89 | **CONFIRMED** (one sub-claim weakened) | R0.7: n=240, 17 rc 124, median 3.9 s, Pearson 0.77. The rc-0 median rises 16x from load < 50 to ≥ 200. *Weakened:* the two "low-load" timeouts (04:18:23Z at load1 84 and 04:20:39Z at 89) came on the falling edge of the 04:08Z load-363 peak (`02-timeline-forensics.md:57`). Their bounds were also scaled *down* by the same trailing reading: `plan.py:312-318` uses `30 × load1 / (4 × ncpu)`, giving 63 s and 66 s. They do not show sensitivity at ~8/core. Blaming the band, rather than load alone, rests on analogy: there are no placer runs at 31 to compare. |

### R2. Levers

| # | Lever | Verdict | Evidence |
|---|---|---|---|
| L1 | `ProcessType Interactive` for the reconciler, and move-kick or the reset poller | **CONFIRMED** | Mechanism: R0.3 shows the Interactive job at base 31/max 63, against the default job's 20/20. Effect: R0.1 shows the same verb at 31 taking 1.1-2.0 s, against 33-61 s at 20. Limits: (a) the DF band is oversubscribed (R0.2: 12-48 runnable on 8 P-cores), so a residual tax remains. From the R0.5 and §3.2 wall/cpu figures I estimate it at 1.1-7x, still an order of magnitude better than 20. (b) It acts on only about half of the lost minutes (F1). The move-lane `HELD:load`, the hook-origin records and the false `HELD:busy` all need their own fixes. |
| L2 | Python actors set FG role plus USER_INITIATED (37) and read it back | **WEAKENED** | *Works:* 37 is measured (R0.4) and holds for ≥ 240 s under load (R0.6); the ≥ 37 bands held 0-6 runnable threads (R0.2). *Overclaimed:* "recovery work no longer depends on the fleet's load" is false for anything the actor runs as a child. The role is not inherited (R0.6 child base 31), and the actors drive bash, `ps` and other children: lr_recon used 0:31.08 CPU in 21:16 of wall time (`ps -o time,etime -p 51148`), so its own loop is a small part of a pass. *Simplification:* under L1 the tree is DAEMON_INTERACTIVE, whose ceiling is IN (`task_policy.c:887-888`). Plain `pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED)` then gives 37 (R0.4: `spawn.py daemon_interactive none in` → 37), so the undocumented-role risk disappears for the reconciler itself. Persistence beyond minutes is still unmeasured. |
| L3 | `cc-band-exec` role shim (Python) wrapping lr-handoff, the recycle watcher, lr-fire-resume, the probe, and `kitten @` calls | **WEAKENED** (the `kitten @` part refuted) | Mechanism confirmed (F7). But: (1) the shim is a Python wrapper, and the interpreter starts in the parent's band *before* it can lift. That costs 0.08-0.83 s at 31 and 2.8-15.3 s at 20 (`03-harm-evidence.md:19,360`), while a `kitten @` call costs 0.05-0.08 s at 31 (`07-kitty-control-plane.md:22`). Wrapping each `kitten @` call therefore costs at least as much as the call it is meant to speed up. (2) A bash driver spends little CPU of its own. The repo lesson "Driver CPU ≠ pipeline progress" (`.claude/rules/agent-operating-lessons-situational.md:46`) says so. Its jq, `ps`, `kitten`, python and `sleep` children stay at 31. (3) L3's stated reason that children at 31 are fine is that the 31 band holds 4-10 runnable threads. R0.2 refutes that: it holds 12-48. (4) A lifted bash at 47 ties kitty's main thread when kitty is frontmost (R0.3, base 47). |
| L4 | Replace load-average gates with a canary in the actor's own band | **WEAKENED** | The gates guard different things, and a canary in the actor's band measures none of them. The recycle bound guards **typed** relaunches: "the bound only has to cover typing, which is measured clean up to ~32/core" (`scripts/handoff-fire.sh:4108-4113`), and staged recycles are already exempt (`:4103-4104`). The move worker's 20/core wait is a *copy* of that bound (`lr-move-worker.sh:305-306,335-349`). It held staged moves (`03-harm-evidence.md` gate table), so it should become staged-aware or be dropped, not swapped for a canary. `cpu_ok` already has a 20 s anti-starvation floor (`admit.py:150-157`) and refused 2 of 11 (`02-timeline-forensics.md:45`, `03-harm-evidence.md:37`). A canary at 37/47 always passes (R0.5), which amounts to deleting the gate, more simply. It also says nothing about the cost of the admitted relaunch, which runs at 31 in the pane (§6). The cheaper canary, "count runnable threads at PRI ≥ the actor's" via `ps -M`, is unsound because of decay (F3). |
| L5 | Keep critical-path LR work out of utility and background; drop the census clamp | **WEAKENED** | *The background half is confirmed:* R0.8 saw 0.07 CPU-s in 73 min at PRI 4, and `launchd/com.claude.boot-resume.plist:46-53` records 10 min spent inside `sysctl -n kern.boottime` at PRI 4. *The census half is stale and off the incident's path.* The "19-27 CPU-s" figure is the pre-2026-10-18 full census. `LR_MOVE_SNAP_SIDS` now restricts it to waiting rows (`lr-move-batch.sh:321-331`), and the worker calls a census "~7 CPU-seconds" (`lr-move-worker.sh:135-136`). The census only gates rows that were busy at plan time (`wait:*`, `lr-move-worker.sh:142-175`). Neither incident batch had one: `ls move/20261020T0*` shows no `snap.tsv`. "10-60 min" is an extrapolation (CPU-s × utility tax), not a measurement. Once L1 lands, dropping the clamp puts the census at 31 against sessions, which is exactly why it was added (`lr-move-batch.sh:335-337`). |
| L6 | Record a runnable-thread histogram by PRI band with each load sample | **WEAKENED** (fix the method) | Recording this is right; the proposed instrument is wrong. `ps -M -A` reports decayed current priority, so it understates the DF band 1.05-6x (R0.2: 2-38 shown against 12-48 by base). Record `pth_priority` (base) from `proc_pidinfo(PROC_PIDTHREADINFO)` instead. `census.py` read ~4,800 threads in **0.25 s real** (`/usr/bin/time -p`), far cheaper than the ps estimate. It cannot read root-owned processes (~430 of ~1,600), so label it a lower bound. |
| L7 | Narrow kitty RC queries (`ls --match`) and check App Nap | **WEAKENED** (the App Nap half is the stronger half) | Payload: the full 645 KB `ls` takes 0.05 s at 31, so size is not the bottleneck. `cc_tui_rpc` already uses `ls --match id:$id` (`scripts/lib/cc-tui.sh:133`). Full listings remain in the handoff-fire kitty probe (`handoff-fire.sh:1529`, `kt ls`) and the memoised census (`lr-upgrade.sh:916`). From PRI 20, axis 07 measured `ls --match` at 0.99-5.65 s, so narrowing does not rescue a starved client. App Nap: this is a measured precedent, not a hypothesis (F8: PRI 4 with the screen locked and 9/9 queries failing at 10 s on 10-01). It deserves a higher rank than the doc gives it. `NSAppSleepDisabled` stays an operator act, and its effect is unproven. |

### R3. Answers to two open questions (partial)

- **Is the 31 band saturated at high load?** At load 182-219: **yes, already.** The DF band held 12-48
  runnable threads in all 8 samples (R0.2). The incident's 300-375 was not reproduced. So the doc's
  "L1 alone may be enough" premise is weaker than §3.1 implies, and L2 matters for the Python actors.
- **Does a self-set role persist?** It persisted for 240 s at load 182-224 (R0.6). Hours are still unmeasured.
