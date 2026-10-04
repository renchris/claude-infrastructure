# Lens: internal soundness and statistics — working notes (2026-10-04)

Auditor scope: the method's stop rule, estimator, bound math, seeds, simulation, self-certification, and the
consistency of REPORT.md, the calibration REPORT, SKILL.md and the kit code. Read-only. All paths are relative to
`/Users/chrisren/Development/.worktrees/wt-cc-024434-55635` unless absolute. Labels: **measured** (from records or a
command I ran), **modeled** (simulation output), **asserted** (a doc's claim I did not re-derive).

Short names: R = `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`;
CAL = `docs/research/research-calibration/REPORT.md`; SIM = `docs/research/research-calibration/evidence/sim/`.

## 0. Reproduction checks (these hold up)

- `python3 scripts/research-kit/estimate.py simulate --profile {lite,standard,full} --n0 20` =>
  lite `cap_pct 48.4, desk_left 2.69, invisible_left 1.13, p_any 0.96, take_back_pct 4.2`; standard `23.4, 1.57, 1.12,
  0.87, 3.2`; full `9.8, 1.35, 1.12, 0.87, 1.4`. These match `evidence/final/profile_sim.out` N0=20 base rows exactly. The
  port is faithful (modeled). `git status --short` afterwards => empty (nothing written).
- I copied `estimate.py`'s `program()` in memory (exec of the source with one counter added, no file written) and ran it
  at the measured inputs (u 0.12, q 0.2, omit 0.58, b 0.2, N0 20). It reproduces CAL's rows exactly: desk-left lite
  6.66 / standard 6.45 at fpp 0.22, and 9.36 / 13.46 at fpp 1.13 (compare `SIM/sim-main-fa022.out`, `sim-main-fa113.out`).
  So my instrumented numbers below come from the same model.
- The hold-rate lower bound in R §6.6 (22% at 2, 74% at 10, 90.5% at 30, 95% at 59) equals 0.05^(1/n): 0.224, 0.741,
  0.905, 0.9505. The arithmetic is correct.
- R §10's Chao1 point values are the classic f1²/(2·f2): pass 1 has f1=10, f2=5, so 10.0; pass 2 has f1=13, f2=2, so 42.2
  (computed from `evidence/certification/pass{1,2}-findings.json` `times_found`). The arithmetic is correct.

## 1. The headline KPI is inverted: the "95% bound holds" claim improves as triage gets worse

Mechanism (code). `estimate.py:forecast` sets `found = sum(new_material)` over the counted rounds, where `new_material`
counts every CONFIRMED + MATERIAL hole (`lib/round.py:348-355`), real or false. It then draws the residual as
NegBin(found+1, 1−π) from the seed miss rate π (`estimate.py:predictive_draws`). False material findings therefore
inflate both the point forecast and the 95% bound. A take-back is defined as escapes > that bound
(`estimate.py:program`, `tb=`).

Same model, Lite, N0 20, other inputs at measured values (modeled; rows from `SIM/*`):

| false material / read | desk left (mean) | npred95 | point | 95% bound exceeded | point exceeded (desk) |
|---|---|---|---|---|---|
| 0.01 (`sim-attr-a-fpp.out`) | 6.24 | 15 | 7 | 1.2% | 36.8% |
| 0.02 (`sim-fpp0.02.out`) | 6.10 | 16 | 7 | 2.2% | 32.0% |
| 0.05 | 6.14 | 17 | 8 | 0.8% | 28.8% |
| 0.10 | 6.38 | 18 | 8 | 0.4% | 23.0% |
| 0.22 (`sim-main-fa022.out`) | 6.66 | 23 | 11 | 0.2% | 14.0% |
| 1.13 (`sim-main-fa113.out`) | 9.36 | 58 | 31 | 0.0% | 0.8% |

My instrumented run, ratio of mean npred95 to mean real desk residual (modeled): lite 2.6× at fpp 0.01, 3.6× at 0.22,
6.4× at 1.13; standard 2.7×, 4.7×, 8.4×.

Reading. Both exceedance rates fall monotonically as false findings rise, while the true residual stays flat or rises.
The method's headline statistic (R §1 lines 33-35, §3.12 reading 3: "The printed 95% bound still holds";
CAL §1: "because it widens with everything that goes wrong") rewards degraded triage. At measured triage the
certificate prints an interval 3.6–8.4 times the expected residual, and `lib/gate_cert.py:213` hard-codes
"take-backs 0" at issue. An interval that is never exceeded and is 4–8 times too wide is conservative and
uninformative. That is not calibration.

## 2. The stop rule cannot fire at measured inputs; the divergence rule would fire and is neither built nor modeled

- Quiet means zero verified material findings, real or false (R §3.8, lines 520-521; `lib/round.py:359`). With T
  reads per round, P(quiet) ≤ e^(−fpp·T). For Lite (T=8, K=2) that is e^−1.76 = 0.17 per round at fpp 0.22, so about
  0.03 for two in a row. At fpp 1.13 it is e^−9.0 ≈ 1.2e-4 (arithmetic). Instrumented run (modeled): the share of
  programs with any quiet round at all is lite 25% / standard 13% at fpp 0.22, and 0% / 0% at 1.13. Cap hit 97.6–100%
  (`sim-main-*`).
- The base assumption of 0.01 per read already conflicted with R's own literature row: "A neutral review of a correct
  artifact flags something at least 88% of the time" (R §2.4, line 150). That base needed triage to remove at least 98.9%
  of flags. Measured triage removed about 20% of distinct items (verifier confirmed 295/332 and raters passed 237: CAL
  §4.1, lines 107-108).
- Even the most generous reading leaves the rule dead. Forgive all 72 "real but not material" calls, which the
  frame-row clause might remove (CAL §4.1, lines 118-121), and the 17 provably false calls alone give 0.22 per read,
  which is 11× the 0.02 the rule needs (CAL §5, line 232). A false claim can still name a frame row.
- So the method as measured is a fixed budget of 6 rounds (Lite). Every certificate will read "stopped at the round cap"
  (`lib/gate_cert.py:196-199`).
- Divergence rule (R §3.8, lines 526-529): "found count stays at 0.7 or more of the previous round for two rounds while
  still at 5 or more ⇒ restructure the unit once". In my instrumented run (modeled) it fires in 9% (lite) / 64%
  (standard) of programs at fpp 0.22, and 84% / 100% at 1.13. `grep -rni diverg scripts/research-kit
  evidence/final/profile_sim.py research-calibration/calib_sim.py` => no matches. The rule is neither implemented nor
  simulated, yet at measured inputs it would trigger a rebuild of 1–2 days, plus its own fix-born text, in most
  programs.

## 3. Code defect: seed catches are counted as real material findings

- `lib/round.py:348-359` (cmd_close) computes `real` as holes that are CONFIRMED + MATERIAL **and `not
  h.get("seed_match")`**. `quiet` comes from `real`. Only after that does it call `seed.py match`.
- `seed.py:cmd_match` (179-202) marks the vault seed `caught` when any MATERIAL hole's line range overlaps the seed's
  `detect_span` (`overlaps`, 156-163). It never writes `seed_match` back onto the hole.
- `grep -rn seed_match` across the repo, excluding docs => only `lib/round.py:353,357` (readers) and
  `tests/research-kit-round.bats:152`, where the test hand-writes `"seed_match":"S-3"` into the fixture. No producer
  exists. The lead cannot set the field either, because seeds are sealed (`briefs/seed-author.md`: "the lead never sees
  them").
- Consequence (code-read): a round that catches only seeds is NOT quiet. That contradicts R §3.9 ("Seed catches never
  reset the quiet count") and the simulation (`estimate.py:program`, where seeds never enter `found`). The seed is also
  counted in `found`, so it inflates the residual a second time. The lead may also "fix" the planted defect, which
  orphans the seed (`seed.py:194-196`) and shrinks the denominator. The bats test passes only because it supplies the
  missing field.
- Matching is by proximity, not identity: any MATERIAL hole whose lines overlap the span catches the seed. At the
  plan-length cap (1 seed per 25 lines, `kit.py:165,196-200`), a finding spanning 3–5 lines overlaps some seed span
  with probability about (seed span + finding span) × seeds ÷ lines, roughly 0.2–0.4 (arithmetic, spans assumed).
  Unrelated findings, false ones included, would mark seeds caught, bias π upward and the residual downward.

## 4. Live contradiction: the signed TM2 contract prints the refuted pre-calibration forecast

- `estimate.py:36-45` still holds `BASE = dict(u=0.05, fpp=0.01, q=0.05, omit=0.3…)`, `FIX_BORN 0.1`, `U_HI 0.2`, and
  an `ASSUMED` list naming those values. `forecast()` uses BASE for the invisible mean and the round-1 R_max simulation.
  `gate_cert.py:174` copies `assumed` onto every certificate. `grep -rn 'fpp\|params-measured'` finds nothing in the
  kit that reads the measured parameters (`research-calibration/evidence/params-measured.json`).
- `intake.py:286-296,350-355` renders the contract page from `estimate.py simulate` at BASE and prints "Model output,
  uncalibrated until the calibration run (§6.6)", although that run landed 2026-10-01 (build plan A3, `72ee29cb`).
- Live record: `/Users/chrisren/Development/.worktrees/tm2-plan/docs/research/truememory-2.0-2026-09-28/program/CONTRACT.md:20-24`
  reads profile **standard**, "desk-detectable left 1.57, invisible left 1.12 … chance of at least one material change
  after signoff 0.87; chance the 95% bound is exceeded 3.2%". The operator signed that frame on 2026-10-02 and again on
  2026-10-03 (`~/.claude/autonomy/research/truememory-2-0/signoff.jsonl`, `action: frame`, pins `91c951c…`,
  `c4a115a…`). The measured model for standard at 20 holes says 6.45 desk, 3.65 invisible, P(any) 1.00 (CAL §5). TM2's
  own calibration row says 185 holes at freeze before the audit (145 after), fpp 2.0, fix-born 0.40
  (`research-calibration.jsonl`, `params-measured.json` `b_tm2 0.399`). The signed expectation is about 4× too
  optimistic for an average plan and much more for this one.
- Profile contradiction: R §6.1 (line 991) and decision 4 (R §9) say "lite is the profile for every size until triage
  brings false material findings near 0.02". SKILL.md (Stage 1 step 2) still says "lite for case-sized work, standard
  for medium", and `intake.py` accepts any profile without warning. TM2 runs standard, which costs twice the reads for
  6.45 desk holes against lite's 6.66 (CAL §5).
- Invisible share: `forecast()` prints `invisible_mean = n_hat·0.05/0.95`. At the measured u 0.12 the factor is 0.136,
  so the certificate understates the invisible part about 2.6× (arithmetic). `U_HI 0.2` sits below the measured upper
  bracket (pooled `u_hi 0.234`, per-plan 0.34, CAL §4.4).

## 5. REPORT.md headline sections still carry the pre-calibration numbers

- R §1 lines 33-36: the bound is "exceeded … in about 1–4%"; "The typical-case forecast … the simulation does not yet
  report that rate"; "about 6–9 in 10 with a strong front end". Measured (CAL §5 / R §3.12 addendum, lines 702-719):
  P(any) 1.00 in every profile, and about 6.5–7.6 desk plus 3.0–4.7 invisible material changes after signoff at a
  strong front end (20 holes). The typical forecast's exceedance is now reported (14% Lite measured; 22–38% base).
- §10 item 14 (line 1320) required changing "6–9 in 10" to "6–10 in 10". Line 35 still reads "6–9".
- §10 item 5 says the confusion between bound exceedance and point-forecast exceedance is "Resolved in §1". But the
  §3.12 table header (line 656) still labels the 95%-bound exceedance "Chance the printed forecast is exceeded", and
  §7 (line 1104) says "The forecast is exceeded in about 1–4% of programs" and "0.7–1.6 per program at a strong front
  end".
- Wording: R line 5 and §10 speak of "3 quiet rounds"; the default Lite profile stops at 2 (`kit.py:122`, R §6.1 table).

## 6. Seeds: the controls that give the bound its meaning are not built

- R §3.9 says a blind pre-screen discards seeds it catches, so seeds resemble the harder holes; and the certificate
  prints a seed-realism check, the rater-downgrade share, the merge-error rate, the escape-seed catch rate per class and
  the fix-born series (R §3.10, lines 594-599).
- `grep -rni 'realism|pre-?screen|escape.?seed|merge.?error|downgrade' scripts/research-kit` => only `kit.py:166`
  (`"escape_seeds": 20`) and the docstring and ASSUMED strings in `estimate.py`. No pre-screen, no realism check, no
  escape cohort logic, no downgrade or merge-error tally. `gate_cert.py:lines_for` (190-235) renders none of them.
- Measured realism (from `research-calibration.jsonl`, pooled by me): seeds caught **and rated material** 35/64 = 0.547.
  Known at-freeze holes detected: 120/377 = 0.318 over all; 120/(120+126) = 0.488 over desk-findable (detected plus
  missed-desk). Seed recall includes triage (q_seeds 0.17), so seed detection alone is about 0.66 against 0.49 for real
  desk holes. Seeds were about 1.35× easier, without the pre-screen. The simulations assume seeds drawn from the same
  difficulty distribution as real holes (`estimate.py:program`, `item(blind_ok=False)`), so the modeled coverage
  rests on an assumption the calibration data contradict modestly. The bias direction (residual underestimated)
  partly cancels the false-F inflation of §1. Compensating errors are not calibration.
- Seed counts: at 1 per 25 lines the median plan carries 16, not 40 (CAL §4.11). The scap16 re-run was done at base
  inputs only (`SIM/sim-base-scap16.out`), not at measured inputs.

## 7. The only empirical test of the forecast shows coverage without skill

From `docs/research/research-calibration.jsonl` (16 rows; my computation, measured):
- Spearman rank correlation of `forecast_point` with `realized_desk_missed`: 0.24 (0.17 excluding TM2).
- `forecast_95` ranges 18.1–697.4, median 44.3, against a realized median of 3.5. The median bound is 12× the realized
  count. TM2: point 11.7, realized 151. land-ship-v2: point 21, realized 1.
- So "its 95% bound on 1 [of 16]" (CAL §4.9; R §3.12 reading 3) is coverage bought with width. The point forecast
  barely ranks plans. This is a one-round, 4-seed replay, not the full estimator, but it is the only out-of-sample
  evidence, and it is cited as support.

## 8. Where unlimited effort could go: triage, which the method does not list

- The measured model shows more desk effort does not help at measured triage: lite 6.66, standard 6.45, full 7.58 desk
  holes left (CAL §5), because each false fix breeds holes.
- With triage restored, effort pays: standard falls to 4.79 desk holes with false material calls back at 0.01, and to
  1.82 with the downgrade rate also back at 0.05 (CAL §5 attribution table, `SIM/sim-attr-*.out`). The bottleneck is
  triage precision.
- R §6.4 "Where extra budget goes, in order" still lists front end, width, depth, seeds; it has no triage line. CAL §6
  proposes three triage changes as "outside this wave's edit scope", and none was adopted: `RUBRIC.md` and
  `briefs/rater.md` match §3.11. CAL says each change "is testable on this replay's records
  (`evidence/adjudicate/` holds the ground truth for 160 items)". No wave in `docs/plans/RESEARCH_PROGRAM_BUILD.md`
  owns that test (grep for triage there finds only the wave-C job verb).
- For the operator's goal of spending as long as physically possible, the method as built has no stage where more
  spend lowers the residual at the measured inputs. The one lever that does, triage precision, is unbuilt and untested.

## 9. Literal goal versus attainable goal

- P(at least one material change after signoff) = 1.00 at measured inputs for every profile (CAL §5). With desk triage
  restored to base, the invisible residual is still 2.65–2.93, and P(any) stays at 0.94–0.98 (`SIM/sim-attr-d`, `-c`
  rows above). Invisible holes cannot be estimated from reviewer overlap (R §2.4, Link 2003, asserted).
- "Never come back with one more thing" as zero post-signoff material changes is therefore not attainable by any desk
  method, at any spend, on this evidence. The strongest attainable version has four parts: (a) no item ever produced by
  re-asking (relay-only answers, R §4); (b) a post-signoff count forecast that is calibrated **and sharp**, printed
  before signoff; (c) contact-first front-end work, which is the only lever on the invisible part; (d) triage precision
  good enough that the desk loop converges instead of capping.

## 10. Self-certification record (R §10)

- Chao1 "about 42 unfound" (pass 2) has, by Chao's 1987 log-normal interval (var = f2[(f1/f2)⁴/4 + (f1/f2)³ +
  (f1/f2)²/2] = 1484), a 95% range of about 9 to 194 unfound. Pass 1's "about 10" has a range of about 2 to 42 (my
  computation). The report prints points only.
- The rise from 10 to 42 after one fix round is the fix-born divergence signal the report itself names (12 of 17 pass-2
  findings were in text pass 1 added, R line 1292).
- §10 used Chao1 over reviewer frequencies, with no seeds. The method's estimator was never applied to its own design,
  so §10 tests the document, not the method's statistics. Gate row 15 FAILS today (build plan B1: fallback 0.96 at
  high load; recall 14/14 "only because a fallback routes as completeness"). Under R §6.5 no certificate can issue
  until the router is fixed. That is reported honestly.

## 11. Smaller estimator issues

- Shadow cohort: `estimate.py:forecast` and `program()` draw the shadow-stratum residual with `found=0`
  (`predictive_draws(rng, 0, …)`). Its mean is about π_sh/(1−π_sh) however many fixes were made. Found fix-born holes
  are pooled into the original stratum and scaled by the original seeds' miss rate, although fix-born holes had fewer
  rounds of exposure. The fix-born residual is understated when there are many fixes (code-read), which is exactly the
  measured regime (10–40 fix-born per program, `sim-main-*` "fix-born").
- Caps live in code and are enforced: `lib/round.py:168-172` refuses past R_max, and 179-181 refuses after the stop
  rule fires. This is a strength.

## 12. Strengths

- The models are re-runnable and reproduce exactly (§0). The calibration was held out, audited (78% hole precision),
  and plainly reports that the stop rule cannot fire and that width buys nothing (CAL §1, §5). The "uncalibrated" label
  is kept, and the program-count lower bound is correctly computed. Gate row 15's failure is reported rather than
  papered over. Caps are code, not prose.
