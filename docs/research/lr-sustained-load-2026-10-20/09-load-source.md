# 09 · What generates the sustained load (axis 09-load-source)

Read-only census, 2026-10-20 04:19-04:41Z, on the live box (10 logical CPUs: **8 P-cores + 2 E-cores**,
`sysctl -n hw.ncpu hw.perflevel0.logicalcpu hw.perflevel1.logicalcpu` => `10 / 8 / 2`; 64 GB).
The load was 88-230 during the window (`uptime`, `sysctl -n vm.loadavg`). Nothing was killed,
signalled, typed or reconfigured. Scratch data is in `/tmp/ls09/` (ps samples, rapid snapshots, the
scripts listed in §8).

Tags: **[M]** measured (command named), **[E]** estimated (method named), **[H]** hypothesis.

---

## 0 · Answer in one paragraph

The load average on this Mac is mostly **runnable-but-starved background-band threads, not work
that is competing with sessions**. On Darwin the load average counts runnable threads only
(`sched_run_buckets[TH_BUCKET_RUN]`, xnu `osfmk/kern/sched_average.c`). At load ~200, **112-127 of
the 186-195 runnable threads (60-65%) sit in the background band (pri ≤ 4)** [M, §2]. On Apple
silicon that band runs only on the E-cores, and this box has 2. Most of those threads are Dia
renderer threads (46-71) and Spotlight `mdworker_shared` (20-24). In the default band (pri 21-31),
where every Claude session, tool call and hook runs, only **14-17 threads** are runnable on 8
P-cores. So the default band is barely contended. **The same 1-second micro-task took 1.03-1.66 s at
pri 31, 9.9-40 s at pri 20 (utility), and did not finish in 240 s at pri 4 (background)**, all three
rounds at load 188-231 [M, §3]. That is why "high load does not block more sessions" holds: sessions
run in a band the load figure barely describes. It is also why limit-recover stalls. **The
reconciler, its placer, its capacity probe and the move lane run at pri 20, because launchd jobs with
no `ProcessType` (and `Standard`) are clamped there** [M, §4]. The repo already measured the result:
"a nominal 5 s wait took 41-50 s" (`scripts/limit-recover/lr-reset-poller.sh:249-252`). Separately,
the CPU itself is saturated (0-0.2% idle, **sys 40-53%**). The kernel share comes from a fork/exec
storm of **280-1,410 process creations per second** [M, §1]. The largest removable self-inflicted
parts of it are duplicated deploy-live host suites, the per-tool-call hook chain and launchd
pollers. The largest non-removable part is session test gates (pytest `-n 6`, bats).

---

## 1 · Census

### 1.1 Process table: three samples, 20 s apart [M]

Command: `ps -axo pid,ppid,stat,pri,%cpu,etime,time,comm` ×3 → `/tmp/ls09/ps{1,2,3}.txt`.

| Sample (UTC) | load1 | procs | S | **Z** | R | sum %CPU (ps) |
|---|---|---|---|---|---|---|
| 04:19:42 | 87.96 | 1,610 | 1,421 | **112** | 74 | 565 |
| 04:20:02 | 87.06 | 1,609 | 1,422 | **115** | 72 | — |
| 04:20:22 | 94.22 | 1,618 | 1,384 | **125** | 108 | 866 |

Counts by command class (sample 1 / 3; %CPU is ps's decaying average) [M]:

| Class | count | %CPU s1 → s3 | Notes |
|---|---|---|---|
| `bash` | 265 / 267 | 99 → 17 | long-lived pollers plus transient tool, hook and test shells (§1.3) |
| `zsh` | 79-84 | ~2-4 | Bash-tool shells (`shell-snapshots`) and kitty window shells |
| `claude` / `claude.exe` | 35 + 4 | 87 → 43 | top shows 41 `claude.exe` (754 threads) |
| Dia `Browser Helper (Renderer)` | 35-36 | 99 → **471** | 2.4-2.6 GB RSS for the top two (`~/.reso/load.jsonl` top3) |
| Dia main + `Browser Helper` | 1 + 7 | 21-34 | |
| `WindowServer` | 1 | 68-88 | root, pri 79 |
| `SevenRooms OS` | 1 | 10-63 | operator app |
| `Python` / `python` | 36-38 / 6 | 13-25 | pytest workers, cc-await-ping helpers, lr_recon |
| `kitty` | 1 | 3-10 | pri 46, 33 threads |

`top -l 2 -o cpu` (04:21:12Z) [M]: `Processes: 1445 total, 88 running, 6404 threads`;
**`CPU usage: 47.7% user, 52.89% sys, 0.2% idle`**. Top CPU: WindowServer 71%, a Dia renderer 58%,
**kernel_task 39%** (727 threads), Dia 36%, `Browser Helper` 25%, **syspolicyd 17%**, SevenRooms
14%, kitty 12%, notifyd 8%, fseventsd 5%, opendirectoryd 4%. A second read at 04:25Z gave
`59.32% user, 40.67% sys, 0.0% idle`.

### 1.2 Zombies [M]

All 112-125 zombies have **108 parented to kitty pid 853** (`ps … | awk '$3 ~ /^Z/{print $2}' |
sort | uniq -c`). The rest are 8 + 3 under two `claude` processes and singles under `expect`, Pioneer
AutoLaunchers and short bash parents. kitty is still `0.48.2` (`kitty --version`), and
`/Applications/kitty.app.staged` is still present. This is the known 0.48.2 signal-fd bug
(kovidgoyal/kitty#10436; repo analysis `docs/research/load-root-cause-2026-10-17/H-kitty-zombies.md`).
**Zombies do not enter the load average.** They are never runnable. Their only cost is the bug they
indicate: this kitty drops SIGCHLD/SIGUSR1/SIGTERM. Whether that bug also explains the kitty
remote-control socket not answering within 10 s is **[H]**, not measured here.

### 1.3 Fork/exec rate: the storm [M]

Method: pid-counter delta (`sh -c 'echo $$'` 10 s apart; macOS allocates pids sequentially and wraps
at 99,999).

| Window (UTC) | pids / 10 s | per second | load1 |
|---|---|---|---|
| 04:21:32-04:22:12 (4 reads) | 11,510-14,102 | **1,150-1,410** | 117-125 |
| 04:35:55-04:36:26 (3 reads) | 2,806-3,417 | **280-340** | 178-196 |

The fork rate fell 4× while the load *rose*. **The load figure does not track the fork storm.** §2
explains why. The storm shows up in CPU instead: sys 40-53%, kernel_task 39%, syspolicyd 17% (it
checks each exec, per `load-reinvestigate-2026-10-17/FINDINGS.md:75`), and in VM counters over 10 s
(`vm_stat` delta): **308k translation faults/s, 52k COW faults/s, 61k zero-fill/s**, while
compressions, swapins and swapouts were **0/s** and pageins 809/s. **Memory is not the bottleneck
now**: `memory_pressure -Q` reports 72% free, and `vm.swapusage` is 2.67 of 4 GB used, with 0
swapouts in the window.

### 1.4 Who forks: young-process ancestry [M sample; shares E]

Method: 30 rapid `ps -axww -o pid,ppid,etime,args` snapshots 0.3 s apart. Each unique process aged
≤ 2 s was classified by the first matching ancestor class (`/tmp/ls09/an2.py`). Caveat: ps sampling
catches about 1 in 10 forks (1,058 seen versus ~11,000 created in the same ~10 s), and it is biased
toward processes that live longer, so the shares are indicative.

| Ancestor class | 04:20Z (n=1,058) | 04:37Z (n=719) | Real work or overhead |
|---|---|---|---|
| deploy-live host bats (`test-hermeticity-lint.bats`) | **23.6%** | 11.4% | **overhead: duplicated** (§5.2) |
| Claude Code hooks (`~/.claude/hooks/*`) | **18.1%** | 10.2% | overhead per tool call (§5.3) |
| pytest gates (b13 agent-context-sync `uv run pytest -n 6`, `install.sh` trees) | 14.0% | 14.9% | real session work |
| limit-recover (`lr-*`, `handoff-fire.sh`, `claude-accounts`) | 10.3% | 10.2% | control plane (needed) |
| launchd infra daemons (lead-supervisor, capacity-alarm, cc-reaper, cc-dispatch, registration-state, it2-kitty, …) | 9.0% | **20.2%** | overhead: polling (§5.4) |
| unattributed (parent already exited, or root daemon) | 8.4% | 18.9% | — |
| postland-verify / nightly bats | 6.9% | 2.8% | infra verification |
| other Bash-tool shells | 4.7% | 6.1% | real session work (includes this census's own `ps`) |
| macapp sweep (`scripts/macapp/sweep.sh`) | 2.7% | 4.0% | real session work |
| session helpers (`cc-await-ping` / crash-watchdog) | 0.1% | 0.1% | already event-driven (`cc-kqwait`) |

### 1.5 CPU attribution including reaped children [M]

Instrument: `/tmp/ls09/ru.py`. It is adapted from the repo's
`docs/research/load-reinvestigate-2026-10-17/rusage-attrib.py`: `proc_pid_rusage` flavor 2,
self plus reaped-children CPU delta, uid 501 only, grouped by the launchd-child root, with claude
subtrees split by direct-child kind. It catches the sub-second processes that `ps` and `top` miss.

| Group | run 1 (30 s, 04:23Z) | run 2 (45 s, 04:25Z) | of which sys |
|---|---|---|---|
| Claude sessions: Bash-tool shells (tests, gates, builds) | 234% (28.5%) | **321% (33.1%)** | ~50% sys |
| **Dia browser** (renderers) | 182% (22.2%) | **220% (22.6%)** | 28% |
| Claude sessions: reaped children of claude (finished hooks and tool shells) | 121% (14.8%) | 68% (6.9%) | ~40-55% sys |
| Claude binaries themselves | 72% (8.7%) | 104% (10.7%) | 15-23% |
| `deploy-live.sh` trees (host bats) | 47% (5.7%) | **138% (14.2%)** | 31-85% |
| `lead-supervisor.sh --daemon` | **63% (7.7%)** | 5% | 36% |
| SevenRooms OS | 22% | 18% | |
| autonomy-sweep / postland-verify / capacity-alarm / lr-reset-poller / crash-watchdogs | 1-18% each | | |
| Total attributed (uid 501) | 820% | 972% | |

Root-owned processes (not in `proc_pid_rusage` scope) come from `top`: WindowServer ~70-88%,
kernel_task ~39%, syspolicyd ~17%, notifyd ~8%.

---

## 2 · What the load number is made of: runnable threads by priority band [M]

Method: `/tmp/ls09/runq.sh`. Three samples ~25 s apart. Each sample takes `top -l 2 -stats pid,th,command`,
where `#TH` = total/running and running includes runnable, joined to `ps -o pid=,pri=` for the band.

| Sample | load1 | runnable threads (top) | **bg ≤4** | util 5-20 | default 21-31 | high >31 | exited mid-sample |
|---|---|---|---|---|---|---|---|
| 04:30:30Z | 207.5 | 186 | **113** | 14 | 14 | 30 | 15 |
| 04:30:56Z | 206.4 | 195 | **127** | 14 | 14 | 28 | 12 |
| 04:31:21Z | 199.9 | 194 | **112** | 11 | 17 | 37 | 17 |

Biggest contributors to runnable threads (sample 2): Dia `Browser Helper (Renderer)` @pri4 **61**,
`mdworker_shared` @pri4 **23**, Dia main @pri55 8, `Google Chrome` (agent-browser) @pri20 6 plus
helpers 8, `bash` @pri4 6, `gh` @pri4 4, `jq` @pri4 3, `mds_stores` 4, WindowServer 2. Dia plus
Spotlight held **89-100** runnable threads in every sample.

Why so many threads in the bottom band are runnable at once: on Apple silicon, background-QoS
threads run **only on E-cores** and cannot be promoted to P-cores
([Eclectic Light 2022](https://eclecticlight.co/2022/11/28/can-you-game-core-allocation-on-apple-silicon/),
[2025](https://eclecticlight.co/2025/05/09/what-is-quality-of-service-and-how-does-it-matter/)). A
cited xnu comment (`sched_amp_common.c`) extends that to utility as well, which is **[H]** for this
macOS build. This box has 2 E-cores [M, `hw.perflevel1.logicalcpu`]. So 110-130 bg threads queue on
2 cores, and each counts as one unit of load. **About 55-65% of the load average is a queue on 2
E-cores that sessions never compete in.**

On Darwin the load figure is runnable threads only:
`uint32_t nthreads = os_atomic_load(&sched_run_buckets[TH_BUCKET_RUN], relaxed) - 1;` in
[xnu osfmk/kern/sched_average.c](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/sched_average.c)
(WebFetch). Unlike Linux, uninterruptible waits are not counted, so "real work vs uninterruptible
waits" does not apply here. The split that matters is **by band**.

Historic shape [M, `~/.reso/load.jsonl` from `gl.reso.load-sampler`, 10-min means on 2026-10-20]:
load1 was 97-359 all night (peak means 302-359 at 02:40-03:00Z), and `ps`-R counts were 74-201. The
sampler (pri 20, nice 5) logged only 26-29 samples per 10 min at the peak, against 50-57 at load
~100-180. **The pri-20 sampler itself loses about half its ticks at the peak**, which shows the same
utility-band starvation.

---

## 3 · The decisive measurement: same task, three bands, at load 188-231 [M]

`/tmp/ls09/band.sh`: 100 × `/usr/bin/true` plus a 2M-iteration Python loop (~1 s of work). It runs in
the default band (this session's pri 31), under `taskpolicy -c utility` and under
`taskpolicy -c background`, with a 240 s bound (`/opt/homebrew/bin/timeout 240`).

| Round | default (pri 31) | utility (pri 20) | background (pri 4) | load1 |
|---|---|---|---|---|
| 1 | **1.03 s** | **39.96 s** | **> 240 s (TIMEOUT)** | 201-213 |
| 2 | **1.66 s** | **29.28 s** | **> 240 s (TIMEOUT)** | 188-231 |
| 3 | **1.10 s** | **9.87 s** | **> 240 s (TIMEOUT)** | 188-208 |

What this shows:
- **Default band is effectively uncontended** at load ~200: 1.0-1.7 s for ~1 s of work. That
  matches the operator's observation that high load per core has not blocked more activity.
- **Utility band is 9-39× slower.** A 30 s probe bound or a 120 s placer bound is therefore
  0.75-13 s and 3-13 s of default-band work respectively. Those are the observed `probe-error` and
  `place rc=124 cause=timeout` (§4).
- **Background band does not complete.** Anything on a limit-recover path under `taskpolicy -b`
  never finishes. `lr-reset-poller.sh:344-350` already recorded this for evidence-gc: "133 of them
  sat runnable for hours".

---

## 4 · Where the limit-recover control plane runs [M]

| Process | pri / nice | How it got there |
|---|---|---|
| `python -m lr_recon` (pids 38189 and, after restart, 51148) | **20 / 0** | `com.reso.lr-reconciler.plist` has **no `ProcessType`** (`plutil -convert json` → keys: Label, KeepAlive, ProgramArguments, …) |
| `claude-accounts --json` / `--place` children | 20 | inherited from the reconciler |
| `lr-reset-poller.sh` (move-lane starter) | 20 | `com.reso.lr-reset-poller` has no ProcessType; the repo documents it at `lr-reset-poller.sh:249-252` |
| `capacity-alarm.sh` | 20 / 10 | `ProcessType Standard`. **Standard = the same clamp as unset** |
| `lead-supervisor.sh`, `compressor-sentinel.sh`, `load-sampler.sh` | 20 | no ProcessType |
| `research-classifier-warm`, `voiceink.keepalive` | **31** | `ProcessType Interactive` |
| Hammerspoon keepalive | 37 | Interactive |
| All Claude sessions, Bash-tool shells and hooks | **31** | children of kitty → login shell |
| `com.reso.lr-move-kick` (staged Interactive starter) | **not loaded** | present only at `launchd/staged/com.reso.lr-move-kick.plist`; absent from `launchctl list` and `~/Library/LaunchAgents` |

Placer timeline in the incident window [M, `~/.reso/limit-recover/recon/events.jsonl`, `ev=place`,
02:36-04:25Z]: 19 placements. **9 hit `rc=124 cause=timeout` at 63-120 s.** That includes 04:18Z
and 04:20Z at load 84-89, so the timeouts are **not a high-load-only event**. Answered placements
took 18.7-106 s. Probe outcomes in the same window: `admit-refused` ×11, `probe-error` ×8.
`lr_recon/admit.py:58-66` runs the bash probe with `timeout=30`, and `admit.py:143-151` (`cpu_ok`)
gates on `load1/ncpu`. §2 shows that number is about 60% a 2-E-core background queue.

Conclusion for this axis: **the stalls follow the control plane's band, not the load**. A pri-20
process needs 9-39× wall time for its work, and pri 4 gets none. Session work sits at pri 31 and
still runs at near-uncontended speed. Raising the control plane's band does not require lower load.

---

## 5 · Real work vs self-inflicted overhead

### 5.1 Real, deliberate session work (keep; do not throttle)
- b13 agent-context-sync round-18 team: 6 sessions (`51b0c87a`, `c9838a66`, `b783f976`, `91e9856d`,
  `a2727d12`, `7f868d7e`) issued 89-218 Bash calls each from 02:00 to 04:00Z. They ran concurrent
  `uv run --locked pytest -q -p no:cacheprovider -n 6 tests/test_setup_report.py|test_cli.py` and
  two `scripts/gate.sh` at pri 31 (pids 79314 and 30225, 27-28 min old at 04:33Z)
  [M, `~/.claude/logs/bash-execution.log`, `ps`]. pytest calls per 10 min were 7-17 at 02:10-02:50Z,
  the same window as the load peak (means 276-359). The correlation is [M]; the causation is [E].
  The same class was the root cause on 2026-10-17 (`load-root-cause-2026-10-17/DESIGN.md:60-66`).
- Session Bash-tool subtrees in general: 234-321% CPU.
- Claude binaries: 72-104% CPU across ~41 processes.

### 5.2 Self-inflicted and removable at equal session count: duplicated deploy-live host phases [M]
Five `deploy-live.sh` trees were alive at 04:24Z (`ps -axww`):
- launchd `--auto` pid 19519;
- three **orphaned** (ppid 1) agent- or desk-fired runs: 2785 at 1h04m, 5969 at 35m and 11018 at 4m;
- one inside a session's tool shell, pid 28720.

Two of them were each running `timeout -k 10 3600 nice -n 19 bats tests/test-hermeticity-lint.bats`
(pids 44193 at 59 min and 87269 at 31 min). That is **the same read-only suite against the same live
layer, twice**. The script says so itself: "THIS SCRIPT HAS NO RUN LOCK … `deploy-now.sh` … can land
inside a running host phase … the overlap costs load, not correctness" (`scripts/deploy-live.sh:180-189`).
The host suite is sized at a 3600 s bound because it takes 1,399 s even at load 9-22
(`deploy-live.sh:160-179`). Cost: **47-138% CPU (6-14%) and 11-24% of young processes**. Note
`nice -n 19` does not demote it out of pri 20, the band the control plane uses (ps: `pri=20 ni=19`).

### 5.3 Self-inflicted per tool call: the hook chain [M config, E cost]
`~/.claude/settings.json` (symlinked into `.claude-secondary`/`-tertiary`; `ls -la`) fires per **Bash**
tool call: 11 PreToolUse (10 `Bash` + 1 `*` research-block), 8 PostToolUse (log-bash,
waiting-recycle, relay-verbatim, bash-output-offload, memory-index-drain, plus 3 match-all:
teammate-checkpoint, cc-permission-beacon, mailbox-drain) and 1 PostToolBatch. That is **~20 hook
processes per Bash call**. A Read/Grep call fires ~5. Every turn end fires **14 Stop hooks**, and
every prompt fires 7 UserPromptSubmit hooks (`jq -r '.hooks[$e][] | …'`). None is `async`. All run
at pri 31 in the session band, and each forks several `jq`/`sed`/`grep`/`git`. Share: 10-18% of
young processes [M, §1.4]. The 2026-10-17 estimate was 66-83 execs/s and under 5% CPU
(`DESIGN.md:89-91`).

### 5.4 Self-inflicted: launchd pollers [M]
- `lead-supervisor.sh --daemon` (30 s sweep, `scripts/lead-supervisor.sh:89`): 5-63% CPU, bursty, 36%
  sys in run 1.
- autonomy-sweep (300 s): up to 18%.
- capacity-alarm (60 s): 2-4%.
- session-search-sweep (60 s), cc-reaper (300 s), cc-dispatch (300 s), postland-verify (300 s,
  runs bats), registration-state, it2-kitty, assignee-pane-residency.

Together they are 9-20% of young processes. Per-session helpers are now near zero:
`cc-await-ping` (79 processes) waits on kqueue (`bin/cc-await-ping:837-850`, `cc-kqwait`), and the
32 `lead-crash-watchdog.sh` are one per live lead (2026-10-17 verdict).

### 5.5 Not session work, but the biggest share of the load number
- **Dia** (operator's browser): 182-220% CPU, 46-71 runnable bg threads, 2.4-2.6 GB RSS per top
  renderer.
- **Spotlight** (`mdworker_shared` ×27, `mds`, `mds_stores`): 20-30 runnable bg threads, ~5% CPU (uid
  501 part). The file churn from worktrees and test temp dirs is what feeds it [H].
- SevenRooms OS: 14-63%.
- agent-browser headless Chrome: 14-19 runnable threads at pri 20/47.

### 5.6 Shape: fork storm or CPU hogs?
**Both, and they show up in different meters.**
- **CPU**: half is short-lived processes, measured as kernel sys 40-53%, 280-1,410 forks/s, and
  reaped-children CPU 68-121%. The other half is a handful of long-lived hogs: Dia renderers ~2
  cores, WindowServer ~0.8, claude binaries ~1, pytest/xdist workers.
- **Load average**: dominated by long-lived **starved background threads** (Dia and Spotlight on 2
  E-cores), not by the fork storm. The fork rate fell 4× while the load rose (§1.3).

---

## 6 · Levers (none reduces the session count)

| # | Lever | Mechanism | Expected effect | Risk | Effort |
|---|---|---|---|---|---|
| L1 | **Run the LR control plane in the default band**: `ProcessType Interactive` on `com.reso.lr-reconciler` and `com.reso.lr-reset-poller`, and load the staged `com.reso.lr-move-kick` | Interactive → pri 31, measured on 3 loaded agents. Children inherit, so the placer, probe, handoff-fire, transplant and recycle all leave the 9-39× utility tax | Micro-task 10-40 s → 1.0-1.7 s [M]. The 30 s probe and 120 s placer bounds become ~10-30× headroom instead of timing out | Control plane CPU is ~1-3% (lr-reset-poller 2%, lr-fleet 1.1% [M ru.py]), so its competition with sessions is negligible. A runaway loop would cost a core at pri 31 rather than starve quietly. It is an operator-owned launchd edit, and needs a restart at a cohort boundary (see the bash-log note at 04:24Z about not restarting mid-cohort) | S |
| L2 | **Never put a limit-recover step under `taskpolicy -b`/`-c utility`** (audit, e.g. `scripts/lib/restore-heartbeat.sh:454` puts `cc-sessions --json` under utility in boot-resume) | utility = 9-39×, background = never [M §3] | Removes silent never-finishing steps | none for correctness | S |
| L3 | **Replace `load1/ncpu` as the CPU signal** in `admit.py:cpu_ok`, the idle-lane "20/core recycle bound" and the placer with a default-band contention metric: count of runnable threads at pri ≥ 21 (top `#TH` × ps pri), or the wall time of a fixed 50 ms probe at pri 31 | 55-65% of load1 is a 2-E-core bg queue that never competes with pri-31 work [M §2] | Default-band runnable was 14-17 on 8 P-cores at load ~200, i.e. "admit" | A new signal needs its own threshold, derived rather than guessed (`gc-cpu-vs-session-ceiling` lesson) | M |
| L4 | **Single-flight deploy-live's host phase**: lock keyed by live HEAD, so a second deploy-live skips host_checks while one is running | The same read-only `test-hermeticity-lint.bats` ran twice concurrently (59 m and 31 m) | −47-138% CPU (6-14%), −11-24% of young processes [M] | One run's verdict covers both. No safety loss: host_checks never rolls back (`deploy-live.sh:98-100`) | S-M |
| L5 | **Hook chain**: mark side-effect-only PostToolUse/Stop hooks `async` where the contract allows. Merge the 3 match-all PostToolUse hooks and log-bash/relay-verbatim/bash-output-offload into one dispatcher process | ~20 processes per Bash call and 14 per turn end, all pri 31 | 10-18% of young processes, less sys time [E] | Some hooks must stay synchronous (gates, rewrites). Each merge needs a parity test | M |
| L6 | **lead-supervisor sweep**: event-driven (WatchPaths on the registry) or a longer `SUPERVISOR_SWEEP` | 30 s sweep bursts to 0.6 core, 36% sys | −0.05-0.6 core [M range] | Slower detection of a stall | S |
| L7 | **Spotlight exclusions** for `~/Development/.worktrees`, `~/.reso`, `~/.claude*/projects`, test TMPDIRs (operator, System Settings → Spotlight → Privacy) | mdworker 20-30 runnable bg threads, fed by test file churn [H] | −20-30 load units. Little CPU | Loses Spotlight search in those trees | S |
| L8 | **Dia**: discard or close heavy background tabs when the box runs unattended (operator) | 46-71 runnable bg threads, ~2 cores | −50-70 load units and ~2 cores, mostly on E-cores | The operator's own browser; not session work | S |
| L9 | **kitty 0.48.2 → patched or 0.49.x** at the next planned restart (already staged) | 108 zombies, signals dropped | 0 load. May help RC-socket reliability [H] | A kitty restart moves every pane (operator-planned) | S |

L1-L3 address the operator's premise directly. They let recovery run *at* load 200-400 instead of
waiting for it to drop, and they cost no session capacity. L4-L6 remove waste. L7-L8 shrink a load
figure that mostly measures nothing sessions compete for. Under L3 that figure would not matter
anyway.

---

## 7 · Open questions
1. Does `ProcessType Interactive` also lift the threads' QoS clamp, or only the base priority? In
   other words, does `lr_recon` then run on P-cores? Check after the change with the §3 micro-task
   started *from* the job (log `ps -o pri=` plus wall time). That is the `MOVE-KICK pri` line
   `lr-reset-poller.sh:256` already logs.
2. Is the utility band E-core-only on this macOS 15 build (the cited `sched_amp_common.c` comment), or
   just lower priority on P-cores? The 9-39× spread across rounds suggests it shares the E-core
   queue part of the time [H].
3. What makes the placer slow even at load 84-89 (04:18 and 04:20Z timeouts at 63-66 s)? It may be
   network-bound or process-walk-bound, not CPU-bound. That is placer-axis territory; it was not
   profiled here.
4. Which hooks dominate fork count per call? This pass did not run hooks (read-only). A per-hook
   `/usr/bin/time -l` fixture run in a scratch HOME would rank them.
5. How much of the 40-53% sys time is exec-provenance checking (syspolicyd 17%) versus fork/COW
   faults? Splitting it would need `eslogger` or `sudo` (root), which was out of scope.

## 8 · Reproduce (all read-only)
- `/tmp/ls09/ps{1,2,3}.txt`: ps samples. `/tmp/ls09/fast.txt` and `fast2.txt`: rapid snapshots.
  `an.py` / `an2.py`: young-process classification.
- `/tmp/ls09/ru.py 30|45`: rusage attribution, outputs `ru1.txt` and `ru2.txt`.
- `/tmp/ls09/runq.sh`: runnable threads by band. `/tmp/ls09/band.sh` → `band.out`: the three-band timing.
- Fork rate: `a=$(sh -c 'echo $$'); sleep 10; b=$(sh -c 'echo $$'); echo $(( (b-a+99999)%99999 ))`.

---

## Skeptic review

Adversarial re-check, 2026-10-20 04:46-05:00Z, at load 184-232 (`uptime`). It was read-only:
nothing was killed, typed, loaded or edited. The new scratch files are in `/tmp/skep09/`:
`band2.sh` → `band2.out`, `thr.sh` (per-thread census), and `fork.sh`. Tags as above: [M] measured
(command named), [E] estimated (method named), [H] hypothesis.

### New measurements the verdicts rest on

**R1. The band timing, re-run with CPU time** (`/tmp/skep09/band2.sh`, the same micro-task under
`/usr/bin/time -p`) [M]:

| Round | default (pri 31): wall / user+sys | utility (pri 20): wall / user+sys | background (pri 4) |
|---|---|---|---|
| 1 | 1.12 s / 0.49 s | 49.99 s / 0.45 s | > 150 s (TIMEOUT) |
| 2 | 1.00 s / 0.41 s | 33.53 s / 0.47 s | > 150 s (TIMEOUT) |
| 3 | 0.87 s / 0.43 s | 30.06 s / 0.45 s | > 150 s (TIMEOUT) |

Separately, `taskpolicy -c background /bin/sh -c 'ps -o pri= -p $$'` did not return within 60 s [M].
The task is **~0.45 s of CPU, not "~1 s of work"**. The default band therefore runs it at
**2.0-2.4× stretch**: fast, but not "uncontended". Utility runs it at 67-111× its CPU time, which is
34-45× the default band's wall time. Utility's CPU time matches default's (0.45 vs 0.43 s). That is
weak evidence the utility work ran on P-cores rather than slower E-cores [E: an E-core would need
more CPU-seconds for the same work], which fits Eclectic Light 2025: utility "will be preferentially
run on P cores … when they're all fully occupied, macOS will run them on E cores"
([URL](https://eclecticlight.co/2025/05/09/what-is-quality-of-service-and-how-does-it-matter/),
WebFetch). This answers open question 2: utility is starved by priority, not confined to the E-cores.

**R2. A per-thread band census.** §2's method joins each process's runnable-thread count to ps's
*process-level* `pri`. That misfiles threads. Dia main (pid 1037) has a process `pri` of 55, but its
**13 runnable threads are all at 4T** (`ps -M -p 1037` => `13 R 4T`, `39 S 37T`, `18 S 31T`). Daemons
flip too: cfprefsd and trustd show pri 31 in `/tmp/ls09/pri.2` but 4 now (`ps -o pid,pri -p 635,797`).
Per thread (`/tmp/skep09/thr.sh`, `ps -AM` with each thread's own STAT and PRI, 3 samples
04:56:28-04:56:50Z, load 207-210) [M]:

| Sample | runnable | bg ≤4 | util 5-20 | default 21-31 | high >31 |
|---|---|---|---|---|---|
| 1 | 176 | **129 (73%)** | 31 | 15 | 1 |
| 2 | 212 | **154 (73%)** | 38 | 18 | 2 |
| 3 | 205 | **162 (79%)** | 30 | 11 | 2 |

Dia renderers contributed 40/44/67 runnable bg threads, Dia main 13 and Dia `Browser Helper` 6-7.
The process-level "high 28-37" band is an artifact of the method; per thread it holds 1-2. The
headline therefore gets *stronger* (73-79% bg rather than 60-65%), and default-band contention is
11-18 runnable threads on 10 cores. That is consistent with R1's 2× stretch. Utility is 30-38
runnable, not 11-14. The utility band includes a transient `kitten` remote-control client at 20T
(pid 55738, `R`, in `/tmp/skep09/thr.2`). So kitty RC clients started from pri-20 daemons pay the
utility tax before they ever reach kitty's socket. Whether that explains the 10 s "terminal did not
answer" verdicts is [H] (its parent had exited before it could be read).

**R3. Session work is not uniformly at pri 31.** `hooks/qos-rewrite.sh` (PreToolUse Bash) prefixes
simple agent commands matching `hooks/config/qos-batch.patterns` with `taskpolicy -c utility`. The
patterns cover `(uv run) pytest`, `shellcheck`, `npm install|ci`, `du -s`, `ffmpeg`, `magick`,
`tesseract` and `agent-browser`. `~/.claude/bin/bats` → `bin/cc-bats` demotes bats. Live: the
deploy-live bats pid 87272 is `pri 20 ni 19` under a pri-31 `timeout` parent (`ps -axo …`). The
repo's own calibration says `nice` alone leaves pri at 31 (`darwin-qos-band-mechanics` memory note),
so the 20 comes from cc-bats, not from `nice -n 19`. The b13 pytest calls are compound (`;`, `&&`,
`|` in `~/.claude/logs/bash-execution.log`), and qos-rewrite rewrites simple commands only, so
§5.1's "pri 31" holds for them. Demoted session batch work, however, shares the utility band with
the LR control plane.

### Verdicts on findings

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| F1 | Load is mostly starved background-band threads; the default band is barely contended | **CONFIRMED** (method flawed, conclusion stronger) | R2: per-thread bg share is 73-79%, default band 11-18 runnable. §2's process-level join mislabels threads (Dia main's 13 pri-4 runnable threads counted as pri 55; "high 28-37" is 1-2 per thread). Recount of `/tmp/ls09/topth.*` gives Dia-renderer bg 49/61/46, so the "71" upper bound is not reproduced. "Barely contended" overstates it: default runs at 2.0-2.4× stretch (R1). |
| F2 | Same task: default 1.0-1.7 s, utility 10-40 s, background >240 s | **CONFIRMED** | R1 reproduces it at load 189-232: default 0.87-1.12 s, utility 30-50 s, background >150 s ×3, plus a bare `ps` under `-c background` that did not finish in 60 s. Live corroboration: `stat -f …` pid 55337 at pri 4 had been `RN` for 6:39 under a 6h51m pri-4 `find` (`ps -o … -p 65507`). The work unit is ~0.45 CPU-s, not ~1 s. |
| F3 | LR control plane at pri 20 (no ProcessType / Standard); this explains probe-error and placer timeouts | **CONFIRMED**, with two corrections | `ps`: lr_recon 51148 pri 20 (`ps -M` all threads 20T), lr-reset-poller 55309/65409/96509 pri 20, capacity-alarm (`ProcessType Standard`) pri 20 ni 10. Plists for lr-reconciler and lr-reset-poller have no ProcessType (`plutil`). Interactive voiceink keepalive `open` pid 1409 runs at pri 31. lr-move-kick is absent from `~/Library/LaunchAgents`, and the staged plist is Interactive with WatchPaths on `move/requests`. `lr-reset-poller.sh:252` (main checkout 20368fc85; line numbers in this review are from that checkout) records the 41-50 s figure. `admit.py:59-66` (now) itself blames "the 30 s bound firing on a demoted child". **Correction 1:** the 04:18 and 04:20Z timeouts were against a *load-scaled* bound of 63-66 s (`plan.py:312-318`: 30 s × load1/40), not 120 s. Counting `ev=place` from 02:36 to 04:25Z gives 8 of 19 rc=124 (9 of 23 through 04:41Z), not 9 of 19. Answered durations of 14-106 s do not track load (14.3 s at load 198, 85.2 s at 158). Band-not-load is consistent with that, but the placer's own work was not profiled. **Correction 2:** "sessions, tool shells and hooks at pri 31" is not universal (R3). |
| F4 | CPU saturated (0-0.2% idle), sys 40-53%, fork storm 280-1,410/s that load does not track; memory not the bottleneck | **CONFIRMED** | `/tmp/skep09/fork.sh`: 9,371-10,119 pids per 10 s at load 184-186. `top -l 2`: 58.36 user / 41.63 sys / 0.0 idle. Recomputed from `/tmp/ls09/vm1`/`vm2`: 3,083,441 translation faults per 10 s (308k/s) and 52k COW/s. `memory_pressure -Q` => 69% free. Load tracking was only weakly testable (3 windows), but R2's bg-dominated census explains the decoupling. |
| F5 | CPU attribution incl. reaped children (Bash-tool 28-33%, Dia 22-23%, deploy-live 6-14%, lead-supervisor 1-8%, …) | **WEAKENED** | `ru2.txt` attributes 972% to uid 501 alone. Adding the doc's own root figures (WindowServer 70-88%, kernel_task 39%, syspolicyd 17%, notifyd 8%) gives 1,106-1,124% on a 1,000% box [E: arithmetic]. flavor-2 reaped-child time credits a child's *whole lifetime* CPU at reap time, including CPU spent before the window. Groups that reap long children (deploy-live 138%, lead-supervisor 63%, "reaped children of claude") are the likeliest to be inflated. Read the ranking as indicative, not as shares. |
| F6 | Duplicated deploy-live host phases (two concurrent hermeticity bats, orphan trees, no run lock) | **CONFIRMED** (the duplication); its cost is overstated | `/tmp/ls09/tree.txt`: 44190→44193 under 2785 (ppid 1, started ~03:20Z) and 87265→87269 under 5969 (ppid 1, started ~03:49Z). `deploy-live.sh:180-189` says "NO RUN LOCK". 5969/87269 is still alive at 59 min, its `--selftest` `RN` at pri 20 for 12 min (`ps`). The deploy-live plist has **no ProcessType** (Nice 10, LowPriorityIO), so `deploy-live.sh:161`'s "ProcessType Background (PRI 4)" comment is stale: `--auto` pid 61795 runs at pri 20 ni 10. The "6-14% CPU / 11-24% of young processes" is the whole deploy-live class, not the duplicate (see L4). |
| F7 | ~20 synchronous hook processes per Bash call, 14 per turn end, none async | **CONFIRMED** (count); share medium | `jq` over `~/.claude/settings.json` (all 4 config dirs symlink it): PreToolUse `*`(1)+`Bash`(10)=11; PostToolUse match-all(3)+`^Bash$`(1)+`Bash`(3)+`Bash\|Write\|Edit\|MultiEdit`(1)=8; PostToolBatch 1; Stop 1+13=14; UserPromptSubmit 7. `async` is false on every one of these (only SessionStart has async entries). The 10-18% share comes from a 1-in-10 ps sample and was not re-measured. |
| F8 | Zombies (108 under kitty 0.48.2) add no load; #10436 fix staged, not applied | **CONFIRMED** | Now 111 under 853 (`ps -axo stat=,ppid=`). `kitty --version` => 0.48.2. `/Applications/kitty.app.staged` exists. `H-kitty-zombies.md:7,32` cites #10436 / f3fdc21850d7. Zombies are not threads, so they are not in `sched_run_buckets`. |
| F9 | The 02:20-03:10Z peak coincided with the b13 team's concurrent pytest/gate.sh; "real work" | **WEAKENED** | The pytest counts are reproduced: 17/14/15/7/12 per 10 min at 02:10-02:50Z (`grep … bash-execution.log`). Equal peaks occur without that work, though. Recomputed from `~/.reso/load.jsonl`: 04:00Z mean **314** (max 396) with 4 test-gate commands, and 00:40Z mean 267 with 3. Correlation over one window does not establish the peak's cause (repo lesson `aggregate-correlation-refutes-the-obvious-cause`). The sampler's tick loss is confirmed (n=26-29 at 02:30-03:00Z), but n=28-29 also at 00:30-00:40Z. |

### Verdicts on levers, under permanent load of 15-40/core

| # | Lever | Verdict | Why |
|---|---|---|---|
| L1 | ProcessType Interactive on lr-reconciler + lr-reset-poller; load lr-move-kick | **CONFIRMED** (the strongest lever; still needs verification under load) | It does not depend on the load falling. R1 gives pri 31 34-45× the throughput of pri 20 at load ~200, and the default band is timeshared fairly with sessions instead of starved. The repo's ratchet note says a utility-clamped parent cannot spawn a pri-31 child, so the change must be at the launchd job. A live Interactive LaunchAgent child runs at pri 31 (voiceink `open` pid 1409). It probably also removes the utility tax on `kitten @` RC clients (R2) [H]. **Caveats:** (a) the expected "1.0-1.7 s" is a 2× stretch that grows with default-band session count, so headroom is relative, not absolute; (b) `lr-move-batch.sh:335-339` deliberately re-clamps the switch-census to utility (19-27 CPU-s per its comment → ~21-50 min at R1's 67-111× [E]), so L1 alone does not lift that step (see L2); (c) loading or editing a LaunchAgent is an operator act, and open question 1 can only be closed by the `MOVE-KICK pri` line (`lr-reset-poller.sh:260`) from a real run, per the "verify a cure under its load" lesson. |
| L2 | Never run an LR step under `taskpolicy -b` / `-c utility` | **CONFIRMED**, wrong example | Background never completes (R1: 3× >150 s, plus a bare `ps` >60 s). The cited example, `restore-heartbeat.sh:454`, is the boot-resume census, **not an LR step**. The live LR instance is `lr-move-batch.sh:338-339` (`snap_tp=(taskpolicy -c utility)` around `--switch-census`), which the doc missed. evidence-gc (`lr-reset-poller.sh:373`) is off the critical path. Trade-off: the census's 19-27 CPU-s would then compete at pri 31, which is small next to sessions [E]. |
| L3 | Replace load1/ncpu with a default-band contention signal | **WEAKENED** | The direction is right: load1 is 73-79% pri-4 threads (R2). **But (a)** the metric as specified ("top #TH × ps pri") is the process-level join R2 shows misfiles threads, so it needs `ps -AM` per thread (~5,800 lines per pass), and that walk run at pri 20 is itself taxed. **(b)** The admission CPU brake caused only **2 of 11** refusals since 02:30Z; 8 were `probe-error` (`events.jsonl` ev=admit-refused), and `cpu_ok` already has a 20 s anti-starvation floor (`admit.py:42,150-157`). The gain on admission is therefore small; the real targets are the idle-lane gate (`lr-move-worker.sh:335-349`, `HF_PRECHECK_LOAD_PER_CORE` 20) and the load-scaled placer bound (`plan.py:312-318`). **(c)** The "pri-31 probe wall time" variant measures the right thing but only after L1. Under the operator premise, deleting the load term may beat re-deriving a threshold. |
| L4 | Single-flight deploy-live host_checks, keyed by live HEAD | **WEAKENED** | The two duplicate runs started ~03:20Z and ~03:49Z (`tree.txt` etime), on either side of main commits 31f4242e0 (03:13Z) and e6bbd0465 (03:41Z) (`git log main`). They were very likely **different HEADs**, so a HEAD-keyed lock would not have deduped them [E]. An any-HEAD "skip or supersede while one runs" lock would. The savings are overstated: 47-138% is the whole deploy-live class, of which only the overlapping half is duplicate, and 138% comes from the over-attributed run (F5). Relevance to LR: the host bats run at pri 20 (cc-bats), the LR plane's band today, and become irrelevant to LR once L1 lands. |
| L5 | Async-ify + merge hooks | **WEAKENED** | `async` changes turn latency, not process creation or CPU: the same processes still fork. Only the merge cuts execs. The 10-18% share is from a 1-in-10 ps sample (F7). It does nothing for LR reliability; at most it frees CPU for sessions. |
| L6 | lead-supervisor event-driven / longer sweep | **WEAKENED** | `lead-supervisor.sh:89` `SWEEP=30` is confirmed. The 63% is one 30 s run (5% in the next) from reaped-child accounting that can include pre-window CPU (F5). The saving is small and uncertain, and does not touch LR. |
| L7 | Spotlight exclusions + discard Dia background tabs (operator) | **WEAKENED** | The mechanism holds: Dia threads are 59-87 of the runnable bg threads per thread (R2). mdworker did not appear among R2's contributors (mds_stores 3-4), so the Spotlight share varies over time. The effect is cosmetic for LR: it shrinks load1 (~200 → ~120-140 [E]), which would clear the 20/core idle-lane gate today but never the 2.5/core brake. The operator's premise is that sessions refill the box, so this does not make recovery reliable; L1+L3 do. It is safe, but operator-owned. |

### What the doc missed and the levers should carry
1. **LR is in the same band as demoted session batch work.** qos-rewrite and cc-bats push agent
   pytest, bats, npm, shellcheck and agent-browser into utility (R3), next to the reconciler. So the
   LR plane's tax grows with session count even if bg-band load does not. That is one more reason
   L1, not load reduction, is the fix.
2. **kitty RC clients inherit their caller's band.** A pri-20 caller's `kitten @` is taxed at
   34-45× (R1, R2). `HELD:pane:resolver-unavailable` and "terminal did not answer" may be partly
   client-side starvation rather than kitty itself [H]. Test: time `kitten @ ls` from pri 31 versus
   `taskpolicy -c utility` at the same load (read-only).
3. kitty pid 853 holds 3 threads `R` at 4T with ~0 CPU time across 3 reads (`ps -M -p 853`). They
   are starved, but its main threads (47T, 31T) are asleep, so RC service is probably not blocked
   there [H].
