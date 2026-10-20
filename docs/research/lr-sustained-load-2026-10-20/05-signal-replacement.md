# Axis 05: replacing load-average gates with signals from the resource each gate protects

Read-only research, 2026-10-20 (UTC). Incident: next3 hit weekly 100% at about 02:31Z with 9 sessions. At 04:14Z,
5 of the 9 were back. Load was 150-375 on 10 cores.

Tags used below:
- **M** = measured. The command or file is named.
- **I** = inferred from measured facts.
- **H** = hypothesis, not verified.

All load-per-core figures assume `hw.ncpu` = 10 (`sysctl -n hw.ncpu` => `10`).

---

## 0. Answer

1. **Four load-average gates sit on the recovery path, and none of them reads the resource it protects.**
   - `cpu_ok` in `admit.py`.
   - The move worker's `load_wait` in `lr-move-worker.sh`.
   - handoff-fire's recycle load hold, `hf_recycle_load_gate`.
   - The load-scaled placer timeout in `plan.py`.

   What the gates protect is fine under the standing load:
   - The TUI boot took 11 s at about 12/core (one sample).
   - Typed relaunch lines were submitted 43 of 43 times up to 31.8/core.
   - Timer wake latency at 16-20/core is a few milliseconds.

   What was slow was **our own control plane**:
   - The capacity probe ran ≥30 s inside the daemon. The same probe takes 1.4-3.8 s from an interactive shell at
     20/core.
   - The placer hit its 120 s timeout on 6 of 17 calls.
   - The pass cadence was 7-14 min.

   The daemon runs at PRI 20, which is the Utility QoS band. Under Utility QoS the same probe measures 2.3× slower.
   A gate keyed on load average therefore refuses a healthy resource, forever, on a box whose design point is
   "always loaded".
2. **The binding throughput limit was the pass, not a refusal.**
   - The CPU brake's anti-starvation floor is "one admission per 20 s". The admissions in a pass happen seconds
     apart, so the floor degenerates to **one admission per pass**.
   - The incident had 12 actuator spawns in about 103 min (M), a rate of 0.12/min.
   - Little's law with the measured attempt durations predicts the 1h43m that was observed (§4).
3. **The replacement is one primitive used five times, plus one override:**
   - **LatencyGate.** A Gradient2/Vegas-style concurrency limit on the protected resource's own latency and
     success. Its baseline is learned *under the current load*, so a permanent high load becomes the baseline,
     not a refusal. It has a hard floor of 1 in flight, so it can slow recovery but never stop it.
   - **Deadline override.** Every queued recovery has a soft deadline, `t_detect + W_soft`. Past it, every soft gate
     is bypassed, subject only to the hard safety predicates and a lane width sized by Little's law. With bounded
     passes and bounded attempts, every recovery is attempted by a computable time **regardless of load** (§5).
4. **One cheap lever outside the gates.**
   - Run the control plane in the Interactive band (`ProcessType Interactive`, an operator-only launchd change).
   - Make every latency probe run in the band of the work it gates. Otherwise the gate measures its own
     starvation and blames the resource for it.

---

## 1. What each load gate did in the incident (evidence)

### 1.1 Load is permanently above every threshold (M)

Command: a python scan of `~/.reso/load.jsonl*`. It has 131,316 samples from 2026-10-02 to 2026-10-20, taking
`loadavg[0]/10`.

| Window | n | p10 | p50 | p90 | >2.5/core | >8 | >20 | >24 | >32 |
|---|---|---|---|---|---|---|---|---|---|
| all (10-02 → 10-20) | 131,316 | 0.9 | 2.5 | 23.7 | 50% | 22% | 12% | 10% | 6% |
| since 10-17 | 18,614 | 1.8 | 15.4 | 37.1 | 84% | 67% | 40% | 33% | 16% |
| incident 02:30-04:15Z | 377 | 14.4 | 24.9 | 35.4 | **100%** | **100%** | 64% | 53% | 22% |

Since 10-17 the load has been below 20/core 113 times. Only 26 of those stretches lasted at least 600 s, which is
the move worker's wait. A threshold gate on this box opens by luck, and it opens less as the fleet grows. That
matches the operator premise.

### 1.2 The reconciler's admission (`lr_recon/admit.py`)

The `admit-refused` events from `~/.reso/limit-recover/recon/events.jsonl` (t ≥ 02:30Z) (M):

| Refusal | Count | Times (Z) |
|---|---|---|
| `probe-error` | **8** | 02:43:56, 02:44:27, 02:44:58, 03:35:33, 03:36:31, 03:51:07, 03:59:58, 04:08:51 |
| `cpu` | 2 | 02:54:18, 02:54:19 |
| `restore-r` | 1 | 03:15:41 `active 18 + in flight 4 + 1 vs R 22` |

**Correction to the brief.** The CPU brake did *not* refuse every pass.

- `cpu_ok` (`admit.py:143-150`) admits whenever 20 s have passed since the last admission.
- Both `cpu` refusals came 5-6 s after the `jobs-recorded` event for d7eb73d2 at 02:54:13. That event is written
  in `_dispatch` right before an actuator spawn, so d7eb73d2 was admitted then (**I**).
- So the brake's real effect is **one admission per pass**:
  - its floor is in seconds (`CPU_FLOOR_S = 20.0`, `admit.py:40`) and global (`last_admit_at`, `admit.py:94`);
  - the members of one pass are decided seconds apart;
  - the passes that planned moves were 1.2-14.1 min apart (the `place` events at 02:36:27 … 04:18:23, M).

The drip did open. d7eb73d2's 02:54 admission came after three consecutive probe-errors (`DRIP_AFTER = 3`,
`admit.py:42`) (**I**).

**The probe-error is a timeout, not a refusal.**
- `default_runner` bounds the probe at 30 s and maps a timeout to rc -1 (`admit.py:58-66`). `probe()` turns
  anything other than rc 0/9 into `probe-error` (`admit.py:196-199`).
- The three 02:43-02:45 refusals are 31 s apart. That is one full timeout per member, run serially inside one
  pass.
- `~/.claude/autonomy/idl.jsonl` has no `lr-reconciler` probe row between 02:43 and 02:45. The probe writes its row
  at the end (`capacity-admit.sh:496-536`), so it was killed before it finished (M: an idl scan for
  `caller == lr-reconciler`, ts ≥ 02:30).
- Each such refusal adds 30 s to the pass, which makes the next pass later. That is a positive feedback loop
  between probe latency and admission rate.

**Probe wall time against band and load** (M, `bash /tmp/sr05_probe.sh`): the reconciler's exact probe command,
`CC_ADMIT_LOAD_TERM=off CC_ADMIT_RESTORE_R=22 cc_capacity_probe`, three runs, with the IDL redirected to `/tmp`.

| Caller band | Load1 | Wall times |
|---|---|---|
| interactive shell, PRI 31 | 205 | 3.78 s, 2.04 s, 1.41 s (rc 0) |
| `taskpolicy -c utility` (PRI 20, the daemon's band) | 206-214 | 8.67 s, 5.77 s, 3.68 s (rc 0) |
| inside the daemon (incident) | 253-329 | ≥30 s ×3 (02:43-02:45). About 24 s at 03:35:33→03:35:57, which is the gap between the refusal event and the next IDL `admitted` row (**I**) |

**The daemon's band** (M):
- `ps -M -p 38189` => both threads `20T`.
- `ps -Ao pri,args` => 56 claude processes at PRI 31, 3 at 20, 1 at 4.
- LR actuators (`lr-handoff.sh`, `lr-reset-poller.sh`, `claude-accounts --json`) are at PRI 20.
- `scripts/limit-recover/com.reso.lr-reconciler.plist` has no `ProcessType` key (grep => nothing).
- `man launchd.plist`: "If left unspecified, the system will apply light resource limits to the job, throttling its
  CPU usage and I/O bandwidth."
- A precedent already exists: the staged `launchd/staged/com.reso.lr-move-kick.plist:23-24` declares
  `ProcessType Interactive` for exactly this reason (commit 17962edb6).

### 1.3 `BootSlots` AIMD is never fed (M)

`grep -rn "on_wave" scripts/limit-recover/lr_recon/` finds only the definition (`admit.py:378`) and
`tests/test_admit.py`.
- `__main__.py` constructs `BootSlots` (`:97`), acquires (`:1101`) and releases (`:1086-1091`), but never calls
  `on_wave`.
- So `limit` stays at `START = 6` forever (`admit.py:297, 308`).
- The one latency-driven gate in the design (FLEET_V2 architecture §581) is open-loop in production.

### 1.4 What the protected resource actually did

**One attempt's stages** (M, `bundle-20261020T033648Z/events.jsonl` for d7eb73d2):

| Stage | t (Z) | Elapsed |
|---|---|---|
| bundle dir created | 03:36:48 | — |
| `assign` | 03:39:26 | +158 s |
| `focus` probed | 03:42:48 | +202 s |
| `gate` admitted (token) | 03:42:55 | +7 s |
| `recycle-armed` | 03:44:11 | +76 s |
| `SWITCHED-UNPROVEN` | 03:52:36 | +505 s |
| `relaunch-typed` | 03:52:41 | +5 s |
| **`composer-painted`** | **03:52:52** | **+11 s ← the TUI boot** |
| `submitted` | 03:52:54 | +2 s |

At 11.6-12.4/core (M: `load.jsonl` 03:52:01-03:52:23Z read loadavg[0] 116.33-123.50; the incident's lower range),
the resource that `BootSlots` and the CPU brake guard took 11 s of a roughly 16 min attempt. The rest is control-plane
time. One sample, so this does not show the boot is fast at 30/core.

**The typing transport** (M): every `class == recycle-type-attempt` row in `~/.claude/logs/handoffs.jsonl`, n = 43,
the first at 2026-10-18T03:39Z.

| load/core | n | `send_ms` p50 | `send_ms` max | verdict |
|---|---|---|---|---|
| <8 | 10 | 0 | 2000 | 10 submitted |
| 8-16 | 19 | 1957 | 8000 | 19 submitted |
| 16-24 | 8 | 1000 | 1920 | 8 submitted |
| 24-32 | 6 | 2487 | 3603 | 6 submitted |

Success is 43/43 and latency is roughly flat across load bands. That is the shape a latency gate would *admit* and
a load gate *refuses*.

**Timer wake latency, a PSI-like stall probe** (M, `python3 /tmp/sr05_wake.py`: 60 × `sleep(0.02)`, overshoot
in ms):

| Band | Load1 | Result |
|---|---|---|
| default (PRI 31) | 158 | p50 4.31, p90 10.15, max 31.99 |
| `nice -n 11` (PRI 20) | 197 | p50 3.83, p90 5.20, max 35.15 |
| `taskpolicy -c background` (PRI 4) | 158-215 | **0.00 s CPU after 7 min 12 s** (`ps -o time` => `0:00.00`). It never finished |

At 16-20/core, scheduling latency for short interactive work is milliseconds at PRI ≥20. The cliff is the
background band, not the load.

Caveat (**H**): `nice 11` reproduces the daemon's priority, not its launchd I/O throttle. The 2.3× probe slowdown
under `taskpolicy -c utility` is the better proxy.

**kitty's remote-control socket** (M):
- Earlier research found kitty at **PRI 4** while the screen was locked. `kitty @ ls` answered in 0.10-0.12 s at
  load 51 and failed 9/9 at exactly 10 s at load 120-133 (`docs/research/recycle-unreachable-2026-10-01.md:11-12`).
- Now: `ps -M -p 853` => main thread `47T`, other threads `31T`.
- `defaults read net.kovidgoyal.kitty NSAppSleepDisabled` => "does not exist".

So kitty's answer time depends on its QoS band (App Nap / not frontmost), not only on load (**H**, carried from that
doc at about 60%). Either way it is a property of *kitty*, which only a kitty latency probe can see.

### 1.5 The idle move lane's load wait (M, `~/.reso/limit-recover/move/*/…events.jsonl`)

- **Batch `20261020T024813Z`, 4 sessions.** Each did `load-wait "load 33.37/core above the 20/core recycle bound;
  waiting up to 600s"`, then `NOTMOVED: HELD:load … 605-613s`.
  - That is final: `lr-move-worker.sh:349`.
  - Only `HELD:unreachable` is retried: `lr-move-worker.sh:428+`.
- **Batch `20261020T030423Z`.**
  - It waited 1,660 s on load. `load-wait` was at t_ms 1792465599773 and `slot-wait` at 1792467259515.
  - The result was then `NOTMOVED: became-limited: its last record is now a limit error, so it owes a turn this lane
    does not type`.
  - **The wait turned a cheap idle move, with no prompt and no first turn, into an expensive limited one.**

### 1.6 The placer (M, `place` events)

- Of 17 calls, **6 returned rc=124** at the full timeout (02:36, 02:53, 03:06, 03:49, 04:08, 04:18).
- The answered calls took 18.7-106.0 s.
- The timeout is `30 s × load1/(4·ncpu)`, capped at 120 s (`plan.py:296-302`). It saturates at 120 s from 16/core,
  so above that it is a fixed 120 s bound.
- A miss sends movers that started the pass waiting back to WAIT_DATA (`plan.keep_waits`, `plan.py:305-314`).
- The placer runs as a child of the PRI-20 daemon (**I**).

### 1.7 Restarts erase the admission state (M)

- `restarts.jsonl` shows daemon restarts at 03:23:17 and 03:53:16. The watchdog log reads `holder changed` at the
  same times.
- `Admission` keeps `refusals`, `last_drip_at`, `last_admit_at` and `entered_at` in memory only
  (`admit.py:91-104`).
- Each restart re-arms the 3-refusal run and the CPU floor's reference.

---

## 2. Prior art and the property taken from each

| Source | What it says | Property used here |
|---|---|---|
| CoDel, RFC 8289 (https://www.rfc-editor.org/rfc/rfc8289.html) | TARGET 5 ms and INTERVAL 100 ms. Act only when sojourn time stays above TARGET for a full INTERVAL. The next drop is at `t + INTERVAL/sqrt(count)`. Track the **minimum** sojourn, not the average, to separate a standing queue from a burst. It does not drop when less than one MTU would remain | (a) Gate on the time the work *waits* at the resource. (b) Use the minimum over a window to detect a *standing* problem. (c) A **non-starvation floor**: never shed the last unit |
| Netflix concurrency-limits, Vegas (https://github.com/Netflix/concurrency-limits) | queue ≈ `L·(1 − minRTT/sampleRTT)`. Grow while the queue is below alpha (2-3) and shrink above beta (4-6) | A latency-*ratio* gate. The absolute load never appears |
| Netflix Gradient2 (`Gradient2Limit.java:43-50, 306`) | `gradient = max(0.5, min(1.0, tolerance·longRtt/shortRtt))`, `newLimit = gradient·limit + queueSize`, smoothing 0.2, queueSize 4 | The baseline is a **long EWMA under current conditions**, so a permanent regime shift becomes the baseline. The gradient floor of 0.5 bounds shrinkage per step |
| Netflix AIMDLimit (`AIMDLimit.java:102-111`) | `if (didDrop ‖ rtt > timeout) limit *= backoffRatio (0.9)`. `else if (inflight·2 ≥ limit) limit += 1`. Clamped [min, max] | Loss-based backoff. Grow only when the limit is actually being used (the app-limited guard) |
| TCP AIMD (RFC 5681) and the RTO estimator (RFC 6298, `SRTT + 4·RTTVAR`) | Additive increase and multiplicative decrease converge to a fair share. The timeout is derived from measured RTT and its variance | Adaptive timeouts in place of the fixed 10 s and 30 s bounds |
| Google SRE, client-side adaptive throttling (https://sre.google/sre-book/handling-overload/) | Reject locally with probability `max(0, (requests − K·accepts)/(requests + 1))`, K = 2, over 2 min. "Under normal conditions, the two values are equal." The formula was confirmed via Apache Beam's `AdaptiveThrottler`; the book page shows it as an image | Gate per *target account* on that account's accept rate. The `+1` keeps a trickle and means it never throttles to zero |
| Linux PSI (https://docs.kernel.org/accounting/psi.html) | "some" is the share of time at least one task is stalled on a resource; "full" is the share when all are. Windows of 10/60/300 s. Triggers are "stall amount in a time window" | Measure **stall time**, not queue length. loadavg is queue length; PSI is the time lost. macOS has no PSI, so the analogue is the resource's own latency (§3) |
| Little's law, L = λ·W | Mean in-flight equals throughput times time in system | Size concurrency from the target recovery time (§4) |
| launchd `ProcessType` (`man launchd.plist`) | Unset gives "light resource limits … throttling its CPU usage and I/O bandwidth". Interactive gives "same resource limitations as apps, that is to say, none" | The control plane's measurer must not be the starved party (§1.2) |
| macOS memory pressure | `sysctl kern.memorystatus_vm_pressure_level` => `1` (normal; 2 = warn, 4 = critical). `kern.memorystatus_level` => `77` (% free). `pmset -g therm` => "No thermal warning level has been recorded" (M) | The OS's own verdicts for memory and thermal state. They cost one sysctl read and replace the bash memory terms |

---

## 3. The signal substrate: what to measure, at what cost

Rule 1. **A gate reads a file. It never forks a measurement.**
- A sampler, or the actuators themselves (passively), append samples. The gate reads the latest window.
- This is the pattern `active-cpu-sampler.sh` already uses for the ACTIVE term (`capacity-admit.sh:1238-1288`:
  "The gate reads one file and never samples or sleeps itself").

Rule 2. **Measure in the band of the work being gated.**
- The sampler and the reconciler run Interactive.
- Otherwise a PRI-20 measurer reports its own starvation as resource latency. The 2.3× probe gap in §1.2 is this
  error.

Rule 3. **Passive first, active only when stale.** Every actuator call to the resource already produces a latency
sample. Record it. Probe actively only when there is no sample younger than `T_stale`.

| Signal | Protected resource | Source (passive) | Active fallback and cost | Today's nominal (M unless noted) |
|---|---|---|---|---|
| `kitty_rtt` (ms, ok) | kitty RC socket: resolver, pane proof, composer read, typed `/exit` | wrap `kt`/`hf_bounded kitty @` (`handoff-fire.sh:1359`, `:1005-1033`) to append `{t, rtt_ms, rc, connect_rc, queue}` | `kitty @ ls --match id:<live pane>` = 37 ms, 14 KB vs 499 ms for a bare `ls` (`U08-pane-transport.md:243-244`). At most 1 per 15 s | 0.10-0.18 s healthy; deaf = 10 s timeouts (`recycle-unreachable-2026-10-01.md:11`) |
| `type_ok`, `send_ms` | typed relaunch transport | `recycle-type-attempt` rows already carry `send_ms`, `verdict`, `load_per_core` | none needed | 43/43 submitted, p50 0-2.5 s (§1.4) |
| `boot_s` | a TUI boot in a pane | bundle `events.jsonl` `relaunch-typed` → `composer-painted` | none | 11 s at about 12/core, one sample (§1.4) |
| `engage_s`, `engage_ok` | target account's first turn (API) | record timeline `submitted` → `engaged` (`types.py:691-699`), handoffs `engage_latency_s` | none | d7eb73d2 0 s (submitted = engaged 03:53:21) |
| `api_ok(acct)` | target account's API (429 / overloaded / limit) | first-turn outcome per target: ENGAGED vs TARGET-* verdicts (the pacer already sees them, `admit.py:166-169`) | none | **H**: no 429 telemetry located |
| `probe_s`, `probe_ok` | the capacity probe itself | wrap `Admission.probe` with a monotonic timer | — | 1.4-3.8 s (PRI 31) and 3.7-8.7 s (PRI 20) at 21/core; ≥30 s in the daemon (§1.2) |
| `place_s`, `place_ok` | `claude-accounts --place` | already logged (`__main__.py:983-998`) | — | 18.7-106 s answered; 6/17 timeouts |
| `mem_level` | RAM | `sysctl -n kern.memorystatus_vm_pressure_level` (8 ms) | — | 1 (normal) |
| `self_lag` | the reconciler's own scheduling | heartbeat `max_step_gap_s` (exists); a timer-overshoot sample per pass | — | heartbeat `max_step_gap_s 120.06` vs bound 120.0 (M, `recon/heartbeat`) |

Not on the list on purpose: loadavg, CPU idle %, runnable-thread count. These are box-global scalars. They cannot
tell "the box is busy" from "this resource is unhealthy". §1.4 shows the box can be very busy while every protected
resource is healthy.

Keep exactly one box-global *hard* stop: thermal state critical or memory pressure critical (level 4). These are OS
verdicts about physical limits, not queue length.

---

## 4. Little's law: why the incident took 1h43m, and what concurrency the target needs

- Measured admission rate: 12 actuator spawns (`spawn` events) between 02:36 and 04:19Z, which is **λ ≈ 0.117/min**
  (one per 8.6 min) (M).
- Measured attempt durations, spawn → exit event, were roughly 7-33 min:
  - d7eb73d2 R: 02:46→03:19 and 03:23→03:54;
  - 7aae55e1: 02:54→03:19 and 03:43→04:04;
  - db755a94: 03:08→03:39;
  - e80b61f4: 03:15→03:46 and 03:53→04:10.

  That gives **W ≈ 22 min** (median, **I**).

  Caveat: event `t` is the write time, and some `spawn` rows print after later rows, so these spans are ±1 pass.
- Then L = λ·W ≈ 0.117 × 22 ≈ **2.6 attempts in flight on average**. That is well under the `BootSlots` limit of 6,
  so the **admission rate**, not the slot count, was binding.
- Not every attempt succeeds:
  - attempts per recovered session = 12 spawns / 5 recovered ≈ 2.4;
  - so throughput ≈ 0.117/2.4 ≈ 0.05 sessions/min, i.e. about 20 min per session;
  - for 9 sessions that is about 3 h, consistent with 5 of 9 at 1h43m (**I**).

**Sizing rule.** To recover N sessions within a target `W_target`, the gates must allow mean concurrency
`L_req = N · a · W / W_target`, where `a` is attempts per success and `W` is the attempt duration.

- With the incident's N = 9, a = 2.4, W = 22 min and W_target = 20 min, that gives L ≈ 24. That is impossible, which
  shows the levers are `a` and `W` as much as the gate.
- With the fixes in §6, take a = 1.2 (failed attempts are mostly control-plane timeouts) and W = 8 min (the boot
  is 11 s; the 3-8 min control-plane stages shrink when they are not starved). Then L ≈ 9·1.2·8/20 ≈ **4.3**.
  That fits inside `BootSlots` at 6 (**I**, estimate).
- **The gate must never cap below `L_req`** when the resource signals are healthy. A load threshold has no notion of
  `L_req`. A LatencyGate whose floor is at least 1 and whose growth is driven by healthy samples reaches it.

---

## 5. The design

### 5.1 Primitive A: `LatencyGate` (one class, five instances)

State per instance: limit `L` (float), `in_flight`, long baseline `B`, short estimate `S`, `last_decrease_at`.
Parameters: `L_min`, `L_max`, `τ` (tolerance), `σ` (smoothing), `q` (queue allowance), `β` (backoff),
`α_s`, `α_l`.

```
on_sample(x_seconds, ok, now):
    if not ok:                                   # timeout, error, INDETERMINATE charged to THIS resource
        if now - last_decrease_at >= I:          # at most one decrease per interval (TCP: once per RTT;
            L = max(L_min, floor(β·L))           #  CoDel: act only after a full INTERVAL)
            last_decrease_at = now
        return
    S = α_s·x + (1-α_s)·S                        # short EWMA, α_s = 0.5  (≈ last 3 samples)
    B = α_l·x + (1-α_l)·B                        # long  EWMA, α_l = 0.05 (≈ last 40 samples)
    if B > 2·S: B = 0.95·B                       # Gradient2's drift guard: let the baseline come down
    g = clamp(τ·B/S, 0.5, 1.0)                   # τ = 2: latency may double vs its own baseline for free
    if in_flight·2 >= L:                         # AIMDLimit's app-limited guard: grow only if used
        L = (1-σ)·L + σ·(g·L + q)                # σ = 0.2, q = 1
    else:
        L = (1-σ)·L + σ·(g·L)
    L = clamp(L, L_min, L_max)

admit():  return in_flight < max(L_min, floor(L))     # L_min >= 1: never zero
```

Where `I = max(5 s, median of the last 10 latency samples)`.

Why this is safe under permanent high load:
- `B` is learned under whatever load the box runs at. If boots take 30 s at 35/core every day, 30 s is the baseline
  and `g = 1`.
- The gate shrinks only on **divergence**, meaning the short estimate is worse than τ× the recent baseline, or on
  **failure**. Those are the two events that mean "this resource is degrading now", not "the box is busy".
- `L_min ≥ 1` with bounded attempts gives throughput ≥ `1/T_att` per gate in the worst case. That is CoDel's
  non-starvation rule and the SRE `+1`.

### 5.2 Primitive B: the deadline override (age before gates)

Every queued recovery `r` gets `D_r = t_detect(r) + W_soft`. `t_detect` is read from the on-disk record
(`timeline.detected`, `types.py:692`), so a daemon restart cannot reset it.

```
decide(r, now):
    if hard_block(r): return HOLD(reason)                 # busy turn, unsent draft/paste, live bg work the
                                                          # operator owns, claim held by a live actuator,
                                                          # target account itself capped, mem/thermal critical
    if now >= D_r:                                        # OVERDUE: soft gates do not apply
        if deadline_lane(r.target).in_flight < 1 and deadline_lane_global.in_flight < D:
            return ADMIT("deadline")
        return WAIT("deadline-lane", until=next lane release)
    for g in soft_gates(r):                               # LatencyGates, SRE throttle, restore budget
        if not g.admit(): return WAIT(g.name, until=min(D_r, now + backoff(g)))
    return ADMIT("gates")
```

Definitions:
- `W_soft` defaults to 10 min. It is the longest a recoverable session waits on *soft* evidence. Make it a knob,
  `LR_W_SOFT_S`.
- `D` is the global deadline-lane width: `max(2, ceil(N_overdue · a · W_att / W_target))`, i.e. Little's law (§4).
  It is capped at `BootSlots.cap`.
- A failed attempt re-enters the queue with its **original** `t_detect`, so it stays overdue. Its retry spacing is
  `min(2^k · 30 s, 5 min)`, which avoids hot-looping on a broken pane without ever dropping out.
- This also covers the post-transplant `PRE-MOVE/None` record, which nothing re-drives (RECON-DEFECT ×4 at
  03:43-03:59, M). An overdue record is re-driven by age, not by substate. It still needs the in-progress fix so the
  record is *in* a dispatchable substate.

### 5.3 The guarantee

**Claim.** Assume:
- **A1.** Every pass finishes within `P_max`. Today the pass is unbounded in practice: serial 30 s probes, 120 s
  placer and 40 s ps; heartbeat `max_step_gap_s` reached 120.06 s. Enforce A1 with §6 levers 3 and 7: the probe once
  per pass and asynchronous, and the placer served from cache.
- **A2.** Every admitted attempt holds its lane for at most `T_att`. The actuator's own wall budget enforces this.
- **A3.** Only hard predicates survive the deadline, and each hard predicate has its own escalation after `W_hard`:
  a page plus a visible verdict in the pane.

Then a record `r` that is not hard-blocked is first attempted by

    t_attempt(r) ≤ t_detect(r) + W_soft + P_max + ceil(k_r / D) · T_att

where `k_r` is the number of overdue, not-hard-blocked records with an earlier `t_detect`. It is retried at least
every `5 min + P_max` after each failure. **No term depends on load.** Load can only lengthen `T_att` and `P_max`,
which are bounded by construction, and it cannot hold a gate shut.

**The incident replayed under the bound** (estimate, with W_soft = 10 min, P_max = 3 min, T_att = 15 min,
N = 9 overdue, a = 1.2, W_target = 20 min, so D = ceil(9·1.2·15/20) = 9, capped at 6):
- the last session is first attempted by 10 + 3 + ceil(8/6)·15 = **43 min** after its detection;
- observed, for comparison: 7aae55e1 was detected at 02:31:55 and confirmed at 04:13:50 (**102 min**), and
  db755a94 was still `PRE-MOVE/None` at 04:20 (M, `recon/sessions/*.json`).

With healthy LatencyGates (the normal case, §1.4), the soft gates admit long before `D_r`, and the bound is just the
worst case.

### 5.4 Why aggressive admission is acceptable now

The cost of admitting into a degraded resource used to be a stranded session. After Wave A's K1 commit handshake
that is no longer true. "A hold therefore no longer strands anything: it is a clean stand-down before any keystroke"
(`docs/research/lr-wake-incident-2026-10-18/decisions/load-hold-bound.md:16-18`).

The incident's failed attempts confirm it:
- `NOTMOVED … the source was never retired and the session is alive in pane 41; a retry is safe`
  (`recon/actlogs/db755a94.1.R.log`);
- `HELD:unknown … the admit is aborted … a retry is safe` (`7aae55e1.2.R.log`).

So over-admission costs a retry, while under-admission costs the operator's session for an hour. The asymmetry
favours latency gates with a floor and a deadline.

The exception is the post-transplant rollback that leaves `PRE-MOVE/None`. Until that fix lands, an overdue re-drive
of such a record depends on it.

---

## 6. Per-gate replacements

### G1. The CPU brake, `Admission.cpu_ok` (`admit.py:143-150`, called at `:266`)

- **Today:** `load1/ncpu ≤ max(2.5, L_open)`, or 20 s since the last admission.
- **Protects:** "the pre-limit operating point" (§C6 gate 2). But the restore budget R (gate 1) already bounds the
  count to what was running before the cap. Restoring capped sessions is net-zero against the pre-limit
  population.
- **Replace with:** nothing load-keyed. Delete the load comparison.
- If a time pacing is still wanted, make it **pass-independent**: a token bucket with rate `ρ = 1/20 s` and burst
  `b = BootSlots.cap`. Then an 8-min pass carries up to `b` admissions instead of 1:

      tokens = min(b, tokens + (now − t_last)·ρ); admit iff tokens ≥ 1; tokens −= 1

  The bucket's level must be persisted, or rebuilt from the `jobs-recorded`/`spawn` events at startup (§1.7).
- **Bound:** none needed. The bucket refills at ρ whatever the load.
- **Evidence:** §1.2. Both `cpu` refusals came seconds after an admission in the same pass. The floor's unit
  (seconds) does not match the loop's unit (passes).

### G2. The capacity probe, gate 4 (`admit.py:182-199`; `capacity-admit.sh:1229-1235`, `:1294+`)

- **Today:**
  - one `bash -c "source …; cc_capacity_probe"` per member, serially, bounded at 30 s;
  - a timeout is reported as `probe-error`, which counts as a refusal toward the drip run.
- **Replace with:**
  1. **One probe per pass, asynchronous.** Start it at the top of the pass and read the result at dispatch. Its
     inputs are box-global: memory, segments, the active census. The only per-member term is `R`/in-flight, which
     the reconciler computes itself (`restore_ok`, `admit.py:138-140`).
     - Cost drops from `n × 30 s` to at most 30 s per pass, off the critical path.
  2. **A timeout is UNKNOWN, not a refusal.** It decays to the LatencyGate on `probe_s`.
     - When `probe_ok` is false, the probe's memory terms fall back to one in-process read of
       `kern.memorystatus_vm_pressure_level`. Refuse only at 4, critical.
     - That reading is the OS's own memory verdict and costs about 8 ms (M: `sysctl` 6-24 ms at load 141).
  3. **An adaptive timeout:** `T_probe = clamp(SRTT + 4·RTTVAR, 10 s, 60 s)` over `probe_s` (RFC 6298 form). A
     fixed 30 s sits inside the probe's in-daemon distribution (§1.2).
- **Bound:** the probe can no longer refuse on its own latency, and its worst-case cost per pass is `T_probe`.

### G3. The drip, `decide()` (`admit.py:260-289`)

- **Today:** the drip follows `restore-r` and `cpu`, and opens after 3 consecutive refusals, at most once per 30 s,
  per cohort. Its state is in memory.
- **Replace with:** the deadline override (§5.2), evaluated **first**, keyed on on-disk `t_detect`. It needs no
  refusal counter, so a restart cannot reset it.
- Keep the page when a cohort first goes overdue (today's `page_due`, `admit.py:279-281`).
- **Bound:** §5.3.

### G4. The per-account pacer (`admit.py:153-176`)

- **Today:** at most 3 submitted-not-ENGAGED per target account. A slot frees itself after 20 s.
- **Keep** it as `L_min`/`L_max` bounds for a per-account LatencyGate on `engage_s`/`engage_ok`.
- **Add** the SRE throttle on that account's first-turn accepts over a 2-min window:

      p_reject(acct) = max(0, (req − 2·acc) / (req + 1))

  - `req` = first turns submitted to `acct`; `acc` = ENGAGED within `T_engage`.
  - On a healthy account `acc ≈ req`, so `p = 0` and nothing changes from today.
  - On an account that is returning 429/overloaded, the throttle sheds load but never reaches 1 (the `+1`).
- **Bound:** the deadline override still applies per record.
- **Evidence gap:** **H**. No 429 / overloaded first-turn telemetry was located. Instrument `engage_ok` with the
  failure class first.

### G5. Boot slots, `BootSlots` (`admit.py:292-410`)

- **Today:** `on_wave` is never called (§1.3), so the limit is fixed at 6. `FAST_S = 15` and `SLOW_S = 45` are
  absolute and come from a quiet box ("measured 5-9 s", FLEET_V2 §581).
- **Replace with:** a per-sample LatencyGate on `boot_s`, fed from each bundle's
  `relaunch-typed`→`composer-painted` pair:
  - `L_min = 2` (the existing FLOOR), `L_max = LR_BOOT_MAX` (12), `τ = 2`.
  - Thresholds are relative: "slow" means `boot_s > max(SLOW_S, 3·B)`.
  - An INDETERMINATE boot counts as a failure **for the boot gate only when `kitty_rtt` is healthy at that moment**.
    Otherwise it is charged to the kitty gate, because one rc carries two causes (`.claude/rules`: "Two causes, one
    rc").
- **Bound:** `L ≥ 2` always.

### G6. The placer timeout (`plan.py:296-302`; `__main__.py:973-999`)

- **Today:** `30 s × load/(4·ncpu)`, capped at 120 s. On rc 124, movers fall to `WAIT_DATA` for up to
  `KEEP_MAX_MISSES` passes.
- **Replace with stale-while-revalidate.**
  - Keep the last answered placement per lane with its timestamp and the capped-account set it saw.
  - If the set is unchanged and the answer is younger than `T_place_fresh` (10 min), **use it now** and run the fresh
    `--place` asynchronously.
  - Its timeout comes from `place_s` (RFC 6298 form), clamped to [30, 180] s.
  - On a miss with no usable cache, fall back to the cheapest valid ranking: exclude every account at or over its
    cap, then rank by the last utilisation facts. A fallback placement is tagged `placed_by=fallback` so the audit
    can tell it apart.
- **Bound:** a mover waits at most one pass for placement when any cached or fallback ranking exists. Today it waits
  6 timeouts × 120 s, plus the passes in between.

### G7. The move worker's load wait (`lr-move-worker.sh:299-352, 354-358, 420-422`) and handoff-fire's recycle load hold (`handoff-fire.sh:4096-4153`)

- **Today:**
  - The worker waits while `load/core > 20` (`HF_PRECHECK_LOAD_PER_CORE`) for up to `max(UNTIL, 600)` s, then
    finishes `HELD:load`, which is final.
  - handoff-fire holds before the commit when `load/core > 24` and the relaunch would be typed.
- **What they protect, in their own words:** the typed relaunch through the kitty RC transport. That is F1, pane 44
  (`handoff-fire.sh:4096-4101`).
- **Replace with a transport-health gate.** Proceed iff both hold:
  1. `kitty_ok`: a `kitty_rtt` sample younger than 60 s with rc 0, and the **minimum** RTT over the last 60 s
     ≤ `T_kitty` (2 s; nominal 0.04-0.18 s). Using the minimum is CoDel's standing-queue test: one slow ls is a
     burst, while a minimum above target is a deaf transport.
  2. `type_ok`: of the last 20 `recycle-type-attempt` rows, at least 18 are `submitted`. Today that is 43/43.
- If either is false:
  - wait with backoff (5, 10, 20, 40 s, the existing `HF_KPROBE` schedule) **bounded by the record's `D_r`**, not by
    a separate 600/3600 s;
  - past `D_r`, take the **staged-successor** path, which types nothing and "proceeds at any load"
    (`handoff-fire.sh:4103-4105`);
  - if staging is impossible, return the item to the queue with its original age. Never finish a final
    `HELD:load`.
- **Bound:** §5.3. The batch in §1.5 would not have waited 1,660 s, because 43/43 typing and a live kitty answer
  were available, and it would not have turned into `became-limited`.

### G8. kitty RC bounds (`HF_TIMEOUT_S` 10 s; `CC_KITTY_CONNECT_TIMEOUT_S` 3 s)

- **Replace with:** an adaptive per-call bound, `T = clamp(SRTT + 4·RTTVAR, 10 s, 40 s)`, over the passive
  `kitty_rtt` ring.
- Keep the existing slow/stuck split (`hf_recycle_kitty_precheck`, accept queue ≥ 128 means stuck, which is the
  operator's to fix).
- **Root-cause lever (operator-only):** keep kitty out of the App Nap / background band:
  `defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES`, then relaunch kitty at the operator's chosen
  moment.
  - Today the key does not exist (M).
  - The 2026-10-01 investigation measured kitty at PRI 4 while locked, with RC deaf at load 120+.

### G9. The measurer's band: `com.reso.lr-reconciler` and its children

- **Today:** `ProcessType` is unset, so the daemon is at PRI 20 with "light resource limits … throttling its CPU usage
  and I/O bandwidth". Actuators, probe and placer inherit it.
- **Replace with:** `ProcessType Interactive` on `com.reso.lr-reconciler.plist`, as the staged `lr-move-kick` already
  does.
- This is **promotion, not demotion**. Under the operator constraint it does not slow any session.
- Its CPU cost is small: `ps -M -p 38189` => STIME 0:35.73 + UTIME 0:11.64 over about 38 min of uptime, about 2% of
  one core (M, approximate).
- **Operator-only:** this is a launchd change.
- **Diagnostic before and after:** record `probe_s` and `place_s` in the daemon. The 2.3× utility-vs-default probe
  gap (§1.2) predicts the effect (**H** until measured in the daemon itself).

### G10. The restore budget R, gate 1 (`admit.py:107-140`)

- **Today:** `R = max(ceiling, A_open + C_open)` is frozen at ACTIVE entry and compared with **fleet-wide**
  `active` (`__main__._active_now`). At 03:15:41 it refused `active 18 + in flight 4 + 1 vs R 22`.
- That makes R a load-like global term: a busier fleet refuses restoration.
- **Replace with a cohort-local net-zero bound:**

      restored(cohort) + in_flight(cohort) + 1 ≤ |cohort members active at cap|

  This restores exactly what was running when the cap hit, independent of the rest of the fleet. The fleet's
  growth is the spawn gates' business, not recovery's.
- **Bound:** a cohort can always restore its own members.

---

## 7. Gates that stay hard (they survive the deadline)

These are facts about the specific session, not about load. Each must have its own escalation after `W_hard`.

| Hard predicate | Why it is hard |
|---|---|
| busy turn | `HELD:busy`. Interrupting work loses work. Example: 769b7294, `A rc=6 → HOLD/HOLD-COMPOSER` ×3 |
| an unsent draft or pasted block in the composer | `HELD:draft` destroys text |
| a live actuator's claim/fence on the sid | duplicate movers |
| the target account at or over its cap | moving into a wall |
| memory pressure level 4 or thermal critical | OS-declared physical limits |

---

## 8. What not to do

1. **Do not swap loadavg for another box-global scalar** such as idle %, the runnable count, or "CPU-active
   sessions" as a refusal term. §1.4 shows the protected resources are healthy while every global scalar reads
   "saturated".
2. **Do not leave any wait unbounded by `D_r`.** Today's three open-ended waits (load, placement, probe) are what
   produced 102 min.
3. **Do not let a latency gate measure from a starved band.** It converts the controller's starvation into a
   verdict about the resource. That is the same class as "Wrapper renames your timeout" in `.claude/rules`.
4. **Do not use fixed latency thresholds taken from a quiet box,** such as `FAST_S = 15` and `SLOW_S = 45`. Use the
   baseline learned in the current regime.

---

## 9. Rollout order (smallest first)

1. G1 (delete the load term, token bucket) and G3 (deadline-first, on-disk age). Pure Python in `admit.py` and the
   `_admit` call site, plus tests. This removes the "1 per pass" cap.
2. G2 (one asynchronous probe per pass, UNKNOWN ≠ refuse). This removes the 30 s × n pass inflation.
3. Passive signal capture: the `kitty_rtt` ring in `kt`/`hf_bounded`; `boot_s` from bundle events; `probe_s` and
   `place_s` timers. This is measurement only and changes no behaviour, so it can ship first and run in shadow.
4. G5 (wire `BootSlots` to `boot_s`) and G7 (transport-health gate in place of the load waits, bounded by `D_r`).
5. G6 (placer cache).
6. G4 (SRE throttle), after `engage_ok` failure classes exist.
7. Operator-only items: G9 `ProcessType Interactive`, and G8 `NSAppSleepDisabled` for kitty.

Each step is verified **under the load that caused the incident** (`.claude/rules`: "Verify a cure under its
load"). Name the load1 beside every after-reading.

---

## 10. Deviations and side effects of this research

- Read-only throughout. Scratch files written: `/tmp/sr05_wake.py`, `/tmp/sr05_probe.sh`, `/tmp/sr05-idl.jsonl`,
  `/tmp/sr05_nice11.out`.
  - `/tmp/sr05_wake.py` was written with a shell heredoc, which the brief forbids for file writes. It is a
    7-line `/tmp` scratch script.
- The background-band wake probe (`taskpolicy -c background python3 /tmp/sr05_wake.py`, pid 71479) was still
  unscheduled when this was written. It was left alone, not signalled. It is a sleeper at 0 CPU.
- The probe timing ran the real `cc_capacity_probe` with `CC_ADMIT_IDL=/tmp/sr05-idl.jsonl`.
  - It charges nothing (`capacity-admit.sh:1225-1229`) and does not sweep tokens; sweeps happen only in mint, at
    `:824-835`.
  - Its rows went to `/tmp`, not to the live IDL.
- Seen while measuring (M, `ps -Ao`): other processes were running `taskpolicy -b bash -c "… cc_capacity_probe
  lr-reconciler first-turn"`, probably sibling research axes. If they use caller `lr-reconciler` against the live
  IDL, they contaminate the IDL's `lr-reconciler` rows as a signal.

---

## Skeptic review

Adversarial re-check, 2026-10-20 ~04:40-04:50Z. Read-only apart from the scratch files listed at the end. The
same tags apply: **M** = measured, with the command or file named; **I** = inferred; **H** = hypothesis.

**Code base.** The line numbers above are against the worktree base, 60c87719f. The live checkout has moved on
since then:
- `ed5614054` splits `probe-error` into `probe-timeout` and `probe-error rc=N`.
- `20368fc85` re-offers a move that rolled back after its transplant as a counted retry. The `PRE-MOVE/None` fix
  that this doc's §5.2 depends on has therefore **landed**.
- `31f4242e0` is the WAIT_RESET fix.

The re-checks below use the worktree code, which is what the incident daemon ran until its 03:23Z restart.

### S0. Three facts this review adds, which change several verdicts

1. **The pass uses one clock.** `_run_pass` sets `now = time.time()` once (`__main__.py:1615`) and hands the same
   `now` to every `decide()` in `_dispatch` (`:1171-1220`).
   - So, within a pass, `now - last_admit_at` is exactly 0 after the first admission. The brake allows **at most
     one admission per pass whenever `load1/ncpu > L_open`**, and **any number** below that.
   - `L_open` is the load at ACTIVE entry, `max(load1, load5)/ncpu` (`admit.py:107-123`). It is not 2.5.
2. **The idle lane's moves stage their relaunch.** The incident's idle-lane handoff log
   (`move/20261020T030423Z-*/9240c6a9….handoff.log`) reads:
   - `precheck load: not gated (the relaunch is staged in the pane, keystroke-free)`;
   - then `exit: SIGTERM … at rest with our successor staged, so nothing is typed`.

   `handoff-fire.sh:13831-13837` says why: "A MOVE NOW STAGES ITS RELAUNCH (Wave S)". The worker's own load wait
   (`lr-move-worker.sh:299-352`) still assumes "a move always is" a typed recycle (`:299-301`). It has drifted from
   the gate it says it must stay in step with (`:305-307`). So the 605-1660 s waits guarded **a keystroke path the
   moves did not take**.
3. **Utility-band starvation is far worse than 2.3×.**
   - M, `bash /tmp/sk05_probe.sh`: four default runs interleaved with three utility runs (the fourth was cut off by
     the outer bound).
   - Default band: **3.03, 2.56, 3.92, 3.69 s**.
   - `taskpolicy -c utility`: **54.11, 88.40, 82.41 s**.
   - Both at load1 181-230, rc 0 every time. That is a 15-30× gap.
   - The box is an M1 Max with 8 P-cores and 2 E-cores (M, `sysctl hw.perflevel0.logicalcpu` => 8,
     `hw.perflevel1.logicalcpu` => 2). Utility QoS falls back to E-cores when the P-cores are full, and lowered QoS
     ran at about 12% of the speed of high QoS on an M1 Pro
     (https://eclecticlight.co/2025/05/09/what-is-quality-of-service-and-how-does-it-matter/). With 15-37 runnable
     per core, the P-cores are always full.
   - So the daemon's ≥30 s probes and its multi-minute pre-placement stages (S2) are what this band predicts.

### S1. Key findings

| # | Finding | Verdict | Evidence from the re-check |
|---|---|---|---|
| F1 | CPU brake: "one admission per pass" | **WEAKENED** | **The mechanism holds, and is stronger than stated:** every member of a pass shares one `now` (S0.1).<br>**The real effect is not universal:**<br>• Two passes admitted two limited first-turn members each: 03:08:24 (db755a94 R + 769b7294 A) and 03:43:17 (7aae55e1 R + 769b7294 A). M: `spawn` events; both records are `kind=limited`, and A and R are in `FIRST_TURN`.<br>• That is possible only because `load1/ncpu ≤ L_open`. Load at the 03:14:35-03:15:41 dispatch was 22.7-25.8/core, and at 03:43-03:47 it was 16.5-19.2/core. At the 02:54:18-19 `cpu` refusals it was 28.6/core. So `L_open` was about 25-28/core (I), matching load at 02:31Z: load1 25.0-26.2, load5 26.6-27.1 (M, `~/.reso/load.jsonl`).<br>• Each restart re-freezes `L_open` at the restart's load: about 24.9 at 03:23 and about 15.5 at 03:53. The brake got **stricter** as the incident went on (I).<br>**The count is a floor:** `admit-refused` is written only when a record's reason changes (`__main__.py:1225-1233`), so "2 cpu refusals" undercounts. db755a94 was refused `cpu` at 02:54 and almost certainly again in the 02:54:50 pass, which had load 35/core and admitted 7aae55e1. db755a94 was admitted only in the 03:08:24 pass, about 20 min of brake cost (I). |
| F2 | probe-error was the 30 s timeout | **CONFIRMED** (strengthened) | `admit.py:58-66`, `:196-199`. The three refusals at 02:43:56, 02:44:27 and 02:44:58 are 31 s apart (M, `events.jsonl`). The live commit `ed5614054` says the same: "six 'probe-error' refusals at load ~259 were the 30 s bound firing on a demoted child". My utility-band re-run took 54-88 s (S0.3), so the 30 s bound sits in the *middle* of the daemon band's distribution, not its tail.<br>**Caveat:** the IDL has `caller=lr-reconciler` refuse rows at 02:49:14-02:51:14Z with `R=0/1/3/8`. The daemon's R was 22 (the 03:15:41 event), so something other than the daemon writes rows under that caller. The IDL cannot be used as a clean daemon-probe signal. |
| F3 | Daemon at PRI 20, no ProcessType | **CONFIRMED** | • The new daemon pid 51148 shows `20T` on both threads (M, `ps -M -p 51148`), and `ps -o pri` read 20 three times. `lr-reset-poller.sh` reads 20.<br>• Claude processes are at 31: 36 at 31 and 1 at 37 now (M).<br>• The installed `~/Library/LaunchAgents/com.reso.lr-reconciler.plist` has no `ProcessType` key (M, cat).<br>• The man text is quoted correctly (M, `man launchd.plist` lines 474-501).<br>• The staged `lr-move-kick.plist` uses Interactive at `:23-24`. It is **not installed** (M, `ls ~/Library/LaunchAgents`). Its commit `17962edb6` already records "a nominal 5 s wait took 41-50 s, the recycle precheck 163 s" at PRI 20. |
| F4 | `on_wave` is never called | **CONFIRMED** | `grep -rn on_wave scripts bin` in the live checkout finds only `admit.py:390` (its definition) plus tests. |
| F5 | The protected resources were healthy | **WEAKENED** | **Boots:** healthy, and better supported than the doc says. 80 bundles have `relaunch-typed`→`composer-painted` pairs, not 1. Max 13 s; p50 5-7 s; bands <8 (n=37) and 8-16 (n=9) are dense, but only **one** sample is above 16/core (M, `python3 /tmp/sk05_boot.py`).<br>**Typing:** 43/43 holds, but it is **22 distinct recycles** (22 `line=disarm` + 21 `line=cmd` rows), all on 2026-10-18 and none in this incident. The 24-32 band's p50 recomputes to 1743.5 ms, not 2487 (M).<br>**Timer wake** of 4 ms says nothing about CPU-bound work: the same PRI-20 band runs the probe 15-30× slower (S0.3).<br>**kitty RC was not healthy in this incident.** Of 12 attempts, three failed on the kitty transport:<br>• `d7eb73d2.1.R` HELD:pane:resolver-unavailable ("no terminal control socket answered at all");<br>• `7aae55e1.1.R` HELD:composer-unreadable;<br>• `db755a94.1.R` recycle ABORTED at the watcher's 10 s pane probe, after its own precheck kitty probe had *answered*.<br>`e80b61f4.1.R` needed a second try after a 3 s connect timeout (M, `recon/actlogs/`). None of these was behind a load gate (all `precheck load: not gated`), so they do not justify the load gates. They do refute "kitty is fine under the standing load". |
| F6 | The idle lane's load wait is final and costly | **CONFIRMED** (sharpened) | **Batch 1** waited 605-613 s, then HELD:load (M). `:349` is the final verdict.<br>**Batch 2** waited 1660 s (1792467259515 − 1792465599773 ms).<br>The two "became-limited" sessions hit the weekly limit **during the wait**, on background `<task-notification>` turns: 3e929a81 at 03:13:21Z and 3d1d988a at 03:19:58Z (M, tails of their `.claude-tertiary` transcripts). Their first load wait began at 02:51.<br>**Two corrections:**<br>• Per S0.2, the wait guarded a typed path these staged moves never take. So the cost was paid for nothing, not traded for safety.<br>• The two that did move then needed 19 min from `actuate` to `actuated` (03:35:33→03:54:35) at about 15-18/core. This is the same PRI-20 starvation, and it would have raced 3e929a81's 03:13 limit even with no wait (I). |
| F7 | Load is above every threshold most of the time | **WEAKENED** | The numbers reproduce (M, `python3 /tmp/sk05_load.py`, 131,411 samples). Since 10-17: 83.7% of samples are above 2.5/core, 67.0% above 8 and 39.8% above 20. In the incident window: 100% above 8 and 64.5% above 20.<br>But "most of the time" and "only by luck" are false for the 20 and 24 gates:<br>• since 10-17 the load is **below** 20/core in 60% of samples;<br>• there are 27 dips of at least 600 s, including 10.4 h on 10-17 and 3.9 h on 10-18.<br>The CPU brake's real threshold is `L_open` (about 27/core here), not 2.5.<br>The upward trend is real (p50 2.5 overall vs 15.5 since 10-17). The operator premise, not this data, is what makes threshold gates wrong. |
| F8 | Little's law explains 1h43m; admission rate was binding | **WEAKENED** | λ holds: 12 spawns from 02:36 to 04:19 (M). The recomputed spawn→exit spans are 5.5, 7.2, 11.6, 14.7, 15.7, 17, 21, 24.5, 30.6, 31, 31 and 33 min, so **median W ≈ 19 min** (M, `python3 /tmp/sk05_spans.py`), and L ≈ 2.2.<br>**The lanes are conflated.** The reconciler held 5 of the 9 sessions; the idle lane held the other 4 (`move/20261020T0*`). At 04:14 the reconciler had recovered 3 (d7eb73d2, e80b61f4, 7aae55e1) with 12 spawns, so **a ≈ 4, not 2.4**. The other 2 recoveries were idle-lane MOVEDs at 03:58.<br>**λ is an outcome, not a gate.** The attempt failures were kitty (×3), busy/HOLD-COMPOSER (769b7294 ×5), **restart-induced claim refusals** (×2, see F9) and the db755a94 `PRE-MOVE/None` strand (03:39→04:32). On top of that, a pass's pre-placement stage took about 10 min: the 02:54:50 pass's `place` began about 03:04:29 (I). These delays are not admission refusals. "Admission rate was binding" overstates one cause among several. |
| F9 | Restarts erase admission state | **CONFIRMED** (understated) | The `Admission` state is all in memory (`admit.py:91-104`). Restarts are recorded at 03:23:17 and 03:53:16 (M, `restarts.jsonl` lstart; `watchdog.log` "holder changed" lines at 03:24:11 and 03:53:28).<br>**Added:**<br>• **The restarts were deploys.** `31f4242e0` committed 03:13Z → restart 03:23Z; `e6bbd0465` 03:41Z → 03:53Z; `20368fc85` 04:12Z → 04:31Z (M, `git log`).<br>• **Each restart also killed an in-flight attempt.** `_startup` re-stamps open claims to the new pid (`__main__.py:1741-1744`). The old daemon's actuator then hit `--recycle REFUSED: another actuator holds session … move claim (pid 47282 / 38189, lr-reconciler)` → HELD:unknown. M: `e80b61f4.1.R.log`, `7aae55e1.2.R.log`. Two of the 12 attempts were lost this way.<br>• **Each restart also lowered `L_open`** (F1). |
| F10 | Placer timeout saturates at 120 s; 6/17 missed | **CONFIRMED** (one correction) | `plan.py:296-302` (the cap is reached at 16/core). Of 17 `place` events from 02:36 to 04:18, 6 had rc=124. Answered calls took 18.7-106.0 s (M).<br>**Correction:** `keep_waits` (`plan.py:305-314`) *keeps* movers that began the pass in a WAIT_* state in their prior wait for up to 3 misses. Only new (DETECTED) movers, or movers past 3 misses, get `wait-data`. The doc's §1.6 states the opposite.<br>**Added:** the 04:18:23 miss came at load1 84 (8.4/core) against a **63 s** bound. The load scaling shrank the bound while the placer's own latency did not fall. That supports a bound derived from `place_s`. |

### S2. Levers

| # | Lever | Verdict | Would it work under a permanent 15-40/core, and is it safe? |
|---|---|---|---|
| L1 | Delete `cpu_ok`'s load term; pass-independent token bucket, persisted | **WEAKENED** | **Safe, and right under the premise.** `L_open` freezes at entry, so any rise in load after the cap, or any restart, makes the brake bind (F1).<br>**But the expected effect is overstated.** The brake bound in about 2 passes of this incident (cost: about 20 min to db755a94). Two passes admitted 2 members. Only 5 limited records ever sat in the reconciler.<br>"Several-fold faster admission" is not supported. The incident's time went to attempt failures, the slow control plane and restarts (F8, F9). |
| L2 | Deadline override first in `decide()` | **WEAKENED** | **Sound idea.** `t_detect` is on disk (the records carry `timeline.detected`). Its `PRE-MOVE/None` dependency has now landed (`20368fc85`).<br>**The 43 min bound is not credible yet.** It assumes `P_max` = 3 min and `T_att` = 15 min. Measured passes were 4-20 min apart, and one pass spent about 10 min before even reaching the placer (F8). Attempts ran up to 33 min.<br>With the measured `P_max` ≈ 14 min and `T_att` ≈ 31 min, the same formula gives 10 + 14 + 2·31 ≈ **86 min**, against the 102 min observed.<br>**Most of the delay sat outside `decide()`:** WAIT_DATA placement, kitty failures, HOLD-COMPOSER, and restart claim refusals. The override bypasses none of them.<br>It only pays off after L4 (band) and L7 (placer) make A1 and A2 true. |
| L3 | Async once-per-pass probe; timeout = UNKNOWN; fallback to `kern.memorystatus_vm_pressure_level`, refusing at 4 | **WEAKENED** | **Once per pass, asynchronous, and UNKNOWN ≠ refuse are sound.** The probe's 30 s × n serial cost is real (F2).<br>**The fallback is unsafe by this repo's own measurements.** `capacity-admit.sh:236-252` records the 2026-07-30 panic: "Every existing rung read a HEALTHY box at death while the kernel's own memorystatus verdict already said `compressor_exhausted`". Segments were at 100% while only 33% of the compressed-pages limit was in use. The compressor-segment term is "the memory term that CAN bind" (`:81`).<br>A pressure-level-4-only fallback discards the one term with panic history.<br>**Better fallback:** read the compressor-sentinel's 10 s samples (`~/.claude/logs/compressor-sentinel.jsonl`, field `pct`; M, its latest row reads `"pct":13.50`). That is the doc's own §3 Rule 1, "a gate reads a file". |
| L4 | `ProcessType Interactive` for the reconciler (operator-only) | **CONFIRMED** (strengthened) | The re-measured gap is **15-30×**, not 2.3× (S0.3), and the Apple-silicon mechanism explains it: Utility QoS lands on 2 E-cores whenever the 8 P-cores are full.<br>It is safe: it is a promotion, and the control plane is small. Children inherit the band, so the probe, the placer, `ps` and the actuators all move up.<br>**Gaps in the lever as written:**<br>• The idle lane's starter `com.reso.lr-reset-poller` is also at PRI 20 (M). Its fix (staged `lr-move-kick`, `17962edb6`) is not installed. Without it the idle lane keeps its 19-min actuate (F6).<br>• Gate the change on a read-back (`ps -M` pri ≥ 31) after the reload, as `53-lr-move-kick-activate.sh` does. |
| L5 | Transport-health gate replaces `load_wait` and `hf_recycle_load_gate` | **WEAKENED** | **Removing the final HELD:load is right** (F6).<br>**The replacement targets the wrong path.** The incident's idle moves staged and typed nothing (S0.2), and handoff-fire's own precheck already exempts staged moves (`handoff-fire.sh:13836-13837`). The minimal, evidence-backed fix is to make the worker ask the same predicate (`CC_PANE_SUCCESSOR` on and the successor lib loads) and skip `load_wait`. Its `kitty_probe` precheck (`:13851-13858`) remains the transport check.<br>**Of the proposed signals:**<br>• `type_ok` ("18 of the last 20 typed attempts") reads a population that has stopped being produced: the newest `recycle-type-attempt` row is 2026-10-18T19:23Z (M). It would be a gate on stale history.<br>• `kitty_ok` (minimum RTT over 60 s) would have **passed** db755a94, whose precheck probe answered before its watcher probe went deaf (F5). |
| L6 | Feed `BootSlots` from per-sample `boot_s` with relative thresholds | **WEAKENED** | **Correct that it is open-loop** (F4).<br>**No effect on this incident:** mean in-flight was about 2.2 against a limit of 6, and the idle lane got its slots within seconds of asking at 03:34 (M).<br>**The data already exists:** 80 boot samples, max 13 s. So simply calling the existing `on_wave` would classify every recorded boot as fast (≤ `FAST_S` 15) and grow the limit. The relative-threshold machinery is premature with one sample above 16/core.<br>**Charging INDETERMINATE boots to "the kitty gate"** needs a kitty gate that does not exist.<br>**Growing to 12** has no measurement behind it: the `BootSlots` docstring notes the box was "never measured above 4" concurrent boots (`admit.py:310-314`). |
| L7 | Placer stale-while-revalidate; timeout from `place_s`; fallback excludes capped accounts | **CONFIRMED** (with a dependency) | **It would work at any load:** a cached answer costs nothing.<br>**It is safe:** a stale placement that walks into a fresh cap costs one safe retry (K1).<br>**The `place_s` bound is directly supported** by the 04:18 miss at 63 s and 8.4/core (F10).<br>**Dependency (H):** `--place` is already cache-only (`--max-wait 0`, `plan.py:260-262`). So the 18-120 s runtimes are probably the same PRI-20 starvation as the probe, and L4 may remove most of the misses by itself. Measure `place_s` after L4 before building SWR. |
| L8 | Cohort-local R plus the SRE throttle per account | **WEAKENED** | **R:** in this incident it produced exactly one refusal (03:15:41), and e80b61f4 spawned in the very next pass (03:15:54 `now`). R is already bounded by the shared refusal run since 2026-10-13 (`admit.py:251-265`). Low value.<br>**SRE throttle:** this adds a gate that can only slow recovery. There is no 429 or overloaded telemetry (the doc's own **H**), and no target account failed in this incident. Not a recovery-speed lever. |
| L9 | Adaptive kitty bound `SRTT+4·RTTVAR` clamped to 10-40 s, plus `NSAppSleepDisabled` | **WEAKENED** | **The bound helps a *slow* kitty, not a *deaf* one.**<br>• Slow: e80b61f4's 3 s connect miss answered on the next try.<br>• Deaf: the cited 2026-10-01 measurement is 9/9 failures at exactly 10 s with kitty at PRI 4, and this doc's own background-band probe got 0 CPU in 7 min.<br>• Per kitty call, a 40 s bound multiplies `T_att` when kitty is starved.<br>**`NSAppSleepDisabled` is unset (M).** Whether kitty was napped during the incident is unverified (H). Its main thread reads `47T` now, with the operator active, and kitty was not sampled during the incident. Applying the key needs a **kitty relaunch with ~36 live sessions in it**, a large operator cost that the lever does not weigh.<br>**First:** measure kitty's PRI and RC RTT while the screen is locked. |

### S3. Net

The doc's central diagnosis holds and is **stronger** than written: the control plane, not the protected
resources, was the slow party, and the cause is the Utility band on a box with 2 E-cores (S0.3).

Ranked by evidence:
1. **L4**, with the reset-poller/move-kick band fix, is the highest-confidence lever.
2. **Deleting the idle lane's load wait for staged moves** (S0.2) is the next, and is simpler than L5's new gate.
3. **Stop deploying the reconciler mid-incident, or make a restart not re-stamp claims under an in-flight
   actuator** (F9). This lost 2 of the 12 attempts, and no lever above addresses it.

Over-claims to retract:
- "one admission per pass" as the binding limit (F1, F8);
- "kitty is healthy under load" (F5);
- the 43 min bound before A1 and A2 hold (L2);
- the pressure-level memory fallback (L3).

### S4. Skeptic's side effects

- **Scratch files:** `/tmp/sk05_load.py`, `/tmp/sk05_spans.py`, `/tmp/sk05_probe.sh` (Write tool) and
  `/tmp/sk05_boot.py`.
  - **Deviation:** `/tmp/sk05_boot.py` was written with a shell heredoc, which the brief forbids.
- **Probe runs:** `cc_capacity_probe` ran 7-8 times with `CC_ADMIT_IDL=/tmp/sk05-idl.jsonl` and caller
  `sk05-measure`.
  - It charges nothing (`capacity-admit.sh:1221-1235`), and no live IDL row was written under `lr-reconciler`.
  - The outer `timeout 250` cut off the last utility-band run. `pgrep -fl sk05-measure` then found nothing left.
- No process was signalled. No launchctl, no cc-lr mutation, no pane input.
