# The label-foreign guard shipped and works; the subject-foreign route is what is left

**2026-08-24.** Backlog item `485f8f87eb5f`, **project `claude-infrastructure`**, was dispatched to a
`--venue cloud` session whose one attached repository is `renchris/claude-infrastructure`. Its subject
is `.github/workflows/tenant-drift.yml` in **`renchris/reso-management-app`**. Unworkable on arrival —
the eighth dispatch recorded in this chain, and the first since the guard landed.

The three prior files close with *"no guard has shipped"* (`venue-foreign-repo-recurrence-2026-08-17.md`
:399, :485). **That is now false, and the correction is this file's first contribution.** `cross_repo()`
exists in `bin/cc-eligible` and refuses the label-foreign route outright. It does not refuse this item,
and cannot — which is exactly what `venue-foreign-master-redispatch-2026-08-17.md` §3 predicted seven
days ago about the remedy as filed.

## 1 · The guard is real — measured on identical item text, one field apart

Two fixtured rows carrying the **same title**, differing only in `project`, against a resolvable lane:

| row | `project` | `cc-eligible check` | rc |
|---|---|---|---|
| label-foreign | `reso-management-app` | `verdict=ineligible-cross-repo` | **3** |
| **subject-foreign — THIS item** | `claude-infrastructure` | `verdict=eligible` | **0** |

```
reach : elsewhere — project 'reso-management-app' is renchris/reso-management-app;
        the VM is given only renchris/claude-infrastructure          ← label-foreign, REFUSED
reach : reachable-or-unmeasured — either the lane's own repo, or nothing measurable — arm fails OPEN
                                                                     ← subject-foreign, PASSED
```

The discriminator is `cross_repo(project)` (`bin/cc-eligible:735-749`): it compares `repo_for(item.project)`'s
origin against the lane's. **It reads the `project` field and never the item's text.** This row's label
is accurate — the item was filed from a `claude-infrastructure` session — so every term is satisfied and
the arm passes it. §3 of the master doc argued this from the source; the table above is the measurement.

So the chain's remaining occurrences are not a guard that failed. They are the **residue** of a guard
that works on the route it was keyed to, applied to a route keyed on something else.

**Dating it is not possible from here** and I will not guess: `.git/shallow` is present at depth 50, so
`git log -S"def cross_repo"` collapses onto the shallow boundary `d8b517b2` (2026-08-23) and reports the
file as created there. The guard landed at or before that boundary; a full clone is needed to say when.

## 2 · The occurrences are drawn from an enumerable pool, and one draw is left

Prior files treat each occurrence as an independent recurrence. For the two `claude-infrastructure`-labelled
ones it is not — both come from **one filing act**. `docs/plans/CI_GREEN_PRODUCER_NOTIFICATION.md:200-203`
is a table of foreign-repo CI producers, filed as four backlog rows from the session that wrote the analysis,
all inheriting `project=claude-infrastructure`:

| filed id | subject repo | state today |
|---|---|---|
| `9333991e4544` | `doc_classifier` | **burned a cloud slot 08-15** (`venue-foreign-subject-repo-2026-08-15.md`) |
| `485f8f87eb5f` | `reso-management-app` | **burned a cloud slot today** — this file |
| `e3f988b489c3` | `reso-management-app` | parked: `blocked-tail-triage-2026-08-16.md:219` rules it TRULY-OPERATOR |
| **`54d7aff8ed8d`** | **`lakehouse-lecture`** | **live, never triaged, never fired** |

`54d7aff8ed8d` appears in exactly two places on trunk — the filing line and the table row — and in no
triage, no block, no adjudication. It is the fourth draw from a pool whose other three are accounted for.
**Predicted: it burns the next slot it is offered**, on the same route, for the same reason. That is the
same shape of prediction `cloud-venue-project-repo-mismatch-2026-08-16.md` §4 made about the second of its
two named projects; that one came true in ~24h.

The generalisable form, which is worth more than the prediction: **a session that analyses foreign repos
and files its findings mints subject-foreign rows in bulk, all stamped with the analysing session's own
project.** The pool is enumerable *before* it is drawn — grep the filing site — where the chain has so far
only ever counted occurrences *after*.

## 3 · The 08-15 discriminator fires on this row, and the alias row is why

`venue-foreign-master-redispatch-2026-08-17.md` §3 closes: the 08-15 discriminator — *an item whose text
names a dispatch-set project other than its own `project`* — *"should be restored as a conjunct of
whichever of (a)/(b) is chosen, at `cc-offload`."* Checked against this row's text and today's
`scripts/dispatch-projects.conf`, it fires, and the mechanism is a detail worth handing to an implementer:

The item's text says **`reso`**, not `reso-management-app`. A naive match against the conf's project column
still hits, because **`reso` is itself a row** — a `skip=` row kept deliberately (*"an ALIAS of
reso-management-app … item migrated to `0c9d92ba9a0a`"*), retained so a historical mislabel stays explained.
That row was written for provenance. It doubles, for free, as the spelling that catches this item's prose.

The conjunct therefore wants to match against **every row in the conf including `skip=` rows**, not only
the three `repo=` ones. Matching `repo=` alone would miss this item entirely.

## 4 · A probe method that does not manufacture its own false success

`venue-foreign-repo-recurrence-2026-08-17.md` "New fact 3" records that the 08-18 session's rails probe
**created** `~/.claude/autonomy/backlog.jsonl` — `ensure_file()` does an unconditional `mkdir -p` + truncate
— after which `cc-backlog needs` returned exit 0 and a well-formed id, filing an operator step onto a tmpfs
that dies at teardown. Loud failure escalated to silent, as a side effect of probing.

Re-read on trunk today, the hazard is unchanged: `bin/cc-backlog:930-933`.

**It was not tripped here.** `~/.claude/autonomy` was absent when this session started and is absent now,
verified before and after every probe above. The arm was measured instead through its documented overrides:

```sh
env HOME=<scratch-fakehome> CC_BACKLOG_FILE=<scratch>/fixture.jsonl \
    CC_ELIGIBLE_CLOUD_REPO=<the checkout> bin/cc-eligible check <fixtured-id>
```

`CC_BACKLOG_FILE` moves the store, and a fixtured `$HOME` makes `repo_for()`'s `~/Development/<project>`
assembly resolvable — which is what the first attempt got wrong. A forced lane over an **absent**
`~/Development` refuses *both* rows for `no readable git repo`, reading as a clean discriminator when it is
an artifact; `bin/cc-eligible:694-698` warns about precisely this fixture failure. The valid form needs both
projects to resolve to real repos with distinct origins, and only then does the table in §1 mean anything.

**So: a VM in this chain can measure the venue arms without writing to the live store at all.** No later
session needs to rediscover the hazard by tripping it.

## 5 · Measured from inside this session

| what | value |
|---|---|
| host `$HOME` / cwd | `/root` / `/home/user/claude-infrastructure` |
| clone | `rev-list --count HEAD` → **50**, `.git/shallow` present |
| `HEAD..origin/main` | **0** — this tree IS trunk |
| `/Users`, `/root/Development` | both absent |
| GitHub scope | `renchris/claude-infrastructure`, one repository — reso read **denied by the harness**, not inferred |
| `bats` / `shellcheck` / `gh` | all **absent** (`jq`, `python3` present) |
| `tenant-drift` as a `.yml`/`.ts` artifact over the checkout | **0 hits** |
| `~/.claude/autonomy` | absent at session start **and at session end** |

The GitHub denial is quoted rather than assumed:

```
Access denied: repository "renchris/reso-management-app" is not configured for this session.
Allowed repositories: renchris/claude-infrastructure
```

## 6 · The item itself — NOT adjudicated

`485f8f87eb5f`'s premise is **neither confirmed nor refuted here**, and must not be recorded as either.
Its claim — `tenant-drift.yml` dying at `pnpm/action-setup` on a multiple-versions conflict, 100% failure
since 2026-05-24 — is checkable only against the reso workflow file and its Actions history, both behind
the denial quoted above. The one thing this session can say is that the claim's *provenance* is a
first-hand log read: `docs/research/ci-notification-flap-2026-08-15/A-crossrepo-census.md:140` quotes run
`31401486855`'s failure verbatim. That is evidence the premise was true **when filed**, not that it is true
now, and a fix landing in reso in the nine days since would be invisible from here.

Marking it `done` would be a false close over a guard that may still be red. Marking it refuted would
invent a measurement. It stays open, and it must not be re-fired into this VM shape.

## 7 · Not fixed here, deliberately

The conjunct §3 describes belongs at `bin/cc-offload` — the fire spends the slot, per 08-16's relocation,
which this session does not reopen. Three refusals from the prior files re-measured and still binding:

- **`bats` and `shellcheck` are absent**, so a shell change to the fire path cannot be gated here. Landing
  an ungated guard into the fire path trades a bounded waste (one slot) for an unbounded one (a fleet that
  cannot dispatch).
- **The observer is the subject.** A session this lane created cannot verify a change to the lane.
- **The choice between (a) fail-closed and (b) route-by-project remains an open operator decision**, filed
  2026-08-16, and §4 of the master doc constrains it further (a cross-repo master must resolve to
  refuse/park, never route). This file adds a ninth cost datapoint and one new constraint — the conjunct
  must read `skip=` rows — but does not pick.

What this file does change is the premise the decision is argued from: **it is no longer a choice about an
unbuilt guard.** Half of it is deployed and measured. The open question narrowed from *"which shape"* to
*"does the deployed shape get its text-keyed conjunct."*

## 8 · Operator actions

1. **The decision above is still yours** (option (a) vs (b) + the §3 conjunct). Nothing here picks it.
2. **`54d7aff8ed8d` should be triaged before it is offered a slot** — §2. It is the last live draw from a
   pool of four; triaging it costs a grep, and letting it fire costs a session.
3. **`485f8f87eb5f` needs a venue that can see `renchris/reso-management-app`** — a local claim, or a cloud
   session attached to that repo. Its premise is unverified either way (§6).

The rails this dispatch was handed (`cc-backlog done|block|reopen`, `cc-notify --role desk`) were **not
run** — deliberately, per §4. On a VM with no store they fail with `unknown id`, and the recovery a worker
naturally reaches for next (`cc-backlog needs`) succeeds onto a tmpfs. This session's report is this file,
landed on trunk, which is the only durable channel it has.
