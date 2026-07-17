---
name: frontier-routing
description: >-
  The frontier-tier model ROUTING discipline — when to use versus avoid the frontier model (currently Fable 5, the tier ABOVE the Opus 4.8 default) and the full bounded-autonomy escalation policy. Load when choosing a model tier for a spawn, when work hits a wall that might warrant frontier escalation, or at session wrap-up with open holes. Rules: frontier is opt-in and its value is EXCLUSIVELY the delta above the default tier (unknown-unknowns the default is blind to), NEVER routine or already-identified work; the human never model-switches or starts frontier sessions, so the agent escalates autonomously but BOUNDED (hook-enforced per-session spawn cap in frontier_discovery_budget — a blocked spawn means PARK, never retry); capture holes via /frontier-hole, escalate via /frontier-run (inline ≤2 panelists on a blocking wall, batch at wrap-up when OPEN holes ≥2 and window active), long-horizon generator-class problems via /frontier-campaign; feed the supply side every session (wrap-up seam scan, telemetry-residue sweep, exogenous triggers); the lead itself never runs on the frontier model. SSOT: ~/.claude/model-config.yaml (frontier_access window/roles/budgets). Ledger: per-project docs/research/FRONTIER_HOLES.md. Triggers: "should I use Fable/the frontier model", model-tier selection for a spawn, an unexplained-behavior/adversarial-undecidable wall, session wrap-up with ≥2 open holes. This is the routing POLICY (WHEN to reach for the frontier tier) — NOT the action commands /frontier-hole (capture), /frontier-run (panel), /frontier-campaign (long-horizon), which it points to.
---

## Frontier Tier Routing (All Projects)

**Default model = Opus 4.8 @ effort max** (`roles.lead_default` in
`~/.claude/model-config.yaml`). The frontier tier (currently Fable 5) is
**opt-in only**: its value is exclusively the delta above the default tier —
unknown unknowns the default tier is *blind to* — never already-identified
problems or routine work. Standing agent duties, every session:

1. **Never select or propose the frontier model for identified/routine work** —
   including subagent spawns outside the SSOT's conditional slots
   (`research_adversarial` / `workflow_judge` / `eval_judge` / `teammate_frontier`).
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
   (concurrent-session lock); the lead itself never runs on the frontier model.
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
