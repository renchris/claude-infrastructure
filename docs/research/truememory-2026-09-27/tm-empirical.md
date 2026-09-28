# TrueMemory vs cheap baselines: retrieval on our own agent-memory corpus

Write-up of an experiment that a network outage interrupted. No step was re-run for this write-up.
Every number comes from the result JSONs, the logs or the harness under
`/tmp/tm-research/tm-empirical/` and `/tmp/tm-sandbox/`. Numbers I derived here (confidence
intervals, sign tests, overlap ratios, rank matrices) came from small read-only python over those
JSONs. Anything the artefacts do not settle is marked **UNKNOWN**.

**Headline.** Measured over 50 queries, recall@1 was:
- TrueMemory full search with the reranker: **0.94**, at about **23 s per query** and **1.46 GB** peak RSS.
- A 60-line FTS5 + model2vec RRF script: **0.90**, at about **13 ms per query** and 187 MB RSS.
- FTS5 BM25 on its own: **0.78**.
- BM25 over the always-loaded indexes alone: **0.44**. Those indexes cannot reach the gold file for 34% of the queries.

The gap between TrueMemory and the RRF script is 3 queries against 1 and is not significant
(p = 0.625).

---

## 1. Method

### Corpus
- **Memory files (496).** Copies of `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/*.md`
  in `/tmp/tm-sandbox/corpus/memory/`. This is every file in that directory except `MEMORY.md`.
  I checked this with a read-only diff of the file lists. The live directory has 497 `.md` files,
  and the only one missing from the copy is `MEMORY.md`.
- **Lessons (144).** Copies of `claude-infrastructure/docs/lessons/*.md` in `/tmp/tm-sandbox/corpus/lessons/`.
- **Size.** 640 documents, 2,398,542 bytes (`results_baselines.json` `_meta`). Median document is
  2,999 chars and the largest is 38,510, so TrueMemory's 50,000-char truncation (`text[:50000]`)
  never cut anything.
- **Indexes.** These live in `/tmp/tm-sandbox/indexes/` and are used only by the index-only baselines:
  - `MEMORY.md`, the hot, always-loaded index: 148 links, 148 files.
  - `agent-operating-lessons.md` and `agent-operating-lessons-situational.md` (the rules hooks):
    144 lesson links, which covers all 144 lessons.
  - `MEMORY_ARCHIVE_2026-H2-COLD.md`, copied from `memory/archive/`. This is the cold index, which is
    **not** auto-loaded: 285 links.
  - Hot plus cold together link 432 of the 496 memory files.

### Queries and gold labels
- `queries.json` holds **50** queries, not the "25+" in the brief: 20 `lexical`, 20 `mixed` and
  10 `paraphrase`. Each query has the fields `id`, `q`, `gold` and `style` and nothing else.
- Gold sets: 35 queries have 1 gold file, 12 have 2 and 3 have 3. That makes 68 gold files in
  total: 52 memory and 16 lessons.
- A query counts as a hit at rank k if **any** of its gold files is at rank ≤ k. MRR uses the first
  gold hit. The code is `common.score`.
- **How the queries were written: UNKNOWN beyond this.** No generation notes were kept.
  - The file's mtime is 15:17. That is about one minute after the corpus copy (15:15–15:16) and
    before any run.
  - The queries are symptom-phrased ("my background nohup job died and its log file is empty").
  - The brief says the agent that wrote them knew the gold files.
- **Measured lexical overlap.** This is the mean fraction of each query's terms (harness tokenizer,
  stopwords removed) that appear in the gold file's slug, name, description or H1:
  lexical 0.55, mixed 0.53, paraphrase 0.34.

### Variants that ran (source: `harness/*.py`)

| Variant | Exact method |
|---|---|
| `rg_distinct_terms` | One `rg -i -c -F` subprocess per query term. Files are ranked by the number of distinct terms matched, then by total hit count. |
| `rg_all_terms_AND` | `rg -i -l -F` intersection over all terms: what an agent gets from chaining `rg -l`. |
| `fts5_bm25_body` | SQLite FTS5, `porter unicode61`, one column with the whole file text, `ORDER BY bm25(d)`, LIMIT 20. The query is the terms OR'd together. |
| `fts5_bm25_fielded_10_5_1` | FTS5 with columns name+H1 / description / body, `bm25(d,0,10,5,1)`, LIMIT 20. |
| `index_only:<idx>` | FTS5 BM25 over the one-line `- [title](file) — hook` entries of the index, LIMIT 40 lines, each line mapped to its file. There are five: hot `MEMORY.md`; rules hooks; cold archive index; always-loaded = hot + rules; all = hot + rules + cold. |
| `m2v_vec_only_{full,head}` | `minishlab/potion-base-8M` (model2vec static embeddings) with cosine over the corpus. `head` encodes H1-or-name + description. `full` encodes the head plus the body. Top 100. |
| `rrf_fts5fielded+m2v_{full,head}` | RRF (k=60) of the fielded-FTS5 top 100 and the m2v top 100. |
| `tm_doc_full` (patch1) | TrueMemory 0.7.6.2, built from `/tmp/truememory-src`. Each file is one `Memory.add(text)`. `Memory.search(q, limit=20)` runs with the cross-encoder reranker. The harness patches the reranker to clone every parameter tensor after load (see §4). Edge tier (`TRUEMEMORY_EMBED_MODEL=edge`): model2vec potion-base-8M embeddings plus the `cross-encoder/ms-marco-MiniLM-L-6-v2` reranker, on CPU. |
| `tm_doc_norerank` | Same database, `search(..., _skip_reranker=True)`. |
| `tm_doc_vec` | Same database, `search_vectors(q, limit=20)`. |
| `tm_doc_full_ASINSTALLED_nanreranker` | Same database with `--patch-reranker 0`, full mode only. It reused the `doc.db` built by the patched run, so no ingest was measured for it. |

Variants that ran only partly or not at all:
- **`tm_chunk_*`**, where each file is split into header + ≤1200-char paragraph groups, with limit 60.
  - Only `norerank` and `vec` printed results, and only to `/tmp/tm-sandbox/run_chunk2.log`. No
    JSON was written, and the log has no `DONE`.
  - `chunk full` (reranked): **UNKNOWN**. It was presumably running when the outage hit.
- **`rerank_lite.py`**, which would rerank the top 5/10/20 of the RRF-lite results with MiniLM.
  The script exists but there is **no output file**, so it did not run or did not finish. Its
  results are **UNKNOWN**.

Some rank caps come from the harness, not the methods:
- TrueMemory returns at most 20 rows (60 for chunk). Rows whose id is not in the idmap are dropped
  before the file dedupe; these are TrueMemory's own `summary` rows, 11 in full mode and 44 in norerank.
- FTS5 returns at most 20 rows, index-only 40 lines, and m2v/RRF 100.

Recall@10 and MRR therefore treat a gold file below those caps as a miss.

Platform: macOS 15.7.9 on arm64 (from the `sample` headers), CPU only, Python 3.12.13.

## 2. Results (n = 50)

| Variant | R@1 | R@5 | R@10 | MRR | Hits@1 / @5 | 95% CI R@1 (Wilson) | Query latency (mean) |
|---|---|---|---|---|---|---|---|
| rg_distinct_terms | 0.36 | 0.64 | 0.76 | 0.485 | 18 / 32 | 0.24–0.50 | 159 ms |
| rg_all_terms_AND | 0.02 | 0.06 | 0.06 | 0.035 | 1 / 3 | 0.00–0.10 | 210 ms (47/50 queries return **zero** files) |
| fts5_bm25_body | 0.76 | 0.86 | 0.90 | 0.809 | 38 / 43 | 0.63–0.86 | 0.85 ms |
| fts5_bm25_fielded_10_5_1 | 0.78 | 0.88 | 0.92 | 0.832 | 39 / 44 | 0.65–0.87 | 2.9 ms |
| index_only: hot MEMORY.md | 0.26 | 0.28 | 0.34 | 0.280 | 13 / 14 | 0.16–0.40 | not recorded |
| index_only: rules hooks | 0.20 | 0.22 | 0.22 | 0.217 | 10 / 11 | 0.11–0.33 | not recorded |
| index_only: cold archive index | 0.38 | 0.44 | 0.50 | 0.414 | 19 / 22 | 0.26–0.52 | not recorded |
| **index_only: always-loaded (hot + rules)** | **0.44** | **0.52** | 0.54 | 0.473 | 22 / 26 | 0.31–0.58 | not recorded |
| index_only: all indexes (hot + rules + cold) | 0.74 | 0.86 | 0.88 | 0.787 | 37 / 43 | 0.60–0.84 | not recorded |
| m2v_vec_only_full | 0.68 | 0.88 | 0.94 | 0.772 | 34 / 44 | 0.54–0.79 | not recorded separately |
| m2v_vec_only_head | 0.82 | 0.90 | 0.90 | 0.854 | 41 / 45 | 0.69–0.90 | not recorded separately |
| rrf_fts5fielded+m2v_full | 0.86 | 0.96 | 0.96 | 0.903 | 43 / 48 | 0.74–0.93 | 24.8 ms |
| **rrf_fts5fielded+m2v_head** | **0.90** | 0.94 | 0.94 | **0.916** | 45 / 47 | 0.79–0.96 | **12.6 ms** |
| tm_doc_vec | 0.60 | 0.82 | 0.92 | 0.707 | 30 / 41 | 0.46–0.72 | 3.3 ms |
| tm_doc_norerank | 0.86 | 0.96 | 0.96 | 0.897 | 43 / 48 | 0.74–0.93 | 489 ms (p50 476) |
| **tm_doc_full (reranker, patched)** | **0.94** | **0.96** | 0.96 | **0.947** | 47 / 48 | 0.84–0.98 | **23,072 ms** (p50 22,663; max 38,798; first call 72.4 s) |
| tm_doc_full as installed (unpatched) | 0.94 | 0.96 | 0.96 | 0.947 | 47 / 48 | 0.84–0.98 | **49,671 ms** (p50 39,486; max 146,018; first call 154.3 s) |
| tm_chunk_norerank (log only) | 0.82 | 0.92 | 0.96 | 0.866 | n/a | n/a | 3,685 ms (p50 2,851) |
| tm_chunk_vec (log only) | 0.78 | 0.90 | 0.90 | 0.827 | n/a | n/a | 28 ms (p50 16) |
| tm_chunk_full | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | n/a | n/a | UNKNOWN |

Hits@1 broken down by query style (lexical /20, mixed /20, paraphrase /10):

| Variant | Lexical | Mixed | Paraphrase |
|---|---|---|---|
| fts5 fielded | 18 | 17 | 4 |
| always-loaded index | 12 | 8 | 2 |
| rrf head | 19 | 20 | 6 |
| tm_doc_norerank | 19 | 18 | 6 |
| tm_doc_full | 20 | 19 | 8 |

Almost all of the reranker's gain and of the vectors' gain over BM25 is on paraphrase queries.

Paired comparisons (exact two-sided sign test on discordant queries, computed here):

| Comparison | Cutoff | Queries only the first finds | Queries only the second finds | p |
|---|---|---|---|---|
| tm_doc_full vs rrf head | @1 | 3 (q13, q36, q48) | 1 (q04) | 0.625 |
| tm_doc_full vs rrf head | @5 | 1 (q36) | 0 | not tested |
| tm_doc_full vs fts5 fielded | @1 | 8 | 0 | 0.008 |
| rrf head vs fts5 fielded | @1 | 6 | 0 | 0.031 |
| tm_doc_full vs tm_doc_norerank | @1 | 4 (q35, q43, q44, q46) | 0 | 0.125 |

- Both vector-fused methods beat plain BM25, and that difference is real at this n.
- TrueMemory's lead over the RRF script is **not** distinguishable from noise with 50 queries.
- `tm_doc_norerank` (TrueMemory's own hybrid without the reranker) scores exactly the same as the
  RRF-lite `full` script: 43 / 48 hits and MRR 0.897 against 0.903.

## 3. Cost: latency, RAM, disk and install

| | FTS5 (stdlib) | FTS5 + model2vec RRF | TrueMemory (edge tier, doc variant) |
|---|---|---|---|
| Dependencies | none: Python's `sqlite3` | `model2vec` + `numpy`. Their install size alone was not measured: **UNKNOWN** | 74 packages including torch 2.14.0, transformers 5.17.0, sentence-transformers 6.1.0, scipy, scikit-learn and anthropic (`install.log`) |
| Install time | 0 | UNKNOWN (installed as part of the TrueMemory venv) | **90.9 s** wall-clock. `/usr/bin/time` gives 90.89 s real, and `install.start` / `install.end` give 1790540139 → 1790540230 = 91 s. "Prepared 74 packages in 1m 26s". |
| Venv on disk | 0 | UNKNOWN | **911 MB** (`du -sh venv`), of which torch is 553 MB. The uv cache is 1.4 GB. |
| Model files | none | potion-base-8M: 30.2 MB safetensors, plus a 30.2 MB ONNX copy in the HF snapshot (`stat -L`) | Same potion-base-8M, plus the MiniLM-L-6 cross-encoder: 90.9 MB safetensors. The whole HF cache is 146 MB (`du -sh /tmp/tm-sandbox/xdg`). `/tmp/tm-sandbox/models/minilm` (88 MB) is a copy the experimenter made, not part of the install. |
| Index / DB on disk | 4.47 MB (`fts5_body.db`, from 2.40 MB of corpus) | FTS5 in memory plus a 640×256 float matrix in memory. No file was written. | **24.8 MB** (`doc.db` + wal + shm). The chunk DB is 22.9 MB + 6.6 MB wal. |
| Build / ingest | 81 ms (body) or 237 ms (fielded) | Encoding the corpus took 2.4 s (head) or 13.3 s (full). Model load took 8.7 s. | **326.7 s** for 640 `add()` calls: p50 11 ms, mean 510 ms, max 23.9 s. The stalls presumably come from TrueMemory's background consolidation, but that is inferred, not measured. |
| Peak RSS | 50.6 MB. This is `ru_maxrss` of the baseline process, which also ran rg and index-only. The rg subprocesses are not counted. | 187 MB (`ru_maxrss`) | **1.46 GB** patched and **1.47 GB** as installed, from a psutil sampler every 0.25 s plus `ru_maxrss`. |
| Query latency | 0.85–2.9 ms | 12.6 ms (head) / 24.8 ms (full) | 23.1 s with the reranker (49.7 s as installed), 489 ms without it, 3.3 ms vector-only |

Why the reranked search takes 23 s per query on CPU is **UNKNOWN**. By the source (`engine.py`
line 2059), the reranker scores `results[:limit*3]` = 60 whole-document pairs per query. No profile
separated tokenisation from the forward pass.

## 4. The reranker defect in the as-installed build

**What the artefacts show.** These are standalone probes in the TrueMemory venv
(`/private/tmp/tm-sandbox/venv/...`; torch 2.14.0, transformers 5.17.0, safetensors 0.8.0). Each
loaded `cross-encoder/ms-marco-MiniLM-L-6-v2` and ran one forward pass.

1. `t.log` and `t_threads1.log`: `Fatal Python error: Bus error` in
   `torch/nn/modules/linear.py:134`, called from `transformers/models/bert/modeling_bert.py`. This
   is the first `Linear` of the BERT encoder.
2. `t2.log`: the probe printed `[nan nan]`. From its shape this is two predicted scores, but the
   probe script was not kept (it ran as `python -c "<string>"`), so its exact inputs are **UNKNOWN**.
3. `t_clone.log`: after cloning the weights, the probe printed `clone tensor([[-1.1824]])`. That is
   a finite logit.
4. The harness author diagnosed it in `rerank_lite.py`: "mmap-backed weights give NaN/SIGBUS on this
   box". The fix used everywhere afterwards (`tm_eval.py --patch-reranker 1`) wraps
   `truememory.reranker.get_reranker` and runs `p.data = p.data.clone()` on every parameter, which
   copies the memory-mapped safetensors weights into ordinary memory.
5. Leftovers whose outcome is **UNKNOWN** because no log records one:
   - `t3.log` prints a parameter's name, shape and some boolean flags; its meaning cannot be
     recovered without the script.
   - `venv2`, created 15:27–15:32, holds older torch 2.13.0, transformers 4.57.6,
     sentence-transformers 5.7.0 and safetensors 0.6.2. It looks like a downgrade test.
   - `models/minilm` is a local copy of the cross-encoder, made at 15:32.

**How TrueMemory would handle this.**
- `engine.search` wraps the rerank in `try/except Exception: logger.debug(...)` (`engine.py`
  lines 2046–2066). A Python exception from the reranker is therefore swallowed silently at DEBUG
  level, and the search falls back to the order it had before reranking.
- A SIGBUS kills the whole process instead.
- NaN scores raise no exception. `reranker._normalize_and_fuse` has no finiteness check, so a NaN
  logit would pass into the fused `score` and into the sort.

**What the recorded as-installed evaluation shows.** This is `results_tm_doc_asinstalled.json`,
written at 16:44 with `--patch-reranker 0`. It does **not** reproduce the NaN.
- `nan_score_rows = 0` across every returned row.
- R@1, R@5, R@10 and MRR match the patched run exactly (47 / 48 hits, MRR 0.947), and differ from
  `norerank` (43 hits@1). So the reranker ran and gave finite, useful scores.
- The top 5 match the patched run for 41/50 queries, and the full top 20 for only 6/50 (measured by
  comparing `raw_tm_doc_asinstalled.json` with `raw_tm_doc_patch1.json`). Every difference is among
  non-gold positions, which is consistent with small numeric differences in the scores.
- The run was **about 2.2× slower**: 49.7 s mean against 23.1 s, first call 154 s against 72 s, and
  a worst query of 146 s. That fits weights being paged in from mmap on demand, but that is a
  hypothesis, not measured.
- The result key `..._ASINSTALLED_nanreranker` is a **label that `tm_eval.py` gives to every
  unpatched full run**. It is not a detection.

**Conclusion on the defect.** On this machine the unpatched MiniLM reranker has been seen to
SIGBUS or return NaN. The evidence is 3 standalone probe logs, and none of them keeps its script.
In the one recorded end-to-end as-installed run it did neither; it was just 2.2× slower.

The following are **UNKNOWN**:
- whether the defect is intermittent (memory pressure, page cache state) or specific to the probe
  code path;
- how often it happens;
- whether it reproduces outside this sandbox.

The brief says the as-installed reranker "produced NaN". The evaluation data does not support that;
only the probes do.

## 5. Per-query failure analysis

These are the gold ranks for every query that at least one strong method missed at rank 1.
"–" means the gold file was not in the returned list.

| q | Style | Query (abridged) | fts fielded | always-loaded idx | all idx | rrf head | m2v full | tm norerank | tm full |
|---|---|---|---|---|---|---|---|---|---|
| q04 | mixed | bats green but a mid-body assertion never checks | 8 | – | 3 | 1 | 5 | 4 | 3 |
| q13 | lexical | pgrep -f finds a claude session whose prompt mentions the tool | 2 | 1 | 1 | 2 | 4 | 1 | 1 |
| q36 | paraphrase | plan doc says mechanism exists, code doesn't implement it | 8 | 1 | 1 | 31 | 4 | 1 | 1 |
| q39 | mixed | `for x in $LIST` loop ran only once in my verification check | 2 | – | – | 1 | 17 | 1 | 1 |
| q43 | lexical | in-process subagent stopped after 100 turns | 1 | 1 | 1 | 1 | 8 | 3 | 1 |
| q44 | paraphrase | output file still empty so I assumed it crashed | 14 | 2 | 2 | 1 | 1 | 2 | 1 |
| **q45** | paraphrase | health check says worker is dead because status file not updated, but it is mid-run | – | **5** | 6 | 96 | 99 | – | – |
| q46 | paraphrase | alert fires all the time so nobody pays attention | 5 | 10 | 24 | 1 | 11 | 4 | 1 |
| **q47** | paraphrase | backup path worked so well nobody noticed the main path was broken for weeks | – | – | – | 43 | **3** | – | – |
| q48 | paraphrase | test with hardcoded date started failing months later | 15 | – | 17 | 4 | 2 | 1 | 1 |

**No query was missed by every one of the 17 variants at top 5.** Two queries, q45 and q47,
were missed at rank 1 by every variant. Every lexical and every fused method, including all TrueMemory modes, also missed them at top 5.

- **q45**, gold `memory/liveness-proxy-cannot-be-output-age.md`.
  - The gold file talks about "stamp age", "alarm", "verifier", "mutex" and "run END". The query
    says "health check", "worker", "status file" and "not updated".
  - Distractors that share "health" and "worker" (`job-health-vs-work-outcome.md`,
    `desk-worker-lifecycle-triage.md`) take the top spots in FTS5, RRF and TrueMemory.
  - Only the **hand-written one-liner in MEMORY.md** ("Stamp age ≠ alive — a stamp is written at
    run END, so it reads INERT mid-run") reaches the top 5 (rank 5), through the word "mid-run".
    The curated index hook is the one signal written in symptom language.
- **q47**, gold `memory/lossless-fallback-hides-its-dead-primary.md`. This is a pure synonym
  paraphrase: backup→fallback, main path→primary, broken for weeks→a mutex orphaned a month.
  - BM25 shares no rare term with the gold file.
  - Vector-only search on the full text ranks it 3 (m2v) or 6 (TrueMemory vec).
  - Fusing with BM25 noise pushes it to 21 or 43 (RRF), and out of the top 20 for TrueMemory's
    hybrid and reranker. So fusion can bury the best single signal.

Other patterns:
- **Pure-lexical failures are rare.** FTS5 got 18/20 lexical queries at rank 1.
- **q36** shows that the `head` encoding (title + description only) can miss when the gold file's
  description is abstract: rrf_head ranks it 31 while the always-loaded one-liner ranks it 1.
- **q39** has a broad collection file ("vacuous-pass traps") as its gold, which vectors rank low
  (17); BM25 on the literal `$LIST` / "loop" terms rescues it.
- **q04** has 3 acceptable gold files, and all methods place one of them in the top 5 or top 10.

## 6. How much the always-loaded index already covers

- **Coverage ceiling.**
  - Only **33 of 50 (66%)** queries have any gold file linked from the hot `MEMORY.md` or from
    the rules-hook indexes.
  - The 17 queries with no such link are q03, q06, q07, q09, q10, q11, q15, q19, q20, q22, q23,
    q24, q27, q28, q29, q38 and q48.
  - For those 17 no amount of index reading can help; the file has to be found by searching.
  - Adding the cold archive index raises the ceiling to 49/50. Only q24's gold file is in no index.
- **BM25 over the always-loaded one-liners** finds the gold file at rank 1 for **22/50 (44%)** and
  in the top 5 for **26/50 (52%)**. That is two thirds of what is reachable (22 of 33).
- **Adding the cold index**, BM25 over index lines alone reaches **37 hits@1 and 43 hits@5**. That
  equals whole-body FTS5 at top 5 (43) and is 1 short of it at rank 1 (38).
  - So the hand-written hooks are about as searchable as the full text.
  - The cold index is not loaded, though, so an agent has to open or grep it.
- Caveat: the index-only baseline is BM25 over the lines, not an agent reading them. An agent that
  has `MEMORY.md` in context may match paraphrases better than BM25 does, but it still cannot beat
  the 66% ceiling. What an LLM reading the index would actually score is **UNKNOWN**; it was not
  run.

## 7. Verdict

**For a file-based Claude Code memory of about 640 files and 2.4 MB, adopt fielded SQLite FTS5
fused by RRF with model2vec `potion-base-8M` head embeddings.**

| Metric | This method | TrueMemory full |
|---|---|---|
| R@1 | 0.90 | 0.94 |
| R@5 | 0.94 | 0.96 |
| MRR | 0.916 | 0.947 |
| Latency | about 13 ms per query | 23 s per query |
| Peak RSS | 187 MB | 1.46 GB |
| Other cost | about 30 MB of model; no torch | 911 MB venv; 5.4 min ingest |

- The script needs only `numpy` and `model2vec` on top of the standard library, and `harness/hybrid_lite.py` already implements it.
- The gap to TrueMemory full is 3 queries against 1 at rank 1 and 1 query at rank 5, which is not
  significant at n = 50.
- TrueMemory without its reranker (0.86 / 0.96) is no better than this script.
- Its only measured advantage is the MiniLM reranker. On this machine that reranker costs 23–50 s
  per query and needs a weight-cloning patch to be safe from SIGBUS or NaN, which TrueMemory would
  swallow or propagate silently.

**Not worth adopting at this corpus size:**
- TrueMemory as a retrieval backend, for the cost, fragility and non-significant gain above.
- `rg` keyword search. Ranking by distinct terms gets R@1 0.36. ANDing all terms returns nothing
  for 47/50 symptom-phrased queries, which is what an agent chaining `rg -l` actually gets.

**If you add nothing:**
- Plain FTS5 (0.78 / 0.88, stdlib, 3 ms) is the zero-dependency floor and already far beyond grep.
- The always-loaded index alone points at the gold file for about **44% at rank 1 and 52% in the
  top 5**, with a hard **66% ceiling**.
- Keeping the index hooks in symptom language matters: they are the only thing that found q45.

## 8. Threats to validity

1. **Same author for queries and gold.** The agent that wrote the queries knew the gold files, and
   the queries were written right after the corpus was copied.
   - This favours lexical methods, since the queries reuse the files' own words. Even paraphrase
     queries share 34% of their terms with the gold file's title and description, lexical ones 55%.
   - It inflates every absolute score. Real symptom queries from later sessions would probably score
     lower. That is an estimate, not measured.
2. **Small n.** 50 queries, and only 10 paraphrase queries.
   - The Wilson 95% intervals for R@1 of TrueMemory full (0.84–0.98) and RRF head (0.79–0.96)
     overlap heavily.
   - Differences of 1–3 queries should not be read as rankings.
3. **Incomplete gold.** Each query lists 1–3 gold files. The corpus holds near-duplicates, for
   example the same topic in `memory/` and `lessons/`, and unlabelled but relevant files would count
   as misses.
4. **Possible post-hoc tuning.** `hybrid_lite.py` (15:51) was written after the baseline results
   existed (15:19). It is **UNKNOWN** whether the `head` encoding or the FTS weights 10/5/1 were
   chosen after looking at results on these same 50 queries. If they were, the RRF numbers are
   optimistic.
5. **Truncation differs between methods.** TrueMemory ranks are capped at about 20 rows before
   dedupe, FTS5 at 20 and RRF at 100. This affects R@10 and MRR slightly, and R@1 and R@5 not at all.
6. **The as-installed defect was not reproduced** in the recorded run (§4). A clean as-installed
   run may be faster or slower than 49.7 s, and may or may not produce NaN.
7. **Single machine, single run.** Latencies come from one pass on a macOS arm64 CPU with no
   repeats. Model-load and first-call times were measured once.
8. **Incomplete variants.** The chunk variant with the reranker and the `rerank_lite` probe (a
   reranker on a small RRF pool) never produced results. So whether a cheap top-5 or top-10 rerank
   keeps TrueMemory's 0.94 at a fraction of the cost is **UNKNOWN**.
