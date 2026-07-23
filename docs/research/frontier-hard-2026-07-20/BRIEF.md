# Frontier-hard problem portfolio — restructured mission brief (2026-07-20)

**You are:** Fable 5 @ max reasoning, lead synthesizer. Fired via /handoff by the wave-shepherd
session (desk-checkout, account `next`) on operator instruction: *"investigate what are the most
complex problems in our application and architecture that require the highest-frontier-intelligence
(you, Fable 5, max reasoning) to build, improve, and solve"*. "Our application and architecture" =
the claude-infrastructure system: this repo (bin/ hooks/ scripts/ launchd/ skills/) + its live
deployment (~/.claude layer, ~/.claude/autonomy, launchd jobs, the running 4-account fleet).

**Deliverables (the frozen DoD):**
1. `docs/research/frontier-hard-2026-07-20/SYNTHESIS.md` — the ranked frontier-hard portfolio.
2. `docs/research/FRONTIER_HOLES.md` — INTEGRATE new holes (unknown-unknowns) + campaign
   candidates (generator-class / capability-ceiling) in the file's existing format. NEVER overwrite
   history; extend C-DSH-1/2, don't re-derive them.
3. Wave reports + this brief + synthesis committed on YOUR branch, landed via the project-local
   `/ship` (standing-land authorized in `.claude/CLAUDE.md` — no fresh ask needed), then a compact
   operator summary in chat.

## Inputs

**A. The 13-axis evidence wave** (launched ~00:30Z by the predecessor; deep-research/Opus except
axis 8 = Fable derivation panelist). Reports land INCREMENTALLY at
`/Users/chrisren/Development/claude-infrastructure/docs/research/frontier-hard-2026-07-20/` (the
SHARED checkout — readable from your worktree; copy files into your worktree before committing):
`fr-01-dataplane` (backlog/dispatch/wave-plan consistency) · `fr-02-liveness` (signal→state
inference, undecidable residue) · `fr-03-actuation` (tty-fire taxonomy, substrate verdict) ·
`fr-04-authority` (4-layer permission model, classifier SPOF, delegation formalism) ·
`fr-05-economics` (quota/value scheduling, auth-lifecycle) · `fr-06-verification` (claim→truth,
a19 escapes re-run) · `fr-07-discovery` (self-improvement blind spots, rule→enforcement gap) ·
`fr-08-collapse` (ADVERSARIAL derivation: content→action trust chains, file-IPC, SPOFs,
law-composition deadlocks) · `fr-09-census` (patch-resistant failure classes, delta-bounded) ·
`fr-10-gates` (irreducible human-touchpoint census) · `fr-11-context` (context economy, succession
theory) · `fr-12-workspace` (git concurrency, live-layer deploy model) · `fr-13-mesh` (hook/skill
config compilation). Each report ends with ranked rows:
`Problem | Evidence | Why-default-tier-insufficient | Solution-shape | Confidence`.

**B. Prior corpus (consume before concluding):** `docs/research/desk-audit-2026-07-18/synthesis.md`
(19-agent audit: themes A-F, G-* gap ledger, I-LIVE-1 stunned-desk incident) + `a17/a18/a19`
(strand scenarios S-0..S-3; liveness ESCAPES; the 12 done-attack escapes D-1..D-12) ·
`docs/research/SESSION_AUTONOMY_RESEARCH.md` (design law: 7 invariants, blind-check law, D9,
injection-channel law, authority ceiling C10, one-artifact-one-role) ·
`docs/plans/ORCHESTRATOR_DESK_24X7_PLAN.md` (P0-1..12, programs A-F) ·
`docs/research/desk-self-handoff-2026-07-19/panel-findings.md` (the prior Fable panel — YOUR
quality bar: identity models, decidability analysis, falsifying probes, NEW/CONFIRMED/REFUTED
tags) · `docs/research/desk-anti-hitl-2026-07-19.md` · `docs/L3-L4-AUTONOMY-ROADMAP.md`.

**C. Predecessor's interim theses** — PRIORS to test against evidence, not conclusions; refute
freely (tag REFUTED with reason):
- **T-A Truth-layer gap (extends C-DSH-1 beyond recycle-lifecycle):** the whole desk infers agent
  state from mendacious indirect signals (mtimes, JSONL tails, pane liveness, HEAD moves); every
  fix spawns new seams (census evidence: supervisor oscillation, reaper UTC, false-cliff,
  registration blindness). The generator move: a fleet-wide event-sourced attestation/heartbeat
  protocol with causal stamps + durable-product proofs, making whole false-inference classes
  unrepresentable. Test: does the wave's evidence support "protocol redesign" over "keep patching"?
- **T-B Prose-law → substrate semantic gap:** invariants live in prose (CLAUDE.md, design-law docs)
  and are enforced by model attention, which decays (injection-channel law). The generator move: a
  rule→actuator compiler — every binding rule gets a deterministic channel (hook/gate/test) or is
  explicitly marked advisory; measure today's enforced-vs-prose ratio (fr-07 delivers the count).
- **T-C Principled succession:** ruling #1 (supervisor PAGES, never acts) × human-absent-by-design
  = orchestrator death is unrecoverable BY LAW (a17 S-1). The frontier design: autonomous
  succession rails that provably cannot self-widen authority (C10-compatible respawn — consent
  delegated for WORK, never for persistence). Includes verified knowledge-carry (successor proves
  mission-possession before predecessor exits) and the context-economy inversion (H-DSH-2 two-tier).
- **T-D Content→action trust boundary:** worker-authored text flows into desk actuation, fired
  prompts, operator-run `--run` commands, and long-lived memory — with no provenance typing
  anywhere. Cross-agent prompt-injection + confused-deputy chains are unswept seams (fr-08 owns).
- **T-E Adversarial completeness verification:** a19's structural center — every completeness
  defense routes through the working model's own judgment or phrasing ("the continuation loop is
  opt-in by the exact agent whose judgment is compromised"; the tool-blind /goal evaluator). The
  frontier design: machine-readable DoD with per-item verify commands + a tool-USING independent
  judge; identify the irreducibly-judgment residue and its handling.
- **T-F Scheduling economics:** is 4-account × slot × window × value placement a real optimization
  frontier or is greedy near-optimal at this scale? (fr-05 delivers evidence either way — an
  anti-frontier verdict here is a finding, not a failure.)
- **T-G Config/deploy substrate:** live hooks = symlinks into a branch-checkout working tree
  (machine-wide mutation on checkout); 5-way settings replication; /tmp-resident state. Is a
  compiled, versioned, atomically-switched config/deploy layer the generator fix (fr-12/fr-13)?

## Method (in order)
1. Orient: read this brief, FRONTIER_HOLES.md, audit synthesis, panel-findings (the bar).
2. **Write your OWN derivation first** — from the system model, before folding wave reports —
   so your frontier judgment isn't anchored by the workers' framing.
3. Fold reports as they land (poll the dir; they arrive over ~30-90 min). For each row:
   CONFIRMED (matches your derivation / prior corpus), NEW (frontier delta), REFUTED (with reason),
   or ROUTINE (send to cc-backlog, not the portfolio).
4. Rank the surviving portfolio by: generator leverage (# named worklist/gap items dissolved) ×
   ceiling height (why default-tier fails: patch-resistance evidence, cross-cutting design,
   undecidability) × activation cost. 5-9 items is the expected shape; fewer is fine.
5. Per item: problem statement · evidence (file:line/commit/incident) · why-frontier · solution
   shape + first move · routing (`/frontier-campaign` candidate C-NNN | hole H-NNN | Fable build
   session | operator ruling) — in SYNTHESIS.md; mirror holes/candidates into FRONTIER_HOLES.md.
6. Missing reports after ~90 min: note the gap, proceed (OASIS stop — never block on stragglers).
   The predecessor session (shared checkout, account next) shepherds the wave and will have
   written/ensured disk copies; do NOT respawn wave agents.
7. Land (worktree → gate → /ship → content-verify), then the operator summary + readout.

## Hard constraints (verbatim-binding)
1. NEVER commit or land in the shared checkout `/Users/chrisren/Development/claude-infrastructure`
   — work in YOUR worktree, copy report files in, land via the project-local /ship only.
2. INTEGRATE-never-overwrite on FRONTIER_HOLES.md and every existing doc (Edit, not Write).
3. Read-only toward the live fleet: no launchctl, no kills, no cc-notify to working sessions, no
   backlog mutations except routing ROUTINE items via `cc-backlog add`.
4. Fable window is open (SSOT ~/.claude/model-config.yaml); you ARE the frontier tier — do not
   spawn further Fable subagents for this synthesis (budget discipline); Opus subagents only if a
   targeted gap-check is genuinely needed.
5. The operator asked for MAX reasoning: depth over speed, but the deliverable is the ranked
   portfolio — not an essay. Panel-findings.md is the bar for rigor per item.
