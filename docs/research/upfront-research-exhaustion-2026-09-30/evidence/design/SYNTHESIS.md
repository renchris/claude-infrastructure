# Certified Upfront Research (CUR v2): the synthesized protocol

Synthesis of `/tmp/rescomp/design/{statistical-stopping,frame-contract,reality-contact}.md` under the three judge
verdicts, 2026-09-30, after the 15:26 CDT reboot. Read-only on every repo. Paths without a root are relative to
`/Users/chrisren/Development/claude-infrastructure` (trunk `cda13e6a1`).

**Spine: statistical-stopping (SS), revision 2.** It had the highest total across the three judges (sum of the five
axis scores per judge: SS 39.5 + 38 + 37 = 114.5; frame-contract 38.5 + 36.5 + 37 = 112; reality-contact 34 + 33.5 +
36 = 103.5). It also led on the two axes the operator's complaint is about: termination (9.5 / 9 / 9) and no
take-backs (8.5 / 8 / 8). Its weaknesses were a thin front end and thin contact coverage. Those are exactly where the
other two designs are strongest, so they are grafted in:
- **From frame-contract (FCR):** the Hole-Pattern Checklist, the evidence-source register and its tie-breaker, a
  closure instrument and reversibility tier per decision, the bounded frame critique, store reconciliation, and change
  requests with a cause field and a presumption against change.
- **From reality-contact (RCF):** computed evidence tiers E0–E6, the H1–H7 contact matrix, the STPA hazard grid and the
  state × input grid, an executable spec that must self-test red and green, value-of-information probe ordering, the
  verdict vector over the operator's own question frames, a bounded re-ask rehearsal, set decisions and the probe-kit
  doctor.

Every fatal flaw the judges named is closed; §13 maps each one.

**Provenance.** The pre-reboot synthesis used a frame-contract spine and an older judge set. It is preserved unchanged
as `SYNTHESIS.r1-pre-reboot.md`, and `statistical-stopping.md` §14 cites its §12.

**New evidence produced for this synthesis:** `synth_width.py` / `synth_width.out` (same `cert_sim.py` model). They add
a T = 24 width step and the max tier under false positives with a hard cap.

**Contact checks re-run this session:**

| Check | Result |
|---|---|
| `bin/cc-signoff:1-30, 91-110` | refuses a claude ancestor, pins bytes, renders forgeries VOID; accepts only cc-mission row ids |
| `grep -nE 'ancestr\|operator-only\|ppid\|PPID' bin/cc-decide` | no hits |
| `ls .../fnm/node-versions/*/installation/bin/gemini` | present under v18.18.0, v20.19.6 and v22.21.1 |
| `/opt/homebrew/bin/claude --version` / `--help` | 2.1.278; lists `--setting-sources` (line 219) |
| `~/.local/bin/codex`, `/opt/homebrew/bin/ollama` | present |
| `~/.claude/settings.json` | `research-precognition-nudge.sh` already registered on UserPromptSubmit (a new branch needs no settings migration); `frontier-spawn-gate.sh` registered only on PreToolUse `Agent` |
| `scripts/wrap-ledger.sh:616-623` and `:2286-2288` | REMAINDER counts `- [ ]` boxes; an absent DoD still renders the ✅ rung |
| `hooks/completion-assert.sh:1278`, `CLAUDE.global.md:616-619` | D4 ("the answer is always yes"); F1 ("nothing left on the table") |
| `agents/deep-research.md:187`, `agents/research-decomposition-critic.md:37-38`, `skills/research-subagents/SKILL.md:798-803` | the three gap quotas, verbatim |
| `bin/cc-decide:42,480` | `expire-sweep` records a fired class-B default as `expired-actioned` and reports it; it never executes it |
| `ls docs/research \| wc -l` | 406 entries, no index |

The panel-isolation probe is SS's, run this session with a positive control from `cd /tmp`. `claude -p` without the
flag quoted the mission board; with `--setting-sources local` it answered `NONE` (`statistical-stopping.md:20-24`).

---

## 0. Diagnosis in five lines

1. **Holes surface late because the checks run after the claim.** Of 200 holes that surfaced after a "complete" claim, 64.5% were desk-findable, 60% were misses inside a frame the research already had, 11.5% were known items re-rendered, 3% were new requirements, and only 5% were unreachable by any upfront process on this machine (`taxonomy.md:9-18, 277`).
2. **"Complete" is measured against nothing.** The DoD carries the superlative verbatim (`hooks/dod-persist.sh:1-15`). REMAINDER counts `- [ ]` boxes, which only 4 of 76 DoD files have (`wrap-ledger.sh:616-623`; `close-assertion.md` §1.3). An absent DoD renders ✅ (`:2286-2288`).
3. **The machinery requires a new hole on every ask.** Every gap-finder has a quota ("Find 2-3 gaps", "name 1-3 … MISSING", "List 3" plus promote-unless-excluded). F1 passes any refinement, D4 forces every named item to be driven, and no Stop arm guards an unbounded "not done". So "No, one more thing" is the only compliant answer.
4. **Nothing is persisted or computed.** There is no materiality definition, no stop rule in code (OASIS is prose, `SKILL.md:756-782`) and no verdict history. Each ask regenerates a fresh critique, and "Are you sure?" flips answers 46% of the time. Bounded passes over a frozen artifact converged (10→7→2; 7→1→0). Open fix-in-loop critics did not (23/21/24/28).
5. **A literal 100.00 with zero unknowns cannot be certified** without examining at least 95% of every place a hole could be (n ≥ 0.95N). What can be certified is 100.00% closure of a signed frame plus a measured residual bound, bought at a price chosen once. That is what this protocol produces.

---

## 1. What the protocol promises

**Research 100.00/100.00** means all of the following on one frozen snapshot, and nothing else. The operator ratifies
this definition once, as AD1.
- (a) Every row of the operator-signed frame is closed with a receipt that a script checks. This part is exactly
  100.00.
- (b) Certification stopped under the pre-registered rule: K dry rounds, or the cap.
- (c) The certificate states the estimated desk-detectable material holes still present, with a 95% bound, per
  stratum, printed beside the forecast the operator bought at intake.
- (d) Every item research cannot reach is declared, owned and dated.
- (e) The operator signed the content hash.

**No take-backs.** A signed verdict changes only through one of three things:
1. an **escape**: a reproduced, material, in-frame miss;
2. a failed deterministic freshness re-check;
3. an operator change request.

Every escape is counted and shown against the count printed at signoff. A *take-back* is defined as the certificate's
calibration failing (§8.3), and it is reported as one. New requirements, drift, the narrowing of a carried set, and
declared residuals are typed events, not reversals. **The answer never changes because a question was asked.**

**Finite.** Every loop has a numeric cap (§2.3). The program ceiling is printed at ratification, and only an explicit
operator act exceeds it.

| Conviction | Value | Basis |
|---|---|---|
| The protocol terminates | 97% | by construction: every loop capped, every gate row finite; the 3% is a cap not enforced in code |
| It terminates within the forecast R_max, not R_abs | 85% | `forecast_check.out`: p90+4 covered 99.3% (model right) and 93.3% (misspecified) |
| The stated bound is calibrated on real LLM panels | 60% | every number comes from `cert_sim.py`; W0 (§12) measures it; certificates print "uncalibrated" until then |

**Operator rulings needed.** Each carries `Replaces: <practice> — ruling pending` until it is ruled. AD1–AD3 go as one
class-C packet with the **measured** W0 price table.

| # | Ruling | Replaces | Recommendation | Conviction |
|---|---|---|---|---|
| AD1 | "100.00", "no take-backs" and "finite" mean §1 above | the open "as long as it takes / literal 100.00" reading | adopt | 88%. The literal reading is provably uncertifiable; what is open is whether a stated bound satisfies the operator |
| AD2 | Under a certified program, research reopens only on a MATERIAL escape; REFINEMENTs go to the build backlog (`apply-at-build`) | F1 "nothing left on the table" (`CLAUDE.global.md:617`) as the post-certificate net-positive test | adopt | 85% |
| AD3 | While a certificate exists, a "no" to a completeness ask must cite an escape, a failed freshness row or a change request; "driving" a new concern means filing and triaging a challenge | how D4 "the answer is always yes" (`completion-assert.sh:1278`) reads on re-asks | adopt; the Stop arm ships warn-only until ruled | 82% |
| AD4 | Remove the gap quotas from the three prompts; zero is a valid answer | not an operator-stated practice | do it, no ruling needed | 92% |

Without AD1, the protocol still runs and still issues certificates, but the anti-regeneration arm stays in warn mode.

---

## 2. The protocol at a glance

### 2.1 Phases

| Phase | Locus | Work | Gate rows it must pass | Prior budget |
|---|---|---|---|---|
| **P0 Intake and frame** | L (lead with the operator; the exchange is the asset) | mining, interview, superlative translation, frame registers, tier choice, bounded frame critique, ratification | S1 | 2 d; about 25 runs; 60–90 min of operator time |
| **P1 Prior art, census, premises, sources** | S | index search, topic lock, censuses by 2 methods and grids, premise register, source register | S2, S3, S4 (registered) | 1.5 d |
| **P2 Measure-first contact wave (CW)** | S, driving a Workflow | environment doctor, incumbent at n ≥ 5, ceilings, premise probes in VOI order, handed-command dry runs, credential lifetimes | S4 (tiers), S7 (environment rows) | 1.5 d |
| **P3 Decisions** | S (research waves inside) | option census and option probes, timeboxed decision rows in VOI order, rulings, sets | S5 | 3 d |
| **P4 Executable spec and contact matrix** | S (teammates for skeleton, harness and model check) | harness with self-test, contact skeleton, H1–H7 cells, grids probed | S6, S7 | 2.5 d |
| **P5 Synthesis, freeze, seeding** | S (single integrator) | plan written from the ledgers; trace, reconcile, lint, fresh read; freeze S₁; seeds planted and pre-screened | S8, S9, S12 | 1 d |
| **P6 Certification** | S per round | round 1 plus forecast; rounds to the stop; rehearsal; Fable sweep | S13, S14, Q1–Q8 | forecast after round 1 (max24: p50 5–6 rounds) |
| **P7 Gate, signoff, build start** | S, then operator | `cc-research gate`, `cc-signoff`, then revalidation at build start | S10, S11, full gate | 0.5 d |

Each dispatched phase session has a goal that ends at the agent's reach, never on an operator-only act
(`docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md`):

`--goal 'cc-research gate --program <P> --phase P<n> prints every row PASS or FILED(<id>) — proven by the session running it and printing the output; do not edit frame.json; brief above, frame at docs/research/<P>/frame.json'`

### 2.2 The one dial: the tier

The operator picks a tier at intake from a priced curve (§3.7). The residual threshold is spent **there**, never as an
exit gate. As an exit gate, a μ̂ ≤ 0.5 target ended in an operator decision in 53.2% of simulated programs
(`tier_curve.out` §C). **Recommended for this operator: max24**, explained in §3.7.

### 2.3 Loops: the complete list, each capped

| # | Loop | Cap | After the cap |
|---|---|---|---|
| L1 | A refuted premise re-plans its dependency closure (P2/P4 → P3) | each D-row reopened by refutation at most 2× | a third refutation: carry it as a set (if contact-decided and irreversible), or file a class-B packet whose default is the surviving option with the highest conviction |
| L2 | D-row research | the timebox set at intake; a reversible row gets ≤ 2 runs plus a revisit trigger | class B (default: recommended option) or class C (escalation surface or operator value) as a carried row |
| L3 | Frame critique | exactly 2 rounds | none |
| L4 | Census critic | once per population | later misses are the panels' census lens, counted in the estimate |
| L5 | Certification rounds | R_max = min(forecast p90 + 4, R_abs), fixed after round 1 | `stop=cap` certifies |
| L6 | Dead, partial or voided panel slot | 2 re-runs | next family in the ratified order; "reduced diversity" printed |
| L7 | Seed realism rewrite | 1 | "realism flag" printed |
| L8 | Hard-tail detector per weak class | 1 attempt | "weak lens" named |
| L9 | Adjudication re-pass when κ < 0.7 | 1 | "adjudication unstable" printed |
| L10 | Disputed finding | 1 reproduction probe | MATERIAL-DISPUTED, named |
| L11 | Stratum return to P1–P4 when N̂₀ ≫ what discovery expected | 1 per stratum, timeboxed 1.5 d, never extends R_max | none |
| L12 | Rehearsal | runs once; ≤ 2 delta rounds on its finds | finds counted in the certificate |
| L13 | Escape after the gate | ≤ 2 delta rounds per escape | a further find is itself an escape; §8.3 applies |
| L14 | Phase overrun | at 1.5× budget, one class-B packet | its default "proceed" fires at 24 h: open rows become carried rows |

Nothing else loops. There is no open-ended "find gaps" loop anywhere: 23/21/24/28 new items per round
(`7c395da7` 15:58:52Z) and 37→…→16 over 13+ rounds (`dcbd2f8e`) are the reason.

### 2.4 Build state: Profile H now, Profile F later (one protocol)

The protocol does not wait for tooling.
- **Profile H (hand-run, available at W0).** Registers are JSON/JSONL files written by the lead. Five small scripts do
  the rest: `probe-run.sh` (records command, environment, stdin, exit and raw output); `courier.sh` (CLI panels by
  absolute path, plus the sanitized-bundle builder); `cur_estimate.py` (a port of `cert_sim.py`'s `predictive_draws`,
  `chao2_bc`, `jk2`, `mann_whitney_z` and the forward forecast); `seed.py` (anchored patches, vault, match, orphan);
  `gate.sh` (jq predicates).
- **Profile F (full).** The same stores and rules behind `bin/cc-research`, Workflows and hooks (§12).

The certificate prints which profile produced it. Profile H has no re-ask hook, so the program's `FRAME.md` first
line and the session DoD point at `gate --render`, and the lead relays it.

---

## 3. P0: intake and the frame

### 3.1 Mine before asking

A read-only fan-out writes `intake-mined.md`, with every claim quoted and receipted. It reads:
- **Prior art:** a research index built by `cc-research index` (406 entries have none today); `docs/plans/**` here and in
  sibling repos; `cc-memory-search <terms>`; transcripts `~/.claude*/projects/*/*.jsonl`, including `<sid>/subagents/**`.
- **Operator history:**
  - `msg search` / `msg with` for every named counterparty (hole 194, the in-person author agreement);
  - `cc-decide list --all --json` for prior rulings (hole 186, the apex-domain decision);
  - `cc-backlog list --all` and `cc-mission list`;
  - CLAUDE.md house rules that act as acceptance criteria (hole 198, the one-command preference).
- **Topic lock:** a positive liveness signal before starting (a commit minutes old, a live pane, open custody). An owner
  is never declared dead from absence (hole 139: three plans for one topic).

### 3.2 Interview: one sitting, 12 questions, each pre-filled from the mining

The operator confirms or corrects each pre-filled answer.
1. **Consumer.** Who consumes the deliverable on day one, and how is it installed: agent, human or CI? (#198)
2. **Where it runs and what keeps it alive.** Host, OS or device, scheduler and interpreter, CI image, tenant, network. What keeps it alive, what expires, who re-authenticates? (#92, #96, #168, #153)
3. **What binds it.** Prior decisions, private facts, relationships, accounts and tenants; the agent lists what it mined. (#147, #186, #194)
4. **"Not lacking".** What does it mean? Give 3–5 positive references per taste axis, and name who judges them. (#62, #65, #66)
5. **Exclusions.** What is out of scope, in your words? This is the only legitimate exit of the negative-space rule (`SKILL.md:800-803`), now answered up front.
6. **Irreversibility.** Which actions are irreversible or spend money, and what must never regress? (#159, `b03a348`)
7. **What can move under us.** Which upstreams may move, and where could this be published or mirrored? (#181, #187, #175)
8. **Contact-only properties.** What can only be verified in production or over time, and who owns that check?
9. **Deadline.** What is it, and what happens if it is missed (the negative branch)? (#179)
10. **Escape cost.** How many research days is one decision-changing hole found after build worth avoiding? This is Dalal–Mallows' c/f. The contract page states: *"c = ∞ means never deploy."*
11. **Tier.** Which tier, from the price curve (§3.7), and R_abs.
12. **Question frames.** Which of your historical re-ask frames matter here (§3.8)?

### 3.3 Superlative translation (a port of `skills/ground-up/SKILL.md:14-18`)

Every superlative becomes one or more acceptance (AM) rows. Each carries:
- a numeric predicate, and a ceiling measured first, as a P2 probe (hole 11: "maximally fast" was never compared with
  the engine's 0.14 s floor);
- a threshold, and a negative-result branch;
- for taste: a positive reference set, with the operator's eye as a dated E6 gate. A ban-list is never acceptance
  (hole 62).

Every hold carries an expiry (hole 56: a 21-day unanswered warm lead). The lint refuses any predicate matching
`perfect|100th|maximal|best|exhaustive|absolute|flawless` without a number. The superlative appears in 80 of 88
historical completeness asks (`reask_frames.py`), so without this step every future ask is unfalsifiable. The
operator's words are kept in `frame.json.intent_verbatim` and are never the predicate.

### 3.4 Frame registers

| Register | Content | Closure rule |
|---|---|---|
| **AM** acceptance | predicate with a number, check command, target environment, threshold, negative branch, planted-defect control | S6: shown red on known-bad and green on known-good |
| **DR** decisions | question, type (fact / design / taste), options (**must include do-nothing and use-what-exists**), premises, `what_would_flip`, **closure instrument** (desk, spike, model-check, tracer, prototype, load-fault, deploy-rehearsal, operator-eye), **reversibility** (reversible / costly / irreversible), timebox, VOI rank | S5 |
| **Premises** | every factual claim a DR or AM row rests on, with `truth_lives_in` and a **computed** required tier (§4.1) | S4 |
| **Censuses** | the populations the checklist (§3.5) requires; two are grids | S2 |
| **Sources** | every evidence source: our stores **and** those we do not write (upstream trackers, registries, vendor rules pages, access and production logs, the public web, operator tenants) | S3. Completeness is stated relative to this list (Zowghi & Gervasi) |
| **Contact matrix** | components × H1–H7, with the instrument named per applicable cell | S7 |
| **Residual** | what research on this machine cannot settle | S11 |
| **CUs** | certification units of ≤ 1,500 lines each, plus one **seam unit** per boundary with a sibling plan (LIMIT_DETECT dropped the request writer at such a seam, `LIMIT_RECOVER_100P.md:772-777`) | used to scope reopens |
| **Strata** | FACT (C3, C10 facts) · COVERAGE (C4, C6, C1 omissions) · VALIDITY (C5, C7, C8, C11) · CONTACT (C9; covered by S7, outside the statistical estimate) · FRAME (C2; intake plus change requests) | estimates per stratum once it holds ≥ 12 found holes, pooled otherwise |

**Frame-size rule.** Keep 7–10 decision groups at the top level, so the frame stays reviewable for omissions (STPA
Handbook pp.19–20).

**Coverage is computed, never set by hand.** An axis is covered when its checklist row maps to at least one register
row, or to a quoted exclusion. Depth is then tested by the certification panels' lenses. The judges faulted FCR's
self-set "meaning-saturated" status; it is not used here.

### 3.5 Frame Axis Checklist (FAC v0, 32 rows)

Each row is FCR's HPC-01…30 plus two RCF axes. Every frame maps each row to a register row, or marks it N/A with a
reason. The checklist lives at `docs/research/frame-axis-checklist.jsonl`, and **every post-gate frame defect adds a
row**. Hole ids are rows of `taxonomy_holes.py`.

| FAC | Axis the frame must carry | Holes |
|---|---|---|
| 01 | Options include do-nothing and use-what-exists | 110, 120, 68 |
| 02 | Candidates enumerated from the artifact itself (repo, fork, installed), never from memory | 173, 69 |
| 03 | Upstream or base version as an explicit DR; upstream tracker as a source | 181, 182 |
| 04 | Instance census: every checkout, copy and deployed instance | 88, 102 |
| 05 | Caller and consumer census keyed by *name*, not path | 90, 44 |
| 06 | Execution contexts: deployment interpreter, scheduler, CI/build OS, real device vs simulator | 92, 91, 95, 153, 41 |
| 07 | Liveness and expiry: where it runs, what keeps it alive, what expires, who re-authenticates | 168, 96, 16, 170 |
| 08 | Concurrency and the fleet case: concurrent actors, N > 1, generator vs UI races | 193, 126, 142 |
| 09 | Publication surfaces: mirrors, forks, jobs that push | 175, 187, 190 |
| 10 | Operator-owned accounts, tenants and devices | 147, 134 |
| 11 | Evidence beyond our own stores: access logs, trackers, the public web | 57, 111, 182 |
| 12 | Prior invariants, each with a guard test | 159, 141 |
| 13 | Handed commands run by the agent under the real invocation (`!`, no TTY, launchd) | 155, 91, 156 |
| 14 | Platform and feature-support matrix | 33 |
| 15 | Deliverable consumer and install path | 198 |
| 16 | Operator-private relationships and agreements | 194, 107 |
| 17 | Hazard census: write paths to live data, destructive instruments, irreversibility | 10, 90, 126 |
| 18 | Seams with sibling plans: an owner for every producer and consumer | `LIMIT_RECOVER_100P.md:772-777` |
| 19 | A measured ceiling for every performance or superlative target | 11, 15 |
| 20 | Positive reference set for taste | 62, 65, 66 |
| 21 | Pre-registered thresholds and a negative-result branch | 179 |
| 22 | Every hold carries an expiry | 56 |
| 23 | Freshness: sibling trunk activity, registry releases, credential validity | 119, 165, 103, 164, 96 |
| 24 | Research probes never mutate the live subject | 49 |
| 25 | Compliance and data residency for external deliverables | 87 |
| 26 | Real artifacts, n > 1, a load control | 191, 53 |
| 27 | Property list includes liveness and recovery; every fix re-checked by the instrument that found the bug | AWS (Newcombe 2014 pp.3); C7 |
| 28 | Emergent load and feedback behavior exercised on a running thin slice | AWS p.5; 191 |
| 29 | Deploy rehearsal, rollback and kill switch designed before build | Knight Capital (SEC 2013-222); 95, 121 |
| 30 | Source register reconciled: every source consulted or N/A with a reason | 57, 111, 182 |
| 31 | Decisions settled by default (freeze clauses, shipped-OFF defaults) registered and ruled | 181, 192 |
| 32 | Cost and quota of building and running the deliverable measured, not estimated | 109, 162 |

### 3.6 Materiality rubric (one rubric, used everywhere, fixed at intake)

A finding is **MATERIAL** only if it carries a locus (file:line or a verbatim quote), names a registered id, and does
at least one of these:
- **(a)** changes a DR's chosen option, or drops its conviction below 90;
- **(b)** changes an AM row's verdict or threshold, or shows the row cannot discriminate;
- **(c)** changes sequencing, an interface contract, or a cost or timeline figure by more than ±20%;
- **(d)** adds a census member that a DR or AM row must cover, and that changes the row;
- **(e)** moves a load-bearing premise outside its tolerance;
- **(f)** is a safety, security, data-integrity or irreversibility hazard. This one is always MATERIAL: stop and surface.

The other levels:
- **REFINEMENT** improves detail without meeting (a)–(f). It goes to `apply-at-build` and is never integrated during
  certification.
- **COSMETIC** is logged.
- **GENERIC** (no locus or no id) is logged and rejected.

**Deciding it (vote plus reproduction, never agreement alone):**
1. Verification comes first. A verifier reproduces the finding from the primary source through `probe-run`, **blind
   to how many panels found it**. The result is CONFIRMED, REFUTED or CONTACT.
2. Rater 1 (Opus xhigh) rates every confirmed finding. Rater 2, from a different family, rates every singleton, every
   finding rater 1 calls MATERIAL, and a 20% sample of the rest. Rater 3, from a third family and blind to the other
   two, rates only disagreements.
3. The finding is **MATERIAL** when at least 2 of the raters say so **and** its claimed consequence (the DR or AM flip,
   or the >20% move) is reproduced by a probe or a primary read.
4. If 2 or more raters say MATERIAL but the consequence cannot be reproduced, **one** further reproduction probe runs
   (L10). If it still cannot be settled, the finding is **MATERIAL-DISPUTED**:
   - it is named on the certificate;
   - it does **not** reset the dry count;
   - it is applied at build;
   - if it names an irreversible DR, it joins that DR's build-wave-1 narrowing probe.
5. If fewer than 2 raters say MATERIAL, it is a REFINEMENT.

**Why disagreement is not MATERIAL.** A false MATERIAL item breaks a dry run exactly as a real one does. At 0.25 per
round, build-tier rounds go from 9/12 to 10/17 (p50/p90); at 0.5, to 14/27 (`tier_curve.out` §D). Agents flag
something on correct artifacts at least 88% of the time (arXiv 2603.18740), and FixedBench measured action bias at
35–65%.

**Post-gate severity** (EASA AMC 20-189 classes):
- **SIGNIFICANT:** an (f), or an unmitigated flip of a signed irreversible DR. It pauses only the build waves inside its
  dependency closure.
- **FUNCTIONAL:** any other MATERIAL escape. A scoped fix runs while unrelated waves continue.
- **PROCESS / LIFE-CYCLE DATA:** never pause anything.

### 3.7 Tier and stop parameters (the price curve the operator buys from)

N₀ is the number of material holes still present at the first freeze. The front end (P1–P5) sets it: 20 means a
strong front end, 60 a weak one. The model uses b = 0.1, u = 0.05 and s = 100, with **no** false positives. Its
numbers are illustrative until W0 replaces them.

| Tier | Stop | Rounds p50/p90 (N₀ = 20 · 60) | Panel-runs p50/p90 (20 · 60) | Desk-detectable material left, mean / P(≥1) (20 · 60) | Source |
|---|---|---|---|---|---|
| decision | K=2, T=8 | 5/7 · 7/10 | 40/56 · 56/80 | 0.52/0.38 · 0.95/0.57 | `tier_curve.out` §A |
| build | K=3, T=8 | 7/9 · 9/12 | 56/72 · 72/96 | 0.33/0.27 · 0.62/0.46 | §A |
| wide | K=2, T=16 | 5/6 · 6/7 | 80/96 · 96/112 | 0.20/0.18 · 0.41/0.33 | §A |
| max | K=3, T=16 | 6/7 · 7/9 | 96/112 · 112/144 | 0.13/0.12 · 0.25/0.21 | §A (rerun in `synth_width.out`: 0.13/0.11 · 0.28/0.24) |
| wide24 | K=2, T=24 | 4/6 · 5/7 | 96/144 · 120/168 | 0.09/0.09 · 0.20/0.17 | `synth_width.out` |
| **max24 (recommended)** | K=3, T=24 | 5/7 · 6/8 | 120/168 · 144/192 | **0.06/0.05 · 0.15/0.14** | `synth_width.out` |

Holes no desk reviewer finds (universally blind) remain at **every** tier: about **1.1** at N₀ = 20 and about **3.3**
at N₀ = 60 (`synth_width.out`; `stopping_model.out` §2 gives 3.3–3.5).

**What the curve says about spending the operator's budget:**
1. **The front end is the cheapest assurance, and the only one that also shrinks the desk-invisible mass.** Moving N₀
   from 60 to 20 cuts max24's desk-detectable residual from 0.15 to 0.06 and the invisible mass from 3.3 to 1.1. More
   panels move only the first number.
2. **Width beats depth.** wide24 (K=2, T=24) leaves 0.20 at N₀ = 60 against max's 0.25 (K=3, T=16), at a similar
   panel-run cost, in 5/7 rounds against 7/9. Extra panels run concurrently; extra dry rounds run in sequence.
3. **Seeds buy the statement, not the residual.** At K=3, T=8, the median stated bound is 3 whether s = 60 or 300
   (`tier_curve.out` §B).
4. **False positives stretch the schedule.** max with 0.25 false MATERIAL items per round and a 16-round cap takes
   9/14 rounds at N₀ = 60 (`synth_width.out`). This is why §3.6 exists.

**Recommendation: max24.** The operator offered "ALL our time/tokens", and this is the tightest simulated tier. It needs
codex and gemini to sustain 6 panels each per round, which W0 measures. If they cannot, fall back to max. The contract
page states it plainly: *"At max24, about 1 program in 20 keeps at least one desk-detectable material hole with a
strong front end (about 1 in 7 with a weak one). Separately, about 1–3 holes no desk reviewer can see remain; only
contact reduces those. Every one that surfaces is counted against the bound printed at signoff."*

**Stop parameters** (ratified with the tier; the max24 defaults):

| Parameter | Default | Basis |
|---|---|---|
| T panels per round | 24: 4 families × 6 strategies, as 3 concurrent Workflow runs of 8 | the Workflow cap is `Math.min(16,Math.max(2,e-2))`, which is 8 on 10 cores, per run (`docs/research/orchestration-units-2026-08-19.md:116-120`) |
| families_min / non_anthropic_min | 3 / 1 | Chao & Tsay: 3 sources is the minimum for estimating dependence; Briand: fewer than 4 inspectors is unusable |
| K dry rounds | 3 | Guest 2020 run length 2–3; dry rounds alone are never trusted (§5.7) |
| Carried seeds s₀ | 60, survivor-matched, capped at 1 per 25 lines | the stated bound held 98.9% at s = 60 (`carried_seeds.out`) |
| Shadow seeds | 1 per applied fix, planted in its edited span | fix-born cohort |
| Escape seeds | 20, stratified by class | hard-tail gate, never a denominator |
| R_max | min(forecast p90 + 4, R_abs), fixed after round 1 | `forecast_check.out` |
| R_abs | 14 | max with 0.25 false positives per round and a cap of 16 reached a p90 of 14 (`synth_width.out`); T = 24 needs fewer rounds |
| fable_cap (program) | 10: frame critique 2, ladder ≤ 1, certification slots ≤ 5, sweep 2 | each phase session stays ≤ 6 (`~/.claude/model-config.yaml:1116`) |
| Overrun factor and default | 1.5×; class-B "proceed" at 24 h | L14 |

### 3.8 Question-frame map and the verdict vector

Every completeness question gets a **vector** answer. At intake, every historical question frame maps to an axis or
to a quoted exclusion (S1). Counts are regex counts over the 88 asks (`python3 /tmp/rescomp/design/reask_frames.py`).

| Axis | Computed from | Historical frames mapped |
|---|---|---|
| V1 Research | gate plus certificate | correct/complete/covering (51), researched/exhausted (30) |
| V2 Decisions | open DR rows, carried sets with narrowing dates, class-C carried rows | decisions/steps outstanding (17) |
| V3 Residual scheduled | `residual.jsonl`, owners and dates | — |
| V4 Escapes since signoff | challenge triage, per stratum, against n_pred95 | no take-backs/final (5) |
| V5 Loose ends | S12 store reconciliation, computed | no loose ends/follow-ons (6) |
| V6 Built | harness rows green after build | all waves/master plan (1) |
| V7 Deployed and live | live content-read rows, not deploy status (the Denver lesson) | deployed and live (20) |
| V8 Optimum | ceilings measured and met | optimum/"nothing can beat it" (6) |
| V9 Session | the wrap-ledger rung | good to close/done (15), saved/persisted (3) |

The catchphrase "100th percentile / perfection" (80 of 88) maps to no axis; §3.3 translates it.

### 3.9 Bounded frame critique: the only open-ended "what is missing?" in the protocol

- **Two pre-declared rounds**, each of **6 blind panels across ≥ 3 families**. At least 1 is non-Anthropic, and Fable
  takes 1 slot per round.
- The panels read the **registers, the censuses, the contact matrix and the FAC map, not the prose**, because critics
  audit what a plan says, not its unstated premises (`shard-7.md` pattern 1). C4, the class with the most
  decision-changing holes (22 of 32), lands exactly there.
- Zero is an expected answer. Every proposed row cites a locus and the DR it would affect.
- An adjudicator dedups, and the lead **integrates by Edit**, never appending.

The negative-space trigger runs **here and nowhere else**.

### 3.10 Ratification (operator-only, content-pinned, off the customer board)

- The frame files are landed on trunk. `cc-research frame render` produces one page: register counts, the definition
  of complete (§1), the tier with its price row, R_abs and the computed ceiling (§10.3), operator-owned dates, and
  *"c = ∞ means never deploy"*.
- The operator runs, in their own terminal, `cc-signoff research:<P>/frame --evidence <frame.json blob sha on
  origin/main>`. This is B7 (§12): cc-signoff's three arms factored into a library, plus a `research:` namespace backed
  by `~/.claude/autonomy/research/<P>/signoff.json`.
  - **Never `cc-decide`:** it has no agent guard (grep above).
  - **Never cc-mission:** research programs must not land on the customer board, whose rows outrank all work.
- **Interim, before B7 lands.** The operator types `ratify <P> frame <sha12>` as a genuine prompt in an **origin**
  session. It is recorded with the transcript path and record uuid, using the predicate at
  `hooks/enforce-email-formatting.py:688` (which mirrors `hooks/lib/cc-interactive.sh`) plus
  `hooks/lib/origin-identity.sh`. The certificate prints "interim ratification (weaker: detection only)".
- After signing, `frame.json` changes only through a change request (§8.4). One changed byte shows as "re-opened"
  until it is re-signed.
- The session DoD becomes one falsifiable line: `Scope (frozen): research program <P> frame v<n> (sha …) certified at
  tier <t> — proven by cc-research gate --program <P> printing CERTIFIED`.

---

## 4. The research loop, P1–P5

### 4.1 Rules that hold in every phase

1. **No quotas. Zero is valid.** Every finding carries a locus, the id it would change, and a frame class. A panel with
   a quota can never return a dry round, so any dry-round stop is unreachable by construction.
2. **Discovery and certification are kept apart.**
   - Discovery (P1–P5) is directed and adaptive, and sees prior findings. It **never** enters the estimation matrix,
     because adaptive search biases every estimator low (Böhme 2021).
   - Certification (P6) is blind, runs on a frozen snapshot, and measures.
3. **Evidence tiers are computed, never typed.** Probes run only through `probe-run`, which records the command,
   environment descriptor, stdin, n, raw output and negative control.

   | Tier | Meaning |
   |---|---|
   | E0 | recall |
   | E1 | secondary text |
   | E2 | primary static read |
   | E3 | live read with a TTL |
   | E4 | measurement: n ≥ 5, load control |
   | E5 | target-environment execution |
   | E6 | operator contact |

   The required tier follows `truth_lives_in`: code needs E2, current state E3, behavior E4, deployment behavior E5,
   and taste, intent or private facts E6. **E0 and E1 never close a load-bearing claim.** Inherited findings enter at
   their original tier until probed, because 43 of 158 plan moves were false when written (`plan-lifecycle.md` §3).
4. **Probes are safe.** `mutates_live=false`, or a sandbox (a throwaway label, sandbox HOME, `--dry-run`). A probe that
   must touch something live becomes a `cc-backlog needs --run` item (hole 49: a probe killed its own subject).
5. **Every probe that can fail is shown able to fail.** E4 and E5 probes run a negative control against a known-bad
   input or environment where feasible; otherwise they carry `control: none (<reason>)`, which the panels see.
6. **Everything persists in the project repo**, never in /tmp. The 15:26 reboot wiped `/tmp/rescomp`, which is the
   point; hole 76 is another case.
7. **Integrate, never append.** A single integrator records every edit list. "The integration is the generator"
   (`docs/lessons/integrating-review-findings-by-local-edits-manufactures-contradictions.md:14`).

### 4.2 P1: prior art, censuses, premises, sources

- **Censuses.** Every population the FAC requires gets `census/<pop>.json`:
  - built from a generating command plus a **second, independent method run by a different agent**, with the union
    reconciled;
  - with a coverage argument: how a missing member would show up;
  - checked **once** by a blind non-Anthropic census critic (L4), which names unlisted members, each with a locus that
    proves it exists.

  A census built from memory is inadmissible.
- **Grid censuses**, which show their own empty cells:
  - the **STPA hazard grid**: control actions and write paths × the four unsafe types (not provided, provided wrongly,
    wrong timing or order, wrong duration);
  - the **state × input grid**: every state machine × every input, including timeout, startup, shutdown and offline.

  A cell holds a scenario with a probe, or `n/a` with a reason.
- **Premises.** Every factual claim a DR or AM row could rest on, with `truth_lives_in`, a required tier, `recheck_cmd`,
  TTL and `validated_at_sha`. External dated facts are premises of kind `external-fact`.
- **Sources.** Each source is consulted by its access command, or excluded with the operator's quote.

### 4.3 P2: measure-first contact wave (CW), before design

The problem statements were usually wrong: 10 of 12 constraint cells were later falsified
(`plan-lifecycle.md` §5.3). The positive control is FLEET_V2's W0, after which W0–W6 landed in about 1.5 days. So the
contact wave runs **before** the decisions. It is one Workflow slot per probe, in this order:
1. **`probe-kit doctor`.** It resolves binaries through the *interactive* shell's PATH, because the agent's Bash and
   Workflow PATH is `/Applications/kitty.app/Contents/MacOS:/usr/bin:/bin:/usr/sbin:/sbin`, where `codex`, `gemini` and
   `shellcheck` read as absent although they are installed. It records interpreters (`/bin/bash` 3.2.57 for launchd),
   `env -i` scheduler emulation, OS version, container availability (the docker CLI panics today), cross-vendor CLI
   auth and credential expiry.
2. **The incumbent**, measured at n ≥ 5 with a load control (hole 12: ±20% load contamination).
3. **Every ceiling** named by a superlative predicate.
4. **Risky premises, in value-of-information order**: `priority = p(refute) × dependents × late_cost / probe_cost`.
   The p(refute) prior is 0.27 for E1-origin premises. Refutations then land while few decisions rest on them, which
   keeps L1 small.
5. **Every handed command**, run by the agent with stdin at `/dev/null` (hole 155).
6. **Credential and lock lifetimes** (holes 96, 142).

**Refutation-rate check.** If 0 of ≥ 20 risky premises are refuted, the probes were chosen to pass (Reinertsen). A
critic then re-samples 20% of the falsifiers, once. The rate is reported, not a quota.

### 4.4 P3: decisions

- **Options census** per DR: do-nothing, use-what-exists (hole 110), every option from any prior ranking re-read
  (hole 108), and every candidate already in the repo, never truncated by an unstated cap (holes 173, 69).
- **Trunk and siblings are re-read before any recommendation** (holes 119, 165).
- **Order and timeboxes.** Rows are researched in VOI order (Weitzman), each inside its intake timebox, using
  `/research` waves (N 8–12) with the zero-allowed brief. Every surviving option gets a probe, and `what_would_flip` is
  checked by a probe.
- **Depth follows reversibility and closure instrument:**
  - *reversible*: at most 2 runs, the cheapest defensible option, and a `revisit_trigger` for the build;
  - *irreversible with a desk instrument*: researched in the wave, then certified in P6;
  - *irreversible with a contact instrument*: closed in P4, or **carried as a set**.
- **A carried set** has 2–4 members, each with a feasibility probe; a narrowing probe dated in build wave 1; a
  pre-written branch per member; a revision budget in hours; and a `why_not_now` from the residual classes. A later
  elimination executes a signed branch and is never a take-back (Toyota set-based design).
- **Rulings:**

| Condition | Route |
|---|---|
| ≥ 90 conviction with a receipt | the agent rules; a class-A record |
| < 90 after exhaustive research, the residue is framing, and weekly-Fable headroom exists | frontier ladder stage 2 (Fable writes a document), then back to Opus |
| < 90 at the timebox, not an escalation surface | class B: `--default <recommended option> --deadline +48h --conviction N --receipt R` |
| < 90, touching an escalation surface (auth, destructive migration, navigation, DB timeout) or an operator value (money, a customer relationship, irreversibility) | class C, which never defaults. It is a **carried row**: it blocks only the build waves that depend on it, never the certificate, and appears in V2 as a dated operator wait |

`cc-decide expire-sweep` only *reports* a fired class-B default (`bin/cc-decide:480`). `cc-research` applies it and
records `ruled_by: packet-default`.

### 4.5 P4: executable spec, contact skeleton and the contact matrix

- **Acceptance harness** `docs/research/<P>/harness.sh`:
  - one row per AM row, echoing the command it ran and that command's own unpiped exit code;
  - `--self-test` must exit non-zero over `fixtures/known-bad/`, and `--self-test-green` must exit 0 over
    `fixtures/known-good/`. For a greenfield subject that does not exist yet, **the known-bad fixture is the planted
    defect**;
  - every row is classed SOUND, NOT-A-COMMAND, ALREADY-PASSES, BLIND-TO-MECHANISM, FAILS-GREEN, MUTATES-STATE or
    BROKEN-SYNTAX (the DOCS_CONSOLIDATION §9 taxonomy). Only SOUND rows and labeled regression guards are admitted.

  This is the pattern of the one plan that closed and stayed closed: 45 of 58 checks unsound before build, programme
  done in 25.75 h, never reopened (reso `DOCS_CONSOLIDATION_100P.md:2059-2099`).
- **Contact skeleton.** A throwaway worktree holding the thinnest end-to-end path, crossing every environment in the
  doctor's census once:
  - a **scheduler-initiated** launchd run under `/bin/bash` 3.2.57 (hole 92);
  - the target build image, or a declared `tooling-degraded` residual while docker is broken;
  - one real tenant call where research holds one;
  - real artifacts through the pipeline;
  - handed commands with no stdin.

  Its evidence is kept. Its code is thrown away, or adopted by build wave 1 only through that wave's own review.
- **Contact matrix cells.** Each applicable cell (component × H1–H7) needs an executed probe, a set record, or a
  residual entry. `n/a` needs a reason the frame critic saw.

  | Column | Class | Instrument |
  |---|---|---|
  | H1 | interleavings and recovery | small-scope exhaustive enumeration in stdlib Python by default, with safety **and liveness** properties; TLC/hypothesis only after an operator-approved install. **Every proposed fix is re-checked by the same instrument** (AWS found "a bug in the first proposed fix") |
  | H2 | emergent load | load on the skeleton at production n (synthetic rigs: FLEET_V2 W5's 5- and 30-session rig) |
  | H3 | model vs reality | a spike on the real dependency |
  | H4 | integration | skeleton end to end in the real configuration |
  | H5 | user-need validity | an E6 prototype or a reference set in front of the operator |
  | H6 | complex-domain unknowns | a set decision |
  | H7 | deployment state | dry-run deploy, rollback, kill-switch drill |
- **Fault injection** against every hazard-grid cell: kill -9 mid-write, quota death, network drop, reboot, partial
  write, TTL expiry via a time-compression probe.
- **Cost control (L14).** Cells are worked in VOI order inside P4's timebox. An overrun carries the remaining cells as
  named, dated rows that block only the build waves depending on them.

### 4.6 P5: synthesis, freeze, seeding

1. The plan is written **from** the ledgers by a single integrator.
2. `trace check`: every finding id in every research artifact maps to a plan anchor or a recorded rejection (holes 172,
   61, 77).
3. `reconcile`: plan-prose open markers, research residual sections, backlog, open decisions, custody and dirty files
   each map to done, not-required-with-reason, filed, or a row (C1).
4. `lint`: numbers consistent across sections, no superseded values, anchors that resolve, no /tmp paths, no numberless
   superlatives, every cited probe id exists.
5. A **fresh-context whole read** after the last edit, recorded as a probe (hole 180: a script-assembled plan held 20
   defects).
6. **Freeze** snapshot S₁. From here, edits happen only between certification rounds.
7. **Seeding** (§5.3).

---

## 5. P6: certification (the spine)

### 5.1 Panels: composition, invocation, isolation

**Composition at max24 (T = 24).**

| Slots | Family | Invocation |
|---|---|---|
| 6 | Anthropic, Opus 5.5 | `/opt/homebrew/bin/claude -p --setting-sources local --model <opus> --allowedTools "Read Grep Glob"` |
| 6 | OpenAI | `~/.local/bin/codex exec -s read-only` |
| 6 | Google | `~/Library/Application Support/fnm/node-versions/v22.21.1/installation/bin/gemini -p … --approval-mode plan`, with that node's `bin` on PATH |
| 6 | Anthropic-alternate | Opus with different strategies. Fable 5.1 takes 1 slot in odd rounds, within the cap |

- Each family runs 6 strategies: full context; spec-only (the plan without research docs); adversarial "assume it
  fails in production"; consumer; operability and security; registers-only (census, premises, contact matrix).
- Local `ollama` models (gemma4 26B, qwen3-coder 30B, devstral 24B) join only as **extra** slots. They count toward
  `families_min` only if their round-1 seed recall is at least 0.33 (RCF's admission floor).
- The simulated composition models Fable and Opus as correlated at ρ = 0.6. W0 measures the true correlation.

**Isolation** (enforced, not instructed):
- Every panel is a **separate CLI process launched by a courier slot** of the round Workflow. The courier relays the raw
  output verbatim and never filters it.
- Anthropic panels run with `--setting-sources local`, which the probe showed loads none of the operator's resident
  instructions.
- The panel's cwd is a **sanitized bundle at a fresh path per round**: `git archive <trunk_sha>` extracted into
  `~/.claude/autonomy/research/<P>/rounds/<k>/bundle/`. It has **no `.git`**, no `docs/research/<P>/`, no `.claude/`
  and no `CLAUDE.md`, plus the seeded plan and registers.
- Seeds are **encrypted at rest** (`openssl enc -aes-256-cbc`, key in the login keychain) and decrypted in memory only
  by `seed apply|match`.
- A **post-round integrity grep** checks panel transcripts and outputs for the real program path, the vault path and
  `git log`. A hit **voids** the panel (L6).
- Every prompt carries the snapshot sha and the bundle hash, because the Workflow resume cache key has no tree term
  (`docs/research/workflows-vs-teams-2026-08-20.md:364-367`).
- **Stated limit:** same-UID codex and gemini processes could still read the real repo, so their isolation is
  detection, not prevention (§11).

**Fable accounting.** Headless panels load no user hooks, and `frontier-spawn-gate.sh` is on the Agent matcher only.
So `cc-research panel run` keeps the program's own Fable ledger against `fable_cap` and checks `claude-accounts`
weekly-Fable headroom first. A refused slot becomes Opus, flagged on the certificate.

### 5.2 Panel brief (frozen; identical for all T panels)

> Audit the FROZEN bundle in your cwd against `frame.json`. Read-only. You will not see other reviewers' or earlier
> findings; do not look for them.
> Part 1: for each AM and DR row in scope, answer YES / NO / UNKNOWN, each with a receipt (a file:line you read). No
> receipt ⇒ UNKNOWN.
> Part 2: for each of the 11 lenses (premise, census, instrument, trace, consistency, sequencing, criteria, contact
> declaration, drift, frame-omission, operator-intent), state what you checked, then either findings or "nothing
> material".
> **Zero findings is a correct and expected outcome. You are not rewarded for finding something.**
> Each finding must carry:
> (a) a locus;
> (b) the DR/AM id it changes and how, or the sequencing, interface or cost figure it moves by more than 20%, or the
> hazard;
> (c) a read receipt;
> (d) your probability that it is real and material, plus the observation that would falsify it.

### 5.3 Seeds: carried, anchored, survivor-matched

- **Format.** A seed is a patch anchored on a verbatim quote: `{sid, cohort, class, file, anchor_quote (≥ 40 chars,
  unique), replacement, defect_statement, detect_span}`.
- **Application.** `seed apply` builds each round's bundle from the tracked, unseeded plan and applies every uncaught
  seed. The lead never sees seeds.
- **Mutation operators, one per class**, stratified to the desk-findable mix (C4 29, C3 26, C1 23, C5 13, C6 12, C7 8,
  C8 8, C11 4, C10 3):
  - C3: contradict a load-bearing figure;
  - C4: delete a proven population member;
  - C5: swap a check for one that cannot fail;
  - C6: drop the plan item a finding requires;
  - C7: change one restatement of a value;
  - C8: move a verification after a land;
  - C10: insert a stale dated fact;
  - C11: replace a number with a superlative;
  - C1: drop an open item from the reconciliation.

  C2 and C9 are not seedable and sit outside the statistical certificate.
- **Cohorts:**
  - **Original**, s₀ planted at S₁ and carried to the end.
  - **Shadow**, one per applied fix, planted in its edited span and carried. Shadow seeds age exactly like the fix-born
    holes (C7) they stand in for.
  - **Escape**, 20 transplanted *mechanisms* from `docs/research/escape-library/escapes.jsonl`. They form a hard-tail
    gate and are never a denominator: as a denominator they overestimate about 2.5×.
- **Survivor-matched.** The seed author, a family different from the lead's and never a panelist, writes about 2× s₀
  candidates. A blind discovery-style pre-screen discards the ones it catches. Against fresh seeds the bound held
  95.5%; after the pre-screen, 98.2% (`seed_realism.out`).
- **Realism, checked twice and bounded:**
  - a third-family discriminator on 20 blind (seed span, real span) pairs. Above 70% correct means one rewrite (L7);
  - a round-1 Mann–Whitney capture-count test, which flags at z > 1.645, with a false-alarm rate of 4–6%. A flag
    prints "μ̂ likely low; the bound stands".
- **Orphans are censored.** A fix that rewrote a seed's anchor removes the seed from its cohort's denominator. This
  widens the estimate without biasing it (`tier_curve.out` §E: 98.3% and 97.7% hold rates).
- **Caught.** A finding whose locus overlaps `detect_span` and whose claim matches `defect_statement` catches the
  seed. A script proposes the match; one seed-aware judge confirms it and may return the finding as real.

### 5.4 Adjudication, verification and fixes

1. **Dedup adjudicator** (Opus xhigh, blind to panel identity, detection counts and seeds): clusters findings into
   candidate holes and logs every merge and split.
2. **Verification and materiality** follow §3.6. Singletons are verified and **never culled** for being singletons
   (Deng 2024).
3. **Fixes are MATERIAL-only, between rounds, by integration.** A fresh consistency reader then reads the edited spans
   and their dependents; its finds are discovery and never enter the matrix. Every fix to an H1-checked design is
   re-checked by the same instrument.
4. REFINEMENT, COSMETIC and MATERIAL-DISPUTED items are **not** integrated during certification. They go to
   `cc-backlog add --why-not-now "not-yet-true: build wave <n>" --dod-ref …`. Refinements therefore cannot create
   fix-born holes.

### 5.5 Estimators (`cur_estimate.py` / `cc-research estimate`; each has a planted-input test that must go red)

- **Primary: the carried-seed posterior predictive**, per cohort. With s_eff = planted − orphaned, k_left = uncaught,
  and F = verified MATERIAL real holes attributed to the cohort:
  - π ~ Beta(k_left + ½, s_eff − k_left + ½);
  - R | π ~ NegBin(F + 1, 1 − π);
  - cohort draws are summed for the total;
  - μ̂ = F·π̃/(1 − π̃), with π̃ = (k_left + 0.5)/(s_eff + 1);
  - the stated bound **n_pred95** is the 95% quantile of R, and P(≥ 1) is read off the same draws.

  n_pred95 held 97.8–100% at s = 20–300 and N₀ = 20 and 60. Fresh end-of-process seeds held only 71–87%
  (`carried_seeds.out`, `cert_calibration.out`).
- **Cross-checks and forecast inputs:**
  - bias-corrected Chao2, S + ((T−1)/T)·Q1(Q1−1)/(2(Q2+1));
  - jackknife 2, S + ((2T−3)/T)Q1 − ((T−2)²/(T(T−1)))Q2;
  - per-family Chao2;
  - the family × family co-detection matrix, recorded to `research-calibration.jsonl`;
  - a log-linear dependence model once ≥ 3 families are present.

  These are all biased low under positive correlation. They are never gated on.
- **Coverage is never reported as "percent complete"**: in simulation it read 0.976 when 83% had been found.
- **Fix-born rate:** b̂ = verified MATERIAL holes in round k+1 inside round k's edited spans ÷ fixes in round k.

### 5.6 Forecast, R_max and divergence

- **After round 1**, `forecast` simulates the program forward, 150 programs, from:
  - N̂₀ = JK2 of the round-1 matrix (median 1.03× the truth in simulation);
  - R̂ = round-1 original-cohort recall, mapped through the calibration table in `forecast_check.out`;
  - b̂, from a prior of 0.1.

  It prints p50/p90 rounds and panel-runs. R_max = min(p90 + 4, R_abs) is fixed and dated. The closed form is not used:
  it held in only 5–17% of programs.
- **Every round re-forecasts** and plots a burndown. R_max never moves except by the operator's `extend`.
- **Divergence.** Run the delete-machinery step when either condition holds:
  - b̂ ≥ 0.5 at round 3 or later;
  - the found-count ratio is ≥ 0.7 over two consecutive rounds while counts are still ≥ 5.

  The step: delete machinery or restructure the offending CU (`/ground-up` on that unit), **never** another round of
  the same. Those rounds spend the same R_max. The evidence:
  - b = 0.6 takes 15/21 rounds;
  - b = 0.9 fails to stop within 40 rounds in 29% of programs;
  - b = 1.2 reproduces the 23/21/24/28 signature (`stopping_model.out` §4–5).
- **N̂₀ far above what discovery expected** means the structural gates passed too early. That stratum gets one return
  to P1–P4 (L11).

### 5.7 The stop rule (the only one)

**Stop at the end of round r ≥ K + 1 when the last K rounds were dry: `stop=dry`.** A dry round has 0 new verified
MATERIAL findings, real or false, on the same snapshot sha. MATERIAL-DISPUTED does not reset the count, and a dry round
makes no edits. **Otherwise stop at r = R_max: `stop=cap`.** The last round's finds are fixed and consistency-read, and
the certificate names them.

Both stop reasons certify. The cap costs no measured residual: at 0.25 false positives per round, cap-stopped programs
left 0.41 desk-detectable holes, against 0.67 for dry-stopped ones (`tier_curve.out` §D).

K dry rounds decide *when* to stop; the carried seeds decide *what the stop is worth*. Neither is stated without the
other. A quiet run alone matched only 69–89% of themes (Guest 2020), and "50 consecutive irrelevant" missed its target
in 39% of runs.

### 5.8 Re-ask rehearsal and Fable sweep (after the stop, once each, inside the caps)

- **Rehearsal (L12).** 12 blind courier sessions, mixed families. Each gets **one historical frame as a lens** (for
  example "deployed and live", "nothing can beat it"), the certified bundle and the verdict render. **Never** the
  operator's literal challenge wording: "Are you sure?" flips answers 46% of the time (FlipFlop). Each answer is typed:
  - answered by axis Vn;
  - an unmapped frame: a class-B packet, default "exclude, quoting intake Q5", which the operator may reverse by
    `amend`;
  - an in-frame MATERIAL candidate: §3.6 triage. A verified one is fixed, then ≤ 2 delta rounds follow.
- **Fable sweep.** 2 baseline-blind `frontier-derivation` panelists read the certified bundle
  (`skills/frontier-run/SKILL.md:116-137`). NEW items go through challenge triage. If NEW MATERIAL exceeds a stratum's
  n_pred95, that is a **calibration breach** (§8.3).

---

## 6. The exit gate: exact criteria

`cc-research gate --program <P> [--phase Pn]` prints `S<n>|Q<n> PASS|FAIL|FILED <evidence>`. Every predicate reads the
ledger and re-executes what it names in this run. UNKNOWN fails.

### 6.1 Structural rows (each PASS, or FILED as a carried row with an owner, a date and the build waves it blocks)

| Row | Criterion |
|---|---|
| **S1 Frame** | `sha256(frame.json)` equals the signoff pin. 0 lint hits for numberless superlatives. Every AM row has `check_cmd`, a threshold and a negative branch. Every FAC row (32) is mapped or N/A with a reason. All 11 question frames are mapped or excluded with a quote. 0 open change requests |
| **S2 Census** | Every FAC-required population has a census with **≥ 2 independent methods**, whose generating commands, re-run now, reproduce the member set (any diff dispositioned). Option censuses contain do-nothing and use-what-exists. Grid censuses have **0 empty cells**. The census critic ran once per population, and 0 verified members are unintegrated |
| **S3 Sources** | Every source is `consulted` (access command run, evidence path exists) or `excluded` with the operator's quote |
| **S4 Premises** | Load-bearing premises with achieved tier < required tier: **0** (computed from `probes.jsonl`). Verdict `unknown`: 0. Every refuted premise's dependents are REVISED. The refutation rate is reported; 0 of ≥ 20 needs the 20% falsifier re-sample on file |
| **S5 Decisions** | **0 open** DRs. Each is ruled (≥ 90 plus receipt, `what_would_flip` probe-checked), ladder-ruled, operator-ruled, `packet-default`, or carried: a set meeting §4.4, or a class-C carried row. Reversible rows used ≤ 2 runs and have a revisit trigger. FAC-31 defaults are registered and ruled |
| **S6 Instruments** | This run: `harness.sh --self-test` exits ≠ 0 over known-bad **and** `--self-test-green` exits 0 over known-good. 0 non-SOUND rows except labeled guards. Every row has a red-proof probe. Timing rows have n ≥ 5 and a load control |
| **S7 Contact** | Every doctor environment is crossed by ≥ 1 skeleton, measure or dry-run probe. Every scheduled component has ≥ 1 **scheduler-initiated** run. Every handed command ran with stdin at `/dev/null`. Every applicable H1–H7 cell holds an executed probe, a set record, or a residual. Every H1 property list includes ≥ 1 liveness property. Every E4/E5 probe has a negative control or a stated reason |
| **S8 Trace and persistence** | `trace check`: 0 unmapped findings. 0 cited paths outside the repo. Every evidence path exists at the snapshot sha. The index search is recorded. The topic lock is positive |
| **S9 Integrity and freeze** | `lint` 0 errors. A fresh read after the last edit found 0 MATERIAL. The certifying snapshot sha equals the plan sha. There is no post-freeze edit without a following round |
| **S10 Freshness** (≤ 24 h before the gate, and again at build start) | Every `recheck_cmd` re-run. Trunk commits since `validated_at_sha` touching any `depends_on_paths` are dispositioned. Credentials are valid for the build window plus 7 days |
| **S11 Residual** | Every residual row has an allowed `why_unreachable` (production-traffic, external-tenant-not-held, elapsed-time, operator-eye, or tooling-degraded with a `cc-backlog needs` id), a closest probe already run, a verify command, an owner, a due date, and a backlog id with a falsifier |
| **S12 Reconciliation** | 0 unmapped items across plan-prose markers, research residual sections, `cc-backlog list --project`, `cc-decide list --open` (project), custody and dirty files |
| **S13 Panels** | Every counted round had T_eff = T complete panels, with every lens attested, ≥ 3 families and ≥ 1 non-Anthropic. Integrity-grep hits in counted panels: 0. Void and dead slots were re-run (L6) or the next family took them, with "reduced diversity" printed |
| **S14 Rehearsal** | 12 of 12 frames typed. 0 unmapped frames without a disposition. Every verified in-frame MATERIAL find was fixed, with ≤ 2 delta rounds |

### 6.2 Statistical rows (stated on the certificate; none can block)

| Row | Stated |
|---|---|
| **Q1 Stop** | `stop=dry` or `stop=cap`, the round count against the forecast, and R_max with its date |
| **Q2 Residual** | μ̂, n_pred95 and P(≥ 1) per stratum and in total, beside the tier forecast bought at intake. If n_pred95 exceeds the p90 of the forecast's simulated bound, it is flagged **below tier**. That opens a class-B packet offering `extend` at its quoted price, default "accept as issued" at 24 h |
| **Q3 Fix-born** | the b̂ series and the found-per-round series |
| **Q4 Hard tail** | escape-seed recall per class with ≥ 3 seeds. Below 0.5 gets one structural detector attempt (L8), then a named **weak lens**. Also reported per family: Anthropic recall well above non-Anthropic on escape seeds but not on original seeds suggests contamination |
| **Q5 Adjudication** | dedup and materiality κ on the rater-2 sample, with one re-pass below 0.7 (L9) |
| **Q6 Realism** | the discriminator result and the Mann–Whitney flag |
| **Q7 Calibration** | "uncalibrated" until W0 reports, then W0's measured hold rate beside the 95% claim. No multiplier is applied, because calibrating by k multiplies variance by k² (Briand 2000) |
| **Q8 Budget** | actual against forecast per phase; every overrun packet resolved or `expired-actioned`. Informational |

### 6.3 Verdict states and the overrun rule

- **CERTIFIED:** every S row PASS or FILED, Q1 reached, Q2–Q8 stated. The stop reason, carried rows, degradations, weak
  lenses and disputed items are printed.
- **NOT CERTIFIED:** rows still in work inside their phase budget.
- **STALE:** a post-issue S10 re-check failed. It re-validates dependents only (§8.1, drift).

**Overrun (L14).** A phase at 1.5× its budget files:

`cc-decide open --class B --what "Phase P<n> of <P> is at 1.5x budget: <open rows>" --option "extend::<N> more runs" --option "proceed::open rows become carried rows, owned and dated" --default proceed --deadline <+24h> --conviction N --receipt <gate output>`

On `expired-actioned`, `cc-research` converts the open rows to carried rows. The program therefore **always** reaches a
verdict, naming what it carries, unless the operator vetoes. A build wave fires only when no row in its dependency
closure is open or carried-unresolved: `handoff-fire.sh --requires-gate <P>`, B10.

### 6.4 The certificate (`cc-research verdict --render`; the numbers are illustrative)

```
Research: CERTIFIED (3 dry rounds in a row). Program <P>, frame v3 signed 10-02 (sha a1b2…), snapshot 9f8e…, trunk <sha>, 10-16 14:05.
V1 Frame 100.00% closed: 16/16 decisions (1 carried set, narrowed in build wave 1 on 10-18) · 12/12 censuses, 2 methods each, 0 empty grid cells ·
   58/58 acceptance rows sound, shown red first, re-run 10-16 · 71/71 premises at required tier · 14/14 sources consulted · 32/32 checklist rows mapped.
   Stated relative to the 14 sources you signed; a new source is a scope change, not a miss.
V1 Certified: 6 rounds × 24 blind reviewers, 4 model families; 41 decision-changing holes found and fixed; last 3 rounds found 0.
   Estimated desk-detectable decision-changing holes still present: 0.1 · at most 1 (95%) · 7% chance of at least one — UNCALIBRATED until W0.
   You bought max24: forecast 0.06–0.15 left, 5–14% chance of at least one; this certificate is within it.
   Hidden test defects caught 58/60; realism check passed; past-escape defects 18/20; weak lens: none. Disputed: H-52 (applied at build).
V2 Decisions: 0 open; 1 carried set (sync backend, narrowed 10-18); 0 awaiting you.
V3 Scheduled, not open: 3 production/tenant/time checks, owners and dates in residual.jsonl. Degraded: no Linux build image (docker CLI broken).
V4 Since signoff: 1 challenge (relabel of H-12), 0 escapes (bound 1).  V5 Loose ends: 0 unmapped across 6 stores.
V6 Built 0/58 · V7 Live – · V8 Ceilings 3/3 measured, 2/3 met.  V9 Session: ✅ (wrap-ledger).
No new critique was run to answer this. Verbs: cc-research challenge (a specific concern) · extend --rounds 2 (≈+0.02 holes, ≈6 h) · amend (new scope, priced).
100.00 would mean examining every possible hole location; the target you signed on 10-02 is max24.
```

---

## 7. Answering "are we 100.00/100.00 complete?"

The operator asks as often as they like and gets the same computed answer. Each ask reads stores; it never draws a new
sample. That makes repeated asking anytime-valid: a monotone escape counter crosses a threshold fixed at signoff at some
ask if and only if its final value exceeds it.

1. **Detect from any pane.** `hooks/research-precognition-nudge.sh`, already registered on UserPromptSubmit, gains a
   branch:
   - it matches the completeness regex: `Q` from `/tmp/rescomp/internal/ca_scan.py:6`, copied into the repo because
     /tmp is reaped, widened with `100th|perfect|exhaust|take[- ]?back|nothing left|good to close`;
   - it resolves the program from `~/.claude/autonomy/research/programs.json` (named in the prompt, the cwd's repo, or
     the single active program; otherwise one status line per active program);
   - it injects `cc-research verdict --render` with the instruction: *"RELAY VERBATIM, then at most 3 lines. Do not
     start a critique, a fresh-eyes review, or a new panel. A specific concern is filed with `cc-research challenge`;
     report its triage."*
2. **Before the certificate exists,** the same render shows the progress vector: the phase, open rows per register,
   and the forecast date. "Not yet" is then a computed answer that names the rows, never a fresh audit.
3. **Only deterministic checks run on an ask:** TTL-expired `recheck_cmd`s and the trunk diff on `depends_on_paths`.
   Live-environment harness rows are **not** re-executed per ask; the render cites their last scheduled run with a
   timestamp. A red live row is re-run n = 3 and counts as drift or flake unless it is red in 2 of 3.
4. **Idempotent.** An identical ask re-renders the same words, marked "unchanged since HH:MM", and appends to
   `verdicts.jsonl`.
5. **Three verbs, no fourth:**
   - `challenge`: a specific concern (§8);
   - `extend --rounds m` / `raise --tier`: prints the expected yield μ̂·(1 − (1 − ρ̂)^m) and its cost first, then runs
     pre-registered rounds on the certified snapshot. Those looks are counted (Lewis 2021), and it is never a reopen.
     If every carried seed is already caught, the quote says more rounds cannot tighten the statement;
   - `amend`: new scope, priced (§8.4).
6. **Symmetric Stop arm** (`hooks/completion-assert.sh`, beside D3/D4; warn-only until AD3). While a certificate
   exists, a reply to a completeness ask:
   - may say **"no" or "not yet"** only if it cites a challenge whose triage is `escape` (reproduced and MATERIAL), a
     failed S10 row from this turn, or a change-request id;
   - may say **"yes"** only if it relays a render from this turn.

   **A pending challenge does not withdraw the certificate.** The answer is "Certified; CH-7 filed, triage pending;
   it would change DR-3 if confirmed." This closes RCF's hole, where a "no" could cite a hole filed in the same turn
   and still unreproduced. The existing false-done arm extends to `gate` exiting non-zero.
7. **Two verdicts at every close.** `scripts/wrap-ledger.sh` gains a `GOAL` field (`CERT=valid|stale|absent|failed`
   plus the tier) from `cc-research verdict --machine`. Line 1 keeps the session rung, and `Goal:` is its own line.
   The absent-DoD ✅ at `:2286-2288` becomes "unknown". `/are-we-done` gains the same `Goal:` line.

---

## 8. After the gate: typed change control, never a global reopen

### 8.1 Challenge triage (`cc-research challenge --locus … --names … --text …`)

Build-time discoveries, rehearsal and sweep findings, and operator concerns all enter here, and each is checked
against the ledger first.

| Triage | Test | Action | Counted as an escape? |
|---|---|---|---|
| generic | no locus or no id | logged | no |
| refuted | the verifier cannot reproduce it from the primary source | logged | no |
| relabel (C1) | matches a hole, residual, backlog or reconciliation row. Re-raising needs evidence dated after that row's disposition | answer with the row | no |
| immaterial | fails §3.6 | `apply-at-build` | no |
| frame defect | the frame should have held it (a C4 or C2u pattern). **Tie-breaker:** if its evidence came from a source not in `sources.jsonl`, it can never be an in-frame miss | change request `cause=frame_defect`; adds a FAC row | no, counted against the frame's P0 |
| frame expansion (C2n) | a new requirement | change request `cause=operator_new` (§8.4) | no |
| contact residual realized (C9) | a `residual.jsonl` row | run its verification in its slot; a failure reopens only its dependents | no (budgeted) |
| set narrowing | a carried set's narrowing probe ran | apply the winning member's pre-written branch; charge the revision budget | no (planned) |
| drift (C10) | a recheck differs after `validated_at` | re-run the probes; re-verify dependents via `supports` / `load_bearing_for`; re-certify the affected CU only if a DR or AM verdict changes | no (dated) |
| **escape** | an in-frame, reproduced MATERIAL miss (C3–C8, C11, C2u) | §8.2 | **yes** |

### 8.2 Escape handling

1. Compute the dependency closure from `trace.jsonl` (`impact H-x`).
2. Assign severity (§3.6). SIGNIFICANT pauses only the build waves inside the closure; FUNCTIONAL pauses none.
3. Fix by integration, then run the consistency read on the edited spans and their dependents. H1 cells re-check the
   fix with the same instrument.
4. Run one **delta round**: T/2 blind panels across ≥ 2 families, on the edited CU plus the stratum's lens, with a shadow
   seed in every edited span. A non-dry delta round gets its finds fixed and one more delta round. **Cap: 2 per escape**
   (L13).
5. Re-issue the certificate as v(n+1). It names the escape, and V4 shows the stratum count beside its n_pred95.
6. Add the mechanism to the escape library, and write one line in `docs/lessons/` naming the lens that missed it.

### 8.3 Take-back: the certificate's calibration failing

The same verdict applies in three cases:
- a stratum's escape count exceeds its n_pred95;
- a Fable sweep's NEW MATERIAL exceeds that bound;
- a structural row is shown to have been false when certified (for example a census missing a member that existed).

That stratum alone is re-certified from its census and premise registers upward, with its own new R_max. The event is
reported as a **take-back**: on the certificate, in `research-calibration.jsonl`, and in `docs/lessons/`. Because the
counter only grows and the threshold is fixed at signoff, reading this test at every ask does not inflate its error.

### 8.4 Change requests: a baseline with a presumption against change

`changes.jsonl` records every post-signoff change. Each carries a `cause` (`operator_new`, `operator_unelicited`,
`frame_defect`, `reality_moved`, `escape`) and a justification: the decision it changes, its price in rounds and days
(re-computed through §10.3), and why the signed frame could not hold it.
- **Operator-originated changes** are accepted by the operator's own prompt, recorded like interim ratification. They
  are logged as `Scope (grown, cause=operator)`, not scored as take-backs, and run as a **mini-program** on the new axis:
  its own censuses, premises, contact cells and one certification round on the affected CUs.
- **Agent-originated changes** go to the operator as a class-C packet with the price.
- **A descope** runs through the same path and is priced as a saving.
- **Why the burden sits on the change:** GAO found 72% cost growth in programs that changed requirements after
  development began, against 11% in programs that did not (FY2009 NDAA §814, `systems-engineering.md` §6).
- The amended `frame.json` is re-signed. The content pin reopens only the changed bytes.

---

## 9. Artifacts and schemas

**Project repo, tracked** (`docs/research/<P>/`). Stores are append-only event logs and state is the fold, as in
`cc-backlog`. JSON is used because models are less likely to rewrite it (`llm-failure-modes.md` T2). Markdown is
rendered, never hand-edited.

```
FRAME.md  frame.json  intake.md  intake-mined.md  sources.jsonl
decisions.jsonl  premises.jsonl  census/<pop>.json  contact_matrix.json
probes.jsonl  evidence/<probe-id>/{cmd,stdout,stderr,env.json}
acceptance.json  harness.sh  fixtures/{known-bad,known-good}/
residual.jsonl  trace.jsonl  holes.jsonl  rounds/<k>/matrix.json  rounds/<k>/panels/<pid>.json
cert/CERT-v<n>.{json,md}  challenges.jsonl  changes.jsonl  verdicts.jsonl  budget.json
```

**Sealed, outside every repo, mode 0700:** `~/.claude/autonomy/research/<P>/`, holding `vault/seeds.enc`,
`rounds/<k>/bundle/` (a fresh path per round), panel transcripts and `signoff.json`. Their hashes are committed into
`matrix.json`, so the vault can be audited afterwards without being exposed during the program.

**Machine-wide:**
- `~/.claude/autonomy/research/programs.json`: program → repo, status, certificate path.
- Tracked in claude-infrastructure: `docs/research/INDEX.jsonl`, `frame-axis-checklist.jsonl`,
  `escape-library/escapes.jsonl`, and `research-calibration.jsonl` (one row per program: family co-detection matrix,
  per-family recall, realism, forecast against actual, escapes against bound, quota % per panel-run).

```jsonc
// frame.json (pinned by cc-signoff research:<P>/frame)
{ "program": "slug", "version": 3, "intent_verbatim": "…", "deliverable": "one sentence, numbers, no superlatives",
  "consumer": {"who": "", "installed_by": "agent|human|ci", "runs_where": "env id"}, "deadline": "YYYY-MM-DD",
  "am": ["AM-01"], "dr": ["DR-01"], "components": ["sync daemon"],
  "fac_map": [{"fac": "FAC-24", "row": "N/A", "reason": "no live subject"}, {"fac": "FAC-06", "row": "K-03"}],
  "exclusions": [{"what": "", "operator_words": ""}],
  "reask_map": [{"frame": "deployed and live", "axis": "V7"}],
  "cus": [{"id": "CU-2", "spans": ["PLAN.md:1-1400"]}, {"id": "CU-seam-1", "between": ["PLAN.md", "SIBLING.md"]}],
  "materiality": {"rubric": "CUR-2"}, "strata": ["FACT", "COVERAGE", "VALIDITY"],
  "tier": {"name": "max24", "T": 24, "K": 3, "families_min": 3, "non_anthropic_min": 1,
           "seeds": {"original": 60, "shadow_per_fix": 1, "escape": 20}, "R_abs": 14, "R_max": null, "fable_cap": 10,
           "forecast": {"residual_mean": [0.06, 0.15], "p_any": [0.05, 0.14], "rounds_p50_p90": [[5, 7], [6, 8]], "source": "synth_width.out"},
           "c_over_f_days": 3},
  "budget": {"phase_days": {"P0": 2, "P1": 1.5, "P2": 1.5, "P3": 3, "P4": 2.5, "P5": 1}, "overrun_factor": 1.5,
             "overrun_default": "proceed", "ceiling_days": 20.9},
  "residual_allowed": ["production-traffic", "external-tenant-not-held", "elapsed-time", "operator-eye", "tooling-degraded"],
  "operator_dates": [{"what": "E6 taste gate AM-12", "due": "YYYY-MM-DD"}],
  "trunk_sha_at_ratify": "", "profile": "H|F",
  "ratified": {"route": "cc-signoff|interim-prompt", "row": "research:<P>/frame", "pin": "", "ancestry": ["zsh", "kitty"], "at": ""} }

// decisions.jsonl
{ "id": "DR-04", "group": "G2", "question": "", "type": "fact|design|taste", "options_census": "census/options-DR-04.json",
  "options": [{"label": "do-nothing", "probe": "P-.."}, {"label": "use-what-exists", "probe": "P-.."}],
  "premises": ["PR-031"], "chosen": "", "conviction": 92, "receipt": "", "what_would_flip": "", "flip_checked_by": "P-..",
  "closure_instrument": "desk|spike|model-check|tracer|prototype|load-fault|deploy-rehearsal|operator-eye",
  "reversibility": "reversible|costly|irreversible", "runs_used": 1, "revisit_trigger": "", "timebox_d": 1, "voi_rank": 3,
  "refutation_reopens": 0, "ruled_by": "agent|ladder|operator|packet-default", "packet": {"id": "", "class": "A|B|C"},
  "set": {"members": [{"label": "", "feasibility_probe": "P-..", "branch": ["plan anchors"]}],
          "narrowing_probe": {"cmd": "", "env": "", "wave": "B1", "owner": "", "due": ""}, "revision_budget_h": 6,
          "why_not_now": "production-traffic|external-tenant-not-held|elapsed-time|operator-eye"},
  "status": "open|ruled|carried|reopened", "affects": ["PLAN.md§4"], "validated_at_sha": "", "ts": "" }

// premises.jsonl
{ "id": "PR-031", "kind": "claim|external-fact", "claim": "", "load_bearing_for": ["DR-04", "AM-17"],
  "truth_lives_in": "code|live-state|behavior|target-env|operator", "required_tier": "E2..E6",
  "achieved_tier": "computed", "origin": {"source": "", "tier": "E1"}, "probes": ["P-044"],
  "verdict": "holds|refuted|partial|unknown", "tolerance": "", "p_refute_prior": 0.27,
  "validated_at": {"ts": "", "trunk_sha": "", "depends_on_paths": [""]}, "ttl_h": 72, "recheck_cmd": "" }

// probes.jsonl (written only by probe-run)
{ "id": "P-044", "closes": ["PR-031"], "kind": "read|live-read|measure|spike|skeleton|model-check|fault-inject|dry-run-deploy|handed-cmd|read-through|reproduce|operator-view",
  "env": {"id": "launchd-bash32", "descriptor": {"interpreter": "/bin/bash 3.2.57", "PATH": "/usr/bin:/bin", "os": "15.7.9"}},
  "cmd": "", "stdin": "/dev/null", "n": 5, "load_control": true, "falsifier": "",
  "negative_control": {"ran": true, "against": "", "reported_refutation": true, "reason_if_not_run": null},
  "contact_cell": "sync daemon/H4", "raw": "evidence/P-044/", "exit": 0, "mutates_live": false,
  "sandbox": "none|sandbox-HOME|dry-run|throwaway-label", "trunk_sha": "", "at": "" }

// census/<pop>.json
{ "population": "", "form": "list|grid", "methods": [{"agent": "", "cmd": "", "count": 0}, {"agent": "", "cmd": "", "count": 0}],
  "members": [{"id": "", "source_line": ""}], "reconciled_diff": [], "coverage_argument": "",
  "grid": {"rows": "", "cols": ["not-provided", "provided-wrongly", "wrong-timing-or-order", "wrong-duration"],
           "cells": [{"row": "", "col": "", "scenario": "", "probe": "P-..|null", "na_reason": null}]},
  "critic": {"family": "openai", "ran": true, "unlisted_verified": 0, "integrated": true}, "validated_at": {"ts": "", "sha": ""} }

// sources.jsonl
{ "id": "E-04", "source": "upstream issue tracker", "kind": "ours|external|operator-owned|production",
  "access_cmd": "gh issue list -R owner/repo …", "status": "consulted|excluded", "consulted_at": "", "evidence": ["evidence/P-.."],
  "exclusion_quote": null }

// contact_matrix.json
{ "rows": [{ "component": "sync daemon", "cells": {
    "H1": {"applies": true, "instrument": "small-scope-enum", "properties": ["no lost write", "eventually idle (liveness)"], "probes": ["P-061"], "status": "clean|finding|open"},
    "H5": {"applies": false, "na_reason": "consumer is an agent (intake Q1)"},
    "H6": {"applies": true, "instrument": "set-decision", "decision": "DR-07", "status": "carried"} } }] }

// acceptance.json (rows)
{ "id": "AM-17", "fac": "FAC-19", "predicate": "p90 end-to-end ≤ 1.5 s on 20 real clips", "check_cmd": "", "env": "",
  "threshold": {"metric": "p90_ms", "op": "<=", "value": 1500, "ceiling_probe": "P-.."}, "negative_branch": "",
  "expect_prebuild": "RED|GREEN-guard", "control": {"known_bad": "fixtures/known-bad/..", "red_proof_probe": "P-..", "known_good": "fixtures/known-good/.."},
  "n": 5, "load_control": true, "soundness": "SOUND|NOT-A-COMMAND|ALREADY-PASSES|BLIND-TO-MECHANISM|FAILS-GREEN|MUTATES-STATE|BROKEN-SYNTAX",
  "taste_gate": {"refs": [""], "judge": "operator", "due": ""}, "status": "sound|carried|reopened" }

// residual.jsonl
{ "id": "RS-3", "property": "", "why_unreachable": "production-traffic|external-tenant-not-held|elapsed-time|operator-eye|tooling-degraded",
  "closest_probe": "P-..", "verify_cmd": "", "owner": "agent|operator", "due": "", "backlog_id": "", "falsifier": "", "reopens_on_fail": ["AM-.."] }

// trace.jsonl
{ "from": "docs/research/<P>/x.md#warm-connection", "to": "PLAN.md§4.2", "type": "implements|supports|depends|rejects", "reason": null }

// holes.jsonl (event log; seeds revealed only after adjudication)
{ "id": "H-041", "event": "raise|adjudicate|verify|rate|dispose|reopen", "round": 3,
  "source": "panel|delta|rehearsal|sweep|discovery|consistency|challenge|build|operator",
  "raised_by": {"panel": "r3p5", "family": "openai", "strategy": "spec-only", "blind": true, "snapshot_sha": ""},
  "locus": {"path": "", "lines": "", "quote": ""}, "names": ["DR-04"], "cu": "CU-2", "stratum": "COVERAGE", "taxonomy_class": "C4",
  "verification": {"status": "CONFIRMED|REFUTED|CONTACT", "probe": "P-.."},
  "materiality": {"level": "MATERIAL|MATERIAL-DISPUTED|REFINEMENT|COSMETIC|GENERIC", "clause": "a|b|c|d|e|f",
                  "raters": {"r1": "M", "r2": "M", "r3": null}, "consequence_repro": "P-.."},
  "severity": "significant|functional|process|lifecycle-data|null", "seed_match": null,
  "frame_class": "in-frame-miss|frame-defect|frame-expansion|relabel|contact-residual|drift|set-narrowing|immaterial",
  "born_in_edit": false, "edit_round": null, "reopen_set": [],
  "disposition": {"kind": "fixed|apply-at-build|residual|cr|rejected|duplicate", "ref": ""}, "ts": "" }

// rounds/<k>/panels/<pid>.json (schema'd courier return; raw output kept verbatim beside it)
{ "pid": "r3p5", "round": 3, "family": "openai", "binary": "~/.local/bin/codex", "version": "codex-cli 0.147.0", "strategy": "spec-only",
  "snapshot_sha": "", "bundle_hash": "", "status": "complete|partial|dead|void",
  "lenses": [{"lens": "census", "checked": [""], "result": "nothing material|[fid]"}],
  "rows": [{"id": "AM-17", "answer": "YES|NO|UNKNOWN", "receipt": ""}],
  "findings": [{"fid": "", "locus": {}, "lens": "", "claim": "", "names": [], "receipt": "", "p_real_material": 0.7, "falsifier": ""}],
  "integrity": {"hits": 0}, "tokens": 0, "wall_s": 0 }

// rounds/<k>/matrix.json (seed ids and detections only, never seed content)
{ "round": 3, "snapshot_sha": "", "T": 24, "families": {"anthropic": 6, "openai": 6, "google": 6, "anthropic-alt": 6},
  "dry": false, "m": [{"id": "H-041", "stratum": "COVERAGE", "x": [0, 1, 0]}],
  "seeds": {"original": {"s_eff": 58, "k_left": 7, "orphaned": 2}, "shadow": [{"cohort": "shadow-r2", "s_eff": 4, "k_left": 1}],
            "escape_by_class_family": {"C4": {"anthropic": [2, 3], "openai": [1, 3]}}},
  "est": {"mu_hat": 0, "n_pred95": 0, "p_any": 0, "per_stratum": {}, "chao2_bc": 0, "jk2": 0, "per_family_chao2": {},
          "codetect": [[0]], "b_hat": 0, "rho_hat": 0, "realism": {"mw_z": 0, "flag": false}},
  "found_per_round": [47, 9, 3], "forecast": {"N0_hat": 0, "R_hat": 0, "p50": 0, "p90": 0, "R_max": 0, "fixed_at": ""},
  "stop": "running|dry|cap", "voided_panels": [], "kappa": {"dedup": 0, "materiality": 0, "repass": false}, "sealed_hashes": {} }

// vault seed (decrypted only in memory by seed apply|match)
{ "sid": "S-07", "cohort": "original|shadow-r3|escape", "class": "C3", "file": "PLAN.md", "anchor_quote": "≥40 chars, unique",
  "replacement": "", "defect_statement": "", "detect_span": "PLAN.md:212-218", "planted_round": 1,
  "state": "live|caught|orphaned", "state_round": null, "prescreen": {"caught": false} }

// cert/CERT-v<n>.json
{ "cert": "CERT-v3", "program": "", "profile": "H|F", "snapshot_sha": "", "trunk_sha": "", "issued": "", "tier": "max24",
  "stop": "dry|cap", "rounds": 6, "panel_runs": 144, "families": 4, "structural": {"S1": "PASS"},
  "carried": [{"row": "DR-07", "kind": "set", "blocks_waves": ["B1"], "due": ""}],
  "residual": {"FACT": {"mu": 0, "n_pred95": 0, "p_any": 0}, "COVERAGE": {}, "VALIDITY": {}, "total": {}}, "calibrated": false,
  "named_open": {"disputed": ["H-52"], "weak_lenses": [], "realism_flag": false, "reduced_diversity": [], "degradations": ["no Linux image"]},
  "declared_residual": ["RS-1"], "escapes": {"FACT": 0, "COVERAGE": 0, "VALIDITY": 0}, "take_backs": 0,
  "signed": {"route": "cc-signoff", "row": "research:<P>/cert", "pin": ""} }

// challenges.jsonl
{ "id": "CH-5", "ts": "", "raised_by": "operator|agent|sweep|build|rehearsal", "locus": {}, "names": [], "evidence_date": "",
  "triage": "generic|refuted|relabel|immaterial|frame-defect|frame-expansion|contact-residual|set-narrowing|drift|escape|pending",
  "severity": null, "action": "", "delta_rounds": [], "cert_reissued": "CERT-v4|null" }

// changes.jsonl
{ "id": "CR-3", "cause": "operator_new|operator_unelicited|frame_defect|reality_moved|escape", "justification": "",
  "affected_rows": [], "price": {"rounds": 0, "days": 0}, "ruling": {"route": "operator-prompt|cc-decide", "ref": ""}, "resigned": "" }

// verdicts.jsonl
{ "ts": "", "session": "", "cwd": "", "question": "", "answered_with": "CERT-v3|progress|CH-5", "vector": {"V1": "", "V4": ""},
  "unchanged_since": "", "take_back": false }
```

---

## 10. Timeline and budget model

### 10.1 Units

- **Units are agent-runs and panel-runs** at a fixed brief and effort. Execution effort, not calendar time, predicts
  reliability growth (Wood 1996). W0 measures wall time, tokens and **weekly-quota %** per run per family
  (`claude-accounts` before and after).
- **Parallelism** is about 6–8 Anthropic runs (4 accounts at `cc-wave-plan` ≤ 2 per account per wave), plus the codex
  and gemini lanes. Certification rounds run as 3 concurrent Workflow runs of 8.
- `Wall(phase) = max(critical path, Σ unit cost / p) + dated operator waits`. Every operator gate carries a date, so
  dormancy prints as blocking days, never as research. sevenrooms was idle 33 of 35 days (`greenfield-cases.md`
  mechanism 9).

### 10.2 Worked prior for a medium greenfield

The example has about 15 DRs, 12 FAC-driven censuses, 60 premises, 50–70 AM rows, 6 components in the contact matrix,
and certification at max24. These are **priors to calibrate**; the round figures come from simulation.

| Phase | Runs / probes | Agent-days p50 | Operator |
|---|---|---|---|
| P0 | ≈ 25, including 12 frame-critique panel-runs | 2 | 60–90 min interview, 15 min signoff |
| P1 | ≈ 40 (2 methods × censuses, premises, sources) | 1.5 | 0 |
| P2 | ≈ 30 probes (E2 0.1–0.25 h; E4 1–3 h; E5 2–6 h each) | 1.5 | 0 |
| P3 | ≈ 40 runs plus option spikes, VOI order, timeboxed | 3 | class-C rulings, dated (≈ 5 min each) |
| P4 | harness, skeleton (8–16 h), H-cells, faults | 2.5 | E6 taste gates, dated |
| P5 | ≈ 8, including seed author, pre-screen, discriminator | 1 | 0 |
| P6 | round 1 (seeding checks, realism, forecast) ≈ 1 d; then ≈ 4.5 h per fix round and ≈ 2.5 h per dry round; p50 5–6 rounds, p90 7–8 | 1.5–2 (p90 2.5) | 0 |
| P6 tail | rehearsal 12 runs, sweep 2, gate | 0.5 | 15 min cert signoff |
| P7 | S10 re-run, build-start revalidation | 0.5 | 0 |
| **Total** | **≈ 300–400 runs, including 120–192 certification panel-runs** | **≈ 14 p50, ≈ 17 p90** | **≈ 2–4 h plus dated rulings** |

**Tokens (prior).** At 150–250K tokens per substantial run, the program is roughly 60–120M tokens across vendors.
About half the certification panel-runs are non-Anthropic (codex and gemini subscriptions). This is **not measured**;
W0 prices it in quota %.

**Anchors:**
- Past research phases converged in 1–2 days, and the weeks came afterwards as leakage: LIMIT_RECOVER_100P spent 22
  days and 30 `/goal` conditions after "complete".
- DOCS_CONSOLIDATION took 25.75 h and was never reopened.
- FLEET_V2 landed W0–W6 in about 1.5 days after a measure-first W0.

This protocol spends more before the claim, to spend almost nothing after it.

### 10.3 The finite guarantee (printed on the contract page at ratification)

`Ceiling = 1.5 × Σ(P0–P5 budgets) + R_abs × fix-round time + P6 tail + P7`

With the defaults: `1.5 × 11.5 d + 14 × 4.5 h + 0.5 d + 0.5 d ≈ 17.25 + 2.6 + 1.0 ≈ **21 agent-days**`.

It can be exceeded only by an explicit operator act: a veto of an overrun default, an `extend`, a `raise`, or an
`amend`. Each prints its price first. Operator waits are shown separately as dated blocking days. The 1.5 factor
shrinks as `research-calibration.jsonl` accumulates programs (reference-class forecasting).

### 10.4 Where the operator's "100× effort for the last 1%" goes, in order

1. **The front end.** More census methods, more contact cells, production-scale rigs, an E6 prototype in front of the
   operator. It is the only lever that shrinks both the desk-detectable residual and the desk-invisible mass (§3.7
   reading 1).
2. **Width.** A higher T and more families (max → max24).
3. **Depth.** A higher K.
4. **Seeds.** These tighten only the statement.

`extend` quotes each purchase's expected yield. A purchase that cannot move the number is labeled as such.

---

## 11. The honest residual

What no upfront method can eliminate, and what this protocol does about each:

| Residual | Why it cannot be zero | What the protocol does |
|---|---|---|
| **Literal zero unknowns** | Certifying no hole left needs examining n ≥ 0.95N of all places a hole could be. With F = 60 holes found, "P(≥ 1 left) ≤ 5%" at 95% confidence needs 3,654 seeds, all caught (`stopping_model.out` §1) | replaced by AD1: frame closure plus a stated, priced bound |
| **Holes every model family misses** | unidentifiable from overlap (Link 2003); about 1.1 (N₀ = 20) to 3.3 (N₀ = 60) at every tier in the model (`synth_width.out`) | contact before the claim (P2, P4, S7); declared on every certificate in words; the Fable sweep as a partial, different detector; a breach counts as a take-back |
| **Production, external tenant, elapsed time, the operator's eye** | the property lives only there: 6 of 200 historically (holes 16, 34, 95, 121, 134, 170) | residual rows with owner, date, verify command and falsifier (S11); carried sets where the choice depends on them; a failure reopens only dependents |
| **Genuinely new requirements** | the operator's intent changes: 6 of 200 | an operator change request, a mini-program and a price; not a take-back |
| **Unforeseeable drift** | the world moves: 4 of 200 | TTLs, recheck commands and sha stamps (S10 at gate and build start); scoped revalidation |
| **Expected desk-detectable escapes > 0** | at max24, P(≥ 1) ≈ 0.05 (strong front end) to 0.14 (weak); at build tier 0.27–0.46 | the forecast is printed at signoff; every escape is shown, counted and fixed locally with ≤ 2 delta rounds; a count above n_pred95 is a take-back |
| **Estimator calibration** | family correlation on design review and seed realism are unmeasured. Kim et al. measured 60% same-wrong-answer agreement on multiple-choice questions, not plans | **W0 blocks everything else**; certificates print "uncalibrated" until it reports; the co-detection matrix is recorded per program |
| **Materiality mistakes** | M vs refinement is a judgment (TM2's "uncatchable" bucket moved 13 ↔ 5 with its definition) | 3 raters across families plus consequence reproduction; disputed items named and applied at build; mistakes surface as escapes and are counted |
| **Frame defects** | a pattern no FAC row and no critic anticipated | counted as `frame_defect`; the FAC grows by one row per defect, so each program is less exposed than the last |
| **Isolation of non-Anthropic panels** | same-UID codex and gemini can read the real repo | sanitized cwd, encryption, fresh paths, integrity grep: detection, not prevention; stated on the certificate |
| **The method's own machinery** | new code can hold C7-type holes | every gate and estimator has a planted-input test that must go red; W0 runs by hand first; the first program is an explicit calibration run |
| **Operator acceptance** | AD1 is a value judgment | one class-C packet with measured W0 prices; until ruled, certificates issue and the Stop arm warns without blocking |

---

## 12. Build list for this environment

Execution locus is **S** (a dispatched session per wave in its own worktree, landed through the project `/ship`), except
W0a. Each wave's goal is its exit criterion, which the session runs and prints.

| Wave | Deliverable | Exit criterion |
|---|---|---|
| **W0a** (L, hours; urgent, /tmp was wiped once today) | Persist `/tmp/rescomp/**` (taxonomy, ledger, stats, forensics, internal and external research, designs, simulations, both syntheses, `loop_asks.json`, `ca_scan.py`, `reask_frames.py`) to `docs/research/research-completeness-2026-09-30/`. Derive `escape-library/escapes.jsonl` (the 129 desk-findable rows, with receipts) and `frame-axis-checklist.jsonl` (§3.5) | `git ls-tree origin/main -- docs/research/research-completeness-2026-09-30/` lists them, verified by content |
| **W0** (S, blocking; the positive control for the whole method) | Build the Profile H scripts (§2.4), then run P5–P6 by hand on historical snapshots with known later holes: the VoiceInk latency plan at `989f6dbf` 2026-09-28T05:21:27Z ("It's now done"; 20 defects and the upstream v2.20 axis surfaced after it) and the VoiceInk quota plan at `ba08cab8` 19:25Z (D22–D24 surfaced after). **Measure:** recall of the known later holes *before* "done"; the family co-detection matrix; seed realism, pre-screen catch rate and seed distraction (seeded vs unseeded copies); quota % per panel-run per family; whether codex and gemini sustain 6 panels per round (max24 vs max); gemini auth under a real call; `--setting-sources local` on the Opus-5.5 binary; read confinement under `--allowedTools "Read Grep Glob"`; ollama admission (seed recall ≥ 0.33); whether Workflow `agent({model:fable})` reaches `frontier-spawn-gate`; **the hold rate of n_pred95** | `docs/research/cur-w0-backtest.md` with each measurement and its receipt. Then AD1–AD3 are filed as one class-C packet with conviction, receipt and the **measured** price table |
| **W0b** (S, parallel with W0) | **B7**: `scripts/lib/operator-signoff.py`, cc-signoff's three arms factored out, plus a `research:<P>/<frame\|cert>` namespace in `bin/cc-signoff` backed by `~/.claude/autonomy/research/<P>/signoff.json`. **AD4**: the zero-allowed wording replaces `agents/deep-research.md:187`, `agents/research-decomposition-critic.md:37-38` and `skills/research-subagents/SKILL.md:798-803, 823`; the negative-space trigger is scoped to P0 frame critique | bats: cc-signoff refuses from a claude ancestry, pins the blob, renders an agent-written row VOID, and never touches cc-mission rows. A replayed `/research` wave returns a valid "zero findings" without coercion |
| **W1** (S) | `bin/cc-research` core (Python): `init` (scaffold, topic lock, `programs.json`), `index`, `frame {new,lint,render}`, `census {add,verify,grid}`, `source`, `premise {add,due,queue}`, `decision {point,set,narrow}`, `trace check`, `reconcile`, `lint`, `freeze`, `impact`, `estimate`, `forecast` (the `cert_sim.py` model, copied to `tests/fixtures/research-cert/`), `gate`, `verdict --render\|--machine`, `challenge`, `amend`, `extend`, `raise`, `budget`. Append-only folds as in `cc-backlog` | pytest and bats green. **Every gate row and estimator goes red on a planted input.** The estimators reproduce the worked example (47 → Chao2 56.0) and `carried_seeds.out` on fixture matrices. The forecast reproduces `forecast_check.out` within ±1 round at p50 |
| **W2** (S) | Contact machinery: `probe run` (records env, stdin, n, raw output and negative control; refuses `mutates_live` without `--sandbox`; computes tiers), `probe-kit {doctor,install}` (interactive-shell PATH resolution; installs are `cc-backlog needs` items for the operator), `harness selftest`, `contact {init,check}`, and the `cur-contact` Workflow | the doctor prints the verified inventory (bash 3.2.57, codex, gemini under fnm, ollama; docker degraded; TLC and hypothesis absent). `contact check` fails on a planted empty cell. Harness self-test goes red and green on fixtures |
| **W3** (S) | Certification machinery: `panel run` (couriers, program Fable ledger, headroom check), sanitized-bundle builder, vault (`openssl` plus keychain), `seed {author,prescreen,apply,match,realism}` with orphan censoring, and the `cur-round`, `cur-frame-critique` and `cur-rehearsal` Workflows under `~/.claude/workflows/`. Agents write to disk and return paths and hashes, because the orchestrator has no filesystem (`workflows-vs-teams-2026-08-20.md:185`) | one live round on a toy program: 24 complete panels across 4 families, integrity grep 0 hits, a seeded defect caught and matched, an orphan censored, a voided panel re-run |
| **W4** (S) | Hooks and commands: the re-ask branch in `hooks/research-precognition-nudge.sh` (no settings migration needed); the symmetric arm in `hooks/completion-assert.sh` (warn-only, `Replaces: D4 re-ask semantics, certified programs only — ruling pending`); a `GOAL` field plus absent-DoD → "unknown" in `scripts/wrap-ledger.sh:2286-2288`; the superlative lint and `cause=` on `Scope (grown)` in `hooks/dod-persist.sh:76-96`; a `Goal:` line in `commands/are-we-done.md:52-57, 70-72`; `--requires-gate <P>` in `scripts/handoff-fire.sh`; `SKILL.md:944-948` routing re-checks to `challenge`; OASIS (`SKILL.md:756-782`) scoped to discovery-wave spawning | bats: a completeness prompt from a **different cwd** injects the render; an identical re-ask renders identical words; "No, one more check" without an escape id warns (blocks after AD3); an absent DoD reads unknown; `--requires-gate` refuses a wave whose closure holds a carried row |
| **W4-op** (operator) | Rule AD1–AD3 (the one packet from W0). On adoption: a one-sentence F1 edit in `CLAUDE.global.md` and the live `~/.claude/CLAUDE.md`, and the Stop arm flipped from warn to block | the packet is actioned |
| **W5** (S, the next greenfield) | The skill `research-program` and the command `/research-program` (P0 script, 12 questions, FAC, rubric, and the panel, seed-author, adjudicator, verifier, consistency-reader and rehearsal briefs). Then the full P0–P7 program at the ratified tier. Escapes are tracked for 30 days after build start | CERTIFIED issued; the 30-day escape report written; a `research-calibration.jsonl` row appended |

**Order:** W0a → {W0, W0b} → W1 → {W2, W3, W4} → W5. Nothing past W0b ships before W0 reports, because W0 may change
parameters.

**Existing tools, reused as they are:**
- `cc-decide`: priced choices *inside* the frame. The tier choice, `extend`/`raise`, class-B timebox and overrun
  defaults, class-C carried rows, and agent-originated change requests. Never for ratification.
- `cc-backlog`: residuals (`--why-not-now "not-yet-true: …" --falsifier`), `apply-at-build` rows (`--dod-ref`), and
  operator-only installs (`needs --run`).
- `handoff-fire.sh`: phase and round sessions.
- `frontier-run` / `frontier-derivation`: the sweep.
- `/ground-up`: the divergence step.
- `msg`, transcripts, `cc-memory-search`, `cc-sessions`, `cc-custody`: mining and the topic lock.

**Tooling limits today,** each re-verified by the doctor and degraded explicitly, never silently:
- the docker CLI panics, so there is no Linux-image probe;
- Java/TLC and `hypothesis` are absent, so stdlib small-scope enumeration is used;
- `grok-wiki` fails on the broken `claude` stub (`skills/grok-wiki-audit/SKILL.md:16`), so couriers call vendor CLIs
  directly;
- gemini auth has not been exercised by a real call;
- `migrations/0029` (the Bash arm of the frontier gate) is unrun, which is why the program Fable ledger exists.

---

## 13. Every judge's fatal flaw, and how it is closed

| Flaw (design; judges) | Closed by |
|---|---|
| **FCR:** ratification through `cc-decide`, which has no agent guard (all three) | operator-only `cc-signoff research:<P>/frame\|cert` (B7), with an interim genuine-prompt route labeled weaker (§3.10) |
| **FCR:** G8 hard thresholds on lower-bound estimators from one round; fresh end-seeds held 71–87% (all three) | no residual exit gate: stop is dry-K or the cap, with the residual stated; carried and shadow seeds with n_pred95 (97.8–100%) (§5.3–5.7) |
| **FCR:** Workflow-agent panels inherit resident context; the ledgers are in the repo panels read; blindness only instructed (all three) | separate CLI processes; `--setting-sources local`; a sanitized, history-free bundle at a fresh path without the program dir; encrypted vault; integrity grep voids panels (§5.1) |
| **FCR:** dead-slot re-runs uncapped ("every slot alive") | L6: 2 re-runs, then the next family, "reduced diversity" printed (S13) |
| **FCR:** overrun default "proceed" contradicts "build cannot fire while red"; F0's goal contains an operator act | overrun turns open rows into carried rows that block only dependent waves (`--requires-gate`); phase goals end at "gate printed PASS or FILED" (§2.1, §6.3) |
| **FCR:** "meaning-saturated" is a status the lead sets itself; re-ask hook keyed on cwd; 5–9.5 day prior optimistic | coverage computed from register mappings (§3.4); `programs.json` resolution from any pane (§7.1); priors re-derived at about 14 days p50 and a 21-day ceiling (§10) |
| **RCF:** G9 hard exit gate; class C with no default and "reopen a named phase"; P2/P4→P3 loops uncapped; overruns class C (all three) | SS stop rule, residual stated; overruns are class B with a default; L1 caps refutation reopens at 2 per DR; every loop is in §2.3 |
| **RCF:** adjudicator disagreement counts as MATERIAL, inflating rounds | vote plus consequence reproduction; unresolved disputes are MATERIAL-DISPUTED and do not reset the dry count (§3.6) |
| **RCF:** a "no" may cite a hole filed this turn that is still unreproduced | a "no" needs a challenge triaged `escape` (reproduced and MATERIAL); a pending challenge leaves the certificate standing (§7.6) |
| **RCF:** `verdict` re-executes the live harness on every ask, so flake flips a yes; the rehearsal uses literal challenge wording | per-ask checks are deterministic only, live rows cite scheduled runs with a 2-of-3 flake rule; the rehearsal uses frames as lenses, once (§7.3, §5.8) |
| **RCF:** "gemini not installed" is false; unmeasured ollama as the third family | gemini by absolute fnm path (verified present this session); ollama only as extra slots above a 0.33 seed-recall floor; the doctor resolves through the interactive PATH (§5.1, §4.3) |
| **RCF:** ratification through cc-mission pollutes the customer board | the `research:` namespace, off the board (§3.10) |
| **RCF:** no C1 store-reconciliation gate | S12 plus V5 (§6.1) |
| **RCF:** F1/D4 edits without `ruling pending`; Stop arm blocks outright | AD2/AD3 carry `Replaces: … — ruling pending`; the arm is warn-only until ruled (§1, W4) |
| **RCF:** the Fable bound relies on an Agent-only hook | program Fable ledger in `panel run` with a headroom check (§5.1) |
| **RCF:** probe kit needs Java/TLC, hypothesis, Docker; emulable-but-unbuilt cells cannot be parked; per-cell rehearsals are partial implementation priced from unmeasured priors | stdlib enumeration by default; `tooling-degraded` is an allowed, printed residual with a `needs` id; cells are VOI-ordered inside the P4 timebox, and an overrun carries them as dated rows (§4.5) |
| **SS:** P(≥ 1 material left) = 0.46 at the default build tier | the recommended tier for this operator is max24 (0.05–0.14), plus the front-end lever; the chance is stated at intake in plain words (§3.7) |
| **SS:** calibration is self-rated 60%, from its own model | W0 backtest on historical snapshots blocks all later waves; "uncalibrated" printed until it reports; take-back = calibration breach (§12, §8.3) |
| **SS:** heaviest build, thinnest front end (no checklist, no bounded frame critique, contact a list) | FAC-32, the source register, grid censuses, the bounded frame critique and the H1–H7 matrix grafted in (§3–4); Profile H lets the protocol run before the full build (§2.4) |
| **SS:** at b ≥ 1 it cannot stop before the cap | MATERIAL-only fixes, refinements not integrated, single integrator plus consistency read, b̂ ≥ 0.5 → delete machinery; the cap still certifies (§5.4, §5.6) |
| **SS:** MATERIAL-DISPUTED deferred to build | one reproduction probe first (L10); a dispute on an irreversible DR joins that DR's build-wave-1 narrowing probe (§3.6) |
| **SS:** quote-anchored seeds on a plan edited every round are fragile | only MATERIAL fixes edit the plan; orphans are censored, measured unbiased (`tier_curve.out` §E); W0 measures the orphan rate on real plans |
| **SS:** Stop arm warn-only until the D4/F1 ruling | kept, and made explicit: AD3 narrows D4's re-ask semantics without contradicting "drive it", because triage *is* driving; the injection hook needs no ruling and works from day one (§1, §7) |
| **All three:** new tooling needed first, itself exposed to the loop; no hand-run profile | Profile H at W0 (§2.4); every build wave has a numeric exit criterion that goes red on a planted input, and no superlatives appear in any wave DoD (§12) |
| **All three:** everything depends on the operator ratifying what 100.00 means | AD1 as one class-C packet with measured prices after W0; until then certificates issue and the arm warns (§1) |

---

## 14. Taxonomy coverage: every class, its mechanism, its gate, its residual

| Class (n; desk-findable) | Mechanism | Gate | Declared residual |
|---|---|---|---|
| C1 claim frame narrower (23; 23) | verdict vector over the operator's frames; computed reconciliation; two-level close; re-asks answered from the ledger; relabel triage | S1 (frame map), S12, §7 | none expected; a relabel is not a miss |
| C2 operator intent (12; 2) | mining plus a 12-question pre-filled interview; operator-signed frame; change requests with a cause | S1 | **C2n, 6 (3%)**: new requirements, priced and never a take-back |
| C3 unverified premise (29; 26) | premise register with computed tiers; VOI-ordered probes; refutation-rate check; FACT-stratum seeds | S4, S10, Q2 | secondary premises only where VOI = 0, stated |
| C4 population never enumerated (32; 29) | FAC-32; two-method censuses; STPA and state × input grids; source register with tie-breaker; census critic once; bounded frame critique on registers | S2, S3, S1, Q2 COVERAGE, Q4 | members no search reaches: inside the stated bound, or a named weak lens |
| C5 instrument could not discriminate (29; 13 desk, 15 build) | harness red and green self-test; red-proof per row; negative controls on probes; n ≥ 5 with load control; re-execution, never recall | S6, S7 | build-only instrument defects move into the contact matrix |
| C6 research lost (12; 12) | index at start; trace check; repo persistence; topic lock | S8 | none expected |
| C7 self-created by edits (10; 8) | single integrator; MATERIAL-only fixes; consistency read; shadow seeds; b̂ and the divergence rule; H1 fixes re-checked | S9, Q1, Q3 | fix-born holes inside the shadow cohort's stated bound |
| C8 review late or unsaturated (8; 8) | certification before any claim; dead and voided slots re-run; build gated on the verdict | S13, Q1, `--requires-gate` | none |
| C9 contact-only (30; 1 desk, 29 probe) | measure-first contact wave; skeleton; H1–H7 cells; every handed command run; carried sets | S7, S5, S11 | **6 of 30**: production, tenant or time (holes 16, 34, 95, 121, 134, 170), owned and dated; `tooling-degraded` named |
| C10 reality moved (8; 3) | TTLs, recheck commands, sha stamps; trunk and sibling re-read before recommending, at the gate and at build start; non-mutating probes | S10 | **4 of 8 unforeseeable**: drift triage, dependents only |
| C11 criterion not operationalized (7; 4) | superlative lint; measured ceilings; thresholds and negative branch; positive references with a dated E6 gate; hold expiry | S1, S6 | taste verdicts are the operator's by design, as a dated gate |

**Declared residual:** 16 of 200 (8%): C2n 6, irreducible C9 6, unforeseeable C10 4. This matches the taxonomy's
"10 unreachable + 6 new requirements" (`taxonomy.md:277`). The back-test figure that 89% of holes move in front of the
claim is hindsight-assisted, especially for C4 (`taxonomy.md:343`). Treat it as an upper bound that W0 and the first
program measure.

---

## 15. Receipts index

- **Designs and verdicts:** `/tmp/rescomp/design/{statistical-stopping,frame-contract,reality-contact}.md`; the three
  judge verdicts in the task; the prior synthesis in `SYNTHESIS.r1-pre-reboot.md`.
- **Simulations** (all under `/tmp/rescomp/design/`, stdlib Python, rerunnable): `cert_sim.py` (the model),
  `tier_curve.out` §A–E, `stopping_model.out` §1–5, `cert_calibration.out`, `carried_seeds.out`, `seed_realism.out`,
  `forecast_check.out`. New this synthesis: `synth_width.py` / `synth_width.out` (T = 24 rows and max with false
  positives).
- **Corpus:** `/tmp/rescomp/taxonomy.md`, `taxonomy_holes.py`, `python3 /tmp/rescomp/taxonomy_stats.py`,
  `loop_asks.json` (88 asks), `design/reask_frames.py` (frame counts), `design/.ledger_dump.txt`, `internal/ca_scan.py`.
- **Repo anchors re-read this session** (trunk `cda13e6a1`):
  - `bin/cc-signoff:1-32, 88-115`;
  - `bin/cc-decide` (no guard; `:42`, `:480` expire-sweep);
  - `scripts/wrap-ledger.sh:614-624, 2283-2290`;
  - `hooks/completion-assert.sh:1276-1279`;
  - `CLAUDE.global.md:616-619`;
  - `agents/deep-research.md:187`, `agents/research-decomposition-critic.md:37-38`,
    `skills/research-subagents/SKILL.md:798, 800-803`;
  - `skills/ground-up/SKILL.md:14-18`;
  - `hooks/enforce-email-formatting.py:688-720` (the genuine-prompt predicate);
  - `docs/research/orchestration-units-2026-08-19.md:116-120`;
  - `docs/research/workflows-vs-teams-2026-08-20.md:185, 364-367`;
  - `~/.claude/model-config.yaml:1116`;
  - `~/.claude/settings.json` (UserPromptSubmit list; frontier gate on the Agent matcher only);
  - both `docs/lessons/` files cited;
  - `hooks/lib/{cc-interactive,origin-identity,dod-path}.sh`, `bin/{cc-custody,cc-sessions,cc-backlog,cc-mission,cc-wave-plan}`
    and `scripts/handoff-fire.sh` all exist.
- **Machine facts re-read this session:**
  - gemini symlinks under fnm v18.18.0, v20.19.6 and v22.21.1;
  - `/opt/homebrew/bin/claude` 2.1.278 with `--setting-sources`;
  - `~/.local/bin/codex`;
  - `/opt/homebrew/bin/ollama` 0.33.3;
  - `docs/research` holds 406 entries.

  From the designs' same-day probes: codex `Logged in using ChatGPT`; the `--setting-sources local` NONE-vs-mission-board
  pair; `/bin/bash` 3.2.57; the docker CLI panic; Java and hypothesis absent.
- **External** (via `/tmp/rescomp/external/*.md`, with their primary citations): Callaghan & Müller-Hansen 2020;
  Guest, Namey & Chen 2020; Francis 2010; Hennink 2017; Chao et al. 2009; Briand et al. 2000; Link 2003; Kim et al.
  2025; Böhme et al. 2021; Deng et al. 2024; Dalal & Mallows 1988; Hanley & Lippman-Hand 1983; Wood 1996; Lewis et al.
  2021; Huang et al. 2024; FlipFlop; FixedBench; arXiv 2603.18740; NPR 7123.1D App. G; NASA SEH 6.2/6.5; FY2009 NDAA
  §814 and the GAO 72%/11% quote; EASA AMC 20-189; STPA Handbook; Zowghi & Gervasi 2003; Newcombe et al. 2014; Boehm
  1988; Reinertsen; Toyota SBCE; Snowden & Boone 2007.
