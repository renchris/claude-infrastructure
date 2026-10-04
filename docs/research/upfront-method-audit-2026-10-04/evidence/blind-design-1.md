# Pre-run the question, measure what is left, disclose the rest

A design built from first principles without seeing the existing method. I call it Escape-Calibrated Certification (ECC).

## 0. Thesis

1. **A "one more thing" is a search that the operator's question sets off and that the signoff never ran.** When "are we 100% complete?" turns up a hole, the search behind the "complete" claim was weaker than the one the question started: a different frame, a builder anchored to their own work, and a context that was not fresh. The fix is to make signoff consist of that exact search, run many times from fresh, blind, vendor-diverse contexts, until it comes back dry under a stopping rule fixed in advance. Then answering at "are we done?" is relaying a result, not starting a new search.
2. **Completeness in an open world cannot be proven. Two things can be certified:** (a) 100% coverage of a closed obligation ledger that was enumerated mechanically, and (b) a measured, calibrated estimate of what lies outside it.
3. **A surprise is a hole the operator did not know about, not just a hole.** Disclosing accepted residuals, named blind classes and scheduled post-signoff checks turns would-be surprises into known items. Disclosure is about half of the achievable reduction.
4. **Measure valid yield, not raw yield.** LLM reviewers never go quiet; they go wrong. The stopping signal is adjudicated-valid material findings per round falling to zero while raw findings stay flat.
5. **Every fix is a hole source.** Field studies put bad or bug-inducing fixes at roughly 9–29% (Firefox PRs about 12%; Yin et al. 15–24% of post-release fixes incorrect). Fixes are gated by a materiality bar and re-reviewed. The certified commit must be the reviewed commit.
6. **The method validates itself** by backtesting against the 200 historical holes, not by argument. The same backtest is how it should be compared with the existing method.

Reframing the literal ask: "upfront" should mean *before signoff*, not *before build*. Desk research before any artifact exists finds intent, decision and platform-fact holes, but most of the 2/3 desk-findable holes live in the artifact and only become findable once it exists. ECC front-loads intent, decisions and an early contact with the real environment, and back-loads discovery. All of it finishes before anyone says "done."

## 1. Causal model of escapes (what each mechanism targets)

| Hole class (historical share) | Why it escaped | ECC mechanism |
|---|---|---|
| Desk-findable (~67%) | The builder judged their own work; no closed universe; "done" decided by narrative; the end-question frame differed; context decayed | Mechanical census ledger, builder ≠ certifier, blind diverse discovery rounds, the canary lens (the operator's literal question pre-run), seeded calibration |
| Needs contact (~15%) | Verified in a worktree or with stubs, not as built; wrong interpreter (launchd's bash 3.2), wrong PATH, wrong account | Walking skeleton deployed on day 1, as-built evidence flag, fresh-machine and scheduler-interpreter probes, soak |
| Unreachable upfront (~5%) | Production load, time, operator taste | Early show-don't-tell artifacts for taste, named exclusions with monitors and scheduled checks so they arrive as planned, not as surprises |
| New intent (~3%) | The operator changed their mind or learned something | Frame amendment / change control, tracked separately from escapes |
| Unlabelled remainder (~10%) | Probably fix-induced holes and drift (sibling commits, environment changes) | Content-addressed evidence that goes stale automatically, fix gate, nightly re-verification |

## 2. State (all on disk; the session is a stateless worker over it)

- **Frame** (signed by the operator, hashed): goal; 5–15 concrete acceptance scenarios; non-goals; a **materiality bar per quality attribute** (what counts as "material" for correctness, security, performance, UX, docs, portability), declared before any reviewer runs; answers to the surprise inventory (§3, P0); the **pre-registered stopping rule** with its thresholds, so the goalposts cannot move in either direction.
- **Obligation ledger**: `id, source (frame clause | census generator | finding), acceptance check (executable where possible), evidence class (desk | as-built | contact | soak | operator-eye), status`.
- **Evidence store**: each item is `command + hash of every input it depends on + output + environment + as-built flag + positive control`. The positive control is a recorded mutant that turns this check red, so it is proof the evidence *can* fail. Evidence whose input hashes change goes stale automatically.
- **Finding log**: every finding with its adjudication, its canonical-hole id after dedupe, and the reviewer, model, vendor and lens that found it. It includes a **refuted registry**: a re-raised finding that was already refuted is auto-invalid unless it brings new evidence.
- **Decision log**: each decision the agent made on the operator's behalf, with a conviction % and the options considered.
- **Disclosure register**: accepted below-bar items, named non-certifiable classes, the monitor for each, and post-signoff scheduled checks.
- **Estimator state**: capture histories per canonical hole, per-class recall on seeded defects, the accumulation curves.
- **Escape log**: every post-signoff hole, with a root cause naming the instrument that should have caught it.

## 3. Phases

**P0. Frame and intent elicitation (operator time: about 30–60 min, once).** The agent drafts the frame and a **surprise inventory**: 50–150 "would you be annoyed in three weeks if…" items, generated from the historical-hole taxonomy, the domain and a pre-mortem. The operator marks each in / out / don't-care. Recognition is cheap where recall is not, and this pass is where most of the 3% intent class and much of the operator-eye class get pulled forward. The frame also fixes the size: if the ledger is likely to pass a few hundred obligations, split into slices that are each certified on their own.

**P1. Census → obligation ledger.** Several independent generators enumerate the universe.
- *Mechanical, closed by construction.* Parsers walk the artifact and emit every CLI flag, environment variable, config key, file written, exit code, error message, external call, scheduled job, schema column, state transition and credential or certificate TTL. Every sentence in the docs that asserts behavior becomes an obligation with an executable check.
- *Generative.* Lifecycle (install, configure, run, upgrade, migrate, roll back, uninstall, back up, observe, debug, hand off); actors (the operator, sibling sessions, launchd/cron, CI, a future maintainer, an attacker); quality attributes (ISO 25010); state space (empty, one, many, max, concurrent, interrupted, partial failure, retry, clock boundary, offline); environment cross-product (OS, shell version, PATH, account); and **one generator per historical-hole category**.
- Each generative census runs at least 3 times across different models. It counts as **saturated** when its last two runs add zero material obligations, read off a species-accumulation curve. The frontier model (Fable) gets one narrow job here: "what dimension is missing from this list of censuses?", which is a framing blind spot, not line-level review.

**P2. Decisions and early contact.** Every design decision is listed with a conviction %. At 90% or above, decide and record it in the disclosure. Below 90%, research it; anything still below 90% goes to the operator in one batched, options-and-numbers message, ordered by value of information. Meanwhile a **walking skeleton** is deployed end to end in the real environment within the first day. The cheap time to find contact holes (the scheduler's interpreter, permissions, real accounts, quotas) is before the code depends on wrong assumptions.

**P3. Build, test-first from the ledger.** Each obligation's acceptance check is written before or alongside its code, and each check carries its positive control. The builder never certifies.

**P4. Discovery rounds** (§4), alternating with the **fix gate** (§5) until the stopping rule (§6) holds.

**P5. Contact and soak, as built.** Every contact-class obligation is verified against the deployed artifact, not the worktree. That covers a fresh-machine install (clean HOME, `PATH=/usr/bin:/bin`, the scheduler's actual interpreter), real accounts and network, fault injection (kill -9 mid-operation, disk full, network drop), and a **soak** that crosses the time boundaries the census named (midnight, quota reset, log rotation, reboot, DST where relevant).

**P6. Operator acceptance (operator time: about 20–40 min).** An **intent diff**: what you asked → what I built → the decisions I made for you → what is deliberately out. It comes with a show-don't-tell walkthrough: recordings, screenshots, real outputs. Operator-eye items are signed here or become frame amendments.

**P7. Certificate**, computed from state (§8).

**P8. Post-signoff watch.** The monitors and scheduled checks from the disclosure register run, and escapes go into the escape loop (§10).

## 4. The discovery engine

**Round composition.** A full round has at least 6 blind reviewers across at least 3 vendors (Claude Opus/Sonnet, OpenAI codex, Google Antigravity), each assigned a different lens. They get the frame, the artifact and read access to the running environment. They do **not** get the ledger, earlier findings or other reviewers' output: blindness is what keeps captures independent and stops anchoring. A separate *ledger auditor* slot re-executes evidence (it does not read claims) and checks each positive control.

**Lens library.** The new user on a fresh machine; the operator three weeks later; the adversary; the maintainer six months on; the 3 a.m. incident responder; the scheduler (a different interpreter and environment); concurrency (two sessions at once); interruption and partial failure; upgrade from the previous version; docs truth (execute every claim); and one lens per historical-hole category. Above all there is the **canary lens: the operator's literal question, "are we 100% complete? what did we forget?", asked verbatim in a fresh context.** Pre-running it is the core mechanism; it is how answering at signoff becomes relaying.

**Instrument diversity beats model diversity.** LLM errors are strongly correlated across vendors (Kim et al., ICML 2025: models agree on about 60% of the cases where both are wrong). So every round also includes non-LLM instruments: property-based tests and fuzzing, mutation testing of the suite, static analyzers run exactly as the land gate invokes them, and model checking (TLA+/Alloy or exhaustive state enumeration) for any concurrency or state-machine core. These have uncorrelated blind spots.

**Finding schema.** Each finding gives: the claim; the location; the obligation id, or "unledgered" (a finding outside the ledger is a census failure and also adds an obligation); a concrete failure scenario; a **reproduction** (failing test, command and output, or exact steps); and a severity read against the frame's bar. A finding without a repro is an "unverified concern": it is resolved by a probe or dismissed with a reason, never silently dropped.

**Adjudication.** An adjudicator from a *different vendor than the finder* (which avoids self-preference) tries to refute the finding and executes the repro. The verdict is valid-material, valid-below-bar, invalid or unverified. Dedupe maps valid findings to canonical holes (obligation + failure scenario). A sample is double-deduped to measure agreement. Precision (valid / raised) is tracked per model × lens and decides which slots get bought next.

**Estimators.** For each canonical hole, record which reviewers caught it.
- *Chao1:* undiscovered ≈ f1²/(2·f2), where f1 = holes found by exactly one reviewer and f2 = holes found by exactly two. When singletons dry up, the curve has saturated.
- *Jackknife Mh:* Briand et al. found that heterogeneity-aware jackknife models do best, and that every model underestimates with fewer than about 4 inspectors.
- *Good–Turing:* the probability that the next valid finding is new ≈ f1/n.

All of these are **lower bounds**, because reviewers share blind spots.

**Seeded calibration (error seeding, Mills 1972, done properly).** A *sealed* seeder session the lead cannot read builds a calibration copy of the artifact. Seeds are (a) **real historical holes replayed**: revert old fixes where the code still exists, or re-create the hole's pattern; and (b) synthetic seeds per historical class. The calibration copy goes through the same round configuration as the real artifact. Per-class recall r_c gives:
- *Residual correction:* expected remaining real holes in class c ≈ found_c × (1/r_c − 1). This forces an honest truth: the residual scales with how many holes there were. Finding 40 at 95% recall leaves about 2. So build quality (test-first, small scope) matters as much as discovery.
- *Blind-class detection:* a class whose seeds are rarely caught by any LLM reviewer tells you more reviewers will not help. Add a different *instrument* for it (an execution check, a contact probe, a model checker) or list it as an exclusion.
- Statistical power is stated: 10 seeds cannot tell 90% from 99%. Unbounded budget buys 50+ seeds per class.

## 5. The fix gate

- Only valid-material findings get fixed. Below-bar findings go to the disclosure register as accepted residuals with a reason. The operator sees them, so they are not later surprises, and acting on them would only add fix-injection risk.
- Every fix: the repro becomes a regression test first; then the smallest diff (prefer deleting or simplifying); then evidence whose input hashes changed goes stale and re-executes; then a **diff-scoped blind review** of the fix and its blast radius by fresh reviewers.
- The fix-injection rate is measured per project, as the share of fixes that later produce a hole, and feeds the decision of whether to fix at all: fix only if expected harm of the hole > p(injection) × expected harm of a new hole.
- **Freeze invariant:** the certified commit must equal the last-reviewed commit. Any later change makes the certificate stale in the affected blast radius, and recertifying covers the delta plus a diff round.

## 6. Pre-registered stopping rule (defaults; tune them by backtest)

Certify only when all of these hold:
1. **Ledger closed:** every census generator is saturated, and every obligation has evidence that passes on the current commit, including its positive control. Contact- and soak-class evidence is as-built.
2. **Discovery dry:** the last 2 consecutive full rounds, covering together every lens in the library, produced 0 valid material findings.
3. **Residual bounded:** the seeded-recall-corrected residual is below 0.5 expected material desk holes, with Good–Turing new-hole probability below 5%. Reported as a lower bound.
4. **Calibrated:** seeded recall in each desk-findable class has a Wilson lower bound ≥ 0.85, or the class has a dedicated non-LLM instrument, or it is a named exclusion.
5. **Canary dry:** the operator's literal close question, replayed in at least 10 fresh contexts across at least 3 vendors and several phrasings, yields 0 valid material findings against the certified commit.
6. **Contact complete:** every contact probe passed as built, and the soak window ended with no anomalies.
7. **Intent closed:** the intent diff is signed and no decision is open.
8. **Freeze:** certified commit = reviewed commit, and nothing landed after the last round.

## 7. Spending unbounded budget

**Allocation.** Treat each instrument (lens × model, mechanical census, fuzzing, mutation, model checking, contact probe, soak) as a bandit arm, priced by *valid* material holes found per unit cost. Measured precision and seeded recall update the price. The next unit of budget goes to the arm with the best marginal yield. Spread quota across the four accounts' reset schedules and across vendors.

**Where more spend keeps helping (with no ceiling for a long time):**
- More **seeds**: tighter recall bounds, so a more honest certificate.
- More **instrument types** for low-recall classes.
- **Fuzzing and property-test** CPU, and corpus growth.
- **Model checking** of critical cores.
- **Wall-clock soak** across time boundaries. Time-dependent holes can only be bought with time.
- **Nightly re-verification** of all evidence against the moving trunk and environment (drift capture).
- **Backtesting** the method itself (§10).
- **Scope reduction:** every obligation removed is a hole that cannot exist.

**Where more spend stops helping:** once seeded recall has plateaued for the desk lenses and singletons are zero across rounds, more same-type LLM review only replays shared blind spots. Valid yield sits at zero while raw yield stays flat, so precision collapses. That is the signal to move spend to a different instrument class, not to stop.

**Where more spend starts hurting:**
- Unadjudicated false positives acted on (fix churn adds holes).
- Gold-plating that adds surface and therefore obligations.
- Goodhart pressure on reviewers rewarded by finding count.
- A growing adjudication backlog.
- More asks of the operator. Their attention is the scarcest resource, so asks are budgeted: P0, P6 and batched sub-90% decisions only.
- Context decay in long sessions.
- Stale research: a long delay lets dependencies and APIs drift, which nightly re-verification partly offsets.

## 8. What the certificate honestly says (rendered, never written as prose)

- **Scope:** frame hash, ledger hash, certified commit, environment.
- **Coverage:** N/N obligations verified, with as-built evidence re-executed at time T and every positive control confirmed. This is a real 100%, of a closed universe.
- **Discovery:** rounds, reviewers, vendors and lenses; the valid-yield sequence (for example 14 → 5 → 1 → 0 → 0); f1 and f2; the residual estimate stated as a *lower bound*; seeded recall per class with intervals.
- **Contact:** the probes and the soak duration.
- **Disclosures:** accepted below-bar items; named non-certifiable classes, each with its monitor, owner and first scheduled check (+24h, +7d); decisions made on the operator's behalf.
- **Prediction:** once enough backtests and escape history exist, a calibrated expected-escape figure for covered classes. Never "100.00/100.00".
- **Validity:** stale when the commit, environment or frame changes. It is re-checked by the nightly job.

## 9. Operator intent and continuity

**Intent.** Recognition beats recall (the surprise inventory). Taste is pulled forward with early concrete artifacts. Decisions are logged with conviction and disclosed. New intent after signoff is a **frame amendment**: it adds obligations, a delta certification follows, and it is counted separately from escapes. Mixing the two would corrupt the calibration.

**Continuity.** The lead is a *role*, not a context. Every session start runs `verify`, which re-executes stale evidence against the current commit and environment, and then resumes the state machine (phase, round counter, adjudication queue, open probes). Handoff briefs are rendered from state, never written from memory. Rejected approaches and refuted findings are stored with reasons so a successor does not re-raise them. A multi-week program is **hierarchical**: per-slice certificates, plus an integration ledger for obligations that cross slices, plus a program certificate. That certificate needs every slice certificate re-verified fresh at the final commit, plus integration discovery rounds. Separation of roles holds across sessions: builder, certifier, adjudicator, sealed seeder and lead.

## 10. The "are we done?" behavior

- **The answer is computed.** A prompt hook detects close questions and injects the rendered certificate. The reply relays it: "Yes/No against frame F. N/N verified as built at T. Discovery ran dry (14 → 5 → 1 → 0 → 0). Residual ≥ 0.3 expected desk holes, as a lower bound. Not certifiable: X, Y, watched by M, first check +24h. Below-bar items you accepted: … Decisions I made for you: …"
- **Invariance.** Asking again, or rephrasing, gets the same answer, because that exact question was pre-run as the canary and its statistics are part of the certificate. The question is not a fresh search prompt, because the search has already been done. The certificate's own invariance test asks it in many phrasings across vendors.
- **Honesty is never suppressed.** If the agent genuinely notices a real hole after certifying, it must say so. It files it as an **escape** (a command, not a passing remark in prose), the certificate is revoked, and the hole is root-caused to the instrument that should have caught it. A Stop hook blocks any "complete/done/100%" claim unless a certificate exists whose commit equals the current HEAD and whose evidence is fresh. It also blocks a post-certificate finding raised in prose without an escape record.
- **The escape loop.** Any escape in a *covered* class is a defect in the method. Its fix adds a lens, seeds or a census generator, and the backtest is re-run. Escapes per certified project, broken down by class, are the method's real-world score. The target is zero in covered classes, and the escape count is the only honest evidence of how close it gets.

## 11. How to decide whether the existing method is the best (I cannot see it)

**The arbiter is a backtest, not a debate.** The 200 historical holes are a labelled dataset. Snapshot each project at its false "complete" claim, run a candidate method at a fixed budget, and measure:
- recall of the holes that were later reported, by class;
- precision;
- fix-injection rate;
- operator-minutes;
- cost.

Split the holes into train and test sets: lenses derived from the 200 holes would otherwise score themselves.

**Discriminating questions for the existing method:**
1. Does it pre-run the operator's literal close question as a gate?
2. Does it stop on adjudicated *valid* yield, not raw yield or a timebox?
3. Does it estimate the residual with capture–recapture, and calibrate it with sealed seeded defects, including replays of real historical holes?
4. Does it treat that estimate as a lower bound because of correlated LLM errors, and add non-LLM instruments for blind classes?
5. Is the ledger closed by mechanical census and saturation curves?
6. Is evidence content-addressed, as built, positive-controlled and stale on change?
7. Does it declare a materiality bar and stopping rule *before* review?
8. Does it treat every fix as a hole source (repro-first, diff review, freeze invariant)?
9. Does it separate disclosure from defect, and new intent from escape?
10. Does it compute its "done" answer and enforce it with hooks?
11. Does it run an escape loop that updates the method?
12. Has it been backtested?

Each "no" names a specific class of future "one more thing."

KEY MECHANISMS: [{"name":"Canary lens: pre-run the operator's close question","what":"The literal question \"are we 100% complete? what did we forget?\" is asked verbatim in at least 10 fresh, blind contexts across at least 3 vendors and several phrasings, against the certified commit. Signoff requires 0 valid material findings from it.","why_it_reduces_surprises":"A one-more-thing is the search the question sets off that signoff never ran. Running it beforehand, many times, turns the answer at question time into relaying a result instead of starting a new search."},{"name":"Mechanically closed obligation ledger with saturation curves","what":"Parsers enumerate every flag, environment variable, config key, file written, exit code, external call, state transition, credential TTL and docs claim. Generative censuses (lifecycle, actors, ISO 25010, state space, environment cross-product, one per historical-hole category) each run at least 3 times across models until two runs in a row add nothing.","why_it_reduces_surprises":"It turns \"complete\" from a narrative into 100% coverage of a universe built mechanically. A finding outside the ledger exposes a census failure and is fed back into the ledger."},{"name":"Blind, vendor- and instrument-diverse discovery rounds","what":"6 or more reviewers across 3 or more vendors, each with a distinct lens, blind to the ledger and to earlier findings. Every round also runs property tests and fuzzing, mutation testing, gate-identical static analysis, and model checking for concurrency cores.","why_it_reduces_surprises":"LLM errors are about 60% correlated (Kim et al. 2025), so adding instrument types with uncorrelated blind spots finds holes that more LLM reviewers cannot."},{"name":"Repro-gated cross-vendor adjudication with a refuted registry","what":"Each finding must carry a reproduction. An adjudicator from a vendor other than the finder's tries to refute it and executes the repro. Precision is tracked per model and lens. A refuted finding raised again without new evidence is automatically invalid.","why_it_reduces_surprises":"It removes LLM false positives before they turn into churn-inducing fixes, and makes valid yield, not raw yield, the measured signal."},{"name":"Capture-recapture residual estimation","what":"Valid findings are deduped to canonical holes, with a record of which reviewer caught each. Chao1 (f1²/2f2), jackknife Mh and Good–Turing estimate the number of undiscovered holes and the probability that the next finding is new, reported as lower bounds.","why_it_reduces_surprises":"It replaces a felt sense of being done with a measured residual, and gives an objective signal when singletons dry up."},{"name":"Sealed seeded calibration using replayed historical holes","what":"A seeder session the lead cannot read reverts real historical fixes and plants synthetic per-class seeds in a calibration copy, which is reviewed under the same configuration. Per-class recall corrects the residual and flags blind classes.","why_it_reduces_surprises":"It measures what the reviewers actually catch, so blind classes get a dedicated instrument or an explicit exclusion instead of a silent gap. It also measures the method on the operator's own hole history."},{"name":"Content-addressed, as-built, positive-controlled evidence","what":"Each piece of evidence records a command, the hashes of its inputs, its environment and an as-built flag, plus a mutant that turns it red. Changed inputs make it stale automatically, and a nightly job re-executes everything.","why_it_reduces_surprises":"It catches evidence that cannot fail, results verified in a worktree but not as built, drift from sibling commits, and staleness from fixes: the unlabelled ~10% and much of the 15% that needs contact."},{"name":"Fix gate and freeze invariant","what":"Only valid material findings get fixed. Each fix gets a repro test first and a minimal diff, followed by a blind review scoped to the diff. The fix-injection rate is measured, and the certified commit must equal the last reviewed commit.","why_it_reduces_surprises":"Studies put bad fixes at 9–29%. Without the gate, fixing findings creates the next round of holes after signoff."},{"name":"Materiality bar and stopping rule pre-registered in a signed frame","what":"Before any review, the operator signs per-attribute materiality thresholds and the full stopping rule, along with acceptance scenarios and non-goals.","why_it_reduces_surprises":"It stops goalposts from moving, so findings that are reviewer taste cannot force endless rounds and a premature stop cannot be argued in."},{"name":"Surprise inventory and intent diff","what":"At intake the operator marks 50–150 recognition items (\"would you be annoyed if…\") as in, out or don't-care. At acceptance they sign a diff of asked → built → decided for you → out, with recordings and screenshots.","why_it_reduces_surprises":"Recognition is cheap where recall is not. This pulls intent and operator-eye holes forward, and turns decisions made on the operator's behalf into disclosed, signed items."},{"name":"Disclosure register with monitors and scheduled checks","what":"Accepted below-bar items and named non-certifiable classes are listed in the certificate, each with a monitor, an owner and a scheduled post-signoff check (+24h, +7d).","why_it_reduces_surprises":"A surprise is an undisclosed hole. Disclosure makes the unreachable 5% arrive as expected events rather than as one-more-things."},{"name":"Computed certificate and hook-enforced answer","what":"A prompt hook injects the rendered certificate when a close question is asked. A Stop hook blocks any done-claim unless the certificate's commit is HEAD and its evidence is fresh, and blocks a post-certificate finding raised in prose without an escape record.","why_it_reduces_surprises":"The answer stays the same however the question is asked or repeated, and any real late finding is recorded as a measured escape instead of being folded casually into a reply."},{"name":"Escape loop and method backtest","what":"Every post-signoff hole is root-caused to the instrument that should have caught it, and the method gets a new lens, seeds or census. Candidate methods are backtested on train/test-split snapshots of the 200 historical false-done moments, measuring recall by class, precision, fix-injection rate, operator-minutes and cost.","why_it_reduces_surprises":"The method's coverage grows from its own failures, and \"is this the best method\" becomes an empirical comparison at a fixed budget instead of a debate."},{"name":"Early walking skeleton in the real environment","what":"An end-to-end deployment in the real environment (scheduler interpreter, real accounts and permissions) within the first day, followed later by fresh-machine probes, fault injection and a soak across time boundaries.","why_it_reduces_surprises":"It finds the ~15% of holes that need contact while they are still cheap, before code has been built on wrong platform assumptions."},{"name":"Stateless sessions over on-disk state with hierarchical slicing","what":"The lead is a role. Each session starts by running verify, which re-executes stale evidence, and handoffs are rendered from state. Multi-week programs certify slices, then an integration ledger, then a program certificate re-verified at the final commit.","why_it_reduces_surprises":"Nothing that matters lives only in a context window, so handoffs and recycles across days do not lose decisions, refuted findings or invalidated evidence."}]
IMPOSSIBLE: Literal 100.00/100.00 completeness cannot be proven, for four reasons:
1. **The goal is open-world.** No oracle exists for intent the operator has not yet formed, and semantic properties of code are undecidable in general (Rice's theorem). Every specification is incomplete with respect to the world it describes.
2. **Some classes no instrument can see.** Capture-recapture and seeding estimate only classes that at least one instrument can detect. A hole class every reviewer, test, checker and probe is jointly blind to has zero catchability and cannot be counted. LLM error correlation makes this risk real, so every residual estimate is a lower bound.
3. **Some holes need production or time.** Real load, real user behavior, and failures that only appear over months (dependency deprecation, API drift, data growth) cannot be fully exercised before production. Soak and time-boundary probes shrink this class but do not close it.
4. **The operator's future intent and taste can change.** New intent after signoff is change, not a defect, and no method prevents it.

Statistical caveats: seeded defects may be easier than real ones, and a residual estimate is only as tight as the number of seeds behind it.

What can honestly be certified:
- 100% coverage of a closed, mechanically enumerated ledger, with evidence re-executed as built;
- a valid-yield sequence that ran dry under a pre-registered rule;
- a calibrated lower-bound residual, with per-class recall;
- the list of named exclusions, each with its monitor and scheduled check;
- once enough escape history and backtests exist, a calibrated expected-escape rate for covered classes.

The honest substitute for "100.00/100.00" is: zero escapes in covered classes is the target, and any escape in a covered class is a defect in the method that gets fixed.
BUDGET: Budget is allocated as a multi-armed bandit. Each instrument is priced by adjudicated valid material holes found per unit of cost, using measured precision and seeded recall. Quota is spread across the four accounts' reset schedules and three vendors.

**Spend that stays productive almost without a ceiling:**
- Seed count, to tighten recall bounds: 50+ per class, including replays of real historical holes.
- New instrument types for classes with low recall: execution checks, model checking, contact probes.
- CPU for fuzzing and property tests, plus corpus growth.
- Wall-clock soak across time boundaries (midnight, quota reset, log rotation, reboot). Time-dependent holes can only be bought with time.
- Nightly re-execution of all evidence against the moving trunk and environment, to catch drift.
- Mutation testing of the evidence suite.
- Backtesting candidate methods against the 200-hole history with a train/test split.
- Scope reduction: each obligation removed is a hole that cannot occur.

**Where more stops helping:** once seeded recall plateaus for the desk lenses and singleton findings stay at zero across rounds, more same-type LLM review only replays shared blind spots. Raw findings stay flat while valid yield is zero, so precision collapses. That is the signal to move spend to a different instrument class.

**Where more starts hurting:**
- False positives that are acted on, which causes fix churn (9–29% of fixes inject bugs).
- Gold-plating that adds surface and new obligations.
- Goodhart pressure on reviewers rewarded for finding count.
- An adjudication backlog.
- Operator-attention cost, so asks are capped to intake, acceptance and batched sub-90% decisions.
- Context decay in long sessions.
- Research going stale while the environment drifts.

The pre-registered stopping rule, together with the measured valid-yield curve, is what stops the process. It does not stop on a timebox.
