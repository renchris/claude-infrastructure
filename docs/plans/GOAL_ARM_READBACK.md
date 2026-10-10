---
status: complete
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

## Phase 2 — Fix (lead-inline) — DONE (landed `41cc634df`, live 2026-10-10)

Trunk shas: `57765631d` (tall-box read, both copies; residue receipt holds the payload; truthful mangled messages + desk page on recycle; verdict list), `7001ad446` (research), `9e56493ec` (❯ under the last border ⇒ dialog, both paths), `f14b42653` (tail-only acceptance for a capped box; dialog-above and indented-box vetoes; probe fixtures), `41cc634df` (suite closes the capacity-admit gate).
- Shipped rule, both copies (`composer_content`, `LR_SCREEN_SH`): 24-row read as before; on bottom-border-without-top, a bigger window (`FIRE_COMPOSER_READLINES_MAX` / `LR_SCREEN_LINES_MAX`, default 200; ≤ 24 disables) accepted only when composer-shaped; vetoes (top rule at column 0, no ❯ below the box, no option row above it) on both paths.
- Key learning: the first cut failed open (trust dialog under an echoed prompt). The hostile-transcript test, the skeptic and the modal slot each caught it; the same hole, and a dialog drawn above a live composer reading EMPTY, already existed before this work.
- Key learning: the composer IS height-capped (~40% of the pane), measured on a throwaway pane; a capped box on a tall pane reaches the bigger read with a continuation first row, hence tail-only acceptance (never EMPTY).
- Gates: `tests/composer-tall-readback.bats` 1..20 green, 14 of 20 red on pre-fix `16b6b441f`; touched existing suites 1..178 green; bare shellcheck clean; corpus 0 of 1,001 verdicts changed.
- Blocker resolved: a teammate spawn was refused by the runtime (it2 unreachable), so the lead wrote both copies (locus L).

## Out of scope (recorded, not filed)

- The whole-screen copies (`cc-tui.sh`, `lr-composer-snapshot.sh`, `bin/it2-kitty`) misread the win527 teammate panel as a non-empty draft. That holds rather than types, so it is not a safety defect; porting the shape checks there would change their verdict words (`slot-siblings.md` §4).
- `scripts/limit-recover/lr_recon/observe.py` has its own copy and is off limits for this task (FLEET_V2 reconciler live).
