# The cloud return/land arm's 08-17 step — real, and separately, the probe that could not see it

Backlog `f85fce7c26f5`. Measured 2026-08-25 from a **cloud VM** (this repo's own off-box lane), so
every figure below comes from `origin` and from the commit graph. Nothing here reads the operator's
box, and §3 says exactly which question that leaves open and the one command that settles it.

The item carried two claims and they needed separating, because one of them is a candidate
explanation for the other:

- **A.** the return/land arm died at `2026-08-17T09:12:05Z`; push rate stepped **81% → 33%**
- **B.** 54 landed branches were pruned on 08-19, and a raw branch-presence probe scores those
  identically to never-pushed — so the step could be an artifact of the instrument

**Both are true, and B does not explain A.** They are independent defects that happened to land in
the same week, which is why the item read as one thing.

---

## 1 · A is real — two methods, one of which the pruning confound cannot touch at all

### 1.1 The pruner's own manifest, written at the time, by patch equivalence

The 54 branches of claim B were not deleted by an outside hand: `scripts/branch-prune-landed.sh`
(`d40b04fa`, first run **2026-08-19**) deleted them, and it **recorded every branch it considered
with a verdict** — `docs/research/branch-prune-manifest-2026-08-19.tsv`. That manifest is on trunk,
it is the strongest evidence available, and it needed no re-derivation:

- **54 `claude/fire-*` branches DELETED**, exactly the item's number, plus one `wt-` branch.
- Its test is `git cherry` — **patch equivalence, never ancestry** — which is the right instrument
  here, since `ship-land` rebases and rewrites every object before pushing.
- It holds anything with a tip younger than 6 h, so the last day is censored by design.

Landing rate by fire day, over **all** branches present at prune time (`DELETED` = every commit
patch-equivalent on trunk):

| fire day | 08-11 | 08-12 | 08-13 | 08-14 | 08-15 | 08-16 | 08-17 | ‖ | 08-18 | 08-19 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| branches | 8 | 12 | 13 | 13 | 17 | 8 | 10 | ‖ | 6 | 5 |
| landed | 6 | 9 | 7 | 10 | 11 | 4 | 5 | ‖ | **1** | **0** |
| rate | 75% | 75% | 54% | 77% | 65% | 50% | 50% | ‖ | **17%** | **0%** |

**50–77% through 08-17, then 17%.** Discount the 08-19 column — the 6 h hold censors it — and the
step still stands on 08-18 alone, against a floor of 50% over the preceding week. This is the same
step the item reports as 81% → 33%, seen through a different instrument, on a different population,
computed by a different program at a different time.

### 1.2 Corroboration on a population the confound cannot touch

The confound in B works in exactly one direction: pruning **removes landed branches from the
remote**. So restrict the census to branches that **still exist** and the artifact is gone by
construction — whatever pruning did, it did not do it to these. (This is a snapshot taken on 08-25,
six days after §1.1's, so it also catches anything that landed late.)

Landing in this repo **re-authors** (the lander rebases; a branch's own sha never appears on
trunk), so ancestry and `git cherry` are both useless here. Subject equality survives a re-author
and is the discriminator used below. Commits are restricted to those authored at or after the
branch's own fire timestamp, so a branch's inherited history is not counted as its work.

```bash
git fetch --unshallow origin                       # a cloud clone is shallow; ancestry is garbage until this
git fetch origin 'refs/heads/claude/*:refs/remotes/probe/*'
git log origin/main --format='%s' > /tmp/main-subjects
# per branch: commits authored since its fire stamp whose subject is absent from trunk
```

**Stranded own-work commits on surviving `claude/*` branches, by fire day:**

| 08-11 | 08-12 | 08-13 | 08-14 | 08-15 | 08-16 | 08-17 | ‖ | 08-18 | 08-19 | 08-20 | 08-21 | 08-22 | 08-23 | 08-24 | 08-25 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 3 | 2 | 3 | 0 | 1 | 1 | 1 | ‖ | 4 | 18 | 9 | 5 | 6 | 5 | 36 | 11 |

**11 stranded commits across the seven days through 08-17, against 94 across the eight days from
08-18.** Per-branch verdicts tell the same story: through 08-17 the 29 surviving branches read **20
LANDED / 3 PARTIAL / 6 UNLANDED**; from 08-18 the 81 of them read **6 LANDED / 0 PARTIAL / 74
UNLANDED** (plus one branch carrying no own-work commits at all).

If anything this **understates** the step. The pre-08-19 survivors are the *leftovers* of the
pruning sweep — the branches it did not take — so they should be biased toward unlanded, and they
are the opposite. The break is in the arm, not in the instrument.

**Do not read §1.2's day-by-day counts as a rate.** They are absolute stranded-commit counts over a
varying number of fires per day; they establish a step, not its size. §1.1 is the rate. The item's
own 81%/33% figures come from the operator's declaration store, which a cloud VM cannot reach —
they are not reproduced here, and they do not need to be.

---

## 2 · B is real, is a different defect, and is FIXED

`bin/cc-cloud`'s `classify()` convicted `NOT-STARTED` on an absent ref **before** asking either
question that could have contradicted it. The consequence was not cosmetic: `cc-backlog`'s
`cloud_map` maps `NOT-STARTED` → **`open`** and `LANDED` → `done`, so each of the 54 pruned
successes was returned to the dispatch wave and re-fired against work already on trunk — and since
the `LANDED` arm is only reachable while the ref exists, `done` became structurally unreachable for
those sessions forever.

Fixed as **C7 VANISHED** — full statement of the arm, its two discriminators and the `base_sha`
guard in `docs/plans/CLOUD_OBSERVABILITY.md` §4.1 (corrected), §4.3, §4.4. Asserted by
`bin/cc-cloud --selftest` (29/29), whose new cases are credited one-for-one by three mutants:
reverting the arm reddens exactly the three new assertions and leaves both controls green; dropping
the `base_sha` guard reddens only the re-used-branch control; dropping the `landed()` lookup reddens
only the pruned-land case.

**This is not a fix for A.** It is the reason A was hard to see, and the reason the board will keep
lying about it until the live layer carries the new bytes.

---

## 3 · What a cloud VM cannot settle about A, and the command that does

The mechanism of the 08-17 stop needs reads this VM has no path to: the return ledger
(`~/.claude/autonomy/cloud/`, `return.jsonl`), the sweep's IDL journal, and the launchd job's own
environment. **One hypothesis is worth testing first, and it is cheap.**

`ba69a451` (committed `2026-08-17T01:10:22-07:00`, i.e. **`08:10:22Z`**) replaced the deployed-copy
gate in `scripts/autonomy-sweep.sh` with an **exact** path compare:

```bash
_cc_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _cc_cfg="${_cc_cfg%/}"
_cloudret_deployed=0
[ "$0" = "$_cc_cfg/scripts/autonomy-sweep.sh" ] && _cloudret_deployed=1
```

It gates **both** `cloud-return.sh` and `cloud-refusal-route.sh`; failing it makes them
`skipped-not-deployed` on every 300 s tick, silently and forever. It landed **62 minutes before the
last recorded land** at `09:12:05Z`, which is about the interval a `deploy-live.sh` convergence
plus one sweep tick would take. That is a coincidence worth one command, not a conclusion.

**The suspect is `$_cc_cfg`, not `$0`.** The plist runs the sweep as `/bin/zsh -lc '… ~/.claude/
scripts/autonomy-sweep.sh'`, so `$0` is `$HOME/.claude/scripts/autonomy-sweep.sh` — but `_cc_cfg`
comes from `CLAUDE_CONFIG_DIR`, and three migration scripts in this repo record that the operator's
shell exports `CLAUDE_CONFIG_DIR=~/.claude-next` (`migrations/0013…:26`, `0009…:80`, `0006…:87`),
one of them noting it may be exported **unexpanded**. If any startup file that `zsh -lc` sources
sets it, the compare is `/Users/chrisren/.claude/scripts/…` against
`/Users/chrisren/.claude-next/scripts/…` and the return rail has been off since the moment that gate
landed. (`zsh -lc` is non-interactive and sources `.zshenv`/`.zprofile`/`.zlogin` but **not**
`.zshrc`, so an export at `~/.zshrc:460` alone would *not* do it — which is exactly why this needs
measuring rather than asserting.)

Run this on the box; it answers the whole hypothesis in one line:

```bash
launchctl print gui/$UID/com.chrisren.autonomy-sweep 2>/dev/null | grep -i claude_config_dir; \
/bin/zsh -lc 'echo "CLAUDE_CONFIG_DIR=[$CLAUDE_CONFIG_DIR] HOME=[$HOME]"'; \
jq -r 'select(.probe=="cloud-return") | "\(.ts) \(.cloud_return_rc)"' \
  ~/.claude/autonomy/idl.jsonl 2>/dev/null | tail -20
```

A tail of `skipped-not-deployed` starting on 08-17 confirms it. A tail of `0` refutes it, and the
next place to look is `return.jsonl`'s per-session outcomes — the sweep rc says only that the pass
*ran*, never that anything landed.

**The gate has no test for the path its one real caller actually invokes.** The behavioural arm in
`tests/autonomy-sweep.bats` runs `bash "$deployed/autonomy-sweep.sh"` with `CLAUDE_CONFIG_DIR`
fixtured to the same root, so it exercises the one spelling that is guaranteed to match and never
the plist's. Whatever the answer above turns out to be, that gap is why a rail could go silent for
eight days with a green suite — worth closing regardless.

---

## 4 · A third finding, incidental but it cost real time here

`tests/cloud-return.bats` fixtures `$HOME` for hermeticity, but its lander stub reached
`git commit-tree` **without an identity on the command**, unlike every other commit the suite makes.
On any box with no global `user.email` — a cloud VM, a fresh CI runner — that commit died, `trunkref`
never received the tree, and **six cases went red on the content-verify leg**: precisely the shape of
"the return rail is broken", against pristine trunk, for a reason that is entirely the environment's.
Fixed in place; the suite now reads **24/24 with no ambient git identity at all**.

Recorded because of what it nearly did: those six reds were about to be reported as independent
corroboration of A. Attributing them against a stashed, pristine `bin/cc-cloud` is what caught it —
a red that reproduces identically on trunk is evidence about the harness, never about the diff.
