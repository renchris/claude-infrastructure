# Pre-spawn decomposition — memory-economy ground-up investigation (2026-08-10)

## Restatement (user's vocabulary)
Deep research and investigate our claude-infrastructure and identify what can be ground-up
improved and re-architected that would eliminate tech debt and streamline our utilization of
memory to address our memory bottleneck limiting us to ~15 concurrent Claude Code +
claude-infrastructure + Kitty Terminal sessions on our fixed M1 Max 64GB 10-Core CPU MacBook
Pro 16" — including but not exclusive to: pollers/watchers/cron jobs/schedulers; inefficient
use of worktrees keeping a large number left open without proper and proactive event-driven
clean-up; lack of git maintenance or adjacent git hooks.

Question type: Architectural + Operational. Out of scope: Market / Competitive / BD / Legal /
product-feature research. Named entities (Kitty, Claude Code, M1 Max) ARE the research
subjects (internal infrastructure), not use-case archetypes — named-entity audit n/a.

Task category: A (breadth-first independent axes) + C (fleet-scale, >20 files) → MAS.

## Live anchor census (measured this session, 2026-08-10)
- 64GB RAM, swap 0 used at snapshot. claude ×14 = 8.7GB · node ×13 = 3.4GB ·
  claude.exe (subagents) ×5 = 2.7GB · chrome-devtools-mcp ×5 = 1.8GB (one 1.6GB, up 1h22m) ·
  next-server ×2 = 2.5GB · esbuild ×6 = 850MB · tsc 1.55GB · npm ×5 · bash ×70 = 162MB ·
  kitty ×1 = 157MB · Browser/Google/Dia ≈ 7.7GB.
- 47 user LaunchAgents; ours ≈ 30 (com.claude.* 22, com.chrisren.* 6, com.reso.* + gl.reso.* 7,
  org.git-scm.git.{hourly,daily,weekly}, homebrew ollama + postgresql@14).
  Dead: com.claude.discovery (-15), com.claude.lead-supervisor (-15). Resident now: dispatcher
  51100, compressor-sentinel 64116, postland-verify 86570, capacity-alarm 98609,
  caffeinate-floor 818, gl.reso.worktree-gc 69670.
- Worktrees: claude-infrastructure 115 · reso-management-app 76 · doc_classifier 63 ·
  finance-ai-web-app 10 · others ≈ 14. Two worktree-GC daemons EXIST
  (com.claude.worktree-gc-infra, gl.reso.worktree-gc) yet counts stay high.
- Hooks: 74 files in hooks/, 12 events with 41 matchers in ~/.claude/settings.json
  (PreToolUse 5 · PostToolUse 7 · SessionStart 6 · SessionEnd 6 · Stop 2 · UserPromptSubmit 2 ·
  Notification 4 · PermissionRequest 4 · TeammateIdle 1 · WorktreeCreate 1 · TaskCompleted 1 ·
  PreCompact 2).
- crontab: empty (everything is launchd).
- Ground-up program already exists: docs/plans/GROUND_UP_REBUILD_MAP.md, ground-up skill,
  gu-* worktrees (gu-worktree-warmpool-b, gu-memory-knowledge, gu13c-*), docs/ground-up-payloads/.

## Decomposition table

| Axis | Sub-questions | Agent |
|---|---|---|
| A. Resident footprint | 64GB decomposition; marginal RSS of 1 session tree (main+MCP+statusline+shells); the 70 bash; claude.exe subagent cost; RSS vs compressed via footprint/vmmap | census-fleet |
| B. Scheduled compute | per-plist trigger/cadence/script/cost/status; dead jobs; redundancy clusters (5 reapers); poll→event conversion; aggregate wakes/day | sched-launchd |
| C. Session pollers | census session-spawned watchers (cc-await-ping 15s, waiting-recycle, statusline, keepalives); cardinality ×15 sessions; orphans (ppid 1); event-driven consolidation | pollers-sessions |
| D. Worktree lifecycle | population stats (age/dirty/landed); why GC daemons leave 115+76+63; creation:removal ratio; disk + .git/worktrees metadata; event-driven GC at land/pane-death | worktrees |
| E. Git maintenance | maintenance.repo enrollment vs fleet; loose objects/packs/reflog per repo; fsmonitor/untrackedCache/commit-graph; git-op cost in hooks; missing git hooks | git-maint |
| F. Hook economics | per-event fork bill (measured, not static-counted); broad vs narrow matchers; hot-path store reads per fire; dispatcher consolidation design | hook-forks |
| G. Session levers | MCP server policy (chrome-devtools-mcp 1.6GB, 5 instances); statusline cost; node heap flags; idle-session RSS + policy | session-cost |
| H. Terminal layer | kitty scrollback/pane economics + config deltas; iTerm2 residency/duplication (it2 deps); Hammerspoon role | terminal-layer |
| I. Stores & growth | du by store (2997-session projects dir, backups, 662 plans, jsonl stores, daemon logs, /tmp/cc-*); hot-path readers × frequency; per-store retention/compaction design; MEMORY.md over-limit as worked example | stores-bloat |
| J. Prior art | settled decisions + status per domain (CONTEXT_ECONOMY_V2, GROUND_UP_REBUILD_MAP, inertness-generator, context-econ, opus5-adaptation §D6, migrations c10, open plans); graveyard (git log --all prior gc/reaper/consolidation attempts); hard constraints register | prior-art |
| K. Adversarial defend | which "waste" answers an incident (memory/docs cite); consolidation SPOF risks; 3 missed dimensions (hostile reviewer) | adversary-defend |
| L. Adversarial refute | evidence RAM-attribution FAILS: CPU/QoS bands, maxproc/fd/pty, page cache, swap/memorystatus history 14d, quota; rank binding constraints; instrumentation for next wall event | bottleneck-refute |

Decomposition: 12 axes → 33 sub-questions → 12 parallel subagents.
Adversarial slots: K + L = 2/12 ≈ 17% (≥2 at N≥10 ✓; distinct framings: hostile-reviewer vs red-team).
Entanglement audit: source domains disjoint (plists / hooks dir / worktree dirs / .git internals /
docs / live procfs); tool patterns mixed (Bash-measurement A,C,L · plist+script reading B ·
git-internal E,D · Read-heavy J,K · config G,H · du/forensics I); polarity mixed (find-waste
A-I · defend K · refute L). Entangled productive pairs ≤ 30% ✓.

Negative space (3, with reasons): (1) token/quota economics — explicitly owned by
CONTEXT_ECONOMY_V2; prior-art agent verifies coverage rather than re-researching. (2) Tuning
the operator's own apps (Chrome/Dia/Adobe ≈ 7.7GB) — outside claude-infrastructure's remit;
bottleneck-refute ATTRIBUTES it but we do not re-architect it. (3) CC binary internals beyond
config-exposed levers — not actionable locally; axis G covers the config surface.

## Revision 1 (critic REVISE + operator interjection, 2026-08-10)
Operator (verbatim): "Really emphasis the 'including but not exclusive to' we are relying on
you to exhaustively explore our blind spots of topics of investigation not said where you have
high signal for." → the named domains are a floor; unnamed high-signal domains are in scope.

New axes:
| M. Dev-tool + editor residency | next-server ×2 (2.5GB) despite devserver-gc daemon; tsc 1.55GB; esbuild ×6; npm ×5; ollama; postgresql@14; Cursor/VS Code TS-servers + extension hosts per open worktree; orphan attribution; kill-on-session-end / TTL policy design | devtools-residency |
| N. Orchestration-layer economics | claude.exe subagent RSS (~540MB avg ×5 now) — RAM bill of research waves / agent teams; desk+dispatcher+supervisor residency; handoff-fire spawn graph at steady state; cc-offload state (HEAD 237ecf24 — read the DIFF, not the subject) + remote isolation offload sizing | orchestration-econ |
| O. Blind-spot sweep (3rd adversarial/negative-space slot) | memory-relevant subsystems NONE of the other 14 axes cover; 3-8 candidates w/ evidence + size | blindspots |

Ownership splits (critic): C owns statusline CENSUS → G consumes the number; I owns the
store-growth census → F consumes per-fire read cost only. A += per-session RSS growth-over-
lifetime (leak vs fixed), git background daemons census (fsmonitor--daemon, credential-cache),
browser-process attribution (infra-owned auth profiles/dia-cdp/agent-browser vs operator
browsing). B += boot-resume respawn storm, ollama/postgres tenancy. E += fsmonitor design
question at 278-worktree scale. L += compressor-sentinel + capacity-alarm forensics (what
fired at past walls). J stays deep-research despite critic's Explore suggestion — Explore
lacks Write access and the delivery contract requires a file (skill field 7).

Decomposition (revised): 15 axes → 44 sub-questions → 15 parallel subagents.
Adversarial + negative-space slots: K, L, O = 3/15 = 20% ✓ (hostile-reviewer / red-team /
blind-spot sweep — distinct framings). Model routing: K, L, O on Fable (call-time model
override per skill § frontier tier; window OPEN per SessionStart); productive 12 on
deep-research default (Opus).
Expected artifact set += devtools-residency.md · orchestration-econ.md · blindspots.md (15 total).

## Sample deliverable row (structure contract for every worker finding)
Finding: worktree GC leaves landed worktrees behind
Evidence: scripts/worktree-gc.sh:42 requires merged AND >7d; 87/115 fail only the age arm (measured)
Cost now: 115 worktrees ≈ N GB disk + .git/worktrees index inflation (measured)
Re-architecture: remove at /ship post-land + pane-death reaper; 48h grace
Sizing: recovers ~N GB, -100 scan dirs · effort S · risk low (recreate is cheap)
Existing mechanism: com.claude.worktree-gc-infra — EXTEND, not new

## Delivery contract
Reports dir R = /private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/626d9307-164b-41d5-8747-eb1ab8df099c/scratchpad/reports
Expected artifact set (wave done = all 12 exist):
census-fleet.md · sched-launchd.md · pollers-sessions.md · worktrees.md · git-maint.md ·
hook-forks.md · session-cost.md · terminal-layer.md · stores-bloat.md · prior-art.md ·
adversary-defend.md · bottleneck-refute.md
