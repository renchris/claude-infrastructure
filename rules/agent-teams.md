# Agent Teams: Cross-Project Orchestration Rules

Loaded by `~/.claude/CLAUDE.md` Agent Teams section. Applies to **every project**.

## Runtime assumption (CC version — corrected 2026-06-20)

**Two tracks, and BOTH are teams runtimes — they differ only in the team API surface:**
- **Stable** (`claude` / `cc` → CC **2.1.114**, deliberately pinned): exposes the classic
  **`TeamCreate` / `TeamDelete`** tools that this file's examples use.
- **Eval** (`claude-next` → CC **2.1.183**, the `~/.claude-183` binary): on **2.1.178+**, which
  **removed `TeamCreate` / `TeamDelete`** for an **implicit-team model** — you spawn teammates by
  calling the **`Agent` tool with `team_name`** (the runtime forms the team implicitly; the
  `TeamCreate`/`TeamDelete` *tools* simply don't exist). Agent Teams are ENABLED here
  (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and **validated working on 2.1.183** (verified
  2026-06-20). The earlier "183 is deliberately not a teams runtime / needs doc-migration first"
  framing is **superseded**. Stable 2.1.114 stays pinned — by *choice*, not by a teams gap.

**Detect the RUNNING runtime — do NOT trust `claude --version`.** `claude` / `cc` are shell
functions that resolve the *stable-pinned* launcher (`~/.claude-versions/current` → 2.1.114), so
`claude --version` reports **2.1.114 even inside a 2.1.183 `claude-next` session** — the classic
"claude is a shell function" trap, except it returns a plausible-but-wrong number instead of
failing, so the usual alarm doesn't fire. Identify the actual session by: the `AI_AGENT` env
(`claude-code_2-1-XXX_agent`), `CLAUDE_CODE_EXECPATH` (`.../.claude-183/...` ⟹ eval/2.1.183), the
parent process command, or **tool availability** (`TeamCreate`/`TeamDelete` present ⟹ 2.1.114;
absent ⟹ implicit-team model ⟹ 2.1.178+). **Absence of `TeamCreate` means USE the implicit-team
model — NOT "teams are unavailable, build solo."** (That wrong inference cost a session 2026-06-20.)

**When on the eval track:** read every `TeamCreate` / `TeamDelete` example below as the *2.1.114*
surface — do the equivalent via `Agent({ name, team_name, model, … })` to spawn + `shutdown_request`
to each teammate to tear down (there is no `TeamDelete` call). The teammate `model` MUST be on the
Max auto-mode allowlist (`claude-opus-4-8` / `claude-fable-5`); a bare background subagent is
hard-blocked from writing code, and `sonnet` silent-demotes to acceptEdits + breaks parallelism
(see `feedback-agent-team-models.md`). Validated end-to-end on 2.1.183 by an 8-teammate
worktree-isolated build (query/round-trip optimization), 2026-06-21. Stable hold recorded in
`~/.claude-versions/MANIFEST.jsonl` (`2.1.183 → skip`, eval-only — a launcher-nag silencer, not a
teams verdict).

## Decision Rule

| Task Type | Pattern |
|---|---|
| Writes/modifies code (2+ tasks) | Agent Teams (TeamCreate + worktrees) |
| Writes/modifies code (1 task) | Single agent in lead session OR one assignee |
| Research/exploration (no code) | `Explore` subagent (read-only, fire-and-forget) |
| 50+ parallel read-only tasks | Subagents |

## Why an Assignee at All

Spawn an assignee **to preserve LEAD context** — lead stays clean for orchestration,
synthesis, and direction; assignee burns its context on implementation.

This goal is **structurally defeated** if the assignee runs out of context mid-work.
Recovery costs lead context anyway, plus the friction of cleanup. Four observed
crashes (`doctor-green-gate 2026-04-17`, `routines-v1 Wave 2 2026-04-18`,
`validators-p0 2026-04-21`, `tp-assignee 2026-05-03`) all trace to brief-design
errors — not teammate output sizing.

## Brief Discipline (5 Mandatory Rules)

### Rule 1 — Brief ≤150 lines

Each brief line is processed at uncached rate. 250-line brief = ~5K tokens before any
work. 100-line brief = ~2K. Cap brief at 150 lines. Reference memory or docs files
for research context instead of inlining. Strip lead-mode framing ("from convergence:",
"21-agent research said:") — assignee doesn't need the meta-narrative.

### Rule 2 — Pre-grep line ranges, embed in brief

Before spawning, lead runs `grep -n "<symbol>" <file>` for every file the assignee
will touch. Embed the line numbers in the brief: *"Read lines 100-150 of file X for
the relevant region. DO NOT read the full file."* Brief becomes a guided tour, not
an open exploration. Saves 1-3K tokens per file.

### Rule 3 — Visual verification = separate fire-and-forget subagent

NEVER include screenshot loops in an implementation teammate brief. Screenshots are
multimodal tokens (~1500 per image). 5 screenshots × multiple inspection passes =
10-15K tokens just on verification. After implementation merge, spawn a separate
`Explore` subagent for visual verification — its context dies on return; doesn't
pollute the implementation teammate or lead.

### Rule 4 — "Stop on first issue, message lead" — no `investigate` language

"Investigate" → deep diagnosis loops. Teammate runs many bash commands, reads many
files, runs many evals. Each step adds context. Brief explicitly says: *"If you
encounter an issue: commit current work, send a 1-paragraph problem report to lead,
mark task in-progress with note, go idle. DO NOT debug. Lead decides whether to
fix-in-place, abandon, or spawn a debug subagent."*

### Rule 5 — Phase-by-phase checkpoints with explicit lead ack

Multi-phase briefs MUST require explicit lead ack between phases. Brief says: *"After
Phase A commit, send a one-line completion note to lead and AWAIT explicit go-ahead
before Phase B."* Or: split into separate teammates (one per phase, parallel via
worktrees or sequential via spawn-after-merge). Never one teammate doing 3 phases
solo — context accumulates across all of them.

## Pre-Spawn Checklist (Mandatory)

Before calling `Agent` for a teammate spawn, lead verifies:

- [ ] Brief is ≤150 lines (count it)
- [ ] Every file in scope has line ranges grepped + embedded
- [ ] Visual verification deferred to separate Explore subagent
- [ ] "Stop on issue, message lead" clause present verbatim
- [ ] Multi-phase has explicit checkpoint between phases (or split into separate teammates)
- [ ] Brief avoids: "investigate", "explore", "research more", "audit comprehensively"

If any box is unchecked, **rewrite the brief before spawning**. The pre-spawn cost is
low; the recovery cost (lead context burned salvaging a crashed teammate) is high.

## Sizing (per existing rules)

| Guardrail | Threshold |
|---|---|
| Output LOC target | ≤300 LOC (400 hard cap) |
| Reading radius (total input) | ≤2,000 LOC |
| Single-file read | No file > 2,000 LOC read in full |
| Domain cohesion | 1 domain per teammate |
| Brief length (NEW) | ≤150 lines |

## Per-Teammate Effort (2026-06-11 — binary-verified mechanism)

Teammate panes launch fresh `claude` processes that re-resolve their worktree's
`.claude/settings.local.json` — the lead's live effort is NOT forwarded. So per-member
effort IS settable, at worktree setup time:

```bash
~/.claude/scripts/set-teammate-effort.sh <worktree> low|medium|high|xhigh
```

Run it during Setup (after worktree creation, BEFORE spawn). Defaults per SSOT
`effort_defaults`: mechanical/routine → `high`; judgment-dense or `teammate_frontier`
(Fable) members → `xhigh`. Without an override, panes resolve the user-settings floor
(xhigh). `max` is settings-inexpressible (schema cap) — the script rejects it.

This does NOT apply to in-process subagents (Agent tool, no `team_name`): they inherit
the lead's live effort with no override surface (GH #25591/#25669/#31536/#65598 open).

## Model Pinning (2026-07-16 — corrects a latent SSOT contradiction)

Same mechanism as effort, one axis over: a **non-session model** (Fable while the lead
is Opus, etc.) requires an Agent-Team **assignee** — `Agent({ name, team_name, model })`
with `team_name` SET. Assignees honor `model` (allowlist: `claude-opus-4-8` /
`claude-fable-5`). **Bare / in-process subagents inherit the session model, and a
call-time `model:` override is silently ignored** — no error, it just runs on the
session model. Observed 2026-07-16 (CC 2.1.207, `.claude-secondary`): a `deep-research`
subagent spawned `model: "fable"` ran as **Opus 4.8** and hung ~35 min in "Hatching"
with zero output; re-spawning the identical brief as a teammate (`team_name` +
`model: "fable"`) is the fix.

⚠️ This **corrects** `~/.claude/rules/research-subagents.md`, which reads as if
`model: "fable"` on a bare `deep-research` subagent runs on Fable. That holds (if ever)
ONLY on the claude-next eval track — NOT universally. On any other track, route
non-session-model work through an assignee, or hand off to the desk's external
2-way orchestration (which spawns independent model-pinned CC instances outside the
internal subagent system). Never trust a bare-subagent `model:` override to take effect.

## Lifecycle

1. **Plan** — Phase 0 orchestration in plan document
2. **Pre-spawn checklist** — verify all 6 boxes (above)
3. **Setup** — Create worktrees manually, TeamCreate, spawn teammates
4. **Execute** — Teammates work, lead monitors via TaskList + completion notifications
5. **Merge** — Sequential cherry-pick for schema-touching work; git merge for independent work
6. **Cleanup** — `shutdown_request` to each teammate, remove worktrees, TeamDelete

## When Things Go Wrong

If a teammate crashes (context limit / `/compact` regression):

1. **Don't `claude --resume`** — that fails (GH #49593)
2. Inspect the worktree state with `git log --oneline` and `git status`
3. If commits exist: lead can fast-forward merge, then continue from there
4. If only uncommitted: lead commits AS LEAD on the teammate's branch (`git -C /tmp/wt-X/ commit ...`), then merges
5. Document in an incident memory file (`incident-<teammate>-context-<date>.md`)

References per-project:
- `<project>/.claude/rules/agent-teams.md` — project-specific overrides
- `<project>/memory/feedback-assignee-brief-discipline.md` — full rationale
- `<project>/memory/incident-*-context-*.md` — past crash records
