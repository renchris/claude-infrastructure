# The revert remedy on `postland-revert-0e5e2c3bb7c2` is disproved — fix forward instead

**Date:** 2026-09-19 · **Backlog row:** `df325e4274a6` · **Fix:** `6e94c027` (this branch)
**Row title:** `post-land AUTO-REVERT FAILED(step=revert rc=90): tests/deploy-link-parity.bats @
0e5e2c3bb7c2 (revert none on postland-revert-0e5e2c3bb7c2)`

## The verdict in one line

The row's **conviction was correct at the time it was written** and its **remedy is wrong today**.
`tests/deploy-link-parity.bats` is still red on trunk, but the assertion that is red is no longer
the one `0e5e2c3b` broke, and the commit that owns today's red is `5fea9387` — which is itself the
*fix* for the red `0e5e2c3b` caused. Hand-landing `git revert 0e5e2c3b`, which is what the standing
page prescribes, would take the Jev feature off trunk **and leave the suite exactly as red as it is
now**. It is fixed forward by `6e94c027` instead.

## What the page asks for, and why it cannot work

`scripts/postland-verify.sh:3234` sets `rc=90` when `git revert` conflicts, so `step=revert` and
`revert=none`. The file's own comment at that site records that the branch is then a bare copy of
`origin/main` with zero commits on it, and that the remedy has to be "make a revert commit by hand,
resolving the conflict", not "land the branch". That is the remedy this row carries.

`postland-revert-0e5e2c3bb7c2` exists only on the desk — `git ls-remote --heads origin
'postland-revert*'` returns empty — so there is nothing on the remote to land in any case. But the
substantive objection is independent of the branch:

> **`0e5e2c3b` never touched `scripts/deploy-link-parity.sh`.**
> `git show --stat 0e5e2c3b` names `install.sh` and `scripts/deploy-parity-assert.sh`, not this
> file. Today's red is produced by 13 lines that `5fea9387` added to
> `scripts/deploy-link-parity.sh`. A revert of `0e5e2c3b` cannot remove lines it never wrote, and
> the failing assertion derives its inputs by **reading that script's text**, not by looking at the
> filesystem — so the derived set still contains `scripts/jev` after the revert, and case 64 stays
> red.

## The two generations, measured

Suite run at three commits in a detached worktree, with the TAP plan line asserted present in each
run so that a gate *refusal* could not be read as a pass:

| commit | what is red | note |
|---|---|---|
| `0e5e2c3bb7c2` | `not ok 42`, `not ok 43` | case 64 **GREEN** |
| `5fea93873532` | `not ok 64` | 42/43 green |
| `1885776a` (trunk) | `not ok 64` | trunk today |

- **`0e5e2c3b`** ("feat(jev): in-hook semantic verdicts") taught `install.sh` the `scripts/jev`
  class and extended `deploy-parity-assert.sh`, but not `deploy-link-parity.sh` — the third auditor
  over the same state model. Case 42, the arm pinning *install.sh's classes* against the forward
  walk, went red. **The bisect that convicted `0e5e2c3b` was right about that red.**
- **`5fea9387`** ("walk scripts/jev — the third auditor never heard of it") closed case 42 by adding
  `scripts/jev` to the **forward walk**. But the forward walk is the very enumeration that case 64
  pins against the **live-side stray sweep**, and the sweep's list did not follow. Case 64 went red
  on the next land.

So the fix for one coverage arm was the culprit for the other. The gap moved one leg to the right;
it did not close.

## Root cause, derived rather than argued

Re-running the suite's own `derive_stray_sets()` extraction against trunk's
`scripts/deploy-link-parity.sh` gives 12 forward-walked directories, 10 stray-swept, 1 declared
`NOT-STRAY-SWEPT` (`commands`). The unclaimed set has exactly one member:

```
scripts/jev
```

This is the generator the file's own comments already name, one turn further on: **five separate
hand-written enumerations of the live layer live in this file, any of them can grow alone, and
closing the gap in one of them buys exactly one land.** Cf. the always-loaded rule *"a scope
sentence is not falsified by anything it says; it is falsified by a sibling enumeration growing,
and no reader of either one can see the other move"*, and
`sibling-auditors-must-share-the-state-model`.

## The fix, and why swept rather than declared

`scripts/jev` joins the `sweep_strays` loop. It copies `scripts/lib`'s deploy leg line for line
(`ensure_real_dir` + per-file `link_file`/`copy_file`, `install.sh:759-770`) and is an **executed**
surface — `evaluate.mjs` and `pilot.sh` both run — so an unversioned real file appearing there is
the `bin/cc-mail` defect class, not the normal path that exempts `commands/`.

### The behavioural arm is not optional

Case 64 pins the **text** of the sweep loop header, so it goes green the instant the word
`scripts/jev` appears in that line — *including under a sweep that cannot actually reach the
directory*. `sweep_strays` globs `"$CFG/$d"/*` one level deep, so a nested member is reachable only
because the caller passes the nested path; that is a property of the **argument**, which a
list-text assertion structurally cannot see. Case 67 plants the defect instead. Both mutants were
built and run:

| mutant | case 64 | case 67 |
|---|---|---|
| fix removed entirely (pre-fix state) | **RED** | **RED** |
| loop text kept verbatim, `[ "$d" = "scripts/jev" ] && return 0` inside `sweep_strays` | GREEN | **RED** |

The second row is the point: it is the power case 64 lacks. `.mjs` is the deliberate plant —
`scripts/jev` is the one deployed class `install.sh` globs bare `*` precisely because `.mjs` appears
in no deploy glob in the tree, so a sweep that had quietly grown an extension filter would pass the
existing `.py` case and fail this one. `commands/` is the discriminating control in both cases, so
neither green can come from the sweep having merely become indiscriminate.

## What was run

```
tests/deploy-link-parity.bats   1..67   0 not ok
tests/deploy-parity.bats        1..107  0 not ok
tests/gate-ownscope-leak.bats   1..24   0 not ok
tests/ms365-reply-splice.bats   1..18   0 not ok
tests/worktree-gc.bats          1..110  0 not ok
tests/wrap-ledger.bats          1..133  0 not ok
scripts/self-path-lint.sh          rc=0
scripts/test-walltime-lint.sh      rc=0
scripts/permission-gate-lint.sh    rc=0
scripts/rules-hook-budget-lint.sh  rc=0
scripts/bats-shellcheck-lint.sh    rc=0   (see below)
shellcheck -S warning scripts/deploy-link-parity.sh   rc=0
```

Two instrument notes, both of which would have manufactured a false green:

- **`bats-shellcheck-lint.sh` first REFUSED** — `rc=2`, `⛔ shellcheck not installed — NOT a clean
  verdict`. This VM has no shellcheck. It was re-run against a real shellcheck 0.10.0 rather than
  read as a pass (*"a gate refusal is not a gate result"*).
- **The gate's own scope was empty before the commit.** It infers own-scope from
  `origin/main...HEAD`, which reported `0 changed .bats line(s)` while the work sat uncommitted —
  a clean-looking verdict over nothing. Re-run after committing, it reports `20 changed .bats
  line(s)` and `1 suite(s) scanned`. That second run is the one quoted above.

## Provenance of this reading

- Checkout arrived **shallow at depth 50** and was `git fetch --unshallow`'d before any trunk read;
  every ancestry claim here was made against a complete history.
- `git merge-base --is-ancestor 0e5e2c3bb7c2639f1bdc2f5bb95f4475a602d5f0 origin/main` → **0**
  (in trunk). Same for `5fea93873532ddbd93161ff601a2d9d2c82e2abf`.
- **Dispatcher vintage:** `git rev-parse origin/main:bin/cc-dispatch` =
  `dc9130372d6332940388c2a17da7c65c1af3c3bd`, **equal** to the blob that composed the brief. The
  dispatcher that fired this session *is* trunk, so nothing here is qualified by dispatcher lag.

## Disposition

- The red is **fixed forward** by `6e94c027`, not reverted.
- The standing page for `postland-revert-0e5e2c3bb7c2` should be **cleared without hand-landing
  anything** — its remedy is disproved above, and its branch holds zero commits.
- `0e5e2c3b` (Jev) and `5fea9387` (the forward walk) both **stay on trunk**.
