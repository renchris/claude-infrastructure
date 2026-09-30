# The third dispatch of `8f59467c92b0`, and the finding is that ALL THREE specified remedies miss it

**Date:** 2026-08-28 · **Measured on:** a cloud VM clone of `renchris/claude-infrastructure`, branch
`claude/fire-20260828T194440Z-99290-1`, HEAD `cec44595` (== `origin/main`, `HEAD..origin/main` = 0).
Written from inside the VM, in the posture of `venue-foreign-subject-repo-2026-08-15.md` and
`venue-foreign-master-redispatch-2026-08-17.md`, whose conclusions this file extends and — on one
point each — refutes.

**Finding, in one line:** `8f59467c92b0` was dispatched into an unworkable venue for the **third**
time in thirteen days, and the reason is no longer "the remedy has not landed yet" — a remedy *did*
land, and **neither it, nor the discriminator the 08-17 status entry prescribed to complete it, nor
the natural repair of that discriminator, can refuse this row.** Each fails for a different,
measured reason. The gap is not a missing spelling or an unimplemented conjunct; it is that every
proposed comparison reads a field that, for this row, is clean.

---

## 1 · The venue, measured

Identical in shape to the 08-15 and 08-17 fires:

```
$ ls -d ~/Development                          → No such file or directory
$ ls -d ~/Development/reso-management-app      → No such file or directory
$ ls -d ~/Development/doc_classifier           → No such file or directory
$ git remote -v                                → origin  https://github.com/renchris/claude-infrastructure
GitHub MCP scope                               → renchris/claude-infrastructure only
```

R1-R4 of `docs/plans/MASTER_PRODUCT_REPOS.md` edit `reso-management-app` and `doc_classifier`
exclusively. Both trees are absent and both are outside the session's GitHub scope, so the waves are
**unreachable by construction, not by difficulty** — the same end state, and the same sentence, as
the two prior fires.

## 2 · The rails do not reach, and they fail at rc 0

The dispatch brief's own remedy path (`cc-backlog block 8f59467c92b0 --needs …`) was run rather than
assumed, exactly as the 08-17 entry instructed:

```
$ cc-backlog block 8f59467c92b0 --needs "…"
cc-backlog block: unknown id 8f59467c92b0
rc=0
```

`~/.claude/autonomy/` holds no `backlog.jsonl` on arrival (the directory is created empty by the
first call), and `cc-backlog list --all --json` returns `[]`. So the store this row lives in is not
present, the refusal is spelled on stdout, and **the exit status is 0** — a caller that checks `rc`
records a successful block that never happened. A cloud VM's only durable channel to the desk is the
branch it pushes; this file is the notification.

## 3 · The landed arm is project-keyed, and this row's project is correct

`bin/cc-eligible` now carries the reach arm the 08-21 measurement asked for
(`CROSS_REPO = "ineligible-cross-repo"`, `cross_repo()` at :766, in `BLOCKING`). It compares the
item's `project` to the one repo the lane attaches, by normalised origin:

```python
item_repo = repo_for(project)                      # ~/Development/<project>
if os.path.realpath(item_repo) == os.path.realpath(lane): return False, ""
if item_origin and item_origin == lane_origin:     return False, ""
```

This row's `project` is `claude-infrastructure`, which **is** the lane. Both early returns fire and
the arm is silent. That is the arm working as designed — it was built for the 106-of-133 label-foreign
population and it refuses those correctly. It simply cannot see a row whose label is accurate.

Predicted by `MASTER_PRODUCT_REPOS.md` Phase 0 on 08-20 ("correct projection buys nothing"); this
file confirms it against the landed code rather than against the proposal.

## 4 · NEW — the prescribed subject discriminator would ALSO miss this row

The plan's 08-17 status entry closes with the remedy: *"The remedy needs the 08-15 **subject**
discriminator restored as a conjunct at `cc-offload`."* That discriminator, as specified in
`venue-foreign-subject-repo-2026-08-15.md`:

> An item whose **text** names a dispatch-set project **other than its own `project`** is
> subject-foreign, whatever its label says.

It works on `9333991e4544` because, in that doc's own words, *"this row's title opens with
`doc_classifier`"*. **It does not work here, because this row's text names neither foreign project.**

The classified span is not free text — `bin/cc-eligible:490` fixes it:

```python
SPAN_FIELDS = ("title", "dodRef", "condition", "source")
```

and `bin/cc-discover:274` fixes what a plan-minted row puts in it:

```sh
add_candidate "advance $title" "$proj" "$path" "plan-open" …
#   title=advance <plan H1>   project=<from plan path>   dodRef=<plan path>   source=plan-open
```

So for `8f59467c92b0` the entire classified span is:

| field | value | names a foreign project? |
|---|---|---|
| `title` | `advance MASTER: product repos — the operator's actual products, one wave per repo` | no |
| `dodRef` | `…/docs/plans/MASTER_PRODUCT_REPOS.md` | no |
| `condition` | `master-product-repos` | no |
| `source` | `plan-open` | no |

`grep -cE 'reso-management-app|doc_classifier'` over that span returns **0**. Every foreign tree is
named in the plan **body**, which is not in the span — precisely the sentence Phase 0 already
carried ("never the plan BODY, where every foreign tree is named"), now shown to defeat the
*remedy* and not merely the incumbent gate.

Reproduced end-to-end against the real predicate, with the exact minted span and all three repos
present on the dispatching side (fixture `$HOME`, fixture store; the id keys to `79e7c3cb7357`
because the hash covers project+title+source and this fixture's `source` is verbatim `plan-open`):

```
$ cc-eligible why 79e7c3cb7357
  verdict : eligible
  project : claude-infrastructure
  refused : (nothing fired)
  reach   : reachable-or-unmeasured — either the lane's own repo, or nothing measurable — arm fails OPEN
  history : ok — certified against a FULL clone — the horizon is real

$ cc-backlog claim 79e7c3cb7357 --by test-sid --venue cloud
79e7c3cb7357
claim exit=0                                   ← ADMITTED, third time running
```

Every arm is silent and **every arm is correct as written**. `refused: (nothing fired)` is true — the
row spells no refused word. `reach: the lane's own repo` is true — the label really is
`claude-infrastructure`. `history: ok` is true — the dispatching desk holds a full clone. The verdict
`eligible` is sound under every rule the gate has and useless as read, which is the `cmd_explain`
caveat ("weaker than 'this is repo-only work'") reaching its limit case.

## 5 · NEW — and the natural repair over-refuses badly on this repo's own corpus

The obvious fix to §4 is to follow `dodRef` to the plan and scan its **body** for dispatch-set
projects other than the item's own. Measured across all 76 plans in `docs/plans/` (word-boundary
counts of the two dispatchable foreign labels, against `claude-infrastructure`):

- **24 of 76 plans** name a foreign dispatchable project at least once. A `>= 1` rule therefore
  refuses cloud dispatch for every item minted from **32%** of the plan corpus.
- The self-normalising variant — *the plan names a foreign tree at least as often as its own* —
  flags **12**, and most of them are genuine `claude-infrastructure` work that a cloud VM can do:

| plan | own | reso | dc | what it actually is |
|---|---|---|---|---|
| `MASTER_PRODUCT_REPOS` | 10 | 10 | 10 | **truly foreign** — the row under study |
| `HOOK_CHAIN_COST` | 0 | 3 | 0 | claude-infrastructure hook cost; reso is an *example* |
| `LAND_PIPELINE_V2` | 1 | 2 | 0 | claude-infrastructure land pipeline |
| `DEPLOY_DECOUPLING_V2` | 1 | 3 | 0 | claude-infrastructure deploy decoupling |
| `SUBAGENT_STOP_HOOK_LOOP` | 0 | 1 | 0 | claude-infrastructure hook loop |
| `MASTER_OPERATOR_GATED` | 0 | 1 | 0 | claude-infrastructure operator gating |

Counting the other direction is no better: `BACKLOG_DRAIN_24_7` names reso 22 times and
`doc_classifier` 10 — more foreign mentions than any plan except this one — and is unambiguously
claude-infrastructure work, escaping only because it also names its own project 110 times.

This is the false-positive direction that `tests/cc-eligible-cross-repo.bats` calls *"the expensive
one — it would refuse work that is in fact perfectly runnable off-box"*, and the corpus says a body
scan lands in it immediately. **The 08-15 doc's caveat was right and understated:** it anticipated
that "a genuine cross-repo claude-infrastructure item names every project by construction", and the
measurement shows that describes a third of this repo's plans, not an edge case.

So the body scan is not a drop-in for the text scan. No arm was implemented here on the strength of
this, deliberately — see §6.

## 6 · What this leaves standing, and why nothing was implemented

Three specified comparisons, three measured refutations:

| remedy | reads | why it misses `8f59467c92b0` |
|---|---|---|
| landed `cross_repo` (08-21) | `item.project` vs lane origin | the label is **accurate**; project == lane |
| 08-15 subject discriminator (prescribed by the plan's 08-17 entry) | the item's **text span** | the span names no foreign project (§4) |
| dodRef **body** scan (the natural repair) | the plan body | over-refuses 24/76 plans (§5) |

The filed decision (`cloud-venue-project-repo-mismatch-2026-08-16.md` §3, and the row the 08-17 entry
opened) is keyed on the pair (`item.project`, `session.attached_repo`). This measurement says the pair
is **not sufficient in either of its proposed extensions**, which the decision as filed could not have
known — it was written believing the subject discriminator was the missing conjunct and that
restoring it would close the class.

What still stands, and is untouched by anything measured here, is the mechanism the 08-17 entry
costed at ~0: **a `projectName` entry in the plan index**, which `scripts/find-plan.sh:73` already
reads and prefers over the path basename. It is a *declaration*, not a classifier, so it has no
false-positive surface at all — it refuses exactly what it is told to refuse and nothing else. It is
also **not reachable from this VM**: the index lives at `$HOME/.claude/plans-index.json`, which is
desk state and is absent here.

No gate arm was written this session, and that is a considered refusal rather than an omission.
`MASTER_PRODUCT_REPOS.md` reserves the fix shape for the desk in terms this session has no standing
to overturn — *"A one-item worker should not pick that unilaterally"* — and the two shapes a worker
*could* have implemented from inside this VM are the two §4 and §5 just refuted. Landing a classifier
measured to refuse a third of the plan corpus, in order to park one row, would trade a burned slot
per fire for a silently narrowed dispatch surface across every project.

## 7 · Disposition

**`block`, not `reopen`** — unchanged from the 08-17 entry, and for the same reason: this row is
blocked on *where it was sent*, not on missing information. The rail does not reach from here (§2),
so the block must be applied desk-side. The item is not done, not refuted, and not startable at this
venue.

**Nothing in R1-R4 is refuted.** The waves are open, correct as filed, and unstarted; the plan's
frontmatter (`status: open`) is accurate and `plan-phase-scan.sh --falsify` correctly declines to
retract it (verified at dispatch: exit 1, silent). This file adjudicates the **venue**, and nothing
about reso's red `pnpm lint`, its four unlanded branches, its Amplify/Fly split-brain, or
doc_classifier's unauthenticated `POST /api/run/start` — none of which were readable from this
session, and diagnosing which from a title alone is the anti-goal `bin/cc-venue` §5 names.

## 8 · The cost, stated plainly

Three dispatches (08-15, 08-17, 08-28) over thirteen days, each spending a full worker slot to
re-derive that the work is elsewhere. The 08-17 entry measured that a disproof written into plan
prose *"bought two days"* because nothing in the dispatch chain reads prose. This file is prose too,
and will buy nothing on its own — the only thing that stops the fourth fire is a desk-side change,
and §6 names the one that carries no false-positive cost.
