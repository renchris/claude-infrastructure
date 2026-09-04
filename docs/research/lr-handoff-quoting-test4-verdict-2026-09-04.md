# VERDICT: cc-backlog `b3a3f5b694e6` is ALREADY CURED — `ac341e51` landed 5h39m before the row was fired

**Date:** 2026-09-04 · **Lane:** cloud (off-box VM) · **Row:** `b3a3f5b694e6`
**Row text:** post-land RED — `tests/lr-handoff-launcher-quoting.bats::4. %q does not weld argv: --prompt stays
one argument, fable stays four` @ `a03a4b6386ab`

**Verdict: NO CODE WORK. The assertion the row convicts was fixed on trunk before this dispatch existed,
and the fix is live-proven by mutant, not merely present.** This document is the evidence; nothing in the
repository is changed by it.

---

## 1. The cure, and its ancestry assertion

```
ac341e516fed4e55f84eb6f9f733ad4eff77ebad
  fix(tests): the 5.1 flip left four assertions pinning Fable 5 — one red, three vacuous
  git merge-base --is-ancestor ac341e51 origin/main  →  exit 0 (YES)
```

Its diff is one line, and it is exactly the line the row names:

```diff
 tests/lr-handoff-launcher-quoting.bats @ test 4 (body at :171, assertion at :185)
-  [[ "$output" == *"argv[7]=<claude-fable-5>"* ]] || false
+  [[ "$output" == *"argv[7]=<claude-fable-5-1>"* ]] || false
```

The cure's own commit body already diagnoses the row correctly: the Fable 5.1 keying flip swept `scripts/`
and `bin/` and never swept `tests/`, so `lr-handoff.sh` began emitting `claude-fable-5-1` while this
assertion still pinned `claude-fable-5`. The assertion terminates on `>`, so no substring match rescued it
— a genuine red, in the postland run of `a03a4b6386ab`, which is the sha this row cites.

## 2. What was actually run here, on trunk

Checkout state at time of run: `git rev-list --count HEAD..origin/main` = **0** — this tree *is* trunk
(`8b9ea57d`). The checkout arrived shallow at depth 50 and was unshallowed first, so every ancestry read
below answers from full history rather than from inside a horizon.

```
$ bats tests/lr-handoff-launcher-quoting.bats
1..12
ok 1 … ok 12          # all twelve green, test 4 among them
```

## 3. Mutant proof — the assertion is LIVE, not vacuously green

A green suite on trunk is not by itself proof the row is cured: it would read identically if the assertion
had been widened into uselessness. So the emitter was reverted and the suite re-run.

The id is **hardcoded at `scripts/limit-recover/lr-handoff.sh:338`**, not resolved from the SSOT:

```bash
FIRE_ARGV+=(--model claude-fable-5-1 --effort "${EFFORT:-high}")
```

| Mutant | Test 4 |
|---|---|
| trunk, unmodified | `ok 1` |
| `lr-handoff.sh:338` → `claude-fable-5` | `not ok 1` … `line 185: [[ "$output" == *"argv[7]=<claude-fable-5-1>"* ]] || false' failed` |

Both mutants were reverted with `git checkout --`; `git status --porcelain` is empty.

⚠️ **One negative result worth recording, because it is a trap for the next reader.** The first mutant
attempted here flipped `model-config.yaml` `frontier_latest: claude-fable-5-1 → claude-fable-5` and test 4
**still passed**. That is not a vacuous assertion — it is that this emitter does not read the SSOT at all.
`lr-handoff.sh:338` carries its own copy of the model id, so the SSOT is not the single copy on this path
and the next lateral bump will break it again in exactly the same way. Not filed as work here (out of this
row's scope, and the cure's author already surveyed the id population deliberately), but it is the standing
reason this class of red recurs.

## 4. Why an already-cured row was dispatched — a staleness fact, not a defect

| Event | Time (PDT) |
|---|---|
| RED observed, row filed — postland run of `a03a4b6386ab` | 2026-09-03 23:01 |
| **Cure `ac341e51` lands on trunk** | **2026-09-04 03:39** |
| this row dispatched to the cloud lane | 2026-09-04 09:18 |

The cure preceded the dispatch by **5h39m**. The row was open in the backlog store the whole time: nothing
re-reads a filed RED against trunk before firing it, so a cured row stays dispatchable until something
closes it. This is the failure mode the dispatch brief's own FIRST STEP is written to catch, and it caught
it — which is the argument for keeping that step mandatory rather than advisory.

## 5. Dispatcher vintage — BEHIND trunk (landed ≠ live)

The brief declares the bytes that composed it: `bin/cc-dispatch` blob `646b8a65…`. Trunk carries
`98ab38f5…`. **DIFFERENT — the dispatcher that fired this session is behind trunk.**

Resolved concretely: the brief's blob is the one from `4c60e894` (landed 06:28 PDT); trunk moved to
`124c4da0` (landed 06:50 PDT). This session was fired at 09:18 PDT — **2h28m after the newer dispatcher
landed** — still running the older bytes. That is a convergence fact about the live layer, not a defect in
`cc-dispatch`: the newer commit was on trunk and the executing copy had not caught up.

Consequence for reading this document: "the fix already landed" does not answer "did the fix run." For the
row itself that distinction is inert — the gate runs the test out of the checkout, not out of a converged
live copy, so the trunk state *is* what the gate sees. It is recorded because the same gap on a
`hooks/`- or `bin/`-resident cure would not be inert.

## 6. Disposition

Close `b3a3f5b694e6` as **already cured**, evidence `ac341e51`. No diff is proposed. Re-deriving one would
have meant re-landing a change already on trunk, i.e. a revert wearing a fix's clothes.
