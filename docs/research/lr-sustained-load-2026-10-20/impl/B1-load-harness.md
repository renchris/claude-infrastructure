# B1 · Load harness and the §5 guarantee tests: implementation design

Item `B1-load-harness` from `REPORT.md` §4(b) (`REPORT.md:289-292`), §5 (`REPORT.md:423-499`) and §6 (`REPORT.md:511`).
I did this research read-only on 2026-10-20 between about 17:35Z and 18:05Z, at worktree HEAD `28b25a119`. I edited no code, typed into no pane, ran no launchctl and signalled no system process. The only things I started were short probe processes under `/tmp/b1-probe/`, described in §2.

**Labels.** *M* means measured, with the command named. *E* means estimated, with the method named. *H* means a hypothesis. Code citations are `path:line` at `28b25a119`.

**Verdict: BUILD. Conviction 75%.** An agent can build and run this end to end. Every file it adds or changes is under `tests/`, plus one hermetic unit test under `scripts/limit-recover/lr_recon/tests/`. No launchd job and no operator act is needed to pin the bands. Four questions go to the operator (§15). None of them blocks the build: each has a safe default.

---

## 0. Answer

1. **Two tiers, because there are two different things to prove.**
   - The *logical* half needs no load to show. No decision may read the load average (G1). Our own timeout is never a verdict (G2). Pacing runs on the wall clock (G3). A restart is neutral (G6). A virtual-clock replay of the real `run_pass` proves these in seconds, in the land gate, at any priority.
   - The *physical* half can only be shown on a live box: priority band and contention. It needs the real daemon, real actuators, real `ps` and kitty, and the real band mix. That is the live harness, built on the W5 rig and run on demand.
2. **Bands are pinned without launchd.**
   - The cure arm inherits the caller's band. A session's Bash tool reads base priority 31 (M), the same 31/63 a `ProcessType Interactive` job gets (axis 04 R0.3).
   - The red arm puts `/usr/sbin/taskpolicy -c utility` in front of the detached supervisor. That gives a hard 20/20, identical to a launchd job with no ProcessType (axis 04 R0.3/R0.4).
   - Both are read back with `proc_pidinfo`: the daemon, every sampled child, and kitty.
   - The harness refuses a cure arm whenever its own base priority is below 31, for example when started under `cc-bats`, which clamps to utility (`bin/cc-bats:752`).
3. **The load generator is one process started at 31 whose worker threads demote themselves.**
   - Each worker thread demotes itself to the background band (base 4, E-cores only) or to utility QoS (base 20), or stays at 31 with a duty cycle.
   - The threads spin in `hashlib`, which releases the GIL, so they are truly parallel.
   - Measured: the threads read `(4, runnable)×4`, `(20, runnable)×4` and `(31, runnable)×6`, and the self-demoted processes stopped on time.
   - The obvious design fails. A python started under `taskpolicy -c background` had used 0.02 CPU-s after more than 3 min, still starting (M).
   - On this box the ambient load is already 15-40 per core by design, so the generator only *tops up*. It never waits for load to change.
4. **What is measured.**
   - Per member and per lane: `t0` (the later of death and request) → detect → first attempt → each later attempt → engaged.
   - Sources are on-disk records, actlog birth times and `events.jsonl`.
   - Beside every reading, every 5-15 s: load1, a runnable-thread census by base priority, the daemon's band, the children's band and kitty's band.
5. **Thresholds come in three kinds.**
   - *Hard* assertions must hold today: band, load present, zero `HELD:load`, zero IMPOSSIBLE for a soft reason, every non-held member ENGAGED by `T_done`, no double typer.
   - *Target* assertions are the §5 bound terms. Each is owned by an unbuilt item (B2, B3, A6) and becomes hard when that item lands.
   - *Power*: some assertion the cure arm passes must fail in the red arm, or the pair is `SIGNAL-DEAD`.
6. **Measured cost on the live box is small.**
   - The rig is a few CPU-s per attempt.
   - The census costs 0.26-0.54 s per read (M).
   - The two constrained budgets are kitty's file descriptors (125 now) and kitty's coalition process count (482 now, against warn 500 and alarm 700, M). The preflight checks both.
   - Default-band top-up competes with sessions, so it is off unless the operator allows it.
7. **A precondition, found while reading.** The rig's fake `claude` ignores the positional prompt that the relaunchers now pass on argv. That leaves fallback C believing the prompt was delivered, so the rig most likely stalls at HEAD (H, strong; §2 M10). Fixing the stub is step 1, and its red-proof is the first control.

---

## 1. What B1 proves, and what it cannot

| Property (§5) | Shown by | Why there |
|---|---|---|
| G latency bound per member | live harness (target until B2/B3); sim covers the admission/dispatch part | it depends on `P_max` and `T_att`, which are physical |
| G1 no decision reads load | sim (load invariance of the full decision trace) + static lint | logical; must not depend on the box's load to be detected |
| G2 our timeout is never a verdict | sim (placer rc 124, probe timeout) + existing `test_classify.py`, `handoff-remote-pane-term.bats` + live (kitty-delay fault) | both |
| G3 wall-clock pacing, pass ≤ `P_max` | sim (pacing); live (`band.log` pass gaps) | both |
| G4 band ≥ 31 for the daemon and every child | live harness readback; existing `test_band.py` | physical |
| G5 no giving up for a soft reason | live (H4, H5); sim (S4) | both |
| G6 restart-neutral | live (`kill9_post_transplant` fault, target: A6); sim (S5) | both |

**Out of reach of a fake `claude`.**
- Real boots and the API. A real boot measured 7-13 s (`REPORT.md:166`). A fresh boot plus first turn took 46 s median and 212 s p90 at 30-40/core (`gap-4…:45-50`). The stub can only burn a calibrated number of CPU-seconds at band 31.
- The real `--place` corpus cost. B4 needs its own benchmark; the fake placer burns a fixed CPU cost (§9.3).
- The credential flip (C1).
- Routing policy (D1, D2).
- Claude Code's messaging socket (C2). C2 must add a stub socket to use this harness.

---

## 2. New measurements taken for this design

| # | What | Command | Result |
|---|---|---|---|
| M1 | Band of a Bash-tool shell in a session | `python3 -I scripts/limit-recover/lr_recon/band.py $$` | **31**; `ps -o pri= -p $$` read 30, the decayed current priority |
| M2 | Load and topology | `sysctl -n vm.loadavg hw.ncpu hw.perflevel0.logicalcpu hw.perflevel1.logicalcpu` | 278.67 (27.9/core) at 17:40:14Z, then 152.63 about 10 min later; 10 = 8 P + 2 E cores |
| M3 | Runnable threads by base priority | `/usr/bin/python3 -I /tmp/skeptic-04/census.py` ×3 (axis 04's read-only census) | load1 273: base 4 153-156 · base 20 11-12 · **base 31 33-45** · base 47 0-1; 0.26-0.54 s real per read |
| M4 | Python start under a clamp | `taskpolicy -c background\|utility /usr/bin/python3 -I /tmp/b1-probe/spin.py 6 6`, read 3 s later by `runq.py <pid>`; then `ps -o pri,etime,time` | background: one thread `(4, runnable)`, and after 3 min 16 s still **0.02 CPU-s**, in interpreter start-up. It exited much later; I did not signal it. Utility: at 3 s one thread `(20, state 4)`, worker threads not yet started. Matches axis 09 R1 (>150 s at background) |
| M5 | Spinner threads that set their own band, in a process started at 31 | `/usr/bin/python3 -I /tmp/b1-probe/spin2.py 4 6 bg` (`setpriority(PRIO_DARWIN_THREAD, 0, PRIO_DARWIN_BG)` per thread), `spin3.py 4 5` (`pthread_set_qos_class_self_np(QOS_CLASS_UTILITY)`), and a plain `spin.py 6 4` at 31, each read by `runq.py <pid>` (`proc_pidinfo` THREADINFO) | `{(31,waiting):1, (4,runnable):4}` · `{(31,waiting):1, (20,runnable):4}` · `{(31,waiting):1, (31,runnable):6}`. So `hashlib` releases the GIL: all workers are runnable at once in every band. **The two self-demoted processes exited on their own wall-clock stop** within 30 s |
| M6 | The production rail at 31, pass interval | python read of `~/.reso/limit-recover/recon/band.log` | 3,866 lines over 10.52 h, **all `pri=31`**; pass + wait gap p50 10 s · p90 13 s · p99 19 s · max 193 s. The incident's band-20 passes were 4.9-13.6 *min* (`REPORT.md:89`) |
| M7 | Does priority 31 escape `ps` stalls? | `events.jsonl` rows `ev=abstain` with t ≥ 07:23Z | **4** abstains in 10.5 h, "`/bin/ps …: timed out at 30-37s`" (07:40, 08:19, 08:30, 11:06Z). So 31 does not fully escape the kernel-side `ps` stall (`REPORT.md:155`) |
| M8 | Recovery evidence at 31 in production | `events.jsonl` since 07:23Z | 2 `spawn` (both C, 07:23:17Z), 0 limit cohorts. **Production has almost no attempt data at 31.** The harness is the only near-term source |
| M9 | Main kitty | `ps -o pid,pri,etime,comm -p 853`; `band.py 853`; `lsof -p 853` numeric fds | PRI 47 main thread, task base 31; **125 numeric fds** (57 PIPE, 35 CHR, 31 REG, 2 unix). `launchctl limit maxfiles` soft 256 (kitty's own limit is unverified, H). A second kitty (`kitty-pr3`, pid 41475) reads **base 4**, App-Napped (H), and `pgrep -x kitty` finds it first |
| M10 | Stub vs argv prompt | read `tests/rig/stub-claude.py:602-626`, `scripts/limit-recover/lr-fire-resume.sh:1734-1736`, `bin/reso-resume-one:942` | both relaunchers spawn `… --resume $sid {*}$xargs {*}$prompt`. The stub runs `resume(a[a.index("--resume") + 1])` (`:615-616`) and drops the prompt. `a8ebaa7c0` makes fallback C treat an argv prompt as delivered. `git log -- tests/rig` last touched 10-07. **H (strong): a rig run at HEAD leaves argv-relaunched members unengaged** |
| M11 | Coalition and memory headroom | last row of `~/.claude/logs/capacity-alarm.jsonl` | `coal_true_procs` 482 (warn 500, alarm 700, `scripts/capacity-alarm.sh:341-342`); headroom 25.58 GB; segments 11.1%; verdict ALARM from the load rung alone (23.5/core vs 2.5) |
| M12 | Production switches | `ls -la ~/.reso/limit-recover/{autorecover.on,recon.on,recon/autorecover.on}`; `cat recon/mode` | **`recon/autorecover.on` exists since 2026-10-20 12:10 local**, so census and hook records are no longer plan-only. `recon.on` exists; mode `act` |

**M12 matters beyond B1.** The plan-only premise of A7 (`REPORT.md:176`) has changed on the live box. The harness mirrors the production switches (§6.3) so that it measures the configuration that is actually live.

---

## 3. Architecture

```
Tier G — land gate (hermetic, seconds, any band, no kitty, virtual clock)
  scripts/limit-recover/lr_recon/tests/test_guarantee_sim.py   real run_pass, mocked children, FakeTime
  tests/lr-recon-guarantee-sim.bats                            runs it (the gate runs bats)
  tests/lr-guarantee-g1-lint.bats + tests/rig/g1-allow.tsv     static G1 lint, stale-entry check
  tests/lr-load-harness-lib.bats                               load_lib verdict logic on fixture runs; loadgen demotion
  tests/rig-stub.bats (+cases)                                 stub argv prompt and the new fault knobs

Tier L — live harness (on demand, from a band-31 context, 15-60 min)
  tests/rig/lr-load-harness.sh   driver: preflight · lock · mirror · arms · generator · sampler · collect · verdict
   ├─ tests/rig/lr-recon-rig.sh  ×2 concurrent arms (cure /tmp/lrh-<id>-cure, red /tmp/lrh-<id>-red)
   │    └─ supervisor (detach) [taskpolicy -c utility for red] → python3 -m lr_recon → real actuators
   ├─ tests/rig/loadgen.py       one process at 31; threads self-demote to 4 / 20 or duty-cycle at 31
   ├─ tests/rig/load_lib.py sample   every 5 s: daemon/children/kitty base; every 15 s: runq census
   └─ tests/rig/load_lib.py collect|assert|pair|analyze
  shared readers: tests/rig/runq.py (ctypes proc_pidinfo/proc_pid_rusage; B6 may lift it)
```

**Why both arms run concurrently.** The research's band evidence came from same-moment interleaved A/B runs (`REPORT.md:109`), because sequential arms on this box see different load (M2: 278 then 153 within 10 min). Concurrency also halves wall time.

The cost is small. The red arm runs at 20 and competes only with utility-band work. The cure arm's rig work is a few CPU-s per attempt (§13). The two arms are isolated by HOME, by the `rig:true` registry rule (`observe.py:576`), by per-arm window titles, and by a cross-arm audit (§9.4).

---

## 4. Pinning the bands without a launchd job

| Arm | Construction | Expected base / max | Readback |
|---|---|---|---|
| cure | the harness runs from a session's Bash tool or a pane (31) and starts the supervisor with `detach` (`scripts/lib/detach.sh`, `setsid` Popen; inherits the band) | 31 / 63, as `claude.exe` and an Interactive job (axis 04 R0.3) | daemon: `band.log` line every pass (`__main__.py:541-554`, `band.py:120-143`); sampler: `band.base_priority(pid)` for the supervisor, the daemon and every descendant |
| red (band) | the same, with `/usr/sbin/taskpolicy -c utility` as the first argv element of the detached command | **20 / 20**: "identical to a utility clamp", the launchd no-ProcessType ceiling (axis 04 R0.3); inherited by every route (R0.4) | same; the daemon also pages `band-low` into the rig's `cc-notify` stub (expected) |
| red (incident, optional) | the red arm on a `git archive 58885750c` tree (read-only on the repo) | 20 / 20 | same |

**Rules.**
- **The harness's own band is checked first.** `band.py $$` must read ≥ 31, or the run ends `NO-VERDICT band:caller-clamped` with exit 3. The message names the likely clamp: `cc-bats` (`bin/cc-bats:752`), postland at background QoS (`scripts/postland-verify.sh:16,433`), or a launchd job with no ProcessType. "A utility-clamped parent cannot produce a priority-31 child" (`REPORT.md:106`, axis 04 R0.4).
- **The harness driver, sampler and generator controller always run at the caller's 31,** never under the red clamp. The measuring instrument is never starved; only the subject is.
- **The `claude` stubs run at 31 in both arms.** Kitty launches them. That matches production, where sessions are at 31 and only the rail moved.
- **Kitty's band is read every 5 s.**
  - The kitty pid comes from the socket name `kitty-<pid>` (`CC_TERM_KITTY_PID`, `lr-recon-rig.sh:62`), never from `pgrep`, which found the napped `kitty-pr3` instance first (M9).
  - Rows where kitty's base priority is below 31 are binned `kitty-napped` and never pooled with the main bins. That is the B8 class.
- **No operator step is needed.** The on-demand rig plist (`scripts/limit-recover/com.reso.lr-reconciler-rig.plist`) sets no ProcessType, so it would run at 20. The harness does not use it.

---

## 5. The load generator (`tests/rig/loadgen.py`)

**Thread construction (M5).**
- One process, started at the caller's 31, so it starts in milliseconds (M4 shows why it must not start under a background clamp).
- It runs K worker threads. Each one first sets its own band:
  - **bg:** `libSystem.setpriority(3 /*PRIO_DARWIN_THREAD*/, 0, 0x1000 /*PRIO_DARWIN_BG*/)` → base 4, E-core confined;
  - **ut:** `pthread_set_qos_class_self_np(0x11 /*QOS_CLASS_UTILITY*/, 0)` → base 20;
  - **df:** no change → base 31, duty-cycled `busy_ms/idle_ms` (default 600/400) to look like bursty `claude.exe` work.
- The work is `hashlib.sha256(1 MiB)` in a loop. CPython releases the GIL for hashes of 2 KiB or more, so the threads are concurrently runnable.
  - Measured in M5: 4 of 4 runnable at bg, 4 of 4 at ut, 6 of 6 at df.
  - The df probe cost at most 24 CPU-s at 31 (6 threads for 4 s).
- Never wrap the generator in `taskpolicy` to set its band. Under a utility clamp python had not started its threads 3 s in, and under a background clamp it did not finish starting in minutes (M4).

**Control and stop.**
- The main thread stays at 31 and polls once per second. It exits with `os._exit(0)` (all threads die at once) when any of these holds:
  - the parent harness pid is gone (deadman);
  - `--max-s` has passed (default 3600);
  - `/tmp/lr-harness/OFF` exists;
  - the control file says `stop`.
- Counts are adjusted by re-spawning the process with the new counts. That is cheap at 31, and bg threads may never get CPU to see a retire flag.
- **Fork storm (opt-in only, `--storm R`):** a ut thread runs `posix_spawn("/usr/bin/true")` at rate R, capped at 400/s. This reproduces the sys-time and `syspolicyd` share (axis 09 §1.3: 280-1,410 execs/s). It is off by default, because the ambient box already has it.

**Levels, defined by what the subject competes with, not by load1.**

load1/ncpu mostly counts base-4 threads on 2 E-cores (`REPORT.md:126`). Adding bg spinners raises that number and stresses neither the 31 band nor the 20 band. So:

| Bin | Defining measure | Anchors (measured) |
|---|---|---|
| `r31-low` | median runnable base-31 threads per P-core in [1, 2) | gap-4: 6-75, median 10 at 21-25/core |
| `r31-mid` | [2, 4) | axis 04 R0.2: 12-48 at load 182-219 |
| `r31-high` | ≥ 4 | M3: 33-45 at load 273 |
| load bins, recorded beside | load1/ncpu in [15,20), [20,30), [30,40), ≥ 40 | `REPORT.md:474-479` targets 15, 25, 40 |
| `r20` | runnable base-20, recorded (the red arm's competition) | axis 09 R2: 30-38; M3: 11-12 |

**Closed loop.** The controller in `load_lib.py sample` runs every 15 s from the census. It computes `deficit = target − (ambient − own)` per band and rewrites the generator's control file. It never waits for load to change.

| Mode | What it adds |
|---|---|
| `--level ambient` (default) | nothing; the run is classified by measured bin |
| `--bg-topup N` | up to N bg threads (cap 200) to reach a load1/ncpu target (e.g. 40) |
| `--df-topup N` | up to N df threads (cap 16) to reach `r31-high`. **Operator-gated**: it takes P-core time from sessions (§13, §15) |

---

## 6. The cohort, the faults, and when the clock starts

### 6.1 Matrices (new `tests/rig/faults/*.json`, same format as `matrix30.json`)

**`guarantee9.json`** has n = 9, as in the incident. `source: next`, `go_barrier: true`, `die_spread_s: 120`.

| Group | n | Knobs | `expect` | What it checks |
|---|---|---|---|---|
| clean-limited | 3 | — | ENGAGED | the baseline lanes |
| kitty-slow | 1 | `kitty_delay_s: [2, 15]` | ENGAGED | A3: our 3 s and 10 s kitty bounds fire and are retried, never IMPOSSIBLE |
| composer-unreadable-once | 1 | `composer_unreadable_s: 120` | ENGAGED | TRANSIENT retry of `HELD:composer-unreadable` (`b26fb875d`) |
| true-busy | 1 | `busy_for_s: 300` (WORKING at go, dies at go+300) | ENGAGED | a hard hold until the turn ends; `t0` = its death |
| goal-meta | 1 | `goal_meta_after_limit: true` | ENGAGED | no false HELD:busy (`c82a349ce`, `9fc5964c3`) |
| heavy-lead | 1 | `heavy_lead_subagents: 18` | ENGAGED | weight 19 placed under the seat model (`69ebee15f`) |
| restart-mid-actuation | 1 | `daemon_fault: kill9_post_transplant` | ENGAGED | G6; self-claim refusals counted (target, owner A6) |

The `placer` block is: `{cpu_s: 4.0, sleep_s: 200, sleep_calls: [1, 2], kmax: 24, occupied: {next2: 6, next3: 6, next4: 6}}`.
- `cpu_s` 4.0 is the measured `--place` CPU per call (axis 06 §4: "about 4 CPU-s per call", cProfile 4.10 s wall at foreground).
- The two sleeps exceed the 120 s bound (`plan.py:358-364`), so the "placer sleeping past its bound" fault fires twice.

**`guarantee30.json`** has n = 30.
- It is `guarantee9` ×3, plus 3 `idle: true` (MOVED, via the idle fan-out), 1 `draft: {at: boot}` (HOLD-DRAFT, a hard hold that must page) and 1 `bg_job: {at: boot}` (HOLD-BGWORK).
- The extra groups make the cohort 33, not 30; the build sets the counts so they sum to 30. `rig_lib expand` already refuses a mismatch (`lr-recon-rig.sh:135-136`).

**`smoke3.json`** has 3 clean-limited members. It is the quick check, run first after any rig change.

### 6.2 Death and request (the clock start)

- Today the stubs die at boot, before the daemon exists (`stub-claude.py:539-570`), and the rig then runs `cc-lr recover --limited` (`lr-recon-rig.sh:234-238`).
- With `go_barrier`, a stub boots in WORKING (a user turn, busy frame) or idle. After the daemon's first heartbeat the rig writes `$RIG/go`, and each stub writes its limit death at `go + die_at_s`. `die_at_s` is drawn per member from a seeded uniform over `[0, die_spread_s]`.
- The stub records `died_at` in `$RIG/tmp/stub/<sid>.json`. That is the production shape: the daemon is live while sessions hit the wall.
- **`t0(r) = max(died_at, t_request)`**, where `t_request` exists only when the matrix uses the `cc-lr recover` path.
- `t_detect(r)` = `timeline.detected` (`types.py:697-706`).
- Death → detect latency is reported separately. A slow band delays detection too, and §5's `t_detect` alone would hide that.

### 6.3 Mirroring the production switches

- At preflight the harness reads, read-only, `~/.reso/limit-recover/{recon.on, autorecover.on, recon/autorecover.on, recon/mode}`.
- It then sets `LR_RIG_AUTORECOVER=on|off` for both arms. Today that is `on` (M12): the rig touches `$RIG/lr/autorecover.on` and `$RIG/state/autorecover.on`, as it already does for idle fan-out matrices (`lr-recon-rig.sh:201`).
- `--request cc-lr` keeps the legacy operator-verb path for W5 matrices.

---

## 7. What is measured, and from which file

| Quantity | Source (per arm root `$R`) | Note |
|---|---|---|
| `died_at`, `busy_until`, `garble_until` | `$R/tmp/stub/<sid>.json` (stub state, new keys) | stub wall clock at the event |
| `t_detect` | `$R/state/sessions/<sid>.json` `.timeline.detected` | pass-scoped `now` |
| **attempt start** | birth time of `$R/state/actlogs/<sid8>.<attempt>.<ACT>.log` (`os.stat().st_birthtime`); `act.spawn` opens it immediately before `popen` (`act.py:302-305,320-327`) | real wall time. The `spawn` event's `t` is the pass `now` (`act.py:346-353`), up to one pass earlier, so it is a cross-check only |
| actuator / lane | the `ACT` token in the actlog name; `events.jsonl` `spawn.detail` "`A pid=…`" | lanes in the rig: A, A-husk, B, C, C-retry, R, … (`types.py:91-103`); `kind` limited vs idle |
| attempt end, outcome | `events.jsonl` `ev=exit` "`A rc=6 → HOLD/HOLD-COMPOSER`"; actlog tail verdict | `t` is the reaping pass |
| engaged | `.timeline.engaged`, `.close.via`, `.close.at` (`rig_lib.timings`, `rig_lib.py:515-541`) | observed, so it includes up to one pass of observation lag |
| holds and soft-reason history | `.close.seen[]`, `.last_error`, `.wait`, `events.jsonl` (`reprobe`, `admit-refused`, `place` rc and dur) | `place` rows carry `rc, dur, timeout, load1` (`__main__.py:1018-1036`) |
| pass interval (`P` upper bound) | consecutive `$R/state/band.log` lines, one per pass (`__main__.py:541-554`) | the gap is pass + wait (3/5/20 s, `__main__.py:57`) |
| stall | `$R/state/heartbeat` `max_step_gap_s` (`clock.py:202-251`) | |
| abstains | `events.jsonl` `ev=abstain` | M7 shows they happen at 31 |
| pages | `$R/state/pages.log` (the rig's `cc-notify` stub, `lr-recon-rig.sh:125-126`) | hard holds must page |
| self-claim refusals (G6) | `grep -c "another actuator holds session" $R/state/actlogs/*` (the incident string, `REPORT.md:175`) | |
| bands and load | `samples.jsonl` (§9.8) | every 5 s per-pid; census every 15 s |
| rig CPU | supervisor `times` at exit (reaped descendants: the daemon and its waited-on actuators); stub `proc_pid_rusage` at teardown | |
| kitty delay applied | `$R/state/kitty-delay.log` (the wrapper's own log) | proves the fault fired |

**Per member, `members.jsonl`:**
`t0`, `death→detect`, `detect→first attempt`, `t0→first attempt`, the attempt list (`actuator, t_spawn, t_exit, rc, verdict`), the retry gaps (`t_spawn[i+1] − t_exit[i]`), `first attempt→engaged`, `t0→engaged`, `k_r`, `bound_s`, `fault_exercised`.

**Per arm and per lane:** p50, p90 and max of each interval, by actuator letter and by kind.

---

## 8. Assertions, thresholds, verdicts

The §5 constants for the target bound are `W_soft` 600 s, `P_max` 180 s, `T_att` 900 s, `D` 6 (`BootSlots.START` and `PACE_BURST`, `admit.py:51-55,336-341`) and `B_max` 300 s (`REPORT.md:437-443`).
- `k_r` is the number of non-held members with `t0` earlier than r's.
- `bound(r) = W_soft + P_max + ceil(k_r / D) · T_att`.
- `T_done(r) = t0 + bound(r) + T_att`.

### 8.1 Preconditions. A failure means `NO-VERDICT`, never PASS and never FAIL

| id | Precondition |
|---|---|
| P1 band pinned | cure: the daemon's `band.log` reads 31 on ≥ 95% of lines, and every sampled descendant reads ≥ 31. Red: 20 / 20 |
| P2 load present ("Verify a cure under its load", `agent-operating-lessons-situational.md:83`) | ≥ 70% of samples fall in the declared bin, with no sampler gap over 3× its interval for more than 10% of the run |
| P3 faults fired | each member's fault is `fault_exercised` (a kitty-delay log row; `HELD:composer-unreadable` seen; `busy_until` written; …). If more than 20% did not fire, the run is NO-VERDICT, and a non-firing member's own assertions are NO-VERDICT |
| P4 rig sane | setup finished; foreign records = 0; the planted non-rig row was refused (`rig_lib.refusal`, `rig_lib.py:373-394`) |

### 8.2 Hard assertions. These must hold now, and a failure means FAIL

| id | Assertion | Guarantee |
|---|---|---|
| H1 | zero `HELD:load` / `HOLD-LOAD` in any record, event or actlog | G1 |
| H2 | zero IMPOSSIBLE or ESCALATED whose reason is soft (resolver-unavailable, unreachable, wedged, composer-unreadable, `probe-timeout`, place rc 124) | G2, G5 |
| H3 | every non-held member ends ENGAGED, MOVED or IN-PLACE by `T_done(r)` | G5 |
| H4 | every hard-held member (HOLD-DRAFT, HOLD-BGWORK, true busy) is still open, never IMPOSSIBLE, and has paged within `MAX_AGE_S[sub] + 2·P_obs` (`types.py:119-133`) | §5 hard predicates |
| H5 | double-typer 0, split-brain 0, lost-records 0 (`rig_lib.audit`, `rig_lib.py:123-200`) | safety |
| H6 | after every failed attempt, the next spawn starts within `B(attempt) + 2·P_obs`, where `B` is the classify backoff ≤ 300 s (`b26fb875d`) | G retry clause |

### 8.3 Target assertions. Each is reported and owned by an item; it becomes hard in that item's commit

These live in `tests/rig/load-expect.json` as `{"T1": "target:B3", …}`. A target that passes is reported `XPASS`, which tells the owner to flip it.

| id | Assertion | Owner |
|---|---|---|
| T1 | `t_first(r) − t0(r) ≤ bound(r)` for every non-held r | B3 (with B2) |
| T2 | `P_obs` = max `band.log` gap minus wait ≤ 180 s | B2 |
| T3 | `T_att,obs` = max(`t_exit − t_spawn`) ≤ 900 s | B2, B5 |
| T4 | zero self-claim refusals after `kill9_post_transplant` | A6 |
| T5 | (phase 2) a member that turns limited while queued in the move lane is driven | A7 |

### 8.4 Power, and the pair verdict

**Power** holds when there is an assertion A in (H ∪ T) such that `cure(A) = PASS` and `red(A) = FAIL`, both arms satisfy P1-P4, and the two arms' level bins overlap. This follows the lesson "a case passing in both arms is an equivalence guard, not a red-proof" (`agent-operating-lessons-situational.md:62`).

| Pair verdict | Condition | Exit code |
|---|---|---|
| PASS | power holds, and the cure arm passes every hard assertion | 0 |
| FAIL | the cure arm fails a hard assertion while its preconditions hold | 1 |
| NO-VERDICT | a precondition failed in either arm, or a harness bound fired (boot wait, heartbeat wait) | 3 |
| SIGNAL-DEAD | both arms pass every assertion the red arm was expected to fail | 4 |

A harness bound firing ("our timeout") is "unknown, retry" under the operator premise. It is never a FAIL.

**Early stop for the red arm.** The red arm is cheap (band 20) but slow. It stops as soon as power is established: it has failed an assertion that the finished cure arm passed. Otherwise it runs to `max T_done`.

**One verdict line, which carries every gap** ("Runner states its gaps", `agent-operating-lessons-situational.md:115`):

```
lr-load-harness 20261021T0900Z-ab12 · cure band 31 (31/31) r31-high load/core p50 24.1 in-bin 86% · H 6/6 · T1 PASS T2 PASS T3 PASS T4 XFAIL[A6] · detect→attempt p50 41s p90 75s max 102s · attempt→engaged p50 58s p90 140s · faults 9/9 fired | red band 20 (20/20) · H3 FAIL 6/9 · T1 FAIL 9/9 · POWER via T1,H3 → PASS
```

---

## 9. Changes, file by file

### 9.1 `tests/rig/lr-recon-rig.sh` (about +80/−15 lines)

```diff
@@ :30-32
-RIG=/tmp/lr-rig
+RIG="${LR_RIG_ROOT:-/tmp/lr-rig}"                 # the harness passes /tmp/lrh-<id>-<arm>
+RIG_TAG="$(basename "$RIG")"                       # window titles and teardown matches are per arm
 HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
-REPO="$(cd "$HERE/../.." && pwd)"
+REPO="${LR_RIG_TREE:-$(cd "$HERE/../.." && pwd)}"  # the code under test; stub/fake/rig_lib stay from $HERE
+BAND="${LR_RIG_BAND:-inherit}"                     # inherit | utility (the red arm)
+HB_WAIT_S="${LR_RIG_HB_WAIT_S:-60}" BOOT_WAIT_S="${LR_RIG_BOOT_WAIT_S:-90}"
@@ write_env (:52-64)  add
+export LR_RIG_TAG="$RIG_TAG" LR_RIG_REAL_KITTY="$KITTY_REAL"
+export CC_TERM_KITTY="$RIG/bin/kitty-slow" LR_KITTEN_BIN="$RIG/bin/kitten-slow"   # pass-through without a fault file
+export RIG_PLACE_CPU_S=… RIG_PLACE_SLEEP_S=… RIG_PLACE_SLEEP_CALLS=… RIG_PLACE_KMAX=… RIG_PLACE_OCCUPIED=…  # from the matrix's placer block
@@ teardown (:82,:84)
-  … close-window --match "title:^lr-rig" …
+  … close-window --match "title:^${RIG_TAG}( |\$)" …
-  … close-window --match "cwd:^(/private)?/tmp/lr-rig/" …
+  … close-window --match "cwd:^(/private)?${RIG}/" …
@@ :96
-case "$RIG" in /tmp/lr-rig) rm -rf /tmp/lr-rig ;; *) die "refusing to clear $RIG" ;; esac
+case "$RIG" in /tmp/lr-rig|/tmp/lrh-[0-9A-Za-z]*-cure|/tmp/lrh-[0-9A-Za-z]*-red*) rm -rf -- "${RIG:?}" ;;
+  *) die "refusing to clear $RIG" ;; esac
@@ :162-163, :173 titles
-  --os-window-title lr-rig … --title "lr-rig control"     /  --title "lr-rig s$n"
+  --os-window-title "$RIG_TAG" … --title "$RIG_TAG control" /  --title "$RIG_TAG s$n"
@@ :172-176  LR_RIG_LAYOUT=splits (harness default): ≤4 members per OS window via --type=window --location=vsplit|hsplit,
             a new --type=os-window per group of 4; tabs stay the legacy default (operator rule, bin/it2-kitty:263)
+ printf '%s\t%s\n' "$wid" "$sid" >> "$RIG/windows.sid"      # the kitty-slow wrapper's window→member map
@@ :185  … -lt 90 …  →  … -lt "$BOOT_WAIT_S" …
@@ :201  autorecover: also when LR_RIG_AUTORECOVER=on (the harness mirrors production, §6.3)
@@ supervisor.sh heredoc (:202-218): add at the loop's end
+times > "$RIG/state/supervisor.times"      # reaped-descendant CPU: the arm's rig cost
@@ :222-223
-SUP="$(detach "$RIG/state/supervisor.out" /usr/bin/env -i /bin/bash -c '. "$0"; exec /bin/bash "$1"' \
+pfx=(); [ "$BAND" = utility ] && pfx=(/usr/sbin/taskpolicy -c utility)
+SUP="$(detach "$RIG/state/supervisor.out" ${pfx[@]+"${pfx[@]}"} /usr/bin/env -i /bin/bash -c '. "$0"; exec /bin/bash "$1"' \
        "$RIG/env.sh" "$RIG/supervisor.sh")" || die "supervisor spawn"
@@ :231  … -lt 60 …  →  … -lt "$HB_WAIT_S" …   (the harness sets 600 for red: python start at 20 under load)
+[ "$(json go_barrier)" = true ] && : > "$RIG/go"       # stubs die at go + die_at_s
@@ :235  run cc-lr recover only when LR_RIG_REQUEST=cc-lr (default for legacy matrices)
@@ end: write $RIG/rig-result.json {drive_rc, audit_rc, refusal_rc, line_rc, got, expected} before teardown
```

Notes:
- The `${pfx[@]+…}` spelling keeps `/bin/bash` 3.2 safe under `set -u` with an empty array ("Deployment interpreter ≠ yours", `agent-operating-lessons.md`).
- `pkill -f "$RIG/bin/claude"` (`:85`) is already per root. `/tmp/lr-rig/bin/claude` is not a substring of `/tmp/lrh-…`.
- The default root `/tmp/lr-rig` and `com.reso.lr-reconciler-rig.plist` keep working unchanged.

### 9.2 `tests/rig/stub-claude.py` (about +170 lines)

1. **Argv prompt (the precondition; M10).** `main()` (`:602-626`) changes to:
   ```python
   VALUE_FLAGS = {"--model","--effort","--permission-mode","--mcp-config","--settings",
                  "--append-system-prompt","--session-id","--resume","-r"}
   def _resume_args(a):
       i = a.index("--resume") if "--resume" in a else a.index("-r")
       sid, rest, prompt, j = a[i + 1], a[i + 2:], "", 0
       while j < len(rest):
           if rest[j] in VALUE_FLAGS: j += 2; continue
           if rest[j].startswith("-"): j += 1; continue
           prompt = rest[j]; j += 1
       return sid, prompt
   ```
   `resume(sid, prompt)` (`:572`) sets `t.pending_prompt = prompt`. `Tui.key_loop` (`:383`) calls `self.submit(self.pending_prompt)` once, right after its first `draw()` following boot (after `boot_delay_s` and `boot_cpu_s`). That is the real CLI's self-submit. `submit` (`:342-381`) already writes the user record (token included) and applies `first_turn` faults.
2. **`go_barrier`, `die_at_s`.**
   - `fresh()` (`:539-570`) writes history, boot marker and composer, but no death.
   - `Tui.tick()` (`:479`) writes `error("limit")` once `$LR_RIG/go` exists and `time() ≥ mtime(go) + die_at_s`, then `mark(died_at=…)`.
   - Without `go_barrier`, behaviour is exactly as today.
3. **`busy_for_s`.** The stub boots with a user turn and a busy frame, and no limit. At `go + busy_for_s` it writes the assistant partial plus the limit error and records `busy_until`.
4. **`goal_meta_after_limit`.** Right after the limit error, it appends the `isMeta` user record ("A session-scoped Stop hook is now active…") stamped 1 s *before* the limit. This is 769b7294's shape (`REPORT.md:177`). It needs a new fixture, `tests/fixtures/lr-recon/jsonl/goal-meta-after-limit.jsonl`, copied from the case in `tests/handoff-recycle-same-account.bats` (`c82a349ce`).
5. **`composer_unreadable_s`.**
   - From `died_at` to `died_at + N`, `draw()` (`:263`) paints a new fixture, `tests/fixtures/lr-recon/screens/composer-unreadable-2.1.284.txt`, then the normal frame. It records `garble_until`.
   - *Build check:* the fixture must make the real composer reader return unreadable. Run it through `scripts/lib/lr-composer-snapshot.sh` against a pane, or through the parser the parity suite uses (`tests/composer-parser-parity.bats`).
6. **`heavy_lead_subagents: K`.** At death it creates `<tx dir>/<sid>/subagents/agent-<i>.jsonl` × K with `os.utime` set to `died_at − 60`. That is inside `[death − 600, death]`, the window `plan.subagents_written` counts (`plan.py:102-117`).
7. **`boot_cpu_s`.** On `--resume`, it burns this many CPU-seconds (a hash loop) before painting READY.
   - Default 0.
   - The harness sets it from `calibrate`: the CPU time of real `claude.exe` processes aged 10-30 s, read with `proc_pid_rusage`, read-only.
   - Until it is calibrated, the value is E. There is no measured boot CPU-s figure.
8. **Seam for G2:** `stop_failure_hook: <path under $HOME/.claude/hooks>`. At death it pipes the hook's StopFailure JSON to that command. B1 does not use it; G2 does.

### 9.3 `tests/rig/fake-claude-accounts.py` (about +60 lines, in `place()` at `:63-110`)

- **`RIG_PLACE_CPU_S`.** Burn this many CPU-s before answering. That is real CPU in the caller's band, so the placer pays the band tax exactly as the real one did: fired at 120 s at 20, answers in seconds at 31.
- **`RIG_PLACE_SLEEP_S` / `RIG_PLACE_SLEEP_CALLS`.** On those call ordinals (a counter file `fake-accounts.calls` beside `fake-accounts.rr`), sleep past the bound.
- **Seat model `RIG_PLACE_KMAX` / `RIG_PLACE_OCCUPIED`.**
  - Refuse an account when `occupied + Σ live charges + w > KMAX`, with `reason: "no-eligible"`.
  - Charges are keyed by the mover row's `assign_id`, with a 1200 s TTL.
  - A mover's own `assign_id` is refunded, mirroring E4.3 (`69ebee15f`).
  - The rig's `accounts.json` (`rig_lib.build_home`, `rig_lib.py:206-226`) gains `"router": {"KMAX": <kmax>}`, so the reconciler's clamp reads the same KMAX (`plan.py:173-196`).

### 9.4 `tests/rig/rig_lib.py` (about +130 lines)

- **`expand`** (`:41-63`): carries the new knobs, plus matrix-level `go_barrier`, `die_spread_s` (to a per-member `die_at_s` from a seeded `random.Random(seed)`) and the `placer` block.
- **`drive`** (`:433-506`): new `daemon_fault: kill9_post_transplant`. It fires when the member's record `phase ∈ {TRANSPLANTED, EXITING}` and a recorded actuator pid is alive (`os.kill(pid, 0)`). That is the incident's restart-after-transplant shape (`REPORT.md:175`).
- **`audit`** (`:123-200`): adds `foreign records`, the count of `state/sessions/*.json` whose sid is not in `specs.json`, which must be 0. It also adds the list of window ids left after teardown.
- **New `result`:** writes `rig-result.json` for the harness.
- **`_settled`** (`:417-430`) is unchanged. The busy member's `expect` is ENGAGED.

### 9.5 New `tests/rig/kitty-slow` (about 40 lines of bash; `kitten-slow` is a symlink)

```bash
#!/bin/bash
# kitty RC delay fault: a call whose --match names a member window listed in $LR_RIG/faults/kitty-delay.tsv
# (window_id<TAB>lo<TAB>hi) sleeps U(lo,hi) s first, then execs the real binary. No file → pure exec.
real="${LR_RIG_REAL_KITTY:-/Applications/kitty.app/Contents/MacOS/kitty}"
[ "${0##*/}" = kitten-slow ] && real="${real%/kitty}/kitten"
f="${LR_RIG:-}/faults/kitty-delay.tsv"; w=""
if [ -s "$f" ]; then
  for a in "$@"; do case "$a" in id:*) w="${a#id:}" ;; esac; done
  if [ -n "$w" ] && row="$(awk -F'\t' -v w="$w" '$1==w {print $2" "$3; exit}' "$f")" && [ -n "$row" ]; then
    s="$(awk -v r="$row" -v seed="$$" 'BEGIN{split(r,a," "); srand(seed); printf "%.1f", a[1]+rand()*(a[2]-a[1])}')"
    printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$w" "$s" "${1:-}" >> "$LR_RIG/state/kitty-delay.log"
    sleep "$s"
  fi
fi
exec "$real" "$@"
```

It works because `CC_TERM_KITTY` wins verbatim in `bin/cc-kitty-bin:27-29`. Every actuator resolves its kitty through it: `handoff-fire.sh:1194-1206`, `cc-tui.sh:80-92`, `lr-lib.sh:1236-1245`. The daemon's own kitten reads `LR_KITTEN_BIN` (`observe.py:226-229`). The wrapper is bash in the caller's band, as the real client is.

### 9.6 New `tests/rig/runq.py` (about 130 lines; ctypes only, never forks)

- **`census()`** returns `{base_pri: runnable_count}` plus readable and total counts. It reads `proc_listallpids`, then `PROC_PIDLISTTHREADS` and `PROC_PIDTHREADINFO` (`pth_priority` = base, `pth_run_state == 1`). This is lifted from axis 04's read-only `census.py`; M3 shows the cost. About 430 root-owned processes are unreadable, so it is a lower bound (axis 04 L6).
- **`base_of(pid)`** is `lr_recon.band.base_priority` (`band.py:74-92`), imported by path.
- **`threads_of(pid)`** returns a `{(base, run_state): n}` counter (M5's probe).
- **`descendants(root)`** walks ppid through `PROC_PIDTBSDINFO`. **`rig_procs(rig)`** adds young same-uid processes whose argv (sysctl `KERN_PROCARGS2`) contains the rig root. That catches watchers that were re-parented to launchd.
- **`fd_count(pid)`** uses `PROC_PIDLISTFDS`. **`cpu_s(pid)`** uses `proc_pid_rusage(RUSAGE_INFO_V2)`.

### 9.7 New `tests/rig/loadgen.py` (about 200 lines)

```
loadgen.py run --bg N --ut N --df N [--df-duty 600/400] [--storm R] --parent PID --max-s S --ctl FILE
  main thread (31): every 1 s → os._exit(0) if parent dead | now > deadline | /tmp/lr-harness/OFF | ctl says stop
  worker(kind): bg → setpriority(PRIO_DARWIN_THREAD, 0, PRIO_DARWIN_BG); ut → pthread_set_qos_class_self_np(UTILITY, 0)
                loop: sha256(1 MiB) [df: busy busy_ms, sleep idle_ms]
  storm (opt-in): ut thread, posix_spawn /usr/bin/true at ≤ R/s (cap 400)
  writes $ctl.pid and $ctl.own = {"bg":n,"ut":n,"df":n,"pid":p}
```

### 9.8 New `tests/rig/load_lib.py` (about 550 lines; stdlib, `/usr/bin/python3 -I`)

| Subcommand | Does |
|---|---|
| `sample RUN ARM… --every 5 --census-every 15` | appends `samples.jsonl` rows: `{t, load:[1,5,15], ncpu, runq:{4:…,20:…,31:…}, runq_s, own:{bg,ut,df}, arms:{cure:{sup, daemon:{pid,base}, kids:{n,min_base,max_base}}, red:{…}}, kitty:{pid,base,fds}}`. Drives the generator's control file from the deficit rule (§5). Watches the abort triggers (§10) |
| `collect RUN ARM` | from the arm root, writes `members.jsonl` (§7) and `lanes.json` (per-actuator and per-kind p50/p90/max) |
| `assert RUN ARM` | evaluates P1-P4, H1-H6 and T1-T5 with `load-expect.json` modes; writes `summary.json`; prints the arm half of the verdict line |
| `pair RUN` | power, early-stop state, `pair.json`, the full verdict line, exit code (§8.4) |
| `analyze DIR…` | across saved runs: t_first p90 against the r31 bin and the load bin, next to `P_obs + T_att,obs`. Report only (§5 item 5's slope test; with few runs it is indicative, never a gate) |

**Core of `assert`, as pseudocode:**

```python
nonheld = [m for m in members if m.expect not in HARD_HOLDS]         # HOLD-DRAFT, HOLD-BGWORK
nonheld.sort(key=lambda m: m.t0)
for k, m in enumerate(nonheld):
    m.k, m.bound = k, W_SOFT + P_MAX + ceil(k / D) * T_ATT
    m.t_done = m.t0 + m.bound + T_ATT
    T1[m] = m.t_first is not None and m.t_first - m.t0 <= m.bound
    H3[m] = m.closed_via in ("ENGAGED", "MOVED", "IN-PLACE") and m.closed_at <= m.t_done
    H6[m] = all(nxt.t_spawn - cur.t_exit <= backoff(cur.n) + 2 * P_obs
                for cur, nxt in pairs(m.attempts) if cur.failed)
H1 = count(records/events/actlogs matching r"HELD:load|HOLD-LOAD") == 0
H2 = count(terminal in ("IMPOSSIBLE",) or escalated, reason in SOFT_REASONS) == 0
T2 = max(gap - wait_of(gap) for gap in band_log_gaps) <= 180
T4 = count_actlog("another actuator holds session") == 0
```

### 9.9 New `tests/rig/lr-load-harness.sh` (about 330 lines; `/bin/bash` 3.2 safe)

```
lr-load-harness.sh preflight [--n N]               read-only checks, prints the budget table, exit 0/3
lr-load-harness.sh run --matrix F [--arms cure,red] [--red band|incident:<sha>] [--level ambient]
                       [--bg-topup N] [--df-topup N] [--kitty main|private] [--out DIR] [--detach]
lr-load-harness.sh status RUN_ID | wait RUN_ID [--max 270] | stop [RUN_ID] | calibrate | analyze DIR…
```

`run` flow:
1. **Gates, all failing to NO-VERDICT with exit 3.**
   - `/tmp/lr-harness/OFF` absent.
   - `flock /tmp/lr-harness/lock` (one run at a time).
   - `band.py $$` ≥ 31.
   - Preflight budgets (§13).
   - No production cohort moving: no `~/.reso/limit-recover/recon/sessions/*.json` open in a MOVING phase or `PLANNED`. Production recovery has priority.
2. Mirror the production switches (§6.3).
3. **Trees.** The cure arm uses HEAD's checkout. `--red incident:<sha>` uses `git archive <sha> | tar -x -C /tmp/lr-harness/trees/<sha>`, which only reads git objects.
4. **Start the instruments.** Start `load_lib.py sample` in the background, then `loadgen.py` (counts from the controller; 0 under `--level ambient`).
5. **Launch both arms in the background:**
   `LR_RIG_ROOT=/tmp/lrh-$ID-cure LR_RIG_LAYOUT=splits LR_RIG_AUTORECOVER=… bash tests/rig/lr-recon-rig.sh --n N --faults F --timeout <max T_done>`,
   and the same with `-red`, `LR_RIG_BAND=utility`, `LR_RIG_HB_WAIT_S=600` and, for an incident arm, `LR_RIG_TREE=…`.
   `LR_RIG_KEEP=1` is set so that `collect` can read the arm root before teardown.
6. **Watch.** Poll arm results. Apply the red early stop (§8.4): `touch $R/stop`, then the rig's own teardown. Apply the abort triggers (§10).
7. **Finish.** `collect`, `assert` per arm, then `pair`. Tear down both arms (`bash tests/rig/lr-recon-rig.sh --teardown` with each `LR_RIG_ROOT`), stop the generator and sampler, and print the verdict line.

Results go to `/tmp/lr-harness/<id>/`; `--out DIR` copies `{summary,pair,lanes}.json` and `members.jsonl`.

**Agent operability.**
- `--detach` starts the run through `scripts/lib/detach.sh` and prints the id.
- `wait` blocks for at most 270 s per call, so an agent never holds one Bash call for more than 4.5 min.
- The detached run inherits, and re-reads, band 31.

### 9.10 Data files

- **`tests/rig/faults/{guarantee9,guarantee30,smoke3}.json`** (§6.1).
- **`tests/rig/load-expect.json`:** `{"H1":"hard",…,"T1":"target:B3","T2":"target:B2","T3":"target:B2","T4":"target:A6","T5":"target:A7"}`.
- **`tests/rig/g1-allow.tsv`:** one row per allowed load read, as `path<TAB>enclosing-function<TAB>class<TAB>reason/owner`. Rows are anchored on the function name, not a line number ("Insertions break line citations", situational rules). Seed rows, measured with `grep -n -E "getloadavg|vm\.loadavg|load1|ncpu"` and enclosing-def `awk`:

  | path | function | class |
  |---|---|---|
  | `lr_recon/admit.py` | `enter_active` | telemetry (`l_open` recorded, read by nothing) |
  | `lr_recon/admit.py` | `decide` | telemetry (arguments deleted, `:283`) |
  | `lr_recon/__main__.py` | `_admission_period`, `_admit` | telemetry (arguments) |
  | `lr_recon/__main__.py` | `_plan` | bound-stretch (owner B2) |
  | `lr_recon/plan.py` | `place_timeout` | bound-stretch (owner B2) |
  | `lr_recon/clock.py` | `load_multiplier` | bound-stretch |
  | `lr_recon/observe.py` | `ps_bound` | bound-stretch |
  | `lr-move-worker.sh` | `mw_load_per_core` | telemetry (`ev load`, `05829eeb7`) |
  | `handoff-fire.sh` | `hf_recycle_load_bound` and its precheck callers | harm-gate-typed (`REPORT.md:153`; staged moves exempt, `handoff-fire.sh:13879`) |

  The build enumerates the other 28 load matches in `handoff-fire.sh` (M: `grep -c`) and classifies each, or scopes them out as the fire path rather than the recycle path, with that reason.

### 9.11 Tier G tests

**`scripts/limit-recover/lr_recon/tests/test_guarantee_sim.py`** (about 380 lines).
- It follows `tests/test_midpass_progress.py`'s pattern: `FakeTime`, `mock.patch` of `observe.observe`, `plan.place`, `act.spawn`, `Admission.probe` and `mint_token`, plus `os.getloadavg`.
- A `Sim` charges every child its virtual cost. Costs are the 31-band p90 at 40/core: place 15 s (`134000efe`: 8.1 s at 22/core, scaled), probe 4 s, census 3 s, kitty 0.1 s per record.
- It turns a fake actuator into a timed transient NOTMOVED exit after `T_att_sim` (a verdict line appended to the actlog path `act.spawn` opened, plus `act.EXIT_CODES[pid]`, as `test_rollback.py` does). That frees the slot and drives retries.

| Case | Asserts | Mutant that must kill it (run at build, recorded in the docstring) |
|---|---|---|
| S1 load invariance | the full decision trace (spawn sid, actuator, virtual t; admission verdicts) is identical for load1 ∈ {150, 250, 400} on 10 CPUs | patch `Admission.pace_ok` to also require `getloadavg()[0]/10 < 20` → traces differ |
| S2 first-spawn bound | `t_first − t_detect ≤ 2·P_sim + ceil(k/6)·T_att_sim` (no soft gate before spawn but placement and `BootSlots`) | `BootSlots.START = 1` → k ≥ 1 exceeds the bound |
| S3 retry bound | after each transient exit, the next spawn ≤ `backoff(n) + 2·P_sim`, and the backoff never exceeds 300 | classify cap 900 → red |
| S4 our timeout is not a verdict | place rc 124 for the first 3 passes and probe `RC_TIMEOUT` on the first pass → every record still open, then spawned; no IMPOSSIBLE, no `HELD:load` | map rc 124 to DETERMINISTIC → red |
| S5 restart neutrality | rebuild `Ctx` from disk mid-run: `t_detect` unchanged, no second spawn for an attempt whose actuator is alive. `expectedFailure` (A6): the claim stays stamped to the live actuator, not the new daemon pid (`__main__.py:1786-1790`) | — (A6 flips it) |

**`tests/lr-recon-guarantee-sim.bats`** (about 20 lines): `cd scripts/limit-recover && python3 -m unittest lr_recon.tests.test_guarantee_sim`, with each case asserted, like `tests/lr-recon-one-driver.bats:20`. The literal `scripts/limit-recover` path makes it reachable for `gate-select lint` (`scripts/gate-select.sh:277,314`).

**`tests/lr-guarantee-g1-lint.bats`** (about 90 lines).
- Scan set: `lr_recon/*.py` (not tests), `lr-move-*.sh`, `lr-handoff.sh`, `lr-fire-resume.sh`, `lr-transplant.sh`, `handoff-fire.sh`.
- Rule 1: every load read lies in an allowlisted function.
- Rule 2: every allowlist row still matches (stale rows fail).
- Rule 3: every rail call of `cc_capacity_probe` or `cc_capacity_admit` carries `CC_ADMIT_LOAD_TERM=off` (`admit.py:224-226`), because the library's load gate defaults to 2.0/core (`scripts/lib/capacity-admit.sh:168,1382-1384`).
- Red-proof: copy a rail file to `$BATS_TEST_TMPDIR`, add a function with a bare `os.getloadavg()`, point the lint at it (`G1_LINT_ROOT`), expect exit 1.

**`tests/lr-load-harness-lib.bats`** (about 220 lines). This runs `load_lib.py assert` and `pair` on fixture runs under `tests/fixtures/lr-load-harness/`:
- cure PASS with red FAIL → exit 0;
- red PASS → `SIGNAL-DEAD` (4);
- cure daemon at 20 → `NO-VERDICT band` (3);
- 50% of samples out of bin → `NO-VERDICT load` (3);
- a fault that did not fire → member NO-VERDICT;
- T4 failing while owned by A6 → `XFAIL`, and passing → `XPASS`;
- one loadgen case: a 1-thread `--bg 1 --max-s 2` run reads `(4, *)` for its worker through `runq.threads_of`, and the process is gone within 10 s.
  - That case is valid in any parent band, because bg is the floor.
  - It holds no wall-clock bound tighter than 10 s.

**`tests/rig-stub.bats` additions** (about 70 lines):
- `claude --resume SID --model x "continue <token>"` → the transcript gains a user record carrying the token. This is **red against today's stub**.
- `go_barrier` death at `die_at_s`.
- The `busy_for_s` order of records.
- `goal_meta_after_limit` puts an `isMeta` record earlier than the limit.
- `heavy_lead` mtimes fall in the window.
- `RIG_PLACE_CPU_S` burns at least that much CPU (`resource.getrusage` of the child).
- The seat model refuses at KMAX.

---

## 10. Failure modes under permanent 15-40/core load

| Failure | Handling |
|---|---|
| Harness started from a clamped context (bats, postland, a launchd job without ProcessType) | `band.py $$` < 31 → refuse, `NO-VERDICT band:caller-clamped`, exit 3, before anything is created |
| Red-arm daemon start at 20 is slow (python imports in band 20) | `LR_RIG_HB_WAIT_S=600` for red. A miss is our bound: `NO-VERDICT setup`, never FAIL. The startup delay is reported, because production pre-A1 paid it too |
| Stub boots slow (kitty under load, n = 30) | `BOOT_WAIT_S = min(600, 30 + 10·n)`; a miss means NO-VERDICT |
| The generator cannot start or stop at the bg band | it never starts under a clamp (M4); it starts at 31 and threads self-demote; the main thread at 31 exits with `os._exit` (M5) |
| Load drops below the declared bin mid-run (M2: 278 → 153 in about 10 min) | no waiting. Classify by measured bin; P2 fails, so NO-VERDICT is reported with the actual bin distribution; re-run later or top up with `--bg-topup` |
| The sampler is starved | it runs at 31 (`runq` 0.26-0.54 s, M3); a sample gap over 3× its interval is counted; more than 10% gaps fails P2 |
| Kitty napped or locked (PRI 4, B8 class) | kitty's base priority is in every sample; rows below 31 are binned `kitty-napped` and never pooled; a run that is mostly napped is still reported, labelled |
| Kitty fd or coalition exhaustion from the rig's windows | preflight budget (§13). Abort trigger: kitty fds > 230 or coalition > 650 mid-run → stop both arms, teardown, `NO-VERDICT budget` |
| Memory pressure (a real harm, `REPORT.md:150`) | preflight refuses at headroom < 8 GB or segments ≥ 45% (the capacity-alarm warn floors, `capacity-alarm.sh:285,301`); abort on crossing |
| A production cohort goes ACTIVE mid-run | sampler trigger: any production record enters PLANNED or a MOVING phase → teardown both arms within one sample. The rig must not compete with a real recovery at 31 |
| Teardown slowed by kitty | per-call `timeout 10`; final sweep by `cwd:^…$RIG/`; leftover window ids are listed in `rig-result.json`; `stop` re-runs teardown |
| Harness or session dies mid-run | the generator's parent-death deadman (≤ 1 s); `stop` cleans arms by pidfiles and roots; `/tmp/lr-harness/OFF` blocks new runs |
| Cross-arm interference | registries are per-HOME and the `rig:true` rule (`observe.py:576`) refuses the other arm's sids. The audit asserts 0 foreign records per arm (P4). Titles and cwd matches are per root |
| A `ps` stall at 31 (M7) | counted (`abstain` events) and reported per arm; it is part of the physics, not a harness failure |

---

## 11. Test plan, and the controls that are red before the fix

| # | Control | Red before | Green after |
|---|---|---|---|
| C0 | `bash tests/rig/lr-recon-rig.sh --n 3 --faults tests/rig/faults/smoke3.json` at HEAD (before the stub fix), cure only | **expected red (H, M10)**: argv-relaunched members never engage (`drive` TIMEOUT, rc 1) | the same command after 9.2-1: rc 0, DoD line matches |
| C1 | `tests/rig-stub.bats` argv-prompt case | red on today's `stub-claude.py` (`:615-616` drops it) | green |
| C2 | Sim S1-S4 | each killed by its named mutant (§9.11); record "mutant → red" in the commit message, as `6841626b4` did ("8 of 8 killed") | green on HEAD |
| C3 | G1 lint | the planted bare `getloadavg` → red; an emptied allowlist → red on HEAD's known reads | green with the seeded allowlist |
| C4 | `load_lib` fixture suite | the SIGNAL-DEAD, NO-VERDICT and XPASS fixtures each produce their exit code | — |
| **C5** | **The live pair** `run --matrix guarantee9.json --arms cure,red` at ambient | **red arm = HEAD at band 20 must FAIL** one assertion the cure passes: power. Expected through T1 and/or H3. Placer: 4 CPU-s at a 5-111× stretch fires the 120 s bound (`REPORT.md:140`, axis 06 §3); pass length at 20 was 4.9-13.6 min (`REPORT.md:89`); kitty clients at 20 cost 1-4.5 s per call (`REPORT.md:116`) | cure arm passes every hard assertion. Verdict exit 0. **If the red arm passes: SIGNAL-DEAD, exit 4, and the next step is `--red incident:58885750c`** |
| C6 | Repeat C5 with `--bg-topup` to load/core ≥ 36 | — | the same pair verdict, recorded in the 30-40 bin. This answers gap-4's open "no census ≥ 28/core" (`gap-4…:247-248`) |

Before landing, run the suites with the plan line asserted ("Gate refusal ≠ gate result"):
`bats tests/rig-stub.bats tests/lr-recon-guarantee-sim.bats tests/lr-guarantee-g1-lint.bats tests/lr-load-harness-lib.bats`, and check `1..N` in the output.

---

## 12. How it runs: land gate versus on demand

**Land gate.**
- **Suites:** `rig-stub.bats`, `lr-recon-guarantee-sim.bats`, `lr-guarantee-g1-lint.bats`, `lr-load-harness-lib.bats`.
- **Cost:** seconds.
- **Clock:** virtual, with no wall-clock bound tighter than 10 s. That matters because the gate runs bats at utility (`bin/cc-bats:752`) and postland at background QoS (`scripts/postland-verify.sh:16`), and a wall-clock test there reads the band, not the code. One example: `place.bats (j)`'s 2.5 s bound read 3.6-4.0 s under load on both trees (`69ebee15f` message).
- **Selection:** `gate-select` maps by literal paths. Edits under `tests/rig/*.py` are test-tree files with no `PATH_RE` edge (`gate-select.sh:117-119,277`), so they probably fall back to FULL (H). Check with `bash scripts/gate-select.sh --explain <base>..HEAD` before landing.

**On demand (Tier L).**
- Run by an agent or the operator, from a session pane or Bash tool, after any change to the rail.
- **Rail files:** `lr_recon/**`, `lr-*.sh`, `handoff-fire.sh` recycle path, `lr-fire-resume.sh`, `cc-tui.sh`, `capacity-admit.sh`, the plists.
- **Required as DoD evidence for:** A6, B2, B3, B5, C2 and G2.
- **The commit message cites** the run id and the verdict line. Optionally `--out docs/research/lr-sustained-load-2026-10-20/harness-runs/<id>/` keeps the JSON as evidence. That directory is written by the implementing agent, never by the harness's default path.

**Never in postland or nightly.** They run at background QoS, where the generator and the rig cannot even start (M4). A scheduled Tier-L run would need its own `ProcessType Interactive` LaunchAgent, which is an operator install; that is deferred (§15 Q4).

---

## 13. Cost on the live box

| Resource | Rig and harness add | Anchor | Guard |
|---|---|---|---|
| P-core CPU (sessions' band 31) | cure-arm rig: daemon (~2.4% of a core in production, axis 06 F-L4) + actuators (E: a few CPU-s per attempt; measured per run from `supervisor.times`) + stubs (idle `select` loops) + sampler (E: about 3% of one core: 0.3-0.5 s census every 15 s, M3) | M3, M6 | none needed |
| `--df-topup N` | N × duty (0.6) runnable at 31: sessions lose up to `N/(R31+N)` of P-core share. At R31 = 40 and N = 16, about 29% (E, proportional share) | M3 | **off by default; operator-gated (Q1)** |
| Utility band | red arm (actuators at 20) + any `--ut` top-up: competes with `cc-bats` and `qos-rewrite` demoted gates | axis 09 R2-R3 | none |
| E-cores (background band) | `--bg-topup`: bg band work (Dia renderers, Spotlight, background-QoS postland) gets a smaller share, about 50% less at +150 threads (E: 150 ambient + 150) | M3; axis 09 §2 | cap 200; off unless asked |
| Kitty fds | E: about 2.6 per window (M9: 125 fds for about 35 CHR ptys + 57 pipes); n = 9 × 2 arms + controls ≈ 21 windows ≈ +55 fds | M9 | preflight: `fds + 3 × windows ≤ 230` (the soft 256 is unverified for kitty, H) |
| Kitty coalition processes | E: 3-5 per member at peak (zsh, stub, actuator children) → n = 9 × 2 ≈ +60-90; n = 30 × 2 ≈ +200-300 | M11: 482 now (warn 500, alarm 700) | preflight refuses a projection ≥ 650; a WARN crossing is allowed (capacity-alarm only pages; "it does not ACT", `capacity-alarm.sh:70-74`; its verdict is already ALARM from the load rung) |
| Memory | E: stubs at about 10-20 MB RSS each (python 3.9 with a TUI) → n = 9 × 2 ≈ 0.2-0.4 GB | M11: 25.6 GB headroom | headroom ≥ 8 GB, segments < 45% |
| Screen | `splits` layout: ⌈n/4⌉ OS windows per arm, titled `lrh-<id>-<arm>`; focus handed back (`lr-recon-rig.sh:155-165`) | | operator Q2 |
| Wall time | n = 9: cure about 10-25 min (E, from the production pass gaps at 31, M6, and the gap-4 boot tails), red ≤ `max T_done` ≈ 58 min (§8) with early stop; sampler and generator end with the run | | `--max-s` 3600 |

`preflight` prints this table filled with the live values before any run, and refuses with NO-VERDICT and exit 3 when a guard fails.

---

## 14. Rollout and kill switch

**Rollout.**
1. **Rig fixes (9.1-9.5) and `smoke3`.**
   - Land C1, then run C0 before and after the change, cure only.
   - Exit criterion: smoke rc 0 in two consecutive runs.
2. **Tier G (9.11).**
   - The S1-S4 mutants are killed (C2), the lint is red-proved (C3), and the `load_lib` fixtures pass (C4).
   - Land the suites.
3. **Tier L (9.6-9.10).**
   - First a cure-only `guarantee9` run at ambient, reviewed by hand: every fault fired, the bands read back, the cost table is inside budget.
   - Then the C5 pair. Record the baseline verdict line in the commit message.
4. Then C6 (top-up to ≥ 36/core, if Q3 allows), and `guarantee30` once n = 9 is stable.
5. **Owner flips.** B2, B3 and A6 each edit `load-expect.json` (`target:<item>` → `hard`) in their own commit, citing a pair run that shows `XPASS` turning into a hard PASS.

**Kill switches** (all live harness state is under `/tmp`; nothing in `~/.claude*` or `~/.reso` is written):
- `bash tests/rig/lr-load-harness.sh stop` tears down every arm (stop files, then each arm's `--teardown`), stops the generator by its pidfile, and removes the lock.
- `touch /tmp/lr-harness/OFF` makes any running generator exit within 1 s and blocks new runs.
- `lr-recon-rig.sh --teardown` with `LR_RIG_ROOT=<arm root>` tears down a single arm, as today (`:92`).
- **Automatic stop:** the parent-death deadman, `--max-s`, and the §10 abort triggers (budget, memory, production cohort).

---

## 15. Operator steps

**None are required to build or run in the default mode.** That mode is ambient load, bg and ut top-up off, the main kitty, a splits layout, and both arms.

The operator asks below are rulings on cost, not blockers. Each has a safe default.

| # | Ask | Default if unanswered |
|---|---|---|
| Q1 | May `--df-topup` add up to 16 default-band threads (up to about 30% of sessions' P-core share, for ≤ 30 min) to reach `r31-high` when ambient is lower? | no; the high bin is reached only when ambient is high (it read 33-45 at 27/core, M3) |
| Q2 | May the harness open its OS windows (⌈n/4⌉ per arm) in the main kitty, as W5 did? The alternative is `--kitty private`: a second kitty instance with its own socket, which may be App-Napped to PRI 4 (M9) | main kitty, n ≤ 9 by default |
| Q3 | May `--bg-topup` reach load/core ≥ 36, halving the E-core share of background work (Dia renderers, Spotlight, background-QoS postland) for ≤ 45 min? | no; the 30-40 bin is recorded only when ambient reaches it |
| Q4 | Later, optional: install a `ProcessType Interactive` LaunchAgent for a weekly Tier-L run. Exact plist not designed here | on demand only |

---

## 16. Dependencies on other items

- **B1 depends on no item to be built.** It measures HEAD as it is.

**Items whose verification uses B1:**
- **A6, restart safety.** T4 and sim S5 flip to hard. The `kill9_post_transplant` fault reproduces the incident's self-claim refusal.
- **B2, bounded pass.** T2 and T3 flip to hard. `band.log` gaps and the per-phase timings B2 adds are read here.
- **B3, deadline override.** T1 flips to hard, and §5's bound becomes enforced.
- **B4, cheap place.** It cannot be proven by the rig, whose placer is a CPU-burn model. Its own corpus benchmark gives a new `cpu_s` value, which is then re-run here.
- **B5, kitty off the critical path.** Measured by the `kitty-slow` fault and the per-lane attempt→engaged numbers.
- **B6, telemetry.** It can lift `tests/rig/runq.py` (the base-priority census) into `lr_recon`.
- **B7, the pass-`now` audit.** Covered by sim S1-S3. B7's "advance the wall clock inside one pass" helper can be shared with `test_guarantee_sim.Sim`.
- **B8, kitty hygiene.** The `kitty-napped` bins and the kitty band in every sample show B8's effect when run with the screen locked.
- **C2, socket prompt.** Needs a messaging-socket stub (C2's own scope) before the harness can show it.
- **G2, self-recovery.** Uses the `stop_failure_hook` seam (9.2-8) to run the real StopFailure path in the rig.
- **A7, limited cohort ruling.** Phase 2, T5, needs the move lane in the rig. That means a rig poller stand-in with `LR_LAUNCHCTL_BIN` (`lr-reset-poller.sh:320`) and `launchctl` and `osascript` shims on the rig PATH. Without them, `cc-lr move` and the poller's watchdog would `kickstart` the **real** poller or reconciler (`bin/cc-lr:1731-1745`; `lr-reset-poller.sh:330`).
  - M12 shows `recon/autorecover.on` is now set in production, so A7's premise needs re-reading first.

**Not testable by this harness:** D1 and D2 (routing and shedding policy, no burn model), and C1 (credential flip, fake `claude`).

---

## 17. Effort and LOC (E: per-file estimates summed)

| Part | LOC |
|---|---|
| `lr-recon-rig.sh` changes | 95 |
| `stub-claude.py` knobs and argv prompt, plus 2 fixtures | 190 |
| `fake-claude-accounts.py` | 60 |
| `rig_lib.py` | 130 |
| `kitty-slow` | 40 |
| `runq.py` | 130 |
| `loadgen.py` | 200 |
| `load_lib.py` | 550 |
| `lr-load-harness.sh` | 330 |
| matrices, expect file, allowlist | 110 |
| `test_guarantee_sim.py` and its bats | 400 |
| G1 lint bats | 90 |
| `load_lib` bats and fixtures | 220 |
| `rig-stub.bats` additions | 70 |
| **Total** | **≈ 2,600**, of which about 780 are test code. Effort M+, about 3-4 agent-days including the first live pairs |

---

## 18. Risks and open questions

1. **The red arm passes at ambient (SIGNAL-DEAD).**
   - Possible, because the waves removed the load-wait logic. At 20 the remaining costs are band-only, and the rig's actuator CPU is small.
   - Mitigation: `--red incident:58885750c`, or a C6 top-up.
   - SIGNAL-DEAD is honest information about the waves' effect, not a harness failure.
2. **Fidelity gaps.**
   - Stub boots are cheap until `boot_cpu_s` is calibrated (E). The placer is a CPU model, with the cost taken from axis 06.
   - So the cure arm's `T_att` is optimistic against production: 46-212 s boot plus first turn at 30-40/core (gap-4).
   - T1 and T3 will be re-checked once real numbers exist.
3. **Cross-arm isolation is argued, not yet shown** (H): two rig daemons, one kitty. The P4 audit (0 foreign records per arm) is the evidence, checked on the first pair run.
4. **Kitty budgets.** Kitty's real `RLIMIT_NOFILE` is unverified, and the splits layout's interplay with `kitty-fullscreen-guard` (`ae020a953`) is unverified. Watch the first run with `--n 3`.
5. **The composer-unreadable fixture must actually be unreadable** to the real reader. If it is not, P3 marks the fault as not fired; it never silently passes.
6. **Statistics.** n = 9 per arm per run is small. Use p90 and max per run plus `analyze` across runs. The cross-load slope test is report-only.
7. **Edits under `tests/rig/*.py` probably trigger a FULL land gate** (H, §12).
8. **The admission docstring is stale.** It still calls the CPU brake "this module's load gate" (`admit.py:220-222`) after A4. That is not B1's to fix, and the lint does not read docstrings.

---

## 19. Conviction: 75%

The design needs no production change and no operator step to pin bands. Both key mechanisms, band readback and self-demoting load threads, were measured working on this box today (M1, M5).

The 25% doubt is in four places:
- the rig needs repair first (M10);
- red-arm power at ambient is not yet shown, so SIGNAL-DEAD is possible;
- two-arm isolation is argued, not yet shown;
- the fake `claude` and placer cannot reproduce boot and placer cost beyond a CPU model.

Each of these is something the harness detects and states in its own verdict. None of them can make it silently pass.

---

## Review — efficacy-under-permanent-load

**Lens.** This review asks two things:
- Does B1 actually prove, or catch a violation of, bounded recovery time at 15-40/core with every lane at PRI 31?
- Does any wait, bound or gate it adds, or certifies, assume that load falls?

**How the review was done.**
- Read-only, at worktree HEAD `28b25a119`, on 2026-10-20 between about 18:35Z and 19:05Z.
- I edited no code, typed into no pane, ran no launchctl, and signalled no process.
- I started only three probes, under `/tmp/b1-review/`: `python3 -I -c 'import json,os,sys'` at the default band, under `taskpolicy -c utility`, and under `taskpolicy -b`. The `-b` probe was still in interpreter start-up when I finished. I did not signal it.

**Verdict: NEEDS-CHANGES. Adjusted conviction: 55%** (the design says 75%).
- The two-tier shape is right, and the build needs no operator step.
- As written, though, B1 has four efficacy problems:
  1. It can return PASS while production misses the bound. The rig removes exactly the costs that grow with load.
  2. It can return NO-VERDICT on most runs, because of load swings the premise itself allows.
  3. Its G1 checks would certify a rail that still has load gates on it today.
  4. Some of its own hard assertions get looser as passes get slower.
- Every change below is confined to `tests/` and the design text. None of them needs a production edit.

### R.1 What held up

| Claim | Check | Result |
|---|---|---|
| M10: the stub drops the argv prompt | `stub-claude.py:614-617` resumes with `a[a.index("--resume")+1]` only; `lr-fire-resume.sh:1066-1078` defaults `LR_PROMPT_ARGV` on; `:1734-1736` spawns `… --resume $sid {*}$xargs {*}$aprompt` | confirmed |
| D = 6 is a constant today | `BootSlots.on_wave` (`admit.py:422`) has no non-test caller (`grep -rn on_wave scripts bin tests` finds only `admit.py` and `test_admit.py`). `limit = min(START 6, cap 12)` | confirmed. §8's D = 6 is right at HEAD |
| The pace has no load term | `admit.py` `pace_ok`; `decide` deletes its load arguments (`:283`) | confirmed |
| `band.log` gets one line per pass, written after the pass | `_band` is called after `run_pass` (`__main__.py:1837`). The wait constants are at `__main__.py:61` (`3.0, 5.0, 20.0`). The design cites `:57`, which is `MOVING` | confirmed; the citation has drifted |
| The cure arm's 60 s heartbeat wait is enough | `hb.write_now()` runs at start-up, before the first pass (`__main__.py:1822`), so only python start at 31 counts. M: 0.15 s real for `import json,os,sys` at the default band | refutation failed |
| M6 | I recomputed it from `~/.reso/limit-recover/recon/band.log` | M: 4,337 lines over 11.39 h, all `pri=31`. Gap p50 10 s, p90 13 s, p99 19 s, max 193 s. **One gap is over 180 s** |
| M7 | `events.jsonl` rows since the first `band.log` line | M: 4 `abstain` rows, "ps … timed out at 30-37s" |
| The production-cohort gate does not block today | `recon/sessions/*.json` | M: 138 records. 4 are open, all `PRE-MOVE/PARKED-REBOOT`, none `PLANNED` or MOVING |
| The load-scaled bounds are constants inside the premise | `place_timeout` is capped at 120 s from 16/core (`plan.py:358-364`). `ps_bound` is capped at 40 s from 10/core (`observe.py:90-98`) | confirmed |

### R.2 Findings and the change each one needs

**F1. S1 cannot see a load gate whose threshold is below 15/core** (Tier G, G1).
- S1 compares traces at load1 150, 250 and 400 on 10 CPUs, which is 15, 25 and 40 per core.
- A gate at 2.0/core refuses identically at all three. That is the library's default (`capacity-admit.sh:168`). So does a gate at 8/core, the old handoff-fire bound. S1 then passes.
- The named mutant (20/core) is the only kind S1 can kill.
- **Change:**
  - Use load1 levels {5, 150, 250, 400, 1000}. 0.5/core sits below every known threshold. 1000 covers the 96.8/core the incident saw (`plan.py:360`).
  - Add a second mutant: `pace_ok` requires `load/ncpu < 2.0`. It must turn S1 red.

**F2. Patching `os.getloadavg` does not reach the load reads captured as default arguments** (Tier G).
- `clock.Clock.__init__(getloadavg=os.getloadavg)` (`clock.py:82`) and `observe.ps_bound(load_fn=os.getloadavg)` (`observe.py:91`) bind the builtin when the function is defined.
- `mock.patch("os.getloadavg")` replaces the module attribute only. A future gate written the same way would read the real box's load in every S1 level. S1 would stay green, because the land gate's own load is the same at all three levels.
- **Change:**
  - S1 walks every function in `lr_recon` and fails if any `__defaults__` or `__kwdefaults__` holds `os.getloadavg`, unless the sim patches that function's parameter.
  - The G1 lint also flags `from os import getloadavg` and module-level aliases.

**F3. The sim must spawn nothing real** (Tier G at the land gate's band).
- `run_pass` still reaches real children:
  - `store.proc_lstart`, a real `ps`, with a bound, which reads `""` on timeout (`store.py:530-546`, from `_own_and_charge`, `__main__.py:1061`);
  - `_run_snap`, the composer snapshot through kitty (`__main__.py:567-578`);
  - `_provenance`'s `Popen` (`__main__.py:529`).
- In `cc-bats` (utility, `bin/cc-bats:752`) or postland (background QoS) at 15-40/core, those bounds fire on some runs and not others. S1 then differs because of band, not code.
- **Change:** a tripwire. Patch `subprocess.Popen`, `subprocess.run`, `lr_recon.clock.run_bounded`, `store.proc_lstart`, `_run_snap` and `_provenance` to raise. A real child fails the case before any trace is compared.

**F4. Corrections to S2, S3 and S4, so that their mutants actually die.**
- **S2.** `BootSlots.START = 1` kills only members with k ≥ 2. Member k = 1 waits one `T_att`, and that is within `2·P + ceil(1/6)·T_att`. The cohort must also:
  - have k ≥ 7, to reach `ceil(k/6) = 2`;
  - use `T_att_sim > PACE_EVERY_S` (20 s), or the pace dominates and S2 reds on correct code.
- **S2, the dead AIMD.** `on_wave` would halve D on any boot over 45 s (`admit.py:356-364`). Boots at 30-40/core run 46-250 s (gap-4:45-50), so wiring it would cut D to the floor of 2 at load. S2 must assert `ctx.boots.limit == 6` on every pass, so that wiring it turns S2 red.
- **S3.** The backoff runs 10, 30, 60, 120, 240, then 300 (`classify.py:172-173`). A cap-900 mutant first differs at the 6th consecutive TRANSIENT failure. S3 must drive at least 6.
- **S4.** `keep_waits` changes behaviour once misses exceed `KEEP_MAX_MISSES = 3` (`plan.py:54`, `:371-373`). Exactly 3 rc-124 passes stops at the boundary. Drive at least 5.

**F5. The restore budget and the drip are never exercised, in the rig or the sim.**
- The restore budget and the drip are the admission paths that bind when the fleet is busy (`admit.py:234-260`).
- `_active_now` counts only snapshot sessions (`__main__.py:1088-1092`), and the rig refuses every non-rig sid (`observe.py:576`). So in the rig, active stays far below R.
- **Change:**
  - Add a sim case S2b: active above R. Each member's first spawn comes within `DRIP_AFTER` passes plus its queue position × `DRIP_EVERY_S`.
  - Add a rig knob `busy_extra: N`: N extra rig stub panes held WORKING, so the live daemon refuses on the restore budget and drips.

**F6. The fake `claude` boots in milliseconds, so the bounds that load actually stretches never fire** (risk of a false PASS).
- Production boot plus first turn, at PRI 31 (gap-4:45-50):

  | Load | Median | p90 |
  |---|---|---|
  | 30-40/core | 46 s | 212 s |
  | ≥ 40/core | 168 s | 250 s |

- That crosses the 180 s READY wait (`a24255bf6`) and feeds `LAUNCHER_CHAIN_MAX_S` = 600 s (`settle.py:756`).
- `boot_cpu_s` calibrates CPU time only, not boot wall time.
- **Change:**
  - Draw `boot_delay_s` per member (the stub already sleeps on it in `resume()`) from gap-4's distribution for the run's measured load bin.
  - Add a `slow-boot` group with `boot_delay_s` in [190, 300] s, expect ENGAGED.
  - Until then, T3 (`T_att,obs ≤ 900`) is vacuous in the rig. B2 must not flip T3 to hard on rig evidence alone.

**F7. P2 makes the verdict depend on load staying in one bin.**
- M2 itself shows 27.9/core falling to 15.3/core in about 10 min. A 60-75 min run will rarely keep 70% of its samples in one bin.
- Under `--level ambient`, "the declared bin" is undefined. "Re-run later" then means waiting for load to sit still.
- **Change:**
  - P2 holds when, on at least 70% of samples, load1/ncpu ≥ 15 (the premise floor) and r31 ≥ 1 per P-core.
  - Bins become tags on each attempt: r31 and load1 at its spawn, and over its wall interval.
  - `analyze` stratifies attempts, not runs.

**F8. H4 and H6 stretch with the load they are meant to judge.**
- Both bounds use `2·P_obs`. A slow pass widens its own bound, so H6 can never fail because passes were long. That is load coupling inside an assertion.
- H6 also ignores admission queueing. After a failure, a retry may correctly wait for:
  - a boot slot (6 of them, held while any BOOTING actuator lives, `__main__.py:1123-1129,1139`);
  - a pace token (one per 20 s after the burst of 6);
  - the per-account pacer (3 per account, released after 20 s);
  - the restore budget or the drip.
- With 9 members and 6 slots, correct code fails H6.
- **Change:**
  - The hard H6 is counted in passes: the next spawn comes no later than the 2nd pass boundary (from `band.log` or the heartbeat) after `next_eligible_at`. Intervals that an `admit-refused` or `boot-slots` event names are subtracted.
  - Those waits get their own bound: a slot wait ≤ `ceil(k/6)·T_att,obs`, and a pace wait ≤ 20 s × queue position.
  - The seconds form uses `P_max` = 180 s and is a target owned by B2. H4 gets the same change.

**F9. H1 misses the load holds that are actually on the rail.**
- H1 greps only for `HELD:load|HOLD-LOAD`.
- The R lane through `act.cmd_replace` (`act.py:247-254`, chosen at `__main__.py:1372-1373`) runs `boot-resume-launch.sh:429` `cc_capacity_admit` with no `CC_ADMIT_LOAD_TERM`.
- The library defaults the load term **on** (`capacity-admit.sh:1305,1440-1447`), with a ceiling of 2.0/core. At 15-40/core it therefore refuses on load until the unkeyed 3-refusal budget releases.
- `classify.py:71-73` maps that text ("capacity-admit: REFUSING … load") to **WAIT**. So no `HELD:load` is ever written, and H1 passes.
- `bin/reso-resume-one:306` makes the same bare call.
- **Change:** H1 also counts:
  - the capacity library's load refusals, from the arm HOME's capacity-admit ledger and the actlogs (`/core > ceiling`, a refuse row whose term is load);
  - `hf_recycle_load_gate`'s hold text (`handoff-fire.sh:4183-4194`).

**F10. The G1 lint's scope and its Rule 3 leave live load reads out.**
- **Add to the scan set:**
  - `scripts/boot-resume-launch.sh` and `bin/reso-resume-one` (F9);
  - `bin/cc-lr` `cl_self_wait_s`, which is 900 s × min(4, 1 + load/5), so 3600 s across the whole premise (`bin/cc-lr:330-341`);
  - `lr-lib.sh`, `lr-reset-poller.sh`, `lr-fleet.sh`, `scripts/lib/capacity-admit.sh`, `bin/cc-wave-plan`, `bin/cc-dispatch`;
  - `bin/claude-accounts`'s `--place`/`--rank` code. The rig fakes it, so only the lint can see it.
- **Rule 3:**
  - A bare `cc_capacity_admit` or `cc_capacity_probe` call is a violation, because the library defaults the load term on.
  - A `${X:-off}` form, as in `lr-fire-resume.sh:905` and `lr-lib.sh:517,534`, passes only if no rail environment (plists, `actuator_env`, the rig's `env.sh`) sets X.

**F11. The "harm-gate-typed" allowlist row certifies a gate that waits for load to fall.**
- `hf_recycle_load_gate` holds a typed relaunch above 24/core at the commit and 20/core at the precheck (`handoff-fire.sh:4159-4194`). That covers most of the premise's range.
- `HOLD-LOAD` is re-probed every 120 s and never releases while load stays up (`settle.py:60,78`; `types.py:130`).
- Allowlisting it turns C3 green while G1 is violated.
- **Change:**
  - Allowlist classes become `telemetry`, `capped-bound-stretch` and `debt:<owner>`. A `debt` row is printed by the lint and in the verdict line ("G1 debt 1"). It is never silent.
  - Add a live group `typed-relaunch` (member env `CC_PANE_SUCCESSOR=off`) so the harness can show whether `HOLD-LOAD` ever releases at ambient load.
  - The operator ruling (decision `600709c5fe4b`, 10-19) predates the binding premise. Re-asking it is the operator's step.

**F12. Bound-stretch rows must be capped.**
- `clock.load_multiplier` is `max(1, load1/ncpu/2)`, with no cap (`clock.py:156-164`): ×20 at 40/core. It has no caller (`grep -rn load_multiplier scripts bin` finds only the definition).
- **Change:** the lint requires every bound-stretch function to return `min(MAX, …)`. It flags `load_multiplier` as dead and uncapped instead of seeding it as an allowed row.

**F13. The run-length bounds are fixed, and they are shorter than the run.**
- For `guarantee9`, `max T_done` = go + 300 (the busy member's `t0`) + 600 + 180 + 2·900 + 900 = **go + 3,780 s**.
- The red arm's heartbeat wait (up to 600 s) and the boot wait come on top, about 75 min in total. That is more than `--max-s 3600`.
- `guarantee30` needs about go + 6,300 s.
- The sampler and generator stop at 3,600 s. Gaps in the red arm's samples then fail P2 exactly when H3 would establish power.
- **Change:** `max-s` = heartbeat wait + boot wait + `max T_done` + teardown margin, computed from the matrix.

**F14. P1 cannot see short-lived children.**
- A 5 s sampler misses almost every `ps`, `kitten`, place and probe child, which live for seconds.
- The 95% `band.log` tolerance also hides real demotions in an arm whose band the harness itself controls.
- **Change:**
  - The fake placer and the stub (both python already) record `band.base_priority(os.getpid())` on every invocation, and P1 reads those in-path records.
  - Cure arm: 100% of `band.log` lines at 31. Any line below 31 is a G4 FAIL, reported with its line.

**F15. The kitty-slow fault measures the fault more than the rail, and its wrapper adds execs.**
- With U(2, 15) s on every matching call, a 3 s-bounded call succeeds only when the draw is under 3 s: probability 1/13, about 8% (E, uniform). Every retry draws again.
- So the member engages largely by luck, and a cure-arm H3 FAIL would be the fault's doing.
- The wrapper also forks `awk` (twice) and `date` on faulted calls, and runs an `awk` lookup on every call that names an id whenever the fault file exists.
- At utility, one exec costs about 15× the default band. M: python start took 2.26 s under utility against 0.15 s at the default band, at load1 210 on 10 CPUs. That extra cost lands mostly on the red arm, so the instrument helps manufacture power.
- **Change:**
  - Delay only the first K calls of each attempt, or a fraction p = 0.3 of calls, so the test measures "our bound fired, then the retry succeeded".
  - Use a pure-builtin fast path: a `while read` lookup, no `awk` or `date` on calls that are not faulted.
  - Also parse `window_id:` (`lr-handoff.sh:2271`, `lr-lib.sh:1329`).

**F16. Power from a band-20 red arm only re-proves A1, and the "incident" tree is not the incident.**
- `58885750c` already contains `31f4242e0` and `20368fc85` (`git merge-base --is-ancestor` returns true for both).
- It has no `band.py` (`git ls-tree 58885750c scripts/limit-recover/lr_recon/ | grep -c band.py` returns 0), so P1, T2 and `P_obs` from `band.log` are undefined in that arm.
- **Change:**
  - Item DoD runs use `--red tree:<parent-of-item>@31`, concurrently. Power is: the item's target assertion fails on the parent and passes on the item, at the same band.
  - Pass boundaries come from the heartbeat (`progress`, `max_step_gap_s`), sampled by the harness, so they do not depend on `band.log`.
  - Name the real pre-fix tree (`31f4242e0^` = `60c87719f`), or say plainly what `58885750c` is.

**F17. T2 is optimistic in the rig.**
- The rig daemon observes 9-30 sessions. Production observes the whole fleet.
- Production already has a 193 s gap at 31 (R.1), which is over 180 s.
- **Change:** record the production `band.log` gaps for the run window beside the rig's (read-only). Judge T2 on max(rig, production).

**F18. Tier G will not meet its "seconds" cost in postland, and two of its cases are red there.**
- postland runs `tests/*.bats` minus the host manifest, at background QoS (`postland-verify.sh:16,433`; header of `host-suites.manifest`).
- Python start under each band, at load1 210-291 on 10 CPUs (M, `/usr/bin/time -p … python3 -I -c 'import json,os,sys'`):

  | Band | Python start |
  |---|---|
  | `taskpolicy -b` | **not done after 6 min 58 s**, PRI 4, 0.00 CPU-s (`ps -o pri,etime,time`) |
  | `-c utility` | 2.26 s |
  | default | 0.15 s |

- So the loadgen case ("process gone within 10 s") and the `RIG_PLACE_CPU_S` burn case in `rig-stub.bats` fail or take minutes there.
- **Change:**
  - Move both cases into the Tier-L preflight self-test, or skip them with a counted reason when `band.py $$` < 31.
  - Keep one python process per Tier-G suite.
  - Verify the `1..N` plan line under `taskpolicy -b` before landing.

**F19. Lane coverage must be stated in the verdict.**
- The rig drives only the reconciler's actuators (A, A-husk, B, C, C-retry, R).
- It does not drive:
  - the poller/move lane (wave 2's "the move worker never waits for load");
  - the dispatcher (wave 5);
  - the boot-slot store shared with `cc-lr move` (`<lr_root>/locks/swap-slots`, `__main__.py:100-104`).
- **Change:** `summary.json` and the verdict line carry `lanes: reconciler`. A pair run is never cited as DoD for a move-lane or dispatcher item.

**F20. Matrix and per-member hardness.**
- Add `target-limited` (`first_turn: limit`). It is in `matrix30.json` but `guarantee9` dropped it. It is §5's "target capped, then re-place" path, the common one when 4 accounts run hot.
- H3 for the `restart-mid-actuation` member is `target:A6` until A6 lands. The self-claim refusal is still open (`REPORT.md:175`), so a hard H3 there can turn HEAD's baseline into FAIL for A6's defect.

**F21. C0's red-proof depends on load.**
- With the prompt dropped, `launcher_settled` releases C after `LAUNCHER_CHAIN_MAX_S` = 600 s (`settle.py:756,818-823`).
- So members engage about 600 s late. They do not "never engage".
- Against `smoke3`'s 900 s timeout (`lr-recon-rig.sh:241`), whether the run is red or green depends on load.
- **Change:** assert the mechanism instead.
  - Before the fix: a `prompt-argv` note, no token record within the boot, and a C spawn at least 600 s after the relaunch.
  - After the fix: no C spawn, and the token record within the boot.

**F22. C6 cannot answer gap-4's open question.**
- `--bg-topup` adds base-4 threads on the E-cores. It raises load1, not r31 (§5 of this design says so).
- So C6 says nothing about the organic band mix at 28/core and above (gap-4:246-247).
- **Change:**
  - Re-cast C6 as the physical G1 control: load1 pushed to ≥ 36/core at constant r31 must leave the cure arm's per-attempt intervals unchanged.
  - Answer gap-4 opportunistically: arm the census whenever ambient load1 reaches 280 during any run.

**F23. The watchdog's band in the cure arm differs from production's.**
- `com.reso.lr-reconciler-watchdog.plist` sets only `StartInterval` and no ProcessType, so in production it runs at 20 (H, from axis 04 R0.3).
- The rig's cure supervisor runs it at 31 (`lr-recon-rig.sh:212`).
- **Change:** in the cure arm, run the watchdog under `taskpolicy -c utility`, so that a late kill or a ceiling kill (G6) shows up where it would in production.

**F24. How attempts are enumerated.**
- The actlog is named `sid8.attempt.ACT` and opened for append (`act.py:302-305`, `:322`).
- C and C-retry do not bump `rec.attempt`; only move actuators do (`__main__.py:1289-1297`). So a second C in the same attempt appends to the first one's file, and the file's birth time dates only the first.
- **Change:** take attempts from `ev=spawn` rows. Use the birth time only to refine the first spawn of each file.

**F25. Define H2 by outcome, not by a list of six reasons.**
- `classify.py`'s TRANSIENT allowlist (`:80-93`) has no `READY-NOT-SEEN` and no generic "timed out".
- A failure caused by load can therefore go DETERMINISTIC, then ESCALATED, then IMPOSSIBLE after `REARM_CAP` = 4 re-arms (`__main__.py:784-790`), under a reason H2 does not list.
- **Change:** zero ESCALATED or IMPOSSIBLE for any member whose matrix `expect` is ENGAGED, whatever the reason text.

### R.3 New waits, bounds and gates in B1 itself, against the premise

| Item | Does it assume load falls? | Ruling |
|---|---|---|
| Caller band ≥ 31; OFF file; lock; budget preflight (fds, coalition, memory); production-cohort gate | no | keep |
| Cure heartbeat wait 60 s; red 600 s; boot wait | no; a miss is NO-VERDICT, "unknown, retry" | keep, and report the red arm's start-up latency |
| P2 "≥ 70% in the declared bin" | **it needs load to hold still**, and the premise lets load swing from 15 to 40 | change (F7) |
| H4 and H6 at `2·P_obs` | **the bound grows with load** | change (F8) |
| `--max-s 3600` | no, but it is shorter than the run | change (F13) |
| `--bg-topup` loop on load1 | no, but load1 is a 1-minute EMA, so the control lags (H: oscillation) | drive it from the runnable census |
| Allowlisting `hf_recycle_load_gate` | **it certifies a gate that waits for load to fall** | change (F11) |

### R.4 Measurements taken for this review

| # | Command | Result |
|---|---|---|
| V1 | python over `band.log` gaps | M: see R.1, M6 row |
| V2 | python over `events.jsonl` since the first `band.log` line | M: 4 `abstain` rows, `ps` timed out at 30-37 s |
| V3 | python over `recon/sessions/*.json` | M: 4 open records, all PARKED-REBOOT |
| V4 | `/usr/bin/time -p [taskpolicy -c utility\|-b] /usr/bin/python3 -I -c 'import json,os,sys'` at load1 210 → 291 | M: default 0.15 s · utility 2.26 s · background still in start-up at 6 min 58 s (PRI 4, CPU 0:00.00) |
| V5 | `grep -c -E 'getloadavg\|vm\.loadavg\|load1\|ncpu\|load_per_core\|LOAD_PER_CORE'` per rail file | M: `handoff-fire.sh` 57, `lr-move-worker.sh` 6, `bin/cc-lr` 3, `lr-fire-resume.sh` 2. `boot-resume-launch.sh` and `reso-resume-one` 0: they read load only through the library's default |
| V6 | `git merge-base --is-ancestor` and `git ls-tree` on `58885750c` | M: it contains `31f4242e0` and `20368fc85`; `band.py` is absent |

---

## Review — correctness-and-safety

Adversarial review, 2026-10-20, worktree HEAD `28b25a119`. The lens: could the harness strand a recovery, double-move a session, lose a draft, cause split-brain, break an invariant or break an existing test? I read the cited code myself and ran only read-only commands, plus three harmless probes (R-M1 to R-M3). I edited no code, typed into no pane and ran no launchctl.

**Verdict: NEEDS-CHANGES. Adjusted conviction: 60%** (down from 75%).

The two-tier shape is right, and the band mechanism works. But the live tier has four ways to reach outside its own arm and into production or the operator's screen (S1-S4). Several hard assertions are written so that HEAD fails them by construction (C1, C3-C7, C9). Either problem would make the first live pair unsafe or its verdict meaningless.

### R0. New measurements taken for this review

| # | Command | Result |
|---|---|---|
| R-M1 | `echo caller=$$; /usr/sbin/taskpolicy -c utility /bin/bash -c 'echo child self=$$ ppid=$PPID; ps -o pid,ppid,pri,comm -p $$ -p $PPID'` | `child self=43657 ppid=43651`. The child's parent is the caller at PRI 31, and the child runs at PRI 20. So taskpolicy execs in place, and `detach`'s printed pid (`scripts/lib/detach.sh`, Popen) names the red supervisor. **§4's red-arm mechanism is confirmed.** |
| R-M2 | `a=$(/bin/sh -c 'echo $$'); /bin/sleep 5; b=$(/bin/sh -c 'echo $$'); echo $((b-a))` | **4,025 pids in about 5 s** (about 800/s). At PID_MAX 99,999 the pid space wraps about every 2 min (E, from that rate). |
| R-M3 | `ps -A -o pid= \| wc -l` · `ps -A -o comm= \| grep -c -E "claude(\.exe)?$"` | 1,606 live processes, 37 of them `claude`. A stale pid lands on a live process about 1.6% of the time per pidfile (E: 1,606 / 99,999) |
| R-M4 | `command -v flock` | nothing. **`flock(1)` is not installed** (also no `/opt/homebrew/bin/flock`). `timeout` is `/opt/homebrew/bin/timeout` |
| R-M5 | `bin/cc-kitty-socket` · `ps -o pid,pri,comm -p 853 -p 41475` | `unix:/tmp/kitty-853`; 853 at PRI 47 (main kitty), 41475 at PRI 4 (`kitty-pr3`). Today the rig picks the main kitty |
| R-M6 | `ls -la ~/.reso/limit-recover/recon/autorecover.on`; last row of `capacity-alarm.jsonl` | Confirms M12 (12:10 local) and M11 (`coal_true_procs` 482) |

### R1. Citations checked

Most cited lines are accurate at `28b25a119`. I checked about 60 `file:line` claims. These are right:
- `stub-claude.py:385,563-567,602-626`, `lr-fire-resume.sh:1734-1736`;
- `lr-recon-rig.sh:30-32,52-64,82-85,96,135-136,155-165,201-223,231,234-238`;
- `rig_lib.py:41-63,123-200,373-394,417-506,515-541`, `observe.py:50-56,221-232,576`;
- `__main__.py:541-554,1018-1036,1786-1790`;
- `plan.py:102-117,173-196,358-364`, `admit.py:51-55,216-226,281-283,336-341`, `types.py:91-103,119-133,697-706`, `act.py:301-353`;
- `cc-kitty-bin:27-29`, `handoff-fire.sh:1194-1206,13877`, `cc-tui.sh:80-92`, `lr-lib.sh:1236-1245`;
- `cc-bats:752`, `postland-verify.sh:16,433`, `capacity-alarm.sh:70-74,285,301,341-342`;
- `capacity-admit.sh:168,1382-1384`, `it2-kitty:263`, and the rules at `situational.md:62,83,115,119`.

These have drifted or are wrong:
- `bin/reso-resume-one:942` → the spawn is at **:944**.
- `__main__.py:57` is `MOVING`. The 3/5/20 s waits are at **:61** (`ACTIVE_FAST_S, ACTIVE_S, DORMANT_S`).
- H5 credits `rig_lib.audit` with "split-brain 0, lost-records 0". `rig_lib.audit` computes only double-typer and fold. Split-brain and lost-records come from `report.dod_line` (`report.py:386ff`) through `cc-lr status`.
- `clock.load_multiplier` (`clock.py:156`) has **no caller**. `grep -n load_multiplier lr_recon/*.py` finds only its def. It is dead code, not "bound-stretch".

### R2. Safety defects: the live tier can reach outside its arm

**S1. Rig successor panes can land inside the operator's own OS windows.**
- `lr-handoff`'s "fire beside" path (the R REPLACE lane, `__main__.py:1331-1334`) places its pane through `cc_place_pane` (`lr-handoff.sh:2260-2269`).
- Placement rule 2 is "a vsplit into the next OS window with room … fullest first" (`pane-placement.sh:39-41`). Its candidates are **every** OS window in the kitty instance (`:134-145`). Nothing filters them to the caller's own windows.
- The rig's own window has no room in either layout:
  - the design's `splits` layout puts 4 members per OS window, and 4 is the cap;
  - the legacy tab layout fails `room()` because it has more than 1 tab (`:122-127`).
- So the successor goes into the fullest *operator* window that has fewer than 4 panes, or into the other arm's window. It splits and resizes the operator's live sessions, and it may take focus: `CC_PLACE_FOCUS=1` when there is no `SOURCE_PANE` (`lr-handoff.sh:2263`). The operator's keystrokes, or a half-typed draft, can then go into a rig stub.
- Teardown's `cwd:` match would close the pane only at the end.
- **Required:**
  - Lay out rig OS windows so that rule 1 always holds: 1 tab and at most 2 members per OS window, which leaves room for concurrent successors.
  - Make the sampler audit every 5 s that no window whose cwd is under a rig root sits in a non-rig OS window. On a hit, abort as `NO-VERDICT containment`.
  - Add the same count, which must be 0, to P4.

**S2. Pidfile kills without an identity check, on a box that reuses a pid within minutes (R-M2, R-M3).**
- `teardown()` sends SIGCONT and then SIGTERM to `supervisor.pid` and `state/daemon.pid` with no check of who now owns the pid (`lr-recon-rig.sh:73-74`). `drive` SIGKILLs `daemon.pid` (`rig_lib.py:449-456`).
- The design adds three more such kills: `kill9_post_transplant`, `stop` (which re-runs teardown, possibly hours later) and the generator's pidfile stop.
- `daemon.pid` goes stale whenever the daemon has died and the supervisor is in its 10 s restart sleep (`lr-recon-rig.sh:216`), and after any run. At about 800 pids/s, a late teardown of 4-5 stale pidfiles signals some unrelated live process about 7% of the time (E). That process could be a production `claude`.
- **Required:** every kill by pidfile must first match the recorded `(pid, lstart)`, and the argv must contain the arm root or `lr_recon`. `runq.py` already plans `KERN_PROCARGS2`. This applies to the rig changes in 9.1/9.4, to `stop`, and to the generator.

**S3. Arms leak when the harness dies or the red arm stops early.**
- The supervisor stops only when `$RIG/stop` exists (`lr-recon-rig.sh:207`).
- Actuators are spawned with `start_new_session=True` (`act.py:320-327`), and teardown kills only the supervisor and the daemon. Live red-arm actuators (handoff-fire, lr-transplant, reso-resume-one opening new windows) outlive an early stop or abort mid-move.
- If the session that runs the harness is itself limit-recovered (likely on this box), nothing stops either arm's act-mode daemon. It keeps polling the main kitty every 3-5 s indefinitely.
- **Required:**
  - Give each supervisor its own deadman: exit when the harness `(pid, lstart)` is gone or a `$RIG/deadline` epoch (max `T_done` + margin) has passed.
  - Make teardown kill every `rig_procs(rig)` process, by verified identity, *before* closing windows.
  - Run a second sweep about 30 s later for late R windows, and record the leftovers in `rig-result.json`.

**S4. The `--request cc-lr` path can `launchctl kickstart` the real production poller.**
- `cmd_recover_limited` → `cmd_switch_driver` (`bin/cc-lr:613`) → `launchctl kickstart "gui/$(id -u)/$POLLER_LABEL"` (`bin/cc-lr:1111-1115`). `cmd_move` does the same (`:1731-1745`).
- `launchctl` addresses the user's real launchd domain whatever HOME is, and the rig's PATH has no shim.
- The design defers the `launchctl` and `osascript` shims to A7 phase 2 (§16), but the cc-lr path is reachable in phase 1 (`--request cc-lr`, C0 on the legacy path).
- **Required:**
  - Put `launchctl` and `osascript` shims first on the rig PATH (`$RIG/bin`) for every harness run. They log their argv and do nothing.
  - Export `CC_LR_POLLER_LABEL=rig.invalid` (`bin/cc-lr:76`).
  - Make P4 report the shim log.

**S5. Focus and Spaces.**
- The rig hands focus back only once, at setup (`lr-recon-rig.sh:155-165`). Two arms running that read → launch → hand-back sequence concurrently can race. Arm B can read arm A's freshly focused rig window as "the operator's" and hand focus back to it.
- The `splits` layout makes ⌈n/4⌉ (with S1's change, ⌈n/2⌉) OS windows per arm, each on its own Space by the operator rule (`it2-kitty:263-264`). R windows mid-run never hand focus back.
- **Required:**
  - Serialize the window-opening phase across arms with the harness lock.
  - Open a control window first in every new OS window, so no member pane is ever focused.
  - Have the sampler record the focused window id each sample. When it is a rig window, count it as a focus theft, report the count in the verdict line, and hand focus back.
  - Q2 should state this cost.

**S6. The generator's kill switches all depend on its own main thread getting the GIL (H).**
- With up to 200 bg threads at base 4 on saturated E-cores, a bg thread can be descheduled while holding the GIL. The main thread at 31 then cannot run its 1 s check: parent-death, `--max-s`, `OFF` and control-file stop all stall.
- M5 tested 4-6 threads, not this configuration. M4 shows how long base-4 Python can starve.
- **Required:**
  - Add an external stop path that needs no GIL: the sampler, a separate process at 31, SIGKILLs the generator by verified `(pid, lstart)` on `OFF`, deadline or harness death. Optionally add a `/bin/sh -c 'sleep N; kill -9 PID'` backstop.
  - Make C4 run the cap configuration (`--bg 200`) for 30 s and assert the process is gone within 10 s of `OFF`, from a band-31 context only (see C11).

**S7. The production-priority gate is too narrow.**
- §9.9 gate 1 refuses only on production records that are MOVING or PLANNED. A queued production record (PRE-MOVE in BACKOFF, WAIT_* or RELAUNCHED-UNPROMPTED) is also a recovery that the operator premise bounds, and the rig's two act-mode daemons at 31 compete with it for P-core, `--place` and kitty main-thread time.
- **Required:**
  - Refuse and abort when any open, non-hard-held production record exists. This yields `NO-VERDICT production-busy`, a retry later, and never a wait.
  - At the end of the run, check read-only that `~/.reso/limit-recover/recon/sessions/` holds no record for any rig sid. Production's census does see rig `--resume` processes through `resume_leaves` (`observe_rows.py:236-254`).

**S8. The safety outcomes the lens names are not asserted.**
- H5 counts launch-lock takers per (sid, attempt). Nothing checks the *world*:
  - a double-delivered prompt (the a8ebaa7c0 risk: the stub's new argv self-submit followed by a C typed later; or a kitty-slow `send-text` that kitty executed after our 3 s timeout fired, followed by a retry);
  - a cleared draft;
  - two live holders of one sid.
- **Required** (as hard assertions, from the stub's own state and `ps`, never from the daemon's records, per the "Own records ≠ the world" rule):
  - **H7:** each attempt's submit token appears in at most one user record in the target transcript.
  - **H8:** the HOLD-DRAFT member's composer still holds its draft text at teardown. The stub records any `\x15`, `\x7f` or submit applied to a draft buffer.
  - **H9:** at the end, at most one live holder per sid, and the transcript is live in exactly one account cfg.

**S9. The `rm -rf` guard accepts `..`.**
- In a `case` pattern `*` matches `/`. So `/tmp/lrh-[0-9A-Za-z]*-red*` accepts `/tmp/lrh-a-red/../../../Users/chrisren`, and `…-cure` accepts `/tmp/lrh-a/../../Users/x-cure`.
- **Required:** `[[ "$RIG" =~ ^/tmp/lrh-[0-9A-Za-z]+-(cure|red)$ ]]`, and refuse any `..`.

### R3. Correctness defects: verdicts HEAD fails by construction, or that cannot be computed

**C1. The heavy lead cannot be placed under the matrix's own placer block.**
- Its weight is 1 + 18 = 19 (`plan.py:166-169`). `clamp_weight(19, 24)` = 19 (`plan.py:189-197`).
- With `occupied` 6 on each of next2, next3 and next4 and KMAX 24, 6 + 19 = 25 > 24 on every eligible account. So it sits in WAIT_CAPACITY forever, and H3 fails in both arms.
- With KMAX 24 the clamp (`69ebee15f`) is never exercised either.
- The fake's charge TTL is 1200 s, but the real placer uses `ASSIGN_TTL_MIN = 15.0` (`bin/claude-accounts:3811`). The real placer also honours `--unassign` voids (`:110`), which the daemon calls at 5 sites (`__main__.py:363,758,773,911,939`). The fake's `main` answers `{}` to them (`fake-claude-accounts.py:112-117`). So seats stay charged after a member closes, which gives false WAIT_CAPACITY.
- **Required:**
  - Set the occupancy so that at least one account has 19 + (n − 1) free seats, *or* lower KMAX so the clamp binds (e.g. KMAX 8, occupied 0, clamped weight 7).
  - Use a 900 s TTL.
  - Implement `--unassign` voids.
  - Key the call-ordinal sleep fault to the daemon's `--movers` calls only.

**C2. Actlog birth time is not the spawn time for a repeated actuator.**
- `act.spawn` opens `<sid8>.<attempt>.<ACT>.log` in append mode (`act.py:320`).
- `rec.attempt` is bumped only for `MOVE_ACTUATORS = (A, A-husk, B, R)` (`settle.py:33,272-279`). So a C, C-retry or HEAL retry within one attempt appends to the existing file, and its birth time stays at the first spawn. H6, and the attempt list for the C lanes, would be computed from the wrong times.
- **Required:** take the spawn list from the `ev=spawn` rows (one per spawn, with pid; `act.py:346-353`). Take each spawn's wall time from the `ProcRole.lstart` recorded in `rec.procs` (`act.py:334-336`), with the actlog birth time only as a cross-check for the first spawn.

**C3. H6 as a hard assertion contradicts HEAD's own retry schedule.**
- The following legitimately exceed `backoff + 2·P`:
  - ESCALATED records (`next_eligible_at = None`; they re-arm after `REARM_S = 900` s, `classify.py:23,193-196,205-209`);
  - WAIT_CAPACITY waits for a seat;
  - HOLD re-probes (`REPROBE_S` 120 s, `settle.py:28`).
- `backoff(n)` counts TRANSIENT failures per record, not per attempt (`classify.py:187-190`).
- **Required:**
  - Apply H6 only to exits whose disposition is BACKOFF or RETRY.
  - Measure the next spawn against the `next_eligible_at` the daemon recorded, plus 2·P_obs: the daemon keeps its own promise.
  - Assert separately that `next_eligible_at − t_exit ≤ 300` for soft classes.
  - §5's "any failed attempt" clause becomes a target owned by B3.

**C4. H4 contradicts itself on the true-busy member.**
- H4 lists true busy among the hard holds that must stay open, but §6.1 expects ENGAGED, and the pseudocode's `HARD_HOLDS` leaves it out. `MAX_AGE_S` has no busy key (`types.py:119-133`), so H4's page deadline is undefined for it.
- With `go_barrier` and autorecover, a busy stub is not limited until `go+300`, so no `HELD:busy` is ever exercised. A hold arises only on the `--request cc-lr` path.
- **Required:**
  - Drop true busy from H4.
  - Either move the busy member to a `--request cc-lr` matrix, where it is requested while WORKING, or relabel it as "late death".

**C5. H4's page deadline falls after the rig stops watching.**
- `drive` returns as soon as every member is terminal or has held its expected HOLD for 30 s (`rig_lib.py:417-430,498-499`).
- HOLD-DRAFT pages at 900 s and HOLD-BGWORK at 1200 s (`types.py:122-124`). If collection follows `drive`, those pages are never seen.
- **Required:** keep each arm alive until max(hold entry + `MAX_AGE_S` + 2·P_obs) of its held members. Otherwise mark H4 `NO-VERDICT window`, never FAIL.

**C6. H1 and the G1 allowlist disagree, and HEAD still emits `HELD:load`.**
- handoff-fire's precheck holds `HELD:load` above 20 per core whenever a move types its relaunch instead of staging it (`handoff-fire.sh:13877-13888`; bounds 20/24 at `:4159-4180`). That covers every case where the successor library fails to load or the stage is refused, which a kitty-slow fault can cause.
- §9.10 allowlists this function as "harm-gate-typed" (allowed), while H1 forbids its verdict.
- H1's regex also misses the capacity library's own load-term refusals. The `cc_capacity_admit` call in `hf_lr_admit` defaults its load term on (see C7).
- **Required:**
  - Classify the allowlist row as `violation:owner=<item>`, and expect H1 to FAIL at HEAD on any typed relaunch at 20/core or more. Alternatively, scope H1 to the reconciler and report handoff-fire's `HELD:load` as its own line.
  - Widen H1 to the library's load-refusal text.

**C7. Lint Rule 3 is red at HEAD as written.**
- `hf_lr_admit` (`handoff-fire.sh:17946`) calls `cc_capacity_admit` with no load-term variable (`:17961-17962`), so the library defaults the term on (`capacity-admit.sh:1305,1405`).
- It is fire-path only: it is skipped for a recycle and whenever an admit token is present (`:17941-17949`).
- `lr-fire-resume.sh:905` spells the switch `CC_ADMIT_LOAD_TERM="${LR_LOAD_TERM:-off}"`, and `lr-lib.sh:518,534` spells it `"${CC_ADMIT_LOAD_TERM:-off}"`.
- So C3's "green with the seeded allowlist" is false. The builder would be pushed to edit `handoff-fire.sh`, which is outside B1's file list.
- **Required:**
  - Anchor Rule 3 on the same function allowlist, with a seed row for `hf_lr_admit` and its scope reason.
  - Name which spellings count as off, and decide whether an env-overridable default-off is acceptable.

**C8. Power via T2 alone proves pass length, not recovery outcomes.**
- At band 20, T2 (`P_obs` ≤ 180) will almost always fail in the red arm (passes of 4.9-13.6 min, `REPORT.md:89`). So power, and with it PASS, can rest on T2 alone, even if H3 and T1 cannot tell the arms apart. The red early stop makes that the likely path.
- The incident tree has no `band.py`: `git cat-file -e 58885750c:scripts/limit-recover/lr_recon/band.py` reports it absent. That arm writes no `band.log`, so its P1 and T2 must come from the sampler and the heartbeat.
- **Required:**
  - A pair PASS needs power on an outcome assertion (T1, H3 or H6). Power via T2 or T3 only prints `PASS (power: pass-length only)`, with exit 5.
  - Use the sampler as the P1 source and heartbeat gaps as the T2 source when `band.log` is absent.
  - `band.log` does not record which of the 3/5/20 s waits applied (`band.py:110-117`). So `wait_of(gap)` must subtract the minimum, 3 s, to stay conservative.

**C9. The restart member's known A6 defect would fail the whole pair at HEAD.**
- `kill9_post_transplant` reproduces the open self-claim bug (`__main__.py:1786-1790` restamps claims to the new daemon pid). H3 and H5 for that member are therefore likely to fail, and they are hard. That would make every HEAD pair `FAIL` and hide the other eight members.
- **Required:** while A6 is open, scope that member's H3 and H6 as `target:A6`. Keep its double-typer count printed in the verdict line.

**C10. C0's predicted mechanism is wrong, and C0's green criterion depends on the box's load.**
- With the argv prompt dropped, `launcher_settled` releases C after `LAUNCHER_CHAIN_MAX_S = 600` s (`settle.py:756,819-823`). C then types, and the stub accepts typed text (`stub-claude.py:453-459`). So members engage late; they do not "never engage".
- C0 would be red through the DoD line's p95 term, `p95 detect→engaged = Ns (> 120s)` (`report.py:400-404`), or through `drive` TIMEOUT. Neither proves the mechanism.
- The same fixed 120 s p95 is in the green criterion. At 15-40 per core it reads the band, not the code (lesson "a wall-clock test reads the band").
- **Required:**
  - Run C0 on the legacy rig path (no `go_barrier`, `LR_RIG_REQUEST=cc-lr`).
  - Assert the mechanism: a `prompt-argv` note, no `submitted` record, and a C spawn at least 600 s after the target holder appeared.
  - Compare the DoD line without its p95 term and report p95 beside it.

**C11. The Tier-G suites run in postland at background QoS, and postland auto-reverts.**
- postland runs `tests/*.bats` minus the host manifest (`host-suites.manifest:6-7`) at background QoS, and it auto-reverts a bisected culprit (`postland-verify.sh:14-18`).
- Under a background clamp, Python took more than 3 min just to start (M4). Two kinds of case would therefore go red there and could revert B1 or an innocent later commit:
  - the loadgen "gone within 10 s" case;
  - every new `rig-stub.bats` case that starts the stub and waits on it.
- **Required:** each such case reads `band.py $$` and skips below 20 ("Env can falsify a precondition", `situational.md:205`), or moves to Tier L. Only `test_guarantee_sim`, the lint and the fixture-only `load_lib` cases may assert in the gate.

**C12. The stub cases need a pty.**
- `Tui.key_loop` calls `termios.tcgetattr(stdin)` before its first draw (`stub-claude.py:385-386`). Under bats with `</dev/null` that raises, so C1 cannot submit anything, and the design's argv submission "after the first draw()" never runs.
- **Required:** run C1 and the other stub cases under a pty (`pty.fork` or `script -q`), ended by SIGHUP (`stub-claude.py:603`) within a stated bound.

**C13. There is no `flock` (R-M4).**
- **Required:** use a `mkdir` lock or `fcntl.flock` in `load_lib`, holding `(pid, lstart)` with stale-lock takeover.
- Without it, gate 1 either fails every run or, unchecked under `set -u` without `-e`, runs unlocked.

**C14. The cure arm must run a frozen tree.**
- The rig symlinks `~/.claude/{scripts,hooks,lib}` and `bin/*` to `$REPO` (`lr-recon-rig.sh:104,118`). A cure arm on the live worktree reads mid-run edits, and a /ship rebase there ("Ship owns the tree").
- **Required:** run the cure arm from `git archive HEAD` into `/tmp/lr-harness/trees/<sha>`, the same mechanism as the incident arm, and print the sha in the verdict line.

**C15. Death must happen once, and only in the original process.**
- `Session.spec` is read again by a resumed stub (`stub-claude.py:83-91`). A `tick()` death keyed only on `go + die_at_s` would fire again on the *target* account, unless it is guarded by `not self.resumed` and a `died_at` mark, as `first_turn_done` is.
- In `guarantee30` the idle fan-out is on. Members waiting for `go` while idle at rest on the limited source would be moved before they ever die. Their resumed stub would then die on the target, which is a second move.
- **Required:**
  - Guard the death on `not self.resumed` and on `died_at` being absent.
  - Waiting members boot WORKING, never idle, whenever `idle_fanout` is on.

**C16. S5 bundles a property that may pass with one that fails.**
- "`t_detect` unchanged / no second spawn" may hold today. "Claim stays stamped to the actuator" is A6.
- Under one `expectedFailure`, a regression of the first half is masked.
- **Required:** split S5 into S5a (hard, if it holds at HEAD) and S5b (xfail A6).

**C17. `k_r` does not match §5.**
- §5 counts *overdue* non-held records detected earlier (`REPORT.md:441`). The pseudocode counts every earlier member, which loosens T1's bound and weakens its power.
- The design also anchors T1 on `t0` (death) where §5 anchors on `t_detect`. That is stricter; state it as a deliberate deviation.

**Minor.**
- `$KITTY_REAL` is undefined under `set -u` (9.1 `write_env`).
- `kitty-slow` misses the `--match=id:N` spelling.
- The generator's `--max-s` 3600 is shorter than `guarantee30`'s max `T_done` (E: about 6,180 s for k = 29). Derive it from the run.
- S2's mutant (`START = 1`) kills only for k ≥ 2.
- The orphaned `foreign.pid` and `legacy-*.pid` sleeps are never reaped by teardown (`rig_lib.py:260-272`).

### R4. What holds up under this lens

- Cross-arm record isolation: `rig:true` plus `rig_keep` (`observe.py:576`), per-arm HOME, registry and `LR_STATE_DIR`.
- BootSlots' shared store resolves under `LR_STATE_DIR` per arm (`__main__.py:101-104`, `types.py:240`).
- The rig's watchdog is per-root and never calls launchctl (`lr-recon-watchdog.sh:54,66,75`).
- I found no machine-global `/tmp` lock in the rail scripts. A grep over `handoff-fire.sh`, `lr-*.sh`, `capacity-admit.sh` and `pane-placement.sh` found only a selfclose log path.
- `CC_TERM_KITTY` is honoured verbatim at every resolution site. The only basename check is on the kitty *server's* comm (`handoff-fire.sh:1395`), which the wrapper does not affect.
- `BootSlots.on_wave` has no caller, so D = 6 holds for S2.
- `l_open` is never read by a gate (`admit.py:115,146,153`).
- The sim's seams exist as named (`run_pass` `__main__.py:1652`; the patches at `test_midpass_progress.py:124-172`).
- No existing test is broken by the proposed `expand`, `drive` or env changes. `rig-stub.bats`' derived-line test only calls `expected_line`.

### R5. Required changes, in priority order

1. Contain placement (S1): at most 2 members per single-tab OS window, plus a containment audit and abort.
2. Make every kill identity-checked (S2), and give each arm a deadman and an actuator sweep (S3).
3. Put `launchctl` and `osascript` shims and a bogus poller label on the rig PATH now (S4). Serialize window setup across arms and count focus thefts (S5).
4. Give the generator an external, GIL-free kill path, and test it at `--bg 200` (S6).
5. Widen the production gate to any open non-hard-held record, and check at the end that production holds no record for a rig sid (S7).
6. Add H7 (no duplicate prompt), H8 (draft intact) and H9 (at most one live holder per sid), all read from the world (S8). Use a strict regex for the `rm` guard (S9).
7. Fix the placer block, TTL, `--unassign` and call ordinals (C1). Take spawn times from `ev=spawn` and `lstart` (C2).
8. Rescope H6 (C3), H4 (C4, C5), H1 and the allowlist (C6), and lint Rule 3 (C7). Scope the restart member's assertions to `target:A6` (C9).
9. Require outcome power for PASS, and add band.log fallbacks for the incident arm (C8).
10. Run C0 on the legacy path with a mechanism assertion and a load-independent green criterion (C10).
11. Make postland-safe skips below band 20 (C11), a pty stub harness (C12), a `mkdir`/`fcntl` lock (C13), a frozen cure tree (C14), death guards on the stub (C15), and the S5 split (C16). Match `k_r` to §5 (C17).
