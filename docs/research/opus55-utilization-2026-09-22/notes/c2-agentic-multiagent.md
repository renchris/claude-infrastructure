# c2-agentic-multiagent — Claude Opus 5.5 System Card pp. 183-199 (§8.10 long context, §8.11 agentic search, §8.12 multi-agent)

Source: /tmp/opus55-src/syscard.pdf (PDF page == printed page). All charts viewed visually. Values marked "approx." are read off log-scale axes (x positions); y-values printed as data labels are exact.

Context from outside the chunk (p.174, Table 8.1.A note): "Unless otherwise noted, all Claude Opus 5.5 results use the following standard configuration: adaptive thinking at max effort, default sampling settings ... averaged over five trials." -> The ProgramBench single-agent (8.10.1) number and the large-team results do not state an effort, so they presumably use the default max (not stated in-section). Multi-agent DRACO explicitly states max (p.193).

## p.183 — Fig 8.9.B ArXivMath (Aug 2026) with tools (tail of §8.9, belongs to another chunk; recorded for completeness)
Cost axis = published cost per task, perfect caching, tokens only (log). Evaluated without safeguards classifiers.
- Opus 5.5: Low 28.9% (~$0.08) · Med 67.1% (~$0.45) · High 79.4% (~$0.9) · Xhigh 94.7% (~$2.1) · Max 96.9% (~$4.3)
- Fable 5.1: Low 61.4% (~$2) · Med 75.9% (~$4) · High 87.7% (~$6.5) · Xhigh 93.0% (~$10) · Max 92.1% (~$13)  [Fable max < xhigh]
- Opus 5: Low 53.1% (~$1.05) · Med 78.1% (~$2.8) · High 88.6% (~$5) · Xhigh 90.4% (~$7.7) · Max 90.4% (~$10)
- Note Opus 5.5 LOW (28.9%) is far below Opus 5 low / Fable low — steep low-effort cliff on math.

## §8.10.1 ProgramBench (pp.183-184) — long-context agentic coding
- 200 program-reconstruction tasks: given only binary + docs, rebuild codebase reproducing behavior; no internet, no decompilation tools. Tasks range jq/ripgrep to FFmpeg/SQLite/PHP interpreter. >247,000 execution-based behavioral tests generated via agent-driven fuzzing.
- 34 tasks excluded (reference binary <0.9 on hidden tests), leaving 166; scored only against tests the reference binary passes.
- Harness: mini-swe-agent (upstream), WITHOUT the six-hour time limit. 1M token budget (per p.189).
- Results: Opus 5.5 91.2% · Fable 5.1 87.6% · Opus 5 85.4%. No effort level stated; no per-effort data; no cost/tokens.
- "Opus 5.5 episodes cover a range of context lengths up to the full 1M token window" — Anthropic calls it "a strong measure of long-context coding performance". No context-length-bucketed breakdown/degradation curve given.

## §8.11.1 Humanity's Last Exam (pp.184-186)
- 2,500 multimodal expert questions. Two configs: no tools; with web search, web fetch, programmatic tool calling, code execution.
- "thinking was set to auto"; total tokens across contexts capped at 1M; NO context compaction. Grader: Claude Opus 4.6.
- Contamination guard: blocklist HLE-discussing sources for searcher+fetcher (App. 9.2); text-rule screen of every correct transcript; Claude Opus 5 reviews flagged transcripts; confirmed cheating re-graded incorrect.
- Fig 8.11.1.A (with tools) — cost/task, perfect cache, web search fees excluded:
  - Opus 5.5: Low 57.4% (~$0.075) · Med 63.0% (~$0.18) · High 63.9% (~$0.28) · Xhigh 66.4% (~$0.65) · Max 67.7% (~$2.1)
  - Fable 5.1: Low 60.2% (~$0.53) · Med 62.4% (~$0.70) · High 63.1% (~$1.2) · Xhigh 65.2% (~$2.3) · Max 65.6% (~$3.3)
  - Opus 5: Low 55.0% (~$0.28) · Med 60.6% (~$0.65) · High 62.5% (~$1.1) · Xhigh 63.4% (~$1.7) · Max 63.6% (~$2.4)
  - Observations: Opus 5.5 Med (63.0%, ~$0.18) ≈ Fable High (63.1%, ~$1.2) at ~1/6 the cost (but < Opus 5 Max 63.6%); Opus 5.5 High 63.9% > Opus 5 Max 63.6% at ~1/8 cost. Opus 5.5 Xhigh 66.4% > Fable Max 65.6%. Fable LOW (60.2%) beats Opus 5.5 LOW (57.4%) but at ~7x cost.
- Fig 8.11.1.B (no tools):
  - Opus 5.5: Low 52.9% (~$0.04) · Med 59.0% (~$0.11) · High 59.6% (~$0.14) · Xhigh 62.8% (~$0.32) · Max 64.4% (~$0.98)
  - Fable 5.1: Low 53.2% (~$0.30) · Med 55.9% (~$0.45) · High 58.0% (~$0.75) · Xhigh 60.4% (~$1.5) · Max 60.9% (~$2.3)
  - Opus 5: Low 47.4% (~$0.13) · Med 53.9% (~$0.31) · High 55.5% (~$0.50) · Xhigh 56.5% (~$0.80) · Max 56.6% (~$1.05)
  - Observations: Fable Low 53.2% marginally > Opus 5.5 Low 52.9% (7x cost). Opus 5.5 Med 59.0% > Opus 5 Max 56.6% and > Fable High 58.0%.

## §8.11.2 DRACO (pp.186-187) — Perplexity deep research, 100 tasks, rubric-graded (factual accuracy, breadth/depth, presentation, citation)
- Tools: web search, web fetch, programmatic tool calling, code execution; 980k token task budget.
- Judge: Claude Opus 4.6 (paper used Gemini 3 Pro, no longer available); binary MET/UNMET rubrics, normalized per paper §4.2; 5 grading runs per response, mean; judge prompt from paper App. C.5. Paper App. A: judge choice shifts absolute scores 10-25 points while preserving ordering -> not comparable to paper headline numbers.
- Own harness (no App. C.4 system prompt); model writes final report to a file; only that file is graded (not full transcript).
- Fig 8.11.2.A (cost/task, perfect cache, search fees excluded):
  - Opus 5.5: Low 72.5% (~$0.27) · Med 83.9% (~$2.1) · High 85.0% (~$3.6) · Xhigh 86.7% (~$9) · Max 87.4% (~$16)
  - Opus 5: Low 83.3% (~$2.0) · Med 85.6% (~$4.3) · High 87.3% (~$8.5) · Xhigh 87.4% (~$13) · Max 88.3% (~$16)
  - Fable 5.1: Low 84.2% (~$4.3) · Med 85.7% (~$6.5) · High 86.5% (~$9) · Xhigh 86.9% (~$14) · Max 87.7% (~$17.5)
  - Observations: DRACO is a case where Opus 5.5 does NOT lead. Opus 5 Max 88.3% is the top point; Fable Max 87.7% also > Opus 5.5 Max 87.4%. Opus 5 High (87.3%, ~$8.5) > Opus 5.5 Xhigh (86.7%, ~$9) at similar cost. Opus 5.5 is cost-competitive only at Med/High (83.9-85.0%, $2-3.6); Opus 5.5 Low collapses to 72.5%. Curves nearly overlap in $2-$16 region.

## §8.11.3 WANDR (pp.187-188) — Perplexity wide research, 500 tasks, tens-to-hundreds of entities, structured records with citations
- Same tools, 980k token task budget. Judge has the same web-fetch tool, re-fetches cited URLs; judge = Claude Opus 4.6 (Perplexity uses GPT-5.4). Offline frozen index (Perplexity uses live web); prompts differ; not comparable to competitor numbers.
- Metric: soft F1 (precision = verified share; recall = completed share); partial credit; malformed entity rows dropped, not task-failed.
- Fig 8.11.3.A:
  - Opus 5.5: Low 31.2% (~$1.2) · Med 62.8% (~$11) · High 67.3% (~$17) · Xhigh 71.3% (~$29) · Max 72.3% (~$38)
  - Fable 5.1: Low 63.3% (~$23) · Med 64.5% (~$26) · High 66.7% (~$33) · Xhigh 67.7% (~$43) · Max 68.7% (~$50)
  - Opus 5: Low 50.5% (~$11) · Med 58.1% (~$22) · High 64.6% (~$42) · Xhigh 67.0% (~$55) · Max 67.1% (~$63)
  - Observations: Opus 5.5 Low collapses (31.2%) — the cheapest point is ~10x cheaper but half the score. Fable Low 63.3% > Opus 5.5 Med 62.8% (but ~2x cost). Opus 5.5 High 67.3% ≈ Opus 5 Xhigh/Max (67.0/67.1%) at ~1/3 cost and > Fable High. Opus 5.5 Xhigh/Max lead outright. Wide-research tasks are expensive: $11-$63/task across the frontier.

## §8.12 Multi-agent (pp.189-199)

### §8.12.1 Multi-agent ProgramBench (pp.189-191)
- 166 "golden" tasks (ref binary ≥0.9); list differs from §8.10.1 in four tasks.
- Configs: (a) single agent, 20M token limit, WITH context compaction (vs 1M in §8.10.1) so "larger token expenditure of multi-agent teams does not act as a confounder"; (b) fixed five-agent team, 4M token limit per agent; (c) async subagents, 1M token limit per agent. (Token limits from figure legends.)
- Single-agent baseline here uses same task tools/grading as MA configs, NOT §8.10.1 harness — not comparable to 91.2%.
- Graded at intermediate snapshots -> cumulative curves. Run on "an alternate, broadly comparable snapshot of Opus 5.5". No effort level stated for this section.
- Fig 8.12.1.A score vs derived latency (log s): 5-agent team reaches 0.6 at ~2,200 s; async ~3,500 s (approx.); single ~6,000 s (approx.). Text: "the five-agent team achieves a 2.7x latency improvement over the single agent to reach the same score of 0.6." Async "largely between the two". All three converge ~0.95-0.97 at long latency (single agent's tail extends to ~500,000+ s; approx.).
- Fig 8.12.1.B score vs tokens per task (log): single agent is most TOKEN-efficient above ~0.3M tokens: reaches ~0.6 at ~0.55M, ~0.85 at ~1M (approx.); 5-agent team ~0.6 at ~1.1M, ~0.85 at ~2M (approx.); async subagents ~0.6 at ~2M, ~0.85 at ~6-8M (approx.). Async curve is highest at very small budgets (<~0.3M, ~0.2 score at ~0.2M; approx.). All converge ~0.95-0.97 by ~20M.
- Text: "when latency matters, five-agent teams and async subagents can productively absorb additional token budget by distributing work across agents, allowing them to reach a given score faster at a higher cost."

### §8.12.2 Multi-agent DRACO (pp.191-193)
- Short tasks: single-task latencies 13 to 71 minutes. "On shorter problems like these, we find that multi-agent teams can take longer than their single-agent counterparts to finish a task due to their coordination overhead."
- Latency incentives: (1) general latency pressure = instruction on importance of time efficiency + cumulative elapsed time shown after every step; (2) latency budget = fixed window displayed beside elapsed time (no instruction). Budgets = single-agent latency per task x 1.0, 0.75, 0.5, 0.25.
- Same token limits (single 20M; 5-team 4M/agent; async 1M/agent). "All of these runs are at max effort." Each point mean of two runs; latency = mean derived latency.
- Fig 8.12.2.A (approx. positions; y = DRACO score 0-100, x = seconds log):
  - Single agent: standard ~87.2 @ ~2,300 s · pressure ~86.0 @ ~1,400 s · 1.0x ~85.5 @ ~1,150 s · 0.75x ~85.3 @ ~950 s · 0.5x ~83.3 @ ~720 s · 0.25x ~79.8 @ ~360 s
  - Five-agent team: standard ~89.7 @ ~2,700 s · pressure ~88.8 @ ~1,500 s · 1.0x ~89.1 @ ~1,380 s · 0.75x ~88.5 @ ~1,100 s · 0.5x ~88.0 @ ~800 s · 0.25x ~84.6 @ ~400 s
  - Async subagents: standard ~89.4 @ ~3,400 s · pressure ~88.5 @ ~1,800 s · 1.0x ~88.1 @ ~1,300 s · 0.75x ~87.5 @ ~1,020 s · 0.5x ~86.3 @ ~730 s · 0.25x ~80.1 @ ~370 s
- Text: "they dominate the score–latency Pareto frontier at increasingly tight time budgets. At a latency budget of 0.5x, the five-agent team is capable of more than matching single-agent performance, with a roughly 2.8x speedup." Latency pressure "drives both multi-agent teams to complete the task earlier than the unprompted single agent."
- Effort vs budget: "reducing effort and tightening a latency budget can both bring down task latency, [but] ... The former results in less work overall, whereas the latter preserves more of the work at a given latency by sustaining higher effective parallelism. This is true even among fixed teams, which exhibit less idleness."
- Async collapse: "At tighter latency budgets, the coordination and latency overhead of spawning new subagents becomes large enough that the lead spawns them at a much lower rate and prefers to act as a single agent." Pre-spawned 5-team still highly parallel at same latency (0.25x: async ~80.1 ≈ single ~79.8; team ~84.6).
- No token/cost numbers for multi-agent DRACO.

### §8.12.3 Large agent teams (pp.193-198)
- New eval set: tasks supporting >100 concurrent agents; used "to measure and improve both the capability and the alignment of agents operating in large teams."
- Team sizes 1, 10, 30, 100; 24 hours each; three attempts averaged. "Slightly different model version than the released one; performance is comparable." Effort not stated.
- Tasks: knowledge base (read company docs, write indexed notes; score = reader-with-notes QA accuracy on held-out questions); Lean formalization (prove challenging theorem from fixed statements; 49 formal theorem statements, weighted milestones).
- "Opus 5.5 outperforms both models at every team size in both tasks. For all models, scores generally rise with team size, with diminishing returns."
- Fig 8.12.3.A Knowledge base (24h best score): Opus 5.5 0.53 / 0.70 / 0.71 / 0.74; Fable 5.1 0.53 / 0.66 / 0.69 / 0.68; Opus 5 0.45 / 0.64 / 0.65 / 0.68 (sizes 1/10/30/100). Note: at size 1 Opus 5.5 and Fable both label 0.53 (Opus 5.5 plotted marginally higher); Fable DECLINES 30->100 (0.69->0.68).
- Fig 8.12.3.B Lean (24h): Opus 5.5 0.39 / 0.66 / 0.66 / 0.68; Opus 5 0.19 / 0.44 / 0.55 / 0.58; Fable 5.1 0.16 / 0.33 / 0.45 / 0.53. Fable is WORST on Lean at all sizes (below Opus 5). Opus 5.5 single agent (0.39) beats Fable 10-agent team (0.33) and nearly Opus 5 10-agent (0.44).
- Fig 8.12.3.C Knowledge base Opus 5.5 over time (2h / 6h / 24h): size1 0.37/0.47/0.53 · size10 0.53/0.64/0.71 · size30 0.66/0.68/0.71 · size100 0.69/0.71/0.74. (24h @10 = 0.71 here vs 0.70 in Fig A — label discrepancy.)
- Fig 8.12.3.D Lean Opus 5.5 over time: size1 0.07/0.14/0.39 · size10 0.15/0.42/0.66 · size30 0.34/0.58/0.66 · size100 0.44/0.64/0.68.
- Text: "Larger teams reach a given level of performance much earlier, so scaling up the team substantially reduces the time needed to complete the task even when the 24-hour scores are close."
- Harness: fixed team; one lead + N−1 helpers start together with full task; up to 24h; one shared Linux machine; no network; each agent has shell, file editor, Send Message, Wait for Message; any agent can message any other; one shared Git repo (graded). "The model is instructed to use the terminal command to check for the time and plan accordingly."
- Emergent structure (100-agent teams, Fig 8.12.3.E): Lean team two-tier — lead appointed a dozen (12) sub-leads; sub-leads hand out work to their helper groups and report back. Knowledge base team flat — lead divided records at start; helpers owned parts; little inter-helper communication; no sub-leads. Sub-lead defined as helper that is main sender of messages to ≥3 other helpers.

### §8.12.4 Harnesses (pp.198-199)
- Fixed team: peers, identical tools, all see full task. DRACO: designated lead; run ends when lead finishes; report as it stands is graded. ProgramBench: no lead; peers get same prompt; shared repo main branch graded; ends when every agent finishes. Work division left to agents. Send Message (delivered after recipient's next tool result) + Wait for Message (blocks sampling). ProgramBench: each agent its own checkout, share via Git. DRACO: shared container filesystem.
- Async subagents: lead spawns asynchronous long-lived subagents at will, retains task tools; spawn returns immediately. Subagent sees ONLY lead's instructions, not original task. Subagents message lead and other working subagents. Final response delivered to lead as a message; subagent then idles until lead wakes it. Subagents: task tools + Send Message; lead additionally: Wait for Message, create/terminate/status (working, idle, queued, terminated). No cap on number of subagents.

### §8.12.5 Methodology (p.199)
- Token usage: every token entering an agent's context window (input+output) counted once per window, not per request; summed over all agents.
- Latency = derived: agent input/output token counts divided by fixed reference prefill and decode rates + measured tool execution time. Clocks carried across hand-offs (spawned agent starts at spawner's clock; receiving a message advances clock to sender's if later). ProgramBench: longest agent trajectory (max clock); DRACO: lead's final clock. Isolates harness latency from serving variance; tool time as measured.
- Implication: reported speedups are NOT raw wall-clock; they exclude queuing/rate limits — and a multi-account fleet's real throughput limits (quota, rate limits) are not modelled.

## Linked-source cross-reference (prompting.txt, "Time signals for multi-agent harnesses") — belongs to another chunk; noted only
- Recommends harness append "elapsed 340s / 1200s"; set budget somewhat above desired; if unpredictable, show elapsed alone + sentence "Time matters here: do not spend time that can be avoided, and the earlier a correct result is obtained, the better." Budget advisory — keep your own timeout; under time pressure model may search/verify a little less.

## Absent / not answered by this chunk
- No effort level stated for ProgramBench (single), multi-agent ProgramBench, or large-team runs (only DRACO multi-agent says max; default per Table 8.1.A is max).
- No per-effort data for any multi-agent configuration; no low/medium-effort teams.
- No mixed-model teams (e.g., Opus 5.5 lead + Sonnet/Haiku workers) or mixed-effort teams (lead high, workers low). All teams homogeneous per model.
- No Sonnet 5 / Haiku 4.5 / Opus 4.8 in any of these charts.
- No cost/token totals for multi-agent DRACO or large teams; no $ for ProgramBench.
- No context-length-bucketed degradation curve for ProgramBench (only claim that episodes span up to 1M).
- No per-effort ProgramBench, no ProgramBench cost.
- No team sizes between 1 and 5 or 5 and 10 for small teams; small-team results only at N=5 (fixed) and uncapped async.
- No quality/alignment incident data (reward hacking, overeager actions, conflicts between agents) reported for the large teams in this section, despite "measure and improve ... alignment".
- No real wall-clock (serving) latency; no rate-limit effects.
- No DRACO/WANDR breakdown by rubric category.
