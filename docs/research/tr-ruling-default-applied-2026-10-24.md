# TR ruling: the class-B default fired, and trunk already carries it (2026-10-24, cloud session)

Item `9b906bcc1011`, "class-B default fired: Retry only, keep the wait". Decision `db44ab0ebc55`
(the typed-relaunch hold, plan closure TR; filed in `docs/plans/LR_SUSTAINED_LOAD_IMPL.md`, the
`cc-decide open` line under "Operator decisions and actions"; deadline 2026-10-24T17:00:00Z).
Run off-box (Anthropic VM, `CLAUDE_CODE_REMOTE=true`), so no live state, kitty or rig was reachable.

## Verdict

**DONE, no code owed.** The default option was "Retry only, keep the wait": retry the successor
stage once, then keep the 24/20 per-core load hold. Both halves are already on trunk in W12b
part 1, `ac25e898e` (`git merge-base --is-ancestor ac25e898e origin/main` → rc 0):

| Half of the ruling | Where on trunk | State |
|---|---|---|
| Retry | `hf_succ_stage_retry` (`scripts/handoff-fire.sh`), called from `hf_recycle_load_gate` before any hold | ON by default; kill switch `stage-retry.off` / `HF_STAGE_RETRY_GATE=off` |
| Keep the wait | `hf_typed_relaunch_hold_mode` prints `load` when neither the env seam nor `typed-relaunch-hold.mode` says `terminal` | code default `load` = the 24/20 per-core comparison |

Part 2 of W12b was "the default flip follows the ruling". Under this ruling there is nothing to
flip: the default stays `load`. The `terminal` key stays in the code, opt-in by mode file, for a
future re-ruling, because removing it would be work the ruling did not ask for.

**What changes because of the ruling.**

- The `debt:typed-relaunch` rows in `tests/rig/g1-allow.tsv` (lines 25-28) **stay**. The ruling
  keeps the load wait, so it is an accepted debt, not one waiting on a flip. `tests/lr-guarantee-g1-lint.bats:415`
  pins one of those rows, so removing them would redden that suite.
- The owed Tier-L run "W4's typed-relaunch group shows 0 HOLD-LOAD under `terminal`" is no longer
  a W12b Done criterion. It belonged to the "Retry, then check the terminal" option. Run it only
  if the decision is reopened.
- The residual the ruling accepts, stated rather than hidden: a move whose stage is still refused
  after the retry still waits for load to fall below 24/core (20 at the precheck). At 15-40/core
  that wait can last a long time, and W8 pages it as HOLD-LOAD. The option text gave the size: "none of 48 since 10-18" moves
  reached the unstaged path.

## What was run

- `git fetch --unshallow`; `git rev-list --count HEAD..origin/main` → 0, so this tree is trunk.
- `git rev-parse origin/main:bin/cc-dispatch` → `91998d21fe1f…`, EQUAL to the brief's dispatcher
  blob, so the dispatcher that fired this session is trunk.
- `git merge-base --is-ancestor ac25e898e origin/main` → rc 0.
- Read `hf_typed_relaunch_hold_mode`, `hf_succ_stage_retry` and `hf_recycle_load_gate` on trunk.
  `git log ac25e898e..origin/main -- scripts/handoff-fire.sh` shows later commits only in
  self-close, pane-close, origin-identity and kalloc. None of them touches these three functions.
- Not run: the bats suites (`bats` is not installed on this VM). No code changed, so no suite's
  input changed.
