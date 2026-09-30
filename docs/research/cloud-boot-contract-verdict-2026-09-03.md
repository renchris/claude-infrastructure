# The boot contract landed on 09-02, and the dispatcher that re-fired the row on 09-03 was still not running it

**Row:** `cc-backlog 0c8b39b67665` — *"CLOUD_OBSERVABILITY.md's 'first act = push an empty commit'
contract is PROSE-ONLY, never implemented — it is the sole basis for C1 NOT-STARTED being readable
as 'never booted'."*
**Venue:** cloud VM, `session_01FuTBvYuZqWRU9aju6dq7hB`, branch
`claude/fire-20260903T085341Z-76193-1`, fired 2026-09-03T08:53:41Z.
**Disposition:** **DISCHARGED** by `0efcc073` (2026-09-02 04:32:18 +0000), an ancestor of
`origin/main`. No code work was warranted and none was done. The row's second clause was already
REFUTED on trunk before this dispatch. What this session adds is one measurement the 09-02 session
could not make: **the cure landed and, twenty-eight hours later, the actuator was still not running
it** — which is why the row was re-dispatched at all.

Trunk at the time of this reading: `5711f19d` (2026-09-03 01:27:15 -0700). Working tree
`git rev-list --count HEAD..origin/main` = 0.

---

## 1 · The verdict: cured, not closed

`0efcc073` — *"feat(cloud-boot): the absence contract stops being prose — and the population it
moves is handled"* — is on trunk:

```text
$ git merge-base --is-ancestor 0efcc073 origin/main   # rc 0
```

🚨 **That assertion was re-run on a DEEP clone.** A dispatched worker's checkout arrives shallow at
depth 50, and inside that horizon `--is-ancestor` and `git log -S` answer *"no"* for *"I cannot see
that far"*. This session reproduced exactly that failure while measuring §3 below, so the ancestry
claim above is only admissible because `git fetch --unshallow` ran first. `22b8824c` is the commit
that made that a rail, and §3 is the reason it did not reach this brief.

It carries all three parts the row and its sibling document call for:

| part | where, on trunk | proved by |
| --- | --- | --- |
| the ping is EMITTED, cloud-only | `bin/cc-dispatch:2906-2908` (`boot_rail`, gated `[ "$venue" = cloud ]`) | selftest arms `(c7) a CLOUD brief carries the boot ping` / `(c7) a LOCAL brief has NO boot ping` |
| a **bare ref creation**, not an empty commit | same block; §16.1 corrects §4.1's wording in the design doc | `(c7) …and forbids the empty commit that would land as trunk noise` |
| the population it moves is handled | `scripts/cloud-reconcile.sh` answers **66 — nothing to land**; `scripts/cloud-return.sh:517` reads 66 as a non-verdict | `tests/cloud-reconcile.bats`, `tests/cloud-return.bats` |

**Re-verified on this VM rather than recalled.** `bash bin/cc-dispatch selftest` → **180 passed, 0
failed**, including all twelve `(c7)` arms (the six above plus the off-box tail: no `/ship`, push as
the completion signal, `cloud-park.sh` for an operator gate, a verdict artifact for a cured row,
never `cc-backlog done`). `bash -n` clean on `cc-dispatch`, `cloud-reconcile.sh`, `cloud-return.sh`,
`cloud-park.sh`. `bats` is not installed in this image, so the two `.bats` suites were not run here;
the `rc=66` arms were confirmed present by inspection at `cloud-reconcile.sh` (two `exit 66` sites)
and `cloud-return.sh:517`.

## 2 · The refuted clause was already refuted on trunk

The row calls the contract *"the sole basis"* for reading `C1 NOT-STARTED` as "never booted". That
has been false since 2026-08-27: `scripts/cloud-inbox.py` reads the control plane per session and
separates "never ran a turn" from "ran turns, pushed nothing" with no worker cooperation at all.
This is recorded on trunk at `CLOUD_OBSERVABILITY.md` §16.4, which also names the larger fix — wire
`inbox`'s projection into `cc-cloud classify()` — as **orthogonal and unfiled**. Nothing here
changes that; it is not this row's scope and it is not filed by this session either, because a
cloud VM cannot write the backlog store (§4).

## 3 · The measurement this session adds: the cure is landed and not live

The 09-02 session observed the vintage gap in passing. This session measures it **after** the cure
landed, and it is unchanged.

**The evidence is this dispatch's own brief.** Three rails are on trunk and absent from it:

| rail | landed | conditional? | in this brief? |
| --- | --- | --- | --- |
| `--unshallow` clause in FIRST STEP | `22b8824c` 2026-09-01 04:59:58Z | **no — every brief** | **absent** |
| `DISPATCHER VINTAGE` line | `f9cbe177` 2026-09-02 02:15:02Z | **no — every brief** | **absent** |
| `BOOT PING` + off-box terminal tail | `0efcc073` 2026-09-02 04:32:18Z | cloud-only | **absent** |

The first two are unconditional — composed at `bin/cc-dispatch:2909` and `:2918` and printed at
`:2948-2949` with no `$venue` guard — so their absence is decisive on its own: **the bytes that
composed this brief predate `22b8824c`, i.e. three landed `bin/cc-dispatch` commits and just over
two days behind trunk at fire time.**

Everything else follows from that vintage and needs no second explanation. This brief handed an
off-box worker `git -C /Users/chrisren/Development/claude-infrastructure …` (a path that does not
exist here) and all three on-box terminal dispositions — `cc-backlog done`, `cc-backlog block`,
`cc-notify --role desk` — which are exactly the defects §16.3 fixed. ⚠️ **No venue-misclassification
inference is available from this**: the venue-conditional tail was introduced *by* `0efcc073`, so
before it every brief carried the local tail regardless of venue. Whether this row's `venuePlan`
says `cloud` cannot be read from here.

**The gap bit inside this very session.** Because the brief carried no `--unshallow` clause,
`git log -S "is-shallow-repository" -- bin/cc-dispatch` was first run against the shallow clone and
named `d92d773c` — the wrong commit — for the clause whose real origin is `22b8824c`. The correct
answer appeared only after `git fetch --unshallow`. That is `22b8824c`'s own defect, reproduced by a
worker fired 2 days after `22b8824c` landed, *because* it landed and did not go live.

### Why this is a convergence fact, not a defect in `0efcc073`

`bin/cc-dispatch` is a per-file symlink into the checkout, so it should go live on the trunk
fast-forward — which makes "behind" a statement about the desk's checkout or the symlink, not about
the diff. **Three candidate causes, and this VM can separate none of them:** the desk's checkout is
behind `origin/main`; `~/.claude/bin/cc-dispatch` is stale or is a copy rather than a link; or the
pass was composed from an older worktree. `~/.claude/autonomy/` and the desk's blob are unreadable
from here.

**One read on the desk settles it:**

```sh
git -C ~/Development/claude-infrastructure rev-parse HEAD:bin/cc-dispatch; readlink -f ~/.claude/bin/cc-dispatch
```

This is also the loop generator §15 and §16 keep circling, stated at its narrowest: **the actuator
that fires re-dispatches converges on no schedule tied to the landing that cures them.** A row cured
at 04:32 on 09-02 was re-fired at 08:53 on 09-03 by a dispatcher that could not have told its worker
the cure existed, could not have told it it was off-box, and could not have told it to deepen its
clone before checking. The cure for *this* row is complete; the cure for the class is a convergence
guarantee on `bin/cc-dispatch`, and it is not this row.

## 4 · Honest limits of this document

- **Not run here:** `tests/cloud-reconcile.bats`, `tests/cloud-return.bats` (no `bats` in the image).
  Both were green in `0efcc073`'s own verification, 33/33 and 40/40.
- **The vintage is bounded from above, not pinned.** "Predates `22b8824c`" is what the absent rails
  prove; the exact blob is unreadable from a VM. `f9cbe177`'s `DISPATCHER VINTAGE` rail exists
  precisely to make this exact rather than inferred — the next dispatch fired by a converged
  dispatcher will state its own blob.
- **No store was written.** `cc-backlog` is not on `PATH` here and `~/.claude/autonomy/` does not
  exist, confirming §16.3's measurement a second time. Per `CLOUD_OBSERVABILITY.md` §14 this landed
  file *is* the disposition: the desk closes `0c8b39b67665` from it, on `0efcc073` as evidence.
