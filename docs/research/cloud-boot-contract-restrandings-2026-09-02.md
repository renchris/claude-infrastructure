# The boot contract was implemented nine times and landed zero times

**Row:** `cc-backlog 0c8b39b67665` — *"CLOUD_OBSERVABILITY.md's 'first act = push an empty commit'
contract is PROSE-ONLY, never implemented."*
**Venue:** cloud VM, `session_01Y6CYm6KezSikd3KVGCnEjL`, branch
`claude/fire-20260902T035207Z-13641-1`, 2026-09-02.
**Disposition:** the stated premise is TRUE and the implication drawn from it is REFUTED. What the
row needs is not a tenth implementation.

---

## 1 · The premise, checked on trunk

**TRUE.** On `origin/main` at `1ff275ba`, `docs/plans/CLOUD_OBSERVABILITY.md` §4.1 and §8 step 2
require a cloud session's brief to push the declared branch as its first act, and nothing emits it.
`bin/cc-dispatch`'s brief composer — the only surface that reaches a dispatched worker before its
first read — writes a TASK line, a DoD line, the premise contract, the staleness rail, the vintage
rail, the rails line and three terminal dispositions. No boot instruction, on either fire lane.

The live artifact is this session's own brief. It was fired by the dispatcher, and it contains no
boot ping; it also predates two rails that are on trunk today (the `--unshallow` clause and the
DISPATCHER VINTAGE line), so the dispatcher that fired it is behind trunk — landed is not live.

## 2 · …and nine workers have already fixed it

Searched with `git log -S "first act" --all -- bin/ scripts/`, then tested each with
`git merge-base --is-ancestor <sha> origin/main`:

| sha | date | branch | what it touched |
| --- | --- | --- | --- |
| `0cc728a2` | 09-01 | `claude/fire-20260901T200442Z-37476-1` | `bin/cc-dispatch`, doc, new bats |
| `ea2b988f` | 08-31 | `claude/fire-20260901T024128Z-78597-1` | `cc-offload`, `handoff-fire.sh`, `lib/cloud-create.sh` |
| `faf78977` | 08-31 | `claude/fire-20260831T201554Z-59973-1` | same set |
| `f578e350` | 08-28 | `claude/fire-20260828T171710Z-23251-1` | + `bin/cc-cloud` |
| `adec5241` | 08-27 | `claude/fire-20260827T005935Z-10851-1` | + `lib/cloud-boot-contract.sh` |
| `5d7d7d84` | 08-26 | `claude/fire-20260826T152747Z-5820-1` | + `lib/cloud-payload.sh` |
| `648c1a1d` | 08-26 | `claude/fire-20260826T113700Z-58202-1` | `handoff-fire.sh` only |
| `b9440fa8` | 08-26 | `claude/fire-20260826T064255Z-22036-1` | + `bin/cc-eligible`, `lib/cloud-brief.sh` |
| `52a39c70` | 08-25 | `claude/fire-20260825T184512Z-6494-1` | `cc-offload`, `lib/cloud-create.sh` |

**Nine implementations. Nine branches. Zero on trunk.** Each is a full, tested, independently
reasoned diff — most of them larger than this one — and each was written by a worker that had, like
this one, correctly established that the contract was prose. Seven of the nine put the rail in the
FIRE LANES (`cc-offload` / `handoff-fire.sh` / `lib/cloud-create.sh`), which covers briefs the
dispatcher never composes; the two most recent put it in the dispatcher.

This is §15's ten-dispatch loop, on the row whose subject is the mechanism that would have made it
visible. The re-dispatch predicate is `open`, and nothing a VM can run makes a row anything else.

## 3 · The lane is NOT dead, so that is not the explanation

Counted on trunk, keyed on the trailer `scripts/cloud-reconcile.sh` writes when it re-authors a
cloud branch:

```text
git log origin/main --grep='^Cloud-session:' --oneline | wc -l   →  116
most recent                                                      →  d92d773c, 2026-09-01
claude/fire-* branches on origin                                 →  360
```

Cloud results do land, including the day before this dispatch. So "the return path is broken" is
refuted as a general claim, and the honest statement is narrower and is the one thing this VM
cannot see: **why none of these nine were returned.** The evidence lives on the operator box only —
`~/.claude/autonomy/cloud/<id>.land-refused` (the lander's own verdict, keyed to a branch head) and
the return ledger. One read of those nine settles it; nothing here can.

One candidate cause is recorded on trunk by an earlier worker and is worth checking first.
`d92d773c` measured the land gate convicting a `bin/cc-dispatch` diff of suites that are red on
unmodified trunk *in this venue* — `cc-dispatch-v2` 17/17, `cc-dispatch-fire-evidence` 2/2,
`operator-readout` 43/43 — with a pristine-worktree control proving none was attributable. This
session reproduced the `cc-dispatch-v2` half and found its cause: the fixture pins
`A2_BASE_SHA=ec92e68c` as an "immutable ancestor of origin/main", and that object **does not
resolve in a fresh clone** — not at depth 50, and not after `git fetch --unshallow` (3,954 commits).
It exists on GitHub (authored 2026-07-31) but is reachable from no ref, so every clone that was not
present when it was written is missing it, and `setup()` dies in `tar` for tests 2-18. The desk's
long-lived checkout still has the object, which is why this is invisible there.

## 4 · The clause that is refuted

The row says the contract is *"the sole basis for C1 NOT-STARTED being readable as 'never booted',
and without it no-ref cannot distinguish never-started from nothing-to-commit."*

**Not since 2026-08-27.** `scripts/cloud-inbox.py` and `cloud-create-api.py --verify` read the
control plane per session and report `worker_status`, `status_bucket` and
`post_turn_summary.{status_category,status_detail,needs_action}` — which separates a session that
never ran a turn from one that ran turns and pushed nothing, with **no worker cooperation at all**.
Its own header carries the measurement: 262/262 control-plane GETs returned 200, and **222 of 262
sessions the board filed NOT-STARTED had ended a turn asking a question.**

So the boot ping is not the only discriminator, and it is the weaker one — it depends on an LLM
obeying prose. What it *is* is the discriminator available to `classify()`, which is git-only,
offline, and costs one `ls-remote` it already makes. The larger fix is orthogonal and is not this
row: **wire `inbox`'s projection into `cc-cloud classify()` so the board stops rendering
NOT-STARTED over sessions the control plane can see working.** That is the change that would move
85% of the board, and nothing in this diff does it.

## 5 · What was built here, and why not the literal contract

Not a tenth variant of the brief rail. This diff keeps the smallest brief-side change that is
correct, adopts the part of `0cc728a2` that no other branch has, and adds the half **none of the
nine touched** — the downstream one.

1. **`bin/cc-dispatch` — the ping, cloud-only.** `git push -u origin HEAD`, before the FIRST STEP.
2. **A bare ref creation, NOT `commit --allow-empty`.** §4.1's literal wording is true of the sensor
   and false of everything downstream: `cloud-reconcile.sh`'s `reauthor_branch` replays a branch's
   commits with `commit-tree`, which replays an empty one happily, so the literal contract would
   put one content-free commit on `main` per cloud fire. Eight of the nine prescribe the empty
   commit; `0cc728a2` does too. A bare push creates the same ref, is the same single observation to
   `ls-remote`, and leaves nothing to land.
3. **`bin/cc-dispatch` — the rails and the tail, cloud-only** (adopted from `0cc728a2`, re-derived
   against current trunk rather than cherry-picked, because that commit predates the `--unshallow`
   clause and would revert it). The incumbent brief tells an off-box worker to `/ship`, then to
   close with `cc-backlog done`, park with `cc-backlog block` and wake with `cc-notify` — all four
   wrong off-box. Confirmed from inside this VM: `cc-backlog` and `cc-notify` write
   `~/.claude/autonomy/*`, which does not exist here.
4. **`bin/cc-dispatch` — `git -C <desk path>` is inert off-box.** Every rail hardcoded the ITEM's
   repo path as resolved on the operator's box. This session's brief told it to run
   `git -C /Users/chrisren/Development/claude-infrastructure fetch --unshallow`; the checkout is
   `/home/user/claude-infrastructure`. The staleness rail — the one that exists to protect the
   shallow clone a cloud worker actually gets — was inert on the only venue that has one. Cloud
   briefs now drop the prefix; local briefs are byte-identical to before.
5. **`scripts/cloud-reconcile.sh` + `scripts/cloud-return.sh` — the population the ping MOVES.**
   This is the half nine implementations skipped, and shipping the ping without it is a regression.
   Before the ping, a VM that boots and commits nothing has no ref: C1 NOT-STARTED, and
   `cloud-return.sh` returns at step 1 with "nothing to return". After it, the same session has a
   ref, reads C5 ALIVE / C4 STALLED, and arrives **at the land** — which would fetch, re-author,
   rebase and push a branch whose commits change no file, then report a refusal: a land-refused
   artifact latched to the head, a `LAND REFUSED` wake, custody left open. Three alarms per dead
   session, about a branch with nothing wrong with it. So `--land` now answers **66 — nothing to
   land** for a branch carrying no content against its trunk (`--all` skips it without counting a
   failure), and `cloud-return.sh` reads 66 as a non-verdict: no artifact, no wake, exactly as
   quiet as the NOT-STARTED case it replaces.
6. **`tests/cloud-return.bats` — `sed -i ''` is BSD-only.** On GNU sed the empty string is the
   script and the script becomes a filename, so tests 32-35 failed on Linux and passed on the
   operator's mac. A cloud worker runs on Linux; the venue that most needs to verify this suite was
   the one that could not.

## 6 · Measured about this venue, in passing

Each verified live in this session, and each contradicts something a reader might assume:

- **A VM can create a remote ref and cannot delete one.** `git push origin HEAD:refs/heads/<x>`
  succeeds; `git push origin --delete <x>` fails with a sideband disconnect on every retry. Ref
  cleanup is a desk job, which is one more reason the ping must not also be a commit.
- **`bats` and `shellcheck` are absent** from the image and installable with `apt-get`. A worker
  that does not install them cannot run this repo's gate at all, and nothing in the brief says so.
- **The clone arrives shallow at depth 50**; `git fetch --unshallow` works and yields 3,954 commits.
  Before it, `git log` over a cited file showed **one** commit, which is exactly the "the cure never
  landed" misreading the staleness rail was written to prevent.

## 7 · Honest limits

- Whether *this* diff lands is not decided here, and the nine above are the reason to say so
  plainly. If it strands, the row's blocker was never the code.
- §5's items 5 and 6 are verified by suite (`tests/cloud-reconcile.bats` 33/33,
  `tests/cloud-return.bats` 40/40, `bin/cc-dispatch selftest` 180/180, red-proved against the
  pristine tree). §5's items 1-4 are verified the same way, but their *effect* — a worker actually
  pushing on boot — cannot be observed from here; it is observable on the next cloud dispatch as a
  ref appearing inside the boot budget.
- `cc-dispatch-v2` is 17/17 red in this venue for the reason in §3, identically on the pristine
  tree. It is not attributable to this diff and is not fixed by it.
