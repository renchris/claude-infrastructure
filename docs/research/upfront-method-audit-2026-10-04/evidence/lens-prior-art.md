# Lens: external prior art — is method v1.1 the strongest known way to make an upfront completeness claim hold?

Auditor: one of nine, 2026-10-04. Read-only except this file. Paths are relative to the worktree
`/Users/chrisren/Development/.worktrees/wt-cc-024434-55635` unless absolute.
Labels: **measured** (counted from data this session or by the cited study), **modeled** (simulation
output), **asserted** (a document's claim I did not re-derive). "Fetched" means WebFetch/WebSearch
this session; WebSearch summaries are a summarizing model's text, so I treat them as secondary.

## 0. Bottom line

The method already borrows most of the strongest prior art: declared frame plus owned TBD/TBR items
and change control (NASA/DoD/DO-178C), independent blind review without meetings or debate,
capture-recapture and error seeding, set-based decisions, a walking skeleton, reference-class
timing, and a feedback loop from escapes to the checklist. Where it falls short of prior art is
**in the parts the calibration study measured as broken**, and for each one a known mechanism
exists that the method does not use:

1. Triage: 1.13 false material calls per reviewer-read (measured) and no calibrated acceptance
   rule. Prior art: conformal risk control / Learn-then-Test on a labelled set, Cooke's
   seed-weighted experts, decomposed binary rubrics. The method's own 2026-09-30 literature review
   recommended two of these (T7, T13); neither reached the method. The reviewer's
   `p_real_material` is collected and consumed by nothing.
2. Forecast: the printed 95% bound "holds" because it is very wide (per-plan median 44, range
   18 to 697, against a realized median of 12; measured from `research-calibration.jsonl`). Prior
   art says to maximize sharpness subject to calibration and to score forecasts with proper rules.
3. Perspectives: the default (lite) profile runs only `full-context` and `plan-only`. Pre-mortem,
   consumer, ops/security and frame-rows-only never run and were never measured. Every reviewer
   gets the same 11-lens checklist, which is the setup the inspection literature found no better
   than ad hoc reading.
4. Omissions (58% of holes, caught at 28% per round, measured): no omission detector independent
   of the plan text. Prior art: NASA IV&V's independently built reference model, N-fold
   inspection, and DO-178C structural coverage analysis, whose stated purpose includes finding
   inadequate requirements.
5. STPA is only partly adopted: the step-3 grid without step 2 (control structure) or step 4
   (loss scenarios from process-model flaws).
6. Model checking is a label: there is no checker on the machine, and the liveness gate is a
   regex.

The literal goal (zero post-signoff "one more thing") is physically unattainable on two
independent grounds (§9). The strongest attainable version is the one the method targets: 100% of
a signed frame, plus a forecast that is both calibrated and **sharp**, plus parking and relaying.
Item 2 is where it currently misses that version.

## 1. What our method has (receipts)

- Lite = `per_slot_set` 2 → strategies `STRATEGIES[:2]` = `full-context`, `plan-only`
  (`scripts/research-kit/lib/kit.py:92-99`, `:122-131`, `:176`). Decision 4 makes lite the default
  for every size (`docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md` §9 row 4,
  `docs/research/research-calibration/REPORT.md` §1).
- Reviewer brief: the same 11 lenses for every reviewer, plus `p_real_material` per finding
  (`skills/research-program/briefs/reviewer.md`). Command
  `grep -rn 'p_real_material' scripts/research-kit skills/research-program | grep -v briefs/reviewer.md`
  => no output. The probability is consumed nowhere.
- Rater brief: open clause rubric (a)-(g), with M/R/C/G labels (`skills/research-program/briefs/rater.md`).
- Rater 2 reviews every singleton, but no rule requires support or reproduction for a singleton
  (`REPORT.md` §3.8, verification and rating item 2). `grep -n -i 'conformal|corroborat|abstention'`
  over REPORT, the calibration REPORT and the build plan => no hit.
- Prior literature review recommended: "A new item counts only if ≥2 of N raise it independently
  … or one raises it with a receipt that a separate verifier confirms by reproduction"; and
  "Calibrate the threshold once on a labelled set of past raised items (real vs churn), then apply
  it mechanically" (`docs/research/upfront-research-exhaustion-2026-09-30/evidence/external/llm-failure-modes.md:121`, `:70`).
  The built method kept reproduction but dropped the corroboration rule and the calibrated threshold.
- Calibration, measured (n=16 plans, one round): false material 1.13 per read (0.22 counting only
  false), downgrades 0.2, omissions 58% caught at 28% vs commission 37%, fix-born 0.21, per-read
  recall full 0.22 / plan 0.11, phi Opus–Opus(frontier slot) 0.62, Opus–OpenAI 0.51, fitted share of
  holes no slot reaches in one round `u` 0.6 (`docs/research/research-calibration/REPORT.md` §1,
  §4.1, §4.5, §4.7; `docs/research/research-calibration/evidence/fit.json`). Rater 1's refutations
  are uninformative: 43% on known-real holes against 36% on unmatched ones (§4.1).
- Ground truth that already exists for threshold calibration: "`evidence/adjudicate/` holds the
  ground truth for 160 items" (calibration REPORT §6).
- Detection model: strategy effect `h ~ N(0, sd_s)` with `sd_s` = 0.5, assumed
  (`evidence/design/cert_sim.py:12, 59`). The extra strategies are modeled, not measured.
- STPA: only "control actions and write paths × the four unsafe types" (`REPORT.md` §3.3, Grids).
  `grep -i 'control structure|process model|loss scenario'` over the skill, kit and REPORT => none.
- Model checking: `"model-check": 5` is a probe kind that earns evidence level 5 on exit 0 plus a
  negative-control record (`scripts/research-kit/lib/kit.py:357-360`). `which tlc alloy apalache`
  => not found, while `/usr/bin/java` is present. The liveness gate is
  `re.search(r"liveness|eventually", str(x))` over property strings, and it is skipped when
  `properties` is absent (`scripts/research-kit/lib/gate_rows_a.py:448-455`).
- Forecast sharpness, measured this session from `docs/research/research-calibration.jsonl`
  (python tabulation): per-plan `forecast_95` = 42, 55, 18, 620, 697, 55, 18, 46, 55, 21, 21, 465,
  37, 21, 387, 33 (median 44.3); `forecast_point` median 5.5; `realized_missed` median 12.0. The
  bound held on 15 of 16 and the point was exceeded on 6 of 16 (REPORT §3.12 calibration text).

## 2. Prior art, one family at a time

| Family | What it guarantees | Measured effectiveness | Our equivalent | Verdict |
|---|---|---|---|---|
| NASA NPR 7123.1 / SE Handbook; DoD milestones; CCB | Completeness relative to a baseline: TBD/TBR named, owned, scheduled; changes go through a CCB | Process standard, no effect size | Signed frame, residual rows, §5 change control (`evidence/external/systems-engineering.md` §1-2) | **Equivalent or stronger** (the gate computes its predicates) |
| DO-178C trace + OPR classes (AMC 20-189) | Bidirectional trace; only "Significant" open problem reports block approval | Standard | Trace check, materiality classes, carried rows | Equivalent |
| DO-178C **structural coverage analysis** (§6.4.4.3) | Exposes "shortcomings in requirements-based test cases", "inadequacies in software requirements" and dead code (secondary: https://ldra.com/ldra-blog/do-178c-structural-coverage-analysis/, fetched via search) | Standard practice; no effect size | **None.** No coverage-driven omission check over the code the deliverable touches or over the skeleton | **Gap** (F4) |
| NASA IV&V | Independence on technical, managerial and financial axes; IV&V builds its own system reference model and validates requirements against it (search summary of NASA IV&V docs, https://www.nasa.gov/?p=97667 and the IV&V technical framework; the framework PDF returned 404 on fetch) | Program-level | Vendor-diverse reviewers give technical independence. Two derivation panels in the frame critique only (`REPORT.md` §3.2 step 6). Certification readers are anchored on the plan | **Partial** (F4) |
| ISO 26262 confirmation measures / FMEA | Independent confirmation review; component × failure-mode table | — | Gate, grids | Partial; acceptable |
| **STPA** (Leveson & Thomas 2018) | Losses → hazards → control structure → UCAs → loss scenarios | Controlled experiment, 21 students: recall STPA 0.443, FMEA 0.326, FTA 0.231; coverage 0.70 / 0.60 / 0.30; time 116 / 94 / 88 min (Abdulkhaleq & Wagner, https://ar5iv.labs.arxiv.org/html/1612.00330, fetched) | Step 3 grid only | **Partial** (F5) |
| HAZOP guide words | Systematic deviation generation (no/more/less/reverse/early/late/other than) | — | Four unsafe types plus state × input | Partial; the guide words add quantity and reverse deviations |
| Requirements traceability and coverage | Orphans in either direction become detectable | — | Trace check, gate row 8 | Equivalent |
| **TLA+ / Alloy model checking** | Exhaustive within bounds; finds deep interleavings | AWS: a bug whose shortest trace was 35 steps "passed unnoticed through extensive design review, code reviews, and testing" (Newcombe et al., CACM 2015, https://cacm.acm.org/magazines/2015/4/184701-how-amazon-web-services-uses-formal-methods/fulltext, via search summary) | A "small exhaustive enumeration" contact cell, but no checker, and the evidence is a label | **Nominal** (F6) |
| Cleanroom | Box-structure specification, team correctness verification, statistical usage testing | Asserted in the literature; not fetched | The relay test (20 trials) is a small usage test | Not needed beyond the relay test |
| **Fagan inspection / reading techniques** | Defect removal before test | Fagan at IBM: 60-90% of defects removed before first test; rate ceiling about 140 lines/hour for design documents (secondary, search summary). **Scenario-based reading** gave a higher detection rate than Ad Hoc or Checklist, and "Checklist reviewers were no more effective than Ad Hoc reviewers" (Porter, Votta & Basili 1995, https://www.cs.umd.edu/~aporter/html/scenarios.html, fetched). Fusaro, Lanubile & Visaggio 1997 did not replicate the scenario advantage (https://doi.org/10.1023/A:1009742216007, search summary). Meetingless inspections lost nothing; meeting gains were offset by meeting losses (Porter/Votta, search summary) | Blind independent reviewers, no meeting. **One identical 11-lens checklist for all**; perspectives exist but are off at lite | Meeting design: **equivalent**. Reading technique: **gap** (F3) |
| N-fold inspection | Independent teams find different faults | Fault detection rate rises from 35.1% at N=1 to 77.8% at N=9; 38.9% → 83.3% at N=7; 36% → 76.4% at N=8 (Kantorowitz, Guttman & Arzi, https://csaws.cs.technion.ac.il/~kantor/publications/nfold.pdf, fetched, text via pdftotext) | Multi-vendor panel. Our per-read recall is 0.22 (measured), similar to one human team | Equivalent in structure. The low per-read recall is the limit |
| Capture-recapture / species richness | Estimate of the unseen, with assumptions | Covered in `evidence/external/unseen-estimation.md` | `estimate.py`, seeds | Equivalent |
| **Pre-mortem / prospective hindsight** | More failure reasons generated | +30% reasons (Mitchell, Russo & Pennington 1989; quality of reasons not assessed) (https://corporate.jasoncollins.blog/premortem, fetched via search) | Strategy `assume-fails-in-production`, **off at lite**, the default | **Gap at the default** (F3) |
| Red teaming | Adversarial search | — | Adversary evidence dir; seeds | Equivalent |
| Delphi | Anonymous iterated estimates | Beat staticized groups in 12 studies to 2, and interacting groups 5 to 1; no consistent edge over other structured procedures (Rowe & Wright 1999, search summary) | Raters vote blind, rater 3 settles | Adequate; no change |
| **Superforecasting / proper scoring / Cooke classical model** | Calibration tracking; performance weighting on seed questions | GJP: training, teaming and tracking all improved accuracy (Mellers et al. 2014, search summary). Cooke: performance weighting beat equal weighting out-of-sample on 26 of 33 studies (p = 0.001), with double the information at a 50% training split (Colson & Cooke 2017, search summary of https://strathprints.strath.ac.uk/60136/) | Seeds measure **panel** recall only. Reviewer probabilities are unused, no reviewer is weighted or screened by seed performance (except local models at 0.33), and forecasts get no proper score | **Gap** (F1, F2) |
| Calibration and sharpness | "Maximize the sharpness of the predictive distributions subject to calibration"; PIT histograms and proper scoring rules (Gneiting, Balabdaoui & Raftery 2007, https://sites.stat.washington.edu/people/raftery/Research/PDF/Gneiting2007jrssb.pdf, search summary) | — | Coverage only ("95% bound held") | **Gap** (F2) |
| Bayesian/statistical stopping (TAR) | Reject "recall < target" at a confidence level | Reliable recall with about 17% average work saving (Callaghan & Müller-Hansen 2020, https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7700715/, search summary) | K quiet rounds plus seed-based bound | Equivalent in spirit. At measured triage the rule never fires: 93-100% of programs hit the cap (modeled) |
| Set-based concurrent engineering | Keep options open until data narrows them | Covered in `epistemic-limits.md` §1.5 | Carried sets | Equivalent |
| Prototyping / spikes / walking skeleton / IKIWISI | Requirements surface on seeing (Boehm, IEEE Computer 33(7), 2000) | — | Contact skeleton, one reaction checkpoint | Equivalent; residual priced |
| Requirements elicitation | Structured interviews are among the most effective techniques (Davis et al. 2006 systematic review, search summary) | — | One 12-question interview, **pre-filled; you confirm or correct** | Partial (F7). Acquiescence and satisficing in agree/confirm formats (Saris, Krosnick & Shaeffer; search summary) |
| Multi-agent debate | — | Does not reliably beat self-consistency or ensembling (Smit et al., ICML 2024, https://proceedings.mlr.press/v235/smit24a.html, search summary); debate degrades through conformity (Wynn 2025, cited in `llm-failure-modes.md:43`) | Not used: blind, independent reviewers | **Strength** |
| LLM-as-judge reliability | — | Self-preference correlates with self-recognition (Panickssery et al., NeurIPS 2024, search summary). CheckEval's decomposed binary questions raised cross-evaluator agreement by 0.45 (https://arxiv.org/abs/2403.18771, fetched). LLM reviewers "frequently misclassify correct code implementation as non-compliant", and "more detailed prompt design, particularly with those requiring explanations and proposed corrections, leads to higher misjudgment rates" (https://arxiv.org/abs/2603.00539, fetched) | Rater 1 non-Anthropic (handles self-preference). The reviewer brief demands explanation, receipt and falsifier for every finding: the configuration that paper found raises false flags. Open-clause rubric, not decomposed binary questions | Partial (F1) |
| Correlated LLM errors | — | "models agree 60% of the time when both models err … larger and more accurate models have highly correlated errors, even with distinct architectures and providers" (Kim et al., ICML 2025, https://arxiv.org/abs/2506.07962v1, fetched). Locally: phi 0.51 cross-vendor vs 0.62 same-vendor (measured) | Diversity is counted by vendor | Partial (F8). Method diversity (Basili & Selby 1987: reading and functional testing find different fault classes, search summary) is the stronger lever |
| Unattainability of "prove zero" | — | Butler & Finelli 1993: quantifying ultra-high software reliability by testing is infeasible, and reliability growth models do not escape it (IEEE TSE 19(1), search summary); Link 2003 (already cited) | §7 residuals | **Correctly handled** (F9) |
| Requirements volatility | — | Requirements change at more than 2% per calendar month, ranging from under 1% to over 4% (Capers Jones via https://www.ppi-int.com/systems-engineering-newsjournal/ppi-syen-38/, search summary) | Parked next version; measured 1.6 new ideas per session-day | Correctly handled |
| Safety-case culture | — | Nimrod Review 2009: the safety case was "a lamentable job from start to finish", a "paperwork and 'tick box' exercise" (https://risktec.tuv.com/knowledge-bank/the-folly-of-paper-safety-lessons-from-the-nimrod-review/, search summary) | Gate rows re-execute predicates; reviewers are blind | Strength, with a warning that applies to F2 and F6: a certificate whose bound is uninformative, or whose "model-check" is a label, is the paper-safety failure mode |

## 3. F1: triage has no calibrated acceptance rule (the measured binding constraint)

- Measured: 1.13 false material calls per read; the stop rule needs about 0.02; 93-100% of
  programs hit the cap (calibration REPORT §1, §4.1). The calibration REPORT's own candidate fixes
  (§6) are a frame-row filter, rating against the acceptance criterion, and moving "real but not
  material" to the verifier. These are rubric tightenings with no statistical guarantee.
- What prior art adds:
  - **Conformal risk control / Learn-then-Test.** Pick the acceptance threshold on a held-out
    labelled set so that the false-acceptance rate among accepted items is at most α with high
    probability (search summary: arXiv 2608.17994, 2602.13110). The labelled set already exists:
    160 adjudicated items plus the seed cohort. The score to threshold already exists too:
    `p_real_material`, plus support count (how many independent slots raised it), plus whether an
    executable check reproduces it.
  - **Cooke's classical model.** Weight or screen each reviewer slot by its calibration on seeds,
    since seeds are exactly Cooke's "seed variables". Out-of-sample it wins 26 of 33 studies.
  - **CheckEval.** Turn clauses (a)-(g) into binary sub-questions with receipts (for (b): "name
    the acceptance row; quote its threshold; does the finding change the verdict: Y/N; run the
    command: exit?"). Measured +0.45 cross-evaluator agreement.
  - **Overcorrection evidence.** Asking for explanations and fixes raises false flags; their
    remedy is to execute the proposed fix against tests. Our analog is a finding-carried failing
    check: the finding must ship a command that fails on the frozen plan's harness and passes after
    its proposed edit.
- Why it matters for the goal: until false material calls fall about 50-fold, every program ends
  at the cap. The certificate then says "stopped at cap" and the residual is 6.5-7.6 desk holes
  (modeled, calibration REPORT §5). That is a guaranteed stream of "one more thing" after
  signoff.

## 4. F2: the forecast is calibrated by width, not by sharpness

- Measured: the bound held on 15 of 16 plans, but the per-plan bounds were 18 to 697 (median 44)
  against 12 realized. A bound that allows 44 material changes after signoff does not answer "no
  one more thing". It does report honestly, but it does not reduce surprises.
- Prior art: maximize sharpness subject to calibration, and score the whole predictive
  distribution with proper scoring rules (CRPS, log score) and a PIT histogram (Gneiting et al.
  2007). With one program every 2-3 weeks, a binary hold rate needs 59 programs for a 95% lower
  bound of 95% (`REPORT.md` §6.6). PIT and proper scores extract calibration information from
  every program's realized count, not just a hold/no-hold bit.
- Recommendation: put bound width next to the point forecast on the first line of the
  certificate; add a sharpness acceptance criterion (for example, the 95% bound at most 3 times
  the point forecast, or an absolute ceiling the operator signs at intake); log the CRPS and PIT
  value per program in `research-calibration.jsonl`; and refuse "no-take-backs" wording when the
  bound fails the sharpness criterion.

## 5. F3: the default profile turns off every perspective, and the lens list is a uniform checklist

- `kit.py:176` slices strategies by `per_slot_set`. Lite gets 2, so `assume-fails-in-production`
  (pre-mortem), `consumer`, `operations-and-security` and `frame-rows-only` never run at the
  default. Calibration measured only full and plan (fit.json). The claim that "width buys
  nothing" (REPORT §3.12 calibration reading 2) is modeled with an assumed `sd_s` and says nothing
  about these perspectives.
- Prior art: in Porter, Votta & Basili, the assigned-scenario method beat both checklist and ad
  hoc reading, and the checklist was no better than ad hoc. Their scenarios were distinct
  procedures given to different reviewers. Fusaro et al. failed to replicate the advantage, so the
  effect is real but fragile. Prospective hindsight gives +30% reasons (count, not quality).
- Our brief gives every reviewer the same 11-lens checklist. That is the "checklist" arm. Clause
  (f) (hazard, "always material") has no reviewer assigned to look for hazards at lite.
- Recommendation: at lite, replace `plan-only` (recall 0.11, half of full-context's 0.22) with one
  assigned scenario per vendor slot set, rotating pre-mortem, ops/security hazard, and
  frame-rows-only derive-then-diff. Give each scenario a procedure, not a lens. Measure
  per-strategy seed recall in the next calibration replay before freezing the choice.

## 6. F4: there is no omission detector independent of the plan text

- Measured: omissions are 58% of holes at freeze, and one round caught 28% of them against 37% of
  commission holes (calibration §4.5). Seeds measure omission recall but do not raise it.
- Prior art: NASA IV&V validates requirements against a reference model it builds itself; N-fold
  inspection uses independent teams; DO-178C uses structural coverage to find "inadequacies in
  software requirements".
- Recommendation:
  - (a) A `derive-then-diff` certification strategy. The reviewer gets the signed frame, the
    environment doctor output and the census files, without the plan; writes what the plan must
    contain; then gets the plan and diffs. This is the frontier skill's baseline-blind derivation,
    moved into certification.
  - (b) A coverage pass. Run the acceptance harness and the contact skeleton under coverage (bash
    xtrace or kcov for hooks, coverage.py for the kit). Every touched existing function, hook arm
    or caller that no acceptance row exercises becomes a frame-omission candidate. This detector is
    not an LLM, so it is not subject to the correlated-error ceiling.

## 7. F5: STPA is half-adopted

STPA's step 2 (control structure: controllers, actuators, sensors and feedback, plus each
controller's process model) is what generates the control-action population, and step 4 (loss
scenarios: why a controller would issue an unsafe action, such as stale feedback or a wrong
process model) is where the "controller believed X" class lives. Example 1 in `REPORT.md` §2.3
("Session state reported as job state") is a textbook process-model flaw. Our grid has neither
step. Abdulkhaleq & Wagner measured STPA recall at 1.36 times FMEA's and 1.9 times FTA's (modest
n=21, students). Recommendation: add a control-structure census to `checklist.jsonl` and to gate
row 2, from which the UCA grid's rows are generated; add a loss-scenario column (feedback missing,
stale or wrong; process model wrong; actuator fails) to each applicable UCA cell.

## 8. F6, F7, F8: shorter notes

- F6, model checking nominal: no TLA+/Alloy/Apalache on the machine, though Java is present, so
  `tla2tools.jar` would run. `model-check` evidence is a probe label. The liveness check is a regex,
  skipped when no property list exists. AWS's 35-step bug is the prior art for why this cell is
  worth a real tool on this machine's concurrency-heavy subjects (hooks, landing locks, daemons).
  Recommendation: ship one checker as a `probe-run.sh` verb, and require a checker output artifact
  (states explored, properties, a counterexample when the negative control is run) in place of a
  regex.
- F7, interview pre-fill: "each pre-filled from the mining; you confirm or correct"
  (`REPORT.md` §3.2 step 2). Acquiescence and satisficing literature: respondents endorse
  presented assertions, more so when the asker is seen as expert. Six of 200 holes were intent
  that existed and was never asked for (`REPORT.md` §2.2). Recommendation: unprimed answer first,
  then show the mined pre-fill and record the diff. Low cost, evidence secondary.
- F8, diversity counted by vendor: Kim et al. show cross-provider correlation stays high for
  strong models. Locally, cross-vendor phi is 0.51 against 0.62 same-vendor. Detector-type
  diversity (reading, execution, model checking, coverage, the operator's look) finds different
  fault classes (Basili & Selby). Recommendation: report the certificate's independence by
  detector type, and price non-reading detectors against reviewer reads in §6.4.

## 9. Attainability of the goal as stated

- **Unattainable, part 1: certifying that nothing is left.** Holes shared by every detector family
  are unidentifiable from overlap (Link 2003, `evidence/external/unseen-estimation.md:110`).
  Demonstrating very low residual rates by testing needs infeasible volumes (Butler & Finelli
  1993). Locally, the fitted share of holes no slot reaches in one round is 0.6 (measured fit).
- **Unattainable, part 2: no operator-originated "one more thing".** Requirements change at about
  1-4% a month industry-wide (Capers Jones). Users discover requirements by seeing artifacts
  (Boehm's IKIWISI). Locally, 1.6 new ideas per active session-day (`REPORT.md` §2.2 item 6).
  No research spend reaches ideas the operator has not had yet.
- **Strongest attainable version:** 100% of a signed frame; every post-signoff change is either a
  parked new-version idea or a counted escape against a forecast that is calibrated **and sharp**;
  answers to re-asks are relays. The method's design matches this. Its measured weak points
  (F1-F4) keep the attainable version out of reach today.

## 10. What I did not verify

- Paywalled primaries (DO-178C text, Parnas & Weiss's Active Design Reviews: the DTIC PDF returned
  an HTML stub to curl, and a 403 to WebFetch). A secondary claim of "35% more defects" for
  perspective-based reviews is unverified and not used.
- I did not read the private calibration store (`$CC_PRIVATE_DIR`). So whether support count or
  `p_real_material` actually separates the 17+72 false or immaterial items from the 40 real ones is
  untested. The F1 recommendation is to run exactly that test on the existing 160-item ground truth
  before adopting a threshold.
