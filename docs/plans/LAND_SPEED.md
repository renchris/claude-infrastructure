---
status: complete
---

# LAND_SPEED — first-time-successful, fast lands in claude-infrastructure

Opened 2026-09-24 · branch `fix/land-speed`

Scope (frozen): make landing in claude-infrastructure (scripts/ship-land.sh) first-time-successful
and fast — root-cause the measured failure and latency classes, fix the top ones with
red-then-green tests, land them, and record before/after numbers from `~/.claude/land.log` —
without weakening any gate.

## Phase 0 — orchestration

| wave | work | locus | why |
|---|---|---|---|
| W1 | measure (census script + per-arm precheck timing) | **L** (lead-inline) | read-only, and every later decision hangs on it |
| W2 | fix 1 — stranded-sweep `--mine` prefilter | **L** | one script + its suite, ~70 lines; a fan-out would cost more context than it saves |
| W3 | fix 2+ — chosen from the W1 ranking | **L** | same file (`scripts/ship-land.sh`) for every candidate — parallel writers would conflict |
| W4 | land + converge + post-window census | **L** | serial by nature (one land-lock) |

Lead context budget: hand off at ~60% fill; succession point is after any committed fix — the plan
and the census reproduce all state from disk.

## The instrument

`scripts/land-speed-census.py` (tests: `tests/land-speed-census.bats`). Every number below is a
re-run of it; never quote one without its window.

```
python3 scripts/land-speed-census.py --from 2026-09-18T01:20:00Z --to 2026-09-25T01:20:00Z   # baseline
python3 scripts/land-speed-census.py --compare <first-fix-live stamp> --days 7              # before/after
```

Two corrections to the brief's numbers, both from the census's denominator rules (which follow
`scripts/gate-red-census.sh`): the brief counted 314 `stage:"round"` rows (exit 42) as attempts.
Rounds are internal to one land. Counted correctly the landed rate is **61%, not 41%**, and
attempts per landed branch are **p50 1 / p90 3**, not 2 / 6.

## Baseline (2026-09-18T01:20Z → 2026-09-25T01:20Z, n = 567 terminal lands, 265 rounds)

| | value |
|---|---|
| landed | 346 (61.0%) — 220 on gate round 1 |
| exit 6 (gate red) | 141 — 102 statics/ratchet-only, 39 smoke-involved |
| exit 11 / 143 / 5 / 9 / 7 | 31 / 13 / 17 / 6 / 4 |
| landed total_s p50 / p90 | **1036s / 2903s** |
| … gate_s | 353 / 2197 |
| … gate_arms_s | 228 / 808 |
| … **post_s** (lock release → landed row) | **584 / 858** |
| … pre_s | 5 / 15 |
| stale-round gate time thrown away | 53.9 h in the window (21.2 h of it arms) |

## Findings, ranked by cost

1. **The post-push stranded-sweep was the biggest single term — 56% of a median landed land,
   more than the whole gate.** `post_release_finish` runs `stranded-sweep.sh --mine <sid>` before
   it writes the landed row, and the sweep forked one `git cherry` per local branch. There are
   2,984 local branches now (the script's own comment priced 708). Timed on the real repo:
   **16m43s** at load ~180, and it ended in a NO VERDICT because a sibling reaped its backup ref
   mid-walk. Lead 1–3 all missed it because they looked inside the gate.
   → **FIXED** (fix 1): under `--mine` only commits reachable from the session's anchors (minus
   trunk) or carrying its trailer can be reported; that set is computed in two git calls and only
   branches containing it are walked. Same repo and load: **0.95s**, same verdict.
2. **Stale-gate re-rounds (lead 1)** — confirmed large: 126 of 346 landed lands needed ≥2 rounds,
   and 53.9 gate-hours were thrown away. Rounds that go stale are the long ones (a stale round-3
   row has smoke p50 764s), so each re-round is as likely to go stale again. Per-round increments
   (round rows carry CUMULATIVE gate_s, so these are differences): round 1 gate p50 255s, round 2
   p50 479s, round 3 p50 542s — re-rounds cost MORE than first rounds, because union scope adds
   the sibling delta's suites on top of re-running the lander's own.
   **Replay** (20 sampled stale re-rounds, each put back through `gate-select --direct` as
   own-range and sibling-delta-range): **499 of 517 own suites (97%) were not selected by the
   sibling delta** — the re-round re-proved suites nothing had touched. First replayed row: 17
   suites / 768s of smoke, 18 own suites, sibling selected 0.
   → **FIXED** (fix 3): a suite green earlier in THIS land, blob unchanged, and not selected by
   `gate-select --direct <base it went green>..<this base>` is carried. This is the selector's own
   model — the land gate already trusts it to decide which suites a change can reach at all; the
   sibling delta's suites still run. FULL / a dead selector / a changed blob / a red, cut or
   unreached suite all re-run. Kill switch `SHIP_LAND_SMOKE_CARRY=off`; land.log `smoke_carried`.
   The arms half of a re-round is already blob-memoized per file for most arms (moving-ref: 749
   verdicts carried, 2 proven fresh); fix 2 removed the largest unmemoized re-scan.
   **Per-arm split** (the one measurement the 2026-09-09 land-gate research could not take):
   `ship-land.sh --precheck` on this branch with a timestamp on every `→ gate:` line, load ~150,
   arms total 228s. Raw log: `/tmp/land-speed-precheck-arms.log` (ephemeral; re-derive by
   re-running precheck through the same timestamping loop).

   | arm | s |
   |---|---|
   | unattended-path (bare-name binaries) | **132** — selftest 101 + own-scope scan 72 (timed apart) |
   | test-hermeticity | 32 |
   | git-identity | 16 |
   | everything else (30 arms) | ≤ 5 each |

   (Arm time = gap between consecutive `→ gate:` lines. fleet-manifest's gap reads 17s but its own
   OK line lands 5s after its header; the rest is the post-arm tail, so it sits in the last row.)

   The unattended arm scanned the tree **twice per round**: its `--selftest` includes a real-tree
   arm that is a STRICT scan of the same root, and the gate then ran the OWN-SCOPE scan, whose
   blocking set is a subset of strict's. → **FIXED** (fix 2): the selftest prints a receipt only
   when that arm ran and passed; the gate skips its own-scope scan only on the exact receipt for
   the same root. ~72s off every round, including every stale re-round.
3. **Gate reds (lead 2)** — 102 of 141 reds are statics/ratchet arms only, the class
   `ship-land.sh --precheck` already covers (it exists, runs statics + every ratchet arm, takes no
   lock and writes no row). Their direct cost is small (p50 152s each, 4.7 h in the window); what
   they cost is a second land. Nothing in land.log records whether a lander ran precheck first.
   **Not made mandatory, deliberately:** precheck runs the same arms the land does, so putting it
   in front of every land adds a full arms phase to the ~82% that are not arm-red in order to save
   one cycle on the ~18% that are — a net loss while the arms are the cost. What shortens a red
   is cheaper arms (fix 2) and arm ORDER: arms fail fast, and ~21 reds/week (bats-shellcheck 15,
   kill-guard 4, …) sit behind the unattended arm. Moving that arm last would surface them ~100s
   sooner at no semantic cost; left as a follow-up because it is a ~90-line block move in a file
   siblings edit weekly.
4. **Load (lead 3)** — load was 135–250 on a 10-core box through this whole session. land.log does
   not record load, so arms-vs-load cannot be read from the store.
5. **exit 143** — 13 killed lands, 6.9 h, p50 948s. Killed from outside; not a ship-land defect.

## Fixes

| # | commit | what | tests |
|---|---|---|---|
| 1 | `472993fb8` | stranded-sweep `--mine` prefilter | `tests/stranded-sweep.bats` 17–19, red 3/3 pre-fix, green 19/19 |
| 2 | `236d7fdbb` | unattended-path own-scope scan carried by the selftest's strict receipt | `tests/ship-land.bats` LAND_SPEED ×2 (red 1/2, root-blind mutant killed); `tests/unattended-path-lint.bats` receipt (red pre-fix) |
| 3 | `d04090569` | stale re-round carries own suites the trunk delta cannot reach | `tests/land-gate-cas.bats` LAND_SPEED carry ×2 (red 1/2, selection-blind mutant killed) |
| — | `52ecab2dd` | the census | `tests/land-speed-census.bats` 4/4 |

Shas are pre-land; the land rebases them. Resolve by subject on trunk.

## Before / after

Landed `86f9c997d` at 2026-09-25T03:08:37Z (content-verified, sweep clean); live layer converged
the same minute (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, rc 0, 0 un-stamped
commits above the live tip). The land's own smoke was load-shed (load ~200 ≥ ceiling 80), so the
behavioural proof is the suites run by hand this session: stranded-sweep 19/19, land-speed-census
4/4, land-gate-cas 22/22, gate-selftest-memo 8/8, gate-precheck 13/13, land-gate-memo 11/11,
gate-ownscope-leak 24/24, land-lint-scope-derived 13/13, ship-land-converge-edge 9/9,
land-inflight 9/9, land-reland-row-identity 4/4, gate-home-isolation 23/23, unattended-path-lint
21/21, ship-land 179/179 once the pre-existing red below was fixed. (`land-gate-cas` "many refs"
went red once on a wall-clock `hold_s ≤ 2` bound at load ~200, then passed in BOTH arms, trunk
scripts and branch scripts, back to back at the same load. It was the box, not the diff.)

`python3 scripts/land-speed-census.py --compare 2026-09-25T03:08:37Z --days 7`:

| landed lands | baseline (7d, n=338) | post (n=2 — **too small to judge**) |
|---|---|---|
| total_s p50 / p90 | 1037 / 2869 | 776 (this land), 1003 (a sibling) |
| gate_s p50 / p90 | 348 / 1987 | 770, 205 |
| **post_s** p50 / p90 | **593 / 883** | **1 (this land)**, 794 (the sibling) |

**Read the post column per row, not as a percentile.** With n=2 the census's p50 picks the larger
value. The 794s is `research/tokeff-wave2`, which landed 10s after this one and ran its OWN
worktree's pre-fix `stranded-sweep.sh`: ship-land resolves every script through `$SCRIPT_DIR`, so a
rail fix reaches only lands from worktrees cut after it (situational lesson "Rail fix is
per-worktree"). This land ran the fixed sweep: 1s. On a quiet trunk the fix reaches the fleet over
roughly a day as worktrees turn over; re-run `--compare` with the same cut once n ≥ 30 to publish
a p50. Fix 3 did not fire on this land (it went green on round 1, so no re-round happened). Fix 2
did fire ("unattended-path own-scope scan CARRIED"). This land's arms were 745s at load ~200, so
one land at that load cannot show fix 2's ~72s.

Pre-existing red found and fixed on the way (`a476baecc`, rebased on land): `tests/ship-land.bats`
"shellcheck ABSENT" was red on trunk at the same load. Since `362811da6` the lint searches
`/opt/homebrew/bin` when PATH misses, and the fixture sealed only PATH. It also pinned
pre-rewording text.

## Follow-ups (not done; each named with why)

- **Move the unattended-path arm last in run_gate.** Arms fail fast, and ~21 reds/week sit behind
  it, so they would surface ~100s sooner. Not done: it is a ~90-line block move in a file siblings
  edit weekly, for about 35 min/week of red latency. It passes F1 but not the size bar for this land.
- **Publish post-fix p50s** once the post window reaches n ≥ 30 (same `--compare` cut).
