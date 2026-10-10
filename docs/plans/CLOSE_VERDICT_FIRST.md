---
status: in-progress
---

# CLOSE_VERDICT_FIRST — a close leads with the answer to "good to close?"

Scope (frozen): an origin close whose good-to-close verdict is no can no longer open with a line that reads as done (✅ / "complete" / "nothing to do"), by default — the rule in the slim + full global CLAUDE variants and the deployed rules file, the template in hooks/lib/close-shape.sh and commands/wrap.md, enforced in hooks/completion-assert.sh — with regression tests that replay both 2026-10-10 screenshot closes (left: ✅ line 1 + "Good to close: no" → refused/reshaped; right: ✅ + "Good to close: yes" → passes), landed via project /ship, converged, deployed files verified; scripts/limit-recover/lr_recon/** and settings.json untouched.

Origin: operator request 2026-10-10 via FLEET_V2 lead (pane claude-infrastructure-16). Evidence:
`~/.reso/close-shape/two-closes-2026-10-10.png` — two closes, both line 1 `✅ …`; the left one's
verdict (line 2, same paragraph) is `Good to close: no`. At a glance both read YES.

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave.** This session is itself the dispatched session (S) for the whole
  task; inside it:
  - W1 research — Dynamic Workflow, read-only `workflow-lean` slots + skeptic (operator authorized
    workflows explicitly). Locus T-equivalent (workflow): its output is a single REPORT.md the lead
    must synthesise against the implementation immediately.
  - W2 implement — T (in-session teammates) if the design touches hooks AND docs in separate files;
    why: the change is small (<500 LOC total) and the docs must state exactly what the hook enforces,
    so the lead synthesises both before one land.
- **Task size per unit.** Research slots 20–60K output each; implementation teammates 40–80K, ≤5
  files each.
- **Team.** W2: `hooks-impl` (close-shape.sh, completion-assert.sh, tests/completion-assert.bats);
  `docs-impl` (CLAUDE.rules.slim.10-session-close.md, CLAUDE.global.md, commands/wrap.md, and any
  slim-variant line). Dependency: docs-impl blockedBy the frozen design in REPORT.md, not by
  hooks-impl.
- **Worktrees.** Lead on `close-verdict-first`; teammates in their own worktrees, merged by the lead.
- **Lead context budget + succession point.** Reserve ≥50% for deciding; succession point = after
  W2 merge if fill >60% (recycle with this plan as the bridge).

## W1 — Research (Dynamic Workflow)

Questions: (a) line-1 shape options and glance-readability; (b) wrap-ledger git-only ✅ vs a
task-level no; (c) interaction with CC_ACT_WINDOW, D3, D6, D7, opaque-id nudge, /wrap,
operator-readout, peer/assignee exemptions; (d) the 613-close figures in close-shape.sh — re-derive
or re-scope; (e) exact doc edits. Output: `docs/research/close-verdict-first-2026-10-10/REPORT.md`.

## W2 — Implement

(filled from REPORT.md)

## W3 — Gate, land, converge, verify

bats touched (assert `1..N`), shellcheck bare as the land gate runs it, `scripts/ship-land.sh`,
`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, grep deployed
`~/.claude/rules/10-session-close.md` and `~/.claude/CLAUDE.md` for the new rule.
