# TrueMemory review — measurements from one Claude Code user

Date: 2026-09-27. TrueMemory at `063e5b8` (v0.7.6.2). Paths below are relative to the TrueMemory
repo. "Measured" means we ran it; "read" means we read the code; "claimed" means the README, paper
or an issue says so.

Our setup, for context: Claude Code's built-in auto memory (a folder of Markdown files per
project, one fact or lesson per file, plus a MEMORY.md index loaded into every session, capped at
25,000 characters), with our own hooks and scripts on top. About 640 memory and lesson files were
used as the test corpus.

## 1. Hook output does not reach the model in Claude Code (measured)

TrueMemory's SessionStart and UserPromptSubmit hooks print `{"additionalContext": "..."}` at the
top level of the JSON (`ingest/hooks/session_start.py:752`, `ingest/hooks/user_prompt_submit.py:831`).
Claude Code only reads `additionalContext` inside `hookSpecificOutput`.

Test: a throwaway hook that prints a marker token, then `claude -p` asked whether the token is in
context.

| Hook output | Claude Code 2.1.114 | Claude Code 2.1.280 |
|---|---|---|
| `{"additionalContext": "PROBE-…"}` | not seen | not seen |
| `{"hookSpecificOutput": {"hookEventName": "<event>", "additionalContext": "PROBE-…"}}` | seen | seen |

Same result for UserPromptSubmit and SessionStart. Fix: wrap the output as in row 2, with
`hookEventName` matching the event. A test that asserts the rendered JSON shape would catch a
regression; no current test checks what Claude Code consumes.

## 2. Retrieval on our corpus (measured)

640 files, 2.4 MB, 50 hand-labelled queries phrased as the symptom an agent would hit, each with
one known correct file. R@1 = correct file ranked first.

| Method | R@1 | R@5 | Latency per query | Peak RAM |
|---|---|---|---|---|
| ripgrep, rank by distinct terms matched | 0.36 | 0.64 | 159 ms | — |
| Always-loaded index lines only | 0.44 | 0.52 | — | — |
| SQLite FTS5 (porter unicode61), fielded name/description/body | 0.78 | 0.88 | 2.9 ms | 50 MB |
| FTS5 + model2vec potion-base-8M, fused with RRF | 0.90 | 0.94 | 12.6 ms | 187 MB |
| TrueMemory hybrid, no reranker | 0.86 | 0.96 | 489 ms | — |
| TrueMemory full (MiniLM cross-encoder reranker) | 0.94 | 0.96 | 23 s (49.7 s unpatched) | 1.46 GB |

- TrueMemory full vs FTS5+model2vec: 3 queries won to 1 (sign test p = 0.625, not significant).
  Nearly all of the vector and reranker gain came from the 10 paraphrase queries.
- Setup cost: 911 MB venv (torch 553 MB), 91 s install, 326.7 s to ingest 640 files (p50 11 ms,
  max 23.9 s per `add()`).
- The unpatched reranker returned NaN or SIGBUS in standalone probes (mmap-backed weights); the
  recorded end-to-end run was not affected.
- Threats to validity: one author wrote both the queries and the gold labels; n = 50.

## 3. Capture, gate and merging on our data (measured unless noted)

- **Encoding gate acts as a length filter:** correlation of score with log length r = 0.876; 0 of
  19 facts of ≤50 characters pass, against 139 of 140 over 200 characters; short durable rules pass
  2 of 185. The L3 `f_length` weight (8.54) is by far the largest. The greeting-prefix rule at
  `encoding_salience.py:285-288` is unanchored and rejects lines starting "Supabase…", "History…",
  "Your…", "Hidden…", "High…". PE latches fail open permanently (`encoding_gate.py:507,551`). L5
  ships at α = 0.2 against its own test's α = 0 recommendation (`tests/test_l5_surprise_rerank.py:11-16`).
- **Regex extractor:** over 40 transcripts it produced 1,089 "facts", 976 of them under 25
  characters; 141 would bypass the gate as corrections (`encoding_gate.py:251-276`).
- **Dedup and contradiction handling:** the dedup UPDATE overwrote one person's row with another
  person's fact, and Production with Staging via an "as of" phrase (`ingest/markers.py:82-83`).
  UPDATE overwrites in place (`storage.py:1178`), which contradicts "superseded, not deleted" in
  `ingest/dedup.py:11`. A correction starting "Actually…" superseded nothing; the word "office"
  filed a Heroku→Fly migration under office_location; 30 agent-style messages produced 25 timeline
  rows. Trait profiles are substring unions with no decay (`personality.py:999-1023`).

## 4. Runtime cost (measured)

Once the model daemon idle-exits, each recall hook loads Qwen3 in-process: 678-709 MB and 8-17 s.
MPS runs out of memory and the fallback stays on CPU with one thread. An orphaned daemon held
1.9 GB. Clustering silently did nothing on every install (#696); the temporal filter was dead
through a key mismatch (#466); the entity boost is never written back into the score
(`salience.py:474-481`).

## 5. Benchmark claims (read)

| Claim | Status | Evidence |
|---|---|---|
| LoCoMo 93.0% | Ties the paper's own full-context baseline (92.99%) | The top 100 of 369-689 messages go to the answerer; the conversations fit in context anyway |
| Judge validity | Weak | The judge prompt says "Be generous"; a 200-token cap after a chain-of-thought prompt; about 31% of credit comes from answers with no final answer; manual audit found 10-20% false positives (n = 40, estimated) |
| LongMemEval 87.8% lead | Not supported | RAG scores 87.0, inside TrueMemory's 86.6-88.6 run spread |
| BEAM-1M 76.6% | Not supported | Official rubric and Kendall-τ scoring unused; a stronger judge drops it to 51.7% (#716) |
| Gate AUC 0.788 / 0.730 / 0.816 | Unverifiable | Sweeps gitignored, harness tests skip, #280 flags possible hallucinations; the gate is off in the benchmark runs |
| Contradiction resolution | Unproven | Empty in production until #455/#580; 1 of 7 phrasings detected; #716 shows 6/6 → 0/6 with a stronger judge |
| Robustness engineering (flock, SAVEPOINT swap, deadlines, quarantine) | Real and tested | 40 lock/SAVEPOINT tests pass; kernel-released flock confirmed by probe. Removing the flock fails only 1 of 72 tests |

## 6. Install-time and privacy observations (read)

- The installer rewrites Claude Code `settings.json` hooks and adds a CLAUDE.md block calling
  MEMORY.md "a lossy, potentially stale cache" (`ingest/CLAUDE_TEMPLATE.md:3-18`).
- The MCP instructions steer the model to recall API keys, SSH credentials and database passwords
  (`mcp_server.py:373-376`).
- Telemetry is on by default, and a hook extracts email addresses (`telemetry.py:45,160-184`;
  `user_prompt_submit.py:681-731`).
- One further security finding is withheld until the author has fixed it; it goes to the author privately.
- On 2026-09-27, HEAD failed with mcp 2.2.0 and CI had been red since 2026-08-29; the PyPI 0.7.6.2
  release still installed.
- Importing the ingest pipeline resolves `Path.home()` at import time (`ingest/pipeline.py:84-87`),
  so setting HOME after import still writes `~/.truememory/ingest.lock`.

## 7. What we are taking, as ideas (independent implementations, no TrueMemory code)

- An FTS5 index over the whole memory store, with a quoted-OR query builder
  (`fts_search.py:31-39`).
- Escaping recalled text before it is injected, framed as data rather than instructions.
- A nearest-duplicate check when a memory file is written.
- The stale-session scanner pattern: non-blocking lock, watermark, prune before early return
  (`session_start.py:455-624`).
- The issue tracker as a catalogue of silent memory failures: no-op features, benchmark path ≠
  product path, tests that only check the producer.
