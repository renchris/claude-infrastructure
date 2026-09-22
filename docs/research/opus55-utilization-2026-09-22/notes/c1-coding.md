# c1-coding — Claude Opus 5.5 System Card pp. 174-183 (§8.1-§8.10.1)
Source: /tmp/opus55-src/syscard.pdf (tier primary). Text via pdftotext; charts read visually (Read pages 176-177, 180-183). "approx." = read off chart, not printed.

## §8.1 Table 8.1.A (p.174) — Opus 5.5 / Opus 5 / Fable 5.1 / GPT-6 Astra
- SWE-bench Pro 89.9 / 79.2 / 81.2 / –
- SWE-bench Multilingual 93.9 / 89.5 / 89.1 / –
- SWE-bench Multimodal 61.4 / 59.4 / 54.7 / –
- FrontierCode v1.1 (Main) 54.4 / 48.0 / 50.3 / 53.3   (table = max effort for Claude; best-effort figures differ, see §8.4)
- Terminal-Bench 4.0 66.4 / 52.3 / 55.8 / 57.9   (Opus 5.5 at xhigh)
- Terminal-Bench-Science 0.1 58.7 / 29.0 / 52.6 / 64.6   (Astra wins)
- HLE no tools 64.4 / 56.6 / 60.9 / –; with tools 67.7 / 63.6 / 65.6 / 57.2
- OSWorld 2.0 partial/strict 81.8/48.7 / 74.0/37.2 / 80.7/42.8 / –
- HealthBench Professional 65.6 / 59.8 / 62.1 / 63.4
- GDPval-AA v2.1 1846 / 1708 / 1735 / 1542
- AA-Briefcase v1.1 1822 / 1673 / 1678 / 1569
- AutomationBench 40.0 / 26.9 / 31.4 / 41.4   (Astra wins)
Caption: standard config = adaptive thinking at max effort, default sampling, averaged over five trials; TB4.0 at xhigh; context windows eval-dependent, <=1M tokens; competitor figures from their published cards/leaderboards.

## §8.2 SWE-bench (p.175): avg of 5 trials. Pro 89.9% (large multi-file diffs); Multilingual 93.9% (300 problems, 9 languages); Multimodal 61.4% (screenshots/mockups). No per-effort data, no tokens/cost.

## §8.3 DeepSWE v1.1 (p.175): 113 long-horizon SWE tasks, written from scratch. Opus 5.5 74.2% avg over 5 trials. NO comparators, no effort, no tokens.

## §8.4 FrontierCode v1.1 (pp.175-177): 150 tasks by Cognition from real PRs; autonomous, containerized, internet access, no human intervention, no timeout info. Graded on blocking functional criteria (held-out unit tests, scope + performance blockers) + weighted rubric (model-graded test coverage, prohibited patterns). mean@5.
- Note: performance DECLINES above medium effort for Opus 5.5 (grading penalizes out-of-scope changes even if helpful).
- Best-effort ranking Main: Opus 5.5 54.6 (medium) > Fable 5 53.5 > Opus 5 53.4 > GPT-6 Astra 53.3 > Fable 5.1 52.8.
- Extended: Opus 5.5 65.3 (medium) > Fable 5 64.9 > GPT-6 Astra 64.5 > Opus 5 63.6 = Fable 5.1 63.6.
- At max: Opus 5.5 54.4 Main, 63.6 Extended.
- Harness: Cognition ran all; Claude models in Claude Code, GPT in Codex CLI. Only output tokens reported (no cost). No error bars.
Fig 8.4.A Main (approx., x = avg output tokens/task):
- Opus 5.5: low 47.3 @~9k; medium 54.6 @~17.5k; high ~54.0 @~26k; xhigh ~51.4 @~60k; max 54.4 @~155k
- Opus 5: low ~42 @~23k; medium ~53.4 @~33k; high ~48 @~58k; xhigh ~43.7 @~62k; max ~48 @~100k
- Fable 5.1: low ~52.8 @~19.5k; medium ~51 @~26k; high ~50.4 @~38k; xhigh ~48.8 @~62k; max ~50.3 @~95k
- Fable 5: low ~48 @~23k; medium ~49.8 @~33k; high ~52.7 @~43k; xhigh ~53.5 @~58k; max ~51.6 @~75k
- GPT-6 Astra: low ~45.3 @~7k; none ~48.5 @~8k; medium ~48 @~11k; high ~51 @~15k; xhigh ~50.7 @~17k; max ~53.3 @~30k
- GPT-5.6 Sol: low ~35.4 @~12k; medium ~40 @~17k; high ~45.1 @~22k; xhigh ~46.8 @~25k; max ~47.5 @~32k
Fig 8.4.B Extended (approx.):
- Opus 5.5: low ~60.3 @~7k; medium 65.3 @~15k; high ~65.2 @~21k; xhigh ~63.5 @~52k; max 63.6 @~145k
- Opus 5: low ~55.7 @~18k; medium 63.6 @~28k; high ~58.4 @~45k; xhigh ~56.9 @~55k; max ~58.9 @~85k
- Fable 5.1: low ~63.2 @~15k; medium ~63.6 @~21k; high ~62.7 @~33k; xhigh ~61.4 @~55k; max ~62.0 @~78k
- Fable 5: low ~60.8 @~19k; medium ~62.8 @~27k; high ~64.3 @~36k; xhigh 64.9 @~50k; max ~63.6 @~65k
- GPT-6 Astra: low ~57.4 @~6k; none ~60.8 @~7k; medium ~60.3 @~9.5k; high ~63.1 @~12.5k; xhigh ~62.1 @~15k; max 64.5 @~27k
- GPT-5.6 Sol: low 50 @~10k; medium ~54.7 @~15k; high ~58.7 @~19k; xhigh ~60 @~22k; max ~60.6 @~28k
Observations: Opus 5.5 max uses ~9x the output tokens of its medium (~155k vs ~17.5k) for -0.2 pts Main. Fable 5.1 at LOW beats Opus 5.5 at LOW on both Main (~52.8 vs ~47.3) and Extended (~63.2 vs ~60.3), but at ~2x tokens. Fable 5 xhigh (~53.5) beats Opus 5.5 xhigh (~51.4) on Main.

## §8.5 Terminal-Bench 4.0 (pp.177-178): 66 tasks (comp bio, physics sim, CAD, formal proofs, GPU perf). 4.0 increased timeouts, adaptive RAM/CPU; reduced harness confounds (CLI memory, compaction strategy, container protocol).
- Opus 5.5 66.36% WITH SAFEGUARDS; flagged requests answered by a fallback model per default server-side fallback policy (2.5% of requests, affecting 10% of trials). Fallback model not named.
- Mythos 5.1 60.9; Fable 5.1 55.8; Opus 5 52.3. Trials: Opus 5.5 5/task (330), Mythos 10/task (660), Opus 5 15/task (990). SE ±2.6 (Opus 5.5), ±1.6-2 others.
- Claude Code --bare mode; Opus 5.5 at xhigh (max = 64.8%, within noise); comparison models at max.
- Public leaderboard Opus 5 51.8% (5 trials, Claude Code harness). GPT-6 Astra 57.9% at high (their max slightly lower than high).

## §8.6 Terminal-Bench-Science 0.1 (pp.178-179): 70 Stanford-led science tasks, hidden tests.
- Opus 5.5 58.7% with safeguards; fallback model answered 3.9% of requests, affecting 5% of trials. 10 trials/task (700).
- Fable 5.1 52.6 (700 trials); Opus 5 29.0 (12/task, 840); Fable 5 24.7 (700). SE clustered by task ±3.5-4.8 (±4.8 Opus 5.5).
- Claude Code --bare, max effort. Public leaderboard Opus 5 30.0, Fable 5 21.4 (3 trials). GPT-6 Astra 64.6 at max (beats Opus 5.5).

## §8.7 FrontierSWE v2 (p.179): Proximal, 34 ultra-long-horizon tasks (port Quantum Espresso Fortran->Rust, OpenGL renderer for flight sim, post-train an LLM). Strongest models work close to 20 HOURS per task; far from saturated. All models at max effort in Proximal's own harness, 5 trials/task, mean.
- GPT-6 Astra 65.5 > Opus 5.5 62.3 (2nd) > Fable 5.1 56.3 > GPT-5.6 Sol 32.2.

## §8.8 CursorBench 4.0 (pp.179-180): Cursor's benchmark from real Cursor usage, in Cursor's production agent harness; scores measured by Cursor. Opus 5.5 costs estimated by Anthropic from Cursor token counts at list prices: $4/M uncached input, $5/M 5-min cache write, $0.20/M cache read, $20/M output. Not comparable with earlier CursorBench versions.
- Opus 5.5: max 57.8; xhigh 56.0; high 56.0 (~$4/task); medium 52.5 (~$3/task); low approx. 43.7 @~$1.2 (chart).
- Fable 5.1 max 51.8 @ $17.28; Opus 5 max 46.6 @ $11.95; GPT-5.6 Sol max 41.7 @ $8.23.
- Opus 5.5 high: above every other model at ~1/4 cost of Fable 5.1 max. Medium: above Fable 5.1 max, ~1/4 cost of Opus 5 max.
Fig 8.8.A approx (score @ $/task):
- Opus 5.5: low ~43.7 @~$1.2; medium 52.5 @~$2.9; high 56.0 @~$4.1; xhigh 56.0 @~$7; max 57.8 @~$13
- Fable 5.1: low ~45.1 @~$5.5; medium ~46.8 @~$7; high ~49.2 @~$9.2; xhigh ~51.6 @~$12.5; max 51.8 @ $17.28
- Opus 5: low ~40.7 @~$4.8; medium ~43.4 @~$7; high ~44.7 @~$9.3; xhigh ~46.1 @~$11.6; max 46.6 @ $11.95
- GPT-5.6 Sol: low ~24.6 @~$0.85; medium ~31.1 @~$1.9; high ~35.7 @~$2.9; xhigh ~37.7 @~$4.6; max 41.7 @ $8.23
- Grok 4.6 (4 levels): low ~33.5 @~$2.2; medium ~36.1 @~$3.5; xhigh ~40.4 @~$5.2; high ~41.4 @~$6.2
Observation: only point where Fable 5.1 beats Opus 5.5 is low vs low (~45.1 vs ~43.7), at ~4.5x cost. Opus 5.5 low (~$1.2) ≈ Opus 5 medium (~43.4 @ ~$7).

## §8.9 ArXivMath (pp.180-183): MathArena, Aug 2026 release, 57 problems, 25 resolve/refute conjectures. 4 attempts/problem; evaluated internally WITHOUT safeguards classifiers.
- Max: Opus 5.5 91.2 no tools / 96.9 with tools (code sandbox, no internet); Fable 5.1 82.9 / 92.1; Opus 5 78.1 / 90.4.
- MathArena leaderboard (different setting, 2 attempts, LLM judge): GPT-6 Astra (max) 88.6; Fable 5.1 (high) 87.7.
Fig 8.9.A no tools (labels printed; cost approx.; x = "Published cost per task (USD, perfect caching, log scale; tokens only)"):
- Opus 5.5: low 32.0 @~$0.15; med 64.0 @~$0.52; high 73.2 @~$0.95; xhigh 86.0 @~$2.1; max 91.2 @~$3.8
- Opus 5: low 36.0 @~$0.68; med 67.5 @~$2.6; high 71.5 @~$4.5; xhigh 75.4 @~$5.8; max 78.1 @~$7.5
- Fable 5.1: low 50.9 @~$2.0; med 67.1 @~$3.8; high 73.2 @~$6; xhigh 82.5 @~$10.5; max 82.9 @~$12.5
Fig 8.9.B with tools:
- Opus 5.5: low 28.9 @~$0.08; med 67.1 @~$0.45; high 79.4 @~$0.95; xhigh 94.7 @~$2; max 96.9 @~$4.4
- Opus 5: low 53.1 @~$1.05; med 78.1 @~$2.9; high 88.6 @~$5; xhigh 90.4 @~$8; max 90.4 @~$9.8
- Fable 5.1: low 61.4 @~$2; med 75.9 @~$4; high 87.7 @~$7; xhigh 93.0 @~$10; max 92.1 @~$13
Observations: Opus 5.5 at low/medium LOSES to Opus 5 and Fable 5.1 at same effort (steep effort scaling), but is far cheaper per rung; Opus 5.5 xhigh (~$2) beats every other model's max. Fable 5.1 xhigh > its max with tools.

## §8.10.1 ProgramBench (p.183): 200 program-reconstruction tasks from binary + docs (jq, ripgrep ... FFmpeg, SQLite, PHP); no internet/decompilation; 247,000+ fuzzing tests. 34 flaky tasks excluded -> 166. mini-swe-agent harness, WITHOUT the six-hour time limit. Opus 5.5 91.2; Fable 5.1 87.6; Opus 5 85.4. Effort not stated (default = max per table caption convention).
