<!-- markdownlint-configure-file { "MD003": false, "MD013": false, "MD022": false, "MD031": false, "MD032": false, "MD040": false, "MD041": false, "MD060": false } -->
---
name: plan-update
description: Update plan files with compaction templates, Phase 0 scaffolding, and section organization. Use when working on plan files, compacting completed phases, generating Phase 0 orchestration, or restructuring sections. Also invokable as the slash command `/plan-update [plan-name-or-path]`.
allowed-tools: Read,Edit,Glob,Grep,Bash
---

# Plan Update Skill

Maintain plan files following CLAUDE.md conventions: completed sections compact, upcoming sections expand, Phase 0 is mandatory for team-based work.

**Two ways in** — both resolve to this file:

- Natural language — user says "update the plan", "compact phase 2", "mark Phase 5 done".
- Slash command — user types `/plan-update [plan-name-or-path]`.

Follow the Executable Workflow below for either path.

## Before You Edit Any Plan File

**CRITICAL — Follow this checklist every time:**

1. ✅ **Read the plan file first** — Use Read tool to understand current state, completed sections, and pending work
2. ✅ **Use Edit, never Write** — Always use Edit to integrate changes. Write overwrites everything.
3. ✅ **Phase 0 REQUIRED for all implementation plans** — Any plan with 2+ implementation tasks MUST have Phase 0 with Agent Team orchestration. Default to Agent Teams for ALL code changes. Only omit Phase 0 for pure research/exploration plans.
4. ✅ **Preserve all history** — Never delete completed sections, "Why:" lines, known issues, or learnings
5. ✅ **Apply templates below** — Use the exact formats for compaction and expansion

## Executable Workflow

This is the step-by-step procedure the `/plan-update` slash command runs. Follow it when invoked via natural-language trigger phrases too.

### Step 1 — Resolve the plan file (THIS session only)

**Never auto-pick by filesystem mtime.** A plan file touched two minutes ago might belong to a parallel session or a hook — not this conversation. The target is always the plan this session has been referencing.

With an explicit argument, resolve in this order:

1. Absolute path that exists → use it.
2. Relative path that exists from cwd → resolve to absolute.
3. Bare name (with or without `.md`) → Glob search, first hit wins:
   - `~/.claude/plans/<name>.md`
   - `$PWD/.claude-plans/<name>.md`
   - `$PWD/docs/plans/<name>.md`
   - `~/Development/*/.claude-plans/<name>.md`
   - `~/Development/*/docs/plans/<name>.md`

With no argument: **the session's plan file is whatever the harness assigned to this session.** That's it. Check in order:

1. **`## Plan File Info:` system reminder** — if plan mode was ever entered this session, the harness injected this block with the plan path. Use it verbatim. Do not second-guess. It doesn't matter whether the file was populated by `/copy-plan`, briefly edited, or is "just a scratch" — it is the session's plan.
2. **No plan mode this session** — scan conversation for a single unique `~/.claude/plans/*.md` / `.claude-plans/*.md` / `docs/plans/*.md` reference and use it.
3. **Nothing found** — STOP and ask the user to pass the path. Never guess by mtime.

Do NOT call `~/.claude/scripts/find-plan.sh` — it prints file content, not path. Use Glob + conversation-context inspection for resolution.

Announce the resolved absolute path plus which signal you used (e.g., "Plan Mode reminder", "ExitPlanMode 3 turns ago", "explicit user reference"). If the path is outside the 5 plan-file patterns protected by `backup-before-write.sh`, warn the user that backup + plan-history hooks may not fire.

### Step 2 — Scan structure

Invoke the phase scanner:

```bash
~/.claude/scripts/plan-phase-scan.sh <resolved-path>
# or --markdown for human-readable
```

The script emits JSON:

```json
{
  "file": "…",
  "total_lines": 1568,
  "summary": {"sections": 81, "done": 1, "pending": 80, "in_progress": 0, "superseded": 0, "phase_0": 3},
  "sections": [
    {"start_line": 78, "end_line": 222, "line_count": 145, "level": 2, "status": "PENDING", "commit_hashes": [], "is_phase_0": true, "title": "Phase 0 — Agent Team Orchestration"},
    …
  ]
}
```

Status detection (inside the script):

| Signal in heading | Status assigned |
|---|---|
| `SUPERSEDED` (bounded word) | `SUPERSEDED` |
| `DONE` (bounded word) | `DONE` |
| `WIP` or `IN PROGRESS` | `IN_PROGRESS` |
| 7–40 char hex commit hash (non-numeric) | `DONE` (implicit) |
| none of the above | `PENDING` |

Fenced code blocks are skipped, so `#` bash comments inside `` ``` `` don't register as headings. Section `end_line` is computed as the line before the next heading at the same-or-higher level (or EOF).

### Step 3 — Cross-reference completion signals

Three signal sources. All are advisory; when they conflict, trust the most specific.

**3a. Git log cross-check.** For every section with commit hashes in its heading or body:

```bash
git log --oneline <hash>                       # in cwd repo
git -C ~/Development/claude-infrastructure log --oneline <hash>   # if plan touches global hooks/scripts
```

- Hash resolves → status is trustworthy; proceed to compact.
- Hash missing in all candidate repos → DRIFT. Do NOT compact; report to user.

**3b. Body `**Status**:` line.** The scanner sets `status_source: "body"` when it picked up status from a `**Status**:` or `**v1 Status**:` style line in the section body (not the heading). Treat as equivalent weight to the heading marker.

**3c. Task list cross-reference.** The harness injects the current session's TaskList via system-reminders. For every `#NNN` task ID referenced in a section's body, find the matching task and check its status:

- Plan says `DONE`, all referenced task IDs `completed` → confirmed compact candidate.
- Plan says `DONE`, any referenced task ID still `in_progress` or `pending` → DRIFT. Report; do NOT compact.
- Plan says `PENDING` but all referenced task IDs `completed` → candidate for promotion to DONE (ask user for commit hash).
- No task IDs referenced → skip this check.

For IN_PROGRESS sections: do NOT compact. Consider expanding if thin (<10 lines of substantive content).

### Step 4 — Propose edits (do NOT apply yet)

**4a. Anchor uniqueness pre-check.** For each proposed compaction/expansion, pre-verify the `old_string` anchor is unique in the plan BEFORE proposing. Workflow:

1. Compose the anchor: heading line + first 2–3 body lines of the section.
2. Count occurrences: `Grep` for the anchor's first line (header + status) or the full anchor block.
3. If count > 1, extend the anchor downward (another 3–5 body lines) until unique.
4. If still not unique after 10+ body lines: FLAG this section as "manual-edit-required" in the proposal. Don't attempt to auto-edit.

This prevents reactive "Edit failed" loops by validating anchors up front.

**4b. Emit a structured preview** naming every section you intend to change. Include:

- Count of compactions, expansions, preservations, manual-edit-required
- Per-section: current range, current line count, proposed new line count, 1-line rationale
- Phase-0 sections explicitly flagged as PRESERVED (immutable)
- Sections flagged DRIFT from Step 3 (commit-hash or task-list mismatch) — will NOT be changed

**4c. Unified-diff preview.** For each approved compaction or expansion, show a mock unified diff before applying:

```diff
--- plan.md (before, lines A–B)
+++ plan.md (after, proposed)
- ### Phase 2: Frobnicate — lots of step-by-step detail
- 1. Do thing X
- 2. Do thing Y
-   - with sub-bullet a
-   - with sub-bullet b
- ...
+ ### Phase 2: Frobnicate — DONE (`abc1234`, Mar 10 2026)
+ - Shipped frobnicator. Commits: abc1234, def5678.
+ - Key learning: bare integer defaults avoid snapshot drift.
+ - Files: 3 changed (schema, migration, types).
```

**4d. Dry-run mode.** If user invoked `/plan-update --dry-run` OR explicitly said "dry run" / "preview only", STOP after 4c. Do not proceed to Step 5. Print the complete diff set and exit.

Otherwise wait for green-light unless the user pre-authorized ("proceed without asking", "auto", etc.).

### Step 5 — Apply edits

For each approved change, use `Edit` (never `Write`). Anchor uniqueness is already verified in 4a — just apply:

- `old_string` = the pre-verified unique anchor from Step 4a.
- `new_string` follows the compaction or expansion template exactly (see below).
- Preserve "Why:" lines, learnings, known issues, historical decisions verbatim inside the compact form.
- Never modify Phase 0 section structure. The Team Roster status row is the only field inside a Phase 0 that's safe to update (e.g., mark a teammate `shutdown`).

If an Edit still fails (file changed between Step 4 and Step 5): STOP, re-run Step 2 to rescan, re-propose. Do not blindly retry.

### Step 6 — Summary + handback

Report the before/after line counts, number of sections touched, and list of preserved Phase-0 sections. Remind the user:

- Backups live in `~/.claude/backups/` (last 10 per file)
- Plan-history auto-commits to `~/.claude/plan-history/plans/<name>.md`
- Recovery: `~/.claude/scripts/restore-file.sh <path> --list` → `--pick N`

Do NOT commit to the cwd git repo — the user decides when. Suggest: `/commit docs(plans): compact <plan-name>` when ready.

## Templates

### Completed Section Compaction

When a phase is done, compact it to 4-5 lines max. Preserve key learning and commit hash.

```markdown
### Phase N: Title — DONE (`commit_hash`, Date Month Year)
- Summary sentence describing what was delivered
- Key learning: specific insight discovered during implementation
- Blocker resolved: what blocked progress and how it was fixed
- Files: N files changed
```

**Example:**
```markdown
### Phase 5: Widget Schema — DONE (`abc123`, Mar 15 2026)
- Added widgetType + description columns. Migration 0045.
- Key learning: bare integer() needed for defaults (not timestamp_ms mode)
- Blocker resolved: pre-commit hook required staged migrations
- Files: 4 files changed (schema, migration, types, operationBuilder)
```

**What to remove:** Step-by-step implementation details, intermediate debugging sessions, command logs, iteration counts.

**What to keep:** The "why" (key learning), the "what" (one-liner summary), the "how it worked" (commit hash), blockers, file count.

---

### Upcoming Section Expansion

Upcoming phases are the working blueprint. Include file paths, line ranges, decision context, trade-offs, constraints.

```markdown
### Phase N: Title (Days X-Y)

**Objective**: One sentence describing the end state.

**Files & Changes**:
- `src/app/actions/replicache/tableServiceActions.ts:120-180` — Add X mutation, handle Y edge case
- `drizzle/schema.ts:450-480` — Add Z column with default value
- `replicache/types.d.ts:80-95` — Extend PanelGuest with new fields
- `lib/replicache/operationBuilder.ts` — Entire file for context (large)

**Implementation Steps**:
1. [Step 1 description with file:line reference]
2. [Step 2 with decision rationale]
3. [Step 3 with known gotcha or trade-off]

**Decision Context**:
- **Chose X over Y because**: [rationale]
- **Constraint**: [technical, stakeholder, or timeline constraint]
- **Trade-off**: [what we're optimizing for vs. what we're not]

**Known Issues**:
- [Issue 1]: [how to work around it or when to revisit]
- [Issue 2]: [investigation needed or blocked on external dependency]

**Blockers**:
- [Blocker 1]: Depends on Phase N-1 (will resolve when that phase completes)
```

**Example:**
```markdown
### Phase 2: Bottle Order Mutations (Days 3-5)

**Objective**: Implement all 12 bottle order mutations (create, update, delete, bulk operations).

**Files & Changes**:
- `lib/replicache/operationBuilder.ts:900-1100` — Add buildBottleOrderOperation with cascading deletes
- `src/app/actions/replicache/bottleActions.ts` — Entire file for mutation handlers
- `replicache/types.d.ts:200-250` — Add BottleOrder type with 8 fields
- `src/components/bottle-flow/BottleFlow.tsx:1-50` — Mutation call sites

**Implementation Steps**:
1. Grep "bottleOrder" in operationBuilder.ts to find parent entity structure
2. Add buildBottleOrderOperation — handle cascading delete of linked items
3. Implement 12 mutation handlers in bottleActions.ts
4. Update types.d.ts with BottleOrder interface
5. Test locally with pnpm db:setup (includes bottle test data)

**Decision Context**:
- **Chose cascading delete over soft delete**: Bottle orders are transient, not audit-required
- **Constraint**: Mutations must process sequentially (Replicache requirement)
- **Trade-off**: No undo/history for bottle orders — they're immediate and final

**Known Issues**:
- batchPrefetch doesn't include bottleOrder yet (will add in Phase 3)
- Local test data only — production seeding deferred to Phase 4

**Blockers**:
- Depends on Phase 1 (schema migration 0031 must be committed)
```

---

### Phase 0: Agent Team Orchestration (MANDATORY — Default for ALL Implementation Plans)

**Agent Teams are the DEFAULT for all implementation work.** Any plan with 2+ tasks that
write or modify code MUST include Phase 0 with full Agent Team orchestration. The user
expects 9/10 implementation sessions to use Agent Teams. Only omit Phase 0 for plans that
are purely research/exploration with no code changes.

If the implementation has only 1 task, a single agent suffices — but 2+ tasks → Agent Teams.

**Source**: `memory/PHASE_0_TEMPLATE.md` (refer to it for complete details)

```markdown
## Phase 0: Agent Team Orchestration — CRITICAL SETUP

### Pre-Flight Checklist

```bash
# 1. Verify agent teams feature enabled
grep CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS ~/.claude/settings.json

# 2. Ensure main branch is clean
git status  # Should be "On branch main, nothing to commit"

# 3. Create worktrees for each agent BEFORE spawning
git worktree add /tmp/worktree-agent1 feat/stream1/initials
git worktree add /tmp/worktree-agent2 feat/stream2/initials
# ... repeat for each agent

# 4. Verify custom agent exists (if needed)
ls -lh .claude/agents/schema-migration.md
```

### Team Roster

| Agent Name | Role | Worktree | Branch | Tasks | Model |
|------------|------|----------|--------|-------|-------|
| [agent-1] | [role] | `/tmp/worktree-[name]` | `feat/[stream]/[initials]` | 1, 2, 3 | opus |
| [agent-2] | [role] | `/tmp/worktree-[name]` | `feat/[stream]/[initials]` | 4, 5, 6 | opus |
| **team-lead** | Merge loop + verification | N/A | `main` | — | opus |

### Task Dependency Graph

| Task ID | Agent | Depends On | Description | Tokens | Type |
|---------|-------|-----------|-------------|--------|------|
| 1 | agent-1 | — | [Task description] | 150K | schema |
| 2 | agent-1 | 1 | [Task description] | 120K | mutation |
| 3 | agent-1 | 2 | [Task description] | 80K | ui |
| ... | ... | ... | ... | ... | ... |

### Spawn Wave Order

**Wave 1 (Schema)**: All agents work in parallel on independent schema changes (~45 min)
- Monitor for TypeScript errors
- Do NOT intervene unless idle >25 min without commits
- Expected completion: ~45 min

**Wave 2 (Mutations)**: Agents continue on their own streams in parallel (~60–90 min)
- Each agent finishes their mutation tasks
- Parallel execution — no inter-agent wait
- Expected completion: ~60–90 min after Wave 1

**Wave 3 (UI + Verification)**: Each agent completes UI and typecheck (~40–60 min)
- Expected completion: ~40–60 min after Wave 2

**Shutdown & Merge (Lead Only)**: Sequential shutdown of agents, then cherry-pick merge loop (~30 min)
- See "Merge Loop Plan" section below for detailed steps

### Manual Intervention Points

| Trigger | Action | Timing |
|---------|--------|--------|
| Agent idle >15 min (has commits) | Nudge via SendMessage | During wave |
| Agent idle >25 min (no commits) | Shutdown + respawn on fresh worktree | During wave |
| TypeScript error blocks commit | Agent self-fixes (monitor iTerm2 pane) | During wave |
| Context at 75%+ | Send "Pause, I'll /compact, then resume" | During wave |
| Context at 90%+ | Shutdown + respawn | During wave |

### Context Budget

**Per-agent**: 1M tokens total

| Phase | Budget | Notes |
|-------|--------|-------|
| Base (docs + code context) | ~50K | CLAUDE.md, schema, operationBuilder |
| Wave 1 (schema edits) | ~100–150K | Grep + read scoped sections |
| Wave 2 (mutations) | ~100–150K | Full file context, careful typing |
| Wave 3 (UI + build output) | ~80–120K | Components + typecheck |
| **Free buffer** | **500K+** | Unlikely to hit context limit |

### Merge Loop Plan (Lead Only)

After all agents complete and provide shutdown approval:

```bash
# 1. Verify all branches have clean git state
for branch in [branch1] [branch2] [branch3]; do
  echo "=== $branch ==="
  git diff $branch  # Should be empty
  git log --oneline -n 1 $branch
done

# 2. Cherry-pick code files (NOT .sql migrations)
git cherry-pick [branch1] -- drizzle/schema.ts replicache/types.d.ts lib/replicache/operationBuilder.ts

# 3. Generate migration (auto-applies to local DB, creates next sequential number)
pnpm generate

# 4. Commit atomically (schema + migration together)
git add drizzle/schema.ts drizzle/migrations/
git commit -m "feat(schema): description matching commit convention"

# 5. Repeat for each branch sequentially (parallel merges create conflicts)

# 6. Final verification
pnpm typecheck
pnpm build
pnpm migrate:lint
pnpm db:reset  # Apply all new migrations
pnpm dev       # Verify app starts
```

### Cleanup After Completion

```bash
# After all agents shut down and merge loop completes:
git worktree list | grep /tmp/worktree | awk '{print $1}' | xargs -I{} git worktree remove {}
git branch -d feat/[stream1]/cr feat/[stream2]/cr ...
TeamDelete
```

### Estimated Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| Pre-Flight Setup | 10–15 min | One-time |
| Wave 1 (Schema) | 45 min | Mechanical |
| Wave 2 (Mutations) | 60–90 min | Largest files |
| Wave 3 (UI) | 40–60 min | Pattern-matched |
| Shutdown | 2–5 min | Sequential |
| Merge Loop | 25–30 min | Lead only |
| Verification + Cleanup | 15 min | Final gate |
| **TOTAL** | **~4–5 hours** | Wall-clock time |

---
```

**For complete Phase 0 details** (pre-flight commands, spawn prompt templates, failure decision tree, success criteria): Refer to `memory/PHASE_0_TEMPLATE.md` — this template is an overview, that memory file is the executable reference.

---

## Decision Checklist

Before editing a plan file, verify:

- [ ] **Read first** — Ran Read tool to see current plan state, completed phases, and pending work
- [ ] **Edit not Write** — Will use Edit tool, not Write (preserves surrounding content)
- [ ] **Phase 0 exists** — If plan uses agent teams, Phase 0 is the first section before all other work
- [ ] **Preserve history** — All completed sections, key learnings, decisions, and known issues remain
- [ ] **Apply correct template** — Completed sections use compaction format, upcoming sections use expansion format
- [ ] **File paths have line ranges** — Upcoming sections include `file.ts:line-range` for specificity
- [ ] **Rationale documented** — Decision context, trade-offs, and constraints are clear

---

## Recovery & Safety Nets

Every Edit on a protected plan file is cushioned by three layers. Do not panic if a change looks wrong.

| Layer | What it does | Where it lives |
|---|---|---|
| Auto-backup on Write | `backup-before-write.sh` PreToolUse hook snapshots the file to `~/.claude/backups/<basename>__<ts>.bak` before any Write/MultiEdit. Last 10 per basename. | `~/Development/claude-infrastructure/hooks/backup-before-write.sh` |
| Plan-history git repo | `plan-version-commit.sh` PostToolUse hook auto-commits every plan Write/Edit to `~/.claude/plan-history/plans/<basename>.md` in a dedicated git repo. Full diff history. | `~/.claude/plan-history/` (separate .git) |
| Restore CLI | `restore-file.sh` atomically restores any backup by listing timestamps or picking the Nth most recent. | `~/.claude/scripts/restore-file.sh` |

Recipes:

```bash
# List every backup for a plan
~/.claude/scripts/restore-file.sh ~/.claude/plans/my-plan.md --list

# Restore the latest backup
~/.claude/scripts/restore-file.sh ~/.claude/plans/my-plan.md

# Restore a specific backup (3rd most recent)
~/.claude/scripts/restore-file.sh ~/.claude/plans/my-plan.md --pick 3

# Diff an earlier plan revision
cd ~/.claude/plan-history && git log --oneline plans/my-plan.md
git diff HEAD~3 -- plans/my-plan.md
```

If `backup-before-write.sh` injects an **OVERWRITE GUARD** warning, STOP: you called Write on a plan file. Switch to Edit. Restore from backup if the Write already completed.

---

## Trigger Phrases

This skill activates when the user says:

- "update plan" / "update the plan"
- "compact completed" / "compact plan section"
- "mark phase done" / "complete phase" / "finish phase"
- "generate Phase 0" / "add Phase 0" / "create Phase 0"
- "plan template" / "plan structure" / "plan conventions"
- "expand upcoming" / "restructure plan"
- "/plan-update" (explicit slash command, optional `[plan-name-or-path]` arg)
