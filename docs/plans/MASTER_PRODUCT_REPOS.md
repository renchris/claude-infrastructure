---
status: open
---

# MASTER: product repos — the operator's actual products, one wave per repo

**Condition key:** `master-product-repos` · **Live members 2026-08-12 (measured after the apply):** 59 (34 open · 25 blocked)
**Inventory (note the project split — it is the lease boundary):**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-product-repos" and .status!="done")|"\(.project) \(.id) \(.status) \(.title[0:80])"' | sort`

🚨 **ONE SLUG, ONE LEASE GROUP PER PROJECT — and that is a mechanism, not a filing convenience.**
`cc-backlog` keys a condition id on project+condition, and the sibling lease selects on
`(.project) == $p` (`bin/cc-backlog:1819`). So this single slug resolves to **one independent lease
group per repo**: a reso wave and a doc_classifier wave can run concurrently without either refusing
the other, while the store still reports one effort per repo. Two slugs would buy the same isolation
and cost an extra effort against a budget that asks for ten.

**Why the repo outranks the subsystem.** A row reading *"pnpm lint is RED on origin/main"* is a reso
effort, not a claude-infrastructure verification effort: the tree it edits decides which wave can work
it, and no claude-infrastructure session has that checkout. Measured while building the classifier —
ordering the subsystem rules first stole 43 of reso's 57 rows into waves that could not have touched
them.

**Why this matters most of all the ten.** The parent plan opened on this number:
`reso-management-app` took **0 commits in 7 days** while `claude-infrastructure` took 884. *The
infrastructure had become the work.* This group is the operator's actual product.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

🚨 **SUPERSEDED FOR THE LOCAL DRAIN (2026-08-13): read every `S` below as `T`.** This table was
authored under the one-session-per-wave model. The non-cloud backlog is now worked by THE LOCAL DRAIN —
a single standing session whose entire purpose is that it occupies **one** of the ~15 concurrent slots
for its whole life (`BACKLOG_SELF_DRAINING_2026-08-12.md:392`: *"One slot, indefinite duration — because
the bottleneck is concurrent sessions (~15), not session length"*). Firing a dispatched session per wave
spends a second slot and defeats the mission. Work every wave with **teammates INSIDE the drain session**
(`Agent({name})`, worktree-isolated, ≤150-line briefs, each torn down with a structured
`shutdown_request` — a plain-text broadcast leaves an orphaned pane and worktree), and recycle at the
EFFORT boundary via `handoff-fire.sh --recycle` — same pane, fresh context, no new slot. The `S` markers
below are left in place as the historical record of how these waves were originally scoped.

🚨 **THE MASTER ROW IS NOT DISPATCHABLE TO A `claude-infrastructure` WORKER — CLOUD OR LOCAL
(measured 2026-08-15).** Every open wave below edits `reso-management-app` or `doc_classifier`;
this plan's home repo contributes no work at all. But the dispatch chain projects an item by the
plan FILE's location, not by the trees its waves edit:

`scripts/find-plan.sh:70 project_name_for()` derives the project from the path (`*/docs/plans/*` →
basename of the repo dir) → `bin/cc-discover` C2 mints `advance <title>` under that project →
`bin/cc-eligible:593 repo_for()` measures `~/Development/claude-infrastructure`, finds no
local-only state named in the span fields (`title · dodRef · condition · source` — never the plan
BODY, where every foreign tree is named), and returns `eligible` → a claude-infrastructure worker
is fired at work in two trees it does not hold.

Measured on a cloud fire of `8f59467c92b0`: the VM held exactly one checkout
(`claude-infrastructure`), its GitHub scope was pinned to that one repo, and neither
`~/Development/reso-management-app` nor `~/Development/doc_classifier` existed — so R1-R4 were
**unreachable, not merely hard**. The gate is not wrong about what it measures; it measures the
tree the LABEL names, and for a cross-repo master the label and the work disagree. This plan
already states the governing rule two sections up — *"the tree it edits decides which wave can
work it"* — and its own master row is the counter-example to it.

**Until the routing fix lands, work these waves only from a session that HOLDS the target tree**
(the local drain, per the SUPERSEDED note above), and treat the correctly-projected member rows as
the real handles — they carry `reso-management-app` / `doc_classifier` and route correctly. The
master row is a coordination header, not a unit of work; advancing it means advancing members.

🚨 **CORRECTION (measured 2026-08-20): a correctly-projected member row misroutes too — the
projection was never the load-bearing part.** A cloud fire of `b0be87487228` (project
`reso-management-app`, "`--bs-cap` under-reserves the caption", naming `_lib/type.ts` and
`Surface.tsx`) landed on a VM holding exactly one checkout — `claude-infrastructure` — with GitHub
scope pinned to `renchris/claude-infrastructure` and no `~/Development/reso-management-app` on
disk. The label was RIGHT and the work was still unreachable, so the paragraph above is wrong where
it says member rows "route correctly": correct projection buys nothing, because **nothing in the
chain compares the item's project to the repo the VM will actually hold.**

Read out of `bin/cc-eligible` this session, the cloud gate has exactly two arms and neither can
ask that question:

- `classify_all()` (line 445) is pure regex over the span fields — it fires on *spellings* of
  local-only state (`launchd`, `sudo`, …). A repo name is not such a spelling, so a foreign-tree
  item matches nothing.
- `DEEP_HISTORY` (via `HistoryOracle.unreachable()`) certifies cited shas against the 50-commit
  cloud horizon. This item cites no sha, so the arm is silent.

With both silent, `assess_full()` returns `eligible — repo-only work, no local-only state named`,
and that verdict is TRUE as written and useless as read: `cmd_explain` already warns that
"eligible" means *no spelling in the list fired*, "which is weaker than 'this is repo-only work'".
Worse, `repo_for(project)` resolves `~/Development/reso-management-app` and the oracle certifies it
`ok` — a healthy reading of a tree the *dispatching* box holds, which says nothing whatever about
the *receiving* one. **The gate measures the wrong box.** So this is not a missing spelling to add
to the list (the remedy `REFUSAL_NOTE` offers); it is a missing arm — a cross-repo/venue check that
convicts when `project` is not the repo the target venue is scoped to. Adding a spelling cannot
close it, and forcing past it re-burns a slot each time.

Consequence for this table: the "work these waves only from a session that HOLDS the target tree"
rule stands, but it must be enforced at `claim --venue cloud`, not left to the label. Until it is,
**every** open `reso-management-app` / `doc_classifier` row is cloud-ineligible in fact while
reading `eligible`, and each cloud dispatch of one costs a full worker slot that can only report
the blocker back. (`b0be87487228` did exactly that: it could not even record its own transition —
the VM has no `~/.claude/autonomy/backlog.jsonl`, so the ledger is unwritable from the venue the
gate sent it to.)

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **R1 · reso: unblock the gate** | **S** (reso worktree) | `pnpm lint` green on `origin/main`; a fresh worktree can pass `ship-land` | — |
| **R2 · reso: land the queue** | **S** (reso worktree) | the 4 unlanded branches (87+ commits) landed or explicitly abandoned | R1 |
| **R3 · reso: prod split-brain** | **S** (reso worktree) | Amplify/Fly deploy path is single-brained and audited | — |
| **R4 · doc_classifier** | **S** (doc_classifier worktree) | the security-gated routes fixed, the 3 gate-green branches merged | — |

R1-R3 and R4 are **separate leases**, so R4 runs concurrently with the reso waves.

🚨 **READ `reso-management-app/CLAUDE.md` BEFORE LANDING ANYTHING THERE, and run its
`scripts/land-status.sh`.** Landing cost is a perishable fact about live infrastructure: reso cut over
to LAND_SHIP_V2 on 2026-08-02, which made `/ship` free and left `/deploy` as the only money-spender —
and a global policy file that restated the old fact caused a refusal to land a docs-only commit three
days after it became false. A live measurement outranks any remembered verdict, including this
paragraph.

**Lead context budget:** ≥50%, and the lead of this group holds the deploy decisions. **Succession
point:** between R2 and R3.

## Sub-waves

### R1 · reso: the gate is red on trunk, so nothing can land
`pnpm lint` is RED on `origin/main` — 122 `import-x/extensions` errors on `styled-system/{css,jsx,recipes}`
imports — and it is *unusable* in a fresh worktree for the same reason. `next-env.d.ts` is gitignored,
generated, and absent, so a fresh worktree cannot pass `ship-land`'s typecheck gate. `tsconfig.json`
excludes `scripts/bottle-gen*.ts`, so typecheck is blind to the whole image-generation surface.
Provisioner scripts have ZERO eslint coverage (`eslint.config` globally ignores `scripts/**`).

### R2 · reso: the landing queue
Four branches hold unlanded value: heat-v2 / walk-in rebuild (39 commits on `cc-225947-27025`,
worktree `wt-pool-1`), platform-page (25 commits), bottle-service VT choreography (10 commits), BALLAST
bottle-service menu. Several are blocked on `design:gate` red **from machine saturation, not from the
diff** — so retry on a quiet machine before touching the code (memory:
`bound-must-fit-the-band-not-the-bench`). Settle `wt-pool-1` BEFORE any main history rewrite.

### R3 · reso: production split-brain
Amplify Oregon frozen ~7 h / 24 commits with `autoBuild=False` on `main` and no `release` branch
connected; Path F auto-deploys write no `releases.jsonl` audit row, so the Fly Build SLO panel is blind
to the production deploy path; the Amplify build cache has never been WRITTEN since ~2026-06-12;
`fly-log-shipper-iad` ships NOTHING for a serving `reso-iad`. Several members are console-only steps
already keyed to `master-operator-gated` — check that group first.

### R4 · doc_classifier
`POST /api/run/start` spawns the whole run-all spine (`subprocess.Popen`) with no `require_role`; all 6
run-monitor routes plus `/api/capabilities` are gated only by `run_monitor`; `reviewapp/api/auth.py`
mints a fresh `PyJWKClient` per token (pre-auth JWKS fetch amplification, PoC-proved); the pinned uv
toolchain wheel is fetched with no `--require-hashes` and no `--index-url`. Three gate-green branches
are waiting to merge. **These are the security members of this group — work them first.**

## Definition of done
Both product trees can land: their gates are green on trunk and in a fresh worktree, the unlanded
branch queue is empty or explicitly abandoned with reasons, the production deploy path is
single-brained and audited, and doc_classifier's authorization holes are closed with tests.

## Status log
- **2026-08-28 — THIRD cloud dispatch of `8f59467c92b0`, and the finding is that ALL THREE
  specified remedies miss this row.** Same VM shape as 08-15 and 08-17 (one checkout, GitHub scope
  of one repo, no `~/Development`), so R1-R4 were again unreachable by construction and remain
  **open, correct as filed, and unstarted** — nothing about the plan is refuted, only the venue.
  What is new is that "the remedy has not landed yet" is no longer the explanation. A remedy *did*
  land — `bin/cc-eligible`'s reach arm (`CROSS_REPO`, `cross_repo()` at :766, in `BLOCKING`) — and
  **three** comparisons now fail on this row, each for its own measured reason:
  **(1)** the landed arm is keyed on `item.project`, and this row's label is *accurate*
  (`claude-infrastructure` == the lane), so both early returns fire and it is silent;
  **(2)** 🚨 **the subject discriminator this plan's 08-17 entry prescribed would ALSO miss it** —
  it reads the item's TEXT, and `bin/cc-eligible:490` fixes that span to
  `("title","dodRef","condition","source")` while `bin/cc-discover:274` fixes what a plan-minted row
  puts there (`advance <H1>` · the plan path · the condition · `plan-open`). `grep -cE
  'reso-management-app|doc_classifier'` over the whole span returns **0**; every foreign tree is
  named only in the plan BODY. Reproduced end-to-end with the exact minted span and all three repos
  present: `verdict=eligible`, `refused: (nothing fired)`, `claim --venue cloud` **exit 0**;
  **(3)** the natural repair — follow `dodRef` and scan the plan body — **over-refuses**: 24 of the
  76 plans in `docs/plans/` name a foreign dispatchable project, and the self-normalising variant
  flags 12, most of them genuine claude-infrastructure work (`HOOK_CHAIN_COST` 0/3,
  `LAND_PIPELINE_V2` 1/2, `DEPLOY_DECOUPLING_V2` 1/3). That is the expensive false-positive
  direction `tests/cc-eligible-cross-repo.bats` names, so it is not a drop-in for (2).
  Consequence for the filed decision (`cloud-venue-project-repo-mismatch-2026-08-16.md` §3): the
  pair (`item.project`, `session.attached_repo`) is **not sufficient in either proposed extension**,
  which the decision could not have known — it was filed believing the subject conjunct would close
  the class. Still standing and untouched: the ~0-cost **`projectName` entry in the plan index**
  (`scripts/find-plan.sh:73` already reads it), which is a *declaration* and therefore has no
  false-positive surface — but it lives in `$HOME/.claude/plans-index.json`, which is desk state and
  absent from the VM. **No gate arm was written**: the two shapes reachable from inside the VM are
  exactly the two just refuted, and this plan reserves the fix shape for the desk. Also re-confirmed:
  the block rail fails at **rc 0** from a VM (`cc-backlog block …` → `unknown id`, exit 0), so the
  block must be applied desk-side. Full measurement →
  `docs/research/venue-master-redispatch-3rd-2026-08-28.md`. **Disposition: `cc-backlog block`**,
  unchanged.
- **2026-08-17 — the SAME row was cloud-dispatched AGAIN, and the re-fire is the finding.**
  `8f59467c92b0` was fired into an identical VM shape (one checkout, GitHub scope of one repo, no
  `~/Development`) ~2 days after the 08-15 entry below wrote its disproof into THIS FILE. R1-R4 were
  untouched and remain **open, correct as filed, and unstarted** — nothing about the plan is
  refuted, only the venue. Three things this fire measured that the 08-15 one could not:
  **(1)** a disproof in plan prose does not park an item — nothing in the dispatch chain reads it,
  so the 08-15 entry bought two days; **(2)** the class census in `docs/research/venue-*` is
  undercounted — the 08-15 fire of this row is absent from it (recorded here instead, inside
  `b4ddaa27`, a commit about land-blockers), making the real figure **six dispatches over five
  items in four days**; **(3)** 🚨 **both options of the filed remedy PASS this row.** The open
  decision (`cloud-venue-project-repo-mismatch-2026-08-16.md` §3) is keyed on
  (`item.project`, `session.attached_repo`) — but this row's project label is *accurate*
  (`find-plan.sh:70` derives it correctly from the plan's path) and only the BODY names the foreign
  trees, so fail-closed finds every term satisfied and route-by-project resolves right back to this
  VM. Resolving it as written stops four of the six and neither of this one's. The remedy needs the
  08-15 **subject** discriminator restored as a conjunct at `cc-offload`.
  One cost correction to the four-mechanism list in Phase 0: *"a `projectName` entry in the plan
  index"* is **not a build** — `scripts/find-plan.sh:73` already reads `.plans[$k].projectName` and
  prefers it over the path basename, so it is a ~0-cost data entry, and setting it to a foreign
  project composes with fail-closed to park THIS row specifically. Full measurement →
  `docs/research/venue-foreign-master-redispatch-2026-08-17.md`. **Disposition: `cc-backlog block`,
  not `reopen`** — blocked on where it was sent; the rails fail at rc 0 from a VM, so verify the
  block took rather than assuming it.
- **2026-08-15 — a cloud dispatch of the master row `8f59467c92b0` advanced nothing, and the
  disproof is the ROUTING CHAIN, not the plan.** The waves are all still open and all still
  correct; what is refuted is that this row can be worked by the venue it is fired at. Full
  measurement + the four-tool chain that produces it → the 🚨 block in Phase 0 above. Nothing in
  R1-R4 was touched, because nothing in R1-R4 was reachable: the worker held one checkout and the
  two product trees were absent. **Filed as a decision for the desk, not fixed here** — the fix
  shape is a choice between four mechanisms that `find-plan.sh`, `cc-discover`, `cc-eligible` and
  `cc-dispatch` all read (a plan-frontmatter `project:` key · a `projectName` entry in the plan
  index · a new `ineligible-foreign-tree` class in `cc-eligible` · a not-dispatchable plan list
  beside `dispatch-projects.conf`), and a cross-repo master targets TWO trees, so the single-value
  options cannot express it. A one-item worker should not pick that unilaterally. Note the fix is
  NOT confined to `--venue cloud`: a *local* claude-infrastructure worker is equally unable to
  edit these trees under the dedicated-worktree rail, so `cc-eligible` (which only answers "may
  this go off-box?") is the narrowest of the four and probably the wrong one.
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 58 rows joined by
  `group.py`: 44 `reso-management-app`, 15 `doc_classifier`, plus `reso`, `reso-qa-runner`,
  `lakehouse-lecture` and `agent-build-hackathon` singletons. The 2026-08-09 triage deliberately left
  these unmapped ("they belong to OTHER repos and have their own masters"); this is that master.
