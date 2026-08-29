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

## 5. Second dispatch, 2026-08-29 — the refusal recurred, and now it has a reader

Re-dispatched to a second `anthropic_cloud` VM five days later, same lane, same clone, same
refusal. **n=2 makes this a loop, not an incident**: §4 named the right park command and nothing
routed it, so the item stayed OPEN, stayed cloud-labelled, and burned a second VM. Every venue fact
above was re-measured today and is unchanged — `origin/main` carries no `tenant-drift.yml`,
`.github/workflows/` holds only `diagrams.yml` and `hermetic.yml`, `~/Development/reso-management-app`
does not exist, `cc-backlog` is not on `PATH`, and `~/.claude/` has no `autonomy/`.

**What changed, and it is the reason this recycle is not just §4 restated.** `c8da1242`
(2026-08-27, three days after the first refusal) built the return channel this document said did
not exist: `cloud-create-api.py --verify` now surfaces `post_turn_summary`
(`status_category` / `status_detail` / `needs_action`), and `scripts/cloud-inbox.py` +
`cc-cloud inbox` read it. So a cloud VM's park request finally has a consumer. `RUNNABLE_RE`
(`scripts/cloud-inbox.py:89`) allowlists the `cc-backlog` prefix, so §4's command classifies
**RUNNABLE** rather than PROSE and surfaces under its own heading. ⚠️ **The inbox reads and
classifies; it never executes** — deliberately, since the string is composed by a remote VM. This
routes the ask to a human at the desk; it does not discharge the item. The loop closes when someone
runs §4's line, and not before.

**The self-admission guard is true of this session by measurement, so §1's deferral stands without
needing to be remembered.** `.git/shallow` is present, `git rev-list --count HEAD` = 50, and the
graft root is `1ca8d168` — the commit that landed this very document. `HistoryOracle.certify()`
therefore returns `shallow` here and `cc-venue` cannot mint a `cloud` label, which is exactly the
mechanical form of the guard at `bin/cc-venue:55`. Widening `cross_repo` from this venue would be
deciding this session's own admission; it remains an on-box change.

**The same root defect surfaced in a SECOND mechanism this dispatch, which is the new finding.**
§1 established that `project` is a proxy for reachability rather than a measurement of it. The
dispatch brief's EVIDENCE-AGE arm made the identical substitution on a different axis: the item's
sentence says *"READ **reso's** own CLAUDE.md for landing policy first"*, and the arm extracted the
bare name `CLAUDE.md`, resolved it against the item's `project` (claude-infrastructure), and warned
that four commits had landed on it since filing — `078c96a13`, `eff291df6`, `b8124fe6a`,
`c7e1250c8`. All four touch **this** repo's `CLAUDE.md`; none can discharge an item about reso's.
Two things follow. First, a bare filename in an item body is ambiguous across repos and the
staleness check cannot see it, so the cure is the same one §1 points at: **the target repo belongs
in a field, not in prose** — fix that once and both arms stop guessing. Second, and separately:
none of the four is an ancestor of `origin/main` here (`git merge-base --is-ancestor` rc=1 on each;
they resolve only on `claude/fire-*` branches), while their *content* is on trunk — `CLAUDE.md:123`
carries the `msg` section from `c7e1250c8` and `:403` the W3 clause from `eff291df6`. That is a land
path rewriting shas, and it is why this repo's own rule is *verify landings by CONTENT, never by
count*: an evidence-age arm that cites shas will keep naming commits that no longer exist on the
branch it is measuring.

**Premise, re-checked: still not refuted, and still not confirmable from this venue.** Nothing
readable here contradicts any clause of the item. The last direct measurement is still run
`31401486855` (2026-08-10T15:03Z), now **19 days stale** — the `git show origin/main:<path>` step
the dispatch brief opens with is unrunnable against a repo with no remote here, so §3's pre-derived
one-line fix must still be re-checked against reso's trunk before anyone writes it.
