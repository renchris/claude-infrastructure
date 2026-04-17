---
description: Populate Plan Mode document with a plan file's verbatim content (no synthesis, no research). Searches ~/.claude/plans/, .claude-plans/, docs/plans/ or accepts a direct path.
disable-model-invocation: true
allowed-tools: ExitPlanMode
argument-hint: <plan-filename-or-path>
---

You are in plan mode. Call `ExitPlanMode` exactly once, with the `plan` parameter set to the full markdown content below (everything after the `---` divider, until end of message). Verbatim. No edits, no research, no other tools, no commentary.

If the content below starts with "Plan not found:" or "usage:", abort and surface that error instead of calling ExitPlanMode.

---

!`~/.claude/scripts/find-plan.sh "$ARGUMENTS"`
