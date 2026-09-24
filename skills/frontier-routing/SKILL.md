---
name: frontier-routing
description: "Policy for when to use the frontier model (Fable) instead of the default tier: only for unknown-unknowns after research stalls, inside the hook-enforced spawn cap. Points to /frontier-hole, /frontier-run and /frontier-campaign."
---

## Frontier Tier Routing (All Projects)

**Default model = `roles.lead_default` @ `effort_defaults.default`** (both in
`~/.claude/model-config.yaml`). The frontier tier (`versions.frontier_latest`) is
**not opt-in and not a default — it is the third branch of Follow-On Gate F2**
(CLAUDE.global.md § Frontier Tier Routing): its value is exclusively the delta above the default tier —
unknown unknowns the default tier is *blind to* — never already-identified
problems or routine work. Standing agent duties, every session:

1. **Never select or propose the frontier model for identified/routine work** —
   including subagent spawns outside the `roles.*` the SSOT pins to
   `versions.frontier_latest` (read the list there live; it is not restated here).
2. **Capture frontier holes proactively (agent-initiated).** The moment work hits
   a qualifying wall — behavior unexplained after a real investigation, an
   adversarial verify that cannot decide, or a never-derivation-swept seam
   between ≥2 subsystems — invoke `/frontier-hole` yourself. Never grind on
   inline; never `/model`-switch the lead session.
3. **Escalate to the frontier tier autonomously, bounded** (user policy
   2026-06-09: the human NEVER model-switches or starts frontier sessions —
   if the agent doesn't escalate, nobody does). Two triggers, both
   agent-initiated via `/frontier-run`:
   - **Blocking wall** — the current task cannot proceed correctly without the
     answer: escalate NOW. ≤2 fresh-context `frontier-derivation` panelists on
     that one hole (`model: "fable"`), then continue the task with the verdict.
   - **Batch at wrap-up** — main task complete, OPEN holes ≥ 2, window active:
     run the panel, write the report, update ledger statuses.
   Hard bounds (non-negotiable): the per-session spawn cap in
   `frontier_discovery_budget` is hook-enforced — a blocked spawn means PARK,
   never retry; mark each hole `IN-PANEL` in the ledger BEFORE spawning
   (concurrent-session lock); the lead itself never runs on the frontier model —
   **except stage 2 of the escalation ladder**, where the lead RECYCLES ONTO it to
   write a document and recycles back (CLAUDE.md § Frontier Tier Routing; design +
   the three trigger conditions T-a/T-b/T-c in
   `claude-infrastructure/docs/plans/NONLIMIT_RESUME_LADDER.md` § W3). The premise of
   the blanket form was prompt-cache cost, which a fresh process does not pay. The cap
   now counts that fire too (hooks/frontier-spawn-gate.sh session arm), so the carve-out
   is bounded rather than an exemption.
4. **Feed the supply side — discovery must not wait for walls.** Standing
   default-tier sources, outputs routed to the ledger (anti-capture filter
   applies): (a) wrap-up scan — did this session expose an unswept seam or a
   generator candidate (a solution dissolving ≥3 *named* worklist items)?
   (b) telemetry-residue sweep — periodically mine sub-alarm production deltas
   (rum-compare / Loki / Logs Insights); an unexplained delta is by
   construction an undiscovered problem; (c) exogenous triggers — dep bumps,
   platform shifts, calendar load events open seams regardless of code churn.
   Panels emit falsifiable runtime predictions; the lead runs the cheap probes
   — a missed prediction means the system MODEL is wrong: open a hole on that.
5. **Long-horizon campaigns** (generator-class unsolved problems) go through
   `/frontier-campaign`: Fable as bounded ARCHITECT/JUDGE over default-tier
   implementer teammates with lead acks between phases — never an autonomous
   Fable implementation monolith. One concurrent campaign (SSOT).

SSOT for window/roles/effort/budgets: `~/.claude/model-config.yaml`. Ledger
(holes + seam registry + campaign candidates): per-project
`docs/research/FRONTIER_HOLES.md`.
