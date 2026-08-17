# The 08-16 prediction came true in 24 hours, on the second project it named

**2026-08-17.** Backlog item `c33f3b1cb278`, **project `reso-management-app`**, was dispatched to a
`--venue cloud` session whose one attached repository is `renchris/claude-infrastructure`. Its brief
names `/Users/chrisren/Development/reso-management-app` and cites `operationBuilder.ts:553-562`,
`batchPrefetch.ts:350-355` and `appActions.ts`. None is reachable here, so the item was **unworkable
on arrival** — the fourth such dispatch in four days.

`cloud-venue-project-repo-mismatch-2026-08-16.md` §4 closes with this sentence:

> Until one of those ships, **every** non-`claude-infrastructure` item fired via `cc-offload up` from
> this checkout burns a cloud session that cannot reach its own subject. The dispatch set currently
> lists two such projects (`scripts/dispatch-projects.conf`): `doc_classifier` and
> `reso-management-app`.

That was written one day ago. The three prior occurrences were all `doc_classifier` (or
`doc_classifier`-subjected). **This is the first `reso-management-app` one** — the second of the two
named projects, firing within ~24h of the prediction. That is the whole contribution of this file: a
prediction moving from argued to observed, on the project that had not yet been observed.

## The occurrences

*(rows appended as each new VM writes its own; nothing above is restated by them)*

| date | item | `project` | route |
|---|---|---|---|
| 08-14 | `1cc794cbc6c4` | `doc_classifier` | label-foreign |
| 08-15 | `9333991e4544` | `claude-infrastructure` | subject-foreign (label passes, text is about `doc_classifier`) |
| 08-16 | `c07fb00eb9b6` | `doc_classifier` | label-foreign — **located the cause** at `bin/cc-offload:84` |
| 08-17 | `c33f3b1cb278` | `reso-management-app` | label-foreign |
| 08-17 | `38de29ec5e59` | `doc_classifier` | label-foreign — **second cloud burn of the same item** (§ below) |

The 08-17 `reso-management-app` row is a **repeat of the 08-14/08-16 route**, not a fifth route. The class has stopped producing
new spellings and is now producing recurrences on a known mechanism — which is why nothing about the
discriminator is re-derived below.

## The cause is settled; the fix is a pending decision

`cloud-venue-project-repo-mismatch-2026-08-16.md` §2 located it and this file does not improve on it:
`REPO="${CC_OFFLOAD_REPO:-$ROOT}"` (`bin/cc-offload:84`) derives the attached repo from **the firing
checkout's** origin, and the item's `project` field is never consulted or compared. Fire from
`~/Development/claude-infrastructure` and every session gets `renchris/claude-infrastructure`
attached, whatever the brief is about.

That doc's §3 also frames the remedy correctly, and this session endorses it against the reading it
displaces: the gap is **structural — a property of the pair** (`item.project`,
`session.attached_repo`) — not a missing spelling in `bin/cc-eligible`. Two shapes are on the table,
**(a) fail closed** at fire time and **(b) route by `item.project`**, and choosing between them
depends on facts unverifiable from any VM (GitHub App installation on the second repo, whether
`cc-offload land` works against it). So this is not a specified-but-unbuilt fix; it is an **open
decision, filed 2026-08-16, now carrying a fourth datapoint of cost.**

For completeness, since the earlier files proposed a `cc-eligible`-side conjunct: the 08-14 conjunct
(*a `cloud` label requires the item's project repo to be the attached one*) would also refuse this
row on the label alone. It is the weaker of the two placements — it gates the *claim*, while
`cc-offload` gates the *fire*, and it is the fire that spends the slot.

## Measured from inside this session

| what | value |
|---|---|
| clone | `git rev-list --count HEAD` → **51**, `.git/shallow` present |
| `~/Development` (`/root/Development`), `/Users` | both absent |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| the three cited files | 0 hits over the checkout |

`cc-eligible` reads the row as cloud-suitable — correctly, on its own terms, exactly as on all three
prior occasions. The item names no local-only state, cites no sha, needs no browser, no pane, no
`launchd`. Recorded because one spelling had not been probed before: the brief names its subject as
an **absolute repo path**, and that form is read as nothing either.

| probe | verdict |
|---|---|
| the item's full text | `eligible` · classes `[]` |
| `/Users/chrisren/Development/reso-management-app` alone | `eligible` · classes `[]` |
| `project reso-management-app, repo /Users/chrisren/…` | `eligible` · classes `[]` |
| `~/Development/reso-management-app` | `eligible` · classes `[]` |

🚨 **This is a measurement, not a proposed arm.** Adding a path spelling to `bin/cc-eligible` would
be widening a denylist on a hunch — the thing that file's own header (`:25-37`) forbids — and it
would place the guard at the claim rather than at the fire. The row is here to close the question
"was it a spelling all along?" with a no, not to reopen it.

## The rails handed to this dispatch fail QUIETLY here

Worth recording once, because it is a trap for the next worker rather than a fact about this item.
The brief's blocked-path instructions are `cc-backlog block` / `cc-backlog reopen` plus
`cc-notify --role desk`. `~/.claude/autonomy/` does not exist on this VM, so both **exit 0 while
doing nothing**:

```
$ cc-backlog reopen c33f3b1cb278
cc-backlog reopen: unknown id c33f3b1cb278                            # rc 0

$ cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 reason=role-unset          # rc 0
```

A worker that ran them and trusted the exit code would report the item parked when it is not. A
cloud VM's only durable channel to the desk is the branch it pushes, so this file is the
notification.

## Operator actions

The decision from `cloud-venue-project-repo-mismatch-2026-08-16.md` §3 — **(a) fail closed vs (b)
route by project** — is unchanged and is the one that stops all four. This adds only the ledger
disposition for this item, which needs the Mac:

```
cc-backlog block c33f3b1cb278 --needs "re-dispatch to a session that can reach reso-management-app — a local claim, or a cloud fire whose attached git_repository source IS reso-management-app; premise NOT adjudicated (docs/research/venue-foreign-repo-recurrence-2026-08-17.md)"
```

`block` rather than `reopen`: the item is not blocked on information or on a judgment call, it is
blocked on **where it was sent**, and parking it out of the dispatch wave is what stops it being
re-fired into the same VM shape before the guard exists.

## Not fixed here, deliberately

`bin/cc-eligible`'s `OFFBOX_LANE` class states the binding rule: *a session this lane created cannot
verify a change to the lane — the observer and the subject are the same object.* `bin/cc-venue`'s
header says the same of a 50-commit clone deciding its own admission. `bin/cc-offload` fires paid
cloud sessions, and neither `bats` nor `shellcheck` is installed here, so the repo's gate cannot be
run on a shell change — landing an ungated guard into the fire path would trade a bounded waste for
an unbounded one. All three refusals are the 08-16 session's, restated because they still hold.

## The item itself — NOT adjudicated

No claim is made about the `/list` concurrent-delete orphan, and none should be inferred. The
`LIST_HAS_ITEMS` guard, `batchPrefetch`'s `deleteList` case and `appActions.ts`'s admin CVR scoping
were never readable from this session. The brief's own mandated first step — *read what this item
cites on TRUNK, because a post-land RED reproduces faithfully in a stale tree* (`cc-backlog
6110fc45141e`) — is unrunnable here for the strongest possible reason: there is no tree, stale or
otherwise. Diagnosing it from the brief's prose is the anti-goal `bin/cc-venue` §5 names — *"a
wrongly-routed item improvises a plausible answer against history it cannot read, and reports
success."*

---

# FIFTH OCCURRENCE, same day, later fire — `38de29ec5e59`, and this item had already burned a cloud session once

*Written from inside that fifth VM, appended to this file rather than given a third one: the class
and its cause are settled above and are not re-derived. Two facts here are new.*

**2026-08-17.** Backlog item `38de29ec5e59`, **project `doc_classifier`**, was dispatched to a
`--venue cloud` session whose one attached repository is `renchris/claude-infrastructure`. Its brief
names `/Users/chrisren/Development/doc_classifier` and its DoD ref is
`pipeline/backbone/port/build.py#L125`. Neither is reachable here — the same label-foreign route as
08-14 and 08-16, on the same project.

## New fact 1 — the class is older than this table's first row, and **this item opened it**

`bin/cc-dispatch:619-626` records item `38de29ec5e59` as *"the very first producer-routed dispatch
(session_01YcTifmgrKh3KFYuz45Rret, fired 2026-08-11T20:30Z)"* — three days before the 08-14 row.
That fire failed by a **different mechanism**, which is why it is recorded here and deliberately
**not** added to the table above: it went through `handoff-fire`'s cloud leg, the deprecated CLI
create, which *"bundle-retries, DELIVERS NO BRIEF … the session sat NOT-STARTED forever"*, and the
dispatcher's follow-up declare *"OVERWROTE the leg's correct declaration with the worktree name as
the branch, so the reconcile watched a branch the VM would never push"* (`bin/cc-dispatch:1972-1983`).
It was also born UNMANAGED — no custody, no wake, no auto-land (`:619-626`).

So `38de29ec5e59` is the first item known to have burned **two** cloud sessions, by two different
actuators, with **zero turns of work on its subject** either time: once because the brief never
arrived, once because the subject repo did not. The per-item cost of an unfixed venue is therefore
not bounded at one session — the dispatcher re-fires the row, and each new actuator introduces its
own way to waste it.

## New fact 2 — unlike the 08-17 `reso` item, this item's premise and supersession **are** adjudicable from this repo, and both resolve in its favour

The 08-17 `reso-management-app` row above could only be left NOT adjudicated, because nothing in this
checkout speaks to it. This one is different: a triage of `doc_classifier` ran **in this repo** and
its report is here.

**Premise — CONFIRMED, by a reader newer than the filing.**
`docs/plans/backlog-consolidation-2026-08-09/OUT-docclf.md:47` records a **KEEP** verdict for
`38de29ec5e59` from a run against `doc_classifier` `origin/main` @ `cc6a30a6a62c…`, with the
sub-claims read live:

- `pipeline/backbone/port/build.py:126-137` — `_stage_uv` runs
  `pip download uv==<UV_VERSION> --no-deps --only-binary=:all: <platform_args> -d <scratch>`:
  **no `--require-hashes`, no `--index-url`**.
- `build.py:480-492` — the sibling wheelhouse fetch **does** pass `--require-hashes -r requirements.lock`.
  The asymmetry the item names is real and is in one file.
- `build.py:118-122` — the `_stage_uv` docstring itself claims the binary is *"fetched with the same
  `pip download --only-binary` mechanism as the wheelhouse"* and that *"the binary's own sha256 joins
  PACKAGE_MANIFEST.json"* — i.e. **the code's own documentation states the self-referential property
  the item flags**: the packager *records* the sha it just downloaded rather than checking it against
  a pin, so `verify-package.sh` can only confirm the manifest agrees with itself.

The filed DoD ref (`#L125`) sits one line off the verified range (126-137); same function, no
discrepancy of substance.

**Supersession — DOES NOT HOLD.** The brief flags sibling `71258c80fce2` (DONE 2026-07-31T17:26:40Z)
as possibly already carrying the fix. It cannot: `doc_classifier`'s `origin/main` **has not moved
since 2026-07-30** (`OUT-docclf.md:8-14`, from a `.git/FETCH_HEAD` stamped 2026-08-09 12:26 — a fresh
read, not a stale tracking ref), so no landed change since the filing could satisfy anything; the
triage that re-read the claim live ran **2026-08-09, nine days after** that sibling reached DONE and
still found it true; and the sibling's own evidence line says its branch `wt-71258c80fce2` is *"NOT
landed on main"*. The same reasoning the 08-16 session applied to `c07fb00eb9b6` applies here
unchanged, and for the same governing measurement.

**Therefore `38de29ec5e59` is open, correct as filed, and unstarted.** It is blocked on *where it was
sent*, not on what it says.

## What the fix is, for whoever reaches a venue that can see it

Already specified — do not re-derive. `OUT-docclf.md:154-159` (cluster **M-P-2**, item 4 of 5 in its
order) states the DoD clause: *"`_stage_uv` fetches under `--require-hashes` against a pin the
packager does not itself author"*, `make ci` green, landed on `origin/main`. Its falsifier
(`OUT-docclf.md:161-164`) is:

```
git show origin/main:pipeline/backbone/port/build.py | sed -n '116,140p' | grep -q -- --require-hashes
```

That command is the whole verdict, and it is **unrunnable from this venue** — there is no
`doc_classifier` tree here to run it against. Note also that M-P-2 groups this item with four others
in the same file-and-surface set and gives an explicit order; a worker that reaches the right venue
should read that grouping before opening a diff, because two of the five conflict if done separately.

## Measured from inside this session

| what | value |
|---|---|
| clone | `git rev-list --count HEAD` → **50**, `.git/shallow` present |
| `HEAD` vs `origin/main` | **0 behind** — a fresh fetch succeeded; this VM *is* at `claude-infrastructure` trunk |
| `bin/cc-offload:84` on trunk | `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` — **unchanged; no guard has shipped** |
| `/Users`, `~/Development`, any `doc_classifier` checkout | absent (`find / -maxdepth 4 -name doc_classifier` → 0 hits) |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| `cc-eligible check 38de29ec5e59` (fixture) | `verdict=eligible` · `named: (nothing — no spelling in the list fired)` |

The `cc-eligible` verdict is the **fifth** consecutive one and is still correct on its own terms: the
work is repo-only and names no local-only state. The gap remains the pair
(`item.project`, `session.attached_repo`), exactly as §2 of the 08-16 doc argues — nothing here
reopens the widen-the-denylist question that doc closed with a no.

## The rails fail quietly here too — reproduced, with exit codes

The brief's disposition instructions (`cc-backlog done` / `block` / `reopen`, `cc-notify --role desk`)
are laptop-shaped. `~/.claude/autonomy/` does not exist on this VM, so they **exit 0 while doing
nothing** — re-measured this session, matching the 08-17 `reso` finding:

```
$ cc-backlog done 38de29ec5e59 --evidence "…"
cc-backlog done: unknown id 38de29ec5e59                                    # rc 0

$ cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 reason=role-unset                # rc 0
```

**The ledger was NOT updated by this session and must not be reported as such.** A cloud VM's only
durable channel to the desk is the branch it pushes; this file is the notification.

## Operator actions

The §3 decision from `cloud-venue-project-repo-mismatch-2026-08-16.md` — **(a) fail closed at the
fire vs (b) route by `item.project`** — is unchanged and now carries a fifth datapoint of cost, plus
the first evidence that the cost per item is not capped at one session. Nothing new is proposed.

The ledger disposition for this item needs the Mac:

```
cc-backlog block 38de29ec5e59 --needs "re-dispatch to a session that can reach renchris/doc_classifier — a local claim, or a cloud fire whose attached git_repository source IS doc_classifier; premise CONFIRMED on origin/main and supersession by 71258c80fce2 REFUTED (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § FIFTH OCCURRENCE); second cloud session burned on this item"
```

`block`, not `reopen`, and not `done`: the item is not blocked on information or on a judgment call,
it is blocked on **where it was sent**, and parking it out of the dispatch wave is what stops a sixth
fire into the same VM shape before the guard exists. Marking it `done` would be false — nothing about
`build.py` changed.

## Not fixed here, deliberately

The three refusals the 08-16 and 08-17 sessions recorded still hold verbatim and are not re-argued:
`bin/cc-offload` fires paid cloud sessions and neither `bats` nor `shellcheck` is installed here, so
the repo's gate cannot be run on a shell change; `bin/cc-eligible`'s `OFFBOX_LANE` class states that a
session this lane created cannot verify a change to the lane; and a 50-commit clone cannot adjudicate
its own admission. Landing an ungated guard into the fire path would trade a bounded waste for an
unbounded one.

**No claim is made about `build.py` beyond what `OUT-docclf.md` already verified on 2026-08-09.** The
file was never readable from this session. The premise is confirmed *by citation to a dated read of
trunk*, not by this VM re-reading it — a distinction that matters precisely because the brief's
mandated first step (read what the item cites on trunk) is unrunnable here.
