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

## 9 · THIRD OCCURRENCE — 2026-08-27, and §3's prediction is now OBSERVED against shipped code

`8f59467c92b0` was fired a third time, into the same VM shape, **10 days** after §8 wrote its
disposition into this file. The interval did not shrink: 08-15 → 08-17 was 2 days, 08-17 → 08-27
was 10. The row is not converging on a fix; it is being re-served.

**This venue, measured rather than inherited.** Branch `claude/fire-20260827T231330Z-47448-1`,
HEAD `6e7a4bf1`, `is-shallow-repository` = true, `rev-list --count HEAD` = **50**,
`HEAD..origin/main` = 0 (this tree IS trunk, so nothing below is a stale-tree artifact).
`$HOME` is `/root`; `~/Development` does not exist; `ls ..` holds only `claude-infrastructure`.
**Both routes to the product trees are closed, and the second one is new evidence** — the API route
was assumed by §§1-8 and is now measured:

```
mcp__github__get_file_contents renchris/reso-management-app CLAUDE.md
→ Access denied: repository "renchris/reso-management-app" is not configured for this session.
  Allowed repositories: renchris/claude-infrastructure
```

So the trees are unreachable by disk *and* by API. There is no third route.

### What is new relative to §§1-8

**(a) The `cross_repo` arm shipped in between, and this row still passed it.** On 08-15/08-17 the
venue predicate had no repo-identity arm at all; `bin/cc-venue` and `cc-eligible`'s
`cross_repo(project)` both exist on trunk now. The arm keys on the item's **`project` field**,
resolves it through `repo_for()`, and compares normalised origins against the lane. This row's
`project` is `claude-infrastructure` — which *is* the lane — so the arm returns reachable, and it is
**right to**: `find-plan.sh:70` derived that label correctly from the plan's own path. §3 predicted
exactly this ("both §3 options pass this row") from a reading of unwritten code. It is now an
observation of code that shipped and ran. The prediction cost 10 days to confirm and nothing about
it changed.

The sibling `tenant-drift-venue-refusal-2026-08-24.md` §1 names this residual shape in general —
**filed under X, specified against Y** — and reports it on a different row (`485f8f87eb5f`). This is
that shape's **second observation**, and the first on a *cross-repo master*, which is the harder
sub-case: `485f8f87eb5f` has one foreign subject and could in principle be routed to it, while this
row's work spans **two** foreign trees and a session gets exactly one `git_repository` source
permanently. Route-by-project cannot express it at any width. **A cross-repo master must resolve to
refuse/park, never to route** — §3 said so, and the shipped arm is the first thing that could have
acted on it.

**(b) The silent rc-0 that §8 told the next session to verify is now measured.** From this VM:

```
./bin/cc-backlog list --all   → rc=0, 0 bytes of output
test -e ~/.claude/autonomy/backlog.jsonl → ABSENT
```

`bin/cc-backlog:887` resolves the store to `$HOME/.claude/autonomy/backlog.jsonl`, which does not
exist here, and the read reports **success** over it. A `cc-backlog block` issued from this venue
would therefore exit 0 and write nothing. That failure mode is established as fact.

⚠️ **It is NOT hereby claimed to be what happened to §8's disposition.** §8 filed the block as an
*operator* action needing the Mac, so the likeliest history is that it was never run at all rather
than that it ran and silently no-opped. The two are indistinguishable from here, and the distinction
matters to whoever fixes the return path: one is a broken rail, the other a dropped handoff. What
*is* certain is the outcome — the row was not parked, and it re-fired.

**(c) Not fixed here — and the grounds are now MECHANICAL, where §6's were a judgment call.**
`bin/cc-venue:55` states the guard verbatim: *"A cloud VM must never build or run the venue rule: it
would be deciding its own admission, and its 50-commit clone cannot read the history that justifies
the exclusions."* This clone is shallow at exactly 50. So the venue rule was neither built nor run
in this session, deliberately — including `cc-venue assess` on this row, which would have been the
tempting move. §6's independent grounds were re-measured and still hold: **`bats` and `shellcheck`
are both ABSENT** on this host, so a shell/Python change to the fire path cannot be gated here, and
`bin/cc-offload` fires paid sessions.

**(d) The "~0-cost" plan-index stopgap is not reachable from a VM either.** §3 costed *"a
`projectName` entry in the plan index"* as a data entry rather than a build, and that costing is
correct — `scripts/find-plan.sh:73` already reads `.plans[$k].projectName` and prefers it over the
path basename. But `:38` resolves `CC_PLAN_INDEX_PATH` to `$HOME/.claude/plans-index.json`: live
operator-box state, **outside this repo**, and a C10 in-place edit. So the one remedy a VM could
plausibly have applied is the one it structurally cannot reach. Every option in the set now needs
the Mac.

### The item itself — still NOT adjudicated

§7 stands verbatim and is not weakened by a third look. R1-R4 (`pnpm lint` red on reso's trunk, the
four unlanded branches, the Amplify/Fly split-brain, `doc_classifier`'s `require_role` holes) remain
**open, correct as filed, and unstarted**. Nothing about them was readable from this session, and
per the honesty standard `tenant-drift-venue-refusal-2026-08-24.md` §2 sets, whether any of their
cures landed on the product trunks in the interim is **unknown and unconfirmable from this venue** —
not "unrefuted". The plan's falsifier returning `NOT REFUTED` at fire time says only that a probe
declined to retract; it is not a positive confirmation, and it reads a plan file, not the product
trees. **What is refuted is the venue, for the third time — never the plan.**

## 10 · Operator actions (2026-08-27)

Unchanged in shape from §8, updated for the third occurrence. Needs the Mac — the ledger is absent
here and a write from this venue exits 0 without writing (§9b).

```
cc-backlog block 8f59467c92b0 --needs "re-dispatch ONLY to a session holding BOTH reso-management-app and doc_classifier (the local drain, per MASTER_PRODUCT_REPOS.md Phase 0). This row is cross-repo: a cloud VM gets one git_repository source permanently, so no cloud fire can serve it at any width. THIRD misroute of this id (08-15, 08-17, 08-27); premise NOT adjudicated; the shipped cc-eligible cross_repo arm passes it correctly because its project label is accurate — see docs/research/venue-foreign-master-redispatch-2026-08-17.md#9"
```

`block`, not `reopen` — blocked on **where it was sent**, not on information or a judgment call.
§8 already said this and the row still re-fired, so the block taking is the thing to verify, not the
command to re-derive.

The §9a finding belongs on the existing under-specification row (`--source 8f59467c92b0`, §8) as a
confirmation, not a new row: what it adds is that the prediction has been **observed against shipped
code**, which is the evidence that decision was waiting on.
