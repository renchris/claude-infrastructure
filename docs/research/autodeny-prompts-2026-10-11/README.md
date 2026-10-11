# Timed auto-deny permission prompts — investigation 2026-10-11

Question: how often do sessions hit "Claude Code will automatically deny this request in M:SS, to avoid blocking
progress on an unattended session", do we hold a record of all of them, and how do we stop them.

Scope (frozen): census the timed auto-deny prompts from every local record, explain the CC 2.1.293 mechanics, and land
the fixes that survived adversarial review (C1 PermissionRequest deny-with-recipe hook + its registration migration,
C2 workflow-lean/deep-research guidance, C4 `bin/cc-autodeny-census`, C5 narrow allow rules handed to the operator).

## Findings

- 64 unique timed/auto-denied prompts, 2026-09-29 → 2026-10-11 (82 raw rows across 4 account stores, deduped by
  tool_use_id): 50 timed out after 120 s, 11 denied without a dialog (the 3-per-session cap), 3 in subagents that cannot
  prompt. 51 were workflow agents (42 workflow-lean). 48 of 64 fell on 10-10/10-11; 57 on CC 2.1.293.
- ALL 64 are CC's dangerous-removal safety check (`circuitBreaker:"dangerousRemoval"`, `classifierApprovable:false`).
  No allow rule, PreToolUse allow or bypass mode clears it. 40 are false positives: a `bash -c` script with NO rm that
  the 2.1.293 inline-shell scanner cannot read (a function, `"$@"` runner, `$VAR` as a command, source/eval, `set --`,
  brace expansion). The rest: `cd X; rm rel/*` (12), unguarded `$VAR/` rm targets (8), real rm inside `-c` (3), 1 probe.
- Classifier denial-limit fallback (the other timed dialog): 3 inferred, none since 2026-09-26.
- Telemetry: no local store records all of them. CC's own events (`tengu_safety_check_dialog_auto_denied` etc.) are
  remote-only; transcripts are the only complete local record (dedupe across stores). The permission-archive beacon saw
  26/48 and cannot tell an auto-deny from a human deny; supervisor pages arrive after the 120 s timer fires.

## Files

| file | content |
|---|---|
| mechanics.md | CC 2.1.293 reverse-engineering: triggers, timers, precedence, env switches |
| lead-notes.md | the inline-shell `"$@"` trigger traced from the operator's screenshot |
| local-telemetry.md / inventory.md | record coverage per store; current allowlist + hooks + sanctioned change path |
| design.md / verdicts.md | candidate fixes C1–C6 and the safety/efficacy reviewers' verdicts (C6 env kill switch rejected) |
| prototypes/ | census scripts and the 64-row TSV (`autodeny-64.tsv`) |
