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

---

## 4. Failure-mode table — every observed mode → its structural answer

A mode without an answer is an unfinished design.

| # | Observed failure mode | Evidence | Structural answer (the inversion) |
|---|---|---|---|
| **M1** | Gate corpus runs at interactive priority, starving 31 sessions | 72/103 bats procs `pri=31`; QoS coverage 0% of CPU | **Move the QoS band from the caller to the tool.** A `bats` shim earlier on `PATH` re-execs the real bats under `nice -n 19` + `taskpolicy -c background`. Inversion: *the tool demotes itself, so no caller can forget.* O(1) code, covers hand-typed, scripted, and launchd invocations alike. |
| **M2** | Load-gated admission control amplifies contention | `gate_admit` deleted: ~2 h sleeping/run; 5 gates self-starving at load 16–18 vs their own ceiling of 8 | **Keep it deleted (R1).** Demote priority; never queue, never sleep. The existing lint at `postland-verify.sh:1154` is the enforcement — extend it to the new shim rather than duplicating policy. |
| **M3** | Stop chain costs 3688 ms/turn; one hook is 73% of it | `operator-readout.sh` = 2711 ms, min-of-2 | **Make the readout's cost proportional to *change*, not to every turn.** It re-renders disk truth unconditionally; it already has damping semantics for *display* (15-min re-assert) — push that damping *below* the expensive reads so an unchanged state is a cheap stat, not a full render. |
| **M4** | Watchdog spawn/exit ledger does not balance (~102 lost); liveness test is unsound past one PID wrap | log accounting; `lead-crash-watchdog.sh:601` bare `kill -0` vs R5; PID wrap every 5.05 h | **pid+lstart liveness + a census leg with a positive control.** Makes "no orphans" distinguishable from "nobody looked" (R6), and makes the residue countable before it is optimised. |
| **M5** | 31 unbounded `osascript` sites share one serialized AppleEvent channel | `grep`; documented machine-wide iTerm2/AppleEvent wedge 2026-07-26, cited in `lead-crash-watchdog.sh:18` | **Universalize the bound that already exists.** The `lcw_osa` helper is the proven shape; hoist it to one sourced helper and convert the 31 bare sites. Bound must fit what it bounds (R7) — not idle-calibrated. |
| **M6** | Session ceiling is unstated, so pressure would be discovered by swapping | 44.7 GB @30, 57.2 GB @50, no guard | **State the ceiling (≈50) and alarm on the leading indicator** (compressor growth / swap > 0), not on the lagging one (already swapping). |

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
| **AC1** | ≥95% of bats **CPU** runs at `pri≤10` during a gate burst | `scripts/qos-census.sh` → `coverage_cpu_pct` | **0%** |
| **AC2** | 0 top-level bats invocations at `pri=31` | `ps -eo pri,args \| grep -E 'bats( \|$)' \| awk '$1==31'` → empty | **72 procs** |
| **AC3** | The shim covers the hand-typed form | `cd <worktree> && timeout 5 bats --version` then census the child's `pri` → `≤10` | n/a (no shim) |
| **AC4** | The shim FAILS LOUD when `taskpolicy` is absent (R4) | `PATH=/usr/bin:/bin CC_BATS_TASKPOLICY= bin/cc-bats --version` → non-zero **or** an explicit stderr degradation notice; never a silent nice-0 pass | n/a |
| **AC5** | `gate_admit` stays absent (R1/M2) | `grep -c '^[[:space:]]*gate_admit' scripts/postland-verify.sh` → `0`; the existing lint still passes | `0` ✓ |
| **AC6** | Stop chain ≤1500 ms | min-of-3 timing of the 9 Stop hooks with a probe payload | **3688 ms** |
| **AC7** | `operator-readout.sh` unchanged-state path ≤300 ms | min-of-3 with an unchanged state marker | **2711 ms** |
| **AC8** | The rendered readout block is byte-identical before/after M3 | diff `operator-readout.sh --render` output across the change on a fixed fixture | — |
| **AC9** | Watchdog census balances, with a positive control (R6) | `cc-reaper --watchdog-census` → `spawned/live/exited/lost` + a `control=OK` line proving the detector fires | ledger off by **~102**, no census exists |
| **AC10** | Watchdog liveness uses pid+lstart (R5) | `grep -c 'lstart' hooks/lead-crash-watchdog.sh` → `>0`; RED-proof asserts a recycled-PID fixture is classified dead | bare `kill -0`, line 601 |
| **AC11** | 0 unbounded `osascript` sites in `hooks/` (R7) | `grep -rn '^[^#]*osascript' hooks/ \| grep -vE 'timeout\|_osa\|TB' \| wc -l` → `0` | **31** repo-wide |
| **AC12** | Session ceiling stated + alarmed (M6) | the ceiling appears in this doc §1 **and** a live read alarms on `sysctl vm.swapusage` used > 0 | unstated |
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
