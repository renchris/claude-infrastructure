# STOP_CHAIN_WAVE2 (`a507762b0a0d`) — already cured; the row re-dispatched on a spelling

**Verdict: the work was finished and landed on 2026-09-03. Nothing in it needed re-deriving.** This
document is the evidence for closing the row, plus the cure for the thing that kept it open.

Written off-box (cloud VM, branch `claude/fire-20260904T111242Z-24158-1`) on 2026-09-04. Every trunk
read below was taken after `git fetch --unshallow` — the checkout arrives at depth 50, and inside
that horizon `git merge-base --is-ancestor` and `git log <sha>..origin/main` both answer "not
landed" for "I cannot see that far", which is exactly how a landed cure gets re-derived.

**Dispatcher vintage: EQUAL.** `git rev-parse origin/main:bin/cc-dispatch` =
`646b8a652e71dd5e5e506dffe23725437accea6b`, the blob that composed the brief. The dispatcher that
fired this session IS trunk, so nothing here is a landed-not-live artifact of the deploy layer.

---

## 1. All six waves are on trunk

`git rev-list --count HEAD..origin/main` = 0, so these reads are of trunk itself.

| Wave | Row | Sha in the plan | Ancestor of trunk? |
|---|---|---|---|
| W3 | `c9c3445be29d` | `bf6385171` | yes |
| W1 (session-continue half) | `61a3b40d8695` | `4993f2b55` | yes |
| W4 | `79e2b74796af` | `1416abc10` | yes |
| W1 (goal-inert half) + W2 | `0f4147dcb20b` | `8be512f22` | yes |
| W6 | `d8147be371cd` | ~~`efe703403`~~ → `ad4748584` | **corrected** |
| W5 | `a9ede190ee3b` | ~~`5ecff6f14`~~ → `a7b6d51bd` | **corrected** |

Plus `d691234e5`, the reviewed `tsv-pad-lint` exemption the plan records as its one real gate red.

### The two corrected shas

`efe703403` and `5ecff6f14` are not objects in this repository — not on trunk, not on any ref,
`git rev-parse` fails outright. Both changes ARE landed; only the pointers were wrong. Found by
content, then asserted:

```
git grep 'cc-agent-harvest --session' origin/main -- skills/   → ad4748584 (W6 pointers)
git grep 'CUSTODY_SRC="pane"' origin/main -- scripts/          → a7b6d51bd (W5 attribution)
git merge-base --is-ancestor <each> origin/main                → both exit 0
```

The other four were correct as written. **This is §W6's own lesson turned on the table that records
it:** an evidence pointer nothing can resolve is indistinguishable from evidence that does not
exist, and a reader auditing this plan's DoD ("landed via the project-local `/ship`") would have
found two of six waves unverifiable. The plan now carries the corrected shas and a note saying what
was wrong, per INTEGRATE-never-overwrite.

## 2. Why a finished plan re-dispatched a cloud session

The plan closed itself on 2026-09-03 (`a4b8cb90`) by flipping its frontmatter from `status: open`
to **`status: done`**. `done` is not in the schema, and it is not one of the aliases:

```
scripts/find-plan.sh plan_status():
  case "$val" in in_progress) val=in-progress ;; completed) val=complete ;; esac
  case "$val" in open|in-progress|complete|superseded) … ;; *) unknown ;; esac
```

So `plan_status` answered `unknown`. `plan-phase-scan.sh --falsify` has two arms, and both then
declined to retract:

- **arm (a)** retracts only on `complete`/`superseded` — never reached.
- **arm (b)** retracts only when no level-≥2 section is `PENDING`. Seven were, and every one is
  narrative the plan wrote *about being finished* ("OUTCOME — all six closed", "Four things the
  plan did not anticipate", "One gate red, and it was real"). The scanner marks a heading DONE from
  a DONE token or a commit hash *in the heading*; a section describing completion carries neither.

Measured through the real probe, holding everything else constant:

```
status:done         plan_status=unknown     falsify=<silent>   exit=1   ← never retracts
status:complete     plan_status=complete    falsify=FALSIFIED  exit=0
status:completed    plan_status=complete    falsify=FALSIFIED  exit=0   ← alias already existed
status:superseded   plan_status=superseded  falsify=FALSIFIED  exit=0
status:open         plan_status=open        falsify=<silent>   exit=1   ← correct, plan is open
```

**The silence is the defect.** `unknown` fails toward "still open", which is the right default for a
plan nobody has classified and the wrong one for a plan that classified itself. Nothing warns:
the row stays open, the falsifier keeps declining to retract, and the desk keeps dispatching. This
is precisely the `a50e6ab779e8` pathology the brief names — a title describing work that finished
long ago — reached by a different route.

## 3. The cure

**The row's own fix:** `docs/plans/STOP_CHAIN_WAVE2.md` frontmatter → `status: complete`. The probe
now prints `FALSIFIED` and exits 0, so the row retracts.

**The generator fix:** `done` added as an alias for `complete` in all three copies of the status
grammar, which are required to agree and are commented as such (*"Kept in sync with
setup-plan-symlinks.sh and validate-plan-structure.sh"*):

| File | Change |
|---|---|
| `scripts/find-plan.sh` | `case … in done\|completed) val=complete` |
| `hooks/setup-plan-symlinks.sh` | awk: `if (v=="completed" \|\| v=="done") v="complete"` |
| `hooks/validate-plan-structure.sh` | accepted alternation gains `done` |

This is the existing alias mechanism, not a fifth state: `completed` and `in_progress` are already
aliased for exactly this reason. `done` is the spelling this repo uses for the terminal state
everywhere else — `cc-backlog done`, "row done", the plan's own OUTCOME heading — so the collision
is structural rather than a typo. The **canonical four stay the only values advertised** in the
validator's author-facing messages; `done` is accepted so a plan spelled that way is never
simultaneously complained about by one oracle and read as `unknown` by another.

Census across all 76 plans on trunk: 31 `open`, 30 `complete`, 13 `in-progress`, 1 `superseded`,
**1 `done`** — this plan. One instance, and it cost a full cloud dispatch.

### Red-proven, per the plan's own DoD

Each suite carries a control that is green on both branches (so the harness is provably wired) and
an arm that moves. Run with bats 1.11.0:

```
tests/find-plan-list-open.bats     11/11   arm: "'done' is terminal, not UNKNOWN"        red on trunk
tests/plan-index.bats              15/15   arm: "alias 'done' is terminal, not open work" red on trunk
tests/validate-plan-structure.bats 14/17   arm: "alias 'done' draws no status complaint"  red on trunk
```

Each also gets a negative control (`donezo` / `wibble` still reads UNKNOWN, still complains) so the
alias cannot have been widened into a catch-all.

`shellcheck -x` clean on all three changed shell files. `bats-shim-parity-lint`,
`bats-kill-guard-lint`, `bats-testname-eval-lint`, `bats-shellcheck-lint`, `pipefail-sigpipe-lint`,
`tsv-pad-lint` and `bats-assert-liveness.py` all exit 0.

## 4. Pre-existing and NOT mine: the validator crashes on Linux

The 3 reds in `validate-plan-structure.bats` above (`NEW authored plan lacking status`, `NEW plan
with an INVALID status value`, `pre-existing via old mtime`) **reproduce identically on pristine
trunk in this environment** — checked out and run before any edit of mine. They are not caused by
this change and are not driven here.

Cause, since a bare "pre-existing red" is not a diagnosis. `hooks/validate-plan-structure.sh:55`:

```sh
mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
age=$(( now - mt ))
```

`stat -f %m` is the BSD/macOS form. GNU `stat` reads `-f` as `--file-system` and then takes `%m` as
an operand, which fails; it prints a **multi-line filesystem report on stdout** and exits 1. So
`2>/dev/null` hides only the error line, `|| echo 0` appends `0` to that report, and `$(( now - mt ))`
evaluates a value beginning `File:` — an unset identifier under `set -u`:

```
validate-plan-structure.sh: line 56: File: unbound variable      (exit 1)
```

**Consequence:** on any Linux runner the status-schema gate is dead for a non-git plan directory —
it neither blocks nor warns, it aborts. The desk is macOS, where `stat -f %m` is correct, so this
has never been visible there. The git branch of `is_new_plan` returns before reaching `stat`, so
plan dirs inside a repo are unaffected — which is why the rest of the suite passes.

Not fixed here: it is outside this row's frozen scope, and the repair changes what a *blocking*
gate does on a platform it currently no-ops on (plans that today pass silently would start failing
exit 2). That deserves its own row and its own decision, not a drive-by in a docs correction.

**It did shape the tests.** An exit-code-only assertion in that suite passes vacuously on Linux —
green with the fix and without it — the silent-vacuous-pass trap §W5 of the plan names by hand.
The new alias tests therefore drive their fixtures through a **git-backed** directory and assert on
the emitted message, so they discriminate on either platform.

---

## What this row costs, restated

The plan's stated purpose was to test whether the backlog workflow "files more than it solves", and
§W6 found a row asking to build a tool that had shipped 25 days earlier. This row is the same
failure one layer up: the work was done, landed, and green, and the store could not tell, because a
finished plan spelled its terminal state with a word three parsers had never been taught. A
completion no consumer can read is indistinguishable from work not started — which is exactly what
`docs/plans/CLOUD_OBSERVABILITY.md` §4.1 says about a cloud session that pushes nothing, and it is
the same bug about a different object.
