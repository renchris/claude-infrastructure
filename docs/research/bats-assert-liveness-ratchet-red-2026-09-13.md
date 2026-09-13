# The `bats-assert-liveness` ratchet red at `fd74695bec91` — confirmed, cured, and what it hid

cc-backlog `7729e7d81438` · post-land AUTO-REVERT FAILED(step=revert rc=90) ·
`tests/bats-assert-liveness.bats` @ `fd74695bec91f6ac421ff2bf1f34d3f12674a1d0`

Measured off-box (cloud VM, Linux, bats 1.13.0, python 3.11.15) against
`origin/main` = `cc492538`, with the checkout unshallowed first and
`git rev-list --count HEAD..origin/main` = **0** (this tree IS trunk).
Dispatcher vintage: `git rev-parse origin/main:bin/cc-dispatch` =
`27c461a5f1a4de551fdfbe2a619e28e696c13aaa`, **equal** to the blob named in the
brief — the dispatcher that fired this row is trunk, so no landed-not-live
caveat applies to the remedy below.

## Verdict: the premise is CONFIRMED, not refuted

The item is one of the classes this repo normally treats with suspicion — a
whole-tree **ratchet** suite named by a post-land walk, where reachability
carries no information because every commit reaches it
([A bisect's culprit is in its output, not in the range]). It is **not** that
class here. `tests/bats-assert-liveness.bats` case 25 runs
`python3 scripts/bats-assert-liveness.py --summary` over all of `tests/`, and
the convicted commit **adds a `.bats` file** — `tests/cc-cannot.bats`, 72 lines
— which is precisely the kind of diff that can redden this ratchet.

A/B against the analyzer, one variable, same box:

| tree | dead assertions | rc |
|---|---|---|
| `00a21809` — the culprit's **parent** | 0 in 0 of 666 files | 0 (green) |
| `fd74695be` — the **convicted** commit | 1 in 1 of 667 files | 1 (red) |
| `cc492538` — **trunk today** | 2 in 1 of 668 files | 1 (red) |

The attribution is sound and the red was **still live on trunk** when this ran:
AUTO-REVERT reported `rc=90`, i.e. the revert conflicted and applied nothing, so
nothing had cured it in the interim. (Per the corpus, a *failed* auto-revert on
a ratchet is the benign outcome — had it applied, it would have reverted the
whole `cc-cannot` feature and left the red where it was.)

## What was actually dead

Both findings are the `negation` class — a bare `! cmd` in non-final position,
which bash exempts from `errexit`, so the assertion is evaluated and discarded:

- `tests/cc-cannot.bats:33` — `! printf '%s' "$output" | grep -q "tui"`,
  introduced by `fd74695be` (this item's culprit).
- `tests/cc-cannot.bats:90` — `! printf '%s' "$output" | grep -q "read-only"`,
  introduced by **`e3f43187c`**, a *later* commit.

### Finding: a ratchet that is already red admits further members of its own class silently

The second dead assertion is the part worth carrying. Once case 25 was red at
`fd74695be`, the gate had no remaining signal to give: `e3f43187c` added the
same defect to the same file and produced no *new* red, because a binary
whole-tree ratchet is already saturated. The post-land walk convicts on the
first member and every subsequent member lands under its cover. The tell is in
the count, not the colour — `1 → 2` dead assertions across two commits, while
the gate read `red → red` throughout. ⇒ **when a ratchet's red goes unfixed,
its population keeps growing invisibly; read the ratchet's own count, not its
exit status, and treat an unfixed ratchet red as an open admission window
rather than a single known defect.**

### The A3 site was dead but shadowed; the R0 site was the only guard

These two are not equally costly, and the difference only shows under a mutant.

`A3` (line 33) sits under a live `[ "$status" -ne 0 ]`. The realistic
regression it guards — the `/usr/bin/env <anything>` glob bypass the commit
exists to forbid — makes the subject return `HUMAN` (rc 0), which that live
neighbour catches. So the dead assertion was redundant *for the realistic
mutant*, and a naive mutant (restoring the glob) is caught by the neighbour and
attributes nothing.

`R0` (line 90) has **no status assertion at all**:

```bash
run bash "$CC" -- "gh pr view 1 --repo x/y --web"
! printf '%s' "$output" | grep -q "read-only"     # ← dead: the ONLY guard on this case
```

With that line dead, the entire first case of `R0` was unguarded — a real
coverage hole, not a redundancy.

## Red-proofs

Green-in-both-arms proves nothing ([Green in both arms is an EQUIVALENCE
guard]), so each revival was scored against a mutant that removes the cure from
the **subject** (`bin/cc-cannot`), with the pristine subject as control.

`R0` — mutant drops `--web` from `RO_MUT`, so `gh pr view … --web` wrongly
matches read-only:

| | pristine subject | MUTANT subject |
|---|---|---|
| PRE (dead assertion) | GREEN | **GREEN** ← defect invisible |
| POST (revived) | GREEN | **RED** ← defect caught |

`A3` — the isolating mutant holds the status constant at rc 2 (so the live
neighbour stays satisfied) and emits the word `tui` in the `UNRESOLVED` reason,
which is the exact and only quantity line 33 guards. Verified the mutant really
changed the subject: `UNRESOLVED no-lookup no affirmation reached this command
(no tui channel)`, rc unchanged at 2.

| | pristine subject | MUTANT subject |
|---|---|---|
| PRE (dead assertion) | GREEN | **GREEN** |
| POST (revived) | GREEN | **RED** |

## The cure

`python3 scripts/bats-assert-liveness-fix.py tests/cc-cannot.bats` — the
sanctioned fixer, not a hand-imitated repair (it declines at exit 2 rather than
guessing, and its per-class output differs by class). It emitted the
`negation`-class repair, ` || false`, on both lines and nothing else:

```
-  ! printf '%s' "$output" | grep -q "tui"
+  ! printf '%s' "$output" | grep -q "tui" || false
-  ! printf '%s' "$output" | grep -q "read-only"
+  ! printf '%s' "$output" | grep -q "read-only" || false
```

Two lines. No production code changed.

## Verification

**The ratchet:** `python3 scripts/bats-assert-liveness.py --summary` →
`0 dead assertion(s) in 0 of 668 file(s)`, rc 0.

**`tests/bats-assert-liveness.bats`, A/B against a pristine `origin/main`
worktree on this same box, one variable:**

- pristine trunk: 7 reds — 3, 4, 5, 14, 21, **25**, 36
- with this diff: 6 reds — 3, 4, 5, 14, 21, 36

Case **25 (RATCHET) is the only difference**. This diff turns exactly one red
green and moves nothing else.

**`tests/cc-cannot.bats`:** 4 reds before the diff (1, 7, 11, 13) and the same
4 after — no regression. Cases 3 and 10, the two the diff touches, pass in both
arms.

**`scripts/bats-shellcheck-lint.sh tests/cc-cannot.bats`:** rc 0, `clean — 1
suite(s) scanned, 0 blocking finding(s), 0 unanalyzable.`

### Off-box reds that are NOT this item, stated so they are not re-filed

Both residual red sets are environment artifacts of running on a Linux VM, and
both are pre-existing on pristine trunk (measured above, not assumed —
[A "pre-existing red" is a claim, not a measurement]):

- **`bats-assert-liveness.bats` 3, 4, 5, 14, 21, 36** — every one uses
  `LEGACY_BASH=/bin/bash`, which the suite requires to be macOS system bash
  3.2. Here `/bin/bash` is major **5**, so the "dead under 3.2" claims invert.
  Case 3 is the suite's own designed-in guard for exactly this and it fired
  correctly; its header says a box shipping a different `/bin/bash` "fails
  HERE, loudly, instead of inverting a claim downstream." Expect all 6 green on
  the desk.
- **`cc-cannot.bats` 1, 7, 11, 13** — each needs a desk path that is absent on
  this VM, verified individually: `~/.claude/autonomy/approval-queue-drain.sh`,
  `/tmp/approval-queue-drain.sh`,
  `/Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh`,
  `~/.claude/scripts/handoff-fire.sh` — plus a `com.claude.deploy-live` launchd
  agent. All ABSENT here.

`scripts/bash32-parse-lint.sh` returns **rc 2, `NON-VERDICT`** on this box for
the same reason (`/bin/bash is bash 5, not 3.x`). That is a refusal, not a
pass, and is recorded as such — [A gate refusal is not a gate result]. The
repair is a plain ` || false` append with no version-dependent syntax, and the
analyzer that certifies it is calibrated to 3.2 by design.

## Disposition

Not refuted; **cured**. The row closes on this diff, not on a disproof.
