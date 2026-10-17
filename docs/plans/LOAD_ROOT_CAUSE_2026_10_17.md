---
status: in-progress
---

# Load root cause 2026-10-17: implementation program

Scope (frozen): implement the agent-drivable fixes of `docs/research/load-root-cause-2026-10-17/DESIGN.md`
§5 (waves 1-5) so the same session work costs the machine less, with no throttling, demotion, capping, kill
policy or session reduction; make worktree lifecycle event-driven and reversible (PARK before any removal,
a tombstone before every removal, restore on resume); hand every operator-only step over as one script.

Design, evidence and per-row verify recipes: `docs/research/load-root-cause-2026-10-17/DESIGN.md` (§2 ranked
fixes X1-X27, §3 worktree lifecycle, §4 instrument, §5 WP table with file ownership). Axis evidence: the
`A-…J-*.md` files beside it. This plan does not restate them; a wave session reads its WPs' rows there.

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave:** every wave is **S** (one dispatched `handoff-fire.sh` session per wave, each
  leading its own Agent Team, one teammate per WP, disjoint files per DESIGN §5). No T or L waves.
- **Concurrency:** W1-CI, W1-ACS, W2 and W4 are file-disjoint and fire together. W3 waits for W1-CI and W2
  (WP-15/16/17 depend on WP-7/8/9/10/13). W6 is conditional on the post-wave re-measurement.
- **Load etiquette for every session and teammate:** run only the bats/pytest files your WP names, never a
  full suite outside the land gate; no `ps -A` in new code; never kill or signal anything; never point
  worktree-gc, `git worktree remove/prune` or `git branch -d/-D` at a real worktree (WORKTREE_MANAGEMENT_V2
  HAZARD RULE) — use a throwaway repo.
- **Owned elsewhere:** live Wave 4c of `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md` owns `scripts/wrap-ledger.sh`,
  `hooks/operator-readout.sh` and the session-continue / completion-assert / boundary-handoff Stop hooks.
  No WP here touches them, nor `hooks/lead-crash-watchdog.sh`.
- **Lead context budget:** the origin lead keeps ≥50% free; it fires, collects notify-back pings, reviews
  landed state and files operator steps. Succession point: after W1-CI, W1-ACS, W2 and W4 report, or at
  60% fill, whichever is first; recycle with this plan as the bridge.

## Waves

| Wave | Repo | WPs (DESIGN §5) | Fixes | Status |
|---|---|---|---|---|
| W0 | — | OP-1, OP-2, OP-2b, OP-2c | X1 fseventsd restart, X24 cleanups, wired + fs_usage capture | X1 **done by another actor** (fseventsd pid 96656, 14 MB at 2026-10-17 ~10:00Z; was 12-13 GB). Spotlight Privacy entry, OP-2* pending → operator script |
| W1-CI | claude-infrastructure | WP-1, WP-5, WP-6, WP-7, WP-8 | X2, X3 (bats), X8, X5, X4 | pending |
| W1-ACS | agent-context-sync | WP-2, WP-3, WP-4, WP-22, WP-30 | X3, X11, X20, X10, X26 | pending |
| W2 | claude-infrastructure | WP-9, WP-10, WP-11, WP-12, WP-13, WP-14 | X6, X7, PARK tier, §4.2 detectors | pending |
| W3 | claude-infrastructure | WP-15, WP-16, WP-17 | X9 event queue, activation (staged), X17 | blocked on W1-CI + W2 |
| W4 | claude-infrastructure | WP-18-21, WP-23, WP-24, WP-25, WP-26, WP-28 | X12, X13, X25, X16, X15, X14 gate, X20, X18 | pending |
| W5 | hammerspoon-config, reso | WP-27, WP-31 | X22, X6 for reso's janitor | owner repos; fire with W4's session if their CLAUDE.md permits |
| W6 | — | WP-29, WP-32, OP-4 | X-POOL, X27, X23 | conditional on the post-W1 re-measurement and operator rulings |

## Learnings

- The load (365-520) was ~65-85% four concurrent agent-context-sync gates, multiplied by per-test waste
  (xcrun cache misses per fresh test HOME, duplicated and sentinel-killed suites, polling forks) and by a
  wedged fseventsd (4th episode). Claude sessions themselves were 9-13%. DESIGN §1.
- A shared gate pool is **not** supported by today's numbers (X-POOL: back-to-back is 21% slower); remove
  the waste first, then re-measure.
