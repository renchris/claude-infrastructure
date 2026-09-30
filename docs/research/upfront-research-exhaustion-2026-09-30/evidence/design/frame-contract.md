# Frame-and-Contract Research (FCR): an upfront research method that finishes

Design for the next weeks-long greenfield project. Organizing angle: **completeness only means something against a declared frame.** The frame is enumerated, ratified by the operator and frozen before research starts. Research fills persisted ledgers against it. An exit gate is computed from those ledgers by a script. The question "are we 100.00/100.00 complete?" is answered by relaying the gate's certificate, never by a fresh critique. After the gate, every new finding is typed before anything reopens.

Evidence base (read in full for this design): `/tmp/rescomp/taxonomy.md` (200 holes, 11 classes; ledger `/tmp/rescomp/taxonomy_holes.py`, counts `python3 /tmp/rescomp/taxonomy_stats.py`), `/tmp/rescomp/forensics/shard-0..7.md`, `/tmp/rescomp/internal/{research-machinery,close-assertion,plan-lifecycle,greenfield-cases}.md`, `/tmp/rescomp/external/{stopping-rules,unseen-estimation,llm-failure-modes,systems-engineering,epistemic-limits}.md`. Repo anchors were first read at trunk `5d8f1ce24` and re-read after the 2026-09-30 15:26 CDT reboot at trunk `cda13e6a1`; §11 lists what that re-check confirmed and what it changed.

---

## 0. Answer first

1. **The loop is not caused by too little research. It comes from research measured against no fixed denominator, certified by checks that run after the claim, and re-judged from scratch on every ask.** Of 200 holes that surfaced after a "complete" claim, only 6 (3%) were new operator requirements, 129 (64.5%) were desk-findable, and 23 (11.5%) were already known and on disk (`taxonomy.md:9-16`). The machinery requires every gap-finder to return gaps ("List 3", "Find 2-3 gaps", "name 1-3 missing axes": `skills/research-subagents/SKILL.md:798`, `agents/deep-research.md:187`, `agents/research-decomposition-critic.md:37-38`). It lets a gap be dropped only by quoting the operator's own exclusion words (`SKILL.md:800-803`). Its "complete" is a count of `- [ ]` boxes that research DoDs never contain (`scripts/wrap-ledger.sh:616-623`; 4 of 76 DoD files carry any box, `close-assertion.md` §1.3). Given those three facts, "No, one more thing" is the only answer the rules allow.
2. **FCR moves the checks in front of the claim and fixes the denominator.** It has five phases:
   - **F0.** Intake and a ratified **Research Contract**: decisions, questions, axes, censuses, acceptance checks, a materiality threshold, the declared residual, the stop rule and the budget.
   - **F1.** Censuses and premise verification.
   - **F2.** Axis research.
   - **F3.** A contact wave on the real target.
   - **F4–F5.** A frozen snapshot, then certification by blind, family-diverse panels with seeded defects. The panels' overlap gives a numeric estimate of what is still unfound.

   The taxonomy puts 178 of 200 historical holes (89%) within reach of steps like these, each of which already has a working exemplar in the corpus (`taxonomy.md:303`).
3. **The operator's "100.00/100.00" becomes two numbers, and the operator ratifies that definition in F0:**
   - **Frame closure.** This can be exactly 100.00: every contract row is closed with a receipt that a script can check.
   - **Residual.** A bounded estimate of material holes not yet found (a lower bound, with seed recall).

   Certifying "zero unknown holes" would require examining ≥95% of every place a hole could be (`stopping-rules.md` §2; Callaghan & Müller-Hansen 2020). No method gives that, so the design states the bound instead of implying one.
4. **The re-ask stops generating holes.** After the gate, the answer to "are we complete?" is the certificate itself, injected by a hook, so the model does not regenerate it. A new candidate hole must name a location, the decision it would flip, and its frame class. Only a verified material in-frame miss, or a ratified frame change, reopens anything, and then only the rows it affects. Buying more assurance is a separately priced extension, not a reopen.
5. **The timeline becomes predictable because every phase has a budget in agent-runs, and certification has a price table computed from the data.** Worked example: 8 panels find 47 holes; reaching 90/95/99% of the estimated total costs 3.1/7.6/18 more panels (`unseen-estimation.md` §3.6). Overruns go to a class-B decision packet whose default is "accept the current bound and proceed". A phase cannot drift into months.
6. **Where the operator's "100× effort for 1%" should go:** into F0 (frame critique and intake), F3 (contact) and a higher certification target. That is where the corpus says holes are cheapest to catch. It should not go into open-ended re-asks, which the evidence shows do not converge (23/21/24/28 new items per round, `7c395da7` 15:58:52Z; 37→…→16 over 13+ rounds, `dcbd2f8e`).
7. **This is how high-assurance engineering already ends an upfront phase, so none of it is novel.**
   - NASA's SRR asks whether requirements are mature enough "to begin Phase B", with every TBD and TBR "clearly identified with acceptable plans and schedule for their disposition". It never asks whether they are 100% complete (NPR 7123.1D App. G, `systems-engineering.md` §1).
   - After the baseline, a change needs board approval and an impact assessment, under a statutory presumption against change. GAO found 72% cost growth in programs that changed requirements after development began, against 11% in programs that did not (FY2009 NDAA §814, `systems-engineering.md` §6).
   - Aviation lets every open problem report ship open with a recorded justification, except an unmitigated "Significant" one (AMC 20-189, `systems-engineering.md` §3).
   - Requirements theory says external completeness "cannot be defined in absolute terms", only relative to the sources consulted (Zowghi & Gervasi 2003, `systems-engineering.md` §5).

   FCR is the same structure (frame, finite grid, a to-be-determined (TBD) ledger, baseline, board, severity triage), with one addition. Because the finders here are correlated LLMs rather than independent engineers, FCR also measures what is still unfound.

---

## 1. Principles (each tied to evidence)

| # | Principle | Why (receipt) |
|---|---|---|
| P1 | **Freeze the population before any stop rule can fire.** | Every valid stopping rule assumes a fixed universe (Francis et al. 2010 principle 1; Ferguson ch. 5, where the one-step look-ahead rule is optimal only when the problem is monotone). Moving goalposts break monotonicity, and then no rule terminates (`stopping-rules.md` §0.3, D3). |
| P2 | **Answer from a persisted ledger, never regenerate.** | Anthropic's long-running harness keeps state in JSON because "the model is less likely to inappropriately change or overwrite JSON files"; recall decays with context and compaction (`llm-failure-modes.md` T2, F12–F13). C1 (11.5%) is exactly known items re-rendered as new. |
| P3 | **Zero is a correct answer, and every candidate needs a location, a decision and a frame class.** | "Find problems" prompts degrade correct work (Huang ICLR 2024: 75.8%→38.1%). Agents patch already-fixed issues 35–65% of the time (FixedBench). Completeness is the least stable judge criterion (arXiv 2603.04417). |
| P4 | **A check certifies "done" only after it has been shown red on a planted defect.** | C5, 29 holes. Positive control: DOCS_CONSOLIDATION_100P ran 58 acceptance commands before build, found 45 unsound, closed in 25.75 h and never reopened (`plan-lifecycle.md` §0.5, reso `550409f79`). |
| P5 | **Review bounded passes over a frozen snapshot, never an open fix-in-loop critic.** | Bounded passes converged: 10→7→2 (`ba08cab8` 19:28:54Z) and 7→1→0 (`04235d35` 22:32:30Z). Pre-declared "round 2 of 2, the last" shipped in about 2 days (`greenfield-cases.md` row 5). Open fix-in-loop critics did not converge. |
| P6 | **Contact happens inside research.** | C9 is 15%, and 24 of those 30 could have been probed on this machine (`taxonomy.md:15`). Exemplar: FLEET_V2's measure-first W0, after which W0–W6 landed in about 1.5 days. |
| P7 | **Materiality is defined against the decision register.** | ISA 320: an omission is material if it could change a decision. Howard 1966: information that cannot change an action has value 0. No materiality definition exists in the repo (`close-assertion.md` §2). |
| P8 | **Estimate the residual from independent, family-diverse panels plus seeds; never from agreement.** | Same-family errors agree ~60% of the time vs 33% by chance (Kim ICML 2025). In simulation, 1→5 families found 44 more holes. Only representative seeds recovered the true total; coverage read 0.976 while 83% was found (`unseen-estimation.md` §5). |
| P9 | **Separate the goal verdict from the session verdict.** | "'Safe to close' described *my session's* state, not the job" (`7f533f05` 09:08:24Z). reso `FLOOR_PLAN.md:63-66`: "each time true of the wave then running and false of the question asked". |
| P10 | **Every superlative becomes a number with a measured ceiling.** | `skills/ground-up/SKILL.md:14-18` already bans superlatives: they "make completion unfalsifiable — the exemplar's Stop-hook thrashed on exactly this". /research and dod-persist lack that rule (`stop-rule-machinery.md` S11). |
| P11 | **Completeness is stated relative to named sources, and the source list is part of the frame.** | Zowghi & Gervasi: external completeness "is a relative measure since the external sources may themselves be incomplete, or not all relevant external sources may be known" (`systems-engineering.md` §5, S12). In the corpus, "no way to ask" came from searching only our own stores (hole 57), and an apex-301 recommendation was inverted by access logs nobody had opened (hole 111). Each "one more thing" amounts to a source consulted for the first time. |
| P12 | **Classify each question by the instrument that can close it before spending desk time on it.** | Cynefin: in the complex domain "right answers can't be ferreted out … probe first" (Snowden & Boone 2007 p.6). AWS: design reviews, informal proofs and fault injection all missed bugs that model checking found, and model checking does not find "sustained emergent performance degradation" (Newcombe et al. 2014 pp.1, 5, 7). Boehm: "How much is enough?" is "determined by the level of risk incurred by not doing enough" (1988 p.9). All in `epistemic-limits.md` §1, §3 H1–H7. |
| P13 | **A re-check everyone expects to pass buys almost no information.** | Reinertsen: a binary test yields the most information "at a 50 percent failure rate", and "minimizing failure rates drives us towards the point of zero information generation" (`epistemic-limits.md` §1.3). A fresh desk critique of a certified snapshot is such a test, so it is not run on a re-ask (§5.3). |
| P14 | **Where contact decides and the choice is irreversible, carry a set of alternatives with elimination tests; never pick early.** | Toyota delays commitment "yet has what may be the fastest … development cycles in the industry", and establishes "feasibility before commitment" (Sobek, Ward & Liker 1999, `epistemic-limits.md` §1.5). Loch, De Meyer & Pich call parallel trials "selectionism" (§1.9). A discovery at build time then removes one member of the set; it does not reopen a decision. |

---

## 2. Phase F0: intake and the Research Contract (the frame)

This is where most of the effort goes. The frame is small compared with the content, so hunting for holes here is cheap, and every hole found here costs nothing later.

### F0.1 Prior-art and history sweep (agent-driven; closes C6 and prepares C2u)

Before talking to the operator, a mining workflow reads:
- `docs/research/**` and `docs/plans/**` in this repo and sibling repos. Build and reuse `docs/research/INDEX.jsonl` (topic, path, date, status). No such index exists today: 404 entries (`stop-rule-machinery.md` §4).
- Transcripts (`~/.claude*/projects/*/*.jsonl`) for the project's nouns, including prior operator decisions such as the apex-domain ruling (`c0f857b6` 2026-09-20T17:47:22Z).
- `msg search` for operator-private context such as relationships and agreements. Hole 194, the in-person agreement with the author, reversed a plan built on "unresponsive" (`dcbd2f8e` 20:31:36Z).
- Memory (`cc-memory-search`), `cc-backlog list`, `cc-decide list --open --json`, `cc-mission list`, `cc-sessions`.
- **Topic lock.** If a live owner of the topic exists (a positive liveness signal: a commit minutes old, a live pane, open custody), stop and join it. Never declare it dead from absence (hole 139: "three plans for one topic").

Output: `intake-mined.md`, with every claim quoted and a receipt.

### F0.2 Intake interview (closes C2u; one sitting, pre-filled)

The agent pre-fills each answer from F0.1. The operator only confirms or corrects, which takes about 30–60 minutes of operator time. The fixed questions:

1. **Consumer.** Who uses the deliverable, who installs it, and in what shape? (Hole 198: "deploy was a 4-step human doc; operator needed one-prompt".)
2. **Operator-private facts.** Relationships, agreements, accounts, tenants and devices the operator owns (hole 147: "example.com M365 tenant existed all along").
3. **Prior decisions that bind.** A mined list for the operator to confirm.
4. **Deployment reality.** Where it runs, what keeps it alive, what expires, and who re-authenticates. (SevenRooms: a 9-day outage from a laptop dependency never modeled, `greenfield-cases.md` mechanism 8.)
5. **Definition of "not lacking",** in the operator's words (the SevenRooms insight brief "judged lacking twice" until asked, `SEVENROOMS_MIRROR.md:353`).
6. **Taste targets.** A positive reference set (URLs, screenshots) and who judges it.
7. **Deadline and the cost of a post-build hole relative to a research day.** This is the Dalal–Mallows `c/f` ratio; §7 turns it into the certification target.
8. **Explicit exclusions.** What is out of scope, quoted.

Output: `intake.md`, holding the operator's verbatim answers.

### F0.3 Superlative translation (closes C11)

Each superlative in the ask ("100th percentile", "maximally fast", "perfect") becomes one or more predicates, each with:
- a measured ceiling, measured in F0 by a quick probe. Hole 11: "maximally fast" was never compared with the 0.14 s engine ceiling;
- a pass threshold;
- the branch taken if the result is negative (hole 179: no negative-result branch).

Taste becomes: a positive reference set, plus the operator's eye as a named gate, plus a structural pre-screen. A ban-list is never the acceptance test (holes 62, 65, 66). Any "hold until perfect" gate carries an expiry date (hole 56: a warm lead went unanswered for 21 days).

### F0.4 Frame construction

The lead drafts the contract rows:

| Register | Row type | Content |
|---|---|---|
| **Decisions** `D-nn` | every implementation decision the research must settle | question, type (`fact` / `design` / `taste`), options (the census must include **do-nothing** and **use-what-exists**), premises it rests on, the plan sections it affects, **closure instrument** (P12: `desk`, or one of `spike` / `model-check` / `tracer` / `prototype` / `load-fault` / `deploy-rehearsal` / `operator-eye`), **reversibility** (`reversible` / `costly` / `irreversible`) |
| **Evidence sources** `E-nn` | every source the research must consult | our stores (repo, transcripts, `msg`, memory, backlog) **and** the ones we do not write: upstream issue trackers, registries, vendor docs, access and production logs, the public web, the operator's accounts and tenants. The certificate states completeness relative to this list (P11). |
| **Questions** `Q-nn` | research questions | each maps to ≥1 D-row. A question that maps to no decision is dropped at F0 (its VOI is 0). |
| **Axes** `X-nn` | strata of the question space | project-specific axes plus every applicable **Hole-Pattern Checklist** row (§2.1) |
| **Coverage cells** `C-Qnn-Xnn` | question × applicable axis | closed when both code-saturated (topics named) and meaning-saturated (specified to implementation depth). Hennink 2017 shows breadth arrives about 2× before depth. |
| **Censuses** `K-nn` | populations to enumerate | options, candidates, callers, instances, execution contexts, accounts/tenants, concurrent actors, publication surfaces, invariants, evidence sources |
| **Premises** `P-nn` | load-bearing facts | seeded by the lead; grows in F1–F2 |
| **Acceptance** `A-nn` | the deliverable's properties | a check command, a target environment and a planted-defect control. This is the build's acceptance matrix, written now. |
| **Residual** `R-nn` | what research on this machine cannot settle | production, a tenant, elapsed time, or the operator's eye. Each has an owner, a date, a check command and a budget line in the build plan. |
| **Materiality** | three levels | **M1**: flips a D-row choice, an interface, a sequencing, an A-row, or a risk above the declared bar. **M2**: refines a D-row without flipping it. **M3**: cosmetic. Only M1 can reopen research. |
| **Stop rule and budget** | pre-registered parameters | §4 and §7 |

**Frame-size rule.** Keep the top level reviewable: about 7–10 decision groups, each carrying its own D-rows. The STPA Handbook caps system-level hazards at "no more than 7 to 10" because a longer list is "harder to identify things that are missing" (p.19–20, `systems-engineering.md` §4). A frame too long to review cannot be critiqued for omissions, and F0.5 exists to find omissions.

**Depth follows reversibility and instrument (P12, P14).**
- A `reversible` D-row gets a capped decision: at most 2 runs, the cheapest defensible option, and a `revisit_trigger` recorded for the build. Researching a reversible choice to 100% buys an option nobody needs (real-options reasoning, `epistemic-limits.md` §1.8, marked there as reasoning, not a citation).
- An `irreversible` D-row whose closure instrument is not `desk` must either close in F3 or be carried into the build as a set of 2–3 alternatives, each with an elimination test and the build wave that runs it.

### F0.5 Frame critique (the only open-ended "what's missing?" in the method)

This is the one step where the method asks "what is missing?", and it asks it about the **frame**, not the content. It is bounded:
- **Two rounds, pre-declared.**
- Each round runs **6 blind panels across ≥3 model families** (§3.3).
- **Zero is an expected answer.** Every proposed row must cite a location and the D-row it would affect.
- An adjudicator deduplicates, and the lead integrates the accepted rows by editing, not appending (C7).
- The Hole-Pattern Checklist (§2.1) is applied mechanically: every pattern is either mapped to a frame row or marked N/A with a reason.

**Frontier use:** Fable 5.1 sits on one or two of the six panels as a *different family*. The argument for it is its different blind spots, not greater strength (`CLAUDE.global.md` Frontier Tier Routing). Shard 7's pattern 1: the "what's missing" reviewers "audit what the plan *says*". The stale base, "author unresponsive", the single-session frame and "a human is the installer" were all premises no reviewer examined (`shard-7.md:159`, its H2/H15/H14/H19). C4, the class with the most decision-changing holes (22 of 32, `taxonomy.md:29`), is where such escapes land. F0.5 is where unstated premises get named, for example the base version (ledger hole 181) and the installer (ledger hole 198).

### F0.6 Ratification (operator act)

- The contract renders to a one-page summary: counts per register, the definition of complete, the stop rule, the budget and the price table.
- It is opened as a `cc-decide open --class C` packet with the options `ratify::research starts against contract vN` and `amend::name the rows`.
- The ratified contract is hashed. From then on it changes only through a **change request** that carries a cause (§6).
- The session DoD becomes one falsifiable line: `Scope (frozen): research contract <slug> vN (sha …) certified — proven by fcr gate --project <slug> exiting 0`. No superlative text.

### 2.1 Hole-Pattern Checklist (HPC v0), derived from the 200-hole corpus

Every contract maps each row to a frame row, or marks it N/A with a reason. Ids refer to `/tmp/rescomp/taxonomy_holes.py`. The file lives at `docs/research/hole-patterns.jsonl` and grows every time a post-gate frame defect is found (§6).

| HP | Frame axis the contract must carry | Corpus holes it would have caught |
|---|---|---|
| 01 | Option census includes do-nothing and use-what-exists | 110, 120, 68 |
| 02 | Candidate census drawn from the artifact itself (repo, fork, installed), not from memory | 173, 69 |
| 03 | Upstream or base version as an explicit D-row; upstream issue tracker as an evidence source | 181, 182 |
| 04 | Instance census: every checkout, copy and deployed instance | 88, 102 |
| 05 | Caller and consumer census keyed by name, not path | 90, 44 |
| 06 | Execution-context matrix: deployment interpreter, scheduler, CI/build OS, real device vs simulator | 92, 91, 95, 153, 41 |
| 07 | Liveness and expiry: where it runs, what keeps it alive, what expires, who re-authenticates | 168, 96, 16, 170 |
| 08 | Concurrency and the fleet case: concurrent actors, N>1 instances, generator vs UI races | 193, 126, 142 |
| 09 | Publication surfaces: public mirrors, forks, jobs that push | 175, 187, 190 |
| 10 | Operator-owned accounts, tenants and devices | 147, 134 |
| 11 | Evidence beyond our own stores: access logs, issue trackers, the public web | 57, 111, 182 |
| 12 | Prior invariants, each with a guard test | 159, 141 |
| 13 | Handed commands run by the agent under the operator's real invocation (`!`, no TTY, launchd) | 155, 91, 156 |
| 14 | Platform and feature-support matrix | 33 |
| 15 | Deliverable consumer and install path | 198 |
| 16 | Operator-private relationships and agreements | 194, 107 |
| 17 | Hazard census: write paths to live data, destructive instruments | 10, 90, 126 |
| 18 | Seams with sibling plans: an owner for every producer and consumer | LIMIT_RECOVER_100P.md:772-777 |
| 19 | A measured ceiling for every performance or superlative target | 11, 15 |
| 20 | Positive reference set for taste | 62, 65, 66 |
| 21 | Pre-registered thresholds and a negative-result branch | 179 |
| 22 | Every hold carries an expiry | 56 |
| 23 | Freshness: sibling trunk activity, registry releases, credential validity | 119, 165, 103, 164, 96 |
| 24 | Research probes never mutate the live subject | 49 |
| 25 | Compliance and data-residency gate for external deliverables | 87 |
| 26 | Real artifacts, n>1, a load control | 191, 53 |
| 27 | Property list includes liveness and recovery, not only safety; every proposed fix is checked with the instrument that found the bug | external: AWS "Failed to find a liveness bug as we did not check liveness" and "found a bug in the first proposed fix" (`epistemic-limits.md` §1.2); corpus analogue C7 |
| 28 | Emergent load or feedback behavior (retry storms, fleet contention) exercised on a running thin slice | external: AWS p.5, chaos principles (`epistemic-limits.md` H2); corpus analogue 191 |
| 29 | Deploy rehearsal, rollback and kill switch designed before the build | external: Knight Capital, SEC 2013-222 (`epistemic-limits.md` H7); corpus analogues 95, 121 |
| 30 | Evidence-source register reconciled: every E-row consulted or marked N/A with a reason | 57, 111, 182 (P11) |

Ledger check (2026-09-30, after the reboot). Every corpus id above was printed from `taxonomy_holes.py` and falls in the class the row claims. One loose fit: HP04's id 102 ("gone+locked registrations get false remedy", C9) is a remedy-population case rather than an instance-census case. HP27–29 carry no corpus hole; they come from external evidence and are labeled that way.

---

## 3. The research loop (F1–F5) and its roles

Each phase runs as **one dispatched session** (`handoff-fire.sh`, execution locus S), with a measurable goal: `fcr gate --project <slug> --phase Fx` exits 0, proven by the session printing that output. The lead holds only the ledgers, never the research content (§8).

### 3.1 Phases

| Phase | Work | Closes | Exit sub-gate |
|---|---|---|---|
| **F1 Census and premise** | Enumerate each `K` census **by two independent methods** (e.g. grep by name plus a runtime trace; the registry plus the repo) and reconcile the union. Every premise under a D-row with tier `secondary` is read at its primary source or measured. Every external fact gets a `recheck_cmd` and a TTL. | C3, C4, C10 (setup) | every K reconciled; no D-row rests on a `secondary` premise |
| **F2 Axis research** | Deep-research workers, one per cell cluster, briefed with the contract rows they serve. Adapted brief: no gap quota; findings carry locus and D-row. Waves of 8–12 (`research-subagents` N band). Every D-row gets a conviction number with a receipt. Design and taste D-rows close by decision (conviction ≥90, or operator-ruled against the reference set), not by saturation (Braun & Clarke 2021). | C4, C6, C11 | every cell code- and meaning-saturated with evidence paths that exist; every `desk` D-row settled or ruled (a `reversible` one inside its 2-run cap, with a revisit trigger); every non-desk D-row queued for F3 with its instrument named, or explicitly `residual` |
| **F3 Contact** | Every A-row check is run against current trunk and the target environment. First it is shown **red on a planted defect**, then green (or red) on the real subject. Spikes run on the deployment interpreter and OS, live processes are read, real artifacts are used at n>1 with a load control, and every command that will be handed to the operator is run by the agent. Probes are read-only against live subjects; anything that mutates runs on a disposable replica. Every D-row whose closure instrument is not `desk` runs that instrument here: a **spike** for one named technical question (thrown away), a **tracer** slice end to end in the real configuration (kept), **model-check** for concurrency and failure-recovery designs and for every proposed fix to them, **load-fault** on the tracer slice, **deploy-rehearsal** including rollback (`epistemic-limits.md` §3 H1–H7). Anything still needing production, a tenant or time becomes an `R` row. | C5, C9 | every A-row has `red_proof` and a target-env result, or an R-row; every non-desk D-row has its instrument's result, a carried set (P14), or an R-row |
| **F4 Synthesis and freeze** | The plan is written *from* the ledgers. A **traceability check** runs: every finding id in research artifacts maps to a plan item or a recorded rejection. A **store reconciliation** runs: plan-prose open markers, research residual sections, backlog rows, open decisions, custody and dirty files are each reconciled to done, not-required-with-reason, or filed. Then a whole-artifact consistency read (C7) and a snapshot `S_k`: the plan plus ledgers, hashed. | C1, C6, C7 | traceability 100%; 0 M1 contradictions; snapshot hash recorded |
| **F5 Certification** | Blind, seeded, family-diverse panels on the frozen `S_k` (§3.3). Adjudication, typed intake (§6), materiality votes, estimation (§4.4, gated by §5.1 G8). Material in-frame misses are fixed in `S_{k+1}`, then a **delta round** re-audits only the changed spans and their dependents. At most `R_max` rounds, pre-declared (default 3). | C5, C7, C8 | G8 |

### 3.2 Roles

| Role | Model and effort | Rule |
|---|---|---|
| Lead (per phase, dispatched) | Opus 5.5, high | Holds ledgers only; integrates by Edit; never runs a critic loop that fixes inside the loop |
| History miner (F0.1) | Opus 5.5, medium | Receipts only; output is quoted claims |
| Census enumerators (F1) | Opus 5.5, medium; two methods by different agents | A method is a command or a procedure, never recall |
| Premise verifier (F1) | Opus 5.5, medium | Moves each premise to tier `code` / `live` / `measured`, or flags it |
| Axis researchers (F2) | `deep-research` agent type with an FCR brief, high | Zero gaps allowed; every finding carries locus and D-row |
| Contact prober (F3) | Opus 5.5, medium; worktree isolation only when mutating a scratch copy | Red on the planted defect first; records the exact invocation and the environment |
| Seeder (F5) | A family different from the panels' majority, high | Writes a sealed seed file; never a panelist |
| Certification panelists (F5, F0.5) | ≥3 families (§3.3), xhigh for Anthropic panels | Blind: no ledger, no other panels' output, no seed list; frozen snapshot path only |
| Adjudicator (F5) | Opus 5.5, xhigh; a second adjudicator on a 20% sample | Panel-blind deduplication; matches seeds; logs every split and merge |
| Materiality voters | 3 independent voters, mixed family, medium | M1 needs ≥2 of 3, **and** independent reproduction of the claimed decision flip |
| Frontier (Fable 5.1) | xhigh | Only (a) as a panel family in F0.5 and F5, and (b) the frontier ladder on a D-row still below 90% after exhaustive research, where what remains is a framing question (Follow-On Gate F2 third outcome). Never for routine cells. Counts against the contract's `fable_slots_max` (6 per phase session), which `fcr round` enforces. `frontier-spawn-gate` counts it only on Agent-tool spawns (§8.3). Fable writes findings and documents, never edits. |

### 3.3 Certification panel design (capture occasions)

- **T ≥ 8 panels per full round.** Below 4, no estimator works (Briand et al. 2000, lines 855-857).
- **≥3 families.** Opus 5.5 and Fable 5.1 are both Anthropic models, so same-provider correlation applies (Kim 2025). **At least one panel family must be non-Anthropic.** Re-measured 2026-09-30 after the reboot; this corrects an earlier line that said the CLIs were simply "present":
  - `codex` at `~/.local/bin/codex`: `codex login status` prints "Logged in using ChatGPT", rc 0.
  - `gemini` exists only under fnm node installs (`~/Library/Application Support/fnm/node-versions/v22.21.1/installation/bin/gemini`, also v18/v20). `~/.gemini/settings.json` selects `oauth-personal`, and `oauth_creds.json` is dated 2026-02-22. Whether that token still authenticates is **unverified**.
  - `pi` exists only under node v22.21.1.
  - `grok-wiki` is at `~/bin/grok-wiki`.
  - `antigravity` is at `~/.antigravity/antigravity/bin/antigravity`.
  - `grok` exists only as the cmux-bundled `/Applications/cmux.app/Contents/Resources/bin/grok`.
  - `cursor-agent` (`~/.local/bin`) and `opencode` (`~/.opencode/bin`) are present and not yet assessed.
  - **Contact finding about the method itself:** a Workflow agent runs with `PATH=/Applications/kitty.app/Contents/MacOS:/usr/bin:/bin:/usr/sbin:/sbin` (observed in this workflow slot), so every one of these CLIs reads MISSING by bare name. A non-Anthropic panel slot must call absolute paths, or source the PATH entries from `~/.zprofile:9` and `~/.zshrc:204-228`. A slot that silently fails to find its CLI is a dead slot, and G8 must fail on it.
- **Perspectives** vary across panels (operability, data, security, consumer, adversarial "assume it fails"). **Context strategy** varies too (full repo, plan only, plan plus ledgers). Each panel's `family / perspective / strategy` is recorded as covariates.
- **Seeds.** About 30 representative seeds, written to match real hole strata and adapted from HPC patterns for this project, are injected into a *copy* of the snapshot. About 15 escape seeds come from the 200-hole corpus. Escape seeds are a hard-tail recall gate, never the Mills denominator: as a denominator they overestimate about 2.5× (`unseen-estimation.md` §5 row I).
- **Blindness is enforced.** Panels never see prior holes. A re-found known hole counts as a *recapture*, which the estimator needs; it is not a new item. This removes the conflict between "do not re-raise" and "capture-recapture needs independent occasions".
- **Singletons are kept** until estimation. They are verified before they enter scope, but they are never deleted first (Deng 2024: dropping singletons makes the estimate read "complete").
- **Adaptive follow-up** (e.g. "here is round 1, find more") is allowed only in F2. Its finds never enter the incidence matrix (Böhme 2021).
- **The certification prompt** (adapted from `llm-failure-modes.md` §3.3):
  - Part 1: YES / NO / UNKNOWN with a receipt for every A-row and D-row in scope. No receipt means UNKNOWN.
  - Part 2: optional candidate holes. Each carries a locus, the D-row or A-row it flips and how, a frame class, and a probability plus a falsifier.
  - "Proposing zero is correct and expected."

---

## 4. Persisted artifacts and schemas

Location: **the project repo**, `docs/research/fcr/<slug>/`, tracked and never in /tmp (C6: "5 of 9 research artifacts existed only in /tmp", `greenfield-cases.md`). Format: JSON/JSONL; a Markdown view is rendered, never hand-edited. Stores are append-only event logs; current state is the fold (the same model as `cc-backlog`). The sealed seed file is committed as a sha256; its content stays outside the panels' reach (§8).

### 4.1 `contract.json` (frozen; changes only through `changes.jsonl`)

```json
{
  "slug": "proj", "version": 3, "sha256": "…", "status": "draft|ratified",
  "ratified": {"packet": "cc-decide id", "at": "ISO", "operator_quote": "…"},
  "deliverable": {"statement": "one sentence, numbers, no superlatives", "consumer": "…", "deploy_target": "…"},
  "intake_path": "intake.md", "prior_art_path": "intake-mined.md",
  "definition_of_complete": {
    "frame_closure": "every D,Q,C,K,P,A row closed with a receipt; every R row owned and dated",
    "residual_target": {"severity": "M1", "g": 0.95, "chao2_residual_max": 1.0, "jk2_residual_max": 2.0},
    "seed_recall_min": 0.90, "escape_recall_floor": 0.50, "rounds_max": 3
  },
  "materiality": {"M1": "flips a D/A row, interface, sequencing or risk ≥ bar", "M2": "refines without flipping", "M3": "cosmetic"},
  "superlatives": [{"operator_words": "…", "predicate": "…", "ceiling": "…", "measured_by": "cmd", "negative_branch": "…"}],
  "hpc": {"version_sha": "…", "map": [{"hp": "HP-07", "row": "X-04|K-02|N/A", "reason": "…"}]},
  "sources_path": "sources.jsonl", "frame_groups_max": 10,
  "stop_rule": {"panels_min": 8, "families_min": 3, "non_anthropic_min": 1, "fable_slots_max": 6,
                "cli_paths": {"codex": "~/.local/bin/codex", "gemini": "<fnm node bin, resolved and recorded at F0>"},
                "families": ["claude-opus-5-5", "claude-fable-5-1", "codex"], "perspectives": ["…"],
                "seeds": {"representative": 30, "escape": 15}},
  "budget": {"agent_runs": {"F0": 25, "F1": 40, "F2": 30, "F3": 30, "F4": 5, "F5": 90},
             "wall_days": {"F0": 2, "F1": 1, "F2": 2, "F3": 2, "F4": 0.5, "F5": 2},
             "overrun_factor": 1.5, "reserve_fraction": 0.2, "c_over_f": 20},
  "freshness": {"default_ttl_h": 72, "trunk_sha_at_ratify": "…"}
}
```

### 4.2 Row registers (one JSONL each; fold by `id`)

| File | Required fields |
|---|---|
| `decisions.jsonl` | `id, group, question, type(fact/design/taste), options[{label, evidence}], has_do_nothing, has_use_existing, chosen, conviction(0-100), receipt, premises[P-ids], depends_on[], affects[plan anchors], closure_instrument, reversibility(reversible/costly/irreversible), revisit_trigger, carried_set[{label, elimination_test, build_wave}], status(open/settled/operator-ruled/carried/residual), packet, validated_at_sha, ts` |
| `sources.jsonl` | `id(E-nn), source, kind(ours/external/operator-owned/production), access_cmd, consulted(bool), consulted_at, evidence[paths], n_a_reason, ts` |
| `coverage.jsonl` | `id(C-Qnn-Xnn), question, axis, d_ids[], code_saturated, meaning_saturated, evidence[paths], status(open/closed/n_a), n_a_reason, snapshot, ts` |
| `censuses.jsonl` | `id, population, methods[{name, command, count, artifact}], union_count, disagreements[], reconciled, members_artifact, ts` |
| `premises.jsonl` | `id, statement, tier(code/live/measured/secondary), source, observed_at, recheck_cmd, ttl_h, validated_at_sha, supports[D-ids], status(verified/flagged/refuted), ts` |
| `acceptance.jsonl` | `id, property, check_cmd, target_env, invocation(tty/!/launchd/ci), n, load_control, control{planted_defect, red_observed, red_output}, result{rc, output}, status, ts` |
| `residual.jsonl` | `id, item, kind(TBD/TBR), why_not_now(production/tenant/time/operator-eye), check_cmd, owner, due, budget_runs, build_wave, status`. This is NASA's TBD/TBR ledger: "clearly identified with acceptable plans and schedule for their disposition" (`systems-engineering.md` §1). A known unknown listed here does not block the gate; an unlisted one is the failure mode. |

### 4.3 `holes.jsonl` (the hole ledger; event log)

```json
{"id": "H-0042", "event": "raise|adjudicate|classify|verify|dispose|reopen",
 "text": "…", "locus": {"path": "…", "line": 0, "quote": "…"},
 "raised_by": {"session": "…", "agent": "…", "family": "codex", "perspective": "ops",
               "round": 2, "snapshot_sha": "…", "blind": true, "post_gate": false},
 "dup_of": null, "seed_match": null,
 "frame_class": "in_frame_miss|frame_defect|frame_expansion|relabel_known|contact_residual|drift|set_elimination|immaterial|rejected",
 "taxonomy_class": "C1..C11",
 "evidence_source": {"row": "E-04|null", "in_register": true},
 "materiality": "M1|M2|M3", "materiality_votes": ["M1", "M2", "M1"],
 "opr_class": "significant|functional|process|lifecycle_data",
 "decision_affected": {"row": "D-07", "flips_to": "…", "repro_receipt": "…"},
 "impact_rows": ["D-07", "C-Q03-X02", "A-11"],
 "disposition": "fixed_in_snapshot|cr_opened|residual|backlog|dropped|duplicate",
 "counted_as": "process_defect|frame_defect|scope_growth|none", "ts": "ISO"}
```

### 4.4 `rounds.jsonl` (the incidence matrix and estimates per certification round)

```json
{"round": 2, "type": "full|delta", "snapshot_sha": "…", "scope": "all|changed spans+dependents",
 "panels": [{"id": "p1", "family": "claude-opus-5-5", "perspective": "…", "strategy": "…", "alive": true, "tokens": 0}],
 "matrix": {"H-0042": ["p1", "p4"]}, "seeds_found": {"S-07": ["p2"]},
 "estimates": {"severity": "M1", "S_obs": 0, "Q1": 0, "Q2": 0, "chao2_bc": 0, "jk1": 0, "jk2": 0,
               "coverage": 0, "q0": 0, "next_panel_expected_new": 0,
               "m_g": {"0.90": 0, "0.95": 0, "0.99": 0, "asymptote": 0},
               "seed_recall": {"representative": 0, "escape": 0, "rule_of_three_miss_ub": 0},
               "per_family": {"claude-opus-5-5": {"S_obs": 0, "chao2_bc": 0}}},
 "yield_curve": [10, 7, 2]}
```

### 4.5 `verdicts.jsonl` (verdict history, the take-back detector) and `changes.jsonl`

```json
{"ts": "ISO", "contract_sha": "…", "snapshot_sha": "…", "trunk_sha": "…",
 "gate": {"G1": "pass", "G2": "pass", "…": "…", "G12": "pass"},
 "verdict": "certified|certified_at_accepted_bound|not_certified|stale", "accepted_bound_packet": "cc-decide id|null",
 "certificate": "rendered text, §5.2",
 "supersedes": "ts|null", "take_back": false, "take_back_cause": null}

{"id": "CR-3", "cause": "operator_new|operator_unelicited|frame_defect|reality_moved",
 "text": "…", "justification": "why the ratified frame did not contain it",
 "affected_rows": ["…"], "ruling": {"packet": "cc-decide id", "ts": "ISO"},
 "counted_as_takeback": false}
```

---

## 5. The exit gate and the re-ask protocol

### 5.1 Exit gate `fcr gate --project <slug>` (exit 0 only when every row passes)

| Gate | Checkable criterion (script-computed; UNKNOWN fails) | Class |
|---|---|---|
| **G1 Contract** | `contract.json` status `ratified`; sha matches; its cc-decide packet is `actioned`; no open CR | C2, C11 |
| **G2 Decisions** | every D-row `settled` (conviction ≥90 with an existing receipt), `operator-ruled`, `carried` (a set of 2–3 alternatives, each with an elimination test and a build wave), or `residual` with an R-row; no settled D-row lists a premise with tier `secondary` or status `flagged`; every non-desk D-row has its closure instrument's result or is carried | C3, C4, C9 |
| **G3 Censuses** | every K-row `reconciled` with ≥2 methods; option censuses have `has_do_nothing` and `has_use_existing` true | C4 |
| **G4 Coverage** | every cell `closed` (code- and meaning-saturated, every evidence path exists) or `n_a` with a reason recorded at ratification; HPC map has no unmapped pattern; every E-row in `sources.jsonl` `consulted` or `n_a` with a reason | C4, C6 |
| **G5 Acceptance** | every A-row has `control.red_observed=true` and a `result` from `target_env`, or a linked R-row; n and load control match the contract | C5, C9 |
| **G6 Traceability** | every finding id in `docs/research/fcr/<slug>/**` resolves to a plan anchor or a recorded rejection | C6 |
| **G7 Consistency and freeze** | the last whole-artifact consistency read is newer than the last edit; 0 M1 contradictions; the plan hash equals `snapshot_sha` of the certifying round | C7 |
| **G8 Certification** | on the certifying full round: T ≥ `panels_min`, families ≥ `families_min`, ≥1 non-Anthropic, **every slot alive** (a dead or partial slot fails the gate); for M1 holes, `chao2_bc − S_obs ≤ 1.0` and `jk2 − S_obs ≤ 2.0`; representative seed recall ≥ 0.90; escape seed recall ≥ floor; every M1 hole from that round fixed and a delta round on the changed spans and dependents returns 0 new M1; rounds ≤ `rounds_max` | C5, C7, C8 |
| **G9 Freshness** | every premise and external fact re-checked within its TTL (the `recheck_cmd` is run, not recalled); trunk activity since `validated_at_sha` touches no path in any D-row's `affects`; credentials in any A-row pass a validity probe | C10 |
| **G10 Residual** | every R-row has an owner, a due date, a check command and a build wave | C9 |
| **G11 Budget** | spend per phase reported against budget; any overrun has a cc-decide packet | timeline |
| **G12 Store reconciliation** | open markers in plan prose, research residual sections, `cc-backlog list --project`, `cc-decide list --open` for the project, custody and dirty files: each reconciled to done, not-required-with-reason, or filed with a class | C1 |

**Verdict states.** Every run of `fcr gate` appends a `verdicts.jsonl` row with one of four states:
- `certified`: every gate passes at the ratified targets.
- `certified_at_accepted_bound`: G8's residual or seed-recall target was missed, and the operator accepted the achieved bound through a class-B packet (§7 rule 2). The certificate prints the achieved numbers and the packet id.
- `not_certified`
- `stale`: G9 failed.

The certificate always prints the achieved bound, never only the target, so the operator can see which state was reached and why.

**Getting the gate into wrap-ledger.** Corrected after the reboot re-read. The earlier claim was that writing open gate rows as `- [ ]` lines into the DoD file needs "no change to `wrap-ledger.sh`". That holds only under three conditions:
1. The DoD store is repo-keyed and lineage-filtered. REMAINDER counts boxes after `dod_filter_for` keeps only the `## … · toplevel=<path> · session=<id>` blocks in the reading wave's lineage (`hooks/lib/dod-path.sh:155-185`; `scripts/wrap-ledger.sh:616-621`; live format `~/.claude/autonomy/dod/repo-dd814e49aae581ad.md:5`). So fcr must write its boxes inside an attributed block. Boxes placed before the first `## ` are "always kept", which would leak into every wave's REMAINDER.
2. REMAINDER sums every kept block. A later gate run must therefore flip its own earlier boxes to `[x]` in place, not append a new block.
3. A sibling wave outside the lineage never sees the boxes.

The recommended form is a small change instead: wrap-ledger reads `fcr status --machine` when a contract exists for the repo, and the GOAL rung is computed from it (≈10 lines, one reader). Boxes remain only as the zero-code fallback. Conviction 85% that the direct reader is better; the residual 15% is the cost of a second reader.

### 5.2 The certificate (what "100.00/100.00" means after F0 ratification)

```
Research certified: <slug> contract v3 (sha a1b2…) on snapshot 9f8e… at <ts>, trunk <sha>.
Frame: 100.00% closed: 18/18 decisions, 64/64 coverage cells, 9/9 censuses, 41/41 acceptance checks (all shown red first), 72/72 premises at primary tier.
Unknowns: 8 blind panels, 3 families; material holes found in the certifying round 6, all fixed and re-verified.
  Estimated M1 holes still unfound: 0.9 (Chao2, bias-corrected) / 1.6 (jackknife 2), inside the
  ratified targets ≤1.0 / ≤2.0. Both are lower bounds: correlated panels can hide a shared blind
  spot. Seed recall 0.93 (28/30); escape seeds 9/15.
Complete relative to 14 named sources (sources.jsonl); a source outside that list is a frame question, not a miss.
Carried into the build: 2 decisions as alternative sets, each with an elimination test and a build wave.
Declared residual (not research-reachable): 4 TBD/TBR items, owners and dates in residual.jsonl. Planned, not open.
What would reopen this: a material in-frame miss (location + the decision it flips, independently
  reproduced) · a ratified change request · a failed freshness re-check. Nothing else.
Price of more assurance: 95% target +7.6 panels (~0.5 day) · 99% +18 panels (~1 day).
```

### 5.3 Re-ask protocol (stops the loop)

1. **Detect.** A `UserPromptSubmit` hook matches the completeness-ask patterns already mined. The source regex is `Q` at `/tmp/rescomp/internal/ca_scan.py:6`: `100.00/100.00`, `100/100`, "are we (100%) complete/done", "absolute perfection". It should be widened with the "100th percentile" and "exhaustive" forms that `reask_scan.py` used (`stop-rule-machinery.md` §6). `reask_scan.py` did not survive the reboot. When the cwd or project has an FCR contract, it runs `fcr status --render` and injects the output as additionalContext labelled "RELAY VERBATIM; do not regenerate".
2. **Relay.** The answer's first lines are the certificate (or the not-certified gate rows), reproduced verbatim, under the Communication Discipline rule on rendered output. The session verdict (wrap-ledger rung) stays a separate line. `/are-we-done` gains a `Goal:` line computed from `fcr status` (P9).
3. **Run only computed checks.** The re-ask may run `fcr gate --freshness`: deterministic re-check commands, which are a measurement rather than a generator. It may not start a critique, a "fresh-eyes review", or a new panel. That kind of check did not exist until the question was asked (`989f6dbf` 05:26:16Z). FlipFlop measured that "are you sure?" flips answers 46% of the time, with a 17% average accuracy drop (`llm-failure-modes.md:128`). A desk re-read of a certified snapshot is also a test everyone expects to pass, which Reinertsen puts near "zero information generation" (P13). The information-rich next step is the certification extension of step 5, which is priced and pre-registered.
   The answer lists the TBD/TBR rows as **planned, not open**, with owners and dates. NASA's gate practice treats a listed known unknown with a disposition plan as mature, not incomplete (`systems-engineering.md` §1, M3).
4. **Admit a candidate only through intake (§6).** If the operator or the model names a specific concern, it enters `holes.jsonl` with its locus and goes through typed intake. The verdict changes only if intake yields a verified M1 in-frame miss, a ratified CR, or a failed freshness check. Every reversal is written to `verdicts.jsonl` with `take_back: true` and its cause, so reversals are counted rather than free.
5. **Priced extension.** If the operator wants more assurance, that is a class-B packet with the m_g price table, whose default is "no extension". The extension is a pre-registered continuation of the same statistics; its looks are counted in the certificate (Lewis et al. 2021 on sequential bias). It is never a reopen.
6. **Enforce.** A new `completion-assert` arm fires when an FCR contract is certified and a reply to a completeness ask reverses or hedges the certificate ("no, one more check", "not yet") without citing a hole id whose disposition is `in_frame_miss` + M1 verified, a CR id, or a failed G9 row. Its reason text: "answer from fcr status; route the concern through fcr hole add". The symmetric arm (claiming certified while `fcr gate` exits non-zero) extends the existing false-done arm.

---

## 6. After the gate: typed hole intake (no global reopen)

`fcr hole add --locus <path:line|quote> --text …` then `fcr hole classify H-x`:

| Step | Rule | Outcome |
|---|---|---|
| 1 Locus | No specific locus ⇒ `rejected` (generic "scalability", "edge cases": F15 generic-critique mode) | logged, no work |
| 2 Dedup | Matches a ledger row ⇒ `duplicate` / `relabel_known`; answer from that row's disposition. Re-raising needs evidence dated after the disposition. | no work (C1 relabels end here) |
| 3 Frame class | `in_frame_miss`: the row existed and the process missed it (C3–C8) · `frame_defect`: the frame should have had the row (a C4/C2u escape) · `frame_expansion`: a new operator requirement (C2n) · `contact_residual`: already an R-row (C9) · `drift`: a premise's re-check changed (C10) · `set_elimination`: a build-time result removed a carried alternative (P14). This is expected and never a reopen. **Mechanical tie-breaker (P11):** if the hole's evidence came from a source not in `sources.jsonl`, it cannot be `in_frame_miss`. It is `frame_defect` if the source was knowable at F0, else `frame_expansion`. | determines who pays and what reopens |
| 4 Materiality | 3 voters, ≥2 say M1, **and** the claimed flip is reproduced independently (FixedBench reproduce-first). Otherwise M2/M3. The M-levels map onto aviation's open-problem-report classes (AMC 20-189): M1 = **Significant** (blocks until resolved or mitigated with a justification); M2 = **Functional** (ships open with a recorded justification); M3 = **Process** or **Life-cycle data**. Only unmitigated Significant items block approval (`systems-engineering.md` §3). | M2/M3 ⇒ `cc-backlog add` for the build (or dropped); never a research reopen |
| 5 Impact scope | `fcr impact H-x` walks `depends_on` / `affects` / `supports` to the smallest set of rows and plan anchors | only those rows reopen |
| 6 Scoped repair | Reopened rows go back to their phase's sub-gate. A new snapshot is taken, then a **delta round** (≥4 panels, ≥2 families) on the changed spans and dependents. The rest of the certificate stands. | verdict amended, not replaced |
| 7 Accounting | `in_frame_miss` counts as a **process defect**. `frame_defect` counts against F0 and adds a pattern to HPC. `frame_expansion` is a CR (`cause=operator_new`), budgeted separately and **not** a take-back. `drift` is a CR (`cause=reality_moved`). | metrics §9.2 |
| 8 Change control | A CR carries a **presumption against change**. Its `justification` must state the decision it changes, its cost in runs and days, and why the ratified frame could not hold it. The ruling packet shows the cumulative CR cost against the contract budget. This mirrors the DoD Configuration Steering Boards (FY2009 NDAA §814: boards "approve or disapprove" changes that affect cost or schedule, and the program manager may "object to the addition of new program requirements"). The evidence behind it is GAO's 72% vs 11% cost growth (`systems-engineering.md` §6, M4). A **descope** CR (§814(c)(2)(B)) uses the same path and is priced as a saving. The operator stays the board, so this is a burden of proof, never a refusal. | the ratified frame stays the reference; growth is visible and priced |

**Build-time discoveries** go through the same intake. An M1 in-frame miss found during implementation triggers a scoped research sprint with its own two-page mini-contract. Everything else is build work.

**The operator's standing rules this touches.** The Follow-On Gate's F1 counts every refinement as net-positive under "nothing left on the table" (`CLAUDE.global.md:616-617`). `completion-assert` D4 says "the answer is always yes; drive it" (`completion-assert.sh:1278`). Under a certified contract, M2/M3 items would go to the build backlog instead of being driven as research. Those are operator-stated practices, so this change needs the operator's ruling (§8.4).

---

## 7. Time and effort budget model

**Unit.** One agent-run at a fixed brief and effort (Wood 1996: execution effort, not calendar time, predicts reliability growth). Tokens and wall-clock are derived from runs. Priors below are for a medium-large greenfield (≈15 D, 10 X, 8 K, 60 P, 40 A). They are **estimates to be calibrated**, not measurements. Actuals are logged to `docs/research/fcr-calibration.jsonl` after each project (reference-class forecasting).

| Phase | Agent-runs (prior) | Wall-clock (prior) | Operator time |
|---|---|---|---|
| F0 sweep, interview, translation, frame, 2 critique rounds, ratify | ≈25 | 1–2 days | 45–60 min interview + ratification read |
| F1 censuses (2 methods × K) and premise verification | ≈40 | 0.5–1 day | 0 |
| F2 axis research (2 waves × 10–12) | ≈30 | 1–2 days | D-rows ruled by operator: dated in `cc-decide` |
| F3 contact (A-rows + contact premises) | ≈30 | 1–2 days | 0 unless an R-row needs a credential |
| F4 synthesis, traceability, consistency | ≈5 | 0.5 day | 0 |
| F5 seeds, 1 full round (8 panels), ≤2 delta rounds, adjudication, materiality votes | ≈90 (many at low/medium effort) | 1–2 days | 0 |
| **Total** | **≈220** | **5–9.5 working days** | **≈1–2 h plus dated rulings** |
| Reserve | +20% for post-gate scoped reopens and one priced extension | | |

Calibration anchors from the corpus: research phases converged in 1–2 days and the weeks came afterwards (`greenfield-cases.md` answer first). DOCS_CONSOLIDATION went from first commit to programme complete in 25.75 h. FLEET_V2 landed W0–W6 in about 1.5 days after a 22-agent pre-build review. At roughly 150–250K tokens per substantial run, the prior is about 30–45M tokens. Check this against `claude-accounts` before ratification; it is not measured.

**Predictability rules:**
1. **Timeline formula:** T = Σ phase budgets + R_max × round time + dated operator latencies + reserve. Operator gates carry dates inside the contract, so dormancy is visible instead of being read as unfinished research (sevenrooms: idle 33 of 35 days, `greenfield-cases.md` mechanism 9).
2. **Overrun:** a phase at 1.5× budget stops and files `cc-decide open --class B` with conviction, a receipt and two options (`extend by N runs` / `accept current bound, proceed`). The default is proceed, firing at a deadline 24 h later. The timeline cannot silently stretch, and the operator keeps a veto.
3. **Certification price table.** After the first full round, `fcr estimate` computes m_g for g = 0.90/0.95/0.99 and the asymptote (Chao et al. 2009 Eq. 14–15). Worked example: T=8, S_obs=47, Chao2=56 gives +3.1/+7.6/+18/+33.8 panels. The operator's "100× for 1%" appetite becomes a **target chosen in advance** (g=0.99, or seed count 300 for a ≤1% miss rate at 95% by the rule of three) with a finite, stated price. It is never an open loop.
4. **The optimal residual is positive.** Dalal & Mallows 1988: expected remaining = f/(cμ). The intake's `c_over_f` answer sets g. A setting of c = ∞ means "never deploy", and the one-page contract summary says so in those words so the choice is deliberate.
5. **Budget per D-row follows its tier, so the F2 and F3 budgets are computed from the frame, not guessed.**
   - `reversible`: ≤2 runs plus a revisit trigger.
   - `costly`: the F2 wave share.
   - `irreversible` with `desk` closure: the F2 wave share, plus certification.
   - `irreversible` with a non-desk instrument: an F3 instrument budget, time-boxed. The spike box is "a week or two" at XP scale, and the prior here is 1–3 runs. Anything that does not close inside its box is carried as a set (P14) instead of extended.

   Boehm's "How much is enough?" is exactly this: effort is set by the risk of not doing enough, per item, not uniformly (`epistemic-limits.md` §1.4).
6. **Frame growth has a price tag at the moment it is proposed.** Each accepted CR re-computes T under rule 1 and prints the delta in its ruling packet (§6 step 8). The timeline moves only by ratified, priced changes, never by unlogged discovery.

---

## 8. Mapping to this environment: what to build

### 8.1 P0 (needed before the next greenfield starts)

| Build | What | Integrates with |
|---|---|---|
| `bin/fcr` | Verbs: `init` (with topic lock via `cc-sessions` + custody), `intake`, `row add/close`, `source add/consult`, `premise`, `census`, `accept`, `carry` (register an alternative set with elimination tests), `snapshot`, `round`, `hole add/classify`, `impact`, `cr`, `gate [--phase Fx] [--freshness]`, `status --render`, `ratify` (opens the cc-decide C packet). Stores per §4; append-only fold like `cc-backlog`. | cc-decide (ratification, D-row rulings, CRs, overruns); cc-backlog (M2/M3 → build rows); cc-mission (R-rows with owners and dates when customer-facing) |
| `bin/fcr-estimate` (python) | From `rounds.jsonl`: Chao2 (classic and bias-corrected), JK1/JK2, coverage (iNEXT formula), q0, next-panel expected new, m_g, Mills from representative seeds, escape recall, rule-of-three, per-family estimates. Unit tests against the worked example (47 → 56.0 / 54.2 / 57.5 / 62.0). | `fcr gate` G8 |
| Skill `research-contract` | This method: F0 script, interview questions, HPC, certification prompt, intake rules. Loaded by `/research` whenever a contract is requested or exists. | `/research`, plan-conventions |
| Edits to the quota prompts | Replace "List 3 with reasons" (`SKILL.md:798`, `:823`), "Find 2-3 gaps" (`deep-research.md:187`) and "name 1-3 missing axes" (`research-decomposition-critic.md:37-38`) with zero-allowed plus locus plus decision plus frame class. Scope the negative-space trigger to F0.5 only. Replace OASIS criterion 3's `c·N^α` fit, which has no asymptote and so can never state a residual, with the estimator. Under a certified contract, suspend "re-check ⇒ apply more aggressively" (`SKILL.md:944-948`). | research-subagents, agents/ |
| `/are-we-done` + wrap-ledger | Add a `Goal:` line from `fcr status` beside the session verdict. When a contract exists and is uncertified, the rung cannot be ✅. Preferred: wrap-ledger reads `fcr status --machine` directly (≈10 lines). Fallback with no parser change: `fcr gate` keeps its open rows as `- [ ]` boxes inside **one attributed `## … · toplevel= · session=` block that it flips in place**, because the lineage filter drops foreign blocks and keeps unattributed boxes for everyone (§5.1). | `commands/are-we-done.md:52-57`, `scripts/wrap-ledger.sh:616-621`, `hooks/lib/dod-path.sh:155-185`; also fixes absent-DoD ✅ (`wrap-ledger.sh:2286-2288`) for research sessions |
| Re-ask relay hook | `hooks/fcr-reask-relay.sh` (UserPromptSubmit): pattern match → inject `fcr status --render`. | §5.3 |
| `completion-assert` arm | Blocks an unsupported reversal of a certified verdict; extends false-done to `fcr gate` failure. | `hooks/completion-assert.sh` |
| `dod-persist` | Warn on a superlative in a `Scope (frozen)` line (generalizes `ground-up/SKILL.md:14-18`). Add a `cause=` field to `Scope (grown)`, which has none today (`dod-persist.sh:88-96`). | hooks |

### 8.2 P1 (Dynamic Workflows; saved, reusable, one per phase)

Workflow scripts have no filesystem access and no clock. Each workflow takes contract rows via `args`, returns schema'd results, and the dispatched-session lead writes them to the ledgers with `fcr`.

| Workflow | Shape |
|---|---|
| `fcr-frame` | `parallel` miners (transcripts, msg, memory, docs index, backlog/decisions/mission, sibling sessions) → 1 drafter → 2 fixed rounds × 6 blind critique panels (`model` per slot; a non-Anthropic slot is an agent that shells out, **by absolute path** because Workflow agents get a stripped PATH (§3.3), to `~/.local/bin/codex exec` / the fnm-installed `gemini -p` / `~/bin/grok-wiki ask --agent codex` and relays the output verbatim; a slot whose CLI is missing or unauthenticated returns `alive:false`, never an empty finding list) → adjudicator. |
| `fcr-census` | `pipeline(censuses, methodA, methodB, reconcile)`; methods by different agents, no shared context. |
| `fcr-premise` | `pipeline(premises.filter(tier==secondary), verifyPrimary)`. |
| `fcr-axis` | `pipeline(cellClusters, deepResearch(agentType:'deep-research', FCR brief), findingsToRows)`. |
| `fcr-contact` | `pipeline(acceptanceRows, plantDefectAndRunRed, runOnTarget)`; `isolation:'worktree'` only when a probe mutates a scratch copy. |
| `fcr-certify` | `seeder` → `parallel` T blind panels on the seeded snapshot copy → adjudicator (panel-blind dedup, seed match) → `pipeline(candidates, 3 materiality voters, reproducer)` → returns the incidence matrix. `fcr-estimate` runs after the workflow returns. |
| `fcr-delta` | Same as certify, restricted to the changed spans plus dependents; ≥4 panels, ≥2 families; not pooled with full rounds. |

The workflow-authoring reference's generic "loop-until-dry" (K consecutive empty rounds) and "completeness critic … becomes the next round of work" patterns may be used for discovery in F1–F3, **never for certification**. The first is the "N consecutive nothing-found" rule, which missed its recall target in 39% of cases (Callaghan & Müller-Hansen 2020). The second is the open generator that did not converge in the corpus.

### 8.3 Sessions, goals and frontier

- **Execution locus S per phase:** `scripts/handoff-fire.sh --prompt-file /tmp/fire-fcr-<slug>-F2.txt --worktree fcr-<slug>-f2 --notify-back … --goal 'fcr gate --project <slug> --phase F2 exits 0 — proven by the session running it and printing the output; do not edit contract.json; DoD at docs/research/fcr/<slug>/contract.json'`. Everything is on disk, so a recycle between phases loses nothing. This addresses the 8-day dormancy caused by "continuation depended on a live session's in-memory state" (`GROUND_UP_DISPATCH.md:414`).
- **A build cannot fire while the gate is red.** The build plan's Phase 0 lists `fcr gate` as the precondition of wave 1 (C8: "W1 fired while r4/r7 were open", `3c73a9d9`).
- **Frontier:** Fable panels in F0.5 and F5 count toward `frontier_discovery_budget.max_fable_spawns_per_session`, which is **6** (`~/.claude/model-config.yaml:1116`). The design's use fits because each phase is its own session: F0.5 uses ≤2 Fable panels × 2 rounds = 4, and F5 uses ≤2 in the full round + ≤1 per delta round × 2 = 4.
  Measured 2026-09-30 after the reboot: `hooks/frontier-spawn-gate.sh` is registered **only on the `Agent` matcher** (`jq` over `~/.claude/settings.json` returns one entry, matcher `Agent`). The Bash session arm stays inert until `migrations/0029` runs.
  A Workflow `agent({model})` call is not an Agent tool call, so whether the gate sees it is **unverified, and must be treated as uncounted**. The contract therefore carries `stop_rule.fable_slots_max: 6` per phase session, and `fcr round` refuses a round whose plan exceeds it. The bound lives in the tool that plans the round, not in a hook that may not fire.
  If Fable headroom is absent (`claude-accounts`), substitute another family and record the degradation in the certificate.

### 8.4 Adoption decisions that need the operator's ruling (they replace stated practices)

| # | Decision | Recommendation | Conviction |
|---|---|---|---|
| AD1 | For research, "100.00/100.00" means frame closure at 100.00 plus a stated residual bound, ratified per project | adopt | 88% (the statistical impossibility is proven; what remains is whether the operator accepts a bound as the answer) |
| AD2 | Under a certified contract, the Follow-On Gate's F1 test for *reopening research* is M1 materiality, not "nothing left on the table"; M2/M3 go to the build backlog | adopt | 85% |
| AD3 | `completion-assert` D4 ("drive every named item") is carved out for post-certification M2/M3 holes | adopt | 82% |
| AD4 | Remove the gap quotas from the three agent prompts | adopt | 92%. This is not a practice the operator stated, and it can go ahead without a ruling. |

---

## 9. Taxonomy coverage and residual

### 9.1 Every class, addressed or declared residual

| Class (n) | FCR mechanism | Where | What remains |
|---|---|---|---|
| **C1** Claim frame narrower (23) | Two-level close; goal verdict from `fcr status`; G12 store reconciliation; re-ask relay | F4, §5 | none by construction; a relabel answers from the ledger |
| **C2u** Unelicited intent (6) | History sweep (transcripts, msg, prior decisions) and pre-filled interview; operator co-signs | F0.1–F0.2, F0.6 | anything the operator withholds or forgets |
| **C2n** New requirement (6) | CR with `cause=operator_new`, a presumption against change and a priced timeline delta; a descope channel; budgeted; not a take-back | §6 steps 7–8, §7 rule 6 | **declared residual** (3%): legitimate growth |
| **C3** Unverified premise (29) | Premise register with tiers, TTL and re-check; G2 bars secondary tiers under decisions | F1, G2, G9 | premises measured wrongly (instrument error), which C5 controls reduce |
| **C4** Population not enumerated (32) | Censuses by two methods; do-nothing and use-what-exists; HPC; an evidence-source register that names stores we do not write (P11); frame critique across families | F0.4–F0.5, F1, G3–G4 | patterns no family and no HPC row anticipates; counted as `frame_defect` and fed into HPC |
| **C5** Instrument could not discriminate (29) | Planted-defect red proof on every A-row; target env, n>1, load control; handed commands run | F3, G5 | a control that shares the instrument's blind spot (the test-audit risk) |
| **C6** Research lost (12) | Research index; topic lock; traceability G6; repo persistence; ledger-first | F0.1, F4, G6 | none expected |
| **C7** Own edits create holes (10) | Integrate by Edit; whole-artifact read after the last edit; snapshot freeze; delta rounds on changed spans and dependents | F4–F5, G7 | fixes inside the final delta round (bounded by that round) |
| **C8** Review late or unsaturated (8) | Certification before any claim; dead slot blocks; pre-declared rounds; build blocked while the gate is red | F5, G8 | none by construction |
| **C9** Contact-only (30) | A closure instrument per D-row (P12); contact wave for the 24 local ones (spike, tracer, model-check, load-fault, deploy rehearsal); irreversible contact-decided choices carried as sets (P14); R-rows as a TBD/TBR ledger with owners and dates for production, tenant and time | F0.4, F3, G2, G10 | **declared residual** (6 of 30 in the corpus), budgeted post-build, never a reopen; a carried set's eliminations are expected, not holes |
| **C10** Reality moved (8) | TTL, re-check commands, trunk sha, sibling check at the gate and at build start; non-mutating probes | F1, G9 | **declared residual**: unforeseeable drift (4 in the corpus), handled as CR `reality_moved` |
| **C11** Criterion not operationalized (7) | Superlative translation with measured ceilings; positive reference sets; negative-result branch; hold expiry | F0.3, G1 | taste the operator's eye rejects after ratification: a CR, not a miss |
| *Beyond the taxonomy* | Universal blind spots of every model family (Link 2003: not identifiable from overlap) | G8 seeds | **declared statistical residual**: bounded by seed recall, never zero |
| *Beyond the taxonomy* | Complex-domain unknowns whose cause and effect is visible "only in retrospect" (Cynefin), and emergent load behavior no model checker sees (AWS p.5) | P12, P14, F3 load-fault, R-rows | **declared residual**: carried as a plan-revision budget (the 20% reserve in §7) and as alternative sets, never as a "100% complete" claim (`epistemic-limits.md` §3 H2, H6) |

**Back-test caveat.** The taxonomy puts 178 of 200 corpus holes within reach of steps like these, but "findable" is hindsight-assisted, especially for C4 (`taxonomy.md:343`). Treat 89% as an upper bound on what this design would have moved in front of the claim.

### 9.2 How we will know it works (measured on the first project, against the corpus baseline)

- **Take-backs:** `verdicts.jsonl` rows with `take_back=true`. Baseline: 144 of 222 completeness asks opened with a no/gap marker (crude, `stop-rule-machinery.md` §6).
- **Post-gate M1 escapes per project** by frame class, set against the certificate's estimate. This is estimator calibration: if escapes routinely exceed `jk2 − S_obs`, the correlation correction is too weak.
- **Frame-defect rate** (HPC growth per project) and **CR count by cause**.
- **Budget accuracy:** actual versus prior runs per phase, logged to `fcr-calibration.jsonl`.
- **Family × family overlap matrix:** the first measurement of how correlated LLM panels are when finding design holes. No published data exists (`unseen-estimation.md` §8).

---

## 10. Adversarial self-pass (what could make this fail, and the answer)

1. **"The frame itself will have holes, so C4 just moves into F0."** Correct, and intended: a frame hole is cheaper to find (the frame is small, and F0.5 attacks it with 12 diverse panel-runs plus 30 HPC rows) and it is counted (`frame_defect`), so the method improves each project. It is not eliminated.
2. **"Gate gaming: evidence paths that exist but do not support the claim."** The adjudicator's 20% second-rater sample re-derives closed cells. Materiality needs reproduction. G5 needs a red observation, not a file.
3. **"False closure (F7): the anti-churn rules suppress real misses."** The evidence burden is symmetric: YES needs a receipt, UNKNOWN fails the gate, and a candidate with a locus always enters intake. What is removed is only the *unanchored* regeneration.
4. **"Materiality will be gamed to M2 to avoid reopening."** Three mixed-family voters decide it, not the lead. M2/M3 rows go to the build backlog where they stay visible, and post-build escapes of "M2" rows that were really M1 are counted.
5. **"The estimators assume independence, and LLM panels are correlated."** Every estimate is reported as a lower bound. The non-Anthropic family minimum, per-family estimates and seeds (the only estimator that sees shared blind spots, per the simulation) are required. The gate thresholds are defaults to calibrate after the first project, stated as such.
6. **"The overhead is too high for small projects."** A lite profile scales down (T=6, 2 families, 15 seeds, one full round). The certificate states which profile was used.
7. **"Seeds are expensive and unrealistic."** Escape seeds are reused across projects from the corpus. Representative seeds are adapted from HPC patterns by a separate family. Easy synthetic seeds are known to underestimate (simulation row G: 169 vs 200), so the certificate never relies on them alone.
8. **Unverified inside this design** (updated 2026-09-30 after the reboot):
   - Now verified: codex is authenticated; the frontier gate is registered only on the Agent matcher; the cap is 6.
   - Still open: whether gemini's 2026-02-22 OAuth token still authenticates; whether a Workflow `agent({model})` spawn reaches the Agent-matcher hook (treated as uncounted, §8.3); the token prior (§7).

   Each is an F0 contact check for the method, not an assumption. The stripped Workflow PATH (§3.3) is a finding this design only caught by running a check on itself. That is P6 applied to the method.
9. **"The contract becomes the new perfection target, and the loop moves up one level."** The frame is bounded by construction: two pre-declared critique rounds, a frame-size rule of 7–10 groups, HPC applied mechanically, and a CR path with a presumption against change once ratified. A frame question after ratification is a CR with a price (§6 step 8), not a reason to re-run F0.
10. **"A presumption against change will suppress legitimate new requirements."** The operator is the board, and the CR is decided by a `cc-decide` packet. The presumption only puts the burden of proof, and the price, on the change (GAO: 72% vs 11% cost growth). A descope CR runs through the same path. C2n (3% of corpus holes) is budgeted, never scored as a take-back.
11. **"Carried alternative sets are indecision under another name."** Only irreversible D-rows whose deciding evidence is contact-only may be carried. Each member needs an elimination test with a build wave, and G2 fails a carried row without them. Toyota's evidence is that this shortens cycles (P14). The alternative is to pick one now and discover the "one more thing" later, which is the loop itself.

---

## 11. Re-verification after the 2026-09-30 15:26 CDT reboot

This file came back with the rebuilt `/tmp/rescomp` corpus (16:01). It predates the taxonomy re-derivation (16:15) and the two external reports that landed after it (`epistemic-limits.md` 16:07, `systems-engineering.md` 16:12). It was not rewritten. Its load-bearing claims were re-checked at their sources and it was extended by Edit.

**Confirmed unchanged at trunk `cda13e6a1`:**
- The gap quotas: `skills/research-subagents/SKILL.md:798` ("List 3 with reasons"), `:800-803` (drop only on the user's words), `:823`, `:944-948` ("apply this rule more aggressively"); `agents/deep-research.md:187` ("Find 2-3 gaps"); `agents/research-decomposition-critic.md:37-38, 80`.
- OASIS, with c·N^α and ε=0.5 in prose only: `SKILL.md:756-782`.
- The close computation: REMAINDER counts boxes at `scripts/wrap-ledger.sh:616-621`, the absent-DoD ✅ is at `:2286-2288`, and "exhaustively" is defined as git facts at `commands/are-we-done.md:52-57, 70-72`.
- `Scope (grown)` has no cause field: `hooks/dod-persist.sh:88-96`.
- completion-assert D4 ("the answer is always yes"): `hooks/completion-assert.sh:1278`.
- Follow-On Gate F1: `CLAUDE.global.md:616-617`.
- The superlative ban: `skills/ground-up/SKILL.md:14-18, 88-91`.
- `docs/plans/GROUND_UP_DISPATCH.md:414`.
- reso `docs/plans/FLOOR_PLAN.md:63-66` and `sevenrooms-bridge/docs/plans/SEVENROOMS_MIRROR.md:353` quote as cited.

**Confirmed in the external reports:**
- The worked example (47 → 56.0 / 54.2 / 57.5 / 62.0; +3.1 / 7.6 / 18.0 / 33.8 panels) at `unseen-estimation.md:248-268`.
- Simulation rows G (169) and I (499) at `:309-318`.
- The n ≥ 0.95N impossibility at `stopping-rules.md:75`.
- FlipFlop 46% at `llm-failure-modes.md:128`.
- The workflow-authoring skill's "loop-until-dry" ("until K consecutive rounds return nothing new") and "completeness critic" ("What it finds becomes the next round of work"), read verbatim from the loaded skill.

**Confirmed in the ledger.** Every HPC corpus id was printed from `taxonomy_holes.py` and sits in the class its row claims (the one loose fit is noted under §2.1). `python3 /tmp/rescomp/taxonomy_stats.py`, run for this re-check, prints: 200 holes, ids 1..200 contiguous; C1–C11 = 23/12/29/32/29/12/10/8/30/8/7; DC 95; desk 129; DC-and-desk 70; C3–C8 120 (60.0%). All match `taxonomy.md:26-37` and the figures this file uses.

**Changed by this re-check:**
1. Taxonomy line references moved when the taxonomy was rewritten (`:302` → `:303`, `:320` → `:343`).
2. `reask_scan.py` is gone; the pattern source is now `internal/ca_scan.py:6`.
3. The CLI inventory was wrong as written: bare-name lookups fail in a Workflow agent's PATH, codex is authenticated, and gemini's token is unverified (§3.3).
4. The frontier gate covers only Agent-tool spawns. The design now bounds Fable slots itself (§8.3).
5. The "no wrap-ledger change" route needs attributed, flip-in-place boxes. A direct `fcr status` reader is now the recommended route (§5.1).
6. Integrated from the two new external reports: P11–P14, the evidence-source register, the frame-size rule, closure instruments, carried sets, the TBD/TBR ledger, the open-problem-report (OPR) class mapping, change control with a presumption against change and a descope path, and budget rules 5–6.
7. The F0.5 note said "The 23 forensic C4 holes". C4 has 32 holes, and the cited pattern (`shard-7.md:159`) names four unstated premises, not a count, so the note was rewritten.
8. A whole-file consistency read after the last edit (the design's own C7 rule) added the new states to the enums they belong to (`set_elimination` in `holes.jsonl`, `certified_at_accepted_bound` in `verdicts.jsonl`, `carried` in F2's sub-gate), updated the HPC row count in §10, and made the sample certificate state achieved values against targets.
