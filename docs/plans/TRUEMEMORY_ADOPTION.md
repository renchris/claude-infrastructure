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

**Scope (grown, 2026-09-27, operator-approved):** +#35 end-to-end delivery benchmark in Wave B
(below). Why: retrieval is solved cheaply on our data (FTS5+embedding 90% vs TM 94%, noise), and
only 2-3 of 14 real misses were retrieval misses. The open question is whether the agent USES the
right lesson when it matters, which only a task-level A/B can answer.

**Scope (grown, 2026-09-27, operator: "maximal extraction … 100.00/100.00"):** +Wave D (build-later
#15-#22, each behind its entry condition) · +Wave E (experiments #4b, #23-#27, each ending in a
measured adopt-or-drop verdict) · +cross-cutting rules X6-X8 · +the stack inventory that defines
#35's arm 1. Rejections #28-#34 stay rejected; reopening one needs its §4 reopen condition met.

**Source of truth for designs:** the research doc. This plan does not restate designs. It owns the
order, ownership, locus and status. Per-item sections point at `§3.x` and add only what the doc
does not hold.

---

## Phase 0 — orchestration

**Execution locus per wave.**

| Wave | Locus | Items | Why this grouping |
|---|---|---|---|
| A · correctness + safety | **S** (dispatched session `tma-wave-a`, leads its own teammates) | #1, #2, #3, #8, #11 + autoDream-pin migration + rejection record | all independent of each other; #3 gates #6/#10/#14 in B and C |
| B · substrate + push consumers | **S** (`tma-wave-b`) | #4, #5, #6 (+#7 as its acceptance criterion), #10, #26 in shadow mode, then #35 delivery benchmark | #6 and #10 read #3's registry (X5); #5's retriever arm needs #4 |
| C · the rest of build-now | **S** (`tma-wave-c`) | #9, #12, #13, #14 | #14's sweep block needs #2; #12 edits the same instruction lines #10 edits |
| D · build-later | **S** (`tma-wave-d`) | #15-#22, each behind its entry condition | every entry condition is a Wave A-C deliverable |
| E · experiments | **S** (`tma-wave-e`) | #4b, #23, #24, #25, #26 verdict, #27, #36 | each needs #4/#5 (and #14 for #24-25) to measure against |

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

## Wave A — correctness and safety (S · `tma-wave-a`) — DONE 2026-09-28

**Landed (origin/main, content-verified):**
- #1 `6b1afce14` wording from `claudeMdExcludes` via `hooks/lib/rules-loaded.sh`; `6d052d43e` static
  lint `tests/hook-output-contract.bats`; `03e41f1c6` hermetic HOME for both new suites.
- #2 P0 `bef0303d4` (tracking table via temp file) · P0b `9ce845cb0` (probe via busy-timeout
  `session_index_sql`, skip-on-failure, `-bail` + `BEGIN IMMEDIATE`, `user_version` fast path) ·
  P1 `ce235bc70` (sessions_fts identity fingerprint, hourly alarm-only parity, `SWEEP-VERDICT`) ·
  `58c2951b8` errexit-reachable asserts. P0b ported to claude-session-search `5811933` (no P0 there:
  that copy has no `awk -v tracking`). P2 not built (optional). Follow-up fix "a stamped DB
  re-creates a dropped sessions_fts" (see Learnings), in both repos.
- #3 `d08ab07ab` every-exit IDL rows (harvest, session-index-end/-start, nudge interval 0 vs garbage) ·
  `dde03ca37` `scripts/idl-expected-fires.tsv` + SILENT/DEGRADED/UNKNOWN · `2b1c101f3`, `663044b6c`.
- #8 `cf32f48ff` `memory-fleet-sweep.sh --reach`: `REACH`, `NATIVE`, `NATIVE-STORE`,
  `NATIVE-TRANSCRIPTS`, `HISTORY` rows and the two verdict tokens.
- #11 `46a55dc07` `scripts/memory-store-snapshot.sh` (bare gitdir outside the store, CAS commit),
  rotor pre-mutation call, detached SessionStart trigger, compact-memory step · `127d39e20` its BLIND
  reasons (X3) · `1f4a425f4`.
- Migration `59331fee0` `migrations/0043-autodream-pin.sh` (c10, staged; operator step
  `ac6cfd21f07f`). Rejection record `b531da930` (MEMORY_KNOWLEDGE_V2 §8 R11-R18, R2 scope note, R7
  correction).

**Learnings (for Waves B and C):**
- Live `--reach` reads `REACH-VERDICT dark_dest=3` (personal, sevenrooms-bridge and the
  `~/Development` root store), not the 2 the research predicted, and #1 does not lower it: #1 fixes
  wording, not reachability. Clearing it needs a pointer in a delivered file for each store, which
  is a memory-store or foreign-repo write. The alarm row belongs to row 10 (plan R5).
- The nightly alarm may page `harvest-skill-end` and `memory-nudge` SILENT for about one night after
  deploy (live: 0 rows vs D=79 and D=34) until about 10 rows accrue. That is the gap it exists to
  show. If harvest keeps reading `index-row-stub` BLIND, the SessionEnd race is real: derive
  commands from the transcript too.
- New land gates a wave must pre-run: bare `shellcheck -s bash` on every changed `.bats` (one scope
  per file, so an array and a string sharing a name trip SC2178/SC2128);
  `scripts/test-hermeticity-lint.sh` (it also forces removal of an allowlist line once a suite is
  hermetic); `scripts/bats-assert-liveness.py` (a mid-test `[[ … ]]` needs `|| false` on bash 3.2);
  `scripts/moving-ref-control-lint.sh` (it flags `git show main:` even on a fixture repo; read through
  a resolved sha).
- Under load above about 80, ship-land sheds its test smoke and lands "behaviorally UNGATED". Run
  each item's suites yourself before and after the land.
- Named teammates can finish and still leave nothing but uncommitted edits when their process dies;
  #1's last fix was completed lead-inline from its worktree.
- The `NATIVE` sentinel reads `nondefault=0`: all native memory passes are off in all six caches today.
- Branches that are each green can still be red together. P0b's `user_version` fast path returned
  before the idempotent `CREATE … IF NOT EXISTS` pass, so a dropped `sessions_fts` never came back.
  Only P1's identity suite, run against trunk after both landed, showed it (2 of 10 red). Fix: one
  read returns both the stamp and whether the table exists. Re-run every wave suite on trunk after
  the last land, not only on each branch.


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

## Wave B — substrate and push consumers (S · `tma-wave-b`) — DONE 2026-09-28

**Landed (origin/main, content-verified):**
- X6 probe + #35 pre-registration `2866cb421` (research §5.15-5.16; `hook-probe/{tool,failure,subagent}-run.sh`),
  re-verified on 2.1.280 `c36bf87cf`. All four tool-event channels deliver on 2.1.278 and 2.1.280.
- #6+#7 output arm `bf2524ed8` (inject-sanitize.jq, lesson-symptoms.tsv) · `4a5b11919` (bash-output-offload
  and log-bash PostToolUseFailure arms through hooks/lib/lesson_recall.py) · `1d46ca69d` (lesson-recall-replay.py:
  denominator, delivery join including subagents/*.jsonl, canary; registry rows; nightly step 7).
  #6 emitters `6bacb2210` (lesson pointers on the cc-bats DEFERRAL, ship-land UNGATED/killed and deploy-live
  core.bare lines) · `ba8e5c24a` (ship-land refuses an outer timeout/gtimeout at preflight, rc 2;
  SHIP_ALLOW_OUTER_TIMEOUT=1; postland-verify's auto-revert lane opts out).
- #5 `5224eec5e` (docs/research/memory-eval/recall_eval.py, public fixture, README) · `123844981`.
- #26 shadow `e2d44ff12` (memory-nudge:ruling IDL rows + ~/.claude/state/ruling-shadow.jsonl; no model text).
- #10 `bd56935ab` (hooks/lib/memory_neighbours.py, backup-before-write branch, OVERWRITE GUARD past tense,
  mem-neighbours-outcome.py nightly step 7b) · nudge reword `00ca6bdf3`.
- #4 `910f86140` (bin/cc-memory-search) · `045c8f334` (registry row) · `974122f01` (CLAUDE.global.md,
  CLAUDE.global.slim.md, compact-memory step 7) · `c9b085699` · combined-tree fixes `e771f4b88` (alarm
  selftest) and `131ecf70f` (nightly stubs).
- #35 `9fe735df7` (harness) · `05e357990` (no deletes, pinned origin) · `ddf721d05` (§5.17 results): **no gain** (0 wins, 0 losses, 16 ties; stock solved 15/16, so the tasks had no headroom).
  #6 delivered its pointer in 8/8 symptom runs and none opened it; #10 never fired. Research §5.17.
  The pre-registered no-gain branch applies: no push consumers on faith, Wave E #23 and #26 stop, and a
  delivery-research wave needs tasks the stock arm fails.
- Live layer converged at `ba8e5c24a`; live canaries green (lesson-recall CANARY-VERDICT ok; cc-memory-search
  CANARY-VERDICT ok stores=16 miss=0). X6 live probes passed for #6 (both arms), #10 and the nudge line.

**Learnings (for Waves C-E):**
- Idle teammates are reaped. The TeammateIdle auto-shutdown ends a teammate and removes its worktree once it
  idles with a clean tree, even while it waits on the lead: #35's first teammate died waiting for a one-line
  decision. Brief teammates to `touch <worktree>/.teammate-busy` before any wait and never design a lead
  checkpoint into a brief. Branches survived every reap; recreate the worktree from the branch.
- All the Wave B branches appended to the same three files (idl-abstain-alarm.sh, idl-expected-fires.tsv,
  nightly-regression.sh). Every land after the first hit a rebase conflict. All were unions, but one union left
  a function unclosed and two teammates both numbered their nightly step 7. Next wave: one teammate owns the
  registry and nightly edits and the others hand it their rows.
- Branches green alone, red together, twice: (1) #6's replay and #10's new-file count read live data, so the
  alarm --selftest went 56/2 on trunk (`e771f4b88`); (2) neither new nightly step was stubbed in
  deploy-live.bats' fixture nightly, so 6 of its cases went red on trunk (`131ecf70f`). Each item's own
  suites were green. Run the selftests and deploy-live.bats on the combined tree before the last land.
- `bats` here is the cc-bats admission shim. A refusal prints no `1..N` and zero `not ok`, so a failure filter
  reads it as a pass (it did once this wave). Only a plan line is a result.
- 2.1.278 refuses claude-opus-5-5 ("version 2.1.280 or newer is required"); #35 ran on 2.1.280 and X6 was
  re-run there. The zsh `claude` function was broken in tool calls; probes call the binary by path.
- #6 permanently holds out 3 of its 8 symptom slugs (sha1 % 5), including the live nohup recurrence. The
  verdict needs ≥15 control events (§3.6 acceptance 6), not a 2-week read.
- #6 first counted 49 hits/day on successful output: reads of lesson and memory files print the literals. The
  hook and the replay now skip those commands; 11/day after.
- The land gate's wall-clock lint reads an invalid test date (`2026-13-45`) as a future time bomb; use a
  non-date string for "rejects garbage" cases.
- Never shut a teammate down while a land runs from its worktree. The reaper removed #35's worktree mid-land;
  the orphaned ship-land then rebased and LANDED the lead's own branch (`156484592`, the plan with placeholders,
  plus `131ecf70f`, `c36bf87cf`) and left #35's commits unlanded. The earlier "foreign" rebase of the lead
  worktree was the same process. Harvest, shut down, confirm the process is gone, recreate the worktree from the
  branch, and only then land.
- Deferred to Wave E #4b: the private retriever-arm run of recall_eval.py (it needs the per-project store map
  the #5 teammate built ad hoc). #4b's entry condition (#4 and #5 landed) now holds.
- Seen read-only, not this repo's: the reso shared checkout sat at core.bare=true during this wave.

#4 (§3.4, targets both `CLAUDE.global.md:103` and `CLAUDE.global.slim.md:47` plus live copies) ·
#5 (§3.5, seeded from the 19 time-valid field queries; the private gold goes in
`~/.claude/autonomy/memory-eval/`, never the repo) · #6 with #7 (§3.6, §3.7; delivery probe first;
holdout needs ≥15 control events) · #10 (§3.10; logs every exit path, nightly outcome check) ·
#26 shadow mode (§3.23-3.27 group; log-only, no model-facing text).
**Wave B's first action:** the private gold query set is already preserved at
`~/.claude/autonomy/memory-eval/field-queries.json` (copied off `/tmp` by the lead, 2026-09-27).
If it is ever missing, re-derive it per `docs/research/truememory-2026-09-27/gap-2.md`.

**#35 end-to-end delivery benchmark (last Wave B item; runs after #4, #6, #10 land).**
- **Question it answers:** given a real task where a stored lesson decides the outcome, does the
  agent use that lesson and get it right?
- **Arms:** (1) Claude Code auto memory out of the box, no hooks of ours; (2) our stack before
  Wave B; (3) our stack with #6's tool-failure push and #10; (4) optional: TrueMemory with its hook
  output wrapped in `hookSpecificOutput` (install only in a sandboxed HOME, never the real config;
  drop the arm if it will not install cleanly).
- **Harness:** start from `docs/research/truememory-2026-09-27/ab-harness/` (`run-ab.sh`,
  `score.py`, `tasks.tsv`, prototype `cc-memory-search`; built and dry-run in the study, never run
  for real). Its defaults point at `/tmp` paths: re-point them, and regenerate the frozen store copy
  from the live store rather than committing it (it is private). Extend `tasks.tsv` so every task has
  a lesson whose absence changes the outcome, plus control tasks where no lesson applies.
- **Scoring:** lesson used (read or acted on), task correct, time, tokens. Pre-register the pass rule
  before running (the harness already carries one: ≥30% line-arm uptake at p<0.05 counts; <10% means
  substrate only).
- **Budget:** 12 tasks × 2 reps × 4 arms ≈ 96 runs ≈ 2-4 weekly-quota points on one account (priced
  from 88 comparable runs at 0.02-0.04 pp each; `cc-quota-price` fit, rel-RMSE 0.37). Route it to
  the account that would otherwise strand the most quota. Operator ruling 2026-09-27: runs at this
  cost need no ask.
- **If push shows no gain** (arm 3 not better than arm 2 on lesson-used, sign test p ≥ 0.1): do not ship more push consumers on faith. Stop Wave E's push-shaped experiments (#23, #26), keep #6 and #10 only if their own logs show delivered-and-used events, and open a research wave on WHY delivery does not change behaviour (salience, placement in the tool result, rule wording), using #36's fixtures. That research wave is the one this program pre-authorises.
- **Done when:** the results table (arm × lesson-used × correct × tokens) and its verdict are
  appended to `docs/research/truememory-2026-09-27.md` §5 and landed.

## Wave C — the rest of build-now (S · `tma-wave-c`) — ready (Wave B DONE 2026-09-28)

#9 (§3.9) · #12 (§3.12, both CLAUDE variants) · #13 (§3.13, link lint only; no forget cascade) ·
#14 (§3.14, loud fallback; consumer-level test).

## After this program — build-later and experiments (not in the frozen DoD)

*(Superseded 2026-09-27 by Waves D and E below: the operator asked for maximal extraction, so
these items are now in the DoD, each behind its entry condition. The table is kept as the original
record.)*

| # | Item | Starts when |
|---|---|---|
| 15 | read-ledger | #2 P0+P0b landed |
| 16, 17 | consolidation families + merge-losslessness rule | #4 and #10 landed |
| 18 | episodic-session-recall | #2 landed and indexing `workflows/wf_*.json` |
| 19 | rotor fd-lock | any time |
| 20 | report-only frontmatter schema listing | any time |
| 21, 22 | claim-queue spec; deny-only capture ledger | a background worker is approved |
| 23-27 | experiments | #4 and #5 exist (23, 27); #14 (24, 25); #26 already in B |

## Wave D — build-later items (S · `tma-wave-d`) — BLOCKED on Waves A-C

Each item's design is the research doc section named. "Done" = landed, gate-green, own suite passes.

| # | Item | Design | Entry condition | Done when |
|---|---|---|---|---|
| 15 | read-ledger (protects entries in the rotor's rank; never selects for eviction) | §3.15 | #2 P0+P0b landed | ledger fills hourly; rotor test shows a read entry is kept |
| 16 | consolidation families at compaction (propose-only, mutual top-3) | §3.16 | #4 and #10 landed | `/compact-memory` step 7b proposes families; nothing merges without a human |
| 17 | merge-losslessness rule (every hard token survives or is recorded superseded) | §3.17 | with #16 | `cc-memory-dropped-token-audit --pair` flags a lossy merge in a fixture |
| 18 | episodic-session-recall (narrow cue line pointing at claude-search) | §3.18 | #2 landed AND the sweep indexes `*/workflows/wf_*.json` | the gap-2 episodic misses resolve through claude-search in a replay |
| 19 | rotor fd-lock (kernel-released lock, not 180 s age reclaim) | §3.19 | any time | a killed rotor leaves no lock; test proves it |
| 20 | report-only frontmatter schema listing | §3.20-3.22 | any time | `memory-fleet-sweep --schema` lists violations, writes nothing |
| 21, 22 | claim-queue spec; deny-only capture ledger | §3.20-3.22 | a background memory worker is approved (Wave E #24 verdict) | spec recorded in `MEMORY_KNOWLEDGE_V2.md`; ledger only if the worker is approved |

## Wave E — experiments, each ending in a measured adopt-or-drop verdict (S · `tma-wave-e`)

An experiment is done when its verdict and numbers are appended to the research doc §5, not when it
ships. Adopted ones become Wave-D-style build items; dropped ones get a rejection row.

| # | Experiment | Design | Entry condition | Verdict rule |
|---|---|---|---|---|
| 4b | FTS5 + model2vec (potion) fusion in `cc-memory-search` | §3.4 stage 2 | #4 and #5 landed | adopt if #5 shows a gain on queries NOT written by an agent (the study's 0.78 → 0.90 R@1 gain, 6 wins to 0, p = 0.031, was on agent-written queries). model2vec needs numpy only, no torch, so R14's hook-path rule holds |
| 23 | per-prompt pointer recall, shadow mode first | §3.23-3.27 | #4, #5, #7 landed | pre-registered: over ≥40 shadow fires on real operator prompts, hand-labelled, top-1 relevant ≥60% with a Wilson 95% lower bound ≥45%, AND fires on ≤15% of prompts; else drop. The study measured raw bm25 floors as length-confounded (top-1 relevant 6/40 in a mixed store), so the floor must be rank- or length-normalised |
| 24 | candidate extractor, `--dry-run` Stage 0 only | §3.23-3.27 | #14 landed | pre-registered: on a hand-labelled sample of ≥50 Stage-0 candidates, ≥90% pass every anti-capture class, AND it recovers ≥3 of the 4 never-written operator rulings (gap-2 #47, #58, #66/67, #70 family) from their transcripts; else drop |
| 25 | transcript capture scan, dry-run verdicts | §3.23-3.27 | #24 passes Stage 0 | as #24 |
| 26 | ruling-shaped operator text nudge | §3.23-3.27 | already shadowing in Wave B | pre-registered: over ≥20 shadow fires, precision ≥70% (fire = a standing operator ruling, hand-labelled), AND it fires on ≥2 of the 4 never-written rulings when their prompts are replayed; else drop. Baseline: the study's regex 5 hits, 0 standing rules; unanchored "remember" 11 hits, about 8 rules |
| 27 | provenance-and-verification tier (prose receipt) | §3.23-3.27 | #4, #5 landed | adopt only with a delivery mechanism other than prose (X7) |
| 36 | adherence at the moment of action: rules already in context or resident but not followed | new (gap-2 §classification row "in context or resident, not obeyed") | #35's harness exists | Fixtures: the four real misses — #10 (re-read the thread before each draft), #11 (a claim that implied nothing was due later), #29 (a command handed to the user that the agent could run), #79 (a sign-off the agent was told it may never give) — plus the resident-lesson recurrences (71% of recurrences had the rule resident, `our-usage.md:129`). Step 1, bounded: inventory the repo's existing moment-of-action checks (Stop-hook close checks such as `completion-assert.sh`, `anti-deference-nudge.sh`; PreToolUse guards) and map which of the four each would have caught. Step 2: build the cheapest mechanism that pushes the one relevant rule at the action (a draft, a close, a hand-off command) and run it through #35's harness on these fixtures. Pre-registered: adopt if it prevents ≥3 of 4 fixture misses with ≤10% added false blocks on control tasks; else record why and drop |

## Open questions (tracked, not yet answerable)

| Question | Why it matters | How it gets answered |
|---|---|---|
| Do our PreToolUse hooks fire on tool calls made inside Claude Code's native background memory writers (extractMemories, autoDream)? | If not, those writers bypass every guard we have, and #11's history is the only protection | Only testable when either flag reads on. #8's native-pass sentinel detects a flip; the first session after a flip runs a marker-hook probe (X6 pattern) inside the fork before trusting anything |

## Cross-cutting rules learned 2026-09-27 (X6-X8, bind on Waves B-E)

These extend the research doc's X1-X5 (§2) with what the session after the study measured.

- **X6 · Prove delivery live, not by shape.** Any hook that injects text must, before it counts as
  done, pass a live delivery probe: the pattern in
  `docs/research/truememory-2026-09-27/hook-probe/run.sh` (a marker token, `claude -p`, the model
  asked whether it sees it), run on the current Claude Code binary. Why: TrueMemory's injection
  looked correct and was dropped by Claude Code; only a live probe showed it. The output must be
  `{"hookSpecificOutput": {"hookEventName": "<event>", "additionalContext": …}}`.
- **X7 · A prose instruction is not a delivery mechanism.** No item may count "a line in CLAUDE.md or
  rules telling the model to search/check X" as its consumer. Measured: 0 of 54 and 2 of 64 uptake.
  Delivery must be pushed by a hook at the moment of need (tool failure, file write, prompt).
- **X8 · No artifact lives only in `/tmp`.** Eval corpora, gold sets, harnesses and results go to the
  repo (if not private) or `~/.claude/autonomy/` (if private) the moment they exist. The study nearly
  lost its harness and gold set to `/tmp`; `/private/tmp` is wiped at boot.

## Stack inventory — what is Claude Code's and what is ours (the #35 arm-1 baseline)

- **Claude Code built-in:** per-project memory folder; `MEMORY.md` index loaded every session,
  capped at 25,000 UTF-16 chars / 200 lines after frontmatter and comment stripping (newest entries
  dropped silently past the cap); the built-in memory-writing instruction (types user / feedback /
  project / reference, `[[links]]`); `CLAUDE.md` and `.claude/rules/*.md` loading; two flag-gated
  background writers (extractMemories, autoDream), off today; `autoMemoryDirectory` setting.
- **Ours:** the anti-capture rules; `hooks/memory-nudge.sh`, `hooks/memory-index-drain.sh`;
  `bin/cc-memory-rotate` (cold tier) and `/compact-memory`; `hooks/lib/memory-index-measure.sh`;
  `docs/lessons/` + rules-file hooks + `scripts/rules-hook-budget-lint.sh`;
  `scripts/worktree-memory-link.sh` and the per-account symlink mirror (one physical store);
  `hooks/harvest-skill-end.sh`; the session index (`hooks/session-index-*.sh`, `claude-search`, the
  `claude-session-search` repo); `scripts/memory-fleet-sweep.sh`, `bin/cc-memory-dropped-token-audit`.
- **#35 arm 1** therefore runs with a config dir that has none of "ours": no hooks, no rules files,
  the stock memory instruction, and a frozen copy of the store via `autoMemoryDirectory`.

## Status log

- 2026-09-27 — Research landed (`docs/research/truememory-2026-09-27.md`). Plan created. Wave A next.
- 2026-09-27 — Wave A fired (pane `tma-wave-a`, account next). Hook-delivery finding re-measured live (`9639822a7`). #35 delivery benchmark added to Wave B; A/B harness preserved under `docs/research/truememory-2026-09-27/ab-harness/`.
- 2026-09-27 — Scope grown to maximal extraction: Waves D (build-later) and E (experiments with verdict rules), X6-X8 learned in the post-study session (live delivery probe, prose is not delivery, nothing only in /tmp), and the built-in-vs-ours stack inventory. Upstream TrueMemory fix kit: `docs/research/truememory-2026-09-27/UPSTREAM_FIX_KIT.md`.
- 2026-09-27 — Completeness review closed four plan gaps: numeric pre-registered verdicts for #23/#24/#26, #35's no-gain branch (pre-authorises a delivery-research wave), new experiment #36 for rules in context but not followed (4 of 14 real misses), and the native-fork hook question as a tracked open question. Our own hooks were checked for TrueMemory's top-level additionalContext bug: 38 files reference it, none emit it outside hookSpecificOutput.
- 2026-09-28 — Wave A DONE: #1, #2 (P0, P0b, P1 + claude-session-search port), #3, #8, #11, migration 0043 (staged) and the rejection record landed; learnings under § Wave A. Wave B next.
- 2026-09-28 — Wave B DONE: #4, #5, #6+#7, #10, #26 (shadow) and #35 landed; live layer converged. #35 read no gain (the tasks had no headroom), so the pre-registered no-gain branch applies: Wave E #23 and #26 stop and the next delivery measurement needs tasks the stock arm fails. Learnings under § Wave B. Wave C next.
