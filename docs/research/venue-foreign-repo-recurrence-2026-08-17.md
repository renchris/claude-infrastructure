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

## The four

| date | item | `project` | route |
|---|---|---|---|
| 08-14 | `1cc794cbc6c4` | `doc_classifier` | label-foreign |
| 08-15 | `9333991e4544` | `claude-infrastructure` | subject-foreign (label passes, text is about `doc_classifier`) |
| 08-16 | `c07fb00eb9b6` | `doc_classifier` | label-foreign — **located the cause** at `bin/cc-offload:84` |
| 08-17 | `c33f3b1cb278` | `reso-management-app` | label-foreign |
| 08-17 | `5ab3327ed0c8` | `reso-management-app` | label-foreign **+ store-foreign** — see § The fifth |

This one is a **repeat of the 08-14/08-16 route**, not a fifth route. The class has stopped producing
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
