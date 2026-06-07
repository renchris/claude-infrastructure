---
name: skill-promote
description: Promote a reviewed draft skill from ~/.claude/skills-pending/<slug>/ to the active ~/.claude/skills/<slug>/ after explicit human confirmation. Strips the draft frontmatter. Companion to /harvest-skill.
allowed-tools: Read, Bash, Edit, AskUserQuestion, Glob
argument-hint: "<slug> — the pending skill directory name to promote"
---

# /skill-promote — activate a reviewed draft skill

1. Resolve `<slug>` from `$ARGUMENTS`. Read `~/.claude/skills-pending/<slug>/SKILL.md`.
   If absent, list `~/.claude/skills-pending/*/` and STOP.
2. Show the full SKILL.md for review. Use **AskUserQuestion** to confirm
   (Promote / Edit-first / Cancel). NEVER promote without explicit approval.
3. On approval: `mkdir -p ~/.claude/skills/<slug>`, move the dir contents over, then strip the
   `status: draft` / `created_by:` / `origin_session:` frontmatter lines via Edit.
4. Report the active path. **If a same-named skill already exists, STOP and surface the conflict —
   do not overwrite** (global File Update Rule).
