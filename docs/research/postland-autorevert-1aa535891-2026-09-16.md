# A post-land AUTO-REVERT that was right about guilt, wrong about trunk, and did not fail

2026-09-16 · cc-backlog `9796d76a14da` · measured off-box on a Linux cloud VM
(bats 1.13.0, shellcheck 0.9.0), base `cfb6c91e`, verified against `origin/main` at `5edaeb53`.

The row reads:

> post-land AUTO-REVERT FAILED(step=land rc=124): `tests/deploy-link-parity.bats` @ `1aa535891cd7`
> (revert `c9eb836d3b52e088176b8a56eb6525211504fcf1` on `postland-revert-1aa535891cd7`)

Two of its three load-bearing claims are false, and they fail in opposite directions.

---

## 1. The premise is REFUTED: the revert did not fail, it landed

`rc=124` is a timeout. `scripts/postland-verify.sh:596` sets `SHIP_TO="${CC_POSTLAND_SHIP_TIMEOUT_S:-900}"`
and the land runs as `( cd "$wt" && bounded "$SHIP_TO" "$REPO_SHIP" )`, so 124 means *our own 900 s
bound fired on the land lane*. The FAILED page renders that as a statement about trunk:

```
trunk is STILL RED; deploy stays pinned to the last green stamp.
```

That line is an **inference from an exit code**, never a read of trunk. Measured:

```
$ git merge-base --is-ancestor c9eb836d3b52e088176b8a56eb6525211504fcf1 origin/main ; echo $?
0                                  # the revert IS on trunk
$ git log --format='%h %p %ci' -1 c9eb836d
c9eb836d 00f67bbc 2026-09-15 23:53:49 -0500
```

The bound killing `ship-land` does not mean nothing landed. This repo's own corpus already records
why — *"ship-land refuses a second land from one worktree while the first is in flight, and its
post-push stranded sweep runs for minutes AFTER `land-verify` has already printed success — so a log
showing `HEAD -> main` is not the process exiting. Await the pid, not the push line."* A `bounded`
kill lands inside exactly that window. The marker comment at the PROVISIONAL write reasons the other
way (`land_exit=99` … *"non-zero, so it reads as FAILED (accurate — nothing landed)"*); that
inference is what this incident falsifies for the timeout case.

**A revert believed failed and actually landed is the worse half of the pair.** A revert known to
have landed pages loudly (C37, `postland-reverted-*.page`, *"a commit was removed from trunk
unattended"*). This one wrote the FAILED page instead, so the fix came off trunk with the only
artifact about it asserting the opposite, and nobody looking.

## 2. The conviction was CORRECT — and that is not the same as the revert being right

Run at each tree, one variable per arm, plan line asserted every time
(`CC_BATS_QOS=off bats tests/deploy-link-parity.bats`):

| tree | what it is | result |
|---|---|---|
| `cb691cb6` = `1aa535891^` | the culprit's parent | `1..66` · **66 ok** · rc 0 |
| `1aa535891` | the culprit | `1..66` · **64 ok, 2 not ok** · rc 1 |
| `00f67bbc` = `c9eb836d^` | trunk the instant before the revert, culprit still present | `1..66` · **66 ok** · rc 0 |
| `origin/main` | trunk today, revert applied | `1..66` · **66 ok** · rc 0 |

The two reds at the culprit:

```
not ok 42 every deploy class install.sh globs is either forward-walked or declared NOT-PER-FILE
not ok 43 the coverage arm can FIRE — a new install.sh class in neither set is reported unclaimed
```

Parent green, culprit red — so the FAILED page's own guilt ritual (*"culprit RED + parent GREEN =>
guilty, and the do: line below is right"*) returns **GUILTY**, correctly. `1aa535891` added
`scripts/*.py` to install.sh's deploy glob and did not extend `deploy-link-parity.sh`'s forward walk,
which is precisely what case 42 exists to catch.

**And the revert was still wrong, because the red was already cured 72 minutes before it.**

```
1aa535891  2026-09-15 08:15:23  fix(install): scripts/*.py never deployed …      ← culprit
9ff56eed6  2026-09-15 22:41:13  fix(deploy): the auditor never walked scripts/*.py …  ← CURE
c9eb836d3  2026-09-15 23:53:49  Revert "fix(install): scripts/*.py never deployed …"  ← revert
```

`9ff56eed` is the only commit in the range touching `scripts/deploy-link-parity.sh`; it adds one
forward-walk line and its own body says *"Both cases green after the one-line walk, 66/66."* Row 3
of the table above is the independent confirmation: the commit the revert was **composed on top of**
already had the convicted suite at 66/66.

`git merge-base --is-ancestor 9ff56eed63e8563649b2a95b5f9d735adf1799f0 origin/main` → 0.

## 3. What the revert cost

`install.sh`'s top-level scripts loop went back to `for script in "$REPO_DIR"/scripts/*.sh`, leaving
**35** top-level `scripts/*.py` undeployed. Among them `scripts/kitty-pane-title-overlay.py`, which
`config/kitty.conf:436` and `:486` bind by **absolute live path**:

```
map cmd+shift+b combine : launch … ${HOME}/.claude/scripts/kitty-pane-title-overlay.py off --all : …
map cmd+opt+b   combine : launch … ${HOME}/.claude/scripts/kitty-pane-title-overlay.py toggle
```

That is the original incident verbatim — a live chord executing a stale one-off copy nothing
updates, while `deploy-live.sh` reports "at trunk tip". The sibling `kitty-pane-title-toggle.sh` on
the same two lines *is* deployed, because it is `.sh`; only the `.py` half is dark.

Two second-order costs, both quiet:

- **Trunk was left internally inconsistent.** `9ff56eed` survived the revert, so
  `deploy-link-parity.sh` per-file walks a class `install.sh` no longer deploys. Case 42 quantifies
  in one direction only (*every class install.sh globs is walked*), so an auditor walking **more**
  than the deployer deploys violates nothing and the suite stays green over it.
- **An expired justification was restored as a standing prohibition.** `deploy-parity-assert.sh` is
  back at `scripts/*.py) want=0`, carrying the 2026-08-31 census comment that ends *"do not add
  scripts/\*.py to install.sh on the strength of this arm"* — with the falsification `1aa535891` had
  recorded beside it deleted. The next reader inherits a refuted premise reading as a decision.
  (Same shape as the corpus rule *a negative decision record whose premise expires silently converts
  a deferral into a permanent block*.)

## 4. The gap: the FAILED page asks about guilt, never about the tip

`auto_revert()` guards the culprit's **ancestry** (`trunk_state`, the 2026-08-09 orphaned-sha fix)
and `bisect_culprit_confirm_ok` re-measures *the failing test fails AT the culprit*. Both are sound
and both return the right answer here. Neither asks the question this incident turns on: **is the
suite still red at trunk tip?**

The INERT page does ask it — *"is `$ftest` still red on trunk? a green there makes this moot"*
(`:2968`). The FAILED page, which is the only one that asks the operator for irreversible hand-work
(`do: … worktree add … postland-revert-… && … ship-land`), does not. Its comment block even cites
the near-identical `97758a6323ee` case, where the red *"was cured FORWARD by 8460f5ac9"* and
*"reverting as prescribed would have taken a good commit off trunk"* — there the revert conflicted
and applied nothing, which the corpus already records as the good outcome. Here it applied.

The remedy is one line on the FAILED page, mirroring the INERT page's opener, emitted **above** both
`do:` arms (that page's own rule: *"ORDER IS THE PROPERTY, not presence: a check printed BELOW the
instruction it qualifies is not a check"*). Filed as a separate item rather than taken here: it
changes a live actuator's page text, and `tests/postland-verify*.bats` pins that page's line
ordering, so it is its own change with its own gate surface — not this row's payload.

**The row's own falsifier could not have caught this either.** `postland-verify.sh:3315` states it
outright: *"the backlog row's `--falsify-red` asks 'is the red gone?', which a revert makes true
whether or not the culprit was guilty."* The probe the dispatcher ran returned exit 1 (silent,
NOT REFUTED) — the safe direction, and here carrying no information at all.

## 5. What was done

Re-landed `1aa535891` by reverting `c9eb836d`. All three paths verified byte-identical to the
culprit's tree (`git diff 1aa535891 -- <path>` empty for `install.sh`,
`scripts/deploy-parity-assert.sh`, `tests/deploy-parity.bats`). Nothing but the revert had touched
them since, so there is no superseded half to preserve:
`git log --oneline 1aa535891..origin/main -- <the three paths>` names only `c9eb836d`.

**Attribution of the green**, because a green that is not attributed is not evidence. With the
re-land applied: `deploy-link-parity` 66/66, `deploy-parity` 107/107 (matching `1aa535891`'s own
claim). Mutant — delete `9ff56eed`'s single forward-walk line from `scripts/deploy-link-parity.sh`,
anchor asserted unique (1 site) and file restored after — dies on **cases 42 and 43 and nothing
else**, reproducing the post-land RED exactly. So the green is caused by the cure, not by luck, and
the suite is not decorative on this axis.

**Gate**, both arms wherever anything was red:

```
deploy-link-parity        66/66     deploy-parity             107/107
ms365-reply-splice        18/18     install-stale-refusal      10/10
install-worktree-refusal   8/8      install-wire-hooks           7/7
land-lint-scope-derived   13/13     install-templatedir-home    10/10
gate-select               45/45     install-staged-plist         6/6
install-mirror-symlink     7/7      install-fleet-activation     9/9
config-mirror-isolate     12/12     completion-assert        138/138
install-skills-nested      7/7
install-resident-reload   10/15  ← pre-existing          deploy-live  165/168  ← pre-existing
```

The two red suites are **platform-bound (launchd) and not caused by this diff**: their failing-test
*name sets* are byte-identical at pristine `origin/main` and under the re-land, `diff`ed rather than
counted. `shellcheck -S warning` on `install.sh` and `scripts/deploy-parity-assert.sh`: 0 findings,
identical in both arms.

## 6. Carry-outs

1. **A land bound firing is not evidence that nothing landed.** Derive a revert's outcome by reading
   trunk back (`merge-base --is-ancestor "$rev" origin/main` after a fetch), never from the land
   lane's exit code. `rc=124` in particular is our own timer, and the push may already have taken.
2. **A correct conviction does not license a revert.** Guilt is a fact about the culprit's tree; the
   decision to revert is a fact about the **tip**. A red cured forward leaves the first true and the
   second false, and every guard we have re-measures only the first.
3. **Reverting one half of a two-commit repair leaves the tree inconsistent in a direction no test
   quantifies over.** The deployer and its auditor are mirrors by design; a revert can desynchronise
   them, and a coverage assertion written in one direction stays green across it.
4. **A revert restores deleted prose as well as deleted code** — including a justification that a
   later commit had refuted in place. Reverting a fix can reinstate the argument against it.
