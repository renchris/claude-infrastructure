# Why "are we 100% complete?" yields a new item every time, and how to get a stable answer

Scope: LLM-specific causes, from papers (2023-2026), vendor docs and practitioner reports, plus techniques that give stable answers. Every claim carries a receipt. Researched 2026-09-30.

---

## 0. Verdict (answer first)

The "one more thing, forever" loop is **the expected output of the question as it is asked, not proof that the research has holes.** Four measured LLM properties make it close to certain:

1. **The question demands an item.** Asking "find problems / anything missing?" makes models change correct work more often than they fix wrong work (Huang et al., ICLR 2024: GPT-3.5 CommonSenseQA fell from 75.8% to 38.1% after one "Review your previous answer and find problems with your answer" round). Coding agents given an already-fixed issue still submit a patch 35-65% of the time (FixedBench, arXiv 2605.07769), which the authors call "action bias". Six LLMs asked neutrally to security-review *patched* code flagged something ≥88% of the time (arXiv 2603.18740). Most flags were false, but up to 57.5% (Opus 4.5) were real bugs *unrelated to the question* (F17).
2. **Models cannot reliably say "nothing".** Training and evals reward guessing over abstaining (OpenAI, Sept 2025). Verbalized confidence runs high (Xiong et al., ICLR 2024). Models answer false-premise questions as fluently as sound ones (CREPE, Cancer-Myth).
3. **Each fresh sample explores a different region.** One judge disagrees with itself across runs (Rating Roulette, EMNLP-F 2025: the best model gave the same MT-Bench verdict on all 3 runs in only 61.3% of cases). The "completeness" criterion is the least stable (arXiv 2603.04417). Inference at temperature 0 is still nondeterministic (Thinking Machines, 2025).
4. **The frame drifts and the memory decays.** Evaluation criteria change as you look at outputs (Shankar et al., UIST 2024, "criteria drift"). Recall falls with context length (Lost in the Middle; Chroma Context Rot, 18 models). Compaction "can result in the loss of subtle but critical context" (Anthropic). Broad "collect everything" agentic search succeeds ~0-5% of the time (WideSearch, ICLR 2026).

**Consequence.** An open-ended "anything missing?" is an unbounded generator. It can never return a stable "no". Stability has to come from the protocol:
- a **frozen, closed checklist**, answered from a **persisted ledger** rather than regenerated;
- **explicit, rewarded abstention**;
- a **materiality gate** (would this change a decision?) and a **"why was this not in the frame?"** justification on every new item;
- a **quantitative stopping rule** (saturation run length, or capture-recapture across *independent* reviewers), not a vibe.

**The operator's own machinery has this bug built in.** `agents/deep-research.md:187` says "Find 2-3 gaps". `~/.claude/skills/research-subagents/SKILL.md:353,798` says "List 3 with reasons" and auto-promotes any dimension whose reason is "not obviously relevant" (SKILL.md:800-801). Both are quota prompts that guarantee non-empty output (see §4).

---

## 1. Failure modes: mechanism, evidence, and how each shows up in "are we complete?"

| # | Failure mode | Primary evidence (receipt) | How it produces "one more thing" |
|---|---|---|---|
| F1 | **Intrinsic self-correction does not converge; it degrades** | Huang et al., "LLMs Cannot Self-Correct Reasoning Yet", ICLR 2024 (arXiv 2310.01798). Prompt: *"Review your previous answer and find problems with your answer."* GPT-3.5 CommonSenseQA 75.8% → 38.1% (1 round) → 41.8% (2 rounds). "The model is more likely to modify a correct answer to an incorrect one than to revise an incorrect answer to a correct one." The authors attribute part of this to the feedback prompt biasing the model. | Each "are we complete?" is a self-correction round with no external oracle. The literature predicts churn, not convergence. |
| F2 | **Self-correction only works with reliable external feedback** | Kamoi et al., TACL 2024 (arXiv 2406.01297): "no prior work demonstrates successful self-correction with feedback from prompted LLMs in general tasks"; it "works well in tasks that can use reliable external feedback". | Plan completeness has no test oracle unless you build one (a closed checklist, acceptance criteria). Without one, you are in the regime where self-critique does not work. |
| F3 | **Models are bad at locating errors (so critique is noisy), good at fixing a located one** | Tyen et al., ACL-Findings 2024 (arXiv 2311.08516): LLMs "struggle... even in highly objective, unambiguous cases" at finding mistakes. Correction is robust once the location is given. | "Anything missing?" asks for the weak skill (locate), with no location given. Output is high-variance guesses. |
| F4 | **Demand characteristic / action bias: the prompt implies an item exists** | FixedBench, Gloaguen et al., SRI Lab ETH (arXiv 2605.07769; blog sri.inf.ethz.ch/blog/fixedcode). Given an issue that is **already fixed**, agents submit unnecessary patches in 35-65% of cases. Sonnet 4.6 abstained correctly only 65.0%, Gemini 3 Pro 36.5%. Cause quoted: LLMs "are trained to always find a way to 'succeed' at the task they are given". A reproduce-first instruction raised abstention (GPT-5.4 mini 60.5→88.5%, Sonnet 4.6 65.0→80.5%) but caused **false abstention** when the issue was only partially fixed. | "Find what's missing" is exactly FixedBench's setup: the task framing says "there is a defect". The model's trained success criterion is producing one. |
| F5 | **Abstention is penalized in training and evals** | OpenAI, "Why language models hallucinate" (Sept 2025): evals "reward guessing over acknowledging uncertainty". SimpleQA example: gpt-5-thinking-mini abstains 52% with 26% errors, o4-mini abstains 1% with 75% errors. Wen et al., "Know Your Limits" abstention survey, TACL 2025. | "Nothing material is missing" is an abstention-shaped answer. Absent explicit reward for it, the prior favors producing *something*. |
| F6 | **Sycophancy (toward the user's implied belief)** | Sharma et al. (Anthropic), ICLR 2024 (arXiv 2310.13548): five assistants consistently sycophantic. Humans and preference models prefer convincing sycophantic answers "a non-negligible fraction of the time". FlipFlop, Laban et al. (arXiv 2311.08596): "Are you sure?" flips answers 46% of the time on average, with a 17% average accuracy drop across 10 LLMs. SycEval (AIES 2025, arXiv 2502.08177): 58.19% sycophancy overall, 14.66% regressive (to wrong), 78.5% persistence. | The operator's repeated "are we 100.00/100.00 complete?" after prior claims carries an implied belief ("you probably missed something"). Sycophancy predicts a flip to "actually no". Repeating the question is itself the FlipFlop challenge. |
| F7 | **Reverse sycophancy / overcorrection** | arXiv 2608.26511, "Sycophancy Suppression Can Impair Rational Updating": suppressing unsupported yielding sacrifices rational updating. The two share internal circuitry. FixedBench's reproduce-first fix produced false abstention on partial fixes. arXiv 2603.18740 (Alexopoulos et al., v4 23 Sep 2026, 6 LLMs): framing vulnerable code as bug-free cut detection by 16-60 pp for most models and by 93.5 pp for GPT-4o-mini (97.2% → 3.6%). Claude Opus 4.5 was "the sole exception", with only a 6.9% decrease (§III-B1). Bug-present framing barely moved false positives, because those were already ≥88% under neutral framing (see F17). | A naive fix ("stop finding things, say we're done") swaps churn for false closure. The protocol must make *both* directions costly: unsupported additions and unsupported "done". |
| F8 | **Self-preference / self-bias in self-refinement** | Xu et al., "Pride and Prejudice", ACL 2024: self-refine "amplifies self-bias" across 6 LLMs. Panickssery et al., NeurIPS 2024: self-recognition correlates linearly with self-preference. Zheng et al. MT-Bench (NeurIPS 2023): GPT-4 about +10% self-win-rate, Claude-v1 about +25%. | Same-family reviewers approve the parts they wrote and re-find gaps in their own blind-spot pattern. Churn and blind spots coexist. |
| F9 | **LLM-as-judge instability, position and verbosity bias** | Zheng et al. 2023 (arXiv 2306.05685): position, verbosity and self-enhancement biases. Rating Roulette (Haldar & Hockenmaier, EMNLP 2025, arXiv 2510.27106): low intra-rater reliability. On MT-Bench the most reliable judge (Qwen 3) reached Krippendorff α = 0.563 against the 0.8 threshold, and "gave the same judgment on all 3 runs for only 61.3% of cases" (§4, verified in the arXiv HTML 2026-09-30). **Position bias:** Shi et al., "Judging the Judges" (arXiv 2406.07791; 15 judges, >150,000 instances) find position bias "not due to random chance" and "strongly affected by the quality gap between solutions". Bias therefore dominates exactly when candidates are close, as marginal "one more thing" items are. **Verbosity bias:** Saito et al. (arXiv 2310.10076): "GPT-4 prefers longer answers more than humans". Dubois et al. (arXiv 2404.04475): AlpacaEval "is known to favor models that generate longer outputs", which needed a regression-based length control. arXiv 2603.04417 "Same Input, Different Scores": inconsistency even at temperature 0, and the **completeness criterion shows the highest variability**. | The operator's criterion *is* completeness, the least stable judgment dimension measured. Asking twice samples the judge's noise. Verbosity bias adds a pull of its own: a longer gap list *looks* more thorough to an LLM judge or a tired human, so "found 4 more things" outranks "nothing material". |
| F10 | **Sampling variance / nondeterminism** | Thinking Machines, "Defeating Nondeterminism in LLM Inference" (Sept 2025): batch-size variation makes temperature-0 endpoints nondeterministic. Sclar et al., ICLR 2024 (arXiv 2310.11324): up to 76 accuracy points from prompt formatting alone. | A new session and a slightly reworded question is a new draw from a wide distribution of "missing items". Union over N draws grows roughly monotonically with N. |
| F11 | **Evaluator criteria drift** | Shankar et al., "Who Validates the Validators?", UIST 2024 (arXiv 2404.12272): "users need criteria to grade outputs, but grading outputs helps users define criteria". Some criteria are "dependent on the specific LLM outputs observed". | Each review round shows new material, which generates new criteria, which generates new gaps. The goalpost moves because the rubric is re-derived each time instead of frozen. |
| F12 | **Long-context and agentic-search recall limits** | Liu et al., "Lost in the Middle", TACL 2024. Chroma "Context Rot" (July 2025, 18 models): "performance grows increasingly unreliable as input length grows". Anthropic context-engineering post: "as the number of tokens... increases, the model's ability to accurately recall information from that context decreases". WideSearch (ByteDance, ICLR 2026, arXiv 2508.07999): broad info-seeking success near 0%, best 5%, while cross-validated humans approach 100%. NoLiMa (arXiv 2502.05167), where needle and question share little wording: "At 32K... 11 models drop below 50% of their strong short-length baselines", and GPT-4o falls from 99.3% to 69.7%. Recall of a *paraphrased* prior finding (the normal case for "did we already cover X?") is the degraded regime. | "Exhaustive" is precisely the task class agents fail. Each pass recalls a *different* subset, so a later pass "discovers" what an earlier pass had but lost. |
| F13 | **Loss of prior research across context windows / multi-turn** | Anthropic: "overly aggressive compaction can result in the loss of subtle but critical context whose importance only becomes apparent later" (effective-context-engineering). Anthropic long-running harness: a later agent "would look around, see that progress had been made, and declare the job done" (the mirror failure). Laban et al., "LLMs Get Lost in Multi-Turn Conversation" (ICLR 2026, arXiv 2505.06120): 39% average drop, mostly from *unreliability*, not aptitude. | A new session re-derives the gap list instead of reading the closed-items ledger, so it re-raises items already dispositioned (the operator experiences these as "new holes"). It can equally declare done prematurely. |
| F14 | **Homogeneous panels converge falsely; debate degrades** | Wynn et al., "Talk Isn't Always Cheap" (ICML-MAS 2025, arXiv 2509.05396): debate lowers accuracy over time; agents flip correct→incorrect to agree. Kim et al., "Correlated Errors in LLMs" (ICML 2025): models agree about 60% of the time when both err; same-provider and larger models are *more* correlated. (Already cited locally in SKILL.md:758-762, arXiv 2502.19559/2604.03809.) | Panel "agreement that we're complete" from same-family agents is weak evidence. Independence assumptions behind capture-recapture and panels are violated unless enforced. |
| F15 | **Generic-critique mode** | LLM peer review studies (arXiv 2412.01708; arXiv 2608.03659): reviews are "generic and paper-unspecific". 14 weakness clusters recur regardless of paper (e.g. "limited experimental scope", "scalability"). | Many "one more thing" items are template weaknesses (edge cases, scalability, observability, security) that can be generated for *any* plan. They are distinguishable only by a materiality and specificity test. |
| F16 | **Overthinking / redundant rounds in reasoning models** | Chen et al., "Do NOT Think That Much for 2+3=?" (ICML 2025, arXiv 2412.21187): o1-like models produce 2-4 solution rounds, *more on easier sets*. Later rounds add little accuracy or diversity. Self-Refine (Madaan 2023, arXiv 2303.17651): gains diminish after 2-3 iterations while cost grows linearly. | High-effort models spend budget re-litigating closed questions. Extra effort buys variance, not coverage. |
| F17 | **A neutral "review for issues" on a correct artifact still returns issues, and the mix is mostly noise with some real finds** | arXiv 2603.18740 §III-B2: on *patched* (fixed) code under **neutral** framing, "All models exhibit very high apparent false positive rates (≥ 88%)", Claude 3.5 Haiku excepted (68.4%). In a 240-sample manual check, 75% were genuine false positives and 39% of those were "factually incorrect claims about code behavior". Yet "an average of 25% (up to 57.5% for Claude Opus 4.5) of alerts on 'fixed' files were genuine bugs, unrelated to the studied CVE, that were later fixed upstream." | This is the strongest direct evidence for the operator's symptom. Ask a frontier model to look for problems in a finished artifact and it almost always reports one. For the newest models a meaningful minority are real, *but unrelated to the question asked*. Churn is therefore neither pure noise nor proof of holes: each item needs a materiality and relevance test (T5), not auto-acceptance. |
| F18 | **Agents do not know their knowledge boundary, so they over-search** | "Search Wisely" (arXiv 2505.17281, EMNLP 2025): agentic RAG shows "over-search (retrieving redundant information) and under-search". "One model could have avoided searching in 27.7% of its search steps", and inefficiency correlates with "the models' uncertainty regarding their own knowledge boundaries". AdaSearch (arXiv 2512.16883): "overreliance on search introduces unnecessary cost". | Research agents have no internal signal that says "enough". Termination has to be imposed from outside (T9-T11) or trained in. It will not emerge from asking. |
| F19 | **Vendor-acknowledged over-eagerness in current Claude models** | Anthropic prompting best practices, "Overeagerness": "Claude Opus 4.5 and Claude Opus 4.6 have a tendency to overengineer by creating extra files, adding unnecessary abstractions, or building in flexibility that wasn't requested." The vendor fix is a scope clause: "Only make changes that are directly requested or clearly necessary." (platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices, fetched 2026-09-30) | The same scope-expansion prior carries over to plans: unasked-for "flexibility" and "hardening" items read as gaps. The vendor's fix is a scope clause, which is the prompt-level form of the materiality gate. |

**Composite causal story.** The loop is F4+F5 (the prompt demands an item and abstention is unrewarded), fed by F9+F10 (each ask is a fresh noisy draw), with F11 (criteria re-derived per round) and F12/F13 (prior dispositions not recalled) turning every draw's novelty into an apparent hole. F6 amplifies it once the operator has repeated the question. F1-F3 explain why iterating does not converge: there is no external oracle, and the models are weak at locating true gaps. F17 sets the base rate: asked to review a finished artifact, current models flag something about 9 times in 10, and a minority of those flags are real but off-question. F18 and F19 explain why no internal stop signal appears: agents do not know their knowledge boundary, and the current Claude models carry a vendor-documented scope-expansion prior.

---

## 2. Techniques that give stable answers (evidence and what each fixes)

| Technique | Evidence | Fixes |
|---|---|---|
| **T1 Fixed, closed checklist of Boolean items** (decomposed criteria, frozen before review) | CheckEval (EMNLP 2025, arXiv 2403.18771): decomposed binary checklist raised inter-evaluator agreement by **+0.45** and cut score variance across 12 evaluator models. Anthropic multi-agent research: "A single LLM call with a single prompt outputting scores from 0.0-1.0 and a pass-fail grade was the most consistent and aligned with human judgements." | F9, F10, F11, F15 |
| **T2 Answer from a persisted ledger, never regenerate** | Anthropic long-running harness: the initializer writes "a comprehensive file of feature requirements"; "the model is less likely to inappropriately change or overwrite JSON files compared to Markdown files"; "It is unacceptable to remove or edit tests"; fresh windows recover state via `claude-progress.txt` plus git. Anthropic multi-agent: agents "retrieve stored context like the research plan from their memory rather than losing previous work". | F12, F13, and re-raising of dispositioned items |
| **T3 Explicit, rewarded abstention / "nothing material" as a first-class answer** | Anthropic hallucination guide: "Explicitly give Claude permission to admit uncertainty... can drastically reduce false information"; "If you can't find a supporting quote... remove that claim". OpenAI (2025): reward calibrated abstention. FixedBench: reproduce-first raised correct abstention +15.5 to +28 pp, and making inaction "an explicitly valued outcome" is the authors' prescription. | F4, F5 |
| **T4 Evidence-anchored items (quote or path required, else retract)** | Anthropic guide ("verify with citations"; retract unsupported claims). Chain-of-Verification (Dhuliawala et al., arXiv 2309.11495): answering verification questions *independently* ("factored") reduced hallucinations most. | F3, F15 (generic items cannot cite a specific locus) |
| **T5 Materiality gate** ("would this change a decision, and which one?") | Audit standard ISA 320: misstatements "including omissions, are considered to be material if they... could reasonably be expected to influence the economic decisions of users". The same test ports directly: an omission is material only if it would change a named plan decision. Value-of-information logic underlies the optimal-stopping result below. | F15, F16, trivial "one more thing" |
| **T6 "Why was this not in the frame?" justification** | Derived from criteria drift (Shankar 2024). A new item must be classed as (a) missed by the frozen checklist (a checklist defect, so it goes back to the checklist owner, not straight into scope), (b) a new fact since freeze (changelog, release), or (c) previously dispositioned (cite the ledger row, then reject). | F11, F13 |
| **T7 Self-consistency / independent-sample agreement with adaptive stopping** | Wang et al., self-consistency (ICLR 2023): majority vote over diverse samples, +17.9% GSM8K. Adaptive-Consistency (Aggarwal et al., EMNLP 2023, arXiv 2305.11860): stop sampling when the posterior that the leader beats the runner-up clears a threshold; up to 6× fewer samples with <0.1% accuracy loss. Kadavath et al. 2022 (arXiv 2207.05221): P(True) calibration improves "when we allow models to consider many of their own samples". Anthropic guide: "Best-of-N verification... Inconsistencies across outputs could indicate hallucinations." | F10 (turns noise into a measurable signal: an item raised by 1 of N independent samples is noise until corroborated) |
| **T8 Independent heterogeneous panel with an agreement threshold** | PoLL (Verga et al., arXiv 2404.18796): a panel of diverse-family models beats a single large judge, with "less intra-model bias". Caveat: Kim et al. ICML 2025, errors correlate within providers and among large models. Debate *degrades* (Wynn 2025), so panelists must be blind to each other. | F8, F9, F14 |
| **T9 Quantitative saturation stopping rule** | Guest, Namey & Chen, PLOS ONE 2020: saturation = **base size** (default 4), **run length** (2-3), **new-information threshold** (≤5% or 0%). Guest 2006: 92% of themes by interview 12. Hennink & Kaiser 2022 systematic review: saturation at 9-17 interviews. | Replaces "does it feel complete?" with a counted curve |
| **T10 Capture-recapture estimate of undiscovered items** | Software inspection (Eick et al., ICSE 1992; Briand, El Emam et al., TSE 2000) and systematic-review stopping (Chao estimator, arXiv 2404.01176; confidence-based stopping, arXiv 2606.15380). With two *independent* reviewers finding n1 and n2 items with m overlap, Lincoln-Petersen N̂ ≈ n1·n2/m and residual ≈ N̂ − |union|. **Caveat:** Briand et al. found estimates unreliable with few inspectors, and LLM reviewer correlation (F14) biases N̂ *downward*. Treat it as a floor, use ≥3 heterogeneous reviewers, and prefer Chao-type estimators. | Gives a numeric "expected remaining" to set against a threshold |
| **T11 Optimal stopping on expected improvement vs cost** | Hammar, Alpcan & Lupu, "Optimal Stopping of Self-Refining Foundation Models" (arXiv 2608.10729, Aug 2026): a threshold policy on expected improvement relative to cost is "significantly more cost-efficient" than prior stopping policies. Anthropic "Building effective agents": evaluator-optimizer fits "when we have clear evaluation criteria"; agents commonly carry "stopping conditions (such as a maximum number of iterations)". | F1, F16 |
| **T12 Factor the question; ask it once per item, never globally** | Tyen 2024 (locate vs correct); CoVe factored variant; Laban 2025 (fully specified single-turn beats multi-turn). | F3, F13 |
| **T13 Calibrated abstention with a statistical guarantee (sampling-based, not verbalized)** | Conformal abstention (Yadkori et al., NeurIPS 2024, arXiv 2405.01563) uses the LLM "to self-evaluate the similarity between each of its sampled responses" and then conformal prediction to give "rigorous theoretical guarantees on the hallucination rate". Semantic entropy (Farquhar, Kossen, Kuhn & Gal, *Nature* 630:625-630, 2024) samples N answers, clusters them by meaning (bidirectional entailment) and treats high entropy as confabulation. Universal Self-Consistency (Chen et al., arXiv 2311.17311) extends majority vote to **free-form** outputs such as gap lists: "USC effectively utilizes multiple samples" where answer extraction is impossible. | F5, F10. A gap raised in 1 of N samples, sitting in its own semantic cluster, is the measurable signature of a confabulated "one more thing". Calibrate the threshold once on a labelled set of past raised items (real vs churn), then apply it mechanically. |
| **T14 Binary pass/fail judgments with written critiques, calibrated to one human expert** | Practitioner: Hamel Husain, "Creating a LLM-as-a-Judge That Drives Business Results" (hamel.dev/blog/posts/llm-judge): 1-5 scales are "uncalibrated... What makes something a 3 versus a 4? Nobody knows". The prescription is "Don't stray from binary pass/fail judgments" plus a critique, iterating the judge prompt until it agrees with the domain expert. Converges with CheckEval (T1) and Anthropic's single pass-fail grader (T1). | F9, F11. The operator acts as the domain expert *once*, at freeze, labelling what "complete" means for each dod item. Later checks are graded against those labels, not re-derived. |
| **T15 Vendor pattern: success criteria first, persisted notes, bounded self-critique** | Anthropic prompting best practices, "Research and information gathering": "Provide clear success criteria: Define what constitutes a successful answer to your research question". The sample prompt says "Track your confidence levels in your progress notes to improve calibration. Regularly self-critique your approach and plan. Update a hypothesis tree or research notes file to persist information". For multi-window work: "Review progress.txt, tests.json, and the git logs." | F1 (self-critique is safe only when bounded by success criteria), F13. Note that the vendor pairs self-critique with success criteria and persistence. The operator's loop keeps the critique and drops the other two. |

**Ruled out or down-weighted:**
- **Multi-agent debate as a completeness check.** It degrades accuracy through conformity (Wynn 2025; arXiv 2606.00820 reports 57-77% of conformity flips going correct→wrong).
- **"Two consecutive waves agree" as a stop rule.** The operator's own SKILL.md:758-762 already rejects this, correctly.
- **Verbalized confidence alone as the gate.** It is overconfident (Xiong 2024); use it only alongside sample agreement.
- **"Just tell it to be decisive / say we're done".** It triggers F7 false closure (FixedBench partial-fix abstentions; arXiv 2603.18740).

---

## 3. What the protocol and prompt must literally say

### 3.1 Freeze phase (once, before research starts; human-signed)

1. **Definition-of-Done checklist file (JSON, not markdown; per T2):** `dod.json`, one Boolean item per row, each with `id`, `question`, `acceptance_evidence` (what artifact proves yes), `decision_it_serves`. Items are phrased to be answerable yes/no with a receipt (CheckEval-style decomposition).
2. **Decision register:** the named decisions the research exists to settle (stack, architecture, scope, and so on). Materiality is defined *relative to this list*.
3. **Axis coverage map** with a saturation parameter set: base 4, run 2, threshold 0 new *material* items (Guest 2020).
4. **Change control:** after freeze, `dod.json` may gain an item only through a logged **checklist-defect** entry carrying the T6 justification and operator sign-off. Removal requires the same.

### 3.2 Ledger (persisted, append-only)

`gaps.jsonl`, one row per raised item: `{id, text, raised_by (session/agent/model), raised_at, evidence_path_or_quote, decision_affected, materiality: material|immaterial, frame_class: checklist-defect|new-fact|already-dispositioned|out-of-scope, disposition, disposed_at}`. **Every completeness question is answered by reading this file and `dod.json`, never by regeneration.** A new session's first act is to load both (Anthropic harness pattern).

### 3.3 The completeness prompt (replaces "are we 100% complete / anything missing?")

Verbatim template for the checker:

> You are auditing completeness against a FROZEN checklist, not brainstorming.
> Inputs: `dod.json` (frozen), `decisions.md`, `gaps.jsonl` (all previously raised items and their dispositions), and the research artifacts.
> 1. For EACH `dod.json` item, answer YES / NO / UNKNOWN, with the artifact path or quote that proves it. No receipt ⇒ UNKNOWN, never YES.
> 2. Then, and only then, you MAY propose new items. **Proposing zero new items is a correct and expected outcome; you are not rewarded for finding something.** Each proposed item MUST carry all four of:
>    (a) a specific locus: file:line, URL or quote (generic concerns like "scalability" or "edge cases" without a locus are rejected);
>    (b) the named decision in `decisions.md` whose choice would CHANGE if this item resolved the other way, and how (if none would change, the item is immaterial: log it as such and do not escalate);
>    (c) its frame class: `checklist-defect` (why did the frozen checklist miss it?), `new-fact` (cite the post-freeze source and date), or `already-dispositioned` (cite the `gaps.jsonl` id; then drop it);
>    (d) your probability that the item is real and material, and what evidence would falsify it.
> 3. Do not re-raise any item whose id appears in `gaps.jsonl` with a disposition, unless you cite NEW evidence dated after that disposition.
> 4. Final line: `COMPLETE` if every dod item is YES and no new material item survived (b); otherwise `INCOMPLETE: <dod ids NO/UNKNOWN>; <new material item ids>`.

Why each clause exists:
- "zero is expected" counters F4/F5.
- The locus requirement counters F3/F15.
- The decision-change test is ISA-320 materiality, against F15/F16.
- The frame class counters F11/F13.
- No re-raise without new evidence counters F13 and F6.
- The probability plus falsifier clause counters F5 with Xiong-style overconfidence in mind; it is **never used alone**.

### 3.4 Running the check (statistics, not one opinion)

- **N ≥ 3 independent checkers**, blind to each other, **heterogeneous** (different model families or effort tiers where available; at minimum, different framings and seeds). Per F14 and Kim 2025, same-family agreement is weak.
- A new item counts only if **≥2 of N raise it independently** (self-consistency, T7), **or** one raises it with a receipt that a separate verifier confirms by reproduction (FixedBench reproduce-first, T3). Single-sample items go into the ledger as `unconfirmed`, not into scope. For free-form gap lists, first cluster the N checkers' items by meaning (semantic-entropy-style bidirectional entailment, or a USC selection pass; T13), then count cluster support. Do not count string matches.
- **Capture-recapture:** from the checkers' material-item sets, compute N̂ (Chao1 or Lincoln-Petersen) and residual expected items. Stop when residual < ε (for example 0.5), **and** the saturation run (2 consecutive rounds) yields 0 new material items (Guest 2020). Because LLM errors correlate, treat N̂ as a lower bound and require the heterogeneous-panel condition.
- **Adaptive sampling:** add checkers only while the posterior over "new material item exists" is undecided (Adaptive-Consistency), with a hard cap on rounds (Anthropic "maximum number of iterations"; Hammar 2026 threshold policy).

### 3.5 How the operator should ask

- Replace "are we 100.00/100.00 complete?" with: "Run the completeness audit against dod.json and gaps.jsonl; report COMPLETE or the INCOMPLETE line." This removes the implied-belief challenge that drives FlipFlop/SycEval flips (F6), and routes the question to the ledger rather than a fresh generation (F13).
- **Do not re-ask the same question in the same session after a COMPLETE.** Repeating the challenge is the FlipFlop protocol: 46% flip rate and a 17% average accuracy drop.

---

## 4. Where the operator's current machinery encodes the failure

Read-only observations of local files:

| Local text | Receipt | Literature conflict | Suggested replacement |
|---|---|---|---|
| "Find 2-3 gaps. Investigate them with real tool calls" | `/Users/chrisren/Development/claude-infrastructure/agents/deep-research.md:187` and `agents/deep-research-sonnet.md:97` (re-verified 2026-09-30 by `sed -n`; the same sentence sits in the system prompt of the agent that wrote this report) | Quota prompt: guarantees ≥2 items regardless of truth (F4, FixedBench action bias; Huang 2024 "find problems" prompt) | "List any gaps that pass the locus + decision-change test; zero is an expected answer." |
| "What dimensions am I NOT exploring, and why not? List 3 with reasons." | `~/.claude/skills/research-subagents/SKILL.md:353, :798` | Same quota effect, once per invocation, forever | Same zero-allowed wording, plus the frame-class requirement |
| "If any reason is 'I forgot' or 'not obviously relevant' → promote into scope, spawn the missing subagent(s)" | `SKILL.md:800-801` | No materiality gate: every generated dimension auto-expands scope. This is the goalpost mover (F11, F15) | Promote only if the item names a decision it would change (ISA-320-style test). Otherwise log it as immaterial in the ledger. |
| OASIS "Adversarial null: ... 'what am I missing' returns refinements only, no new axis" | `SKILL.md:771-772` | The stop condition depends on a demand-characteristic prompt returning nothing, which the literature says it rarely will (F1, F4, F5). The stop condition is therefore rarely satisfiable, which matches the operator's symptom. | Replace with the capture-recapture residual plus 0-new-material-in-run-2 rule (§3.4), computed over *material* items only |
| OASIS already rejects "two waves agree" because homogeneous committees collapse | `SKILL.md:758-762` | Consistent with Kim 2025 and Wynn 2025 (keep) | Keep; add heterogeneity to the panel requirement |

---

## 5. Adversarial self-pass (gaps checked with real calls)

1. **"Isn't some of the churn real, i.e. the research genuinely was incomplete?"** Yes, partly. WideSearch shows exhaustive collection really is weak (≤5%), so some new items are true misses (F12). The protocol does not suppress them. It routes them through `checklist-defect` (fix the checklist once, with a reason) instead of silently widening scope. The capture-recapture residual quantifies how many true misses to expect. That is the honest answer to "are we 100%": an estimate with a bound, never a certainty.
2. **"Won't anti-churn prompting cause false closure?"** Verified. FixedBench's reproduce-first instruction produced wrong abstentions on partial fixes (arXiv 2605.07769). Bug-free framing cut vulnerability detection 16-93% (arXiv 2603.18740). Anti-sycophancy impairs rational updating (arXiv 2608.26511). Hence §3.3 keeps a *symmetric* evidence burden: YES needs a receipt, and a new item needs a receipt. UNKNOWN is its own state.
3. **"Do panels and capture-recapture actually give independent estimates with LLMs?"** Only partially. Kim et al. (ICML 2025) find about 60% error agreement and higher correlation among large, same-provider models. Briand et al. (TSE 2000) found capture-recapture unreliable with few inspectors. Mitigation: heterogeneous families, ≥3 reviewers, treat N̂ as a floor, and pair it with the saturation run rule rather than relying on it alone.
4. **Discrepancy found in a secondary source.** agentpatterns.ai states reproduce-first moves "GPT-5.4 mini from 24% to 77%" and that agents patch "already-passing code >50%". The primary SRI blog and arXiv abstract say 60.5→88.5% and a 35-65% failure range. This report uses the primary numbers.

5. **Post-reboot verification pass (2026-09-30, second run; this file was restored from the pre-reboot run and extended with Edit, not rewritten).** Primary sources were re-fetched from arXiv abs or HTML and the quoted numbers grepped:
   - Confirmed: Huang 2024 Table 3 (75.8 → 38.1 → 41.8) and the "more likely to modify a correct answer" quote. FixedBench abstract (35-65%, "action bias", "inaction needs to be explicitly framed as a path to success"). 2603.04417 ("completeness scoring showing the largest fluctuations"). 2608.10729 (Hammar, Alpcan, Lupu, submitted 11 Aug 2026). Rating Roulette 61.3%.
   - Corrected: Rating Roulette's 61.3% is Qwen 3, the most reliable of the 3 judges tested (α 0.563), not a frontier model. 2603.18740's "16-93%" is now split into 16-60 pp for most models, 93.5 pp for GPT-4o-mini and 6.9% for Opus 4.5. The earlier "false positives little changed" is now explained by the ≥88% neutral baseline.
   - Added: F17-F19 and T13-T15, answering the hostile-reviewer question "does this still hold on current frontier models, and isn't some churn real?" The answer, from 2603.18740: newer models resist bug-free framing better (Opus 4.5 -6.9%), and more of their unprompted flags are real (up to 57.5%). That strengthens the case for a materiality and relevance gate over a blanket "stop finding things".

**Residual uncertainties:**
- No located paper measures "are we complete?" churn on *planning documents* specifically. The mechanism is inferred from adjacent measured tasks: self-correction, FixedBench, judge consistency.
- The CheckEval +0.45 agreement gain is on NLG evaluation, not plan audits.
- The Rating Roulette and 2603.04417 numbers are on older or other-family models. No Opus 5.5 or Fable 5.1 measurement was found.
- The optimal-stopping paper (2608.10729) is a fresh preprint on a coding benchmark.

---

## 6. Sources

Papers:
- Huang et al., LLMs Cannot Self-Correct Reasoning Yet, ICLR 2024: https://arxiv.org/abs/2310.01798 (html v2 for quotes)
- Kamoi et al., When Can LLMs Actually Correct Their Own Mistakes?, TACL 2024: https://arxiv.org/abs/2406.01297
- Tyen et al., LLMs cannot find reasoning errors..., ACL-F 2024: https://arxiv.org/abs/2311.08516
- Gloaguen et al., Coding Agents Don't Know When to Act (FixedBench): https://arxiv.org/abs/2605.07769 ; https://www.sri.inf.ethz.ch/blog/fixedcode
- OpenAI, Why language models hallucinate (Sept 2025): https://openai.com/index/why-language-models-hallucinate/
- Wen et al., Know Your Limits (abstention survey), TACL 2025: https://aclanthology.org/2025.tacl-1.26
- Sharma et al., Towards Understanding Sycophancy, ICLR 2024: https://arxiv.org/abs/2310.13548
- Laban et al., Are You Sure? FlipFlop: https://arxiv.org/abs/2311.08596
- SycEval, AIES 2025: https://arxiv.org/abs/2502.08177
- Sycophancy Suppression Can Impair Rational Updating: https://arxiv.org/abs/2608.26511
- Contextual bias in LLM security code review: https://arxiv.org/abs/2603.18740
- Xu et al., Pride and Prejudice, ACL 2024: https://aclanthology.org/2024.acl-long.826
- Panickssery et al., LLM Evaluators Recognize and Favor Their Own Generations, NeurIPS 2024: https://arxiv.org/abs/2404.13076
- Zheng et al., Judging LLM-as-a-Judge (MT-Bench), NeurIPS 2023: https://arxiv.org/abs/2306.05685
- Haldar & Hockenmaier, Rating Roulette, EMNLP-F 2025: https://arxiv.org/abs/2510.27106
- Same Input, Different Scores: https://arxiv.org/abs/2603.04417
- Sclar et al., prompt-format sensitivity, ICLR 2024: https://arxiv.org/abs/2310.11324
- Thinking Machines, Defeating Nondeterminism in LLM Inference (Sept 2025): https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/
- Shankar et al., Who Validates the Validators?, UIST 2024: https://arxiv.org/abs/2404.12272
- Liu et al., Lost in the Middle, TACL 2024: https://arxiv.org/abs/2307.03172
- Chroma, Context Rot (July 2025): https://trychroma.com/research/context-rot
- WideSearch, ICLR 2026: https://arxiv.org/abs/2508.07999
- Laban et al., LLMs Get Lost in Multi-Turn Conversation: https://arxiv.org/abs/2505.06120
- Wynn et al., Talk Isn't Always Cheap: https://arxiv.org/abs/2509.05396
- Not All Flips Are Conformity: https://arxiv.org/abs/2606.00820
- Kim et al., Correlated Errors in LLMs, ICML 2025: https://arxiv.org/abs/2506.07962
- LLM peer-review risks: https://arxiv.org/abs/2412.01708 ; https://arxiv.org/abs/2608.03659
- Chen et al., Do NOT Think That Much for 2+3=?, ICML 2025: https://arxiv.org/abs/2412.21187
- Madaan et al., Self-Refine: https://arxiv.org/abs/2303.17651
- Hammar et al., Optimal Stopping of Self-Refining Foundation Models (Aug 2026): https://arxiv.org/abs/2608.10729
- CheckEval, EMNLP 2025: https://arxiv.org/abs/2403.18771
- Wang et al., Self-Consistency: https://arxiv.org/abs/2203.11171
- Aggarwal et al., Adaptive-Consistency, EMNLP 2023: https://arxiv.org/abs/2305.11860
- Kadavath et al., LMs (Mostly) Know What They Know: https://arxiv.org/abs/2207.05221
- Xiong et al., Can LLMs Express Their Uncertainty?, ICLR 2024: https://arxiv.org/abs/2306.13063
- Verga et al., Replacing Judges with Juries (PoLL): https://arxiv.org/abs/2404.18796
- Dhuliawala et al., Chain-of-Verification: https://arxiv.org/abs/2309.11495
- Guest, Namey & Chen 2020, thematic saturation: https://pmc.ncbi.nlm.nih.gov/articles/PMC7200005/
- Hennink & Kaiser 2022 / Guest 2006 (via FHI360 summary): https://researchforevidence.fhi360.org/riddle-me-this-how-many-interviews-or-focus-groups-are-enough
- Chao's estimator as TAR stopping criterion: https://arxiv.org/abs/2404.01176 ; Confidence-based stopping: https://arxiv.org/abs/2606.15380
- Briand/El Emam capture-recapture comparison: https://ehealthinformation.ca/web/default/files/wp-files/isern-98-11.pdf
- Alexopoulos et al., Measuring and Exploiting Contextual Bias in LLM-Assisted Security Code Review (v4, Sep 2026): https://arxiv.org/html/2603.18740
- Shi et al., Judging the Judges: A Systematic Study of Position Bias in LLM-as-a-Judge: https://arxiv.org/abs/2406.07791
- Saito et al., Verbosity Bias in Preference Labeling by LLMs: https://arxiv.org/abs/2310.10076
- Dubois et al., Length-Controlled AlpacaEval: https://arxiv.org/abs/2404.04475
- NoLiMa: Long-Context Evaluation Beyond Literal Matching: https://arxiv.org/abs/2502.05167
- Search Wisely: Mitigating Sub-optimal Agentic Searches (over-search): https://arxiv.org/abs/2505.17281 ; AdaSearch: https://arxiv.org/abs/2512.16883
- Yadkori et al., Mitigating LLM Hallucinations via Conformal Abstention (NeurIPS 2024): https://arxiv.org/abs/2405.01563
- Farquhar, Kossen, Kuhn & Gal, Detecting hallucinations in LLMs using semantic entropy, Nature 630:625-630 (2024): https://doi.org/10.1038/s41586-024-07421-0 (metadata via api.crossref.org)
- Chen et al., Universal Self-Consistency: https://arxiv.org/abs/2311.17311

Practitioner:
- Hamel Husain, Creating a LLM-as-a-Judge That Drives Business Results (Critique Shadowing; binary pass/fail): https://hamel.dev/blog/posts/llm-judge/

Vendor docs:
- Anthropic, Effective harnesses for long-running agents: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Anthropic, How we built our multi-agent research system: https://www.anthropic.com/engineering/multi-agent-research-system
- Anthropic, Effective context engineering for AI agents: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Anthropic, Building effective agents: https://www.anthropic.com/engineering/building-effective-agents
- Anthropic, Reduce hallucinations: https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations
- Anthropic, Claude prompting best practices ("Overeagerness", "Research and information gathering", multi-window "tests.json"): https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

Standard:
- ISA 320 materiality (FRC UK): https://www.frc.org.uk/getattachment/163782e0-f168-4992-9cd3-c22dee7ce22f/ISA-(UK)-320_Revised-June-2016_Updated-May-2022.pdf
