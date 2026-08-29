# The row that BOTH filed options pass — and the first re-dispatch of an already-disproved item

**2026-08-17, ~08:52Z.** Backlog item `8f59467c92b0` — *"MASTER: product repos"*, **project
`claude-infrastructure`** — was dispatched to a `--venue cloud` session whose one attached repository
is `renchris/claude-infrastructure`. Every open wave it names (`R1`-`R4`) edits
`~/Development/reso-management-app` or `~/Development/doc_classifier`. Neither exists on this host;
neither is in this session's GitHub scope. Unworkable on arrival.

That much is the fifth occurrence of a class already located
(`cloud-venue-project-repo-mismatch-2026-08-16.md` §2) and already filed as an open decision (§3).
This file does not re-derive the cause. It records the four things this particular row measures that
the four prior ones could not, **two of which refute the remedy as currently filed.**

---

## 1 · This is a RE-dispatch — the first repeat of an item, not of a route

`8f59467c92b0` was fired at a cloud VM on **2026-08-15** and produced a full disproof: the 🚨 block
in `docs/plans/MASTER_PRODUCT_REPOS.md` Phase 0 (*"Measured on a cloud fire of `8f59467c92b0`: the VM
held exactly one checkout … so R1-R4 were unreachable, not merely hard"*) plus a status-log entry.
Two days later the same id was fired into the same VM shape, and this session re-measured the same
absent trees.

The prior four occurrences were four *distinct* items, so each could be read as the class finding a
new victim. This one is the class **failing to learn from its own recorded output**, which converts
`venue-foreign-repo-recurrence-2026-08-17.md`'s closing question from an inference into a
demonstrated cost:

> grep for foreign-repo returns three hits, all under `docs/research/`, none in `bin/` or `scripts/`:
> the conclusion never reached the enforcing store. That, not the discriminator, is the remaining
> open question.

Confirmed at the strongest possible resolution. A disproof written to a markdown file — even one
written into the item's own DoD-ref plan, which is the most on-topic location available — does not
park the item, because nothing in the dispatch chain reads plan prose. The 08-15 session did
everything right and it bought two days.

## 2 · The census is undercounted, and structurally so — six dispatches, five items

`venue-foreign-repo-recurrence-2026-08-17.md` § "The four" lists four occurrences. It is missing the
08-15 fire of this row, and the reason it is missing generalises:

| date | item | `project` | route | recorded in |
|---|---|---|---|---|
| 08-14 | `1cc794cbc6c4` | `doc_classifier` | label-foreign | `venue-foreign-project-repo-2026-08-14.md` |
| 08-15 | `9333991e4544` | `claude-infrastructure` | subject-foreign | `venue-foreign-subject-repo-2026-08-15.md` |
| 08-15 | **`8f59467c92b0`** | `claude-infrastructure` | **subject-foreign, cross-repo** | **`docs/plans/MASTER_PRODUCT_REPOS.md` only** |
| 08-16 | `c07fb00eb9b6` | `doc_classifier` | label-foreign — located the cause | `cloud-venue-project-repo-mismatch-2026-08-16.md` |
| 08-17 07:15 | `c33f3b1cb278` | `reso-management-app` | label-foreign | `venue-foreign-repo-recurrence-2026-08-17.md` |
| 08-17 08:52 | **`8f59467c92b0`** | `claude-infrastructure` | subject-foreign, cross-repo — **repeat of row 3** | this file |

**Six dispatches over five distinct items in four days.** The 08-15 master fire is absent from the
`venue-*` family because that worker wrote its disproof where its brief pointed — the plan file — and
landed it inside `b4ddaa27`, a commit whose subject is *"A7 — two land-blockers outside the gate
arms"*. Nothing links the two.

So the class's own ledger is assembled by whichever misrouted worker happens to grep for siblings,
and it sees only the occurrences that chose the same filename convention. Any count taken from the
`venue-*` docs is a floor, not a total. This matters for the decision below: it is being weighed
against a cost figure that is low by at least one.

## 3 · 🚨 Both filed options PASS this row — the remedy as filed cannot stop its own worst case

This is the load-bearing finding. The open decision (`…mismatch-2026-08-16.md` §3, endorsed by
`venue-foreign-repo-recurrence-2026-08-17.md` §"The cause is settled") offers two shapes, both keyed
on the pair (`item.project`, `session.attached_repo`):

| option | on this row | why |
|---|---|---|
| **(a) fail closed** — refuse when `--item`'s project is not the attached repo | **fires it** | `item.project` = `claude-infrastructure`; attached repo = `claude-infrastructure`. Every term satisfied. |
| **(b) route by `item.project`** — resolve the repo from the item and attach that | **fires it, at the same VM** | resolves to `~/Development/claude-infrastructure`, which is where it already went. |

Neither refuses. The row's label is not wrong — this plan genuinely lives in
`claude-infrastructure/docs/plans/`, and `scripts/find-plan.sh:70 project_name_for()` derives the
project from that path correctly. The label is *accurate and irrelevant*: the work is in two other
trees, and only the plan BODY says so.

This is precisely the **subject-foreign** route that `venue-foreign-subject-repo-2026-08-15.md`
identified on 08-15 and answered with a different discriminator — *an item whose text names a
dispatch-set project other than its own `project`*. When 08-16 relocated the guard from the claim
(`cc-eligible`) to the fire (`cc-offload`) — correctly, since the fire is what spends the slot — the
**subject-foreign arm was dropped from the framing**, not refuted. The 08-16 §3 options and the 08-17
endorsement are both purely `item.project`-keyed, and a `project`-keyed comparison cannot by
construction see a row whose project is right.

**Therefore: resolving the decision as currently written would have stopped four of these six
dispatches and neither occurrence of this one** — including the only item that has now burned two
slots. A relocation of placement silently narrowed the discriminator; that narrowing is the finding.

The 08-15 discriminator survives the relocation intact — it reads `title`/text against
`scripts/dispatch-projects.conf`, both available at fire time as readily as at claim time. It should
be restored as a conjunct of whichever of (a)/(b) is chosen, at `cc-offload`.

## 4 · A cross-repo master is a structural counterexample to option (b)

Option (b) attaches the repo named by `item.project`. This row's work spans **two** foreign trees
(`reso-management-app` for R1-R3, `doc_classifier` for R4), and a cloud session gets exactly one
repository, permanently — `cc-offload up --via api` refuses (exit 5) unless the session reads back
with exactly one `git_repository` source (`CLOUD_BACKLOG_PIPELINE.md:48-49`). There is no in-session
recovery; the worker cannot clone its way out.

So (b) is not merely insufficient here, it is **inexpressible**: no single-valued project field can
route a row whose work is in two trees. `MASTER_PRODUCT_REPOS.md`'s own 2026-08-15 status entry
states this (*"a cross-repo master targets TWO trees, so the single-value options cannot express
it"*) — but it states it in a plan file, and §1 above is the measurement of what plan prose is worth
to this chain. Recorded here so it sits where an implementer of §3 will read it.

The implication is narrow and should not be over-read: it does not choose (a) over (b). It says a
cross-repo master must resolve to **refuse/park**, never to route, under either shape — which is a
constraint on the fix, not a verdict on it.

### One cost fact the four-mechanism list gets wrong

`MASTER_PRODUCT_REPOS.md` Phase 0 lists four candidate mechanisms, among them *"a `projectName` entry
in the plan index"*. That one is **not a build** — `scripts/find-plan.sh:73` already reads
`.plans[$k].projectName` from `$CC_PLAN_INDEX_PATH` and prefers it over the path-derived basename. It
is a data entry in an existing override path, cost ~0.

It composes usefully with (a): setting `projectName` on a cross-repo master to a *foreign* project
makes the fail-closed guard refuse the row, which is the desired park. It does not fix the class —
every other subject-foreign row still has an accurate label and no index entry — but it is the
cheapest available stopgap for **this** row specifically, and it needs no shell change in the fire
path.

*(Not verified from here: whether `~/.claude/plans-index.json` currently carries an entry for this
plan. The file does not exist on this VM. The read path in `find-plan.sh` is verified on trunk.)*

---

## 5 · Measured from inside this session

| what | value |
|---|---|
| host / `$HOME` | `vm` / `/root` |
| clone | `git rev-list --count HEAD` → **50**, shallow = `true` |
| `HEAD..origin/main` | **0** — this tree IS trunk; every read below is a trunk read |
| `~/Development`, `/Users` | both absent |
| `/home/user` | `claude-infrastructure` only |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| `bin/cc-offload:84` on trunk | `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` — unchanged, cause still live |
| guard in the enforcing store | **none** — `grep -rniE 'foreign.repo\|subject.foreign' bin/ scripts/ hooks/` returns only unrelated dispatch-loop prose |

**The rails fail quietly here, exactly as 08-16/08-17 recorded** (re-measured, not inherited):

```
$ bin/cc-backlog reopen 8f59467c92b0
cc-backlog reopen: unknown id 8f59467c92b0                          # rc 0

$ bin/cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 reason=role-unset        # rc 0
```

`~/.claude/autonomy/` does not exist, so nothing written to the ledger from here would survive
teardown. Both commands are also off `PATH` entirely — invoked as the brief spells them they exit
`127`, and invoked from `bin/` they exit `0` having done nothing. A worker trusting either exit code
would report this item parked when it is not. **A cloud VM's only durable channel to the desk is the
branch it pushes, so this file is the notification.**

## 6 · Not fixed here, deliberately — refusal grounds re-measured, not inherited

- **`bats` and `shellcheck` are both ABSENT** on this host (`shfmt` too). The repo's gate cannot be
  run on a shell change, and `bin/cc-offload` fires *paid* cloud sessions: landing an ungated guard
  into the fire path would trade a bounded waste (one slot) for an unbounded one (a wrong refusal
  starves the tap).
- **`OFFBOX_LANE`** — a session this lane created cannot verify a change to the lane; the observer and
  the subject are the same object. This session is that VM.
- The decision itself turns on facts unverifiable from any VM (GitHub App installation on the second
  repo, whether `cc-offload land` works against it), and §3-§4 above *widen* it rather than settle it.

## 7 · The item itself — NOT adjudicated

No claim is made about R1-R4, and none should be inferred. `pnpm lint` on `reso-management-app`, the
four unlanded branches, the Amplify/Fly split-brain, and `doc_classifier`'s `require_role` holes were
never readable from this session — the trees do not exist here. **R1-R4 are open, correct as filed,
and unstarted**; what is refuted is the venue, and (per §3) the sufficiency of the filed remedy —
never the plan.

The brief's mandated first step — *read what this item cites on TRUNK* — was runnable for the
`claude-infrastructure` half (the plan, `cc-offload`, `find-plan.sh`, the sibling research docs: all
read at `HEAD..origin/main` = 0) and is unrunnable for the product half for the strongest possible
reason: there is no tree, stale or otherwise. Diagnosing R1-R4 from the plan's prose is the anti-goal
`bin/cc-venue` §5 names — *"a wrongly-routed item improvises a plausible answer against history it
cannot read, and reports success."*

## 8 · Operator actions

Needs the Mac; the ledger lives at `~/.claude/autonomy/backlog.jsonl`, absent here.

```
cc-backlog block 8f59467c92b0 --needs "re-dispatch only to a session HOLDING reso-management-app and doc_classifier (the local drain, per MASTER_PRODUCT_REPOS.md Phase 0) — this row is cross-repo and cannot be served by any single attached cloud repo; SECOND misroute of this id (08-15, 08-17), premise NOT adjudicated (docs/research/venue-foreign-master-redispatch-2026-08-17.md)"
```

`block`, not `reopen`: the item is blocked on **where it was sent**, not on information or a
judgment call, and parking it out of the dispatch wave is what stops a third fire into the same VM
shape. Note the 08-15 disposition evidently did not park it — verify the block took, rather than
assuming it.

The §3/§4 findings belong on the existing decision row rather than a new one (`--source
c07fb00eb9b6`, filed 2026-08-16, per that doc §4):

```
cc-backlog add --project claude-infrastructure --title "the cc-offload venue guard decision is under-specified: BOTH filed options (fail-closed, route-by-project) pass a subject-foreign row, and a cross-repo master is inexpressible for route-by-project — restore the 08-15 subject discriminator as a conjunct at the fire" --dod-ref "docs/research/venue-foreign-master-redispatch-2026-08-17.md#3" --source 8f59467c92b0
```

---

## 9 · 2026-08-29 — the remedy LANDED, and this row survived it. Third fire of the same id.

**Twelve days later `8f59467c92b0` was fired at a third cloud VM of the identical shape** (`$HOME`
`/root`, `~/Development` absent, `/home/user` holding `claude-infrastructure` alone, GitHub scope
`renchris/claude-infrastructure`, clone 50 commits with `.git/shallow` present, `HEAD..origin/main`
= 0). R1-R4 were again unreachable by construction. What makes this fire worth recording is not the
recurrence — §1 already established that — but that **the guard §3 asked for is now on trunk, is
measurably working, and does not fire on this row.**

### 9.1 · §5's "guard in the enforcing store: none" is RETRACTED

`bin/cc-eligible` now carries a measured, non-spelling arm — `CROSS_REPO = "ineligible-cross-repo"`
(`:430`), computed by `cross_repo(project)` (`:766`) and placed *before* the history arm. Its header
block (`:404-427`) records the census that justifies it: joining each cloud declaration's `item=` to
that item's `project` puts **106 of the 133 `NOT-STARTED` sessions (80%) on a repo the VM was never
given** — 92 `reso-management-app`, 14 `doc_classifier` — against **13 for `claude-infrastructure`**.
That is this class, counted at fleet scale, and it is the largest single cause of the pile.

*Attribution is horizon-limited and is deliberately not asserted.* The arm's own comment dates the
measurement **2026-08-23**. `git log -S'ineligible-cross-repo'` from this VM returns exactly one
commit, `6250ee26` (2026-08-26) — **which is the shallow boundary itself**, so its diff shows the
whole file as added and says nothing about when the arm landed. The landing commit lies outside the
50-commit horizon and cannot be certified from here; only *presence on trunk* is claimed. (This is
`DEEP_HISTORY`'s own failure mode caught in the act, one arm over.)

### 9.2 · Measured: the member rows are stopped, this row is not

Run end-to-end against the shipped predicate, fixture `$HOME` with two real git trees carrying
distinct origins, lane pinned to the attached repo — i.e. the DESK's decision, reproduced:

```
CC_ELIGIBLE_CLOUD_REPO=$FX/Development/claude-infrastructure   # what a cloud fire attaches
cc-eligible why <row>
```

| fixture row | `project` | verdict | `reach` |
|---|---|---|---|
| *"pnpm lint is RED on origin/main — 122 `import-x/extensions` errors"* (an R1 member) | `reso-management-app` | **`ineligible-cross-repo`** | `elsewhere — project 'reso-management-app' is renchris/reso-management-app; the VM is given only renchris/claude-infrastructure` |
| *"MASTER: product repos — the operator's actual products, one wave per repo"* (**this row**) | `claude-infrastructure` | **`eligible`** · `refused: (nothing fired)` | `reachable-or-unmeasured — either the lane's own repo, or nothing measurable — arm fails OPEN` |

So §3's table is no longer a projection about a *filed* option; it is a measurement against
*shipped* code. Option (a) fail-closed is what landed, keyed exactly on the pair
(`item.project`, attached repo), and every term is satisfied for this row because its label is
correct. The class's members are now refused and **only the master row still routes** — the one item
that has now burned three slots.

### 9.3 · 🚨 The 08-15 subject discriminator would ALSO miss this row — as filed

This is the new finding, and it revises §3's own recommendation. §3 closes by asking that the 08-15
discriminator — *"an item whose text names a dispatch-set project other than its own `project`"* —
be restored as a conjunct at the fire. Measured against this row, **that conjunct does not fire
either**, because the arms read `SPAN_FIELDS = ("title", "dodRef", "condition", "source")`
(`bin/cc-eligible:490`) and this row's span text is:

```
MASTER: product repos — the operator's actual products, one wave per repo docs/plans/MASTER_PRODUCT_REPOS.md
```

Tested against every name in `scripts/dispatch-projects.conf`:

| read | `reso-management-app` | `doc_classifier` |
|---|---|---|
| the item's span fields (what every arm sees) | **0 hits** | **0 hits** |
| the plan BODY at its `dodRef` | 10 hits | 9 hits |

`9333991e4544` was catchable by the 08-15 rule only because its *title* happened to open with the
word `doc_classifier`. This row's title names no project at all; the foreign trees appear **only in
the plan body**, which is precisely what `MASTER_PRODUCT_REPOS.md` Phase 0 already says the span
fields exclude (*"never the plan BODY, where every foreign tree is named"*).

**Consequence: all three filed remedies pass this row** — (a) fail-closed, (b) route-by-project, and
(c) the 08-15 subject discriminator over span text. A conjunct that would catch it must read the
**content of the `dodRef`**, not the item's fields. That is a strictly larger change than §3
proposed (an arm that opens a file rather than matching a string), and it is the honest cost of
covering this shape.

### 9.4 · The ~0-cost stopgap is now live, and it takes TWO steps, not one

§4's cost note said a `projectName` entry in `~/.claude/plans-index.json` composes with fail-closed
to park this row. That was conditional on fail-closed landing. **It has landed** (§9.1-9.2), and the
member-row line of the table above is the proof that the arm it composes with actually refuses. So
the stopgap is one data entry away — but it is *not* sufficient alone, and §4 did not say why:

`cc-backlog`'s id hashes **project + title + source**, so changing `projectName` does not retro-label
the existing row. It governs what `cc-discover` mints *next*. Parking this row therefore needs both:

1. `cc-backlog block 8f59467c92b0` — the existing id, already minted under `claude-infrastructure`.
2. the `projectName` entry — so the next mint from this plan lands under a foreign project and is
   refused by the arm measured above, instead of re-minting a fresh `claude-infrastructure` id that
   passes exactly as this one did.

Step 2 without step 1 leaves this id firing; step 1 without step 2 leaves the plan free to mint a
successor. Both are desk actions — `~/.claude/plans-index.json` does not exist on this VM
(`find-plan.sh:38`, `$HOME/.claude/plans-index.json`), and the read path that honours it
(`find-plan.sh:73`, preferring it over the path basename) is verified on trunk, unchanged.

### 9.5 · The rails still fail at rc 0 — re-measured, and the 08-17 warning is now vindicated

§8 closed with *"verify the block took, rather than assuming it."* Re-run from this session:

```
$ bin/cc-backlog block 8f59467c92b0 --needs "…"
cc-backlog block: unknown id 8f59467c92b0                           # rc 0
$ bin/cc-backlog list --all
                                                                    # empty, rc 0
```

`~/.claude/autonomy/` does not exist here, so the store is unwritable and *both* the 08-15 and 08-17
dispositions demonstrably did not take — this fire is the evidence. A worker trusting the exit code
would report the item parked three times over while it stayed in the wave.

### 9.6 · Not fixed here — refusal grounds re-measured, not inherited

- **`bin/cc-venue`'s guard applies to this session verbatim**: *"A cloud VM must never build or run
  the venue rule: it would be deciding its own admission, and its 50-commit clone cannot read the
  history that justifies the exclusions."* This is that VM on that clone (`git rev-list --count
  HEAD` → 50, `.git/shallow` present). `bin/cc-eligible` **is** the venue rule.
- **`bats`, `shellcheck` and `shfmt` are all still ABSENT** (re-measured, not carried over from §6).
  The repo's gate cannot be run on a change to the predicate, and a wrong refusal in that arm
  starves the tap for every project — an unbounded cost traded against one bounded slot.
- §9.3 *widens* the open decision rather than settling it, exactly as §3-§4 did.

### 9.7 · The item itself — still NOT adjudicated

R1-R4 remain **open, correct as filed, and unstarted**. `pnpm lint` on `reso-management-app`, the
four unlanded branches, the Amplify/Fly split-brain and `doc_classifier`'s `require_role` holes were
again never readable — the trees do not exist here. Nothing in this section refutes the plan; what
is refuted is the venue, and now also the sufficiency of the *third* filed remedy.
