# c3-multimodal-professional — Claude Opus 5.5 System Card pp. 199-221 (§8.13-§8.17)

Source: /tmp/opus55-src/syscard.pdf (PDF page == printed page). Charts read visually via Read(pages); values marked "approx." are read off plots, not printed. Cross-refs to prompting.txt / announce.txt noted where they speak to the same benchmarks.

## Page 199 top — tail of §8.12.5 (multi-agent eval methodology; belongs to chunk c2/§8.12)
- Token usage counted "once per window rather than once per model request", summed over all agents. Latency is DERIVED: tokens / fixed reference prefill+decode rates + measured tool time; clocks carried across hand-offs; ProgramBench = longest trajectory; DRACO = lead's final clock. (Context only; no numbers on this page.)

## §8.13 Multimodal

### 8.13.1 Chartography (pp. 199-202)
- 100 tasks, specialized chart types (Kaplan-Meier, candlestick, contour, wind rose, Sankey, Bode, 3D surface); graded against expert acceptable ranges per chart.
- Config: adaptive thinking + max effort for headline; with tools = container with image + std libs + image cropping tool. Grader: Gemini 3.5 Flash (matching Surge leaderboard); prior cards used Sonnet 4.6 as judge for Claude only -> slightly lower previous scores.
- Headline (Fig 8.13.1.A, max effort, 5 runs, 95% CI):
  | model | no tools | with tools |
  |---|---|---|
  | Opus 5.5 | 64.4 | 89.0 |
  | Fable 5.1 | 44.8 | 88.4 |
  | Opus 5 | 29.8 | 83.4 |
  | Sonnet 5 | 15.6 | 73.2 |
  | Gemini 3.8 Flash (Surge, no tools) | 42.5 | — |
  | GPT-5.6 Sol (Surge, no tools) | 45.0 | — |
- Text: "Without tools, Claude Opus 5.5 shows step-function improvement in raw visual reasoning capabilities, outperforming Claude Fable 5.1 by a wide margin."
- Fig 8.13.1.B (no tools, accuracy vs cost/task, log x; effort points NOT labelled; presumably ascending effort left->right), approx.:
  - Opus 5.5: $0.021 57.0 · $0.026 59.0 · $0.031 59.2 · $0.08 62.4 · $0.48 64.4  (flat: +7pt over ~23x cost)
  - Fable 5.1: $0.026 36.6 · $0.045 42.0 · $0.08 46.0 · $0.30 47.0 · $0.85 44.8 (top point BELOW the previous — non-monotone)
  - Opus 5: $0.016 17 · $0.04 22.5 · $0.07 25.8 · $0.15 26.5 · $0.25 30.0
  - Sonnet 5: $0.004 7 · $0.01 11.5 · $0.022 14 · $0.04 14.4 · $0.35 15.6
  - => Opus 5.5 cheapest point (~$0.02, ~57%) beats every point of every other Claude model, incl. Fable 5.1 at ~$0.85.
- Fig 8.13.1.C (with tools), approx.:
  - Opus 5.5: $0.04 71.5 · $0.09 85.2 · $0.12 86.8 · $0.30 89.6 · $1.3 89.0 (peak at 4th point; max slightly lower at ~4x cost)
  - Fable 5.1: $0.15 54.5 · $0.21 67.5 · $0.40 74.5 · $0.70 77.0 · $1.25 87.7 · $2.1 88.4 (6 points)
  - Opus 5: $0.085 46 · $0.15 57.8 · $0.25 69.5 · $0.50 78.5 · $0.90 84.0 · $1.25 83.4 (6 points)
  - Sonnet 5: $0.15 28.3 · $0.35 52.9 · $0.60 64.9 · $0.90 66.6 · $1.5 73.2
  - Text: "Given access to tools, Claude Opus 5.5 Pareto-dominates prior Claude models on the score-cost frontier."
  - => Opus 5.5 at ~$0.09 (~85%) > Opus 5 max (83.4% at ~$1.25): ~14x cheaper. Opus 5.5 at ~$0.30 (~89.6%) >= Fable 5.1 max (88.4% at ~$2.1): ~7x cheaper.
- Cross-ref prompting.txt:42: "even at its lowest effort setting it read values off dense charts more accurately than Claude Opus 5 did at its highest, using a small fraction of the output tokens." prompting.txt:165: "The model uses these tools more effectively at higher effort levels. Without tools, raising effort improves its reading of technical drawings but does little for charts." Also recommends higher-res images + container with PIL/OpenCV or a crop tool.

### 8.13.2 BenchCAD Vision2Code (pp. 202-205)
- 17,900 execution-verified CadQuery programs, 106 part families; Vision2Code = generate CadQuery code from multi-view renders. 1,000-file random subset (historically within 0.01 voxel IoU of full set). Voxel IoU, mean of 5 runs, max effort. With tools = container + image files + std libs + crop tool.
- METHOD CORRECTION: prior implementation used 128x128 px pre-rendered views from HF; reference GitHub impl renders 256x256 per view (4x resolution). Prior Claude models scored "significantly lower" relative to others because of this. They reproduced GPT-5.6 Sol no-tools only at 256px.
- Headline (Fig 8.13.2.A):
  | model | no tools | with tools | prior (low-res) |
  |---|---|---|---|
  | Opus 5.5 | 0.730 | 0.962 | — |
  | Fable 5.1 | 0.606 | 0.926 | 0.437 / 0.843 |
  | Opus 5 | 0.497 | 0.899 | 0.366 / 0.821 |
  | Sonnet 5 | 0.322 | 0.519 | — |
  | GPT-5.6 Sol (OpenAI-reported) | 0.706 | 0.834 | |
  | GPT-6 Astra (OpenAI-reported) | — | 0.959 | |
- Text: "Claude's performance on this evaluation scales substantially with test-time compute, particularly when the models are equipped with tools that enable visual verification of intermediate outputs." Opus 5.5 "nearly achieves a perfect voxel IoU".
- Fig 8.13.2.B (with tools, IoU vs cost/task log x, unlabelled effort points), approx.:
  - Opus 5.5: $0.009 0.397 · $0.025 0.526 · $0.06 0.565 · $0.40 0.759 · $6.5 0.962
  - Fable 5.1: $0.025 0.383 · $0.10 0.447 · $0.55 0.549 · $3.5 0.779 · $5 0.831 · $11 0.926
  - Opus 5: $0.02 0.304 · $0.65 0.473 · $3.5 0.774 · $6.5 0.868 · $10 0.899
  - Sonnet 5: $0.004 0.200 · $0.22 0.244 · $1.3 0.385 · $2.3 0.448 · $7 0.519
  - => steep, near-linear-in-log-cost scaling: Opus 5.5's last step (~0.76 -> 0.96) costs ~16x more per task (~$0.40 -> ~$6.5). Unlike Chartography, max effort pays off here. Opus 5.5 max (~$6.5, 0.962) beats Fable 5.1 max (~$11, 0.926).
- Resolution sensitivity is itself a fact: 4x pixel resolution moved Fable 5.1 no-tools 0.437 -> 0.606 and Opus 5 0.366 -> 0.497.

### 8.13.3 OSWorld 2.0 (pp. 205-208)
- 108 long-horizon computer-use tasks, live Ubuntu VM via screenshots + mouse/keyboard; weighted checkpoints. Metrics: partial score, strict pass rate; pass@1 over 5 runs. 1080p, max 500 action steps, max effort. Model grader where needed: Claude Opus 4.8.
- Harness changes since Fable 5.1/Mythos 5.1 card: Sept 10, 2026 task files; agent now retains every screenshot and uses Claude API server-side context management, compacting once conversation exceeds 100k tokens. Supersedes earlier figures.
- Fig 8.13.3.A (max): Opus 5.5 81.8 partial / 48.7 strict; Fable 5.1 80.7 / 42.8; Opus 5 74.0 / 37.2.
- Fig 8.13.3.B price vs partial (API list prices incl. caching; one point per effort; "levels differ by model"), approx.:
  - Opus 5.5: $0.95 58.4 · $1.95 74.1 · $2.45 77.8 · $4.3 80.8 · $8.5 81.8
  - Fable 5.1: $4.3 66.7 · $5.5 74.0 · $7.0 76.1 · $9.2 78.7 · $12.5 80.7
  - Opus 5: $5.0 65.7 · $6.3 70.1 · $8.5 74.3 · $10.5 74.5 · $11.5 74.0 (max below xhigh-ish point)
- Fig 8.13.3.C price vs strict, approx.:
  - Opus 5.5: 21.7 · 35.7 · 40.4 · 45.8 · 48.7 (same x as above)
  - Fable 5.1: 27.2 · 34.8 · 37.4 · 41.1 · 42.8
  - Opus 5: 30.4 · 33.7 · 37.8 · 39.3 · 37.2
- => Opus 5.5 4th point (~$4.3) matches Fable 5.1 max partial (80.8 vs 80.7) at ~1/3 the $/task and beats it on strict (45.8 vs 42.8). Opus 5.5 at ~$2.45 (77.8) already > Opus 5 max (74.0 at ~$11.5). Opus 5.5 lowest point (~$0.95) is weak (58.4 / 21.7) — steep low end: strict pass collapses at low effort.
- Cross-ref prompting.txt:42: "at its default effort it matched the success rate that Claude Opus 5 reached only at a much higher effort setting." (default effort per announce = medium).
- whatsnew.txt: on Claude API/Google Cloud Opus 5.5 accepts only computer_toolset_20260801 (computer_20251124 -> 400).

## §8.14 Real-world professional tasks

### 8.14.1 OfficeQA (p. 208) — Opus 5.5 LOSES to Fable 5.1
- Databricks; U.S. Treasury Bulletin corpus; agentic, extracted text in sandbox + code execution. Pro = 133-question harder subset.
- max effort, mean of 5 runs: Opus 5.5 78.9 / Pro 67.7; Opus 5 78.1 / 66.9; Fable 5.1 80.2 / 69.0. No per-effort data.

### 8.14.2 Legal Agent Benchmark (Harvey LAB) (p. 209)
- 2,010+ tasks, 27 practice areas; closed document universe; LLM judge, all-criteria pass (criteria per task min 23, median 56, max 194). Held-out 120 problems run by Artificial Analysis.
- Opus 5.5 max: 8.3% all-pass, 91.2% mean criterion-pass. NO comparison numbers for other models printed in this section (text says earlier-model scores are AA-measured, but none shown).

### 8.14.3 GDPval-AA v2.1 (p. 209)
- 220 tasks, 44 occupations, 9 industries; shell + web browsing; Elo from blind pairwise comparisons, anchored DeepSeek V4.1 Flash (max) = 1600. Run by Artificial Analysis.
- Opus 5.5 max 1846, xhigh 1820 (top two); Fable 5.1 max 1735; Opus 5 max 1708. "xhigh achieves similar performance as max while using about 51% fewer output tokens."
- Cross-ref announce.txt:248/270: "At default effort (medium), Opus 5.5 beats GPT-6 Astra at max effort for about a fifth of the cost per task." Table: GPT-6 Astra 1542?, other 1588 (column headers not in this chunk — see announce chunk).

### 8.14.4 AA-Briefcase v1.1 (p. 210)
- Long-horizon knowledge work: multi-week projects, many linked tasks, thousands of input files; grading = rubric + pairwise judging by panel of frontier models (task success, analytical quality, presentation quality).
- Opus 5.5 max 1822, xhigh 1780, high 1705 (top three); Fable 5.1 max 1678; Opus 5 max 1673. Leads Fable 5.1 on both analytical-quality and presentation Elo. "xhigh achieves similar performance as max while using about 41% fewer output tokens." Note: Opus 5.5 at HIGH (1705) > Fable 5.1 max (1678) and Opus 5 max (1673).

### 8.14.5 Toolathlon Verified (pp. 210-211) — Opus 5.5 NOT best
- 108 tasks, >600 tools across 32 apps; execution-based checkers; trajectories ~20-27 assistant turns. Toolathlon-Verified final release (June 2026).
- Opus 5.5: 77.8% Pass@1; of 324 trials, 1 (0.3%) stopped by production safety classifiers, 6 (1.9%) halted by the harness's sandbox-escape monitor — all 7 counted failures.
- Table 8.14.5.A (max effort; Opus 5.5 and Fable 5.1 run with safety classifiers):
  | model | Pass@1 | Pass@3 | Pass^3 | avg turns |
  |---|---|---|---|---|
  | Opus 5.5 | 77.8 | 82.4 | 72.2 | 26.9 |
  | Fable 5.1 | 77.8 | 81.5 | 73.1 | 23.7 |
  | Opus 5 | 80.6 | 87.0 | 73.1 | 23.5 |
  | Mythos 5 | 79.3 | 86.1 | 73.1 | 19.8 |
  | Opus 4.8 | 79.9 | 88.0 | 71.3 | 20.4 |
  | Sonnet 5 | 74.7 | 84.3 | 65.7 | 24.5 |
- Opus 5.5 uses the MOST turns (26.9) and ranks below Opus 5 and Opus 4.8 on Pass@1 and Pass@3.
- Harness validated by re-running Sonnet 5 and Opus 4.8; internal figures ~3 pts above published leaderboard (71.6%, 76.2%) because leaderboard counts null attempts (8/324 Sonnet 5, 11/324 Opus 4.8) as failures.
- The 6 sandbox-escape-monitor halts are an alignment-relevant signal (unattended tool agent tripping an escape monitor ~1.9% of trials) — details not given here.

### 8.14.6 AutomationBench (pp. 211-212)
- Zapier; simulated company, dozens of REST endpoints across 47 apps; must discover endpoints via search, obey layered policy docs, avoid planted distractions; deterministic assertions, pass/fail. Private held-out leaderboard.
- max: Opus 5.5 40.0%, Fable 5.1 31.4%, Opus 5 26.9%.
- Fig 8.14.6.A (labelled effort points; approx. cost/score). Opus 5.5 cost = Anthropic calc from Zapier token counts at list prices w/ caching; others from Zapier leaderboard 1.0.6:
  - Opus 5.5: Low $0.50 23.3 · Medium $0.64 28.6 · High $0.70 32.0 · Extra high $0.86 34.4 · Max $1.37 40.0
  - Opus 5: Low $0.75 20.3 · Medium $0.89 23.9 · High $1.03 20.5 · Extra high $1.15 25.2 · Max $1.27 26.9
  - GPT-5.6 Sol: Low $0.42 11.7 · Medium $0.57 19.6 · High $0.64 24.7 · Extra high $0.75 26.4 · Max $0.91 28.7
  - GPT-6 Astra: Low $1.08 30.3 · Medium $1.28 34.1 · High $1.46 37.1 · Extra high $1.53 38.9 · Max $1.77 41.4
  - Fable 5.1 not plotted (text only: 31.4% at max).
- => GPT-6 Astra max (~41.4) edges Opus 5.5 max (40.0) at ~30% more cost. Opus 5.5 medium (28.6 @ ~$0.64) > Opus 5 max (26.9 @ ~$1.27). Opus 5.5 high (32.0) > Fable 5.1 max (31.4). Opus 5.5 max costs ~60% more than xhigh for +5.6 pts — max genuinely buys accuracy here. Opus 5 is non-monotone (High < Medium).

## §8.15 Healthcare (pp. 212-214)
- HealthBench: 5,000 conversations, 48,000+ rubric items. HealthBench Professional: 525 physician-authored conversations. LLM-judge = Claude Opus 4.8. Max effort, adaptive thinking, 5 trials, no tools/custom system prompts. "Claude Opus 5.5 was run with safety classifiers enabled and a refusal fallback to Claude Opus 5."
- HealthBench raw / length-adjusted: Sonnet 5 59.2/58.7; Opus 5 67.1/57.8; Fable 5.1 66.7/60.0; Opus 5.5 68.1/60.6. (Length adj = GPT-5.5 System Card method.)
- HealthBench Professional raw / length-adj: Sonnet 5 62.4/57.8; Opus 5 73.4/59.8; Fable 5.1 74.2/62.1; Opus 5.5 77.1/65.6.
- Length-adjustment penalty sizes: Opus 5 loses 9.3 (HB) / 13.6 (HBP); Opus 5.5 7.5 / 11.5; Fable 5.1 6.7 / 12.1; Sonnet 5 0.5 / 4.6 — i.e., Opus-class models are verbose; Sonnet 5 barely penalised.
- Safeguard routing fact: refusal fallback target = Claude Opus 5.

## §8.16 Multilingual (pp. 214-216)
- GMMLU (42 languages, single trial, max): Opus 5.5 94.3; Fable 5.1 94.0; Opus 5 92.5; Sonnet 5 89.2.
- MILU (11 languages, 5 trials, max): Opus 5.5 93.1; Fable 5.1 93.0; Opus 5 92.1; Sonnet 5 89.3.
- Essentially saturated; Opus 5.5 ~= Fable 5.1.

## §8.17 Life sciences (pp. 216-221) — Fable 5.1 NOT reported; comparators Mythos 5.1, Opus 5, Sonnet 5, GPT-6 Astra (max reasoning; OpenAI-declined attempts excluded)
- Defaults: 5 attempts/problem at max effort (1 for sequence generation and biomedical image analysis; 3 for library ranking; 5 runs/target for binder design).
- BioMysteryBench (bash, file editor, fixed packages, allow-listed domains): Human Solvable (73): Opus 5.5 89.3, Opus 5 91.4, Mythos 5.1 90.3, Sonnet 5 84.9 (chart GPT-6 Astra 0.89). Human Difficult (17): Opus 5 51.8, Opus 5.5 50.0, Mythos 5.1 44.1, Sonnet 5 39.4 (chart GPT-6 Astra 0.32). => Opus 5 >= Opus 5.5 on both.
- LatchBio: SpatialBench Verified (115): Mythos 5.1 77.6, Opus 5.5 72.0, Opus 5 71.7, Sonnet 5 68.9. SingleCellBench (195): Mythos 5.1 61.8, Opus 5.5 61.2, Opus 5 60.5, Sonnet 5 56.5.
- Morphology-to-molecule (Axiom Bio; closed sandbox, no network): Opus 5.5 34.0, Mythos 5.1 25.8, Opus 5 25.0, Sonnet 5 6.8, GPT-6 Astra 22.8.
- Medicinal chemistry (504 ADME Qs, no tools): Opus 5.5 63.5, Opus 5 57.9, Mythos 5.1 57.7, GPT-6 Astra 56.6, Sonnet 5 41.3.
- Protein Sequence Generation (336 briefs, no tools): Opus 5.5 60.2, Mythos 5.1 46.0, Opus 5 42.4, Sonnet 5 20.2.
- Library Ranking (83 problems, no tools, chance-normalized AP): Mythos 5.1 56.9, Opus 5.5 56.0, Opus 5 53.5, Sonnet 5 44.0 (not comparable to Mythos 5.1 card; revised set/grader).
- De novo binder design (15 targets, 24h wall-clock budget each, GPU sandbox, no internet, 30 binders; 5 runs/target): Opus 5.5 82.6, Mythos 5.1 79.1, Opus 5 78.9, Sonnet 5 72.6. Opus 5.5 higher than Opus 5 and Sonnet 5 on all 15 targets, than Mythos 5.1 on 14/15. (Long-horizon autonomous 24h run — the only 24h-budget autonomy result in this chunk.)
- Biomedical image analysis (91 cases/31 tasks; classical packages, no pretrained models/internet; normalized baseline 0 / best published 100): GPT-6 Astra 77.5, Opus 5.5 71.4, Mythos 5.1 67.1, Opus 5 61.0, Sonnet 5 42.3.
- Protocols (bash, editor, web search): Troubleshooting (206): Opus 5.5 73.7, Mythos 5.1 70.2, Opus 5 68.9, GPT-6 Astra 66.0, Sonnet 5 49.9 (Opus 5/Sonnet 5 re-run w/o external network). Understanding V2 (119, Benchling): Opus 5 71.8, Mythos 5.1 69.6, Opus 5.5 69.0, GPT-6 Astra 61.9, Sonnet 5 58.9.
- Fig 8.17.8.A summarises all (values match text to 2 dp).

## Cross-cutting observations (INFERENCE, mine)
- Per-effort curves exist in this chunk ONLY for Chartography (no tools/with tools), BenchCAD (with tools), OSWorld 2.0, AutomationBench (only one with labelled effort points), plus xhigh/high Elo points for GDPval-AA and AA-Briefcase. Everything else is max-only.
- Pattern: visual-reading tasks (Chartography) saturate early — max is waste; generative/verification-heavy tasks (BenchCAD, AutomationBench) keep scaling to max; knowledge-work Elo: xhigh ~= max at 41-51% fewer output tokens.
- Where Opus 5.5 loses: OfficeQA (Fable 5.1), Toolathlon (Opus 5, Opus 4.8, Mythos 5; ties Fable 5.1), AutomationBench (GPT-6 Astra), BioMysteryBench + Protocols Understanding (Opus 5), SpatialBench/Library ranking (Mythos 5.1), biomedical image analysis (GPT-6 Astra).
- Opus 5.5 takes more turns on Toolathlon (26.9 vs 23.5 Opus 5) — potentially more quota per task on tool-heavy agent loops.
