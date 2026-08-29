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

✅ **RESOLVED FOR THE MEMBER ROWS — and NOT for this master row (measured 2026-08-29).** The missing
arm the paragraph above asks for has **landed**: `bin/cc-eligible` now carries
`CROSS_REPO = "ineligible-cross-repo"` (`:430`), a measured — not spelling — arm computed by
`cross_repo(project)` (`:766`) and placed before the history arm. Its own census (`:404-427`) puts
**106 of 133 `NOT-STARTED` cloud sessions (80%) on a repo the VM was never given** (92
`reso-management-app`, 14 `doc_classifier`). So the sentence above — *"every open
`reso-management-app` / `doc_classifier` row is cloud-ineligible in fact while reading `eligible`"* —
**is now false in its second half**: those rows read `ineligible-cross-repo` and are refused at
`claim --venue cloud`, which is exactly where it asked for the enforcement.

🚨 **This master row is in the residual the arm cannot drain, and it re-fired on 2026-08-29 — the
THIRD dispatch of `8f59467c92b0` (08-15, 08-17, 08-29).** Run against the shipped predicate with the
lane pinned to the attached repo, an R1 member row returns `ineligible-cross-repo` while this row
returns `eligible · refused: (nothing fired) · reach: … arm fails OPEN` — because `cross_repo` is
keyed on `project`, and this row's project label is *accurate*. The 2026-08-17 prediction that "both
filed options PASS this row" is therefore no longer a projection about a filed option; it is a
measurement against landed code.

**And the third remedy misses it too.** The 08-15 subject discriminator (*an item whose text names a
dispatch-set project other than its own*) reads `SPAN_FIELDS = ("title","dodRef","condition",
"source")` (`cc-eligible:490`). This row's span text names `reso-management-app` **0 times** and
`doc_classifier` **0 times**; this plan's BODY names them 10 and 9 times. A conjunct that catches
this shape must read the **content of the `dodRef`**, not the item's fields — strictly more than
§3 of the research doc proposed. Full measurement, the two-step stopgap that *does* park it, and the
re-measured refusal grounds → `docs/research/venue-foreign-master-redispatch-2026-08-17.md` §9.

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
- **2026-08-29 (10:55Z) — a FOURTH fire, six hours after the third, and the third fire's exit code
  was wrong.** `8f59467c92b0` reached a fourth cloud VM of the identical shape, 6 h 24 m after the
  entry below landed its own disproof on trunk (`d075abc2`, 04:30:59Z). R1-R4 untouched and **still
  open, correct as filed, and unstarted** — the plan is not refuted, the venue is, for the fourth
  time. Two things this fire measured:
  **(1)** the re-fire interval is **shortening**, not stable — 2 days · 12 days · **6 h 24 m** —
  so the cost of the unclosed decision is now roughly a worker slot per dispatch pass, not one per
  week. A full disproof landed on trunk *between* fires 3 and 4 and changed nothing, re-confirming
  at a tighter interval that nothing in the dispatch chain reads plan prose.
  **(2)** 🚨 **the entry below is wrong about the exit code, and its causal claim goes with it.**
  Re-run here on **unchanged** code (`git diff d075abc2..origin/main -- bin/cc-backlog` is empty),
  capturing each rc in isolation: `cc-backlog block` returns **rc 3** with `unknown id` on stderr
  (`bin/cc-backlog:1943` — `has_id … || return 3`), and `cc-notify --role desk` returns **rc 3**
  naming `role-unset`. The block rail therefore **fails closed and says so**; the dispositions of
  08-15 and 08-17 did not fail *silently*, they failed *loudly and unheard*. The one genuinely
  silent rail is `cc-backlog list --all` — **rc 0, zero bytes**, indistinguishable from an empty
  backlog. That is where the store-absent verdict is missing, and hardening it is what would make
  this conviction readable by the tooling that fires these items rather than only by the session
  that cannot act on it.
  One new contribution to the still-open four-mechanism decision: the options differ in **where
  they live**, and that is what all four fires have foundered on. A plan-frontmatter `project:` key
  is the **only one whose fix is a commit** — the plan index is untracked live-layer state, the
  `cc-eligible` arm is refused by `bin/cc-venue`'s guard, and `dispatch-projects.conf` is keyed on
  project with the incumbent unioned in unconditionally. Not implemented here (ungated shell change
  on a VM with `bats`/`shellcheck`/`shfmt` all absent — re-measured; and a single-value key still
  cannot express a master targeting two trees). Full measurement →
  `docs/research/venue-foreign-master-redispatch-2026-08-17.md` §10.
  **Disposition: unchanged — `cc-backlog block`, still not `reopen`; both steps are desk actions.**
- **2026-08-29 — the guard LANDED, the member rows are stopped, and THIS row was fired a third
  time.** `8f59467c92b0` reached a third cloud VM of the identical shape (one checkout, GitHub scope
  of one repo, no `~/Development`, 50-commit shallow clone). R1-R4 untouched and **still open,
  correct as filed, and unstarted** — nothing about the plan is refuted, only the venue, for the
  third time. Three things this fire measured that 08-17 could not:
  **(1)** the missing arm 08-15/08-16/08-17 asked for is **on trunk** — `ineligible-cross-repo` in
  `bin/cc-eligible`, measured over the whole live cloud population (106 of 133 stalled sessions,
  80%, sent to a repo the VM was never given). 08-17's *"guard in the enforcing store: none"* is
  retracted, and the Phase 0 claim that member rows still read `eligible` is now false.
  **(2)** Run end-to-end against that shipped predicate, an R1 member row is **refused**
  (`ineligible-cross-repo`) and **this row is still `eligible`** — `refused: (nothing fired)`, the
  reach arm failing OPEN — because `cross_repo` is keyed on `project` and this row's label is
  accurate. The 08-17 prediction is now a measurement against landed code.
  **(3)** 🚨 **the 08-15 subject discriminator would miss it too.** Every arm reads
  `SPAN_FIELDS = (title, dodRef, condition, source)`; this row's span text names
  `reso-management-app` and `doc_classifier` **zero** times while this plan's body names them 10 and
  9. So **all three** filed remedies pass this row, and a conjunct that catches it must read the
  `dodRef`'s CONTENT — more than §3 proposed. The one thing that does park it is the ~0-cost
  `projectName` entry, now composable with a LANDED arm, and it needs **two** steps because the id
  hashes project+title+source: `block` the existing id *and* set `projectName`, or the plan mints a
  fresh passing successor. Full measurement →
  `docs/research/venue-foreign-master-redispatch-2026-08-17.md` §9.
  **Disposition: `cc-backlog block`, still not `reopen`** — and 08-17's warning to *verify the block
  took* is now vindicated rather than precautionary: re-measured here, `cc-backlog block` answers
  `unknown id` at **rc 0** against an absent store, which is why the 08-15 and 08-17 dispositions
  both failed silently and this row fired a third time. *(⚠️ CORRECTED by the 2026-08-29 10:55Z
  entry above: re-measured on unchanged code, `block` returns **rc 3** with stderr — it fails
  closed. `list --all` is the rail that answers rc 0 silently. The dispositions failed unheard,
  not unsignalled.)*
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
