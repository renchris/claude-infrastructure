---
status: in-progress
---

# TrueMemory adoption — build the verified adoptions into our agent memory

**Scope (frozen):** implement every **build-now** adoption (#1-#14) from
`docs/research/truememory-2026-09-27.md` §2, to that doc's per-item design (§3.x) and the
cross-cutting acceptance criteria X1-X5 (§2). Each item is landed on trunk, gate-green, and its own
bats suite passes. Build-later items (#15-#22) and experiments (#23-#27) are out of this DoD. They
are listed at the end with their named dependency so the next session can pick them up once the
data they wait on exists. Rejections (#28-#34) are recorded in `MEMORY_KNOWLEDGE_V2.md` so no
session re-derives them.

**Source of truth for designs:** the research doc. This plan does not restate designs. It owns the
order, ownership, locus and status. Per-item sections point at `§3.x` and add only what the doc
does not hold.

---

## Phase 0 — orchestration

**Execution locus per wave.**

| Wave | Locus | Items | Why this grouping |
|---|---|---|---|
| A · correctness + safety | **S** (dispatched session `tma-wave-a`, leads its own teammates) | #1, #2, #3, #8, #11 + autoDream-pin migration + rejection record | all independent of each other; #3 gates #6/#10/#14 in B and C |
| B · substrate + push consumers | **S** (`tma-wave-b`) | #4, #5, #6 (+#7 as its acceptance criterion), #10, #26 in shadow mode | #6 and #10 read #3's registry (X5); #5's retriever arm needs #4 |
| C · the rest of build-now | **S** (`tma-wave-c`) | #9, #12, #13, #14 | #14's sweep block needs #2; #12 edits the same instruction lines #10 edits |

Waves are **serial**: they share `hooks/memory-nudge.sh`, `bin/cc-memory-rotate`,
`scripts/memory-fleet-sweep.sh`, `hooks/lib/session-index-helpers.sh` and the two CLAUDE variants.
Within a wave the dispatched session assigns ONE owner per shared file (below).

**Task size per unit.** Each item is one unit, targeted at the 40-150K-output band (≈30-75 min,
3-6 files). #3 (S-M) is the largest; split it registry-vs-branch-logging if its brief exceeds 150
lines. No item is expected over 500 LOC.

**Shared-file ownership inside Wave A** (the only overlaps):

| File | Owner | Others |
|---|---|---|
| `hooks/memory-nudge.sh` | #3 (`:46-47,493-502`) | #1 edits `:531-560` after #3 merges, or hands its hunk to #3's owner |
| `bin/cc-memory-rotate` | #1 (`:25-41,516-528`) | #11 adds its pre-mutation snapshot call after #1 merges |
| `scripts/memory-fleet-sweep.sh` | #8 (`--reach`, `NATIVE` rows) | #11 adds its history row after #8 merges |

**Merge order inside a wave:** smallest diff first, rebase + `--ff-only`, each via project `/ship`.

**Lead context budget + succession point.** The lead is the origin session that ran the study. It
holds ≥50% of its window for deciding. It fires each wave and reviews the landed result by
reading the wave's close ping and `git log`, never its transcript. **Succession point:** after
Wave A lands, if the lead's fill is ≥35% it recycles (`handoff-fire.sh --recycle`) before firing B.
Everything a successor needs is this plan plus the research doc.

**Operator-only steps this program creates** (each filed with `cc-backlog needs` by the wave that
creates it, never done by an agent):
- Run the autoDream-pin migration (Wave A stages it: `autoDreamEnabled:false` in all 5 account
  `settings.json`; c10 class, agents may not edit settings).
- Register any new hook: designs #6 and #10 avoid needing one. If a wave finds it does need one, it
  stages a c10 migration and files it.
- Optional: the prose-line A/B (`docs/research/truememory-2026-09-27.md` §5.12; needs a real
  account config dir). It decides only whether #4's prose line counts as a consumer, so it is not
  on any build-now critical path.

---

## Wave A — correctness and safety (S · `tma-wave-a`) — NOT STARTED

| # | Item | Design | New/changed files (research doc §2) | Suite that must pass |
|---|---|---|---|---|
| 1 | situational-truth-and-delivery-contract | §3.1 | `hooks/lib/rules-loaded.sh` (new); `hooks/memory-index-drain.sh:249-290`; `bin/cc-memory-rotate:25-41,516-528`; `hooks/memory-nudge.sh:531-560`; `hooks/lib/memory-index-budget.sh:348`; plan R7 correction | `tests/hook-output-contract.bats` (new) |
| 2 | session-index-coverage: P0 awk fix, **P0b DROP fix in both helper copies**, P1 identity fingerprint + parity alarm | §3.2 | `hooks/lib/session-index-helpers.sh:228-271,783-800`; `hooks/session-index-sweep.sh`; **`~/Development/claude-session-search/hooks/lib/session-index-helpers.sh:116-157` (separate repo: read its CLAUDE.md, land there too)** | `tests/session-index-sweep.bats` (+ ≥2-row and locked-DB cases, both red before the fix) |
| 3 | memory-hook-heartbeats → expected-fires registry | §3.3 | `hooks/harvest-skill-end.sh`; `hooks/session-index-end.sh:56-109`; `hooks/memory-nudge.sh:46-47,493-502`; `scripts/idl-abstain-alarm.sh:26,128-157`; `scripts/idl-expected-fires.tsv` (new) | `tests/harvest-skill-end.bats`, `tests/idl-abstain-alarm.bats` |
| 8 | delivered-surface-reach-audit + native-pass sentinel | §3.8 | `scripts/memory-fleet-sweep.sh` (`--reach`, `NATIVE` rows) | `tests/memory-fleet-sweep.bats` |
| 11 | local-store-history | §3.11 | `scripts/memory-store-snapshot.sh` (new); `bin/cc-memory-rotate` mutation branches; trigger from the already-registered SessionStart hook (no new registration); `commands/compact-memory.md` | new `tests/memory-store-snapshot.bats` |
| — | autoDream-pin migration (staged, not run) | §1 finding 4, §7 | `migrations/<next>-autodream-pin.sh` per `migrations/README.md` (c10) | its own dry-run self-check |
| — | rejection record | §4 | `docs/plans/MEMORY_KNOWLEDGE_V2.md` new §8 (R11-R15 as the doc names them, plus #33, #34) | n/a (docs) |

Hard constraints for the wave: never write any memory store or `settings*.json`; never register a
hook; stage migrations only; X1-X5 bind on every new hook branch or lib; test the RENDERED hook
JSON; land via project `/ship` from the wave's own worktree.

## Wave B — substrate and push consumers (S · `tma-wave-b`) — BLOCKED on Wave A

#4 (§3.4, targets both `CLAUDE.global.md:103` and `CLAUDE.global.slim.md:47` plus live copies) ·
#5 (§3.5, seeded from the 19 time-valid field queries; the private gold goes in
`~/.claude/autonomy/memory-eval/`, never the repo) · #6 with #7 (§3.6, §3.7; delivery probe first;
holdout needs ≥15 control events) · #10 (§3.10; logs every exit path, nightly outcome check) ·
#26 shadow mode (§3.23-3.27 group; log-only, no model-facing text).
**Wave B's first action:** copy `/tmp/tm-research/gap2/field-queries.json` to
`~/.claude/autonomy/memory-eval/` if it still exists. `/tmp` is wiped at boot. If it is gone,
re-derive it per `docs/research/truememory-2026-09-27/gap-2.md`.

## Wave C — the rest of build-now (S · `tma-wave-c`) — BLOCKED on Wave B

#9 (§3.9) · #12 (§3.12, both CLAUDE variants) · #13 (§3.13, link lint only; no forget cascade) ·
#14 (§3.14, loud fallback; consumer-level test).

## After this program — build-later and experiments (not in the frozen DoD)

| # | Item | Starts when |
|---|---|---|
| 15 | read-ledger | #2 P0+P0b landed |
| 16, 17 | consolidation families + merge-losslessness rule | #4 and #10 landed |
| 18 | episodic-session-recall | #2 landed and indexing `workflows/wf_*.json` |
| 19 | rotor fd-lock | any time |
| 20 | report-only frontmatter schema listing | any time |
| 21, 22 | claim-queue spec; deny-only capture ledger | a background worker is approved |
| 23-27 | experiments | #4 and #5 exist (23, 27); #14 (24, 25); #26 already in B |

## Status log

- 2026-09-27 — Research landed (`docs/research/truememory-2026-09-27.md`). Plan created. Wave A next.
