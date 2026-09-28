# TrueMemory — RETRIEVAL axis (notes)

Source: shallow clone `/tmp/truememory-src` @ `063e5b8` (Sep 2026). Paper: arXiv 2605.04897v1 (10 pp, read in full as PDF).
Labels: **MEASURED** = I ran it (command/script named) or read the code line; **CLAIMED** = README/paper/docstring/comment says so, not verified by me; **ESTIMATED** = my arithmetic (method named).
Scratch scripts: `/tmp/tm-research/scratch/{quirks*.py,fts_eval.py,dense_eval.py,dense_eval.out}`.
Scratch venvs: `/tmp/tm-venv` (mine: numpy+pytest, truememory installed `--no-deps`), `/tmp/tm-research/venv` (sibling's, full deps; used read-only with `HF_HUB_OFFLINE=1`).
Nothing under `~/.claude*` or the claude-infrastructure repo was written. Memory stores/lessons were only READ (to build throwaway /tmp FTS indexes).

---------------------------------------------------------------------------------------------------

## 0. TL;DR for our workflow

1. **The lexical half of TrueMemory's pipeline needs no embeddings and does most of the work on OUR corpus.**
   SQLite FTS5 `porter unicode61` + BM25 column weights (name/description/body) + a stopword-filtered OR query
   gives R@5 = 0.88 / R@1 = 0.78 on the sibling's 50 hand-labelled queries, at ~1 ms p50 (MEASURED, `dense_eval.py`).
   The miss class is **paraphrase** (5/10 at R@5).
2. **The cheapest real lift is a static embedder with RRF.** `potion-base-8M` (Model2Vec, TrueMemory's Edge embedder)
   is numpy+tokenizers only (no torch). RRF(k=60) with FTS5 took R@5 0.88 → 0.96 and R@1 0.78 → 0.84 at ~1.2 ms/query and
   +152 MB RSS (MEASURED). Dense-only is worse than FTS5 at R@1 (0.66).
3. **The cross-encoder is the biggest R@1 lift but expensive.** MiniLM-L6 over FTS5 top-50: R@1 0.94, p50 ≈ 1.3 s/query,
   +280 MB on load, peak 1.85 GB with torch (MEASURED, CPU, 2000-char passages). Adding potion under it changed nothing
   at R@5 (0.96 either way). For us an in-session LLM already reads the top-k — the calling model *is* the reranker.
4. **Much of TrueMemory's ranking stack is heuristic multipliers stuck onto rank-fused scores, and several are broken or inert**
   (§7). Do not port the multipliers. Port: FTS5 schema/tokenizer, safe query quoting, RRF, a candidate-pool-then-rerank shape,
   the score-space contract (#632), the recall cache keyed on everything that changes the payload (#645), and the "skip the reranker on hook paths" rule (#690).
5. n=50 hand queries is SMALL. With 50 queries one query is 2 pp, so the potion lift (+4 queries at R@5) is suggestive, not proven.

---------------------------------------------------------------------------------------------------

## 1. Tiers, models, sizes, RAM

Canonical table `truememory/tier_config.py:25-47` (MEASURED read):

| tier | embedder (internal id) | dim | reranker | group |
|---|---|---|---|---|
| edge | `model2vec` → `minishlab/potion-base-8M` (`vector_search.py:259-262`) | 256 | `cross-encoder/ms-marco-MiniLM-L-6-v2` | edge |
| base | `qwen3_256` → `Qwen/Qwen3-Embedding-0.6B`, `truncate_dim=256` Matryoshka (`vector_search.py:271-282`) | 256 | `Alibaba-NLP/gte-reranker-modernbert-base` | basepro |
| pro  | same as base | 256 | same as base | basepro |
| custom | any HF id via `TRUEMEMORY_CUSTOM_*`, needs `TRUEMEMORY_CUSTOM_ALLOW_DOWNLOAD=1` (`tier_config.py:74-133`) | 1-4096 | default MiniLM | custom |
| (deep search, any tier) | — | — | `BAAI/bge-reranker-v2-m3` (`mcp_server.py:779`, comment "568M, ~0.77s/query") | — |

Legacy/extra embedders still loadable: `minilm` (all-MiniLM-L6-v2, 384d), `bge-small` (384d) (`vector_search.py:263-270`).
Pro = Base + HyDE (LLM API key); in-code gate is `tier == "pro"` (`mcp_server.py:1130`).

Sizes and RAM:
- CLAIMED: potion "~30MB, CPU" and Qwen3 "~1.5GB, GPU recommended" (`vector_search.py:10-12`). MiniLM CE 22M params, gte-modernbert 149M (`reranker.py:9-13`).
  README tier table: Edge "8 MB lightweight / 22M reranker / any machine CPU only"; Base/Pro "600 MB / 149M / 4 GB+ RAM" (`README.md:116-122`).
  Paper §5: Edge ≈ 30M params total, ~123 MB fp32 weights, "runtime working-set RAM under 1 GB", Raspberry Pi 4 sufficient; larger configs "2 to 4 GB runtime RAM, none require a GPU" (paper p.7-8).
  Benchmark harness memory: Edge 512 MB container, Base 4 GB (`benchmarks/locomo/BENCHMARK_RESULTS.md:130-131`).
  Installer: "Downloads ~1.5GB of AI models" (`README.md:73`).
- MEASURED (`dense_eval.py`, macOS arm64, Python 3.12, CPU): potion load 0.68 s warm / 7.2 s cold; encode 640 docs 0.54–0.66 s;
  +152 MB RSS for model2vec+potion. MiniLM CrossEncoder load 10.4 s cold; +280 MB RSS; process peak 1852 MB after scoring
  50 queries x 50 pairs with 2000-char passages. Qwen3/gte not measured.
- Memory hygiene knobs: model server process shared across hooks, idle exit 300 s (`model_server.py:72`); MCP unloads models after
  `TRUEMEMORY_MODEL_IDLE_SEC` = 300 (`mcp_server.py:1655-1704`); optional RSS cap `TRUEMEMORY_MAX_RSS_MB` (`mcp_server.py:1656`).
  Hook recall arms a 5 s model-server deadline so a contended server fast-fails and the engine falls back to FTS-only
  (`ingest/hooks/_shared.py:97-116`).
- Qwen3 Matryoshka truncation leaves `||v||≈0.55`; they L2-normalise at write (`vector_search.py:604-623`). `engine.add()` stores
  the raw pre-embedding without that normalisation (`engine.py:732,766-769`) — harmless only because vec tables use
  `distance_metric=cosine` (`vector_search.py:579-601`).
- MEASURED (grep): no `prompt_name`/instruction prefix is passed when encoding Qwen3 queries (`vector_search.py:909`, `hybrid.py:190`).
  CLAIMED (Qwen model card, not verified here): Qwen3-Embedding expects an instruction on the query side; omitting it costs a few points.

---------------------------------------------------------------------------------------------------

## 2. Storage / lexical substrate (the piece that needs no embeddings)

- `messages_fts USING fts5(content, sender, recipient, category, modality, content_rowid='id', tokenize='porter unicode61')`,
  kept in sync with triggers on insert/update/delete (`storage.py:47-69`). Not an external-content table, so text is stored twice.
- Query sanitiser: split on whitespace, strip `"`, wrap every token in double quotes, join with ` OR ` (`fts_search.py:31-39`).
  Injection-safe; **no stopword removal** in the main path. MEASURED consequence (`fts_eval.py`, 1477-doc corpus, 394 hook-text queries):
  p50 11.2 ms / p95 33 ms with TM's builder vs 2.65 / 4.9 ms with stopwords removed, same accuracy (R@5 0.985 vs 0.987): OR-ing "the"/"a"
  walks huge posting lists.
- BM25 via `ORDER BY messages_fts.rank`, **default column weights** (content, sender, recipient, category, modality all 1.0) (`fts_search.py:96-102,138`).
- Scores min-max normalised per query: best hit is always **1.0**, worst is always **0.0** (`fts_search.py:48-73`). A relative score, so it cannot be thresholded.
  This caused #632 (below). A side effect: multiplicative boosts on the bottom row are no-ops (0 x 1.3 = 0).
- Date-window variant pulls `min(max(limit*10,100),1000)` candidates, filters ISO strings lexicographically with an exclusive next-day
  upper bound, and normalises BEFORE trimming (#633 M-10) (`fts_search.py:198-275`).
- Sender filter in SQL (`search_fts_by_sender`, `fts_search.py:152-195`) is used for "entity" search.

---------------------------------------------------------------------------------------------------

## 3. Dense layer

- sqlite-vec `vec0(embedding float[256] distance_metric=cosine)` tables per tier group (`vector_search.py:579-601,168-200`); KNN via
  `WHERE embedding MATCH ? AND k = ?`. Directives are post-filtered after over-fetching 2x (`vector_search.py:914-959`).
- Score: `1/(1+cosine_distance)` for ranking (`vector_search.py:942`); `max(0,1-d)` for the absolute cosine used by the encoding gate (`vector_search.py:1003`).
- "Separation" vectors: a second embedding of `"{sender} to {recipient} on {date}: {content}"` (`vector_search.py:1155-1159`), searched as a
  third RRF list at 0.8 x vec weight, **only if the DB has >5 distinct senders** (`hybrid.py:199-208,254`). The paper says this fires
  only with more than five senders, because in 2-3 person chats the shared sender prefix gives a uniform ranking (paper p.6).
- Model load is a lazy singleton, or a proxy to a shared model-server process (`vector_search.py:231-313`).

---------------------------------------------------------------------------------------------------

## 4. Fusion — RRF

- Generic `reciprocal_rank_fusion(lists, k=60)`: `score += 1/(k+rank_1based)`. Ids are keyed as `str(id)` so `id=0` survives and
  mixed int/str ids merge. The richest copy of each doc is kept, and ties break on `str(id)` for determinism (`hybrid.py:51-114`; #583 tests).
- `search_hybrid`: FTS top-200 + vec top-200 (+ sep top-200) (`_CANDIDATE_POOL = 200`, `hybrid.py:123,193-208`); weighted RRF with
  `k=60`, `fts_weight`, `vec_weight`, `sep = 0.8*vec` (`hybrid.py:232-262`); provenance `source` ∈ fts/vec/sep combos,
  `fts_rank`, `vec_rank` (`hybrid.py:267-289`).
  - RRF score magnitudes: rank-1 in one list = 1/61 ≈ 0.0164; rank-1 in fts+vec = 0.0328; +sep = 0.046 (ESTIMATED, arithmetic).
    Every downstream heuristic that mixes in [0,1]-scale scores must rescale against this. Most of the #584/#630/#632/#633 bug
    cluster is this mismatch.
  - **The 200-per-list pool caps candidate generation whatever `limit` is**, so "deep" search's "5x more candidates"
    (`mcp_server.py:371`; `_DEEP_INTERNAL_LIMIT=500`, `:757`) cannot exceed ≈400-600 unique hybrid candidates. What deep actually adds is a
    bigger rerank window and a heavier reranker (MEASURED code read, `hybrid.py:123` vs `engine.py:2184,2411`).
- Adaptive weights come from a regex query classifier: 6 types with patterns; the type with the most matches wins
  (`query_classifier.py:11-128`). Only `fts`/`vec` weights are consumed (`engine.py:1775-1776`); e.g. factual 1.2/0.8, temporal 0.8/0.6,
  entity 1.5/0.7, personality 0.5/0.5. The `temporal`/`personality`/`consolidation` weights in the table are **never read** (MEASURED grep: only
  `weights"].get("fts"|"vec")`). The paper admits "a principled calibration sweep over the source weights is left for future work" (p.6).
- `get_search_mode` → "diffuse" on words like all/overview/summarize/typically, else "spotlight". This only sets the salience floor, 0.02 vs 0.05
  (`query_classifier.py:131-157`, `engine.py:2020-2029`).

---------------------------------------------------------------------------------------------------

## 5. Full ranking pipeline (code order)

### 5a. `TrueMemoryEngine.search(query, limit)` — `engine.py:1729-2120` (used by hooks, `Memory.search`)
0. classify → weights + mode (`:1761-1776`).
1. `search_hybrid(limit=limit*3)`; on failure or no vectors → `search_fts(limit=limit*3)` (`:1779-1801`).
2. If >5 distinct senders among results: **scent trail** (proper nouns + senders from the top 3 → FTS by sender, plus an FTS on
   joined trail terms at 0.7x) (`:1812-1817`, `search_quality.py:18-86`).
3. If >5 senders: **quality self-check**. If the top-5 max < 0.04 and the range < 0.005, it runs single-word FTS on up to 3 words longer than 3 chars, at 0.5x
   (`:1819-1824`, `search_quality.py:89-131`).
4. **Temporal** (`:1826-1906`): `detect_temporal_intent` (§6). If `has_temporal`, `search_temporal` filters the pool to the window
   (or, with no window, just re-sorts by time) and returns `limit*2`. Existing ids get **score x 1.3** and `+temporal`, and new ones are appended.
   If trajectory/sort_by_time, the pool is re-sorted by timestamp (`:1867-1868`). If both `after` and `before` are known, FTS is re-run inside the window and
   new rows are appended at `0.8 x local_max x normalized` (#633 M-10) (`:1873-1903`).
5. **Personality supplement** only when the query has personality intent. Profile rows are scored `0.8 x max`, style/fts rows
   `TRUEMEMORY_L0_SCORE_SCALE` (0.9) `x max` (`:1912-1945`).
6. **Contradiction/fact_timeline supplement** at `0.8 x max` if no score (`:1948-1981`), and a **consolidated-summary supplement** rescaled
   from raw keyword-overlap ints to `0.8 x max x rel` (#633 M-09) (`:1983-2014`). `search_consolidated` returns early when the
   `summaries` and `fact_timeline` tables are empty (#689 PERF-01, "≈44% of search cost at scale" CLAIMED in comment `consolidation.py:1212-1227`).
7. **Salience guard** (skippable): entity boost (+30% of max if sender/recipient matches, +20% if mentioned, −15% otherwise),
   then drop rows with learned-logistic salience < floor (0.05 spotlight / 0.02 diffuse; env `TRUEMEMORY_MIN_SALIENCE`).
   Contradiction rows are exempt (`:2020-2034`, `salience.py:508-566,409-505,354-406`). Salience is a 13-feature logistic model
   (`salience.py:153-209`, weights `data/l3_weights.json`).
8. **L5 surprise boost** `score *= 1 + α·surprise`, α=0.2 (`:2039-2040`, `l5_boost.py:70-137`). It is a no-op until
   `surprise_scores` has been built by consolidation. Summary/profile/contradiction rows are skipped (`l5_boost.py:16-18`).
   α=0.2 came from a "5-point sweep x 3 seeds, 93.20% vs 93.00% at α=0" (CLAIMED `engine.py:2456-2460`). That is a 0.2 pp effect.
9. **Cross-encoder** (skippable via `_skip_reranker`): re-sort by score, slice `limit*3`, then `rerank_with_modality_fusion(rrf_weight=.4,
   rerank_weight=.6)` (`:2045-2066`). Fusion min-maxes both the CE and the incoming score, then takes `0.6·ce + 0.4·orig`, with degenerate lists → 0.5
   (#633 M-77) (`reranker.py:245-277`). The modality factor multiplies the CE score by 0.7 (detail question) or 1.2 (synthesis question) for
   modality ∈ {episode, fact} (`reranker.py:368-435`).
10. Clean: drop directives, dedupe by id and by `content[:200]`, clamp negatives to 0, sort by `score`, then `str(id)`, and trim (`:2068-2120`).

### 5b. `search_agentic` (MCP `truememory_search` / `_search_deep`; `Memory.search_deep`) — `engine.py:2126-2446`
- Pool: `max(limit*8,100)` if reranking (`:2183-2186`). MCP passes `limit=100` (standard) or `500` (deep) (`mcp_server.py:756-757,1139-1141,1190-1192`),
  so `search()` gets asked for 800 or 4000. Hybrid still yields ≤200/list (see §4).
- Runs `search()` with **no** surprise/reranker/salience (`:2187`).
- **HyDE** (Pro, or a configured deepsearch provider): `hyde_search` = RRF(search_hybrid(q), search_hybrid(hyp_doc)); then RRF again
  with the primary list (`:2190-2202`, `hyde.py:122-190`). So the original query is counted in 2 of the 3 underlying lists (ESTIMATED from structure).
  Prompts are **conversation-snippet style**: "Write it as dialogue between two people" (`hyde.py:36-40`); a factual variant exists
  but is only used by `hyde_multi_search`, which the engine never calls (MEASURED grep).
- `normalize_scores` min-max → [0,1] (#584) (`:2207-2209`, `agentic_search.py:22-45`).
- Cluster supplement (HDBSCAN centroids, top 3 clusters) runs only if vectors are healthy (M-78) (`:2223-2243`, `clustering.py:198-`).
- **Entity-focused search**: query words matched against known senders → FTS by sender on the stopword-stripped query (≤2 senders);
  otherwise a stopword-stripped FTS. Overlap → **x1.5** once (`_entity_boosted` flag, #582). New rows are added at their normalised score,
  or x0.1 if outside the detected time window (#633 M-68) (`:2259-2335`, `agentic_search.py:145-230`).
- Salience guard with entity rescue (`:2342-2361`).
- **Sufficiency**: top-5 average score > 0.02 and ≥3 unique 100-char prefixes (`agentic_search.py:74-83`). If insufficient and an LLM is available: 2-3 LLM
  refined queries through `search()`; new rows x0.9, overlaps x1.15 (`:2363-2396`, prompts `agentic_search.py:86-142`).
- Surprise boost → CE on `[:limit*5]`, top_k=limit (`:2404-2416`). Optional LLM 0-10 rerank of ≤50 docs (`reranker.py:442-517`), which MCP never
  enables (MEASURED: `use_llm_reranker` is not passed from `client.search_deep`).
- `clean_results` with optional `max_per_session` diversity by `category` (`agentic_search.py:233-308`).

### 5c. Hook-time recall (what an agent sees automatically)
- SessionStart: 5 **fixed generic queries** ("user preferences favorites likes dislikes", "personal facts name location job role",
  "recent decisions and commitments", "corrections and updates to prior information", "relationships family friends coworkers")
  through `engine.search(..., _skip_reranker=True)`. Results are substring-deduped and capped at 500 chars/memory and an 8192-char payload
  (x2 at intensity=max) (`ingest/hooks/session_start.py:1019-1071,92-117`). Directives are force-injected first, limit 50 (`:88,779-`).
  The queries are **not project/cwd-aware**.
- Recall cache: JSON file, TTL 300 s (`_shared.py:72-79`). The key is the normalised db_path, user, intensity, budget and producer (#645, `_shared.py:615-637`).
  Every store/delete/update/configure invalidates it, and a transient all-queries-failed result must not negative-cache "" (#645 M-36, `session_start.py:1106-1113`).
  SessionStart writes a marker so the first prompt's auto-recall is debounced (60 s) (#561, `_shared.py:466-491,640-666`).
- UserPromptSubmit: regex recall-intent detector (`user_prompt_submit.py:125-147`), prompt length 10-500, code-looking prompts skipped
  (`:149-154,624-629`) → `m.search(prompt, limit=5, _skip_reranker=True)`, 200-char lines in `<truememory-recall>` (`:632-678`).
  Intensity "enhanced" searches every 5th prompt (8 results) and "max" every prompt (10) (`:544-621`).
- #690: hook and dedup paths pass `_skip_reranker=True` so a cold hook never loads a CrossEncoder (CLAIMED rationale; locked by `tests/test_issue_690_skip_reranker.py`).

---------------------------------------------------------------------------------------------------

## 6. Temporal parsing (`temporal.py`)

- `parse_date_reference` (`:96-198`), in order: ISO `YYYY-MM-DD`; `YYYY-MM`; "June 15, 2025"; "15 June 2025"; early/mid/late + Month + Y
  (01/15/25); early/mid/late + Y (01-01 / 05-01 / 09-01); "Month YYYY"; bare `20\d{2}`. Month names plus 3-letter forms and "sept" (`:79-89`).
- `detect_temporal_intent` (`:215-505`) returns `{has_temporal, after, before, sort_by_time, is_trajectory, reference_date}`:
  - trajectory words: over time, trajectory, grew/grow/growth, **change(d)**, evolve(d), evolution, progress(ion/ed), decline(s/d),
    **improve(d)**, deteriorate, `from … to …`, timeline, chronolog (`:261-284`);
  - from X to Y / between X and Y ranges; "in Month YYYY" → month bounds; "in YYYY" → year; after/before X (captures American
    "Jan 15, 2026"; `:342-367`, #506); "as of X" (before=X, or after=X with upcoming/future/**next**/scheduled); first/next month|week|year windows
    (+31/+7/+365 days); relative yesterday / last N days|weeks|months|years (month = 30 d) / last week|month|year, resolved against `datetime.now()` (#509);
    parenthesised dates; and finally any standalone date.
- Boundaries: `_validate_iso_date` rejects malformed input (`:40-54`); `_exclusive_upper_bound` → next day for date-only (`:57-72`, #593/#506).
  Empty timestamps are dropped whenever a bound is active (M-70, `fts_search.py:259-264`).
- `get_timeline` backfill: `SELECT … WHERE timestamp in window ORDER BY timestamp` with **no LIMIT** (`temporal.py:598-656`). It is called whenever
  fewer than `limit` in-window results remain (`:582-593`).
- #466 fix: the engine consumes `after`/`before`, not `start_date`/`end_date` (test `test_issue_466_temporal_key.py`).
- Episodes (6-hour gap) and landmark events exist (`:676-906`) but are not on the search path I traced.

---------------------------------------------------------------------------------------------------

## 7. Measured and code-level defects in the ranking stack (why not to port the multipliers)

A. **Temporal "trajectory" false positives demote the NEWEST rows.** MEASURED (`quirks2.py`, FTS-only engine, 12 rows with monthly timestamps):
   "how did we change the deploy hook" → `has_temporal=True, is_trajectory=True`, no dates. Top-5 became Feb, Mar, Apr, Jan, May, all
   `fts+temporal` at 1.3x, against Apr, Mar, May, Jun, Jul for the control query "the deploy hook". Mechanism: `search_temporal` sorts the pool
   **ascending** by time and keeps `limit*2` (`temporal.py:578-595`); every survivor gets x1.3 (`engine.py:1857-1860`), so the newest
   rows past `limit*2` are the only ones left unboosted. Triggers include ordinary engineering words: change/changed/improve/progress/next/"from X to Y".
   For an agent memory, "what changed" usually wants the newest.
B. **The chronological re-sort is undone.** `engine.py:1867-1868` sorts by timestamp, but the final `cleaned.sort` is by score (`:2119`).
   In the main `search()` path the trajectory ordering never reaches the caller (MEASURED code read; consistent with A's output ordered by score).
C. **The salience-guard entity boost is a no-op on the final ranking.** `filter_by_entity` stores `entity_boost` and sorts by
   `score+entity_boost` but never writes it back into `score` (`salience.py:474-481`). Both later sorts use `score` only (`engine.py:2053-2058,2119`).
   MEASURED (`quirks3.py`): guard order [alice 0.7+0.45, bob 0.9−0.135] → final `engine.search` order [bob 0.9, alice 0.7].
   Tests #487/#488 assert the boost value and the call order, not the final ranking. (The agentic x1.5 entity boost *is* folded into
   score, `engine.py:2304`.)
D. **Scent trail and quality self-check inject [0,1]-scale rows into an RRF-scale (≈0.03) pool.** MEASURED (`quirks4.py`): with primaries at
   0.033, scent-trail rows came in at 1.0/0.7 and fallback rows at 0.5, 15-30x the organic scores (`search_quality.py:61-83,114-121`).
   The self-check threshold `max<0.04 and range<0.005` is met by almost any hybrid top-5 (fts+vec rank-1 = 0.0328; ESTIMATED arithmetic), so
   in >5-sender DBs it fires on most queries. It is dormant in single-user Claude Code installs (sender = user_id), which is why the benchmarks
   (2-3 speakers) never see it. No test references either function (MEASURED grep of `tests/`).
E. **Round-2 refinement is effectively dead.** `check_sufficiency` requires top-5 avg > 0.02 (`agentic_search.py:83`), but it runs after
   min-max normalisation (`engine.py:2209`), where the top row is 1.0, so the average is ≥0.2 whenever ≥2 distinct scores exist (ESTIMATED from code).
   LLM refined queries almost never run.
F. **The modality factor is dead code in practice.** It only touches `modality ∈ {episode, fact}` (`reranker.py:395-399`). `engine.add` writes `modality=""`
   (`engine.py:753`) and nothing in `truememory/` assigns those values (MEASURED grep). If it did fire: ms-marco MiniLM emits raw logits
   (negative for irrelevant pairs, CLAIMED from model behaviour), and x0.7 / x1.2 on a negative logit inverts the intended direction.
G. The query-classifier weight profile is mostly unused (§4). `rerank_with_llm` is never enabled from MCP.
H. **The benchmark set-up flatters every ranker.** The LoCoMo harness feeds **100** retrieved items to the answer model
   (`bench_truememory_edge.py:233-234`: `search_agentic(limit=100)` → context). Conversations average 588 messages (MEASURED from
   `benchmarks/locomo/data/locomo10.json`: 419-689), so the answer model sees ≈17% of each conversation. That rewards recall@100, not
   precision@5. The paper describes "top-k (default k=10) … passed to the answer model; pre-rerank window is 100" (p.7). The bench code passes
   all 100 post-rerank items, which is inconsistent with the paper text.
I. **The BM25 baseline (80.5%) is a strawman tokenizer.** It uses `rank_bm25` on `.lower().split()` with punctuation left attached and no stemming
   (`bench_bm25.py:182-185`). TrueMemory's own FTS5 uses porter+unicode61. So the "+9.1 pp Edge over BM25" (`BENCHMARK_RESULTS.md:16,19`) credits the
   embedder and reranker with part of a tokenizer gap. No per-layer ablation is published. The paper reports a "56-configuration ablation" only as a "1.3-pp spread
   within the top family" (abstract).
J. Headline inconsistency: README LongMemEval **92.0%** (`README.md:18,54,117`) vs paper **87.8%** (abstract; p.10 §6.3).
K. README "instant recall … in under 200ms" (`README.md:227`) is CLAIMED. The MCP search path cross-encodes up to `limit*5 = 500` pairs (`engine.py:2411`),
   and my MiniLM measurement was ≈1.3 s per 50 pairs of long passages on CPU. Hook paths skip the reranker, so <200 ms is plausible only there (ESTIMATED).
L. Unbounded `get_timeline` backfill (§6) and N+1 queries per subject in `search_contradictions` (`consolidation.py:1113-1131`) are scale hazards.

Tests I ran (MEASURED): `pytest` on 17 retrieval test files in `/tmp/tm-venv`, FTS-only with no model downloads
(HOME=/tmp/tm-home, TRUEMEMORY_NO_MODEL_SERVER=1): **194 passed, 6 failed**. All 6 failures are `ModuleNotFoundError: mcp` (env, not logic):
`test_issue_463_hyde_tier_gate` x4, `test_issue_645::test_truememory_configure_invalidates_recall_cache`, `test_reranker_tier::test_truememory_configure_propagates…`.
The tests lock id hygiene, score-space rescaling, boundary dates, cache keys and call order. **None lock end-to-end ranking quality** (A-E above pass the suite).

---------------------------------------------------------------------------------------------------

## 8. Measurements on OUR corpus (what works without embeddings)

### 8a. Known-item from our own hook text (`fts_eval.py`; corpus = both live stores' topic files + docs/lessons = 1477 docs, 6.0 MB; read-only)
Queries = MEMORY.md index lines (label + hook, 250) and rules-file lesson hooks (144) → the linked file. Index build 150-165 ms; DB ≈11 MB.
- label+hook (easy, vocabulary overlaps): body-only R@5 0.985-0.987, MRR 0.955; name+desc+body 0.997. p50 2.2-2.7 ms with stopwords.
- **label only (2-6 words)**: body-only TM-query R@5 0.787; body-only stopword 0.799; fields bm25(1,1,1) 0.916; **fields bm25(5,3,1) 0.939,
  R@1 0.827, p50 0.48 ms**. Leak caveat: for lessons, `name` = the H1 title ≈ the label.
- 3 random content words from the hook: body 0.716; fields(1,1,1) 0.794.
- Lexical-only RRF (body list + name/desc list, k=60): labels 0.931, 3-word 0.726. **Single-index column weighting ≥ RRF of lexical views.**

### 8b. Hand-labelled realistic queries (sibling's `tm-empirical/queries.json`, 50 queries: 20 lexical / 20 mixed / 10 paraphrase; corpus 640 docs) — `dense_eval.py`
| system | R@1 | R@5 | R@10 | MRR | p50 | paraphrase R@5 |
|---|---|---|---|---|---|---|
| FTS5 fielded(1,1,1), TrueMemory OR-quoted query | 0.76 | 0.84 | 0.88 | 0.803 | 2.3 ms | 3/10 |
| FTS5 fielded(10,5,1), stopword query | 0.78 | 0.88 | 0.92 | 0.825 | 0.9 ms | 5/10 |
| potion-base-8M dense only | 0.66 | 0.86 | 0.90 | 0.749 | 0.1 ms | 7/10 |
| **RRF(FTS5 + potion), k=60** | **0.84** | **0.96** | 0.96 | 0.891 | 1.2 ms | 8/10 |
| FTS5 → MiniLM CE top-50, fused .6/.4 (TM formula) | 0.94 | 0.96 | 0.96 | 0.944 | 1267 ms | 8/10 |
| FTS5 → MiniLM CE top-50, pure CE order | 0.94 | 0.96 | 0.96 | 0.945 | 1392 ms | 8/10 |
| RRF(FTS5+potion) → MiniLM CE fused (≈ Edge tier) | 0.94 | 0.96 | 0.96 | 0.947 | 1339 ms | 8/10 |
(For comparison, the sibling's `results_baselines.json`: rg distinct-terms R@5 0.64; always-loaded indexes only 0.52; all indexes incl. cold 0.86.)

Takeaways: (1) FTS5 alone beats ripgrep and index-only lookup by a wide margin; (2) potion+RRF is the best cost/benefit step (sub-ms extra,
no torch); (3) the CE mainly fixes R@1 ordering. An LLM that reads a top-5/10 list gets that for free; (4) n=50 → ±2 pp per query.

---------------------------------------------------------------------------------------------------

## 9. Transfer map to our file-based workflow

| TrueMemory piece | Needs embeddings? | Port? | How, for us |
|---|---|---|---|
| FTS5 porter+unicode61 over files | no | YES | throwaway/derived `~/.cache/…/memory-fts.sqlite` rebuilt from `memory/*.md` + `docs/lessons/*.md` (150 ms full rebuild for 1.5k docs, measured), so no sync triggers are needed. Columns name/description/body/type; `bm25(d,0,5,3,1)`. |
| safe OR-quoted query | no | YES, with stopwords | quote tokens (injection-safe), drop stopwords: 4x faster p50 at equal accuracy (measured) |
| RRF k=60 | no (any ranked lists) | YES | fuse FTS5 with (a) a potion list if we accept model2vec, or (b) ripgrep/regex exact-hit lists, or (c) several agent-written query variants ("HyDE by the calling model": the agent is already an LLM, so query expansion costs nothing) |
| static embedder (potion-8M) | yes (tiny) | OPTIONAL, recommended to trial | numpy+tokenizers only; +152 MB, 0.5 s to embed 640 docs; cache vectors keyed by file sha |
| cross-encoder rerank | yes (torch) | NO for hooks; maybe for an explicit "deep" command | ~1.3 s/query CPU and ~1.8 GB peak. The in-session model already reranks when it reads the top-k |
| HyDE (LLM hypothetical doc) | LLM | adapt, not port | the calling agent writes 2-3 phrasings. TM's dialogue-style prompt is wrong for fact/lesson files |
| temporal intent parser | no | NARROW port only | explicit date/range parsing (ISO, "last N days", "in Month YYYY", `modified:` frontmatter) is useful. Do NOT port the trajectory keyword list or the x1.3 (defect A) |
| entity boost / salience guard / surprise boost | no | NO | inert or broken here (C, E); our anti-capture rule already filters at write time |
| score-space tag (#632) | no | YES (idea) | never threshold a min-maxed score. If dedup uses a lexical score, use raw bm25 or an explicit overlap measure, tagged |
| recall cache keyed on every payload-affecting input (#645) + invalidate on write | no | YES (idea) | if a SessionStart/UserPromptSubmit recall hook is added: key on store path, query set, budget and producer; invalidate on any memory write |
| skip heavy ranker on hook paths (#690); 5 s deadline with lexical fallback (#577) | — | YES (idea) | hooks must be lexical-only and time-boxed |
| SessionStart fixed generic queries | no | NO | our MEMORY.md index is better. If anything, derive queries from cwd/branch/recent files |
| per-prompt recall-intent regex (`user_prompt_submit.py:125-147`) | no | MAYBE | a cheap gate for a UserPromptSubmit "you may already know this" hint that injects ≤5 hook lines (not bodies) from FTS5 |
