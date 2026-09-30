# Principled stopping rules for exhaustive research, and how they define "research is done" for an LLM-agent program

Author: deep-research subagent, 2026-09-30. Read-only. Primary sources were downloaded to `/tmp/rescomp/external/src/` (`francis.txt`, `guest2020.txt`, `yang.txt`, `lewis.txt`, `briand.txt`, `sr5.txt`, `gt.txt`), so every quote below can be grepped again.

---

## 0. Bottom line

1. **Every rigorous stopping rule in these literatures certifies a *bounded* claim, never "100%".** Each certificate reads like one of these: "recall ≥ τ at confidence 1−α" (TAR), "≤ x% new information in a run of r after base b" (Guest 2020), "remaining faults ~ Poisson(f/cμ)" (Dalal–Mallows), or "the expected value of the next step ≤ its cost" (VOI / optimal stopping). No rule exists that certifies zero residual unknowns without examining the whole population, and section 2 proves this for the operator's case.
2. **Asking "are we 100.00/100.00?" over and over is a sequential test with no error control, put to a generator that always produces a candidate.** Three mechanisms, each documented, predict the "one more thing, dozens of times" loop even when the plan is already adequate:
   - **Sequential bias from repeated looks.** Lewis, Yang & Frieder 2021 call it "sequential bias induced by multiple testing" (lewis.txt:401).
   - **Sycophantic capitulation to "are you sure?".** Sharma et al. 2023: assistants "frequently admit mistakes even when their initial answers were correct".
   - **Intrinsic self-review without an external oracle degrades answers.** Huang et al., ICLR 2024.
3. **The population of "holes" must be frozen before any stopping rule can fire.** Every rule assumes a fixed universe: the collection C and relevant set R in TAR, the theme population in saturation, fault count N in software testing. Moving goalposts are population drift, and under drift no rule terminates. Francis et al. 2010 make a-priori specification the first principle.
4. **The workable definition of "done" is a pre-registered, multi-rule certificate:**
   - a frozen question and a frozen stratification of axes (Francis principle 1);
   - a novelty-rate threshold over a run (Guest 2020);
   - a residual-risk bound from independent null probes (rule of three / hypergeometric);
   - an unseen-species estimate across independent agents (Good-Turing / Chao2), corrected for correlated same-model agents;
   - a decision-relevance filter: the VOI of a candidate finding is 0 if it cannot change the implementation decision (Howard 1966).

   A late "one more thing" is then either (a) inside the certified residual, and so a logged, expected event rather than a take-back; or (b) proof that a pre-registered assumption broke. Only (b) justifies reopening research.

---

## 1. Rule-by-rule catalogue

### A. Qualitative saturation

| # | Rule / source | Exact rule | Parameters | Guarantee | Operationalization for LLM-agent research |
|---|---|---|---|---|---|
| A1 | **Theoretical saturation**, Glaser & Strauss 1967, *Discovery of Grounded Theory* p.61 | Stop sampling for a category when "no additional data are being found whereby the [researcher] can develop properties of the category" (quoted in Guest 2020, guest2020.txt) | None; judgment-based, defined per category and driven by theoretical sampling | None. It is a definition, not a test | Saturation is **per category**, not per project. Keep a codebook of categories (research axes) and mark each saturated on its own. A study-wide "done" is the conjunction of all categories. |
| A2 | **Guest, Bunce & Johnson 2006**, *Field Methods* 18(1):59–82 | Empirical: in 60 interviews, "70% of all 114 identified themes turned up in the first six interviews, and 92% were identified within the first 12" (as summarized in Guest 2020) | Homogeneous sample, fixed interview guide | Descriptive only. Holds under homogeneity and a fixed instrument | The discovery curve is steeply concave: most material arrives early and a long tail of rare themes stays open. Expect the tail. A single rare item appearing late is the normal shape of the curve, not a sign of failure. |
| A3 | **Francis et al. 2010**, *Psychology & Health* 25(10):1229–45, doi 10.1080/08870440903194015 | Four principles (francis.txt:374–454): **(1)** specify a priori an *initial analysis sample*, with stratified diversity sampling, "Otherwise, spurious early data saturation may be achieved due to spurious homogeneity"; **(2)** specify a priori a *stopping criterion*: "how many more interviews will be conducted, without new shared themes or ideas emerging"; **(3)** ≥2 independent coders, with agreement reported; **(4)** report the method so readers can audit it | **10 + 3**: "At least 10 interviews… when three further interviews have been conducted with no new themes emerging… tested after each successive interview (i.e., 11, 12 and 13; then 12, 13 and 14…)" | Procedural transparency, not probabilistic. In their Study 1 the criterion *failed* for 2 of 3 belief categories: saturation "was achieved for Normative beliefs but not for other beliefs or study-wise saturation" (francis.txt:94–101) | The **pre-registration pattern**. Before the research session: fix the axes and strata (initial sample), fix the run length of consecutive null probes that ends research, and use two independent coders (two different model families or two blind agents) to judge whether a finding is "new". Report the criterion in the plan doc. |
| A4 | **Guest, Namey & Chen 2020**, *PLOS ONE* 15(5):e0232076 | Saturation ratio = (new unique themes in the run) ÷ (unique themes in the base). Saturated when ratio ≤ threshold. Runs overlap and slide one unit at a time. Reported as "6⁺²" (6 interviews, plus a 2-interview confirming run) | **Base** = 4, 5 or 6 ("base size appears to have almost no effect"). **Run length** = 2 or 3 (longer is more conservative). **Threshold** = ≤5% or 0% new information | Explicitly **none**: "there is no guarantee that saturation is in fact reached when meeting these thresholds." Bootstrap over 10,000 resamples calibrates it. At the **0%** threshold the retrospective *degree of saturation* was only **87–89%** (homogeneous datasets 1–2) and **69–76%** (heterogeneous dataset 3). At ≤5% it was 78–82%, and 62–71% for the heterogeneous set (guest2020.txt) | **The single most important number for the operator:** even "zero new information over a confirming run" corresponds to ~70–89% of the eventually-known theme universe. **A run of null probes does not certify completeness.** Use the ratio as a *rate* signal. Set the run length at 3 or more for conservatism, and pair it with the residual-risk bounds in section C. |
| A5 | **Hennink, Kaiser & Marconi 2017**, *Qual Health Res* 27:591–608. **Hennink & Kaiser 2022**, *Soc Sci Med* (PubMed 34785096) | Two distinct saturation targets. *Code saturation*: the range of issues is identified, at 9 of 25 interviews. *Meaning saturation*: each code is fully understood in its dimensions and nuances, at 16–24 interviews. The 2022 systematic review finds 9–17 interviews or 4–8 focus groups typical | Code vs meaning | Descriptive | **Two separate done-states.** "All topics identified" (breadth) arrives about 2× earlier than "each topic understood to implementation depth". A plan can be breadth-complete and still produce depth "holes" for months. Certify both, per axis. |
| A6 | **Fugard & Potts 2015** (summarized in Guest 2020); **Lowe et al. 2018**, *Field Methods* 30(3):191–207 | Binomial power: sample size n needed to observe a theme of population prevalence p at least k times with power 1−β. Lowe et al.: choose a target proportion of the domain (e.g. 90%) and the mean prevalence of items, then estimate n | p (prevalence floor), k, power | Probabilistic, **conditional on a prevalence floor** | **Completeness only means something relative to a prevalence floor.** To detect, with 95% probability, a gap that a random probe hits with probability p, you need n ≥ ln(0.05)/ln(1−p) probes. For p = 0.10 that is 29, for p = 0.05 it is 59, for p = 0.01 it is 299 (computed; see section 2). A gap that fewer than 1% of probes would touch is not certifiable at any practical budget, so declare that floor explicitly. |
| A7 | **van Rijnsoever 2017**, *PLOS ONE* 12(7):e0181689 | Simulation: saturation (all codes observed at least once) "is more dependent on the mean probability of observing codes than on the number of codes". Purposive "minimal/maximum information" sampling beats random chance but yields fewer repetitions per code | Code-observation probability | Simulation-based | Directed (purposive) probing reaches saturation faster, but each finding gets fewer independent confirmations. Balance directed axis probes against some randomized probes that estimate the residual. |
| A8 | **Braun & Clarke 2021**, *QRSEH* 13(2):201–16 | Critique: saturation is coherent only for "neo-positivist, discovery-oriented" analysis, and incoherent for interpretive/reflexive work where meaning is generated rather than found | none | none | Applies to design choices, which are constructed rather than discovered, as opposed to fact-finding. Saturation cannot end a design debate. Design questions close by **decision** (VOI, conviction threshold), not by saturation. |

### B. Systematic-review / TAR screening stopping rules (high-recall retrieval)

| # | Rule / source | Exact rule | Parameters | Guarantee | Operationalization |
|---|---|---|---|---|---|
| B1 | **Callaghan & Müller-Hansen 2020**, *Systematic Reviews* 9:273, doi 10.1186/s13643-020-01521-4 | After prioritized screening, draw a **random sample** of n from the N unseen documents. Test H₀: recall < τ_tar with a hypergeometric test. K_tar = ⌊ρ_seen/τ_tar − ρ_AL + 1⌋ is the minimum count of unseen relevant documents consistent with H₀. p = P(X ≤ k), X ~ Hypergeometric(N, K_tar, n). **Stop when p < 1−α** | τ_tar = 0.95, α = 0.95 (p < 0.05) | "We reject that recall < 95% with 95% confidence." Empirically hit the target in 99.05% of runs with 17% mean work saving. Heuristics failed: "50 consecutive irrelevant" missed the target in **39%** of cases. "Even a perfect estimator of the proportion of unseen documents that are relevant is insufficient on its own" | **"N consecutive nothing-found" is exactly the operator's implicit rule, and it fails about 39% of the time in this benchmark.** Replace it with random-probe sampling against a stated recall target. Worked example (computed): 95 findings seen, τ = 0.95 gives K_tar = 6. With 2,000 unexamined "places a hole could be", 0 hits in 300 random probes gives p = 0.377 (cannot stop), and 786 null probes are needed to stop. The price of a recall *guarantee* is explicit and finite. |
| B2 | **Cormack & Grossman 2016**, "Engineering Quality and Reliability in TAR", SIGIR '16:75–84, doi 10.1145/2911451.2911510. Rules as restated in Yang, Lewis & Frieder 2021 (yang.txt:104–201) | **Knee method.** Gain-curve slope ratio ρ(s) = [Rel(i)/i] / [(Rel(s)−Rel(i)+1)/(s−i)], where i is the knee (the point of maximum distance from the chord). Stop at the first s with **ρ(s) ≥ 156 − min(Rel(s),150) and s ≥ 1000**. **Target method.** Randomly sample until **10** relevant documents are found, hide them, and stop when all 10 are rediscovered. **Budget method.** Stop if s ≥ 0.75C, or if both ρ(s) ≥ 6 and s ≥ 10C/Rel(s) | Knee targets recall 0.7. Target set t = 10 | Knee and Budget are heuristic ("not clear how to adapt… to recall goals differing 0.7"). **Target**: recall ≥ 0.70 at 95% confidence (Lewis et al. show 9 suffice, and 10 give ≈0.74) | **The Target method is the cleanest agent analogue.** Before research ends, have an *independent* agent seed a hidden "canary set" of 10 real gaps (sampled at random, not chosen for being hard). The main program is done at recall ≥ 0.7 (95%) only when it has independently rediscovered all 10. Raising the recall target means a larger canary set (see B3). The knee gives a cheap *signal* to start the certification phase, not a certificate. |
| B3 | **Lewis, Yang & Frieder 2021**, "Certifying One-Phase TAR", CIKM '21, arXiv 2108.12746 | **QBCB rule**: given a random positive sample of size r, recall target t and confidence 1−α, stop when the j-th sampled positive is found, where j is the smallest integer such that [1, D_j] contains the t-quantile with (1−α) confidence (binomial approximation). The Target rule is a special case (lewis.txt:85–89, 295–301) | r, t, α | Statistically valid. Two further findings: (i) **"sequential bias induced by multiple testing"** invalidates naive repeated checks (lewis.txt:401); (ii) "overshooting a recall target… is a major source of excess cost… incurring a larger sampling cost to reduce excess recall leads to lower total cost" (abstract) | Two lessons. (1) **Every repeated "are we done?" check is a multiple test.** Without a pre-set rule or alpha-spending, the chance of a false "not done" (or false "done") compounds. (2) **Overshoot is itself the dominant cost.** Paying up front for a proper certification sample is cheaper than open-ended "keep going to be safe". This directly contradicts the "100× more research for 1%" framing. |
| B4 | **Yang, Lewis & Frieder 2021**, "Heuristic Stopping Rules for TAR", DocEng '21, arXiv 2106.09871 | Surveys fixed-iterations, 2399 + 1.2R, BatchPos, Knee, Budget, CMH-heuristic, and their Quant/QuantCI (recall estimated from model probabilities) | various | Heuristic: no guarantee | Heuristics are fine as *triggers* for starting certification. They are not certificates. |

### C. Unseen-species, residual-risk, and fault-content estimators

| # | Rule / source | Exact rule | Parameters | Guarantee | Operationalization |
|---|---|---|---|---|---|
| C1 | **Good–Turing**, Good 1953, *Biometrika* 40:237–64 (from Turing's work). Hsu 2025 notes (gt.txt) | Missing mass estimate m̂ₙ = (number of items seen exactly once) / n. This is the estimated probability that the **next** probe yields something never seen before. It is the leave-one-out estimator, unbiased for m_{n−1} | f₁ (singletons), n | Unbiased (for n−1) under i.i.d. sampling from a fixed distribution | Count across all probes/agents how many findings were surfaced **exactly once**. If 25 of 40 findings are singletons, P(next probe finds a new thing) ≈ 0.625, so "done" is nowhere near. A near-zero f₁/n is the precondition for credibly saying "done". **The "one small other thing" pattern is the signature of a high singleton fraction**, which is mathematically incompatible with saturation. |
| C2 | **Chao1 / Chao2**, Chao 1984/1987; Chao & Jost 2012, *Ecology* 93:2533 | Abundance: Ŝ = S_obs + f₁²/(2f₂). Incidence (T sampling units, e.g. T independent agents): Ŝ = S_obs + ((T−1)/T)·Q₁²/(2Q₂), with Q₁ = findings reported by exactly 1 agent and Q₂ = by exactly 2. Coverage-based stopping (Chao & Jost) plots completeness against sample coverage | f₁, f₂ or Q₁, Q₂, T | **Lower bound** on total richness under heterogeneity | Run T ≥ 5 independent research agents over the same frozen question. Tabulate which agent found which item (after dedup). Example (computed): T = 10, S_obs = 40, Q₁ = 25, Q₂ = 6 gives Ŝ ≈ 87, so about 47 items are still unseen. Stop when Ŝ − S_obs < 1 (or below a declared floor) **and** coverage ≥ target. |
| C3 | **Capture–recapture for inspections**, Eick et al. 1992 (ICSE); **Briand, El Emam, Freimut & Laitenberger 2000/2001**, NRC ERB-1084 (briand.txt:45–70, 150–158) | Estimate total defects from the overlap between inspectors' finds. Recommended model: **M_h with Jackknife estimator** (heterogeneous detection probabilities) | Number of inspectors | "overall… tend to **underestimate**… using a small number of inspectors (defined as less than four) will lead to rather inaccurate estimates… underestimation may be substantial" | Use **≥4 (preferably 5+) independent reviewers** per axis, and the jackknife M_h estimator. Treat the estimate as a **lower bound** on remaining gaps, because same-model agents are positively correlated (they share blind spots), which biases every capture–recapture estimate downward. |
| C4 | **Rule of three**, Hanley & Lippman-Hand 1983, *JAMA* 249:1743–45 | 0 events in n independent trials gives a 95% upper bound on the event rate of ≈ **3/n** (exact: 1−0.05^{1/n}) | n | Exact binomial bound, assuming independent, identically-targeted trials | After n **independent, randomized** null probes (each asks whether a hole exists at a randomly drawn place), the per-probe hole rate is ≤ 3/n at 95%. Computed: n = 30 gives ≤ 9.5%, n = 100 gives ≤ 2.95%, n = 300 gives ≤ 0.99%. This is the honest wording of a certificate: "residual hole rate < 1% per probe at 95% confidence", not "100%". |
| C5 | **Dalal & Mallows 1988**, "When should one stop testing software?", *JASA* 83:872–79 (via Höhle 2016 restatement) | N ~ Poisson(λ) faults with exponential detection times (rate μ). With testing cost f per unit time and extra cost c per fault fixed after release rather than before: **stop at the first t with (f/c)·(e^{μt}−1)/μ ≥ K(t)**, where K(t) is the number of faults found so far | f, c, μ | Bayes-optimal (minimizes expected loss). At stopping, remaining faults ~ **Poisson with mean f/(cμ)** | The first **economically optimal stopping rule for bug-finding** in this list, and it names the residual. The expected number of remaining gaps is f/(cμ): cost per unit of research, divided by (cost of finding the gap *after* shipping × discovery rate). If fixing a gap post-deploy is cheap relative to research time, the optimal residual is large. Perfection is optimal only when c → ∞, and then the rule says **never stop**. That is the operator's stated preference and the literal cause of "never deploy". |

### D. Decision-theoretic: value of information and optimal stopping

| # | Rule / source | Exact rule | Guarantee | Operationalization |
|---|---|---|---|---|
| D1 | **Howard 1966**, "Information Value Theory", *IEEE Trans. SSC* 2(1):22–26; Raiffa & Schlaifer 1961 | EVPI = E_θ[max_a U(a,θ)] − max_a E_θ[U(a,θ)] ≥ 0. EVPI upper-bounds the value of any imperfect information. **VOI = 0 whenever the information cannot change the optimal action** | Exact within the decision model | **Decision-relevance filter.** For every "one more thing", ask which implementation decision (architecture, interface, sequencing, go/no-go) it could flip. If none, its VOI is exactly 0 however true it is: log it and do not reopen research. Compute EVPI per open decision. Research on a decision stops when EVPI < the cost of a research wave. |
| D2 | **EVSI / ENBS**, Claxton & Posnett 1996; Ades et al. 2004; R `voi` package | ENBS(n) = EVSI(n) − Cost(n). Optimal n* = argmax ENBS. Stop, or do not start, research when EVSI < cost | Bayes-optimal | Before each research wave, estimate what the wave could change (EVSI) against its cost in tokens, days and delay. Any wave with ENBS ≤ 0 does not run. This replaces "as long as it takes" with "as long as it pays". |
| D3 | **1-stage look-ahead / monotone stopping**, Chow, Robbins & Siegmund 1971; Ferguson, *Optimal Stopping*, ch. 5 (sr5.txt:48–80) | N₁ = min{n : Yₙ ≥ E(Yₙ₊₁ \| Fₙ)}: "stop at the first n for which the return for stopping is at least as great as the expected return of continuing one stage and then stopping." **Optimal when the problem is monotone**: once the 1-sla says stop, it keeps saying stop | Optimal under monotonicity | Research under a frozen scope is monotone, because the marginal yield of new material falls (Guest 2006 curve). Stop when the expected decision-value of one more wave ≤ its cost. **Scope creep breaks monotonicity**: reopening the question restarts the yield curve, and the myopic rule stops being optimal. That is why freezing is a precondition. |
| D4 | **Weitzman 1979**, "Optimal Search for the Best Alternative", *Econometrica* 47(3):641–54 ("Pandora's rule") | Each box i has cost cᵢ and reward distribution Xᵢ. Reservation value σᵢ solves E[(Xᵢ − σᵢ)⁺] = cᵢ. **Selection**: open the box with the highest σ. **Stop** when the best prize found exceeds every unopened box's σ | Optimal for independent boxes | Treat each unexplored research axis as a box, with σ = the plausible upside that exploring it could add to the plan, net of cost. Explore in σ order. Stop when no remaining axis's σ beats what exploring it would improve. It gives both **what to research next** and **when to stop**. |
| D5 | **Wald SPRT** 1945/1947; Wald–Wolfowitz 1948 optimality | Accumulate the log-likelihood ratio. Stop when it crosses A ≈ log((1−β)/α) or B ≈ log(β/(1−α)) | For fixed (α, β), minimal expected sample size among all tests | Frame "done" as H₁: residual hole rate ≤ p₀ vs H₀: ≥ p₁. Sequential null/non-null probes cross a boundary with pre-set error rates. This is the principled replacement for "ask again". |
| D6 | **Safe anytime-valid inference**, Ramdas, Grünwald, Vovk & Shafer 2023, *Stat. Sci.* 38(4):576–97 | e-processes / test martingales stay valid "at all stopping times, accommodating continuous monitoring… and optional stopping or continuation for any reason" (Ville's inequality) | Type-I control under optional stopping | The mathematically correct way to let the operator ask "are we done?" at any time: the evidence for "not done" must be a betting-style e-value that is valid under continuous monitoring. It is not a fresh sample from a model that is primed to find something. |

---

## 2. Impossibility and cost results for "100.00/100.00"

- **Certifying 100% recall requires near-exhaustive examination.** With τ_tar = 1, H₀ is "at least one relevant item remains unseen", so K = 1. For a sample of n from N unexamined units, P(X = 0) = 1 − n/N, and rejecting at 95% needs **n ≥ 0.95N** (computed for N = 100, 1,000 and 10,000: 95, 950, 9,500). Any claim of 100% complete at 95% confidence is either exhaustive enumeration of the frozen universe or false. With an open universe (moving goalposts), N is undefined and the claim cannot be made.
- **Null runs certify a rate, not absence.** Rule of three: 300 consecutive independent null probes still allow a 1% per-probe hole rate. Guest 2020: 0% new information over a confirming run reached only 69–89% of eventual themes.
- **The optimal residual is positive whenever the post-deploy fix cost is finite.** Dalal–Mallows: expected remaining = f/(cμ) > 0 for finite c. The rule says stop never only as c → ∞.
- **Overshooting targets costs more than certifying them.** Lewis et al. 2021: paying for a larger certification sample lowers total cost "in almost all scenarios".

The claim that 100× effort buys the last 1% has the direction right, but the pay-off is not 100.00. It is a certified bound, and the bound's tightness is set by the budget.

---

## 3. Why the operator's loop happens, mechanism by mechanism

| Observed behaviour | Mechanism | Receipt |
|---|---|---|
| Every "are we 100%?" returns "one more thing" | The generator always produces a candidate. Assistants "frequently admit mistakes even when their initial answers were correct" when challenged | Sharma et al. 2023, arXiv 2310.13548 (ICLR 2024) |
| Self-audit keeps revising | Intrinsic self-correction without external feedback does not improve reasoning and can degrade it. Earlier "gains" came from oracle labels deciding when to stop | Huang et al., ICLR 2024, arXiv 2310.01798 |
| Repeated checks never converge | Sequential bias / multiple testing: each ad-hoc look is a new test with no alpha-spending | Lewis et al. 2021, lewis.txt:401; Ramdas et al. 2023 |
| Goalposts move | Population drift: every rule assumes fixed C, R or N. Reopening scope resets the discovery curve and breaks monotonicity (1-sla optimality) | Francis principle 1 (francis.txt:376–402); Ferguson ch. 5 |
| "Saturated" research later has holes | (a) spurious homogeneity: the same model and the same framing give false saturation; (b) code vs meaning saturation: breadth done, depth not; (c) the 0% run captures only ~70–89% | Francis (francis.txt:392–396); Hennink 2017; Guest 2020 |
| Multi-agent agreement looks like completeness | Correlated same-model agents violate capture–recapture independence, which biases estimates downward. Fewer than 4 inspectors gives substantial underestimation | Briand et al. (briand.txt:150–158) |
| Good-Turing may be over-trusted | Good-Turing measures missing mass *of the generator's own sampling distribution*, "a local batch-diversity diagnostic, not an estimator of the historically undiscovered valid mass" | Avestimehr, Duffy & Médard 2026, arXiv 2605.15219 |
| Research never ends | Perfection has no loss function, so VOI is undefined, and Dalal–Mallows with c = ∞ says never stop | Howard 1966; Dalal & Mallows 1988 |

---

## 4. Operational protocol: a pre-registered "Done Certificate" for an LLM research program

Each step is tied to the rule above that justifies it.

1. **Freeze the population (A3 principle 1, D3).** Write the question, the decision list (every implementation decision the research must settle) and the axis stratification (the codebook) before research starts. Changes to the frozen scope need an explicit operator amendment, which is logged as a new study and not as a continuation.
2. **Declare the certificate parameters a priori (A3 principle 2, A4, B1).** For each axis: base size b (e.g. the first 4 probe-waves), run length r ≥ 3, new-information threshold ≤ 5% for breadth and 0% for depth, recall target τ (e.g. 0.95), confidence α (0.95), and a prevalence floor p_min. Write them into the plan doc.
3. **Two saturation levels per axis (A5).** Code saturation (topics enumerated) and meaning saturation (each topic specified to implementation depth). Both are required.
4. **Independent, diverse samplers (A3 principle 3, C3).** At least 4–5 agents per axis, with blind briefs and preferably mixed model families or effort levels, to reduce correlated blind spots. Two independent judges decide whether a finding is "new" (dedup), with agreement reported.
5. **Residual estimation (C1, C2, C3).** Tabulate findings × agents. Compute the Good-Turing missing mass f₁/n, Chao2 Ŝ and the M_h jackknife. **Gate:** missing mass ≤ declared ε **and** Ŝ − S_obs < 1 (or below the floor). Treat all of these as lower bounds.
6. **Random-probe certification (B1, B2/B3, C4).** An independent agent either (a) seeds a hidden **canary set** of ≥10 randomly sampled real gaps (Target/QBCB rule, recall ≥ 0.7 at 95%; use more for higher τ), or (b) runs n randomized null probes against a frozen checklist of "places a hole could live", and the hypergeometric test (B1) or rule of three (C4) gives the bound. **The certificate states the bound**, for example: "recall ≥ 95% at 95% confidence; residual per-probe hole rate ≤ 1%".
7. **Decision-relevance filter (D1, D2, D4).** Any late finding is classified in one of three ways. (i) VOI = 0: it cannot flip any listed decision, so log it to a post-deploy backlog. (ii) Inside the certified residual, so the certificate expected it, and it is routed to implementation-time handling. (iii) It violates a pre-registered assumption (a new stratum or a broken independence), which is the only legitimate trigger to reopen research, and then only for that stratum.
8. **Anytime-valid "are we done?" (D5, D6).** Replace free-form re-asking with a sequential test. The question "are we done?" is answered by the certificate's current state: its e-value or SPRT boundary. It is not answered by a fresh generative audit. A fresh audit is a new sample and has to go through step 7.
9. **Economic stop (C5, D2, D3).** State f (the cost of a research day or wave) and c (the extra cost of fixing a gap after deploy compared with before). The optimal expected residual is f/(cμ). If the operator insists on c → ∞, the documented consequence is "never deploy", and the operator must choose that deliberately.

---

## 5. Mapping to the local OASIS stop (`~/.claude/skills/research-subagents/SKILL.md:756–803`)

- OASIS already rejects agreement-as-saturation (:758–764), in line with C3's correlation bias, and uses a sublinear-tail threshold ε = 0.5 unique findings (:773–774), which is close to A4.
- **Gaps against the literature:**
  - (a) No a-priori run length, base or threshold. "Never stop on count" (:781) contradicts Francis/Guest, whose rules *are* pre-set counts.
  - (b) The "adversarial null" (:771–772) is a single same-model sample, which is exposed to the sycophancy and intrinsic-self-correction failures above. A null from one sampler bounds nothing (rule of three with n = 1 gives ≤ 95%).
  - (c) The negative-space trigger requires the model to "List 3 with reasons" (:796–799). It is a **forced generator of candidates**, a structural source of "one more thing" on every invocation.
  - (d) No residual estimator (Good-Turing, Chao2), no certified recall statement, no frozen population, no decision-relevance/VOI filter, and no guard against sequential bias.

---

## 6. Adversarial pass

- **Gap 1: are these i.i.d.-sampling rules valid for directed LLM search?** No, not strictly. TAR certification works because the *certification sample* is random even when the screening is directed (B1, B3). The same split applies here: directed agents for discovery, a randomized probe or canary sample for certification. Correlated agents make C1–C3 estimates *lower bounds* (Briand: underestimation). NOVA 2026 warns that Good-Turing reflects only the generator's own distribution. So the certificate must include heterogeneous samplers and must not lean on Good-Turing alone.
- **Gap 2: can "places a hole could live" be enumerated for a greenfield design?** Only partially. It works for fact-finding (APIs, constraints, prior art). For constructed design choices, Braun & Clarke (A8) implies saturation is the wrong tool. Those decisions close by VOI/conviction (D1–D4) and are reopened only by assumption violation.
- **Gap 3: is the 39% failure of "N consecutive nulls" specific to one dataset?** It comes from Callaghan & Müller-Hansen's simulation on 20 systematic-review datasets, so it is directional, not universal. Guest 2020's 69–89% degree-of-saturation figure corroborates it independently in a different domain.
- **Unverified or secondary:**
  - Guest 2006 was read via the Guest 2020 summary, because the SAGE PDF was blocked (403 / HTML stub).
  - The Cormack & Grossman 2016 rules were read via the Yang et al. 2021 restatement, because the authors' page returned 404.
  - The Dalal–Mallows formula was read via Höhle's 2016 restatement, not the JASA original.
  - The Weitzman rule was read via secondary summaries (the Harvard PDF was an HTML stub).
  - Howard 1966 volume and pages were confirmed via search metadata only.
  - The Soudani et al. 2026 deep-research stagnation controller (arXiv 2608.15191) has no published thresholds in its abstract.

---

## Sources

- Guest, Namey & Chen 2020: https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0232076
- Francis et al. 2010: https://openaccess.city.ac.uk/id/eprint/1732/
- Callaghan & Müller-Hansen 2020: https://pmc.ncbi.nlm.nih.gov/articles/PMC7700715/
- Yang, Lewis & Frieder 2021 (heuristic rules; Knee/Target/Budget restated): https://arxiv.org/pdf/2106.09871
- Lewis, Yang & Frieder 2021 (QBCB, sequential bias): https://arxiv.org/pdf/2108.12746
- Cormack & Grossman 2016: https://doi.org/10.1145/2911451.2911510
- Hennink et al. 2017 / Hennink & Kaiser 2022: https://pubmed.ncbi.nlm.nih.gov/34785096/
- van Rijnsoever 2017: https://pmc.ncbi.nlm.nih.gov/articles/PMC5528901/
- Lowe et al. 2018: https://journals.sagepub.com/doi/10.1177/1525822X17749386
- Braun & Clarke 2021: https://uwe-repository.worktribe.com/output/4820803
- Saunders et al. 2018: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5993836/
- Good–Turing (Hsu 2025 notes): https://www.cs.columbia.edu/~djhsu/coms6998-s25/good-turing.pdf
- Chao estimators: https://www.esapubs.org/archive/mono/M084/003/appendix-C.pdf
- Briand et al. capture–recapture: https://www.ehealthinformation.ca/web/default/files/wp-files/2001-A-Comprehensive-Evaluation.pdf
- Rule of three: https://en.wikipedia.org/wiki/Rule_of_three_(statistics) (Hanley & Lippman-Hand, JAMA 1983)
- Dalal & Mallows 1988 restated: https://staff.math.su.se/hoehle/blog/2016/05/06/when2stop.html
- EVPI: https://en.wikipedia.org/wiki/Expected_value_of_perfect_information; Howard 1966 IEEE SSC-2(1):22–26
- ENBS: https://rdrr.io/cran/voi/man/enbs.html
- Ferguson, Optimal Stopping ch. 5: https://www.math.ucla.edu/~tom/Stopping/sr5.pdf
- Weitzman 1979: https://econometricsociety.org/publications/econometrica/1979/05/01/optimal-search-best-alternative; https://arxiv.org/pdf/2301.13534
- Ramdas et al. 2023 SAVI: https://arxiv.org/abs/2210.01948
- Sharma et al. 2023 sycophancy: https://arxiv.org/abs/2310.13548
- Huang et al. 2024 self-correction: https://arxiv.org/abs/2310.01798
- Avestimehr, Duffy & Médard 2026 NOVA: https://arxiv.org/abs/2605.15219
- Soudani et al. 2026 deep-research stagnation: https://arxiv.org/abs/2608.15191
