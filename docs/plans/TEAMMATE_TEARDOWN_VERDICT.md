---
status: in-progress
---

# Teammate teardown verdict — a lead-ordered teardown is a retirement, not a crash

Scope (frozen): hooks/lead-crash-watchdog.sh paints a lead-ordered teammate teardown (shutdown_request, TaskStop, then SIGTERM exit 143) as RETIRED by its lead with no re-spawn advice, while an unexplained teammate death is still painted NOT A CLEAN EXIT; regression replay + control in tests/watchdog-retired-teammate.bats (fails pre-fix); research synthesis at docs/research/teammate-teardown-verdict-2026-10-10/REPORT.md; landed via project /ship and converged live. Untouched: scripts/limit-recover/lr_recon/**, settings.json, hooks/completion-assert.sh, hooks/lib/close-shape.sh, hooks/operator-readout.sh.

Scope (grown): +correct the agent-teams skill's stale shutdown claims (idle 0/4, "idle never answers", trusting idle_notification) and tell the lead to check the member worktree before escalating — the stale text is how cvf-docs was killed mid-task with 3 uncommitted files.

Origin: operator request 2026-10-10 on pane 200 (teammate cvf-docs, session 5b813b72), fired by close-verdict-first-195; back-channel claude-infrastructure-16.

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave.** Research wave: one Dynamic Workflow (5 read-only `workflow-lean` slots + 1 skeptic), run in this dispatched session. Implementation wave: **L · lead-inline**. Why: the change is one function's control flow (`teammate_facts`) plus its renderer case and the test file that pins it. The test fixtures must be written against the exact record shapes the parser accepts, so splitting them across teammates would mean two agents sharing one contract with no file boundary between them.
- **Task size.** One unit, about 260 changed lines across 2 files. That is inside the 40–150K band for one session; no split.
- **Team.** None for implementation (L). Research slots: arm-mechanics, evidence-census, fleet-frequency, contract-and-skill, design-and-control, skeptic.
- **Dependencies.** research → design (conviction gate) → implement + test → land → converge.
- **Worktree.** `~/Development/.worktrees/teammate-teardown-verdict`, branch `teammate-teardown-verdict`.
- **Lead context budget + succession point.** The lead holds at least 50% of its window for deciding. The succession point is after the converge: the session then self-closes, and no later wave exists.

## Phase 1 — Research — DONE (2026-10-10)
- Root cause: the RETIRED arm reads only the member's own transcript for a delivered `<teammate-message>` shutdown_request. A busy member receives it only at its next turn boundary, TaskStop writes nothing on the member's side, and SIGTERM ends it before a boundary. So the arm missed it.
- Fleet measurement: 28 lead-ordered teammate teardowns were painted CRASH (20 of them were TaskStop-only), including 6 after the arm landed. Each sent one false SESSION DEATH page to the desk.
- Design D1 was chosen: read the lead's transcript for what the harness itself wrote (the SendMessage result `toolUseResult`, and the TaskStop result with `task_type: in_process_teammate`, joined by `tool_use_id`). D2 (team inbox/config) was rejected because no evidence survives there. D3 (a helper that writes a marker) was rejected: it depends on the lead model obeying it, it is inert for teammates under the current arms, and it has the largest change surface.
- Full synthesis: `docs/research/teammate-teardown-verdict-2026-10-10/REPORT.md`.

## Phase 2 — Implement D1 + tests (L) — DONE (`6ae154ab6`, 2026-10-10)
- Key learning (skeptic): judge the TaskStop by its tool_use time, not its result. The result lands 0.0–0.5 s after the member's exit flush, and keying on it rescued only 4 of 28.
- Further skeptic amendments: a shutdown_request alone counts only when the member was between turns; the window is 600 s; the identity line is flushed first; a mid-task stop gets a ⚠ headline and is not auto-closed.
- Gates: `watchdog-retired-teammate.bats` 1..17 green, sibling watchdog suites green, bare shellcheck clean. Fleet replay: 23/28 rescued, 52/52 kept, 0/77 flipped.

Original plan for this phase, kept for the record:
- `hooks/lead-crash-watchdog.sh` `teammate_facts`: adds a lead-side source, gated as follows:
  - the lead transcript is resolved from the team's config.json `leadSessionId`, or else from the team name `session-<sid8>`;
  - records written by a member are excluded;
  - the order must come after the member's first record, and within the 30 minutes before its last write;
  - an `approve:false` reply from the member vetoes it.
  It also emits SOURCE and MIDTASK fields, and `retired_teammate` reads field 4 explicitly.
- Renderer: the RETIRED case distinguishes the member-side source from the lead-side source. A member stopped mid-task gets a worktree warning and is not auto-closed. The re-spawn advice is removed from the retired banner and the retired death page.
- Tests: tests 13–17 in `tests/watchdog-retired-teammate.bats` (replay, control, idle-lead, guards, banner).

## Known issues / follow-ups surfaced by research (not in frozen scope)
- Members launch without `cc-close-attrib`, so a teammate death never gets an exit code and cannot be named `external-sigterm`. `cc-pane-runner` prints the exit code but does not record it.
- In arm 1.5, the sid-keyed marker check ignores `mode`, so a teammate-written `teammate-idle` marker absolves any death of its sid.
- `handle_crash`'s team scan (~:1973) omits `~/.claude-quaternary/teams`.
- `skills/agent-teams/SKILL.md` § Shutdown Protocol has stale claims: "idle members never answer" was overturned by the W5 probe, and the skill trusts an `idle_notification` that can be stale. That staleness is how cvf-docs was killed with 3 uncommitted files (kept by its lead in 9bab03777).
