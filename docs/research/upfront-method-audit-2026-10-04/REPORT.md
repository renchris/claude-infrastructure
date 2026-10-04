# Is method v1.1 the best way to reach "100.00/100.00, no one more thing"? Audit of 2026-10-04

Read-only audit of the no-take-backs research method (method v1.1) against the operator's goal of 2026-10-04. Paths
are relative to the repo root unless absolute.

- **REPORT** means `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`, the method's design.
- **CAL** means `docs/research/research-calibration/REPORT.md`, the calibration study of 2026-10-01.
- **TM2** is the one live program, TrueMemory 2.0 (`truememory-2-0`), whose records sit in the worktree
  `/Users/chrisren/Development/.worktrees/tm2-plan`.
- Per-lens evidence is in `evidence/` beside this file.

Each number carries a label:
- **measured**: counted from data, by me this session or by the cited lens or study;
- **modeled**: simulation output;
- **asserted**: a document's claim that I did not re-derive.

## 1. The answer

**No. Method v1.1 is not yet the best attainable method for this goal. Conviction in that verdict: 93%.**

The single fact that decides it: at the method's own measured inputs, a typical program is expected to have about
**10 material changes after signoff**, and the chance of at least one is **1.00**. That is Lite at 20 holes at
freeze: 6.7 holes a reviewer could have found plus 3.0 that no reviewer finds (modeled,
`docs/research/research-calibration/evidence/sim/sim-main-fa022.out`; CAL:210-215). The operator signed the pilot's
contract against **0.87 and 1.57** (`tm2-plan/.../program/CONTRACT.md`, "Profile: standard"). I reproduced that
figure from the live estimator, which still runs the pre-calibration inputs:
`estimate.py simulate --profile standard --n0 20 --reps 300` => `desk_left 1.57, p_any 0.87, regime base` (measured).
Each of those roughly 10 changes will arrive as "oh, one more thing", and against the number he signed it will read as
a broken promise.

The verdict breaks into three parts.

**(a) Design: the right skeleton, not the best version.** Two independent designs were written from scratch, given
only the goal, without seeing ours. Both converged on the same core:
- a signed list of what "complete" means (the "frame");
- contact with the real environment early;
- capped, blind, multi-vendor review;
- a seeded estimate of what is left;
- a re-ask answered from stored state.

Ours is stronger than both on four counts:
- it is the only one that has been backtested;
- it terminates under the noise it measured;
- it routes re-asks by program state rather than by wording;
- its planted test defects ("seeds") pass through the same raters as real findings
  (`evidence/compare-blind-designs.md` §0-1).

The design has three gaps that the evidence ties directly to "one more thing":
- It certifies a frozen **plan**, and the build runs after the certificate. Both blind designs certify the **built
  artifact** before anyone says "done".
- It leaves triage unchanged, although its own calibration names triage as the main lever. Triage is the step that
  decides which findings count as material.
- It stops contact and building on a calendar timebox rather than on yield, so unlimited budget has nowhere useful to
  go.

Conviction that the skeleton is right: about 75%. Conviction that the design as written is the best attainable:
about 20%.

**(b) Built and live: present, but the parts that answer the goal are off or broken.** What is live:
- the hooks and the five launchd jobs;
- both migrations;
- all 30 research test suites, 372/372 green (measured, `evidence/lens-as-built.md`).

What is off or broken:
- **Gate row 15 fails.** Row 15 tests the classifier that routes a re-ask to "relay the certificate". The kit
  certifies only when every row passes (`scripts/research-kit/lib/gate.py:139-153`), so no program on this machine
  can get a certificate today. The fix decision, packet `4bf73c4e55d5` ("fix the classifier path"), has been open
  since 2026-10-02T00:44Z at 65% conviction, with no default and no deadline (measured).
- **The relay check fails open on fallback.** When the classifier times out, the label is "unavailable". On that
  label the check that blocks "yes, plus one more item" replies does not run (`router.py:640`), and only research
  tools are blocked (`router.py:563`). The build plan measured fallback at 0.51 at machine load 45-80 and 0.96 at
  load ~295 (asserted, `docs/plans/RESEARCH_PROGRAM_BUILD.md:171-176`). Load during this audit was 36-44 on 10 cores
  (measured, `uptime`).
- **The relay check reads wording, not content.** I ran it as a pure function this session (measured):
  - a new item written in plain prose ("the published wheel ships the maintainer API token in plain text") passes;
  - "No - escape." passes;
  - a real defect named by file path is blocked.
- **The certificate is frozen at issue time.** It prints the literal text "take-backs 0"
  (`scripts/research-kit/lib/gate_cert.py:213`) and "no programs observed yet (uncalibrated)" (`:230`), and nothing
  found after signoff ever reaches it.
- **The program covers one directory.** The registry holds one `cwd_roots` entry, tm2-plan (measured,
  `~/.claude/autonomy/research/programs.json`). Build waves and sibling worktrees therefore run under the standing
  rules that force "no, one more thing".
- **Seed catches count as real findings.** Nothing writes `seed_match` onto a finding (measured, grep: two readers
  at `lib/round.py:353,357`, one hand-written test fixture, no producer).

Conviction that the build is the best attainable: under 5%.

**(c) Proven in practice: nothing about the back half.**
- **Pilot status.** TM2 is in stage 4 of 8 and still "registered", with 0 certification rounds. Its only round
  directories are `census`, `census-grids`, `fc1` and `fc2` (measured, `ls ~/.claude/autonomy/research/truememory-2-0/rounds/`).
- **The only out-of-sample test.** This is CAL's replay of 16 held-out plans:
  - the 95% bound held on 15 of 16 plans;
  - the point forecast ranks plans poorly: Spearman rank correlation 0.24 against realized desk misses, 0.17 without
    TM2 (measured, this session, `docs/research/research-calibration.jsonl`);
  - the median bound is 44.3 against a median realized desk miss of 3.5;
  - the one plan that broke the bound was the method's own design report (22 realized against 21.16).
- **The operator's reaction to the method's main output.** At stage 4 the pilot lead closed with "Good to close: yes"
  and 16 decisions handed back at 44-89% conviction (2026-10-04T07:17:09Z). Sixteen minutes later the operator
  ordered more research on every decision (07:33:10Z; measured from transcript `b671b47e`).

What would make it the best attainable, in one line: precise triage, certification of the built artifact, and a live,
honest forecast in the words the operator signs. Section 3 ranks the ten changes.

## 2. What the goal asks that physics and statistics forbid

This is stated once, with receipts.

**"100.00/100.00 … not to come back with 'one more thing'".** Taken literally, this means zero material change after
signoff. That cannot be reached at any spend, and it could not be certified even if it were reached.

- **Holes every reviewer misses.**
  - The measured share is 0.12, bracketed 0.02-0.34 (CAL:91, 138-144).
  - Holes shared by every detector family cannot be estimated from reviewer overlap (Link 2003;
    `upfront-research-exhaustion-2026-09-30/evidence/external/unseen-estimation.md:110-112`).
- **Certifying zero is infeasible.** It needs examining at least 95% of every place a hole could be. At 60 holes, a
  5% statement needs 3,654 seeds, all caught (modeled, REPORT:1103; `evidence/design/stopping_model.out:12` in that
  dir).
- **The world moves.**
  - The pilot's contract page prints a 0.99 chance of an upstream release during the program (modeled, CONTRACT.md
    "Chance an upstream release lands").
  - 4 of 200 historical holes were unforeseeable (asserted, REPORT:1108).
- **The operator's intent changes.** 6 of 200 holes were new intent, and he has about 1.6 new ideas per active
  session-day (asserted, REPORT:1107).
- **Even the best-case model leaves changes.** With triage restored to the assumed base values, the model still
  leaves 2.6-2.9 invisible holes, and P(any change) is 0.93-0.99 (modeled, CAL
  `evidence/sim/sim-attr-c*.out`, `sim-attr-d*.out`).

**"As infinitely long (time, token, cost, effort) as physically possible".** Spending more helps only through
specific levers, and it hurts through others.

- **More desk review at today's triage adds holes.**
  - Desk holes left (modeled, CAL:37-39): Lite 6.66, Standard 6.45, Full 7.58.
  - The reason: every false finding that gets "fixed" breeds new holes at 0.21 per fix (measured, CAL:28).
- **More calendar time adds drift.** In the pilot, live reads lapse after 72 hours, and one census went stale within
  a day when an outside PR collided with planned units (asserted, `tm2-plan/.../stage4-work/PLAN.md` § Known issues).
- **The physical ceiling is quota.**
  - Every account reached 100% weekly use in every recent window (measured, `evidence/lens-critic-long-horizon-continuity-and-capacity.md`).
  - So a program displaces other work one for one. Full is about 52% of a fleet-week (modeled, same file).
- **The operator has already ruled on this.** Ruling 5 says "Infinite means the program does not start", and ruling
  8 freezes the method and allows changes "only from measured results" (REPORT:1176, 1179). The 2026-10-04 goal
  conflicts with both. That conflict needs his word; it should not be settled by quietly choosing a reading.

**The strongest attainable version of the goal.** When you are told "done":
- nothing that desk review, a probe, or building could have found is still unnamed;
- every remaining change is either a named row with an owner and a date, or counted against a calibrated, sharp
  forecast you signed beforehand;
- asking again never produces a new item.

That version has four parts:
- **Done on the built artifact.** "Done" is claimed on the built, contact-tested artifact, not only on the plan.
- **A reachable stop rule.** Triage is precise enough that the review stop rule can fire. That needs about 0.02 false
  material calls per reviewer-read; today it is 0.22-1.13 (CAL:20-23).
- **An honest forecast.** It is calibrated and sharp, stated in the units the operator experiences (all causes), and
  updated live after signoff.
- **Re-asks only relay.** A real late hazard still has a recorded channel.

Even this version expects about 4.5-5 material changes per program at 20 holes. That figure is modeled: triage fixed,
no as-built stage; desk 1.8-2.4 plus invisible 2.6-2.9. Certifying the built artifact should cut it further, but that
effect is unmodeled. **The forecast and the live counter are therefore what keep "one more thing" from feeling like a
broken promise.**

## 3. Ranked changes

The ranking puts the largest expected cut in post-signoff surprises first, weighted by conviction. "Kind" says whether
an agent can drive the change now, whether it needs an operator ruling, or whether it needs a measurement first.
Changes that alter the frozen method's text conflict with **ruling 8** (REPORT:1179, "Change only named sections, from
measured results"). Those need a ruling, not a silent edit. Code fixes that make the build match what REPORT already
specifies do not conflict.

| # | Change | Evidence | Expected effect on post-signoff surprises | Conviction | Kind | Ruling conflict |
|---|---|---|---|---|---|---|
| 1 | **Fix triage precision, measurement first.** Run a blind, vendor-diverse re-adjudication of the 129 + 31 ground-truth items using the rubric's own a-g text with no outcome test. Then A/B the candidate filters on that ground truth: frame-row pre-filter; rating against the row's acceptance criterion; executable reproduction for MATERIAL calls; Design 1's harm-weighted fix rule. Put the winner in code ahead of the raters and re-run `calib_sim`. **Do not build CAL §6's "count real-but-not-material as a refinement at the verifier" before the measurement.** | Restoring false calls and downgrades takes Standard's desk residual from 6.45 to 1.82, and the share of programs at the cap from 100% to 36% (modeled, CAL:221-230). Triage was left "outside this wave's edit scope" (CAL:250-255). RUBRIC and briefs are unchanged since 0fb32f503, which predates calibration (measured, git log). The ground truth is a hindsight line: all 129 items were verifier-CONFIRMED with consequence reproduced (measured, 129/129). The two vendor raters agree at Cohen's kappa 0.08 over 295 items (measured). 63 of rater 1's 71 not-material calls carry its own REFUTED re-verification, so that disagreement is mostly about whether a hole is real (measured). If the 72 "real but not material" items are real, CAL §6's fix leaves 9.3 desk holes against 2.3 for a precise filter (modeled, `evidence/lens-critic-materiality-ground-truth.md`) | Largest modeled lever: about 4-5 fewer desk holes per program, and the stop rule becomes reachable | 85% that triage is the lever; 35% that CAL §6's fix is the right one | needs-measurement, then needs-operator-ruling | Ruling 8 (triage is not a named section) |
| 2 | **Certify the built artifact before "done".** Add a stage after the last build wave and before implementation signoff. It reuses rounds, raters and the seed vault with code-native instruments: a failing-test repro for every finding; mutation testing of the acceptance harness, with mutants as seeds; an as-built contact re-run (clean HOME, `PATH=/usr/bin:/bin`, the scheduler's interpreter); a soak across time boundaries. Split the forecast into before and after implementation signoff | Both blind designs converge on this (`evidence/compare-blind-designs.md` A1). In the replay, 131 of 224 known holes the round missed (58.5%, TM2 excluded) were later found by building, probing, production or the operator (measured, this session). REPORT itself says "only contact or building can" lower the residual and sends the budget to build wave 1 *after* the certificate (REPORT:1036-1039) | Moves build- and probe-findable holes from after the claim to before it. Size unmodeled | 80% | needs-operator-ruling | Ruling 1 (what the certificate certifies) and ruling 8 |
| 3 | **Tell the operator the real number, and re-sign.** Make `estimate.py` load the measured parameters by default, keeping base as a labeled contrast. Re-render TM2's contract and re-present rulings 1 and 4 with measured numbers. Fix the stale text: REPORT §1 "6-9 in 10" and "1-4%" (REPORT:33-36), §7 "0.7-1.6" (REPORT:1104), the §3.12 column header, and SKILL.md:65 "standard for medium". Have intake warn on a non-lite profile | `estimate.py:36-38` still holds BASE u 0.05, fpp 0.01, q 0.05; `:329` uses BASE u for the invisible mean. Nothing reads `params-measured.json` (measured, grep). Ruling 1 resolved at 2026-10-01T06:07:33Z; calibration landed at 13:11Z the same day (measured, packet `83adb541ea19`, commit 72ee29cbc). TM2's page (rendered 2026-10-02T06:12:59Z) prints 0.87 and "uncalibrated until the calibration run". TM2 runs Standard; at its measured size (185 holes at freeze) Standard may beat Lite (60 holes: 24.7 against 27.0 total, modeled, sim-main-fa022) | Removes none of the holes, but about 10 arrivals become announced events instead of broken promises | 95% | drivable-now (code, text); the re-sign and TM2's profile are needs-operator-ruling | Rulings 1 and 4 must be re-presented, not edited around |
| 4 | **Make the re-ask layer able to certify, and make it hold.** Move the classifier off a cold `claude -p` (resolve `4bf73c4e55d5`). Run the relay check on "unavailable" turns whose reply opens with a verdict. Score a fallback honestly in `heldout.py:219`, which today counts it as completeness. Give a fired or recycled successor's machine-envelope first prompt a deterministic label instead of "deny every tool". Register build and sibling worktrees as program roots, and give `completion-assert.sh` D4 the prompt-alias key. Render the certificate live: an after-signoff counter from `changes.jsonl`/`challenges.jsonl`; no literal "take-backs 0"; lines for residuals, scheduled checks and Built/Live, as REPORT:815-816 specifies | Row 15 FAIL means no certificate (`gate.py:148`). The fallback path is `router.py:352-360`, `:563`, `:640`. Unlabeled defaults to completeness, which denies everything (`router.py:532`). A HANDOFF-ENGAGE brief is not "genuine" (`router.py:83-85, 340`). `cwd_roots=[a.root]` comes from `gate.py:116`. Scheduled triage writes post-signoff records that the renderer never reads (`gate_cert.py:190-230`) | Without it: no program reaches the certificate, about half of re-asks at today's load skip the relay check, and build waves get the standing "drive it" rules | 90% | drivable-now; the classifier time limit is decision `4bf73c4e55d5` (needs-operator-ruling) | None for the code fixes; they implement REPORT §4 |
| 5 | **Make rounds survive a 24/7 regime.** Re-run dead, missing and partial slots (today only voided ones re-run). Refuse to close a round with a non-complete planned slot. Make round re-entry resumable after a process death. Preflight lanes before `open-round`, and do not spend R_max on infrastructure-lost rounds. Add a gate row requiring stop "dry" or "cap reached by counted rounds". Sweep registered programs on the schedule. Add a program lease, and lock id minting and the seed vault | `cli_cert.py:273` skips dead panels, and `round.workflow.js:69-76` re-runs only voided ones. A lane counts as live if any one slot completed (`cli_cert.py:332`). The live sweep logs "no program in certifying\|certified" hourly (measured, `~/.claude/logs/research-sweep.out.log`; `cli_jobs.py:44`), so TM2's class-B defaults due 2026-10-06T04:00Z will not reach its records | Prevents "quiet" rounds that had missing reads, and permanent wedges that end in hand-edited records | 90% | drivable-now | None |
| 6 | **Fix the statistical core in code.** Write `seed_match` before computing quiet, matching by defect identity rather than line overlap (`seed.py:198`). Deflate `found` by a measured false-material rate. Give the shadow stratum its own found count (`estimate.py:324` passes 0). Raise U_HI to the measured bracket. Report bound sharpness (bound ÷ realized) and rank skill beside coverage. Build the seed pre-screen and a realism statistic | Every false material call inflates the bound, so its hold rate improves as triage worsens: bound exceeded 1.2%, then 0.2%, then 0.0% as false calls go 0.01, 0.22, 1.13 (modeled, `evidence/lens-internal-soundness.md`). Seeds were caught and rated material at 35/64 (measured) against 0.488 detection for real holes (asserted, same file). Spearman 0.24; median bound 12.6× the realized desk misses (measured) | The certificate's numbers start meaning what they say; the headline measure stops rewarding worse triage | 90% | drivable-now | None |
| 7 | **Point unlimited budget at the levers that pay.** Stop contact and the skeleton on yield (K quiet probes) rather than on a stage clock. Let `escape_cost_days` drive a value-of-information rule: keep probing while measured finds per day × escape cost > 1. Add a priced per-decision research extension to the operator menu. Tag every decision below 90 by what blocks it, and default or carry only rows blocked by the operator or by production. Instrument the pilot so front-end yield can be fitted | Stage 3 and stage 5 in Lite get 0.75 and 1.0 agent-days (`lib/kit.py` PROFILES); an overrun yields only a "proceed" packet. `escape_cost_days` is collected and printed and nothing reads it (measured, grep: `intake.py:179,274,304,362,419` only). Signing actions are frame, cert, extra-round, reopen and veto (`scripts/lib/operator_sign.py:44`). The operator re-ordered research 16 minutes after the stage-4 close (measured). The model cannot yet price front-end effort: 11 of 16 replay plans had 0 front-end days (measured) | Contact is the only lever on the invisible share (REPORT:1030-1031); size unmeasured | 70% | needs-operator-ruling, plus needs-measurement for the yield model | Rulings 2 (timebox receipt), 5 (how the escape cost is elicited) and 7 (class C converts to a class-B default) |
| 8 | **Strengthen the omission defenses.** Omissions are the largest class. Changes: review censuses until two consecutive runs add nothing (today a census is reviewed once); after the 2 frame-critique fix rounds, run review-only rounds until one is quiet, or print an estimate of remaining frame omissions; add the operator's literal close question as a certification strategy and add "100.00/100.00 complete" to the rehearsal phrasings; add a derive-then-diff strategy and STPA's control-structure and loss-scenario steps; ask intake questions 3, 4, 5 and 16 unprimed before showing the pre-fill; add checklist rows for persistence and for lessons learned | Omissions are 58% of holes at freeze; one round catches 28% of them against 37% of commission holes (measured, CAL §4.5). The census critic refuses a second run (`lib/cli_records.py:180-182`). The frame critique is "Exactly 2 rounds" (REPORT:1049); TM2's fc1 and fc2 found 22 and 18 material, but most fc2 finds were in fc1's own edits, so this calls for review-only rounds, not more fixing. All 12 TM2 intake answers came through multiple-choice confirmation (asserted, `tm2-plan/.../intake-answers.md`) | Attacks the class that most often returns as "I forgot". Size unmeasured | 65% | needs-operator-ruling | Ruling 8 |
| 9 | **Give refinements and hazards somewhere to go.** Give the apply-at-build list a record, a writer, a certificate line and a build-completion gate, and route the triage "immaterial" bucket into it. Give a rubric clause (f) hazard a recorded channel on relay turns: a whitelisted `cc-research concern add --raised-by agent` that writes to the triage queue only, never to the reply | No kit code reads a REFINEMENT-level hole; the list exists only as prose (measured, grep: `intake.py:68-69`). TM2 writes `apply-at-build.jsonl` from a pilot-local script. About 29% of historical post-claim holes are a class the rubric rates immaterial (asserted, materiality lens). On relay turns every tool except the certificate read is denied (`router.py:537-548`) | Refinements stop being silently dropped and resurfacing at build; a real hazard seen at "are we done?" is recorded rather than muted | 85% (apply-at-build); 70% (hazard channel) | drivable-now (apply-at-build implements the spec); needs-operator-ruling (hazard channel) | The hazard channel reverses REPORT §4.4 ("An agent cannot file a concern inside a completeness turn"), adopted under ruling 8 |
| 10 | **Outside programs: stop computing the first "yes" blind.** Capture the frozen scope as checkable items. Report SCOPE=unverifiable for a prose-only definition of done, instead of "met". Allow one bounded, fresh-context review before the first "Good to close: yes" on a task that has a plan | `scripts/wrap-ledger.sh:686-699` counts only unchecked `- [ ]` lines, so a prose `Scope (frozen):` line always reads "met". Of 76 live DoD files, 4 have any checkbox (measured, operator-interface lens). `CLAUDE.global.slim.md:178` forbids "a reflexive double-check pass or verify subagent over your own finished work" | Everyday sessions, where the method does not apply, lose their most mechanical source of "one more thing" | 75% | needs-operator-ruling | The operator's global verification rule, not §9 |

Two cautions apply to every row.

- **This audit is itself an open desk review of the method, outside any program.** REPORT §10 measured what that kind
  of review does: the estimate of unfound items grew from about 10 to about 42 after one fix round, and 12 of 17
  pass-2 findings were born in the fixes (REPORT:1280-1293). So act on these changes through ruling 8's route
  (measured results, named sections, priced), not as another critique-and-fix loop.
- **Rows 4-6 make the build match its own specification.** They are bugs, not method changes, and they are what
  stands between the pilot and any certificate.

## 4. Strengths worth keeping

Each of these was verified by at least one refutation pass.

- **Caps on the loops that get worse with spend.** The method caps fix-and-review loops (fix-born 0.21 per fix, 0.40
  under TM2's open loop, measured, CAL:123-131). It caps research on a re-ask (an "Are you sure?" flips answers 46% of
  the time; asserted from external papers). It caps open critique loops (23, 21, 24, 28 new blockers per round;
  REPORT:96-98). It parks new ideas with a priced override.
- **The loop it replaced failed measurably.** TM2's open loop ran 29 critique rounds with 519 verified findings and did
  not converge. Round 1 had 37, round 22 had 7 and round 29 had 21 (measured, git log on `tm2-plan-replan`).
- **Contact before design found real defects** that the desk plan did not have. TM2's contact matrix had 8 of 15 cells
  with findings: red CI legs on Windows and macOS; shipped hooks that never reach the model on several hosts; a gap in
  `forget` on builds without JSON1; branch-only files surviving the public projection. Two other cells, K4 and K8,
  were already known (measured, `tm2-plan/.../program/contact_matrix.json`).
- **Two-method censuses caught population omissions before signoff.** They found a 9th host adapter and the JSON1
  axis, which became known rows KR-01 and KR-02. All 90 premises carry re-check commands (measured, adversarial lens).
- **The method was backtested.** It is the only one of the three designs with a held-out replay, and it reversed its
  own "widest tier" recommendation on that evidence (CAL §1-3).
- **Detection is measured times triage.** A seed counts only if a hole rated MATERIAL overlaps it (`seed.py:183-198`).
- **Re-asks are routed by program state.** On a positive completeness label, research tools are blocked, and the
  priced menu never reaches the reply (`router.py:537-548`).
- **The machinery is sound where it reaches.**
  - The registry fails closed on a missing or unparseable file.
  - The exemption text is byte-identical across the live copies.
  - The models reproduce exactly (`estimate.py simulate` matches `profile_sim.out`).
  - The caps live in code, and `round.py` refuses a round past R_max.
  - An account switch or `/compact` keeps all program state, because records live under
    `~/.claude/autonomy/research`, not in the per-account config dir.

## 5. Checked and rejected

12 of 136 findings did not survive refutation. Each is listed with the reason. A rejected finding's underlying fact can
still be true, and where it matters it appears above in its corrected form.

1. **"'A higher cap would not help' is unsupported for review-only rounds."** Extra review-only rounds also produce
   false material calls (8 reads × 0.22 per read, per round), and the lens's table counted only true holes.
2. **"Calendar time is the one input where more spend makes outcomes worse."** Already stated in REPORT §1 and §7 and
   in ruling 1. The fact is kept in §2 above.
3. **"Certified always means 'stopped at the round cap'" (as-built).** Already measured and printed:
   REPORT:710 and 989-991, and the certificate's "stopped at the round cap" wording (`gate_cert.py:196-199`).
4. **"The forecast is too wide to answer the question."** The width is a replay artifact. With 4 seeds per plan, the
   bound-to-point ratio depends only on how many were caught: 7.1×, 9.2× or 33.2× (measured by the refuter). The
   narrower point, that no sharpness or rank skill is reported, survived as row 6.
5. **"Independence is counted by vendor, but errors correlate."** The method already ranks non-reading detectors and
   the front end ahead of reviewer width (REPORT:1028-1035).
6. **"The method rightly refuses to turn budget into desk review" (a strength).** The lens's own numbers contradicted
   it: Standard 8.13 against the Lite baseline of 8.81 (modeled).
7. **"The plan is written only one way; omissions are attacked only by critique."** Censuses are already generative,
   two-method detectors. The phi ≈ 0 figure was computed only over items at least one slot detected.
8. **"Zero changes after signoff is unattainable; the best version is a contact-quiet throwaway build."** This
   duplicates the method's own statement, and its 0.4-per-program forecast is contradicted by calibration.
9. **"The pilot runs Standard against the calibration's Lite" (unbounded-budget version).** At TM2's measured size the
   design-point comparison does not apply. The question survives as an operator ruling in row 3.
10. **"81% of real replies would be blocked by the relay check."** The sample came from before the exemption existed
    and without the relay injection, and stripping the close-format lines did not remove the blocks.
11. **"The hook layer fails in the safe direction" (a strength).** Fallback fails open (row 4).
12. **"Ours terminates; the blind designs would never certify" (a strength).** The Poisson model did not match Design
    2's stop rule. "The 95% bound held" is the weak coverage claim that row 6 corrects.

Many surviving findings were also cut back in severity, from critical to major or from major to minor, because the
refuters found the core fact already acknowledged in REPORT, or the harm narrower than stated. The surviving claims are
reported here in their narrowed form.

## 6. Method of this audit

**Lenses.** There were twelve:
- **Nine audit lenses:** goal fit, internal soundness, as built, track record, prior art, unbounded budget,
  adversarial scenarios, operator interface, and a blind-design comparison.
- **Three completeness critics:** materiality ground truth, long-horizon continuity and capacity, and end-to-end live
  behavior.

**Counts.**
- 136 findings.
- 89 findings got three independent refutation verdicts: a fresh re-check, an "already addressed?" check and a
  goal-relevance check. The other 47 got one.
- 314 verdicts in all, of which 35 (11%) voted to refute.
- 12 findings (9%) were rejected; 124 survive.

**Blind-design comparison.** Two designs were written in fresh contexts that saw only the operator's goal
(`evidence/blind-design-1.md`, `blind-design-2.md`), then compared against ours, checked against code
(`evidence/compare-blind-designs.md` §1 table). Both agree with ours that open-world 100.00/100.00 is impossible. They
converge on six things ours lacks or runs weakly:
- certifying the built artifact;
- the operator's literal question as a review lens;
- census saturation;
- adjudication precision as the main spend;
- disclosure written into the relayed answer;
- an honest channel for a late real hole.

Neither has measured anything.

**What I re-checked myself this session** (all read-only):
- the estimator inputs and forecast code (`estimate.py:36-38, 316-329`);
- `estimate.py simulate`, standard and lite (outputs above);
- the gate's certify rule;
- `cwd_roots` and the registry;
- the absence of any `seed_match` writer;
- the `escape_cost_days` readers;
- the router fallback, tool-hook and relay-check paths, with the relay check run on four replies;
- the certificate renderer;
- the slot-status and rerun paths;
- the profiles and caps;
- the signing actions;
- the sweep scope and its live log;
- the ruling and calibration timestamps;
- the TM2 contract page and stage-4 outcome;
- the transcript close and re-ask;
- the replay's rank correlation, bound sharpness and missed-hole split, recomputed from
  `research-calibration.jsonl`;
- the rater kappa and the rater-1 re-verification split, recomputed from the private calibration store at
  `~/Development/claude-private/docs/research/research-calibration-2026-10-01/`. That store quotes private plans, so
  only counts are cited here.

`git status` showed only this audit directory as untracked, before and after.

**Limits of this audit.**
- **No live behavior.** No vendor CLI, quota-spending run, certification round or real routed prompt was allowed. So
  these remain unmeasured: live re-ask label rates, live relay behavior, and a blind, vendor-diverse re-adjudication of
  the materiality boundary, which row 1 depends on.
- **The calibration is thin.** It is one retrospective round over 16 plans, and every after-signoff number is modeled.
- **The back half has never run.** No program has produced a certificate, so nothing there is proven, here or
  anywhere.
- **Same model family.** The auditors share a model family with the method's author. The blind designs and the
  external sources reduce that blind spot but do not remove it.
- **Some lens measurements were not re-run.** These are the fleet quota history, the 94-prompt transcript mine and the
  TM2 contact matrix. They rest on the lens that took them.

