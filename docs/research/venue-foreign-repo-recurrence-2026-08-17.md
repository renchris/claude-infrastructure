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
| 08-19 | `38de29ec5e59` | `doc_classifier` | label-foreign — **third cloud burn of the same item**, 2 days after the row above (§ SIXTH OCCURRENCE) |

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
