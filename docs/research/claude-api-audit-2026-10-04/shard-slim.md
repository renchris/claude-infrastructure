# Prompt audit, shard "slim": the always-loaded global instructions

## Assumptions (Step 0)

- **Scope:** `CLAUDE.global.slim.md` (26,939 chars after the loader strips HTML comments) and `CLAUDE.rules.slim.10-session-close.md` (30,250 chars), deployed byte-identical to `~/.claude/CLAUDE.md` and `~/.claude/rules/10-session-close.md` (checked with `cmp`; origin/main has no newer edits to either file). Together they are 57,189 chars of the 60k user-tier budget and load into every main session, teammate, fired session and default-agent subagent or Workflow slot on the machine. `CLAUDE.global.md` was read only to decide whether a hunk needs a mirror. The mission board (`00-mission-board.md`) and the project-tier files are outside this shard.
- **Target model:** Opus 5.5 at effort high, which is the default for every session. The frontier note in the file targets Fable 5.1.
- **Repository constraint:** the slim text is eval-gated. F1 round 4 extended passed at pin `d446c60e…` (commit `d570ed0bf`, `docs/research/token-efficiency-2026-09-23/eval/GATE.md` § R4.5). About 4k chars have landed since then without a gate, so `cc-instructions-variant status` reports STALE (INSTRUCTION_BUDGET.md, Known issues). For that reason this report keeps two kinds of hunk apart. Stale-fact and path fixes are proposed as string replacements. Anything that changes behavior is routed to a gated round, not to a direct edit.
- **Text pinned by tests:** `tests/research-program-exemption-rules.bats` pins the exemption definition and its six pointers. `tests/cc-memory-search.bats:246` pins `Run .cc-memory-search <terms>. first`. `tests/cc-memory-supersession-check.bats:123` pins the supersession rule. No hunk below touches pinned text, except slim-17, which says so.

## Summary

1. **Cost lever, largest measured.** Workflow slots still load the full house instructions in 52% of cases: 2,895 of 5,598 slot transcripts in the last 7 days, across 78 workflows. That is about 57k chars of user tier per slot, plus the project tier. The repository's own offline re-gate PASSED `workflow-lean` at 84% cheaper per slot with equal correctness, but the only place that says so is the research-subagents skill. The always-loaded line that sends fan-outs to Workflows does not name it (slim-09).
2. **Runnable commands that only work in this one repo.** Seven commands are written as repo-relative paths (`scripts/handoff-fire.sh`, `hooks/operator-readout.sh`, `scripts/desk-strand-replay.py`, `bin/cc-permission-audit`) or as bare names that are not on PATH (`handoff-fire.sh`). These files load in every repo. Round 3 of the gate measured the cost of exactly this shape: `scripts/wrap-ledger.sh` caused about 26 of slim's 43 non-zero exits, and the fix was to use the `~/.claude/` form, which the files already use for wrap-ledger and session-continue (slim-01…08).
3. **Contradictions with the code.** Three were found. `cc-do` is handed over as a command that "confirms once", but under `!` it runs nothing (its own header says so), which breaks the file's zero-keystroke rule (slim-16). `CC_LADDER=off` is presented as a kill switch that no code reads (slim-15). `§ W3.6` points at a heading that has never existed (slim-11).

Counts by group: Group 1: 1 (1d migration-relative phrasing). Group 2: 13 (volatile paths ×8, stale facts ×2, dangling anchor ×1, pointer inconsistency ×2) plus 1 conflict flag (cc-do). Group 4 / cost and eval: 4 (workflow-lean, the CC_LADDER chokepoint, conditional loading of the exemption, a gated slim round 5). Group 3 does not apply: these files contain no tool definitions.

## Findings, highest confidence first

| id | Location | Pattern | Why | Conf. | Action |
|---|---|---|---|---|---|
| slim-02 | slim:86 | G2 volatile path | The dispatch recipe is copy-pasted as written, but `scripts/handoff-fire.sh` exists only in claude-infrastructure. It is not on PATH; the live file is `~/.claude/scripts/handoff-fire.sh`. Before the slim deploy, reso worktree sessions ran `ls scripts/handoff-fire.sh` and got "No such file" (13 transcripts, 2026-08-19 to 09-04) | high | rewrite |
| slim-06 | close:123 | G2 volatile path | `hooks/operator-readout.sh --render` is not on PATH and is repo-relative. This is the same mechanism round 3 measured for `scripts/wrap-ledger.sh` | high | rewrite |
| slim-11 | slim:132 | G2 dangling anchor | `NONLIMIT_RESUME_LADDER.md` has no `W3.6` heading, at HEAD or in any revision. The open question is § W4 row R3, now live as class-C packet `2c7259995a6b` | high | rewrite |
| slim-01, 03, 05, 07, 08 | slim:78, 132; close:112, 184 ×2 | G2 volatile path | Same mechanism as slim-02. A bare `handoff-fire.sh` is not on PATH in any repo | medium | rewrite |
| slim-04 | slim:194 | G2 volatile path | `bin/cc-permission-audit` fails outside the repo. The bare name is on PATH | medium | rewrite |
| slim-09 | slim:110 | cost lever (input tokens 2.2 / re-baseline adds text) | Census: 2,895 of 5,598 workflow slots in 7 days loaded the close protocol. F2 re-gate PASS: −84% per slot, verifier 28/28, judge 40/40. The always-loaded line that picks Workflows is silent on `agentType` | medium | add |
| slim-10 | slim:125 | 1d model-version workaround / G2 fact true of a moment | All 41 running Claude processes are `.claude-284`. No 2.1.260 session is left. `model-config.yaml:169` keeps the rule where it can expire | medium | remove |
| slim-12, 13 | close:4, 225 | G2 conflict between instruction files | Header line 3, newer (`110c9d393`, 2026-10-03), names the deployed `~/.claude/CLAUDE.full.md`. The close file still sends readers to the shared checkout, which the project CLAUDE.md says "frequently sits on another session's feature branch" | medium | rewrite |
| slim-14 | close:17-18 | 1d migration-relative phrasing | "is no longer prose discipline" compares the rule with a version the model never saw | medium | rewrite |
| slim-15 | slim:132 | 1d unenforced instruction | `git grep CC_LADDER` finds no code that reads it. The plan's own text says the kill switch "must be mechanical, not prose" (`NONLIMIT_RESUME_LADDER.md:835-840`). It was first reported 2026-09-22 (`opus55-synth-reprobe…/T3-frontier-budget-*.md`) and is still not implemented | medium | needs new code |
| slim-16 | close:211 vs close:207, slim:191 | G2 conflict (code contradicts text) | Bare `cc-do` asks for one Enter. With stdin closed (`!`), it prints the board, says NOTHING RAN and exits 3 (`bin/cc-do:51-58`). The rendered row is bare `▶ cc-do`. The fix touches the renderer and the consent semantics, so it is the operator's call | medium | flag / operator decision |
| slim-17 | close:74-80 + 6 pointers | cost lever (conditional content always loaded) | The exemption plus its pointers are 2,935 chars in every context. Only one program is registered (cwd root `tm2-plan`): 9 of 528 main sessions in 3 days, and `is-active` ran in 3. The text is a dated operator ruling and test-pinned, so the change is the operator's call | medium | operator decision |
| slim-18 | whole user tier | cost / eval hillclimb | A gated "round 5" re-certifies the stale pin and tests cuts that census data supports: the ladder mechanics (0 fires and 0 frontier-routing loads in 528 sessions), the shared task list (task tools absent while 0023 has been staged for 17 days) and the Opus 5-era brevity lines (re-test candidates per the migration guide) | medium | needs measurement |

## Checked and left alone (keep list)

- The Plans paragraph (slim:52) uses caps, bold and arrows in a file otherwise written in calm prose. It is **eval-load-bearing**: round 3 measured that the calm pointer wording made 9 of 10 slim runs load plan-conventions without need, and `7140cd89b` restored this wording. Keep.
- The `<tone_preference>` recap is a deliberate end-of-prompt recap (keep-list 10). Its "Hand over one command, not a list" line is what fixed T16 in round 4. The HTML comment above it is stripped by the loader and costs nothing.
- Communication Discipline lines (mid-task narration and others): mid-task narration matches the migration guide's documented lever 3 for Opus 5.5 ("a one-line statement of intent before the first tool call and a short recap at the end"). The verbosity lines are Opus 5 mitigations, which the guide says to keep as the starting point and re-test. They are in slim-18 and not edited here.
- The refusal line (slim:27) and Manual-Command Delivery (slim:188) look as if they overlap, but the two were gated together in R4 and pass. This is working redundancy.
- Pressure language is light: one bold close-contract line and the measured plans paragraph. Safety prohibitions (git clean -x, force-push, --no-verify, `msg` stores) carry their reasons. Keep.
- Every repo path, flag, env default and section anchor was verified, except those in slim-01…08 and slim-11/15. That covers 59 paths; the CLAUDE_CONTINUE_MAX 8, CC_MECH_MAX 2, CC_SHIP_FLOOR_MAX 2 and CC_ACT_WINDOW 3 defaults; `cc-backlog` classes, `--falsifier` and `--blocked`; `cc-decide --open`; `handoff-fire` flags; handoff.md § Autonomous fire items 1 and 6; agent-teams § Runtime assumption and § Pre-Spawn Checklist; and effort_defaults.opus55_*. Migrations 0023 and 0029 read `staged-pending` in `scripts/registration-state.sh`, so the conditional wording about them is accurate.
- Caching: there is no cross-session ordering finding. The system prompt's environment block (cwd, date) differs between sessions before the memory block starts, so moving the volatile board after the close rules would not create a shared cache prefix.

## Mirrors

`CLAUDE.global.md` has the same repo-relative paths at lines 202, 236, 827, 999 and 1129, the same 2.1.260 sentence at line 347 and the same `§ W3.6` anchor at line 347. The full variant is no longer loaded (it is deployed as `CLAUDE.full.md`), so mirroring keeps the two consistent but is not needed for cost. `hooks/lib/why-tier.sh:156` repeats the cc-do sentence from slim-16.

## Side observations (outside this shard)

- `commands/wrap.md:20` runs `scripts/wrap-ledger.sh --full` repo-relative, the same mechanism as slim-02.
- The PostToolUse "RELAY VERBATIM" hook fires on any Bash command whose text mentions `operator-readout.sh --render`, including a Python script that only verifies strings. That is a false positive.
