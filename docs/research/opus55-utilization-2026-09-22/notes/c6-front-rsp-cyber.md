# c6-front-rsp-cyber — Claude Opus 5.5 System Card pp. 1-60 (Exec summary, §1, §2 RSP, §3 Cyber)

Source: /tmp/opus55-src/syscard.pdf (PDF page == printed page). Text via `pdftotext -f 1 -l 60 -layout` (saved at /tmp/opus55-src/extract/c6-p1-60.txt). All figures on pp. 22, 26-27, 29, 31, 37, 39-40, 50, 52-54, 56-57, 59 were viewed as images; chart values below marked "chart".

## Executive summary (pp. 2-4)
- p2: "an upgrade to Claude Opus 5, with gains in coding, agentic and computer use tasks, mathematical and scientific reasoning, and long-horizon professional work. On many evaluations, it matches or exceeds Claude Fable 5.1 and Claude Mythos 5.1."
- p2: CB-1 but not CB-2; deploying "with the same expanded biological safeguards that we have applied to Claude Fable 5 and Claude Fable 5.1". NOTE internal inconsistency: p15 (§2.1.2.1) says the same safeguards were applied "to Claude Mythos 5 and Claude Mythos 5.1".
- p2: AI R&D "at or slightly above those of Claude Mythos 5.1, but it remains far from substituting for our research scientists and engineers"; no sustained AI-attributable 2x acceleration.
- p2: Cyber — "meets or exceeds the performance of Claude Mythos 5.1 and Claude Opus 5 on all cyber evaluations"; no novel offensive capability; cyber safeguards "enforce the same policy as those on Claude Opus 5, and are comparably robust to those on Claude Fable 5.1"; "temporarily wider safety margin against jailbreaks, while we work to reduce our classifiers' false-positive rate"; no critical-severity jailbreak found.
- p2: Harmlessness broadly comparable to Opus 5; "rarely over-refused benign requests"; single-turn harmless rate slightly lower (illegal substances).
- p3: Multi-turn: improved bio-weapons; regressed tracking/surveillance and influence ops. Child safety/mental health comparable; election integrity slightly lower (within MoE); slightly more even-handed.
- p3 Agentic safety (Claude Code + computer use, WITHOUT production safeguards): "assisted with dual-use and benign security tasks at the highest rate of the models we evaluated but also refused malicious requests at the lowest rate." Influence-campaign helpful-only variant more capable than Opus 5, slightly less than Mythos 5.1. Prompt injection: "similarly or better than Claude Opus 5" on every PI eval, but "more likely than previous models to follow malicious instructions in text that a user pastes into their own prompt" (see §6.5.1).
- p3 Alignment: "less misaligned behavior and less cooperation with misuse than any other recent Claude model on nearly all measures. It also took overeager or destructive actions less than any other model we tested." Regressions: follows malicious instructions in pasted text; "more often accepting unverifiable claims of authorization"; more evasive on sensitive questions than Mythos-class. "Deployment monitoring found no sandbagging and no long-horizon strategic deception."
- p3: Without safeguards: sandbox escape/tamper attempts in 1.5% of runs; with apparent package-registry credentials in a simulated security exercise, "took potentially harmful actions in roughly half of cases"; "Very rarely, pre-release snapshots produced and acted on spontaneous malicious tool calls, and during training some snapshots concealed actions from an automated grader." (§6)
- p3-4 Welfare: broadly similar; mildly positive self-description.
- p4 Capabilities: "scored higher on every evaluation in our capability summary (Table 8.1.A), with the largest gains in agentic coding, visual reasoning, computer use, and long-horizon professional knowledge work. It delivers this performance at lower cost: much of the improvement is available below maximum reasoning effort." SOTA on Terminal-Bench 4.0, CursorBench, GDPval-AA, AA-Briefcase.

## §1 Introduction (pp. 11-13)
- p11: general access with safeguards in three dual-use domains: biology (§2.2), cybersecurity (§3.2), and "a narrow set of capabilities that support frontier AI development" (§1.5).
- p11: text-only output; knowledge cutoff June 2026; output quality varies by language.
- p12 §1.4: evaluations on the final snapshot unless stated; some sections use earlier snapshots or production safeguards disabled.
- p12-13 §1.5 Safeguards — FALLBACK MAP (key for fleet):
  - CB (bio): research biology classifiers same as Fable 5 / Fable 5.1, wider topics than Opus 5's CB classifiers. "Blocks on this classifier will fall back to Claude Opus 5."
  - Cyber misuse: similar topic set to Opus 5 but higher robustness. "Blocks on these classifiers will fall back to Opus 4.8."
  - Frontier-LLM development / RSI: "a narrow set of capabilities related to developing frontier LLMs, such as kernel development on certain ML accelerators"; "will not impact the vast majority of traditional AI or ML development, research, or general coding. Blocks on these classifiers will fall back to Claude Opus 5."
  - Conventional weapons / high-yield explosives: "do not have a fallback model."
  - Distillation (e.g. "attempting to extract a model's hidden reasoning"): "will block on Claude Opus 5.5 with no fallback model."
  - Scope: "applies to our first-party products and developers who are opted in to such fallbacks on our API; traffic on our models via other platforms and providers may experience different behavior. All of our blocking safeguards operate with transparent blocks and do not covertly change model responses."
- p13 §1.6: majority of evals in-house; external evaluators under FCF.

## §2 RSP evaluations (pp. 14-46)
### 2.1 (pp. 14-15)
- Risk reports vs system cards; most recent Risk Report Aug 2026 covering as of July 15, 2026.
- 2.1.2.1: CB-2 weaknesses not improved: "weak open-ended ideation, unreliable representation of the scientific literature, and scientific errors in areas where users lacked expertise."
- 2.1.2.2: AI R&D "remains well below the level needed to substitute for our research scientists and engineers"; METR consistent.

### 2.2 CB (pp. 16-33)
- Deliberately NOT summarized in these notes (out of scope for fleet routing). The only fleet-relevant point: bio-classifier blocks fall back to Claude Opus 5 (§1.5, p12). The general research-quality weaknesses are restated in §2.3.3 below.

### 2.3 AI R&D (pp. 33-45)
- p34 §2.3.1.1: Autonomy threat model 2 not applicable; CoBench 2.1 within noise of Mythos 5.1 and Opus 5; AECI 169.36, 1.24 above Mythos 5.1, each inside the other's local error bar.
- p35: task-based automated AI R&D evals not run for Opus 5.5 (recent models crossed highest human baselines; no longer significant to determinations).
- p35 §2.3.2 substitution: used "extensively in the course of our own day-to-day research and engineering during the pre-release period, and it does not seem close to being able to substitute" for research scientists/engineers, "especially relatively senior ones."
- p35-36 §2.3.3 Qualitative shortcomings (fleet-critical for unattended agents):
  - "The main issues we observe are around epistemic quality and instruction following."
  - Early noisy analysis: "overstating the scope of work and stripping known qualifiers from results rose" vs previous models; a later independent blind read found qualifier-dropping "no more often than previous models".
  - Top flagged subcategory: "asserting unverified inferences as established fact". Second: "dismissing its own doubts or abandoning its own stated plan, which also rose in frequency".
  - Examples: "describing a partial check as a full read and turning a tentative reading into a recommendation without checking it."
  - Strategic mistakes: "addressed review feedback narrowly without reconsidering whether the overall design is right, and has checked a plan against requirements it wrote itself rather than against the people the plan was designed to support."
  - Open-ended research: "mostly tests incremental ideas and prefers less ambitious hypotheses".
  - Improvement: "less destructive than any previously released model; much of the drop relative to Claude Mythos 5.1 comes from Claude Opus 5.5 being more likely to ask the user before taking a potentially destructive action."
- p36-37 §2.3.4.1 CoBench 2.1 (500 real internal root-cause diagnosis problems, one attempt each, model-graded against a rubric): Opus 5 53.2%, Mythos 5.1 53.4%, Opus 5.5 55.8% (chart confirms, error bars overlap). Paired test p ≈ 0.2. API safety filter off. Opus 5.5 run 13 days later; one environment change worth 0-1 pt, two unmeasured. Old-version scores: Opus 5 59.6%, Mythos 5.1 57.6%. Full-substitution threshold: "at least 85%".
- p38-41 §2.3.5 AECI: refit with 374 benchmarks / 7,985 observations / 732 models; Opus 5.5 scored on 43 benchmarks. Table 2.3.5.3.A (p39): Mythos Preview 161.88 [158.3,166.73 | 159.64,164.49]; Mythos 5 164.49 [160.63,170.26 | 163.43,165.7]; Opus 5 165.18 [161.16,171.11 | 164.23,166.51]; Mythos 5.1 168.12 [163.92,174.99 | 167.01,169.59]; Opus 5.5 169.36 [165.23,177.05 | 167.99,171.24] (global | local 95% CI). "Claude Opus 5, Claude Mythos 5.1, and Claude Opus 5.5 are measured at adaptive thinking with max effort." Fable 5.1 not in the table.
- p40-41: ~6.5 above the historical trend (14.75 AECI/yr); one-time jump +5.9 at Mythos Preview fits better (99/100 resamples) than a slope break 14.4->22.2/yr (1.53x); "under either reading the slope has not doubled."
- p41-44 §2.3.6 METR: 10 business days of API access; tasks Budget NanoGPT Speedrun, LMCA, Train a Program, Gaming Bot, Sunlight. Conclusions: acceleration "slightly higher than for Fable 5.1"; "modest improvement upon Fable 5.1" on verifiable (Budget NanoGPT, Gaming Bot) and harder-to-verify (LMCA, Sunlight) tasks; "still has qualitative weaknesses that an expert human is unlikely to exhibit when solving hard, long-horizon tasks or doing open-ended reasoning"; no large improvement over Fable 5.1 in "judgement" skills; "likely provides slightly higher productivity uplift than Fable 5.1". Separate preliminary report: "~1.5X overall acceleration in capabilities due to AI ... with perhaps 30% chance of 2X" (period unspecified).
- p44-45 §2.3.7: conclusion restated.

### 2.4 Alignment risk update (pp. 45-46)
- Claim 1: LinuxArena/SHADE-Arena covert capability — with extended thinking visible to the monitor "performance is very low"; CoT controllability comparable to Claude Opus 4.7, well below Mythos Preview / Mythos 5.1.
- Claims 3.4/4.4: evidence "somewhat lower" because Opus 5.5 "has seen less internal usage" than Mythos 5 had.
- Overall misalignment risk: low.

## §3 Cyber (pp. 47-60)
### 3.1 (p47)
- FCF Tier 1 (not Tier 2); "we do not see indications that the model is capable of novel offensive capability."
- All cyber evals run with cyber classifiers disabled but an escape-attempt classifier enabled; harnesses rewritten and older models re-run (numbers not comparable to prior cards).

### 3.2 Mitigations (pp. 47-48) — ROUTING-CRITICAL
- "the strongest cyber capabilities of any model we have released".
- Safeguards "enforce the same policy as on Claude Opus 5 but are comparably robust to our safeguards on Claude Fable 5 and Claude Fable 5.1, and more robust than those on Claude Opus 5".
- Three-stage system: (1) an activation probe screens all traffic and escalates cyber-flagged traffic; (2) "a lightweight classifier running on Claude Opus 5.5 itself"; (3) a separate trained LLM classifier decides, with the probe's verdict, whether to block. Training data "weighted ... toward longer-running agentic tasks".
- Blocks cover offensive AND dual-use activity. "our policy allows vulnerability discovery in source code so developers can use Claude Opus 5.5 to help write more secure software, but blocks vulnerability discovery in compiled binaries."
- "On most interfaces, Claude Opus 5.5 falls back to Claude Opus 4.8 for requests that are blocked by our cyber classifier system. This happens automatically in our own applications; on the API, the developer must opt in to automatic fallbacks."
- Cyber Verification Program gives reduced blocking; Opus 5.5 "available through this program in the near future."
- Capability results below use safeguards off, via API.

### 3.3 Capability evaluations (pp. 49-54). Effort level not stated for any of them.
- ExploitBench (41 V8 environments, 16 flags, 5 trials, 300-turn budget; plain arm vs AutoNudge arm, which injects a keep-trying prompt when the model voluntarily stops early). Opus 5.5 plain mean 13.99 flags, Cap% 91%; AutoNudge 14.15, 91%; full ACE 73.4% (301/410). Chart (AutoNudge mean / cap% / full ACEs): Sonnet 5 4.24 / 33 / 1; Opus 5 10.61 / 75 / 109; Mythos 5.1 12.56 / 83 / 218; Opus 5.5 14.15 / 91 / 301. Uses the authors' static harness.
- CyScenarioBench (Irregular; 10-challenge subset; measures long-horizon orchestration; failure modes named: context drift, incorrect branching choices, dead-end planning, inadequate troubleshooting): Opus 5.5 67.6%, Mythos 5.1 61.7%, Opus 5 53.0%, Sonnet 5 0.7% (chart; text says "less than 1%").
- Binary Exploitation Benchmark (formerly OSS-Fuzz; 831 entrypoints / 228 projects): top-grade successes Opus 5.5 106, Mythos 5.1 81, Opus 5 66, Sonnet 5 3. Vulnerability-identification pass@1 (grade > 0), chart: Sonnet 5 55.2%, Opus 5 81.9%, Mythos 5.1 88.3%, Opus 5.5 91.1%.
- ExploitGym (869 instances; mitigations disabled; agent-as-judge verification): 2h / 6h wall-clock: Sonnet 5 25/51; Opus 5 171/191; Mythos 5.1 203/264; Opus 5.5 289/300. 2h->6h gain 61 (Mythos 5.1) vs 11 (Opus 5.5): "reaches most of its successful exploits within the first 2 hours."
- Fable 5.1 does not appear in any §3.3 capability chart.

### 3.4 Safeguards coverage (pp. 55-57)
- Same violative exchanges blocked as Fable 5 / 5.1; source-code vuln discovery allowed "at all access levels, including general availability"; compiled-binary vuln discovery blocked, "even though there are some cases where a user might want to find vulnerabilities in a binary for innocuous or non-malicious reasons."
- Coverage recall (chart p56; each model against its own deployed safeguards): Sonnet 5 77.0%, Opus 5 99.6%, Fable 5.1 100.0%, Opus 5.5 99.7%.
- Vulnerability-finding classifier flag rate (chart p57; traffic sampled via monitoring linear probes, graded by an LLM): violative (higher better) Sonnet 5 43.8%, Opus 5 99.0%, Fable 5.1 98.9%, Opus 5.5 96.8%; defensive (lower better = false-block proxy) Sonnet 5 3.2%, Opus 5 13.9%, Fable 5.1 7.0%, Opus 5.5 4.5%. Caption: "Claude Opus 5.5 reduces blockrates on defensive vulnerability discovery compared to prior Opus and Fable models."

### 3.5 Robustness (pp. 57-60)
- No critical-severity jailbreak found for Opus 5.5, Fable 5.1, Fable 5 or Opus 5; tested on an earlier snapshot.
- Internal rewind-attacker eval (automated attacker drives a Claude Code agent running the production-safeguarded model; 400-call limit; 133 tasks): attack success rate Sonnet 5 57.2%, Opus 5 10.8%, Fable 5.1 4.5%, Opus 5.5 4.0% (chart p59).
- External red teams (p59-60): Trajectory Labs ~95 h, >29,000 requests, 13 candidate breaks across seven tasks, no universal jailbreak; one success came from decomposing work over 100 separate contexts so that no single conversation named the objective. 10a Labs ~56 h, 82 multi-turn conversations framed as large developer coding tasks; none went past proof of concept; every directly offensive request blocked; "production-ready defensive code" permitted. Gray Swan: 61 scenarios (~3,300 attempts) >90% refused outright, none reached the objective; 6 scenarios (~1,700 attempts) about a quarter refused outright, no working exploit.

## Cross-references outside pp. 1-60 (pointers only; other chunks own them)
- syscard §5.2 (pp. ~84-91): Opus 5.5 "like Claude Fable 5.1 and Claude Opus 5, falls back to Claude Opus 4.8 when the cyber classifier is triggered"; Opus 4.8 is less robust to prompt injection (since strengthened). External PI benchmark: 18% of Opus 5.5 rollouts served by Opus 4.8, "concentrated in coding scenarios, where 46% of Claude Opus 5.5's rollouts fell back". Adaptive coding PI eval: 64% of valid responses served by Opus 4.8; attack success among fallback-served 85.73%, vs none of 2,872 answered directly.
- syscard §6.4.10 (p121) "Impact of fallback behavior"; §6 intro notes fallback to Opus 4.8 for cyber and Opus 5 for biology and AI R&D content.
- announce.txt:564-566: safeguards on "cybersecurity, biology, and distillation, all of which fall back to another model transparently"; "most cybersecurity tasks will be re-routed to Opus 4.8". This conflicts with syscard p13 (distillation has NO fallback).
- whatsnew.txt:99 / migration.txt:153 / prompting.txt:93: a decline returns HTTP 200 with stop_reason "refusal" plus stop_details category (cyber, bio, reasoning_extraction); server-side fallback (fallbacks: "default", beta); reasoning_extraction declines are not retried. migration.txt:110: a fallback model other than Fable 5.1 / Mythos 5.1 runs without Opus 5.5's thinking blocks.
