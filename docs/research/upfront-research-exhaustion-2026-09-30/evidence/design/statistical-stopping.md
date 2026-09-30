# Certified research: a statistical-stopping methodology for upfront greenfield research

Design unit `statistical-stopping`, 2026-09-30, **revision 2** (rerun after the 15:26 CDT reboot; the revision log is
§14). Read-only on every repo. Evidence read: `/tmp/rescomp/taxonomy.md` (+ `taxonomy_holes.py`, `taxonomy_stats.py`),
`/tmp/rescomp/forensics/shard-0..7.md`, `/tmp/rescomp/internal/*.md`, `/tmp/rescomp/external/*.md`, and the prior
run's judge verdicts as recorded in `/tmp/rescomp/design/SYNTHESIS.md` §12.

New evidence produced by this unit. The reboot deleted revision 1's simulation scripts, so all of it was rebuilt and
re-run; all of it is stdlib Python and rerunnable, under `/tmp/rescomp/design/`:
- `cert_sim.py`: the shared model;
- `stopping_model.py`/`.out`, `cert_calibration.py`/`.out`, `carried_seeds.py`/`.out`, `seed_realism.py`/`.out`
  (new), `tier_curve.py`/`.out`, `forecast_check.py`/`.out` (new).

Contact probes run this session:
- **Cross-vendor CLIs.** `codex --version` => `codex-cli 0.147.0`, and `codex login status` => `Logged in using
  ChatGPT`. `gemini --version` => `0.29.5`. Both resolve only by absolute path, because this shell's post-reboot
  PATH is `/Applications/kitty.app/Contents/MacOS:/usr/bin:/bin:/usr/sbin:/sbin`. `grok-wiki` was not found.
  `~/Library/Application Support/fnm/node-versions/v22.21.1/installation/bin/claude` => `permission denied`, the
  broken-stub trap of `skills/grok-wiki-audit/SKILL.md:16`.
- **Isolation of Anthropic panels**, with a positive control, run from `cd /tmp`. The prompt asked for the first
  sentence of the "Mission board" section, or NONE.
  - `/opt/homebrew/bin/claude` (2.1.278) `-p --model opus` => `7 customer deliverable(s) are stale.`, and the
    operator's SessionEnd hook also ran (it failed: `database is locked`).
  - The same call with `--setting-sources local` => `NONE`.
- **Ratification channel.** `bin/cc-signoff` refuses any process with a claude ancestor, pins the bytes it signs,
  and renders a forgery as VOID (`bin/cc-signoff:1-30, 101-110`). Today it accepts only cc-mission row ids
  (`:94-97`). `bin/cc-decide` has no ancestry or operator check: a grep for `ancestry|operator-only|ppid` returns
  nothing.

Paths without a root are relative to `/Users/chrisren/Development/claude-infrastructure`.

---

## 0. Answer first

1. **"Done" becomes a measured quantity, issued once, as a certificate.**
   - **When research ends.** T blind panels from at least 3 model families review a frozen snapshot that carries
     hidden planted defects ("seeds"). Research ends when K consecutive rounds of those panels find no new
     material hole, or at a cap R_max fixed after round 1 from a forecast.
   - **What the certificate states.** The seed-calibrated estimate of material holes still present, with its 95%
     predictive bound.
   - **Where the operator's residual threshold goes.** It is applied at **entry**: at intake the operator buys a
     tier (K, T, seeds) from a calibrated price curve whose expected residual meets their threshold. It is not an
     exit gate, because used as a gate it is often unreachable. With the build-tier stop and a 0.5-hole target,
     53% of simulated programs ended in an operator decision instead of a certificate (`tier_curve.out` §C).
   - **How it is answered.** From disk, every time it is asked. It is never regenerated.
2. **Statistics certify completeness. Structure is what produces it.** Of the 200 holes that surfaced after a
   "complete" claim, 60% were in-frame process misses (C3 to C8), 11.5% were known items that the close left out
   (C1), and 15% were contact-only (C9), 24 of those 30 probe-able on this machine (`taxonomy.md` §2). So the loop
   runs structural passes first: an intake frame, census registers, a premise register, a contact wave, and
   discriminating controls. Certification rounds then measure how much those passes missed. An estimator only sees
   holes inside the frame it is given. The frame is closed by construction, and the estimator measures what is
   left inside it.
3. **100.00/100.00 is replaced, not lowered.** No valid rule certifies zero residual short of examining nearly
   every place a hole could be (n ≥ 0.95N; `stopping-rules.md` §2). A certificate buys a bound, and how tight the
   bound is depends on what you spend. This design turns "as long as it takes" into a price curve the operator
   picks from (§9.3). The process terminates because the target is a number.
4. **Two simulation results set design rules** (rebuilt after the reboot; `cert_calibration.out`,
   `carried_seeds.out`, `seed_realism.out`).
   - **Seeds must be carried.** Seeds planted only at the end overstate recall on the holes that remain, because
     the survivors of several rounds are the hard ones. The naive "no real hole found, seed recall 0.95, so at most
     1 left" bound held in only 71–87% of simulated programs, and 88–96% even with a Clopper-Pearson lower recall;
     it claimed 95% (`cert_calibration.out`). **Carried seeds** fix this. They are planted at the first freeze, plus
     one shadow seed per fix, and removed only when a panel catches them, so they pass through the same filter as
     real holes. The stated bound (a 95% posterior-predictive quantile) held in 97.8–100% of runs, at every seed
     count from 20 to 300 and at N₀ = 20 and 60. At s ≥ 40 its median is 2–4 holes (`carried_seeds.out`).
   - **Seeds must also survive what the real holes survived.** At the first freeze, real holes are the ones
     discovery missed. Against fresh seeds, the point estimate ran 15% low and the bound's hold rate fell to 95.5%.
     A one-pass pre-screen that discards seeds a discovery-style reader catches restores 98.2%. A capture-count
     test on round-1 data flags mismatched seeds in 20–90% of runs, depending on how large the mismatch is: 52% for
     discovery survivors and 90% for seeds one logit easier. Its false-alarm rate is 4–6% (`seed_realism.out`).
5. **The re-ask stops generating holes because it no longer triggers an audit.** A UserPromptSubmit hook injects
   the rendered certificate, resolved by program name from any pane. A Stop arm flags a "no, one more thing" reply
   unless it cites a typed challenge that triage accepted as an in-frame material miss. It is warn-only until the
   operator rules on the D4/F1 change it implies (§10.2). Such an escape is shown and counted against the bound
   printed at signoff. It triggers a local fix plus at most 2 delta rounds on one stratum, never a program reopen.
   Because each ask reads a monotone counter against a fixed threshold instead of drawing a fresh sample, asking
   1,000 times has the same error rate as asking once (§7.5).
6. **The timeline becomes a forecast after round 1.**
   - **Inputs from round 1:** the starting hole count (jackknife-2, median 1.03× the truth in simulation), carried-seed
     recall, and a prior on the fix-born rate b.
   - **What `cc-research forecast` does.** It simulates the program forward.
     - With the model right, the actual round count fell at or under the forecast p90 in 91% of programs.
     - With heavier heterogeneity and a b 2.5× the prior, it did so in 66%.
     - Adding 4 rounds covers 99% and 93% respectively (`forecast_check.out`). The cap is therefore
       **R_max = min(forecast p90 + 4, R_abs)**, where R_abs is ratified at intake.
   - **The closed form is rejected.** Revision 1's closed form, ⌈ln(N̂₀/μ)/ln(1/q)⌉ + K, ignores heterogeneity; its
     forecast held in only 5–17% of programs, so it is dropped.
   - **The cap costs no measurable residual.** At 0.25 false positives per round, programs stopped by a 12-round
     cap left 0.41 desk-detectable holes on average, against 0.67 for programs stopped dry (`tier_curve.out` §D).
7. **False positives are the schedule risk; fix-born holes are the divergence risk.**
   - **False positives.** Each false MATERIAL finding that survives verification breaks a dry run. At 0.25 per round,
     the build tier's rounds go from 9/12 to 10/17 (p50/p90); at 0.5, to 14/27 (§D). So a dispute never counts as
     MATERIAL (§3.3).
   - **Fix-born holes.** Convergence needs a fix-born rate b < 1, not revision 1's "b < 0.5·R". In practice b = 0.6
     already takes the round count from 9/12 to 15/21. Within 40 rounds, b = 0.9 fails to stop 29% of the time and
     b = 1.0 fails 89% of the time. At b = 1.2 the found count per round runs 47, 49, 53, 59, the observed
     23/21/24/28 critic-loop signature (`stopping_model.out` §4–5). b̂ is measured from round 2. At
     b̂ ≥ 0.5 the prescribed step is to delete machinery, not to run another round.

Conviction that this design **terminates**: **97%**. Termination holds by construction, because every loop is
capped and every gate row is finite (§6). The 3% is implementation risk, such as a cap that is not enforced in code.

Conviction that it terminates **within the forecast** (R_max, never R_abs): **85%**. This rests on the simulation
above, the in-corpus convergence under bounded passes (10→7→2 in `ba08cab8`; 7→1→0 in `04235d35`), and two plans
that verified before building and never reopened (`plan-lifecycle.md` §0.5).

Conviction that the certificate's stated bound is **calibrated for real LLM panels**: **60%**. Two things set the
true figure and neither is measured: the correlation between model families on design-hole finding, and how
realistic the seeds are. Wave W0 (§10.4) measures both on historical snapshots whose later holes are known. **Until
W0 reports, every certificate prints "uncalibrated"**, and nothing in §§6–8 should be relied on as a calibrated
number.

---

## 1. What "complete" means under this method

### 1.1 The certificate is the only completeness claim

A research program may say "complete" in exactly one form: a certificate `CERT-v<n>` produced by
`cc-research cert` (§10) after `cc-research gate` has printed CERTIFIED. The claim covers one frozen snapshot of the
**certified object**: the plan, its registers and its acceptance matrix, at a git sha. It carries five parts, and
every one of them is computed:

| Part | What it says | Computed from |
|---|---|---|
| Structural closure | Every register passed its gate (S1–S10, §6.1) | register files + their check commands |
| Stop | `stop=dry`: K consecutive rounds of T blind panels found 0 new verified material holes on this snapshot. Or `stop=cap`: R_max was reached; the last round's finds are fixed and listed | round matrices |
| Residual estimate | "Estimated desk-detectable material holes still present: μ̂; 95% bound n_pred95; P(at least one) = p". This is stated per stratum and carries the tier forecast it was bought against. It prints "uncalibrated" until W0 reports | carried + shadow seeds and real finds (§5.4) |
| Named open items | MATERIAL-DISPUTED findings, weak lenses (Q4), and the realism flag (Q6), each by name | `holes.jsonl`, round manifests |
| Declared residual | The classes this certificate cannot see, with owners and dates: contact-only in production, a tenant or time; unforeseeable drift; operator-new scope; and holes no desk panel family can see (the mass Link 2003 proves unidentifiable) | `contact.jsonl`, `facts.jsonl`, `frame.json` |

### 1.2 Why a bound and not 100.00 (the arithmetic the operator ratifies at intake)

- **Zero residual cannot be certified without exhaustive review.** With a 100% recall target, H₀ is "at least one
  hole remains". A random sample of n from N unexamined places misses a single remaining hole with probability
  1 − n/N, so 95% confidence needs n ≥ 0.95N (`stopping-rules.md` §2).
- **Null runs certify a rate, not absence.** With zero misses among s seeds, the 95% upper bound on the miss rate
  is 1 − 0.05^(1/s): 0.095 for s = 30, 0.049 for 60, 0.030 for 100, 0.010 for 300 (`stopping_model.out` §1).
  Certifying "fewer than 5% chance that even one desk-detectable material hole remains", when certification found
  F = 20–60 real holes, needs every one of 209–609 seeds caught for a posterior mean, or 1,257–3,654 for 95%
  confidence (`stopping_model.out` §1). That is the exact cost of the operator's last percent, stated in advance.
- **More seeds do not remove holes; more panels do.** At the build tier, the true residual is about 0.55 whether
  s = 60 or 300. Only the statement's width moves: the original cohort's median bound goes from 3 to 2, and the
  total stays at 3 (`carried_seeds.out`, `tier_curve.out` §B). What the stop rule leaves is bought with T and K (§9.3).
- **Perfection has no loss function.** Dalal & Mallows's optimal residual is f/(cμ). It reaches zero only as the
  cost of a post-release fix goes to infinity, and at that limit the rule says never stop (`stopping-rules.md`
  C5). The operator keeps the choice. This method makes the choice explicit and priced, and makes it once.

### 1.3 "No take-backs", defined so it can be kept

Revision 1 defined a take-back so that escapes inside the stated bound did not count. A judge called this out: it
made real escapes invisible (`SYNTHESIS.md` §12, row "SS redefines take-back"). Revision 2 separates three things,
and hides none of them:

- **Every post-gate hole is visible and counted.** The certificate carries a live escape counter per stratum, printed
  beside the number the certificate forecast at signoff ("expected desk-detectable material holes still present:
  μ̂; 95% bound n_pred95"). An escape is never relabeled as not-an-escape. Only a hole that triage (§8.1) shows is
  *not* an in-frame miss is recorded under its own class: a new operator requirement, a declared contact residual,
  dated drift, a relabel of a known item, or refuted.
- **"No redo" is a structural promise.** An escape triggers a local fix and a stratum-local delta round (§8.2). It
  never reopens the program. This holds by construction, whatever the count.
- **A take-back is the certificate's calibration failing.** It happens when a stratum's escape count exceeds its
  n_pred95, or when a structural gate row (S1–S10) is shown to have been false when it was certified. It is
  reported as a take-back, and only that stratum is re-certified (§8.3).

The escape count divided by the stated bound, across programs, is the method's own error metric
(`docs/research/research-calibration.jsonl`, §5.1). Before W0 reports (§10.4), every certificate prints
**"uncalibrated"** next to its bound.

---

## 2. Phase map

| Phase | Name | Output | Ends when | Classes it removes |
|---|---|---|---|---|
| P0 | Intake and ratification | `frame.json` (acceptance matrix AM, decision register DR, materiality rubric, strata, stop parameters, tier, deadline, exclusions) | the operator signs the frame in their own terminal (`cc-signoff research:<P>/frame`, B7; §3.6) | C2u, C11, C1's frame |
| P1 | Prior art and census | research-index hits; `census/*.jsonl`; topic ownership lock | S2 and S6(index) pass | C4, C6 |
| P2 | Discovery (directed, adaptive) | research docs; DR rows decided at ≥90% conviction or ruled by the operator; `premises.jsonl` at primary tier; `trace.jsonl` | every DR row is closed or filed; S3 and S6 pass | C3, C6, C4 depth |
| P3 | Contact wave | `contact.jsonl` with executed probes; every AM check run against current state and shown red on a planted defect | S4 and S5 pass | C9 (24/30), C5 |
| P4 | First freeze and calibration round (round 1) | snapshot S₁; survivor-matched seeds planted (§5.3); round-1 matrix; realism check; **forecast and R_max** | round 1 has been adjudicated | C8 timing |
| P5 | Certification loop | rounds 2..k: fix MATERIAL findings only (REFINEMENT, COSMETIC and DISPUTED go to `apply-at-build`, so they cannot spawn fix-born holes) → integrate → consistency read → refreeze (shadow seeds planted in edited spans) → round | the stop rule fires: K dry rounds, or r = R_max (§6.2 Q1) | C3–C8 residue, C7 |
| P6 | Certificate and Fable blind-spot sweep | `CERT-vN`; the Fable sweep reconciled | the sweep is reconciled through the challenge protocol | cross-check on universal blind spots |
| P7 | Implementation gate | trunk and facts re-validated; contact residuals scheduled | build fires | C10 |

**P2 ends by decision, not by saturation.** Design choices are constructed rather than discovered, so saturation
cannot close them (Braun & Clarke; `stopping-rules.md` A8). A DR row closes at ≥90% conviction with a receipt
(the existing F2 rule, `CLAUDE.global.md:619`) or by an operator ruling. Rows are researched in order of expected
decision value, using Weitzman's reservation value: the plausible change to the choice, net of cost. Each row
gets a timebox at intake. A row that exhausts its timebox below 90% becomes a `cc-decide` class-C packet carrying
its number and receipt. It does not get an open-ended extension.

---

## 3. Intake: fixing scope, frame, materiality and "complete" (P0)

### 3.1 Intake interview (the lead asks; one sitting, about 30–60 minutes of operator time)

Mined before the interview, so no question the record already answers gets asked (outbound-drafting discipline):
- prior operator decisions on the topic: `msg search "<topic terms>"`, a transcript grep across
  `~/.claude*/projects/*/*.jsonl`, `cc-decide list --all --json | jq` on the project, and `cc-backlog list --all
  --project P`;
- sibling or adjacent plans and research (P1's index);
- house rules in CLAUDE.md that act as acceptance criteria. Hole 198, the one-command preference, was a C2u miss
  of this kind.

Then five questions. Each exists because a C2u or C11 hole in the ledger needed it:

| # | Question | Hole it would have prevented |
|---|---|---|
| 1 | Who consumes the deliverable, and what do they do with it on day one? | 36, 194 (consumer never established) |
| 2 | Which private facts, relationships or agreements bind this? (The agent lists what it mined and asks what is missing.) | 185 (an in-person agreement with an author), 107 |
| 3 | Which earlier decisions of yours bind this? (The agent lists the ones it found.) | 186 (the apex-domain decision) |
| 4 | What does "not lacking" mean? Show one or more positive references for any taste axis. | C11 holes 56, 62, 65, 66 |
| 5 | What must be true by which date, and what happens if it is not? (The deadline and the negative branch.) | 179 (a perfection hold with no expiry) |

### 3.2 Superlative translation (port of `skills/ground-up/SKILL.md:14-18`)

Every superlative in the ask ("100th percentile", "maximally", "absolute perfection") becomes one or more AM rows,
each with:
- a **measured ceiling first**, for example "maximally fast" against the engine's 0.14 s floor (hole 11);
- a threshold;
- a check command;
- the branch taken on a negative result.

For taste axes, the AM row names a positive reference set and makes the operator's eye a gate with a date. A
ban-list is not acceptance (hole 62). The operator's superlative is preserved in `frame.json.intent_verbatim` and
is not part of the acceptance predicate.

### 3.3 Materiality rubric (fixed at intake; the adjudicator applies it)

A hole is **MATERIAL** if and only if it carries a locus (file:line or quote) and at least one of the following:
- **(a)** it would change the chosen option of a named DR row, or push that row's conviction below 90%;
- **(b)** it would change an AM row's verdict, threshold or check validity;
- **(c)** it would change sequencing, an interface contract, or a cost or timeline figure by more than ±20%;
- **(d)** it is a security, data-integrity or safety risk (always material).

**REFINEMENT** improves detail without meeting (a)–(d). **COSMETIC** is wording or format. A finding without a
locus is **GENERIC**: it is logged and rejected.

**Disagreement between raters does not make a finding MATERIAL.** This reverses revision 1, which counted ties as
MATERIAL "to be conservative". The judges found that choice made the stop unreachable. Measured here: every false
MATERIAL finding that passes verification breaks a dry run exactly as a real one does. At 0.25 such findings per
round, the build tier's rounds rise from 9/12 to 10/17 (p50/p90), and at 0.5 to 14/27, so the tail runs into the cap
(`tier_curve.out` §D). Agents flag something on correct artifacts ≥88% of the time (`llm-failure-modes.md` F17),
and FixedBench measured action bias at 35–65% (F4). So a dispute goes to one third rater, a different family,
blind to the other two. If the dispute still stands, the finding is **MATERIAL-DISPUTED**:
- it does not reset the dry count;
- it is listed by name on the certificate;
- it is fixed at build (`apply-at-build`), with the dispute recorded.

This rubric is the ISA 320 test ported to plans (`llm-failure-modes.md` T5).
It turns the heavy-tailed stream of "one more thing" into a finite population. Without a severity floor,
discovery grows like a power law without end (`unseen-estimation.md` §3.1 item 2).

### 3.4 Strata

Holes are estimated per stratum when a stratum holds ≥12 found holes, and pooled otherwise. Briand et al. found
accuracy saturates at about 12 defects (`unseen-estimation.md` §2.1).

| Stratum | Classes | Detector |
|---|---|---|
| FACT | C3, C10 (facts) | panels (premise lens) + premise register |
| COVERAGE | C4, C6, C1 omissions | panels (census and trace lenses) + census registers |
| VALIDITY | C5, C7, C8, C11 | panels (instrument, consistency and criteria lenses) + discriminating controls |
| CONTACT | C9 | contact probes only. **Outside the statistical certificate.** Desk panels are structurally blind here, and this is exactly the unidentifiable universal-blind mass in Link 2003 |
| FRAME | C2 | intake + challenge triage. Not estimated |

### 3.5 Stop parameters and tier (pre-registered, part of the ratified frame)

Defaults (overridable only at ratification):

| Parameter | Default | Source |
|---|---|---|
| Panels per round, T | 8 at the build tier. That equals the Workflow concurrency cap on this 10-core Mac, `Math.min(16,Math.max(2,e-2))` with 10 cores ⇒ 8, per workflow run (`docs/research/orchestration-units-2026-08-19.md:118-120`). T = 16 runs as two concurrent workflow runs | Briand: fewer than 4 inspectors is unusable, and error flattens above 4–5 |
| Model families per round | ≥3; 4 available (§4.3) | Chao & Tsay: 3 sources is the minimum for estimating dependence |
| Carried seeds, original cohort s₀ | 60, survivor-matched (§5.3); cap 1 per 25 lines of certified text | 60 already gives the median stated bound of 3 that 300 seeds give at N₀ = 60 (`tier_curve.out` §B) |
| Shadow seeds | 1 per applied fix, in its edited span | the fix-born cohort (§5.3) |
| Escape seeds | 20, stratified by class | hard-tail gate (§5.5) |
| K (consecutive dry rounds) | tier-dependent (§9.3) | Guest 2020 run length 2–3; stopping after a run of dry probes alone fails (next row) |
| Residual threshold | **used at entry, to choose the tier** from the price curve; never an exit gate | an exit gate on μ̂ ≤ 0.5 ended in an operator decision in 53% of programs (`tier_curve.out` §C) |
| Adjudication agreement | Cohen's κ on dedup and materiality is **reported**. Below 0.7 there is one re-adjudication pass of the disagreeing items. It is never a gate | Francis principle 3; a κ gate was one of revision 1's loops |
| R_max (cap) | min(forecast p90 + 4, R_abs), fixed after round 1 and printed with a date | `forecast_check.out`: p90+4 covered 99% of programs, and 93% under model misspecification |
| R_abs (absolute ceiling) | ratified at intake. Build tier: 16 rounds | the build tier's p90 at 0.25 false positives per round is 17 (`tier_curve.out` §D), and the cap costs no measured residual |
| Fable cap | 6 per program by default (§4.4), enforced by `cc-research` | the existing hook cannot see headless panels |

Why K dry rounds are not trusted on their own: a quiet run is not completeness. Guest 2020's 0%-new-information run
matched only 69–89% of the themes eventually found, and "50 consecutive irrelevant" missed its recall target in 39%
of runs (`stopping-rules.md` A4, B1). Here the dry rounds decide **when to stop**, and the carried seeds decide
**what the stop is worth**. Neither is stated without the other.

### 3.6 Ratification

Ratification goes through an **operator-only signature, never `cc-decide`**. `bin/cc-decide` has no agent guard, so
an agent could "ratify" its own frame. That was a judge's fatal flaw against revision 1, and the grep in the header
confirms it. `bin/cc-signoff` already has the three arms a ratification needs:
- it refuses when a claude process is an ancestor;
- it pins bytes to `origin/main`;
- it renders a forgery as VOID.

But it accepts only cc-mission row ids (`bin/cc-signoff:94-97`). Research programs must not be added to the customer
mission board, whose rows outrank all other work. Build item B7 (§10.1) therefore factors the three arms into a shared
library and adds a `research:<program>/<frame|cert>` namespace.

The agent prepares `docs/research/<program>/FRAME.md` and `frame.json`, lands them, and hands over one command, which
runs in the operator's own terminal:

`cc-signoff research:<program>/frame --evidence <frame.json sha on origin/main>`

A signed frame is content-pinned. Any later byte change to `frame.json` shows as "re-opened" until it is signed again.
After signing, the frame changes only through `cc-research amend`, which logs
`Scope (grown, cause=operator|agent-miss|drift)`; this closes gap G5 in `close-assertion.md` §5. An operator
amendment is not scored as a miss.

A `cc-decide` class-C packet is still used for what it is good at: priced, conviction-bearing decisions *inside* the
frame, such as the tier choice with its forecast, and DR rows still below 90% after their timebox.

---

## 4. The research loop and its roles (P1–P6)

### 4.1 Two kinds of search, kept apart

| | Discovery (P1–P3, and adaptive follow-ups) | Certification (P4–P5) |
|---|---|---|
| Purpose | find and fix holes | measure how many remain |
| Sees prior findings? | yes: directed, adaptive, specialist lenses | **no**: baseline-blind, frozen snapshot, same brief for every panel |
| Enters the incidence matrix? | **never** (adaptive search biases every estimator low; Böhme 2021, `unseen-estimation.md` §2.8) | yes |
| Quota of findings? | **none**: zero is a valid answer | **none**: zero is the expected answer at the end |
| Artifact edited during? | yes | **no**: fixes happen between rounds only |

### 4.2 Roles

| Role | Model / effort | Brief essentials | Writes |
|---|---|---|---|
| Program lead | Opus 5.5, high (dispatched session, §10.4) | owns `frame.json`, fires rounds, fixes between rounds by **integrating** edits (never appending), and never adjudicates its own plan | plan, registers |
| Census builders | Opus, high | enumerate each population (§6.1 S2) from the repo, logs and live stores, recording the search command per row | `census/*.jsonl` |
| Census critic (blind) | a non-Anthropic family | "Name members of population X that the list omits; zero is a valid answer; each needs a locus that proves it exists" | findings, then verified |
| Premise verifiers | Opus, high | raise every load-bearing premise to the code, live or measured tier, or mark it secondary with VOI = 0 | `premises.jsonl` |
| Contact prober | Opus, high, a dispatched session with tool access | runs every probe-able contact item on the target interpreter or OS; runs every handed command | `contact.jsonl` |
| Seed author | a family different from the lead's, in a separate session, never a panelist | writes original-cohort candidates (about 2× s₀), shadow seeds after each fix, and escape seeds from the mutation operators (§5.3); runs the discovery-style pre-screen and keeps the survivors | encrypted seed vault |
| Seed-realism discriminator | a third family | blind pairs of (seed span, real span): "which is planted?" | realism score |
| **Certification panels** (T = 8) | 4 families × 2 context strategies (§4.3) | frozen seeded snapshot; the 11-lens checklist; zero-allowed; the 4-field finding form; coverage attestation for every lens | panel JSON (§5.2) |
| Courier | Opus, medium | launches every panel as a **separate CLI process**, resolving binaries by absolute path (the header probe found a non-executable `claude` stub and a minimal PATH): `codex exec -s read-only`, `gemini -p … --approval-mode plan`, and for Anthropic panels `/opt/homebrew/bin/claude -p --setting-sources local --model <opus\|fable>`. That last flag strips the operator's resident instructions, rules and user hooks (probe in the header: `NONE` vs the mission board). It saves the raw output **verbatim** and never filters or summarizes, which keeps panels independent | raw output file |
| Dedup adjudicator | Opus, xhigh, blind to panel identity, detection counts and seeds | clusters findings into candidate holes and logs every merge and split | cluster log |
| Seed matcher | a script plus one Opus judge that knows the seeds | routes findings whose locus overlaps a seed span. The judge can return a finding as real | seed detections |
| Verifier | Opus, high, a different family from the finder where possible | reproduces each candidate from the primary source, with a tool receipt, **blind to how many panels found it** (so singletons are verified, not culled) | CONFIRMED / REFUTED / CONTACT |
| Materiality raters | rater 1 Opus xhigh; rater 2 codex on a 20% sample plus **every singleton**; rater 3 gemini only on disputes | apply §3.3; an unresolved dispute is MATERIAL-DISPUTED, never MATERIAL | κ (reported, with one re-adjudication pass below 0.7; never a gate) |
| Consistency reader | Opus, xhigh, a fresh context | whole-artifact read after the last edit of each fix cycle (C7) | contradictions → holes |
| Fable slots | Fable 5.1, high | §4.4 | — |

### 4.3 Model diversity, checked on this machine today (a contact probe, not a doc claim)

- **Anthropic:** Opus 5.5 (default) and Fable 5.1 (frontier). They are the same provider, so they are modeled as
  correlated: the log-linear dependence term in §5.4. The simulation's Fable slot is correlated with Opus at ρ = 0.6.
  Headless panels run with `--setting-sources local`, verified this session to load none of the operator's resident
  instructions.
- **OpenAI:** `codex-cli 0.147.0`, `codex login status` reports "Logged in using ChatGPT" (re-probed after the
  reboot). Headless: `codex exec -s read-only`.
- **Google:** `gemini` 0.29.5, with `~/.gemini/oauth_creds.json` present (mode 0600, dated Feb 22). Headless:
  `gemini -p … --approval-mode plan`. Auth has not been exercised by a real call; round 0 preflights it.
- **Not usable as-is:**
  - `grok-wiki` is not on this shell's PATH after the reboot. Revision 1 found it failing with `EACCES` on the
    broken `claude` stub (`skills/grok-wiki-audit/SKILL.md:16`), and this session hit the same stub directly.
  - Couriers call the vendor CLIs by absolute path, and round 0's preflight records each resolved binary and its
    version.
- **Default round composition (T = 8):**
  - Opus × 2: full context, and adversarial "assume it fails in production";
  - codex × 2: full context, and spec-only (plan without research docs);
  - gemini × 2: full context, and consumer perspective;
  - Opus or Fable × 2: spec-only, and adversarial. Fable fills one of these slots in rounds 1, 3 and 5 only (§4.4).
- **Why this matters:** in simulation, moving from 1 to 4–5 families is the largest single lever.
  - Holes found by 10 panels rise from 136–151 to 166–184 of 200 (`unseen-estimation.md` §5).
  - At the same stop rule (K = 3), eight Opus panels leave 1.50 desk-detectable material holes on average, with
    P(≥1) = 0.76, and need 10/14 rounds. The diversified eight leave 0.70 (P = 0.50) in 9/12 rounds.
  - Sixteen diversified panels leave 0.27 (P = 0.23) in 7/9 rounds (`stopping_model.out` §2).
  - Same-family panels also make the round-1 Chao2 read low: 48.9 against a true 57 (§3).

### 4.4 When the Fable frontier tier is used (and when not)

| Use | Why this, and not the default | Budget |
|---|---|---|
| Intake framing ladder, **only** if an AM or DR framing question is still below 90% after research (the T-a/T-b/T-c test in `CLAUDE.global.md`) | a different model's blind spot on framing, which is the class (C4 unstated premises; shard-7 pattern 1) that critics miss | 1 |
| One certification slot in rounds 1, 3 and 5 | a fourth, partly independent capture occasion. Modeled as correlated with Opus | 3 |
| Post-gate blind-spot sweep: 2 `frontier-derivation` panelists, baseline-blind, on the certified snapshot, reconciled CONFIRMED / NEW / REFUTED (`skills/frontier-run/SKILL.md:116-137`) | a structurally different detector aimed at the mass that overlap statistics cannot see (Link 2003). Its NEW material count checks the certificate: more NEW than the stated bound means the calibration broke (§8.3) | 2 |
| **Never** | the lead; file edits (5.1 rewrites whole files); adjudication | — |

That totals 6, exactly `frontier_discovery_budget.max_fable_spawns_per_session: 6`
(`~/.claude/model-config.yaml:1116`).

**The existing gate cannot see these spawns, so `cc-research` enforces the cap itself.** Measured this session:
- `hooks/frontier-spawn-gate.sh` is registered only on the `Agent` matcher. The Bash-matcher check in the global
  instructions returns `false`, because migration 0029 has not been run.
- A panel run as `claude -p --setting-sources local` loads no user hooks at all.

So neither a courier's CLI call nor a `handoff-fire.sh --model fable` round session is counted by that hook.
`cc-research panel run` keeps its own per-program Fable ledger (`fable_cap` in `frame.json`, ratified with the tier),
checks weekly-Fable headroom with `claude-accounts` before each Fable slot, and refuses past the cap. A refused Fable
slot is filled by Opus and flagged in the round manifest; it is never silently dropped. Whether Workflow `agent()`
calls with `model: fable` are counted by the hook remains **unverified**, and W0 checks it.

### 4.5 The certification panel brief (frozen; the same for all T panels)

Its core clauses, written to counter the measured failure modes in `llm-failure-modes.md`:

> You are auditing the FROZEN plan at `<seeded path>` against the frame at `<frame.json>`. Read-only. You will not
> see other reviewers' findings or any earlier findings; do not look for them.
> For EACH of the 11 lenses (premise, census, instrument, trace, consistency, sequencing, criteria, contact
> declaration, drift, frame-omission, operator-intent), attest what you checked, then either list findings or
> write "nothing material".
> **Zero findings is a correct and expected outcome. You are not rewarded for finding something.**
> Each finding MUST carry: (a) locus (file:line or verbatim quote); (b) the DR or AM id it would change and how,
> or the sequencing, interface or cost figure it moves by more than 20%, or the safety risk; (c) a tool-call
> receipt from the primary source (code, live store, measurement), because a claim from memory is rejected;
> (d) your probability it is real and material, plus the observation that would falsify it.
> Do not read `<real program dir>`. Do not read the git history of `<program files>`.

This removes the quota prompts the research found. `agents/deep-research.md:187` "Find 2-3 gaps",
`agents/research-decomposition-critic.md:37-38` "name 1-3", and `skills/research-subagents/SKILL.md:796-803` "List
3" each guarantee a non-empty output. **A panel with a quota can never return a dry round, so any dry-round stop
rule is unreachable by construction.** Removing the quotas is a precondition of this design, not a refinement.

---

## 5. Persisted artifacts and schemas

### 5.1 Layout

Tracked in the **project** repo, never in /tmp (C6; `greenfield-cases.md` row voiceink: 5 of 9 artifacts existed only
in /tmp):

```
docs/research/<program>/
  FRAME.md            human-readable frame (rendered from frame.json)
  frame.json          AM, DR, rubric, strata, stop parameters, tier, deadline, exclusions, ratification
  premises.jsonl      premise register
  census/<pop>.jsonl  one file per population
  contact.jsonl       contact register
  trace.jsonl         research finding → plan item | rejection
  facts.jsonl         dated external facts + recheck commands
  holes.jsonl         hole ledger (append-only; the fold of records = current state)
  rounds/<k>/matrix.json   incidence matrix + estimators for round k (no seed content, only seed ids + detections)
  rounds/<k>/panels/<pid>.json   panel outputs (seed spans redacted after the round)
  cert/CERT-v<n>.json, CERT-v<n>.md
  challenges.jsonl    post-gate challenge triage
  verdicts.jsonl      every completeness question asked and what answered it
```

**Sealed**, outside every repo, mode 0700, and seeds **encrypted at rest**. This is a judge's fix. Panels run as the
same uid, so file mode alone does not keep a panel out; a stray grep should find ciphertext, not seeds. The sealed
paths:
- `~/.claude/autonomy/research/<program>/vault/seeds.enc`: `openssl enc -aes-256-cbc`, with the key in the login
  keychain. Only `cc-research seed apply|match` decrypts it, in memory.
- `…/rounds/<k>/bundle/`: the seeded snapshot the panels read, at a **fresh path per round**.
- `…/rounds/<k>/sanitized-worktree/`: the code at the trunk sha, with `docs/research/<program>/` and `.git` removed.
  It is the panels' cwd, so no panel can reach `git log` or the unseeded plan.

The hash of each sealed file is committed into `matrix.json`, so the vault can be audited after the program without
being exposed during it. After every round, an **integrity audit** greps every panel's transcript and output for the
real program path, the vault path and `git log`. A hit **voids that panel**, and the round is re-run with a
replacement panel.

Machine-level stores, outside any one program:
- `~/.claude/autonomy/research/programs.json`: a program registry (name → repo, certificate path, status). It lets the
  re-ask hook resolve a program from any cwd (§7.1).
- `docs/research/research-calibration.jsonl` in claude-infrastructure: one row per program. Each row holds the family
  × family co-detection matrix, round-1 seed recall per family, the realism checks, the forecast against the actual
  round count, and post-gate escapes against the stated bound. The reference class that replaces this design's
  simulated priors accumulates here.

### 5.2 Record schemas (JSON; `cc-research` validates on write)

```jsonc
// frame.json
{ "program": "...", "question": "...", "intent_verbatim": "...", "consumer": "...", "deadline": "YYYY-MM-DD",
  "tier": "decision|build|max", "trunk_sha_at_ratify": "...",
  "am": [{ "id": "AM-7", "predicate": "p50 end-to-end ≤ 1.5 s on 20 real clips", "ceiling": {"value": 0.14, "unit": "s", "receipt": "..."},
           "check_cmd": "...", "expected_now": "fail|pass", "negative_branch": "...",
           "control": {"planted_defect": "...", "went_red": true, "known_good": "...", "went_green": true, "receipt": "..."},
           "taste_gate": null }],
  "dr": [{ "id": "DR-3", "question": "...", "options": ["...", "use-what-exists", "do-nothing"], "chosen": "...",
           "conviction": 92, "receipt": "...", "timebox_days": 2, "voi_note": "..." }],
  "materiality": { "rubric_version": 1 },
  "strata": ["FACT", "COVERAGE", "VALIDITY"],
  "exclusions": [{ "what": "...", "operator_words": "..." }],
  "declared_residual_classes": ["CONTACT-prod", "CONTACT-tenant", "CONTACT-time", "DRIFT-unforeseeable", "FRAME-new"],
  "stop": { "T": 8, "families_min": 3, "K": 3, "seeds": {"original": 60, "shadow_per_fix": 1, "escape": 20},
            "R_escape_min": 0.5, "R_abs": 16, "R_max": null, "fable_cap": 6,
            "tier_forecast": {"residual_mean": 0.62, "p_any": 0.46, "rounds_p50": 9, "rounds_p90": 12, "source": "tier_curve.out §A"} },
  "ratified": { "signoff_row": "research:<program>/frame", "ts": "...", "origin_main_pin": "<blob sha>",
                "ancestry": ["zsh", "kitty"], "tier_packet": "<cc-decide id of the tier choice>" } }

// premises.jsonl
{ "id": "P-12", "claim": "...", "load_bearing": true, "supports": ["DR-3", "AM-7"],
  "tier": "code|live|measured|secondary", "source": "path:line | cmd => output | URL",
  "checked_at": "ISO", "recheck_cmd": "...", "fresh_for_h": 72, "voi_if_secondary": "cannot flip DR-3 because ..." }

// census/<population>.jsonl — first line is the header
{ "header": true, "population": "execution-contexts", "search_cmds": ["..."], "coverage_check": "...", "critic": {"panel": "...", "unlisted_verified": 0} }
{ "member": "launchd (/bin/bash 3.2.57)", "source": "...", "how_found": "cmd => output", "in_plan_at": "PLAN.md:212" }

// contact.jsonl
{ "id": "X-4", "property": "...", "target": "interpreter|os|process|artifact|scale|tenant|prod|time",
  "probe_cmd": "...", "ran_at": "ISO", "receipt": "...", "verdict": "pass|fail|n/a",
  "irreducible": false, "owner": null, "due": null, "falsifier": null, "backlog_id": null }

// trace.jsonl
{ "finding": "docs/research/x.md#warm-connection", "maps_to": "PLAN.md§4.2" }
{ "finding": "...", "rejected": "reason", "rejected_by": "DR-5" }

// facts.jsonl
{ "id": "F-9", "fact": "upstream VoiceInk latest = v2.19", "source": "URL", "observed_at": "ISO",
  "recheck_cmd": "gh release view -R ... --json tagName", "dependents": ["P-12", "DR-1"], "last_rechecked": "ISO", "changed": false }

// holes.jsonl (append-only; one record per state change)
{ "id": "H-41", "round": 3, "source": "panel|adaptive|discovery|consistency|challenge|contact|operator",
  "panels": ["r3p2", "r3p6"], "locus": {"path": "...", "lines": "212-218", "quote": "..."},
  "class": "C4", "stratum": "COVERAGE", "materiality": "MATERIAL|MATERIAL-DISPUTED|REFINEMENT|COSMETIC|GENERIC",
  "material_ref": {"dr": ["DR-3"], "am": [], "how": "..."},
  "verification": {"status": "CONFIRMED|REFUTED|CONTACT|UNCONFIRMED", "by": "...", "receipt": "..."},
  "frame_class": "in-frame-miss|frame-expansion|relabel|contact-residual|drift|criteria",
  "born_in_edit": true, "edit_round": 2,
  "disposition": {"kind": "fixed|rejected|apply-at-build|residual|open", "ref": "commit sha | backlog id | reason"},
  "adjudication": {"merge_log": "...", "rater2": "agree|disagree|n/a", "rater3": "agree|disagree|n/a"}, "ts": "ISO" }

// rounds/<k>/panels/<pid>.json (schema'd Workflow return)
{ "pid": "r3p5", "round": 3, "family": "openai", "model": "...", "effort": "...", "strategy": "spec-only",
  "snapshot_sha": "...", "seeded_bundle_hash": "...", "status": "complete|partial|dead",
  "lenses": [{"lens": "census", "checked": ["..."], "result": "nothing material | [fid...]"}],
  "findings": [{"fid": "...", "locus": {...}, "lens": "...", "claim": "...", "material_ref": {...},
                "receipt": "...", "p_real_material": 0.7, "falsifier": "..."}],
  "tokens": 0, "wall_s": 0 }

// rounds/<k>/matrix.json
{ "round": 3, "snapshot_sha": "...", "T": 8, "families": {"anthropic": 3, "openai": 2, "google": 2, "fable": 1},
  "dry": false, "holes": [{"id": "H-41", "stratum": "COVERAGE", "x": [0,1,0,0,0,1,0,0]}],
  "seeds": {"original": [{"sid": "S-07", "class": "C3", "x": [...]}], "shadow": [], "escape": [], "orphaned_this_round": []},
  "est": {"S_obs": 0, "Q1": 0, "Q2": 0, "chao2_bc": 0, "jk1": 0, "jk2": 0, "coverage": 0, "next_panel_gain": 0,
          "per_family_chao2": {}, "family_codetection": [[0]],
          "original": {"F": 0, "k_left": 0, "s_eff": 60, "orphaned": 0, "mu_point": 0, "n_pred95": 0, "p_any": 0},
          "shadow": {"F": 0, "k_left": 0, "s_eff": 0, "mu_point": 0, "n_pred95": 0},
          "total": {"mu_point": 0, "n_pred95": 0, "p_any": 0}, "escape_by_class": {"C4": [3, 4]},
          "realism": {"mw_z": 0.0, "flag": false}},
  "found_per_round": [47, 9, 3], "b_hat": 0.0, "stop": "running|dry|cap", "R_max": 13, "voided_panels": [],
  "kappa": {"dedup": 0.0, "materiality": 0.0, "readjudicated": 0}, "sealed_hashes": {...} }

// vault seeds (decrypted only in memory by cc-research seed apply|match)
{ "sid": "S-07", "cohort": "original|shadow-r3|escape", "class": "C3", "file": "PLAN.md",
  "anchor_quote": "≥40 chars, unique in file", "replacement": "...", "defect_statement": "...",
  "detect_span": "PLAN.md:212-218", "planted_round": 1, "state": "live|caught|orphaned", "state_round": null,
  "prescreen": {"caught": false, "panel": "..."} }

// cert/CERT-v<n>.json
{ "cert": "CERT-v3", "program": "...", "snapshot_sha": "...", "trunk_sha": "...", "issued": "ISO",
  "tier": "build", "stop": "dry|cap", "rounds": 9, "panel_runs": 72, "families": 4,
  "structural": {"S1": "pass", "...": "..."}, "calibrated": false,
  "residual": {"FACT": {"mu": 0, "n_pred95": 0, "p_any": 0}, "COVERAGE": {}, "VALIDITY": {}, "total": {}},
  "named_open": {"disputed": ["H-52"], "weak_lenses": ["C6"], "realism_flag": false, "reduced_diversity": []},
  "declared_residual": [{"class": "CONTACT-prod", "ref": "X-4", "owner": "...", "due": "..."}],
  "escapes": {"FACT": 0, "COVERAGE": 0, "VALIDITY": 0}, "signed": {"by": "cc-signoff", "row": "research:<P>/cert", "pin": "..."} }

// challenges.jsonl
{ "id": "CH-5", "ts": "ISO", "raised_by": "operator|agent|fable-sweep|build", "locus": {...},
  "material_ref": {...}, "frame_class_claimed": "...", "evidence_date": "ISO",
  "triage": "relabel|immaterial|frame-expansion|contact-residual|drift|escape|refuted",
  "action": "...", "stratum_reopened": "COVERAGE|null", "delta_round": "rounds/d2|null", "outcome": "..." }

// verdicts.jsonl
{ "ts": "ISO", "session": "...", "question": "...", "answered_with": "CERT-v3|CH-5", "cert_valid": true }
```

### 5.3 Seeds: the mutation operators (one per desk-detectable class)

Seeds are written against the seeded copy of the snapshot, never the tracked plan. Carried seeds are stratified in
proportion to the desk-findable distribution in `taxonomy_stats.py` (C4 29, C3 26, C1 23, C5 13, C6 12, C7 8, C8 8,
C11 4, C10 3).

| Class | Operator |
|---|---|
| C3 | Change a load-bearing figure or fact so that the primary source contradicts it (the code, `live cmd => output`) |
| C4 | Delete one member of an enumerated population (a caller, platform, tenant, option such as "use what exists") that the repo or live store proves exists |
| C5 | Replace an AM check with one that cannot fail (presence-only, `\|\| true`, a grep of the plan itself, n = 1) |
| C6 | Delete the plan item that a research-doc finding requires, and keep the research doc |
| C7 | Change one restatement of a value (a table cell against prose) |
| C8 | Move a verification step after a land or publish step |
| C10 | Insert an external fact with an old observation date that has since changed |
| C11 | Replace a numeric predicate with a superlative |
| C1 | Drop an open item from `trace.jsonl` or the reconciliation while it stays in plan prose |

Not seedable, and explicitly outside the panel certificate: C2 (operator-private) and C9 (contact).

**Seed mechanics across edits.** A judge found these unspecified in revision 1. The format and lifecycle:

- **Format.** A seed is a patch anchored on a verbatim quote:
  `{sid, cohort, class, file, anchor_quote (≥40 chars, unique in the file), replacement, defect_statement, detect_span}`.
  Seeds live only in the vault (§5.1).
- **Application.** `cc-research seed apply` builds each round's bundle from the tracked, unseeded plan at the round's
  sha, then applies every uncaught seed. The lead edits only the unseeded plan and never sees a seed.
- **Orphans are censored, not counted.** If a fix rewrote a seed's anchor, so it is absent or no longer unique, the
  seed is orphaned at that round. It leaves its cohort's denominator and counts as neither caught nor surviving.
  Censoring that does not depend on difficulty leaves the estimator unbiased and only widens it (`tier_curve.out`
  §E).
- **Cohorts.**
  - The **original cohort** (s₀ seeds) is planted at the first freeze and carried to the end.
  - A **shadow cohort** plants one seed inside each applied fix's edited span, then carries it. Shadow seeds age
    exactly like the fix-born holes (C7) they stand in for. They replace revision 1's "fresh seeds at confirmation",
    which only covered holes born by the last fix.
  - The **escape cohort** (20) is the hard-tail gate (§5.5), never a denominator.
- **Caught.** A panel finding whose locus overlaps a seed's `detect_span`, and whose claim matches the
  `defect_statement`, catches that seed. A script proposes the match; one seed-aware judge confirms it and can return
  the finding as real. A caught seed is removed from later bundles, exactly as a fixed hole is.

**Survivor-matched seeding (new in revision 2).** By the first freeze, the real holes have already survived the
discovery phases (P1–P3). They are the ones discovery missed, and so on average harder than freshly written seeds.
`seed_realism.out` measures what that does to the bound. The seed author therefore writes about 2× the candidate
seeds, and passes them through a **pre-screen**: one blind Opus pass with the P2 discovery brief on a seeded copy.
Candidates the pre-screen catches are discarded, just as discovery would have removed a real hole like them. Only
survivors enter the original cohort.

**Realism checks.**
1. **Once, before round 1.** A discriminator from a third family gets 20 blind pairs of (seed span, real span). If it
   identifies the seed more than 70% of the time, the seeds are rewritten **once**. This answers Musa's critique
   that seeded defects are easier to find than real ones (`unseen-estimation.md` §2.6).
2. **On round-1 data, which costs nothing extra.** Among items caught in round 1, compare how many panels caught each
   seed with how many caught each real hole (one-sided Mann-Whitney, flag at z > 1.645).

   Measured in `seed_realism.out` (s = 100, 1,500 runs per row):

   | Scenario | Flag rate | Stated bound held (claims 95%) | μ̂ vs true residual |
   |---|---|---|---|
   | Seeds matched to real holes | 5.5% | 99.2% | 0.97 vs 0.70 |
   | Seeds 0.5 logit easier | 39.9% | 98.1% | 0.59 vs 0.64 |
   | Seeds 1 logit easier | 90.4% | 97.2% | 0.42 vs 0.65 |
   | Real holes are discovery survivors, seeds fresh | 51.7% | 95.5% | 0.84 vs 0.98 |
   | Same, seeds pre-screened (survivor-matched) | 4.4% | 98.2% | 1.23 vs 0.90 |
   | Weaker discovery, seeds fresh | 20.1% | 97.3% | 0.85 vs 0.76 |
   | Weaker discovery, seeds pre-screened | 4.8% | 98.2% | 1.07 vs 0.77 |

   Two readings follow.
   - **The stated bound is robust to seeds being too easy.** The flat-prior predictive stays at or above 95% in every
     scenario. The **point estimate** μ̂ is what runs low, by up to 35%.
   - **Pre-screening removes the mismatch the test detects.** Its flag rate falls to the false-alarm rate.

   A flag therefore does not stop the program. The certificate prints "realism flag: seeds easier than real holes
   (z = …): μ̂ likely low; the bound stands", and W0's calibration row records it. Revision 1's other round-1 check,
   Mills N̂ ÷ jackknife-2 N̂ outside [0.5, 2], flagged in **0%** of runs in every scenario above. It is dropped. An
   earlier draft of this revision fell back to "the larger of the seed estimate and JK2 − F". That was also
   dropped: the round-1 JK2 has a P10–P90 spread of about ±9 holes (`stopping_model.out` §3), so JK2 − F is noise at
   residuals below 1.

### 5.4 Estimators (all computed by `cc-research estimate`; each has a planted-input test that must go red)

Per round k on snapshot S_k. Only verified MATERIAL real holes enter the matrix. Q_j is the number of holes found
by exactly j of the T panels.
- **Overlap estimators** (cross-check and forecast input; biased low under positive correlation):
  - bias-corrected Chao2: S + ((T−1)/T)·Q1(Q1−1)/(2(Q2+1));
  - jackknife 2: S + ((2T−3)/T)Q1 − ((T−2)²/(T(T−1)))Q2;
  - coverage Ĉ;
  - expected new holes from panel T+1;
  - per-family Chao2. The divergence between families measures dependence.

  Formulas and sources are in `unseen-estimation.md` §3.4.
- **Carried-seed ratio (the primary residual estimate)**, computed per cohort. The original cohort covers the holes
  present at the first freeze. The shadow cohort covers fix-born holes. Per cohort:
  - s_eff = seeds planted − orphaned (§5.3), and k_left = seeds still uncaught;
  - survival π̃ = (k_left + 0.5)/(s_eff + 1);
  - F = verified MATERIAL real holes found so far that are attributed to that cohort: original holes, or holes
    `born_in_edit` for the shadow cohort. A false positive that passed verification inflates F, which is the
    conservative direction;
  - point estimate μ̂ = F·π̃/(1−π̃). This is Mills' / Lincoln–Petersen's ratio, with the seeds as the marked set;
  - **stated bound n_pred95** = the 95% quantile of the posterior predictive of the residual count R. Here
    π ~ Beta(k_left + ½, s_eff − k_left + ½) (Jeffreys), and R | π ~ NegBin(F + 1, 1 − π), which is a flat prior on
    the cohort's size. The cohorts' draws are summed for the total, and P(at least one) is read off the same draws.
    `cert_sim.py: predictive_draws` implements it.

  **Why these choices, measured on the rebuilt simulation** (`carried_seeds.out`, `cert_calibration.out`):
  - Fresh end-seeds held their bound in only 71–87% of runs.
  - Revision 1's μ_up = F·π_up/(1−π_up) bounds the *mean*, not the count. At N₀ = 60 it held in 95–100% of runs at
    s ≤ 100, but only 86–87% at s ≥ 200. At N₀ = 20 it was already down to 89% at s = 60, and reached 77% at s = 300.
    Once seeds pin π tightly, the count's own scatter dominates.
  - The posterior predictive bound held in 97.8–100% at every s from 20 to 300, at N₀ = 20 and 60. So
    **n_pred95 is the stated bound, and μ̂ is the point estimate.**
  - The same predictive gives a stated P(≥1 left) of 0.51 when the true rate is 0.45 (N₀ = 60, s = 100). It is
    slightly conservative, which is the right direction.
- **Fix-born holes (C7)** are covered by the shadow cohort. It replaces revision 1's fresh-seeds-at-confirmation
  bound, which covered only holes born by the last fix. Shadow seeds are born with each fix and carried, so they
  have the same age mix as the fix-born holes still alive.
- **Fix-born rate:** b̂ = (verified material holes in round k+1 whose locus falls inside round k's edited spans) ÷
  (fixes applied in round k). It is printed each round beside the found-per-round series. Its divergence reading is
  in §9.2.
- **Realism check (round 1):** the Mann–Whitney capture-count test in §5.3, reported on the certificate.
- **Dependence model**, once ≥3 families are present: a log-linear model over the 2^T capture histories, with a
  family × family interaction for same-provider pairs (Opus/Fable). It is reported beside Chao2, not in place of
  it (`unseen-estimation.md` §2.4).
- **Singletons are never deleted before estimation.** Verification is blind to detection counts. A REFUTED
  singleton leaves the matrix because it is false, never because it is single (Deng 2024; `unseen-estimation.md`
  §2.10).

### 5.5 Escape seeds: the hard tail

The 129 desk-findable holes in `/tmp/rescomp/taxonomy_holes.py`, each with a receipt, seed the escape library at
`docs/research/escape-library/escapes.jsonl`. It gains a row for every post-gate escape in every future program.
For each program the seed author transplants 20 escape **mechanisms**, never their content, into the snapshot.
Their recall is reported per class. They are **not** used as a population denominator: in simulation, escapes
overestimated N about 2.5× (`unseen-estimation.md` §5 row I). They gate the hard tail (§6.2 Q4).

---

## 6. The exit gate (`cc-research gate`)

**Every row below is finite by construction.** Revision 1 had rows that could loop: a residual threshold that seeds
could not resolve, a κ gate, an uncapped hard-tail detector, and a re-run of realism "until it passes". The judges
named each one (`SYNTHESIS.md` §12). In revision 2, each row either checks an artifact that exists, or runs once
with a named fallback. The only loop in the protocol, certification rounds, is capped by R_max (§6.2 Q1). The gate
therefore always ends in **one verdict: CERTIFIED, with its stop reason and its stated residual.**

### 6.1 Structural gates (frame closure)

| Gate | Criterion | Mechanical check |
|---|---|---|
| S1 Frame | `frame.json` hash equals the ratified hash, or the change log has an amendment. There are zero superlative-lint hits in AM predicates. Every AM row has `check_cmd`, a threshold and `negative_branch` | hash compare; lint over `am[].predicate` with the ground-up ban list |
| S2 Census | These populations each have a file with ≥1 member or a `none, searched <cmd>` row: options (including do-nothing and use-what-exists), candidates from the repo, callers and instances, platforms and execution contexts (including the scheduler's interpreter), accounts and tenants, concurrent actors (sibling sessions or plans on the topic), publication surfaces, prior invariants (each with a guard test), evidence sources (logs, trackers), baseline decisions (including silent defaults and freeze clauses), and runtime dependencies (where it runs, what keeps it alive, what expires, who re-authenticates). The blind census critic runs **once** per population. Every member it names that verifies is integrated, so zero verified members stay unintegrated. The critic is never re-run to look for zero: later census misses are the certification panels' census lens, counted in the estimate | file presence, header `search_cmds` non-empty, the critic's single pass integrated |
| S3 Premises | Every `load_bearing` premise has tier ∈ {code, live, measured} within `fresh_for_h`, or is secondary with a `voi_if_secondary` that names why it cannot flip its DR | jq over `premises.jsonl` |
| S4 Instruments | Every AM `check_cmd` has run against current state with its `expected_now` result, and has gone red on a planted defect with a receipt. This is the DOCS_CONSOLIDATION_100P pattern that found 45 of 58 unsound checks before build (`plan-lifecycle.md` §4.5). **Greenfield case** (the subject does not exist yet; a judge said revision 1 left this undefined): the check runs against a fixture pair from P3. The known-bad fixture violates the predicate, for example a stub endpoint that sleeps past the latency threshold. The known-good fixture satisfies it, and may be the P3 contact spike. Discrimination means the check returns fail on known-bad and pass on known-good | `control.went_red == true` and `control.went_green == true` with receipts, rerun by `gate --rerun-controls` |
| S5 Contact | Every non-irreducible contact item has `verdict` and `receipt`. Every irreducible item (production, tenant or time only) has an owner, due date and falsifier and is filed (`cc-backlog add --why-not-now "not-yet-true: …" --falsifier …`). Every command the plan hands the operator has been run by the agent | jq; `cc-backlog list --json` cross-check |
| S6 Trace and index | The research-index search at program start is recorded. Every finding anchor in the program's research docs has a `maps_to` or a `rejected` row. There is a topic ownership lock with a positive liveness signal, so no second lead is live on the topic | `cc-research trace --check` exits 0 |
| S7 Consistency | The consistency reader's pass ran on the **certified** snapshot sha after the last edit, with 0 open contradictions. Edited spans and their dependents (from `premises.supports` and `facts.dependents`) were re-verified | sha equality; `holes.jsonl` fold |
| S8 Liveness | Every counted round has T_eff = T complete panels (every lens attested) and ≥ `families_min` families. Dead, partial or voided (integrity-audit hit) slots were re-run, never counted as clean. The cap is 2 re-runs per slot. After that the slot takes the next family in the ratified order. If fewer than `families_min` families are available, the round runs with those it has, and the certificate prints "reduced diversity: <n> families in round k" | round manifests; the integrity-audit log |
| S9 Drift | Within 24 h of the gate, the trunk sha was re-read, every `facts.jsonl` recheck_cmd was re-run, and no changed fact has unresolved dependents. Credentials the plan depends on were validity-checked | recheck log |
| S10 Reconciliation (C1) | Every open item in every store maps to done, not-required-with-reason, filed, or AM or DR. The stores are plan prose (`TODO`/`open`/`- [ ]`/"follow-on" markers), research-doc residual sections, `cc-backlog list --project P`, `cc-decide list --open` for the project, and dirty files. There are zero unmapped items | `cc-research reconcile --check` |

### 6.2 Statistical rows (on the final snapshot)

A structural row that fails at gate time is fixed; its list of checks is finite. If the fix is MATERIAL, a delta
round runs on the affected certification unit, capped at 2 as in §8.2. That is the only work allowed after the stop
rule fires.

| Row | Criterion | Can it block? |
|---|---|---|
| **Q1 Stop** | `stop=dry`: the last K rounds were consecutive and dry, meaning 0 new verified MATERIAL findings, real or false, on the same snapshot sha. Any MATERIAL fix, from any source, resets the count; MATERIAL-DISPUTED does not. **Or** `stop=cap`: r = R_max. The last round's finds are fixed and consistency-read, and the certificate names them | No. Both stop reasons certify. The cap costs no measured residual (`tier_curve.out` §D) |
| **Q2 Residual (stated)** | μ̂, n_pred95 and P(≥1), per stratum and in total, printed beside the tier forecast the operator bought at intake (`frame.json.stop.tier_forecast`). `cc-research forecast` also simulates the distribution of the *stated* bound for this program's measured N̂₀ and R̂. If the actual n_pred95 exceeds that distribution's p90, the certificate is flagged **below tier** | No. "Below tier" opens a `cc-decide` class-B packet offering `extend` (§6.3) at its quoted price. Its default, "accept as issued", fires after 24 h |
| **Q3 Fix-born** | The shadow cohort is stated inside Q2. b̂ and the found-per-round series are printed. At b̂ ≥ 0.5 in any round ≥ 3, the divergence step (§9.2) runs inside the same R_max | No |
| **Q4 Hard tail** | Escape-seed recall ≥ 0.5 in each class with ≥3 escape seeds. For a class below it, **one** attempt: a structural detector (a census file, a lint, a probe) is added and tested once, against that class's escape seeds, in the next round or in a delta round. If the class is still below 0.5, the certificate names it a **weak lens**, and the W0 calibration row records it | No |
| **Q5 Adjudication** | Dedup and materiality κ on the second-rater sample (every singleton included) are reported. Below 0.7, one re-adjudication pass runs on the disagreeing items. Unresolved disputes are MATERIAL-DISPUTED (§3.3) | No |
| **Q6 Realism** | The round-1 Mann–Whitney flag (§5.3) is reported. The bound stands; the certificate says μ̂ is likely low | No |
| **Q7 Calibration state** | "uncalibrated" until W0 reports. After W0, W0's measured hold rate for the stated bound is printed next to its 95% claim. No multiplier is applied, because calibrating with a factor k multiplies variance by k² (Briand 2000, Eq. 9; `unseen-estimation.md` §2.1) | No |

### 6.3 Buying more after the stop: `cc-research extend` (Dalal–Mallows, made explicit)

The stop never extends itself. When the operator wants more assurance, `cc-research extend --rounds m` prints a
quote:
- **the expected material holes m more rounds would catch:** μ̂·(1 − (1 − ρ̂)^m), where ρ̂ is the carried-seed
  catch rate per seed-round over the last K rounds;
- **the cost:** m·T panel-runs, in weekly-quota percent (§9.1);
- **the ratio of the two.**

This is Dalal & Mallows's comparison of detection value against search cost (`stopping-rules.md` C5), shown to the
operator instead of hidden in a loop. The decision to buy is a value call, so it is a `cc-decide` class-C packet.

**Assurance that cannot be measured cannot be bought.** If every carried seed is already caught, more rounds cannot
tighten the stated bound, and the quote says so. Tightening the statement needs more seeds (§1.2). Tightening the
residual needs more panels (T), and in the simulation, width beats depth (§9.3).

---

## 7. Answering "are we 100.00/100.00 complete?" after the gate

1. **Answer from disk, never by regeneration.** `hooks/research-cert-inject.sh` (new UserPromptSubmit hook, sibling
   of `hooks/research-precognition-nudge.sh`) matches the completeness-question pattern. It reuses the regex from
   `/tmp/rescomp/internal/ca_scan.py`, which must be copied into the repo, because /tmp is reaped. The hook resolves
   the program through `~/.claude/autonomy/research/programs.json`, which matches the cwd's repo or a program name in
   the prompt. That makes it work from any pane and any worktree; revision 1's cwd keying missed asks from other panes
   (`close-assertion.md` G11). When the program holds a valid certificate, the hook injects
   `cc-research cert --render` as `additionalContext` with this instruction: *"Answer =
   this certificate verbatim plus ≤3 lines. Do not start a fresh audit. A new item is filed with
   `cc-research challenge` (locus, DR/AM id changed, frame class, evidence date) and you report its triage
   verdict."* Every ask is appended to `verdicts.jsonl`.
2. **The rendered answer** (example shape):
   ```
   Research certificate v3 · program <P> · snapshot a1b2c3d · issued 2026-10-14 · tier build (signed 10-01)
   Stopped: 3 rounds in a row found no new material hole (round 9 of a 16-round cap; forecast was 9, p90 12)
   Material holes found and fixed: 57 over 9 rounds (72 blind panel-runs, 4 model families)
   Estimated material holes still present: 0.6 · at most 3 (95%) · 45% chance of at least one — UNCALIBRATED until W0
   You bought: build tier, forecast 0.62 left, 46% chance of at least one; this certificate is within it
   Hidden test defects: 58 of 60 caught; realism check passed. Hard tail: 17 of 20 past-escape defects caught;
     weak lens named: "research never reached the plan" (2 of 3 caught)
   Named open items: 1 disputed finding (H-52, fixed at build) · 0 escapes since signoff
   Outside this certificate by design: 6 production/tenant/time checks, each owned and dated (contact.jsonl);
     holes no desk reviewer can see, which the contact wave and the Fable sweep target
   100.00 would need every possible hole location examined; the target you signed on 10-01 is the build tier.
   ```
3. **Two verbs, no third.** The operator can **buy more**: `cc-research extend --rounds m` or
   `cc-research raise --tier max` prints the price and the expected yield (§6.3, §9.3), and opens a class-C packet.
   Or the operator can **challenge** a named item (§8). A bare
   re-ask gets the same answer, deterministically. This removes the "Are you sure?" flip, which changes answers
   46% of the time in FlipFlop (`llm-failure-modes.md` F6), and the fresh-sample noise (F9, F10).
4. **Stop-hook symmetry (closes G7 in `close-assertion.md` §5).** A new arm in `hooks/completion-assert.sh`: when a
   valid certificate exists and the reply opens with a not-done marker ("No", "not yet", "one more", "one check
   remains"), the reply must cite a `CH-<n>` whose triage is `escape`. Otherwise the arm blocks with *"regenerated
   audit: answer from the certificate, or file a challenge"*. Today every arm guards against a false done, and
   none against an unbounded "not done" (`close-assertion.md` §1.6). **This changes an operator-stated practice:**
   D4's "the answer is always yes" (`hooks/completion-assert.sh:1278`) and F1's "nothing left on the table"
   (`CLAUDE.global.md:616-617`). So it ships carrying
   `Replaces: D4/F1 drive-every-named-item, for certified research programs only — ruling pending`, and waits for
   the operator's ruling (§10.2). Until the ruling, the hook only injects the certificate, and the Stop arm runs in
   warn mode.
5. **Why re-asking no longer inflates error (the sequential-testing argument).** Asking "are we done?" repeatedly
   is a multiple test when each ask draws a fresh sample, which is Lewis et al.'s "sequential bias induced by
   multiple testing" (`stopping-rules.md` B3, D6). Here no ask draws a sample. Each ask reads one monotone counter,
   post-gate escapes per stratum, against one fixed threshold printed at signoff, n_pred95. A counter that only grows
   crosses a fixed threshold at some point in time if and only if its final value exceeds it. So checking it
   1 time or 1,000 times has the same error rate: ≤5% per stratum when calibrated. That is the anytime-valid property
   (Ramdas et al. 2023) in its simplest form, and it holds because the question is answered by a store, not by a
   model.
6. **Two verdicts at every close (closes C1).** `scripts/wrap-ledger.sh` gains a `GOAL` field:
   `CERT=valid|stale|absent|failed` plus the tier. Line 1 keeps the session rung. `Good to close:` covers the
   session, and a separate `Goal:` line relays the certificate. The absent-DoD ✅ at `scripts/wrap-ledger.sh:2286-2288`
   becomes "unknown", matching `CLAUDE.global.slim.md:259`.

---

## 8. A hole found after the gate: triage without reopening everything

### 8.1 Challenge triage (`cc-research challenge`; typed, and checked against the ledger first)

| Triage | Test | Action | Scored as a miss? |
|---|---|---|---|
| refuted | the verifier cannot reproduce it from the primary source | log it | no |
| relabel (C1) | the locus or claim matches a `holes.jsonl` or reconciliation row | answer with that row's disposition | no |
| immaterial | fails §3.3 | log it, `apply-at-build` | no |
| frame-expansion (C2n) | needs a requirement absent from the ratified frame and supplied now | `cc-research amend` with `Scope (grown, cause=operator)`; a **mini-program** for the new axis with its own mini-certificate (census, premise and contact passes on that axis only, plus rounds on the affected CU) | no |
| contact-residual (C9) | the property lives in production, a tenant or time, and is declared in `contact.jsonl` | route it to that item's owner and date | no |
| drift (C10) | a `facts.jsonl` recheck now differs, or trunk moved | re-run the rechecks; re-verify only the dependents in `facts.dependents` / `premises.supports`; re-certify the affected CU if a DR or AM verdict changes | no (dated) |
| **escape** | an in-frame material hole the certificate should have caught (C3–C8, C11) | §8.2 | **yes** |

### 8.2 Escape handling: a local fix, a stratum-local delta round, and the escape counted against the bound

1. Fix by integrating the change. Then run the consistency reader on the edited spans and their dependents.
2. Run **one delta round**: T blind panels on the edited CU plus the stratum's lens only, with a shadow seed in each
   edited span, as for any fix (§5.3). If it finds a MATERIAL hole, that hole is fixed and one more delta round
   runs. The cap is 2 delta rounds per escape. Anything the second one finds is itself filed as an escape, and a
   stratum with that many escapes is heading for §8.3's calibration test anyway.
3. Increment the stratum's escape count on the certificate. The certificate is re-issued as v(n+1), names the
   escape, and prints the count beside the stratum's n_pred95. Every escape is shown (§1.3).
4. Add the escape's mechanism to the escape library (a hard-tail seed for every future program) and write one line
   in `docs/lessons/` saying which lens missed it.

### 8.3 When the certificate itself is refuted (a take-back)

A stratum's calibration broke when its escape count exceeds its `n_pred95`. The cause is a seed-realism failure or
an unmodeled blind spot. Because the count only grows and the threshold is fixed at signoff, this test can be read
at any time and as often as anyone likes, without inflating its error rate (§7.5).

The same verdict applies in two other cases:
- a post-gate Fable sweep reports more NEW material holes than the stratum's bound;
- a structural gate row (S1–S10) is shown to have been false when certified, for example a census file that was
  missing a member which existed.

That stratum, and only that stratum, is re-certified from its census and premise registers upward, with a new
R_max from its own forecast. This is a **take-back**, and it is reported as one: on the certificate, in
`research-calibration.jsonl`, and as a `docs/lessons/` entry naming the lens or seed class that failed.

### 8.4 Why this does not reopen everything

The certificate is per stratum and per certification unit (CU). Large plans are partitioned into CUs of ≤1,500
lines. Each seam between sibling CUs or plans is its own "seam CU", because seams drop axes: LIMIT_DETECT dropped
the request writer while LR100P narrowed it out (`plan-lifecycle.md` §5 item 6). An escape has a locus, a
locus has a CU and a stratum, and the reopen is scoped to those.

---

## 9. Time and effort budget: making the timeline predictable

### 9.1 The unit of effort is the panel-run, not the day

A panel-run is one blind panel with a fixed brief, fixed effort and a token cap. Wood (Tandem 1996) found
execution effort to be the only reliable time base for reliability growth. Calendar time and test counts "did not
provide credible results" (`unseen-estimation.md` §2.7). Round 0 measures, per family: wall seconds, tokens, and
weekly-quota percentage per panel-run (`claude-accounts` before and after). Every later budget is priced in
those units.

### 9.2 The forecast (computed at round 1, updated every round, plotted as a burndown)

- **N̂₀** = jackknife 2 of round 1 as the point estimate, with Chao2 as the lower bound (Briand 2000). In
  simulation with the diversified eight, JK2 had median 59.4 [P10 50.6, P90 68.7] against a true detectable 57.
  Chao2 read low at 52.4 [46.8, 59.6], and Mills' seed estimate read 57.6 [50.9, 64.7] (`stopping_model.out` §3).
- **R̂** = the fraction of carried seeds caught in round 1. It is mapped to the model's per-panel detection level
  through a calibration table (`forecast_check.out` line 2). **b̂** starts from a prior of 0.1 and is measured from
  round 2.
- **`cc-research forecast` simulates the program forward** from (N̂₀, R̂, b̂): 150 programs, printing p50/p90 rounds
  and panel-runs. The simulation is `cert_sim.py` with the measured inputs. How good that is, measured
  (`forecast_check.out`):
  - With the model right, the actual round count fell at or under the forecast p90 in **91%** of programs. The
    median error was 0, and the P10/P90 errors were −2/+3 rounds.
  - Under misspecification (heavier heterogeneity, b 2.5× the prior), it did so in **66%**, with a median error of +2.
  - **p90 + 4 covered 99% and 93%.** Hence R_max = min(p90 + 4, R_abs).
  - It is re-forecast after every round from the observed counts, and plotted as a burndown.
- **The closed form is dropped.** Revision 1's ⌈ln(N̂₀/μ)/ln(1/q̂)⌉ + K held in only 17% (model right) and 5%
  (misspecified) of programs. It ignores that survivors get harder every round.
- **Wall time per round** = panel wave (8 concurrent, measured d̂) + adjudication and verification + fix,
  integrate and consistency read. Illustrative: 1 h + 1–1.5 h + 1–2 h, about 3–4.5 h. A dry round has no fix step,
  about 2–2.5 h. Round 0 replaces these.
- **Divergence diagnosis** (`cc-research diagnose`, run every round from round 3). The model's contraction per
  round is q = 1 − R(1 − b). Convergence needs b < 1; revision 1's "b < 0.5·R" was wrong. What the simulation shows
  (`stopping_model.out` §4–5):
  - **b = 0.1 converges.** The found-per-round series runs 47, 9, 3, 1.4, 0.7, and the stop comes at 9/12 rounds.
  - **b = 0.6 converges slowly.** 47, 27, 17, 11, and 15/21 rounds.
  - **b = 0.9** fails to stop within 40 rounds 29% of the time, and **b = 1.0** 89% of the time.
  - **b = 1.2 diverges.** 47, 49, 53, 59: the 23/21/24/28 critic loop (`taxonomy.md` §3).

  So at **b̂ ≥ 0.5**, or a found-count ratio ≥ 0.7 over two consecutive rounds while the counts are still ≥ 5 (at
  small counts the ratio is noise), the next step between rounds is to
  **delete machinery or restructure the offending CU** (`/ground-up` on it). It is never another round of the same.
  Those rounds are spent from the same R_max. Two other diagnoses:
  - **R̂ collapsing** means a panel or family defect, handled by the preflight.
  - **N̂₀ well above the discovery phase's expectation** means structural gates passed too early. That stratum gets
    **one** return to P1–P3, charged against R_abs.

  A panel with a quota ("find 2-3 gaps") never produces a dry round, so under a quota the stop rule is unreachable
  by construction. Removing quotas (§4.5) is a precondition, not a refinement.

### 9.3 The price curve: what tighter certification costs

From `tier_curve.out` §A: 1,000 simulated programs per row, b = 0.1, 5% of holes universally blind, 100 carried
seeds, panels from 4 families (T = 16 is the same four families with four strategies each). N₀ is the number of
material holes still present at the first freeze, after the structural passes. Round 0 and W0 replace these
illustrative numbers with measured ones.

| Tier | Stop rule | Rounds p50/p90 (N₀ = 60) | Panel-runs p50/p90 (N₀ = 60) | Desk-detectable material left, mean · P(≥1), N₀ = 60 | Same, N₀ = 20 | Stated bound, median (N₀ = 60) |
|---|---|---|---|---|---|---|
| decision | K = 2, T = 8 | 7 / 10 | 56 / 80 | 0.95 · 0.57 | 0.52 · 0.38 | 4 |
| **build (default)** | K = 3, T = 8 | 9 / 12 | 72 / 96 | 0.62 · 0.46 | 0.33 · 0.27 | 3 |
| deep | K = 4, T = 8 | 10 / 14 | 80 / 112 | 0.49 · 0.37 | 0.23 · 0.20 | 3 |
| wide | K = 2, T = 16 | 6 / 7 | 96 / 112 | 0.41 · 0.33 | 0.20 · 0.18 | 2 |
| **max** | K = 3, T = 16 | 7 / 9 | 112 / 144 | 0.25 · 0.21 | 0.13 · 0.12 | 2 |
| beyond max | K = 4, T = 16 | 8 / 11 | 128 / 176 | 0.19 · 0.17 | 0.09 · 0.09 | 2 |

What the table says, and what the operator ratifies at intake:
- **This is the operator's "100× effort for the last 1%", with prices.** Going from build to max costs about 1.5×
  the panel-runs and cuts the expected residual about 2.5×. Beyond max, each further halving costs more than the one
  before. It stays finite, and it is bought knowingly, once.
- **Width beats depth.**
  - At the same p90 of 112 panel-runs, "wide" (K = 2, T = 16) leaves less than "deep" (K = 4, T = 8): 0.41
    against 0.49.
  - It also takes about 40% fewer rounds (6/7 against 10/14), because the extra panels run concurrently while the
    extra dry rounds run in sequence.
  - So a surplus budget buys families and panels first, and dry rounds second.
- **Structural passes are the cheapest assurance.** Every hole P1–P3 removes before the freeze is one the
  certificate need not find. At the build tier, N₀ = 20 leaves 0.33 where N₀ = 60 leaves 0.62. This is the
  statistical reason the frame, census, premise and contact passes come first (§0 item 2).
- **Seeds buy the statement, not the residual.** At the build tier and N₀ = 60, the stated bound's median is 3
  whether s = 60 or 300, and the true P(≥1) stays 0.43–0.47 (`tier_curve.out` §B). The default s₀ is therefore 60.

The universally blind mass is invisible to every tier. It is 5% of holes in the model, about 3.3 left
(`stopping_model.out` §2). That mass is what the contact wave (C9) and the Fable sweep exist for. It is declared on
the certificate and never folded into the estimate. In the corpus, its real-world counterpart is the 30 C9 holes
plus 4 unforeseeable drifts (`taxonomy.md` §2). 24 of those 30 are probe-able locally, which is why the contact wave
(P3) runs before the freeze instead of being left to panels.

### 9.4 Whole-program budget template (a weeks-long greenfield)

| Phase | Budget (illustrative) | Operator time |
|---|---|---|
| P0 intake and ratification | 1 day | about 1 h interview + ratification |
| P1 prior art and census | 1–2 days | — |
| P2 discovery | sum of DR timeboxes (typically 5–10 days), VOI-ordered | rulings on packets below 90% |
| P3 contact wave | 1–3 days | only irreducible items, filed |
| P4 round 1 + forecast | 0.5 day | forecast presented; the tier is re-confirmed only if the p90 date passes the deadline |
| P5 certification | forecast: at the build tier, 9/12 rounds (p50/p90), about 1.3–1.8 days if rounds run back to back in dispatched sessions (≈6 fix rounds × 4 h + 3 dry rounds × 2.5 h at p50), or 4–5.5 working days if only daytime | none |
| P6 certificate + Fable sweep | 0.5 day | one `cc-signoff` of the certificate |
| **Total** | **about 2.5–4 weeks; the P5 share has a computed p90 from round 1 and a hard ceiling at R_abs** | about 3–4 h across the program |

**The finite guarantee, printed at ratification.** `Ceiling = Σ(P0–P3 timeboxes) × 1.5 + R_abs × (round time) + P6`.
With the defaults that is (1 + 2 + 10 + 3) × 1.5 = 24 days for P0–P3, plus 16 rounds × 4 h (2.7 days back to back,
or 8 days if rounds run only in daytime), plus 0.5 day: about **27 days**, or about **32.5 working days**. Only an explicit
operator act can exceed it: `extend` (§6.3) or an amendment (§3.6). The 1.5 factor shrinks as
`research-calibration.jsonl` accumulates programs (reference-class forecasting).

Calendar time in the corpus was dominated by dormancy and operator gates, not research. sevenrooms-bridge was idle
33 of 35 days (`greenfield-cases.md` mechanism 9). So every operator gate in `frame.json` carries a due date, and
`cc-research forecast` prints them as blocking days rather than folding them into "research".

---

## 10. Mapping to this environment: what to build

### 10.1 New components

| # | Component | Where | Notes |
|---|---|---|---|
| B1 | `cc-research` CLI (Python) | `bin/cc-research` | verbs: `init` (scaffold, topic lock, `programs.json` entry), `index` (search docs/research, docs/plans, transcripts, `msg`, `cc-memory-search`), `freeze`, `seed` (author request, pre-screen, discriminator test, encrypted apply/match, orphan censoring), `panel run` (courier launch with the program's Fable ledger), `ingest`, `estimate`, `gate`, `forecast` (the `cert_sim.py` model, fitted), `diagnose`, `cert --render`, `reconcile`, `trace --check`, `challenge`, `amend`, `extend`, `verdict`. The stores are in §5. **Each estimator and gate has a planted-input test that must go red** (the C5 prevention step, `taxonomy.md` §C5). The estimator tests reuse `/tmp/rescomp/design/cert_sim.py` fixtures, copied into `tests/fixtures/research-cert/` because /tmp is reaped |
| B2 | Certification-round Workflow script | `workflows/cert-round.js` | stage A: `parallel` of T courier `agent()` slots with `{label, phase, model, effort}` and a schema'd return. Each courier launches one CLI panel (B3). Stage B: `pipeline` of dedup, then parallel verifiers, then materiality raters 2 and 3. The **snapshot sha and seeded-bundle hash go in every prompt**, because the resume cache key is (prompt, opts) with no tree term, so a resumed run would otherwise serve a stale report (`docs/research/workflows-vs-teams-2026-08-20.md:364-367`). The orchestrator is a `vm.createContext` sandbox with no `fs` (`…:185`), so agents write to disk and return paths and hashes, and the round session runs `cc-research ingest`. Concurrency is 8 per workflow run (`docs/research/orchestration-units-2026-08-19.md:118-120`); T = 16 means two concurrent runs |
| B3 | Courier brief + preflight | `skills/research-certification/courier.md` | Binaries by absolute path. `codex exec -s read-only`; `gemini -p … --approval-mode plan`; `/opt/homebrew/bin/claude -p --setting-sources local --model <opus\|fable>`. cwd = the sanitized worktree. Preflight: `codex login status`, a one-token gemini call, a `--setting-sources local` NONE-probe with a positive control (as in the header), and a record of every binary's version. The post-round integrity grep voids a contaminated panel |
| B7 | Operator-signoff library | `scripts/lib/operator-signoff.py` + a `research:` namespace in `bin/cc-signoff` | factor out cc-signoff's three arms: ancestry refusal, content pin, and VOID rendering (`bin/cc-signoff:1-30`). Then accept `research:<program>/<frame\|cert>`, backed by `~/.claude/autonomy/research/<program>/signoff.json`, not the customer mission board. Ratification (§3.6) and certificate signoff use it. `cc-decide` is not used for either, because it has no agent guard |
| B8 | Calibration store | `docs/research/research-calibration.jsonl` + `cc-research calib` | one row per program (§5.1). It feeds the forecast priors and the "uncalibrated" / measured-hold-rate line on every certificate |
| B4 | Skill + command | `skills/research-certification/SKILL.md`, `commands/research-program.md` | phases, briefs (panel, seed author, census critic, adjudicator, verifier, consistency reader), the rubric, and the "zero is a valid answer" clauses |
| B5 | Re-ask hook | `hooks/research-cert-inject.sh` (UserPromptSubmit) | §7.1 |
| B6 | Escape library | `docs/research/escape-library/escapes.jsonl` | seeded from `/tmp/rescomp/taxonomy_holes.py` (129 desk-findable rows plus receipts; persist it before /tmp is reaped) |

### 10.2 Edits to existing machinery (each removes a mechanism the audits found)

| File:line | Today | Change |
|---|---|---|
| `skills/research-subagents/SKILL.md:796-803`, `:819-828` | "List 3 with reasons"; promote anything "not obviously relevant" unless the user excluded it | zero-allowed; promote only if the item passes §3.3 materiality against the program's DR/AM; otherwise log it as immaterial |
| `skills/research-subagents/SKILL.md:944-948` | a re-check framing means apply the rule "more aggressively" | when a certificate exists, a re-check routes to `cc-research challenge` |
| `skills/research-subagents/SKILL.md:766-779` (OASIS 2–3) | an adversarial null that is never met; an uncomputed `c·N^α` curve | when a program is active, point to `cc-research estimate`. The `c·N^α` fit has no asymptote, so it can never state a residual (`unseen-estimation.md` §6) |
| `agents/deep-research.md:187` | "Find 2-3 gaps" | "List gaps that pass the locus and decision-change test; zero is expected" |
| `agents/research-decomposition-critic.md:37-38` | "name 1-3 … MISSING" | same zero-allowed form, with a locus required |
| `hooks/dod-persist.sh:76-96` | carries the superlative verbatim; `Scope (grown)` has no cause | superlative lint (port `skills/ground-up/SKILL.md:14-18`) points to a certificate DoD: `Scope (frozen): research certificate tier <X> for <program> by <date>`. Add `cause=` to grown lines |
| `scripts/wrap-ledger.sh:616-623`, `:2286-2288` | REMAINDER counts `- [ ]` boxes; absent DoD reads ✅ | add the `GOAL`/`CERT` field; absent DoD becomes unknown |
| `hooks/completion-assert.sh` (new arm beside D3/D4, `:1276-1278`) | only guards against a false done; D4 says "the answer is always yes" | §7.4 anti-regeneration arm, warn-only until the operator rules. **Operator practice changed:** `Replaces: D4 drive-every-named-item, for certified research programs only — ruling pending` |
| `CLAUDE.global.md:616-619` (F1/F2) | F1 passes every refinement under "nothing left on the table" | after a certificate, F1 net-positive means §3.3 MATERIAL, and REFINEMENT goes to `apply-at-build`. **Operator practice changed:** `Replaces: F1 "nothing left on the table" as the post-certificate net-positive test — ruling pending`. The ruling is asked as one `cc-decide` class-C packet with conviction and receipt, together with the D4 row. Both edits ship only after it is actioned |
| `commands/are-we-done.md:52-57,70-72` | "exhaustively" is a git property | add the goal question: relay `cc-research cert --render` |
| `skills/research-subagents/SKILL.md:756-782` (OASIS) | the program-level stop rule is prose, with no computed residual | when a research program is registered, OASIS governs only discovery-wave spawning. The completeness claim is the certificate |

### 10.3 Existing tools, used as they are

- `cc-decide`, for priced choices *inside* the frame:
  - the tier choice with its forecast;
  - `extend` purchases (class C);
  - "below tier" certificates (class B, default "accept as issued" at 24 h);
  - DR rows that stay below 90% after their timebox (class C, with conviction and receipt);
  - class-A records of decisions the agent made.

  It is **not** used for frame ratification or certificate signoff. Those go through B7, because `cc-decide` has no
  agent guard.
- `cc-backlog`: irreducible contact items (`--why-not-now "not-yet-true: …" --falsifier`) and `apply-at-build`
  refinements (`--dod-ref` to the plan item).
- `frontier-run` / `frontier-derivation`: the post-gate Fable sweep.
- `/ground-up`: prescribed on a divergence diagnosis.
- `msg`, transcripts and `cc-memory-search`: intake mining and `index`.

### 10.4 Build waves (plan Phase 0 locus: S = dispatched session by default)

| Wave | Locus | Deliverable | Exit criterion |
|---|---|---|---|
| **W0 measure-first backtest** | S | Run the protocol by hand (scripts plus a Workflow) on **historical snapshots with known later holes**. Two candidates: the VoiceInk latency plan at its "It's now done" snapshot (`989f6dbf` 2026-09-28T05:21:27Z; 20 defects and the upstream axis surfaced after it), and the VoiceInk quota plan at sign-off (`ba08cab8` 19:25Z; D22–D24 surfaced later). Measure: recall of the known later holes, the family × family co-detection matrix, the round-1 realism statistic (seeds vs real), the pre-screen's catch rate, panel-run cost in weekly-quota percent, whether the Fable spawn gate counts workflow agents, and **the hold rate of the stated bound**, meaning the known later holes against n_pred95 at the snapshot | a report with measured R̂ per family, the correlation matrix, the hold rate, and the fraction of known later holes the protocol caught **before** the snapshot's "done". **This is the positive control for the whole design; nothing else ships before it**, and certificates print "uncalibrated" until it lands |
| W1 | S | `cc-research` stores, estimators, gate and forecast, with tests (each gate red on a planted input) | test suite green; each estimator matches `cert_sim.py` on fixture matrices, and the forecast reproduces `forecast_check.out` within ±1 round at p50 |
| W2 | S | `cert-round.js`, courier, briefs, sanitized-worktree builder, seed vault | one live round on a toy program, with every S8 integrity check passing |
| W3 | S | hook and skill edits (§10.2) and the re-ask hook | bats: a completeness prompt injects the certificate; a "No, one more" reply without a CH id is blocked |
| W4 | S | escape library, seed author, and realism test | discriminator ≤70% on 20 pairs |
| W5 | S (the operator's next greenfield) | the full P0–P7 program | certificate issued; post-gate escapes tracked for 30 days |

The research lead fires a dispatched session per round with
`--goal 'round k matrix ingested and cc-research gate --round k printed its verdict (continue, stop=dry or stop=cap) — proven by that command's output; do not edit the plan during the round'`.
The goal ends at the agent's reach. It never contains an operator-only act such as signoff. A goal with such a
conjunct can never clear (`docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md`), and the
judges flagged exactly that in phase goals.

---

## 11. Every taxonomy class: mechanism, gate, residual

| Class (n; desk-findable) | Mechanism in this design | Gate | What stays residual, declared |
|---|---|---|---|
| C1 claim frame narrower (23; 23) | The certificate is the goal verdict. `reconcile` maps every item in every store. Re-asks read the ledger, and known items triage as relabel | S10; §7.5 | none expected; a relabel is not a miss |
| C2 operator intent (12; 2) | intake interview + mining (§3.1); the frame signed by the operator through B7 (content-pinned, so no agent can edit it silently afterwards); `amend` with cause | S1 | **C2n (6/200 = 3%): genuinely new requirements.** Not preventable. Logged as frame expansion with a mini-program, shown on the certificate under its own class, and never scored as an escape |
| C3 unverified premise (29; 26) | premise register at primary tier; panel premise lens; C3 seeds measure panel recall on exactly this | S3; Q2 per stratum FACT | secondary premises with VOI = 0, stated |
| C4 population never enumerated (32; 29) | census registers with search commands + a blind non-Anthropic census critic, run once; C4 seeds; "use what exists" and "do nothing" are mandatory options | S2; Q2 per stratum COVERAGE; Q4 | members no search reaches: inside the stated bound, or a named weak lens if the C4 escape seeds stay below 0.5 recall |
| C5 instrument could not discriminate (29; 13 desk + 15 build) | every AM check red on a planted defect (S4); re-execute, never recall; contact wave for harness–production parity | S4, S5; C5 seeds | build-only instrument defects move to the contact register |
| C6 research did not reach the artifact (12; 12) | index search at start; `trace --check`; tracked stores; topic lock | S6 | none expected |
| C7 self-created by edits (10; 8) | integrate, don't append; consistency read on the certified sha; b̂ and the found-per-round series measured each round; **shadow seeds** (one per fix, carried) state the fix-born residual; at b̂ ≥ 0.5, delete or restructure (§9.2); refinements are not integrated during certification, so they cannot spawn fix-born holes | S7; Q1; Q3 | fix-born holes inside the shadow cohort's stated bound |
| C8 review late or unsaturated (8; 8) | certification **is** the saturation measure, and it runs before any claim; dead, partial and voided slots are re-run (capped at 2, then the next family); no build fires before the certificate | S8; Q1 | none |
| C9 contact-only (30; 1 desk, 29 probe) | contact wave inside research (24 of 30 were probe-able locally); every handed command run by the agent | S5 | **6/30: production, tenant or elapsed time** (holes 16, 34, 95, 121, 134, 170). Declared with owner, date and falsifier as budgeted post-build verification |
| C10 reality moved (8; 3) | dated facts with recheck commands; trunk sha on the certificate; rechecks at the gate and at build start; probes forbidden from mutating live subjects | S9; P7 | **4/8 unforeseeable drift.** Handled by drift triage, re-validating dependents only |
| C11 criterion not operationalized (7; 4) | superlative lint; measured ceilings; pre-registered thresholds and negative branch; positive references; the operator's eye as a dated gate; perfection holds expire | S1 | taste verdicts are the operator's by design (a dated gate, not research) |

Coverage claim: every class has a mechanism and a gate row. The declared residual is C2n (6), irreducible C9 (6)
and unforeseeable C10 (4), or 16 of 200 (8%). This agrees with the taxonomy's own "10 unreachable + 6 new
requirements" (`taxonomy.md` §2, §5).

---

## 12. Rules this design depends on (each a measured failure if broken)

1. No quota on any gap-finding instrument. Zero is valid. A quota makes the dry-round stop unreachable.
2. Certification panels are blind: no prior findings, no seeds, no other panels, and the same frozen brief. They
   run as separate CLI processes, without the operator's resident instructions (`--setting-sources local` for
   Anthropic panels). A panel whose transcript touches the real program path or `git log` is voided.
3. Adaptive findings never enter the matrix.
4. Singletons are verified blind to their count and never culled as singletons.
5. The artifact is frozen during a round. MATERIAL fixes are integrated between rounds. REFINEMENTS are not
   integrated during certification; they are carried to build.
6. Seeds are carried from the first freeze, plus one shadow seed per fix. They are survivor-matched by a pre-screen,
   quote-anchored, censored when orphaned, and encrypted in a vault outside every repo.
7. At least 3 model families in every counted round. Agreement is never a stop signal.
8. Dead or partial slots are re-run (capped), never counted.
9. A dispute is MATERIAL-DISPUTED, never MATERIAL. False positives are what stretch the schedule.
10. Every loop has a cap fixed in advance: rounds (R_max ≤ R_abs), delta rounds (2 per escape), slot re-runs (2),
    realism rewrites (1), hard-tail detector attempts (1), returns to P1–P3 (1 per stratum).
11. The residual threshold chooses the tier at entry. The exit states the residual; it never gates on it.
12. Evidence lives in the project repo, never /tmp.
13. After the certificate, every completeness question is answered from the certificate. A new item is a challenge.
    Every escape is shown and counted against the bound printed at signoff.

---

## 13. Residual risk and open questions

- **Calibration on real panels is unmeasured.**
  - The model's assumptions are stated in the `cert_sim.py` docstring: logit-normal difficulty, persistent family
    and strategy blind spots, a Fable slot correlated with Opus at ρ = 0.6, and perfect verification apart from
    the modeled false-positive rate.
  - Real LLM families may be more correlated on design-hole finding than that. Kim et al. 2025 measured 60%
    same-wrong-answer agreement, but on multiple-choice questions, not plans.
  - W0 measures it, and certificates print "uncalibrated" until it does.
- **Seed realism is still the weakest link, but it is now bounded.**
  - `seed_realism.out` shows that the stated bound survives seeds up to 1 logit too easy (97.2% hold) and discovery
    survivors (95.5%). Only the point estimate runs low, by up to 35%.
  - Two mismatches are not modeled: seeds of the wrong **kind** (a class mix unlike the real holes), and a hole
    class seeds cannot represent at all (the universally blind mass).
  - The per-class escape seeds (Q4) and W0 are the only checks on those.
- **Pre-screen strength is a guess.** Survivor-matched seeding works in simulation when the pre-screen filters like
  discovery did (flag rate 4.4–4.8%, hold rate 98.2%). In practice, discovery's strength is known only roughly,
  from its find log. W0 records the pre-screen's catch rate beside the realism statistic, so the matching can be
  tuned.
- **Seed density.** 60 mutations in a plan of 1,500–3,000 lines is one per 25–50 lines. Whether that distracts
  panels from real holes is unmeasured. W0 compares panel yield on seeded and unseeded copies.
- **Cost.** 72/96 panel-runs (p50/p90) at the build tier, plus adjudication and couriers, is a real draw on weekly
  quota. W0 prices it in quota percent, and `extend` quotes use those prices.
- **Universal blind spots** are unidentifiable from overlap (Link 2003). The certificate declares this mass and
  does not estimate it. The Fable sweep and the contact wave are partial detectors only.
- **Two operator rulings are pending.** They cover D4 and F1 for certified programs (§10.2). Until they are given,
  the anti-regeneration Stop arm is warn-only. A re-ask then still receives the certificate injected, but a
  "no, one more" reply is not blocked.
- **Isolation limits.** `--setting-sources local` is probe-verified for Anthropic panels. Codex and gemini panels
  run as the same uid and could in principle read the vault's ciphertext or the real repo. The fresh-path bundle,
  the sanitized cwd, encryption and the post-round integrity grep make this detectable, not impossible.
- **Unverified here:** gemini auth under a real call; whether `frontier-spawn-gate.sh` counts workflow `agent()`
  calls with `model: fable` (irrelevant for CLI panels, which the program ledger counts); the Workflow
  schema'd-return syntax. All three are W0 checks.

---

## 14. Revision log

### Revision 2 (2026-09-30, after the 15:26 CDT reboot)

**Why a revision.** The reboot wiped /tmp. This file came back with the restored corpus, but its six simulation
scripts and outputs did not, so every number it cited had no receipt. They were rebuilt from scratch
(`cert_sim.py` plus six experiment scripts), and every cited number now comes from an `.out` beside this file. The
prior run's judge verdicts against revision 1 are in `SYNTHESIS.md` §12, rows "SS". They were treated as the
adversarial pass this design itself requires before a claim (C8), and each is closed below.

| Revision 1 said | Revision 2 says | Why (receipt) |
|---|---|---|
| Exit gate Q2: μ̂ ≤ tier target | residual **stated**, not gated; the threshold chooses the tier at entry | a μ̂ ≤ 0.5 gate ended in an operator decision in 53% of programs at N₀ = 60 (`tier_curve.out` §C); judge row "SS Q2 unreachable" |
| Ties between raters count as MATERIAL | MATERIAL-DISPUTED: named, fixed at build, and does not reset the dry count | false positives at 0.25/round take rounds from 9/12 to 10/17, and at 0.5 to 14/27 (`tier_curve.out` §D); judge row "tie→MATERIAL" |
| κ ≥ 0.7 gate; realism re-run until it passes; the hard-tail detector must catch its class | each reported, with one bounded attempt and a named fallback | judge row "κ gate; uncapped Q4/Q6" |
| R_max = forecast p90 + 2, closed-form forecast | R_max = min(simulated p90 + 4, R_abs) | closed form held in 5–17% of programs; p90 + 4 covered 99% and 93% under misspecification (`forecast_check.out`) |
| Convergence condition b̂ < 0.5·R̂ | b < 1; practical divergence step at b̂ ≥ 0.5 | `stopping_model.out` §4–5 |
| Fresh seeds at confirmation cover fix-born holes | shadow seeds, one per fix, carried | fresh seeds cover only the last fix's holes; shadow seeds age with all of them |
| Stated bound = Poisson 95% quantile at μ_up | posterior predictive: Beta(Jeffreys) × NegBin(F + 1) | μ_up fell to 77–87% hold at large s; the predictive held 97.8–100% (`carried_seeds.out`) |
| Q6: Mills ÷ JK2 in [0.5, 2] | Mann–Whitney capture-count test on round-1 data | the ratio flagged 0% in every mismatch scenario; the test flags 20–90%, with 4–6% false alarms (`seed_realism.out`) |
| (absent) seeds against discovery survivors | survivor-matched seeding by pre-screen | discovery survivors took hold to 95.5% with μ̂ 15% low; the pre-screen restores 98.2% (`seed_realism.out`) |
| Seed mechanics across edits unspecified | quote-anchored patches, re-applied per snapshot, orphans censored | judge row "carried-seed mechanics"; censoring widens without bias (`tier_curve.out` §E) |
| Escapes inside the bound are not take-backs | every escape shown and counted; take-back = calibration breach | judge row "SS redefines take-back" |
| Ratify through `cc-decide` | operator-only signoff (B7, from `cc-signoff`'s three arms) | `cc-decide` has no agent guard (grep, header); judge row "ratification forgeable" |
| Panels as Workflow agents sharing the operator's context | separate CLI processes; `--setting-sources local` for Anthropic; fresh-path bundle; encrypted vault; integrity grep | probe in header (NONE vs mission board); judge rows "contamination", "same-UID vault" |
| Fable cap = hook's per-session budget | program-level Fable ledger in `cc-research` | the hook is Agent-matcher only and not loaded under `--setting-sources local` (header) |
| D4/F1 edits presented as plain changes | flagged `Replaces: … — ruling pending`; the Stop arm is warn-only until ruled | judge row "F1/D4 not flagged as operator practice" |
| Concurrency cite `workflows-vs-teams-2026-08-20.md:104`; no-fs cite `:64` | `orchestration-units-2026-08-19.md:118-120`; `workflows-vs-teams-2026-08-20.md:185` | the old lines do not contain the claims (checked this session) |
| Build tier K = 3, T = 8: 64/88 runs, 0.52 left | K = 3, T = 8: 72/96 runs, 0.62 left (N₀ = 60); 56/72 and 0.33 (N₀ = 20) | rebuilt model (`tier_curve.out` §A); the old outputs no longer exist, so they cannot be compared line by line |

**Kept unchanged from revision 1:** the phase structure; the intake interview and superlative translation; the
materiality rubric (a)–(d); the census, premise, contact, trace and reconciliation registers; strata; escape seeds
as a hard-tail gate, never a denominator; the no-quota brief; the re-ask hook and the two-verdict close; per-CU
scoping of reopens; the W0-first build order.
