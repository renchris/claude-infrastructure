# Always-loaded project rules

<!-- HOW TO ADD A LESSON HERE — read this before appending. -->

**This file is injected into EVERY session in this repo, in full.** That is what makes it
valuable and what makes it expensive: on 2026-09-17 it reached **190,960 chars (~48K tokens a
session)** because 70 lessons had been pasted in whole rather than split, and 89.5% of the file
was evidence nobody needed resident. It now sits at ~43K chars for the same 121 rules.

**The convention, and it is the whole budget discipline:**

| tier | what lives there | budget |
|---|---|---|
| this file | ONE hook per lesson — a sentence that **states the rule** so a reader can act on it without opening anything | ≤ ~350 chars per bullet |
| `docs/lessons/<slug>.md` | the full body: the incident, the measurements, the shas, the companions, the method warnings | unbounded |

So a new lesson is TWO writes: the body to `docs/lessons/<slug>.md`, then one hook here linking
`../../docs/lessons/<slug>.md`. A bullet whose link target is `.` has no body and is the shape
this file was cleaned up to remove — `scripts/rules-hook-budget-lint.sh` refuses one at the land
gate. Never character-truncate a hook to fit: rewrite it so it still states its rule.

**Why the hook may not degrade into a label.** `Empty vs no-surface — two states look alike`
names a topic and teaches nothing. `An emptiness gate cannot separate "empty" from "absent";
absence needs its own verdict, because a timeout renders them identical and they demand opposite
actions` is the same lesson made usable. The second is what belongs here.

**The two ceilings on this file are NOT the same kind of thing** (measured, and encoded in
`bin/cc-memory-rotate`): **4 MiB is HARD** — at or over it the loader SKIPS the file entirely and
every rule here silently vanishes; **150k chars is COSMETIC** — a startup warning, nothing is
truncated. Do not read the warning as loss, and do not let that make it free: the cost it is
reporting is context budget, which is the scarce resource here.

Situational lessons live in `agent-operating-lessons-situational.md` beside this file, and new lessons are appended there, not here: "one hook here" above means one hook in that file, unless the lesson must fire in every session (the land refuses a new bullet in this file without `RULES_RESIDENT_ADD_OK=1`). Before diagnosing a failing test, gate, hook, land or tool, grep that file for the symptom. The lessons below fire on any work in this repo.

- demoted 2026-09-06 from MEMORY.md to MEMORY_ARCHIVE_2026-H2-COLD.md; the rule itself is unchanged at `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/landedness-over-commits-is-blind-to-staged-content.md` — commit-landedness is blind to staged/untracked bytes ⇒ before deleting, ask per PATH by CONTENT
- [Never wrap /ship in your own timeout](../../docs/lessons/never-wrap-ship-in-your-own-timeout.md) — ship-land bounds itself, and under lock contention its runtime exceeds any bound you would guess; an outer timeout cannot tell progress from wedged, so it can only convict a healthy land. Run it unbounded and read ITS verdict.
- [Ship owns the tree](../../docs/lessons/never-write-a-tracked-file-while-ship-is-in-flight.md) — between firing /ship and reading its verdict the worktree is the LANDER's: writing a tracked file re-arms its rebase, and REMOVING the tree revokes the still-running process's cwd, turning every git it forks into exit 128 and its audit leg into NO VERDICT. Ask which process was launched from a dir before deleting it.
- [Gate refusal ≠ gate result](../../docs/lessons/a-gate-refusal-is-not-a-gate-result.md) — A gate that REFUSES to run emits no TAP lines and exits 0, so a `not ok` filter reads it as a pass — assert the plan line `1..N` before believing a filtered result, and remember your own background gate holds one of the concurrency slots.
- `narrated-verdict-is-indistinguishable-from-a-computed-one.md` — a conclusion you echo into a command's OWN output stream reads back as that command's result, and you will believe it over the contradicting rows three lines below. The only rule in the corpus about the model itself as a fabricating instrument; its incident came one step from `git rebase --continue` under a live lander.
  Body: `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/narrated-verdict-is-indistinguishable-from-a-computed-one.md`.
- [Empty selector is a universal selector](../../docs/lessons/empty-selector-is-a-universal-selector.md) — `VAR=x cmd` binds VAR to that command only, so a later pipeline stage reads it EMPTY, and an empty pattern selects EVERY line. Assign at shell level, and run the census alone and count its rows before any kill loop.
- [In-process agent caps at 100 turns](../../docs/lessons/in-process-agent-stops-at-100-turns-the-same-agent-in-a-workflow.md) — an in-process Agent spawn stops at its frontmatter maxTurns mid-pass while the harness reports a normal completion carrying partial work; size such briefs to fit, demand incremental writes, and resume via SendMessage rather than re-firing.
- [Subagent cannot answer a prompt](../../docs/lessons/a-subagent-cannot-answer-a-permission-prompt-so-a-prompt-trigger.md) — a subagent has nobody to answer an ask, so a prompt-triggering command in its brief never returns and looks exactly like slow work ⇒ ban them BY NAME in the brief, with the reason, or it respells the idiom.
- [Probe writes into a live session](../../docs/lessons/a-research-probe-that-drives-real-ui-writes-into-the-operator-s.md) — "Read-only" is heard as "do not edit files" and does not stop an agent invoking an action whose whole purpose is to MOVE something — name and forbid side-effecting probes against live targets; a `test_*` entry point is not a read.
- [Draggable pane title is primary](../../docs/lessons/a-draggable-pane-title-outranks-every-other-title-bar-property-o.md) — OPERATOR RULING, do not re-litigate: kitty's drag hangs off REAL title-bar render data, so any chord, script or daemon that disables real bars in exchange for the prettier graphics-protocol overlay is FORBIDDEN.
- [Arming ≠ mootness](../../docs/lessons/arming-and-mootness-cannot-share-one-falsifier.md) — a --falsifier field means "this row is no longer needed" and its consumer CLOSES on exit 0, so a probe detecting the precondition ARRIVING deletes the row at the instant it becomes actionable; say exit 0 aloud as a sentence about the row before storing it.
- [Deployment interpreter ≠ yours](../../docs/lessons/the-deployment-interpreter-is-not-the-one-on-your-path.md) — `#!/usr/bin/env bash` resolves against the SCHEDULER's PATH, so a launchd job gets /bin/bash 3.2 (no `case`+`continue` inside `$( )`) while you test under 5.x ⇒ for anything launchd/cron/CI runs, RUN it under that interpreter in the suite; parse-check alone misses runtime-only breaks.
- [Soft reset onto a moved ref reverts](../../docs/lessons/soft-reset-onto-a-moved-ref-reverts-the-difference.md) — `git reset --soft origin/main` keeps your STALE index and re-points HEAD at the NEW trunk, so the commit means "make trunk look like my old tree": 477 deletions across 11 files of siblings' landed work. Squash by rebase; `git show --stat` every squash and read the FILE LIST.
- [Landed ≠ tested](../../docs/lessons/a-landed-verdict-is-not-a-tested-verdict.md) — ship-land SHEDS its smoke past a load ceiling and still pushes (`behaviorally UNGATED`), so a LANDED verdict says the bytes arrived, never that they are right; read the smoke line and run your diff's suites yourself — and assert the `1..N` plan line, because a cc-bats deferral has zero `not ok` too.
- [Own records ≠ the world](../../docs/lessons/an-absence-in-your-own-records-bounds-the-records.md) — three negative searches feel like confirmation when all three stores are ones WE write (our config, our mailbox, our archive); that supports "we have no record", never "there is no way" — name an un-searched store we do not write, usually the public web, before any such verdict.
- [Turn adjacency ≠ elapsed time](../../docs/lessons/turn-adjacency-is-not-wall-clock-adjacency.md) — a model has no clock, so "just now" and "within a minute" are inferences from TURN POSITION and are free to be hours wrong on an idle session; measure with date/stat/etime before any duration sets a verdict, and read the subject's own printed verdict before inventing a mechanism to contradict it.
- [Census misses the owner](../../docs/lessons/a-cwd-census-cannot-see-a-worktrees-owner.md) — a wave lead owns its worktrees from the repo ROOT and is never cwd'd in them, so a cwd census reads every one as ownerless and cannot tell that from abandoned; demand a positive owner signal (a commit minutes old, the branch namespace) before touching another session's branch.
- [Unreachable goal never clears](../../docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md) — a /goal conjunct needing an operator-only act (a credential, a consent, loading a daemon) blocks forever, and blocks AFTER all reachable work is done; the signature is a negative permission clause inside the success condition. End the condition at the agent's reach.
- [Gate invocation is contract](../../docs/lessons/a-gates-invocation-is-part-of-its-contract.md) — the land gate runs `shellcheck` BARE (ship-land.sh:3258); `-S warning` hides info findings and `-x` SUPPRESSES SC1091, so more-thorough is not a superset — grep the gate for its literal command before any local check, and annotate every code a line can emit.
