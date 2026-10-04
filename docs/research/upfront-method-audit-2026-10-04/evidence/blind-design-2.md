# Census, Contact, Saturate, Certify: a method for near-zero post-signoff surprises

## 1. Why the "one more thing" loop exists

The loop has three causes; a method that fixes only one keeps looping.

1. **No denominator.** "Complete" was asserted against an open space. Any later search of an open space finds something, so "are we 100%?" is a productive instrument and the agent, correctly, searches again. The fix is to close the space before building: enumerate what will be checked, so "complete" means "every enumerated cell is resolved", and discovery of a cell *outside* the enumeration becomes a named, countable event rather than a feeling.
2. **No residual estimate.** The agent reported a vibe, not a number. Inspection research solved this in 1992: run independent reviewers, measure how much they overlap, estimate how many defects remain (capture-recapture, Eick et al. ICSE 1992; Briand et al. on which estimators to trust and how many inspectors they need). The stop rule becomes statistical.
3. **Search on demand instead of search to exhaustion.** The historical "one more thing" was found by asking the question *after* the claim. The method must run that exact question, adversarially, many times, *before* the claim, until it stops producing. Then the operator's question can only relay.

A fourth fact shapes the allocation: of 200 historical holes, 2/3 were desk-findable, 15% needed contact with the real environment, 5% were unreachable up front, 3% were new intent. More desk research alone caps at ~67% of the mass. Each stratum needs its own instrument: desk → saturation; contact → a contact phase; unreachable → watchers that certify *detection*; intent → a signed frame that turns post-signoff intent into change, not failure.

## 2. The ledger: the only memory

Everything below writes to one on-disk, append-only ledger (JSONL journal plus a derived view) at the project root. It holds the frame (versioned), the lattice of cells, findings, probes (repro artifacts), decisions, pass records, estimator outputs, and certificates. Sessions are stateless workers over it.

- A cell flips to VERIFIED only with an artifact path and a run receipt (command plus output hash). Prose cannot flip a cell.
- The answer to "are we done?" is *computed* from the ledger (a `certify` command renders it), never narrated.
- Every session boots with a drift check: re-run the verification suite; any stamp that no longer passes reverts its cell to UNRESOLVED. Certificates are per-sha and per-environment snapshot, and rot with time.
- Hooks enforce it mechanically: (a) a reply containing a completion claim is blocked unless a certificate exists for HEAD; (b) a tracked write during a saturation freeze is blocked; (c) a code edit in the fix phase must cite a finding id whose probe reproduced; (d) an "are we done" prompt injects the rendered ledger into context before the model answers.

## 3. Phase 0: Frame (operator intent, captured once, in one batch)

Intent is the one stratum no agent spend reaches, so it is elicited with structured techniques, early, in one batch rather than dribbled:

1. Goals and non-goals, each a sentence the operator signs.
2. 5-15 concrete scenarios written as examples with expected outcomes (given/when/then), including the operator's own first hour with the thing.
3. Premortem (Klein): "It is a month after signoff and this turned out not to be what you wanted. Why?" Each answer becomes a cell or a non-goal.
4. Adjacent-value list: the agent enumerates everything nearby it would otherwise "discover" later (the 100th-percentile instinct) and the operator rules each IN or OUT now. This is the explicit home for "nothing left on the table", so it cannot leak into post-signoff surprises.
5. The materiality rubric is signed with the frame: M0 (wrong output, data loss, security, a signed scenario fails), M1 (in-frame defect), M2 (cosmetic or quality; operator decides), M3 (out of frame → change request). "Material" is never relitigated per finding.
6. Exclusions: what will be certified as unreachable (production-only, calendar time, operator taste) and the watcher that stands in for each.

Then a **walking skeleton** (a thin end-to-end slice, 10-20% of the build) goes in front of the operator with a scripted walkthrough. Seeing the artifact surfaces intent that interviews do not; this is where most of the 3% is recovered cheaply. Frame F1 is signed after the walkthrough. Later intent is F2, F3…: a change, re-certified on its delta, not a hole in F1.

Decisions during build follow one rule: reversible decisions proceed on the agent's default with a logged conviction; irreversible or value forks are batched into one ask per milestone with options and numbers, never one per turn.

## 4. Phase 1: Census (build the denominator)

The lattice is built before significant code is written and grows only by explicit events.

- **Rows**: components (from the design), interfaces (every external thing: API, OS, browser, DB, service, credential, hardware, deploy target, scheduler), scenarios (from the frame), and time-dependent behaviours (expiry, rotation, DST, day-30, day-365).
- **Columns (concerns)**: correctness; input domain and edges; failure modes (FMEA verbs: absent, late, slow, duplicate, wrong, partial, reordered); concurrency; security; performance and cost; data and migration; deploy and rollback; observability; docs and operability; UX and accessibility; licensing; upgrade and dependency drift.
- **Seed from history**: every one of the 200 historical holes is mapped to a cell. A hole that fits no cell adds a dimension. The lattice is thereby calibrated to this operator's actual blind spots, not a generic checklist.

Each cell has one state: UNRESOLVED, VERIFIED(artifact), N/A(reason), CONTACT-PENDING, UNREACHABLE(watcher id), DEFERRED(decision id). Closed-sense completeness is "zero UNRESOLVED and zero CONTACT-PENDING". The new-cell discovery rate during later phases is the method's own health metric: if saturation passes keep adding cells, the census was shallow and is regenerated before continuing.

## 5. Phase 2: Build to evidence

- Every cell's verification is an artifact: a test, a property-based test, a contract check, a probe script, a proof sketch, or a measured run. A research unit's deliverable is a cell flip or a decision row, never prose; research that ends without a ledger write is lost by rule.
- Tests are validated by mutation testing: a suite that kills few mutants is theater and its cells revert to UNRESOLVED. Property tests and fuzzers run on a budget that grows with calendar time; they have their own Good–Turing saturation curve (probability of a new failure class ≈ f1/n).
- Design by contract at every interface row; the contract is what a later blind reviewer checks in both directions (spec→code and code→spec).
- Code is written by teammates in worktrees from briefs that name the cells they must flip. The lead never writes code; it owns the ledger and stays under 50% context.

## 6. Phase 3: Contact (the 15%)

Before freeze, every interface row is exercised against the real thing: the real API with sandbox credentials, the real deploy target, the real browser matrix, production-shaped data, the real scheduler and interpreter, the real OS version. Anything only the operator can provide (a credential, a tenant, a device) is filed as an operator step at census time, not discovered at the end. Time is made reachable by clock injection and soak runs over days, since the budget is unbounded. What remains genuinely unreachable (live production traffic, the operator's taste in use, calendar events) is marked UNREACHABLE with a **watcher**: a detector, an alert path, a rollback, and a bound on time-to-detect. The certificate claims detection, not absence, for those rows.

## 7. Phase 4: Freeze and saturate (the core)

At a frozen sha (tracked writes blocked by hook), independent blind review passes run until a statistical stop rule fires.

**Engineered independence.** Knight–Leveson showed independently written versions fail together far more than chance; the 2026 replication with coding agents found 3- and 5-version ensembles realise only ~0.44 of the gain independence would give, below 0.3 when built from one model. Same-model reviewers share blind spots, so passes are diversified on every axis available: vendor (Claude, Codex, Antigravity), model tier, **decomposition axis**, and artifact viewpoint. Each axis is a separate pass with its own prompt:

1. by component (each unit against its contract)
2. by concern (one column across all rows, e.g. every failure-mode verb against every component)
3. by scenario (execute each signed scenario against the running system and compare)
4. by interface (contract conformance against the real counterpart)
5. by time (day 1, 30, 365, DST, expiry, restart, upgrade)
6. by adversary (security)
7. by spec→code trace and separately code→spec trace (orphan requirements, orphan behaviour)
8. by history (the 200-hole classes as a checklist)
9. by first hour (a new operator's walkthrough with only the docs)
10. **self-ask**: a fresh context is told "the operator just asked: are we 100% complete, what did we forget?" and must produce findings. This is the historical loop, run deliberately, N times, before the claim.

Each pass is blind: it sees the frame, the artifact, the lattice's row and column names, and nothing from other passes. It returns findings as (cell id, claim, repro recipe, materiality class).

**Adjudication: no repro, no finding.** A separate adjudicator (a different model than the finder where possible) tries to reproduce every finding against the frozen sha as a failing probe (test, script, screenshot diff). Not reproduced → NOT-A-FINDING, logged against the finder config. Reproduced → a finding with its probe attached and materiality assigned from the signed rubric. This one gate keeps LLM false "material" findings from costing anything beyond adjudication time, and produces the data that steers spend: each reviewer config (vendor × axis × prompt) accumulates precision and unique-recall; configs below a precision floor or with zero unique material finds over three rounds are retired.

**Estimation.** With K passes, count material findings by how many passes found them: f1 (exactly one), f2 (exactly two). Chao1 gives a lower bound on undiscovered material findings, f1²/(2·f2) (f1(f1−1)/2 when f2 = 0); Good–Turing gives the probability that the next pass finds something new, ≈ f1/n. Briand's results say estimator accuracy depends strongly on inspector count, so the estimate counts only after at least 6 passes, and Chao1 is treated as a lower bound because detectability is heterogeneous.

**Stop rule** (all three must hold):
- Chao1 estimate of undiscovered material findings < 0.5, with upper 95% bound < 1;
- the last three passes, spanning at least two vendors and two axes, produced zero new material findings;
- the self-ask axis produced zero new material findings on its last two runs.

**Fix batch, then re-saturate.** All M0/M1 findings are fixed in one batch, each fix minimal and turning its own probe green, by teammates in worktrees; M2 goes to the operator as one list; M3 to the change queue. Fixing creates holes, so the estimate is void at the new sha: a new round runs, with passes prioritised on cells touched by the diff and their dependents, plus at least one full pass per vendor for non-local effects. The method measures **holes introduced per fix**; a subsystem where a round's fixes introduce as many as they close is a design failure and is rebuilt from its contract rather than patched again. Rounds continue until a round ends with zero M0/M1 and the stop rule holds.

## 8. Phase 5: Certificate

`certify` renders, from the ledger, for frame Fn at sha S:
- lattice totals: VERIFIED / N/A / UNREACHABLE (with watcher) / DEFERRED (with decision), and zero UNRESOLVED;
- saturation record: passes, vendors, axes, f1, f2, Chao1 estimate and bound, zero-yield streak, reviewer precision table;
- contact record: each interface row and the real counterpart it was exercised against;
- exclusions and watchers, each with its time-to-detect bound;
- what the certificate does not claim (section 13);
- method recall on the historical corpus (section 14).

Signoff is acceptance of the exclusions. A certificate without an exclusions section is invalid by rule, because unstated exclusions are exactly where "one more thing" lives.

## 9. Phase 6: After signoff

Watchers are live. Every post-signoff surprise is classified and fed back:
- in-lattice miss → a **saturation escape**, the method's defect: record which reviewer config would have caught it, add or sharpen an axis, re-run the backtest;
- outside the lattice → a new dimension; the lattice template changes for every future project;
- new intent → frame Fn+1, incremental re-certification of the delta;
- watcher catch → not a surprise; time-to-detect is measured against its bound.

The historical corpus grows, and the method's recall against it is the long-run quality metric.

## 10. Answering "are we done?"

The answer is computed, never searched for on demand.

- **Before certificate**: "No", plus the rendered ledger: N cells unresolved, M contact pending, open decisions, current round and estimate. The question triggers no new search; the ledger already knows what is open.
- **At certificate**: relay it verbatim: frame, sha, totals, residual estimate, exclusions, watchers. Then one sentence: "New intent becomes frame Fn+1; say it."
- **"Really? 100%?"**: the same certificate, plus a priced option: "another saturation round costs about X quota; the yield curve predicts about Y material findings; the rule says stop; your call." The loop ends as a decision with a number, not as a search.
- If the question ever *does* surface something new, that is logged as a saturation escape, not treated as normal diligence. An agent that finds "one more thing" on being asked has proved the pre-claim self-ask axis was under-run, and the method is amended before the next certificate.

Honesty rule: "100.00/100.00" is stated only in the closed sense (every enumerated cell resolved), always beside the open-sense estimate and the exclusions. Overclaiming is itself a cause of the loop.

## 11. Where unbounded budget goes, and where it stops helping or hurts

Budget is allocated first by hole mass, then by measured yield.

Productive, in order:
1. **Census depth and the historical backtest**: cheap and highest-leverage; a dimension missing from the lattice cannot be saturated.
2. **Contact**: sandbox tenants, real environments, soak runs over days. Expensive per hole, but the only instrument for the 15%.
3. **Saturation passes** until the stop rule: more vendors and more axes, not more copies of one reviewer; the 0.44 independence factor means a same-model repeat buys less than half what a new axis buys.
4. **Adjudication**: never wasted; it also calibrates reviewers.
5. **Long-running mechanical search**: mutation testing, fuzzing, property tests, clock-injected soak; these scale with wall time and have their own saturation curves.
6. **Ground-up rebuilds** where holes-introduced-per-fix is high.

Where more spend stops helping (measurable): past the stop rule, each additional LLM pass yields false positives at a near-constant rate (CR-Bench: review agents trade resolution against spurious findings, with low signal-to-noise when tuned to find everything) while confirmed yield is ~0. The ledger shows it as reviewer precision collapsing while unique-recall is zero.

Where more spend hurts:
- Acting on unreproduced or M2/M3 findings: every fix is a hole-introduction opportunity, so fixing non-material findings raises the residual.
- Reviewing reviews, or re-running the same vendor on the same axis: correlated, adds confidence without information.
- Growing a context past ~50-75%: reasoning degrades and claims turn narrative; recycle on the ledger instead.
- Re-opening the frame without the operator to chase adjacent value: scope drift disguised as diligence.
- Chasing the unreachable 5% with desk research: no instrument reaches it; the spend belongs in watchers.

The real bound is weekly quota across four accounts plus two external vendors, so rounds are scheduled against quota headroom and the lead keeps a yield-per-quota-point table per reviewer config.

## 12. Continuity across sessions, days and weeks

- The main session is a **role** (ledger owner, state-machine driver), not a context: it recycles whenever fill passes ~50%, and its successor boots from the ledger and the drift check. Nothing a successor needs lives in a transcript.
- Workers are dispatched by role with a brief naming the cells or pass id they own: census workers; build teammates in worktrees; contact sessions with operator-supplied credentials filed up front; saturation passes as a Dynamic Workflow (up to 16 concurrent: vendors × axes plus self-ask); an adjudication workflow; fix teammates. Each ends by writing its result into the ledger with artifacts; the lead accepts nothing without a run receipt.
- Handoff bridge = ledger path + sha + role + round number. Prose summaries are forbidden as state carriers.
- A worker's "found nothing" is accepted only with the enumerated scope it actually covered; a refused or timed-out pass is NO VERDICT, not a zero.
- Calendar time is used, not feared: soak runs, clock-injected day-30/day-365 runs, and repeated drift checks across days turn time-only holes into desk-findable ones.

## 13. What is impossible, stated plainly

- **Unknown dimensions.** Saturation works inside the lattice; a concern nobody enumerated is invisible to every pass. The backtest and the post-signoff feedback loop shrink this, never to zero.
- **Correlated blind spots.** All current LLM reviewers share priors; engineered diversity recovers less than half of the independence gain, which is why Chao1 is read as a lower bound. The only decorrelated reviewers are real contact and the operator's eye, so both are scheduled instruments.
- **The unreachable 5%**: live production, real calendar time, operator taste in use. Certifiable only as detection with a time bound, never as absence.
- **New intent (3%)**: not predictable; reducible by the frame, the premortem and the walking skeleton, then converted into change rather than failure.
- **World drift**: a certificate is true at sha S in environment E at time T. Dependency, API and OS updates invalidate it; the drift check reports this rather than pretending.
- **Statistical, not absolute**: the residual is an estimate with assumptions (closed population, equal-enough detectability, independence). "Zero" is a bound, not a proof.

The honest certificate therefore reads: zero known material holes in frame Fn at sha S; estimated undiscovered desk-findable material holes ≤ e; all interfaces contacted or watched; exclusions listed; method recall R on the historical corpus.

## 14. Validating the method itself

Before trusting it on a new project, run it blind against the 200 historical holes at their pre-fix artifacts: build the lattice, run the saturation axes, measure recall per stratum. Desk-findable recall below ~90% means the axes are wrong, not the budget. Test the estimator too: at each historical "claimed complete" point, did Chao1 predict the holes found afterwards? That calibration decides how far the stop-rule thresholds can be trusted, and is re-run as the corpus grows.

## Sources
- Capture-recapture for inspections and reinspection decisions: [Briand et al., Fraunhofer](https://publica.fraunhofer.de/handle/publica/289208), [A Comparison and Integration of Capture-Recapture Models (ISERN 98-11)](https://ehealthinformation.ca/web/default/files/wp-files/isern-98-11.pdf), [Quantitative Evaluation of Capture-Recapture Models (ISERN 97-22)](https://ehealthinformation.ca/web/default/files/wp-files/isern-97-22.pdf), [2001 comprehensive evaluation](https://www.ehealthinformation.ca/web/default/files/wp-files/2001-A-Comprehensive-Evaluation.pdf)
- Unseen-species residual risk: [Assurances in Software Testing: A Roadmap](https://arxiv.org/pdf/1807.10255), [Good-Turing sample coverage](https://metricgate.com/docs/sample-coverage-estimator-good-turing/), [Chao et al. 2017](https://www.uvm.edu/~ngotelli/manuscriptpdfs/Chao_et_al-2017-Ecology.pdf)
- Independence failure: [Knight & Leveson experiment](https://libraopen.lib.virginia.edu/public_view/jd472w463), [N-Version Programming with Coding Agents (2026)](https://arxiv.org/pdf/2606.20158), [Failure Independence in LLM-Generated Code (2026)](https://arxiv.org/pdf/2607.02808), [Spec, Code, Tests, One Author](https://tianpan.co/blog/2026-05-10-spec-code-tests-single-author-lost-test-independence)
- Review-agent signal-to-noise: [CR-Bench (ICLR 2026)](https://www.iclr.cc/virtual/2026/10017268), [arXiv 2603.11078](https://arxiv.org/abs/2603.11078)
KEY MECHANISMS: [{"name":"Closed denominator (the lattice)","what":"Before building, enumerate every cell that will be checked: components, interfaces, scenarios and time behaviours as rows; correctness, failure-mode verbs, security, data, deploy, observability, docs, UX, drift as columns. Seed it from the 200 historical holes; a hole that fits no cell adds a dimension. Each cell has one state and flips to VERIFIED only with an artifact and run receipt.","why_it_reduces_surprises":"It turns 'complete' from a narrative into 'zero UNRESOLVED cells', and makes discovery of anything outside the enumeration a countable method defect instead of a reason to search the open space again."},{"name":"Signed frame with adjacent-value list and premortem","what":"One-batch intent elicitation: goals/non-goals, example scenarios, a premortem, a list of every nearby thing the agent would otherwise 'discover' later ruled in or out by the operator, a signed materiality rubric, and signed exclusions; then a walking-skeleton walkthrough before frame F1 is signed.","why_it_reduces_surprises":"Most of the 3% new-intent holes surface when the operator sees an artifact, so they are recovered early; everything after signoff is classified as a frame change, not a hole, and 'material' is never relitigated."},{"name":"Contact phase with watchers","what":"Every interface row is exercised against the real counterpart before freeze; operator-only prerequisites (credentials, tenants) are filed at census time; time is reached by clock injection and multi-day soak; genuinely unreachable rows get a detector, alert, rollback and a time-to-detect bound.","why_it_reduces_surprises":"Targets the 15% that desk research cannot reach, and converts the unreachable 5% from surprises into bounded, pre-announced detections."},{"name":"Engineered-independence blind passes","what":"At a frozen sha, review passes run across vendors (Claude, Codex, Antigravity), model tiers and ten decomposition axes (component, concern, scenario, interface, time, adversary, spec/code traces both ways, history checklist, first hour, self-ask), each blind to the others.","why_it_reduces_surprises":"Same-model reviewers share blind spots (3-5 version ensembles realise ~0.44 of the independence gain, <0.3 same-model), so diversifying the axis of attack recovers coverage that repeating one reviewer cannot."},{"name":"No repro, no finding","what":"A separate adjudicator reproduces every finding against the frozen sha as a failing probe; unreproduced claims are logged as not-a-finding against the finder config, and each reviewer config accumulates precision and unique-recall, with low performers retired.","why_it_reduces_surprises":"Removes the cost of LLM false 'material' findings (which, when acted on, create new holes) and steers spend to the reviewers that actually find unique material defects."},{"name":"Capture-recapture stop rule","what":"Count material findings by how many passes found them (f1, f2); Chao1 estimates undiscovered holes, Good-Turing f1/n the chance the next pass finds something new. Stop only when the estimate is <0.5 with upper bound <1, the last three passes across two vendors and two axes found nothing new, and the self-ask axis is dry twice.","why_it_reduces_surprises":"Replaces 'I feel done' with a measured residual and a saturation signal, and tells the operator when more spend has stopped buying information."},{"name":"Batch fix, re-saturate per sha, measure holes-per-fix","what":"All M0/M1 findings are fixed in one minimal batch with their probes turned green; the estimate is voided at the new sha and a new round runs, prioritised on touched cells plus one full pass per vendor; a subsystem whose fixes introduce as many holes as they close is rebuilt from its contract.","why_it_reduces_surprises":"Fixing creates holes, so an estimate from before the fix is worthless; re-saturating per sha catches fix-induced holes, and the holes-per-fix metric detects when patching has become the problem."},{"name":"Pre-claim self-ask axis","what":"A fresh context is repeatedly told 'the operator just asked: are we 100% complete, what did we forget?' and must produce findings, adjudicated like any other pass; the certificate requires this axis to be dry.","why_it_reduces_surprises":"The historical loop was an instrument that worked; running it to exhaustion before the claim leaves the operator's post-claim question nothing to find."},{"name":"Ledger-computed answers and hook-enforced claims","what":"An append-only ledger is the only memory; sessions are stateless workers over it; hooks block a completion claim without a certificate for HEAD, block tracked writes during a freeze, require a reproduced finding id for any fix edit, and inject the rendered ledger on 'are we done?'. The answer is a relay of the certificate, with a priced option for another round.","why_it_reduces_surprises":"The model cannot narrate completion or answer from memory; continuity across recycles, handoffs and weeks is the ledger, not a transcript; and the 'really, 100%?' loop ends as a decision with a number instead of a fresh search."},{"name":"Historical backtest of the method","what":"Run the lattice and saturation axes blind against the 200 historical holes at their pre-fix artifacts; measure recall per stratum and whether Chao1 at the old 'complete' points predicted what was found afterwards; feed every post-signoff escape back as a new axis or dimension.","why_it_reduces_surprises":"A method that cannot re-find known holes is not trustworthy on unknown ones; the backtest calibrates the stop thresholds and makes the method learn this operator's actual blind spots."}]
IMPOSSIBLE: Absolute 100.00/100.00 in the open sense cannot be certified by any method; what can be certified is the closed sense (every enumerated cell resolved with evidence) plus a bounded, statistical residual. Six limits remain no matter the budget: (1) unknown dimensions, since saturation only works inside the lattice and a concern nobody enumerated is invisible to every pass; (2) correlated blind spots, since all current LLM reviewers share priors and engineered diversity recovers under half the independence gain, so Chao1 is a lower bound and only real contact and the operator's eye are decorrelated; (3) the unreachable ~5% (live production, real calendar time, operator taste in use), certifiable only as detection with a time-to-detect bound, never as absence; (4) new operator intent (~3%), reducible by the frame, premortem and walking skeleton but not predictable, so it is converted into a frame change rather than counted as a hole; (5) world drift, since a certificate is true at sha S in environment E at time T and dependency, API and OS updates invalidate it, which the boot-time drift check reports; (6) the estimate's own assumptions (closed population, equal-enough detectability, independence), which make 'zero remaining' a bound, not a proof. The honest certificate states: zero known material holes in frame Fn at sha S, estimated undiscovered desk-findable material holes <= e, all interfaces contacted or watched, exclusions listed, method recall R on the historical corpus.
BUDGET: Budget is allocated by where the hole mass is, then steered by measured yield. In order: (1) census depth and the historical backtest, cheap and highest-leverage because a dimension missing from the lattice cannot be saturated; (2) contact: sandbox tenants, real environments, multi-day clock-injected soak, the only instrument for the 15%; (3) saturation passes until the capture-recapture stop rule fires, spent on new vendors and new decomposition axes rather than repeats of one reviewer (a same-model repeat buys less than half what a new axis buys); (4) adjudication of every finding, never wasted because it also calibrates reviewer precision and unique-recall; (5) long-running mechanical search (mutation testing, fuzzing, property tests, soak) that scales with wall time and has its own Good-Turing saturation curve; (6) ground-up rebuilds where holes-introduced-per-fix is high. More spend stops helping, measurably, once the stop rule holds: additional LLM passes then yield false positives at a near-constant rate while confirmed yield is ~0, visible as reviewer precision collapsing with zero unique-recall. More spend hurts when it acts on unreproduced or M2/M3 findings (each fix is a hole-introduction opportunity), re-runs the same vendor on the same axis (confidence without information), grows a context past ~50-75% (reasoning degrades into narrative claims; recycle on the ledger instead), re-opens the frame without the operator (scope drift as diligence), or chases the unreachable 5% with desk research instead of watchers. The practical bound is weekly quota across four accounts plus two external vendors, so rounds are scheduled against headroom with a yield-per-quota-point table per reviewer config, and calendar time (days and weeks) is used deliberately for soak, drift checks and day-30/day-365 runs rather than treated as a cost.
