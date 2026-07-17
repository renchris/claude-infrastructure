# Global Development Standards

## Rule Priority Legend

- 🚨 **CRITICAL** - Breaking causes production issues, data loss, security vulnerabilities
- ⚠️ **IMPORTANT** - Breaking causes significant rework or inconsistency
- 💡 **PREFERRED** - Style preference, improves quality
- 📝 **INFO** - Context/background, not actionable

---

## Code Style & Stack

Primary stack + language/style/file-naming conventions — Next.js 15/16 (App Router) · React 19 RSC · TS 5.9+ · Python FastAPI/Alembic/mypy-strict/ruff/Pydantic v2 · package manager by lockfile · TS strict-mode / explicit-return-types / interfaces-vs-types / named-exports / Server-Components-by-default / no-render-functions · PascalCase components, `use`-prefixed hooks, snake_case Python — live in the **coding-standards** skill, which auto-loads when you write or review code in those stacks. Git rules below stay always-resident.

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

### Plan Document Conventions

Plan/design/roadmap docs accumulate decisions across sessions → INTEGRATE never overwrite; completed sections compact (learnings + commit hashes + blockers), upcoming sections expand (file:line detail); **MANDATORY Phase 0 (Agent Team Orchestration) as the FIRST section** for any plan with 2+ code-writing tasks; never delete historical decisions / "Why:" rationale / learnings / known issues. Full conventions → the **plan-conventions** skill (the `backup-before-write` hook also auto-injects an abridged form on plan-file edits).

## Browser Automation

Browser automation — navigate / click / fill / screenshot / extract, or "No such tool available" for browser tools → the **browsermcp** skill: the `mcp__browsermcp__*` tool list + navigate→snapshot→ref→click workflow, wrapper + Chrome-extension setup, `.mcp.json` config, the troubleshooting decision tree, the `agent-browser` CLI fallback, and the auto-triggering `react-best-practices` / `vercel-design-guidelines` knowledge skills. Auto-loads on any browser-automation task.

---

## Agent Teams Reinforcement (All Projects)

**Agent Teams are the DEFAULT for all implementation work.** This applies globally.
Code-writing tasks with 2+ files MUST use Agent Teams (`team_name` + worktree isolation). Spawn
API is runtime-specific (see the **agent-teams** skill § Runtime assumption): classic `TeamCreate`
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

Full decision table, runtime detection, the 5-rule brief discipline, sizing, per-teammate
effort + model-pinning, **teammate lifecycle / graceful-shutdown / crash recovery** (previously
resident here), and post-crash scripts → the **agent-teams** skill (auto-loads before any teammate
spawn; the `agent-teams-enforce` PreToolUse hook also points to it on every Agent spawn).

---

## Research Subagents Reinforcement (All Projects)

Research subagents (no `team_name`, fire-and-forget) are disjoint from Agent
Teams; teammates write code, subagents never do. No parallelism cap;
decomposition determines count, not the reverse. Default N=12 for typical
complex research; sensitivity table in the **research-subagents** skill. Use the custom
`deep-research` subagent (`~/.claude/agents/deep-research.md`) when depth is
warranted (BUT: nested fan-out is not operational in stock Claude Code as of
May 2026 — recursion permission is aspirational; see Regression notes in
`deep-research.md`). Use `Explore` for fast terminal codebase lookups.

Per-subagent depth target: **150-250K tokens, hard ceiling 500K** (the prior
"500-800K" range landed in empirically-degraded context). See
the **research-subagents** skill for the pre-spawn artifact, the
task-category gate (multi-agent for breadth-first; single-agent for
depth-coordination), banned-phrase table, OASIS stop criterion, adversarial
sampling at 15-20%, partial-failure protocol, and synthesis bottleneck rules.

---

## Frontier Tier Routing

**Default model = Opus 4.8 @ effort max.** The frontier tier (currently Fable 5) is **opt-in only** — its value is exclusively the *delta above the default* (unknown-unknowns the default is blind to), NEVER routine/identified work; the lead itself never runs on it. Because the human never model-switches or starts frontier sessions, the agent **escalates autonomously but BOUNDED** (hook-enforced per-session spawn cap; a blocked spawn = PARK, never retry): capture holes with `/frontier-hole`, escalate with `/frontier-run` (inline ≤2 panelists on a blocking wall; batch at wrap-up when OPEN holes ≥ 2 and the window is active), long-horizon generator-class problems via `/frontier-campaign`. The full discipline — the 5 standing duties, supply-side discovery feeding, per-slot routing — is in the **frontier-routing** skill. SSOT: `~/.claude/model-config.yaml` (`frontier_access`). Ledger: per-project `docs/research/FRONTIER_HOLES.md`.

## Concurrent Sessions — Worktree Isolation (All Projects)

Multiple Claude Code sessions on ONE checkout share the git index → a bare
`git commit` in one session sweeps another's staged files; ref-lock races
(`cannot lock ref 'HEAD'`); shared-file clobber. Observed repeatedly.

**Rule — CONDITIONAL, not "always" (always-worktree taxes the 90% single-session case: cold `.next` rebuild, gitignored-state divergence, stale `/tmp` litter, wrong-dir mistakes):**

- **Single session** → work in the repo root on the default branch. NO worktree.
- **Read-only sessions** (research, audit, status, planning that writes NO tracked file) → no worktree; share root freely. Classify by *write footprint*, not intent — a session that writes a tracked plan/doc IS a writer for that file.
- **2+ concurrent WRITER sessions** → each writer gets its own worktree+branch via the **native flag `claude -w <name>`** (`--worktree`, optionally `--tmux`). Agent Teams already isolate teammates in worktrees — unchanged.

**Never commit or land in the shared checkout.** `~/Development/claude-infrastructure` is the symlink source for `~/.claude` and frequently sits on another session's feature branch. Committing there risks (a) landing onto a branch you did not create, and (b) a concurrent `/ship` of that branch rebase-dropping your commit — incident 2026-07-11: `dfacccd` (limit-recover skill, 5 new files) silently dropped by a sibling land of `feat/two-way-session-comms`; `git rev-list origin/main..HEAD` read 0 ('looks landed') while the files were absent from main. Always work in a dedicated worktree, commit on your OWN branch, and land via the project-local `/ship`. Verify landings by CONTENT (`git ls-tree origin/main -- <paths>`), never by count.

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

## Manual-Command Delivery

When you need the USER to run something themselves — an interactive login (`gcloud auth login`, `/login`), `sudo`, a safety-classifier-blocked or destructive op they must own, anything needing their terminal/credentials — do NOT scatter copy-paste commands inline in chat (TUI wrapping + smart quotes corrupt them). Write ALL of it to one `/tmp/<topic>-<purpose>.sh` with per-step `# comment`s, open it with `cursor`, and give a short walk-through that POINTS at the file. Full rule → the **manual-command-delivery** skill.
