---
status: in-progress
---

# GOAL_ARM_READBACK — a tall composer reads as "<unreadable>" and the /goal is never submitted

Scope (frozen): root-cause and fix why handoff-fire.sh's /goal arming read a healthy composer as "<unreadable>" and left the /goal typed but unsubmitted. Done = a long wrapped /goal in a narrow or mid-turn pane reads back as matching and gets its CR, while a real modal still reads as unreadable or mismatched and gets none; a regression test fails before the fix and passes after; research synthesis in docs/research/goal-arm-readback-2026-10-10/REPORT.md; landed via the project /ship and converged live. Do not touch scripts/limit-recover/lr_recon/**, hooks/completion-assert.sh, hooks/lib/close-shape.sh, hooks/operator-readout.sh, hooks/lead-crash-watchdog.sh or settings.json.

## Phase 0 — Agent Team Orchestration

- **Execution locus:** Phase 1 = Dynamic Workflow (read-only, 5 `workflow-lean` slots). Phase 2 = **L** (lead-inline). Why: one ~40-line parse rule mirrored in two files that must stay rule-identical. A teammate (`Agent({name:"lr-port"})`) was tried for the lr-fire-resume copy and refused by the runtime ("teammateMode is set to iterm2 but the it2 CLI is not reachable"), so the lead wrote both copies.
- **Task size:** one unit, ~3 files of code and tests, inside the 40–150K band.
- **Lead context budget:** hold ≥50% for deciding; succession point is after the land + converge, so the lead closes there (self-close --terminal).

## Phase 1 — Research (Dynamic Workflow, read-only, 5 slots incl. skeptic)

Root cause reproduced live on pane 203 (32 cols × 62 rows, mid-turn) before the wave: `composer_content` reads the last `FIRE_COMPOSER_READLINES:-24` rows; a 472-char /goal wraps to 22 composer rows, and with the 3-row footer the composer's TOP border sits 26 rows from the bottom, so the parse sees one border and returns UNKNOWN. The same captured screen parses to the exact payload at 30 rows. Evidence: `docs/research/goal-arm-readback-2026-10-10/evidence/`.

Synthesis: `docs/research/goal-arm-readback-2026-10-10/REPORT.md` (Q1–Q4). Conviction in D1 above 90%: corpus replay 0/997 verdicts changed, every repo modal fixture stays fail-closed alone and under a hostile transcript, and the incident screen parses to the exact payload.

## Phase 2 — Fix (lead-inline)

- `scripts/handoff-fire.sh` `composer_content`: bigger window only on bottom-border-without-top, accepted only when composer-shaped (5 checks). `FIRE_COMPOSER_READLINES_MAX` (default 200; set ≤ 24 to disable).
- `scripts/limit-recover/lr-fire-resume.sh` `LR_SCREEN_SH`: the same rule (`LR_SCREEN_LINES_MAX`).
- Residue receipt on an unreadable scrub records the payload, not `<unreadable>`; scrub-off records the whole read.
- `arm_goal` mangled branch: truthful about the scrub (`FIRE_PASTE_SCRUB`), tells the fired session to drive without the backstop, pages the desk on a recycle.
- `commands/handoff.md` verdict list completed.
- Tests: `tests/composer-tall-readback.bats` (window-honouring stubs; red against HEAD for the tall cases).
- Commit `373bb4230`.

## Out of scope (recorded, not filed)

- The whole-screen copies (`cc-tui.sh`, `lr-composer-snapshot.sh`, `bin/it2-kitty`) misread the win527 teammate panel as a non-empty draft. That holds rather than types, so it is not a safety defect; porting the shape checks there would change their verdict words (`slot-siblings.md` §4).
- `scripts/limit-recover/lr_recon/observe.py` has its own copy and is off limits for this task (FLEET_V2 reconciler live).
