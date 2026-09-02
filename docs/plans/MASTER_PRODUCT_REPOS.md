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
- **2026-09-02T08:20Z — SIXTH fire, and it is the one that NARROWS the cause from three candidates
  to one.** `8f59467c92b0` reached a sixth cloud VM of the identical shape (`$HOME` `/root`,
  `~/Development` absent, `/home/user` holding `claude-infrastructure` alone, clone 50 commits with
  `.git/shallow` present, `HEAD..origin/main` = 0). R1-R4 untouched and **still open, correct as
  filed, and unstarted** — the venue is refuted, not the plan, for the sixth time. What makes this
  fire different from the five before it is that **every known defect in the park interlock was
  already fixed and on trunk, and the park itself was landed and visible** — so the recurrence can
  no longer be explained by any of them. Timeline, all UTC: `d877dc7e` *"the park interlock reads a
  ref the dispatcher never fetches"* lands **09-01T06:43:13**, putting an explicit `refresh_trunk`
  in front of the cloud claim gate (`cc-dispatch:2593-2614`); `1cdd601f` lands the fifth fire's park
  **09-02T00:59:01**; `9a17fea6` lands the `REAP_ACTORS` fix **09-02T06:02:15**; the desk lands
  trunk HEAD `f56ea619` **09-02T08:09:58**; this fire is composed **09-02T08:20:30**.
  **(1) Candidate (a) — a stale `orc.ref` — is REFUTED.** This was 09-02's leading hypothesis
  (*"a park landed ~23 h before this fire is invisible to a ref not fetched since"*). Measured:
  `git merge-base --is-ancestor 1cdd601f origin/main` is true, and `f56ea619` was landed **10 m 32 s**
  before this fire, so `origin/main` in the desk's checkout demonstrably held the park at claim time —
  and `d877dc7e` had already made that refresh explicit a day earlier.
  **(2) Candidate (c) — an automaton retiring the park — is REFUTED for this row**, by reading all
  three reap writers rather than by supposing. The cure sweep's `unblock` (`cc-backlog:6167`) selects
  only blocks with `.by == "cc-backlog-reap"` *and* a `needs` matching three reap-authored sentences;
  a step-8 park block has neither (`cloud-return.sh:644` calls `block` with **no** `--by`, carrying
  the park's operator step). The two `reopen` sites (`:5954`, `:6049`) live in the stale-*claim* loop
  and cannot select a `blocked` row. So once step 8 writes the block, nothing re-opens it. 🚨 One
  thing worth recording because it is **not** what `9a17fea6` closed: a step-8 block is desk-keyed
  and necessarily stamped *after* the park it answers, so it retires the park by timestamp the
  instant it is written — `park_assess` reads `honoured` from the park's own consequence. That is
  harmless *only* because no reap path re-opens a desk-blocked row; it is one selector away from a
  permanent leak, and the retraction rule's ground (*"block because the row is then outside
  cc-dispatch's fire predicate anyway"*) is an assumption about other code, not a property of the arm.
  **(3) 🚨 Candidate (b) SURVIVES and is now the only one left: a fire composed without passing
  `cc-backlog claim --venue cloud`.** Established structurally — the park arm has exactly **one**
  caller (`cc-eligible:17`, `:497`), reached only from `cc-dispatch:2593` and only when `venue=cloud`
  (which needs `venuePlan=cloud` **and** `CC_FIRE_CLOUD=on`); and `bin/cc-offload`, the actuator that
  actually creates the session, contains **no** reference to `cc-eligible`, no claim, and no park
  read. Any path reaching the actuator without the claim is unguarded by construction, and no further
  work on the predicate can see it.
  **(4) The one check that decides it is the DESK's, because a VM cannot run it.** `cc-dispatch`
  journals its own decision per id — `idl claimed … venue=cloud` (`:2747`), `idl skipped …
  cloud-ineligible` (`:2685`), `idl note … gate=trunk-unrefreshed` (`:2613`). Whether **any** such
  record exists for `8f59467c92b0` at ~`2026-09-02T08:20Z` settles (b) outright: a record means the
  gate ran and admitted, and the question is which arm; **no** record means this fire never passed the
  gate, and the fix belongs at the actuator rather than in the predicate.
  **(5) 🚨 The refusal ground the 09-01 and 09-02 entries cited is RETRACTED.** Both declined to
  touch `bin/cc-eligible` on `bin/cc-venue`'s guard. That reading does not survive: the guard keys on
  the **effect** — *"a cloud label may only be written from a certification, and a shallow clone
  cannot certify"* — which governs `cc-venue --apply` **writing** a cloud label, not editing the
  predicate's source; and `9a17fea6` is a landed counter-example, a cloud VM changing
  `bin/cc-eligible` with 274 tests green, on trunk 2 h 18 m before this fire. Same shape as 09-01's
  retraction of the tooling ground — a refusal that survived re-citation because nobody re-ran the
  probe. The honest ground is narrower and is about the finding, not about permission: the surviving
  candidate says the predicate may not be consulted at all, so another change to it is the shape of a
  correct analysis that lands and moves nothing. Fire 5's `_park_doc` shallow fail-open
  (`cc-eligible:943`) stays **open** for the same reason — real, but the admitting gate runs on the
  desk's full clone, so it cannot be what fired this dispatch.
  **Disposition: PARKED via a third entry in `docs/parks/8f59467c92b0.md`** — same `needs:` as 09-01
  and 09-02, deliberately unchanged so the desk sees one consistent instruction. The entry names
  **this** branch, so `cloud-return.sh` step 8 calls `block` instead of falling through to
  `cc-backlog done`.
- **2026-09-02 — FIFTH fire, the first one AFTER a park was on trunk, so the park's efficacy is now
  MEASURED rather than hoped for: it did not hold.** `8f59467c92b0` reached a fifth cloud VM of the
  identical shape (`$HOME` `/root`, `~/Development` absent, `/home/user` holding
  `claude-infrastructure` alone, clone 50 commits with `.git/shallow` present, `HEAD..origin/main`
  = 0). R1-R4 untouched and **still open, correct as filed, and unstarted** — the venue is refuted,
  not the plan, for the fifth time. Four things this fire measured that 09-01 could not:
  **(1) The park file and the arm are both CORRECT, and the failure is UPSTREAM of the arm.** Run
  end-to-end here against the shipped predicate — a certified repo holding this exact park, a store
  carrying this row with no `block`/`unblock` — `bin/cc-eligible check 8f59467c92b0` returns
  `ineligible-parked` at **rc 3** and names the `needs:` line verbatim. So 09-01's channel is not
  the thing that broke; something ahead of `cc-backlog claim --venue cloud` is.
  **(2) 🚨 The 09-01 park was INERT FOR THIS DISPATCH BY CONSTRUCTION, and would have settled the
  row as `done`.** `cloud-return.sh` step 8 honours the last entry only when its `branch:` names the
  branch it is returning (`scripts/cloud-park.sh` header, *"a stale entry is inert by construction
  rather than by cleanup"*). The 09-01 entry names `claude/fire-20260901T012151Z-85215-1`, so on
  this dispatch's return step 8 finds no entry for its branch and **falls through to
  `cc-backlog done`** — marking finished a row whose four waves are unstarted. That is a worse
  outcome than the re-fire it was meant to stop, and it is a property of every re-fire of an
  already-parked row, not of this one. This fire appended its own entry
  (`## 2026-09-02T00:57:23Z`, branch `claude/fire-20260902T005055Z-82369-1`); re-measured after the
  append, the arm reads the NEW last entry and still refuses.
  **(3) NEW DEFECT, measured: the park arm fails OPEN on every shallow clone, for a certification it
  does not use.** `_park_doc()` (`bin/cc-eligible:899`) returns `None` whenever
  `orc.certify() != "ok"` — it shares the HISTORY oracle's certification, and `certify()`
  (`:708-711`) returns `shallow` on a grafted clone. But reading a park needs no horizon at all:
  `git show <ref>:docs/parks/<id>.md` resolves perfectly on a shallow clone, as this session did to
  read the 09-01 entry before writing anything. Measured by varying only `CC_ELIGIBLE_REPO` over one
  store and one park: this VM's shallow checkout → `park=not-measured`, verdict `eligible`, rc 0; a
  full repo holding only that park file → `ineligible-parked`, rc 3. The comment at `_park_doc`
  ("one certification, shared with the history arm") is the whole cause — the two arms need
  different certifications, and the park arm inherited the stricter one.
  **(4) Whether (3) is what let THIS fire through is NOT measurable from here, and is not claimed.**
  The claim-time gate runs on the operator's box, where the checkout is full and `certify()` is
  `ok`. Two candidates only the desk can check: **(a)** `_park_doc` reads `orc.ref`, i.e.
  `origin/main` **in `~/Development/claude-infrastructure`**, which is only as fresh as that
  checkout's last fetch — a park landed ~23 h before this fire is invisible to a ref not fetched
  since; **(b)** a dispatch path that never passes `cc-backlog claim --venue cloud`, which is the
  arm's only caller.
  **Disposition: PARKED via a second entry in `docs/parks/8f59467c92b0.md`** — same `needs:` as
  09-01, deliberately unchanged so the desk sees one consistent instruction. Not fixed here on the
  one ground 09-01 also cited: `bin/cc-venue`'s guard forbids a cloud VM building or running the
  venue rule (its 50-commit clone cannot read the history justifying the arms), and
  `bin/cc-eligible` is that rule — and the fix in (3) is a change to which items that rule refuses.
  09-01's retraction of the tooling ground stands and is not re-litigated.
- **2026-09-01 — FOURTH fire, and this one is PARKED rather than written down.** `8f59467c92b0`
  reached a fourth cloud VM of the identical shape (`$HOME` `/root`, `~/Development` absent,
  `/home/user` holding `claude-infrastructure` alone, clone 50 commits with `.git/shallow` present,
  `HEAD..origin/main` = 0). R1-R4 untouched and **still open, correct as filed, and unstarted** —
  the venue is refuted, not the plan, for the fourth time. What is new is not another measurement of
  the recurrence but that the channel to stop it now exists and had never been used:
  **(1) `scripts/cloud-park.sh` is on trunk and `docs/parks/` carried no entry for this id.** It is
  a cloud worker's only way to park its own row: the VM lands `docs/parks/<id>.md`, `bin/cc-eligible`
  reads it at `cc-backlog claim --venue cloud` and returns `ineligible-parked`, and
  `cloud-return.sh` step 8 turns it into the ledger `block`. The 08-15, 08-17 and 08-29 dispositions
  were prose plus `cc-backlog block` — and re-measured here, `block` returns **rc 3** (`unknown id`,
  writes nothing) and `cc-notify --role desk` returns `enqueued=0 reason=role-unset`, because
  `~/.claude/autonomy/` does not exist on a VM. That is why three dispositions bought nothing and
  this one is a landed file instead. *(Corrects §9.5's `rc 0` reading, per `cloud-park.sh`'s own
  header erratum.)* The park is landed at the sha this entry ships in.
  **(2) 🚨 §9.4's ~0-cost `projectName` stopgap DOES NOT HOLD — it self-erases, and on this very
  plan.** `hooks/plan-index-update.sh:154` writes `.projectName = $projectName` **unconditionally**
  into `~/.claude/plans-index.json` on every PostToolUse edit of any `*/docs/plans/*.md`, from the
  purely path-derived `classify_path()` basename, with no `// (.projectName)` preservation of an
  existing value. So a hand-set foreign `projectName` survives only until the next edit of this plan
  file — which is the status-log append every one of these fires makes, including this one. The
  stopgap would have been erased by the act of recording it.
  **(3) And it was never needed for this id.** `cc-backlog`'s `--condition` keying hashes
  project+condition and drops title and source (`bin/cc-backlog:335`); the plain event key is
  project+title+source (`:961`). Under either, nothing this fire writes re-keys the row, so the
  landed park governs the id that actually fires. `projectName` governs only what `cc-discover`
  mints *next* — and per (2) it cannot durably govern even that.
  **Disposition: PARKED via `docs/parks/8f59467c92b0.md`, not `reopen`** — blocked on where it is
  sent. The operator-only step on the record is *re-file R1-R4 as per-repo plans inside the
  `reso-management-app` and `doc_classifier` trees*; no claude-infrastructure worker, cloud or local,
  can reach those two checkouts under the dedicated-worktree rail. Not fixed here on ONE ground:
  `bin/cc-venue:55` forbids a cloud VM from building or running the venue rule, and `bin/cc-eligible`
  is that rule.
  **(4) 🚨 And the SECOND ground every prior fire cited is RETRACTED.** §6 and §9.6 both recorded
  *"`bats`, `shellcheck` and `shfmt` are all ABSENT"* as a co-equal reason the predicate could not be
  changed. Both probed with `command -v` — *is it installed* — and neither asked *can it be
  installed*. Measured here: `apt-get install -y --no-install-recommends shellcheck bats shfmt`
  succeeds in seconds and all three resolve under `/usr/bin`. The tooling was never a refusal ground
  at any of the four fires; it is the "negative tool-claim inferred from one failed call" the global
  memory-hygiene rule names, and it survived three re-measurements because each re-ran the same
  insufficient probe. The decision does not reopen — `cc-venue:55` is sufficient alone — but future
  fires should cite the guard and stop citing the tooling. Corollary, hit by this land: the gate's
  `.bats` shellcheck ratchet exits **9 GATE-KILLED** when `shellcheck` is missing, so on a cloud VM
  a *markdown-only* diff is unlandable until one `apt-get` runs.
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
  both failed silently and this row fired a third time.
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
