# A cured row that no cloud worker can close, and the one channel that can

**2026-08-26.** Backlog `f85fce7c26f5` — *"the cloud return/land arm died 2026-08-17T09:12:05Z"* —
was dispatched to a `--venue cloud` session again. **Its cure landed on trunk on 2026-08-25 and the
row is still open.** This file records the verification (so the row is not re-derived a fourth time)
and names the mechanism that keeps it open, which is not the same defect the row describes.

## 1 · The row is CURED — `a42f107a`, and it is an ancestor of `origin/main`

    fix(cc-cloud): deletion is the last step of a successful session, and the probe read it as failure
    a42f107aaca68da83345e1c8f95f283a35f4f13a   2026-08-25 03:52:32 -0700
    Refs: cc-backlog f85fce7c26f5

`git merge-base --is-ancestor a42f107a origin/main` → **0**. Three files, +272/−7: `bin/cc-cloud`,
`scripts/branch-prune-landed.sh`, `tests/cc-cloud.bats`.

The row's own three clauses, each answered by that commit and **not restated here** — the commit
body and `bin/cc-cloud`'s header block are the record:

| the row's clause | its disposition |
|---|---|
| push rate stepped 81% (through 08-16) → 33% (from 08-18) | **artifact of the probe.** Any rate over cc-cloud's states steps down at a prune with no change in the fleet at all. |
| 54 landed branches pruned 08-19 score identically to never-pushed | **confirmed and fixed.** `docs/research/branch-prune-manifest-2026-08-19.tsv` tallies **55 DELETED · 41 HOLD-stranded · 1 HOLD-young**. C3 LANDED now precedes C1 NOT-STARTED, gated on positive push evidence. |
| the create/fire path frozen since 08-11 does not explain it | **accepted, unchanged.** The explanation is the read side, not the fire side. |

A separate, genuinely dead arm behind the same date was fixed two days earlier — `cd5d009b5`
(bound-kill debris blocking every land retry) and `d0f40767f` (the cure sweep matching a sentence
its own blocker had stopped writing). Both are ancestors of `origin/main`. Together they are why the
lane "landed a branch and closed a row end-to-end for the first time since 2026-08-17T09:12Z"
(`docs/plans/BACKLOG_DRAIN_24_7.md`, 2026-08-23 entry). **The row's headline was true and its stated
evidence was contaminated; both halves have landed fixes.**

### Re-verified on trunk today, not recalled

Working tree byte-identical to `origin/main` on all three files (`git diff origin/main --` empty).

    bats tests/cc-cloud.bats     1..31, 31 ok, 0 not-ok
    bin/cc-cloud --selftest      24 passed, 0 failed

Tests **8** (`a LANDED session stays LANDED after its branch is pruned`) and **9** (`C1 survives the
hoist: no ref and NO evidence of one is still NOT-STARTED, even when the declared path is already on
trunk`) are the two arms of the cure and its guard. Both green. Test **12** (`a path set filled
BEFORE the prune keeps the session LANDED after it`) covers the generator arm in
`branch-prune-landed.sh`.

## 2 · The residue is not this row's mechanism — it is CURED ≠ CLOSED, made structural

The row has churned **after** its own cure landed, in this repo's own status record
(`docs/plans/BACKLOG_DRAIN_24_7.md`, per-link `comm` reconciliations):

| link | date | movement |
|---|---|---|
| drain recycle #214 | 2026-08-25 | reads `claimed` |
| drain recycle #222 | 2026-08-25 | **claimed → open** |
| drain recycle #223 | 2026-08-25 | **open → claimed** |
| drain recycle #233 | 2026-08-26 | **claimed → open** |
| drain recycle #235 | 2026-08-26 | **open → claimed** (before that link's open) |
| this dispatch | 2026-08-26 | claimed again |

Cure landed **2026-08-25T10:52:32Z**. Both 08-26 movements are unambiguously after it, and the row
has been claimed and released without closing at least three times. This is `#145`'s CURED ≠ CLOSED,
but with a sharper edge than "someone forgot": **for a cloud worker the close is mechanically
unreachable.**

### Why — the close is joined to a content-verified path set, and a correct worker has no content

`scripts/cloud-return.sh` step 8 is the only actuator that closes a dispatched row, and its own
comment states the constraint exactly: *"the laptop's job; the VM cannot reach the backlog store at
all."* It fires `cc-backlog done "$item" --evidence …` **only** when `landed_ok -eq 0`, which
requires:

1. `cc-cloud fill-paths --id` to derive `paths=` **from the VM's own commits** (step 5), and
2. every path in that set to be content-present on the trunk ref (step 6, `git ls-tree`, never a
   sha — the land re-authors).

A worker dispatched onto a row whose cure already landed has **nothing correct to commit**. So it
pushes nothing, and the chain is deterministic:

    no commits → no ref (or ref at its pre-fire sha)
      → cc-cloud C1 NOT-STARTED
      → cloud-return.sh:273 "NOT-STARTED (cc-cloud already rows this); nothing to return", rc 0
      → cc-backlog cloud_map: NOT-STARTED → open
      → re-dispatched next wave, forever

Note what this is *not*: it is not the bug `a42f107a` fixed. That one made a **landed** session read
NOT-STARTED. This one is a **correctly** NOT-STARTED session — the worker really did push nothing —
whose verdict is nevertheless wrong at the row level, because "the worker found nothing to do" and
"the worker never booted" are the same observation from the desk. **There is no desk-side fix**: the
distinguishing fact exists only inside the VM, and the VM's only channel to the desk is its branch.

## 3 · The channel, therefore the convention

A VM has exactly one way to say anything to the desk: **land a path.** So a cloud worker that finds
its row already cured should land a *verdict artifact* — a research file naming the cure sha, the
verification it ran, and the evidence — and that path is then what `fill-paths` derives,
`landed_ok` content-verifies, and step 8 closes the row on. The machinery needs no change; it
already does the right thing the moment a path exists.

This is the same shape the venue-mismatch class arrived at independently — seven cloud sessions
appending to `docs/research/venue-foreign-repo-recurrence-2026-08-17.md`, each landing a row rather
than inventing code work. That convention was never written down, so each VM re-derives it or, worse,
does not: **the two failure modes available to a worker with no convention are inventing junk work to
justify a push, or pushing nothing and burning the slot.** The second is what has happened to
`f85fce7c26f5` at least three times since 08-25.

Written into the lane's SSOT as `docs/plans/CLOUD_OBSERVABILITY.md` §14.

### Honest limits

- **This does not close the row by itself.** It makes the row *closable*: the desk's next
  `cloud-return.sh` pass content-verifies this file's path on trunk and fires
  `cc-backlog done f85fce7c26f5`. If that pass does not run, the row stays open and the loop
  continues — the fix is the convention plus a working return arm, not either alone.
- **A fast-forwarded land still reads UNKNOWN.** `fill-paths` bounds its range at the merge-base
  with the trunk, and that range is empty for a true ancestor, so it refuses rather than writing an
  empty set. `a42f107a` names this limit and measures it as the rare arm (this repo's `--merged`
  finds 1 of 97 against `git cherry`'s 56, because ship-land rebases). Unchanged here.
- **Nothing above claims the cloud lane is healthy.** It claims one row's cure is on trunk and one
  structural reason rows like it do not close. The queue behind the lane is a separate question with
  its own record in `docs/plans/BACKLOG_DRAIN_24_7.md`.
