# TrueMemory upstream fix kit

Everything needed to fix TrueMemory itself, should we decide to contribute. The study that
produced it is `../truememory-2026-09-27.md` (§4 rejections, §5 measurements, §6 claims). This file
turns those findings into a work list against TrueMemory's own code.

**Status: parked.** On 2026-09-27 the findings went to TrueMemory's author (§6 below). Nothing has
been contributed. Whether to contribute is the operator's call, and so is signing TrueMemory's
relicensing CLA, which any upstream PR requires.

**Licence boundary.** TrueMemory is AGPL-3.0-only plus a relicensing CLA. Code written *for a PR to
TrueMemory* lives in a fork of TrueMemory under its licence. Nothing from TrueMemory is copied into
this repo: our own adoptions (docs/plans/TRUEMEMORY_ADOPTION.md) are independent implementations of
ideas.

## 1. Baseline to work from

- Repo: `https://github.com/buildingjoshbetter/TrueMemory`, studied at `063e5b8` (v0.7.6.2).
  Every file:line below refers to that commit; re-check against HEAD before editing. Paths are
  relative to the `truememory/` package directory, except those starting with `tests/` or
  `benchmarks/`, which are relative to the repo root. All 20 cited files were confirmed present at
  `063e5b8` on 2026-09-27.
- Reproduce: `git clone https://github.com/buildingjoshbetter/TrueMemory && git -C TrueMemory checkout 063e5b8`
- On 2026-09-27, HEAD failed with mcp 2.2.0, CI had been red since 2026-08-29, and the PyPI 0.7.6.2
  release still installed. Fix #9.1 first, or every other PR lands on a red CI.

## 2. Tools in this folder

| Path | What it does |
|---|---|
| `hook-probe/run.sh [claude-binary]` | Proves whether Claude Code delivers a hook's `additionalContext`. Four arms: UserPromptSubmit and SessionStart, each top-level and nested. About 2 minutes, Haiku. The acceptance test for fix #1. |
| `empirical-harness/` | The retrieval bake-off: `baselines.py` (ripgrep, FTS5 body/fielded, index-only), `hybrid_lite.py` (FTS5 + model2vec RRF, the 60-line comparator), `tm_eval.py` (TrueMemory search; `--patch-reranker 1` clones reranker tensors after load), `rerank_lite.py`, `common.py` (paths), `sandbox-env.sh` (env for a sandboxed run). |
| `empirical-results/` | `queries.json` (50 symptom-phrased queries with gold file names) and every result and raw ranking JSON. Per-query rankings let a fix be scored against the same 50 queries. |
| `ab-harness/` | The task-level A/B harness (`run-ab.sh`, `score.py`, `tasks.tsv`). Plan item #35 extends it. |
| `review-for-author.md` | The measurements summary sent to TrueMemory's author. |

**Running the harness.** It expects a corpus at `/tmp/tm-sandbox/corpus`: copies of
`~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/*.md` (prefix `memory/`)
and this repo's `docs/lessons/*.md` (prefix `lessons/`). The corpus is private, so it is regenerated,
never committed. Before importing TrueMemory, source `sandbox-env.sh` AND set
`TRUEMEMORY_INGEST_LOCK` inside the sandbox: `ingest/pipeline.py:84-87` resolves `Path.home()` at
import time, and the study leaked one `~/.truememory/ingest.lock` that way. Never run TrueMemory's
`install.sh` or any setup subcommand against a real config: the installer rewrites Claude Code hooks.
Install with `uv pip install -e <clone>` into a venv under the sandbox. Budget: 911 MB venv, 91 s
install, 327 s ingest, 1.46 GB peak RSS.

## 3. Fix list, ordered by what TrueMemory's users gain

Each item: the defect with its evidence, the change, and the test that proves it.

### #1 Hook output never reaches the model in Claude Code (measured)
- **Defect.** `ingest/hooks/session_start.py:752` and `ingest/hooks/user_prompt_submit.py:831`
  print `{"additionalContext": …}` at the top level. Claude Code reads it only under
  `hookSpecificOutput`. `hook-probe/run.sh`: top-level reads NONE, nested returns the token, on
  2.1.114 and 2.1.280, for both events.
- **Change.** Print `{"hookSpecificOutput": {"hookEventName": "<SessionStart|UserPromptSubmit>", "additionalContext": …}}`.
  Check the other adapters (`hooks/adapters/*.py`, `hooks/core.py`) for the same shape.
- **Test.** A unit test that asserts the rendered JSON shape and event name; plus `hook-probe/run.sh`
  against the patched hook as the end-to-end check.

### #2 Default search pays 1,800x latency for a gain the test cannot distinguish (measured)
- **Defect.** Full search with the MiniLM cross-encoder: R@1 0.94, 23 s/query (49.7 s unpatched),
  1.46 GB. TrueMemory without the reranker: 0.86 at 489 ms. Field-weighted FTS5 (name 10, description
  5, body 1) + model2vec fused with RRF: 0.90 at 12.6 ms, 187 MB. Full vs the RRF script: 3 wins to 1
  (p = 0.625). Also: min-max score normalisation makes scores impossible to threshold
  (`fts_search.py:48-73`); no stopword removal makes cost superlinear (#689, p95 9.5 s at 10k).
- **Change.** Make the reranker opt-in (it is already skipped on hook paths, #690). Weight FTS5 by
  field. Replace min-max with rank-based fusion or raw bm25. Add stopword removal.
- **Reranker crash.** mmap-backed weights returned NaN or SIGBUS in standalone probes. The harness
  workaround (`tm_eval.py` `--patch-reranker 1`): clone every parameter tensor after load.
- **Test.** Re-run `empirical-harness` on the same 50 queries: R@1 within noise of 0.94, p50 latency
  under 50 ms.

### #3 Benchmarks cannot show what the memory features add (read)
- **Defect.** LoCoMo 93.0% ties the paper's own full-context run (92.99%); the chats fit in context;
  the encoding gate is off in every benchmark run; the judge prompt says "Be generous"
  (`benchmarks/locomo/scripts/bench_truememory_pro.py:94-103`); the benchmark path is not the product
  path (#451, #456); BEAM-1M drops to 51.7% with a stronger judge (#716); the gate AUCs are
  unreproducible (#280).
- **Change.** Benchmark on histories longer than the context window, with the gate on, through the
  same code path users run, against "paste as much history as fits". Use a strict judge and the
  official rubrics. Commit the gate sweeps so the AUCs reproduce.
- **Test.** The benchmark report carries all three arms (TrueMemory, full-context-that-fits,
  no-memory) and the judge prompt.

### #4 Merging overwrites correct facts (measured)
- **Defect.** Dedup UPDATE overwrites in place (`storage.py:1150-1182`, `:1178`), contradicting
  "superseded, not deleted" (`ingest/dedup.py:11`). It overwrote one person's row with another's
  fact, and Production with Staging via an "as of" marker (`ingest/markers.py:82-83`). "Actually…"
  superseded nothing; 1 of 7 correction phrasings detected; "office" filed a Heroku→Fly migration
  under office_location.
- **Change.** Insert the new fact and mark the old one superseded (keep both, link them). Require the
  same subject before a merge. Treat regex contradiction detection as a suggestion, not an action.
- **Test.** The two measured cases as regression fixtures: after ingest, both old and new rows exist
  and the old one is marked superseded.

### #5 Encoding gate scores length, not value (measured)
- **Defect.** r(log length, score) = 0.876; 0 of 19 facts of ≤50 chars pass, 139 of 140 over 200;
  short durable rules pass 2 of 185; L3 `f_length` weight 8.54 dominates. Unanchored greeting-prefix
  regex rejects "Supabase…", "History…", "Your…", "Hidden…", "High…" (`ingest/encoding_salience.py:285-288`).
  PE latches fail open permanently (`ingest/encoding_gate.py:507,551`). L5 ships at α = 0.2 against
  its own test's α = 0 (`tests/test_l5_surprise_rerank.py:11-16`). The gate-eval tests skip
  (`tests/test_gate_eval_harness.py:21-22`).
- **Change.** Anchor the regex. Make the PE latch re-arm. Refit or drop `f_length`; evaluate against
  length-matched negatives. Ship L5 at the tested α.
- **Test.** Length-matched fixture set: short durable rules must pass at the same rate as long ones.

### #6 Regex extractor stores fragments (measured)
- **Defect.** Over 40 transcripts: 1,089 "facts", 976 under 25 characters; 141 would bypass the gate
  as corrections (`ingest/encoding_gate.py:251-276`); 16 of 19 eager hits were Claude Code Stop-hook
  feedback, not user content.
- **Change.** Drop hook-injected text (Stop-hook feedback, system reminders) before extraction; set a
  minimum length; route corrections through the gate.

### #7 Safety and privacy (read)
- MCP instructions steer the model to recall API keys, SSH credentials and database passwords
  (`mcp_server.py:373-376`).
- Telemetry is on by default, and a hook extracts email addresses (`telemetry.py:45,160-184`;
  `ingest/hooks/user_prompt_submit.py:681-731`).
- `sanitize_injection_content` (`_sanitize.py:26-47`) escapes too little, and one further security finding is withheld until the author has fixed it.
- The installer rewrites Claude Code hooks and adds a CLAUDE.md block calling MEMORY.md "a lossy,
  potentially stale cache" (`ingest/CLAUDE_TEMPLATE.md:3-18`).

### #8 Silent no-ops (read, from TrueMemory's own tracker and code)
Clustering did nothing on every install (#696); the temporal filter was dead through a key mismatch
(#466); the entity boost is never written back into the score (`salience.py:474-481`); the trajectory
×1.3 demotes the newest rows; the per-exchange store shipped writing 0 rows (#634); the MEMORY.md
migrator duplicates on re-run and drops topic files (`ingest/migrate_memory_md.py`); the stale-session
scanner's hardcoded roots (`ingest/hooks/_shared.py:34-45`, `session_start.py:517`) matched 0 of 40
of our transcript paths. Each needs a test that fails when the feature does nothing.

### #9 Runtime and robustness (measured)
1. HEAD breaks on mcp 2.2.0; CI red since 2026-08-29.
2. Once the daemon idle-exits, each recall hook loads Qwen3 in-process: 678-709 MB, 8-17 s. MPS runs
   out of memory and the fallback sticks to CPU with 1 thread. An orphaned daemon held 1.9 GB.
3. `ingest/pipeline.py:84-87` resolves `Path.home()` at import time.
4. Removing the ingest flock fails only 1 of 72 tests: the lock is under-tested.

## 4. What TrueMemory does well (keep in any rewrite)

The lock and SAVEPOINT engineering is real and tested (40 tests pass; kernel-released flock confirmed
by probe). The quoted-OR FTS5 query builder (`fts_search.py:31-39`) is injection-safe. The
stale-session scanner pattern (`session_start.py:455-624`: non-blocking flock, held watermark, prune
before early return) is sound. The issue tracker is a good catalogue of silent memory failures.

## 5. Open questions a contributor would need answered

- Which tier is the author's default target (edge, base, pro)? Our measurements used edge
  (model2vec potion-base-8M + MiniLM reranker, CPU).
- Would the author accept making the reranker opt-in, or prefer a cheaper default reranker?
- Is a breaking change to hook output acceptable for non-Claude adapters (Cursor, Codex, Gemini,
  OpenClaw), which may read the top-level form?

## 6. Outreach record (2026-09-27)

The operator messaged TrueMemory's author with the comparison, attaching `review-for-author.md`.
Which exact version went out is not recorded here; the operator reported "I already sent off" after
the full comparison was drafted. A shorter four-point version (hook fix, speed at the same accuracy,
a benchmark against paste-the-whole-history on long chats with the gate on, merging without
overwriting) was written afterwards. No reply recorded yet.
