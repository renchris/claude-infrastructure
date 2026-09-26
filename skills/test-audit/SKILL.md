---
name: test-audit
description: "Gate for writing, changing or reviewing bats tests, and the workflow to audit and prune low-value tests: re-asserted source, duplicated contracts, stubs that prove themselves, test-only seams. Adapted from OpenClaw's test-audit."
---

# Test Audit

Adapted from OpenClaw's `test-audit` skill
(<https://github.com/openclaw/openclaw/blob/main/.agents/skills/test-audit/SKILL.md>, MIT,
© 2026 OpenClaw Foundation), which let OpenClaw delete ~400k LOC of tests with little change in
coverage. The value bar and junk patterns are theirs. The bats mechanics, the gates and the
repo-specific patterns are ours.

Two modes, one value bar. The **authoring gate** applies to every new or changed test at write
time. **Audit mode** sweeps existing tests for ones that re-assert source, duplicate stronger proof,
couple to implementation, or keep test-only production seams alive. Optimise for confidence, not
deletion count.

## Authoring gate

Before adding a `@test`, answer four questions. If any has no answer, do not add the test yet.

1. What observable behaviour, invariant or independent contract does it protect? For a hook this
   is usually the decision JSON, the exit code or the file it writes, not the helper it calls.
2. What credible regression makes it fail?
3. Why does existing coverage not already catch that failure? Each contract has one primary owner
   suite at the strongest boundary. A second layer needs a distinct risk the owner cannot reach.
   Extend a loop or table case in the owner suite before writing a near-duplicate.
4. Does it need a production seam (an env var, flag or function no production caller uses)?
   Hermeticity redirects (`HOME`, state dirs, `PATH` stubs) are fine. A seam that only lets the
   test skip the real path is not; test at the real boundary instead.

Then check the test against every junk pattern below. A match fails the gate unless the retention
bar names the contract it independently guards.

A regression test must fail on the pre-fix code for the intended reason. Record that as the file
header's `RED-proof:` line, the house convention. A regression test that never went red proves the
stub, not the fix. One regression at the owner boundary covers the bug; do not replay it at every
layer it passes through.

## Junk patterns

- `run cmd` with no check of `$status` or `$output` (bats `run` swallows the exit);
- self-comparisons and identity copies;
- copied fixtures, inventories or lists that restate the source's own list;
- exact source or string greps of production files (but see the retention bar);
- private-helper or call-shape tests duplicated by a real-boundary test of the same contract;
- the same scenario asserted twice, in one file or across sibling suites;
- expected values produced by the subject under test;
- stubs that implement the asserted behaviour, or one stub standing in for different tools;
- fixtures that supply the receipt or ordering the subject should produce, or persistence asserted
  against a store the code path never writes;
- negative controls that pass for an unrelated reason: refused by a different guard, an earlier
  exit, or a missing file. Delete the guard under test on a scratch copy; if the test still
  passes, it guards nothing (`sibling-guard-makes-the-fixture-vacuous`,
  `predicate-refusal-is-not-a-negative`);
- a stale assertion that pins behaviour a later fix changed on purpose, which now guards the bug
  (`stale-assertion-becomes-an-inverted-guard`);
- a count or span assertion that covers mechanisms the test does not test
  (`assertion-span-must-equal-its-subject`);
- names that promise more than the body exercises;
- tests whose only purpose is keeping a test-only seam, or production code only tests call, alive.

The lesson names in brackets are memory files under
`~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/`.

Some patterns are already enforced mechanically, so audits skip them. Dead `[[ ]]`, `(( ))` and
`!` assertions are caught by `scripts/bats-assert-liveness.py`. Hermeticity, shellcheck,
kill-guards and eval'd test names have their own `scripts/*-lint.sh`.

## Retention bar

Keep a test when it independently enforces a public contract: a hook's permission decision or
emitted JSON, a CLI's exit codes and output, a config, migration, storage, security, platform,
default, deploy-parity or resident-instruction contract. Also keep:

- call ordering where the order is observable;
- regressions with a credible failure mode. A test named for an incident or a date is one of
  these; read `git log -S` on it before judging;
- source inspection when it is the cheapest independent guard: it fails when the user-facing key,
  byte or path changes, and survives an identifier-only rename;
- a test that is red at baseline. Treat it as a possible product bug, reproduce it, and fix the
  owner rather than deleting it.

Slow or static is not a reason to delete. A test that resembles the implementation may still be
the only proof of a contract; prove otherwise before removing it.

## Audit workflow

**Discovery is read-only.** For a broad sweep, split `tests/*.bats` into lanes along production
owners (not file prefixes alone) and give each lane to a read-only subagent. Add one cross-cutting
lane for byte-identical bodies across files, test-only production seams, and production code only
tests call. A mechanical pre-scan can seed the lanes, but most real candidates need reading.

**Candidate evidence.** Record every field before editing. A missing field means the candidate is
not ready:

- exact test name and `tests/<file>:<line>`;
- what failure it can actually detect;
- non-test callers of the seam it exercises;
- the keeper (the stronger remaining proof, by file:line and name), or why no contract exists;
- history: the commit that added it, and why;
- production or test-support code its removal unlocks;
- risk, and the command that proves the keeper still covers the contract;
- conviction as a percentage. Act on 90% or more; list 70–89% as watch items, not edits.

Marks: **D** delete · **C** consolidate into a named owner · **F** keep the contract, fix the
assertion. A retained test that moves files stays retained.

**Edit shape.** One coherent owner-boundary batch per commit. Delete test-only exports, flags and
dead production paths rather than aliasing them. Do not add replacement tests that restate the
same implementation, and do not turn uncertain candidates into cleanup to raise the count.

## Validation

1. Run each touched suite: `bats tests/<file>.bats`. Before believing a filtered result, assert
   the `1..N` plan line: a refused run prints no TAP and exits 0.
2. For an **F** edit, show the repaired assertion goes red: mutate a scratch copy of the subject
   and run the test against it.
3. `python3 scripts/bats-assert-liveness.py tests/<file>.bats` and bare `shellcheck` on every
   touched file (the land gate runs it bare).
4. `git diff --check`, then `git diff --numstat`, reporting production separately from tests.
5. Land through the project-local `/ship`, never a bare push.

## Report

Removed categories and counts · production simplifications · retained false positives and why ·
the validation actually run · production versus test LOC · commit and land state · watch items.
