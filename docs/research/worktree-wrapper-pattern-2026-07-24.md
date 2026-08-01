# The per-instance worktree wrapper — provenance, mechanism, and whether it extends here

**Date:** 2026-07-24 · **Type:** read-only investigation + verdict · **Repos:** `reso-management-app` (source), `claude-infrastructure` (candidate)

> ⚠️ **READ §6 AND §7 BEFORE ACTING. Net verdict: ADOPT — i.e. the answer below STANDS.**
> §6 (2026-07-31) reversed this to "do not adopt"; §7 (same day) found §6 wrong on two of its three
> legs — its "zero recorded failures" null came from an instrument blind to the actual failure, and
> its "we tried it and reverted it" commits reverted the *hook-deny alternative*, not worktree
> isolation. §6's re-measured FIGURES are still the current ones and are worth reading; its
> conclusion is not. §4's cost analysis also has one sign error, corrected in §7.3: editing in the
> shared root does not merely risk a sweep, it **structurally blocks the deploy lane**.

**Answer up front:** Yes — extend it, but *not* by porting reso's bespoke scripts. The
generalized extraction already exists and is already installed (`worktree-harness`, Homebrew).
claude-infrastructure has independently re-derived reso's exact failure three times and patched
it point-wise each time; the structural fix is a `.harnessrc` + one launcher-routing change.
Two things must ship with it (a GC, and a deploy step for the `~/.claude` symlink layer), and
one exemption must be decided by the operator (the desk session).

---

## 1. WHY it exists — the requirement and the failure it replaced

Verbatim scope, from `reso-management-app/docs/plans/CC_PARALLEL_SESSIONS_SIMPLE_PLAN.md`:

> Open NUMEROUS Claude Code sessions in iTerm2, launched from the `reso-management-app`
> folder, where each session: (a) **always starts off the latest main**, (b) keeps its
> **unstaged/staged/commit work fully separate** from the other sessions, (c) **never blocks
> main from being committed to**. As simple as that.

What it replaced was a **policy** stack — a writer-lock daemon (`reso-writer-lock.py`) plus a
`concurrent-writer-guard.sh` PreToolUse guard. That stack had two live regressions
(`CC_WORKTREE_DX_STREAMLINE_DISCOVERY.md`): a session-long lock held for hours that only a
manual `kill -TERM` cleared, and a stale base (new worktrees branched off a diverging local
`main`). The verdict was to delete the lock/guard rather than fix them:

> The writer-lock and guard defend an invariant git already enforces per-worktree, and are
> already no-ops inside every worktree — so they are deleted, and the launcher always isolates.

The design meets a/b/c **structurally, not by policy**: `git worktree add … main` resolves the
`main` ref at creation (a); each linked worktree owns a physically distinct `index`/`HEAD`/reflog
so one session's `git add -A` *cannot* reach another's staged work (b); no session works on
`main` directly, and concurrent ff merge-backs serialize at git's microsecond ref-lock (c).

## 2. FROM WHERE — provenance

| Artifact | What it is |
|---|---|
| `docs/research/CC_WORKTREE_DX_STREAMLINE_DISCOVERY.md` (2026-06-02) | Discovery, workflow `wf_38e0551a-63e`, 14 agents / 1.31M subagent tokens. Threat model + options matrix. Its *recommendation* was superseded the next day. |
| `docs/plans/CC_WORKTREE_DX_STREAMLINE_PLAN.md` | The superseded design (op-scope + ancestry + carry-forward + root-off-main). |
| `docs/plans/CC_PARALLEL_SESSIONS_SIMPLE_PLAN.md` (2026-06-03) | **The one that shipped.** Workflow `wf_6be47c37-d90`, 11 agents (8 build axes + 2 opus red-teams + synth), 888K tokens, 10/10 converged with no dissent. Status DONE; claude-infra commit `fdf0bda` removed the vestigial lock/guard. |
| `~/Development/worktree-harness` | The **generalized public extraction** — MIT, on Homebrew, `worktree-harness` already on `$PATH`. `lib/cmd_launch.sh` header says it verbatim: *"the always-isolate launcher. Generalizes reso's `_cc_route_check` + `claude()` wrapper."* |

The narrowing from the 1.31M-token discovery to the shipped one-paragraph design is the notable
part: the second workflow converged on *deleting* the machinery the first one proposed to fix.

## 3. HOW it works — the mechanism

**The wrapper is a zsh shell-function layer in `~/.zshrc`, not a Claude Code feature.**

`_cc_route_check()` (`~/.zshrc:106-131`) is the shared routing gate. It echoes a worktree PATH on
stdout when the caller should launch there, echoes nothing when it should launch in place, and
returns non-zero only when isolation was *required but failed*:

```
CLAUDE_ISOLATION_SKIP=1        → return 0 (escape hatch)
not a git repo                 → return 0 (launch in place)
.git is a FILE (linked wt)     → return 0 (already isolated, never nest)
.git is a DIR && basename == "reso-management-app"   → ISOLATE       ← the gate
```

The gate is a **hardcoded basename comparison** (`:112`). That single line is why the pattern is
reso-only today.

Branch name: `cc-$(date +%H%M%S)-$$` (`:113`) — the shell PID makes it collision-free per pane,
which is what produces the `wt-cc-HHMMSS-PID` worktrees under `~/Development/.worktrees/`.

Provisioning is tiered: warm pool claim → `$HOME/.reso/bin` installed copy → cold
`new-worktree.sh` → give up (`:117-127`).

Three launchers (`claude()` `:133`, `claude-default()` `:151`, `claude-next()` `:368`, plus the
pinned-stable variant `:580`) all consume it identically and **refuse to launch un-isolated on
root** if isolation failed. Each carries a **resume guard**: `--continue/--resume/-c/-r` never
spawn a fresh worktree, because the new worktree's project dir is empty so resume would find
nothing. A separate `ccr` picker (`:446-530`) exists solely because always-isolate scatters
sessions across per-worktree project dirs and no single launch point can see them all.

**Supporting scripts** (`reso-management-app/scripts/`, 1059 LOC total):

- `worktree-pool.sh` (277) — 10 pre-built warm slots at `wt-pool-N` on `pool/slot-N`. Exists
  because a cold reso spawn costs ~20-30s (worktree add + pnpm hardlink install + codegen +
  supply-chain verify) plus ~8s DB seed; a claim costs <1s. `git worktree add` happens *only*
  inside `ensure`, serialized by a global mutex — deliberately keeping the historical parallel
  `worktree add` races (GH #34645/#48927) off the hot path.
- `worktree-gc.sh` (422) — 5-gate conservative reaper (clean tree, merged, no `.teammate-busy`,
  no live process, idle >30 min). Dry-run by default; **branches always preserved**.
- `new-worktree.sh` (100) — cold path. `merge-to-main.sh` — the ff-only merge-back with a
  `merge-base --is-ancestor` assert + typecheck gate.

---

## 4. SHOULD claude-infrastructure adopt it

> ⚠️ **This section's CONCLUSION (adopt) stands — but its numbers are stale and one cost is
> mis-signed.** §6.1 tabulates how each 2026-07-24 figure moved (use §6's numbers, not these);
> §7.3 corrects the "instant-live edit loop" cost — losing it is a BENEFIT, not a price, because
> editing in root is what blocks `deploy-live`'s ff-merge. Read §6 and §7 before acting.

### The pattern is already here — unmanaged

`git worktree list` in claude-infrastructure returns **50 worktrees across three different
location conventions** (`/tmp/wt-*`, `~/Development/.worktrees/*`, `~/Development/wt-*`), **11 of
them `prunable`** (directory gone, metadata stranded), against **244 branches**. There is no GC,
no naming convention, and no launcher enforcement. So this is not "adopt worktrees or not" — it
is "manage the worktrees we already create ad-hoc, or keep not managing them."

### The evidence that policy-only isolation is failing here

claude-infrastructure's `.claude/CLAUDE.md` carries the rule *"Never commit or land in the shared
checkout"* — the same **policy** shape reso deleted in favour of structure. It is not holding:

| Signal | Measurement |
|---|---|
| Commit volume | **430 commits in 14 days** — comparable to reso, i.e. genuinely high-volume |
| Concurrent sessions in the shared checkout | **6 live sessions** with `cwd = ~/Development/claude-infrastructure`, sharing one git index |
| Direct commits to the shared checkout | **33 commit events in the last 60 reflog entries**; 2026-07-21 shows an entire session's ~15 commits landing straight onto `main` there, plus a rebase |
| Known data loss | Incident 2026-07-11 — `dfacccd` (limit-recover skill, 5 new files) silently dropped by a sibling `/ship` of `feat/two-way-session-comms`; `rev-list origin/main..HEAD` read 0 ("looks landed") while the files were absent from main |
| The failure already recurred | `bin/cc-wave-plan:267`: *"Workers used to fire co-cwd with the desk in the SHARED checkout, so a wave of them fought over one git index and land-conflicted (rebase exit 5)."* |
| The system is already fighting it | `scripts/ship-land.sh` has a dedicated **shared-checkout refusal** in its fail-closed envelope |

Three independent point-fixes for one root cause (the `.claude/CLAUDE.md` rule, the
cc-wave-plan per-item `--cwd`, the ship-land refusal) is the
`desk-whack-a-mole-means-file-systemic-fix` pattern verbatim: repeated manual reconciliation of
the same class *is* the signal to build the structural fix.

### What is genuinely different here, and what it changes

**Cost inverts — adoption is cheaper here than in reso.** claude-infrastructure is 18 MB / 475
tracked files with **no `node_modules`, no install, no codegen, no DB seed**. A cold worktree is
~1 s. The 277-LOC warm pool that reso *needs* is **not needed here for cost**. (It has a
different value here: `cc-wave-plan:267` notes that because no pool exists,
`handoff-fire --worktree` provisions cold, and a cold worktree fire races CC boot for the
auto-submit keystroke — the `cold-worktree-fire-autosubmit-race` failure. A pool would dissolve
that, but it is an optimization, not a prerequisite.)

**The one real cost: this repo is its own deploy surface.** `~/.claude/` is ~195 per-file
symlinks into this checkout (`~/.claude/hooks/*.sh` → `.../claude-infrastructure/hooks/*.sh`).
Editing in the shared checkout is *instantly live machine-wide*; editing in a worktree is not
live until landed **and** ff-synced **and**, for brand-new files, symlinked. Always-isolate makes
the already-filed `deploy-lag-checkout-behind-origin` pain **universal** rather than incidental.
Worth noting the flip side: instant-live also means a half-finished or broken hook edit in the
shared checkout breaks every running session immediately — isolation removes that blast radius.
This trade is real and must be paired with an explicit deploy step, not hand-waved.

**The desk is the one genuine exemption question.** `scripts/desk-land.sh:15` states the
invariant: *"The desk session lives in the SHARED checkout … on `main`, but its landable work is
committed in WORKTREES on session branches."* The entire 3-option analysis in that file's header
exists because the desk's shared-checkout cwd makes the hook-allowed push shape unreachable
(`desk-cannot-self-land-cwd`). So the desk's position in the shared checkout is a **liability it
already works around**, not a requirement — always-isolate would incidentally dissolve
`desk-cannot-self-land-cwd`. But five call sites hardcode `$HOME/Development/claude-infrastructure`
as the shared checkout — `hooks/operator-readout.sh:62`, `scripts/ship-land.sh:303`,
`scripts/desk-land.sh:15,61`, `scripts/desk-invariant.sh:68`, `bin/cc-dispatch:93` — every one of
them env-overridable (`CC_SHARED_CHECKOUT`, `SHIP_LAND_SHARED_CHECKOUT`,
`DESK_INVARIANT_CANNED_CWD`, `CC_DISPATCH_REPO`), so the coupling is configurable rather than
structural. **This is the operator's call, not an auto-continue.**

### Recommended shape

1. **Use `worktree-harness`, do not port reso's scripts.** It is the sanctioned generalization of
   this exact wrapper, already installed. Same auto-branch format (`<prefix>-<HHMMSS>-<pid>`),
   same never-nest rule, same refuse-on-failure with `WH_ISOLATION_SKIP=1` override. Config is a
   sourced `.harnessrc` (`HARNESS_BASE_POLICY=origin`, `HARNESS_INSTALL=none`,
   `HARNESS_MERGE_GATE="<shellcheck+bats>"`, `HARNESS_GC_KEEP=(…)`).
2. **Replace the hardcoded basename gate with repo opt-in.** `~/.zshrc:112` currently reads
   `basename == "reso-management-app"`. Make it "isolate if the repo has a `.harnessrc`" — that
   fixes reso and claude-infrastructure with one line and stops the gate needing an edit per repo.
3. **Ship the GC in the same change.** 50 worktrees / 11 prunable / 244 branches is what
   adoption-without-GC looks like; reso's equivalent is a 422-LOC 5-gate reaper for a reason.
   `worktree-harness gc --prune` covers it (branches preserved).
4. **Ship a deploy step in the same change.** Land → ff-sync the shared checkout → link any
   brand-new tracked file into `~/.claude/`. Without it, always-isolate converts an occasional
   deploy-lag into the default state.
5. ~~**Operator decision required:** does the desk keep its shared-checkout cwd?~~ **RESOLVED
   2026-07-25 — exempt the desk. See §5 below for the derivation.**

### What would argue against

Honest counterweights, none of which I judge decisive: the pattern's benefit scales with
*concurrent writers*, and a single-session day in this repo pays worktree overhead for nothing
(this is exactly what the global CLAUDE.md "CONDITIONAL, not always" rule protects) — but 6
concurrent sessions in the shared checkout today says that is not the regime we are in. And the
symlink-liveness change is a real workflow cost that must be absorbed by (4), not ignored.

---

## 5. The desk question — resolved (2026-07-25)

**Verdict: exempt the desk. The exemption is narrow, cheap, and reversible, and it does not block
adoption of anything else.** Two of the three candidate objections turned out to be false; the
third is real, specific, and load-bearing.

### 5.1 The reaper objection — FALSE, already mitigated

Hypothesis: an isolated desk sitting in a worktree would be mis-classified and reaped, since
`bin/cc-classify:185` decides teammate-hood by **cwd shape alone** —
`is_worktree_session()` matches `/tmp/wt-*`, `/private/tmp/wt-*`, `*/.worktrees/*`,
`/tmp/worktree-*`, all of which an isolated desk would live under.

It does not hold, for two independent reasons:

- **Ordering.** Desk-role never-reap fires at step 4.6 (`cc-classify:390`, *"the desk-role file
  resolves to this session — desk-role (never-reap)"*), which is checked **before** the
  finished-teammate branch at `:419`.
- **The 2026-07-24 fix.** That branch now requires `is_worktree_session "$cwd" && fired_peer
  "$pane"` — the spawner's own stamp. Its comment records exactly this bug being fixed: *"The cwd
  path alone is NOT teammate evidence (2026-07-24: an operator conversing inside a wt-pool
  worktree was reaped as finished-teammate 14 min after their prompt)."*

The desk's identity is a **file**, not a path — `~/.claude/cc-roles/desk` holds a pane UUID, and
`bin/desk-register` is explicit that every role-addressed consumer follows it. Isolation cannot
move that. **Not a blocker.**

### 5.2 The hardcoded-path objection — WEAK

All five shared-checkout call sites are env-overridable (`CC_SHARED_CHECKOUT`,
`SHIP_LAND_SHARED_CHECKOUT`, `DESK_INVARIANT_CANNED_CWD`, `CC_DISPATCH_REPO`). Configuration, not
structure. **Not a blocker.**

### 5.3 The real blocker — six pieces of desk state are cwd-keyed

`hooks/waiting-recycle.sh:160-176` keys six sentinels on `hash(config_dir | cwd)` via `key_cwd()`:
`arm`, `cooldown`, `live`, `brief`, `disarm`, `busyforce`. **The code states the premise it
depends on, in a comment, at `:161`:**

> Per-cwd key (arm + cooldown survive a recycle **since cwd is stable across it**)

**Per-instance isolation falsifies that stated premise.** Every recycle mints a fresh worktree →
a fresh cwd → all six sentinels revert to default, permanently and silently, with no way to
durably re-arm (you would have to re-run `arm --live` after every single recycle).

Verified empirically — sentinel probe across both config dirs:

| cwd | `live` | `arm` |
|---|---|---|
| `~/Development/claude-infrastructure` (shared) | **YES** | **YES** |
| `/tmp/wt-worktree-pattern` (a worktree) | no | no |

What each loss costs:

- **`live`** is the switch between *actually firing* the deterministic self-handoff and
  **SHADOW / log-only** (`:169`). An isolated desk would silently degrade to shadow on every
  recycle — it would log that it *would* have fired, forever, and never fire. This is precisely
  the silent fail-closed class this repo keeps getting bitten by (cf.
  `deploy-lag-checkout-behind-origin`, where an autofiring poller nearly shipped dead).
- **`cooldown`** is the documented **cross-session loop-breaker** (`:49`: *"a fresh recycled desk
  (same cwd) sees the predecessor's cooldown"*). Losing it per recycle admits recycle thrash.
- **`brief`** is the standing successor-brief; **`disarm`** the per-desk opt-out; **`busyforce`**
  the Tier-3 forced-recycle opt-in.

Fragmentation is already observable rather than theoretical: **28 distinct `arm`/`live`/`brief`
sentinel triples** exist in `state/waiting-recycle`, one set per cwd that has ever been armed.

### 5.4 The condition that would flip this verdict

Re-key those six sentinels onto the **role file** instead of cwd. The code already knows this is
the better anchor — `:322` observes that `COORD` is a fixed path so arm-by-default keys on the
role *"regardless of which config dir the desk migrates to (**unlike the (cfg,cwd) arm
sentinel**)"*. It is a contained change: six `*_for()` helpers plus a migration for existing
sentinels. **After that, the desk can isolate like everything else and the exemption retires.**
Until then, exempting it is the correct call — not a concession.

### 5.5 Why the exemption costs almost nothing

Exactly **one** session needs it: the role-holder. A live registry tally shows **6 live sessions
in the shared checkout**, and the desk-role pane is **not among them**. The other five are
ordinary sessions that carry all the index-contention risk and should isolate. So the exemption
carves out one session and leaves the entire benefit of the change intact.

### 5.6 Finding discovered en route — there is no live desk, and has not been for ~41 hours

Not part of the worktree question, but it surfaced from the same registry reads and is
operator-facing:

- `~/.claude/cc-roles/desk` points at pane `D08B4FC0-…`, written **2026-07-20**.
- That pane has **no registry row** and no live process.
- `com.claude.desk-invariant` **is** loaded in launchd (exit 0), and is correctly detecting this:
  **499 `no live desk process resolves…` abstention records**, spanning
  **2026-07-23T07:35Z → 2026-07-25T00:15Z (continuous, still firing)**.
- Its replacement path is failing, not succeeding: `handoff-fire returned nonzero;
  no-registry-row pane=D08B4FC0-…`.

So the desk-existence invariant — the organ whose whole purpose is that nothing else can *create*
a desk — has been in a failing respawn loop for ~41 hours. This wants its own investigation.

---

## 6. RE-MEASURED 2026-07-31 — the §4 verdict is REVERSED

> ⚠️ **§6 IS ITSELF SUPERSEDED — see §7 (same day).** Two of the three legs below do not hold: the
> "zero recorded failures" null came from an instrument structurally blind to the failure, and the
> "we tried it and reverted it" commits reverted the *hook-deny alternative*, not worktree isolation.
> **The correct verdict is §4's: ADOPT.** §6's measurements stand; its conclusion does not.

**Answer up front: do NOT adopt always-isolate in claude-infrastructure.** §4 above recommended
adoption. That recommendation rested on measurements taken 2026-07-24 which have since decayed, and
on an incident attribution that does not survive checking. The concurrency premise is *confirmed*;
the *harm* premise is not. This section supersedes §4's "Recommended shape" on the adopt/don't
decision. §1–§3 (provenance and mechanism) are unaffected and remain accurate.

### 6.1 The evidence §4 relied on has decayed

| §4 figure (2026-07-24) | Re-measured 2026-07-31 |
|---|---|
| "33 commit events in the last 60 reflog entries" of direct-on-main root pressure | **5 direct-on-main in 7 days against 1,002 commits — 0.5%** |
| 50 worktrees, **11 prunable**, 244 branches | 118 worktrees, **0 prunable**, **1,334 branches** |
| root "frequently sits on another session's feature branch" (`.claude/CLAUDE.md`) | the root has left `main` **7 times all-time, last on 2026-07-15** — 16 days |

The single 33-event spike was **2026-07-21**. It did not recur.

### 6.2 The load-bearing incident would not have been prevented by worktrees

`.claude/CLAUDE.md` and §4 both cite incident 2026-07-11 — `dfacccd` (limit-recover, 5 files)
silently dropped by a sibling `/ship`. `SHIP_LAND_HARDENING_PLAN.md:28` records that
**"Session A (`wt-pool-4`) committed `dfacccd`"** — the losing session was **already
worktree-isolated**. `land-gate-serialization-2026-07-25.md:26` classifies it exactly: *"a sibling
moved `origin/main` between one rebase and its push."* That is a **landing race on the shared remote
ref**, a class per-session worktrees do not touch. It was fixed by `land-lock.sh` +
`stranded-sweep.sh` (`981c8ac7`, same day) and the fail-closed `ship-land.sh` pipeline (`40a016ce`).

Same pattern in the 2026-07-26 session-close incidents: both affected sessions (`session-a3f68174`,
`9850bcd5`) were **in worktrees**. And the 2026-06-12 incident in `git-worktree-guard.sh`'s header is
harm *caused by* worktrees — a reap that deleted an active session's tree.

The one incident worktrees genuinely did fix — dispatch workers fighting one index (`cc-wave-plan:267`)
— **is already done**: workers have spawned in their own worktrees since `8460d71f` (2026-07-20).

### 6.3 This repo already ran the experiment and reverted it on a measured soak

```
8f4264ba 2026-06-02 feat(worktree-isolation): reso-writer-lock.py — OS advisory writer-lock
8ed7cf3c 2026-06-02 feat(worktree-isolation): concurrent-writer-guard.sh — PreToolUse guard
528bf705 2026-06-03 fix(guard): default CLAUDE_ISOLATION_MODE to log — soak verdict: hard-deny cost > benefit
fdf0bda7 2026-06-03 chore(worktree): remove writer-lock + concurrent-writer-guard stack
```

`528bf705`'s subject **is** the verdict. Re-proposing hard enforcement without new harm evidence
re-runs a settled experiment.

### 6.4 The concurrency is real — concurrency is not harm

Confirmed, keyed on process **cwd** (never `pgrep -f`, which matches agent briefs): **11 live
claude-infra sessions, 9 of them in the shared root, 5 of those concurrent writers**; over 7 days
**≥2 concurrent writers 74% of the time ≥1 writer is live**, peak 12.

Against that: **zero recorded index-collision or ref-lock failures** across **114,859 commands / 310
sessions / ~46 h** — and that window (2026-07-30T08:33Z →) is the *highest-concurrency period on
record*. The `INC-1` claim in `docs/WORKTREE_WORKFLOW.md:12-13` ("bare commits sweep another
session's staged files… observed repeatedly"), copied verbatim into `CLAUDE.md:196`, has **one prose
source and zero grounding** — no sha, log, test, or artifact.

### 6.5 The cost side is what actually grew

**244 → 1,334 branches in 7 days (5.5×)**, of which **639 are already merged into main** (dead
weight), with **no GC**. Auto-wrapping adds one branch + one worktree per session at 14–27
sessions/day. Disk is *not* the constraint (claude-infra's 116 worktrees sum to ~3.8 GB, avg 33 MB —
the 148 GB under `~/Development/.worktrees` is reso's `node_modules`, not ours). **Cardinality is.**

And the cost unique to this repo stands: **`~/.claude` is ~302 per-file symlinks into the root
working tree**. Editing there is instantly live machine-wide; from a worktree an edit is inert until
landed **and** ff-synced **and**, for brand-new files, symlinked. Always-isolate would make
`deploy-lag-checkout-behind-origin` the default state rather than the exception.

### 6.6 What was done instead

- **Implemented** (`d94f1bf9`): project memory now follows the worktree. Measured 2026-07-31: **164
  worktree-keyed project dirs, 0 with a `memory/` dir**, against 213 topic files in the primary's —
  so every worktree session, including the 79 per-dispatch `wt-<12hex>` trees, ran memory-blind.
  This is worth fixing *regardless* of the adopt decision and is the cc-tlid repo-identity pattern.
- **Not built, deliberately**: the two other "HIGH" provisioning breakages did not survive
  verification. A permission storm is contradicted by **350 global allows + `defaultMode: auto`**
  (the 86 project-local entries are one-offs like `Bash(rm -rf bin/__pycache__)`), and the trust
  dialog does **not** block start — `gu-session-lifecycle` ran 4 sessions totalling 5.1 MB at
  `hasTrustDialogAccepted: false`.
- **Backlogged, named**: (a) branch GC for the 639 merged-dead refs — the real growing cost;
  (b) the never-landed A3 shared-checkout commit guard (`SESSION_AUTONOMY_RESEARCH.md:288`) — note a
  *hard-deny* variant would repeat §6.3's reverted experiment, so if built it should be
  warn/checkpoint first.

### 6.7 Limits of this re-measurement

- `bash-commands.log` starts **2026-07-30T08:33Z**, so "zero recorded failures" is scoped to ~46 h,
  not all time.
- Writer *overlap* was measured, not write *conflict* — whether two overlapping writers ever touched
  the same file was not established.
- Session liveness is proxied by transcript first→last span (median 27.4 min, p90 474 min), which an
  idle-but-open session inflates; the live process+cwd census is the independent corroboration.
- **What would flip this back:** a dated, grounded working-tree/index collision in the shared
  checkout — i.e. the INC-1 class with an artifact attached. On current evidence it has zero
  recorded instances.

### 6.8 Note for anyone resuming the stranded `gu-worktree-warmpool-b` branch

That branch's headline finding — the `git worktree remove` guard arm costing **96,457 ms** against a
registered `timeout: 10`, i.e. failing open in the destroy direction — was measured **2026-07-30**
against pre-fix code. The batched-`lsof` fix landed on trunk as **`86b52e32` (2026-07-31T14:09)**,
**34 h after that branch's tip**. Re-timed live 2026-07-31: **502 ms**. Do not re-apply that branch's
M1 patch; it is superseded, and trunk deliberately rejects the timeout it adds (a bound that gives up
can only make a safety refusal fail OPEN — `git-worktree-guard.sh:70-74`). The parse bypasses it
diagnoses (`git -c` between verb and subcommand, `--git-dir=`) do still appear real on trunk and are
the salvageable part.

---

## 7. CORRECTION to §6 (same day, 2026-07-31) — §6 is wrong; §4's "adopt" was right

**§6 reversed §4 on three legs. Two of them do not hold, and the operator supplied the evidence
that broke them. Net: ADOPT always-isolate for claude-infrastructure.** §6's *measurements* stand;
its *verdict* does not. Both sections are kept because the way this went wrong is the reusable part.

### 7.1 "Zero recorded failures in 114,859 commands" — wrong instrument, not a null result

§6.4 searched the logs for `cannot lock ref` / `index.lock`. **The failure the operator actually
hits — one session's commit sweeping another session's files out of the shared index — raises no
error at all. It succeeds.** It can never appear in a search for error strings, so the null was
guaranteed before it was run and carried no information. A second attempt to count blind
`git add -A` / `git commit -a` in `~/.claude/logs/bash-commands.log` was also void: the probe
matched its **own** command line in the log (the same self-match trap already recorded in
`docs/research/…` and in memory). Two instruments, both structurally blind. **Absence of a logged
error is not absence of the failure** — and per-worktree indexes prevent this class by construction:
each linked worktree owns a physically distinct `index`/`HEAD`, so one session's `git add` *cannot*
reach another's staged work.

### 7.2 "This repo tried it and reverted it" — backwards; the revert was of the ALTERNATIVE

§6.3 cited `528bf705` ("soak verdict: hard-deny cost > benefit") and `fdf0bda7` as this repo
rejecting isolation. Reading what those commits actually **changed** rather than what their subjects
**say**:

- `528bf705` touches exactly one file — `hooks/concurrent-writer-guard.sh` (+6/−5).
- `fdf0bda7` deletes `hooks/concurrent-writer-guard.sh` (142), `hooks/reso-writer-lock.py` (207),
  and 34 lines of `hooks/validate-bash.sh`.

That stack is a **PreToolUse hook that denied git writes mid-session, plus an advisory lock** — the
*policy* approach. "Hard-deny cost > benefit" is a verdict on **being blocked mid-session by a hook**,
not on starting in a worktree. And §1 of this very document already quotes why the stack was deleted:

> The writer-lock and guard defend an invariant git already enforces per-worktree, and are already
> no-ops inside every worktree — so they are deleted, **and the launcher always isolates.**

It was retired **because worktree isolation replaced it**. §6 cited the retirement of the losing
alternative as evidence against the winner. **Generalizable rule: date and read the DIFF, never the
subject line — a commit message describes intent, the diff describes the change.**

### 7.3 The surviving leg is real but narrow, and the cost argument INVERTS

`dfacccd` was indeed committed from `wt-pool-4`, so worktrees do not fix the **landing-race** class.
True, and irrelevant to the **index-sweep** and **deploy-block** classes, which are what actually
bite here. Distinct failure classes need distinct fixes; one class's immunity is not the other's.

**And §6.5's headline cost — "isolating kills the instant-live edit loop" — has the sign backwards.**
Observed live 2026-07-31 (operator screenshot + independent confirmation):

- `config/kitty.conf` and `README.md` sat **uncommitted in the shared checkout**, owned by a sibling
  session, and were **also modified by incoming commits**.
- `deploy-live.sh`'s `git merge --ff-only` therefore **refused**, correctly, rather than overwrite them.
- Root fell **16 commits behind trunk**; `com.claude.deploy-live` sat at **exit 1** for hours; the
  live `~/.claude` layer went stale fleet-wide.
- The triage a session produced was: *"the blocker clears itself (not yours, not mine) … Nothing to
  run; it resolves when they commit."* — **an unbounded wait on work nobody present owns.**

The root checkout is being asked to be two incompatible things at once: a **scratch tree many
sessions edit**, and the **ff-merge target that must stay clean**. Editing in root does not merely
risk a sweep; it **structurally blocks the deploy lane**. Under always-isolate no session edits root,
so root is always clean and the ff always succeeds. Isolation does not cost the deploy loop — **it is
what keeps it unblocked.** (§4 said this — *"`merge --ff-only` needs a clean root tree, and today
concurrent sessions dirty it"* — and §6 underweighted it.)

### 7.4 Verdict, and what must ship with it

**Adopt always-isolate**, via the `~/.zshrc:112` gate (basename → `.harnessrc` opt-in, reusing the
installed `worktree-harness`). Ship these in the same change or the cure hurts:

1. **Branch/worktree GC** — 1,334 branches, **639 already merged into main**, growing ~5.5×/week with
   no reaper. Always-isolate adds one branch + one worktree per session at 14–27 sessions/day. This
   was §4's recommendation #3 and remains unbuilt; it is the one genuine cost §6 got right.
2. **Desk exemption** — and re-point `scripts/desk-invariant.sh:93`'s `CANNED_CWD`, or a respawned
   desk silently lands back in root and re-creates the dirty-root condition on its own.
3. **Accept the deploy-latency trade explicitly**: a hook edit stops being instantly live and goes
   land → green stamp → deploy tick. Note the flip side — today a half-finished hook edit in root
   breaks every running session *immediately*; isolation removes that blast radius. Note also that
   the green gate is currently deadlocked at this commit rate
   (`docs/plans/DEPLOY_GATE_CONVERGENCE.md`) — that is prerequisite work, not a consequence of this.

### 7.5 Why §6 is kept rather than deleted

The error is instructive and cheap to re-make: a decayed prior verdict (§4), a subagent report taken
at face value, a commit **subject** read as if it were the **diff**, and a null from an instrument
that could not have detected the failure. Deleting §6 would leave §7 asserting a conclusion with no
visible reason for the reversal — which is the same "verdict with no provenance" defect that made §4
dangerous in the first place. **When correcting a verdict, leave the falsified reasoning visible.**

---

## 8. IMPLEMENTATION (2026-08-01) — §7.4's prescription was unsafe as written

§7's verdict (adopt) stands. Its **prescription** did not survive contact with the tree: all three
of its named prerequisites were mis-stated, each in a way that would have caused a real defect.
Corrected here at implementation time, with what actually shipped.

### 8.1 "Branch/worktree GC … remains unbuilt" — FALSE; the script is built, the SCHEDULER is not

`scripts/worktree-gc.sh` exists (49 KB) with a six-oracle safety model, `git branch -d`-only
deletion, and a full `CC_WTGC_*` env surface. What is missing is a **scheduler for this repo**:
the only reaper on the machine is `gl.reso.worktree-gc.plist` → `~/.reso/worktree-gc-run.sh`,
which hardcodes `REPO="…/reso-management-app"`. So claude-infrastructure has never been swept —
**126 worktrees, 1,193 branches** — and `--prune-branches` is off by default besides. This is the
[[desk-autonomy-dormancy-staged-not-loaded]] shape: built, correct, and inert. Shipped as
`scripts/worktree-gc-infra-run.sh` + `launchd/com.claude.worktree-gc-infra.plist` (04:15, so it
never contends with reso's 03:15 slot for the same git objects).

### 8.2 The one-line gate change would have run RESO's pool script against any repo

§7.4 says "via the `~/.zshrc:112` gate (basename → `.harnessrc` opt-in)". Changing only the
**condition** is unsafe, because the gate's **body** resolves the creation path through a ladder
whose second rung is **not repo-scoped**:

```zsh
elif [[ -f "$HOME/.reso/bin/worktree-pool.sh" ]]; then      # ← a GLOBAL path, no repo test
    _wtpath="$( cd "$_top" && bash "$HOME/.reso/bin/worktree-pool.sh" claim "$_wt" )"
```

That file exists. Any repo newly opted in falls straight into it and gets reso's pool logic
(env copying, port assignment, pnpm install, DB setup) executed against it. The rung must be
gated on the repo actually being reso before the condition is widened — **widening an opt-in
without scoping the branches it unlocks is how a policy change becomes an execution bug.**

### 8.3 `.harnessrc` / `worktree-harness` was the wrong mechanism for THIS repo

`worktree-harness` is installed and generic, but `doctor` on this repo reports two defaults that
are wrong and **silent**: worktree home `~/.worktrees` (this repo's entire convention, its gc
exclude lists and every operator habit say `~/Development/.worktrees`) and package manager
`npm → npm ci`, inferred from a `package.json` that exists only to render diagrams
(`beautiful-mermaid`; `node_modules` is absent even in the primary checkout). A `.harnessrc`
could correct both — at which point the tool is configured to do exactly what a 40-line script
does, plus a version-skew surface. Shipped instead: `scripts/new-worktree.sh`, which fills the
gate's **already-supported third rung** (fixed contract: name→derived path, stderr-only, non-zero
on failure) and branches off `origin/main` after an explicit fetch, never the local ref
(backlog #68). Marker file is **`.worktree-isolate`**, not `.harnessrc` — naming it after a tool
we deliberately do not use would invite someone to "fix" the mismatch by adopting it.

### 8.4 Ordering constraint the rollout must respect (this is what remains)

The gate flip is LAST and has a **live-content** precondition, not merely a landed one:

1. `~/.claude/scripts/desk-invariant.sh` is a **symlink into the root checkout**, so the desk
   exemption is live only once root has advanced to the commit carrying it.
2. Root advances **only** via `deploy-live.sh --auto`. A raw `git merge --ff-only` in root is
   forbidden here for a reason that bites this very change: it advances *files* but creates **no
   symlinks**, and §8.1 ships **brand-new** files (`worktree-gc-infra-run.sh`, the plist, the
   activation script) that need `install.sh` to be linked. A raw ff would make the desk exemption
   live while leaving the new reaper unlinked and silently inert.
3. Therefore: land → deploy → **verify by CONTENT** that the live
   `~/.claude/scripts/desk-invariant.sh` contains the exemption → only then flip `~/.zshrc`.

Flipping before (3) does not merely lose the exemption — it makes the desk mint a **new worktree
per respawn**, an unbounded leak in the exact subsystem §8.1 exists to bound.
