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

**VERIFIED 2026-08-26 against the action's own source**, not inferred from the message —
`pnpm/action-setup@v4` `dist/index.js`, which is readable from a cloud VM because it is a public
third-party action and not the unreachable repo:

```js
if (typeof d === "string" && d.startsWith("pnpm@") && d.replace("pnpm@","") !== t) {
  throw new Error(`Multiple versions of pnpm specified:...`)
```

`d` is `packageManager`, `t` is the `version` input, and the whole check sits inside `if (t) {…}`.
Omitting `version` makes `t` falsy, skips the conflict arm, and falls through to reading
`packageManager`. Resolution order is `version` input → `packageManager` → **error if neither
exists**.

⚠️ **That last clause is the one way this fix fails on-box, so check it before pushing:** deleting
`version:` is only correct if reso's `package.json` actually carries `packageManager`. Here it
does, and the failure text is its own proof — `vs pnpm@11.9.0 … in package.json` could not have
been printed otherwise. Confirm on trunk anyway; the census is now 16 days old.

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

## 5. It re-dispatched anyway — 2026-08-26, second refusal

**A document on trunk is not a dispatch control, and this is now measured rather than predicted.**
§4 was written on 2026-08-24 and named the one command that would park the item. Nobody ran it, so
on **2026-08-26** `485f8f87eb5f` was dispatched to a cloud VM a second time — same lane, same
scope (`renchris/claude-infrastructure`), same disk, same refusal. The second worker's whole
contribution was to re-derive §1–§2 and find them already written.

The cost is not one wasted slot. The item is now in a **loop with no natural exit**: every wave
re-promotes it, because the only artifact recording its ineligibility lives in `docs/research/`
and nothing in the dispatch path reads prose. A third dispatch is the default outcome, not a risk.

Two things were re-established from scratch this time, and both hold:

- **The venue refusal is unchanged.** No reso clone, no reso remote, GitHub scope is exactly the
  one repo, and `.github/workflows/` here still holds only `diagrams.yml` and `hermetic.yml`.
- **The guard's precondition is positively confirmed, not assumed.** `cc-venue:55` keys on the
  effect — *"a cloud label may only be written from a certification, and a shallow clone cannot
  certify."* This box: `git rev-parse --is-shallow-repository` → `true`, 50 commits, `.git/shallow`
  present. So the refusal to self-admit is grounded in a measurement of this box, which is what
  the guard asks for.

**Why the predicate was again not widened here.** The tempting read is that `cc-eligible` fails
OPEN and routes *toward* local, so a cloud→local narrowing is the safe direction the header prices
at nothing (`cc-eligible:264`). That is true of the direction and still wrong for the author: the
`cc-venue:55` guard is keyed on a cloud VM **building** the venue rule at all, and its stated
reason — *"its 50-commit clone cannot read the history that justifies the exclusions"* — is a fact
about this box that the shallow check above just confirmed. Widening from here would also be the
wrong SHAPE: `cc-eligible`'s own header warns that *"widening a denylist on a hunch is how the tap
starves"* (memory: `denylist-enumerates-spellings-not-the-class`), and adding a `reso` spelling
enumerates one spelling of the class §1 already named exactly — **filed under X, specified against
Y**. That class wants a *field* carrying the target repo, so `cross_repo()` measures reachability
instead of proxying it through `project`. A field is data an on-box session can populate; a
spelling is a hunch this box would be adding about its own admission.

**So the residue is an operator step, and it is one line.** It is not research, and it is not
work a further cloud dispatch can absorb.

## 6. Found while trying to land §5: the cloud lane cannot land in this repo either

Landing the §5 edit ran `scripts/ship-land.sh` and it exited **6 (GATE RED)** on a one-file
markdown diff:

```
✗ gate: unattended-path-lint --selftest FAILED — the detector no longer discriminates, so
  its clean verdict would mean nothing. Fix the lint before landing.
unattended-path-lint --selftest: FAILED (11 of 42) — the detector does not discriminate.
```

**Attributed before anything was touched, and it is not this diff's.** The same selftest was run
from a detached worktree at unmodified `origin/main` (`52db0d9a`) in this same container and
failed **identically — 11 of 42, same assertions**. Every other gate arm passed clean over the
diff: hermeticity (551 suites, 0 new leaks), wall-clock, AF_UNIX, moving-ref, git-identity, UTC
stamp, pipefail/SIGPIPE, self-path, pane-spawn coverage.

⚠️ **Exit 6 is documented as "your diff is red — a claim about your code, actionable, never retry
it unchanged."** Here that reading is false, and measurably so: the failing arm is a **selftest of
the detector**, which scans no part of the diff and fails the same way with the diff absent. The
`/ship` skill's own base-branch clause is the right one — *a check red on the base branch too* is
the legitimate "not mine."

**Root cause NOT diagnosed, deliberately, and it is the wrong box to diagnose it from.** The
failure signature is mixed in direction — nine assertions are `want 1, got 0` (the detector finds
nothing) but *"the real tree is not clean under the shipped allowlist"* is `want 0, got 1` (it
finds something it should not) — which is the shape of a regex-dialect difference (GNU vs BSD
`grep`/`sed`) rather than a logic regression. That is consistent with this being **Linux-specific**
in a lint written for a macOS fleet: it reasons about launchd plists and `/sbin`-only binaries, and
this container has no `shellcheck` and no `bats` at all. **It is an inference, not a measurement** —
nothing here can observe the operator's Mac, where trunk lands demonstrably succeed.

**Consequence, which is the part worth carrying:** a cloud VM in this lane can do work and commit
it, but **cannot land it** — the land path is gate-red before it reaches the lock, for a reason no
cloud-side diff can clear. Work dispatched here is therefore `📦` by construction, and the
container is ephemeral, so an unpushed cloud commit is a *loss*, not a park. This one is pushed to
its own branch rather than landed; the on-box session that picks up §4 lands it.

Not fixed here for the same reason §5 gives for the predicate: a cloud VM editing the gate that is
refusing its own land is deciding its own admission, and `unattended-path-lint` is a macOS-fleet
safety lint this box cannot test against the fleet it guards.
