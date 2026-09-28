# TrueMemory study: what to take into our agent memory

Date: 2026-09-27. Subject: `buildingjoshbetter/TrueMemory` at `063e5b8` (v0.7.6.2, AGPL-3.0-only,
arXiv 2605.04897), compared against our file-based auto-memory in `claude-infrastructure`.
34 candidates, each judged by three independent lenses: **efficacy** (does it work inside TM?),
**premise** (is our gap real, and do we already have it?) and **fit** (is it net-positive here?).
Labels: **MEASURED** = run or read this study; **CLAIMED** = paper, README or issue; **ESTIMATED** = method stated.
TM paths are relative to `/tmp/truememory-src`; ours are relative to the repo unless absolute.

**Revised the same day after a five-part gap pass** (`gap-1.md` … `gap-5.md`, summarised in §5.10-5.14):
Claude Code's own background memory writers (gap 1), a replay of the real misses (gap 2), uptake of
prose "search first" lines (gap 3), liveness of the new branches (gap 4), and the `sessions_fts`
deleter (gap 5). No candidate changes disposition class. Finding 1 is reframed, a fourth finding is
added, and the waves change. Nine items change conviction: #2, #4, #5, #6, #8, #9, #10, #11 and #26.
Most build-now items also gain acceptance criteria (cross-cutting X1-X5 in §2). One new rejection
(R18) and one new operator decision (the autoDream pin) are added.

---

## 1. Verdict

**Do not install, run or copy TrueMemory. Take four things from it:**
1. a lexical search index over the whole store;
2. its injection-hygiene and hook-delivery lessons;
3. its write-safety and concurrency patterns;
4. its issue tracker, used as a catalogue of how memory systems fail silently.

None of its distinctive "memory intelligence" survives measurement on our data: the encoding gate,
speech-act salience, the regex contradiction timeline, the surprise boost, trait profiles, and the
ML retrieval stack.

Four findings support this.

1. **Our binding problem is delivery at the moment of need, plus capture of operator rulings.
   Retrieval is the cheap substrate both need. TM delivers none of it to Claude Code.**
   (Revised by gaps 2-3. The first draft said "retrieval, not capture", which the real misses do not support.)
   - Main sessions consult a stored topic or lesson 2.0% of the time (5.6% of sessions with a typed prompt).
   - A prose "go search" line does not change that (MEASURED, gap 3). The resident "grep that file for
     the symptom" line was followed 0 of 54 times at a failing test (Wilson upper bound 6.6%).
     "Grep MEMORY.md first" was followed 2 of 64 times before a new topic file was written.
   - Replaying the 14 operator-voiced misses (MEASURED, gap 2):
     - pull retrieval over the right store fixes 2-3;
     - 6 were never stored, and 4 of those 6 are operator rulings stated in a session and never written down;
     - 4 were already in context or resident and were not obeyed.
   - Every lesson recurrence had its answer captured, and FTS5 ranks it 1-4 from the raw symptom
     text. Nothing issued the query. These are trigger misses, not retrieval misses.
   - The always-loaded index reaches the right file for at most 66% of queries (R@5 0.52).
   - Fielded SQLite FTS5 over the whole store reaches R@5 0.88 in about 3 ms, standard library only.
   - TM's own hybrid scores 0.96, but so does a 60-line FTS5+model2vec script. TM's reranked path
     costs about 23 s and 1.46 GB per query.
   - TM's session-start and per-prompt injection emits a top-level `additionalContext` that Claude Code drops
     (MEASURED-run on 2.1.114 and 2.1.280, §6).
   - **So the levers are push, not pull:** symptom recall on tool output (#6), the write-time
     neighbour advisory (#10), prompt recall or native prefetch (#23), and capture of rulings (#24, #26).
     The FTS5 index (#4) is their shared substrate, not the remedy on its own.
2. **TM's headline numbers do not measure its memory features.**
   - LoCoMo 93.0% equals the paper's own full-context oracle (92.99%).
   - The gate is disabled in every benchmark, and its AUCs have no data behind them (#280).
   - The benchmark path is not the product path (#455, #456, #451).
3. **The study found live defects in our own memory stack that matter more than any TM mechanism.**
   All MEASURED this session:
   - the session-index sweep has indexed nothing since 2026-09-07 (a BSD-awk `-v` newline bug; 191,067 log lines);
   - `sessions_fts` holds 40 of 9,422 sessions. **Cause found (gap 5):** a migration probe with no busy
     timeout reads "database is locked" as "column missing", and the migration heredoc, run without
     `-bail`, then executes `DROP TABLE sessions_fts`. The probe fails 2.6-3.1% of the time under contention.
     Errexit kills the caller before its log line, so nothing records it. It happened in July too;
   - SessionEnd records 11,666 of 11,670 sessions as "0 msgs", which starves harvest-skill-end's `MSGS>=12` gate;
   - six model-facing strings still say the situational rules file "loads by default" although
     `claudeMdExcludes` removes it on every account, and one of them tells the model to **delete**
     MEMORY.md bullets on that basis;
   - 4 of 5 account roots load `CLAUDE.slim.md` (about 93% of the last day's transcripts), but every
     planned instruction edit targets only `CLAUDE.global.md` (gap 4).
4. **Claude Code already ships two autonomous memory writers into our stores, and only a server flag
   keeps them off (gap 1, MEASURED-static in 2.1.114, 2.1.260, 2.1.278 and 2.1.280).**
   - `extractMemories` (post-turn) and `autoDream` (consolidation) fork with Edit/Write on any `.md` in
     the shared physical store, plus `rm -f` of `.md` files. `archive/` is not a protected directory.
   - The extraction prompt forbids verification ("no grepping… no git commands"). That contradicts our
     anti-capture rule.
   - A flip of `tengu_passport_quail` or `tengu_onyx_plover` reaches running sessions within about 6 h.
     If it happens, 13 of 37 stores, infra included, would dream on their first interactive turn.
   - autoDream can be pinned off with `autoDreamEnabled:false`. Extraction has no opt-out short of
     disabling auto-memory, which also stops MEMORY.md loading.
   - Nothing has fired: 0 `memory_saved` records in 2,442 transcripts, and no `.consolidate-lock` in any store.
   - Consequence: #11's history is the only undo, and #8 needs a sentinel for these flags.

**Prior study: none.** `grep -ril truememory` over the repo and `git log --all -S TrueMemory` both
return 0. Recording the rejections (§4) in `docs/plans/MEMORY_KNOWLEDGE_V2.md` stops the next session
from re-deriving them.

**Suggested order (revised after the gap pass).**
- **Wave A: correctness and safety, all independent.** #1, #2 (P0 now includes the DROP fix), #3
  (grown into the expected-fires registry that gates #6, #10 and #14), #8 (plus the native-pass
  sentinel) and #11 (moved up; the only undo for the native writers).
- **Wave B: the substrate and the push consumers, side by side.** #4 and #5 (#5 starts now on the 19
  real field queries), #6 with #7 as its acceptance criterion, and #10. #6 and #10 never depended on
  #4. They push at the two moments, failure time and write time, where the prose pull lines were
  measured not to bind. Their own uptake is unmeasured until #3's registry reads them. #26 starts here
  in shadow mode.
- **Wave C: the rest of build-now.** #9, #12, #13, #14 (its sweep block waits for #2).
- Build-later items follow their named dependency. The remaining experiments (#23, #24, #25, #27)
  start once #4 and #5 exist.
- **One new operator decision:** pin `autoDreamEnabled:false` in all 5 account `settings.json` files (§7).

---

## 2. Ranked adoption table

| # | Candidate | Disposition | Wave | Conv. | Size | Target files | Depends on |
|---|---|---|---|---|---|---|---|
| 1 | situational-truth-and-delivery-contract | build-now | A | 80 | S | hooks/lib/rules-loaded.sh (new); hooks/memory-index-drain.sh:249-290; bin/cc-memory-rotate:25-41,516-528; hooks/memory-nudge.sh:531-560; hooks/lib/memory-index-budget.sh:348; tests/hook-output-contract.bats (new); docs/plans/MEMORY_KNOWLEDGE_V2.md §4 R7 | — |
| 2 | session-index-coverage | build-now | A | **85** (was 82) | S | hooks/lib/session-index-helpers.sh:**228-271**,783-800,961,1127-1134; hooks/session-index-sweep.sh:188,215-262; tests/session-index-sweep.bats; **port of the init_db fix to** claude-session-search/hooks/lib/session-index-helpers.sh:116-157 | — |
| 3 | memory-hook-heartbeats → expected-fires registry | build-now | A | 78 | **S-M** (was S) | hooks/harvest-skill-end.sh:12,41-47; hooks/session-index-end.sh:56-109; hooks/memory-nudge.sh:46-47,493-502; scripts/idl-abstain-alarm.sh:26,128-157; **scripts/idl-expected-fires.tsv (new)**; tests/harvest-skill-end.bats, tests/idl-abstain-alarm.bats | — (gates #6, #10, #14) |
| 4 | derived-fts5-memory-search (**substrate**) | build-now | B | **70** (was 78) | S-M | bin/cc-memory-search (new); tests/cc-memory-search.bats (new); CLAUDE.global.md:103 **+ CLAUDE.global.slim.md:47** + live copies; commands/compact-memory.md:325-329 | — |
| 5 | memory-eval-harness | build-now | B | **78** (was 75) | S | docs/research/memory-eval/recall_eval.py (new); tests/memory-recall-eval.bats (new) + public synthetic fixture; ~/.claude/autonomy/memory-eval/ (private gold, **seeded from gap2/field-queries.json**) | #4 (retriever arm only) |
| 6 | symptom-to-lesson-tool-hook | build-now | B | **70** (was 72) | S | bin/cc-bats:643; scripts/ship-land.sh:1444-1451,2548; scripts/deploy-live.sh (core.bare text); hooks/bash-output-offload.sh; hooks/log-bash.sh; hooks/lib/lesson-symptoms.tsv (new, **resolved via dereferenced self-path**); scripts/idl-abstain-alarm.sh:128 (BLIND vocabulary); tests (new) | delivery probe; #3 |
| 7 | injection-sanitizer | build-now | B (with #6) | 74 | XS | hooks/lib/inject-sanitize.jq (new, **dereferenced path or inlined def**); tests inside the first recall hook's suite | first recall hook (#6/#23) |
| 8 | delivered-surface-reach-audit **+ native-pass sentinel** | build-now | A | **76** (was 74) | S | scripts/memory-fleet-sweep.sh (`--reach`, `NATIVE` rows); tests/memory-fleet-sweep.bats | #1 |
| 9 | visible-cold-tier-pointer | build-now | C | **68** (was 74) | S | bin/cc-memory-rotate:1237-1249,1290,1566-1577; tests/cc-memory-rotate.bats:199-210; commands/compact-memory.md:825-828; .claude/rules/agent-operating-lessons.md:33 | — |
| 10 | whole-store-neighbour-advisory | build-now | B | **73** (was 75) | S | hooks/lib/memory_neighbours.py (new); hooks/backup-before-write.sh:82-83 branch **and :248 tense**; CLAUDE.global.md:103-104 **+ CLAUDE.global.slim.md:47**; hooks/memory-nudge.sh:560; tests (new) | #3 |
| 11 | local-store-history | build-now | **A** (was C) | **77** (was 73) | S | scripts/memory-store-snapshot.sh (new); bin/cc-memory-rotate (mutation branches); **a SessionStart or nightly snapshot trigger**; commands/compact-memory.md; scripts/memory-fleet-sweep.sh; tests (new) | — |
| 12 | structured-supersession | build-now | C | 72 | XS | CLAUDE.global.md:108-109 **+ CLAUDE.global.slim.md**; hooks/memory-nudge.sh:560; commands/compact-memory.md steps 4 and 7 | — |
| 13 | forget-cascade-and-link-integrity (link lint only) | build-now | C | 72 | S | scripts/rules-hook-budget-lint.sh:107-203; .claude/rules/agent-operating-lessons-situational.md (header line); compact-memory orphan sweep; bin/cc-memory-refs (optional, read-only) | — |
| 14 | transcript-normaliser | build-now | C | 70 | S | hooks/lib/transcript_norm.py (new); hooks/lib/session-index-helpers.sh:653-663,859-873; bin/cc-suggest-filter:232-292; tests/transcript-norm.bats (new) **+ a consumer-level test** | #3; #2 (sweep block only) |
| 15 | read-ledger | build-later | after #2 | 70 | S-M | bin/cc-memory-read-ledger (new); hooks/session-index-sweep.sh (hourly block); bin/cc-memory-rotate:103-107,1142-1160; scripts/growth-coverage.conf | #2 P0 (awk + DROP fixes) |
| 16 | consolidation-families-at-compaction | build-later | after #4, #10 | 66 | S | commands/compact-memory.md step 7b; bin/cc-memory-neighbours (shares #10's scorer) | #4, #10 |
| 17 | divergent-token-guard (as merge-losslessness rule) | build-later | with #16 | 62 | XS | commands/compact-memory.md:325-329; bin/cc-memory-dropped-token-audit:100-132 (`--pair`) | #16 |
| 18 | episodic-session-recall | build-later | after #2 | 60 | S | hooks/memory-nudge.sh (one cue line); uses existing claude-search | #2 P0 (awk + DROP fixes); **#2 also indexing `workflows/wf_*.json`** |
| 19 | rotor-lock-deadline-swap-hygiene | build-later | — | 62 | S | bin/cc-memory-rotate:114-115,342-350,381-391; hooks/memory-index-drain.sh:273-321; tests/cc-memory-rotate.bats:453 | — |
| 20 | frontmatter-validator-env-clamp | build-later | — | 60 | S | scripts/memory-fleet-sweep.sh (`--schema`); hooks/memory-nudge.sh:46-47 | — |
| 21 | claim-queue-primitives | build-later | — | 55 | XS now / M later | docs/plans/MEMORY_KNOWLEDGE_V2.md (spec); bin/cc-harvest-close (new, S) | an approved background worker |
| 22 | capture-decision-ledger (deny-only) | build-later | — | 52 | XS | hooks/backup-before-write.sh:117-134; commands/compact-memory.md:97-185 | — |
| 23 | userprompt-pointer-recall | experiment | after #4, #5 | 62 | M | hooks/memory-prompt-recall.sh (new, shadow mode); migration (operator-run) | #4, #5, #7 |
| 24 | candidate-extractor-worker | experiment | after #14 | 60 | M | bin/cc-memory-extract (new; `--dry-run` Stage 0 only, **re-targeted Stage-0 gold**) | #14 |
| 25 | transcript-capture-enqueue | experiment | after #24 | 58 | S | bin/cc-memory-capture-scan (new; dry-run verdicts only) | #24 passing Stage 0 |
| 26 | speech-act-nudge-trigger (**widened to ruling-shaped operator text**) | experiment | **B, shadow** (was "after #4/#5") | **60** (was 55) | S | hooks/memory-nudge.sh:50 (the existing jq call); tests/memory-nudge-budget.bats | — |
| 27 | provenance-and-verification-tier (prose receipt) | experiment | after #4, #5 | 55 | XS | CLAUDE.global.md:101-104 **+ CLAUDE.global.slim.md**; hooks/memory-nudge.sh:560; commands/compact-memory.md | — |
| 28 | dna-numeric-encoding-gate | reject | — | 90 | S (doc) | MEMORY_KNOWLEDGE_V2 §8 R11 | — |
| 29 | dna-install-copy-truememory | reject | — | 88 | S (doc) | MEMORY_KNOWLEDGE_V2 §8 R15 + file-header convention | — |
| 30 | dna-regex-contradiction-inplace-update | reject | — | 87 | S (doc) | MEMORY_KNOWLEDGE_V2 §8 R13; pointer beside bin/cc-memory-rotate:93-102 | — |
| 31 | dna-heavy-retrieval-stack | reject | — | 85 | S (doc) | MEMORY_KNOWLEDGE_V2 §8 R14 | — |
| 32 | dna-auto-store-paths | reject | — | 85 | S (doc) | MEMORY_KNOWLEDGE_V2 §8 R12 | — |
| 33 | brief-time-recall-for-dispatched-and-subagents | reject | — | 80 | — | (salvage: agents/workflow-lean.md:27-28 if ever evidenced) | — |
| 34 | resident-tier-demotion-with-recall | reject | — | 80 | — | already shipped (cb5f7109c + migration 0036); residue lives in #1 and #6 | — |

`#` is a stable ID used throughout this document and the gap notes. Rows keep their original rank
order, and the Wave column gives the build order after the gap pass. Bold marks a gap-pass change.
Conviction is the synthesised conviction in the stated disposition. For a reject it is conviction
in the rejection. Where lenses disagreed, the refined design below resolves the disagreement and
the conviction reflects what remains uncertain.

**Cross-cutting acceptance criteria for every new hook branch or lib (gap 4).** Items #6, #7, #10
and #14 each sit behind a fail-open construct that makes "broken" and "healthy, nothing matched"
look the same. So each must:
- **X1.** Resolve its lib through a dereferenced self-path (`hooks/backup-before-write.sh:107-119`),
  never through `~/.claude/hooks/lib`. `install.sh:340` links only `*.sh` and `*.py`, so a new `.tsv`
  or `.jq` is never linked live. `scripts/deploy-parity-assert.sh:551-552` does not repair a new `.py`.
  A bats case runs the hook through a symlink in a temp dir.
- **X2.** Log under its own IDL name (e.g. `bash-output-offload:lesson`), so the host hook's other rows
  cannot mask a dead branch.
- **X3.** Add its could-not-observe reasons to the BLIND list in `scripts/idl-abstain-alarm.sh:128` in
  the same commit. New reasons default to DORMANT (`:26`) and would read green.
- **X4.** Write state to `$HOME/.claude/state`, not `$CFG/state`, which is 4 physical directories. The
  main root holds about 7% of the last day's transcripts.
- **X5.** Take its expected-fire denominator from a source the branch does not write (#3's registry).
- Test the **rendered** hook JSON, including `jq -s length == 1` where a hook already emits
  `updatedInput` or `updatedToolOutput`.

---

## 3. Per-adoption sections

### 3.1 situational-truth-and-delivery-contract (build-now, 80, S)
- **TM mechanism (a counter-example).** TM's context hooks print a top-level `{"additionalContext":…}`
  (`truememory/ingest/hooks/session_start.py:751-753`; `user_prompt_submit.py:830-831`). The CC
  2.1.278 binary logs "Hook JSON output had unrecognized keys (ignored)" for that shape
  (`/tmp/tm-research/_cc_strings.txt:191692-191693`; static read, not a live run). TM's test checks
  the producer shape only (`tests/ingest/test_onboarding.py:61`). Its MCP instructions run 4,865
  chars against a 2,048-char host cap. The lesson is that TM tested the producer and never the consumer.
- **Our gap (MEASURED).**
  - `claudeMdExcludes = ["**/.claude/rules/agent-operating-lessons-situational.md"]` is set on all 5
    roots (migration 0036).
  - "loads by default" still appears at `bin/cc-memory-rotate:29,522`, `hooks/memory-nudge.sh:537,560`,
    `hooks/memory-index-drain.sh:249,275,284` and `hooks/lib/memory-index-budget.sh:348`. The last one
    was missed by the candidate brief.
  - `memory-index-drain.sh:284` tells the model to DELETE the MEMORY.md bullet because the rules
    file "loads by default".
  - 127/144 lesson bodies and 68 topic files are reachable only through the excluded file.
  - 10 of 11 sessions after 09-25 did not load it.
- **Design.**
  - Add `hooks/lib/rules-loaded.sh` (about 20 lines). `rules_file_loads <abs-path>` does one jq read
    of the single shared `~/.claude/settings.json` (all roots link to it since 0037) and matches with
    `[[ $p == $g ]]`. If it cannot tell, it fails open to "unknown", never to "loads".
  - Drain already-cited branch (`:278-285`): recommend DELETE only if the citing file loads. Otherwise
    keep the bullet as the only resident pointer, or promote it under `RULES_RESIDENT_ADD_OK`.
  - Compute the wording at all six sites. The per-prompt nudge states it conditionally, so it pays for no jq.
  - **Do not** change routing to COLD. COLD had 1 main-session read in 30 days, and the 09-23 routing
    ruling plus the still-open 0036 decision (`docs/research/token-efficiency-2026-09-23/REPORT.md:66-68`)
    belong to the operator.
  - Add a static lint, `tests/hook-output-contract.bats`, with two checks. (a) Any line that builds
    `additionalContext` sits under `hookSpecificOutput`. (b) No hook or bin string pairs an excluded
    path with "loads by default". Add ≤10,000-char assertions to the existing nudge, drain and budget suites.
  - Correct MEMORY_KNOWLEDGE_V2 §4 R7. PostToolUse `additionalContext` does reach the model
    (`hooks/memory-index-drain.sh:341`).
- **Cost.** About 150-200 lines. About 7 ms of jq, on drain, budget and rotor paths only; 0 ms per prompt.
- **Lenses.**
  - Efficacy adapt 72: TM supplies only the counter-example.
  - Premise adapt 80: drop the COLD default, shrink the glob matcher, add the missed :348 site.
  - Fit adapt 78: a static lint is enough, and running every registered hook on fixtures is not worth it.
- **Gap pass.**
  - **A second silent delivery lever (gap 1).** `tengu_sepia_cormorant` together with
    `tengu_umber_petrel` is a per-model kill switch that turns auto-memory off. It stops MEMORY.md
    loading, and no setting overrides it. It is off in all six caches today.
  - `rules_file_loads` only ever answers about `claudeMdExcludes`. The contract's "what actually loads"
    question therefore also needs #8's `killswitch=` field.
  - **The static lint gains one check (gap 4).** Any hook that emits `hookSpecificOutput` must set
    `hookEventName` from the payload's `hook_event_name`, not hard-code it, whenever it is registered for
    more than one event. `log-bash.sh` is registered for both PostToolUse and PostToolUseFailure, and CC
    throws or drops a mismatched name.

### 3.2 session-index-coverage (build-now, 85, S; was 82)
- **TM mechanism.** A stale-session scanner with a non-blocking flock, a held watermark and
  prune-before-early-return (`session_start.py:455-624`; #694; M-37). Its roots are hardcoded
  (`ingest/hooks/_shared.py:34-45`; `session_start.py:517`) and accepted 0 of 40 of our transcript
  paths. TM's own #560 measured the full walk as cheap (0.1 s warm), so do not port its global-mtime
  watermark: it misses transcripts that move between roots with their mtime preserved.
- **Our gap (MEASURED, re-checked this session).**
  - `file_tracking` has 11 rows, and `max(last_swept_at)` is 2026-09-07T05:32:38Z.
  - `~/.claude/logs/sweep-daemon.log` holds 191,067 lines of "awk: newline in string".
  - Cause: `session_index_changed_files` (`hooks/lib/session-index-helpers.sh:783-800`, since `0ad853ab8`
    on 2026-07-29) passes the whole tracking table through `awk -v`. BSD awk rejects a multi-line value
    once there are 2 or more rows. The failure sits inside a process substitution, so `set -e` never sees it.
  - `tests/session-index-sweep.bats:86-123` never tracks more than 1 row.
  - `sessions_fts` holds 40 of 9,422 rows. The 08:15Z backfill rebuilt 9,351, and the table was emptied
    later. **The cause is now verified (gap 5, MEASURED on DB copies):**
    - **It was a `DROP`.** `sqlite_master` rowids 19-23 are gone and the table was re-created at
      rowids 27-32. The old root pages 20-24 are on the freelist. The data table is 17 pages; a
      replayed `DELETE` rebuild would leave about 10,600. That rules out `rebuild_fts`, backfill:635,
      `tag.py:1010-1014`, install.sh:220 and retention.
    - **The migration probe triggers it.** The probe `sqlite3 "$DB" "PRAGMA table_info(sessions);" 2>/dev/null | grep -c … || true`
      (`hooks/lib/session-index-helpers.sh:230,243,258`) has no busy timeout, and it reads any failure
      as "column missing". Under contention it returned 0 in 39/1500 and 46/1500 tries ("database is
      locked"); with `.timeout 5000`, 0/1500.
    - **The heredoc keeps going.** The migration heredoc runs without `-bail`. Its `ALTER` fails on the
      duplicate column and the `DROP TABLE IF EXISTS sessions_fts` still runs (shown with a non-DDL
      stand-in; a hook blocks DDL text).
    - **Errexit hides it.** Callers run under `set -euo pipefail` and die before the "Migrated" log line.
      That line last appeared in March.
    - **No lock covers it.** `init_db` runs outside the index lock on every SessionStart stub, every
      SessionEnd and every sweep tick.
    - **It recurs.** The 07-26 backup has the same fresh-table signature. The weekly backfill rebuild
      has been fighting the wipe since at least July.
    - **Caller (inferred, not proven).** Most likely the SessionStart stub of one of two parallel
      `claude -p` probe sessions at 19:01:32Z, at load about 180. The stale-lock reclaim at 19:01Z is
      not causal: `init_db` runs before any lock is taken.
  - SessionEnd and SessionStart already index 98.7% of transcripts across the 4 roots. About 56 are
    missing, roughly 18 a week. 636 non-primary rows are content-less stubs.
- **Design.**
  - **P0 (XS).** Pass the tracking table through `ENVIRON` or a temp file. Log `change detection FAILED
    rc=N` to `session-index.log`. Add a bats case with 2 or more tracked rows, which fails today.
  - **P0b, the DROP fix (XS-S; promoted from P1 after gap 5, because it is the root cause).**
    Apply it in **both** helper copies, ours (`:228-271`) and `claude-session-search/hooks/lib/session-index-helpers.sh:116-157`,
    which the backfill sources.
    - **Probe.** Go through `session_index_sql` (busy timeout) with
      `SELECT name FROM pragma_table_info('sessions')`. On rc≠0 or empty output, log
      `init_db probe failed rc=N` and **skip every migration**. `init_tracking` (`:1190-1196`) already uses this pattern.
    - **Migration.** Run it with `-bail` inside one `BEGIN IMMEDIATE … COMMIT`: ALTER, DROP, CREATE, then
      INSERT…SELECT to repopulate. Log **before** the DDL.
    - **Hot paths.** Gate them on `PRAGMA user_version`, or move migrations out of hooks and the sweep, so
      a probe that runs 1,500+ times a day cannot destroy data.
    - **Test.** A bats case with a locked or unreadable DB asserts that `sessions_fts` survives and a log
      line appears. `gap5/errexit_probe.sh` shows today's code fails that case.
  - **P1 (S).**
    - An hourly damped parity check of `fts_rows` against `sessions`. It is **alarm-first**: rebuild only
      after P0b lands, so it does not become a damper that hides a live deleter.
    - A **table-identity fingerprint** logged each sweep tick: the `rootpage` of `sessions_fts_data` and
      the sqlite_master rowid of `sessions_fts`. A change without a VACUUM means DROP+CREATE. This is the
      cheap detector. SQLite has no DDL triggers and none on virtual tables (DOC, not run), so a trigger
      cannot catch this deleter.
    - The `BEGIN IMMEDIATE` rebuild is now **optional hygiene**: it was never the cause.
    - The sibling-repo item changes from "trace the rebuild callers" to "port P0b" (above).
  - **P2 (S).** An hourly multi-root gap-fill over `SESSION_INDEX_PROJECT_ROOTS` (`helpers:961`),
    deduped by `pwd -P`. It indexes only files idle 30 minutes or more that lack a sessions row. It does
    not scan all 4 roots on every 60 s tick: MEASURED 6.5-8.7 s wall for that at load 146.
  - Verdict line: per-root counts, `fts_rows/sessions`, and the age of the newest `last_swept_at`.
- **Cost.** About 1.5 s of system CPU per hour. An 11-12 s rebuild only when drift is detected.
- **Lenses.** Efficacy adapt 72, premise adapt 82, fit adapt 80. **All three found the awk bug
  independently.** The candidate's "sweep sees 22%" was wrong: it sees 0%. Its "78% never indexed" was
  wrong too: 98.7% are indexed.
- **Gap pass.**
  - Conviction 82 → 85: both defects now have measured root causes and XS fixes.
  - #15 and #18 now depend on P0 plus P0b, not on the P1 self-heal, so they can start sooner.
  - If #18 is ever built, P2 must also index `*/workflows/wf_*.json`. The #106 answer lived only there
    (gap 2).
  - Flagged, not investigated: retention removes 727-1,888 `sessions` rows a week, and the backfill
    re-adds them (gap 5).

### 3.3 memory-hook-heartbeats → expected-fires registry (build-now, 78, S-M; was S)
- **TM mechanism (a counter-example).** TM's health payload (`mcp_server.py:920-968`, #592) reads only
  in-process globals. It reported "all healthy" while clustering was dead (#720). It never noticed
  SessionEnd staying silent for 6+ days (#722, still open, found by a user looking at empty logs).
  `record_encoding_gate_error` has no production caller. `model_server.status` outlives its writer
  (`model_server.py:941-945`). The transferable lesson: the hook logs itself on every exit path, and
  silence is measured against expected fires.
- **Our gap (MEASURED).**
  - harvest-skill-end has logged 20 rows ever: 11 in July, 8 in August, 1 in September.
  - Root cause, re-checked this session: SessionEnd index lines read "0 msgs" in 11,666 of 11,670
    cases. Harvest gates on `MSGS>=12` (`hooks/harvest-skill-end.sh:46`) read from that same row. The
    two hooks are separate SessionEnd groups, so the header's "Runs AFTER session-index-end" (`:12`) is
    doubtful.
  - `memory-nudge.sh:46-47` treats a garbage `MEMORY_NUDGE_INTERVAL` the same as the documented kill
    switch 0.
- **Design.**
  - Enroll harvest-skill-end in `hooks/lib/idl-log.sh` on **every** exit path, with BLIND and DORMANT
    vocabulary. A reading of `msgs==0` is `stale-telemetry` (BLIND), not "below gate".
  - The nudge logs decision turns only. The drain logs only when it acts.
  - `scripts/idl-abstain-alarm.sh` gains a **SILENT** class: a registered hook with fewer than NMIN rows
    while its denominator reaches D. The denominators are SessionEnd index lines and `nudge-*.count` files.
  - Fix harvest's input: count messages from `transcript_path`, or fix `session-index-end.sh:56-109`'s
    `MSG_COUNT`. Correct the header.
  - Separate the kill switch from garbage in the nudge (garbage falls back to 12).
  - Drop the proposed per-day log dirs, PID attribution (hooks are short-lived) and the `--hooks` sweep flag.
- **Cost.** About 15 ms, on SessionEnd only. Nightly alarm pass. No per-prompt cost.
- **Lenses.**
  - Efficacy adapt 72.
  - Premise adapt 78: found the 0-msgs root cause, and a no-fork printf is impossible on /bin/bash 3.2.57.
  - Fit adapt 80: reuse the IDL; a naive "below-gate" verdict would be classed DORMANT and hide the defect.
- **Gap pass (gap 4): generalise SILENT into a registry, and make it the gate for #6, #10 and #14.**
  The design above applies the lesson only to hooks that already exist. The new branches each sit
  behind a fail-open construct, and none names an independent denominator.
  - Replace the two hard-coded denominators with `scripts/idl-expected-fires.tsv`, one row per branch:
    `branch  denominator-fn  window  D_min  ratio_floor`. Seed rows:

    | branch | independent denominator | SILENT if | DEGRADED if |
    |---|---|---|---|
    | harvest-skill-end | SessionEnd index lines | rows < NMIN while D ≥ D_min | — |
    | memory-nudge | `nudge-*.count` summed over **all 4** state dirs | same | — |
    | backup-before-write:neighbours (#10) | new `memory/*.md` + `docs/lessons/*.md` by birthtime (fleet about 67/week) | D ≥ 10 and rows = 0 | rows/D < 0.5 |
    | bash-output-offload:lesson + log-bash:lesson (#6) | nightly replay of the same symptom table over the last 24 h of tool-result text in all 4 roots | expected ≥ 3 and delivered = 0 | rows/expected < 0.5 |
    | session-index:norm (#14) | "Indexed session" lines in session-index.log | `norm=lib` rows = 0 while D ≥ 5 | any `norm=fallback` row (BLIND) |
    | cc-memory-search (#4) | its commands in bash-execution.log(+.gz); new topic files; memory greps | D ≥ 50 and rows = 0 | tool rows < log invocations; any `Exit: 127` |

  - A denominator that cannot be computed prints `denominator: UNKNOWN (<why>)`. It is never omitted and
    never read as HEALTHY (the rule at `idl-abstain-alarm.sh:153-157`).
  - The selftest gets one RED and one UNKNOWN case per registry row.
  - **New concrete case (gap 5).** A hook that dies under errexit leaves no line at all. The bb889361
    SessionStart stub that never logged is an example. Session-index hooks need a row per invocation,
    written from a trap, so SILENT can see them.
  - Size S → S-M (ESTIMATED: about 60-100 extra lines and about 10 selftest cases).

### 3.4 derived-fts5-memory-search → `bin/cc-memory-search` (build-now as substrate, 70, S-M; was 78)
- **TM mechanism.**
  - FTS5 `porter unicode61` (`storage.py:47-69`).
  - A quoted-OR query builder that is injection-safe (`fts_search.py:31-39`).
  - RRF with k=60 (`hybrid.py:229-257`).
  - A score-space contract (#632; `ingest/dedup.py:169-176`; `client.py:186-192`).
  - The reranker is skipped on hook paths (#690, `c96dbcd`).
  - Defects to avoid: no stopword removal on the main path, which makes cost superlinear (#689: p95
    9.5 s at 10k memories), and min-max score normalisation, which makes scores impossible to threshold
    (`fts_search.py:48-73`).
- **Our gap (MEASURED).**
  - An audit of all 98 registered hooks found none that retrieves by relevance.
  - Consult rate is 2.0% of main sessions.
  - The always-loaded index gets R@5 0.52 and can reach the gold file for only 66% of queries. `rg` gets 0.64.
  - 192 of 496 topics cannot be reached from any delivered surface.
  - 98,167 chars of descriptions are never loaded.
- **Design.**
  - Python stdlib, written fresh.
  - **v1 builds no cache**: an in-memory FTS5 table per call.
  - Default scope: the current project store (realpath), the `- [` link lines of `archive/*COLD*.md`
    only (never PRE-COMPACT snapshots), `docs/lessons/*.md`, and both rules files with one row per hook line.
  - `--all` is opt-in and labels each hit with its store. A cross-store query put another project's
    memories in the top 5.
  - Columns: name + H1, description, body.
  - bm25 column weights are a **named constant chosen by #5**. 10/5/1 and 5/3/1 are both unproven.
  - Query: stopwords removed, at most 12 tokens, quoted-OR.
  - Output: pointer lines only, with the raw bm25 score tagged by its score space. Flags `--top`,
    `--json`, `--since` (`metadata.modified` is nested).
  - Reuse the tokenizer conventions of `hooks/lib/session-index-helpers.sh:221,295`.
  - Ship its consumers in the same change. A pull tool alone gets used about as rarely as Grep (2%
    consult), and gap 3 shows the prose consumers barely raise that (see "Gap pass" below):
    - `CLAUDE.global.md:103`, `CLAUDE.global.slim.md:47` and the live copies become
      "`cc-memory-search <terms>` first (falls back to grep MEMORY.md)". This is XS, but book no uptake for it;
    - compact-memory step 7 generates candidate pairs from it;
    - ~~resident rules `:33` points at it~~ dropped in the gap pass (0/218 uptake of that line).
  - Log invocations for #15.
  - Stage 2: potion+RRF only after #5 shows a gain on queries that are not agent-authored, never inside
    a hook, and never with a cross-encoder. Add a persistent cache only when a latency-bound consumer exists.
- **Cost.** About 250-350 LOC plus about 15 bats. Project scope: 0.11 s warm, 0.51 s cold, 24 MB,
  0.4 ms per query. `--all`: 1-4 s.
- **Lenses.**
  - Efficacy adapt 80: TM's FTS and RRF are load-bearing and never reverted.
  - Premise adapt 72: state the gain against `rg` (0.64 → 0.88), not 0.52; most of the lift comes from
    including the cold tier; the 150-165 ms rebuild figure is unsourced.
  - Fit adapt 80: no cache, no superseded ranking (0 adopters), `--all` opt-in.
- **Gap pass: re-scoped from "lead remedy" to "substrate". Conviction 78 → 70.**
  - **The prose consumers will not bind (gap 3, MEASURED).** The line this item rewrites,
    `CLAUDE.global.md:103`, was followed 2 of 64 times before a new topic file. The resident line 33 was
    followed 0 of 54 times at a failing test. `claude-search`, a pull CLI no instruction names, appears
    in 0.42% of sessions. `/compact-memory`, the second consumer, ran at most 12 times in 30 days.
    Expect 0-10% invocation from a prose line. Keep the XS rewording, but book no uptake for it. Drop the
    `.claude/rules/…:33` rewording, which gains nothing measurable.
  - **What it is for:** the shared index for #5, #10 (optional), #16, #23 and manual use. Conviction as
    lead remedy would be about 60, and about 72 as substrate. 70 reflects the second.
  - **Replay changes (gap 2, n=14):**
    - Search `type: feedback` topics **across all stores by default**. The Pyramid rule (#70), the
      run-this rule (#29) and the nearest rule to #58 all lived in another project's store.
    - Keep `--all` opt-in for project and reference topics. `--all` helped 3 cases and hurt 1 (#79, 4 → 6).
    - **No 12-term cap on a verbatim prompt**, or rank terms by rarity before capping. The cap dropped #78
      from rank 4 to 15.
    - #5 counts "retrieval reinforced a superseding memory" as a failure class. For #47 the top hit was
      the agent-written playbook that says "Replaces 'at least 4MB on Google Images'".
  - **Both instruction variants carry it (gap 4).** `CLAUDE.global.md:103` **and**
    `CLAUDE.global.slim.md:47`. Four of five roots link `CLAUDE.md` to `~/.claude/CLAUDE.slim.md`
    (MEASURED `ls -la`). A static check asserts the tool name appears in both.
  - **Liveness (gap 4).**
    - One log row per invocation, written in a `finally` block.
    - A parity check against the independent `bash-execution.log`. A surplus there means it crashed
      before logging, and `Exit: 127` means it is unreachable. Both page.
    - A nightly known-answer canary per active store: its newest topic `name` must come back in the top 5.
    - Report the zero-hit share. Above 50% (ESTIMATED threshold) means scope misresolution.
  - **30-day read.** If it is invoked in fewer than 5% of sessions that hit a failing test or write a
    new memory file, stop listing any prose line as a consumer.

### 3.5 memory-eval-harness (build-now, 78, S; was 75)
- **TM mechanism (a counter-example).**
  - The gate-eval tests skip 4 of 4 (`tests/test_gate_eval_harness.py:21-22`).
  - The sweeps are gitignored (`.gitignore:83-89,116-121`).
  - The judge prompt says "Be generous" (`benchmarks/locomo/scripts/bench_truememory_pro.py:94-103`).
  - The benchmark path diverges from production (#451, #456).
- **Our gap.** No instrument measures recall or capture. The only assets are in `/tmp`:
  `tm-empirical/queries.json` (50 queries), `harness/{common,baselines}.py` and `relearning-hits.tsv`.
- **Design.**
  - `docs/research/memory-eval/recall_eval.py`, a port of our own `/tmp` harness using stdlib FTS5.
    It scores exact gold-path matches (R@1, R@5, MRR by query style, Wilson intervals). A `gold-missing`
    class is reported separately and never counted as a miss.
  - Arms:
    - **loaded-only**: what the loader actually injects after truncation;
    - **load-everything**: FTS over the store and lessons;
    - any shipped retriever, **invoked exactly as its hook invokes it**. That is the lesson of TM #451/#456.
  - A committed synthetic public fixture (about 8-10 fake files and queries, with exact asserted
    metrics) so `tests/memory-recall-eval.bats` never skips.
  - Private gold lives in `~/.claude/autonomy/memory-eval/`. When it is absent the harness prints a loud NOT-RUN.
  - Add about 11-30 **field** queries lifted verbatim from `relearning-hits.tsv` evidence, tagged
    separately from the 50 agent-authored ones. Keep a sealed holdout of about 20 queries.
  - A frozen corpus snapshot plus a sha manifest.
  - Port `an3.py` as a field recurrence counter.
  - **Defer** `capture_eval`, which has no extractor to score. **Drop** per-change f3 arms. The IFS arm
    already ran at ceiling (40/40 in both arms, `docs/research/token-efficiency-2026-09-23/eval/GATE.md:525-541`),
    and each run costs $0.5-0.8.
- **Cost.** About 150 LOC plus bats. Under 1 s per run.
- **Lenses.** Efficacy adapt 74, premise adapt 72, fit adapt 80.
- **Gap pass: starts now, not after #4. Conviction 75 → 78.**
  - The field set it wanted now exists: `gap2/field-queries.json`. It holds 19 real queries: 13
    operator-verbatim prompts plus 6 recurrence symptoms. Each has time-valid gold (born before the
    miss) and a `gold-missing` label on 5. This answers the §5.1 threat that one author wrote both
    queries and gold.
  - The retriever arm is the only part that waits for #4.
  - Add three outcome classes beside hit and miss:
    - `gold-missing` (never stored, so it is a capture failure, not a retrieval failure);
    - `in-context-not-obeyed`;
    - `reinforced-superseding-memory` (#47).
  - Limit: weight tuning (10-5-1 vs 5-3-1) cannot be settled on this set, because only 5 of 13 operator
    items have time-valid gold at the default scope.
  - Also score prose-line uptake per #4's 30-day read. The operator-run A/B in `gap3/ab/` is the
    controlled version (§5.12).

### 3.6 symptom-to-lesson recall at the emitters and on tool output (build-now, 70, S; was 72)
- **TM mechanism.** None on tool output: `grep PostToolUse` over the TM tree returns 0, and its hooks
  are `ingest/cli.py:853-856`. Borrowed discipline only: pointer payloads under a budget
  (`session_start.py:862-923`) and debounce (`_shared.py:466-491`). Neither is proven, because TM's CC
  delivery is broken. The #288 figure of 17/50 was measured on an older regex.
- **Our gap (MEASURED).**
  - Re-learning census: 251 sessions hit a lesson's symptom after the lesson existed. In 71% of them
    the lesson was resident; only 4% had opened it.
  - But 154 of those 251 hits are strings **our own tools print, which already state the lesson**:
    `bin/cc-bats:643` (DEFERRAL) and `scripts/ship-land.sh:2548` (UNGATED).
  - Hand-confirmed recurrences number about 8-12 in 30 days.
  - The live one is `timeout N … ship-land.sh`: command hits continued through 09-25, including 8 on
    09-21 and 7 on 09-22. No guard exists.
  - core.bare is fading: it self-heals via `deploy-live.sh:1672-1724` since `e99dcdf82`.
  - The IFS pattern is already land-gated by `tsv-pad-lint`.
- **Design (cheapest variant).**
  1. **Emitter pointers.** Append the lesson's absolute body path at `bin/cc-bats:643`,
     `scripts/ship-land.sh:2548,1449-1451` and the core.bare diagnostics in `deploy-live.sh`.
  2. **Deterministic prevention.** Hoist ship-land's ancestry walk (`:1444-1448`) into a start-of-run
     preflight. If `timeout`/`gtimeout` is an ancestor, refuse with rc 2 and the lesson path. Override
     with `SHIP_ALLOW_OUTER_TIMEOUT=1`. Do not build an advisory PreToolUse arm: the docs say PreToolUse
     `additionalContext` arrives with the tool result (`_cc_hooks.md:1003`), so it cannot prevent anything.
  3. **An output arm for foreign emitters only** (git, bash, shellcheck, bats), folded into hooks that
     are already registered:
     - `bash-output-offload.sh`: an in-process scan of the head and tail 32 KB, placed before its size
       early-exit, against a static `hooks/lib/lesson-symptoms.tsv` (at most 15 rows, literals of 12+
       chars; slugs may point at docs/lessons or memory topic files).
     - `log-bash.sh`: scan the `.error` text on PostToolUseFailure only.
     - Seed rule: a literal that `git grep` finds in our own emitters is refused.
     - Emit `hookSpecificOutput.additionalContext` as a factual line, at most 600 chars per pointer and
       1,500 per call.
     - Dedup per (session_id, agent_id or main, slug). Kill switch `CC_LESSON_RECALL=off`.
     - Append each hit to `~/.claude/state/lesson-hits.jsonl`.
  4. **Probe first**: a nonce through PostToolUse and PostToolUseFailure `additionalContext` must reach
     the model in a main session, a subagent and `-p`.
  5. **Holdout**: suppress 20% of slugs by hash for 2 weeks. Measure Read-within-5-calls and re-fire.
  - Defer the `symptoms:` frontmatter, the compile cache and the c10 migration until the table exceeds 15 rows.
- **Cost.** About 150 LOC plus bats. Under 1 ms on typical output and about 5 ms on 71 KB (in-process
  Python, against 96 ms for a standalone bash+grep hook). No new registration. The Bash volume is 12,718
  calls a day.
- **Lenses.** Efficacy adapt 68, premise adapt 72, fit adapt 78. They agree on the shrink. The
  candidate's 251-session headline is replaced by about 8-12 real recurrences plus measured cross-scope misses.
- **Gap pass.**
  - **Premise reinforced (gap 2).** Every replayed recurrence had its gold captured, and fielded FTS5
    ranks it 1-4 from the raw symptom or command text. The gold hook line ranks 1 of 122-130 lines for
    never-wrap-ship and never-write-tracked. The gap is purely the trigger, and only this item supplies one.
  - **Moved into Wave B beside #4 (gap 3).** It never depended on #4.
  - **Conviction 72 → 70 (gap 4), because of new delivery risks:**
    - `log-bash.sh` serves both PostToolUse and PostToolUseFailure. CC throws or drops a mismatched
      `hookEventName` (`_cc_strings.txt:195712,294055`, static).
    - PostToolUseFailure `additionalContext` has 0 live uses today (266 PreToolUse and 94 PostToolUse
      attachments sampled, 0 failure ones), so it is an untested channel.
    - `bash-output-offload.sh` wraps everything in one `except Exception: sys.exit(0)` (`:26-29,70-74`).
      An exception in a scan placed before its size early-exit would silently kill the existing offload too.
  - **Acceptance criteria added (gap 4):**
    1. **Isolation.** The scan runs in its own `try`. On exception it writes one `failed` row and
       continues to the unchanged offload. A bats case forces an unreadable table and asserts the offload
       JSON is byte-identical.
    2. **One JSON object.** When offload and pointer both fire, the single `hookSpecificOutput` carries
       `updatedToolOutput` **and** `additionalContext` (`jq -s length == 1`). The day-0 probe must also
       cover this combined case.
    3. **Event-name echo.** log-bash emits the payload's own `hook_event_name`. Rendered-output bats run
       on captured real payloads for both events.
    4. **Table positive control.** Each evaluation logs `rows_loaded`, and 0 is the BLIND reason
       `no-symptom-table`. A nightly canary pipes a canary literal through the **deployed**
       `~/.claude/hooks/bash-output-offload.sh` and asserts a pointer.
    5. **Recurring delivery check.** Every hit row records `tool_use_id`. The nightly replay joins each
       row to a `hook_additional_context` attachment with the same `toolUseID` and reports
       `delivered/emitted`. Below 0.9 pages. This replaces the one-time probe as the standing check,
       since delivery changes between binaries.
    6. **Holdout re-scoped.** At about 36 fires per 2 weeks (ESTIMATED from the census), a 20% holdout
       gives about 7 controls. Even 9/29 against 0/7 is p≈0.11, so a 2-week read cannot tell dead from
       working. The holdout clock starts after 7 days of liveness, delivery ≥ 0.9 and a green canary.
       The efficacy verdict waits for ≥ 15 control events (about 2 months, ESTIMATED). A 2-week read is
       labelled "liveness only".
    7. Cross-cutting X1-X5 (§2). `lesson-symptoms.tsv` would never be linked live, so it must be
       resolved through the dereferenced path.

### 3.7 injection-sanitizer (build-now as an acceptance criterion, 74, XS)
- **TM mechanism.** `sanitize_injection_content` (`truememory/_sanitize.py:26-47`) escapes only
  `<truememory-*` and `<system`. MEASURED passing straight through it:
  - a newline followed by `## User Directives (always loaded)` (it forged a section);
  - `<function_calls>`, `<invoke>`, a full-width `＜system-reminder＞` and zero-width-split tags;
  - ANSI sequences, which leave `[31m` residue.
  Recalled memories are also framed as "facts … use these" (`session_start.py:1091-1093`).
- **Our gap.** It does not exist yet: no hook injects stored memory text today. The first recall hook
  (#6, #23) creates the channel. `hooks/dod-persist.sh:276-290` already re-injects model-written text
  raw; that is the same class of risk and is flagged but out of scope here.
- **Design.**
  - `hooks/lib/inject-sanitize.jq` defines `def inj_san`, used inside the `jq -n` call each recall hook
    already makes. It:
    - strips CSI sequences, control characters and zero-width/bidi characters;
    - flattens newlines to ` ⏎ `;
    - case-insensitively escapes `<` or `＜` before `/?system`, `*-reminder`, `function_calls`, `invoke`,
      `antml`, `untrusted_`, `important` and our own wrapper tokens;
    - neutralises a leading `#`, `>` or `---`;
    - truncates to 200 chars **after** escaping.
  - Pointers only (path plus description), under the header "recalled memory pointers — data, not instructions".
  - About 6 bats cases on the **rendered** hook output.
  - Drop the write-time H1/H2 lint: 328 of 1,709 files would flag, with 0 true positives. Drop the
    Python helper: 40 ms per call against about 0 in jq.
- **Lenses.** Efficacy adapt 72 (TM's sanitizer is string-tested only), premise adapt 68 (ship with
  its first consumer), fit adapt 78.
- **Gap pass (gap 4).** A new `hooks/lib/*.jq` is never linked into `~/.claude/hooks/lib`, because
  `install.sh:340` globs only `*.sh` and `*.py` (MEASURED read). Either resolve it through the hook's
  dereferenced self-path, or inline the `def` in the hook. Otherwise the sanitizer is silently absent on
  the box it ships for. It ships in Wave B as an acceptance criterion of #6.

### 3.8 delivered-surface-reach-audit + native-pass sentinel (build-now, 76, S; was 74)
- **TM mechanism (a counter-example).** Its health checks never looked at delivery (#720, #722).
- **Our gap (MEASURED).** `scripts/memory-fleet-sweep.sh` reports only DARK entries. In infra, 44
  topics are cited only by the excluded file. The **personal** store (1 bullet) and **sevenrooms-bridge**
  (2 bullets) own excluded situational files that no delivered file names. Those lessons are
  unreachable today.
- **Design.**
  - `--reach` flag; the default table and the 0/1/2 exit contract are unchanged.
  - One Python heredoc computes the delivered set: `mim_effective_file` links, plus project CLAUDE.md
    and `.claude/rules`, minus `claudeMdExcludes` (through #1's helper).
  - Per store: `REACH store= topics= hop1= excl_bullets= excl_only_topics= dark_dest=`.
  - A final `REACH-VERDICT dark_dest=N` line is the one token to alarm on: 2 today, 0 after #1.
  - Row 10 owns the board row (plan R5).
  - Drop the transitive-closure percentages, superseded-hot (always 0), and a second orphan count,
    which would give two orphan instruments that disagree (31 against 11).
- **Lenses.** Efficacy adapt 62, premise adapt 72, fit adapt 78.
- **Gap pass: add a native-pass sentinel (gap 1; XS on top, conviction 74 → 76).** It is the only
  detector for a server flip that turns on Claude Code's own writers in our stores. It belongs here, not
  in #3, because #3's SILENT class measures absence and this measures presence.
  - **Flags.** Per `.claude.json` cache (there are **six**, not five), emit
    `NATIVE root=… quail= slate= onyx_enabled= onyx_available= moth= stone= linen= haze= killswitch=`.
    Emit it from `cachedGrowthBookFeatures`; today every value is off.
    - `killswitch` is `tengu_sepia_cormorant` matching the model id **and** `tengu_umber_petrel`. It
      silently stops MEMORY.md loading and outranks `autoMemoryEnabled`. It belongs to #1's delivery
      contract.
    - `stone` (`tengu_stone_shell`) changes the index model: pinned topic files load alongside
      MEMORY.md. That breaks the 25k-budget math and the rotor's premise.
  - **Per store.** Emit `consolidate_lock= team_dir= logs_dir=`. `.consolidate-lock` stays on disk
    permanently after a first dream. Today all 37 stores read 0.
  - **Transcripts.** Emit `memory_saved_records=<count since last run>`. Today it is 0 in 2,442
    transcripts. The control query matched 250 files, so these records do persist.
  - **Alarm** on any non-default value. The alarm row belongs to row 10 (plan R5).

### 3.9 visible-cold-tier-pointer (build-now, 68, S; was 74)
- **TM mechanism.** "(N of M directives shown — use truememory_directives…)" (`session_start.py:985-1004`).
  Its byte-truncation branch drops both the count and the route. MEASURED: 30 × 400-char directives
  showed 9 of them, dropped the newest 21, and left a bare marker.
- **Our gap (MEASURED).**
  - The only pointer to COLD is a column-0 comment, which the loader strips
    (`mim_effective_file | grep -c cold` = 0).
  - Its count is stale: it says 171 against 285 bullets.
  - The rotor's `HAVE_PTR` grep (`bin/cc-memory-rotate:1240`) matches the hand-written comment, so it is never refreshed.
  - It breaks the PROTECTED rule at `commands/compact-memory.md:825-828`.
  - COLD had 1 main-session read in 30 days.
- **Design.**
  - A rotor-owned visible line after the H1. It must not start with `- [`, so it is never an entry. It
    uses a relative path and names no tool:
    `- Not loaded: <N> demoted rules, listed in archive/MEMORY_ARCHIVE_<Y>-H<h>-COLD.md; their topic files stay in this dir. Grep here before concluding a rule is absent.`
    That is 164 units at N=285.
  - N is recomputed with `grep -c '^- '` at each rotation, and the line is replaced in place by its prefix.
  - Charge its units in the projection. Retire `PTR_LINE` (`:1237-1249,1566-1577`).
  - Rewrite `tests/cc-memory-rotate.bats:199-210`: the line is present, costs at most 200 units, and N
    equals the COLD count.
  - For the situational half, amend resident rules `:33` rather than adding a second line.
  - Switch the line to `cc-memory-search` once #4 ships.
  - Measure archive touches over 14 days before and after.
- **Cost.** About 1 displaced entry. Expect one normal rotation, since headroom is 51 units.
- **Lenses.** Efficacy adapt 58 (TM gives no evidence the pointer is followed), premise adapt 82, fit adapt 78.
- **Gap pass (gap 3): conviction 74 → 68, moved to Wave C.**
  - "Grep here before concluding a rule is absent" is itself a prose pull line. The two analogous
    lines measured 0/54 and 2/64, so expect about 0-5% uptake.
  - Its value is **truthfulness**: a correct count, a correct path, and restoring the PROTECTED
    discoverability rule. Recall is not the benefit.
  - It stays build-now because it is cheap and fixes a stale, stripped pointer. Book no recall gain
    unless the `gap3/ab/` A/B shows that a named pointer is followed.

### 3.10 whole-store-neighbour-advisory (build-now, 73, S; was 75)
- **TM mechanism.**
  - Vector candidate plus arbitration (`ingest/dedup.py:117-245`).
  - gzip novelty (`ingest/encoding_gate.py:337-423`). Its CLAIMED AUC of 0.788 measures signal against
    noise, not duplicates (#107), and is flagged unverifiable (#280). The score is length-confounded,
    and the branch at `:407` is dead.
- **Our gap (MEASURED).**
  - "grep MEMORY.md first" (`CLAUDE.global.md:103`) sees 29.8% of infra topics and 12.1% of reso topics.
  - Real duplicate pairs:
    - nohup (09-27 hot / 08-11 cold-only) and pipefail (09-11 / 08-09 cold-only), where the twin is invisible to the rule;
    - vitest, where both copies are hot and the rule was simply not followed;
    - a 71 s abandoned draft;
    - 3 newly found pairs (predicate error/refusal, describe-alarms 06-30/08-22, solo-dev push-main).
  - What works: gzip novelty under 0.25 caught **0 of 3** real pairs (scores 0.55-0.88). IDF token
    overlap on name, description and first paragraph ranked the twin **first in 8 of 8** directions.
- **Design.**
  - `hooks/lib/memory_neighbours.py` (stdlib), called from a roughly 15-line branch in
    `hooks/backup-before-write.sh` placed **before** its non-existent-file fast exit (`:82-83`). Output
    goes through `_bbw_out`, so the canon `updatedInput` survives.
  - It fires on a Write to a **new** `memory/*.md` (not MEMORY.md, not `archive/`) or `docs/lessons/*.md`.
  - The pool is the same store plus lessons, reading only the first 1.5 KB of each file.
  - It always shows the top 2 neighbours in at most 400 chars: "Same rule → Edit that file and discard
    the new one; corrects it → superseded_by; different → ignore". There is no threshold.
  - Kill switch `CC_MEM_NEIGHBOURS=off`. Timeout 2 s. Log to `$CFG/state/mem-neighbours.jsonl`.
  - Reword `CLAUDE.global.md:103-104` and `memory-nudge.sh:560`, and ask sessions to create topic files
    with Write (the Bash door covers about 18% today).
  - v2, only if uptake shows: a dir-mtime arm in the drain, plus a one-time sweep of the 7 known pairs for compaction.
- **Cost.** 0.07-0.47 s, only when a new memory file is written. No settings edit and no pending activation.
- **Lenses.** Efficacy adapt 74, premise adapt 72, fit adapt 80. All three drop gzip and the absolute threshold.
- **Gap pass.**
  - **Moved into Wave B (gap 3).** It is the real write-time consumer that `CLAUDE.global.md:103` never
    was. That line had 2/64 compliance; the IDF scorer found the twin top-1 in 8 of 8 directions.
  - **Conviction 75 → 73 (gap 4).** The advice always arrives **after** the file exists. All 266 of 266
    sampled PreToolUse context attachments reached the model with the tool result.
  - "Discard the new one" needs an `rm` outside the repo. `hooks/rm-safe-allowlist.sh:8-12` never
    auto-allows that, so under `defaultMode: auto` it goes to the classifier or a prompt. Nothing in the
    design observes whether the duplicate gets deleted.
  - **Acceptance criteria added:**
    1. **Every exit path logs, from the bash branch.** Rows are `fired`, `abstained:kill-switch`,
       `abstained:empty-pool`, `abstained:neighbour-lib-missing` (BLIND), `failed:timeout` and
       `failed:rc=N`. Each carries `tool_use_id` and the top-2 paths. They go to
       `$HOME/.claude/state/mem-neighbours.jsonl` (X4), not `$CFG/state`.
    2. **Rendered-output bats.** A Write to a symlinked-spelling new path yields exactly one JSON object
       carrying both `updatedInput` (the canon rewrite) and `additionalContext`. The EXIT trap
       (`:75-79`) would otherwise print a second object.
    3. **Post-hoc wording:** "You just created X; its nearest existing files are A, B. If X restates A,
       move anything new into A." Fix the same tense defect in the hook's own OVERWRITE GUARD (`:248`).
    4. **Outcome check, nightly, from `stat` and the rows.** Each fired case is classed `kept_distinct`,
       `merged`, `superseded` or `unresolved`. `unresolved` means a likely duplicate was left behind, and
       it is reported to compact-memory.
    5. **Friction probe.** Record whether `rm <abs memory path>` is auto-allowed, classified or prompted.
       If it prompts, reword the advice to "Edit A, and leave X for compact-memory's orphan sweep".
  - **Operator option, not adopted:** a deny-once variant (`permissionDecision: deny` with the neighbours
    as the reason, once per session and path). It makes the advice arrive **before** the write. The cost
    is about 55 extra round-trips a week fleet-wide (ESTIMATED) and a risk of suppressing capture. It
    becomes the treatment arm if item 4's `unresolved` share stays high.
  - Target list adds `CLAUDE.global.slim.md:47`.

### 3.11 local-store-history (build-now, Wave A, 77, S; was Wave C, 73)
- **TM mechanism (mostly a counter-example).**
  - A SQLite online backup, taken only before migrations and rotated at 3 (`storage.py:416-450`).
  - The tier-switch backup copies a WAL database with `shutil.copy2` (`tier_switch/manager.py:475-495`).
  - Dedup UPDATE overwrites in place (`storage.py:1150-1182`).
- **Our gap (MEASURED).**
  - None of the 39 physical stores is under git.
  - restic backs up only `archives/claude-code` (`~/.claude/scripts/restic-claude-archive-backup.sh:58`).
  - The Time Machine destination fails to mount (Code=18, AutoBackup=0, no local snapshots).
  - `backup-before-write` covers only Write overwrites, and 0 memory backups exist.
  - R2 (`MEMORY_KNOWLEDGE_V2.md:231-237`) cites this lack of undo.
- **Design.**
  - `scripts/memory-store-snapshot.sh <store> <reason>`.
  - The gitdir lives **outside** the store, at `$HOME/.local/state/cc-memory-history/<physical-slug>.git`.
    It is bare, never pushed, and the script refuses to run if a remote exists.
  - Commits are lock-free: a temp `GIT_INDEX_FILE`, then `write-tree`, `commit-tree`, and `update-ref`
    compare-and-swap. No commit is made when the tree is unchanged. The script always exits 0 with a `verdict=`.
  - It is called **before** each mutation, inside the actuator's own lock: the rotor's mutation branch,
    the drain actuator, and the compact-memory step.
  - memory-fleet-sweep reports each store's history age against its newest mtime.
  - About 12 bats cases: a stale-lock case, the CAS race, symlinked worktree stores mapping to one
    gitdir, config-mirror adopt, and snapshot failure never failing the rotor.
  - Frame it for the operator: it widens what counts as reversible, but it does not itself relax R2.
    R3 and R7 still gate capture separately.
- **Cost.** About 50-150 ms per mutation (ESTIMATED). Mutations are rare: 30 rotations in the busiest
  store. All stores total 12.5 MB.
- **Lenses.** Efficacy adapt 72, premise adapt 74 (the 1,461-line loss was a mailbox, not a memory
  store), fit adapt 75. Fit's external gitdir avoids collisions with the config-mirror rsync and `index.lock`.
- **Gap pass (gap 1): moved into Wave A, design amended, conviction 73 → 77.**
  - Claude Code's `extractMemories` and `autoDream` can Edit, Write and `rm -f` any `.md` in our stores,
    `archive/*-COLD.md` included. A server flag is all that keeps them off (Finding 4).
  - As designed, #11 snapshots only **before our own** actuators mutate. The native passes never call
    those actuators, so their writes would have no pre-image.
  - **Add a non-actuator trigger:** a snapshot at SessionStart (detached), plus one in the nightly fleet
    sweep. Call it from an already-registered SessionStart hook, so no new registration or operator-run
    migration is needed. Both are no-ops when the tree is unchanged (the CAS design), so the cost is about zero.
    Any in-session native write then has a pre-image at most one session old.
  - This is the **only undo for extraction**, which has no settings opt-out. It is also the undo for
    the dangling links the rotor already reports but cannot explain.
  - Whether our PreToolUse hooks (e.g. `backup-before-write`) fire on tool calls inside those background
    forks is **UNVERIFIED**. `rm` via Bash would not be backed up either way.

### 3.12 structured-supersession (build-now, 72, XS)
- **TM mechanism.** `fact_timeline` is a regex-derived table, rebuilt each time (`consolidation.py:782-865`).
  It was dead in the benchmarked build: its rows carried no `id`, so `engine.search` dropped them. It
  stayed dead until #482, #581 and #580, and #580 found it detected 1 of 7 phrasings.
- **Our gap (MEASURED).**
  - `superseded_by:` appears in 0 of 1,332 topic files, so the rotor's rank 0 (`cc-memory-rotate:87,1149`) is inert.
  - One real unmarked case: reso `MEMORY-ARCHIVE.md:885-888` supersedes a 5-file design-gate cluster
    whose files carry no marker.
- **Design.**
  - Add one clause to `CLAUDE.global.md:108-109` and the nudge: "a correction EDITS the file it
    corrects with a dated CORRECTED line; only when a new file wholly replaces an old one, write
    `superseded_by: <heir> (YYYY-MM-DD)` in the OLD file".
  - compact-memory step 7 "supersede" writes that key and repoints the index line to the heir.
  - A report-only check in step 4: dangling heir, cycle, key placed beyond line 12, index line pointing
    at a superseded file.
  - A human-gated backfill of the few known pairs.
  - Drop the required `supersedes:` and `valid_until:` fields, the Read redirect hook (8,644 Reads a
    week for about 0 events), and search ranking.
- **Lenses.** Efficacy adapt 68, premise adapt 72, fit adapt 78.
- **Gap pass.**
  - Target list adds `CLAUDE.global.slim.md` (gap 4). The rule text must land in both variants.
  - **A named case to add (gap 2, miss #47).** An agent-written research artifact superseded an
    **operator practice** without any operator ruling. `.claude/rules/bottle-reference-sourcing.md`
    opened with "Replaces: 'at least 4MB on Google Images'". Twelve hours later the operator asked for
    the practice "like normal", and retrieval would have surfaced the wrong rule at rank 1.
  - Add to the clause: a new entry that **replaces an operator-stated practice** needs the operator's
    ruling. It should carry "Replaces: <practice> — ruling pending" until the operator gives one.
    This is the only miss where more retrieval would have done harm.

### 3.13 link integrity (build-now, 72, S; the forget cascade itself is dropped)
- **TM mechanism (a counter-example).** The #685 cascade still leaks, MEASURED:
  - forgotten text survives in summaries (`structured_fact` rows with empty `message_ids`);
  - lowercase-written keys against raw-case deletes (`storage.py:1109-1140`).
  Its list-driven cascade drifted four times (#462, #500, #589, #685).
- **Our gap (MEASURED).**
  - 41 of 168 situational links resolve only from the store, because routing is verbatim (`cc-memory-rotate:1448`).
  - 36 distinct broken wikilinks, none caused by retirement: 4 are lesson slugs and about 6 are misspellings.
  - 10-11 genuine orphans.
  - There is no demand for a forget command: 0 of 2,650 prompts ask for one.
- **Design.**
  - A link-resolution arm in `scripts/rules-hook-budget-lint.sh`, at the land gate. It resolves each
    `](target)` relative to the file, then to the owning store, and flags only targets that resolve
    nowhere (0 of 168 today). It carries a selftest.
  - **Keep verbatim routing.** Rewriting links breaks the restore contract, the `grep -qxF` idempotency
    (`:593,:636`) and the already-cited veto (`:448`). Add one header sentence to the situational file
    instead: bare `x.md` links resolve in the store dir.
  - A report-only `[[slug]]` near-miss list (difflib) in the compact-memory orphan sweep.
  - Optionally, a read-only `bin/cc-memory-refs`.
  - Drop `cc-memory-forget --apply`, wikilink rewriting and the COLD re-pointer.
- **Lenses.** Efficacy adapt 78 (success must mean a whole-tree scan, not a list), premise adapt 78,
  fit adapt 78. Premise wanted absolute-path rewriting; fit showed it breaks the rotor's invariants.

### 3.14 transcript-normaliser (build-now, 70, S)
- **TM mechanism.** A structural unwrap (`ingest/transcript.py:158-276`) plus an echo strip (`:313-347`).
  The echo strip is inert on CC, because hook context lands in `attachment` entries that TM already
  drops. TM never reads isMeta, origin or promptSource (0 grep hits).
- **Our gap (MEASURED).** The session-index context text is contaminated: 78 of 122 selected messages
  (64%) were Stop-hook feedback, skill bodies or peer messages (`session-index-helpers.sh:653-663,859-873`).
  `bin/cc-suggest-filter:232-292` already holds a `typed_prompt()` predicate.
- **Design.**
  - `hooks/lib/transcript_norm.py`, about 60 lines, with two functions.
    - `is_operator`: `origin.kind==human` with text not starting `<`, then `promptSource` of typed or
      queued, then a fallback prefix list that merges cc-suggest-filter's prefixes with `<bash-input>`.
    - `iter_turns(path, offset)`: reads only user and assistant entries (dropping attachments makes the
      per-hook prefix constants unnecessary), skips tool_result-only turns, and truncates assistant text to 500 chars.
  - Move cc-suggest-filter's predicate into it, so there is one Python copy.
  - First consumer: the session-index Python blocks, with an inline fallback if the import fails.
  - Leave the jq presence classifiers alone; they are independent by design (`tests/interactive-parity.bats`).
  - Defer failing-Bash evidence snippets until a consumer exists. Note that the signal is
    `tool_result.is_error`; Bash results carry no exit-code field.
- **Lenses.** Efficacy adapt 70, premise adapt 68 (it needs a consumer), fit adapt 78 (the session
  index is that consumer).
- **Gap pass (gap 4): the planned fallback silently reverts the fix.** The inline fallback on a failed
  import is the old contaminated logic, and the planned tests cover only the producer lib.
  1. **Loud fallback.** Log `norm=lib` or `norm=fallback:<ExcType>` once per process, to
     session-index.log and as the IDL row `session-index:norm`. A fallback row is BLIND
     (`norm-import-failed`, X3). The fallback stays, because the index must not die.
  2. **Consumer bats.** Call `session_index_extract_context` (as `hooks/session-index-end.sh:114` does)
     on a captured real transcript containing Stop-hook feedback, a skill body, a peer message and one
     typed prompt, and assert only the typed prompt survives. Repeat with the lib unimportable and
     assert the fallback line.
  3. **Output metric.** Nightly: the share of `context_text` rows indexed in the last 24 h that carry
     non-operator markers. Baseline 64% (78/122). Accept at ≤ 10% (ESTIMATED threshold), and page on
     regression.
  4. **Sequencing.** `session_index_extract_all` (`helpers:816`) is fed by the dead sweep, so accept on
     the SessionEnd path until #2 P0 lands.
  5. The sibling repo's helper copy differs (`cmp`) and will not import the lib. Do not claim "one
     Python copy" across both repos.

### 3.15 read-ledger (build-later after #2, 70, S-M)
- **TM mechanism.** An opt-in instrumentation overlay: metadata only, 7-day retention, no reader in
  production, and no tool behind the name `reader.py` claims.
- **Our gap.** The rotor names its own missing criterion: "No read ledger exists" (`bin/cc-memory-rotate:103-107`).
- **Design.**
  - An hourly damped block in the repaired session-index sweep, never inside the per-file loop.
  - An rg prefilter over all 4 roots, subagents included.
  - Excludes the author and bulk readers (more than 10 topics in one session).
  - Rows are metadata only and pruned at 365 days.
  - A summary TSV is read by `durability_rank` (`:1142-1160`) **only as protection**: read by a
    non-author in the last 60 days gives rank 2. It never selects a file for eviction. A stale ledger
    prints `reads=absent|stale`.
  - Add a `growth-coverage.conf` row.
- **Lenses.** Efficacy adapt 72, premise adapt 78, fit adapt 72.
- **Gap pass (gap 5).** It depends on #2 P0 plus P0b (the awk fix and the DROP fix), not on the P1
  self-heal, so it can start sooner. Its hourly block runs inside the sweep, so it also inherits X2-X5.

### 3.16 consolidation-families-at-compaction (build-later after #4 and #10, 66, S)
- **Design.**
  - A propose-only compact-memory step 7b.
  - BM25 over name, description and first paragraph (not full bodies, which fat aggregator files saturate).
  - Mutual top-3 pairs that are not yet linked, scoped to topics new since `archive/.family-names`:
    37 infra and 59 reso pairs per 14 days (MEASURED).
  - Decide MERGE, LINK or NONE **before** writing any link, because `compact-memory.md:327` treats linked
    pairs as distinct.
  - Report the hot-hub count before and after, since 4 or more inbound links pin an entry hot.
  - Never write a summary or family file. That is TM's L4 lesson, CLAIMED at `CHANGELOG.md:377-380` and
    confounded by a scorer bug (#633).
  - Hand-judged precision: about 25-45% true edges (n=20).
- **Lenses.** Efficacy adapt 65, premise adapt 70 (the "control family" example was false: it is already
  linked), fit adapt 72.
- **Gap pass (gap 1). Do not defer this to Claude Code's native `autoDream`.**
  - autoDream is the native equivalent, but its Phase 4 is autonomous and lossy. It shortens index
    lines, deletes "contradicted facts" and removes pointers. It knows none of the rotor's protections:
    PINNED, TAIL_GUARD, the type hold, or the dangling-link refusal.
  - In 2.1.278 its conservative team-pruning and CLAUDE.md-reconcile paragraphs are defined but never
    inserted into the prompt.
  - Keep it pinned off (§7). #16 plus #17 are our propose-only, lossless substitute.

### 3.17 divergent-token-guard → merge-losslessness rule (build-later with #16, 62, XS)
- **TM mechanism.** `_has_divergent_numbers` (`ingest/dedup.py:100-114`) only runs at cosine > 0.92 on
  the no-LLM path. When it fires, TM keeps **both** facts (ADD). The "6 of 6" claim in #576 is about a
  regex that was never shipped.
- **Measured problem with the proposal.** Hard-token multisets differ in 100% of nearest-neighbour body
  pairs and in 29 of 29 candidate pairs, **true duplicates included**. As a HARD CONSTRAINT it would veto every merge.
- **Design.**
  - Prose in step 7: when values differ, supersede rather than merge. A merge must carry every hard token
    or a "Superseded (date): was X" line.
  - An optional `--pair A B --into C` mode in `bin/cc-memory-dropped-token-audit`, reusing `toks()`.
- **Lenses.** Efficacy adopt-as-advisory 72, premise reject 80 (no incident; the label is noise), fit
  adapt 80. The lossless-merge form resolves the disagreement.

### 3.18 episodic-session-recall (build-later after #2, 60, S)
- **Premise refutation.** `claude-search` already runs bm25 over `sessions_fts` and `chunks_fts`, with
  temporal parsing (`claude-session-search/bin/session-search.py:97,534-620`). 0 of the 4 cited misses
  would have changed: agents found them with find or git log, and #110 has no index row.
- **Design.**
  - No new CLI.
  - One narrow-cue line merged into memory-nudge's JSON. The regex covers prior-session phrasings
    (did we, last session, like we did, a week ago, retrieve that research…). It fires on 35 of 2,650
    prompts and catches 4 of 4 targets; the broad cue set fired on 31%.
  - It points to `claude-search '<nouns>'` and injects nothing from other sessions.
- **Lenses.** Efficacy adapt 72, premise reject 78, fit adapt 74.
- **Gap pass (gap 2, MEASURED).** The premise refutation holds on the replay.
  - #78, #88 and #106 were each found by `find` or `git` in 12 s to 3 min.
  - `sessions_fts` (40 rows) and `chunks_fts` (679) match 0 rows for any of the episodic misses.
  - The #106 answer lived only in workflow result JSON (`*/workflows/wf_*.json`), which the indexer
    does not read.
  - Disposition unchanged. Two dependencies are added: #2 P0 plus P0b, and #2 indexing workflow
    result files. Without the latter, #106-type misses stay invisible to this item.

### 3.19 rotor-lock (build-later, 62, S)
- **Measured.** The rotor's TERM trap releases the lock (5 of 5 runs), so only SIGKILL leaves it
  orphaned. The realistic orphan path is `memory-nudge.sh:240-244,265`, which runs the rotor unbounded
  inside a 5 s UserPromptSubmit hook. The drain has no `verdict=locked` arm.
- **Design.**
  - Replace the 180 s age-based reclaim with a kernel-released fd lock: `flock -n` if present, else
    `/usr/bin/lockf -s -t 0`, else the old mkdir lock.
  - Never unlink the lock file. Children run with `9>&-`.
  - bats cases: SIGKILL mid-run, a held lock returns `verdict=locked`, and a forced `mv` failure leaves
    the index byte-identical.
  - Drop the index-append lock (a hook cannot span the tool's own write) and the deadline env var.
- **Lenses.** Efficacy adapt 78, premise reject 78, fit adapt 70.
- **Gap pass (gap 1).** No lock of ours can cover Claude Code's `extractMemories` or `autoDream` forks,
  which do not take it (ESTIMATED from the fork code). CC's read-before-Edit staleness check gives the
  fork partial lost-update protection against the rotor, but not the other way round. #11 is the
  mitigation, not this item. Disposition unchanged.

### 3.20-3.22 small build-later items
- **frontmatter-validator-env-clamp (60, S).**
  - Add a `--schema` report mode to memory-fleet-sweep. There are 12 files without frontmatter
    fleet-wide, 0 hard violations in 314 recent writes, and no `name==stem` rule (206 false positives).
  - Drop the write-time validator.
  - Drop the post-hoc Bash backup, which captures the *new* bytes.
  - Drop the `env_int` fallback, which contradicts the fail-closed doctrine at
    `memory-index-measure.sh:80` and breaks the default-ratchet tests.
  - Drop the `.corrupt` rename, since `.rotate.log` has no reader.
  - Lenses 70 / reject 80 / 78.
- **claim-queue-primitives (55).**
  - No consumer exists. Record TM's queue failure list as the acceptance spec for any future background
    memory worker:
    - claim by rename, with pid, start time and `claimed_at`;
    - a retry cap that moves items to `.failed`;
    - count items, never prune them silently;
    - FIFO order by `queued_at`;
    - take the lock before reading cap state;
    - refund the budget on every denial path;
    - the worker is Python, not bash, because of cc-reaper's 600 s rule;
    - admission goes through `scripts/lib/capacity-admit.sh`.
  - The harvest ledger gets a flocked status writer after #3.
  - Lenses 70 / reject 78 / 80.
- **capture-decision-ledger (52, XS).**
  - Add a deny-only row in `backup-before-write.sh`'s budget deny branch through `idl-log.sh`.
  - The compact-memory orphan step labels "pointer refused <ts>" for each orphan it finds.
  - Premise: 23 real refusals, all 08-23..09-04 on reso, 0 since, 0 orphans caused. Drains are already in `.rotate.log`.
  - Lenses 70 / reject 75 / 70.

### 3.23-3.27 experiments
- **userprompt-pointer-recall (62, M).**
  - CC 2.1.278 ships native prompt-time recall: `startRelevantMemoryPrefetch`, which emits
    `relevant_memories`. It is gated by `tengu_moth_copse`, which is false in the cached features. The
    hook must step aside if that flag turns true, and dedupe against `relevant_memories` attachments.
    Never set `CLAUDE_MEMORY_STORES` to enable it: that starts the memory-store sync watcher.
  - Store allowlist: personal and reso first, not infra.
  - No first-prompt debounce, because 65% of sessions have exactly one prompt.
  - Replace the raw-bm25 floor, which is length-confounded (a gold-median floor passes 104 of 109 long
    prompts but only 2 of 110 short ones), with three gates: 2 or more rare terms in name or
    description, a top-1/top-2 margin, and a per-store floor calibrated on about 50 hand-labelled real prompts.
  - Shadow mode for 1-2 weeks. Enable a store only if precision is at least 0.7. Personal measured
    10 of 11; the mixed store 6 of 40.
  - Output goes through #7.
  - **Gap pass.**
    - **Replay (gap 2).** On verbatim prompts it puts time-valid gold in the top 5 for #10, #11, #48,
      #78 and #79 at project scope, and for #88 and the Pyramid half of #70 with `--all`. But 3 of those
      5 project-scope hits (#10, #11, #79) were already in context. Net new is about 2-4 of 14 misses a
      month. It stays an experiment.
    - **One of only two read-time push paths (gap 3)**, beside native prefetch. If `tengu_moth_copse`
      flips on, this steps aside as planned.
    - Its shadow log inherits X2-X5, and its delivery is checked by the `tool_use_id` join, as in #6.
- **candidate-extractor-worker and transcript-capture-enqueue (60 / 58).**
  - Run Stage 0 only: `bin/cc-memory-extract --dry-run` over the last 30 days of eligible sessions:
    cli entrypoint, at least 2 operator prompts, not under `/private/tmp`.
  - Why that filter: 94.5% of sdk-cli sessions are eval fixtures, the real-repo capture rate is 10.9%,
    and real headless capture is 0 of 135.
  - Input: operator turns plus up to 1,500 chars of the preceding assistant text via #14. No tool results.
  - Run `claude -p --setting-sources ''` on the cheap tier. The DO-NOT list is read from the
    CLAUDE.global.md anti-capture section and fails closed if missing. The transcript is fenced as untrusted.
  - Gate: at least 50% of candidates promotable; surfaces the voiceink sign-off rule (#58) and the reso
    human-sourced-image rule (#79); abstains on #70, which was already stored.
    - **Corrected in the gap pass (gap 2): two of these gold targets are time-invalid.** At the #70 miss
      the fde store was **empty**; every file was born 15 h later. The live session itself stored the
      #58 rule 17 s after the prompt.
    - **Replacement Stage-0 targets** are the moments when an operator ruling was stated and never
      captured:
      - session 19f6b94b on 09-16 (the mannered-prose rule, pasted twice);
      - 5e498dc5 at 09-12T03:14Z (the Google-Images curation practice);
      - the 09-14/15 kitty sessions (drag priority).
      Keep #79's sourcing half.
  - Only if Stage 0 passes, build:
    - a nightly launchd pull scanner (no SessionEnd hook, no queue directory);
    - a held per-session watermark table;
    - hooks disabled in the child;
    - at most 3 candidates per store per night, expiring after 14 days;
    - the pending count surfaced at SessionStart, not in the nudge (reach 9.6%).
  - The harvest ledger's 20/20 unreviewed is the stall risk to beat.
  - **Gap pass (gap 1): step aside for, but do not defer to, native `extractMemories`.**
    - Native extraction is a server flag away, and its prompt forbids verification. So do not treat it as
      a substitute.
    - If `tengu_passport_quail` ever reads true (from the #8 sentinel), two things follow:
      - Stage 0 first scores native `memory_saved` output against the anti-capture classes;
      - the nightly worker dedupes against native writes.
    - Native extraction suppresses itself in any window where the main thread wrote memory.
  - **Priority (gap 2).** 4 of the 6 gold-missing misses are uncaptured operator rulings, so capture is
    a real gap. It ties #4 and outranks #23. It does not outrank #4. It stays an experiment because
    Stage 0 is unrun.
- **speech-act-nudge-trigger (60, S; was 55). Starts now in Wave B, still in shadow.**
  - Shadow mode only, inside memory-nudge's existing jq call.
  - Match unanchored `\bremember\b[:,]?` (excluding "remember when/what/how…"), "from now on", "i told
    you" and "keep forgetting". Do **not** copy TM's `_QUOTED_SPAN_RE`, which eats contractions (MEASURED).
  - Measured: the proposed regex hit 5 of 2,180 prompts and found 0 rules. The yield is about 1 new
    uncaptured rule a month, and 2 of 3 genuine restatements were already stored (a compliance problem, not capture).
  - **Gap pass (gap 2): the target moves, and so does the timing.**
    - The dominant class among the real misses is an operator ruling stated in a session and never
      written down (#47, #66/67, #70, the sourcing half of #79).
    - The regex above keys on **restatement** words ("remember", "i told you"), which fire only after
      the miss. The capture moments themselves were plain imperatives: "we just go through 'at least
      4mb' images on google images", or a pasted prose rule.
    - So widen the shadow trigger to **ruling-shaped operator text**: imperatives or "we (always|just|
      don't) …" about how work is done, in a typed prompt. Keep the restatement patterns as a second class.
    - Score the widened trigger's shadow log against the four capture moments named in #24's corrected
      Stage 0.
    - **The widened regex's precision is unmeasured.** That is the open cost, so it stays an experiment
      and is not promoted to build-now. It has no dependency, so it starts in Wave B.
    - Gap 2 proposed "build-now, shadow". Shadow mode injects nothing, so the two labels differ only in
      name. Experiment is kept until precision is measured.
- **provenance-and-verification-tier (55, XS).**
  - A prose-only `Receipt: <cmd> => <output> [conditions: binary/version, headless|interactive, config dir]`
    line, placed in the anti-capture rule, the nudge SKIP clause and the compact-memory review order.
  - The flagship refuted claim was measured, then **over-generalised** to other scopes. So the
    conditions field is what matters; a tier label is not.
  - Count `^Receipt:` adoption after 30 days.
  - **Gap pass.**
    - Target list adds `CLAUDE.global.slim.md` (gap 4).
    - Add the #47 case (gap 2). A receipt should also record **whose** practice an entry replaces. The
      line "Replaces: <operator practice>" without an operator ruling is the flag (see #12).
    - As a prose line it is subject to gap 3's uptake evidence. Its measured 30-day adoption is the
      test that matters.

---

## 4. What we deliberately do not adopt

Record these as **one new section** in `docs/plans/MEMORY_KNOWLEDGE_V2.md`: "§8 TrueMemory study
(2026-09-27): rejected alternatives", numbered R11-R18. §4 is attempt 1's closed list, and §7.6 is
already taken. The sibling DNA candidates each claimed "R11", so they must be numbered together.
R18 was added in the gap pass.

| R | What | Why (measured unless marked) |
|---|---|---|
| R11 | Numeric encoding gate (novelty+salience+PE), speech-act/L3 salience, L5 surprise boost | On our corpus it acts as a length filter: r(log length, score)=0.876. 0/19 facts of ≤50 chars pass, against 139/140 over 200 chars. Short durable rules pass 2/185, while verbose anti-capture rewrites pass 5/5. L3's `f_length` weight is 8.54, the largest by far. The unanchored greeting prefix at `encoding_salience.py:285-288` rejects "Supabase…", "History…", "Your…", "Hidden…" and "High…". PE latches fail-open forever (`encoding_gate.py:507,551`). L5 ships at α=0.2 against its own test's α=0 recommendation (`tests/test_l5_surprise_rerank.py:11-16`). The gate is disabled in every benchmark, and its AUCs are unreproducible (#280). It would also put an embedder on our write path. Reopen only if a scorer beats length-matched controls on ≥20 negatives per anti-capture class. |
| R12 | Auto-store paths: regex no-LLM extractor, PreCompact raw snapshot, synchronous per-exchange store, MEMORY.md migrator/`--slim` | Over 40 transcripts the regex path produced 1,089 "facts", 976 of them under 25 chars; 141 would bypass the gate as corrections (`encoding_gate.py:251-276`). 16 of 19 eager hits were Stop-hook feedback. The per-exchange store shipped writing 0 rows (#634). The migrator's bare `add` duplicates on re-run and drops topic files. Our R2 still bars content-creating automated writes. The carve-out is the drain's non-lossy relocation. |
| R13 | Regex contradiction detection, in-place UPDATE dedup, ever-growing trait profiles | "Actually…" superseded nothing. "office" filed a Heroku→Fly migration under office_location. 30 agent-style messages gave 25 timeline rows. Dedup overwrote Bob's row with Alice's fact, and overwrote Production with Staging via "as of" (`ingest/markers.py:82-83`). UPDATE overwrites in place (`storage.py:1178`), contradicting `ingest/dedup.py:11`. Profiles are substring unions with no decay (`personality.py:999-1023`). TM itself disabled L4 sheets for leaking superseded facts. This independently confirms the rotor's refusal to read prose markers (`bin/cc-memory-rotate:93-102`). |
| R14 | ML retrieval runtime and heuristic multipliers: model daemon, Qwen3, cross-encoder, HDBSCAN, temporal ×1.3, entity/scent boosts, fixed SessionStart queries | Once the daemon idle-exits, each recall hook loads Qwen3 in-process: 678-709 MB and 8-17 s. MPS runs out of memory and the fallback sticks to CPU with 1 thread. An orphaned daemon held 1.9 GB. Clustering silently no-op'd on every install (#696). The temporal filter was dead through a key mismatch (#466). The entity boost is never written back into the score (`salience.py:474-481`). The trajectory ×1.3 demotes the newest rows. The cross-encoder gives R@1 0.84 (RRF) → 0.94 at about 1.3 s and 1.85 GB, but the calling model already reads the top-k. On TM's own benchmark the models are worth a real +1-2.4 pp, in a regime (top-100 into the answerer, lenient judge) that does not match ours. Rule: nothing on a hook path imports torch or talks to a daemon. |
| R15 | Installing, running or copying TrueMemory | The installer rewrites settings.json hooks and adds a CLAUDE.md block calling MEMORY.md "a lossy, potentially stale cache" (`ingest/CLAUDE_TEMPLATE.md:3-18`). The MCP instructions steer the model to recall API keys, SSH credentials and DB passwords (`mcp_server.py:373-376`). Telemetry is on by default and a hook scrapes emails (`telemetry.py:45,160-184`; `user_prompt_submit.py:681-731`). A remote message is injected unsanitised (`session_start.py:200-205`). Licence is AGPL-3.0-only plus a relicensing CLA, and our repo is headed for public projection with no licence (`46-public-repo-cutover.sh`, pending). HEAD breaks on mcp 2.2.0 and CI has been red since 08-29; the PyPI 0.7.6.2 release still installs. **Convention:** ideas only; copy no code, regex, prompt or template text, weights or fixtures; a file header reads "Idea: arXiv 2605.04897 / TrueMemory #N; independent implementation, no TrueMemory code". Reopen only if TM is relicensed permissively, a fresh install passes a smoke test, and its hooks emit `hookSpecificOutput`. |
| R16 | Recall appended to dispatched and subagent briefs | 94.5% of the "54% headless" population is `/private/tmp` eval/probe traffic. handoff-fire panes are interactive cli sessions that already load MEMORY.md. 87% of subagents are Workflow agents, which `PreToolUse(Agent)` never sees, including the worker that motivated the idea. Top-1 relevance on 25 real briefs was about 12%. At most, widen `agents/workflow-lean.md:27-28`. |
| R17 | Further demotion of resident lessons to recalled pointers | Already done: cb5f7109c plus 0036 cut resident rules to 19 bullets (3.7k tokens), gated at −20.9% cost per run (p=0.008, `GATE.md:503-511`). The f3 parity gate that was proposed cannot be met (about 105-2,150 runs per arm). The remainder is truthfulness (#1) and symptom recall (#6). |
| R18 | Hand consolidation or capture to Claude Code's native `autoDream` / `extractMemories` (gap 1) | Both fork with Edit/Write on any `.md` in our stores and `rm -f` of `.md`; `archive/` is not protected. autoDream's Phase 4 shortens lines, deletes "contradicted facts" and drops pointers. That is the lossy half our rotor and compact-memory deliberately keep human-gated, and its conservative team and CLAUDE.md paragraphs are dead text in 2.1.278. The extraction prompt forbids verification ("no grepping… no git commands"), which contradicts our anti-capture rule. Extraction has **no opt-out** short of disabling auto-memory, which also stops MEMORY.md loading. **Rule:** pin `autoDreamEnabled:false` (operator decision, §7), watch both flags with #8's sentinel, and let #11 be the undo. #16/#17 and #24/#25 stay ours, with step-aside clauses. |

**R2 wording (gap 1).** R2 (`MEMORY_KNOWLEDGE_V2.md:231-237`) reads "Every mechanism in this plan is
read-only against the store". That is a rule about what **we** build, not a guarantee about the store.
Reword it to say so, and add: "vendor background passes can write the store; see #11 and the #8
sentinel". Do not relax it.

Sub-parts dropped from adopted items, so nobody resurrects them:
- a PreToolUse advisory arm (it arrives after the command runs);
- a standalone per-Bash hook fork;
- `symptoms:` frontmatter before 15 rows;
- routing demoted lines to COLD;
- a dynamic run-every-hook contract test;
- a persistent FTS cache or embeddings in v1;
- a gzip-novelty threshold;
- a Python sanitizer helper;
- the H1/H2 body lint;
- `supersedes:`/`valid_until:` as required fields;
- a Read redirect hook;
- `cc-memory-forget --apply`;
- rotor link rewriting;
- an env_int fallback;
- a post-hoc Bash backup;
- PID-attributed heartbeat status;
- SessionEnd or PreCompact enqueue hooks;
- a claimq library ahead of any consumer;
- per-change f3 arms;
- (gap pass) the `.claude/rules/…:33` rewording as a #4 consumer (0/218 uptake of that line);
- (gap pass) a 2-week efficacy verdict from #6's holdout (it has no power);
- (gap pass) a DELETE log or SQLite trigger to catch the `sessions_fts` deleter (DROP fires neither;
  use the root-page fingerprint);
- (gap pass) `autoMemoryEnabled:false` or `DISABLE_GROWTHBOOK=1` as a way to block native extraction.
  The first also stops MEMORY.md loading. The second disables every server flag.

---

## 5. Empirical probe results (what was run)

### 5.1 Retrieval on our corpus (640 docs, 2.4 MB, 50 hand-labelled queries; `tm-empirical.md`)
| Method | R@1 | R@5 | Latency | Peak RSS |
|---|---|---|---|---|
| `rg` distinct terms / `rg -l` AND | 0.36 / 0.02 | 0.64 / 0.06 | 159 / 210 ms | — |
| Always-loaded index lines (hot + rules) | 0.44 | 0.52 (ceiling 66%) | — | — |
| All index lines incl. COLD | 0.74 | 0.86 | — | — |
| FTS5 body / fielded 10-5-1 | 0.76 / 0.78 | 0.86 / 0.88 | 0.85 / 2.9 ms | 50 MB |
| RRF FTS5 + potion head | 0.90 | 0.94 | 12.6 ms | 187 MB |
| TM hybrid, no reranker | 0.86 | 0.96 | 489 ms | — |
| TM full (reranker, patched) / as installed | 0.94 / 0.94 | 0.96 / 0.96 | 23 s / 49.7 s | 1.46 GB |

- Sign test, TM full against RRF: 3 wins to 1, p=0.625, not significant. RRF against FTS5: 6 to 0,
  p=0.031. Nearly all of the vector and reranker gain is on the 10 paraphrase queries.
- Two queries were missed at rank 1 by every method. One (q45) was reached only by a hand-written
  **symptom-phrased index hook**.
- TM cost: 911 MB venv, 91 s install, 326.7 s to ingest 640 docs. The unpatched MiniLM reranker was
  seen to SIGBUS or return NaN in standalone probes, but not in the recorded end-to-end run.
- Threats to validity: one author wrote both queries and gold, n=50, and weights may have been tuned after the fact.

### 5.2 TM runtime cost (`tm-ops.md` §0)
- A hook that recalls with the daemon down: 8.14 s and 709 MB. The same hook with a non-recall prompt: 0.13 s and 38 MB.
- Base on MPS: 1.60 GB footprint. After an MPS OOM it sticks to CPU at about 1 core and 1.9 GB until killed.
- The edge tier with its daemon down: 4.25 s and 125 MB.

### 5.3 Gate and salience (`tm-gate.md` §2, edge tier only)
- r(log length, score) = 0.876. Encode rate by length: 0/19 at ≤50 chars, 139/140 over 200.
- Durable rules in short-title form: 2/185 pass. Verbose anti-capture rewrites: 5/5 pass.
- PE: a contradiction scores 0.05, unrelated text 0.21.
- Prefix-regex rejects: see R11.

### 5.4 Lifecycle, dedup and forget (`tm-lifecycle.md`, `tm-gate.md` P8, `efficacy-forget-cascade.notes.txt`)
- Regex supersession on agent text: see R13.
- Forget cascade: "Zanzibar Quay 4417" and "Priya" survive `delete_message` in `summaries`, and the
  `josh` profile rows survive the delete of `Josh`.
- `log_batch_summary` reported 6 passed when 4 actually passed.
- A SessionEnd-spawned worker killed mid-run leaves its session permanently marked extracted.
- The 20-chunk cap dropped 96.3% of a 41 MB transcript while the marker recorded the full size.

### 5.5 Capture and noise (`tm-capture.md`, premise scratch)
- Of 2,203 "human" messages TM parses, only 19.8% look typed. Noise is 58.7% of formatted chars.
- The regex extractor produced 1,089 facts, 976 under 25 chars.
- The candidate's gap numbers overstated the problem once re-based:
  - sdk-cli: 2,312 of 2,447 are fixtures or probes;
  - real-repo capture: 10.9%;
  - real headless capture: 0/135.

### 5.6 Injection and delivery (`tm-injection.md`, `eff_inject_sanitize_probe.out`)
- Top-level `additionalContext` is ignored by CC 2.1.278 (static read).
- MCP instructions: 4,865 chars against the 2,048-char cap. The cut falls mid-"Storing", so the
  Recalling, Proactive and Directives sections never arrive.
- The sanitizer can be bypassed: see §3.7.

### 5.7 Our usage (`our-usage.md`, `our-read.md`, `our-write.md`; 7,881 transcripts, 10.03 GB, full scan)
- Pure consult rate: 2.0% of 3,318 main sessions; 5.6% of the 917 with a typed prompt.
- Non-author reads in 30 days: 25/496 infra topics, 18/144 lesson bodies, 1 COLD read.
- Reachability: 150/496 topics one hop from a delivered surface; 192 unreachable even transitively.
- Re-learning: 251 sessions hit a lesson's symptom after the lesson existed, 71% resident, 4% opened;
  but 154 of them are self-describing emitters, leaving about 8-12 real recurrences.
- Operator voice: 10 cross-session memory misses and 4 restated rules in 30 days. Gap 2 classified
  these 14 as: 2 captured but not surfaced, 1 captured in another store, 6 never stored, 4 in context
  but not obeyed, 1 not a memory miss (§5.11).
- Capture: 5.3% of sessions write memory (10.9% real-repo), and the nudge reaches 9.6%.
- Hygiene: `superseded_by` adopted 0 times. 37-40% of topics have no inbound link.

### 5.8 Live defects found in our stack (re-checked this session)
| Defect | Evidence | Fix |
|---|---|---|
| Session-index sweep dead since 09-07 | 191,067 "newline in string" lines; `file_tracking` 11 rows | #2 P0 |
| `sessions_fts` near-empty: **DROPped by the init_db migration probe** (recurring since at least July) | 40 / 9,422; freed root pages 20-24; probe false "missing" in 2.6-3.1% of tries under contention | #2 P0b (was P1) |
| SessionEnd writes 0 msgs, which starves harvest | 11,666 / 11,670 index lines | #3 |
| False "loads by default" plus a DELETE instruction | 6 sites incl. `memory-index-budget.sh:348` | #1 |
| Lessons routed into excluded, pointerless files | personal, sevenrooms-bridge | #1, #8 |
| Cold pointer stripped and stale (171 vs 285) | `mim_effective_file | grep -c cold` = 0 | #9 |
| Rotor unbounded inside a 5 s prompt hook | `memory-nudge.sh:240-244,265` | #19 |
| Plan R7 says PostToolUse context does not reach the model | `memory-index-drain.sh:341` shows it does | #1 |
| Native CC memory writers can be switched on server-side, with no extraction opt-out | `tengu_passport_quail` / `tengu_onyx_plover` gates; 6 caches, all off | #8 sentinel, #11, autoDream pin (§7) |
| Instruction edits target a variant ~7% of transcripts load | 4 of 5 roots link `CLAUDE.md` → `CLAUDE.slim.md` (rule at `CLAUDE.global.slim.md:47`) | #4, #10, #12, #27 target lists |
| New `hooks/lib/*.tsv`/`*.jq` never linked; new `*.py` not repaired by deploy-live | `install.sh:340`; `deploy-parity-assert.sh:551-552` | X1 |
| Hook state split over 4 physical `$CFG/state` dirs | `readlink`; main root about 7% of the last day's transcripts | X4 |

### 5.9 Trigger-precision probes
| Probe | Result |
|---|---|
| Proposed speech-act regex (2,180 prompts) | 5 hits, 0 standing rules. Unanchored `remember`: 11 hits, about 8 rules |
| Episodic cue sets (2,650 prompts) | broad set fires on 31%; narrow set 35 hits, 4/4 targets |
| Raw bm25 floor for prompt recall | length-confounded (104/109 long against 2/110 short pass); mixed-store top-1 relevant 6/40; personal store 10/11 |
| Neighbour detection on real duplicate pairs | gzip <0.25: 0/3; IDF overlap top-1: 8/8 directions; FTS5 twin #1 for both infra pairs |
| Brief-time recall on 25 real briefs | 7 relevant / 8 partial / 10 irrelevant; 4 of the 7 already in context |
| Symptom scan cost | in-process Python 4.9 ms on 71 KB, against bash+grep 96 ms (p90 169) |

### 5.10 Claude Code's native memory passes (gap 1; `gap-1.md`, scratch `gap1/`)
Static reads cover 2.1.278 (the strings dump) and were cross-checked in 2.1.114, 2.1.260 and 2.1.280.
The launcher runs 2.1.280. Current state was checked read-only.

| Item | Result |
|---|---|
| Stores reached | the default `memoryDir` is `<config>/projects/<slug>/memory/`; every account root resolves to the one physical store under `~/.claude/projects` (200/200 sampled entries are symlinks) |
| extractMemories gate | `tengu_passport_quail` (plus `tengu_slate_thimble` for non-interactive sessions); main thread only; cadence `tengu_bramble_lintel` = **7** turns in all six caches; skips turns where the main thread already wrote memory |
| autoDream gate | `tengu_onyx_plover` `{enabled}` or `{available}`; the `autoDreamEnabled` setting wins once the flag passes; no dreams from SDK or `-p` runs; staged payload `minSessions:3, minHours:24`; clock = mtime of `.consolidate-lock` (0 if absent) |
| Permissions (both passes, same function) | Read/Grep/Glob; read-only Bash plus `rm -f` of `.md` files; Edit/Write on any `.md` under memoryDir except protected segments, and **`archive/` is not protected** |
| Extraction prompt | "Do not waste any turns attempting to … verify … no grepping source files … no git commands" |
| Off-switches | no settings key for extraction; `autoMemoryEnabled:false` also stops MEMORY.md loading; local flag overrides return null in external builds; `DISABLE_GROWTHBOOK=1` kills every flag |
| Refresh | every 360 min by default and at launch, so a flip reaches running sessions within about 6 h |
| Other levers | `tengu_sepia_cormorant` + `tengu_umber_petrel` = per-model auto-memory kill switch that no setting overrides; `tengu_stone_shell` = pinned topic files load alongside MEMORY.md; `tengu_haze_glass` = org memory; `tengu_linen_orbit` = "tools" memory mode (semantics not read) |
| Current state (MEASURED-run) | six caches (not five), all passes off; 0 `memory_saved` in 2,442 transcripts (the control matched 250); 0 `.consolidate-lock`, `team/` or `logs/` in 37 stores; no pins set in any of the 5 `settings.json` |
| Exposure on a flip | 13 of 37 stores have ≥3 sessions in 30 days and no lock, so they would dream on the first interactive turn (infra 117 sessions) |
| Team memory counters | UI tallies only; team memory needs `CLAUDE_MEMORY_STORES` or `tengu_haze_glass` (false) |
| Unverified | whether our PreToolUse hooks fire on tool calls inside these background forks |

### 5.11 Replay of the real misses through fielded FTS5 (gap 2; `gap-2.md`, scratch `gap2/`)
- **Method.** Gold counts only if it existed before the miss, by file birth time or first git add.
  Scopes: P (project, the #4 default), A (`--all`), X (A plus repo docs, reference only). Queries: the
  operator's verbatim prompt (`op`), its first 12 terms (`op12`), and an agent phrasing (`ag`, written
  with gold known, so an upper bound).
- **Classification of the 14 misses:**

  | class | items | n |
  |---|---|---|
  | captured, fixable at the #4 default scope | #48 (rank 1), #78 (rank 4) | 2 |
  | captured in another project's store | #88 (rank 2 with `--all`) | 1 |
  | never stored before the miss | #47, #58, #66/67, #70, #106, #110 | 6 |
  | in context or resident, not obeyed | #10, #11, #29, #79 | 4 |
  | not a cross-session memory miss | #13 | 1 |

- **The 12-term cap** dropped #78 from rank 4 to 15. `--all` was required for #88 and for the Pyramid
  half of #70. Moving from P to A improved one case and worsened #79 from rank 4 to 6.
- **#47: retrieval would have done harm.** The top hit in P and A is the agent-written playbook that
  says "Replaces 'at least 4MB on Google Images'".
- **Recurrences.** The gold hook line ranks 1 (of 122-130) for never-wrap-ship and never-write-tracked,
  and 2 of 208 for tab-IFS. The topic files rank 1-4. Every one is a trigger miss.
- **Session index.** 40 FTS rows. `pinterest`, `perrier`, `react doctor`, `truememory` and `image2`
  each match 0. The #106 answer is only in workflow JSON.
- **Caveats.** n=14 with one analyst. Files modified after a miss were indexed at their current text.
  Silent misses are not in the 14.

### 5.12 Uptake of prose "search first" lines (gap 3; `gap-3.md`, scratch `gap3/`)
| Line | Setting | Followed |
|---|---|---|
| rules `:33` "grep that file for the symptom" | f3 headless replay, exclude arm, prompt "tests/X.bats is failing, fix it" | **0/22** |
| same line | real sessions with the line resident and a strict `not ok N` | **0/32** (pooled 0/54, Wilson upper bound 6.6%) |
| `CLAUDE.global.md:103` "grep MEMORY.md first" | real sessions that created a topic file with Write | **2/64** strict (3.1%); 12/64 loose (any look at the dir) |
| `claude-search` (named in no resident instruction) | all 3,318 main sessions | 14 sessions (0.42%), mostly `which` probes |
| `/compact-memory` | 30 days | ≤ 12 runs |
| all memory pulls in 1,801 headless eval sessions | — | 0 |

- **Estimate for #4's prose line:** 0-10% invocation (ESTIMATED from the two Wilson upper bounds).
- **Limits.** The f3 tasks are low-need (the model knew every fix). The write-time rate cannot see a
  mental check against the resident MEMORY.md. None of this measures a named new CLI with a crisp trigger.
- **A/B built, not run.** `gap3/ab/` holds `run-ab.sh`, a prototype `cc-memory-search`, 12 tasks and a
  scorer with a pre-registered rule: line-arm invocation ≥30% with p<0.05 means the prose consumer
  counts; below 10% means substrate only. It uses a frozen store copy through `autoMemoryDirectory`.
  - It needs a real account config dir, so it is operator-run.
  - Cost is about $41-52 for 48 runs (ESTIMATED from GATE.md).
  - At 20 runs per arm it has 0.91 power to detect a true 40% uptake (MEASURED by simulation).
  - Dry run passed with the model call stubbed.

### 5.13 The `sessions_fts` deleter (gap 5; `gap-5.md`, scratch `gap5/`)
- **Proof of DROP, not DELETE.** `sqlite_master` rowids 19-23 are gone and the table was re-created at
  27-32. Old root pages 20-24 are on the freelist (17,978 free pages). The data table is 17 pages; a
  replayed DELETE rebuild leaves 10,629.
- **Window.** 19:00:04Z to 19:01:37Z on 09-27.
- **Mechanism, reproduced link by link on copies.**
  - Probe false "missing": 39/1500 and 46/1500 under contention, against 0/1500 with `.timeout 5000`.
  - Without `-bail`, statement 2 runs after statement 1 fails (non-DDL stand-in).
  - Real `init_db` under errexit on a junk DB: rc=1, no "Migrated" line.
- **Recurrence.** The 07-26 backup has the same fresh-table signature (153/5,653 rows, rowids 1-154).
- **Exonerated.** Every DELETE-based rebuild site, retention, the backfill (Sundays only) and the
  tagger (no launchd job).

### 5.14 Liveness and delivery of the new branches (gap 4; `gap-4.md`, scratch `gap4/`)
| Probe | Result |
|---|---|
| Context attachment order (522 transcripts, 2 days) | PreToolUse 266/266 delivered with the tool result; PostToolUse 94/94 after it; PostToolUseFailure 0 (never used) |
| Mismatched `hookEventName` | thrown or dropped (`_cc_strings.txt:195712,294055`, static) |
| New topic files by birthtime | 67 in 7 days, 132 in 14 days (reso 54, infra 34 over 14 days) |
| Bash volume | 35,029 calls over about 3.2 days, peak 12,718 in a day; 210 memory-path greps |
| #6 expected fires | about 36 foreign-emitter hits per 2 weeks before dedup (ESTIMATED from the census) |
| #6 holdout power | 9/29 against 0/7 gives p=0.106; only 12/29 reaches p=0.041 |
| `rm` of a memory file | not auto-allowed (`rm-safe-allowlist.sh:8-12`); goes to the classifier or a prompt |
| Account roots on the slim CLAUDE variant | 4 of 5; `~/.claude` root held 20 of 286 transcripts in the last day |

### 5.15 X6 live probe of the tool-event channels (Wave B, 2026-09-28; `hook-probe/RESULTS-tool-events-2026-09-28.md`)
Claude Code 2.1.278, `claude -p --setting-sources ''`, Haiku 4.5.

| Channel | Result |
|---|---|
| PostToolUse(Bash), one object with `updatedToolOutput` + `additionalContext` (#6 combined case) | both delivered |
| PreToolUse(Write), one object with `updatedInput` + `additionalContext` (#10 through `_bbw_out`) | delivered |
| PostToolUseFailure(Bash), `hookEventName` echoed from the payload (#6 log-bash arm) | delivered; `.error` is `Exit code N\n` + stdout + stderr |
| PostToolUse inside a subagent | delivered, as a `hook_additional_context` attachment in `<sid>/subagents/agent-<id>.jsonl` only |

This retires §3.6 gap-4's "PostToolUseFailure `additionalContext` has 0 live uses, an untested channel". A
delivery replay must read subagent transcripts too, or it undercounts delivery.

### 5.16 #35 end-to-end delivery benchmark — PRE-REGISTRATION (written 2026-09-28, before any run)
**Question.** Given a real task where a stored lesson decides the outcome, does the agent use that lesson and
get the task right, and does Wave B's push (#6 tool-output pointers, #10 write-time neighbours) change that?

**Arms.** All arms: `claude -p` on account `next`, Opus 5.5 effort high, `--setting-sources ''` (no operator
settings or hooks), empty MCP, the f3 sandbox-guard PreToolUse hook, a fixture clone of this repo, and a frozen
COPY of the infra memory store loaded through `autoMemoryDirectory` (regenerated from the live store into
`~/.claude/autonomy/memory-eval/`, never committed).
1. **Stock Claude Code**: no hooks of ours, no rules files, the operator's user `CLAUDE.md` excluded; only the
   built-in memory instruction and the frozen store.
2. **Our stack before Wave B**: our memory hooks, rules files and instruction text exported from `abaf1e990`.
3. **Our stack with Wave B**: the same set exported from trunk after #4, #6 and #10 landed.
4. **TrueMemory** (optional): installed only in a sandboxed HOME with its hook output wrapped in
   `hookSpecificOutput`; dropped, and said so, if it will not install cleanly.

**Tasks.** 12: 8 lesson tasks (each has one gold lesson whose absence changes the outcome; ≥4 make the agent
run a command whose output carries a foreign-emitter symptom from `hooks/lib/lesson-symptoms.tsv`, ≥2 are
write tasks that would create a near-duplicate memory topic) and 4 control tasks where no stored lesson
applies. 2 reps each.

**Measures per run.** lesson-used (the run opened the gold file, or its answer or action applies the gold
rule by the task's mechanical rubric, or on a write task it edited the existing twin instead of leaving a new
duplicate) · correct (task rubric, mechanical) · wall time · tokens (input + output + cache creation, from the
run's usage record).

**Primary test (decides the verdict).** On the 8 lesson tasks × 2 reps = 16 cells paired by (task, rep),
arm 3 vs arm 2 on lesson-used, one-sided sign test, ties dropped. **Gain** if p < 0.1; **no gain** if p ≥ 0.1.
With 16 untied pairs that needs ≥ 12 wins (P(X≥12)=0.038; ≥11 gives 0.105). Many ties are expected, so a
null reads "no detectable gain at this n", never "push does nothing".

**Secondary (reported, never overriding the primary).** correct, arm 3 vs arm 2 (same test); arm 2 vs arm 1
on lesson-used (does our pre-Wave-B stack beat stock); on the 4 control tasks, arm 3's false-pointer rate and
correctness, which must not trail arm 2 by more than 1 of 8.

**Branches.** Gain → #6 and #10 stay, Wave E push experiments proceed. No gain → per plan § Wave B: no new
push consumers on faith, Wave E #23 and #26 stop, #6/#10 stay only if their own logs show delivered-and-used
events, and a delivery-research wave opens on #36's fixtures.

**Budget.** ~96 runs ≈ 2-4 weekly-quota points on `next` (operator ruling 2026-09-27: no ask needed). Stop
and report if measured spend passes 5 points.

### 5.17 #35 results (run 2026-09-28)
**Verdict: NO GAIN (p = 1.0), and this benchmark could not have shown one because it has no headroom.** Every
lesson task was solved with or without the lesson, so all 16 primary pairs tied. Read this as "these tasks do
not separate the arms", never as "the push does nothing".

72 runs (12 tasks × 2 reps × arms 1-3), all exit 0, on Claude Code 2.1.280, `claude-opus-5-5` at effort high,
account `next`. Arm 2 = `abaf1e990`; arm 3 = `ba8e5c24a` (trunk with #4, #5, #6+#7, #10 and #26 landed).
Harness: `truememory-2026-09-27/bench/`; scorer `score.py`, tests `tests/bench-score.bats`. Run dirs and
per-run scores stay private under `~/.claude/autonomy/memory-eval/bench-runs/`.

| arm | runs | lesson-used (8 lesson+write tasks × 2) | correct (same) | control correct | control false pointer | median wall s | median tokens |
|---|---|---|---|---|---|---|---|
| 1 stock | 24 | 15/16 | 15/16 | 8/8 | 0/8 | 22 | 19,907 |
| 2 pre-Wave-B | 24 | 16/16 | 16/16 | 6/8 † | 0/8 | 26 | 70,024 |
| 3 Wave B | 24 | 16/16 | 16/16 | 6/8 † | 0/8 | 26 | 70,284 |

† A rubric artefact, not a failure; see deviation 6.

**Primary (arm 3 vs arm 2, lesson-used, paired by task × rep):** 0 wins, 0 losses, 16 ties, p = 1.0 → no gain.

**Secondaries.**
- Correct, arm 3 vs arm 2: 0 wins, 0 losses, 16 ties, p = 1.0.
- Lesson-used, arm 2 vs arm 1: 1 win, 0 losses, 15 ties, p = 0.5. The one difference is T05 rep 1, where the
  stock arm answered YES to wrapping the lander in an outer timeout.
- Controls: arm 3's false-pointer rate is 0/8, the same as arm 2's, and its correctness equals arm 2's (6/8
  each; 8/8 after deviation 6). Neither measure trails arm 2 by more than 1 of 8.
- **Delivery vs use (#6).** Arm 3 delivered the gold lesson's pointer in a `hook_additional_context`
  attachment in all 8 runs whose command printed a `lesson-symptoms.tsv` literal (T01-T04 × 2), and in no other
  run. **None of those 8 runs opened the lesson it pointed to**, and arms 1 and 2 reached the same answers
  without the pointer. No run in any arm Read a gold lesson on T01-T06. So #6 delivers, but this benchmark has
  no evidence that the delivery gets used.
- **Write-time neighbours (#10).** On W01-W02 no run in any arm created a duplicate. Every run found the
  existing twin: on W01 it edited the twin, and on W02 it indexed the unindexed twin in `MEMORY.md`. On W02,
  arm 3 alone also revised the twin's body (2/2, against 0/4 for arms 1-2). #10's neighbour log
  (`mem-neighbours.jsonl`) is empty in every write run, because no run wrote a new topic file. So #10 had
  nothing to catch.
- **Cost.** Our instruction text costs about 50K tokens a run (median 19.9K for stock against 70K for arms
  2-3). Arms 2 and 3 are within 0.4% of each other. Measured spend, smoke runs included: `next` weekly went
  from 7% to 9%.

**Hooks registered in arms 2 and 3.** The two lists are identical; the hook bodies differ between the two
shas:
- `backup-before-write`: PreToolUse, Write|Edit|MultiEdit
- `log-bash`: PostToolUse and PostToolUseFailure, Bash
- `memory-index-drain`: PostToolUse, Bash|Write|Edit|MultiEdit
- `harvest-skill-end`: SessionEnd
- `memory-nudge`: UserPromptSubmit
- `bash-output-offload`: PostToolUse, ^Bash$

Arm 1 registers none of these. All three arms also run the f3 sandbox guard.

**Branch taken under §5.16: no gain.** Per plan § Wave B:
- No new push consumers are added on faith.
- Wave E #23 and #26 stop.
- #6 and #10 stay only if their own logs show delivered-and-used events. In this benchmark #6 was delivered
  but never opened (0/8), and #10 never fired.
- A delivery-research wave opens on #36's fixtures. That wave needs tasks the stock arm fails. This task set
  gave stock 15/16, so it cannot measure a delivery effect.

**Deviations from §5.16.**
1. **Task validity, the main deviation.** §5.16 requires each lesson task to have "one gold lesson whose
   absence changes the outcome". Measured, none did: stock solved 15/16, and no run read a gold lesson on
   T01-T06. The tasks were fixed and committed before any run, and were not changed after the smoke run.
2. **Arm 4 (TrueMemory) was dropped.** TM's native ingest extracts facts through an external LLM
   (`ingest/pipeline.py:9`, `LLMConfig`). Loading the frozen store the way TM installs would need a paid API
   key, and the only TM config on disk holds a placeholder. I dropped it after about 3 minutes of the
   20-minute allowance, and installed nothing.
3. **HOME.** `claude` itself keeps the real HOME, because a redirected HOME reports "Not logged in"
   (measured when the harness was built). Only our hooks run with `HOME` and `CLAUDE_CONFIG_DIR` pointed into
   the run dir, so their state and logs land there.
4. **Instruction loading.** `--setting-sources ''` loads no user or project `CLAUDE.md` in any arm, so the
   operator's user `CLAUDE.md` is excluded from every arm, not only arm 1. Arms 2 and 3 get their
   instruction text (the fixture's `.claude/CLAUDE.md` and rules, plus the tree's `CLAUDE.global.slim.md`)
   through `--add-dir` with `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`.
5. **The arm-3 fixture is 27 commits newer than arm 2's.** It includes a ship preflight check that refuses an
   outer timeout, which is T05's subject. Arm 2 was already at ceiling on T05, so this changed no pair.
6. **C03 rubric artefact.** In all four arm-2/3 runs of C03, the repo's own "never commit in the shared
   checkout" rule led the agent to build `ops/sum.sh` in a sibling worktree. The pre-registered check looks
   only in the fixture, so it scored those runs 0. All four sibling copies print `9` for `sum.sh 2 3 4`,
   which makes control correctness 8/8 in every arm. The table keeps the mechanical score.
7. **Smoke runs** (T01 in arms 1-3) ran under a separate root and are excluded from the results. They matched
   the full run.

### 5.18 Wave E #23 and #26 — DROP under §5.17's no-gain branch (recorded 2026-09-28, no build)
**Rule applied.** §5.16 pre-registered: "No gain → … Wave E #23 and #26 stop". §5.17 measured no gain (0 wins,
0 losses, 16 ties, p = 1.0), so both stop. Neither experiment's own verdict rule (plan § Wave E) was scored,
and neither is reopened by a result recorded here.

- **#23 per-prompt pointer recall: DROP.** Never built. Its rule (≥40 hand-labelled shadow fires, top-1 relevant
  ≥60% with Wilson lower bound ≥45%, fires on ≤15% of prompts) was never run. It is a push consumer at the prompt,
  the class §5.17 says not to add on faith. *Reopen only if* a delivery-research wave, on tasks the stock arm
  fails (#36's fixtures, §5.23-5.24), shows that a pushed pointer changes what the agent does.
- **#26 ruling-shaped operator text nudge: DROP.** It shadowed from Wave B (`e2d44ff12`) until this wave. Its
  live log never reached its own n. From the first row (2026-09-28T07:10:14Z) to 16:45:19Z, the
  `memory-nudge:ruling` IDL rows numbered 184: **0 fired**, 15 no-match, 169 not-typed. Most counted prompts in
  that window were machine-authored (fire briefs, task notifications, teammate mail), and
  `~/.claude/state/ruling-shadow.jsonl` was never written. Its rule needed ≥20 fires with precision ≥70% and fires
  on ≥2 of the 4 never-written rulings, and it had 0 fires. The fire path is retired: the shadow is now off unless
  `CC_RULING_SHADOW=on` is set. Each prompt still logs one `abstained kill-switch` row, a reached guard (DORMANT),
  so the registry row stays true. *Reopen only if* the same delivery-research wave shows that capture at the
  ruling moment changes behaviour. #24's Stage 0 (§5.20) measures the capture half from transcripts, not prompts.

### 5.19 Wave E #4b — FTS5 + model2vec fusion on operator-worded queries
**Pre-registration (committed 2026-09-28, before any scored run; the rule is the lead's, fixed).**

- **Question.** Does RRF fusion of the shipped FTS5 ranking with model2vec cosine beat FTS5 alone on queries
  the operator typed? §5.1's 0.78 → 0.90 R@1 (6 wins to 0, p = 0.031) was on agent-written queries.
- **Unit.** One operator-worded query with ≥1 hand-labelled gold file born before the query time.
- **Arms.** A = `bin/cc-memory-search`'s own `build_corpus` and `search` (imported, never `main`, so no log is
  written), top 100. B = RRF (k = 60, `1/(60+i+1)` per list, i from 0) of A's list and the top 100 by
  `minishlab/potion-base-8M` cosine over head text (H1, else name with `-` as space, then `. ` and the
  description), the `empirical-harness/hybrid_lite.py` recipe. Same query text, scope and corpus in both.
- **Scope and corpus.** The shipped default (project) scope, resolved for the query's project: its store as the
  current store (`MEMORY_INDEX_PATH`), its repo root for lessons and rules (`claude-infrastructure` = this
  branch's tree), and the feedback sweep over every store under `~/.claude/projects`. A document born after the
  query time is removed before ranking, in both arms: topics by file birth time, lessons by first git add,
  rules-hook rows by `git blame` line time, cold rows by their target's birth. Text is today's (as in §5.11).
  A gold file that `build_corpus` dropped as a same-(name, description) twin counts through its kept twin.
- **Primary.** Rank of the first gold hit, 11 if not in the top 10. Win = B strictly better. One-sided sign
  test, ties dropped. **ADOPT iff p < 0.05 AND R@1(B) ≥ R@1(A); else DROP.** A query with no gold in its own
  scope's corpus is gold-missing: out of the primary and R@k, kept for the supersede count.
- **Secondary (never overriding).** R@1, R@5, MRR per arm with Wilson 95% CIs; the same test on the field
  records' `agent_query` (replication); per arm, queries whose top 1 is non-gold and declares
  `Replaces:`/`Supersedes:` (recall_eval's `SUPERSEDE`, the #47 class); B's cold latency (fresh process: load,
  encode corpus, one query), warm per-query latency and peak RSS.
- **Query set** (private: `~/.claude/autonomy/memory-eval/wave-e/4b/queries.json`,
  sha256 `5d0040be9844d06ebac8bf1e325af5e3112e2204f2fef0d5b0099b8339ac0e26`; 30 records).
  - Field: the 19 records of `field-queries.json`, query = `operator_verbatim`. 15 have gold of a searchable
    kind (topic, lesson, rules hook); #47, #66, #67, #106 do not (a runbook, research docs, none).
  - Transcript: typed prompts (`transcript_norm.typed_prompt`) in `~/.claude*/projects/*/*.jsonl`, last 60 days:
    6,008 typed prompts. Pass 1 (the brief's cue phrases plus synonyms) matched 64; pass 2 (broader cues:
    "didn't we", "our runbook", "you keep", "in the past", …) matched 29 more. Of the 93 read, 12 were field
    records already in the set, and 11 qualified: they relied on something stored and a searchable gold file
    was born before them. The rest asked about in-session state or had no stored answer.
  - Gold was labelled blind from the stores (grep, Read, the agent's reply in the transcript) before either arm
    ran on any query.
- **Branches.** ADOPT → phase 4: an opt-in `--fuse` in `cc-memory-search` (lazy import, FTS5 fallback with one
  stderr line, a `fuse` field in the state log row), never default, never on a hook path. DROP → nothing more
  is built; reopen only on a gain at p < 0.05 on ≥40 operator-worded queries.
- **Deviation known at registration.** 1. **n < 40.** 26 scorable units (15 field + 11 transcript) after 93
  cue-matched prompts, against the plan's target of ≥40. Stopped there as the brief directs. A significant
  result needs at least 5 wins to 0 (or 7 to 1) among untied pairs.

**Results (run 2026-09-28). Verdict: DROP. Fusion did not win on operator wording, and its R@1 fell.**
Harness `docs/research/memory-eval/fusion_eval.py` (tests in `tests/memory-recall-eval.bats`), run with a
private venv (model2vec 0.9.0, numpy, no torch). Raw per-query ranks stay private in
`~/.claude/autonomy/memory-eval/wave-e/4b/results.json`. Corpus per project scope, as of each query:
personal 476 docs, reso 1,119, infra 869, voiceink 385, fde 384.

| style | n scored | arm | R@1 [95%] | R@5 [95%] | MRR [95%] | top 1 supersedes |
|---|---|---|---|---|---|---|
| operator (`op`) | 21 | A FTS5 | 0.333 [0.17, 0.55] | 0.429 [0.24, 0.63] | 0.368 [0.20, 0.58] | 0 |
| operator (`op`) | 21 | B fused | 0.238 [0.11, 0.45] | 0.381 [0.21, 0.59] | 0.338 [0.18, 0.55] | 0 |
| agent (`ag`) | 11 | A FTS5 | 0.636 [0.35, 0.85] | 0.818 [0.52, 0.95] | 0.705 [0.41, 0.89] | 0 |
| agent (`ag`) | 11 | B fused | 0.545 [0.28, 0.79] | 0.818 [0.52, 0.95] | 0.667 [0.38, 0.87] | 0 |

- **Primary (`op`, rank of first gold, 11 past the top 10):** B 7 wins, 3 losses, 11 ties, one-sided
  p = 0.172. R@1(B) 0.238 < R@1(A) 0.333. Both conditions fail, so DROP.
- **Replication on `agent_query` (field records):** 1 win, 2 losses, 8 ties, p = 0.875. §5.1's 6-0 did not
  reproduce on this corpus and scope.
- **By source (`op`):** field records 5 wins, 1 loss (11 scored); transcript queries 2 wins, 2 losses (10).
  Fusion helps deep ranks (5 of the 7 wins lift a gold from past 10 into ranks 5-10), and it pushes FTS5's
  near-top hits down (R-wrap 1 → 30, T01 4 → 20, T04 1 → 2): that is the R@1 loss.
- **Superseding top 1 (the #47 class):** 0 in both arms, over all 30 records.
- **Cost of B:** a fresh process with the model cached answers one query in 0.85-0.92 s, against 1.0 s for
  FTS5 alone in the same probe (the difference is disk-cache noise). The model loads in 0.30-0.37 s (4.5 s on
  first use, download included). A fused query takes a mean of 59 ms (max 123 ms) over 49 queries,
  including each project's first pass that encodes its heads. Peak RSS is 135-140 MB for one query and
  278 MB for the full run, against 42 MB for FTS5 alone. On disk: a 103 MB venv and a 117 MB model cache.

**Branch taken: DROP.** Nothing more is built; `cc-memory-search` stays FTS5-only. *Reopen only on* a gain at
p < 0.05 on ≥40 operator-worded queries.

**Deviations from the pre-registration.**
2. **21 units scored, not 26.** Five more records came out gold-missing under the pre-registered rules. #88 and
   T06: the gold is a project topic in the reso store, outside the infra project scope (reachable only with
   `--all`). R-wrap2 and R-tracked: the gold lessons were first added on 2026-09-17T23:30Z, after the queries,
   when the text still lived inside the rules file. #58: the gold file was born 17 s after its prompt, which
   created it. `field-queries.json` calls all five time-valid; file birth says otherwise.
3. **A harness fix after the pre-registration commit, before any scored run** (`da8de49d3`): rules-hook blame
   had silently fallen back to file birth in reso's checkout, which is flagged `core.bare`, and in a subdirectory.
4. **The #47 supersede finding cannot reproduce on today's text.** #47's top FTS5 hit is still the per-bottle
   pipeline playbook §5.11 named, but that file no longer carries a `Replaces:` line.
5. **Warm latency is not isolated.** The 59 ms mean includes each project's first head-encoding pass, so pure
   per-query latency is lower.

### 5.20 Wave E #24 — candidate extractor, Stage 0 (`--dry-run`)
**Pre-registration (committed 2026-09-28, before any scored run).**

*Rule (plan § Wave E, verbatim):* "#24: on a hand-labelled sample of ≥50 Stage-0 candidates, ≥90% pass every
anti-capture class, AND it recovers ≥3 of the 4 never-written operator rulings (gap-2 #47, #58, #66/67, #70
family) from their transcripts; else drop." Stage 0 writes nothing to any memory store.

*Tool.* `bin/cc-memory-extract --dry-run` (`4180921d6`): eligible = cli entrypoint, ≥2 operator prompts, cwd not
under `/tmp` or `/private/tmp`, transcript written in the last 30 days (385 of 4,384 transcripts on 2026-09-28).
Input is operator turns plus ≤1,500 chars of preceding assistant text, no tool results, fenced as untrusted.
Model `claude-haiku-4-5-20251001` via `claude -p --setting-sources ''` with no tools, at most 5 candidates per
call, 40,000-char chunks.

*Sample.*
- **Targets (4 rulings, 5 sessions), all eligible:** #47 `5e498dc5` (turn 2026-09-12T03:14:12Z); #58 `61853387`
  (2026-09-14T03:35:46Z); #66/67 family `09eb03c8` (personal cwd, 09-14/15) and `9d0a2a8d` (infra cwd, turns
  09-15T12:40Z-18:40Z); #70 family `19f6b94b` (2026-09-16T13:39:07Z and 16:33:29Z). The 09-16 kitty session in
  `/private/tmp/wt-kitty-overlay` (`0a92dbc5`, where "Then the draggable one" was said) is ineligible by the filter
  and is not a target.
- **Random:** eligible non-target sessions in the order of `random.Random(24).shuffle` over the sorted eligible
  ids; the first 40, then further batches of 20 from the same order until the run has ≥50 non-target candidates.

*Labelling.* If there are more than 60 non-target candidates, a seeded random 60 (`random.Random(24).sample`) is
labelled; otherwise all of them. Each labelled candidate gets one boolean per anti-capture class, judged on the
candidate as a would-be memory entry: transient error; environment-specific one-off; lucky path; unverified
negative tool-claim; already indexed (the same rule was in any store before the source turn, checked with
`bin/cc-memory-search --all` and grep over the stores, with file birth times). Plus `promotable` (durable,
generalizable and correct). A candidate passes iff it fails no class. Target-session candidates are judged for
recovery only and are outside the pass-rate sample (they were chosen, not sampled). The labeller is this agent,
reading the candidate and its source turn; it is not blind to the tool.

*Recovered* = at least one candidate from that ruling's session(s) whose body states the ruling:
- #47: the operator's reference-image practice: going through "at least 4MB" Google Images results by hand.
- #58: do not start implementing until the operator signs off (research, then plan, then sign-off).
- #66/67: the kitty pane title must stay click-to-drag, as a standing requirement that other title-bar changes
  (styling, overlay) must not trade away.
- #70: no mannered prose: say what you mean directly and literally, not through metaphor or flourish.

*Primary test and branches.* PASS iff the labelled pass rate is ≥90% (point estimate, n ≥ 50) AND recovered ≥3/4;
otherwise DROP. Reported beside it: Wilson 95% CI, per-class failure counts, promotable share (the older 50%
gate, secondary only), model calls and wall time. PASS ⇒ build #25 (§5.21); DROP ⇒ #25 is dropped unbuilt.

### 5.21 Wave E #25 — transcript capture scan, dry-run verdicts
*Pending: owned by the Wave E teammate `tme-24`; decided by #24's Stage-0 verdict.*

### 5.22 Wave E #27 — provenance-and-verification tier
**Verdict: DROP.** A non-prose channel exists. It has never carried a delivered-and-used event, and §5.17
makes that the price of any push consumer.

**Pre-registration** (written 2026-09-28T16:56:52Z, before any #27 measurement;
`~/.claude/autonomy/memory-eval/wave-e/27/preregistration.md`). The plan rule is "adopt only with a delivery
mechanism other than prose (X7)". The operational rule: **ADOPT iff** (a) a non-prose channel pushes text at the
moment a memory entry is written (a hook on the write, X6-probed), **AND** (b) that channel's own live log
shows ≥1 delivered-and-used event (§5.17's keep rule for #6 and #10), **AND** (c) the claim class a receipt
guards is present (≥1 entry written in the last 30 days that states a measured or negative tool claim without
its conditions). Else DROP, naming which leg failed.

| leg | measured (2026-09-28, all stores read-only, 2,316 real store dirs) | holds? |
|---|---|---|
| (a) channel | #10's `backup-before-write` new-topic branch pushes `additionalContext` on a `Write` to a new `*/memory/*.md` or `docs/lessons/*.md`, and passed its X6 live probe in Wave B | yes |
| (b) delivered-and-used | `mem-neighbours.jsonl` holds 1 row, and it is the X6 probe's own sandbox (`/var/folders/…/proj/memory/`). The live IDL holds 0 `backup-before-write:neighbours` rows. #35's write runs gave #10 nothing to catch (§5.17). Two topic files were born after the branch went live (16:16Z and 16:20Z). Neither was created by a `Write` tool call that transcript search could find, so the branch, which sees `Write` only, had nothing to see | **no** |
| (c) claim class present | 294 topic files born in the last 30 days. 91 carry a negative tool-claim line (crude regex: a negation beside a tool name). 71 of those 91 carry no condition token (binary version, headless/interactive, config dir). `^Receipt:` lines in any store: 0 | yes |

The need is real, since leg (c) holds: 71 recent entries state a tool claim with no conditions, the exact
over-generalisation §3.23-3.27 names. The only non-prose delivery path, though, is #10's message, and it has
no evidence of use. Adding a receipt clause to it would be a push consumer added on faith, which §5.17's
no-gain branch rules out. A prose `Receipt:` line is ruled out by X7 (measured uptake 0/54, 2/64).

*Reopen only if* `scripts/mem-neighbours-outcome.py` shows ≥1 delivered-and-used new-topic advisory. Then add
one receipt sentence to that same message ("if this entry states a tool claim, record the command, its output
and the conditions: binary/version, headless|interactive, config dir"), and measure adoption as the share of
`^Receipt:` or conditions-bearing claim lines in topics born after the change, against this section's 71/91.

**Deviations.** 1. The claim scan is a regex screen, not hand-labelled. It decides nothing, because leg (b)
fails on its own. 2. #10's live window is short: converged 2026-09-28 early, read at 17:00Z. Leg (b) reads
"no evidence yet", which the reopen condition covers.

### 5.23 Wave E #36 — adherence at the moment of action: inventory, fixtures, PRE-REGISTRATION
*Pending: owned by the Wave E teammate `tme-36a`, which writes the pre-registration here before any scored run.*

### 5.24 Wave E #36 — results
*Pending: owned by the Wave E teammate `tme-36b`, which replaces this line with the A/B results and verdict.*

---

## 6. Trust assessment of TrueMemory's claims

| Claim | Status | Evidence |
|---|---|---|
| LoCoMo 93.0% (SOTA-adjacent) | Real harness output, but **adds nothing over full context** | The paper's own oracle is 92.99%. Top-100 of 369-689 messages goes to the answerer. |
| Judge validity | **Weak** | "Be generous". A 200-token cap after a CoT prompt. About 31% of credit comes from answers with no final answer. Manual audit: 10-20% false positives (n=40, ESTIMATED). |
| LongMemEval 87.8% leads | **Not supported** | RAG scores 87.0, inside TM's 86.6-88.6 run spread. The badge shows the oracle 92.0. The `_s` baselines have no result files. |
| BEAM-1M 76.6% SOTA | **Not supported** | Official rubric and Kendall-τ scoring unused. A stronger judge drops it to 51.7% (#716, open). |
| Gate AUC 0.788 / 0.730 / 0.816 | **Unverifiable** | Sweeps gitignored, harness skips, maintainer's #280 says "possible hallucinations". The gate is disabled in the benchmarks. |
| "Superseded, not deleted" (`ingest/dedup.py:11`) | **False** | The code overwrites in place (`storage.py:1178`). |
| Contradiction resolution | **Unproven** | Empty in production until #455/#580. 1/7 phrasings detected. #716: 6/6 → 0/6 with a stronger judge. |
| Per-prompt recall in Claude Code | **Not delivered (MEASURED-run)** | Top-level `additionalContext` is dropped; only `hookSpecificOutput.additionalContext` reaches the model. Live probe 2026-09-27, `claude -p` with a throwaway hook printing a marker token: top-level form read `NONE`, nested form returned the token, for both UserPromptSubmit and SessionStart, on 2.1.114 and 2.1.280. TM's hooks print the top-level form (`session_start.py:752`, `user_prompt_submit.py:831`). No TM test checks what CC consumes. |
| ~80 MB per session | **True only while the daemon is up** | 0.7 GB and 8-17 s per recall hook once it idle-exits. |
| Robustness engineering (flock, SAVEPOINT swap, deadline, quarantine) | **Real and tested** | 40 lock/SAVEPOINT tests pass; kernel-released flock confirmed by probe. The weakness: removing the flock fails only 1 of 72 tests. |
| Issue tracker | **High value as a failure catalogue** | 383 of 393 issues are owner-filed agent audits, with little external usage signal. The failure classes themselves are real and transferable: silent no-ops, benchmark ≠ product, producer-only tests. |

Net: TM's numbers do not show that its memory mechanisms work. Its code and issues are good evidence
of **how agent memory fails**, and that is what we extracted.

---

## 7. Method and receipts

**Method.**
- 11 axis studies: TM capture, gate, lifecycle, retrieval, injection, ops and external evidence; our
  read, write and usage paths; and an empirical retrieval bake-off.
- 34 candidates, each judged by three independent lens workers.
- Workers ran read-only against the repo and every memory store. TM code ran only in `/tmp` venvs with
  a sandboxed HOME and telemetry off.
- The clone is shallow (50 commits from 2026-06-11), so earlier history came from `gh`.
- Conviction numbers are synthesis judgments over the lens convictions and are not measurements.
- **Gap pass.** Five follow-up workers each tested one gap the first synthesis left open:
  - native passes (static reads of four CC builds);
  - a replay of the real misses with time-valid gold;
  - uptake of prose pull lines (transcript natural experiments plus the f3 replay);
  - liveness of the new branches;
  - the `sessions_fts` deleter (DB copies, freelist walk, stress reproduction).
  All ran read-only outside `/tmp`. The synthesiser re-checked the claims that changed dispositions or
  targets: `CLAUDE.global.slim.md:47`, the 4 slim symlinks, the migration heredoc at
  `session-index-helpers.sh:228-236`, the `autoDreamEnabled` gate string in `_cc_strings.txt`, and the
  `install.sh:340` globs. All five matched.

**Hygiene incident.** `~/.truememory/ingest.lock` was created at 19:27 by `lockprobe_efficacy.py`,
which imported TM's pipeline without redirecting HOME (`ingest/pipeline.py:84-87` resolves
`Path.home()` at import time). It is the only artefact outside `/tmp`. The lead removed it after the run (it held one pid; the directory held only that file). Any future TM run must set `HOME`,
`TRUEMEMORY_INGEST_LOCK` and `TRUEMEMORY_TELEMETRY=off` before import. The gap pass added no artefact
outside `/tmp`. Its A/B dry-run directory `gap3/ab-dry/` remains in `/tmp` because the permission layer
refused its `rm`.

**Operator decisions this synthesis does not take.**
- Migration 0036, the situational exclude, is still open (`REPORT.md:66-68`). #1 therefore derives its
  wording from settings rather than flipping a constant.
- Whether to relax R2 on the strength of #11.
- The rotor's routing destination.
- Registering any new hook, which is an operator-run c10 migration. #6 and #10 were designed to avoid needing one.
- **New (gap 1): pin `autoDreamEnabled:false` in all 5 account `settings.json` files** (`~/.claude`,
  `~/.claude-{next,secondary,tertiary,quaternary}`).
  - They are separate real files, and config-mirror does not propagate this key.
  - Effect: none while the flag is off. It fully blocks autoDream if the flag ever reports enabled or
    available, because the setting wins once the flag passes.
  - There is **no equivalent pin for extraction**. Do not reach for `autoMemoryEnabled:false`, which also
    stops MEMORY.md loading.
  - Conviction in the pin: about 85 (ESTIMATED). It costs one key per file and is reversible.
  - It is the operator's call because it edits `settings.json`.
- **New (gap 3): whether to run the `gap3/ab/` A/B** (about $41-52, operator-run). It would only narrow
  the uptake bound for a named CLI. It would not change the direction of any verdict.
- **New (gap 4): #10's deny-once variant**, which delivers the advice before the write at the cost of
  about 55 round-trips a week. Wait for #10's `unresolved` outcome share first.
- **New (gap 4): whether to widen `install.sh:340` and `deploy-parity-assert.sh:551` to `*.tsv`/`*.jq`,
  and make `*.py` want=1.** X1's dereferenced-path rule avoids needing this.

**Notes files.** The Markdown notes are committed beside this doc in `docs/research/truememory-2026-09-27/`. Raw scratch (the `gap1/`-`gap5/` and `tm-empirical/` directories, harnesses, result JSONs, the CC strings dump) stayed in `/tmp/tm-research/` and is not preserved.
- Axis studies:
  - TM side: `tm-capture.md`, `tm-gate.md`, `tm-lifecycle.md`, `tm-retrieval.md`, `tm-injection.md`, `tm-ops.md`, `tm-external.md`.
  - Our side: `our-read.md`, `our-write.md`, `our-usage.md`.
  - Bake-off: `tm-empirical.md`, with harness and result JSONs in `tm-empirical/`.
- Efficacy lens: `efficacy-*.notes.txt` (19 files), `efficacy-delivered-surface-reach-audit.md`,
  `efficacy-local-store-history.md`, `efficacy-userprompt-pointer-recall.txt`; issue extracts
  `eff-ledger-issues.txt`, `eff-supersede-issues.txt`.
- Premise lens:
  - `premise-dna-install-copy-truememory.notes.txt`, `premise-episodic-session-recall.md`, `premise-forget-cascade.notes.txt`,
    `premise-frontmatter-validator-env-clamp.notes.txt`, `premise-injection-sanitizer.notes.txt`,
    `premise-provenance-and-verification-tier.md`, `premise-speech-act-nudge-trigger.md`, `premise-structured-supersession.md`;
  - `premise/memory-eval-harness.md`, `premise/session-index-coverage.md`;
  - `premise-consol/notes.txt`, `premise-ledger/notes.txt`, `premise-brieftime/notes.txt`.
- Fit lens: `fit-*.notes.txt` (21 files), `fit-episodic/NOTES-fit-episodic-session-recall.md`,
  `local-store-history-fit.md`; scratch in `fit-{sym,fts,recall,episodic,extractor,tn,neigh,consol,supersede,reach,readledger,speechact,brief}/`.
- Raw data: `relearning-hits.tsv` (345 rows), `prompts-typed.jsonl` (2,650 prompts), `corrections-all.tsv`,
  `an2.out`, `an3.out`, `scan/files3.jsonl`, `our_write_*.out`, `our_write_nn_sample.txt`, `lesson-dates.txt`.
- Gap pass:
  - `gap-1.md`, with scratch `gap1/` (`L288953.txt`, `dream-chunk.txt`, `store-eligibility.txt`).
  - `gap-2.md`, with scratch `gap2/`: `sessprobe.py/.json`, `replay.py`, `run_replay.py` →
    `replay_results.json`, `hist_rules.py`, **`field-queries.json`** (the seed for #5), and the dialogue
    excerpts `dace.txt`, `d71.txt`, `adb-after.txt`.
  - `gap-3.md`, with scratch `gap3/`: `pullscan.py`, `tokeff-scan.jsonl`, `natexp.py`, `nat-all.jsonl`,
    `A-clauses.tsv`, the A/B in `ab/`, and the dry run in `ab-dry/`.
  - `gap-4.md`, with scratch `gap4/`: `order.py`, `births.py`, `bash7d.log`, `tx1d.txt`, `ctx-sample.txt`.
  - `gap-5.md`, with scratch `gap5/`: DB copies `session-index.db`, `old.db` and `exp.db`; `race/stress.sh`,
    `stress_timeout.sh` and `zeros.log`; `errexit_probe.sh` with fake HOME `fh/`.
- Reference dumps: `_cc_hooks.md` (CC hook docs), `_cc_strings.txt` (CC 2.1.278 strings), `gate-scratch/paper.txt` (arXiv PDF text).
