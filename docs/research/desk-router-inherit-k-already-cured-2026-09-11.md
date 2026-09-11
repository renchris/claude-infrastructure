# cc-backlog `1f6208064577` — ALREADY CURED on trunk; verdict, not a re-derivation

**Date:** 2026-09-11 · **Verdict:** DONE. The cure is `9465e011`, an ancestor of `origin/main`.
**Dispatched:** cloud fire `20260911T074910Z-60161-1`, i.e. **84 minutes after the cure landed.**
**Written off-box** (Anthropic-managed VM); no desk state was readable from here.

---

## 1. The verdict, and the two assertions behind it

| | |
|---|---|
| cure commit | `9465e01191202f9dab518637cde49a1037754e69` |
| subject | *fix(router): inherit the last sweep's census so a starved ps stops excluding the whole fleet* |
| `git merge-base --is-ancestor 9465e011 origin/main` | **rc 0 — ANCESTOR** |
| committed to trunk | **2026-09-11T06:24:35Z** |
| this session fired | **2026-09-11T07:49:10Z** (+84 min) |
| trunk at read | `4d7a65d7` (2026-09-11T07:11:37Z), `HEAD..origin/main` = **0** |

The commit closes the row in its own trailer — `Closes cc-backlog 1f6208064577` — and its DoD line
names this item's own reference, `docs/research/desk-router-abstention-2026-09-01.md § NOT shipped`.
It carries the whole sketch: `inherit_k` + `k_panes`, the `k_stale`/`k_stale_as_of` stamp, the
fourth `k_src` value `panes-stale`, `k_stale_s=` in route-meta, and 215 lines across
`bin/claude-accounts` with 380 lines of tests in three suites.

**I re-derived nothing and changed no shipped byte.** This file is the only artifact.

## 2. The read that would have said NEVER LANDED — and why the checkout mattered

Two traps sat in front of this row, and both point the same way (toward re-deriving a landed cure):

**(a) The checkout arrives SHALLOW.** `git rev-parse --is-shallow-repository` printed `true` at
depth 50. Every trunk read below is wrong in one direction only inside that horizon —
`--is-ancestor` exits 1 both for *no* and for *I cannot see that far*. `git fetch --unshallow` ran
before any read here; without it the cure is invisible and the correct-looking move is to build it
again.

**(b) The sha the cloud session reported is NOT the sha that landed.** The commit's own trailers say
`Original-commit: 3fbe58900970662df9dad2cbf775d789ac2bf031`, `Original-branch:
claude/fire-20260904T170832Z-32559-1`. Measured:

```
9465e011…  ANCESTOR-OF-TRUNK
3fbe5890…  OBJECT-ABSENT / NOT-ancestor   ← the land rebased it; patch-id and sha both moved
```

An ancestry or landedness check keyed on the sha the *worker* reported reads **never landed,
permanently**, however many times the row is re-dispatched. This is
[[cited-sha-may-not-survive-the-land]] recurring, and it is why the verification below is by
CONTENT and BEHAVIOUR rather than by ref.

## 3. What I actually ran

`bats` is absent on this VM, so the three shipped suites could not be executed. The cure's core is
pure Python, so it was exercised directly against `git show origin/main:bin/claude-accounts` —
**14 arms, each written so that the property could fail**, since a probe with only happy paths
proves nothing.

| arm | asserts | result |
|---|---|---|
| P1 ×4 | a starved census inherits the prior count; `k_panes` charges it; `k_src` = `panes-stale` | ok |
| P1c ×3 | **control** — with nothing to inherit, still `None` / `unmeasured` | ok |
| P2 ×3 | **the floor** — past the 600 s grace both bounds refuse, at write *and* at charge | ok |
| P3 | **the load-bearing half** — `row["k"]` stays `None`, so `heal()`'s rotation gate and `handoff-fire.sh`'s relogin gate keep refusing | ok |
| P4 ×3 | re-inheritance carries the **original** `k_stale_as_of`; an expired chain does not renew | ok |

`GREEN: all arms pass, including every refuting arm` (rc 0).

**Positive control — the probe has power.** Green on trunk is an equivalence guard unless the same
probe can go red, so it was re-run against the cure's own parent `9465e011^`. It cannot even load:

```
AttributeError: module 'ca' has no attribute 'K_GRACE_S'

symbol          parent  trunk
K_GRACE_S            0      5
def inherit_k        0      1
def k_panes          0      1
def _k_stale_s       0      1
panes-stale          0      6
```

The mechanism is wholly absent pre-cure and wholly present post-cure. Suites on trunk:
`claude-accounts.bats` (15 `@test`, 34 cure refs), `claude-accounts-core.bats` (94, 6),
`account-fact-derivation.bats` (17, 9).

## 4. Why a cured row was still dispatched — candidates, not a conclusion

The backlog store lives on the operator box and is unreadable from here, so **the closing mechanism
is UNDETERMINED** and is deliberately not asserted. What *is* measurable from trunk:

- The work was authored on a cloud branch fired **2026-09-04** and landed **2026-09-11T06:24:35Z** —
  a **7-day gap** between a complete, tested cure existing on a branch and it reaching trunk. For
  that week the row was correctly open while the cure was finished.
- Across that same window the research doc's status block already read **"SHIPPED 2026-09-04"**.
  **A doc status block dates AUTHORSHIP; a backlog row closes on the LAND.** Both readers are right
  and they disagree: the doc says done, the row says open. Neither is a defect — they answer
  different questions, and this row is what it looks like when the gap between them is a week long.
- My fire is 84 min *after* the land, so any dispatch snapshot taken before 06:24:35Z would name
  this row legitimately.
- Combined with §2(b): if anything downstream confirms landedness against the worker-reported
  `Original-commit`, it cannot ever observe this cure. That is a live candidate, not a finding.

**Dispatcher vintage, per the brief's own check.** The bytes that composed this brief are
`bin/cc-dispatch` blob `9109de61dc7add48cd94809d54e591af0bfe9021`; trunk carries
`e61bcbfc657a44a20b03d7d52ab3e921fd138242`. **DIFFERENT — the dispatcher that fired me is BEHIND
trunk.** Stated rather than assumed: this is a convergence fact about the deploy layer, and it does
not bear on the correctness of the cure read above. Landed is not live, and *"the fix already
landed"* does not answer *"did the fix run"*.

## 5. Disposition

Close `1f6208064577` **done**, evidence `9465e011` — asserted an ancestor of `origin/main`, verified
by content and by a positive-controlled behavioural probe. No code change is wanted; the item's
§ *NOT shipped* block in `desk-router-abstention-2026-09-01.md` already carries its own status
update naming `inherit_k` + `k_panes` and the two things that came out differently from the sketch.

One thing to carry forward, cheap and general: **assert landedness against the sha on TRUNK, never
against the sha the worker reported** — a rebased land moves both the sha and the patch-id, so the
worker's own citation is the one identifier guaranteed to go stale at the moment the work succeeds.
