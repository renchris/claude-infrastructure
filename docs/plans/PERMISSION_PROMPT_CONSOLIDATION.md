---
status: in-progress
---

# PERMISSION_PROMPT_CONSOLIDATION — stop autonomous sessions stalling on prompts that approve safe, repeatable actions

**Scope (frozen, 2026-09-24):** operator directive, verbatim: *"Can we also /handoff Opus 5.5 high consolidating
permission requests and pretool hook requests to scalable patterns to our allowlist?"* So: census every
permission prompt and PreToolUse-hook `ask` that interrupted a session, cluster them into scalable patterns, and
remove the safe ones at the right layer — hook false positives FIXED IN THE HOOK (landed, bats red on parent);
settings allow/ask-rule changes STAGED as one operator-applied step (never written by an agent). Dangerous asks stay.

## Phase 0 — Agent Team Orchestration

**Execution locus:** S — one dispatched session (this plan's owner), Opus 5.5 @ high. It may fan out read-only
research subagents for the census; hook edits stay on the session itself (one owner per hook file).
**Lead context budget + succession point:** hold ≥50% for judgment; `--recycle` after the census is persisted here.

## Evidence that triggered it (2026-09-23/24, RESO_LATENCY_100P)

Three dispatched reso sessions sat ~45 min to 8 h at prompts nobody was watching:
1. `hooks/validate-bash.sh` family: `rm -r on non-build-artifact target: 'src/app/api/w0-probe'` and `'$O/tmp'` —
   scratch paths the session itself had just created (a probe route; a tmp dir under a variable).
2. `Ask rule Bash(git stash drop:*) overrides auto mode` — present in ALL FIVE config dirs' settings.json
   (`permissions.ask`, beside `git stash clear:*`) — on a session dropping its OWN temporary stash
   (`git stash push -m X … && git stash apply <X> && git stash drop <X>`, a red-on-parent capture idiom).
3. `Contains command_substitution` — not statically analysable, so auto mode deferred to the prompt.

## Method

1. Census, read-only: `bin/cc-permission-harvest` and `bin/cc-permission-audit` (read their own caveats — the
   audit's `approved 0 · unknown N` is an unpopulated join key, not a measurement) plus the transcripts' hook-ask
   records. Output: a ranked table — pattern · count · sessions stalled · stall minutes · layer (hook ask /
   settings ask rule / auto-mode classifier / no allow rule) · safe-to-remove? · the scalable rule or hook change.
2. Hook layer (yours to land): fix false positives scoped to the EFFECT, never by widening a denylist spelling
   (memory: denylist-enumerates-spellings-not-the-class). Every change gets a bats case red on the parent and a
   case proving the dangerous sibling (`rm -rf src`, `rm -rf /etc`, `$HOME`) still asks.
3. Settings layer (the operator's to apply): ONE staged step — a `migrations/` c10 entry or a `cc-do` item — that
   edits the allow/ask lists in every config dir identically (accounts are interchangeable; a fork is a defect).
   Name each rule's census count and why it is safe. Never write settings*.json yourself.
4. The classifier layer (command substitution etc.): prefer reshaping the IDIOM the agents use (a helper script
   agents call instead of the inline chain) over any allow rule, and record which prompts are structural.

## Status

| Step | State | Evidence |
|---|---|---|
| Plan + fire | fired 2026-09-24 | — |
