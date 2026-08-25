# `485f8f87eb5f` (reso tenant-drift) is cloud-INELIGIBLE, and the shipped arm cannot say so

**Verdict: venue refusal, not a work refusal.** Dispatched 2026-08-24 to an `anthropic_cloud` VM
whose GitHub scope is exactly `renchris/claude-infrastructure` and whose disk holds exactly that
clone. The item's subject is `renchris/reso-management-app` → `.github/workflows/tenant-drift.yml`.
That file cannot be read, edited, or landed from here, so the item was not attempted.
**Re-dispatched to the same venue 2026-08-25, 18h16m after this document landed — §5.**

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

**CONFIRMED UPSTREAM 2026-08-25, against the action's own source rather than its README** — which
documents `version` as "optional when `packageManager` exists" and says nothing at all about the
two disagreeing. `readTargetVersion()` in `pnpm/action-setup@master` `src/install-pnpm/run.ts`:

```ts
if (version) {
  if (packageManagerVersion && packageManagerVersion !== version) {
    throw new Error(`Multiple versions of pnpm specified: …
Remove one of these versions to avoid version mismatch errors like ERR_PNPM_BAD_PM_VERSION`)
  }
  return version
}
```

Three things follow that the pre-derivation could only assume. The guard is `!==`, so this is a
**disagreement** check, not a both-present check — which is why the workflow ran green until reso's
`packageManager` moved off 9 and has been red on every commit since. The action names exactly two
cures, and deleting `version:` is the correct one: deleting `packageManager` instead would satisfy
the same guard while unpinning every local `pnpm` invocation in the repo. And `return version`
means the input WINS when they agree — so bumping `version: 9` → `11.9.0` is green today and red
at the next `packageManager` bump, which is the drift this check exists to catch, in the check
itself.

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

## 5. §4's request was made to a dispatch that has no reader for it (2026-08-25)

**This is the SECOND cloud dispatch of `485f8f87eb5f`, and §1–§4 were already on trunk when it
fired.** They became reachable at `cc87238f` (2026-08-25T04:45:28Z); this session was fired at
2026-08-25T23:01:28Z — **18h16m later**, into the same venue, against the same unreachable file.
§4 addressed itself to "the next dispatch". The next dispatch was this one, and it arrived carrying
no channel by which a document on trunk could have reached it.

That is the correction §4 needs: **a doc is not a mechanism, and the dispatcher reads venue labels,
not `docs/research/`.** The reason it reads a stale one is already measured, in `cc87238f`'s own
body: *"venue-label staleness is measured per-ITEM (did trunk move under the paths this item cites)
and never per-RULE."* This item's label was written once from `project = claude-infrastructure` →
cloud (§1), and nothing since has asked again. Landing a refusal cannot invalidate a label; only
the item's own cited paths moving can, and none of this item's paths live in this repo.

Re-measured here rather than recalled, and all of §1–§2 holds: no reso clone on disk (no
`~/Development`, no `/Users/chrisren`), GitHub scope exactly `renchris/claude-infrastructure`, no
`tenant-drift.yml` anywhere on `origin/main`, `.github/workflows/` still `diagrams.yml` +
`hermetic.yml`. The tree is trunk (`HEAD..origin/main` = 0). §2's staleness arithmetic advances
with the calendar and nothing else: the last direct measurement of the failing run is now **15 days**
old, and reso's trunk remains the only oracle for whether the cure has since landed there.

`cc-backlog` still cannot discharge it, and the shape is worse than "no store": `bin/cc-backlog:995`
runs `mkdir -p "$(dirname "$BACKLOG")"` before writing, so `cc-backlog block 485f8f87eb5f` here
**succeeds** — creating `/root/.claude/autonomy/backlog.jsonl` and writing a row for an id that
store has never held, then exiting 0 into an ephemeral container. A silent exit 0 is what makes it
a fake discharge rather than a failure.

**Why this session did not repair the predicate either, and it is the code's rule rather than
caution.** The repair §1 identifies — teach `cross_repo()` to read a target repo out of the item's
text, not only its `project` field — *is* the admission rule, and `bin/cc-eligible`'s own
`OFFBOX_LANE` states the bar for changing it: *"A SESSION THIS LANE CREATED CANNOT VERIFY A CHANGE
TO THE LANE… the observer and the subject are the same object."* That list carries
`("venue", r"\bvenue\b")` precisely so an item asking for this edit is refused the cloud lane; a
cloud session performing the edit unasked is the same circularity with the gate skipped. `cc-venue:55`
keys the guard on the effect for the same reason. Both still stand.

So the item stays parked-by-hand, and the durable fix is one an on-box session can make without
touching the lane rule at all: **this item's target repo exists only in its prose.** Put
`renchris/reso-management-app` in a field the join can see, and the arm that already works for 106
of 107 (§1) works for this one too — no predicate widened, no observer judging itself.
