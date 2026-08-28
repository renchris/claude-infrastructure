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

## 5. 2026-08-28 — dispatched again, to the same venue. §4's cure is REFUTED.

**The second cloud dispatch of this item landed four days later, on an identical VM, and refused
identically.** This section is appended by that session. §1–§3 are re-verified and stand unchanged;
**§4 does not, and this is the deliverable** — its recommended cure is documented *in this repo* as
the thing that AMPLIFIES the loop it was meant to stop.

### 5.1 The venue facts, re-measured rather than inherited

| fact | how it was established, 2026-08-28 |
|---|---|
| GitHub scope is exactly `renchris/claude-infrastructure` | the session's own scope declaration; reading reso is *prohibited*, not merely unavailable |
| the reso clone is absent | `~/Development` does not exist; the only checkout is this repo |
| this repo is not the carrier | `.github/workflows/` holds `diagrams.yml` + `hermetic.yml`; no `tenant-drift.yml` on `origin/main` |
| tree **is** trunk | `git rev-list --count HEAD..origin/main` = 0 (so §2's staleness caveat does not apply to this reading) |
| the clone is **grafted at 50 commits** | `git rev-parse --is-shallow-repository` = true, `.git/shallow` present |
| `cc-backlog` is unrunnable | no `~/.claude/autonomy/`; the container's `~/.claude` is a fresh scaffold, not the live layer |

That fifth row is the guard firing *mechanically*, exactly as `bin/cc-eligible:74-84` says it should:
a shallow clone makes `HistoryOracle.certify()` return `shallow`, and no cloud label may be written
without a certification. The prose rule and the measurement agree here — this VM cannot certify.

### 5.2 Why `cc-backlog block` (§4) does not park this item

§4 assumed `block` removes the item from the dispatch wave until an operator acts. **It does not.**
`docs/plans/BACKLOG_DRAIN_24_7.md` records this exact id crossing the blocked boundary **in both
directions**, repeatedly, across the drain links — **eight status transitions, zero closes**:

```
blocked → open   ·  open → blocked  ·  claimed → BLOCKED  ·  open → CLAIMED
claimed → open   ·  open → claimed  ·  claimed → open     ·  open → claimed
```

The drain links name it as sitting on a **standing WOULD-UNBLOCK cloud list**, and annotate it *"the
off-box actuator is working that cluster right now — do NOT hand-touch them."* So a `block` written
here would be reverted by the unblocker and the item re-admitted to the same cloud lane, with
`project` still `claude-infrastructure`, so `cross_repo()` still passes and the next VM refuses
again. That is the loop this session is the newest turn of, not a fix for it.

`bin/cc-premise:1284-1287` already states the general form, measured on a different item:

> the item was auto-blocked for thrash, unblocked seven days on, and re-dispatched with the original
> file list verbatim. `block`/`unblock` **AMPLIFIES** this rather than pausing it — blocked items sit
> longest … and unblock is the one transition that re-admits an item to the wave without re-reading
> anything.

**Read §4 as refuted on its remedy, not on its diagnosis.** Blocking is not wrong because the item is
healthy; it is wrong because `blocked` is not a durable state for a row on the unblock list, so the
cure decays into another dispatch.

### 5.3 Why this session did not fix it either — the forbidden set is defined in-repo

The durable cure has to teach the router that this item's **target** repo is reso, whereas
`cross_repo()` keys on its **`project`** field (§1). Every place that could carry it is inside the
routing rule's own surface, which `bin/cc-dispatch:251-253` names by path:

> `CC_DISPATCH_VENUE_RULE_PATHS` (default: `bin/cc-venue`, `bin/cc-eligible`, `bin/cc-premise`) —
> **the ROUTING RULE's own surface.** A landing under any of these voids a venue label as
> `venue-rule-moved` and re-derives it.

So a diff from here would (a) be a cloud VM building the venue rule — the one thing `bin/cc-venue:55`
forbids outright, on a rationale this VM's 50-commit clone confirms rather than escapes — and (b)
void **every** venue label fleet-wide, forcing re-derivation of the whole board to service one row.
Both costs land on the operator, neither is visible from here. The alternative — adding a target-repo
field to the item — is a store write, and there is no store.

**This is a hard boundary, not a judgment call, and it is why two cloud slots have now produced
documents instead of a diff.** The third will too.

### 5.4 What actually has to happen — one on-box session, two items

The work is unchanged from §3 and remains pre-derived, so the on-box session spends minutes:

1. Re-run the FIRST STEP check against **reso's** trunk (`git show origin/main:.github/workflows/tenant-drift.yml`)
   — the census behind §3 is now ~18 days stale and reso's trunk is the oracle. If the `version: 9`
   input is already gone, the item is **done on trunk** and closes with that sha.
2. Otherwise apply §3's one-line diff, and read reso's own `CLAUDE.md` for landing policy first
   (`/ship` there is free since `fb76c35bb`, but that is a perishable fact — run its `land-status.sh`).
3. Expect the first green setup to yield a **red check**. Per §3 that is the alarm working; the DoD is
   *the check runs*.
4. Batch with `6e86209ae6bc` — same repo, same file family.

**And route it so it stops returning.** The row needs `venue=local` (or an equivalent that survives
the unblocker), not `blocked`. Only an on-box session can write that, and only an on-box session
should decide whether one item justifies widening `cross_repo()` from a `project` proxy to a
cited-target measurement — the residual case §1 measured at 1 of 107.
