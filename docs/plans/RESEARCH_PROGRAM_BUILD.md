---
status: open
---

# Research program build — tooling for the no-take-backs upfront research method

Scope (frozen): build wave 1 of the method in `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md` §8
(items 2–8) so the next greenfield program can run it, with every §10 open item closed by a failing planted-input
test; run the calibration study (§8 item 14) in parallel; then wave 2 (items 9–13, 15) alongside the pilot.

Ruled 2026-10-01 by the operator ("Proceed as you recommend with all"): REPORT.md §9 decisions 1–9 adopted, decision
packet `83adb541ea19` actioned. Method version 1.1 is frozen; it changes only from measured results (decision 8).

## Phase 0 — Agent team orchestration

**Execution locus per wave.**

| Wave | Locus | Content | Depends on |
|---|---|---|---|
| A1 | S (dispatched session) | Items 2 + 3: zero-allowed research prompts; the standing-rule exemption in both instruction variants, `hooks/completion-assert.sh` and the live copies, keyed on the program registry (§10 open item 10) | — |
| A2 | S | Items 4 + 7: operator-only signing library; the seven-script hand-run kit and the program registry with states `registered → certifying → certified` (§10 items 1, 4, 7, 9, 13, 17) | — |
| A3 | S | Item 14: calibration study over at least 10 held-out historical plans (read-only replay). Settles decision 4 and the labeled assumptions (fix-born rate, holes at freeze, Lite/Full stage budgets, point-forecast exceedance) | — |
| B1 | S | Items 5 + 6: re-ask router, research block, polarity-independent Stop check; the settings migration as a `c10` migration the operator runs (§10 items 1–3, 8, 11–13) | A2 (registry) |
| B2 | S | Item 8: `research-program` skill, `/research-program` command, intake script, briefs, rubric | A2 |
| C | S | Wave 2: items 9–13, 15, in parallel with the pilot | B1, B2 |

A1, A2 and A3 touch disjoint files and fire concurrently. B1 and B2 fire when A2 lands. Each dispatched session leads
its own Agent Team where it has 2+ code-writing tasks.

**Lead budget and succession.** The lead (the session that wrote this plan) only fires waves, collects pings, and
lands nothing itself; it recycles once A1–A3 are fired and their custody is recorded. Each wave session owns its own
worktree, gates and `/ship`.

**Acceptance rule for every wave.** Each REPORT.md §10 open item a wave owns gets a planted-input test that fails
before the change and passes after it, run in the land gate. A wave is done when its tests are green on trunk and its
items are live (converged), not when the code is written.

## Waves

### A1 — prompts and standing-rule exemption
- REPORT.md §8 item 2 (cites the exact lines) and item 3; §3.1 ruling 2.
- Key the exemption on the program registry resolution (§10 item 10), not on a DoD marker no step writes.
- Status: **landed and live 2026-10-01** (`7310c4ac8` prompts, `7cca316c0` registry lib, `a08892a16` rules,
  `b1fd89b6a` hook; converged, both live copies byte-equal to trunk). §10 item 10 closed by option 1: everything
  keys on `scripts/lib/research-program.sh` (`rp_resolve_cwd`, `rp_is_active`; registry contract in its header,
  which A2's `gate.sh` writes). Also fixed the same quota in two uncited siblings (`deep-research-sonnet.md`,
  `frontier-derivation.md`). Learnings: the land gate requires `$HOME` fixtured in every new suite and refuses
  `! ( … )` assertions errexit cannot reach; the slim variant's `derived-from` stamp was already stale and was left
  alone.

### A2 — signing library, hand-run kit, registry
- REPORT.md §8 items 4 and 7; layout per `evidence/design/SYNTHESIS.md:932-1097`.
- Registry state `certifying` set at freeze so the relay test runs with the block on (§10 item 1).
- Status: not started.

### A3 — calibration study
- REPORT.md §8 item 14; §6.6 lists what it measures. Output: `docs/research/research-calibration.jsonl` and a report;
  changes to the report only as priced edits to named sections (profile table, caps, seed counts).
- Status: not started.

### B1, B2, C
- Expanded with file:line detail when A2 lands.
