# Land-gate serialization — gate outside the lock (2026-07-25)

**Status: LANDED on trunk** — fix + RED-proof suite `190c839`, this doc + ship.md prose
`efd54bb` (worktree commits `2f91866`/`6804a8a`, SHAs rewritten by the dogfood land's own
round-2 rebase). Brief filed by the shutdown-hardening session (2026-07-25) after hitting the
pathology first-hand; forensics in `docs/research/session-crash-forensics-2026-07-23.md`
§ 2026-07-25.

> ⚠️ **SUPERSEDED IN PART — read the last section first.** This fix moved the gate out of the lock,
> which traded a queueing cost for a *concurrency* cost (N landers = N unlocked corpora), filed as
> backlog `77738605376f`. That item is now **resolved by the v2 fast lane (`492c5106`)**, which
> removed the corpus from the land entirely — so the "gate-concurrency cap / queue" this document's
> follow-on asked for is respectively unnecessary and **forbidden**. See
> § *Resolution of the follow-on THIS design created* at the end.

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

---

# Resolution of the follow-on THIS design created — backlog `77738605376f` (2026-07-30)

**This fix created its own successor problem, and that successor is now closed — by none of the
three remedies it asked for.** Moving the gate out of the lock (above) converted a *queueing* cost
into a *concurrency* cost: with the corpus unlocked by design, N simultaneous landers ran N full
corpora. Item `77738605376f` filed that on 2026-07-26 and prescribed "a gate-concurrency cap /
queue / changed-path test selection". Two days later the **v2 fast lane** (`492c5106`, 2026-07-28)
deleted the premise instead: **a land no longer runs a corpus at all**, so there is no N-way
multiplication left to cap.

Read this section before acting on the item's title. Anyone starting from that title alone will
design a cap for a pathology that no longer exists, and one of its three prescribed remedies is
now *forbidden by design*.

## The premise was real, and it rotted

The original measurement was sound — it is preserved in the `block` records of `9c5d0ba74e79` and
`2d36e63d16a2`: ~10-12 concurrent full corpora, load 17-20, swap 2.5 G of 4 G with 546,696
pageouts, and gates dying at arbitrary test counts (68 / 438 / 1581 / 561) with no `pkill` anywhere
in the repo — i.e. memory-pressure termination, not test failure. Six ship-land attempts in one
worktree and four in another all failed to land; no session landed anything for hours.

What rotted is the *prescription*, not the observation. Today the same topology cannot arise:

| the item's remedy | disposition today | why |
|---|---|---|
| gate-concurrency **cap** | **unnecessary** | nothing in a land is unbounded any more, so there is no quantity left to cap. The one component that still runs a corpus — the post-land verifier — is already a mutex-guarded **singleton** (`postland-verify.sh`, `run.lock.d`), i.e. a cap of exactly 1. |
| **queue** | **🚨 FORBIDDEN** | waiting *is* the amplifier. `gate_admit` was precisely this queue and it is deleted, not tuned (`ship-land.sh:466-485`): five concurrent gates once sat at load 16-18 waiting for a ceiling of 8 **while their own corpora were the load** — self-starvation below their own threshold. Every waiter that timed out then ran the corpus anyway, so the wait bought nothing but latency. Re-adding a queue re-adds the deadlock. |
| **changed-path test selection** | **shipped** — and made sound | `gate-select.sh --direct` picks the suites of *this diff*. §"Rejected alternatives B" above rejected this as unsound, and that reasoning still holds **for a gate that must be conservatively sufficient**. v2 escapes it by changing what the selection is *for*: it feeds a best-effort **smoke**, never a proof, and the whole-tree proof moved to the verifier. Selection unsoundness can therefore no longer reach trunk — the soundness bet §B refused to take is still not taken. |

## What a land costs now (structural, every path bounded)

`run_gate` (`ship-land.sh:980`) in the default `fast` lane:

1. **statics — O(diff), not O(tree):** `shellcheck` + `bash -n` on the shell files in
   `git diff --name-only <range>`, `py_compile` on the python ones (`:997-1007`).
2. **four ratchets — seconds each, scope-independent:** hermeticity, wall-clock time-bomb, UTC
   timestamp-contract, and `.bats` shellcheck (`test-hermeticity-lint.sh`,
   `test-walltime-lint.sh`, `utc-stamp-lint.sh`, `bats-shellcheck-lint.sh`; `:1009` onward). Each
   greps `tests/` and *names the offending file to the session that wrote it*, binding on that
   land's own diff.
3. **the smoke — the only test work, and every exit from it is bounded** (`:780-861`):

| condition | behaviour | cost |
|---|---|---|
| `IN_LAND_LOCK=1` | statics + ratchets only — **structural**, checked at the one place a suite could start, so no call site can forget it | 0 |
| selector missing / answers `FULL` | no smoke (`FULL` is the selector's "cannot decide"; in v2 it can no longer mean "run everything") | 0 |
| 0 direct suites map to the range | lint-only land | 0 |
| 1-min load ≥ `CC_GATE_MAX_LOAD` (8) | **SKIPPED entirely — never waited** | 0 |
| otherwise | direct suites minus host-manifest suites, one `nice`d process each, serial, **one total wall budget** `SHIP_LAND_SMOKE_BUDGET_S` (120 s), deadline re-checked before each suite | **≤120 s** |

A named `not ok` in a direct suite blocks (exit 6 — a verdict about your diff). A cut or budget kill
**proceeds** (attested `smoke:"partial"`) — a non-verdict must never block a land. `GATE_EFFECTIVE_FULL`
is pinned to 0 in *both* lanes, so a land makes no full-suite claim and the verifier stays the sole
writer of gate-green.

**The amplifier is broken at the root:** the shed is a pure predicate, so a gate starting under
fleet load contributes *no* test load. More landers can no longer produce more load — the feedback
term the 2026-07-26 runaway depended on is gone.

## Verified 2026-07-30 (live, under exactly the condition the item describes)

Measured on the 10-core / 64 GiB box at load **37-57** — 4.6-7× the shed ceiling, i.e. the wave
condition, not a quiet-box rehearsal:

- **A real land's gate completed GREEN in 29 s at 1-min load 56.75.** This document's own land is
  the trace: `./scripts/ship-land.sh --dry-run` → fetch + rebase onto `origin/main` + full fast-lane
  gate + `gate GREEN`, `rc=0`, wall **29 s**, no lock taken. That is the item's own failure condition
  (it reported "cannot complete" at load 17-20) at **3× that load**, completing in under half a
  minute. Path taken: four ratchets clean over 205 suites, then `smoke — 0 direct suite(s) map to
  this range (lint-only land)`.
- **Corpus today: 205 suites / 3348 tests** — the item's "~1751 tests" has since **roughly doubled**,
  so the v1 pathology would be materially worse now than when it was measured. The fix removed the
  corpus from the land rather than tuning around it, so this growth costs a land nothing.
- **Selection is O(diff):** direct-suite selection over the last five real lands →
  **0, 0, 0, 3, 0 suites of 204**.
- **Zero of the 9 bats suites live on the box were land gates** — all were other sessions' single-suite
  runs, resolved by `cwd` (`lsof -d cwd`), not by argv. `pgrep -f ship-land.sh` matched only session
  *briefs*, never a gate: argv carries whole prompts, so it over-counts by design.
- **The verifier is alive and single-flight:** stamps advancing (newest minutes old), background QoS
  band, fresh worktree per run, `run.lock.d` mutex in the `land-lock.sh` shape.
- The properties above are **test-enforced**, not merely documented: the in-lock bats ban in both
  lanes (`land-gate-cas.bats:214,259`, `ship-land.bats:1678`), the smoke budget
  (`ship-land.bats:1033,1054`), the shed predicate incl. malformed-ceiling fail-open
  (`ship-land.bats:1080-1126`), and `GATE_EFFECTIVE_FULL=0` (`ship-land.bats:422`).

## Where the load went, and what is tracked elsewhere

The corpus did not vanish — it moved to the singleton verifier, and **that is where the remaining
difficulty now lives**. Do not re-file it here; it is extensively tracked already. At the time of
writing the verifier's recent stamps read `verdict:"red"` with `failing:["tests/"]` at loads 47-61 —
a *non-specific* failure, which is the cut-misread-as-red signature (a real red always names a test),
already covered by `d1ba434f6239` and its refinement `8b90c69e0edd` (a gate has **four** terminal
states — GREEN / RED / KILLED / HUNG). Related open items: `e3229172d3a0`, `a49a6a4541f1`,
`cde699d09fa8`, `cc89fc8dc765`, `36ed9b03e47a`, `62599dd76a60`, `168cfdfda0b5`, and
`60ec4c2d86d4` (port a run-wide admit cap to the verifier, where a per-call bound multiplies across
the retry ladder).

One consequence of the shed deserves naming because it is easy to read as a regression and is
**by design**: under normal fleet load the smoke skips, so a land runs *no* bats at all. Anything
that assumed the land gate would execute a suite is therefore not being enforced there — filed
separately as `e38d68f0c3c2` (the `bats-assert-liveness` ratchet had not been enforcing; trunk
carried 25 dead assertions).

## The cap WAS built, and it must NOT be landed — `refs/proposals/gate-slot-semaphore`

The remedy this item asked for exists as finished, tested code. **Do not land it, and do not rebuild
it.** `refs/proposals/gate-slot-semaphore` = `3d052701` (2026-07-26, UNLANDED, reachable from no
branch head; 602 insertions over 5 files, incl. 231 lines of tests) adds `gate_slot_acquire`: a
machine-wide **counting semaphore** keyed on the same shared git dir as `land-lock`, capping
concurrent gates at `SHIP_LAND_GATE_SLOTS` (default `cores/3`, floor 2 — **3 slots** on this 10-core
box), the slot held *only* across the unlocked gate, fail-open after `SHIP_LAND_GATE_SLOT_WAIT`
(**2700 s**) with `gate_wait_s`/`gate_slot` telemetry and a `SHIP_LAND_GATE_SLOTS=0` kill switch.

It is careful work and it was the right design **for the tree it was written against** — its own
sizing comment says so: *"5-9 gates ⇒ load 20-31, peak 96; `cores/3` keeps the …"*, i.e. calibrated
against **full-corpus** gates. `492c5106` removed that subject two days later, and the arithmetic
inverts:

- **It would queue 45 minutes to protect 29 seconds.** The thing being admitted is no longer a
  20-53 min corpus; it is statics + ratchets + a shed-able ≤120 s smoke — measured at **29 s** above.
  A 3-slot gate with a 2700 s wait bound is a queue whose wait dwarfs its work by ~90×.
- **Fail-open makes it buy latency, not protection.** After 2700 s the land "proceeds unadmitted" —
  so under exactly the sustained contention it exists for, it *still* does the uncapped thing, having
  first spent 45 minutes. That is verbatim the critique that killed `gate_admit`: every waiter that
  finally timed out ran the corpus anyway.
- **It re-introduces a WAIT into the land path**, which R7 forbids outright. Note the mechanism
  critique does *not* transfer: a **count**-keyed semaphore has none of `gate_admit`'s self-starvation
  feedback (slots are directly controlled; loadavg is a noisy signal the waiters' own subjects
  produce, and is not even session-attributable). Had the corpus stayed on the land path, this would
  have been the *correct* fix and strictly better than the load-keyed shed. It loses on **subject
  size**, not on mechanism — record that distinction, because the reasoning is reusable if a corpus
  ever returns to the land.

Its open backlog item `6767ec9bb425` ("gate admission bounds LOAD but not CONCURRENCY — N landers can
all observe load < ceiling and start together") is closed with this section as evidence. The
observation was **exactly right**: the shed is a per-lander predicate and genuinely does not cap the
herd. What removed the risk is that the herd's per-member cost collapsed to seconds — not that the
herd got capped. Should a corpus ever return to a land, reopen that item and start from `3d052701`
rather than from scratch.

**Lesson for the ledger.** A work item's symptom and its prescribed remedy rot independently. This
item's symptom was fixed at a different layer two days after filing, while one of its three named
remedies (the queue) became actively forbidden in the same change. Re-derive the premise from disk
before implementing any parked item's prescription — and check the DoD ref for a resolution section
like this one first.
