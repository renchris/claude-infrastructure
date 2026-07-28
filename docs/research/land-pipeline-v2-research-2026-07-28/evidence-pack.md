**Note:** `SendMessage` is not exposed in this subagent's tool inventory (verified via ToolSearch — only `WebSearch`/`WebFetch` are deferred). This report is my final return; harvest from here.

---

# LANDING PIPELINE — MEASURED EVIDENCE PACK (no architecture framing inherited)

**Method.** Read all 9 named docs in full + the restart brief (`git show origin/main:docs/research/RESTART-BRIEF-2026-07-27.md` — not in the working tree; HEAD is 2 behind origin/main). **Every doc-sourced number was independently re-derived from live disk** (`~/.claude/land.log` 788 rows, `~/.claude/autonomy/postland/stamps/` 24 files, `flakes.jsonl` 26 rows, `scripts/ship-land.sh`, `scripts/postland-verify.sh`, `launchctl list`, `cc-backlog`). Where re-derivation disagrees with a doc, **both are given and the doc is marked ✗** (§6).

---

## 1. MEASURED CONSTANTS

### 1.1 Corpus size — the `n` in every model (moving target)

| Date/source | suites | tests | cite |
|---|---|---|---|
| 2026-07-25 research | 117 | ~1,579 | `GATE_RELIABILITY_2026-07-25.md:32`, `:172` |
| 2026-07-25 build | 118 → 121 | — | `:574-575` |
| 2026-07-26 root-cause | 124 | 1,749 | `LANDING_GATE_ROOT_CAUSE_2026-07-26.md:31`, `:310` |
| 2026-07-26 plan | 126 | — | `GATE_ARCHITECTURE_PLAN.md:41-56` |
| 2026-07-26 postland | 137 / 141 | 2,085–2,242 | `GATE_ARCHITECTURE_PLAN.md:341`; backlog `b59eb997d035`, `b4e49b4b5014` |
| **2026-07-27 LIVE** | **144** | **2,307** | live: `ls tests/*.bats \| wc -l`; `bats --count tests/` |

Hermeticity lint LIVE: `144 suites; 106 grandfathered, 0 new leaks` (ran `scripts/test-hermeticity-lint.sh`). Was `118/109/9` at build (`GATE_RELIABILITY:575`), `109 of 124` non-hermetic (`ROOT_CAUSE:371`).

### 1.2 Full-gate wall time

| Metric | Value | Cite |
|---|---|---|
| Full sweep, load 16–40 | **1,615 s (26.9 min)** / 117 suites; independent run 1,710 s | `GATE_RELIABILITY:172-173` |
| Load elasticity | **1.8–2.5×** ("~15 min" is the low-load figure) | `:173` |
| Full gate range (postland runner.log) | **1,186–3,217 s (20–53 min)** | `ROOT_CAUSE:90` |
| Fitted G (3 independent methods) | **1,044 s** | `GATE_RELIABILITY:45-47` |
| **LIVE postland `run_s`** (n=24 stamps, incl. retry ladder) | min **222**, median **2,777**, max **13,248 s (3.7 h)**; ≥6,606 on 4 runs | live: stamps/*.json |
| CPU character | **32% CPU (9 CPU-min)** — 97% of wall is fork/exec, true blocking sleep **≈45 s** of 588 s literal `sleep` | `GATE_RELIABILITY:174-176` |
| Concentration | `cc-reaper.bats` **628 s = 37%** of suite; top-5 = 54%; 65 suites under 5 s total 141 s | `:177-179` |
| Per-file bats overhead | **0.147 s** ⇒ sum-of-files ≈ full-run **+1%** (sharding/per-suite is ~free) | `:211`, `:264` |
| Per-suite runner cost | **+3.0% wall** (0.46 s × 126 = 58 s on a 1,957 s run at load 93) | `GATE_ARCHITECTURE_PLAN.md:101` |

### 1.3 The per-suite hazard law and q

- `P(green) = (1−q)^n`, **q = 2.94% per suite**, MLE over **55 real gate runs** carrying a suite count (`land.log` 00:09:49Z→08:34:06Z 07-26). Single-hazard model **5.0×10⁵ times more likely** than constant-per-run (2·ΔlogL = 26.3). — `GATE_ARCHITECTURE_PLAN.md:41-46`
- P(green): **n=1 → 97.1% · n=3 → 91.4% · n=55 → 19.4% · n=126 → 2.3%** — `:50-56`
- Retry-effective: 2 failed-twice vs 10 retries-passed = **17% retry-failure ⇒ q_eff 0.49%**; P(green|n=126) **2.3% → 49.9%** — `:99-100`
- Flake-elimination ceiling: killing 100% of `not ok` flakes moves q 2.94% → 2.44%, P **2.3% → 4.4%** — `:73-75`

### 1.4 Landing outcomes — LIVE re-derivation of `land.log`

`~/.claude/land.log` has **two writers**: 341 rows carry `"tool":"ship-land"`; **447 rows are `land-lock.sh` lock lines with no `tool` field**. Any rate computed over the raw file is wrong (`ROOT_CAUSE:17` — doc counted 174/256/430; live is 341/447/788).

| Population | n | exit 0 | exit 6 | other |
|---|---:|---:|---:|---|
| **Attested ship-land (all time)** | 341 | **180 (53%)** | **151 (44%)** | 3:10 |
| Attested, BEFORE Phase 1 (`1bc02f6f`, 07-26T21:27Z) | 257 | 153 (60%) | 95 (37%) | 3:9 |
| Attested, AFTER Phase 1 | 84 | **27 (32%)** | **56 (67%)** | 3:1 |
| Lock-only rows | 447 | 234 | 34 | **42:133 · 75:19 · 5:10 · 130:9 · 127:5 · 143:2 · 1:1** |

- **173 distinct branches** attempted a land. Attempts/day: 07-19 **68** · 07-20 19 · 07-21 3 · 07-23 9 · 07-24 4 · 07-25 21 · **07-26 152** · 07-27 65. Lands/day (exit 0): 68 · 16 · 3 · 6 · 4 · 19 · **46** · 18.
- **Median gap between successful lands = 1,161 s (~19.4 min)** (n=179 gaps; mean 4,035 s). Doc said 1,101 s — `ROOT_CAUSE:91`. **T_gate (20–53 min) > T_trunk-move (19 min)** confirmed live.
- `exit:9` (KILLED / non-verdict) has **NEVER been attested — 0 rows**. `exit:4` (shared-checkout refusal) — **0 rows**.
- Historic window (`GATE_RELIABILITY:61-63`): 34 h, **63 full-gate runs → 24 pushes; 39 gates = 11.3 machine-hours pure waste**; one 2-commit landing (U2) took **20 h 25 m and ≥6 full gates**.

### 1.5 Gate-tier split (`selected_n = −1` ⇒ ran `run_bats_all`, the FULL corpus; code-confirmed `ship-land.sh:153,726,862,867,873`)

| Tier | rows | landed | failed | fail rate |
|---|---:|---:|---:|---:|
| **FULL (−1)** — LIVE all-time | 132 | 6 | 126 | **95%** |
| FULL excluding the one 71-attempt branch | 61 | 5 | 56 | **91%** |
| **narrow (≥0)** — LIVE all-time | 82 | 56 | 26 | **32%** |
| FULL / narrow, doc figure (scoped era only) | 34 / 13 | 1 / 7 | 33 / 6 | 97% / 46% (`ROOT_CAUSE:35-36`) |

narrow `selected_n`: **median 27, mean 36.1, max 102, min 0**. Post-Phase-1 narrow: median 29, max 95.
`gate_scope` is literally **`"scoped"` on all 214 rows that carry it** — it records the *policy*, never the tier.

### 1.6 Lock, hold, starvation

| Metric | Value | Source |
|---|---|---|
| Lock hold, exit-0 lock rows (n=234) | median **228 s**, p90 **966 s**, max **6,771 s (1.9 h)** | LIVE |
| Lock hold, all 447 lock rows | median 78 s, p90 682 s, **45.4% under 30 s** | LIVE (doc: median 228/p90 682/29% under 30 s — `ROOT_CAUSE:100-101`) |
| Wait | median **0 s**, p90 **1,961 s**, max **7,386 s** | LIVE |
| **Lock starvation (`exit 75`)** | **19 events, every one at `wait_s` 3600/3601** = the `LAND_LOCK_WAIT` ceiling (`land-lock.sh:62`) | LIVE |
| Stale-gate re-rounds (`exit 42`) | **133 events** | LIVE (doc cited 23 — `ROOT_CAUSE:346`) |
| Pre-CAS-fix hold collapse | median **298 s → 1 s** (n=198 pre-split vs 75 post-split) | `GATE_ARCHITECTURE_PLAN.md:186-188` |
| CAS bench, 4 landers / 6 s gate | hold 6–11 s → **0–1 s**; max queue 28 s → 6 s; occupancy 29 s → 8 s; makespan 36 → 34 s | `land-gate-serialization-2026-07-25.md:124-127` |
| Live 5-day-blockage holder | **3 h 36 m** holder, 3 queued, own land `rc=75` after full 3601 s | memory `five-day-gate-blockage-rootcause.md` |

### 1.7 Load

| Metric | Value | Source |
|---|---|---|
| `gate_admit` ceiling `CC_GATE_MAX_LOAD` | **8** (budget 600 s/call, poll 15 s) | `ship-land.sh:312`; twin in `postland-verify.sh:387` |
| Run-wide cap `CC_GATE_ADMIT_TOTAL_WAIT` | **1200 s**, ship-land only | `ship-land.sh:322` |
| Load while "stuck" | **88–104** (Chrome 153% + iTerm 130% + WindowServer 71%) | RESTART-BRIEF §1 |
| Load after closing Chrome/Dia | 10–16 | RESTART-BRIEF §1 |
| Concurrent-gate load band | 13–19 / 16–26 / 16–40 | `GATE_RELIABILITY:38`, `:172`; backlog `02ba4e52389a` |
| Self-starvation observation | **5 concurrent ship-land gates at load 16–18** vs their own ceiling 8 | memory `gate-admit-ceiling-self-starvation.md` (status: **HYPOTHESIS, untested**) |
| LIVE now | load 5.72 | `uptime` |

### 1.8 Flake / exoneration / cut statistics

- **`flakes.jsonl` LIVE: 26 rows total.** `outcome`: **24 × `pass-on-retry`** (phase `land-gate`), **2 × `1-of-3`** (phase `postland`). **`cut-not-red`: 0 rows — the K2 cut-ledger has never once fired.**
- Top exonerated files: `comms-drain-activate` 7 · `cc-reaper` 5 · `cc-inbox-guard` 4.
- Cut evidence at scale (LIVE): **7 same-second cross-worktree `exit:6` clusters covering 20 REDs**, all within 2026-07-26T03:10Z–06:45Z, 2–4 distinct worktrees each. Doc: 21 of 39 (54%), all FULL tier — `ROOT_CAUSE:120-122`.
- Counter-evidence that the tree is green: full-suite runs on disk reached **1,460 / 1,588 / 1,608 / 1,643 `ok` with ZERO `not ok`**; `fullbats.out` **1,643/1,643 EXIT=0** — `ROOT_CAUSE:124-126`. Clean-room runs since: **2,085 ok / 1 not-ok** (backlog `b59eb997d035`), **2,096 ok / 0** (`c3dd374de94a`), **2,242 ok / 1** (`b4e49b4b5014`), **2,307 tests / 0 not-ok** at load 9 (RESTART-BRIEF §1).
- Failure-shape census: across 6 full-gate transcripts **7,283 `ok`, 3 `not ok`, 15 kill-lines — 83% kills** — `GATE_ARCHITECTURE_PLAN.md:71`.
- SIGKILL localisation: all 3 `exit 137` rows target `tests/cc-reaper.bats`, at loadavg **15.10/15.32/15.32** — the *lowest* in the file, while SIGTERM + genuine `not ok` sit at **19.23–21.10** (load correlation **inverted**) — `ROOT_CAUSE:136-141`.

### 1.9 Post-land net stamps (LIVE)

- **24 stamps · 24 `red` · 0 `green` EVER · `last-green` file absent.** (Docs recorded 5 → 15 → 22 stamps, same 0-green: `ROOT_CAUSE:66`, `GATE_ARCHITECTURE_PLAN.md:219`, RESTART-BRIEF §4.)
- Failing-set frequency: `deploy-parity` **17** · `desk-arm-live` **17** · `desk-recycle-durable` **17** · `lr-team-audit` **17** · `session-continue` **17** · `waiting-recycle` **17** · `test-hermeticity-lint` **7** · **`tests/` (the fabricated cut sentinel) 7** · `cc-relogin-status` 1.
- Those 6 suites measured **154 tests / 0 failures** individually on trunk (`GATE_ARCHITECTURE_PLAN.md:258-266`) and **147 ok / 0 not-ok twice**, alone and together in one bats process (`:293`, `:327-330`, RESTART-BRIEF §1).

### 1.10 Livelock arithmetic

λG = 0.93 at the incident-night burst (λ = **3.21–3.38 lands/h**, G = 1,044 s). Predicted invalidation **60.6%** vs observed **62.5%** — 3% model error (`GATE_RELIABILITY:45-50`).

| G | P(invalidated) | E[wall]/land | P(rounds exhaust → in-lock fallback) |
|---|---|---|---|
| 1,044 s | 62.5% | 46.4 min | 24.4% |
| 300 s | 24.5% | 6.6 min | 1.5% |
| 60 s | 5.5% | 1.1 min | 0.02% |
| 30 s | 2.8% | 0.5 min | ~0% |

`GATE_RELIABILITY:52-57`. Robust to λ doubling (λ=6.8/h, G=60 → 10.7%).

### 1.11 Selector cost

| Measurement | Value | Cite |
|---|---|---|
| Recall on developer-attested co-change pairs | **237/237 (100%)** over 551 commits; 26/26 non-obvious | `GATE_RELIABILITY:141-142` |
| 50-land simulation | median **8 suites / 31 s**; p90 589 s; 1 of 50 → FULL | `:143-146` |
| FULL-trigger allowlist | 24/390 files (6.2%) | `:147` |
| Keystone effect (same 40 trunk commits) | FULL **8/40 (20%) → 3/40 (7.5%)**; 7 of the 8 were `added-unmapped` | `ROOT_CAUSE:222-224` |
| Post-keystone replay (48 real ranges) | **FULL 30/48**; 6 of 18 scoped ranges select 55–76 suites; ≈75% of lands run ≥55 suites | `GATE_ARCHITECTURE_PLAN.md:86` |
| K3 closure breadth (pure-M, 2-file change) | **55 of 124 suites · 989 of 1,749 tests (57%)**; 55/55 carry `closure`; **39/55 (71%) reachable ONLY via closure** | `ROOT_CAUSE:309-313` |
| K4 union amplification | own range **4 suites → 57 after one sibling landed = 14×** | `ROOT_CAUSE:336-343` |
| Proof-cache headroom | suites whose closure intersects a commit: **median 1, mean 25.4, max 70 of 126**; 57 gate runs shared 15 bases / 43 trees ⇒ **5,394 → ~986 executions (5.5×)** | `GATE_ARCHITECTURE_PLAN.md:164-166` |
| Docs-only ranges | still map to FULL (~1,630 tests for a docs land) | backlog `4a420270c9c8` |

### 1.12 Stranded exposure (four detectors, all disagreeing)

Raw `origin/main..HEAD` summed **342 rows/36 branches** → union of distinct SHAs **219** → patch-id dedup **164** (`STRANDED_EXPOSURE_2026-07-26.md:§1`). Re-scoped: **481 branches carry unlanded commits, 208 are ship-land's own `ship/backup-*`/`preland-backup-*` refs ⇒ 273 real branches, 396 commits, 197 patch-ids, 190 truly stranded** (`ROOT_CAUSE:16`). Of 60 orphan-exclusive patches, **4 RECOVER / 56 ABANDON**; 73 of 81 carrying branches are backup refs that `ship-land.sh:690` never deletes. **49 worktrees live now.**

---

## 2. FAILURE TAXONOMY — every distinct mode, with counts

| # | Mode | Mechanism (file:line) | Measured frequency / impact |
|---|---|---|---|
| F1 | **Load-kill / external SIGTERM cut, laundered as RED** | `run_bats_all` branched on exit code only (`ship-land.sh:246-249` pre-fix); `postland-verify.sh:150` fabricated `failing=tests/` | **20 REDs in 7 same-second cross-worktree clusters** (LIVE); 4 of 5 postland "REDs" were cuts (`ROOT_CAUSE:116-118`); **`tests/` sentinel still in 7 of 24 live stamps** |
| F2 | **Peer sessions `pkill` each other's gates** | ad-hoc typed commands; live killer PID 26727 `/tmp/wt-close-harden` `kill -TERM` over every `ship-land.sh` + `bats` on the box; `reaper-e2e.sh:24` same pattern | ≥54% of REDs externally cut; **true rate unmeasurable — ship-land installs no signal trap**, so `exit:143` is a **~18% capture floor** (only 2 rows LIVE) (`ROOT_CAUSE:21,57`) |
| F3 | **HUNG gate (no signal, reproducible wedge)** | `bin/cc-inbox-guard:39/95` forks real `it2` unbounded; `${VAR:-}` cannot distinguish unset from set-empty so the disable seam never disabled | `rc=124, 2 of 14 ok` → `rc=0, 14/14` after bound. **Named as THE 5-day whole-box outage**; fix existed as **dangling commit `c3edb2d`, reachable from no branch head**, recovered as `b5ccde0` (memory `five-day-gate-blockage-rootcause.md`; backlog `fe21305312ec`) |
| F4 | **Lock starvation** | `land-lock.sh:62` 3600 s ceiling → exit 75 | **19 events, all at the ceiling** (LIVE). Max observed queue 2,777 s = 77% of ceiling (`GATE_RELIABILITY:63`) |
| F5 | **In-lock fallback serialises the box** | `ship-land.sh:666-670`, `main_locked:424-428` after `SHIP_LAND_GATE_ROUNDS`(3) | Live: PID 97389 held lock **35+ min**; max hold **6,771 s (1.9 h)**; only 45% of holds <30 s (LIVE) |
| F6 | **Stale-gate re-round churn (exit 42) + union amplification** | `ship-land.sh:322-325` unions `FIRST_BASE..new-base` | **133 exit-42 rows LIVE**; one land's cost went **4 → 57 suites (14×)** from a sibling's land (`ROOT_CAUSE:336-343`) |
| F7 | **Admit-ceiling self-starvation** | ceiling 8; each gate's own corpus is the load the others wait on | 5 concurrent gates at load 16–18. **HYPOTHESIS, untested** (memory `gate-admit-ceiling-self-starvation.md`) |
| F8 | **Per-call admit bound multiplying across a loop** | `gate_admit` 600 s is **per call**; ship-land calls it at `:536,:585,:601,:677` | postland re-enters ~12×/corpus ≈ **2 h of sleeping**; turned a 43-min run into **2 h 27 m** (RESTART-BRIEF §1; backlog `60ec4c2d86d4`). **`grep TOTAL_WAIT scripts/postland-verify.sh` = ABSENT** (LIVE) |
| F9 | **Deterministic hard stops that no retry can clear** (§9's class) | (a) hermeticity ratchet, tree-scoped → each land answerable for every other's file (4 hit in one night: `push-send`, `cc-wait`, `settings-drift`, `handoff-splitright` mid-gate); (b) wall-clock fixtures (`cc-relogin-status` crossed 2026-07-27T00:00Z); (c) deploy drift (4 trunk scripts never symlinked); (d) unconditional escalation PARK at preflight | `GATE_ARCHITECTURE_PLAN.md:444-456`. **exit 3 (PARK) = 10 rows LIVE** |
| F10 | **Frozen-port / fork-EAGAIN suite** | `cc-authbrowser.bats` binds ports 9341–9344, un-overridable | fails **~3/26 in EVERY gate**; 2 of 2 ship-land gates RED at load 50 AND load 14; 26/26 green in isolation (backlog `4ab95ffe2374`, `e280bbc8b6e4` via `3c6bf04ba842`) |
| F11 | **Whole-tree assertion inside a concurrent suite** | `test-hermeticity-lint.bats:22` lints the WHOLE tree mid-full-suite | passes standalone, fails in-suite. **This is the localized single cause of 14 consecutive red stamps** (backlog `b59eb997d035`) |
| F12 | **PID-reuse flake in the lock's own suite** | `land-lock.bats` `sleep 1 & kill $!` → OS recycles pid to a live proc → 75 not 0 | 2 consecutive ship-land exit 6 on a docs-only branch green 1579/1579 in isolation (backlog `dae1de8e9943`) |
| F13 | **Non-deterministic 6–8 min suite stall** | `comms-drain-activate.bats`, suite-position varies, self-releases | wedges every gate past foreground timeouts (backlog `11c7797f2e99`) |
| F14 | **Carrier lifetime, not gate health** | agent Bash tool hard-capped at **10 m 00 s (exit 143)**; a ~60-min gate inside one is truncated → exit 6 with ZERO `not ok` | 6 attempts on `761a546f939c` all "rc=6 with zero not-ok" (backlog `761a546f939c`) |
| F15 | **Retry-loop amplification by one branch** | — | `wt-1a941c28a079`: **71 attempts, 70 exit 6, 1 land**, spanning 28 h 10 m; **28 attempts in one 56-min window** (06:02–06:58Z 07-27), all FULL tier (LIVE) |
| F16 | **Lock keyed per-worktree, not per-repo** | `land-lock.sh:27-28` uses `--show-toplevel` | two worktrees get different lock dirs and land concurrently; bats suite overrides `LAND_LOCK_DIR` so keying is **untested** (`p09-ship-land.md:14-21`, G-P9-1 `:118`) |
| F17 | **REFUTED: OOM/jetsam** | — | **ZERO `memorystatus: killing` events in 4 h** with a passing positive control (2,568 `memorystatus` lines). 64 GB RAM, 5 TiB swap headroom. 63 bats = 2.7 GB vs 27 `claude` = 9.6 GB (`ROOT_CAUSE:20,58`) |
| F18 | **REFUTED: hermeticity as the driver** | — | 9/13 observed-failing suites non-hermetic = **69%, BELOW the 86.5% base rate** (P(X≤9\|neutral)=0.087); a hermetic suite (`desk-recycle-durable`, fixtures `$HOME` at :19) failed reproducibly; 83% of failure lines are kills, not `not ok` (`GATE_ARCHITECTURE_PLAN.md:65-77`) |
| F19 | **REFUTED (then partly re-instated): it2 API wedged machine-wide** | 8 direct probes rc=0 in 1.2–3.6 s | filed as ARTIFACT (`ROOT_CAUSE:18`), then **the refutation itself retracted** — trunk landed `5a80a64` "an unbounded probe deadlocked the fleet"; the fault is **intermittent**, so a single-moment probe cannot refute it (backlog `fe21305312ec` second correction) |

---

## 3. TRIED — SHIPPED? HELPED? RESIDUAL?

| Intervention | Shipped | Measured effect | Residual / stated reason it didn't unblock |
|---|---|---|---|
| **Unlocked optimistic CAS gate** (gate outside the lock, 3 rounds + in-lock fallback) | ✅ `190c839` (2026-07-24) | Lock hold median **298 s → 1 s**; bench max queue 28 s → 6 s. Doc states it **must not be reverted** | Did **not** touch G. Two modes survived it by name: **load-flake false-REDs** and the **exit-42 re-gate storm** (`GATE_RELIABILITY:9`, `:26-43`). LIVE: 133 exit-42 rows, 19 exit-75 |
| **Changed-scope selector** (`gate-select.sh`, 7 clauses, fail-closed) | ✅ `d1c5219` (07-25T18:08 PDT) | 100% recall on 237/237 historical pairs; median land 15 min → ~4 min in sim | `added ⇒ FULL` rule routed the fleet's dominant change shape (`bin/x` + `tests/x.bats` added together) into FULL: **3 of 4 replayed failing ranges said `FULL <- added-unmapped`** (`ROOT_CAUSE:71-86`) |
| **Keystone: delete `added-unmapped`** | ✅ `19a2cfe` | FULL **20% → 7.5%** on 40 trunk commits; landed through the normal scoped path; 3 tests sabotage-proven | Post-keystone replay still **FULL 30/48**; "scoping has hit its correctness floor" (`GATE_ARCHITECTURE_PLAN.md:86`) |
| **CUT ≠ RED (TAP-body verdict, both layers)** | ✅ `c605a2e` | 390 ok / 0 not-ok; sabotage-proven both layers. Unblocked `deploy-live` conceptually | **A labelling change, not a landing change** — converts 33 false REDs into 33 undecidables with no policy; P(green\|FULL) stays 2.6% (`:87`). **LIVE: `exit:9` attested 0 times; `cut-not-red` written to flakes.jsonl 0 times** — the mechanism has never fired in a real land |
| **`gate_admit` bounded load shedding** (ceiling 8, fail-OPEN) | ✅ on trunk | intended to damp the herd | Per-call 600 s budget **multiplies** across loops (F8). Bounds **LOAD but not CONCURRENCY** — N landers can all observe load<8 and start together; jitter spreads the herd, does not cap it (backlog `6767ec9bb425`). A worked counting-semaphore impl + 6 tests **exists but sits unlanded** on `wt-f8e40b4c577d` (`gate_slot_acquire`) — exactly **1 row in land.log carries `gate_slot`** |
| **Per-suite gate runner (Phase 1)** | ✅ `1bc02f6f` | Arithmetic: P(green\|n=126) 2.3% → **49.9%**, cost +3.0%. 60/60 tests | **§9: land success rate HALVED, 66% → 30%.** Doc's stated reason: it rewrote `run_bats_all` (FULL tier) while "all 64 of 64 post-Phase-1 lands ran scoped" — **✗ see §6.1**. Also **never applied to postland's call site** (`postland-verify.sh:504` still runs the monolith over 144 suites) |
| **In-gate flake exoneration** (failed FILE re-run, fresh TMPDIR, `--direct` carve-out) | ✅ (inside S2) | **24 `pass-on-retry` rescues LIVE**, all phase `land-gate` | R10 argued for always-RED; rejected with rationale (`GATE_RELIABILITY:437-447`). Ladder **cannot clear** a deterministic failure — it re-ran postland's suites 3× under the same wrong PATH and called the agreement "reproducible" (`GATE_ARCHITECTURE_PLAN.md:298-316`) |
| **`$HOME` isolation per gate (APFS clone, Phase 2a)** | ✅ `d9b934ee` | 32 MB in **1.48 s**, no space cost; effect-read `gate_home_setup` ×5 in both trunk and live `~/.claude` | Was a **precondition for the proof cache**, not a flake fix. Did not move the 0-green-stamp state (24 red stamps after it) |
| **Own-diff ratchet scoping** | ✅ `f5b1efed` | own-scope ×2 live | Filed *because* the tree-scoped ratchet was a fleet-wide hard stop (F9a) |
| **Wall-clock time-bomb lint** | ✅ `58e5bb97` | linked, selftest RC=0 | Reactive to `cc-relogin-status` detonating at 2026-07-27T00:00Z |
| **PATH normalization in postland** | ✅ `5abe5934` | Repro in 10 s; the 6 suites pass **147/0** with a session PATH | **Did not clear it.** A stamp **with** the fix (`873e646b`) still stamped red at load 8.18. Formally **RETRACTED** (backlog `10941179f8ec`, `19080082c195`). Desk then ruled the opposite direction — make suites PATH-hermetic, do NOT normalize (`c3dd374de94a`) |
| **Guaranteed-progress in-lock fallback** | ✅ (original CAS design) | Terminates; cannot be invalidated | Is itself F5 — held the machine-wide mutex 1,052 s / 35 min / max 6,771 s live |
| **`land-verify.sh` content-verify in code + stranded-sweep + land-lock** | ✅ 2026-07-11 train (`981c8ac`,`5a06905`,`9bdb31e`) | 11/11 bats; race sim reproduced the drop | Sweep exit 1 is the **normal state** on a multi-session box (any peer WIP trips it) ⇒ ownership is not machine-decidable — named THE blocker to autonomous landing (`p09-ship-land.md:122`, G-P9-5). Lock keying still per-worktree (F16) |
| **Serialize the gate** | ❌ REJECTED | 21 concurrent landers × 1,186–3,217 s = **7–19 h queue at k=1**, 2–6 h at k=3; most landers would exit 75, not queue | `GATE_ARCHITECTURE_PLAN.md:84` |
| **CI offload** | ❌ REJECTED | **37 of 126** suites need it2/iTerm/osascript/launchctl/GUI; 109 written against live `~/.claude`; GH macOS ≈ **5,700 min/day** at 10× billing; a self-hosted runner *is this box* | `:85`; `GATE_RELIABILITY:371` |
| **bats `--jobs` / shard parallelism** | ❌ BACKLOGGED | requires GNU parallel (absent; `-j` without it **executes 0 tests and only warns** — a silent no-op gate); realized speedup **1.7×, not 4×**; 4-shard makespan pinned at 10.5 min by `cc-reaper.bats` alone | `GATE_RELIABILITY:214-219`, `land-gate-serialization:85-88` |
| **Signal-based cut detection (`rc==137/143`)** | ❌ would have failed silently | bats runs under `pipefail` with `bats_test_count_validator` returning 1 on truncated TAP ⇒ **a SIGKILLed suite surfaces as plain `1`**, never 137/143 | `ROOT_CAUSE:264-270` |

---

## 4. DESIGNED, NOT BUILT (status as of now)

| Item | Design location | Status |
|---|---|---|
| **K3 — bound/split the `closure` clause** (depth bound, or direct/indirect split; `gate-select.sh --direct` primitive already exists) | `ROOT_CAUSE:300-330` | **Specified with numbers, NOT BUILT.** Explicitly ranked *below* K2 — the 55-suite gate landed successfully (`hold_s=161`), so closure breadth is "wasteful, not fatal" |
| **K4 — cap UNION-SCOPE re-gate** (3 options: interaction-set only / cap+defer / make it merely visible) | `ROOT_CAUSE:332-355` | **NOT BUILT** |
| **K5 — bound the in-lock gate** | `ROOT_CAUSE:357-359` | **NOT BUILT**, lowest priority |
| **Phase 2b — content-addressed per-suite proof cache** (key = `sha(suite ‖ transitive closure)`; 3 existing pieces need wiring: `gate-select.sh:228` `closure[s]`, `postland-verify.sh` `env_fingerprint()`+tree stamps, ship-land's tree stamps) | `GATE_ARCHITECTURE_PLAN.md:146-180` | **Precondition met (2a landed), still EMBARGOED** pending one real green stamp (§7). §9 adds: "the proof cache addresses none of these [deterministic blockers] … it must stop being described as the thing that unblocks landing" (`:457-459`) |
| **Phase 3 — hermeticity for ~20 hot cacheable suites** | `:204` | **After 2b.** WIP stash `herm-migration-wip` on `wt-1a941c28a079` |
| **Resumable/checkpointed gate (option 5)** | `GATE_RELIABILITY:374-376` | "HIGH VALUE, LATER" — deferred because the keystone was expected to remove most long gates |
| **AIMD concurrency window (Zuul), auto-revert, Chromium without-patch leg, `cc-reaper.bats` 4-way split, worktree-from-stamped-ref, nightly tree/drift split** | `GATE_RELIABILITY:502`, `:600-607` | **All backlogged** |
| **Gate concurrency semaphore** (`gate_slot_acquire`, RED-proofed, 6 tests) | branch `wt-f8e40b4c577d` | **BUILT, UNLANDED.** Constraint recorded: must be a **sibling** of the land-lock dir, never a child (`land-gate-cas.bats` asserts that dir's absence proves the lock path never ran) |
| **§9's revised program** (1. ratchet must not hard-stop a lander over a suite outside its diff; 2. lint forbidding absolute dates in fixtures; 3. deploy-parity existence leg; 4. **attribute-the-red logging on exit 6**) | `GATE_ARCHITECTURE_PLAN.md:467-473` | 2 and 3 LANDED (`58e5bb97`, `33e60df2`+`f94d9631`); 1 partially (`f5b1efed`); **4 NOT BUILT — `land.log` still records `exit` but never the failing suite**, confirmed live (field set: ts/repo/branch/sid/verify/sweep/esc_scan/exit/head/base/tree/gate_scope/selected_n) |
| **Session-ownership tagging + `stranded-sweep --mine`** (T-P9-4, "the crux that makes G3 liftable") | `p09-ship-land.md:138`, `:153-154` | **NOT BUILT.** Session-Id trailer convention is near-dead (4 of last 60 trunk commits, `GATE_RELIABILITY:69`) |
| **`land-lock` keying fix to `--git-common-dir`** (T-P9-1) | `p09-ship-land.md:135` | **NOT BUILT** — lock still keys per-worktree |
| **Declared `# gate-scope:` headers** (F7, declaration-over-inference) | `GATE_RELIABILITY:430-434` | Deferred to backlog; shipped as `gate-select.sh lint` instead |

---

## 5. POSTLAND-VERIFY — what it was for, and why it is not live

**Purpose.** It is the *enabling precondition* for scoped landing: the invariant swap trades "trunk is full-suite-green at every commit, proven pre-push" (I3-old) for "every trunk tree is full-suite-verified within ≤~28 min of landing, with bisected culprit + backlog remediation" (I3-new) plus "the live `~/.claude` layer only advances to a green-stamped tree" (I4) — `GATE_RELIABILITY:475-491`. Ranked **S1, "Build — precondition for S2's flip"** (`:497`). `ship-land.sh`'s `postland_net_live()` staleness guard is what makes a scoped land defensible at all.

**As built** (T3, `6fbfb1e`+`3629759`, 399 LOC + plist + activation script): 6 verbs (`--run-if-needed|--run|bisect|is-green|status|--selftest`); tree-keyed stamps `~/.claude/autonomy/postland/stamps/<tree>.json`; single-slot requeue-never-cancel; dedicated persistent worktree `~/Development/.worktrees/ci-postland`; retry ladder (re-run failed file alone ×2 in a fresh TMPDIR, convict at ≥2/3); bisect-before-page; state-keyed page filenames; `env_fingerprint()` (bats/cc/load). Later: `classify_hang` + bounds (`POSTLAND_SUITE_TIMEOUT_S` 2700 at `:125`, `POSTLAND_FILE_TIMEOUT_S` 300), rc-124-before-signal ladder ordering pinned by a mutation test (`GATE_RELIABILITY:309-357`). T4's 14-test suite was contract-first: 11/14 failed against a do-nothing stub, 14/14 on first contact with the real runner.

**Why it is not live — five independent reasons, all disk-verified:**

1. **Nothing schedules it.** `launchctl list | grep postland` → **NOT LOADED**. `com.claude.postland-verify.plist` (StartInterval 300, RunAtLoad false, Nice 10, LowPriorityIO) is one of **17 staged scripts in `docs/activation/pending-activation/`** (`09-postland-verify-activate.sh`). Activation is **C10 operator-only and classifier-blocked for agents**. `GATE_ARCHITECTURE_PLAN.md:344-347`: "A guard whose premise depends on a stamp nobody produces fails the same way whether the bug is fixed or not."
2. **No postland process is running now** (`pgrep -f postland-verify` → empty). RESTART-BRIEF §4 recorded pid 13755 parented to launchd surviving an iTerm restart — "but if it ever exits, nothing restarts it." It has exited.
3. **Zero green stamps, ever — 24/24 red, `last-green` absent.** So `deploy-live.sh` fail-closes: verbatim `deploy-live: REFUSED — no GREEN stamp among the newest 200 commits of origin/main — nothing is safe to deploy` (`ROOT_CAUSE:287-289`). Landing *and* deploying were blocked by the same misread.
4. **The staleness guard is inert by construction.** `postland_net_live()` counts only `"verdict":"green"` stamps and `[[ "$newest" -gt 0 ]] || return 0` (`ship-land.sh:238`) treats **zero green stamps as "net not adopted yet ⇒ trust"**. The two states — *never ran* and *runs constantly, always red* — are byte-identical as `newest_green == 0`, so **every scoped land on this box has landed on a premise that has never held** (`GATE_ARCHITECTURE_PLAN.md:210-233`).
5. **Its runner still runs the monolith.** `postland-verify.sh:504` = `bats tests/` over all 144 suites/2,307 tests, bounded 2700 s. Phase 1's per-suite runner was applied to ship-land only. By §1's law that is P(green) ≈ 1.5% per attempt on blast radius alone (`:341-343`). And it has **no run-wide admit cap** (`grep TOTAL_WAIT scripts/postland-verify.sh` → absent; its per-retry `gate_admit` is at `:364`).

**Root-cause status of the 0-green deadlock (newer than every doc read):** backlog `da18f179ac50` records **10 hypotheses eliminated with evidence** (test defects · interference · load · gitignored state · pollution · PATH · TMPDIR+nice · reused-vs-fresh worktree · kill-victim-by-exposure · ~/bin drift) and concludes "audit the VERDICT PATH, not the suites." Two live items then localize it: **`b4e49b4b5014`** — first reproduction, full 137 suites **in postland's OWN reused worktree = 2,242 ok / 1 not-ok**, the single failure being `test-hermeticity-lint` "selftest GREEN through a SYMLINK (the DEPLOYED `~/.claude` path)"; and **`b59eb997d035`** — clean-room 2,085 ok / 1 not-ok, the sole failure `test-hermeticity-lint.bats:22`, a **whole-tree assertion executed mid-full-suite** (passes standalone, fails in-suite). *"This is what has kept 14 consecutive stamps red and deploy-live fail-closed."* The other 6 convicted suites are spurious.

---

## 6. ADVERSARIAL PASS — doc claims that do NOT survive re-derivation

1. **✗ `GATE_ARCHITECTURE_PLAN.md:426` — "All 64 of 64 post-Phase-1 lands ran `gate_scope=scoped`, zero FULL runs."** `gate_scope` is **always** the literal string `"scoped"` on all 214 rows that carry it — it records the policy, not the tier. The tier field is `selected_n` (`ship-land.sh:153,726,862,867,873`: −1 = `run_bats_all`). In §9's own window (Phase-1 land → §9's commit `7d589e00` at 05:22Z) **21 of 48 rows carry `selected_n=−1`**; all-time it is **132 of 214**. Phase 1 did land on a path real traffic takes — §9's stated explanation for its failure is measurement error. §9's raw counts also don't reproduce: I get **257/153 (59%)** before and **48/21 (43%)** in-window, vs §9's 226/150 (66%) and 64/19 (30%). The *direction* (success rate roughly halving) reproduces; the magnitudes do not.
2. **⚠ The "FULL tier is 97% fatal" headline is 53% one branch.** `wt-1a941c28a079` contributes **71 of 132** FULL-tier rows (70 red / 1 land). Excluding it the FULL fail rate is **91% (56/61)** — the headline survives, but any per-attempt statistic over this log is a **retry-loop-weighted** statistic, not a per-change statistic. That branch's eventual land was itself **FULL tier**, and it landed **40 min after its last RED** (06:41:34Z red → 07:20:55Z exit 0), which weakens "landed on the first attempt of the first quiet window" (RESTART-BRIEF §1).
3. **✗ "K2 gave cuts a policy."** `exit:9` — the non-verdict code the whole CUT≠RED design terminates in — has been attested **zero times in 788 rows**, and `cut-not-red` has been written to `flakes.jsonl` **zero times**. Every gate failure on this box still reads as `exit 6` = RED. The discriminator is landed and tested but has produced no observable effect in production.
4. **✗ "load is the blockage" (RESTART-BRIEF §1) — half-refuted by its own §6**, and the refutation is on origin/main: the decisive post-repair stamp graded **current trunk at load 9.34** and convicted **the same six suites**. Load explains the LANDS (37 REDs → landed at load 9); it does **not** explain the 0-green-stamp deadlock. The residual cell — full corpus × reused `ci-postland` worktree — has since been reproduced (`b4e49b4b5014`) and localized to one whole-tree assertion (`b59eb997d035`), i.e. **neither load nor PATH**.
5. **⚠ Every corpus-size constant in the models is stale.** The q-law was fitted at n=126; the corpus is now **144 suites / 2,307 tests** and grew ~14% in ~36 h. Any P(green) figure quoted from the plan is optimistic by construction, and `q` has never been re-fitted against the per-suite runner's live outcomes.
6. **⚠ Both `exit:143` rows come from `land-lock.sh`'s EXIT trap, not ship-land** — ship-land installs no signal trap and passes only hardcoded literals to `attest_land`, so **it can never record its own signal death** (`ROOT_CAUSE:21`). The 20–53 min unlocked gate, where suites actually run, is **entirely unobserved by the telemetry**. Any peer-kill rate derived from `land.log` is a floor of unknown tightness.

---

## 7. NAMED BLOCKERS / UNCERTAINTIES

- **`land.log` records no failing suite on exit 6** — 151 attested REDs are unattributable cause-by-cause. `GATE_ARCHITECTURE_PLAN.md:461-465` calls this "the same blindness §1 was written to escape" and names it the cheapest next measurement. Still unbuilt.
- **`land.log` is live** — it grew 430→437 rows mid-session for the root-cause doc, and 788 for me. Every exact count is a snapshot.
- **`gate-select` DIRECT edges come from PROSE mentions, not functional dependency** — a comment citing a script path makes an unrelated suite "changed" (backlog `a71df503c6f1`).
- **Landing state now:** 82 open / 23 blocked backlog items; 49 worktrees; shared checkout 2 commits behind origin/main; `deploy-parity-assert.sh` RC=0; **`7edc3b5b` (+118/−10, 5 files) sits committed on the shared checkout's `main` and NOT on origin/main — the exact 2026-07-11 drop shape**, protected on `rescue/shared-checkout-accounts-7edc3b5b` (backlog `91a29f4806fe`).
- **F7 (admit-ceiling self-starvation) is explicitly an untested hypothesis.** Its own memory note records the method trap: `pgrep -f ship-land.sh` matches a *claude session whose prompt mentions the script* — resolve gates by `lsof -d cwd`, not argv.
- **The killer's identity is a STRONG LEAD, not proven**: every SIGKILL targets `tests/cc-reaper.bats`, load-correlation is inverted, and `cc-teardown:345-353` runs a TERM→KILL ladder on a timer — but nobody has caught the ladder against a bats PID (`ROOT_CAUSE:128-167`). The decisive probe (log every TERMed PID's argv for an hour, grep for `bats`) has not been run.