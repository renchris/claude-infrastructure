# A6 — Benchmarks that actually predict web visual-design-review competence

**Read date for every leaderboard cited: 2026-08-26.** Agent A6. Scope: which published
benchmarks predict competence at *reviewing* web visual design, and where those benchmarks
currently stand.

---

## 0. The headline, before the tables

**Three findings dominate everything below.**

1. **Our task is JUDGEMENT; almost every benchmark measures GENERATION or GROUNDING.**
   Design2Code, WebSight, UI-Bench, DesignBench measure *producing* UI. ScreenSpot measures
   *finding a named target*. Only two benchmarks in existence measure a model's ability to
   *evaluate* a design — WebDevJudge and AesEval-Bench — and both report that frontier models
   fail at it.

2. **The public "current standings" for these benchmarks are largely unusable.** The official
   CharXiv leaderboard has been frozen since **2024-12-25**. The ScreenSpot-Pro leaderboard on
   llm-stats.com self-declares **"0 verified results, 25 self-reported"** and blanket-cites the
   2025 benchmark paper as the source for scores of models released in 2026 — a citation that
   cannot be true. Aggregators disagree with vendor system cards by **14 points** on the same
   model (below, section 3). Treat any 2026 number for these benchmarks as vendor self-report
   until proven otherwise.

3. **The benchmark most likely to mislead us is ScreenSpot-v2, and I can quantify it.** In H
   Company's own primary results table, five models spanning **38.5% -> 66.1% on ScreenSpot-Pro**
   (a 27.6-point spread) all score **91.5% -> 94.9% on ScreenSpot-v2** (a 3.4-point spread).
   ScreenSpot-v2 is saturated to the point of being a coin-flip for model selection while looking
   like a decisive 90%+ signal. Full mechanism in section 6.

---

## 1. Benchmark relevance table

Columns: what it measures - why it does/does not predict design-review skill - current best score
with model + date read - split - provenance flag.

### Tier A — genuinely predictive of design review

| Benchmark | What it measures | Predicts design review? | Current best (read 2026-08-26) | Split | Provenance |
|---|---|---|---|---|---|
| **WebDevJudge** ([arXiv 2510.18560](https://arxiv.org/html/2510.18560v1)) | MLLM-as-judge agreement with expert humans on **paired running web apps** — functionality *and* aesthetics | **YES — this is our task, almost exactly.** Pairwise preference over rendered, interactive web artifacts | **Human 84.82%**; best models GPT-4.1 **66.06%** and Claude-4-Sonnet **66.06%**; Claude-3.7-Sonnet 65.14%; DeepSeek-V3 63.61%; Gemini-2.5-Pro 62.23% | 654 instances (filtered 10,501 -> 1,713 -> 654) | Paper-reported, ICLR 2026. Inter-annotator agreement 89.7% w/ ties, 94.0% w/o — unusually strong |
| **AesEval-Bench** ([arXiv 2603.01083](https://arxiv.org/abs/2603.01083), 2026-03-01) | Graphic-design **aesthetics**: 4 dimensions (layout, color, font, graphics), 12 indicators, 3 tasks — aesthetic judgment, region selection, **precise localization of the defect** | **YES — the only benchmark that scores "find the aesthetic flaw and point at it"** | Aesthetic judgment: **GPT-5 0.7252**; GPT-o3 0.7105; GPT-4o 0.7031. Region selection: GPT-5 **0.6989**. **Precise localization (bbox IoU): GPT-5 0.1993** <- see section 6 | ~4,500 QA pairs (3 tasks x 1,500 designs), Crello test split | Paper-reported. Ground truth = majority vote over annotators on *perturbed* designs; annotator count + IAA **not reported** — a real weakness |
| **ScreenSpot-Pro** ([arXiv 2504.07981](https://arxiv.org/abs/2504.07981)) | Localize a **named** text/icon target in a high-res professional screenshot. 1,581 instructions, 23 apps, 3 OSes | **PARTIALLY.** Best available proxy for precise localization + small-target fidelity at real screen resolution. But it is *search for a named thing*, not *detection of an unnamed defect* — see section 6 | Vendor system card: Opus 4.6 **69.0%** -> Opus 4.7 **79.5%**. Best open-weight: Holo2-235B-A22B **70.6%** (1-step) / 78.5% (3-step); Holo2-30B-A3B **66.1%**. Aggregators claim Opus 4.8 87.9% — **uncorroborated, contradicted** (section 3) | Full set; greedy decoding | **Mixed and contested.** Vendor self-report vs aggregator numbers differ by 14pp |
| **OCRBench v2** ([official](https://99franklin.github.io/ocrbench_v2/), snapshot **2026.06**) | 23 sub-tasks / 8 capabilities incl. **Spotting** (text localization), Recognition, Parsing, Extraction | **PARTIALLY — the best small-text-fidelity proxy**, because it scores *localization of text*, not just reading it | EN: Yaochi-DTS-A2T-1.9 **73.4**, Posicube_DVLM 69.8, KDL Frontier 68.1, NVIDIA Nemotron 3 Nano **65.8** (open), Qwen3.6-35B-A3B **65.5** (open). ZH: TeleMM-2.0 66.2 | Quarterly-refreshed leaderboard, EN and ZH tracks | Official + actively maintained (**rare — most here are not**). But top slots are **OCR-specialist submissions we would never deploy** (section 6) |

### Tier B — measures a real sub-skill, but saturated or indirect

| Benchmark | What it measures | Predicts design review? | Current best (read 2026-08-26) | Split | Provenance |
|---|---|---|---|---|---|
| **BLINK** | 14 classic CV tasks -> 3,807 MCQs: relative depth, correspondence, multi-view, counting, **object localization, spatial reasoning** | **WEAK-POSITIVE.** Closest thing to a fine-visual-discrimination probe, but MCQ format and non-UI imagery | Seed 2.1 Pro **0.814**; best open-weight Qwen3-VL-235B-A22B-Instruct **0.707** (rank 3 of 13). **Human 95.70%** | val | [llm-stats](https://llm-stats.com/benchmarks/blink) aggregate, self-reported. Original paper baselines: GPT-4V 51.26%, Gemini 45.72% |
| **Design2Code** ([arXiv 2403.03163](https://arxiv.org/abs/2403.03163), NAACL 2025) | Screenshot -> HTML/CSS. Metrics: CLIP score, block-match, text/position/color similarity, CW-SSIM, TreeBLEU | **WEAK.** Fidelity of *generation* != ability to *spot* an infidelity. And see contamination below | GLM-5V-Turbo **0.948**; Qwen3-VL-235B-A22B-Thinking 0.934. (benchlm additionally lists Kimi K2.5 91.3%, Claude Opus 4.6 77.3%) | Test-only, 484 pages | FLAG: [llm-stats](https://llm-stats.com/benchmarks/design2code) states **"0 verified results and 2 self-reported results."** FLAG: **contamination by construction** — curated from the **C4 validation set**, a standard pretraining corpus |
| **MMMU-Pro** ([Artificial Analysis](https://artificialanalysis.ai/evaluations/mmmu-pro)) | 3,460 expert questions, 30 disciplines, 10 options, vision-only condition | **NO for our purposes** — but it is the *least bad* aggregate, and AA is the one source that **runs evals itself** | Gemini 3.7 Flash (high) **85%**; Gemini 3.7 Flash (low) 85%; **Claude Opus 5 (Adaptive Reasoning, Max Effort) 85%** | standard + vision-only | GOOD: **"All evaluations are conducted independently by Artificial Analysis"** — highest-credibility source found. benchlm separately claims GPT-5.4 Pro 94% — not corroborated |
| **CharXiv** ([official](https://princeton-nlp.github.io/CharXiv/)) | Chart reasoning + descriptive Q on real scientific figures — small text, dense annotation | **WEAK-POSITIVE** for small-text/chart fidelity | WARNING: **official leaderboard last updated 2024-12-25**: Claude 3.5 Sonnet Reasoning **60.20%** / Descriptive 84.30%; GPT-4o 47.10/84.45. **Human 80.50 / 92.10** | **validation** | WARNING: **official board abandoned ~20 months.** benchlm claims Claude Mythos 5 93.5% (2026-08-03) — Mythos 5 is **restricted-access to vetted partners**, so a public third party could not have run it |

### Tier C — do not track (with the reason)

| Benchmark | Verdict | Reason |
|---|---|---|
| **ScreenSpot / ScreenSpot-v2** | **Actively misleading** | **Saturated.** Holo2 primary table: models spanning 38.5-66.1% on ScreenSpot-Pro all land 91.5-94.9% on ScreenSpot-v2. Qwen-GUI-3B (a **3B** model) hits 86.4%. See section 6 |
| **WebSight** | **Not a benchmark at all** | It is a **synthetic training dataset** — 823K pairs (v0.1) -> 2M pairs — built by HuggingFaceM4 to *fine-tune* screenshot->HTML models. No leaderboard, no test split, and synthetic pages do not resemble real design ([HF](https://huggingface.co/datasets/HuggingFaceM4/WebSight), [arXiv 2403.09029](https://arxiv.org/abs/2403.09029)) |
| **UI-Bench** ([arXiv 2508.20410](https://arxiv.org/abs/2508.20410)) | **Wrong subject** | Ranks **text-to-app tools**, not models, with *humans* as the judges. Current board: Orchids 30.08, Figma Make 27.46, Lovable 27.14, Anything 25.46, Bolt 24.44, Magic Patterns 24.23, Same.new 23.57, Base44 23.47, v0 22.24, Replit 20.95 (n=4,047 blinded pairwise matches). Tells us which *product* designs well; says nothing about which *model* reviews well |
| **VisualWebArena / WebVoyager / WebCanvas** | **Measures the scaffold** | WebArena progress 14% (2023) -> 71.6% (2025, OpAgent) is *"almost entirely from better agent scaffolding, memory, and planning."* WebVoyager rows swing by "evaluator, harness, attempt budget, tool access, task filtering" — one tracker shows GLM-5V-Turbo 88.5%, another shows a *scaffold* ("Alumnium") at 98.5%. Useful datum only: VisualWebArena agents drop to **~16-36% vs 89% human** once tasks need visual matching |
| **VSR / CV-Bench / MMVP / SpatialEval / RealWorldQA** | **No live leaderboard** | All 2023-24 artifacts that survive only as *rows inside papers*, not maintained boards. No 2026 standings exist to read. CV-Bench 2,638 examples; MMVP only **300** images (too small to separate frontier models); VSR 10k/65 relations; SpatialEval 13k. Their content is subsumed by BLINK |
| **MMMU (non-Pro)** | **Known-broken** | ~**30% of original MMMU questions are answerable from text alone, no image required.** This is precisely the "MMMU-style aggregate" the brief rules out — and the reason is now documented, not just suspected |

---

## 2. The 3-5 benchmarks we should actually track

Ranked by decision value for *design review*, not by popularity.

1. **WebDevJudge** — the only benchmark whose task *is* ours (judge a rendered web artifact
   against a human expert). Track the human-vs-model agreement gap; that gap is our error bar.
2. **AesEval-Bench** — the only benchmark scoring aesthetic judgement *and* defect localization
   in the same harness. Its localization IoU is the single most alarming number in this report.
3. **ScreenSpot-Pro** — our precise-localization / small-target regression test. Track it, but
   read only **vendor system cards and model-developer releases**, never the aggregators.
4. **OCRBench v2 (Spotting + Recognition sub-scores)** — small-text fidelity, and the only
   actively-maintained official board in the set. Track the *sub-scores*, not the composite.
5. *(optional 5th)* **MMMU-Pro via Artificial Analysis only** — not because it predicts design
   review, but because it is the one independently-run number, useful as a sanity floor to
   detect a model that is broadly weak at vision.

**Drop entirely:** ScreenSpot-v2, WebSight, UI-Bench, VisualWebArena/WebVoyager/WebCanvas,
MMMU, CV-Bench/MMVP/VSR/SpatialEval/RealWorldQA, and Design2Code as a *primary* signal.

---

## 3. Contamination and self-report flags (explicit, per the brief)

| Flag | Evidence |
|---|---|
| **Design2Code is contaminated by construction** | Curated from the **C4 validation set** (a Common Crawl derivative), which "often comprises the majority of pre-training data for LLMs." The 484 test pages are real, public, pre-2024 web pages. High-fidelity reproduction may be recall, not vision |
| **llm-stats ScreenSpot-Pro: "0 verified results, 25 self-reported"** | Its own page says so. It then cites arXiv:2504.07981 (April 2025) as the source for **Claude Opus 4.8, GPT-5.2, Qwen3.8 Max** — models that did not exist when that paper published. The citation is a blanket attribution, not a per-score provenance |
| **Aggregator vs vendor conflict, 14 points** | benchlm.ai: Claude Opus 4.6 = **83.1%** on ScreenSpot-Pro. The Opus 4.7 system card reports Opus 4.6 = **69.0%** -> 4.7 = 79.5%. Both cannot be right. Prefer the system card |
| **CharXiv 2026 numbers cannot be independently sourced** | Official board frozen 2024-12-25. benchlm's "Claude Mythos 5 93.5%" concerns a model Anthropic restricts to *vetted partners* — no public evaluator has access |
| **Self-report is the norm, not the exception** | On SWE-bench Verified leaderboards, **99 of 100 results are self-reported**. Independent administration (ARC Prize running Opus 5's ARC-AGI-3) is called out as *exceptionally uncommon* |
| **Harness variance exceeds most model deltas** | Identical weights show **10-20pp** swings by scaffold; **"the scaffold gap alone can exceed 28 points."** Claude Opus 4.5 scores **80.9% on SWE-bench Verified but 45.9% on SWE-bench Pro** — 35 points, same weights |
| **ScreenSpot-Pro gains can be pure input-resolution** | Opus 4.6->4.7 went **69.0% -> 79.5%** on ScreenSpot-Pro and 74.0% -> 78.6% on LAB-Bench FigQA attributed to accepting **2,576px long edge / 3.75MP, up from 1,568px / 1.15MP (~3.3x pixels)**. **Implication for us: our screenshot pipeline's downsampling policy may matter more than our model choice.** Test that before spending on a model upgrade |

---

## 4. (c) Where is the cloud-vs-open-weight gap largest?

Using **primary sources only** (H Company's own model card + Anthropic system cards), because the
aggregator numbers fail section 3.

**Holo2 primary table** ([HF Hcompany/Holo2-8B](https://huggingface.co/Hcompany/Holo2-8B), Apache-2.0, base Qwen3-VL-8B-Thinking):

| Model | ScreenSpot-Pro | ScreenSpot-v2 | OSWorld-G | WebClick-v1 | Ground-UI-1K |
|---|---|---|---|---|---|
| Holo2-30B-A3B | **66.1%** | 94.9% | 76.1% | 91.3% | 85.4% |
| Holo2-8B | 58.9% | 93.2% | 70.1% | 89.5% | 83.8% |
| Holo2-4B | 57.2% | 93.2% | 69.4% | 88.8% | 83.3% |
| Holo1.5-7B | 57.9% | 93.3% | 66.2% | 90.2% | 84.0% |
| Qwen3-VL-8B-Thinking | 38.5% | 91.5% | 56.0% | 85.9% | 83.6% |

Holo2-235B-A22B additionally reports **70.6%** single-step / 78.5% within-3-steps on ScreenSpot-Pro.

**The gap, per axis:**

| Axis | Best open-weight | Frontier cloud | Gap | Verdict for local-vs-cloud |
|---|---|---|---|---|
| **GUI grounding (ScreenSpot-Pro)** | Holo2-235B **70.6%**; **Holo2-30B-A3B 66.1% runs locally** | Opus 4.7 **79.5%** (system card) | **~9-13pp** | **Smallest gap. A 30B MoE is within ~13pp of frontier — and it is within 3pp of the frontier model of one generation earlier (Opus 4.6, 69.0%).** Local is viable here |
| **Fine visual discrimination (BLINK)** | Qwen3-VL-235B 0.707 | Seed 2.1 Pro 0.814 | **~11pp** | Moderate; both far below human 95.7% |
| **Small-text / OCR spotting (OCRBench v2 EN)** | Nemotron 3 Nano 65.8, Qwen3.6-35B-A3B 65.5 | specialist 73.4 | **~8pp** | Small — and the leaders are specialists, not general frontier models |
| **Chart/small-text reasoning (CharXiv)** | — | — | historically large ("substantial, previously underestimated gap") but **unmeasurable in 2026** — board dead | Unknown. Do not assert |
| **Design/aesthetic judgement (WebDevJudge, AesEval)** | not separately reported | GPT-5 0.7252 / best judge 66.06% | **~0 relevant** | **The frontier models are themselves failing. The cloud-vs-open gap is not the binding constraint here — the human-vs-machine gap is (18.8pp on WebDevJudge).** |

**The decision this implies:** the local-vs-cloud question is *only* live for the grounding
sub-task, where open weights are close and a 30B model is deployable. For the actual judgement
task, paying for frontier cloud buys a model that agrees with expert humans **66% of the time
against a human ceiling of 85%** — so the choice between cloud and local matters far less than
whether we accept that error rate at all.

---

## 5. (d) Is there an aesthetic / design-quality benchmark, validated against human designers?

**Not "essentially none" — but close, and weaker than it first appears. Two exist, plus one
adjacent. All three have disqualifying limitations for model *selection*.**

| Benchmark | Human validation | Limitation for us |
|---|---|---|
| **WebDevJudge** | **Strongest validation found anywhere in this survey.** Naive direct comparison gave only **65% inter-annotator agreement**; introducing **rubric trees** (intention / static quality / dynamic behavior) raised it to **89.7% with ties, 94.0% without** — vs 63% for MT-Bench. Human baseline 84.82% | Judges **paired** implementations, not a single artifact. Real design review is single-artifact critique. Also: it is a 2025-dated model roster (GPT-4.1, Claude-4-Sonnet); nobody has re-run it on 2026 frontier models |
| **AesEval-Bench** | Human annotators trained on tutorials, **majority voting** over multiple annotators. **Annotator count and inter-annotator agreement are NOT reported; no human baseline is given** | Ground truth is built by **perturbing** designs and asking models to detect the perturbation — a synthetic proxy for "is this design good." Source is Crello (graphic design), **not web UI**. And no human ceiling means we cannot say how far models are from good |
| **UXBench** ([arXiv 2606.16262](https://arxiv.org/pdf/2606.16262), 2026-06-16) | References an expert-validation appendix; finds LLM UX critiques show *"measurable but limited consistency with professional designer assessments"* | Exact rater counts, agreement stats and per-model scores are not extractable from the preprint's compressed streams. **Directionally the most on-target benchmark for critique quality — but not yet usable as a scoreboard.** Warrants a full-text read |

**Counter-datum worth flagging:** ARTIFACTSBENCH reports **>90% agreement** between human web
developers and MLLM evaluators on visual fidelity, layout correctness and interactive integrity —
sharply contradicting WebDevJudge's 66%. The likely reconciliation is task difficulty: agreement
on *gross* correctness (does it render, is the layout broken) is easy; agreement on *preference
between two competent designs* is what collapses. Do not cite the 90% number as evidence models
can review design.

**What a credible design-review benchmark would require** (none jointly satisfied today):

1. **Single-artifact critique, not pairwise preference** — real review has no B to compare against.
2. **A reported human ceiling AND inter-annotator agreement**, from **named credentialed
   designers**, not crowdworkers. WebDevJudge shows this is achievable but needs rubric trees to
   lift IAA above ~65%.
3. **Localized findings** — a critique scored on *where* it points, not just what it says.
   AesEval is the only benchmark that attempts this, and the result is damning (below).
4. **Actionability scoring** — "the hierarchy is weak" is unusable; "the h2 at 14px is only 2px
   from body text, raise it to 20px" is a review. UXBench is the only attempt.
5. **Contamination resistance** — real web pages from Common Crawl/C4 are disqualified by
   construction. Needs held-out, freshly-authored, or perturbation-generated artifacts with a
   private test split.
6. **Precision on false positives** — a reviewer that flags 40 issues to catch 8 real ones is net
   negative. No existing benchmark scores precision/recall of *findings*; they score agreement
   with a preference label.

---

## 6. Adversarial self-pass

*"What would a hostile reviewer say I did not check?"* Three gaps, investigated with real calls:

### The benchmark most likely to mislead us: **ScreenSpot-v2** (and ScreenSpot-v1)

**The mechanism, quantified from a single primary table (section 4).** ScreenSpot-v2 compresses a
27.6-point true capability spread into 3.4 points of measured score. Qwen3-VL-8B-Thinking scores
**91.5%** on ScreenSpot-v2 and **38.5%** on ScreenSpot-Pro — the same model, the same nominal
skill, differing only in target size and screen resolution. A **3B** model (Qwen-GUI-3B) reaches
86.4% on ScreenSpot-v2.

So a model can post **>91% on ScreenSpot-v2** — a number that reads as "solved" — while being
**wrong about small targets on a real high-DPI screen roughly 6 times in 10**. Web design review
is exactly the small-target, high-resolution regime. If we select on ScreenSpot-v2 we will pick a
model that cannot see the thing we are asking it to review.

**Runner-up misleader: OCRBench v2's composite.** Its top three slots (Yaochi-DTS-A2T-1.9,
Posicube_DVLM, KDL Frontier) are OCR-specialist leaderboard submissions we would never deploy as
a design reviewer. Ranking by composite points at a model with no general reasoning. Track the
**Spotting** and **Recognition** sub-scores of models we would actually run, not the board's top
rows.

### Gap 1 — "Is ScreenSpot-Pro even the right proxy?" **Largely no, and I nearly asserted it was.**

ScreenSpot-Pro is **search for a named target**: *"click the layers panel."* Design review is
**detection of an unnamed defect**: *"what is wrong with this page?"* These are different
computational problems — one has the answer in the prompt, the other does not.

**The evidence that this distinction is real and load-bearing:** AesEval-Bench measures exactly
the unnamed-defect case, and the best model on earth scores **bbox IoU 0.1993**. IoU 0.20 is
"pointing at roughly the right quadrant." The *same class of models* ground named targets at
66-79%. **Localization ability does not transfer from named-target search to unnamed-defect
detection**, and ScreenSpot-Pro cannot see that collapse. This is the strongest single caution in
this report: a high ScreenSpot-Pro score is necessary-ish but nowhere near sufficient.

### Gap 2 — "Did you check whether the aggregators are simply fabricating?" **Yes; the answer is nuanced, which matters.**

I initially suspected benchlm.ai / llm-stats.com were inventing models: "Claude Mythos 5,"
"Muse Spark," "Qwen3.8 Max," "GLM-5V-Turbo." **I was wrong on the model names** — Claude Mythos 5
and Fable 5 are genuine Anthropic releases (Fable 5 announced 2026-06-09; Mythos 5 restricted,
US-government hold lifted late June 2026). The current lineup is Haiku 4.5 / Sonnet 5 / Opus 5
(2026-07-24) / Fable 5, with Mythos 5 restricted-access.

**So the failure is provenance, not invention** — which is *more* dangerous, because the pages
look legitimate. The scores are unsourced or falsely sourced, attached to real model names. That
is precisely the failure mode that survives a casual credibility check.

### Gap 3 — "You assumed the model is the variable." **It may not be the dominant one.**

The Opus 4.6->4.7 ScreenSpot-Pro jump (**69.0% -> 79.5%**) is attributed to accepting ~3.3x more
pixels, not to better vision. If our screenshot pipeline downsamples before the model sees it, we
inherit the *old* score regardless of which model we buy. **Before any model-selection spend, run
one model against one page at native vs downsampled resolution.** That experiment is cheap and
may dominate the entire model-choice decision.

---

## 7. What NO existing benchmark measures — where we must build our own eval

Each is a capability the brief names, with the confirmed absence of any benchmark for it.

1. **Single-artifact design critique.** Every judgement benchmark is *pairwise* (WebDevJudge,
   UI-Bench) or *classification over perturbations* (AesEval). Nothing scores "here is one page,
   tell me what is wrong with it" — our actual task.
2. **Precision/recall of design findings.** No benchmark scores *false positives*. A reviewer
   flagging 40 issues to catch 8 is net-negative for us, and would score identically to a precise
   one on every board surveyed.
3. **Localization of an unnamed defect.** Only AesEval attempts it (IoU 0.1993, graphic design,
   not web). **No web-UI defect-localization benchmark exists at all.**
4. **Design-system / brand-consistency conformance.** Nothing measures "does this violate *our*
   spacing scale, type ramp, or token set" — inherently project-relative, so no public benchmark
   can cover it. Unambiguously ours to build.
5. **Cross-viewport and responsive-breakpoint review.** Every benchmark here is single-screenshot.
   Nothing evaluates spotting a defect that appears only at 375px or only at 1440px.
6. **Small-text fidelity *in web UI specifically*.** OCRBench v2 is documents; CharXiv is
   scientific figures (and is dead). Neither covers 12px UI labels on low-contrast backgrounds —
   a dominant real-world design defect.
7. **Actionability of the fix.** UXBench is the only attempt and is not yet a usable scoreboard.
   Nothing scores whether a critique names the element, the property, and the target value.
8. **Stability / self-consistency of judgement.** No benchmark reports variance across reruns on
   the same artifact. WebDevJudge does report **persistent positional bias resistant to
   prompting** — evidence that instability is real and unmeasured.

**Minimum viable internal eval, implied by the above:** 50-100 held-out pages we author or perturb
ourselves (contamination-proof), each with **designer-authored, localized, severity-tagged defect
lists**; score models on **precision and recall of findings** plus **localization IoU**; report
**inter-designer agreement** as the ceiling; run every candidate at **native and downsampled
resolution** to separate model skill from pipeline loss. WebDevJudge's rubric-tree method is the
proven way to lift annotator agreement from ~65% to ~90% — copy it rather than inventing an
annotation protocol.

---

## 8. Blockers and uncertainties

- **CharXiv 2026 standings are unobtainable.** Official board dead since 2024-12-25; every 2026
  number traces to an unsourced aggregator. No trustworthy current CharXiv figure was found.
- **Claude Opus 5 vision benchmarks not retrieved.** The system card PDF exceeded the fetch size
  limit (maxContentLength). Opus 5's ScreenSpot-Pro / CharXiv numbers remain unread — **the
  single highest-value follow-up**, since Opus 5 is a likely candidate. URL:
  `https://www-cdn.anthropic.com/c5fbac3f0b1280a933ebd26d3cb8bb9f5bdeaf48/Claude%20Opus%205%20System%20Card.pdf`
  (OSWorld 2.0 = 70.6% retrieved secondhand only).
- **UXBench per-model scores not extracted** (PDF stream compression). Directionally the most
  on-target benchmark for critique quality; warrants a full-text read.
- **AesEval-Bench has no human baseline and no reported IAA.** Its numbers show models are bad in
  absolute terms but cannot tell us how bad relative to a designer.
- **WebDevJudge figure variance:** the paper HTML gives GPT-4.1 66.06% / human 84.82%; a secondary
  summary gives 70.34% / 84.56%. Likely a different table (ties included/excluded). Paper used.
- **Artificial Analysis MMMU-Pro table did not render** — only three top entries were extractable
  from prose; the full ranked table needs a JS-capable fetch.
- **Design2Code contamination is argued from construction (C4 validation set), not from a
  published contamination study.** I searched for one and found none. The mechanism is sound; the
  citation is inferential, and is flagged as such.
- **Post-cutoff model landscape.** Model names and releases after ~May 2026 (Opus 5, Fable 5,
  Mythos 5, Gemini 3.7, GPT-5.x, Seed 2.1 Pro, GLM-5V-Turbo) were verified via web search only.

---

## Sources

- [WebDevJudge (arXiv 2510.18560)](https://arxiv.org/html/2510.18560v1)
- [AesEval-Bench (arXiv 2603.01083)](https://arxiv.org/abs/2603.01083)
- [UXBench (arXiv 2606.16262)](https://arxiv.org/pdf/2606.16262)
- [UI-Bench (arXiv 2508.20410)](https://arxiv.org/abs/2508.20410) - [leaderboard](https://uibench.ai/leaderboard)
- [DesignBench (arXiv 2506.06251)](https://arxiv.org/pdf/2506.06251)
- [ScreenSpot-Pro (arXiv 2504.07981)](https://arxiv.org/abs/2504.07981) - [repo](https://github.com/likaixin2000/ScreenSpot-Pro-GUI-Grounding) - [official board](https://gui-agent.github.io/grounding-leaderboard/index.html)
- [Holo2-8B model card (H Company)](https://huggingface.co/Hcompany/Holo2-8B)
- [OCRBench v2 official leaderboard](https://99franklin.github.io/ocrbench_v2/) - [arXiv 2501.00321](https://arxiv.org/html/2501.00321v2)
- [CharXiv official leaderboard](https://princeton-nlp.github.io/CharXiv/)
- [MMMU-Pro - Artificial Analysis](https://artificialanalysis.ai/evaluations/mmmu-pro)
- [Design2Code (arXiv 2403.03163)](https://arxiv.org/abs/2403.03163) - [NAACL 2025](https://aclanthology.org/2025.naacl-long.199/) - [llm-stats board](https://llm-stats.com/benchmarks/design2code)
- [WebSight dataset (HF)](https://huggingface.co/datasets/HuggingFaceM4/WebSight) - [arXiv 2403.09029](https://arxiv.org/abs/2403.09029)
- [The Spatial Blindspot of VLMs (arXiv 2601.09954)](https://arxiv.org/pdf/2601.09954)
- [llm-stats ScreenSpot-Pro board](https://llm-stats.com/benchmarks/screenspot-pro) - [benchlm ScreenSpot-Pro](https://benchlm.ai/benchmarks/screenspot-pro) — both cited **as evidence of the provenance problem**, not as scores
- [Benchmark methodology / contamination guide](https://www.digitalapplied.com/blog/llm-benchmark-methodology-2026-contamination-leaderboard-guide)
- [Opus 4.7 system card readthrough (dev.to)](https://dev.to/ji_ai/i-read-all-232-pages-of-the-opus-47-system-card-28mh) — source of the 69.0 -> 79.5 resolution claim
- [Claude Opus 5 System Card (PDF, not fully read)](https://www-cdn.anthropic.com/c5fbac3f0b1280a933ebd26d3cb8bb9f5bdeaf48/Claude%20Opus%205%20System%20Card.pdf)
