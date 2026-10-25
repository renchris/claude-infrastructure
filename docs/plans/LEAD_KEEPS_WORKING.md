---
status: in-progress
---

# Lead keeps working while a decision is open — implementation plan

Scope (frozen): lead-idle-fix — Phase 1: a Dynamic Workflow researches and writes one design doc under docs/research/ (chosen design, rejected rivals and why, test plan) covering (a) keep working on ungated in-scope items, (b) class B for judgment calls with a status-quo course, (c) find an existing ruling before asking, (d) standing operator grants loaded every session (first: Codex cross-vendor review), (e) the close stack refuses a Blocked idle while ungated in-scope work remains, loop scopes included, (f) wake a stalled session itself; Phase 2: implement it with tests that fail without each change, land via project /ship, converge, verify deployed ~/.claude copies by content; no settings-file edits, no weakened gate.

Ruling: operator decision `d610f8473106` (2026-10-24). Incident: `~/.cache/agentsync-bring-back/b13/report/why-the-lead-idled.md`.
Design (the SSOT for every file, line anchor, bound and test): `docs/research/lead-keeps-working-2026-10-24.md`; its §8 is the step table this plan executes.

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE**

| Wave | Locus | Tracks (design §8.1 steps) | Why this locus |
|---|---|---|---|
| 1 | **S** (default) | A scope floor (1, 2, 3) · B subject nudge (4) · C decide + grant code (5, 7) | disjoint file sets; each track leads its own Agent Team in its own worktree |
| 2 | **S** | D rule and machine text (6) | fired after A and C land, so no loaded sentence names a verb that is not yet on trunk |
| 3 | **L** | integration: B13 replay suites, red/green receipts, converge check, deployed-copy content check, class-A records, pings | one line of why: it is synthesis of the tracks' receipts, small output, and the goal's proof must surface in the lead's transcript |
| 4 | **S** | E held-out instruction re-gate (9) | operator ruled 2026-10-04 to run it at the next slim edit (`docs/plans/INSTRUCTION_BUDGET.md:127`); it measures the converged slim text |

**Lead context budget.** The lead (session `3d1dc252`) holds ≤ 50% of its 1M window for deciding; it reads track
pings and receipts, never track diffs in full. Succession point: at 60%, or at any idle after Wave 2 is fired with
≥ 35%, recycle with this plan as the bridge (`handoff-fire.sh --recycle`).

**Land order.** A lands 1+2 before 3 (consumers read absent fields as today, so each land is safe alone). B is a
no-op until A's floor writes `scope-floor*` IDL rows, so it lands whenever it is green. C's `.ceiling` field makes
A's hold tiers stricter when present and absent folds to "no ceiling", so C and A land in either order. D lands
after A and C. Every track converges its own land (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`).

**Test contention.** cc-bats admits 2 live bats roots under load (`bin/cc-bats:514`); an rc 75 is a deferral, not a
verdict. Every track runs its own direct suites, asserts the `1..N` plan line, and never trusts the land smoke
(it cuts at 900 s or is shed under load; `maps/test-infra.md` §2.2).

## Tracks

| Track | Worktree / branch | Status | Landed shas |
|---|---|---|---|
| A scope floor | `lkw-scope-floor` | pending | |
| B subject nudge | `lkw-subject-nudge` | pending | |
| C decide + grant code | `lkw-decide-grant` | pending | |
| D rule text | `lkw-rule-text` | pending (fires after A, C) | |
| E re-gate | `lkw-regate` | pending (fires after D) | |

## Definition of done (per track)

Each track's done: every file its design §8.1 row names is changed as §3 specifies; every new check has a bats test
that is RED on `origin/main`'s subject and green on the change (plus one mutant per new guard), with the receipts in
the commit body; landed through the project-local `/ship`; converged; `git ls-tree origin/main -- <paths>` printed.

The lead's done (Wave 3): design §7.8's deployed-copy checks pass by content; §8.4's two class-A records and the one
`cc-backlog needs` step are filed; the B13 lead and the originator are pinged.
