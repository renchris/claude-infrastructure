# Global Development Standards

## Rule Priority Legend

- 🚨 **CRITICAL** - Breaking causes production issues, data loss, security vulnerabilities
- ⚠️ **IMPORTANT** - Breaking causes significant rework or inconsistency
- 💡 **PREFERRED** - Style preference, improves quality
- 📝 **INFO** - Context/background, not actionable

---

## Primary Stack

- Frontend: Next.js 15/16 (App Router), React 19 Server Components, TypeScript 5.9+
- Backend: Python FastAPI, Alembic, mypy strict, ruff
- Package Managers: Check project lockfile (pnpm-lock.yaml → pnpm, bun.lockb → bun, package-lock.json → npm)
- Infrastructure: AWS, Fly.io, Harness.io, Kubernetes

## Code Style

### TypeScript/JavaScript

- Strict mode always - No implicit any
- Explicit return types for exported functions/APIs; infer for React component returns

**Examples:**
```typescript
// ✅ Exported function - explicit return type
export async function getUser(id: string): Promise<User> { ... }

// ✅ React component - inferred return
export function UserCard({ user }: Props) { ... }

// ✅ Internal helper - inferred
function formatDate(date: Date) { ... }
```

**Interfaces vs Types:**
```typescript
// ✅ Interface for object shape
interface User { id: string; name: string }

// ✅ Type for union
type Status = 'pending' | 'success' | 'error'

// ✅ Type for utility
type PartialUser = Partial<User>
```

- ESLint Airbnb ruleset
- Server Components by default (Next.js App Router only)
  - Add `'use client'` ONLY when component needs: useState/useEffect, browser APIs, event handlers, or browser-context libraries
- Prefer interfaces for object shapes, types for unions/utilities
- Named exports over default exports (except pages/layouts)
- **Never use render functions** (`const renderX = () => <JSX/>` called as `{renderX()}`) inside components — extract as a named component instead. Render functions bypass React reconciliation, can't hold hooks, and recreate on every parent render.

### Python

- Type hints always - mypy strict compliance
- ruff for linting and formatting
- Pydantic v2 for data validation
- FastAPI: dependency injection, async handlers

### Git Commit Messages

- Lowercase start (except proper nouns)
- No redundant verbs: `feat: authentication` not `feat: add authentication`
- Conventional Commits: feat|fix|docs|style|refactor|test|chore

### Git Commit Workflow

**Commit proactively — one atomic commit per completed logical task, as you go,
without waiting to be asked.** Pushing to origin stays the user's explicit call
(see Git Safety). Each commit follows these rules:

1. **One commit per logical task.** Each task/phase/fix gets its own atomic commit.
   Never bundle unrelated changes. Never commit pre-existing unstaged changes from
   prior sessions — save them with `git diff > /tmp/stash.patch`, restore after.
2. **Isolate mixed-change files.** When a file contains changes from multiple tasks
   or sessions: `git checkout -- <file>`, re-apply only the current task's changes
   via Edit, stage, commit, then restore the rest from the saved patch.
3. **Fixup when amending an existing commit.** Use `git commit --fixup=<hash>` when
   the change is a correction to a specific prior commit (typo, missed file, bug
   introduced by that commit). For new work, always create a new commit.
4. **Autosquash without interaction.** When fixup commits exist and the user requests
   squash: `GIT_EDITOR=true git rebase --autosquash <base>`. This bypasses the
   editor, making it non-interactive and safe to run.
5. **Scope check.** Before staging, run `git diff --name-only` and confirm every file
   belongs to the current task. If unsure, ask.

### Git Safety

- **Never use `--no-verify` to bypass pre-commit hooks.** If a hook blocks your commit,
  it caught a real issue. Fix the underlying problem instead of bypassing the safeguard.
- Never force push to main/master
- **`git push` only on explicit user request** — commit per task and accumulate locally; the user decides when to push to origin.
- Never run destructive commands (hard reset, force push) without explicit user request
- Never run interactive git commands (rebase -i, add -i) - they require terminal interaction
- **Never run `git clean` with `-x` or `-X` flags** — these delete gitignored files which may include paid assets (AI-generated images, API outputs) that cost real money and have cooldown periods to regenerate. `git clean -f -d` (without -x) is safer but still confirm with user first.
- **Never `git add -f` gitignored directories** — if something is in `.gitignore`, it's intentional. Force-adding bloats git history with binaries and defeats the protection that gitignore provides against `git clean -f -d`.

### File Naming

- React components: PascalCase (`UserProfile.tsx`)
- Client components: Add `'use client'` directive at top (NOT filename suffix)
- Hooks: `use` prefix (`useAuth.ts`)
- Python: snake_case (`user_service.py`)

## AI Guidelines

- Check for existing patterns before making changes
- Look for project-level CLAUDE.md
- Run linters before commits (use project's package manager, not a default)

### File Update Rule (CRITICAL — All Agents)

**INTEGRATE new content into existing files — NEVER overwrite or delete existing sections.**

This rule applies to ALL file types: plans, docs, CLAUDE.md, memory, research, runbooks.
It applies to the lead agent AND every subagent/teammate.

| Action | Tool | When |
|--------|------|------|
| Update a section | `Edit` | Always — targeted replacement preserves surrounding content |
| Add a new section | `Edit` | Append after the last relevant section |
| Full rewrite | **NEVER** | Do not use `Write` on existing files unless creating from scratch |
| Restructure | **Ask user first** | Propose the new structure, get approval |

**If you see the PreToolUse warning "OVERWRITE GUARD"**: Stop. Switch to `Edit`. If the
file has already been overwritten, restore immediately:
```bash
~/.claude/scripts/restore-file.sh /path/to/overwritten/file
```

**Why this is CRITICAL**: Plan files, research docs, and CLAUDE.md accumulate decisions
and context across sessions. A full rewrite destroys that history. This has happened
multiple times and caused significant rework.

**Recovery**: All Write operations to existing files are auto-backed up by the
`backup-before-write.sh` PreToolUse hook. Backups are in `~/.claude/backups/`.

### Memory Hygiene — Anti-Capture List (CRITICAL — All Agents)

When writing memory (a `MEMORY.md` index line or a topic file) or proposing a skill,
persist only **durable, generalizable** knowledge. **SKIP** — do NOT encode as a
permanent rule:

- **Transient errors** — a flake, a one-off network/rate-limit failure, a CI hiccup.
- **Environment-specific one-offs** — a path/port/state true only of this machine,
  worktree, or moment.
- **Lucky paths** — "X worked once" with no reason it generalizes.
- **Negative tool-claims** — "tool Y can't do Z" inferred from one failed call.
  Verify before encoding; a wrapper/flag/version usually explains it. (Live example:
  `claude --version` "failed" only because `claude` is a shell function — the real
  binary `claude-latest` was fine.)
- **Anything already indexed** — grep `MEMORY.md` first; update the existing entry
  instead of adding a near-duplicate.

Capture instead: reusable rules, durable decisions **+ their why**, confirmed
constraints, and corrections to prior memory. **Why:** this prevents memory rot — an
agent hardening a transient failure into a permanent self-imposed refusal. (Adapted
from hermes-agent `agent/background_review.py` `_DO_NOT_CAPTURE`; the most portable
idea in that repo. `/compact-memory`, `/harvest-skill`, and the `memory-nudge.sh`
hook all embed this same list.)

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

### Agent Teammate Lifecycle (CRITICAL — All Sessions)

**TeammateIdle hook auto-shuts down idle teammates** (`~/.claude/hooks/teammate-auto-shutdown.sh`).
No orphaned panes — teammates terminate immediately when they finish work.

**Graceful shutdown (redesigned Apr 18 2026; pane-close fixed for CC 2.1.161 on 2026-06-05 — 5 rules):**
1. **Checkpoint FIRST.** The auto-shutdown hook invokes `teammate-checkpoint.sh`
   with a synthetic `TeammateIdle` payload BEFORE removing the worktree. The
   checkpoint uses git plumbing (`read-tree` + `add -A` + `write-tree` +
   `commit-tree`) — bypasses pre-commit entirely, captures tracked +
   untracked files, zero impact on working tree. Writes
   `refs/checkpoints/<member>/<ts>` + `refs/wip/<member>/LAST` (fast-path alias).
2. **Fallback patch.** If checkpoint fails, the hook also writes
   `/tmp/<team>-<member>-<ts>.patch` with status + diff HEAD for manual recovery.
3. **Defer on dirty tree** (up to `TEAMMATE_MAX_DEFERS=3`). TeammateIdle fires
   3-4× per teammate in multi-turn work; reaping on first idle was wrong.
   The hook now snapshots + defers until the teammate actually quiesces.
4. **Cooperative marker.** If `<worktree>/.teammate-busy` exists, defer
   unconditionally. Teammate writes it before multi-turn work, removes on done.
5. **Only then reap** — close the EXACT pane, then `git worktree remove`. The
   pane id comes from the team `config.json` member field `tmuxPaneId` (iTerm2
   session UUID, or tmux `%N`) and is closed with `it2 session close -f -s <id>`
   / `tmux kill-pane -t <id>`.
   **The old `kill -TERM $PPID` was the "closes too early / inconsistent" bug**:
   a TeammateIdle hook runs LEAD-side as `lead-claude → /bin/sh -c → bash`, so
   `$PPID` is the already-dead `/bin/sh` shim — the backgrounded kill hit a
   PID-RECYCLED process (the lead or an unrelated shell). Targeting the recorded
   pane id is deterministic. **⚠️ 2026-06-09 correction**: the it2 CLI's `-f`
   never propagates force to the API (it only skips its own TTY confirm), and
   iTerm2's non-forced API close prompts on running-job panes REGARDLESS of the
   never-prompt profile — so the `~/.claude/bin/it2` shim now intercepts
   `session close -f -s <id>` too and closes via python `async_close(force=True)`
   (the only reliable no-modal close; the `Claude-Teammate` profile covers ⌘W
   only). Fixes the hook AND CC's native `killPane` at one choke point. See
   memories `it2-session-close-force-modal-2026-06-09.md` +
   `teammate-pane-close-2.1.161.md` (corrected in place).

**Respawn recovers uncommitted work**: `scripts/team/respawn-team.sh <team>`
emits Step 0 — Checkpoints section showing each member's
`refs/wip/<member>/LAST` SHA + cherry-pick / reset --soft / diff HEAD recipes.
New teammates resume from the checkpoint before starting new work.

**Subagents vs Teammates (Agent Teams = Default):**
- **Teammates** (`team_name` set): **DEFAULT for all implementation.** Persist until shutdown. Max **6 concurrent**. Use for ANY task that writes code.
- **Subagents** (no `team_name`): Research/exploration ONLY. Auto-terminate after returning results. Safe at ~50 parallel. Never for code changes.

**Shutdown Protocol:**
1. Send `{"type": "shutdown_request"}` to EACH teammate individually (parallel OK)
2. Plain text broadcasts do NOT close panes — only structured `shutdown_request` works
3. Kill iTerm2 pane manually if needed: `killall -9 tmux` (pane dies; agent stays until timeout)
4. Clean worktrees: `git worktree remove /tmp/worktree-<name>` (or `/tmp/wt-<team>-<name>`)

**Liveness detection (pull-based, race-free):**
- `verify-team.sh <team> --strict-liveness` checks iTerm2 pane presence via
  osascript on `tmuxPaneId` and cross-references `~/.claude/logs/teammate-lifecycle.log`.
- The `isActive` flag in `~/.claude/teams/<team>/config.json` is harness-owned
  and write-once-at-spawn — NEVER trust it as "alive now". Use pull-based checks instead.

**If teammate hangs**: (stable 2.1.114) GitHub #31788 — `TeamDelete` can block permanently. Kill pane, manually remove `~/.claude/teams/<team-name>`. Checkpoint refs survive in the worktree's `.git/` — run `git for-each-ref refs/wip/<member>/LAST` to recover. On the 2.1.183 implicit-team model there is no `TeamDelete` — send `shutdown_request`; if it hangs, kill the pane + `git worktree remove`.

**Known limitations**: No session resumption with in-process teammates, context compaction can break coordination, one team per session.

## BrowserMCP

Use BrowserMCP (not Playwright) for browser automation:

```
mcp__browsermcp__browser_navigate   - Navigate to URL
mcp__browsermcp__browser_snapshot   - Get page accessibility tree (use for element refs)
mcp__browsermcp__browser_click      - Click element by ref
mcp__browsermcp__browser_type       - Type into element
mcp__browsermcp__browser_screenshot - Capture screenshot
mcp__browsermcp__browser_press_key  - Press keyboard key
mcp__browsermcp__browser_hover      - Hover over element
mcp__browsermcp__browser_wait       - Wait for time (seconds)
```

Workflow: `navigate` → `snapshot` → use `ref` from snapshot → `click`/`type`

**Setup**: Wrapper script (`~/bin/browsermcp-wrapper.sh`) ensures NVM/PATH consistency. Chrome extension 1.3.4+ required (install from [Chrome Web Store](https://chromewebstore.google.com/detail/browser-mcp-automate-your/bjfgambnhccakkhmkepdoekmckoijdlc), connect per tab).

**Project Config** (`.mcp.json`):
```json
{
  "mcpServers": {
    "browsermcp": {
      "command": "/Users/chrisren/bin/browsermcp-wrapper.sh",
      "timeout": 15000
    }
  }
}
```

**Troubleshooting Decision Tree:**

| Symptom | Solution |
|---------|----------|
| Tools unavailable after `/compact` (GitHub #3426) | Start fresh session (`/exit` then `claude`) |
| Wrapper script fails | `claude mcp remove browsermcp -s project && claude mcp add browsermcp -s project -- npx -y @browsermcp/mcp` |
| Extension not connecting | Reinstall, pin to toolbar, click "Connect" per tab |

See [BrowserMCP Docs](https://docs.browsermcp.io/setup-server), [Issue #3426](https://github.com/anthropics/claude-code/issues/3426), [Issue #1611](https://github.com/anthropics/claude-code/issues/1611), [Issue #723](https://github.com/anthropics/claude-code/issues/723) for details.

### agent-browser (CLI Fallback)

When BrowserMCP unavailable, use `agent-browser`:

```bash
agent-browser open <url>                    # Navigate
agent-browser snapshot -i                   # Get interactive elements
agent-browser click @e1                     # Click by ref
agent-browser fill @e2 "text"               # Fill input
agent-browser close                         # Close browser
```

For existing browsers via Chrome DevTools Protocol: `agent-browser --cdp 9222 snapshot -i`

**Troubleshooting**: `agent-browser install` (missing Chromium), `--headed` flag (debug), `--cdp 9222` (connect to running browser).

### Vercel Agent Skills (Knowledge-Based)

Two auto-triggering knowledge skills from `vercel-labs/agent-skills`:

| Skill | Auto-Triggers On | Provides |
|-------|------------------|----------|
| `react-best-practices` | "optimize performance", "review React code", "check for waterfalls" | 45+ performance rules (Promise.all, barrel imports, React.cache, dynamic imports) |
| `vercel-design-guidelines` | "review my UI", "check accessibility", "audit design" | 8 audit categories with file:line references |

For explicit invocation: describe what you want ("review my component for performance issues"). Deep dives: reference rule files in `~/.claude/skills/react-best-practices/references/rules/`.

---

## Agent Teams Reinforcement (All Projects)

**Agent Teams are the DEFAULT for all implementation work.** This applies globally.
Code-writing tasks with 2+ files MUST use Agent Teams (`team_name` + worktree isolation). Spawn
API is runtime-specific (see `rules/agent-teams.md` § Runtime assumption): classic `TeamCreate`
on stable 2.1.114; on the 2.1.183 implicit-team model there is no `TeamCreate` — spawn via
`Agent({ name, team_name, model: opus|fable-5 })`. Background subagents (no `team_name`) are for
research/exploration only — never for code changes.

**Split during planning, not after crash.** If any teammate's deliverable >500 LOC,
SPLIT into 2-3 teammates in Phase 0. **Brief body ≤150 lines** (tightened from 200
after tp-assignee crash 2026-05-03). Reading list >5 files = too wide. `/compact`
crashes teammates (GH #49593) — preventive splitting is the only reliable path.

**Mandatory pre-spawn checklist** for every Agent call with `team_name`:
1. Brief ≤150 lines (count it)
2. Pre-greped line ranges embedded for every target file
3. No visual verification inline (defer to separate Explore subagent post-merge)
4. "Stop on issue, message lead" clause verbatim
5. Multi-phase = explicit checkpoint or split into separate teammates
6. No "investigate" / "explore" / "audit" language

See `~/.claude/rules/agent-teams.md` for full decision table, lifecycle, brief
discipline rationale, and post-crash recovery scripts.

---

## Research Subagents Reinforcement (All Projects)

Research subagents (no `team_name`, fire-and-forget) are disjoint from Agent
Teams; teammates write code, subagents never do. No parallelism cap;
decomposition determines count, not the reverse. Default N=12 for typical
complex research; sensitivity table in the rule file. Use the custom
`deep-research` subagent (`~/.claude/agents/deep-research.md`) when depth is
warranted (BUT: nested fan-out is not operational in stock Claude Code as of
May 2026 — recursion permission is aspirational; see Regression notes in
`deep-research.md`). Use `Explore` for fast terminal codebase lookups.

Per-subagent depth target: **150-250K tokens, hard ceiling 500K** (the prior
"500-800K" range landed in empirically-degraded context). See
`~/.claude/rules/research-subagents.md` for the pre-spawn artifact, the
task-category gate (multi-agent for breadth-first; single-agent for
depth-coordination), banned-phrase table, OASIS stop criterion, adversarial
sampling at 15-20%, partial-failure protocol, and synthesis bottleneck rules.

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

---

## Concurrent Sessions — Worktree Isolation (All Projects)

Multiple Claude Code sessions on ONE checkout share the git index → a bare
`git commit` in one session sweeps another's staged files; ref-lock races
(`cannot lock ref 'HEAD'`); shared-file clobber. Observed repeatedly.

**Rule — CONDITIONAL, not "always" (always-worktree taxes the 90% single-session case: cold `.next` rebuild, gitignored-state divergence, stale `/tmp` litter, wrong-dir mistakes):**

- **Single session** → work in the repo root on the default branch. NO worktree.
- **Read-only sessions** (research, audit, status, planning that writes NO tracked file) → no worktree; share root freely. Classify by *write footprint*, not intent — a session that writes a tracked plan/doc IS a writer for that file.
- **2+ concurrent WRITER sessions** → each writer gets its own worktree+branch via the **native flag `claude -w <name>`** (`--worktree`, optionally `--tmux`). Agent Teams already isolate teammates in worktrees — unchanged.

**Fresh-worktree setup** (gitignored files are absent): copy `.env*`/secrets + set up the local DB per-worktree (never symlink either); run the package-manager install — with pnpm it's hardlink-cheap from the store, so **`pnpm install --frozen-lockfile`, never symlink `node_modules`** (breaks pnpm's isolated layout + native bins). Use **distinct dev + inspector ports** per worktree (the `--inspect` port collides silently). A repo-root **`.worktreeinclude`** (gitignore-syntax) auto-copies gitignored files on newer CC; a project `scripts/new-worktree.sh` wires the rest where present.

**Merge back:** rebase-onto-default + `--ff-only`, serialized, **smallest-diff first**; **`git rerere` enabled globally** (auto-resolves repeated same-hunk conflicts across branches). Worktrees do NOT prevent same-hunk, JSON-array-append (migration journals/checksums), lockfile, or *semantic* conflicts → designate a **single owner per shared file**, **serialize migration-generating sessions**, and gate every merge with `typecheck` + `lint`.

**Caveats:** prefer manual `claude -w` over the Agent tool's `isolation: "worktree"` — parallel *automated* worktree creation has had `.git/config.lock` races + a data-loss bug (GH #34645, #48927; manual `-w` is unaffected). Never run `git restore .` / `git checkout -- .` in the main tree while linked worktrees hold staged work (shadows their edits). jj workspaces are architecturally better but blocked on stock CC (GH #27466) — revisit later.

---

## Session Close Protocol (All Projects)

🚨 Drive in-scope work to a finished, verified, committed state **without stopping to ask**;
surface everything else; end every *write* turn with one un-fakeable state readout — replacing
the manual "are we complete / loose-ends / handoff?" close. **Mechanism = this rule + a `/wrap`
command. NO Stop hook** (a Stop hook can't see scope and can't reach the model except by
*blocking* — an infinite-loop anti-pattern; an advisory `additionalContext` Stop hook is inert).
The agent runs the git/gate reads itself, so the ledger reports facts, not self-report.

**Freeze the DoD at intake.** The first time a task will write tracked files, restate the user's
ask as one line — **`Scope (frozen): …`** (in the plan, else inline). Close-time completeness is
then a *diff against that contract*, never a fresh re-judgment — the brake on scope-metastasis.
Unreconstructable scope is itself a STOP-ASK, never a guess.

**Disposition by end-state** (a turn is usually several at once → judge per task, not per turn):

| End-state | Action |
|---|---|
| Read-only / advisory / research (no tracked writes) | **No ledger, no auto-continue.** Answer and yield. |
| In-scope: unwritten / unverified / uncommitted | **Auto-continue:** finish → run gate → commit (atomic, explicit paths). ≥2 code tasks → Agent Teams. |
| In-scope: gate ran **red** | **Auto-debug** the root cause (cap ~2 cycles → commit partial + report). Never blind-retry, never bypass the hook. |
| Committed, **not pushed/landed** | **Terminal-valid** — a neutral fact, *not* a loose end. Offer ship/land as the user's call. |
| Needs a **decision** (destructive migration / auth / nav pattern / timeout) or **info** | **STOP-ASK** (overrides auto-continue); commit in-progress work first. |
| Out-of-scope discovery | **Name + backlog** (durable write), never pursue — unless security / data-integrity, then **stop-surface now**. |
| Genuinely complete | **Assert plainly, no hedge.** |
| Context / budget exhausted, work remains | **`/handoff`** — never fake completion. |

**Auto-continue is permitted IFF all four hold** — else surface/ask, do not continue:
**G1** inside the frozen DoD (not an adjacency, not unobserved-problem hardening) ·
**G2** touches no escalation surface (auth/session, destructive migration, navigation pattern, DB timeout) ·
**G3** the action is local — edit / run-gate / commit; **never push / deploy / ship / land** (that is always the user's explicit call) ·
**G4** the commit is task-clean (explicit paths; never sweep unrelated / parked / other-session changes).
Honor explicit pauses ("stop here", "come back to this") as terminal-valid parked WIP.

**"Done this turn" — assert with zero hedge IFF:** scope-complete vs the frozen DoD · statically
green (the repo's commit-time gate passed on the closing commit; "n/a", never a false ✓, for
docs/SQL-only commits) · behaviorally green (the repo's test/build/visual gates **run this turn**,
not recalled — re-run after any rebase/merge/cherry-pick) · no pending decision. Otherwise **hedge
with the clearing verb** ("implemented but UNVERIFIED — running tests"; "blocked on your decision:
DROP X"), never "probably fine".

**The readout** — emit at every write-turn close; **suppress on read-only turns**. Default = **ONE
line**: the governing state (Pyramid, answer-first), from live reads not memory. Pick the worst-open
rung (priority **⛔ > 📤 > 🔧 > 📦 > ✅**); each is exactly one disposition row above (the map stays MECE):

| State | = disposition row | One-line readout |
|---|---|---|
| ⛔ **Blocked** | needs a **decision** (destructive migration / auth / nav / timeout) or **info** | `⛔ Blocked — need your call: <decision>.` |
| 📤 **Handoff** | context/budget exhausted, work remains | `📤 Out of context — /handoff.` |
| 🔧 **Loose ends** | unwritten / unverified / uncommitted, or a gate ran **red** | `🔧 Loose ends — continuing.` |
| 📦 **Parked** | committed, **not pushed/landed** (`trunk..HEAD > 0`) | `📦 Done, but only on a branch — /ship to land it (else lost).` |
| ✅ **Live** | genuinely complete AND on trunk (`trunk..HEAD = 0`, clean) | `✅ Complete & live on trunk — nothing to do.` |
| _E0_ read-only (no tracked writes) | — | **no readout** — answer and yield |

`📦` vs `✅` (*committed ≠ landed*) is the load-bearing split — it surfaces the branch-stranded risk.
The line's verb = the `→ Next` below; only ⛔/📦 wait on the user, the rest auto-continue. Mixed turn →
show the worst-open rung only.

**Opt-in detail** (`/wrap --full` / on request) appends the dense per-field ledger — never the default:

```text
SESSION LEDGER  (live git/gate reads · base = origin trunk)
Scope (frozen): <DoD>          Remainder: <none | …>
Done&verified:  tsc <✓|n/a> · lint <✓|n/a> · test <0|NOT-RUN> · build <0|n/a> [+ repo gates]
Committed:      <N> — NOT pushed   (<short shas>)
Landed/shipped: <trunk..HEAD count>   (>0 ⇒ committed, parked — your call)
Blocked on you: <decision/info | none>
Out of scope:   <named → file | none>
→ Next:         <ONE verb: continue · commit · run-gate · STOP-ASK · /handoff · "Complete in full">
```

**Auto-continue actuation (🔧 only).** On the 🔧 state — and ONLY 🔧 — arm the continuation hook so a
turn-close re-prompts you instead of stopping with work left: `~/.claude/hooks/session-continue.sh set
"<the ONE next step>"`. **Clear it** (`~/.claude/hooks/session-continue.sh clear`) the instant the state
becomes ✅ / 📦 / ⛔ / 📤, on a read-only turn, or when the kill-switch fires — those MUST stop. A Stop
hook actuates it (`decision:block` feeds the step back as your next turn); a hard cap
(`CLAUDE_CONTINUE_MAX`, default 8) bounds runaway. Scope-judgment stays with YOU (only you see the frozen
DoD) — the hook is a dumb actuator. This is the *cross-turn* arm of auto-continue; *within* a turn you
just keep working (don't stop on 🔧 in the first place).

The single `→ Next` verb may be **auto-fired** for continue / commit / run-gate / handoff; ship and
land are only ever **offered**, never the default verb (no editorializing toward pushing — push is
the user's call). Per-project gate names, escalation greps, and the trunk live in the project
`CLAUDE.md` "Session Close" section; `/wrap` computes the ledger from live git/gate reads.

**Kill-switch:** any per-prompt "…and stop", "no auto-continue", or "just do X" suspends
auto-continue for that turn — surface and yield instead.

---

## Manual-Command Delivery (All Projects)

When you need the USER to run something themselves — anything you can't or shouldn't run: interactive
logins (`gcloud auth login`), `sudo`, a safety-classifier-blocked action, a force-push / destructive op
they must own, or any command needing their terminal/credentials — do NOT scatter copy-paste commands
inline in chat. TUI line-wrapping, smart quotes, and markdown fences corrupt them on paste (heredocs and
anything with quotes/URLs especially). Instead, EVERY time:

1. Write ALL of it to one `/tmp/<topic>-<purpose>.sh` — plain shell, one clean block per step, each
   preceded by a `# comment` (what it does, why, required vs optional, expected output).
2. Open it: `cursor /tmp/<topic>-<purpose>.sh` (print the path if the `cursor` CLI is absent).
3. In chat, give a SHORT walk-through that POINTS at the file (step names + effect + expected output) —
   never restate the commands inline.

Standing pattern for every manual hand-off, in all sessions and repositories. `/tmp` only —
regenerable, disposable, never committed. **Why:** copy-paste fidelity — a wrapped/smart-quoted heredoc
pasted from chat silently breaks; a file opened in Cursor is exact. The inline chat carries the
*walk-through*, the file carries the *commands*.
