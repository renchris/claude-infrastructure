# TrueMemory — EXTERNAL EVIDENCE axis (paper, benchmark harnesses, issues, alternatives, licence)

Written 2026-09-27. Source clone: /tmp/truememory-src (shallow, 50 commits, HEAD 063e5b8).
Scratch artefacts: /tmp/tm-research/scratch/ (paper.pdf, paper.txt, issues.tsv, ext_issues.txt,
key_issues.txt, beam_compute_metrics.py, beam_run_eval.py).

Labels: **MEASURED** = I ran it or read the code/data myself (command or file:line given).
**CLAIMED** = README / paper / blog / issue says so and I did not reproduce it.
**ESTIMATED** = my own inference, method stated.

No prior TrueMemory study was found in this repo: `grep -ril truememory` over the repo's *.md returned nothing (MEASURED).

---

## 0. Verdict (short)

The headline numbers are **real outputs of the published harness**, but they are **inflated in absolute terms and weak as comparisons**:

1. **LoCoMo 93.0% equals "paste the whole conversation into context".** The paper itself reports a gpt-4.1-mini full-context oracle of 92.99%, against 92.96% for TM Pro (paper p.8 §6.1, paper.txt:441-458). Each LoCoMo conversation is only 11-22K tokens (MEASURED, see §2.1). On this benchmark the memory system adds **no accuracy over full context**. What it adds is cost: about 1/5 the cost per correct answer (CLAIMED).
2. **The judge is lenient by design and credits unfinished answers.** The prompt says "Be generous: if the generated answer mentions the same core topic/fact, mark CORRECT" (bench_truememory_pro.py:94-103). Answers are capped at 200 tokens after a "Think step by step" instruction, so about 40% of answers are cut off mid-reasoning (MEASURED). About 31% of TM Pro's credited answers are truncated with no final answer at all (MEASURED). A 40-item manual strict audit of TM Pro "correct" answers found 4 plainly wrong and 4 more with no committed answer (ESTIMATED 10-20% false-positive rate, see §2.3).
3. **LongMemEval 87.8% vs plain ChromaDB RAG 87.0%: a statistical tie.** The three TM runs span 86.6-88.6 (MEASURED from result JSONs). The README badge still shows the **oracle** 92.0% (README.md:18). The repo holds **no result files** for any `_s` baseline (MEASURED).
4. **BEAM-1M 76.6% "SOTA" does not use BEAM's official scoring.** It is a binary gpt-4o-mini judge against `ideal_response`. The rubric is loaded and never used (beam1m.py:136 vs :213). Event ordering is scored binary instead of Kendall-tau-b. An external user re-judged 60 of TM's own answers with a stronger judge: **76.7% → 51.7%**, and contradiction_resolution fell **6/6 → 0/6** (issue #716, CLAIMED by the reporter, unanswered by the maintainer).
5. **Competitor rows are partly misconfigured or unreproducible.**
   - Supermemory was ingested with no per-conversation container scoping and a fixed 90 s sleep. It then retrieved 0 items for 260/1540 LoCoMo questions and 114/500 LME questions (MEASURED).
   - EverMemOS numbers come from a pre-computed retrieval file that is not in the repo.
   - "Zep ≈71%" on LoCoMo matches no Zep or Mem0 LoCoMo figure. 71.2% is Zep's LongMemEval number.
6. **None of TM's distinctive "memory" features are measured.** The encoding gate is disabled in every benchmark (paper abstract, p.1). Its AUC claims (0.788 / 0.730 / 0.816) have no data in the repo: `benchmarks/gate_eval/` is absent and the test skips (MEASURED). The maintainer's own audit (#280) calls these CHANGELOG numbers "possible hallucinations".
7. **Benchmark path ≠ product path** (maintainer-filed #455 / #456 / #451). The benchmarks call `engine.ingest()`, a 14-step batch with consolidation, and `top_k=100`. MCP users got `add()` (4 steps, L5 tables empty) and `top_k=10`. This was "fixed" by exposing a manual `truememory_consolidate` tool.

**Trust rating (ESTIMATED):**
- LoCoMo absolute: low.
- LoCoMo ranking vs BM25 / RAG: moderate. TM > Chroma RAG by about 6.8 pp holds within the harness, but that RAG baseline uses a default MiniLM embedder.
- LME: the claimed lead is not supported.
- BEAM "SOTA": not supported.
- Engineering lessons in the issue tracker: high value, and in several cases directly transferable (§5).

---

## 1. The paper — arXiv 2605.04897v1

"Storage Is Not Memory: A Retrieval-Centered Architecture for Agent Recall", Joshua Adler & Guy Zehavi, Sauron Labs, submitted 2026-05-06, v1 only, "Technical report". The PDF has 17 pages (MEASURED with `pdfinfo`). Not peer reviewed (CLAIMED on the arXiv abstract page).

### 1.1 Thesis and method (CLAIMED, paper.txt:16-116)
- **Thesis:** extraction at ingestion is the wrong primitive. Store events verbatim and put the intelligence in a multi-stage retrieval pipeline.
- **Six layers L0-L5, ten stages** (paper.txt:137-370):
  1. Stage 1: an encoding gate built from three signals.
     - Novelty: gzip compression gain against nearest stored neighbours, `n = (|gz(M‖e)|−|gz(M)|)/|gz(e)|`.
     - Salience: a rule-based speech-act classifier for messages of 50 chars or fewer, else the length/number/date/emotion scorer.
     - Prediction error: `1 − cos(embed(e[SEP]m1), embed(m1[SEP]m1))`.
     - Weights (0.25, 0.20, 0.30), τ = 0.30. Per-category threshold offsets: correction −0.06, decision −0.04, relationship −0.04. Salience floor 0.10.
  2. Stage 2: the L1 writer (FTS5 plus sqlite-vec at 256d).
  3. Stage 3: L4 consolidation (summaries, contradiction records, timeline rows with superseded-by links).
  4. Stage 4: L5 "predictive coder", a surprise score from unseen fact fingerprints.
  5. Stage 5: L0 speaker engram (a preference map plus a char-n-gram style vector).
  6. Stages 6-8: FTS5 BM25 plus dense retrieval, fused with weighted RRF (k=60, w_sep=0.8).
  7. Stage 9: L3 reweighting (temporal ×1.3, personality injection at 0.8/0.9 × max, surprise ×(1+0.2σ)).
  8. Stage 10: cross-encoder rerank with a modality factor (detail ×0.7 on summaries, synthesis ×1.2).
- **Default top-k to the answer model is 10.** In benchmarks the pre-rerank window is 100 (paper.txt:366-370). In the code the answer model actually receives 100 items (§2.1).

### 1.2 Evaluation claims (CLAIMED)
- **LoCoMo Table 2** (paper.txt:490-517): EverMemOS 94.48, TM Pro 93.0, Base 92.01, Edge 89.65, RAG 86.17, Engram 84.55, BM25 80.45, Zep ~71 (published), Supermemory 65.39, Mem0 61.43.
- **Full-context oracle** (paper.txt:441-458): gpt-4.1-mini 92.99% [91.60, 94.16], 45.6M input tokens per run. Opus 4.6 full context: 96.75%. No context at all: 3.90%.
- **"Retrieval is the bottleneck"** (paper.txt:460-573): of 357 wrong answers from an early version, full context recovered 330 (92.4%).
- **LME Table 4** (paper.txt:589-604): TM oracle 92.0, TM S 87.8, RAG 87.0, EverMemOS 83.0 (their paper, gpt-4o), Engram 82.2, BM25 81.6, Mem0 66.0.
- **BEAM-1M** (paper.txt:612-637): 76.6 vs Hindsight 73.9. The paper admits "different answer model … not controlled".
- **Ablation** (paper.txt:655-976): a 56-config grid on **v0.4.0**, spread 89.9-93.1.
  - No-reranker cells score 89.9-91.2.
  - HyDE adds +1.0 pp.
  - Data "collected on the v0.4.0 pipeline; absolute scores may differ on v0.6.0" (paper.txt:684-707).

### 1.3 Limitations the paper states itself (paper.txt:779-795)
1. Gate disabled everywhere, so its contribution is unmeasured.
2. BEAM-1M is the longest horizon tested.
3. A semantic-match judge, "more lenient than exact-match … absolute accuracy numbers should not be compared directly".

### 1.4 Problems in the paper I found (MEASURED against repo / external sources)
- **P1. Category labels are wrong, and inconsistent between paper and repo.**
  - The paper's per-category recovery table (paper.txt:528-538) labels Cat1 "single-sess.", Cat2 "multi-sess.", Cat3 "knowl.-upd." and Cat4 "temporal". It concludes that "knowledge-update … hardest … consistent with contradiction-bearing questions".
  - The repo labels them Cat1 single-hop, Cat2 multi-hop, Cat3 temporal, Cat4 open-domain (BENCHMARK_RESULTS.md:31; bench_truememory_pro.py:138).
  - LoCoMo's released code maps 1=multi-hop, 2=temporal, 3=open-domain/commonsense, 4=single-hop (the known whitepaper/code mismatch; see the awesome-agent-memory note and Memori docs in Sources).
  - So the paper's "knowledge-update is hardest" is really "open-domain/commonsense is hardest". The repo's "Mem0 devastated on multi-hop 37.7%" (BENCHMARK_RESULTS.md:164) is really Mem0 at 37.7% on **temporal**, which fits Mem0's session-blob ingestion losing timestamps.
  - Correct-label per-category table (MEASURED, python over result JSONs):
    - TM Pro run2: multi-hop 92.6 / temporal 92.8 / open-domain 80.2 / single-hop 94.8
    - RAG: 86.9 / 84.4 / 79.2 / 87.4
    - BM25: 77.7 / 79.8 / 69.8 / 82.9
    - Mem0: 78.0 / **37.7** / 74.0 / 63.5
- **P2. Table 1 disagrees with the scripts.** It says BEAM max answer tokens is 200 (paper.txt:487). The BEAM script uses 500 (beam1m.py:38) and the BEAM README says 500.
- **P3. "Zep ~71%" for LoCoMo is unsourced.**
  - Zep's own LoCoMo claims are 84%, later revised to 75.14%. Mem0 reported 58.44% / 65.99% for Zep.
  - 71.2% is Zep's **LongMemEval** gpt-4o number.
  - ESTIMATED: a conflation.
- **P4. "Leads every agent memory product on LME by ≥4.8 pp" is outdated.** Published LongMemEval_S results under the official gpt-4o judge include Mastra OM 94.87% (gpt-5-mini), 84.23% (gpt-4o), and OMEGA 95.4% (CLAIMED by those vendors). The comparison also mixes judges.
- **P5. "Rankings are valid because every system is scored identically" does not hold here.**
  - The judge credits truncated, uncommitted reasoning.
  - The share of each system's credit that comes from truncated no-final-answer outputs varies widely (MEASURED, §2.3): EverMemOS 11.5%, TM ~30%, RAG/BM25 ~40%.
  - So leniency interacts with context style and verbosity, not only with correctness.
- **P6. Artefacts behind key claims are missing.** The paper says "code, evaluation harness, and benchmark outputs are available" (paper.txt:775-777). These are not in the repo (MEASURED, `git ls-files | grep -i 'full_context|oracle|ablation|grid|sweep|auc'` found only tests/test_gate_eval_harness.py):
  - the full-context oracle JSON (`full context gpt4mini.json`, cited at paper.txt:526);
  - the 56-cell ablation outputs;
  - the gate AUC sweeps (`benchmarks/gate_eval/`, which the test skips when absent: tests/test_gate_eval_harness.py:21-22).
- **P7. Near the label-noise ceiling.** The LoCoMo audit found 99/1540 (6.4%) wrong gold answers, a theoretical ceiling of 93.57% (dial481/locomo-audit, CLAIMED). TM (93.0) and EverMemOS (94.5, which is *above* that ceiling) sit where judge leniency and key noise dominate. The same audit found gpt-4o-mini accepts **62.81%** of deliberately wrong "vague-but-topical" answers. The audit also found gpt-4.1-mini full context with a CoT prompt gets 92.62%.
- **P8. Is the "no GPU" framing true?** It is CLAIMED for deployment. The benchmarks ran on T4, A10G and A100-80GB (bench_truememory_pro.py:307; longmemeval diff lines 262; beam README). This is fine for speed, but the latency and hardware claims are not what was benchmarked.

---

## 2. Benchmark harnesses — how the numbers are produced

### 2.1 LoCoMo (benchmarks/locomo/)
- **Pipeline** (bench_truememory_pro.py):
  1. Answer model gpt-4.1-mini, `max_tokens=200`, temp 0 (:50-52).
  2. Judge gpt-4o-mini, `max_tokens=10`, 3 votes, majority (:53-56, :120-134).
- **Answer prompt is tuned to LoCoMo** (:73-92). It opens "personal conversations between friends", includes date-arithmetic hints ("If someone says 'last year' and the message is from 2023…") and ends "Think step by step, then give your final answer". The same prompt is used for all systems, so this is not an unfair advantage, but it is dataset-specific prompt engineering.
- **Judge prompt** (:94-103): the system prompt says "strict". The user prompt says "**Be generous**: if the generated answer mentions the same core topic/fact, mark CORRECT". The judge receives the **entire** generated text, including chain-of-thought, not an extracted final answer.
- **Harness-side temporal preprocessing for all systems** (`_rtime`, :158-168): it rewrites "yesterday", "last week", "last year", "recently" (+7 days) and similar into "(approximately <date>)" inline before ingestion. The same code is in every bench script (e.g. bench_bm25.py:146-167). This is benchmark-specific help that a production memory would not get from the harness.
- **Category 5 (adversarial) is excluded** (:185). This is standard practice but removes the abstention test.
- **Retrieval depth.** Every system passes `limit=100` (TM :245-246; bm25 top-100; rag `n_results=100` bench_rag.py:189; mem0 `limit=100` bench_mem0.py:204; supermemory :207). Inside TM, `search_agentic` builds a candidate pool of `max(limit*8,100)` = **800** (truememory/engine.py:2184).
  - MEASURED conversation sizes (python over data/locomo10.json): 369-689 messages, about 10.9K-22.4K tokens (chars/4) per conversation.
  - So TM's candidate pool covers **every message**, and the cross-encoder reranks the whole conversation.
  - The top 100 handed to the answer model are **15-27% of the entire conversation**.
  - ESTIMATED: this is why TM equals the full-context oracle. The task is "rerank a small corpus and pass a fifth of it", not long-horizon memory.
- **Silent failure risk.** `engine.ingest()` wraps each of its 14 steps in try/except and logs at DEBUG (engine.py:1427-1560+). A benchmark run can silently lose layers such as clustering or consolidation. This matches maintainer issues #696 and #720 ("hdbscan missing causes silent consolidation failure").
- **Baselines.**
  - **Mem0**: sessions ingested as one text blob each (bench_mem0.py:193-200), default `all-MiniLM-L6-v2` embedder (:187), gpt-4o-mini extraction.
  - **Supermemory**: all sessions `add(content=txt)` with **no container tag or user scoping**, then a fixed `time.sleep(90)` (bench_supermemory.py:183-193). It then searched unscoped. MEASURED: 260/1540 questions retrieved **0** memories. With 10 conversations spawned in parallel against one account, cross-conversation contamination is also likely (ESTIMATED).
  - **EverMemOS**: reads `evermemos_retrieval.json` from a Modal volume, pre-built by the EverMemOS team (bench_evermemos.py:6-17, :186). The file is not in the repo and cannot be reproduced.
  - **RAG baseline**: Chroma with its default embedder (all-MiniLM-L6-v2). A stronger dense baseline, e.g. Qwen3-Embedding + BM25 hybrid with no other layers, was never run. The v0.4 ablation cells "qwen3 256d × no reranker" (91.2%) and "model2vec 256d × no reranker" (89.9%) are the closest proxies. Both still include HyDE and TM's other layers, so the marginal value of L0/L3/L5 is never isolated.
- **verify_scores.py** only recounts the stored `correct` booleans (verify_scores.py:65-68). It cannot detect judge error. MEASURED: running it prints "ALL VERIFIED" for 15 files.

### 2.2 Measured recomputation (python over results/*.json)
- **TM Pro runs** 92.79 / 93.05 / 93.05. **Base** 91.8 / 92.1 / 92.2. **Edge** 89.9 / 89.5 / 89.5.
- **Baselines** (single run): BM25 80.5, Engram 84.5, EverMemOS 94.5, Mem0 61.4, RAG 86.2, Supermemory 65.4.
- **Split judge votes are rare** (7-44 per 1540). The 3-vote majority is nearly deterministic at temperature 0, so it behaves like n=1, as the commenter on #716 noted.

### 2.3 Measured judge-leniency evidence (my own analysis)
- **Truncation.** Answers not ending in sentence punctuation (python regex `[.!?)"*]\s*$`) number 335-790 per system. TM Pro: 653-672 of 1540, about 43%.
- **Credit from "uncommitted" answers** (truncated and never contain "final answer"). Share of all judged-correct answers:

  | System | Share of credit |
  |---|---|
  | BM25 | 40.0% |
  | RAG | 39.7% |
  | Edge | 31.4% |
  | TM Pro | 30.9% |
  | Base | 30.1% |
  | Engram | 29.2% |
  | Supermemory | 25.4% |
  | Mem0 | 21.5% |
  | EverMemOS | 11.5% |

- **Manual strict audit.** 40 random TM Pro run2 judged-CORRECT items, `random.seed(42)`, output saved in the tool-results file, items #0-#39.
  - Plainly wrong: 4.
    - #3: lists Chicago / Italy / Barcelona; gold is Seattle, Chicago, NY, Paris.
    - #8: "traveling to Tokyo and Boston"; gold is "exploring and growing his brand".
    - #15: "wholesaler"; gold is "perfect spot for her store".
    - #19: grilled chicken; gold is salmon.
  - No committed answer (truncated before concluding): 4 (#5, #20, #29, #37).
  - Partial or lenient-acceptable: about 5 (#18, #22, #23, #28, #9).
  - **ESTIMATED false-positive rate: 10% (plainly wrong) to 20% (wrong or uncommitted).** 95% Wilson interval for 4/40 is about 4-23%. Implied strict accuracy for TM Pro is roughly 75-84%, not 93%. The method is one rater on n=40, so treat it as order-of-magnitude.
  - Low-token-overlap examples judged correct: "Would John be open to moving to another country?" (gold No) answered "Not enough information" and was marked CORRECT. "How many hikes?" (gold Four) answered "at least three" and was marked CORRECT.

### 2.4 LongMemEval (benchmarks/longmemeval/)
- `bench_truememory_pro.py` and `bench_truememory_pro_s.py` differ only in app name, GPU (A100 vs A10G), system name and dataset path (MEASURED with `diff`).
- **Judge:** the same "Be generous" prompt plus lines on preferences and knowledge updates (bench_truememory_pro_s.py:83-94). This is **not** LongMemEval's official type-specific gpt-4o judge. Numbers are not comparable to the public LME leaderboard.
- **Abstention** is a keyword match anywhere in the hypothesis, including chain-of-thought (:127-133). Refusal phrases include "not mentioned" and "don't have". A reasoning line such as "X is not mentioned, but…" followed by a confident answer still passes. The answer prompt dictates a refusal phrase that contains "don't have" (:68).
- "Strict" is a misnomer: `_s` is LongMemEval **S**mall (~115K tokens). The README calls it "Strict (harder)".
- **Result files** (MEASURED): all five baseline JSONs are the **oracle** variant.
  - bm25 90.0, rag 91.8, engram 86.0, mem0 64.0, supermemory 15.8.
  - supermemory_run1.json's `benchmark` field reads "LongMemEval_oracle"; the others carry no variant field but their j_scores equal the README oracle row.
  - The `_s` baseline numbers in README and paper (RAG 87.0, BM25 81.6, Engram 82.2, Mem0 66.0) have **no backing files**.
  - Supermemory's 15.8% appears in both tables from a single oracle file.
  - Supermemory LME: 114/500 questions retrieved 0 items, and 166 answers are the canned "I don't have that information…" (MEASURED). That is an integration failure, not a memory result.
- **TM S runs** 86.6 / 88.6 / 88.2 against RAG 87.0: inside TM's own run-to-run spread.
- On the oracle variant, TM 92.0 vs RAG 91.8 vs BM25 90.0. The oracle haystack contains only evidence sessions, so retrieval is nearly trivial.
- README.md:18 badge "LongMemEval 92.0%" is the oracle score. Maintainer issue #282 flagged this and it was closed "cosmetic". The README table row "TrueMemory Base LME 84.1%" (README.md:55) has no result file (MEASURED: longmemeval/results holds only pro files plus baselines).

### 2.5 BEAM (benchmarks/beam/)
- **Official BEAM scoring** (MEASURED from mohammadtavakoli78/BEAM `src/evaluation/run_evaluation.py`, `compute_metrics.py`):
  - A per-ability evaluator iterates **rubric items**, each judged by an LLM with `unified_llm_judge_base_prompt` (compute_metrics.py:339-348).
  - Event ordering uses Kendall tau-b normalised × F1 (compute_metrics.py:270-308).
- **TM's scoring:**
  - A binary CORRECT/WRONG judge against `ideal_response`, "Be generous with phrasing differences" (beam1m.py:76-86, :104-118).
  - The rubric is parsed into the question dict (:136) but the judge call uses only `q["ideal"]` (:213).
  - Event ordering scored binary gives 19.5%, which is not comparable to tau-based scores.
- **Hindsight 73.9%** is from Vectorize's own "Agent Memory Benchmark" with a different answer model. Its method is not disclosed on the pages I fetched. The same source gives Hindsight 64.1% at 10M; TM's 10M is a single run of 65.0% on 20 questions per category.
- `truememory_pro_beam10m_run1.json` has `"benchmark": "BEAM-1M"` in its metadata although it is the 10M run (MEASURED; a copy-paste slip).
- **Issue #716 (external, OPEN, no maintainer reply).** Same 60 answers, same prompt: gpt-4o-mini gives 46/60 (76.7%), gpt-5.5 gives 31/60 (51.7%). contradiction_resolution 6/6 → 0/6, abstention 5/6 → 1/6, summarization 6/6 → 3/6. Fact-lookup abilities were unchanged (CLAIMED by the reporter, with verdict reasoning quoted).

---

## 3. GitHub issues — what users and the maintainer report

MEASURED with `gh issue list --state all`: 393 issues. 383 were filed by the owner (`buildingjoshbetter`), mostly agent-run audits ("Hunter 5x", "BLAST OFF", "78 agents", "7-model review panel"). Only 10 come from 6 external accounts. Discussions are disabled. Stars 379, forks 49, latest release v0.7.6.2 (2026-06-11), last push 2026-09-02.

### 3.1 External-user complaints
- **#716 (OPEN):** judge too weak for BEAM (§2.5).
- **#722 (OPEN):** the SessionEnd hook never fires in Claude Desktop on Windows, so "auto-extraction silently does nothing for days". The reporter suggests Stop as a fallback.
- **#732 (OPEN):** a device override is ignored during tier rebuild, re-exposing an MPS OOM retry storm.
- **#598:** the model server uses AF_UNIX and crashes on Windows. Search always times out while status shows OK.
- **#385:** stdout pollution breaks the MCP JSON-RPC connection.
- **#316:** BLAS/OpenMP oversubscription under sub-agent fan-out. A single `m.add()` took **19 minutes**; fixed by pinning thread env vars to 1.
- **#328:** `|` in a query triggers accidental parallel fan-out, causing a 1 h 21 min hang with no request timeout.
- **#196:** MCP zombie processes leak about 450 MB each on Windows.
- **#194:** 10+ Windows bugs, "hooks silently never fire".
- **Recurring theme: silent failure** (hooks not firing, degraded search reported as OK), plus heavy per-process ML runtime cost under Claude Code's many-MCP-process model.

### 3.2 Maintainer-filed issues most relevant to us
- **#272 "CRITICAL: TrueMemory called less often — MEMORY.md cannibalizes MCP tool usage".** With Claude Code's auto-memory MEMORY.md (200+ lines) loaded at session start, "Claude has zero incentive to call truememory_search". Their fix was to migrate MEMORY.md into TrueMemory and slim it (#273), plus an "always search first" instruction.
  - For us this is **external evidence that the always-in-context index is what the model actually uses**. A pull-based search tool gets bypassed unless injected.
- **#288:** the auto-recall regex detects 17/50 (**34%**) of recall-shaped prompts at 89.5% precision. Keyword triggers miss implicit recall.
- **#277:** the user's MEMORY.md held plaintext passwords and health data, loaded every session. It was closed as "user hygiene", but the migration design had to add credential detection.
- **#576 (P0), #687 (P1): dedup silently drops real updates.**
  - The cosine > 0.92 fast path skips "I take 10mg of melatonin" → "5mg" (cos 0.9826), mortgage 6.5→5.9%, a deadline Oct 15 → 16 (0.991 on Qwen3).
  - In a 90-pair calibration, 20% of genuine updates scored above 0.92 while 11/30 true duplicates scored above the highest update: **no threshold separates them**.
  - Fix: a **marker-gated arbitration**. If digits, number-words, months or proper nouns differ, send the pair to LLM or heuristic arbitration instead of skipping. The marker regex flagged 6/6 eaten updates.
  - CLAIMED with a reproduction snippet in the issue.
- **#400:** the Stop hook marks a session "extracted" even when ingest was only queued or failed, so sessions are silently skipped. Fix: mark only on confirmed ingest.
- **#421:** the extractor interpolates the raw transcript into the LLM prompt, enabling prompt injection and **second-order memory poisoning** that persists across sessions. Fix: delimit the transcript and tell the model to treat it as untrusted data.
- **#455 / #456 / #451:** the benchmark path diverges from production (above).
- **#689:** recall is superlinear. p95 is 9.5 s at 10K memories and breaches the hook deadline, giving **silently empty recall**. Causes: OR-joined FTS over all tokens, plus a duplicate FTS fallback.
- **#685:** a single-memory forget leaves derived PII in summaries and entity profiles. Derived artefacts need cascade on delete.
- **#567 / #578:** directive (always-loaded) injection had no count or byte cap until they added a budget.
- **#556-#561:** the SessionStart hook blocked for 30 s or more; they moved work async.
- **#280:** CHANGELOG v0.6.0 contains unverifiable numbers ("Opus hallucinated numbers"), including the gate AUCs that the paper repeats.
- **#450:** the extractor covers only 7 fact categories and misses project state, decisions with rationale, and relationship changes. Deferred.

---

## 4. Independent reviews and comparisons

- **No independent technical review of TrueMemory found.** Searched the web, HN via the Algolia API, and dev.to.
  - HN story 48232071 ("I tried to preserve my grandmother's mind…", 2026-05-22) scored 3 points with 3 comments. The only praise comes from `huntehhh`, who is also the author of 4 repo issues and PRs. Their own log in #316 references their own company ("Hunter joined NoviusHealth as CTO"). They are not demonstrably independent.
  - dev.to "Whitepaper Thunderdome: HAGE vs Storage Is Not Memory" is by VEKTOR Memory, a competitor. It praises the paper and offers no methodological critique.
  - DeepWiki, awesome-lists and paperswithcode entries are auto-generated.
- **Context on the benchmark ecosystem (CLAIMED by the cited sources):**
  - LoCoMo audit (Penfield Labs / dial481): 6.4% wrong gold answers; the gpt-4o-mini judge accepts 62.81% of vague-but-topical wrong answers and 10.61% of specific-but-wrong ones; full context with CoT on gpt-4.1-mini gets 92.62%.
  - Letta "Is a filesystem all you need?" (2025-08): a Letta agent storing the conversation history in files and searching them with plain filesystem tools scored **74.0% on LoCoMo with gpt-4o-mini**, beating specialised memory libraries. Their conclusion: memory is about context management and agentic search, not the retrieval mechanism.
  - Zep vs Mem0 dispute: Zep claimed 84%, Mem0 said 58.44%, Zep re-reported 75.14%.
  - LongMemEval_S under the official gpt-4o judge: Zep 71.2 (gpt-4o), Mastra OM 84.23 (gpt-4o) and 94.87 (gpt-5-mini), OMEGA 95.4 (GPT-4.1), Mem0 claims 93.4.

---

## 5. What the leading alternatives do that TrueMemory does not (and that matters for a file-based Claude Code memory)

All alternatives below use permissive licences (MEASURED via `gh repo view`): claude-mem Apache-2.0 (94.8K stars), Letta Apache-2.0, Graphiti Apache-2.0, Mem0 Apache-2.0, MemOS Apache-2.0, A-Mem MIT, Supermemory MIT, Hindsight MIT, Mastra "other" (Mastra's own licence). TrueMemory is AGPL-3.0-only.

| System | Mechanism TrueMemory lacks or does weakly | Relevance to our file store |
|---|---|---|
| **Graphiti / Zep** | Bi-temporal facts. `valid_at`/`invalid_at` (world time) plus `created_at`/`expired_at` (system time). A contradicting fact **closes** the old one's validity window rather than deleting it. Caveat, Graphiti #1728: unscoped invalidation let unrelated facts retire each other. | Add `valid_from` / `superseded_by` / `expired` frontmatter to topic files. Never delete, mark superseded. Scope any automatic supersede proposal to the same `name`/topic only. |
| **Letta** | Always-in-context **memory blocks** with character limits, edited by the agent. A **sleep-time agent** asynchronously rewrites and consolidates the blocks (`rethink_memory`). Filesystem agent scored 74% on LoCoMo. | Our MEMORY.md is a memory block with a hard cap. The sleep-time pattern equals an offline `/compact-memory` proposer. Per our plan (R2) it must stay **propose-only / human-gated** because the store is unbacked. |
| **Mem0** | Explicit LLM arbitration of every new fact against top-k similar existing memories: **ADD / UPDATE / DELETE / NOOP**. | Our anti-duplicate rule is prose. A write-time "nearest existing topic files" lookup with an ADD/UPDATE/NOOP decision makes it mechanical, and TM #576 says to gate it on differing numbers, dates and names. |
| **A-Mem** | Zettelkasten notes with LLM-generated keywords, tags and links. A new note triggers **memory evolution**, updating linked older notes. | Topic-file `related:` links, plus a check that a new fact updates the linked file rather than adding a sibling. |
| **Mastra Observational Memory** | No retrieval. An Observer converts history into a dated, emoji-prioritised (🔴🟡🟢) observation log at a token threshold. A Reflector condenses it at a second threshold. A stable prefix gives high prompt-cache hit rates. | Closest to our design: an index loaded every session. It argues for token-threshold-triggered reflection, per-line priority markers in MEMORY.md, and keeping the loaded prefix stable for caching. |
| **claude-mem** | Hooks SessionStart / UserPromptSubmit / PostToolUse / Stop / SessionEnd capture **tool-use observations**, AI-compressed and typed (bugfix, decision, security_alert…). SQLite FTS5 plus Chroma. **Progressive disclosure**: search index (~50-100 tokens per result), then timeline, then full observation (~500-1000 tokens). A `<private>` tag excludes content. | Our MEMORY.md-index-plus-topic-files already is progressive disclosure. Borrow the **per-entry cost hint** and the `<private>` exclusion convention. |
| **Hindsight** | Separates world facts, experiences and **opinions/beliefs with confidence** that get revised. A "reflect" pass synthesises observations. | A `confidence:` or `verified:` frontmatter field fits our "unverified negative tool-claims" ban: store with status rather than as fact. |
| **MemOS** | MemCube: memory units with provenance, versioning and lifecycle governance. | Provenance (`source: session-id / commit`) on topic files. |
| **Claude Code native / Anthropic memory tool** | File directory the model reads and edits (view/create/str_replace), just-in-time loading. | That is our substrate. TM #272 shows it wins over an MCP side-store in practice. |

What TrueMemory has that the others mostly lack (ESTIMATED from paper plus issues):
- a cheap **non-LLM novelty signal** (gzip compression gain);
- a **speech-act salience** table (commitment 0.8, correction 0.6, question 0.2, noise 0.02) with per-category threshold offsets (corrections and decisions admitted more easily);
- hybrid BM25 plus dense retrieval with RRF, and a cross-encoder rerank;
- verbatim retention so later scoring functions can be applied retroactively.

The first two are the transferable ideas. The retrieval stack matters little at our scale: a small store, with the index loaded whole.

---

## 6. AGPL-3.0 implications for us

**Facts (MEASURED):**
- LICENSE is the verbatim AGPL-3.0 text (661 lines). pyproject declares `AGPL-3.0-only` (pyproject.toml:10).
- README.md:307 and CONTRIBUTING.md:289 add "Free for personal and research use. Commercial use requires a separate license from Sauron Labs."
- CONTRIBUTING.md:295-301 is a CLA granting Sauron Labs the right to relicense contributions as proprietary, so the project is dual-licensed.

**Our repo (MEASURED):**
- `origin` = renchris/claude-infrastructure-private, PRIVATE, no licence.
- A PUBLIC renchris/claude-infrastructure also exists, with no licence. The repo describes itself as "this PUBLIC repo" (.gitignore:79). README.md:666 gives the public clone URL. docs/activation/pending-activation/46-public-repo-cutover.sh projects this repo to the public one.

**Implications (ESTIMATED; not legal advice):**
1. **Copying TM source into this repo is a bad idea.**
   - Private use alone triggers no AGPL duty. AGPL obligations attach on *conveying* (distribution) and, via §13, on offering a *modified* version to remote users over a network.
   - But this repo is projected to a public GitHub repo. Publishing copied or derived TM code is conveying. The derived files, and arguably the combined work they link into, must then be offered under AGPL-3.0 with source, and our unlicensed public repo would hold AGPL code.
   - It also creates a dispute surface with the "commercial use requires a licence" statement. Note that under AGPL §7 a "further restriction" added to AGPL terms can be removed by the recipient, but the stated intent and the CLA make the owner's posture clear.
2. **Reimplementing ideas is fine.** Algorithms, thresholds, the gzip-novelty formula, marker-gated dedup and speech-act categories are ideas and facts described in a public paper and issues, not copyrightable expression. Write fresh code from the *paper and issue text*, without transcribing TM source files. Keep a note citing the paper as inspiration.
3. **Running TM unmodified as a separate local tool** (pip install, MCP) creates no copyleft obligation for our repo, because it is a separate program communicating over stdio or MCP. We have ruled out installing it anyway (it edits agent configs).
4. **Prefer permissive sources for any actual code borrowing:** Mem0, Graphiti, Letta, claude-mem (Apache-2.0); A-Mem, Hindsight, Supermemory (MIT).

---

## 7. Transfer ideas (first pass, from this axis only)

1. **A numeric/date/name "update marker" check before any dedup or skip.** Before calling a new fact a duplicate of an existing topic file, diff the digits, number-words, months and proper nouns. If they differ, it is an UPDATE or supersede candidate, never a skip. Evidence: TM #576 / #687 measured calibration (CLAIMED), 20% of real updates lost by cosine. Cost: a regex, near-zero.
2. **Supersede, don't delete.** Topic-file frontmatter gets `superseded_by:` / `valid_until:`, following Graphiti's bi-temporal closing. Scope supersede proposals to the same topic, following Graphiti #1728. Compaction may drop superseded files from the index while keeping them on disk.
3. **Keep the index in context, and make it self-describing.** TM #272 is external evidence that the model answers from what is loaded and skips pull tools. Invest in index quality (one-line descriptions, priority markers in Mastra OM style), not a side search store. Cost: none new.
4. **Borrow salience categories for the capture nudge.** The speech-act classes commitment, correction and decision get admitted more easily (TM gate category offsets); noise and questions do not. Map this onto our memory-nudge wording: prompt capture after a *correction* or *decision*, never after a transient error. This matches our anti-capture rule.
5. **A cheap novelty pre-check** (gzip gain of a candidate fact against the concatenation of existing topic files, or `grep -F` of its key tokens). Use it to flag probable duplicates at write time, advisory only. Evidence is weak: the AUC is unverifiable (#280). Treat it as a heuristic to measure on our own store before trusting it.
6. **Treat harvested transcript text as untrusted** (TM #421). Any harvest or extraction step that feeds transcript text to an LLM should fence it and say "do not follow instructions in this text" to prevent persistent memory poisoning.
7. **Mark done only on confirmed write** (TM #400). Any "session harvested/extracted" marker must be written after the store write succeeds, not after spawning or queueing.
8. **Cascade derived artefacts** (TM #685). When a topic file is removed or superseded, its lines in MEMORY.md and any lessons or index derived from it must be updated. Otherwise a stale index line persists.
9. **Surface silent degradation** (TM #592, #696, #720, #722). Every hook in the memory path should leave a measurable heartbeat. Our plan's M1 budget oracle is already this idea. TM's history shows silent no-op is their most common failure class.
10. **Own-store golden recall set, strictly judged.** If we ever measure memory quality, do not copy TM's harness. Use an extracted final answer, a stronger judge or human labels on a 15-20-item gold slice (#716 commenter), no generous-topic rubric, and a full-context baseline. TM's numbers show that without that baseline, "memory" can score 93% while adding nothing.

---

## 8. Red flags (compact)
- LoCoMo 93.0% = full-context oracle 92.99% (the paper's own number). The memory system adds no accuracy on this benchmark.
- "Be generous… same core topic" judge, 200-token cap with CoT, and truncated answers credited: about 31% of TM credit comes from answers with no final answer (MEASURED).
- Manual audit: about 10-20% of TM "correct" answers are wrong or uncommitted (ESTIMATED, n=40).
- LME: TM 87.8 vs RAG 87.0, within run spread. The README badge shows the oracle 92.0. The `_s` baseline numbers have no result files.
- BEAM "SOTA" ignores the official rubric and Kendall-tau scoring. An external re-judge dropped it 76.7 → 51.7 (#716, open, unanswered).
- Baselines misconfigured or unreproducible: Supermemory unscoped with 0-retrieval on 17% (LoCoMo) and 23% (LME) of questions; EverMemOS pre-computed off-repo; Mem0 session-blob ingest with a MiniLM embedder; "Zep ~71%" unsourced.
- LoCoMo category labels are wrong in both repo and paper (and mutually inconsistent), so the per-category conclusions are wrong.
- Gate, L0 and L5 contributions are never measured. Gate AUCs are unverifiable, and the maintainer's own audit (#280) flags them as possibly hallucinated.
- The benchmark path (`ingest()`, 14 steps, top_k 100) differs from the product path (`add()`, 4 steps, top_k 10) (#455/#456/#451).
- 383/393 issues are owner-filed, agent-generated audits. There is very little external usage signal (10 external issues, one HN comment thread from an affiliated tester).
- AGPL-3.0-only, plus a "commercial use requires licence" statement and a relicensing CLA. Our repo is projected public, so do not copy code.

## Sources
- arXiv abstract: https://arxiv.org/abs/2605.04897 ; PDF https://arxiv.org/pdf/2605.04897v1 (local /tmp/tm-research/scratch/paper.txt)
- Repo and issues: https://github.com/buildingjoshbetter/TrueMemory (issues #716 #722 #732 #598 #385 #316 #328 #196 #194 #272 #273 #277 #280 #282 #288 #400 #421 #450 #451 #455 #456 #576 #685 #687 #689)
- LoCoMo audit: https://github.com/dial481/locomo-audit ; https://penfieldlabs.substack.com/p/we-audited-locomo-64-of-the-answer
- LoCoMo category mapping note: https://github.com/Snseam/awesome-agent-memory/blob/main/papers/mem0-paper.md ; https://memorilabs.ai/docs/memori-cloud/benchmark/results/
- BEAM official eval: https://github.com/mohammadtavakoli78/BEAM (src/evaluation/compute_metrics.py, run_evaluation.py)
- Hindsight BEAM: https://hindsight.vectorize.io/blog/2026/04/02/beam-sota
- Letta filesystem: https://www.letta.com/blog/benchmarking-ai-agent-memory/ ; sleep-time https://docs.letta.com/guides/agents/architectures/sleeptime/ ; memory blocks https://www.letta.com/blog/memory-blocks/
- Graphiti temporal model: https://blog.getzep.com/beyond-static-knowledge-graphs/ ; issue https://github.com/getzep/graphiti/issues/1728
- Zep/Mem0 dispute: https://blog.getzep.com/lies-damn-lies-statistics-is-mem0-really-sota-in-agent-memory/ ; https://github.com/getzep/zep-papers/issues/5
- Mastra OM: https://mastra.ai/research/observational-memory
- claude-mem: https://github.com/thedotmack/claude-mem
- Benchmark overview: https://memnode.dev/articles/agent-memory-benchmarks-2026-real-numbers
- HN thread: https://news.ycombinator.com/item?id=48232071
- Competitor review: https://dev.to/vektor_memory_43f51a32376/the-whitepaper-thunderdome-hage-vs-storage-is-not-memory-5epd
