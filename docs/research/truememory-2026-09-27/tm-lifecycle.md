# TrueMemory LIFECYCLE axis: consolidation, contradiction, forgetting, summaries, entity sheets, personality

Source: shallow clone `/tmp/truememory-src` at `063e5b8` (package version 0.7.6.2).
Probes and outputs: `/tmp/tm-research/scratch-lifecycle/` (in-memory or /tmp SQLite only; HOME sandboxed, telemetry off).
Evidence labels used below:
- **MEASURED-RUN**: I executed it (command and output file named).
- **MEASURED-READ**: I read the code at the cited file:line.
- **CLAIMED**: README, CHANGELOG, docstring or paper says so and I did not reproduce it.

Test run (MEASURED-RUN): `pytest tests/test_issue_580_* test_issue_591_* test_issue_685_* test_issue_692_* test_consolidation_lock.py test_issue_498_* test_consolidation_gaps.py test_issue_581_* test_l4_entity_sheets_disabled.py` gave **95 passed in 1.49s**. The suite passes, but several tests are weak (see §9).

---

## 0. One-paragraph verdict

TrueMemory's "lifecycle" has four parts:
1. An append-only raw `messages` table. It never decays or expires.
2. A derived layer that is fully rebuilt on each consolidation: `summaries`, `fact_timeline`, clusters, episodes, landmarks, surprise scores and Dunbar relationships. Each rebuild is DELETE-all then re-INSERT inside a SAVEPOINT.
3. Explicit `forget`, which is a hard delete of one row plus a best-effort purge of the derived rows keyed to it.
4. A write-time dedup that decides ADD, UPDATE or SKIP. Its UPDATE **overwrites the old memory in place**, even though its docstring says the old memory is superseded and not deleted.

Contradictions are found by about 11 regexes run over all messages, and the result is a bitemporal-ish `fact_timeline` (`superseded_by`, `valid_from`, `valid_to`, `status`). At query time this surfaces as a "Current / History" supplement row. Superseded raw messages remain fully searchable. On agent-style text the regex detector has low recall and low precision (measured below).

The genuinely good, transferable ideas are:
- the **three-phase read, compute, short atomic write** discipline with a SAVEPOINT that preserves the prior derived artifacts on failure;
- **provenance lists** (`message_ids`) that make precise forget-cascade possible;
- **extractive, not generative** summaries;
- a **separate sub-budget plus a visible truncation marker** for always-loaded content;
- the measured decision to **kill fat per-entity profile sheets** because they saturate retrieval and leak superseded facts;
- the rule that **corrections must never be deduped away** and **number-divergent near-duplicates are distinct facts**.

---

## 1. Consolidation: what runs, in what order, and under which lock

### 1.1 Entry points and cadence (MEASURED-READ)

| Trigger | Where | Behaviour |
|---|---|---|
| Every N `add()` calls in the same process | `engine.py:361-366` (N = `TRUEMEMORY_AUTO_CONSOLIDATE_EVERY`, default **25**), `engine.py:800`, `engine.py:813-829` | In-memory counter `_adds_since_consolidation`. Spawns a daemon thread `_bg_consolidate`. Skipped if a previous thread is still alive. |
| Startup "if stale" | `engine.py:584`, `engine.py:658-677` | If `messages >= N` **and `message_clusters` is empty**, spawns a `startup-consolidate` thread. |
| MCP tool `truememory_consolidate` | `mcp_server.py:1630-1648` | Synchronous `engine.consolidate()`. The docstring says to call it "at session end (via hooks)". `grep consolidate` over `truememory/ingest` and `truememory/hooks` found **no hook that calls it**. |
| Bulk `ingest()` | `engine.py:1427-1670` | 14 steps, including consolidation steps 6, 7, 12 and 13. |

**CHANGELOG drift**: the CHANGELOG says the default is 100 (`CHANGELOG.md:124-125`). The code and test say 25 (`engine.py:363-364`, `tests/test_consolidation_gaps.py:95-99`).

**Cadence defects:**
- **The counter is per process, so hook processes almost never hit the threshold** (MEASURED-READ). The counter lives on the engine instance (`engine.py:362`). Claude Code hook processes (`hooks/core.py:490,673`, `ingest/pipeline.py:379`) construct a fresh `Memory()` each run and store only a few facts, so N=25 is effectively reached only in long-lived MCP servers.
- **The startup staleness sentinel is an optional feature's output** (MEASURED-RUN, `probe_cadence.py` then `probe_cadence.out`). `hdbscan` is an optional extra (`pyproject.toml:48-52`), but `_HAS_CLUSTERING` is True whenever `clustering.py` imports (it imports only numpy; `hdbscan` is imported lazily at `clustering.py:126`; the flag is set at `engine.py:235-240`). Without hdbscan, `cluster_messages` raises, `message_clusters` stays at 0 rows forever, and **startup consolidation re-fires on every engine open**. Measured: 3 simulated opens spawned 3 `startup-consolidate` threads; the `consolidate()` stats show `cluster_messages: ERROR: No module named 'hdbscan'` and `message_clusters rows after consolidate: 0`.

### 1.2 `engine.consolidate()` order (MEASURED-READ `engine.py:1014-1152`)

All steps run under `self._write_lock`, a `threading.Lock` (`engine.py:338`, held at `engine.py:1066`). Each step is wrapped in try/except, and stats record `"ERROR: ..."` rather than raising.
1. `cluster_messages` (only if `_HAS_CLUSTERING and _has_vectors`), `engine.py:1067-1074`
2. `extract_preferences(conn)`, `engine.py:1076-1082`. **A no-op**: `personality.py:583-584` returns `{}` when `entity is None`, and it never writes to the DB even with an entity (`personality.py:559-685` only returns a dict). Measured timing is `extract_preferences: 0.000s` (`probe_cadence.out`). The test `test_consolidate_calls_extract_preferences` mocks it and asserts only that it was called (`tests/test_consolidation_gaps.py:57-68`).
3. `build_summaries`, `engine.py:1084-1089`
4. `detect_contradictions`, `engine.py:1091-1096`
5. `build_structured_facts`, `engine.py:1098-1103`
6. `build_surprise_index` (predictive), `engine.py:1105-1111`
7. `detect_episodes` and `detect_landmark_events` (temporal), `engine.py:1113-1127`
8. `build_dunbar_hierarchy(primary = most frequent sender)`, `engine.py:1129-1147`
9. `conn.commit()`, `engine.py:1149`

Entity sheets (`build_entity_summary_sheets`) are **not** in `consolidate()`. They exist only in `ingest()` step 12, behind `TRUEMEMORY_ENTITY_SHEETS=1` (`engine.py:1624-1652`).

### 1.3 Lock and transaction model (MEASURED-READ plus tests)

- **Two lock layers:**
  - The in-process `threading.Lock` `_write_lock` serializes `add`, `update`, `delete` and `consolidate` (`engine.py:746,844,870,1066,1192`). Test #484 asserts that `build_summaries` runs with the lock held (`tests/test_issue_484_consolidate_lock.py:30-55`).
  - SQLite WAL with a busy_timeout pragma covers cross-process writers (`storage.py:590-592`).
- **Three-phase pattern (#401, #591)**: read all messages, compute in memory, then a short write. Implemented in `build_summaries` (`consolidation.py:895-1068`), `detect_contradictions` (`consolidation.py:819-865`) and `build_structured_facts` (`consolidation.py:1582-1604`). The tests hook the compute function and prove that a second connection can write during compute (`tests/test_consolidation_lock.py:56-101`, `tests/test_issue_591_consolidation_txn.py:160-205,318-358`).
- **SAVEPOINT write wrapper `_consolidation_write`** (`consolidation.py:46-98`, #649 and #692):
  - It nests in the caller's transaction without committing it.
  - `ROLLBACK TO` on error means the DELETE plus re-INSERT is atomic, so the **prior derived table survives a failed rebuild**. Tests: `tests/test_consolidation_lock.py:104-135`, `tests/test_issue_591_consolidation_txn.py:207-250`, `tests/test_issue_692_build_summaries_txn.py:38-69`.
  - Root-cause story (CLAIMED in docstring, `consolidation.py:60-64`): the old code's `conn.commit()` silently committed a caller's in-flight writes, causing "a live lock incident".
- **Where the discipline is not applied** (MEASURED-READ):
  - `consolidate()` holds the **Python** `_write_lock` for the whole run, compute included (`engine.py:1066-1149`). In-process `add()` therefore blocks for the full duration. Only the SQLite write lock was shortened.
  - `cluster_messages` does DELETE, then HDBSCAN compute, then INSERT, then `conn.commit()` (`clustering.py:128-189`). It holds a SQLite write transaction through the HDBSCAN compute and commits the caller's transaction. `_init_cluster_tables` uses `executescript` (`clustering.py:60-63`), which implicitly COMMITs in pysqlite.
  - `build_entity_profiles` (`personality.py:555`), `build_dunbar_hierarchy` (`personality.py:1309`) and `build_entity_summary_sheets` (`consolidation.py:1479`) each call `conn.commit()` directly.
- **Shared connection across threads**: `_bg_consolidate`'s docstring says "with its own connection" (`engine.py:832`), but it calls `self.consolidate()` on the shared `self.conn`, opened with `check_same_thread=False` (`storage.py:578`, `engine.py:1290`). The tests themselves note that cross-thread SQLite "causes segfault on Python 3.14" and disable startup consolidation to avoid it (`tests/test_consolidation_gaps.py:20-21`).
- **Summary-table clobbering order**: `build_summaries` does `DELETE FROM summaries` for **all** periods (`consolidation.py:1059`), which includes `structured_fact` and `entity_profile` rows. It works only because `build_structured_facts` runs after it. `build_structured_facts` deletes only its own period (`consolidation.py:1594`), and a test checks that it does not clobber other periods (`tests/test_issue_591_consolidation_txn.py:292-310`).

### 1.4 Cost (MEASURED-RUN `probe_scale.py` then `probe_scale.out`, synthetic corpus dense in trigger words, so read it as near worst case)

| n messages | build_summaries | detect_contradictions | structured_facts | fact_timeline rows | summaries (rows / chars) |
|---|---|---|---|---|---|
| 1,000 | 0.10 s | 0.03 s | 0.05 s | 706 | 19 / 50,841 |
| 5,000 | 0.32 s | 0.18 s | 0.20 s | 3,520 | 19 / 214,314 |
| 20,000 | 1.74 s | 3.62 s | 2.27 s | 14,356 | 19 / 860,851 |

Every consolidation is a **full rebuild over all messages**, with no incremental path. `fact_timeline` IDs are therefore unstable across runs (`DELETE FROM fact_timeline` at `consolidation.py:837`).

---

## 2. Contradiction handling and supersession

### 2.1 Detection (MEASURED-READ `consolidation.py:237-351`, `432-779`)

`_CHANGE_PATTERNS` has 11 regexes, each typed:
- `explicit_change`: "switched/migrated/moved from X to Y", "replaced X with Y"
- `pricing`: `$N per/ unit`
- `location_change`
- `status_change`: "Name quit/joined/…"
- `schedule_change`
- `informal_correction`: "actually / correction: / update:"
- `negation_change`: "not X anymore / no longer X"
- `invalidation`: "that's wrong/incorrect/outdated"
- two `retraction` forms: "changed my mind about / I was wrong about / turns out X", and "scratch that / disregard / never mind"

The **subject key** comes from `_normalize_subject` (`consolidation.py:380-390`). A small keyword map sends "postgres", "clickhouse" and similar to `database`, and "office" to `office_location`, and so on (`consolidation.py:354-373`). The check is **`keyword in raw or keyword in context`**, where `context` is the whole message. Otherwise the subject is the raw value, lowercased with spaces turned into `_`, truncated to 50 characters.

**Supersession rule**: within a subject, the latest occurrence in timestamp order supersedes the previous one:
- `superseded_by = new_id`, `status='superseded'`, `valid_to = new timestamp` (`consolidation.py:853-863`).
- There is no per-fact confidence score or semantic check.
- `status_change`, `invalidation` and no-capture `retraction` **never create supersede links** (`consolidation.py:608-633,714-728,764-777`).

### 2.2 Measured behaviour on agent-memory-style text (MEASURED-RUN `probe_contradictions.py` then `probe_contradictions.out`)

| Case | Input | Result |
|---|---|---|
| A: correction of a prior fact | "The deploy script lives at bin/deploy.sh", then "Actually the deploy script lives at scripts/deploy.sh" | **No supersession.** One row, subject `the_deploy_script_lives_at_scripts/deploy` (whole sentence, truncated at the `.`). The first fact is not recorded at all. |
| B: explicit chain | "switched from PostgreSQL to ClickHouse", then "migrated from ClickHouse to DuckDB" | Works: PostgreSQL→ClickHouse→DuckDB, and `search_contradictions('what database')` returns DuckDB. |
| C: normaliser collision | "switched from Heroku to Fly because the office wifi was slow" | Filed as **`office_location`** Heroku→Fly. "Actually the standup is in the morning now" becomes subject **`gym_schedule`**. "moved from Jest to Vitest; see…" is **missed** because `;` is not in the terminator class. |
| D: "Scratch that, we will use NATS" after "use Redis" | | Only a `_retraction` marker row. **Redis is not superseded.** |
| E: "Dev joined", then "Dev left" | | Both rows `active`; no contradiction recorded. |
| F: assistant tool narration | "Turns out the test was flaky…", "Actually running the linter now.", "That's wrong path…" | **3 junk fact rows** (false positives). |

The cadence probe gives a false-positive rate estimate: 30 agent-style messages produced **25 fact_timeline rows** (`probe_cadence.out`).

### 2.3 Surfacing (MEASURED-READ)

- **`search_contradictions`** (`consolidation.py:1071-1181`) works as follows:
  - It drops stopwords from the query.
  - For **every distinct subject** it runs one SELECT (N+1 queries).
  - A subject matches when a query word is a *substring* of the subject or a fact.
  - The current fact is the last non-superseded one. If every row is superseded, it falls back to the last row with relevance multiplied by 0.5.
  - It returns **all** matches, uncapped.
- **Engine injection**: every contradiction result is appended with `score = 0.8 × max existing score`, so it survives the top-K slice before reranking (#581; `engine.py:1947-1981`). The loop has **no cap**.
  - MEASURED-RUN (`probe_search.py` then `probe_search.out`): on a synthetic corpus with 8,623 subjects, the query "which tool do we use for deploys" returned **8,623** contradiction rows in 57 ms, because "tool" is a substring of every `toolNNN` subject.
- **`search_consolidated`** adds up to 5 "[Fact Timeline: subject] Current: X / History: ts: fact (superseded|current)" blocks with score `relevance*2` (`consolidation.py:1315-1338`). The engine then rescales them to `0.8 × pool max` (#633; `engine.py:1983-2014`).
- **Raw superseded messages are never down-weighted.** The message "We use PostgreSQL" still ranks normally through FTS and vector search. Only the supplement row carries the "current" signal.
- Salience-guard fix: contradiction rows lacked a `content` key and scored 0. They are now given `content = current_fact` (`engine.py:1966-1972`; tests `tests/test_issue_581_contradiction_inject.py:19-86`).

### 2.4 Write-time supersession in the ingest pipeline (MEASURED-READ)

- `dedup.check_duplicate` (`ingest/dedup.py:117-245`) chooses ADD, UPDATE or SKIP. Stage 1 is a vector search limited to 3 results.
- **Corrections are never SKIPped.** If the fact is a correction (by category or by the shared `UPDATE_MARKERS` in `ingest/markers.py:30-…`), it is routed to the LLM, or to heuristic UPDATE (`dedup.py:184-195`, `340-348`). CLAIMED motivation (#576/#649): the gate and dedup used different vocabularies, so corrections passed the gate and were then SKIPped as duplicates.
- **Number divergence**: above 0.92 cosine similarity without an LLM, a pair whose digit runs differ is **ADDed as a distinct fact** (`dedup.py:196-215`, #687).
- **Score-space contract**: the 0.92 threshold is trusted only when the score is a true cosine (`score_space == "cosine"`). Fused or relative scores defer to the LLM or to word overlap (`dedup.py:169-176,224-231`; `client.py:186-193,208-228`).
- The heuristic path (`dedup.py:323-409`) works as follows:
  - Substring containment gives SKIP (new is a subset of old) or UPDATE (new expands old).
  - Jaccard above 0.60 means the longer version wins.
  - Similarity above 0.75 with update markers gives UPDATE.
- **The UPDATE is an in-place overwrite**, contradicting `dedup.py:11` ("the old memory is superseded (not deleted)"):
  - `pipeline._update_fact` calls `Memory.update(existing_id, new_content)` (`ingest/pipeline.py:732-759`), which calls `engine.update` (`engine.py:1154-1231`), which calls `storage.update_message` (`storage.py:1150-1182`). That is `UPDATE messages SET content=?`.
  - The old text is lost.
  - The **timestamp is not updated** (only fields passed are changed; `client.update` passes only content, `client.py:282-294`), so the corrected fact keeps the original date.
  - `fact_timeline` and summaries keep the old content until the next full consolidation.
  - The recall cache is invalidated (`client.py:290-293`).

### 2.5 Directive contradictions (MEASURED-READ)

There is no code-level check. The MCP instructions tell the model: "If a new instruction contradicts an existing directive, remove the old directive first, then store the new one" (`mcp_server.py:383-384`). Exact-content directive dedup exists (`client.py:116-136`, #638).

---

## 3. Forgetting, decay and pruning

- **No time-decay, TTL, archival or capacity eviction exists for memories** (MEASURED-READ: `grep -E "forget|decay|prune|expire|half.?life|evict"` over `truememory/` shows only telemetry, log, marker and buffer pruning: `ingest/hooks/stop.py:86-202`, `instrumentation/writer.py:102-135`, `mcp_server.py:1791`, `session_start.py:489-493`). The message store grows without bound. Only derived tables are rebuilt.
- **Explicit forget**: `truememory_forget(memory_id)` is `alwaysLoad` (`mcp_server.py:1216-1228`, #566, test `tests/test_issue_566_forget_always_load.py`). It calls `client.delete` then `engine.delete`, which calls `storage.delete_message` (`storage.py:1050-1147`):
  1. It deletes vector rows across all tier tables (`storage.py:1073-1085`, #589).
  2. It deletes message-keyed children: `fact_timeline`, `landmark_events`, `surprise_scores`, `message_clusters`, `causal_edges` (`storage.py:1087-1101`). FKs are also `ON DELETE CASCADE` (`storage.py:101,134,144-145,175,180`), with `PRAGMA foreign_keys=ON` (`storage.py:592`).
  3. **Right-to-be-forgotten (#685)**: it deletes any summary whose `message_ids` JSON lists the id (`storage.py:1119-1127`, via `json_each`). It also deletes `summaries`, `entity_profiles` and `entity_style_vectors` rows `WHERE entity = <sender or recipient>`, and `entity_relationships` for that entity (`storage.py:1103-1141`). These are "rebuilt clean on the next consolidation".
  4. The FTS row goes via trigger (`storage.py:60-62`), and the recall cache is invalidated (`client.py:296-304`).
- **Case-mismatch bug in the forget cascade** (MEASURED-RUN, `probe_contradictions.out` case G):
  - Derived entity rows are keyed **lowercase** (`personality.py:931-932`, `personality_style_vec.py:187-188`, `consolidation.py:994`).
  - `delete_message` deletes `WHERE entity = <raw sender>` (`storage.py:1116,1129-1134`).
  - With sender `"Josh"`, the `entity_profiles` and `entity_style_vectors` rows for `josh` **survive** the forget. A lowercase `josh` summary without `message_ids` also survives.
  - Test #685 seeds only lowercase `josh`, so it cannot catch this (`tests/test_issue_685_forget_derived.py:21-45`). `delete_all` does lowercase (`engine.py:904-935`, #501).
  - Real-world impact is bounded: profiles store traits and topics, not verbatim text, and real `entity_monthly` summaries list `message_ids`, so the precise path catches them.
- **Dangling supersession after forget** (MEASURED-RUN, case H): deleting the message that carried the newer price removes its `fact_timeline` row. The old row keeps `status='superseded'` and `superseded_by=<deleted id>`. `search_contradictions` then returns the old `$200` at relevance 0.5, still labelled superseded, until the next full consolidation re-derives the table.
- **Directive injection cap** (`ingest/hooks/session_start.py:88,828-859,968-1008`):
  - `DIRECTIVE_LIMIT=50` keeps the **newest** directives (#638 M-92).
  - A separate character **sub-budget** fraction (`_DIRECTIVE_BUDGET_FRACTION`) stops directives from evicting the recall block.
  - Overflow appends an explicit marker: `- [directives truncated — over budget; prune with truememory_forget]`, or "(k of n directives shown …)".
  - **Inconsistency** (MEASURED-READ): after the newest-first fetch the rows are re-sorted ascending (`session_start.py:855`) and the budget loop breaks at the first overflow (`:985-996`). Under *character* pressure the **newest** directives are the ones dropped, the opposite of the count cap.

---

## 4. Summaries (MEASURED-READ `consolidation.py:868-1068`)

- The summaries are **extractive**, never generated. The docstring says: "keeps the system local, fast, and hallucination-free" (`consolidation.py:885-887`).
- **Monthly**:
  - Messages are grouped by `YYYY-MM` and scored with the heuristic `_message_salience`, which uses length, numbers, event verbs and proper nouns (`consolidation.py:142-184`).
  - "**Ring-width**" sizing: `ring_width = high_salience_count + 2 × fact_change_count`. Coverage is top max(25, n/3) if ring_width > 10, max(15, n/5) if > 5, else max(8, n/8) (`consolidation.py:922-940`).
  - Each sentence is then re-scored (`_score_sentence`, `consolidation.py:194-228`). The top max(20, n/3) sentences are kept, restored to chronological order and prefixed `[sender]` (`consolidation.py:945-963`).
- **entity_monthly**: senders with at least 10 messages get, for each month with at least 3 messages, the top max(5, n/4) messages truncated to 500 characters (`consolidation.py:990-1044`).
- **Provenance**: each row stores `message_ids` (JSON) and `key_facts` (extracted numbers). `message_ids` is what makes the precise forget purge possible.
  - Leak (MEASURED-READ): monthly `key_facts` come from `top_messages` (`consolidation.py:965-970`), but `message_ids` come only from `top_sentences` (`:963`). A message whose numbers entered `key_facts` but none of whose sentences survived is not listed. Forgetting it leaves its numbers in that monthly row. The entity sweep does not cover this, because the monthly row has `entity=''`.
- **Structured facts** (`consolidation.py:1483-1604`): a regex team roster (`X is our CTO`, `hired X`) and "Known Locations", as `period='structured_fact'`.
- **Search**:
  - `search_consolidated` (`consolidation.py:1184-1361`) scores keyword overlap plus a month/year time bonus.
  - Since #689 (PERF-01) it short-circuits when both tables are empty (`consolidation.py:1212-1228`). The CLAIMED cost of that fallback was "≈44% of search cost at scale".

## 5. Entity sheets (L4): disabled, with a measured-by-authors rationale

- `build_entity_summary_sheets` (`consolidation.py:1364-1480`) builds one fat row per sender with at least 5 messages. The row holds counts, active period, top contacts and 10 "notable messages".
- It is deprecated and disabled by default (`engine.py:1624-1652`). There is a one-time idempotent purge of legacy rows, flagged in `metadata.l4_entity_profile_migration_done` (`engine.py:586-656`).
- Tests: `tests/test_l4_entity_sheets_disabled.py` (13 tests: default off, env var accepts variants, purge idempotent across opens, other stages preserved).
- **CLAIMED rationale** (`CHANGELOG.md:377-380`, `consolidation.py:1369-1380`, `engine.py:1625-1636`): monolithic per-entity rows "saturated top-1 retrieval by keyword match and leaked superseded facts into contradiction scoring". Disabling was "Pareto-dominant (+5.3% relative composite, +3.2 pts contradiction accuracy, −4 KB/persona storage)".
- The supporting `REPORT.md` (`_working/memorist/l4_consolidation/REPORT.md`, referenced in the test docstring) **is not in the repo**, so the numbers are CLAIMED and not reproducible here.
- Why it matters for us: this is the strongest evidence in the codebase that **aggregate restatement artifacts hurt**. They are stale copies that keep superseded facts alive and out-rank the atomic fact.

## 6. Personality and style (L0)

- **Entity profiles**:
  - Bulk build (`personality.py:441-556`): keyword-cluster topics and traits, formality, emoji use, greeting, per-recipient topic.
  - Incremental build on each `add()` (`personality.py:910-1053`; called at `engine.py:780-789`, skipped for directives, #637): a rolling average length; `uses_emoji` sticky-ORed; formality frozen after the first message.
  - **topics and traits are a monotone union and never decay** (`personality.py:1001-1002,1019-1023`).
  - Trait matching is **substring**: "care" matches "career", "run" matches "brunch" (`personality.py:1004-1022`).
- **Style vectors** (`personality_style_vec.py`):
  - 256-dimension hashed character 3-, 4- and 5-grams, L2-normalized, with md5 as a stable hash (`:32-68`).
  - The incremental running mean is `(v*count + new)/(count+1)`, then renormalized (`:165-233`). There is no recency weighting.
  - CLAIMED: 0.686 vs 0.271 accuracy against the keyword approach (`CHANGELOG.md:381-384`).
- **search_personality** (`personality.py:688-907`): aspect keyword detection, FTS candidates, then score = 5.0 (same entity) + 0.5·cos(query) + 0.5·cos(profile). It prepends "profile" summary rows at score 1.0.
- **Dunbar hierarchy** (`personality.py:1242-1310`) is computed only for the single most-frequent sender. Layers come from frequency ratio thresholds 0.6, 0.3 and 0.1. The docstring says "frequency/recency", but recency (`last_ts`) is stored and **never used**.

## 7. Clustering (`clustering.py`)

- HDBSCAN (min_cluster_size 10, min_samples 5) runs on L2-normalized embeddings, followed by centroids and a session_range (`clustering.py:107-191`). The `summary` column is never populated.
- `search_clustered` (`:198-347`) does two stages (top 3 centroids, then cosine within them). It is used only as a supplement in `search_agentic` (`engine.py:2216-2225`), gated on live vectors (M-78).
- It is a full rebuild with no incremental path. Transaction hygiene is **not** applied (§1.3).

## 8. MEMORY.md migrator (`ingest/migrate_memory_md.py`): what happens to *our* format

MEASURED-RUN (`parse_memory_md` on the synthetic `MEMORY.sample.md` in our index shape, output in `probe_migrate.out`):
- `- [Title](file.md) — hook` becomes `"<## header>: Title — hook"`. Only the **index hook** is imported.
- The linked **topic files are never opened** (the parser reads only the one file: `migrate_memory_md.py:45-121`). All real fact content in our store would be lost.
- A pure-link bullet with no hook (`- [cc-memory-rotate](cc-memory-rotate.md)`) is **dropped entirely** (`_PURE_LINK_RE`, `:17,82-83`).
- A nested bullet emits the parent text a second time with the child appended (`:101-110`), producing a near-duplicate row.
- Frontmatter and HTML comments are skipped only because they are not bullets. `>` lines and `#` H1 are skipped explicitly.

MEASURED-READ:
- `migrate()` calls `Memory.add(content, user_id="MEMORY.md migration")` (`:168-177`). **category is computed and then dropped**, and the sender becomes the fake entity "MEMORY.md migration". That entity gets its own profile and style vector.
- The docstring says "The encoding gate handles deduplication automatically" (`:4-6`). In fact `Memory.add` calls `engine.add` with **no gate and no dedup** (`client.py:95-150`; only exact-directive dedup exists).
  - The `duplicates` and `skipped` counters are never incremented (`:137-143`), so the CLI always prints 0 for both (`ingest/cli.py:837-841`).
  - A re-run duplicates every row.
- `auto_detect_memory_md()` returns the **first non-empty MEMORY.md in sorted `rglob` order** under `~/.claude/projects` (`:31-42`). That is an arbitrary project.
- `--slim` **overwrites MEMORY.md** with a 4-line template (`:22-28,179-180`).
- The backup is a single `.md.bak`, overwritten on each run (`:148-151`).

## 9. Test quality notes (MEASURED-READ)

- `test_issue_498_auto_consolidate.py` contains only `inspect.getsource` string checks (`:13-33`), with no behavioural assertion.
- `TestSupersedeStatus.test_informal_correction_supersedes` asserts only `len(rows) >= 1` (`tests/test_issue_580_contradiction_record.py:234-251`). Supersession does not actually happen in that scenario (probe case A).
- `test_superseded_ranked_lower` does not test the 0.5 halving it names (`:280-291`).
- `test_casual_actually` has no real false-positive assertion (`:301-313`).
- `test_issue_685` uses only lowercase senders (it misses the case bug in §3).
- `test_consolidate_calls_extract_preferences` mocks a function that is a no-op in production.

---

## 10. Transfer ideas for our file-based Claude Code memory workflow

Our anchors are:
- `bin/cc-memory-rotate`: durability rank, with `superseded_by:` as rank 0 (`bin/cc-memory-rotate:86-100`), mkdir lock with 180 s stale reclaim, temp+rename (`:108-119`).
- `commands/compact-memory.md`: `superseded_by:` doc at `:81-93`, and near-duplicates handled by a human who picks merge, keep or supersede (`:325-329`).
- `docs/plans/MEMORY_KNOWLEDGE_V2.md`.

| # | TrueMemory mechanism | Transfer | Fit |
|---|---|---|---|
| T1 | `fact_timeline` `superseded_by`, `valid_to`, `status` and "Current / History" surfacing | We already have `superseded_by:` frontmatter, but it is used only as an eviction rank. Add a **read-time redirect**: a PostToolUse(Read) hook that, when a topic file with `superseded_by:` is read, injects "superseded by <heir> on <date>; read that instead". Optionally add a `supersedes:` back-pointer plus a date in the heir, and a lint that flags **dangling or cyclic chains** (TM's case H shows a dangling pointer is the natural failure). | High |
| T2 | Forget cascade over derived artifacts, keyed by provenance (`message_ids`), plus cache invalidation | A `/forget-memory <name>` procedure or script. It deletes the topic file and removes **every derived copy**: the MEMORY.md index line, archive/COLD lines, `[[name]]` links, lessons hook lines, and harvest outputs. It then re-runs the orphan sweep. Lesson from bug G: **normalize the key identically at write and delete time** (slug case, `.md` suffix, symlinked store path). | High |
| T3 | Three-phase read → compute → short atomic write, with SAVEPOINT rollback that preserves the prior artifact | The rotor already does temp+rename. Make it a stated invariant for *every* derived-artifact rebuild (index regeneration, lesson hook tier, archive): never "clear first, then fill"; a failure must leave the previous file intact. TM's regression tests (a concurrent writer during compute, a forced write failure preserving the prior state) are a **test template** for our side-cars. | Medium (mostly present) |
| T4 | Kill fat per-entity sheets (CLAIMED +3.2 pts contradiction accuracy) | Supports our one-fact topic-file policy. Forbid "profile" or "summary" topic files that restate facts owned by other topic files. Index hooks stay pointers, not restatements. Compact-memory should flag any topic file whose body quotes three or more other topic files' facts. | High (cheap policy) |
| T5 | Corrections are never deduped away; number-divergent near-duplicates are distinct | Amend the anti-duplicate rule. A near-duplicate that differs in a number, date, version, path or SHA is **not** a duplicate. A correction must land as a supersede (edit plus `superseded_by:` or an in-file CORRECTED passage), never be skipped as "already known". A cheap check: diff the digit runs and paths of the candidate pair. | High |
| T6 | Anti-pattern: in-place UPDATE loses history and keeps the old timestamp | When a harvest or nudge updates a topic file, keep the prior claim as a dated CORRECTED passage (which our corpus already does: 26/388 files). **Bump a `verified:` or `updated:` date** so recency is truthful. | Medium |
| T7 | Visible truncation marker plus separate sub-budget for always-loaded content | When MEMORY.md exceeds the 25,000-character or 200-line cap, emit an explicit marker line ("index truncated at N; run /compact-memory") rather than a silent cut. Reserve a sub-budget for the highest-durability rank. Avoid TM's bug: make the count cap and the character cap drop the **same** end. | Medium |
| T8 | Cadence: every N adds plus startup-if-stale | Our nudges could fire compaction after N new topic files since the last compaction. **The counter must be persisted on disk** (TM's in-process counter never trips in short hook processes). **The staleness sentinel must be something the consolidation itself always writes**, such as `archive/.last-compact` with a timestamp, never an optional feature's output (TM's startup trigger re-fires on every open). | Medium |
| T9 | Extractive, provenance-carrying summaries | Any compaction or rollup that writes summary text should be extractive (quote the source lines) and list its source topic names, so forget and supersede can cascade precisely. | Medium |
| T10 | Regex contradiction detection (`actually`, `turns out`, `no longer`) | **Do not transfer.** Measured low precision and recall on agent text (§2.2). This independently corroborates our rotor's refusal to match prose SUPERSEDED/CORRECTED markers (`bin/cc-memory-rotate:93-100`). | Negative result |
| T11 | Monotone trait accretion, rolling style vectors, Dunbar layers | No transfer, except as an anti-pattern: accumulated "traits" or "preferences" with no decay or evidence pointer become permanent after one mention. Any operator-preference memory needs a source and date. | Low |
| T12 | Ring-width summary sizing (event-heavy periods get more detail) | Possible: archive rollups give more lines to periods with more corrections or decisions. | Low |
| T13 | MEMORY.md migrator | No value to us. It confirms that a naive importer takes only the index hooks. If we ever export, the topic files are the unit, not the index. | Negative result |
