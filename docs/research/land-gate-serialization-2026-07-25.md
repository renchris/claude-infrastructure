# Land-gate serialization — gate outside the lock (2026-07-25)

**Status: LANDED on trunk** — fix + RED-proof suite `190c839`, this doc + ship.md prose
`efd54bb` (worktree commits `2f91866`/`6804a8a`, SHAs rewritten by the dogfood land's own
round-2 rebase). Brief filed by the shutdown-hardening session (2026-07-25) after hitting the
pathology first-hand; forensics in `docs/research/session-crash-forensics-2026-07-23.md`
§ 2026-07-25.

## Problem

`scripts/ship-land.sh` ran the **entire gate** (shellcheck + ~100-file bats suite + `bash -n` +
`py_compile`, ~10–20 min) **inside** the machine-wide landing lock (`scripts/land-lock.sh`, keyed
on the shared git dir so every worktree serializes). N concurrent landers therefore serialized at
~N × suite-time. Observed live: a land queued **~40 min** while `origin/main` advanced
`0098a41 → 6494f41 → 7791209 → 7acffb8` (four sibling lands ahead of it), with the 60-min
`LAND_LOCK_WAIT` ceiling looming — starvation by architecture, not by any buggy line.

Root cause: **the lock protected far more than its critical section.** It exists to close the
2026-07-11 rebase→push race (incident `dfacccd`: a sibling moved `origin/main` between one
session's rebase and push, silently dropping a commit past a `rev-list --count == 0` check). That
race window is fetch → rebase → push → content-verify. The gate merely proves a tree green — it
needs no mutual exclusion.

## Chosen design — optimistic CAS landing (brief's option A, refined)

**Invariant: the GATE proves the FINAL rebased tree green; the LOCK covers ONLY the race window
(fetch-compare → push → content-verify).**

Up to `SHIP_LAND_GATE_ROUNDS` (default 3) optimistic rounds:

1. **Unlocked** (parallel across sessions): `git fetch` → `git rebase origin/<trunk>` → **full
   gate** on the rebased tree → record the exact gated pair `(GATE_BASE = origin/<trunk>,
   GATE_HEAD = HEAD)`. `--dry-run` stops here — a dry run never takes the lock at all.
2. **Locked** (seconds): last-moment `git fetch` → **CAS check**: `origin/<trunk> == GATE_BASE`
   AND `HEAD == GATE_HEAD`?
   - **Yes** → the gated tree IS the pushed tree, byte-for-byte. Push → `land-verify.sh`
     content-verify (still in-lock, after the push) → stranded-sweep → attest.
   - **No** (a sibling landed mid-gate) → exit 42 (internal stale-gate code), **release the
     lock**, loop: re-rebase + re-gate the new final tree unlocked. The re-gate fires **iff**
     origin moved in the window.
3. **Rounds exhausted** (sustained contention — every unlocked gate invalidated): guaranteed-
   progress fallback = rebase + full gate **inside** the lock (the pre-fix behavior). A held
   mutex stops further pipeline movement, so this round cannot be invalidated and the pipeline
   terminates. `SHIP_LAND_GATE_ROUNDS=0` is the kill switch back to exactly this pre-fix
   behavior.

The T-P9-7 verify-fail bounded auto-retry loop (re-fetch + rebase + re-gate + re-push on a
content drop) is unchanged and stays in-lock: it is the rare incident-recovery path against
**non-pipeline** trunk movers, whom the lock cannot exclude anyway.

### Why the stale path re-runs the FULL gate (the brief's "delta re-gate scoping" question)

green(our tree on old base) + green(sibling's landed tree) does **not** imply green(our commits
rebased onto theirs): semantic conflicts require no file overlap. And a changed-path test→source
map is not conservatively sufficient in this repo — bats tests read prose too (several suites
assert on `.md` content), so even a docs-only sibling delta can flip a test. The only provably
sufficient re-check of the final tree is the full gate. The fix is therefore **where** the gate
runs (unlocked, parallel), never **whether** — no soundness-by-mapping bet anywhere.

### Correctness proof sketch

- **Green trunk:** a push happens only in two shapes: (fast path) under the lock with
  `origin/<trunk> == GATE_BASE ∧ HEAD == GATE_HEAD`, i.e. the pushed tree is bit-identical to
  the tree the full gate proved green on exactly that base; or (fallback/retry path) after a
  full in-lock gate of the rebased tree. Either way the pushed tree was fully gated — the
  pre-fix invariant, preserved exactly.
- **No silent drop (2026-07-11 guarantee):** pipeline siblings cannot move `origin/<trunk>`
  between the in-lock fetch-compare and the push (mutex). Non-pipeline movers are caught exactly
  as before: non-ff rejection (exit 7) or post-push in-lock content-verify + bounded auto-retry
  (exit 8 on exhaustion), plus stranded-sweep. Content-verify never left the lock.
- **Termination/progress:** each optimistic round either lands, fails loud (2/5/6/7/8), or
  exits 42; 42 can occur at most `SHIP_LAND_GATE_ROUNDS` times before the in-lock fallback,
  which cannot be invalidated. Starvation among fallback landers is bounded by the existing
  `LAND_LOCK_WAIT` queue — now against seconds-scale holds instead of suite-scale ones.
- **Fail-closed preserved:** exit codes 0/2–8 keep their contract (42 is internal and never
  escapes ship-land; land-lock's 75 propagates as before); never `--no-verify`; never force;
  backup ref `ship/backup-*` written in preflight, before any lock.

## Rejected alternatives

- **B — changed-file-scoped gate (test→source map):** unsound here (tests read docs; semantic
  coupling is unmapped); any conservative map degenerates to "run everything". Rejected rather
  than backstopped-nightly — a gate that is only *probably* sufficient re-opens the class of
  silent breakage this pipeline exists to kill.
- **C — `bats --jobs` parallelization:** bats 1.13 requires GNU parallel (or rush), not
  installed on this box; and the ~113 suites have not been audited for parallel-safety (shared
  `/tmp`/HOME mutations would flake the one gate every land depends on). Orthogonal and
  stackable later behind an opt-in env after a parallel-safety audit; not part of this fix.
  Per-suite memoization keyed on tree hashes only helps re-running an identical tree — a rebase
  onto a moved trunk always changes the tree, so it buys nothing on the stale path.
- **D — two-phase lock (intent lock for push only):** the rebase must sit in the same critical
  section as the push or the 2026-07-11 race reopens; with the CAS design the "rebase" inside
  the lock is the degenerate check *that no rebase is needed* — same effect, no second lock.

## Proof artifacts (RED-proofed, durable products)

`tests/land-gate-cas.bats` — 8 tests; **6 fail against the pre-fix pipeline** (run verified on
`d263977`), the other 2 (kill-switch ≡ pre-fix semantics; the no-drop invariant, which held
before too) pass on both by design. Instrumentation: a PATH-shimmed `shellcheck` records
LOCKED/UNLOCKED per gate invocation (mutex-dir existence at run time — a durable product per
run), and doubles as a deterministic race injector landing sibling commits onto origin exactly
inside the gate→lock window:

- CAS fast path: origin unmoved → exactly 1 gate run, UNLOCKED; land content-verified.
- Stale gate: sibling lands mid-gate → CAS detects, re-gates UNLOCKED; **both** contents intact
  on trunk (no drop, either side).
- The iff: unmoved → 1 gate run; moved → 2. Both directions in one test.
- Rounds exhausted (sibling lands during *every* unlocked gate): observer reads
  UNLOCKED·UNLOCKED·LOCKED — the fallback terminates and lands all content.
- Kill switch `SHIP_LAND_GATE_ROUNDS=0`: gate runs IN-LOCK (pre-fix behavior reachable).
- Dry-run: gate UNLOCKED and the mutex dir is never created.
- Hold-time collapse: 3s gate stub ⇒ logged `hold_s ≤ 2` (pre-fix: ≥ 3).
- True concurrency: two real ship-land processes race on one mutex with overlapping 2s gates —
  both exit 0, both files content-identical on trunk, 2× `verify:ok` in land.log.

## Benchmark — lock-hold collapse (4 simultaneous landers, 6s synthetic gate)

Same fixture both sides (bare origin, 4 clones, distinct files, shellcheck stubbed to 6s;
land-lock telemetry is the measurement). Old = `d263977`, new = `2f91866`. All 8 lands green,
all content verified on trunk.

| metric | old (gate in-lock) | new (CAS) |
|---|---|---|
| per-land lock hold | 6–11 s (≈ gate) | **0–1 s** (+ one 6 s fallback hold, see below) |
| max queue wait | 28 s | **6 s** |
| total lock occupancy | 29 s | **8 s** |
| makespan (worst lander) | 36 s | 34 s |

The one 6s hold in the new column is the 4th lander exhausting its 3 optimistic rounds under
*perfectly simultaneous* maximum contention — the bounded fallback doing its job. Scaling the
6s stub to the real ~15-min suite: the old max queue wait ≈ 3 × suite ≈ 45 min (this is the
observed 40-min live queue); the new wait is a few seconds, because waits now queue behind
seconds-scale CAS holds, not suite-scale gate holds. Contention analysis: any single lander
needs ≤ `ROUNDS+1` gate executions (so for N > ROUNDS+1 simultaneous landers the *worst*
lander is strictly better than the old N × suite queue), gates run CPU-parallel across
sessions, and in the common case (arrivals spread wider than one suite-duration) the
serialization tax is zero — the lock is held for the seconds the push+verify actually need.
Bench harness: session scratchpad `bench-land-gate.sh` (fixture recipe reproduced in
`tests/land-gate-cas.bats`'s shim pattern).

## Live dogfood trace (2026-07-25, the fix landing itself)

The fix landed **via the pipeline it fixes**, under real concurrency with a sibling session
(`fix/desk-invariant-headless-respawn`) still landing on the **old** code — the worst
transition-period topology (an old-style lander holds the lock through its entire suite).
From this session's land output + `land.log` telemetry:

- **Round 1:** full gate ran unlocked, in parallel with the sibling's in-lock gate (pre-fix,
  this session would have queued behind it for the whole suite before even starting its own).
  CAS child then queued 231 s for the mutex (the sibling's old-style hold); on acquire it read
  the trunk moved (`893cd58 → e34ab65` — the sibling had landed) and released with
  **`hold_s: 0`, exit 42**.
- **Round 2:** re-gated the new final tree unlocked (full suite); CAS acquired with **no
  wait**, held **14 s** total for push + content-verify + stranded-sweep (277 branches), and
  landed `190c839` + `efd54bb`, `verify: ok`.

Both stale-detection (zero-hold release) and the fast path (14 s hold) exercised live on the
first production land; the 231 s queue was behind an old-code holder — the last such queue,
since every subsequent lander picks the fix up from trunk.

## Follow-on surfaced by concurrent gating (fixed same-day)

The first post-fix land attempt went gate-RED on a **pre-existing** sporadic flake that the old
serialization had been masking by rarely running suites under load: `lead-supervisor.sh`'s
STALL? branch called `resolve_page` in the same sweep that created the page, so with
integer-second stamps a page born at X.99s read as deadline-elapsed at X+1.00s
(fixture deadline 1s) ⇒ phantom same-sweep ESCALATE ⇒ a 2-notify count the e2e asserts
against. Concurrent unlocked gates raise machine load and suite-run frequency, so this class
of load-sensitive test flake now surfaces more — each is a real defect to fix at root
(same-sweep guard + deterministic T22b forcing the race via `CC_SUP_PAGE_DEADLINE_S=0`),
never to retry past.

## Operational notes

- `LAND_LOCK_WAIT`/`LAND_LOCK_TTL` semantics unchanged; the TTL's never-reap-a-live-holder rule
  still applies to the (now rare, still legitimate) long in-lock fallback hold.
- land.log now shows exit-42 acquisitions (hold ≈ 0) for invalidated rounds — expected
  telemetry, not failures.
- `~/.claude` deploys via the trunk fast-forward as usual; no consumer of `ship-land.sh`
  changes shape (`desk-land.sh`, `handoff-fire.sh land` pass through the same CLI + exit
  codes; `hooks/ship-rail-push-allow.sh` matches Bash-tool push shapes, and ship-land's push
  remains a subprocess).
