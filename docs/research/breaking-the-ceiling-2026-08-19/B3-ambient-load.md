# B3 — The 20.19: what is actually in the admission gate's numerator

**Date:** 2026-08-19 · **Box:** MacBookPro18,2 M1 Max, `hw.ncpu`=10, 64 GiB, macOS 15.6.1, CC 2.1.220
**Axis question:** attribute the ambient load, split it three ways, decide whether the gate is right,
and price the prize.
**Windows measured:** four censuses spanning load1 **8.35 → 46.39** on the same box, same day.

---

## 1 · Verdict

1. **The ambient is not 20.19 and is not a level at all.** Load1 ranged **8.35–46.39** in one day;
   the `×1.553` R-procs→load factor behind 20.19 is not reproduced by any of my windows (measured
   **0.913 / 1.077 / 1.235**). Re-derived with a factor my instrument actually measured, the prior's
   own 13.000 R-procs is **13.0–16.1 load units — BELOW the 20.0 ceiling.** "Ambient alone exceeds
   the gate" does not survive re-derivation. What IS stable is the **share**.
2. **Our own tooling is 25.9% of the load numerator — more than double Claude's 12.7%** — and
   **`cc-backlog` alone is 17.5% of the whole box**, 1.4× the entire Claude fleet. That is (b), and
   it is the actionable number.
3. **One command explains it.** `cc-backlog list --blocked --json` folds a **4.2 MB** append-only
   JSONL through ~137 `jq` sites: **4.38 CPU-s, ≥56 forks, 5.8–7.5 s wall**. Six Stop hooks resolve
   `wrap-ledger.sh`, which calls it **uncached**; `completion-assert.sh` calls it again with a
   **5 s timeout it can no longer meet — rc=124, 3 of 3 runs.** The box pays the full fork storm for
   a check that has silently become a no-op.
4. **The gate is measuring the wrong thing, and the right term is already built.** At load **37.17**
   (186% of ceiling ⇒ REFUSE) the live `cc_sp_active` read **4 of a ceiling of 8** (⇒ ADMIT). Wire
   `capacity_gate()` to `cc_capacity_admit`'s `active`+`segments`+`headroom` terms with the load
   term **off** — the same configuration `capacity-admit.sh` already uses on the Agent-tool path.
5. **Prize, both methods agreeing: 10 of 19 capacity refusals in 9 days become admits (~53%)** —
   ≈1.2 extra fires/day. Real but small. **The larger prize is not the gate**: 5–7 s of dead
   wall-clock on every turn-end of every session, growing with the store, is a direct tax on
   session-*equivalents*. This is a **SUSTAINED** lever, not a burst one, and it costs the BOX only —
   zero quota.

---

## 2 · The numbers, with the command behind each

### 2a · The three-way split — the headline table

Definitive census `run4`: **240 samples**, per-thread `R`+`U` states joined to a full ppid/argv
ancestry table, nearest-recognisable-owner attribution. **Mean load1 = 34.56, mean census = 37.88
threads ⇒ ratio 0.913 — the level control PASSES to within 8.7%** (§2b). `load-equiv` = threads ×
0.913.

| class | threads/sample | % | load-equiv | MEASURED/INFERRED |
|---|---:|---:|---:|---|
| **A1 macOS / third party** | 12.733 | 33.6% | 11.62 | M |
| **B1 OUR AUTOMATION** (hooks · pollers · CLI) | **9.817** | **25.9%** | **8.96** | M |
| **C CLAUDE** sessions/agents + their tools | 4.804 | 12.7% | 4.38 | M |
| ? unattributable (exited between the two `ps` passes) | 4.117 | 10.9% | 3.76 | M |
| A2 `next dev` devserver (`wt-pool-2`) | 2.571 | 6.8% | 2.35 | M |
| B2 terminal / shell (iTerm2 · kitty · zsh) | 1.504 | 4.0% | 1.37 | M |
| A3 Dia browser (39 renderers) | 1.454 | 3.8% | 1.33 | M |
| X **this wave's own instrument** (disclosed, excluded from B1) | 0.646 | 1.7% | 0.59 | M |
| A4 Cursor | 0.229 | 0.6% | 0.21 | M |
| **TOTAL** | **37.875** | 100% | **34.56** | |

`claude.exe` **itself** is only **1.592** threads (4.2%); the rest of C is `ugrep`/`next-build`/etc.
that Claude's Bash tool spawned. **The unattributable 4.117 are almost certainly short-lived forks
of the same storm, so B1 = 9.817 is a FLOOR** (ceiling 13.93 = 36.8% if all of them are ours).

```sh
# sampler (240 iters, ~0.55 s apart): per-thread runnable+uninterruptible, plus a full ppid/argv table
ps -axM | awk '<count STAT ^R or ^U per pid>'            # → run4/th.tsv
ps -axo pid=,ppid=,args=                                  # → run4/pr.tsv
sysctl -n vm.loadavg                                      # → run4/ld.tsv
# attribution: walk ppid to the nearest owner; global pid map as fallback for exited parents
```
Harness + raw data: `/tmp/b3/{fin.sh,final.py,run1..run4}`.

### 2b · The control that had to be able to fail — and what it says

Prior waves quoted attribution from a census that **never cleared its own control** (`corr(load,
R-procs) = −0.05`). I ran it three times.

| window | mean load1 | mean census | **ratio load/census** | corr(load, EWMA60(census)) |
|---|---:|---:|---:|---:|
| run1 (quiet, R only) | 12.814 | 10.380 | 1.235 | −0.088 |
| run2 (mid, R+U) | 14.886 | 13.820 | 1.077 | −0.537 |
| **run4 (busy, R+U)** | **34.560** | **37.875** | **0.913** | n/a (short window) |

**LEVEL control: PASSES** — three windows across a 2.7× load range, ratio 0.913–1.235, best
agreement at the high load that matters. **DYNAMICS control: FAILS/UNDECIDED** — correlation is
negative, but each window is only 2.5–4 min against a 60 s time constant ≈ 2.5 independent
observations, so the correlation is uninformative, not refuting. **Read every figure here as a
LEVEL attribution and never as a predictor of load's motion.**

**This kills the ×1.553.** No window reproduces it. It is not a calibration; it is a fudge factor
fitted at one point, and every absolute derived from it (including 20.19) inherits ~55% inflation.

### 2c · (b) broken down — one command is two thirds of it

| owning script | threads/sample | % of B1 | % of box |
|---|---:|---:|---:|
| **`cc-backlog`** | **6.642** | **67.7%** | **17.5%** |
| `find-plan.sh` | 0.929 | 9.5% | 2.5% |
| `cc-dispatch` | 0.525 | 5.3% | 1.4% |
| `capacity-alarm.sh` | 0.383 | 3.9% | 1.0% |
| `plan-phase-scan.sh` | 0.375 | 3.8% | 1.0% |
| `teammate-reap-alarm.sh` · `deploy-live.sh` · 12 others | 0.963 | 9.8% | 2.5% |

By immediate image, the single largest row on the entire box is **`jq` = 4.550 threads** — **2.9×
`claude.exe`'s 1.592.**

### 2d · The mechanism, measured

| fact | value | command |
|---|---|---|
| backlog store size | **4.2 MB / 12,314 lines** (was 2.1 MB when last researched — **doubled**) | `wc -c -l ~/.claude/autonomy/backlog.jsonl` |
| `jq` call sites in `cc-backlog` | **137** | `grep -c "jq " ~/.claude/bin/cc-backlog` |
| one call, unbounded | **7.54 s / 5.81 s** wall | `time cc-backlog list --blocked --json` |
| one call, CPU | **user 2.00 + sys 2.38 = 4.38 CPU-s** (sys > user ⇒ fork/exec, not compute) | `/usr/bin/time -p` |
| one call under the shipped bound | **rc=124 at 5.05 s, 3 of 3** | `timeout 5 cc-backlog list --blocked --json` |
| distinct helper processes per call (FLOOR, ~50 Hz sampling) | **≥56** (`jq` ×~56, `ugrep`, `awk`, `sed`, `head`, `grep`) | pid-set sampling during one call |
| Stop hooks configured | **12** (PreToolUse 16, PostToolUse 12) | `jq` over `~/.claude/settings.json` |
| Stop hooks that resolve+invoke `wrap-ledger.sh` | **6** (`session-continue`, `anti-deference-nudge`, `completion-assert`, `boundary-handoff`, `operator-readout`, `dod-persist`) | `grep -nE '^[^#]*wrap-ledger\.sh'` |
| cached call sites | **3, all in `operator-readout.sh`** (`blg_list_cached`) | `grep -n blg_list_cached hooks/*.sh scripts/*.sh` |
| uncached call sites on the Stop path | **`completion-assert.sh:611` + `wrap-ledger.sh` `count_operator_steps()`** | source read |

**Two compounding defects.**
**(i) The bound is now shorter than the work.** `completion-assert.sh:611` runs
`timeout 5 … --blocked --json`; the call takes 5.8–7.5 s. rc=124 fails the `[ "$brc" -eq 0 ]`
guard, so `d1` stays 0 — **the D1 "operator work prosed instead of filed" oracle is dead, silently,
fail-open** — and the box still pays 4.38 CPU-s and ≥56 forks for the nothing it returns. This is
the repo's own `[Repro exonerates]` / `[Retry bound too small]` shape: a bound sized before its
subject grew.
**(ii) The cache is defeated by the fleet it was built for.** `blg_list_cached` keys on
`(mtime,size)` of the append-only store — exact, but **every append by any of 18 sessions
invalidates it for all of them**. Measured append rate **9–29 rows/hour** (`ts` histogram over
`backlog.jsonl`), i.e. a bust roughly every 3 min, against a per-session Stop cadence faster than
that. 52 cache files in a 240-min window = 52 distinct store versions folded.

### 2e · The named suspects, refuted by measurement

Process **count** is not load. Every suspect nominated from a casual `ps`:

| suspect | live count | **threads/sample** |
|---|---:|---:|
| `gitstatusd-darwin-arm64` | 18 | **0.0000** |
| `caffeinate` | 7 | **0.0000** |
| `SpeechSynthesisServerXPC` | 14 | **0.0000** |
| `sleep` (41 live; all children of `cc-await-ping`×25, `lead-crash-watchdog`×12) | 41 | **0.0000** |
| `distnoted` | 17 | 0.154 |
| `cfprefsd` | 11 | 0.167 |
| Dia `Browser Helper (Renderer)` | 39 | 1.225 |
| `mds`/Spotlight | — | 1.025 |
| iTerm2 | 1 | 1.279 |
| kitty | 1 | 0.225 |
| WindowServer | 1 | 0.204 |
| `kernel_task` | 1 (740 threads) | **0.0000 — INVISIBLE to `ps -axM`** |

**39 processes contributing exactly zero.** The 25 `cc-await-ping` + 12 `lead-crash-watchdog` poll
loops are `sleep`-blocked and cost nothing at rest — a poller's process count says nothing about its
load. `kernel_task` is the instrument's known blind spot (25–28% CPU by `top`, 0 threads by `ps`);
it is inside the 0.913 ratio's 8.7% residual, not attributable.

### 2f · Is the gate right? — the two numbers that settle it

```sh
sysctl -n vm.loadavg                      # { 37.17 30.29 20.76 }  → 3.72/core > 2.0  ⇒ REFUSE
. scripts/lib/spawn-presence.sh; cc_sp_active   # 4              → 4 of ceiling 8    ⇒ ADMIT
```
Same instant. The load term and the term designed for this job **disagree by 3.7×, and only one of
them measures Claude.** `capacity_gate()` (`scripts/handoff-fire.sh:4368`) evaluates exactly **two**
terms — `load` and `headroom`. Its sibling `cc_capacity_admit` (`scripts/lib/capacity-admit.sh`)
already ships **four** — `load`, `headroom`, `segments` (compressor %, the actual panic mode),
`active` (mid-turn sessions, ceiling 8) — **and already turns the load term OFF on the Agent-tool
path.** `cc_sp_active` is live and costs 0.75 s / 0.44 CPU-s.

`capacity-admit.sh:16` also already records the retraction — *"discard 1-min loadavg/ncpu as the
saturation proxy with a fixed 2.0 ceiling"* — and `:20` the live proof, and `§8.5.7` that iTerm2 +
WindowServer + XProtect are ~2.4 **unsheddable** cores, so refusing spawns cannot lower the number
the gate reads. **My measurement is the missing quantity for that retraction: 87.3% of the numerator
is not Claude.**

Corroborating decoupling: at load 15.72, `iostat -c` read **53–57% idle**; summing `top`'s own
per-process `%CPU` gave **269.8% of a 1000% ceiling**. The gate was at 79% of its ceiling with 5.5
cores idle. Later, at load 42.99, `iostat` read **us 65 / sy 35 / id 0** — a 35% system share, the
signature of fork/exec, not computation.

### 2g · Gate telemetry — what the gate has actually done

```sh
jq -r 'select(.class=="refused" and .gate=="capacity" and .under_test==false)|.detail' \
   ~/.claude/logs/handoffs.jsonl
```
**19 production capacity refusals in 9 days**, against **213 admits carrying a load reading**
⇒ **22 of 232 evaluations (9.48%) above 20.0**. Load at refusal: 20.46 · 20.62 · 20.70 · 20.84 ·
21.00 · 21.16 · 21.89 · 22.17 · 22.45 · 22.54 · 24.88 · 26.24 · 27.75 · 27.99 · 30.03 · 33.19 ·
44.43 · 46.39 · 118.95. **Ten of nineteen sit between 20.46 and 22.54** — inside 2.6 points of the
ceiling. Admit-side distribution: p25 9.24 · **p50 12.59** · p75 15.76 · p90 18.27.

---

## 3 · The prize — the arithmetic, two independent ways

**Removing `cc-backlog`'s fold from the Stop path removes 6.642 threads = 6.06 load points.**

**Method A — absolute subtraction** against the observed 232-evaluation distribution:

| ambient shed (load pts) | evaluations still > 20.0 | refusal rate |
|---:|---:|---:|
| 0.0 | 22 | 9.48% |
| 2.0 | 15 | 6.47% |
| 4.0 | 12 | 5.17% |
| **6.0** | **11** | **4.74%** |
| 8.0 | 7 | 3.02% |

**Method B — proportional** (B1 = 28.4% of the numerator at any load; `cc-backlog` = 67.7% of B1
⇒ ×0.808): every refusal below **24.75** becomes an admit ⇒ **10 of 19**.

**Both land on ≈50%: the capacity-refusal rate halves, 22→11 or 19→10, ≈1.2 extra fires/day.**
Method B's proportionality is **INFERRED** — I measured B1's share at load 34.56, not at 20.7.

**Honest ceiling on this lever:** even shedding *all* non-Claude load only takes the refusal rate
9.48% → ~0%, i.e. **at most 22 extra fires in 9 days.** The gate is **not** what holds the fleet at
~15. Whoever concludes otherwise is pricing a 9.5% event as if it were the wall.

**The lever that is worth more than the gate — and it is SUSTAINED, not burst.** Every turn-end of
every session pays **5.05 s** (the timeout) to **7.5 s** (unbounded) of wall-clock on a store fold,
at ≥2 uncached call sites, for a check that returns `rc=124`. Against a ~60–90 s turn that is a
**5.6–11% throughput tax on every session-equivalent in the fleet**, and it is **superlinear in
fleet size** — more sessions ⇒ more appends ⇒ more cache busts ⇒ more full folds. In
session-equivalent terms across 18 resident / ~6.5 working sessions that is **≈0.4–0.7 working
sessions of pure wait, recovered for free.** It costs no quota, no cloud, and changes nothing about
how we work.

---

## 4 · The top 3 reductions, with measured cost

| # | reduction | measured cost removed | risk | effort |
|---|---|---|---|---|
| **1** | **Give `cc-backlog list` an index instead of a full-store `jq` fold** — or at minimum extend `blg_list_cached` to `wrap-ledger.sh`'s `count_operator_steps()` and `completion-assert.sh:611`, the two uncached Stop-path callers. | **6.642 threads · 17.5% of the box · 4.38 CPU-s × N-per-Stop · ≥56 forks/call** | low — read path only; the `(mtime,size)` key is already exact | small (cache extension) / medium (index) |
| **2** | **Fix the bound before the store outgrows it again.** `timeout 5` is now shorter than the 5.8–7.5 s call: the D1 oracle is dead fail-open while still billed. Either raise the bound *and* cache, or delete the call. | restores a silently-dead close-integrity check **and** removes a pure-waste 4.38 CPU-s | low | trivial |
| **3** | **`find-plan.sh` (0.929) + `cc-dispatch` (0.525) + `plan-phase-scan.sh` (0.375) — same fold pattern, same fix.** | 1.829 threads · 4.8% of the box | low | small |
| — | **NOT worth doing:** quit Dia (1.454 = 3.8%), kill gitstatusd/caffeinate/speech (**0.000**), switch terminal (iTerm2 1.279 vs kitty 0.225 — real but a one-off 1.05). | — | — | — |

---

## 5 · What I could NOT measure, and why

1. **`kernel_task`.** 740 threads, 25–28% CPU by `top`, **0 by `ps -axM`**. It is unattributable by
   this instrument and sits inside the 8.7% level-control residual. `sudo`/`dtrace` would resolve it;
   I have neither and would not run them on the live fleet.
2. **The 4.117 unattributable threads (10.9%).** Processes that exited between the thread pass and
   the ancestry pass (~0.15 s). A global pid-map fallback recovered most; these are the residue.
   They are shorter-lived than 0.15 s, which makes them *almost certainly* fork-storm members — so
   B1 is a floor, not a point estimate. Proving it needs `dtrace proc:::exec-success`.
3. **The dynamics control.** Every window was 2.5–4 min against load1's 60 s constant ≈ 2.5
   independent observations. The negative correlations are uninformative. **A multi-hour census
   spanning real load excursions is the one measurement that would let anyone predict load from a
   census rather than merely apportion it.**
4. **How many of the 6 wrap-ledger Stop hooks actually reach the backlog call on a given Stop.**
   All six *resolve and invoke* `wrap-ledger.sh` (static read); whether each reaches
   `count_operator_steps()` depends on guards I did not execute — executing Stop hooks writes live
   state, which rule 4 forbids. The per-Stop multiplier is therefore **1 ≤ N ≤ 7**, and every
   figure above uses **N=2** (the two call sites I proved uncached).
5. **B1's share at a *marginal* load (~20.7).** Measured at 34.56 only. Method B assumes
   proportionality; Method A does not, and they agree — but neither is a measurement at 20.7.
6. **My own instrument is in the numerator: 0.646 threads (1.7%)**, plus a sibling wave watcher
   (`scratchpad/w.sh`) and my `ps` loops. All are classified `X` and excluded from B1 and from every
   percentage. The wave itself is also *in* the C bucket: **C is 12.7% measured during a 14-agent
   research wave — i.e. an upper bound on Claude's ordinary share, not a typical one.**
7. **Nothing was killed, stopped, torn down, or reconfigured.** No `settings.json`, `.claude.json`
   or `accounts.json` was read for write or modified. All probes are `ps`/`top`/`iostat`/`sysctl`
   reads plus five `cc-backlog list` invocations (a read-only subcommand).

---

## 6 · The decision this axis changes

**Do not spend effort "halving the ambient". Spend it on two edits.**

1. **Cache or index `cc-backlog list` on the Stop path** (extend `blg_list_cached` to
   `wrap-ledger.sh` and `completion-assert.sh:611`). This is the only item in the whole ambient
   picture large enough to matter: **17.5% of the load numerator, 1.4× the entire Claude fleet,
   and 5–7 s off every turn-end of every session.** It is a **sustained** lever and it costs the box
   only — no quota, no cloud.
2. **Re-key `capacity_gate()` off load.** Concrete term, using code that already exists and is
   already live on another path:

   > **Admit unless** `cc_sp_active + 1 > CC_ADMIT_ACTIVE_CEILING` (8) **or**
   > compressor segments ≥ `CC_ADMIT_MAX_SEGMENT_PCT` (50) **or**
   > reclaimable headroom < `CC_HW_DEFAULT_MIN_HEADROOM_GB` (4).
   > **Load term OFF** on the fire path, exactly as `capacity-admit.sh` already sets it on the
   > Agent-tool path. Keep the `CC_ADMIT_BUDGET` bound.

   **Do NOT "subtract ambient" from the load term.** Ambient is not a constant (8.35→46.39 in one
   day), so any subtracted number is stale within hours; and measuring it at gate time costs a
   0.15 s per-thread census that would itself enter the population it measures — the repo's own
   `[Gate ≠ own signal]` defect.

**And retire "the ambient is 20.19."** It is a snapshot multiplied by a factor no window reproduces.
The durable, replicated statement is the **share**: **Claude is ~12% of the load-average numerator
even mid-wave; our own tooling is ~26%; the single largest process class on this box is `jq`.**

**What this axis does NOT license.** The gate is a **9.5%** event. Fixing it entirely buys ~22 fires
in 9 days. If the operator wants >15 concurrent session-equivalents, this axis returns the
throughput tax (worth ≈0.4–0.7 working sessions, free) and a corrected gate — **not the ceiling.**
The ceiling is somewhere else, and any wave conclusion that rests on "ambient alone exceeds the
gate" now rests on a refuted premise.
