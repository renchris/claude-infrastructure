# `4f7bf7b75181` re-dispatched 1h28m AFTER its own cure landed — re-verification on trunk

**Item:** cc-backlog `4f7bf7b75181` — *"post-land HUNG: tests/postland-verify.bats wedged at
11426/14327 @ 4bffeaeeb22d — un-stubbed external seam, timeout-wrap it (NOT a peer pkill)"*.
**Worked:** 2026-09-20, off-box (cloud VM, Linux 6.18.44 x86_64, bash 5.2.21, bats 1.13.0), branch
`claude/fire-20260920T230255Z-34826-1`, fired 2026-09-20T23:02:55Z.
**Verdict:** **DONE — cured on trunk before this session was fired. No code is owed.** The cure is
`e3a7ace41b7096de16b4f72ebb436f1a47deb009`, and the finding this session adds is not about the
defect: it is that the row re-dispatched **1h28m32s after its own cure landed on trunk**, so what is
live here is the CLOSE path, not the stall watcher.

The companion record — the diagnosis, the disproof of the premise, the two-arm run and the
mutants — is `docs/research/postland-hung-poll-floor-2026-09-20.md`, landed by the cure commit
itself. This file does not restate it. It records (a) the ancestry assertions the brief asks for,
(b) an **independent** re-measurement of the effect on a different box after the land, and (c) the
re-dispatch fact.

---

## 1. Provenance, as the brief requires

| check | command | result |
|---|---|---|
| shallow clone | `git rev-parse --is-shallow-repository` | `true` → `git fetch --unshallow` run **before** any trunk read |
| tree vs trunk | `git rev-list --count HEAD..origin/main` | **0** — this tree IS trunk (`bb5b2e4a`) |
| dispatcher vintage | `git rev-parse origin/main:bin/cc-dispatch` | `dc9130372d6332940388c2a17da7c65c1af3c3bd` — **EQUAL** to the blob that composed this brief, so the dispatcher that fired this session is trunk. No landed-but-not-live gap to reason about on that axis |
| cited `4bffeaeeb22d` | `git cat-file -t 4bffeaeeb22d` | **`tree`**, not a commit — `--is-ancestor` refuses it. Correct for this producer (stamps are tree-keyed) but not walkable as history |
| falsifier, re-run at filing | `postland-verify.sh --falsify-red …` | NOT REFUTED (exit 1), silent — and that is consistent with a cure: the probe asks about a RED stamp's reproduction, which a landed fix to the *watcher's sleep* does not retract |

## 2. The cure is on trunk — asserted, not assumed

```
$ git merge-base --is-ancestor e3a7ace41b7096de16b4f72ebb436f1a47deb009 origin/main && echo ANCESTOR
ANCESTOR
$ git merge-base --is-ancestor ccd8dce4c1c1be4831c892bb9fb223ebbeeb8999 origin/main && echo ANCESTOR
ANCESTOR
$ git merge-base --is-ancestor 9fe923385f87a594c701e640c13bd8aa09a42a32 origin/main && echo ANCESTOR
ANCESTOR
```

| sha | subject | role |
|---|---|---|
| `e3a7ace4` | *fix(postland): the stall watcher charged its poll PERIOD as a cost floor on every corpus run* | **the cure** — `STALL_TICK_S` + `stall_wait`, the call site, 4 tests, the lesson + its hook, the companion research doc |
| `ccd8dce4` | *fix(tests): SC2034 on STALL_TICK_S …* | follow-up: shellcheck cannot see a read inside an `eval`'d body |
| `9fe92338` | *docs(research): the two arms, the sibling population, and the selftest baseline* | the two-arm table and the sibling population, appended to the companion doc |

`git log -S'stall_wait' -- scripts/postland-verify.sh` returns exactly `e3a7ace4`: one introduction,
no later churn, nothing reverted.

## 3. The premise, re-checked against trunk rather than taken from the companion doc

> *"un-stubbed external seam, timeout-wrap it"*

Refuted, and re-established here from the file on trunk rather than from §1 of the companion:

- `scripts/postland-verify.sh:3798` — the bats seam is **already** `exec "$TIMEOUT_BIN" -k 10
  "$SUITE_TO" …`, with no `--foreground`, i.e. in its own process group so the signal reaches the
  whole bats tree. There was no un-stubbed seam to wrap; a further `timeout` would have been a third
  bound over an interval that contained no work.
- `scripts/postland-verify.sh:3810` — the watcher's wait is now `stall_wait "$poll" "$cpid" ||
  break`, the cure's call site. This is the half a unit test cannot reach
  (`helper-position-bounds-a-fixs-reach`), and it has its own arm below.

The parenthetical *"NOT a peer pkill"* was right and remains right: nothing was killed.

## 4. Independent re-measurement on this box, after the land

Different VM, different session, trunk as-is, default period (`POSTLAND_STALL_POLL_S` unset):

```
$ bats --count tests/postland-verify.bats
152
$ bats -T -f 'stall_wait|the watcher.s wait is stall_wait' tests/postland-verify.bats
1..4
ok 1 stall_wait: the wait ends when the CHILD does, not when the period does in 1113ms
ok 2 stall_wait: a LIVE child still costs the FULL period (so every clock above is unchanged) in 3124ms
ok 3 stall_wait: POSTLAND_STALL_TICK_S=0 restores the whole-poll sleep (the kill switch) in 3098ms
ok 4 the watcher's wait is stall_wait, not a bare sleep (the site the fix has to reach) in 91ms
```

The `1..4` plan line is asserted, not just the absence of `not ok` — a refused or deferred gate
emits zero `not ok` too (`a-gate-refusal-is-not-a-gate-result`).

**The effect itself, re-timed on the two tests the companion doc's §3 measured:**

| test | companion §3, pre-fix | companion §3, post-fix | **this box, trunk, today** |
|---|---|---|---|
| `C7: CC_POSTLAND_WORKTREE is still honored verbatim …` | 60 442 ms | 1 448 ms | **1 391 ms** |
| `C7: a trailing-slash TMPDIR reaches the corpus …` | 60 421 ms | 1 409 ms | **1 379 ms** |

Two independent boxes land within 5% of each other on the post-fix figure, and ~44x below the
pre-fix one. The 60 s floor is gone from trunk.

**The sibling population** (the companion's *"it was never one suite"*), re-run whole:

```
$ bats -T tests/postland-verify-bisect-bound.bats tests/postland-verify-passfloor.bats \
        tests/postland-band-floor.bats
1..46        # 46 ok, 0 not ok, real 0m49.503s
```

46/46, ~49.5 s against the companion's 51 s. On unpatched trunk the 4-test `passfloor` file alone
had not finished 3 of its 4 tests in 10 minutes. Seven of the 46 are `# skip taskpolicy(8) absent on
this host` — a macOS instrument this Linux VM does not carry, unrelated to this row and green-by-skip
in both arms.

Box-only reds recorded in the companion's §5 (`stat -f %m` is BSD syntax, so the C6/C6b/C33 mutex
block dies on GNU coreutils; and `identity_assert` drops the fixture's `tester@example.com`, cured
for a verification run by a `git config --system` identity `HOME` redirection cannot hide) were met
again here exactly as described. Nothing in scope is reachable from either, and nothing was touched
for them.

## 5. The finding this session actually adds

| event | UTC | source |
|---|---|---|
| cure landed on trunk (`e3a7ace4`, committer date = desk replay) | **2026-09-20T21:34:23Z** | `git log -1 --format=%cI` |
| this session fired on the SAME row | **2026-09-20T23:02:55Z** | branch name `claude/fire-20260920T230255Z-34826-1` |
| gap | **1h28m32s** | |

The row was re-dispatched onto a cured tree, and the dispatcher that did it is byte-identical to
trunk (§1) — so this is not a stale-dispatcher artifact. Two readings are open and this box cannot
separate them, because the backlog store is on the operator machine and every verb against it is a
no-op from here:

1. **the desk's close simply had not run yet** — the return path lands content and closes the row on
   its own cadence, and 1h28m is inside a plausible one; or
2. **the land and the close are not coupled** — the reconciler replayed the branch onto trunk and the
   row stayed open, in which case the row will keep re-firing until someone closes it by hand.

What distinguishes them is a single fact nobody off-box can read: whether `4f7bf7b75181` is open
right now. **It is worth reading, because the two differ in what they cost.** Under (2) every
re-fire spends a whole cloud session re-deriving a verdict that already exists — this session is
either the first or the second such re-derivation, and a `git log --oneline -S'stall_wait'` was
enough to establish it in under a minute, which is the cheap half. The expensive half is that a
worker with no companion doc to find would have written the diff: `a-re-dispatch-loop-is-evidence-
about-the-dispatcher-not-about-the-row` is exactly this shape, and it warns that a returning row can
be one nobody has failed at. Here somebody had already succeeded at it.

**Why this file exists at all, rather than nothing:** a branch with no commits is indistinguishable
from a VM that never booted, so the row would re-dispatch forever on the strength of this session's
silence (`CLOUD_OBSERVABILITY` §4.1). This is the verdict the brief asks for in the already-cured
case — the cure sha, asserted; what was run; the evidence — and no invented code work.

## 6. Exactly what was run

```bash
git rev-parse --is-shallow-repository; git fetch --unshallow          # true → deepened first
git fetch origin -q; git rev-list --count HEAD..origin/main           # 0
git rev-parse origin/main:bin/cc-dispatch                             # EQUAL to the brief's blob
git cat-file -t 4bffeaeeb22d                                          # tree
git log --oneline -S'stall_wait' -- scripts/postland-verify.sh        # e3a7ace4, the only one
git merge-base --is-ancestor {e3a7ace4,ccd8dce4,9fe92338} origin/main # all ANCESTOR
npm install -g bats                                                   # 1.13.0
git config --system user.{email,name} …                               # §4, harness only, no repo change
bats --count tests/postland-verify.bats                               # 152
bats -T -f 'stall_wait|the watcher.s wait is stall_wait' tests/postland-verify.bats   # 1..4, 4 ok
bats -T -f 'C7: CC_POSTLAND_WORKTREE is still honored verbatim|C7: a trailing-slash' \
     tests/postland-verify.bats                                       # 1..2, 1391ms / 1379ms
bats -T tests/postland-verify-bisect-bound.bats tests/postland-verify-passfloor.bats \
        tests/postland-band-floor.bats                                # 1..46, 46 ok, 49.5s
bash -n scripts/postland-verify.sh
bash scripts/rules-hook-budget-lint.sh
```

## 7. Disposition

`4f7bf7b75181` is **DONE**, cured by `e3a7ace4` (ancestor of `origin/main`, asserted in §2) before
this session existed. It must not be closed as *"timeout-wrapped a seam"* — that remedy is refuted
(§3) and the seam was already bounded. Close it against `e3a7ace4`, citing the companion doc for the
diagnosis and this file for the post-land re-verification.

Then read whether the row was still open at 2026-09-20T23:02:55Z (§5). If it was, the owed work is
on the return path — land-then-close coupling — and it is a **new row**, not this one
(`cause-refuted-effect-discharged`: this row's cause is dead, and the re-dispatch is a different
effect on a different subject). Nothing about the stall watcher is owed.
