---
status: in-progress
row: 11
subsystem: Worktree & warm-pool management — where writers work
---

# WORKTREE MANAGEMENT V2 — ground-up rebuild of row 11

**Scope (frozen):** a writer always gets an isolated, correctly-provisioned worktree, and no
worktree holding unlanded work is ever destroyed — with one named owner per artifact class, so
disk drift has a collector instead of a witness. Measured, landed, and verified by disk-truth
acceptance reads.

Methodology: `skills/ground-up/SKILL.md`. Exemplars: `LAND_PIPELINE_V2.md` (row 1),
`SESSION_LIFECYCLE_V2.md` (row 2 — the cell-falsification exemplar).

> **Session note.** This is the **second attempt** at row 11. The first died abruptly at
> 2026-07-30T04:39Z, ~39 min in, with nothing landed (worktree was `ahead=0` and clean, so
> nothing was stranded; only one transcript in its project dir, so it did not recycle; cause
> unexplained). Its Phase-1 work was good and has been **independently re-derived here, not
> inherited** — every number below is measured this session. The lesson encoded in this document's
> existence: **land Phase 1 before building anything.**

---

## §0 — Phase 0 · orchestration

Single-owner rebuild (this session). No teammates spawned for Phase 1: the measurements are
cross-cutting and a split would have produced numbers nobody owned. Three **read-only** research
subagents were fanned out for breadth (reaper audit · hook + registration audit · branch-graveyard
sweep); every decision-grade number in §1 was re-derived by the lead from primary disk truth.

🚨 **HAZARD RULE FOR THIS ROW — binding on every future session that touches these files.**
The subject of this row is a **reaper**, and the box holds live work. At measurement time:
**117 registered worktrees of this repo, 29 of them holding 115 unlanded commits**, including
concurrent ground-up rebuilds and the campaign coordinator's own worktree. Therefore:
never point a test, probe, dry-run, or "just checking" invocation of `scripts/worktree-gc.sh`,
`git worktree remove`, `git worktree prune`, or `git branch -d/-D` at a real worktree or a real
branch — **not even with a flag believed to be read-only**. Build a throwaway repo under the
session scratchpad and exercise the reaper there. Every experiment in §1.6 was run that way, and
each names its target repo explicitly. A destroyed worktree here loses another row's unlanded
rebuild; there is no undo.

---

## §1 — Phase 1 · measured constants (with citations)

All figures measured 2026-07-30 between 08:0xZ and 08:4xZ on this box, by the lead, from primary
disk truth. Scripts preserved in the session scratchpad. **Counts move — 116→118 registered
worktrees drifted *during* the session — so each is a timestamped sample, not a state.**

### 1.1 The standing-constraint cell is FALSIFIED as a constraint (killed, then renamed)

The map's row-11 cell reads **"107 GB observed drift; ownership per artifact-class"**. The
number re-derives close, and **it is not a constraint.**

| # | Constant | Value | How measured |
|---|---|---|---|
| C1 | Worktree disk, all repos under `~/Development/.worktrees` | **116.5 GiB** (122,154,540 KiB) across 198 dirs | `du -sk ~/Development/.worktrees/*` |
| C2 | Volume capacity | **7.28 TiB** (7,811,085,600 KiB) | `df -k /Users/chrisren` |
| C3 | Volume free | **5.00 TiB** (5,367,362,896 KiB), 32% used | same |
| C4 | Worktrees as share of volume | **1.56%** | C1/C2 |
| C5 | Free space ÷ worktree footprint | **43.9×** | C3/C1 |
| C6 | `claude-infrastructure` object store | 41.76 MiB packed + 2.41 MiB loose | `git count-objects -vH` |

**Verdict: KILLED as a constraint.** The entire worktree footprint is 1.56% of the volume with
44× that much free. Disk pressure cannot be the binding resource, so a design whose primary aim is
reclaiming bytes is designing against a ghost. This is row 13's learning landing for the third
time on this campaign (rows 2, 5, 8, 10, 12, 13 all had cells falsified or renamed), and the
predecessor session reached the same conclusion independently — two derivations, one answer.

**Renamed cell (proposed to the coordinator):**
> *"The irreplaceable resource is un-recreatable working-tree content, not bytes and not commits.
> A collector must be able to name what it would destroy — and both of the reaper's independent
> safety gates are blind to the same class."*

### 1.2 The irreplaceable resource, measured honestly (patch-id deduped)

A per-branch commit **sum** is a row count, not a quantity of work
(memory: `redundant-session-gc-by-content`). Deduped:

| # | Constant | Value | How measured |
|---|---|---|---|
| C7 | Local branches | **1,029** | `for-each-ref refs/heads` |
| C8 | Branches ahead of `origin/main` | **620** | `rev-list --count origin/main..$b` per branch |
| C9 | SUM of per-branch counts (**inflated row count**) | **2,784** | sum of C8's per-branch values |
| C10 | DISTINCT unlanded commit objects (union) | **2,207** | `rev-list origin/main..$b` ∪, `sort -u` |
| C11 | DISTINCT **patch-ids** (unique *changes*) | **955** | `git show \| git patch-id --stable` ∪ |
| C12 | Duplication factor C10/C11 | **2.30×** | derived |
| C13 | `git cherry` `-` — change ALREADY on trunk | **1,974** | `git cherry origin/main $b` per branch |
| C14 | `git cherry` `+` — change NOT on trunk (irreplaceable) | **799** | same |

So the naive headline (2,784 unlanded commits) overstates unique irreplaceable *changes* by
**2.9×**, and **71% of unlanded commits are already on trunk by content** (C13 vs C13+C14).

### 1.3 …and 96% of it has no worktree to protect

| # | Constant | Value | How measured |
|---|---|---|---|
| C15 | Branches with a worktree checked out | **114** | `worktree list --porcelain` → `branch refs/heads/` |
| C16 | Unlanded branches **with** a worktree | **28** | `comm -12` of C8 names and C15 |
| C17 | Unlanded branches with **no** worktree | **592** | `comm -23` |
| C18 | Distinct commits carried by those **bare refs** | **2,128** | `rev-list` ∪ over C17 |
| C19 | Share of unlanded commits with no worktree | **96.4%** | C18/C10 |

**This is the row's central structural fact.** "Never destroy a worktree holding unlanded work"
is aimed at a population that holds **3.6%** of the unlanded commits. The durable carrier of
unlanded work is **the branch ref**, not the worktree — and the reaper's `--prune-branches` mode
(`scripts/worktree-gc.sh:586`) is the only mechanism that deletes branches.

### 1.4 Worktree population, and a correction to my own first count

| # | Constant | Value | How measured |
|---|---|---|---|
| C20 | Registered worktrees of this repo | **117** (118 mid-session; drifting) | `worktree list --porcelain \| grep -c '^worktree '` |
| C21 | Directories under `~/Development/.worktrees` | **199** | `ls -1d` |
| C22 | …belonging to `claude-infrastructure` | **112** | per-dir `.git` → `gitdir:` target |
| C23 | …belonging to **OTHER repos** (`doc_classifier`, `reso-management-app`) | **83** | same |
| C24 | …non-git leftovers (empty `chore/`, `fix/` path stubs) | **4** | same |
| C25 | **Prunable** admin entries | **0** | `worktree list --porcelain \| grep -c '^prunable'` |
| C26 | Worktrees holding unlanded commits / total those commits | **29 / 115** | per-worktree `rev-list origin/main..HEAD` |
| C27 | Worktrees with dirty tracked files / total files | **8 / 23** | per-worktree `status --porcelain` |

⚠️ **CORRECTION, my own error, recorded rather than hidden.** My first pass reported "87 orphan
directories" and "5 prunable registered paths". **Both were false**, and by the same mechanism —
*two sides of a comparison drawn from different populations*
(memory: `positive-control-the-denominator`). I diffed `.worktrees/*/` against **all** registered
worktree paths, which include paths outside that directory, so the main checkout and three
out-of-tree worktrees showed as "missing". Corrected by asking git directly: **0 prunable** (C25).
And of the 87 "unregistered" dirs, **83 are worktrees of other repositories** (C23) — a
cross-repo sharing fact, not a leak. `~/Development/.worktrees` is shared by 5 repos.

**The reaper already knows this.** `scripts/worktree-gc.sh:13-15` enumerates *only* from
`git worktree list --porcelain` and documents "NEVER a directory glob: ~/Development/.worktrees is
SHARED ACROSS 5 REPOS"; `:223` guards basename collision across those repos. **This axis is
already correct and must not be "fixed"** (memory: `inventory-before-building`).

### 1.5 Deploy / activation truth for every surface this row touches

| # | Surface | Live-layer form | Landing == deploying? |
|---|---|---|---|
| C28 | `scripts/worktree-gc.sh` | **symlink** → shared checkout | **YES** |
| C29 | `hooks/worktree-setup.sh` | **symlink** → shared checkout | **YES** |
| C30 | `hooks/git-worktree-guard.sh` | **symlink** → shared checkout | **YES** |
| C31 | Checkout lag behind trunk at measurement | **0** commits | sawtooth, not a state |

All three owned files are per-file symlinks into `~/Development/claude-infrastructure`, so **this
row needs no activation step** — landing puts the change live for every running session. (Contrast
`~/.claude/CLAUDE.md`, a real file where landing changes nothing; not a surface of this row.)

**Consumed dependencies, checked for existence evidence rather than trusted:**

| # | Dependency | State | This design's fail-soft behaviour |
|---|---|---|---|
| C32 | Row 4 session-beat oracle (`~/.claude/cc-beats`) | **ABSENT — INERT** (verified by `ls`) | never consulted; not in the reaper today either |
| C33 | `~/.claude/hooks/live-session-registry.sh` output dir `~/.reso/live-sessions` | present | reaper reads it; missing row ⇒ "not live" (fail-open, see F-4) |
| C34 | Row 2 `~/.claude/cc-fired/*.json` | **161 records, 131 naming a worktree path**, schema 2 with `cwd`/`closedAt`/`succession` | **usable ownership oracle — populated and durable** |

### 1.6 Throwaway-repo experiments (target named in every case)

Target for E1–E4: a repo created and destroyed inside
`…/scratchpad/LAB`. **No real worktree or branch was reachable from any of these commands, and
`scripts/worktree-gc.sh` was never invoked.** git 2.54.0.

| # | Experiment | Result |
|---|---|---|
| E1 | `git worktree remove` (**no** `--force`) on a worktree holding **only gitignored** files (`secrets/creds.env`, `expensive.env`) | **REMOVED. exit 0. Silent. Data destroyed.** `status --porcelain` was empty; `--ignored=matching` showed `!! expensive.env`, `!! secrets/` |
| E2 | **CONTROL** — same command, tracked file modified | **REFUSED**: `fatal: … contains modified or untracked files, use --force` |
| E3 | **CONTROL** — same command, untracked (not ignored) file | **REFUSED**, same fatal |
| E4 | `git cherry <absent-trunk-ref> <branch>` | `fatal: unknown commit origin/main`, **rc=128** |
| E5 | `pgrep -f claude` vs the real process population | **259 matches** vs **41** real (`ps` comm-basename); and it **does not contain this session's own `claude` pid** |

E2 and E3 are the positive controls that make E1 meaningful: the refusal mechanism demonstrably
works, and **git's definition of "unsafe to delete" simply excludes ignored files.**

---

## §2 — Phase 2 · the inversion

**The row protects the replaceable thing, and is structurally blind to the irreplaceable one.**

`scripts/worktree-gc.sh` is not a naive reaper — it is careful, and its care is aimed at
**commits**: `landed()` uses patch-equivalence not commit counts (`:229-243`); the dispose path
demands an A3 proof that a durable ref preserves the tip (`:426`); `verify_preserved` re-checks the
unlanded set after the fact and exits **4** if it cannot confirm (`:371-377`, `:611-613`); it never
passes `--force` and never `-D`, deliberately leaving "git's refusal as the second gate on our
evidence" (`:449`, `:544`, `:585`).

Every one of those protections guards the class that is **2.30× duplicated, 71% already on trunk
by content, and 96.4% not in a worktree at all** (C10–C19). Meanwhile:

1. **`--ignored` appears nowhere in the script.** Its content gate (`:488`) is
   `git status --porcelain`, which by definition does not report ignored paths.
2. **git's own refusal — the declared second gate — has the same blind spot** (E1, controlled by
   E2/E3).

So the two "independent" nets **fail on exactly the same class**. That is not defence in depth; it
is one gate counted twice. And the class they both miss is the one the operator's own standing
rules single out as unrecoverable: gitignored `.env`/secrets, local DBs, and **paid generated
assets that cost real money and have regeneration cooldowns** (global `CLAUDE.md`, Git Safety).
Measured live: multiple worktrees read **CLEAN** under `status --porcelain` while holding
gitignored content (e.g. `banner-storyboard-10` 4 entries, `gu-account-relogin` 7,
`gu-context-economy` 3).

**The structural change:** make the collector's evidence set cover *un-recreatable content*, and
require every destructive act to **name what it would destroy** — an inventory, not a boolean.
A gate that cannot enumerate its blast radius cannot be audited, and `--force`-free git is not a
substitute for looking.

---

## §3 — Failure-mode table

Modes are **observed or experimentally demonstrated this session**, each with its structural
answer. A mode without an answer is an unfinished design.

| # | Failure mode | Evidence | Structural answer |
|---|---|---|---|
| F-1 | Worktree removed while holding gitignored, un-recreatable content (`.env`, paid assets, local DB) | **E1** + live CLEAN-but-ignored worktrees (§1.6, §2) | Add an ignored-content probe to the evidence set; classify ignored paths as *recreatable* (`node_modules/`, `dist/`, `.next/`) vs *un-recreatable* (everything else) and refuse on the latter. Enumerate, don't just refuse |
| F-2 | Unlanded work lost with no worktree involved — the branch ref is the real carrier | C17-C19: 592 branches / 2,128 commits with no worktree | `--prune-branches` must apply the same content-preservation proof the dispose path applies, and report the reflog/durable-ref position it relies on |
| F-3 | `origin/main` stale or unfetched ⇒ `landed()` false for everything ⇒ fleet routed to the dispose path where `unlanded_set` is empty ⇒ A3 and `verify_preserved` both pass **vacuously** ("0 patch(es) preserved") | E4 (rc=128 swallowed by `2>/dev/null` at `:232`,`:242`); code path `:506-521`→`:426`→`:376` | Require a *positive* landedness measurement: a dispose proof must assert `n > 0` patches actually preserved, or refuse with a distinct "landedness unmeasurable" verdict — a third state, never a silent zero (memory: `gate-never-ran-vs-gate-red`) |
| F-4 | Liveness oracle degraded rather than absent: `lsof`/`pgrep` present but returning nothing ⇒ `ORACLES=1`, `LIVE_CWDS=""` ⇒ **whole fleet reads dead** | `:199-206` counts oracle *existence*, not function; contrast `:190-195` which requires success | Count an oracle only when it returns a positive result verified against a **known-live control** (this session's own worktree); a zero-result oracle is UNKNOWN, not "all dead" |
| F-5 | `pgrep -f claude` is both over- and under-inclusive: 259 matches vs 41 real processes, and it misses this session's own live `claude` | **E5** (memory: `pgrep-f-matches-agent-briefs`) | Match on the **command position** (`ps -Ao pid,comm` + basename), never an argv substring. Over-match is safe here; the **under-match is not** |
| F-6 | A live session whose cwd is a **subdirectory** of the worktree is invisible to the cwd oracles (all three comparisons are exact-match: `:213` `grep -qxF`, `:226`, `:361`) | code read | Ancestor-prefix match, not string equality. Header at `:19-20` already claims over-matching is safe — implement to that claim |
| F-7 | `git status` failing (corrupt index, unreadable `.git`) reads as **CLEAN** and falls through toward removal | `:488` — `[ -n "$(… 2>/dev/null)" ]`, status discarded | Distinguish "clean" from "unreadable": capture rc, treat non-zero as KEEP |
| F-8 | Non-numeric `CC_WTGC_IDLE_MIN`/`CC_WTGC_ABANDON_HOURS` makes `[ -lt ]` non-zero, **skipping the floor** rather than enforcing it | `:504`, `:513` unvalidated; contrast `:221`,`:499` which do validate | Validate with the same `case … *[!0-9]*` idiom already used elsewhere; invalid ⇒ refuse, never skip |
| F-9 | The mutex declares itself stale after 60 min by reading its own never-refreshed creation mtime, so a still-running pass gets its lock broken | `:170` vs `:174` | Heartbeat the lock during the sweep, or hold pid + `kill -0` liveness; a 116-worktree sweep's real duration must be measured against the window |
| F-10 | `--prune` is advertised by the guard hook but is a **no-op alias for the fully destructive default** | `:103` (`: ;`); advertised at `hooks/git-worktree-guard.sh:5,73` | Make `--prune` mean prune-only, or stop advertising it; a flag whose name implies "safe subset" must not be the destructive default |
| F-11 | No env kill switch — `DRY_RUN` is settable only from argv, so the reaper cannot be disabled fleet-wide without editing it | `:95-100`; grep finds no `CC_WTGC_DISABLE` | Ship `CC_WTGC_DISABLE` (ground-up skill: every new mechanism ships a kill switch, never revert-as-plan) |
| F-12 | `worktree prune` (`:472`) runs **before** the gate loop, so `CC_WTGC_EXCLUDE` never protects it | `:468-472` vs `:484` | Apply the exclude list to prune as well, or document prune as unconditional and prove it is content-free |
| F-13 | Two named "core surfaces" of this row **do not exist** — `scripts/new-worktree.sh`, `.worktreeinclude` | never added on any ref (control passed: `worktree-gc.sh` returns 3 shas); absent from tracked tree, shared checkout, live layer | Correct the map cell. A cell naming phantoms is a map defect and fixing it is in scope |
| F-14 | Stashes, reflogs, submodules, LFS objects are never consulted before removal | grep: zero references in the reaper | Name them explicitly as out-of-evidence in the disposal record, so the gap is legible rather than assumed-covered |

---

## §4 — Rejected alternatives

| # | Alternative | Why rejected |
|---|---|---|
| R-1 | **Reclaim disk** — aggressive GC keyed on the 116.5 GiB footprint | The cell's own premise, falsified: 1.56% of volume, 44× headroom (C1–C5). Designing a destructive mechanism against a non-binding resource is how a collector becomes the top risk |
| R-2 | Pass `--force` to `git worktree remove` so removals stop being "refused" | Inverts the safety story. git's refusal is one of only two content gates; E1 shows it is already too weak, not too strong |
| R-3 | Rewrite the reaper from scratch | Measured against the source: its commit-preservation logic (patch-equivalence, A3 proof, `verify_preserved`, exit 4, no `--force`/`-D`, cross-repo scoping) is **correct and hard-won**, with 41 tests and 0 dead assertions. The defect is a *missing evidence class*, not a wrong architecture. Rewriting would re-introduce solved problems (memory: `inventory-before-building`) |
| R-4 | Delete the 83 other-repo directories under `~/Development/.worktrees` | They are live worktrees of other repositories. My own first count called them orphans — corrected in §1.4. The reaper is already correctly scoped to one repo's `worktree list` |
| R-5 | Add `.gitignore`d paths to tracking so the existing gate sees them | Would commit secrets and multi-GB `node_modules` into history. The gate must learn to look, not the content move |
| R-6 | Build `scripts/new-worktree.sh` + `.worktreeinclude` because the cell names them | They have never existed on any ref (F-13), and the native `claude -w` flag plus `hooks/worktree-setup.sh` already provision. Building a phantom to satisfy a cell is the wrong direction — correct the cell (decision recorded, not assumed) |
| R-7 | Trust row 4's session-beat oracle for liveness | Verified **INERT** — `~/.claude/cc-beats` absent (C32). Consumed fail-soft: never consulted, and its absence changes nothing |

---

## §5 — Acceptance criteria as disk-truth reads

Each AC names the file or command that proves it. Narration is not evidence.

| # | Criterion | Disk-truth read |
|---|---|---|
| AC-1 | The reaper's evidence set covers gitignored content | `grep -c -- '--ignored' scripts/worktree-gc.sh` ≥ 1, and a throwaway-repo test asserts a worktree holding an un-recreatable ignored file is KEPT |
| AC-2 | E1's data-loss path is closed | New bats case: ignored-only worktree ⇒ `KEEP`; RED-proved against a pristine `git archive` tree (must FAIL there) |
| AC-3 | Every destructive act names its blast radius | Disposal ledger row carries an inventory of ignored paths it would have destroyed; `jq` over `~/.claude/state/worktree-disposals.jsonl` |
| AC-4 | Landedness is never vacuously proven | Dispose refuses with a distinct verdict when the trunk ref is unresolvable; test asserts the verdict token, not just a non-removal |
| AC-5 | Liveness oracles are function-verified, not existence-counted | A degraded-oracle test (binary present, output empty) ⇒ refuse, exit 3 |
| AC-6 | Liveness matches on command position and subdirectory cwds | Tests for a subdir-cwd live session and for the `pgrep -f` over/under-match |
| AC-7 | Env kill switch exists | `CC_WTGC_DISABLE=1 bash scripts/worktree-gc.sh` mutates nothing; asserted in the suite |
| AC-8 | Map row 11 corrected | `GROUND_UP_REBUILD_MAP.md` row 11 no longer names phantom surfaces; cell renamed per §1.1 |

**Status of each AC: NOT YET MET.** This document is the Phase-1 landing; §3's answers are
designed, not built. Nothing in §5 may be reported met until its read is run and quoted.

---

## §6 — Remainders / open questions

- **R-a** `CC_BATS_ACTIVE` is not unset in `tests/worktree-gc.bats` `setup()` (siblings do unset it,
  e.g. `tests/qos-chokepoint.bats:40`). Whether it changes behaviour here needs PATH-shim tracing —
  open, not a finding.
- **R-b** Real duration of a 116-worktree sweep vs the 60-min lock-staleness window (F-9) is not
  answerable by reading, and cannot be measured against real worktrees. Needs a throwaway repo
  scaled to ~116 worktrees.
- **R-c** `tests/worktree-gc.bats` REMOVE-half assertions are `[ ! -d "$p" ]` and would pass
  **vacuously** if the fixture's `worktree add` silently failed (`wt()` at `:62-65` swallows rc).
  Discriminator-pair discipline mitigates; worth an explicit fixture assertion.
- **R-d** Warm-pool semantics: `wt-pool-3`, `wt-pool-7` exist on disk (3.71/3.88 GiB) but the
  pool build logic lives in `scripts/handoff-fire.sh` (row 2's file, row 2 DONE). **Coordinator
  ping required before touching that file** — it is the campaign's live fire path.
