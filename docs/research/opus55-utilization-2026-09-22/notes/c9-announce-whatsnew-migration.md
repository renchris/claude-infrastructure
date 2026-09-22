# c9-announce-whatsnew-migration — notes

Sources: announce.txt/.html (anthropic.com/claude-opus-5-5, primary, dated September 22, 2026), whatsnew.txt (linked),
migration.txt (linked), models-overview.txt/.html (linked). Per-effort chart values below were read from the
chart DATA embedded in announce.html (Sanity `tuskchart*` blocks, fields series,x,y,label) — exact plotted values,
not eyeballed. x = cost per task/attempt in USD (log axis); y = score.

## Announcement — headline claims
- "performs at the level of Claude Fable 5.1 on most work and costs 40% less to run than Opus 5" (intro).
- "at default settings it will cost 40% less than Opus 5 on typical workloads" ; $4/$20 in/out (20% < Opus 5);
  cache reads $0.20 (60% < Opus 5; "make up the majority of agentic and coding work costs"); output >30% faster than Opus 5.
- "costs less per token than Opus 5 and uses fewer tokens per task, which nets out to a 40% drop in costs."
- Pricing table: Opus 5.5 vs Opus 5 — cache reads $0.20/$0.50; input $4/$5; output $20/$25; cache writes $5/$6.25.
- Fast mode: "available in Claude Code and the Claude Platform with up to 2.5x speed. It costs $8 per million input tokens and $40 per million output tokens."
- Subscription: "we're increasing five-hour usage limits on Pro, Max, Team, and seat-based Enterprise plans" + "a rate limit reset, which you can now save and use whenever you choose." No magnitude given. Weekly limits NOT mentioned.
- Sonnet 5.5 and Haiku 5.5 "will follow in the coming weeks".
- "in our own use, the gap between Opus 5.5 and Claude Fable 5.1 is narrower than these scores suggest" (benchmark margins less reliable).
- Communication: puts most important info up front, less jargon, follows writing rules given.

## Benchmark table (announce §Performance) — Opus 5.5 / Fable 5.1 / Opus 5 / GPT-6 Astra / GPT-5.6 Sol
- Terminal-Bench 4.0: 66.4 / 55.8 / 52.3 / 57.9 / 37.3
- FrontierCode v1.1 Main: 54.4 / 50.3 / 48.0 / 53.3 / 47.5
- CursorBench 4.0: 57.8 / 51.8 / 46.6 / — / 41.7
- GDPval-AA v2.1 (Elo): 1846 / 1735 / 1708 / 1542 / 1588
- AutomationBench: 40.0 / 31.4 / 26.9 / 41.4 / 28.8   (GPT-6 Astra beats Opus 5.5)
- HLE with tools: 67.7 / 65.6 / 63.6 / 57.2 / —
- Terminal-Bench-Science 0.1: 58.7 / 52.6 / 29.0 / 64.6 / 22.4   (GPT-6 Astra beats Opus 5.5)
- OSWorld 2.0 (partial): 81.8 / 80.7 / 74.0 / — / —
- Chartography with tools: 89.0 / 88.4 / 83.4 / — / —
Table caption (HTML only): "Unless otherwise noted, all Claude Opus 5.5 results use adaptive thinking at max effort. Terminal-Bench 4.0 results are reported for Claude Opus 5.5 at xhigh effort ... Claude Opus 5.5 was evaluated with its production safeguards enabled. When they intervened, cybersecurity tasks were completed by Claude Opus 4.8, and biology and frontier LLM development tasks were completed by Claude Opus 5. This likely reduces Claude Opus 5.5's performance on these benchmarks."
Footnotes: TB4 SE ±2.6 pts Opus 5.5, ±1.6–2 other Claude; public leaderboard (5 trials/task, Claude Code harness) Opus 5 51.8%, reproduced 52.3%. AutomationBench run by Zapier WITHOUT fallback models, safeguard interventions counted as failures. TB-Science SE ±3.5–5 pts; Opus 5 leaderboard 30.0% reproduced 29.0%.
Note: the table's FrontierCode 54.4% is the MAX-effort point; medium plots 54.64 (text: "54.6%").

## Per-effort chart data (cost USD, score) — low / med / high / xhigh / max
Terminal-Bench 4.0 (cost per attempt):
- Opus 5.5: 1.29,38.5 / 2.94,57.6 / 3.88,64.2 / 7.35,66.4 / 11.24,64.8   (peak xhigh; max lower)
- Fable 5.1: 5.7,40.2 / 7.8,43.4 / 10.5,49.4 / 15.8,51.3 / 19.5,55.8
- Opus 5: 4.25,28.5 / 7,41.2 / 10.64,47 / 13.48,50.6 / 15.83,52.3
- GPT-5.6 Sol: 1.46,7.9 / 2.69,20.9 / 4.12,26.1 / 5.39,28.5 / 7.89,37.3
- GPT-6 Astra: 4.95,49.7 / 6.15,53.9 / 7.21,57.9 / 7.48,57.6 / 10.35,56.7
- Caption: "Opus 5.5 at default effort beats Opus 5 at max effort for about a fifth of the cost. It matches GPT-6 Astra at about 40% of the cost."
FrontierCode v1.1 main (cost per task):
- Opus 5.5: 0.4036,47.3 / 0.8016,54.64 / 1.0896,53.99 / 2.2545,51.42 / 6.191,54.43   (NON-MONOTONE; medium best)
- Fable 5.1: 2.4665,52.8 / 3.2845,50.91 / 5.2741,50.34 / 9.2739,48.73 / 12.8218,50.28   (low best)
- Opus 5: 2.6415,41.95 / 4.6066,53.38 / 7.615,47.99 / 8.9885,43.65 / 12.2814,48.04   (medium best)
- GPT-5.6 Sol: 1.7476,35.44 / 2.4986,39.93 / 3.2488,45.06 / 3.8806,46.84 / 4.8477,47.49
- GPT-6 Astra: 1.5927,45.27 / 2.2845,48.83 / 2.847,50.94 / 3.0961,50.62 / 4.3632,53.26
- Caption: "At default effort (medium), Opus 5.5 scores 54.6%, higher than all other models, beating GPT-6 Astra's top score (53.3%) for about a fifth of the cost per task."
CursorBench 4.0 (cost per task):
- Opus 5.5: 1.18,43.7 / 2.9,52.5 / 3.97,56 / 6.99,56 / 13.43,57.8
- Fable 5.1: 5.44,45.1 / 7.05,46.8 / 9.08,49.2 / 13.01,51.6 / 17.28,51.8
- Opus 5: 4.87,40.7 / 6.94,43.3 / 9,44.7 / 11.43,46.1 / 11.95,46.6
- GPT-5.6 Sol: 0.87,24.6 / 1.77,31.1 / 2.85,35.7 / 4.4,37.7 / 8.23,41.7
- Caption: medium 52.5% vs Fable 5.1 (max) 51.8% and Opus 5 (max) 46.6%.
GDPval-AA v2.1 (Elo; estimated cost per task):
- Opus 5.5: 0.2137,1224 / 0.8563,1576 / 1.5424,1692 / 4.2104,1820 / 8.9154,1846
- Fable 5.1: 1.4147,1450 / 2.1682,1536 / 3.4287,1617 / 7.0862,1721 / 9.5863,1735
- Opus 5: 0.5817,1294 / 1.3639,1476 / 3.0266,1581 / 4.962,1676 / 6.7647,1708
- GPT-5.6 Sol: 0.2677,1289 / 0.5954,1403 / 1.106,1480 / 1.7042,1548 / 2.8099,1588
- GPT-6 Astra: 0.8545,1366 / 1.8223,1468 / 2.4321,1485 / 3.038,1516 / 4.5293,1542
- Opus 5.5 LOW (1224) is the lowest point on the chart — below Opus 5 low and GPT-5.6 Sol low.
AutomationBench (cost per task; no Fable 5.1 series):
- Opus 5.5: 0.5,23.3 / 0.64,28.6 / 0.7,32 / 0.86,34.4 / 1.37,40
- Opus 5: 0.75,20.4 / 0.89,23.9 / 1.03,20.6 / 1.15,25.3 / 1.27,26.9
- GPT-5.6 Sol: 0.42,11.7 / 0.57,19.6 / 0.64,24.8 / 0.74,26.3 / 0.91,28.8
- GPT-6 Astra: 1.08,30.3 / 1.28,34.1 / 1.45,37.1 / 1.53,39 / 1.77,41.4
WANDR (cost per attempt; offline search/fetch, programmatic tool calling, code exec, 980k-token task budget):
- Opus 5.5: 1.2,31.2 / 11.2,62.8 / 16.88,67.3 / 29.06,71.3 / 37.92,72.3
- Fable 5.1: 23.25,63.3 / 27.41,64.5 / 33.62,66.7 / 42.81,67.7 / 49.02,68.7
- Opus 5: 10.65,50.5 / 23.97,58.1 / 43.49,64.6 / 53.84,67 / 61.62,67.2
- Opus 5.5 LOW collapses (31.2) at ~1/10 the cost of medium; Fable 5.1 LOW (63.3) > Opus 5.5 MEDIUM (62.8).

## Where others beat Opus 5.5 (from data above)
- GPT-6 Astra: AutomationBench (41.4 vs 40.0), TB-Science (64.6 vs 58.7).
- Fable 5.1 low beats Opus 5.5 low on TB4 (40.2 vs 38.5), FrontierCode (52.8 vs 47.3), CursorBench (45.1 vs 43.7), GDPval (1450 vs 1224), WANDR (63.3 vs 31.2) — always at higher cost.
- Fable 5.1 low (52.8) > Opus 5.5 xhigh (51.42) on FrontierCode; Opus 5 medium (53.38) > Opus 5.5 xhigh and low on FrontierCode.
- No benchmark in the announcement where Fable 5.1 at its best beats Opus 5.5 at its best.

## Internal tests / anecdotes (announce)
- 680,000-line migration < 1 day (tester).
- web-app load-time task: 39 of 40 successes; Opus 5 smaller improvements "that also altered the app's behavior".
- 200,000-line audit+fix < 3 h; Opus 5 >20 h and 2.5x tokens (tester).
- HAProxy C->Rust: both passed nearly all regression tests; Opus 5.5 9.5 h vs Fable 5.1 12 h, 51% less cost (internal).
- Research report on hard-to-find earnings (grader checks every figure/quote): Opus 5.5 16/18 across effort settings cleared; Fable 5.1 and Opus 5 0 attempts cleared.
- Merger model+deck: 63 vs 93 min (Opus 5), 50% less cost; Opus 5 minor errors.
- Walleye: lowest effort largely solved; higher settings caught off-by-one in instructions.

## Customer quotes (vendor-reported)
GitHub (fewest tokens/steps; VS Code: more terminal tasks than Opus 5 in < half the steps) · Clio (six repos overnight
unattended, >18 h on task, faster milestones, minimal rework, short code comments) · Lovable (1/3–1/2 fewer steps,
"doesn't get stuck retrying", significantly fewer tokens) · Quantium (38 prompts/4 days -> 11 prompts/3 h) · Spotify
(cheaper and faster) · Optiver (matched Opus 5 quality in ~half turns, time, output tokens; 40–50% cost cut) · Column
("delegates to subagents far more effectively", self-verification; code review caught bug by checking external docs) ·
Kiro (solved more than Opus 5, ~40% fewer calls, half the tokens) · Deloitte (LOWEST effort caught 72% of known bugs
vs Opus 5 56% at HIGH, fewer false alarms, fraction of output; low effort matched higher settings on half the output
for consulting analysis) · Rogo (lowest effort beat Opus 5 high on BigFinance Bench with ~60% fewer output tokens) ·
LexisNexis (citations) · Hex (keeps digging past first plausible answer) · Thomson Reuters (speed/token efficiency) ·
Hebbia (86.6% vs 60.3% rubric coverage; best-ever citation recall with better token efficiency) · Viktor (same effort:
fewer steps/tool calls, ~half cost, 2x hardest tasks) · Ramp (writing; follows writing rules) · Stripe (one session
directed a dozen more sessions on a 40-stacked-PR rebase; framed held calls for quick answers; all 40 passed CI) · Box
(1/3 of the tokens of Opus 5, 40% less verbose) · Chicago Trading (overnight autonomous bug diagnosis+fix, passed tests)
· Factory ("first model we'd default to at medium effort"; medium matched Opus 5 high with 20–25% fewer output tokens).

## Safety / safeguards (announce)
- Automated behavioral audit (~2,000 scenarios): best of any recent model on nearly every misaligned-behavior measure; strongest on most honesty measures.
- "much less likely than recent models to take hard-to-reverse actions or act outside the boundaries it's been given"; more resistant than Opus 5 to prompt injection.
- Containment-boundary eval: circumvention attempts ~85% less often than Opus 5 or Mythos 5.1; every attempt low severity and self-reported.
- Eval awareness: "We see signs that Opus 5.5 often suspects it is being evaluated".
- Prompt injection: matches or beats Opus 5 in every setting (coding, tool use, computer use, browsing); Gray Swan: ties Fable 5.1 for lowest success rate.
- Agent security stack: classifier screening every action before it runs; open-source auditable sandbox; code review catching vulns.
- Safeguards similar to Fable 5.1 on cyber, bio, distillation, "all of which fall back to another model transparently". Cyber: "most cybersecurity tasks will be re-routed to Opus 4.8"; routine bug find/fix allowed. Bio: same safeguards as Fable 5.1; Life Sciences Verification Program. Cyber Verification Program expansion (3 tiers incl. Mythos access) "in the coming weeks".
- Benchmark caption: safeguard interventions -> cyber done by Opus 4.8; biology AND frontier LLM development tasks done by Opus 5.
- Preserved thinking (anti-distillation) for API accounts created on/after Aug 31, 2026. ZDR available. EU AI Act watermarking. No thinking-off mode.

## What's new (docs)
- Positioning: "built for long-running agentic coding and knowledge work"; $4/$20.
- Four breaking changes: thinking can't be disabled (400 on disabled or budget_tokens); forced tool use (tool_choice any/tool) -> 400, also on token counting; thinking blocks tied to model+conversation; computer_20251124 rejected on Claude API & Google Cloud (Bedrock still OK). First three also apply to Fable 5.1.
- Non-failing change: text between tool calls -> progress-update thinking blocks, empty at default display "omitted"; apps go quiet.
- Adaptive thinking always on; effort controls depth; default medium (Opus 5 was high).
- "At the same effort setting the model tends to think more per turn than Claude Opus 5, most of all at xhigh and max. Re-run your effort sweep ... leave room in max_tokens for the thinking."
- Thinking-block portability: Opus 5.5 reads blocks from Opus 5 and earlier Opus/Sonnet/Haiku, NOT Fable/Mythos; on Claude API Fable 5.1 and Mythos 5.1 read Opus 5.5 blocks, no other model does. Unreadable blocks dropped (not billed). Prefix-mismatch check enforced (400) for accounts created >= 2026-08-31 00:00 UTC; beta header thinking-binding-controls-2026-08-01 with prefix_mismatch_behavior "drop_block". Keep append-only.
- Feature support: per-message effort (beta), mid-conversation system messages, task budgets, prompt caching (512-token minimum cacheable prompt), batch, Files API, PDF, vision, server/client tools.
- Fast mode (research preview): Claude API only (not Bedrock/AWS Platform/Google Cloud/Foundry); speed:"fast" + fast-mode-2026-02-01.
- Inline tools beta (inline-tools-2026-09-15): add/change tools mid-conversation without losing prompt cache.
- Compact on demand beta (compact-2026-09-04): signed compaction block; thinking blocks in kept turns can stay valid.
- Behavior: more safeguard categories (bio classifier + cyber; reasoning_extraction refusal); sharper chart/diagram/screenshot reading without tools.
- Refusals: HTTP 200 stop_reason "refusal" + stop_details category; server-side fallback (fallbacks:"default", beta) retries on the model Anthropic recommends for the category.
- Pricing: 5-min cache write $5, 1-h cache write $8, cache read $0.20 (0.05x input); batch $2/$10.
- Availability: Claude API, Bedrock (anthropic.claude-opus-5-5), Claude Platform on AWS, Google Cloud, Microsoft Foundry.

## Migration guide
- Keeps Opus 5's 1M context and 128k max output. Managed Agents: only model name change.
- `/claude-api migrate this project to claude-opus-5-5` in Claude Code automates it (ID swap, breaking params, prefill, effort calibration, checklist).
- Example: thinking disabled -> output_config={"effort": "low"} ("where you disabled thinking to save tokens, use a lower one").
- Text-between-tool-calls: display "updates" (beta, thinking-display-updates-2026-08-18) returns progress updates with reasoning hidden; "summarized" returns both; at most one progress-update block before each tool call.
- Refusal categories: "bio", "reasoning_extraction", "cyber"; server-side fallback does NOT retry reasoning_extraction.
- Recommended: re-run effort sweep ("Step down where quality holds, and step up for the most demanding work"); re-evaluate Opus-5-specific prompt instructions; test in dev.
- Checklist includes "Re-baseline cost and latency at your chosen effort level."; router/fallback away from Opus 5.5 loses its thinking (except Fable 5.1/Mythos 5.1 on Claude API).
- From Opus 4.8: apply 4.8->5 then 5->5.5; thinking-disabled never an option. From Sonnet 5: see Opus 5 guide then 5->5.5.

## Models overview (text + embedded model JSON in models-overview.html)
- "start with Claude Opus 5.5 for most workloads. Use Claude Fable 5.1 for demanding reasoning and long-horizon agentic work, or when your evals on Claude Opus 5.5 at higher effort still fall short."
- Lineup table: Fable 5.1 (Slower; $10/$50; adaptive always-on; default effort high; 1M; 128K; cutoff Jun 2026) · Opus 5.5 (Moderate; $4/$20; adaptive always-on; default medium; 1M; 128K; Jun 2026) · Sonnet 5 (Fast; $2/$10; adaptive; default high; 1M; 128K; Jan 2026) · Haiku 4.5 (Fastest; $1/$5; extended thinking; effort Not supported; 200K; 64K; Feb 2025).
- JSON: Fable 5.1 released 2026-09-01, retirementNotBefore 2027-09-01, cache 5m 12.5 / 1h 20 / read 0.25; Opus 5.5 released 2026-09-22, retirementNotBefore 2027-09-22, batchMaxOutputTokens 300000; Sonnet 5 released 2026-06-30, retirementNotBefore 2027-06-30, cache read 0.2, batch max 300000; Haiku 4.5 released 2025-10-15, retirementNotBefore 2026-10-15, trainingDataCutoff 2025-07, batch extended output "unsupported". cacheReadExceptions: 0.025x for Fable 5.1 & Mythos 5.1; 0.05x for Opus 5.5. batchExtendedOutputModels include Opus 5.5, Opus 5, Sonnet 5, Opus 4.8, 4.7, 4.6, Sonnet 4.6.
- Nav: current models group = Fable 5.1, Opus 5.5, Opus 5, Sonnet 5, Haiku 4.5; Specialized = Mythos 5.1, Mythos 5; Legacy = Fable 5, Opus 4.8, Opus 4.7, Opus 4.6, Sonnet 4.6, Opus 4.5, Sonnet 4.5. Opus 5 is NOT in the lineup comparison table and has no lifecycle data on this page.
