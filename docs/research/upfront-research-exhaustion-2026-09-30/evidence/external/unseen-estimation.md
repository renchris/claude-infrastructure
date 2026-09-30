# Estimating what has not been found: capture-recapture, unseen-species estimation, seeding and reliability growth applied to LLM research panels

Author: deep-research subagent, 2026-09-30. Scope: external literature plus a simulation of my own. The only local file read was `~/.claude/skills/research-subagents/SKILL.md` (for the OASIS stop rule). Artifacts:
- this report
- source texts: `/tmp/rescomp/external/unseen-src/`, plus the Briand/El Emam PDFs in `/tmp/rescomp/external/src/`
- simulation: `/tmp/rescomp/external/unseen-sim/sim.py` and `sim2.py`

---

## 0. The answer

1. **The operator's "one more thing" loop is an uncalibrated removal-sampling experiment with no residual estimate.** Each "are we complete?" round is one more search occasion. Each round removes what it finds, and nobody computes how many holes the overlap pattern implies are still unfound. Software engineering has solved this exact problem for code inspections since 1992 (Eick et al., ICSE 1992, pp. 59-65, DOI 10.1145/143062.143090):
   - Run several **independent** inspectors.
   - Record which inspector found which defect.
   - Use the overlap to estimate the total defect count and the residual.
2. **Mechanically, it transfers directly:**
   - one blind LLM research panel = one inspector (one "capture occasion");
   - a found hole = a captured animal;
   - the hole × panel incidence matrix is all the data needed.
3. **Estimator choice has been settled empirically.**
   - Use a heterogeneity model (Mh). Report the Jackknife as the point estimate and Chao's estimator as a lower bound (Briand, El Emam, Freimut & Laitenberger, IEEE TSE 26(6):518-540, 2000).
   - **With fewer than 4 inspectors, no estimator is usable.** Estimates underestimate systematically, and some estimators often fail to produce any estimate.
   - A 10-year review found most software-engineering studies recommend Mh-JK (Petersson, Thelin, Runeson & Wohlin, JSS 72(2):249-264, 2004).
4. **The binding problem for LLM panels is correlation.** Panels that share a model share its blind spots (Kim et al., ICML 2025: when two models are both wrong they pick the same wrong answer ~60% of the time, against 33% by chance; more accurate models are *more* correlated).
   - Positive dependence between panels makes every overlap-based estimator **underestimate**.
   - Holes that *every* panel family is structurally blind to are **mathematically invisible** to any overlap statistic (Link, Biometrics 59:1123-1130, 2003: population size is not identifiable under heterogeneity).
5. **Therefore overlap statistics alone can never certify "complete". Three corrections are required together:**
   - **Diversity of panels.** Different model families (the local toolchain already has Grok/Codex/Claude CLIs via grok-wiki), different perspectives and different context strategies. This makes the capture occasions closer to independent.
   - **Dependence modelling with ≥3 sources.** Log-linear models with interaction terms, or the Chao-Tsay sample-coverage approach.
   - **A known denominator.** Seeded holes, whose recall directly measures panel detection probability, including on the hard tail. Past escapes (the "one more thing" items from earlier projects) are the ideal stress-test seeds.
6. **"100.00/100.00" cannot be certified statistically, and the last percent is exponentially expensive.**
   - In the worked example below: 8 panels find 47 holes and Chao2 puts the total at ≥56. Reaching 90% of that needs ~3 more panels, 95% needs ~8, 99% needs ~18, and "no expected unseen hole" needs ~34 (4.2× the original effort).
   - Ecology field datasets needed 1.05× to 10.67× the original sample to reach the estimated asymptote (Chao et al., Ecology 90:1125, 2009).
   - Even then the asymptote is a *lower bound*.
   - By the rule of three, certifying a hole-miss rate ≤1% at 95% confidence needs ≥300 seeds, all found (Hanley & Lippman-Hand, JAMA 249:1743, 1983).
7. **The practical exit from indefinite research is a pre-registered, quantified stop.** State the target as, for example, "≥95% of estimated hole mass at severity ≥S, with seed recall ≥0.9 on stratified seeds". Stop when the estimates say you have met it, and let a loss function (Dalal & Mallows, JASA 83:872-879, 1988), not a desire for perfection, pick the target.

---

## 1. Why these methods match the complaint

| Operator's process | Statistical name | Consequence |
|---|---|---|
| Research session finds N holes, says "complete" | Single-occasion census; no estimate of what was missed | The claim of completeness has no evidence behind it |
| "Are we complete?" gets asked again and finds one more | Removal sampling (Zippin, J. Wildl. Manage. 22:82-90, 1958, DOI 10.2307/3797301). Each pass searches after the previous finds were removed | Heterogeneity (easy holes found first) makes removal estimates underestimate the total. Declining finds per pass is the signal to model, not to ignore |
| Each new round is told what was already found | Behavioural or adaptive response (model Mb; "adaptive bias" in Böhme's fuzzing work) | Independence is broken and every standard estimator is biased |
| Fixes between rounds change the plan | Open population (new holes are "born") | Closed-population estimators are invalid. The "one more thing" is partly *new* holes, not missed ones |
| Same model runs every round | Correlated occasions (local dependence) | Overlap looks high, so the estimate says "near complete" while shared blind spots stay hidden |

The first four rows are process faults that can be fixed. The fifth needs diversity plus a known denominator.

---

## 2. Evidence base, source by source

### 2.1 Capture-recapture for software inspections

- **Eick, Loader, Long, Votta & Vander Wiel, "Estimating software fault content before coding", ICSE 1992, pp. 59-65** (Crossref DOI 10.1145/143062.143090).
  - First inspection use.
  - Inspectors search independently before the meeting, and model Mt (inspector-specific detection rates) is applied.
  - There was no ground truth, so validation was only that the estimates agreed with inspectors' intuition. Summary per Briand et al. 2000, `/tmp/rescomp/external/src/2001-A-Comprehensive-Evaluation.txt:423-430`.
- **Vander Wiel & Votta 1993 (IEEE TSE)** compared Mt against Mh in simulation.
  - They found Mt better, and it can be improved by grouping defects into classes of similar detectability, i.e. stratifying (same file, lines 431-435).
  - **Transfer: stratify holes by kind** (architectural, interface, operational, security, and so on) and estimate per stratum.
- **Briand, El Emam, Freimut & Laitenberger, IEEE TSE 26(6):518-540, 2000.** The first large study with ground truth: NASA/GSFC requirements inspections with known defect counts (lines 560-588). Key results:
  - "There is a general trend towards underestimation" (line 844).
  - "For less than four inspectors … no estimator yields satisfactory results" (lines 855-857). "The median RE decreases fast below 4 inspectors and does not change significantly above that level" (line 1175).
  - The recommendation is Model Mh with the Jackknife estimator. Heterogeneity (defects differing in detectability) improves estimates significantly, while adding inspector variation (Mt) does not (lines 1244-1262). Mean absolute bias with 5 inspectors: M0 0.27, Mh(JE) 0.16, Mh(Ch) 0.15, Mth(Ch) 0.14 (Figure 8, lines 1236-1242).
  - **Failure rates** (Table 5, lines 1290-1296), i.e. how often an estimator produces no estimate at all:
    - Mh(JE): 0.5% with <4 inspectors, 0% with ≥4.
    - Mh(Ch): 12.8% and 3.9%, rising to 20.2% with <12 defects.
    - Chao fails when no defect was found by exactly two inspectors (lines 1283-1287).
  - **Accuracy saturates at about 12 defects.** "No large improvement in median relative error to be expected once there are twelve or more defects in a document" (lines 1205-1206).
  - **Naive calibration is a trap.** Multiplying estimates by a historical correction factor k gives Var(RE_calibrated) = k²·Var(RE) (Eq. 9, lines 1360-1372): "calibration creates a major problem when it is the most needed!"
  - **Limit of the model family itself.** Even Mth "does not cover the case in which one or more inspectors focus on finding specific types of defects, as it is assumed, for example, with Perspective-based reading" (lines 396-400). This is exactly the perspective-diverse panel design. Perspective diversity creates an inspector × hole interaction, which needs log-linear interaction terms (§2.4).
- **Briand, El Emam & Freimut, ISERN-98-11 (ISSRE 1998).**
  - Capture-recapture "tend[s] to provide extreme under/over estimation".
  - The Detection Profile Method is an alternative: sort defects by how many inspectors found them, fit a curve, and extrapolate to zero.
  - A selection procedure between the two matched each method's accuracy without the extreme outliers (`isern-98-11.txt` abstract, lines 13-45).
- **Petersson, Thelin, Runeson & Wohlin, "Capture-recapture in software inspections after 10 years research", JSS 72(2):249-264, 2004.** "A majority recommending the Mh-JK model", with a stated "need for application experiences" (Lund record https://lup.lub.lu.se/record/277230).

### 2.2 Unseen-species estimation (the incidence form fits panels)

In ecology terms, each panel is one *sampling unit* (a "replicated incidence sample"). Q_k is the number of holes found by exactly k of the T panels, and U = Σ k·Q_k.

- **Good 1953, Biometrika 40:237-264 (DOI 10.2307/2333344), the Good-Turing estimate.**
  - The probability that the next observation is new is f1/n, so sample coverage is Ĉ = 1 − f1/n.
  - Incidence form: q0 = Q1/U. This is also the expected fraction of new holes in one more panel (Chao et al. 2009, `ChaoEcology2009.txt:296-300`).
- **Chao 1987, Biometrics 43:783 (DOI 10.2307/2531532): Chao1 / Chao2 lower bound.**
  - Incidence form: Ŝ = S_obs + ((T−1)/T)·Q1²/(2·Q2) (Chao et al. 2009 Eq. 13, `ChaoEcology2009.txt:284`).
  - Bias-corrected form when Q2 = 0: ((T−1)/T)·Q1(Q1−1)/2 (iNEXT source `EstIndex.R:56`).
  - It is a **lower bound** under heterogeneity (Bron et al. 2024, `2404.01176.txt:633`).
  - Intuition: many holes seen only once relative to holes seen twice means many were missed entirely.
- **First- and second-order jackknife (Burnham & Overton, Biometrika 65:625-633, 1978, DOI 10.1093/biomet/65.3.625):**
  - Ĵ1 = S + ((T−1)/T)·Q1
  - Ĵ2 = S + ((2T−3)/T)·Q1 − ((T−2)²/(T(T−1)))·Q2
- **Chao & Jost, Ecology 93:2533-2547, 2012: coverage-based comparison.**
  - Compare or stop on *completeness* (coverage), not on sample size.
  - Incidence coverage as implemented by Chao's own package: Ĉ = 1 − (Q1/U)·A, with A = T·Q̂0/(T·Q̂0 + Q1) (`/tmp/rescomp/external/unseen-src/EstIndex.R:56-58`; iNEXT on CRAN, maintainer Anne Chao).
- **Chao, Colwell, Lin & Gotelli, "Sufficient sampling for asymptotic minimum species richness estimators", Ecology 90:1125-1133, 2009.**
  - This is the stopping-effort equation. Additional panels needed to reach a fraction g of Ŝ:
    m_g ≈ log[1 − (T/(T−1))·(2Q2/Q1²)·(g·Ŝ − S_obs)] / log[1 − 2Q2/((T−1)·Q1 + 2Q2)] (Eq. 15, lines 236-245).
  - "Complete" means expected unseen < 0.5; the effort for that solves 2Q1(1+x) = exp(x·2Q2/((1−1/T)Q1 + 2Q2/T)), with m = T·x (Eq. 14).
  - Empirically, reaching the asymptote took **1.05× to 10.67×** the original sample, and "substantially less effort is needed to detect 95% or 90%" (lines 258-265).
- **Orlitsky, Suresh & Wu, PNAS 2016, "Optimal prediction of the number of unseen species".** Extrapolation is reliable only up to about n·log n more samples, and no estimator can go further (per PMC5127330 summary). So one cannot extrapolate from 5 panels to the result of 500.
- **Lee & Böhme 2024 (arXiv 2402.05835), "How much is unseen depends chiefly on information about the seen".** Evolved estimators beat Good-Turing in MSE. Noted, not load-bearing.

### 2.3 Why completeness can never be proven from overlap alone

- **Link 2003, Biometrics 59(4):1123-1130 (DOI 10.1111/j.0006-341X.2003.00129.x).** "Reasonable alternative models may predict essentially identical observations from populations of substantially different sizes … even with very large samples" (USGS record https://pubs.usgs.gov/publication/5224356).
  - For panels: the same incidence matrix is consistent with "we have 95%" and with "we have 60%, and a large class of holes is near-undetectable by all panels".
  - Only an external known-truth set (seeds) or a structurally different detector can break this tie.
- **Simulation (mine): coverage measures the wrong thing.** Scenario E in §5 has 10% of holes invisible to every panel. The coverage estimate reads **0.976** while the true fraction found is 166/200 = **0.83**.
  - Coverage is weighted by detection mass, so holes with near-zero detectability contribute nothing to it.
  - **Never report coverage as "percent complete".**

### 2.4 Dependence between sources: the correction theory

- **Chao, Tsay & Lin, "The applications of capture-recapture models to epidemiological data", Stat. Med. 2001 (DOI 10.1002/sim.996).** Crossref abstract:
  - "Most epidemiological approaches merging different lists and eliminating duplicate cases are likely to be biased downwards" (this is the lead merging panel outputs).
  - There are three approaches: ecological models, log-linear models and the sample-coverage approach. Each handles "two types of source dependencies: local (list) dependence and dependence due to heterogeneity."
  - The method also assumes "no matching errors" (§4, dedup).
- **Chao & Tsay, JASA 1998, pp. 283-293.**
  - With two sources, dependence is not identifiable.
  - "An additional recapture sample … can be used to estimate the correlation bias." They express correlation bias as a function of sample coverage and inter-list dependence, and give a nonparametric estimator that includes it (https://pure.lib.cgu.edu.tw/en/publications/a-sample-coverage-approach-to-multiple-system-estimation-with-app-3/).
  - **Transfer: at least three distinguishable panel *families* are needed before correlation between families can even be estimated.**
- **Direction of bias.** Lincoln-Petersen gives N̂ = n1·n2/m, where m is the number of holes both panels found. Positive correlation inflates m, so N̂ falls: **correlated panels always make you look more complete than you are.** Negative dependence (perspective panels searching disjoint regions) deflates m and overestimates.
- **Log-linear models with interaction terms** (the International Working Group for Disease Monitoring and Forecasting 1995 review, Am. J. Epidemiol.). Fit the 2^T contingency table of capture histories with λ_{ij} terms for panel pairs that share a model family or prompt. **Group panels by family and put family × family interactions in the model.**
- **Bron, van der Heijden, Feelders & Siebes 2024 (arXiv 2404.01176): the direct precedent for machine "panels".**
  - An ensemble of *different* learners (LR, RF, …) acts as five capture occasions for estimating how many relevant documents remain in technology-assisted review.
  - Model diversity is justified as additive Poisson rates λ_i = Σ_j λ_ij (lines 615-624).
  - Chao is used as a lower bound, plus Rivest's Poisson-regression version with η heterogeneity terms and a profile-likelihood 95% CI (lines 641-700).
  - Worked example: N̂ = 125.18 against a true N = 120, with Chao (1987) at 116.24 (lines 690-692).
  - Their independence argument ("committee members search independently", lines 629-633) holds only because the learners have separate training sets. The LLM equivalent is separate context and no shared findings.

### 2.5 How correlated are LLM panels? (why "more subagents" is not "more inspectors")

- **Kim, Garg, Peng & Garg, "Correlated Errors in Large Language Models", ICML 2025 (PMLR 267; arXiv 2506.07962).**
  - Studied 349 models × 12,032 questions, 71 models on HELM, and 20 models on resume screening.
  - "On Helm, pairs of models agree on average about 60% of the time when both models are incorrect (… uniformly at random would lead to 1/3)."
  - Same provider, same architecture and similar size all raise correlation. "Even after conditioning … models that are more accurate individually also have more correlated errors" (`2506.07962.txt` abstract and §1).
- **Goel et al., "Great Models Think Alike and this Undermines AI Oversight", ICML 2025 (arXiv 2502.04313).** Introduces the CAPA metric. "Model mistakes are becoming more similar with increasing capabilities."
- **Local corroboration.** `~/.claude/skills/research-subagents/SKILL.md:758-763` already records that "homogeneous LLM committees converge to >0.95 cosine similarity in 1-2 rounds" and that agreement is "the textbook signature of false consensus".
- **Transfer.** Ten Opus panels is closer to one inspector with ten attempts than to ten inspectors. Rule of thumb: effective independent inspectors ≈ number of *distinct families × distinct perspectives with no shared context*, not the number of subagents.

### 2.6 Seeding and mutation: a known denominator

- **Mills 1972 (IBM FSD, "On the statistical validation of computer programs").**
  - Seed s artificial defects. If testing finds k seeds and n real defects, N̂ = n·s/k.
  - The method requires seeded and real defects to be equally detectable (Briand et al. 2000, lines 411-417).
- **Musa et al. 1984 critique:** seeding "fails to be accurate due to the difficulties in seeding the software with defects similar to those naturally occurring … seeded defects are much easier to find" (Briand et al. 2000, lines 418-420).
- **Just, Jalali, Inozemtseva, Ernst, Holmes & Fraser, "Are mutants a valid substitute for real faults in software testing?", FSE 2014 (Distinguished Paper).**
  - Covered 357 real faults. Mutant detection correlates with real-fault detection independently of coverage.
  - Only **73% of real faults are coupled to common mutants**, and the paper analyses what the uncoupled 27% look like (`mutation-effectiveness-fse2014.txt:174, 773`).
  - **Transfer: synthetic seeds cover about three-quarters of the real-hole space at best. The rest has to come from real escapes.**
- **Hanley & Lippman-Hand, JAMA 249:1743-1745, 1983: rule of three.** Zero misses in s seeds gives a 95% upper bound of 3/s on the miss rate. So:
  - ≤5% needs 60 seeds, all found;
  - ≤1% needs 300.
  - Relative SE of Mills' N̂ ≈ √((1−r)/(r·s)): **0.066 with 40 seeds at recall 0.85, 0.042 with 100, 0.013 with 300 at recall 0.95** (computed in `unseen-sim`).

### 2.7 Reliability growth models (the time-series view)

- **Goel-Okumoto 1979 (IEEE Trans. Reliability).**
  - Expected holes found by effort t: μ(t) = a(1 − e^(−bt)).
  - Expected residual: a·e^(−bt).
  - Instantaneous discovery rate: a·b·e^(−bt). Stop when this falls below a threshold.
- **Wood, "Software Reliability Growth Models", Tandem TR 96.1 (Sept 1996; IEEE Computer 29(11), 1996), `unseen-src/wood.txt`:**
  - Predicted residual against first-year field defects: 33 vs 34, 33 vs 28, 10 vs 9 (lines 51-54).
  - "The simple exponential model outperformed the other models" out of 9 (lines 56-58).
  - "**Execution (CPU) time is the best measure of the amount of testing.** Using calendar time or number of test cases … did not provide credible results" (lines 59-60).
  - Parameters "do not become stable until about **60% of the way through the test**" (line 909).
  - "No single methodology seems capable of capturing all the variability of different releases" (lines 47-50).
  - **Transfer:** measure effort in a unit comparable to execution time: independent panel-runs at a fixed brief/effort, or tokens of novel search. Do not use days or rounds. Do not trust the residual estimate until the curve has flattened well past its knee.
- **Dalal & Mallows, "When should one stop testing software?", JASA 83(403):872-879, 1988 (DOI 10.1080/01621459.1988.10478676).** Stopping is a sequential decision that minimises expected loss (cost of an escaped fault × expected residual, weighed against the cost of more testing). **This replaces "100.00/100.00" with an explicit, defensible target.**
- **Removal method (Zippin 1958).** The existing "ask again, find more" loop can be turned into an estimate with no extra effort: fit declining catch per pass. With heterogeneity it underestimates, the same way as M0.

### 2.8 Adaptive search breaks the estimators

- **Böhme, "STADS: Software Testing as Species Discovery", TOSEM 2018 (arXiv 1803.02130).**
  - Good-Turing discovery probability (singletons ÷ samples) is used as the residual-risk bound for fuzzing campaigns.
  - "The discovery probability U provides an upper bound on the probability to discover a new vulnerability" (lines 383-387).
  - The paper discusses the adaptive-bias caveat (line 263).
- **Böhme, Liyanage & Wüstholz, "Estimating Residual Risk in Greybox Fuzzing", ESEC/FSE 2021.** Blackbox estimators "systematically and substantially under-estimate the true risk" under adaptive bias, where the process changes its sampling based on what it found (https://2021.esec-fse.org/details/fse-2021-papers/39/Estimating-Residual-Risk-in-Greybox-Fuzzing).
- **NOVA (arXiv 2605.15219), fundamental limits of AI generate-verify-accumulate loops.** "Good-Turing estimation is a local batch-diversity diagnostic, not an estimator of the historically undiscovered valid mass." Unanchored feedback can "lock generation onto early accepted artifacts and leave initially reachable valid artifacts undiscovered" (quoted via WebFetch summary; not independently re-read).
- **Transfer:** a wave-2 brief of the form "here are wave 1's findings, find what's missing" is adaptive sampling. Its finds are valuable but **must not enter the capture-recapture matrix**. Estimation data comes only from blind panels on a frozen snapshot.

### 2.9 Direct precedents: capture-recapture as a stopping rule for *searching*

- **Kastner, Straus, McKibbon & Goldsmith, J. Clin. Epidemiol. 62:149-157, 2009.** "The capture-mark-recapture technique can be used as a stopping rule when searching in systematic reviews." Four databases were treated as capture occasions to estimate the total literature.
- **Bron et al. 2024** (§2.4). Stopping technology-assisted review with Chao's estimator over an ensemble of diverse learners.
- No published application of capture-recapture to LLM research or review panels was found. An extended web search returned LLM bug-finding benchmarks but no overlap-based residual estimation. The method here is therefore novel in application, even though every component has a primary source.

### 2.10 A trap specific to the lead's synthesis step: deleting singletons

- **Deng, Umbach & Neufeld, "Nonparametric richness estimators Chao1 and ACE must not be used with amplicon sequence variant data", ISME J. 2024 (PMC11208923).** Denoising pipelines remove singletons by default, which "renders the use of singleton-dependent Chao1 and ACE metrics meaningless."
- **Transfer.** A lead that drops findings "only one subagent mentioned" (as noise, or failing a 90% conviction bar) is doing exactly that.
  - Q1 shrinks, the estimators collapse onto S_obs, and the report says "complete".
  - Singletons are the single most informative number. **Keep them in the matrix. Verify them, but do not delete them before estimating.**

---

## 3. The procedure for LLM research panels

### 3.1 Before the round (pre-registration)
1. **Freeze the artifact.** Snapshot the plan or knowledge base at a commit, which makes the population closed. Fixes go into a later snapshot, and the changed regions get a smaller delta round.
   - Reason: fixes inject new holes. Capers Jones's figure is ~7% of defect repairs introducing a new defect, and ≥25% at high complexity (cermacademy.com/?p=3375; ganssle.com, secondary). That is part of the observed "one more thing" stream and is not a sign of missed holes.
   - With injection rate b the series converges to N0/(1−b), so it ends only if each round re-inspects just the changed regions.
2. **Define the unit "hole" with a severity floor.** For example: "would change an implementation decision, an interface, a sequencing or an acceptance criterion". Define strata, since stratifying improves estimates (Vander Wiel & Votta 1993).
   - Without a floor the "species" are heavy-tailed trivia, and discovery grows like a power law without end (§6).
3. **Pre-register the stop target**, for example: lower bound Ĉhao2 − S_obs ≤ 1 at severity ≥ S; Mh-JK residual ≤ 2; stratified seed recall ≥ 0.9; zero seed misses in the escape stratum. Pick the numbers with a Dalal-Mallows style loss, not "100.00".
4. **Plant seeds.** Two sets, never revealed to panels, with an adjudicator who knows which findings are seeds:
   - **Representative seeds** (≈30-60), written to match real hole strata and difficulty. Where possible, adapt real holes from past projects so they are not synthetic-easy (Musa's critique).
   - **Escape seeds** (≈10-30): the "actually one more thing" items from past projects, harvested from transcripts. These are the hard tail by construction. My simulation shows that using them as a *Mills denominator* overestimates N by about 2.5× (§5, prior_escapes). Use them as a **recall gate on the hard stratum**, not as the population estimator.

### 3.2 Panel design (the capture occasions)
5. **T ≥ 6 blind panels, better 8-10.** Briand shows fewer than 4 is unusable and median error stops improving above 4-5. Two panels also cannot identify dependence, and three is the minimum for a dependence term (Chao & Tsay).
6. **Diversity along three axes, each with at least 2-3 levels:**
   - **Model family:** Opus, Fable, plus cross-vendor CLIs already on the machine (grok-wiki drives Grok/Codex/Claude/Pi/Antigravity). Kim et al. show same provider or architecture raises error correlation.
   - **Perspective:** threat, operability, data, and so on. This raises coverage but creates inspector × hole interaction (Briand lines 396-400), which is modelled below.
   - **Context strategy:** full repo, spec only, adversarial "assume it fails". Record each panel's family, perspective and strategy as covariates.
7. **Independence hygiene.** No panel sees another's findings, the lead's hypotheses or the seed list. Every panel gets the same frozen snapshot. Adaptive follow-up waves are allowed, but their finds are logged *outside* the estimation matrix (§2.8).

### 3.3 Building the matrix
8. **Deduplicate with a panel-blind adjudicator** into a hole × panel 0/1 matrix, logging every split/merge decision.
   - Over-splitting inflates Q1 and overestimates. Over-merging inflates Q2 and underestimates. Chao et al. 2001 assume "no matching errors".
   - Run a second adjudicator on a sample and report inter-rater agreement.
9. **Keep singletons** (§2.10).

### 3.4 Estimation (report all of these, never one number)
| Quantity | Formula / source | Role |
|---|---|---|
| S_obs | — | Found |
| Chao2 (bias-corrected) | S + ((T−1)/T)·Q1(Q1−1)/(2(Q2+1)) | **Lower bound**; primary gate |
| Mh jackknife, order 1-2 | Burnham & Overton 1978 | Point estimate recommended by Briand 2000 / Petersson 2004 |
| Log-linear with family × family terms, or Rivest Poisson regression | IWGDMF 1995; Rivest (Rcapture), as used by Bron 2024 | Correction for correlated families; profile-likelihood CI |
| Sample coverage Ĉ | 1 − (Q1/U)·A (iNEXT) | Detection-mass completeness; **not** "percent complete" |
| Expected new holes from one more panel | Q̂0·Q1/(T·Q̂0 + Q1) | Marginal value of another panel |
| m_g panels to reach g·Ŝ | Chao et al. 2009 Eq. 15 | Budget |
| Mills N̂ from representative seeds | S_obs / seed recall | **The only estimator that sees universal blind spots**, if seeds are representative |
| Escape-seed recall | k_esc / s_esc; rule-of-three bound | Hard-tail gate |
| Per-family Chao2 vs pooled | — | Divergence between families measures dependence |

### 3.5 Stop or continue
10. **Stop when every pre-registered gate holds.** Otherwise spend the m_g panels, choosing the family or perspective with the most singletons (the least-saturated direction).
11. **Once stopped, the claim is**, for example: "Found 54. Lower bound 56 (Chao2). Point estimate 58 (Mh-JK), 95% CI [55, 66]. Representative-seed recall 0.93 (95% CI …), escape-seed recall 0.80. Expected new holes from one more blind panel: 0.4."
    - That statement cannot be taken back later: an escape that surfaces afterwards is a quantified tail event covered by the CI, not a broken promise.

### 3.6 Worked example (computed: `unseen-sim`, second python block)
T = 8 panels, frequency counts Q1..Q8 = 12, 7, 6, 5, 5, 4, 4, 4, so S_obs = 47 and U = 173.

| Estimate | Value |
|---|---|
| Chao2, classic | 56.0 |
| Chao2, bias-corrected | 54.2 |
| Jackknife 1 | 57.5 |
| Jackknife 2 | 62.0 |
| Coverage Ĉ | 0.94 |
| q0 (chance the next finding is new) | 0.069 |
| Expected new holes from panel 9 | 1.29 |

Additional panels to reach a fraction g of Ŝ = 56:

| Target | Additional panels |
|---|---|
| 90% | 3.1 |
| 95% | 7.6 |
| 99% | 18.0 |
| Asymptote (expected unseen < 0.5) | **33.8**, i.e. 4.2× the effort already spent, and still only a lower bound |

This is the operator's "weeks become months" arithmetic, stated in advance instead of discovered one hole at a time.

---

## 4. Assumptions that break, and their corrections

| Assumption | How LLM panels break it | Direction of bias | Correction (source) |
|---|---|---|---|
| Closed population | Plan edited between rounds; fixes inject holes (~7% per fix, Jones) | Looks like endless "missed" holes | Freeze a snapshot per round; delta rounds on changed regions only |
| Independent occasions (local dependence) | Same model or provider, shared prompt, shared repo context; errors correlated 60% vs 33% by chance (Kim 2025) | **Underestimate** (m inflated) | Model-family diversity; ≥3 families; log-linear interactions; Chao-Tsay coverage approach |
| Equal hole detectability (M0/Mt) | Some holes intrinsically hard | Underestimate | Mh estimators (JK, Chao); stratify (Vander Wiel & Votta) |
| Detectability > 0 for every hole | Universal blind spots of the current model generation | Invisible to all overlap statistics; not identifiable (Link 2003) | Representative seeds (Mills); structurally different detectors (tests, formal checks, humans); escape seeds |
| Inspector effect uniform across holes (Mth) | Perspective panels specialise | Negative dependence gives overestimate; mixed gives either direction | Log-linear panel × stratum terms; estimate within strata |
| No behavioural response | Follow-up waves given prior findings | Underestimate (Böhme 2021) | Keep adaptive waves out of the matrix |
| No matching errors | Fuzzy deduplication of prose findings | Split gives over-, merge gives underestimate | Blind adjudicator, second rater, logged decisions |
| Singletons retained | Lead filters one-off findings | Collapses toward S_obs (false "complete") | Keep singletons (Deng 2024) |
| Seeds representative | Synthetic seeds are easier (Musa); mutants miss 27% of real faults (Just 2014) | Easy seeds give recall too high and N̂ too low | Seeds adapted from real holes; stratified; escape seeds as a separate gate |
| Effort measured consistently (SRGM) | Rounds differ in effort or model | Unstable fits | Fixed brief, effort and budget per panel; effort in panel-runs or tokens (Wood 1996) |

---

## 5. Simulation: what correlation and blind spots do to the estimators

Script: `/tmp/rescomp/external/unseen-sim/sim.py` and `sim2.py`, 400 replications each.

Set-up:
- True N = 200 holes; T = 10 panels.
- Hole detectability: logit = −1.2 + difficulty(sd 1.2) + a family-specific blind-spot effect shared by panels of the same family.
- "Universal blind spot" = 10% of holes with detection probability 1e-4 for every family.
- All values are medians.

| Scenario | S_obs | Chao2 | JK2 | Coverage Ĉ | Mills (seeds) |
|---|---|---|---|---|---|
| A: 1 family, no universal blind spot | 151 | 171 [158-186] | 190 [173-205] | 0.956 | — |
| B: 1 family, 10% universal | 136 | 154 | 171 | 0.955 | — |
| C: 1 family, strong family effect (sd 2.5) | 140 | 157 | 172 | 0.969 | — |
| D: 5 families (sd 2.5), no universal | **184** | **191 [185-198]** | 200 [187-212] | 0.976 | — |
| E: 5 families, 10% universal | 166 | 173 | 180 | **0.976** | — |
| F: E + 40 seeds, representative of the found-able mix | 166 | 172 | 180 | 0.975 | 178 |
| G: E + 40 *easier* seeds (+1.5 logit) | 166 | 172 | 179 | 0.976 | 169 |
| H: E + 40 seeds representative *including* blind-spot rate | 166 | 172 | 180 | 0.977 | **198 [181-224]** |
| I: E + 40 seeds = past escapes | 166 | 172 | 180 | 0.976 | 499 [375-668] (seed recall 0.33) |

What the table shows:
- **Family diversity is the biggest single lever.** Going from 1 to 5 families (C to D) found 44 more holes and brought JK2 onto the truth.
- **Overlap estimators cannot see universal blind spots.** From D to E, the truth "loses" 20 holes that no family can see. Chao2 and JK2 drop accordingly, and coverage goes *up* to 0.976 while the true fraction found is 0.83.
- **Only representative seeds recover the truth**, and their precision is limited by the seed count: with 40 seeds, 10-90% spans [181, 224].
- **Easy seeds reproduce Musa's failure** (169).
- **Escape seeds are far too hard to use as a denominator** (499). They belong as a hard-tail recall gate.

Limits of the simulation: logit-normal heterogeneity, independent families, a fixed 10% blind mass. It is illustrative, not calibrated to LLM data. The calibration data would come from running §3 on a real project with seeds.

---

## 6. Implication for the local OASIS stop rule (read-only observation)

`~/.claude/skills/research-subagents/SKILL.md:774-776`, OASIS check 3: "Sublinear tail: cumulative-discovery curve fits `c·N^α` (α<1); next subagent's expected gain < ε (default 0.5 unique findings)." Four problems, measured against the literature above:

- **A fitted c·N^α with α<1 has no asymptote.** It assumes an *unbounded* number of holes, so the rule can never express "residual ≈ 0", only "the marginal gain is small". That is consistent with the operator's experience of there always being one more thing.
  - The finite alternatives are the exponential Goel-Okumoto (Wood 1996: the best of 9 models) or Chao's incidence extrapolation. Both give a *residual* as well as a slope.
- **It discards multiplicity.** Discovery counts per subagent throw away Q1 and Q2 (who found what, and how many times), which is the information that makes capture-recapture work (Briand 2000; Chao 2009).
- **"Expected gain < 0.5" can be computed directly.** Use Q̂0·Q1/(T·Q̂0 + Q1) from the incidence matrix instead of a curve fit, with seeds added for the part overlap cannot see.
- **Correlated panels satisfy the rule falsely.** OASIS check 1 (brief-cosine ≤ 0.6) diversifies *topics*, not *models*, while Kim et al. show error correlation is driven by provider and architecture. Axis-orthogonal briefs on one model family are closer to Briand's "perspective-based reading" case (inspector × defect interaction) than to independent inspectors.

---

## 7. Alternatives considered and ruled out

- **M0 or Mt MLE (the Eick 1992 original):** significantly underestimates against Mh (Briand Figure 7-8). Ruled out as primary.
- **Two-panel Lincoln-Petersen:** dependence cannot be identified with two sources (Chao & Tsay 1998), and fewer than 4 inspectors is unusable (Briand). Ruled out.
- **Calibrating by a historical multiplier k:** variance grows with k² (Briand Eq. 9). Use only with the variance reported.
- **Coverage (Ĉ) as the completeness metric:** blind to universal blind spots (§5). Report it, never gate on it alone.
- **Detection Profile Method alone:** has extreme outliers like capture-recapture. Useful as a cross-check (ISERN-98-11).
- **Agreement or consensus as a stop signal:** it is evidence of collapse, not coverage (Kim 2025; Goel 2025; local SKILL.md:758-763).

---

## 8. Blockers and uncertainties

- **No empirical study of capture-recapture on LLM panels exists.** Every transfer here is by analogy, and the effective correlation between Opus, Fable and cross-vendor panels on *design-hole* finding (as opposed to MCQ errors) is unmeasured. The first project run under §3 should record the family × family overlap matrix to measure it.
- **Seed authoring cost and realism** is the weakest link (Musa; Just 27%). Escape-harvesting from transcripts is the best available source of realistic seeds. It needs the transcript-mining work other workers in this wave may be doing.
- **NOVA (arXiv 2605.15219)** claims were read through a WebFetch summarisation model, not the full PDF.
- **Capers Jones' 7% bad-fix rate** comes from secondary and blog sources (cermacademy, Ganssle), not a peer-reviewed primary source.
- **Unverified page ranges:** Petersson 2004 (from the Lund record) and Chao & Tsay 1998 (283-293, from the search result).

## 9. Adversarial self-pass (what a hostile reviewer would say, and what I checked)

1. **"Your estimator assumes a closed population, but the operator's plans change between rounds."** Checked: the bad-fix injection literature supports this, and the remedy (freeze and delta-inspect) is in §3.1.
2. **"The lead's synthesis step may destroy the estimator's input."** Checked the singleton-deletion analogue in microbial ecology (Deng 2024). It is a direct hit, now §2.10.
3. **"Seeding from past escapes sounds ideal. Did you test it?"** Simulated it (§5, row I). Escapes are biased hard and overestimate by about 2.5× as a Mills denominator, so the recommendation was changed to a separate hard-tail gate.
4. **"Coverage 0.97 sounds like done."** Simulated it: 0.976 coverage alongside 83% truly found. The report now forbids using coverage as "percent complete".
5. **"Is there prior art on LLM panels?"** An extended search found none. This is stated as a gap, not papered over.

## 10. Sources

**Software inspection and capture-recapture**
- Eick et al. 1992, ICSE: https://doi.org/10.1145/143062.143090
- Briand, El Emam, Freimut & Laitenberger 2000, IEEE TSE 26(6), NRC report: https://www.ehealthinformation.ca/web/default/files/wp-files/2001-A-Comprehensive-Evaluation.pdf (local `/tmp/rescomp/external/src/2001-A-Comprehensive-Evaluation.txt`)
- Briand, El Emam & Freimut, ISERN-98-11: https://ehealthinformation.ca/web/default/files/wp-files/isern-98-11.pdf
- Petersson et al. 2004, JSS 72(2): https://lup.lub.lu.se/record/277230

**Unseen-species estimation**
- Good 1953, Biometrika 40:237: https://doi.org/10.2307/2333344
- Chao 1987, Biometrics 43:783: https://doi.org/10.2307/2531532
- Burnham & Overton 1978, Biometrika 65:625: https://doi.org/10.1093/biomet/65.3.625
- Chao, Colwell, Lin & Gotelli 2009, Ecology 90:1125: https://www.uvm.edu/~ngotelli/manuscriptpdfs/ChaoEcology2009.pdf
- Chao & Jost 2012, Ecology 93:2533; iNEXT source: https://github.com/AnneChao/iNEXT (R/EstIndex.R, R/iNEXT.r); CRAN: https://cran.r-project.org/web/packages/iNEXT/refman/iNEXT.html
- Orlitsky, Suresh & Wu 2016, PNAS: https://pmc.ncbi.nlm.nih.gov/articles/PMC5127330
- Deng, Umbach & Neufeld 2024, ISME J.: https://pmc.ncbi.nlm.nih.gov/articles/PMC11208923/

**Identifiability and source dependence**
- Link 2003, Biometrics 59:1123: https://pubs.usgs.gov/publication/5224356
- Chao & Tsay 1998, JASA: https://pure.lib.cgu.edu.tw/en/publications/a-sample-coverage-approach-to-multiple-system-estimation-with-app-3/
- Chao, Tsay, Lin et al. 2001, Stat. Med.: https://doi.org/10.1002/sim.996

**Correlation between LLMs**
- Kim, Garg, Peng & Garg 2025, ICML: https://arxiv.org/abs/2506.07962
- Goel et al. 2025, ICML: https://arxiv.org/abs/2502.04313

**Seeding and mutation**
- Just et al. 2014, FSE: https://homes.cs.washington.edu/~mernst/pubs/mutation-effectiveness-fse2014.pdf
- Hanley & Lippman-Hand 1983, JAMA 249:1743 (rule of three): https://en.wikipedia.org/wiki/Rule_of_three_(statistics)
- Mills 1972 and Musa 1984, as summarised in Briand et al. 2000, lines 411-420

**Reliability growth and stopping**
- Goel & Okumoto 1979, IEEE Trans. Reliability; Wood 1996, Tandem TR 96.1: https://eclass-b.uoa.gr/modules/document/file.php/D55/%CE%A3%CE%97%CE%9C%CE%95%CE%99%CE%A9%CE%A3%CE%95%CE%99%CE%A3%202007-2008/Software%20Reliability%20Growth%20Models.pdf
- Dalal & Mallows 1988, JASA 83:872: https://doi.org/10.1080/01621459.1988.10478676
- Zippin 1958, J. Wildl. Manage. 22:82: https://doi.org/10.2307/3797301

**Adaptive search and residual risk**
- Böhme, STADS (TOSEM 2018): https://arxiv.org/abs/1803.02130
- Böhme, Liyanage & Wüstholz 2021, ESEC/FSE: https://2021.esec-fse.org/details/fse-2021-papers/39/Estimating-Residual-Risk-in-Greybox-Fuzzing
- NOVA: https://arxiv.org/abs/2605.15219

**Stopping rules for literature search and review**
- Kastner et al. 2009, J. Clin. Epidemiol. 62:149: https://pmc.ncbi.nlm.nih.gov/articles/PMC2655834
- Bron et al. 2024: https://arxiv.org/abs/2404.01176

**Bad-fix injection (secondary)**
- Capers Jones: https://insights.cermacademy.com/?p=3375; Ganssle: https://www.ganssle.com/rants/latentdefects.htm
