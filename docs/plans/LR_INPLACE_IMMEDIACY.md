---
status: complete
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
## W2 — after W1 merges (succession point: recycle/hand off here if context > ~60%)

Follow-ups to send to W1 teammates after their first report (each red-then-green):
- cclr: (a) lru_switch_census: for a sid/sids selection, filter on the sid BEFORE the per-row jq forks
  (lr-upgrade.sh :1012-1030, :1088-1100) — the plan-time census ran 3.0-3.4 min under load (raw/D §3d);
  (b) lr-move-batch.sh :245-252 WATCH census narrowed to the waiting rows' sids (repeated --sid) —
  one census is 19-27 CPU-s and 6-10 min wall under load (raw/F); (c) plan.json gains
  `router_ranked_epoch` when cmd_move's strict router check ranked the target.
- admit: reuse plan.json `router_ranked_epoch` at admission when younger than LR_MOVE_ROUTE_REUSE_S (120 s);
  the router read was 5-132 s, 323 s with --fresh (raw/G §2.1). The close-time --fresh re-read stays.
- worker Part 2: (a) load pre-gate before W3: while load/core > hf_recycle_load_bound's bound (same env
  chain HF_RECYCLE_HOLD_LOAD_PER_CORE → CC_GATE_MAX_LOAD_PER_CORE → 8; CC_FIRE_CAPACITY_GATE=off bypass),
  wait holding the claim but NO slot, poll 10 s, until the intent check fails → NOTMOVED "load: …";
  (b) lr_session_location fast path: try <store>/projects/<slug(cwd)>/<sid>.jsonl per store first, glob only
  on a miss (verdict = 1.0 CPU-s/call, globs ~18,200 dirs × 4 stores; prove ran 604-685 s after rc 6);
  (c) W2 ends when the row is gone from two consecutive snapshots (raw/E R1: ghost waits 9-28 min);
  (d) false STRANDED: a holder found by the plan row's pid (+ its CLAUDE_CONFIG_DIR) is not "no live process"
  (e3dedc17 alive with no registry row).

New work (not yet assigned):
- Band: the whole move lane runs at pri 20 (launchd's default light limits on com.reso.lr-reset-poller;
  no ProcessType) while the load runs at 31; a child cannot climb back to 31 (measured: taskpolicy -a
  from a utility-clamped parent stays 20). Remedy candidates: (1) a staged com.reso.lr-move-kick
  LaunchAgent (ProcessType Interactive, WatchPaths move/requests) that runs only the kick, with the
  census explicitly clamped `taskpolicy -c utility`; operator activation script; (2) ProcessType on the
  poller itself (lifts its heavy arms too — rejected). The positive-control probe (throwaway launchd
  jobs) was refused by the removal safety check this session; the activation script must verify pri.
- Load hold decision (operator, file with cc-decide): keep 8/core (+K3 fail-fast + worker wait) vs raise
  to 24/core (raw/H: 0 failures in 11-18 hardened recycles at 8-32/core; none measured above 24.6;
  rule-of-three bound <27%) vs build keystroke-free resume relaunch (makes the bound moot).
- Keystroke-free resume relaunch design: stage a gated successor before /exit (the stage blocks on a
  go-file the watcher writes after its fold/launch-lock/holder rails) — a design + skeptic wave.
- Rescue verb gap: lr-fleet --one refuses to relaunch into its own husk shell (pane 344, e739e5b5).
- Holds (out of the idle-session scope): E R2 (carry sleep-only jobs on a healthy source — operator
  ruling, narrows 1b97389dd), R3 (goal hold keyed on goal activity), R4 (requester's own cc-lr move
  as the holding job).

## W1 merge + W2 execution (2026-10-18, successor lead, session 74ba67f2)

- **Execution locus:** W1 merge **L** (lead-inline: a cherry-pick + gate of finished branches). W2 **T**:
  five named teammates in worktrees `lri2-{census,batch,verdict,goal,drafts}` off the merged tree
  `c54950eea`. Why T: one lane, five disjoint hunks, merged against each other. Lead context: kept the
  merge, gate, A/B and report; succession point = after the W2 land.
- **W1 merged** (cherry-picked, smallest first): cclr `d3e4c07e8` · worker W1+fixup autosquashed
  `6095d2cd4`, W3 `cf4adc3d4` · pane 374's `69ed4dae1` as `825d5fc44` (-x; conflicts kept both: the
  intent re-check and the load re-check after the kernel read; the claim released once, right after the
  result mv; `intent_recheck` added inside the load wait) · admit A1 `05216bb90` · handoff K2/K1/K3/K4
  `a21849eb1 46240c952 552b997b6 c54950eea`. Gate on the merged tree: see REPORT §5.
- **Lead-built:** `6459508f5` the `--move-kick` mode + staged `com.reso.lr-move-kick` (Interactive band,
  WatchPaths) + `53-lr-move-kick-activate.sh` (reads the priority back from a real run). Activation is the
  operator's (filed). Load-hold decision filed `600709c5fe4b` (class C, conviction 70).
- **W2 owners:** census = lr-upgrade census prefilter, watch census narrowed to waiting sids,
  `LRU_SELF_SID=` pin + `taskpolicy -c utility` clamp on lr-move-batch.sh's census calls · admit2 = A2
  act-by sidecar, A3 wall-clock admit wait (900 s), A4 rename-and-verify steal + ROUTE_WHY reset,
  `router_ranked_epoch` reuse · verdict = known-path transcript read, ghost waits end on two absent
  snapshots, no false STRANDED on a live pid · goal = goal hold keyed on goal activity (operator ask 6a,
  `c6ebf58a8`) · drafts = stale drafts carried, junk discarded, live typing waits (operator ask 6b;
  opt-in `HF_RCY_CARRY_STALE=1` inside hf_rcy_carry_eligible approved by the lead).
- **Learnings:** under load ~200 a bats case can take minutes; gate the merged superset once and A/B each
  red on a detached control worktree run at the same moment, not branch by branch.

## W1 + W2 — DONE (2026-10-18)

- **W1 landed at `552b3129b`** (the shas in REPORT §5 rows 1-8). K4 dropped at the rebase: pane 374 landed
  the same fix in its own hunk (`467c9c45c`, `52d4a9809`, `08f8971f2`).
- **W2 landed at `033e972eb`** (REPORT §5 rows 9-15). `census` and `verdict` stopped answering mid-wave,
  so the lead built census fix 4 (utility clamp, `8835fc9fc`) and V4 (limit read at the cwd slug,
  `033e972eb`) inline.
- **Live:** both converged with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`. The
  Interactive-band starter is staged; its activation is the operator's (backlog `074a5990b2cd`).
- **Filed, not built:** the load-hold decision `600709c5fe4b`; replacing launcher-started panes, decision
  `56c6862291f2`; cap-triggered fan-out `bbf8b34403bb`. Reported to pane 374: the tee race at
  `lr-handoff.sh:1981` (REPORT §6 item 7).
- **Learnings:** four land attempts were red, each on a single text ratchet that a green suite run cannot
  see (AF_UNIX bind, dead assertion, hermeticity seams, `.bats` shellcheck). Run those four lints on the
  changed suites before the first `/ship` (docs/lessons/run-the-test-ratchets-before-the-land.md). An
  idle in-process teammate can stop answering mail; after ~1 h of silence, harvest its commits from its
  worktree and finish the item inline.
- **Next (not this scope):** the keystroke-free resume relaunch (REPORT §6 item 3) and the ~3 min
  successful-move floor (§6 item 4) are the remaining distance to a sub-minute move.
