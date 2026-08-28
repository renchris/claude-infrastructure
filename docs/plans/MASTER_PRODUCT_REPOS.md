---
status: open
targets: reso-management-app, doc_classifier
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
- **2026-08-28 — the 08-27 fix is CORRECT and still did not land; the blocker is one `gate_red` that
  should be an `arm_nonverdict`, at `scripts/ship-land.sh:3201`.**
  `8f59467c92b0` fired again, one day later, into the same VM shape (`$HOME=/root`, the checkout at
  `/home/user/claude-infrastructure`, no `~/Development`, no `~/.claude/autonomy`). R1-R4 remain
  unreachable and unstarted; nothing in the plan is refuted, only the venue — for the Nth time.
  This entry adds two things the 08-27 entry could not.
  **(1) The stranding is ACCELERATING, and the 08-27 commit is itself now stranded.** Re-measured
  today by patch-id (`git cherry`, which survives `ship-land`'s rebase): of the **181** fire
  branches dated ≥ 08-24, **180 still carry content absent from trunk** — against 131 of 133
  measured yesterday. That is ~48 further branches stranded in a single day. Trunk's copy of this
  file still ends at the 08-17 entry, so the 08-27 arm never reached it either.
  **(2) The cure is verified, and the ONLY thing between it and trunk is one arm that cannot render
  a verdict on this platform.** The 08-27 subject-foreign arm was cherry-picked here and
  re-verified independently, not taken on trust: **68/68 green** across all four `cc-eligible`
  suites with 0 failures; red-proofed against trunk's `bin/cc-eligible`, where the new suite goes
  **5 ok / 5 not ok**, failing exactly tests 1, 2, 4, 8, 9 as claimed; and end-to-end on the REAL
  plan file in a Mac-shaped `$HOME`, `8f59467c92b0` → `verdict=ineligible-foreign-tree`, **exit 3**,
  naming both trees, while the live control (`AUTONOMY_DISPATCH_V2.md`, which *mentions*
  `reso-management-app` once but declares nothing) stays `eligible`, exit 0.
  `scripts/ship-land.sh --dry-run` nonetheless exits **6 (GATE RED)**. Every other arm is clean —
  statics, all nine ratchets, and `unattended-path` own-scope on the 2 files this diff touches. The
  single red is `unattended-path-lint --selftest`, **11 of 42**, which reproduces identically on
  clean `origin/main` in a throwaway worktree with this commit absent. It is environmental: the
  lint measures the live box's Mac toolchain, and this Linux VM lacks `gtimeout`/`taskpolicy`/
  `osascript`/`plutil`/`gh`/`shellcheck`/`tmux`, so 8 fixtures resolve nothing (`want 1, got 0`)
  and 3 `EMBEDDED_ALLOWLIST` staleness checks invert (`want 0, got 1`).
  🚨 **Where the fix belongs — and why it is a DECISION, not a patch.** `ship-land.sh:3198-3202`
  answers a failing selftest with `gate_red unattended-path-selftest`. But this file already
  distinguishes the two cases and has vocabulary for the other one: `arm_nonverdict` (used at
  `:3192` and `:3205` for precisely "this arm could not produce a trustworthy verdict"), against
  `GATE_RED` for "a check produced a REAL verdict and it was red" (`:268-274`). A detector that was
  never able to discriminate **on this platform** has not regressed — it has produced a
  non-verdict, and the gate is currently classifying it as a red. Making the selftest report *why*
  it failed, so the gate can tell platform-inapplicability from a genuine regression, is the fix.
  **Not done here, deliberately:** it changes when a security gate blocks, its safety argument
  rests on the Mac passing all 42 (true by inference from every landed commit, but not measurable
  from this VM), and misclassifying even one of the 11 cases would blind a real check on the
  operator's own box. Do **not** follow the lint's printed fix — deleting the stale
  `EMBEDDED_ALLOWLIST` lines would remove protections the Mac needs (confirms `46db2550`, itself
  stranded). No sanctioned bypass exists and none was sought: `SHIP_LAND_UNATTENDED_LINT`
  substitutes the lint and `SHIP_LAND_UNATTENDED_OWN_SCOPE` only widens scope; the selftest runs
  unconditionally ahead of `own_run`. **This is the ⛔ for the desk: one platform-policy call that
  unblocks 180 stranded branches, not this row alone.**
- **2026-08-27 — the disproofs were never the problem; they never LANDED. Fixed by landing the arm.**
  `8f59467c92b0` fired into the same VM shape again (one checkout, no `~/Development`, no
  `~/.claude/autonomy`), so R1-R4 are unreachable and the premise is refuted at this venue for the
  Nth time. What is new is **why the previous N disproofs bought nothing**, measured BY CONTENT
  rather than by ancestry (the cloud clone is shallow — `git rev-list --count origin/main` = 50 —
  so `merge-base --is-ancestor` reports STRANDED for commits that are demonstrably on trunk, and
  every count in this entry is a content check instead):
  **(1)** trunk's copy of THIS FILE carries status entries for `2026-08-12`, `08-15`, `08-17` and
  nothing later, while disproof commits dated 08-24, 08-26 (×3) and 08-27 (×2) exist on
  `origin/claude/fire-*` branches. Measured with `git cherry` (**patch-ids, which survive the
  rebase `ship-land` performs** — an ancestry test would mis-read every rebase-landed branch as
  stranded, and did: it gave "2 of 207 merged", which is not the same claim): of the **133** fire
  branches dated 08-24 → 08-27, **131 still carry patches whose content is not on trunk.** Each
  cloud worker wrote its finding, committed it, pushed it to its own fire branch, and closed; the
  branch was never landed, so trunk never learned, so the next worker read a plan frozen at 08-17
  and rediscovered the same fact. The doc channel is not inert because docs do not work — it is
  inert because **a fire branch is not a landing**.
  **(2)** 🚨 **The `feat(cc-eligible)` subject-foreign arm (73a2b1f8, 08-24) is one of those
  strandings, and it is the exact fix this row needed.** Trunk's `cross_repo()` is healthy and
  passes this row by construction — the row's project label IS `claude-infrastructure` and is
  ACCURATE, since `find-plan.sh:70` derives it from the plan file's path. Only a `targets:`
  frontmatter declaration can express a master whose work is in two other trees.
  **Landed in this commit**, with the one-line `targets: reso-management-app, doc_classifier`
  declaration that arms it. Gate: **68/68 green** (58 sibling cc-eligible tests unchanged + 10 new),
  red-proofed against trunk's `bin/cc-eligible` — tests 1, 2, 4, 8, 9 FAIL without the arm, which
  matches 73a2b1f8's own claim. This row is now cloud-INELIGIBLE by measurement, not by prose.
  **(3)** Correction to `802ad21e` ("the return rails are rc-0 no-ops"): **they are not.**
  `cc-backlog done|block|reopen 8f59467c92b0` each exit **3** with `unknown id`, and
  `cc-notify --role desk` exits **3** with `reason=role-unset`. The rails are loud and honest. The
  rc-0 reading is the `$?`-after-`head` artifact this repo has already named twice (`c0fa70e5`,
  `739bc469`) — reproduced here by accident, then re-measured without the pipe. The real defect is
  narrower and unfixable from the VM: `cc-backlog list --all --json` returns `[]` because the store
  does not exist off-box, so **no transition of this item can be recorded from cloud at all** —
  the `done`/`block` instruction in the dispatch brief is unexecutable at the venue it is sent to.
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
