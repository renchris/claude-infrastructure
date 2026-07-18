# Pre-Spawn Decomposition — Orchestrator-Desk Exhaustive Investigation

## Goal (fidelity restatement, user's vocabulary)
Investigate our documentation and assets — skills, scripts, CLAUDE.md, rules — of the main-session
"orchestrator desk" archetype/pattern/workflow. The desk must drive all sessions: /handoff at will,
manage return results, 2-way communication; (a) exhaustively research/retrieve/identify ALL tasks to
reach a 100.00/100.00 complete-and-correct, 100th-percentile implementation of a repository or
long-horizon task; (b) manage the work with as many parallel/concurrent /handoff sessions as needed —
gracefully communicating, closing, re-handing-off at good pause points for fresh context; (c) renew
itself by /handoff to keep a clean small context and a sharp un-context-rotted brain. Runs
autonomously, net-positive, 24/7, WITHOUT human in the loop. Two chronic failure modes to fix:
(FM1) losing purpose / losing track of what exhaustive completeness means — pausing until a human
re-asks; (FM2) "idle session" standoff — sessions believed waiting/working that are not. Clean and
non-fragile: code, practices, and behavior.

## Question type
Operational + Architectural + Product (gap/task inventory). Out of scope: Market, Competitive,
BD/Sales, Legal/Compliance. No named external entities → named-entity audit n/a.

## Task category
A (breadth-first independent retrieval across disjoint asset clusters) + C (degraded-context: >>20
files, whole-repo audit). MAS applies.

## Decomposition table

| # | Axis | Sub-questions | Primary sources (disjoint) |
|---|------|---------------|----------------------------|
| P1 | Handoff/spawn machinery | /handoff bridge artifact + fire path (it2, split-right, launcher/account selection); post-fire ENGAGEMENT verification + cold-worktree auto-submit race; handoff-disposition decision tree + --self-retire semantics; boundary-handoff trigger + does the DoD/goal survive the bridge? | commands/handoff.md, scripts/handoff-fire.sh, scripts/handoff-disposition.sh, hooks/boundary-handoff.sh, scripts/handoff-selfclose-e2e.sh, docs/plans/HANDOFF_DISPOSITION_PLAN.md, tests/{fire-autonomy,handoff-splitright,handoff-disposition,notify-back}.bats, scripts/limit-recover/lr-handoff.sh |
| P2 | Two-way comms & message safety | channel inventory desk↔session + channel-ladder law (§8.5 E5); completion result return path (cc-announce VERIFIED-or-LOUD, completion-push, notify-back); payload-lint/comms-safety incident class; silent-loss surfaces (pane-UUID drift, exit-deadline) | bin/{cc-notify,cc-announce,cc-await-ping,cc-bind}, scripts/{payload-lint,comms-safety-gate,completion-push,exit-deadline}.sh, docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md, docs/COMMS-SAFETY-ACTIVATION.md, docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md, tests/{cc-announce,cc-await-ping,cc-notify,completion-push,exit-deadline,payload-lint,notify-back}.bats |
| P3 | Idle classification + reaping | the 7 idle causes' exact detector logic + inputs; which causes map to FM2; reap policy + safety gates (reap-guard, horizon lint, RED-proven CL/RP/TD); team-orphan-reaper vs cc-reaper split; cc-deathwatch-kqueue role | bin/{cc-classify,cc-reaper,cc-deathwatch-kqueue}, scripts/{reap-guard,reaper-e2e,reaper-safety-gate,reaper-horizon-lint,team-orphan-reaper}.sh, docs/{AUTONOMOUS-REAPER-ACTIVATION,REAPER-SAFETY-ACTIVATION}.md, tests/{cc-classify,cc-reaper,reap-guard}.bats, launchd/com.claude.team-orphan-reaper.plist |
| P4 | Wait/recycle discipline | waiting-recycle quiet-boundary predicate + what state survives recycle; cc-wait + wait contracts (owned-wait vs stall); never-stuck B1-c invariants (21 audited); exit-deadline computation | hooks/waiting-recycle.sh, tests/{waiting-recycle,cc-wait,wait-contract-lint}.bats, bin/cc-wait, scripts/{wait-safety-gate,wait-contract-lint,never-stuck-gate}.sh, docs/NEVER-WAIT-ACTIVATION.md |
| P5 | Supervision + session registry | registry schema/lifecycle/staleness (does in-place handoff update it?); cc-board/cc-sessions/cc-context visibility surfaces; lead-supervisor vs lead-deathwatch vs lead-reconciler vs lead-crash-watchdog (trigger/cadence/action/overlap); D2 runtime activation state | hooks/{live-session-registry,session-register,session-deregister,session-end,session-start,session-save-id}.sh, hooks/session-index-*.sh, bin/{cc-sessions,cc-board,cc-context}, scripts/{lead-deathwatch,lead-supervisor,lead-reconciler,supervisor-e2e,session-lifecycle-safety-gate}.sh, hooks/lead-crash-watchdog.sh, tests/{lead-deathwatch,lead-reconciler,session-registry}.bats, docs/D2-RUNTIME-ACTIVATION.md |
| P6 | Completeness / anti-premature-done discipline | anti-deference Stop hook: patterns caught, re-prompt, cap; session-continue arm/clear/actuate + who arms it in practice; /goal implementation + condition-hold semantics; does /wrap exist anywhere (CLAUDE.md references it); premortem/task-quality/plan-phase-scan/seam gates | hooks/{anti-deference-nudge,session-continue,task-quality-gate}.sh, tests/anti-deference-nudge.bats, commands/*.md sweep for goal/wrap, scripts/{premortem-gate,plan-phase-scan,p8-e2e}.sh, docs/WORKFLOW_SEAM_GATES.md, docs/rulings/P8-GO.md, global CLAUDE.md §Session Close |
| P7 | Intent / roadmap / activation state | L3→L4 level definitions + delivered P0 milestones + remainder; SESSION_AUTONOMY_PLAN/RESEARCH architecture + decisions; W0-W3 human-intervention audit findings; W4-W5 proposal (proposed-unbuilt); definitive LIVE vs STAGED-awaiting-human wiring table (wiring-all.sh, C10) | docs/L3-L4-AUTONOMY-ROADMAP.md, docs/plans/SESSION_AUTONOMY_PLAN.md, docs/research/{SESSION_AUTONOMY_RESEARCH,W0-W3_INTERVENTION_AUDIT}.md, docs/proposals/W4-W5-SESSION-ORCHESTRATION.md, docs/activation/wiring-all.sh, docs/*-ACTIVATION.md |
| P8 | Quota / account sustainability | limit-recover disk-truth audit + transplant — unattended?; lr-reset-poller; cc-route slot routing (live reads) + RT gates; cc-respawn RS gates + reset-time auto-resume; claude-accounts heal/rank + account-relogin headless viability; Kimi metered overflow | bin/{claude-accounts,cc-route,cc-respawn,claude-kimi}, accounts.json, commands/limit-recover.md, scripts/limit-recover/*, scripts/{route-safety-gate,respawn-safety-gate,limit-reset-safety-gate}.sh, tests/{cc-route,cc-respawn,lr-reset-poller,claude-kimi}.bats, docs/KIMI_METERED_INTEGRATION.md, ~/.claude/model-config.yaml |
| P9 | Ship/land & worktree safety | project-local vs global /ship; land-lock serialization + stranded-sweep; content-verification enforcement; SHIP_LAND_HARDENING_PLAN残; the never-push-without-user vs 24/7-net-positive tension — what would safe auto-land require? | commands/ship.md, .claude/ project-local commands, scripts/{land-lock,stranded-sweep}.sh, tests/{land-lock,stranded-sweep}.bats, docs/plans/SHIP_LAND_HARDENING_PLAN.md, hooks/{git-worktree-guard,worktree-setup,check-edit-boundary}.sh, docs/WORKTREE_WORKFLOW.md, .claude/CLAUDE.md |
| P10 | Runtime substrate & 24/7 plumbing | launchd truth (repo plists + ~/Library/LaunchAgents actually loaded); permission autonomy at 3am (smart-bash-allowlist, rm-safe, validate-bash — what still prompts); update/version + config-mirror integrity on cold spawns; backup/blast-radius (backup-before-write, prune, restic) | launchd/*.plist, install.sh, hooks/{smart-bash-allowlist,rm-safe-allowlist,validate-bash,config-mirror-assert,pre-session-validate,push-critical,cache-expiry-tracker,cache-expiry-warning,notify}.sh, settings-templates/, statusline.sh, bin/{it2-wrapper,claude-latest,claude-update,claude-versions,claude-bump-models}, scripts/{prune-backups,restic-claude-archive-backup,smoke-test}.sh, ~/Library/LaunchAgents (live read) |
| P11 | Incident forensics (empirical) | reconstruct from transcripts/memory/git: nudge misroutes ×3 + false stall/RECYCLE ×2 + wrong causal claims ×3 (2026-07-16); cold-fire non-engagement; dropped-commit 2026-07-11; ≥2 concrete FM1 premature-pause instances; per incident: signal present vs conclusion drawn vs ground truth vs which current asset would catch it now; recurring FM1/FM2 signatures | memory dir (all desk entries), claude-search CLI, ~/.claude*/projects/**/*.jsonl (targeted), git log, hooks logs if any |
| P12 | Verification coverage map | asset↔test matrix for every bin/hook/script (or NONE); RED-by-design un-hold bars inventory + un-hold conditions; when do tests actually run (pre-commit? CI? launchd? never); RED-proof quality spot-check of 5 critical suites | tests/*.bats, hooks/tests/*, scripts/*gate*.sh, scripts/*e2e*.sh, scripts/*lint*.sh, install.sh, any CI/pre-commit wiring |
| P13 | Behavioral layer (prompt-space) | which desk rules are prompt-encoded vs hook-enforced (encode-vs-enforce table); lazy-load skill trigger reliability + miss modes; commands vs skills vs raw-prompt inventory of desk verbs; memory→code promotion candidates; where context rot defeats prompt-only rules (FM1 link) | CLAUDE.md (repo+global resident), skills/*/SKILL.md, commands/*.md (all), docs/CLAUDEMD_LAZYLOAD_REVIEW.md, memory MEMORY.md + entries, hooks/memory-nudge.sh |
| P14 | Task/plan ledger | .claude-tasks/.claude-plans structure + index hooks + symlinks; disk-truth "ALL open work" query path + staleness/duplication traps (SessionStart says "Plans: 0" while docs/plans/* exist — verify); plan lifecycle enforcement (version-commit, pin-session, quality-gate); does anything map goal→plan→tasks→sessions? | .claude-tasks/, .claude-plans/, hooks/{plan-index-update,plan-pin-session,plan-version-commit,migrate-plans-index,setup-plan-symlinks,setup-task-symlinks,task-completed-index,task-mutation-index}.sh, scripts/{find-plan,current-session-plan}.sh, skills/{plan-conventions,plan-update}/SKILL.md, commands/copy-plan.md |
| A15 | Hostile reviewer — 24/7 collapse (fable) | argue the desk STRANDS within 24h unattended: concrete strand scenarios (trigger→stuck state→why no recovery) each file:line-grounded; name the dimension the productive wave missed | whole repo, cross-seams priority |
| A16 | Liveness-model attacker (fable) | ≥8 concrete FM2 scenarios (believed-working-but-idle / believed-idle-but-working / believed-fired-never-engaged / believed-closed-but-orphaned) traced through actual detector code; per scenario verdict CAUGHT-TODAY(file:line) or ESCAPES(why) | bin/cc-classify, hooks/waiting-recycle.sh, scripts/lead-*.sh, registry hooks, memory incidents |
| A17 | Completeness-discipline attacker (opus) | ≥8 concrete FM1 scenarios where the desk halts believing done/blocked with work remaining — attack /goal condition evaluation, anti-deference pattern list, session-continue arm/clear, DoD survival across /handoff bridges + recycles; verdict CAUGHT/ESCAPES per scenario | hooks/{anti-deference-nudge,session-continue,boundary-handoff}.sh, commands/handoff.md, CLAUDE.md close protocol |

Decomposition: 14 axes → 52 sub-questions → 17 parallel subagents (14 productive + 3 adversarial =
17.6%; wave-2 devil's-advocate + red-team vs lead synthesis planned, lifting lifetime adversarial
ratio to ~25% appropriate for autonomous-ops stakes).

## Routing & depth
- P1–P14, A17: `deep-research` (Opus 4.8 frontmatter default, inherited max effort). A15, A16:
  `deep-research` with call-time `model: "fable"` (frontier window OPEN per SessionStart live read;
  if frontier-spawn-gate blocks, PARK the fable attempt and respawn that brief on default tier —
  tier-fallback, not a retry).
- Depth: synthesis-class 150K modal / 256K ceiling, ~25–35 tool calls each.
- Artifact-reference hybrid: full report → scratchpad/reports/<ID>-<slug>.md (via Bash heredoc —
  deep-research has no Write tool); return = executive summary ≤3K + report path. Keeps lead
  synthesis context ≤ ~60K inbound.
- Severity vocabulary (shared): P0 = strands/corrupts the 24/7 loop within a day; P1 = degrades
  throughput/quality or occasionally loses work; P2 = polish.

## Entanglement audit (N=14 productive)
Source subsets disjoint by construction (beat-owned dirs/files; P11 transcripts+memory not repo
code; P12 tests; P7 docs). Framing polarity varies: descriptive-map (P1–P5,P7–P10), gap-hunt
(P12–P14), forensic-empirical (P11), attack (A15–A17). Tool patterns: Bash-heavy (P10–P12),
Read/Grep-heavy (rest). Single model family — methodological diversity is the compensator.
Entangled pairs ≪30%. ✓

## Negative space (lead inline, 3 dimensions)
1. CC runtime/binary capability drift — thin coverage by design; SSOT'd by cc-version-audit skill +
   MANIFEST discipline; P10 touches the update surface. Not promoted.
2. External/web orchestration research — explicitly out of scope per user intake ("investigate OUR
   documentation and assets"); repo already embeds SESSION_AUTONOMY_RESEARCH.md (P7 reads it).
3. Task/plan ledger subsystem — WAS a forgotten dimension → promoted to P14 per the skill's rule.

## Stop criterion
OASIS at synthesis: orthogonality held at brief-write; A15's "missed dimension" = adversarial-null
check; sublinear tail judged on unique-finding curve across returns; falsification test before
declaring coverage complete. Gap-fill wave 2 (3–8 narrow) only on NAMED gaps.

## Critic verdict + revisions (v2 — research-decomposition-critic, REVISE applied)
Critic found: orthogonality PASS, cost PROPORTIONATE, type-fidelity PASS; 3 completeness holes +
missing sample-row schema. Revisions:
- **P15 (new): Unattended-escalation policy** — map every STOP-ASK / user's-call / approval surface
  (CLAUDE.md close protocol, G2/G3 gates, push-is-user's-call, permission ask-rules) and derive what
  the desk does at that boundary with NO human present; what roadmap/rulings already decide; task
  candidates for a decision-queue protocol honoring operator standing values.
- **P16 (new): Machine wake/power/network continuity** — pmset/caffeinate/sleep-missed launchd fires
  (StartCalendarInterval vs KeepAlive), session survival across sleep/network-drop/reboot, LaunchAgent
  login-session dependency, post-reboot auto-resume chain. Live read-only checks sanctioned.
- **P8 augment**: how is "net-positive" measured per cycle (cost-vs-value, not just quota survival).
- **P14 augment**: progress/throughput accounting — telemetry-e2e.sh, cc-board, token-usage,
  commit-delta; does any asset quantify work-value vs wheelspin?
- **Shared return-schema (all briefs)**: gaps `G-<ID>-<n> | file:line | FM1/FM2/24x7/none | P0/P1/P2 |
  one-line failure scenario | fix sketch`; tasks `T-<ID>-<n> | action | acceptance criterion |
  depends-on`.
- Adversarial renumbered: A17 hostile-24/7 (fable), A18 liveness-attacker (fable), A19
  completeness-attacker (opus).

Decomposition (v2): 16 axes → 58 sub-questions → 19 parallel subagents (16 productive + 3
adversarial = 15.8%; wave-2 devil's-advocate/red-team vs synthesis still planned). Sub-batches:
P1–P10, then P11–P16+A17–A19.
