---
name: plan-conventions
description: >-
  Conventions for writing and updating PLAN documents so decisions accumulate losslessly across sessions. Load when creating or editing a plan / design / roadmap doc (the backup-before-write hook also auto-injects an abridged form on plan-file edits; this skill is the full version). Rules: INTEGRATE new content, never overwrite or delete existing sections; COMPLETED sections → compact to key learnings + commit hashes + blockers (drop granular step detail); UPCOMING sections → expand with file paths + line ranges + decision context + trade-offs; the MANDATORY Phase 0 rule — any plan with 2+ code-writing tasks MUST use Agent Teams and include Phase 0 (Agent Team Orchestration: team roster + roles, task dependency graph with blockedBy, worktree/branch assignments, spawn-wave order) as the FIRST section; NEVER delete historical decisions, "Why:" rationale, learnings, or known issues (they compound in value). Triggers: "write a plan", "update the plan", "add a phase", editing a *plan*.md / design doc / .claude-plans/ file, Phase 0 orchestration. Companion to the plan-update skill/command (the mechanical applier) — this skill is the RULESET + rationale, not the editor.
---

### Plan Document Conventions (CRITICAL — All Agents)

Plans accumulate decisions across sessions. Always INTEGRATE updates using these patterns.
The `backup-before-write.sh` hook auto-injects these rules on every Write or Edit to plan files.

**Completed Sections → Compact**

Mark DONE. Collapse to key learnings, commit hashes, and blockers only. Remove granular
step-by-step implementation details that are no longer needed. Example:

```
### Phase 5: Widget Schema — DONE (`abc123`, Mar 15 2026)
- Added widgetType + description columns. Migration 0045.
- Key learning: bare integer() needed for defaults (not timestamp_ms mode)
- Blocker resolved: pre-commit hook required staged migrations
```

**Upcoming Sections → Expand**

Comprehensive implementation detail — file paths with line ranges, decision context,
trade-offs, constraints. These sections are the working blueprint for the next session.

**Phase 0 Rule (MANDATORY — Agent Teams Default)**

**Agent Teams are the DEFAULT for all implementation work.** Any plan with 2+ tasks that
write or modify code MUST use Agent Teams and include Phase 0 as the FIRST section.
Only use background subagents for research/exploration (no code changes) or 50+ parallel
read-only tasks. The user expects 9/10 implementation sessions to use Agent Teams.

Phase 0 MUST include **Agent Team Orchestration**:
- Team size and roles (which agents, what each does)
- Task dependency graph (`blockedBy` relationships)
- Worktree assignments (branch names, isolation strategy)
- Spawn wave order (what runs in parallel vs sequential)

This ensures parallel work is architected before implementation begins.

**Never delete**: Historical decisions, "Why:" rationale, learnings, or known issues.
These compound in value across sessions and inform future decisions.
