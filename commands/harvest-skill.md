---
name: harvest-skill
description: Draft a reusable skill (SKILL.md) from a just-finished session's workflow into a human-review staging area (~/.claude/skills-pending/). Never auto-promotes. Use after a session where you repeated a multi-step workflow worth capturing. Hermes skill-synthesis analog, human-gated.
allowed-tools: Read, Write, Bash, Glob, Grep
argument-hint: "[slug or short description of the workflow — optional; auto-detects from the recent session if omitted]"
---

# /harvest-skill — draft a skill from session experience (human-gated)

Synthesize a reusable skill from a workflow you just performed, into a STAGING area for review.
Mirrors hermes-agent autonomous skill creation, **minus the autonomous write** — the human
promotes it later with `/skill-promote`.

## Steps
1. **Pick the workflow.** If `$ARGUMENTS` names it, use that. Otherwise inspect the recent
   session: the in-context conversation, plus `~/.claude/skills-pending/_candidates.jsonl`
   (logged by the SessionEnd harvest hook — has `commands_run` / `files_changed` per session).
   Harvest-worthy = a multi-step procedure repeated >=2x OR a >=4-tool chain likely to recur.
   **If nothing qualifies, STOP and say so — do not invent one.**
2. **Draft the skill.** Write `~/.claude/skills-pending/<slug>/SKILL.md` with frontmatter:
   `name`, `description` (with a precise "Use when…" trigger), `status: draft`,
   `created_by: harvest`, `origin_session: <id>`. Body = the procedure as numbered steps,
   real file paths, and a `## Do NOT` anti-pattern section.
3. **Anti-capture gate (embed + obey):** SKIP capturing transient errors, environment/worktree
   one-offs, lucky paths, negative tool-claims, or anything an existing skill already covers
   (grep `~/.claude/skills` + `.claude/skills` first). Capture only durable, generalizable procedure.
4. **Report** the staged path + a one-line summary. Tell the user to review it and run
   `/skill-promote <slug>` to activate. **NEVER write into `~/.claude/skills/` directly.**
