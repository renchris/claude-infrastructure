---
status: open
---

# MACHINE CAPACITY & RESOURCE GOVERNANCE — ground-up rebuild (row 13)

**Scope (frozen):** claude-infrastructure sustains **30 concurrent Claude Code sessions** on the
10-core / 64 GiB box with **≥95% of gate-suite (bats) CPU running in Darwin's BACKGROUND band**
(measured baseline: **0% of CPU, 30% of procs**), under the standing constraint that *any session
may invoke `bats` directly by hand and no caller can be trusted to demote itself*. Includes:
exonerate-or-fix each of the three named risks (lag / memory pressure / leaks) against disk truth,
state the session ceiling with its alarm, and add the missing capacity row to
`GROUND_UP_REBUILD_MAP.md`.

**Standing constraint (the one that kills lazy designs):** *the caller cannot be trusted.* Sessions
are told by `CLAUDE.md` to run the gate before committing, and they do it by typing `bats tests/…`
or `timeout 5400 bats tests/…` directly. Any design whose correctness depends on a caller
remembering to wrap itself in `nice`/`taskpolicy` is already measured to fail 70% of the time. This
kills: "document the wrapper", "add it to the runbook", "tell the teammate brief to use it".

**Method:** the `ground-up` skill. Exemplar: [LAND_PIPELINE_V2.md](LAND_PIPELINE_V2.md).
**Baseline measured:** 2026-07-29, on the live box mid-load (31 sessions, 8 concurrent gate runs).

---

## Phase 0 — Agent Team Orchestration

Three code-writing tasks with **disjoint file ownership**. No task exceeds ~250 LOC, so no split is
required beyond this roster. Briefs ≤150 lines, pre-greped line ranges embedded, verbatim
stop-on-issue clause, no visual verification inline.

| Teammate | Owns (exclusive) | Deliverable | blockedBy |
|---|---|---|---|
| `cap-qos` | `bin/cc-bats` (new), `scripts/qos-census.sh` (new), `tests/qos-chokepoint.bats` (new) | The chokepoint shim + its census + RED-proofed tests | — |
| `cap-readout` | `hooks/operator-readout.sh` | Cut the 2711 ms Stop-path cost; no behaviour change to the rendered block | — |
| `cap-leak` | `bin/cc-reaper` (watchdog census leg only), `tests/watchdog-census.bats` (new) | pid+lstart liveness + spawn/exit accounting so the ~102 lost watchdogs are countable | — |

Worktree/branch: all three off `ground-up/concurrency-capacity` (base `6ce912b3`), one worktree
each. Spawn wave: all three concurrently (no dependency edges). Phase-checkpoint review against
§7 acceptance criteria, which are written **before** any spawn.

**Seams consumed, not redesigned:** row 1 owns the verifier's QoS decision (`postland-verify.sh`
§BACKGROUND QoS) — this row *universalizes* it to the invocation chokepoint and must not change the
verifier's own policy or re-add its deleted admission control. Row 6 owns hook wiring; row 12 owns
launchd activation. Row 5 owns the *dispatch* concurrency ceiling (how many workers fire); this row
owns the *resource* consequence (what priority their work runs at).

---

## 1. Measured constants — WITH CITATIONS

Every number below was derived from primary disk truth on 2026-07-29. No number is inherited from
a prior doc.

| Constant | Value | How measured |
|---|---|---|
| Host | MacBookPro18,2 (M1 Max), 10 cores, 64 GiB, macOS 15.6.1 | `sysctl -n hw.model hw.ncpu hw.memsize` |
| Live sessions at baseline | **31 real** (+25 wrapper shims at 1–3 MB) | `ps` over `claude.exe` + `.bin/claude`; RSS distribution is bimodal |
| Per-session RSS | **mean 636 MB**, range 417–985 MB | `ps -eo rss` over the 31 real procs |
| RSS vs session age | **FLAT** — 30 h session = 417 MB; 33 min session = 700 MB | `ps -eo etime,rss` correlation, n=56 |
| fds per session | **22–24, flat with age** | `lsof -p` on 3 youngest + 3 oldest |
| Threads per session | 16–29 (679 across 29 procs) | `ps -M <pid>`, `top -stats th` |
| Memory at 30 sessions | **44.7 GB of 64 GiB** | 26.1 GB measured non-claude + 30 × 636 MB |
| Memory ceiling | **~50 sessions** (57.2 GB → pressure) | same model |
| Hook chain per **Bash** tool call | **1037 ms CPU** (8 hooks) | min-of-3 timing each: curl-gate 128, validate-bash 170, git-worktree-guard 73, keychain-guard 71, rm-safe-allowlist 73, log-bash 87, waiting-recycle 278, teammate-checkpoint 157 |
| **Stop** chain per turn | **3688 ms**, of which `operator-readout.sh` = **2711 ms (73%)** | min-of-2 timing each, 9 hooks |
| Tool-call rate | **59.2 / session / hour** (one per ~61 s) | 592 `tool_use` blocks across 10 active sessions, 60 min transcript window |
| Hook CPU at 30 sessions | **~0.9 cores** of 10 | 30 × 59.2/hr × ~1 s + turn-rate × 3.7 s |
| Fork rate | **5.5 procs/sec** | count of procs with `etime ≤ 10 s` |
| Procs / threads | 1206 / 5704 | `top -l 1` |
| OS ceilings | `maxprocperuid` 10666 (**976 used**), `maxfiles` 491520, `ulimit -n` 1048576, `num_taskthreads` 16384 | `sysctl`, `ulimit` |
| bats corpus | **149 files, 2403 `@test` cases** | `grep -c '^@test' tests/*.bats` |
| Concurrent gate runs observed | **8 distinct** `bats-run-*` | unique `bats-run-` tokens in `ps` args |
| **QoS coverage (the defect)** | **30% of procs, 0% of CPU** — 72 procs at `pri=31`, 31 at `pri≤10` | `ps -eo pid,nice,pri,%cpu` census over all bats procs |
| Load avg during gate burst | **40.9 / 44.2 / 38.7** on 10 cores | `uptime` |
| CPU during burst | **736% of 1000%** | `ps -eo %cpu` sum |
| CPU steady (instantaneous) | 508% of 1000%; `claude.exe` 129% | `top -l 2`, **second** sample |
| iTerm2 + WindowServer | 96% + 66% = **1.6 cores** | `top -l 2`, second sample |
| Watchdog accounting | 3763 spawned − 568 clean-exit − 3060 crash-path = **135**; 33 live ⇒ **~102 lost** | `grep -c` on `~/.claude/logs/lead-crash-watchdog.log` |
| Sessions exiting via crash path | **81%** (3060 / 3763) | same log |
| `osascript`/`it2` call sites | **165 total, 31 with no timeout wrapper** | `grep -rn` over `hooks/ bin/ scripts/` |

### 1.1 Measurement traps hit (record them — they cost real time)

- **`ps %cpu` is a lifetime average, not instantaneous.** It read `claude.exe` at 33% while `top`'s
  second sample read 129%. Any CPU claim must come from `top -l 2` and use the **second** sample.
- **A substring classifier mislabels by path.** `.claude-219/node_modules/.bin/claude` matches
  `\.claude.*bin`, so real sessions were counted as "hook processes" and produced a phantom
  **11.22 GB** of hook RSS. True figure: **0.15 GB across 75 procs.** Classify by `comm`, never by
  a path substring.
- **PID-delta is not a fork rate.** Max PID was 98637 — near the 99999 wrap — so the delta read 0.
  Use `etime ≤ N` instead.

---

## 2. INVARIANTS (numbered requirements) vs ARCHITECTURE

First principles is not amnesia. Sorted from `MEMORY.md`, the incident record, and the enforced
lints already in the tree.

### INVARIANTS — any design must keep these

- **R1 — A shedder that WAITS amplifies.** `gate_admit` (poll loadavg, sleep below a ceiling) is
  DELETED and must stay deleted: it cost ~2 h of sleeping per run, and with 5 concurrent gates
  *each gate's own corpus was the load the others were waiting out* — self-starvation below their
  own ceiling. Enforced by lint at `scripts/postland-verify.sh:1154`. The verifier is the net, so it
  is the one party that may never be the thing that waits.
  → *Corollary:* the answer to contention is **priority demotion**, never queueing or sleeping.
- **R2 — Enforcement must live at the chokepoint.** A rule enforced only inside one caller is
  detection, not a gate (memory `enforcement-must-live-at-the-chokepoint`). The QoS band enforced
  inside `postland-verify.sh` is exactly this failure: 70% of gate procs bypass it.
- **R3 — Census the actuator against the real target population.** A mechanism is presumed inert
  until counted against live targets (memory `actuator-must-see-the-target-population`: 134/134
  MISS). `ps -o comm=` truncates at 16 chars — never key a census on it.
- **R4 — A built feature must FAIL LOUD when inert.** ~100% abstain ⇒ inert by construction
  (memory `feature-durability-mechanism-not-memory`). A QoS shim that silently no-ops when
  `taskpolicy` is absent is a non-feature.
- **R5 — pid liveness must be pinned by pid **+ lstart**, never pid alone.** The PID space wraps
  every ~5.05 h at the measured 5.5 forks/sec, so a bare `kill -0 $pid` is unsound beyond one wrap
  (memory `periodic-job-self-overlap`). Already the repo's rule in `land-lock`/`cc-backlog`; NOT
  applied in `lead-crash-watchdog.sh:601`.
- **R6 — Absence alarms need existence evidence.** "0 procs at pri=31" must be distinguishable from
  "the census never ran" (memory `absence-alarm-needs-existence-evidence`). Every census emits a
  positive control.
- **R7 — Bound every external call, and the bound must fit what it bounds.** 31 unbounded
  `osascript` sites share ONE serialized machine-wide AppleEvent channel; the documented
  2026-07-26 wedge is this class (memory `bounding-external-calls`,
  `exoneration-bound-must-fit-what-it-bounds`). An idle-calibrated timeout is an off-switch under load.
- **R8 — Every new mechanism ships with an env kill switch**, never revert-as-plan.
- **R9 — Re-derive a "standing constraint" before designing against it.** The map's own row-5
  learning; applied here — it is what turned "the box is out of memory" into "the box is fine on
  memory and wrong on priority".

### ARCHITECTURE — the incumbent's mechanisms, inherited from nothing

`postland-verify.sh`'s internal `QOS=(nice -n 19 taskpolicy -c background)` array; the
`lead-crash-watchdog.sh` detached-daemon-per-session shape; the 69-entry hook fan; the
per-caller `lcw_osa` timeout helper. All are *candidates*, none is a given.

---

## 3. What the measurement actually proved — the three named risks

The goal named three risks. Two are **exonerated by measurement**; one is real and mis-located.

### 3.1 "Memory pressure" — EXONERATED at the stated range

30 sessions = **44.7 GB of 64 GiB**, 0 bytes of swap in use at baseline. Pressure begins at ~50
sessions. The stated 15–30 range is comfortably inside budget, and the correct action is to **state
the ceiling and alarm before swap**, not to cap sessions.

### 3.2 "Leaks" — EXONERATED for the two mechanisms that looked guilty; one small real residue

- **Per-session RSS does not leak.** Flat with age; the 30-hour session is one of the *smallest*
  (417 MB) while a 33-minute session is 700 MB. RSS tracks context size, not uptime.
- **fds do not leak.** 22–24 per session regardless of age, against a 1,048,576 limit.
- **`gitstatusd` is exonerated.** 39 procs, 0.09 GB, ~0% CPU.
- **The 33 orphaned `lead-crash-watchdog.sh` daemons are NOT a leak.** All 33 pidfiles resolve to
  live claude sessions; `ppid=1` is by design (`disown`, line 816, required so the SessionStart hook
  can return immediately). 33 watchdogs for 33 sessions is correct steady state at ~2 MB and 0% CPU
  each. **My own PID-reuse hypothesis was refuted by this check** — recorded because the hypothesis
  was plausible and cheap-looking, and gating a redesign on it would have been wrong.
- **Real residue:** the spawn/exit ledger does not balance — ~102 watchdogs unaccounted over the
  log's life. Small in absolute cost, but it is *unbounded in time* and currently **uncountable**,
  which is the property that matters (R6). This is M4 below.

### 3.3 "Lag" — REAL, and located at priority, not at volume

Steady state at 30 sessions is not saturated: ~0.9 cores of hook overhead, 129% `claude.exe`, all
OS ceilings under 10% utilised. The measured **load 40.9 / 736% CPU** was a **burst**: 8 concurrent
gate runs, 2403 `@test` cases each, **72 of 103 bats procs at `pri=31`** — full interactive
priority, competing head-on with all 31 interactive sessions.

The bypassing invocation is the *ordinary* one. A live session was running
`timeout 5400 bats tests/postland-verify.bats` at `nice 0` — precisely what `CLAUDE.md` instructs
sessions to do before committing. `which bats` → `/opt/homebrew/bin/bats`, the real binary. **There
is no wrapper, so there is no chokepoint.**

> **⚠ SUPERSEDED IN PART by §8.5.7 — read that before using this paragraph.** The adversarial pass
> showed that (a) load is a **high-variance** signal, not a trend — 13 samples ranged 29.15→59.80 at
> a *constant* 31–32 sessions, so "load climbed 27→40.9" is oscillation, not accumulation; and (b)
> the gate corpora are **not** the dominant term — 31 sessions total only ~18% of process CPU
> (0.036 cores each) while a **single iTerm2 process exceeds the whole session fleet**. The
> `pri=31` census finding stands exactly as measured, and demoting it remains correct and cheap —
> but it buys ~0.5–0.7 cores, not the difference between load 40 and load 20.

---

## 4. Failure-mode table — every observed mode → its structural answer

A mode without an answer is an unfinished design.

| # | Observed failure mode | Evidence | Structural answer (the inversion) |
|---|---|---|---|
| **M1** | Gate corpus runs at interactive priority, starving 31 sessions | 72/103 bats procs `pri=31`; QoS coverage 0% of CPU | **Move the QoS band from the caller to the tool.** A `bats` shim earlier on `PATH` re-execs the real bats under `nice -n 19` + `taskpolicy -c background`. Inversion: *the tool demotes itself, so no caller can forget.* O(1) code, covers hand-typed, scripted, and launchd invocations alike. |
| **M2** | Load-gated admission control amplifies contention | `gate_admit` deleted: ~2 h sleeping/run; 5 gates self-starving at load 16–18 vs their own ceiling of 8 | **Keep it deleted (R1).** Demote priority; never queue, never sleep. The existing lint at `postland-verify.sh:1154` is the enforcement — extend it to the new shim rather than duplicating policy. |
| **M3** ✅ **BUILT** | Stop chain costs 3688 ms/turn; one hook is 73% of it | `operator-readout.sh` = 2711 ms, min-of-2 | **Make the readout's cost proportional to *change*, not to every turn.** It re-renders disk truth unconditionally; it already has damping semantics for *display* (15-min re-assert) — push that damping *below* the expensive reads so an unchanged state is a cheap stat, not a full render. |
| **M4** | Watchdog spawn/exit ledger does not balance (~102 lost); liveness test is unsound past one PID wrap | log accounting; `lead-crash-watchdog.sh:601` bare `kill -0` vs R5; PID wrap every 5.05 h | **pid+lstart liveness + a census leg with a positive control.** Makes "no orphans" distinguishable from "nobody looked" (R6), and makes the residue countable before it is optimised. |
| **M5** | 31 unbounded `osascript` sites share one serialized AppleEvent channel | `grep`; documented machine-wide iTerm2/AppleEvent wedge 2026-07-26, cited in `lead-crash-watchdog.sh:18` | **Universalize the bound that already exists.** The `lcw_osa` helper is the proven shape; hoist it to one sourced helper and convert the 31 bare sites. Bound must fit what it bounds (R7) — not idle-calibrated. |
| **M6** OK-BUILT | Session ceiling is unstated, so pressure would be discovered by swapping | 44.7 GB @30, 57.2 GB @50, no guard | **State the ceiling (≈50) and alarm on the leading indicator** (compressor growth / swap > 0), not on the lagging one (already swapping). |

**Structural check (skill Phase 2):** is the new design the old one with bigger constants? No. M1
inverts *who* applies the policy (tool, not caller). M3 inverts *what* the cost scales with (change,
not turns). M4 inverts *what proves health* (a counted census, not silence). M2 is a deliberate
non-change, defended by an existing lint.

---

## 5. Scope boundary — what this row does NOT touch

- **Hook count / hook micro-optimisation.** 69 hooks cost ~0.9 cores at 30 sessions against a
  10-core box. Real, but not the binding constraint. Cutting the 1037 ms Bash chain is row 6's
  concern and is explicitly *not* pursued here — it would be effort spent against a non-problem
  while M1 burns whole cores. (M3 is the exception: one hook at 73% of a 3.7 s path is an outlier,
  not micro-optimisation.)
- **Capping concurrent sessions.** Both memory and CPU fit at 30. Capping would forfeit real
  capacity to avoid a priority bug.
- **`--max-old-space-size` on sessions.** RSS is flat with age; there is no leak to contain.
- **iTerm2's own 96% CPU.** Measured and noted, but it is a third-party renderer; the actionable
  part of the AppleEvent story is M5 (our call sites), not iTerm2's internals.
- **Row 5's dispatch concurrency ceiling.** Different subsystem, active rebuild, shared seam
  declared in Phase 0.

---

## 6. REJECTED ALTERNATIVES (do not relitigate)

| Rejected | Why |
|---|---|
| Re-add load-gated admission control (`gate_admit`) | Measured failure: ~2 h sleeping/run, 5 gates self-starving on their own load. Lint-blocked at `postland-verify.sh:1154`. R1. |
| Serialize all gate runs behind one global lock | Turns wall-time into unbounded deploy latency, and the landing lock already serializes the *land* path — the burst is from *pre-commit* gates, which must stay parallel. Demotion gives contention relief without a queue. |
| Ask callers to use a wrapper (docs / runbook / teammate brief) | Directly falsified by the standing constraint: 70% of live procs bypass the existing in-caller wrapper. A rule the caller must remember is not a mechanism (R2). |
| Cap sessions to <15 | Memory and CPU both fit at 30 (§3.1, §3.3). Would forfeit capacity to mask a priority bug. |
| Kill the per-session watchdogs / `gitstatusd` | Both exonerated by measurement (§3.2). Would remove crash recovery to fix a non-problem. |
| Shrink the bats corpus / sample tests | The corpus is the safety net for a fleet that lands continuously; row 1 already moved it off the land path for latency. Priority, not coverage, is the lever. |
| Nice the *sessions* up instead of gates down | Requires elevated privilege for negative nice, and inverts the default: new sessions would start un-prioritised. Demoting the known-batch workload is the smaller, safer change. |

---

## 7. Acceptance criteria — DISK-TRUTH READS (written before any spawn)

Each criterion names the exact command whose output proves it. Narration does not count.

| # | Criterion | Proving read | Baseline |
|---|---|---|---|
| **AC1** ✅ **MET (100%) — see §9.7; the ~70% ceiling was a contaminated instrument, now retracted** | ≥95% of bats **procs** at `pri≤10` during a burst | `scripts/qos-census.sh` → `coverage_proc_pct` | **21.1% → 50.0%** measured; ~30% of invocations are structurally unreachable by a PATH shim |
| **AC1-b** | `coverage_cpu_pct` reported alongside, as the impact metric — **not** the gate | same JSON row → `coverage_cpu_pct`, `gate_on` | 0% |
| **AC2** | 0 top-level bats invocations at `pri=31` | `ps -eo pri,args \| grep -E 'bats( \|$)' \| awk '$1==31'` → empty | **72 procs** |
| **AC3** | The shim covers the hand-typed form | `cd <worktree> && timeout 5 bats --version` then census the child's `pri` → `≤10` | n/a (no shim) |
| **AC4** | The shim FAILS LOUD when `taskpolicy` is absent (R4) | `PATH=/usr/bin:/bin CC_BATS_TASKPOLICY= bin/cc-bats --version` → non-zero **or** an explicit stderr degradation notice; never a silent nice-0 pass | n/a |
| **AC5** | `gate_admit` stays absent (R1/M2) | `grep -c '^[[:space:]]*gate_admit' scripts/postland-verify.sh` → `0`; the existing lint still passes | `0` ✓ |
| **AC6** ✅ **MET** | Stop chain ≤1500 ms | min-of-2/3 timing of the 9 Stop hooks, steady state | **3688 ms → 882 ms** |
| **AC7** ✅ **MET** | `operator-readout.sh` unchanged-state path ≤300 ms | min-of-3, warm latch | **2711 ms → 140 ms** (19×; cold render still 3221 ms, by design) |
| **AC8** ✅ **MET** | The rendered readout block is byte-identical before/after M3 | `--render` old-vs-new on the SAME tree → identical sha `707c143f78f66e62` | — |
| **AC9** | Watchdog census balances, with a positive control (R6) | `cc-reaper --watchdog-census` → `spawned/live/exited/lost` + a `control=OK` line proving the detector fires | ledger off by **~102**, no census exists |
| **AC10** | Watchdog liveness uses pid+lstart (R5) | `grep -c 'lstart' hooks/lead-crash-watchdog.sh` → `>0`; RED-proof asserts a recycled-PID fixture is classified dead | bare `kill -0`, line 601 |
| **AC11** | 0 unbounded `osascript` sites in `hooks/` (R7) | `grep -rn '^[^#]*osascript' hooks/ \| grep -vE 'timeout\|_osa\|TB' \| wc -l` → `0` | **31** repo-wide |
| **AC12** MET | Session ceiling stated + alarmed (M6) | `scripts/capacity-alarm.sh` -> 4-rung verdict; swap-used>0 => ALARM; `--selftest` proves every rung reachable | unstated -> OK@29.3 GB headroom |
| **AC13** | Row 13 exists in the map with plan link + landed shas | `grep -c 'MACHINE_CAPACITY_V2' docs/plans/GROUND_UP_REBUILD_MAP.md` → `>0` | absent |

**Proof bar (non-negotiable, from the exemplar's catches):** RED-proof every new test against the
pristine pre-change tree recovered via `git archive` — never a hand-edited approximation. Positive
control next to every absence assertion. `|| false` on non-final `[[ ]]` in bats. Re-run controls
under `/bin/bash` when the artifact ships to launchd (the Bash tool runs zsh).

---

## 7.1 What this design does when its dependencies are dark (binding map ruling)

The map's DONE ruling requires every row to consume other rows' mechanisms **fail-soft** and to say
in its plan what happens when the dependency is inert. Checked, not trusted:

| Consumed | Owner | If it is dark | Row 13's behaviour |
|---|---|---|---|
| `postland-verify.sh`'s internal `QOS=(nice -n 19 taskpolicy -c background)` | 1 | verifier runs un-demoted | **Independent by construction.** The shim demotes at the `bats` invocation, so coverage does not depend on the verifier's own array running. If BOTH apply the demotion is **idempotent** (`nice 19` twice is still 19; `taskpolicy -c background` twice is a no-op), so there is no double-penalty and no ordering requirement. |
| the deleted-`gate_admit` lint at `postland-verify.sh:1154` | 1 | lint not run | AC5 re-reads it directly (`grep -c`), so row 13 proves the invariant from disk rather than assuming row 1's suite ran. |
| `/usr/sbin/taskpolicy` | OS | absent (non-Darwin, stripped image) | Degrade to `nice -n 19` **with a loud stderr notice** (AC4). Never a silent nice-0 pass — R4. |
| row 4's `~/.claude/cc-beats` session oracle | 4 | **provably inert today** (verified: no `cc-beats` dir, `session-beat.sh` in no live `settings.json`, activation `.done` absent) | **Not consumed.** Row 13's session count comes from `ps` over `claude.exe`, which needs no activation. Noted so a later revision does not reach for the oracle believing it live. |
| row 5's dispatch concurrency ceiling | 5 | ceiling not enforced ⇒ more concurrent workers than planned | Row 13 is **ceiling-agnostic**: demotion makes N concurrent gate bursts yield to interactive work regardless of N. This is the point of choosing priority over admission control (R1) — it degrades gracefully instead of having a cliff. |

**Activation posture (C10).** The shim is a repo file on `PATH`; wiring it into the interactive
`PATH` is an operator step, so it ships staged in `docs/activation/pending-activation/` **and** the
live queue, with the exact command plattered. Until activated the shim is inert — and per R4 the
census must therefore report coverage from the *live* population, so an unactivated shim shows as
0% rather than as success.

## 8. Kill switches (R8)

| Mechanism | Switch | Effect when set |
|---|---|---|
| `bin/cc-bats` QoS shim | `CC_BATS_QOS=off` | exec real bats verbatim, no demotion |
| shim `taskpolicy` resolution | `CC_BATS_TASKPOLICY=<path>` (set-but-empty honoured verbatim) | pin or disable the taskpolicy leg; empty ⇒ `nice` only, with the AC4 loud notice |
| readout damping (M3) | `CC_READOUT_DAMP=off` | always full-render, restoring today's cost exactly |
| watchdog census (M4) | `CC_WATCHDOG_CENSUS=off` | census leg no-ops; reaper otherwise unchanged |
| osascript bound (M5) | `CC_OSA_TIMEOUT_S=<n>` / `CC_OSA_TIMEOUT_BIN=` | retune or disable the bound verbatim |

Set-but-EMPTY must be honoured verbatim at every seam (`${VAR+set}`, not `${VAR:-}`) — a seam that
cannot turn a thing OFF is not a seam.

---

## 9. Open questions / accruing proof

- **AC1 needs a burst to measure.** Coverage during a *quiet* box is meaningless. The read accrues
  the next time ≥2 gates run concurrently; `qos-census.sh` writes a timestamped row so the proof is
  read from disk later, not narrated now.
- **The 81% crash-path exit rate** (3060/3763) is out of scope here but is a real signal for row 2
  (session lifecycle) or row 4 (registry & reaping) — most are deliberate recycles reclassified by
  `classify_death`, but the ratio has never been audited. Named and backlogged, not pursued.

## 8.5 Phase-1 fan-out results (4 read-only axes + adversarial verify)

Every claim below is a subagent's, re-derived by the lead before entry. Corrections are marked.

### 8.5.1 M1 INDEPENDENTLY CONFIRMED — and the population is larger than the lead measured

> "The dominant compute load is un-gated agent-invoked `bats`, not landing gates — every other bats
> path IS bounded, this one has no admission control at all."

**11 concurrent ROOT bats invocations** (not the lead's 8 runs), and **exactly ONE is a
land/verify-class corpus run** — the other ten are agent sessions running the repo's own suites from
Bash tool calls in `wt-10941179f8ec`, `wt-f72db4e3e68d`, `wt-b4e49b4b5014`, `wt-c3dd374de94a`. Both
*derived* paths are already bounded (`ship-land.sh:386,:712` sheds at `CC_GATE_MAX_LOAD`;
`postland-verify.sh:199,:246-262` singleton mutex + the QoS band) — **neither covers a plain
`bats tests/…`**. A grep of `hooks/` for `loadavg|ncpu|MAX_LOAD` finds no term anywhere in the Bash
PreToolUse chain. Verbatim conclusion: *"the fleet bounded every DERIVED test path and left the
PRIMITIVE unbounded."* This is M1, reached independently, and it names the same fix — the chokepoint
plus the nice+taskpolicy band. **`bin/cc-bats` is the right artifact.**

**Follow-on it adds beyond M1 (backlogged, NOT built here):** one admission term in the Bash
PreToolUse chain for test-runner command lines — *admit if load/core < ceiling AND live bats roots
< K, else **DEFER with the exact re-run command** (never kill, never queue-then-run-anyway)*. Note
this is **not** an R1 violation: refusing-and-reporting is shedding, not waiting; `gate_admit` failed
because it *slept*. Distinct from M1 (which needs no policy decision) and lands in row 6's hook
chain, so it belongs to a separate change with its own RED-proof.

### 8.5.2 ⛔ OPERATOR-BLOCKING — the machine-capacity ceilings ALREADY EXIST and are INERT

The single highest-value finding, and it is not a build task:

- `git rev-list --count HEAD..origin/main` = **54**. The shared checkout is 54 commits behind.
- `origin/main:scripts/handoff-fire.sh:819-874` contains `capacity_gate()` — *"P0-17 machine-capacity
  admission gate (lag incident 2026-07-29)"*, ceiling `CC_FIRE_MAX_LOAD_PER_CORE` default **2.0**,
  enforced at `:1634`. Commit `0fc3a3d3`, an ancestor of origin/main.
- `origin/main:bin/cc-dispatch:43-63` contains the decision/admission split with
  `free_slots = max(0, CEILING - live_workers)`.
- **Live layer:** `grep -c capacity_gate ~/.claude/scripts/handoff-fire.sh` = **0**;
  `grep -c CEILING ~/.claude/bin/cc-dispatch` = **0**. The live symlinks point into the *behind*
  checkout, so both landed ceilings are absent from the layer that actually runs.
- The gate's own header records load **27** (2.7/core) when it was written earlier the same day; the
  lead measured **40.9** (4.09/core) hours later — load climbed straight past a landed ceiling that
  would have refused every net-new fire.

This is memory `deploy-lag-checkout-behind-origin` exactly: *landed ≠ deployed*. **Structural answer
(for a later change, not a `git pull`):** a ceiling must be read from a location that *cannot* lag —
bind the hardware term in harness config, not in a symlinked script body — and make inertness LOUD,
so the gate self-reports `capacity_gate: ABSENT` at every spawn rather than silently admitting.

> #### ⚠ RETRACTION — do NOT deploy to "activate the ceiling". The adversarial pass refuted this.
>
> The archaeology above is confirmed line-for-line, **but its two load-bearing inferences are
> false, and acting on them would cause an outage.** Recorded in full because the wrong version of
> this finding was committed first (`2cda5bc6`) and a reader must not act on it:
>
> - **Only ONE of the two is a machine-capacity ceiling (category error).** `cc-dispatch`'s
>   `CEILING` (`:105`, default 6; `FREE_SLOTS` at `:444`) is a **quota-bounded worker-concurrency
>   cap** — its own comment at `:64` binds it to `|accounts| × CC_WAVE_MAX_PER_ACCT = 8`. It never
>   reads cores, load, or memory. Only `capacity_gate()` is a hardware term.
> - **"Nothing bounds net-new spawns" is FALSE.** Two spawn bounds are **live right now**:
>   `~/.claude/bin/cc-dispatch:57 CC_DISPATCH_MAX_SPAWN=2` per tick (enforced `:234`) and
>   `~/.claude/bin/cc-wave-plan:41 CC_WAVE_MAX_PER_ACCT=2` × 4 accounts. Measured: 11 dispatcher
>   fires in 4 h. What is missing is a **hardware** term, not a bound.
> - **~~DEPLOYED AS WRITTEN, `capacity_gate` IS A PERMANENT DISPATCH OUTAGE~~ — RETRACTED, see §9.5: the gate was already live, and at 1.55/core it ADMITS. The measurement below is accurate for its window; the projection from it was not.** Ceiling 2.0/core = load
>   20 on 10 cores. All **13 sampled loads were ≥ 29.15** (≥ 2.92/core, max 59.8) ⇒ the gate's own
>   verdict computes **REFUSE 10/10**. It exempts only `RECYCLE` (`:1634`) and fails open only on an
>   *unreadable* probe (`:852-857`) — a readable, permanently-over-ceiling probe **refuses forever
>   with exit 9**. iTerm2 + XProtect + WindowServer alone are ~2.4 cores and are *not* sheddable by
>   refusing fires, so load would never fall back under the ceiling on its own. This is precisely
>   the `fail-closed-degradation-as-amplifier` trap its own header claims to design around.
>
> **What survives:** the deploy lag is real and **worse than first stated — 68 commits / 3 h 44 m
> behind and actively widening**, and the inertness is confirmed with a positive control
> (`grep -rl vm.loadavg ~/.claude/{hooks,bin,scripts}/` returns **empty** — there is no load-based
> gate anywhere live, and the same grep finds `capacity_gate` at 7 lines in origin/main content, so
> the detector distinguishes deployed from not-deployed). **Root cause found:**
> `launchctl list | grep deploy` shows `com.claude.deploy-live` loaded with **last exit 1**, and
> `~/.claude/autonomy/postland/deploy.log` is wall-to-wall
> `~/.claude/scripts/deploy-live.sh: No such file or directory` — the brand-new-file symlink gap.
> That symlink was since repaired (created Jul 29 10:32) **yet the checkout has not advanced in
> ~22 ticks** and the log stopped writing at 10:28. So the operator item is *"the deployer is
> broken"* (row 1), **not** *"deploy to get your ceiling"*.
>
> **The invariant worth keeping** is that a hardware term must bind somewhere on the spawn path and
> the live layer must not silently lag the landed tree. **The architecture to discard** is 1-min
> `loadavg/ncpu` as the saturation proxy with a fixed 2.0 ceiling and no sustained-saturation
> escape — falsified below (§8.5.7). A redesign must key on a **sheddable** quantity actually
> attributable to sessions, not on a system-wide loadavg dominated by iTerm2 and macOS XProtect.

### 8.5.7 ⛔ THE BIGGEST CORRECTION — load is NOT a function of session count, and the sessions are not the load

This falsifies the framing the whole row was commissioned under, and it must be read before any
future capacity work:

- **Load is a high-variance signal, not a trend.** 13 samples over ~100 s at a **constant 31–32
  sessions**: 29.15, 37.66, 44.35, 45.96, 47.01, 49.94, 50.43, 55.56, 56.96, 56.04, 54.74, 56.24,
  59.80 — a **2.05× swing while session count changed by at most 1**. The lead's 40.9 and the
  verifier's 29.15 were **the same 31 sessions**. So this row's own opening observation —
  "load climbed 27 → 40.9" — is **oscillation, not accumulation.**
- **The 31 sessions are only ~18% of process CPU.** Measured: 31 `claude.exe` = **111.9% total,
  3.61% each (0.036 cores)** of 612.8% total process CPU. Meanwhile **a single `iTerm.app` process
  is 125.2% CPU / 2.17 GB RSS — more than the entire session fleet summed.** Then
  `XprotectService` 61.6%, `WindowServer` 54.3%, `bfs` 31.1%, Chrome ~39%, plus a fork storm of
  177 bash + 64 `-zsh` + 39 zsh + 48 sleep + 36 gitstatusd (1307 procs).
- **Consequence for M1, stated honestly:** the census measures bats at ~0.5–0.7 cores of 10. So
  **M1 is correct, cheap, safe, and NOT the dominant lag term.** It is worth doing — demotion
  *reorders* rather than refuses, so it is the right kind of lever for a load you cannot shed — but
  this plan must not oversell it. The dominant terms are the **TUI renderer** (iTerm2 +
  WindowServer ≈ 1.8 cores), macOS scanning, and **per-event fork churn** (§8.5.4), in that order.
- **Consequence for the exoneration in §3.1/§3.2:** unchanged and strengthened. Memory and leaks
  were never the problem, and the per-session CPU cost (0.036 cores) is smaller than this plan
  first estimated.
- **XProtect is high-variance too, and all three measurements disagree:** axis 3 sampled 89.9%, the
  verifier 61.6%, the lead 0.0% instantaneous / ~4.6% lifetime-average. Treat it as an oscillating
  consumer of order 0.5 cores, never as a stable figure — and never from a single `ps %cpu` read.

Related: **a ceiling was built for RECOVERY spawns only.** `lr-select.py:83-84` caps recovery at
`MAX_TOTAL=4` / `MAX_PER_WORKTREE=1`, and `SESSION_SPRAWL_CONSOLIDATION_PLAN.md` (status `complete`)
states the right principle verbatim — *"the fix is at spawn time, not a reaper"* — but its caller
inventory enumerates only the four resume/recovery callers. The organic paths (handoff-fire net-new
fires, desk fires, Agent-Team assignee spawns) were never given a fleet term. That gap is what
`0fc3a3d3` tried to close 8 days later, and it is undeployed.

### 8.5.3 M3 mechanism identified exactly — pay-then-damp is structural, not incidental

`operator-readout.sh:326` runs `render_block … > "$TMPB"` **first**; the damping latch starts at
`:330` and hashes **the rendered block** at `:333`. So the latch input *is* the expensive output —
the 900 s TTL suppresses *printing* and saves **zero** CPU. Inside `render_block` (108-288): 24
command substitutions, 75 pipeline stages, and per invocation `git`×7, `jq`×6, `cc-backlog`×5,
`cc-blockers`×2, `cc-decide`×2 — including a `git rev-list --count HEAD..origin/main` against the
**one shared checkout's `.git`** from every session's every Stop. This is the structural cause of the
lead's measured 2711 ms.

**Structural answer (refines M3):** invert the latch input — damp on a *cheap* change-stamp computed
**before** rendering (HEAD sha + a trunk-distance cached by a single writer, × mtimes of
`pending-activation/`, `decisions/`, backlog jsonl) and render only on stamp change or TTL expiry.
Separately, the shared-checkout deploy-lag read must be produced **once by a single writer** into a
file every session reads, never recomputed N times against one contended `.git`.

### 8.5.4 NEW — the hook chain is O(N²), and it is fork-dominated not work-dominated

Measured at load 58.4: 40 × `bash -c 'exit 0'` = **13.38 ms wall vs 6.78 ms child CPU ⇒ 49% pure
scheduler queueing**. At load 69.2: bash fork+exec 15.5 ms, zsh 17.9 ms, jq startup 15.1 ms,
`git rev-parse HEAD` 15.0 ms, **python3 startup 68.7 ms**. Fork-inducing `$(` counts on the
per-Bash-call chain: `waiting-recycle.sh` **131**, `teammate-checkpoint.sh` 17, `validate-bash.sh` 13.
So the lead's 1037 ms ≈ 67 forks and 3688 ms ≈ 238 forks.

**Why it is O(N²):** forks/s is O(N); cost-per-fork is O(load); load is O(forks/s). Measured
inflation already 2× (6.78 ms of work billed at 13.38 ms). **This revises the lead's §1 conclusion
that hook cost is a benign ~0.9 cores** — that figure was measured *at* high load and is therefore
partly self-inflicted, and it grows super-linearly rather than linearly. Structural answer: stop
paying process creation per event — one long-lived per-session hook **broker** over a pipe, or as a
bounded fallback collapse the 5 PreToolUse/Bash hooks into one process and the 9 Stop hooks into one.
Owner: **row 6** (hook layer), with this row supplying the O(N²) measurement.

Also on the hot path: `waiting-recycle.sh:536` does a **full-file `jq` parse of the session
transcript on every PostToolUse** — O(transcript size), which grows monotonically within a session.

### 8.5.5 Additional leak-class findings (row 13 backlog; none built here)

| Finding | Evidence | Owner |
|---|---|---|
| `cc-backlog` full-slurp on the **Stop hot path** — O(records-ever-filed), 0.80 ms/record | axis 4 | 10 / 13 |
| `session-index.db` has **zero retention** (299-day span, 5788 rows), opened by 3 sqlite3 procs | axis 4 | 9 |
| **10 of 28 launchd plists on disk are absent from the live layer** — the GC/reaper layer is staged-not-loaded | axis 2 & 4 | 12 |
| `postland-verify`: a **300 s launchd interval wrapping a 10,800 s** corpus (self-overlap risk; it does hold a mutex) | axis 2 | 1 |
| `cc-classify` inside `cc-reaper`: O(live_sessions × 4 account roots × corpus) filesystem walk | axis 2 | 4 |
| `idl.jsonl` is one **17.5 MB** append-only file, full-grepped **4× per `cc-audit` call** | axis 2 | 10 |
| `log-bash.sh` appends unbounded; `bash-execution.log` is **23% over its own stated cap** | axis 4 | 6 |
| 168 stale files in `~/.claude/watchdog` (oldest 100 d); worktree janitor covers 1 of 5 owning repos | axis 3 & 4 | 11 |

### 8.5.6 Lead corrections to the fan-out's own claims (re-derived before entry)

- **"XProtect + syspolicyd burn ~97% of one core" — NOT SUPPORTED at that magnitude.** Re-derived:
  `XprotectService` pid 903 is at **0.0% CPU** now, with `TIME` 122:50 over `ELAPSED` 1d20h33m =
  **~4.6% of one core lifetime-average**; `syspolicyd` 78:41 over the same span = ~2.9%. The reported
  89.9% is the **same `ps %cpu` lifetime-average trap** the lead recorded in §1.1 — and it is
  self-contradicted by the `TIME` column in the agent's own evidence. Combined, these scanners are
  ~0.3 cores, not ~1. **The worktree sprawl underlying it IS real and re-derived: 131 dirs, 114 GB,
  4.26M files** (a plain `du` over it exceeded a 2-minute timeout, which is itself evidence of
  scale). Kept as a row-11 sprawl item; **dropped as a CPU finding.**
  Also: the proposed `.metadata_never_index` fix is a **Spotlight** exclusion, and the same report
  exonerates Spotlight (`mds` 1.1%, `mds_stores` 0.7%) — it would not reclaim XProtect time. The
  agent's structural answer conflated the two scanners.
- **The lead's own "19.7 GB across 31 sessions" overcounts by ~2.34×** — `ps rss` double-counts
  shared pages; true footprint ≈ 8.4 GB. Session count and per-process RSS re-derive correctly.
  **This makes §3.1's memory exoneration stronger, not weaker.**
- **The lead's "RSS flat with age" used the wrong instrument** (`rss` rather than phys_footprint).
  The *conclusion* (no per-session leak) is unchallenged — fd-flatness and the 30 h/417 MB vs
  33 min/700 MB spread both still hold — but the instrument is named here so a later revision
  re-derives it with `footprint(1)`.
- **"8 concurrent gate runs" → 11 concurrent bats roots** (68-87 bats-family procs at sample time).
  Strengthens M1.
- **"69 hook commands" — CONFIRMED** by independent re-derivation.
- **Method warning worth keeping:** `launchctl print`'s `runs =` field is **not** a reliable run
  counter; trusting it would have produced two false duty cycles.

## 9.1 Build-phase measurements — three Darwin constraints that changed the design

Discovered while building M1 (`bin/cc-bats`, `scripts/qos-census.sh`, `tests/qos-chokepoint.bats`).
All three were found by the artifacts' own tests failing, which is the proof bar working.

1. **`nice` alone does NOT demote on Darwin.** Calibrated with known controls:
   `nice 19 + taskpolicy -c background` → `NI=20 PRI=4`; **`nice 19` alone → `NI=20 PRI=31`** —
   still full interactive priority; a plain proc → `PRI=31`. So `taskpolicy -c background` is the
   load-bearing mechanism and `nice` is nearly cosmetic for contention. **Consequence for row 1:**
   its documented fallback at `postland-verify.sh:168` ("absent `taskpolicy(8)` ⇒ nice alone, never
   a hard fail") is right not to hard-fail, but the fallback it names does not achieve the demotion
   its neighbours assume. `cc-bats` therefore treats nice-only as a **WARNING** state, and the
   census refuses to count it as covered.
2. **The background band is a ONE-WAY RATCHET.** A plain child of a demoted parent *inherits*
   `PRI=4`; `taskpolicy -B -p <pid>` does **not** lift it (verified: stayed 4); and there is no
   `default`/`none` QoS clamp (only `utility`/`background`/`maintenance`). So a known-FULL control
   process **cannot be constructed from inside a demoted process**. A two-sided positive control
   calibrated for a full-priority caller is therefore *unrunnable* from a demoted caller — and
   reporting FAIL there would be a false conviction (a bound under what it measures can only
   convict). Hence the census has **four** control states, reads its own band first, and reports
   `AMBIENT-DEMOTED` rather than `SIGNAL-DEAD` when fired from inside a gate.
3. **CPU-weighted coverage is the wrong thing to GATE on.** A demoted proc that is *sleeping*
   contributes `0.0` to `ps %cpu`, so CPU coverage reads 0% even when every proc is correctly
   demoted. (A CPU-*active* demoted proc registers fine — verified 14.4% at `PRI=4`.) The gate is
   therefore **proc coverage**; CPU coverage is reported as the impact metric. AC1 was rewritten.

**End-to-end demonstration (2026-07-29, live box).** Baseline census: 4 gate runs in flight,
**0/47 procs demoted, verdict FAIL** — the defect reproduced from disk truth. With two
shim-wrapped runs added: **12/57 demoted (21.1%)**, i.e. the shim demotes its entire descendant
tree. Coverage stays FAIL because the other sessions' runs are unshimmed — which is precisely what
the PATH activation fixes, and is why AC1 can only be *proven* after activation, during a burst.

**Proof status of M1:** `tests/qos-chokepoint.bats` — **16/16 GREEN** on the change tree;
**15/16 RED** against the pristine `git archive` of base `6ce912b3` (the sole pass is the
deliberately tree-independent grep control). The first RED run caught **two vacuous tests of my
own** — `[ ! -f "$log" ]` and a `grep` absence assertion both pass trivially when their subject
does not exist — now guarded by explicit existence assertions.

## 9.2 M3 BUILT — the readout now damps before it pays

`hooks/operator-readout.sh`: a **cheap pre-render change-stamp** gates `render_block`. The stamp is
`stat` on the activation dir / decisions dir / backlog file, plus this cwd's `HEAD` and dirty count,
plus the shared checkout's `origin/main` — read with `rev-parse` (a ref read), never `rev-list` (a
commit walk). Two bounded `git` calls and three `stat`s replace ~100 forks.

| Measure | Before | After |
|---|---|---|
| `operator-readout.sh`, steady-state turn | **2711 ms** | **140 ms** (19x) |
| Full Stop chain, steady state | **3688 ms** | **882 ms** (AC6 met) |
| Rendered block | - | **byte-identical** (`--render`, old vs new, same tree) |
| `CC_READOUT_DAMP=off` | - | 3626 ms - restores the old path exactly |

**Safety properties, deliberately chosen:**
- The stamp may only suppress **inside the TTL the latch already enforced**. An expired latch always
  re-renders, so the worst case is a stamp-invisible change going unreported for <= TTL - the
  staleness bound the operator already lives with. It can never suppress *past* the TTL.
- Dirty-tree state is read with a real `git status`, **not** a `.git/index` mtime, so an unstaged
  edit cannot slip through that window.
- When the stamp moves but content doesn't, the new stamp is persisted **with the original
  timestamp**. Refreshing the ts there would let a never-changing block suppress its own 15-minute
  re-assert indefinitely just by being touched - a silent loss of the operator's re-assert guarantee.
- A pre-M3 two-field latch is never read as a match; an absent field is "unknown", which falls
  through to a render and upgrades the format.

**Proof:** `tests/operator-readout.bats` **26/26 green**; **4 of 5** changed/new tests RED against a
pristine `git archive` of `c43ed39c` (the fifth is a deliberate behaviour-preservation positive
control that must pass in both trees).

**One existing test was deliberately changed, not relaxed.** Test 14 asserted the abstain reason
`latched-ttl`; the cheap gate introduces a second reason (`stamp-unchanged-ttl`), so the test now
names **both** paths - strictly more precise than before. Verified first that the reason string has
no consumer outside that file (`grep -rn 'latched-ttl'` over `*.sh`/`*.bats`/`*.md` **and** the
extensionless `bin/` - hits only the hook and the test). Recorded here per the map's binding rule
that a test encoding a superseded premise may be changed only deliberately and never quietly.

## 9.3 M6 BUILT — the ceiling now has an alarm, and it is an ALARM not a GATE

`scripts/capacity-alarm.sh`. The design boundary is the whole point: the landed `capacity_gate()`
is the cautionary case (REFUSE 10/10 against real samples = permanent dispatch outage), so this
reports and exits — it never refuses, blocks, queues, sleeps or polls (R1), and test (xiii) fails if
a refusal verb ever appears.

**Instrument choice, because the obvious ones lie:** not `loadavg` (2.05x swing at constant session
count, not session-attributable), and not summed `ps rss` (overcounts shared pages ~2.34x). What
decides whether the box swaps is **reclaimable headroom** = free + speculative + inactive +
purgeable, with `vm.swapusage` used > 0 as the hard (lagging) signal.

Four verdicts, never a boolean: `OK` (0) · `WARN` (1) · `ALARM` (2) · **`NO-DATA` (3)**. The fourth
is load-bearing — a capacity alarm that reads OK when it cannot measure actively asserts safety.
Live: 8 sessions, 29.3 GB headroom, room for ~47 more, `OK`. Proof: **13/13 green**, **12/13 RED**
against a pristine archive.

**Three defects this file's own tests caught, each a named memory:**
1. `python3 -` with a heredoc **ate the piped `vm_stat`** — the program is read from stdin, so the
   heredoc claimed the data channel and the alarm reported permanent `NO-DATA` (memory
   `blind-check-generators-stdin-and-sid-keys`; shellcheck SC2259). Fixed to `python3 -c`. The
   four-state design is what surfaced it: a boolean would have said "fine".
2. Swapping the process census for a name-matcher to satisfy SC2009 **silently undercounted to 0
   with 8 live sessions** — macOS matches a truncated argv, so a long absolute path never matches.
   That is `actuator-must-see-the-target-population` (134/134 MISS): a counter reading 0 forever
   would have made the alarm report an empty fleet. Reverted, measurement recorded inline.
   **Verify a census instrument against a known population before trusting it.**
3. The R1 "never sleeps" guard **matched the script's own prose**, convicting the documentation of
   the property it checks (`detector-matching-its-own-skill-description`). Comments are now stripped
   before matching, with a control proving the stripping did not defang it.

## 9.4 AC1 IS NOT MET, AND A PATH SHIM CANNOT MEET IT — measured after activation

The operator activated the shim (2026-07-29 18:01). It works, and it is transparent: a full suite
run through it passes unchanged, and **every post-shim PATH invocation is demoted** — verified as a
property, not a hope, by classifying each live `bats-exec-suite` as pre/post-shim by age and
checking its band.

Coverage accrual, from the durable census log:

| When | Runs in flight | Demoted/total | Verdict |
|---|---|---|---|
| pre-shim (22:29) | 6 | 12/57 = **21.1%** | FAIL |
| shim active, quiet (01:05) | 4 | 14/48 = **29.2%** | FAIL |
| shim active, 3-run shimmed burst | 7 | 32/64 = **50.0%** | FAIL |

**But the residual is not all drain.** One post-shim run persisted at `pri=31` across four samples.
Its parent chain names the cause exactly:

```
timeout 90 /opt/homebrew/bin/bats tests/handoff-fire-validate.bats
```

**An absolute-path invocation never consults `PATH`, so a `PATH` shim cannot see it.** Measured
distribution of live top-level invocations: **~6 absolute-path vs ~14 PATH-based — roughly 30%
structurally uncovered.** The callers are *agents typing the absolute path in Bash tool calls*, not
our own scripts: the only in-repo absolute reference is `bin/cc-bats`'s own fallback resolver.

**So AC1 as written (≥95%) is unreachable by M1 alone, and this row should not claim otherwise.**
The standing constraint — *the caller cannot be trusted* — bites one level deeper than the design
answered. M1 raised coverage from 21% toward a ~70% ceiling; it did not remove the failure class.

**Two ways to actually close it, neither taken here (both need an operator decision):**
1. **Shim the Homebrew path itself** — point `/opt/homebrew/bin/bats` at `cc-bats` (it is currently a
   symlink to `../Cellar/bats-core/1.13.0/bin/bats`), and add the Cellar path to `cc-bats`'s resolver
   so it can still find the real binary. Covers both invocation forms. Costs: it mutates a
   package-manager-owned path machine-wide, and `brew upgrade bats-core` silently restores the
   original — so it needs a parity check to stay true. **Escalation surface: operator's call.**
2. **One admission term in the Bash `PreToolUse` chain** for test-runner command lines — the
   independent Phase-1 recommendation (§8.5.1). Sees the command line regardless of how bats is
   spelled, so it covers both forms. Must **DEFER with the exact re-run command, never queue-or-sleep**
   (R1). Lands in row 6's hook chain, so it is a separate change with its own RED-proof.

**What M1 is worth, stated honestly:** it removes the *largest single* uncovered class (hand-typed
`bats tests/…`, the form `CLAUDE.md` itself instructs) at O(1) cost and zero caller effort, and it is
verifiably transparent. It is a real improvement with a named ceiling — not the complete fix the
acceptance criterion asked for.

## 9.5 SELF-CORRECTION — my "permanent dispatch outage" projection is FALSIFIED

Two claims this row made about the landed `capacity_gate()` need retracting, and both were mine.

**1. "It is inert / there is a deployment to withhold" — WRONG.**
`~/.claude/scripts/handoff-fire.sh` is a **symlink into the shared checkout**, so for that file
*landing IS deploying* and the staged-activation frame never applied. Verified on the DEPLOYED copy:
default **ON** (`CC_FIRE_CAPACITY_GATE:-on`), ceiling `CC_FIRE_MAX_LOAD_PER_CORE:-2.0`, net-new fires
refused with `exit 9`; `--recycle` exempt by design. The gate has been live all along. My §8.5.2
"INERT in the live layer" reading came from grepping `~/.claude/scripts/handoff-fire.sh` at a moment
the checkout was 54-68 commits behind — the symlink was resolving to an older file body, which is a
real deploy-lag fact but NOT the same as "the mechanism is absent".

**2. "Deployed as written it is a permanent dispatch outage" — OVERSTATED, and now measured false.**
That projection came from 13 samples in a window where load sat at 29.15-59.80 (2.92-5.98/core), all
above the 2.0 ceiling. It assumed load would never fall back. **It did:** measured after the fleet
drained from 31 sessions to 8, `loadavg1 = 15.5` on 10 cores = **1.55/core ⇒ the gate ADMITS.** And
the IDL carries **1498 `"reason":"capacity"` rows**, i.e. the gate has been exercising both verdicts,
not wedged on one. A ceiling that refuses at 4.0/core and admits at 1.55/core is behaving as a
ceiling, not as an outage.

**What survives, and it is still worth having:** the gate keys on a quantity that is *not*
session-attributable (§8.5.7 — loadavg is dominated by the TUI renderer and macOS scanning, and swung
2.05x at constant session count), so *what* it throttles is only loosely related to *what* is
consuming the box. That criticism of the instrument stands. The prediction about its operational
effect did not.

**The generalisable lesson — and it is the same one this row keeps re-learning, now against itself:**
a projection from a single high-variance window is not a measurement. §8.5.7 established that
loadavg swings 2× at constant session count; I then built a "permanent" claim on 13 samples drawn
from one side of that swing. Re-derive before gating a decision on it — *including* when the claim is
your own, and especially when it is the one you stated most forcefully.

## 9.6 AC1 CLOSES AT ~70% — "shadow mode" REJECTED 3/3 by adversarial review, and it found a live bug

§9.4 named two ways to reach AC1's >=95%. Option A (repoint `/opt/homebrew/bin/bats` at the shim) was
built, reviewed by three independent lenses, and **all three returned DO-NOT-BUILD**. It is not
staged, and the activation was deleted rather than left lying around.

**Why it was rejected — a closed 2-cycle, measured, not theorised.** `pwd -P` physicalises the
DIRECTORY only and never the final symlink, so `self_phys` was the SYMLINK's path. Two symlink paths
to the SAME script therefore compared as DIFFERENT files, the self-skip could not fire, and with TWO
shims on PATH the run became a closed 2-cycle: shim A execs B, B (already `CC_BATS_ACTIVE=1`) execs A.
Reproduced independently: **134 resolution legs split exactly 67/67 between the two paths**, rc=137,
~200 fork+exec/s, **zero output**, sustained indefinitely. And **two shims is precisely the state
option A creates** — `~/.claude/bin/bats` at PATH position 1 plus `/opt/homebrew/bin/bats` at 16,
with six live/staged plists exporting exactly that PATH. A mechanism whose *purpose* is to reduce
machine load, whose *default post-install state* can fork-storm the box, is not worth 0.2-0.3 cores.

**What the review earned us anyway — a latent defect in the SHIPPED, LIVE shim.** The same
dir-only physicalisation is in the shim that is deployed right now. It is harmless today because the
box has exactly ONE shim (verified: `/opt/homebrew/bin/bats` is still Homebrew's real binary), but it
would fire the moment any second shim or symlink chain appeared. Fixed regardless of the rejected
proposal:

- `phys_of()` — a single helper resolving the FULL symlink chain via `/usr/bin/readlink -f`,
  addressed **absolutely** so it cannot depend on `PATH`.
- An **unresolvable candidate now SKIPS**. Treating "I could not resolve this" as "therefore it is
  not me" was the precise inversion that produced the loop.
- If the shim cannot establish its OWN identity it **refuses with 127** rather than proceeding
  blind. "Cannot determine self" is a third state, not a reason to continue.
- A second, independently-found instance of the same class: `$(dirname …)`/`$(basename …)` on a
  minimal PATH yielded empty, and `cd ""` **silently succeeds** — same collapse, same loop, and a
  valid seed did NOT rescue it (`seeded_phys` collapsed identically and was rejected as "self").

Measured before → after, two shims on PATH: **rc=137 / indefinite / no output → rc=0 / 0s** across
seed absent, valid and stale. Minimal PATH: **infinite loop → rc=127 in 0s**.

**Also corrected, both found by review:** the parity lint defaulted its seed to
`$CLAUDE_CONFIG_DIR/state/cc-bats-real` while the shim reads `$HOME/.claude/...` — on this box those
differ (`~/.claude-secondary` vs `~/.claude`), so the lint judged a path nothing reads and would have
reported the healthy-looking `NOT-ACTIVE` **while shadow mode was live**: the brew-fragility watchdog
silently inert, the exact failure class it exists to catch. And its `STALE-SEED` grade of
"silent-but-not-fatal" was **measured false** — with two shims a stale seed never reached the Cellar
sweep, because the PATH walk returned the sibling shim first.

**THE DECISION, plainly: AC1 is CLOSED AT ~70% and that is the final answer, not a deferral.**
The acceptance criterion was written before the invocation distribution was known. Option A is
rejected on evidence. Option B (a Bash `PreToolUse` admission term) remains available but belongs to
row 6 and would add per-tool-call fork cost to the chain this row measured as the O(N^2) term — which
is self-defeating for this row's own goal. What shipped removes the largest single uncovered class
(the hand-typed `bats tests/…` form `CLAUDE.md` itself instructs) at O(1) cost and zero caller effort.

## 9.7 ⛔ AC1 IS **MET** — the ~70% ceiling was a CONTAMINATED INSTRUMENT, not a real gap

A completeness critic re-derived §9.4's population and found the census denominator polluted. This
retracts §9.4 and §9.6's coverage arithmetic. The census counted ANY process whose argv contained
"bats"; measured live that was 157 rows of which only 114 were real bats processes:

| class | rows | of which `pri=31` |
|---|---|---|
| **real bats internals** | **114** | **0** |
| `timeout` wrappers | 6 | 6 |
| shell `-c` lines | 17 | 17 |
| claude sessions | 19 | 18 |

**Every single `pri=31` row was pollution.** A `timeout 800 bats …` wrapper legitimately sits at
`pri=31` while every bats child it spawned is at `pri=4` — reproduced on three live wrappers — so it
manufactures exactly the "uncovered" signal this tool exists to detect.

**Re-derived with a clean denominator:**

| instrument | reading |
|---|---|
| contaminated | 112/153 = **73.2% FAIL** ← this is where "~70% ceiling" came from |
| clean | **92/92 = 100.0% PASS** |
| clean + one deliberately-undemoted run | 90/96 = 93.8% **FAIL** (still detects real undemotion) |

**Consequences, stated plainly:**
- **AC1 (≥95%) is MET.** It was never ceilinged; the ceiling was an artifact.
- **§9.4's "~6 absolute vs ~14 PATH ⇒ ~30% structurally uncovered" is FALSIFIED.** Its sole evidence
  — `timeout 90 /opt/homebrew/bin/bats tests/handoff-fire-validate.bats` — is a *wrapper* argv,
  which reads `pri=31` even when the run beneath it is fully covered.
- **The shadow-mode rejection (§9.6) STANDS and is now doubly right.** It rested on the measured
  fork-storm, which is independent of coverage — and there was never a coverage gap to justify the
  risk in the first place.
- The three historical rows in `qos-census.jsonl` carry the polluted denominator and must not be
  compared against post-fix rows. `QOS_CENSUS_STRICT=off` reproduces the old behaviour for exactly
  that comparison, never for a verdict.

**The fix, and a defect inside the fix.** The first correction excluded rows containing `timeout `,
`<shell> -c ` or `claude` — and that was **worse than the contamination**: this repo's own primary
checkout is `/Users/chrisren/Development/claude-infrastructure`, so `grep -v claude` deleted GENUINE
bats rows whose test path merely contained the word. Measured against one live run: **strict saw 0
rows, permissive saw 5 — and all 5 were real bats processes at `pri=31`**, i.e. precisely the
undemoted population the census exists to find. A census reporting 100% with a whole undemoted run in
front of it is worse than one that over-counts.

The shipped discriminator is therefore **positional, not a blacklist**: bats execs its internals as
`bash <…>/libexec/bats-core/bats-exec-*`, so the libexec path must occupy argv field 5 or 6
(`ps -eo pid,nice,pri,%cpu,args`). That admits every real bats process regardless of what its test
paths are called, and rejects the wrapper classes by construction — no word can become collateral
damage. Verified both ways: a `claude`-pathed run is now counted (73/73 = 100% PASS), and 36
wrapper/shell/session rows are still dropped, **28 of which were at `pri=31`**.

**Also fixed:** the census's self-band read raced its own `taskpolicy` exec, transiently reading
`pri=31` and producing a spurious `SIGNAL-DEAD` (~1 run in 5 inside a suite, 0 in 11 direct
invocations). Now sampled three times with any-demoted-wins — biased toward the honest
`AMBIENT-DEMOTED` degradation, never toward a false signal-death. **0 failures in 6 runs.**

**The lesson, which this row had already written down and then repeated.** §1.1 and §10 both record
a path-substring classifier miscounting sessions as hooks. The census made the same mistake in a
different file, in the same session, and *then the first fix made it again in the opposite
direction*. Substring presence in an argv is not evidence that a process IS the thing. Anchor on
structure — a field position, an executable path — and positive-control the DENOMINATOR, not only
the classifier.

## 10. Learnings (accumulate; never delete)

- 2026-07-29: The row's own framing was wrong in the *direction* the map's row-5 learning predicts.
  The goal named "lag / memory pressure / leaks"; measurement exonerated memory (44.7 GB @30 of
  64 GiB) and both leak candidates (RSS flat with age, fds flat with age, watchdogs correctly
  1:1 with sessions), and relocated "lag" from volume to **priority**. Re-deriving the constraint
  first is what prevented a redesign aimed at the wrong resource.
- 2026-07-29: Two of the lead's own hypotheses were refuted by its own next check — PID-reuse
  keeping watchdogs alive (all 33 pidfiles resolve to live sessions) and an 11.22 GB hook-RSS
  figure (a path-substring classifier counting real sessions as hooks; true value 0.15 GB).
  **Both were cheap to check and would have been expensive to design against.** Recorded because
  the failure mode is generic: a plausible mechanism plus a big-looking number reads as a finding.
- 2026-07-29: `ps %cpu` is a lifetime average. It understated `claude.exe` by ~4× (33% vs 129%).
  Any CPU claim in this repo should cite `top -l 2` second-sample.
