# `485f8f87eb5f` (reso tenant-drift) is cloud-INELIGIBLE, and the shipped arm cannot say so

**Verdict: venue refusal, not a work refusal.** Dispatched 2026-08-24 to an `anthropic_cloud` VM
whose GitHub scope is exactly `renchris/claude-infrastructure` and whose disk holds exactly that
clone. The item's subject is `renchris/reso-management-app` → `.github/workflows/tenant-drift.yml`.
That file cannot be read, edited, or landed from here, so the item was not attempted.

This is the 107th instance of the class `bin/cc-eligible` documents at `CROSS_REPO` — but it is
**not** the shape that arm refuses, which is why it got through.

> **Re-dispatched 2026-08-26 into the same venue — see §5.** This document landed on trunk and did
> not park the item, because a dispatch reads the store and not `docs/research/`. The one command
> that discharges it is in §4 and needs a box that has `~/.claude/autonomy/backlog.jsonl`.

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

## 5. It re-dispatched. A DOC IS NOT A PARK — measured 2026-08-26

**This document landed on trunk and did not stop anything.** It is an ancestor of `origin/main`
via `04c00694`, and two days later `485f8f87eb5f` was dispatched **again**, into a venue whose
constraints are identical in every measured respect:

| Fact | 2026-08-24 | 2026-08-26 (this session) |
|---|---|---|
| GitHub scope | `renchris/claude-infrastructure` | `renchris/claude-infrastructure` |
| reso clone on disk | absent | absent (`~/Development` does not exist) |
| clone depth | shallow | shallow, 50 commits |
| `~/.claude/autonomy/backlog.jsonl` | absent | absent |
| `cc-backlog` on `PATH` | absent | absent |
| `tenant-drift.yml` / `pnpm` on trunk | neither | neither (`.github/workflows/` = `diagrams.yml`, `hermetic.yml`) |

Two worker slots now spent on one unreachable item, and the second one arrived carrying a freshly
regenerated premise-check block — so whatever else is true, **the item is not parked.** (From here
it cannot be distinguished whether §4's `block` was never run or was run and later reopened; the
observable is that it dispatched as open.)

**The generalisable defect, which is larger than this item.** §4 was written as advice to *the next
dispatch*, but a dispatch reads the store, not `docs/research/`. Nothing in the pipeline consumes a
refusal doc, so a cloud-refused item whose only artifact is a document re-enters the wave on every
cycle, forever, at one burned slot each. The refusal was correct, complete, and pre-derived the fix
— and was still worth zero, because it was written to the wrong surface. **A refusal is discharged
by a store write or it is not discharged.**

That changes §1's closing sentence from a question of judgement into arithmetic. The predicate
widening is no longer "if an on-box session judges one item worth it" — the cost is not one item,
it is one slot per wave until someone spends a single command. The command is in §4 and needs a box
with the store; it remains unrunnable from this venue, for the same reason it was on 2026-08-24.

**Still not fixed from here, and the guard is now confirmed mechanical rather than remembered.**
`bin/cc-eligible`'s shallow guard keys on the dangerous effect — a cloud label minted from a
truncated clone — and `git rev-parse --is-shallow-repository` returns `true` here at 50 commits, so
`HistoryOracle.certify()` returns `shallow` and abstention is automatic. The rule against building
the venue rule from inside the lane stands on its own footing anyway: *a session this lane created
cannot verify a change to the lane* (`bin/cc-eligible:221`) — if a widened `cross_repo` were wrong,
every failure mode is invisible from inside the session the lane produced.
