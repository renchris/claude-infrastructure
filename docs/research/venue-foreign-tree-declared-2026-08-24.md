# The third fire of one row, the first one the landed guard should have stopped — and both filed repairs refuted

**2026-08-24.** Backlog item `8f59467c92b0` — *"MASTER: product repos"*, project
`claude-infrastructure` — was dispatched to a `--venue cloud` session whose one attached repository
is `renchris/claude-infrastructure`. Every open wave it names (`R1`-`R4`) edits
`~/Development/reso-management-app` or `~/Development/doc_classifier`. Neither exists on this host.
Unworkable on arrival, for the third time.

This file does not re-derive the cause — `cloud-venue-project-repo-mismatch-2026-08-16.md` §2 located
it and `venue-foreign-master-redispatch-2026-08-17.md` recorded the second fire. It records the three
things **this** fire measures that the two prior ones could not, and the fix that followed from them.

---

## 1 · The guard landed, and this row walked through it

The decisive difference from 08-17. `460211b83` (2026-08-23T21:30Z) landed the cross-repo eligibility
arm — `CROSS_REPO = "ineligible-cross-repo"` in `bin/cc-eligible`, with `cross_repo(project)` at :726
wired into `assess_full` at :817 and a ten-test suite. The 08-15 and 08-17 sessions both asked for
exactly this. It shipped, and **~20 hours later this row was dispatched anyway.**

That is not a failure of the arm. Read on trunk this session, `cross_repo(project)` takes **one**
argument and compares the item's project to the lane's origin. This row's project label is
*accurate* — `scripts/find-plan.sh:70 project_name_for()` derives it from the plan FILE's path, and
`docs/plans/MASTER_PRODUCT_REPOS.md` genuinely lives in `claude-infrastructure`. Every term the arm
can see is satisfied, so it passes, correctly, by construction.

`venue-foreign-master-redispatch-2026-08-17.md` §3 predicted this in the abstract — *"both filed
options PASS this row"*. This is that prediction confirmed against a shipped implementation rather
than against a proposal. The class now has a measured instance of *the remedy running and not
firing*, which is a strictly stronger fact than the one 08-17 could offer.

## 2 · 🚨 The filed repair cannot see this row either — SPAN_FIELDS excludes the plan body

`venue-foreign-master-redispatch-2026-08-17.md` §3 closes by naming the fix: *"restore the 08-15
subject discriminator as a conjunct"* — an item whose **text** names a dispatch-set project other
than its own. Measured this session, that discriminator is inert on this row.

The text a classifier receives is assembled in `build_index` from `SPAN_FIELDS`
(`bin/cc-eligible:450`):

```python
SPAN_FIELDS = ("title", "dodRef", "condition", "source")
```

For `8f59467c92b0` those four are, respectively, *"MASTER: product repos — the operator's actual
products, one wave per repo"*, `docs/plans/MASTER_PRODUCT_REPOS.md`, `master-product-repos`, and its
discovery source. **Not one of them contains the string `reso-management-app` or `doc_classifier`.**
Only the plan BODY does — which `MASTER_PRODUCT_REPOS.md:51-53` already states in as many words
(*"never the plan BODY, where every foreign tree is named"*), written by the 08-15 session about a
different arm and never connected to the 08-17 remedy that the same constraint kills.

So the remedy as filed would have stopped four of the seven dispatches in this class and neither
occurrence of this one, for a second and independent reason from the one 08-17 gave.

## 3 · And the obvious repair to THAT is worse — the 31% measurement

The natural next move is to follow the `dodRef` and scan the plan body. Measured over the 45 open
plans in `docs/plans` (frontmatter `status` not `complete`/`superseded`):

| | count |
|---|---|
| open plans | **45** |
| naming `reso-management-app` or `doc_classifier` anywhere in the body | **14 (31%)** |

The fourteen: `AUTONOMY_DISPATCH_V2`, `BACKLOG_DRAIN_24_7`, `BACKLOG_SELF_DRAINING_2026-08-12`,
`CONCURRENCY_PROGRAM`, `DESK_ROUTER_AND_STARTUP_V1`, `GROUND_UP_REBUILD_MAP`,
`INFRA_PERFECTION_2026-07-25`, `MACHINE_CAPACITY_V2`, `MASTER_ENFORCING_STORE`,
`MASTER_OPERATOR_GATED`, `MASTER_PRODUCT_REPOS`, `SHIP_LAND_HARDENING_PLAN`,
`TWO_WAY_SESSION_COMMS_PLAN`, `WORKTREE_MANAGEMENT_V2`.

Thirteen of those fourteen mention a product repo *in passing* — as an example, a cost note, a
cross-reference. A body scan refuses **a third of this repo's plan-derived work** from cloud in
order to park one row. `bin/cc-eligible`'s own header names that failure mode by name: *a denylist
enumerates SPELLINGS, never the class it is standing in for*
(memory: `denylist-enumerates-spellings-not-the-class`).

Both inferential shapes are therefore out: one cannot see the row, the other cannot see the
difference between a subject and a mention.

## 4 · What landed — the signal is DECLARED, not inferred

`182c81e9`. A fourth arm in `bin/cc-eligible`, beside the label arm rather than inside it, because
the two answer different questions ("is the LABEL elsewhere" / "is the declared WORK elsewhere") and
a row can satisfy one and not the other:

```
FOREIGN_TREE = "ineligible-foreign-tree"
```

A plan whose work is in other trees **says so in its frontmatter**, and the arm reads that
declaration and nothing else:

```yaml
---
status: open
targets: reso-management-app, doc_classifier
---
```

`declared_targets()` reads only the `---`-fenced header (bounded at 200 lines), never the body.
Each declared target is then measured through the existing `cross_repo()`, so the new arm inherits
that one's fail-open law in every direction instead of restating it — an unresolvable lane, an
unreadable tree, or a target that is a second checkout of the lane's own origin all stay silent.
It fails open additionally on: no `dodRef`, a ref resolving to no file, a file with no frontmatter,
and a frontmatter with no `targets:` key. A target equal to the item's own project is skipped —
that case is `CROSS_REPO`'s, and reporting it twice would double-count one fact in the census.

Three properties this shape has that neither inferential one did:

- **Zero false positives by construction.** Nothing fires without an explicit key, so the 31%
  above are untouched — pinned directly as test 3, *"A MENTION IS NOT A DECLARATION"*.
- **Two trees are expressible.** `MASTER_PRODUCT_REPOS.md`'s own 2026-08-15 entry states that a
  cross-repo master targets two trees and *"the single-value options cannot express it"*. A list
  does. Pinned as test 4.
- **The cost of being wrong is bounded and one-directional.** Per `REFUSAL_NOTE`, a refusal costs
  only the cloud venue: the item still claims and drains locally, untouched. That is the reverse of
  the fire-path change 08-17 §6 declined to make, where a wrong refusal starves the tap.

`docs/plans/MASTER_PRODUCT_REPOS.md` now carries the declaration, so the row that has burned three
slots is parked by a mechanism in the enforcing store rather than by prose.

## 5 · The two 08-17 refusal grounds, re-measured rather than inherited

`venue-foreign-master-redispatch-2026-08-17.md` §6 declined to fix anything from a VM on three
grounds. Two were re-measured this session and do not hold:

| 08-17 ground | this session |
|---|---|
| *"`bats` and `shellcheck` are both ABSENT — the repo's gate cannot be run"* | **Resolved in ~30 s.** `npm install -g bats` and `pip install shellcheck-py` both succeed through the proxy. The gate ran: **64/64 green** on the four `cc-eligible` suites, `bats-shellcheck-lint` clean, `gate-select.sh lint` rc 0, and the three `bats-*-lint` guards rc 0. |
| *"landing an ungated guard into the FIRE path trades a bounded waste for an unbounded one"* | **Does not apply to this arm.** The change is to `cc-eligible` (the claim-side predicate), not `bin/cc-offload`. A wrong refusal here costs the cloud venue only; the item drains locally. |
| *"`OFFBOX_LANE` — a session this lane created cannot verify a change to the lane"* | **Stands, and is why the arm is inert here.** `cloud_repo()` resolves via `_lane_from_self()`, which requires the script to live under `$HOME/Development`; on this VM it lives at `/home/user/claude-infrastructure/bin`, so the lane is unresolvable and the whole reach family fails open. The arm is exercised by the fixtured suites and takes effect on the dispatching box. |

**Red-proof, measured not asserted.** Against parent `7fbc0ffb` (zero occurrences of `FOREIGN_TREE`,
zero of `declared_targets`, counted with `grep -c`): **FAIL 1, 2, 4, 8, 9** — the five that demand a
refusal, a named tree, the class in the census, or a blocked claim. **PASS 3, 5, 6, 7, 10** — all
five assert the eligible direction, which a parent that refuses nothing gives away for free, so none
of them is a red-proof; 5-7 are true fail-open controls and 3 and 10 become load-bearing only once
the arm exists.

## 6 · Two pre-existing REDs, named and not driven — the second one blocks the land path itself

**(a)** `tests/cc-venue.bats` test 11 (*"an unreadable LEDGER refuses to route at all"*) fails on
this branch. It fails **identically on parent `7fbc0ffb`**, checked out into a clean worktree and
run there, and it concerns `cc-venue`'s routing of an unreadable ledger — nothing this diff touches.

**(b) 🚨 `scripts/ship-land.sh` cannot land from a cloud VM at all, and this is why the two prior
fires' work reached trunk only as a branch.** `/ship --dry-run` on this change reached the gate and
exited **6 (GATE RED)** — not on the diff, but on a lint's own selftest:

```
✗ gate: unattended-path-lint --selftest FAILED — the detector no longer discriminates,
  so its clean verdict would mean nothing. Fix the lint before landing.
```

Run directly it reports **`FAILED (9 of 39)`**, and the nine are environmental rather than
diff-related — *"a bare `/sbin`-only binary"*, *"the plist half did not fire on an INLINE export
PATH"*, *"a caller PATH without `/sbin` silently dropped a finding"*. The lint's subject is
macOS: `/sbin` binaries and launchd plists, neither of which this Linux VM has. **Measured
identical on parent `7fbc0ffb` in a clean worktree: 9 of 39, same nine.** Pre-existing,
environmental, and unrelated to this diff.

The consequence is structural and worth stating plainly: **the project-local `/ship` rail is
unusable from any cloud VM**, because a fail-closed gate arm cannot self-certify off-Darwin. That
is not a reason to force past it — the arm is right that a non-discriminating detector's clean
verdict means nothing — so this branch is pushed and left for a land from the Mac. It also
retroactively explains the shape of the two prior fires, whose output likewise reached trunk by
branch rather than by `/ship`.

Neither red is caused here and neither is driven here.

## 7 · The item itself — STILL NOT ADJUDICATED

No claim is made about R1-R4 and none should be inferred. `pnpm lint` on `reso-management-app`, the
four unlanded branches, the Amplify/Fly split-brain, and `doc_classifier`'s `require_role` holes were
never readable from this session — the trees do not exist here. **R1-R4 are open, correct as filed,
and unstarted.** What is refuted is the venue, and now also the sufficiency of both filed repairs —
never the plan.

Measured from inside this session: `$HOME` = `/root`; `~/Development` and `/Users` both absent;
`/home/user` holds `claude-infrastructure` only; `HEAD..origin/main` = **0**, so every read above is
a trunk read; `~/.claude/autonomy/` does not exist, so `cc-backlog` and `cc-notify` remain
unwritable from here exactly as 08-17 §5 recorded. **A cloud VM's only durable channel to the desk
is the branch it pushes** — this file and `182c81e9` are the notification.

## 8 · Operator actions

Needs the Mac; the ledger lives at `~/.claude/autonomy/backlog.jsonl`, absent here.

```
cc-backlog block 8f59467c92b0 --needs "re-dispatch only to a session HOLDING reso-management-app and doc_classifier (the local drain, per MASTER_PRODUCT_REPOS.md Phase 0) — cross-repo, unservable by any single attached cloud repo; THIRD misroute (08-15, 08-17, 08-24), premise NOT adjudicated (docs/research/venue-foreign-tree-declared-2026-08-24.md)"
```

`block`, not `reopen`: blocked on **where it was sent**, not on information or a judgment call. The
08-15 and 08-17 dispositions evidently did not park it — verify the block took rather than assuming
it.

The arm landed in `182c81e9` should make that block belt-and-braces rather than the only guard, but
it is worth confirming on the Mac, where the lane resolves and the arm is live:

```
cc-eligible check 8f59467c92b0     # expect: verdict=ineligible-foreign-tree, exit 3
```

Two rows worth filing against the class rather than this item:

```
cc-backlog add --project claude-infrastructure --title "tests/cc-venue.bats test 11 is RED on trunk — an unreadable ledger does not refuse to route; predates 7fbc0ffb" --dod-ref "docs/research/venue-foreign-tree-declared-2026-08-24.md#6"

cc-backlog add --project claude-infrastructure --title "the other 13 cross-repo-ish masters carry no targets: declaration — audit which open plans work a tree other than their own and declare it" --dod-ref "docs/research/venue-foreign-tree-declared-2026-08-24.md#3" --source 8f59467c92b0
```
