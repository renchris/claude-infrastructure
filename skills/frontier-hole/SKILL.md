---
name: frontier-hole
description: Capture an unknown-unknown candidate (a "frontier hole") for the frontier-tier model (currently Fable 5) WITHOUT burning frontier tokens inline. Use PROACTIVELY — agent-initiated, no user prompt needed — the MOMENT mid-task work hits a qualifying wall — unexplained behavior after real investigation, an adversarial verify that couldn't decide, or a never-derivation-swept seam between subsystems. Also on user phrases "park this for Fable", "log a frontier hole", "that's beyond Opus", /frontier-hole. NOT for ordinary identified bugs or tasks (those go to the normal worklist; default-tier work solves them).
---

# frontier-hole — park an unknown-unknown for the frontier window

Routine work runs on the default tier (Opus 4.8 @ max — `lead_default` in
`~/.claude/model-config.yaml`). When something *smells beyond that tier*, do NOT
switch models, spawn frontier agents, or keep grinding inline — capture a
structured hole in the project ledger and move on. `/frontier-run` spends the
frontier window on the queue deliberately, in batch, where the 2× cost buys
discovery instead of routine effort.

## Qualifying bar (ALL three — else it's a normal worklist item, not a hole)

1. **Not an already-identified problem.** If the bug/feature is named and scoped,
   the default tier handles it. Putting the frontier model in front of
   already-solved or already-identified problems wastes the window — its edge is
   only on what the default tier is *blind to*.
2. **A default-tier wall was actually hit**, one of:
   - **Unexplained** — observed behavior contradicts the system model after a
     real investigation (not after one failed grep);
   - **Undecidable** — an adversarial verify panel split or could not refute;
   - **Unswept seam** — a composition of ≥2 subsystems whose joint invariant
     lives only in prose and has never been derivation-audited. Highest-yield
     class per the 2026-06-09 Fable panel (memory:
     `feedback-frontier-window-baseline-blind-derivation-2026-06-09`).
3. **A falsifiable question can be stated** — what exactly would the frontier
   model confirm or refute?

If genuinely unsure whether it qualifies, capture it anyway with
`Confidence: low` — a ledger line is free; inline frontier tokens are not.

## Action

1. Ledger = `docs/research/FRONTIER_HOLES.md` (repo-relative). If missing, create
   it with a `## Open` and a `## Resolved` section plus a 3-line header pointing
   at this skill. If present, **Edit/INTEGRATE — never overwrite**.
2. Grep the ledger first; update an existing hole rather than duplicating.
3. Append under `## Open` (≤40 lines, this exact heading shape — the
   SessionStart hook counts `^### H-\d.*OPEN`):

   ```markdown
   ### H-<next-number> · <one-line hole> — OPEN <YYYY-MM-DD>
   - **Seam/axis**: <subsystems involved + file:line anchors>
   - **Wall**: unexplained | undecidable | unswept-seam — <one sentence>
   - **Falsifiable question**: <what the frontier model must confirm/refute>
   - **Default-tier attempts**: <what was tried/ruled out — so the panel doesn't redo it>
   - **If true, changes**: <impact on architecture/priorities>
   - **Confidence frontier-worthy**: high | low
   ```

4. Report the hole ID in one line, then fork on whether the wall BLOCKS the
   current task:
   - **Non-blocking** (the usual case): STOP here — no model switching, no
     spawning. The hole runs in a wrap-up or later session's batch via
     `/frontier-run`.
   - **Blocking** (the task cannot proceed correctly without the answer):
     invoke `/frontier-run` yourself NOW on this one hole (inline path, ≤2
     panelists per `frontier_discovery_budget.inline_blocking_max`), then
     continue the task with the verdict. The lead still never model-switches.

## Proactive use (agent-initiated — the normal case)

This skill exists so the AGENT leaves holes for the frontier tier during
routine work; a human typing `/frontier-hole` is the fallback, not the design.
When the bar is met mid-task: capture (≤2 minutes), then apply the fork in
step 4 — non-blocking holes wait for a batch; a blocking hole escalates inline
immediately via `/frontier-run`. Either way, include one line in the final
message — e.g. *"Parked H-007 (CVR × offline-queue seam); runs in the next
wrap-up batch"* or *"H-007 blocked the task — escalated inline, verdict
folded in."* At main-task wrap-up, if OPEN holes ≥ `batch_min_open_holes` and
the window is active, run the batch yourself per `/frontier-run` — the human
never triggers this.
