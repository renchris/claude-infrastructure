# A cloud fire attaches the FIRING repo, never the ITEM's repo — measured 2026-08-16

**Written from inside the VM that the defect produced.** A `doc_classifier` backlog item
(`c07fb00eb9b6`) was dispatched into an `anthropic_cloud` session whose one attached repository is
`renchris/claude-infrastructure`. The item's own subject — `pipeline/s9_export/reconciler.py`,
`report.py`, `loader.py` — is in a repo this VM cannot obtain, so the item is unworkable here by
construction. Nothing in the fire path noticed.

This document is the disposition of that item **and** the located cause, because the cause is in
`claude-infrastructure` (this repo) while the item is not.

---

## 1 · The item: `c07fb00eb9b6` — BLOCKED on venue, NOT refuted, NOT superseded

The dispatch brief asked for a premise check and a supersession adjudication before acting. Both are
answerable from evidence already in this repo; neither outcome is "refuted".

**Premise — CONFIRMED, and by a reader newer than the filing.**
`docs/plans/backlog-consolidation-2026-08-09/OUT-docclf.md:35` records a **KEEP** verdict for this
item from a triage run against `doc_classifier` `origin/main` @ `cc6a30a6a62c664a1e06c799bb829f6c00b1fa57`,
with the sub-claims re-read live:

- `pipeline/backbone/cli.py:1884` still raises *"a TargetReader adapter is installed but the reconcile
  bridge is not wired"* — the "no production caller until B22" premise, verbatim.
- `pipeline/s9_export/report.py:125` — `render_report(report, quarantine)` takes the roster **beside**
  the report; the render is `_header/_counts/_dollars/_columns/_quarantine/_verdict` with **no**
  `record_hash(quarantine) == report.quarantine_ref` assertion anywhere.
- `pipeline/s9_export/loader.py:93,280` — `staged_batch_hashes` is a tuple of `record_hash` per batch,
  i.e. **keys, not bytes**, as filed.

**Supersession — DOES NOT HOLD.** The dispatch brief flags sibling `71258c80fce2` (DONE
2026-07-31T17:26:40Z) as possibly carrying this fix. It does not: the triage above ran **2026-08-09**,
nine days *after* that sibling reached DONE, read `origin/main` fresh (`.git/FETCH_HEAD` stamped
2026-08-09 12:26), and still found every sub-claim live. The same report records the governing reason
this cannot have decayed — `doc_classifier`'s `origin/main` **has not moved since 2026-07-30**
(`OUT-docclf.md:8-14`), so no landed change since the filing could satisfy the item. The sibling's own
evidence line says its branch `wt-71258c80fce2` is *"NOT landed on main"*.

**Therefore the item is open, correct as filed, and unstarted.** It is blocked on *where it was sent*,
not on what it says. It is also, per that report's sequencing (`OUT-docclf.md:192-196`), the
worst-consequence item in its cluster — a wrong GO on the artifact that signs Gate 4 — while being the
least urgent, because the path that exposes it is unwired until B22.

**Why it could not be worked here:** `/Users` does not exist on this host; no `doc_classifier`
checkout exists anywhere on this filesystem; and GitHub reaches this VM only through MCP tools scoped
to `renchris/claude-infrastructure`, which excludes `renchris/doc_classifier`
(`OUT-docclf.md:3` records that remote). Reading the cited files on trunk — the brief's mandated FIRST
STEP — is not possible from this venue.

---

## 2 · The cause: the attached repo comes from the firer's cwd, the brief comes from the item

`cc-offload up` accepts the backlog item (`--item`, `bin/cc-offload:390`) and the brief
(`--task`), and carries the item through to the declare (`bin/cc-offload:550`). The repository the
VM will actually receive comes from somewhere else entirely:

```
bin/cc-offload:84    REPO="${CC_OFFLOAD_REPO:-$ROOT}"          # $ROOT = the checkout cc-offload runs from
bin/cc-offload:520   remote_url="$(cd "$REPO" … git remote get-url origin)"
bin/cc-offload:522   repo_slug=…                               # → --repo passed to the create API
```

`repo_slug` is derived from **the firing checkout's** origin. The item's `project` field is never
consulted, and the two are never compared. Fire from `~/Development/claude-infrastructure` and every
session gets `renchris/claude-infrastructure` attached — whatever project the brief is about.

This is load-bearing because a cloud session gets **exactly one** repository, permanently:
`cc-offload up --via api` refuses unless the session reads back with exactly one `git_repository`
source (`CLOUD_BACKLOG_PIPELINE.md:48-49`), and *"GitHub reaches the VM only through MCP tools scoped
to one repository"* (`:107`). There is no in-session recovery — the worker cannot clone its way out.

**Verified VM shape** (this host): `hostname` = `vm`, `$HOME` = `/root`,
`git rev-parse --is-shallow-repository` = `true`, `git rev-list --count HEAD` = 50 — the documented
Firecracker/50-commit shape of `CLOUD_BACKLOG_PIPELINE.md:100-112`, with the wrong repo in it.

### Why the eligibility gate does not catch it (and is not wrong to miss it)

`cc-eligible` is the claim-time off-box predicate. Measured against this item's exact text:

```
$ CC_BACKLOG_FILE=<fixture> cc-eligible check c07fb00eb9b6
verdict=eligible          # exit 0 — `--venue cloud` is PERMITTED
```

That verdict is **correct on its own terms**: the work is repo-only, names no `launchd`, no browser,
no pane, no `~/.claude` — nothing in `bin/cc-eligible`'s spelling lists fires, and rightly so. The
work is genuinely cloud-suitable. It was routed to the wrong VM.

The gap is structural, not a missing spelling, so widening the keyword lists would be the wrong fix
(and `bin/cc-eligible:25-37` explicitly warns against widening on a hunch). `cc-eligible` answers
*"may this WORK go off-box?"* — a property of the item alone. Nothing answers *"can the SESSION THIS
WORK IS GOING TO see this project?"* — a property of the **pair** (`item.project`,
`session.attached_repo`). Two details make the gap invisible from inside `cc-eligible`:

- `repo_for()` (`bin/cc-eligible:613-627`) maps `project` → `~/Development/<project>`, a **local**
  path. On the firing Mac that directory exists and is full, so the history oracle certifies `ok` and
  the measured arm is satisfied — while the VM is receiving a different repo entirely.
- The measured (deep-history) arm is sound by *containment*: "this clone is full and the VM's is a
  subset of it". That inference has an unstated precondition — **that the VM clones the same repo at
  all**. Here it does not, so the subset is empty and the argument does not apply. `no-repo` is a
  fail-open state by design (`bin/cc-eligible:86`), which is right for an instrument outage and
  silent for this.

The repo's own doctrine already describes the resulting failure exactly: *"a wrong ELIGIBLE puts a
worker in a VM that CANNOT do the work at all and cannot tell you so — it will improvise something
plausible against state it cannot see"* (`bin/cc-eligible:44-48`). That is this session, and only the
brief's mandated read-trunk-first step prevented the improvisation.

---

## 3 · The fix is a decision, not an edit — so it is filed, not landed

Two shapes, and choosing between them is not this session's call:

- **(a) Fail closed.** When `--item` names a project that is not the attached repo, refuse the fire.
  Minimal, matches this repo's producer-fails-closed pattern, needs an off-switch env var and must
  fail *open* when the project is empty or unresolvable. Costs nothing but the refusal.
- **(b) Route correctly.** Resolve the repo from `item.project` and attach *that*. Strictly more
  capable, but it depends on facts not verifiable from inside this VM: whether the Claude GitHub App
  is installed on `renchris/doc_classifier`, whether the firing account can reach it, and whether
  `cc-offload land` works against a second repo. `OUT-docclf.md:3-6` also notes `doc_classifier` has
  **no `CLAUDE.md` and no `/ship` rail**, so its return path is unlike this repo's.

**Not attempted here, deliberately.** `bin/cc-offload` fires paid cloud sessions, and this VM has
neither `bats` nor `shellcheck` (both confirmed absent), so the repo's gate cannot be run on a shell
change. Landing an ungated guard into the fire path — where a wrong refusal starves the cloud tap —
would trade a bounded waste for an unbounded one.

---

## 4 · Operator actions

Both need the Mac (the ledger lives at `~/.claude/autonomy/backlog.jsonl`, which does not exist in
this VM — nothing written here would survive session teardown):

```
cc-backlog block c07fb00eb9b6 --needs "re-dispatch to a session that can reach renchris/doc_classifier — a local claim, or a cloud fire whose attached git_repository source IS doc_classifier; premises re-confirmed on origin/main and not superseded (docs/research/cloud-venue-project-repo-mismatch-2026-08-16.md §1)"

cc-backlog add --project claude-infrastructure --title "cc-offload up attaches the FIRING repo, never the item's — a foreign-project item lands in a VM that cannot see its own subject (measured: c07fb00eb9b6 into a claude-infrastructure VM). Decide fail-closed guard vs route-by-project" --dod-ref "bin/cc-offload#L84" --source c07fb00eb9b6
```

Until one of those ships, **every** non-`claude-infrastructure` item fired via `cc-offload up` from
this checkout burns a cloud session that cannot reach its own subject. The dispatch set currently
lists two such projects (`scripts/dispatch-projects.conf`): `doc_classifier` and
`reso-management-app`.

---

🚨 **CONFIRMED 2026-08-17, on the second of those two projects.** `c33f3b1cb278` (project
`reso-management-app`) was fired into a `claude-infrastructure` VM and was unworkable on arrival —
~24h after this paragraph was written, and the first occurrence on `reso-management-app` rather than
`doc_classifier`. The prediction is now observed, not argued, and the §3 decision — **(a) fail
closed vs (b) route by project** — carries a fourth datapoint of cost.
`venue-foreign-repo-recurrence-2026-08-17.md`.

🚨 **§3 IS UNDER-SPECIFIED — an implementer must read this before building either option
(2026-08-17, ~08:52Z).** `8f59467c92b0` (the cross-repo product-repos master) was misrouted on 08-15
and **again** on 08-17, and **both §3 options pass it**:

- Its `project` label is `claude-infrastructure` and that IS the attached repo, so **(a) fail closed**
  finds every term satisfied. The label is accurate — the plan really does live in this repo's
  `docs/plans/` — and irrelevant: only the plan BODY names the two foreign trees. This is the
  **subject-foreign** route of `venue-foreign-subject-repo-2026-08-15.md`, whose discriminator was
  dropped, not refuted, when §2-3 here relocated the guard from the claim to the fire. Restore it as
  a conjunct at `cc-offload` — it reads the item's text against `scripts/dispatch-projects.conf`,
  both available at fire time.
- Its work spans **two** trees, so **(b) route by project** is not merely insufficient but
  *inexpressible*: a session gets exactly one `git_repository` source, permanently (`:69-72` above).
  A cross-repo master must resolve to **refuse/park**, never to route, under either shape.

Also a cost correction to the option set: *"a `projectName` entry in the plan index"* is **not a
build** — `scripts/find-plan.sh:73` already reads `.plans[$k].projectName` and prefers it over the
path-derived basename, so it is a data entry (~0 cost) that composes with (a) as a per-row stopgap.
Full measurement, and a corrected occurrence census (six dispatches / five items — the `venue-*`
family undercounts) → `venue-foreign-master-redispatch-2026-08-17.md` §§2-4.

**A FIFTH followed the same day** — `38de29ec5e59`, `doc_classifier` again, into another
`claude-infrastructure` VM. It adds the one thing the first four could not show: that item had
**already** burned a cloud session on 2026-08-11 (`bin/cc-dispatch:619-626`), by a different
mechanism, so the cost of an unfixed venue is **not capped at one session per item** — the
dispatcher re-fires the row. Its premise was re-confirmed and its supersession refuted from evidence
already in this repo, so it is open-and-unstarted, blocked purely on venue.
`venue-foreign-repo-recurrence-2026-08-17.md` § FIFTH OCCURRENCE.
