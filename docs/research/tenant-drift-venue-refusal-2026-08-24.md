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

## 5. It re-dispatched anyway — §4 is not a park, and could never have been one

**2026-08-27, three days later.** The same item `485f8f87eb5f` was dispatched to a second cloud VM
(branch `claude/fire-20260827T192028Z-61984-1`, HEAD `8ca08d17`), scope `renchris/claude-infrastructure`,
`/Users/chrisren/Development` absent, no `~/.claude/autonomy/`, `cc-notify` unreachable (it needs an
iTerm2 pane). Every venue fact in §1 re-measured identical. The brief carried no trace of this
document — it re-derived the premise-check and FIRST-STEP instructions from scratch, against a repo
it still cannot read.

**The loop is structural, not an oversight.** §4's remedy is a `cc-backlog block` command, and §4's
own last paragraph says that command is unrunnable from the only venue that ever reaches this item.
So the refusal can only ever be written as prose, prose does not change the row's state, and the
row re-enters the next wave unchanged. A document cannot park an item; only the store can. **This
file has now been read by the dispatcher exactly zero times and by refused workers twice.**

**And the class is not new.** `docs/research/` carries ten venue-refusal documents — `2026-08-11`,
`-14`, `-15` (×2), `-16`, `-17` (×2), `-21`, `-22`, `-24` — at least seven of them the same shape:
an item reaching a VM that cannot see its subject. §1's framing of this item as "the 107th instance …
the residual case the join could not see" was itself written nine days after
`venue-foreign-subject-repo-2026-08-15.md` documented the identical *filed-under-X-specified-against-Y*
route, and one day after `venue-dod-offtrunk-2026-08-24.md`. Each refused session writes a fresh
document; none can write the store; the count of documents grows and the count of parked items does
not. **The doc-per-refusal habit is the visible symptom of the missing write, and adding an eleventh
document would have been this session's contribution to it** — hence this section rather than a new
file.

Not fixed from here, for the same reason as §1: widening `cross_repo()` (bin/cc-eligible:766) to key
on an item's *target* repo rather than its `project` field would be a cloud VM editing the predicate
that admits cloud VMs, which `bin/cc-venue`'s guard forbids by name, and this shallow clone cannot
read the 107-instance history that justifies the arm's current exclusions. It is also not this item's
scope. It stays an on-box decision.

## 6. Premise state, re-checked 2026-08-27

Unchanged from §2, and now staler. **Not refuted; not confirmable from this venue.** Nothing readable
here contradicts any claim in the item. The last direct measurement of the failing workflow is still
run `31401486855` (2026-08-10T15:03Z) — now **17 days old**. The §3 fix is still *pre-derived and
unverified against reso's trunk*: an on-box session must run the FIRST-STEP check
(`git show origin/main:.github/workflows/tenant-drift.yml`) before writing the diff, because a cure
that already landed would make §3's patch a revert. Re-confirmed from here: this repo is not the
carrier — no `tenant-drift.yml` on `origin/main`, and `.github/workflows/` holds only `diagrams.yml`
and `hermetic.yml`.

The one action that ends this loop is still §4's command, and it still needs a box with the store:

```
cc-backlog block 485f8f87eb5f --needs "dispatch on-box: target is renchris/reso-management-app/.github/workflows/tenant-drift.yml, unreachable from a cloud VM (see docs/research/tenant-drift-venue-refusal-2026-08-24.md §5 — refused twice, 08-24 and 08-27)"
```
