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

## 5. It happened again on 2026-08-28 — a doc is not a store, measured

`485f8f87eb5f` was re-dispatched **four days later to the identical venue**: another
`anthropic_cloud` VM, GitHub scope `renchris/claude-infrastructure`, a **50-commit shallow clone**
(`git rev-parse --is-shallow-repository` → `true`), `$HOME=/root` with no `~/.claude/autonomy/`.
Every refusal in §1–§4 reproduced exactly. Two cloud worker slots have now been spent on one item,
and neither could touch it.

That is the prediction in §4 coming true rather than a new failure. §4 named the right command and
could not run it, so the only record of the refusal was this file — and **no arm of the dispatcher
reads `docs/research/`**. There is no repo-resident venue store to write to either: `config/` holds
no exclusion list, and `bin/cc-eligible` / `bin/cc-venue` / `bin/cc-dispatch` carry no
never-cloud/route-local denylist. The park is only expressible in the operator's backlog store, on
the box, which is precisely the surface a cloud VM does not have. **Until an on-box session runs
§4's command, this item will keep re-dispatching here on every wave.**

The guard held for the second session too, and now automatically rather than by memory: a 50-commit
grafted clone makes `HistoryOracle.certify()` return `shallow`, so this VM cannot write a venue
label at all. §1's fix — widening `cross_repo` past the `project` field — remains an on-box
session's to make, and no predicate code was written from here.

### The new finding: a SECOND arm is blind to the same field

§1 measured `cross_repo` reading `project` as a proxy for reachability. The 2026-08-28 dispatch
shows the **evidence-age arm** keying on the same field and going wrong the same way. The item's
prose says *"READ reso's own CLAUDE.md for landing policy first"*; the arm resolved that bare name
against **this** repo and reported the item's cited file as freshly touched, offering four commits
as a possible discharge:

```
078c96a13  fix(claude-md): an operator rule lived only in the live file …
eff291df6  feat(close): W3 — slots and a store, not a word cap
b8124fe6a  docs(close): the close cap is a number now …
c7e1250c8  docs: register the msg command for personal message history
```

All four are claude-infrastructure's own `CLAUDE.md`, verified with `git log --oneline -1 <sha> --
CLAUDE.md`. None has any bearing on `renchris/reso-management-app`'s tenant-drift workflow. The arm
was inviting the session to close the item as already-discharged **against the wrong repo's
history** — the false-done the FIRST STEP check exists to prevent, arriving through the check
itself.

So `project` is not one arm's local shortcut. Two independent arms — reachability and
evidence-freshness — resolve an item's subject through it, and both mis-resolve on the same
residual shape: **filed under X, specified against Y.** That widens the case for §1's fix from one
misrouted item to a class that can also manufacture a plausible wrong closure. Whichever on-box
session takes it should fix the resolution, not either arm.
