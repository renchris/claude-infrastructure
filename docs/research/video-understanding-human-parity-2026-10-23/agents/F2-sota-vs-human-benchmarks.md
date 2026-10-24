# F2 — State of the art vs human performance in video understanding, by axis (2026-10-23)

Labels: **MEASURED** = this agent ran it (a fetch plus a grep of a downloaded paper, done on 2026-10-23; the command is named). **DOCUMENTED** = a paper, vendor or leaderboard says it (URL given). **INFERRED** = this agent's arithmetic or judgement. Every "gap" is INFERRED arithmetic: human minus best model, in points, on the benchmark's own metric.

Scope note: I did no model runs. "MEASURED" here covers only retrieval checks, e.g. "grep found no human baseline in the paper". I used papers fetched as `/tmp/f2dl/*.html` (arXiv HTML via curl), searched with `/tmp/f2scripts/grab.py <url> <file> <regex>`.

---

## 0. Bottom line

- **Parity holds only on a few narrow axes.** These are knowledge recall from lecture-style video, EgoSchema-style 3-minute egocentric QA, metric size estimation, and goal inference from egocentric clips. Everywhere else the gap is 10–60 points (INFERRED, from the tables below).
- **The newest, harder benchmarks agree.** Video-MME-v2 (Apr 2026), MMSI-Video-Bench (Dec 2025), VideoOdyssey (Oct 2026) and AVI-Bench (Jun 2026) all put the best frontier model 28–58 points below humans (DOCUMENTED, URLs below).
- **The older benchmarks without a human baseline are saturated.** Video-MME v1, MLVU and MVBench sit at 78–89 but publish no human number (MEASURED by grep, §1). They cannot support a parity claim either way.
- **Claude almost never appears on video leaderboards.** Most appearances are third-party tables that feed it sampled frames. Claude Opus 4.5 trails Gemini 3 Pro by 10.8 points on Video-MME with subtitles and 18.9 on LVBench, as reported in the Qwen3.5 model card (DOCUMENTED, §7). I found no Anthropic-published video benchmark for Opus 4.7, 5 or 5.5 (§7).

---

## 1. Semantic QA (general and long-video understanding)

| Benchmark (year) | Best model, score | Human | Gap | Claude | Source / label |
|---|---|---|---|---|---|
| **Video-MME-v2** (Apr 2026), group-consistency "Non-Lin" score, with subtitles | Gemini-3-Pro 49.4 (avg acc 66.1); without subtitles 38.2 | Human experts 90.7 (avg acc 94.9) | **41.3** Non-Lin; 28.8 acc | not evaluated | https://arxiv.org/html/2604.05015 — DOCUMENTED. Prior repo copy: `~/.claude/research-artifacts/meeting-video-2026-10-06/model-understanding.md:28` |
| Video-MME-v2, by level (with subtitles) | Gemini-3-Pro L1 perception 64.0 / L2 temporal 50.0 / L3 reasoning 40.6 | 94.8 / 91.1 / 87.9 | 30.8 / 41.1 / **47.3** | — | same URL — DOCUMENTED |
| **Video-MME v1** (2024; scores 2025–26) | Gemini-3 Pro 88.4 with subtitles / 87.7 without; benchlm lists Seed 2.1 Pro at 89.2 (subtitle setting not stated) | **none published** | n/a | Claude 4.5 Opus 77.6 with subtitles / 81.4 without | https://huggingface.co/Qwen/Qwen3.5-397B-A17B ; https://benchlm.ai/benchmarks/videomme — DOCUMENTED. No human baseline: grep `Human [Ee]xpert\|[Hh]uman (performance\|baseline\|accuracy\|level)` on arXiv 2405.21075v3 found 0 matches — MEASURED |
| **LVBench** (2024, rev. 2025), hour-long | Gemini-3 Pro 76.2; Deep Video Discovery agent 76.0 with transcripts | 94.4 | **18.2** | Claude 4.5 Opus 57.3 | Qwen3.5 card (above); human row in Table 3 of https://arxiv.org/html/2406.08035 — DOCUMENTED (grep hit "Overall Human … 94.4" — MEASURED). Agent result: `model-understanding.md:30` |
| **Video-MMMU** (2025), knowledge acquisition from lecture video | Qwen3.8 Max 88.7, Gemini 3 Pro 87.6 | Human expert 74.44 (senior undergraduates) | **−14.3 (models ahead)** | Claude Opus 4.5 84.4 (benchlm rank 9); Claude-3.5-Sonnet 65.78 was the paper's top model in 2025 | https://benchlm.ai/benchmarks/videommmu ; https://arxiv.org/html/2501.13826 Table "Human Expert 74.44 … Claude-3.5-Sonnet 65.78" — DOCUMENTED (grep hit — MEASURED) |
| **MLVU** (2024) | Qwen3.5-397B 86.7 M-Avg | **none published** | n/a | Claude 4.5 Opus 81.7 | Qwen3.5 card — DOCUMENTED. No human baseline: grep of arXiv 2406.04264 hit only "human annotators" in annotation text — MEASURED |
| **LongVideoBench** (2024) | Deep Video Discovery agent 71.6 | **none published** | n/a | — | `model-understanding.md:30` — DOCUMENTED. Grep of arXiv 2407.15754 hit only licence and annotator text — MEASURED |
| VideoReasonBench (2025) | Gemini-2.5-Pro 56 | 73.8 | ~18 | — | search summary of https://arxiv.org/pdf/2505.23359 — DOCUMENTED (secondary; I did not read the primary) |

Reading: on knowledge-heavy and speech-heavy QA, models pass a non-expert human bar (Video-MMMU). Once questions are grouped so that a correct answer must hold up under consistency checks, the best model reaches about half the human score (Video-MME-v2) (INFERRED). Video-MME-v2 also says leaderboard scores overstate real comprehension, and that perception errors cascade into reasoning (DOCUMENTED, `model-understanding.md:28`). About 30% of Video-MME and MLVU items can be answered with no frames at all (DOCUMENTED, arXiv 2505.14321 via `~/.claude/research-artifacts/meeting-video-2026-10-06/adv-red-team.md:9`).

---

## 2. Spatial / 3D reasoning from video

| Benchmark (year) | Best model, score | Human | Gap | Claude | Source / label |
|---|---|---|---|---|---|
| **VSI-Bench "Thinking in Space"** (Dec 2024) | End-to-end: SenseNova-SI 68.8 (CVPR 2026) and Cambrian-S-7B 67.5 (69.2 when fine-tuned on VSI-590K). Frontier general models: GPT-5 55.03, Gemini-2.5-Pro 51.5 | 79.2 (400-question tiny subset; humans had unlimited time and could re-watch) | **10.4** (specialist models); **24.2** (GPT-5) | not evaluated | human table: https://arxiv.org/html/2412.14171v1 ; GPT-5: https://arxiv.org/html/2508.13142 (v5, 30 Dec 2025) Table 7; Cambrian-S: https://cambrian-mllm.github.io/cambrian-s/ ; SenseNova: https://arxiv.org/abs/2511.13719 — DOCUMENTED. "Unlimited time" comes from a search summary — DOCUMENTED (secondary) |
| VSI-Bench per task, GPT-5 vs human | Object size 73.31 vs 60.4; room size 47.52 vs 45.9; absolute distance 34.47 vs 47.0; object count 53.31 vs 94.3; relative distance 63.71 vs 94.7; relative direction 48.69 vs 95.8; route plan 50.26 vs 95.8; appearance order 68.93 vs 100 | — | **models ahead on size (+12.9, +1.6)**; behind by 31–47 on configuration, route and order tasks | — | arXiv 2508.13142 Table 7 — DOCUMENTED |
| VSI-Bench, agentic | RieMind (geometric tools plus GPT-4.1) 89.5, **static split only**; the authors call it an "upper bound" | 79.2 | above human, but not comparable | — | search summary of https://arxiv.org/abs/2603.15386 — DOCUMENTED (secondary). The abstract I fetched gives no absolute number, so 89.5 is unverified |
| **MMSI-Video-Bench** (Dec 2025) | Gemini 3 Pro 38.0 (chance 24.1) | 96.4 | **58.4** | Claude Haiku 4.5 34.3 | https://arxiv.org/html/2512.10863v1 — DOCUMENTED |
| **VLM4D** (ICCV 2025), spatiotemporal motion | Gemini-2.5-Pro 62.0 | 98.8 (100-question sample) | **36.8** | — | https://arxiv.org/html/2508.02095 — DOCUMENTED (grep hit "human accuracy (98.8%)" — MEASURED) |
| **VSI-SUPER** (Cambrian-S, Nov 2025), hour-scale spatial recall and count | Gemini-2.5-Flash at 60 min: recall 41.5, count 10.9; out of context at 120 min. Cambrian-S at 1 fps: recall 0.0 at 120 and 240 min | no human score | n/a (humans "count intuitively", no number) | — | https://cambrian-mllm.github.io/cambrian-s/ — DOCUMENTED |
| Spatial suite, mostly image or multi-image (Dec 2025) | MMSI 41.80 / OmniSpatial 59.90 / STARE 54.59 / SpatialViz 51.27 / SITE 61.88 / CoreCognition 84.37 (all GPT-5); MindCube-Tiny 63.56 (Grok-4) | 97.2 / 92.63 / 96.50 / 82.46 / 67.5 / 86.98 / 94.55 | 55.4 / 32.7 / 41.9 / 31.2 / 5.6 / 2.6 / 31.0 | none | arXiv 2508.13142 Table 3 — DOCUMENTED |
| ERQA, EmbSpatialBench (vendor-run) | Gemini-3 Pro 70.5 ERQA; Qwen3.5 84.5 EmbSpatial | none published | n/a | Claude 4.5 Opus 46.8 ERQA / 75.7 EmbSpatial | Qwen3.5 card — DOCUMENTED |

Reading: metric estimation (how big, how far) is at or above the human level, because humans are bad at it too. Allocentric configuration (which direction, which route), cross-view correspondence and hour-scale spatial memory are 30–60 points below humans (INFERRED). I found **no** VSI-Bench score for Gemini 3 Pro (search, 2026-10-23).

---

## 3. Temporal / causal and fine-grained motion

| Benchmark (year) | Best model, score | Human | Gap | Claude | Source / label |
|---|---|---|---|---|---|
| **TOMATO** (ICLR 2025) | Paper: Qwen2-VL-72B 37.9, GPT-4o 37.7. 2026: Seed 2.1 Pro 79.5, self-reported and unverified | 95.2 (full video); 79.7 (16 frames) | **57.3** (paper); **15.7** (Seed, self-reported) | Claude 3 Opus 28.2, Claude 3.5 Sonnet 27.8 | `/tmp/f2dl/tomato.html` grep of arXiv 2410.23266v2 — MEASURED retrieval, DOCUMENTED numbers; https://llm-stats.com/benchmarks/tomato — DOCUMENTED |
| **TempCompass** (2024) | Qwen2.5-VL-72B 74.8 (aggregator; task format not stated); Qwen3-VL-8B 0.743 | Multi-choice average 97.3 (direction 96.7, speed 90) | ~**22.5** | — | Table 2 of arXiv 2403.00476 (grep — MEASURED); scores: search summary of https://arxiv.org/pdf/2607.12304 — DOCUMENTED (secondary) |
| **TemporalBench** (NeurIPS 2024), multiple-binary | GPT-4o 38.0–38.5 | 67.9 (crowd workers, not experts) | **~30** | — | search summary of https://arxiv.org/abs/2410.10818 — DOCUMENTED (secondary) |
| **Vinoground** (2024), group score | GPT-4o ~35 with chain of thought, 24.6 plain (table extraction garbled) | 90.0 (all frames); 85.2 (32 frames) | **~55** | — | search summary of https://arxiv.org/abs/2410.02763 — DOCUMENTED (secondary, needs a check against the table) |
| **MVBench** (CVPR 2024) | GPT-5.2 78.1 | **none published** | n/a | Claude 4.5 Opus 67.2 | Qwen3.5 card — DOCUMENTED; grep of arXiv 2311.17005 for a human baseline found 0 matches — MEASURED |
| **MotionBench** (CVPR 2025) | "below 60%" for all models | **none published** | n/a | — | abstract https://arxiv.org/abs/2501.02955 — DOCUMENTED; grep of v1 HTML for a human baseline found 0 matches — MEASURED |
| **FAVOR-Bench** (NeurIPS 2025) | "less than 50%" close-ended | none found | n/a | — | search summary of https://arxiv.org/abs/2503.14935 — DOCUMENTED (secondary) |
| Video-MME-v2 Level 2 (temporal) | Gemini-3-Pro 50.0 | 91.1 | **41.1** | — | §1 — DOCUMENTED |

Reading: fine-grained motion (direction, rotation, speed, count, order) is the clearest large-gap axis. The 2024 papers put it at 30–57 points. The only 2026 claim that narrows the gap to about 16 points (Seed 2.1 Pro on TOMATO) is self-reported (INFERRED). The mechanism is consistent across papers: models recognise single frames but "fail to interpret these frames as a continuous sequence" (TOMATO abstract, DOCUMENTED). Default 1 fps sampling also misses sub-second events (DOCUMENTED, `docs/research/agent-video-understanding-2026-07-26.md:136`, `:179`).

---

## 4. Audio-visual joint understanding

| Benchmark (year) | Best model, score | Human | Gap | Claude | Source / label |
|---|---|---|---|---|---|
| **VideoOdyssey-AV** (v2, 13 Oct 2026), ultra-long omni | Gemini-3.1-Pro 46.1 | 80.7 | **34.6** | not evaluated | https://arxiv.org/html/2605.22907 — DOCUMENTED |
| **AVI-Bench** (Jun 2026) | Gemini-2.5-Pro 57.21 overall; hardest subtasks: AVSQA 16.50, ASQA 29.48, AVLG 35.08 | pilot study of 6 people: AVSQA 90.55, ASQA 86.11, AVLG 96.48 (no overall human score) | **74.1 / 56.6 / 61.4** on those subtasks | none of the 28 models is Claude | https://arxiv.org/html/2606.07643 — DOCUMENTED. The authors warn against direct human-model comparison |
| **WorldSense** (ICLR 2026, v3) | Gemini 2.5 Pro 65.1 | none reported | n/a | Claude 3.5 Sonnet 34.8 (vision only, 16 frames) | https://arxiv.org/html/2502.04326v3 ; grep of the Claude row — MEASURED retrieval |
| **Daily-Omni** (v2, Mar 2026) | Qwen3-Omni-30B-Thinking 73.60; Gemini 2.5 Flash 73.06; WITA-Omni 85.21 (press release only) | none reported | n/a | not evaluated | https://arxiv.org/html/2505.17862v2 ; https://www.utusan.com.my/?p=1399789 — DOCUMENTED |
| **AV-Odyssey** (Dec 2024) | Gemini 1.5 Pro 30.8 all-avg (third in Table 4; the field sits around 25–35, near chance) | no measured human score; DeafTest sound counting: Gemini 1.5 Pro 81% vs humans "can easily score 100%" (authors' assertion) | ~19 on sound counting (vs an asserted 100) | — | grep of https://arxiv.org/html/2412.02611v1 — MEASURED retrieval, DOCUMENTED |
| **MMOU** (2026) | Gemini 2.5 Pro 64.2 | 84.3 | **20.1** | — | search summary of https://arxiv.org/pdf/2603.14145 — DOCUMENTED (secondary) |
| **OmniVideoBench** (ICLR 2026) | Gemini-2.5-Pro 58.90; below 50 on music and background sound | not found | n/a | — | search summary of https://arxiv.org/abs/2510.10689 — DOCUMENTED (secondary) |

Reading: joint audio-visual reasoning is a large-gap axis (20–35 points overall, 55–75 on fine audio-visual localisation and sound-QA subtasks) (INFERRED). Low-level acoustics are weak points: loudness, pitch, music style and tempo. Claude has no audio input path, so it can only reach this axis through an ASR transcript (INFERRED from Claude being evaluated "vision-only" in WorldSense, DOCUMENTED). Speech is the largest single lever in semantic QA: subtitles add 10 points on Video-MME long videos (DOCUMENTED, `model-understanding.md:25`, `:32`).

---

## 5. Egocentric / long-horizon memory

| Benchmark (year) | Best model, score | Human | Gap | Claude | Source / label |
|---|---|---|---|---|---|
| **EgoSchema** (NeurIPS 2023), 3-minute clips | ~77 (HCQA-1.5, CVPR 2025 challenge, blind test); 80.76 top entry on benchmarklist (split unclear) | ~76 | **about 0 (parity)** | — | search summaries of https://arxiv.org/pdf/2308.09126, https://benchmarklist.com/benchmarks/egoschema/ — DOCUMENTED (secondary) |
| **HourVideo** (NeurIPS 2024), 20–120 min | Gemini 1.5 Pro 37.3 (no newer public result found) | 85.0 (3 experts, 14 videos, 11.2 h, 213 questions) | **47.7** (stale; 2024 model) | — | grep of https://arxiv.org/html/2411.04998 — MEASURED retrieval, DOCUMENTED |
| **VideoOdyssey-V** (Oct 2026) | Gemini-3.1-Pro 56.3 | 84.4 | **28.1** | — | https://arxiv.org/html/2605.22907 — DOCUMENTED |
| LVBench (see §1) | 76.2 | 94.4 | 18.2 | Claude 57.3 | §1 |
| VSI-SUPER (see §2) | counting collapses to 10.9 at 60 min | — | — | — | §2 |

Reading: EgoSchema is solved at roughly human level. Its 3-minute clips are "long" only by 2023 standards. At hour scale, humans still lead by 18–48 points, and in streaming spatial counting models degrade to near zero beyond about 1 hour (INFERRED from the rows above).

---

## 6. Theory of mind / social cues in video

| Benchmark (year) | Best model, score | Human | Gap | Claude | Source / label |
|---|---|---|---|---|---|
| **MoMentS** (EMNLP Findings 2025), short films | LLaVA-Video-72B 67.66 (video plus transcript; open models only) | 86.33 average / 91.0 majority vote (100-item sample) | **18.7** | not evaluated (no frontier closed model was tested) | https://arxiv.org/html/2507.04415v2 — DOCUMENTED |
| **EgoToM** (Meta, 2025) | goal: models >80; belief and action: "about 50+% at best" (GPT-4-turbo, Llama-3.1-405B) | goal ~90, belief ~70, action ~77 | goal **~<10 (near parity)**; belief **~20**; action **~27** | not evaluated | https://arxiv.org/html/2503.22152 (text approximations; exact values are in Fig. 4) — DOCUMENTED |
| IntentBench-Prime, from Social-IQ 2.0 / EMER / MDPE (Aug 2026) | Qwen2.5-Omni-7B SFT 70.4 (Hard split) | none reported | n/a | Claude Haiku 4.5 used only as a curation auditor | https://arxiv.org/html/2608.13239 — DOCUMENTED |
| SocialOmni (2026, v3 Sep 2026); Motion2Mind (Nov 2025) | numbers not retrieved; Motion2Mind was withdrawn for revision (May 2026) | — | — | — | https://arxiv.org/abs/2603.16859 ; https://arxiv.org/abs/2511.15887 — DOCUMENTED |

Reading: the evidence on ToM is thin and dated. No 2026 frontier closed model (Gemini 3, GPT-5.x, Claude) has a published score with a human baseline on a video ToM benchmark that I found (search, 2026-10-23). Where data exist, goal inference is near parity; beliefs, next actions and mental states from film trail humans by roughly 19–27 points (INFERRED).

---

## 7. Where Claude appears

DOCUMENTED; all scores are third-party unless stated.

- **Qwen3.5-397B model card**, run by the vendor, Claude 4.5 Opus column: Video-MME 77.6 with subtitles / 81.4 without, VideoMMMU 84.4, MLVU 81.7, MVBench 67.2, LVBench 57.3, MMVU 77.3, ERQA 46.8, EmbSpatialBench 75.7, CountBench 90.6 — https://huggingface.co/Qwen/Qwen3.5-397B-A17B. Gemini-3 Pro, same table: 88.4 / 87.7 / 87.6 / 83.0 / 74.1 / 76.2 / 77.5 / 70.5 / 61.2 / 97.3.
- **benchlm VideoMMMU**: Claude Opus 4.5 84.4, rank 9 of 12 (snapshot 2026-10-23) — https://benchlm.ai/benchmarks/videommmu. No Claude entry on benchlm Video-MME — https://benchlm.ai/benchmarks/videomme.
- **MMSI-Video-Bench**: Claude Haiku 4.5 34.3 vs Gemini 3 Pro 38.0 — arXiv 2512.10863.
- **WorldSense**: Claude 3.5 Sonnet 34.8, vision only — arXiv 2502.04326v3.
- **TOMATO**: Claude 3 Opus 28.2, Claude 3.5 Sonnet 27.8 — arXiv 2410.23266v2.
- **Video-MMMU (paper, 2025)**: Claude-3.5-Sonnet 65.78 with 20 frames, the top model in the paper at the time — arXiv 2501.13826.
- **Absent from** Video-MME-v2, the VSI-Bench GPT-5 evaluation (2508.13142), VideoOdyssey, AVI-Bench, MoMentS, EgoToM and Daily-Omni (DOCUMENTED per paper fetches above).
- **Opus 4.7 / 5 / 5.5**: I found no video benchmark in any Anthropic-published table. The Azure catalog lists Opus 4.7 system-card rows with no video benchmark — https://ai.azure.com/catalog/models/claude-opus-4-7. A third-party catalog lists Opus 5.5 input as text, images and files, not video — https://www.orcarouter.ai/blog/claude-opus-5-5-video-plan-one-shot. Both are DOCUMENTED (secondary); I did not open the Opus 5.5 system card.
- Implication: as Opus 5.5, video understanding runs through sampled frames plus an external ASR transcript. Its per-axis ceiling is roughly the Claude 4.5 Opus frame-based numbers above, plus whatever the agent's tooling adds. The Deep Video Discovery agent gained 17 points over a single pass on LVBench (`model-understanding.md:30`). This is INFERRED; I ran no Claude video evaluation.

---

## 8. Conclusion: parity map, with numbers

**At or above human level (INFERRED from the DOCUMENTED rows):**

- Knowledge acquisition from lecture or professional video: Video-MMMU 88.7 vs 74.44, i.e. +14.3. The human bar is senior undergraduates.
- 3-minute egocentric QA: EgoSchema ~77–81 vs ~76.
- Metric size estimation: VSI-Bench object size 73.3 vs 60.4, room size 47.5 vs 45.9.
- Goal inference from egocentric video: EgoToM >80 vs ~90, so near parity.
- Dense on-screen text extraction: models exceed a casual viewer. This is the prior repo self-assessment, `docs/research/agent-video-understanding-2026-07-26.md:152-155`, INFERRED there and not benchmarked.

**Moderate gap, 10–25 points:**

| Benchmark | Gap (points) |
|---|---|
| VSI-Bench overall, specialist models (79.2 vs 68.8) | 10.4 |
| VSI-Bench overall, frontier generalists (GPT-5) | 24.2 |
| LVBench | 18.2 |
| MoMentS ToM | 18.7 |
| MMOU audio-visual | 20.1 |
| EgoToM belief | ~20 |
| TempCompass | ~22.5 |
| TOMATO, 2026 self-reported only | 15.7 |

**Large gap, over 25 points:**

| Benchmark | Gap (points) |
|---|---|
| MMSI-Video-Bench (spatial) | 58.4 |
| TOMATO (paper) | 57.3 |
| Vinoground | ~55 |
| HourVideo (stale) | 47.7 |
| Video-MME-v2 reasoning level | 47.3 |
| VSI-Bench relative direction / route planning (GPT-5) | 47.1 / 45.5 |
| Video-MME-v2 overall | 41.3 |
| VLM4D | 36.8 |
| VideoOdyssey-AV | 34.6 |
| TemporalBench | ~30 |
| VideoOdyssey-V | 28.1 |
| EgoToM next action | ~27 |
| AVI-Bench audio-visual subtasks | 57–74 |

**Answer to the operator's question (INFERRED):** no. No 2026 model, Claude included, "watches a video through like a human" across semantic, spatial, temporal, audio and social axes together. Parity exists only where the answer is in speech, text or single-frame semantics. Configuration-level spatial reasoning, fine motion, joint audio-visual reasoning, hour-scale memory and mental-state inference remain 20–60 points below humans on the newest benchmarks.

---

## 9. Caveats and unverified items

- Human baselines are thin, from small samples:
  - VSI-Bench: 400-question subset, unlimited time.
  - HourVideo: 213 questions.
  - VLM4D and MoMentS: 100 items each.
  - TemporalBench: crowd workers.
  - Video-MMMU: undergraduates.
  - AVI-Bench: a 6-person pilot.
  Treat each gap as ±several points (INFERRED).
- Numbers I took only from search summaries, without reading the primary table: Vinoground ~35, TemporalBench 38, MMOU, OmniVideoBench, VideoReasonBench, EgoSchema SOTA, RieMind 89.5 and TempCompass 74.8. They are marked "secondary" above.
- Several 2026 leaderboard numbers are self-reported by vendors and unverified (Seed 2.1 on TOMATO and Video-MME; WITA-Omni on Daily-Omni). The benchlm Video-MMMU row for Claude Opus 4.5 gives no source; it matches the Qwen3.5 card value of 84.4.
- I did not research TinyCloud or CloudGlue internals here; sibling file P3 covers them.
- The privacy constraint was respected: from the meeting-video artifacts I used only public benchmark numbers (`model-understanding.md`, `adv-red-team.md`).
