---
status: in-progress
---

# Continuous delivery to LIVE kitty sessions — no human prompt, no restart

**Operator's question, 2026-09-17:** *"How can we consistently without human-in-the-loop
prompting have your work landed, deployed, and live to current ongoing Kitty sessions without
manual user commands or without needing to restart?"*

**Scope (frozen):** answer that question with a measured design, and land whatever of it is
buildable. Success is a pipeline where an agent's commit reaches the bytes a RUNNING kitty
session executes, with no operator command and no kitty restart — or a precise statement of
which links genuinely cannot be closed and why.

---

## Why this is not one problem

The chain has four links and they fail for unrelated reasons. Tonight's session hit three of
them in three hours, which is what prompted the question:

| # | Link | State tonight | Failure seen |
|---|---|---|---|
| L1 | commit → **trunk** | `/ship` works | livelocked ~3h on gate/contention; one land needed the in-lock path |
| L2 | trunk → **shared checkout** | `deploy-live.sh` | **REFUSED — DIVERGED** 3× today; a commit made IN the shared checkout blocks the whole fleet |
| L3 | checkout → **live layer** | per-file symlinks | works, but a NEW file needs `install.sh`; an ADD is absent, not stale |
| L4 | live layer → **RUNNING process** | *mostly unsolved* | see below |

**L4 is the operator's actual ask and it is not uniform.** Measured tonight:

- **kitty.conf** — ALREADY SOLVED. `kitten __watch_conf__` (pid 74784) watches the config and
  reloads it in ~100 ms with no restart. A landed config change reaches live panes by itself
  once L2/L3 complete.
- **shell scripts** (`kitty-pane-title-toggle.sh`) — solved by construction: each press execs
  the file fresh, so a new version is picked up on the next press.
- **long-lived daemons** (`kitty-pane-title-overlay.py`) — NOT solved. The daemon holds its code
  in memory; tonight the cost fix required killing pid 84540 by hand before the new code ran.
- **the kitty binary itself** — NOT solvable without a restart. The C patch
  (`docs/patches/kitty-window-title-band.patch`) is in this class.

So "no restart" is achievable for three of four classes and provably impossible for the fourth.
That distinction is the answer's spine.

---

## Phase 0 — Agent Team Orchestration

**Execution locus this wave: RESEARCH SUBAGENTS (read-only fan-out), lead synthesises.**
Justification: every open question is a *measurement of existing machinery*, not a code change.
Nothing here writes a tracked file until synthesis, so the worktree-isolation rule does not
bind. Implementation waves that follow will be dispatched sessions (S) per the standing default.

Lead context budget: hold ≥50% for synthesis and the implementation decision.

---

## THE SHARED TASK LIST

`CLAUDE_CODE_ENABLE_TODO_TOOLS` is unset on this box, so `TaskCreate`/`TaskList` do not exist
(verified this session: `ToolSearch` returns no match). Per CLAUDE.md § Shared Task List, **this
table IS the list** until migration `0022` lands. Update the Status column in place; never
delete a row.

| id | Task | Link | Status | Owner |
|----|------|------|--------|-------|
| T1 | Why do shared-checkout commits keep blocking converge, and what auto-resolves it | L2 | research | A1 |
| T2 | What fires `/ship` today without a human, and where are the gaps | L1 | research | A2 |
| T3 | What fires `deploy-live` after a land; why is it effectively manual | L2 | research | A3 |
| T4 | The gate-green / certgate deadlock pinning the live layer | L1/L2 | research | A4 |
| T5 | Reaching a RUNNING process: the four classes, what each needs | L4 | research | A5 |
| T6 | Daemon hot-reload: how a long-lived python daemon adopts new code | L4 | research | A6 |
| T7 | Verification: how we PROVE live sessions run the new bytes | L3/L4 | research | A7 |
| T8 | Prior art already built and unwired in this repo (incl. the activation queue) | all | research | A8 |
| T9 | Failure modes that go SILENT, and what alarm would catch each | all | research | A9 |
| T10 | What "no human in the loop" genuinely cannot cover, and why | all | research | A10 |
| T11 | Unblock tonight's divergence (`145c32f53`) without destroying a peer's work | L2 | lead | lead |
| T12 | Synthesise → design → implement | all | blocked by T1-T10 | lead |

---

## Open questions the wave must answer

1. Is there a sanctioned auto-converge trigger, or is `deploy-live` only ever run by hand?
2. Can the converge lane tolerate a diverged shared checkout safely, or must divergence be
   *prevented* at the commit site instead?
3. What is the smallest reliable hot-reload contract for our daemons — exec-on-change, a version
   stamp checked per tick, or supervision that restarts on mtime?
4. Does anything today verify that a RUNNING session executes the landed bytes, as opposed to the
   live layer merely containing them?

---

# SYNTHESIS — wave A1-A10, 2026-09-17

**The answer: the pipeline is ~90% built. Four specific things are missing, all small, and one
of them is why nobody noticed the other three.**

## The finding that reframes the question (T5, conviction 97%)

**For `kitty.conf` there is no deploy step at all — landing IS deploying.** `~/.config/kitty/kitty.conf`
symlinks into this repo, and kitty's `__watch_conf__` child resolves symlinks before watching
(`tools/watch/api.go:104-107`), so **the watcher is watching this repo's `config/` directory**.
Verified two ways: a sandbox arm (edit the real file → SIGUSR1 in 159 ms) and `lsof -p 74784`
showing fd 10 = `/Users/chrisren/Development/claude-infrastructure/config`. Measured latency
**0.12-0.21 s**, no restart, no converge, no `install.sh`.

Three caveats that are now written down rather than rediscovered:
- **2 of our options are restart-required and reload SILENTLY**: `listen_on` (`config/kitty.conf:123`)
  and `macos_option_as_alt` (`:296`). `listen_on` is load-bearing — it mints `/tmp/kitty-{pid}`.
  `allow_remote_control` was suspected and is ACQUITTED (a 2,600-char grep window had run past
  into the neighbouring block).
- **A cold drop-in directory is not watched at all.** `desired_dirs` is built at watcher start;
  `drag-arm.d` was created at 22:47 against a watcher started at 20:13. After creating any NEW
  drop-in dir, one write to `kitty.conf` is required before it is watched.
- `kitten` is a separate binary: `kitty @` calls pick up new bytes, but the already-spawned
  `__watch_conf__` / `__atexit__` children do not.

## The four gaps

| # | Gap | Evidence | Size |
|---|---|---|---|
| G1 | **Nothing stops the write that breaks everything.** A `git commit` in the shared checkout makes `merge --ff-only` arithmetically impossible, blocking converge FLEET-WIDE. The FF-GATE (`hooks/validate-bash.sh:1250`) already denies `merge`/`pull`/`reset`/`checkout` there — `commit` appears nowhere in its scope note, its 18 tests, or the backlog. Never considered, not considered-and-rejected. **63 commits in 36 days; 16 hand-cures; 45+ logged DIVERGED refusals (a floor — `refusal_bump()` returns early unless `AUTO=1`, so hand-run refusals count nowhere).** | T1 | 1 hook arm + an escape hatch for the desk |
| G2 | **Nothing fires the converge after a land.** All four `deploy-live` references in `ship-land.sh` are COMMENTS (`:2437`, `:2480`, `:4173`, `:4205`); `:38` states the intent — *"DEPLOY — not land — waits for the green verdict."* The only automated caller is a 600 s clock that advances only when the lag budget trips. **40.1% of 152 advances were run BY HAND** (independently reproduced: `.claude/commands/ship.md:124` measured 39.4%). Median residency commit→live **2.31 h**, p90 **15.95 h**. | T3 | edge trigger in `post_release_finish()` |
| G3 | **The alarm channel is dead, and that is why G1/G2 stayed invisible.** `~/.claude/cc-roles/desk` = pane **672**; `it2 session list` returns 11 panes and 672 is not among them (re-verified by the lead). **66/66 pages in 24 h: `delivered:false, channel:"none", notify_rc:0`** — the notifier succeeds at delivering nothing. 13/13 delivered on 09-07; zero since. 1,554 unseen escalations, and the only offered action is a mass-ack that would silence the divergence class for 7 more days. | T9 | make `cc-notify --role` exit non-zero on a dead target (3 lines) |
| G4 | **A long-lived daemon never adopts landed code.** The overlay daemon holds its source in RAM; tonight's cost fix needed a manual kill. **The cure already shipped in this repo**: `lead-supervisor.sh:1329 self_restart_if_stale()` — sha256 its own source per tick, ABSTAIN if unreadable, exit on change. | T6 | ~8 lines, copying the shipped pattern |

## Corrections the wave forced on the lead's own plan

- **Cherry-pick-and-land does NOT clear a divergence** (T1). `--ff-only` compares ANCESTRY, so an
  equivalent copy leaves the original object on live HEAD and the lane still refuses. Only the
  owner landing that very commit, or a `reset --keep` after content is proven present, clears it.
  The lead started a cherry-pick rescue on this basis and it was the wrong instrument; the peer
  landed their own work instead and the checkout went 0-ahead/0-behind by itself.
- **The daemon never needed killing** (T5). `main()` tries `_client()` first, so a live daemon
  serves every press with old code; `kitty-pane-title-overlay.py stop` sends `quit`, unlinks the
  socket, and the next press respawns in ~400 ms — and unlike a kill it wipes placements first.
- **Naive `os.execv` self-reload is a trap** (T6, probed): PEP 446 CLOEXEC closes the listening
  socket, the socket FILE survives with nobody listening, and for ~0.1-0.2 s every client gets
  ECONNREFUSED — which `_client` reads as "no daemon" and answers by spawning a competitor that
  can win the freed flock. Quit-and-respawn has none of it (ENOENT, not ECONNREFUSED).

## Already built, merely off (T8)

- **`CC_INSTALL_RESIDENT_RELOAD`** — the actuator for G4's general case. Detector running
  unconditionally (`deploy-live.sh:1705-1899`), actuator landed with a 13-case suite
  (`install.sh:1101-1118`), every safety precondition met, **default 0**. Blocked on decision
  packet `4194644aea26`, whose actuator `/tmp/resident-reload-flip.sh` was **reaped by the
  2026-09-16 reboot** — the decision is answerable and currently unexecutable. Re-minting is ~10 lines.
- **`com.claude.deploy-live` is the one job the CPU-band repair skipped** — `ProcessType Background`
  ⇒ PRI 4, E-core confined, measured against `postland-verify` at PRI 20 on the same box.
  Migrations 0010 and 0016 fixed the siblings; no migration exists for deploy-live.

## The irreducible residue (T10) — what "no human" honestly cannot cover

1. **CONSENT** — the predicate is "did a human decide", which is not a property of any artifact.
2. **SELF-AUTHORIZATION** — automating it makes "the operator decides what the agent may do" false.
3. **VALUE FORKS** — three tonight (disarm → re-arm → opt-out-to-opt-in), none derivable from code.
4. **PROCESS IDENTITY** — a session cannot restart the kitty it lives in; it dies mid-command.
   Five mechanisms checked and each dead for a different reason (no `SCM_RIGHTS` fd handoff
   anywhere in kitty's tree; `detach-window`'s three destinations are all within one `Boss`).

🚨 **And the measurement that reframes "manual commands": 86% of permission refusals raise NO
DIALOG AT ALL.** Of 29 refusals tonight, 4 coincided with a prompt; 25 had nothing to press.
Two different populations: PROMPTS are a keystroke problem (4,503 archived, p50 12 s, **98.2%
approved**); REFUSALS are a hand-back problem (194 in 9 days, **1,966 agent-hours blocked**). An
allowlist edit cannot touch either — a `permissions.allow` rule does not suppress a PreToolUse
hook's `ask`, and **45.9% of prompts are structurally unallowlistable** (multi-statement,
substitution, heredoc). Self-inflicted share: **9.2% of all prompts are file-writing heredocs**,
a shape produced by the auto-mode style instruction to prefer heredocs over the Write tool.

## Next wave (implementation) — locus S, one dispatched session per item

Ordered by (harm prevented ÷ size). G3 first because it is what made the rest invisible.

| id | Task | Depends on | Status |
|----|------|-----------|--------|
| T13 | G3: `cc-notify --role` non-zero on dead target + sweep records `channel:"dead-target"` | — | open |
| T14 | G1: FF-GATE arm denying `git commit` in the shared checkout, with a named escape hatch | — | open |
| T15 | G2: edge-trigger converge from `post_release_finish()`, guarded on `git cherry` empty | — | **BUILT** — `converge_kick()` in `scripts/ship-land.sh`, 11 cases in `tests/ship-land.bats` |
| T16 | G4: overlay daemon self-retire on source-sha change, gated on `not st["on"]` | — | open |
| T17 | Re-mint `/tmp/resident-reload-flip.sh` for packet `4194644aea26` | — | open |

### T15 as built — what it does, and the four things it deliberately does NOT do

`post_release_finish()` now calls `converge_kick()`, the DEPLOY sibling of the postland-verify kick
already beside it: detached, guarded, and structurally unable to fail a land. The clock is untouched
and remains the backstop for a land that died before reaching that line, and for the tail of a burst
the interval floor skips.

**Does:** skip when `git cherry origin/main HEAD` in the shared checkout is non-empty — and when it
skips, prints the G1 divergence to the LANDER'S OWN TERMINAL, named, with the inspect command and an
explicit "YOUR LAND IS FINE", because that is a surface someone is reading at that moment and the
page channel G3 measured is not. Then, at most once per `SHIP_LAND_CONVERGE_KICK_MIN_S` (default
600, the tick's own period), it writes one marker line to `deploy.log` and spawns
`deploy-live.sh --auto` detached, stdin closed, both streams appended to that same log.

**Does NOT relax the lag budget.** `CC_DEPLOY_MAX_LAG_COMMITS=0` is the *agent's* standing-converge
lever (`.claude/CLAUDE.md`), taken by a session that is present and attributable. Baking it into
every land converts it into unattended standing policy — every land advancing the live layer on
ABSENCE of evidence — which is a fleet behaviour change and a C10 decision, not a trigger's. A test
pins that the spawn passes neither lag variable, so a later "helpful" edit reddens.

**Does NOT use the bare form.** It looks safer (`refusal_bump()` is `--auto`-gated) and is not: the
refusal page at `deploy-live.sh:2336` is keyed on the TIP SHA and damped only under `--auto`, and a
land MOVES the tip — so a bare-form kick would mint a FRESH page file per land through any green
famine, straight into the channel G3 says is already drowning. Accepted residual, stated: `--auto`
makes this the second writer of the unlocked single-line `REFUSALS_FILE`; a collision loses one
increment and delays an R7 escalation by one tick. That is strictly cheaper than a page per land.

**Does NOT serialise against the launchd tick, and cannot.** `deploy-live` has no run lock — checked,
not assumed (`deploy-live.sh:180`: *"What serialises them is launchd, on the timer path only"*). The
`mkdir` lock here covers the interval STAMP only, so two concurrent landers cannot both read the old
value and both fire; the floor is what bounds the population this adds (the lane now ticks on a 600 s
clock OR a land, whichever comes first, so the `--auto` call rate at worst doubles). Overlap with a
tick remains possible and is the same exposure already accepted for `scripts/deploy-now.sh`.

**What is NOT established, and is not establishable off-box.** This was built in a cloud VM with no
access to the operator's `deploy.log`, land ledger or launchd state, so the *size* of the win is
unmeasured. Specifically: the kick can only beat the clock by up to 600 s **if the clock is
delivering its requested cadence** — `com.claude.deploy-live` is `ProcessType Background`, which the
plan's own T8 finding notes is the one job the CPU-band repair skipped, and a requested cadence is a
request to a scheduler, never an observation. The honest claim is therefore structural, not
numeric: the converge now has a caller wired to the EVENT that creates the work and independent of
launchd entirely, which helps whether the timer is healthy or being coalesced. **The re-measurement
that settles it** (on-box, after this is live for a few days) is: count `converge edge-trigger` lines
in `deploy.log` against `deployed` lines over the same window, and re-derive the hand-run share the
way `.claude/commands/ship.md:124` does — resolved-SHA ffs in the checkout's reflog against
`deployed` lines. If the marker count is ~0 while advances continue, the kick is being skipped (read
the floor and the cherry guard, in that order) rather than the timer being the problem.

## Record

- 2026-09-17 created. Wave A1-A10 dispatched; 9 reported, T4 (gate-green) outstanding.
- Divergence that blocked the converge at wave start (`145c32f53`) cleared itself when its
  author landed it; checkout returned to 0-ahead/0-behind without intervention.
- 2026-09-17 T15 built off-box (cloud). 11 new cases; **6 red-proved** against trunk's
  `ship-land.sh`. The rest are the no-op/degrade arms and are green in BOTH arms by construction —
  equivalence guards, not red-proofs — so each is instead pinned by a MUTANT: **12 mutants run, 12
  killed** (bare form · relaxed budget · cherry guard removed · floor removed · floor fails open ·
  kill switch ignored · git-repo check removed · `-x` check removed · streams inherited ·
  `Popen`→`call` · lock removed · stale-reap removed). The last two are a discriminating PAIR: each
  kills exactly one of the two lock cases and leaves the other green, which is what separates "the
  lock defers to a live holder" from "a leaked lock is reaped" — two states that are the same
  directory on disk.
  The streams-inherited mutant is the one that earned its keep: it SURVIVED the case originally
  written for it, because a detached child writes after bats' `run` has already collected — that
  case was vacuous by construction and was replaced with one that pins the reason for detaching (a
  slow `deploy-live` must not delay the land), which the `Popen`→`call` mutant kills.
  **The stale-lock reap exists because of that same review pass**, not because a test asked for it:
  the first draft's `mkdir "$lock" || return 0` meant a lander group-SIGKILLed inside the
  millisecond critical section would leave a directory that latched this box's converge lane OFF
  permanently — and silently, since a kick that never fires is indistinguishable from a kick with
  nothing to do. That is the fail-safe-mimics-healthy shape, in a guard added to make things safer.
- 2026-09-17 **What was verified off-box, and with what instrument** — stated because a cloud VM is
  not the operator's box and the difference matters in one direction. Ran: `bash -n`; shellcheck
  **0.11.0** (the gate's version, fetched for this — clean, rc 0, and the LOCAL 0.9.0 is red on
  trunk too, so the differential and not the absolute is what carries); `bats-assert-liveness.py`
  clean; test-hermeticity / test-walltime / utc-stamp lints clean over the whole `tests` tree;
  `bats-shellcheck-lint --range` clean; `unattended-path-lint` **77 findings on this branch and 77
  on a pristine `origin/main` worktree, none naming either changed file**. Full `tests/ship-land.bats`
  A/B against that same pristine worktree: trunk **11 failing**, branch **10 failing**, and the
  branch's failing set is a strict SUBSET of trunk's — **zero branch-only failures**. Those shared
  failures are this Linux VM, not the tree (`sysctl hw.ncpu`, `/usr/sbin`, an absent-shellcheck
  expectation, postland stamps), which is exactly why the claim is made as a differential rather
  than as a suite verdict. NOT verified here and not verifiable here: any behaviour of the real
  `deploy-live.sh` against the real shared checkout — the tests drive a recording stub, by design.
- 2026-09-17 **`scripts/ship-land.sh` LINE-SHIFT MAP** for T15's insert, computed from the diff
  hunks rather than eyeballed. Old line **< 1467** → unchanged · **1467–1557** → **+151** ·
  **≥ 1558** → **+156**. Fourteen `ship-land.sh:NNNN` citations exist across the tree; one grep
  establishes that **every one of them is prose in a comment or a dated plan — none is an executed
  lookup**, so nothing breaks and the map is published here instead of rewriting eight files this
  row does not otherwise touch (scoping a re-pin by LIVENESS, not by count). The one citation
  inside a file this diff already owns was re-keyed off its number entirely — and it had ALREADY
  rotted on trunk, pointing at a `typed-send-lint` comment rather than the `DEAD_LINT` block it
  names, which is the argument for a stable anchor over a number in anything meant to outlive one
  commit.
