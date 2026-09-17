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

| id | Task | Depends on | Outcome |
|----|------|-----------|---------|
| T13 | G3: `cc-notify --role` non-zero on dead target + sweep records `channel:"dead-target"` | — |
| T14 | G1: FF-GATE arm denying `git commit` in the shared checkout, with a named escape hatch | — |
| T15 | G2: edge-trigger converge from `post_release_finish()`, guarded on `git cherry` empty | — | **DONE** — `tests/ship-land-converge-edge.bats`, 9/9 green with the diff and 9/9 red on pristine trunk. ONE REFINEMENT AGAINST THE SPEC, and it decides whether the guard works at all: the predicate is read with `git -C $DEPLOY_REPO`, **never in the lander's own worktree**. `merge --ff-only` compares ANCESTRY in the SHARED CHECKOUT, so that checkout is the only repo whose divergence can block the advance; the lander's HEAD is by construction ahead of its own origin at this point (it is what just landed), so reading `git cherry` there would answer a different question and skip every time. Case 6 pins exactly that. Failure direction is deliberate — a stale ref, an unreadable repo, `core.bare=true`, or no git at all each yield non-empty output or a non-zero rc, and every one of them SKIPS while the 600 s timer still converges. Concurrency needed no new lock: `deploy-live.sh:180` already records that the non-timer path can overlap a host phase and that the overlap "costs load, not correctness". Kill switch `SHIP_LAND_CONVERGE=off`. |
| T16 | G4: overlay daemon self-retire on source-sha change, gated on `not st["on"]` | — |
| T17 | Re-mint `/tmp/resident-reload-flip.sh` for packet `4194644aea26` | — |

## Record

- 2026-09-17 created. Wave A1-A10 dispatched; 9 reported, T4 (gate-green) outstanding.
- 2026-09-17 T15 (G2) landed. The edge trigger closes the 40.1%-by-hand figure at its source: every
  land that leaves the shared checkout fast-forwardable now kicks the degraded-tier converge
  itself, so the clock becomes the backstop rather than the mover. What it deliberately does NOT
  do is cure a DIVERGED checkout — that is G1's subject, and until G1 lands a diverged checkout
  turns this trigger into a warning on every land rather than an advance. The two gaps are
  therefore coupled in one direction: G2's value is bounded by how often G1's defect occurs
  (measured: 63 commits in 36 days).
- Divergence that blocked the converge at wave start (`145c32f53`) cleared itself when its
  author landed it; checkout returned to 0-ahead/0-behind without intervention.
