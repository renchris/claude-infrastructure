# R10: Independent evidence and normalized pricing across the video-understanding field (2026-10-24)

Axis: which evidence about video-understanding products and models is **independent** (run by someone other than the vendor), what the current leaderboards actually say, what developers report from real use, and what one hour of video costs on each route. The agent in question is Claude Opus 5.5 in Claude Code, which has no video or audio input.

**Labels.** MEASURED means I ran the named command today, and it covers retrieval facts only: a sort, a grep, a price-API query or a star count. DOCUMENTED means a page says it; the URL is given. INFERRED means my reasoning. ESTIMATED means my arithmetic, and the method is stated each time. A row is **vendor-run** if the vendor of the product produced it, **competitor-run** if a rival vendor produced it, **owner-run** if the benchmark's authors ran the models themselves, and **independent** if an academic or third party with no product at stake ran it.

**Scope and method.** I used WebSearch, WebFetch, curl with a desktop user agent, the HN Algolia API, the GitHub API (`gh api`), the Azure Retail Prices API and the AWS Price List bulk CSV. I made no accounts, uploaded nothing and installed nothing. Scratch copies are in `/tmp/r10dl/` and scripts in `/tmp/r10scripts/`; neither survives a reboot, so the URL is the citation of record.

**What this extends.** F2 (`docs/research/video-understanding-human-parity-2026-10-23/agents/F2-sota-vs-human-benchmarks.md`) built a human-vs-model gap map. F3 and `~/.claude/research-artifacts/meeting-video-2026-10-06/video-api-alternatives.md` priced routes as of 2026-10-06. This file adds three things: who produced each leaderboard row, the newest independent evaluations (Aug to Oct 2026, two of which cover Claude), and a re-verified price table. I did not repeat F2's human baselines except where a row needs one.

---

## 0. Bottom line

1. **Almost no current leaderboard number is independent.** llm-stats marks **0 verified rows** on every video board I checked: Video-MME 17 self-reported, LVBench 31, MLVU 10, MVBench 18, LongVideoBench 6, TempCompass 4 and VideoMMMU 28. benchlm says "0 of N rows come from the benchmark owner or an independent run" for Video-MME (3 rows), LVBench (6) and VideoMMMU (12). Both pages were fetched 2026-10-24 (DOCUMENTED). The official boards that do run models themselves (Video-MME v1, LVBench, LongVideoBench, TempCompass, Video-Holmes v1) stopped adding entries between 2024 and 2025. All of them are **stale by more than 6 months** (MEASURED via `gh api repos/<repo>/commits`, §1).
2. **Four 2026 owner-run or independent evaluations carry the real signal.**
   - Video-MME-v2 (Apr 2026, owner-run, 60 rows): the best model is Gemini-3-Pro at 49.4 against a human score of 90.7.
   - VideoGAIA (12 Aug 2026, independent, agentic, frames only): the best model is Seed2.0-Pro at 58.3. **Claude Opus 4.7 and 4.8 rank last of 20, at 34.7 and 36.9.**
   - Video-HolmesV2 (Sep 2026): Gemini-2.5-Pro scores 73.2 on multiple choice but only 35.2 on evidence.
   - Video-Oasis (ECCV 2026): "55% of existing benchmark samples are solvable without visual input or temporal context".
   All are DOCUMENTED; URLs are in §1 and §2.
3. **Claude Opus 5.5 has exactly one video number, and a competitor produced it.** Google's Gemini 4 Argon evaluation table gives LVBench scores of Argon 91.7, GPT-6 Astra 87.5, **Claude Opus 5.5 83.7** and Claude Fable 5.1 79.7. Google marks the row "self-computed for all models". Gemini ran at 1 fps, while Opus 5.5 received **600 frames** "due to API limitations", which is the Claude API's per-request image cap (DOCUMENTED, secondary reproductions of Google's table, §1.3). No Anthropic table and no independent run exists for Opus 5.5 on video (DOCUMENTED absence: benchlm's Opus 5.5 page lists no video benchmark).
4. **No independent head-to-head of commercial video APIs exists.** The only cross-vendor comparisons are vendor-run or competitor-run:
   - VideoDB vs AWS Nova vs Twelve Labs Marengo 3.5 on action retrieval (VideoDB-run, 6 Oct 2026);
   - Twelve Labs' Pegasus 1.5 vs Gemini 3.1 Pro (Twelve Labs-run, Apr 2026);
   - Twelve Labs' Video-to-Text Arena (vendor-hosted, about 2025);
   - Memories.ai's "vs" pages, which have since been removed (404 today).
   Sources are in §2 (DOCUMENTED). This confirms the October finding (`video-api-alternatives.md:10`) with three more months of evidence.
5. **Normalized prices are unchanged since October except Gemini 4 Argon.** Argon is $0.72 per hour now and $1.44 from 2026-12-01, and per HackerNoon it is not yet generally callable. Gemini 3.5 Flash-Lite is still the floor at about $0.11 per hour (low resolution). Dedicated services cost $1.75 to $11.40 per hour. Claude's own frame route costs about $0.08 to $2.66 per hour of Opus 5.5 input, depending on frame count (ESTIMATED, §4).
6. **Community reports converge on four failure modes:** wrong timestamps, silently dropped content, Whisper inventing speech in silent stretches, and frame extraction breaking on ffmpeg 9. They also converge on one fix: pin timing to a deterministic ASR pass and treat model timestamps as hints (DOCUMENTED, §3).

---

## 1. Leaderboards: top-10 entries, dates and who produced each row

Rows are copied from the named page on 2026-10-24 unless stated otherwise. "Self-rep." means the aggregator itself labels the row self-reported.

### 1.1 Video-MME (v1, 2024)

The official board (https://video-mme.github.io/home_page.html) runs submissions under a fixed protocol. Its newest entry is dated **2025-09-28**, so the board is stale. Sorted by overall with subtitles:

| # | Model | w/ subs | w/o subs | Date |
|---|---|---|---|---|
| 1 | video-SALMONN 2+ 72B | 81.6 | 79.7 | 2025-09-28 |
| 2 | Gemini 1.5 Pro | 81.3 | 75.0 | 2024-06-15 |
| 3 | AdaReTaKe 72B | 79.6 | 73.5 | 2025-03-04 |
| 4 | JT-VL-Chat 38B | 79.1 | 70.6 | 2025-07-24 |
| 5 | Qwen2-VL 72B | 77.8 | 71.2 | 2024-08-19 |
| 6 | GPT-4o | 77.2 | 71.9 | 2024-06-15 |
| 7 | LLaVA-Video 72B | 76.9 | 70.6 | 2024-08-28 |
| 8 | Gemini 1.5 Flash | 75.0 | 70.3 | 2024-06-15 |
| 9 | Oryx-1.5 34B | 74.9 | 67.3 | 2024-10-21 |
| 10 | InternVL2.5 72B | 74.0 | 72.1 | 2024-12-13 |

The aggregator view (https://llm-stats.com/benchmarks/video-mme, "Verified 0, Self-reported 17", updated 2026-10-24) has this top 10, with the subtitle setting unstated:

| # | Model | Score |
|---|---|---|
| 1 | Seed 2.1 Pro | 89.2 |
| 2 | Seed 2.1 Turbo | 89.0 |
| 3 | Qwen3.7-Plus | 88.0 |
| 4 | MiMo-V2.5 | 87.7 |
| 5 | Kimi K2.5 | 87.4 |
| 6 | MiniMax M3 | 85.4 |
| 7 | Gemini 2.5 Pro | 84.8 |
| 8 | Qwen3.6 Plus | 84.2 |
| 9 | Gemini 1.5 Pro | 78.6 |
| 10 | Nova 2 Omni | 77.9 |

benchlm (https://benchlm.ai/benchmarks/videomme) carries only 3 rows, flags the benchmark "not marked current", and says the "top three [are] within 1.8 points".

Reading (INFERRED): the board is saturated and self-reported. VideoGAIA's authors say the same: "leading models have already achieved approximately 90% accuracy on the Video-MME leaderboard" (arXiv 2608.14718 abstract).

### 1.2 Video-MME-v2 (Apr 2026): the one current owner-run board

The board is at https://video-mme-v2.netlify.app/#leaderboard. The data comes from the page's `leaderboardDataRaw` array. I parsed and sorted it with a python regex over `/tmp/r10dl/vmme2-site.html`, which yielded 60 rows (MEASURED). The metric is the grouped non-linear score, and the authors run submitted model responses themselves. Rows carry no per-row dates. The launch was 2026-04-07 and the latest repo news is 2026-08-05.

| # | Model (frames) | Non-Lin w/ sub | Non-Lin w/o sub | Avg acc w/ sub |
|---|---|---|---|---|
| — | Human expert | 90.7 | — | 94.9 |
| 1 | Gemini-3-Pro (1 fps) | 49.4 | 38.2 | 66.1 |
| 2 | Doubao-Seed-2.0-Pro-260215 (1 fps) | 43.3 | 35.2 | 60.5 |
| 3 | Gemini-3-Flash (1 fps) | 42.5 | 32.9 | 61.1 |
| 4 | Kimi-K2.5 (512) | 40.7 | 33.0 | 58.0 |
| 5 | Qwen3.5-397B-A17B-Think (512) | 39.1 | 30.3 | 55.9 |
| 6 | MiMo-v2-Omni (1 fps) | 38.6 | 29.9 | 56.1 |
| 7 | GPT-5 (50) | 37.0 | 26.4 | 55.6 |
| 8 | Kimi-K2.5 (64) | 36.1 | 27.3 | 54.4 |
| 9 | Qwen3.5-27B-Think (512) | 31.4 | 19.5 | 49.6 |
| 10 | Qwen3.5-397B-A17B-Think (64) | 30.6 | 20.7 | 48.9 |

No Claude, Gemini 3.5+/4, GPT-5.5+ or Twelve Labs row appears (MEASURED by the same parse). Frame count matters: Kimi-K2.5 goes from 36.1 at 64 frames to 40.7 at 512 (MEASURED from the same rows). The authors invite submissions by email, so the board is not self-serve.

### 1.3 LVBench (hour-long, 2024)

The official board (https://lvbench.github.io/) is owner-run. Its newest entry is **2025-05-29**, so it is stale; the repo's last commit is 2025-07-09 (MEASURED, `gh api repos/zai-org/LVBench/commits`). Top 10:

| # | Model | Score | Date |
|---|---|---|---|
| 1 | Deep Video Discovery (agent) | 74.2 | 2025-05-29 |
| 2 | Seed1.5-VL-Thinking | 64.6 | 2025-05-14 |
| 3 | AdaReTaKe | 53.3 | 2025-03-04 |
| 4 | GPT-4o-2024-11-20 | 48.9 | 2025-04-30 |
| 5 | GLM-4V-Plus-0111 | 48.7 | 2025-01-24 |
| 6 | InternVL2.5-78B | 43.6 | 2025-01-24 |
| 7 | mPLUG-Owl3 | 43.5 | 2024-11-23 |
| 8 | Qwen2-VL-72B | 41.3 | 2024-09-20 |
| 9 | TimeMarker | 41.3 | 2024-10-29 |
| 10 | InternVL2-40B | 39.6 | 2024-08-30 |

The human score is 94.4 (F2).

The aggregator view (https://llm-stats.com/benchmarks/lvbench, "Verified 0, Self-reported 31", updated 2026-10-24) has this top 10:

| # | Model | Score |
|---|---|---|
| 1 | Gemini 4 Argon | 91.7 |
| 2 | Gemini 3.8 Flash | 87.1 |
| 3 | Gemini 3.7 Flash | 85.4 |
| 4 | Qwen3.8 Max | 81.8 |
| 5 | Seed 2.1 Pro | 78.0 |
| 6 | Seed 2.1 Turbo | 76.8 |
| 7 (tie) | Qwen3.8-Flash-Next | 76.6 |
| 7 (tie) | Qwen3.8 Flash | 76.6 |
| 9 | Qwen3.7-Plus | 76.2 |
| 10 | Kimi K2.5 | 75.9 |

Context for those rows:
- DataLearner adds Gemini 3.8 Flash *with tools* at 87.8. It notes that Gemini 3.7 Flash's 85.4 came from Google's model card on 2026-08-13 "using 1,024 frames and no tools" (https://www.datalearner.com/benchmarks/lvbench, updated 2026-10-11).
- Google's Gemini 4 Argon table, labelled "self-computed for all models", gives Argon 91.7, GPT-6 Astra 87.5, **Claude Opus 5.5 83.7** and Claude Fable 5.1 79.7. The methodology note reads: "Gemini sampled video at 1 FPS; Astra got 800 frames, Fable 5.1 300 and Opus 5.5 600, 'due to API limitations'". Thinking was set to maximum on all models. These are DOCUMENTED but secondary, from reproductions of Google's evaluation page: https://apidog.com/blog/gemini-4-argon-benchmarks/, https://hackernoon.com/gemini-4-argon-how-does-it-do-against-gpt-6-astra-and-claude (6 Oct 2026) and https://www.cometapi.com/ja/models/google/gemini-4-argon/. I could not reach Google DeepMind's evaluation-methodology page itself.

Reading (INFERRED): this is the only Opus 5.5 video number anywhere. Two things limit it. A rival ran it, and Opus was capped at 600 frames while Gemini saw 1 fps (about 3,600 frames per hour). Even so, it puts Opus 5.5's frame route about 8 points under Argon and 3.4 under Gemini 3.8 Flash, which is far closer than the 57.3 that F2 cites for Claude 4.5 Opus.

### 1.4 MLVU (2024)

The README dev mini-board (https://github.com/JUNJIE99/MLVU) was last updated 2026-04-13, which is borderline for the 6-month cut (MEASURED, `gh api`). Rows are self-submitted. Top 10 by M-Avg:

| # | Model | M-Avg |
|---|---|---|
| 1 | LVAgent | 83.9 |
| 2 | TSPO-72B | 77.3 |
| 3 | TSPO-7B | 76.3 |
| 4 | VideoChat-Flash | 74.7 |
| 5 | VideoLLaMA3 | 73.0 |
| 6 | Oryx-1.5 | 72.3 |
| 7 | Aria | 70.6 |
| 8 | LinVT | 68.9 |
| 9 | LLaVA-OneVision-72B | 66.4 |
| 10 | Video-XL | 64.9 |

Aggregators:
- llm-stats (10 rows, all Qwen, 0 verified): Qwen3.7-Plus 87.4, Qwen3.5-122B 87.3, Qwen3.6 Plus 86.7 and so on.
- benchmarklist (https://benchmarklist.com/benchmarks/mlvu/, rows labelled "Self-reported", 2026-06-01): GPT-5.4 (xhigh) 86.1, Gemini 3.1 Pro 84.7, "Claude Opus 4.6 Max" 81.7.

That Claude value equals the Claude 4.5 Opus figure in Qwen's model card, so the label is probably wrong (INFERRED).

### 1.5 LongVideoBench (2024)

The official board (https://longvideobench.github.io/) has had no update since 2024; the repo's last commit is 2024-07-24 (MEASURED), so it is stale. Top 10:

| # | Model (max frames) | Score |
|---|---|---|
| 1 | GPT-4o-0513 (256) | 66.7 |
| 2 | Aria (256) | 65.0 |
| 3 | LLaVA-Video-72B (128) | 64.9 |
| 4 | Gemini-1.5-Pro (256) | 64.4 |
| 5 | LLaVA-OV-72B (32) | 63.2 |
| 6 | LLaVA-Video-7B (128) | 62.7 |
| 7 | Gemini-1.5-Flash (256) | 62.4 |
| 8 | GPT-4-Turbo (256) | 60.7 |
| 9 | InternVL2-40B (16) | 60.6 |
| 10 | mPLUG-Owl3-7B (128) | 60.1 |

llm-stats has 6 rows, 0 verified: Seed 2.1 Pro 80.6, Seed 2.1 Turbo 80.6, Kimi K2.5 79.8, Seed 1.8 77.4, Seed 2.0 Mini 74.8, Qwen2.5-VL-7B 54.7. The Deep Video Discovery agent scores 71.6 (F2).

### 1.6 VideoMMMU (2025)

No owner board has rows newer than the paper. Aggregators:
- llm-stats (28 rows, 0 verified), top 10: Gemini 3 Pro 87.6, Gemini 3 Flash 86.9, Kimi K2.5 86.6, GPT-5.2 85.9, Qwen3.7-Plus 85.4, Gemini 3.1 Flash-Lite 84.8, GPT-5 84.6, MiniMax M3 84.6, Qwen3.6-27B 84.4, Qwen3.6 Plus 84.0.
- benchlm (12 rows; "0 of 12 … independent", "9 provider self-reports, 3 secondary"): Qwen3.8 Max 88.7 at the top, and **Claude Opus 4.5 84.4 at rank 10**.

The human expert score is 74.44 (F2). This is the only board where models beat humans, and the questions are knowledge-heavy.

### 1.7 MVBench (2024)

There is no online board; the README shows a static image, and Ask-Anything's last commit is 2026-07-17 (about VideoChat3). Aggregators:
- llm-stats (18 rows, 0 verified), top 10: GLM-5.3-Flash 77.8, Qwen3.5-122B 76.6, Qwen3.6-27B 75.5, Qwen3.5-35B 74.8, Qwen3.6-35B 74.6, Qwen3.5-27B 74.6, Qwen2-VL-72B 73.6, Qwen3-VL-32B-Thinking 73.2, Qwen3-VL-32B 72.8, Qwen3-VL-30B 72.3.
- benchmarklist ("Self-reported", 2026-08-26): Gemini 3.7 Flash 82.2, GLM 5.3 Flash 77.8, GPT-5.6 Terra 75.0, DeepSeek V4 Flash Vision Exp 69.4, **Claude Opus 4.8 67.1**. That Claude row has no traceable source (DOCUMENTED; the provenance is unverified).

No human baseline exists (F2).

### 1.8 TempCompass (2024)

The official Hugging Face space (https://huggingface.co/spaces/lyx97/TempCompass) last announced results on 2024-08-30, when GPT-4o was the leader. The repo's last commit is 2025-04-04, so the board is stale (MEASURED). llm-stats has 4 rows, 0 verified: Seed 1.8 86.9, Seed 2.0 Mini 83.7, Qwen2.5-VL-72B 74.8, Qwen2.5-VL-7B 71.7. Human: 97.3 (MEASURED retrieval in F2; also on https://benchmarklist.com/benchmarks/tempcompass/). **No frontier closed model from 2026 has a TempCompass number anywhere** (DOCUMENTED absence across llm-stats, benchlm and benchmarklist).

### 1.9 VSI-Bench (Dec 2024)

There is no maintained leaderboard. The repo's last commit is 2025-08-05, llm-stats returns 404 and benchlm returns 404 (MEASURED). The best-known entries, all self-reported in papers unless marked:

| Model | Score | Source |
|---|---|---|
| SSR-7B (3D) | 73.9 | arXiv 2603.00409, Mar 2026 |
| InternVL3.5-241B | about 69.5 | implied by SSR's "+4.4 over previous SOTA" |
| SenseNova-SI | 68.8 | — |
| Cambrian-S-7B | 67.5 | — |
| Ouroboros-Spatial-8B | 63.3 | arXiv 2606.11719 |
| GPT-5 | 55.0 | third-party, arXiv 2508.13142 |
| Gemini-2.5-Pro | 51.5 | — |
| Human | 79.2 | — |

No Gemini 3+, Claude or GPT-5.5+ score exists. ICML 2026's FN-VSI paper shows that raw VSI-Bench scores are driven by "ground-truth answer value and queried object type", and its factor normalisation "substantially re-ranks" models (https://icml.cc/virtual/2026/68265, DOCUMENTED).

### 1.10 Video-Holmes (2025) and Video-HolmesV2 (Sep 2026)

The v1 official board (https://video-holmes.github.io/Page.github.io/) is owner-run; the repo's last commit is 2025-07-13, so it is stale. Top 10:

| # | Model | Score |
|---|---|---|
| 1 | Gemini-2.5-Pro (audio) | 51.3 |
| 2 | Gemini-2.0-Flash-Thinking (audio) | 49.5 |
| 3 | Gemini-1.5-Pro (audio) | 45.7 |
| 4 | Gemini-2.5-Pro | 45.0 |
| 5 | Gemini-2.0-Flash-Thinking | 43.1 |
| 6 | GPT-4o | 42.0 |
| 7 | Gemini-1.5-Pro | 41.2 |
| 8 | Claude 3.5 Sonnet | 41.0 |
| 9 | Video-RTS | 40.0 |
| 10 | Claude 3.7 Sonnet | 39.3 |

Adding audio moves Gemini 2.5 Pro from 45.0 to 51.3, a lever Claude does not have (INFERRED).

**Video-HolmesV2** (arXiv 2609.17248, Sep 2026, owner-run; I parsed its tables with `/tmp/r10scripts/tables.py`) tested only older closed models:

| Model | MCQ | Evidence score | Overall |
|---|---|---|---|
| Gemini-2.5-Pro | 73.2 | 35.2 | 54.2 |
| Gemini-2.5-Flash | 65.3 | 28.6 | 46.6 |
| Qwen3-VL-235B | 55.3 | 8.5 | 34.9 |
| GPT-4o | 46.9 | n/a | n/a |

The paper's section title is "The Illusion of Accuracy: Why Evidence Matters". On the hardest split, ultra-long 60-150 minute video, Gemini-2.5-Pro drops to about 66 (MEASURED by table parse; DOCUMENTED values).

---

## 2. Third-party and cross-vendor head-to-heads

| Evaluation (date) | Who ran it | Systems compared | Result | Independence |
|---|---|---|---|---|
| **VideoGAIA** (arXiv 2608.14718, 12 Aug 2026; CUHK, Ant, Tsinghua, HKUST) | Academic authors; 271 tasks, each checked by 3 experts | 20 frontier models in one agent loop. Each gets "20 coarse frames sampled uniformly", plus a "thinking with videos" tool that "samples up to 20 additional frames from a model-selected temporal segment", plus web tools. No native video or audio | Seed2.0-Pro 58.30; Qwen3.7-Plus 56.09; Kimi-K3 54.61; GPT-5.5 53.14; Kimi-K2.6 52.77; GPT-5.4 52.03; Qwen3.5-Plus 52.03; Gemini-3.1-Pro 50.92; GPT-5.2 50.92; Qwen3.5-397B, Qwen3.8-Max and GLM-5V-Turbo 50.18; Kimi-K2.5 49.82; Qwen3.6-Plus 49.08; MiMo-V2.5 48.71; **Claude-Opus-4.6 47.97**; GLM-4.6V 46.86; Gemini-3.5-Flash 43.91; **Claude-Opus-4.8 36.90**; **Claude-Opus-4.7 34.69** | **Independent.** The scores come from the paper's main table; I parsed them with `/tmp/r10scripts/tables.py` (MEASURED retrieval, DOCUMENTED values). The 95% interval is about ±6 points (ESTIMATED: 1.96·√(0.25/271)). |
| **Video-MME-v2** (Apr 2026, 60 rows) | Benchmark owners | Gemini-3-Pro/Flash, GPT-5, Doubao-Seed-2.0-Pro, Kimi, Qwen, InternVL and others | §1.2 | Owner-run, with responses submitted by email |
| **Google's Gemini 4 Argon table** (13 Oct 2026) | Google | Argon, GPT-6 Astra, Claude Fable 5.1, Claude Opus 5.5 on LVBench | 91.7 / 87.5 / 79.7 / 83.7; frames were unequal (1 fps vs 800 / 300 / 600) | **Competitor-run** for the three non-Google models |
| **VideoDB action retrieval** (https://videodb.io/blog/a-faster-path-to-the-next-policy, 6 Oct 2026) | VideoDB | VideoDB Action Segmentation + Search; AWS Nova 2 Multimodal Embeddings; Twelve Labs Marengo 3.5; SigLIP2; Qwen3-VL Embedding; Cosmos-Embed; InternVideo2; PE-AV. Benchmark: 2,835 egocentric videos, 100 h, 11,369 queries (Lightwheel EgoStandard) | Hit@10: VideoDB 40.39, Nova 35.40, Marengo 3.5 32.87, SigLIP2 24.96. At tIoU ≥ 0.5: VideoDB 20.49, Nova 10.01, Marengo 9.61 | **Vendor-run.** A results download is offered. It is the only public number on Marengo 3.5 not produced by Twelve Labs |
| **Twelve Labs: Pegasus 1.5 vs Gemini 3.1 Pro** (blog dated about 19 Apr 2026, https://www.twelvelabs.io/blog/introducing-pegasus-1-5) | Twelve Labs, on its own dataset and metrics | Pegasus 1.5 vs Gemini 3.1 Pro | The blog says Pegasus "outperformed Gemini 3.1 Pro" on "segmentation quality and multimodal prompting quality". The homepage says "+13.1% … Multimodal Prompting" with no metric definition (WebFetch of https://www.twelvelabs.io/, 2026-10-24) | **Vendor-run**, not reproducible |
| **Twelve Labs Video-to-Text Arena** (https://www.twelvelabs.io/blog/video-to-text-arena, about 2025) | Twelve Labs | Pegasus 1.2 vs Gemini 2.0 Flash / 2.5 Pro, GPT-4o, Nova | Qualitative, hand-picked examples | **Vendor-run**; older than 6 months |
| **Gemini agentic video** (blog 2026-09-01) | Google, plus one partner | Agentic vs static mode on Gemini 3.7/3.6 Flash and 3.5 Flash-Lite | "Up to 88% fewer tokens, up to 66% lower cost, up to 7% higher accuracy". The 88% comes from one long-video benchmark (397.6K → 47.7K tokens per query, accuracy 87.5 → 88.5). Partner Ponder: about 3.5× fewer input tokens | **Vendor-run.** The Ponder figure is the only third-party number (DOCUMENTED via https://blog.google/innovation-and-ai/models-and-research/gemini-models/introducing-agentic-video-in-gemini/ and summaries of it) |
| **Memories.ai "vs Gemini / vs Twelve Labs" pages** | Memories.ai | Memories.ai vs Gemini and Twelve Labs | They claimed big margins, with "comparative data … sourced from Google's model release blogs" (search summary). https://memories.ai/vs and https://memories.ai/vs/gemini return **404** today (MEASURED, curl/WebFetch) | **Vendor-run**, now withdrawn |
| **Pixeltable and Mixpeek "best video intelligence APIs 2026" lists** | Vendors selling a pipeline layer | Many | Fit-based lists, not test results. Mixpeek says "last tested: February 1, 2026" | Vendor-written; older than 6 months |

What is missing (DOCUMENTED absence, from searches on 2026-10-24): no independent test of any of these, on any public benchmark or on real customer video:
- Twelve Labs Pegasus 1.5/1.6, Jockey, Marengo
- Cloudglue/Tinycloud, Memories.ai, VideoDB's QA side, Reka Vision, Mixpeek
- Bedrock Data Automation, Azure Video Indexer / Content Understanding
- Gemini agentic mode

The academic boards evaluate base models, not these services. The VLMEvalKit authors give the reason: "due to the limited resources of commercial APIs and the significant costs … we focused on testing … open-source LMMs" (arXiv 2407.11691).

---

## 3. Developer-community reports of real-world reliability

All entries are DOCUMENTED, with dates from the HN Algolia API (`curl hn.algolia.com/api/v1/items/<id>`) or the GitHub API. They are anecdotes, not measurements.

- **Gemini timestamps are not trustworthy on long media.** simonw tested Gemini 3 Pro on a meeting: it captured the gist, "but the fact that the transcript isn't close to an exact match … and the timestamps are incorrect - means it's very hard to trust" (HN item 45970519, 2025-11-18; more than 6 months old). Another commenter guessed Gemini "has no insight into the time stamps … ballparking it" (45971339).
- **The fix teams settled on is Whisper for timing and an LLM for text.** One team: "we've moved back to Whisper for timestamp accuracy and then Gemini Flash for transcription correction" (49471385, 2026-08-27). A second runs Whisper first for word timestamps, then Gemini Pro without timestamps, and aligns the two by runs of matching words (49474789, 2026-08-28). A third reports that Gemini 3.5 Transcribe produced no hallucinations on silence or noise in their evaluation, but "exactly 20 seconds of silence will lead to a 403" (49472275).
- **Gemini spot-retrieval sometimes works.** One user's three requested moments "do actually exist in the video, I checked. If there are more, I don't know" (47717208, 2026-04-10). The caveat about missed moments is the same omission risk simonw raised.
- **Claude's frame route works but is expensive, and people are sceptical it captures motion.** These come from the Show HN for claude-real-video (48766005, 2026-07-02, 167 points, 62 comments; the repo now has 2,257 stars, MEASURED via `gh api`):
  - "keyframes are not videos. Motion, object permanence, are not things Claude can infer from a set of images"
  - "Pretty terribly expensive way to watch a video with Claude. Use Gemini or some local VLM"
  - "With Gemini 3.1 flash lite an hour of video works out to $0.24 at the API rates". My ESTIMATE in §4 is $0.12 at low resolution and $0.29 at default resolution with audio, so this is consistent.
  - "NotebookLM … was only analysing the transcripts and not the video"
  - "my experience with ffmpeg scene detection is that it's flaky"
  - Also: "a frame rate of 2fps is generally sufficient", and putting frames in a grid "worked decently" for motion design.
- **The most-installed Claude skill fails silently in specific ways.** From bradautomates/claude-video issues (19,117 stars, 210 open issues, last push 2026-09-25, all MEASURED via `gh api`):
  - #99 and #117: ffmpeg 9 removed `-vsync`, so "both frame paths fail, zero frames extracted"
  - #222: "Whisper invents dialogue on videos with no speech, and it is presented as a normal transcript"
  - #178: "--fps override silently truncates frame coverage to the head of the video"
  - #37: "2 fps hard cap yields 1–2 frames" on sub-second clips
  - #250: Gemini engine "repeated HTTP 503 … no bounded retry"
  - #144 and #240: non-English videos get the auto-translated captions
  - #93: on macOS with brew's yt-dlp, "frames never extract"
- **Tinycloud** has 2 Show HN comments, both enthusiastic and neither measured (47720755, 2026-04-10). **No HN story mentions Memories.ai in 2026** (Algolia: 0 hits).

Reading (INFERRED): the community's failure modes match the measured traps in our own baseline: a hallucinated final ASR line, erased pauses, sheet-level misreads (REPORT.md rows 3 and 6). Practitioners also arrive at our design independently: deterministic ASR for timing, a model for semantics, and verification against the source.

---

## 4. Normalized price per hour of video (one full pass, input side)

Method (ESTIMATED unless marked published):
- Token-priced routes: tokens per hour × price.
- Per-minute routes: × 60.
- Output tokens are excluded unless stated. A typical 5K-token answer adds $0.02 to $0.10.
- Prices are from the pages fetched 2026-10-24, or from APIs whose publication date is given.

| Route | Unit price (source, date) | $/video-hour | Notes |
|---|---|---|---|
| **Local ffmpeg + whisper.cpp + Apple Vision OCR** | $0 | **$0** plus machine time | No egress. Quality is what our baseline measured (REPORT.md) |
| **Claude Opus 5.5 reading frames (our route)** | $4/MTok input, $20 output, cache hit $0.20 (https://platform.claude.com/docs/en/about-claude/pricing, fetched 2026-10-24). Image tokens = ⌈w/28⌉·⌈h/28⌉ (F3) | **a)** 100 frames at 512×288 (claude-video "balanced"): 20.9K tok → **$0.08**. **b)** 600 frames at 512×288 (Google's LVBench frame count): 125K → **$0.50**. **c)** 1 frame/10 s at 1280×720: 431K → **$1.72**. **d)** 1 fps as 16-up 2000×1125 contact sheets: 225 × 2,952 = 664K → **$2.66**. Transcript about 12K tokens → $0.05 | Re-asking over cached frames costs 5% of the first read. Limits: 600 images per request, ≤2000 px once there are more than 20 images. Sonnet 5.5 costs half ($2/MTok) |
| **Gemini 3.5 Flash-Lite** (static) | $0.30/MTok, audio same (ai.google.dev pricing, updated 2026-10-22) | **$0.11** low (360K tok) / $0.32 high | Free-tier data is used to improve products; paid tier is not |
| **Gemini 3.1 Flash-Lite** | $0.25 video/image, $0.50 audio | **$0.12** low / $0.29 default (258 tok/frame) | Community figure: "$0.24" (HN 48766005) |
| **Gemini 3.8 Flash** (static) | $0.75/MTok until 2026-12-31, then $1.50 | **$0.27** low / $0.81 high; **$0.54 / $1.62 from 2027-01-01**; batch half | Agentic mode is vendor-claimed at up to 88% fewer tokens (≈$0.04 per query on the cited benchmark) |
| **Gemini 3.1 Pro Preview** | $4/MTok above 200K tokens | **$1.44** low | — |
| **Gemini 4 Argon** | $2/MTok until 2026-11-30, then $4; batch $1/$2 | **$0.72** low now; **$1.44 from 2026-12-01**; high resolution does not fit in one call (1.08M > 1,048,576) | The pricing page lists it. HackerNoon (6 Oct) says access is currently limited to "trusted cyber defenders through Google's Fairwind Program" (DOCUMENTED, secondary). Treat it as possibly not callable |
| **Twelve Labs Pegasus 1.6 / 1.5**, direct | Analyze input $1.75/h; output $7.50/MTok (https://www.twelvelabs.io/overage, fetched 2026-10-24) | **$1.75** plus output | Also needs a plan: Free $0 (3 GB), Plus $29/mo (50 GB), Pro $99/mo (200 GB). Storage overage $0.065/GB-month; Jockey $2/MTok |
| **Pegasus 1.5 on Amazon Bedrock** | $0.00049 per input video second, effective 2026-10-01 (AWS Price List CSV `AmazonBedrockFoundationModels`, published 2026-10-12, MEASURED by grep) | **$1.76** | Output $7.50/MTok |
| **Twelve Labs Marengo 3.0 embed** (search index) | $2.50/h video plus $0.50/h audio, direct; Bedrock $0.0007/s | **$3.00** direct / **$2.52** Bedrock | Marengo 3.5 is token-priced ($0.26/MTok video); tokens per hour are not published |
| **Cloudglue** describe/extract/index | 4 credits/min; packs from $15/1,000 to $600/60,000 credits (https://cloudglue.dev/pricing, fetched 2026-10-24) | **$2.40–$3.60** | No change since October. Last feature release 2026-08-29 (F3) |
| **Memories.ai** Video Datalake | $0.05/min at fps 1.0; vendor says "about $0.90 per hour" at fps 0.3 (https://docs.memories.ai/datalake/pricing.md, fetched 2026-10-24) | **$3.00** at fps 1 / **$0.90** at fps 0.3 | Plus search $0.008/call, storage $0.02/GB-month. Data is deleted 30 days after the balance hits zero |
| **Reka Vision API** | $0.05/min indexing; QA $2/MTok output (https://docs.reka.ai/vision/pricing.md, fetched 2026-10-24) | **$3.00** | Free 3 h; developer-tier data auto-deletes after 30 days |
| **Mixpeek** | The current page shows "Build $25/month plus usage … metered per unit of content", with no per-minute figure (fetched 2026-10-24) | **unknown today**; $3.00 per the Oct-06 baseline ("as of August 2026") | Pricing model changed after October |
| **VideoDB** | "Talk to us"; no public price (https://videodb.io/pricing, fetched 2026-10-24) | **unknown** | Software Advice lists "from $20/month" (secondary) |
| **Amazon Bedrock Data Automation** (video) | $0.05/min standard; $0.084/min custom (AWS Price List CSV `AmazonBedrock` us-east-1, last-modified 2026-10-16, MEASURED by grep) | **$3.00** standard / **$5.04** custom | Previously SECONDARY in October; now confirmed |
| **Amazon Nova 2 Omni / Nova 2 Pro** (video tokens) | Omni $0.30/MTok; Pro $1.375/MTok, us-east-1 (same CSV) | **unknown**: video tokens per second not found | Nova 2 Lite ignores audio in video (Oct baseline) |
| **Azure Content Understanding** (video) | Extraction $1.00/h plus contextualization $0.001/1K tokens plus model tokens (Azure Retail Prices API, eastus, MEASURED 2026-10-24) | **≥$1.00**; Microsoft's illustrative total is $3.33 (Oct baseline) | Needs an Azure subscription |
| **Azure AI Video Indexer** | Standard video $0.09/min + audio $0.024; advanced $0.15 + $0.04; basic $0.045 + $0.0126 (Retail Prices API, MEASURED 2026-10-24; effective dates 2022–2023) | **$6.84** standard / **$11.40** advanced / **$3.46** basic | Prices unchanged for 3+ years |

**Price ranking (ESTIMATED):**
1. Local route, $0.
2. Claude reading about 100 thumbnails, about $0.08.
3. Gemini Flash-Lite, $0.11–0.12.
4. Gemini 3.8 Flash at low resolution, $0.27, which doubles on 2027-01-01.
5. Claude reading 600 small frames, about $0.50.
6. Gemini 4 Argon, $0.72, which doubles on 2026-12-01.
7. Gemini 3.1 Pro, $1.44.
8. Pegasus, $1.75.
9. Claude 720p at 0.1 fps, $1.72; Claude 1 fps contact sheets, $2.66.
10. Cloudglue, Memories.ai at fps 1, Reka and Bedrock Data Automation, $2.40–3.60.
11. Azure Video Indexer, $3.46–11.40.

Dedicated services cost about 8 to 100 times Gemini Flash-Lite for one pass: $0.90 to $11.40 against $0.11 (ESTIMATED from the table).

---

## 5. Products and models with **no** independent evidence (as of 2026-10-24)

DOCUMENTED absence: searches plus the boards in §1 and §2.

- **Twelve Labs Pegasus 1.5 and 1.6, and Jockey.** Pegasus appears on no public video QA board, and its claims are vendor-run. Pegasus 1.6 (GA 2026-10-06) has no published benchmark at all; one news write-up notes "claims … came without published reproducible metrics". Marengo 3.5 has one competitor-run retrieval number (VideoDB, §2).
- **Cloudglue / Tinycloud.** No evaluation; 2 HN anecdotes.
- **Memories.ai.** No evaluation; its comparison pages have been withdrawn.
- **VideoDB.** Only its own benchmarks (action retrieval; WGO-Bench segmentation F1 of 28.93 vs 19.92 for a baseline, self-run).
- **Reka Vision API and Reka Rho-1.** Vendor posts only.
- **Mixpeek.** Vendor lists only.
- **Amazon Bedrock Data Automation.** No evaluation. Nova 2 Omni has a self-reported Video-MME of 77.9, and Nova Multimodal Embeddings appear in VideoDB's competitor-run benchmark.
- **Azure AI Video Indexer and Azure Content Understanding.** No third-party evaluation found.
- **Gemini agentic video mode.** Vendor numbers plus one partner ratio.
- **Gemini 4 Argon.** Vendor table only, and not generally callable per HackerNoon.
- **Gemini 3.7 and 3.8 Flash on video.** Self-reported LVBench rows only; no owner-run board has them yet.
- **Claude Opus 5.5 on video.** Only Google's competitor-run LVBench row.
- **Agent skills** (claude-video, claude-real-video, claude-video-vision, claude-eyes, video-understanding-skill). No evaluation; community anecdotes and issue trackers only. claude-eyes self-reports 88 of 92 cuts and 0 of 8 dissolves (F3).

**With at least some independent or owner-run evidence:**
- Gemini 3 Pro and 3 Flash (Video-MME-v2)
- Gemini 3.1 Pro and 3.5 Flash (VideoGAIA)
- Gemini 2.5 Pro (HolmesV2, VideoOdyssey via F2)
- GPT-5, 5.2, 5.4 and 5.5 (Video-MME-v2, VideoGAIA)
- Claude Opus 4.6, 4.7 and 4.8 (VideoGAIA)
- Kimi K2.5–K3, Seed 2.0 Pro, Qwen3.5–3.8 (Video-MME-v2, VideoGAIA)
- Open VLMs (VLMEvalKit and lmms-eval, both Apache-2.0 or similar, about 4.4K stars each, pushed 2026-10-22; MEASURED)

---

## 6. Ranked entries for an agent builder (comparison)

| # | Entry | Category | Independence of evidence | What it tells a Claude agent builder | Staleness |
|---|---|---|---|---|---|
| 1 | VideoGAIA | benchmark | Independent | Claude Opus 4.7 and 4.8 are last of 20 on a frames-plus-tools agent loop; Opus 4.6 is mid-pack. This is the only independent Claude video agent result | Aug 2026 |
| 2 | Video-MME-v2 | benchmark | Owner-run | Best 49.4 vs human 90.7; frame count moves scores by 4–9 points; no Claude row | Apr–Aug 2026 |
| 3 | Google's Argon LVBench table | frontier-api | Competitor-run | The only Opus 5.5 video number: 83.7 at 600 frames vs Argon 91.7 at 1 fps | Oct 2026 |
| 4 | Gemini API (3.5 Flash-Lite, 3.8 Flash, agentic) | frontier-api | Mixed: Gemini 3 is owner-run on v2; agentic mode is vendor-only | Cheapest escalation at $0.11–0.27/h; community reports wrong timestamps | Oct 2026 |
| 5 | Video-Oasis audit | benchmark | Independent | 55% of benchmark items are answerable without video, so read every high score with that discount | Jul 2026 (v2) |
| 6 | Video-HolmesV2 | benchmark | Owner-run | Multiple-choice accuracy overstates evidence by about 2×; long video drops about 7 points | Sep 2026 |
| 7 | Aggregators (llm-stats, benchlm, benchmarklist, DataLearner) | benchmark | Self-reported; 0 verified rows | Useful to spot vendor claims, not as evidence | Oct 2026 |
| 8 | LVBench official and aggregate | benchmark | Official board is owner-run but stale; 2026 rows are self-reported | Hour-scale gap to humans is now about 3–15 points on vendor claims | Official 2025-05 (stale) |
| 9 | Legacy boards: Video-MME v1, MLVU, LongVideoBench, MVBench, TempCompass, VideoMMMU, Video-Holmes v1 | benchmark | Official boards stale; current rows self-reported | Saturated (80–89), or missing frontier models (TempCompass, Holmes) | 2024–2025 (stale) |
| 10 | VSI-Bench | benchmark | Self-reported papers; one third-party GPT-5 row | Spatial reasoning: no 2026 frontier row; scores are composition-sensitive (FN-VSI) | Repo 2025-08 (stale) |
| 11 | VideoDB action-retrieval benchmark | search-embedding-infra | Vendor-run, data downloadable | The only number on Marengo 3.5 and Nova embeddings for temporal retrieval | Oct 2026 |
| 12 | Twelve Labs (Pegasus 1.6, Marengo 3.5, Jockey) | agent-native-startup | Vendor-only | $1.75/h; claims are unverifiable | Oct 2026 |
| 13 | Cloudglue / Tinycloud | agent-native-startup | None | $2.40–3.60/h; development paused | Sep 2026 |
| 14 | Memories.ai | agent-native-startup | None (claims withdrawn) | $0.90–3.00/h | Oct 2026 |
| 15 | Reka Vision API | agent-native-startup | None | $3.00/h | Oct 2026 |
| 16 | Amazon Bedrock (BDA, Nova 2, TwelveLabs on Bedrock) | hyperscaler-service | None for BDA; Nova embeddings competitor-run | $1.76–5.04/h (MEASURED prices) | Oct 2026 |
| 17 | Azure Video Indexer / Content Understanding | hyperscaler-service | None | $1.00–11.40/h (MEASURED prices) | Prices 2022–2026 |
| 18 | Claude frame-route skills (claude-video, claude-real-video and others) | agent-integration | Community and issue trackers only | $0.08–2.66/h of Opus input; silent failure modes are documented | Oct 2026 |

---

## 7. Narrative for this axis (INFERRED)

The field has split into two evidence regimes. The legacy academic boards (Video-MME, LVBench, LongVideoBench, TempCompass, Video-Holmes) stopped running new models in 2024–25. Their 2026 numbers now arrive as vendor self-reports that aggregators label unverified, and they cluster at 80–92. A new generation of harder, owner-run or independent benchmarks keeps the best model 30–55 points below humans: Video-MME-v2, VideoGAIA, Video-HolmesV2 and VideoOdyssey, plus the Video-Oasis audit. These are the only places Claude appears in 2026.

The VideoGAIA result matters most for us. Under the same protocol our pipeline uses (sampled frames, a tool to fetch more frames from a chosen segment, and web tools), recent Claude Opus versions rank at the bottom. GPT-5.5 (53.1) and Gemini 3.1 Pro (50.9) score 14–18 points higher than Opus 4.7 and 4.8 (34.7, 36.9). One plausible reading is that newer Opus versions are weaker at deciding where to look, rather than at reading frames. That would argue for deterministic indexing (cuts, OCR, ASR) feeding Claude, rather than Claude-driven exploration. This is INFERRED from one benchmark, at about ±6 points, on Opus 4.7 and 4.8 rather than 5.5.

Google's competitor-run LVBench row (Opus 5.5 at 83.7 with 600 frames) is the counterweight. With enough frames, Opus 5.5 is within single digits of Gemini on hour-long QA.

On commercial services, nothing independent exists, and the vendors' own comparisons use private datasets. Twelve Labs is the clearest case: its homepage carries "+13.1%" against Gemini 3.1 Pro with no metric. A team choosing a service therefore has two sound options. One is a small bake-off on its own recordings, which `video-api-alternatives.md:100` already recommended. The other is to pick on mechanism and price. On price, Gemini Flash-Lite and Claude's own thumbnail route are within 2× of each other, and both are roughly 15–30× cheaper than the $1.75–3.60 dedicated services for a one-pass read (ESTIMATED).

---

## 8. Gaps and caveats

- I ran no model and evaluated no service. Every quality number is someone else's.
- Google's Argon table, the 600-frame Opus 5.5 setting and the Fairwind access limit all come from secondary reproductions. Google DeepMind's evaluation-methodology page was not reached.
- benchmarklist's "Claude Opus 4.8 MVBench 67.1" and "Claude Opus 4.6 Max MLVU 81.7" have no traceable source and may be relabelled Claude 4.5 Opus rows.
- Gemini pricing and video docs were read via WebFetch summaries, because curl hits a devsite sign-in redirect (MEASURED: `curl -sI` returns 302 to `/oauth2authorize`).
- Twelve Labs' Video-to-Text Arena date is approximate.
- Nova 2 and Marengo 3.5 tokens per hour are not published, so those per-hour figures are unknown.
- Mixpeek's current per-minute price is not on its page.
- VideoGAIA has 271 tasks, so ranks within about 6 points are not separable (ESTIMATED binomial interval). Its Claude rows come from Opus 4.6–4.8, not 5.5.
