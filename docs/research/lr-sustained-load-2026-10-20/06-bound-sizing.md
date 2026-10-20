# 06 — Bound sizing on the limit-recover path under sustained load

Axis 06 of the lr-sustained-load research (incident 2026-10-20: next3 weekly-capped at ~02:31Z, 9 sessions,
5/9 back at 04:14Z, load1 150-375 on 10 cores). This pass was read-only. I measured nothing by acting on a
pane or a process. Every number below is labelled **M** (measured: the command or file is named) or **E**
(estimated: the method is named). **H** marks a hypothesis.

Code references are to the live repo `/Users/chrisren/Development/claude-infrastructure` at `20368fc85`.
That is the source `~/.claude` runs from; this worktree is at `60c87719f`.

---

## 0. Answer

1. **Most bounds on this path were sized from foreground (PRI 31) measurements, but the work runs in
   PRI 20.** The reconciler has no `ProcessType` in its plist (`scripts/limit-recover/com.reso.lr-reconciler.plist`).
   For that case, launchd "will apply light resource limits to the job, throttling its CPU usage and I/O
   bandwidth" (`man launchd.plist`, ProcessType). The measured PRI is 20:
   `ps -o pri -p <reconciler pid>` => `20` for both pid 38189 and pid 51148. It competes against ~700
   PRI-31 processes and 27 claude processes at PRI 31 (`ps -axo pri,comm`).

   Every actuator it spawns inherits that band. For example, `lr-handoff.sh --sid 3d1d988a…` and its
   `lr-transplant.sh --phase abort` were both seen at PRI 20 (`ps -axo pid,ppid,pri,…` at 04:25Z).

   In the reconciler's band, the same three sub-steps the bounds were sized on cost **5-135x** their
   foreground time (table §1). This is exactly the lesson `bound-must-fit-the-band-not-the-bench`.
2. **Load1 does not predict the cost, so load-scaled bounds cannot fit it.** Utility-band `--place`
   (identical input) took 260.8 s at load 157 and 19.9 s at load 197, one minute apart (M, §1). Over a
   week of production, answered `--place` durations at load 200-249 had a median of 18.7 s, while at load
   100-149 they reached 75.7 s (M, §3.2).
   - `place_timeout()` scales with load1. It also *shrinks* as load falls: at load 84-89 it was a 63-66 s
     bound, and the bound fired twice at 04:18Z and 04:20Z (M, events.jsonl).
   - `fire_engage_window()` saturates at 4/core, so under the operator's premise it is a constant 480 s.
3. **Several "not answering" verdicts are our own bound firing inside an interpreter start-up, then
   being read as a fact about the world.**
   - `kitty_socket_accepting` bounds a `/usr/bin/python3` fork at 3 s (`handoff-fire.sh:1460`). Python
     start-up alone measured 7.89 s in the utility band (M, §1).
   - Its rc 124 is collapsed into "not accepting" at `handoff-fire.sh:2867,2874`. That leaves
     `accepting` empty, so the resolver's retry branch (`[ -n "$accepting" ]`, :2903) never runs. The
     verdict is then `HELD:pane:resolver-unavailable` "none of the candidates would even accept a
     connection" (actlog `d7eb73d2.1.R.log`).
   - This is the `exoneration-bound-must-fit-what-it-bounds` shape: "cannot tell" is converted into a
     negative verdict.
4. **The move lane's `HELD:load` (600 s) is not a bound on work. It is a wait for "reasonable load".**
   That is the design the operator premise rules out.
   - It is also stale. Wave S (`e2d0cee07`, 2026-10-19T23:12Z) made a staged-successor move exempt from
     the load hold at the precheck (`handoff-fire.sh` 4-pre: "load: not gated (the relaunch is staged …)").
   - The move worker's copy of that bound (`lr-move-worker.sh:335-352`, `load_over`/`load_wait`) never
     got the exemption.
   - So in the incident, 9240c6a9 waited **1660 s** in `load-wait`. The precheck that followed then said
     "load: not gated" (M, `move/20261020T030423Z-next3-next2-15173/9240c6a9….events.jsonl` and
     `.handoff.log`).
   - All four idle sessions of the first batch were released as `NOTMOVED HELD:load` after 605-613 s,
     "nothing touched" (M, the first batch's `*.json`).
5. **Why `--place` takes more than 120 s.** It is cache-only and does no network or sweep. Its in-process
   cost is 4.1 s in the foreground, and **94 % of that is two corpus-growing scans**:
   - `holds()` (`bin/claude-accounts:6603`) is 65 %. It globs `projects/*/<sid>.jsonl` across ~18,300
     project dirs per account, making 109,713 `lstat` calls for 2 movers.
   - `apply_burn()` (`:4828`) is 29 %. It re-parses 14 days (41,098 lines) of the 19.3 MB utilization
     log on every call.

   In the utility band that 4 s of work becomes 20-261 s. Both scans grow without limit: project dirs
   accumulate, and the log grows. This is tell #3 of the band lesson.
6. **What to do instead.** Use bounds that measure *progress, not load*:
   - (a) Put the recovery path in the same scheduling band as the sessions it competes with.
   - (b) Delete the work that scales with the corpus.
   - (c) Bound children by liveness (CPU-time advancing), not by wall time.
   - (d) Size the residual wall bounds adaptively from their own answered durations, RFC 6298-style.
   - (e) Treat every "our bound fired" as a third state that retries at a different moment, never as a
     negative verdict.
   - (f) Remove waits for load entirely.

   §5 has the formulas and §6 the levers.

---

## 1. Measurements, foreground vs the reconciler's band (M)

Commands are in `/tmp/bs06-measure.sh`, `/tmp/bs06-measure2.sh`, `/tmp/bs06-profile.sh` and `/tmp/bs06-glob.sh`.
Each script prints `sysctl -n vm.loadavg` beside every run. "utility" is `taskpolicy -c utility`. Its
band check printed `ps -o pri=` => **20**, the same PRI as the live reconciler. Background (`taskpolicy -b`)
printed **4** and plain printed **31**.

| sub-step | band | run 1 | run 2 | run 3 | load1 at runs | ratio to fg (E: run ÷ fg median) |
|---|---|---|---|---|---|---|
| `cc_capacity_probe lr-reconciler first-turn` (the brief's exact command, rc 0) | fg (PRI 31) | 4.20 s | 2.54 s | 2.45 s | 86.5-87.1 | 1x |
| same | utility (PRI 20) | **42.81 s** | 21.03 s | 15.56 s | 122-141 | 6-17x |
| same | background (PRI 4) | started 04:30:18Z, **not finished at 04:36:45Z (>387 s)** | — | — | 208 | >80x |
| `claude-accounts --json` | fg | 1.37 s | 1.21 s | 0.81 s | 87-88 | 1x |
| same | utility | **119.80 s** | **126.87 s** | **184.53 s** | 155-177 | 99-153x |
| `kitty @ --to unix:/tmp/kitty-853 ls` | fg | 0.39 s | 0.18 s | 0.15 s | 88 | 1x |
| same | utility | 1.66 s | 1.33 s | 3.24 s | 208 | 7-18x |
| `claude-accounts --place --lane general --recovery --max-wait 0` (2 synthetic movers, empty facts dir; identical argv to plan.py:271-289) | fg | 5.39 s | 4.05 s | 7.42 s | 140-145 | 1x |
| same | utility | **260.80 s** | 19.88 s | 20.58 s | 157 / 197 / 198 | 4-48x |
| `/opt/homebrew/bin/python3 -c pass` (the reconciler's PATH python) | fg | 0.15 s | 0.14 s | 0.12 s | 140-148 | 1x |
| same | utility | **7.89 s** | 0.18 s | 0.57 s | 142-197 | 1.3-56x |
| compile `bin/claude-accounts` (11,629 lines; a script's `__main__` is never byte-cached) | fg | 0.40 s | 1.07 s | 0.77 s | 140-142 | 1x |
| same | utility | 18.47 s | 1.34 s | 4.00 s | 142-198 | 2-24x |

Two facts dominate this table.

- **The spread is the signal.** Consecutive utility runs vary 13x on `--place` (260.8 → 19.9 s) and
  44x on bare Python start-up (7.89 → 0.18 s). The variance does not track load1: the 260 s run is at
  the *lower* load. This matches the band lesson's 2026-09-20 addendum ("10-40x spread between
  consecutive runs"). No constant, and no load-proportional formula, fits that.
- **Another worker's background-band probe** of the same function (`taskpolicy -b … cc_capacity_probe`,
  pid 32123, parent 21572) was still alive after **53 min 12 s** (`ps -axo pid,pri,etime,…` at
  04:33:03Z => `32123 4 53:12`). I did not touch it.

Caveat (E): my own runs overlapped each other and another worker's runs, so they added a few runnable
threads to a run queue of 120-208. That contribution is small against the queue, but it is not zero.

---

## 2. Why the band is 20, and why it matters more than any single constant

- `com.reso.lr-reconciler.plist` sets no `ProcessType`, and `man launchd.plist` says: *"If left
  unspecified, the system will apply light resource limits to the job, throttling its CPU usage and I/O
  bandwidth."* Measured PRI is 20, which equals `taskpolicy -c utility`.
- `act.py:315-329` spawns actuators with `subprocess.Popen(..., start_new_session=True)`, with no clamp
  change, so they inherit PRI 20. Observed: `11763 … 20 … lr-handoff.sh --sid 3d1d988a…` and
  `11909 … 20 … lr-transplant.sh --phase abort`.
- The claude sessions, which are what the operator *wants* the CPU spent on, are at PRI 31
  (`ps -axo pri,comm | grep claude` => 27 at 31). Under the operator's premise the PRI-31 run queue is
  never empty, so a PRI-20 process gets only the slack. That is the 5-150x in §1.
- **Cost of lifting it (M):** the reconciler used 41.92 s CPU over 27 min 26 s of wall (pid 38189,
  `ps -o time,etime`), which is ≈2.5 % of one core of 10. Moving that to PRI 31 takes almost nothing
  from the sessions. It does stop the sessions from taking *all* of the reconciler's time.
- The darwin band memory (`darwin-qos-band-mechanics`) says an undemoted (31) child cannot be built from
  inside a demoted parent: `taskpolicy -B` does not lift it. So the fix has to be at the launchd job
  (`ProcessType Interactive`), not inside the daemon. **H:** Interactive yields PRI ≥31 for the daemon
  and its children. This is unverified because launchctl is forbidden in this pass. Positive-control it
  with `ps -o pri` after the plist change.

---

## 3. Inventory of the bounds on the recovery path

| # | bound | value | where | sized from | runs in band | what firing becomes | incident evidence |
|---|---|---|---|---|---|---|---|
| B1 | admission probe runner | 30 s flat | `lr_recon/admit.py:61-73` (`timeout=30`) | fg probe ≈2.5-4 s | 20 | `probe-timeout` / (pre-ed5614054) `probe-error`, counted as a refusal toward the drip | 7 `admit-refused … probe-error` 02:43-04:08Z (M, events.jsonl). The docstring itself records "six probe-error refusals at load ~259 were the 30 s bound firing on a demoted child" |
| B2 | `--place` | `30 × load1/(4·ncpu)` clamped [30, 120] s | `lr_recon/plan.py:55,312-318`, called `__main__.py:976-980` | 04:00Z non-answers at 264-968 | 20 | rc 124 → keep wait ≤3 misses → WAIT_DATA | 7 of 18 place passes since 00Z were rc 124. Answered ones took 18.7-106 s (M) |
| B3 | `--assign-many`, `--unassign` | 30 s flat | `plan.py:465,484` | — | 20 | rc 124, phantom not written or voided | — |
| B4 | ps census | `20 × (1 + lpc/10)` capped at 40 s, budget 90 s | `observe.py:83-99` | W7a load 87-116 | 20 | `abstain` — the whole pass decides nothing | `03:58:07 abstain ps degraded: … timed out at 40s; ps budget spent` (M) |
| B5 | snapshot | 20 s | `__main__.py:533` | — | 20 | — | — |
| B6 | kitty RC round-trip (`kt`, `kitty_socket_answers`) | `HF_TIMEOUT_S` 10 s | `handoff-fire.sh:1090,1416,1598` | "ONE IPC round-trip" | 20 when reconciler-driven | non-zero = "does not answer" | `recycle ABORTED: the terminal did not answer the watcher's pane probe for 41 (… the 10 s bound firing …)` (db755a94.1.R.log) |
| B7 | kitty connect probe | `CC_KITTY_CONNECT_TIMEOUT_S` 3 s around a `/usr/bin/python3` fork | `handoff-fire.sh:1458-1482` | fg python start ≈0.1 s | 20 | rc 124 → treated as **not accepting** at :2867/:2874 → no retry → `HELD:pane:resolver-unavailable` | d7eb73d2.1.R.log: "none of the candidates would even accept a connection" |
| B8 | resolver retry | 3 tries, 2 s backoff, **only if a socket accepted** | `handoff-fire.sh:2903` | load-197 spike measured 2026-09-20 | 20 | PARK | as B7 |
| B9 | detached kitty probe budget | 5 tries, 5/10/20/40 s, ≤120 s budget | `handoff-fire.sh:1554-1589` | ~60 s accept-burst cycles | 20 | `HELD:unreachable` | 28 `HELD:unreachable` across move/ (M, grep) |
| B10 | lr-handoff `kitty @`/osascript | `LRH_OSA_TIMEOUT_S` 15 s | `lr-handoff.sh:132-145` | — | 20 | per call site | — |
| B11 | move worker load wait | `max(600, UNTIL)` s at 20/core | `lr-move-worker.sh:335-352` | — (a wait, not a work bound) | caller's | `NOTMOVED HELD:load … nothing touched` | 4 of 4 idle movers in batch `…024813Z…` held 605-613 s at 33-38/core (M) |
| B12 | recycle commit load hold / precheck | 24 / 20 per core | `handoff-fire.sh:4117-4151` | 33/33 typed lines clean ≤32/core | — | `HELD:load` | 70 `HELD:load` across move/ (M, grep) |
| B13 | engagement window | `120 × lpc` capped at 480 s (cap reached at 4/core) | `handoff-fire.sh:6523-6560` | 84 samples, median 15 s, right-censored | 20/31 | not engaged | since 10-19: n=61 engaged, median 35 s, max 268 s (M, handoffs.jsonl `engage_latency_s`) |
| B14 | watcher pane-proof ticks | `(HF_TIMEOUT_S+3+5)×5` | `handoff-fire.sh:2195` | derived from B6 | 20 | ABORT before /exit | as B6 |
| B15 | reconciler watchdog | stall 900 s, slow 3600 s, step margin 60 s past declared child bound | `lr-recon-watchdog.sh:78-88`, `clock.py:349-362` | 2026-10-18/19 kills | — | kill + restart mid-pass | holder changed 03:24, 03:53, 04:31Z (watchdog.log; not watchdog kills) |
| B16 | slot wait / still-busy | 600 s / 3600 s | lr-move-worker.sh | — | — | `NOTMOVED` | 14 `slot-wait … 600s`, 50 `still-busy … 3600s` across move/ (M, grep) |

Siblings-outlier tell (lesson 1, tell #1): B1, B3, B5, B6 and B7 are flat constants of 3-30 s. Their
siblings B2, B4 and B13 were already re-sized for load. All five flat ones have a foreground origin.

---

## 4. Per-bound analysis

### 4.1 B1: the admission probe (30 s)

- What it runs: `bash -c "source capacity-admit.sh; … cc_capacity_probe lr-reconciler first-turn"`
  (`admit.py:189-211`).
  - An `xtrace` of one foreground run => 618 trace lines, 413 at subshell depth ≥2.
  - Externals counted: 18 `awk`, 5 `/usr/sbin/sysctl`, 2 `vm_stat`, 2 `date`, 2 `dirname`, 1 `jq`,
    1 `grep`, 1 `mkdir`, plus sourcing the presence lib (`bash -x … 2>/tmp/bs06-trace.txt`).
  - So ≈35-40 fork+execs (E: externals plus the `$( )` subshells), and every one queues in the PRI-20 band.
- Measured: fg 2.45-4.20 s, utility 15.6-42.8 s (§1). Against 30 s the bound fires on some passes
  and not others, which is the noise regime the lesson says cannot be fitted.
- Cost structure: `admit()` (`admit.py:245-299`) calls `probe()` once **per member per pass**. A
  cohort of k members therefore pays up to k×30 s per pass inside the serial loop. The probe "charges
  nothing" (`cc_capacity_probe`, capacity-admit.sh:1229), and its terms are box-wide (load, memory,
  segments, active-cpu), so one answer per pass is equally valid for every member of that pass. (E:
  read of the terms. `CC_ADMIT_RESTORE_R` is the same R for all members.)
- Incident shape: `02:43:56 / 02:44:27 / 02:44:58 admit-refused probe-error` (three passes ~31 s
  apart, i.e. the bound), then `02:46:14 spawn d7eb73d2` via the drip. Each drip admission therefore
  cost ≥3 × 30 s of probe plus the 30 s drip clock (M, events.jsonl). The brief's "CPU brake refused
  every pass" is not what these events show. `cpu` appears 2 times; `cpu_ok` has a 20 s
  anti-starvation floor (`admit.py:150-157`). The probe's bound is what held.

### 4.2 B2: the placer, and why it exceeds 120 s

**Profile (M, cProfile of the exact `--place` argv, foreground, 4.10 s wall, `/tmp/bs06-cprofile.txt`):**

| function | cumulative | share | scales with |
|---|---|---|---|
| `cmd_place` → `holds()` (6 calls) → `glob.glob(projects/*/<sid>.jsonl)` | 2.670 s | 65 % | movers × candidate accounts × project dirs. 109,713 `posix.lstat` (1.137 s). Project dirs: 18,327 / 18,326 / 18,401 / 18,196 for next / next2 / next3 / next4 (`ls -1 …/projects \| wc -l`) |
| `apply_burn()` → `_util_tail(hours=336)` → parse | 1.195 s (0.714 s in `_util_tail`) | 29 % | size of `~/.claude/logs/account-utilization.jsonl` (19.3 MB; 41,098 JSON lines parsed for the 14-day window) |
| `compile` of the script | 0.115 s | 3 % | script size (11,629 lines) |
| everything else (cache read, scoring) | ~0.1 s | 3 % | movers × 4 |

- **Nothing in `--place` scales with load by itself. It is CPU and metadata work** that the PRI-20
  band stretches by 4-48x (§1).
- The two dominant terms scale with **corpus size**, which only grows. `holds()` is called for every
  mover × every non-source account that passed the capacity, fact and floor checks (`:6619-6624`).
  With the incident's n=3, that is up to 9 globs, ≈165k `lstat` (E: 109,713 × 9/6).
- Glob alone measured fg 0.09-0.19 s and utility 0.36-0.85 s per call. A direct
  `os.path.exists(<cfg>/projects/<slug>/<sid>.jsonl)` for 4 accounts measured ≤0.0003 s
  (`/tmp/bs06-glob.sh`).

**Production history (M, all 232 `place` events in `recon/events.jsonl{,.1}`, 2026-10-13 → 10-20):**

| load1 | passes | rc 124 | answered median | answered max |
|---|---|---|---|---|
| 0-49 | 134 | 0 % | 2.9 s | 23.9 s |
| 50-99 | 47 | 4 % | 4.0 s | 14.4 s |
| 100-149 | 14 | 0 % | 17.8 s | 75.7 s |
| 150-199 | 14 | 14 % | 17.9 s | 89.6 s |
| 200-249 | 4 | 25 % | 18.7 s | 30.9 s |
| 250-299 | 10 | 50 % | 51.4 s | 106.0 s |
| 300-349 | 6 | 50 % | 74.3 s | 88.2 s |

- Duration vs mover count shows no trend: n=1 median 3.2 s, n=5 4.4 s, n=8 5.0 s. Load and band
  dominate, not n.
- The answered population is **right-censored at the bound**. Every rc 124 is a sample > its bound,
  so the true tail at 250+ is longer than 106 s.
- A timeout kills the child (`run_bounded` → `subprocess.run(timeout=)`). The next pass starts the
  same 4 s of work from zero, under an identical bound, which "abstains identically and costs the
  bound again" (exoneration lesson, "How to apply").
- The loop is serial (`__main__._plan`), so each miss also delays every other record's progress by
  the full bound.
- **Inverse sizing:** `place_timeout` follows load1 *down*. At 04:18Z and 04:20Z, load1 84-89 gave
  bounds of 63-66 s, and both fired (`rc=124 … dur=63.4s timeout=63s load1=84`, `dur=66.5s timeout=66s
  load1=89`). That is why WAIT_DATA persisted after the peak.

### 4.3 B6-B9: the kitty bounds

- Server side is fine: kitty runs at PRI 46 (`ps -axo pid,pri,comm` => `853 46 …/kitty`). `kitty @ ls`
  answers in 0.15-0.39 s fg and 1.3-3.2 s utility even at load 208 (§1).
  **H (supported, not proven):** most of a slow `kitty @` round-trip is *client* start-up in the low
  band, since the client is a full kitty and Python runtime, not kitty's RC thread. The connect probe
  (B7) is pure client: `/usr/bin/python3` (Xcode 3.9) start-up under a 3 s bound, against a utility
  start-up measured at up to 7.89 s.
- **Defect (high confidence, code):** `handoff-fire.sh:2867` and `:2874` read
  `kitty_socket_accepting "$cand" && accepting="$cand"`.
  - The probe returns 124/137 when *its own* bound fires (documented at :1458 and :1489). That rc is
    indistinguishable from refused (3) / ENOENT (4) here.
  - So `accepting` stays empty, and the retry branch (`if [ -n "$accepting" ]`) is skipped. The resolver
    then returns 3 with the message "none of the candidates would even accept a connection".
  - That is exactly the d7eb73d2 first R attempt (actlog `d7eb73d2.1.R.log`).
  - The probe's rc vocabulary was built to separate these cases (commit message in the block comment at
    :1451-1457). These two call sites throw that away.
- B9's budget (≤120 s, 5 tries) is the right *shape*: retry at a different moment. But it applies only
  to `hf_recycle_kitty_probe`, and only when `LR_INPLACE_AWAIT=0`. The resolver (B8) retries 3 × 2 s,
  and only after an accept.

### 4.4 B11/B12: the load waits

- B11 is a wait for load to fall, with a deadline. Under the operator's premise it is either a
  pure delay (load falls eventually) or a guaranteed NOTMOVED (it does not).
- Incident, first batch (`move/20261020T024813Z-next3-next2-78304/*.events.jsonl`, M): 4 workers
  entered `load-wait` at 33-34/core and finished `NOTMOVED HELD:load` after 605/608/609/613 s.
- Second batch (`…030423Z…15173`, M): the workers waited from 03:06:39Z to 03:34:19Z (**1660 s**).
  In that time two of them became limited ("became-limited: its last record is now a limit error"),
  i.e. **the wait turned two idle moves into limited recoveries**.
- The one that proceeded (9240c6a9) hit lr-handoff's precheck, which printed
  `precheck load: not gated (the relaunch is staged in the pane, keystroke-free)`.
- Since Wave S (`e2d0cee07`, landed 2026-10-19T23:12Z, before the incident), a staged-successor move is
  exempt from the load hold. B11 is a copy of the hold's bound ("These two copies MUST stay in step",
  `lr-move-worker.sh:303-307`) but not of its exemption. `grep -n -i 'successor\|CC_PANE_SUCC'
  lr-move-worker.sh` finds only draft-carry lines (28, 209, 234, 295).
- B12 (the commit hold) remains defensible only for a *typed* relaunch. The 600709c5fe4b decision
  measured 33/33 clean typed lines up to ~32/core. Under the premise the load sits at 15-37/core, so
  even B12 binds about half the time. The cure is to always stage, not to wait.

### 4.5 B13: the engagement window

- `fire_engage_window` = `int(120 × lpc)` clamped to [120, 480]. It reaches 480 at 4/core.
- The box was at ≥8/core for 78 % of the time in the 600709c5fe4b sample, and at 15-37 in this
  incident. So the window is in effect a constant 480 s, and "scaled with load" no longer describes it.
- Data (M, handoffs.jsonl since 10-19, n=61): median 35 s, max 268 s. That fits 480 s with margin, but
  the sample is censored at the window and excludes non-engagements.
- The block comment (:6505-6520) already says why waiting is cheap here: PARKED and WEDGED short-circuit,
  and only a live, non-modal claude spends the window. So B13 is a soft spot rather than an incident
  blocker. Its successor should be progress-based (§5), not a bigger cap.

### 4.6 lr-handoff prechecks and the rest of one move (M)

9240c6a9, the one move in the incident that completed via `cc-lr move`. Times are from `move/…15173/9240c6a9….events.jsonl`,
the bundle `events.jsonl` and the bundle file mtimes:

| step | from → to (UTC) | wall |
|---|---|---|
| load-wait (B11; redundant, see 4.4) | 03:06:39 → 03:34:19 | 1660 s |
| slot | 03:34:19 → 03:34:42 | 23 s |
| actuate → bundle dir | 03:35:33 → 03:36:43 | 70 s |
| bundle → `assign` event | → 03:37:51 | 68 s |
| precheck (registry … focus) | 03:37:51 → 03:44:03 | **372 s** |
| admit (swap-exempt) | → 03:44:06 | 3 s |
| transplant | → 03:46:07 (`transplant.json` mtime) | 121 s |
| handoff-fire start-up → watcher armed | 03:46:10 → 03:50:25 (`handoff-recycle-31-1792468225` log name) | 255 s |
| armed → /exit landed (SIGTERM, successor staged) | → 03:54:32 | 247 s |
| **relaunched claude READY** | 03:54:34 → **03:54:41** | **7 s** |
| worker proof-first | → 03:58:43 | 242 s |
| total `wall_s` | | 3179 s |

**Claude Code itself booted in 7 s at that load.** The orchestration around it took ~25 min, plus a
redundant 28-minute wait before that. The shell orchestration is fork-heavy bash. It runs in whichever band
its caller had, and every step is bounded by constants sized in PRI 31. The work being protected is fast,
and the protection is slow.

---

## 5. Design: bounds that fit a box that is always loaded

Principles. Each one comes from a measurement above.

1. **Fix the band before any bound.** Every number here is band × work. Moving the reconciler and its
   actuators from PRI 20 to PRI 31 removes the 5-150x multiplier without touching a constant. The cost
   is ≈2.5 % of one core (§2). Mechanism: plist `ProcessType Interactive` (H: verify PRI after reload).
   The same applies to any launchd job on the recovery path, e.g. the reset poller, if it actuates.
2. **Shrink the work so the bound has less to bound.**
   - `holds()`: one `os.path.exists` per account on the mover's known slug instead of a `projects/*`
     glob. The reconciler already knows each mover's transcript path. Add `slug` to the mover row, and
     keep the glob as a fallback only when it is absent. Measured ≤0.3 ms vs 0.1-0.85 s per call.
   - `apply_burn()`: serve the burn fields from the keepwarm sweep cache, which already runs on its own
     clock, instead of re-parsing 14 days per `--place`.
   - Admission probe: one evaluation per pass, shared by every member. Or a thin `--json` mode of the
     same library that emits all terms in a single fork, so there is still one detector, not two.
   - Placement: invoke it in-process (import the scorer) or keep a warm worker, removing interpreter
     start-up and the 11.6k-line compile from every call. **E:** fg `--place` drops from ~4.1 s to
     ~0.25 s of in-process work (cProfile minus holds and apply_burn).
3. **Bound by liveness, not wall-clock.** For a child that is *making progress*, the right wall bound is
   none. What must be bounded is *no progress*.
   - Rule: kill a child only when its CPU time (`proc_pidinfo`/`ps -o time=`, or child rusage) has not
     advanced for `T_idle`, e.g. 30 s, **or** an absolute ceiling far above any answered sample, e.g.
     10 × the adaptive bound below.
   - The reconciler already has the machinery: `clock.declare_child` and the watchdog's CPU evidence
     (`lr-recon-watchdog.sh` conditions 2-4). The same rule should apply to the children it waits on.
   - **Do not block the loop on it.** Run `--place` and the probe as `Popen`, carry the handle across
     passes, and let other records progress. The serial 120 s wait is what turns one slow child into a
     fleet-wide stall (§4.2).
4. **Where a wall bound must remain, size it from its own answered history, not from load1.** Use the
   RFC 6298 retransmission-timer recipe (https://www.rfc-editor.org/rfc/rfc6298):
   - `SRTT ← 7/8·SRTT + 1/8·d`, `RTTVAR ← 3/4·RTTVAR + 1/4·|SRTT − d|`, `RTO = SRTT + 4·RTTVAR`,
     with a floor (e.g. 30 s) and a ceiling (e.g. 600 s).
   - **On expiry, double the RTO** (RFC 6298 §5.5), because a timeout is a censored sample, not a
     measurement.
   - Keep the state per (child kind, band) in the heartbeat dir so it survives restarts.
   - This tracks the *actual* band × corpus × load product, including corpus growth, which no load
     formula can.
   - Applied to B1, B2, B3, B5, B6 and B7.
5. **"Our bound fired" is a third state.**
   - B7: rc 124/137 from `kitty_socket_accepting` must set a `probe-unknown` that takes the retry branch,
     never "not accepting".
   - B1: `probe-timeout` already exists (ed5614054). It should not count toward the cohort's refusal run
     the same way as a measured `capacity` refusal; it is no-verdict. Either retry next pass with the
     adaptive bound, or admit through the drip without waiting for 3 runs.
   - B2: rc 124 should keep the previous placement, if one is younger than its TTL, instead of falling
     to WAIT_DATA after 3 misses.
6. **No waits for load.**
   - B11 must at minimum mirror Wave S's exemption: skip `load_wait` when the move will stage a
     successor, which is every in-place move with `CC_PANE_SUCCESSOR` on and the successor lib loadable.
   - Better: delete B11 and let the commit hold (B12) decide at the one point it guards. With staging,
     B12 never binds.
   - Where a typed relaunch is unavoidable, retry the *typing* (bounded attempts, at a different
     moment). Waiting for the box to be quiet is what the premise forbids.

---

## 6. Levers, ranked by effect per effort (E unless noted)

1. **Mirror Wave S in the move worker's load wait (B11).** Effort S.
   - Effect: removes 600-1660 s per idle move whenever a successor stages. All 4 idle movers in batch
     024813Z and all 3 in batch 030423Z waited (M).
   - Risk: a staged stage later refused falls back to typing. B12 still holds then, as designed.
2. **`holds()` → direct slug path.** Effort S.
   - Effect: −65 % of `--place` CPU (M profile). With apply_burn from the cache, −94 %.
   - Risk: a mover row without its slug needs the glob fallback.
3. **kitty probe rc 124 → retry branch (B7/B8).** Effort S.
   - Effect: turns `HELD:pane:resolver-unavailable` on a slow interpreter start into a retry.
   - Risk: a genuinely dead kitty costs one more 2 s backoff.
4. **Reconciler (and its spawns) at `ProcessType Interactive`.** Effort S to change, M to verify.
   - Effect: the band multiplier (6-153x in §1) goes to ~1x, the foreground column.
   - Risk: 2.5 % of a core moves to PRI 31. A hypothetical runaway loop would compete with sessions, but
     the watchdog's CPU-evidence kill still covers it.
5. **One probe per pass (or a single-fork probe).** Effort S-M.
   - Effect: k×30 s per pass → ≤1×. Time to admit for a k-member cohort drops by ~(k−1)/k.
6. **Async `--place` and probe with a liveness bound.** Effort M.
   - Effect: the loop never blocks on a child, and a slow placement no longer stalls admissions and
     settles for other records.
7. **Adaptive bounds (RFC 6298) for the remaining wall bounds.** Effort M.
   - Effect: bounds follow the real distribution, including corpus growth. This retires `place_timeout`'s
     load formula and its inverse shrink (§4.2).
8. **apply_burn from the keepwarm cache.** Effort M.
   - Effect: −29 % of `--place` CPU and 19 MB less parsing per call.

---

## 7. Open questions

- **H:** does `ProcessType Interactive` give the daemon *and* its `Popen` children PRI 31 here, and does
  `taskpolicy -c utility` inside any script still re-clamp it? Needs a positive control after the plist
  change. The change requires launchctl, which this pass did not run.
- How much of a slow `kitty @ ls` is client start-up vs kitty's RC thread at load 300+? A PRI-31 vs
  PRI-20 A/B on `kitty @ ls` at the same moment would split it. Today's utility runs were ≤3.24 s at
  load 208.
- The lr-handoff precheck took 372 s for 9240c6a9 (§4.6). Which band was that `cc-lr move` worker in?
  It was operator-started, possibly PRI 31. If 31, the precheck is slow for another reason that this
  pass did not profile.
- The background-band probe I started at 04:30:18Z had not finished when I wrote this. The task is
  terminated with this run; the result is >387 s.
- Engagement latency (B13) is right-censored. The distribution of *non*-engagements under 480 s at
  30/core is unknown.

---

## Skeptic review

Adversarial pass, 2026-10-20 04:39-04:50Z, read-only. I re-read every cited file:line at the live repo
`20368fc85` (the deployed `~/.claude` copies of `lr-move-worker.sh` and `handoff-fire.sh` match it:
`cmp` => same, and `grep -c 'not gated (the relaunch is staged' ~/.claude/scripts/handoff-fire.sh` => 1).
I recomputed every events/move statistic, and I ran two new read-only measurements. Neither typed into a
pane or signalled any process.

- **A/B, same moment (M):** `bash /tmp/skep06-ab.sh` → `/tmp/skep06-ab.log`. Six interleaved fg (PRI 31)
  / `taskpolicy -c utility` (PRI 20) pairs at load1 168-234.

  | workload | fg, 6 runs | utility, 6 runs | per-pair ratio |
  |---|---|---|---|
  | `/usr/bin/python3 -c pass` | 0.07-0.43 s | 0.43-3.98 s | 4-36x |
  | the exact `kitty_socket_accepting` connect body → `/tmp/kitty-853` | 0.10-0.15 s | 0.36-6.37 s (**3 of 6 > 3 s**) | 4-42x |
  | compile `bin/claude-accounts` (Homebrew python) | 0.23-1.05 s | 1.22-15.80 s | 2.5-45x |

- **Starvation probe (M):** `bash /tmp/skep06-starve.sh` → `/tmp/skep06-starve.log`. One PRI-20 CPU
  spinner ran for 93 s at load1 174-200 and got **3.58 CPU-s, i.e. 3.9 % of one core**. Its CPU time
  advanced in every 2 s sample, so it was never fully stalled.

### Findings

**F1 — the reconciler and its actuators run at PRI 20; no ProcessType. CONFIRMED.** One part of open
question 1 is now answered.
- Measured state:
  - `ps -o pid,ppid,pri,etime,time -p 51148` => `51148 1 20 … 14:36 0:21.03`.
  - Its child `1293 51148 20 … lr-handoff.sh --sid db755a94…` is at PRI 20 too.
  - `PlistBuddy -c 'Print :ProcessType' ~/Library/LaunchAgents/com.reso.lr-reconciler.plist` => absent.
  - `man launchd.plist` (lines 474-489) matches the quote and adds "Standard jobs are equivalent to no
    ProcessType being set".
- Negative control: `com.claude.capacity-alarm` (ProcessType=Standard) runs at PRI 20 (pids 75998 and
  9024).
- **Positive control (new):** `com.claude.research-classifier-warm` has ProcessType=Interactive.
  - Its daemon is pid 60282, ppid 1. It runs `/usr/bin/python3`, the same Xcode 3.9 interpreter the
    reconciler pins, at **PRI 31**.
  - Its plain `subprocess.Popen` children are at PRI 31 (67561, 79632, 82915) and 37 (66888)
    (`ps -o pid,ppid,pri,command`).
  - So on this box, Interactive puts the daemon and its Popen children at PRI 31. One thing is still
    untested: act.py's `start_new_session=True`. setsid changes the session, not the QoS (H).
- Caveat on "sized from foreground":
  - That holds for B7. Its 3 s was added in 90eda0040 against hand runs at load 17.
  - It does not hold for B2. The 120 s cap was sized from in-band reconciler non-answers (plan.py:313
    docstring, "04:00Z non-answers ran at load1 264-968").
  - "Most bounds" is fair; "every" would not be.

**F2 — 5-150x in the band; the spread does not track load1. WEAKENED.**
- The band multiplier is real. I reproduced it at the same moment at 2.5-45x (table above).
- The doc's foreground and utility columns were not measured at the same time:
  - The fg probe and `--json` ran at load 86-88, 04:19-04:20Z (`/tmp/bs06-measure.log`).
  - The utility runs were at load 122-208, 04:22-04:30Z (`/tmp/bs06-measure2.log`).
  - The utility `--place` run 1 (04:27-04:31Z) overlapped the utility `--json` run 3 (04:27-04:30Z) and
    another worker's PRI-4 probe.
  - So the 99-153x (`--json`) and 48x (`--place`) ratios mix band with about 2x load and
    self-contention. The "150x" upper end is not reproduced.
- "The spread does not track load1" holds run to run: connect took 6.37 s at load 208 and 0.36 s at
  load 227.
- Production medians do track load coarsely. Recomputed over all 236 `place` events (10-13 → 10-20),
  the answered median by load1 band was:

  | load1 | 0-49 | 50-99 | 100-149 | 150-199 | 200-249 | 250-299 | 300-349 |
  |---|---|---|---|---|---|---|---|
  | answered median | 2.8 s | 4.0 s | 16.3 s | 16.1 s | 18.2 s (n=5) | 51.4 s | 74.3 s |

  So load1 predicts the median within a small factor, but not the tail.
- "A load-proportional bound cannot fit the tail" stands. "Load1 is non-predictive" is overstated.

**F3 — `--place` cost is 94 % two corpus scans. CONFIRMED, with caveats.**
- `/tmp/bs06-cprofile.txt` shows:
  - `holds` at `bin/claude-accounts:6603`: 2.670 s of 4.101 s, with 109,713 `posix.lstat`.
  - `apply_burn` at `:4828`: 1.195 s.
  - 41,098 `json.loads`.
- The profile's Homebrew 3.14 interpreter is the production one: the shebang is `#!/usr/bin/env
  python3`, and the reconciler's PATH puts `/opt/homebrew/bin` first.
- Re-measured in the foreground at load 170-185:
  - One `holds()`-style glob: 0.897 s (`.claude-secondary`) and 1.218 s (`.claude-quaternary`).
  - A direct `os.path.exists` on the slug path: 0.00001-0.0006 s.
  - `os.scandir(projects)` alone: 0.013-0.018 s.
  - So the cost is the ~18k per-dir lstat, not the listing.
- Project dirs are now 18,329 / 18,326 / 18,401 / 18,196.
- `apply_burn`'s own docstring says "336 h in 73 ms" on a 3.6 MB series. The file is now 19,298,410 B.
- Caveat 1: the profile used 2 synthetic movers and an empty facts dir, so every non-source account
  reached `holds()`. Production capacity and fact checks run first (`:6619-6625` elif order), so 65 % is
  an upper bound.
- Caveat 2: "duration does not grow with mover count" is confounded by load. Answered medians are:
  n=1 3.2 s (161), n=2 18.7 s (19), n=3 69.5 s (7), n=8 4.2 s (6). The n=2/3 rows are the incident's
  high-load passes, so neither direction is shown.

**F4 — `place_timeout` is miscalibrated in both directions. CONFIRMED.**
- `plan.py:312-318` with ncpu 10 gives 30·load1/40: 63 s at load 84, 66 s at load 89, and the 120 s cap
  from load 160.
- Recomputed rc 124 rates: 5/10 at 250-299, 3/6 at 300-349, 1/3 at 350+ (answered max 107.3 s).
- Sharper evidence than the doc's:
  - At 04:15:25: `rc=0 dur=75.7s timeout=76s load1=102`, answered with 0.3 s to spare.
  - Then 04:18 and 04:20 fired at 63 and 66 s. The bound followed load1 down; the work did not.
- A timeout discards the work:
  - `clock.py:349-361` wraps `subprocess.run` unchanged.
  - The Python docs say: "If the timeout expires, the child process will be killed and waited for"
    (https://docs.python.org/3/library/subprocess.html#subprocess.run).
- The heartbeat now reads `"max_step_gap_s":120.076…,"max_step_gap_bound_s":120.0`. The serial loop's
  step gap is the `--place` bound (`cat recon/heartbeat`).

**F5 — the kitty connect probe's 3 s bound fires on interpreter start-up and is read as "not
accepting". CONFIRMED (raised from medium).**
- The cited lines are as stated:
  - `handoff-fire.sh:1458-1482`: `hf_bounded_s "${CC_KITTY_CONNECT_TIMEOUT_S:-3}" /usr/bin/python3`.
  - `:2867` and `:2874`: `kitty_socket_accepting "$cand" && accepting="$cand"`.
  - `:2903`: `if [ -n "$accepting" ]`.
- **New incident evidence:**
  - `recon/actlogs/d7eb73d2.2.R.log:11` and `e80b61f4.1.R.log:9` both read "the control socket
    /tmp/kitty-853 did not accept a connection: the probe's own 3s bound fired (rc 124), so it could
    not tell … asking again in 5s".
  - Both later reached `precheck verdict: OK` (lines 24 and 22).
  - So during the incident the bound fired against the live kitty, and a retry at a different moment
    worked.
- Same-moment A/B: in the utility band the exact connect body exceeded 3 s in 3 of 6 runs.
- Remaining gap: `d7eb73d2.1.R.log` does not log the connect rc. That particular HELD could also have
  been rc 3: a live kitty with a full 128 backlog refuses at once (`handoff-fire.sh:1453-1456`).

**F6 — the move worker's 600 s HELD:load is a wait for load, and lacks Wave S's exemption. CONFIRMED,
with count corrections.**
- Code:
  - `lr-move-worker.sh:335-352` is as stated.
  - `grep -n -i 'successor\|CC_PANE_SUCC'` => only 28, 209, 234 and 295, all draft carry.
  - Both actuator gates exempt a staged successor: the precheck at `handoff-fire.sh:13836` and the
    commit at `hf_recycle_load_gate`, `:4146` (`hf_succ_ours_staged … return 0`). So the worker gates
    moves that neither actuator gate would hold.
- Batch `024813Z`: 4/4 ended `NOTMOVED HELD:load` after 605/608/609/613 s, having entered at
  32.8-34.2/core. Verified.
- **Corrections to batch `030423Z`:**
  - It had **4** workers, not 3.
  - **2** were MOVED: 9240c6a9 (`wall_s` 3179) and ceff45c5 (`wall_s` 3192).
  - 2 were NOTMOVED became-limited: 3d1d988a and 3e929a81.
  - So "all 7 idle movers" is really the same 4 sessions waiting in both batches, 8 waits in all.
- **Why the wait ended:**
  - In `~/.reso/load.jsonl`, load1 was 207.42 at 03:34:13Z and 193.14 at 03:34:25Z.
  - All four workers left `load-wait` at 03:34:19-23Z (`slot-wait` t_ms 1792467259515-1792467263055).
  - That is when load1 dipped under 200 (20/core). The moves that did happen depended on a load dip,
    which is exactly what the premise rules out.
- Wave S's author date, 2026-10-19 18:12 -0500 (23:12Z), is verified.

**F7 — 7 s boot vs ~25 min of orchestration. CONFIRMED in substance; the framing is corrected.**
- The bundle events match the doc:

  | step | time (Z) |
  |---|---|
  | assign | 03:37:51 |
  | focus probed | 03:44:03 (372 s after assign) |
  | admitted | 03:44:06 |
  | `transplant.json` mtime | 03:46:07 |
  | recycle-armed | 03:46:10 |
  | relaunch → READY | 03:54:34 → 03:54:41 (7 s) |
  | `wall_s` | 3179 |

- Small correction: `9240c6a9….watcher.json` gives lstart 03:51:22 and `armed_at` 03:51:27Z, not
  03:50:25 (that is the log-name stamp). So start-up → armed was 317 s and armed → /exit 185 s. The sum
  is unchanged.
- It was not "the one completed move": ceff45c5 completed in the same batch, with near-identical
  actuate/actuated stamps.
- Open question 3, answered (E: repo text plus the poller log; the PRI of those pids was not measured):
  - Both incident batches were started by the reset poller: `poller.log:233739` and `:233743`,
    `MOVE-BATCH started pid 55195/11718`. That job has no ProcessType.
  - `lr-reset-poller.sh:249` records that "Every process the move lane runs sat at priority 20" for
    exactly this reason.
  - The Interactive fix exists only as staged: `launchd/staged/com.reso.lr-move-kick.plist`, ProcessType
    Interactive. `ls ~/Library/LaunchAgents | grep move-kick` => nothing, so it is not installed.
  - So the 372 s precheck very likely ran at PRI 20 as well.

**F8 — the 30 s admission probe was the gate that held, and it costs up to k×30 s per pass.
CONFIRMED, with the interpretation corrected.**
- Recomputed from events since 02:30Z: `probe-error` ×7, `cpu` ×2, `restore-r` ×1.
- Code:
  - The `cpu_ok` floor is at `admit.py:150-157`.
  - The probe call is at `admit.py:282`, inside `decide()` (not `admit()`).
  - `decide()` is called per record from `__main__._admit` (`:1118`).
- **Correction:** 02:43:56, 02:44:27 and 02:44:58 are three *different members* (d7eb73d2, 7aae55e1,
  db755a94) in **one** pass, not three passes. All three were `own … taken` at 02:43:15-16, right after
  one `place` event. That is direct evidence for k×30 s per pass.
- The refusal run counts per member call (`admit.py:284-287`), so the drip opened in the next pass
  (spawn 02:46:14).
- **Additional defect (new):** once the run is ≥ DRIP_AFTER and the drip clock is open, the probe at
  `:282` still runs before the drip check (`:283-296`). Its answer cannot change the outcome (it admits
  either way), so each drip admission still pays up to 30 s for nothing.
- The 7 events say `probe-error` because they predate ed5614054 (2026-10-19 22:59 -0500). Their 31 s
  spacing fits the 30 s bound firing.

**F9 — the engagement window is effectively a constant 480 s and is not a blocker. CONFIRMED.**
- `handoff-fire.sh:6523-6560` is as stated: `int(120·lpc+0.5)` clamped to [120, 480].
- Recomputed from `handoffs.jsonl` since 10-19: n=63, median 35 s, p90 204 s, max 268 s.
- The doc's own censoring caveat still applies.

### Levers

**L1 — mirror Wave S in `load_wait` (or delete it). CONFIRMED.**
- Neither actuator gate holds a staged move (`:13836`, `:4146`).
- The incident wait cost 605-1666 s per worker and turned 2 idle moves into limited recoveries.
- The risk text is slightly off. B12 guards only a stage that is refused *before* /exit. A staged
  successor that fails after the SIGTERM falls back to typing after 20 s with no load gate (9240c6a9
  handoff.log: "typed fallback after 20s at a bare shell"). Wave S already accepted that same risk at
  the precheck, so L1 adds none.
- Count: 4 sessions × 2 batches, not 7.

**L2 — `holds()` → direct slug path. CONFIRMED on mechanism, with a correctness caveat.**
- Measured: glob 0.9-1.2 s vs `exists` ≤0.0006 s.
- Mover rows carry no cwd or slug today (`lr_recon/types.py:834-843`;
  `docs/plans/LIMIT_RECOVER_FLEET_V2.md:574`).
- A stale copy under a *different* slug would be missed, and that is exactly what `store-holds-sid`
  exists to catch.
- Safer variant: keep the glob, but run it only on the winning account after scoring (movers×1 instead
  of movers×3). Or use the slug check as a fast path, with the glob confirming only the winner.

**L3 — rc 124/137 → retry. CONFIRMED.**
- The incident logs show rc 124 followed by OK on a retry (`d7eb73d2.2`, `e80b61f4.1`).
- The risk is overstated. A dead kitty answers rc 3 or 4 quickly, not 124, so the extra backoff lands
  almost only on live-but-slow kitties.
- Gap: rc 3 from a full accept backlog (`:1455-1456`) still skips the retry. Consider retrying 3 as
  well when the socket's owner pid is alive.

**L4 — ProcessType Interactive for the reconciler. CONFIRMED (upgraded from H).**
- The positive control is classifier-warm (Interactive → PRI 31, Popen children at 31).
- The same-moment A/B and the spinner (PRI 20 gets 3.9 % of one core at load ~190) show the band is the
  multiplier. PRI-31 claude booted in 7 s at load ~190 (F7).
- The cost claim is weaker than stated:
  - 2.4 % of one core is the daemon alone (21.03 CPU-s over 876 s, `ps -o time,etime -p 51148`).
  - Its children would move to 31 as well: `--place` at about 4 CPU-s per call, the probe, the ps
    census and the actuators.
  - The repo's move-lane design re-clamps its census to utility under an Interactive kick
    (`lr-move-batch.sh:335-339`) for exactly that reason. L4 should do the same for `observe`'s census.
- The move lane needs the same fix: install the staged `com.reso.lr-move-kick`.

**L5 — one probe per pass. CONFIRMED, with a counting caveat.**
- The terms are box-wide: `probe()` passes no sid or account (`admit.py:196-203`).
- Under the premise (always above 2.5/core), `cpu_ok` refuses a second admission in the same pass
  (`last_admit_at = now` against the 20 s floor). A shared verdict therefore cannot over-admit.
- Caveat: if the shared probe counts one refusal per pass, the drip opens after 3 *passes* instead of 3
  *members*. That is slower than today in the incident shape. Keep the per-member count, and skip the
  probe while the drip clock is open (F8).

**L6 — async `--place`/probe with a liveness bound. CONFIRMED: sound, but secondary.**
- The PRI-20 spinner's CPU time advanced in every 2 s sample at load 174-200 (one 93 s run; the
  background band was not tested). So a 30 s "no CPU progress" rule would not falsely kill a starved
  `--place` at that load.
- Caveat: the probe is a bash process that waits on ~35-40 short children, and its own CPU time stands
  still while it waits. Liveness must therefore sum the process tree.
- After L4, `--place` takes 4-7 s in the foreground, which shrinks the payoff.

**L7 — RFC 6298 adaptive bounds. WEAKENED.**
- The formulas are quoted correctly (RFC 6298 §2, §5.5).
- Consecutive same-band runs vary 0.36 → 6.37 s and 260.8 → 19.9 s. With that spread RTTVAR dominates,
  so RTO = SRTT + 4·RTTVAR sits near its ceiling: in effect a large constant.
- Without L6, raising B2 toward a 600 s ceiling stretches the serial-loop stall (now 120 s,
  `max_step_gap_s`).
- Its stated rationale, "load1 non-predictive", is overstated (F2).
- It adds little after L4+L6.

**L8 — `apply_burn` from the keepwarm cache. WEAKENED.**
- The mechanism contradicts an explicit invariant. The `_render_board` docstring
  (`bin/claude-accounts:7961-7962`) says: "k_phantom and burn_* are render-time decorations and must
  never reach the cache".
- `cmd_place` applies burn to rows from `get_data(max_wait=0)` (`:6516-6526`), so the cache holds no
  burn fields to serve.
- The per-process `_UTIL_MEMO` is off for `--place` (`_UTIL_MEMO_ON` is set only for `--keepwarm`,
  `--local-refresh` and `--readout`, `:4606`).
- It would need a new derived-burn file with its own contract. The effect (−29 % of foreground CPU)
  holds.
