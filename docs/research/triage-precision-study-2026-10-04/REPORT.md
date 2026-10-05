# Triage precision study: four candidate filters tested against a blind, three-vendor reading of the rubric (2026-10-04)

This is the first step of research method v1.2 (decision `1bf69e5c1775`, adopted 2026-10-04). It follows up the calibration study (`docs/research/research-calibration/REPORT.md` §4.1, §4.6, §5) and the method audit (`docs/research/upfront-method-audit-2026-10-04/REPORT.md` §3 row 1). The per-item evidence quotes private repositories, so it stays in the operator's private store under `triage-precision-study-2026-10-04/`. This report gives aggregates only. **Measured** means counted over the study's files. **Modeled** means a `calib_sim.py` simulation or an imputation.

Terms:
- **Triage as run**: the calibration's own triage (a blind verifier, then three raters, then a reproduced consequence). It produced the "1.1 false calls per read" figure and labeled 237 of the 332 items material.
- **Blind call**: this study's re-rating. An item is called material when 2 of 3 vendor lanes say so, each reading only the finding, the plan's acceptance text and `skills/research-program/RUBRIC.md`.
- **False calls per read**: false material calls per reviewer read, over 79 reads.
- **Downgrade rate (q)**: the share of real holes that do not end up MATERIAL.
- **Post-signoff changes**: real holes still in the plan at signoff, per program. This is the desk residual plus the invisible residual, so it counts holes the desk knows about and holes it does not.
- **Lite / Standard**: the method's two profiles, capped at 6 and 10 review rounds.
- **Cap-hit share**: the share of simulated programs that reach the round cap before the quiet-round stop fires.
- **Ground-truth lines**: H (hindsight), S4 (operator-strict), S1 (rubric applied before the outcome) and R (the blind rubric line). Defined in §2.

## 1. The answer

**No candidate filter wins. Keep the calibration's triage as run.** Conviction is 70%, and the verdict is provisional. §5 says what would settle it.

**Updated 2026-10-04 (wave E3a).** §5's measurement has been run and is recorded in Appendix A. F3 applied after the triage as run fails the decision rule: on S4 it is worse in Lite and not distinguishable from the triage in Standard. The verdict above stands and is no longer waiting on that measurement.

- **On the line closest to the operator, the triage as run is best.** That line is S4: a call is false only when later history proved the claim false. There the triage as run leaves the fewest post-signoff changes of any pipeline tested: 8.86 per program in Lite and 8.83 in Standard (modeled). The best filtered pipeline is F3 with a clause-f carve-out ("F3 +f"). It leaves 11.16 / 10.36 unannounced changes, and that is with its disputed items counted as announced and re-checked at build. In total it leaves 16.10 / 16.15 (modeled).
- **The analysis stage's winner did not survive review.** That stage named F3 +f the conditional winner at 50% conviction. Two of the three skeptic passes refuted it, and both refutations stand (§4):
  - F3 +f wins only on the hindsight line, which this study shows is the worst stand-in for the operator.
  - Its "unannounced" figures gave disputed items the wrong behavior in the simulator.
- **Measured effect on false calls and downgrades.** Every filter trades false calls for downgrades.

| Pipeline | Calls kept | False calls per read, H | False calls per read, S4 | Downgrade q, H | Downgrade q, S4 |
|---|---|---|---|---|---|
| Triage as run (calibration) | 237 of 332 | 1.139 | 0.215 | 0.206 | 0.154 |
| Blind call, no filter | 224 of 332 | 1.032 | 0.217 | 0.287 | 0.285 |
| F1 frame-row pre-filter | 0 of 224 | 0.000 | 0.000 | 1.000 | 1.000 |
| F2 acceptance criterion | 157 of 224 | 0.727 | 0.157 | 0.471 | 0.504 |
| F3 executable reproduction | 68 of 224 | 0.249 | 0.040 | 0.735 (0.287) | 0.754 (0.285) |
| F4 harm-weighted fix rule | 205 of 224 | 0.896 | 0.185 | 0.324 (0.287) | 0.335 (0.285) |
| F3 +f (clause-f carve-out) | 97 of 224 | 0.352 | 0.050 | 0.647 (0.287) | 0.665 (0.285) |

  All figures are measured. False calls per read include a mid-point imputation for the 55 items with no hindsight evidence. The figure in brackets leaves out items announced at signoff (F3 MATERIAL-DISPUTED, F4 disclosed). Sources: private store, `triage-precision-study-2026-10-04/analysis/filters_eval.json` and `analysis/lines_grid.json`.
- **Only F3 and F3 +f do better than random removal, and only weakly.** They remove false calls faster than dropping the same number of calls at random, with uncorrected p between 0.016 and 0.05 (measured, `analysis/null_test.json`). Three things weaken that:
  - None of them clears a correction for the 21 tests run.
  - F3's precision gain disappears on the 8 plans where all three vendor lanes voted (§4).
  - Most of F3's cut comes from keeping fewer calls. Only 75 of the 224 calls could be run at review time, mostly because the consequence sat in code the plan had not yet built (measured).
- **Modeled effect on post-signoff changes.** Every filter raises total post-signoff changes, compared with both the unfiltered blind call and the triage as run. The reason is how the model prices each error. A downgraded real hole stays in the plan past signoff. A false call costs only a review round and a fix, and a fix breeds a new hole 0.2 times on average.
- **Counting only unannounced changes:**
  - F3 +f beats the unfiltered blind call on the hindsight line, by about 2.5 holes in Lite and 8.4 in Standard.
  - It gains nothing on S4 Lite (+0.25).
  - It never beats the triage as run on S4.
- **The stop rule.** The quiet-round stop needs about 0.02 false calls per read or fewer at q 0.2–0.29 (modeled, `analysis/sim_sweep.out`).
  - On the hindsight line no pipeline gets there. The best is 0.148, with a plan-bootstrap 95% interval of 0.076–0.232.
  - On S4, F3's 0.040 does not rule out 0.02: its interval is 0.005–0.081.
  - Under F3 or F3 +f the stop does fire, in 58–73% of simulated Lite programs. It fires only because about 70% of real holes are set aside as disputed, and those programs still end with about 16 post-signoff changes.
  - In every simulated cell the chance of at least one post-signoff change is 1.00 (modeled).
- **Why 70% and not higher:**
  - S4 is a proxy, built from one adjudicator's real-versus-false labels.
  - The simulated comparisons use point inputs, not the full uncertainty in those inputs.
  - F3 applied on top of the triage as run, instead of on top of the blind panel, is modeled to tie it on S4. That combination was never measured.

## 2. The rubric line and the hindsight line disagree

The audit's suspicion holds, and it is now measured. The calibration's ground truth sets the materiality line from hindsight: an item counts as material if later history forced the plan to change. A blind reading of the rubric sets a very different line.

The lines:
- **H (hindsight)**: the calibration adjudicator's REAL_MATERIAL label, extended by matches to known holes and seeds.
- **R (rubric)**: the blind 2-of-3 vendor call, as run.
- **S4 (operator-strict)**: every real item counts, and only claims that history proved FALSE count as false. It rests only on the adjudicator's real-versus-false labels.
- **S1 (rubric applied before the outcome)**: the audit lens's asserted, non-blind judgement of which real items the rubric would have called material.

How often each line calls an item material (measured, `analysis/lines.json`):
- The rubric line calls 224 of 332 items material (0.675). With the anthropic lane harmonized, it calls 258 (0.777).
- The hindsight line calls 70 of the 160 labeled items (0.438), and 40 of the 129 adjudicated items (0.31).

On the 160 labeled items the two lines cross like this (measured; skeptic 0 reproduced it from the raw files):

|  | Hindsight: material | Hindsight: not material |
|---|---|---|
| Rubric: material | 52 | 65 |
| Rubric: not material | 18 | 25 |

Agreement measures (measured, `analysis/agreement.json`):
- Cohen's kappa between the two lines is 0.02. Each vendor's kappa against the hindsight adjudicator is between −0.04 and 0.06, and every 95% plan-cluster interval includes 0.
- The rubric line has its own noise. Fleiss kappa among the three vendors is 0.06 as run. It is 0.24 when the anthropic lane is read the same way as the other two on the 7 plans where it applied the frame-row gate literally.
- The blind raters cannot detect a false claim. They read no code, and they called 14 of the 17 history-FALSE items material (0.82), more often than the 40 real-material items (0.73). By lane: openai 14 of 17, google 14 of 16, anthropic 7 of 17.

The lines nest, from widest to narrowest: the operator's line, then the rubric line, then the hindsight line.
- **Evidence that the operator's line is the widest (audit lens §2):** 3 of the 8 items that appeared after a completeness claim are immaterial under the rubric, and about 29% of 188 post-claim holes meet no rubric clause.
- **Share of the 112 real adjudicated items that each line calls material (measured):** hindsight 0.36, rubric 0.71 (0.81 harmonized), S4 1.00.

What this means:
- **The calibration's "1.1 false calls per read" mostly reflects its ground truth.** Counting only claims later proved false (S4), the triage as run makes 0.215 false calls per read. That matches the calibration's own "false only" figure of 0.22, and the lens's own S1 and S4 figures reproduce exactly.
- **On S4 the problem that matters is downgrades, not false calls.** The triage as run downgrades 0.154 of real holes and the blind panel 0.285. A precision filter cannot lower downgrades, and every filter tested raises them.
- **Only verification evidence separates false claims from real ones.** The triage as run put a blind verifier ahead of its raters, while this study's panel saw only the finding packets. That difference is the most likely reason the triage as run keeps more real holes (recall 0.85 against 0.72 on S4). This study did not isolate it.

## 3. Results

**Per pipeline and line.** Columns:
- False calls per read: mid-point, with the imputation range for the 55 unknown items in brackets. This is not a sampling interval (see §4).
- q: the downgrade rate, with the figure excluding announced items in brackets.
- Desk residual and cap-hit share: Lite / Standard, using the rubric-faithful total accounting. Model settings: N0 20, u 0.12, omit 0.58, b 0.2, 500 reps.

Sources: `analysis/filters_eval.json`, `analysis/lines_grid.json`, `analysis/sim_main.out`, `analysis/sim_lines.out`, `analysis/summary.json`. Precision, recall, false calls and q are measured. Desk residual and cap-hit share are modeled.

| Line | Pipeline | Precision | Recall | False calls / read | q | Desk residual L / S | Cap-hit L / S |
|---|---|---|---|---|---|---|---|
| H | Triage as run | 0.62 | 0.79 | 1.139 | 0.206 | 9.74 / 14.04 | 100% / 100% |
| H | Blind call, no filter | 0.68 | 0.71 | 1.032 (0.82–1.13) | 0.287 | 11.01 / 16.59 | 100% / 100% |
| H | F1 frame-row | – | 0.00 | 0.000 | 1.000 | 17.57 / 17.45 | 0% / 0% |
| H | F2 acceptance | 0.68 | 0.53 | 0.727 (0.57–0.80) | 0.471 | 13.23 / 19.49 | 100% / 100% |
| H | F3 exec repro | 0.72 | 0.27 | 0.249 (0.24–0.25) | 0.735 (0.287) | 15.54 / 18.44 | 97% / 100% |
| H | F4 harm-weighted | 0.69 | 0.68 | 0.896 (0.72–0.98) | 0.324 (0.287) | 11.16 / 16.80 | 100% / 100% |
| H | F2+F3 | 0.71 | 0.19 | 0.173 | 0.809 (0.471) | 16.04 / 18.44 | 85% / 100% |
| H | F3+F4 | 0.73 | 0.25 | 0.224 | 0.750 (0.287) | 15.60 / 18.48 | 93% / 100% |
| H | F2+F3+F4 | 0.74 | 0.18 | 0.148 | 0.816 (0.471) | 16.16 / 18.10 | 79% / 99% |
| H | F3 +f | 0.74 | 0.35 | 0.352 (0.29–0.38) | 0.647 (0.287) | 14.73 / 18.42 | 100% / 100% |
| S4 | Triage as run | 0.93 | 0.85 | 0.215 | 0.154 | 5.98 / 5.16 | 99% / 100% |
| S4 | Blind call, no filter | 0.93 | 0.72 | 0.217 (0.18–0.48) | 0.285 | 8.03 / 8.37 | 98% / 100% |
| S4 | F2 acceptance | 0.93 | 0.50 | 0.157 | 0.504 | 11.42 / 12.27 | 91% / 100% |
| S4 | F3 exec repro | 0.96 | 0.25 | 0.040 (0.04–0.05) | 0.754 (0.285) | 14.78 / 14.88 | 27% / 62% |
| S4 | F4 harm-weighted | 0.94 | 0.67 | 0.185 | 0.335 (0.285) | 8.95 / 9.13 | 95% / 100% |
| S4 | F3 +f | 0.97 | 0.34 | 0.050 (0.04–0.13) | 0.665 (0.285) | 13.55 / 13.43 | 42% / 76% |
| R | Triage as run | 0.73 | 0.77 | 0.823 | 0.232 | 8.98 / 12.38 | 100% / 100% |
| R | Blind call (circular) | 1.00 | 1.00 | 0.000 | 0.000 | 2.65 / 0.98 | 62% / 21% |
| R | F2 | 1.00 | 0.70 | 0.000 | 0.299 | 7.79 / 6.66 | 38% / 5% |
| R | F3 | 1.00 | 0.30 | 0.000 | 0.696 | 13.57 / 13.27 | 8% / 1% |
| R | F4 | 1.00 | 0.92 | 0.000 | 0.085 | 4.12 / 2.69 | 57% / 12% |

Filters scored on the R line are circular by construction, because R is the call the filters are applied to.

**Post-signoff changes, Lite / Standard (modeled).** Columns:
- Total: every unfixed real hole, announced or not.
- Rubric-faithful unannounced: disputed items keep the quiet count running and are deferred to build, as RUBRIC.md specifies. Each real disputed item applied at build still breeds 0.2 holes that no round reviews.
- The analysis stage's unannounced column is superseded (§4).

Sources: `analysis/sim_main.out` and `analysis/sim_lines.out` for totals; `skeptics/unann_check.py`, `skeptics/s2_faithful.py` and `skeptics/s2_compose.py` for the faithful re-runs.

| Line | Pipeline | Total | Unannounced, analysis stage (superseded) | Unannounced, rubric-faithful |
|---|---|---|---|---|
| S4 | Triage as run | 8.86 / 8.83 | 8.86 / 8.83 | 8.86 / 8.83 |
| S4 | Blind call, no filter | 10.91 / 11.97 | 10.91 / 11.97 | 10.91 / 11.97 |
| S4 | F3 +f on the blind panel | 16.10 / 16.15 | 10.43 / 9.58 | 11.16 / 10.36 |
| S4 | F3 +f on the triage as run (bounded) | 13.32–16.40 / – | – | 8.98–9.42 / 8.30–8.60 |
| S1 | Triage as run | 10.01 / 11.92 | 10.01 / 11.92 | 10.01 / 11.92 |
| S1 | Blind call, no filter | 11.81 / 14.93 | 11.81 / 14.93 | 11.81 / 14.93 |
| S1 | F3 +f on the blind panel | 16.79 / 18.51 | 10.77 / 11.02 | 11.49 / 11.78 |
| S1 | F3 +f on the triage as run (bounded) | – | – | 9.80–9.87 / 10.02–10.63 |
| H | Triage as run | 13.65 / 21.13 | 13.65 / 21.13 | 13.65 / 21.13 |
| H | Blind call, no filter | 14.90 / 23.17 | 14.90 / 23.17 | 14.90 / 23.17 |
| H | F3 +f on the blind panel | 17.71 / 22.27 | 11.85 / 13.92 | 12.1–12.4 / 14.7–14.8 |
| H | F3 +f on the triage as run (bounded) | – | – | 11.18–12.12 / – |

Notes on this table:
- **"Bounded" rows.** 65 of the triage's 237 material items have no F3 verdict. These rows bound them both ways: all pass, or all become disputed.
- **H row for F3 +f on the blind panel.** The faithful figure is a range because two independent skeptic re-runs differ by up to 0.3.
- **Applying disputed items without re-checking.** If F3 +f's disputed items are applied at build without re-verification, they add 8.2 holes in Lite and 23.8 in Standard (modeled, analytic, `analysis/summary.json` build_addon).

**What the stop rule needs (modeled, `analysis/sim_sweep.out`).** At q 0.2–0.29 the cap-hit share falls below 50% only at about 0.02 false calls per read or fewer:
- Lite: 39–49% at 0, and 53–55% at 0.02.
- Standard: 45–48% at 0.02, and 83–86% at 0.05.

At the q of about 0.735 that F3 runs at, Lite drops to 36.8% at 0.05 false calls per read.

**What F3 costs (measured).** 75 of 224 calls (0.335) could be run at review time, and 68 passed. Permission layers blocked F3 probes on 3 plans: reso-security-100p, research-report-v1 and tm2.

**Clause f under the filters (measured, `skeptics/s2_checks.py`).** The rubric says clause f items are always material, yet all four filters as defined can drop them:
- F1 drops them through the frame-row gate.
- F2 does not admit clause f as a pass route.
- F3 cannot safely reproduce a hazard by running it.
- F4 weighs fixing against leaving, which can downgrade them.

Under F3 +f, 6 items that 2 or more vendors cited under clause f still ended DROPPED. 3 of those 6 are REAL_MATERIAL, and the triage as run kept all 6 MATERIAL. Across the 74 real items any vendor cited under clause f:
- The triage as run kept 62 MATERIAL.
- F3 +f kept 47 MATERIAL, 10 DISPUTED and 17 DROPPED.

Of 99 real disputed items under S4, 95 could not be run at review time.

## 4. Skeptic results

Three independent skeptic passes ran, each through a different lens. Two returned a major refutation and both stand. That is why the winner moved from "F3 +f, conditional" to "no filter, provisional".

**Skeptic 0: statistics. Partly refuted, major.**

Reproduced:
- Every analysis script and every simulation mode re-ran with byte-identical output. The calibration control matched 9 of 9 rows.
- An end-to-end recomputation from the raw files, without the study's shared code, matched: 160 of 160 labels, kappa 0.0192, and F3 at 0.2492 false calls per read.

Refuted (all modeled unless noted):
- **The analysis stage's unannounced runs gave disputed items MATERIAL behavior.** They reset the quiet count and were fixed during the rounds. RUBRIC.md says a disputed item does not reset the quiet count and is applied at build. Corrected against the unfiltered blind call, F3 +f is:
  - S4 Lite: +0.25 instead of −0.48, so no gain.
  - S4 Standard: −1.61 instead of −2.39.
  - H Lite: −2.49 instead of −3.05.
  - H Standard: −8.40 instead of −9.25.
- **"No filter makes the stop rule reachable" is false on S4.** Under the faithful dynamics the stop fires in most S4 Lite programs under F3 and F3 +f. It does so only by deferring about 70% of real holes.
- **The table's intervals are imputation ranges, not sampling intervals.** S4 F3's 0.040 rests on 3 FALSE items from 3 plans. Its Poisson 95% interval is 0.008–0.113 and its plan-bootstrap interval 0.005–0.081, with 15% of draws at or below 0.02 (measured).
- **Multiple comparisons.** The smallest of the 21 null-test p-values is 0.016, above a Bonferroni bar of 0.007 even counting only the 7 pipelines (measured).
- **Input uncertainty never reaches the simulation.** Pipeline differences of 0.5–1 hole sit inside the spread of the inputs. For example, the unfiltered call's q has a bootstrap interval of 0.17–0.40.

**Skeptic 1: blindness, leakage and dead lanes. Not refuted, minor.**

What it checked:
- **No job read outcome data (measured).** It checked every job's own record: all 16 openai command logs, all 15 google trajectories, all 16 anthropic tool-call records and all 64 filter agents. None read labels, the calibration's private outcome files or the seed manifest. F3's git reads were pinned to the review commit or to verified-older commits.
- **Three design defects, none of which leaked:**
  - Some bundles sat under the study directory.
  - Anthropic raters received an unstripped harness-only block naming outcome paths. All 16 opened none of them.
  - Every Claude-run job (the anthropic raters and all 64 filter appliers) received the study's context block: the hypothesis, an aggregate outcome fact, and the F1 definition. The other vendors saw clean prompts.
- **Consequence of the priming.** Priming is perfectly confounded with the anthropic lane, so the study cannot say whether that lane's literal frame-row gate on 7 plans came from the model or from the brief. It did not drive the false-claim finding: the unprimed lanes produced it.

Stratified results (measured, `skeptics/1_strata.py`):
- The blind call is effectively 2-of-2 on 8 of 16 plans (173 of 332 items).
- Kappa against hindsight is +0.16 on those 8 plans and −0.15 on the 3-lane plans. The "the lines disagree" headline holds in both.
- **F3's precision gain on the extended hindsight line exists only on the 2-of-2 plans:** 0.806 against 0.707 there, and 0.639 against 0.648 on the 3-lane plans. Stratified null p-values are 0.095 and 0.167 for F3, and 0.057 and 0.130 for F3 +f.

**Skeptic 2: operator outcome and clause f. Refuted, major.**

- **F3 +f wins only on the hindsight line.** On S4, with faithful dynamics, the triage as run beats it in both profiles: 8.86 / 8.83 against 11.16 / 10.36. On S1 it also wins in Lite, 10.01 against 11.49. In Standard F3 +f is 0.14 lower (11.78 against 11.92), which is inside the input noise.
- **Layering F3 +f on the triage as run** instead of the blind panel ties it on S4 (Lite 8.98–9.42, Standard 8.30–8.60) and helps on S1 and H. Its total post-signoff changes are worse in every cell (modeled).
- **The clause-f carve-out leaks**, by the counts in §3. It protected only items that also won the 2-of-3 material vote, so items the anthropic lane cited under clause f but gated out on the frame row fell through.
- **With every clause-f item protected, F3 +f no longer beats random removal on the hindsight line** (p 0.10). On S4 it still does (p 0.026, measured).
- **A caption correction.** S4 depends on the adjudicator's real-versus-false labels alone, not on the audit lens's buckets.

**Leak audit of the public text:** clean, with 0 leaks.

## 5. What would settle it

The one untested candidate that could reverse "no filter" is **F3 applied to the triage as run's own material calls**, with clause f exempt. Run it once:

1. Apply the F3 definition already used here to the triage's 237 material calls. 65 of them still need an F3 verdict. Exempt every clause-f item from DISPUTED and from the material vote.
2. Score it with the rubric-faithful dynamics: q total, deferred items split into dropped and disputed, plus 0.2 holes for each real disputed item applied at build.
3. Pass 50–100 plan-bootstrap draws of the false-call rate and q through `calib_sim.py`, and Holm-correct the null tests.
4. **Decision rule.** Build "F3 after the triage" only if both of these hold:
   - It beats the triage as run on S4 unannounced changes in both Lite and Standard, with the bootstrap interval of the difference excluding zero.
   - It loses no clause-f item that the triage kept.

   Otherwise close the question with no filter.
5. In the same pass, make the panel symmetric:
   - Re-rate the anthropic lane through the same clean prompt the other vendors got, without the study context block.
   - Re-send the google job for agent-context-sync.
   - Re-run F3 on the 3 permission-blocked plans.

The data point to downgrades rather than false calls as the lever on the operator's line. One sensitivity reading suggests a single frameless-plan instruction for all lanes could help: harmonizing the anthropic lane cut q on the hindsight line from 0.287 to 0.176. This is a judgement-based reading, not a measured arm.

## 6. Method

Population:
- 332 distinct items: every item that went through the calibration's triage. They came from 688 raw findings in 79 non-void reviewer reads (of 96 slots) across 16 plans (measured, private store `population.json`).
- Each item became a blind packet with 8 fields: title, claim, location, quote, consequence, the reviewer's cited clause, an omission flag, and a salted id. Packets carried no members, verdicts, ratings or matches.

Per-plan context:
- The plan's acceptance blocks, copied verbatim, and a generic 30–32 row frame checklist.
- A statement that the plan has no signed frame. None of the 16 has one, because all predate method v1.

Blind rating:
- Three vendor lanes: anthropic claude-opus-5-5, openai gpt-5.6-sol at reasoning effort high, and google gemini-3.8-flash-high.
- One call per plan per lane. Each read only the packet, the context and RUBRIC.md, with sha256 pinned. Vendor CLIs ran in read-only sandboxes from temporary copies of the bundle.
- A call is 2 of 3 live lanes rating the item material, or 2 of 2 where a lane was missing.

Filters:
- Each of F1–F4 was applied to the 224 blind calls by one Opus worker per plan, for 64 applications.
- F3 ran read-only probes against the review-time bundle code.
- F4 used the measured fix-born rate of 0.21 per fix.

Scoring:
- Precision, recall, false calls per read and q, scored against lines H, S1, S2, S4 and R.
- The 55 items with no hindsight evidence were imputed at each line's negative share, with low and high bounds.
- Null test: random removal of the same number of calls.
- Cohen's and Fleiss kappa with plan-cluster bootstrap.

Model:
- The public `docs/research/research-calibration/calib_sim.py` was re-run read-only for each pipeline. The control reproduced 9 of 9 calibration rows and the calibration's main rows exactly.

Integrity:
- The analysis stage's write-up was not saved as a file, because a harness rule refused it. Every number reproduces from the scripts and JSON in private store `triage-precision-study-2026-10-04/analysis/`.
- One skeptic's script imported an analysis module whose import rewrites `analysis/lines_grid.json`. The rewrite is deterministic and its values were unchanged.

## 7. Coverage

**Plans:** 16 of 16: agent-context-sync, device-enrollment-build, hook-surface-100p, land-pipeline-v2, land-ship-v2, limit-detect-100p, limit-recover-100p, limit-recover-fleet-v2, machine-capacity-v2, research-report-v1, reso-latency-100p, reso-security-100p, sevenrooms-laptop-independence, tenant-provisioning-100p, tm2 and voiceink-latency.

**Items:** 332 rated.
- 160 carry a hindsight label: 129 adjudicated plus 31 adjudicator controls. The 129 split into 40 real-material, 72 real-not-material and 17 false.
- 55 have no hindsight evidence and are imputed.

**Rating jobs:** 47 of 48 ran: anthropic 16, openai 16 and google 15.
- **No lane was down for availability.** The missing job, google on agent-context-sync, is a courier refusal over a contradiction in its brief. It was never re-sent.
- **Two google replies returned status ERROR**, on land-pipeline-v2 and land-ship-v2. In both, the output was truncated and then completed within the same call, and the complete arrays were used. All 17 land-pipeline-v2 calls depend on that google vote.
- **The anthropic lane rated nothing material on 7 plans** because it applied the frame-row gate literally. So the call is effectively 2-of-2 on 8 plans.

**Filter jobs:** 64 of 64 ran. F3 probes were blocked by permission layers on 3 plans.

## 8. Limits

**Frameless plans.** Read literally, the rubric makes all 332 items GENERIC. Every vendor call therefore rests on substitute rows, chosen differently by vendor and by plan, and F1 cannot be tested on this population.

**Ground truth:**
- Hindsight labels come from one Opus adjudicator per plan, and hole-matched positives are about 78% precise.
- S1 and S2 rest on the audit lens's asserted, non-blind buckets.
- S4 rests on the adjudicator's real-versus-false calls.

**Blindness:**
- The context block's priming of the Claude-run jobs (§4).
- The study's frame statement, shown to every rater, names the calibration report and F1.
- Some bundles ran with their working directory inside the study directory: openai on 3 plans and google on 2. Their logs show no outside reads.
- F3 appliers on 6 plans and F4 appliers on 3 saw where the bundle differs from the review commit, which marks the seed lines. Leaving out those 6 F3 plans moves F3 from 0.249 to 0.235 false calls per read.

**Applier variance is unmeasured.** Each filter was applied by one worker per plan, and the definitions drifted:
- F2: which rows count.
- F3: where running ends and reading begins.
- F4: severity scales.

**Small counts.** The blind call contains only 14 false calls, and S4 F3's figure rests on 3. Spread across plans is large: the unfiltered call runs from 0.00 to 2.13 false calls per read, and F3 from 0.00 to 0.75.

**Model:**
- One false-call rate and one q per run.
- Point inputs only.
- The build-time add-on is analytic, not simulated.
- Runs cover N0 20 and the calibration's reviewer composition only.
- R-line rows are circular.

**Housekeeping:** one skeptic's scratch files in `/tmp/sk1/` hold private transcript excerpts and should be deleted.

## Appendix A. The reversing measurement: F3 after the triage as run (added 2026-10-04, wave E3a)

**Verdict: do not build "F3 after the triage". The question closes with no filter, and the triage stays as calibrated.** §5's decision rule fails. The second verdict, on clause f, passes, but both must hold.

This appendix records the one measurement §5 left open. Aggregates only; the per-item evidence is in the private store under `triage-precision-study-2026-10-04/f3-after-triage/` (`analysis.py`, `result.json`). **Measured** and **modeled** mean what they mean in the report above.

**The pipeline tested.** Start from the 237 items the triage as run called material. An item any vendor lane cited under clause f stays material and is never disputed (70 items). Every other item needs an F3 pass to stay material. One that fails F3 becomes disputed: announced at signoff and applied at build.

**Decision rule, as written in §5 step 4, and what happened:**

| Condition | Result |
|---|---|
| Beats the triage as run on S4 unannounced changes in Lite, bootstrap interval of the difference excluding zero | **Fails.** Difference +0.28 to +0.46 changes per program (worse); 95% intervals −0.23 to +0.88 and −0.06 to +1.05 |
| The same in Standard | **Fails.** Difference −0.34 to −0.14 (slightly better); 95% intervals −1.78 to +0.77 and −1.52 to +1.02, both spanning zero |
| Loses no clause-f item the triage kept | Passes. 0 of 70 lost, by the exemption |

Each cell gives two figures because 23 items have no F3 verdict (below). They are bounded both ways: all pass, then all disputed. The rule fails under both bounds, so the missing verdicts cannot change the verdict by themselves.

**Point results on S4, Lite / Standard (modeled, 500 simulated programs each, rubric-faithful dynamics):**

| Pipeline | Kept material | Disputed | False calls per read | Downgrade q (unannounced part) | Unannounced changes | Total changes | Cap-hit share |
|---|---|---|---|---|---|---|---|
| Triage as run | 237 | 0 | 0.215 | 0.154 (0.154) | 8.83 / 8.85 | 8.83 / 8.85 | 98% / 100% |
| F3 after triage, unknowns pass | 138 | 99 | 0.101 | 0.500 (0.154) | 9.12 / 8.61 | 13.88 / 14.49 | 77% / 98% |
| F3 after triage, unknowns disputed | 120 | 117 | 0.101 | 0.569 (0.154) | 9.24 / 8.90 | 14.90 / 15.85 | 77% / 98% |

Kept, disputed, false calls and q are measured. The rest is modeled. The triage row differs from §3's 8.86 / 8.83 by simulation noise only.

What the numbers say:
- **F3 halves the false calls and that buys almost nothing.** False calls per read fall from 0.215 to 0.101, but the stop rule needs about 0.02 (§1), so 77% of Lite programs and 98% of Standard programs still run to the cap.
- **The cost is that half or more of the real holes are set aside.** They are announced, so they do not count as unannounced, but each one applied at build still breeds 0.2 holes no round reviews. Total changes after signoff rise from about 8.8 to 14–16.
- **On the other lines F3 after triage looks better, and that does not change the verdict.** On the hindsight line its unannounced changes are 12.1–12.2 / 16.3–16.9 against the triage's 13.6 / 21.2, and on S1 it is level in Lite and lower in Standard (10.5–10.8 against 12.2). §2 shows why the rule is written on S4: the hindsight line is the worst stand-in for the operator.

**Plan bootstrap (modeled).** 100 draws, each resampling the 16 plans with replacement, recomputing the false-call rate and q for both pipelines on the draw, and running both through `calib_sim.py` with the same seed (200 simulated programs per cell). F3 after triage was better than the triage as run in 4–14% of draws in Lite and 52–72% in Standard. Input intervals across draws: triage false calls 0.145–0.286 and q 0.113–0.202; F3 after triage false calls 0.039–0.143 and q 0.43–0.66.

**Null tests, Holm-corrected (measured).** Does F3 dispute false calls faster than disputing the same number of calls per plan at random? Four tests (two lines, two bounds, 20,000 permutations each). Raw p: 0.027 and 0.079 on the hindsight line, 0.083 and 0.325 on S4. After Holm correction the smallest is 0.107. None is significant, so F3 after triage is not shown to discriminate better than random removal.

**Coverage of this pass:**
- **F3 verdicts.** 214 of the 237 items have a verdict: 152 from the study's first pass and 62 from this one. This pass probed 65 items: 45 of the 65 that had no verdict, and all 20 first-pass verdicts on the 3 permission-blocked plans. Results: 11 passed, 3 ran and did not reproduce, 48 could not be run at review time, 3 were blocked again (one by a database-statement guard, one by the test runner's load ceiling, one by a permission layer). 2 of the 20 re-runs changed their verdict.
- **Not run.** The last 20 items, spread over 9 plans, were never dispatched: the machine's capacity gate refused the worker. With the 3 blocked items they are the 23 bounded above.
- **Symmetric panel.** The Anthropic lane was re-rated on all 16 plans through the same clean prompt and bundle the OpenAI lane got, and the missing Google job for agent-context-sync was sent. All 17 jobs returned (Anthropic `claude-opus-5-5`, Google `gemini-3.8-flash-high`), one call per job, 332 of 332 item ids matched. These ratings set the clause-f exemption. The study's first-pass tables in §1–§3 were not recomputed on them.

**Limits specific to this appendix:**
- The clause-f exemption here is the wide one: any single lane's citation protects the item. With the narrower two-lane rule, 12–14 items a lane cited under clause f end disputed, 9–11 of them real. So the "loses no clause-f item" result holds only for the wide exemption.
- F3 verdicts come from one worker per plan, as in the first pass, and 48 of the 65 probed items could not be run at all. F3 after triage is mostly a "not yet buildable" sorter at review time.
- The bootstrap resamples plans and carries simulation noise. It does not resample the adjudicator's real-versus-false labels that S4 rests on.

**Consequence for method v1.2.** Change (a) builds no filter. The lever the data point to is still downgrades, not false calls (§2).
