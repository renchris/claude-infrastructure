# A finished plan re-dispatched itself, and the cause was one word — 2026-09-03

**Verdict on backlog row `a507762b0a0d`** ("advance STOP_CHAIN_WAVE2 — driving the six filed
Stop-chain defects to completion"): **already cured.** All six waves landed on 2026-09-03, the day
the plan was written. The row stayed open because the plan's frontmatter said `status: done`, and
`done` is not a word any consumer of plan status knows.

Written from a cloud VM dispatched against this row. The dispatch itself is the measurement.

---

## 1. The six waves are on trunk

The plan's OUTCOME table records the shas its waves landed under. Four resolve; two do not, because
the project-local `/ship` replayed them onto trunk under new shas. Asserted with
`git merge-base --is-ancestor <sha> origin/main`:

| Wave | Row | OUTCOME table says | On trunk as | Ancestor of `origin/main` |
|---|---|---|---|---|
| W3 | `c9c3445be29d` | `bf6385171` | `bf6385171` | yes |
| W1 (session-continue half) | `61a3b40d8695` | `4993f2b55` | `4993f2b55` | yes |
| W4 | `79e2b74796af` | `1416abc10` | `1416abc10` | yes |
| W1 (goal-inert half) + W2 | `0f4147dcb20b` | `8be512f22` | `8be512f22` | yes |
| W6 | `d8147be371cd` | `efe703403` — **no such object** | `ad474858` | yes |
| W5 | `a9ede190ee3b` | `5ecff6f14` — **no such object** | `a7b6d51b` | yes |

The gate exemption the plan describes (`d691234e5`, the `tsv-pad-lint` discharge) is also an ancestor.

Content-verified rather than sha-verified, per the repo's own rule that a count proves nothing:

- **W6** — `git grep -n cc-agent-harvest origin/main -- skills/` returns the two pointer lines the
  plan prescribed, at `skills/agent-teams/SKILL.md:82` and `skills/research-subagents/SKILL.md:254`.
- **W5** — `a7b6d51b` carries `scripts/wrap-ledger.sh` (+96), `tests/wrap-ledger.bats` (+101) and
  `tests/wrap-ledger-memo.bats` (+33, the pane-id-in-memo-key trap §W5 flagged), plus the
  `CLOSE_INTEGRITY_2026-08-10.md` update the `CUSTODY_SRC` three-state oracle required.

**A sha-only check would have called two of six waves missing and re-derived landed work.** The
OUTCOME table's shas are the pre-land branch shas; the land rewrote them.

## 2. Why the row stayed open

The plan declared itself finished. Its frontmatter, on trunk:

```
---
status: done
---
```

`done` is not in the vocabulary. Four places decide whether a plan is finished, and none accepted it:

| Site | Accepts | Aliases |
|---|---|---|
| `scripts/find-plan.sh` `plan_status()` | `open in-progress complete superseded` | `completed`→complete, `in_progress`→in-progress |
| `hooks/validate-plan-structure.sh` `has_valid_status()` | the four, plus `in_progress`, `completed` | — |
| `hooks/setup-plan-symlinks.sh` (one-pass awk) | closes on `complete superseded` | `completed`→complete |
| `bin/cc-discover` | delegates to `--falsify` → `find-plan.sh --status` | inherits |

Reproduced against trunk bytes:

```
$ bash scripts/find-plan.sh --status docs/plans/STOP_CHAIN_WAVE2.md
unknown
$ bash scripts/plan-phase-scan.sh docs/plans/STOP_CHAIN_WAVE2.md --falsify; echo $?
1
```

`unknown` is **never hidden** — that is a deliberate anti-FM1 property, and it is correct. But it
means an unrecognised word is indistinguishable from a missing one, so a plan that declared itself
finished enumerated as open.

The stored falsifier could not retract it either. Clause (a) keys on `complete|superseded`; with the
word unrecognised it fell through to clause (b), which scans remaining sections — and the OUTCOME
headings carry no `DONE` token, so it reported **7 of 15 sections PENDING** on a plan whose every
wave had landed. The two clauses failed in series for the same single reason.

`cc-discover`'s C2 critic then minted a `plan-open` row from the plan's H1, which is why the row's
title names work that finished before the row existed.

### The corpus says this was a typo, not a dialect

31 closed plans in `docs/plans/`: **30 say `complete`, 1 said `done`.**

### The gate that should have caught it never looked

`validate-plan-structure.sh` does gate the vocabulary — but `is_new_plan()` returns "not new" for a
git-tracked file, and the plan was already tracked when its status changed. A **transition** to an
invalid status takes the pre-existing branch, which warns and never blocks. The warn is an
`additionalContext` advisory. Left as-is: retro-blocking the corpus is the thing that branch exists
to prevent.

Note the validator's own warn text, verbatim: *"add a status: line so find-plan.sh --list-open can
classify it (open vs. **done**)."* The gate uses the word it rejects as a value.

## 3. What was changed

Two commits, both on this branch.

**`f3161344`** — `status: done` → `status: complete` in `docs/plans/STOP_CHAIN_WAVE2.md`. This alone
dissolves the row. Red-proof: controls `ACCOUNT_AGNOSTIC_AGENT_STATE.md` and `AUTONOMY_DISPATCH_V2.md`
exit 1 on both branches; the subject moves exit 1 → exit 0 / `FALSIFIED`.

**`4aa7afe7`** — `done` accepted as an alias in all three encoders. Deliberately accepted and **not
advertised**: the validator's two messages still name only the canonical four, exactly as `completed`
and `in_progress` have always been accepted and never recommended. The three copies had to move
together — teaching the gate alone would be strictly worse than the status quo, since it would wave
the plan through while the enumerator still read `unknown`.

Red-proof per encoder, control green on **both** branches and the arm moving:

```
find-plan-list-open       11/11   arms 9,11 red with find-plan.sh reverted
                                  control 10 (unrecognised word STILL UNKNOWN) green both
validate-plan-structure   13/16   arm 14 red with the hook reverted
                                  controls 15,16 green both
setup-plan-symlinks awk           closed count 1→2 over 4 fixtures
                                  `open` and `wibble` never close on either branch
```

The validator arms are driven through the **tracked** branch, not the NEW branch, for a reason
recorded in the test file: the NEW branch's discriminator is exit 2 vs exit 0, and on Linux that path
cannot fail (§5), so an arm placed there would be a vacuous pass — the trap `STOP_CHAIN_WAVE2.md` §W5
recorded when it found `tests/wrap-ledger.bats`'s argument-blind stubs would have passed rather than
broken.

`hooks/setup-plan-symlinks.sh` has no bats suite in this tree, so its arm is verified by executing the
exact awk program against fixtures rather than by assertion. Its header comment now names the
three-copy sync obligation the other two carry.

`shellcheck -x` clean on all three. `bats-shellcheck-lint`, `bats-assert-liveness`,
`bats-kill-guard-lint` and `bats-testname-eval-lint` clean on both edited suites — the first of those
caught a real SC1010 in the new code (`f="$(tracked_plan done)"`, where the bare word parses as the
loop keyword), fixed by quoting.

### The whole selected gate, with every failure attributed

`scripts/gate-select.sh origin/main..HEAD` selects **222** suites — the transitive closure, mostly
because `setup-plan-symlinks.sh` is a SessionStart hook. All 222 were run on this branch, and every
suite that failed was then re-run on a detached `origin/main` worktree on the same box:

```
222 suites run · 58 with failures · 58 identical to trunk · 0 regressions
```

Two suites differed on a single run — `deathwatch-watchfile` (branch 8/1 vs trunk 7/3) and
`tsv-field-collapse` (branch 33/1 vs trunk 32/2). In both the *branch* was the healthier side, and in
both a 3× repeat run gave byte-identical results on branch and trunk (8/1 and 32/2 respectively). They
are concurrency flake from two suite runners sharing the box, not signal.

The large pre-existing red baseline on this VM (`cc-classify` 19/68, `cc-dispatch-v2` 0/17,
`operator-readout` 61/43, …) is Linux-vs-macOS environment, not trunk breakage — these hooks target
the operator's desk. It is reported here only to make "identical to trunk" a checkable claim.

Independent of the suites, the alias is provably **inert against all existing state**: the only
`status: done` fixture anywhere in the tree is the one added by this change, and the only plan in the
corpus carrying the word is the one commit `f3161344` renames. Its sole effect is on future typos.

## 4. Dispatcher vintage

```
$ git rev-parse origin/main:bin/cc-dispatch
646b8a652e71dd5e5e506dffe23725437accea6b
```

**EQUAL** to the blob that composed this session's brief. The dispatcher that fired this VM *is*
trunk, so nothing here is confounded by a stale deploy layer: the row was dispatched by current code,
against a premise current code could not refute.

## 5. A pre-existing red this session did not cause and did not fix

`tests/validate-plan-structure.bats` tests 1, 3 and 5 fail on Linux. Cause: `is_new_plan()` calls

```sh
mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
```

`stat -f` is BSD/macOS syntax. On GNU coreutils `-f` means *"file system information"* and errors, so
`mt=0`, the computed age is ~56 years, and `is_new_plan` returns "not new" for **every** non-git path.
The NEW-plan gate therefore fails **open** on Linux: an invalid-status new plan is warned instead of
blocked.

Attribution proven, not assumed — substituting `stat -c %Y` in a scratch copy takes the suite to
**13/13**, and the trunk worktree reproduces the identical failure set `[1 3 5]`.

Not fixed here: it is outside this row's frozen scope, it changes a **blocking** PostToolUse gate, and
it is not a defect on the operator's macOS desk where these hooks run. **It is worth filing** — the
portable form is `stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0`, which is
byte-identical in behaviour on macOS (GNU form fails, BSD form answers) and can only ever make the
gate *stronger* on Linux, never weaker, since the current failure mode already yields the weak branch.
It could not be filed from here: `cc-backlog` writes nothing off-box.

It is also **not causal to this row.** The `done` word took the tracked branch and never reached
`stat`.

## 6. The finding that outlives the row

`STOP_CHAIN_WAVE2.md` §W6 recorded that a shipped tool nothing references is indistinguishable from a
tool that does not exist. This row is the same shape one layer down: **a plan that declares itself
finished in a word the machine does not parse is indistinguishable from a plan still holding work** —
and the cost is not a stale row, it is a dispatched VM.

Three properties combined to make one typo durable:

1. **Unknown is never hidden.** Correct as a policy, and it converts any unrecognised word into
   "open" rather than into an error anyone sees.
2. **The falsifier's two clauses fail in series on the same input.** Clause (b) exists precisely to
   catch a plan whose *status* is stale — but here the status was not stale, it was unparseable, and
   clause (b)'s independent evidence (unmarked OUTCOME headings) happened to agree with clause (a)'s
   non-answer. Two clauses, one failure.
3. **Nothing reports an unparseable status to its author.** `unknown` is a valid enum member that
   flows silently through `--list-open`, the C2 critic and the dispatcher. The one component that
   *would* have complained — the validator — is disarmed on exactly the edit that introduces the
   problem, because changing a tracked plan's status is never a "new plan".

The generalisable rule: **where a vocabulary is enforced in more than one place and a miss degrades to
a valid-looking default, the default must be loud.** `unknown` is the right value; being silent about
it is what cost a dispatch. Accepting `done` closes the observed instance. It does not close the class.
