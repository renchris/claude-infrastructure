---
status: complete
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

## W1 — DONE (`9abdc1843`, `b67487b7d`)
- Design A′ (85% after skeptics; >90% with the fixes below): verdict owns line 1 with its own glyph
  (`✅ Good to close: yes — …` / `❌ Good to close: no — …`), ledger rung relayed on line 2; the hook
  refuses only the contradiction (no verdict under a ✅/👤/done-reading line 1, D6 token `verdict-first`).
- Learnings: the left close was the rule working as written (verdict on line 2 in 81% of closes); 264 of
  1,315 ✅-led closes answer no (30 d, slot-corpus). In production the hook would also have missed it:
  the session's `shape` budget was spent and completion-assert timed out (18% of Stop runs at 5 s) — so
  the rules text is the main lever, the hook the backstop, and verdict-first gets its own latch class.
- 2026-08-23 figures in close-shape.sh are stale both ways (73%→83%, "90.7% last line"→12.9%) and the
  instrument that made them is not committed; block reasons carry no corpus numbers from now on.

Scope (grown): +`hooks/operator-readout.sh` withholds `✅ SAFE TO CLOSE` when the close's verdict is no
(1/3 of certificate renders follow a no, skeptic-operator-intent P3); +`commands/are-we-done.md`,
`hooks/lib/why-tier.sh`, `docs/plans/STOPHOOK_MESSAGE_TIERING.md` carry the same template and would
keep teaching the old shape.

## W2 — Implement (T: in-session teammates) — DONE, merged into `close-verdict-first`

| teammate | files | commits |
|---|---|---|
| cvf-hooks | close-shape.sh, completion-assert.sh, completion-assert.bats, fixtures | `5ad54b1e6`, `b90f8953b` |
| cvf-docs | rules slim (30,334 → 30,329 loader units), CLAUDE.global.md, wrap.md, are-we-done.md, why-tier.sh, STOPHOOK plan | `eec712aee` |
| cvf-readout | operator-readout.sh + its bats (decoupled via a `CLOSE_SHAPE_LIB` seam, fail-open) | `e02c87b8e`, lead `67835bcd1` |

- Final hook code = the REPORT.md §2 prototype (41 real-hook replays). Deviations from the lead's first
  rulings, report wins: old-shape 👤 no is refused only when line 1 is the 👤 readout's "my side is
  done/landed/complete" (glyph-only would refuse 266 honest-looking 👤 closes in 30 d vs 129); the
  hedge set keeps `with one thing`.
- The rules text says "a no under a line 1 opening ✅, 👤 or a done reading fails" — stricter than the
  hook on purpose (prompt sets the form, hook is the floor).
- Learning: the machine ran at load 130-300 all afternoon; cc-bats deferred (rc 75) every teammate
  run, so suites ran from the lead in a retry loop.

Lead rulings on top of design.md: "no" needs punctuation after it; D3 verdict branch behind
`CC_VERDICT_FIRST`, no `with`/`after`, no both-polarity branch; reads-done rejects `Complete? No`;
polarity reads yes/negation before the anchor; own latch class `verdict` (COMPLETION_VERDICT_MAX=2);
old-shape 👤 no is refused too; rules :9 becomes "A ✅ rung is an assertion"; `/wrap` line 2 keeps
glyph + state clause, replaces the tail.

## W3 — Gate, land, converge, verify — DONE (`cae15ca1c`, 2026-10-10)
- completion-assert.bats 1..185, 0 failures (LEFT screenshot fires `verdict-first` class `verdict`,
  RIGHT passes); why-tier 1..16 and research-program-exemption-rules 1..4 green; operator-readout
  1..121 with 1 failure — test 113 (busy notice), a pre-existing load flake, not this diff: interleaved
  A/B shows pristine trunk failing it too, cause wrap-ledger's busy probe erroring under load
  (`BUSY_SRC=error`); the verdict code never runs in that test (no transcript).
- Landed `cae15ca1c` (24 paths content-verified); converged on the degraded tier; deployed
  `~/.claude/rules/10-session-close.md`, `CLAUDE.full.md`, hooks carry the rule.
- Rescue: the docs teammate was killed mid-call (lead read idle as done); its 3 uncommitted files were
  recovered as `9bab03777`. Teardown misclassification and the /goal read-back bug were fired as their
  own sessions (custody with pane 16).
- Not done here, dropped from this scope (REPORT.md §7 keeps them): wrap-ledger's git-only ✅ wording,
  `SCOPE=met` without evidence, committing the corpus instrument.

bats touched (assert `1..N`), shellcheck bare as the land gate runs it, `scripts/ship-land.sh`,
`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, grep deployed
`~/.claude/rules/10-session-close.md` and `~/.claude/CLAUDE.full.md` for the new rule. (Correction to
the brief: `~/.claude/CLAUDE.md` is the slim global, which carries no close-placement text — the slim
variant's close protocol IS the rules file — so it is checked only to confirm it was not changed.)
