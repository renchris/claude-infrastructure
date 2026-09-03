# Harvested deliverable — `r-goal`

Recovered by `cc-agent-harvest` from the member's own transcript (`280bb416-2c1f-4cc3-ab75-a1c5ca4130e2`), because a named `Agent` spawn returns no value to the lead.
Model: `claude-opus-5` · backend: `iterm2` · final block: 2026-09-03T17:45:04.722Z · substantive blocks: 1

Verbatim, unedited.

---

Findings written to the contracted path. Both items verified at `origin/main` @ `24c598bac`; nothing edited.

**`0f4147dcb20b` — DRIVABLE, no operator decision.** Gate 2 (`goal-inert-watch.sh:128`) demands the newest `goal_status` attachment be the arm sentinel, so one evaluation permanently silences the hook — both arms are downstream of it. Measured the real record shape over **1,511 attachments in 626 transcripts** across all four account roots: sentinel and evaluation are cleanly distinguishable (`sentinel` only on arm/clear, `reason` only on evaluations, zero ambiguous records), and evaluations are timestamped on the **envelope**, not the attachment. The blind spot is real and quantified — **25 windows where a live goal went ≥2 turns unevaluated with a non-sentinel newest record, 12.6 % of all inert windows**. The remedy is a one-predicate swap: `hooks/lib/goal-state.sh`'s `goal_live_condition` is exactly the needed relaxation and `goal_liveness` already returns the eval count and epoch — the hook currently sources neither and hand-rolls a near-copy of both. The `≥2 turns` threshold is derived from the interrupt argument already in the file's own header, not chosen; wall-clock age would be wrong (idle sessions).

**`61a3b40d8695` — DRIVABLE, but it carries one design fork.** Both halves confirmed (`_gi_abstain` is a bare `exit 0` at `:92`, 10 call sites; `wake_floor:416-697` has zero `log_idl` — its only trace is stderr). Enumerated **13 exit paths / 15 dispositions** for wake_floor. Three findings the item did not anticipate:

- **`ship_floor` has the same defect** — 17 exits, logs 1. Three arms, not two.
- **The wake_floor blocker is not a consumer, it is a landed decision**: `session-continue.sh:53-57` deliberately forbids logging the disarmed steady state, and `tests/session-continue-telemetry.bats:75-78` pins `idl_count -eq 0` on exactly the path the floors run on. Its volume premise is now measurably weak (~30 fleet Stops/day vs 63k IDL rows/day), and option 1 in the writeup — log only the 9 decision-bearing exits and re-scope that test — avoids the reversal entirely.
- **The goal-inert-watch risk is the reason vocabulary, not row counts.** Logging *enrolls* a hook that is currently absent from every table. `idl-abstain-alarm` (the only wired pager) defaults unlisted reasons to DORMANT, so it stays green — provided the tokens avoid its blind set. `cc-audit` would alarm (no reason-class awareness) but has no automated caller and already alarms on three hooks today. `hooks/desk-brief-inject.sh:25-35` is the exact landed precedent for this cure.

Recommendation: ship the goal-inert-watch gate relaxation and its IDL wiring in **one** diff — the relaxation changes which exit paths exist.
