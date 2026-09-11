# The BOUNDED deadline arm is a race on core speed — 2026-09-11

**What this adjudicates.** cc-backlog `94b69debc2cb`: a post-land RED convicting
`tests/cc-permission-harvest.bats::the read-only pipeline is BOUNDED: past CC_PERMHARVEST_MAX_S it
exits 6 and writes no partial proposal` at `6bb41fc64eeb`.

> **VERDICT.** The conviction is **REFUTED** — `6bb41fc64eeb` cannot redden this suite, and the arm is
> green at the culprit, at its parent and at trunk. But the arm is **genuinely fragile, in the one
> direction nobody looks**: it asserts `exit 6` under a `CC_PERMHARVEST_MAX_S=0.01` bound, and the cut
> can only fire while the pipeline is still running — so its unstated precondition is
> `pipeline runtime > bound`. That runtime is pure-Python CPU, measured **30.3–35.5 ms** here against a
> **10 ms** bound: a **3.5x** margin that erodes on a **FASTER, QUIETER** box and never on a loaded one.
> When it erodes the arm reports `status 0` with a proposal written — byte-for-byte how a **deleted
> deadline** reads. Fixed by taking the bound to **0.001 s** (the figure the subject's own `_deadline_s`
> docstring already specifies; the arm had drifted 10x off its spec) and adding a third arm that
> re-derives the margin at run time and reds **naming the erosion**.

Measured off-box on a cloud vCPU (Linux 6.18, CPython 3.11.15), tree at `origin/main` `254d222100`
(`git rev-list --count HEAD..origin/main` = 0). Dispatcher vintage: `origin/main:bin/cc-dispatch` =
`e61bcbfc657a44a20b03d7d52ab3e921fd138242`, **EQUAL** to the blob that composed the brief — the
dispatcher that fired this row IS trunk, so no landed-vs-live gap applies to the dispatch path.

## 1. The attribution is refuted by the culprit's own diff

`6bb41fc64eeb` — *"docs(gate-memo): the ratchet-memo rollout, measured on real lands"* — touches two
files and no others:

```
 .claude/rules/agent-operating-lessons.md |  2 ++
 scripts/lib/gate-memo.sh                 | 29 ++++++++++++++++++++++++-----
```

The rules file is prose. `scripts/lib/gate-memo.sh` is the blob-sha-keyed verdict memo for the land
gate's **pure static checks**; `grep -rl gate-memo` names its consumers as `ship-land.sh` plus the lint
scripts (`bats-kill-guard`, `test-walltime`, `test-hermeticity`, `utc-stamp`, `moving-ref-control`,
`pane-spawn-coverage`, `git-identity`, `test-afunix-path`, `pipefail-sigpipe`) and their own suites.
**Nothing in it runs a bats suite**, and it is not on any path `bin/cc-permission-harvest` or this suite
reads. The convicted diff therefore has no mechanism by which it could redden the convicted test.

This is not the whole-tree-ratchet class (repo memory: *a ratchet's culprit is in its output, not in the
range*) — `cc-permission-harvest.bats` is a subject-specific suite, not a ratchet, so reachability here
was never even one-sided-informative. It is a plain mis-attribution.

## 2. The A/B — the conviction does not reproduce

`bats -f "the read-only pipeline is BOUNDED"`, one variable (the checked-out tree), separate detached
worktrees:

| tree | sha | result |
|---|---|---|
| culprit | `6bb41fc6` | `1..1` · **ok 1** |
| culprit's parent | `4915f69a` | `1..1` · **ok 1** |
| trunk | `254d2221` | `1..1` · **ok 1** |

Whole suite at trunk: **61/61 ok**, plan line `1..61` present (an absence of `not ok` is not a pass —
repo memory: *a gate refusal is not a gate result*). The convicted arm run 20 consecutive times at
trunk: **20 pass / 0 fail**. At the shipped 0.01 s bound, the arm's own command run 40 times returned
`rc 6` with no output directory **40/40**.

**So the red was not reproduced on this box, and this note does not claim to have reproduced it.** What
follows is a defect found while trying to, established on its own evidence.

## 3. The defect: the arm is a race, and it reddens when the box is FAST

The deadline is armed inside `pipeline()` and cancelled in its `finally`, so `SIGALRM` can only cut a
pipeline that is still running. The arm's hidden precondition is therefore `pipeline runtime > bound`.

`cProfile` over `_pipeline` on this suite's fixture: the time is **pure-Python CPU**, with no I/O or
subprocess term of consequence —

```
0.145s cumulative (profiled)
  0.097  set_cover
  0.061   └ run_gates (63)
  0.058      └ permission_matcher.rule_matches_leaf (2191)
  0.030         └ permission_matcher.normalize_leaf (2518)
  0.026  analyse
```

Unprofiled wall time, 7 runs: `0.0355 0.0311 0.0313 0.0318 0.0312 0.0303 0.0319` — **min 30.3 ms, max
35.5 ms**.

Bound sweep, 8 invocations per point, counting `exit 6`:

| bound (s) | 0.001 | 0.005 | 0.010 | 0.015 | 0.020 | 0.025 | 0.030 | 0.040 | 0.060 | 0.100 |
|---|---|---|---|---|---|---|---|---|---|---|
| exit 6 | 8/8 | 8/8 | **8/8** | 8/8 | 8/8 | 8/8 | 8/8 | 1/8 | 0/8 | 0/8 |

The verdict flips between 0.030 and 0.040. The shipped bound was **0.010** — a **3.5x** margin on a
quantity that scales with single-core CPython throughput.

Three things make this worth fixing rather than filing:

1. **The direction is inverted from every other timing flake in this repo.** Load makes the arm *pass*
   (a slower pipeline is easier to cut). It fails when the box is quick and quiet. Every load-keyed
   triage — and this repo has a lot of it — searches the one direction that cannot find it.
2. **The failure is indistinguishable from the defect the arm exists to catch.** On erosion the arm
   reports `status 0` and a written proposal, which is exactly what a deleted deadline reports. A
   reader's first hypothesis will be "the deadline broke", and it will be wrong.
3. **The arm had drifted off its own subject's spec.** `_deadline_s`'s docstring already says: *"at
   0.001 s the suite can prove the cut fires mid-pipeline, prints the named block, and returns 6, in
   milliseconds."* The suite shipped 0.01. Nothing measured the gap, because nothing measured the
   margin at all.

## 4. The fix, and the mutants that prove it has power

- Bound `0.01` → **`0.001`** in the primary arm (~31–44x margin on this box's reading).
- A third arm that **re-derives the margin at run time** and asserts it against a **10x floor**, failing
  with a message that names the erosion and prescribes lowering the bound. It times `_pipeline` itself,
  not the process: interpreter startup is about as large as the pipeline here and is *not* subject to
  the timer, so timing the process would inflate the ratio in the one direction that hides erosion.

Green in both arms proves nothing (repo memory: *green in both arms is an equivalence guard, not a
red-proof*), so each arm was mutated:

| mutant | what it removes | result |
|---|---|---|
| **M1** — margin arm at `bound 0.01, floor 10` | nothing; it is **the configuration that shipped** | **RED**, `MARGIN 0.0360s / 0.0100s = 3.6x` |
| **M2** — margin arm at `floor 1000` | the floor's slack | **RED**, `41.0x` |
| **M3** — `_deadline_s` returns `0.0` | **the cure**: the deadline never arms | **RED**, primary arm at `[ "$status" -eq 6 ]` |
| control | — | green, `MARGIN 0.0444s / 0.0010s = 44.4x` |

**M1 is the load-bearing one.** The new guard convicts the exact bound that was on trunk, at 3.6x
against a 10x floor — so had it existed, the under-margined arm would have been a loud, self-describing
red before it ever reached a land, instead of a silent coin-flip on how fast the box was that minute.
M3 confirms the primary arm still detects a removed deadline at the new bound, i.e. lowering the bound
bought margin without costing power.

## 5. What this does not establish

The desk's original red was not reproduced here, so this note cannot say it *was* the margin. It says:
the convicted commit cannot have caused it; all three A/B arms are green; and the arm carries a real,
measured 3.5x race whose failure signature matches the reported one. Other causes remain open for that
specific observation — gate contention (`cc-bats` refuses a run at 2 concurrent roots and prints a
deferral that a filtered TAP read cannot distinguish from a pass), or a macOS-only term this Linux box
cannot express. Naming the margin does not close those; it removes one live way for this arm to redden
a future land.

## 6. Gates run

`bats` 61/61 (plan line present) · `bats-assert-liveness.py` clean · `test-walltime-lint` clean (659
suites) · `bats-kill-guard-lint` clean · `utc-stamp-lint` clean (670 files) · `test-hermeticity-lint`
clean, 0 new leaks · `bats-testname-eval-lint` clean · `pipefail-sigpipe-lint` clean.
`bash -n` on the `.bats` file errors at line 95 on the **pristine trunk copy** as well — bats files are
not plain bash, so that is a property of the format, not of this diff (control run before reporting it).
