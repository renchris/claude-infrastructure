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

> **Superseded by §5 (2026-08-27): `block` alone is not enough — it leaves the misfiled `project`
> field that made the item cloud-eligible in the first place. Use the two-write discharge in §5.4.**

Park it out of the cloud lane and give it to a box that has reso:

```
cc-backlog block 485f8f87eb5f --needs "dispatch on-box: target is renchris/reso-management-app/.github/workflows/tenant-drift.yml, unreachable from a cloud VM (see docs/research/tenant-drift-venue-refusal-2026-08-24.md)"
```

Neither `cc-backlog` verb could be run from here — this container has no
`~/.claude/autonomy/backlog.jsonl`, so `block`/`done`/`reopen` would have created a fresh store
that nothing reads. A write that no reader can see is a fake discharge, which is the failure this
document exists instead of.

## 5. It recurred — 2026-08-27, same venue, second slot burned

### 5.1 The venue, re-measured rather than inherited

Re-dispatched today to another `anthropic_cloud` VM. Every fact in §1 re-established from this
container, not read off §1: GitHub scope is exactly `renchris/claude-infrastructure` (and the
session prompt forbids reading any other repo); `/home/user/` holds that one clone; `~/Development`
does not exist; `~/.claude/autonomy/` does not exist; `cc-backlog`, `cc-venue`, `cc-eligible` and
`cc-notify` are not on `PATH`. `renchris/reso-management-app` is unreachable by disk and by tool.
Identical refusal, second time.

### 5.2 The recurrence is self-proving, and it indicts the remedy, not the diagnosis

The item arrived **open**. A blocked item is parked out of the dispatch wave by construction, so
its arrival is proof that §4's `block` was never run — which is exactly what §4 said it could not
be, from here. Two cloud dispatch slots have now been spent on one unreachable item.

**A document is not a park.** Dispatch reads `~/.claude/autonomy/backlog.jsonl`; nothing in the
promotion path reads `docs/research/`. So a venue-refusal doc written *from the venue it refuses*
cannot prevent the next dispatch to that venue — it can only shorten it. This one did shorten it:
this session spent minutes confirming §3 instead of an hour re-deriving it, and that is its whole
remaining value. The park itself has to be a store write, and the store is on-box.

### 5.3 The promoting arm is unchanged — established by content, not by log

`cross_repo()` at `bin/cc-eligible:766` on `origin/main` today still keys on the item's `project`
field alone: it resolves `project` through `repo_for()` to `~/Development/<project>` and compares
origins. This item's project is `claude-infrastructure` — the lane itself — so the arm still
answers "reachable" and the item is still promotable. §1's analysis holds verbatim.

⚠️ **That claim is made from the file's content at `origin/main`, deliberately, because the log
cannot support it here.** This clone is grafted at 50 commits: its root commit `decd3402` carries
a synthetic full-tree diff dated **2026-08-25 17:12**, so `git log -- bin/cc-eligible` sees only
the last two days and is structurally incapable of speaking about 2026-08-24, the day §1 was
written. A "no commits touched it since" sentence would have read as evidence and been an artifact
of clone depth. This is the same shallow-clone blindness the `cc-venue` guard is keyed on
(`bin/cc-venue:55`) showing up one layer down, in the history a cloud session would cite.

### 5.4 The discharge — two store writes, on-box, not one

`block` parks this instance. It does **not** fix the cause, which is a misfiled `project`: the row
says `claude-infrastructure` while its subject is `renchris/reso-management-app`. Leave that and a
third dispatch is a coin-flip away. No `cc-backlog` verb mutates an existing row's project —
`add`, `needs`, `dups`, `backfill` and `list` all accept `--project`, none re-files an existing id
— so the durable discharge is a park plus a correctly-filed successor:

```
cc-backlog block 485f8f87eb5f --needs "dispatch on-box: subject is renchris/reso-management-app/.github/workflows/tenant-drift.yml, unreachable from a cloud VM; refused twice (2026-08-24, 2026-08-27) — see docs/research/tenant-drift-venue-refusal-2026-08-24.md"
cc-backlog add --project reso-management-app --title "tenant-drift.yml has never run its check: drop the version: input from pnpm/action-setup" --source tenant-drift-venue-refusal-2026-08-24
```

The successor row lands under the reso lane, where `cross_repo()` measures it correctly and refuses
to promote it to a cloud VM. An on-box reso session then applies §3's one-line diff, batched with
`6e86209ae6bc` per §2.

### 5.5 What was deliberately NOT done from here

Widening `cross_repo()` to read an item's *prose* for a repo it names — the residual
"filed under X, specified against Y" case §1 identifies — is the standing fix, and it stays with an
on-box session. Not out of deference: it is unvalidatable from this venue. The change would need
its false-positive rate measured across the whole backlog, and this container has no backlog to
measure against and no history to read the 107-instance population out of. `bin/cc-eligible`'s own
header names that move by name — *"widening a denylist on a hunch is how the tap starves"*
(`bin/cc-eligible:250`, `:317`). An unmeasurable edit to the promotion gate is worse than the
second-order bug it patches.

### 5.6 The premise, one more time

Unchanged from §2: **not refuted, and still not confirmable from this venue.** Nothing readable
here contradicts any claim in the item, and the FIRST STEP check (`git show origin/main:<path>`)
remains unrunnable against a repo with no remote in this container. The on-box session must re-run
it against reso's trunk before writing the diff — the census behind the claim is now 17 days old.
