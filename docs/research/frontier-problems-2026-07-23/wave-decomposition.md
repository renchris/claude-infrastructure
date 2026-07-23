# Frontier-problems investigation 2026-07-23 — pre-spawn artifact

Goal (operator, verbatim restatement): find the most complex, highest-margin problems in the
claude-infrastructure application/architecture requiring frontier intelligence (Fable 5 max) —
memory issues eliminated; context/time performance/efficiency; session-to-session pass-through
quality; clean-up/GC; 2-way communication visible to Terminal UI/User; silent-failure elimination
with UI visibility + log capture. 100x research time warranted for 100th-percentile implementation.

Question type: Architectural + Operational. Out of scope: Market/Competitive/BD/Legal/Product.
Task category: A (breadth-first) + C (degraded-context codebase audit: 61 hooks + 109 bin/scripts + stores).

Decomposition: 11 axes → ~40 sub-questions → 11 parallel deep-research (Opus 4.8) subagents.
Adversarial: axis K in-wave (hostile completeness) + wave-2 red-team vs draft synthesis + lead negative-space.
Entanglement audit: source-disjoint primaries (docs / branch-graph / memory+git / hooks / bin+scripts /
stores / comms surfaces / telemetry / transcripts / live disk); framing polarity varied (C incident-backward,
D/E code-forward, K refute-framed). ≤30% pair entanglement. All-Anthropic family → methodological diversity
is the compensator.

| Axis | Agent | Primary sources |
|---|---|---|
| A prior-art + in-flight branch ledger | axisA-prior-art | docs/research/*, docs/rulings, docs/proposals, 24 unmerged branches, worktree list |
| B crash/memory residue post-correction | axisB-crash | feat/handoff-memory-review docs+commits, claude-crashes.jsonl, cc-crash-report, watchdog |
| C silent-failure incident corpus → mechanism classes | axisC-incidents | memory/*.md, git log, research docs |
| D hooks-layer seam audit (61) | axisD-hooks | hooks/*, settings hooks wiring, hook logs |
| E bin/scripts seam audit (109) + reconciler inventory | axisE-binscripts | bin/*, scripts/* |
| F state-store census + config drift | axisF-stores | ~/.claude/autonomy/*, registries, settings*, CLAUDE.md dual-copy, symlink layer |
| G 2-way comms + TUI visibility + permission stalls | axisG-comms | cc-notify, mailbox, statusline, operator-readout, cc-blockers, mail v3 doc, live counts |
| H context/time/token economics | axisH-econ | context-econ doc, waiting-recycle, cache-expiry hooks, token-usage transcripts, limit-recover |
| I succession fidelity (handoff pass-through) | axisI-handoff | handoff-fire.sh, dod-persist, wrap-ledger, real transcript chains, MEMORY.md flow |
| J GC/lifecycle accumulation + reaper blind spots | axisJ-gc | live disk (worktrees, branches, backups, projects/, /tmp), reapers |
| K hostile completeness review | axisK-hostile | this artifact + repo top-level + FRONTIER_HOLES |

Per-subagent: deep-research (Opus 4.8), target 150-200K ctx, ceiling 256K, ~25-40 tool calls,
return 3-12K dense signal in the CANDIDATE FRONTIER PROBLEM row format + findings tables.
Synthesis: lead (Fable 5 max) — problem book at docs/research/frontier-problems-2026-07-23.md
via own worktree/branch + /ship; FRONTIER_HOLES.md entries; campaign candidates.

## Critic revision (research-decomposition-critic, 2026-07-23) — APPLIED
- D/E/C lens separation: D = event-chain integrity (code-forward), E = receipt discipline +
  reconciler inventory (code-forward), C = incident corpus (history-backward); dedup lines added.
- NEW axis L: daemon/launchd/process-layer health (daemon-stacking, idl-deadlock, staged-vs-loaded,
  who-watches-the-watchers) — was falling through J (files) vs live jobs.
- NEW axis M: permission/authorization architecture (5-dir stack, ask-halts, beacon, classifier
  denials) — was buried as a G sub-clause.
- NEW in-wave adversarial N: red-team the failure-taxonomy FRAME (design-tradeoff taxes vs
  failures; simplification candidates) → in-wave adversarial = K+N = 2/14, meets N≥10 floor.
- Explore routing for A/J REJECTED with reason: eval track ≥2.1.198 Explore inherits lead model
  (capped opus) → no cost win vs deep-research(opus); quality favors deep-research.
- Sample deliverable row instantiated in every brief (drift-catchable at return time).
- Live/dynamic observation folded into L/G/J as live read-only reads (launchctl list, ps, live counts).
Final wave: 14 = A B C D E F G H I J L M + adversarial K N. Sample row: see lead message log.

## Running state (successor-readable; updated 2026-07-23 ~09:3xZ)
- HARVESTED (reports in scratchpad/reports/): A, C, D, K, N. IN FLIGHT: B, E, F, G, H, I, J, L, M.
  Harvest via scratchpad/harvest.py <names>; idle_notification ≠ delivery (proven again this run:
  my 6 SendMessage mid-flight corrections NEVER appeared in any finished agent's transcript).
- Landing worktree: /private/tmp/wt-frontier-problems, branch docs/frontier-problems-2026-07-23
  (based on origin/main fe52c1f). Commit d1a67df = recovered frontier-hard-2026-07-20 wave
  (13 reports + BRIEF + SHEPHERD-NOTES) rescued from dangling checkpoint ref 38c6efb.
- KEY CONTEXT: today's goal is a RE-ISSUE of the 2026-07-20 frontier-hard mission whose synthesis
  stranded (fp-A found it). Deliverables: frontier-hard-2026-07-20/SYNTHESIS.md (short pointer),
  docs/research/frontier-problems-2026-07-23.md (the ranked portfolio), FRONTIER_HOLES.md
  INTEGRATE, land via project-local /ship (standing-land).
- Crash story (for premise hygiene): teardown-confound correction (doc at
  `git show 31c7cb4:docs/research/session-crash-forensics-2026-07-23.md`); organic ~0.24% flat;
  pin-183 WITHDRAWN; fix = deploy 11 landed commits + teardown-marker contract.
- fp-K discounts to honor at synthesis: activation-gap claims need LIVE re-verification (244
  commits since 07-18 closed some); dedupe a18-derived findings; memory = hypotheses not ground
  truth; crash-axis output provisional.
- Portfolio priors to test (mine + predecessor T-A..T-G): attestation kernel · deploy/activation
  substrate · receipts/effect-contracts · monitor-signal-integrity (nothing audits the auditors) ·
  complexity self-generation loop (deletion budget) · succession fidelity under C10 · operator-
  attention oracle · economic scheduler (maybe anti-frontier) · K's NEW: security threat model,
  restore drill, test-oracle validity.
