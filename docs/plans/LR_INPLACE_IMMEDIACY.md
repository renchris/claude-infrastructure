---
status: in-progress
---

# LR in-place immediacy — make an in-place account move take seconds, not hours

Scope (frozen): measure and root-cause why in-place account moves take tens of minutes to hours instead
of seconds, then land fixes that make an idle healthy session's in-place move to a named account complete
in well under a minute even on a loaded box, each fix with a red-then-green bats test; report the
before/after numbers.

Report: `docs/research/lr-inplace-immediacy-2026-10-18/REPORT.md` (evidence in `raw/`).
Origin: fired by session 620db313 (pane 344) after 2h20m moved ~5% of 15 sessions, 2026-10-17T23:45Z.

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave:**
  - W0 evidence: **L** + unnamed read-only subagents (B-H). Why L: the lead is itself the dispatched
    session for this wave and holds the synthesis.
  - W1 fix wave: **T** (named teammates, one worktree each, inside this dispatched session). Why T: the
    lead IS the wave's dispatched session; members share one lane and must be merged against each other.
  - F1 (mid-tick drain): **L**, one subject file plus its suite, landed first so the goal's top fix is not
    queued behind the team.
- **Lead context budget:** keep ≥50% for synthesis; succession point = after W1 merges and lands,
  recycle with the plan + report on disk if any wave remains.
- **Ownership (one owner per file):**

| Teammate | Worktree / branch | Owns | Fixes |
|---|---|---|---|
| lead | lr-inplace-immediacy | lr-reset-poller.sh, tests/lr-move-drain.bats, the report | F1 drain |
| admit | lri-admit | lr-move-batch.sh (except :245-252), lr-intent.sh, tests/lr-move-admit.bats, tests/lr-intent.bats | A1 intent at admission · A2 act-by from admission · A3 wall-clock admit wait · A4 steal race + router reason |
| cclr | lri-cclr | bin/cc-lr, lr-upgrade.sh census selector, lr-move-batch.sh :245-252, tests/lr-move-plan.bats | repeated --sid / --sids in priority order, mixed-source batch |
| (next) | — | lr-move-worker.sh, lr-move-lib.sh | intent re-check during waits, priority slot ticket, load pre-gate, cheaper verdict reads |
| (next) | — | lr-handoff.sh | kitty-unreachable retry with backoff, name an expired intent |

- **Merge order:** F1 (landed first) → cclr → admit (smallest diff first; both touch lr-move-batch.sh in
  disjoint hunks) → worker → handoff. Gate each merge with shellcheck (bare) + the touched suites.

## Decisions

- Mid-tick drain is a background subshell of the tick, not a new LaunchAgent: every launchd job here needs
  an operator-run activation script (`launchd/fleet.manifest` "activate" column; com.reso.* plists are not
  loaded by install.sh), so a new agent would not be live on converge. The subshell keeps the launchd
  environment and the "never the requester's child" rule of design-swap-v3 §4.2.
- Supersede-not-collide is not built: every observed collision (10 rows) was a holder whose intent had
  expired before its batch started (G §3); A1 removes those holders. A newer request colliding with an
  older VALID waiter is redundant, not lost.
