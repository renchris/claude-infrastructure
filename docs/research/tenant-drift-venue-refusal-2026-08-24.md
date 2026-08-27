# `485f8f87eb5f` (reso tenant-drift) is cloud-INELIGIBLE, and the shipped arm cannot say so

**Verdict: venue refusal, not a work refusal.** Dispatched 2026-08-24 to an `anthropic_cloud` VM
whose GitHub scope is exactly `renchris/claude-infrastructure` and whose disk holds exactly that
clone. The item's subject is `renchris/reso-management-app` → `.github/workflows/tenant-drift.yml`.
That file cannot be read, edited, or landed from here, so the item was not attempted.

This is the 107th instance of the class `bin/cc-eligible` documents at `CROSS_REPO` — but it is
**not** the shape that arm refuses, which is why it got through.

## 1. Why the cross-repo arm passed it

`cross_repo(project)` (bin/cc-eligible:724) keys on the item's **`project` field**, resolves it
through `repo_for()` to `~/Development/<project>`, and compares origins against the lane. For this
item `project = claude-infrastructure` — the lane itself — so the arm correctly returns
"reachable" and the item was promoted.

The measured population behind that arm is items **filed under** reso (92) or doc_classifier (14).
This one is the residual case the join could not see: **filed under X, specified against Y.** It
was filed by claude-infrastructure's own CI-census work (`CI_GREEN_PRODUCER_NOTIFICATION.md` §5,
which filed all four cross-repo producers under the census's project), and its target repo appears
only in the prose, never in a field. `project` is therefore a proxy for reachability, not a
measurement of it — sound for 106 of 107, blind here.

Not fixed from this session **by rule**: `bin/cc-venue`'s guard — *"a cloud VM must never build or
run the venue rule: it would be deciding its own admission."* An on-box session owns the fix, if it
judges one item worth widening a predicate for.

## 2. The premise, checked as far as it can be checked here

**Not refuted, and not confirmable from this venue.** No claim in the item is contradicted by
anything readable here; the last direct measurement is run `31401486855` (2026-08-10T15:03Z), in
`docs/research/ci-notification-flap-2026-08-15/A-crossrepo-census.md` §5. Whether the cure has
landed on reso's trunk in the 14 days since is **unknown** — the FIRST STEP check (`git show
origin/main:<path>`) is unrunnable against a repo with no remote here. An on-box session must
re-run it before writing a diff; the census is 9 days stale and reso's own trunk is the oracle.

The claim that this repo is not the carrier **is** confirmed: no `tenant-drift.yml` on
`origin/main`, and `.github/workflows/` here holds only `diagrams.yml` and `hermetic.yml`, neither
of which mentions pnpm.

## 3. The fix, pre-derived — so the on-box session spends minutes, not an hour

Failure verbatim: `Multiple versions of pnpm specified: version 9 in the GitHub Action config …
vs pnpm@11.9.0 … in package.json`. `pnpm/action-setup` (v4) raises this whenever `with.version` is
set **and** `package.json` carries `packageManager`; it refuses to guess which wins. The fix is to
delete the `version:` input and let the action read `packageManager` — the pin then has one home
and cannot drift again, which the alternative (bumping `version: 9` to `11.9.0`) reintroduces.

```diff
       - uses: pnpm/action-setup@v4
-        with:
-          version: 9
```

**Expect the first green setup to produce a red check, and do not read that as a failed fix.** The
drift check has never once executed since 2026-05-24, so its first real run is also its first
assertion against ~3 months of unaudited tenant config. A red there is the alarm working; the
item's DoD is *the check runs*, not *the check passes*.

Batch with `6e86209ae6bc` (also open, same repo, same file family: `scripts/checks/tenant-drift.ts`
asserts manifest-vs-Turso but never env-var-vs-manifest). One reso session, both items.

## 4. What the next dispatch should do with this item

Park it out of the cloud lane and give it to a box that has reso:

```
cc-backlog block 485f8f87eb5f --needs "dispatch on-box: target is renchris/reso-management-app/.github/workflows/tenant-drift.yml, unreachable from a cloud VM (see docs/research/tenant-drift-venue-refusal-2026-08-24.md)"
```

Neither `cc-backlog` verb could be run from here — this container has no
`~/.claude/autonomy/backlog.jsonl`, so `block`/`done`/`reopen` would have created a fresh store
that nothing reads. A write that no reader can see is a fake discharge, which is the failure this
document exists instead of.

---

## 5. Second burn, 2026-08-27 — §4 was never executed, and that is now the item's largest fact

Re-dispatched to a second `anthropic_cloud` VM three days later. Same venue, same refusal, same
four measurements, re-taken rather than recalled:

| probe | 08-24 | 08-27 |
|---|---|---|
| `/Users`, `~/Development`, any `reso-management-app` clone | absent | absent |
| GitHub scope | `renchris/claude-infrastructure` | `renchris/claude-infrastructure` |
| `tenant-drift.yml` on `origin/main` here | absent (`.github/workflows/` = `diagrams.yml`, `hermetic.yml`) | unchanged |
| `~/.claude/autonomy/backlog.jsonl` | absent | absent |
| clone | 50-commit graft | 50-commit graft, `HEAD..origin/main` = 0 |

**The premise is still neither refuted nor confirmable from this venue** — §2 stands verbatim, and
its "9 days stale" is now 17. Nothing here contradicts the item; nothing here can check it. reso's
trunk remains the only oracle and this VM still cannot read it.

What is new is not about tenant-drift at all. §4 named the exact command that would have kept this
item out of the cloud lane, and the next dispatch fired it into the cloud lane anyway. For this
item, *"nothing in the dispatch chain reads plan prose"* (`venue-foreign-repo-recurrence-2026-08-17.md`)
has moved from **argued to measured**: the argument was on trunk, on-topic, in the item's own
named file, and it bought nothing. A third document recommending the same unexecuted command would
be the loop, not a contribution — which is why §6 changes the recommendation instead of repeating it.

## 6. The remedy is `venue`, not `block` — supersedes §4

§4 was wrong about the verb, and the difference matters more than the venue refusal it was written
about. `cc-backlog block` parks the row **behind a human** and out of every wave, so the item stops
burning slots and also stops draining; on a store whose blocked rows have a p90 of days, that trades
a recurring cost for an indefinite one. The item does not need a human. It needs to stop being
offered to the one venue that cannot do it.

`cc-dispatch` already reads `venuePlan` and filters the cloud queue on it — *"that is genuinely
ineligible reads `venuePlan=local` and leaves the cloud queue by the filter"* (`bin/cc-dispatch:1755`).
So the shipped one-line remedy, using existing machinery, adding no predicate and touching no gate:

```
cc-backlog venue 485f8f87eb5f --venue local \
  --why "ineligible-cross-repo: subject is renchris/reso-management-app/.github/workflows/tenant-drift.yml — unreachable from the cloud lane, which is given only renchris/claude-infrastructure (docs/research/tenant-drift-venue-refusal-2026-08-24.md)"
```

The token leads with `ineligible-cross-repo` because that is the name `bin/cc-eligible:430` already
gives this class, so a split on `": "` files it with its 106 siblings rather than minting a synonym.
After it, the row stays **open and drainable** — it simply drains on a box that has reso — and the
cloud queue loses it permanently. No operator decision, no parked row, no new arm.

Not runnable from here for the reason §4 already gave: no store. This is the on-box step.

**Why this is not a `cc-eligible` patch.** The honest fix for the *class* is upstream —
`cross_repo()` keys on the `project` field, and this item's project label is accurate while its
subject is foreign, so no reading of that field can catch it. Widening the predicate from a VM is
refused by `bin/cc-venue`'s guard (§1), and `venue-foreign-repo-recurrence-2026-08-17.md` separately
settled that the `cc-eligible` placement is the weaker of the two anyway: it gates the *claim*, while
`cc-offload` gates the *fire*, and it is the fire that spends the slot. That remains the open
decision filed 2026-08-16. The `venue` line above does not wait on it.

**Second-order note for whoever executes it.** A `venuePlan=local` row still provisions its worktree
from `project`, i.e. from `~/Development/claude-infrastructure`, so the on-box worker arrives in this
repo and must `cd` to reso itself. That is workable — on-box, both trees exist and neither is
scope-fenced — and it is strictly better than the alternative of re-filing under
`reso-management-app` (which is a `repo=` row in `scripts/dispatch-projects.conf` and would provision
correctly, but mints a NEW id: ids are keyed on `project+title+source`, so a relabel is an
add-plus-terminate, the hand migration that file documents at its `reso` alias row). One line beats
two rows unless the worktree provenance is later measured to matter.

§3's pre-derived fix is untouched and still the work.
