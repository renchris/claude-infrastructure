# Lens: two blind designs against method v1.1

Auditor: compare slot, 2026-10-04. Read-only except this file and `blind-design-{1,2}.md` beside it (the two
designs, saved verbatim). Paths are relative to the worktree `/Users/chrisren/Development/.worktrees/wt-cc-024434-55635`
unless absolute. REPORT means `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`; CAL means
`docs/research/research-calibration/REPORT.md`. Labels: **measured** (counted from data, this session or by the cited
study), **modeled** (simulation output or arithmetic over a stated model), **asserted** (a document's claim not
re-derived here).

## 0. Bottom line

Both blind designs agree with ours on what cannot be done: literal open-world 100.00/100.00 is impossible, and the
honest claim is 100% of a closed list plus a stated residual. Ours is stronger than both on four points that matter
for the goal: it has actually been backtested (CAL), it terminates under the noise it measured, it handles the re-ask
by state rather than by wording, and it seeds through the same raters. Neither blind design has any of these, or has
measured anything.

The blind designs converge, independently, on one structural point ours does not have, and our own data supports
them on it. **Ours certifies the plan before build. They certify the built artifact before anyone says "done".** Ours
prints a forecast of material changes after signoff, and at measured inputs that forecast is about 10 per program, with
P(at least one) = 1.00 (CAL §5). Those are the "one more thing" moments, now forecast and counted, but they still arrive after
the operator has been told the work is certified. The other convergent mechanisms ours lacks or runs weakly are the
operator's literal question used as a review lens, census saturation, adjudication precision as the main place to
spend, disclosure in the relayed answer, and an honest channel for a late real hole. Each is below with its receipt.

## 1. Convergence table

"Ours" is checked against code where code exists, not only against the REPORT.

| Mechanism | D1 | D2 | Ours (receipt) |
|---|---|---|---|
| Signed frame, closed list, 100% in the closed sense | yes | yes | yes: REPORT:185-191; gate rows 1-12 |
| Materiality fixed before review | per attribute | M0-M3 | yes, clauses (a)-(g): `skills/research-program/RUBRIC.md` |
| Walking skeleton in the real environment | day 1 | 10-20% slice | yes, build wave 0 under launchd `/bin/bash` 3.2.57: REPORT:413-416 |
| Discovery on the **built artifact** before signoff | P4-P5 | Phase 4 at a frozen code sha | **no**: certifies a frozen plan (REPORT:3, 432-444); build follows signoff (REPORT:610-613) |
| Non-LLM instruments (mutation, fuzzing, property tests, model checking) | in every round | Phase 2 + 5 | contact cells name "small exhaustive enumeration" (REPORT:418); no mutation/fuzz stage |
| Operator's literal close question as a lens | canary, ≥10 contexts, ≥3 vendors, gates | self-ask axis, gates | **partial**: rehearsal after the stop, default 3 frames, Anthropic-only, lead-judged (below) |
| Census saturation until dry | ≥3 cross-model runs, stop at 2 dry | new-cell rate as health metric | 2 methods + reviewer **once** (REPORT:322-327, :1050) |
| Repro-gated adjudication | cross-vendor, executes repro | "no repro, no finding" | verifier reproduces from primary source; 3 cross-vendor raters (REPORT:503-512) |
| Precision tracked per reviewer config, spend steered by it | bandit | retire low performers | **no** (pinned composition, REPORT:469-471) |
| Refuted registry | yes | — | **no** cross-round registry in code (`scripts/research-kit/lib/round.py:337-356`) |
| Fix rule tied to measured fix-injection rate | yes | holes-per-fix → rebuild | divergence rebuild at ≥0.5/fix (REPORT:526-529); fixes all MATERIAL |
| Seeded calibration | sealed, separate copy, per-class, historical replays | **none** | sealed vault, omission operators, through raters, shadow + escape cohorts (REPORT:542-569) |
| Capture-recapture estimator | Chao1, jackknife, Good-Turing | Chao1 stop rule | seed Beta-NegBin predictive (`estimate.py:110-126`); Chao1 only in §10 self-cert |
| Surprise inventory / adjacent-value list | 50-150 items | adjacent-value IN/OUT | 12 pre-filled interview questions (REPORT:231-245) |
| Disclosure register in the answer | yes | exclusions mandatory | gate row 11 enforces fields; **not rendered** in the relay (below) |
| Soak / clock injection over days | yes | yes | elapsed time is a residual class (REPORT:588) |
| Hook-computed answer | prompt hook + Stop hook | prompt hook + Stop hook | router + PreToolUse block + relay check (REPORT:731-850; `router.py`) |
| Escape loop feeding the method | yes | yes | escape library + lesson + checklist row (REPORT:910-911) |
| Backtest with held-out split | proposed | proposed | **done**: 16 held-out plans, checklist and library rebuilt (CAL §2) |
| Caps / timebox | none ("not a timebox") | none | every loop capped (REPORT:1042-1075); finite escape cost (REPORT:241-242) |

## 2. (a) What the blind designs have that ours lacks or does weaker

### A1. No as-built certification before "done" (both designs; goal-mismatch)

- Ours certifies research. The REPORT's scope line is "greenfield research and planning" (REPORT:3). Stage 6 freezes a
  plan snapshot (REPORT:442-444), Stage 8 issues the certificate, then build starts (REPORT:610-613). Nothing in §3-§8
  runs discovery on the finished artifact. During and after build, holes arrive as escapes, contact misses or drift
  (REPORT:873-916). `grep -n -i 'after build|post-build|built 0' REPORT.md` => only the interview question (:241), the
  illustrated "Built 0/58 · Live –" line (:816) and 30-day build-escape reporting (:1090, :1143).
- What that costs against the goal, measured or modeled:
  - P(≥1 material change after signoff) is 0.63-1.00 at base inputs (REPORT:656-664, modeled) and **1.00 at measured
    inputs**, with about 6.7 desk + 3.0 invisible holes left under Lite at 20 holes (CAL §5 table, modeled from
    measured inputs).
  - In the replay, excluding TM2, the one round missed 224 known at-freeze holes. 131 of them (58.5%) were later found
    by non-desk detectors: building, probing, production or the operator (measured; `research-calibration.jsonl`
    fields `known_missed_desk` = 93 and `known_missed_nondesk` = 131 summed over 15 plans, computed this session).
  - The taxonomy marks 54 of 200 holes "only by building/probing" (`evidence/taxonomy.md:37`, measured).
  - CAL §4.4: desk review found 27% of the holes history attributes to building.
- Ours already knows building is the next instrument: "no further desk review can lower this; only contact or
  building can … budget is then redirected to build wave 1 as the next research instrument" (REPORT:1036-1040). It
  puts that instrument **after** the signoff. D1 says so directly: "'upfront' should mean *before signoff*, not
  *before build*" (`blind-design-1.md` §0).
- The data argues for the blind designs here. A mitigation in ours: the contact wave and skeleton (REPORT:350-362,
  413-416) take some of the 131 forward, and the calibrated plans had neither. The size of that effect is unmeasured.
- **Recommendation.** Add a Stage 9, as-built certification, after the last build wave and before the operator's
  implementation signoff. It reuses the Stage 7 machinery with code-native instruments:
  - every finding needs an executable repro (a failing test) against the frozen code sha;
  - mutation testing of the acceptance harness, where mutants are seeds;
  - an as-built contact re-run from a clean HOME under `PATH=/usr/bin:/bin` and the scheduler's interpreter;
  - a soak across the time boundaries the frame names;
  - the literal-question lens (A3);
  - D1's intent diff: asked → built → decided for you → deliberately out.

  It keeps the same caps, raters and seed vault. The research certificate's forecast then splits into "found before
  implementation signoff" and "after it". This is the change most likely to move the operator's metric.

### A2. Adjudication precision is the binding constraint, and ours has not changed it (both designs; defect)

- Measured: 1.13 false material calls per reviewer-read after full triage (0.22 counting only false claims); rater
  downgrades 0.22 (seeds 0.17); stop rule never fires; every profile hits its cap in 93-100% of programs (CAL §1,
  §4.1, §4.6). CAL §6: "the lever is the materiality triage … not width, depth or seeds", with three candidate fixes
  listed. "Not changed, because it is outside this wave's edit scope."
- Still unchanged: `git log -1 -- skills/research-program/RUBRIC.md` => `0fb32f503 2026-10-01 07:34`; calibration
  landed `21a585908 2026-10-01 08:11`. The rubric was last edited before the calibration landed.
- Both blind designs make adjudication the core spend: "Adjudication: never wasted" (D2 §11); precision tracked per
  model × lens (D1 §4). **But repro-gating alone would not fix our measured failure.** Our verifier already reproduces
  from the primary source and confirmed 295 of 332 items. Of the 89 false material calls, 72 were "real but not
  material" and only 17 were false (CAL §4.1). The blind-design mechanism that reaches the 72 is D1's
  decision-theoretic fix rule: "fix only if expected harm of the hole > p(injection) × expected harm of a new hole"
  (D1 §5), plus its per-attribute materiality bar. Our measured fix-born rate of 0.21 per fix (CAL §4.2) is exactly
  the p(injection) that rule needs. It agrees with Yin et al.'s 15-24% (asserted by D1; well known).
- Repro-gating does help at the artifact stage (A1). There a repro is a failing test, a much sharper filter than a
  rater reading a plan. Rater 1 "refuted" 43% of history-proven holes (CAL §4.1), which shows reading-based
  refutation is noisy. That precision gain is asserted, not measured.
- **Recommendation.**
  - Apply CAL §6's three changes at the verifier, before any rater: (1) reject a finding that names no signed frame
    row; (2) rate against the frame row's acceptance criterion; (3) classify real-but-not-material as a refinement.
  - Add D1's harm-weighted fix rule with p(injection) = the program's measured fix-born rate, so a low-harm item goes
    to disclosure, not to a fix.
  - Keep a precision table per (vendor × strategy), across programs only (within a program the composition stays
    pinned, see §3).
  - Before adopting any of these, test them on CAL's 160 ground-truth items (`evidence/adjudicate/`). The goal is a
    false-material rate near 0.02 and a downgrade rate near 0.05, the values at which the stop rule fires (CAL §5).

### A3. The operator's literal close question is not a lens (both designs; gap)

- D1's canary ("are we 100% complete? what did we forget?", ≥10 fresh contexts, ≥3 vendors) and D2's self-ask axis
  both run the historical loop on purpose, many times, before the claim.
- Ours, as built:
  - The 6 slot strategies contain no such lens (`scripts/research-kit/lib/kit.py:93-100`), and the 11 brief lenses
    have none either (`skills/research-program/briefs/reviewer.md`).
  - The rehearsal runs after the stop, never edits the plan, and turns finds into known rows (REPORT:531-533). Its
    default frames are 3, not the 12 REPORT:532 states: `HISTORICAL_FRAMES = ["deployed and live", "nothing can beat
    it", "no loose ends"]` (`scripts/research-kit/intake.py:86`).
  - Rehearsal frame sessions are Workflow `agent()` calls, so they run on Anthropic only, and their materiality is
    self-assessed. Promoting a find to a known row "is the lead's" (`workflows/rehearsal.workflow.js:13-14, 45-50`),
    with no verifier and no raters.
  - The relay test's phrasings omit the operator's most frequent form ("100.00/100.00 complete"): `PHRASES = ['Are
    you sure?', 'Is this all before we close?', 'no take-backs?', 'if more research moves your conviction, do it now']`
    (`rehearsal.workflow.js:26-27`). REPORT:83 says the superlative appears in 80 of 88 asks.
- Data for the lens:
  - 120 of 200 holes were misses inside the frame research already had, and the ask was usually the first adversarial
    audit (REPORT:75-77).
  - C1 (claim frame narrower than the question) is 23 holes, 13 of them decision-changing (`evidence/taxonomy.md:26`).
- Data against **gating** on it, as D1 rule 5 and D2's stop rule do: at the measured false-material rate, P(10 canary
  contexts all dry) = e^(−10×0.22) = 0.11, or 1.2×10⁻⁵ at 1.13 (modeled, Poisson, computed this session). A canary
  gate would never pass today.
- **Recommendation.**
  - Add `literal-close-question` as a slot strategy in certification rounds. Its finds go through the same verifier
    and raters and count toward the quiet streak, with no separate gate.
  - Add "are we 100.00/100.00 complete? what did we forget?" to `HISTORICAL_FRAMES` and to the relay `PHRASES`.
  - Run rehearsal frame sessions through `courier.sh` across vendors, and send their finds through the raters before
    they become known rows.

### A4. Censuses stop at one reviewer, though they can saturate (D1; gap)

- Ours: each population is built by 2 independent methods, then one blind cross-vendor reviewer checks it once
  (REPORT:322-327). The loop table caps the census reviewer at "Once per population" (REPORT:1050).
- D1: at least 3 cross-model runs per census, stopping when two consecutive runs add zero material members (a
  species-accumulation curve).
- Why this one can work when the review stop rule cannot: a census addition must "prove any member it adds exists"
  (REPORT:324-325). Existence is cheap to verify and rarely false, so the false-material noise that keeps review
  rounds from going quiet is largely absent. An until-dry rule here can actually fire.
- Data for it:
  - Omissions are 58% of holes at freeze, and one round catches 28% of them against 37% of commission holes (CAL §4.5).
  - C4 "population never enumerated" is the most decision-changing class: 32 holes, 22 of them DC (REPORT:56).
  - §3.12 reading 1: the front end is the only lever that shrinks both residuals (REPORT:668-670; modeled).
- **Recommendation.** Replace "census reviewer once" with "runs from different vendors until 2 consecutive runs add
  zero verified members", bounded by the escape-cost number rather than a count. Record the accumulation curve on the
  certificate.

### A5. The relayed answer discloses no residuals or exclusions (D2 explicitly; defect, as built)

- D2: "A certificate without an exclusions section is invalid by rule, because unstated exclusions are exactly where
  'one more thing' lives." D1: disclosures with monitor, owner and first check.
- Ours designs a "Scheduled checks: 3 production or elapsed-time checks with owners and dates" line and a "Built 0/58
  · Live –" line (REPORT:815-816). The renderer emits neither. `scripts/research-kit/lib/gate_cert.py:191-235`
  (`lines_for`) renders head, signed frame, forecast, decisions, next version, known rows, calibration and
  fingerprint. Residual rows (`residual.jsonl`, enforced by gate row 11, `lib/gate_rows_b.py:166-204`) are not
  rendered.
- Worse, the relay check blocks any token the certificate lines do not carry (file:line, ids, paths, code spans:
  `router.py:608-635`). A model asked "are we complete?" therefore **cannot** name a declared residual such as "the
  production check due Oct 20", so the operator does not hear it.
- **Recommendation.** Render one line per residual row (id, reason, owner, due, verify command) and the Built/Live
  line in `lines_for`, so that disclosing the declared residual is part of the relay instead of a violation of it.

### A6. No honest channel for a late real hole in a completeness turn (D1; defect)

- D1: "Honesty is never suppressed … it files it as an escape (a command, not a passing remark in prose)".
- Ours: in a completeness or pushback turn, every tool except the certificate read is denied
  (`router.py:537-549`). The relay check blocks a reply that names anything not on the certificate, with no safety
  exception (`router.py:608-658`; `grep -n -i 'safety|hazard|security' router.py` => no hit). Concerns are admissible
  only from executed detectors or an operator prompt with a location (REPORT:837-840).
- That conflicts with the method's own rubric clause (f): "safety, security, data-integrity or irreversibility hazard.
  Always material: stop and surface" (`RUBRIC.md`). It also conflicts with the global rule "Security or data-integrity
  issues: stop and surface now".
- The relay arm abstains after `COMPLETION_RELAY_MAX` = 2 blocks (`hooks/completion-assert.sh:274-300`). A persistent
  reply therefore gets through on the third try with no record, which is the opposite of D1's recorded escape.
- Our data supports suppressing *ordinary* agent concerns: without these rules, 10-30 asks produce 1.6-8.1 notices and
  up to a 48% chance of a false take-back (REPORT:841-842, modeled). It does not support suppressing the
  always-material class.
- **Recommendation.** In completeness turns, allow one more tool: `cc-research concern --class safety --location …`.
  Render it in the operator-readout block only, never in the reply, and send it to the daily triage. That keeps the
  relay invariant without silencing a real hazard.

### A7. Seeds in separate calibration copies, stratified by class (D1; improvement)

- Ours plants seeds in the plan the reviewers read, at most 1 per 25 lines (REPORT:556-562). The median plan
  therefore carries 16 seeds and the 95% bound widens (CAL §4.11). Per-plan `forecast_95` in the replay ran from 18.1
  to 697.4 against realized misses of 6 to 151 (measured, `research-calibration.jsonl`).
- D1 seeds a separate calibration copy, so the number of seeds is no longer tied to plan length. With an unlimited
  budget, that buys a sharper bound, which our own priority list places last only because seeds "tighten only the
  statement" (REPORT:1034).
- Separately, the estimator pools all seeds (`estimate.py:110-126`). The seed author mixes classes "in the proportions
  the frame states" (`briefs/seed-author.md:11`), and the calibration used 1 omission seed in 4 (CAL §2). With measured
  per-round recall of 0.28 for omissions and 0.37 for commissions, and 58% real omissions, a 25-30% omission seed mix
  overstates pooled recall. The residual comes out about 11-13% too low (modeled, computed this session: residual
  factor 1.88-1.92 against 2.15).
- **Recommendation.**
  - Use a stratified estimator: one recall per class, summed.
  - Set the omission share of the original cohort to the measured 0.58.
  - Allow extra sealed calibration copies, bought from the operator's escape-cost budget.

### A8. Refuted registry, scoped to verifier refutations (D1; improvement, minor)

- `round.py:337-356` counts a round's new material holes from the `round` field. Nothing in code dedupes against
  findings already refuted or rated below material in earlier rounds. That work is the lead's, by hand.
- A re-raised item gets re-rated blind, and raters disagree often (82 disagreements went to rater 3, CAL §2). Some of
  the non-quiet rounds are plausibly re-litigation (unmeasured: the replay ran one round).
- The data cuts both ways. Rater 1 "refuted" 43% of history-proven holes (CAL §4.1), so a registry over **rater**
  downgrades would entrench the 0.2 downgrade rate, the main driver of the desk residual (CAL §5 attribution table).
- **Recommendation.** Keep a registry over **verifier** REFUTED verdicts only, the ones with a quoted contradicting
  span (`briefs/verifier.md:9`). A re-raised refuted item is not new unless it cites new evidence.

### A9. Recognition-based intent elicitation (both designs; gap, minor)

- D1's surprise inventory (50-150 "would you be annoyed if…" items) and D2's adjacent-value IN/OUT list arrived
  independently. Ours has 12 pre-filled interview questions (REPORT:231-245) and parks later ideas.
- The adjacent-value list is a direct home for the operator's "nothing left on the table" value, which ours handles by
  suppressing it inside programs (REPORT:199-203).
- Data: C2u (intent existed but was never asked for) is 6 of 200; C1 is 23 of 200 (REPORT:56-61). The upside is
  bounded at roughly 3-14% of holes.
- **Recommendation.** Add an adjacent-value recognition list to intake step 2, generated from the mining, the 33
  checklist rows and the held-out escape library. Each item is ruled IN (it becomes a frame row) or OUT (it becomes a
  non-goal quoted on the contract page).

### A10. Time made reachable, and watchers with a time-to-detect bound (both designs; gap, minor)

- Both blind designs turn time-only holes into findable ones with clock injection and multi-day soak. D2 gives every
  unreachable row a detector, an alert path, a rollback and a time-to-detect bound.
- Our residual rows carry verify_cmd, owner, due, backlog_id and falsifier (`gate_rows_b.py:186-192`), but no alert
  path and no detection bound.
- Data: only 6 of 200 holes needed production, a tenant or elapsed time (`evidence/taxonomy.md:15`).
- **Recommendation.** Add `detector` and `ttd_bound` fields to residual rows, and make clock-injected day-30/day-365
  runs a contact-cell instrument.

## 3. (b) What ours has that the blind designs miss

- **B1. A real backtest with held-out data.** Both blind designs say the arbiter is a backtest (D1 §11, D2 §14); neither
  has run one.
  - Ours replayed 16 plans with the checklist and escape library rebuilt without each plan's holes (CAL §2), and
    measured every input it had assumed.
  - It then reversed its own widest-tier recommendation on the evidence: Standard 6.45 and Full 7.58 desk holes
    against Lite 6.66 (CAL §1, modeled from measured inputs).
  - This is the only measured evidence in any of the three designs.
- **B2. Seeds that pass through the same raters, with omission operators and shadow cohorts.**
  - D2 has no seeding at all. Its stop rule is Chao1 over material findings. Our own self-certification shows that
    estimator is unstable at this noise level: about 10, then about 42, between two passes (REPORT:1282-1285,
    measured). CAL's fitted detection model has hole-difficulty spread `sd_d` 2.5 and 60% of holes unreached per
    round (CAL §4.7), the heterogeneity that sends Chao1 low, while false singletons push it high.
  - D1 seeds, but does not route seeds through the adjudicator, so its recall is detection only. Ours measures
    detection times triage (REPORT:509-511): 35 of 64 seeds caught and rated material (CAL §3).
- **B3. Termination under measured noise.**
  - Neither blind design has a timebox. Both stop only when valid yield reaches zero.
  - At the measured 0.22 false material calls per read, P(two consecutive quiet 6-reviewer rounds) = e^(−12×0.22) =
    0.07. At 1.13 it is about 0 (modeled, Poisson, computed this session). The blind designs would never certify and
    so never deploy, which REPORT:241-242 names as the meaning of an infinite escape cost.
  - Ours terminates with a bound that held: 95% bound exceeded in ≤2.2% of simulated programs, and on 1 of 16 replayed
    plans (CAL §1, §4.9).
- **B4. Re-ask handling by state, with tools blocked.**
  - D2 answers "Really? 100%?" with a priced option inside the reply. Ours keeps the menu out of the model's sight
    (REPORT:801-803), because "Are you sure?" flips answers 46% of the time (REPORT:150-152) and 20 of 73 "yes" replies
    named a new item (REPORT:91-92; a regex upper bound per REPORT §10 item 15).
  - Ours also blocks tools in the turn, which a Stop hook cannot do (REPORT:789-795). 95.7% of asks called tools and
    15.7% spawned research (measured).
  - Neither blind design blocks tools or polices the "yes, plus one more thing" reply.
- **B5. Computed conviction.** Both blind designs log self-reported convictions. Ours derives conviction from an
  evidence tally by a fixed rule (REPORT:376-386), because 193 of 217 self-reported convictions sat on multiples of 5
  (measured).
- **B6. Operator-only signing and caps in code** (`cc-signoff` refuses under an agent; `round.sh` refuses past R_max:
  SKILL.md:22-29, :121). Plus detector pinning, a fingerprint and a new-detector ledger (REPORT:469-471, :1109).
  Neither blind design guards against an agent buying more research for itself, or against a model upgrade changing
  what is findable.
- **B7. Operator dormancy bounded.** Class-C packets convert to class-B defaults at their due date (REPORT:951-958;
  sevenrooms was idle 33 of 35 days). The blind designs batch asks but give them no deadline or default.

## 4. (c) Where claims about what is attainable differ

| Claim | Blind design | Ours | Who is right, on what evidence |
|---|---|---|---|
| Literal open-world 100.00/100.00 | impossible (D1 IMPOSSIBLE; D2 §13) | impossible (REPORT:18-20, :1103) | **Agree.** Certifying zero needs ≥95% coverage of every possible locus; at 60 holes, a 5% statement needs 3,654 seeds, all caught (REPORT:146-148, modeled). Holes every reviewer family misses cannot be estimated from overlap (Link 2003, asserted via REPORT:148) |
| A stop rule that fires with residual < 0.5 and no timebox | attainable (D1 §6 rules 2-3; D2 stop rule) | not at measured triage; caps needed | **Ours, on present evidence** (B3). The blind designs are right about the lever, though: restoring false material to 0.01 and downgrades to 0.05 cuts Standard's desk residual from 6.45 to 1.82 holes (CAL §5 attribution, modeled) |
| Where signoff should sit | after build and as-built verification (D1 §0) | before build (REPORT:610-613) | **D1, for the operator's stated goal.** 131 of 224 missed known holes (ex-TM2) were found later by non-desk detectors (measured); P(≥1 post-signoff material change) = 1.00 at measured inputs (CAL §5, modeled). Ours' contact wave shrinks this by an unmeasured amount |
| "Disclosure is about half of the achievable reduction" | D1 thesis 3 | no such claim | **D1 overclaims.** In our taxonomy the disclosure-addressable classes are C1 (23), production, tenant or time (6) and new intent (6): about 17.5% of 200 (REPORT:56-66, measured). A disclosed count of about 10 forecast changes does not make any one of them known |
| "Desk recall below ~90% means the axes are wrong, not the budget" | D2 §14 | the lever is triage | **Ours (modeled).** CAL §5: false material and downgrades explain most of the residual, and width buys nothing. Axes were not separately measured |
| Same-model ensembles realize under 0.3 of the independence gain; heterogeneous ones about 0.44 | D2 §7, cited to arXiv 2606.20158 | phi 0.62 frontier-on-Opus, 0.51 Opus-vs-OpenAI (CAL §4.7, measured) | **The number is real but cited to the wrong paper.** Fetched: arXiv 2607.02808 (Nogueira et al., 2 Jul 2026) reports "0.43 and 0.44 … dropping below 0.3 when ensembles are built from the same model". 2606.20158 (Ron, Baudry, Monperrus) reports failure counts, not this figure. Both measure N-version code, not reviewers, so applying them to review is an analogy. Our measured phi points the same way |
| LLMs agree on about 60% of cases where both err | D1 §4, Kim et al. ICML 2025 | consistent | **Confirmed** by web search (secondary): PMLR v267 kim25e, "models agree 60% of the time when both models err" on one leaderboard dataset |

**Strongest attainable version of the goal.** The parts that are physically out of reach:
- zero unknowns in an open world (REPORT §7);
- holes every instrument is blind to;
- production, tenant or time properties (6 of 200);
- intent the operator has not formed yet (6 of 200);
- a world that moves (4 of 200 unforeseeable).

What is attainable: 100% of a signed, saturated closed list; certification of the **built artifact** before the
operator is told "done"; a residual that is calibrated and sharp; every residual disclosed in the answer itself; and a
re-ask that relays that state without searching again. Ours has the closed list, the relay and calibration machinery
the blind designs lack. It lacks the as-built stage, disclosure in the relay, and the triage precision that would let
any stop rule fire.

## 5. Commands run this session

- `python3` over `docs/research/research-calibration.jsonl` => all 16 plans: known 520, detected 120, missed_desk 126,
  missed_nondesk 131. Excluding TM2: known 337, detected 113, missed_desk 93, missed_nondesk 131, so 131/224 = 0.585.
- `python3` arithmetic => P(quiet 6-read round) 0.267 at fpp 0.22 and 0.0011 at 1.13; P(2 quiet) 0.071; P(10 canary
  contexts dry) 0.11 and 1.2e-05. Seed-mix residual underestimate 0.125 at a 25% omission mix and 0.108 at 30%.
- `git log -1 --format='%h %ci' -- skills/research-program/RUBRIC.md` => `0fb32f503 2026-10-01 07:34:52 -0500`;
  `... -- docs/research/research-calibration/REPORT.md` => `21a585908 2026-10-01 08:11:22 -0500`.
- `cat ~/.claude/autonomy/research/programs.json` => one program, `truememory-2-0`, state `registered`.
- WebFetch https://arxiv.org/abs/2606.20158 and https://arxiv.org/abs/2607.02808, quoted above. WebSearch for Kim et
  al. 2025 => https://proceedings.mlr.press/v267/kim25e.html.
