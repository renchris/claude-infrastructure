# Lens: converting unbounded budget into fewer post-signoff surprises

Auditor: one of nine, 2026-10-04. Read-only except this file. Paths relative to
`/Users/chrisren/Development/.worktrees/wt-cc-024434-55635` unless absolute. Labels: **measured** (counted from
records or a command run this session), **modeled** (output of the calibration simulator run this session),
**asserted** (my judgment or an effect size I chose).

## 0. Answer first

The method gets the direction right and the conversion wrong. §6.4 ranks the front end first and refuses to buy
desk review, and the model confirms that at measured triage more review is neutral or harmful. But the levers that
could turn unlimited budget into fewer surprises (contact, a throwaway build, generating the plan more than one way)
are stopped by a clock, not by their yield. Code offers no way to buy more of them. The operator's escape-cost
number is collected and then used by nothing. Today the binding constraint has two halves:
1. Review cannot absorb budget. The measured false-material floor is 0.22 per read, 11 times the 0.02 the stop rule
   needs. Nothing that has been built targets that floor.
2. Front-end spending cannot be priced. The model treats holes at freeze (N0) and the invisible share (u) as
   exogenous inputs, so no one can say when to stop spending there. Spend is set by timeboxes.

So an operator with infinite budget, running this method as built, spends a fixed 6.5–28 days. The only extra thing
code lets them buy is the one the calibration showed does nothing.

## 1. Receipts read

- REPORT `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`:
  - §1:16-39, §2.2:73-106, §3.4:337-362, §3.6:407-428, §3.8:446-540, §3.12:638-725.
  - §6.1:964-1010, §6.4:1028-1040, §6.5:1042-1075, §7:1099-1115, §9:1162-1180, §10:1273-.
- Calibration `docs/research/research-calibration/REPORT.md` (all), `research-calibration.jsonl` (16 rows),
  `evidence/params-measured.json`, `evidence/fit.json`, `calib_sim.py`, `analyze.py:385-414`.
- Kit:
  - `scripts/research-kit/estimate.py` (all), `lib/kit.py:115-200`, `lib/round.py:160-172`,
    `lib/gate_rows_b.py:400-420`.
  - `scripts/lib/operator_sign.py:22-44`, `intake.py:179-419` (grep), `skills/research-program/briefs/rater.md:8,18`.
- Evidence beside REPORT: `evidence/internal/plan-lifecycle.md:7-13`, `evidence/internal/greenfield-cases.md:17-23`,
  `evidence/external/epistemic-limits.md:9,39-64,107-110`.
- Live pilot, read only:
  - `~/.claude/autonomy/research/programs.json` (truememory-2-0, state `registered`).
  - `~/.claude/autonomy/research/truememory-2-0/rounds/fc{1,2}/matrix.json`.
  - `/Users/chrisren/Development/.worktrees/tm2-plan/docs/research/truememory-2.0-2026-09-28/program/`
    (`contact_matrix.json`, `frame.json`, `budget.json`, `residual.jsonl`) and `stage4-work/PLAN.md` § Outcome.
  - tm2-plan commits `6254d278e`, `0b3b52446`.

## 2. The model runs (modeled; read-only, nothing written)

Command, run this session: `PYTHONDONTWRITEBYTECODE=1
PYTHONPATH=docs/research/upfront-research-exhaustion-2026-09-30/evidence/design:docs/research/research-calibration
python3 - <<EOF … calib_sim.run(...) … EOF`.
- It drives `calib_sim.program`, whose `--control` reproduces `profile_sim.out` (calibration REPORT §5).
- Setup: the two-vendor Lite composition (what the replay ran), 500 reps, seed 7.
- Measured base inputs: u 0.12, fpp 0.22, q 0.2, omit 0.58, b 0.2, surf_blind 0.5, N0 20 (calibration §3).
- "E[surfaced]" = desk_left + 0.5 × invisible: the model's expected material changes after signoff
  (surf_det 1.0, surf_blind 0.5).

| # | Scenario (what I changed from measured) | Hit cap | Desk left | Invisible left | E[surfaced] | P(any) |
|---|---|---|---|---|---|---|
| 0 | none: measured Lite, two vendors | 95.6% | 7.44 | 2.75 | **8.81** | 1.00 |
| 1a | width: Standard | 100% | 6.45 | 3.35 | 8.13 | 1.00 |
| 1b | width: Full | 100% | 7.27 | 4.27 | 9.40 | 1.00 |
| 2a | depth: Lite with hard cap 12 | 78.4% | 6.52 | 3.02 | 8.03 | 1.00 |
| 2b | depth: Full with hard cap 30 | 100% | 9.75 | 6.01 | **12.75** | 1.00 |
| 3a | triage: fpp 0.02 | 58.6% | 6.98 | 2.72 | 8.34 | 1.00 |
| 3b | triage: fpp 0.02, q 0.05 | 71.8% | 4.48 | 2.75 | 5.85 | 1.00 |
| 3c | triage fpp 0.02, q 0.05, then Full width | 31.2% | 1.79 | 2.98 | 3.28 | 0.97 |
| 3d | triage fpp 0.005, q 0.02, Full, cap 30 | 0% | 1.26 | 2.96 | 2.74 | 0.95 |
| 3e | q 0.1 only (a partial frame-row filter) | 96.4% | 5.61 | 2.97 | 7.09 | 1.00 |
| 4a | front end: N0 10 | 92.8% | 4.00 | 1.53 | 4.76 | 1.00 |
| 4b | front end: N0 5 | 86.6% | 2.29 | 0.88 | 2.73 | 0.96 |
| 5a | contact: N0 10, u 0.06 | 93.6% | 4.11 | 0.86 | 4.54 | 1.00 |
| 5b | build-to-learn: N0 5, u 0.03 | 89.6% | 2.49 | 0.20 | **2.59** | 0.95 |
| 5c | build-to-learn plus triage (3b) | 21.4% | 1.52 | 0.18 | 1.61 | 0.84 |
| 6 | fix-born b 0.05 | 94.6% | 6.24 | 2.44 | 7.46 | 1.00 |
| 7a | divergent plans: N0 14 | 95.2% | 5.19 | 2.12 | 6.25 | 1.00 |
| 7b | divergent plans: N0 15, omit 0.45 | 95.6% | 5.26 | 2.18 | 6.35 | 1.00 |
| 8 | every lever optimistic: N0 5, u 0.03, fpp 0.005, q 0.02, omit 0.3, b 0.05, Full, cap 30 | 0% | 0.30 | 0.20 | **0.40** | **0.35** |
| 8' | as 8, but triage left at measured | 82.4% | 1.61 | 0.18 | 1.70 | 0.90 |

**What this shows (modeled):**
- Width and depth are neutral or negative while triage is at measured values (rows 1–2). Full with a 30-round cap is
  worse than doing nothing extra (12.75 against 8.81), because every false finding that gets fixed breeds holes at
  b = 0.2.
- Triage on its own changes little in Lite (row 3a), because the downgrade rate q decides the residual (3b). Triage
  is what makes width useful (3c, 3d).
- The front end and contact are the largest single levers (rows 4–5), and they are the only ones that move the
  invisible part.
- Even with every lever at an optimistic value, 35% of programs still see at least one change after signoff
  (row 8).

**Big caveat (asserted):** N0 and u are exogenous in this model. Rows 4, 5 and 7 show the effect of the *assumed*
reduction. They do not estimate how much contact or building achieves, because nothing measures that (§4, F-model).

## 3. The activities the brief asked about: does the method do it, cap it, or forbid it?

### 3.1 Build-to-learn: a throwaway full implementation, then a rebuild

**Does the method do it?** A thin slice only. REPORT §3.6:413-416 says "Contact skeleton = build wave 0. The
thinnest end-to-end path". The pilot built one: `tm2/slice-green 3e549ad`, probed in K5, K6, K7 and K12
(`contact_matrix.json`).

**Caps.**
- Stage 5 has a budget of 1–2.5 days (§3.6 heading; `lib/kit.py` lite `stage_days[5]=1.0`). It overruns at
  1.5× into a class-B "proceed" (`lib/gate_rows_b.py:408-417`; §6.5:1065).
- Cells that do not fit the budget are "declared up front as build-wave residual" (§3.6:423).
- A full build happens only after signoff. §6.4:1038-1039 says "the budget is then redirected to build wave 1 as
  the next research instrument". So what the build finds counts as "material changes after signoff, any cause"
  (§5.2:897-899). That is exactly the operator's "one more thing".
- There is one divergence rebuild per program (§3.8:526-529).

**Evidence that building finds what desk review misses (measured):**
- Over the 16 calibration rows, 120 known at-freeze holes were caught by the one round, 126 were missed but later
  found at the desk, and 131 were missed and later found by a non-desk detector: building, probing, production or
  the operator. That is 35% of 377 (computed this session from `research-calibration.jsonl` fields
  `known_detected`, `known_missed_desk` and `known_missed_nondesk`).
- `plan-lifecycle.md:7`: "things only visible once built or run (41, 25.9%) … verification-by-building is the top
  class at 30.2%".
- `plan-lifecycle.md:13`: the one plan that closed and stayed closed ran all 58 acceptance commands before
  building. It found 45 of them unsound and finished in 25.75 h with no reopen.
- Pilot Stage 3 contact found something in 8 of its 15 cells (K4, K5, K8, K9, K10, K11, K13, K15), with 7 clean.
  K11 is decision-changing: "TrueMemory as shipped at 063e5b8 reaches the model on none of them" (`stage4-work/PLAN.md`
  § Outcome). Stage 3 still ended on its clock: commit `6254d278e` says "stage 3 clock ended", and `budget.json`
  records stage 3 running from 2026-10-02T06:26Z to 2026-10-03T03:51Z, about 0.89 days.

**What the method's own literature says.** `epistemic-limits.md:9`: high-assurance organizations "declare the
baseline only after those instruments stop producing findings". Also Brooks, "plan to throw one away"
(`epistemic-limits.md:56-59`), and spikes and tracer bullets (`:62-64`). The method applies a stop rule driven by
yield (K quiet rounds) to desk review, which cannot absorb budget. To contact, which can, it applies a calendar.

**Marginal effect (modeled, with assumed effect sizes).** Moving the full build before signoff converts the 35%
non-desk-found class into findings made before the freeze. If that halves-to-quarters N0 and cuts u by 4×, then
E[surfaced] goes from 8.81 to 2.59 (row 5b), or to 1.61 with triage fixed (5c). This is the largest lever available.
The cost is roughly one extra build (asserted). Under the operator's stated "infinite time/tokens", cost is not the
constraint.

### 3.2 Exhaustive contact and probing of the real environment

**Does the method do it?** Yes. Stage 3 runs the doctor, the current solution, ceilings, risky premises ordered by
value, handed commands, and credential lifetimes (§3.4:350-358). Stage 5 has contact cells and fault injection.
Gate row 7 checks it.

**Caps.** Stage budgets: lite 0.75 days for stage 3 and 1.0 for stage 5 (`lib/kit.py` PROFILES), with the
1.5× overrun leading to "proceed". There is no stop rule driven by yield. The pilot's `voi_rank` was "still unset
(critic 16)" (`stage4-work/PLAN.md` § Known issues), so even the value-of-information ordering in §3.4 item 4 had not
been computed.

**Marginal effect.** The same mechanism as 3.1, at lower intensity: row 5a gives 8.81 → 4.54 (modeled, assumed
halving of N0 and u). Measured pilot yield was 8 of 15 cells, about 0.53 findings per cell, when the clock stopped
it. The stage was not quiet.

### 3.3 Much larger review with the false-material rate driven down

**Does the method do it?** It has blind triage: a verifier, three raters from different vendors, a reproduction
requirement, and seeds that pass through the raters (§3.8:503-512; §3.11).

**Caps.**
- The profile is lite by default. Full requires a false-alarm rate below 0.01 per read (§6.1:974).
- The rating re-pass runs once, and a disputed finding gets 1 reproduction probe (§6.5:1060-1061).
- The extra round set is limited to one per program (§6.4).

**Measured state.**
- False material calls run at 1.13 per read, or 0.22 counting only the claims history shows were false
  (calibration §4.1). That already includes "reproduced consequence" triage (calibration §1:20-21).
- So a reproduction requirement is in place and is not enough. 0.22 is 11× the 0.02 the stop rule needs
  (calibration §5:232-234).
- The calibration's three candidate fixes (calibration §6:252-255) were:
  - reject findings that name no frame row before any rater sees them;
  - rate against the row's acceptance criterion;
  - count "real but not material" as a refinement at the verifier.
  None of them is enforced in code. The frame-row rule exists only as a sentence the rater is told to follow
  (`briefs/rater.md:8,18`). Since 2026-10-01 no commit has touched the calibration evidence to re-test triage
  variants (`git log --since=2026-10-01 -- docs/research/research-calibration skills/research-program/briefs
  scripts/research-kit`). The ground truth for doing so exists: 160 adjudicated items (calibration §6:255).
- Rater qualification: seeds give in-program ground truth for q. The certificate *prints* the downgrade share
  (§3.8:510-511) but never uses it to select or replace raters.

**Cost of the fix experiment (modeled from `evidence/price.json` via calibration §4.8).** Triage costs 0.16 weekly
pp per plan-round, so re-triaging all 16 plans under one variant is about 2.6 pp of one account. That is cheap
against the ~10 pp the study spent.

**Marginal effect (modeled).** With triage at measured values, adding review gives zero or negative value
(rows 1–2). With triage at 0.02 and 0.05, Full width becomes worth something: 8.81 → 3.28 (row 3c). Better triage
is the gate that lets review budget convert at all.

### 3.4 Longer operator-intent elicitation

**Does the method do it?** Yes: a 12-question sitting pre-filled from mining (§3.2:231-245), one reaction
checkpoint, and at most 2 taste rounds (§3.6:424-428).

**Caps.** The checkpoint happens once, and taste gets 2 rounds (§6.5:1051).

**Measured ceiling on the benefit.** C2 holes (intent arriving late) are 12 of 200, with 2 of them
decision-changing (REPORT §2.1 table). Only 7 of 158 goalpost moves came from a new operator requirement
(`plan-lifecycle.md:7`). The pilot's Stage 1 took 1.4 h (`budget.json` stage 1, 03:11Z to 04:36Z).

**Marginal effect (asserted).** At most about 4–6% of holes, so a longer interview buys little. The better intent
instrument is an artifact the operator can react to: §6.4 item 1 and `epistemic-limits.md:110` (Boehm and FDA:
prototypes in front of real users). That instrument comes nearly free with build-to-learn (3.1), which would justify
a second reaction checkpoint on the throwaway build.

### 3.5 Mutation-style seeding

**Does the method do it?**
- Yes, at 40, 60 or 100 seeds by profile, at most 1 per 25 plan lines.
- It includes omission operators, shadow seeds and escape seeds (§3.9).
- A blind pre-screen discards easy seeds.

**Caps.** The 1 seed per 25 lines limit. The median plan, about 420 lines, carries 16 seeds (calibration §4.11).

**Marginal effect on surprises (modeled).** None. At 16 seeds "the residuals are unchanged and the printed 95% bound
widens" (`sim-base-scap16.out`, calibration §4.11). §6.4 item 4 already says seeds "tighten only the statement".
This is a strength of honesty. The unused value of seeds is rater qualification (3.3).

### 3.6 Longitudinal re-checks

**Does the method do it?** Yes, through scheduled launchd jobs: freshness, drift, market and triage (§5.5). The
five plists exist in `~/Library/LaunchAgents` (`ls … | grep research` returned 5 files). Whether they are loaded was
not checked: launchctl is out of bounds for this audit.

**Caps.** Drift re-validation once per premise per program, after which the premise becomes a carried row
(§6.5:1069). Re-checks are reads: they edit no plan and breed no fix-born holes. Under an unbounded budget, the
once-per-premise cap has no cost argument behind it.

**Marginal effect.** Detecting drift earlier does not remove the change. It moves the change earlier, and the
certificate already counts drift separately. Measured share of drift: 24 of 158 goalpost moves (15.2%,
`plan-lifecycle.md:7`) and 8 of 200 holes (C10). Mostly an irreducible limit (§7).

### 3.7 Multiple independent full plans, diverged then merged

**Does the method do it?** No. Stage 6 has "one integrator" (§3.7:432). §3.2:228-230 treats parallel plans for one
topic as a defect to prevent. That rule is about plans nobody coordinated, not about a deliberate N-version step.

**Why it targets the dominant class (measured).**
- Omissions are 58% of holes at freeze.
- One review round catches 28% of omissions against 37% of commission holes (calibration §4.5).
- Critics "audit what a plan says, not its unstated premises" (REPORT §3.2:304-305, citing shard-7:159).
- A second plan generated independently from the same records is an omission detector by construction: anything
  plan B carries that plan A lacks is a candidate omission.

**Decorrelation (measured, with a caveat).** `params-measured.json` `phi`:
- same model, same strategy: 0.367 (32 pairs);
- cross-vendor, same strategy: 0.229 (30 pairs);
- cross-strategy: −0.013 (101 pairs).

The caveat: these phis are computed only over items at least one slot detected (`analyze.py:395`), which biases
them downward. The relative order still holds. Diversity of context or strategy decorrelates detectors more than
diversity of vendor. The model (`cert_sim`) has no strategy dimension, so it cannot credit this.

**Marginal effect (modeled, assumed coverage 30–50% of omissions).** N0 20 → 14–15 gives E[surfaced] 8.81 →
6.25–6.35 (rows 7a and 7b). The cost is 2–3 integrators plus one diff adjudicator and one merge. The merge must be
capped at one so it does not re-create the open loop (TM2's b = 0.40).

## 4. Findings with receipts

**F1 (goal-mismatch, critical). Contact and building are stopped by clock, not by yield, and the full build happens
after signoff.**
- Contact and build stop on stage budgets (`lib/kit.py` `stage_days`, `lib/gate_rows_b.py:408-417`), and unfitted
  cells become build-wave residuals (§3.6:423).
- The build is the "next research instrument" only after the certificate (§6.4:1038-1039), so its finds are
  post-signoff changes (§5.2:897).
- The pilot's contact stage ended by clock while 8 of 15 cells were still producing findings (`6254d278e`).
- The method's own evidence says to baseline when the instruments go quiet (`epistemic-limits.md:9`). Building finds
  the 35% non-desk class (§3.1 above).
- Modeled effect: 8.81 → 2.59.

**F2 (defect, major). An operator with unlimited budget cannot buy front-end or contact time in code. The only
purchase is an extra review round, and the escape-cost answer drives nothing.**
- `operator_sign.py:44`: `ACTIONS = ("frame", "cert", "extra-round", "reopen", "veto")`.
- Veto applies only to an overrun default on a decision (`:23`), with no budget attached.
- REPORT §3.1:207 names a "priced, operator-bought extension", but no kit code implements it:
  `grep -rn -i 'extension' scripts/research-kit/lib` matched only "contradicts or extends" at `cli_records.py:48`.
- `escape_cost_days` is read only by `intake.py:179,274,304,362,419`, which collects and prints it. No cap, profile
  or stop rule consumes it. The pilot's value is 3.0 (`frame.json`).
- Rows 1–2: the purchasable item is the one the model shows to be zero or negative.

**F3 (binding constraint, major). Review cannot absorb budget until false material calls fall by about 11×, and
nothing built targets that.**
- Measured 0.22, needed 0.02 (calibration §5).
- The three candidate fixes are not in code (rater.md:8,18 is an instruction only).
- They have not been re-measured on the 160 adjudicated items.
- Seeds are not used to qualify raters.
- Modeled: widening and deepening review make things worse (row 2b, 12.75).

**F4 (strength, major). The method correctly refuses to convert budget into desk review.**
- It defaults to Lite, gates Full on measured false alarms, caps the extra round set, and stops on the cap round
  with verification only.
- §6.4 orders the front end first, and §6.4:1036-1040 quotes the extra round set as a change to the bound, never as
  a yield.
- Rows 1–2 confirm this is right at measured inputs.

**F5 (defect, major). The live forecast that defines a "surprise" still uses base inputs where the calibration
measured worse ones.**
- `estimate.py:329` `inv_mean = n_hat * BASE["u"] / (1 - BASE["u"])` with u = 0.05. Measured u is 0.12, so the
  invisible forecast is about 2.6× too small.
- `estimate.py:338` computes the round-1 p90 and R_max with `**BASE` (fpp 0.01, q 0.05).
- `gate_cert.py:144-149` puts `estimate.forecast` on the certificate.
- The typical-case forecast is already exceeded in 22–38% of programs at base inputs (calibration §4.9). An
  understated invisible forecast guarantees more changes "beyond what was printed".
- `estimate.py simulate --profile lite --n0 20` ⇒ desk_left 2.69 and p_any 0.97, against 7.44 at measured inputs
  (row 0).

**F6 (gap, major). The model cannot price the front end, so there is no rule for when to stop spending there.**
- N0 and u are inputs, not functions of effort (`calib_sim.program` signature).
- The stages have never run (calibration §4.10).
- Historical data cannot show the lever either: Spearman(front_end_days, holes_at_freeze_audited) is −0.04, and
  per plan line it is −0.29. n = 16, and 11 of the 16 plans had 0 front-end days (computed this session).
- So §6.4's "the front end is the only lever" is a model assumption, not a measurement.

**F7 (improvement, major). Plans are generated only one way, and omissions, the majority class, are attacked only by
critique.**
- Single integrator (§3.7:432).
- The frame critique is exactly 2 rounds, and the pilot found 22 then 18 new material items with the second round
  not quiet (`rounds/fc1/matrix.json` new_material 22, `fc2` 18).
- Cross-strategy phi is about 0, against 0.23 cross-vendor.
- Modeled: 8.81 → about 6.3 at an assumed 30% omission coverage.

**F8 (irreducible limit, major). Zero changes after signoff cannot be reached at any spend.**
- Row 8: every lever optimistic still gives P(any) 0.35.
- An upstream release lands during a program with probability 0.35–0.74 (§6.2).
- New operator ideas arrive at 1.6 per active day (§2.2 item 6).
- Holes shared by every reviewer family cannot be estimated from overlap (Link 2003, REPORT §2.4).
- **Strongest attainable version (asserted):** issue the certificate on a *built*, contact-quiet throwaway
  implementation with executed acceptance (the DOCS_CONSOLIDATION pattern, `plan-lifecycle.md:13`), and count world
  drift and new intent on their own lines.

**F9 (improvement, minor). Longer intent interviews have low marginal value. Artifacts are the instrument.**
- C2 is 6% of holes and new requirements are 4.4% of goalpost moves.
- Recommendation: a second reaction checkpoint on the throwaway build.

**F10 (defect, minor). The pilot runs the Standard profile against the calibration's "Lite for every size".**
- The pilot's `frame.json` has profile `standard`, while REPORT §6.1:991 says "lite is the profile for every size".
- At measured inputs this doubles the reads for no gain: 6.45 desk holes left against 6.66 (calibration §1).
- The kit does not enforce the default.

**F11 (gap, minor). The drift re-validation cap (once per premise per program) has no fix-born justification under
an unbounded budget.**
- Re-checks are reads.
- But detecting drift only moves the change earlier. Low impact.

## 5. Binding constraint today, stated once

For desk review: the false-material floor of 0.22 per read, against the 0.02 the stop rule needs (measured, F3).

For everything else: the front-end levers are capped by clock, there is no way to purchase more of them (F2), and
the model cannot price them (F6).

These combine so that unbounded budget converts into nothing beyond the fixed profile ceiling. The single
highest-value next experiment is cheap and needs no new program: re-run the three triage variants on the
calibration's adjudicated records (about 2.6 pp per variant, modeled). The highest-value method change is a
build-to-learn stage stopped by yield, with the certificate issued after it (F1).
