# The per-instance worktree wrapper — provenance, mechanism, and whether it extends here

**Date:** 2026-07-24 · **Type:** read-only investigation + verdict · **Repos:** `reso-management-app` (source), `claude-infrastructure` (candidate)

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
5. **Operator decision required:** does the desk keep its shared-checkout cwd (exempt via
   `HARNESS_GC_KEEP` / `WH_ISOLATION_SKIP=1` in the desk launcher), or does it isolate too and
   retire the `desk-land.sh` workaround?

### What would argue against

Honest counterweights, none of which I judge decisive: the pattern's benefit scales with
*concurrent writers*, and a single-session day in this repo pays worktree overhead for nothing
(this is exactly what the global CLAUDE.md "CONDITIONAL, not always" rule protects) — but 6
concurrent sessions in the shared checkout today says that is not the regime we are in. And the
symlink-liveness change is a real workflow cost that must be absorbed by (4), not ignored.
