# The boot-ping contract row is CURED — and the cure did not merely land, it RAN

**Row:** cc-backlog `0c8b39b67665` — *"CLOUD_OBSERVABILITY.md's 'first act = push an empty commit'
contract is PROSE-ONLY, never implemented."*
**Verdict:** CURED on trunk by **`0efcc073`**, and PARTLY REFUTED as filed.
**Venue:** cloud VM, `/home/user/claude-infrastructure`, 2026-09-04.
**Dispatch:** this row was fired again 11 days after it was written (2026-08-23T21:26:48Z).

---

## 1 · The cure, asserted

```
$ git merge-base --is-ancestor 0efcc073 origin/main && echo ANCESTOR: yes
ANCESTOR: yes
```

`0efcc073 feat(cloud-boot): the absence contract stops being prose — and the population it moves is
handled` (2026-09-02) names **this row's id in its own first paragraph** and carries all three halves
the row's condition requires:

| Half | Where it lives on trunk | Verified here by |
|---|---|---|
| the brief EMITS the ping | `bin/cc-dispatch:2907` (`boot_rail`) | `git grep -n 'BOOT PING' origin/main -- bin/cc-dispatch` |
| the lander does not alarm on a ping-only branch | `scripts/cloud-reconcile.sh:731` → exit **66** (`NOTHING TO LAND`) | `git grep -n 66 origin/main -- scripts/cloud-reconcile.sh` |
| the return path reads 66 as a non-verdict | `scripts/cloud-return.sh:638` | `git grep -n 66 origin/main -- scripts/cloud-return.sh` |

`§16.1` of `docs/plans/CLOUD_OBSERVABILITY.md` (line 1988) corrects §4.1's wording in place: the ping
is **a bare ref creation, not an empty commit**, because `reauthor_branch` replays an empty commit
onto main happily and would put one content-free commit on trunk per cloud fire.

## 2 · The stronger fact: LANDED is not LIVE, and here it is BOTH

The brief instructed a dispatcher-vintage check, and it came back **EQUAL**:

```
$ git rev-parse origin/main:bin/cc-dispatch
646b8a652e71dd5e5e506dffe23725437accea6b     # == the blob that composed this brief
```

So the dispatcher that fired this session **is** trunk. That converts the usual weak claim ("the fix
already landed") into the strong one: **the fix ran.** The brief this session is holding was produced
by the very code `0efcc073` added, and its BOOT PING section is byte-identical to
`bin/cc-dispatch:2907` — including the `git push -u origin HEAD` wording, the explicit *"Do NOT make
an empty commit"* clause, and the repo-relative rails.

**This session executed it.** `git push -u origin HEAD` was the first act of this turn; the branch
`claude/fire-20260904T103118Z-84707-1` existed at trunk's head, carrying no commit, before anything
was read. The contract is no longer prose in the only sense that matters: a worker obeyed it.

## 3 · What was run in this venue

```
$ bash bin/cc-dispatch selftest
cc-dispatch selftest: 180 passed, 0 failed
```

The twelve `(c7)` arms — the ones `0efcc073` added for exactly this condition — are green here:

```
ok   (c7) a CLOUD brief carries the boot ping
ok   (c7) …and names the ONE command, not a description
ok   (c7) …and forbids the empty commit that would land as trunk noise
ok   (c7) …and its rails are repo-RELATIVE: no desk path a VM cannot reach
ok   (c7) a CLOUD brief does NOT tell an off-box worker to /ship
ok   (c7) …it says the PUSH is the completion signal
ok   (c7) …it routes an operator gate through cloud-park
ok   (c7) …and a cured/refuted row through a VERDICT ARTIFACT
ok   (c7) …never through cc-backlog done, which writes nothing off-box
ok   (c7) a LOCAL brief has NO boot ping
ok   (c7) …and keeps its absolute git -C <repo> prefix
ok   (c7) …and keeps the on-box terminal dispositions
```

`bats` is not installed in this VM, so `tests/cloud-reconcile.bats` and `tests/cloud-return.bats`
were not re-run here; `0efcc073`'s own body records them at 33/33 and 40/40 with three arms
red-proved against the pristine tree.

Staleness rails, run before any of the above: `git rev-parse --is-shallow-repository` → `true`, so
`git fetch --unshallow`; `git rev-list --count HEAD..origin/main` → **0**, i.e. this tree *is* trunk,
so every read above is a trunk read.

## 4 · The half of the row that is REFUTED, not cured

The row asserts the ping is **"the sole basis for C1 NOT-STARTED being readable as never booted"**.

That has been false since **2026-08-27**. `scripts/cloud-inbox.py` reads the control plane directly
and separates *"never ran a turn"* from *"ran turns, pushed nothing"* with **no worker cooperation at
all** — 222 of 262 sessions filed NOT-STARTED had ended a turn asking a question. The ping is the
weaker discriminator; it is merely the one `classify()` can afford.

`0efcc073` already recorded this refutation in its commit body. It is restated here because the row
was re-dispatched with the refuted clause intact, and a row's premise is a claim made at filing time,
not a fact.

## 5 · Why this row survived nine correct fixes

`0efcc073` measured it: the contract had been correctly diagnosed and fully fixed **nine times**
before — `0cc728a2 · ea2b988f · faf78977 · f578e350 · adec5241 · 5d7d7d84 · 648c1a1d · b9440fa8 ·
52a39c70`, 08-25 to 09-01 — each on its own stranded fire branch, **none returned to trunk**. The
lane was not the cause (116 re-authored cloud commits are on trunk). The evidence that settles it is
readable only on the operator box: `~/.claude/autonomy/cloud/<id>.land-refused` for those nine ids.
Full measurement: `docs/research/cloud-boot-contract-restrandings-2026-09-02.md`.

This dispatch is the tenth firing of the row and the first one after the cure. It produced no code.

## 6 · Follow-on, for the desk to file (this VM cannot write the backlog)

**Wire `cloud-inbox.py`'s control-plane projection into `cc-cloud classify()`.** Named as orthogonal
and explicitly excluded from `0efcc073`; still unbuilt on trunk today — `bin/cc-cloud:1502` exposes
`inbox` as a standalone verb only, and `classify()` does not consult it. `0efcc073` estimates it
would move **85%** of the board, which is an order of magnitude more than the ping. Not filed from
here: `cc-backlog` writes nothing off-box.

Also unresolved and not attributable to any diff here: `tests/cc-dispatch-v2.bats:32` pins
`A2_BASE_SHA="ec92e68c"` as an *"immutable ancestor of origin/main"*, and **that object resolves in
this clone not at all** — `git cat-file -t ec92e68c` → `fatal: Not a valid object name`, after a full
`--unshallow`. The suite itself could not be run here (no `bats`), so the 17/17 red figure is
`0efcc073`'s measurement, not this session's; the *cause* is re-confirmed above by a one-line read.
