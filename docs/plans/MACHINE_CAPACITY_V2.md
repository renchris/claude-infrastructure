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
  can return immediately). ~~33 watchdogs for 33 sessions is correct steady state~~ — **⚠ ARITHMETIC
  CORRECTED 2026-07-30 (the exoneration STANDS; only its count identity was wrong).** §1 measures the
  fleet at **31 real sessions**, not 33, so "one watchdog per session" cannot be what 33 daemons
  means, and the doc previously asserted both numbers. The true reading is **33 daemons against a
  31-session fleet — a 2-daemon surplus, not a 2-session undercount.** Disk evidence for *why*, and
  it is not sample drift: sibling commit `2f62ee62` (2026-07-29 17:48, *"single-instance guard +
  one-handler-per-death — watchers accumulated per SessionStart"*) records that this hook spawned a
  detached daemon on **every** SessionStart — startup **and** resume **and** clear **and** compact —
  with nothing retiring the previous incarnation, so a long-lived pane accumulated multiple watchers
  all polling the same lead pid (measured in the live log at the time: 3064 "LEAD CRASH detected"
  lines across 2597 distinct pids, one pid recorded **19** times). A daemon count **above** the
  session count was therefore the expected state, and 1:1 was never a measured invariant. **Why the
  exoneration is unaffected:** it rests on a *per-pidfile* property — every pidfile resolving to a
  **live** session, i.e. no daemon outliving its subject — which is exactly what was checked, and
  which duplicate watchers on a live session satisfy. The cost claim is likewise per-daemon (~2 MB,
  0% CPU each) and does not depend on the ratio. What the correction *does* retire is the implicit
  "therefore nothing is accumulating": the duplicate-per-SessionStart accumulation is real, was fixed
  by `2f62ee62`, and is a second, independent reason the §10 learning's phrase *"watchdogs correctly
  1:1 with sessions"* should be read as "no watchdog outlives its session", never as a count identity.
  **My own PID-reuse hypothesis was refuted by this check** — recorded because the hypothesis
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
| **AC1-b** ✅ **MET** | `coverage_cpu_pct` reported alongside, as the impact metric — **not** the gate | same JSON row → `coverage_cpu_pct`, `gate_on`. **Evidence 2026-07-30:** latest row of `~/.claude/logs/qos-census.jsonl` = `…"coverage_proc_pct":100.0,"coverage_cpu_pct":100.0,"threshold":95,"demoted_pri_max":10,…,"gate_on":"proc"` — CPU is reported and `gate_on` names **proc**, so CPU is explicitly not the gate. `grep -c coverage_cpu_pct` → **8 of 8** rows; `grep -c gate_on` → **6 of 8** (the 2 earliest rows predate the field, consistent with §9.7's "do not compare historical rows") | 0% |
| **AC2** ✅ **MET** — via the corrected instrument; the row's own read is **RETIRED** (note [a]) | 0 top-level bats invocations at `pri=31` | ~~`ps -eo pri,args \| grep -E 'bats( \|$)' \| awk '$1==31'` → empty~~ — **this read is contaminated exactly as §9.7 describes and must not be used** (note [a]). **Corrected read, 2026-07-30:** (i) positional discriminator — `ps -eo pid,nice,pri,%cpu,args \| awk '($5 ~ /libexec\/bats-core\/bats-exec/ \|\| $6 ~ /libexec\/bats-core\/bats-exec/) && $3==31'` → **0 rows**; all 16 real bats procs live read `pri=4`. (ii) `scripts/qos-census.sh` @ `2026-07-30T08:21:26Z` → `runs_in_flight 5 · procs_demoted 32/32 · procs_full 0 · control OK · VERDICT PASS` | **72 procs** |
| **AC3** ✅ **MET** | The shim covers the hand-typed form | `cd <worktree> && timeout 5 bats --version` then census the child's `pri` → `≤10`. **Evidence 2026-07-30:** `which bats` → `/Users/chrisren/.claude/bin/bats` → symlink → `…/claude-infrastructure/bin/cc-bats`. Live proof from a caller measured at `pri=31` (`ps -o pid,nice,pri -p $$` → `NI 0 PRI 31`): a hand-typed `bats <tmp>.bats` produced the child `/usr/bin/env bash /opt/homebrew/bin/bats …` at **`ni=20 pri=4`** — demoted, and the shim still resolved the real binary | n/a (no shim) |
| **AC4** ✅ **MET** | The shim FAILS LOUD when `taskpolicy` is absent (R4) | `PATH=/usr/bin:/bin CC_BATS_TASKPOLICY= bin/cc-bats --version` → non-zero **or** an explicit stderr degradation notice; never a silent nice-0 pass. **Evidence 2026-07-30:** run verbatim → stderr `cc-bats: WARNING — taskpolicy(8) unavailable. nice -n 19 alone does NOT move PRI off 31 on Darwin, so gate work will still compete with interactive sessions. QoS effectively NOT applied.` The same run with `2>/dev/null` emits only `Bats 1.13.0`, proving the notice is on **stderr** and not a stdout artifact. rc=0 ⇒ the criterion's *explicit-notice* branch, not a silent pass | n/a |
| **AC5** ✅ **MET** | `gate_admit` stays absent (R1/M2) | `grep -c '^[[:space:]]*gate_admit' scripts/postland-verify.sh` → `0`; the existing lint still passes. **Evidence 2026-07-30:** count = **0**; the lint survives at `scripts/postland-verify.sh:1245-1247` and its own `grep -qE '^[[:space:]]*gate_admit' "$SELF"` returns non-zero ⇒ the `okp` branch ("no admission control anywhere in the runner"), never `badp` | `0` ✓ |
| **AC6** ✅ **MET** | Stop chain ≤1500 ms | min-of-2/3 timing of the 9 Stop hooks, steady state | **3688 ms → 882 ms** |
| **AC7** ✅ **MET** | `operator-readout.sh` unchanged-state path ≤300 ms | min-of-3, warm latch | **2711 ms → 140 ms** (19×; cold render still 3221 ms, by design) |
| **AC8** ✅ **MET** | The rendered readout block is byte-identical before/after M3 | `--render` old-vs-new on the SAME tree → identical sha `707c143f78f66e62` | — |
| **AC9** ✅ **MET — SUPERSEDES the ❌ below, which is STALE (re-read 2026-07-31)**. The ❌ was assigned by the §7.0 sweep on 2026-07-30 and was true *then*; the §11 completion wave built M4 hours later (§11.12), and the sweep was never re-run. Disk, this tree: `grep -c 'watchdog-census' bin/cc-reaper` → **6** (the sweep recorded 0); `ls tests/watchdog-census.bats` → **PRESENT** (the sweep recorded "No such file"); the ledger reads at `bin/cc-reaper:1146` (`n_spawn=$(grep -cF 'spawned watchdog daemon' …)`). Suite green this session: **12/12 ok, 0 not-ok**, reconciled against its `1..12` header. ~~❌ NOT MET — M4 shipped nothing~~ | Watchdog census balances, with a positive control (R6) | `cc-reaper --watchdog-census` → `spawned/live/exited/lost` + a `control=OK` line proving the detector fires. **Evidence 2026-07-30:** `grep -c watchdog-census bin/cc-reaper` → **0**; `ls tests/watchdog-census.bats` → *No such file or directory*; `grep -rn 'watchdog[-_]census\|WATCHDOG_CENSUS' bin/ scripts/ hooks/ tests/` → **0 hits** (`bin/cc-reaper` itself exists, 65193 B, and contains no `census` / `--watchdog` token at all). **Missing:** the whole M4 leg — the `--watchdog-census` subcommand, the spawned/live/exited/lost ledger, the `control=OK` positive control, and the `CC_WATCHDOG_CENSUS=off` kill switch §8 already declares | ledger off by **~102**, no census exists |
| **AC10** ✅ **MET — SUPERSEDES the ⚠ below, which is STALE (re-read 2026-07-31)**. Note [b]'s complaint was exact and is now answered: the daemon's poll of the **LEAD** — not just its own identity record — pins pid+lstart. `hooks/lead-crash-watchdog.sh:849-855` `lead_alive()` does `kill -0` **then** compares `ps -o lstart= -p "$p"` against the pinned value, with the DST-safe three-state degradation (§11.11); `:813` records the change in its own words — *"The check here used to be a bare `kill -0 \"$pid\"`"*; `:743` states the invariant. `grep -c lstart` → **11** (was 4, all of which note [b] correctly discounted as the daemon's own record). ~~⚠ PARTIAL — the read passes on code this row did not write; the poll it names is unchanged (note [b])~~ | Watchdog liveness uses pid+lstart (R5) | `grep -c 'lstart' hooks/lead-crash-watchdog.sh` → `>0`; RED-proof asserts a recycled-PID fixture is classified dead. **Evidence 2026-07-30:** count = **4** — so the read as written passes — but all four sit in the daemon's **own** identity check (`daemon_alive()` at `:718`, `WATCHDOG_START` at `:1008`), and `git blame -L 705,725` attributes 100% of them to sibling commit `2f62ee62` *"single-instance guard + one-handler-per-death"* (2026-07-29 17:48), not to this row. **The liveness this AC names — the daemon's poll of the LEAD — is still a bare `kill -0 "$pid"` at `hooks/lead-crash-watchdog.sh:761`** (base `6ce912b3` line 630; the `:601` cited in R5/M4). The recycled-PID RED-proof at `tests/lead-crash-watchdog.bats:301-311` exists but `git blame -L 301,311` → **11/11 lines `2f62ee626`**, and it asserts the *daemon-record* path (a recycled pid must not suppress the spawn), never the lead-liveness classification. **Missing:** pid+lstart on the lead poll, and a RED-proof that a recycled **lead** pid is classified dead | bare `kill -0`, line 601 |
| **AC11** ✅ **MET via its successor AC22 — SUPERSEDES the ❌ below, which is STALE (re-read 2026-07-31)**. M5 shipped in the §11 wave: `hooks/lib/osa.sh` exists on trunk and the bare sites were converted. Note [c] was right that the criterion's *own* grep is miscalibrated, so AC22 (§11.4) carries the corrected predicate and `tests/osa-bounds.bats` makes it a **standing** test rather than a one-time read — **14/14 ok, 0 not-ok**, reconciled against `1..14`. ⚠ That predicate was miscalibrated a **second** time and was RED on trunk when this session opened — it convicted `sup_bounded 10 osascript` (`scripts/lead-supervisor.sh:159`), a genuinely bounded call, because the exemption required the wrapper to sit *immediately* before `osascript`. Fixed + two mutant-RED-proved controls (`47c68a1c`). ~~❌ NOT MET — M5 shipped nothing; the read never reached `0` (note [c])~~ | 0 unbounded `osascript` sites in `hooks/` (R7) | `grep -rn '^[^#]*osascript' hooks/ \| grep -vE 'timeout\|_osa\|TB' \| wc -l` → `0`. **Evidence 2026-07-30:** the read returns **2**, not 0 — and returns the **same 2** against the pristine base tree (`git archive 6ce912b3 hooks/` → identical count), i.e. this row moved it by zero. Both residual hits are non-invocations (note [c]), so no *unbounded* osascript CALL survives in `hooks/` — but that was already true at base, from the pre-existing per-caller helpers `nty_osa` / `lcw_osa` / `wrc_osa` landed by `7774734a` (2026-07-26), which predates this row. **Missing:** M5 itself — the one sourced helper and the conversion of the bare sites. Repo-wide the same read returns **33** (`hooks/ bin/ scripts/`), including genuinely unbounded calls at `scripts/handoff-fire.sh:2218,2224,3341,3348` (`osascript -e 'delay …'`), `bin/screenshot-to-clipboard.sh:18`, `bin/dia-cdp-launch.sh:322` | **31** repo-wide |
| **AC12** ✅ **MET** | Session ceiling stated + alarmed (M6) | `scripts/capacity-alarm.sh` -> 4-rung verdict; swap-used>0 => ALARM; `--selftest` proves every rung reachable. **Evidence 2026-07-30:** `launchctl list \| grep capacity-alarm` → `-	0	com.claude.capacity-alarm` (loaded; last exit 0), plist present at `~/Library/LaunchAgents/com.claude.capacity-alarm.plist`. Live run → `live sessions 20 · reclaimable headroom 28.77 GB · swap used 0.00 MB · est. room ~46 more · **VERDICT: OK**` (rc=0). `--selftest` → `OK / WARN / ALARM / ALARM-on-swap>0 / NO-DATA` each reached with `control OK`, closing `capacity-alarm: selftest GREEN (4 rungs + no-data reachable)` | unstated -> OK@29.3 GB headroom |
| **AC13** ✅ **MET** | Row 13 exists in the map with plan link + landed shas | `grep -c 'MACHINE_CAPACITY_V2' docs/plans/GROUND_UP_REBUILD_MAP.md` → `>0`. **Evidence 2026-07-30:** count = **1**, at `docs/plans/GROUND_UP_REBUILD_MAP.md:30`, and the row carries both halves the criterion asks for — the plan link `[MACHINE_CAPACITY_V2.md](MACHINE_CAPACITY_V2.md)` and landed shas `b9fc76b0` (design) · `5370b2ff` (activation) · `fa8f15a8` (fan-out) · `8160416b` (close-out) · `bfe4da1e` (§9.7 census fix) | absent |

### 7.0 Status sweep — every AC marked from disk (2026-07-30)

Before this sweep only 4 of the 14 rows carried a status marker (AC1 + the three M3 rows; AC12 had a
bare unstyled `MET`), so "MET" and "never checked" were indistinguishable. Every row above now
carries **exactly one** marker (`✅ MET` · `❌ NOT MET` · `⚠ PARTIAL` · `➖ N/A`), and every marker
newly assigned rests on a command run against this tree on 2026-07-30 — never on prose. **10 rows
were swept here** (AC1-b · AC2 · AC3 · AC4 · AC5 · AC9 · AC10 · AC11 · AC12 · AC13) → **7 MET ·
2 NOT MET · 1 PARTIAL**; AC1 and AC6/AC7/AC8 were left exactly as previously proven (§9.7, §9.2).
Whole-table tally: **11 MET · 2 NOT MET · 1 PARTIAL.** The two NOT-MET and the one PARTIAL are all
the same fact stated three ways: **`cap-leak` (M4) and M5 shipped nothing**, so the leaks leg and
the AppleEvent leg of the frozen DoD are open.

> #### ⚠ THE TALLY ABOVE IS STALE — corrected 2026-07-31, and the correction is the whole point of dating a sweep
>
> **Whole-table tally is now 14 MET · 0 NOT MET · 0 PARTIAL.** The sweep above ran on 2026-07-30 and
> was accurate *at that hour*; the §11 completion wave built M4 and M5 later the **same day** (§11.12)
> and nobody re-ran it, so the plan spent a day asserting that its own DoD's leaks leg was open when
> the code was on trunk. Re-read from disk this session — AC9 (6 `watchdog-census` refs in
> `bin/cc-reaper`, `tests/watchdog-census.bats` present), AC10 (`lead_alive()` pins pid+lstart on the
> **lead** poll at `:849-855`, the exact gap note [b] named), AC11 (M5 landed; carried forward as AC22
> with a standing test). All three suites green this session.
>
> **The generalisable half, because this row keeps re-learning it against itself:** a status sweep is
> a MEASUREMENT, and it decays exactly like the instrument readings §9.7 and §9.5 had to retract. Two
> oracles inside one document disagreeing (§7.0 said M4/M5 shipped nothing; §11.12 said they shipped)
> means one is stale — **date them and let the shipping side win**. The markers above are struck
> through rather than deleted so the decay itself stays legible. This matches — and is the disk-truth form of —
`GROUND_UP_REBUILD_MAP.md` addendum (0b) ("M4 and M5 are now explicitly declared NOT BUILT",
backlog `cb5514b9d1b4` / `b72a2b8e7666`). No status here contradicts §9.x.

**[a] AC2 — the criterion's own read is the contaminated instrument §9.7 retracts, and it must not
be used again.** Run verbatim on 2026-07-30 it returns **24 rows at `pri=31`**, and *not one of them
is a bats process*: zsh shell-snapshot `-c` lines, `grep --line-buffered -E '^(ok |not ok |bats rc=)'`
output filters, `timeout 5400 bats …` wrappers, and `claude` sessions whose argv merely contains a
bats test path. The sharpest case is a row reading
`/opt/homebrew/bin/timeout -k 10 10800 nice -n 19 /usr/sbin/taskpolicy -c background bats tests/…` —
a **correctly demoted** run whose *wrapper* argv legitimately sits at `pri=31` while every bats child
beneath it is at `pri=4`. So the stated read manufactures the exact "uncovered" signal AC2 exists to
detect. The positional discriminator (libexec path in argv field 5/6, §9.7) returns **0** real bats
procs at `pri=31` out of 16 live. AC2's *substance* holds; its *instrument* is retired.

**[b] AC10 — a grep hit is not a build.** This is the row that would have read MET by accident. The
criterion has two halves and they part company: `grep -c lstart` passes, but only because sibling
commit `2f62ee62` added pid+lstart to the **daemon's own** identity record while fixing a different
bug (watchers accumulating per SessionStart). The R5 violation this AC was written against — the
daemon's 30-second `kill -0` poll of the **lead** pid — is byte-for-byte unchanged from base. A
recycled lead pid still reads as a live lead forever, which is the failure R5 names. Marked PARTIAL,
not MET, because half the criterion is satisfied by code this row neither wrote nor owns.

**[c] AC11 — the two residual hits are non-invocations, and the count is unchanged from base.**
`hooks/waiting-recycle.sh:423` is a `command -v osascript >/dev/null` availability probe (the actual
call on the next line goes through `wrc_osa`), and `hooks/handoff-intent-nudge.sh:26` is the word
"osascript" inside a JSON `additionalContext` prose string. All three real osascript calls in
`hooks/` (`notify.sh:100`, `lead-crash-watchdog.sh:840,888`, `waiting-recycle.sh:424`) are already
wrapped by per-caller helpers and are correctly excluded by the `_osa` filter. This is a
false-positive pattern of the same family as note [a] — substring presence in a line is not evidence
that the line IS the thing (§9.7's lesson, third occurrence).

**[d] AC6 / AC7 / AC8 spot-check (not re-timed; the M3 measurements in §9.2 stand).** Confirmed the
mechanism that produced them is still in the tree: the cheap pre-render change-stamp gate at
`hooks/operator-readout.sh:552` (`[ "${CC_READOUT_DAMP:-on}" != "off" ] && …`) with its kill switch
documented at `:531`, 17 `stamp` references in the file.

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

---

# §11. COMPLETION PROGRAM — systemic elimination at 15–30+ sessions (2026-07-29, operator directive)

**Operator directive (verbatim intent):** */ground-up ensure we eliminate the possibility of device
lag and memory leak/pressure at 15–30+ concurrent sessions — SYSTEMIC, inside claude-infrastructure,
not a one-time fix for the current laptop state (today's numbers are a data point).*

**Scope (frozen, refined):** claude-infrastructure itself carries enforced fail-loud mechanisms so
15–30+ concurrent sessions cannot lag the box or build memory pressure: **(1)** batch-class CPU
demoted to the background band at a chokepoint callers cannot bypass, **≥95% coverage
census-verified CONTINUOUSLY** (absolute-path invocations included); **(2)** render cost
(iTerm2+WindowServer) under a **measured budget with an alarm**, and every one-time machine knob
captured as **drift-detected parity-checked config** in the repo, never a manual tweak; **(3)**
memory governed by an **armed alarm term** (pressure > level-1, swap growth, per-proc RSS outlier)
wired to the operator surface + a bounded-by-construction story for session heaps. Standing
constraints unchanged: the caller cannot be trusted; pane render (not agent compute) is the dominant
lever; no quiet period exists.

**Relation to §1–§10:** this section COMPLETES the row — it closes AC1 (ceilinged at ~70% by
absolute-path invocations, §9.4), builds the never-built M4/M5 (AC9–AC11), and takes ownership of
the two levers §5 deliberately excluded now that the operator's directive puts them in scope:
the TUI render term (the measured dominant consumer, §8.5.7) and continuous verification wiring.

## 11.1 Phase 0 — Agent Team Orchestration (completion wave)

Disjoint file ownership; briefs ≤150 lines with pre-greped ranges; verbatim stop-on-issue clause;
no visual verification inline; RED-proof per artifact against a pristine `git archive` tree.

| Teammate | Owns (exclusive) | Deliverable | blockedBy |
|---|---|---|---|
| `cap2-qos` | `hooks/qos-rewrite.sh` (new), `tests/qos-rewrite.bats` (new) | M7: Bash-boundary batch-demotion rewrite (absolute-path closure) + empirical `updatedInput` probe | design ratified |
| `cap2-render` | `scripts/render-census.sh` (new), `config/iterm2-perf.keys` (new), `scripts/iterm2-perf-parity.sh` (new), `tests/render-census.bats` (new) | M8: render budget census + page, knob SSOT + drift parity | design ratified |
| `cap2-mem` | `scripts/capacity-alarm.sh`, `scripts/store-bounds-census.sh` (new), `config/store-bounds.manifest` (new), `tests/capacity-alarm.bats`, `tests/store-bounds.bats` (new) | M9: session-census fix (BOTH pid families; non-tautological population-control test) + per-proc outlier term + M9-ext pressure-level rungs + unbounded-store ratchet | design ratified |
| `cap2-wr` | `hooks/waiting-recycle.sh` (the two transcript-read sites ONLY), `tests/waiting-recycle-bounded-read.bats` (new) | M13 bounded transcript reads (same-output property + oversize degradation proven) | design ratified |
| `cap2-gate` | `scripts/handoff-fire.sh` (capacity_gate only), fire-suite `setup()` load-immunity, `tests/` fire suites touched minimally | M10 headroom term + M11 load-immune corpus (R-1) | design ratified |
| `cap2-m4m5` | `hooks/lead-crash-watchdog.sh` (exit-path fix), `bin/cc-reaper` (census leg), `hooks/lib/osa.sh` (new), the ~3 remaining bare `osascript` sites (§11.2), `tests/watchdog-census.bats` (new), `tests/osa-bounds.bats` (new) | M4 UPGRADED — the orphan leak is LIVE (≥11 watchdogs ppid=1 oldest 1d14h owning 43/80 sleeps + tree greps): find why the daemon's own session-death exit wedges, fix it, census leg with positive control (AC21), one-shot reap disposition honoring cleanup-disposition rules; + M5 remainder (AC22 with the `*_bounded`-aware grep as a standing test; the OLD grep is miscalibrated — fix the predicate first) | design ratified |

Lead keeps: settings.json hook registration (shared live file, single owner), launchd plists +
`fleet.manifest` rows, activation staging (both live queue + repo SSOT), map row update, all lands
via project-local `/ship` (standing-land), serialized smallest-diff first.

## 11.2 New measured constants (completion baseline, 2026-07-29 late)

| Constant | Value | How measured |
|---|---|---|
| Live snapshot at goal intake | loadavg **49.4/44.0/41.5** on 10 cores; ~30 session-class procs; pressure level **1**; swap **0** | `uptime`, `sysctl`, `ps` first-token census |
| iTerm2 / WindowServer | **159.9% CPU, 2.31 GB RSS** / **56.8% CPU** | `ps -axo pcpu,rss` (burst read; ⏳ top -l 2 second-sample from live axis) |
| `updatedInput` support | stable 2.1.114 claude.exe: **×88** · eval 2.1.219: **×79** (both bun-compiled Mach-O; V8/NODE_OPTIONS heap flags moot) | `grep -ac` on both binaries |
| PreToolUse Bash chain today | **5 hooks** (curl-gate, validate-bash, git-worktree-guard, keychain-guard, rm-safe-allowlist) | `jq .hooks.PreToolUse` on live settings |
| capacity-alarm wiring | **LIVE**: `com.claude.capacity-alarm` loaded, rows every ~10 min, OK @ 26–29 GB headroom | `launchctl list`, jsonl tail |
| capacity-alarm session census defect | reports **sessions=12** while ~30 session-class procs live — pattern matches only `claude-code/bin/claude.exe`, misses `.bin/claude` heavies (417–985 MB each) | jsonl vs `ps` cross-read |
| qos-census | latest burst: **69.4% proc / 66.2% CPU** at 5 runs in flight — at the predicted ~70% absolute-path ceiling; census has NO cadence (rows are manual) | `~/.claude/logs/qos-census.jsonl`; `launchctl list` (no qos job) |
| Unbounded-store landscape | `bash-execution.log` 35 MB · `bash-commands.log` 34 MB · `idl.jsonl` 21 MB (+6.4 MB chain) · `teammate-checkpoint.log` 16 MB · `session-index.db` 49 MB (+49 MB stale .bak) · 62 jsonl/log files in logs+autonomy | `find -size +5M`, `du` |
| Spotlight consumers in repo | **0** (`mdfind|mdutil|mdls` unreferenced) — exclusion safe from tooling side | `grep -rn` hooks/ bin/ scripts/ skills/ commands/ |
| **`updatedInput` PROBE — CONFIRMED, both modes** | On 2.1.219 live: a PreToolUse hook emitting `updatedInput` REWRITES the executed Bash command **with** `permissionDecision:"allow"` AND **without any decision** (permission flow untouched); the transcript keeps the agent's ORIGINAL command in the tool_use block while the rewritten one executes | headless probes, transcripts `~/.claude-next/projects/...289d0a28*.jsonl` + `...26f0d19a*.jsonl`: `EXEC: echo MAGIC_TOKEN_A` → result `REWRITTEN_BY_HOOK_{with,no}-decision` |
| Pages → operator consumer | ONLY `scripts/desk-invariant.sh` + `desk-recycle-invariant.sh` consume `autonomy/pages` (operator-readout and cc-blockers do NOT) — the standing pattern capacity-alarm already uses; surface completeness is row 10's | `grep -rln pages` over the surface files |
| M5 population TODAY (not baseline) | TRUE unbounded osascript sites ≈ **3** (`bin/screenshot-to-clipboard.sh:18`, `bin/dia-cdp-launch.sh:322`, `hooks/waiting-recycle.sh:423`) — the baseline "31" predates intermediate lands, and `hf_bounded`/`lrp_bounded`/`e2e_bounded` per-script wrappers already bound the rest (the AC11 grep must exclude `*_bounded`) | refined `grep -rn` over hooks/ bin/ scripts/ |
| M4 status TODAY | watchdog identity is ALREADY `{pid, lstart}` at the daemon layer (`lead-crash-watchdog.sh:707-718`) ⇒ AC10 likely met on trunk; `bin/cc-reaper` has **0** watchdog references ⇒ AC9 census leg confirmed absent | grep |
| Fire suites | `tests/handoff-fire-capacity-gate.bats` exists (dedicated gate suite); the red-by-load suites' `setup()` blocks pin NO gate env today | grep -ln / awk over setup() |
| **gu13-live LANDED** — sustained-CPU classes (top -l 2 deltas, 250-pid population) | render **1.76–1.91 cores** (0% demoted) · claude panes **1.25–1.28** (22 procs) · teammates **0.57–0.68** (16) · os-daemon 0.77–0.82 · indexing **0.03↔0.80 SWING** · batch 0.11↔0.86 SWING · browser 0.39 · kernel_task 0.55. Stable floor render+claude ≈ **3.7 cores never moves**; the batch/indexing swings are why loadavg oscillates 25→61 at near-constant session count | agent samples A/B |
| Whole-box QoS truth | **3.1% of CPU demoted** (21.7/700.3 at PRI≤4); repo census on gate scope: 49/76 = 64.5% proc / 45.8% CPU, FAIL. **bats is WELL COVERED** (shim proven live: PRI 31→4 transition at the shim boundary; the agent's own "0 of 7 shimmed" claim was INVERTED by its adversarial pass — argv0 shows plain `bats` because the shim execs) ⇒ **the real hole is every batch tool that is NOT bats**: `uv run pytest -m load` **0.67 cores** PRI 31 · recurring `du -sh` at **PRI 46 (boosted above default!)**, state stuck · `npm install` 15.6% · `shellcheck` (458 MB) | agent §(b) |
| Spawn churn — the lever the brief missed | **7.8 procs/sec** (118 new pids/15.1 s); sys-time escalated 36.2%→42.7% while user FELL; threads 6986→7254 in 20 s; each spawn pays syspolicyd+trustd+tccd+opendirectoryd tax (~0.77 cores os-daemon class). Named owner: **≥11 ORPHANED `lead-crash-watchdog.sh` (ppid=1, oldest 1d14h)** owning 43/80 live `sleep`s + tree-wide greps; also 28 `caffeinate` (1:1 per session) | agent §(c)3 |
| Render is single-thread-bound | iTerm2 **one thread at 98.7%** (of 13), **8,268 csw/sec**, 368M cumulative csw; 5 windows/34 panes ⇒ 0.052–0.056 cores/pane as a ratio — but the cost funnels through ONE thread, so **PTY OUTPUT VOLUME, not pane count, is the binding term**; WindowServer 1794 MB backing 34 panes' stores | agent §(c)1 |
| Spotlight — NOT exonerated; worst-case shape | `mds` **48.6%**, class total **0.80 cores**, **21 mdworker spawns/60 s** — while `mdfind -count` over `~/.claude*/projects` returns **0**: the 7,359-file / 4.26 GB transcript corpus (66 modified/hour) is churned but NEVER INDEXED. **Full cost, zero benefit.** None of the 6 config dirs has `.metadata_never_index` | agent §(e) |
| Memory (live re-derive) | pressure level 1 · swap 0 (swapouts 0) · compressor 12.37→5.26 GB @2.35:1 · claude sum **22.07 GB/39 procs** (p50 555 MB, p95 986, max 1037 — no proc >1.5 GB except the 2 render procs) · **fleet GREW 33→39 in the 20-min window** ⇒ the TREND is the risk, alarm-on-cadence is the right shape | agent §(d) |
| Structural classifier facts | argv0 `claude.exe` ≡ exactly the `--agent-id` (teammate) set; **no claude process has a claude parent** (bg subagents are in-process); PRI≤4 runs on the 2 E-cores only — 6.8 undemoted cores contend on 8 P-cores | agent §(d′)/(f) |
| Anomalies (named, not all mine) | 6 concurrent DUPLICATE `cc-dispatch-v2.bats` + 6 `cc-backlog-compact-race.bats` (identical suites, wasted load → row 1/5 backlog) · `bfs -S dfs` unattributable, process gone (open) · `npm install @anthropic-ai/claude-code@2.1.220` mid-measurement | agent anomalies |
| ⏳ iTerm2/WindowServer knob inventory + magnitudes, taskpolicy band semantics, CC background-work knobs, Spotlight-exclusion mechanics on this macOS | AWAITING gu13-levers + gu13-ccguide | external docs + local defaults |
| **gu13-archaeology LANDED** — headline corrections A–G | (a) BOTH activations `.done`, alarm loaded+enabled 20 runs — but **`launchd/fleet.manifest:120` still says `staged`** with a now-false justification ⇒ `cc-fleet` asserts a false state; (b) alarm census **13 of 31** real session trees, two DISJOINT pid families (intersection 0), true claude RSS **19.06 GB not 7.40** — and `tests/capacity-alarm.bats:75` computes `expected` with the IDENTICAL grep (a tautology, not a population control); (c) **AC11's grep is MISCALIBRATED** — returns 33 repo-wide but counts `hf_bounded`/`lrp_bounded`/`e2e_bounded` wrapper calls + prose as violations (true unbounded ≈ 3); (d) `qos-census.sh:213` prints `threshold (CPU)` while gating PROC; (e) `SESSION_LIFECYCLE_V2.md:84-85` misquotes row 13 ~38× ("a pane ≈1.6 cores" — the 1.6 was the WHOLE fleet's draw); (f) hook chain now PreToolUse **12** + PostToolUse **9** (§1's 8-hook figure stale-low); (g) map's deployed-gate line numbers stale (live now byte-identical to trunk: `:1286/:1290/:2273`) | agent report §0, disk-verified |
| Gate refusing LIVE at LOW session count | `vm.loadavg` **52.02** on 10 cores = **5.20/core vs 2.0 ceiling at only 12–15 sessions** — every net-new fire refused while iTerm2 113.7% + WindowServer 86.0% ≈ **2.0 cores purely drawing**; iTerm2 WAS restarted (uptime 1d14h vs 13d22h on 07-26) and rebounded to 113%/2.28 GB ⇒ restart is not a fix | agent live reads |
| Biggest per-turn hook cost after M3 | **`hooks/waiting-recycle.sh` on EVERY PostToolUse**: 139 `$(` forks (grown from 131) + a FULL-transcript `jq` pass at `:617-620` and `:627-628` — O(transcript) per tool call, ~19× the Stop chain's firing rate | static fork proxy + file read |
| Memory truth re-derived — exoneration HOLDS, with two named gaps | RSS flat with age re-confirmed; swap 0 now BUT **2.56 GB of 4 GB swap WAS in use on 07-26** at 57 procs (the alarm's hard signal would have fired — the swap file was reset by reboot, not never-used); compressor **4.2–4.4 GB and RISING** is reported but NOT in the verdict; `kern.memorystatus_vm_pressure_level` absent entirely; **49 crashes: concurrency min 0/max 45/mean 13, mem_free mean 84.8%** ⇒ crashes correlate with CONCURRENCY, not memory (attribution blocked on the still-PENDING `10-close-attrib` activation) | agent §2/§9; `claude-crashes.jsonl` |
| Graveyard | **NOTHING to duplicate** — every row-13 artifact ON-TRUNK (positive-controlled); off-trunk refs are ship-land backup twins only | `git ls-tree origin/main` sweep |
| Remainders had NO consolidated section | scattered across §8.5.1/§9/§9.4/§4/§7/§8.5.5 — §11 is now that section; inherited list reproduced in agent report §4 | grep REMAINDER = 0 |

## 11.3 Failure-mode additions — every mode → structural answer (extends §4)

| # | Mode | Evidence | Structural answer (the inversion) | Kill switch |
|---|---|---|---|---|
| **M7** | The QoS hole is BOTH the absolute-path bats residual (§9.4, ~30%) AND — the larger live term — **every batch tool that is not bats**: `pytest -m load` 0.67 cores PRI 31, recurring `du` at PRI 46, `npm install`, `shellcheck` (§11.2 live axis) | census 69.4% ceiling; whole-box 3.1% demoted | **Move the chokepoint to the Bash TOOL boundary** — a PreToolUse hook rewrites AGENT-issued batch-class commands via `updatedInput` (no permissionDecision — probe-confirmed the rewrite applies while the permission flow stays untouched). Two rewrite forms: (a) any-spelling `bats` token → `cc-bats` (converges on the proven artifact); (b) other table patterns get the demotion prefix (`/usr/bin/nice -n 19 /usr/sbin/taskpolicy -c <band>`) prepended to the whole command when it is a SINGLE simple command, else left alone (fail-open — never wrap compounds by string surgery). Day-one pattern table (`config/qos-batch.patterns`, one regex + band per line): `bats` any path (background) · `pytest`/`uv run pytest` (background) · `shellcheck` (background) · `npm install|ci`/`npx .* install` (background) · recursive `du` (background). The operator's own terminal never passes through the hook — only agents demote, so interactive typing is untouched. The tool boundary cannot be spelled around. FAIL-OPEN on any parse/JSON error + per-hook `timeout: 10` (row 6's standing constraint). | `CC_QOS_REWRITE=off`; per-pattern removal via the config file |
| **M8** | TUI render is the DOMINANT stable consumer (1.76–1.91 cores, never moves) — and it is **single-thread-bound** (one iTerm2 thread at 98.7%, 8,268 csw/sec), so PTY OUTPUT VOLUME, not pane count, is the binding term | §11.2 live axis | **Render gets the same treatment memory got: a budget, a 4-state census, a page.** `render-census.sh` samples iTerm2+WindowServer CPU (top -l 2 second-sample), the hot-thread share, csw/sec, and pane/session counts; alarms on sustained budget breach (`CC_RENDER_BUDGET_CORES`, default from today's 2.0 baseline) with the shed platter (retire orphan watchdogs/panes, `/handoff` idle sessions). Knob SSOT `config/iterm2-perf.keys` + `iterm2-perf-parity.sh` drift check (⏳ knob list + magnitudes from gu13-levers; volume-side levers preferred over pane-side given the single-thread finding). | `CC_RENDER_CENSUS=off` |
| **M8b** | Spotlight: **full cost, zero benefit** — 0.49–0.80 cores + 21 mdworker spawns/min churning 7,359 transcripts that the index does NOT contain (mdfind count = 0) | §11.2 live axis (e) | **Exclude the churn dirs from indexing, with the exclusion itself drift-checked**: `.metadata_never_index` in the 6 claude config dirs + `~/Development/.worktrees` (if gu13-levers confirms the marker works on macOS 15.6; else the Settings-Privacy list as a staged C10 activation with the exact drag-in platter). Effect verified by MEASUREMENT, not marker presence alone: render-census carries the indexing-class CPU + mdworker spawn-rate so the before/after is a disk read. Zero risk to tooling: repo greps found 0 mdfind consumers, and the index already serves 0 transcript results. | remove the marker files |
| **M9** | Alarm's own census undercounts the fleet 12 vs ~30 (violates its in-file verify-against-known-population rule); no per-proc outlier term; append-only stores grow unbounded (8 known instances, §8.5.5) | jsonl vs ps; store table §11.2 | **(a)** census matches BOTH session forms, verified against a known population in tests; **(b)** top phys-footprint outlier term (report always, WARN above `CC_CAP_PROC_WARN_GB`) — the leak-alarm the directive asks for, keyed on the instrument `footprint(1)` §8.5.6 prescribed; **(c)** `store-bounds.manifest` declares every store's cap + owner + rotate remedy; a census walks the manifest and PAGES on breach — the leak CLASS gets one mechanism instead of 8 spot fixes. NEVER deletes (append-only-store safety: archive is the destination's property). | `CC_STORE_BOUNDS=off` |
| **M10** | capacity_gate keys on box-wide loadavg — not session-attributable, not sheddable (§9.5 instrument critique stands) | deployed `:1285-1316` | **Gate a session spawn on what a session actually consumes:** memory headroom term (refuse net-new when reclaimable headroom < `CC_FIRE_MIN_HEADROOM_GB`, sheddable by closing sessions — same instrument as capacity-alarm) alongside the existing loadavg ceiling (kept: §9.5 measured it behaving as a ceiling). Pane-budget term named as follow-on once render-census provides the count. | `CC_FIRE_HEADROOM_GATE=off` |
| **M11** | 16 corpus tests RED **by ambient load** on the pristine tree (capacity gate exit 9 inside fire-path tests) — a gate that fails itself, blocking deploy verification (map R-1) | map ~:236-243 | **A test's environment is pinned, not ambient:** fire suites' `setup()` pins `CC_FIRE_CAPACITY_GATE=off` (+ load-keyed gates off) EXCEPT the dedicated gate-behaviour tests, which set it ON explicitly with synthetic inputs. Extends memory `red-proof-environment-and-ref-fragility` (off load-keyed gates) to the standing corpus. | n/a (test-only) |
| **M12** | Coverage/census claims decay without cadence: qos-census has no runner; alarm verdicts have a consumer only via pages | `launchctl list`; §11.2 | **Continuous verification is wiring, not discipline:** `com.claude.qos-census` launchd job (10-min; NO-BURST rows are cheap and honest) + fleet.manifest rows + staged activation (C10, both queues); every census writes the standard page envelope on FAIL/ALARM so the operator surface renders it by construction. ALSO fixes `fleet.manifest:120` (`staged`→`run` — the row is factually false today and makes `cc-fleet` assert a false state). | per-tool switches above |
| **M13** | `waiting-recycle.sh` does a FULL-transcript `jq` pass on EVERY PostToolUse (O(transcript) per tool call, monotonically growing; 139 forks) — the biggest per-turn cost after M3 | §11.2 (archaeology §7) | **Bound the read, keep the semantics:** the two transcript call sites (`:617-620`, `:627-628`) only need the LAST assistant/interactive lines — read `tail -c` a fixed window (default 256 KB, seam `CC_WR_TAIL_BYTES`) instead of the whole file. Same output on every transcript whose relevant lines are within the window (they are the FINAL lines by construction); a transcript line larger than the window degrades to the incumbent full read. NOT the row-6 broker (that stays row 6's); this is M3's damp-the-cost pattern applied surgically to the top offender. | `CC_WR_TAIL_BYTES=0` (0 ⇒ incumbent full read) |
| **M9-ext** | Alarm verdict ignores the kernel's own leading indicator: `kern.memorystatus_vm_pressure_level` absent; compressor reported but verdict-inert; 07-26 proved the swap rung fires only AFTER the pain | §11.2 memory-truth row | **Let the kernel vote:** pressure level ≥2 floors the verdict at WARN, ≥4 at ALARM (max-combined with headroom/swap rungs); compressor stays reported-not-gated (no calibrated threshold exists — inventing one violates R9). Selftest gains the two new rungs. | existing `CC_CAPACITY_ALARM` |
| lead-fixes | Three one-line falsehoods found by archaeology | §11.2 A–G | `qos-census.sh:213` label `(CPU)`→gated metric name · `SESSION_LIFECYCLE_V2.md:84-85` misquote corrected with the fleet-level number + citation · map row-13 stale line numbers refreshed at close | n/a |

## 11.4 Acceptance criteria — completion (extends §7; disk-truth reads only)

| # | Criterion | Proving read |
|---|---|---|
| **AC14** | Absolute-path bats invocation is demoted end-to-end on BOTH tracks | empirical probe: headless session issues `/opt/homebrew/bin/bats --version` via Bash; child census shows `pri≤10`; probe artifact committed |
| **AC15** | AC1 becomes reachable: first post-M7 burst census ≥95% proc coverage | `qos-census.jsonl` row with `runs_in_flight≥2`, `coverage_proc_pct≥95` (ACCRUING until a burst) |
| **AC16** | Render census live on cadence with 4-state verdict + budget from config | `launchctl list com.claude.render-census`; jsonl rows; `--selftest` proves every rung |
| **AC17** | iTerm2 knob parity: every key in `config/iterm2-perf.keys` matches live defaults, drift pages | `iterm2-perf-parity.sh` exit 0 + a deliberate-drift RED control |
| **AC18** | Alarm session census matches a known population (±0) in test AND live forms both counted | bats fixture census + live cross-read vs `ps` first-token count |
| **AC19** | Per-proc outlier term reports top-3 footprints every row; WARN rung reachable (selftest) | alarm jsonl rows carry `top_procs`; selftest |
| **AC20** | Every §8.5.5 store is in `store-bounds.manifest` with cap+owner+remedy; census pages on breach; bash-execution.log's existing breach is its first live catch | manifest read; census run; page file exists naming the breach |
| **AC21** | M4: watchdog census balances with positive control (was AC9/AC10) | `cc-reaper --watchdog-census` → spawned/live/exited/lost + `control=OK`; `grep -c lstart hooks/lead-crash-watchdog.sh` >0 |
| **AC22** | M5: 0 unbounded osascript sites in hooks/ (was AC11) | §7 AC11's exact grep → 0 |
| **AC23** | Fire suites green under ambient load ≥2.0/core (M11) | full fire-suite run at recorded high load → 0 not-ok |
| **AC24** | Headroom gate: REFUSE and ADMIT both reachable with synthetic inputs; live default admits at today's headroom | gate selftest/bats with env-injected vm_stat; live fire log |
| **AC25** | The map row cell reflects this completion with landed shas resolved from origin/main | map read after land |

## 11.5 Seams (consumed, not redesigned)

Row 2 owns `handoff-fire.sh` control flow — M10 touches ONLY `capacity_gate()` + its telemetry line,
additively. Row 6 owns the hook chain — M7 is a NEW fail-open file registered at the end of the Bash
matcher; the future hook-broker absorbs it (its ~15 ms fork cost ≈ 0.007 cores fleet-wide at
30×59/hr, cited against §8.5.4 honestly). Row 10 owns the operator surface — all new alarms speak
the existing page envelope; zero new surfaces. Row 12 owns launchd activation — plists ship in
`launchd/` + `fleet.manifest` + staged activation scripts in BOTH queues, operator-run (C10).
Row 9 owns session-index retention; row 11 owns worktree sprawl — the store-bounds manifest BOUNDS
and REPORTS them with owner labels; it does not fix them here.

## 11.6 Rejected alternatives (completion; extends §6)

| Rejected | Why |
|---|---|
| Shim `/opt/homebrew/bin/bats` itself (§9.4 option 1) | Mutates a package-manager-owned path machine-wide; `brew upgrade bats-core` silently reverts it (needs its own parity check to stay true); M7 achieves the same closure at OUR chokepoint with a kill switch and no foreign mutation. |
| `NODE_OPTIONS=--max-old-space-size` per-session heap caps | The 2.1.x CLI is a bun-compiled Mach-O (JavaScriptCore) — V8 flags are inert (§11.2). Per-session RSS is exonerated flat-with-age anyway (§3.2); the outlier ALARM (M9b) is the honest bound. |
| DEFER/refuse batch admission in PreToolUse (§8.5.1 follow-on) | Rewrite-to-demote is strictly better: zero round-trips, zero policy decisions, R1-clean (never waits). **RESOLVED — the empirical probe CONFIRMED `updatedInput` rewrite on live 2.1.219 in both decision modes (§11.2)**; M7 ships rewrite-only, no-decision form (permission flow untouched). DEFER stays here as the recorded fallback design should a future binary regress the semantics (the probe is re-runnable). |
| Spotlight exclusion of `~/.claude*` | ⏳ HOLD until gu13-levers: mds CPU was exonerated (§8.5.6) and modern-macOS exclusion mechanics are contested; adopt only with a verifiable, drift-checkable method and measured benefit — else record here with numbers. |

## 11.7 Phase-1 completion wave — status + ratification

**LANDED + integrated above:** gu13-archaeology (harvested from transcript — notification never
arrived; wave-report-harvest applied) · gu13-live · gu13-ccguide. **PENDING:** gu13-levers (knob
inventory + magnitudes, taskpolicy band semantics incl. utility-vs-background and E-core
confinement, Spotlight marker mechanics on macOS 15.6, CC idle-work knobs).

**RATIFIED 2026-07-30 (lead):** the five levers-independent lanes — `cap2-qos` (M7), `cap2-mem`
(M9/M9-ext), `cap2-gate` (M10/M11), `cap2-m4m5` (M4/M5), `cap2-wr` (M13) — proceed now; every
design input they depend on is measured and cited above. `cap2-render` (M8/M8b) holds until
gu13-levers lands (its knob SSOT is the deliverable that needs the external evidence). M7's
per-pattern band choice ships `background` day-one (consistent with cc-bats); if gu13-levers shows
`utility` semantics warrant a split, that lands as a config-file change, not a code change.

**Also noted for the wave:** every ephemeral subagent session arms its own 4-h `cc-await-ping`
watcher (the nudge hook does not exempt subagents — observed on all Phase-1 agents + probes).
Fork-churn litter squarely in this row's domain; smallest fix is a subagent guard in the nudge
hook. BACKLOGGED for row 3/6 with this citation, not built here (their file).

## 11.9 gu13-levers findings (LANDED 2026-07-30) — two premises falsified, one design revision

Full report: measured on THIS box (loadavg 20–46), kernel constants cited from XNU source, iTerm2
3.6.11 knobs from its own `iTermAdvancedSettingsModel.m`, Spotlight via a controlled 4-probe
experiment. The three load-bearing outcomes:

**(1) BAND REVISION — `background` is a measured ~84–89× tax; the row's own M1 band was wrong for
long batch.** PRI map (measured): default 31 · `-c utility` **20** (P-core-eligible,
`THROTTLE_LEVEL_TIER1` I/O ≈ baseline) · `-c background`/`-c maintenance`/`-b` **4** (E-core-
CONFINED — 2 cores shared with 628 system procs at PRI≤4, I/O tier 2). Measured: fork/exec ×84,
CPU ×89 under load, 4-concurrent scaling 1.87× wall ⇒ ~2 usable cores ⇒ N corpora ≈ ⌈N/2⌉ ×
84×-single. `nice -n 19` is DECORATIVE (NI moves, PRI stays 31; indistinguishable from baseline;
irreversible for non-root) — drop it. Clamps are spawn-only and immutable both directions
(`taskpolicy -c … -p` is a SILENT NO-OP, rc=0); only `-b -p`-applied-post-spawn is reversible; every
failed lift returns rc=0 ⇒ never trust the exit code, re-read `ps -o pri=`. **Revision (M1-rev,
extends M7): long-batch band = `taskpolicy -c utility` alone** — yields to interactive PRI 31,
keeps throughput; `background` stays right ONLY for short idle-time bursts. The census's
demoted-band definition widens: pri ≤ 20 counts as covered (utility), reported per-tier. The frozen
DoD's "background band" wording is INSTRUMENT-CORRECTED to "demoted band (utility clamp)": the
DoD's intent — batch cannot compete with the interactive band — is exactly what utility preserves
while removing an 84× self-harm. Child inheritance verified to grandchild depth for both bands.

**(2) iTerm2 (Section A) — the saturated thread is LEGACY CPU GLYPH DRAWING, not parsing.** 5-s
`sample` of the live process: 56–70% of the main thread in `legacyView:drawRect:` →
`iTermTextDrawingHelper`; Metal active for only a minority of sessions (93 vs 2,182 samples).
Parsing (`com.iterm2.mutation`) is 4.7× cheaper than drawing. Second-busiest queue:
`fastForegroundJobUpdates` process-tree walking (803 samples, `__sysctl` ×387 over 1,556 procs).
**The default `disableAdaptiveFrameRateInInteractiveApps=YES` exempts alternate-screen (TUI) panes
from the adaptive throttle — exactly our 60 panes redraw at 60–120 FPS regardless of throughput.**
Top-5 knobs (commands + magnitudes + risk in the harvested report; render lane consumes them):
adaptive-in-TUI false (~0.5–0.9 cores) · UseMetal true (ceiling = the whole 1.39-core bottleneck;
MEDIUM risk at 60 CAMetalLayers — instrument first via showMetalFPSmeter) · frame ceilings 30/30/10
(~0.3–0.6) · fastForegroundJobUpdates false (~0.15–0.4) · dimming+graph-animation off (~0.1–0.3,
ergonomic cost; DimOnlyText middle ground). CC's own TUI uses DECSET 2026 synchronized updates ⇒
full VT100Grid copy per begin/end — inherent per-byte cost above plain streams. Non-visible tabs
parse but do NOT draw (cadence is visibility-gated) — today 60/60 panes are visible, so
tab-stacking is a free structural lever nobody uses.

**(3) Spotlight (Section E) — M8b's premise DOES NOT HOLD; downgraded to a drift probe.** All 15
`~/.claude*` dirs are ALREADY index-excluded by the dot-prefix rule — proven per-file (transcript
mdls: 15 filesystem-only attrs, 0 ContentType/Kind vs control 31/3). Controlled experiment on this
OS: `.metadata_never_index` is **DEAD** (probe dir indexed anyway); `.noindex` suffix and dot-prefix
both work (byte-identical signature). The Privacy list is write-only-by-UI and root-gated to read ⇒
NOT drift-checkable. The 0.49–0.80-core mds reading does NOT reproduce (sustained re-measure: peak
2.1% — the earlier read was a transient rebuild or misattribution; both reads were real,
the class is bursty). `mdutil -s <dir>` is USELESS for directories ("unknown indexing state").
**M8b final shape: NO exclusion action; render-census keeps the indexing-class CPU column; parity
gains the sudo-free per-file probe (mdls attr-count with a positive control on an indexed file —
never assert exclusion from a bare mdfind zero).** Spotlight exclusion cannot reduce FSEvents load
(volume-wide, no opt-out) — category error avoided.

**New anomaly for the ledger:** `NotificationCenter` at 22.8% of a core — 20× the entire mds
family, in nobody's brief. Backlogged with a `sample 660 5` as the named next probe.

## 11.10 Agent-lifecycle gap found DURING this wave (operator-prompted investigation, 2026-07-30)

**Finding: graceful teammate self-close does not operate on the implicit-team runtime, and
API-error "deaths" leave immortal idle processes.** Measured mid-wave: **16 idle `claude.exe`
agent processes ≈ 8.5 GB RSS** — all 7 server-529/500 "corpses" (turn died, process idles
resumable-by-design) + 5 finished researchers + superseded generations. Three compounding causes,
each verified: **(a)** no team manifest is created for an implicit team (`~/.claude/teams/
session-5f645730/` absent) ⇒ the auto-shutdown hook has no member→worktree/pane records;
**(b)** its worktree resolution falls back to the SPAWN cwd — the shared checkout — where the
2026-07-29 owned-tree gate CORRECTLY refuses destruction ("SHARED by 19 members"); right gate,
wrong input; **(c)** a turn killed by an API error never enters the TeammateIdle→shutdown path,
and no reaper leg classifies an agent-corpse session. A fourth amplifier already in §11.7: the
inbox-nudge hook makes every ephemeral subagent arm a 4-h watcher, keeping finished researchers
warm instead of exiting.

**In-wave remedy applied (lead protocol, not code):** the lifecycle's Cleanup step — structured
`shutdown_request` per agent — is the working teardown on this runtime and was MISSING from the
lead's flow; 12 sent on discovery, effect-verified by process census. **Standing lead protocol
from this wave on: shutdown_request every accepted/superseded agent at acceptance time, and
effect-verify with `ps` (a claimed shutdown is not a checked one).**

**Backlogged with owners (not built here — foreign files):** row 2/6 — teammate-auto-shutdown.sh
resolves the member's LIVE cwd (lsof per pid) before the shared-tree gate, and handles the
no-manifest implicit-team case; row 4 — cc-reaper gains an agent-corpse leg (agent-id sessions
whose turn ended in `idleReason:failed`, idle ≥ settle, parent session alive ⇒ platter or reap);
row 3/6 — the subagent watcher exemption (§11.7). Each keyed to this section's evidence.

**RESOLVED same night (amends the "in-wave remedy"):** cooperative explicit-approve close works when
the agent complies (8 clean terminations incl. pane close) — but a corpse resumed by the request
itself may execute its BRIEF instead (observed: read-only replays; one lane's gen-1 authored real
commits mid-"death"). **`TaskStop(name)` is the reliable forced actuator — 8/8 instant** (fleet
18→3 procs, 9.8→2.0 GB). Hierarchy: cooperative close for LIVE agents (checkpoint semantics);
TaskStop for corpses/superseded generations (nothing a checkpoint would save; messaging them is a
resume trigger). Also: name resolution for sends is latest-wins-ish and NONDETERMINISTIC when
suffixed siblings exist (`cap2-qos` routed to gen-1 in one send, to `cap2-qos2` minutes later,
delivering a shutdown-approve to the ACTIVE worker — countermanded) ⇒ never address lifecycle
commands by a base name that has suffixed siblings. Memory: `implicit-team-lifecycle-discipline`.

## 11.11 Completion-wave learnings (accumulate; never delete)

**Instrument + classifier traps, each caught pre-ship by its lane:**
- `taskpolicy -c <bogus>` exits 64 WITHOUT running the program — an unvalidated band column in a
  config table converts matching commands into no-op failures; the hook allowlists
  {utility, background, maintenance} (qos).
- A bare `DEMOTED_PRI_MAX=20` range mis-classifies busy UNDEMOTED work — Darwin timeshare decay
  floats PRI through 31→17 (60-sample floor 17), while clamps PIN (utility exactly 20, background
  exactly 4) ⇒ classify on the CLAMP CONSTANTS {4,20}, not a range; residual (float sampled at
  exactly 20) documented, ~4× smaller (qos).
- `ps -o lstart=` renders through the CURRENT TIMEZONE — a DST shift changes the pin string of a
  process that never restarted; a plain-string compare would have mass-fired handle_crash on every
  healthy team twice a year. Three-state `lead_alive`: DEAD only with positive corroboration (pid no
  longer a claude binary); else IDENTITY-LOST → re-pin, BOUNDED at 2, then exit claiming nothing
  (m4m5).
- `top -n 0` suppresses EVERY process row (an empty-fleet census that looks healthy);
  macOS `ps` has no `etimes`; `pgrep -n <name>` can return empty with the target plainly alive ⇒
  pid and CPU must come from ONE instrument (render).
- `ps -M` %CPU is a lifetime average — the census field carries `hot_thread_src` provenance rather
  than a number reading 4× better than the sample-based truth (render; R5's cousin: a record carries
  its own instrument).
- `jq -c` on a tail window ABORTS the whole stream at a partial first line (zero records — silent
  blanking on ORDINARY files); the `fromjson?` line-wise idiom + a no-record-in-window (never
  empty-result) fallback discriminator (wr).
- A line-scoped `grep -v` exemption launders a REAL call sharing the line with the exempted one; and
  `display notification` is an AppleEvent naming NO application, slipping `tell application` guards
  (m4m5).
- Backticks in a bats `@test` name fail the whole file at GATHER time; `bats … | tail` yields the
  PIPE's rc and a SIGTERM'd run can report exit 0 with no TAP ⇒ every count reconciles the `1..N`
  header, never a bare rc (render, gate2, qos2 — three independent hits in one night).

**Proof-method learnings:**
- An EQUIVALENCE contract cannot be RED-proved against the unbounded reference it equals — the
  second control is a NAIVE-BOUND MUTANT (the brief's literal sketch), with the mutation anchor
  asserted to match exactly once (wr).
- A gate that only reaches the artifact through an interpreter cannot certify the LAUNCH path —
  `/bin/bash "$X"` succeeds on a mode-644 file that launchd EACCESes; the direct-execution test
  caught a real shipped defect (mem).
- Control-must-replay-the-real-artifact, positive form: copy the REAL script, inject the forbidden
  text AFTER its final exit (text the guard must catch, code that can never run), require the
  artifact's OWN selftest to go red, keep an unmodified copy as the negative control (mem lane's
  (vi), superseding a re-typed-regex approximation).
- A handed-down green is ONE EDIT STALE the moment the file changes — re-derive counts from the
  artifact, and treat "committed" vs "RED-proved" as separable states (gate-never-ran is a third
  state; the mem lane's commits shipped before their proof bar and the proofs were run POST-HOC,
  valid as proofs, no longer as a gate).

**Load/lifecycle learnings:**
- The wave reproduced `gate-admit-ceiling-self-starvation` on itself: 121 concurrent bats procs;
  a trivial one-assertion test cost 12.4 s in the background band (the 84× tax measured by §11.9,
  observed independently by four lanes); killing a top-level `bats` ORPHANS its exec children which
  keep re-running the suite (five copies of one suite, 1h14m — self-inflicted loadavg) (mem gen-1).
- Three-sibling worktree convergence (gate, mem) resolves by DISK ADJUDICATION: authorship is
  formally ambiguous (all commits carry the operator's git identity; CPU% attribution is the
  argv-sampling trap) — content verification governs, and the sole-owner ruling + stand-downs must
  precede any shutdown_request (which is itself a resume trigger).
- A property guard names the SUBJECT it protects, not the verb it dislikes — a blanket `rm -f` ban
  convicted the census's own page self-clear; scoping to $ROOT-derived paths with a positive
  control kept conviction power (mem3).

## 11.12 CLOSE vs the frozen DoD (2026-07-30; shas re-resolve from trunk post-land — commit TITLES cited here)

**PROVEN (disk reads, this session):**
- **M7 + M1-rev (DoD clause 1, the chokepoint):** the Bash-boundary rewrite hook exists with 22/22
  green + 22/22 RED and a live-probe-verified envelope; the band is `-c utility` fleet-wide
  (cc-bats, hook prefix, patterns) per the measured 84–89× background tax; the census classifies on
  clamp constants {4,20} (12-sample float floor 17 documented) with per-tier fields. Suites:
  qos-rewrite 22 · qos-chokepoint 21 (8/21 RED-B vs the M7 tree, 13 named unchanged-property
  greens) · census selftest.
- **M9/M9-ext/M9c (DoD clause 3, memory):** alarm census reads BOTH families as trees (60 vs the
  incumbent's 35, live), kernel pressure-level rungs + per-proc outlier term armed, NO-DATA rows
  PARSE (A′ attribution proof: red-pre/green-post at the verbatim bad byte); store-bounds ratchet
  live-caught both real breaches on its first run (AC20 met by measurement). 30/30 + 23/23 green;
  RED 12/30 + 22/23 with every pristine-pass named.
- **M8/M8b (DoD clause 2, render):** render-census with budget verdicts + page (live read 1.76
  cores = dead-center of the measured band); iTerm2 knob SSOT + parity with the sudo-free Spotlight
  drift probe (live: 7 UNSET + 1 real DRIFT = the expected pre-activation state). 35/35 green run
  twice (once demoted under ~90-suite contention); RED 33/35 with both survivors named controls.
- **M10/M11 (gate):** headroom term (session-attributable, sheddable) + load-immune fire suites —
  62/62 green, RED 13/24 with the two by-design greens named; recycle exemption preserved.
- **M4/M5 (leaks/wedges):** watchdog immortality root-caused (bare kill-0 on a recycled pid + the
  untracked-daemon window) and fixed with pid+lstart + the three-state DST-safe lead_alive;
  process-table-first census with dual positive controls (live: 8 untracked orphans, kill platter
  printed, kills nothing); shared osa_bounded + last bare sites converted + the corrected AC22
  standing grep. 19/19 + 12/12 green; RED 19/19 + 6/12 (6 named tree-independent controls).
- **M12/M13:** qos-census cadence plist + fleet.manifest truth (capacity-alarm staged→run);
  waiting-recycle bounded reads (438→24 ms/call, 18×, dual-control RED incl. the naive-bound
  mutant).
- **Lifecycle (unplanned, operator-prompted):** §11.10-§11.11 — the implicit-team close gap found,
  worked around (8 cooperative + 8 forced terminations, fleet 18→3 agent procs / 9.8→2.0 GB),
  protocol + actuator hierarchy recorded in repo memory.

**IN FLIGHT (autonomous, owner named):** the land itself (this session, via the project /ship
fast lane, serialized); the banner campaign (separate subsystem, teammate banner-fix, its own
branch).

**ACCRUING (time-dependent proof + where it will be read):**
- **AC15 (≥95% coverage)** — needs the M7 hook ACTIVATED (operator: 22-qos-rewrite) + one real
  burst; read: `~/.claude/logs/qos-census.jsonl` first `runs_in_flight≥2` row post-activation.
- **AC16/AC17 cadence + parity flip** — after operator activations 23 (census cadence) and 24
  (knob writes); read: launchctl print + the parity page clearing.
- **Render-budget effect** — the §11.9 knob magnitudes (~1.0–2.2 cores predicted) are measured
  claims until 24 runs; read: render-census.jsonl before/after rows.
- **Orphan-watchdog decay** — the exit-path fix prevents NEW orphans immediately on land (symlinked
  files); the existing ~8-10 drain only via the operator's plattered kills; read:
  `bin/cc-reaper --watchdog-census`.

**CEILINGS STATED (never let an unfalsifiable clause hold the session):** AC15's residual after
activation = env-prefixed non-bats commands (documented skip) + PATH-less contexts — the census is
the honest meter, ~4× tighter than the old one. AC23 is PARTIAL: the gate term of ambient
dependence is gone; payload-lint's body-level `timeout 25` wall remains (named, owner row 2/1).
Session count ceiling (~50, memory-bound) unchanged and alarmed.

## 11.13 §9.7 integration — a sibling's mid-campaign correction lands on this program (2026-07-30)

§9.7 (landed by a parallel session while this wave built) retracts the "~70% ceiling / ~30%
absolute-path bypass" arithmetic this program's M7 was partly framed on: the census denominator was
argv-contaminated, and with a clean instrument AC1 was ALREADY MET (92/92 = 100%). Consequences,
stated plainly rather than papered over: **M7's bats-token rewrite half solved a phantom** — kept,
because it is harmless-redundant where PATH covers, converges every spelling on one artifact, and
covers PATH-less contexts; **M7's real value is the non-bats pattern table** (pytest 0.67 cores at
full priority, du at PRI 46, npm, shellcheck — process-level evidence from §11.2's live axis, not
argv-matched, so §9.7's contamination does not touch it) **plus M1-rev** (independent 84-89×
band measurement). The M1-rev census rewrite (clamp-constant classifier + per-tier fields) is the
same instrument §9.7's fix hardened, merged compatibly at land. Backlog reconciliation: the
sibling's cb5514b9d1b4 (M4) and b72a2b8e7666 (M5) were closed with landed evidence — the wave built
exactly what they filed; 0086d70f85c7 closed as implemented-in-the-surviving-form (rewrite, not
DEFER); 2193948bb00e (O(N²) hook broker, row 6) stays open, its worst single term removed by M13.

## 11.14 The wave's own suites were RED on trunk — "merged compatibly at land" was not checked (2026-07-31)

§11.13 closes with the claim that M1-rev's census rewrite and §9.7's denominator fix were *"merged
compatibly at land."* **They were not.** Two of this row's own suites were RED on trunk when this
session opened — four failing tests across `qos-chokepoint` (39 cases) and `osa-bounds` (12) — and
the only backlog item that knew about any of it (`01ab67ffa27d`) had one of the four and
mis-diagnosed it. The row was carrying a DONE map cell over a red gate for a day.

**All four are one class: an artifact changed, and a guard or fixture calibrated to its predecessor
was left behind.** The merges were textually clean every time; nothing a diff review would catch.

| Failing | Root cause | Fix |
|---|---|---|
| (xix), (xx) | `bfe4da1e` (01:06) narrowed the census POPULATION to a positional discriminator (argv field 5/6 must be the bats libexec shape). `2514226e` (01:51, parallel session) added the M1-rev clamp tests, whose `_marker_script` builds its subject at a plain `$TMP/<name>` path — invisible to that discriminator. Measured on one live proc: `procs_total` **0** shipped-strict vs **1** under `QOS_CENSUS_STRICT=off`. The tests could only ever have passed against a NON-SHIPPED configuration. | `_marker_script` writes to `<name>/libexec/bats-core/bats-exec-test`, the shape `_qos_probe_bin` already used — `ef2f2f8d` |
| (xxxiii) | Its one-way-ratchet guard skipped on `own <= 10`. M1-rev then moved the fleet band background(4)→utility(20), so the shim demotes this very suite to pri=20, `20 <= 10` is false, the test did not skip, its children inherited pri=20, the census **correctly** counted them demoted, coverage never dropped. (v)'s sibling guard over the *same* constraint HAD been updated to `<= 20`. | band-relative construction so it RUNS instead of skipping — `ef2f2f8d` |
| AC22 (osa-bounds) | The exemption required a wrapper *immediately* before `osascript` — true of `hf_bounded`/`osa_bounded`/`lcw_osa`, false of `sup_bounded 10 osascript` (`lead-supervisor.sh:159`, landed the same day by `e6d789a8`), which passes its bound as an argument. A genuinely bounded call convicted. | tolerate an optional NUMERIC argument only — `47c68a1c` |

**Found while fixing, and worse than its backlog entry said.** `32be90485a45` filed the unquoted
`$PATH` walk against `scripts/qos-census.sh` as *"harmless in every constructed case"*. Both halves
were wrong: the site is `bin/cc-bats:195`, and it is **arbitrary binary selection** — `for d in $PATH`
pathname-expands, so an entry holding a glob metacharacter is replaced by whatever it MATCHES.
Two-sided against the pristine artifact from `git show HEAD:bin/cc-bats`: pre-fix executed a planted
fake, post-fix printed `Bats 1.13.0`. This is the identity walk whose last inversion produced the
§9.6 fork-storm, and cc-bats is on PATH as `bats` for every session on the box. Fixed + RED-proved
regression test — `50bac438`.

### Learnings (accumulate; never delete)

- **A guard is calibrated to a constant, so changing the constant silently retires the guard.** M1-rev
  updated the band everywhere it was *read* and missed one place it was *assumed*. Generalisation of
  memory `config-change-invalidates-its-own-guard-proofs`, now with a cheap detector: **two sibling
  guards over one constraint disagreeing is the tell** — `<= 20` at `:113` and `<= 10` at `:880`, same
  file, same ratchet, one stale. Grep for the constant, not for the guard.
- **Repairing a stale precondition can quietly convert a RED test into a permanently-SKIPPED one**,
  which scores as green and proves nothing. (xxxiii)'s guard, fixed naively, would have skipped on
  every ordinary PATH-invoked run because the shim always demotes. When a precondition becomes
  unsatisfiable, re-express the property **relative to the configuration** rather than accepting the
  skip — the same trade the file already makes in (xix).
- **A control cannot be recovered by `git archive` when the subject lives inside the test file.** The
  first RED-proof of the AC22 fix copied the new tests into a pristine tree and came back ALL-GREEN —
  because the predicate travels with the tests. The valid form is a NAIVE MUTANT of the predicate with
  the mutation anchor asserted to match **exactly once**. Sibling of §11.11's equivalence-contract
  learning; the failure mode is that a vacuous control looks exactly like a passing one.
- **`rc` is not a verdict, twice over.** An invalid `BATS_TMPDIR` produced `rc=1` with **zero** TAP
  bytes this session — indistinguishable from "tests failed" to anything reading the exit code. Every
  count here reconciles against the `1..N` header. (Also: the first attempt at the cc-bats control ran
  from `/tmp`, died `rc=127` on an unresolved `$CENSUS`, and *looked* like a successful RED.)
- **A backlog item's file attribution decays like everything else** — verify the symptom against the
  tree before fixing where it points. `32be90485a45` named the wrong file AND understated the
  severity; taking it at its word would have produced a no-op edit to `qos-census.sh` and left real
  arbitrary-binary-selection in the shim.

---

## §12 — 2026-07-31 post-panic pass: the chokepoint gap is real, but universalising the EXISTING gate would deadlock the fleet

Added after the 2026-07-31 11:46:47 spinlock panic (`a123c35d`). Read §8.5.2's retraction and
§8.5.7 FIRST — this section depends on both and does not repeat them.

### 12.1 Confirmed: the hardware term guards 2 of 7+ spawn paths (extends §8.5.2)

`capacity_gate()` is still the only hardware term in the tree. Measured coverage of session-spawn
paths this session:

| path | routes through `handoff-fire.sh`? |
|---|---|
| `lr-reset-poller.sh`, `lr-handoff.sh` | GATED |
| `scripts/boot-resume.sh`, `boot-resume-launch.sh` | **BYPASS** |
| `limit-recover/lr-fire-resume.sh`, `lr-transplant.sh` | **BYPASS** |
| `~/.reso/bin/reso-resume-one` | **BYPASS** |
| **`Agent` tool** (subagents / teammates) | **BYPASS** |

The `Agent` path matters most — it is the highest-volume spawn surface. Its two PreToolUse hooks
bind policy (`agent-teams-enforce.sh`) and **frontier budget** (`frontier-spawn-gate.sh`,
`max_fable_spawns_per_session`), never hardware. So the spawn-cap PATTERN is proven here; it is
keyed on the wrong resource. This extends §8.5.7's closing note ("the organic paths … were never
given a fleet term") with the resume/Agent paths enumerated.

The gate's own header asserts *"EVERY fire mode funnels through this script … this is the ONE place
where a HARDWARE term can bind"*. **That sentence is false in the tree** and should be corrected to
name the paths it actually covers — an in-source claim of chokepoint status that is untrue is worse
than no claim, because it stops the next reader from checking.

### 12.2 ⛔ DO NOT "just bind `capacity_gate()` everywhere" — §8.5.2 already discarded that architecture

This was the obvious fix and it is wrong. §8.5.2's retraction says to discard *"1-min `loadavg/ncpu`
as the saturation proxy with a fixed 2.0 ceiling and no sustained-saturation escape"* and to key a
redesign on a **sheddable, session-attributable** quantity.

**Live proof, 2026-07-31 12:13:** load **21.55** on 10 cores = **2.16/core**, i.e. already over the
2.0 ceiling, with 13 sessions and 24 GB RAM free and `0 B` compressor — a perfectly healthy box.
Binding the existing gate to all seven paths would have refused **every** spawn at that moment,
including every recovery path, and §8.5.7 shows why it would not recover on its own: iTerm2 +
WindowServer + XProtect are ~2.4 unsheddable cores, so refusing spawns cannot lower the number the
gate reads. That is `fail-closed-degradation-as-amplifier` and memory
`universalizing-a-mechanism-promotes-its-latent-leak` — arming a narrow mechanism fleet-wide
promotes its latent defect to the default path.

**What to build instead** (unchanged from §8.5.2, restated as an instruction): the term must be
sheddable and session-attributable — per-session memory footprint and/or a session count with a
sustained-saturation escape — read from harness config that **cannot lag** the landed tree, and
inertness must be LOUD (`capacity_gate: ABSENT`) rather than a silent admit.

### 12.3 The 2026-07-31 panic is a DIFFERENT cause class; no spawn gate can see it

`threadprice` (§ commit `a123c35d`) never spawned a session — it was one Bash call inside a live
session that walked `pthread_create` 2000 → 8000 → 16000 against `kern.num_taskthreads`=16384.
Verified arithmetic: 8444 pages × 16384 B = **131.9 MB** RSS against a 4096 MB headroom floor, and
threads parked on a condvar are **not runnable** so they add ~0 to loadavg. **Both gate terms are
structurally blind; the gate would have ADMITTED.**

| class | example | control point | resource term |
|---|---|---|---|
| A — aggregate fleet sprawl | 2026-07-29 lag; ~30-pane freeze | spawn admission | sheddable/attributable (per §12.2) — NOT raw loadavg |
| B — single runaway action in one session | 2026-07-31 `threadprice` | **Bash tool boundary** | thread count, proc count, alloc size |

Class B's chokepoint already exists: **M7 moved QoS enforcement to the Bash PreToolUse boundary**
(`config/qos-batch.patterns`, 22/22 green). A resource-ladder term belongs there, as a *resource*
guard — never a denylist of binary names (`denylist-enumerates-spellings-not-the-class`).

### 12.4 `boot-resume.sh` is a LATENT bomb — do not activate before §12.2 lands

It resumes at GUI login, i.e. into the boot storm — **measured loadavg 346 at boot+2 min today**,
decaying to 89 within 90 s — and it has no capacity term. It is currently INERT
(`~/Library/LaunchAgents/com.claude.boot-resume.plist` exists; `launchctl list` shows nothing; its
own header says "RunAtLoad, shipped UNLOADED"). That inertness is why nothing auto-resumed after
the panic. It IS bounded to 4 by `CC_BOOT_RESUME_MAX_TOTAL`, so this is bad-not-runaway.

**Operator consequence: activating boot-resume as-is converts "the box crashed" into "the box
crashes, reboots, and fires 4 Opus-max sessions into a load-346 storm, ungated."**

### 12.5 §8.5.4's fork storm is the dominant term we actually own — and it has GROWN

Re-measured 2026-07-31 against the plan's own figures:

| hook | `$(` fork sites | plan's figure |
|---|---|---|
| `waiting-recycle.sh` | **144** | 131 |
| `operator-readout.sh` | **75** | (75 pipeline stages noted) |
| `teammate-checkpoint.sh` | 22 | 17 |
| `validate-bash.sh` | 18 | 13 |

Hook counts per event from live `settings.json`: **Stop = 11 hooks**, PreToolUse = 13 (6 on Bash),
SessionStart = 14, PostToolUse = 10, UserPromptSubmit = 6.

So a single session's Stop can cost ~200+ forks, at 15 ms/fork under load, ×N sessions — and
§8.5.4's O(N²) argument (forks/s is O(N); cost-per-fork is O(load); load is O(forks/s)) means this
is the term that makes every other term worse. Unlike iTerm2/WindowServer/XProtect it is **entirely
ours**. Ranked by measured impact this is the highest-value remaining capacity fix, and §8.5.4
already names the structural answer (a long-lived per-session hook broker; bounded fallback =
collapse the 5 PreToolUse/Bash hooks into one and the 11 Stop hooks into one).

### 12.6 Method notes from this pass
- The shared checkout was **39 behind** origin/main; cutting a branch there would have been stale.
- `scripts/handoff-fire.sh` was contested three ways (dirty in the shared checkout from a
  panic-killed session, dirty in `wt-c89b9c7b1526` from a live session, plus this pass) ⇒ the
  extraction must be a NEW file + a parity test, never an edit to the contested file.
- `pgrep -c` does not exist on macOS; `cmd 2>/dev/null || echo 0` turns its usage error into a
  fabricated all-clear. Filed as trap #6 in memory `verification-harness-vacuous-pass-traps`.
- A resumed TUI showing restored scrollback proves the transcript LOADED, not that the session is
  RUNNING — only post-boot transcript rows distinguish the two.

## §12.7 — the fork storm, MEASURED: the collapse §12.5 prescribes does NOT pay, and its cost model was 4× too big

2026-07-31, later the same day. §12.5 named the fork storm "the highest-value remaining capacity
fix" and prescribed §8.5.4's bounded fallback — collapse the chain into one process. That was built
test-first, measured, and **the prescription is falsified**. Two smaller wins in the same area are
real; one is landed. Read this before acting on §12.5's figures.

### 12.7.1 ⛔ The cost model in §8.5.4 / §12.5 is inflated ~4× by a measurement artifact

§8.5.4's per-fork constants (`bash fork+exec 15.5 ms`, `jq startup 15.1 ms`, `python3 68.7 ms`) were
obtained by timing a child from a wrapper. **That bills the wrapper's own fork as well as the
child's.** The marginal cost of one more exec of a page-cached binary inside an already-running
shell is **~2-4 ms**, not 11-15.

Measured directly (`scripts/hook-chain-bench.sh`, which demonstrates the artifact inline so it
cannot be re-made):

| probe | ms |
|---|---|
| wrapper-timed `bash -c 'exit 0'` — **THE ARTIFACT** | 11 |
| a guard's whole preamble `INPUT=$(cat)` + `printf｜jq` | 22 |
| …same, builtin read instead of `$(cat)` | 16 |
| …same, pre-parsed (no `cat`, no `jq`) | 13 |

So a guard's entire redundant preamble is **~9 ms**, of which ~6 ms is the `cat` fork and ~3 ms the
`jq`. The derived claim in the build's own header — *"~93 ms is interpreter startup and ~78 ms is
six redundant jq"* — does not survive; the true figure is ~45 ms across five guards.

**Consequence for §8.5.4's O(N²) argument: the DIRECTION survives, the MAGNITUDE does not.**
Cost-per-fork really is O(load) — which is precisely why the collapse's benefit is small at normal
load and only grows in the high-load regime it exists to prevent. That makes it **unvalidatable by
wall-clock measurement at normal load**, which is a design constraint on any future attempt, not a
detail.

### 12.7.2 What was built, and why it lands INERT

`hooks/hook-chain.sh` + `tests/hook-chain.bats` + `tests/hook-chain-live-parity.bats` +
`config/hook-chains.d/` (commit `a30b5df2`). Correct, 25 bats + 14 selftest checks green,
shellcheck clean — and **deliberately not wired into settings.json**, default mode `exec` (process
model unchanged):

| | ms |
|---|---|
| REAL 6-guard PreToolUse/Bash chain, serial (today) | **169** |
| dispatcher, exec mode | 187 |
| dispatcher, source mode | 169 |
| 6 *no-op* members, serial | 60 |
| 6 *no-op* members, dispatcher source mode | **41** |

It wins on trivial members and not on real ones, because **sourcing is not uniformly cheaper**:
`git-worktree-guard` −3 ms and `keychain-guard` −8 ms, but `validate-bash.sh` **+48 ms**
(94 → 142) — sourcing a large member costs bash the same parse an exec would, minus only process
creation, so the chain's biggest member is its worst case.

It is landed rather than discarded because it is the vehicle any future collapse needs, and because
landing it *with the negative result attached* is what stops the next session rebuilding it. Its
three safety laws are reusable for anything fronting a guard chain: **no skip spelling** (no env
value runs fewer members than the registry — "disable" degrades to fork+exec), **loud inertness**
(absent/empty registry or missing member refuses, never admits — §12.2's rule for `capacity_gate`),
**every member always runs**.

### 12.7.3 ✅ LANDED — six hooks forked `/bin/cat` to read stdin, on every Bash tool call

Commit `c957df9e`. `INPUT=$(cat)` is a fork *and* an exec. Six hooks on the Bash boundary did it —
five PreToolUse plus `log-bash.sh` on PostToolUse — so every Bash tool call paid six of them before
any guard decided anything. Replaced with a builtin read.

Interleaved A/B (both sides in ONE run, pipe stdin, load stable 11.00 → 10.68):

> **6 hooks `$(cat)` = 171 ms → builtin read = 153 ms — 18 ms (10.5%) saved per Bash tool call.**

No new machinery, no dispatcher, interfaces unchanged. This is the fork-storm reduction §12.5 asks
for, delivered by the boring route rather than the architectural one.

### 12.7.4 ⚠ OPEN, operator decision — `curl-gate.py` is project-scoped but registered GLOBALLY

The single largest item in the chain, and it is pure waste almost everywhere:

- `hooks/curl-gate.py:409` — `if not cwd.startswith(PROJECT_ROOT): sys.exit(0)`, where
  `PROJECT_ROOT = "/Users/chrisren/Development/reso-management-app"` (`:36`).
- It is registered in the **global** `settings.json` PreToolUse/Bash chain.
- Measured **48 ms of a 169 ms chain (28%)**; the same chain without it is 130 ms.

So in every session outside that one project — which is nearly all of them, including all of
claude-infrastructure — each Bash tool call spawns a 48 ms python3 process that is *structurally
incapable of deciding anything*. It is also the one member that can never be collapsed (python
cannot be sourced into bash), so no dispatcher work reduces it.

**Not fixed here, because the remedy is a policy choice with two defensible answers** and neither is
mine to pick: (a) move its registration into a project-level `.claude/settings.json` under
reso-management-app — cheapest, but the repo's 5-config-dir parity machinery
(`scripts/settings-drift-assert.sh`) governs global settings, not project ones; or (b) make the hook
project-agnostic so it guards curl everywhere — strictly more security, more cost, and a behaviour
change for every other repo. **(a) is the recommendation**; it is worth ~28% of the hot path.

### 12.7.5 Method notes — four ways this measurement lied before it told the truth

Each was caught by a control, and each is a re-usable trap:

1. **Wrapper-billed fork** (§12.7.1) — the artifact that inflated the whole model 4×.
2. **Cross-run comparison.** The *same* chain read 163 ms and 216 ms twenty minutes apart purely
   because load moved 16.4 → 20.4. A benchmark verdict certifies stability *within* one run only;
   a baseline must be **interleaved into the same run**. `hook-chain-bench.sh` now refuses to print
   a comparison when start/end load diverge >1.25×.
3. **zsh does not word-split.** `for m in $MEMBERS` under zsh iterates **once** over the whole
   string, every hook path is invalid, and the loop reports ~0 ms — a vacuous result that reads as a
   spectacular win. Cost two false readings before it was spotted. (Already trap #1 in memory
   `verification-harness-vacuous-pass-traps`; it recurred anyway.)
4. **Controls that cannot fire.** The first live-parity corpus used `curl --insecure` as
   curl-gate's trigger — which never fires outside `PROJECT_ROOT`, so the mutation control was
   vacuous. The first before/after verdict snapshot produced **0** non-abstain rows because
   `$'\x01'` does not expand inside a heredoc. Both were caught only because each control counts
   its own non-trivial rows and fails when the count is too low. **A parity suite must assert that
   its corpus actually triggers something**, or it is comparing silence to silence.

Also: the aggregation bug this found in its own subject — `rank_of` matched two literal JSON
spellings while the live guards emit **both** compact (`jq -nc`) and pretty (heredoc, space after
the colon) forms, so three guards' verdicts silently ranked 0. Normalize, then match; never
enumerate spellings (memory `denylist-enumerates-spellings-not-the-class`).

And a working note: `keychain-guard.sh` blocks its own trigger string when that string appears in
an *agent's* Bash argv, so test corpora containing it must assemble it at runtime
(memory `guard-refusal-fires-on-its-own-harness`).

### 12.7.6 Ranked remainder for the next session

1. **`curl-gate.py` scoping (§12.7.4)** — ~28% of the PreToolUse/Bash chain, config-only, needs an
   operator decision between (a) and (b) above.
2. **`waiting-recycle.sh` on PostToolUse/Bash** — 101 ms, the single most expensive hook measured,
   fires on every Bash call, and §8.5.4 notes it full-`jq`-parses the transcript per invocation
   (O(transcript), grows monotonically within a session). Not touched here. Measure it the same way
   — interleaved, pipe stdin — before assuming the parse is the cost.
3. **The Stop chain (11 hooks, 287 `$(` sites)** — untouched. It fires once per turn versus the
   Bash boundary's many, so it is second priority despite the bigger site count; and §12.7.1 says
   to expect ~9 ms/hook of removable preamble, not the ~24 ms §12.5's constants imply.
4. **The long-lived broker** (§8.5.4's actual structural answer, of which the collapse was only the
   bounded fallback) — still unbuilt. §12.7.1's constraint applies: it cannot be validated by
   wall-clock at normal load, so it needs a fork-COUNT acceptance criterion, not a millisecond one.

### 12.7.7 ⚠ LANDED ≠ LIVE — the 18 ms/call win is inert, and so is everything else landed today

Checked immediately after landing §12.7's commits, because "landed" in §12.7.3 would otherwise read
as "in effect". It is not:

- `~/Development/claude-infrastructure` (the shared checkout that **all** `~/.claude/{hooks,bin,
  scripts}` per-file symlinks point into) is **75 commits behind origin/main**.
- `com.claude.deploy-live` IS loaded, and IS running — with **last exit 1**. Its log gives two
  distinct refusals:
  - `REFUSED — target 34e725d629ca is not a descendant of live HEAD ec92e68ce0fd — this would ROLL
    BACK the live layer`
  - `REFUSED — no GREEN stamp among the newest 200 commits of origin/main — nothing is safe to
    deploy`

So the fleet is still running the OLD hooks: the six `$(cat)` forks are still being paid on every
Bash tool call in every live session, and will be until the live layer advances.

The second refusal is memory `verify-throughput-below-trunk-velocity` recurring — *"0 green stamps
all day was a CONVERGENCE deadlock (105 commits/3h vs a 0.8-3.1h verify), not a failing test"*. The
first is the divergence shape from `idempotent-repair-gated-behind-conditional-advance`: live HEAD
is not an ancestor of the deploy target, so every tick refuses rather than advancing.

**Not fixed here, deliberately.** It is a different subsystem from this row, it was already filed as
§8.5.2's row-1 operator item (*"the deployer is broken"*, not *"deploy to get your ceiling"*), and
the repair would have to touch the shared checkout — which this session is barred from (it holds two
dirty files belonging to other sessions, and is the symlink source for the live layer). Recorded
here so no one reads a landed millisecond figure as a live one.

**Consequence worth stating plainly:** every capacity fix this plan lands is inert until the
deployer converges. That makes the deploy stall a higher-priority capacity item than anything
remaining in §12.7.6 — a fix that cannot reach the fleet has an effect size of zero.
