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
| 08-18 | `0dafb03ed73d` | `reso-management-app` | label-foreign — **the first occurrence on a new day, after five documents** (§ below) |
| 08-19 | `21e2c1088736` | `reso-management-app` | label-foreign — **third distinct `reso` item**; first whose cargo is a POLICY DECISION (§ below) |
| 08-19 | `ce7651b02a17` | `doc_classifier` | label-foreign — **the guard already fires from here and cannot fire there** (§ SEVENTH) |
| 08-19 | `21e2c1088736` | `reso-management-app` | label-foreign — **decision-class**: route-by-project would not have finished it either (§ below) |
| 08-19 | `38de29ec5e59` | `doc_classifier` | label-foreign — **third cloud burn of the same item**, 2 days after the row above (§ SIXTH OCCURRENCE) |
| 08-19 | `38de29ec5e59` | `doc_classifier` | label-foreign — **third burn of the same item**, and the first fired *after* its disproof was on trunk (§ THIRD BURN below) |
| 08-20 | `38de29ec5e59` | `doc_classifier` | label-foreign — **THIRD burn of the same item**, and the row was still `open` at fire time (§ SIXTH OCCURRENCE) |
| 08-20 | `20caf9661ea4` | `reso-management-app` | label-foreign — first **DECISION** item; three days after the cause was located and published (§ below) |
| 09-03 | `9ce3c6350e2f` | `claude-infrastructure` | **subject-foreign** — the label is *correct* and route-by-project would still misroute it; **two weeks** after the previous row (§ EIGHTH below) |

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
# SIXTH OCCURRENCE, 2026-08-19 — `21e2c1088736`, and the first whose cargo is a POLICY DECISION

*Written from inside that VM. The class, its cause and the open remedy are settled above and are not
re-derived. Three facts are new, and the third CORRECTS the "rails fail quietly" warning this file
gives twice.*

**2026-08-19.** Backlog item `21e2c1088736`, **project `reso-management-app`**, was dispatched to a
`--venue cloud` session whose one attached repository is `renchris/claude-infrastructure`. Its brief
names `/Users/chrisren/Development/reso-management-app`, cites `operationBuilder.ts:1451,1499,1589`
and `:791-812`, and its DoD ref is
`docs/research/UNDO_SURFACE_AND_CONCURRENCY_2026-08-16.md § 2`. None is reachable here — the same
label-foreign route as 08-14, 08-16 and both 08-17 `reso` rows, on the project that has now burned
**three** cloud sessions across three distinct items.

## New fact 1 — a DECISION item is worse cargo than a bug, in two specific ways

The five above were bugs or a compaction chore. This one is explicitly *"DECISION (not a bug fix)"*:
a policy fork between **(A)** hiding/disabling Undo for `door_staff` on manager-only actions and
**(B)** widening permissions so door staff can reverse their own action. Two consequences that do not
follow from the earlier rows:

1. **The misroute withholds a cheap DISPROOF, not just an implementation.** The brief's own mandated
   first question — *can `door_staff` perform the FORWARD action at all?* — is a one-grep question
   against the reso tree, and a `no` **dissolves the item**: the same gate that rejects the undo would
   already have hidden the affordance, and the lying button is unreachable in practice. So the cost of
   sending this row to a VM is not "the fix waits"; it is that the ~2 minutes that might have closed it
   for free cannot be spent, while the slot is spent anyway.
2. **The improvisation anti-goal has a sharper shape here.** `bin/cc-venue` §5 names it — *"a wrongly-routed
   item improvises a plausible answer against history it cannot read, and reports success."* For a bug
   that yields a wrong patch. For this row it would yield a **recommendation about a permission model**,
   authored without reading a single permission gate, on a surface whose one existing carve-out
   (`door_staff` check-in) was ratified by a dated decision the brief cites (2026-06-20). That is the
   one output shape whose wrongness is least visible downstream: a diff gets reviewed against code, a
   policy verdict gets quoted.

Both are reasons to prefer `block` over any attempt to answer from the brief's prose, which is what
§ Operator actions below does.

## New fact 2 — route (b) is not an unspecified build: the project→repo mapping already exists, twice, in this repo

The open 08-16 decision is **(a) fail closed at the fire vs (b) route by `item.project`**, and the
argument for it being genuinely open is unchanged (it turns on facts no VM can verify: the GitHub App
installation on the second repo, and whether `cc-offload land` works against it). But one thing that
reads as build cost in (b) is already paid, and this session measured it rather than inferring it:

| the mapping | where it already lives |
|---|---|
| `repo_for(project)` → `~/Development/<project>` | `bin/cc-eligible:607-620`, documented as *"cc-dispatch's project_repo convention, deliberately … so the venue arm and the worktree provisioner can never disagree about which tree an item's project means"* |
| the per-project SSOT, more explicit | `scripts/dispatch-projects.conf` — `reso-management-app  repo=~/Development/reso-management-app`, already a `repo=` row |

`bin/cc-offload:84` on `origin/main` is still `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` — verified this
session, **no guard has shipped** — i.e. the fire path derives the attached repo from the firing
checkout while two in-repo sources already answer the question it is not asking. What remains open in
(b) is the two unverifiable-from-VM facts, not the resolver.

Corollary, from `cc-eligible why --json` run on a fixture of this item's text (verdict `eligible`,
`classes []` — the **sixth** consecutive such verdict, still correct on its own terms): the assessment
carries `history: {state: "no-repo", repo: "/root/Development/reso-management-app"}`. That is a
property of **this VM**, not of the Mac — on the producer the tree exists — so it is not a
ready-made discriminator, and this row does not propose it as one. It is recorded because it shows the
oracle already resolves `project → tree` inside the same assessment the fire path ignores.

## New fact 3 — CORRECTION: `cc-notify` no longer fails silently. It exits 3 and names both failures

The § "rails fail QUIETLY" block and § 4 of "The fifth" both conclude **"`cc-notify` is the silent
one"** (rc 0, `reason=role-unset`). **That is stale as of trunk today.** Re-measured here, all four
rails and their exit codes:

```
$ cc-backlog block  21e2c1088736 --needs "…"    cc-backlog block: unknown id 21e2c1088736     # rc 3
$ cc-backlog done   21e2c1088736 --evidence "…" cc-backlog done: unknown id …                 # rc 3
$ cc-backlog reopen 21e2c1088736                cc-backlog reopen: unknown id …               # rc 3
$ cc-notify --role desk "…"
    a role is pointed at a pane by cc-roles claim / handoff-fire (--as-role) / desk-register
    cc-notify: fallback=phone-unwired — push-send is INERT (PUSHOVER_TOKEN/PUSHOVER_USER unset).
    This is push-send's exit 3, NOT a role failure …                                          # rc 3
```

`cc-notify` now falls through the unresolvable role to a **phone leg** and reports a machine token for
its outcome (`bin/cc-notify:418-456`); that leg first appears inside this clone's 50-commit horizon at
`36cbb55e` (2026-08-18) — one day after the two measurements above, which is why they disagree with
this one. So a worker chaining `block` then `notify` and checking the last exit code is now warned by
**both**, and the standing advice inverts: on this VM shape every rail is loud, and the failure to
watch for is no longer a silent rc 0 but the fact that **nothing was written at all** —
`~/.claude/autonomy/backlog.jsonl` was created empty (0 bytes) by these probes and stayed empty, so no
false ledger state exists here either. **The ledger was NOT updated by this session and must not be
reported as such.** A cloud VM's only durable channel to the desk is the branch it pushes; this file
is the notification.
# The seventh — the refusal already exists, and it can only fire where it is not needed

**2026-08-19.** Backlog item `ce7651b02a17`, project `doc_classifier`, title *"reviewapp/api/auth.py:
fresh PyJWKClient per token → pre-auth JWKS fetch amplification (medium, PoC-proven: 4 fetches from 2
rejected tokens)"*, fired into a cloud session whose one attached repository is
`renchris/claude-infrastructure`. Third distinct `doc_classifier` item, two days after the last row,
`bin/cc-offload:84` byte-unchanged. The class-level facts are not restated; three things below are new,
and the first two revise conclusions recorded above rather than adding to them.

## 1 · The eligibility side is not silent on this item — it refuses, and the refusal is unreachable

Every occurrence above concluded that `cc-eligible` reads the row as cloud-suitable *and is correct on
its own terms*, and closed the widen-the-denylist question with a no. That is right about the **keyword
lists** and it is the wrong place to have stopped looking. The file's other arm — the **history
certification**, a measurement rather than a spelling — already fires on this item:

```
$ cc-eligible why ce7651b02a17                                   # fixture, this VM
  verdict : eligible
# SIXTH OCCURRENCE — `38de29ec5e59` again, two days later, and the pair is not un-computed: it is mis-classed

*Written from inside the third VM burned on this one item. The class, its cause and this item's
premise are settled above and are **not** re-derived — §"New fact 2" already confirmed the premise on
trunk and refuted the supersession, and nothing here disturbs either. One measurement below is new,
and it narrows where the guard belongs.*

**2026-08-19.** Item `38de29ec5e59`, project `doc_classifier`, dispatched to a `--venue cloud`
session whose one attached repository is `renchris/claude-infrastructure`. Same brief, same DoD ref
(`pipeline/backbone/port/build.py#L125`), same absent subject. The brief again carried the PREMISE
CHECK and SUPERSESSION preambles, and again neither is runnable here.

## The cost is now compounding on a settled diagnosis

| | |
|---|---|
| cloud sessions burned on **this item** | **three** — 08-11 (`handoff-fire` leg, brief never delivered), 08-17, 08-19 |
| turns of work on `build.py` across all three | **zero** |
| `bin/cc-offload:84` on `origin/main` today | `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` — **byte-identical; no guard has shipped** |
| the 08-16 §3 decision (a) fail-closed vs (b) route-by-project | still open, now carrying a **sixth** datapoint |

Two days of trunk activity separate this fire from the one above (54 commits; `HEAD..origin/main` = 0
here, so this VM *is* at trunk). None touched the fire path. The diagnosis has been correct and
stationary since 08-16; what is missing is the decision, not the analysis.

## The one new measurement — `no-repo` is doing two jobs, and off-box only one of them is true

The five sessions above concluded that the gap is the pair (`item.project`,
`session.attached_repo`) and that **no spelling** in `bin/cc-eligible` would catch it. Both hold.
But the pair is not *un-computed* — `cc-eligible` already resolves and reports it:

```
$ cc-eligible why 38de29ec5e59            # fixture built from this brief's own text
  verdict : eligible
  project : doc_classifier
  refused : (nothing fired)
  history : no-repo — NOT CERTIFIED: no readable git repo for this project — reach is unknown
            repo=/root/Development/doc_classifier ref=- depth=50
```

`no-repo` is one of the three states on which, per `bin/cc-eligible:86-92`, *"the GATE stays fail-open …
the PRODUCER fails closed"* — and the producer does exactly that: `bin/cc-venue:281` returns
`{"venue": "local", "token": "uncertified-history"}`. **A venue label minted from here would have been
`local`.** The guard that stops this dispatch is built, shipped and working.

It cannot fire where it is needed, and the reason is structural rather than a missing case.
`repo_for()` (`bin/cc-eligible:613-626`) resolves a project to `$HOME/Development/<project>` — a path on
**the machine doing the measuring**. On the Mac that path exists for `doc_classifier`
(`scripts/dispatch-projects.conf`: `repo=~/Development/doc_classifier`, *"verified 2026-07-29: repo
present"*; `OUT-docclf.md:3`), so the oracle reads a real, full clone, certifies reach, and the producer
promotes to `cloud`. The certification is a measurement of the **producing** filesystem being used to
predict reach on the **consuming** one, and for a foreign project those two answers are opposites by
construction: present on the box that decides, absent on the box that works.

That the path resolution — not the item's text — is what moves the verdict is measurable from here:

| resolved repo | history state |
|---|---|
| `/root/Development/doc_classifier` (absent) | `no-repo` — NOT CERTIFIED |
| `CC_ELIGIBLE_REPO=/home/user/claude-infrastructure` (present) | `shallow` — NOT CERTIFIED |

Same item text, different certification, and the only variable is which tree the oracle was pointed at.
The Mac's third answer (`reachable`, on a full clone) is **inferred** from `repo_for()`'s definition plus
the two citations above, not measured — this VM's clone is shallow, so it cannot reproduce a `reachable`
and the `shallow` guard in arm B is that refusal working as designed.

This does **not** reopen the denylist question. It relocates the fix to an arm that already exists: the
certification is sound about *reach into history* and unsound about *reach to the repo at all*, because
it never asks which repo the consuming session will attach. Both shapes on the open 08-16 decision
((a) fail closed at the fire, (b) route by `item.project`) still hold; this only shows the predicate side
is nearer to already answering than four notes have recorded, and that the missing input is
`session.attached_repo` — the same value `bin/cc-offload:84` derives from the wrong place.

**This is the third face of one generator.** `CLOUD_BACKLOG_PIPELINE.md` A2 F3 found the M2 freshness
gate refusing cloud fires *"on a staleness check about a directory the cloud session does not use"*;
`bin/cc-offload:84` attaches the firing checkout's origin rather than the item's; and the history oracle
certifies against the firing box's filesystem. Three guards, all measuring the local disk to decide
something about a remote one.

## 2 · CORRECTION — the disposition rails do **not** exit 0; they fail loudly

Both 08-17 sections record `cc-backlog` and `cc-notify` as *"exit 0 while doing nothing"*, and draw the
trap from it: *"a worker that ran them and trusted the exit code would report the item parked when it is
not."* **That does not reproduce.** Measured this session with the store absent, invoked bare:

```
$ cc-backlog block  ce7651b02a17 --needs "…"    → cc-backlog block: unknown id …    rc 3
$ cc-backlog done   ce7651b02a17 --evidence "…" → cc-backlog done: unknown id …     rc 3
$ cc-backlog reopen ce7651b02a17                → cc-backlog reopen: unknown id …   rc 3
$ cc-notify --role desk "…"                     → verdict=unresolvable enqueued=0   rc 141
                                                  + names the fix: cc-roles list
```

`bin/cc-backlog:1562` is `has_id "$id" || { …; return 3; }`. The rc-0 reading reproduces exactly, and
only, when `$?` is read after a pipe:

```
$ cc-backlog block … >/dev/null 2>&1;        echo $?   → 3
$ cc-backlog block … 2>&1 | head -1 >/dev/null; echo $?   → 0      # head's rc, not the tool's
```

Every rc quoted in the two sections above sits beside a piped, `head`-trimmed transcript. That is
consistent with a measurement artifact, and it is **not proof of one**: `63b71c0e` (2026-08-18) touched
that line, and this clone is grafted at 50 commits with its oldest reachable commit *being* `63b71c0e`,
so the pre-08-17 source is unreadable from here and the two hypotheses cannot be separated at this
venue. One command on the Mac settles it:

```
git log -L1562,1562:bin/cc-backlog --oneline | head -20
```

The operational consequence is the opposite of what is recorded above, so it is worth stating plainly:
**the rails are safe to run blind.** A worker that runs them on a VM gets a non-zero exit and a
diagnostic, not a false confirmation. The reason a cloud VM still cannot dispose of its item is that the
store is not here — not that the tools lie about it.

## 3 · The M-P-2 consolidation was decided ten days ago and never actuated

The sixth occurrence noted in passing that a worker reaching the right venue *"should read that grouping
before opening a diff, because two of the five conflict if done separately."* The dispatch record now
makes that a mechanism defect rather than advice. `OUT-docclf.md:132` groups five items — `e3d8a8cf90a4`,
`ce7651b02a17`, `38de29ec5e59`, `16319f4234a3`, `1a9f3323e4d7` — as **one effort** under one DoD, with an
explicit order in which `ce7651b02a17` is member **3**, behind a member 2 that *"must be done in one diff
or they conflict."* Two of those five have since each been dispatched as a **standalone one-item wave**:
`38de29ec5e59` on 08-17, `ce7651b02a17` today. Even a correctly-routed fire of this brief would therefore
have produced a wrong-shaped diff — a venue fix alone does not make this item workable as sent.

The ledger already ships the actuator. A `--condition` group joined with `link` gives its members a
shared **lease** that admits one at a time (`bin/cc-backlog:352`, `:525-532`), which is precisely the
constraint M-P-2 describes; `bin/cc-dispatch:1075` names *"the consolidation actuator (R6)"* as the repair
and disclaims it as out of scope for that file. Nothing joined these five. This is the same diode the
§"the conclusion never reached the enforcing store" finding names for the venue fix, arriving
independently: the consolidation is **plan prose**, and nothing in the dispatch chain reads plan prose.
# SEVENTH OCCURRENCE — 2026-08-19, `21e2c1088736` (reso): the first row that **option (b) would not have saved**

**2026-08-19.** Backlog item `21e2c1088736`, **project `reso-management-app`**, dispatched to a
`--venue cloud` session attached to `renchris/claude-infrastructure`. It cites
`operationBuilder.ts:1451,1499,1589` and `docs/research/UNDO_SURFACE_AND_CONCURRENCY_2026-08-16.md`;
`/Users` and `~/Development/reso-management-app` are both absent and the repo is outside this
session's GitHub scope, so the brief's mandated first step — read the citations on `origin/main` —
is unrunnable. Unworkable on arrival, three days after the cause was located and still unguarded.

Nothing about the mechanism is re-derived: the cause is `bin/cc-offload:84`
(`REPO="${CC_OFFLOAD_REPO:-$ROOT}"`, re-read this session and unchanged on this clone) and the
remedy is the open (a)/(b) decision. **One new fact only.**

## The new fact: option (b) is not a complete remedy, because some misrouted items are decision-class

Every prior row is a *code or analysis* item, and for all six the implied claim is that routing the
fire by `item.project` (option **b**) would have made the item workable. This row is the first where
it would not. The item's own text names its terminal state:

> THE FORK IS POLICY, not code: (A) hide/disable Undo for door_staff on manager-only actions … or
> (B) widen permissions so door staff can reverse their own action.

A correctly-routed VM with the reso checkout could answer the item's empirical opener — *can
`door_staff` perform the FORWARD action at all?*, which the item itself says may dissolve the whole
thing — and would then stop at a product policy call that belongs to the operator. So option (b)
converts this row from *unworkable* to *partially workable, terminating in `⛔`*, not to *done*.

That does not weaken the (a)/(b) decision — six of seven rows are unaffected and the cost figure is
unchanged. It refines what the decision buys: **venue routing fixes reachability, not disposition.**
A decision-class item dispatched to any autonomous worker, local or cloud, ends at the same fork;
what it wants is `cc-decide` (a class-C packet the desk adjudicates), not a dispatch slot. Whether
the dispatch set should exclude decision-class rows is a separate, unfiled question, noted here
because this is the first row that exposes it.

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
# SEVENTH OCCURRENCE, 2026-08-18 — `0dafb03ed73d`, and the documentation is not a control

**This section is one screen long on purpose.** Six prior dispatches produced five documents in five
days; the rate did not fall. Nothing above reached an *enforcing store* — the repo's own
`conclusion-must-reach-the-enforcing-store` rule, restated by every file in this family and obeyed by
none of them, because the fix is a decision (§3 of `cloud-venue-project-repo-mismatch-2026-08-16.md`)
and a document cannot make one. A sixth essay would be the same non-control at a higher cost, so this
occurrence contributes a table row, two verified facts and a disposition — nothing else.

**The occurrence.** Backlog item `0dafb03ed73d`, project `reso-management-app` — *"Amplify build cache
never WRITTEN since ~2026-06-12 … fix `cache.paths` in `amplify.yml`"* — was dispatched into an
`anthropic_cloud` session whose one attached repository is `renchris/claude-infrastructure`. The
plainest route (label-foreign), the second `reso-management-app` item in two days, and the first on a
new date. Its subject (`amplify.yml`) and its cited evidence
(`docs/research/DEP_AUDIT_2026-08-11/b2-turbopack-build-cache.md`) are both in
`~/Development/reso-management-app`, which does not exist here; GitHub reaches this VM only through
MCP tools scoped to `renchris/claude-infrastructure`. **Unworkable on arrival.**

**Fact 1 — the guard site named on 08-16 is the right one, and this is the first session to check.**
`bin/cc-offload:84` was located as the cause, but no prior doc verified that the *dispatcher* fires
through it. It does: `bin/cc-dispatch:1972-1985` selects between actuators and states that
*"THE CLOUD ACTUATOR IS `cc-offload up`, NOT a --cloud flag on the local spawn"* — the venue is a
selection between actuators, not an argv mutation. So a guard at `cc-offload` covers the dispatch path
whole. `scripts/handoff-fire.sh`'s own `--cloud` leg carries the identical defect by a second route
(`CLOUD_CWD="$PWD"`, `scripts/handoff-fire.sh:7066` — it ignores the `--cwd`/`--worktree` that would
name the item's tree), but that leg is the DEPRECATED CLI create the dispatcher no longer selects, so
it does not have to be guarded first. **One site, not two.**

**Fact 2 — what has actually been stopping the improvisation is an accident.** Across all seven
occurrences, nothing in the fire path noticed; what prevented a plausible answer against unreadable
state was the brief's mandated FIRST STEP (*read what this item cites on trunk*). That instruction is
in the template because of an unrelated incident (stale-tree diagnosis, `6110fc45141e`), not because
of this class. It is a control this class did not build and cannot rely on: it works only while briefs
keep carrying it, and it fires *after* the session is paid for.

**Measured here** (the documented shape, unchanged): `hostname` = `vm`, `$HOME` = `/root`,
`git rev-parse --is-shallow-repository` = `true`, `git rev-list --count HEAD` = 50, `HEAD..origin/main`
= 0. `bats` and `shellcheck` both absent (`command -v` rc 1), so the repo's gate cannot be run on a
shell change — the third refusal below still holds verbatim.

**The rails fail quietly, re-measured:** `~/.claude/autonomy/backlog.jsonl` does not exist, so
`cc-eligible why` returns `verdict=unknown-store` (fail-open, rc 0) and every `cc-backlog` verb would
write an ephemeral store that dies with the container. **This session did NOT update the ledger and
must not be reported as having done so.** This branch is the notification.

## Operator action

```
cc-backlog block 0dafb03ed73d --needs "re-dispatch to a session that can reach renchris/reso-management-app — a local claim, or a cloud fire whose attached git_repository source IS reso-management-app; NOT adjudicated (amplify.yml and the cited DEP_AUDIT doc are unreadable from a claude-infrastructure VM); docs/research/venue-foreign-repo-recurrence-2026-08-17.md § SEVENTH OCCURRENCE"
```

`block`, not `reopen` and not `done`: the item is blocked on **where it was sent**, not on information
or a judgment call, and parking it out of the wave is what stops an eighth fire into the same VM shape.

## Not fixed here, and the item is NOT adjudicated

The three standing refusals are unchanged and not re-argued: `bin/cc-offload` fires paid cloud sessions
and this VM cannot run the gate (measured above); `bin/cc-eligible`'s `OFFBOX_LANE` class states that a
session this lane created cannot verify a change to the lane; and §3's choice — **(a) fail closed vs
(b) route by project**, as amended by the under-specification note on cross-repo masters — is a
decision, which is precisely what a document cannot supply.

**No claim is made about the Amplify build cache.** `amplify.yml`, the `cache.paths` key, job 1457's
artifact and `b2-turbopack-build-cache.md` were never readable from this session. The item's premise is
neither confirmed nor refuted here; it is untouched.
| clone | `git rev-list --count HEAD` → **50**, `.git/shallow` present |
| `HEAD` vs `origin/main` | **0 behind** — fresh fetch; this VM *is* at `claude-infrastructure` trunk |
| `bin/cc-offload:84` on trunk | `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` — **unchanged; no guard has shipped** |
| `/Users`, `~/Development`, any `reso-management-app` checkout | absent (`find / -maxdepth 4 -name reso-management-app` → 0 hits) |
| GitHub scope | `renchris/claude-infrastructure`, one repository — `get_file_contents` on `renchris/reso-management-app` returns *"not configured for this session"*; an unauthenticated clone fails on credentials |
| the cited files (`operationBuilder.ts`, the DoD-ref doc) | 0 hits over the checkout |
| `cc-eligible check` (fixture of this item's text) | `verdict=eligible` · `classes []` · `history.state=no-repo` |

## Operator actions

The §3 decision from `cloud-venue-project-repo-mismatch-2026-08-16.md` — **(a) fail closed at the fire
vs (b) route by `item.project`** — is unchanged, now carries a sixth datapoint of cost, and is
narrowed only by New fact 2 (its resolver already exists). Nothing new is proposed.

This item's ledger disposition needs the Mac:

```
cc-backlog block 21e2c1088736 --needs "re-dispatch to a session that can reach reso-management-app — a local claim, or a cloud fire whose attached git_repository source IS reso-management-app; premise NOT adjudicated, and the brief's own first question (can door_staff perform the FORWARD action?) may dissolve it in one grep (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § SIXTH OCCURRENCE); third cloud session burned on this project"
```

`block`, not `reopen` and not `done`: the item is blocked on **where it was sent**, not on information
or on a judgment call, and parking it out of the wave is what stops a seventh fire into the same VM
shape before the guard exists. `reopen` would return it to the wave; `done` would be false — nothing
about `operationBuilder.ts` changed.

**For whoever reaches a venue that can see it**, the brief's mandated first step is the whole triage
and should be run before any policy argument is opened — against `origin/main`, never a local tree:

```
git -C ~/Development/reso-management-app fetch origin -q
git -C ~/Development/reso-management-app show origin/main:<path>/operationBuilder.ts | sed -n '780,820p;1440,1600p'
```

If `door_staff` cannot reach the forward action, the affordance is already hidden and the item closes
without touching the permission model. Only if it CAN does the (A)/(B) fork become real.

## The item itself — NOT adjudicated

No claim is made about the floor-plan undo surface, the `isManagerOrAbove` gates, the 2026-06-20
check-in carve-out, or which of (A)/(B) is right, and none should be inferred. `operationBuilder.ts`
and `UNDO_SURFACE_AND_CONCURRENCY_2026-08-16.md` were never readable from this session — the brief's
mandated first step (*read what this item cites on TRUNK*) is unrunnable here for the strongest
possible reason: there is no tree, stale or otherwise. Everything above is a measurement of the
**venue**, never of the item.
| clone | `git rev-list --count HEAD` → **50**, `.git/shallow` present, oldest reachable commit `63b71c0e` (2026-08-18) |
| `HEAD` vs `origin/main` | **0 behind** — fresh fetch succeeded |
| `bin/cc-offload:84` | `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` — **unchanged; no guard has shipped** (3 days after the decision was filed) |
| `/Users`, `~/Development`, any `doc_classifier` checkout | absent (`find / -maxdepth 4 -name doc_classifier` → 0 hits) |
| GitHub scope | `renchris/claude-infrastructure`, one repository — and `renchris/doc_classifier` exists (`OUT-docclf.md:3`) but is out of scope, so it cannot be cloned from here either |
| `cc-eligible check ce7651b02a17` (fixture) | `verdict=eligible` · `refused: (nothing fired)` · `history: no-repo` |

## The item itself — NOT adjudicated

No claim is made about `reviewapp/api/auth.py` by this session, and none should be inferred. The premise
is **confirmed by citation to a dated read of trunk** — `OUT-docclf.md:49` verified on `origin/main`
@ `cc6a30a6` that `jwt.PyJWKClient(settings.jwks_url, cache_keys=True).get_signing_key_from_jwt(...)` is
constructed inline per token at `auth.py:73`, and that `cache_keys=True` caches only within a throwaway
instance — not by this VM re-reading it. The brief's own mandated first step is unrunnable here for the
reason the fourth occurrence already gave: there is no tree, stale or otherwise. Whether the fix has
landed since 2026-07-30 is unknown from this venue; `OUT-docclf.md:163` carries the falsifier, and it
needs a `doc_classifier` checkout to run.

## Operator actions

The §3 decision from `cloud-venue-project-repo-mismatch-2026-08-16.md` — **(a) fail closed at the fire vs
(b) route by `item.project`** — is unchanged and now carries a seventh datapoint. §1 above adds one input
to it: the predicate side already computes the right answer when pointed at the consuming machine, so
whichever shape is chosen, `session.attached_repo` is the value both `bin/cc-offload:84` and
`cc-eligible`'s `repo_for()` are missing.

Two ledger dispositions need the Mac. First, this item:

```
cc-backlog block ce7651b02a17 --needs "re-dispatch to a session that can reach renchris/doc_classifier — a local claim, or a cloud fire whose attached git_repository source IS doc_classifier; AND dispatch it as part of M-P-2, not standalone (OUT-docclf.md:132 puts it 3rd of 5 behind a member that must share a diff); premise CONFIRMED by citation only (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § SEVENTH)"
```

Second, the grouping — the thing that stops members 4 and 5 being fired standalone next:

```
for i in e3d8a8cf90a4 ce7651b02a17 38de29ec5e59 16319f4234a3 1a9f3323e4d7; do cc-backlog link "$i" --condition mp-two-axis-separation-docclf; done
```

*(Signature checked against the source, not assumed: `link` takes **one** id per call
(`bin/cc-backlog:48`, `cmd_link` at `:2690-2715`), hence the loop; and the slug carries **no digit** —
`cmd_link` rejects digits outright, "a slug carrying a measurement mints one GROUP per measurement",
and its own error text prescribes spelling the numeral out. `mp2-…` would have exited 2. The group
semantics — one lease, one live member — are at `:352` and `:525-532`. Not exercised here: there is no
store on this VM, so this is a read of the code, not a dry run.)*

## Not fixed here, deliberately

The three standing refusals hold verbatim and are not re-argued: `bin/cc-offload` fires paid cloud
sessions and neither `bats` nor `shellcheck` is installed here, so the repo's gate cannot be run on a
shell change; `bin/cc-eligible`'s `OFFBOX_LANE` class states that a session this lane created cannot
verify a change to the lane; and a 50-commit clone cannot adjudicate its own admission. §1 identifies a
placement inside `bin/cc-eligible`, which is squarely inside that third refusal — it is written as a
finding for the open decision, not as a patch withheld.
| clone | `git rev-parse --is-shallow-repository` → `true`, `git rev-list --count HEAD` → **50** |
| `~/Development` (`/root/Development`), `/Users` | both absent |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| `docs/research/UNDO_SURFACE_AND_CONCURRENCY_2026-08-16.md` | 0 hits over the whole filesystem |
| `cc-eligible check 21e2c1088736` (fixture, item's real title + source) | `verdict=eligible` · exit 0 · `refused: (nothing fired)` |
| `cc-eligible why` history arm | `no-repo — NOT CERTIFIED … repo=/root/Development/reso-management-app depth=50` |

The `eligible` verdict is the **seventh** consecutive one and is again correct on its own terms — the
item names no local-only state, no browser, no pane, no sha. Note the history arm *did* see the
missing tree and is required to fail **open** there, which is right for a gate that must never starve
the tap on an instrument outage: `no-repo` measured from inside the VM cannot distinguish "this
project has no repo" from "this VM is not where that repo lives." The discriminator remains the pair
(`item.project`, `session.attached_repo`), unavailable to `cc-eligible` at claim time and available
to `cc-offload` at fire time. Unchanged from the 08-16 finding; recorded only to show it re-measured.

## The rails fail quietly here too

`~/.claude/autonomy/` does not exist on this VM, so `cc-backlog list --open` returns empty and every
disposition verb in the brief is a silent no-op — third session to reproduce this, unchanged.
**The ledger was NOT updated by this session and must not be reported as such.**

## Operator actions

The (a)/(b) decision from `cloud-venue-project-repo-mismatch-2026-08-16.md` §3 is unchanged and now
carries a seventh datapoint. Nothing new is proposed for it.
# SIXTH ITEM, THREE DAYS LATER — `20caf9661ea4`, and the first whose deliverable IS the judgment

*Written from inside that VM. The class and its cause are settled above and are not re-derived; the
three standing refusals in § Not fixed here are re-confirmed below and not re-argued. Three facts
here are new.*

**2026-08-20.** Backlog item `20caf9661ea4`, **project `reso-management-app`**, was dispatched to a
`--venue cloud` session whose one attached repository is `renchris/claude-infrastructure`. Its brief
names `/Users/chrisren/Development/reso-management-app`, its subject is the `@rocicorp/undo` package
plus `lib/create-undo-context.tsx`, `lib/undo-helpers.ts` and `lib/__tests__/undo-helpers.test.ts`,
and its DoD ref is `docs/research/UNDO_LIST_ACTIONS_AUDIT_2026-08-16.md`. None is reachable here.

## New fact 1 — the class outlived its own publication by three days, unguarded

The cause was located on 08-16 at `bin/cc-offload:84` and published in this file on 08-17. Measured
on `origin/main` today, from a fetch that succeeded:

```
$ git show origin/main:bin/cc-offload | sed -n '84p'
REPO="${CC_OFFLOAD_REPO:-$ROOT}"
```

Unchanged. `grep -n 'project\|CC_OFFLOAD_REPO'` over the same file returns that one line and nothing
else — the item's `project` field is still never consulted or compared, and no guard of either shape
has shipped. The **(a) fail closed vs (b) route by `item.project`** decision filed 2026-08-16 is
still open and now carries a sixth item and a seventh dispatch of cost (this file's own count is a
floor — see the undercount warning above).

## New fact 2 — a DECISION item has no partial value off-box, and no premise to adjudicate by citation

Every prior row was a bug or premise item, and two of them retained partial value from the wrong
venue: `38de29ec5e59`'s premise was **confirmed** and its supersession **refuted** by citation to
`OUT-docclf.md`, a dated read of the right trunk that happens to live in this repo. That is not
available here, and the reason generalises past this item.

This item's deliverable is a **judgment about whether to delete code** — its own title is *"decide
`@rocicorp/undo`'s fate"*. There is no premise separable from the verdict: the fork it states (delete
and foreclose the Cmd+Z undo-stack path, vs keep and leave a test suite asserting a library that is
not live) is not a fact to check but a value call over trade-offs, and both arms are only weighable
against code this session cannot read. A misrouted bug item wastes a session; a misrouted decision
item is a **total** loss, because the one thing it exists to produce is precisely the thing a VM that
cannot see the subject must not manufacture.

Nor is it adjudicable by citation, and that was checked rather than assumed:

| probe over this checkout | hits |
|---|---|
| `grep -rn 20caf9661ea4` | 0 |
| `grep -rni 'rocicorp\|create-undo-context\|undo-helpers\|UNDO_LIST_ACTIONS'` | 0 |

`docs/plans/backlog-consolidation-2026-08-09/OUT-reso.md` is the analogue of `OUT-docclf.md` and it
does **not** carry this row: it was measured 2026-08-09 against `reso-management-app` `origin/main`
@ `55c0c2294`, while the item's own re-verification is dated 2026-08-17. It predates the item.

Two rows in that triage are *adjacent reasoning* for whoever adjudicates on the Mac, and are offered
as reading, **not** as a verdict:

- `b235198a915f` (KEEP) — *"both halves still on trunk … The delete-vs-keep decision is unmade"*, on
  a preview route plus its visual spec and snapshot. Structurally the same shape as this item: an
  unmounted artifact plus the test that is its only consumer, with the fate call open. Two rows, one
  decision principle — worth ruling on together rather than twice.
- `14e142267a7a` (PRUNE) — *"it exists only as PROOF for `610586f8aeb7`, which is dead … A proof of a
  retired defect retires with it."* The nearest established principle in reso's own ledger to this
  item's "its test suite gives false assurance that an undo library is live". It is a principle about
  a *retired* defect, and whether the Cmd+Z path is retired or merely unbuilt is exactly the open
  question — so it informs the ruling and does not settle it.

## New fact 3 — the prescribed rail is the silent one, and the silence has two causes now

The brief's blocked-path instruction is `cc-backlog block 20caf9661ea4 --needs "…"`. Measured here:

```
$ cc-backlog block 20caf9661ea4 --needs "…"
cc-backlog block: unknown id 20caf9661ea4                                   # rc 0
$ cc-backlog done  20caf9661ea4 --evidence "…"
cc-backlog done: unknown id 20caf9661ea4                                    # rc 0
```

`~/.claude/autonomy/` is absent, so **the exact command the brief hands a blocked worker exits 0
while doing nothing.** The record above has `reopen` at rc 0 in one session and rc 3 in another; add
`block` and `done` at rc 0. A worker that checks exit codes reports the item parked when it is not.

`cc-notify` is still rc 0 and still inert, but for a **different reason** than the two occurrences
above recorded:

```
$ cc-notify --role desk "…"
cc-notify: fallback=phone-unwired — push-send is INERT (PUSHOVER_TOKEN/PUSHOVER_USER unset).
This is push-send's exit 3, NOT a role failure                              # rc 0
```

08-17 saw `reason=role-unset`; this is `fallback=phone-unwired`. Two independent causes, same rc 0,
same zero delivery — so the silence is **structural to running off-box, not one misconfiguration
waiting to be fixed.** This branch remains the only durable channel to the desk.

## Measured from inside this session

| what | value |
|---|---|
| clone | `git rev-list --count HEAD` → **50**, `.git/shallow` present |
| `HEAD` vs `origin/main` | **0 behind** — fresh fetch succeeded; this VM *is* at `claude-infrastructure` trunk |
| `/Users`, `/root/Development`, `/home/user/Development`, `~/.claude/autonomy` | all absent |
| any `reso-management-app` checkout | `find / -maxdepth 5 -name reso-management-app` → 0 hits |
| `~/.claude/projects/` | one entry, this session's own `-home-user-claude-infrastructure` |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| `bats` / `shellcheck` | **both ABSENT** (`jq`, `python3` present) |

`cc-eligible check` on a fixture of this item's full text — **the sixth consecutive `eligible`**, and
still correct on its own terms: the work names no local-only state, cites no sha, needs no browser,
no pane, no `launchd`.

```
verdict=eligible
  refused : (nothing fired)
  history : no-repo — NOT CERTIFIED: no readable git repo for this project — reach is unknown
            repo=/root/Development/reso-management-app ref=- depth=50
```

🚨 **That `no-repo` is an artifact of measuring from the VM and proves nothing about the fire.** On
the Mac `repo_for("reso-management-app")` resolves to a tree that exists, so the certification taken
at label time is not the one printed here. It is recorded to forestall the tempting misreading —
*"the producer would have abstained"* — which this session cannot support either way. The gap remains
the pair (`item.project`, `session.attached_repo`), unchanged.

## Operator actions

The 08-16 decision — **(a) fail closed at the fire vs (b) route by `item.project`** — is unchanged,
is the one that stops the whole class, and now carries the datapoint that it has cost a session on
every one of the last four days it went unmade. Nothing new is proposed.

The ledger disposition for this item needs the Mac:

```
cc-backlog block 21e2c1088736 --needs "re-dispatch to a session that can reach reso-management-app — a local claim, or a cloud fire whose attached git_repository source IS reso-management-app; then note it is DECISION-class and terminates at an operator policy fork (A hide/disable Undo for door_staff vs B widen permissions), so consider cc-decide rather than a dispatch slot; premise NOT adjudicated (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § SEVENTH OCCURRENCE)"
```

`block`, not `reopen` and not `done`: the item is blocked on **where it was sent**, and parking it
out of the wave is what stops an eighth fire into the same VM shape before the guard exists.

## Not fixed here, deliberately

The three standing refusals were re-measured this session and all still hold: `bats` and `shellcheck`
are **absent** (confirmed, not assumed), so the repo's gate cannot be run on a shell change to the
paid-fire path; `bin/cc-eligible`'s `OFFBOX_LANE` class states that a session this lane created
cannot verify a change to the lane, and lists `venue` precisely so an item asking to edit that file
is refused; and this clone is shallow at 50 commits, which `bin/cc-venue`'s own guard says disqualifies
it from minting venue rules.

## The item itself — NOT adjudicated

No claim is made about `door_staff`, `isManagerOrAbove`, or the eleven floor-plan undos. The cited
files were never readable from this session, and the item's opening question — whether `door_staff`
can perform the forward action at all, which would make the whole item theoretical — **remains
open**. It is the first thing the next worker should answer.
`repo_for(project)` (`bin/cc-eligible:613-626`) lands exactly on the absent tree and the oracle says
so. The verdict is still `eligible` because **`no-repo` is classed as an instrument outage**, and the
file's founding rule fails open on those: *"a claim must never be starved by an instrument outage"*
(`:86`). That classification is right on the Mac, where `no-repo` means *I could not measure reach*.
It is wrong off-box, where `no-repo` for a foreign project is not an outage at all — **it is the
answer.** One token is standing for two states:

| state | on the box | in a VM |
|---|---|---|
| `no-repo` | cannot measure reach → fail open, correctly | the project has no tree here → the work cannot run, at all |

So the missing thing is neither a new measurement nor a denylist spelling — it is a **discriminator
between two states that currently share one token**, evaluated against the venue being asked for.
The header's own asymmetry already decides which way it resolves once separated: *"a wrong ELIGIBLE
puts a worker in a VM that CANNOT do the work at all and cannot tell you so… Stranding is
recoverable; a confident worker on invisible state is not"* (`:44-50`).

🚨 **This does not reopen the "was it a spelling all along?" question — that stays closed with a no**,
and it does not displace the 08-16 §3 decision: `cc-offload` gates the *fire* and the fire is what
spends the slot, so a `cc-eligible` conjunct remains the weaker placement (§"The cause is settled"
above). It is recorded because it changes the shape of the weaker fix from *add an arm* to *split an
existing verdict*, which is cheaper and does not widen a denylist.

## Not fixed here — the same three refusals, re-measured

Unchanged and not re-argued: `bin/cc-eligible`'s `OFFBOX_LANE` rule (a session this lane created
cannot verify a change to the lane); a clone grafted at 50 commits cannot adjudicate its own
admission (`.git/shallow` present, `git rev-list --count HEAD` → **50**); and the repo's gate cannot
be run on a change to the fire path — `bats` **ABSENT**, `shellcheck` **ABSENT** (`jq` and `python3`
present). Landing an ungated guard into the path that fires paid cloud sessions trades a bounded
waste for an unbounded one.

## The rails, re-measured — `block` and `done` are silent here too

The §"rails fail quietly" blocks above record `cc-backlog reopen` at rc 0 in one session and rc 3 in
another. On this VM the two verbs a blocked worker is actually told to use are both **rc 0**:

```
$ cc-backlog done  38de29ec5e59 --evidence "…"
cc-backlog done: unknown id 38de29ec5e59                              # rc 0
$ cc-backlog block 38de29ec5e59 --needs "…"
cc-backlog block: unknown id 38de29ec5e59                             # rc 0
$ cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 reason=role-unset          # rc 0
```

`~/.claude/autonomy/backlog.jsonl` does not exist here, and the store is untracked and unsynced
(`git ls-files | grep backlog.jsonl` → no match), so nothing written from this venue could reach the
desk regardless of exit code. **The ledger was NOT updated by this session and must not be reported
as such.** This branch is the notification.

## Operator actions

Nothing new is proposed. The 08-16 §3 decision — **(a) fail closed at the fire vs (b) route by
`item.project`** — is the one that stops the class; §1 of "The fifth" still holds that (b) alone does
not reach a `~/.claude`-store subject.

The ledger disposition for this item is **unchanged from the § FIFTH OCCURRENCE block above** and
needs the Mac. `block`, not `reopen` and not `done`: the item is blocked on *where it was sent*, its
premise is confirmed and its supersession refuted, and parking it out of the wave is what stops a
**fourth** fire into the same VM shape before the guard exists.

## The item itself — NOT adjudicated, for the third time

No claim is made here about `_stage_uv`, `--require-hashes`, `verify-package.sh` or `bootstrap.sh`
beyond what `OUT-docclf.md` verified on 2026-08-09 and §"New fact 2" above already cites. The file
was never readable from this session. Its DoD and falsifier are already written
(`OUT-docclf.md:154-164`, cluster **M-P-2**, which orders this item against four others in the same
surface set — read the grouping before opening a diff). The falsifier is one command and it is
unrunnable here for the strongest possible reason: there is no `doc_classifier` tree, stale or
otherwise.
# THIRD BURN of `38de29ec5e59` — 2026-08-19, the first one fired *after* its own disproof was on trunk

*Appended from inside that VM. The class, its cause, this item's premise and its supersession are all
settled above and none is re-derived. **One** fact here is new, and it is about the remedy, not the item.*

**2026-08-19.** The same item, the same project, the same one attached repository
(`renchris/claude-infrastructure`), the same brief — `/Users/chrisren/Development/doc_classifier`,
DoD ref `pipeline/backbone/port/build.py#L125`. Third actuator-burn on one row (08-11 `handoff-fire`
cloud leg, 08-17 `--venue cloud`, 08-19 `--venue cloud`), still **zero turns of work on its subject**.

## The new fact: writing the disproof to trunk did not stop the re-fire

The 08-17 section chose its channel deliberately — *"a cloud VM's only durable channel to the desk is
the branch it pushes; this file is the notification"* — and paired it with an operator action, a
manual `cc-backlog block` run on the Mac. Two days later that section is **on `origin/main` and this
VM read it**, and the item fired anyway. So this occurrence measures the remedy of record end-to-end:

| what the 08-17 section did | what it bought |
|---|---|
| wrote the confirmed premise + refuted supersession to trunk | this session skipped straight to disposition — real, and the reason nothing above is re-derived |
| recommended `cc-backlog block 38de29ec5e59 --needs …` (operator, on the Mac) | **not run** — the row was still dispatch-eligible on 08-19 |

That is the same self-refuting shape the 08-15 disproof hit (§ the UNDERCOUNTED note above:
*"nothing in the dispatch chain reads plan prose"*), now observed on the file that recorded it. The
disproof is durable for a **reader**; it is inert for the **dispatcher**. A remedy whose stop-arm is
a human command has a latency, and this row prices it at **≥2 days and one additional burn**.

🚨 **This bears on the open (a)/(b) decision** and is the only thing here that should move it. Both
options in `cloud-venue-project-repo-mismatch-2026-08-16.md` §3 sit at the fire; the *interim*
protection everyone has relied on instead — park the row by hand — is the arm just measured failing.
It argues for **(a) fail closed at the fire**, which needs no human in the loop per row, over any
disposition that keeps depending on the park being run. Nothing else about §3 is reopened.

## Re-measured from inside this session

Recorded because a two-day-old measurement of a *fire path* is a claim, not a fact:

| what | value | vs 08-17 |
|---|---|---|
| `HEAD..origin/main` | **0** — this VM *is* at `claude-infrastructure` trunk | same |
| clone | 50 commits, `.git/shallow` present | same |
| `bin/cc-offload:84` on trunk | `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` | **byte-identical — no guard has shipped** |
| `git log --since=2026-08-17 origin/main -- bin/cc-offload cc-eligible cc-venue cc-dispatch` | one commit, `e1b0bb80` (link-parity/skills-wall) | unrelated to the venue pair |
| `scripts/dispatch-projects.conf` | still lists `doc_classifier repo=~/Development/doc_classifier` | same — **a fourth fire is not prevented** |
| `/Users`, `~/Development`, any `doc_classifier` checkout, `backbone/port/build.py` | absent (`find /` → 0 hits) | same |
| GitHub scope | `renchris/claude-infrastructure`, one repository | same |
| `bats` / `shellcheck` | **both ABSENT** (`jq`, `python3` present) | same — the shell gate still cannot run here |

## Rails — reproduced a third time, with exit codes

```
$ cc-backlog done 38de29ec5e59 --evidence "…"
cc-backlog done: unknown id 38de29ec5e59                                    # rc 0
$ cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 reason=role-unset                # rc 0
```

`~/.claude/autonomy/` does not exist here, so both **exit 0 while doing nothing**. **The ledger was
NOT updated by this session and must not be reported as such** — the operator command below is still
outstanding, and its being outstanding is this section's subject.

## Operator action — unchanged, and now the thing being measured

```
cc-backlog block 38de29ec5e59 --needs "re-dispatch to a session that can reach renchris/doc_classifier — a local claim, or a cloud fire whose attached git_repository source IS doc_classifier; premise CONFIRMED and supersession by 71258c80fce2 REFUTED (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § FIFTH OCCURRENCE); THIRD session burned on this item"
```

Still `block`, not `reopen`, and not `done`: nothing about `build.py` changed, and marking it done
would be false. The fix itself remains specified and unstarted at `OUT-docclf.md:154-164` (cluster
**M-P-2**, item 4 of 5 — read the grouping before opening a diff; two of the five conflict if done
separately), with the falsifier a worker in the right venue runs:

```
git show origin/main:pipeline/backbone/port/build.py | sed -n '116,140p' | grep -q -- --require-hashes
```

## Not fixed here — same three refusals, one of them now sharper

`bats` and `shellcheck` are absent, so a shell change to the fire path cannot be gated; `bin/cc-eligible`'s
`OFFBOX_LANE` holds that a session this lane created cannot verify a change to the lane; a shallow
50-commit clone cannot adjudicate its own admission. Sharper this time: (a) and (b) are an **open
operator decision**, so a VM implementing either would not be fixing a specified bug, it would be
choosing for the operator — inside the very fire path that dispatched it, ungated. The escalation
above is offered *to* that decision, not as a substitute for it.

**No claim is made about `build.py`.** It was not readable from this session either.
# SIXTH OCCURRENCE — `38de29ec5e59` a THIRD time, and the doc a stranded VM writes is a FALSE-DONE GENERATOR

*2026-08-20, written from inside the third VM burned on this one item. The class, its cause and this
item's adjudication are settled above and are NOT re-derived — §§ FIFTH OCCURRENCE and
`cloud-venue-project-repo-mismatch-2026-08-16.md` §§2–3 stand verbatim. Three things here are new, and
the second one is the reason this section exists.*

Re-measured this session, all unchanged: no `doc_classifier` checkout anywhere
(`find / -maxdepth 4 -name doc_classifier` → 0); GitHub scope is the one repo `renchris/claude-infrastructure`;
`git show origin/main:bin/cc-offload` line 84 is still `REPO="${CC_OFFLOAD_REPO:-$ROOT}"`, so **no guard has
shipped**; `HEAD..origin/main` = 0 with `.git/shallow` present at 50 commits; and the disposition rails still
exit 0 while doing nothing (`cc-notify --role desk` → `verdict=unresolvable enqueued=0 reason=role-unset`,
`~/.claude/autonomy/` absent). **This session did not update the ledger and must not be reported as having
done so.**

## New fact 1 — the prescribed `block` is not on the row, and the dispatcher proves it

§ FIFTH OCCURRENCE closed by prescribing `cc-backlog block 38de29ec5e59`, on the reasoning that parking it
*"is what stops a sixth fire into the same VM shape before the guard exists."* The sixth fire happened
anyway, three days later, into the same VM shape.

That is not merely suggestive — the dispatcher settles it. `bin/cc-dispatch` filters to `status=="open"` at
step 1 and its own suite pins the behaviour: case **(k)**, *"blocked item → NOT dispatched (passed)"* +
*"blocked item → ZERO spawn (no loop)"* (`bin/cc-dispatch:2497-2503`). A row that reaches a fire was
therefore `open` when the pass read it. So the prescription was either never applied or was folded away
again — and either way the finding generalises past this item: **a cloud VM's remedy for a venue mismatch
is a sentence in a file, and the mechanism that re-burns the item reads the store.** Prose cannot park a row.
The period of this loop is ~3 days and its cost is one paid session per turn.

## New fact 2 — the ONLY artifact a stranded VM can produce is what marks its item DONE

`scripts/cloud-return.sh` step 8 (`:395-423`) marks the fired item done, unattended, on the laptop:

```sh
if [ "$landed_ok" -eq 0 ] && [ -n "$BACKLOG_BIN" ]; then
  "$BACKLOG_BIN" "done" "$item" --evidence "cloud $id → $trunk: $paths"
```

Every input to that condition is subject-blind, and the chain closes on itself:

- **`item` is populated on dispatcher fires.** `bin/cc-dispatch:2307` fires `up --via api --task … --item "$id"`
  and `bin/cc-offload:550` writes it onto the declaration. This session's declaration therefore carries
  `item_id=38de29ec5e59`.
- **`paths` is the VM's own diff.** `cc-cloud fill-paths` derives it from the branch's commits against the
  merge-base — it asks what this session wrote, never what the item was about.
- **`landed_ok` checks those same paths against the FIRING repo's trunk** (`git -C "$repo" ls-tree "$trunk" -- "$p"`).
- **Nothing compares the item's project to the repo.** `grep -n project scripts/cloud-return.sh` → **zero hits**.

So on a venue-mismatched fire the only durable act available to the VM — pushing a research doc into
`claude-infrastructure`, which is exactly what this file is and what §§ above instruct — is *precisely* the
act that makes its item content-verify and closes it, with evidence reading
`cloud <session> → main: docs/research/….md`. **The honest artifact and the false completion are the same
push.** `build.py` is never touched, and the item that named a real, twice-confirmed supply-chain hole on a
foreign repo folds to `done`.

This inverts the cost model §3 of the 08-16 doc was decided against. An unfixed venue was priced at *one
burned session per fire*, a bounded waste. It is actually *one burned session **plus** the silent completion
of the item that was burned* — and the completion is the sticky half: `cmd_transition`'s terminal guard
(`bin/cc-backlog:1600-1615`) refuses `reopen` and `unblock` over a `done` row with rc 4, so recovery needs
`--force`. The local lane does not have this defect for the same reason it does not have the venue one:
`cc-dispatch` already resolves the repo **from the item's own project** (`project_repo()` /
`scripts/dispatch-projects.conf`, `:1187-1192`). Only the cloud lane attaches the firer's repo — and only
the cloud lane's return path then reads that repo's trunk as proof about the item.

**One command survives every ordering.** `block` takes neither the terminal guard (reopen/unblock only) nor
the done latch (claim only), and status is a last-transition-wins fold — so `cc-backlog block <id> --needs …`
lands over `open`, `blocked` and `done` alike. It is therefore correct whether the operator runs it before
the sweep, after it, or after a `done` has already been folded in. Nothing else about this item needs
sequencing.

## New fact 3 — the standing refusal's TOOLING leg is refuted; its real leg is untouched

Three sessions declined to ship a guard citing, in part, that *"neither `bats` nor `shellcheck` is installed
here, so the repo's gate cannot be run on a shell change."* Measured this session, that leg is **false**:

| step | result |
|---|---|
| `npm i -g bats@1.11.0` | OK — Bats 1.11.0 |
| `pip install shellcheck-py` | OK — ShellCheck 0.11.0 |
| `bats tests/cloud-return.bats` (untouched tree) | 6/24 failing |
| root cause of the 6 | no git identity in the container — the fixture overrides `HOME`, so the stub lander commits as `root@vm.(none)` |
| after `git config --system user.email/user.name` | **24/24 green** |

A future cloud VM should not repeat that refusal in that form: the gate for this lane's scripts **is
obtainable here**, and the six red tests are a container-provisioning gap, not a repo signal.

**The conclusion is unchanged, on the leg that actually carries it.** `bin/cc-eligible`'s `OFFBOX_LANE`
class states the rule that forbids the fix, and it is not about difficulty or tooling:

> A SESSION THIS LANE CREATED CANNOT VERIFY A CHANGE TO THE LANE. … It is not a statement about difficulty;
> it is that the observer and the subject are the same object. (`bin/cc-eligible:212-231`)

`scripts/cloud-return.sh` **is** that lane — W2 of `CLOUD_BACKLOG_PIPELINE.md`, the one thing on it that acts
unattended, as its own suite header says. A green hermetic suite whose lander, `cc-backlog` and `cc-custody`
are all stubs proves the argv, not the return; the failure mode of a wrong guard here is that nothing lands
or nothing closes, and both are invisible from inside the session the lane produced. So the fix is **filed,
not landed** — the same disposition, now resting on the leg that a tooling change cannot move.

## Operator actions

Both need the Mac. The first is unchanged from § FIFTH OCCURRENCE except that it is now also the recovery
for a false-done, and is correct in any order relative to the sweep:

```
cc-backlog block 38de29ec5e59 --needs "re-dispatch to a session that can reach renchris/doc_classifier — a local claim, or a cloud fire whose attached git_repository source IS doc_classifier; premise CONFIRMED on origin/main and supersession by 71258c80fce2 REFUTED (docs/research/venue-foreign-repo-recurrence-2026-08-17.md §§ FIFTH+SIXTH OCCURRENCE); THIRD cloud session burned on this item; if cloud-return already folded it to done over this doc's land, that done is FALSE — build.py was never touched"
```

```
cc-backlog add --project claude-infrastructure --title "cloud-return marks a fired item done from the FIRING repo's trunk with no check that the item's project is that repo — a venue-mismatched VM's only durable artifact (a research doc) content-verifies and silently completes the item it could not work on (measured: 38de29ec5e59)" --dod-ref "scripts/cloud-return.sh#L395" --source 38de29ec5e59
```

The §3 fork of the 08-16 doc — **(a) fail closed at the fire vs (b) route by `item.project`** — is still the
operator's, still unshipped, and now carries a sixth datapoint plus a second failure face. Nothing new is
proposed about it here; note only that face 2 outlives either choice, because a same-repo item whose work a
VM cannot finish reaches the identical `done` on any doc it pushes.
cc-backlog block 20caf9661ea4 --needs "re-dispatch to a session that can reach reso-management-app — a local claim, or a cloud fire whose attached git_repository source IS reso-management-app. This is a DECISION item: its deliverable is the delete-vs-keep ruling itself, so it has no partial value off-box and was NOT adjudicated (docs/research/venue-foreign-repo-recurrence-2026-08-17.md § SIXTH ITEM). When it is ruled on, consider it together with b235198a915f — same shape (unmounted artifact + its only-consumer test, fate unmade) — and read 14e142267a7a's 'a proof of a retired defect retires with it' as adjacent, not dispositive."
```

`block`, not `reopen` and not `done`: the item is not blocked on information or on a judgment call
that this session could have made — it is blocked on **where it was sent**, and parking it out of the
wave is what stops a seventh fire into the same VM shape before the guard exists. `done` would be
false; nothing about `@rocicorp/undo` changed.

And one step this record needs that the earlier ones did not state: **this file reached you on a
branch, not on trunk, and merging it is yours.** Per § The second refinement, the land gate is RED on
this VM for any diff — `unattended-path-lint --selftest` cannot discriminate on Linux — so the commit
is pushed to `claude/fire-20260820T065955Z-38594-1` and could not be landed from here. Gate it on the
Mac (where that arm can certify itself) and land it via the project-local `/ship`.

## Not fixed here, deliberately

The three refusals recorded by the 08-16 and 08-17 sessions hold verbatim and are re-confirmed by
measurement, not by memory: `bin/cc-offload` fires paid cloud sessions and **neither `bats` nor
`shellcheck` is installed here**, so the repo's gate cannot be run on a shell change;
`bin/cc-eligible`'s `OFFBOX_LANE` class states that a session this lane created cannot verify a
change to the lane — the observer and the subject are the same object; and `bin/cc-venue`'s header
states that a shallow clone may not decide its own admission, which `.git/shallow` + `depth=50` makes
true of this session by measurement. Landing an ungated guard into the fire path would trade a
bounded waste for an unbounded one.

**Two refinements, both measured here rather than inherited.** The first sharpens the shellcheck
clause and strengthens it: a missing `shellcheck` does **not** make the gate refuse to run: it
produces a **NON-VERDICT** on that arm, by deliberate design — `scripts/ship-land.sh:2308` guards it
because *"a MISSING checker is not a claim about this tree … unguarded it exits 127 and the else-arm
files `gate_red`, so a box without the binary is told its code is RED … identically whether the code
is spotless or filthy."* So the accurate statement is not *"the gate cannot run"* but *"the arm that
would judge a shell change abstains here"* — landing a `cc-offload` guard from this VM would be
landing it **ungated**, which is the same refusal on firmer ground.

## The second refinement changes what the operator has to do: THIS VM CANNOT `/ship` AT ALL

Newly measured, and not recorded by any occurrence above. The land gate is **structurally RED on
this host for any diff whatsoever**, including a pure-markdown one:

```
$ bash scripts/ship-land.sh --precheck            # diff = this file, 170 insertions, 0 deletions
✗ gate: unattended-path-lint --selftest FAILED — the detector no longer discriminates, so
  its clean verdict would mean nothing. Fix the lint before landing.
✗ ship-land: GATE RED at precheck — not pushing.          # PRECHECK_RC=6
```

Every other arm ran and came back clean (test-hermeticity 517 suites, wall-clock, AF_UNIX,
moving-ref, git-identity 784 files, utc-stamp, pipefail/SIGPIPE, self-path, pane-spawn coverage).
The one red arm is **not attributable to this diff**, and that was tested rather than assumed:
restoring the worktree to `origin/main` content and re-running the selftest fails **identically** —
`FAILED (9 of 30)`.

The cause is that `scripts/unattended-path-lint.sh` is **macOS-shaped by subject**: it reasons about
`/sbin/md5` (*"md5 on macOS exists ONLY at /sbin/md5"*, `:66`), a Homebrew PATH that *"ADDS Homebrew
and DROPS /usr/sbin and /sbin"* (`:60`), `/usr/sbin/sysctl`, and `launchctl` reloads. `uname -s` here
is **Linux**, so its fixtures cannot discriminate and the detector correctly refuses to certify
itself. That refusal is right — a lint whose selftest fails must not emit a clean verdict — and it
means a cloud VM's commits can be **committed and pushed to a branch, never landed from the VM**.

Consequence for this class, and it is a cost the five rows above do not name: a misrouted cloud
session cannot even land its own incident report. **The branch is the whole deliverable, and merging
it is an operator step.** That is presumably how the 08-14 → 08-17 records reached `origin/main`,
where this session read them.

🚨 **Not fixed here, for the same reason as everything else in this section.** Making the lint
portable is a change to a shell file, on a host where the arm that would judge it abstains
(`shellcheck` absent) and where `bats` cannot run its 30-case suite — i.e. precisely an ungated
change to a gate. The correct fix is a platform guard (skip-with-a-named-non-verdict on non-Darwin,
never a silent pass), and it belongs to a session that can gate it.

## The item itself — NOT adjudicated

No claim is made about `@rocicorp/undo`'s fate, and none should be inferred. The package, the two
`lib/` modules, the test file, the shipped `restoreTodo` toast the brief contrasts them with, and the
audit at `docs/research/UNDO_LIST_ACTIONS_AUDIT_2026-08-16.md` were **never readable from this
session** — there is no `reso-management-app` tree here, and the checkout that is here mentions none
of them. The brief's own mandated first step — *read what this item cites on TRUNK, never in your own
tree* — is unrunnable for the strongest available reason: there is no tree, stale or otherwise.

The item states its own fork sharply and correctly, and that is exactly what makes ruling on it from
here indefensible: both arms turn on facts about live reso code — whether the Cmd+Z undo-stack path
is still wanted, and what the test suite actually asserts. Answering from the brief's prose would be
the anti-goal `bin/cc-venue` §5 names — *"a wrongly-routed item improvises a plausible answer against
history it cannot read, and reports success."*

---

# EIGHTH OCCURRENCE — the label is RIGHT, and that is the finding (2026-09-03)

**Backlog `9ce3c6350e2f`**, project **`claude-infrastructure`** — the attached repo, correctly
labelled — dispatched `--venue cloud`. Title:

> reso docs still gate the frontier tier on the deleted claude-next eval track
> (`project-pass.md`, `CONTEXT_EXHAUSTION_GUARDRAILS.md`)

Two weeks after the 08-20 row, the longest quiet gap this table records. The class did not stop; it
produced its **first row whose `project` label is not a mislabel at all**, which is a different
finding from the seven above and is the only reason this section exists.

## Where the two cited names live — the brief's own open question, answered from trunk

The dispatch brief flagged both names as unresolvable: *"CITED NAME(S) with no directory component
and no carrier on origin/main … they may live OUTSIDE this repo … resolve the location before
reading this as evidence either way."* Trunk answers it in one grep:

```
$ git grep -n 'project-pass\|CONTEXT_EXHAUSTION' origin/main
origin/main:skills/model-upgrade/SKILL.md:75:   - project `.claude/commands/project-pass.md`, `docs/research/CONTEXT_EXHAUSTION_GUARDRAILS.md`
origin/main:templates/model-classification.json:28:    "Development/reso-management-app/.claude/commands/project-pass.md",
origin/main:templates/model-classification.json:29:    "Development/reso-management-app/docs/research/CONTEXT_EXHAUSTION_GUARDRAILS.md"
```

Both are **`reso-management-app`** files. Neither has ever existed in this repo — not at HEAD, not on
any ref, not under any directory:

```
$ git log --all --pretty=format: --name-only | sort -u | grep -icE 'project-pass|CONTEXT_EXHAUSTION'
0
```

So the row is unworkable here for the ordinary reason, confirmed against the API rather than assumed:

```
$ mcp__github__get_file_contents renchris/reso-management-app .claude/commands/project-pass.md
Access denied: repository "renchris/reso-management-app" is not configured for this session.
Allowed repositories: renchris/claude-infrastructure.
```

`add_repo` is **not present** in this session's tool surface, so the escape hatch that error names is
also closed. `/Users` and `~/Development` are absent; `/home/user` contains exactly one entry,
`claude-infrastructure`.

## NEW FACT 1 — this row defeats remedy option (b), and it is the first that does so on the merits

Every row above is *label-foreign* (`project` names a repo the session cannot reach) or, once, the
08-15 *subject-foreign* row where the label passed and the text was about `doc_classifier`. Option
**(b) route by `item.project`** fixes the first kind by construction and was arguably a clerical fix
for the second.

**It cannot fix this one, and not because the label is wrong — because the label is right.**
`claude-infrastructure` genuinely owns this item. This repo carries the register that names those two
reso files: `skills/model-upgrade/SKILL.md:75` lists them in the model-upgrade skill's *canonical
reference list* (the walk a future tier insertion is required to make), and
`templates/model-classification.json:28-29` classifies them `review` — *"current routing guidance
interleaved with historical citations … NEVER auto-rewritten"*. The row is a claude-infrastructure
register whose **targets** are extraterritorial. Route-by-project would dispatch it to
`claude-infrastructure` — where it already is — and it would be unworkable on arrival again.

Option **(a) fail closed at fire time** does refuse it, if the predicate is over *the pair* (what the
brief cites, what the session can reach) rather than over the `project` field. That is the
distinction the 08-16 doc's §3 draws between gating the *claim* and gating the *fire*, and this row
is the first evidence that the two options are not merely differently-placed — for a subject-foreign
row with a defensible label, **(b) is not a weaker (a); it is a non-remedy.** The open decision filed
2026-08-16 now carries that as a discriminator rather than only a cost count.

## NEW FACT 2 — half the premise is not foreign, it is UNTRACKED-LOCAL, and nothing sees that either

The title asserts two things. The first — *reso docs still gate the frontier tier* — is foreign, as
above. The second — *the **deleted** claude-next eval track* — is **unverifiable from any venue that
is not the operator's box**, and this is not a venue-scope problem:

- The deletion is performed by `docs/activation/pending-activation/29-launcher-consolidation-activate.sh`,
  which edits **`~/.zshrc`** (*"DELETE `claude-next{,2,3,4}` · `claude-opus5{,-2,-3,-4}` · `cc-next{,2,3,4}`"*, `:19`).
  `~/.zshrc` is on no ref.
- Whether it has run is recorded by a `.done` marker beside the script. **Zero `.done` markers are
  tracked**, across all 52 activation scripts (`git ls-tree -r origin/main -- docs/activation/ | grep -c '\.done$'` → `0`),
  and `.gitignore` says nothing about them. The marker is desk-local by construction.
- `LAUNCHER_SPEC.md`, which that script names as *"the binding target state … in claude-infrastructure"*,
  is **not on trunk** either.

So a cloud worker cannot establish the antecedent the whole item rests on. Worse for the guard: the
spelling that would betray it reads clean. Driving `cc-eligible`'s pure classifier directly — `check`
itself cannot run here, it needs the ledger and answers `verdict=unknown-store … fail-open`:

| text passed to `classify_all` | classes | verdict |
|---|---|---|
| the item's full title | `[]` | `eligible` — *"repo-only work — no local-only state named"* |
| `project-pass.md` | `[]` | `eligible` |
| `CONTEXT_EXHAUSTION_GUARDRAILS.md` | `[]` | `eligible` |
| `reso-management-app` | `[]` | `eligible` |
| `/Users/chrisren/Development/reso-management-app/.claude/commands/project-pass.md` | `[]` | `eligible` |
| **`~/.zshrc claude-next launcher`** | `[]` | **`eligible`** |

The last row is the one worth keeping. `~/.zshrc` is *precisely* the class `cc-eligible`'s own header
enumerates — *"A cloud VM has no `~/.claude`, no local browser, no dev server, no pane registry, no
keychain"* — and the predicate does not recognise it. This is a **measurement, not a proposed arm**,
for the reason that file's header (`:25-37`) states and the 08-17 session already re-stated: adding
`~/.zshrc` to the list would widen a denylist by one spelling, at the claim rather than at the fire,
against a class the list cannot enumerate.

## Measured from inside this session

| what | value |
|---|---|
| clone | arrived **shallow**; `git fetch --unshallow` → `is-shallow-repository` **false**, `rev-list --count HEAD` **4010** |
| `HEAD..origin/main` | **0** — this tree *is* trunk (`a8b181f2`); every read below is a trunk read |
| dispatcher vintage | `git rev-parse origin/main:bin/cc-dispatch` → `646b8a652e71…` — **EQUAL** to the blob named in the brief. The dispatcher that fired this session **is** trunk; no landed-not-live gap to discount |
| `/Users`, `~/Development` | both absent |
| GitHub scope | `renchris/claude-infrastructure`, one repository; `add_repo` absent |
| the two cited files | 0 hits over the checkout, 0 over all refs, 0 in all history |
| cure already on trunk? | **no cure exists to find** — the artifacts the item would change are not in this repo, so the brief's `git log <sha>..origin/main -- <path>` check has no path to run against |

## The item itself — NOT adjudicated, and this time the refusal has a second leg

No claim is made about what `project-pass.md` or `CONTEXT_EXHAUSTION_GUARDRAILS.md` say. They were
never readable from this session.

The novelty is that **even the half that IS in this repo must not be touched here.** Trunk carries the
same gate the item complains of, in files this session can edit — `model-config.yaml:117`
(`tracks: [claude-next]`), `:104` (*"Fable exists ONLY on the claude-next eval track"*),
`commands/research.md:85`, `hooks/agent-teams-enforce.sh:517`. Editing them would be acting on the
exact proposition NEW FACT 2 shows is unverifiable from here. The Follow-On Gate's **F2
(well-researched, grounded in this session's disk-truth investigation)** fails, and it fails for a
reason that is a fact about the venue rather than about the diligence of the worker: *the evidence for
"deleted" lives in a file no ref carries.*

Recorded, not acted on, so the desk session that can read `~/.zshrc` inherits it rather than
re-deriving it — and note it is not one edit but a rename, because the gate's substance appears to
survive its spelling. There are still two tracks (`claude` at 2.1.219 and `claude-prev` at the pinned
2.1.114, per this repo's `CLAUDE.md`), and 2.1.114 still does not know `claude-fable-5`. What changed
is which name the live track answers to. Three things travel together wherever that gate is written,
in reso and here alike:

1. the track name, `claude-next` → whatever the consolidated entrypoint is called;
2. the fallback, `Opus 4.8` → `Opus 5` (`CLAUDE.md`: *"Default model = Opus 5 @ effort high"*);
3. the window — `commands/research.md:85` still reads `(window 2026-06-09 → 2026-06-23)`, which
   `model-config.yaml` itself calls the **prior** window, *"pulled early 06-12"*. Fable has been
   `permanent: true` since 2026-07-20 with `end` a far-future sentinel.

`grep -rn frontier_access` over `bin scripts hooks lib` finds **no code consumer of `.tracks`** — the
gate is prose in every instance, which is why it drifted unnoticed and why fixing it is a doc walk,
not a code change.

## Disposition

Parked, not closed: `docs/parks/9ce3c6350e2f.md`, per §15. The `needs:` line is the one step, and it
is a **venue** step rather than an operator-credential step — the first park in this class whose
blocker is *which machine*, not *which human*.
