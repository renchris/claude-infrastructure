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

## 5. Second burn, 2026-08-28 — the doc is on trunk and the dispatcher does not read it

Re-dispatched to another `anthropic_cloud` VM four days after §1–§4 landed. Everything above held;
nothing in it needed revising. What this run adds is one **measurement** where 08-24 had an
inference, and one conclusion about where a fix can live.

**The refusal is now measured, not argued.** 08-24 reasoned from the session's declared scope.
This run asked GitHub for the file and was denied at the tool boundary:

```
mcp__github__get_file_contents(renchris/reso-management-app, .github/workflows/tenant-drift.yml)
→ Access denied: repository "renchris/reso-management-app" is not configured for this session.
  Allowed repositories: renchris/claude-infrastructure
```

So the premise is **still not refuted and still not confirmable here**: whether the one-line cure in
§3 has landed on reso's trunk in the 18 days since run `31401486855` cannot be read from this venue
by any route — not the filesystem, not the git remote, not the GitHub API. §3 stands as written and
is what an on-box session should verify against reso's trunk before writing anything.

**A document is the wrong carrier and this run proves the cost.** `venue-foreign-repo-recurrence-2026-08-17.md`
already established that nothing in the dispatch chain reads prose, and that a disproof written into
an item's own DoD-ref plan bought two days. This file was the most on-topic location available for
this item, it landed on trunk, and it bought four days and then zero — the item was fired again, at
its own doc, into the same wall. Two cloud slots have now been spent producing analyses that agree
with each other and cannot reach the store that dispatches.

**The residue is therefore one operator action, unchanged from §4 and now twice-owed.** Run on-box,
where the store exists:

```
cc-backlog block 485f8f87eb5f --needs "dispatch on-box: target is renchris/reso-management-app/.github/workflows/tenant-drift.yml, unreachable from a cloud VM (see docs/research/tenant-drift-venue-refusal-2026-08-24.md)"
```

Until that row flips, this item is a standing cloud-slot burn on a ~9-day timer, and the next VM
will write a sixth `venue-*` document saying so. The class-level remedy remains the open decision
filed 2026-08-16 — fail-closed at fire time (`bin/cc-offload:84`) vs route-by-`item.project` — and
this item is the case that **route-by-project would not have caught**: its `project` field is
accurate, so only fail-closed on the (`attached_repo`, `subject`) pair reaches it.
