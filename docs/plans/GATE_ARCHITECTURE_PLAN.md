---
status: in-progress
---

# Landing-gate architecture — the plan

## Phase 0 — orchestration

**Phase 1 is deliberately NOT an Agent-Team task: it is a single-function change in one file
(`scripts/ship-land.sh::run_bats_all`) plus its own suite.** Splitting it across teammates would
add merge surface to the one change that must land first and cannot itself rely on a healthy gate.
Driven solo, on `fix/gate-per-suite-keystone`, landed via the project-local `/ship`.

Phase 2 IS a 2+ code-writing-task wave and takes a team when it starts:

| Teammate | Deliverable | Worktree | blockedBy |
|---|---|---|---|
| `gate-home-iso` | per-gate APFS-cloned `$HOME` (`cp -Rc`) + its bats suite | `wt-gate-home-iso` | Phase 1 landed |
| `gate-proof-cache` | content-addressed per-suite proof cache: join `gate-select.sh:228` `closure[s]` to the tree-keyed stamps | `wt-gate-proof-cache` | `gate-home-iso` (isolation is a correctness precondition, §4) |
| `gate-hermetic-hot` | fixture the ~20 hot cacheable suites via the existing lint ratchet | `wt-gate-hermetic-hot` | none (parallel) |

Spawn wave: `gate-home-iso` + `gate-hermetic-hot` together; `gate-proof-cache` after
`gate-home-iso` lands. **Never ship the cache before isolation** — §4 "honest coupling".


**Provenance.** Distilled from a 30-agent Fable-5 + Opus-5 Dynamic Workflow
(`gate-rootcause-keystone`, run `wf_cee941c9-9b8`, 2026-07-25 23:53 → 2026-07-26 01:35), which
adjudicated four filed root causes under adversarial default-to-refute verification. The run
completed; its carrier session was re-tasked 84 s later and the findings sat unread in
`/private/tmp` scratch until recovered on 2026-07-26. Full agent output:
`~/RECOVERED-workflow-wf_cee941c9-9b8/FINDINGS.md` (499 KB) · patch: `scratchpad/KEYSTONE.patch`
· evidence: `scratchpad/EVIDENCE.md`, `branch_census.tsv`.

This document exists because that research was nearly lost twice. **Read this before proposing any
further gate fix** — three of the four intuitively-obvious fixes are measured losers.

---

## 1. The governing law

    P(gate green) = (1 - q)^n        q = 2.94% per suite,  n = suites in the run

MLE over all 55 real gate runs carrying a suite count (`~/.claude/land.log`,
2026-07-26T00:09:49Z → 08:34:06Z). A single per-suite independent hazard reproduces the entire
curve — n=1 → 2/2 green, n=126 → 1/39 green — and is **5.0 × 10⁵ times more likely** than a
constant per-run model (2·ΔlogL = 26.3).

**Therefore `n` is the lever. `q` is second-order.** Every fix must be judged by which one it moves.

| n (suites) | P(green) |
|---:|---:|
| 1 | 97.1% |
| 3 | 91.4% |
| 55 | 19.4% |
| 126 | **2.3%** |

A 126-suite FULL gate was never "flaky". It was arithmetically near-impossible, and it stayed that
way through every contention fix applied to it.

---

## 2. What is REFUTED — do not re-litigate

**Hermeticity is not the cause.** The 109-of-126 unfixtured figure is real
(`scripts/test-hermeticity-lint.sh`), but three independent measurements kill it as the driver:

- **No enrichment.** Of 13 suites observed genuinely failing, 9 are non-hermetic = 69%, *below* the
  86.5% base rate (P(X≤9 | neutral) = 0.087). Causation would predict ~13/13. We see depletion.
- **A hermetic suite failed reproducibly.** `tests/desk-recycle-durable.bats` fixtures `$HOME` at
  line 19 and was still among the 6 postland declared failing.
- **Wrong failure shape.** Across 6 full-gate transcripts: **7,283 `ok`, 3 `not ok`, 15 kill-lines**
  — 83% kills. Shared-state collision produces `not ok`, never SIGKILL.
- **Ceiling arithmetic.** Eliminating 100% of `not ok` flakes moves q 2.94% → 2.44% and
  P(green|FULL) **2.3% → 4.4%**. A 2-point gain on a 97-point problem, for a ~109-file change that
  cannot itself land.

**Hermeticity is relocated, not discarded:** it is the *precondition* for caching and offload
(§4), not a flake fix. Fix ~20 hot cacheable suites, not all 109.

**Also rejected, with measurements:**

| Option | Why it loses |
|---|---|
| Serialize the gate (one land at a time) | 21 concurrent landers × 1186–3217 s suite = **7–19 h queue** at k=1, 2–6 h at k=3. `land-lock.sh:62` caps waits at 3600 s then exits 75, so most landers would *fail*, not queue. Rations concurrency without reducing cost. |
| Offload to CI | **37 of 126** suites need `it2`/`iTerm`/`osascript`/`launchctl`/GUI and cannot run headless; 109 are written against a live `~/.claude`. GH macOS bills 10× ≈ 5,700 min/day. A self-hosted runner *is this box*. |
| More selector scoping | Its biggest lever already landed (`19a2cfe`). Replaying 48 real land ranges through the NEW selector still yields FULL 30/48; 6 of 18 scoped ranges select 55–76 suites. **≈75% of real lands still run ≥55 suites.** Scoping has hit its correctness floor — the remaining FULL triggers are *right* to fail closed. |
| CUT-aware `run_bats_all` alone (landed `c605a2e`) | A **labelling** change, not a landing change. Converts 33 false REDs into 33 *undecidables* with no policy, leaving P(green\|FULL) at 2.6%. Necessary, not sufficient. |

---

## 3. Phase 1 — the per-suite runner (do this first)

**Change:** `run_bats_all` hands all 126 files to ONE `bats-exec-suite` process, so a kill at suite
120 loses all 126. `run_scoped_suite` (`ship-land.sh:252-283`) is already per-file, already captures
the kill signature, already exonerates via one fresh-TMPDIR re-run, already writes `flakes.jsonl`,
already carves out DIRECT suites. **Delete the monolith's body; loop `run_scoped_suite` over
`tests/*.bats`.**

- Measured retry-failure rate: 2 "failed twice" vs 10 retries that passed = 17% ⇒ **q_eff = 0.49%**
- **P(green | n=126): 2.3% → 49.9% — a 21.5× improvement**
- Cost: **+3.0% wall time** (bats startup 0.46 s × 126 = 58 s on a 1957 s run, timed at load 93)
- `GATE_EFFECTIVE_FULL` is a separate flag from the runner (`:114`, `:288`), so the **full-suite
  claim survives intact** — same suites, same verdict rule, smaller blast radius.
- Ships with kill switch `SHIP_LAND_FULL_PER_SUITE=off` restoring the monolith. Deliberately an env
  flag, not a revert: **a revert would itself need the gate**, and the bootstrap deadlock is exactly
  what we are escaping.

Compose with what already landed — do not replace it: `c605a2e` (CUT ≠ RED, TAP-body verdict) and
`gate_admit` (bounded fail-OPEN load shedding) are both on trunk and both stay.

---

## 4. Phase 2 — content-addressed per-suite proof cache (the durable architecture)

**PICK (panel verdict): the resumable/checkpointed gate.** It is the only option that reduces
per-lander **work** rather than rationing **concurrency**, so it is the only one that preserves the
2026-07-25 unlocked-parallel design.

> The defect is that doubt about *selection* is currently paid as re-running the *proof*. A proof
> cache separates them: the selector may keep shouting FULL, and FULL then costs only the suites
> whose content actually changed.

**Key** = `sha(suite content ‖ transitive closure content)` → green.

**Nothing new needs inventing — three existing pieces need wiring:**
1. `scripts/gate-select.sh:228` already computes `closure[s]` (fixpoint transitive input set per suite)
2. `scripts/postland-verify.sh` already has `env_fingerprint()` + tree-keyed stamps at `$STAMPS/$tree.json`
3. `ship-land.sh` already writes tree-keyed stamps

**Measured payoff:** over the last 40 trunk commits, suites whose closure intersects a commit are
**median 1, mean 25.4, max 70 of 126** — a median **125 of 126 suites are provably unaffected and
cache-reusable**. Today's 57 gate runs shared only 15 distinct bases across 43 trees:
suite-executions **5,394 → ~986 (5.5×)**.

**Three properties only this option buys:**
1. **CUT ≠ RED becomes structural.** A killed suite writes no cache entry ⇒ UNPROVEN. It can never
   be RED and never a false green — strictly stronger than the TAP-body heuristic.
2. **Cost is sublinear in landers.** Overlapping trees each pay only for what others have not proven.
   Parallelism stops being the enemy.
3. **Every wasted run becomes an asset.** The 7 RED full-suite runs (20–53 min) that produced pure
   load would instead pre-prove ~125/126 suites for the next lander.

**HONEST COUPLING — do not ship the cache alone.** With 109/126 suites reading and writing the live
`~/.claude` while ~40 sessions mutate it, a cached GREEN can be a *durable* false green. Per-gate
`$HOME` isolation is a **precondition**, and it is cheap: `cp -Rc ~/.claude/autonomy <dest>` (APFS
clonefile) copied **32 MB in 1.48 s** with no space cost. It independently dissolves `2f71dded07f2`.

---

## 5. What the 2026-07-25 design got right (keep it)

The machine-wide mutex must protect the **CAS on the trunk tip, not the proof**. Measured:
splitting the gate out of the lock (`190c839`, then the optimistic-round loop at
`ship-land.sh:653-666`) collapsed median lock hold **298 s → 1 s** (n=198 pre-split vs 75
post-split). The `exit 42` stale-gate re-round (`:441` → consumed at `:662`) is textbook optimistic
concurrency control. **Do not rebuild serialization** — `ee453a792903` is filed on the pre-split
design being the defect, and its premise is stale.

---

## 6. Sequence

| Phase | Change | Moves | Status |
|---|---|---|---|
| 0 | CUT ≠ RED (TAP-body verdict) | labelling | **LANDED** `c605a2e` |
| 0 | `gate_admit` bounded load shedding | q | **LANDED** |
| 0 | selector: added file runs same clauses | n (7→3 FULL of 40) | **LANDED** `19a2cfe` |
| **1** | **per-suite runner** | **n: P 2.3% → 49.9%** | **THIS PLAN** |
| 2 | `$HOME` isolation per gate (APFS clone) | precondition | next |
| 2 | content-addressed proof cache | work: 5.5× fewer executions | next |
| 3 | hermeticity for ~20 hot cacheable suites | enables caching | after |

Judge every future proposal against §1: **does it reduce `n`, or is it another `q` fix?**
