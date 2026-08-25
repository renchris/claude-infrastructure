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
| 08-17 | `5ab3327ed0c8` | `reso-management-app` | label-foreign **+ store-foreign** — see § The fifth |
| 08-17 | `38de29ec5e59` | `doc_classifier` | label-foreign — **second cloud burn of the same item** (§ below) |
| 08-18 | `5ab3327ed0c8` | `reso-management-app` | label-foreign — **second cloud burn**, the day after § The fifth adjudicated it (§ below) |
| 08-23 | `616d58ac42df` | `reso-management-app` | label-foreign — after a **5-day quiet gap**; cause re-verified UNSHIPPED on trunk (§ below) |
| 08-24 | `485f8f87eb5f` | `claude-infrastructure` | subject-foreign — recorded in its own file (`tenant-drift-venue-refusal-2026-08-24.md`), not here |
| 08-25 | `485f8f87eb5f` | `claude-infrastructure` | subject-foreign — **second cloud burn**, 1 day after a venue-family doc adjudicated it by name (§ below) |

The 08-17 `reso-management-app` row is a **repeat of the 08-14/08-16 route**, not a fifth route. The class has stopped producing
new spellings and is now producing recurrences on a known mechanism — which is why nothing about the
discriminator is re-derived below.

🚨 **This table is UNDERCOUNTED, and the closing question below is now ANSWERED — 2026-08-17,
~08:52Z.** `8f59467c92b0` (project `claude-infrastructure`, the cross-repo product-repos master) was
misrouted **twice**: on 08-15 — an occurrence absent from this table because that worker recorded it
in `docs/plans/MASTER_PRODUCT_REPOS.md` rather than in a `venue-*` file, inside a commit
(`b4ddaa27`) about something else entirely — and again ~1.5h after this file landed. The true figure
is **six dispatches over five distinct items**, and any count taken from the `venue-*` family is a
floor. That re-dispatch also settles this file's *"the conclusion never reached the enforcing store"*
question at full resolution: the 08-15 disproof was written into the item's own DoD-ref plan, the
most on-topic location available, and bought two days — nothing in the dispatch chain reads plan
prose. **And it refutes the remedy as filed:** both §3 options of the 08-16 doc PASS that row, since
its `project` label is accurate and only the plan BODY names the foreign trees.
`venue-foreign-master-redispatch-2026-08-17.md`.

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

# The fifth, same day — and the first whose subject is in NO repo

**2026-08-17, second dispatch.** Backlog item `5ab3327ed0c8`, project `reso-management-app`, title
*"MEMORY.md at 23842 B of 24985 B cap — compact to <17.1KB"*, fired into a second cloud session with
the same one attached repository. Appended here rather than filed as its own note because it is the
same class on the same day and the anti-capture rule is explicit about near-duplicates — but it
carries **three facts the four above do not**, and the third changes the item's disposition.

## 1 · Store-foreign, not merely label-foreign — a new sub-case

The prior four were all *repo*-subjected: real source files, in a real repo, that this VM had not
cloned. Route (b) — *route by `item.project`* — would have made every one of them workable.

This one is not reachable by route (b) either. Its subject is the **project memory index**, which
Claude Code keys on the session's cwd and stores at

```
$CLAUDE_CONFIG_DIR/projects/<slugify(repo root)>/memory/MEMORY.md
```

— i.e. `~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/MEMORY.md`. That
path is **in no git repository at all**. Resolution measured, not assumed: `hooks/memory-nudge.sh:93-113`
builds it from `--git-common-dir`; `scripts/worktree-memory-link.sh:4-9` states the keying and the
consequence; `bin/cc-memory-rotate:26-29` refuses any path not matching `*/memory/MEMORY.md`,
"a repo file merely named MEMORY.md has no read limit to protect."

So the pair this class is normally about — (`item.project`, `session.attached_repo`) — is not the
whole discriminator. **A third state exists: the subject is not a repo object.** Attaching
`reso-management-app` would leave this item exactly as unworkable as attaching nothing. Whichever of
(a)/(b) the open 08-16 decision picks, this row needs the `~/.claude`-store arm as well.

## 2 · `cc-eligible` has the right spelling and the item walks past it

Unlike the four above — where §"Measured from inside this session" correctly concludes *no spelling
would have caught it* — this file's `BOX` list **does** carry the exact class, added 2026-08-11 (W1):

```python
("dot-claude", r"~/\.claude\b|\$HOME/\.claude\b"),   # THE LIVE LAYER
```

with the comment *"`~/.claude` DOES NOT EXIST on the VM … the artifact under discussion is not in the
repo at all."* That is this item, precisely. It is missed because the title names the **file**
(`MEMORY.md`) and never the **store** (`~/.claude`), and `SPAN_FIELDS` is title/dodRef/condition/source:

| probe | verdict |
|---|---|
| the item's full title | `eligible` · classes `[]` |
| `+ condition memory-index-over-budget` | `eligible` · classes `[]` |
| the same subject written `~/.claude/projects/…/memory/MEMORY.md` | `ineligible-box` · `dot-claude` |

🚨 **Recorded as a measurement; deliberately not fixed here.** Same three refusals the 08-16 and
c33f3b1cb278 sessions gave, all still binding: `bin/cc-eligible`'s own `OFFBOX_LANE` states that *a
session this lane created cannot verify a change to the lane — the observer and the subject are the
same object*, and its `venue` spelling exists to refuse exactly an item asking to edit that file;
`bin/cc-venue` abstains in a 50-commit clone by measurement. Re-confirmed here: `.git/shallow`
present, `git rev-list --count origin/main` → **50**. And the gate cannot be run on a shell change —
`bats` and `shellcheck` are both **ABSENT** on this VM (`jq` and `python3` are present; an earlier
`command -v bats jq` in this session returned 0 on `jq` alone and briefly read as "bats ok", which is
why this line names each tool separately).

The narrowing this needs is also **not** a hunch-widening of the kind the header forbids — the class
is already in the list and the question is only which spellings reach it. But it is still a change to
the admission predicate, so it routes home.

## 3 · The item is probably already serviced, and its premise is in a superseded unit

This is the part that makes the disposition differ from the four above, and it is why the brief's
mandated *"if the cure is already on trunk, the item is DONE"* step matters here even though the
subject is unreachable.

**A landed actuator already services this exact condition, fleet-wide.** `hooks/memory-nudge.sh:178-229`
("ACTUATE, then advise") invokes `bin/cc-memory-rotate` on **every** prompt whose index is at/over
`ROTATE_AT`, for whatever project the session's cwd resolves to — not just this repo. Both files are
present on `origin/main` (content-verified; the exact landing sha is not attributable from a clone
grafted at 50 commits, where everything older collapses onto the boundary commit `b4fc288e`). Its
header records why it exists: twelve hand-compactions in fourteen days, because *"insertion is
machine-speed … while removal was human-speed."* Hand-compacting this index is the work that
mechanism was built to stop anyone doing.

Positive control, run here against a synthetic index (200 entry lines + linked topic files):

```
before 25609 B → verdict=rotated moved=37 stage2=0 after=21355 B
                 cold=…/archive/MEMORY_ARCHIVE_2026-H2-COLD.md
```

The rotor works. Lines move verbatim; restore is a paste.

**And the item's numbers are in the unit corrected on 2026-08-15** (`cc-backlog 7a56de4c54ab`,
derivation in `hooks/lib/memory-index-measure.sh`). "23842 B of 24985 B cap" is raw disk bytes; the
loader strips YAML frontmatter and block HTML comments, trims, and compares **characters** against
**25000** — including stripping the `<!-- cold tier: … -->` pointer the rotor itself writes.
`cc-memory-rotate:36-49` reconciles this by shifting its thresholds up by the measured gap. Measured
here on a fixture at **23824 raw B** — within 18 B of the item's stated size:

```
loader-vs-disk overhead 401 B — thresholds shifted to limit=25401 rotate_at=23901 target=21401
verdict=noop size=23824 rotate_at=23901
```

**A file at this item's stated raw size read `noop`** — under the threshold, nothing to do. The
overhead is per-file, so this does not prove reso's index is fine; it proves the item's headline
figure cannot decide the question, because it is not in the unit the cap is enforced in.

One genuine mismatch survives either way: the item asks for **<17.1KB** (≈70% of 24985). The rotor's
`TARGET` is `LIMIT-4000` ≈ **21000**. No landed mechanism drives to 17.1KB, and reaching it would
mean archiving well past the sanctioned ~2.5-4 KB headroom — the **lossy, human-gated** half of
`/compact-memory`, not the rotor's reversible cold split. That target looks like a filing session's
own choice rather than any mechanism's.

## 4 · The rails, re-measured (one differs from the record above)

Same trap, one correction. `cc-notify` still fails **silently**:

```
$ cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 uuid= reason=role-unset    # rc 0
```

But `cc-backlog reopen` did **not** exit 0 here:

```
$ cc-backlog reopen 5ab3327ed0c8
cc-backlog reopen: unknown id 5ab3327ed0c8                            # rc 3
```

The §"rails fail QUIETLY" block above records rc 0 for this call. On this VM it is rc 3. The
operative warning is unchanged and now sharper: **`cc-notify` is the silent one** — a worker that
chains the two and checks only the last exit code reports a desk notification that was never
enqueued. This branch remains the only durable channel.

## 5 · Operator actions for `5ab3327ed0c8`

The 08-16 decision — **(a) fail closed vs (b) route by project** — is unchanged and still the one
that stops the class, with the §1 caveat that this row needs the `~/.claude`-store arm too, since (b)
alone does not reach it.

This item's own disposition is **not** re-dispatch. Re-measure the premise in the live unit first; if
it is under the cap, nothing needs doing and the standing condition already has an actuator:

```
cc-backlog block 5ab3327ed0c8 --needs "re-measure reso's index in the LOADER unit on the Mac — cc-memory-rotate ~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/MEMORY.md --dry-run --verbose. verdict=noop ⇒ close as already-serviced (memory-nudge auto-rotates fleet-wide at ROTATE_AT); verdict=rotated ⇒ it has already fixed itself. Re-open ONLY if a real target below the rotor's ~21000-char TARGET is wanted — that is /compact-memory's lossy, human-gated half, not the rotor's. Item's '23842 B of 24985 B' is the raw-byte unit superseded 2026-08-15 (7a56de4c54ab); premise NOT adjudicated (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § The fifth)."
```

`block` rather than `reopen`, for the reason given above and one more: `reopen` returns it to the
wave, and the guard that would stop it being re-fired into this same VM shape does not exist yet.

## 6 · The item itself — NOT adjudicated

Whether reso's index is over its cap today was never readable from this session. `/root/.claude/projects/`
contains exactly one entry, this session's own `-home-user-claude-infrastructure`; `/Users` and
`/root/Development` are absent. Everything in §3 is a measurement of the **mechanism** — on trunk, and
on synthetic fixtures built here — never of the operator's index. No compaction was performed, none
should be inferred, and the 17.1KB target is reported as a mismatch to adjudicate, not as a defect
found.

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

---

# 2026-08-18 — `5ab3327ed0c8` FIRED AGAIN, and both rails blocks above are wrong

*Written from inside the next VM, appended here rather than given a sixth `venue-*` file: this file
already owns this item (§ The fifth), and the master doc's §2 measured that a new filename per
occurrence is what makes the census a floor instead of a total. The class and its cause are settled
above and are not re-derived. **Three facts are new, and two of them CORRECT this file.***

**2026-08-18, ~07:58Z.** Backlog item `5ab3327ed0c8` — *"MEMORY.md at 23842 B of 24985 B cap —
compact to <17.1KB"*, project **`reso-management-app`** — was dispatched to a `--venue cloud` session
whose one attached repository is `renchris/claude-infrastructure`. `/Users` and `/root/Development`
are absent; `/home/user` holds `claude-infrastructure` alone. Unworkable on arrival, for the second
time, **one day after § The fifth adjudicated it and prescribed `block`.**

## New fact 1 — the second item to burn two cloud sessions, and the first whose shape option (a) already refuses

`venue-foreign-master-redispatch-2026-08-17.md` §1 demonstrated a re-dispatch of `8f59467c92b0` and
drew the right conclusion for that row: it is **subject-foreign**, its `project` label is accurate,
and *both* filed options pass it — so its recurrence indicts the remedy as under-specified.

This row is the other shape. `project` = `reso-management-app`, attached repo = `claude-infrastructure`:
the pair is unequal, so **option (a) — fail closed when `--item`'s project is not the attached repo —
refuses it on its own terms, with no subject arm needed.** Its recurrence therefore says something
narrower and harder: not that the remedy is mis-specified, but that **it is still unbuilt.**
Re-verified on trunk today (`HEAD..origin/main` = 0, so every read below is a trunk read):

```
bin/cc-offload:84   REPO="${CC_OFFLOAD_REPO:-$ROOT}"            # cause unchanged
grep -rniE 'foreign.?repo|subject.?foreign|attached.?repo' bin/ scripts/ hooks/
                    → 1 hit, hooks/worktree-setup.sh:86, unrelated prose
```

And the disposition's own failure is now measured twice, on two different items. § The fifth's park
was a `cc-backlog block` command **that only the Mac can run** — the ledger lives at
`~/.claude/autonomy/backlog.jsonl`, absent from every VM. A disposition the deciding session cannot
enact does not park anything; it is a note. `8f59467c92b0` proved that for plan prose (master §1),
and this row proves it for an operator-action code block, which is the *stronger* case: the 08-17
session did everything its brief asked, wrote the exact command, and the item was re-fired in ~23 h.

## New fact 2 — 🚨 the rails do NOT fail quietly. Every `rc 0` in this file's rails blocks is a probe artifact

Both rails blocks above — and the one in the master doc — record `rc 0` and build a standing warning
on it (*"`cc-notify` is the silent one … a worker that chains the two and checks only the last exit
code reports a desk notification that was never enqueued"*). § The fifth then read its own `rc 3` for
`reopen` as a difference **between VMs**. It is not. Both readings reproduce on ONE box, in
consecutive commands, differing only in the pipeline:

| invocation | rc |
|---|---|
| `bin/cc-backlog reopen 5ab3327ed0c8` | **3** (`unknown id`) |
| `bin/cc-backlog reopen 5ab3327ed0c8 2>&1 \| head -2` → `$?` | **0** ← `head`'s status, not the tool's |
| `bin/cc-notify --role desk "…"` | **3** (`verdict=unresolvable enqueued=0 reason=role-unset`) |

`$?` after a pipeline is the LAST element's status, and every rails block in this family was written
with `| head`. The trunk source agrees with the unpiped reading and has no support for the other:
`bin/cc-notify:15` documents *"Missing/empty role file → exit 3"*, and `cc-backlog` returns 3 on an
unknown id. **So the warning inverts: both rails fail LOUDLY. What is silent is the way they were
measured** — which is the more portable lesson, and the reason this correction is worth more than the
datapoint it replaces.

## New fact 3 — the probe CREATES the store, and `cc-backlog needs` then reports SUCCESS

`~/.claude/autonomy/` does not exist on a fresh VM — this file and the master both say so, and it was
absent when this session started. It is not absent after the rails are tried: `ensure_file()`
(`bin/cc-backlog:908-911`) does `mkdir -p` + `: > "$BACKLOG"` unconditionally. Measured here, in
order:

```
ls /root/.claude/autonomy            → No such file or directory
bin/cc-backlog reopen 5ab3327ed0c8   → rc 3, unknown id          # and the store is now created
bin/cc-backlog block  5ab3327ed0c8 --needs "…"   → rc 3, unknown id
bin/cc-backlog needs  "probe step" --project reso-management-app → rc 0, echoes b3a403c16f95
bin/cc-backlog list --all → blocked | b3a403c16f95 | reso-management-app | probe step
```

`needs` does not take a known id — it FILES a new row — so it cannot fail the way `block` and
`reopen` do. Against the empty store its own predecessor just created, it succeeds completely: exit
0, a well-formed 12-hex id, and a row that reads `blocked` in `list`. Everything a worker would check
says the operator step is filed. It is filed on a tmpfs that dies at teardown.

This is reachable straight from the brief every misrouted worker receives, which names both verbs —
*"If blocked on an OPERATOR-only step … `cc-backlog block <id> --needs`"* — and a worker whose `block`
returns `unknown id` will very reasonably reach for `needs` next. **The failure mode escalates from
loud to silent as a side effect of the worker's own probing**, and the silent end is strictly worse
than the `unknown id` this file has been recording: an id that addresses nothing looks exactly like
an id that addresses something.

## Measured from inside this session

| what | value |
|---|---|
| host `$HOME` / cwd | `/root` / `/home/user/claude-infrastructure` |
| clone | `rev-list --count HEAD` → **50**, `is-shallow-repository` → **true** |
| `HEAD..origin/main` | **0** — this tree IS trunk |
| `/Users`, `/root/Development` | both absent |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| `bats` / `shellcheck` / `shfmt` | **all absent** (`jq`, `python3` present) |
| `bin/cc-eligible check 5ab3327ed0c8` (fixtured on the item's real title) | `verdict=eligible`, classes `[]`, rc 0 |

That last row re-confirms § The fifth §2 on today's trunk: the `dot-claude` spelling that describes
this item exactly is never reached, because the title names the file and not the store. Adding
`--venue cloud` to the fixture changes nothing — the gate is what the producer already consulted.

## Operator actions

Needs the Mac. The 08-17 command is unchanged in substance; re-issued with the second burn recorded,
since the first issuance evidently did not take:

```
cc-backlog block 5ab3327ed0c8 --needs "re-measure reso's index in the LOADER unit on the Mac — cc-memory-rotate ~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/MEMORY.md --dry-run --verbose. verdict=noop ⇒ close as already-serviced (memory-nudge auto-rotates fleet-wide at ROTATE_AT); verdict=rotated ⇒ it has already fixed itself. Re-open ONLY if a real target below the rotor's ~21000-char TARGET is wanted — that is /compact-memory's lossy, human-gated half. Item's '23842 B of 24985 B' is the raw-byte unit superseded 2026-08-15 (7a56de4c54ab). SECOND cloud burn (08-17, 08-18); premise NOT adjudicated (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § 2026-08-18)."
```

**Verify the block took, rather than assuming it** — that is the whole lesson of new fact 1, and the
same warning the master doc gave for `8f59467c92b0` one occurrence before this one.

## Not fixed here, deliberately

The three standing refusals hold verbatim and are re-measured, not inherited: `bats` and `shellcheck`
are absent, so the repo's gate cannot be run on a change to `bin/cc-offload`, which fires **paid**
sessions — landing an ungated guard there trades a bounded waste (one slot) for an unbounded one (a
wrong refusal starves the tap); `bin/cc-eligible`'s `OFFBOX_LANE` class states that a session this
lane created cannot verify a change to the lane, and its `venue` spelling exists to refuse exactly an
item asking to edit that file; and `bin/cc-venue` abstains in a 50-commit clone by measurement
(`is-shallow-repository` → `true`, re-confirmed above).

New facts 2 and 3 are corrections to *this file*, not to the fire path, which is why they land here
and land now: they change what the next misrouted worker believes about its own exit codes.

## The item itself — NOT adjudicated

Unchanged from § The fifth, and for the same reason: whether reso's index is over its cap today was
never readable from this session. `/root/.claude/projects/` holds exactly one entry, this session's
own. No compaction was performed and none should be inferred. The brief's mandated first step — read
what the item cites on trunk — was run in full for the `claude-infrastructure` half (`HEAD..origin/main`
= 0) and is unrunnable for the subject, which is in no tree here and, per § The fifth §1, in no git
repository at all.

**The ledger was NOT updated by this session.** The `b3a403c16f95` row in new fact 3 is a probe
artifact on an ephemeral store and must not be looked for on the Mac. This branch is the notification.

---

# 2026-08-23 — the class resumes after a 5-day gap, and the cause is still on trunk

**Backlog item `616d58ac42df`, project `reso-management-app`**, fired into a `--venue cloud` session
whose one attached repository is `renchris/claude-infrastructure`. Its brief names
`/Users/chrisren/Development/reso-management-app` and cites `venueSvgData.ts:34-38`,
`venueSvgRendering.ts:92` and `FLOOR_PLAN.md`. None is reachable here — the same label-foreign route
as 08-14/08-16/08-17/08-18, on the same project. **Eighth dispatch, sixth distinct item, third
distinct `reso-management-app` item.**

Nothing about the discriminator, the cause, the rails or the standing refusals is re-derived; all of
it is settled above and holds verbatim. Two facts are new, and both are dates rather than mechanisms.

## New fact 1 — the gap was not a fix

The last recorded occurrence is **08-18**. This one is **08-23**: five days with no row. A gap that
size invites the reading that the tap stopped producing foreign fires — which is exactly the reading
this row refutes. The class did not stop; it resumed on the project it had already burned twice.
That matters for how the pending decision is prioritised: quiet is not evidence, because the
producer (`bin/cc-offload`) is unchanged and only the *arrival rate of foreign-project items* moved.

## New fact 2 — the cause is re-verified UNSHIPPED, seven days after it was filed

Measured on today's trunk from inside this session (`HEAD..origin/main` → **0**, so this tree IS
trunk — the brief's mandated first step, run in full for the `claude-infrastructure` half):

| what | value |
|---|---|
| `bin/cc-offload:84` | `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` — **unchanged** since the 08-16 session located it |
| a `(item.project, attached_repo)` pair arm in `bin/cc-eligible` | **absent** — `grep` for `attached`/`item.project`/`foreign` hits only two prose comments |
| `cc-eligible check` (fixtured on this item's real title + source) | `verdict=eligible`, classes `[]`, rc 0, `history.state: no-repo` for `/root/Development/reso-management-app` |

So the 08-16 decision — **(a) fail closed at fire time vs (b) route by `item.project`** — is now
**seven days open and carrying eight dispatches of cost**. The `no-repo` fail-open is the 08-14
note's finding, unchanged and correctly by design; it is recorded here only to show the gate was
consulted and still abstains.

## The rails — new facts 2 and 3 of the 08-18 section both reproduce exactly

Recorded because reproduction is what turns a correction into a rule, and because a worker reading
only the *earlier* rails blocks in this file would still be misled. Unpiped, on this VM:

```
bin/cc-backlog reopen 616d58ac42df   → rc 3   (unknown id)
bin/cc-notify --role desk "…"        → rc 3   (verdict=unresolvable enqueued=0 reason=role-unset)
```

Both fail **loudly**, as the 08-18 correction established — every `rc 0` in the older blocks is a
`| head` artifact. And the store-creation side effect reproduces too: `/root/.claude/autonomy/` was
absent at session start and exists after the first `reopen` (`ensure_file()`, `bin/cc-backlog:908-911`),
holding a 0-byte `backlog.jsonl`. **`cc-backlog needs` was deliberately NOT run here** — per the 08-18
finding it would have succeeded against that empty store and filed a well-formed id addressing
nothing. The 08-18 warning is therefore load-bearing and worked: it changed this session's behaviour.

## Measured from inside this session

| what | value |
|---|---|
| host `$HOME` / cwd | `/root` / `/home/user/claude-infrastructure` |
| clone | `rev-list --count HEAD` → **50**, `is-shallow-repository` → **true** |
| `HEAD..origin/main` | **0** — this tree IS trunk |
| `/Users`, `/root/Development` | both absent |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| the three cited files | **0 hits** over the whole checkout |
| `bats` / `shellcheck` / `shfmt` | all **ABSENT** (`jq`, `python3`, `node` present) |

## Operator actions

Needs the Mac. Same disposition as the other `reso-management-app` rows, and `block` rather than
`reopen` for the same reason: the item is blocked on **where it was sent**, not on information or a
judgment call, and the guard that would stop it being re-fired into this same VM shape does not exist
yet.

```
cc-backlog block 616d58ac42df --needs "re-dispatch to a session that can reach reso-management-app — a local claim, or a cloud fire whose attached git_repository source IS reso-management-app. EIGHTH foreign-repo dispatch; cause re-verified unshipped on trunk 2026-08-23 (bin/cc-offload:84). Premise NOT adjudicated (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § 2026-08-23)."
```

**Verify the block took rather than assuming it** — the standing warning from new fact 1 of the
08-18 section, which this session had no way to run.

## Not fixed here, deliberately

The three standing refusals are re-measured, not inherited, and all three still bind: `bats` and
`shellcheck` are **absent**, so the repo's gate cannot be run on a change to `bin/cc-offload`, which
fires **paid** sessions — landing an ungated guard there trades a bounded waste (one slot) for an
unbounded one (a wrong refusal starves the tap); `bin/cc-eligible`'s `OFFBOX_LANE` class states that
a session this lane created cannot verify a change to the lane; and `bin/cc-venue` abstains in a
50-commit clone by measurement (`is-shallow-repository` → `true`, re-confirmed above).

## The item itself — NOT adjudicated

No claim is made about the floor-plan doc rot, and none should be inferred. Whether
`venueSvgData.ts:34-38` still carries the dead docblock, whether `contentBounds` is required at
`venueSvgRendering.ts:92`, whether `FLOOR_PLAN.md` frontmatter still reads `status:open`, and whether
the FIRE STATE table and OP-7 are stale — none was readable from this session; the files return 0
hits over the entire checkout. The brief's own mandated first step (*read what this item cites on
TRUNK, because a post-land RED reproduces faithfully in a stale tree* — `cc-backlog 6110fc45141e`) is
unrunnable here for the strongest reason available: there is no tree, stale or otherwise. Its
companion clause — *if the cure is already on trunk, the item is DONE* — is equally unrunnable, and
the item may well be exactly that: its own premise is that two prior premises went dead without the
doc noticing, which is the shape of work that resolves itself. Deciding that from the brief's prose
is the anti-goal `bin/cc-venue` §5 names — *"a wrongly-routed item improvises a plausible answer
against history it cannot read, and reports success."*

**The ledger was NOT updated by this session** — both rails returned rc 3, and the
`/root/.claude/autonomy/backlog.jsonl` this session's probe created is empty and dies at teardown.
This branch is the notification.

---

# 2026-08-25 — a doc filed to stop a re-dispatch did not stop it, and the residual class gets its third member

**Backlog item `485f8f87eb5f`, project `claude-infrastructure`**, fired into a `--venue cloud`
session whose one attached repository is `renchris/claude-infrastructure`. Its subject is
`renchris/reso-management-app` → `.github/workflows/tenant-drift.yml`. **Ninth dispatch, seventh
distinct item — and the second burn of an item that a venue-family doc adjudicated by name, one day
earlier.**

Nothing about the discriminator, the cause, the rails or the standing refusals is re-derived; all of
it is settled above and holds. Three facts are new.

## New fact 1 — the residual class now has three members, and it is the class BOTH filed remedies pass

This row is **subject-foreign**, not label-foreign: `project = claude-infrastructure` is *accurate* —
the item was filed by this repo's own CI-census work (`CI_GREEN_PRODUCER_NOTIFICATION.md` §5) — and
the target repo appears only in the prose. `cross_repo()` (`bin/cc-eligible:724`) keys on the
`project` field, resolves it through `repo_for()`, compares origins against the lane, and correctly
returns *reachable*. The gate was consulted and was right on its own terms.

So neither shape of the open 08-16 decision stops this row. **(b) route by `item.project`** would
attach `claude-infrastructure` — which is what already happened, twice. **(a) fail closed at fire
time**, as filed, certifies on the same field and passes it equally. This file already ruled exactly
that for `8f59467c92b0`: *"both §3 options PASS that row, since its `project` label is accurate and
only the plan BODY names the foreign trees."* That ruling now has a third member — `9333991e4544`
(08-15), `8f59467c92b0` (08-15/08-17), `485f8f87eb5f` (08-24/08-25) — and it is the class with the
**worst** recurrence rate in the table: every one of the three has burned at least two sessions.

The portable form: **`project` is a proxy for reachability, not a measurement of it.** Six of the
nine dispatches are fixed by making the label authoritative; three are not, because the label is
already right and the *brief* is what points elsewhere. A remedy keyed on the field cannot see them.

## New fact 2 — 🚨 a `docs/research/` venue-family doc, titled with the item id, does not stop a re-dispatch either

This is the fact worth the commit. The 08-15 row established that *"nothing in the dispatch chain
reads plan prose"* — the disproof was written into the item's own DoD-ref plan, the most on-topic
location then available, and bought two days. The obvious escape from that finding is **location**:
maybe a plan file is simply the wrong shelf, and a note filed in the `venue-*` research family, named
for the item, would be read.

It is not, and that escape is now closed. `docs/research/tenant-drift-venue-refusal-2026-08-24.md`
was filed on trunk, in this directory, with the item's id in its first line, stating the item is
cloud-ineligible and naming the exact `cc-backlog block` that parks it. **The item was re-fired into
the identical VM shape within ~24 hours.** Re-verified from inside this session:

| what | value |
|---|---|
| `bin/cc-offload:84` | `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` — **unchanged**, nine days after the 08-16 session located it |
| a `(item.project, attached_repo)` pair arm in `bin/cc-eligible` | **absent** — `grep` for `attached`/`item.project`/`foreign` hits one prose comment (`:410`) |
| anything in the dispatch chain reading `docs/research/` | **nothing** — `bin/cc-offload` has one hit, a comment about TSV field collapse; `bin/cc-dispatch`'s two are citations in comments |

The generalisation, which is the reason to record this rather than a ninth tally mark: **a document
is not a store.** Shelf, title and specificity make no difference, because no reader exists on the
path that would have to consult one. Every future session that reaches this venue should file its
conclusion where a reader already looks, or accept that the conclusion buys nothing but a record —
which is what this file is, honestly labelled.

## New fact 3 — the item is not covered by `M-reso-1`'s falsifier, though it is the purest instance of that effort's own theme

`docs/plans/backlog-consolidation-2026-08-09/OUT-reso.md` builds one master reso item, **`M-reso-1` —
*"every reso gate and monitor either measures what it claims, or says it cannot"***, and gives it a
six-conjunct falsifier (`:197`) whose exit 0 means the effort is no longer needed. That falsifier
greps `.github/workflows/` for `fabricated\|menu-guard` only. **Nothing in it asserts that
`tenant-drift.yml` ever runs.**

A gate that has not executed once since 2026-05-24 while continuing to appear in the workflow list is
the strongest possible member of *"measures what it claims, or says it cannot"* — it does neither, and
it is the only member of that theme the effort cannot detect. `M-reso-1` could be driven to exit 0
with this check still dead for three months.

**This is not a defect in the consolidation.** `485f8f87eb5f` was filed 2026-08-15, six days *after*
`OUT-reso.md` froze its falsifier; the consolidator could not have covered an item that did not exist.
The transferable defect is structural and belongs to the effort format: **a falsifier is frozen at
authoring time, and nothing re-opens one when a later item lands inside its file footprint.** This
item's footprint (`.github/workflows/`) is named verbatim in `M-reso-1`'s own disjointness argument
(`:281`).

Its correct home is that sequence, and the sequence already has the slot: step 5 (`b384effb4100`) is
`.github/workflows/`-owned, and step 6 (`6e86209ae6bc`) is the same file family
(`scripts/checks/tenant-drift.ts`) — which is independently what
`tenant-drift-venue-refusal-2026-08-24.md` §3 recommends batching with. **One reso session, three
items, one owner.**

## The premise — the cited path is RESOLVED, from two dated repo-resident measurements

The brief flags `tenant-drift.yml` as a cited name with no directory component and no carrier on
`origin/main`, and asks that the location be resolved before the absence is read as evidence. It
resolves here, without reaching reso:

| source | date | what it says |
|---|---|---|
| `OUT-reso.md:28` | 2026-08-09 | reso's `.github/workflows/` holds `grafana-validate(.disabled)`, `security-scan`, `soketi-image-cve-scan`, **`tenant-drift`** — an on-disk listing in reso |
| `ci-notification-flap-2026-08-15/A-crossrepo-census.md:140` | 2026-08-10 | run `31401486855`, failure verbatim, located in the **setup step, before the drift check itself ever runs** |

So the file is `renchris/reso-management-app` → `.github/workflows/tenant-drift.yml`, it existed 16
days ago, and its absence from `origin/main` here is **correct and expected** — this repo is not the
carrier, which the 08-24 doc also confirmed. Nothing in the premise is refuted. The one clause that
remains unverifiable from any cloud VM is whether the cure has landed on reso's trunk in the 15 days
since the last direct measurement; reso's trunk is the oracle and it is unreachable here.

## Measured from inside this session

| what | value |
|---|---|
| clone | `git rev-list --count HEAD` → **50**, `.git/shallow` present |
| `HEAD..origin/main` | **0** — this tree IS trunk for the `claude-infrastructure` half |
| `/Users`, `/root/Development` | both absent |
| `~/.claude/autonomy/` | absent |
| `cc-backlog`, `cc-eligible`, `cc-venue` on `PATH` | none — present in the checkout, not installed |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| the cited file | 0 hits over the checkout outside the two prose citations above |

## The rails were NOT probed, deliberately — new fact 3 of the 08-18 section, applied

This session ran **no** `cc-backlog` verb. That is a change in posture, not an omission, and the
reason is this file's own 08-18 finding: `ensure_file()` creates the store as a side effect of any
probe, after which `cc-backlog needs` succeeds completely — exit 0, a well-formed id, a row that reads
`blocked` — on a tmpfs that dies at teardown. Every earlier session in this family probed first and
documented the wreckage second.

**Two corrections to that finding's citation, both verified on today's trunk.** It has drifted to
`bin/cc-backlog:994-997`, not `:908-911` — the 08-18 line numbers now point at `OPERATOR_CONDITION`,
so a future session checking the reference would find nothing and might read the whole finding as
stale. And the body is

```sh
ensure_file() {
  mkdir -p "$(dirname "$BACKLOG")" 2>/dev/null || true
  [ -f "$BACKLOG" ] || : > "$BACKLOG"
}
```

— the `mkdir -p` is unconditional but the truncation is **guarded by `[ -f ]`**, so "does `mkdir -p` +
`: > "$BACKLOG"` unconditionally" overstates it. The consequence the 08-18 section drew is unaffected
and stands: on a VM where `~/.claude/autonomy/` is absent, a probe creates both the directory and an
empty store, and every later verb then reports success against it.

The store's absence was therefore established by `ls` alone, which is non-destructive and sufficient.
**The ledger was NOT updated by this session, and no phantom row was created.** This branch is the
notification.

## Operator actions

The 08-16 decision — **(a) fail closed at fire time vs (b) route by `item.project`** — is unchanged,
**nine days open, carrying nine dispatches of cost**, and per new fact 1 it does **not** cover this
row or the two others in its class. A third shape is now needed alongside it: *certify against the
item's cited paths, not its label* — `cc-venue paths <id>` already computes exactly that path set,
so the input exists and is unread by the fire path.

This item's ledger disposition needs the Mac:

```
cc-backlog block 485f8f87eb5f --needs "re-dispatch on-box: subject is renchris/reso-management-app/.github/workflows/tenant-drift.yml, unreachable from a cloud VM. Fix pre-derived (drop the `version:` input from pnpm/action-setup@v4) in docs/research/tenant-drift-venue-refusal-2026-08-24.md §3; batch with 6e86209ae6bc and b384effb4100 as M-reso-1 steps 5-6. Premise NOT refuted; reso trunk unverified since 2026-08-10."
```

`block` rather than `reopen`: the item is blocked on **where it was sent**, not on information or a
judgment call. **Verify the block took rather than assuming it** — the standing warning from new fact
1 of the 08-18 section, which this session had no way to run.

## Not fixed here, deliberately

All three standing refusals re-measured, and all three still bind. `bin/cc-venue`'s guard is the
binding one for the fix this row argues for: *"a cloud VM must never build or run the venue rule: it
would be deciding its own admission, and its 50-commit clone cannot read the history that justifies
the exclusions."* Widening the certification to the cited-path set **is** authoring an exclusion, and
this clone is 50 commits with `.git/shallow` present — so `HistoryOracle.certify()` returns `shallow`
by construction and the guard's mechanical arm is active, not merely its prose. `bin/cc-eligible`'s
`OFFBOX_LANE` class states the same of the lane. And `bats`/`shellcheck` are absent, so the repo's
gate cannot be run on a change to `bin/cc-offload`, which fires **paid** sessions.

Two sessions have now independently reached this refusal on this item. That agreement is itself the
argument for moving the work rather than re-dispatching it a tenth time.

## The item itself — NOT adjudicated

No claim is made about `tenant-drift.yml`'s current state on reso's trunk, and none should be
inferred. The pre-derived fix in the 08-24 doc §3 is endorsed as *reasoning* and was not verified
here — the file returns 0 hits over this checkout. The brief's mandated first step (*read what this
item cites on TRUNK*) is unrunnable for the strongest reason available: there is no tree, stale or
otherwise. Its companion clause — *if the cure is already on trunk, the item is DONE* — is equally
unrunnable, and 15 days have passed since the last direct measurement, so the on-box session must
re-run it before writing a diff. Deciding it from the brief's prose is the anti-goal `bin/cc-venue`
§5 names — *"a wrongly-routed item improvises a plausible answer against history it cannot read, and
reports success."*

## Addendum, same session — 🚨 the standing "the gate cannot be run here" refusal is WRONG, and the truth is worse

Every section above (08-17 through 08-23) carries a version of *"`bats` and `shellcheck` are absent,
so the repo's gate cannot be run on a shell change."* Both binaries are indeed absent. But the
inference drawn from that — *the gate is simply unavailable here* — is false, and this session
measured the real behaviour by running the docs-only land it was entitled to run.

`scripts/ship-land.sh --dry-run` **runs**, reaches its ratchet phase, and exits **6 — GATE RED**, on
a three-file markdown diff. The red arm is `unattended-path-lint --selftest`, which fails **11 of
42**. It fails **identically on clean `origin/main`** — measured in a throwaway worktree at
`origin/main` with this session's commit absent — so it is **pre-existing on trunk, not caused by any
diff**, and `ship-land.sh` fails closed. **No land of any kind is possible from this venue.**

### Why it is red, and why the fix it prints must NOT be applied

The lint's real-tree arm reports 20 `EMBEDDED_ALLOWLIST` entries as no longer needed and instructs:

> `Fix: delete their lines from EMBEDDED_ALLOWLIST … — the ratchet only shrinks.`

The flagged entries are `timeout`, `gtimeout`, `sysctl`, `taskpolicy`, `lsof`, `gh`, `cc-notify`. An
allowlist entry is judged stale when its binary **resolves on the unattended PATH**, so the verdict is
a pure function of *which binaries exist on the box running the lint*. Measured here:

| binary | this Linux VM | why it matters |
|---|---|---|
| `timeout` | **present** (`/usr/bin/timeout`) | not in macOS's base system — which is why the repo uses `gtimeout` at all |
| `gtimeout`, `taskpolicy`, `osascript`, `plutil`, `gh`, `cc-notify` | **absent** | all present or installed on the operator's Mac |
| `sysctl` | `/usr/sbin` | reachable here; the Mac's unattended `launchd` PATH is the case this lint exists for |

So the ratchet is macOS-tuned and this is a Linux VM, and the inversion on `timeout` alone is enough
to produce the false *"stale allowlist"* verdict. **A cloud session that obeyed the printed fix would
delete protections the operator's box still needs, and the ratchet-only-shrinks rule means the
deletion is designed to be hard to undo.** The gate's own remediation instruction is actively harmful
when followed from this venue — which is a strictly worse trap than a gate that merely refuses to
start, because this one prints a confident, specific, wrong instruction to a worker with no way to
check it.

Two portable consequences, and the second is the one that generalises past this repo:

1. **This is not a trunk regression and must not be filed as one.** Nothing is wrong on the Mac. Any
   future VM that reports "trunk gate is red" from this venue is reporting its own environment.
2. **`ship-land.sh` is not venue-portable, and it fails closed rather than abstaining.** A ratchet
   whose verdict depends on the host's installed binaries has no way to say *"I am not on the box I
   was written for"* — so it converts an unmeasurable state into a RED, which is the opposite of the
   fail-open law `bin/cc-eligible`'s header states for exactly this reason. Whether the right shape is
   an abstain arm keyed on `uname`/a marker file, or a pinned tool manifest, is a real decision and it
   needs the box that can verify both sides.

This is why the commit on this branch is pushed **but not landed**, and it is the honest version of
the refusal the four sections above were reaching for.
